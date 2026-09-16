# KMS_RUNTIME_CREDENTIALS — E2 runtime credential provider (sts:AssumeRole) for the KMS signer

**Status:** IMPLEMENTED IN THE REPOSITORY, LOCALLY TESTED, DARK. **Not deployed. Not adopted.**
O1 production adoption, AWS access-key creation, Supabase secrets, deployment, and billing changes remain **unapproved** (owner decisions —
`docs/release/PHASE2_PFA18C_BOOTSTRAP_READINESS_REPORT.md` §7/§10). Nothing in this document creates an AWS resource or a secret.

Sources: `supabase/functions/credential-sign/kms-taxonomy.ts` (pure provider + signer core), `supabase/functions/credential-sign/kms.ts`
(SigV4 transports + factory), `supabase/functions/credential-sign/index.ts` and `supabase/functions/door-manifest/index.ts` (consumers),
`tests/credential-sign-sts-provider.test.ts` (mocked-network suite). Companion: `KMSADAPTER.md` (§11 item 2 is closed by this document).

---

## 1. Contract (both signing consumers)

```
                    ┌──────────────────────── kms-taxonomy.ts (PURE, unit-tested) ────────────────────────┐
env (Deno.env) ──►  parseAssumeRoleConfig ──► AssumeRoleCredentialProvider ──► AwsKmsSignerCore ──► derToRaw ──► index.ts §9 sign-after-verify
                    resolveAwsCredentials      (cache · single-flight ·         (temporary-only gate ·
                    (BASE key pair)            early refresh · timeout ·        key scope · bounded Sign ·
                                               retry · redaction)               response validation)
                                                     │                                 │
                                          StsTransport (kms.ts)               KmsTransport (kms.ts)
                                          SigV4 w/ BASE creds → sts.<region>  SigV4 w/ TEMP creds → kms.<region>
```

- `AwsCredentialProvider { getCredentials(): Promise<AwsTemporaryCredentials> }` is **the** contract. `credential-sign` and `door-manifest`
  both obtain their signer from `kms.ts`'s `selectKmsSignerFromEnv()` at module scope; the provider (and its cache) is therefore **one per
  runtime isolate per edge**. There is no second wiring path.
- **Separation:** the BASE credentials (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`, the runtime IAM *user*) authenticate exactly one request —
  `sts:AssumeRole`. `AwsKmsSignerCore.assertTemporaryCredentialsUsable` refuses to call KMS with anything that is not an `ASIA…` access key
  with a session token and a future `expiresAtMs`. A provider failure propagates; **there is no fallback to signing with the base user.**
  (Tests: "NO base-credential fallback" ×2.)
- DARK default preserved: `KMS_PROVIDER` unset/anything but `aws` ⇒ `UnconfiguredKmsSigner` (always `kms_provider_unconfigured`, PERMANENT).
  `KMS_PROVIDER=aws` without the full env + base credentials ⇒ PERMANENT before any network call.

## 2. Configuration (all validated; PERMANENT `aws_sts_config_invalid:<field>` names the field only)

| Env | Meaning | Validation |
|---|---|---|
| `KMS_PROVIDER` | `aws` selects the AWS signer | exact match |
| `AWS_REGION` (or `KMS_REGION`) | the ONE region; STS and KMS hosts are derived from it | `^[a-z]{2}(-[a-z]+)+-\d$` |
| `KMS_SIGNER_ROLE_ARN` | the runtime **role** to assume | `arn:aws:iam::<12 digits>:role/<path/>name` |
| `KMS_SIGNER_EXTERNAL_ID` | `sts:ExternalId` the role's trust policy requires | 2–1224 chars of `[\w+=,.@:/-]` |
| `KMS_SIGNER_SESSION_NAME` | `RoleSessionName` (default `snatchit-kms-signer`) — appears in CloudTrail | 2–64 chars of `[\w+=,.@-]` |
| `KMS_SIGNER_DURATION_SECONDS` | role session length (default 3600) | 900–3600 |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | **BASE** credentials of the runtime IAM user — STS only | presence |

**Endpoints:** `sts.<region>.amazonaws.com` and `kms.<region>.amazonaws.com`, derived from the validated region. **No env var can set an
endpoint** (`AWS_ENDPOINT_URL*`, `STS_ENDPOINT`, … are ignored — tested). The test suite injects transports, never endpoints.

## 3. What is validated on the STS response

`parseAssumeRoleResponse` (strict tag extraction, not a general XML parser): `AssumedRoleUser.Arn` must **equal**
`arn:aws:sts::<role account>:assumed-role/<role name>/<session name>` (else SECURITY `aws_sts_identity_mismatch`); `AccessKeyId` must be
`ASIA…` (else SECURITY `aws_sts_credentials_not_temporary`); `SecretAccessKey`/`SessionToken` present and plausibly sized; `Expiration`
parseable, ≥ 60 s ahead, ≤ 12 h + 5 min ahead (else PERMANENT `aws_sts_expiration_invalid`). Missing tags ⇒ PERMANENT
`aws_sts_response_malformed:<tag>`.

## 4. Cache, refresh, concurrency

- Cache key = `region | role ARN | ExternalId | session name | duration | base ACCESS KEY ID` (identifiers only, in memory only). Any change
  invalidates the cache — including a rotated base key.
- Refresh starts `refreshAheadMs` (5 min) before `Expiration`; concurrent callers await ONE in-flight refresh; a refresh that fails while
  the cached credential still has ≥ `minValidityMs` (30 s) left serves the cached credential; **a credential past (or within 30 s of)
  expiry is never returned** — the failure propagates.
- Per-attempt timeout 5 s (AbortSignal forwarded to `fetch`); up to 3 attempts with 200/600 ms backoff for TRANSIENT failures only
  (timeout, transport error, HTTP 429/5xx, `Throttling`/`RequestLimitExceeded`/`ServiceUnavailable`/…). PERMANENT failures (`AccessDenied`,
  `InvalidClientTokenId`, `SignatureDoesNotMatch`, `ExpiredToken` on the base key, `MalformedPolicyDocument`, `RegionDisabled`, config)
  are thrown on the first attempt and are **operator** conditions. KMS `Sign`: 5 s timeout, 2 attempts, 200 ms backoff, same split.

## 5. Redaction

Thrown `KmsSignError` messages carry an identifier only: `aws_sts_http_<status>:<Code>` / `kms_http_<status>:<__type>` where the code is
**allowlisted** (known AWS STS/KMS identifiers; anything else — including a well-formed but unknown token that could encode an account id or
key id — is surfaced as `unknown`), `aws_sts_timeout`, `aws_sts_transport_unavailable`, `aws_sts_identity_mismatch`,
`kms_response_algorithm_mismatch`, `kms_response_key_mismatch`, `kms_response_missing_signature` (stable, no echoed value), … Never: a
credential, session token, `Authorization` header, request body, ExternalId, echoed KeyId/algorithm, or raw STS/KMS response text.
Regression suite: `tests/credential-sign-error-redaction.test.ts` (sentinel ARNs/accounts/principals/tokens checked in `message`, `String()`,
`stack`, `JSON.stringify`, and Sentry/console-style payloads). The KMS error path was tightened as part of this change
(the previous message embedded up to 200 chars of the KMS body, which restates the key ARN and principal). The redaction test searches every
failure path for sentinels planted in credentials, ExternalId, and bodies.

## 6. SDK evaluation (requirement 7) — decision: keep the reviewed SigV4 transport, add no dependency

| | `@aws-sdk/client-sts` (+ `client-kms`) via `npm:` in Deno | existing hand-rolled SigV4 (`kms.ts`) + strict STS tag extraction |
|---|---|---|
| Maintenance | AWS-maintained SigV4, XML/JSON codecs, retry/backoff, endpoint resolution | ~100 lines SigV4 already reviewed for `kms:Sign`; +30 lines strict tag extraction; retry/timeout ~60 lines, all unit-tested |
| Runtime fit | Works under Supabase Edge (`npm:` specifiers supported) but pulls a large dependency graph (smithy core, codecs, credential-provider chain) into a cold-start-sensitive isolate; edge bundle size grows materially | zero dependencies; nothing new in the isolate |
| Behavioural surface | the SDK's *default credential chain* would silently look for env/profile/IMDS credentials and could route a request to an endpoint from `AWS_ENDPOINT_URL_STS` — exactly the "arbitrary endpoint / accidental base-credential use" surface requirement 2–3 forbid; would need to be pinned off explicitly | endpoint derived from region only; base credentials reachable only by the STS call; temporary-only gate before KMS |
| Auditability | large third-party code path between our bytes and the signature | every decision is in `kms-taxonomy.ts` and tested against mocked transports |
| Verdict | **not adopted now**; revisit only if the repo adopts the SDK for KMS as well, with the credential chain and endpoint resolution explicitly disabled | **adopted** |

The evaluation is documentary (dependency graph, default-chain and endpoint-override behaviour from the SDK's documented design), not a
benchmark; no package was installed.

## 7. Operational requirements (proposal for O1 — owner-unapproved)

1. **Principals** (`docs/release/pfa18c_artifacts/`): IAM user `snatchit-credential-sign-runtime` (no console; ONE access key; policy = `sts:AssumeRole`
   on the runtime role only, all `kms:*` denied) → role `SnatchIt-CredentialSign-Runtime` (trust: that user + `sts:ExternalId`; permissions =
   `kms:Sign` on the exact key ARN with `kms:SigningAlgorithm=ECDSA_SHA_256`, `kms:MessageType=RAW`). Key policy v2 grants Sign to the role only.
2. **Secrets placement** (founder-run, never through chat): `supabase secrets set AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY KMS_SIGNER_ROLE_ARN
   KMS_SIGNER_EXTERNAL_ID AWS_REGION` for the two signing functions; `KMS_PROVIDER=aws` only at the separately authorized dark-deploy train.
   The ExternalId is generated locally (≥ 32 random chars), stored only in the role trust policy and Supabase secrets.
3. **ExternalId is a trust CONDITION, not credential protection.** It stops a *confused-deputy* assumption of the role by another principal that
   the trust policy might otherwise admit; it does nothing if the base access key leaks, because the leaked key is used together with the
   same ExternalId from the same secret store. Protection of the base credentials rests on: Supabase secret storage access control, the base
   user's policy (`sts:AssumeRole` only, no KMS, no IAM), the key policy pinning Sign to the role, CloudTrail (M1) on `AssumeRole`/`Sign`, and
   rotation below.
4. **Rotation (base access key), every 90 days or on suspicion:** create key #2 for the runtime user → `supabase secrets set` the new pair →
   verify in CloudTrail that `AssumeRole` calls now carry the new key id (the provider's cache key includes the access key id, so new isolates
   pick it up on the next refresh; existing isolates at most one session length later) → deactivate key #1 → after one full session length
   with zero `AssumeRole` calls on key #1, delete it. Two keys active for at most one rotation window. `ExternalId` rotation: update the trust
   policy AND the secret in one change window; the provider re-reads config every call, so the next refresh uses the new value.
5. **Compromise response** (in this order; each step is founder-executed under PFA-18B/§13 of the ceremony runbook):
   a. Stop issuance: `feature.native_issuance_enabled=false` (if ever true) — in-band, one platform_admin.
   b. Revoke the base key: `aws iam update-access-key --status Inactive` then delete; rotate ExternalId; remove the runtime user from the
      role trust policy if the role itself is suspect.
   c. Cut Sign at the key: `PutKeyPolicy` removing the runtime role's Sign (or `DisableKey` for the emergency path) — the role's sessions
      (≤ 1 h) cannot sign once the key policy no longer grants it, regardless of cached credentials.
   d. Revoke the signing key in the DB if forged credentials are possible: PFA-18B `kernel.revoke_signing_key` (force-closes manifests).
   e. Evidence: CloudTrail `AssumeRole` (session name, source IP) and `Sign` events for the window, from Device 2 under M1.
6. **Detection:** alarm on `AssumeRole` for the runtime role by any principal other than the runtime user, on any `kms:Sign` by a non-runtime
   principal, and on `AssumeRole` from source IPs/ASNs inconsistent with Supabase egress (advisory only — Supabase egress is not fixed).

## 8. Residuals and gaps (honest)

- O1 still stores one long-lived AWS secret in Supabase. That is a property of Supabase Edge (documented capability: static secrets), not of
  this code. O4 (signer on AWS compute with an ambient role) is the zero-static-secret alternative and remains an owner decision before T3.
- `kms.ts`'s SigV4 transports are Deno-only and are exercised by construction and by `deno check` — **`deno check` was not available on the
  engineering host; that validation is OUTSTANDING (CI/deploy time), not passed.**
- The KMS response `KeyId` echo check (`validateAwsSignResponse`) still accepts a bare id or alias tail; the new `assertKmsHandleInScope`
  requires the *request* handle to be a full key ARN in the configured region/account, which closes the scope gap at the request side.
- Clock skew: STS `Expiration` is compared with the isolate clock; a skew > 60 s toward the future would make fresh credentials look
  "already expiring" and refresh every call (safe, noisy), a skew toward the past would extend apparent validity by the skew (bounded by
  `minValidityMs`; KMS rejects genuinely expired tokens anyway).

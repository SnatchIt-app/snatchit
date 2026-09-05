# PHASE 2 — PFA-18C BOOTSTRAP READINESS REPORT

**Date:** 2026-09-05 · **Session:** backend continuation — AWS baseline reconciliation + bootstrap implementation readiness
**Scope:** design + evidence only. **No AWS mutation, no production-DB mutation, no KMS key, no deploy, no flag, no billing change, no migration 110.** C18 preserved.

```
REPO:                 /Users/josetascon/snatchit-consol · branch feature/venue-native-and-product-v2 · HEAD b607389
PR:                   #52 OPEN (base phase2/consolidation, MERGEABLE, head = b607389)
PRE-EXISTING UNCOMMITTED WORK (preserved, untouched):
                      M  docs/release/PHASE2_PRODUCTION_KMS_SIGNING_CEREMONY_EXECUTION.md   (prior coordinator session)
                      ?? docs/phase2/TICKETS_READ_CONTRACT_CORE_COORDINATION.md              (prior tickets session)
PRODUCTION (fresh, read-only, 2026-09-05 20:17:23Z):
                      ledger 124 · 093+109 present · numeric tip 109 · signing_key 0 · expected_fingerprint null ·
                      monitor false · native_issuance false · native_scanning false · tickets/pins/sessions/scans/manifests 0 ·
                      native edges NOT deployed  →  UNCHANGED vs recorded baseline; no repair performed
M4:                   PASS (canonical §6.1 L428–536 writes algorithm='ES256' explicitly; PRE-FLIGHT 2b; POST-CHECK)
BOOTSTRAP VERDICT:    NOT READY — 1 conditional P0 + 2 P1 + 4 owner decisions before Phase-1 mutations begin
```

Execution record (continuously maintained): `docs/release/PHASE2_PFA18C_SINGLE_FOUNDER_KMS_BOOTSTRAP_EXECUTION.md`
Reviewable artifacts (NOT applied): `docs/release/pfa18c_artifacts/` (10 policy/config JSON files + README)

---

## 1. Evidence classes used in this report

| Class | Meaning | Used for |
|---|---|---|
| **OWNER-RETURNED** | typed by the founder from the primary machine; not independently observed by Claude (C18: Claude has no AWS access) | the entire AWS baseline (§2) |
| **CLAUDE-OBSERVED** | read-only query/inspection performed by Claude this session | production precheck, repo/M4, code facts, official-docs facts |
| **PLANNED** | designed here, not yet applied, therefore **not PASS** | every M1/M2/M3 control |

No planned control is marked PASS anywhere in this report. No owner ratification is invented.

## 2. AWS baseline (OWNER-RETURNED, 2026-09-05)

Account `652872010073` · principal `arn:aws:iam::652872010073:user/jose-admin` (IAM user, `AIDAZQARUJFMXKFV5U5JY`) · auth `aws login` (temporary
credentials, no long-lived keys) · CLI 2.36.40 · profile `snatchit-admin` · saved region `us-east-1`, env unset · Organizations **not in use** ·
CloudTrail `[]` · S3 `[]` · IAM users `jose-admin` only (AdministratorAccess via group `SnatchIt-admins`; passkey MFA registered; **fresh MFA
sign-in test deferred**) · IAM roles: 3 service-linked only · root: MFA used, **0 access keys** · long-lived keys created: **none** ·
billing: owner prefers Free plan, **no upgrade authorized**, plan type **not proven**.

Assessment (CLAUDE-OBSERVED reasoning over owner-returned facts):
- §4 root safety **PASS** (IAM user, not root). `jose-admin` is the **setup administrator**; it is **not** a compliant ceremony principal (it is unbounded
  AdministratorAccess and therefore cannot satisfy the M1 deny-set). A dedicated ceremony role is required (§5).
- §5 region: `us-east-1` is the only signal; nothing is frozen in the repo/architecture → **OWNER CONFIRMATION required** to pin.
- M1/M2/M3: **nothing exists to reuse.** Every control must be created. Zero risk of duplicate infrastructure.
- Open item: the MFA fresh-sign-in test is deferred; the ceremony role's trust policy requires `aws:MultiFactorAuthPresent=true`, so the first
  `assume-role` attempt doubles as that test (Stage M1-4 below).

## 3. Findings this session

### P0-FREEPLAN (CONDITIONAL — blocks CreateKey until resolved)
Official AWS Free Tier documentation (CLAUDE-OBSERVED, 2026-09-05):
- "Your free account plan ends after six months or when your credits are fully used - whichever occurs first." (docs: awsaccountbilling …/free-tier.html)
- "The account closes on its own 6 months after you open it or when your credits run out, whichever comes first." (aws.amazon.com/free)
- "AWS will retain your data for 90 days after your free plan expires … If you don't upgrade your account within 90 days, AWS will permanently
  erase your AWS account and all its content." (Free Tier FAQ)
- "free account plans don't have access to certain AWS services" — the official pages do **not** enumerate them; S3 is confirmed available on both
  plans; KMS/CloudTrail/IAM availability is **not stated**.
- S3 Object Lock, COMPLIANCE mode: "The only way to delete an object under the compliance mode before its retention date expires is to delete the
  associated AWS account." (S3 user guide)

Consequence: a production trust root (KMS key) and compliance-locked audit evidence must not be created in an account that can auto-close.
**CreateKey is NO-GO until (a) the plan type is proven `PAID`, or (b) the owner explicitly authorizes the upgrade** (upgrade converts the account;
remaining credits still apply for 12 months from creation). Read-only proof: `aws freetier get-account-plan-state` (returns `accountPlanType`
FREE|PAID, `accountPlanStatus`, `accountPlanExpirationDate`, remaining credits). If the account predates 2025-07-15 it is on the legacy program
and this finding does not apply — the same command shows that.

Cost model once on a paid plan (official pricing pages): KMS key **$1/month prorated hourly**; asymmetric `Sign` **$0.15 per 10,000 requests, excluded
from the KMS free tier**; CloudTrail **first copy of management events to S3 free**; S3 storage for CloudTrail logs: cents/month. Total ≈ **$1–2/month**
before any issuance volume. No hardware/commitment beyond the Object-Lock retention (which is a *data* commitment, not a spend commitment).

### P1-PUBKEY-FORMAT (pre-issuance blocker; strongly recommended pre-bootstrap)
- Runbook D3 + the canonical §6.1 artifact store `kernel.signing_key.public_key` as an **SPKI PEM block** (`-----BEGIN PUBLIC KEY-----`); PRE-FLIGHT 2
  even *requires* the armor; G3 rehearsal verified against the PEM read back from the DB.
- `kernel.get_ticket_signing_context` (103:189) returns that column verbatim.
- `credential-sign/index.ts:309–320` (`verifyWithWebCrypto`) does `atob(publicKeyB64)` and documents the input as "standard base64 SPKI DER".
  `atob` on PEM armor throws `InvalidCharacterError` (demonstrated locally, Node 24: `atob(PEM)` throws; `atob(stripped)` decodes). The catch returns
  `false` → sign-after-verify fails → **every credential is refused (`kms_sign_verify_failed`)** — fail-closed, but a silent permanent brick because
  `public_key` is immutable (`guard_signing_key_immutable`). The vitest suites pass because their fixtures are bare base64 DER.
- Door side: `_shared/offline-verify.ts:373` delegates to an injected `ctx.verify(m1Entry.public_key, …)`; the production door primitive is in
  the mobile app (not in this repo) — its convention is **unverified**.
- Fix (recommended): keep D3 = PEM in the DB (artifact, fingerprint gate, rehearsal all depend on it) and make **every verify primitive
  armor-tolerant**: a pure `normalizeSpkiBase64()` in `credential.ts` (strip `-----BEGIN/END PUBLIC KEY-----` + whitespace; accept bare base64
  unchanged), used by `credential-sign` and by the door verifier; plus vitest cases with PEM-shaped fixtures. Alternative (rejected): change the
  artifact to store bare base64 — breaks PRE-FLIGHT 2's armor check and the G3-rehearsed verification path.
- **NOT implemented this session** (no production-bearing code changed). Acceptance criteria in §9.

### P1-RUNTIME-CREDS (M3 design gap — resolved on paper in §7, engineering + owner decision required)

### OBS-1 — AWS KMS now offers `ECC_NIST_EDWARDS25519` (official key-spec reference). The repo premise "AWS KMS offers NO Ed25519" is outdated.
The **ratified D2 = ES256 stands**; `AwsKmsSigner` is ES256-only; the §6.1 artifact gates ES256. Recorded so nobody reopens D2 mid-ceremony.

### OBS-2 — CloudTrail classifies KMS `Sign` / `GetPublicKey` as **Read** management events; `Disable/Delete/ScheduleKey` as Write. The M1 trail must
log **Read + Write** (`ReadWriteType: All`) and must **not** exclude `kms.amazonaws.com`; Device 2 read-back = `get-event-selectors` shows no
`ExcludeManagementEventSources` / no `eventSource NotEquals kms.amazonaws.com`.

### OBS-3 — `door-manifest` also calls `kmsSigner.sign` (index.ts:343). The M3 runtime role serves **two** edges (credential-sign, door-manifest).
Neither needs `kms:GetPublicKey` at runtime (the public key comes from the DB row / manifest) → runtime = `kms:Sign` only.

## 4. M4 — CONFIRMED PRESENT (canonical artifact)
`docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md` §6.1: L428 `-v ALGORITHM="ES256"` (explicit, never the column default); L476–493 PRE-FLIGHT 2b
(empty/unsanctioned/≠ES256 aborts); L511–515 `insert … algorithm … i.algorithm`; L531/536 POST-CHECK pins `k.algorithm`. Unchanged since the
2026-09-04 off-production proof.

## 5. M1 — audit plane, Model B (PLANNED; concrete design)

| Element | Design | Artifact |
|---|---|---|
| Trail | `snatchit-audit-trail`, **multi-region**, log-file validation **ON**, management events **Read+Write**, KMS events **included**, no Insights/data events (cost) | — |
| Bucket | `snatchit-audit-652872010073` (globally unique; account id in name), `us-east-1` (omit `--create-bucket-configuration` for us-east-1), **Object Lock enabled at creation** (`--object-lock-enabled-for-bucket`; versioning auto), Block Public Access ALL, TLS-only | `m1_audit_bucket_policy.json` |
| Object Lock | **COMPLIANCE** default retention, `Years = <OWNER DECISION>` | `m1_object_lock_configuration.json` |
| Encryption | **SSE-S3 (AES256)** — satisfies the ratified "SSE-S3 or a CMK the ceremony principal cannot administer". A log CMK would add a second key whose policy/deletion becomes a new attack surface for no gain; **not introduced** | — |
| Ceremony identity | new IAM role **`SnatchIt-KMS-Ceremony`**, assumed by `jose-admin` **only with MFA** and fixed session name `pfa18c-ceremony`, max session 1 h. All ceremony AWS calls run as this role session | `m1_ceremony_role_trust.json`, `m1_ceremony_role_policy.json` |
| Deny-set (ceremony role) | CloudTrail Stop/Delete/Update/PutEventSelectors/RemoveTags (+Create/AddTags); S3 delete/policy/lifecycle/versioning/retention/legal-hold/bypass/encryption/replication/object-lock-config/public-access on the audit bucket; `iam:*`, all `sts:AssumeRole*`, `organizations:*`, `account:*`; KMS lifecycle (ScheduleKeyDeletion, DisableKey, aliases, grants, replication, import, all non-Sign crypto ops) | `m1_ceremony_role_policy.json` |
| Allow-set (ceremony role) | `kms:CreateKey` **only** with `KeySpec=ECC_NIST_P256 ∧ KeyUsage=SIGN_VERIFY ∧ KeyOrigin=AWS_KMS ∧ MultiRegion=false ∧ BypassPolicyLockoutSafetyCheck=false`; Describe/GetPublicKey/GetKeyPolicy/PutKeyPolicy/Sign only on keys tagged `snatchit:purpose=ticket-signing`; read-only CloudTrail/S3 inspection | same |
| Anti-escalation | the role session cannot widen itself (iam/sts denied). **Residual (disclosed, P3-REGRANT):** `jose-admin` outside the session keeps AdministratorAccess; root exists. Both are DETECTABLE only → Device 2 must confirm **zero `jose-admin`/root management events inside the ceremony window** | — |
| Root / break-glass boundary | root: MFA, 0 keys, **never used** in the ceremony; `jose-admin`: setup + emergency (PFA-18B KMS `DisableKey` path) only, never the ceremony session | — |
| Second-device verification (M1 read-back) | from Device 2: `describe-trails` (multi-region, validation), `get-trail-status` (IsLogging), `get-event-selectors` (All, no KMS exclusion), `get-bucket-object-lock-configuration` (COMPLIANCE + Years), `get-bucket-versioning`, `get-bucket-encryption` (AES256), `get-bucket-policy`, `get-public-access-block`, `iam get-role`/`get-role-policy` for the ceremony role (diff against the artifact), `lookup-events` for the window | `m2_verifier_policy.json` |

**Retention — OWNER DECISION (not frozen anywhere; PFA-18C forbids inventing it).** Compliance retention can be **extended** later, never shortened,
and objects cannot be deleted by anyone (root included) until it lapses. Options: **1 year** (least irrevocable; bootstrap evidence would become
deletable after a year unless extended), **3 years** (covers bootstrap→commerce and a typical audit horizon; recommended by engineering),
**7 years** (financial-records horizon; heaviest commitment in an account that may later be restructured under Model A). Storage cost is
negligible in every case. Model A (separate audit account, required before T3) becomes the durable plane regardless.

## 6. M2 — second clean device + read-only identity (PLANNED)

- **Device 2** = a physically different machine (or, minimum, a different OS user session that shares no shell, files, `~/.aws`, browser profile, or
  clipboard with the ceremony host). AWS CloudShell opened from a browser on a *different physical device* is acceptable as a fallback (it shares
  nothing with the ceremony host's filesystem) but adds the same-account residual already accepted under Model B.
- **Identity** = IAM user **`snatchit-kms-verifier`**: console password + MFA, AWS-managed `SignInLocalDevelopmentAccess` (required for `aws login`),
  the read-only inline policy `m2_verifier_policy.json`. Authentication on Device 2 = `aws login --profile verifier` → temporary credentials,
  auto-refreshed, session ≤ 12 h; **no long-lived access key** is ever created for it.
- **KMS scope** = `GetPublicKey`, `DescribeKey`, `GetKeyPolicy` (the ratified M2 minimum). **No `kms:Sign`, no `kms:Verify`, no admin** — explicitly
  denied. The §5.3 "wrong key FAILS" check is done locally with a throwaway keypair; "altered message FAILS" is a local openssl verify. The Sign for
  the binding proof is made by the ceremony role; Device 2 only verifies.
- Initially `key/*` read scope in-region (read-only, harmless); optionally tightened to the exact ARN post-CreateKey (an extra founder mutation —
  not required).
- **Attestation (Stage M2-3)**: `sts get-caller-identity` (Account, Arn = verifier user), `configure get region`, a successful read
  (`cloudtrail get-trail-status`), and a *denied* mutation probe that is safe to attempt (`kms create-alias` on a non-existent key → expect
  AccessDenied, not NotFound), plus the full M1 read-back. Nothing is mutated from Device 2, ever.

## 7. M3 — runtime signer identity and credential lifecycle (design resolved; engineering + owner decision open)

**Facts (CLAUDE-OBSERVED):** Supabase Edge Functions receive **only static secrets** (`supabase secrets set` / dashboard → `Deno.env`); Supabase docs
describe **no AWS role, OIDC federation, or instance-metadata credential source** for functions. `kms.ts` "does NOT itself call `sts:AssumeRole`"
and reads `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SESSION_TOKEN` from env (`kms-taxonomy.ts:125–133`); `KMS_SIGNER_ROLE_ARN` is only a
name. Manually pasted expiring credentials are **not** a production mechanism (they die within hours). So *something* durable must sit in Supabase
secrets — the only question is what, and how narrow.

| Option | Mechanism | Static secret in Supabase? | PFA-18C "distinct runtime **role**" | Engineering | Verdict |
|---|---|---|---|---|---|
| **O1 (recommended)** | IAM user `snatchit-credential-sign-runtime` (may ONLY `sts:AssumeRole` → role `SnatchIt-CredentialSign-Runtime`, ExternalId) → role has `kms:Sign` on the exact ARN | yes: the user's access key (blast radius = ability to obtain Sign sessions; no IAM, no other keys, no Decrypt) | literal ✔ | `kms.ts`: STS `AssumeRole` via the existing SigV4 helper, in-isolate credential cache, refresh ≥5 min before `Expiration`, fail closed | **adopt** |
| O2 | IAM user with direct `kms:Sign` | yes (same blast radius) | ✘ (user, not role) — would need a PFA wording amendment | none | rejected: no security gain over O1, governance cost |
| O3 | IAM Roles Anywhere (X.509 trust anchor; runtime holds a private cert) | yes (the cert's private key) | ✔ | heavy: custom `CreateSession` signing in Deno; no official helper for edge runtimes | not now |
| O4 | move the signer edge to AWS compute (Lambda) with an ambient role | **no** | ✔ | architecture change (edge → Lambda + call path + PFA-PT review) | the only zero-static-secret design; **owner decision if wanted before commerce** |

**O1 lifecycle, concretely:** (1) founder creates the runtime user + role from the artifacts, generates the ExternalId locally, creates ONE access
key; (2) founder runs `supabase secrets set AWS_ACCESS_KEY_ID=… AWS_SECRET_ACCESS_KEY=… KMS_SIGNER_ROLE_ARN=… KMS_SIGNER_EXTERNAL_ID=… AWS_REGION=us-east-1`
(values never pass through chat; `KMS_PROVIDER=aws` is set only at the separately authorized dark-deploy train); (3) on each cold start / expiry the
edge calls `AssumeRole` (DurationSeconds 3600, `RoleSessionName=credential-sign`), caches the temporary triple in module scope, refreshes when
`Expiration − now < 5 min`, and throws `aws_kms_credentials_unavailable` (PERMANENT) on any STS failure — never signs with stale or missing creds;
(4) key policy v2 grants `kms:Sign` **only** to the runtime role (§Artifacts), so a leaked user key alone cannot sign without also assuming the role
(logged in CloudTrail with session name); (5) rotation: two-key overlap every 90 days, founder-executed, old key deleted after the swap is
verified in logs; (6) detection: CloudTrail alarm on `AssumeRole` for that role from an unexpected principal, and on any `Sign` by a non-runtime
principal (Model A makes this tamper-proof).

**Honest residual:** O1 still stores one long-lived AWS secret inside Supabase. That is inherent to Supabase Edge, not to this design; it is bounded to
Sign-only on one key and is the same class of secret as the Stripe key already stored there. If the owner wants zero static AWS secrets, O4 is the
path and should be decided before T3, not mid-ceremony.

Ordering that PFA-18C requires and this design satisfies: the runtime **role** exists before CreateKey (so key policy v1 can name it); the exact-ARN
`m3_runtime_role_policy.json` is attached **after** CreateKey and **before** the ceremony is declared complete; the ceremony role loses Sign at v2.

## 8. Official-documentation verification (CLAUDE-OBSERVED this session)

| Claim | Source | Result |
|---|---|---|
| Free plan: 6-month / credit-exhaustion closure; 90-day retention then permanent erase; upgrade path; credits expire 12 months after creation | aws.amazon.com/free · docs free-tier.html · Free Tier FAQ | **confirmed** (→ P0-FREEPLAN) |
| Free plan excluded-service list | same pages | **not enumerated** by AWS; treated as unknown |
| `aws freetier get-account-plan-state` returns `accountPlanType FREE|PAID`, status, expiration, remaining credits | AWS CLI reference | **confirmed** (read-only owner check) |
| KMS: $1/key/month prorated; asymmetric Sign $0.15/10k, excluded from free tier | aws.amazon.com/kms/pricing | **confirmed** |
| CloudTrail: first copy of management events to S3 free | aws.amazon.com/cloudtrail/pricing | **confirmed** |
| Object Lock: versioning required; enable at creation via `--object-lock-enabled-for-bucket`; COMPLIANCE cannot be shortened/removed by any user incl. root; default retention applies automatically; Days XOR Years | S3 user guide · CLI `create-bucket` / `put-object-lock-configuration` | **confirmed** |
| CloudTrail bucket policy: `cloudtrail.amazonaws.com` GetBucketAcl + PutObject with `bucket-owner-full-control` and `aws:SourceArn` | CloudTrail user guide | **confirmed** (artifact matches) |
| CloudTrail logs KMS events by default; Sign/GetPublicKey are Read events; exclusion is opt-in | CloudTrail "Logging management events" | **confirmed** (→ OBS-2) |
| `aws login`: IAM users/root/federated; temp creds auto-refreshed, ≤12 h; needs `SignInLocalDevelopmentAccess`; cached in `~/.aws/login/cache` | AWS CLI user guide | **confirmed** (basis for M2 identity) |
| KMS key policy: without an account-root statement IAM policies are ineffective and the key can become unmanageable | KMS default key policy guide | **confirmed** (→ `NotAction` design) |
| STS AssumeRole: RoleArn+RoleSessionName required; ExternalId; DurationSeconds default 3600 (900–43200); XML response with Credentials.Expiration | STS API reference | **confirmed** (→ O1 engineering spec) |
| ECC_NIST_P256 ↔ ECDSA_SHA_256; AWS KMS now lists ECC_NIST_EDWARDS25519 | KMS key-spec reference | **confirmed** (→ OBS-1) |
| Supabase Edge secrets are static env vars; no AWS identity federation documented | Supabase docs (functions/secrets) | **confirmed** (→ §7) |

## 9. Remaining engineering work — status and acceptance criteria

Status legend: **I** implemented · **T** tested · **D** deployed · **V** operationally verified. `—` = not.

| # | Item | I | T | D | V | Acceptance criteria |
|---|---|---|---|---|---|---|
| E1 | **P1-PUBKEY-FORMAT** normalization | — | — | — | — | pure `normalizeSpkiBase64()` in `credential.ts` (PEM armor + whitespace stripped; bare base64 unchanged; garbage → verify false); used by `credential-sign` `verifyWithWebCrypto` and documented as the door convention; vitest: PEM-fixture verify PASS, altered PASS→FAIL, EdDSA+ES256; vitest total ≥ 669+new; `npm run typecheck`/`lint` green; no migration |
| E2 | **M3 runtime credential provider** (O1) | — | — | — | — | `kms-taxonomy.ts`: pure STS-XML parser + expiry/refresh decision (unit-tested); `kms.ts`: `AssumeRole` over existing SigV4 (`service=sts`, query API), cache per isolate, refresh at `Expiration−5min`, all failures → `KmsSignError('aws_kms_credentials_unavailable','permanent')`; env contract `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`KMS_SIGNER_ROLE_ARN`/`KMS_SIGNER_EXTERNAL_ID`/`AWS_REGION`; `UnconfiguredKmsSigner` default unchanged; DARK (no deploy); KMSADAPTER.md §11 item 2 closed |
| E3 | **M6 — migration 110** BEFORE INSERT guard on `kernel.signing_key` | — | — | — | — | trigger `tg_signing_key_insert_guard`: reject `scope <> 'global'` (scoped keys stay parked until a PFA un-parks them); reject `algorithm = 'EdDSA'` unless session GUC `snatchit.ceremony_algorithm_override='EdDSA'` is set (blocks the 103 default surviving any future artifact); reject `kms_handle_ref` not matching `^arn:aws:kms:[a-z0-9-]+:\d{12}:key/[0-9a-f-]{36}$` when `algorithm='ES256'`; reject PEM containing `PRIVATE KEY`; pgTAP suite 176 (≥8 negatives + 1 positive); rehearsal reset+test green; G-4 integrity; Gate-2 census bumped; rollback file; NOT applied to production without authorization; **required before issuance, not before bootstrap** |
| E4 | **Gated two-person post-revoke re-bootstrap artifact** | — | — | — | — | SQL artifact: PRE-FLIGHT exactly one `revoked` global + zero `active`; two distinct `platform_admin`+aal2 command keys recorded in `kernel.ceremony_approval` (new table, migration) within a 15-min window, else `dual_control_unavailable`; sets `algorithm` explicitly; fingerprint gate as §6.1; classified TWO-PERSON-MANDATORY post-T3; pgTAP negatives (single approver, expired window, active key present) |
| E5 | **M5 end-to-end credential-sign test** | — | — | — | — | after E1+E2 and a separately authorized **dark** deploy of `credential-sign` with `KMS_PROVIDER=aws`: one throwaway atom on a non-saleable test event; edge returns a token; sign-after-verify PASS; CloudTrail shows exactly one `Sign` by the runtime role; `feature.native_issuance_enabled` stays false throughout; recorded in the execution record |
| E6 | **Model A audit isolation** (before T3) | — | — | — | — | AWS Organizations enabled; separate audit member account; organization trail → Object-Lock bucket in the audit account; SCP on the workload account denying `cloudtrail:Stop*/Delete*/Update*` and audit-bucket mutation to *everyone including admins*; Device-2 read-back from the audit account; PFA-18C residual formally closed |
| E7 | Gate-C owner/config blockers (unchanged) | n/a | n/a | n/a | — | LEGAL/TAX posture (PFA-PT-7) affirmed; `fee.buyer_service_bps` owner-set; `deletion.post_event_hold_hours` owner-set; venue Connect onboarding with transfers capability; dark deploy of native edges (separate authorization); issuance/scanning flag flips (separate authorization). See `FINAL_OWNER_SIGNATURE_AND_PRODUCTION_PREFLIGHT.md` Gate C |

Already in place (I/T, dark, not D/V): `AwsKmsSigner` ES256 transport + taxonomy (vitest 56/56 in `credential-sign-kms.test.ts`), sign-after-verify,
`check_signing_key_invariants` + monitor cron (099), `get_ticket_signing_context` algorithm pinning (103), §6.1 M4-corrected artifact (rehearsal-proven),
PFA-18B revoke + force-close (106/109), door PIN KDF + machine authority (107/108).

## 10. Blockers and the next smallest owner action

**Blocking Phase-1 mutations (in order):**
1. **P0-FREEPLAN** — prove plan type. If FREE: CreateKey stays NO-GO until the owner authorizes the upgrade (≈ $1–2/month run-rate). M1/M2 IAM/CloudTrail/S3
   setup could proceed on a Free plan only if the owner accepts re-creating it after an upgrade; engineering recommends resolving the plan **first**.
2. **Owner decisions:** (a) pin region `us-east-1`; (b) Object-Lock retention years (1 / 3 / 7); (c) M3 = O1 now (static runtime key in Supabase) with O4
   optionally before T3; (d) confirm the naming in `pfa18c_artifacts/README.md`.
3. **E1 (P1-PUBKEY-FORMAT)** — should land before the DB bootstrap so the stored PEM is a deliberate, verified convention (hard requirement before M5).
4. **E2** — required before M5, not before bootstrap.

**Next smallest owner action (read-only, primary machine, profile `snatchit-admin`):**
```bash
aws freetier get-account-plan-state
```
Return the non-secret output (`accountPlanType`, `accountPlanStatus`, `accountPlanExpirationDate`, remaining credits). If the subcommand is missing
on CLI 2.36.40, use Billing console → *Free Tier* page and return the plan type shown. Together with that, reply with the four decisions in item 2.
Nothing is created until those are recorded in the execution record.

**Stage plan once GO (one stage per turn, founder-executed, Device labelled, STOP after each):** M1-1 bucket (Object Lock at creation) → M1-2 encryption +
public-access block + bucket policy → M1-3 Object-Lock default retention → M1-4 trail (multi-region, validation, start logging) → M1-5 ceremony role
(trust + policy) → M1-6 first `assume-role` with MFA (doubles as the deferred MFA test) → M2-1 verifier user (console+MFA+policy) → M2-2 Device-2 `aws login`
+ attestation → M2-3 full M1 read-back from Device 2 → M3-1 runtime user + role (trust; exact-ARN policy deferred) → PHASE-1 GATE → §18 owner checkpoint
→ `AUTHORIZE PFA-18C CREATEKEY`.

# PHASE 2 — PFA-18C BOOTSTRAP READINESS REPORT

**Date:** 2026-09-05 · **Sessions:** backend continuation (AWS baseline reconciliation + readiness) · **corrected + P1-PUBKEY-FORMAT fixed** (same day, later session)
**Scope:** design + evidence only. **No AWS mutation, no production-DB mutation, no KMS key, no deploy, no flag, no billing change, no migration 110.** C18 preserved.

```
REPO:                 /Users/josetascon/snatchit-consol · branch feature/venue-native-and-product-v2 · baseline b607389 → tested code commit c150283
PR:                   #52 OPEN (base phase2/consolidation, MERGEABLE, head = b607389)
PRE-EXISTING UNCOMMITTED WORK (preserved, untouched):
                      M  docs/release/PHASE2_PRODUCTION_KMS_SIGNING_CEREMONY_EXECUTION.md   (prior coordinator session)
                      ?? docs/phase2/TICKETS_READ_CONTRACT_CORE_COORDINATION.md              (prior tickets session)
PRODUCTION (fresh, read-only, 2026-09-05 20:17:23Z):
                      ledger 124 · 093+109 present · numeric tip 109 · signing_key 0 · expected_fingerprint null ·
                      monitor false · native_issuance false · native_scanning false · tickets/pins/sessions/scans/manifests 0 ·
                      native edges NOT deployed  →  UNCHANGED vs recorded baseline; no repair performed
M4:                   PASS (canonical §6.1 L428–536 writes algorithm='ES256' explicitly; PRE-FLIGHT 2b; POST-CHECK)
BOOTSTRAP VERDICT:    NOT READY — CreateKey NO-GO in account 652872010073 under the owner's KEEP-FREE-PLAN decision
                      (see P0-FREEPLAN); P1-PUBKEY-FORMAT FIXED in the repository (tests green, deploy pending);
                      M3 credential provider still to build; owner decisions listed in §10
```

Execution record (continuously maintained): `docs/release/PHASE2_PFA18C_SINGLE_FOUNDER_KMS_BOOTSTRAP_EXECUTION.md`
Code fix for P1-PUBKEY-FORMAT: see §3 and §9 (E1) — tested commit recorded in §11.
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
billing (OWNER-RETURNED, later the same day, via `aws freetier get-account-plan-state`): **accountPlanType FREE, status ACTIVE,
$100 remaining, accountPlanExpirationDate 2027-03-05T17:57:11.079Z**. **Owner decision: KEEP THE FREE PLAN. No billing upgrade is authorized.**

Assessment (CLAUDE-OBSERVED reasoning over owner-returned facts):
- §4 root safety **PASS** (IAM user, not root). `jose-admin` is the **setup administrator**; it is **not** a compliant ceremony principal (it is unbounded
  AdministratorAccess and therefore cannot satisfy the M1 deny-set). A dedicated ceremony role is required (§5).
- §5 region: `us-east-1` is the only signal; nothing is frozen in the repo/architecture → **OWNER CONFIRMATION required** to pin.
- M1/M2/M3: **nothing exists to reuse.** Every control must be created. Zero risk of duplicate infrastructure.
- Open item: the MFA fresh-sign-in test is deferred; the ceremony role's trust policy requires `aws:MultiFactorAuthPresent=true`, so the first
  `assume-role` attempt doubles as that test (Stage M1-4 below).

## 3. Findings this session

### P0-FREEPLAN — CONFIRMED (account is FREE); OWNER DECISION: keep the Free plan ⇒ CreateKey NO-GO in this account
Owner-returned plan state: `accountPlanType FREE`, `ACTIVE`, $100 remaining, expiration **2027-03-05T17:57:11.079Z**. Official AWS Free Tier
documentation (CLAUDE-OBSERVED, 2026-09-05):
- "Your free account plan ends after six months or when your credits are fully used - whichever occurs first." (docs …/free-tier.html)
- "The account closes on its own 6 months after you open it or when your credits run out, whichever comes first." (aws.amazon.com/free)
- "AWS will retain your data for 90 days after your free plan expires … If you don't upgrade your account within 90 days, AWS will permanently
  erase your AWS account and all its content." (Free Tier FAQ)
- "free account plans don't have access to certain AWS services" — the official pages do **not** enumerate them; S3 is confirmed available on both
  plans; KMS/CloudTrail/IAM availability on the Free plan is **not stated** either way.
- S3 Object Lock, COMPLIANCE mode: "The only way to delete an object under the compliance mode before its retention date expires is to delete the
  associated AWS account." (S3 user guide)

Consequence under the owner's decision (recorded, not overridden): a production KMS trust root and compliance-locked audit evidence created in
account `652872010073` have a hard horizon of **2027-03-05** (then a 90-day grace, then erasure) unless the plan is upgraded, and Object-Lock
COMPLIANCE retention would be ended by account closure rather than honoured. Engineering therefore holds **CreateKey = NO-GO in this account**
while the Free plan is kept. This does **not** block repository work (done), M1/M2/M3 *design* (done), or local tests. Paths the owner may choose
later — none is authorized or performed now: (a) authorize a paid-plan upgrade before CreateKey (≈ $1–2/month; remaining credits still apply
for 12 months from account creation, except that an upgrade performed through Organizations/Control Tower expires them immediately — FAQ);
(b) defer the ceremony until (a); (c) place the signing workload in a different, paid member account under the Model-A layout (§9 E6), which
also has to be settled before CreateKey. Note: any test infrastructure (trail/bucket/roles) built on the Free plan is subject to the same
2027-03-05 horizon.

Cost model once on a paid plan (official pricing pages): KMS key **$1/month prorated hourly**; asymmetric `Sign` **$0.15 per 10,000 requests, excluded
from the KMS free tier**; CloudTrail **first copy of management events to S3 free**; S3 storage for CloudTrail logs: cents/month. Total ≈ **$1–2/month**
before any issuance volume. No hardware/commitment beyond the Object-Lock retention (which is a *data* commitment, not a spend commitment).

### P1-PUBKEY-FORMAT — **FIXED IN THE REPOSITORY (this session); deployment pending**
- Defect: runbook D3 + the canonical §6.1 artifact store `kernel.signing_key.public_key` as an **SPKI PEM block** (PRE-FLIGHT 2 even *requires*
  the armor; G3 rehearsal verified against the PEM read back from the DB); `kernel.get_ticket_signing_context` (103:189) returns that column
  verbatim; the credential-sign edge's sign-after-verify primitive `atob()`'d it expecting bare base64 SPKI DER. `atob` on PEM armor throws
  `InvalidCharacterError` (demonstrated, Node 24); the catch returned `false` ⇒ every credential would have been refused
  (`sign_verify_failed`, fail-closed). Vitest fixtures are bare base64, which is why the suites were green.
- **Correct characterization:** this breaks verification until the *verifier code* is repaired. The stored PEM's immutability does **not**
  prevent that repair — the DB representation is correct and unchanged; the consumer was wrong. (Contrast M4/P1-ALGO, which was an
  immutable-*data* defect.) The earlier "silent permanent brick" wording was overstated and is withdrawn.
- **Fix (implemented):** `normalizeSpkiPublicKey(input, algorithm)` — pure, strict, never throws — in `credential-sign/credential.ts`, applied
  inside `verifyToken` and `verifyCanonicalSignature` (so the edge's sign-after-verify and every token verification funnel through it), and an
  identical no-imports copy exported from `_shared/offline-verify.ts`, applied before the door's injected primitive. Accepts exactly one
  `-----BEGIN PUBLIC KEY-----` block (LF/CRLF, no headers) **or** bare canonical padded base64; rejects PRIVATE KEY material, other PEM labels,
  base64url/unpadded/whitespace-laden/non-canonical base64, non-SEQUENCE DER, and — extending the PFA-PT-8 pin to the key bytes — any SPKI whose
  AlgorithmIdentifier is not the pinned algorithm's (ES256 ⇒ uncompressed P-256, 91 bytes, the form AWS KMS/openssl emit; EdDSA ⇒ Ed25519, 44
  bytes). Returns the canonical bare-base64 SPKI DER, so PEM and bare inputs verify identically. New refusal reason `malformed_public_key`
  (distinct from `signature_invalid`) in both `VerifyReason` and `OfflineVerifyReason`; the primitive is never invoked on a malformed key.
  `door-manifest` only *signs* (no local verification) — unchanged; the manifest's verifiers are door-side (below).
- **Tests (real keys, `tests/credential-sign-pubkey-format.test.ts`, 21 cases):** PEM LF/CRLF/bare accepted and canonicalized; PRIVATE KEY,
  other labels, missing END, encapsulated headers, trailing junk, base64url, unpadded/over-padded, internal whitespace, non-canonical trailing
  bits, non-alphabet chars, non-strings, truncated/extended/wrong-tag/indefinite-length DER, wrong key type per algorithm, compressed P-256
  point, P-384, unknown algorithm all refused; both copies agree on the matrix; `verifyToken` ES256 with PEM/bare PASS, wrong key / altered
  message / altered signature ⇒ `signature_invalid`, malformed ⇒ `malformed_public_key` with the primitive never called, alg pin unchanged
  (`alg_mismatch` first); EdDSA covered only within the existing verifier contract; `verifyCanonicalSignature` regression reproduced with the
  edge's exact `atob`+WebCrypto primitive shape (PEM ⇒ false before, true through the fix); `offlineVerify` admits PEM Ed25519/ES256 M1
  entries and refuses malformed ones. AWS signing remains ES256-only.
- **Mobile / scanner boundary — UNVERIFIED, contract stated:** this repository's `app/` contains no door/scan screen and no verifier; the
  offline predicate lives only in `supabase/functions/_shared/offline-verify.ts`. Contract for the scanner SDK: (1) it MUST call the exported
  `normalizeSpkiPublicKey(M1[kid].public_key, M1[kid].algorithm)` (or `offlineVerify`, which does) before its verify primitive and treat `null`
  as a refusal, never as a signature failure; (2) its primitive MUST accept canonical bare-base64 SPKI DER only; (3) required tests: PEM and bare
  M1 entries admit, malformed ⇒ `malformed_public_key`, wrong-type key ⇒ `malformed_public_key`, `alg_mismatch` precedes key parsing, wrong
  key ⇒ `signature_invalid`; (4) **open item:** how a door obtains the public key for the `door-manifest` signature (the edge signs with
  `DOOR_MANIFEST_KMS_HANDLE_REF` from env, and no manifest-key distribution is specified in this repo) — must be specified before door deploy.

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

- **Device 2** = a **physically separate, clean device** (different hardware from the ceremony host; freshly provisioned or at minimum with no
  shared shell, files, `~/.aws`, browser profile, clipboard, or account session with the ceremony host). A second OS user on the same Mac does
  **not** satisfy M2 and is not an option. AWS CloudShell is not an M2 device either (it is not the founder's clean hardware and runs inside the
  same account's control plane).
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

**Status: O1 is engineering's PROPOSAL — NOT owner-approved.** No credential, user, or role exists.

**Documented Supabase capability (CLAUDE-OBSERVED, Supabase docs "Environment Variables"):** Edge Functions read secrets set via `supabase secrets set` /
the dashboard through `Deno.env`; the documented default secrets are Supabase's own (`SUPABASE_URL`, keys, `SB_REGION`, …). **Engineering
inference (not a documented statement):** I found **no** Supabase documentation of an AWS IAM role, OIDC/workload-identity federation, or
instance-metadata credential source available to Edge Functions. That is "not documented / not found", **not** "proven impossible" — an
undocumented or future mechanism would change the analysis. Repo facts: `kms.ts` "does NOT itself call `sts:AssumeRole`" and reads
`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SESSION_TOKEN` from env (`kms-taxonomy.ts:125–133`); `KMS_SIGNER_ROLE_ARN` is only a name.
Manually pasted expiring credentials are **not** a production mechanism (they die within hours). Under the documented capability, *something*
durable must sit in Supabase secrets; the design question is what, and how narrow.

| Option | Mechanism | Static secret in Supabase? | PFA-18C "distinct runtime **role**" | Engineering | Verdict |
|---|---|---|---|---|---|
| **O1 (engineering recommendation — PROPOSED, not approved)** | IAM user `snatchit-credential-sign-runtime` (may ONLY `sts:AssumeRole` → role `SnatchIt-CredentialSign-Runtime`, ExternalId) → role has `kms:Sign` on the exact ARN | yes: the user's access key (blast radius = ability to obtain Sign sessions; no IAM, no other keys, no Decrypt) | literal ✔ | `kms.ts`: STS `AssumeRole` via the existing SigV4 helper, in-isolate credential cache, refresh ≥5 min before `Expiration`, fail closed | **propose** |
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

Ordering that PFA-18C requires and this (proposed) design satisfies: the runtime **role** exists before CreateKey (so key policy v1 can name it); the exact-ARN
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
| E2 | **M3 runtime credential provider** (O1) — **implemented + locally tested (commit `72d4e90`); NOT deployed; O1 NOT adopted** | ✔ | ✔ | — | — | `kms-taxonomy.ts`: pure STS-XML parser + expiry/refresh decision (unit-tested); `kms.ts`: `AssumeRole` over existing SigV4 (`service=sts`, query API), cache per isolate, refresh at `Expiration−5min`, all failures → `KmsSignError('aws_kms_credentials_unavailable','permanent')`; env contract `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`KMS_SIGNER_ROLE_ARN`/`KMS_SIGNER_EXTERNAL_ID`/`AWS_REGION`; `UnconfiguredKmsSigner` default unchanged; DARK (no deploy); KMSADAPTER.md §11 item 2 closed |
| E3 | **M6 — migration 110** BEFORE INSERT guard on `kernel.signing_key` — **implemented + rehearsal-tested (commit `e181c3b`); NOT deployed; production ledger unchanged (124)**; spec/review `docs/phase2/M6_MIGRATION_110_SPEC_AND_REVIEW.md` | ✔ | ✔ | — | — | trigger `tg_signing_key_insert_guard` enforcing the **ratified global ES256 bootstrap lineage with no bypass**: reject `scope <> 'global'` (scoped keys stay parked until a PFA un-parks them — a future PFA changes the guard by migration, never by a runtime switch); reject `algorithm <> 'ES256'` unconditionally (no session GUC, no role exemption — the 103 `EdDSA` default can never survive an INSERT); reject `kms_handle_ref` not matching `^arn:aws:kms:[a-z0-9-]+:\d{12}:key/[0-9a-f-]{36}$`; reject `public_key` that does not parse as an SPKI PEM `PUBLIC KEY` block of a P-256 key or that contains `PRIVATE KEY`; reject `status <> 'active'` on insert; pgTAP suite 176 (≥8 negatives incl. EdDSA-with-superuser + 1 positive); rehearsal reset+test green; G-4; Gate-2 census bumped; rollback file; NOT applied to production without authorization; **required before issuance, not before bootstrap** |
| E4 | **Gated two-person post-revoke re-bootstrap artifact** | — | — | — | — | SQL artifact: PRE-FLIGHT exactly one `revoked` global + zero `active`; two distinct `platform_admin`+aal2 command keys recorded in `kernel.ceremony_approval` (new table, migration) within a 15-min window, else `dual_control_unavailable`; sets `algorithm` explicitly; fingerprint gate as §6.1; classified TWO-PERSON-MANDATORY post-T3; pgTAP negatives (single approver, expired window, active key present) |
| E5 | **M5 end-to-end credential-sign test** | — | — | — | — | after E1+E2 and a separately authorized **dark** deploy of `credential-sign` with `KMS_PROVIDER=aws`: one throwaway atom on a non-saleable test event; edge returns a token; sign-after-verify PASS; CloudTrail shows exactly one `Sign` by the runtime role; `feature.native_issuance_enabled` stays false throughout; recorded in the execution record |
| E6 | **Model A audit isolation** — audit plane before T3; **account LAYOUT settled before CreateKey** | — | — | — | — | **SCPs never apply to an Organizations management account**, so the signing workload must NOT live in the management account. Proposed layout (no organization created now): (1) a NEW, dedicated **management account** that hosts no workloads, no KMS keys, no trails of its own — root MFA, no access keys, used only for Organizations/SCP administration; (2) a **workload (signing) MEMBER account** where the production KMS key, ceremony/runtime/verifier principals, and the app's AWS resources live — this is what the SCP protects; (3) an **audit MEMBER account** owning the organization trail and the Object-Lock bucket, with no workload principals. Because the production key must be created *inside* the member account that the SCP binds, the layout decision precedes CreateKey; the KMS ARN then carries that member account id. Open owner questions: whether `652872010073` (Free plan) becomes the workload member (FAQ: an upgrade *via* Organizations expires Free-Tier credits immediately; joining an org is plan-affecting and must be owner-authorized) or a fresh paid workload account is created. Acceptance: org + 2 member accounts; org trail → audit-account Object-Lock bucket; SCP on the workload account denying `cloudtrail:Stop*/Delete*/Update*/PutEventSelectors`, audit-bucket mutation, and `kms:ScheduleKeyDeletion` on the signing key to *everyone including account admins*; Device-2 read-back from the audit account; PFA-18C residual formally closed |
| E7 | Gate-C owner/config blockers (unchanged) | n/a | n/a | n/a | — | **First-sale gate:** LEGAL/TAX posture (PFA-PT-7) affirmed; `fee.buyer_service_bps` owner-set; venue Connect onboarding with transfers capability; dark deploy of native edges (separate authorization); issuance/scanning flag flips (separate authorization). **Separate, later gate — `deletion.post_event_hold_hours`** gates **deletion *finalization*** (post-event erasure may not run while it is owner-unset; erasure fails closed) — it does **not** gate the first sale. See `FINAL_OWNER_SIGNATURE_AND_PRODUCTION_PREFLIGHT.md` Gate C and the deletion-gate stop condition |

Already in place (I/T, dark, not D/V): `AwsKmsSigner` ES256 transport + taxonomy (vitest 56/56 in `credential-sign-kms.test.ts`), sign-after-verify,
`check_signing_key_invariants` + monitor cron (099), `get_ticket_signing_context` algorithm pinning (103), §6.1 M4-corrected artifact (rehearsal-proven),
PFA-18B revoke + force-close (106/109), door PIN KDF + machine authority (107/108).

## 10. Blockers, owner decisions, next actions

**Blocking Phase-1 AWS mutations (in order):**
1. **P0-FREEPLAN — resolved as an owner decision (keep Free plan), which leaves CreateKey NO-GO in `652872010073`.** M1/M2/M3 setup in this account
   would inherit the 2027-03-05 horizon. Owner to choose later among §3(a)/(b)/(c); nothing authorized now.
2. **Model A account layout** (E6) — settle *which* account will hold the production key before any CreateKey (the key ARN is account-bound).
3. **Owner decisions still open:** (a) pin region `us-east-1`; (b) Object-Lock retention years (1 / 3 / 7 — engineering recommends 3, never chosen by
   engineering); (c) O1 runtime-credential proposal: approve, or direct O4; (d) confirm resource names in `pfa18c_artifacts/README.md`.
4. **E2** AssumeRole credential provider (if O1 is approved) — required before M5, not before bootstrap.

**Done this session:** E1 (P1-PUBKEY-FORMAT) — implemented + tested; deployment of the corrected edges remains pending (dark; separate authorization).

**Owner AWS command convention (all future stages):** every command carries `--profile snatchit-admin --region us-east-1` explicitly — never the
implicit default. Example of the read-only plan check already performed:
```bash
aws freetier get-account-plan-state --profile snatchit-admin --region us-east-1
```

**Next engineering task:** E2 — the STS `AssumeRole` credential provider in `kms.ts`/`kms-taxonomy.ts` (pure XML/expiry logic unit-tested; DARK; no
deploy), *conditional on the owner approving O1*. If O1 is not approved, next is the M6 migration-110 specification review (E3) — still no migration
until authorized.

**Stage plan once GO (one stage per turn, founder-executed, device labelled, `--profile snatchit-admin --region us-east-1` on every command, STOP
after each):** M1-1 bucket (Object Lock at creation) → M1-2 encryption + public-access block + bucket policy → M1-3 Object-Lock default retention →
M1-4 trail (multi-region, validation, start logging) → M1-5 ceremony role (trust + policy) → M1-6 first `assume-role` with MFA (doubles as the
deferred MFA test) → M2-1 verifier user (console+MFA+policy) → M2-2 Device-2 `aws login` + attestation → M2-3 full M1 read-back from Device 2 →
M3-1 runtime user + role (trust; exact-ARN policy deferred) → PHASE-1 GATE → §18 owner checkpoint → `AUTHORIZE PFA-18C CREATEKEY`.

## 11. Changed files, tests, tested commit (P1-PUBKEY-FORMAT fix)

| File | Change |
|---|---|
| `supabase/functions/credential-sign/credential.ts` | `normalizeSpkiPublicKey` (+ strict base64 decode/encode helpers, SPKI prefixes); `VerifyReason` += `malformed_public_key`; `verifyToken` and `verifyCanonicalSignature` normalize before the primitive; resolver docs |
| `supabase/functions/_shared/offline-verify.ts` | identical no-imports copy of the normalizer (exported for the scanner SDK); `OfflineVerifyReason` += `malformed_public_key`; step 2 normalizes before `ctx.verify` |
| `supabase/functions/credential-sign/index.ts` | comment only — documents that the injected primitive now receives canonical base64 (no behaviour change; `door-manifest` untouched) |
| `tests/credential-sign-pubkey-format.test.ts` | NEW — 21 cases (matrix, copy-agreement, `verifyToken`, sign-after-verify regression reproduce/close, `offlineVerify`) |

Checks run on the working tree that became the tested commit (recorded below): `npx vitest run` **690/690 passed, 16 files** (669 before + 21 new);
`npm run typecheck` **clean**; `npm run lint` **0 errors** (45 pre-existing warnings in `src/` screens, unrelated); `scripts/ci/assembled_migration_integrity.sh`
**G-4 PASS** (no migration touched). `deno check` not available locally — Deno-side type check of the edge shells happens at CI/deploy time.
**E2 (later session, same day):** `AssumeRoleCredentialProvider` + `AwsKmsSignerCore` in `kms-taxonomy.ts` (pure), SigV4 transports +
`createAwsKmsSigner`/`selectKmsSignerFromEnv` in `kms.ts`, both edges rewired, `tests/credential-sign-sts-provider.test.ts` (28 mocked-network
cases). Design + operations: `docs/phase2/_impl/KMS_RUNTIME_CREDENTIALS.md`. Suite       Tests  718 passed (718) passed; typecheck clean; lint 0 errors;
`deno check` OUTSTANDING (not available on the engineering host). Tested commit `72d4e90`. Deployment PENDING; O1 adoption, access-key creation,
Supabase secrets, billing: UNAPPROVED.

**Tested commit (P1-PUBKEY-FORMAT):** `c150283` (branch `feature/venue-native-and-product-v2`). **Production deployment: PENDING** — the corrected
`credential-sign` / shared verifier are DARK and undeployed; no edge, flag, DB, AWS, KMS, billing, or secret was changed.

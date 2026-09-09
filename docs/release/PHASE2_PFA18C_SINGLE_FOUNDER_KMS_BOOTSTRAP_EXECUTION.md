# PHASE 2 — PFA-18C SINGLE-FOUNDER AWS KMS / ES256 TRUST-ROOT BOOTSTRAP — EXECUTION RECORD

**Status legend:** PREPARATION · CEREMONY · COMPLETED · NOT COMPLETED · ABORTED · PARTIAL STATE

> Interactive, human-executed. The founder runs **every** AWS and production-database mutation.
> Claude is coordinator / instruction generator / read-back verifier / adversarial checker only.
> No secret material is ever recorded here (no access keys, secret keys, session tokens, DB passwords,
> service-role secrets, private keys, auth cookies, or password-bearing connection strings).

---

## OVERALL STATE

```
OVERALL:                 C2-C5 COMPLETE — the AWS trust root EXISTS and is corroborated (session 8).
                         C3 (insert into kernel.signing_key) NOT AUTHORIZED, NOT PERFORMED.
KMS KEY CREATED:         YES — arn:aws:kms:us-east-1:652872010073:key/45907419-8894-4582-ba79-71e9c29c549e
                         ECC_NIST_P256 / SIGN_VERIFY / ECDSA_SHA_256, Enabled, created 2026-09-09
                         (superseded "KMS KEY CREATED: NO", true through session 7 / 2026-09-06)
SIGNING KEYS IN PROD:    0   ← still zero: the key lives ONLY in AWS KMS, not in Supabase
PRODUCTION MUTATION:     NONE
NATIVE ISSUANCE:         FALSE
NATIVE SCANNING:         FALSE
LAST UPDATED (UTC):      2026-09-09 (session 8 — C2-C5 evidence recorded and corroborated read-only)
```

---

## AUTHORIZATION

Owner-authorized interactive production operation (CLAUDE A train, 2026-09-04): execute the NEXT GATE
identified by the PFA-18C ratification — single-founder KMS bootstrap **infrastructure preparation +
dark trust-root ceremony**, strictly governed by PFA-18C. C18 is binding: the founder personally runs
every AWS IAM / CloudTrail / S3+Object-Lock / KMS / production-DB mutation; Claude never operates AWS or
the DB, is not a ceremony principal, runtime signer, or second-device operator, and never handles secrets.

Interactive rule accepted: one stage at a time — explain, read-only inspect, provide exact human
command(s) with the device labelled, name the non-secret output to return, STOP, verify, then advance.
On any unexpected security-gate failure: STOP, no improvisation.

## PFA-18C RATIFICATION

OWNER-RATIFIED 2026-09-04 — `docs/architecture/_governance/PFA_18C_OWNER_RATIFICATION.md`.
Model APPROVED, execution-gated. M4 FIXED; M1/M2/M3 required before bootstrap; M5/M6 + Model A before
issuance; consumed once; future lifecycle → two-person control (fail closed).

## SOURCE OF TRUTH (re-read this session)

- `docs/architecture/_governance/PFA_18C_OWNER_RATIFICATION.md`
- `docs/architecture/_governance/PFA_SINGLE_FOUNDER_KMS_BOOTSTRAP.md`
- `docs/architecture/_governance/PFA_18C_REMEDIATION_AND_FINAL_RATIFICATION.md`
- `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md` (PFA-18A/18B/18C/PT-6/PT-8)
- `docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md` (canonical §5.3 binding proof, §6.1 bootstrap artifact)
- `docs/release/PHASE2_PRODUCTION_KMS_SIGNING_CEREMONY_EXECUTION.md` (prior two-person NO-GO record)
- `docs/release/PHASE2_093_109_PRODUCTION_MIGRATION_EXECUTION.md`
- signing implementation: migrations 083 / 099 / 102 / 103; `kernel.signing_key`,
  `kernel.check_signing_key_invariants`, `kernel.get_ticket_signing_context`; `AwsKmsSigner`,
  `credential-sign`, signing monitor.

### M4 ARTIFACT VERIFICATION — **PASS**

Canonical §6.1 artifact in `docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md` (L428–536) writes `algorithm`
**explicitly** from `-v ALGORITHM="ES256"` and never inherits the `kernel.signing_key.algorithm` column
default (`'EdDSA'`, migration 103):
- L428 invocation contract `-v ALGORITHM="ES256"` (EXPLICIT — never the column default);
- L476–493 PRE-FLIGHT 2b ALGORITHM GATE — empty/unsanctioned aborts; for this AWS ceremony must be `ES256`;
- L511–515 INSERT column list includes `algorithm`, value `i.algorithm` from ceremony input;
- L531/L536 POST-CHECK asserts `k.algorithm = ceremony_input.algorithm`.
M4 is present and correct → **not a NO-GO.**

---

## PRECHECK — FRESH READ-ONLY PRODUCTION STATE — **PASS**

Read-only via Supabase MCP `execute_sql`, project `hqycwntpfoztoinemqns`, DB `postgres`,
**2026-09-04 16:05:06Z**. No writes.

| Item | Expected | Observed | Result |
|---|---|---|---|
| migration ledger count | 124 | 124 | PASS |
| migration 093 present | yes | yes | PASS |
| migration 109 present | yes | yes | PASS |
| numeric substrate tip | 109 | 109 | PASS |
| `kernel.signing_key` count | 0 | 0 | PASS |
| `signing.expected_key_fingerprint` | null | null | PASS |
| `signing.expected_max_not_after` | null | null | PASS |
| `signing.monitor_enabled` | false | false | PASS |
| `feature.native_issuance_enabled` | false | false | PASS |
| `feature.native_scanning_enabled` | false | false | PASS |
| `kernel.tickets` | 0 | 0 | PASS |
| `venue.door_pin` | 0 | 0 | PASS |
| `venue.door_session` | 0 | 0 | PASS |
| `venue.scan` | 0 | 0 | PASS |
| `venue.door_manifest` | 0 | 0 | PASS |
| native Phase-2 edges deployed | none | none (only legacy commerce/transfer edges) | PASS |

Deployed edge functions (all legacy, none native Phase-2): create-payment-intent, confirm-payment,
send-push, stripe-webhook, auto-finalize-auctions, create-connect-account, confirm-and-release,
enforce-transfer-expiry, delete-account, notify-report, notify-transfer. **No** credential-sign /
primary-checkout / door-session / door-manifest. Config namespace = `catalog.platform_config`.

**Precheck verdict: GO** — production is DARK, unchanged, and matches the ratified baseline.

## OWNER / OPERATOR

```
FOUNDER / CEREMONY OPERATOR:  Jose David Tascon Herrera
ROLE:                         Snatch It Founder / Owner
PFA:                          PFA-18C (single-founder compensating-control INITIAL bootstrap)
SECOND TECHNICAL HUMAN:       none required (compensating-control model)
Juan Fernandez:               NOT Person B — receives no privileged access
```

---

## AWS BASELINE INVENTORY — **RECEIVED 2026-09-05 (owner-returned evidence)**

Evidence class: **OWNER-RETURNED** (typed by the founder from the primary ceremony machine). It is NOT
independently refreshed — Claude has no AWS access by design (C18), so no AWS fact in this record is
Claude-observed. Independent confirmation is deferred to the M2 second-device read-back stage.

| Item | Owner-returned value |
|---|---|
| Account | `652872010073` |
| Principal | `arn:aws:iam::652872010073:user/jose-admin` (IAM user; UserId `AIDAZQARUJFMXKFV5U5JY`) |
| Auth method | `aws login` (browser console session → temporary credentials); verified via `sts get-caller-identity` |
| CLI / host | AWS CLI 2.36.40, Apple-Silicon Mac; profile `snatchit-admin` |
| Region | saved `us-east-1`; `AWS_REGION` / `AWS_DEFAULT_REGION` unset |
| Organizations | `AWSOrganizationsNotInUseException` (no org) |
| CloudTrail (us-east-1) | `[]` — no trail |
| S3 buckets | `[]` — none |
| IAM users | `jose-admin` only (AdministratorAccess via group `SnatchIt-admins`; console login works; passkey MFA registered; **fresh MFA sign-in test deferred**) |
| IAM roles | service-linked only: ResourceExplorer, Support, TrustedAdvisor — **no** ceremony / runtime / verifier role |
| Root | MFA used successfully; **zero** root access keys |
| Long-lived access keys created | **none** |
| Billing | owner wants to stay on the Free plan where possible; **no billing upgrade authorized**; plan type NOT yet proven |

### §4 ROOT SAFETY — **PASS** (active principal is an IAM user, not root; root has 0 access keys + MFA).
### §5 REGION — `us-east-1` is the only signal (saved CLI region; nothing frozen in the repo or architecture).
Recorded as the PROPOSED pin; becomes PINNED on explicit owner confirmation in the next stage.

### M1 / M2 / M3 — **NOT STARTED.** Nothing to reuse: no trail, no bucket, no roles. All must be created.
Concrete design + reviewable policy artifacts prepared (NOT applied):
`docs/release/PHASE2_PFA18C_BOOTSTRAP_READINESS_REPORT.md` and `docs/release/pfa18c_artifacts/`.

### FRESH READ-ONLY PRODUCTION PRECHECK #2 — **PASS, unchanged** (2026-09-05 20:17:23Z, MCP execute_sql, read-only)
ledger 124 · 093+109 present · numeric tip 109 · `kernel.signing_key` 0 · expected_key_fingerprint null ·
expected_max_not_after null · monitor_enabled false · native_issuance false · native_scanning false ·
tickets 0 · door_pin 0 · door_session 0 · scan 0 · door_manifest 0 · native edges not deployed.
No differences from the recorded baseline. No repair performed. No production write.

### M4 RE-VERIFICATION — **PASS** (canonical §6.1, `docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md` L428–536:
explicit `-v ALGORITHM="ES256"`, PRE-FLIGHT 2b gate, `algorithm` in INSERT + POST-CHECK; never the column default).

### NEW FINDINGS (session 2) — details + acceptance criteria in the readiness report
- **P0-FREEPLAN (conditional)** — if the account is on the AWS *Free account plan*, AWS closes it after 6
  months or credit exhaustion, retains data 90 days, then permanently erases it. A production KMS trust
  root and compliance-locked audit evidence cannot live in such an account. **CreateKey is NO-GO until the
  plan type is proven PAID or the owner explicitly authorizes the upgrade.** No upgrade was performed.
- **P1-PUBKEY-FORMAT** — runbook D3 / §6.1 store `kernel.signing_key.public_key` as a PEM block; the
  credential-sign edge's sign-after-verify `atob()`'d it as bare base64 SPKI DER; `atob` throws on PEM armor
  (demonstrated: `InvalidCharacterError`) → every credential would be refused until the VERIFIER CODE is
  repaired. The stored PEM's immutability does not prevent that repair (the DB representation is correct;
  the consumer was wrong) — the earlier "permanent brick" wording is withdrawn. **FIXED in session 3** (see below).
- **M3 runtime-credential design gap** — Supabase Edge exposes only static secrets; `kms.ts` performs no
  AssumeRole. Design resolved on paper (readiness report §7); engineering + owner decision required.
- **OBS** — AWS KMS now offers `ECC_NIST_EDWARDS25519`; the repo premise "AWS has no Ed25519" is outdated.
  Ratified D2 = ES256 stands; no change proposed. CloudTrail classes KMS `Sign`/`GetPublicKey` as **Read**
  events → the trail must log Read+Write and must not exclude `kms.amazonaws.com`.

### SESSION 2 MUTATION LEDGER
AWS: **none.** Production DB: **none** (read-only queries only). KMS key: **not created.** Migration 110: **not created.**
Edges: **not deployed.** Config/flags: **unchanged.** Billing plan: **unchanged.**

_(subsequent sections — M1 audit plane, M1 read-back, M2, M3, Phase-1 gate, CreateKey checkpoint,
CreateKey, key metadata/policy, public-key derivation ×2, fingerprint comparison, §5.3 binding proof,
sign removal, pre-DB checkpoint, DB bootstrap, post-DB state, invariants, monitor, safe sign test,
CloudTrail evidence, final darkness verification, PFA-18C consumption, findings, final result, next gate —
appended as each stage completes.)_

---

## SESSION 3 — 2026-09-05 — OWNER PLAN-STATE EVIDENCE + P1-PUBKEY-FORMAT FIX + DESIGN CORRECTIONS

### Owner-returned evidence (OWNER-RETURNED; not Claude-observed)
`aws freetier get-account-plan-state` on account `652872010073`: **accountPlanType FREE · accountPlanStatus ACTIVE · $100 remaining ·
accountPlanExpirationDate 2027-03-05T17:57:11.079Z.** **Owner decision: KEEP THE AWS FREE PLAN. No billing upgrade authorized.**

### P0-FREEPLAN — status under that decision
CONFIRMED FREE. Under the keep-Free-plan decision, a KMS trust root / compliance-locked audit evidence in this account would have a hard horizon
of 2027-03-05 (+90-day grace, then erasure). **CreateKey = NO-GO in this account while the Free plan is kept.** Owner options (none authorized,
none performed) are listed in the readiness report §3. Repository work and local tests are unaffected and proceeded.

### P1-PUBKEY-FORMAT — FIXED (repository + local tests only; deployment PENDING)
Strict `normalizeSpkiPublicKey` in `credential-sign/credential.ts` (applied in `verifyToken` + `verifyCanonicalSignature`) and an identical
no-imports copy exported from `_shared/offline-verify.ts` (applied before the door's injected primitive); new refusal `malformed_public_key`;
PFA-PT-8 pin extended to the key bytes (ES256 ⇒ uncompressed P-256 SPKI only; EdDSA ⇒ Ed25519 SPKI only). D3 (PEM in the DB) and the D5
fingerprint contract are unchanged. `door-manifest` signs only — unchanged. Scanner/mobile verifier: not in this repo — boundary UNVERIFIED,
contract written in the readiness report §3. Tests: `tests/credential-sign-pubkey-format.test.ts` (21, real P-256/Ed25519 keys; AWS signing stays
ES256-only). Full suite 690/690; typecheck clean; lint 0 errors; G-4 PASS. **Tested commit: `c150283`.**

### Design corrections recorded (readiness report updated)
M2 = physically separate clean device only (same-Mac OS-user and CloudShell fallbacks removed). M6 = ratified global-ES256 lineage with **no**
bypass (session-GUC EdDSA override removed; no migration written). Model A = SCPs never bind the management account ⇒ dedicated management
account + workload member (holds the key) + audit member; layout to be settled **before CreateKey**; no organization created.
`deletion.post_event_hold_hours` gates deletion *finalization*, not first sale. O1 runtime credentials = PROPOSED, not owner-approved; Supabase
"no AWS federation" is a documented-capability finding, not a proof of impossibility. Owner AWS commands carry
`--profile snatchit-admin --region us-east-1`.

### SESSION 3 MUTATION LEDGER
AWS: **none.** Production DB: **none.** KMS: **not created.** Migration 110: **not created.** Edges: **not deployed.** Config/flags/secrets: **unchanged.**
Billing plan: **unchanged (FREE, per owner).** Repository: code + tests + docs committed on `feature/venue-native-and-product-v2`.

---

## SESSION 4 — 2026-09-05 — E2 RUNTIME CREDENTIAL PROVIDER (REPOSITORY + LOCAL TESTS ONLY)

Authorization: repository engineering only. **O1 production adoption, AWS access-key creation, Supabase secrets, deployment, and billing
changes remain UNAPPROVED. AWS plan: FREE (unchanged). No live AWS call was made.**

Implemented (DARK): `AssumeRoleCredentialProvider` (config validation; STS host derived from the region only; strict response extraction;
exact assumed-role identity check; `ASIA…` temporariness check; expiry sanity; per-isolate + per-config cache; single-flight refresh; refresh
5 min ahead; expired never returned; 5 s per-attempt timeout; ≤ 3 attempts, transient-only retry; redacted errors) and `AwsKmsSignerCore`
(ES256 pin; key handle must be a full key ARN in the configured region + role account; temporary-credentials-only gate — no base-credential
fallback; bounded Sign; response echo validation; DER→raw). `kms.ts` keeps the reviewed SigV4 as two transports + `createAwsKmsSigner` /
`selectKmsSignerFromEnv`; `credential-sign` and `door-manifest` both use that one selector. KMS error messages now carry the `__type` code
only (the body restating key ARN + principal is no longer embedded).

Tests: `tests/credential-sign-sts-provider.test.ts` — 28 cases against mocked STS/KMS transports (acquisition/reuse, early refresh, expiry,
concurrency, malformed/missing fields, identity mismatch, non-temporary key, invalid expiration, timeout with fake timers + abort, throttling,
5xx, AccessDenied, failed refresh, config-change invalidation, no-fallback ×2, redaction sentinel search, both consumers, key scope, ES256 pin,
response validation, DARK default). Suite       Tests  718 passed (718) passed; typecheck clean; lint 0 errors. **`deno check`: OUTSTANDING** (not available on the
engineering host — reported as not run, not as passed). **Tested commit: `72d4e90`.**

Design + operational requirements (rotation, compromise response, ExternalId as a trust condition only, SDK evaluation):
`docs/phase2/_impl/KMS_RUNTIME_CREDENTIALS.md`.

### SESSION 4 MUTATION LEDGER
AWS: **none** (no live call). Production DB: **none.** KMS: **not created.** Secrets: **none.** Migration 110: **not created.** Edges: **not
deployed.** Config/flags: **unchanged.** Billing: **FREE, unchanged.** Repository: code + tests + docs committed on `feature/venue-native-and-product-v2`.

---

## SESSION 5 — 2026-09-05 — M6 MIGRATION 110 SPECIFICATION + ADVERSARIAL REVIEW (LOCAL / REHEARSAL ONLY)

Authorization: local specification/tests/migration artifact only. **AWS FREE, unchanged. No AWS resource/key/secret/organization. No
deploy. NOT applied to production. Production ledger 124 / tip 109 / 0 keys / dark — UNCHANGED.**

Artifact: `supabase/migrations/110_signing_key_insert_guard.sql` (+ rollback, pgTAP suite 176, rehearsal census bumps, `tap.seed_core`
harness reconciliation). Guard rules 1–11 (scope global only; status active; ES256 with no override; full KMS key ARN; SPKI PEM of an
uncompressed P-256 key; no private material; advisory-lock serialization; duplicate key_id; exactly one active global; post-revoke recovery
PARKED fail-closed; first row must be the ruling-B key_id). Q7 decision: scoped rows rejected outright while provision/rotate are parked
(resolver most-specific-first ⇒ shadowing; parked writers write nothing; a runtime predicate would be a bypass). Recovery conflict analysis:
none — rule 10 IS the ratified fail-closed; the E4 two-person migration replaces it. PFA-18C wording untouched.

Evidence: fresh replay through 110 (no migration skipped; Gate-2 27/70/37/26); suite 176 51/51; full pgTAP plan 3746 · ok 3742 · not_ok 4 (only the 4 documented
local-only deltas); concurrency probe (second session blocked on the advisory lock then refused `active_global_exists`); unique-index
defense intact; rollback idempotent + double re-apply clean; vitest 729/729; typecheck clean; lint 0 errors; G-4 PASS; **`deno check`
OUTSTANDING** (not installed). Full report: `docs/phase2/M6_MIGRATION_110_SPEC_AND_REVIEW.md`. **Tested commit: `e181c3b`.**

### SESSION 5 MUTATION LEDGER
AWS: **none.** Production DB: **none** (no connection made this session). KMS: **not created.** Secrets: **none.** Migration 110: **written,
rehearsal-applied locally, NOT deployed.** Edges: **not deployed.** Config/flags: **unchanged.** Billing: **FREE, unchanged.**

---

## SESSION 6 — 2026-09-05 — E4 GATED TWO-PERSON POST-REVOKE RE-BOOTSTRAP (MIGRATION 111, LOCAL / REHEARSAL ONLY)

Authorization: local specification/tests/migration artifact only. **AWS FREE, unchanged. No AWS resource/KMS key/secret/organization. No
deployment, activation, or money movement. NOT applied to production. Production ledger 124 / tip 109 / 0 keys / dark — UNCHANGED.**
No owner ratification wording changed.

Artifact: `supabase/migrations/111_signing_key_recovery_two_person.sql` (+ generated rollback embedding 110's guard verbatim, pgTAP suite 177,
176 F2 updated, rehearsal census bumps). Adds the append-only `kernel.signing_key_recovery_approval` (RLS on, zero policies, zero client/
service_role grants), a pure fingerprint helper, `approve_signing_key_recovery` + `execute_signing_key_recovery` (platform_admin + aal2, two
DISTINCT identities, 30-minute window, executor must be an approver, fingerprint-bound, ES256 explicit, idempotent, audited) and re-creates the
110 guard so rule 10 admits a post-revoke row only with two unexpired matching approvals. Preconditions everywhere: zero active, EXACTLY ONE
revoked (0 ⇒ not applicable — the initial bootstrap is the §6.1 ceremony; >1 ⇒ lineage exceeded, needs its own ratification), unused key_id.
PFA-18A provision/rotate parked; PFA-18B revoke untouched. Residual disclosed: one human with two admin identities is detectable, not preventable.

Evidence: fresh replay through 111 (no migration skipped; Gate-2 27/70/37/26); suite 177 67/67; suite 176 51/51; full pgTAP plan 3813 · ok 3809 · not_ok 4 (only the 4
documented local-only deltas); transaction-rollback probe (rolled-back recovery insert leaves 0 active, approvals intact); concurrency probe
(second session blocked on the advisory lock, then refused `active_global_exists`); 111 rollback restores 110's `post_revoke_recovery_parked`,
re-apply ×2 clean; vitest 729/729; typecheck clean; lint 0 errors; G-4 PASS; **`deno check` OUTSTANDING**. Report:
`docs/phase2/E4_MIGRATION_111_RECOVERY_SPEC_AND_REVIEW.md`. **Tested commit: `927a02a`.**

### SESSION 6 MUTATION LEDGER
AWS: **none.** Production DB: **none** (no connection made). KMS: **not created.** Secrets: **none.** Migrations 110/111: **rehearsal-applied
locally, NOT deployed.** Edges: **not deployed.** Config/flags: **unchanged.** Billing: **FREE, unchanged.**

## SESSION 7 — 2026-09-05/06 — DARK PRE-CEREMONY AUDIT (LOCAL / REHEARSAL ONLY)

Authorization: audit + tests + documentation only. **AWS FREE, unchanged. No AWS call or resource. No production DB call (state not re-read;
last recorded: ledger 124 / tip 109 / 0 keys / dark). No deployment, secret, billing change, activation, or money movement.** No ratification
wording changed. Pre-existing user files untouched.

Chain audited: migrations 110–114 (order, rollback order, sha256, census deltas, replay + reverse rollback chain with per-step census/definition
hashes — inverts exactly, reapply lands on the fresh-replay hash `4d20f9f6…`), `/keys` M1 delivery, door-manifest signing (canonical bytes,
DB-derived key identity via 114, ES256/active/window re-pin, sign-then-verify, opaque errors + redaction), the credential → offline-verify →
M2 sync → online scan → offline reconcile state machine, M6/revocation/recovery gates (exact parked / owner-gated points), M5 (new mocked-signer
rehearsal `tests/m5-mocked-signer-rehearsal.test.ts`, 7; live residue stated), signed-M1 bundles (deferred; protocol change identified).
Runbook defects corrected with dated notes: `PRODUCTION_SIGNING_KMS_CEREMONY.md` §7.3 (stale six-item parked loop — `revoke_signing_key` is
un-parked since 106, which production carries) and §13 Step 3 (revoke/force-close/recovery state). Deliverables:
`docs/release/PHASE2_PFA18C_DARK_PRECEREMONY_AUDIT.md` (audit) and `docs/release/PHASE2_PFA18C_OWNER_CEREMONY_RUNBOOK.md` (owner runbook:
NO-GO conditions incl. the Free plan, read-only preflight with the corrected parked-state check, artifacts, authorization phrases per mutation,
post-mutation verification, abort/rollback matrix).

Evidence: full pgTAP plan 3941 · ok 3937 · not_ok 4 (documented 060×2/132×2); suites 176–180 51/67/41/45/42 after the reverse chain; vitest
803/803; typecheck clean; lint 0 errors (45 pre-existing warnings); G-4 PASS; CI run 34002456147 at `1f3fc19` green incl. Deno type-check.
**Tested commit: `1f3fc19`.**

### SESSION 7 MUTATION LEDGER
AWS: **none.** Production DB: **none** (no connection made). KMS: **not created.** Secrets: **none.** Migrations 110–114: **rehearsal only,
NOT deployed.** Edges: **not deployed.** Config/flags: **unchanged.** Billing: **FREE, unchanged.**


---

## SESSION 8 — 2026-09-09 — C2–C5 CEREMONY COMPLETE — **AWS TRUST ROOT ESTABLISHED, SUPABASE UNCHANGED**

The owner ran PFA-18C C2–C5 (key creation, public-key export, challenge signing, two-machine verification). This session
**recorded** that evidence and **independently corroborated** it with read-only AWS reads. No AWS mutation, no Supabase
write, no flag, no deploy, no secret. C3 (insertion of the trust root into `kernel.signing_key`) remains **separately
unauthorized and NOT performed**.

### Owner-reported ceremony evidence

| Item | Value |
|---|---|
| KMS key (as reported) | `arn:aws:kms:us-east-1:652872010073/45907419-8894-4582-ba79-71e9c29c549e` |
| KMS key (**canonical, corrected**) | `arn:aws:kms:us-east-1:652872010073:key/45907419-8894-4582-ba79-71e9c29c549e` |
| D5 public-key fingerprint | `562b5e87bb1c70ba2791503dd3cfe7014332c4cf9278d7c72680806768f64415` |
| Challenge signature SHA-256 | `83c3938e03ac82f5b8ba01687e9f7cc32d366606ba8dd3a206d053fd147eeb15` |
| Signature size | 70 bytes |
| Mac 1 verification | Verified OK |
| Mac 2, correct key | Verified OK |
| Altered challenge | verification FAILED (expected) |
| Wrong key | verification FAILED (expected) |

**Transcription correction.** The reported ARN separates account and key id with `/`. A KMS key ARN uses
`:key/`. `DescribeKey` returns the canonical form above; the account id, region and key id in the reported string are
all correct, only the separator was wrong. **The canonical form is authoritative in this record**; anything downstream
that consumes the ARN (a future C3 insert, the runtime credential provider) must use it.

### Independent corroboration — read-only AWS reads, 2026-09-09

Performed with the `snatchit-admin` read profile. No mutating API was called.

**1. `kms:DescribeKey`** — the key exists and is shaped for ES256 ticket signing:

```
AWSAccountId  652872010073          KeyState   Enabled
KeyId         45907419-8894-4582-ba79-71e9c29c549e
Arn           arn:aws:kms:us-east-1:652872010073:key/45907419-8894-4582-ba79-71e9c29c549e
Description   Snatch It ticket-signing trust root (PFA-18C)
KeyUsage      SIGN_VERIFY           KeySpec    ECC_NIST_P256
SigningAlgorithms  ["ECDSA_SHA_256"]           Origin     AWS_KMS
CreationDate  2026-09-09T01:44:33-04:00        MultiRegion false
```

**2. `kms:GetPublicKey` — D5 fingerprint reproduced exactly.** The exported SubjectPublicKeyInfo is 91 bytes of DER;
its SHA-256 is

```
562b5e87bb1c70ba2791503dd3cfe7014332c4cf9278d7c72680806768f64415
```

— byte-identical to the owner's D5 value. This is the strongest single corroboration available without re-running the
ceremony: it proves the fingerprint in the record belongs to *this* key.

**3. `cloudtrail:LookupEvents` — exactly ONE `Sign` event for this key.** Window 2026-09-08T00:00:00Z → now,
`EventName=Sign`, us-east-1: **1 event returned, 0 others, no failed attempts.**

| Field | Value | Required | Match |
|---|---|---|---|
| `eventID` | `ca5a2602-a9a6-4dc9-967d-37616efd9c37` | — | — |
| `eventTime` | `2026-09-09T06:20:13Z` | — | — |
| `eventSource` / `eventName` | `kms.amazonaws.com` / `Sign` | one Sign | **✓ exactly one** |
| `userIdentity.arn` | `arn:aws:sts::652872010073:assumed-role/SnatchIt-KMS-Ceremony/pfa18c-ceremony` | `SnatchIt-KMS-Ceremony/pfa18c-ceremony` | **✓** |
| `sessionContext.attributes.mfaAuthenticated` | `true` | MFA | **✓** |
| `requestParameters.messageType` | `RAW` | `RAW` | **✓** |
| `requestParameters.signingAlgorithm` | `ECDSA_SHA_256` | `ECDSA_SHA_256` | **✓** |
| `requestParameters.keyId` | the canonical ARN above | this key | **✓** |
| `errorCode` | none | — | clean |
| session `creationDate` | `2026-09-09T05:44:21Z` | — | role assumed ~36 min before the Sign |

The 70-byte signature size is consistent with a DER-encoded ECDSA P-256 signature (70–72 bytes depending on
integer padding) and is recorded as owner-reported; CloudTrail does not carry the signature or its digest, so the
`83c3938e…` challenge-signature SHA-256 stands on the owner's two-machine verification, not on an AWS read.

### Production state — re-read read-only this session, UNCHANGED

```
migration ledger rows           135          (numeric tip 120, max 20260902003623)
kernel.signing_key rows         0            ← the trust root is NOT in Supabase
feature.native_issuance_enabled false
feature.native_scanning_enabled false
feature.native_resale_enabled   false
public.get_my_tickets           absent
```

### SESSION 8 MUTATION LEDGER
AWS: **none** (DescribeKey, GetPublicKey, LookupEvents are read-only). Supabase production: **none** — reads only; the
KMS key was **NOT** inserted into `kernel.signing_key`. Secrets: **none created**. Flags: **unchanged, all three native
gates false**. Edges: **not deployed**. Issuance/scanning: **none performed**. Migrations: **none applied**. Billing:
unchanged.

### NEXT GATED STAGE
**C3 — insertion of the trust root into `kernel.signing_key`** (migration 110's insert guard governs it; two-person
recovery is 111). C3 is **separately unauthorized** and was not begun. Everything after it — key delivery to the door
plane (114), enabling `feature.native_issuance_enabled`, deploying the native edges — remains behind its own gates.

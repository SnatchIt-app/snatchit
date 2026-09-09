# PHASE 2 — PFA-18C SINGLE-FOUNDER AWS KMS / ES256 TRUST-ROOT BOOTSTRAP — EXECUTION RECORD

**Status legend:** PREPARATION · CEREMONY · COMPLETED · NOT COMPLETED · ABORTED · PARTIAL STATE

> Interactive, human-executed. The founder runs **every** AWS and production-database mutation.
> Claude is coordinator / instruction generator / read-back verifier / adversarial checker only.
> No secret material is ever recorded here (no access keys, secret keys, session tokens, DB passwords,
> service-role secrets, private keys, auth cookies, or password-bearing connection strings).

---

## OVERALL STATE

```
OVERALL:                 PREPARATION — AWS baseline RECEIVED; plan state RECEIVED (FREE, owner keeps it) ⇒ CreateKey
                         NO-GO in account 652872010073 under current decisions; M1/M2/M3 NOT STARTED;
                         P1-PUBKEY-FORMAT FIXED in repo (deploy pending)
KMS KEY CREATED:         NO
SIGNING KEYS IN PROD:    0
PRODUCTION MUTATION:     NONE
NATIVE ISSUANCE:         FALSE
NATIVE SCANNING:         FALSE
LAST UPDATED (UTC):      2026-09-05 (session 3 — plan-state evidence + P1-PUBKEY-FORMAT fix)
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

## SESSION 8 — 2026-09-08 — BILLING STEP PREPARATION + STATE RECONCILIATION (NO MUTATION)

Authorization: the owner approved moving beyond the AWS Free plan (pay-as-you-go; **not** a $100 purchase, subscription, support plan, or credit
package; **not** a recurring budget or spending authorization). That approval authorizes **no** KMS key, Organization, account, IAM resource,
CloudTrail trail, Object-Lock bucket, production migration, deployment, secret, or activation. C18 unchanged. Pre-existing user edits preserved
(`M docs/release/PHASE2_PRODUCTION_KMS_SIGNING_CEREMONY_EXECUTION.md`, `?? docs/phase2/TICKETS_READ_CONTRACT_CORE_COORDINATION.md` untouched).

### Reconciliation (CLAUDE-OBSERVED unless stated)
- Audit commits `1f3fc19` / `aa74cc2` remain current: `aa74cc2` = tip of `feature/venue-native-and-product-v2` = `origin`; CI green on both.
  `admin/operating-console @ ab3e17f` (= `aa74cc2` + ops-console 115–120; PR #55; CI green) touches no PFA-18C document or 110–114 file.
- **Production drift from the recorded baseline (owner-approved, not an incident):** ledger **130** rows, numeric tip **120** — migrations 115–120
  (ops console RC3) were applied 2026-09-08 ~00:2xZ per `docs/admin-console/DEPLOYMENT_RECORD_2026-09-08.md` (admin branch); owner visually
  confirmed auto-deploy OFF on 2026-09-07; `git_branch: ""` (mechanical read). **110–114 remain unapplied** (`guard_110_present=false`,
  `recovery_111_present=false`, `venue.get_signing_keys_door` absent). Signing substrate unchanged: `kernel.signing_key` 0 · issuance false ·
  scanning false · monitor false · fingerprint null · max_not_after null · tickets 0 · door_session 0 · census kernel 149 / venue 83 / kernel
  tables 31 · native edges not deployed (11 legacy edges only). Read 2026-09-08T00:38Z via Supabase MCP `execute_sql`, read-only.
  Runbook NG-3 re-baselined by dated note (ledger 130 / tip 120 / 110–114 absent / 0 keys).
- **AWS plan: NOT re-verified** — `aws sts get-caller-identity` / `aws freetier get-account-plan-state` returned "Your session has expired.
  Please reauthenticate using 'aws login'." Last state remains OWNER-RETURNED 2026-09-05 (FREE, $100 remaining, expires 2027-03-05T17:57:11Z).
  PAID will be recorded only from a fresh `get-account-plan-state`.

### Production-order rehearsal (REHEARSAL, local harness, 2026-09-08T00:46Z)
Because production now carries 115–120 without 110–114, the apply order will be 115–120 → 110–114 (not the CI fresh-replay order).
Replayed the chain without 110–114 ⇒ census 149/83/ops 90/31 (= production), applied 110→114 ⇒ 153/87/90/32 with guard + recovery present;
canonical-order replay ⇒ identical census, Gate-2 27/71/37/27 (= CI baseline); function/trigger/policy definitions + routine grants across
seven schemas (682 lines) **IDENTICAL** between the two databases; full pgTAP on the production-order DB `plan 4320 · ok 4316 · not_ok 4`
(documented 060×2/132×2 only). Details: `PHASE2_PFA18C_EXECUTION_READINESS_PACKET.md` §7.1.

### Deliverable
`docs/release/PHASE2_PFA18C_EXECUTION_READINESS_PACKET.md` — billing state + owner steps (B0–B5), Model-A account-layout recommendation
(reuse `652872010073` as the workload member; management + audit accounts later; no Organization now), cost estimate from official pricing
read this session (≈ $1.06–1.15/month dark, ≈ $1.00 of it the key; + $0.015 per 1,000 credentials live; credits treatment + exclusions; budget
alerts are notifications, not caps), M1–M6 / recovery / Model-A reconciliation (PFA controls distinguished from the scanner's M1/M2 manifests),
exact names / bindings / execution order / verification / abort conditions, 110–114 release sequence and dependencies (apply tree must contain
115–120; `db push --include-all --dry-run` must list exactly 110–114; dark deployment separated from activation), remaining owner decisions
(region pin; irreversible Object-Lock years; O1 vs O4 runtime credentials; layout confirmation; names; MFA mechanism for the ceremony trust;
C3/C4 ordering), and the next authorization-bearing action (C1 / M1-1 after NG-1 clears).

### Official-documentation facts read this session (for the billing step)
Upgrade = Console home → Cost and Usage widget → "Upgrade plan" (`https://console.aws.amazon.com/billing/home?#/freetier/upgrade`) → review →
"Upgrade account"; CLI equivalent `aws freetier upgrade-account-plan --account-plan-type PAID`. Remaining credits apply automatically after the
upgrade until 12 months after account creation; upgrading **via** Organizations/Control Tower expires them immediately; a Free plan auto-upgrades
on joining an Organization. Payment method is not charged until the upgrade; afterwards only pay-as-you-go usage beyond credits. Free plans
"don't have access to certain AWS services" (not enumerated).

### SESSION 8 MUTATION LEDGER
AWS: **none** (read-only calls attempted; session expired; no login performed by Claude). Production DB: **none** (read-only queries only).
KMS: **not created.** Secrets: **none.** Organizations/accounts/IAM/CloudTrail/S3: **none.** Migrations 110–114: **NOT applied** (rehearsal
only). Edges: **not deployed.** Config/flags: **unchanged.** Billing plan: **unchanged (FREE last seen 2026-09-05; not re-read).**
Repository: this record, the runbook NG-3 dated note, and the readiness packet — committed on `feature/venue-native-and-product-v2`.

---

## SESSION 9 — 2026-09-08 — PAID-PLAN CONFIRMATION (OWNER-CONFIRMED) + C1 PACKAGE PREPARATION (NO MUTATION)

Authorization: the owner reports completing the direct AWS Paid-plan upgrade in the Console (root used for billing; `jose-admin` remains the
engineering identity). **Recorded as OWNER-CONFIRMED until the API verifies it.** The 2026-09-05 "keep Free plan" decision is **superseded**.
The upgrade authorizes **no** IAM/S3/CloudTrail/Organizations/KMS creation, production migration, secret, deployment, or activation. C18 unchanged.
Pre-existing user edits preserved (`M docs/release/PHASE2_PRODUCTION_KMS_SIGNING_CEREMONY_EXECUTION.md`, `?? docs/phase2/TICKETS_READ_CONTRACT_CORE_COORDINATION.md`).

### Billing / identity verification — NOT YET (CLAUDE-OBSERVED 2026-09-08T01:25Z)
`aws sts get-caller-identity` and `aws freetier get-account-plan-state` (profile `snatchit-admin`, us-east-1) both returned:
"Unable to refresh login credentials because of a change in your password. Please reauthenticate with your new password using 'aws login'."
⇒ no fresh identity or plan evidence this session. **PAID will be recorded only from a fresh `get-account-plan-state`.** Runbook NG-1 carries a
dated note (owner-confirmed; cleared on API evidence only). Nothing was purchased; the upgrade was not repeated.

### Reconciliation (CLAUDE-OBSERVED 2026-09-08T01:26Z)
Branch tip `21ac8e7` = `origin`; no later change to any PFA-18C document, artifact, or 110–114 file on any branch (`admin/operating-console` → `78a56fd`,
its deployment record only). Production: ledger **130**, numeric tip **120**, present 115–120, **110–114 absent**, `kernel.signing_key` **0**, flags
dark (issuance/scanning/monitor false; fingerprint/max_not_after null), tickets 0, census kernel 149 / venue 83 / kernel tables 31 — unchanged vs
session 8. All ten artifact JSON files parse; unchanged since `aa74cc2` before this session's corrections.

### Artifact validation (OFFICIAL-DOC-backed; log in `docs/release/pfa18c_artifacts/README.md`)
F1 key-policy lockout safety → v1 gains an explicit ceremony `PutKeyPolicy/GetKeyPolicy/DescribeKey` statement (removed in v2); F2 principal
existence/eventual consistency → C1 order corrected (IAM principals before the bucket policy and key policy; ≥ 60 s wait); F3 verifier could not
enrol MFA or change its password → `VerifierManageOwnMFAAndPassword` (own user only) + `VerifierReadPasswordPolicy`; F4 `Years` integer; F5 never
print `assume-role` credentials (`--query AssumedRoleUser`); F6 MFA condition satisfied only by `SerialNumber`+`TokenCode` of a TOTP device on
`AssumeRole` (U2F/passkeys unsupported for MFA-protected API access; `aws login` MFA context undocumented — not assumed; condition never removed).
Everything else in the ten files reviewed and left unchanged.

### Deliverables (committed on `feature/venue-native-and-product-v2`)
`PHASE2_PFA18C_EXECUTION_READINESS_PACKET.md` rewritten: §1 verification steps V0–V3; §2 single consolidated decision sheet D1–D8 (region;
irreversible retention — not pre-selected; O1 vs O4; layout with `652872010073` as the eventual workload member; names; ceremony MFA mechanism;
T3 interpretation for M5; C3/C4 order) with the pre-bootstrap vs pre-activation split and Model B temporary / Model A before T3; §3 cost
reconfirmed (usage-based; no $100 package; no recurring budget); §5 **C1 package** C1-0…C1-10 with resource/purpose, prerequisites, commands,
read-backs, refusal tests, abort conditions, cleanup limits, placeholder replacement rules; §6 110–114 sequence (venue-native lineage, no
merge-to-main, apply tree must contain 115–120, dry run must list exactly 110–114). Runbook: NG-1 and §F dated notes. Artifacts: F1/F3.

### SESSION 9 MUTATION LEDGER
AWS: **none** (two read-only calls attempted; both refused for an expired/changed login session; no `aws login` run by Claude). Production DB:
**none** (read-only queries only). KMS: **not created.** Secrets/ExternalId: **none generated or stored.** Organizations/accounts/IAM/CloudTrail/S3:
**none.** Migrations 110–114: **NOT applied.** Edges: **not deployed.** Config/flags: **unchanged.** Billing: **upgrade OWNER-CONFIRMED, not
API-verified; nothing purchased.** Repository: packet, execution record, runbook notes, README validation log, two artifact corrections.

---

## SESSION 10 — 2026-09-08 — PAID VERIFIED · C1 AUTHORIZED · PREFLIGHT DONE · LATER STAGES PREPARED (NO MUTATION)

Authorization received (owner, 2026-09-08): **PFA-18C M1/M2/M3 SETUP within the reviewed C1 package**, subject to its prerequisites and the
five remaining confirmations (R1 region, R2 names, R3 layout, R4 TOTP, R5 M5 scope + ordering). Owner-confirmed decisions: PAID/ACTIVE;
`jose-admin` engineering principal; root 0 keys + MFA; **Object-Lock COMPLIANCE 3 years**; **O1**; keep-Free-plan superseded; pay-as-you-go
(no $100 purchase, no recurring $100 budget). Not authorized: Organizations/accounts, CreateKey, DB insert, migrations, secrets, deploy, activation.
Pre-existing user edits preserved.

### Billing / identity / security — VERIFIED (CLAUDE-OBSERVED 2026-09-08T01:50:26Z; corroborates the OWNER-RETURNED output)
`sts get-caller-identity` → `arn:aws:iam::652872010073:user/jose-admin` (UserId `AIDAZQARUJFMXKFV5U5JY`). `freetier get-account-plan-state` →
**`PAID · ACTIVE · remaining credits 100.0 USD`**. `iam get-account-summary` → `AccountAccessKeysPresent 0 · AccountMFAEnabled 1 · Users 1 ·
Roles 3 · MFADevices 2`. **NG-1 CLEARED** (runbook dated note). No upgrade repeated; nothing purchased.

### C1-0a preflight — DONE (read-only, CLAUDE-OBSERVED 2026-09-08T01:51Z)
CloudTrail trails `[]` · S3 buckets `[]` · roles = the 3 service-linked only (no `SnatchIt*`) · users `["jose-admin"]` · KMS keys `[]` ·
`jose-admin` access keys `[]` · `jose-admin` MFA = **one passkey** (`u2f/user/jose-admin/jose-admin-touchid-…`), **no TOTP** · groups
`SnatchIt-admins` (AdministratorAccess) + direct `IAMUserChangePassword` · Organizations not in use · `head-bucket snatchit-audit-652872010073`
→ 404 (name free). Production DB (01:49:58Z): ledger 130 · tip 120 · 115–120 present · 110–114 absent · 0 keys · dark · census 149/83/31.
Repository: `614c53d` = origin; CI green (`34177096660`, `34177101087`); no PFA-18C/110–114/edge change since `1f3fc19`; admin `78a56fd`
`supabase/` identical to `ab3e17f`; local `supabase` CLI 2.115.0.

### Prepared this session
`m1_object_lock_configuration.json` Years = 3 (integer). Packet rewritten in place: §2 approvals + the single R1–R5 confirmation; §5 C1 execution
log (C1-0a done; C1-0b…C1-10 pending R1/R2/R4 and Device 2); §5b exact packages for C4 (apply tree `78a56fd`, dry run must list exactly
110–114, read-backs), C2 (CreateKey + independent binding proof), C3 (§6.1/§6.2 guarded bootstrap), C5, C6 (O1 secrets via env-file; dark
deploy with verify_jwt postures true/true/false), C7 (M5) — including the **open engineering question** that `kernel.issue_ticket_atoms`
refuses while issuance is dark, so the credential-sign half of M5 has no atom source without a custody-table test INSERT that would pin the
key; to be ruled on before C7.

### SESSION 10 MUTATION LEDGER
AWS: **none** (read-only calls only). Production DB: **none** (read-only). KMS: **not created.** Secrets/ExternalId: **none.**
IAM/S3/CloudTrail/Organizations: **none.** Migrations 110–114: **NOT applied.** Edges: **not deployed.** Flags: **unchanged.**
Billing: **PAID (verified), unchanged.** Repository: packet, runbook notes, README note, object-lock artifact (Years 3), this record.

---

## SESSION 11 — 2026-09-08 — C1 EXECUTION STARTED (C1-0b) · R5 CORRECTED · M5 PLAN · MODEL A PACKAGE (NO MUTATION)

Owner decisions confirmed 2026-09-08: R1 us-east-1 · R2 reviewed names at `6372538` · retention 3 y COMPLIANCE · O1 · R3 (`652872010073` future
workload member; Model B temporary; Model A before T3) · R4 (additional TOTP on `jose-admin`; serial/token on AssumeRole; passkey kept; MFA
condition never weakened) · 110–114 before the DB insert. **R5 CORRECTION recorded:** no pre-T3 exception; the prior packet text proposing that a
throwaway credential on a non-saleable test event is "not T3", and any attribution of such a ruling to the owner, is withdrawn (packet §2, runbook
C7 dated note). Canonical T3 quoted verbatim in the packet. C7/M5 PENDING until its procedure satisfies governance; no custody insert, issuance
flip, guard disable or bypass. The §5.3 challenge signature is a nonce signature required by the bootstrap, not a production credential.

### State (CLAUDE-OBSERVED)
Repo `6372538` = origin, CI green; admin `2459bdc` (docs addendum; `supabase/` identical to `ab3e17f`; CI green) — **C4 apply tree candidate is
now `2459bdc`**, to be re-verified on apply day. Production 02:14:51Z: ledger 130 · tip 120 · 115–120 present · 110–114 absent · 0 keys · dark.
AWS session valid as `jose-admin`; `list-mfa-devices jose-admin` → passkey only (`u2f/…touchid…`, enabled 2026-09-05) ⇒ C1-0b required.

### C1 log
- C1-0a preflight: DONE (session 10, read-only).
- **C1-0b TOTP enrolment: owner instructed** (console: Users → jose-admin → Security credentials → Assign MFA device → Authenticator app; QR/seed/
  codes never leave the owner's screen). Verification = `list-mfa-devices` shows the passkey + `arn:aws:iam::652872010073:mfa/<name>`. Pending.
- C1-1…C1-10: not started. Device 2 availability: **not yet determined** (must be physically separate and clean; M2 not satisfied until it runs).

### Prepared
Packet rewritten in place (§2 confirmations + R5 correction; §5 execution log; §5b C4 tree `2459bdc`; §5c Model A package with responsibilities,
order, SCP/bucket-policy artifacts under `pfa18c_artifacts/model_a/`, costs, refusal probes; §5d M5 test plan with the exact conflicting
requirements and the smallest clarification proposed for review). Runbook C7 dated note. README Model A entry.

### SESSION 11 MUTATION LEDGER
AWS: **none** (read-only calls only). Production DB: **none** (read-only). KMS/secrets/IAM/S3/CloudTrail/Organizations: **none.**
Migrations 110–114: **NOT applied.** Edges: **not deployed.** Flags: **unchanged.** Billing: PAID, unchanged. Repository: docs + 2 draft artifacts.

### C1-0b — TOTP enrolment on `jose-admin` — DONE 2026-09-08T02:38:37Z
OWNER-RETURNED: user `jose-admin`; TOTP serial `arn:aws:iam::652872010073:mfa/jose-admin-totp`; enabled 2026-09-08T02:38:37+00:00; the
existing Touch ID passkey remains enrolled. CLAUDE-OBSERVED corroboration (read-only `list-mfa-devices`, 02:40:41Z): two devices —
`arn:aws:iam::652872010073:mfa/jose-admin-totp` (2026-09-08T02:38:37Z) and `u2f/user/jose-admin/jose-admin-touchid-…` (2026-09-05).
**SERIAL for C1-9 = `arn:aws:iam::652872010073:mfa/jose-admin-totp`.** Enrolment does not prove the trust condition; that is tested at C1-9.
No seed, QR, code or password was exchanged.

### C1-1 — pre-mutation inspection 2026-09-08T02:40:41Z (read-only)
`get-role SnatchIt-KMS-Ceremony` → NoSuchEntity; `SnatchIt*` roles → none. Artifacts to apply: `m1_ceremony_role_trust.json` sha256
`89540f61…`, `m1_ceremony_role_policy.json` sha256 `1fddd53b…` (last changed at `239983e`; unchanged since the reviewed package). Owner instructed.

### C1-1 — IAM role `SnatchIt-KMS-Ceremony` — **VERIFIED 2026-09-08T02:42:58Z**
OWNER-RETURNED: `create-role` and `put-role-policy` completed successfully on the primary machine (owner-executed).
CLAUDE-OBSERVED read-backs (read-only, `snatchit-admin` profile): `Arn arn:aws:iam::652872010073:role/SnatchIt-KMS-Ceremony` · `RoleId
AROAZQARUJFMULUKHKRAG` · `CreateDate 2026-09-08T02:41:45Z` · `MaxSessionDuration 3600` · `Description "PFA-18C ceremony principal"` ·
trust policy `jq -S` diff vs `m1_ceremony_role_trust.json` (sha256 `89540f61…`) → **identical** · inline policy `pfa18c-ceremony` diff vs
`m1_ceremony_role_policy.json` (sha256 `1fddd53b…`) → **identical** · `list-role-policies` → `["pfa18c-ceremony"]` only · `list-attached-role-policies`
→ `[]`. Refusal tests deferred to C1-9 (need a role session). All comparisons pass ⇒ C1-1 VERIFIED.

### C1-2 — pre-mutation inspection 2026-09-08T02:42:58Z (read-only)
`get-user snatchit-kms-verifier` → NoSuchEntity; users = `["jose-admin"]`. Artifact `m2_verifier_policy.json` sha256 `3082cc74…` (F3 in force).
Managed policy `arn:aws:iam::aws:policy/SignInLocalDevelopmentAccess` exists (default v3, updated 2026-02-12). Owner instructed.

### C1-2 — IAM user `snatchit-kms-verifier` — **PARTIAL** (2026-09-08T03:12:09Z inspection)
OWNER-RETURNED: `create-user` succeeded; `put-user-policy pfa18c-verifier-readonly` **failed** — `LimitExceeded: maximum user inline policy size
2048` (the artifact is 2,544 characters compacted). CLAUDE-OBSERVED (read-only): user `arn:aws:iam::652872010073:user/snatchit-kms-verifier`
(UserId `AIDAZQARUJFM7MUXJXPMR`, created 02:44:06Z); inline policies `[]`; attached managed `[]`; groups `[]`; login profile none; access keys `[]`;
MFA `[]`; customer-managed policy `SnatchIt-KMS-Verifier-ReadOnly` does **not** exist (`list-policies --scope Local` → `[]`); quotas
`UserPolicySizeQuota 2048`, `PolicySizeQuota 6144`. **Correction (packaging only, F7):** apply the identical `m2_verifier_policy.json` (sha256
`3082cc74…`) as customer-managed policy `SnatchIt-KMS-Verifier-ReadOnly` and attach it; permissions and denies unchanged; no split. Owner instructed
(create-policy, attach ×2). The user is NOT recreated. C1-2 is not complete; M2 remains pending Device 2.

### C1-2 — IAM user `snatchit-kms-verifier` — **VERIFIED 2026-09-08T03:36:38Z**
OWNER-RETURNED: `create-policy SnatchIt-KMS-Verifier-ReadOnly`, `attach-user-policy` ×2 and the console password step completed.
CLAUDE-OBSERVED (read-only): policy `arn:aws:iam::652872010073:policy/SnatchIt-KMS-Verifier-ReadOnly` created 03:18:03Z, `DefaultVersionId v1`,
`AttachmentCount 1`, versions = [`v1` default]; `get-policy-version v1` document `jq -S` diff vs `m2_verifier_policy.json` (sha256 `3082cc74…`)
→ **identical**; user attachments = exactly [`…policy/SnatchIt-KMS-Verifier-ReadOnly`, `arn:aws:iam::aws:policy/SignInLocalDevelopmentAccess`];
inline `[]`; groups `[]`; access keys `[]`; login profile created 03:32:13Z (`PasswordResetRequired false`); MFA `[]` (Device 2 enrols its own at
C1-10). Refusal probes deferred to C1-10 (Device 2). C1-2 VERIFIED; **M2 not satisfied** until Device 2 runs.

### C1-3…C1-8 — preflight 2026-09-08T03:36:38Z (read-only)
`head-bucket snatchit-audit-652872010073` → 404 (free); buckets `[]`; trails `[]` (incl. shadow); runtime user/role → NoSuchEntity; present:
role `SnatchIt-KMS-Ceremony`, users `jose-admin`, `snatchit-kms-verifier`, local policy `SnatchIt-KMS-Verifier-ReadOnly`. Artifacts: bucket policy
`76addba3…`, object-lock `9a4c5a8d…` (Years 3), runtime user policy `a1cb8644…`, runtime trust `8ebd036a…` (ExternalId placeholder; filled locally
at C1-3). Dependency restated: the bucket policy (C1-6) names the runtime user/role ⇒ **C1-3 must precede C1-6**; C1-4/C1-5 have no principal
dependency and are reversible while the bucket is empty. Owner instructed: C1-4 + C1-5.

### C1-4 / C1-5 — audit bucket created and hardened — **VERIFIED 2026-09-08T03:41:07Z**
OWNER-RETURNED: `create-bucket --object-lock-enabled-for-bucket`, `put-public-access-block`, `put-bucket-encryption` completed.
CLAUDE-OBSERVED (read-only): `get-object-lock-configuration` → `ObjectLockEnabled: Enabled`, **no Rule** (retention applied at C1-7);
`get-bucket-versioning` → `Enabled` (MFADelete Disabled); `get-public-access-block` → BlockPublicAcls/IgnorePublicAcls/BlockPublicPolicy/
RestrictPublicBuckets all `true`; `get-bucket-encryption` → `AES256`, `BucketKeyEnabled false`, no `KMSMasterKeyID` (`BlockedEncryptionTypes: SSE-C`
reported by S3); `get-bucket-location` → `LocationConstraint null` (= us-east-1); no bucket policy yet; zero object versions. All PASS.
Bucket remains fully reversible (empty). Next: C1-3 (runtime principals; required before the C1-6 bucket policy).

### C1-3 — runtime user + role (O1, trust only) — **VERIFIED 2026-09-08T03:53:31Z**
OWNER-RETURNED: local file `~/pfa18c-local/m3_runtime_role_trust.filled.json` created (ExternalId length 64; value never shared); `create-user`,
`put-user-policy`, `create-role` completed. CLAUDE-OBSERVED (read-only, ≥ 344 s after creation): user `arn:aws:iam::652872010073:user/
snatchit-credential-sign-runtime` (UserId `AIDAZQARUJFMSTRL3SPZY`, 03:47:07Z); inline `pfa18c-runtime-assume-only` diff vs
`m3_runtime_user_policy.json` (sha256 `a1cb8644…`) → **identical**; attached `[]`, groups `[]`, **access keys `[]`**, no login profile. Role
`arn:aws:iam::652872010073:role/SnatchIt-CredentialSign-Runtime` (RoleId `AROAZQARUJFMVY3CGSUOG`, 03:47:46Z, MaxSessionDuration 3600); trust:
one statement, principal = the runtime user only, action `sts:AssumeRole` only, condition operators `[StringEquals]`, condition keys
`[sts:ExternalId]` only, ExternalId length 64 (**value redacted**); structure identical to `m3_runtime_role_trust.json` with the placeholder
masked; `list-role-policies` `[]`, `list-attached-role-policies` `[]` (permissions bound to the exact key ARN only at C2). Refusal test:
`sts assume-role` into the runtime role as `jose-admin` → **AccessDenied** ("not authorized to perform: sts:AssumeRole"). All PASS ⇒ C1-3 VERIFIED.
No access-key secret exists.

### C1-6 — audit bucket policy — **VERIFIED 2026-09-08T04:0xZ**
OWNER-RETURNED: `put-bucket-policy` completed. CLAUDE-OBSERVED (read-only): `get-bucket-policy` decoded and normalized (objects key-sorted,
scalar arrays sorted, statement order preserved) **equals** `m1_audit_bucket_policy.json` (sha256 `76addba3…`); the only raw difference is S3's
reordering of the four-ARN `Principal.AWS` array. Statements intact: `AWSCloudTrailAclCheck20150319` (Allow `cloudtrail.amazonaws.com`
`s3:GetBucketAcl`, `aws:SourceArn` = `arn:aws:cloudtrail:us-east-1:652872010073:trail/snatchit-audit-trail`); `AWSCloudTrailWrite20150319`
(Allow `s3:PutObject` on `AWSLogs/652872010073/*`, `bucket-owner-full-control`, same SourceArn); `DenyInsecureTransport` (Deny `s3:*`, Principal
`*`, `aws:SecureTransport=false`); `DenyCeremonyAndVerifierFromMutatingAuditEvidence` (Deny 17 mutation actions on bucket + objects for
`role/SnatchIt-KMS-Ceremony`, `user/snatchit-kms-verifier`, `role/SnatchIt-CredentialSign-Runtime`, `user/snatchit-credential-sign-runtime`).
Object Lock still `Enabled` with no rule; zero object versions. (Coordinator note: two earlier comparison attempts were tooling errors —
double-encoded JSON, then a normalizer that stringified statements — corrected before recording.) PASS ⇒ C1-6 VERIFIED.

### C1-7 — Object-Lock default retention — **VERIFIED 2026-09-08T04:01:20Z**
OWNER-RETURNED: `put-object-lock-configuration` completed. CLAUDE-OBSERVED (read-only): `get-object-lock-configuration` → `ObjectLockEnabled:
Enabled`, `Rule.DefaultRetention.Mode: COMPLIANCE`, `Years: 3` (artifact `9a4c5a8d…`); `list-object-versions` → no versions, no delete markers;
trails (incl. shadow) `[]`. PASS ⇒ C1-7 VERIFIED. The bucket remains empty and therefore still reversible; **C1-8 (start-logging) is the point at
which the first COMPLIANCE-locked objects (3 years) are written.** Owner instructed for C1-8.

### C1-8 — CloudTrail trail `snatchit-audit-trail` — configuration VERIFIED 2026-09-08T04:03:45Z; first delivery pending
OWNER-RETURNED: `create-trail`, `put-event-selectors`, `start-logging` completed. CLAUDE-OBSERVED (read-only): `describe-trails` →
`Name snatchit-audit-trail`, `TrailARN arn:aws:cloudtrail:us-east-1:652872010073:trail/snatchit-audit-trail`, `S3BucketName
snatchit-audit-652872010073`, `HomeRegion us-east-1`, `IsMultiRegionTrail true`, `IncludeGlobalServiceEvents true`, `LogFileValidationEnabled
true`, `KmsKeyId null`, `IsOrganizationTrail false`, `HasInsightSelectors false`; `list-trails` → exactly one trail. `get-event-selectors` →
`ReadWriteType All`, `IncludeManagementEvents true`, `DataResources []`, `ExcludeManagementEventSources []` (no KMS exclusion); no advanced
selectors. `get-trail-status` → `IsLogging true`, `StartLoggingTime 2026-09-08T04:02:41Z`, `LatestDeliveryTime null` (first delivery not yet
landed at 04:03:45Z), no delivery errors. Bucket: two zero-byte prefix markers (`AWSLogs/652872010073/CloudTrail/`, `…/CloudTrail-Digest/`,
04:02:28Z). **The first locked objects are now being written; the bucket is no longer reversible.** Delivery + per-object COMPLIANCE retention
(3 years) verification: pending (background poll).
Per-object lock on the first written objects (CLAUDE-OBSERVED 04:04:10Z, metadata only): `AWSLogs/652872010073/CloudTrail/` and
`…/CloudTrail-Digest/` → `ObjectLockMode COMPLIANCE`, `RetainUntilDate 2029-09-08T04:02:27Z` (= 3 years), `LegalHold null`, `SSE AES256`,
versioned. ⇒ **3-year COMPLIANCE retention is in force on delivered objects.** Log-file delivery confirmation still pending.
**First log-file delivery — CONFIRMED (CLAUDE-OBSERVED 04:08:09Z, metadata only, contents not read):** `LatestDeliveryTime 2026-09-08T04:07:28Z`,
no delivery error; object `AWSLogs/652872010073/CloudTrail/us-east-1/2026/09/08/652872010073_CloudTrail_us-east-1_20260908T0410Z_….json.gz`
(3,649 bytes) → `ObjectLockMode COMPLIANCE`, `RetainUntilDate 2029-09-08T04:07:28Z`, `LegalHold null`, `SSE AES256`. First digest delivery not
yet (hourly). ⇒ **C1-8 VERIFIED in full.** M1 (Model B) is *configured*; it is marked complete only after the C1-9 deny-set proof and the
Device-2 read-back (C1-10).

### C1-9 — MFA-conditioned AssumeRole test — evidence recorded 2026-09-08T04:29Z (C1-9 still PENDING the refusal probes)
OWNER-RETURNED: **T1** (`sts assume-role` as `jose-admin` via the `aws login` session, **no explicit MFA parameters**) **SUCCEEDED** →
`arn:aws:sts::652872010073:assumed-role/SnatchIt-KMS-Ceremony/pfa18c-ceremony`. **T1 is recorded as a success, NOT as an expected-denial pass.**
**T2** (`get-caller-identity --profile snatchit-ceremony`, CLI prompted for the `jose-admin-totp` code) SUCCEEDED with the same ARN.

CLAUDE-OBSERVED (read-only):
1. Live trust of `SnatchIt-KMS-Ceremony` re-read → **identical** to `m1_ceremony_role_trust.json`: one Allow, principal `user/jose-admin`, action
   `sts:AssumeRole`, conditions `Bool aws:MultiFactorAuthPresent=true` AND `StringEquals sts:RoleSessionName=pfa18c-ceremony`. Inline policy
   identical; no attached policies. Nothing was weakened; no access key was created.
2. CloudTrail event history (sanitized; CloudTrail never logs credentials/OTPs):
   - **T1** `AssumeRole` 2026-09-08T04:24:06Z, eventID `c1ae602c-…`: caller `IAMUser arn:aws:iam::652872010073:user/jose-admin`, temporary
     credential (`ASIA…`), **`sessionContext.attributes.mfaAuthenticated: "true"`**, session `creationDate 2026-09-08T01:45:15Z` (the `aws login`
     session), **requestParameters.serialNumber absent**, `roleSessionName pfa18c-ceremony`, no error; userAgent `md/command#sts.assume-role`.
   - **T2** `AssumeRole` 04:24:43Z, eventID `15b4cd6a-…`: same caller session (`mfaAuthenticated "true"`, created 01:45:15Z),
     **`serialNumber arn:aws:iam::652872010073:mfa/jose-admin-totp`**, `durationSeconds 3600`, no error; userAgent `md/command#sts.get-caller-identity`
     (the profile's automatic assume). Then `GetCallerIdentity` 04:24:43Z by `AssumedRole …/SnatchIt-KMS-Ceremony/pfa18c-ceremony`,
     `mfaAuthenticated "true"`, sessionIssuer = the ceremony role, eventID `3537a93f-…`.
   - The login session's other calls (e.g. `CreateOAuth2Token` 04:24:06Z) also carry `mfaAuthenticated "true"`, creation 01:45:15Z.
3. **Why T1 succeeded — verified vs inferred.** VERIFIED: the trust condition is present and unchanged; the `aws login` session used for T1 is
   recorded by CloudTrail as MFA-authenticated (created 01:45:15Z after the passkey console sign-in). INFERRED (consistent with the official
   condition-key semantics — the key is present for temporary credentials and is `false` when MFA was not used): IAM evaluated
   `aws:MultiFactorAuthPresent=true` from that session's MFA context, so no explicit SerialNumber/TokenCode was needed. LIMITATION: AWS does not
   log the evaluated condition context; a negative control (an AssumeRole from a non-MFA session) was **not** performed and will not be
   manufactured (no access key, no trust change). Consequence: both paths satisfy the condition today; the **reviewed mechanism (T2, explicit
   `--serial-number`/`--token-code`, recorded with the serial in CloudTrail) remains the ceremony procedure** because its MFA evidence is explicit
   and does not depend on the login session's state.
4. IAM policy simulation of the ceremony role's identity policy (read-only, `iam simulate-principal-policy`, run as `jose-admin`):
   **explicitDeny** — `cloudtrail:StopLogging/DeleteTrail/UpdateTrail/PutEventSelectors/AddTags`; `s3:DeleteBucketPolicy/PutBucketPolicy/
   PutBucketVersioning/PutBucketObjectLockConfiguration/PutLifecycleConfiguration/DeleteBucket` on the audit bucket; `s3:DeleteObject/
   DeleteObjectVersion/PutObject/PutObjectRetention/PutObjectLegalHold/BypassGovernanceRetention` on audit objects; `iam:GetUser/PutRolePolicy/
   CreateAccessKey/AttachRolePolicy`; `sts:AssumeRole`, `sts:AssumeRoleWithSAML`; `organizations:CreateOrganization/LeaveOrganization`;
   `account:GetContactInformation`; `sso:ListInstances`; `kms:ScheduleKeyDeletion/DisableKey/CreateAlias/CreateGrant/Decrypt/Encrypt/Verify/
   ImportKeyMaterial`. **allowed** — `kms:CreateKey` only with `KeySpec ECC_NIST_P256 ∧ KeyUsage SIGN_VERIFY ∧ KeyOrigin AWS_KMS ∧ MultiRegion
   false ∧ BypassPolicyLockoutSafetyCheck false` (RSA_2048 / MultiRegion true / Bypass true ⇒ implicitDeny); `kms:Sign/GetPublicKey/PutKeyPolicy/
   DescribeKey` only on keys tagged `snatchit:purpose=ticket-signing` (other tag ⇒ implicitDeny) and `Sign` only with `ECDSA_SHA_256`
   (`ECDSA_SHA_384` ⇒ implicitDeny); positive reads `cloudtrail:GetTrailStatus/DescribeTrails`, `s3:GetBucketPolicy/
   GetBucketObjectLockConfiguration`, `kms:ListKeys`, `sts:GetCallerIdentity` allowed.
Remaining for C1-9: the owner-run live probes as the role (below), then CloudTrail evidence of their `AccessDenied` outcomes.

### C1-9 — live probes as the ceremony role (session `pfa18c-ceremony`, `mfaAuthenticated true`) — 2026-09-08T04:31–04:34Z
OWNER-RETURNED + CLAUDE-OBSERVED (CloudTrail event history, sanitized):
- Positive controls: `GetTrailStatus` 04:31:02Z allowed (eventID `9cac770a-…`); `kms ListKeys` 04:31:10Z allowed, `[]` (eventID `c2ef9696-…`). PASS.
- **P1** `cloudtrail:AddTags` on the trail 04:31:22Z → `AccessDenied` "**with an explicit deny in an identity-based policy**" (eventID `f00a1ecf-…`). PASS.
- **P2** `s3:PutBucketVersioning` on the audit bucket 04:32:02Z → `AccessDenied` "**with an explicit deny in a resource-based policy**" (eventID
  `7d56dfd9-…`) — the bucket policy's deny was cited; the identity-policy deny for the same action is proven separately by the simulator. PASS.
- **P3** `kms:CreateAlias` targeting the all-zero dummy key → **`NotFoundException`**, not `AccessDenied`. **Recorded as INCONCLUSIVE — neither a
  pass nor evidence that the deny is missing.** (CloudTrail event: pending index at the time of writing; recorded below when available.)
  Analysis (read-only): the live policy statement `DenyKeyLifecycleMutationDuringCeremony` is unchanged and lists `kms:CreateAlias` with
  `Resource "*"`; the whole inline policy is still identical to the artifact; the IAM simulator returns **explicitDeny** for `kms:CreateAlias`
  on any key ARN. Per the CreateAlias API reference, the operation requires `kms:CreateAlias` **on the alias (IAM policy) and on the KMS key
  (key policy)**, "A valid KMS key is required. You can't create an alias without a KMS key", and `NotFoundException` = "the specified entity
  or resource could not be found". The request therefore named a resource that does not exist, so the key-policy half of the authorization
  could not be evaluated and KMS answered with resource validation. What the evidence establishes: the request was rejected because the key
  does not exist. What it does **not** establish: whether the identity-policy explicit deny was consulted for this request — AWS documents no
  evaluation order between resource validation and authorization, and none is assumed here. The probe design was engineering's error (it
  predicted `AccessDenied` for a non-existent target); it is withdrawn as a discriminating test. No real key was created and no other key was
  targeted to force a denial.
  Acceptance-criteria determination: the ratified controls require the deny-set and key policy to be **read back and verified from the M2
  device** (ratification items 2–3, M3 "prove by reading the committed key policy from the second device"); live refusal probes are engineering's
  additional evidence, not a ratified criterion. Standing evidence for the KMS lifecycle deny = identical policy read-back + simulator
  explicitDeny. A **discriminating live test exists only once a key exists**: at C2, after CreateKey, the ceremony role attempts
  `kms create-alias --target-key-id <D4>` → expected `AccessDenied` with an explicit identity-policy deny (if wrongly allowed the effect is one
  removable alias, no cryptographic or lifecycle impact); likewise `kms verify` with the proof signature → expected `AccessDenied`. This
  "P3′ at C2" is added to the C2 package. No safe KMS mutation probe against a non-existent key discriminates; `kms generate-random` (no
  resource) can only show the absence of a broad Allow (implicit deny), which is weaker evidence and optional.
- P4 (`iam get-user` as the role) and P5 (`sts assume-role` into the runtime role as the role): outcome not yet returned by the owner / not yet
  indexed at the time of writing.
  P3 CloudTrail event (indexed 04:34:57Z, sanitized): `CreateAlias` 2026-09-08T04:32:32Z by `assumed-role/SnatchIt-KMS-Ceremony/pfa18c-ceremony`
  (`mfaAuthenticated true`), `errorCode NotFoundException`, `errorMessage "Key 'arn:aws:kms:us-east-1:652872010073:key/00000000-0000-0000-0000-
  000000000000' does not exist"`, request parameters not recorded by KMS for this failure, eventID `a99105a8-e773-44fd-915b-377706050837`. The
  event carries no `AccessDenied` and no authorization-failure text — consistent with the analysis above: resource validation answered; the
  identity deny's evaluation for this request is not observable. P3 stays INCONCLUSIVE. P4/P5: no `GetUser`/`AssumeRole` events by the
  ceremony role are indexed as of 04:35Z (not run, or not yet indexed).
- **P4** `iam:GetUser jose-admin` as the ceremony role → OWNER-RETURNED `AccessDenied` **with an explicit identity-policy deny**. PASS (CloudTrail
  corroboration: pending index at the time of writing; appended when available).
- **P5** `sts:AssumeRole` into `SnatchIt-CredentialSign-Runtime` as the ceremony role → OWNER-RETURNED `AccessDenied`; the error does not name
  the denying policy (the runtime trust would refuse this caller regardless). Retained as **non-discriminating** evidence. (CloudTrail
  corroboration pending.)

### C1-9 — status 2026-09-08T04:38Z: completed checks and limits
Completed: T2 MFA-conditioned AssumeRole via serial+token (serial logged in CloudTrail); T1 recorded as a success explained by the
MFA-authenticated login session (not a denial pass; negative control not manufactured); live trust and policy re-read identical; positive
controls; P1 (CloudTrail deny, explicit identity deny); P2 (S3 deny, explicit bucket-policy deny); P4 (IAM deny, explicit identity deny);
P5 (STS deny, non-discriminating); IAM simulator explicitDeny for the entire deny-set incl. `organizations:*`, `account:*`, `sso:*`,
`sts:AssumeRole*`, KMS lifecycle/crypto, and correct scoping of CreateKey/Sign/PutKeyPolicy. **Limits:** P3 (`kms:CreateAlias`) INCONCLUSIVE —
no live evidence for the KMS-lifecycle deny is obtainable without a key; **P3′ is deferred to C2 (separately authorized)**; destructive
denies (`StopLogging`, `DeleteTrail`, `DeleteBucketPolicy`, non-conforming `CreateKey`) are proven by simulation only, by design.
**M1 (Model B) status:** configured and live-probed from the ceremony role; **complete only after the Device-2 read-back (C1-10)**, which the
ratification makes the acceptance criterion.
P4/P5 CloudTrail corroboration (indexed 04:39:13Z, sanitized): **P4** `iam GetUser` 04:36:16Z by `assumed-role/SnatchIt-KMS-Ceremony/
pfa18c-ceremony` (`mfaAuthenticated true`) → `AccessDenied` "… not authorized to perform: iam:GetUser on resource: user jose-admin **with an
explicit deny in an identity-based policy**" (eventID `1a578c07-…`). **P5** `sts AssumeRole` 04:36:50Z by the same session → `AccessDenied`
"… not authorized to perform: sts:AssumeRole on resource: arn:aws:iam::652872010073:role/SnatchIt-CredentialSign-Runtime" — no denying policy
named (eventID `3c27859f-…`); non-discriminating, as recorded. C1-9 closes with these limits: P3 inconclusive / P3′ at C2; destructive denies by
simulation only. C1-10 package prepared (packet §5a′); Device-2 availability to be confirmed by the owner before D2-1.

### C1-10 — Device-2 retrieval manifest (pinned 2026-09-09T02:53:40Z; read-only verification)
OWNER-RETURNED: Device 2 authenticated as `snatchit-kms-verifier` (`aws login --profile verifier`) — CloudTrail corroboration at D2-8.
Manifest commit: **`c4f562dad36ffcdcacb1fe3ba1387f7ab1bbf4cd`** on `feature/venue-native-and-product-v2` of `https://github.com/SnatchIt-app/snatchit`
(**public** repository; commit present on GitHub, committer date 2026-09-08T04:40:01Z; local HEAD = origin tip; no working-tree change to any
listed file). Every SHA-256 below was computed from the committed blob (`git show <sha>:<path>`) and matched byte-for-byte against the bytes
GitHub serves at that ref (`contents/<path>?ref=<sha>`, raw).
| Path | SHA-256 |
|---|---|
| docs/release/pfa18c_artifacts/m1_ceremony_role_trust.json | 89540f612449a3e540f851f1e62082b2c3263e2a9849f6b0f4fcbbec41baf4b7 |
| docs/release/pfa18c_artifacts/m1_ceremony_role_policy.json | 1fddd53beee238063da99a26db3f301c546ee9c111685c5a5f630e0f930bd4d5 |
| docs/release/pfa18c_artifacts/m2_verifier_policy.json | 3082cc74824ef68c47cd2fc39caf0d45b7765f2880936cdb8bb0d08a2cb46889 |
| docs/release/pfa18c_artifacts/m3_runtime_user_policy.json | a1cb864406c73fc674fc264e8a73efe93ebdbbf5f4aed0a05a9ee94641569c9f |
| docs/release/pfa18c_artifacts/m3_runtime_role_trust.json (placeholder; structure comparison only) | 8ebd036a5a71c914b5c8f44589505c9ba71dc5907e0e856403ed0961e5412fd8 |
| docs/release/pfa18c_artifacts/m1_audit_bucket_policy.json | 76addba388521b9c04806ab81d560e1563ae59a75b33ea3fe61ed0cd2b4392f0 |
| docs/release/pfa18c_artifacts/m1_object_lock_configuration.json | 9a4c5a8dad1f6bc7f6a8cb5510e3f8af9e5ec5065fedf75c0997e48698ef7ab0 |
| docs/release/pfa18c_artifacts/m3_runtime_role_policy.json (C2; placeholder ARN) | bb3a2c4f86f532d2d0743e4755e9aaa67fd77d3997a820c211efbb90b0517b52 |
| docs/release/pfa18c_artifacts/kms_key_policy_v1_binding_proof.json (C2) | e0560a960a28d146476bbdfd35654949f9aeebad9ce69d7cc488d1f5d7515dc1 |
| docs/release/pfa18c_artifacts/kms_key_policy_v2_final.json (C2) | 430677d0510ed67987d04a012223fe947ccd0fa1948044215cb52dbf775b2d9d |
| docs/release/pfa18c_artifacts/README.md | 505fe850bdcf6cc8336d8e53d37514eea4a28df40810f24475096f76d813443c |
| docs/release/PHASE2_PFA18C_EXECUTION_READINESS_PACKET.md (C1-10 procedure §5a′) | 8b11d567c758b490e3a4645e44a8f2e072e46e0b3d4e1344afd2b0bbc6ce34ae |
| docs/release/PHASE2_PFA18C_SINGLE_FOUNDER_KMS_BOOTSTRAP_EXECUTION.md (record as of c4f562d) | eb8b246292105f15ef4e7ab73b75436f21ad8b6a95b513aed4ce8d8ce58c0fe7 |
Excluded by design: the filled runtime trust file, the ExternalId, any credential or session data (none are committed anywhere).

---

## SESSION 12 — 2026-09-09 — C1-10 DEVICE-2 RESULTS (OWNER-RETURNED) · D2-8 COORDINATOR CORROBORATION PENDING (NO MUTATION)

Scope: coordinator verification + governance recording only. C2 NOT begun; no KMS key; no AWS/DB/flag/secret/migration mutation. PFA-18A parked.
Full report: `docs/release/PHASE2_PFA18C_C1_PHASE1_GATE_REPORT.md`.

### D2-3 (OWNER-RETURNED, 2026-09-09): Device 2 = physically separate Mac; AWS CLI 2.36.41; jq 1.7.1; LibreSSL 3.3.6; no primary-machine
credentials/files copied; console login as `snatchit-kms-verifier`; Device-2 passkey enrolled; `aws login --profile verifier` → `Account
652872010073`, `Arn arn:aws:iam::652872010073:user/snatchit-kms-verifier`.
### D2-4 — PASS (OWNER-RETURNED): 10/10 files from `c4f562dad36ffcdcacb1fe3ba1387f7ab1bbf4cd`; all SHA-256 matched the manifest (session 11 pin,
coordinator-verified against committed blobs + GitHub bytes); no C2-only artifact downloaded.
### D2-5 — PASS (OWNER-RETURNED): ceremony role trust/policy matched, no managed policies; verifier managed policy matched, attachments exactly
`SnatchIt-KMS-Verifier-ReadOnly` + `SignInLocalDevelopmentAccess`, inline `[]`, access keys `[]`, passkey present; runtime user policy matched,
access keys `[]`; runtime role trust structure matched (`ExternalIdLength 64`, **value never displayed**), inline `[]`, managed `[]`; bucket policy
equivalent; PAB 4×true; SSE-S3 AES256; Object Lock COMPLIANCE 3 y; versioning Enabled; trail multi-region, validation on, no KMS key, logging,
no delivery error, selectors correct. All values equal the coordinator's 2026-09-08 read-backs.
### D2-6 — PASS (OWNER-RETURNED): CreateAlias(non-existent key) → NotFoundException (non-discriminating, as specified); PutBucketVersioning →
AccessDenied (explicit deny, `SnatchIt-KMS-Verifier-ReadOnly`); AssumeRole SnatchIt-KMS-Ceremony → AccessDenied; CreateAccessKey (self) →
AccessDenied (explicit deny); AddTags → AccessDenied. No key created.
### D2-7 — PASS with classified variance (OWNER-RETURNED): ceremony AssumeRole 04:24:06Z (mfa true, serial null = T1) and 04:24:43Z (mfa true,
serial `…:mfa/jose-admin-totp` = T2) seen from Device 2; root activity `[]`; refusal events 04:31:22Z AddTags / 04:32:02Z PutBucketVersioning /
04:32:32Z CreateAlias(NotFound) / 04:36:16Z GetUser / 04:36:50Z AssumeRole — match session-11 event IDs. **Variance:** broader `jose-admin` lookup
also showed `DescribeEventAggregates`, `ListNotificationHubs`, `ListManagedNotificationEvents`, `GetAccountPlanState`, `DescribeRegions`,
`GetAccountColor` — classified as acceptable console background/telemetry **reads** (Health, User Notifications, Free Tier, EC2 region list,
console settings); D2-7 expectation amended to "non-read-only jose-admin events = exactly the C1 setup set"; `readOnly:true` confirmation is a
D2-8 item.
### Final Device-2 safety check (OWNER-RETURNED): `kms list-keys` → `[]`.
### D2-8 — coordinator corroboration — **PENDING / BLOCKED (CLAUDE-OBSERVED 2026-09-09T03:34Z):** every read-only CloudTrail/IAM/KMS query
via `snatchit-admin` returned "Your session has expired. Please reauthenticate using 'aws login'" (the 2026-09-08T01:45Z login session lapsed).
Production DB read-only (03:34:37Z): ledger 130 · tip 120 · 110–114 absent · `kernel.signing_key` 0 · guard absent · tickets 0 · flags dark —
unchanged. Outstanding D2-8 checks: verifier ConsoleLogin/EnableMFADevice/CreateOAuth2Token/GetCallerIdentity under the verifier identity with
MFA; D2-6 outcomes under the verifier identity; D2-5 reads only; jose-admin non-read-only events = C1 set + `readOnly:true` on the variance list;
root none; KMS `[]` + no CreateKey event.
### Governance status: **M2 NOT YET SATISFIED · M1 (Model B) NOT marked complete · C1 PHASE-1 GATE OPEN** (pending D2-8).
**C2 has NOT begun; it requires the separate exact owner authorization "AUTHORIZE PFA-18C CREATEKEY".** C4 (110–114) precedes C3 and needs its own
authorization.

### SESSION 12 MUTATION LEDGER
AWS: **none** (read-only calls attempted; all refused — expired session). Production DB: **none** (one read-only query). KMS: **not created.**
Secrets/keys/IAM/S3/CloudTrail/Organizations: **none.** Migrations/edges/flags: **unchanged.** Repository: this record + the gate report.

---

## SESSION 13 — 2026-09-09 — D2-8 COORDINATOR CORROBORATION (READ-ONLY) · M2 BLOCKED ON VERIFIER MFA POSTURE (NO MUTATION)

Scope: coordinator verification + governance recording only. C2 NOT begun; no KMS key; no AWS/DB/flag/secret/migration mutation. PFA-18A parked.
Coordinator session: `jose-admin` re-established by the owner (CloudTrail `CheckMfa` 03:39:38Z + `ConsoleLogin` 03:39:49Z, `MFAUsed Yes`, passkey).
Full report (revision 2): `docs/release/PHASE2_PFA18C_C1_PHASE1_GATE_REPORT.md`.

### D2-8 results (CLAUDE-OBSERVED 2026-09-09T03:41–03:46Z unless stated)
1. **Verifier identity/posture — FAIL (blocker).** `ConsoleLogin` for `snatchit-kms-verifier` at **2026-09-09T02:44:39Z in us-east-2**, **`MFAUsed: No`**,
   Success (eventID `c6596194…`) — the only verifier ConsoleLogin in any enabled region (fan-out across all regions; verifier events exist only in
   us-east-1 (88) and us-east-2 (7)). `EnableMFADevice` (passkey self-enrolment, F3) 02:47:51Z success (eventID `4c3706e4…`) — **the only successful
   verifier mutation**. `aws login`: `AuthorizeOAuth2Access` + `CreateOAuth2Token` 02:49:44Z (refreshes 03:07:28Z, 03:18:13Z, 03:29:00Z);
   `GetCallerIdentity` 02:50:06Z / 03:23:01Z. **All 88 us-east-1 verifier events carry `mfaAuthenticated: "false"`; none `"true"`.** No later MFA
   sign-in exists. ⇒ handoff §F.2 / packet §5a′ D2-3 posture condition NOT met. Live verifier state: passkey
   `u2f/user/snatchit-kms-verifier/verifier-device2-passkey-6UJX6DTACNAOFIWOQQHF7RNEOA` (02:47:51Z); access keys `[]`; **no successful
   CreateAccessKey**; attachments exactly `SnatchIt-KMS-Verifier-ReadOnly` (v1, AttachmentCount 1, unchanged since 2026-09-08T03:18:03Z) +
   `SignInLocalDevelopmentAccess`; inline `[]`; groups `[]`.
   us-east-2 verifier events (7, itemized): 02:44:39Z ConsoleLogin (MFAUsed No; LoginTo console home, oauth-flow); 02:44:46Z ec2 DescribeRegions
   ×1 (Client.UnauthorizedOperation), health DescribeEventAggregates ×3 (AccessDenied); 02:44:47Z notifications ListNotificationHubs (AccessDenied);
   02:45:45Z ec2 DescribeRegions (UnauthorizedOperation) — all read-only console background, all denied.
2. **D2-6 probes — PASS, corroborated under the verifier identity (us-east-1):** CreateAlias 03:20:13Z NotFoundException (`a7899dcf…`, non-
   discriminating); PutBucketVersioning 03:23:31Z AccessDenied (`c793341a…`); AssumeRole 03:24:14Z AccessDenied (`a6ed84a8…`); CreateAccessKey
   03:24:49Z AccessDenied (`14c7eee4…`); AddTags 03:25:41Z AccessDenied (`12dcc545…`). None succeeded.
3. **D2-5 reads — PASS:** IAM Get/List (GetRole ×4, GetRolePolicy, ListAttachedRolePolicies ×2, GetPolicy, GetPolicyVersion, ListAttachedUserPolicies,
   ListUserPolicies, ListAccessKeys ×2, ListMFADevices, GetUserPolicy, ListRolePolicies), S3 Get ×5, CloudTrail DescribeTrails/GetTrailStatus/
   GetEventSelectors, LookupEvents ×11, kms ListKeys 03:32:27Z. Console background reads 02:44–02:47Z all `readOnly true` (mostly AccessDenied;
   `GetAccountPasswordPolicy` NoSuchEntity = no custom account password policy — hardening note, out of scope). Nothing outside the envelope.
4. **jose-admin — PASS:** non-read-only events since 2026-09-08T02:40Z = exactly the authorized C1 set (CreateRole 02:41:45, PutRolePolicy 02:41:57,
   CreateUser 02:44:06, PutUserPolicy→LimitExceeded 02:44:15, CreatePolicy 03:18:03, AttachUserPolicy 03:18:10/03:18:21, CreateLoginProfile 03:32:14,
   CreateBucket 03:39:06, PutBucketPublicAccessBlock 03:39:16, PutBucketEncryption 03:39:24, CreateUser 03:47:07, PutUserPolicy 03:47:28, CreateRole
   03:47:46, PutBucketPolicy 03:56:17, PutObjectLockConfiguration 04:00:44, CreateTrail 04:02:27, PutEventSelectors 04:02:33, StartLogging 04:02:41;
   2026-09-09 CheckMfa 03:39:38 + ConsoleLogin 03:39:49 = coordinator re-login). TOTP enrolment `CreateVirtualMFADevice` 02:37:28Z / `EnableMFADevice`
   02:38:38Z precede the window (C1-0b). **Variance confirmed read-only** (`readOnly true`, `managementEvent true`, no error, console UA):
   DescribeEventAggregates ×6, ListNotificationHubs ×3, ListManagedNotificationEvents ×42, GetAccountPlanState ×3, DescribeRegions ×2,
   GetAccountColor ×3 — acceptable console background. D2-7 expectation amended: non-read-only jose-admin events = C1 set; read-only console
   background reads acceptable.
5. **Root/KMS — PASS in window:** root since 02:40Z `[]`; `kms list-keys` `[]`; no CreateKey/ScheduleKeyDeletion/PutKeyPolicy/DisableKey since
   2026-09-08T00:00Z. **Out-of-window root observation (flagged for owner acknowledgement):** `PasswordRecoveryRequested` 2026-09-08T01:17:49Z and
   `PasswordRecoveryCompleted` 01:18:21Z (Root) — before the C1 window and the trail; consistent with the owner's stated root use for billing;
   root still 0 access keys + MFA. Inventory as expected; runtime role has no permissions; access keys `[]` on all three users; digest delivery
   2026-09-09T03:13:09Z.
6. **Production — PASS (03:42:25Z):** ledger 130 · tip 120 · 110–114 absent · signing_key 0 · guard absent · tickets 0 · door sessions 0 · flags dark.

### Gate decision
**M2 NOT SATISFIED · M1 (Model B) NOT marked complete · C1 PHASE-1 GATE OPEN.** Blocker: verifier working session not MFA-authenticated.
Remediation R-M2 (Device 2 only): `aws logout --profile verifier`; console sign-out; sign in again with password + passkey (expect ConsoleLogin
`MFAUsed Yes`, `MFAIdentifier` = the verifier's u2f ARN); `aws login --profile verifier`; `get-caller-identity`; re-run D2-6, D2-5 and D2-7 (no
re-download; D2-4 stands); coordinator re-corroborates `mfaAuthenticated "true"` and, if held, records M2 SATISFIED / M1 MODEL B COMPLETE /
C1 PHASE-1 GATE CLOSED. **C2 NOT BEGUN** — requires the separate exact owner authorization "AUTHORIZE PFA-18C CREATEKEY"; C4 (110–114) first,
under its own authorization.

### SESSION 13 MUTATION LEDGER
AWS: **none** (read-only CloudTrail/IAM/KMS/S3/STS calls only). Production DB: **none** (one read-only query). KMS: **not created.** Secrets/keys/
IAM/S3/CloudTrail/Organizations: **none.** Migrations/edges/flags: **unchanged.** Repository: this record + gate report revision 2.

---

## SESSION 14 — 2026-09-09 — R-M2 REMEDIATION CORROBORATED · M2 SATISFIED · M1 MODEL B COMPLETE · C1 PHASE-1 GATE CLOSED (NO MUTATION)

Scope: coordinator read-only corroboration + governance recording. C2 NOT begun; no KMS key; no AWS/DB/flag/secret/migration mutation. PFA-18A parked.
Full report (revision 3): `docs/release/PHASE2_PFA18C_C1_PHASE1_GATE_REPORT.md`.

### R-M2 (OWNER-RETURNED): Device 2 ran `aws logout --profile verifier`, signed out of the console, signed in again as `snatchit-kms-verifier`
with password + the enrolled passkey `verifier-device2-passkey`, ran `aws login --profile verifier --region us-east-1` (identity `Account
652872010073`, `Arn arn:aws:iam::652872010073:user/snatchit-kms-verifier`), re-ran D2-6 (PutBucketVersioning/AssumeRole/CreateAccessKey/AddTags →
AccessDenied; CreateAlias → NotFoundException, non-discriminating), D2-5 (all comparisons/state checks passed), D2-7 (expected results), and
`kms list-keys` → `[]`.

### D2-8 corroboration (CLAUDE-OBSERVED 2026-09-09T04:02:56Z–04:03:13Z, read-only, sanitized)
1. New verifier `ConsoleLogin` (us-east-2): 03:51:35Z (`96ff9126…`) and 03:55:08Z (`64488a49…`), both **`MFAUsed: Yes`**, `MFAIdentifier =
   arn:aws:iam::652872010073:u2f/user/snatchit-kms-verifier/verifier-device2-passkey-6UJX6DTACNAOFIWOQQHF7RNEOA`, Success; `CheckMfa` 03:50:59Z,
   03:51:25Z, 03:54:30Z precede them.
2. New `aws login`: `AuthorizeOAuth2Access` + `CreateOAuth2Token` 03:55:45Z (`62f3281b…`, `e2d682a3…`), session created 03:55:08Z,
   **`mfaAuthenticated: "true"`**; `GetCallerIdentity` 03:56:06Z (`df3c879f…`) `"true"`. Distribution after 03:46Z: **84 events `"true"`, 0 `"false"`,
   0 successful mutations.**
3. D2-6 under the verifier identity, all `mfaAuthenticated "true"`: PutBucketVersioning 03:56:53Z AccessDenied (`f692cf37…`); AssumeRole 03:57:20Z
   AccessDenied (`2f6579df…`); CreateAccessKey 03:57:43Z AccessDenied (`f390806f…`); AddTags 03:58:44Z AccessDenied (`a5fe0f75…`); CreateAlias
   03:59:45Z NotFoundException (`c9b23820…`). No success.
4. D2-5 reads 03:59:56–04:00:10Z (IAM Get/List ×14, S3 Get ×5, CloudTrail Describe/Get ×3) — all read-only, no errors; D2-7 LookupEvents ×7
   04:00:45–04:00:49Z; `kms ListKeys` 04:01:00Z (`7cebef0d…`). Nothing outside the envelope.
5. Verifier state: access keys `[]`; attachments exactly `SnatchIt-KMS-Verifier-ReadOnly` + `SignInLocalDevelopmentAccess`; inline `[]`; groups
   `[]`; MFA = the single passkey; policy v1 unchanged (2026-09-08T03:18:03Z). Root since 2026-09-08T02:40Z `[]`. KMS `list-keys` `[]`; no
   CreateKey/PutKeyPolicy/ScheduleKeyDeletion/DisableKey since 2026-09-08T00:00Z. `jose-admin`: no non-read-only events since 03:46Z. Inventory
   unchanged; access keys `[]` on all three users; runtime role has no permissions. Trail logging, no delivery error.
6. Production (04:03:13Z): ledger 130 · tip 120 · 110–114 absent · `kernel.signing_key` **0** · guard absent · tickets 0 · door sessions 0 · flags
   dark (issuance/scanning/monitor false; fingerprint/max_not_after null). No trust-root bootstrap occurred.

### GATE DECISION (all M2 completion conditions satisfied — handoff §F items 1–7)
**M2 SATISFIED.**
**M1 MODEL B COMPLETE** (audit plane configured, ceremony-probed at C1-9, independently read back from the MFA-authenticated verifier on the
physically separate Device 2; residual: P3′ live KMS-lifecycle deny test at C2; Model B temporary — Model A required before T3).
**C1 PHASE-1 GATE CLOSED** (C1-0a … C1-10 verified; artifacts at `c4f562d…`; execution record sessions 10–14).
**C2 NOT BEGUN** — CreateKey requires the separate exact owner authorization **"AUTHORIZE PFA-18C CREATEKEY"**. Confirmed ordering preserved:
**C4 (migrations 110–114) before the trust-root DB insert (C3), under "AUTHORIZE PFA-18C MIGRATIONS 110-114"**; neither executed.
Carried forward: C7/M5 pending governance clarification (packet §5d); Model A package (packet §5c) not authorized; root password-recovery events
2026-09-08T01:17–01:18Z (out of window) awaiting owner acknowledgement; no account password policy (hardening note).

### SESSION 14 MUTATION LEDGER
AWS: **none** (read-only CloudTrail/IAM/KMS/S3/STS only). Production DB: **none** (one read-only query). KMS: **not created.** Secrets/keys/IAM/S3/
CloudTrail/Organizations: **none.** Migrations/edges/flags: **unchanged.** Repository: this record + gate report revision 3 + packet log row.

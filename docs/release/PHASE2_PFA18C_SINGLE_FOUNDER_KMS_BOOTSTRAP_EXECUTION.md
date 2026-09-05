# PHASE 2 — PFA-18C SINGLE-FOUNDER AWS KMS / ES256 TRUST-ROOT BOOTSTRAP — EXECUTION RECORD

**Status legend:** PREPARATION · CEREMONY · COMPLETED · NOT COMPLETED · ABORTED · PARTIAL STATE

> Interactive, human-executed. The founder runs **every** AWS and production-database mutation.
> Claude is coordinator / instruction generator / read-back verifier / adversarial checker only.
> No secret material is ever recorded here (no access keys, secret keys, session tokens, DB passwords,
> service-role secrets, private keys, auth cookies, or password-bearing connection strings).

---

## OVERALL STATE

```
OVERALL:                 PREPARATION — AWS baseline inventory RECEIVED (owner-returned, 2026-09-05); M1/M2/M3
                         NOT STARTED; CreateKey NO-GO pending plan-type verification + owner decisions
KMS KEY CREATED:         NO
SIGNING KEYS IN PROD:    0
PRODUCTION MUTATION:     NONE
NATIVE ISSUANCE:         FALSE
NATIVE SCANNING:         FALSE
LAST UPDATED (UTC):      2026-09-05 20:30Z
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
  credential-sign edge's sign-after-verify `atob()`s it as bare base64 SPKI DER; `atob` throws on PEM armor
  (demonstrated: `InvalidCharacterError`) → every credential would be refused; the column is immutable.
  Required before M5/issuance; strongly recommended before bootstrap. NOT fixed this session (no code change).
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

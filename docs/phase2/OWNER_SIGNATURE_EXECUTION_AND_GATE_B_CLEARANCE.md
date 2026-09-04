============================================================
SNATCH IT — OWNER SIGNATURE EXECUTION + GATE B CLEARANCE
============================================================

2026-09-04 · governance execution only · NO PRODUCTION MUTATION · NO CODE / NO MIGRATION

> The owner provided the five pending governance approvals and accepted the Phase-2 24-hour observation
> close-out in-session on 2026-09-04. This session RECORDED those approvals in the governance files,
> verified the resulting state, and re-evaluated Gate B. It executed nothing against production
> (read-only inspection only), changed no code/migration/edge byte, and created no migration 110. Owner
> signatures ratify governance/engineering decisions only; they do NOT authorize any production action.

REPOSITORY

BRANCH:                 feature/venue-native-and-product-v2
ENTRY HEAD:             4da04d3 (preflight docs)
FINAL GOVERNANCE HEAD:  <recorded post-commit below> (owner-signature execution + this report; docs only)
CODE RELEASE CANDIDATE: 5721a41 (UNCHANGED — every migration/rollback/edge/app byte is byte-identical to
                        5721a41; all commits since are documentation/governance only)
PR:                     #52 — OPEN, MERGEABLE
CI:                     GREEN on the exact code RC 5721a41 (run 33835866681) AND on the governance head
                        (run 33837011432 — "docs(preflight)…" success). CODE RC vs GOVERNANCE HEAD are
                        distinct: the code RC is the frozen artifact that will be deployed; the governance
                        head only adds signatures/reports and moves no production-bearing byte.
WORKTREE:               clean except the governance docs written this session (+ the earlier untracked
                        Tickets coordination note, unrelated)

------------------------------------------------------------
OWNER SIGNATURES
------------------------------------------------------------

Recorded verbatim in POST_FREEZE_AMENDMENTS.md → "OWNER SIGNATURES RECORDED — 2026-09-04", and reflected
on each PFA's STATUS line. Index: OWNER_SIGNATURE_PACKAGE_20260904.md (now SIGNED).

PFA-18B:            OWNER SIGNATURE: APPROVED (2026-09-04).  STATUS: SATISFIED / RATIFIED.
                   (single platform_admin + aal2 revoke un-park; force-close + #44; no open on revoked
                   trust; provision/rotate STAY parked. Governance only.)
PFA-26-UNPARK:     OWNER SIGNATURE: APPROVED (2026-09-04).  STATUS: SATISFIED / RATIFIED.
                   (pgcrypto bcrypt cost 12, per-hash salt, verifier-only, edge limiter is the control;
                   Argon2id optional-future.)
PFA-PT-6:          OWNER SIGNATURE: APPROVED (2026-09-04).  STATUS: SATISFIED / RATIFIED.
                   (JWS-compact wire format as-is; typ/domain mandatory; no redesign.)
PFA-PT-8:          OWNER SIGNATURE: APPROVED (2026-09-04).  STATUS: SATISFIED / RATIFIED.
                   (trusted-key algorithm pin by kid; no none/fallback/confusion; migration 103.)
PFA-PT-9:          OWNER SIGNATURE: APPROVED (2026-09-04).  STATUS: SATISFIED / RATIFIED (items 1 & 3;
                   item 2 landed in 109; items 4/5 accepted/runbook).

PFA-18A PROVISION/ROTATE:  STATUS: UNCHANGED — PARKED fail-closed (dual_control_unavailable). Not un-parked.
PFA-PT-7 TAX:              STATUS: OPEN — LEGAL/TAX decision required; no rate/jurisdiction/model invented.

------------------------------------------------------------
OBSERVATION CLOSEOUT
------------------------------------------------------------

ARTIFACT:           docs/release/PHASE2_OBSERVATION_CLOSEOUT_20260904.md
TECHNICAL RESULT:   PASS (read-only telemetry over the full window: through-092; ledger 107; 19/19 cron
                    active; 0 cron failures / 15,956 successful executions; no drift; 0 signing keys;
                    native issuance/scanning DARK; 0 unexpected native data; no production mutation).
OWNER ACCEPTANCE:   APPROVED (2026-09-04) — accepted on the recorded read-only telemetry, acknowledging
                    the noted Sentry-not-directly-queried limitation.
FINAL STATUS:       ACCEPTED / COMPLETE (owner-accepted 2026-09-04). Does NOT authorize migration 093–109.

------------------------------------------------------------
KMS DECISION
------------------------------------------------------------

D1:                 AWS KMS (owner-confirmed 2026-09-04; recorded PRODUCTION_SIGNING_KMS_CEREMONY.md §1.2)
D2:                 ES256 / ECDSA P-256 (SHA-256) (owner-confirmed)
CEREMONY:           NOT EXECUTED
SIGNING KEYS:       0

------------------------------------------------------------
RELEASE CANDIDATE
------------------------------------------------------------

CODE RC:            5721a41
MIGRATION RANGE:    093 → 109
MIGRATION HASHES:   MATCH the preflight manifest (FINAL_OWNER_SIGNATURE_AND_PRODUCTION_PREFLIGHT.md) —
                    re-verified this session: 106=2f3c6368…, 107=1765357e…, 108=69a0e658…, 109=55d5a2f4…;
                    093–105 byte-untouched vs 5721a41.
EDGE HASHES:        MATCH the preflight manifest — credential-sign 4ebf9c4c…, primary-checkout 6893467f…,
                    door-session 778df11d…, door-manifest df4c84b8…, refund-execute 0c7ba55b…,
                    payout-execute bce5e8fa…
CODE DRIFT:         NONE (git diff 5721a41..HEAD over supabase/migrations, supabase/rollbacks,
                    supabase/functions, supabase/tests = empty; only docs/ changed)
CI:                 GREEN on 5721a41
REHEARSAL:          GREEN (incremental 092→109 + full replay 000→109 + rollback battery, per the preflight;
                    RC unchanged since, so the rehearsal remains valid)

------------------------------------------------------------
PRODUCTION READ-ONLY
------------------------------------------------------------

TIMESTAMP:          2026-09-04 04:49:24Z (final recheck, read-only)
LEDGER:             107
TIP:                20260902003623 (through 092)
093–109 APPLIED:    0
SIGNING KEYS:       0  (record_scan_door / force_close_* / signing_key.algorithm all absent)
NATIVE EDGES:       NOT DEPLOYED (11 legacy edges only)
FLAGS:              feature.native_issuance_enabled=false, feature.native_scanning_enabled=false (DARK)
UNSET CONFIG:       signing.monitor_enabled / signing.expected_key_fingerprint / fee.buyer_service_bps /
                    deletion.post_event_hold_hours / payout.executor_enabled = NULL
NATIVE DATA:        tickets 0, door_pin 0, scan 0
DRIFT:              NONE
MUTATIONS:          NONE

------------------------------------------------------------
GATE A
------------------------------------------------------------

BACKEND CONSTRUCTION:  GO
P0:                    0
P1:                    0
NEW CODE REQUIRED:     NO (no migration 110; no code/edge change this session)

------------------------------------------------------------
GATE B
------------------------------------------------------------

DARK PRODUCTION MIGRATION 093→109:  READY FOR EXPLICIT OWNER PRODUCTION-MIGRATION AUTHORIZATION

OWNER SIGNATURES COMPLETE:  YES (PFA-18B, PFA-26-UNPARK, PFA-PT-6, PFA-PT-8, PFA-PT-9 items 1&3 — recorded)
OBSERVATION ACCEPTED:       YES (owner-accepted 2026-09-04)
RC FROZEN:                  YES (5721a41; hashes match; no code drift)
CI GREEN:                   YES (on the exact code RC 5721a41)
PRODUCTION BASELINE CLEAN:  YES (ledger 107 / tip 092 / 0 keys / edges absent / flags DARK / no drift)
REHEARSAL GREEN:            YES (092→109 incremental + full replay + rollback battery)
PRODUCTION AUTHORIZED:      NO — Gate B being READY is NOT an authorization. Applying 093→109 requires a
                            separate, explicit owner production-migration instruction.

Every Gate-B precondition from the preflight is now satisfied: the two governance items it was waiting on
(five signatures + observation acceptance) are recorded, and nothing about the code RC, CI, production
baseline, or rehearsal has changed. Tax and the deletion hold do NOT block the dark migration.

------------------------------------------------------------
GATE C
------------------------------------------------------------

FIRST CONTROLLED SALE:  WAITING

TAX:                    OPEN — LEGAL/TAX decision required (blocks quote/PaymentIntent/first sale)
FEE:                    fee.buyer_service_bps NULL — owner value required
KMS:                    ceremony NOT executed; 0 signing keys
CONNECT:                no org/venue/Connect onboarding (transfers capability) provisioned
CONFIG:                 native_issuance_enabled / native_scanning_enabled still false; signing monitor unset
OWNER SALE AUTHORIZATION: not given (separate, later, explicit)

------------------------------------------------------------
PAYOUT
------------------------------------------------------------

VENUE PAYOUT:     NOT AUTHORIZED (separate later gate; payout-execute not deployed; payout.executor_enabled NULL)
PROMOTER PAYOUT:  NOT AUTHORIZED (DARK / out of launch scope)

------------------------------------------------------------
NEXT OPERATION
------------------------------------------------------------

THE NEXT OPERATION REQUIRES A NEW, EXPLICIT OWNER INSTRUCTION AUTHORIZING THE PRODUCTION APPLICATION OF
MIGRATIONS 093→109.

DO NOT EXECUTE IT IN THIS SESSION. When that instruction is given, a separate execution session applies
093→109 (forward-only; hashes pinned to this RC; AUTODEPLOY-VERIFIED-OFF; git_branch empty) under the
STOP conditions recorded in FINAL_OWNER_SIGNATURE_AND_PRODUCTION_PREFLIGHT.md — nothing before that.

------------------------------------------------------------
FINAL STATUS
------------------------------------------------------------

BACKEND CONSTRUCTION COMPLETE:   YES
OWNER SIGNATURES RECORDED:       YES (5 PFAs + KMS D1/D2 confirmed)
OBSERVATION CLOSEOUT ACCEPTED:   YES
CODE RC FROZEN:                  YES (5721a41)
CODE DRIFT:                      NO
CI GREEN ON RC:                  YES
PRODUCTION BASELINE CLEAN:       YES
GATE B READY:                    YES (READY FOR EXPLICIT OWNER PRODUCTION-MIGRATION AUTHORIZATION)
PRODUCTION MIGRATION AUTHORIZED: NO
093–109 APPLIED:                 NO
KMS CEREMONY EXECUTED:           NO
NATIVE EDGES DEPLOYED:           NO
PRIMARY SALE ACTIVATED:          NO
VENUE PAYOUT ACTIVATED:          NO
PROMOTER PAYOUT ACTIVATED:       NO

RECOMMENDED NEXT CLAUDE A ACTION:  Await the owner's explicit production-migration authorization for
093→109. Until then, take no production action. When authorized, run a dedicated execution session that
re-verifies the RC hashes + CI + the production baseline against the STOP conditions immediately before
applying 093→109 forward-only; the KMS ceremony, edge deploys, config, Connect/org onboarding, tax
resolution, and the first controlled sale remain their own later, separately-authorized steps (Gate C).

============================================================

STOP.

NO PRODUCTION MUTATION.

============================================================

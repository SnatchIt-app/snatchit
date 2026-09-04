============================================================
SNATCH IT — FINAL OWNER SIGNATURE + PRODUCTION PREFLIGHT
============================================================

2026-09-04 · governance + preflight only · NO PRODUCTION MUTATION · NO NEW MIGRATION

> This session moved the completed Phase-2 backend toward OWNER-RATIFIED + PRODUCTION-PREFLIGHTED +
> RELEASE-CANDIDATE-FROZEN. It executed NOTHING against production (read-only inspection only), added no
> migration, and signed nothing on the owner's behalf. Owner signatures ratify governance decisions;
> they do NOT authorize any production action. Production authorization is a SEPARATE later instruction.

REPOSITORY

BRANCH:               feature/venue-native-and-product-v2
ENTRY HEAD:           5721a41 (owner-gate un-park train, pushed)
FINAL HEAD:           <recorded post-commit below> (adds preflight + signature package + observation close-out docs; NO code/migration change)
RELEASE CANDIDATE SHA: 5721a41 (the code-bearing tip: migrations 093–109 + edges; this preflight adds docs only, so the RC is unchanged)
PR:                   #52 — OPEN, MERGEABLE (head 5721a41)
CI:                   GREEN on the EXACT RC 5721a41 (run 33835866681: "Migrations apply cleanly (fresh DB)" ✓, "Web build (Next.js)" ✓, "Typecheck / Lint / Unit tests" ✓)
WORKTREE:             clean except the new preflight/governance docs (+ the earlier untracked Tickets coordination note)

------------------------------------------------------------
PRODUCTION READ-ONLY BASELINE
------------------------------------------------------------

LEDGER:               107 rows
TIP:                  20260902003623 (through 092)
093-109 APPLIED:      0 (confirmed: force_close_key_manifests / force_close_session_manifests /
                      record_scan_door / signing_key.algorithm ALL absent in prod)
SIGNING KEYS:         0
NATIVE EDGES:         NOT DEPLOYED — 11 legacy edges only (create-payment-intent, confirm-payment,
                      send-push, stripe-webhook, auto-finalize-auctions, create-connect-account,
                      confirm-and-release, enforce-transfer-expiry, delete-account, notify-report,
                      notify-transfer). No credential-sign / primary-checkout / door-session /
                      door-manifest / refund-execute / payout-execute.
FLAGS:                feature.native_issuance_enabled=false, feature.native_scanning_enabled=false (DARK);
                      signing.monitor_enabled / signing.expected_key_fingerprint / fee.buyer_service_bps /
                      deletion.post_event_hold_hours / payout.executor_enabled = NULL (owner-unset)
CRON:                 19/19 active; 0 failed / 15,956 succeeded in the last 48 h
NATIVE DATA:          tickets 0, door_pin 0, door_session 0, scan 0 (no unexpected Phase-2 data / money facts)
UNEXPECTED DRIFT:     NONE — production is exactly the 076–092 dark substrate as recorded 2026-09-02
MUTATIONS THIS SESSION: NONE

------------------------------------------------------------
BACKEND CONSTRUCTION
------------------------------------------------------------

P0:                     0 (verified — not merely claimed; five adversarial reviewers on the 106–109 train;
                        this preflight re-attested the invariants below)
P1:                     0 (two P1 were found + fixed IN the 106–109 train — the edge /mint arg-name break
                        and the reconcile poison-pill; both closed with tests)
NEW MIGRATION REQUIRED: NO — no release-blocking defect discovered this session; no migration 110 created
BACKEND CONSTRUCTION COMPLETE: YES (GATE A GO — see GATES). provision_signing_key / rotate_signing_key
                        remain parked by owner ruling (PFA-18A), which is a governance decision, not
                        missing code; the bootstrap key is a two-person ceremony insert.

------------------------------------------------------------
OWNER SIGNATURE PACKAGE
------------------------------------------------------------

Mechanism: inline in POST_FREEZE_AMENDMENTS.md ("OWNER SIGNATURE: APPROVED (date). STATUS: SATISFIED /
RATIFIED."), the established repo convention. Convenience index: docs/phase2/OWNER_SIGNATURE_PACKAGE_20260904.md.
Engineering filled NO signature line. Every item authorizes DEVELOPMENT/GOVERNANCE ONLY.

PFA-18B:        DIRECTION: single platform_admin + aal2 revoke un-park (force-close + #44 + no-open-on-
                revoked-trust); provision/rotate STAY parked. SIGNATURE STATUS: OWNER DIRECTION RECEIVED —
                PENDING LITERAL SIGNATURE. (Engineering landed DARK: migration 106.)
PFA-26-UNPARK:  DIRECTION: pgcrypto bcrypt cost 12, per-hash salt, verifier-only, edge limiter is the
                brute-force control; Argon2id optional-future. SIGNATURE STATUS: RECEIVED — PENDING
                SIGNATURE. (Migration 107.)
PFA-PT-6:       DIRECTION: JWS-compact wire format as-is; typ/domain enforcement mandatory; no redesign.
                SIGNATURE STATUS: RECEIVED — PENDING SIGNATURE.
PFA-PT-8:       DIRECTION: trusted-key algorithm pin by kid; no none/fallback/confusion. SIGNATURE STATUS:
                RECEIVED — PENDING SIGNATURE. (Migration 103.)
PFA-PT-9:       DIRECTION: item 1 ratify 104 gate; item 2 wire terminal force-close (landed 109); item 3 no
                record_scan version backstop; item 4 accept offline residual; item 5 break-glass runbook.
                SIGNATURE STATUS: items 1 & 3 RECEIVED — PENDING SIGNATURE.

PRODUCTION AUTHORIZATION IMPLIED: NO — these signatures ratify engineering/governance only.

------------------------------------------------------------
KMS DECISION
------------------------------------------------------------

D1:                   AWS KMS (recorded in PRODUCTION_SIGNING_KMS_CEREMONY.md §1.2; no ambiguity remains)
D2:                   ES256 / ECDSA P-256 (SHA-256); bootstrap signing_key.algorithm set to 'ES256' at ceremony
CEREMONY EXECUTED:    NO
KMS KEY CREATED:      NO
SIGNING KEY ROW:      0
ADAPTER COMPATIBILITY: AwsKmsSigner (SigV4; ECDSA-P256 DER→raw R||S; sign-after-verify; fail-closed
                      UnconfiguredKmsSigner default) is compatible with a D1/D2 = AWS KMS / ES256 key
                      (KeySpec ECC_NIST_P256, SigningAlgorithm ECDSA_SHA_256). vitest KMS adapter tests green.

------------------------------------------------------------
PFA-PT-7 / TAX
------------------------------------------------------------

STATUS:               BOUNDARY HELD — no tax key/gate/model/rate authored anywhere; tax is computed
                      nowhere; the only tax representation is a CLIENT-SIDE advisory that refuses to quote.
                      Owner decision OPEN (affirm compute-none posture, or decide enforcement locus + rate).
BLOCKS MIGRATION 093–109: NO (migrations add no tax object)
BLOCKS KMS CEREMONY:  NO
BLOCKS DARK EDGE DEPLOY: NO
BLOCKS EVENT PUBLISH: NO (A8a′'s publish ladder is the four create_primary_checkout gates; no tax gate)
BLOCKS QUOTE:         YES (client-side) — the client advisory refuses to quote until the owner affirms the
                      posture/locus; this is where "tax fail-closed" actually bites
BLOCKS PAYMENTINTENT: YES (downstream of the quote)
BLOCKS FIRST SALE:    YES — the first controlled sale requires the owner to affirm the compute-none posture
                      (or resolve the locus) so the client will quote and money can move
LEGAL/TAX INPUT REQUIRED: YES — this is a LEGAL/TAX decision, NOT an engineering signature. Do not disguise
                      it as a PFA sign-off; engineering invents no rate/model/locus.

BOUNDARY: DARK INFRASTRUCTURE DEPLOYMENT (migrate 093–109, ceremony, deploy edges, publish event) is
PERMITTED before tax resolution. COMMERCE ACTIVATION (quote → PaymentIntent → sale) is NOT.

------------------------------------------------------------
DELETION HOLD
------------------------------------------------------------

STATUS:               deletion.post_event_hold_hours owner-UNSET (NULL) — fail-closed (a longer/absent hold
                      blocks MORE irreversible tombstones; the conservative direction). It decides when an
                      identity may be IRREVERSIBLY ERASED while order money obligations can still arise.
BLOCKS MIGRATION:     NO
BLOCKS KMS:           NO
BLOCKS DARK DEPLOY:   NO
BLOCKS EVENT PUBLISH: NO
BLOCKS FIRST SALE:    NO
BLOCKS DELETION:      YES — account-erasure finalization is the only thing gated (owner must set the value
                      before erasure-with-live-obligation windows are exercised). Not a sale/scan/migration gate.

------------------------------------------------------------
24H PRODUCTION OBSERVATION
------------------------------------------------------------

ARTIFACT:             NO formal close-out artifact existed at entry — PHASE2_DEPLOYMENT_RECORD_20260902.md
                      stops at "checkpoint 1" (~0.9 h) with "24-hour close: NOT DUE (target ~2026-09-03T20:45Z)".
                      This session created the read-only close-out: docs/release/PHASE2_OBSERVATION_CLOSEOUT_20260904.md.
START:                2026-09-02 20:41:58Z (076–092 apply)
END (target):         ~2026-09-03 20:45Z (24 h); evidence gathered 2026-09-04 (>24 h)
CRON:                 19/19 active; 0 failed / 15,956 succeeded in 48 h
SENTRY:               not directly queried this session; cron run-history + 0 error-severity (checkpoint 1)
                      are the available read-only signals — the close-out records this explicitly
LEDGER:               107 (through 092)
SIGNING KEYS:         0
FLAGS:                DARK; owner-unset keys NULL; native data 0; no drift
RESULT:               TECHNICAL PASS (read-only telemetry over the full window) — PENDING OWNER ACCEPTANCE.
                      Per the rule "do not infer PASS from elapsed time", the PASS rests on actual
                      telemetry (0 cron failures, 0 drift, 0 native data), and OWNER ACCEPTANCE of the
                      close-out is the governance step that closes the gate.

IF MISSING / EXACT CLOSE-OUT REQUIRED: the read-only close-out procedure is now recorded in
PHASE2_OBSERVATION_CLOSEOUT_20260904.md; owner acceptance is the remaining step.

------------------------------------------------------------
RELEASE CANDIDATE
------------------------------------------------------------

SHA:                  5721a41 (code-bearing tip; d07ed8a introduced the code, 5721a41 added its report-HEAD note)
MIGRATIONS:           093 → 109 (17 migrations)
CI ON EXACT SHA:      GREEN (run 33835866681, headSha 5721a41)

HASH MANIFEST (migration → rollback):
  093_primary_ticketing                          0e6729d72cf3f61b0a00c2683962d400   rollback: NONE (foundational; forward-only)
  094_organization_obligation                    1beb85aa6973d3748fa181895e39f9c1   6724170f037e94152338a318d1ba7c87
  095_payout_state_machine_recovery              cb85cac5183d974c392b6422877b2aa4   603ccc51efad91e6720a784dc31d05f1
  096_payout_reversal_and_obligation_recovery    466e0f605e20748e7ddd7e53889fbf5d   674a88a2caad1f0b320cfa00fa976489
  097_settlement_scope_and_shortfall             6730beaf5a94d716938bae7f556d9055   e2d5f32779c656235aa08500619e5228
  098_promoter_prorata_funding                   2684b3f67326cd9e166f164a9e9d74c0   88e61b7709d10e99d43c9b2b971778bf
  099_signing_monitor_and_executor_invokers      e83aca66b2dd76ebcd3e26de5246be43   ac22c6cc700c401b0d9e58535dfd7e4d
  100_venue_obligation_excludes_held_commission  58402dbfec629abaa10b6866ec8abf29   07d538183de7b5bdee8f8589d71414c6
  101_recovery_venue_scope                       8d79dbc7663ebe9caa94271034f9de7e   eb94045811b6968032eb28d8ba2bd765
  102_credential_signing_context_and_saleable    6c5d64cccb9f6bef0fb38b014f3491c1   bced11eed1f7849530061c154eba2de1
  103_signing_key_algorithm_pin                  94d8b9a57001d612f3f1db9b5006a77d   f9be793b96884dc3cb09d95a1c694ab4
  104_scan_session_status_gate                   2d94ac4ff5f2ad83f65af8856ad8b70b   1fe006a2d0e52e2b051634ac459e3931
  105_door_manifest_forceclose_and_reconcile     fadca67fb4c06cfad3707234b90b3bba   9524bf67f02ce7ec1b229928453d4a4a
  106_revoke_signing_key_unpark                  2f3c63686bfc4cd4c7c2bf024be3ba28   dfb4c47fe7103fb8e7409c7d8f7cf8c9
  107_door_pin_kdf_unpark                        1765357ea11ab4726a28129035ae33d1   06a329cef8ba7a855d508359e8fc70a0
  108_door_machine_scan_authority                69a0e658acb132ef13dc6854308aa7ff   b0e468bd64f6bf248879aee02f6a395d
  109_terminal_session_manifest_forceclose       55d5a2f492fd98051bca71fabcbc4871   0960f6007fe45f47517230e166238fee

EDGE HASH MANIFEST (index.ts md5):
  credential-sign   4ebf9c4c5dd4d0e8c855a75c854648cb
  primary-checkout  6893467fe081b79020ff1a2015314ddd
  door-session      778df11deb2ce719a65091b47c62554e
  door-manifest     df4c84b89b189869a4bafbb08ccecca0
  refund-execute    0c7ba55bb3543be6e435d44214c5636b
  payout-execute    bce5e8facf33d6548c83f418bdb8dd66

GOVERNANCE SET: POST_FREEZE_AMENDMENTS.md (PFA-18A/18B/26/26-UNPARK/PT-6/PT-7/PT-8/PT-9 + the 2026-09-03
  ratification addendum); OWNER_GATE_FINAL_UNPARK_REPORT.md; FINAL_DOOR_PLANE_ACTIVATION_READINESS_REPORT.md;
  PRODUCTION_SIGNING_KMS_CEREMONY.md; PRIMARY_TICKETING_ACTIVATION_MATRIX.md;
  PRIMARY_TICKETING_PRODUCTION_ACTIVATION_RUNBOOK.md; OWNER_SIGNATURE_PACKAGE_20260904.md;
  PHASE2_OBSERVATION_CLOSEOUT_20260904.md.

PREFLIGHT == DEPLOY: what is preflighted here (5721a41, migrations 093–109 by the hashes above, the six
edge sources by the hashes above) is exactly what a later production authorization applies. Any hash
drift is a STOP condition.

------------------------------------------------------------
093→109 REHEARSAL
------------------------------------------------------------

092 BASELINE:  clean (REHEARSAL_UPTO=092; census kernel 109 / venue 79 / catalog 16)
093:  OK    094: OK    095: OK    096: OK    097: OK    098: OK    099: OK    100: OK    101: OK
102:  OK    103: OK    104: OK    105: OK    106: OK    107: OK    108: OK    109: OK
               (each applied individually on the 092 baseline, in LC_ALL=C order, zero errors)
FINAL:         census kernel 149 / venue 83 / catalog 17 (exactly the expected +40/+4/+1 deltas);
               full replay 000→109 clean, Gate-2 27/70/37/26 (== CI baseline)
ROLLBACK BATTERY: 094–109 rollbacks apply cleanly and revert state (door fns 0, trigger 0, revoke
               re-parked, PIN re-parked). 093 has NO rollback file (foundational; production forward-only —
               see FORWARD-ONLY PLAN). Rollback rehearsal proves mechanical reversibility, NOT that
               production should roll back once real facts exist.

------------------------------------------------------------
PRODUCTION DATA SAFETY
------------------------------------------------------------

USERS:                 untouched (093–109 add/replace functions + one column + one trigger; no user DML)
LISTINGS:              untouched
PAYMENTS:              untouched
TRANSFERS:             untouched
REFUNDS:               untouched
CONNECT:               untouched
CRON:                  093–109 schedule no new production-bearing cron that activates behavior (native
                       flags stay DARK); existing 19 jobs unaffected
EXISTING ROW MUTATION: NONE across 093→109 (create-or-replace functions, an additive
                       signing_key.algorithm column with a safe default over a 0-row table, additive
                       grants, one AFTER-UPDATE trigger; no backfill, no UPDATE/DELETE of existing rows)
UNEXPECTED:            NONE

------------------------------------------------------------
SECURITY RE-ATTESTATION
------------------------------------------------------------

G4:          PASS (test 166 — venue obligation 9000, excludes held commission)
G5:          PASS (test 167 — cross-venue recovery refused)
M1:          PASS (verifyToken: typ/kid/alg-pin/signature/exp) — unchanged
M2:          PASS (offline-verify OFFLINE-VERIFY-v1 core) — unchanged
KMS:         PASS (AwsKmsSigner / ES256 / DER↔raw / sign-after-verify / fail-closed) — vitest green
TYP:         enforced before signature — unchanged
ALG PIN:     trusted-key algorithm by kid (103) — unchanged
REVOKE:      PASS (test 172 — platform_admin+aal2, force-close #44, open-on-revoked-trust refused, deadlock-free lock order)
PIN:         PASS (test 173 — bcrypt cost 12, opaque failure + timing dummy, no leak, rotation)
MACHINE AUTH: PASS (test 174 — assert-bound scope, body override rejected, service_role-only, poison-pill isolated)
CANCEL:      PASS (test 175 — force-close + #44, scope isolation, duplicate no-re-emit, money non-regression)
DOUBLE SCAN: online prevented (unique index); offline reconciled to one authoritative admit (171/174)
OFFLINE:     PASS (offline-verify core; reconcile isolation)
OLD OWNER:   PASS (verifier stale_version + credential_version bump) — unchanged
REGRESSION:  NONE.

------------------------------------------------------------
DARK EDGE DEPLOYMENT SET
------------------------------------------------------------

FIRST SALE REQUIRED:  credential-sign, primary-checkout  (mint + sign the credential for the first ticket)
FIRST SCAN REQUIRED:  door-session (PIN mint + machine scan relay); door-manifest OPTIONAL (M2 sign; the
                      TLS-only unsigned manifest is MVP-acceptable per §3.9b)
REFUND REQUIRED:      refund-execute  (only when proving the first refund)
PAYOUT REQUIRED:      payout-execute  (SEPARATE, later — first-safe-payout track; NOT for the first sale)
OPTIONAL:             door-manifest (as above)

MINIMUM FIRST-SALE + SCAN BLAST RADIUS: credential-sign + primary-checkout + door-session (+ door-manifest
only if signed manifests are wanted). Do NOT deploy payout-execute for the first sale. Staged activation.

------------------------------------------------------------
CONFIG PREFLIGHT
------------------------------------------------------------

KEY                                   PROD (read-only)   REQUIRED FUTURE            WHO / CONTROL                 NEEDED FOR
feature.native_issuance_enabled       false              true (at issuance step)    platform (dual-control class) TICKET ISSUANCE
feature.native_scanning_enabled       false              true (at scan step)        platform                     DOOR SCAN
signing.monitor_enabled               NULL               true (post-ceremony)       platform                     signing monitor arm
signing.expected_key_fingerprint      NULL               the ceremony fingerprint   two-person (ceremony)         signing trust verify
fee.buyer_service_bps                  NULL               owner business value       owner                        FIRST SALE (fee model)
credential.app_ttl_interval           "4 hours"          (seeded — ok)              platform                     credential TTL
door.manifest_ttl_interval            "12 hours"         (seeded — ok)              platform                     manifest freshness
door.session_ttl_interval             "12 hours"         (seeded — ok)              platform                     door session TTL
door.session_absolute_max_interval    "24 hours"         (seeded — ok)              platform                     door session cap
door.session_post_session_grace       "4 hours"          (seeded — ok)              platform                     door session grace
deletion.post_event_hold_hours        NULL               owner value                owner                        ACCOUNT DELETION only (not sale)
payout.executor_enabled               NULL               true (payout track only)   platform (payout.% dual-ctl) VENUE PAYOUT (separate)

Do NOT set fee.buyer_service_bps or deletion.post_event_hold_hours here — owner business/legal values.

------------------------------------------------------------
KMS CEREMONY PREFLIGHT  (DO NOT EXECUTE)
------------------------------------------------------------

TWO-PERSON:  YES — Person A = AWS/KMS operator (holds kms:CreateKey); Person B = Snatch It DB/trust-root
             verifier (independently confirms the SPKI fingerprint + inserts the bootstrap row). Neither
             can complete the ceremony alone (runbook ADV-1/ADV-2).
IAM:         least privilege — the SIGNING RUNTIME needs kms:Sign (+ kms:GetPublicKey for bootstrap/verify)
             on the SPECIFIC key ARN only. Do NOT grant kms:Decrypt, do NOT grant kms:* , scope by resource
             so the role cannot sign with any other key. (Recommendation flagged in the report; the runbook
             §4a AWS block is the authoring point.)
KEY SPEC:    ECC_NIST_P256 (asymmetric, SIGN_VERIFY usage only)
ALGORITHM:   ECDSA_SHA_256 (ES256) — matches signing_key.algorithm='ES256'
PUBLIC KEY:  SPKI PEM (D3), the format the fingerprint + verify commands consume
FINGERPRINT: derived + INDEPENDENTLY verified by Person B before the DB insert
DB INSERT:   exactly ONE kernel.signing_key row (global bootstrap): public_key SPKI, kms_handle_ref
             version/key-pinned ARN, algorithm='ES256', status active, not_before now
MONITOR:     run kernel.check_signing_key_invariants + arm signing.monitor_enabled; set
             signing.expected_key_fingerprint
STOP CONDITIONS: fingerprint mismatch; >0 pre-existing signing keys; private material leaving KMS; monitor
             unhealthy; algorithm ≠ ES256; kms_handle_ref not version-pinned
READY:       YES to preflight (D1/D2 decided, adapter compatible); the ceremony is a later production op.

------------------------------------------------------------
FIRST CONTROLLED SALE PREFLIGHT
------------------------------------------------------------

ORG:         requires a real org onboarded (none provisioned) — future production op
VENUE:       requires an approved venue under that org — future
CONNECT:     requires Express onboarding + transfers capability on the org's Connect account — future;
             platform charge model (no prohibited transfer_data/on_behalf_of/application_fee) verified in code
FEE POLICY:  fee.buyer_service_bps must be set (owner value) — currently NULL
TAX:         owner must affirm compute-none posture (or resolve locus) so the client will quote — LEGAL/TAX
SIGNING:     KMS ceremony done + one active signing key + monitor armed — future
DOOR:        native_scanning_enabled=true + a door PIN provisioned — future
CONFIG:      native_issuance_enabled=true at issuance — future
OWNER AUTH:  explicit production authorization — future
READY:       NO — this is GATE C (WAITING), gated on tax/legal + config + KMS + Connect/org + owner authorization.

------------------------------------------------------------
FORWARD-ONLY PLAN
------------------------------------------------------------

Production already holds real 076–092 substrate facts (dark smoke), so production is FORWARD-ONLY. Do NOT
author a runbook that rolls 076–092 (or later, once real facts exist) back.

TRANSACTIONALITY: every 093–109 migration is a single `begin;`…`commit;` (verified) — each applies
  atomically. `supabase db push --include-all` applies them in order, each in its own transaction.
PRE-COMMIT FAILURE (a migration errors before its COMMIT): that migration's transaction rolls back on its
  own; the ledger stops at the last successful migration; NO partial object from the failed one persists.
  Handling: STOP, diagnose, FIX-FORWARD (author the fix as the next migration or correct-and-retry the
  un-applied file — it is DARK), never roll back already-applied earlier migrations.
POST-COMMIT FAILURE (a later step — ceremony/edge/config — fails after 093–109 committed): FIX-FORWARD.
  093–109 are DARK (no behavior activates on apply — flags stay false, 0 keys), so a committed-but-not-yet-
  activated substrate is inert and safe; correct the failing later step and continue.
ROLLBACK PROHIBITIONS: do NOT roll back 076–092; do NOT roll back 093–109 once applied to production; the
  rollback files exist for MECHANICAL-REVERSIBILITY REHEARSAL only.

------------------------------------------------------------
STOP CONDITIONS  (encode into the future execution runbook — any one ⇒ HALT)
------------------------------------------------------------

- production observation close-out not accepted by the owner
- release SHA differs from 5721a41 (or the owner-authorized successor)
- CI not GREEN on the exact release SHA
- any migration hash ≠ the manifest above
- production ledger ≠ 107 / tip ≠ through-092 at apply time
- signing keys > 0 BEFORE the ceremony
- any Phase-2 native edge already deployed unexpectedly
- PFA signatures incomplete (18B / 26-UNPARK / PT-6 / PT-8 / PT-9 items 1&3)
- KMS D1/D2 inconsistent with AWS KMS / ES256
- tax boundary violated (commerce activated before the owner tax posture is affirmed)
- deletion gate violated (erasure exercised before deletion.post_event_hold_hours is owner-set)
- production config drift (a flag/key already set unexpectedly)
- migration apply plan lists anything other than 093..109
- KMS fingerprint mismatch (ceremony) / monitor unhealthy
- Connect transfers capability incomplete at the sale gate
- fee.buyer_service_bps unset at the sale gate
- any P0/P1 discovered

------------------------------------------------------------
GATES
------------------------------------------------------------

GATE A — BACKEND CONSTRUCTION:  **GO.** P0=0, P1=0; 093–109 built + tested + CI-green on the exact RC;
  every door-plane and signing mechanism present; provision/rotate parked by owner ruling, not missing code.

GATE B — DARK PRODUCTION MIGRATION 093→109:  **WAITING.**
  WHY: waiting ONLY on (1) owner literal signatures for PFA-18B / PFA-26-UNPARK / PT-6 / PT-8 / PT-9(1,3),
  and (2) owner ACCEPTANCE of the 24-hour observation close-out (technical PASS recorded, acceptance
  pending). Tax (PFA-PT-7) does NOT block the dark migration; the deletion hold does NOT block it. No
  engineering work remains. On those two governance items, Gate B is READY FOR EXPLICIT OWNER
  PRODUCTION-MIGRATION AUTHORIZATION.

GATE C — FIRST CONTROLLED PRIMARY SALE:  **WAITING.**
  WHY: gated on the LEGAL/TAX decision (affirm compute-none posture or resolve locus), fee.buyer_service_bps,
  the KMS ceremony (AWS KMS / ES256), Connect/org onboarding, the issuance/scanning config flips, and a
  separate explicit owner production authorization. None is engineering.

------------------------------------------------------------
REMAINING ACTIONS
------------------------------------------------------------

OWNER:        sign PFA-18B, PFA-26-UNPARK, PT-6, PT-8, PT-9(1,3) inline in POST_FREEZE_AMENDMENTS.md;
              accept PHASE2_OBSERVATION_CLOSEOUT_20260904.md; set fee.buyer_service_bps and
              deletion.post_event_hold_hours (business/legal values) before the steps that need them;
              issue explicit production-migration authorization, then (later) production-sale authorization.
LEGAL/TAX:    affirm the compute-none / client-advisory-refuse posture, OR decide the tax enforcement locus
              + rate/model with counsel (PFA-PT-7). Required before the FIRST SALE, not before dark deploy.
PRODUCTION:   (after authorization) migrate 093→109; run the KMS ceremony (AWS KMS / ES256, two-person);
              deploy the minimal edge set (credential-sign, primary-checkout, door-session [+door-manifest]);
              set config; onboard org/Connect; flip issuance/scanning at their steps; controlled sale + scan;
              prove a refund. Venue payout is a separate later track.
OPTIONAL:     KMS IAM least-privilege review at ceremony; a paid-order cancel regression test; a PIN-length
              floor / per-(venue,session) lockout; the legacy-secret rotation sequence (owner-gated).

------------------------------------------------------------
NEXT OPERATION
------------------------------------------------------------

The exact next operation is a GOVERNANCE one, not a production one: the owner records the five signatures
inline in POST_FREEZE_AMENDMENTS.md and accepts the observation close-out. DO NOT EXECUTE any production
step. Once those two governance items are complete, Gate B is:

  READY FOR EXPLICIT OWNER PRODUCTION-MIGRATION AUTHORIZATION

(not AUTHORIZED). Applying 093→109 remains a separate, explicit, owner-issued production instruction.

------------------------------------------------------------
FINAL STATUS
------------------------------------------------------------

BACKEND CONSTRUCTION COMPLETE:            YES
OWNER SIGNATURE PACKAGE COMPLETE:         YES (prepared; index at OWNER_SIGNATURE_PACKAGE_20260904.md)
OWNER SIGNATURES ACTUALLY RECORDED:       NO (owner must sign; not self-signed)
24H OBSERVATION ARTIFACT VERIFIED:        PARTIAL — no prior artifact existed; a read-only close-out was
                                          created (TECHNICAL PASS), PENDING OWNER ACCEPTANCE
RELEASE CANDIDATE FROZEN:                 YES (5721a41; migration + rollback + edge hash manifest recorded)
CI GREEN ON EXACT RC:                     YES (5721a41)
093→109 REHEARSAL GREEN:                  YES (incremental 092→109 + full replay + rollback battery)
PRODUCTION DRIFT:                         NO
KMS PROVIDER DECIDED:                     YES — AWS KMS
KMS ALGORITHM DECIDED:                    YES — ES256
KMS CEREMONY EXECUTED:                    NO
PRODUCTION MIGRATIONS APPLIED:            NO
NATIVE EDGES DEPLOYED:                    NO
PRIMARY SALE ACTIVATED:                   NO
VENUE PAYOUT ACTIVATED:                   NO
PROMOTER PAYOUT ACTIVATED:                NO
READY FOR EXPLICIT OWNER PRODUCTION-MIGRATION AUTHORIZATION:  YES — once the five signatures are recorded
                                          and the observation close-out is accepted (both governance, no code).

RECOMMENDED NEXT CLAUDE A ACTION:  Hand the owner the signature package (OWNER_SIGNATURE_PACKAGE_20260904.md)
and the observation close-out (PHASE2_OBSERVATION_CLOSEOUT_20260904.md) for inline signing/acceptance in
POST_FREEZE_AMENDMENTS.md. Do NOT apply migrations, run KMS, deploy edges, configure production, move
money, or activate. After the owner records the signatures + accepts the close-out AND issues an explicit
production-migration instruction, a separate execution session applies 093→109 under the STOP conditions
above — nothing before that.

============================================================

STOP.

DO NOT APPLY 093–109.
DO NOT RUN KMS.
DO NOT DEPLOY EDGES.
DO NOT CONFIGURE PRODUCTION.
DO NOT MOVE MONEY.
DO NOT ACTIVATE.

============================================================

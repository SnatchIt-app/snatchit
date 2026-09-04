============================================================
SNATCH IT — PHASE-2 093→109 PRODUCTION MIGRATION EXECUTION
============================================================

2026-09-04 · Gate B production migration · DARK substrate through 109 · NO ACTIVATION

AUTHORIZATION

OWNER AUTHORIZATION:   YES — MIGRATIONS 093→109 ONLY (explicit owner instruction, this session)
KMS AUTHORIZED:        NO
EDGE DEPLOY AUTHORIZED: NO
CONFIG AUTHORIZED:      NO (no config value set by hand; the migrations register their own dark defaults)
COMMERCE AUTHORIZED:    NO
PAYOUT AUTHORIZED:      NO

------------------------------------------------------------
REPOSITORY
------------------------------------------------------------

BRANCH:            feature/venue-native-and-product-v2
GOVERNANCE HEAD:   11d248a (at execution) → this execution-record commit follows
CODE RC:           5721a41 (AUTHORIZED) — all migration/rollback/edge bytes byte-identical to 5721a41
CI:                GREEN on the exact code RC 5721a41 (run 33835866681: migrations fresh-DB, web build,
                   typecheck/lint/unit — all success)
CODE DRIFT:        NONE — git diff 5721a41..HEAD is docs-only (verified)

------------------------------------------------------------
PRE-APPLY PRODUCTION BASELINE
------------------------------------------------------------

PROJECT:           hqycwntpfoztoinemqns ("Snatch It", db.hqycwntpfoztoinemqns.supabase.co) — verified via
                   the linked dry-run connecting to that host
TIMESTAMP:         2026-09-04 05:11:13Z (final read-only recheck)
LEDGER:            107
TIP:               through 092 (max numeric = 092; 093–109 absent)
093–109:           0 applied
SIGNING KEYS:      0
NATIVE EDGES:      NOT DEPLOYED (11 legacy edges only)
FLAGS:             feature.native_issuance_enabled=false, feature.native_scanning_enabled=false
CONFIG:            signing.monitor_enabled / signing.expected_key_fingerprint / fee.buyer_service_bps /
                   deletion.post_event_hold_hours / payout.executor_enabled — absent (unregistered)
NATIVE DATA:       tickets 0, door_pin 0, door_session 0, scan 0
CRON:              19 active
DRIFT:             NONE

------------------------------------------------------------
HASH VERIFICATION  (all match the frozen preflight manifest)
------------------------------------------------------------

093: 0e6729d72cf3f61b0a00c2683962d400   102: 6c5d64cccb9f6bef0fb38b014f3491c1
094: 1beb85aa6973d3748fa181895e39f9c1   103: 94d8b9a57001d612f3f1db9b5006a77d
095: cb85cac5183d974c392b6422877b2aa4   104: 2d94ac4ff5f2ad83f65af8856ad8b70b
096: 466e0f605e20748e7ddd7e53889fbf5d   105: fadca67fb4c06cfad3707234b90b3bba
097: 6730beaf5a94d716938bae7f556d9055   106: 2f3c63686bfc4cd4c7c2bf024be3ba28
098: 2684b3f67326cd9e166f164a9e9d74c0   107: 1765357ea11ab4726a28129035ae33d1
099: e83aca66b2dd76ebcd3e26de5246be43   108: 69a0e658acb132ef13dc6854308aa7ff
100: 58402dbfec629abaa10b6866ec8abf29   109: 55d5a2f492fd98051bca71fabcbc4871
101: 8d79dbc7663ebe9caa94271034f9de7e

ALL MATCH: YES

------------------------------------------------------------
PRE-APPLY GATE
------------------------------------------------------------

RESULT: GO

[x] correct production project (hqycwntpfoztoinemqns, verified)   [x] native edges absent
[x] owner signatures recorded (2026-09-04)                        [x] native flags dark
[x] observation closeout accepted (2026-09-04)                    [x] owner-unset config unset
[x] RC = 5721a41                                                  [x] no unexpected native data
[x] no production-bearing drift after RC (docs only)              [x] no P0/P1 discovered
[x] CI green on RC                                                [x] plan == exactly 093→109 (dry-run)
[x] all 17 hashes match                                           [x] ledger 107 / tip 092 / 093–109 absent
[x] signing keys 0

STOP CONDITIONS: NONE

MECHANISM: supabase CLI `db push --linked --include-all` (the proven 076–092 mechanism; records the
ledger in the repo's numeric-version convention — version="093", name="primary_ticketing"). The CLI was
already authenticated (access token) and resolved the DB password from the OS keychain non-interactively;
NO credential was entered or handled by this session. `supabase link` wrote a local supabase/config.toml
(local artifact, not a production change; left untracked). A `--dry-run` first confirmed the plan was
exactly 093→109 (17 migrations, no seeds, no roles).

------------------------------------------------------------
MIGRATION EXECUTION
------------------------------------------------------------

START:   2026-09-04T05:11:43Z
METHOD:  supabase db push --linked --include-all  (non-interactive; keychain-resolved DB password)
PLAN:    exactly 093→109 (verified by --dry-run immediately before)
093: applied   098: applied   103: applied   108: applied
094: applied   099: applied   104: applied   109: applied
095: applied   100: applied   105: applied
096: applied   101: applied   106: applied
097: applied   102: applied   107: applied
END:     2026-09-04T05:12:23Z  (~40s; push exit 0; "Finished supabase db push."; no errors)

FAILURE: NONE

------------------------------------------------------------
POST-APPLY LEDGER
------------------------------------------------------------

LEDGER:          124 (107 + 17)
TIP:             numeric substrate tip = 109 (all of 093..109 present); max(version) lexical remains the
                 earlier timestamp migration 20260902003623 (expected with the mixed numeric/timestamp
                 version formats — the 093..109 rows sort before it lexically but are all present)
APPLIED RANGE:   093,094,095,096,097,098,099,100,101,102,103,104,105,106,107,108,109 (all 17)
MISSING:         none
UNEXPECTED:      none (only 093..109 were added; count delta is exactly +17)

------------------------------------------------------------
OBJECT VERIFICATION
------------------------------------------------------------

093 primary ticketing:            present (kernel functions +16; census consistent)
094 organization obligation:      present
095 payout state machine recovery: present
096 payout reversal / recovery:    present
097 settlement scope/shortfall:    present
098 promoter prorata funding:      present
099 signing monitor + invokers:    present (monitor-signing-key-invariants + payout-execute-tick crons registered)
100 venue obligation excl. held:   present
101 recovery venue scope:          present
102 credential signing context / SALEABLE: present (get_ticket_signing_context)
103 signing_key.algorithm pin:     present (kernel.signing_key.algorithm column EXISTS)
104 terminal-session scan gate:    present
105 force_close_key_manifests + reconcile: present (kernel.force_close_key_manifests EXISTS)
106 revoke_signing_key un-park:    present (un-parked body)
107 door PIN KDF:                  present (create_door_pin / mint_door_session un-parked; pgcrypto)
108 door machine scan authority:   present (venue.record_scan_door + reconcile_offline_scans_door EXIST)
109 terminal-session force-close:  present (kernel.force_close_session_manifests + trigger
                                   tg_session_terminal_force_close EXIST)
CENSUS:   kernel 149 · venue 83 · catalog 17 (exactly the rehearsed post-109 census)

------------------------------------------------------------
GRANTS / SECURITY
------------------------------------------------------------

PUBLIC / ANON:     no unexpected EXECUTE expansion
AUTHENTICATED:     revoke_signing_key EXECUTE = true (platform_admin + aal2 enforced in-body)
SERVICE_ROLE:      record_scan_door EXECUTE = true; _record_scan_core EXECUTE = false (zero-grant core)
SECURITY DEFINER:  all new functions definer + search_path='' (per the RC, rehearsed)
PROVISION:         STILL PARKED (raises dual_control_unavailable) — grant unchanged, body parked
ROTATE:            STILL PARKED
REVOKE:            un-parked (authenticated; platform_admin + aal2 in-body) — expected
DOOR MACHINE:      record_scan_door / reconcile_offline_scans_door = service_role only; authenticated denied
CORES:             _record_scan_core / _reconcile_core / force_close_* = zero-grant (PUBLIC revoked)
NO generic service_role bypass.

------------------------------------------------------------
DARKNESS
------------------------------------------------------------

NATIVE ISSUANCE:       false
NATIVE SCANNING:       false
SIGNING KEYS:          0
SIGNING MONITOR:       false (registered dark; the daily monitor cron no-ops with 0 keys)
EXPECTED FINGERPRINT:  null (unset; set at the ceremony)
BUYER FEE:             null (owner value, unset)
DELETION HOLD:         null (owner value, unset)
PAYOUT EXECUTOR:       false (registered dark; payout-execute-tick no-ops while false)
NATIVE EDGES:          NOT DEPLOYED (unchanged — no edge deployed this session)
DOOR PINS:             0
DOOR SESSIONS:         0
TICKETS:               0
SCANS:                 0
MONEY MOVED:           NO
CREDENTIALS ISSUED:    NO
NOTE: the 5 owner/dark config keys were REGISTERED by the migrations as null (unset) or false (gated OFF)
— these are safe dark defaults, NOT activations. No flag was flipped to true by this session.

------------------------------------------------------------
DATA NON-REGRESSION
------------------------------------------------------------

USERS:              19 (auth.users)
PROFILES:           unchanged (093–109 perform no public.* DML)
LISTINGS:           111
PAYMENTS:           57
TRANSFERS:          unchanged
REFUNDS:            unchanged
CONNECT:            unchanged
LEGACY DATA:        intact — 093–109 create/replace kernel/catalog/venue/market functions, one additive
                    column (signing_key.algorithm over a 0-row table), additive grants, one trigger; they
                    execute NO INSERT/UPDATE/DELETE against existing legacy (public.*) rows
CRON:               22 active (19 pre + 3 dark invokers: monitor-signing-key-invariants, payout-execute-tick,
                    refund-execute-tick — all config/flag-gated no-ops)
UNEXPECTED MUTATION: NONE

------------------------------------------------------------
OBSERVABILITY
------------------------------------------------------------

SOURCES CHECKED:   (1) supabase CLI `db push` output (clean; exit 0; "Finished supabase db push."; no error
                   lines); (2) Supabase MCP read-only SQL against supabase_migrations.schema_migrations,
                   pg_proc / pg_trigger / information_schema, catalog.platform_config, cron.job,
                   cron.job_run_details, auth.users, public.listings, public.payments.
DB ERRORS:         none surfaced by the apply; no failed objects
CRON:              22/22 active; 0 failures in the last hour (checked cron.job_run_details)
EDGE:              not applicable (no edge deployed / invoked)
SENTRY:            NOT directly queried this session (stated honestly)
OTHER:             the Postgres logs service (query_logs) was not queried; the apply output + catalog +
                   cron read-backs are the evidence relied on

------------------------------------------------------------
IMMEDIATE CHECKPOINT
------------------------------------------------------------

APPLY COMPLETED:   2026-09-04T05:12:23Z
CHECKPOINT:        2026-09-04 ~05:12–05:13Z (read-only, immediately post-apply)
LEDGER:            124 (all 093–109 present)
CRON:              22 active, 0 recent failures
ERRORS:            none
FLAGS:             DARK (issuance/scanning false)
SIGNING KEYS:      0
NATIVE EDGES:      NOT DEPLOYED
NATIVE DATA:       tickets 0 / door_pin 0 / door_session 0 / scan 0
(No long observation window is invented; this is the immediate post-apply checkpoint only. No activation
performed during observation.)

------------------------------------------------------------
POST-APPLY RESULT
------------------------------------------------------------

RESULT: SUCCESS

[x] 093–109 all applied            [x] native edges absent
[x] no unexpected migration        [x] native data unchanged/empty
[x] ledger/tip correct             [x] existing business data intact
[x] expected objects exist         [x] cron healthy (0 failures)
[x] grants correct                 [x] no unexpected money movement
[x] flags dark                     [x] no unexpected credential/ticket/scan facts
[x] signing keys 0                 [x] no P0/P1 discovered

P0: 0
P1: 0

------------------------------------------------------------
NEW PRODUCTION BASELINE
------------------------------------------------------------

MIGRATION TIP:   109 (numeric substrate) — ledger 124 rows
LEDGER:          124
RC:              5721a41
TIMESTAMP:       2026-09-04T05:12:23Z
FLAGS:           DARK (native issuance/scanning false)
SIGNING KEYS:    0
EDGES:           Phase-2 native edges NOT DEPLOYED
STATE:           PHASE-2 DATABASE SUBSTRATE THROUGH MIGRATION 109 — LIVE BUT DARK.
                 This is NOT "primary ticketing live". It is the database substrate live through 109,
                 still dark (no trust root, no edges, no config activated, no flags flipped).

------------------------------------------------------------
GATES
------------------------------------------------------------

GATE A — BACKEND CONSTRUCTION:        GO
GATE B — DARK MIGRATION 093→109:      COMPLETE  (applied + verified dark, 2026-09-04)
GATE C — FIRST CONTROLLED SALE:       WAITING
VENUE PAYOUT:                         NOT AUTHORIZED
PROMOTER PAYOUT:                      NOT AUTHORIZED

------------------------------------------------------------
REMAINING GATE C ITEMS
------------------------------------------------------------

TAX:              OPEN — LEGAL/TAX decision (affirm compute-none posture or resolve locus) — blocks the sale
FEE:              fee.buyer_service_bps registered null — owner value required
KMS:              AWS KMS / ES256 ceremony NOT executed
SIGNING KEY:      0 — one bootstrap key inserted at the ceremony
MONITOR:          signing.monitor_enabled false; signing.expected_key_fingerprint null (set at ceremony)
EDGES:            credential-sign, primary-checkout, door-session (+door-manifest) NOT deployed
ORG:              no production org onboarded
VENUE:            no approved venue
CONNECT:          no Connect onboarding / transfers capability
ISSUANCE:         feature.native_issuance_enabled false
SCANNING:         feature.native_scanning_enabled false
DOOR PIN:         none provisioned
OWNER SALE AUTH:  not given (separate, later, explicit)

------------------------------------------------------------
NEXT OPERATION
------------------------------------------------------------

The next recommended owner-authorized operation is the AWS KMS / ES256 PRODUCTION SIGNING CEREMONY
(two-person, per PRODUCTION_SIGNING_KMS_CEREMONY.md) to establish the trust root and insert the ONE
bootstrap kernel.signing_key row.

IT IS NOT AUTHORIZED. It requires a NEW, explicit owner authorization. Do not create a key merely because
migration 109 is live. This session ends with the substrate live-but-dark and takes no further action.

------------------------------------------------------------
FINAL STATUS
------------------------------------------------------------

OWNER MIGRATION AUTHORIZATION:   YES
PRE-APPLY GATE:                  GO
093–109 APPLIED:                 YES (all 17)
PRODUCTION TIP:                  109 (numeric substrate); ledger 124
PRODUCTION SUBSTRATE THROUGH 109: YES
PRODUCTION DARK:                 YES
SIGNING KEYS:                    0
KMS CEREMONY EXECUTED:           NO
NATIVE EDGES DEPLOYED:           NO
CONFIG CHANGED:                  NO (migrations registered their own dark defaults; no owner value set)
MONEY MOVED:                     NO
TICKETS ISSUED:                  NO
CREDENTIALS ISSUED:              NO
SCANS:                           NO
PRIMARY SALE ACTIVATED:          NO
VENUE PAYOUT ACTIVATED:          NO
PROMOTER PAYOUT ACTIVATED:       NO
GATE B COMPLETE:                 YES
GATE C:                          WAITING

RECOMMENDED NEXT CLAUDE A ACTION:  Await explicit owner authorization for the AWS KMS / ES256 signing
ceremony (the next gate on the path to Gate C). Until then, take no production action — no KMS, no edge
deploy, no config/flag change, no money, no issuance, no scan, no activation. The substrate is live
through 109 and dark; monitor cron health at leisure (read-only). Venue/promoter payout remain separate,
later, unauthorized.

============================================================

STOP.

DO NOT RUN KMS.
DO NOT DEPLOY EDGES.
DO NOT CONFIGURE PRODUCTION.
DO NOT MOVE MONEY.
DO NOT ISSUE TICKETS.
DO NOT SCAN.
DO NOT ACTIVATE.

============================================================

============================================================
SNATCH IT — PRODUCTION KMS SIGNING CEREMONY EXECUTION
============================================================

2026-09-04 · AWS KMS / ES256 trust-root ceremony · RESULT: NO-GO (NOT EXECUTED) · NO PRODUCTION MUTATION

> The owner explicitly authorized the AWS KMS / ES256 signing ceremony. This session performed the
> authorized READ-ONLY preflight, then STOPPED at the mandatory control gate: the ceremony's own
> governance requires TWO independent named human operators with separated duties, and no single
> principal may both create the KMS key and write the trust-root DB row. A single AI agent cannot
> satisfy that separation, and this session additionally has NO AWS operator access. Per the prompt's
> §3 ("If the required second-person control cannot actually be satisfied: STOP. DO NOT CREATE THE
> TRUST ROOT. RESULT = NO-GO. Do not downgrade two-person control for convenience.") the ceremony was
> NOT executed. No AWS key was created, no kernel.signing_key row was inserted, no signing config was
> set. Production is untouched.

AUTHORIZATION

OWNER KMS AUTHORIZATION:  YES — KMS CEREMONY ONLY
MIGRATIONS:               NOT AUTHORIZED (none performed)
EDGES:                    NOT AUTHORIZED (none deployed)
ACTIVATION:               NOT AUTHORIZED (none performed)
COMMERCE:                 NOT AUTHORIZED (none performed)

------------------------------------------------------------
REPOSITORY
------------------------------------------------------------

BRANCH:              feature/venue-native-and-product-v2
HEAD:                65a5ca1 (at session start) → this execution-record commit follows
CODE RC:             5721a41 — signing implementation byte-identical (git diff 5721a41..HEAD over
                     credential-sign / door-manifest / migrations 102/103 = empty)
CI:                  GREEN on RC 5721a41 (unchanged)
SIGNING CODE DRIFT:  NONE

------------------------------------------------------------
PRE-CEREMONY PRODUCTION  (READ-ONLY)
------------------------------------------------------------

PROJECT:              hqycwntpfoztoinemqns ("Snatch It")
TIMESTAMP:            2026-09-04 15:01:28Z
LEDGER:              124
TIP:                 numeric substrate 109 (all 093–109 present)
SIGNING KEYS:        0
EXPECTED FINGERPRINT: null
SIGNING MONITOR:     false
NATIVE ISSUANCE:     false
NATIVE SCANNING:     false
NATIVE EDGES:        NOT DEPLOYED (11 legacy edges only)
NATIVE DATA:         tickets 0, door_pin 0, door_session 0, scan 0
INVARIANT FN:        kernel.check_signing_key_invariants present; signing_key.algorithm column present
DRIFT:               NONE

The database substrate is correctly staged to RECEIVE a trust root (through 109, 0 keys, fingerprint
null, monitor false, fully dark). The technical DB preconditions for the ceremony are satisfied.

------------------------------------------------------------
PRE-CEREMONY GATE
------------------------------------------------------------

RESULT:      NO-GO (execution) — the technical DB preconditions are GO, but the mandatory two-person
             separation and AWS-operator availability are NOT satisfiable in this session.
TWO-PERSON:  NO — cannot be satisfied.

Technical DB preconditions (all GO):
[x] production through 109           [x] native issuance false
[x] ledger 124                       [x] native scanning false
[x] signing keys = 0                 [x] native edges absent
[x] expected fingerprint = null      [x] no unexpected native data
[x] signing monitor = false          [x] owner D1 = AWS KMS / D2 = ES256 (ratified)
[x] PFA-PT-6 ratified                [x] PFA-PT-8 ratified
[x] signing implementation == preflight (no drift)   [x] no P0/P1 discovered

Ceremony execution preconditions (BLOCKING — both fail):
[ ] TWO-PERSON separation available — FAIL. The runbook §2 requires two NAMED individuals who do not
    share credentials: Person A (Key Custodian) holds kms:CreateKey and NEVER the production DB
    superuser (A5); Person B (Trust Verifier) holds the production DB superuser and NEVER kms:CreateKey
    (B5). Its separation invariant: "No single principal may both create the KMS key and write the
    database row," and "Steps that may be done alone: nothing" (§4 key creation, §5 binding proof, §6
    bootstrap insert all require SIMULTANEOUS presence of both operators). A single AI agent is one
    principal and cannot be two independent, credential-separated humans. Downgrading this is the exact
    thing §3 forbids.
[ ] AWS operator access available — FAIL. This session has no AWS CLI, no AWS credentials, and no
    ~/.aws profile. Person A's cloud side (kms:CreateKey, the §5 Sign, kms:GetPublicKey) cannot be
    performed here, and this agent must not create or handle AWS credentials.

STOP CONDITIONS TRIGGERED: "two-person separation unavailable" (§22). Ceremony halted BEFORE any key
creation, per §3 and §21 (stop and correct BEFORE insertion; no orphan resource created because no
resource was created).

------------------------------------------------------------
AWS KMS KEY
------------------------------------------------------------

KEY CREATED:            NO (not attempted — no AWS access; two-person control unsatisfiable)
KEY ID / ARN:           n/a (no key created; no ARN/fingerprint/public key exists to record)
KEY SPEC:               n/a (would be ECC_NIST_P256 per D2)
KEY USAGE:              n/a (would be SIGN_VERIFY)
SIGNING ALGORITHM:      n/a (would be ECDSA_SHA_256 / ES256)
IAM:                    not evaluated against a live key; the runbook prescribes least privilege
                        (kms:Sign + kms:GetPublicKey on the specific key ARN; NEVER kms:Decrypt, NEVER kms:*)
PRIVATE KEY OUTSIDE KMS: NO (no key material of any kind produced this session)

------------------------------------------------------------
PUBLIC KEY / FINGERPRINT
------------------------------------------------------------

PUBLIC KEY FORMAT:   SPKI PEM (the frozen representation, per runbook D3) — none produced this session
PERSON A FINGERPRINT: n/a (no key)
PERSON B FINGERPRINT: n/a (no independent human verifier)
MATCH:               n/a — the §5 binding proof (A signs a challenge through the handle, B verifies
                     against B's own independently exported public key) is the ceremony's load-bearing
                     step and requires two humans; it was not and could not be performed here.

------------------------------------------------------------
BOOTSTRAP SIGNING KEY
------------------------------------------------------------

DB INSERT:            NO — no row inserted into kernel.signing_key.
COUNT BEFORE:         0
COUNT AFTER:          0  (unchanged — production untouched)
STATUS / ALGORITHM:   n/a
PUBLIC KEY MATCH:     n/a
KMS HANDLE MATCH:     n/a
SECOND KEY CREATED:   NO
NOTE: the bootstrap insert (runbook B4) is a PRODUCTION DB MUTATION reserved to the DB SUPERUSER held
by a human Person B, gated on the independent §5 fingerprint agreement with a human Person A. This
agent did not and must not perform it unilaterally.

------------------------------------------------------------
SIGNING CONFIG
------------------------------------------------------------

EXPECTED FINGERPRINT: null (UNCHANGED — not set; there is no verified ceremony fingerprint to set)
MONITOR ENABLED:      false (UNCHANGED — not armed)
CONFIG MATCH:         n/a — no config was written this session

------------------------------------------------------------
INVARIANTS
------------------------------------------------------------

KEY COUNT:   0 (no trust root established)
ALG PIN:     kernel.signing_key.algorithm column present (103); trusted-key pinning code intact (no drift)
TYP / DOMAIN: enforcement intact in the signer (no drift; not exercised — no key)
PUBLIC KEY:  n/a (no key)
FINGERPRINT: n/a (none derived)
KMS HANDLE:  n/a (none)
PROVISION:   PARKED (unchanged, PFA-18A)
ROTATE:      PARKED (unchanged, PFA-18A)
REVOKE:      AVAILABLE under platform_admin + aal2 (PFA-18B, migration 106) — unchanged
MONITOR:     not armed (false); kernel.check_signing_key_invariants present but not run against a key
             (there is no key to check)

------------------------------------------------------------
SAFE SIGNING TEST
------------------------------------------------------------

TEST MESSAGE:          n/a — not performed. The §5 safe binding proof (KMS Sign of a canonical
                       non-business challenge → DER→raw R||S → local verify; wrong-key/altered-message
                       must fail) requires a live AWS key and the two-person binding proof, neither of
                       which exists here.
KMS SIGN:              NOT RUN
DER→RAW / LOCAL VERIFY: NOT RUN
ALTERED / WRONG KEY:   NOT RUN
BUSINESS FACT CREATED: NO
(The signer's AwsKmsSigner / ES256 DER↔raw / sign-after-verify / fail-closed logic is unchanged from the
RC and was proven green in the vitest adapter tests at preflight; it was NOT re-exercised against a live
KMS key this session because no key exists.)

------------------------------------------------------------
POST-CEREMONY DARKNESS  (unchanged — production untouched)
------------------------------------------------------------

MIGRATION TIP:      109
SIGNING KEYS:       0  (NO trust root established)
TRUST ROOT:         NOT ESTABLISHED
NATIVE ISSUANCE:    false
NATIVE SCANNING:    false
NATIVE EDGES:       NOT DEPLOYED
TICKETS:            0
CREDENTIALS:        0
SCANS:              0
MONEY MOVED:        NO
PRIMARY TICKETING LIVE: NO

------------------------------------------------------------
OBSERVABILITY
------------------------------------------------------------

DB:          read-only via Supabase MCP (schema_migrations, kernel.signing_key, catalog.platform_config,
             kernel.tickets, venue.door_pin/door_session/scan, information_schema) — all as expected; 0 keys
KMS:         no AWS API called (no AWS access); no KMS resource created or queried
CRON / MONITOR: not changed; signing monitor remains false (unarmed)
SENTRY:      NOT queried
CLOUDTRAIL:  NOT queried (no AWS activity to audit — nothing was done in AWS)
UNEXPECTED ERRORS: none (no mutation attempted)

------------------------------------------------------------
CEREMONY RESULT
------------------------------------------------------------

RESULT: NO-GO (NOT EXECUTED)

REASON: the mandatory two-person separation of duties (runbook §2; prompt §3) cannot be satisfied by a
single AI agent, and this session has no AWS operator access. The ceremony was halted BEFORE any key
creation or DB write. This is a clean pre-mutation stop, not a partial failure or incident — nothing was
created, so there is no orphan KMS resource and no partial trust-root state.

P0: 0
P1: 0

------------------------------------------------------------
GATES
------------------------------------------------------------

GATE A — BACKEND CONSTRUCTION:        GO
GATE B — DATABASE SUBSTRATE:          COMPLETE (through 109, live-but-dark)
KMS TRUST ROOT:                       NOT ESTABLISHED (this session NO-GO; awaiting a two-person human ceremony)
GATE C — FIRST CONTROLLED SALE:       WAITING
VENUE PAYOUT:                         NOT AUTHORIZED
PROMOTER PAYOUT:                      NOT AUTHORIZED

------------------------------------------------------------
REMAINING GATE C ITEMS
------------------------------------------------------------

TAX:              OPEN (LEGAL/TAX; blocks quote/PaymentIntent/first sale)
FEE:              fee.buyer_service_bps null — owner value required
EDGES:            credential-sign, primary-checkout, door-session (+door-manifest) NOT deployed
ORG:              no production org onboarded
VENUE:            no approved venue
CONNECT:          no Connect onboarding / transfers capability
ISSUANCE:         feature.native_issuance_enabled false
SCANNING:         feature.native_scanning_enabled false
DOOR PIN:         none provisioned
OWNER SALE AUTH:  not given
PLUS (new, because this session did NOT complete it): the KMS trust root (the AWS KMS ES256 key + the
                  one bootstrap kernel.signing_key row + signing.expected_key_fingerprint) still must be
                  established by a two-person human ceremony.

------------------------------------------------------------
NEXT OPERATION
------------------------------------------------------------

The next owner-authorized operation is the SAME AWS KMS / ES256 trust-root ceremony, run by TWO NAMED
HUMANS per docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md — it cannot be delegated to a single AI agent.
Minimum viable execution:

  • Person A (Key Custodian): an IAM principal with kms:CreateKey, NOT holding the production DB
    superuser. Creates ONE asymmetric key (KeySpec ECC_NIST_P256, KeyUsage SIGN_VERIFY,
    ECDSA_SHA_256), scoped least-privilege (kms:Sign + kms:GetPublicKey on that key ARN; never
    kms:Decrypt, never kms:*).
  • Person B (Trust Verifier): holds the production DB superuser, NOT kms:CreateKey. Independently
    exports the public key, computes the fingerprint, and — only after the §5 binding proof (A signs a
    canonical challenge through the handle; B verifies against B's own exported SPKI) matches to the
    byte — runs the bootstrap transaction inserting EXACTLY ONE kernel.signing_key row (global, ES256,
    active, public_key SPKI, kms_handle_ref version-pinned ARN), sets signing.expected_key_fingerprint
    to the verified fingerprint, and (per the runbook's timing) arms signing.monitor_enabled and runs
    kernel.check_signing_key_invariants.

An AI agent may at most ASSIST a human Person B with the read-only/scripted DB-side mechanics under that
human's superuser session — it may not BE Person A or Person B, and may not stand in for the second
person. DO NOT EXECUTE the ceremony in an agent-only session.

------------------------------------------------------------
FINAL STATUS
------------------------------------------------------------

OWNER KMS AUTHORIZATION:       YES
CEREMONY:                      NO-GO (NOT EXECUTED)
AWS KMS KEY CREATED:           NO
ES256:                         n/a (no key)
TWO-PERSON VERIFIED:           NO (not satisfiable by a single AI agent)
SIGNING KEY COUNT:             0 (unchanged)
EXPECTED FINGERPRINT SET:      NO (null, unchanged)
SIGNING MONITOR HEALTHY:       n/a (unarmed; no key)
SAFE KMS SIGN TEST:            NOT RUN
MIGRATION TIP:                 109
NATIVE ISSUANCE:               false
NATIVE SCANNING:               false
NATIVE EDGES DEPLOYED:         NO
TICKETS ISSUED:                NO
CREDENTIALS ISSUED:            NO
SCANS:                         NO
MONEY MOVED:                   NO
PRIMARY SALE ACTIVATED:        NO
VENUE PAYOUT ACTIVATED:        NO
PROMOTER PAYOUT ACTIVATED:     NO
KMS TRUST ROOT COMPLETE:       NO
GATE C:                        WAITING

RECOMMENDED NEXT CLAUDE A ACTION:  Do NOT attempt the ceremony in an agent-only session. Schedule the
two-person human ceremony per PRODUCTION_SIGNING_KMS_CEREMONY.md (Person A = AWS/KMS custodian with
kms:CreateKey; Person B = DB trust-verifier with the production superuser; both present for key creation,
the §5 binding proof, and the bootstrap insert). This Claude A session may assist Person B with the
read-only DB-side verification mechanics under that human's own superuser session, but takes no
production action itself. Production remains substrate-through-109, 0 signing keys, fully dark; no KMS,
no edges, no config, no money, no issuance, no scan.

============================================================

STOP.

DO NOT DEPLOY EDGES.
DO NOT ENABLE ISSUANCE.
DO NOT ENABLE SCANNING.
DO NOT SET FEES.
DO NOT ONBOARD CONNECT.
DO NOT CREATE A SALE.
DO NOT ISSUE A TICKET.
DO NOT SCAN.
DO NOT MOVE MONEY.
DO NOT ACTIVATE PAYOUTS.

============================================================

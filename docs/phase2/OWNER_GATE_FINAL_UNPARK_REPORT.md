============================================================
SNATCH IT — OWNER GATE + FINAL UN-PARK REPORT
============================================================

Migrations 106–109 + door-session edge · 2026-09-04 · DARK / UNAPPLIED / UNDEPLOYED

> **THIS IS NOT PRODUCTION AUTHORIZATION.** No migration applied to production; no edge deployed; no
> schema exposed; no config/flag changed; no KMS key created; no ceremony run; no signing_key inserted;
> no KMS Sign called; no Connect/PaymentIntent/money/ticket/credential/scan in production; nothing
> activated; no secret rotated. Production inspection was READ-ONLY. Tax stays fail-closed (PFA-PT-7
> unchanged). `deletion.post_event_hold_hours` stays owner-unset. Owner DIRECTIONS for the gating PFAs
> were received this train and RECORDED; the literal owner-signature fields remain PENDING — engineering
> did NOT self-sign.

REPOSITORY

BRANCH:      feature/venue-native-and-product-v2
ENTRY HEAD:  7897f2e (package 105 + door edges) — pushed, CI green
FINAL HEAD:  <recorded post-commit below> — the four un-park migrations + tests + governance + edge
REMOTE:      origin = SnatchIt-app/snatchit
PR:          #52 — OPEN, MERGEABLE
CI:          GREEN on entry 7897f2e (CI push run SUCCESS; Migrations guard SUCCESS); the train commit's CI runs on push
WORKTREE:    migrations 106–109 (+ rollbacks, tests 172–175), census edits, governance/matrix/runbook/
             ceremony updates, door-session edge wired to the machine RPCs. Migrations 093–105 byte-
             untouched (git diff empty); 076–092 untouched.

PRODUCTION  (READ-ONLY, via Supabase MCP — project hqycwntpfoztoinemqns)

LEDGER:        107 rows — tip 20260902003623 (through 092; 093–109 unapplied)
TIP:           092 substrate live-but-DARK; 093–109 NOT applied (0 of 093–109 in schema_migrations)
SIGNING KEYS:  0
NATIVE EDGES:  NOT DEPLOYED (11 legacy resale edges only; no credential-sign / primary-checkout /
               refund/payout-execute / door-session / door-manifest)
MUTATIONS:     NONE (force_close_key_manifests absent, signing_key.algorithm column absent,
               revoke_signing_key still the PARKED body in prod — all confirmed by read-only query)

------------------------------------------------------------
OWNER DIRECTIONS
------------------------------------------------------------

PFA-18B:   RECEIVED — un-park revoke under SINGLE platform_admin + aal2 (emergency tightening);
           provision/rotate STAY parked (asymmetric). ENGINEERING LANDED (106). READY FOR SIGNATURE.
PFA-26:    RECEIVED (PFA-26-UNPARK) — pgcrypto bcrypt cost 12, per-hash salt, frozen signatures, edge
           rate-limiter is the brute-force control. ENGINEERING LANDED (107). READY FOR SIGNATURE.
PFA-PT-6:  RECEIVED — approve the existing JWS-compact wire format as-is (no redesign). READY FOR SIGNATURE.
PFA-PT-8:  RECEIVED — approve trusted-key algorithm pinning (migration 103). READY FOR SIGNATURE.
PFA-PT-9:  RECEIVED — item 1 ratify 104 gate; item 2 wire terminal force-close (LANDED, 109); item 3 NO
           record_scan version backstop; item 4 accept offline residual; item 5 break-glass runbook step.
           READY FOR SIGNATURE (items 1 & 3).
KMS D1:    RECEIVED — AWS KMS (reference production provider).
KMS D2:    RECEIVED — ES256 / ECDSA P-256 (SHA-256).

GOVERNANCE STATUS FOR EACH: recorded in docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md
  ("OWNER GATE RATIFICATION TRAIN — 2026-09-03"). Each: OWNER DIRECTION RECEIVED — READY FOR SIGNATURE,
  with the exact owner-approval text preserved in the individual PFA block. NOT self-signed. The KMS
  ceremony runbook (§1.2) now records D1=AWS KMS / D2=ES256 and removes the placeholder ambiguity.

------------------------------------------------------------
REVOKE UN-PARK  (migration 106, PFA-18B)
------------------------------------------------------------

IMPLEMENTED:   YES — kernel.revoke_signing_key real body (was PARKED dual_control_unavailable in 086).
AUTH:          platform_admin ONLY (kernel.is_platform([platform_admin]); granted to authenticated,
               NOT service_role). venue_manager/org_owner/platform_support/buyer/anon all refused (test 172 A1).
AAL2:          required — the 085/096 step-up idiom verbatim: absent aal claim → step_up_unavailable;
               aal1 → step_up_required; only 'aal2' passes (test 172 A2).
AUDIT:         kernel.admin_audit signing_key.revoke (before/after + ack + open-episode count + command_key).
KEY STATE:     forward-only status='revoked' (guard permits active|rotating→revoked; revoked terminal).
               not_after LEFT AS-IS — status is the authority (get_ticket_signing_context refuses on
               status<>'active'; the M1 keyring distributes status). Writing not_after=now() would break
               signing_key_window_ck for a same-instant key (found in test, corrected).
FORCE-CLOSE:   every OPEN in-scope episode closed via kernel.force_close_key_manifests (105) →
               close_reason='key_revoked' + DoorManifestInvalidated (#44, REQ/durable) per episode
               (test 172 B2–B7: scope-exact, out-of-scope isolation).
NEW MANIFEST AFTER REVOKE: BLOCKED — venue.open_door_manifest re-created to refuse opening a session
               whose atoms are pinned to a revoked key (test 172 C3). The check runs under the rank-1
               session lock and AFTER the already-open idempotency branch (a legitimate replay of an
               existing open episode still returns noop_replay; only a NEW open is gated).
RACE:          revoke locks EVERY in-scope session FOR UPDATE (ascending session_id) BEFORE the key flip
               — a SUPERSET of force_close's locked set — so revoke, force_close and cancel_event all
               acquire in one monotonic order (the P2 deadlock an independent reviewer found, where
               loop-1 skipped terminal sessions force_close would later lock, is CLOSED). open-before-
               revoke → episode force-closed; revoke-before-open → refused.
IDEMPOTENCY:   a revoked key replays as noop_replay BEFORE the ack check (test 172 C1); unknown key →
               not_found (C2); wrong non-null ack → unacknowledged_live_credentials (B1); null ack →
               emergency bypass. The ack count is taken UNDER the session lock (tight).
SIGNER:        no fallback — get_ticket_signing_context resolves ONLY the atom's pinned key and refuses
               a revoked key with signing_key_unavailable (test 172 C4).

------------------------------------------------------------
PIN UN-PARK  (migration 107, PFA-26-UNPARK)
------------------------------------------------------------

IMPLEMENTED:   YES — venue.create_door_pin + venue.mint_door_session (both were PARKED
               door_pin_kdf_unavailable). `create extension if not exists pgcrypto with schema
               extensions` (idempotent — already present in prod/CI/rehearsal).
KDF:           pgcrypto bcrypt — crypt(pin, gen_salt('bf',12)) store; crypt(pin, pin_hash)=pin_hash verify.
COST:          bf 12.
SALT:          per-hash, embedded in the modular-crypt output ('$2a$12$…') stored in pin_hash — no new column.
STORAGE:       bcrypt verifier only; never plaintext; never returned to a client; never logged
               (create audit stores label only; edge logOutcome has a fixed non-secret field set).
               test 173 P6 asserts the stored hash begins '$2a'.
VERIFY:        constant-time crypt compare; mint loops active PINs for (venue,session). On a MISS
               (unknown device / session-not-in-venue / no active PIN / wrong PIN) it spends ONE bcrypt
               dummy before raising, so a miss costs ~a single-PIN verify (closes the armed-vs-unarmed
               timing oracle a reviewer flagged). All failures raise the SAME opaque door_session_invalid
               (test 173 M3/M4 — no existence oracle).
RATE LIMIT:    the door-session edge NS_DOOR_PIN limiter (venue||device, 5/60, fail-closed) is the
               brute-force control (owner-directed). Wrong PIN consumes budget; /refresh cannot launder
               /mint (same principal+action). RESIDUAL (accepted, PFA-26): the key has no session/IP
               component, so budget scales with known devices, and PIN length is not frozen — a
               PIN-length floor / per-(venue,session) lockout is an owner/product decision, not invented here.
ROTATION:      revoke_door_pin + create a new PIN (test 173 M7 — revoked PIN fails mint closed). Re-mint
               revokes the prior active session; the device row is locked FOR UPDATE so concurrent
               re-mints cannot race the active-session partial unique.
LEAKAGE:       none — PIN/hash/secret never returned or logged; cross-tenant blocked (create + mint both
               require the session to belong to the venue; test 173 P5).

------------------------------------------------------------
MACHINE DOOR AUTHORITY  (migration 108)
------------------------------------------------------------

IMPLEMENTED:   YES — venue.record_scan_door + venue.reconcile_offline_scans_door (service_role machine
               entrypoints); venue._record_scan_core + venue._reconcile_core (zero-grant shared bodies);
               venue.record_scan + reconcile_offline_scans re-created to delegate to the cores. The
               door-session edge /scan + /offline-batch now relay to the *_door RPCs.
SERVICE_ROLE:  MAY EXECUTE, DECIDES NOTHING. Both machine entrypoints call kernel.assert_door_session
               unconditionally and use the RETURNED bound (device, session); a service_role holder
               without a valid door session cannot admit anything. The zero-grant cores are unreachable
               by anon/authenticated/service_role (revoked from all incl. public) — reached only via the
               definer entrypoints (test 174 D7: authenticated → permission denied).
DOOR SESSION:  the sole gate; a body device/session that disagrees with the token's bound row raises the
               opaque door_session_invalid (test 174 D3/D4).
DEVICE:        server-derived from assert_door_session; scan_meta.device_id rejected (D2); the scan row
               is device-attributed with a NULL actor (D6; bound device is NOT NULL, satisfies
               scan_attribution_ck).
SESSION:       bound; a door session for A cannot admit B's atom (D5 → 'invalid'); a per-item wrong
               session in a batch is isolated as a conflict (D8).
CROSS-VENUE:   impossible — scope is 100% the asserted bound.
BODY OVERRIDE: caught (D2/D3/D4). Reconcile poison-pill fully closed: a malformed/non-UUID
               ticket_atom_id is isolated as a conflict, not a batch abort (D11 — the atom cast is now
               INSIDE the per-item block, fixing a defect inherited verbatim from 105/086).
NON-REGRESSION: the authenticated record_scan preserves 104's observable check ORDER (flag gate before
               role gate — restored after a reviewer noted the core-refactor had reordered it); behavior
               otherwise equivalent to 104/105.

------------------------------------------------------------
CANCEL FORCE-CLOSE  (migration 109, PFA-PT-9 item 2)
------------------------------------------------------------

IMPLEMENTED:   YES — a TRIGGER (catalog.tg_session_terminal_force_close, AFTER UPDATE OF status) fires on
               a session transition INTO cancelled/completed and calls kernel.force_close_session_manifests
               (a session-scoped, zero-grant sibling of force_close_key_manifests). NOT a cancel_event
               rewrite — the narrowest wiring (train §12).
SCOPE:         only the cancelled session's OPEN episode; unrelated events untouched (test 175 C6).
INVALIDATION:  close_reason='event_cancelled' + DoorManifestClosed parity + DoorManifestInvalidated
               (#44, REQ) (test 175 C3/C4/C5).
DUPLICATE CANCEL: no re-fire, no re-emit — the second cancel updates 0 rows (status already cancelled),
               so the trigger's WHEN (old.status distinct from new) is false (test 175 C8/C9).
MONEY NON-REGRESSION: guaranteed BY CONSTRUCTION — the trigger touches only door_manifest + outbox +
               audit; ZERO economic bytes changed; cancel_event's 088 money body is byte-untouched
               (test 175 C7 — comp atoms still skip-voided; G4/G5 unchanged in 166/167). Only 'cancelled'
               is currently reachable; 'completed' is covered defensively (no writer exists — train §13).

------------------------------------------------------------
PFA-PT-9
------------------------------------------------------------

ITEM 1:  APPROVED (owner) — 104 terminal-session record_scan gate ratified (test 170).
ITEM 2:  IMPLEMENTED — terminal force-close wired (109, trigger; test 175).
ITEM 3:  APPROVED (owner) — NO record_scan credential_version backstop; currency stays C37/verifier.
ITEM 4:  ACCEPTED — offline not_after residual bounded by door.manifest_ttl_interval.
ITEM 5:  break-glass admin-transfer force-close/refresh — added to the activation runbook (§ Package 106–109).

------------------------------------------------------------
KMS
------------------------------------------------------------

PROVIDER:        AWS KMS (owner-directed D1).
ALGORITHM:       ES256 / ECDSA P-256 SHA-256 (owner-directed D2); the bootstrap kernel.signing_key.algorithm
                 column (103) is set to 'ES256' at the ceremony.
ADAPTER:         AwsKmsSigner (SigV4, ES256 DER↔raw R||S, sign-after-verify, fail-closed) — unchanged.
NON-REGRESSION:  vitest green (KMS adapter tests unchanged).
CEREMONY EXECUTED: NO. Runbook §1.2 updated with D1/D2; ARN/fingerprint stay placeholders.

------------------------------------------------------------
CRYPTO NON-REGRESSION
------------------------------------------------------------

PFA-PT-6:  wire format unchanged; owner direction received; READY FOR SIGNATURE.
PFA-PT-8:  algorithm pin unchanged (103); owner direction received; READY FOR SIGNATURE.
M1:        verifyToken (typ/kid/alg-pin/signature/exp) — unchanged, green.
M2:        offline-verify OFFLINE-VERIFY-v1 core — unchanged, green.
TYP:       enforced before signature (prior train fix) — unchanged.
ALG PIN:   trusted-key algorithm (103) — unchanged.
ROTATION:  unchanged (test 169 C).
OLD OWNER: verifier stale_version + credential_version bump — unchanged.
(The door-session pure module's misleading sha256 "token_hash" helper was corrected: the authoritative
 token_hash is DB-owned md5('door_session:'||secret) (mint 107 / assert 086); the edge computes none.)

------------------------------------------------------------
MONEY NON-REGRESSION
------------------------------------------------------------

G4:        PASS (test 166 — venue obligation 9000, excludes held commission).
G5:        PASS (test 167 — cross-venue recovery refused).
REFUND:    engineering-ready, DARK, undeployed — untouched.
PAYOUT:    engineering-ready, DARK, undeployed — untouched.
PROMOTER:  DARK, out of scope — untouched.
(106–109 change NO economic byte. 109's trigger touches only the door plane; 108 touches only the scan
 plane; 106/107 touch only signing/PIN. cancel_event's 088 money body is byte-identical.)

------------------------------------------------------------
MIGRATIONS
------------------------------------------------------------

PREVIOUS TIP:  105
NEW TIP:       109
FILES:         106_revoke_signing_key_unpark.sql, 107_door_pin_kdf_unpark.sql,
               108_door_machine_scan_authority.sql, 109_terminal_session_manifest_forceclose.sql
               (+ four rollbacks, + tests 172–175).
HASHES:        106 = 2f3c63686bfc4cd4c7c2bf024be3ba28
               107 = 1765357ea11ab4726a28129035ae33d1
               108 = 69a0e658acb132ef13dc6854308aa7ff
               109 = 55d5a2f492fd98051bca71fabcbc4871
CENSUS:        kernel functions 148 → 149 (+1 force_close_session_manifests); catalog 16 → 17 (+1
               tg_session_terminal_force_close); venue 79 → 83 (+4: _record_scan_core, _reconcile_core,
               record_scan_door, reconcile_offline_scans_door); five-schema routines 282 → 288. Gate-2
               public census UNCHANGED at 27/70/37/26 (no public-schema object). Grants: +2 service_role
               (the two *_door entrypoints); the two cores + the session-scoped helper + the trigger fn
               are zero-grant (PUBLIC revoked). Census tests bumped: 141/142/143/144/145/148/154/156/157;
               parked-behavior assertions updated in 150.
ROLLBACK:      four rollbacks; each verified to revert (106/107 restore the parked bodies; 108 restores
               104/105 bodies + drops the 4 fns; 109 drops trigger + 2 fns). pgcrypto is left installed on
               107 rollback (dropping a shared extension is unsafe; documented, harmless when unused).
EXISTING ROW MUTATION: NONE. Forward-only; no data backfill; no hidden activation (all un-parks become
               reachable only when flags/keys/PINs/config are later set).

------------------------------------------------------------
SECURITY
------------------------------------------------------------

P0:   0 OPEN.
P1:   0 OPEN. Two P1s were FOUND by the adversarial pass and FIXED: (a) the door-session edge /mint
      called mint_door_session with wrong argument names (p_device_id_claim/p_pin) → the whole mint path
      failed closed; corrected to the frozen names. (b) the reconcile poison-pill (a non-UUID
      ticket_atom_id aborted the whole batch) — the atom cast moved inside the per-item block + test D11.
P2:   0 code-level OPEN. Fixed this train: the revoke/cancel deadlock (lock all in-scope sessions
      ascending); the PIN mint timing oracle (dummy bcrypt on miss); the re-mint race (device FOR UPDATE);
      the record_scan flag/role check-order oracle (restored); the pure-module token_hash mislabel. Accepted
      residuals (documented): the door-PIN rate-limit keying + unfrozen PIN length (owner-accepted PFA-26
      control); reconcile_offline_scans_door ignores rather than rejects a per-item device_id (safe — never
      read; the edge rejects it); an unbounded create_door_pin expires_at + unbounded active-PIN count
      (minor); test 175 covers only the comp-atom cancel path (money non-regression is by-construction; a
      paid-order cancel regression test is a tracked hardening item, G4/G5 cover the invariants).

REVOKE BYPASS:       none — platform_admin + aal2, in-body, granted to authenticated only.
PIN LEAK:            none — bcrypt only, never returned/logged; opaque failure.
BRUTE FORCE:         edge rate-limiter fail-closed (owner-accepted control); timing oracle closed.
SERVICE_ROLE BYPASS: none — assert_door_session gates every machine write; cores zero-grant.
CROSS-VENUE:         none — assert-bound scope; create/mint session∈venue guards.
STALE MANIFEST:      reconnect → no_open_episode / #44; offline bounded by not_after (honest residual).
DOUBLE SCAN:         online prevented (unique index); offline reconciled to one admit; repeat → conflict.

------------------------------------------------------------
ADVERSARIAL
------------------------------------------------------------

REVIEWERS: five independent reviewers — (A) revoke authority + race; (B/C) PIN KDF + door-session mint;
           (D/E) machine door authority + service_role; (F/G) cancel force-close + money; (K/L) migration
           discipline + rollback + census + activation-gap. (Crypto/M1/M2/KMS and G4/G5 non-regression were
           re-attested from the unchanged prior-package cores + the money tests 166/167.)
CLAIMS OVERTURNED: "the reconcile per-item cast is isolated" (it was NOT — a non-UUID atom poisoned the
           whole batch, inherited from 105); "record_scan is byte-identical to 104" (the core refactor had
           reordered the flag/role gates); "revoke locks all in-scope sessions so no deadlock" (loop-1
           skipped terminal sessions force_close would lock); the pure module's "token_hash = sha256(...)"
           claim (the real contract is DB md5('door_session:'||secret)).
DEFECTS FOUND:     2 P1 (edge /mint arg names; reconcile poison-pill) + P2s (revoke/cancel deadlock; PIN
           mint timing oracle; re-mint race; record_scan check-order; pure token_hash mislabel).
DEFECTS FIXED:     all of the above, each with a test or a corrected contract (172/173/174 additions;
           edge + pure edits).
OPEN:              no P0/P1. Documented low-severity residuals: PIN rate-limit keying + unfrozen PIN length
           (owner-accepted); reconcile_door per-item device_id ignore-not-reject (safe); unbounded PIN
           expires_at / active-PIN count (minor); the comp-only cancel test (money non-regression by
           construction). None blocks a controlled sale/scan.

------------------------------------------------------------
TESTING
------------------------------------------------------------

FRESH DB:      PASS — replay 000→109, Gate-2 27/70/37/26 (== CI baseline).
PGTAP:         PASS — TOTAL plan=3695 ok=3691 not_ok=4; "matches the expected local baseline" (the 4 are
               the documented local-only deltas: 060 ×2, 132 ×2). New tests 172–175 = 48/48.
VITEST:        PASS — 15 files, 669 tests (door-session pure trimmed of the 3 misleading token_hash tests;
               2 NIST sha256-vector tests kept as a generic-hash check).
TYPECHECK:     PASS — exit 0.
LINT:          PASS — 0 errors (45 baseline warnings).
WEB:           no shared web contract changed (typecheck covers test-imported modules).
MOBILE:        no mobile-facing contract changed.
ASSEMBLER:     PASS — G-4 (093 byte-identical).
GATE-2:        27/70/37/26 (unchanged).
REVOKE:        172 (15) — authz, aal2, ack, force-close cascade, scope isolation, replay, open-refuse,
               signer-refuse, unknown-key.
PIN:           173 (13) — bcrypt storage, authz, envelope, cross-tenant, mint verify, opaque failure,
               token contract, re-mint, PIN-revoke-kills-mint.
RATE LIMIT:    door-session pure tests (namespace/key derivation) green.
MACHINE AUTH:  174 (11) — admit, scan_meta.device_id reject, body device/session reject, cross-session
               refuse, device-attribution, service_role-only, batch isolation, dedupe, poison-pill (D11).
CANCEL:        175 (9) — force-close on cancel, #44, scope isolation, duplicate-cancel no-re-emit, money
               non-regression.
OFFLINE:       offline-verify core (prior) green; reconcile isolation proven (171 R2, 174 D8/D11).
RECONCILE:     171 R1/R2 + 174 D8/D9/D10/D11.
M1/M2:         prior packages, green.
KMS:           adapter tests green (unchanged).
ROTATION:      169 C green.
MONEY:         166/167 green.
ROLLBACK:      all four (106–109) apply cleanly and revert state (door fns 0, trigger 0, revoke re-parked).
CI:            GREEN on entry 7897f2e; the train commit's CI runs on push.

------------------------------------------------------------
ACTIVATION MATRIX  (see PRIMARY_TICKETING_ACTIVATION_MATRIX.md — package-106–109 re-derivation)
------------------------------------------------------------

EVENT DRAFT:            code ✓ · migrated ✓(dark) · NOT ACTIVATED
EVENT PUBLISH:          code ✓ · ratified ✓ · NOT migrated · NOT ACTIVATED
PRIMARY SALE:           code ✓ · NOT migrated · edge NOT deployed · NOT ACTIVATED
PAYMENT CONFIRMATION:   code ✓ · NOT migrated · edge NOT deployed · NOT ACTIVATED
TICKET ISSUANCE:        code ✓ · migrated ✓(dark) · KMS not configured (0 keys) · NOT ACTIVATED
CREDENTIAL SIGN:        code ✓ · PFA-PT-6/8 owner-directed, READY FOR SIGNATURE · NOT migrated · NOT ACTIVATED
DOOR SESSION:           code ✓(DARK, PIN un-parked 107, edge relays machine RPCs) · PFA-26 READY FOR SIGNATURE · NOT ACTIVATED
DOOR MANIFEST:          code ✓(DARK, optional) · KMS (or TLS MVP) · NOT ACTIVATED
DOOR VERIFY:            M1/M2 cores ✓ · door RPCs migrated ✓(dark) · NOT ACTIVATED
SCAN:                   code ✓(104 gate + 108 machine authority) · NOT migrated · NOT ACTIVATED
OFFLINE RECONCILIATION: code ✓(105/108, poison-pill fixed) · NOT migrated · NOT ACTIVATED
REFUND:                 code ✓ · migrated ✓(dark) · edge NOT deployed · NOT ACTIVATED
SETTLEMENT:             code ✓ · migrated ✓(dark) · NOT ACTIVATED
VENUE PAYOUT:           code ✓ · migrated ✓(dark) · edge NOT deployed · NOT ACTIVATED
PROMOTER PAYOUT:        DARK / out of scope · NOT ACTIVATED

------------------------------------------------------------
REMAINING BLOCKERS BY CLASS
------------------------------------------------------------

ENGINEERING:        NONE that is new architecture. The four un-parks (revoke, PIN, machine door
                    authority, terminal force-close) are BUILT + TESTED. provision_signing_key /
                    rotate_signing_key remain PARKED under PFA-18A by design (a credential dual-control
                    mechanism is a separate owner-decision build, NOT required for a controlled first
                    sale — the bootstrap key is a two-person ceremony insert). No other in-band code gap.
OWNER/GOVERNANCE:   PFA-18B, PFA-26-UNPARK, PFA-PT-9 (items 1&3), PFA-PT-6, PFA-PT-8 — owner directions
                    received; literal signatures pending. (KMS D1/D2 decided.)
LEGAL/TAX:          PFA-PT-7 — unchanged, OPEN.
PRODUCTION OPERATION: migrate 093→109; deploy the DARK edges; the KMS ceremony (AWS KMS / ES256);
                    config; org onboarding; schema exposure; deletion.post_event_hold_hours owner-set.
OBSERVATION:        the production-observation closeout artifact before migrate.
OPTIONAL HARDENING: a PIN-length floor / per-(venue,session) lockout; a paid-order cancel regression test;
                    reconcile_door explicit per-item device_id rejection; Argon2id-in-edge PIN KDF; a cap
                    on active PINs per session.

------------------------------------------------------------
FIRST SAFE SALE + SCAN  (exact remaining sequence — DO NOT EXECUTE)
------------------------------------------------------------

1.  Owner signs PFA-18B, PFA-26-UNPARK, PFA-PT-9 (1&3), PFA-PT-6, PFA-PT-8. (D1/D2 decided.)
2.  Owner/counsel resolve TAX (PFA-PT-7) or affirm compute-none; set deletion.post_event_hold_hours.
3.  Production-observation closeout artifact confirmed (ledger 107, 0 keys, native edges undeployed, no mutation).
4.  Apply migrations 093→109 to production (forward-only; hashes pinned; AUTODEPLOY-VERIFIED-OFF; git_branch empty).
5.  KMS ceremony (two-person): create the AWS KMS asymmetric ES256 key; insert ONE kernel.signing_key row
    (SPKI public_key, version-pinned kms_handle_ref, algorithm='ES256') — a global bootstrap key. Verify the trusted key.
6.  Deploy the DARK edges (credential-sign, primary-checkout, door-session, door-manifest) with KMS + provider env.
7.  Provision the door PIN(s) via create_door_pin (now un-parked); onboard a real org (Connect + fee.buyer_service_bps);
    expose the RPC surface to PostgREST; publish an event on_sale (A8a′'s four gates satisfiable).
8.  First quote → PaymentIntent → issue_ticket_atoms (THE irreversible point, G3) → credential-sign (M1) →
    door M1 verify → C37/M2 → controlled door scan (record_scan_door) → offline reconcile (reconcile_offline_scans_door).
9.  Break-glass (PFA-PT-9 item 5): an admin_action transfer during an OPEN episode → force-close/refresh that session.
10. Prove a refund end-to-end before widening.

------------------------------------------------------------
FIRST SAFE PAYOUT  (separate — DO NOT EXECUTE)
------------------------------------------------------------

1.  First safe sale proven + settled.
2.  Deploy payout-execute (DARK); confirm settlement close (G4 obligation excludes held commission).
3.  Enable payout.executor_enabled under dual control; execute ONE venue payout; verify transfer+ledger.
4.  Confirm the reversal/obligation-recovery path (G5 venue-scoped) on a test reversal before widening.
(Promoter payout stays COMPLETELY out of scope and DARK.)

------------------------------------------------------------
FINAL STATUS
------------------------------------------------------------

REVOKE UN-PARK COMPLETE:                 YES (106; owner-directed PFA-18B, signature pending)
PIN UN-PARK COMPLETE:                    YES (107; owner-directed PFA-26-UNPARK, signature pending)
MACHINE DOOR AUTH COMPLETE:              YES (108; door session decides scope; poison-pill fixed)
CANCEL FORCE-CLOSE COMPLETE:             YES (109; trigger; zero money bytes)
PFA-18B ENGINEERING COMPLETE:            YES
PFA-26 ENGINEERING COMPLETE:             YES
PFA-PT-9 ENGINEERING COMPLETE:           YES (item 2 landed; items 1/3 owner-approved; 4/5 accepted/runbook)
KMS PROVIDER DECIDED:                    YES — AWS KMS
KMS ALGORITHM DECIDED:                   YES — ES256
P0 OPEN:                                 NO
P1 OPEN:                                 NO (two found + fixed this train)
BACKEND ENGINEERING BLOCKER TO CONTROLLED SALE:  NO
BACKEND ENGINEERING BLOCKER TO CONTROLLED SCAN:  NO
BACKEND CONSTRUCTION COMPLETE:           YES — every door-plane + signing MECHANISM is built and tested;
                                         provision/rotate stay parked by owner ruling (not missing code);
                                         no large architecture remains.
ENGINEERING READY FOR PRODUCTION PREFLIGHT:  YES
ENGINEERING READY FOR KMS CEREMONY:      YES (D1/D2 decided; owner signatures are the gate)
KMS CEREMONY SHOULD RUN NOW:             NO
ENGINEERING READY FOR DARK PRODUCTION MIGRATION: YES (the code; owner/PFA gates precede applying it)
PRIMARY SALE ACTIVATION AUTHORIZED:      NO
VENUE PAYOUT ACTIVATION AUTHORIZED:      NO
PROMOTER PAYOUT ACTIVATION AUTHORIZED:   NO

RECOMMENDED NEXT CLAUDE A ACTION:  Present the owner-signature package as ONE gate — PFA-18B,
PFA-26-UNPARK, PFA-PT-9 (items 1&3), PFA-PT-6, PFA-PT-8 (D1/D2 already decided) — since every remaining
door-plane and signing item is now an owner signature over already-built, already-tested code. On
signature, no further build is required before the production preflight: migrate 093→109, run the KMS
ceremony (AWS KMS / ES256), deploy the DARK edges, and proceed to a single controlled first sale + scan.

============================================================

STOP. DO NOT DEPLOY. DO NOT APPLY MIGRATIONS. DO NOT RUN KMS. DO NOT CONFIGURE PRODUCTION. DO NOT MOVE
MONEY. DO NOT ACTIVATE.

============================================================

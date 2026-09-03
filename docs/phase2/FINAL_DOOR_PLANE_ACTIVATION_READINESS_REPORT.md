============================================================
SNATCH IT — FINAL DOOR PLANE ACTIVATION READINESS
============================================================

Package 105 + door edges · 2026-09-03 · DARK / UNAPPLIED / UNDEPLOYED

> **THIS IS NOT PRODUCTION AUTHORIZATION.** No migration applied to production; no edge deployed; no
> schema exposed; no config/flag changed; no KMS key created; no ceremony run; no signing_key inserted;
> no KMS Sign called; no Connect/PaymentIntent/money/ticket/credential/scan in production; nothing
> activated; no secret rotated. Production inspection was READ-ONLY. Tax stays fail-closed (PFA-PT-7
> unchanged). deletion.post_event_hold_hours stays owner-unset.

REPOSITORY

BRANCH:      feature/venue-native-and-product-v2
ENTRY HEAD:  9cd95d6 (packages 102-104) — pushed, CI green
FINAL HEAD:  <this train's commit> — pushed if permission allows (else the exact command is under FINAL STATUS)
REMOTE:      origin = SnatchIt-app/snatchit; origin branch = 9cd95d6 at entry
PR:          #52 — OPEN, MERGEABLE
CI:          GREEN on 9cd95d6 (CI + Migrations guard SUCCESS; Supabase Preview SKIPPED — autodeploy off)
WORKTREE:    package 105 + two DARK edges authored; migrations 093-104 byte-untouched (git diff empty)

PRODUCTION  (READ-ONLY, via Supabase MCP)

LEDGER:        107 rows — through 092 (076-092 LIVE-but-DARK; 093-105 unapplied)
SIGNING KEYS:  0
NATIVE EDGES:  NOT DEPLOYED — no credential-sign, primary-checkout, refund/payout-execute, door-session,
               or door-manifest edge in production (11 legacy resale edges only)
MUTATIONS:     NONE

------------------------------------------------------------
ENTRY
------------------------------------------------------------

MIGRATION TIP:  104 (entry) → 105 (this train)
P0:             0 open at entry
P1:             §5.6 signing-key revocation force-close (parked); PFA-26 door-PIN KDF (parked)
P2:             reconcile_offline_scans ordering/outcome drift; record_scan service_role auth path

------------------------------------------------------------
REVOCATION FORCE-CLOSE
------------------------------------------------------------

IMPLEMENTED:      MECHANISM YES (kernel.force_close_key_manifests, migration 105, tested — test 171
                  F1-F7). Wiring into kernel.revoke_signing_key: NO — blocked by PFA-18A (see PFA-18A
                  section); recommended un-park is PFA-18B (owner-gated).
KEY STATE:        revoke_signing_key STAYS PARKED (raises dual_control_unavailable). The mechanism helper
                  does NOT touch the key row — that is revoke's job, gated on PFA-18B.
NOT_AFTER:        the immutability guard forbids re-writing not_after after open; the reconnect-refuse
                  signal is status='closed' → get_door_manifest returns no_open_episode (equivalent for a
                  reconnecting device; the never-reconnects residual is bounded by
                  door.manifest_ttl_interval, ~12h, and no DB write can shorten a value already on a
                  disconnected device). Honest, not hidden.
EPISODES:         every OPEN door_manifest episode in the key's scope is closed.
MANIFESTS:        status→closed + close_reason='key_revoked'.
INVALIDATION FACT: notify.emit_event_required('DoorManifestInvalidated', #44, REQ/raising) per episode +
                  a DoorManifestClosed parity event + kernel.admin_audit — a DURABLE outbox fact, not a
                  push. Authoritative state (status='closed') is queryable after any missed notification.
ATOMICITY:        one transaction; catalog.event_session locked FOR UPDATE (rank 1) before the key row.
                  A concurrent open_door_manifest blocks on the same session lock (verified: both take it).
                  Residual (forward-looking, inert while revoke is parked): open_door_manifest does not
                  inspect key state, so nothing stops a NEW episode opening for that session AFTER the
                  (future) revoke commits — a design item for the PFA-18B un-park, noted below.
SCOPE:            global → every open episode; per_venue(V) → V's; per_event(E) → E's. Proven scope-exact
                  and out-of-scope-isolated (test 171 F6/F7, T-RPC-KEY-05). Matches signing_key's
                  scope_target_ck; event.venue_id is immutable, event un-deletable while a session exists.
RACES:            serialized on the event_session lock; DoorManifestInvalidated dedup key is
                  manifest_id-scoped (no cross-call collision); a duplicate revoke finds status='closed'
                  and no-ops. Idempotent on no episodes (returns 0, no writes).

------------------------------------------------------------
TERMINAL SESSION
------------------------------------------------------------

ONLINE:      CLOSED (migration 104 — record_scan refuses a cancelled/completed session).
OFFLINE:     an M2 downloaded BEFORE the cancel keeps admitting until its downloaded not_after — the
             same bounded residual as revocation.
FORCE-CLOSE: MECHANISM EXISTS (force_close_key_manifests is scope-keyed; a session-scoped sibling for
             cancel_event is a one-liner). Finding: cancel_event's OWN §7.2.1 manifest force-close is
             ALSO unimplemented in 088 (it sets status='cancelled' but never closes the manifest / emits
             #44). Wiring it is PFA-PT-9 item 2 — a follow-up door migration (re-creating the large 088
             cancel_event money function is done under money non-regression, not bundled with signing).
RESIDUAL:    bounded by door.manifest_ttl_interval; accepted (PFA-PT-9 item 4).
PFA:         PFA-PT-9 (items 1/2/4) — recommendation supplied.

------------------------------------------------------------
PFA-18A
------------------------------------------------------------

STATUS:        NOT closed by this train. It is a STANDING owner-signed ruling that the credential
               lifecycle trio (provision/rotate/revoke) performs ZERO mutation until a
               credential-compatible dual-control mechanism is SEPARATELY RATIFIED, and it explicitly
               denies single-control fallback.
REQUIREMENTS:  (a) the dual-control mechanism (unassigned owner-decision — kernel.approval_request is
               money-only); (b) the §5.6 force-close body.
IMPLEMENTED:   (b) is BUILT + TESTED (force_close_key_manifests). (a) is NOT built — it is an owner
               decision this session must not make unilaterally, and PFA-18A pre-emptively forbids the
               single-control fallback that would let engineering route around it.
OPEN:          the revoke un-park. RECOMMENDED resolution: PFA-18B (below) — un-park REVOKE under single
               platform_admin control on the kill-switch-polarity argument (revocation is an emergency
               tightening; WALLET §11.5b / package-102 P3 precedent), provision/rotate stay parked.
               This is the honest classification: the remaining blocker is OWNER/GOVERNANCE, not missing
               engineering.

------------------------------------------------------------
PFA-26 / DOOR PIN
------------------------------------------------------------

STATUS:          RECOMMENDED — PENDING OWNER SIGNATURE (PFA-26-UNPARK). The park itself remains correct;
                 the KDF mechanism was genuinely owner-open.
KDF:             recommended in-DB pgcrypto bcrypt — `crypt(pin, gen_salt('bf',12))` store, crypt-based
                 constant-time verify. Keeps the FROZEN create_door_pin/mint_door_session signatures
                 (PIN arrives at the DB, hashed there). Argon2id (edge/WASM) is cryptographically
                 preferred but needs a signature change — noted, not chosen.
PARAMETERS:      bf cost 12 (owner may set 10-14) — the one tunable value.
SALT:            per-hash, embedded in the bcrypt modular-crypt output stored in pin_hash — NO new column.
VERSION:         the '$2a$12$…' tag carries algorithm+cost; future rotation needs no schema change.
RATE LIMIT:      the door-session edge's NS_DOOR_PIN limiter (venue||device, 5/60, fail-closed) IS the
                 brute-force control for the low-entropy PIN — no in-DB lockout table (none exists).
ROTATION:        revoke_door_pin (live) + create a new PIN; no in-place change.
RUNTIME:         pgcrypto is a Supabase-sanctioned extension; deploy-safe, no new dependency.
OWNER SIGNATURE: REQUIRED (PFA-26 froze this as owner-signed). Engineering did NOT write the un-park
                 migration (it un-parks a parked security boundary — signature first). The door-session
                 edge is authored DARK and surfaces the parked RPC cleanly (503/pin_unavailable).

------------------------------------------------------------
DOOR SESSION EDGE
------------------------------------------------------------

IMPLEMENTED:   YES (DARK) — supabase/functions/door-session/{index.ts,pure.ts}. 63 pure-logic tests
               (NIST SHA-256 + RFC4122 UUIDv5 vectors verify the hand-rolled crypto).
AUTH:          Class B-iii — `Authorization: DoorSession <door_session_id>.<secret>`; the ONLY gate is
               kernel.assert_door_session; every relay call re-derives the device from its RETURN, never
               a body field; a body device_id / scan_meta.device_id is rejected; auth failure is opaque
               (unknown-id and wrong-token indistinguishable).
SCOPE:         the caller chooses nothing — org/venue/event/session/device authority is all server-derived
               via assert_door_session's bound (device_id, event_session_id) return.
TOKEN/SESSION: DB-backed door_session_id + 256-bit secret returned once; token_hash = sha256(id||':'||secret).
TTL:           LEAST(now()+door.session_ttl_interval, pin.expires_at, session_end+post_session_grace),
               computed in mint_door_session (server-side).
REVOCATION:    revoke_door_session (live). The client never receives service_role/db/KMS creds or the PIN.
CROSS-VENUE:   impossible — assert_door_session binds the device↔session; a token for one session/device
               cannot drive another. Whole flow is INERT until PFA-26 un-parks /mint (surfaces cleanly).

------------------------------------------------------------
DOOR MANIFEST EDGE
------------------------------------------------------------

IMPLEMENTED:   YES (DARK, OPTIONAL) — supabase/functions/door-manifest/index.ts.
AUTH:          Class A, single route, staff JWT (venue_scanner/venue_manager via has_venue_role in
               get_door_manifest).
CONTENTS:      KMS-signs `{manifest_id, manifest_version, session_id, not_after, manifest_digest}`
               (deterministic over the digest). Passes through only what get_door_manifest returns.
PII:           NONE — get_door_manifest carries signing_key_id but NEVER public_key/identity (PFA-24);
               the edge adds no buyer/price/payout/Stripe fields.
FRESHNESS:     the manifest's own not_after; a device with no M2 / an M2 past not_after / an M2 for
               another session has NO offline authority (enforced in the offline-verify core).
INVALIDATION:  a reconnecting device gets no_open_episode from /manifest/sync and drops its M2.
DELTA:         base ⊕ ordered deltas (applied set); ordering is deterministic per the frozen model.
TRUST ROOT:    reuses the credential-sign KMS adapter; DARK (UnconfiguredKmsSigner → kms_unconfigured);
               TLS-only unsigned fallback is MVP-acceptable per §3.9b.

------------------------------------------------------------
RECONCILIATION
------------------------------------------------------------

ORDERING:    deterministic — (server_receipt_at [edge-stamped per §9.5], device_boot_id, scan_sequence),
             NULLS LAST, atom tiebreak. The real first-in-wins is the DB commit order enforced by
             record_scan's scan_admitted_in_uq — a client's batch order cannot steal a genuine earlier
             admit from another call.
OUTCOMES:    {status, admitted, duplicates, conflicts} (RPC §9.5) — was {status, reconciled}.
IDEMPOTENCY: the scan partial-unique makes a repeated admit a duplicate/invalid, not a second admission.
DOUBLE-SCAN: ONLINE: none. OFFLINE across two devices: an inherent physical residual (each admits
             locally); the ledger persists exactly ONE admitted row; the second becomes a conflict on
             reconcile. Not pretended away.
CONFLICTS:   per-item isolated (adversarial P1 fix): a malformed atom OR a wrong-session item is counted
             as a conflict and the loop continues — one bad row never poisons the whole batch (test 171
             R2). A wrong-session item is rejected (never attributed to the asserted session).

------------------------------------------------------------
CREDENTIAL VERSION BACKSTOP
------------------------------------------------------------

CURRENT DESIGN:      record_scan takes NO credential_version; currency lives at C37 / the verifier
                     (frozen §7.5/§1223).
ADVERSARIAL FINDING: a rogue-STAFF scanner bypassing C37 could admit a stale screenshot — a
                     trusted-insider threat (venue staff control the physical door regardless), not a
                     credential defect. The old-owner-screenshot defense is proven at the verifier
                     (offline-verify stale_version; C37 live read).
DB BACKSTOP ADDED:   NO.
WHY:                 adding a version param would DEVIATE from the frozen signature and complicate
                     reconciliation for no gain against the real threat. Independent review concurred.
PFA-PT-9:            item 3 — RECOMMENDED keep frozen (no backstop). Owner approval text supplied.

------------------------------------------------------------
OFFLINE SECURITY
------------------------------------------------------------

KEY REVOKE:          reconnecting device → no_open_episode (drops M2). Offline-never-reconnect → bounded
                     by downloaded not_after (≤ door.manifest_ttl_interval). Mechanism built (105);
                     revoke un-park gated on PFA-18B.
SESSION CANCEL:      online closed (104); offline bounded (same not_after residual); force-close wiring is
                     PFA-PT-9 item 2 follow-up.
TRANSFER:            break-glass admin_action transfer during an open episode leaves the M2 stale until
                     not_after (§5.5 residual) — runbook must force-close/refresh (PFA-PT-9 item 5).
DOUBLE DEVICE:       inherent; reconciled to one authoritative admit; the second is a conflict.
NO-NETWORK RESIDUAL: a fully-disconnected scanner cannot be reached by ANY server action; honestly
                     disclosed, not claimed away.
BOUNDED HOW:         door.manifest_ttl_interval (~12h) + credential_version currency (M2 conjunct 3b.iii)
                     + short token TTL + the door freeze.

------------------------------------------------------------
PFA-PT-9
------------------------------------------------------------

STATUS:  RESOLVED to a precise recommendation (owner approval text in POST_FREEZE_AMENDMENTS.md).
ITEM 1:  RATIFY migration 104's terminal-session record_scan gate as the reading of §7.5 admit-gate (1).
ITEM 2:  YES — wire cancel_event (and any completed sweep) to the force-close mechanism; deferred to a
         dedicated door migration (mechanism now exists).
ITEM 3:  NO DB credential_version backstop in record_scan (currency stays at C37/verifier).
ITEM 4:  the offline terminal-session not_after residual is ACCEPTED as bounded.
ITEM 5:  break-glass admin transfer during an open episode → runbook force-close/refresh step.
OWNER APPROVAL TEXT: supplied for items 1 & 3 (the ones needing a ruling); 2/4/5 are tracked follow-ups /
         accepted residuals.

------------------------------------------------------------
CRYPTO NON-REGRESSION
------------------------------------------------------------

PFA-PT-6:  wire format unchanged; PENDING OWNER SIGNATURE (adversarially confirmed prior train).
PFA-PT-8:  algorithm pin unchanged (migration 103); PENDING OWNER SIGNATURE.
KMS:       AwsKmsSigner / ES256 DER↔raw / sign-after-verify / fail-closed — unchanged; vitest 672/672.
M1:        verifyToken (typ/kid/alg-pin/signature/exp) — unchanged, green.
M2:        offline-verify OFFLINE-VERIFY-v1 core — unchanged, green.
ROTATION:  unchanged (test 169 C).
OLD OWNER: unchanged (verifier stale_version + version bump).

------------------------------------------------------------
MONEY NON-REGRESSION
------------------------------------------------------------

G4:        PASS (test 166 — venue obligation 9000, excludes held commission).
G5:        PASS (test 167 — cross-venue recovery refusal).
CROSS-VENUE: refused.
REFUND:    engineering-ready, DARK, undeployed — untouched.
PAYOUT:    engineering-ready, DARK, undeployed — untouched.
PROMOTER:  DARK, out of scope.
(105 touches ONLY door-manifest + reconcile; no economic fact changed. G4/G5 tests pass in the suite.)

------------------------------------------------------------
MIGRATIONS
------------------------------------------------------------

PREVIOUS TIP:          104
NEW TIP:               105
FILES:                 105_door_manifest_forceclose_and_reconcile.sql (+ rollback)
HASHES:                105 = fadca67fb4c06cfad3707234b90b3bba
CENSUS:                kernel functions 147 → 148 (+1 force_close_key_manifests, zero-grant so the F2
                       authenticated-EXECUTE set is UNCHANGED at 67); five-schema routines 281 → 282;
                       market/kernel/catalog string 22/147/16 → 22/148/16. Gate-2 public census
                       unchanged (27/70/37/26). Bumped in 141/142/143/144/148/154/156/157.
EXISTING ROW MUTATION: NONE.

------------------------------------------------------------
SECURITY
------------------------------------------------------------

P0:   0 OPEN.
P1:   0 code-level OPEN this train (the reconcile poison-pill P1 was FOUND + FIXED). The remaining
      "P1" items from the prior train (§5.6 revocation, PFA-26 PIN) are now MECHANISM-COMPLETE and
      reduced to OWNER/GOVERNANCE signature gates (PFA-18B, PFA-26-UNPARK), not missing engineering.
P2:   record_scan/reconcile service_role door-session auth path (deferred, no live consumer, documented);
      reconcile ordering trusts an edge-stamped server_receipt_at (documented contract); open_door_manifest
      does not re-check key state post-revoke (inert while revoke parked — a PFA-18B un-park design item).

PRIVILEGE ESCALATION: none — force_close_key_manifests is zero-grant (revoked from public/anon/
                      authenticated/service_role), SECURITY DEFINER + search_path='' fully qualified.
PIN LEAK:             none — PIN never stored plaintext/logged; door-session edge never logs the PIN,
                      secret, token, or PII; recommended verifier is bcrypt (PFA-26-UNPARK).
CROSS-VENUE:          none — assert_door_session binds device↔session; force-close is scope-exact.
STALE MANIFEST:       reconnect → no_open_episode; offline bounded by not_after (honest residual).
DOUBLE SCAN:          online prevented (unique index); offline bounded + reconciled to one admit.
REVOKED KEY:          mechanism closes in-scope episodes + emits #44 (once revoke un-parks, PFA-18B).

------------------------------------------------------------
ADVERSARIAL REVIEW
------------------------------------------------------------

CLAIMS OVERTURNED: "the per-item session cross-check isolates bad rows" — it did NOT (the raise sat
                   outside the per-item block, poisoning the whole batch). Now true + tested (171 R2).
DEFECTS FOUND:     1 P1 (reconcile poison-pill) + 3 P2 (server_receipt_at trust, reopen-post-revoke,
                   service_role auth path) + test-coverage gaps.
DEFECTS FIXED:     the P1 (per-item isolation) + the two P2 comment/contract clarifications + the R2 test.
OPEN:              reopen-post-revoke (inert, PFA-18B design item); service_role auth path (deferred,
                   dark); global/per_venue scope + idempotency test coverage (per_event proven; symmetric
                   code) — documented, low-risk.

------------------------------------------------------------
TESTING
------------------------------------------------------------

FRESH DB:      PASS — replay 000→105, Gate-2 27/70/37/26 (== CI baseline).
PGTAP:         PASS — TOTAL plan=3647 ok=3643 not_ok=4; RESULT "matches the expected local baseline"
               (the 4 are the documented local-only deltas: 060 ×2, 132 ×2). 171 PASS (9).
VITEST:        PASS — 15 files, 672 tests (door-session 63 + prior 609).
TYPECHECK:     PASS — exit 0.
LINT:          PASS — 0 errors (45 baseline warnings).
WEB:           shared TS contract compiles (typecheck covers test-imported modules); no web contract changed.
MOBILE:        no mobile-facing contract changed; handoff (§2e) updated.
ASSEMBLER:     PASS — G-4 (093 byte-identical).
GATE-2:        27/70/37/26 (unchanged).
REVOCATION:    171 F1-F7 (scope-exact close, #44 emit, no_open_episode, T-RPC-KEY-05 isolation).
KDF:           NOT run (PFA-26 un-park pending owner signature; mechanism recommended, not built).
RATE LIMIT:    door-session pure tests (namespace/key derivation) green.
DOOR SESSION:  63 pure tests (bearer parse, token_hash, device cross-check, dispatch) green.
MANIFEST:      offline-verify core (prior) green; door-manifest edge DARK.
OFFLINE:       offline-verify OFFLINE-VERIFY-v1 (prior) green.
RECONCILE:     171 R1/R2 (shape, first-in-wins, per-item isolation).
M1/M2:         prior packages, green.
KMS:           adapter tests green (unchanged).
ROTATION:      169 C green.
MONEY:         166/167 green.
CI:            GREEN on entry 9cd95d6; the new commit's CI runs on push.

------------------------------------------------------------
ACTIVATION MATRIX  (see PRIMARY_TICKETING_ACTIVATION_MATRIX.md — package-105 re-derivation)
------------------------------------------------------------

EVENT DRAFT:            code ✓ · migrated ✓(dark) · NOT ACTIVATED
EVENT PUBLISH:          code ✓ · ratified ✓ · NOT migrated (102-105) · NOT ACTIVATED
PRIMARY SALE:           code ✓ · NOT migrated · edge NOT deployed · NOT ACTIVATED
PAYMENT CONFIRMATION:   code ✓ · NOT migrated · edge NOT deployed · NOT ACTIVATED
TICKET ISSUANCE:        code ✓ · migrated ✓(dark) · KMS not configured (0 keys) · NOT ACTIVATED
CREDENTIAL SIGN:        code ✓ · PFA-PT-6/8 PENDING · NOT migrated · edge NOT deployed · NOT ACTIVATED
DOOR SESSION:           code ✓(DARK) · PFA-26 PENDING (PIN) + service_role auth path · NOT ACTIVATED
DOOR MANIFEST:          code ✓(DARK, optional) · KMS ceremony (or TLS MVP) · NOT ACTIVATED
DOOR VERIFY:            M1/M2 cores ✓ · door RPCs migrated ✓(dark) · NOT ACTIVATED
SCAN:                   code ✓(104 gate) · NOT migrated (104-105) · NOT ACTIVATED
OFFLINE RECONCILIATION: code ✓(105) · service_role auth path · NOT ACTIVATED
REFUND:                 code ✓ · migrated ✓(dark) · edge NOT deployed · NOT ACTIVATED
SETTLEMENT:             code ✓ · migrated ✓(dark) · NOT ACTIVATED
VENUE PAYOUT:           code ✓ · migrated ✓(dark) · edge NOT deployed · NOT ACTIVATED
PROMOTER PAYOUT:        DARK / out of scope · NOT ACTIVATED

------------------------------------------------------------
REMAINING BLOCKERS BY CLASS
------------------------------------------------------------

ENGINEERING:        SMALL and well-scoped, all gated on an owner signature FIRST: (1) the revoke un-park
                    migration (wire force_close_key_manifests into revoke_signing_key + single-admin
                    authz) — trivial once PFA-18B is signed; (2) the PFA-26 un-park migration (create
                    extension pgcrypto + re-create create_door_pin/mint_door_session with bcrypt) — once
                    PFA-26-UNPARK is signed; (3) the record_scan/reconcile service_role door-session auth
                    path — needed before the door-session edge functions; (4) wire cancel_event to the
                    force-close mechanism (PFA-PT-9 item 2). No LARGE missing architecture remains — every
                    door-plane MECHANISM is built and tested.
OWNER/GOVERNANCE:   PFA-18B (revoke un-park authz), PFA-26-UNPARK (KDF algorithm+cost), PFA-PT-9 items 1&3,
                    PFA-PT-6 (wire format), PFA-PT-8 (alg pin), KMS provider/algorithm (D1/D2).
LEGAL/TAX:          PFA-PT-7 (tax enforcement locus) — unchanged, OPEN.
PRODUCTION OPERATION: migrate 093-105; deploy the DARK edges; the KMS ceremony; config; org onboarding;
                    schema exposure. deletion.post_event_hold_hours owner-set.
OBSERVATION:        the production-observation closeout ARTIFACT (not merely elapsed time) before migrate.
OPTIONAL HARDENING: Argon2id-in-edge PIN KDF (vs bcrypt); the reopen-post-revoke key-state check in
                    open_door_manifest; global/per_venue scope + idempotency test coverage.

------------------------------------------------------------
FIRST SAFE SALE + SCAN  (exact remaining steps — DO NOT EXECUTE)
------------------------------------------------------------

1.  Owner signs: PFA-PT-6, PFA-PT-8, PFA-18B, PFA-26-UNPARK, PFA-PT-9 (items 1&3).
2.  Owner/counsel resolve TAX (PFA-PT-7) or affirm compute-none.
3.  Owner sets deletion.post_event_hold_hours; owner selects KMS provider+algorithm (D1/D2).
4.  Engineering (post-signature, small): write the revoke un-park migration (106), the PFA-26 un-park
    migration (107), the record_scan/reconcile service_role auth-path migration, and the cancel_event
    force-close wiring; re-run the full test floor + CI.
5.  Production-observation closeout artifact confirmed (ledger 107, 0 keys, native edges undeployed).
6.  Apply migrations 093→(latest) to production (forward-only; hashes pinned; AUTODEPLOY-VERIFIED-OFF).
7.  KMS ceremony (two-person): create the asymmetric key, insert ONE kernel.signing_key row (public_key
    SPKI, kms_handle_ref version-pinned, algorithm matching the key) — a global bootstrap key.
8.  Verify the trusted key (fingerprint dual-controlled; monitor status=ok); arm signing.monitor_enabled.
9.  Deploy the DARK edges (credential-sign, primary-checkout, door-session, door-manifest) with KMS +
    provider env; provision the door PIN(s) (now un-parked).
10. Onboard a real org (Connect bound + transfers active; set fee.buyer_service_bps); expose the RPC
    surface to PostgREST.
11. Publish an event to on_sale (A8a′'s four gates satisfiable).
12. First quote → PaymentIntent → issue_ticket_atoms (THE irreversible point, G3) → credential-sign
    (M1) → door M1 verify → C37/M2 check → controlled door scan → offline reconcile.
13. Prove a refund end-to-end before widening.

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

REVOCATION FORCE-CLOSE COMPLETE:                 MECHANISM YES; revoke un-park PENDING PFA-18B (owner)
PFA-18A ENGINEERING COMPLETE:                    the force-close body YES; the dual-control mechanism is
                                                 an OWNER decision (PFA-18B recommends single-admin revoke)
PFA-26 ENGINEERING COMPLETE:                     mechanism RECOMMENDED + edge authored; un-park migration
                                                 PENDING PFA-26-UNPARK (owner)
DOOR SESSION EDGE COMPLETE:                      YES (DARK)
DOOR MANIFEST EDGE COMPLETE:                     YES (DARK, optional)
OFFLINE INVALIDATION COMPLETE:                   MECHANISM YES (reconnect refuse + #44); wiring into
                                                 revoke/cancel is owner/follow-up gated
RECONCILIATION COMPLETE:                         YES (ordering + outcomes + per-item isolation)
M1 COMPLETE:                                     YES
M2 COMPLETE:                                     YES
KMS ADAPTER COMPLETE:                            YES (DARK)
P0 OPEN:                                         NO
P1 OPEN:                                         NO code-level P1 (revocation/PIN are now owner-signature
                                                 gates, not missing engineering)
BACKEND ENGINEERING BLOCKER TO CONTROLLED PRIMARY SALE:  NO for the signing/credential chain (built);
                                                 the door-SCAN un-parks are small and owner-signature-first
BACKEND ENGINEERING BLOCKER TO CONTROLLED DOOR SCAN:     the un-park migrations (revoke, PIN) + the
                                                 service_role auth path — SMALL, each gated on an owner
                                                 signature; no large architecture missing
BACKEND CONSTRUCTION PHASE COMPLETE:             YES for all MECHANISMS; the remaining code is small
                                                 owner-signature-gated un-parks, not new architecture
ENGINEERING READY FOR OWNER GATE PHASE:          YES
ENGINEERING READY FOR KMS CEREMONY:              YES (preflight met; owner signatures + provider decision
                                                 are the gate)
KMS CEREMONY SHOULD RUN NOW:                     NO
ENGINEERING READY FOR DARK PRODUCTION MIGRATION: YES (the code; owner/PFA gates precede applying it)
PRIMARY SALE ACTIVATION AUTHORIZED:              NO
VENUE PAYOUT ACTIVATION AUTHORIZED:              NO
PROMOTER PAYOUT ACTIVATION AUTHORIZED:           NO

RECOMMENDED NEXT CLAUDE A ACTION:  Present the owner-decision package as ONE gate — PFA-18B (single-admin
revoke un-park), PFA-26-UNPARK (bcrypt PIN KDF), PFA-PT-9 items 1&3, PFA-PT-6, PFA-PT-8, and the KMS
provider/algorithm (D1/D2) — since every remaining door-plane and signing item is now an owner signature
plus a SMALL, pre-scoped un-park migration, not missing engineering. On signature, land the four small
un-park/conformance migrations (revoke, PIN, service_role auth path, cancel_event force-close) and
re-run the floor; the backend is then construction-complete for a controlled first sale and scan.

============================================================

STOP. DO NOT DEPLOY. DO NOT APPLY MIGRATIONS. DO NOT RUN KMS. DO NOT CONFIGURE PRODUCTION. DO NOT MOVE
MONEY. DO NOT ACTIVATE.

============================================================

-- ============================================================================
-- 253_scan_sequential_duplicate.sql — migration 20261026210000 (registry 183).
--   S05 "already used": a SEQUENTIAL rescan of a consumed atom records
--   result='duplicate' and returns the prior admission facts
--   {prior:{scan_id, occurred_at, device_id, actor_identity_id, device_label}}; every other refusal stays
--   'invalid' exactly as 108; the first-in-wins ledger invariant (086 C41,
--   scan_admitted_in_uq) holds on both the door machine path and the staff path;
--   S07 (timeout after commit → retry with the same command_key) answers
--   duplicate + prior, never a second admitted row. Also: credential currency
--   (scan_meta.credential_version / key_id vs kernel.tickets) when supplied,
--   an unknown atom answers invalid/unknown_atom instead of raising, every
--   invalid carries a reason, and scan_meta.device_label is captured + echoed.
--   NEGATIVE CONTROL: on a chain WITHOUT 183 (the 108 body) S2/S3/S4/S6/S8/S12/
--   S16-S17 fail (the repeat is 'invalid' and carries no `prior`). Recorded in
--   planning/2026-10-26-launch/B/evidence (RED run) and re-proved by the
--   block-removed mutant after GREEN.
--   The two-connection race (one admitted + one duplicate at a real lock
--   barrier) cannot run inside one pgTAP connection; it is proved by
--   planning/2026-10-26-launch/B/evidence/scan_race.sh on the same chain.
-- ============================================================================
BEGIN;
SELECT plan(30);
SELECT tap.seed_core();

CREATE TABLE tap.memo_253 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store253(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_253 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fetch253(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_253 WHERE k=$1 $m$;

-- ── FIXTURE — venue(approved), event A (6 comp atoms) + event B (1 atom),
-- device, PIN, minted door session on A, native scanning ON. (174 shape.) ────
SELECT tap.login(tap.seller());
SELECT tap._store253('org', (kernel.create_organization('SD Co','SD Co','ck253-o') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch253('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store253('venue', (catalog.create_venue(tap._fetch253('org')::uuid,'SD Hall','wynwood',NULL,'ck253-v') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch253('venue')::uuid,'approved','miami_gate','ck253-a');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_issuance_enabled', 2, 'true'::jsonb, 'public');
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_scanning_enabled', 2, 'true'::jsonb, 'public');
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by)
VALUES (tap._fetch253('venue')::uuid, tap.seller(), 'venue_manager', tap.admin_user()) ON CONFLICT DO NOTHING;

SELECT tap.login(tap.seller());
SELECT tap._store253('eA', (catalog.create_event(tap._fetch253('venue')::uuid,'SD A',
  jsonb_build_object('starts_at',(now()+interval '9 days')::text,'ends_at',(now()+interval '9 days 5 hours')::text),'ck253-eA') ->> 'event_id'));
SELECT tap._store253('sA', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch253('eA')::uuid));
SELECT tap._store253('ttA', (venue.create_ticket_type(tap._fetch253('eA')::uuid,'admission','GA',5000,'public','ck253-ttA') ->> 'ticket_type_id'));
SELECT tap._store253('bA', (venue.create_inventory_batch(tap._fetch253('ttA')::uuid, tap._fetch253('sA')::uuid, 'comp', 100, 0, 'ck253-bA') ->> 'batch_id'));
SELECT tap._store253('eB', (catalog.create_event(tap._fetch253('venue')::uuid,'SD B',
  jsonb_build_object('starts_at',(now()+interval '9 days')::text,'ends_at',(now()+interval '9 days 5 hours')::text),'ck253-eB') ->> 'event_id'));
SELECT tap._store253('sB', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch253('eB')::uuid));
SELECT tap._store253('ttB', (venue.create_ticket_type(tap._fetch253('eB')::uuid,'admission','GA',5000,'public','ck253-ttB') ->> 'ticket_type_id'));
SELECT tap._store253('bB', (venue.create_inventory_batch(tap._fetch253('ttB')::uuid, tap._fetch253('sB')::uuid, 'comp', 100, 0, 'ck253-bB') ->> 'batch_id'));
SELECT tap._store253('dev', (venue.register_scan_device(tap._fetch253('venue')::uuid, 'scanner-253', 'ck253-dev') ->> 'device_id'));
SELECT tap._store253('pin', (venue.create_door_pin(tap._fetch253('venue')::uuid, tap._fetch253('sA')::uuid, 'front', 'pin-253', (now()+interval '1 day'), 'ck253-pin') ->> 'pin_id'));
SELECT tap.logout();
WITH kA AS (INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_event', tap._fetch253('eA')::uuid, 'PUBKEY-253A', 'kms-253A', 'active', now(), 'ES256') RETURNING key_id)
SELECT tap._store253('kA', (SELECT key_id::text FROM kA));
WITH kB AS (INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_event', tap._fetch253('eB')::uuid, 'PUBKEY-253B', 'kms-253B', 'active', now(), 'ES256') RETURNING key_id)
SELECT tap._store253('kB', (SELECT key_id::text FROM kB));
SELECT tap._store253('mA', (kernel.issue_ticket_atoms(jsonb_build_object(
  'session_id',tap._fetch253('sA')::uuid,'org_id',tap._fetch253('org')::uuid,'ticket_type_id',tap._fetch253('ttA')::uuid,
  'batch_id',tap._fetch253('bA')::uuid,'owner_id',tap.buyer(),'quantity',6,'cause','comp',
  'cause_ref',gen_random_uuid(),'signing_key_id',tap._fetch253('kA')::uuid),'ck253-mA') -> 'atom_ids')::text);
SELECT tap._store253('mB', (kernel.issue_ticket_atoms(jsonb_build_object(
  'session_id',tap._fetch253('sB')::uuid,'org_id',tap._fetch253('org')::uuid,'ticket_type_id',tap._fetch253('ttB')::uuid,
  'batch_id',tap._fetch253('bB')::uuid,'owner_id',tap.buyer(),'quantity',1,'cause','comp',
  'cause_ref',gen_random_uuid(),'signing_key_id',tap._fetch253('kB')::uuid),'ck253-mB') -> 'atom_ids')::text);
SELECT tap.login_service();
SELECT tap._store253('mint', (venue.mint_door_session(tap._fetch253('venue')::uuid, tap._fetch253('sA')::uuid, tap._fetch253('dev')::uuid, 'pin-253', 'ck253-mint')::text));
SELECT tap._store253('dsid', (tap._fetch253('mint')::jsonb ->> 'door_session_id'));
SELECT tap._store253('secret', (tap._fetch253('mint')::jsonb ->> 'secret'));
SELECT tap.logout();

-- helper: one machine scan of atom i of event A, under service_role, stores the response
CREATE FUNCTION tap._scan253(i int, key text) RETURNS jsonb
LANGUAGE plpgsql AS $f$   -- INVOKER on purpose: set_config('role') is refused inside a SECURITY DEFINER function
DECLARE r jsonb;
BEGIN
  PERFORM tap.login_service();
  r := venue.record_scan_door((tap._fetch253('mA')::jsonb->>i)::uuid, tap._fetch253('sA')::uuid,
         tap._fetch253('dsid')::uuid, tap._fetch253('secret'), tap._fetch253('dev')::uuid, '{}'::jsonb, key);
  PERFORM tap.logout();
  RETURN r;
END $f$;

-- ── S1 — first machine scan of mA[0] admits ─────────────────────────────────
SELECT tap._store253('r1', tap._scan253(0, 'ck253-scan0')::text);
SELECT is(tap._fetch253('r1')::jsonb ->> 'result', 'admitted', 'S1: the first scan of a fresh atom is admitted (door machine path)');

-- ── S2–S4 — a SEQUENTIAL rescan (new command_key) is duplicate + prior ──────
SELECT tap._store253('r2', tap._scan253(0, 'ck253-scan0-again')::text);
SELECT is(tap._fetch253('r2')::jsonb ->> 'result', 'duplicate',
  'S2: a sequential rescan of the consumed atom records result=duplicate (not a generic invalid)');
SELECT is(tap._fetch253('r2')::jsonb #>> '{prior,scan_id}', tap._fetch253('r1')::jsonb ->> 'scan_id',
  'S3: prior.scan_id is the first (admitted) scan');
SELECT ok((tap._fetch253('r2')::jsonb #>> '{prior,device_id}') = tap._fetch253('dev')
          AND (tap._fetch253('r2')::jsonb #>> '{prior,occurred_at}') IS NOT NULL
          AND (tap._fetch253('r2')::jsonb #>> '{prior,actor_identity_id}') IS NULL,
  'S4: prior carries the admitting device and the admission time (machine path: actor NULL, device-attributed)');

-- ── S5–S7 — ledger + state invariants ──────────────────────────────────────
SELECT is((SELECT count(*)::int FROM venue.scan WHERE ticket_atom_id=(tap._fetch253('mA')::jsonb->>0)::uuid AND result='admitted'), 1,
  'S5: exactly ONE admitted row for the atom');
SELECT is((SELECT count(*)::int FROM venue.scan WHERE ticket_atom_id=(tap._fetch253('mA')::jsonb->>0)::uuid AND result='duplicate'), 1,
  'S6: the rescan is recorded in the ledger as ONE duplicate row');
SELECT is((SELECT state FROM kernel.tickets WHERE ticket_atom_id=(tap._fetch253('mA')::jsonb->>0)::uuid), 'scanned',
  'S7: the atom stays scanned (no second transition, no inventory effect)');

-- ── S8 — S07 timeout-after-commit: the SAME command_key retried → duplicate + prior
SELECT tap._store253('r3', tap._scan253(0, 'ck253-scan0')::text);
SELECT ok((tap._fetch253('r3')::jsonb ->> 'result') = 'duplicate'
          AND (tap._fetch253('r3')::jsonb #>> '{prior,scan_id}') = (tap._fetch253('r1')::jsonb ->> 'scan_id')
          AND (tap._fetch253('r3')::jsonb #>> '{prior,device_id}') = tap._fetch253('dev'),
  'S8: a retry with the ORIGINAL command_key answers duplicate + prior (the committed admission from this device) — S07; p_command_key is NOT an idempotency anchor, the duplicate branch is what makes the retry safe');
SELECT is((SELECT count(*)::int FROM venue.scan WHERE ticket_atom_id=(tap._fetch253('mA')::jsonb->>0)::uuid AND result='admitted'), 1,
  'S9: the retry did not create a second admitted row');

-- ── S10–S11 — a voided (refunded/cancelled) atom stays a plain invalid ──────
UPDATE kernel.tickets SET state='voided', updated_at=now() WHERE ticket_atom_id=(tap._fetch253('mA')::jsonb->>1)::uuid;
SELECT tap._store253('r4', tap._scan253(1, 'ck253-voided')::text);
SELECT is(tap._fetch253('r4')::jsonb ->> 'result', 'invalid', 'S10: a voided atom scans invalid');
SELECT ok(NOT (tap._fetch253('r4')::jsonb ? 'prior'), 'S11: an invalid result carries no prior block');
SELECT is((SELECT state FROM kernel.tickets WHERE ticket_atom_id=(tap._fetch253('mA')::jsonb->>1)::uuid), 'voided',
  'S12: the voided atom is untouched (no transition, nothing consumed)');

-- ── S13 — wrong session: session B''s atom through session A''s door session → invalid, no prior
SELECT tap.login_service();
SELECT tap._store253('r5', venue.record_scan_door((tap._fetch253('mB')::jsonb->>0)::uuid, tap._fetch253('sA')::uuid,
  tap._fetch253('dsid')::uuid, tap._fetch253('secret'), tap._fetch253('dev')::uuid, '{}'::jsonb, 'ck253-xsess')::text);
SELECT tap.logout();
SELECT ok((tap._fetch253('r5')::jsonb ->> 'result') = 'invalid' AND NOT (tap._fetch253('r5')::jsonb ? 'prior'),
  'S13: a wrong-session atom is invalid with no prior (wrong_session is not an admission fact)');

-- ── S14 — fail closed: state=scanned WITHOUT an admitted row is NOT a duplicate
UPDATE kernel.tickets SET state='scanned', updated_at=now() WHERE ticket_atom_id=(tap._fetch253('mA')::jsonb->>2)::uuid;
SELECT tap._store253('r6', tap._scan253(2, 'ck253-orphan')::text);
SELECT ok((tap._fetch253('r6')::jsonb ->> 'result') = 'invalid' AND NOT (tap._fetch253('r6')::jsonb ? 'prior'),
  'S14: a scanned atom with NO admitted ledger row is invalid (duplicate requires the authoritative admitted row)');

-- ── S15–S16 — the C41 race arm (unique_violation) still yields duplicate + one admitted row
-- emulate the losing side of a two-transaction race: an admitted inbound row already
-- exists for a still-active atom when the transition succeeds.
INSERT INTO venue.scan (ticket_atom_id, event_session_id, device_id, result, occurred_at)
VALUES ((tap._fetch253('mA')::jsonb->>3)::uuid, tap._fetch253('sA')::uuid, tap._fetch253('dev')::uuid, 'admitted', now());
SELECT tap._store253('r7', tap._scan253(3, 'ck253-racearm')::text);
SELECT is(tap._fetch253('r7')::jsonb ->> 'result', 'duplicate', 'S15: the unique_violation (race) arm records duplicate');
SELECT is((SELECT count(*)::int FROM venue.scan WHERE ticket_atom_id=(tap._fetch253('mA')::jsonb->>3)::uuid AND result='admitted'), 1,
  'S16: exactly ONE admitted row survives the race arm (scan_admitted_in_uq)');

-- ── S17–S19 — the STAFF path (venue.record_scan, auth.uid() + venue role, no device) shares the core
SELECT tap.login(tap.seller());
SELECT tap._store253('h1', venue.record_scan((tap._fetch253('mA')::jsonb->>4)::uuid, tap._fetch253('sA')::uuid, NULL, '{}'::jsonb, 'ck253-h1')::text);
SELECT tap._store253('h2', venue.record_scan((tap._fetch253('mA')::jsonb->>4)::uuid, tap._fetch253('sA')::uuid, NULL, '{}'::jsonb, 'ck253-h2')::text);
SELECT tap.logout();
SELECT is(tap._fetch253('h1')::jsonb ->> 'result', 'admitted', 'S17: staff path — first scan admits (actor-attributed, device NULL)');
SELECT ok((tap._fetch253('h2')::jsonb ->> 'result') = 'duplicate'
          AND (tap._fetch253('h2')::jsonb #>> '{prior,scan_id}') = (tap._fetch253('h1')::jsonb ->> 'scan_id')
          AND (tap._fetch253('h2')::jsonb #>> '{prior,device_id}') IS NULL
          AND (tap._fetch253('h2')::jsonb #>> '{prior,actor_identity_id}') = tap.seller()::text,
  'S18: staff path — sequential rescan is duplicate with prior carrying the admitting staff identity (device_id NULL on the staff path)');
SELECT is((SELECT actor_identity_id FROM venue.scan WHERE scan_id = (tap._fetch253('h1')::jsonb ->> 'scan_id')::uuid), tap.seller(),
  'S19: the staff-path admitted row is actor-attributed to the scanning staff identity');

-- ── S20–S21 — offline reconcile of a consumed atom now counts as a duplicate, never a second admit
SELECT tap.login_service();
SELECT tap._store253('rec', (venue.reconcile_offline_scans_door(
  tap._fetch253('sA')::uuid, tap._fetch253('dsid')::uuid, tap._fetch253('secret'), tap._fetch253('dev')::uuid,
  jsonb_build_array(jsonb_build_object('ticket_atom_id', tap._fetch253('mA')::jsonb->>0, 'scan_sequence', 9)), 'ck253-rec')::text));
SELECT tap.logout();
SELECT is(concat((tap._fetch253('rec')::jsonb->>'admitted'),'/',(tap._fetch253('rec')::jsonb->>'duplicates'),'/',(tap._fetch253('rec')::jsonb->>'conflicts')), '0/1/0',
  'S20: an offline replay of a consumed atom reconciles as 0 admitted / 1 duplicate / 0 conflicts');
SELECT is((SELECT count(*)::int FROM venue.scan WHERE ticket_atom_id=(tap._fetch253('mA')::jsonb->>0)::uuid AND result='admitted'), 1,
  'S21: still exactly ONE admitted row for the atom after the offline replay');

-- ── S22–S24 — credential currency (BLOCK A): stale claims refuse without a transition
SELECT tap.login_service();
SELECT tap._store253('v1', venue.record_scan_door((tap._fetch253('mA')::jsonb->>5)::uuid, tap._fetch253('sA')::uuid,
  tap._fetch253('dsid')::uuid, tap._fetch253('secret'), tap._fetch253('dev')::uuid,
  jsonb_build_object('credential_version', 7, 'key_id', tap._fetch253('kA')), 'ck253-stale')::text);
SELECT tap.logout();
SELECT ok((tap._fetch253('v1')::jsonb ->> 'result') = 'invalid' AND (tap._fetch253('v1')::jsonb ->> 'reason') = 'credential_stale',
  'S22: a stale credential_version claim is invalid/credential_stale (the holder''s old QR after a reissue)');
SELECT is((SELECT state FROM kernel.tickets WHERE ticket_atom_id=(tap._fetch253('mA')::jsonb->>5)::uuid), 'active',
  'S23: the stale-claim refusal did not transition the atom (still admissible by its current credential)');
SELECT tap.login_service();
SELECT tap._store253('v2', venue.record_scan_door((tap._fetch253('mA')::jsonb->>5)::uuid, tap._fetch253('sA')::uuid,
  tap._fetch253('dsid')::uuid, tap._fetch253('secret'), tap._fetch253('dev')::uuid,
  jsonb_build_object('credential_version', 0, 'key_id', gen_random_uuid(), 'device_label', 'front-door-iphone'), 'ck253-badkey')::text);
SELECT tap.logout();
SELECT ok((tap._fetch253('v2')::jsonb ->> 'result') = 'invalid' AND (tap._fetch253('v2')::jsonb ->> 'reason') = 'credential_stale',
  'S24: a key_id that is not the atom''s pinned signing key is invalid/credential_stale (token signed under a rotated/foreign key)');

-- ── S25–S26 — matching claims admit; the label is captured and echoed in a later prior
SELECT tap.login_service();
SELECT tap._store253('v3', venue.record_scan_door((tap._fetch253('mA')::jsonb->>5)::uuid, tap._fetch253('sA')::uuid,
  tap._fetch253('dsid')::uuid, tap._fetch253('secret'), tap._fetch253('dev')::uuid,
  jsonb_build_object('credential_version', 0, 'key_id', tap._fetch253('kA'), 'device_label', 'front-door-iphone'), 'ck253-good')::text);
SELECT tap._store253('v4', venue.record_scan_door((tap._fetch253('mA')::jsonb->>5)::uuid, tap._fetch253('sA')::uuid,
  tap._fetch253('dsid')::uuid, tap._fetch253('secret'), tap._fetch253('dev')::uuid,
  jsonb_build_object('credential_version', 0, 'key_id', tap._fetch253('kA')), 'ck253-good-again')::text);
SELECT tap.logout();
SELECT is(tap._fetch253('v3')::jsonb ->> 'result', 'admitted', 'S25: claims that match kernel.tickets (version 0, pinned key) admit');
SELECT ok((tap._fetch253('v4')::jsonb ->> 'result') = 'duplicate' AND (tap._fetch253('v4')::jsonb #>> '{prior,device_label}') = 'front-door-iphone',
  'S26: the admitting scan''s device_label is stored and echoed in the later duplicate''s prior');

-- ── S27–S28 — an unknown (well-formed) atom id answers invalid/unknown_atom, no raise, no row
SELECT tap._store253('unk', gen_random_uuid()::text);
SELECT lives_ok(
  format($$SELECT venue.record_scan_door(%L,%L,%L,%L,%L,'{}'::jsonb,'ck253-unknown')$$,
    tap._fetch253('unk'), tap._fetch253('sA'), tap._fetch253('dsid'), tap._fetch253('secret'), tap._fetch253('dev')),
  'S27: an unknown atom id does not raise (no foreign_key_violation → no HTTP 500 at the edge)');
SELECT tap.login_service();
SELECT tap._store253('u1', venue.record_scan_door(tap._fetch253('unk')::uuid, tap._fetch253('sA')::uuid,
  tap._fetch253('dsid')::uuid, tap._fetch253('secret'), tap._fetch253('dev')::uuid, '{}'::jsonb, 'ck253-unknown2')::text);
SELECT tap.logout();
SELECT ok((tap._fetch253('u1')::jsonb ->> 'result') = 'invalid' AND (tap._fetch253('u1')::jsonb ->> 'reason') = 'unknown_atom'
          AND (SELECT count(*) FROM venue.scan WHERE ticket_atom_id = tap._fetch253('unk')::uuid) = 0,
  'S28: unknown atom → result invalid, reason unknown_atom, zero ledger rows (nothing to consume)');

-- ── S29 — reasons distinguish refunded/cancelled from wrong-event (S05/S08)
SELECT ok((tap._fetch253('r4')::jsonb ->> 'reason') = 'voided' AND (tap._fetch253('r5')::jsonb ->> 'reason') = 'wrong_session',
  'S29: invalid responses carry the distinguishing reason: voided (refunded/cancelled) vs wrong_session');

-- ── S30 — malformed claims are refused, not admitted
SELECT tap.login_service();
SELECT tap._store253('m1', venue.record_scan_door((tap._fetch253('mB')::jsonb->>0)::uuid, tap._fetch253('sA')::uuid,
  tap._fetch253('dsid')::uuid, tap._fetch253('secret'), tap._fetch253('dev')::uuid,
  jsonb_build_object('credential_version', 'seven'), 'ck253-malformed')::text);
SELECT tap.logout();
SELECT ok((tap._fetch253('m1')::jsonb ->> 'result') = 'invalid' AND (tap._fetch253('m1')::jsonb ->> 'reason') = 'credential_claims_malformed',
  'S30: a malformed credential_version claim is invalid/credential_claims_malformed, never admitted');

SELECT * FROM finish();
ROLLBACK;

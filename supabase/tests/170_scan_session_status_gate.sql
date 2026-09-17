-- ============================================================================
-- 170_scan_session_status_gate.sql — migration 104: venue.record_scan refuses
-- admission on a TERMINAL event session (cancelled/completed), the door P0-1
-- fix (contract §7.5 admit-gate 1; makes catalog.cancel_event's 088:1607
-- "the cancelled session already denies their scan" assertion TRUE).
-- This is the missing T-RPC-DOOR-04 / T-RLS-DOOR-04 regression.
-- ============================================================================
BEGIN;
SELECT plan(6);
SELECT tap.seed_core();

CREATE TABLE tap.memo_170 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store170(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_170 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fetch170(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_170 WHERE k=$1 $m$;

-- ── FIXTURE — org → venue(approved) → event → session → tt → comp batch →
-- per-event signing key → 3 comp atoms to the buyer; seller granted
-- venue_manager; native scanning enabled; a scan device registered. ─────────
SELECT tap.login(tap.seller());
SELECT tap._store170('org', (kernel.create_organization('Gate Co','Gate Co','ck170-o') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch170('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store170('venue', (catalog.create_venue(tap._fetch170('org')::uuid,'Gate Hall','wynwood',NULL,'ck170-v') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch170('venue')::uuid,'approved','miami_gate','ck170-a');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._store170('event', (catalog.create_event(tap._fetch170('venue')::uuid,'Gate Night',
  jsonb_build_object('starts_at',(now()+interval '10 days')::text,'ends_at',(now()+interval '10 days 5 hours')::text),'ck170-e') ->> 'event_id'));
SELECT tap._store170('session', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch170('event')::uuid));
SELECT tap._store170('tt', (venue.create_ticket_type(tap._fetch170('event')::uuid,'admission','GA',5000,'public','ck170-tt') ->> 'ticket_type_id'));
SELECT tap._store170('batch', (venue.create_inventory_batch(tap._fetch170('tt')::uuid, tap._fetch170('session')::uuid, 'comp', 100, 0, 'ck170-b') ->> 'batch_id'));
SELECT tap.logout();
WITH insk AS (INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_event', tap._fetch170('event')::uuid, 'PUBKEY-170', 'kms-170', 'active', now(), 'ES256') RETURNING key_id)
SELECT tap._store170('key', (SELECT key_id::text FROM insk));
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_issuance_enabled', 2, 'true'::jsonb, 'public');
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_scanning_enabled', 2, 'true'::jsonb, 'public');
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by)
VALUES (tap._fetch170('venue')::uuid, tap.seller(), 'venue_manager', tap.admin_user()) ON CONFLICT DO NOTHING;
SELECT tap._store170('mint', (kernel.issue_ticket_atoms(jsonb_build_object(
  'session_id',tap._fetch170('session')::uuid,'org_id',tap._fetch170('org')::uuid,'ticket_type_id',tap._fetch170('tt')::uuid,
  'batch_id',tap._fetch170('batch')::uuid,'owner_id',tap.buyer(),'quantity',3,'cause','comp',
  'cause_ref',gen_random_uuid(),'signing_key_id',tap._fetch170('key')::uuid),'ck170-mint') -> 'atom_ids')::text);
SELECT tap._store170('a0', (tap._fetch170('mint')::jsonb ->> 0));
SELECT tap._store170('a1', (tap._fetch170('mint')::jsonb ->> 1));
SELECT tap._store170('a2', (tap._fetch170('mint')::jsonb ->> 2));
SELECT tap.login(tap.seller());
SELECT tap._store170('dev', (venue.register_scan_device(tap._fetch170('venue')::uuid, 'scanner-170', 'ck170-dev') ->> 'device_id'));

-- ── A1: a 'scheduled' session (the default) ADMITS. ─────────────────────────
SELECT is((venue.record_scan(tap._fetch170('a0')::uuid, tap._fetch170('session')::uuid, tap._fetch170('dev')::uuid, '{}'::jsonb, 'ck170-s0') ->> 'result'),
  'admitted', 'A1: a scheduled session admits (the terminal-status gate does not touch the normal flow)');

-- ── A2: a 'live' session ADMITS. ────────────────────────────────────────────
SELECT tap.logout();
UPDATE catalog.event_session SET status='live' WHERE session_id = tap._fetch170('session')::uuid;
SELECT tap.login(tap.seller());
SELECT is((venue.record_scan(tap._fetch170('a1')::uuid, tap._fetch170('session')::uuid, tap._fetch170('dev')::uuid, '{}'::jsonb, 'ck170-s1') ->> 'result'),
  'admitted', 'A2: a live session admits');

-- ── A3: a 'cancelled' session REFUSES (the P0 fix; cancel_event's assumption). ─
SELECT tap.logout();
UPDATE catalog.event_session SET status='cancelled' WHERE session_id = tap._fetch170('session')::uuid;
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$SELECT venue.record_scan(%L,%L,%L,'{}'::jsonb,'ck170-s2')$$,
    tap._fetch170('a2'), tap._fetch170('session'), tap._fetch170('dev')),
  NULL, 'precondition_failed: session_not_admitting (status=cancelled)',
  'A3: a CANCELLED session refuses session_not_admitting — a comp atom of a cancelled event is no longer scannable');

-- ── A4: a 'completed' session REFUSES. ──────────────────────────────────────
SELECT tap.logout();
UPDATE catalog.event_session SET status='completed' WHERE session_id = tap._fetch170('session')::uuid;
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$SELECT venue.record_scan(%L,%L,%L,'{}'::jsonb,'ck170-s3')$$,
    tap._fetch170('a2'), tap._fetch170('session'), tap._fetch170('dev')),
  NULL, 'precondition_failed: session_not_admitting (status=completed)',
  'A4: a COMPLETED session refuses session_not_admitting');

-- ── A5: back to 'scheduled' ADMITS the still-active atom — proving the session
-- status was the ONLY blocker (the atom was never consumed while refused). ───
SELECT tap.logout();
UPDATE catalog.event_session SET status='scheduled' WHERE session_id = tap._fetch170('session')::uuid;
SELECT tap.login(tap.seller());
SELECT is((venue.record_scan(tap._fetch170('a2')::uuid, tap._fetch170('session')::uuid, tap._fetch170('dev')::uuid, '{}'::jsonb, 'ck170-s4') ->> 'result'),
  'admitted', 'A5: restoring the session admits a2 — the gate refused, it did not consume the atom');

-- ── A6: exactly the three atoms were admitted (a0, a1, a2), none during the
-- terminal window. ─────────────────────────────────────────────────────────
SELECT is((SELECT count(*)::int FROM venue.scan WHERE event_session_id = tap._fetch170('session')::uuid AND result='admitted' AND direction='in'),
  3, 'A6: exactly three admitted-in scans total — the two terminal-status attempts wrote no admission');

SELECT tap.logout();
SELECT * FROM finish();
ROLLBACK;

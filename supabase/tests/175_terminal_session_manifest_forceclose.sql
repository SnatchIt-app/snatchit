-- ============================================================================
-- 175_terminal_session_manifest_forceclose.sql — migration 109 (PFA-PT-9 item 2).
--   catalog.cancel_event, on flipping a session to 'cancelled', force-closes that
--   session's OPEN door episode and emits DoorManifestInvalidated (#44) — via the
--   terminal-status trigger, without touching the cancel_event money body. An
--   unrelated event's episode is untouched; a duplicate cancel does not re-emit;
--   the cancel result shape (money path) is unchanged (comp atoms still skipped).
-- ============================================================================
BEGIN;
SELECT plan(9);
SELECT tap.seed_core();

CREATE TABLE tap.memo_175 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store175(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_175 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fetch175(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_175 WHERE k=$1 $m$;

-- ── FIXTURE — venue(approved), event A (comp atoms, open manifest) to cancel,
-- event B (open manifest) that must stay open. ───────────────────────────────
SELECT tap.login(tap.seller());
SELECT tap._store175('org', (kernel.create_organization('CK Co','CK Co','ck175-o') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch175('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store175('venue', (catalog.create_venue(tap._fetch175('org')::uuid,'CK Hall','wynwood',NULL,'ck175-v') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch175('venue')::uuid,'approved','miami_gate','ck175-a');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_issuance_enabled', 2, 'true'::jsonb, 'public');
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by)
VALUES (tap._fetch175('venue')::uuid, tap.seller(), 'venue_manager', tap.admin_user()) ON CONFLICT DO NOTHING;

SELECT tap.login(tap.seller());
SELECT tap._store175('eA', (catalog.create_event(tap._fetch175('venue')::uuid,'CK A',
  jsonb_build_object('starts_at',(now()+interval '9 days')::text,'ends_at',(now()+interval '9 days 5 hours')::text),'ck175-eA') ->> 'event_id'));
SELECT tap._store175('sA', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch175('eA')::uuid));
SELECT tap._store175('ttA', (venue.create_ticket_type(tap._fetch175('eA')::uuid,'admission','GA',5000,'public','ck175-ttA') ->> 'ticket_type_id'));
SELECT tap._store175('bA', (venue.create_inventory_batch(tap._fetch175('ttA')::uuid, tap._fetch175('sA')::uuid, 'comp', 100, 0, 'ck175-bA') ->> 'batch_id'));
SELECT tap._store175('eB', (catalog.create_event(tap._fetch175('venue')::uuid,'CK B',
  jsonb_build_object('starts_at',(now()+interval '9 days')::text,'ends_at',(now()+interval '9 days 5 hours')::text),'ck175-eB') ->> 'event_id'));
SELECT tap._store175('sB', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch175('eB')::uuid));
SELECT tap.logout();
WITH kA AS (INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_event', tap._fetch175('eA')::uuid, 'PUBKEY-175A', 'kms-175A', 'active', now(), 'ES256') RETURNING key_id)
SELECT tap._store175('kA', (SELECT key_id::text FROM kA));
SELECT kernel.issue_ticket_atoms(jsonb_build_object(
  'session_id',tap._fetch175('sA')::uuid,'org_id',tap._fetch175('org')::uuid,'ticket_type_id',tap._fetch175('ttA')::uuid,
  'batch_id',tap._fetch175('bA')::uuid,'owner_id',tap.buyer(),'quantity',2,'cause','comp',
  'cause_ref',gen_random_uuid(),'signing_key_id',tap._fetch175('kA')::uuid),'ck175-mA');
SELECT tap.login(tap.seller());
SELECT tap._store175('mfA', (venue.open_door_manifest(tap._fetch175('sA')::uuid,'doors_open','ck175-dA') ->> 'manifest_id'));
SELECT tap._store175('mfB', (venue.open_door_manifest(tap._fetch175('sB')::uuid,'doors_open','ck175-dB') ->> 'manifest_id'));
SELECT tap.logout();

-- ── cancel event A (as platform_admin) ──────────────────────────────────────
SELECT tap.login(tap.admin_user());
SELECT tap._store175('cancel', (catalog.cancel_event(tap._fetch175('eA')::uuid, 'weather', 'ck175-cancel')::text));
SELECT tap.logout();

SELECT is((tap._fetch175('cancel')::jsonb ->> 'status'), 'ok',
  'C1: cancel_event succeeds');
SELECT is((SELECT status FROM catalog.event_session WHERE session_id = tap._fetch175('sA')::uuid), 'cancelled',
  'C2: session A is cancelled');
SELECT is((SELECT status FROM venue.door_manifest WHERE manifest_id = tap._fetch175('mfA')::uuid), 'closed',
  'C3: session A''s open door episode was force-closed by the terminal-status trigger');
SELECT is((SELECT close_reason FROM venue.door_manifest WHERE manifest_id = tap._fetch175('mfA')::uuid), 'event_cancelled',
  'C4: close_reason is event_cancelled');
SELECT is((SELECT count(*)::int FROM notify.outbox WHERE event_type='DoorManifestInvalidated' AND aggregate_id = tap._fetch175('sA')::uuid), 1,
  'C5: a DoorManifestInvalidated (#44) was emitted for the cancelled session');
SELECT is((SELECT status FROM venue.door_manifest WHERE manifest_id = tap._fetch175('mfB')::uuid), 'open',
  'C6: the unrelated event B''s episode stays OPEN (per-session scope)');
SELECT is((tap._fetch175('cancel')::jsonb ->> 'atoms_voided')::int, 0,
  'C7: money non-regression — comp atoms have no refund lineage, still 0 voided (trigger did not disturb the money path)');

-- ── duplicate cancel: no double-close, no re-emit ───────────────────────────
SELECT tap.login(tap.admin_user());
SELECT is((catalog.cancel_event(tap._fetch175('eA')::uuid, 'weather', 'ck175-cancel2') ->> 'status'), 'noop_replay',
  'C8: a duplicate cancel is a noop_replay');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM notify.outbox WHERE event_type='DoorManifestInvalidated' AND aggregate_id = tap._fetch175('sA')::uuid), 1,
  'C9: the duplicate cancel did NOT re-emit #44 (session already cancelled -> trigger did not fire)');

SELECT * FROM finish();
ROLLBACK;

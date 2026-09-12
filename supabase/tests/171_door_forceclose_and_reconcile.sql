-- ============================================================================
-- 171_door_forceclose_and_reconcile.sql — migration 105.
--   Section F: kernel.force_close_key_manifests (§5.6 mechanism) — closes open
--     episodes in the revoked key's scope, emits DoorManifestInvalidated (#44),
--     signals no_open_episode to a reconnecting device, and does NOT touch
--     out-of-scope episodes (T-RPC-KEY-05 scope boundary).
--   Section R: venue.reconcile_offline_scans (RPC §9.5) — {admitted,duplicates,
--     conflicts} shape + first-in-wins + per-item session cross-check.
-- ============================================================================
BEGIN;
SELECT plan(9);
SELECT tap.seed_core();

CREATE TABLE tap.memo_171 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store171(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_171 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fetch171(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_171 WHERE k=$1 $m$;

-- ── FIXTURE — one org/venue(approved), TWO events (A + B), each a session,
-- comp batch, per-event signing key, minted atoms, and an OPEN door manifest. ─
SELECT tap.login(tap.seller());
SELECT tap._store171('org', (kernel.create_organization('FC Co','FC Co','ck171-o') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch171('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store171('venue', (catalog.create_venue(tap._fetch171('org')::uuid,'FC Hall','wynwood',NULL,'ck171-v') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch171('venue')::uuid,'approved','miami_gate','ck171-a');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_issuance_enabled', 2, 'true'::jsonb, 'public');
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_scanning_enabled', 2, 'true'::jsonb, 'public');
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by)
VALUES (tap._fetch171('venue')::uuid, tap.seller(), 'venue_manager', tap.admin_user()) ON CONFLICT DO NOTHING;

SELECT tap.login(tap.seller());
SELECT tap._store171('eA', (catalog.create_event(tap._fetch171('venue')::uuid,'FC A',
  jsonb_build_object('starts_at',(now()+interval '9 days')::text,'ends_at',(now()+interval '9 days 5 hours')::text),'ck171-eA') ->> 'event_id'));
SELECT tap._store171('sA', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch171('eA')::uuid));
SELECT tap._store171('ttA', (venue.create_ticket_type(tap._fetch171('eA')::uuid,'admission','GA',5000,'public','ck171-ttA') ->> 'ticket_type_id'));
SELECT tap._store171('bA', (venue.create_inventory_batch(tap._fetch171('ttA')::uuid, tap._fetch171('sA')::uuid, 'comp', 100, 0, 'ck171-bA') ->> 'batch_id'));
SELECT tap._store171('eB', (catalog.create_event(tap._fetch171('venue')::uuid,'FC B',
  jsonb_build_object('starts_at',(now()+interval '9 days')::text,'ends_at',(now()+interval '9 days 5 hours')::text),'ck171-eB') ->> 'event_id'));
SELECT tap._store171('sB', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch171('eB')::uuid));
SELECT tap._store171('ttB', (venue.create_ticket_type(tap._fetch171('eB')::uuid,'admission','GA',5000,'public','ck171-ttB') ->> 'ticket_type_id'));
SELECT tap._store171('bB', (venue.create_inventory_batch(tap._fetch171('ttB')::uuid, tap._fetch171('sB')::uuid, 'comp', 100, 0, 'ck171-bB') ->> 'batch_id'));
SELECT tap.logout();
WITH kA AS (INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_event', tap._fetch171('eA')::uuid, 'PUBKEY-171A', 'kms-171A', 'active', now(), 'ES256') RETURNING key_id)
SELECT tap._store171('kA', (SELECT key_id::text FROM kA));
WITH kB AS (INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_event', tap._fetch171('eB')::uuid, 'PUBKEY-171B', 'kms-171B', 'active', now(), 'ES256') RETURNING key_id)
SELECT tap._store171('kB', (SELECT key_id::text FROM kB));
SELECT tap._store171('mA', (kernel.issue_ticket_atoms(jsonb_build_object(
  'session_id',tap._fetch171('sA')::uuid,'org_id',tap._fetch171('org')::uuid,'ticket_type_id',tap._fetch171('ttA')::uuid,
  'batch_id',tap._fetch171('bA')::uuid,'owner_id',tap.buyer(),'quantity',3,'cause','comp',
  'cause_ref',gen_random_uuid(),'signing_key_id',tap._fetch171('kA')::uuid),'ck171-mA') -> 'atom_ids')::text);
SELECT tap._store171('mB', (kernel.issue_ticket_atoms(jsonb_build_object(
  'session_id',tap._fetch171('sB')::uuid,'org_id',tap._fetch171('org')::uuid,'ticket_type_id',tap._fetch171('ttB')::uuid,
  'batch_id',tap._fetch171('bB')::uuid,'owner_id',tap.buyer(),'quantity',1,'cause','comp',
  'cause_ref',gen_random_uuid(),'signing_key_id',tap._fetch171('kB')::uuid),'ck171-mB') -> 'atom_ids')::text);
SELECT tap.login(tap.seller());
SELECT tap._store171('mfA', (venue.open_door_manifest(tap._fetch171('sA')::uuid,'doors_open','ck171-dA') ->> 'manifest_id'));
SELECT tap._store171('mfB', (venue.open_door_manifest(tap._fetch171('sB')::uuid,'doors_open','ck171-dB') ->> 'manifest_id'));
SELECT tap._store171('devA', (venue.register_scan_device(tap._fetch171('venue')::uuid, 'scanner-171A', 'ck171-devA') ->> 'device_id'));
SELECT tap.logout();

-- ── Section F — force-close key A's scope (called as SUPERUSER: zero-grant) ──
SELECT is(kernel.force_close_key_manifests(tap._fetch171('kA')::uuid, 'key_revoked'), 1,
  'F1: force_close closes exactly ONE open episode in key A''s (per_event) scope');
SELECT is((SELECT status FROM venue.door_manifest WHERE manifest_id = tap._fetch171('mfA')::uuid), 'closed',
  'F2: session A''s episode is now closed');
SELECT is((SELECT close_reason FROM venue.door_manifest WHERE manifest_id = tap._fetch171('mfA')::uuid), 'key_revoked',
  'F3: close_reason is the D3 code key_revoked');
SELECT is((SELECT count(*)::int FROM notify.outbox WHERE event_type='DoorManifestInvalidated' AND aggregate_id = tap._fetch171('sA')::uuid), 1,
  'F4: a DoorManifestInvalidated (#44) outbox envelope was emitted for session A');
SELECT tap.login(tap.seller());
SELECT is((venue.get_door_manifest(tap._fetch171('sA')::uuid, 0) ->> 'status'), 'no_open_episode',
  'F5: get_door_manifest returns no_open_episode — the reconnect-refuse signal');
SELECT tap.logout();
SELECT is((SELECT status FROM venue.door_manifest WHERE manifest_id = tap._fetch171('mfB')::uuid), 'open',
  'F6 [T-RPC-KEY-05]: event B''s episode stays OPEN — out-of-scope episodes untouched');
SELECT is((SELECT count(*)::int FROM notify.outbox WHERE event_type='DoorManifestInvalidated' AND aggregate_id = tap._fetch171('sB')::uuid), 0,
  'F7: no DoorManifestInvalidated for the out-of-scope session B');

-- ── Section R — reconcile_offline_scans shape + first-in-wins + session check ─
SELECT tap.login(tap.seller());
SELECT tap._store171('rres', (venue.reconcile_offline_scans(
  tap._fetch171('sA')::uuid, tap._fetch171('devA')::uuid,
  jsonb_build_array(
    jsonb_build_object('ticket_atom_id', tap._fetch171('mA')::jsonb->>0, 'server_receipt_at', (now())::text, 'scan_sequence', 1),
    jsonb_build_object('ticket_atom_id', tap._fetch171('mA')::jsonb->>0, 'server_receipt_at', (now()+interval '1 second')::text, 'scan_sequence', 2)
  ), 'ck171-rec')::text));
SELECT is(concat((tap._fetch171('rres')::jsonb->>'admitted'), '/',
                 (tap._fetch171('rres')::jsonb->>'duplicates'), '/',
                 (tap._fetch171('rres')::jsonb->>'conflicts')), '1/0/1',
  'R1: reconcile returns the {admitted,duplicates,conflicts} shape; two same-atom items -> 1 admitted, then the re-scan of the consumed atom is 1 conflict (invalid, not_active); deterministic order');
-- R2: a batch mixing a GOOD item with a WRONG-SESSION item does NOT poison the
-- batch — the good one admits, the mismatched one is an isolated conflict, no raise.
SELECT tap._store171('rres2', (venue.reconcile_offline_scans(
  tap._fetch171('sA')::uuid, tap._fetch171('devA')::uuid,
  jsonb_build_array(
    jsonb_build_object('ticket_atom_id', tap._fetch171('mA')::jsonb->>1, 'scan_sequence', 1),
    jsonb_build_object('ticket_atom_id', tap._fetch171('mB')::jsonb->>0, 'session_id', tap._fetch171('sB'), 'scan_sequence', 2)
  ), 'ck171-rec2')::text));
SELECT is(concat((tap._fetch171('rres2')::jsonb->>'admitted'), '/', (tap._fetch171('rres2')::jsonb->>'conflicts')), '1/1',
  'R2: good item admits, wrong-session item is an isolated conflict — no whole-batch poison (adversarial P1)');
SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;

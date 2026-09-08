-- ============================================================================
-- 172_revoke_signing_key_unpark.sql — migration 106 (PFA-18B).
--   Section A: authorization — platform_admin + aal2 only (venue_manager and a
--     non-aal2 platform_admin refused).
--   Section B: the revoke cascade — status='revoked' (not_after left as-is), in-scope
--     episode force-closed with close_reason='key_revoked', #44 emitted; the
--     out-of-scope episode untouched (scope isolation).
--   Section C: idempotent replay; open-on-revoked-trust refused; the signer
--     refuses the revoked key; unknown key not_found; wrong ack refused.
-- ============================================================================
BEGIN;
SELECT plan(15);
SELECT tap.seed_core();

CREATE TABLE tap.memo_172 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store172(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_172 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fetch172(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_172 WHERE k=$1 $m$;
CREATE FUNCTION tap._aal2() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;

-- ── FIXTURE — org/venue(approved), TWO events A+B, per-event keys A+B, minted
-- atoms, an OPEN door manifest for each. (Same shape as test 171.) ────────────
SELECT tap.login(tap.seller());
SELECT tap._store172('org', (kernel.create_organization('RK Co','RK Co','ck172-o') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch172('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store172('venue', (catalog.create_venue(tap._fetch172('org')::uuid,'RK Hall','wynwood',NULL,'ck172-v') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch172('venue')::uuid,'approved','miami_gate','ck172-a');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_issuance_enabled', 2, 'true'::jsonb, 'public');
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by)
VALUES (tap._fetch172('venue')::uuid, tap.seller(), 'venue_manager', tap.admin_user()) ON CONFLICT DO NOTHING;

SELECT tap.login(tap.seller());
SELECT tap._store172('eA', (catalog.create_event(tap._fetch172('venue')::uuid,'RK A',
  jsonb_build_object('starts_at',(now()+interval '9 days')::text,'ends_at',(now()+interval '9 days 5 hours')::text),'ck172-eA') ->> 'event_id'));
SELECT tap._store172('sA', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch172('eA')::uuid));
SELECT tap._store172('ttA', (venue.create_ticket_type(tap._fetch172('eA')::uuid,'admission','GA',5000,'public','ck172-ttA') ->> 'ticket_type_id'));
SELECT tap._store172('bA', (venue.create_inventory_batch(tap._fetch172('ttA')::uuid, tap._fetch172('sA')::uuid, 'comp', 100, 0, 'ck172-bA') ->> 'batch_id'));
SELECT tap._store172('eB', (catalog.create_event(tap._fetch172('venue')::uuid,'RK B',
  jsonb_build_object('starts_at',(now()+interval '9 days')::text,'ends_at',(now()+interval '9 days 5 hours')::text),'ck172-eB') ->> 'event_id'));
SELECT tap._store172('sB', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch172('eB')::uuid));
SELECT tap._store172('ttB', (venue.create_ticket_type(tap._fetch172('eB')::uuid,'admission','GA',5000,'public','ck172-ttB') ->> 'ticket_type_id'));
SELECT tap._store172('bB', (venue.create_inventory_batch(tap._fetch172('ttB')::uuid, tap._fetch172('sB')::uuid, 'comp', 100, 0, 'ck172-bB') ->> 'batch_id'));
SELECT tap.logout();
WITH kA AS (INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_event', tap._fetch172('eA')::uuid, 'PUBKEY-172A', 'kms-172A', 'active', now(), 'ES256') RETURNING key_id)
SELECT tap._store172('kA', (SELECT key_id::text FROM kA));
WITH kB AS (INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_event', tap._fetch172('eB')::uuid, 'PUBKEY-172B', 'kms-172B', 'active', now(), 'ES256') RETURNING key_id)
SELECT tap._store172('kB', (SELECT key_id::text FROM kB));
SELECT tap._store172('mA', (kernel.issue_ticket_atoms(jsonb_build_object(
  'session_id',tap._fetch172('sA')::uuid,'org_id',tap._fetch172('org')::uuid,'ticket_type_id',tap._fetch172('ttA')::uuid,
  'batch_id',tap._fetch172('bA')::uuid,'owner_id',tap.buyer(),'quantity',2,'cause','comp',
  'cause_ref',gen_random_uuid(),'signing_key_id',tap._fetch172('kA')::uuid),'ck172-mA') -> 'atom_ids')::text);
SELECT kernel.issue_ticket_atoms(jsonb_build_object(
  'session_id',tap._fetch172('sB')::uuid,'org_id',tap._fetch172('org')::uuid,'ticket_type_id',tap._fetch172('ttB')::uuid,
  'batch_id',tap._fetch172('bB')::uuid,'owner_id',tap.buyer(),'quantity',1,'cause','comp',
  'cause_ref',gen_random_uuid(),'signing_key_id',tap._fetch172('kB')::uuid),'ck172-mB');
SELECT tap.login(tap.seller());
SELECT tap._store172('mfA', (venue.open_door_manifest(tap._fetch172('sA')::uuid,'doors_open','ck172-dA') ->> 'manifest_id'));
SELECT tap._store172('mfB', (venue.open_door_manifest(tap._fetch172('sB')::uuid,'doors_open','ck172-dB') ->> 'manifest_id'));
SELECT tap.logout();

-- ── Section A — authorization ───────────────────────────────────────────────
SELECT tap.login(tap.seller());   -- venue_manager, NOT platform
SELECT throws_like(
  format($$SELECT kernel.revoke_signing_key(%L,'incident','1','ck172-r-vm')$$, tap._fetch172('kA')),
  '%platform_admin%',
  'A1: a venue_manager cannot revoke a signing key (platform_admin only — PFA-18B single control)');
SELECT tap.logout();

SELECT tap.login(tap.admin_user());   -- platform_admin but aal1 (no aal claim)
SELECT throws_like(
  format($$SELECT kernel.revoke_signing_key(%L,'incident','1','ck172-r-noaal')$$, tap._fetch172('kA')),
  '%step_up%',
  'A2: a platform_admin WITHOUT an aal2 step-up is refused');

-- ── Section B — the cascade (platform_admin + aal2) ─────────────────────────
SELECT tap._aal2();
SELECT throws_like(
  format($$SELECT kernel.revoke_signing_key(%L,'incident','99','ck172-r-badack')$$, tap._fetch172('kA')),
  '%unacknowledged_live_credentials%',
  'B1: a wrong live-credentials ack is refused (1 open in-scope episode, ack 99)');
SELECT is(
  (kernel.revoke_signing_key(tap._fetch172('kA')::uuid, 'incident', 1, 'ck172-r-ok') ->> 'manifests_closed')::int, 1,
  'B2: platform_admin + aal2 + correct ack revokes and force-closes exactly ONE in-scope episode');
SELECT tap.logout();

SELECT is((SELECT status FROM venue.door_manifest WHERE manifest_id = tap._fetch172('mfA')::uuid), 'closed',
  'B3: event A''s open episode is now closed');
SELECT is((SELECT close_reason FROM venue.door_manifest WHERE manifest_id = tap._fetch172('mfA')::uuid), 'key_revoked',
  'B4: close_reason is the D3 code key_revoked');
SELECT is((SELECT count(*)::int FROM notify.outbox WHERE event_type='DoorManifestInvalidated' AND aggregate_id = tap._fetch172('sA')::uuid), 1,
  'B5: a DoorManifestInvalidated (#44) envelope was emitted for session A');
SELECT is((SELECT status FROM venue.door_manifest WHERE manifest_id = tap._fetch172('mfB')::uuid), 'open',
  'B6 [scope]: event B''s episode stays OPEN — out-of-scope key untouched');
SELECT is((SELECT count(*)::int FROM notify.outbox WHERE event_type='DoorManifestInvalidated' AND aggregate_id = tap._fetch172('sB')::uuid), 0,
  'B7: no #44 for the out-of-scope session B');
SELECT is((SELECT status FROM kernel.signing_key WHERE key_id = tap._fetch172('kA')::uuid), 'revoked',
  'B8: key A is now revoked (forward-only terminal)');
SELECT is((SELECT count(*)::int FROM kernel.signing_key WHERE event_id = tap._fetch172('eA')::uuid AND status='active'), 0,
  'B9: no ACTIVE signing key remains for event A (the revoked key is no longer resolvable as active)');

-- ── Section C — replay, open-refuse, signer-refuse, unknown ─────────────────
SELECT tap.login(tap.admin_user());
SELECT tap._aal2();
SELECT is((kernel.revoke_signing_key(tap._fetch172('kA')::uuid, 'incident', NULL, 'ck172-r-replay') ->> 'status'), 'noop_replay',
  'C1: revoking an already-revoked key is a safe idempotent no-op');
SELECT throws_like(
  format($$SELECT kernel.revoke_signing_key(%L,'incident',NULL,'ck172-r-unknown')$$, gen_random_uuid()::text),
  '%not_found%',
  'C2: an unknown key is not_found');
SELECT tap.logout();

SELECT tap.login(tap.seller());   -- venue_manager
SELECT throws_like(
  format($$SELECT venue.open_door_manifest(%L,'doors_reopen','ck172-reopen')$$, tap._fetch172('sA')),
  '%signing_key_revoked%',
  'C3: open_door_manifest REFUSES to reopen session A — its atoms are pinned to the revoked key (no open on revoked trust)');
SELECT tap.logout();

SELECT tap.login(tap.buyer());    -- the atom owner
SELECT is((kernel.get_ticket_signing_context((tap._fetch172('mA')::jsonb->>0)::uuid) ->> 'code'), 'signing_key_unavailable',
  'C4: the signer refuses the revoked key for an already-pinned atom (no fallback)');
SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;

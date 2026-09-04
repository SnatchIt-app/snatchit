-- ============================================================================
-- 173_door_pin_kdf_unpark.sql — migration 107 (PFA-26-UNPARK).
--   Section P: create_door_pin — bcrypt storage (never plaintext, never returned),
--     venue_manager authz, input envelope, cross-tenant session guard.
--   Section M: mint_door_session — constant-time verify, the token contract that
--     kernel.assert_door_session recomputes, OPAQUE failure (wrong pin/device/
--     session all indistinguishable), re-mint idempotency, PIN-revoke kills mint.
-- ============================================================================
BEGIN;
SELECT plan(13);
SELECT tap.seed_core();

CREATE TABLE tap.memo_173 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store173(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_173 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fetch173(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_173 WHERE k=$1 $m$;

-- ── FIXTURE — org/venue(approved), event+session, a registered scan device. ──
SELECT tap.login(tap.seller());
SELECT tap._store173('org', (kernel.create_organization('PK Co','PK Co','ck173-o') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch173('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store173('venue', (catalog.create_venue(tap._fetch173('org')::uuid,'PK Hall','wynwood',NULL,'ck173-v') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch173('venue')::uuid,'approved','miami_gate','ck173-a');
SELECT tap.logout();
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by)
VALUES (tap._fetch173('venue')::uuid, tap.seller(), 'venue_manager', tap.admin_user()) ON CONFLICT DO NOTHING;
SELECT tap.login(tap.seller());
SELECT tap._store173('eA', (catalog.create_event(tap._fetch173('venue')::uuid,'PK A',
  jsonb_build_object('starts_at',(now()+interval '9 days')::text,'ends_at',(now()+interval '9 days 5 hours')::text),'ck173-eA') ->> 'event_id'));
SELECT tap._store173('sA', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch173('eA')::uuid));
SELECT tap._store173('dev', (venue.register_scan_device(tap._fetch173('venue')::uuid, 'scanner-173', 'ck173-dev') ->> 'device_id'));
SELECT tap.logout();

-- ── Section P — create_door_pin ─────────────────────────────────────────────
SELECT tap.login(tap.buyer());   -- no venue role
SELECT throws_like(
  format($$SELECT venue.create_door_pin(%L,%L,'front','1234',(now()+interval '1 day'),'ck173-p-anon')$$, tap._fetch173('venue'), tap._fetch173('sA')),
  '%insufficient_privilege%',
  'P1: a non-venue_manager cannot create a door PIN');
SELECT tap.logout();

SELECT tap.login(tap.seller());   -- venue_manager
SELECT tap._store173('pin', (venue.create_door_pin(tap._fetch173('venue')::uuid, tap._fetch173('sA')::uuid, 'front', 'sekret-1234', (now()+interval '1 day'), 'ck173-p-ok') ->> 'pin_id'));
SELECT ok(tap._fetch173('pin') IS NOT NULL, 'P2: venue_manager creates a door PIN (pin_id returned)');
SELECT throws_like(
  format($$SELECT venue.create_door_pin(%L,%L,'front','',(now()+interval '1 day'),'ck173-p-empty')$$, tap._fetch173('venue'), tap._fetch173('sA')),
  '%invalid_input%',
  'P3: an empty PIN is rejected before the KDF');
SELECT throws_like(
  format($$SELECT venue.create_door_pin(%L,%L,'front',%L,(now()+interval '1 day'),'ck173-p-big')$$, tap._fetch173('venue'), tap._fetch173('sA'), repeat('x',65)),
  '%invalid_input%',
  'P4: an oversized (>64 byte) PIN is rejected (bcrypt 72-byte truncation guard)');
SELECT throws_like(
  format($$SELECT venue.create_door_pin(%L,%L,'front','1234',(now()+interval '1 day'),'ck173-p-xtenant')$$, tap._fetch173('venue'), gen_random_uuid()::text),
  '%not_found%',
  'P5: a session that is not in this venue is refused (cross-tenant guard)');
SELECT tap.logout();

-- pin_hash is bcrypt, never plaintext, and was never returned to the caller.
SELECT is((SELECT left(pin_hash,3) FROM venue.door_pin WHERE pin_id = tap._fetch173('pin')::uuid), '$2a',
  'P6: the stored pin_hash is a bcrypt modular-crypt verifier ($2a$…), never the plaintext');

-- ── Section M — mint_door_session (service_role machine path) ────────────────
SELECT tap.login_service();
SELECT tap._store173('mint', (venue.mint_door_session(tap._fetch173('venue')::uuid, tap._fetch173('sA')::uuid, tap._fetch173('dev')::uuid, 'sekret-1234', 'ck173-m-ok')::text));
SELECT tap._store173('dsid', (tap._fetch173('mint')::jsonb ->> 'door_session_id'));
SELECT tap._store173('secret', (tap._fetch173('mint')::jsonb ->> 'secret'));
SELECT ok((tap._fetch173('mint')::jsonb ->> 'secret') IS NOT NULL AND (tap._fetch173('mint')::jsonb ->> 'door_session_id') IS NOT NULL,
  'M1: a correct PIN mints a door session (door_session_id + one-time secret returned)');
-- the returned secret assert-verifies against the stored token_hash: the token
-- contract (md5('door_session:'||secret)) matches kernel.assert_door_session.
SELECT is((SELECT event_session_id::text FROM kernel.assert_door_session(
            tap._fetch173('dev')::uuid, tap._fetch173('sA')::uuid, tap._fetch173('dsid')::uuid, tap._fetch173('secret'))),
          tap._fetch173('sA'),
  'M2: assert_door_session accepts the minted secret and returns the bound session (token contract holds)');
SELECT throws_like(
  format($$SELECT venue.mint_door_session(%L,%L,%L,'WRONG-pin','ck173-m-wrongpin')$$, tap._fetch173('venue'), tap._fetch173('sA'), tap._fetch173('dev')),
  '%door_session_invalid%',
  'M3: a WRONG PIN is refused with the opaque door_session_invalid');
SELECT throws_like(
  format($$SELECT venue.mint_door_session(%L,%L,%L,'sekret-1234','ck173-m-wrongdev')$$, tap._fetch173('venue'), tap._fetch173('sA'), gen_random_uuid()::text),
  '%door_session_invalid%',
  'M4: a wrong/unknown device is refused with the SAME opaque error (no oracle)');
SELECT tap.logout();

-- re-mint (the /refresh path) revokes the prior active session for this device+session.
SELECT tap.login_service();
SELECT venue.mint_door_session(tap._fetch173('venue')::uuid, tap._fetch173('sA')::uuid, tap._fetch173('dev')::uuid, 'sekret-1234', 'ck173-m-remint');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM venue.door_session WHERE device_id=tap._fetch173('dev')::uuid AND event_session_id=tap._fetch173('sA')::uuid AND status='active'), 1,
  'M5: re-mint replaces the prior active session — at most one active per (device, session)');
SELECT is((SELECT count(*)::int FROM venue.door_session WHERE device_id=tap._fetch173('dev')::uuid AND event_session_id=tap._fetch173('sA')::uuid AND status='revoked' AND revoked_reason='reminted'), 1,
  'M6: the prior session was revoked with reason reminted');

-- rotate by revoke: revoking the PIN kills future mint (fail-closed).
SELECT tap.login(tap.seller());
SELECT venue.revoke_door_pin(tap._fetch173('pin')::uuid, 'ck173-pin-revoke');
SELECT tap.logout();
SELECT tap.login_service();
SELECT throws_like(
  format($$SELECT venue.mint_door_session(%L,%L,%L,'sekret-1234','ck173-m-afterrevoke')$$, tap._fetch173('venue'), tap._fetch173('sA'), tap._fetch173('dev')),
  '%door_session_invalid%',
  'M7: after the PIN is revoked, mint fails closed (rotation = revoke + recreate)');
SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;

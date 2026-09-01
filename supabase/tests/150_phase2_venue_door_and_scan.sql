-- ============================================================================
-- 150_phase2_venue_door_and_scan.sql — Phase-2 package 086 suite.
-- Frozen sources: plan §8/086 · schema §3.10-3.16/§10 · DOOR §7/§9/§10 · RPC
-- §1.1d/§9/§17.10-13/§20.6/§20.7.5 · RLS §11/§16.4a · DEMOGRAPHICS §10.2 ·
-- PFA-16/17/18A/24/25. Native scanning stays DARK; the signing-key lifecycle
-- (incl. revoke) is PARKED (PFA-18A). BEGIN … plan(N) … finish() … ROLLBACK.
-- ============================================================================
BEGIN;
SELECT plan(62);

SELECT tap.seed_core();

CREATE TABLE tap.memo_150 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store150(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_150 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch150(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_150 WHERE k=$1 $m$;
-- definer reads of deny-all / venue tables under superuser context
CREATE FUNCTION tap._dmcount(p_session uuid, p_status text) RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT count(*)::int FROM venue.door_manifest WHERE session_id=p_session AND status=p_status $m$;

-- ============================================================================
-- SECTION A — THE 086 CLOSED WORLD
-- ============================================================================
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='venue' AND c.relkind='r'), 20,
  'A1: venue holds 20 tables — 8 post-085 + the 12 door/scan tables');
SELECT has_table('venue'::name,'door_manifest'::name, 'A2: venue.door_manifest');
SELECT has_table('venue'::name,'door_manifest_entry'::name, 'A3: venue.door_manifest_entry (AO)');
SELECT has_table('venue'::name,'door_manifest_delta'::name, 'A4: venue.door_manifest_delta (AO)');
SELECT has_table('venue'::name,'scan'::name, 'A5: venue.scan (AO admission ledger)');
SELECT has_table('venue'::name,'door_session'::name, 'A6: venue.door_session (tokenized)');
SELECT has_table('venue'::name,'holder_mix_snapshot'::name, 'A7: venue.holder_mix_snapshot');
SELECT has_function('venue'::name,'open_door_manifest'::name, ARRAY['uuid','text','text']::name[], 'A8: open_door_manifest');
SELECT has_function('venue'::name,'get_door_manifest'::name, ARRAY['uuid','integer']::name[], 'A9: get_door_manifest (M2)');
SELECT has_function('venue'::name,'append_door_manifest_delta'::name, ARRAY['uuid','uuid[]','text','uuid']::name[],
  'A10: append_door_manifest_delta body (SEAM-2, signature frozen from 083)');
SELECT has_function('kernel'::name,'assert_door_session'::name, ARRAY['uuid','uuid','uuid','text']::name[],
  'A11: kernel.assert_door_session (token-bound, §1.1d)');
SELECT has_function('kernel'::name,'revoke_signing_key'::name, ARRAY['uuid','text','integer','text']::name[],
  'A12: kernel.revoke_signing_key authored HERE (PFA-17)');
SELECT hasnt_table('catalog'::name,'event_security_config'::name,
  'A13: PFA-25 — catalog.event_security_config is NOT built (forward obligation)');
SELECT hasnt_function('venue'::name,'set_event_security_config'::name, ARRAY['uuid','jsonb','text','text']::name[],
  'A14: PFA-25 — set_event_security_config is NOT built here');
SELECT hasnt_table('kernel'::name,'dispute_native'::name, 'A15: kernel.dispute_native is NOT here (088)');
SELECT is((SELECT count(*)::int FROM cron.job WHERE jobname LIKE '%door%' OR jobname LIKE '%holder-mix%'), 5,
  'A16: five door/holder-mix cron entries scheduled (P0-1)');

-- the ONE append-only base-snapshot ⇒ signing_key_id present, public_key ABSENT (PFA-24)
SELECT ok(EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='venue' AND table_name='door_manifest_entry' AND column_name='signing_key_id'),
  'A17: door_manifest_entry carries signing_key_id (the M1 join key)');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.columns
                       WHERE table_schema='venue' AND table_name IN ('door_manifest_entry','door_manifest_delta')
                         AND column_name = 'public_key'),
  'A18: PFA-24 — the manifest carries NO public_key (that is M1 = kernel.signing_key)');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.columns
                       WHERE table_schema='venue' AND table_name IN ('door_manifest_entry','door_manifest_delta')
                         AND column_name IN ('holder_identity_id','current_owner_id','owner_id')),
  'A19: the manifest carries NO holder identity (T-RPC-DOOR-17)');

-- ============================================================================
-- SECTION B — CUSTODY WALLS + AO
-- ============================================================================
SELECT ok(NOT has_column_privilege('authenticated','venue.door_pin','pin_hash','SELECT'),
  'B1: door_pin.pin_hash is not client-readable (C9)');
SELECT ok(NOT has_table_privilege('authenticated','venue.door_session','SELECT'),
  'B2: door_session is deny-all (audit-only, §16.4a) — no client read');
SELECT is((SELECT count(*)::int FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid
            JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='venue' AND c.relname='door_session'), 0,
  'B3: door_session carries ZERO policies');
SELECT ok(NOT has_function_privilege('authenticated','venue.mint_door_session(uuid,uuid,uuid,text,text)','EXECUTE')
       AND has_function_privilege('service_role','venue.mint_door_session(uuid,uuid,uuid,text,text)','EXECUTE'),
  'B4: mint_door_session is service_role-ONLY (the door edge)');
SELECT ok(NOT has_function_privilege('authenticated','kernel.assert_door_session(uuid,uuid,uuid,text)','EXECUTE')
       AND has_function_privilege('service_role','kernel.assert_door_session(uuid,uuid,uuid,text)','EXECUTE'),
  'B5: assert_door_session is service_role-ONLY');
SELECT ok((SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
            JOIN pg_proc p ON p.oid=t.tgfoid WHERE n.nspname='venue' AND c.relname='scan'
              AND p.proname='raise_append_only' AND NOT t.tgisinternal)=1,
  'B6: venue.scan is append-only (raise_append_only)');
SELECT ok((SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
            JOIN pg_proc p ON p.oid=t.tgfoid WHERE n.nspname='venue' AND c.relname='door_manifest_entry'
              AND p.proname='raise_append_only' AND NOT t.tgisinternal)=1,
  'B7: door_manifest_entry is append-only');
SELECT ok(NOT has_function_privilege('authenticated','venue.append_door_manifest_delta(uuid,uuid[],text,uuid)','EXECUTE')
       AND NOT has_function_privilege('service_role','venue.append_door_manifest_delta(uuid,uuid[],text,uuid)','EXECUTE'),
  'B8: append_door_manifest_delta is definer-internal — no client/machine grant');

-- ============================================================================
-- SECTION C — DARKNESS + PARKS
-- ============================================================================
SELECT is((SELECT (value #>> '{}')::text FROM catalog.platform_config WHERE key='feature.native_scanning_enabled' ORDER BY version DESC LIMIT 1),
  'false', 'C1: native scanning is DARK (078 seed)');
SELECT throws_ok($$SELECT kernel.revoke_signing_key(gen_random_uuid(),'compromise',0,'ck')$$,
  NULL, 'precondition_failed: dual_control_unavailable — credential dual-control mechanism not yet ratified (PFA-18A); signing-key revocation is parked, no key state changes and no episode is force-closed',
  'C2: PFA-18A — revoke_signing_key FAILS CLOSED (the trio''s third leg; same unbuildable dual control)');
SELECT is((SELECT count(*)::int FROM kernel.signing_key), 0, 'C3: …and it activated/changed no key (zero mutation)');

-- ============================================================================
-- FIXTURE — org → venue → event → session → tt → comp batch → active key → atoms
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._store150('org', (kernel.create_organization('Door Co','Door Co','ck86-o') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch150('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store150('venue', (catalog.create_venue(tap._fetch150('org')::uuid,'Door Hall','wynwood',NULL,'ck86-v') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch150('venue')::uuid,'approved','miami_gate','ck86-a');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._store150('event', (catalog.create_event(tap._fetch150('venue')::uuid,'Door Night',
  jsonb_build_object('starts_at',(now()+interval '10 days')::text,'ends_at',(now()+interval '10 days 5 hours')::text),'ck86-e') ->> 'event_id'));
SELECT tap._store150('session', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch150('event')::uuid));
-- a SECOND session whose door is NEVER opened — the D13 silent-no-op target.
SELECT tap._store150('session2', (catalog.create_event_session(tap._fetch150('event')::uuid,
  jsonb_build_object('starts_at',(now()+interval '11 days')::text,'ends_at',(now()+interval '11 days 4 hours')::text),'ck86-s2') ->> 'session_id'));
SELECT tap._store150('tt', (venue.create_ticket_type(tap._fetch150('event')::uuid,'admission','GA',5000,'public','ck86-tt') ->> 'ticket_type_id'));
SELECT tap._store150('batch', (venue.create_inventory_batch(tap._fetch150('tt')::uuid, tap._fetch150('session')::uuid, 'comp', 100, 0, 'ck86-b') ->> 'batch_id'));
SELECT tap.logout();
-- an active signing key + two minted atoms (the lifecycle is parked; the test inserts directly)
WITH insk AS (INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before)
  VALUES ('per_event', tap._fetch150('event')::uuid, 'PUBKEY-86', 'kms-86', 'active', now()) RETURNING key_id)
SELECT tap._store150('key', (SELECT key_id::text FROM insk));
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_issuance_enabled', 2, 'true'::jsonb, 'public');
SELECT tap._store150('mint', (kernel.issue_ticket_atoms(jsonb_build_object(
  'session_id',tap._fetch150('session')::uuid,'org_id',tap._fetch150('org')::uuid,'ticket_type_id',tap._fetch150('tt')::uuid,
  'batch_id',tap._fetch150('batch')::uuid,'owner_id',tap.buyer(),'quantity',2,'cause','comp',
  'cause_ref',gen_random_uuid(),'signing_key_id',tap._fetch150('key')::uuid),'ck86-mint') ->> 'status'));

-- ============================================================================
-- SECTION D — THE DOOR-MANIFEST ENGINE (open → snapshot → delta → get → close)
-- ============================================================================
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($$SELECT venue.open_door_manifest(%L,'doors','ck86-d-x')$$, tap._fetch150('session')),
  '42501', NULL, 'D1: a plain buyer cannot open a door episode');
SELECT tap.logout();
-- grant the seller venue_manager over the venue
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by)
VALUES (tap._fetch150('venue')::uuid, tap.seller(), 'venue_manager', tap.admin_user()) ON CONFLICT DO NOTHING;
SELECT tap.login(tap.seller());
SELECT tap._store150('mid', (venue.open_door_manifest(tap._fetch150('session')::uuid,'doors_open','ck86-d-1') ->> 'manifest_id'));
SELECT tap.logout();
SELECT is(tap._dmcount(tap._fetch150('session')::uuid, 'open'), 1, 'D2: exactly one OPEN episode after open');
SELECT is((SELECT entry_count FROM venue.door_manifest WHERE manifest_id=tap._fetch150('mid')::uuid), 2,
  'D3: the base snapshot captured both atoms');
SELECT is((SELECT count(*)::int FROM venue.door_manifest_entry WHERE manifest_id=tap._fetch150('mid')::uuid), 2,
  'D4: two door_manifest_entry rows (complete snapshot)');
SELECT ok((SELECT bool_and(signing_key_id = tap._fetch150('key')::uuid)
             FROM venue.door_manifest_entry WHERE manifest_id=tap._fetch150('mid')::uuid),
  'D5: every entry pins the signing_key_id (M1 join key; PFA-24)');
-- door_open_at engaged (the ledger head), == the manifest opened_at
SELECT ok((SELECT s.door_open_at IS NOT NULL FROM catalog.event_session s WHERE s.session_id=tap._fetch150('session')::uuid),
  'D6: first open engaged door_open_at (the freeze head)');
-- a second open is a noop_replay (partial-unique one-open-per-session)
SELECT tap.login(tap.seller());
SELECT is((venue.open_door_manifest(tap._fetch150('session')::uuid,'again','ck86-d-2') ->> 'status'), 'noop_replay',
  'D7: a second open returns the existing episode (≤1 open per session)');
SELECT tap.logout();
-- append a delta via a fresh comp issue (op=add) → the manifest tracks post-open mints
SELECT tap.login(tap.seller());
SELECT tap._store150('comp', (venue.allocate_comp(tap._fetch150('session')::uuid, tap._fetch150('batch')::uuid, 1, 'guest', 'ck86-c-1') ->> 'comp_allocation_id'));
SELECT is((venue.issue_comp(tap._fetch150('comp')::uuid, tap.buyer(), 1, 'ck86-c-2') ->> 'status'), 'ok',
  'D8: issue_comp mints a comp atom (cause=comp)');
SELECT tap.logout();
SELECT ok((SELECT count(*)::int FROM venue.door_manifest_delta WHERE manifest_id=tap._fetch150('mid')::uuid AND op='add') >= 1,
  'D9: …and the post-open mint appended an add delta (append_door_manifest_delta body)');
-- get_door_manifest (M2): entries + deltas, signing_key_id present, no public_key
SELECT tap.login(tap.seller());
SELECT tap._store150('m2', (venue.get_door_manifest(tap._fetch150('session')::uuid, 0))::text);
SELECT tap.logout();
SELECT is((tap._fetch150('m2')::jsonb ->> 'status'), 'ok', 'D10: get_door_manifest returns the open episode');
SELECT ok((tap._fetch150('m2')::jsonb -> 'entries' -> 0 ? 'signing_key_id')
       AND NOT ((tap._fetch150('m2')::jsonb)::text LIKE '%public_key%'),
  'D11: M2 carries signing_key_id and NEVER public_key (PFA-24)');
-- append a revoke delta directly (op=revoke, bare payload) via the SEAM body
SELECT (SELECT venue.append_door_manifest_delta(tap._fetch150('session')::uuid,
          ARRAY[(SELECT ticket_atom_id FROM venue.door_manifest_entry WHERE manifest_id=tap._fetch150('mid')::uuid LIMIT 1)],
          'revoke', gen_random_uuid()));
SELECT ok((SELECT count(*)::int FROM venue.door_manifest_delta WHERE manifest_id=tap._fetch150('mid')::uuid AND op='revoke')=1,
  'D12: a revoke delta appends (bare payload; MP-1 CHECKs satisfied)');
-- the SEAM body is a SILENT NO-OP when the target session has no open episode
-- (session2's door was never opened). op='add' + a random atom would trip the MP-1
-- payload CHECKs IF it reached the insert — it must NOT: no open episode ⇒ early
-- return (DOOR §7.7), so this lives.
SELECT lives_ok(format($$SELECT venue.append_door_manifest_delta(%L, ARRAY[gen_random_uuid()], 'add', gen_random_uuid())$$, tap._fetch150('session2')),
  'D13: append_door_manifest_delta on a session with no open episode is a silent no-op');
-- close
SELECT tap.login(tap.seller());
SELECT is((venue.close_door_manifest(tap._fetch150('session')::uuid,'doors_closed','ck86-d-3') ->> 'status'), 'ok', 'D14: close the episode');
SELECT is((venue.close_door_manifest(tap._fetch150('session')::uuid,'again','ck86-d-4') ->> 'status'), 'noop_replay', 'D15: closing with no open episode is a noop, never an error');
SELECT tap.logout();
SELECT is(tap._dmcount(tap._fetch150('session')::uuid, 'closed'), 1, 'D16: the episode is now closed (terminal)');
SELECT throws_ok(format($$UPDATE venue.door_manifest SET status='open' WHERE manifest_id=%L$$, tap._fetch150('mid')),
  'P0001', NULL, 'D17: a closed episode cannot reopen (guard)');
SELECT throws_ok(format($$DELETE FROM venue.door_manifest_entry WHERE manifest_id=%L$$, tap._fetch150('mid')),
  'P0001', NULL, 'D18: the base snapshot is append-only (no DELETE)');
-- door_open_at is immutable once engaged (ledger head)
SELECT throws_ok(format($$UPDATE catalog.event_session SET door_open_at = now()+interval '1 day' WHERE session_id=%L$$, tap._fetch150('session')),
  'P0001', NULL, 'D19: door_open_at is immutable once engaged (ledger-head trigger)');

-- ============================================================================
-- SECTION E — DOOR PIN + TOKENIZED SESSION (mint/assert/revoke; RV-1)
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._store150('pin', (venue.create_door_pin(tap._fetch150('venue')::uuid, tap._fetch150('session')::uuid, 'front', 'pin1234', now()+interval '1 day', 'ck86-p-1') ->> 'pin_id'));
SELECT tap._store150('dev', (venue.register_scan_device(tap._fetch150('venue')::uuid, 'scanner-1', 'ck86-dev-1') ->> 'device_id'));
SELECT tap.logout();
SELECT ok(NOT (SELECT pin_hash FROM venue.door_pin WHERE pin_id=tap._fetch150('pin')::uuid) = 'pin1234',
  'E1: the PIN is stored hashed, never in the clear');
-- mint a door session as service_role (the edge), assert it, then revoke the pin (RV-1)
SELECT tap.login_service();
SELECT tap._store150('mds', (venue.mint_door_session(tap._fetch150('venue')::uuid, tap._fetch150('session')::uuid, tap._fetch150('dev')::uuid, 'pin1234', 'ck86-ds-1'))::text);
SELECT tap.logout();
SELECT is((tap._fetch150('mds')::jsonb ->> 'status'), 'ok', 'E2: the door edge mints a session (service_role)');
SELECT tap._store150('dsid', (tap._fetch150('mds')::jsonb ->> 'door_session_id'));
SELECT tap._store150('dtok', (tap._fetch150('mds')::jsonb ->> 'session_token'));
SELECT tap.login_service();
SELECT is((SELECT event_session_id FROM kernel.assert_door_session(tap._fetch150('dev')::uuid, tap._fetch150('session')::uuid, tap._fetch150('dsid')::uuid, tap._fetch150('dtok'))),
  tap._fetch150('session')::uuid, 'E3: assert_door_session validates the token and returns the bound session');
SELECT throws_ok(format($$SELECT kernel.assert_door_session(%L,%L,%L,'wrong-token')$$,
    tap._fetch150('dev'), tap._fetch150('session'), tap._fetch150('dsid')),
  '42501', NULL, 'E4: a wrong token is rejected (opaque door_session_invalid)');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT is((venue.revoke_door_pin(tap._fetch150('pin')::uuid, 'ck86-p-2') ->> 'status'), 'ok', 'E5: the manager revokes the pin');
SELECT tap.logout();
SELECT is((SELECT status FROM venue.door_session WHERE door_session_id=tap._fetch150('dsid')::uuid), 'revoked',
  'E6: RV-1 — revoking the pin revoked its door session in the same txn');
SELECT tap.login_service();
SELECT throws_ok(format($$SELECT kernel.assert_door_session(%L,%L,%L,%L)$$,
    tap._fetch150('dev'), tap._fetch150('session'), tap._fetch150('dsid'), tap._fetch150('dtok')),
  '42501', NULL, 'E7: …and the revoked session no longer asserts');
SELECT tap.logout();

-- ============================================================================
-- SECTION F — SCAN (dark gate) + on_identity_erased_door (BP body)
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$SELECT venue.record_scan(%L,%L,%L,'{}'::jsonb,'ck86-s-1')$$,
    (SELECT ticket_atom_id FROM venue.door_manifest_entry WHERE manifest_id=tap._fetch150('mid')::uuid LIMIT 1),
    tap._fetch150('session'), tap._fetch150('dev')),
  NULL, 'precondition_failed: feature_disabled — native scanning is dark',
  'F1: record_scan is gated on native scanning (dark)');
SELECT tap.logout();
-- on_identity_erased_door scrubs the erased identity's comp grantee name
INSERT INTO venue.comp_allocation (event_session_id, batch_id, granted_to_identity, granted_to_name, quantity, granted_by)
VALUES (tap._fetch150('session')::uuid, tap._fetch150('batch')::uuid, tap.other_user(), 'Jane Doe', 1, tap.seller());
SELECT lives_ok(format($$SELECT kernel.on_identity_erased_door(%L)$$, tap.other_user()), 'F2: on_identity_erased_door runs (real body)');
SELECT is((SELECT granted_to_name FROM venue.comp_allocation WHERE granted_to_identity=tap.other_user()), NULL,
  'F3: …and it scrubbed the erased identity''s comp-grantee name (INV #29-#31)');

-- ============================================================================
-- SECTION G — HOLDER-MIX PRIVACY (deny-all; R2 sub-5 floor)
-- ============================================================================
SELECT ok(NOT has_table_privilege('authenticated','venue.holder_mix_snapshot','SELECT')
       AND NOT has_table_privilege('authenticated','venue.holder_mix_bucket','SELECT'),
  'G1: the holder-mix projection is deny-all (read only via get_holder_mix)');
SELECT throws_ok($$INSERT INTO venue.holder_mix_bucket (snapshot_id, bucket, holder_count)
    VALUES (gen_random_uuid(),'woman',3)$$, '23514', NULL,
  'G2: R2 floor — a sub-5 bucket count is physically UNSTORABLE (CHECK)');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.check_constraints cc
                       WHERE cc.constraint_schema='venue' AND cc.check_clause LIKE '%prefer_not_to_say%'),
  'G3: prefer_not_to_say is not a holder-mix bucket');

SELECT finish();
ROLLBACK;

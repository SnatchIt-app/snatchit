-- ============================================================================
-- 272_event_lifecycle_guards.sql — migration 20261102170000 (registry 203).
--
-- Registry 203 / pgTAP 272 — allocated by Claude A 2026-11-02 (cluster DB-5 of
-- D/TRACE-CONTRACTS-20261102.md; A's decisions for EL-03 and EL-04). DARK:
-- applied nowhere. 203 replaces two catalog bodies with their predecessors plus
-- ONE inserted block each:
--   catalog.cancel_event         refuses an event whose status is 'completed'
--     precondition_failed: event_completed — a completed event is not
--     cancelled; refunds after the event go through admin refunds
--   catalog.update_event_session refuses a session whose EVENT is 'completed'
--     or 'cancelled' with precondition_failed: event_terminal (the text
--     create_event_session / update_event raise for a terminal event).
-- Both checks sit after the authority check and before the first write.
--
--   Section A  shape: both bodies are 203's (md5(pg_get_functiondef)); still
--              postgres-owned SECURITY DEFINER plpgsql, search_path = '', jsonb;
--              ACL exactly owner + authenticated; one function per name; the two
--              venue_cmd wrappers (164) and the three sibling verbs untouched;
--              structurally, each guard sits after the authority refusal and
--              before the first write (update_event_session: after the
--              session_terminal check, which keeps answering first).
--   Section R  role checks on a non-terminal event are unchanged (42501).
--   Section K  cancel_event on draft / announced / on_sale / live still works;
--              the live event carries one atom with order lineage, so the
--              void+refund cascade is pinned end to end (atom voided, capacity
--              returned, one event_cancelled refund for the face value, event
--              and session cancelled, the event.cancel audit row).
--   Section X  a cancelled event stays the re-entrant noop_replay (a fixture
--              cancelled event and one cancelled in Section K), writing nothing.
--   Section S  update_event_session: live / on_sale sessions still edit; a
--              session of a completed event (fixture-written, and one completed
--              through publish_event live -> completed) and of a cancelled event
--              whose session is still scheduled answers event_terminal for the
--              manager, the owner, venue_marketing's label arm and the venue_cmd
--              wrapper — row and audit unchanged; a session that is itself
--              cancelled keeps answering session_terminal; scanner / fan keep
--              their 42501.
--   Section C  cancel_event on a completed event (with an issued atom that has
--              order lineage) answers event_completed for the manager, the owner
--              and the wrapper — nothing written (event / session status, atom,
--              capacity, refund, audit, outbox); the event completed through
--              publish_event answers the same; scanner / fan keep their 42501.
--
-- Fixture: 231 style (synthetic rows as postgres, fixed letter-bearing ids
-- a2720000-…, read back as each caller through tap.login, rolled back). Org A:
-- owner b1. Room V (Org A, approved): manager b2, scanner b3, marketing b4. Fan
-- b5. Buyer b6 holds the minted atoms. Session times are fixed instants in 2027.
-- The two atoms are minted by kernel.issue_ticket_atoms (cause 'issue', the
-- order item as cause_ref) under a per-event key inserted with the signing-key
-- insert guard disabled inside this transaction (the tap.seed_core plumbing).
-- Every positive-path call goes through tap._try272 (the returned text, or
-- 'ERROR <SQLSTATE>|<SQLERRM>'), so a wrongful refusal reads `not ok` instead of
-- aborting the file.
--
-- Expected on main 7496fee3 WITHOUT 203 (RED, predicted before the first run):
-- A1, A2, A8, A9 fail (predecessor md5s; no guard in either body); A3-A7 pass.
-- R1-R2, K1-K9, X1-X3 pass. S1-S3, S8a, S12-S14 pass; S4-S9 fail (the calls
-- succeed), S10-S11 fail (rows and audit written). C1-C3 fail (C1's call
-- succeeds and runs the cascade; C2/C3 then answer noop_replay), C4-C7 fail
-- (cancelled, voided, refunded, audited), C8 fails (succeeds); C9-C10 pass.
-- Predicted RED run: all 48 emitted (nothing aborts) = 28 ok + 20 not ok (the 20 named above).
-- ============================================================================
BEGIN;
SELECT plan(48);

CREATE TABLE tap.memo_272 (k text PRIMARY KEY, v text);
-- RETURNS void: a stored value must never reach the TAP stream. pg_prove's parser reads any output line
-- that starts with "ok" as a test result, so echoing K4's stored 'ok|1|1|0' counted a 49th test and threw
-- every later number out of sequence (CI run 41532350645 on f656c6da).
CREATE FUNCTION tap._store272(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_272 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v $m$;
CREATE FUNCTION tap._fetch272(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_272 WHERE k = $1 $m$;
-- the text a statement returns AS THE CALLER, or 'ERROR <SQLSTATE>|<SQLERRM>' — a wrongly refused
-- positive-path call reads `not ok` instead of aborting the file
CREATE FUNCTION tap._try272(q text) RETURNS text
LANGUAGE plpgsql AS
$m$ DECLARE v text; BEGIN EXECUTE q INTO v; RETURN v; EXCEPTION WHEN OTHERS THEN RETURN 'ERROR ' || SQLSTATE || '|' || SQLERRM; END $m$;
-- a session row's editable state plus its tuple id, for "the row is unchanged". updated_at is NOT used:
-- now() is frozen for the whole file's transaction, so a rewrite would leave it bit-identical; any
-- UPDATE of the row (even one writing the same values) gives the visible tuple a new ctid.
CREATE FUNCTION tap._ses272(p uuid) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT concat_ws('|', s.status, coalesce(s.session_label, '-'), s.starts_at, s.ends_at, coalesce(s.doors_at::text, '-'),
                     s.session_version, s.ctid)
      FROM catalog.event_session s WHERE s.session_id = p $m$;
GRANT EXECUTE ON FUNCTION tap._store272(text, text), tap._fetch272(text), tap._try272(text) TO authenticated;

-- ── Fixture (synthetic; never a migration) ─────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at)
SELECT u.id::uuid, repeat('0', 32)::uuid, 'authenticated', 'authenticated', u.email,
       '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()
  FROM (VALUES ('a2720000-0000-4000-a000-0000000000b1', 'owner.272@test.local'),
               ('a2720000-0000-4000-a000-0000000000b2', 'mgr.272@test.local'),
               ('a2720000-0000-4000-a000-0000000000b3', 'scan.272@test.local'),
               ('a2720000-0000-4000-a000-0000000000b4', 'mkt.272@test.local'),
               ('a2720000-0000-4000-a000-0000000000b5', 'fan.272@test.local'),
               ('a2720000-0000-4000-a000-0000000000b6', 'buyer.272@test.local')) AS u(id, email)
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('a2720000-0000-4000-a000-0000000000aa', 'Org A 272', 'Org A 272', 'active');
INSERT INTO kernel.org_member (org_id, identity_id, role) VALUES
  ('a2720000-0000-4000-a000-0000000000aa', 'a2720000-0000-4000-a000-0000000000b1', 'org_owner');
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status) VALUES
  ('a2720000-0000-4000-a000-0000000000c1', 'a2720000-0000-4000-a000-0000000000aa', 'Room V 272', 'wynwood', 'approved');
INSERT INTO venue.staff_role (venue_id, identity_id, role) VALUES
  ('a2720000-0000-4000-a000-0000000000c1', 'a2720000-0000-4000-a000-0000000000b2', 'venue_manager'),
  ('a2720000-0000-4000-a000-0000000000c1', 'a2720000-0000-4000-a000-0000000000b3', 'venue_scanner'),
  ('a2720000-0000-4000-a000-0000000000c1', 'a2720000-0000-4000-a000-0000000000b4', 'venue_marketing');
-- events: ed01 draft · ea01 announced · eb01 on_sale · ee01 live (cascade) · ee02 live (session edit)
-- · eb02 on_sale (session edit) · ef01 completed (atom; cancel) · ef02 live, completed in Section S
-- through publish_event · ef03 completed (session edit) · ec01 cancelled (session cancelled)
-- · ec02 cancelled with its session still scheduled (a fixture-written state)
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status)
SELECT ('a2720000-0000-4000-a000-00000000' || e.tag)::uuid, 'a2720000-0000-4000-a000-0000000000c1',
       'a2720000-0000-4000-a000-0000000000aa', e.tag || ' 272', e.status
  FROM (VALUES ('ed01', 'draft'), ('ea01', 'announced'), ('eb01', 'on_sale'), ('ee01', 'live'), ('ee02', 'live'),
               ('eb02', 'on_sale'), ('ef01', 'completed'), ('ef02', 'live'), ('ef03', 'completed'),
               ('ec01', 'cancelled'), ('ec02', 'cancelled')) AS e(tag, status);
INSERT INTO catalog.event_session (session_id, event_id, session_label, starts_at, ends_at, status)
SELECT ('a2720000-0000-4000-a000-00000000f' || substr(s.tag, 2))::uuid, ('a2720000-0000-4000-a000-00000000' || s.tag)::uuid,
       NULL, s.starts::timestamptz, s.starts::timestamptz + interval '5 hours', s.status
  FROM (VALUES ('ed01', '2027-03-01 01:00:00+00', 'scheduled'), ('ea01', '2027-03-02 01:00:00+00', 'scheduled'),
               ('eb01', '2027-03-03 01:00:00+00', 'scheduled'), ('ee01', '2027-03-04 01:00:00+00', 'live'),
               ('ee02', '2027-03-05 01:00:00+00', 'live'),      ('eb02', '2027-03-06 01:00:00+00', 'scheduled'),
               ('ef01', '2027-03-07 01:00:00+00', 'scheduled'), ('ef02', '2027-03-08 01:00:00+00', 'scheduled'),
               ('ef03', '2027-03-09 01:00:00+00', 'scheduled'), ('ec01', '2027-03-10 01:00:00+00', 'cancelled'),
               ('ec02', '2027-03-11 01:00:00+00', 'scheduled')) AS s(tag, starts, status);
-- one tier + one public batch on the live event ee01 and on the completed event ef01
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility) VALUES
  ('a2720000-0000-4000-a000-0000000000d1', 'a2720000-0000-4000-a000-00000000ee01', 'admission', 'GA ee01 272', 5000, 'public'),
  ('a2720000-0000-4000-a000-0000000000d2', 'a2720000-0000-4000-a000-00000000ef01', 'admission', 'GA ef01 272', 4000, 'public');
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity) VALUES
  ('a2720000-0000-4000-a000-0000000000e1', 'a2720000-0000-4000-a000-0000000000d1', 'a2720000-0000-4000-a000-00000000fe01', 'public_sale', 10),
  ('a2720000-0000-4000-a000-0000000000e2', 'a2720000-0000-4000-a000-0000000000d2', 'a2720000-0000-4000-a000-00000000ff01', 'public_sale', 10);
-- the order triple venue.finalize_primary_order leaves behind (order + payments + payment_native) + the item
-- (items are written while the order is pending — order_item is append-only once the order is issued)
INSERT INTO venue."order" (order_id, buyer_id, event_session_id, org_id, status, source, total_minor, currency, command_idempotency_key) VALUES
  ('a2720000-0000-4000-a000-0000000000a1', 'a2720000-0000-4000-a000-0000000000b6', 'a2720000-0000-4000-a000-00000000fe01', 'a2720000-0000-4000-a000-0000000000aa', 'pending', 'app', 5000, 'USD', 'ck272-order-1'),
  ('a2720000-0000-4000-a000-0000000000a2', 'a2720000-0000-4000-a000-0000000000b6', 'a2720000-0000-4000-a000-00000000ff01', 'a2720000-0000-4000-a000-0000000000aa', 'pending', 'app', 4000, 'USD', 'ck272-order-2');
INSERT INTO venue.order_item (id, order_id, ticket_type_id, quantity, unit_price_minor) VALUES
  ('a2720000-0000-4000-a000-0000000000a3', 'a2720000-0000-4000-a000-0000000000a1', 'a2720000-0000-4000-a000-0000000000d1', 1, 5000),
  ('a2720000-0000-4000-a000-0000000000a4', 'a2720000-0000-4000-a000-0000000000a2', 'a2720000-0000-4000-a000-0000000000d2', 1, 4000);
UPDATE venue."order" SET status = 'paid'
 WHERE order_id IN ('a2720000-0000-4000-a000-0000000000a1', 'a2720000-0000-4000-a000-0000000000a2');
INSERT INTO public.payments (id, buyer_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at) VALUES
  ('a2720000-0000-4000-a000-0000000000a5', 'a2720000-0000-4000-a000-0000000000b6', 5000, 500, 0, 5500, 'pi_test_272_one', 'succeeded', 'native_primary', now()),
  ('a2720000-0000-4000-a000-0000000000a6', 'a2720000-0000-4000-a000-0000000000b6', 4000, 400, 0, 4400, 'pi_test_272_two', 'succeeded', 'native_primary', now());
INSERT INTO kernel.payment_native (payment_id, order_id, amount_minor, currency) VALUES
  ('a2720000-0000-4000-a000-0000000000a5', 'a2720000-0000-4000-a000-0000000000a1', 5500, 'USD'),
  ('a2720000-0000-4000-a000-0000000000a6', 'a2720000-0000-4000-a000-0000000000a2', 4400, 'USD');
-- mint one atom per order (issuance flag on, a per-event key per event; rolled back with the file)
ALTER TABLE kernel.signing_key DISABLE TRIGGER tg_signing_key_insert_guard;
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'feature.native_issuance_enabled', coalesce(max(c.version), 0) + 1, 'true'::jsonb, 'public'
  FROM catalog.platform_config c WHERE c.key = 'feature.native_issuance_enabled';
INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm) VALUES
  ('per_event', 'a2720000-0000-4000-a000-00000000ee01', 'PUBKEY-272-ee01', 'kms-272-ee01', 'active', now() - interval '1 minute', 'ES256'),
  ('per_event', 'a2720000-0000-4000-a000-00000000ef01', 'PUBKEY-272-ef01', 'kms-272-ef01', 'active', now() - interval '1 minute', 'ES256');
SELECT tap._store272('mint1', kernel.issue_ticket_atoms(jsonb_build_object(
  'session_id', 'a2720000-0000-4000-a000-00000000fe01', 'org_id', 'a2720000-0000-4000-a000-0000000000aa',
  'ticket_type_id', 'a2720000-0000-4000-a000-0000000000d1', 'batch_id', 'a2720000-0000-4000-a000-0000000000e1',
  'owner_id', 'a2720000-0000-4000-a000-0000000000b6', 'quantity', 1, 'cause', 'issue',
  'cause_ref', 'a2720000-0000-4000-a000-0000000000a3'), 'ck272-mint-1') #>> '{atom_ids,0}');
SELECT tap._store272('mint2', kernel.issue_ticket_atoms(jsonb_build_object(
  'session_id', 'a2720000-0000-4000-a000-00000000ff01', 'org_id', 'a2720000-0000-4000-a000-0000000000aa',
  'ticket_type_id', 'a2720000-0000-4000-a000-0000000000d2', 'batch_id', 'a2720000-0000-4000-a000-0000000000e2',
  'owner_id', 'a2720000-0000-4000-a000-0000000000b6', 'quantity', 1, 'cause', 'issue',
  'cause_ref', 'a2720000-0000-4000-a000-0000000000a4'), 'ck272-mint-2') #>> '{atom_ids,0}');

-- ── Section A — shape ───────────────────────────────────────────────────────
SELECT is(md5(pg_get_functiondef(to_regprocedure('catalog.cancel_event(uuid,text,text)'))),
  'b23e3dc88e9bb1a3e9c1b84c8626e0f4', 'A1: catalog.cancel_event carries 203''s body (088 + the event_completed guard)');
SELECT is(md5(pg_get_functiondef(to_regprocedure('catalog.update_event_session(uuid,jsonb,text)'))),
  '8b84fb6007d3ee1bb0fb9e488e6d4e41', 'A2: catalog.update_event_session carries 203''s body (165 + the event_terminal guard)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
            WHERE n.nspname = 'catalog' AND p.prosecdef AND l.lanname = 'plpgsql'
              AND 'search_path=""' = ANY (coalesce(p.proconfig, '{}'))
              AND p.proowner = 'postgres'::regrole AND pg_get_function_result(p.oid) = 'jsonb'
              AND p.proname IN ('cancel_event','update_event_session')), 2,
  'A3: both are still postgres-owned SECURITY DEFINER plpgsql bodies with search_path = '''' returning jsonb');
SELECT set_eq(
  $$ SELECT p.proname || ':' || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      WHERE n.nspname = 'catalog' AND p.proname IN ('cancel_event','update_event_session') $$,
  $$ VALUES ('cancel_event:postgres:EXECUTE'), ('cancel_event:authenticated:EXECUTE'),
            ('update_event_session:postgres:EXECUTE'), ('update_event_session:authenticated:EXECUTE') $$,
  'A4: both ACLs are unchanged — exactly owner (postgres) + authenticated; anon / service_role / PUBLIC hold none');
SELECT is((SELECT string_agg(p.proname || '(' || pg_catalog.oidvectortypes(p.proargtypes) || ')', ', ' ORDER BY p.proname)
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'catalog' AND p.proname IN ('cancel_event','update_event_session')),
  'cancel_event(uuid, text, text), update_event_session(uuid, jsonb, text)',
  'A5: one function per name — same signatures, no overload added');
SELECT is((SELECT string_agg(p.proname || '=' || md5(p.prosrc) || ':' || p.prosecdef::text, ' ' ORDER BY p.proname)
             FROM pg_proc p WHERE p.pronamespace = 'venue_cmd'::regnamespace AND p.proname IN ('cancel_event','update_event_session')),
  'cancel_event=09b321729670af3113ea22babf02b329:false update_event_session=8f8eeaca4d1d74c805e123ef90b8e340:false',
  'A6: the venue_cmd wrappers (164) are untouched and still SECURITY INVOKER — they route to the two bodies');
SELECT is((SELECT string_agg(p.proname || '=' || md5(p.prosrc), ' ' ORDER BY p.proname)
             FROM pg_proc p WHERE p.pronamespace = 'catalog'::regnamespace
              AND p.proname IN ('create_event_session','update_event','publish_event')),
  'create_event_session=ee243b12a8b51c7692a8f6ed22506a34 publish_event=b31abddf9aad2cb7b119d517424bb494 update_event=1bf2a04bf1ffccfdbed04d8b067dd2df',
  'A7: the sibling verbs (165''s create_event_session / update_event / publish_event) are untouched by 203');
SELECT ok((SELECT position('insufficient_privilege: org_owner / org_admin / venue_manager' in p.prosrc) > 0
              AND position('insufficient_privilege: org_owner / org_admin / venue_manager' in p.prosrc)
                < position('for update;              -- rank 1' in p.prosrc)
              AND position('for update;              -- rank 1' in p.prosrc)
                < position('precondition_failed: event_completed' in p.prosrc)
              AND position('precondition_failed: event_completed' in p.prosrc)
                < position('for v_s in select es.session_id' in p.prosrc)
              AND p.prosrc LIKE '%if v_e.status = ''completed'' then%raise exception ''precondition_failed: event_completed%'
             FROM pg_proc p WHERE p.oid = to_regprocedure('catalog.cancel_event(uuid,text,text)')),
  'A8: cancel_event — the event_completed guard tests status = ''completed'' on the row read under the rank-1 lock, after the authority refusal and before the session loop (its first write)');
SELECT ok((SELECT position('precondition_failed: session_terminal' in p.prosrc) > 0
              AND position('precondition_failed: session_terminal' in p.prosrc)
                < position('insufficient_privilege: venue_manager or org_owner/org_admin required' in p.prosrc)
              AND position('insufficient_privilege: venue_manager or org_owner/org_admin required' in p.prosrc)
                < position('precondition_failed: event_terminal' in p.prosrc)
              AND position('precondition_failed: event_terminal' in p.prosrc)
                < position('update catalog.event_session' in p.prosrc)
              AND p.prosrc ~ 'e\.status in \(''completed'',''cancelled''\)\) then\s+raise exception ''precondition_failed: event_terminal'';'
             FROM pg_proc p WHERE p.oid = to_regprocedure('catalog.update_event_session(uuid,jsonb,text)')),
  'A9: update_event_session — the event_terminal guard covers completed and cancelled, after session_terminal and the authority refusal, before the first update of the row');

-- ── Section R — role checks on a non-terminal event are unchanged ───────────
SELECT tap.login('a2720000-0000-4000-a000-0000000000b3');
SELECT throws_ok($$SELECT catalog.cancel_event('a2720000-0000-4000-a000-00000000eb01', 'weather', 'ck272-r-1')$$,
  '42501', 'insufficient_privilege: org_owner / org_admin / venue_manager (current operator) / platform_admin only',
  'R1: a venue_scanner still cannot cancel an on_sale event (088''s 42501, unchanged)');
SELECT throws_ok($$SELECT catalog.update_event_session('a2720000-0000-4000-a000-00000000fe02', '{"session_label":"scanner"}', 'ck272-r-2')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required',
  'R2: a venue_scanner still cannot edit a live event''s session (165''s 42501, unchanged)');
SELECT tap.logout();

-- ── Section K — cancel_event on draft / announced / on_sale / live still works ─
SELECT tap.login('a2720000-0000-4000-a000-0000000000b2');
SELECT is(tap._try272($$SELECT catalog.cancel_event('a2720000-0000-4000-a000-00000000ed01', 'weather', 'ck272-k-1') ->> 'status'$$), 'ok',
  'K1: the manager cancels a draft event (unchanged)');
SELECT tap.logout();
SELECT tap.login('a2720000-0000-4000-a000-0000000000b1');
SELECT is(tap._try272($$SELECT catalog.cancel_event('a2720000-0000-4000-a000-00000000ea01', 'weather', 'ck272-k-2') ->> 'status'$$), 'ok',
  'K2: the org owner cancels an announced event (unchanged)');
SELECT tap.logout();
SELECT tap.login('a2720000-0000-4000-a000-0000000000b2');
SELECT is(tap._try272($$SELECT venue_cmd.cancel_event('a2720000-0000-4000-a000-00000000eb01', 'weather', 'ck272-k-3') ->> 'status'$$), 'ok',
  'K3: the manager cancels an on_sale event through the venue_cmd wrapper (unchanged)');
-- the result is projected inside the value helper, so a refused call stores 'ERROR …' text (no json cast to abort on)
SELECT tap._store272('k4', tap._try272($$SELECT (j ->> 'status') || '|' || (j ->> 'atoms_voided') || '|' || (j ->> 'refunds_created') || '|' || (j ->> 'atoms_skipped')
                                           FROM (SELECT catalog.cancel_event('a2720000-0000-4000-a000-00000000ee01', 'weather', 'ck272-k-4') AS j) x$$));
SELECT tap.logout();
SELECT is(tap._fetch272('k4'),
  'ok|1|1|0', 'K4: the manager cancels a LIVE event — the cascade runs: 1 atom voided, 1 refund, 0 skipped');
SELECT is((SELECT t.state FROM kernel.tickets t WHERE t.ticket_atom_id = tap._fetch272('mint1')::uuid)
          || '|' || (SELECT b.sold::text FROM venue.inventory_batch b WHERE b.batch_id = 'a2720000-0000-4000-a000-0000000000e1'),
  'voided|0', 'K5: …the live event''s atom is voided and its capacity returned');
SELECT is((SELECT string_agg(r.reason_code || '|' || r.amount_minor || '|' || r.currency || '|' || r.status || '|' || r.idempotency_key, ',')
             FROM kernel.refund r WHERE r.payment_id = 'a2720000-0000-4000-a000-0000000000a5'),
  'event_cancelled|5000|USD|pending|ck272-k-4:order:a2720000-0000-4000-a000-0000000000a1',
  'K6: …one pending event_cancelled refund of the face value, keyed on the order');
SELECT is((SELECT e.status FROM catalog.event e WHERE e.event_id = 'a2720000-0000-4000-a000-00000000ee01')
          || '|' || (SELECT s.status FROM catalog.event_session s WHERE s.session_id = 'a2720000-0000-4000-a000-00000000fe01'),
  'cancelled|cancelled', 'K7: …the live event and its session are cancelled');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit a
            WHERE a.action = 'event.cancel' AND a.subject_id = 'a2720000-0000-4000-a000-00000000ee01'
              AND a.before ->> 'status' = 'live' AND a.after ->> 'atoms_voided' = '1'), 1,
  'K8: …and one event.cancel audit row records live -> cancelled with the voided count');
SELECT is((SELECT string_agg(e.status, ',' ORDER BY e.event_id) FROM catalog.event e
            WHERE e.event_id IN ('a2720000-0000-4000-a000-00000000ed01', 'a2720000-0000-4000-a000-00000000ea01', 'a2720000-0000-4000-a000-00000000eb01')),
  'cancelled,cancelled,cancelled', 'K9: the draft, announced and on_sale events are cancelled');

-- ── Section X — a cancelled event stays the re-entrant noop_replay ──────────
SELECT tap.login('a2720000-0000-4000-a000-0000000000b2');
SELECT is(tap._try272($$SELECT catalog.cancel_event('a2720000-0000-4000-a000-00000000ec01', 'weather', 'ck272-x-1') ->> 'status'$$), 'noop_replay',
  'X1: cancelling an already cancelled event answers noop_replay (unchanged)');
SELECT tap.logout();
SELECT tap.login('a2720000-0000-4000-a000-0000000000b1');
SELECT is(tap._try272($$SELECT catalog.cancel_event('a2720000-0000-4000-a000-00000000ed01', 'weather', 'ck272-x-2') ->> 'status'$$), 'noop_replay',
  'X2: re-running a cancel on the event cancelled in K1 answers noop_replay (unchanged)');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM kernel.admin_audit a WHERE a.subject_id = 'a2720000-0000-4000-a000-00000000ec01')
          + (SELECT count(*)::int FROM kernel.admin_audit a WHERE a.subject_id = 'a2720000-0000-4000-a000-00000000ed01'), 1,
  'X3: the replays wrote no audit row (only K1''s event.cancel row exists)');

-- ── Section S — update_event_session ───────────────────────────────────────
SELECT tap._store272('ses_ff03', tap._ses272('a2720000-0000-4000-a000-00000000ff03'));
SELECT tap._store272('ses_fc02', tap._ses272('a2720000-0000-4000-a000-00000000fc02'));
SELECT tap.login('a2720000-0000-4000-a000-0000000000b2');
SELECT is(tap._try272($$SELECT catalog.update_event_session('a2720000-0000-4000-a000-00000000fe02', '{"session_label":"live relabel"}', 'ck272-s-1') ->> 'status'$$), 'ok',
  'S1: the manager still relabels a session of a LIVE event');
SELECT is(tap._try272($$SELECT catalog.update_event_session('a2720000-0000-4000-a000-00000000fb02', '{"starts_at":"2027-03-06T02:00:00Z"}', 'ck272-s-2') ->> 'status'$$), 'ok',
  'S2: the manager still moves a session of an ON_SALE event');
SELECT tap.logout();
SELECT is((SELECT s.starts_at = '2027-03-06 02:00:00+00'::timestamptz AND s.session_version = 2
             FROM catalog.event_session s WHERE s.session_id = 'a2720000-0000-4000-a000-00000000fb02'), true,
  'S3: …the move is stored and session_version is bumped');
SELECT tap.login('a2720000-0000-4000-a000-0000000000b2');
SELECT throws_ok($$SELECT catalog.update_event_session('a2720000-0000-4000-a000-00000000ff03', '{"starts_at":"2027-03-09T02:00:00Z"}', 'ck272-s-4')$$,
  'P0001', 'precondition_failed: event_terminal', 'S4: the manager cannot move a session of a COMPLETED event — event_terminal');
SELECT tap.logout();
SELECT tap.login('a2720000-0000-4000-a000-0000000000b1');
SELECT throws_ok($$SELECT catalog.update_event_session('a2720000-0000-4000-a000-00000000ff03', '{"session_label":"late label"}', 'ck272-s-5')$$,
  'P0001', 'precondition_failed: event_terminal', 'S5: the org owner cannot relabel it either — event_terminal');
SELECT tap.logout();
SELECT tap.login('a2720000-0000-4000-a000-0000000000b4');
SELECT throws_ok($$SELECT catalog.update_event_session('a2720000-0000-4000-a000-00000000ff03', '{"session_label":"mkt label"}', 'ck272-s-6')$$,
  'P0001', 'precondition_failed: event_terminal', 'S6: venue_marketing''s label-only arm is admitted, then refused — event_terminal');
SELECT tap.logout();
SELECT tap.login('a2720000-0000-4000-a000-0000000000b2');
SELECT throws_ok($$SELECT venue_cmd.update_event_session('a2720000-0000-4000-a000-00000000ff03', '{"session_label":"wrapper label"}', 'ck272-s-7')$$,
  'P0001', 'precondition_failed: event_terminal', 'S7: the venue_cmd wrapper answers the body''s event_terminal');
SELECT is(tap._try272($$SELECT catalog.publish_event('a2720000-0000-4000-a000-00000000ef02', 'completed', 'ck272-s-8a') ->> 'event_status'$$), 'completed',
  'S8a: the manager completes a live event through publish_event (live -> completed; its session stays scheduled)');
SELECT tap.logout();
SELECT tap._store272('ses_ff02', tap._ses272('a2720000-0000-4000-a000-00000000ff02'));
SELECT tap.login('a2720000-0000-4000-a000-0000000000b2');
SELECT throws_ok($$SELECT catalog.update_event_session('a2720000-0000-4000-a000-00000000ff02', '{"session_label":"after the night"}', 'ck272-s-8')$$,
  'P0001', 'precondition_failed: event_terminal', 'S8: …and its session is no longer editable — event_terminal');
SELECT throws_ok($$SELECT catalog.update_event_session('a2720000-0000-4000-a000-00000000fc02', '{"session_label":"revived"}', 'ck272-s-9')$$,
  'P0001', 'precondition_failed: event_terminal', 'S9: a still-scheduled session of a CANCELLED event — event_terminal');
SELECT tap.logout();
SELECT is(tap._ses272('a2720000-0000-4000-a000-00000000ff03') || ' / ' || tap._ses272('a2720000-0000-4000-a000-00000000ff02')
          || ' / ' || tap._ses272('a2720000-0000-4000-a000-00000000fc02'),
  tap._fetch272('ses_ff03') || ' / ' || tap._fetch272('ses_ff02') || ' / ' || tap._fetch272('ses_fc02'),
  'S10: the three refused sessions are unchanged (status, label, times, session_version, tuple id)');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit a
            WHERE a.action = 'session.update'
              AND a.subject_id IN ('a2720000-0000-4000-a000-00000000ff03', 'a2720000-0000-4000-a000-00000000ff02', 'a2720000-0000-4000-a000-00000000fc02')), 0,
  'S11: …and no session.update audit row was written for them');
SELECT tap.login('a2720000-0000-4000-a000-0000000000b2');
SELECT throws_ok($$SELECT catalog.update_event_session('a2720000-0000-4000-a000-00000000fd01', '{"session_label":"revived"}', 'ck272-s-12')$$,
  'P0001', 'precondition_failed: session_terminal', 'S12: a session that is itself cancelled (K1''s cancel) keeps answering session_terminal, checked first (unchanged)');
SELECT tap.logout();
SELECT tap.login('a2720000-0000-4000-a000-0000000000b3');
SELECT throws_ok($$SELECT catalog.update_event_session('a2720000-0000-4000-a000-00000000ff03', '{"session_label":"scanner"}', 'ck272-s-13')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required',
  'S13: a venue_scanner on a completed event''s session keeps its 42501 (the guard is after authority)');
SELECT tap.logout();
SELECT tap.login('a2720000-0000-4000-a000-0000000000b5');
SELECT throws_ok($$SELECT catalog.update_event_session('a2720000-0000-4000-a000-00000000ff03', '{"session_label":"fan"}', 'ck272-s-14')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required',
  'S14: a fan on a completed event''s session keeps its 42501');
SELECT tap.logout();

-- ── Section C — cancel_event on a completed event ───────────────────────────
SELECT tap._store272('ev_ef01', (SELECT e.status || '|' || e.ctid FROM catalog.event e WHERE e.event_id = 'a2720000-0000-4000-a000-00000000ef01'));
SELECT tap._store272('ses_ff01', tap._ses272('a2720000-0000-4000-a000-00000000ff01'));
SELECT tap.login('a2720000-0000-4000-a000-0000000000b2');
SELECT throws_ok($$SELECT catalog.cancel_event('a2720000-0000-4000-a000-00000000ef01', 'weather', 'ck272-c-1')$$,
  'P0001', 'precondition_failed: event_completed — a completed event is not cancelled; refunds after the event go through admin refunds',
  'C1: the manager cannot cancel a COMPLETED event — event_completed');
SELECT tap.logout();
SELECT tap.login('a2720000-0000-4000-a000-0000000000b1');
SELECT throws_ok($$SELECT catalog.cancel_event('a2720000-0000-4000-a000-00000000ef01', 'weather', 'ck272-c-2')$$,
  'P0001', 'precondition_failed: event_completed — a completed event is not cancelled; refunds after the event go through admin refunds',
  'C2: the org owner cannot either — event_completed');
SELECT tap.logout();
SELECT tap.login('a2720000-0000-4000-a000-0000000000b2');
SELECT throws_ok($$SELECT venue_cmd.cancel_event('a2720000-0000-4000-a000-00000000ef01', 'weather', 'ck272-c-3')$$,
  'P0001', 'precondition_failed: event_completed — a completed event is not cancelled; refunds after the event go through admin refunds',
  'C3: the venue_cmd wrapper answers the body''s event_completed');
SELECT tap.logout();
SELECT is((SELECT e.status || '|' || e.ctid FROM catalog.event e WHERE e.event_id = 'a2720000-0000-4000-a000-00000000ef01')
          || ' / ' || tap._ses272('a2720000-0000-4000-a000-00000000ff01'),
  tap._fetch272('ev_ef01') || ' / ' || tap._fetch272('ses_ff01'),
  'C4: nothing written — the completed event and its session are unchanged (status, fields, tuple ids)');
SELECT is((SELECT t.state FROM kernel.tickets t WHERE t.ticket_atom_id = tap._fetch272('mint2')::uuid)
          || '|' || (SELECT b.sold::text FROM venue.inventory_batch b WHERE b.batch_id = 'a2720000-0000-4000-a000-0000000000e2'),
  'active|1', 'C5: …its atom is still active and its capacity still sold (no void)');
SELECT is((SELECT count(*)::int FROM kernel.refund r WHERE r.payment_id = 'a2720000-0000-4000-a000-0000000000a6'), 0,
  'C6: …no refund row for its order''s payment');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit a
            WHERE a.subject_id IN ('a2720000-0000-4000-a000-00000000ef01', 'a2720000-0000-4000-a000-0000000000a2', tap._fetch272('mint2')::uuid))
          + (SELECT count(*)::int FROM notify.outbox o WHERE o.aggregate_id = 'a2720000-0000-4000-a000-00000000ef01'), 0,
  'C7: …no audit row (event.cancel / event.cancel_skip) and no outbox event for it');
SELECT tap.login('a2720000-0000-4000-a000-0000000000b2');
SELECT throws_ok($$SELECT catalog.cancel_event('a2720000-0000-4000-a000-00000000ef02', 'weather', 'ck272-c-8')$$,
  'P0001', 'precondition_failed: event_completed — a completed event is not cancelled; refunds after the event go through admin refunds',
  'C8: the event completed through publish_event (S8a) cannot be cancelled either — event_completed');
SELECT tap.logout();
SELECT tap.login('a2720000-0000-4000-a000-0000000000b3');
SELECT throws_ok($$SELECT catalog.cancel_event('a2720000-0000-4000-a000-00000000ef01', 'weather', 'ck272-c-9')$$,
  '42501', 'insufficient_privilege: org_owner / org_admin / venue_manager (current operator) / platform_admin only',
  'C9: a venue_scanner on a completed event keeps its 42501 (the guard is after authority)');
SELECT tap.logout();
SELECT tap.login('a2720000-0000-4000-a000-0000000000b5');
SELECT throws_ok($$SELECT catalog.cancel_event('a2720000-0000-4000-a000-00000000ef01', 'weather', 'ck272-c-10')$$,
  '42501', 'insufficient_privilege: org_owner / org_admin / venue_manager (current operator) / platform_admin only',
  'C10: a fan on a completed event keeps its 42501');
SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;

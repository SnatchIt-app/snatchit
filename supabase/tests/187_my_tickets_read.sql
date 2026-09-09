-- ============================================================================
-- 187_my_tickets_read.sql — package 20260909000000 suite (Tickets ownership read).
-- RENUMBERED 2026-09-09 from 176_: the production-aligned admin/native line already
-- owns 176_signing_key_insert_guard.sql (the contiguous 176-186 block covers
-- migrations 110-120). 187 is the next free number and is also the correct order:
-- 20260909000000 is the last migration in the chain. Coverage is unchanged.
--
-- Proves public.get_my_tickets(): owner-scoped by construction (no arguments,
-- binds to auth.uid()), event-first grouped projection, stable vocabularies,
-- defined empty state, fail-closed auth, and no sensitive columns.
--
-- Fixtures: kernel parent chain (org -> venue -> event -> session ->
-- ticket_type -> signing_key -> tickets) is INSERTed directly as the test's
-- superuser session. kernel.tickets' custody-head check is a DEFERRABLE
-- INITIALLY DEFERRED constraint trigger (079) that fires at COMMIT; this file
-- is BEGIN...ROLLBACK, so staging read-fixtures needs no ledger rows.
-- Convention: BEGIN ... plan(N) ... finish() ... ROLLBACK.
-- ============================================================================
BEGIN;
SELECT plan(20);

SELECT tap.seed_core();  -- auth.users personas (buyer / other_user / admin / seller)

-- ---------------------------------------------------------------------------
-- SECTION A — shape, security, grants (no fixtures needed)
-- ---------------------------------------------------------------------------
SELECT has_function('public'::name, 'get_my_tickets'::name, '{}'::name[],
  'A1: public.get_my_tickets() exists and takes no arguments');

SELECT ok((SELECT p.prosecdef FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = 'get_my_tickets'),
  'A2: it is SECURITY DEFINER');

SELECT ok((SELECT array_to_string(p.proconfig, ',') LIKE '%search_path=%'
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = 'get_my_tickets'),
  'A3: it pins an explicit search_path');

SELECT ok(has_function_privilege('authenticated', 'public.get_my_tickets()', 'EXECUTE'),
  'A4: authenticated may EXECUTE');

SELECT ok(NOT has_function_privilege('anon', 'public.get_my_tickets()', 'EXECUTE'),
  'A5: anon has NO EXECUTE (fail closed at the ACL)');

SELECT ok(
  NOT ((SELECT p.proargnames FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'get_my_tickets')
       && ARRAY['current_owner_id','serial_no','org_id','signing_key_id',
                'credential_version','unit_row_id','external_seat_ref','seat_ref',
                'price_minor','currency','kms_handle_ref','stripe_connect_account_ref']::text[]),
  'A6: projection exposes NO sensitive columns (owner id / serial / signing / payment / credential)');

SELECT ok(
  (SELECT p.proargnames FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'get_my_tickets')
  @> ARRAY['event_title','starts_at','venue_name','artwork_ref','ticket_type_name',
           'quantity','ownership_status','fulfillment_status','time_class']::text[],
  'A7: projection carries every required event-first field');

-- ---------------------------------------------------------------------------
-- Fixtures — kernel parent chain (as superuser session)
-- ---------------------------------------------------------------------------
INSERT INTO kernel.organization (org_id, legal_name, display_name, status)
VALUES ('dddddddd-0000-0000-0000-000000000001', 'Fixture Org', 'Fixture Org', 'active');

INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status)
VALUES ('dddddddd-0000-0000-0000-000000000002', 'dddddddd-0000-0000-0000-000000000001',
        'Bass Hall', 'wynwood', 'approved');

INSERT INTO catalog.event (event_id, venue_id, org_id, title, status, hero_image_ref) VALUES
  ('dddddddd-0000-0000-0000-00000000000a', 'dddddddd-0000-0000-0000-000000000002',
   'dddddddd-0000-0000-0000-000000000001', 'Neon Night',  'on_sale',   'events/neon.jpg'),
  ('dddddddd-0000-0000-0000-00000000000b', 'dddddddd-0000-0000-0000-000000000002',
   'dddddddd-0000-0000-0000-000000000001', 'Winter Fest', 'completed', 'events/winter.jpg'),
  ('dddddddd-0000-0000-0000-00000000000c', 'dddddddd-0000-0000-0000-000000000002',
   'dddddddd-0000-0000-0000-000000000001', 'Secret Show', 'on_sale',   'events/secret.jpg');

INSERT INTO catalog.event_session (session_id, event_id, session_label, starts_at, ends_at, status) VALUES
  ('dddddddd-0000-0000-0000-000000000101', 'dddddddd-0000-0000-0000-00000000000a',
   'Main',  now() + interval '30 days', NULL,                          'scheduled'),
  ('dddddddd-0000-0000-0000-000000000102', 'dddddddd-0000-0000-0000-00000000000b',
   'Main',  now() - interval '30 days', now() - interval '30 days' + interval '3 hours', 'completed'),
  ('dddddddd-0000-0000-0000-000000000103', 'dddddddd-0000-0000-0000-00000000000c',
   'Main',  now() + interval '10 days', NULL,                          'scheduled');

INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor) VALUES
  ('dddddddd-0000-0000-0000-000000000201', 'dddddddd-0000-0000-0000-00000000000a', 'admission', 'GA',    5000),
  ('dddddddd-0000-0000-0000-000000000202', 'dddddddd-0000-0000-0000-00000000000b', 'admission', 'GA2',   4000),
  ('dddddddd-0000-0000-0000-000000000203', 'dddddddd-0000-0000-0000-00000000000c', 'admission', 'OTHER', 3000);

INSERT INTO kernel.signing_key (key_id, scope, event_id, public_key, kms_handle_ref, not_before) VALUES
  ('dddddddd-0000-0000-0000-000000000301', 'per_event', 'dddddddd-0000-0000-0000-00000000000a', 'pk-a', 'kms://a', now()),
  ('dddddddd-0000-0000-0000-000000000302', 'per_event', 'dddddddd-0000-0000-0000-00000000000b', 'pk-b', 'kms://b', now()),
  ('dddddddd-0000-0000-0000-000000000303', 'per_event', 'dddddddd-0000-0000-0000-00000000000c', 'pk-c', 'kms://c', now());

-- Buyer: 3 upcoming GA (2 held, 1 listed) + 1 past GA2 (scanned).
INSERT INTO kernel.tickets
  (event_session_id, org_id, ticket_type_id, serial_no, current_owner_id, state, resale_state, signing_key_id) VALUES
  ('dddddddd-0000-0000-0000-000000000101','dddddddd-0000-0000-0000-000000000001','dddddddd-0000-0000-0000-000000000201',1, tap.buyer(),'issued','none','dddddddd-0000-0000-0000-000000000301'),
  ('dddddddd-0000-0000-0000-000000000101','dddddddd-0000-0000-0000-000000000001','dddddddd-0000-0000-0000-000000000201',2, tap.buyer(),'issued','none','dddddddd-0000-0000-0000-000000000301'),
  ('dddddddd-0000-0000-0000-000000000101','dddddddd-0000-0000-0000-000000000001','dddddddd-0000-0000-0000-000000000201',3, tap.buyer(),'issued','listed','dddddddd-0000-0000-0000-000000000301'),
  ('dddddddd-0000-0000-0000-000000000102','dddddddd-0000-0000-0000-000000000001','dddddddd-0000-0000-0000-000000000202',10,tap.buyer(),'scanned','none','dddddddd-0000-0000-0000-000000000302');

-- Other user: 1 ticket to a different event — must never surface for the buyer.
INSERT INTO kernel.tickets
  (event_session_id, org_id, ticket_type_id, serial_no, current_owner_id, state, resale_state, signing_key_id) VALUES
  ('dddddddd-0000-0000-0000-000000000103','dddddddd-0000-0000-0000-000000000001','dddddddd-0000-0000-0000-000000000203',20,tap.other_user(),'issued','none','dddddddd-0000-0000-0000-000000000303');

-- ---------------------------------------------------------------------------
-- SECTION B — owner read (buyer)
-- ---------------------------------------------------------------------------
SELECT tap.login(tap.buyer());

SELECT is((SELECT count(*)::int FROM public.get_my_tickets()), 3,
  'B1: buyer sees exactly 3 groups (2 upcoming GA groups + 1 past)');

SELECT is((SELECT quantity FROM public.get_my_tickets()
            WHERE time_class='upcoming' AND fulfillment_status='held' AND ticket_type_name='GA'), 2,
  'B2: upcoming GA held quantity = 2');

SELECT is((SELECT quantity FROM public.get_my_tickets()
            WHERE time_class='upcoming' AND fulfillment_status='listed' AND ticket_type_name='GA'), 1,
  'B3: a listed atom splits into its own group (quantity 1, fulfillment listed)');

SELECT is((SELECT ownership_status FROM public.get_my_tickets()
            WHERE time_class='upcoming' AND fulfillment_status='held' AND ticket_type_name='GA'), 'valid',
  'B4: issued -> ownership_status valid');

SELECT is((SELECT ownership_status FROM public.get_my_tickets() WHERE time_class='past'), 'used',
  'B5: scanned -> ownership_status used');

SELECT is((SELECT quantity FROM public.get_my_tickets() WHERE time_class='past'), 1,
  'B6: past group quantity = 1');

SELECT is(
  (SELECT array_agg(time_class ORDER BY ord)
     FROM public.get_my_tickets() WITH ORDINALITY AS t(
       event_id, event_session_id, event_title, session_label, starts_at, ends_at,
       doors_at, venue_id, venue_name, artwork_ref, ticket_type_id, ticket_type_name,
       ticket_type_kind, quantity, ownership_status, fulfillment_status, time_class, ord)),
  ARRAY['upcoming','upcoming','past']::text[],
  'B7: ordering is upcoming-first then past');

SELECT ok(NOT EXISTS (SELECT 1 FROM public.get_my_tickets() WHERE event_title = 'Secret Show'),
  'B8: another user''s event never appears (structural owner scope)');

SELECT is((SELECT artwork_ref FROM public.get_my_tickets()
            WHERE time_class='upcoming' AND fulfillment_status='held' AND ticket_type_name='GA'),
          'events/neon.jpg',
  'B9: artwork_ref is the event hero storage path');

SELECT is((SELECT venue_name FROM public.get_my_tickets()
            WHERE time_class='upcoming' AND fulfillment_status='held' AND ticket_type_name='GA'),
          'Bass Hall',
  'B10: venue_name resolved server-side');

SELECT tap.logout();

-- ---------------------------------------------------------------------------
-- SECTION C — successful empty state (admin owns no tickets)
-- ---------------------------------------------------------------------------
SELECT tap.login(tap.admin_user());
SELECT is((SELECT count(*)::int FROM public.get_my_tickets()), 0,
  'C1: an authenticated caller with no tickets gets an empty set (not an error)');
SELECT tap.logout();

-- ---------------------------------------------------------------------------
-- SECTION D — fail closed
-- ---------------------------------------------------------------------------
SELECT tap.login_anon();
SELECT throws_ok($$ SELECT * FROM public.get_my_tickets() $$, '42501',
  NULL, 'D1: anon EXECUTE is denied (permission error, never empty)');
SELECT tap.logout();

-- authenticated role but no subject claim -> the in-body fail-closed guard.
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claims', '{"role":"authenticated"}', true);
SELECT throws_ok($$ SELECT * FROM public.get_my_tickets() $$, '28000',
  'tickets_unauthenticated', 'D2: null uid raises tickets_unauthenticated');
SELECT tap.logout();

SELECT finish();
ROLLBACK;

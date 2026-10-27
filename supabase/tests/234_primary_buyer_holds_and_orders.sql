-- ============================================================================
-- 234_primary_buyer_holds_and_orders.sql — migration 20261027015500 (registry
-- 167): public.reserve_primary_tier, public.release_primary_hold,
-- public.list_my_primary_orders — the buyer's reserve / release / all-orders
-- verbs over venue.reserve_primary_inventory, venue.release_inventory_hold and
-- 182's public.get_my_primary_orders.
--
-- Registry 167 / pgTAP 234 — assigned by Claude A 2026-10-26 (registry @
-- 5f29cbcc). A reviews before this leaves draft; C consumes. DARK: applied
-- nowhere; this file flips no flag outside its own rolled-back transaction.
--
-- Fixture style: 252 (synthetic rows inserted as postgres with fixed ids, tag
-- 23400000-…, read back as each caller through tap.login / tap.login_anon /
-- tap.login_service, everything rolled back). Identities: buyer B1 (…0101),
-- buyer B2 (…0102), a fan with nothing (…0199), anon, service_role and the
-- "authenticated role with no subject" persona. Room V1 (approved). Event E1
-- on_sale with sessions S1 and S2; event E3 announced with session S4. Tiers of
-- E1: GA (public), Two batch (public), Hidden (hidden), Door (door_only); E3:
-- T4 (public). Batches: GA x S1 public_sale cap 5 (bA) plus an OLDER comp batch
-- cap 100 (bAc — the batch a pick without the release_kind filter would take);
-- GA x S2 public_sale cap 10 (bB); Two batch x S1 TWO public_sale batches — m1
-- (older, cap 1) and m2 (newer, cap 10) — for the several-batches rule; Hidden x
-- S1 public_sale (bH — what a pick without the visibility filter would take);
-- Door x S1 door (bD); T4 x S4 public_sale (b4). Config: feature.native_
-- issuance_enabled true, inventory.hold_ttl_interval 15 minutes,
-- inventory.per_user_active_hold_max 3 — each a NEW VERSION of the append-only
-- catalog.platform_config row (174/230/252 pattern), flipped further below by
-- later versions, all rolled back with the file. Orders (as postgres, the 252
-- pattern): B1 P1 (S1, paid, linked payment succeeded, total 3300) / P2 (S2,
-- pending, no link) / P3 (S1, pending, linked payment processing, total 2200);
-- B2 Q1 (S1, pending, linked payment failed, total 6600).
--
--   Section A  shape + ACL + census (NULL-safe on the chain without 167): the
--              three exist, SECURITY DEFINER, search_path = '', volatility
--              v / v / s; EXECUTE authenticated + service_role, anon none, no
--              PUBLIC, proacl not defaulted; signatures and return types; the
--              list's first eight columns ARE get_my_primary_orders' outputs
--              (read from the catalog), then event_session_id uuid, title text;
--              public census 133; comments; no identity-like parameter.
--   Section R  reserve_primary_tier as B1 (current_user = authenticated,
--              pinned): hold created on bA (not the older comp batch) with the
--              engine's 15-minute TTL; replay with the same key = the original
--              hold (quantity 2 although the replay asks 3; held unchanged);
--              oversell_rejected; several batches — two units land on m2 (m1
--              lacks room), one unit (B2) lands on m1 (oldest with room); the
--              other session's batch for S2; hold_cap_exceeded at the 4th hold;
--              hidden / door_only tier / unknown session → P0002 not_found;
--              then B2: flag off → feature_disabled, TTL unset → hold_ttl_unset,
--              announced event → not_on_sale, a public tier whose sale window
--              has not opened → tier_not_on_sale (A's 185 BLOCK W, beneath
--              since 2026-10-27; R17) (all the engine's own refusals,
--              passed through); anon 42501 at the ACL; no-subject and
--              service_role 42501 'insufficient_privilege: authentication
--              required'.
--   Section X  release_primary_hold: B2 releasing B1's hold → P0002
--              'not_found: hold <id>' — the same code and text shape as an
--              unknown id (no oracle) — and B1's hold is untouched; a sweep:
--              key is refused; B1 releases her own (ok / released, held back,
--              movement row); a second release → noop_replay; anon 42501;
--              no-subject 42501.
--   Section O  list_my_primary_orders: B1 sees exactly P1/P2/P3 across S1 and
--              S2, newest first; every row equals 182's get_my_primary_orders
--              row for its session (the mapping is 182's, not a copy);
--              hard-coded (status, payment_state, charge_total_minor) incl. NULL
--              for the unlinked pending order; event_session_id + title; B2
--              sees only Q1; the fan sees none; anon 42501; no-subject 28000.
--
-- Expected on the 182 chain WITHOUT 167 (RED, predicted before the first run;
-- reconciled in EVIDENCE-167.md §1): the fixture (tables only) succeeds;
-- A1-A16 all `not ok` (functions absent — every probe is NULL-safe via
-- to_regprocedure / coalesce; the census reads 130, not 133); R0 ok
-- (current_user = authenticated); the store before R1 is the first direct call
-- of a 167 function, raises 42883 and aborts the transaction, so R1 onward is
-- never emitted. Predicted RED run: 17 emitted = 16 not ok + 1 ok; plan unmet;
-- psql reports the 42883.
-- ============================================================================
BEGIN;
SELECT plan(55);

CREATE TABLE tap.memo_234 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store234(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_234 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch234(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_234 WHERE k = $1 $m$;
GRANT EXECUTE ON FUNCTION tap._store234(text, text), tap._fetch234(text) TO anon, authenticated, service_role;

-- ── Fixture (synthetic; never a migration) ─────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at) VALUES
  ('23400000-0000-4000-8000-000000000101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'buyer1.234@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23400000-0000-4000-8000-000000000102', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'buyer2.234@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23400000-0000-4000-8000-000000000199', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fan.234@test.local',    '{"provider":"email","providers":["email"]}', '{}', now(), now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('23400000-0000-4000-8000-00000000000a', 'Org 234', 'Org 234', 'active');
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, address, approval_status) VALUES
  ('23400000-0000-4000-8000-0000000000a1', '23400000-0000-4000-8000-00000000000a', 'Room 234', 'wynwood', '1 Test St', 'approved');
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  ('23400000-0000-4000-8000-0000000000e1', '23400000-0000-4000-8000-0000000000a1', '23400000-0000-4000-8000-00000000000a', 'Holds night 234', 'on_sale'),
  ('23400000-0000-4000-8000-0000000000e3', '23400000-0000-4000-8000-0000000000a1', '23400000-0000-4000-8000-00000000000a', 'Announced 234',   'announced');
INSERT INTO catalog.event_session (session_id, event_id, starts_at, status) VALUES
  ('23400000-0000-4000-8000-0000000000f1', '23400000-0000-4000-8000-0000000000e1', now() + interval '20 days', 'scheduled'),
  ('23400000-0000-4000-8000-0000000000f2', '23400000-0000-4000-8000-0000000000e1', now() + interval '21 days', 'scheduled'),
  ('23400000-0000-4000-8000-0000000000f4', '23400000-0000-4000-8000-0000000000e3', now() + interval '30 days', 'scheduled');
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility) VALUES
  ('23400000-0000-4000-8000-000000000011', '23400000-0000-4000-8000-0000000000e1', 'admission', 'GA',        3000, 'public'),
  ('23400000-0000-4000-8000-000000000012', '23400000-0000-4000-8000-0000000000e1', 'admission', 'Two batch', 2000, 'public'),
  ('23400000-0000-4000-8000-000000000013', '23400000-0000-4000-8000-0000000000e1', 'admission', 'Hidden',    1500, 'hidden'),
  ('23400000-0000-4000-8000-000000000014', '23400000-0000-4000-8000-0000000000e1', 'table',     'Door',      1000, 'door_only'),
  ('23400000-0000-4000-8000-000000000041', '23400000-0000-4000-8000-0000000000e3', 'admission', 'T4',        2200, 'public');
-- R17's tier: public, on the on_sale event, its sale window opens in three days (162's column; 185 refuses before it opens)
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility, sale_starts_at) VALUES
  ('23400000-0000-4000-8000-000000000015', '23400000-0000-4000-8000-0000000000e1', 'admission', 'Late window', 2500, 'public', now() + interval '3 days');
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold, created_at) VALUES
  ('23400000-0000-4000-8000-0000000000c1', '23400000-0000-4000-8000-000000000011', '23400000-0000-4000-8000-0000000000f1', 'public_sale',   5, 0, 0, '2026-10-05 00:00:00+00'),
  ('23400000-0000-4000-8000-0000000000c2', '23400000-0000-4000-8000-000000000011', '23400000-0000-4000-8000-0000000000f1', 'comp',        100, 0, 0, '2026-09-01 00:00:00+00'),
  ('23400000-0000-4000-8000-0000000000c3', '23400000-0000-4000-8000-000000000011', '23400000-0000-4000-8000-0000000000f2', 'public_sale',  10, 0, 0, '2026-10-05 00:00:00+00'),
  ('23400000-0000-4000-8000-0000000000c4', '23400000-0000-4000-8000-000000000012', '23400000-0000-4000-8000-0000000000f1', 'public_sale',   1, 0, 0, '2026-10-01 00:00:00+00'),
  ('23400000-0000-4000-8000-0000000000c5', '23400000-0000-4000-8000-000000000012', '23400000-0000-4000-8000-0000000000f1', 'public_sale',  10, 0, 0, '2026-10-02 00:00:00+00'),
  ('23400000-0000-4000-8000-0000000000c6', '23400000-0000-4000-8000-000000000013', '23400000-0000-4000-8000-0000000000f1', 'public_sale',  10, 0, 0, '2026-09-01 00:00:00+00'),
  ('23400000-0000-4000-8000-0000000000c7', '23400000-0000-4000-8000-000000000014', '23400000-0000-4000-8000-0000000000f1', 'door',         10, 0, 0, '2026-09-01 00:00:00+00'),
  ('23400000-0000-4000-8000-0000000000c8', '23400000-0000-4000-8000-000000000041', '23400000-0000-4000-8000-0000000000f4', 'public_sale',  10, 0, 0, '2026-10-05 00:00:00+00'),
  ('23400000-0000-4000-8000-0000000000c9', '23400000-0000-4000-8000-000000000015', '23400000-0000-4000-8000-0000000000f1', 'public_sale',  10, 0, 0, '2026-10-05 00:00:00+00');
-- orders: all born pending (082 items are immutable once the order leaves pending); P1 moved to paid after its item
INSERT INTO venue."order" (order_id, buyer_id, event_session_id, org_id, status, source, total_minor, currency, command_idempotency_key, created_at) VALUES
  ('23400000-0000-4000-8000-000000000301', '23400000-0000-4000-8000-000000000101', '23400000-0000-4000-8000-0000000000f1', '23400000-0000-4000-8000-00000000000a', 'pending', 'app', 3000, 'USD', 'p1-234', '2026-10-20 10:00:00+00'),
  ('23400000-0000-4000-8000-000000000302', '23400000-0000-4000-8000-000000000101', '23400000-0000-4000-8000-0000000000f2', '23400000-0000-4000-8000-00000000000a', 'pending', 'app', 3000, 'USD', 'p2-234', '2026-10-21 09:00:00+00'),
  ('23400000-0000-4000-8000-000000000303', '23400000-0000-4000-8000-000000000101', '23400000-0000-4000-8000-0000000000f1', '23400000-0000-4000-8000-00000000000a', 'pending', 'app', 2000, 'USD', 'p3-234', '2026-10-22 08:00:00+00'),
  ('23400000-0000-4000-8000-000000000304', '23400000-0000-4000-8000-000000000102', '23400000-0000-4000-8000-0000000000f1', '23400000-0000-4000-8000-00000000000a', 'pending', 'app', 6000, 'USD', 'q1-234', '2026-10-23 07:00:00+00');
INSERT INTO venue.order_item (id, order_id, ticket_type_id, quantity, unit_price_minor) VALUES
  ('23400000-0000-4000-8000-000000000401', '23400000-0000-4000-8000-000000000301', '23400000-0000-4000-8000-000000000011', 1, 3000),
  ('23400000-0000-4000-8000-000000000402', '23400000-0000-4000-8000-000000000302', '23400000-0000-4000-8000-000000000011', 1, 3000),
  ('23400000-0000-4000-8000-000000000403', '23400000-0000-4000-8000-000000000303', '23400000-0000-4000-8000-000000000012', 1, 2000),
  ('23400000-0000-4000-8000-000000000404', '23400000-0000-4000-8000-000000000304', '23400000-0000-4000-8000-000000000011', 2, 3000);
UPDATE venue."order" SET status = 'paid' WHERE order_id = '23400000-0000-4000-8000-000000000301';
-- payments as the primary-checkout edge shapes them (amount = face, buyer_fee, total = the all-in charge; direct rail)
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at) VALUES
  ('23400000-0000-4000-8000-000000000601', NULL, '23400000-0000-4000-8000-000000000101', NULL, 3000, 300, 0, 3300, 'pi_234_p1', 'succeeded',  'native_primary', now()),
  ('23400000-0000-4000-8000-000000000603', NULL, '23400000-0000-4000-8000-000000000101', NULL, 2000, 200, 0, 2200, 'pi_234_p3', 'processing', 'native_primary', NULL),
  ('23400000-0000-4000-8000-000000000604', NULL, '23400000-0000-4000-8000-000000000102', NULL, 6000, 600, 0, 6600, 'pi_234_q1', 'failed',     'native_primary', NULL);
INSERT INTO kernel.payment_native (payment_id, order_id, amount_minor) VALUES
  ('23400000-0000-4000-8000-000000000601', '23400000-0000-4000-8000-000000000301', 3000),
  ('23400000-0000-4000-8000-000000000603', '23400000-0000-4000-8000-000000000303', 2000),
  ('23400000-0000-4000-8000-000000000604', '23400000-0000-4000-8000-000000000304', 6000);
-- config: new versions of the append-only rows (rolled back with the file)
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'feature.native_issuance_enabled', coalesce(max(version), 0) + 1, 'true'::jsonb, 'public' FROM catalog.platform_config WHERE key = 'feature.native_issuance_enabled';
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'inventory.hold_ttl_interval', coalesce(max(version), 0) + 1, '"15 minutes"'::jsonb, 'restricted' FROM catalog.platform_config WHERE key = 'inventory.hold_ttl_interval';
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'inventory.per_user_active_hold_max', coalesce(max(version), 0) + 1, '3'::jsonb, 'restricted' FROM catalog.platform_config WHERE key = 'inventory.per_user_active_hold_max';

-- ── Section A — shape + ACL + census (NULL-safe) ─────────────────────────────
SELECT has_function('public'::name, 'reserve_primary_tier'::name, ARRAY['uuid','uuid','integer','text']::name[], 'A1: public.reserve_primary_tier(uuid, uuid, integer, text) exists');
SELECT has_function('public'::name, 'release_primary_hold'::name, ARRAY['uuid','text']::name[], 'A2: public.release_primary_hold(uuid, text) exists');
SELECT has_function('public'::name, 'list_my_primary_orders'::name, ARRAY[]::name[], 'A3: public.list_my_primary_orders() exists');
SELECT ok(coalesce((SELECT bool_and(p.prosecdef) AND count(*) = 3 FROM pg_proc p WHERE p.oid IN (
           to_regprocedure('public.reserve_primary_tier(uuid, uuid, integer, text)'), to_regprocedure('public.release_primary_hold(uuid, text)'),
           to_regprocedure('public.list_my_primary_orders()'))), false),
  'A4: all three are SECURITY DEFINER');
SELECT ok(coalesce((SELECT bool_and(p.proconfig = ARRAY['search_path=""']) AND count(*) = 3 FROM pg_proc p WHERE p.oid IN (
           to_regprocedure('public.reserve_primary_tier(uuid, uuid, integer, text)'), to_regprocedure('public.release_primary_hold(uuid, text)'),
           to_regprocedure('public.list_my_primary_orders()'))), false),
  'A5: all three pin search_path = ''''');
SELECT is((SELECT string_agg(p.proname || ':' || p.provolatile::text, ',' ORDER BY p.proname) FROM pg_proc p WHERE p.oid IN (
           to_regprocedure('public.reserve_primary_tier(uuid, uuid, integer, text)'), to_regprocedure('public.release_primary_hold(uuid, text)'),
           to_regprocedure('public.list_my_primary_orders()'))),
  'list_my_primary_orders:s,release_primary_hold:v,reserve_primary_tier:v',
  'A6: reserve and release are VOLATILE (they write through the engines); the list is STABLE');
SELECT ok(NOT coalesce(has_function_privilege('anon', to_regprocedure('public.reserve_primary_tier(uuid, uuid, integer, text)'), 'EXECUTE'), true)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('public.reserve_primary_tier(uuid, uuid, integer, text)'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('service_role', to_regprocedure('public.reserve_primary_tier(uuid, uuid, integer, text)'), 'EXECUTE'), false)
      AND coalesce((SELECT p.proacl IS NOT NULL AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0)
                      FROM pg_proc p WHERE p.oid = to_regprocedure('public.reserve_primary_tier(uuid, uuid, integer, text)')), false),
  'A7: reserve — anon none, authenticated + service_role (explicit grant) EXECUTE, no PUBLIC entry, proacl not defaulted');
SELECT ok(NOT coalesce(has_function_privilege('anon', to_regprocedure('public.release_primary_hold(uuid, text)'), 'EXECUTE'), true)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('public.release_primary_hold(uuid, text)'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('service_role', to_regprocedure('public.release_primary_hold(uuid, text)'), 'EXECUTE'), false)
      AND coalesce((SELECT p.proacl IS NOT NULL AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0)
                      FROM pg_proc p WHERE p.oid = to_regprocedure('public.release_primary_hold(uuid, text)')), false),
  'A8: release — anon none, authenticated + service_role EXECUTE, no PUBLIC, proacl not defaulted');
SELECT ok(NOT coalesce(has_function_privilege('anon', to_regprocedure('public.list_my_primary_orders()'), 'EXECUTE'), true)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('public.list_my_primary_orders()'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('service_role', to_regprocedure('public.list_my_primary_orders()'), 'EXECUTE'), false)
      AND coalesce((SELECT p.proacl IS NOT NULL AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0)
                      FROM pg_proc p WHERE p.oid = to_regprocedure('public.list_my_primary_orders()')), false),
  'A9: list — anon none, authenticated + service_role EXECUTE, no PUBLIC, proacl not defaulted');
SELECT is((SELECT p.proargnames || (SELECT array_agg(format_type(t, NULL) ORDER BY o) FROM unnest(p.proargtypes::oid[]) WITH ORDINALITY u(t, o)) || format_type(p.prorettype, NULL)
             FROM pg_proc p WHERE p.oid = to_regprocedure('public.reserve_primary_tier(uuid, uuid, integer, text)')),
  ARRAY['p_session_id','p_ticket_type_id','p_quantity','p_command_key','uuid','uuid','integer','text','jsonb']::text[],
  'A10: reserve_primary_tier(p_session_id uuid, p_ticket_type_id uuid, p_quantity integer, p_command_key text) returns jsonb');
SELECT is((SELECT p.proargnames || (SELECT array_agg(format_type(t, NULL) ORDER BY o) FROM unnest(p.proargtypes::oid[]) WITH ORDINALITY u(t, o)) || format_type(p.prorettype, NULL)
             FROM pg_proc p WHERE p.oid = to_regprocedure('public.release_primary_hold(uuid, text)')),
  ARRAY['p_hold_id','p_command_key','uuid','text','jsonb']::text[],
  'A11: release_primary_hold(p_hold_id uuid, p_command_key text) returns jsonb');
SELECT is((SELECT p.proargnames || (SELECT array_agg(format_type(t, NULL) ORDER BY o) FROM unnest(p.proallargtypes) WITH ORDINALITY u(t, o))
             FROM pg_proc p WHERE p.oid = to_regprocedure('public.list_my_primary_orders()')),
  ARRAY['order_id','status','total_minor','currency','created_at','atoms_issued','payment_state','charge_total_minor','event_session_id','title',
        'uuid','text','integer','text','timestamp with time zone','integer','text','integer','uuid','text']::text[],
  'A12: list_my_primary_orders returns exactly (order_id, status, total_minor, currency, created_at, atoms_issued, payment_state, charge_total_minor, event_session_id, title)');
SELECT is((SELECT (p.proargnames[1:8], (SELECT array_agg(format_type(t, NULL) ORDER BY o) FROM unnest(p.proallargtypes[1:8]) WITH ORDINALITY u(t, o)))::text
             FROM pg_proc p WHERE p.oid = to_regprocedure('public.list_my_primary_orders()')),
          (SELECT (g.proargnames[2:9], (SELECT array_agg(format_type(t, NULL) ORDER BY o) FROM unnest(g.proallargtypes[2:9]) WITH ORDINALITY u(t, o)))::text
             FROM pg_proc g WHERE g.oid = to_regprocedure('public.get_my_primary_orders(uuid)')),
  'A13: the list''s first eight columns ARE get_my_primary_orders'' eight output columns (names and types, read from the catalog), in its order');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')), 133,
  'A14: GATE-2 public functions = 133 (130 + the three 167 verbs; pgtap excluded — the tests/162 P2 query)');
SELECT ok(coalesce((SELECT count(*) = 3 AND bool_and(length(obj_description(p.oid, 'pg_proc')) > 40) FROM pg_proc p WHERE p.oid IN (
           to_regprocedure('public.reserve_primary_tier(uuid, uuid, integer, text)'), to_regprocedure('public.release_primary_hold(uuid, text)'),
           to_regprocedure('public.list_my_primary_orders()'))), false),
  'A15: every function carries a comment');
SELECT ok(coalesce((SELECT count(*) = 3 AND bool_and(NOT EXISTS (SELECT 1 FROM unnest(coalesce(p.proargnames[1:p.pronargs], ARRAY[]::text[])) a
                                                                WHERE a ~* '(user|buyer|owner|identity|org|actor)'))
                      FROM pg_proc p WHERE p.oid IN (
           to_regprocedure('public.reserve_primary_tier(uuid, uuid, integer, text)'), to_regprocedure('public.release_primary_hold(uuid, text)'),
           to_regprocedure('public.list_my_primary_orders()'))), false),
  'A16: no input parameter names a user / buyer / owner / identity / org / actor — the caller is auth.uid(), never an argument');

-- ── Section R — reserve_primary_tier ─────────────────────────────────────────
SELECT tap.login('23400000-0000-4000-8000-000000000101');
SELECT is(current_user::text, 'authenticated', 'R0: B1 calls as the authenticated role (tap.login)');
SELECT tap._store234('r_k1', public.reserve_primary_tier('23400000-0000-4000-8000-0000000000f1', '23400000-0000-4000-8000-000000000011', 2, 'k1-234')::text);
SELECT is((SELECT (j ->> 'status', (j ->> 'quantity')::int, j ->> 'hold_id' IS NOT NULL, j ->> 'expires_at' IS NOT NULL,
                   (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(j) k))::text FROM (SELECT tap._fetch234('r_k1')::jsonb j) x),
  ('ok', 2, true, true, ARRAY['expires_at','hold_id','quantity','status'])::text,
  'R1: B1 reserves 2 x GA on S1 — {status ok, hold_id, expires_at, quantity 2} and exactly those four keys');
SELECT tap.logout();
SELECT is((SELECT (h.batch_id, h.identity_id, h.quantity, h.status, h.expires_at = now() + interval '15 minutes',
                   h.expires_at = (tap._fetch234('r_k1')::jsonb ->> 'expires_at')::timestamptz)::text
             FROM venue.inventory_hold h WHERE h.hold_id = (tap._fetch234('r_k1')::jsonb ->> 'hold_id')::uuid),
  ('23400000-0000-4000-8000-0000000000c1', '23400000-0000-4000-8000-000000000101', 2, 'active', true, true)::text,
  'R2: the hold sits on bA (GA x S1 public_sale — not the OLDER comp batch), owned by B1 (auth.uid(), never an argument), 2 units, the engine''s 15-minute TTL, expires_at as returned');
SELECT is((SELECT (b1.held, b2.held, (SELECT count(*)::int FROM venue.inventory_hold h WHERE h.identity_id = '23400000-0000-4000-8000-000000000101'))::text
             FROM venue.inventory_batch b1, venue.inventory_batch b2
            WHERE b1.batch_id = '23400000-0000-4000-8000-0000000000c1' AND b2.batch_id = '23400000-0000-4000-8000-0000000000c2'),
  (2, 0, 1)::text,
  'R3: bA.held = 2, the comp batch untouched (held 0), B1 holds exactly one hold');
SELECT tap.login('23400000-0000-4000-8000-000000000101');
SELECT tap._store234('r_k1b', public.reserve_primary_tier('23400000-0000-4000-8000-0000000000f1', '23400000-0000-4000-8000-000000000011', 3, 'k1-234')::text);
SELECT is((SELECT (j ->> 'status', j ->> 'hold_id', (j ->> 'quantity')::int)::text FROM (SELECT tap._fetch234('r_k1b')::jsonb j) x),
  ('idempotency_replay', tap._fetch234('r_k1')::jsonb ->> 'hold_id', 2)::text,
  'R4: a replay with the same key (asking 3) returns the ORIGINAL hold — idempotency_replay, the same hold_id, quantity 2 (the engine''s per-identity key rule)');
SELECT tap.logout();
SELECT is((SELECT (b.held, (SELECT count(*)::int FROM venue.inventory_hold h WHERE h.identity_id = '23400000-0000-4000-8000-000000000101'))::text
             FROM venue.inventory_batch b WHERE b.batch_id = '23400000-0000-4000-8000-0000000000c1'),
  (2, 1)::text,
  'R5: …and the replay drew nothing — bA.held still 2, still one hold');
SELECT tap.login('23400000-0000-4000-8000-000000000101');
SELECT throws_ok($$ SELECT public.reserve_primary_tier('23400000-0000-4000-8000-0000000000f1', '23400000-0000-4000-8000-000000000011', 4, 'k2-234') $$,
  'P0001', 'precondition_failed: oversell_rejected',
  'R6: 4 more of GA on S1 (cap 5, held 2) — the engine''s oversell_rejected passes through with its code');
SELECT tap._store234('r_k3', public.reserve_primary_tier('23400000-0000-4000-8000-0000000000f1', '23400000-0000-4000-8000-000000000012', 2, 'k3-234')::text);
SELECT tap._store234('r_k4', public.reserve_primary_tier('23400000-0000-4000-8000-0000000000f2', '23400000-0000-4000-8000-000000000011', 1, 'k4-234')::text);
SELECT throws_ok($$ SELECT public.reserve_primary_tier('23400000-0000-4000-8000-0000000000f1', '23400000-0000-4000-8000-000000000012', 1, 'k5-234') $$,
  'P0001', 'precondition_failed: hold_cap_exceeded',
  'R7: a fourth active hold (cap 3) — the engine''s hold_cap_exceeded passes through');
SELECT throws_ok($$ SELECT public.reserve_primary_tier('23400000-0000-4000-8000-0000000000f1', '23400000-0000-4000-8000-000000000013', 1, 'k6-234') $$,
  'P0002', 'not_found: no public_sale inventory for ticket type 23400000-0000-4000-8000-000000000013 on session 23400000-0000-4000-8000-0000000000f1',
  'R8: a HIDDEN tier (with a public_sale batch) is not reservable — P0002 not_found');
SELECT throws_ok($$ SELECT public.reserve_primary_tier('23400000-0000-4000-8000-0000000000f1', '23400000-0000-4000-8000-000000000014', 1, 'k7-234') $$,
  'P0002', 'not_found: no public_sale inventory for ticket type 23400000-0000-4000-8000-000000000014 on session 23400000-0000-4000-8000-0000000000f1',
  'R9: a DOOR_ONLY tier (door batch only) — the same not_found');
SELECT throws_ok($$ SELECT public.reserve_primary_tier('23400000-0000-4000-8000-00000000dead', '23400000-0000-4000-8000-000000000011', 1, 'k8-234') $$,
  'P0002', 'not_found: no public_sale inventory for ticket type 23400000-0000-4000-8000-000000000011 on session 23400000-0000-4000-8000-00000000dead',
  'R10: an unknown session — the same not_found (one message, no oracle)');
SELECT tap.logout();
SELECT is((SELECT (h3.batch_id, h3.quantity, h4.batch_id)::text
             FROM venue.inventory_hold h3, venue.inventory_hold h4
            WHERE h3.hold_id = (tap._fetch234('r_k3')::jsonb ->> 'hold_id')::uuid AND h4.hold_id = (tap._fetch234('r_k4')::jsonb ->> 'hold_id')::uuid),
  ('23400000-0000-4000-8000-0000000000c5', 2, '23400000-0000-4000-8000-0000000000c3')::text,
  'R11: SEVERAL public_sale batches — 2 x Two batch lands on m2 (the older m1 has room for 1 only); GA on S2 lands on S2''s own batch bB');
SELECT is((SELECT (count(*)::int, sum(h.quantity)::int)::text FROM venue.inventory_hold h WHERE h.identity_id = '23400000-0000-4000-8000-000000000101' AND h.status = 'active'),
  (3, 5)::text,
  'R12: B1 now holds exactly three active holds (2 + 2 + 1); the refused calls drew nothing');
SELECT tap.login('23400000-0000-4000-8000-000000000102');
SELECT tap._store234('r_q1', public.reserve_primary_tier('23400000-0000-4000-8000-0000000000f1', '23400000-0000-4000-8000-000000000012', 1, 'q1-234')::text);
SELECT tap.logout();
SELECT is((SELECT (h.batch_id, h.identity_id)::text FROM venue.inventory_hold h WHERE h.hold_id = (tap._fetch234('r_q1')::jsonb ->> 'hold_id')::uuid),
  ('23400000-0000-4000-8000-0000000000c4', '23400000-0000-4000-8000-000000000102')::text,
  'R13: one unit of Two batch (B2) lands on m1 — the OLDEST public_sale batch with room');
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'feature.native_issuance_enabled', max(version) + 1, 'false'::jsonb, 'public' FROM catalog.platform_config WHERE key = 'feature.native_issuance_enabled';
SELECT tap.login('23400000-0000-4000-8000-000000000102');
SELECT throws_ok($$ SELECT public.reserve_primary_tier('23400000-0000-4000-8000-0000000000f1', '23400000-0000-4000-8000-000000000011', 1, 'q2-234') $$,
  'P0001', 'precondition_failed: feature_disabled',
  'R14: flag off (a new false version) — the engine''s feature_disabled passes through');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'feature.native_issuance_enabled', max(version) + 1, 'true'::jsonb, 'public' FROM catalog.platform_config WHERE key = 'feature.native_issuance_enabled';
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'inventory.hold_ttl_interval', max(version) + 1, 'null'::jsonb, 'restricted' FROM catalog.platform_config WHERE key = 'inventory.hold_ttl_interval';
SELECT tap.login('23400000-0000-4000-8000-000000000102');
SELECT throws_ok($$ SELECT public.reserve_primary_tier('23400000-0000-4000-8000-0000000000f1', '23400000-0000-4000-8000-000000000011', 1, 'q3-234') $$,
  'P0001', 'precondition_failed: hold_ttl_unset',
  'R15: TTL unset (a new JSON-null version) — the engine''s hold_ttl_unset passes through');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'inventory.hold_ttl_interval', max(version) + 1, '"15 minutes"'::jsonb, 'restricted' FROM catalog.platform_config WHERE key = 'inventory.hold_ttl_interval';
SELECT tap.login('23400000-0000-4000-8000-000000000102');
SELECT throws_ok($$ SELECT public.reserve_primary_tier('23400000-0000-4000-8000-0000000000f4', '23400000-0000-4000-8000-000000000041', 1, 'q4-234') $$,
  'P0001', 'precondition_failed: not_on_sale',
  'R16: a public tier of an ANNOUNCED event — the engine''s not_on_sale passes through');
SELECT throws_ok($$ SELECT public.reserve_primary_tier('23400000-0000-4000-8000-0000000000f1', '23400000-0000-4000-8000-000000000015', 1, 'q5-234') $$,
  'P0001', 'precondition_failed: tier_not_on_sale',
  'R17: a public tier of an ON-SALE event whose sale window opens in three days — 185''s tier_not_on_sale passes through (BLOCK W, venue.ticket_type_on_sale)');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$ SELECT public.reserve_primary_tier('23400000-0000-4000-8000-0000000000f1', '23400000-0000-4000-8000-000000000011', 1, 'a1-234') $$,
  '42501', NULL, 'R17: anon has no EXECUTE (denied at the ACL)');
SELECT tap.logout();
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claims', '{"role":"authenticated"}', true);
SELECT throws_ok($$ SELECT public.reserve_primary_tier('23400000-0000-4000-8000-0000000000f1', '23400000-0000-4000-8000-000000000011', 1, 'n1-234') $$,
  '42501', 'insufficient_privilege: authentication required', 'R18: authenticated role with no subject -> 42501 authentication required (before any lookup)');
SELECT tap.logout();
SELECT tap.login_service();
SELECT throws_ok($$ SELECT public.reserve_primary_tier('23400000-0000-4000-8000-0000000000f1', '23400000-0000-4000-8000-000000000011', 1, 's1-234') $$,
  '42501', 'insufficient_privilege: authentication required', 'R19: service_role (explicit EXECUTE) is refused too — auth.uid() is NULL for it');
SELECT tap.logout();

-- ── Section X — release_primary_hold ─────────────────────────────────────────
SELECT tap.login('23400000-0000-4000-8000-000000000102');
SELECT throws_ok(format($$ SELECT public.release_primary_hold(%L, 'x1-234') $$, tap._fetch234('r_k1')::jsonb ->> 'hold_id'),
  'P0002', 'not_found: hold ' || (tap._fetch234('r_k1')::jsonb ->> 'hold_id'),
  'X1: B2 releasing B1''s hold -> P0002 not_found: hold <id>');
SELECT throws_ok($$ SELECT public.release_primary_hold('23400000-0000-4000-8000-00000000dead', 'x2-234') $$,
  'P0002', 'not_found: hold 23400000-0000-4000-8000-00000000dead',
  'X2: …exactly what an unknown hold id answers (same code, same text shape): no existence oracle');
SELECT throws_ok(format($$ SELECT public.release_primary_hold(%L, 'sweep:x3') $$, tap._fetch234('r_q1')::jsonb ->> 'hold_id'),
  'P0001', 'precondition_failed: reserved_command_key — the sweep: prefix belongs to venue.sweep_expired_inventory_holds',
  'X3: a sweep: command key is refused even on B2''s own hold (it would record the sweep''s expired transition)');
SELECT tap.logout();
SELECT is((SELECT (h1.status, b.held, hq.status)::text
             FROM venue.inventory_hold h1, venue.inventory_batch b, venue.inventory_hold hq
            WHERE h1.hold_id = (tap._fetch234('r_k1')::jsonb ->> 'hold_id')::uuid AND b.batch_id = '23400000-0000-4000-8000-0000000000c1'
              AND hq.hold_id = (tap._fetch234('r_q1')::jsonb ->> 'hold_id')::uuid),
  ('active', 2, 'active')::text,
  'X4: B1''s hold is untouched by B2''s attempt (active, bA.held 2) and B2''s own hold survives the refused sweep: key');
SELECT tap.login('23400000-0000-4000-8000-000000000101');
SELECT tap._store234('x_k1', public.release_primary_hold((tap._fetch234('r_k1')::jsonb ->> 'hold_id')::uuid, 'x5-234')::text);
SELECT is((SELECT (j ->> 'status', j ->> 'hold_id', j ->> 'hold_status', (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(j) k))::text
             FROM (SELECT tap._fetch234('x_k1')::jsonb j) x),
  ('ok', tap._fetch234('r_k1')::jsonb ->> 'hold_id', 'released', ARRAY['hold_id','hold_status','status'])::text,
  'X5: B1 releases her own hold — {status ok, hold_id, hold_status released}, exactly those keys');
SELECT tap.logout();
SELECT is((SELECT (b.held, (SELECT count(*)::int FROM venue.inventory_movement m WHERE m.cause_ref = (tap._fetch234('r_k1')::jsonb ->> 'hold_id')::uuid AND m.movement_kind = 'release' AND m.delta_held = -2))::text
             FROM venue.inventory_batch b WHERE b.batch_id = '23400000-0000-4000-8000-0000000000c1'),
  (0, 1)::text,
  'X6: the engine returned the units (bA.held 0) and wrote its release movement (-2)');
SELECT tap.login('23400000-0000-4000-8000-000000000101');
SELECT is((public.release_primary_hold((tap._fetch234('r_k1')::jsonb ->> 'hold_id')::uuid, 'x7-234') - 'hold_id')::text,
  '{"status": "noop_replay", "hold_status": "released"}',
  'X7: releasing it again is the engine''s terminal-state noop_replay');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$ SELECT public.release_primary_hold('23400000-0000-4000-8000-00000000dead', 'a2-234') $$, '42501', NULL, 'X8: anon has no EXECUTE');
SELECT tap.logout();
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claims', '{"role":"authenticated"}', true);
SELECT throws_ok(format($$ SELECT public.release_primary_hold(%L, 'n2-234') $$, tap._fetch234('r_q1')::jsonb ->> 'hold_id'),
  '42501', 'insufficient_privilege: authentication required',
  'X9: no subject -> 42501 (the engine''s NULL-uid sweep branch is never reachable through the wrapper)');
SELECT tap.logout();

-- ── Section O — list_my_primary_orders ───────────────────────────────────────
SELECT tap.login('23400000-0000-4000-8000-000000000101');
SELECT set_eq($$ SELECT l.order_id FROM public.list_my_primary_orders() l $$,
  ARRAY['23400000-0000-4000-8000-000000000301','23400000-0000-4000-8000-000000000302','23400000-0000-4000-8000-000000000303']::uuid[],
  'O1: B1 sees exactly her three orders, across S1 and S2 — and not B2''s Q1');
SELECT is((SELECT array_agg(l.order_id::text ORDER BY rn) FROM (SELECT l.order_id, row_number() OVER () rn FROM public.list_my_primary_orders() l) l),
  ARRAY['23400000-0000-4000-8000-000000000303','23400000-0000-4000-8000-000000000302','23400000-0000-4000-8000-000000000301'],
  'O2: newest first across sessions (P3 S1 10-22, P2 S2 10-21, P1 S1 10-20)');
SELECT set_eq($$ SELECT (l.order_id, l.status, l.total_minor, l.currency, l.created_at, l.atoms_issued, l.payment_state, l.charge_total_minor)::text FROM public.list_my_primary_orders() l $$,
  $$ SELECT (g.*)::text FROM public.get_my_primary_orders('23400000-0000-4000-8000-0000000000f1') g
     UNION ALL SELECT (g.*)::text FROM public.get_my_primary_orders('23400000-0000-4000-8000-0000000000f2') g $$,
  'O3: every row equals 182''s get_my_primary_orders row for its session — the 182 mapping by construction, not a copy');
SELECT is((SELECT string_agg((l.status, l.total_minor, l.payment_state, coalesce(l.charge_total_minor::text, 'NULL'))::text, ' ' ORDER BY l.created_at) FROM public.list_my_primary_orders() l),
  '(paid,3000,succeeded,3300) (pending,3000,none,NULL) (pending,2000,processing,2200)',
  'O4: P1 paid/succeeded charge 3300 (linked payments.total, face 3000); P2 pending/none charge NULL (no link — never recomputed); P3 pending/processing 2200');
SELECT is((SELECT string_agg((l.event_session_id, l.title)::text, ' ' ORDER BY l.created_at) FROM public.list_my_primary_orders() l),
  '(23400000-0000-4000-8000-0000000000f1,"Holds night 234") (23400000-0000-4000-8000-0000000000f2,"Holds night 234") (23400000-0000-4000-8000-0000000000f1,"Holds night 234")',
  'O5: each row carries its event_session_id and the event title');
SELECT tap.logout();
SELECT tap.login('23400000-0000-4000-8000-000000000102');
SELECT is((SELECT (count(*)::int, min(l.order_id::text), min(l.status), min(l.payment_state), min(l.charge_total_minor))::text FROM public.list_my_primary_orders() l),
  (1, '23400000-0000-4000-8000-000000000304', 'pending', 'failed', 6600)::text,
  'O6: B2 sees only his Q1 (pending, payment failed, its PaymentIntent total 6600) — none of B1''s three');
SELECT tap.logout();
SELECT tap.login('23400000-0000-4000-8000-000000000199');
SELECT is((SELECT count(*)::int FROM public.list_my_primary_orders()), 0, 'O7: a fan with no orders gets an empty set (success, not an error)');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$ SELECT * FROM public.list_my_primary_orders() $$, '42501', NULL, 'O8: anon has no EXECUTE');
SELECT tap.logout();
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claims', '{"role":"authenticated"}', true);
SELECT throws_ok($$ SELECT * FROM public.list_my_primary_orders() $$, '28000', 'orders_unauthenticated', 'O9: authenticated role with no subject -> 28000 orders_unauthenticated');
SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;

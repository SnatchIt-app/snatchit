-- ============================================================================
-- 000_helpers.sql — shared pgTAP harness for the Snatch It DB security gate.
--
-- This file is the ONLY test file that COMMITS: it installs the `tap` schema
-- (persona helpers + fixture builder) that every other file uses inside its
-- own BEGIN…ROLLBACK transaction. It runs first (pg_prove sorts by filename).
--
-- CRITICAL HARNESS RULE (see request_is_service_role(), migration 055):
--   request_is_service_role() returns TRUE when request.jwt.claims is NULL —
--   a claims-less direct DB connection is treated as the trusted service
--   path. A test that runs "as authenticated" WITHOUT setting claims would
--   therefore let p_user_id spoofing succeed and prove nothing. Every persona
--   helper below ALWAYS sets request.jwt.claims; never SET ROLE by hand.
--
-- Personas:
--   tap.login(uid)      -> role authenticated, claims {sub: uid, role: authenticated}
--   tap.login_anon()    -> role anon,          claims {role: anon}
--   tap.login_service() -> role service_role,  claims {role: service_role}
--   tap.logout()        -> back to postgres, claims cleared ('' == NULL to the
--                          nullif() readers) — i.e. the trusted service path
--                          (direct connection / SECURITY DEFINER cron context).
--   tap.set_claims(uid, role) -> claims only, without switching the SQL role
--                          (for probing definer functions like is_admin()).
--
-- All settings use set_config(..., is_local => true), so every persona and
-- claim dies with the enclosing test transaction's ROLLBACK.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgtap;

CREATE SCHEMA IF NOT EXISTS tap;

-- ── Deterministic fixture ids ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION tap.seller()     RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '11111111-1111-1111-1111-111111111111'::uuid $$;
CREATE OR REPLACE FUNCTION tap.buyer()      RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '22222222-2222-2222-2222-222222222222'::uuid $$;
CREATE OR REPLACE FUNCTION tap.other_user() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '33333333-3333-3333-3333-333333333333'::uuid $$;
CREATE OR REPLACE FUNCTION tap.admin_user() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '44444444-4444-4444-4444-444444444444'::uuid $$;

CREATE OR REPLACE FUNCTION tap.listing_a() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT 'aaaaaaaa-0000-0000-0000-000000000001'::uuid $$;  -- active, has succeeded payment + pending transfer
CREATE OR REPLACE FUNCTION tap.listing_b() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT 'aaaaaaaa-0000-0000-0000-000000000002'::uuid $$;  -- active, has succeeded payment + seller_sent transfer
CREATE OR REPLACE FUNCTION tap.listing_c() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT 'aaaaaaaa-0000-0000-0000-000000000003'::uuid $$;  -- cancelled
CREATE OR REPLACE FUNCTION tap.listing_d() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT 'aaaaaaaa-0000-0000-0000-000000000004'::uuid $$;  -- active, only a PENDING payment

CREATE OR REPLACE FUNCTION tap.payment_a() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT 'bbbbbbbb-0000-0000-0000-000000000001'::uuid $$;  -- succeeded (listing A)
CREATE OR REPLACE FUNCTION tap.payment_b() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT 'bbbbbbbb-0000-0000-0000-000000000002'::uuid $$;  -- succeeded (listing B)
CREATE OR REPLACE FUNCTION tap.payment_d() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT 'bbbbbbbb-0000-0000-0000-000000000004'::uuid $$;  -- pending   (listing D)

CREATE OR REPLACE FUNCTION tap.transfer_a() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT 'cccccccc-0000-0000-0000-000000000001'::uuid $$; -- pending
CREATE OR REPLACE FUNCTION tap.transfer_b() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT 'cccccccc-0000-0000-0000-000000000002'::uuid $$; -- seller_sent, evidence set

-- ── Persona helpers ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION tap.set_claims(p_uid uuid, p_role text DEFAULT 'authenticated')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', p_uid, 'role', p_role,
                      'email', p_uid::text || '@test.local')::text,
    true);
END $$;

CREATE OR REPLACE FUNCTION tap.login(p_uid uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM tap.set_claims(p_uid, 'authenticated');
  PERFORM set_config('role', 'authenticated', true);
END $$;

CREATE OR REPLACE FUNCTION tap.login_anon()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  PERFORM set_config('role', 'anon', true);
END $$;

CREATE OR REPLACE FUNCTION tap.login_service()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  PERFORM set_config('role', 'service_role', true);
END $$;

CREATE OR REPLACE FUNCTION tap.logout()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'none', true);
  -- '' reads as NULL through nullif(current_setting(...), '') everywhere the
  -- migrations consult claims => this persona IS the trusted service path.
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- Belt-and-braces: the listing/transfer guard bypass GUCs are transaction-
-- local; a successful RPC earlier in a test file can leave app.bypass_* = 'on'
-- (transfers has the 056c statement-trigger reset; listings does NOT).
-- Call before asserting that a guard trigger blocks a direct write.
CREATE OR REPLACE FUNCTION tap.reset_guards()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('app.bypass_listing_guard',  'off', true);
  PERFORM set_config('app.bypass_transfer_guard', 'off', true);
END $$;

-- ── Fixture builder ─────────────────────────────────────────────────────────
-- Call as postgres (i.e. before any tap.login*) at the top of a test
-- transaction. Everything it creates dies with the file's ROLLBACK.
--
-- Sanctioned-path note: transfers rows are INSERTed directly — the state
-- guard (055/056b) is a BEFORE UPDATE trigger, and production inserts come
-- from ensure_transfer_exists()/the webhook doing plain INSERTs, so a direct
-- INSERT as the service path is faithful. All UPDATE-path custody is what the
-- test files themselves exercise.
CREATE OR REPLACE FUNCTION tap.seed_core()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  -- Users. handle_new_user() auto-creates public.profiles rows.
  INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, phone, phone_confirmed_at, created_at, updated_at)
  VALUES
    (tap.seller(),     '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'seller@test.local', '{"provider":"email","providers":["email"]}', '{}', '+13055550001', now(), now(), now()),
    (tap.buyer(),      '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'buyer@test.local',  '{"provider":"email","providers":["email"]}', '{}', NULL, NULL, now(), now()),
    (tap.other_user(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'other@test.local',  '{"provider":"email","providers":["email"]}', '{}', NULL, NULL, now(), now()),
    (tap.admin_user(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin@test.local',  '{"provider":"email","providers":["email"]}', '{}', NULL, NULL, now(), now())
  ON CONFLICT (id) DO NOTHING;

  -- Profile state (fixture writes as table owner; guarded columns are only
  -- guarded against CLIENT roles via column grants, which do not bind here).
  UPDATE public.profiles
     SET stripe_onboarding_complete = true,
         display_name = 'Seller S', full_name = 'SELLER PRIVATE',
         phone_number = '+13055550001', bio = 'seller bio'
   WHERE id = tap.seller();
  UPDATE public.profiles
     SET display_name = 'Buyer B', full_name = 'BUYER PRIVATE',
         phone_number = '+13055550002'
   WHERE id = tap.buyer();
  UPDATE public.profiles SET display_name = 'Other O' WHERE id = tap.other_user();

  -- Admin allowlist (service-path write; clients are proven unable in 080).
  INSERT INTO public.admin_users (user_id, label)
  VALUES (tap.admin_user(), 'TEST ADMIN')
  ON CONFLICT (user_id) DO NOTHING;

  -- Listings.
  INSERT INTO public.listings
    (id, seller_id, event_name, venue, neighborhood, event_date, event_time,
     ticket_type, quantity, transfer_method, starting_bid, buy_now_enabled,
     buy_now_price, duration_hours, starts_at, ends_at, current_bid,
     cover_image_path, auction_status)
  VALUES
    (tap.listing_a(), tap.seller(), 'Fixture Event A', 'Club A', 'wynwood',  current_date + 30, '21:00', 'GA', 2, 'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/a.jpg', 'active'),
    (tap.listing_b(), tap.seller(), 'Fixture Event B', 'Club B', 'brickell', current_date + 30, '22:00', 'GA', 2, 'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/b.jpg', 'active'),
    (tap.listing_c(), tap.seller(), 'Fixture Event C', 'Club C', 'wynwood',  current_date + 30, '23:00', 'GA', 2, 'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/c.jpg', 'cancelled'),
    (tap.listing_d(), tap.seller(), 'Fixture Event D', 'Club D', 'brickell', current_date + 30, '20:00', 'GA', 2, 'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/d.jpg', 'active');

  -- Payments (cents; 10/10 fee model shape).
  INSERT INTO public.payments
    (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total,
     stripe_payment_intent_id, status, mode, paid_at)
  VALUES
    (tap.payment_a(), tap.listing_a(), tap.buyer(), tap.seller(), 10000, 1000, 1000, 11000, 'pi_fixture_a', 'succeeded', 'buy_now', now()),
    (tap.payment_b(), tap.listing_b(), tap.buyer(), tap.seller(), 10000, 1000, 1000, 11000, 'pi_fixture_b', 'succeeded', 'buy_now', now()),
    (tap.payment_d(), tap.listing_d(), tap.buyer(), tap.seller(), 10000, 1000, 1000, 11000, 'pi_fixture_d', 'pending',   'buy_now', NULL);

  -- Transfers. A: pending (custody tests walk it). B: seller_sent with
  -- evidence (payout + append-only tests).
  INSERT INTO public.transfers
    (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status,
     seller_sent_at, auto_release_at, transfer_evidence_path, expires_at)
  VALUES
    (tap.transfer_a(), tap.listing_a(), tap.payment_a(), tap.seller(), tap.buyer(), 'mobile_transfer', 'pending',     NULL,  NULL,                    NULL,                        now() + interval '24 hours'),
    (tap.transfer_b(), tap.listing_b(), tap.payment_b(), tap.seller(), tap.buyer(), 'mobile_transfer', 'seller_sent', now(), now() + interval '72 hours', 'fixtures/evidence-b.jpg', now() + interval '24 hours');
END $$;

GRANT USAGE ON SCHEMA tap TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA tap TO PUBLIC;

-- ── Sanity plan: prove the harness itself installed ─────────────────────────
SELECT plan(6);

SELECT has_function('tap'::name, 'login'::name,         ARRAY['uuid'],  'tap.login(uuid) exists');
SELECT has_function('tap'::name, 'login_anon'::name,    '{}'::name[],   'tap.login_anon() exists');
SELECT has_function('tap'::name, 'login_service'::name, '{}'::name[],   'tap.login_service() exists');
SELECT has_function('tap'::name, 'logout'::name,        '{}'::name[],   'tap.logout() exists');
SELECT has_function('tap'::name, 'seed_core'::name,     '{}'::name[],   'tap.seed_core() exists');
-- The fail-open service-path nuance the whole harness is built around:
SELECT ok(
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public' AND p.proname = 'request_is_service_role'),
  'request_is_service_role() exists — claims MUST be set in every authenticated test');

SELECT * FROM finish();

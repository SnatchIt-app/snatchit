-- ===========================================================================
-- admin/scripts/fixtures.sql — TEST HARNESS ONLY. SYNTHETIC DATA.
--
-- Seeds the LOCAL rehearsal database (snatchit_rehearsal_admin) with fake
-- accounts, listings, payments, transfers, disputes, reports, flags, webhook
-- events and risk scores so the admin console can be exercised end-to-end
-- against a Supabase-shaped API (admin/scripts/local-stack.sh).
--
--   * Idempotent: every insert is ON CONFLICT DO NOTHING (fixed UUIDs).
--   * Emails are *.example.test, Stripe ids are pi_test_/tr_test_/dp_test_/
--     evt_test_/acct_test_. Passwords are plain text in ops_harness.accounts.
--   * ops_harness is a HARNESS-ONLY schema. It is never part of
--     supabase/migrations and must never exist in staging/production.
--   * Applied by local-stack.sh with psql as `postgres` and no request.jwt
--     claims, which is the "direct admin connection" ALLOW path of the
--     listings insert/proof_status guards. Transfers are inserted directly
--     in their final state (the transfer state guard fires on UPDATE only);
--     the bypass GUCs are still armed for parity with supabase/tests
--     (000_helpers.sql / 141_*) in case a later edit adds an UPDATE.
--   * Refuses to run anywhere but a loopback server on a database whose
--     name contains 'rehears'.
--
-- Accounts (password for all: harness-pass-123; MFA code: 123456)
--   founder.a@example.test  f0000000-0000-4000-8000-0000000000a1  admin_users, aal1 (enrol MFA in-app)
--   founder.b@example.test  f0000000-0000-4000-8000-0000000000a2  admin_users, aal2 (pre-verified factor)
--   support@example.test    f0000000-0000-4000-8000-0000000000a3  NOT an admin (denied path)
--   buyer1@example.test     b0000000-0000-4000-8000-000000000001  plain user
--   buyer2/buyer3, seller1/seller2/seller3 (seller3 is listing-blocked)
-- ===========================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;  -- quiet IF NOT EXISTS notices

-- --- 0. Safety --------------------------------------------------------------
DO $guard$
DECLARE v_addr text; v_supa int;
BEGIN
  v_addr := coalesce(host(inet_server_addr()), 'socket');
  IF v_addr NOT IN ('socket', '127.0.0.1', '::1') THEN
    RAISE EXCEPTION 'fixtures.sql: server address % is not loopback — refusing', v_addr;
  END IF;
  IF current_database() NOT LIKE '%rehears%' THEN
    RAISE EXCEPTION 'fixtures.sql: database % does not contain ''rehears'' — refusing', current_database();
  END IF;
  SELECT count(*) INTO v_supa FROM pg_roles WHERE rolname IN ('supabase_admin','supabase_replication_admin');
  IF v_supa > 0 THEN
    RAISE EXCEPTION 'fixtures.sql: this server carries Supabase platform roles — refusing';
  END IF;
END $guard$;

BEGIN;

-- Parity with supabase/tests: arm the guard bypasses for this transaction.
DO $$ BEGIN
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  PERFORM set_config('app.bypass_listing_guard',  'on', true);
END $$;

-- --- 1. Harness-only schema -------------------------------------------------
CREATE SCHEMA IF NOT EXISTS ops_harness;
COMMENT ON SCHEMA ops_harness IS 'TEST HARNESS ONLY — synthetic auth fixtures for admin/scripts/auth-stub.mjs. Never in migrations.';

CREATE TABLE IF NOT EXISTS ops_harness.accounts (
  email          text PRIMARY KEY,
  password_plain text NOT NULL,
  user_id        uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  aal            text NOT NULL DEFAULT 'aal1' CHECK (aal IN ('aal1','aal2')),
  label          text NOT NULL DEFAULT ''
);
COMMENT ON TABLE ops_harness.accounts IS 'TEST HARNESS — plain-text synthetic logins. aal = level minted at password login.';

CREATE TABLE IF NOT EXISTS ops_harness.factors (
  id            uuid PRIMARY KEY,
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  friendly_name text NOT NULL,
  factor_type   text NOT NULL DEFAULT 'totp',
  status        text NOT NULL DEFAULT 'unverified' CHECK (status IN ('unverified','verified')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ops_harness.factors IS 'TEST HARNESS — fake TOTP factors (any challenge verifies with code 123456).';

-- --- 2. auth.users (rehearsal stub column set) ------------------------------
-- handle_new_user() trigger creates the profiles row; we upsert profile detail below.
INSERT INTO auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) VALUES
  ('f0000000-0000-4000-8000-0000000000a1','authenticated','authenticated','founder.a@example.test','$harness$not-a-real-hash', now() - interval '400 days', '{"provider":"email","providers":["email"]}', '{"harness":true}', now() - interval '400 days', now() - interval '1 day'),
  ('f0000000-0000-4000-8000-0000000000a2','authenticated','authenticated','founder.b@example.test','$harness$not-a-real-hash', now() - interval '400 days', '{"provider":"email","providers":["email"]}', '{"harness":true}', now() - interval '400 days', now() - interval '1 day'),
  ('f0000000-0000-4000-8000-0000000000a3','authenticated','authenticated','support@example.test',  '$harness$not-a-real-hash', now() - interval '90 days',  '{"provider":"email","providers":["email"]}', '{"harness":true}', now() - interval '90 days',  now() - interval '1 day'),
  ('b0000000-0000-4000-8000-000000000001','authenticated','authenticated','buyer1@example.test',   '$harness$not-a-real-hash', now() - interval '120 days', '{"provider":"email","providers":["email"]}', '{"harness":true}', now() - interval '120 days', now()),
  ('b0000000-0000-4000-8000-000000000002','authenticated','authenticated','buyer2@example.test',   '$harness$not-a-real-hash', now() - interval '60 days',  '{"provider":"email","providers":["email"]}', '{"harness":true}', now() - interval '60 days',  now()),
  ('b0000000-0000-4000-8000-000000000003','authenticated','authenticated','buyer3@example.test',   '$harness$not-a-real-hash', now() - interval '5 days',   '{"provider":"email","providers":["email"]}', '{"harness":true}', now() - interval '5 days',   now()),
  ('5e11e000-0000-4000-8000-000000000001','authenticated','authenticated','seller1@example.test',  '$harness$not-a-real-hash', now() - interval '300 days', '{"provider":"email","providers":["email"]}', '{"harness":true}', now() - interval '300 days', now()),
  ('5e11e000-0000-4000-8000-000000000002','authenticated','authenticated','seller2@example.test',  '$harness$not-a-real-hash', now() - interval '45 days',  '{"provider":"email","providers":["email"]}', '{"harness":true}', now() - interval '45 days',  now()),
  ('5e11e000-0000-4000-8000-000000000003','authenticated','authenticated','seller3@example.test',  '$harness$not-a-real-hash', now() - interval '12 days',  '{"provider":"email","providers":["email"]}', '{"harness":true}', now() - interval '12 days',  now())
ON CONFLICT (id) DO NOTHING;

-- --- 3. profiles (rows exist via handle_new_user; fill details) --------------
INSERT INTO public.profiles (id) SELECT id FROM auth.users WHERE email LIKE '%@example.test' ON CONFLICT (id) DO NOTHING;
UPDATE public.profiles p SET
  full_name    = v.full_name,
  display_name = v.display_name,
  is_verified_seller = v.seller,
  is_verified_buyer  = true,
  stripe_connect_id  = CASE WHEN v.seller THEN coalesce(p.stripe_connect_id, v.acct) END,
  stripe_onboarding_complete = v.seller AND v.onboarded,
  stripe_customer_id = coalesce(p.stripe_customer_id, v.cus)
FROM (VALUES
  ('f0000000-0000-4000-8000-0000000000a1'::uuid,'Founder A (synthetic)','founder_a', false, NULL, false, NULL),
  ('f0000000-0000-4000-8000-0000000000a2','Founder B (synthetic)','founder_b', false, NULL, false, NULL),
  ('f0000000-0000-4000-8000-0000000000a3','Support Agent (synthetic)','support_agent', false, NULL, false, NULL),
  ('b0000000-0000-4000-8000-000000000001','Buyer One (synthetic)','buyer_one', false, NULL, false, 'cus_test_buyer1'),
  ('b0000000-0000-4000-8000-000000000002','Buyer Two (synthetic)','buyer_two', false, NULL, false, 'cus_test_buyer2'),
  ('b0000000-0000-4000-8000-000000000003','Buyer Three (synthetic)','buyer_three', false, NULL, false, 'cus_test_buyer3'),
  ('5e11e000-0000-4000-8000-000000000001','Seller One (synthetic)','seller_one', true, 'acct_test_seller1', true, NULL),
  ('5e11e000-0000-4000-8000-000000000002','Seller Two (synthetic)','seller_two', true, 'acct_test_seller2', true, NULL),
  ('5e11e000-0000-4000-8000-000000000003','Seller Three (synthetic)','seller_three', true, NULL, false, NULL)
) AS v(id, full_name, display_name, seller, acct, onboarded, cus)
WHERE p.id = v.id AND p.full_name IS NULL;

-- --- 4. Admin authority: founders ONLY (support deliberately absent) ---------
INSERT INTO public.admin_users (user_id, label) VALUES
  ('f0000000-0000-4000-8000-0000000000a1', 'founder A (synthetic)'),
  ('f0000000-0000-4000-8000-0000000000a2', 'founder B (synthetic)')
ON CONFLICT (user_id) DO NOTHING;

-- --- 5. Harness logins ------------------------------------------------------
INSERT INTO ops_harness.accounts (email, password_plain, user_id, aal, label) VALUES
  ('founder.a@example.test', 'harness-pass-123', 'f0000000-0000-4000-8000-0000000000a1', 'aal1', 'platform_admin via admin_users; no factor yet -> enrol in-app'),
  ('founder.b@example.test', 'harness-pass-123', 'f0000000-0000-4000-8000-0000000000a2', 'aal2', 'platform_admin via admin_users; aal2 pre-verified'),
  ('support@example.test',   'harness-pass-123', 'f0000000-0000-4000-8000-0000000000a3', 'aal2', 'NOT in admin_users — denied-path testing'),
  ('buyer1@example.test',    'harness-pass-123', 'b0000000-0000-4000-8000-000000000001', 'aal1', 'plain marketplace user')
ON CONFLICT (email) DO NOTHING;

-- Founder B and support carry a verified factor so supabase-js reports nextLevel=aal2.
INSERT INTO ops_harness.factors (id, user_id, friendly_name, factor_type, status) VALUES
  ('fac70000-0000-4000-8000-0000000000a2', 'f0000000-0000-4000-8000-0000000000a2', 'Founder B phone (synthetic)', 'totp', 'verified'),
  ('fac70000-0000-4000-8000-0000000000a3', 'f0000000-0000-4000-8000-0000000000a3', 'Support phone (synthetic)',   'totp', 'verified')
ON CONFLICT (id) DO NOTHING;

-- --- 6. Listings (15) -------------------------------------------------------
-- L01 active auction w/ bids | L02 active buy-now, reserved (pending payment)
-- L03..L13 sold (one transfer each) | L14 cancelled | L15 active buy-now by blocked seller
INSERT INTO public.listings
  (id, created_at, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity,
   transfer_method, starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid,
   cover_image_path, status, reserved_by, reserved_until, sold_at, auction_status, winner_user_id, winning_bid_amount,
   ended_at, bid_count, highest_bidder_id, ticket_platform, category, proof_status)
VALUES
  ('11570000-0000-4000-8000-000000000001', now() - interval '5 hours', '5e11e000-0000-4000-8000-000000000001', 'Synthetic Fest — Night 1', 'Test Arena', 'wynwood', current_date + 9, '22:00', 'GA', 2,
   'mobile_transfer', 4000, false, NULL, 24, now() - interval '5 hours', now() + interval '19 hours', 6500,
   'harness/l01.jpg', 'active', NULL, NULL, NULL, 'active', NULL, NULL, NULL, 4, 'b0000000-0000-4000-8000-000000000001', 'dice', 'festivals', 'approved'),
  ('11570000-0000-4000-8000-000000000002', now() - interval '2 hours', '5e11e000-0000-4000-8000-000000000002', 'Rooftop Test Session', 'Harness Rooftop', 'brickell', current_date + 3, '21:00', 'VIP', 1,
   'email', 8000, true, 12000, 12, now() - interval '2 hours', now() + interval '10 hours', 8000,
   'harness/l02.jpg', 'reserved', 'b0000000-0000-4000-8000-000000000002', now() + interval '10 minutes', NULL, 'active', NULL, NULL, NULL, 0, NULL, 'posh', 'nightlife', 'approved'),
  ('11570000-0000-4000-8000-000000000003', now() - interval '1 day', '5e11e000-0000-4000-8000-000000000001', 'Test Club Friday', 'Harness Club', 'south beach', current_date + 1, '23:00', 'GA', 2,
   'mobile_transfer', 5000, true, 7500, 24, now() - interval '1 day', now() - interval '3 hours', 7500,
   'harness/l03.jpg', 'sold', 'b0000000-0000-4000-8000-000000000001', NULL, now() - interval '3 hours', 'sold', 'b0000000-0000-4000-8000-000000000001', 7500,
   now() - interval '3 hours', 0, NULL, 'eventbrite', 'clubs', 'approved'),
  ('11570000-0000-4000-8000-000000000004', now() - interval '2 days', '5e11e000-0000-4000-8000-000000000002', 'Overdue Transfer Show', 'Test Theater', 'downtown miami', current_date + 2, '20:00', 'GA', 1,
   'email', 3000, true, 4500, 24, now() - interval '2 days', now() - interval '26 hours', 4500,
   'harness/l04.jpg', 'sold', 'b0000000-0000-4000-8000-000000000002', NULL, now() - interval '25 hours', 'sold', 'b0000000-0000-4000-8000-000000000002', 4500,
   now() - interval '25 hours', 0, NULL, 'ticketmaster', 'concerts', 'approved'),
  ('11570000-0000-4000-8000-000000000005', now() - interval '3 days', '5e11e000-0000-4000-8000-000000000003', 'High-Risk Seller Gig', 'Harness Hall', 'midtown', current_date + 4, '19:30', 'VIP', 2,
   'mobile_transfer', 9000, false, NULL, 48, now() - interval '3 days', now() - interval '1 day', 15000,
   'harness/l05.jpg', 'sold', NULL, NULL, now() - interval '20 hours', 'sold', 'b0000000-0000-4000-8000-000000000003', 15000,
   now() - interval '1 day', 7, 'b0000000-0000-4000-8000-000000000003', 'axs', 'music', 'pending_review'),
  ('11570000-0000-4000-8000-000000000006', now() - interval '3 days', '5e11e000-0000-4000-8000-000000000001', 'Held Payout Matinee', 'Test Arena', 'wynwood', current_date + 6, '15:00', 'GA', 4,
   'email', 2000, true, 3000, 24, now() - interval '3 days', now() - interval '2 days', 3000,
   'harness/l06.jpg', 'sold', 'b0000000-0000-4000-8000-000000000002', NULL, now() - interval '2 days', 'sold', 'b0000000-0000-4000-8000-000000000002', 3000,
   now() - interval '2 days', 0, NULL, 'seatgeek', 'sports', 'approved'),
  ('11570000-0000-4000-8000-000000000007', now() - interval '6 days', '5e11e000-0000-4000-8000-000000000002', 'Released Payout Night', 'Harness Club', 'south beach', current_date - 2, '23:00', 'TABLE', 1,
   'mobile_transfer', 20000, true, 25000, 24, now() - interval '6 days', now() - interval '5 days', 25000,
   'harness/l07.jpg', 'sold', 'b0000000-0000-4000-8000-000000000001', NULL, now() - interval '5 days', 'sold', 'b0000000-0000-4000-8000-000000000001', 25000,
   now() - interval '5 days', 0, NULL, 'tixr', 'nightlife', 'approved'),
  ('11570000-0000-4000-8000-000000000008', now() - interval '2 days', '5e11e000-0000-4000-8000-000000000001', 'Confirmed But Unpaid Set', 'Test Theater', 'design district', current_date + 1, '21:30', 'GA', 2,
   'email', 3500, false, NULL, 24, now() - interval '2 days', now() - interval '1 day', 5200,
   'harness/l08.jpg', 'sold', NULL, NULL, now() - interval '22 hours', 'sold', 'b0000000-0000-4000-8000-000000000003', 5200,
   now() - interval '1 day', 3, 'b0000000-0000-4000-8000-000000000003', 'fever', 'special_events', 'approved'),
  ('11570000-0000-4000-8000-000000000009', now() - interval '4 days', '5e11e000-0000-4000-8000-000000000003', 'Disputed Delivery Show', 'Harness Hall', 'midtown', current_date - 1, '20:00', 'GA', 2,
   'mobile_transfer', 6000, true, 9000, 24, now() - interval '4 days', now() - interval '3 days', 9000,
   'harness/l09.jpg', 'sold', 'b0000000-0000-4000-8000-000000000001', NULL, now() - interval '3 days', 'sold', 'b0000000-0000-4000-8000-000000000001', 9000,
   now() - interval '3 days', 0, NULL, 'shotgun', 'music', 'approved'),
  ('11570000-0000-4000-8000-000000000010', now() - interval '5 days', '5e11e000-0000-4000-8000-000000000002', 'Buyer-Win Refund Pending', 'Test Arena', 'wynwood', current_date - 2, '19:00', 'VIP', 1,
   'email', 10000, true, 14000, 24, now() - interval '5 days', now() - interval '4 days', 14000,
   'harness/l10.jpg', 'sold', 'b0000000-0000-4000-8000-000000000002', NULL, now() - interval '4 days', 'sold', 'b0000000-0000-4000-8000-000000000002', 14000,
   now() - interval '4 days', 0, NULL, 'dice', 'concerts', 'approved'),
  ('11570000-0000-4000-8000-000000000011', now() - interval '4 days', '5e11e000-0000-4000-8000-000000000003', 'Expired Not Refunded', 'Harness Rooftop', 'brickell', current_date + 1, '22:00', 'GA', 3,
   'mobile_transfer', 2500, true, 4000, 24, now() - interval '4 days', now() - interval '3 days', 4000,
   'harness/l11.jpg', 'sold', 'b0000000-0000-4000-8000-000000000003', NULL, now() - interval '3 days', 'sold', 'b0000000-0000-4000-8000-000000000003', 4000,
   now() - interval '3 days', 0, NULL, 'universe', 'nightlife', 'approved'),
  ('11570000-0000-4000-8000-000000000012', now() - interval '3 days', '5e11e000-0000-4000-8000-000000000001', 'Auto-Released Stuck Payout', 'Test Theater', 'downtown miami', current_date + 2, '20:30', 'GA', 2,
   'email', 4500, true, 6000, 24, now() - interval '3 days', now() - interval '2 days', 6000,
   'harness/l12.jpg', 'sold', 'b0000000-0000-4000-8000-000000000001', NULL, now() - interval '2 days', 'sold', 'b0000000-0000-4000-8000-000000000001', 6000,
   now() - interval '2 days', 0, NULL, 'see_tickets', 'clubs', 'approved'),
  ('11570000-0000-4000-8000-000000000013', now() - interval '8 days', '5e11e000-0000-4000-8000-000000000002', 'Expired And Refunded (healthy)', 'Harness Club', 'coconut grove', current_date - 3, '21:00', 'GA', 1,
   'mobile_transfer', 3000, true, 4000, 24, now() - interval '8 days', now() - interval '7 days', 4000,
   'harness/l13.jpg', 'sold', 'b0000000-0000-4000-8000-000000000003', NULL, now() - interval '7 days', 'sold', 'b0000000-0000-4000-8000-000000000003', 4000,
   now() - interval '7 days', 0, NULL, 'stubhub', 'other', 'approved'),
  ('11570000-0000-4000-8000-000000000014', now() - interval '1 day', '5e11e000-0000-4000-8000-000000000001', 'Cancelled Listing', 'Test Arena', 'little havana', current_date + 5, '18:00', 'GA', 2,
   'email', 3000, false, NULL, 6, now() - interval '1 day', now() - interval '18 hours', 3000,
   'harness/l14.jpg', 'active', NULL, NULL, NULL, 'cancelled', NULL, NULL, now() - interval '20 hours', 0, NULL, 'other', 'nightlife', 'rejected'),
  ('11570000-0000-4000-8000-000000000015', now() - interval '30 minutes', '5e11e000-0000-4000-8000-000000000003', 'Reported Suspicious Listing', 'Harness Hall', 'miami beach', current_date + 7, '22:00', 'VIP', 6,
   'mobile_transfer', 1000, true, 1500, 48, now() - interval '30 minutes', now() + interval '47 hours', 1000,
   'harness/l15.jpg', 'active', NULL, NULL, NULL, 'active', NULL, NULL, NULL, 0, NULL, 'vivid_seats', 'festivals', 'pending_review')
ON CONFLICT (id) DO NOTHING;

-- --- 7. Payments (13): 10 succeeded, 1 refunded, 1 pending, 1 failed --------
-- amount = ticket price, buyer_fee 10%, seller_fee 10%, total = amount + buyer_fee (cents)
INSERT INTO public.payments
  (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, payment_method, mode, created_at, paid_at, failed_at, refunded_at, stripe_refund_id, stripe_livemode)
VALUES
  ('9a900000-0000-4000-8000-000000000003','11570000-0000-4000-8000-000000000003','b0000000-0000-4000-8000-000000000001','5e11e000-0000-4000-8000-000000000001', 7500, 750, 750, 8250,'pi_test_000003','succeeded','card','buy_now', now() - interval '3 hours', now() - interval '3 hours', NULL, NULL, NULL, false),
  ('9a900000-0000-4000-8000-000000000004','11570000-0000-4000-8000-000000000004','b0000000-0000-4000-8000-000000000002','5e11e000-0000-4000-8000-000000000002', 4500, 450, 450, 4950,'pi_test_000004','succeeded','card','buy_now', now() - interval '25 hours', now() - interval '25 hours', NULL, NULL, NULL, false),
  ('9a900000-0000-4000-8000-000000000005','11570000-0000-4000-8000-000000000005','b0000000-0000-4000-8000-000000000003','5e11e000-0000-4000-8000-000000000003',15000,1500,1500,16500,'pi_test_000005','succeeded','card','auction', now() - interval '20 hours', now() - interval '20 hours', NULL, NULL, NULL, false),
  ('9a900000-0000-4000-8000-000000000006','11570000-0000-4000-8000-000000000006','b0000000-0000-4000-8000-000000000002','5e11e000-0000-4000-8000-000000000001', 3000, 300, 300, 3300,'pi_test_000006','succeeded','card','buy_now', now() - interval '2 days', now() - interval '2 days', NULL, NULL, NULL, false),
  ('9a900000-0000-4000-8000-000000000007','11570000-0000-4000-8000-000000000007','b0000000-0000-4000-8000-000000000001','5e11e000-0000-4000-8000-000000000002',25000,2500,2500,27500,'pi_test_000007','succeeded','card','buy_now', now() - interval '5 days', now() - interval '5 days', NULL, NULL, NULL, false),
  ('9a900000-0000-4000-8000-000000000008','11570000-0000-4000-8000-000000000008','b0000000-0000-4000-8000-000000000003','5e11e000-0000-4000-8000-000000000001', 5200, 520, 520, 5720,'pi_test_000008','succeeded','card','auction', now() - interval '22 hours', now() - interval '22 hours', NULL, NULL, NULL, false),
  ('9a900000-0000-4000-8000-000000000009','11570000-0000-4000-8000-000000000009','b0000000-0000-4000-8000-000000000001','5e11e000-0000-4000-8000-000000000003', 9000, 900, 900, 9900,'pi_test_000009','succeeded','card','buy_now', now() - interval '3 days', now() - interval '3 days', NULL, NULL, NULL, false),
  ('9a900000-0000-4000-8000-000000000010','11570000-0000-4000-8000-000000000010','b0000000-0000-4000-8000-000000000002','5e11e000-0000-4000-8000-000000000002',14000,1400,1400,15400,'pi_test_000010','succeeded','card','buy_now', now() - interval '4 days', now() - interval '4 days', NULL, NULL, NULL, false),
  ('9a900000-0000-4000-8000-000000000011','11570000-0000-4000-8000-000000000011','b0000000-0000-4000-8000-000000000003','5e11e000-0000-4000-8000-000000000003', 4000, 400, 400, 4400,'pi_test_000011','succeeded','card','buy_now', now() - interval '3 days', now() - interval '3 days', NULL, NULL, NULL, false),
  ('9a900000-0000-4000-8000-000000000012','11570000-0000-4000-8000-000000000012','b0000000-0000-4000-8000-000000000001','5e11e000-0000-4000-8000-000000000001', 6000, 600, 600, 6600,'pi_test_000012','succeeded','card','buy_now', now() - interval '2 days', now() - interval '2 days', NULL, NULL, NULL, false),
  ('9a900000-0000-4000-8000-000000000013','11570000-0000-4000-8000-000000000013','b0000000-0000-4000-8000-000000000003','5e11e000-0000-4000-8000-000000000002', 4000, 400, 400, 4400,'pi_test_000013','refunded', 'card','buy_now', now() - interval '7 days', now() - interval '7 days', NULL, now() - interval '5 days', 're_test_000013', false),
  ('9a900000-0000-4000-8000-000000000002','11570000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002','5e11e000-0000-4000-8000-000000000002',12000,1200,1200,13200,'pi_test_000002','pending',  NULL,  'buy_now', now() - interval '4 minutes', NULL, NULL, NULL, NULL, false),
  ('9a900000-0000-4000-8000-000000000001','11570000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000003','5e11e000-0000-4000-8000-000000000001', 6500, 650, 650, 7150,'pi_test_000001','failed',   'card','auction', now() - interval '40 minutes', NULL, now() - interval '39 minutes', NULL, NULL, false)
ON CONFLICT (id) DO NOTHING;

-- --- 8. Transfers (11) — every status ---------------------------------------
INSERT INTO public.transfers
  (id, created_at, listing_id, payment_id, seller_id, buyer_id, transfer_method, status,
   seller_sent_at, buyer_confirmed_at, expires_at, payout_released_at, stripe_transfer_id, expired_at, auto_release_at,
   disputed_at, delivery_email, delivery_phone, transfer_evidence_path, dispute_reason, dispute_evidence_path, dispute_notes,
   dispute_resolution, dispute_resolved_at, dispute_resolved_by, buyer_viewed_at, payout_hold_until, payout_risk_tier, payout_reason_codes, payout_review_status)
VALUES
  -- T03 pending, deadline in 2h
  ('7a000000-0000-4000-8000-000000000003', now() - interval '3 hours', '11570000-0000-4000-8000-000000000003','9a900000-0000-4000-8000-000000000003','5e11e000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','mobile_transfer','pending',
   NULL, NULL, now() + interval '2 hours', NULL, NULL, NULL, NULL,
   NULL, NULL, '+13055550101', NULL, NULL, NULL, NULL, NULL, NULL, NULL, now() - interval '2 hours', NULL, NULL, NULL, NULL),
  -- T04 pending, deadline already passed (overdue; expiry job has not run)
  ('7a000000-0000-4000-8000-000000000004', now() - interval '25 hours', '11570000-0000-4000-8000-000000000004','9a900000-0000-4000-8000-000000000004','5e11e000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002','email','pending',
   NULL, NULL, now() - interval '1 hour', NULL, NULL, NULL, NULL,
   NULL, 'buyer2@example.test', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
  -- T05 seller_sent, manual_review (high risk)
  ('7a000000-0000-4000-8000-000000000005', now() - interval '20 hours', '11570000-0000-4000-8000-000000000005','9a900000-0000-4000-8000-000000000005','5e11e000-0000-4000-8000-000000000003','b0000000-0000-4000-8000-000000000003','mobile_transfer','seller_sent',
   now() - interval '3 hours', NULL, now() + interval '4 hours', NULL, NULL, NULL, now() + interval '21 hours',
   NULL, NULL, '+13055550103', 'harness/evidence/t05.jpg', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'high', ARRAY['new_account','high_value','unverified_proof'], 'manual_review'),
  -- T06 seller_sent, held (medium risk) until event-relative safe point
  ('7a000000-0000-4000-8000-000000000006', now() - interval '2 days', '11570000-0000-4000-8000-000000000006','9a900000-0000-4000-8000-000000000006','5e11e000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000002','email','seller_sent',
   now() - interval '40 hours', NULL, now() - interval '1 day', NULL, NULL, NULL, now() + interval '2 days',
   NULL, 'buyer2@example.test', NULL, 'harness/evidence/t06.jpg', NULL, NULL, NULL, NULL, NULL, NULL, now() - interval '30 hours', now() + interval '2 days', 'medium', ARRAY['event_far_out'], 'held'),
  -- T07 buyer_confirmed, payout released (stripe transfer id present)
  ('7a000000-0000-4000-8000-000000000007', now() - interval '5 days', '11570000-0000-4000-8000-000000000007','9a900000-0000-4000-8000-000000000007','5e11e000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001','mobile_transfer','buyer_confirmed',
   now() - interval '4 days 20 hours', now() - interval '4 days 18 hours', now() - interval '4 days', now() - interval '4 days 17 hours', 'tr_test_000007', NULL, now() - interval '3 days 20 hours',
   NULL, NULL, '+13055550101', 'harness/evidence/t07.jpg', NULL, NULL, NULL, NULL, NULL, NULL, now() - interval '4 days 19 hours', NULL, 'low', ARRAY[]::text[], NULL),
  -- T08 buyer_confirmed 2h ago, NO stripe transfer id (release stuck)
  ('7a000000-0000-4000-8000-000000000008', now() - interval '22 hours', '11570000-0000-4000-8000-000000000008','9a900000-0000-4000-8000-000000000008','5e11e000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000003','email','buyer_confirmed',
   now() - interval '5 hours', now() - interval '2 hours', now() + interval '2 hours', NULL, NULL, NULL, now() + interval '19 hours',
   NULL, 'buyer3@example.test', NULL, 'harness/evidence/t08.jpg', NULL, NULL, NULL, NULL, NULL, NULL, now() - interval '3 hours', NULL, 'low', ARRAY[]::text[], NULL),
  -- T09 disputed, open (never_received), 1 day old
  ('7a000000-0000-4000-8000-000000000009', now() - interval '3 days', '11570000-0000-4000-8000-000000000009','9a900000-0000-4000-8000-000000000009','5e11e000-0000-4000-8000-000000000003','b0000000-0000-4000-8000-000000000001','mobile_transfer','disputed',
   now() - interval '2 days', NULL, now() - interval '2 days', NULL, NULL, NULL, now() - interval '1 day',
   now() - interval '1 day', NULL, '+13055550101', 'harness/evidence/t09.jpg', 'never_received', 'harness/dispute/t09.jpg', 'Buyer says nothing arrived (synthetic).', NULL, NULL, NULL, now() - interval '47 hours', NULL, 'high', ARRAY['dispute_open'], NULL),
  -- T10 disputed, resolved buyer_win 6h ago, payment still succeeded -> refund pending
  ('7a000000-0000-4000-8000-000000000010', now() - interval '4 days', '11570000-0000-4000-8000-000000000010','9a900000-0000-4000-8000-000000000010','5e11e000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002','email','disputed',
   now() - interval '3 days 12 hours', NULL, now() - interval '3 days', NULL, NULL, NULL, now() - interval '2 days 12 hours',
   now() - interval '2 days', 'buyer2@example.test', NULL, 'harness/evidence/t10.jpg', 'invalid_tickets', 'harness/dispute/t10.jpg', 'Barcode rejected at door (synthetic).', 'resolved_buyer_refunded', now() - interval '6 hours', 'f0000000-0000-4000-8000-0000000000a2', now() - interval '3 days 11 hours', NULL, 'medium', ARRAY['dispute_open'], NULL),
  -- T11 expired, payment succeeded and NOT refunded (refund pending)
  ('7a000000-0000-4000-8000-000000000011', now() - interval '3 days', '11570000-0000-4000-8000-000000000011','9a900000-0000-4000-8000-000000000011','5e11e000-0000-4000-8000-000000000003','b0000000-0000-4000-8000-000000000003','mobile_transfer','expired',
   NULL, NULL, now() - interval '2 days', NULL, NULL, now() - interval '1 day', NULL,
   NULL, NULL, '+13055550103', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
  -- T12 auto_released 2h ago, no stripe transfer id yet (release stuck)
  ('7a000000-0000-4000-8000-000000000012', now() - interval '2 days', '11570000-0000-4000-8000-000000000012','9a900000-0000-4000-8000-000000000012','5e11e000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000001','email','auto_released',
   now() - interval '26 hours', NULL, now() - interval '1 day', NULL, NULL, NULL, now() - interval '2 hours',
   NULL, 'buyer1@example.test', NULL, 'harness/evidence/t12.jpg', NULL, NULL, NULL, NULL, NULL, NULL, now() - interval '25 hours', NULL, 'low', ARRAY[]::text[], NULL),
  -- T13 expired and refunded (healthy reference case)
  ('7a000000-0000-4000-8000-000000000013', now() - interval '7 days', '11570000-0000-4000-8000-000000000013','9a900000-0000-4000-8000-000000000013','5e11e000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000003','mobile_transfer','expired',
   NULL, NULL, now() - interval '6 days', NULL, NULL, now() - interval '5 days', NULL,
   NULL, NULL, '+13055550103', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL)
ON CONFLICT (id) DO NOTHING;

-- --- 9. Stripe disputes (chargebacks) ---------------------------------------
INSERT INTO public.disputes (id, stripe_dispute_id, stripe_charge_id, stripe_pi_id, payment_id, transfer_id, amount, currency, reason, status, evidence_due_by, created_at)
VALUES
  ('d1590000-0000-4000-8000-000000000009', 'dp_test_000009', 'ch_test_000009', 'pi_test_000009', '9a900000-0000-4000-8000-000000000009', '7a000000-0000-4000-8000-000000000009', 9900, 'usd', 'product_not_received', 'needs_response', now() + interval '2 days', now() - interval '20 hours'),
  ('d1590000-0000-4000-8000-000000000007', 'dp_test_000007', 'ch_test_000007', 'pi_test_000007', '9a900000-0000-4000-8000-000000000007', '7a000000-0000-4000-8000-000000000007', 27500, 'usd', 'fraudulent', 'won', now() - interval '10 days', now() - interval '3 days')
ON CONFLICT (id) DO NOTHING;

-- --- 10. Reports: 3 pending + 1 dismissed -----------------------------------
INSERT INTO public.reports (id, reporter_id, target_type, target_id, reason, notes, status, created_at, resolved_at) VALUES
  ('4e900000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001', 'listing', '11570000-0000-4000-8000-000000000015', 'fraud_or_scam', 'Six VIP tickets at $15 each looks fake (synthetic).', 'pending', now() - interval '20 minutes', NULL),
  ('4e900000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-000000000002', 'user',    '5e11e000-0000-4000-8000-000000000003', 'harassment',    'Seller sent abusive messages after dispute (synthetic).', 'pending', now() - interval '6 hours', NULL),
  ('4e900000-0000-4000-8000-000000000003', 'b0000000-0000-4000-8000-000000000003', 'listing', '11570000-0000-4000-8000-000000000001', 'misleading',    'Event date on the ticket differs from the listing (synthetic).', 'pending', now() - interval '2 days', NULL),
  ('4e900000-0000-4000-8000-000000000004', 'b0000000-0000-4000-8000-000000000001', 'listing', '11570000-0000-4000-8000-000000000014', 'other',         'Duplicate of another listing (synthetic).', 'dismissed', now() - interval '3 days', now() - interval '2 days')
ON CONFLICT (id) DO NOTHING;

-- --- 11. Seller flags --------------------------------------------------------
INSERT INTO public.seller_flags (id, created_at, seller_id, flag_type, severity, details, listing_id, transfer_id, reviewed_at, reviewed_by, resolution, resolution_notes) VALUES
  ('f1a90000-0000-4000-8000-000000000001', now() - interval '1 day',  '5e11e000-0000-4000-8000-000000000003', 'high_dispute_rate',      'critical', '2 disputes on 4 completed transfers (synthetic).', NULL, '7a000000-0000-4000-8000-000000000009', NULL, NULL, NULL, NULL),
  ('f1a90000-0000-4000-8000-000000000002', now() - interval '1 day',  '5e11e000-0000-4000-8000-000000000003', 'repeated_expiry',        'warning',  'Second expired transfer in 14 days (synthetic).', '11570000-0000-4000-8000-000000000011', '7a000000-0000-4000-8000-000000000011', NULL, NULL, NULL, NULL),
  ('f1a90000-0000-4000-8000-000000000003', now() - interval '30 minutes', '5e11e000-0000-4000-8000-000000000003', 'new_account_high_value', 'warning', 'Account 12 days old listing 6x VIP (synthetic).', '11570000-0000-4000-8000-000000000015', NULL, NULL, NULL, NULL, NULL),
  ('f1a90000-0000-4000-8000-000000000004', now() - interval '3 days',  '5e11e000-0000-4000-8000-000000000001', 'rapid_send',             'info',     'Marked sent 40s after sale (synthetic).', '11570000-0000-4000-8000-000000000006', '7a000000-0000-4000-8000-000000000006', now() - interval '2 days', 'f0000000-0000-4000-8000-0000000000a1', 'dismissed', 'Long-standing seller, evidence attached (synthetic).')
ON CONFLICT (id) DO NOTHING;

-- --- 12. Dispute resolutions (append-only table; insert only) ---------------
INSERT INTO public.dispute_resolutions (id, transfer_id, outcome, resolution, refund_required, actor_id, reason, notes, previous_status, new_status, payout_unfrozen, created_at) VALUES
  ('de500000-0000-4000-8000-000000000010', '7a000000-0000-4000-8000-000000000010', 'buyer_win', 'resolved_buyer_refunded', true, 'f0000000-0000-4000-8000-0000000000a2', 'invalid_tickets confirmed by venue', 'Refund via Stripe dashboard SOP pending (synthetic).', 'disputed', 'disputed', false, now() - interval '6 hours')
ON CONFLICT (id) DO NOTHING;

-- --- 13. Payout decisions ----------------------------------------------------
INSERT INTO public.payout_decisions (id, transfer_id, payment_id, seller_id, buyer_id, risk_tier, decision, reason_codes, evidence, buyer_confirmed, dispute_open, event_date, hold_until, actor, decided_at) VALUES
  ('9d000000-0000-4000-8000-000000000005', '7a000000-0000-4000-8000-000000000005', '9a900000-0000-4000-8000-000000000005', '5e11e000-0000-4000-8000-000000000003', 'b0000000-0000-4000-8000-000000000003', 'high',   'manual_review', ARRAY['new_account','high_value','unverified_proof'], '{"synthetic":true,"account_age_days":12}', false, false, current_date + 4, NULL, 'seller-mark-sent', now() - interval '3 hours'),
  ('9d000000-0000-4000-8000-000000000006', '7a000000-0000-4000-8000-000000000006', '9a900000-0000-4000-8000-000000000006', '5e11e000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000002', 'medium', 'hold',          ARRAY['event_far_out'], '{"synthetic":true}', false, false, current_date + 6, now() + interval '2 days', 'seller-mark-sent', now() - interval '40 hours'),
  ('9d000000-0000-4000-8000-000000000007', '7a000000-0000-4000-8000-000000000007', '9a900000-0000-4000-8000-000000000007', '5e11e000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-000000000001', 'low',    'release',       ARRAY[]::text[], '{"synthetic":true}', true, false, current_date - 2, NULL, 'confirm-and-release', now() - interval '4 days 17 hours'),
  ('9d000000-0000-4000-8000-000000000012', '7a000000-0000-4000-8000-000000000012', '9a900000-0000-4000-8000-000000000012', '5e11e000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001', 'low',    'release',       ARRAY[]::text[], '{"synthetic":true}', false, false, current_date + 2, NULL, 'cron:auto-release', now() - interval '2 hours')
ON CONFLICT (id) DO NOTHING;

-- --- 14. Stripe webhook events -----------------------------------------------
INSERT INTO public.stripe_webhook_events (event_id, event_type, received_at, processed, processed_at, last_error, retry_count, claimed_at, failed_at, attempt_count) VALUES
  ('evt_test_ok_000007',     'payment_intent.succeeded', now() - interval '5 days',  true,  now() - interval '5 days', NULL, 0, NULL, NULL, 1),
  ('evt_test_stuck_000005',  'charge.dispute.created',   now() - interval '2 hours', false, NULL, 'TEST HARNESS: simulated handler failure — transfer row locked', 3, NULL, NULL, 3),
  ('evt_test_failed_000013', 'charge.refunded',          now() - interval '3 days',  false, NULL, 'TEST HARNESS: simulated permanent failure', 5, NULL, now() - interval '2 days 20 hours', 5)
ON CONFLICT (event_id) DO NOTHING;

-- --- 15. Seller risk scores --------------------------------------------------
INSERT INTO public.seller_risk_scores (seller_id, account_age_days, total_listings, active_listings, total_completed, total_disputes, total_dispute_losses, total_expired, rapid_send_count, dispute_rate, dispute_loss_rate, expiry_rate, risk_tier, open_flags_count, critical_flags_count, is_listing_blocked, listing_blocked_at, listing_blocked_reason) VALUES
  ('5e11e000-0000-4000-8000-000000000001', 300, 6, 2, 3, 0, 0, 0, 1, 0, 0, 0, 'low', 0, 0, false, NULL, NULL),
  ('5e11e000-0000-4000-8000-000000000002',  45, 5, 1, 2, 1, 1, 1, 0, 0.25, 0.25, 0.25, 'medium', 0, 0, false, NULL, NULL),
  ('5e11e000-0000-4000-8000-000000000003',  12, 4, 1, 1, 1, 0, 1, 0, 0.5, 0, 0.5, 'critical', 3, 1, true, now() - interval '1 day', 'TEST HARNESS: high_dispute_rate critical flag (synthetic)')
ON CONFLICT (seller_id) DO NOTHING;

-- Disarm guards (parity with tap.reset_guards()).
DO $$ BEGIN
  PERFORM set_config('app.bypass_transfer_guard', 'off', true);
  PERFORM set_config('app.bypass_listing_guard',  'off', true);
END $$;

COMMIT;

-- --- Summary ------------------------------------------------------------------
\echo '[fixtures] TEST HARNESS synthetic data present:'
SELECT 'accounts'  AS what, count(*) FROM ops_harness.accounts
UNION ALL SELECT 'admin_users', count(*) FROM public.admin_users
UNION ALL SELECT 'listings',    count(*) FROM public.listings WHERE id::text LIKE '11570000-%'
UNION ALL SELECT 'payments',    count(*) FROM public.payments WHERE id::text LIKE '9a900000-%'
UNION ALL SELECT 'transfers',   count(*) FROM public.transfers WHERE id::text LIKE '7a000000-%'
UNION ALL SELECT 'disputes',    count(*) FROM public.disputes WHERE stripe_dispute_id LIKE 'dp_test_%'
UNION ALL SELECT 'reports',     count(*) FROM public.reports WHERE id::text LIKE '4e900000-%'
UNION ALL SELECT 'webhook_evts',count(*) FROM public.stripe_webhook_events WHERE event_id LIKE 'evt_test_%';

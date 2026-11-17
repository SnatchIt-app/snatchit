-- =============================================================================
-- TEST HARNESS ONLY — synthetic data for reviewing the dashboard design.
--
-- Applied on top of fixtures.sql in a PRIVATE copy of the rehearsal database
-- (default name f_design_rehears), never the shared one and never anything
-- remote. It gives the console the texture of a real business: readable
-- names, more ordinary healthy orders than problem ones, and the same eleven
-- problem cases fixtures.sql already models. Every person, event and venue is
-- invented; every id stays in the harness ranges; Stripe ids are pi_test_ /
-- tr_test_ / re_test_.
--
--   psql -h 127.0.0.1 -U postgres -d f_design_rehears -f admin/scripts/design-fixtures.sql
-- =============================================================================
\set ON_ERROR_STOP on

DO $$
BEGIN
  IF current_database() NOT LIKE '%rehears%' OR inet_server_addr() IS NOT NULL AND host(inet_server_addr()) NOT IN ('127.0.0.1', '::1') THEN
    RAISE EXCEPTION 'design-fixtures: refusing to run against % (must be a loopback *rehears* database)', current_database();
  END IF;
END $$;

BEGIN;

-- --- people: readable names for the harness accounts, plus six more ---------
INSERT INTO auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
SELECT v.id::uuid, 'authenticated', 'authenticated', v.email, '$harness$not-a-real-hash', now() - v.age, '{"provider":"email","providers":["email"]}', '{"harness":true}', now() - v.age, now()
FROM (VALUES
  ('b0000000-0000-4000-8000-000000000004', 'buyer4@example.test', interval '200 days'),
  ('b0000000-0000-4000-8000-000000000005', 'buyer5@example.test', interval '75 days'),
  ('b0000000-0000-4000-8000-000000000006', 'buyer6@example.test', interval '31 days'),
  ('5e11e000-0000-4000-8000-000000000004', 'seller4@example.test', interval '410 days'),
  ('5e11e000-0000-4000-8000-000000000005', 'seller5@example.test', interval '160 days'),
  ('5e11e000-0000-4000-8000-000000000006', 'seller6@example.test', interval '88 days')
) AS v(id, email, age)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.profiles (id) SELECT id FROM auth.users WHERE email LIKE '%@example.test' ON CONFLICT (id) DO NOTHING;

UPDATE public.profiles p SET display_name = v.name, full_name = v.name
FROM (VALUES
  ('b0000000-0000-4000-8000-000000000001', 'Maya Torres'),
  ('b0000000-0000-4000-8000-000000000002', 'Jordan Kim'),
  ('b0000000-0000-4000-8000-000000000003', 'Ava Chen'),
  ('b0000000-0000-4000-8000-000000000004', 'Noah Williams'),
  ('b0000000-0000-4000-8000-000000000005', 'Priya Shah'),
  ('b0000000-0000-4000-8000-000000000006', 'Elena García'),
  ('5e11e000-0000-4000-8000-000000000001', 'Leo Martins'),
  ('5e11e000-0000-4000-8000-000000000002', 'Sofia Reyes'),
  ('5e11e000-0000-4000-8000-000000000003', 'Dee Kaplan'),
  ('5e11e000-0000-4000-8000-000000000004', 'Marcus Bell'),
  ('5e11e000-0000-4000-8000-000000000005', 'Hana Ito'),
  ('5e11e000-0000-4000-8000-000000000006', 'Camila Ruiz')
) AS v(id, name)
WHERE p.id = v.id::uuid;

-- --- the fifteen modelled listings get event names a person would recognise --
UPDATE public.listings l SET event_name = v.name, venue = v.venue
FROM (VALUES
  ('11570000-0000-4000-8000-000000000001', 'Neon Tide Festival — Night 1', 'Bayfront Grounds'),
  ('11570000-0000-4000-8000-000000000002', 'Solstice Rooftop Sessions', 'The Glasshouse'),
  ('11570000-0000-4000-8000-000000000003', 'Velvet Room Fridays', 'The Velvet Room'),
  ('11570000-0000-4000-8000-000000000004', 'Coastline Jazz Supper', 'Harbor Hall'),
  ('11570000-0000-4000-8000-000000000005', 'Midnight Mercado Live', 'Warehouse 27'),
  ('11570000-0000-4000-8000-000000000006', 'Sunday Matinee: Strings', 'Lyric Theater'),
  ('11570000-0000-4000-8000-000000000007', 'Brickell After Dark', 'Sky Lounge 40'),
  ('11570000-0000-4000-8000-000000000008', 'Low Light Sessions', 'Lyric Theater'),
  ('11570000-0000-4000-8000-000000000009', 'Static Bloom Tour', 'Warehouse 27'),
  ('11570000-0000-4000-8000-000000000010', 'Golden Hour Social', 'Bayfront Grounds'),
  ('11570000-0000-4000-8000-000000000011', 'Saltwater Rooftop', 'The Glasshouse'),
  ('11570000-0000-4000-8000-000000000012', 'Afterglow Club Night', 'Lyric Theater'),
  ('11570000-0000-4000-8000-000000000013', 'Little Havana Block Party', 'Calle Ocho Stage'),
  ('11570000-0000-4000-8000-000000000014', 'Comedy Cellar Pop-up', 'The Velvet Room'),
  ('11570000-0000-4000-8000-000000000015', 'Sunrise Rave (VIP tables)', 'Warehouse 27')
) AS v(id, name, venue)
WHERE l.id = v.id::uuid;

-- --- eighteen ordinary, healthy orders: captured, delivered, released --------
-- Listing → payment → transfer per row; buyer confirmed and the seller's share
-- released to their connected account, as most real orders end.
WITH spec AS (
  SELECT n,
         (ARRAY['Neon Tide Festival — Night 2','Velvet Room Fridays','Coastline Jazz Supper','Brickell After Dark','Static Bloom Tour','Golden Hour Social',
                'Afterglow Club Night','Saltwater Rooftop','Midnight Mercado Live','Solstice Rooftop Sessions','Low Light Sessions','Little Havana Block Party'])[1 + (n % 12)] AS event_name,
         (ARRAY['Bayfront Grounds','The Velvet Room','Harbor Hall','Sky Lounge 40','Warehouse 27','Bayfront Grounds','Lyric Theater','The Glasshouse','Warehouse 27','The Glasshouse','Lyric Theater','Calle Ocho Stage'])[1 + (n % 12)] AS venue,
         (ARRAY[4500, 6000, 8500, 3800, 12000, 5500, 7000, 9500, 3000, 15000, 6500, 4200])[1 + (n % 12)] AS price,
         (ARRAY['b0000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000003',
                'b0000000-0000-4000-8000-000000000004','b0000000-0000-4000-8000-000000000005','b0000000-0000-4000-8000-000000000006'])[1 + (n % 6)]::uuid AS buyer,
         (ARRAY['5e11e000-0000-4000-8000-000000000004','5e11e000-0000-4000-8000-000000000005','5e11e000-0000-4000-8000-000000000006',
                '5e11e000-0000-4000-8000-000000000001','5e11e000-0000-4000-8000-000000000002'])[1 + (n % 5)]::uuid AS seller,
         interval '1 hour' * (6 + n * 9) AS ago
  FROM generate_series(1, 18) AS n
), l AS (
  INSERT INTO public.listings
    (id, created_at, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity,
     transfer_method, starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid,
     cover_image_path, status, reserved_by, reserved_until, sold_at, auction_status, winner_user_id, winning_bid_amount,
     ended_at, bid_count, highest_bidder_id, ticket_platform, category, proof_status)
  SELECT format('11570000-0000-4000-8000-0000000001%s', lpad(n::text, 2, '0'))::uuid, now() - ago - interval '1 day', seller, event_name, venue, 'wynwood',
         current_date + (n % 9), '21:00', CASE WHEN n % 4 = 0 THEN 'VIP' ELSE 'GA' END, 1 + (n % 3),
         CASE WHEN n % 2 = 0 THEN 'email' ELSE 'mobile_transfer' END, price, true, price, 24, now() - ago - interval '1 day', now() - ago, price,
         format('harness/l1%s.jpg', lpad(n::text, 2, '0')), 'sold', buyer, NULL, now() - ago, 'sold', buyer, price, now() - ago, 0, NULL, 'dice', 'nightlife', 'approved'
  FROM spec
  ON CONFLICT (id) DO NOTHING
  RETURNING id
), p AS (
  INSERT INTO public.payments
    (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, payment_method, mode, created_at, paid_at, failed_at, refunded_at, stripe_refund_id, stripe_livemode)
  SELECT format('9a900000-0000-4000-8000-0000000001%s', lpad(n::text, 2, '0'))::uuid, format('11570000-0000-4000-8000-0000000001%s', lpad(n::text, 2, '0'))::uuid,
         buyer, seller, price, price / 10, price / 10, price + price / 10, format('pi_test_0001%s', lpad(n::text, 2, '0')), 'succeeded', 'card', 'buy_now',
         now() - ago, now() - ago, NULL, NULL, NULL, false
  FROM spec
  ON CONFLICT (id) DO NOTHING
  RETURNING id
)
INSERT INTO public.transfers
  (id, created_at, listing_id, payment_id, seller_id, buyer_id, transfer_method, status,
   seller_sent_at, buyer_confirmed_at, expires_at, payout_released_at, stripe_transfer_id, auto_release_at, buyer_viewed_at, payout_risk_tier, payout_reason_codes)
SELECT format('7a000000-0000-4000-8000-0000000001%s', lpad(n::text, 2, '0'))::uuid, now() - ago,
       format('11570000-0000-4000-8000-0000000001%s', lpad(n::text, 2, '0'))::uuid, format('9a900000-0000-4000-8000-0000000001%s', lpad(n::text, 2, '0'))::uuid,
       seller, buyer, CASE WHEN n % 2 = 0 THEN 'email' ELSE 'mobile_transfer' END, 'buyer_confirmed',
       now() - ago + interval '40 minutes', now() - ago + interval '3 hours', now() - ago + interval '24 hours',
       now() - ago + interval '3 hours 5 minutes', format('tr_test_0001%s', lpad(n::text, 2, '0')), now() - ago + interval '48 hours', now() - ago + interval '2 hours', 'low', ARRAY[]::text[]
FROM spec
ON CONFLICT (id) DO NOTHING;

COMMIT;

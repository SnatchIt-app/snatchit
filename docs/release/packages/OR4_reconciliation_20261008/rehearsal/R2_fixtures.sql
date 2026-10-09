-- O-R4 R2 fixtures (local rehearsal DB only; never production).
-- #6 and #7 use their real payment ids, PaymentIntents, totals and refunded_at (R0, UTC), so the proposed R3 files
-- run here unchanged except for their three R1/owner markers. Control payments exercise each refusal path.
-- Seeded with session_replication_role = replica, which skips the FK and guard trigger chain (auth -> profiles ->
-- listings) for SETUP ONLY. Every call under test runs afterwards with all triggers on. Each seeded shape exists in
-- production: a live refunded payment with one reversed, unpaid transfer.
begin;
set local session_replication_role = replica;

insert into auth.users (id, email) values
  ('b2000000-0000-4000-8000-000000000001', 'r2-buyer@example.test'),
  ('b2000000-0000-4000-8000-000000000002', 'r2-seller@example.test');
insert into public.profiles (id) values
  ('b2000000-0000-4000-8000-000000000001'),
  ('b2000000-0000-4000-8000-000000000002');
-- one listing per payment: transfers.listing_id is unique
insert into public.listings (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type,
                             quantity, transfer_method, starting_bid, duration_hours, ends_at, current_bid,
                             cover_image_path)
select ('c2000000-0000-4000-8000-00000000000' || n)::uuid, 'b2000000-0000-4000-8000-000000000002',
       'R2 fixture event ' || n, 'R2 venue', 'brickell', '2026-08-10', '22:00', 'GA', 1, 'email', 100, 24,
       '2026-08-05 00:00+00', 100, 'r2/cover.jpg'
  from generate_series(1, 7) n;

-- payments: #6, #7 (real ids) and five controls
insert into public.payments (id, buyer_id, seller_id, listing_id, mode, amount, buyer_fee, total, status,
                             stripe_payment_intent_id, stripe_livemode, refunded_at, amount_refunded_cents,
                             stripe_refund_id)
select v.id::uuid, 'b2000000-0000-4000-8000-000000000001', 'b2000000-0000-4000-8000-000000000002',
       ('c2000000-0000-4000-8000-00000000000' || v.n)::uuid, 'buy_now', v.amount, v.total - v.amount, v.total, v.status,
       v.pi, v.live, v.refunded_at::timestamptz, v.arc, v.sri
  from (values
    -- #6 and #7: R0 as measured
    (1, '32913315-2bf7-4e58-b837-f6c5c34b722b', 1000, 1100, 'refunded',  'pi_3U0XuwGdOzCmGbHw0WVJfW3y', true,  '2026-08-04 17:20:05+00', null::int, null::text),
    (2, '700d469b-045c-430f-8d16-351d9ff3b838',  200,  220, 'refunded',  'pi_3U0YzcGdOzCmGbHw0Z6l7bf7', true,  '2026-08-04 17:20:19+00', null, null),
    -- FT: test-mode twin of #6 (the excluded five's shape)
    (3, 'a2000000-0000-4000-8000-000000000001', 1000, 1100, 'refunded',  'pi_R2TESTMODE000000000001',   false, '2026-08-04 17:20:05+00', null, null),
    -- FH1: hazard 1, a ledger row already exists under another key
    (4, 'a2000000-0000-4000-8000-000000000002', 1000, 1100, 'refunded',  'pi_R2HAZARDONE00000000001',   true,  '2026-08-04 17:20:05+00', null, null),
    -- FH2: hazard 2, the transfer carries a payout
    (5, 'a2000000-0000-4000-8000-000000000003', 1000, 1100, 'refunded',  'pi_R2HAZARDTWO00000000001',   true,  '2026-08-04 17:20:05+00', null, null),
    -- FM: payments.stripe_refund_id already holds a different refund id
    (6, 'a2000000-0000-4000-8000-000000000004', 1000, 1100, 'refunded',  'pi_R2REFIDSET000000000001',   true,  '2026-08-04 17:20:05+00', null, 're_R2PREEXISTING0000001'),
    -- FR: raw hazard-1 control (README R2): a genuine partial refund of 600 already recorded
    (7, 'a2000000-0000-4000-8000-000000000005', 1000, 1100, 'succeeded', 'pi_R2PARTIAL0000000000001',   true,  null,                      600,  're_R2PARTIAL00000000001')
  ) as v(n, id, amount, total, status, pi, live, refunded_at, arc, sri);

insert into public.payment_refunds (payment_id, stripe_refund_id, stripe_dispute_id, amount_cents, source) values
  ('a2000000-0000-4000-8000-000000000002', 're_R2OLDLEDGER000000001', null, 1100, 'dashboard'),
  ('a2000000-0000-4000-8000-000000000005', 're_R2PARTIAL00000000001', null,  600, 'admin');

-- one transfer per payment: reversed and unpaid (as R0), except FH2 (paid) and FR (pending)
insert into public.transfers (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, expires_at, status,
                              payout_released_at, stripe_transfer_id)
select gen_random_uuid(), p.listing_id, p.id, p.seller_id, p.buyer_id, 'email',
       '2026-08-05 00:00+00',
       case when p.id = 'a2000000-0000-4000-8000-000000000005' then 'pending' else 'reversed' end,
       case when p.id = 'a2000000-0000-4000-8000-000000000003' then '2026-08-03 12:00+00'::timestamptz end,
       case when p.id = 'a2000000-0000-4000-8000-000000000003' then 'tr_R2PAID0000000000001' end
  from public.payments p
 where p.buyer_id = 'b2000000-0000-4000-8000-000000000001';

commit;

-- production mirror: refund-state detection is on (O-R2, 2026-10-08)
update ops.setting set value = 'true'::jsonb where key = 'refund_state_detection_enabled';

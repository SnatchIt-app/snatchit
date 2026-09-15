-- D-R126-P2: chargeback lost on an already-refunded charge — the state 20260906120000's writer explicitly caps
-- ("a chargeback on an already refunded charge cannot push the fact past the money that existed").
\set ON_ERROR_STOP 1
BEGIN;
SELECT tap.seed_core();
INSERT INTO auth.users (id, email, aud, role) VALUES ('d1260000-0000-4000-8000-000000000002','d126b@example.test','authenticated','authenticated') ON CONFLICT DO NOTHING;
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, total, stripe_payment_intent_id, status, mode, created_at, paid_at, seller_fee, stripe_livemode)
VALUES ('d1260000-0000-4000-8000-0000000000c1', tap.listing_c(), 'd1260000-0000-4000-8000-000000000002', tap.seller(), 9091, 909, 10000, 'pi_d126_c', 'succeeded', 'buy_now', now()-interval '5 hours', now()-interval '5 hours', 909, false);
SELECT 'C.full_refund' k, public.record_payment_refund('pi_d126_c', 're_d126_c1', NULL, 10000, 'dashboard')::text v;
SELECT 'C.dispute_lost' k, public.record_payment_refund('pi_d126_c', NULL, 'dp_d126_c1', 10000, 'dispute_lost')::text v;
SELECT 'C.payment_fact' k, concat_ws('|', status, amount_refunded_cents, total) v FROM public.payments WHERE id='d1260000-0000-4000-8000-0000000000c1';
SELECT 'C.refund_facts' k, ops.refund_facts(now()-interval '1 day', now()+interval '1 minute')::text v;
ROLLBACK;

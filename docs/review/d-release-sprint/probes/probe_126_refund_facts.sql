-- D-R126 probes (independent; local rehearsal DB only; BEGIN…ROLLBACK). States via real writers where one exists.
\set ON_ERROR_STOP 1
BEGIN;
SELECT tap.seed_core();
INSERT INTO auth.users (id, email, aud, role) VALUES ('d1260000-0000-4000-8000-000000000001','d126@example.test','authenticated','authenticated') ON CONFLICT DO NOTHING;
-- P-A: $100 payment captured; Stripe partial refund $60 (explicit amount), then an amount-less full refund
--      (writer's documented NULL = "full refund of what the charge captured").
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, total, stripe_payment_intent_id, status, mode, created_at, paid_at, seller_fee, stripe_livemode)
VALUES ('d1260000-0000-4000-8000-0000000000a1', tap.listing_c(), 'd1260000-0000-4000-8000-000000000001', tap.seller(), 9091, 909, 10000, 'pi_d126_a', 'succeeded', 'buy_now', now()-interval '5 hours', now()-interval '5 hours', 909, false);
SELECT 'A.refund1' k, public.record_payment_refund('pi_d126_a', 're_d126_a1', NULL, 6000, 'dashboard')::text v;
SELECT 'A.refund2' k, public.record_payment_refund('pi_d126_a', 're_d126_a2', NULL, NULL, 'dashboard')::text v;
SELECT 'A.ledger_sum' k, sum(amount_cents)::text v FROM public.payment_refunds WHERE payment_id = 'd1260000-0000-4000-8000-0000000000a1';
SELECT 'A.refund_facts' k, ops.refund_facts(now()-interval '1 day', now()+interval '1 minute')::text v;
-- P-B: a legacy refund (pre-ledger): status refunded, refunded_at in window, amount_refunded_cents NULL, no ledger row.
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, total, stripe_payment_intent_id, status, mode, created_at, paid_at, refunded_at, seller_fee, stripe_livemode, stripe_refund_id)
VALUES ('d1260000-0000-4000-8000-0000000000b1', tap.listing_c(), 'd1260000-0000-4000-8000-000000000001', tap.seller(), 4545, 455, 5000, 'pi_d126_b', 'refunded', 'buy_now', now()-interval '5 hours', now()-interval '5 hours', now()-interval '2 hours', 455, false, 're_d126_legacy');
SELECT 'B.refund_facts_with_legacy' k, ops.refund_facts(now()-interval '1 day', now()+interval '1 minute')::text v;
ROLLBACK;

-- D: 132 @ 9d82247 — public.record_checkout_attempt (claim-bound pending row). Single-session semantics.
-- Local rehearsal DB; BEGIN…ROLLBACK; results SELECTed as they happen.
\set ON_ERROR_STOP 0
BEGIN;
SELECT tap.seed_core();
CREATE FUNCTION pg_temp.try(q text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE r text; BEGIN EXECUTE q INTO r; RETURN coalesce(r,'ok'); EXCEPTION WHEN others THEN RETURN 'ERR '||SQLSTATE||': '||SQLERRM; END $$;
GRANT EXECUTE ON FUNCTION pg_temp.try(text) TO authenticated, anon, service_role;
SELECT set_config('d.l', tap.listing_b()::text, true);
SELECT set_config('d.b', tap.buyer()::text, true);
-- grants: no client may call any of the three verbs
SELECT tap.login(tap.buyer());
SELECT 'A1.authenticated_record', pg_temp.try($q$SELECT public.record_checkout_attempt(current_setting('d.l')::uuid, auth.uid(), 'buy_now', gen_random_uuid(), null, 100, 10, 10, 110, 'pi_x', false)::text$q$);
SELECT 'A2.authenticated_claim', pg_temp.try($q$SELECT public.claim_checkout_group(current_setting('d.l')::uuid, auth.uid(), 'buy_now')::text$q$);
SELECT 'A3.authenticated_select_claim_table', pg_temp.try($q$SELECT count(*)::text FROM public.checkout_group_claim$q$);
SELECT tap.logout();
SET LOCAL ROLE service_role;
-- B: claim, then record under the right and the wrong token
SELECT 'B1.claim', (public.claim_checkout_group(current_setting('d.l')::uuid, current_setting('d.b')::uuid, 'buy_now'))->>'reason';
SELECT set_config('d.tok', (SELECT claim_token::text FROM public.checkout_group_claim WHERE listing_id = current_setting('d.l')::uuid AND buyer_id = current_setting('d.b')::uuid), true);
SELECT 'B2.record_wrong_token', pg_temp.try($q$SELECT public.record_checkout_attempt(current_setting('d.l')::uuid, current_setting('d.b')::uuid, 'buy_now', gen_random_uuid(), (SELECT seller_id FROM public.listings WHERE id = current_setting('d.l')::uuid), 10000, 1000, 1000, 11000, 'pi_d132_wrong', false)->>'reason'$q$);
SELECT 'B3.rows_after_wrong_token', (SELECT count(*)::text FROM public.payments WHERE stripe_payment_intent_id = 'pi_d132_wrong');
SELECT 'B4.record_right_token', pg_temp.try($q$SELECT public.record_checkout_attempt(current_setting('d.l')::uuid, current_setting('d.b')::uuid, 'buy_now', current_setting('d.tok')::uuid, (SELECT seller_id FROM public.listings WHERE id = current_setting('d.l')::uuid), 10000, 1000, 1000, 11000, 'pi_d132_ok', false)->>'reason'$q$);
SELECT 'B5.row_shape', (SELECT concat_ws('|', status, mode, amount, buyer_fee, seller_fee, total, stripe_livemode, (buyer_id = current_setting('d.b')::uuid)) FROM public.payments WHERE stripe_payment_intent_id = 'pi_d132_ok');
SELECT 'B6.duplicate_intent_raises', pg_temp.try($q$SELECT public.record_checkout_attempt(current_setting('d.l')::uuid, current_setting('d.b')::uuid, 'buy_now', current_setting('d.tok')::uuid, (SELECT seller_id FROM public.listings WHERE id = current_setting('d.l')::uuid), 10000, 1000, 1000, 11000, 'pi_d132_ok', false)->>'reason'$q$);
-- C: after a reclaim the old token records nothing
UPDATE public.checkout_group_claim SET claimed_at = now() - interval '121 seconds'
 WHERE listing_id = current_setting('d.l')::uuid AND buyer_id = current_setting('d.b')::uuid;   -- age it in its OWN statement
SELECT 'C1.reclaim_after_121s', (public.claim_checkout_group(current_setting('d.l')::uuid, current_setting('d.b')::uuid, 'auction'))->>'reason';
SELECT 'C2.old_token_records_nothing', pg_temp.try($q$SELECT public.record_checkout_attempt(current_setting('d.l')::uuid, current_setting('d.b')::uuid, 'buy_now', current_setting('d.tok')::uuid, (SELECT seller_id FROM public.listings WHERE id = current_setting('d.l')::uuid), 10000, 1000, 1000, 11000, 'pi_d132_after_reclaim', false)->>'reason'$q$);
SELECT 'C3.rows_after_reclaim', (SELECT count(*)::text FROM public.payments WHERE stripe_payment_intent_id = 'pi_d132_after_reclaim');
SELECT 'C3b.token_changed', ((SELECT claim_token::text FROM public.checkout_group_claim WHERE listing_id = current_setting('d.l')::uuid AND buyer_id = current_setting('d.b')::uuid) <> current_setting('d.tok'))::text;
SELECT 'C4.mode_recorded_on_reclaim', (SELECT mode FROM public.checkout_group_claim WHERE listing_id = current_setting('d.l')::uuid AND buyer_id = current_setting('d.b')::uuid);
-- D: release is token-bound and group-wide (mode not part of the match)
SELECT 'D1.release_wrong_token', (public.release_checkout_group(current_setting('d.l')::uuid, current_setting('d.b')::uuid, 'buy_now', gen_random_uuid()))->>'reason';
SELECT set_config('d.tok2', (SELECT claim_token::text FROM public.checkout_group_claim WHERE listing_id = current_setting('d.l')::uuid AND buyer_id = current_setting('d.b')::uuid), true);
SELECT 'D2.release_right_token_other_mode_arg', (public.release_checkout_group(current_setting('d.l')::uuid, current_setting('d.b')::uuid, 'buy_now', current_setting('d.tok2')::uuid))->>'reason';
SELECT 'D3.release_again', (public.release_checkout_group(current_setting('d.l')::uuid, current_setting('d.b')::uuid, 'buy_now', current_setting('d.tok2')::uuid))->>'reason';
SELECT 'D4.record_without_any_claim', pg_temp.try($q$SELECT public.record_checkout_attempt(current_setting('d.l')::uuid, current_setting('d.b')::uuid, 'buy_now', current_setting('d.tok2')::uuid, null, 10000, 1000, 1000, 11000, 'pi_d132_noclaim', false)->>'reason'$q$);
SELECT 'D5.missing_argument', pg_temp.try($q$SELECT public.record_checkout_attempt(current_setting('d.l')::uuid, current_setting('d.b')::uuid, 'buy_now', null, null, 10000, 1000, 1000, 11000, 'pi_d132_null', false)->>'reason'$q$);
RESET ROLE;
ROLLBACK;

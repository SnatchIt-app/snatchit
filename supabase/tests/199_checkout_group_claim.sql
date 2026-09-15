-- ============================================================================
-- 199_checkout_group_claim.sql — migration 132 (fresh-mint double charge).
--   Before ANY Stripe mint, the checkout edge must hold the durable group
--   record for (listing, buyer, mode):
--     public.claim_checkout_group(listing, buyer, mode)
--       -> {claimed, claim_token, reason}
--     public.release_checkout_group(listing, buyer, mode, claim_token)
--       -> {released, reason}
--   130's claim lives on a pending payment row, so two requests that both find
--   NO pending row both mint; when their idempotency keys diverge (the `_u`
--   replay retry, a re-price between reads, a failedAttempts flip) that is two
--   intents, two secrets, two captured charges. 132's record exists before the
--   prior-payments read, so the second request is refused before it can mint.
--   One statement (INSERT ... ON CONFLICT ... WHERE stale) makes the claim
--   atomic on the primary key; it takes no payments or listings lock. A claim
--   older than 120 s is reclaimable; release is bound to the token.
--   The concurrent proof is scripts/rehearsal_132_concurrency.sh (pgTAP runs
--   in one transaction); the edge interleave is tests/checkout-group-claim.test.ts.
--
-- VERSION-AGNOSTIC: every call goes through tap._try199, so on a database
-- without 132 the suite completes and reports failures instead of aborting.
-- now() is frozen per transaction, so staleness is set by moving claimed_at
-- back explicitly (owner-level UPDATE; the table has no guard trigger).
-- No superuser-only settings are used.
-- ============================================================================
BEGIN;
SELECT plan(44);
SELECT tap.seed_core();

CREATE FUNCTION tap._try199(p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $f$
declare r jsonb;
begin
  execute p_sql into r;
  return r;
exception when others then
  return jsonb_build_object('__error', sqlstate || ' ' || sqlerrm);
end $f$;
CREATE FUNCTION tap._id199(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $m$ SELECT ('19900000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid $m$;
CREATE FUNCTION tap._claim199(p_listing uuid, p_buyer uuid, p_mode text) RETURNS jsonb LANGUAGE sql
  AS $m$ SELECT tap._try199(format('SELECT public.claim_checkout_group(%L::uuid, %L::uuid, %L::text)', p_listing, p_buyer, p_mode)) $m$;
CREATE FUNCTION tap._release199(p_listing uuid, p_buyer uuid, p_mode text, p_token text) RETURNS jsonb LANGUAGE sql
  AS $m$ SELECT tap._try199(format('SELECT public.release_checkout_group(%L::uuid, %L::uuid, %L::text, %L::uuid)', p_listing, p_buyer, p_mode, p_token)) $m$;
-- the group row, read without depending on the table existing
CREATE FUNCTION tap._row199(p_listing uuid, p_buyer uuid, p_mode text) RETURNS jsonb LANGUAGE sql
  AS $m$ SELECT tap._try199(format('SELECT coalesce((SELECT jsonb_build_object(''token'', claim_token, ''age_s'', extract(epoch FROM now() - claimed_at)::int) FROM public.checkout_group_claim WHERE listing_id = %L::uuid AND buyer_id = %L::uuid AND mode = %L), ''{}''::jsonb)', p_listing, p_buyer, p_mode)) $m$;
-- the group row regardless of the mode that holds it
CREATE FUNCTION tap._any199(p_listing uuid, p_buyer uuid) RETURNS jsonb LANGUAGE sql
  AS $m$ SELECT tap._try199(format('SELECT jsonb_build_object(''mode'', max(mode), ''n'', count(*)) FROM public.checkout_group_claim WHERE listing_id = %L::uuid AND buyer_id = %L::uuid', p_listing, p_buyer)) $m$;
-- move a group claim back in time
CREATE FUNCTION tap._age199(p_listing uuid, p_buyer uuid, p_mode text, p_seconds int) RETURNS jsonb LANGUAGE sql
  AS $m$ SELECT tap._try199(format('WITH u AS (UPDATE public.checkout_group_claim SET claimed_at = now() - make_interval(secs => %s) WHERE listing_id = %L::uuid AND buyer_id = %L::uuid AND mode = %L RETURNING 1) SELECT jsonb_build_object(''aged'', count(*)) FROM u', p_seconds, p_listing, p_buyer, p_mode)) $m$;

CREATE TABLE tap.memo_199 (k text PRIMARY KEY, v jsonb);
CREATE FUNCTION tap._store199(p_k text, p_v jsonb) RETURNS jsonb LANGUAGE sql
  AS $m$ INSERT INTO tap.memo_199 VALUES (p_k, p_v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._get199(p_k text) RETURNS jsonb LANGUAGE sql AS $m$ SELECT v FROM tap.memo_199 WHERE k = p_k $m$;

-- ── FIXTURE — listing L with the buyer's pending buy_now P1 (130's world). ───
INSERT INTO public.listings
  (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
   starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
VALUES (tap._id199(1), tap.seller(), 'Fixture 199', 'Club 199', 'wynwood', current_date + 30, '21:00', 'GA', 2,
        'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/199.jpg', 'active');
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total,
                             stripe_payment_intent_id, status, mode, created_at, stripe_livemode)
VALUES (tap._id199(11), tap._id199(1), tap.buyer(), tap.seller(), 20000, 2000, 2000, 22000, 'pi_199_p1', 'pending', 'buy_now', now(), false);

-- ── A. definition and grants ─────────────────────────────────────────────────
SELECT ok(to_regclass('public.checkout_group_claim') IS NOT NULL, 'A.1: public.checkout_group_claim exists');
SELECT is((SELECT array_agg(a.attname::text ORDER BY k.ord)
             FROM pg_index i
             CROSS JOIN LATERAL unnest(i.indkey) WITH ORDINALITY AS k(attnum, ord)
             JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum
            WHERE i.indrelid = to_regclass('public.checkout_group_claim') AND i.indisprimary),
          ARRAY['listing_id', 'buyer_id'],
  'A.2: primary key is exactly (listing_id, buyer_id) — one group across both modes (D F-132-1)');
SELECT is((SELECT array_agg(c.column_name::text || ':' || c.is_nullable ORDER BY c.column_name)
             FROM information_schema.columns c
            WHERE c.table_schema = 'public' AND c.table_name = 'checkout_group_claim'),
          ARRAY['buyer_id:NO', 'claim_token:NO', 'claimed_at:NO', 'listing_id:NO', 'mode:NO'],
  'A.3: exactly five columns, all NOT NULL');
SELECT ok(coalesce((SELECT c.relrowsecurity FROM pg_class c WHERE c.oid = to_regclass('public.checkout_group_claim')), false)
      AND NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'checkout_group_claim'),
  'A.4: RLS enabled, zero policies');
SELECT ok(to_regclass('public.checkout_group_claim') IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM unnest(ARRAY['anon', 'authenticated']) r(role), unnest(ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE']) p(priv)
             WHERE has_table_privilege(r.role, 'public.checkout_group_claim', p.priv)),
  'A.5: anon and authenticated hold no table privilege');
SELECT is((SELECT string_agg(g.privilege_type, ',' ORDER BY g.privilege_type) FROM information_schema.role_table_grants g
            WHERE g.table_schema = 'public' AND g.table_name = 'checkout_group_claim' AND g.grantee = 'service_role'),
          'DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE',
  'A.5b: service_role holds the explicit table grant (the edge''s E-1 guard SELECTs the token; a CI replay has no default ACL)');
SELECT ok(to_regprocedure('public.claim_checkout_group(uuid,uuid,text)') IS NOT NULL, 'A.6: claim_checkout_group(uuid,uuid,text) exists');
SELECT ok(to_regprocedure('public.release_checkout_group(uuid,uuid,text,uuid)') IS NOT NULL, 'A.7: release_checkout_group(uuid,uuid,text,uuid) exists');
SELECT ok(coalesce((SELECT bool_and(p.prosecdef AND p.proconfig = ARRAY['search_path=""'] AND (p.prorettype::regtype)::text = 'jsonb')
                      FROM pg_proc p WHERE p.oid IN (to_regprocedure('public.claim_checkout_group(uuid,uuid,text)'),
                                                     to_regprocedure('public.release_checkout_group(uuid,uuid,text,uuid)'))
                      HAVING count(*) = 2), false),
  'A.8: both are SECURITY DEFINER, search_path pinned to empty, return jsonb');
SELECT ok(coalesce((SELECT bool_and(has_function_privilege('service_role', p.oid, 'EXECUTE')
                                    AND NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')
                                    AND NOT has_function_privilege('anon', p.oid, 'EXECUTE'))
                      FROM pg_proc p WHERE p.oid IN (to_regprocedure('public.claim_checkout_group(uuid,uuid,text)'),
                                                     to_regprocedure('public.release_checkout_group(uuid,uuid,text,uuid)'))
                      HAVING count(*) = 2), false),
  'A.9: service_role may execute both; anon and authenticated may not');
SELECT is(tap._try199(format('WITH i AS (INSERT INTO public.checkout_group_claim (listing_id, buyer_id, mode, claim_token, claimed_at) VALUES (%L::uuid, %L::uuid, ''native_primary'', gen_random_uuid(), now()) RETURNING 1) SELECT jsonb_build_object(''inserted'', count(*)) FROM i',
                             tap._id199(1), tap.buyer()))->>'__error' LIKE '23514%', true,
  'A.10: the table refuses a mode outside buy_now / auction (check constraint)');

-- ── C. claim ─────────────────────────────────────────────────────────────────
SELECT tap._store199('c1', tap._claim199(tap._id199(1), tap.buyer(), 'buy_now'));
SELECT is(tap._get199('c1')->>'claimed', 'true', 'C.1: the first request claims the group');
SELECT ok(tap._get199('c1')->>'claim_token' IS NOT NULL AND tap._get199('c1')->>'reason' = 'claimed', 'C.2: with a token and reason claimed');
SELECT ok(tap._get199('c1')->>'claim_token' IS NOT NULL AND tap._row199(tap._id199(1), tap.buyer(), 'buy_now')->>'token' = tap._get199('c1')->>'claim_token', 'C.3: the durable row carries that token');
SELECT tap._store199('c2', tap._claim199(tap._id199(1), tap.buyer(), 'buy_now'));
SELECT is(concat_ws('|', tap._get199('c2')->>'claimed', tap._get199('c2')->>'reason', coalesce(tap._get199('c2')->>'claim_token', 'null')),
          'false|claim_held|null',
  'C.4: INTERLEAVE — a concurrent second request of the same group is refused before any mint, with no token');
SELECT ok(tap._get199('c1')->>'claim_token' IS NOT NULL AND tap._row199(tap._id199(1), tap.buyer(), 'buy_now')->>'token' = tap._get199('c1')->>'claim_token', 'C.5: a refused claim leaves the holder''s token untouched');
SELECT is(tap._claim199(tap._id199(1), tap.buyer(), 'auction')->>'reason', 'claim_held', 'C.6: CROSS-MODE — the other mode of the same listing and buyer is the SAME group and is refused (D F-132-1)');
SELECT is(tap._claim199(tap._id199(1), tap.other_user(), 'buy_now')->>'claimed', 'true', 'C.7: another buyer of the same listing is a separate group');
SELECT tap._age199(tap._id199(1), tap.buyer(), 'buy_now', 119);
SELECT is(tap._claim199(tap._id199(1), tap.buyer(), 'buy_now')->>'reason', 'claim_held', 'C.8: a 119 s old claim still holds');
SELECT tap._age199(tap._id199(1), tap.buyer(), 'buy_now', 121);
SELECT tap._store199('c3', tap._claim199(tap._id199(1), tap.buyer(), 'buy_now'));
SELECT is(tap._get199('c3')->>'claimed', 'true', 'C.9: a 121 s old claim is abandoned and reclaimed');
SELECT ok(tap._get199('c3')->>'claim_token' IS DISTINCT FROM tap._get199('c1')->>'claim_token' AND tap._get199('c3')->>'claim_token' IS NOT NULL,
  'C.10: the reclaim issues a new token');
SELECT is(tap._row199(tap._id199(1), tap.buyer(), 'buy_now'), jsonb_build_object('token', tap._get199('c3')->>'claim_token', 'age_s', 0),
  'C.11: the row now carries the new token and a fresh claimed_at');
SELECT is(tap._claim199(tap._id199(1), tap.buyer(), 'buy_now')->>'reason', 'claim_held', 'C.12: the reclaimed group refuses the next request');

-- ── R. release ───────────────────────────────────────────────────────────────
SELECT is(tap._release199(tap._id199(1), tap.buyer(), 'buy_now', tap._get199('c1')->>'claim_token')->>'reason', 'token_mismatch',
  'R.1: the abandoned holder''s late release is refused');
SELECT ok(tap._get199('c3')->>'claim_token' IS NOT NULL AND tap._row199(tap._id199(1), tap.buyer(), 'buy_now')->>'token' = tap._get199('c3')->>'claim_token', 'R.2: and never frees the reclaim');
SELECT is(tap._release199(tap._id199(1), tap.buyer(), 'buy_now', gen_random_uuid()::text)->>'released', 'false', 'R.3: an arbitrary token releases nothing');
SELECT is(tap._release199(tap._id199(1), tap.buyer(), 'buy_now', tap._get199('c3')->>'claim_token'), '{"released": true, "reason": "released"}'::jsonb,
  'R.4: the holder''s token releases');
SELECT is(tap._row199(tap._id199(1), tap.buyer(), 'buy_now'), '{}'::jsonb, 'R.5: release deletes the group row');
SELECT is(tap._release199(tap._id199(1), tap.buyer(), 'buy_now', tap._get199('c3')->>'claim_token')->>'reason', 'not_claimed', 'R.6: a second release reports not_claimed');
SELECT is(tap._claim199(tap._id199(1), tap.buyer(), 'buy_now')->>'claimed', 'true', 'R.7: the next request claims the released group at once');
SELECT is(tap._release199(tap._id199(1), tap.other_user(), 'buy_now', tap._get199('c3')->>'claim_token')->>'reason', 'token_mismatch',
  'R.8: a token from one group never releases another buyer''s group');

-- ── Z. D's reachable cross-mode state (probe_132_cross_mode.sql), real writers ─
-- An auction with Buy Now enabled: the buyer bids, takes a Buy Now hold while the
-- auction runs, and the finalizer ends the auction under the live hold. Both of
-- the edge's entitlement predicates are then true for the same buyer.
SELECT set_config('app.bypass_listing_guard', 'on', true);
INSERT INTO public.listings
  (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
   starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
VALUES (tap._id199(2), tap.seller(), 'Fixture 199 Z', 'Club 199', 'wynwood', current_date + 30, '21:00', 'GA', 2,
        'mobile_transfer', 50, true, 150, 24, now() - interval '1 hour', now() + interval '1 hour', 0, 'fixtures/199z.jpg', 'active');
SELECT tap.login(tap.buyer());
INSERT INTO public.bids (listing_id, bidder_id, amount) VALUES (tap._id199(2), auth.uid(), 60);
SELECT public.reserve_buy_now(tap._id199(2), auth.uid(), 10);
SELECT tap.logout();
SELECT set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.listings SET ends_at = now() - interval '1 second' WHERE id = tap._id199(2);
SELECT public.auto_finalize_expired_auctions();
SELECT is((SELECT concat_ws('|', status, auction_status, (winner_user_id = tap.buyer())::text, (reserved_by = tap.buyer())::text, (reserved_until > now())::text)
             FROM public.listings WHERE id = tap._id199(2)),
          'reserved|ended|true|true|true',
  'Z.1: reachable state — reserved by the buyer (live) AND auction ended with the buyer as winner');
SELECT is(tap._claim199(tap._id199(2), tap.buyer(), 'buy_now')->>'claimed', 'true', 'Z.2: the Buy Now checkout claims the group');
SELECT is(tap._claim199(tap._id199(2), tap.buyer(), 'auction')->>'reason', 'claim_held',
  'Z.3: the auction checkout of the same buyer on the same listing is refused before any mint (RED on the mode-keyed claim)');
SELECT is(tap._any199(tap._id199(2), tap.buyer()), '{"mode": "buy_now", "n": 1}'::jsonb, 'Z.4: one group row, recorded with the holder''s mode');
SELECT tap._age199(tap._id199(2), tap.buyer(), 'buy_now', 121);
SELECT is(tap._claim199(tap._id199(2), tap.buyer(), 'auction')->>'claimed', 'true', 'Z.5: once abandoned, the other mode reclaims the same group row');

-- ── N. arguments ─────────────────────────────────────────────────────────────
SELECT is(tap._try199('SELECT public.claim_checkout_group(NULL, NULL, NULL)')->>'reason', 'missing_argument', 'N.1: NULL claim arguments');
SELECT is(tap._try199('SELECT public.release_checkout_group(NULL, NULL, NULL, NULL)')->>'reason', 'missing_argument', 'N.2: NULL release arguments');
SELECT is(tap._claim199(tap._id199(1), tap.buyer(), 'native_primary')->>'reason', 'invalid_mode', 'N.3: a non-listing mode is refused by reason, not by an error');
SELECT is(tap._row199(tap._id199(1), tap.buyer(), 'native_primary'), '{}'::jsonb, 'N.4: and leaves no row');

-- ── X. unchanged neighbours ──────────────────────────────────────────────────
SELECT is((SELECT concat_ws('|', status, stripe_payment_intent_id, coalesce(supersede_claim_token::text, 'null'))
             FROM public.payments WHERE id = tap._id199(11)), 'pending|pi_199_p1|null',
  'X.1: group claims never touch a payment row or its 130 claim columns');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname IN ('claim_checkout_group', 'release_checkout_group')), 2,
  'X.2: one definition each');
SELECT ok(coalesce(obj_description(to_regprocedure('public.claim_checkout_group(uuid,uuid,text)'), 'pg_proc'), '') LIKE '132:%'
      AND coalesce(obj_description(to_regprocedure('public.release_checkout_group(uuid,uuid,text,uuid)'), 'pg_proc'), '') LIKE '132:%'
      AND coalesce(obj_description(to_regclass('public.checkout_group_claim'), 'pg_class'), '') LIKE '132:%',
  'X.3: table and function comments record 132');
SELECT ok(to_regprocedure('public.claim_checkout_supersede(uuid,uuid,uuid)') IS NOT NULL
      AND to_regprocedure('public.release_checkout_supersede(uuid,uuid)') IS NOT NULL,
  'X.4: 130''s row-claim RPCs remain (the edge still uses them on reuse and supersede)');

SELECT * FROM finish();
ROLLBACK;

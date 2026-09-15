-- ============================================================================
-- 197_checkout_supersede_claim.sql — migration 130 (L1 concurrency residual).
--   A checkout request may hand out or supersede a PaymentIntent secret only
--   while it holds the (listing, buyer, mode) group claim:
--     public.claim_checkout_supersede(listing, buyer, payment)
--       -> {claimed, claim_token, holder_payment_id, reason}
--     public.release_checkout_supersede(payment, claim_token)
--       -> {released, reason}
--   A fresh claim on ANY pending row of the group refuses every other claim in
--   the group (so a second request can neither supersede P1 nor reuse the
--   replacement P2 while the first is mid-flight); a claim older than 120 s is
--   reclaimable (a crashed edge cannot wedge the buyer); release is bound to
--   the token (a late release never frees a reclaim). Claims serialize on the
--   listing row (payments -> listings, the established lock order) — the
--   concurrent proof is scripts/rehearsal_130_concurrency.sh, since pgTAP runs
--   in one transaction.
--
-- VERSION-AGNOSTIC: every call goes through tap._try197, so on a database
-- without 130 the suite completes and reports failures instead of aborting.
-- now() is frozen per transaction, so staleness is set by moving
-- supersede_claimed_at back explicitly (the state a claim made 121 s earlier
-- would leave).
-- ============================================================================
BEGIN;
SELECT plan(45);
SELECT tap.seed_core();

CREATE TABLE tap.memo_197 (k text PRIMARY KEY, v jsonb);
CREATE FUNCTION tap._store197(p_k text, p_v jsonb) RETURNS void LANGUAGE sql SECURITY DEFINER
  AS $m$ INSERT INTO tap.memo_197 VALUES (p_k, p_v) ON CONFLICT (k) DO UPDATE SET v = excluded.v $m$;
CREATE FUNCTION tap._get197(p_k text) RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_197 WHERE k = p_k $m$;
CREATE FUNCTION tap._try197(p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $f$
declare r jsonb;
begin
  execute p_sql into r;
  return r;
exception when others then
  return jsonb_build_object('__error', sqlstate || ' ' || sqlerrm);
end $f$;
CREATE FUNCTION tap._id197(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $m$ SELECT ('19700000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid $m$;
CREATE FUNCTION tap._claim197(p_listing uuid, p_buyer uuid, p_pay uuid) RETURNS jsonb LANGUAGE sql
  AS $m$ SELECT tap._try197(format('SELECT public.claim_checkout_supersede(%L::uuid, %L::uuid, %L::uuid)', p_listing, p_buyer, p_pay)) $m$;
CREATE FUNCTION tap._release197(p_pay uuid, p_token text) RETURNS jsonb LANGUAGE sql
  AS $m$ SELECT tap._try197(format('SELECT public.release_checkout_supersede(%L::uuid, %L::uuid)', p_pay, p_token)) $m$;
-- move a claim back in time without depending on the column existing
CREATE FUNCTION tap._age197(p_pay uuid, p_seconds int) RETURNS jsonb LANGUAGE sql
  AS $m$ SELECT tap._try197(format('WITH u AS (UPDATE public.payments SET supersede_claimed_at = now() - make_interval(secs => %s) WHERE id = %L::uuid RETURNING 1) SELECT jsonb_build_object(''aged'', count(*)) FROM u', p_seconds, p_pay)) $m$;
-- the claim columns, read without depending on them existing
CREATE FUNCTION tap._col197(p_pay uuid) RETURNS jsonb LANGUAGE sql
  AS $m$ SELECT tap._try197(format('SELECT jsonb_build_object(''token'', supersede_claim_token, ''at'', supersede_claimed_at) FROM public.payments WHERE id = %L::uuid', p_pay)) $m$;

-- ── FIXTURE — one listing L; the holder's pending buy_now P1 and P2, a pending
-- auction-mode row A1, another buyer's pending buy_now O1, and a failed F1. ──
INSERT INTO public.listings
  (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
   starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
VALUES (tap._id197(1), tap.seller(), 'Fixture 197', 'Club 197', 'wynwood', current_date + 30, '21:00', 'GA', 2,
        'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/197.jpg', 'active');
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total,
                             stripe_payment_intent_id, status, mode, created_at, stripe_livemode)
VALUES (tap._id197(11), tap._id197(1), tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_197_p1', 'pending', 'buy_now', now(), false),
       (tap._id197(12), tap._id197(1), tap.buyer(),      tap.seller(), 30000, 3000, 3000, 33000, 'pi_197_p2', 'pending', 'buy_now', now(), false),
       (tap._id197(13), tap._id197(1), tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_197_a1', 'pending', 'auction', now(), false),
       (tap._id197(14), tap._id197(1), tap.other_user(), tap.seller(), 20000, 2000, 2000, 22000, 'pi_197_o1', 'pending', 'buy_now', now(), false),
       (tap._id197(15), tap._id197(1), tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_197_f1', 'failed',  'buy_now', now(), false);

-- ── A. definition and grants ─────────────────────────────────────────────────
SELECT has_column('public', 'payments', 'supersede_claim_token', 'A.1: payments.supersede_claim_token exists');
SELECT has_column('public', 'payments', 'supersede_claimed_at', 'A.2: payments.supersede_claimed_at exists');
SELECT ok(to_regprocedure('public.claim_checkout_supersede(uuid,uuid,uuid)') IS NOT NULL, 'A.3: claim_checkout_supersede(uuid,uuid,uuid) exists');
SELECT ok(to_regprocedure('public.release_checkout_supersede(uuid,uuid)') IS NOT NULL, 'A.4: release_checkout_supersede(uuid,uuid) exists');
SELECT ok(coalesce((SELECT bool_and(p.prosecdef AND p.proconfig = ARRAY['search_path=""'] AND (p.prorettype::regtype)::text = 'jsonb')
                      FROM pg_proc p WHERE p.oid IN (to_regprocedure('public.claim_checkout_supersede(uuid,uuid,uuid)'),
                                                     to_regprocedure('public.release_checkout_supersede(uuid,uuid)'))
                      HAVING count(*) = 2), false),
  'A.5: both are SECURITY DEFINER, search_path pinned to empty, return jsonb');
SELECT ok(coalesce((SELECT bool_and(has_function_privilege('service_role', p.oid, 'EXECUTE')
                                    AND NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')
                                    AND NOT has_function_privilege('anon', p.oid, 'EXECUTE'))
                      FROM pg_proc p WHERE p.oid IN (to_regprocedure('public.claim_checkout_supersede(uuid,uuid,uuid)'),
                                                     to_regprocedure('public.release_checkout_supersede(uuid,uuid)'))
                      HAVING count(*) = 2), false),
  'A.6: service_role only — no EXECUTE for anon or authenticated');
SELECT ok((SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'payments'
             AND column_name IN ('supersede_claim_token', 'supersede_claimed_at')) = 2
      AND NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'payments' AND cmd IN ('UPDATE', 'ALL')),
  'A.7: the claim columns exist and no client UPDATE policy reaches them (payments carries SELECT-only policies)');

-- ── C. claim semantics ───────────────────────────────────────────────────────
SELECT tap._store197('c1', tap._claim197(tap._id197(1), tap.buyer(), tap._id197(11)));
SELECT is(concat_ws('/', tap._get197('c1')->>'claimed', tap._get197('c1')->>'reason', tap._get197('c1')->>'holder_payment_id'),
  'true/claimed/' || tap._id197(11), 'C.1: claiming the holder''s pending P1 succeeds');
SELECT ok(coalesce(tap._get197('c1')->>'claim_token', '') ~ '^[0-9a-f-]{36}$', 'C.2: …and returns a claim token');
SELECT is(concat_ws('/', tap._col197(tap._id197(11))->>'token', ((tap._col197(tap._id197(11))->>'at')::timestamptz = now())::text),
  (tap._get197('c1')->>'claim_token') || '/true', 'C.3: …stored on P1 with claimed_at = now()');
SELECT is((SELECT status FROM public.payments WHERE id = tap._id197(11)), 'pending', 'C.4: a claim changes no status');

SELECT tap._store197('c5', tap._claim197(tap._id197(1), tap.buyer(), tap._id197(11)));
SELECT is(concat_ws('/', tap._get197('c5')->>'claimed', tap._get197('c5')->>'reason', tap._get197('c5')->>'holder_payment_id'),
  'false/claim_held/' || tap._id197(11), 'C.5: a second claim on P1 while fresh is refused (no second supersede)');
SELECT ok(tap._get197('c5') ? 'claimed' AND (tap._get197('c5')->'claim_token' IS NULL OR jsonb_typeof(tap._get197('c5')->'claim_token') = 'null'), 'C.6: …with no token');

SELECT tap._store197('c7', tap._claim197(tap._id197(1), tap.buyer(), tap._id197(12)));
SELECT is(concat_ws('/', tap._get197('c7')->>'claimed', tap._get197('c7')->>'reason', tap._get197('c7')->>'holder_payment_id'),
  'false/claim_held/' || tap._id197(11), 'C.7: THE GAP — claiming the replacement P2 while P1 is claimed is refused (no reuse of P2''s secret)');
SELECT ok(tap._col197(tap._id197(12)) ? 'token' AND tap._col197(tap._id197(12))->>'token' IS NULL, 'C.8: …and P2 carries no claim');

SELECT tap._store197('c9', tap._claim197(tap._id197(1), tap.buyer(), tap._id197(13)));
SELECT is(concat_ws('/', tap._get197('c9')->>'claimed', tap._get197('c9')->>'reason'), 'true/claimed',
  'C.9: the same buyer''s auction-mode row is a different group — claimable');
SELECT tap._store197('c10', tap._claim197(tap._id197(1), tap.other_user(), tap._id197(14)));
SELECT is(concat_ws('/', tap._get197('c10')->>'claimed', tap._get197('c10')->>'reason'), 'true/claimed',
  'C.10: another buyer''s pending row on the listing is a different group — claimable');

-- ── R. token-bound release ───────────────────────────────────────────────────
SELECT tap._store197('r1', tap._release197(tap._id197(11), gen_random_uuid()::text));
SELECT is(concat_ws('/', tap._get197('r1')->>'released', tap._get197('r1')->>'reason'), 'false/token_mismatch',
  'R.1: a release with the wrong token is refused');
SELECT is(tap._claim197(tap._id197(1), tap.buyer(), tap._id197(12))->>'reason', 'claim_held', 'R.2: …so the group stays claimed');
SELECT tap._store197('r3', tap._release197(tap._id197(11), tap._get197('c1')->>'claim_token'));
SELECT is(concat_ws('/', tap._get197('r3')->>'released', tap._get197('r3')->>'reason'), 'true/released', 'R.3: the right token releases');
SELECT ok(tap._col197(tap._id197(11)) ? 'token' AND tap._col197(tap._id197(11))->>'token' IS NULL AND tap._col197(tap._id197(11))->>'at' IS NULL,
  'R.4: …and clears both columns');
SELECT tap._store197('r5', tap._release197(tap._id197(11), tap._get197('c1')->>'claim_token'));
SELECT is(concat_ws('/', tap._get197('r5')->>'released', tap._get197('r5')->>'reason'), 'false/not_claimed', 'R.5: releasing again is a no-op (not_claimed)');
SELECT tap._store197('r6', tap._claim197(tap._id197(1), tap.buyer(), tap._id197(12)));
SELECT is(concat_ws('/', tap._get197('r6')->>'claimed', tap._get197('r6')->>'reason'), 'true/claimed', 'R.6: after release the replacement P2 is claimable');

-- ── S. staleness and reclaim ─────────────────────────────────────────────────
SELECT tap._store197('s_tok_old', to_jsonb(tap._get197('r6')->>'claim_token'));
SELECT tap._age197(tap._id197(12), 121);
SELECT tap._store197('s1', tap._claim197(tap._id197(1), tap.buyer(), tap._id197(11)));
SELECT is(concat_ws('/', tap._get197('s1')->>'claimed', tap._get197('s1')->>'reason'), 'true/claimed',
  'S.1: a sibling claim older than 120 s does not block (a crashed edge cannot wedge the buyer)');
SELECT tap._store197('s2', tap._claim197(tap._id197(1), tap.buyer(), tap._id197(12)));
SELECT is(tap._get197('s2')->>'reason', 'claim_held', 'S.2: …and the new claim on P1 blocks P2 again');
SELECT tap._age197(tap._id197(11), 119);
SELECT is(tap._claim197(tap._id197(1), tap.buyer(), tap._id197(12))->>'reason', 'claim_held', 'S.3: a claim 119 s old is still fresh');
SELECT tap._age197(tap._id197(11), 121);
SELECT tap._store197('s4', tap._claim197(tap._id197(1), tap.buyer(), tap._id197(11)));
SELECT is(concat_ws('/', tap._get197('s4')->>'claimed', ((tap._get197('s4')->>'claim_token') <> (tap._get197('s1')->>'claim_token'))::text), 'true/true',
  'S.4: a stale claim on P1 itself is reclaimed with a NEW token');
SELECT is(tap._release197(tap._id197(11), tap._get197('s1')->>'claim_token')->>'reason', 'token_mismatch',
  'S.5: the superseded holder''s late release cannot free the reclaim');
SELECT ok(tap._col197(tap._id197(11)) ? 'token' AND tap._col197(tap._id197(11))->>'token' = tap._get197('s4')->>'claim_token', 'S.6: …the reclaim''s token is still in place');
SELECT is(tap._release197(tap._id197(12), tap._get197('s_tok_old') #>> '{}')->>'reason', 'released',
  'S.7: the stale holder may still clear its OWN row with its own token (no lingering state)');

-- ── Q. a fresh claim on a row that has LEFT pending still blocks its group ────
-- (D-5 Q3.) Mid-supersede the holder's claimed P1 can settle (or fail) while
-- its replacement P2 is pending; if P1's claim stopped counting, a second
-- request could claim P2 and hand out its secret before the holder withdraws
-- P2. A second success on the listing is not prevented by settlement — it is
-- recorded 'unfulfillable' and refunded — so the claim must keep blocking.
INSERT INTO public.listings
  (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
   starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
VALUES (tap._id197(2), tap.seller(), 'Fixture 197 Q', 'Club 197', 'wynwood', current_date + 30, '21:00', 'GA', 2,
        'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/197.jpg', 'active');
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total,
                             stripe_payment_intent_id, status, mode, created_at, stripe_livemode)
VALUES (tap._id197(21), tap._id197(2), tap.buyer(), tap.seller(), 20000, 2000, 2000, 22000, 'pi_197_q1', 'pending', 'buy_now', now(), false),
       (tap._id197(22), tap._id197(2), tap.buyer(), tap.seller(), 30000, 3000, 3000, 33000, 'pi_197_q2', 'pending', 'buy_now', now(), false),
       (tap._id197(23), tap._id197(2), tap.buyer(), tap.seller(), 30000, 3000, 3000, 33000, 'pi_197_q3', 'pending', 'buy_now', now(), false);
SELECT tap._store197('q1', tap._claim197(tap._id197(2), tap.buyer(), tap._id197(21)));
UPDATE public.payments SET status = 'succeeded', paid_at = now() WHERE id = tap._id197(21);   -- P1 settles mid-supersede
SELECT tap._store197('q2', tap._claim197(tap._id197(2), tap.buyer(), tap._id197(22)));
SELECT is(concat_ws('/', tap._get197('q2')->>'claimed', tap._get197('q2')->>'reason', tap._get197('q2')->>'holder_payment_id'),
  'false/claim_held/' || tap._id197(21), 'Q.1: a fresh claim on a row that has SETTLED still blocks the replacement P2 (no second hand-out)');
SELECT is(tap._release197(tap._id197(21), tap._get197('q1')->>'claim_token')->>'reason', 'released',
  'Q.2: the holder releases its claim on the settled row with its token');
SELECT is(tap._claim197(tap._id197(2), tap.buyer(), tap._id197(22))->>'reason', 'claimed',
  'Q.3: once released, the group is claimable again');
SELECT tap._store197('q4', tap._claim197(tap._id197(2), tap.buyer(), tap._id197(23)));
SELECT is(tap._get197('q4')->>'reason', 'claim_held', 'Q.4: …and that new claim on P2 blocks P3 as before');
UPDATE public.payments SET status = 'failed' WHERE id = tap._id197(22);                        -- the claimed row fails
SELECT tap._age197(tap._id197(22), 121);
SELECT is(tap._claim197(tap._id197(2), tap.buyer(), tap._id197(23))->>'reason', 'claimed',
  'Q.5: a STALE claim on a row that left pending does not block (a crashed holder still lapses at 120 s)');

-- ── N. refusals ──────────────────────────────────────────────────────────────
SELECT is(tap._claim197(tap._id197(1), tap.buyer(), tap._id197(15))->>'reason', 'not_pending', 'N.1: a failed row is not claimable');
UPDATE public.payments SET status = 'succeeded', paid_at = now() WHERE id = tap._id197(14);
SELECT is(tap._claim197(tap._id197(1), tap.other_user(), tap._id197(14))->>'reason', 'not_pending', 'N.2: a succeeded row is not claimable');
SELECT is(tap._claim197(tap._id197(1), tap.buyer(), gen_random_uuid())->>'reason', 'unknown_payment', 'N.3: unknown payment');
SELECT is(tap._claim197(tap._id197(1), tap.other_user(), tap._id197(12))->>'reason', 'payment_not_for_listing_buyer', 'N.4: a payment of another buyer');
SELECT is(tap._claim197(tap.listing_a(), tap.buyer(), tap._id197(12))->>'reason', 'payment_not_for_listing_buyer', 'N.5: a payment of another listing');
SELECT is(tap._try197('SELECT public.claim_checkout_supersede(NULL, NULL, NULL)')->>'reason', 'missing_argument', 'N.6: NULL arguments');
SELECT is(tap._try197('SELECT public.release_checkout_supersede(NULL, NULL)')->>'reason', 'missing_argument', 'N.7: NULL release arguments');

-- ── X. unchanged neighbours ──────────────────────────────────────────────────
SELECT is((SELECT count(*)::int FROM public.payments WHERE id IN (tap._id197(11), tap._id197(12), tap._id197(13)) AND status = 'pending'), 3,
  'X.1: claims and releases never change a payment''s status');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname IN ('claim_checkout_supersede', 'release_checkout_supersede')), 2,
  'X.2: one definition each');
SELECT ok(coalesce(obj_description(to_regprocedure('public.claim_checkout_supersede(uuid,uuid,uuid)'), 'pg_proc'), '') LIKE '130:%'
      AND coalesce(obj_description(to_regprocedure('public.release_checkout_supersede(uuid,uuid)'), 'pg_proc'), '') LIKE '130:%',
  'X.3: both comments record 130');

SELECT * FROM finish();
ROLLBACK;

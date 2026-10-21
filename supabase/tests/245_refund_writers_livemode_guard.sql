-- ============================================================================
-- 245_refund_writers_livemode_guard.sql — registry 175 (migration 20261021135000_refund_writers_livemode_guard.sql).
-- Backlog BE-22 (F-MODE-BOUNDARY-DUPLICATED-1): the SQL refund writers record a refund fact for a payment row of
-- ANY mode. public.record_refund_state and public.record_payment_refund had no stripe_livemode check, while the
-- payout claim (claim_payout_attempt, 045) refuses a non-live row and settle_verified_payment cross-checks the row
-- against Stripe's livemode. REPRODUCED on a production-replay clone before 175 was written
-- (private-evidence/A-sprint-20261021/a175/01_red.out: a test-mode row and a NULL row each recorded a refund).
--
-- 175's rule (one shared helper, public.assert_refund_livemode(uuid, boolean)): the 045 predicate of
-- claim_payout_attempt, verbatim — a row is admitted iff stripe_livemode = true, or stripe_livemode = false while
-- app.allow_test_mode_money = 'on' (the sandbox switch; never set in production). NULL is never admitted. A refused
-- call RAISEs 'LIVEMODE_MISMATCH' (P0001, HINT LIVEMODE_MISMATCH) on the locked row before any write.
--
-- Under test:
--   S  objects and grants: the helper (no client EXECUTE), the writers' signatures/definer/search_path/ACL unchanged;
--   W  the switch unset (production): live rows recorded; false and NULL rows refused, nothing written; the exact
--      refusal (message, hint, detail, SQLSTATE); unknown payments and every pre-existing refusal unchanged and
--      still first;
--   G  the sandbox switch: false admitted only by exactly 'on'; NULL never; live always (claim_payout_attempt's
--      asymmetry, so the refund-record refusal set equals the payout refusal set);
--   V  settle_verified_payment: its own binding check is unchanged; its full-refund branch reaches
--      record_payment_refund and is now refused on a non-admitted row (whole call rolled back);
--   C  every edge caller's exact argument shape (stripe-webhook, enforce-transfer-expiry) on a live row is unchanged.
-- Runs as postgres inside BEGIN … ROLLBACK; the writers are called as service_role, as the edges call them.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(52);
SELECT tap.seed_core();
SELECT tap.logout();

-- ── fixtures (transaction-local) ────────────────────────────────────────────
-- One succeeded buy_now payment per case (total 11000) with the given stripe_livemode; its own listing, so the
-- one-success-per-listing index never interferes.
CREATE FUNCTION tap._p245(n int, p_live boolean) RETURNS uuid LANGUAGE plpgsql AS $f$
DECLARE
  v_l uuid := ('dddddddd-0000-0000-0245-' || lpad(n::text, 12, '0'))::uuid;
  v_p uuid := ('eeeeeeee-0000-0000-0245-' || lpad(n::text, 12, '0'))::uuid;
BEGIN
  INSERT INTO public.listings
    (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity,
     transfer_method, starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at,
     current_bid, cover_image_path, auction_status)
  VALUES (v_l, tap.seller(), 'LM Event ' || n, 'Club', 'wynwood', current_date + 30, '21:00', 'GA', 1,
          'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/lm.jpg', 'active');
  INSERT INTO public.payments
    (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id,
     status, mode, paid_at, stripe_livemode)
  VALUES (v_p, v_l, tap.buyer(), tap.seller(), 10000, 1000, 1000, 11000, 'pi_lm245_' || n,
          'succeeded', 'buy_now', now(), p_live);
  RETURN v_p;
END $f$;
CREATE FUNCTION tap._pid245(n int) RETURNS uuid LANGUAGE sql AS $f$
  SELECT ('eeeeeeee-0000-0000-0245-' || lpad(n::text, 12, '0'))::uuid $f$;

-- Run one statement as service_role. 'OK <result>' or 'ERR <sqlstate>|<message>|<detail>|<hint>'.
CREATE FUNCTION tap._as_service245(p_sql text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE v text; m text; d text; h text; s text;
BEGIN
  PERFORM tap.login_service();
  BEGIN
    EXECUTE p_sql INTO v;
    v := 'OK ' || coalesce(v, '<null>');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS s = RETURNED_SQLSTATE, m = MESSAGE_TEXT, d = PG_EXCEPTION_DETAIL, h = PG_EXCEPTION_HINT;
    v := 'ERR ' || s || '|' || m || '|' || coalesce(d, '') || '|' || coalesce(h, '');
  END;
  PERFORM tap.logout();
  RETURN v;
END $f$;
-- The writers with the edges' argument shapes.
CREATE FUNCTION tap._rrs245(n int, p_re text, p_status text DEFAULT 'succeeded', p_amount int DEFAULT 1000,
                            p_source text DEFAULT 'dashboard', p_via text DEFAULT 'webhook') RETURNS text
LANGUAGE sql AS $f$
  SELECT tap._as_service245(format(
    'SELECT public.record_refund_state(%L, %L, %L, %s, NULL, %L, %L)::text',
    'pi_lm245_' || n, p_re, p_status, coalesce(p_amount::text, 'NULL'), p_source, p_via)) $f$;
CREATE FUNCTION tap._rpr245(n int, p_re text, p_dispute text, p_amount int, p_source text) RETURNS text
LANGUAGE sql AS $f$
  SELECT tap._as_service245(format(
    'SELECT public.record_payment_refund(%L, %L, %L, %s, %L)::text',
    'pi_lm245_' || n, p_re, p_dispute, coalesce(p_amount::text, 'NULL'), p_source)) $f$;
-- Every money fact a refund writer can touch on one payment.
CREATE FUNCTION tap._facts245(n int) RETURNS text LANGUAGE sql AS $f$
  SELECT format('%s/%s/%s/%s/%s/%s/%s/%s/%s', p.status, coalesce(p.amount_refunded_cents, 0), coalesce(p.stripe_refund_id, '-'),
                p.refund_requested_cents, p.refund_succeeded_cents, p.refund_failed_cents,
                (SELECT count(*) FROM public.payment_refund_state s WHERE s.payment_id = p.id),
                (SELECT count(*) FROM public.payment_refund_state_log s WHERE s.payment_id = p.id),
                (SELECT count(*) FROM public.payment_refunds r WHERE r.payment_id = p.id))
    FROM public.payments p WHERE p.id = tap._pid245(n) $f$;
-- The untouched shape: succeeded, nothing refunded, no state, no log, no ledger row.
CREATE FUNCTION tap._clean245() RETURNS text LANGUAGE sql AS $f$ SELECT 'succeeded/0/-/0/0/0/0/0/0'::text $f$;
CREATE FUNCTION tap._refused245(n int, p_live text, p_switch text) RETURNS text LANGUAGE sql AS $f$
  SELECT 'ERR P0001|LIVEMODE_MISMATCH|payment ' || tap._pid245(n) || ' stripe_livemode=' || p_live
         || ' app.allow_test_mode_money=' || p_switch || '|LIVEMODE_MISMATCH' $f$;

SELECT tap._p245(1, true),   tap._p245(2, false),  tap._p245(3, NULL),
       tap._p245(4, true),   tap._p245(5, false),  tap._p245(6, NULL),
       tap._p245(7, false),  tap._p245(8, NULL),   tap._p245(9, true),
       tap._p245(10, false), tap._p245(11, NULL),  tap._p245(12, false),
       tap._p245(13, true),  tap._p245(14, false), tap._p245(15, NULL),
       tap._p245(16, true),  tap._p245(17, true),  tap._p245(18, true),
       tap._p245(19, false), tap._p245(20, NULL),  tap._p245(21, true);

-- ── S — objects and grants ──────────────────────────────────────────────────
SELECT ok(to_regprocedure('public.assert_refund_livemode(uuid,boolean)') IS NOT NULL
          AND (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'assert_refund_livemode') = 1,
  'S1: exactly one public.assert_refund_livemode, signature (uuid, boolean)');
SELECT ok((SELECT p.prorettype = 'void'::regtype AND NOT p.prosecdef AND p.proconfig = ARRAY['search_path=""']
                  AND l.lanname = 'plpgsql' AND p.provolatile = 's'
             FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang
            WHERE p.oid = to_regprocedure('public.assert_refund_livemode(uuid,boolean)')),
  'S2: the helper returns void, SECURITY INVOKER, STABLE plpgsql, search_path=''''');
SELECT ok((SELECT p.proacl IS NOT NULL
                  AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
                  AND NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')
                  AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0)
             FROM pg_proc p WHERE p.oid = to_regprocedure('public.assert_refund_livemode(uuid,boolean)')),
  'S3: no client EXECUTE on the helper (anon, authenticated and PUBLIC hold none; ACL not defaulted)');
SELECT ok((SELECT p.prosecdef AND p.proconfig = ARRAY['search_path=""'] AND p.prorettype = 'jsonb'::regtype
             FROM pg_proc p WHERE p.oid = to_regprocedure('public.record_refund_state(text,text,text,integer,text,text,text)'))
      AND (SELECT p.prosecdef AND p.proconfig = ARRAY['search_path=public'] AND p.prorettype = 'jsonb'::regtype
             FROM pg_proc p WHERE p.oid = to_regprocedure('public.record_payment_refund(text,text,text,integer,text)')),
  'S4: both writers keep their signatures, SECURITY DEFINER, search_path and jsonb result');
SELECT ok(NOT has_function_privilege('anon', 'public.record_refund_state(text,text,text,integer,text,text,text)', 'EXECUTE')
      AND NOT has_function_privilege('authenticated', 'public.record_refund_state(text,text,text,integer,text,text,text)', 'EXECUTE')
      AND has_function_privilege('service_role', 'public.record_refund_state(text,text,text,integer,text,text,text)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.record_payment_refund(text,text,text,integer,text)', 'EXECUTE')
      AND NOT has_function_privilege('authenticated', 'public.record_payment_refund(text,text,text,integer,text)', 'EXECUTE')
      AND has_function_privilege('service_role', 'public.record_payment_refund(text,text,text,integer,text)', 'EXECUTE'),
  'S5: only service_role may execute the two writers (unchanged)');
SELECT is((SELECT count(*)::int FROM pg_proc p
            WHERE p.oid IN (to_regprocedure('public.record_refund_state(text,text,text,integer,text,text,text)'),
                            to_regprocedure('public.record_payment_refund(text,text,text,integer,text)'))
              AND p.prosrc LIKE '%PERFORM public.assert_refund_livemode(v_pay.id, v_pay.stripe_livemode);%'), 2,
  'S6: both writers call the one shared helper on the locked row');

-- ── W — the switch unset (production) ───────────────────────────────────────
SELECT is(current_setting('app.allow_test_mode_money', true), NULL, 'W0: the sandbox switch is unset (production)');
SELECT matches(tap._rrs245(1, 're_lm245_1'), '^OK \{.*"recorded": true', 'W1: record_refund_state records a refund on a live row (control)');
SELECT is(tap._facts245(1), 'succeeded/1000/re_lm245_1/0/1000/0/1/1/1', 'W2: …and every money fact moves as before');
SELECT is(tap._rrs245(2, 're_lm245_2'), tap._refused245(2, 'false', 'unset'),
  'W3: record_refund_state refuses a test-mode row: P0001 LIVEMODE_MISMATCH, exact DETAIL, HINT LIVEMODE_MISMATCH');
SELECT is(tap._facts245(2), tap._clean245(), 'W4: …and writes nothing (no state, no log, no ledger, no counters)');
SELECT is(tap._rrs245(3, 're_lm245_3', 'pending', 1000, 'expiry', 'create_response'), tap._refused245(3, 'null', 'unset'),
  'W5: record_refund_state refuses a NULL (unclassified) row');
SELECT is(tap._facts245(3), tap._clean245(), 'W6: …and writes nothing');
SELECT matches(tap._rpr245(4, 're_lm245_4', NULL, 1000, 'dashboard'), '^OK \{.*"recorded": true', 'W7: record_payment_refund records on a live row (control)');
SELECT is(tap._facts245(4), 'succeeded/1000/re_lm245_4/0/0/0/0/0/1', 'W8: …and the one-way record moves as before');
SELECT is(tap._rpr245(5, NULL, 'dp_lm245_5', 1000, 'dispute_lost'), tap._refused245(5, 'false', 'unset'),
  'W9: record_payment_refund refuses a lost dispute on a test-mode row');
SELECT is(tap._facts245(5), tap._clean245(), 'W10: …and writes nothing');
SELECT is(tap._rpr245(6, 're_lm245_6', NULL, NULL, 'dashboard'), tap._refused245(6, 'null', 'unset'),
  'W11: record_payment_refund refuses a full refund on a NULL row');
SELECT is(tap._facts245(6), tap._clean245(), 'W12: …and writes nothing');
SELECT is(tap._rrs245(7, 're_lm245_7', 'failed', 1000), tap._refused245(7, 'false', 'unset'),
  'W13: a failed refund observation on a test-mode row is refused too (state is written for every status)');
SELECT is(tap._as_service245($$SELECT public.record_refund_state('pi_lm245_none', 're_lm245_x', 'succeeded', 1000, NULL, 'dashboard', 'webhook')::text$$),
          'OK {"reason": "unknown_payment", "recorded": false, "payment_id": null}',
  'W14: an unknown payment is still acknowledged, never refused (record_refund_state)');
SELECT is(tap._as_service245($$SELECT public.record_payment_refund('pi_lm245_none', 're_lm245_y', NULL, 1000, 'dashboard')::text$$),
          'OK {"reason": "unknown_payment", "status": null, "recorded": false, "payment_id": null, "amount_refunded_cents": null}',
  'W15: an unknown payment is still acknowledged, never refused (record_payment_refund)');
-- the pre-existing refusals are byte-identical and still win over the mode check (they run before the row lookup)
SELECT is(tap._as_service245($$SELECT public.record_refund_state('pi_lm245_8', NULL, 'succeeded', 1000, NULL, 'dashboard', 'webhook')::text$$),
          'ERR P0001|REFUND_REFERENCE_REQUIRED||', 'W16: REFUND_REFERENCE_REQUIRED unchanged and first, even on a NULL row');
SELECT is(tap._as_service245($$SELECT public.record_refund_state('pi_lm245_8', 're_lm245_8', 'bogus', 1000, NULL, 'dashboard', 'webhook')::text$$),
          'ERR P0001|INVALID_REFUND_STATUS|bogus|', 'W17: INVALID_REFUND_STATUS unchanged and first');
SELECT is(tap._as_service245($$SELECT public.record_refund_state('pi_lm245_8', 're_lm245_8', 'pending', 1000, NULL, 'dashboard', 'bogus')::text$$),
          'ERR P0001|INVALID_OBSERVATION_SOURCE|bogus|', 'W18: INVALID_OBSERVATION_SOURCE unchanged and first');
SELECT is(tap._as_service245($$SELECT public.record_refund_state('pi_lm245_8', 're_lm245_8', 'pending', -1, NULL, 'dashboard', 'webhook')::text$$),
          'ERR P0001|INVALID_REFUND_AMOUNT|-1|', 'W19: INVALID_REFUND_AMOUNT unchanged and first');
SELECT is(tap._as_service245($$SELECT public.record_payment_refund('pi_lm245_8', 're_lm245_8', NULL, 1000, 'bogus')::text$$),
          'ERR P0001|INVALID_REFUND_SOURCE|bogus|', 'W20: record_payment_refund INVALID_REFUND_SOURCE unchanged and first');
SELECT is(tap._as_service245($$SELECT public.record_payment_refund('pi_lm245_8', NULL, NULL, 1000, 'dashboard')::text$$),
          'ERR P0001|REFUND_REFERENCE_REQUIRED||', 'W21: record_payment_refund REFUND_REFERENCE_REQUIRED unchanged and first');
SELECT is(tap._as_service245($$SELECT public.record_payment_refund('pi_lm245_8', NULL, NULL, 1000, 'dispute_lost')::text$$),
          'ERR P0001|REFUND_REFERENCE_REQUIRED||', 'W22: …and for dispute_lost with no reference at all');
SELECT is(tap._facts245(8), tap._clean245(), 'W23: none of W16-W22 wrote anything');
-- REFUND_PAYMENT_MISMATCH (a refund id already bound to another payment) is unchanged on live rows
SELECT is(tap._rrs245(9, 're_lm245_1'), 'ERR P0001|REFUND_PAYMENT_MISMATCH|re_lm245_1|',
  'W24: REFUND_PAYMENT_MISMATCH unchanged on a live row');

-- ── G — the sandbox switch (app.allow_test_mode_money; transaction-local here) ─
SELECT set_config('app.allow_test_mode_money', 'on', true);
SELECT matches(tap._rrs245(10, 're_lm245_10'), '^OK \{.*"recorded": true', 'G1: switch on: a test-mode row is recorded (record_refund_state)');
SELECT is(tap._facts245(10), 'succeeded/1000/re_lm245_10/0/1000/0/1/1/1', 'G2: …with every money fact');
SELECT is(tap._rrs245(11, 're_lm245_11'), tap._refused245(11, 'null', 'on'), 'G3: switch on: a NULL row is still refused (never admitted)');
SELECT is(tap._facts245(11), tap._clean245(), 'G4: …and writes nothing');
SELECT matches(tap._rpr245(12, NULL, 'dp_lm245_12', 1000, 'dispute_lost'), '^OK \{.*"recorded": true', 'G5: switch on: a lost dispute on a test-mode row is recorded (record_payment_refund)');
SELECT matches(tap._rrs245(13, 're_lm245_13'), '^OK \{.*"recorded": true', 'G6: switch on: a live row is still recorded (claim_payout_attempt''s asymmetry)');
SELECT set_config('app.allow_test_mode_money', 'off', true);
SELECT is(tap._rrs245(14, 're_lm245_14'), tap._refused245(14, 'false', 'off'), 'G7: switch ''off'': a test-mode row is refused');
SELECT set_config('app.allow_test_mode_money', 'ON', true);
SELECT is(tap._rrs245(14, 're_lm245_14'), tap._refused245(14, 'false', 'ON'), 'G8: only exactly ''on'' admits (''ON'' does not)');
SELECT set_config('app.allow_test_mode_money', '', true);
SELECT is(tap._rrs245(14, 're_lm245_14'), tap._refused245(14, 'false', 'unset'), 'G9: an empty (reset) switch refuses');
SELECT is(tap._facts245(14), tap._clean245(), 'G10: G7-G9 wrote nothing');
-- the rule itself, every (mode x switch) cell, against the payout claim's predicate (claim_payout_attempt, 045)
CREATE FUNCTION tap._cell245(p_live boolean, p_switch text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE v_helper text; v_payout text;
BEGIN
  PERFORM set_config('app.allow_test_mode_money', coalesce(p_switch, ''), true);
  BEGIN
    PERFORM public.assert_refund_livemode(tap._pid245(99), p_live);
    v_helper := 'admit';
  EXCEPTION WHEN OTHERS THEN v_helper := 'refuse';
  END;
  -- claim_payout_attempt's mode condition, copied from its production body (b6aae868…, lines 84-86)
  v_payout := CASE WHEN p_live IS DISTINCT FROM true
                        AND NOT (p_live IS NOT DISTINCT FROM false
                                 AND coalesce(current_setting('app.allow_test_mode_money', true), 'off') = 'on')
                   THEN 'refuse' ELSE 'admit' END;
  PERFORM set_config('app.allow_test_mode_money', '', true);
  RETURN v_helper || '=' || v_payout;
END $f$;
SELECT is((SELECT string_agg(coalesce(m::text, 'null') || '/' || coalesce(s, 'unset') || ':' || tap._cell245(m, s), ' ' ORDER BY mo, so)
             FROM (VALUES (1, true), (2, false), (3, NULL::boolean)) mm(mo, m)
            CROSS JOIN (VALUES (1, NULL::text), (2, 'off'), (3, 'on')) ss(so, s)),
          'true/unset:admit=admit true/off:admit=admit true/on:admit=admit false/unset:refuse=refuse false/off:refuse=refuse false/on:admit=admit null/unset:refuse=refuse null/off:refuse=refuse null/on:refuse=refuse',
  'G11: all nine (mode x switch) cells: the refund writers'' rule = the payout claim''s rule');
SELECT is(current_setting('app.allow_test_mode_money', true), '', 'G12: the switch is back to unset-equivalent for the rest of the file');

-- ── V — settle_verified_payment ─────────────────────────────────────────────
SELECT is(tap._as_service245($$SELECT outcome FROM public.settle_verified_payment('pi_lm245_19', 'succeeded', 11000, 'usd', true, 0, NULL, 'card', '{}'::jsonb, 'test245')$$),
          'OK binding_mismatch', 'V1: settle''s own binding check is unchanged (test-mode row, live PaymentIntent -> binding_mismatch)');
SELECT is(tap._as_service245($$SELECT outcome FROM public.settle_verified_payment('pi_lm245_20', 'succeeded', 11000, 'usd', false, 11000, 're_lm245_20', 'card', '{}'::jsonb, 'test245')$$),
          tap._refused245(20, 'null', 'unset'),
  'V2: settle''s full-refund branch on a NULL row now reaches the refused writer and raises (no caller reaches it: the sweep never fetches NULL rows)');
SELECT is(tap._facts245(20), tap._clean245(), 'V3: …and the whole settle call is rolled back (nothing written)');
SELECT is(tap._as_service245($$SELECT outcome FROM public.settle_verified_payment('pi_lm245_21', 'succeeded', 11000, 'usd', true, 11000, 're_lm245_21', 'card', '{}'::jsonb, 'test245')$$),
          'OK refunded', 'V4: settle''s full-refund branch on a live row is unchanged (control)');
SELECT is(tap._facts245(21), 'refunded/11000/re_lm245_21/0/0/0/0/0/1', 'V5: …with the refund recorded through record_payment_refund');

-- ── C — the edge callers' exact shapes on live rows (origin/release/production-gate-20260918) ─
-- stripe-webhook/index.ts:779 (charge.refunded) and :984 (refund.*): observed_via 'webhook', source from metadata
SELECT matches(tap._rrs245(16, 're_lm245_16', 'requires_action', 1000, 'expiry', 'webhook'), '^OK \{.*"recorded": true', 'C1: stripe-webhook refund.* shape on a live row');
-- enforce-transfer-expiry/index.ts:154 recordRefundState: create_response (Phase 1 2e) and reconcile (Phase 0 / 1b)
SELECT matches(tap._rrs245(17, 're_lm245_17', 'pending', 11000, 'unfulfillable', 'create_response'), '^OK \{.*"recorded": true', 'C2: enforce-transfer-expiry create_response shape on a live row');
SELECT matches(tap._rrs245(17, 're_lm245_17', 'succeeded', 11000, 'unfulfillable', 'reconcile'), '^OK \{.*"recorded": true', 'C3: enforce-transfer-expiry reconcile shape on a live row');
-- stripe-webhook/index.ts:692 (charge.dispute.closed, lost): refund id NULL, dispute id, amount, 'dispute_lost'
SELECT matches(tap._rpr245(18, NULL, 'dp_lm245_18', 11000, 'dispute_lost'), '^OK \{.*"status": "refunded"', 'C4: stripe-webhook dispute-lost shape on a live row (full chargeback -> refunded)');

SELECT * FROM finish();
ROLLBACK;

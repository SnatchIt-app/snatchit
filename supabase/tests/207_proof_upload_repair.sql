-- 207_proof_upload_repair.sql — pgTAP for migration 140 (F-IMG-1 outcomes 1 and 2).
--
-- Negative control: on the stack WITHOUT 140 the shape section fails at A4 (the verbs
-- return void, not jsonb) and every retry assertion errors instead of answering.
-- The assertions carrying the fix are R2-R6: a retry on an already-sent transfer
-- RETURNS instead of raising, writes nothing (xmin unchanged), fires no second
-- notification, and never replaces accepted proof.
-- Mutants that kill them: remove the `v_status = 'seller_sent'` arm (every retry
-- raises again — the pre-140 defect); or write p over the stored path (R5/R6 see
-- the replacement). Removing the bypass-free UPDATE in attach kills S1/S11.
BEGIN;
SELECT plan(37);
SELECT tap.seed_core();

CREATE FUNCTION tap._try207(stmt text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE stmt; RETURN 'ok'; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE || ' ' || SQLERRM; END $$;
CREATE FUNCTION tap._j207(stmt text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb; BEGIN EXECUTE stmt INTO r; RETURN r; EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('raised', SQLERRM); END $$;
CREATE FUNCTION tap._pay207(p_id uuid, p_listing uuid, p_pi text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  PERFORM set_config('app.bypass_payment_guard','on',true);
  INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total,
                               stripe_payment_intent_id, status, mode, stripe_livemode)
  VALUES (p_id, p_listing, tap.buyer(), tap.seller(), 1000, 100, 100, 1200, p_pi, 'pending', 'buy_now', false);
  PERFORM set_config('app.bypass_payment_guard','',true);
END $$;
CREATE FUNCTION tap._mk207(p_id uuid, p_status text, p_path text, p_listing uuid, p_pay uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  PERFORM set_config('app.bypass_transfer_guard','on',true);
  INSERT INTO public.transfers (id, payment_id, listing_id, buyer_id, seller_id, status, transfer_method,
                                transfer_evidence_path, expires_at, created_at)
  VALUES (p_id, p_pay, p_listing, tap.buyer(), tap.seller(), p_status, 'mobile_transfer', p_path,
          pg_catalog.now() + interval '72 hours', pg_catalog.now());
  PERFORM set_config('app.bypass_transfer_guard','',true);
END $$;
-- transfers_listing_id_key allows one transfer per listing and seed_core already
-- used two of the four; free them inside this transaction (BEGIN…ROLLBACK).
CREATE FUNCTION tap._free207() RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  PERFORM set_config('app.bypass_transfer_guard','on',true);
  DELETE FROM public.transfers WHERE id IN (tap.transfer_a(), tap.transfer_b());
  PERFORM set_config('app.bypass_transfer_guard','',true);
END $$;
CREATE FUNCTION tap._obj207(p_name text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('proof-docs', p_name, tap.seller()) ON CONFLICT DO NOTHING; END $$;
CREATE FUNCTION tap._x207(p_id uuid) RETURNS text LANGUAGE sql SECURITY DEFINER AS $$ SELECT t.xmin::text FROM public.transfers t WHERE t.id = p_id $$;
CREATE FUNCTION tap._p207(p_id uuid) RETURNS text LANGUAGE sql SECURITY DEFINER AS $$ SELECT coalesce(t.transfer_evidence_path,'<null>') FROM public.transfers t WHERE t.id = p_id $$;
CREATE FUNCTION tap._n207() RETURNS int LANGUAGE sql SECURITY DEFINER AS $$ SELECT (SELECT count(*)::int FROM public.notifications) + (SELECT count(*)::int FROM notify.notification) $$;
CREATE FUNCTION tap._ev207(p_name text) RETURNS text LANGUAGE sql SECURITY DEFINER AS $$
  SELECT (tap.seller()::text)||'/transfer-evidence/'||p_name $$;

-- ── A. shape and grants ─────────────────────────────────────────────────────
SELECT has_function('public','mark_transfer_sent', ARRAY['uuid','uuid','text'], 'A1: the 3-argument overload exists');
SELECT has_function('public','mark_transfer_sent', ARRAY['uuid','uuid'],        'A2: the 2-argument overload (the shipped build 13 payload) still exists');
SELECT has_function('public','attach_transfer_evidence', ARRAY['uuid','text'],  'A3: attach_transfer_evidence exists');
SELECT is((SELECT pg_catalog.pg_get_function_result(p.oid) FROM pg_proc p WHERE p.oid='public.mark_transfer_sent(uuid,uuid,text)'::regprocedure), 'jsonb',
  'A4: mark_transfer_sent(3) ANSWERS jsonb — it no longer raises at the caller to say "already done"');
SELECT is((SELECT pg_catalog.pg_get_function_result(p.oid) FROM pg_proc p WHERE p.oid='public.mark_transfer_sent(uuid,uuid)'::regprocedure), 'jsonb', 'A5: the 2-arg overload answers jsonb too');
SELECT is((SELECT pg_catalog.pg_get_function_result(p.oid) FROM pg_proc p WHERE p.oid='public.attach_transfer_evidence(uuid,text)'::regprocedure), 'jsonb', 'A6: attach answers jsonb');
SELECT ok((SELECT p.prosecdef FROM pg_proc p WHERE p.oid='public.attach_transfer_evidence(uuid,text)'::regprocedure), 'A7: attach is SECURITY DEFINER');
SELECT ok((SELECT p.proconfig::text LIKE '%search_path=%' FROM pg_proc p WHERE p.oid='public.attach_transfer_evidence(uuid,text)'::regprocedure), 'A8: attach pins search_path');
SELECT ok(has_function_privilege('authenticated','public.mark_transfer_sent(uuid,uuid,text)','EXECUTE')
      AND has_function_privilege('service_role','public.mark_transfer_sent(uuid,uuid,text)','EXECUTE'), 'A9: mark-sent grants unchanged (authenticated + service_role)');
SELECT ok(NOT has_function_privilege('anon','public.mark_transfer_sent(uuid,uuid,text)','EXECUTE')
      AND NOT has_function_privilege('anon','public.mark_transfer_sent(uuid,uuid)','EXECUTE'), 'A10: anon revoked on both overloads');
SELECT ok(has_function_privilege('authenticated','public.attach_transfer_evidence(uuid,text)','EXECUTE'), 'A11: attach executable by authenticated');
SELECT ok(NOT has_function_privilege('anon','public.attach_transfer_evidence(uuid,text)','EXECUTE')
      AND NOT has_function_privilege('service_role','public.attach_transfer_evidence(uuid,text)','EXECUTE'),
  'A12: attach denied to anon AND service_role — v1 has no operator backfill route');

-- ── R. outcome 1: the retry ─────────────────────────────────────────────────
SELECT tap._free207();
SELECT tap._pay207('c0000000-0000-4000-8000-0000000000a1', tap.listing_c(), 'pi_207_a1');
SELECT tap._mk207('c0000000-0000-4000-8000-000000000001','pending', NULL, tap.listing_c(), 'c0000000-0000-4000-8000-0000000000a1');
SELECT tap._obj207(tap._ev207('first.jpg'));
SELECT tap._obj207(tap._ev207('second.jpg'));
SELECT tap.login(tap.seller());
CREATE TEMP TABLE n207 AS SELECT tap._n207() AS before_transition;
SELECT is(tap._j207($$SELECT public.mark_transfer_sent('c0000000-0000-4000-8000-000000000001', auth.uid(), $$||quote_literal(tap._ev207('first.jpg'))||$$)$$)->>'outcome',
  'transitioned', 'R1: the first call transitions a pending transfer');
CREATE TEMP TABLE n207b AS SELECT tap._n207() AS after_transition, tap._x207('c0000000-0000-4000-8000-000000000001') AS x_after;
SELECT ok((SELECT after_transition FROM n207b) > (SELECT before_transition FROM n207),
  'R2: the transition notifies — at least one row appears');
-- THE FIX: the lost-response retry, same path
SELECT is(tap._j207($$SELECT public.mark_transfer_sent('c0000000-0000-4000-8000-000000000001', auth.uid(), $$||quote_literal(tap._ev207('first.jpg'))||$$)$$)->>'outcome',
  'already_sent', 'R3: the SAME-PATH retry answers already_sent instead of raising — the defect this migration exists to fix');
SELECT is(tap._x207('c0000000-0000-4000-8000-000000000001'), (SELECT x_after FROM n207b),
  'R4: the row was NOT written on the retry (xmin unchanged)');
SELECT is(tap._n207(), (SELECT after_transition FROM n207b),
  'R5: and no second notification fired — the buyer is not told twice');
-- a DIFFERENT path on the retry must never replace accepted proof
SELECT is(tap._j207($$SELECT public.mark_transfer_sent('c0000000-0000-4000-8000-000000000001', auth.uid(), $$||quote_literal(tap._ev207('second.jpg'))||$$)$$)->>'outcome',
  'already_sent', 'R6: a DIFFERENT-path retry also answers already_sent');
SELECT is(tap._p207('c0000000-0000-4000-8000-000000000001'), tap._ev207('first.jpg'),
  'R7: accepted proof is NOT replaced by the retry — the second upload stays an orphan');
SELECT is(tap._j207($$SELECT public.mark_transfer_sent('c0000000-0000-4000-8000-000000000001', auth.uid(), $$||quote_literal(tap._ev207('second.jpg'))||$$)$$)->>'evidence_replaced',
  'false', 'R8: and it says so — evidence_replaced is false');
SELECT is(tap._j207($$SELECT public.mark_transfer_sent('c0000000-0000-4000-8000-000000000001', auth.uid())$$)->>'outcome',
  'already_sent', 'R9: the 2-argument overload (no path) retries cleanly too');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT matches(tap._try207($$SELECT public.mark_transfer_sent('c0000000-0000-4000-8000-000000000001', auth.uid(), NULL)$$),
  'Only the seller', 'R10: a non-seller still cannot mark sent — authorization is unchanged');
SELECT tap.logout();

-- conflicting retries on terminal states still raise
SELECT tap._pay207('c0000000-0000-4000-8000-0000000000a2', tap.listing_d(), 'pi_207_a2');
SELECT tap._mk207('c0000000-0000-4000-8000-000000000002','disputed', NULL, tap.listing_d(), 'c0000000-0000-4000-8000-0000000000a2');
SELECT tap._pay207('c0000000-0000-4000-8000-0000000000a3', tap.listing_b(), 'pi_207_a3');
SELECT tap._mk207('c0000000-0000-4000-8000-000000000003','reversed', NULL, tap.listing_b(), 'c0000000-0000-4000-8000-0000000000a3');
SELECT tap.login(tap.seller());
SELECT matches(tap._try207($$SELECT public.mark_transfer_sent('c0000000-0000-4000-8000-000000000002', auth.uid(), NULL)$$),
  'current status: disputed', 'R11: a retry on a DISPUTED transfer is still rejected');
SELECT matches(tap._try207($$SELECT public.mark_transfer_sent('c0000000-0000-4000-8000-000000000003', auth.uid(), NULL)$$),
  'current status: reversed', 'R12: a retry on a REVERSED transfer is still rejected');

-- ── S. outcome 2: the explicit recovery ─────────────────────────────────────
SELECT tap._pay207('c0000000-0000-4000-8000-0000000000a4', tap.listing_a(), 'pi_207_a4');
SELECT tap._mk207('c0000000-0000-4000-8000-000000000004','seller_sent', NULL, tap.listing_a(), 'c0000000-0000-4000-8000-0000000000a4');
SELECT tap._obj207(tap._ev207('recovered.jpg'));
SELECT tap._obj207(tap._ev207('other.jpg'));
SELECT matches(tap._try207($$SELECT public.mark_transfer_sent('c0000000-0000-4000-8000-000000000004', auth.uid(), $$||quote_literal(tap._ev207('recovered.jpg'))||$$)$$),
  'use attach_transfer_evidence', 'S1: mark-sent REFUSES to backfill a sent-without-proof transfer and names the explicit route');
SELECT is(tap._j207($$SELECT public.attach_transfer_evidence('c0000000-0000-4000-8000-000000000004', $$||quote_literal(tap._ev207('recovered.jpg'))||$$)$$)->>'outcome',
  'attached', 'S2: the seller attaches the proof that was stranded');
SELECT is(tap._p207('c0000000-0000-4000-8000-000000000004'), tap._ev207('recovered.jpg'),
  'S3: the path is recorded — written with the guard ARMED, since null -> value passes it');
SELECT is(tap._j207($$SELECT public.attach_transfer_evidence('c0000000-0000-4000-8000-000000000004', $$||quote_literal(tap._ev207('recovered.jpg'))||$$)$$)->>'outcome',
  'already_attached', 'S4: attaching the same path again answers already_attached and writes nothing');
SELECT matches(tap._try207($$SELECT public.attach_transfer_evidence('c0000000-0000-4000-8000-000000000004', $$||quote_literal(tap._ev207('other.jpg'))||$$)$$),
  'append-only', 'S5: attaching a DIFFERENT path is refused by the append-only guard itself, not by a check this migration could weaken');
SELECT ok(EXISTS (SELECT 1 FROM public.transfers t
                   WHERE t.transfer_evidence_path = tap._ev207('recovered.jpg')
                     AND (t.buyer_id = tap.buyer() OR t.seller_id = tap.buyer())),
  'S6: the buyer''s transfer-party-read predicate now matches the object — which is the whole point of attaching');
-- transfer …001 got its path through mark_transfer_sent, …004 through attach;
-- both must be equally protected, so this is not a duplicate of S5.
SELECT matches(tap._try207($$SELECT public.attach_transfer_evidence('c0000000-0000-4000-8000-000000000001', $$||quote_literal(tap._ev207('second.jpg'))||$$)$$),
  'append-only', 'S7: attach cannot overwrite proof that arrived via mark_transfer_sent either');
SELECT matches(tap._try207($$SELECT public.attach_transfer_evidence('c0000000-0000-4000-8000-000000000002', $$||quote_literal(tap._ev207('recovered.jpg'))||$$)$$),
  'status: disputed', 'S8: attach is refused on a disputed transfer (v1 eligibility)');
SELECT matches(tap._try207($$SELECT public.attach_transfer_evidence('c0000000-0000-4000-8000-000000000004', 'someone-else/transfer-evidence/x.jpg')$$),
  'own folder', 'S9: a path outside the caller''s own folder is refused');
SELECT matches(tap._try207($$SELECT public.attach_transfer_evidence('c0000000-0000-4000-8000-000000000004', $$||quote_literal((tap.seller()::text)||'/covers/x.jpg')||$$)$$),
  'transfer-evidence', 'S10: a path outside transfer-evidence/ is refused');
SELECT matches(tap._try207($$SELECT public.attach_transfer_evidence('c0000000-0000-4000-8000-000000000004', $$||quote_literal(tap._ev207('does-not-exist.jpg'))||$$)$$),
  'no such object', 'S11: a DANGLING path is refused — proof that cannot be fetched is never recorded');
SELECT matches(tap._try207($$SELECT public.attach_transfer_evidence('c0000000-0000-4000-8000-000000000004', '')$$),
  'required', 'S12: an empty path is refused');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT tap._pay207('c0000000-0000-4000-8000-0000000000a5', tap.listing_c(), 'pi_207_a5');
SELECT matches(tap._try207($$SELECT public.attach_transfer_evidence('c0000000-0000-4000-8000-000000000004', $$||quote_literal(tap._ev207('other.jpg'))||$$)$$),
  'only the seller', 'S13: the BUYER cannot attach evidence to the seller''s transfer');
SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;

-- 241_transfer_refusal_hints.sql — pgTAP for migration 20261021131000_transfer_refusal_hints_and_evidence_path.sql
-- (registry 171). Source: sprint-control/SERVER_REFUSAL_CATALOGUE_C_20261021.md §4, §5, §7 (SNT-*, PRF-*, CNF-*)
-- and finding 8.
--
-- WHAT IS PINNED
--   H. Stable HINTs on five transfer refusals, with every MESSAGE byte-identical to production (the app, the web
--      and the confirm-and-release edge match these texts today) and every SQLSTATE unchanged (P0001):
--        SNT-1 'precondition_failed: transfer already sent without evidence — use attach_transfer_evidence'
--              -> HINT TRANSFER_SENT_WITHOUT_PROOF
--        SNT-2 'Transfer cannot be marked as sent from current status: %.' -> HINT TRANSFER_NOT_PENDING, DETAIL status
--              (both mark_transfer_sent overloads; the 2-arg one delegates to the 3-arg one)
--        PRF-1 'transfer_evidence_path is append-only.' (trigger guard_transfer_state_columns) -> HINT PROOF_ALREADY_ATTACHED
--        PRF-2 'precondition_failed: evidence can only be attached to a sent transfer (status: %)'
--              -> HINT TRANSFER_NOT_SENT, DETAIL status
--        CNF-1 'Transfer cannot be confirmed from current status: %.' (confirm_transfer_received, the function the
--              confirm-and-release edge calls, index.ts:197) -> HINT TRANSFER_NOT_CONFIRMABLE, DETAIL status
--   V. mark_transfer_sent(uuid,uuid,text) validates a NON-NULL evidence path with EXACTLY attach_transfer_evidence's
--      rules before storing it (own folder, under transfer-evidence/, an object in proof-docs; '' is attach's
--      'evidence path is required'), same messages, HINT PROOF_PATH_INVALID (attach had no hint, so attach's four
--      path refusals gain it too). Before 171 a seller could record ANOTHER seller's proof (then readable by the
--      seller and their buyer through "proof-docs transfer party read"), a dangling path, or a non-evidence object,
--      clearing the payout engine's EVIDENCE_MISSING signal (supabase/functions/_shared/payout-policy.ts:70) without
--      uploading anything. Reproduced first: private-evidence/A-sprint-20261021/a2/p2/01_repro.out.
--      The rules are attach's EXACTLY: the owner is the RESOLVED caller (auth.uid(); p_user_id only on the service path),
--      never the client-supplied p_user_id (V19-V21); existence is by EXACT object name, so a truncated path that only
--      prefixes a real object is dangling (V22-V23); the prefix rule keeps its leading slash, so an own object under
--      '<uid>/old-transfer-evidence/' is refused (V24-V25), as attach refuses both (A8, A9).
--      UNCHANGED: a NULL path (the sent-without-evidence flow, and the 2-arg overload); the retry on an already-sent
--      transfer (answers already_sent and writes nothing, whatever path it carries); refusal ORDER (caller, lookup,
--      seller, already-sent arm, status, then the path — attach's order: status before path).
--   C. Every caller with valid input still works: the app's call (send/[id].tsx:225, authenticated seller, three keys,
--      '<uid>/transfer-evidence/<stamp>.<ext>' uploaded to proof-docs first), the web's call (web/src/lib/transfers.ts:251,
--      same shape), the 2-arg/NULL callers (scripts/sandbox/20_matrix.sh:115, pgTAP 040/050/110/122/131), the
--      service-role path, attach (send/[id].tsx:290) and the edge's confirm_transfer_received call under service role,
--      including the 'buyer_confirmed' substring the edge's already-confirmed branch reads (index.ts:207-208).
--   S. Shape: grants, SECURITY DEFINER and search_path unchanged on all five routines; the other refusals in the
--      redefined bodies keep their exact text, code and (absent) hint.
--
-- HARNESS. seed_core fixtures plus private transfers built here (one listing + payment per transfer:
-- transfers_listing_id_key / transfers_payment_id_key). The production replay restores 8 app schemas, not storage,
-- so storage.buckets is empty there (a157 03_regress.out:4); a missing bucket is created (proof-docs private,
-- auction-media public, as in the chain). On the chain and in CI both exist and the INSERT never executes (it sits
-- behind IF NOT EXISTS, so no storage.buckets write privilege is needed there). Objects are inserted like 207's
-- tap._obj207. Runs as postgres (PGUSER=postgres), like 207.
-- Everything dies with the ROLLBACK.
--
-- NEGATIVE CONTROL (measured; private-evidence/A-sprint-20261021/a2/p2/fix_p2f/). Without 171, on the production replay
-- AND on the chain: 50/96, the 46 failures being exactly the hint and path assertions (H2 H3 H5-H10 H12 H14 H15 H17 H18
-- H22-H28 V1-V11 V13 V19-V25 A1-A5 A8 A9). With 171: 96/96 on both. Every message (H1 H4 H13 H16 H21 ...), every valid
-- caller (C1-C17), the two fixture checks V17/V18, U1-U9 and S1-S7 pass WITH AND WITHOUT 171. Without 171, A8/A9 fail
-- on the missing hint only: production attach already refuses both paths with the same text.
-- MUTANTS, one deliberate defect each on a fresh replay clone; all 31 killed (m01-m22 implementer, n01-n09 reviewer p2rv;
-- n01-n04 SURVIVED the 85-assertion version of this suite, fix_p2f/runs/01_repro_head241_*.out, hence V17-V25, A8, A9):
--   MUTANT                                       ASSERTIONS THAT DIE
--   m01_snt1_no_hint                            H2 H3
--   m02_snt2_no_detail                          H5 H6 H7 H8 H9 H10 H12
--   m03_snt2_errcode                            H4 H6 H7 H8 H9 H10
--   m04_snt1_msg_hyphen                         H1 H3
--   m05_prf1_no_hint                            H17 H18
--   m06_prf1_hint_on_dispute                    H19
--   m07_prf2_no_detail                          H14 H15
--   m08_cnf1_no_hint                            H22 H23 H24 H25 H26 H27 H28
--   m09_cnf1_wrong_detail                       H22 H23 H24 H25 H26 H27 H28
--   m10_mark_no_owner                           V1 V2 V3 V4 V5 V6 V7 V8 V9 V10 V11 V13 V19 V20 V21
--   m11_mark_no_prefix                          V3 V4 V5 V6 V7 V8 V9 V10 V24 V25
--   m12_mark_no_object                          V4 V5 V6 V7 V8 V9 V10 V22 V23
--   m13_mark_any_bucket                         V5 V6 V7 V8 V9 V10
--   m14_mark_empty_as_null                      V6 V7 V8 V9 V10
--   m15_mark_owner_contains                     V8
--   m16_mark_owner_auth_uid                     V13 V21
--   m17_mark_validate_before_sent_arm           H3 H7 V14
--   m18_mark_validate_before_status             H7
--   m19_mark_owner_no_hint                      V2 V13 V19
--   m20_attach_prefix_no_hint                   A2 A9
--   m21_attach_required_no_hint                 A4 A5
--   m22_mark_skip_service_role                  V13 V21
--   n01_mark_owner_vs_p_user_id                 V19 V20 V21
--   n02_mark_validate_only_if_p_user_is_caller  V19 V20 V21
--   n03_mark_prefix_no_leading_slash            V24 V25
--   n04_mark_object_prefix_match                V22 V23
--   n05_cnf_hint_on_not_buyer                   U5
--   n06_attach_owner_no_hint                    A1
--   n07_guard_append_only_from_null             C11 C12 C13 A7
--   n08_mark_null_treated_as_empty              C6 C7 C8 C9
--   n09_cnf1_detail_caller                      H22 H23 H24 H25 H26 H27 H28
-- V3-V10 share transfer 1 on purpose (V9: refused calls write nothing), so a mutant that lets one bad path through
-- also fails the probes after it; the FIRST failing V names the branch. V19-V25 use one transfer per probe (21-23), so
-- each of n01-n04 dies at its own probe. V21 runs after V13, so it also sees a service-path breach (m16/m22).
-- m17/m18 (validation moved earlier) are the order mutants; m22/m16 are the service-role mutants.
BEGIN;
SELECT plan(96);
SELECT tap.seed_core();

DO $b241$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'proof-docs') THEN
    INSERT INTO storage.buckets (id, name, public) VALUES ('proof-docs', 'proof-docs', false);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'auction-media') THEN
    INSERT INTO storage.buckets (id, name, public) VALUES ('auction-media', 'auction-media', true);
  END IF;
END
$b241$;

-- ── helpers ─────────────────────────────────────────────────────────────────
-- run a statement as the CURRENT role; report the refusal's four client-visible fields, or the jsonb answer
CREATE FUNCTION tap._e241(stmt text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r text; c text; m text; h text; d text;
BEGIN
  EXECUTE stmt INTO r;
  RETURN jsonb_build_object('ok', true, 'answer', r);
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS c = RETURNED_SQLSTATE, m = MESSAGE_TEXT, h = PG_EXCEPTION_HINT, d = PG_EXCEPTION_DETAIL;
  RETURN jsonb_build_object('ok', false, 'code', c, 'message', m, 'hint', nullif(h, ''), 'detail', nullif(d, ''));
END $$;
-- 'code | message' and 'hint | detail' (absent = <none>; a call that did NOT raise reads <no refusal>)
CREATE FUNCTION tap._cm241(r jsonb) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN (r->>'ok')::boolean THEN '<no refusal>' ELSE (r->>'code') || ' | ' || (r->>'message') END $$;
CREATE FUNCTION tap._hd241(r jsonb) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN (r->>'ok')::boolean THEN '<no refusal>'
              ELSE coalesce(r->>'hint', '<none>') || ' | ' || coalesce(r->>'detail', '<none>') END $$;
CREATE FUNCTION tap._out241(r jsonb) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN (r->>'ok')::boolean THEN ((r->>'answer')::jsonb)->>'outcome' ELSE 'raised ' || (r->>'message') END $$;

CREATE FUNCTION tap._t241(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('f2410000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
CREATE FUNCTION tap._ev241(p_uid uuid, p_file text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT p_uid::text || '/transfer-evidence/' || p_file $$;
-- one listing + payment + transfer per fixture, written as postgres (seed_core's own shapes)
CREATE FUNCTION tap._mk241(n int, p_seller uuid, p_status text, p_path text) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_l uuid := ('f2410000-0000-4000-8001-' || lpad(n::text, 12, '0'))::uuid;
        v_p uuid := ('f2410000-0000-4000-8002-' || lpad(n::text, 12, '0'))::uuid;
BEGIN
  INSERT INTO public.listings
    (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
     starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
  VALUES (v_l, p_seller, 'Fixture 241 ' || n, 'Club 241', 'wynwood', current_date + 30, '21:00', 'GA', 2, 'mobile_transfer',
          100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/241.jpg', 'active');
  INSERT INTO public.payments
    (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at)
  VALUES (v_p, v_l, tap.buyer(), p_seller, 10000, 1000, 1000, 11000, 'pi_241_' || n, 'succeeded', 'buy_now', now());
  INSERT INTO public.transfers
    (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status, seller_sent_at, auto_release_at,
     transfer_evidence_path, expires_at)
  VALUES (tap._t241(n), v_l, v_p, p_seller, tap.buyer(), 'mobile_transfer', p_status,
          CASE WHEN p_status = 'pending' THEN NULL ELSE now() END,
          CASE WHEN p_status = 'pending' THEN NULL ELSE now() + interval '72 hours' END,
          p_path, now() + interval '24 hours');
  RETURN tap._t241(n);
END $$;
CREATE FUNCTION tap._obj241(p_bucket text, p_name text, p_owner uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN INSERT INTO storage.objects (bucket_id, name, owner) VALUES (p_bucket, p_name, p_owner); END $$;
-- status | path | xmin, read past RLS
CREATE FUNCTION tap._row241(p_id uuid) RETURNS text LANGUAGE sql SECURITY DEFINER AS $$
  SELECT t.status || ' | ' || coalesce(t.transfer_evidence_path, '<null>') || ' | ' || t.xmin::text
    FROM public.transfers t WHERE t.id = p_id $$;
CREATE FUNCTION tap._st241(p_id uuid) RETURNS text LANGUAGE sql SECURITY DEFINER AS $$
  SELECT t.status || ' | ' || coalesce(t.transfer_evidence_path, '<null>') FROM public.transfers t WHERE t.id = p_id $$;
CREATE FUNCTION tap._n241() RETURNS int LANGUAGE sql SECURITY DEFINER AS $$
  SELECT (SELECT count(*)::int FROM public.notifications) + (SELECT count(*)::int FROM notify.notification) $$;

-- ── fixtures (as postgres) ──────────────────────────────────────────────────
-- O (tap.other_user) is another seller with their own sent transfer and a real proof object.
SELECT tap._mk241(20, tap.other_user(), 'seller_sent', tap._ev241(tap.other_user(), '1729000000020.jpg'));
SELECT tap._obj241('proof-docs', tap._ev241(tap.other_user(), '1729000000020.jpg'), tap.other_user());
-- S's own objects: valid proofs, a non-evidence object, an evidence-shaped object in the wrong bucket
SELECT tap._obj241('proof-docs', tap._ev241(tap.seller(), '1729000000001.jpg'), tap.seller());
SELECT tap._obj241('proof-docs', tap._ev241(tap.seller(), '1729000000004.jpg'), tap.seller());
SELECT tap._obj241('proof-docs', tap._ev241(tap.seller(), '1729000000005.jpg'), tap.seller());
SELECT tap._obj241('proof-docs', tap._ev241(tap.seller(), '1729000000011.jpg'), tap.seller());
SELECT tap._obj241('proof-docs', tap._ev241(tap.seller(), '1729000000012.jpg'), tap.seller());
SELECT tap._obj241('proof-docs', tap._ev241(tap.seller(), '1729000000014.png'), tap.seller());
SELECT tap._obj241('proof-docs', tap._ev241(tap.seller(), '1729000000015.jpg'), tap.seller());
SELECT tap._obj241('proof-docs', tap.seller()::text || '/proofs/1729000000099.jpg', tap.seller());
SELECT tap._obj241('auction-media', tap._ev241(tap.seller(), '1729000000098.jpg'), tap.seller());
-- an own object in a folder that merely ENDS in 'transfer-evidence' (reachable: the 'proof-docs owner insert' policy
-- checks only bucket_id and foldername[1] = auth.uid(); an authenticated seller uploads it through RLS on the replay and
-- the chain, a2/p2/fix_p2f/runs/06_reachability_*.out)
SELECT tap._obj241('proof-docs', tap.seller()::text || '/old-transfer-evidence/1729000000002.jpg', tap.seller());
SELECT tap._mk241(1,  tap.seller(), 'pending',         NULL);   -- refused paths, then the app's valid call
SELECT tap._mk241(2,  tap.seller(), 'pending',         NULL);   -- 3-arg, NULL path
SELECT tap._mk241(3,  tap.seller(), 'pending',         NULL);   -- 2-arg
SELECT tap._mk241(4,  tap.seller(), 'pending',         NULL);   -- service-role caller
SELECT tap._mk241(5,  tap.seller(), 'seller_sent',     NULL);   -- sent without proof: SNT-1, then attach
SELECT tap._mk241(6,  tap.seller(), 'disputed',        NULL);
SELECT tap._mk241(7,  tap.seller(), 'expired',         NULL);
SELECT tap._mk241(8,  tap.seller(), 'reversed',        NULL);
SELECT tap._mk241(9,  tap.seller(), 'buyer_confirmed', NULL);
SELECT tap._mk241(10, tap.seller(), 'auto_released',   NULL);
SELECT tap._mk241(11, tap.seller(), 'seller_sent',     tap._ev241(tap.seller(), '1729000000011.jpg'));  -- sent WITH proof
SELECT tap._mk241(12, tap.seller(), 'pending',         NULL);   -- PRF-2 / CNF-1 on pending
SELECT tap._mk241(13, tap.seller(), 'seller_sent',     tap._ev241(tap.seller(), '1729000000012.jpg'));  -- edge confirm
SELECT tap._mk241(14, tap.seller(), 'seller_sent',     NULL);   -- attach path refusals, then a valid attach
SELECT tap._mk241(15, tap.seller(), 'pending',         NULL);   -- the web's call
SELECT tap._mk241(16, tap.seller(), 'pending',         NULL);   -- the app's call (a transfer no refused probe touched)
SELECT tap._mk241(17, tap.seller(), 'pending',         NULL);   -- the service-role caller's valid call
SELECT tap._mk241(21, tap.seller(), 'pending',         NULL);   -- p_user_id names another seller (V19-V21)
SELECT tap._mk241(22, tap.seller(), 'pending',         NULL);   -- truncated own path (V22-V23)
SELECT tap._mk241(23, tap.seller(), 'pending',         NULL);   -- own object under old-transfer-evidence/ (V24-V25)

-- O's transfer also carries a dispute proof, so the guard's OTHER append-only branch is reachable (H19)
SELECT set_config('app.bypass_transfer_guard', 'on', true);
UPDATE public.transfers SET dispute_evidence_path = 'fixtures/dispute-241.jpg' WHERE id = tap._t241(20);
SELECT tap.reset_guards();
-- result tables, created as postgres before any persona switch
CREATE TEMP TABLE r241 (k text PRIMARY KEY, r jsonb);
GRANT ALL ON r241 TO PUBLIC;
CREATE TEMP TABLE v241 (row_before text, n_before int);
GRANT ALL ON v241 TO PUBLIC;
CREATE TEMP TABLE v241b (row_before text);
GRANT ALL ON v241b TO PUBLIC;
CREATE TEMP TABLE v241c (k text PRIMARY KEY, row_before text);
GRANT ALL ON v241c TO PUBLIC;

-- ═════ H. hints, with messages and codes unchanged ═════════════════════════
SELECT tap.login(tap.seller());
INSERT INTO r241 VALUES
  ('snt1',      tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid(), %L)::text', tap._t241(5), tap._ev241(tap.seller(), '1729000000005.jpg')))),
  ('snt1_bad',  tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid(), %L)::text', tap._t241(5), tap._ev241(tap.other_user(), '1729000000020.jpg')))),
  ('snt2_dis',  tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid(), %L)::text', tap._t241(6), tap._ev241(tap.seller(), '1729000000004.jpg')))),
  ('snt2_dis2', tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid())::text', tap._t241(6)))),
  ('snt2_disb', tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid(), %L)::text', tap._t241(6), tap._ev241(tap.other_user(), '1729000000020.jpg')))),
  ('snt2_exp',  tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid(), NULL)::text', tap._t241(7)))),
  ('snt2_rev',  tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid())::text', tap._t241(8)))),
  ('snt2_bc',   tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid(), %L)::text', tap._t241(9), tap._ev241(tap.seller(), '1729000000004.jpg')))),
  ('snt2_ar',   tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid())::text', tap._t241(10)))),
  ('prf2_pen',  tap._e241(format('SELECT public.attach_transfer_evidence(%L, %L)::text', tap._t241(12), tap._ev241(tap.seller(), '1729000000004.jpg')))),
  ('prf2_dis',  tap._e241(format('SELECT public.attach_transfer_evidence(%L, %L)::text', tap._t241(6), tap._ev241(tap.seller(), '1729000000004.jpg')))),
  ('prf1_att',  tap._e241(format('SELECT public.attach_transfer_evidence(%L, %L)::text', tap._t241(11), tap._ev241(tap.seller(), '1729000000004.jpg'))));
SELECT tap.logout();
-- PRF-1 through a direct write (050's path; the guard is the only writer of this text)
SELECT tap.reset_guards();
INSERT INTO r241 VALUES
  ('prf1_upd',  tap._e241(format('UPDATE public.transfers SET transfer_evidence_path = NULL WHERE id = %L RETURNING id::text', tap._t241(11)))),
  ('dsp_upd',   tap._e241(format($q$UPDATE public.transfers SET dispute_evidence_path = 'x' WHERE id = %L RETURNING id::text$q$, tap._t241(20)))),
  ('state_upd', tap._e241(format($q$UPDATE public.transfers SET status = 'buyer_confirmed' WHERE id = %L RETURNING id::text$q$, tap._t241(11))));
SELECT tap.login(tap.buyer());
INSERT INTO r241 VALUES
  ('cnf1_pen',  tap._e241(format('SELECT public.confirm_transfer_received(%L, auth.uid())::text', tap._t241(12)))),
  ('cnf1_dis',  tap._e241(format('SELECT public.confirm_transfer_received(%L, auth.uid())::text', tap._t241(6)))),
  ('cnf1_exp',  tap._e241(format('SELECT public.confirm_transfer_received(%L, auth.uid())::text', tap._t241(7)))),
  ('cnf1_rev',  tap._e241(format('SELECT public.confirm_transfer_received(%L, auth.uid())::text', tap._t241(8))));
SELECT tap.logout();
-- the edge's own call shape: service role, p_user_id = the buyer (confirm-and-release/index.ts:197-200)
SELECT tap.login_service();
INSERT INTO r241 VALUES
  ('cnf1_svc',  tap._e241(format('SELECT public.confirm_transfer_received(%L, %L)::text', tap._t241(12), tap.buyer()))),
  ('cnf1_bc',   tap._e241(format('SELECT public.confirm_transfer_received(%L, %L)::text', tap._t241(9), tap.buyer()))),
  ('cnf1_ar',   tap._e241(format('SELECT public.confirm_transfer_received(%L, %L)::text', tap._t241(10), tap.buyer())));
SELECT tap.logout();

SELECT is(tap._cm241(r), 'P0001 | precondition_failed: transfer already sent without evidence ' || U&'\2014' || ' use attach_transfer_evidence',
  'H1: SNT-1 message (em dash U+2014 included) and code are byte-identical') FROM r241 WHERE k = 'snt1';
SELECT is(tap._hd241(r), 'TRANSFER_SENT_WITHOUT_PROOF | <none>', 'H2: SNT-1 carries HINT TRANSFER_SENT_WITHOUT_PROOF') FROM r241 WHERE k = 'snt1';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r),
  'P0001 | precondition_failed: transfer already sent without evidence ' || U&'\2014' || ' use attach_transfer_evidence || TRANSFER_SENT_WITHOUT_PROOF | <none>',
  'H3: SNT-1 still wins over an invalid path (the already-sent arm runs before the path check)') FROM r241 WHERE k = 'snt1_bad';
SELECT is(tap._cm241(r), 'P0001 | Transfer cannot be marked as sent from current status: disputed.', 'H4: SNT-2 message and code unchanged (disputed)') FROM r241 WHERE k = 'snt2_dis';
SELECT is(tap._hd241(r), 'TRANSFER_NOT_PENDING | disputed', 'H5: SNT-2 carries HINT TRANSFER_NOT_PENDING and DETAIL = the status (disputed)') FROM r241 WHERE k = 'snt2_dis';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | Transfer cannot be marked as sent from current status: disputed. || TRANSFER_NOT_PENDING | disputed',
  'H6: the 2-ARG overload surfaces the same message, hint and detail') FROM r241 WHERE k = 'snt2_dis2';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | Transfer cannot be marked as sent from current status: disputed. || TRANSFER_NOT_PENDING | disputed',
  'H7: a non-pending status is refused BEFORE the path is judged (an invalid path on a disputed transfer still reads SNT-2)') FROM r241 WHERE k = 'snt2_disb';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | Transfer cannot be marked as sent from current status: expired. || TRANSFER_NOT_PENDING | expired',
  'H8: SNT-2 expired (3-arg, NULL path)') FROM r241 WHERE k = 'snt2_exp';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | Transfer cannot be marked as sent from current status: reversed. || TRANSFER_NOT_PENDING | reversed',
  'H9: SNT-2 reversed (2-arg)') FROM r241 WHERE k = 'snt2_rev';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | Transfer cannot be marked as sent from current status: buyer_confirmed. || TRANSFER_NOT_PENDING | buyer_confirmed',
  'H10: SNT-2 buyer_confirmed') FROM r241 WHERE k = 'snt2_bc';
SELECT ok((r->>'message') ~* 'cannot be marked as sent from current status:\s*(seller_sent|buyer_confirmed|auto_released)',
  'H11: the app''s isAlreadySentRaise regex (src/lib/transfer/markSent.ts) still matches SNT-2') FROM r241 WHERE k = 'snt2_ar';
SELECT is(tap._hd241(r), 'TRANSFER_NOT_PENDING | auto_released', 'H12: SNT-2 auto_released hint and detail') FROM r241 WHERE k = 'snt2_ar';
SELECT is(tap._cm241(r), 'P0001 | precondition_failed: evidence can only be attached to a sent transfer (status: pending)',
  'H13: PRF-2 message and code unchanged (pending)') FROM r241 WHERE k = 'prf2_pen';
SELECT is(tap._hd241(r), 'TRANSFER_NOT_SENT | pending', 'H14: PRF-2 carries HINT TRANSFER_NOT_SENT and DETAIL = the status') FROM r241 WHERE k = 'prf2_pen';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | precondition_failed: evidence can only be attached to a sent transfer (status: disputed) || TRANSFER_NOT_SENT | disputed',
  'H15: PRF-2 disputed') FROM r241 WHERE k = 'prf2_dis';
SELECT is(tap._cm241(r), 'P0001 | transfer_evidence_path is append-only.', 'H16: PRF-1 via attach: message and code unchanged') FROM r241 WHERE k = 'prf1_att';
SELECT is(tap._hd241(r), 'PROOF_ALREADY_ATTACHED | <none>', 'H17: PRF-1 via attach carries HINT PROOF_ALREADY_ATTACHED (raised by the trigger)') FROM r241 WHERE k = 'prf1_att';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | transfer_evidence_path is append-only. || PROOF_ALREADY_ATTACHED | <none>',
  'H18: PRF-1 via a direct UPDATE (the guard trigger itself): same text, same hint') FROM r241 WHERE k = 'prf1_upd';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | dispute_evidence_path is append-only. || <none> | <none>',
  'H19: the guard''s dispute_evidence_path refusal is untouched (text, code, no hint)') FROM r241 WHERE k = 'dsp_upd';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | Cannot directly modify transfer state columns. Use the appropriate RPC. || <none> | <none>',
  'H20: the guard''s state-column refusal is untouched (text, code, no hint)') FROM r241 WHERE k = 'state_upd';
SELECT is(tap._cm241(r), 'P0001 | Transfer cannot be confirmed from current status: pending.', 'H21: CNF-1 message and code unchanged (pending, buyer session)') FROM r241 WHERE k = 'cnf1_pen';
SELECT is(tap._hd241(r), 'TRANSFER_NOT_CONFIRMABLE | pending', 'H22: CNF-1 carries HINT TRANSFER_NOT_CONFIRMABLE and DETAIL = the status') FROM r241 WHERE k = 'cnf1_pen';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | Transfer cannot be confirmed from current status: disputed. || TRANSFER_NOT_CONFIRMABLE | disputed',
  'H23: CNF-1 disputed') FROM r241 WHERE k = 'cnf1_dis';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | Transfer cannot be confirmed from current status: expired. || TRANSFER_NOT_CONFIRMABLE | expired',
  'H24: CNF-1 expired') FROM r241 WHERE k = 'cnf1_exp';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | Transfer cannot be confirmed from current status: reversed. || TRANSFER_NOT_CONFIRMABLE | reversed',
  'H25: CNF-1 reversed') FROM r241 WHERE k = 'cnf1_rev';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | Transfer cannot be confirmed from current status: pending. || TRANSFER_NOT_CONFIRMABLE | pending',
  'H26: CNF-1 through the edge''s service-role call shape') FROM r241 WHERE k = 'cnf1_svc';
SELECT ok((r->>'message') LIKE '%buyer_confirmed%' AND r->>'hint' = 'TRANSFER_NOT_CONFIRMABLE' AND r->>'detail' = 'buyer_confirmed',
  'H27: an already-confirmed transfer: the message still contains ''buyer_confirmed'' (the edge''s already-confirmed branch, index.ts:207) and the hint/detail are set') FROM r241 WHERE k = 'cnf1_bc';
SELECT ok((r->>'message') LIKE '%auto_released%' AND r->>'hint' = 'TRANSFER_NOT_CONFIRMABLE' AND r->>'detail' = 'auto_released',
  'H28: auto_released: the edge''s substring still matches; hint/detail set') FROM r241 WHERE k = 'cnf1_ar';
SELECT is((SELECT count(*)::int FROM r241 WHERE (r->>'ok')::boolean), 0, 'H29: every probe in section H was refused (no probe silently succeeded)');

-- ═════ V. mark_transfer_sent validates the evidence path (attach's rules) ══
INSERT INTO v241 SELECT tap._row241(tap._t241(1)), tap._n241();
SELECT tap.login(tap.seller());
INSERT INTO r241 VALUES
  ('v_foreign', tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid(), %L)::text', tap._t241(1), tap._ev241(tap.other_user(), '1729000000020.jpg')))),
  ('v_prefix',  tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid(), %L)::text', tap._t241(1), tap.seller()::text || '/proofs/1729000000099.jpg'))),
  ('v_dangle',  tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid(), %L)::text', tap._t241(1), tap._ev241(tap.seller(), 'does-not-exist.jpg')))),
  ('v_bucket',  tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid(), %L)::text', tap._t241(1), tap._ev241(tap.seller(), '1729000000098.jpg')))),
  ('v_empty',   tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid(), %L)::text', tap._t241(1), ''))),
  ('v_nested',  tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid(), %L)::text', tap._t241(1), tap._ev241(tap.other_user(), '1729000000020.jpg') || '/../x'))),
  ('v_relself', tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid(), %L)::text', tap._t241(1), 'transfer-evidence/' || tap.seller()::text || '/1729000000001.jpg')));
SELECT is(tap._cm241(r), 'P0001 | precondition_failed: evidence path must be inside the caller''s own folder',
  'V1: ANOTHER seller''s proof path is refused, with attach''s exact message and code (the reproduced defect)') FROM r241 WHERE k = 'v_foreign';
SELECT is(tap._hd241(r), 'PROOF_PATH_INVALID | <none>', 'V2: ...and HINT PROOF_PATH_INVALID') FROM r241 WHERE k = 'v_foreign';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | precondition_failed: evidence path must be under transfer-evidence/ || PROOF_PATH_INVALID | <none>',
  'V3: the seller''s own object OUTSIDE transfer-evidence/ is refused (attach''s prefix rule)') FROM r241 WHERE k = 'v_prefix';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | precondition_failed: no such object in proof-docs || PROOF_PATH_INVALID | <none>',
  'V4: a DANGLING path (no object) is refused') FROM r241 WHERE k = 'v_dangle';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | precondition_failed: no such object in proof-docs || PROOF_PATH_INVALID | <none>',
  'V5: an evidence-shaped object in ANOTHER bucket (auction-media, public) is refused — only proof-docs counts') FROM r241 WHERE k = 'v_bucket';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | precondition_failed: evidence path is required || PROOF_PATH_INVALID | <none>',
  'V6: an EMPTY path is refused with attach''s own empty-path message (NULL is the only "no evidence" value)') FROM r241 WHERE k = 'v_empty';
SELECT is(tap._cm241(r), 'P0001 | precondition_failed: evidence path must be inside the caller''s own folder',
  'V7: a foreign path with a trailing ../ is still judged by its first segment') FROM r241 WHERE k = 'v_nested';
SELECT is(tap._cm241(r), 'P0001 | precondition_failed: evidence path must be inside the caller''s own folder',
  'V8: the caller''s uid must be the FIRST segment, not just somewhere in the path') FROM r241 WHERE k = 'v_relself';
SELECT is(tap._row241(tap._t241(1)), (SELECT row_before FROM v241),
  'V9: every refused call wrote NOTHING — status, path and xmin of the transfer are unchanged');
SELECT is(tap._n241(), (SELECT n_before FROM v241), 'V10: and no notification fired for a refused call');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id = 'proof-docs' AND name = tap._ev241(tap.other_user(), '1729000000020.jpg')), 0,
  'V11: the consequence is closed: the seller still cannot read the other seller''s private proof object (storage RLS)');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id = 'proof-docs' AND name = tap._ev241(tap.other_user(), '1729000000020.jpg')), 1,
  'V12: control: the buyer of the OTHER seller''s transfer can read it (the transfer-party policy works; V11 is not vacuous)');
SELECT tap.logout();
-- service-role caller: the owner rule binds to p_user_id (= the seller once the seller check passed)
SELECT tap.login_service();
INSERT INTO r241 VALUES
  ('v_svc_bad', tap._e241(format('SELECT public.mark_transfer_sent(%L, %L, %L)::text', tap._t241(4), tap.seller(), tap._ev241(tap.other_user(), '1729000000020.jpg'))));
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | precondition_failed: evidence path must be inside the caller''s own folder || PROOF_PATH_INVALID | <none>',
  'V13: the service-role path is held to the same rule (owner = p_user_id = the seller)') FROM r241 WHERE k = 'v_svc_bad';
SELECT tap.logout();
-- the retry on an already-sent transfer is unchanged: it answers and writes nothing, whatever path it carries
INSERT INTO v241b SELECT tap._row241(tap._t241(11));
SELECT tap.login(tap.seller());
SELECT is(tap._out241(tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid(), %L)::text', tap._t241(11), tap._ev241(tap.other_user(), '1729000000020.jpg')))),
  'already_sent', 'V14: a retry on a sent-with-proof transfer still answers already_sent (unchanged 140 contract; nothing is stored there)');
SELECT is(tap._row241(tap._t241(11)), (SELECT row_before FROM v241b), 'V15: ...and writes nothing (xmin unchanged; the accepted proof stays)');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT is(tap._cm241(tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid(), %L)::text', tap._t241(1), tap._ev241(tap.other_user(), '1729000000020.jpg')))),
  'P0001 | Only the seller can mark a transfer as sent.', 'V16: a non-seller is refused as the seller check, before any path check');
SELECT tap.logout();
-- the owner is the RESOLVED caller (auth.uid(); p_user_id only on the service path), existence is by EXACT name, and the
-- prefix rule keeps its leading slash. One pending transfer per probe (21-23), so a mutant that lets one of these through
-- fails at ITS probe instead of by cascade from an earlier one.
SELECT is((SELECT count(*) FILTER (WHERE o.name = tap._ev241(tap.seller(), '1729'))::text || ' exact, '
               || (count(*) FILTER (WHERE pg_catalog.starts_with(o.name, tap._ev241(tap.seller(), '1729'))
                                      AND o.name <> tap._ev241(tap.seller(), '1729')) > 0)::text || ' longer'
             FROM storage.objects o WHERE o.bucket_id = 'proof-docs'),
  '0 exact, true longer', 'V17: fixture: the truncated path has no proof-docs object of its own and is a strict prefix of a real one (V22 is not vacuous)');
SELECT is((SELECT count(*)::text FROM storage.objects o
            WHERE o.bucket_id = 'proof-docs' AND o.name = tap.seller()::text || '/old-transfer-evidence/1729000000002.jpg'
              AND pg_catalog.split_part(o.name, '/', 1) = tap.seller()::text
              AND o.name LIKE '%transfer-evidence/%' AND o.name NOT LIKE '%/transfer-evidence/%'),
  '1', 'V18: fixture: the seller''s own real proof-docs object that only the leading slash of the prefix rule tells apart (V24 is not vacuous)');
INSERT INTO v241c VALUES ('launder', tap._row241(tap._t241(21))), ('trunc', tap._row241(tap._t241(22))), ('oldev', tap._row241(tap._t241(23)));
SELECT tap.login(tap.seller());
INSERT INTO r241 VALUES
  ('v_launder', tap._e241(format('SELECT public.mark_transfer_sent(%L, %L, %L)::text', tap._t241(21), tap.other_user(), tap._ev241(tap.other_user(), '1729000000020.jpg')))),
  ('v_trunc',   tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid(), %L)::text', tap._t241(22), tap._ev241(tap.seller(), '1729')))),
  ('v_oldev',   tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid(), %L)::text', tap._t241(23), tap.seller()::text || '/old-transfer-evidence/1729000000002.jpg')));
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | precondition_failed: evidence path must be inside the caller''s own folder || PROOF_PATH_INVALID | <none>',
  'V19: an authenticated seller passing p_user_id = ANOTHER seller with that seller''s real proof is refused (the owner is auth.uid(), never the client-supplied p_user_id)') FROM r241 WHERE k = 'v_launder';
SELECT is(tap._row241(tap._t241(21)), (SELECT row_before FROM v241c WHERE k = 'launder'), 'V20: ...and wrote nothing (status, path and xmin unchanged)');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id = 'proof-docs' AND name = tap._ev241(tap.other_user(), '1729000000020.jpg')), 0,
  'V21: ...so the seller still cannot read the other seller''s private proof (the cross-seller read V11 guards, attempted through p_user_id)');
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | precondition_failed: no such object in proof-docs || PROOF_PATH_INVALID | <none>',
  'V22: a TRUNCATED own path (a strict prefix of a real proof-docs object, no object of its own) is refused: existence is by exact name') FROM r241 WHERE k = 'v_trunc';
SELECT is(tap._row241(tap._t241(22)), (SELECT row_before FROM v241c WHERE k = 'trunc'), 'V23: ...and wrote nothing (no dangling path stored)');
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | precondition_failed: evidence path must be under transfer-evidence/ || PROOF_PATH_INVALID | <none>',
  'V24: the seller''s own real object under <uid>/old-transfer-evidence/ is refused, as attach refuses it (A9): the prefix rule keeps its leading slash') FROM r241 WHERE k = 'v_oldev';
SELECT is(tap._row241(tap._t241(23)), (SELECT row_before FROM v241c WHERE k = 'oldev'), 'V25: ...and wrote nothing');
SELECT tap.logout();

-- ═════ C. every caller with valid input still works ═══════════════════════
SELECT tap.login(tap.seller());
-- the app: send/[id].tsx:225 — authenticated seller, all three keys, '<uid>/transfer-evidence/<stamp>.<ext>', uploaded first
SELECT is(tap._out241(tap._e241(format('SELECT public.mark_transfer_sent(%L, %L, %L)::text', tap._t241(16), tap.seller(), tap._ev241(tap.seller(), '1729000000001.jpg')))),
  'transitioned', 'C1: the APP''s call with its own uploaded path transitions the transfer');
SELECT is(tap._st241(tap._t241(16)), 'seller_sent | ' || tap._ev241(tap.seller(), '1729000000001.jpg'), 'C2: ...and records exactly that path');
SELECT ok(tap._n241() > (SELECT n_before FROM v241), 'C3: ...and the transition notifies (unchanged)');
SELECT is(tap._out241(tap._e241(format('SELECT public.mark_transfer_sent(%L, %L, %L)::text', tap._t241(16), tap.seller(), tap._ev241(tap.seller(), '1729000000001.jpg')))),
  'already_sent', 'C4: the app''s lost-response retry still answers already_sent');
-- the web: web/src/lib/transfers.ts:251 — same three keys; path '<uid>/transfer-evidence/<digits>.<ext>' (evidence-upload.ts:100)
SELECT is(tap._out241(tap._e241(format('SELECT public.mark_transfer_sent(%L, %L, %L)::text', tap._t241(15), tap.seller(), tap._ev241(tap.seller(), '1729000000015.jpg')))),
  'transitioned', 'C5: the WEB''s call with its uploaded path transitions');
-- NULL path (3-arg) and the 2-arg overload: sent without evidence, unchanged
SELECT is(tap._out241(tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid(), NULL)::text', tap._t241(2)))),
  'transitioned', 'C6: a NULL path still transitions (the sent-without-evidence flow is unchanged)');
SELECT is(tap._st241(tap._t241(2)), 'seller_sent | <null>', 'C7: ...with no path recorded');
SELECT is(tap._out241(tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid())::text', tap._t241(3)))),
  'transitioned', 'C8: the 2-ARG overload (sandbox 20_matrix.sh:115, pgTAP 040/050/122/131) still transitions');
SELECT is(tap._st241(tap._t241(3)), 'seller_sent | <null>', 'C9: ...with no path recorded');
SELECT tap.logout();
SELECT tap.login_service();
SELECT is(tap._out241(tap._e241(format('SELECT public.mark_transfer_sent(%L, %L, %L)::text', tap._t241(17), tap.seller(), tap._ev241(tap.seller(), '1729000000004.jpg')))),
  'transitioned', 'C10: the service-role caller with the seller''s own valid path transitions');
SELECT tap.logout();
-- attach (send/[id].tsx:290): the explicit recovery is unchanged for valid input
SELECT tap.login(tap.seller());
SELECT is(tap._out241(tap._e241(format('SELECT public.attach_transfer_evidence(%L, %L)::text', tap._t241(5), tap._ev241(tap.seller(), '1729000000005.jpg')))),
  'attached', 'C11: attach_transfer_evidence still attaches a valid proof to a sent-without-proof transfer');
SELECT is(tap._st241(tap._t241(5)), 'seller_sent | ' || tap._ev241(tap.seller(), '1729000000005.jpg'), 'C12: ...and records it');
SELECT is(tap._out241(tap._e241(format('SELECT public.attach_transfer_evidence(%L, %L)::text', tap._t241(5), tap._ev241(tap.seller(), '1729000000005.jpg')))),
  'already_attached', 'C13: the same attach again answers already_attached');
SELECT tap.logout();
-- confirm-and-release: service role confirms a seller_sent transfer; the second call raises the text the edge reads
SELECT tap.login_service();
SELECT is(tap._e241(format('SELECT public.confirm_transfer_received(%L, %L)::text', tap._t241(13), tap.buyer()))->>'ok', 'true',
  'C14: the edge''s confirm_transfer_received call succeeds on a seller_sent transfer');
SELECT is(tap._st241(tap._t241(13)), 'buyer_confirmed | ' || tap._ev241(tap.seller(), '1729000000012.jpg'), 'C15: ...status buyer_confirmed');
SELECT is(tap._cm241(tap._e241(format('SELECT public.confirm_transfer_received(%L, %L)::text', tap._t241(13), tap.buyer()))),
  'P0001 | Transfer cannot be confirmed from current status: buyer_confirmed.', 'C16: the repeat (edge retry) raises the unchanged text the edge treats as already confirmed');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT is(tap._e241(format('SELECT public.confirm_transfer_received(%L, auth.uid())::text', tap._t241(11)))->>'ok', 'true',
  'C17: a buyer session confirming directly also still works');
SELECT tap.logout();

-- ═════ A. attach's own path refusals: same text and code, now with PROOF_PATH_INVALID ═
SELECT tap.login(tap.seller());
INSERT INTO r241 VALUES
  ('a_foreign', tap._e241(format('SELECT public.attach_transfer_evidence(%L, %L)::text', tap._t241(14), tap._ev241(tap.other_user(), '1729000000020.jpg')))),
  ('a_prefix',  tap._e241(format('SELECT public.attach_transfer_evidence(%L, %L)::text', tap._t241(14), tap.seller()::text || '/proofs/1729000000099.jpg'))),
  ('a_dangle',  tap._e241(format('SELECT public.attach_transfer_evidence(%L, %L)::text', tap._t241(14), tap._ev241(tap.seller(), 'does-not-exist.jpg')))),
  ('a_empty',   tap._e241(format('SELECT public.attach_transfer_evidence(%L, %L)::text', tap._t241(14), ''))),
  ('a_null',    tap._e241(format('SELECT public.attach_transfer_evidence(%L, NULL)::text', tap._t241(14)))),
  ('a_trunc',   tap._e241(format('SELECT public.attach_transfer_evidence(%L, %L)::text', tap._t241(14), tap._ev241(tap.seller(), '1729')))),
  ('a_oldev',   tap._e241(format('SELECT public.attach_transfer_evidence(%L, %L)::text', tap._t241(14), tap.seller()::text || '/old-transfer-evidence/1729000000002.jpg')));
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | precondition_failed: evidence path must be inside the caller''s own folder || PROOF_PATH_INVALID | <none>',
  'A1: attach, foreign folder: unchanged text/code, HINT PROOF_PATH_INVALID') FROM r241 WHERE k = 'a_foreign';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | precondition_failed: evidence path must be under transfer-evidence/ || PROOF_PATH_INVALID | <none>',
  'A2: attach, outside transfer-evidence/') FROM r241 WHERE k = 'a_prefix';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | precondition_failed: no such object in proof-docs || PROOF_PATH_INVALID | <none>',
  'A3: attach, dangling') FROM r241 WHERE k = 'a_dangle';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | precondition_failed: evidence path is required || PROOF_PATH_INVALID | <none>',
  'A4: attach, empty') FROM r241 WHERE k = 'a_empty';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | precondition_failed: evidence path is required || PROOF_PATH_INVALID | <none>',
  'A5: attach, NULL') FROM r241 WHERE k = 'a_null';
SELECT is(tap._st241(tap._t241(14)), 'seller_sent | <null>', 'A6: attach''s refusals wrote nothing');
SELECT is(tap._out241(tap._e241(format('SELECT public.attach_transfer_evidence(%L, %L)::text', tap._t241(14), tap._ev241(tap.seller(), '1729000000014.png')))),
  'attached', 'A7: then a valid attach on the same transfer succeeds');
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | precondition_failed: no such object in proof-docs || PROOF_PATH_INVALID | <none>',
  'A8: attach, truncated path (prefix of a real object): refused like mark-sent refuses it (V22)') FROM r241 WHERE k = 'a_trunc';
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | precondition_failed: evidence path must be under transfer-evidence/ || PROOF_PATH_INVALID | <none>',
  'A9: attach, own object under old-transfer-evidence/: refused like mark-sent refuses it (V24)') FROM r241 WHERE k = 'a_oldev';
SELECT tap.logout();

-- ═════ U. the other refusals in the redefined bodies are byte-identical, no hint ═
SELECT tap.login(tap.seller());
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | Transfer not found. || <none> | <none>', 'U1: SNT-3 unchanged')
  FROM (SELECT tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid(), NULL)::text', tap._t241(99))) AS r) x;
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | Only the seller can mark a transfer as sent. || <none> | <none>', 'U2: SNT-4 unchanged')
  FROM (SELECT tap._e241(format('SELECT public.mark_transfer_sent(%L, auth.uid(), NULL)::text', tap._t241(20))) AS r) x;
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | Transfer not found. || <none> | <none>', 'U3: PRF-3 unchanged')
  FROM (SELECT tap._e241(format('SELECT public.attach_transfer_evidence(%L, %L)::text', tap._t241(99), tap._ev241(tap.seller(), '1729000000004.jpg'))) AS r) x;
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), '42501 | insufficient_privilege: only the seller can attach evidence || <none> | <none>', 'U4: PRF-8 unchanged')
  FROM (SELECT tap._e241(format('SELECT public.attach_transfer_evidence(%L, %L)::text', tap._t241(20), tap._ev241(tap.seller(), '1729000000004.jpg'))) AS r) x;
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | Only the buyer can confirm transfer receipt. || <none> | <none>', 'U5: CNF-3 unchanged')
  FROM (SELECT tap._e241(format('SELECT public.confirm_transfer_received(%L, auth.uid())::text', tap._t241(12))) AS r) x;
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | Transfer not found. || <none> | <none>', 'U6: CNF-2 unchanged')
  FROM (SELECT tap._e241(format('SELECT public.confirm_transfer_received(%L, auth.uid())::text', tap._t241(99))) AS r) x;
SELECT tap.logout();
-- trusted service path with no caller id (claims cleared, p_user_id NULL)
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | Unable to identify caller. Ensure the request is authenticated. || <none> | <none>', 'U7: SNT-5 unchanged')
  FROM (SELECT tap._e241(format('SELECT public.mark_transfer_sent(%L, NULL, NULL)::text', tap._t241(12))) AS r) x;
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), 'P0001 | Unable to identify caller. Ensure the request is authenticated. || <none> | <none>', 'U8: CNF-4 unchanged')
  FROM (SELECT tap._e241(format('SELECT public.confirm_transfer_received(%L, NULL)::text', tap._t241(12))) AS r) x;
SELECT is(tap._cm241(r) || ' || ' || tap._hd241(r), '42501 | not_authenticated || <none> | <none>', 'U9: PRF-9 unchanged')
  FROM (SELECT tap._e241(format('SELECT public.attach_transfer_evidence(%L, %L)::text', tap._t241(12), tap._ev241(tap.seller(), '1729000000004.jpg'))) AS r) x;

-- ═════ S. shape: grants, definer, search_path unchanged ════════════════════
SELECT ok(has_function_privilege('authenticated', 'public.mark_transfer_sent(uuid,uuid,text)', 'EXECUTE')
      AND has_function_privilege('service_role',  'public.mark_transfer_sent(uuid,uuid,text)', 'EXECUTE')
      AND NOT has_function_privilege('anon',      'public.mark_transfer_sent(uuid,uuid,text)', 'EXECUTE'), 'S1: mark_transfer_sent(3) grants unchanged');
SELECT ok(has_function_privilege('authenticated', 'public.mark_transfer_sent(uuid,uuid)', 'EXECUTE')
      AND has_function_privilege('service_role',  'public.mark_transfer_sent(uuid,uuid)', 'EXECUTE')
      AND NOT has_function_privilege('anon',      'public.mark_transfer_sent(uuid,uuid)', 'EXECUTE'), 'S2: mark_transfer_sent(2) grants unchanged');
SELECT ok(has_function_privilege('authenticated', 'public.attach_transfer_evidence(uuid,text)', 'EXECUTE')
      AND NOT has_function_privilege('service_role', 'public.attach_transfer_evidence(uuid,text)', 'EXECUTE')
      AND NOT has_function_privilege('anon',      'public.attach_transfer_evidence(uuid,text)', 'EXECUTE'), 'S3: attach grants unchanged (authenticated only)');
SELECT ok(has_function_privilege('authenticated', 'public.confirm_transfer_received(uuid,uuid)', 'EXECUTE')
      AND has_function_privilege('service_role',  'public.confirm_transfer_received(uuid,uuid)', 'EXECUTE')
      AND NOT has_function_privilege('anon',      'public.confirm_transfer_received(uuid,uuid)', 'EXECUTE'), 'S4: confirm_transfer_received grants unchanged');
SELECT ok(NOT has_function_privilege('authenticated', 'public.guard_transfer_state_columns()', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.guard_transfer_state_columns()', 'EXECUTE'), 'S5: the guard trigger function stays no-client-execute');
SELECT is((SELECT string_agg(p.oid::regprocedure::text || ' ' || p.prosecdef || ' ' || coalesce(array_to_string(p.proconfig, ','), '<none>'), '; ' ORDER BY p.oid::regprocedure::text COLLATE "C")
             FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
              AND p.proname IN ('mark_transfer_sent', 'attach_transfer_evidence', 'confirm_transfer_received', 'guard_transfer_state_columns')),
  'attach_transfer_evidence(uuid,text) true search_path=""; confirm_transfer_received(uuid,uuid) true search_path=public; '
  || 'guard_transfer_state_columns() false search_path=public; mark_transfer_sent(uuid,uuid) true search_path=""; mark_transfer_sent(uuid,uuid,text) true search_path=""',
  'S6: SECURITY DEFINER and the pinned search_path are unchanged on all five routines (no new overload)');
SELECT is((SELECT tgenabled::text || ' ' || tgfoid::regprocedure::text FROM pg_trigger WHERE tgrelid = 'public.transfers'::regclass AND tgname = 'trg_guard_transfer_state_columns'),
  'O guard_transfer_state_columns()', 'S7: the guard trigger still fires the same function');

SELECT * FROM finish();
ROLLBACK;

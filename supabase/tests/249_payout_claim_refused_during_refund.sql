-- ============================================================================
-- 249_payout_claim_refused_during_refund.sql — migration 20261022003000 (registry 179): public.claim_payout_attempt,
-- the single choke point before any Stripe transfer (the payout sweep, confirm-and-release, dispute_resolve seller_win
-- through the sweep), refuses with REFUND_IN_FLIGHT while an UNSETTLED console refund_execute exists for the transfer's
-- payment. E's finding D2 (2026-10-21), the inverse of 177; owner decision (Jose, 2026-10-21): "Keep manual refunds,
-- no automatic refund after released payout". Stacked on 157 + 158 + 177 (their bodies are pinned in R7).
--
--   R1  the D2 shape by the production path: a refund parked while the transfer was seller_sent, approved (processing:
--       handed to ops-refund-execute), then the cron auto-releases the transfer; the sweep's claim is refused: P0001
--       'REFUND_IN_FLIGHT', DETAIL = the action id; nothing is written (no attempt row, transfer and action untouched).
--       Once the refund settles failed at Stripe (record_action_outcome) the next claim pays; a new refund afterwards
--       is 177's payout_released with the claimed attempt in its basis: both directions closed on one order.
--   R2  the other release paths: the buyer confirms receipt (confirm_transfer_received) with the refund processing;
--       dispute_resolve seller_win with the refund parked (awaiting_approval).
--   R3  157's vocabulary: requested, unknown and succeeded_at_provider refuse (the last two reached by the executor's
--       record_action_outcome from processing); succeeded (record_action_outcome) and rejected (177's own refusal at
--       approval) do not. With R1 (processing, failed) and R2 (awaiting_approval) every state is covered.
--   R4  legitimate payouts unaffected: no refund; a refund processing on ANOTHER payment; an unsettled payout_release
--       on the transfer (the claim's own direction); every existing answer first (TRANSFER_NOT_RELEASABLE, DISPUTED).
--   R5  the open-attempt RECONCILE path is not refused (design decision: it never opens a new Stripe transfer).
--   R6  the lock: after a claim the session holds 157's order advisory lock (pg_locks, key hashtextextended
--       ('ops_money_order:' || payment id, 0)); the key literal is 157's; statically the lock precedes the transfer
--       FOR UPDATE, which precedes the ops.action read, which precedes the INSERT (the order that cannot deadlock
--       with approve_action: 179 header, LOCK ORDER); the state list is the index's set.
--   R7  catalog: 179's md5; minus the marked 179 blocks the body is production's byte for byte (b6aae868); ACL,
--       SECURITY DEFINER, search_path and the overload count unchanged; anon / authenticated cannot execute,
--       service_role can; the 157 / 158 / 177 bodies, the executor and every payout writer keep their md5s.
--
-- Fixtures: orders n = 1..15 under fixed ids aaaaaaaa/bbbbbbbb/cccccccc-0249-...: listing + succeeded LIVE payment
-- (stripe_livemode true) + transfer (seller_sent unless stated). The seller is onboarded (stripe_connect_id) so
-- claim_payout_attempt reaches its INSERT. Founders A = tap.admin_user(), B = tap.other_user() (platform_admin, aal2 via
-- tap.login); the buyer acts as tap.buyer(); the executor (record_action_outcome) acts as service_role; the payout
-- worker (claim_payout_attempt) runs as postgres (service_role in production). refund_execute_enabled is switched on
-- inside this transaction (setting_set, founder A). Two states are set by hand and labelled so: 'requested' (R3.1, a
-- transient state no money request parks in) and the R5 'processing' row (a refund that reached the executor while
-- an attempt was already open: 177 refuses that request today, so the shape is only reachable from history).
-- ============================================================================
BEGIN;
SELECT plan(38);
SELECT tap.seed_core();

INSERT INTO public.admin_users (user_id, label) VALUES (tap.other_user(), 'FOUNDER B') ON CONFLICT (user_id) DO NOTHING;
UPDATE public.profiles SET stripe_connect_id = 'acct_fixture_249' WHERE id = tap.seller();

CREATE TABLE tap.memo_249 (k text PRIMARY KEY, v jsonb);
CREATE FUNCTION tap._s249(k text, v jsonb) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_249 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v $m$;
CREATE FUNCTION tap._g249(k text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_249 WHERE k = $1 $m$;
CREATE FUNCTION tap._id249(k text) RETURNS uuid
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT (v ->> 'action_id')::uuid FROM tap.memo_249 WHERE k = $1 $m$;
CREATE FUNCTION tap._aal249() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;

-- fixture ids
CREATE FUNCTION tap._l249(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT ('aaaaaaaa-0249-0000-0000-' || lpad(n::text, 12, '0'))::uuid $f$;
CREATE FUNCTION tap._p249(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT ('bbbbbbbb-0249-0000-0000-' || lpad(n::text, 12, '0'))::uuid $f$;
CREATE FUNCTION tap._t249(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT ('cccccccc-0249-0000-0000-' || lpad(n::text, 12, '0'))::uuid $f$;

-- one order: listing + succeeded live payment + a seller_sent transfer (the 247 fixture shape)
CREATE FUNCTION tap._order249(n int) RETURNS void
LANGUAGE plpgsql AS $f$
begin
  insert into public.listings
    (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
     starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
  values (tap._l249(n), tap.seller(), 'Fixture 249 #' || n, 'Club 249', 'wynwood', current_date + 30, '21:00', 'GA', 2, 'mobile_transfer',
          100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/249.jpg', 'active');
  insert into public.payments
    (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at, stripe_livemode)
  values (tap._p249(n), tap._l249(n), tap.buyer(), tap.seller(), 10000, 1000, 1000, 11000, 'pi_fixture_249_' || n, 'succeeded', 'buy_now', now(), true);
  insert into public.transfers
    (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status, seller_sent_at, auto_release_at,
     transfer_evidence_path, expires_at)
  values (tap._t249(n), tap._l249(n), tap._p249(n), tap.seller(), tap.buyer(), 'mobile_transfer', 'seller_sent', now(),
          now() + interval '72 hours', 'fixtures/evidence-249.jpg', now() + interval '24 hours');
end $f$;

-- persona wrappers (the 224 / 247 pattern): each call logs in, runs one RPC, logs out
CREATE FUNCTION tap._ex249(p_who uuid, p_key text, p_type text, p_kind text, p_subject uuid,
                           p_params jsonb DEFAULT '{}'::jsonb, p_ref text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql AS $f$
declare v jsonb;
begin
  perform tap.login(p_who); perform tap._aal249();
  v := ops.execute_action(p_key, p_type, p_kind, p_subject, p_params, 'pgTAP 249 ' || p_type, NULL, p_ref);
  perform tap.logout();
  return v;
end $f$;
CREATE FUNCTION tap._refund249(p_who uuid, p_key text, n int) RETURNS jsonb
LANGUAGE sql AS $f$ SELECT tap._ex249(p_who, p_key, 'refund_execute', 'payment', tap._p249(n)) $f$;
CREATE FUNCTION tap._setting249(p_key text, p_on boolean) RETURNS jsonb
LANGUAGE sql AS $f$ SELECT tap._ex249(tap.admin_user(), p_key, 'setting_set', 'setting', NULL,
                                      jsonb_build_object('value', p_on), 'refund_execute_enabled') $f$;
CREATE FUNCTION tap._ap249(p_who uuid, p_action uuid, p_decision text) RETURNS jsonb
LANGUAGE plpgsql AS $f$
declare v jsonb;
begin
  perform tap.login(p_who); perform tap._aal249();
  v := ops.approve_action(p_action, p_decision, 'pgTAP 249 ' || p_decision);
  perform tap.logout();
  return v;
end $f$;
-- the executor (ops-refund-execute, service_role) reports the refund's outcome
CREATE FUNCTION tap._outcome249(p_action uuid, p_state text) RETURNS jsonb
LANGUAGE plpgsql AS $f$
declare v jsonb;
begin
  perform tap.login_service();
  v := ops.record_action_outcome(p_action, p_state, '{}'::jsonb,
         case when p_state = 'failed' then 'card_declined' end,
         case when p_state in ('succeeded', 'succeeded_at_provider') then 're_fixture_249_' || left(p_action::text, 8) end);
  perform tap.logout();
  return v;
end $f$;
-- the buyer confirms receipt or opens a dispute (the app's RPCs)
CREATE FUNCTION tap._buyer249(p_verb text, n int) RETURNS void
LANGUAGE plpgsql AS $f$
begin
  perform tap.login(tap.buyer());
  if p_verb = 'confirm' then
    perform public.confirm_transfer_received(tap._t249(n), tap.buyer());
  else
    perform public.buyer_dispute_transfer(tap._t249(n), tap.buyer(), 'never_received', NULL, 'pgTAP 249');
  end if;
  perform tap.logout();
end $f$;
-- the payout worker's claim, as postgres: 'ok|<attempt_no>|fresh' (a new attempt), 'ok|<attempt_no>|reconcile' (needs_reconcile) or 'err|<sqlstate>|<message>|<detail>'
CREATE FUNCTION tap._try249(n int) RETURNS text
LANGUAGE plpgsql AS $f$
declare r record; v_state text; v_msg text; v_det text;
begin
  select * into r from public.claim_payout_attempt(tap._t249(n), 'pgtap-249');
  return concat_ws('|', 'ok', r.attempt_no, case when r.needs_reconcile then 'reconcile' else 'fresh' end);
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text, v_det = pg_exception_detail;
  return concat_ws('|', 'err', v_state, v_msg, v_det);
end $f$;
-- the refusal the claim must give for the memoised refund action k
CREATE FUNCTION tap._refused249(k text) RETURNS text LANGUAGE sql AS $f$
  SELECT 'err|P0001|REFUND_IN_FLIGHT|' || tap._id249(k)::text $f$;
-- the order's payout state, read from the tables (independent of the code under test)
CREATE FUNCTION tap._fx249(n int) RETURNS text LANGUAGE sql AS $f$
  SELECT concat_ws('/', t.status, (SELECT count(*) FROM public.payout_attempts a WHERE a.transfer_id = t.id)::text || '_attempts',
                   CASE WHEN t.payout_released_at IS NULL THEN 'unrecorded' ELSE 'recorded' END,
                   coalesce(t.stripe_transfer_id, 'no_tr'))
    FROM public.transfers t WHERE t.id = tap._t249(n) $f$;
CREATE FUNCTION tap._act249(k text) RETURNS text LANGUAGE sql AS $f$
  SELECT a.state || '/' || coalesce(a.reject_reason, '-') FROM ops.action a WHERE a.id = tap._id249(k) $f$;

SELECT is(tap._setting249('k249-set-refund-on', true) ->> 'status', 'succeeded', 'S0: setting_set refund_execute_enabled=true succeeds inside the test');

-- ── R1 — the D2 shape by the production path (order 1) ──
SELECT tap._order249(1);
SELECT tap._s249('r1', tap._refund249(tap.admin_user(), 'k249-r1-refund-a01', 1));
SELECT tap._s249('r1ap', tap._ap249(tap.other_user(), tap._id249('r1'), 'approve'));
SELECT is((tap._g249('r1') ->> 'status', tap._g249('r1ap') ->> 'status', tap._g249('r1ap') #>> '{result,handoff}', tap._act249('r1'),
           public.apply_auto_release(tap._t249(1)), tap._fx249(1)),
          ('awaiting_approval'::text, 'processing'::text, 'ops-refund-execute'::text, 'processing/-'::text, true, 'auto_released/0_attempts/unrecorded/no_tr'::text),
  'R1.1: fixture: the refund parked (seller_sent), was approved and handed to ops-refund-execute (processing); then the cron auto-released the transfer');
SELECT is(tap._try249(1), tap._refused249('r1'),
  'R1.2: the sweep''s claim is refused: P0001 REFUND_IN_FLIGHT, DETAIL = the processing refund''s action id');
SELECT is((tap._fx249(1), tap._act249('r1'), (SELECT (t.status, t.payout_released_at, t.stripe_transfer_id, t.payout_review_status) FROM public.transfers t WHERE t.id = tap._t249(1))::text),
          ('auto_released/0_attempts/unrecorded/no_tr'::text, 'processing/-'::text, '(auto_released,,,)'::text),
  'R1.3: nothing written by the refusal: no payout_attempts row, the transfer and the action row untouched');
SELECT is(tap._try249(1), tap._refused249('r1'), 'R1.4: a second claim is refused the same way (no state drift from the refusal)');
SELECT is((tap._outcome249(tap._id249('r1'), 'failed') ->> 'state', tap._act249('r1'), tap._try249(1), tap._fx249(1)),
          ('failed'::text, 'failed/-'::text, 'ok|1|fresh'::text, 'auto_released/1_attempts/unrecorded/no_tr'::text),
  'R1.5: the refund settles failed at Stripe (record_action_outcome): the next sweep''s claim opens attempt #1');
SELECT tap._s249('r1b', tap._refund249(tap.admin_user(), 'k249-r1-refund-a02', 1));
SELECT is((tap._g249('r1b') ->> 'status', tap._g249('r1b') ->> 'reject_reason', (tap._g249('r1b') #>> '{result,payout,basis}') LIKE '%payout_attempt_claimed%'),
          ('rejected'::text, 'payout_released'::text, true),
  'R1.6: and a new refund on the order is now 177''s payout_released with the claimed attempt in its basis: both directions closed');

-- ── R2 — the other release paths (orders 2, 3) ──
SELECT tap._order249(2);
SELECT tap._s249('r2', tap._refund249(tap.admin_user(), 'k249-r2-refund-a01', 2));
SELECT tap._s249('r2ap', tap._ap249(tap.other_user(), tap._id249('r2'), 'approve'));
SELECT tap._buyer249('confirm', 2);
SELECT is((tap._g249('r2ap') ->> 'status', tap._act249('r2'), tap._fx249(2)), ('processing'::text, 'processing/-'::text, 'buyer_confirmed/0_attempts/unrecorded/no_tr'::text),
  'R2.1a: fixture: refund processing, then the buyer confirmed receipt (buyer_confirmed)');
SELECT is(tap._try249(2), tap._refused249('r2'), 'R2.1b: confirm-and-release''s claim is refused: REFUND_IN_FLIGHT, DETAIL = the action id');
SELECT tap._order249(3);
SELECT tap._buyer249('dispute', 3);
SELECT tap._s249('r3', tap._refund249(tap.admin_user(), 'k249-r3-refund-a01', 3));
SELECT tap._s249('r3sw', tap._ex249(tap.admin_user(), 'k249-r3-resolve-03', 'dispute_resolve', 'transfer', tap._t249(3), '{"outcome": "seller_win"}'::jsonb));
SELECT is((tap._g249('r3') ->> 'status', tap._g249('r3sw') ->> 'status', tap._act249('r3'),
           (SELECT (t.status, t.dispute_resolution, t.buyer_confirmed_at IS NULL) FROM public.transfers t WHERE t.id = tap._t249(3))::text),
          ('awaiting_approval'::text, 'succeeded'::text, 'awaiting_approval/-'::text, '(buyer_confirmed,resolved_seller_paid,t)'::text),
  'R2.2a: fixture: a refund parked during the dispute; dispute_resolve seller_win released the payout (buyer_confirmed, resolved_seller_paid)');
SELECT is(tap._try249(3), tap._refused249('r3'), 'R2.2b: the seller-win payout''s claim is refused while the refund is awaiting approval');

-- ── R3 — 157's vocabulary (orders 4..8) ──
SELECT tap._order249(4); SELECT tap._s249('r4', tap._refund249(tap.admin_user(), 'k249-r4-refund-a01', 4)); SELECT public.apply_auto_release(tap._t249(4));
UPDATE ops.action SET state = 'requested' WHERE id = tap._id249('r4');   -- by hand: a transient state (labelled in the header)
SELECT is((tap._act249('r4'), tap._try249(4)), ('requested/-'::text, tap._refused249('r4')), 'R3.1: requested => refused');
SELECT tap._order249(5); SELECT tap._s249('r5', tap._refund249(tap.admin_user(), 'k249-r5-refund-a01', 5));
SELECT tap._s249('r5ap', tap._ap249(tap.other_user(), tap._id249('r5'), 'approve')); SELECT public.apply_auto_release(tap._t249(5));
SELECT is((tap._outcome249(tap._id249('r5'), 'unknown') ->> 'state', tap._act249('r5'), tap._try249(5)), ('unknown'::text, 'unknown/-'::text, tap._refused249('r5')),
  'R3.2: unknown (the executor lost Stripe''s answer) => refused');
SELECT tap._order249(6); SELECT tap._s249('r6', tap._refund249(tap.admin_user(), 'k249-r6-refund-a01', 6));
SELECT tap._s249('r6ap', tap._ap249(tap.other_user(), tap._id249('r6'), 'approve')); SELECT public.apply_auto_release(tap._t249(6));
SELECT is((tap._outcome249(tap._id249('r6'), 'succeeded_at_provider') ->> 'state', tap._act249('r6'), tap._try249(6)),
          ('succeeded_at_provider'::text, 'succeeded_at_provider/-'::text, tap._refused249('r6')),
  'R3.3: succeeded_at_provider (refunded at Stripe, webhook pending) => refused');
SELECT tap._order249(7); SELECT tap._s249('r7', tap._refund249(tap.admin_user(), 'k249-r7-refund-a01', 7));
SELECT tap._s249('r7ap', tap._ap249(tap.other_user(), tap._id249('r7'), 'approve')); SELECT public.apply_auto_release(tap._t249(7));
SELECT is((tap._outcome249(tap._id249('r7'), 'succeeded') ->> 'state', tap._act249('r7'), tap._try249(7)), ('succeeded'::text, 'succeeded/-'::text, 'ok|1|fresh'::text),
  'R3.4: succeeded (terminal) => not refused (the recorded refund then makes production''s PAYMENT_NOT_SUCCEEDED answer)');
SELECT tap._order249(8); SELECT tap._s249('r8', tap._refund249(tap.admin_user(), 'k249-r8-refund-a01', 8)); SELECT public.apply_auto_release(tap._t249(8));
SELECT tap._s249('r8ap', tap._ap249(tap.other_user(), tap._id249('r8'), 'approve'));
SELECT is((tap._g249('r8ap') ->> 'reject_reason', tap._act249('r8'), tap._try249(8)), ('payout_released'::text, 'rejected/payout_released'::text, 'ok|1|fresh'::text),
  'R3.5: rejected (177 refused the approval after the release) => not refused: the payout proceeds');

-- ── R4 — legitimate payouts unaffected; existing answers first (orders 9..14) ──
SELECT tap._order249(9); SELECT public.apply_auto_release(tap._t249(9));
SELECT is(tap._try249(9), 'ok|1|fresh', 'R4.1: no refund_execute on the payment => claimed');
SELECT tap._order249(10); SELECT tap._s249('r10', tap._refund249(tap.admin_user(), 'k249-r10-refund-a01', 10));
SELECT tap._s249('r10ap', tap._ap249(tap.other_user(), tap._id249('r10'), 'approve'));
SELECT tap._order249(11); SELECT public.apply_auto_release(tap._t249(11));
SELECT is((tap._act249('r10'), tap._try249(11)), ('processing/-'::text, 'ok|1|fresh'::text), 'R4.2: a refund processing on ANOTHER payment (order 10) does not refuse order 11''s claim');
SELECT tap._order249(12); SELECT tap._s249('r12pr', tap._ex249(tap.admin_user(), 'k249-r12-payout-a01', 'payout_release', 'transfer', tap._t249(12)));
SELECT public.apply_auto_release(tap._t249(12));
SELECT is((tap._g249('r12pr') ->> 'status', tap._try249(12)), ('awaiting_approval'::text, 'ok|1|fresh'::text), 'R4.3: an unsettled payout_release on the transfer (the claim''s own direction) does not refuse');
SELECT tap._order249(13); SELECT tap._s249('r13', tap._refund249(tap.admin_user(), 'k249-r13-refund-a01', 13));
SELECT tap._s249('r13ap', tap._ap249(tap.other_user(), tap._id249('r13'), 'approve'));
SELECT is((tap._act249('r13'), tap._try249(13)), ('processing/-'::text, 'err|P0001|TRANSFER_NOT_RELEASABLE|status=seller_sent'::text),
  'R4.4: a seller_sent transfer with a refund processing => the existing TRANSFER_NOT_RELEASABLE answers first, byte for byte');
SELECT tap._order249(14); SELECT tap._s249('r14', tap._refund249(tap.admin_user(), 'k249-r14-refund-a01', 14)); SELECT tap._buyer249('dispute', 14);
SELECT is((tap._act249('r14'), tap._try249(14)), ('awaiting_approval/-'::text, 'err|P0001|DISPUTED|'::text),
  'R4.5: a disputed transfer with a refund parked => the existing DISPUTED answers first');

-- ── R5 — the open-attempt reconcile path (order 15) ──
SELECT tap._order249(15); SELECT tap._s249('r15', tap._refund249(tap.admin_user(), 'k249-r15-refund-a01', 15)); SELECT public.apply_auto_release(tap._t249(15));
SELECT tap._s249('r15ap', tap._ap249(tap.other_user(), tap._id249('r15'), 'approve'));
SELECT is((tap._act249('r15'), tap._try249(15)), ('rejected/payout_released'::text, 'ok|1|fresh'::text), 'R5.1: fixture: attempt #1 claimed on order 15 (its refund rejected by 177)');
UPDATE public.payout_attempts SET lease_expires_at = now() - interval '1 minute' WHERE transfer_id = tap._t249(15);   -- the lease ran out
UPDATE ops.action SET state = 'processing', reject_reason = NULL WHERE id = tap._id249('r15');                       -- by hand (header): a refund at the executor while an attempt is open
SELECT is((tap._act249('r15'), tap._try249(15), tap._fx249(15)), ('processing/-'::text, 'ok|1|reconcile'::text, 'auto_released/1_attempts/unrecorded/no_tr'::text),
  'R5.2: the open attempt is handed back for RECONCILIATION (needs_reconcile, no new row): the reconcile path is not refused, by design');

-- ── R6 — the lock ──
SELECT is((SELECT count(*)::int FROM pg_locks l
            WHERE l.locktype = 'advisory' AND l.pid = pg_backend_pid() AND l.granted AND l.objsubid = 1
              AND l.database = (SELECT oid FROM pg_database WHERE datname = current_database())
              AND l.classid::bigint = ((hashtextextended('ops_money_order:' || tap._p249(9)::text, 0) >> 32) & 4294967295)
              AND l.objid::bigint = (hashtextextended('ops_money_order:' || tap._p249(9)::text, 0) & 4294967295)), 1,
  'R6.1: after order 9''s claim this transaction holds 157''s order advisory lock for payment 9 (pg_locks, the 64-bit key split as classid / objid)');
SELECT is((SELECT count(*)::int FROM pg_locks l
            WHERE l.locktype = 'advisory' AND l.pid = pg_backend_pid() AND l.objsubid = 1
              AND l.database = (SELECT oid FROM pg_database WHERE datname = current_database())
              AND l.classid::bigint = ((hashtextextended('ops_money_order:' || tap._p249(1)::text, 0) >> 32) & 4294967295)
              AND l.objid::bigint = (hashtextextended('ops_money_order:' || tap._p249(1)::text, 0) & 4294967295)), 1,
  'R6.2: and for payment 1 (its claim ran inside this transaction too; the refused claims released theirs with their subtransaction)');
SELECT is((SELECT (position('pg_advisory_xact_lock(' IN d) > 0
                   AND position('pg_advisory_xact_lock(' IN d) < position('FROM public.transfers WHERE id = p_transfer_id FOR UPDATE;' IN d)
                   AND position('FROM public.transfers WHERE id = p_transfer_id FOR UPDATE;' IN d) < position('FROM ops.action a' IN d)
                   AND position('FROM ops.action a' IN d) < position('INSERT INTO public.payout_attempts' IN d))
             FROM (SELECT pg_get_functiondef('public.claim_payout_attempt(uuid,text,interval)'::regprocedure) AS d) x), true,
  'R6.3: statically: the advisory lock precedes the transfer FOR UPDATE, which precedes the ops.action read, which precedes the INSERT (the order that cannot deadlock with approve_action)');
SELECT is((SELECT (position($k$hashtextextended('ops_money_order:' || v_order::text, 0)$k$ IN c) > 0,
                   position($k$hashtextextended('ops_money_order:' || v_t.payment_id::text, 0)$k$ IN c) > 0,
                   position($k$pg_advisory_xact_lock(hashtextextended('ops_money_order:' || v_order::text, 0))$k$ IN e) > 0,
                   position($k$pg_advisory_xact_lock(hashtextextended('ops_money_order:' || v_order::text, 0))$k$ IN a) > 0)
             FROM (SELECT pg_get_functiondef('public.claim_payout_attempt(uuid,text,interval)'::regprocedure) AS c,
                          pg_get_functiondef('ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)'::regprocedure) AS e,
                          pg_get_functiondef('ops.approve_action(uuid,text,text)'::regprocedure) AS a) x)::text, '(t,t,t,t)',
  'R6.4: the key literal is 157''s (hashtextextended(''ops_money_order:'' || <payment id>, 0)), the same expression ops.execute_action and ops.approve_action lock');
SELECT is((SELECT position($s$AND a.state IN ('requested','awaiting_approval','processing','unknown','succeeded_at_provider')$s$ IN pg_get_functiondef('public.claim_payout_attempt(uuid,text,interval)'::regprocedure)) > 0
            AND (SELECT array_agg(m[1] ORDER BY m[1]) FROM regexp_matches(pg_get_indexdef(to_regclass('ops.action_money_unsettled_uidx')), '''([a-z_]+)''::text', 'g') m
                  WHERE m[1] NOT IN ('refund_execute', 'payout_release'))
                = ARRAY['awaiting_approval', 'processing', 'requested', 'succeeded_at_provider', 'unknown']), true,
  'R6.5: the state list the claim reads is exactly the unsettled set of 157''s index action_money_unsettled_uidx');

-- ── R7 — catalog ──
SELECT is(md5(pg_get_functiondef('public.claim_payout_attempt(uuid,text,interval)'::regprocedure)), 'e2ba30303f77137f589bb4fd37778cb1',
  'R7.1: claim_payout_attempt carries 179''s body (md5 e2ba3030)');
SELECT is((SELECT md5(regexp_replace(d, '  -- 179 begin\n.*?  -- 179 end\n', '', 'g'))
             FROM (SELECT pg_get_functiondef('public.claim_payout_attempt(uuid,text,interval)'::regprocedure) AS d) x),
          'b6aae8680e1891892dd0d42f62b9531b',
  'R7.2: minus the three marked 179 blocks the body is production''s byte for byte (md5 b6aae868): nothing else changed');
SELECT is((SELECT (regexp_count(d, '  -- 179 begin\n'), regexp_count(d, '  -- 179 end\n'))
             FROM (SELECT pg_get_functiondef('public.claim_payout_attempt(uuid,text,interval)'::regprocedure) AS d) x)::text, '(3,3)',
  'R7.3: exactly three marked blocks (DECLARE, the lock before the transfer FOR UPDATE, the check before the INSERT)');
SELECT is((SELECT coalesce(array_to_string(p.proacl, ','), '<default>') || ':' || p.prosecdef || ':'
                   || coalesce(array_to_string(p.proconfig, ','), '') || ':' || p.provolatile::text
             FROM pg_proc p WHERE p.oid = 'public.claim_payout_attempt(uuid,text,interval)'::regprocedure),
          'postgres=X/postgres,service_role=X/postgres:true:search_path=public:v',
  'R7.4: ACL (postgres + service_role, as production), SECURITY DEFINER, search_path public and volatility unchanged');
SELECT ok(NOT has_function_privilege('anon', 'public.claim_payout_attempt(uuid,text,interval)'::regprocedure, 'EXECUTE'), 'R7.5: anon may not execute it');
SELECT ok(NOT has_function_privilege('authenticated', 'public.claim_payout_attempt(uuid,text,interval)'::regprocedure, 'EXECUTE'), 'R7.6: authenticated may not execute it');
SELECT ok(has_function_privilege('service_role', 'public.claim_payout_attempt(uuid,text,interval)'::regprocedure, 'EXECUTE'), 'R7.7: service_role (the sweep and the edges) may');
SELECT is((SELECT count(*)::int FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'claim_payout_attempt'), 1, 'R7.8: exactly one claim_payout_attempt (no overload)');
SELECT is((WITH want(sig, md5) AS (VALUES
             -- 157 / 158 / 177 bodies this file stacks on (unchanged by it)
             ('ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)', '24209d0697132d5df7bd12f5cf3e5c0c'),
             ('ops.approve_action(uuid,text,text)', 'ddcdcd1401839910726d20ddd206e40d'),
             ('ops.order_detail(uuid)', '4358f577291f84b25986b8904b38ab36'),
             ('ops.action_dispatch(ops.action)', '530105443dff97cdf1639c12d2bf24f1'),
             ('ops.action_precheck(ops.action)', '20a5ae0386be0644293f5230fad84dde'),
             ('ops.refund_payout_refusal(uuid,text)', '897a1f932f20cd775795e7bea740c3b4'),
             -- production: the action pipeline and the refund executor's functions
             ('ops.action_run(uuid)', '546693f1489c364de19e9416a92c07ed'),
             ('ops.executor_claim(uuid,integer)', '1cfa0290546ff36fe07389a9d13b7f9e'),
             ('ops.record_action_outcome(uuid,text,jsonb,text,text)', 'c4fb902ec1f0d0166955993b4cfe96df'),
             ('ops.detect_refunds()', '6a4727f4f39ced0a6078ac639b38de16'),
             -- production: every other payout / transfer writer (247 P9.8's list minus the claim)
             ('public.mark_payout_requested(uuid)', '4c6b3cf979f54450d21decd453c47017'),
             ('public.record_payout_attempt_result(uuid,text,text,jsonb)', '255e9022cd3ef39a20835ae18cc4196e'),
             ('public.reconcile_payout_attempt(uuid,text)', '3d9f95f1d697a4932dfb942c68af12d5'),
             -- BE-37 comment-only drift (247 P9.8 carries the same pair): production's md5 (this suite on the replay) or the chain's
             -- (CI builds the chain); both read with md5(pg_get_functiondef) on a_sprint_prod_template / a_sprint_chain 2026-10-22.
             ('public.record_transfer_payout(uuid,text)', '30622f9196dfae1ccec6e503492f8e03'),
             ('public.record_transfer_payout(uuid,text)', '464d2299d60c9ad8394ea89fc8e16df5'),
             ('public.admin_release_held_payout(uuid,uuid,text)', '41b3487b3a6c30f5ba80739d1d523406'),
             ('public.apply_auto_release(uuid)', '989e89ddc5d48f80f0bc844c88f8500d'),
             ('public.flag_payout_reversal_required(uuid,text,jsonb)', '0d692f3262b234fed9c492a8204b5d01'),
             ('public.mark_transfer_reversed(text)', 'd7650290139e377646cfcbd7094d2376'),
             ('public.freeze_transfer_for_dispute(uuid)', 'ae88b2ed854811a0d4462acd4050aa9e'),
             ('public.resolve_transfer_dispute(uuid,text,uuid,text,text)', '7d18f1d80991e78d1dfea9e8ad7bb209'),
             ('public.resolve_transfer_dispute(uuid,text,uuid,text,text)', '7b9e17a54ec065195a7969d8b107d61d'),
             ('public.confirm_transfer_received(uuid,uuid)', 'a009719657758db9d117d91108b09cbd'),
             ('public.confirm_transfer_received(uuid,uuid)', '2628bda3533c447295ae153e3e276f9a'),   -- 171 (20261021131000) redefines it from production's body
             ('public.buyer_dispute_transfer(uuid,uuid,text,text,text)', 'ea1aa60569a74bc13f4bf62fb1d898c9'),
             ('public.record_payment_refund(text,text,text,integer,text)', '8ce828e3461f97844faa36450241dc8f')),
             ('public.record_payment_refund(text,text,text,integer,text)', 'aadd3cca365aae33b1903daaf9ff67d7'   -- 175 (20261021135000) redefines it from production's body)
           -- a signature fails only when its live md5 matches NONE of its listed values (one value for all but the two drifting writers)
           SELECT coalesce(array_agg(w.sig ORDER BY w.sig), '{}'::text[]) FROM (SELECT DISTINCT sig FROM want) w
            WHERE NOT EXISTS (SELECT 1 FROM want w2 WHERE w2.sig = w.sig AND md5(pg_get_functiondef(to_regprocedure(w2.sig))) = w2.md5)),
          '{}'::text[],
  'R7.9: unchanged: the 157 / 158 / 177 bodies, the production action pipeline, the executor and every other payout writer (record_transfer_payout / resolve_transfer_dispute: production''s or the chain''s md5)');
SELECT is((SELECT obj_description('public.claim_payout_attempt(uuid,text,interval)'::regprocedure, 'pg_proc') LIKE '179 (20261022003000): %'), true,
  'R7.10: the function comment names 179 (the rollback removes it)');

SELECT * FROM finish();
ROLLBACK;

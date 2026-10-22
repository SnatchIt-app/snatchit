-- ============================================================================
-- 247_ops_refund_refused_after_payout.sql — migration 20261022001000 (registry 177): the console's automated refund
-- (refund_execute: ops.execute_action -> ops.action_precheck -> approve_action -> ops.action_dispatch -> the
-- ops-refund-execute edge) is refused once the order's seller payout is released or in flight. Owner decision (Jose,
-- 2026-10-21): "Keep manual refunds, no automatic refund after released payout."
--
--   P1  the 224 T5.16 shape: a payout_release requested and approved in the console (admin_release_held_payout, the
--       transfer is auto_released); a refund_execute afterwards is refused at request: rejected / payout_released, the
--       contract message (owner decision + manual refund SOP), result = the full envelope (stage 'request', payout
--       evidence); recorded like every precheck rejection (rejected row, key bound, no approval, audited); the key
--       replays; nothing is refunded.
--   P2  every released / in-flight shape, each produced by the production writer that produces it, is refused at
--       request with its exact basis and message: buyer confirmation; the auto-release cron; a payout attempt claimed /
--       requested / unknown / succeeded; reversal_required (PAID_DURING_DISPUTE); a reversed transfer; the legacy
--       record_transfer_payout on a seller_sent transfer (the money-moved columns alone); an open attempt on a
--       transfer frozen for a dispute (the attempt alone).
--   P3  neither released nor in flight: still accepted (seller_sent, pending, expired, a buyer-win dispute, a FAILED
--       attempt on a frozen transfer, a payment with no transfer row).
--   P4  dispute_resolve seller_win (the console's own release of a disputed payout): the refund parked during the
--       dispute is refused when approved; a new one is refused at request.
--   P5  TOCTOU: a refund parked while the transfer was seller_sent, then the cron auto-releases it / the buyer
--       confirms and the payout is recorded; approving it is refused at approval (stage 'approval'): the action ends
--       rejected, nothing is handed to ops-refund-execute, executor_claim refuses it (terminal), the payment stays
--       succeeded.
--   P6  the refund dispatch locks the order's transfer row (locked, not updated, after an accepted dispatch whose
--       answer is unchanged) and, statically, before it reads the payout state, with a plain WAITING FOR UPDATE (the
--       statement ends in 'for update;': no SKIP LOCKED, no NOWAIT; review B1: a SKIP LOCKED mutant passed P6.1-P6.4).
--   P7  157 interplay, both orders: an UNSETTLED payout_release blocks a refund as 157's duplicate_unsettled (157
--       answers first); once SETTLED, 177 answers payout_released. A parked refund blocks a payout_release (157);
--       after the deny the payout settles and a new refund is payout_released.
--   P8  every existing answer comes first, byte for byte, on released orders: disabled, payment refunded
--       (stale_state), partial (not_supported), out of range (precondition); disabled at approval.
--   P9  catalog: the helper is internal (postgres only, definer, search_path '', STABLE); action_precheck and
--       action_dispatch keep ACL and attributes; each minus its marked 177 block is its predecessor byte for byte
--       (production action_precheck fbc3d08e, 158's action_dispatch 7f507fc8); the 157/158 bodies, the ops executor
--       functions and every payout writer keep their md5s.
--
-- Fixtures: orders n = 1..30 under fixed ids aaaaaaaa/bbbbbbbb/cccccccc-0247-...: listing + succeeded LIVE payment
-- (stripe_livemode true) + transfer (seller_sent unless stated). The seller is onboarded (stripe_connect_id) so
-- claim_payout_attempt runs. Founders A = tap.admin_user(), B = tap.other_user() (platform_admin, aal2 via tap.login);
-- the buyer acts as tap.buyer(). refund_execute_enabled is switched on inside this transaction (setting_set, founder
-- A). The payout writers run as postgres (service_role in production). Expired transfers are inserted directly, as
-- 000_helpers inserts transfers.
-- ============================================================================
BEGIN;
SELECT plan(89);
SELECT tap.seed_core();

INSERT INTO public.admin_users (user_id, label) VALUES (tap.other_user(), 'FOUNDER B') ON CONFLICT (user_id) DO NOTHING;
UPDATE public.profiles SET stripe_connect_id = 'acct_fixture_247' WHERE id = tap.seller();

CREATE TABLE tap.memo_247 (k text PRIMARY KEY, v jsonb);
CREATE FUNCTION tap._s247(k text, v jsonb) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_247 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v $m$;
CREATE FUNCTION tap._g247(k text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_247 WHERE k = $1 $m$;
CREATE FUNCTION tap._id247(k text) RETURNS uuid
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT (v ->> 'action_id')::uuid FROM tap.memo_247 WHERE k = $1 $m$;
CREATE FUNCTION tap._aal247() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;

-- fixture ids
CREATE FUNCTION tap._l247(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT ('aaaaaaaa-0247-0000-0000-' || lpad(n::text, 12, '0'))::uuid $f$;
CREATE FUNCTION tap._p247(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT ('bbbbbbbb-0247-0000-0000-' || lpad(n::text, 12, '0'))::uuid $f$;
CREATE FUNCTION tap._t247(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT ('cccccccc-0247-0000-0000-' || lpad(n::text, 12, '0'))::uuid $f$;

-- one order: listing + succeeded live payment + (optionally) a transfer in p_status (seller_sent, pending or expired)
CREATE FUNCTION tap._order247(n int, p_status text DEFAULT 'seller_sent', p_transfer boolean DEFAULT true) RETURNS void
LANGUAGE plpgsql AS $f$
begin
  insert into public.listings
    (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
     starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
  values (tap._l247(n), tap.seller(), 'Fixture 247 #' || n, 'Club 247', 'wynwood', current_date + 30, '21:00', 'GA', 2, 'mobile_transfer',
          100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/247.jpg', 'active');
  insert into public.payments
    (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at, stripe_livemode)
  values (tap._p247(n), tap._l247(n), tap.buyer(), tap.seller(), 10000, 1000, 1000, 11000, 'pi_fixture_247_' || n, 'succeeded', 'buy_now', now(), true);
  if p_transfer then
    insert into public.transfers
      (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status, seller_sent_at, auto_release_at,
       transfer_evidence_path, expires_at, expired_at)
    values (tap._t247(n), tap._l247(n), tap._p247(n), tap.seller(), tap.buyer(), 'mobile_transfer', p_status,
            case when p_status = 'seller_sent' then now() end,
            case when p_status = 'seller_sent' then now() + interval '72 hours' end,
            case when p_status = 'seller_sent' then 'fixtures/evidence-247.jpg' end,
            case when p_status = 'expired' then now() - interval '2 hours' else now() + interval '24 hours' end,
            case when p_status = 'expired' then now() - interval '2 hours' end);
  end if;
end $f$;

-- persona wrappers (the 184 / 224 pattern): each call logs in, runs one RPC, logs out
CREATE FUNCTION tap._ex247(p_who uuid, p_key text, p_type text, p_kind text, p_subject uuid,
                           p_params jsonb DEFAULT '{}'::jsonb, p_ref text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql AS $f$
declare v jsonb;
begin
  perform tap.login(p_who); perform tap._aal247();
  v := ops.execute_action(p_key, p_type, p_kind, p_subject, p_params, 'pgTAP 247 ' || p_type, NULL, p_ref);
  perform tap.logout();
  return v;
end $f$;
CREATE FUNCTION tap._refund247(p_who uuid, p_key text, n int, p_params jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
LANGUAGE sql AS $f$ SELECT tap._ex247(p_who, p_key, 'refund_execute', 'payment', tap._p247(n), p_params) $f$;
CREATE FUNCTION tap._setting247(p_key text, p_on boolean) RETURNS jsonb
LANGUAGE sql AS $f$ SELECT tap._ex247(tap.admin_user(), p_key, 'setting_set', 'setting', NULL,
                                      jsonb_build_object('value', p_on), 'refund_execute_enabled') $f$;
CREATE FUNCTION tap._ap247(p_who uuid, p_action uuid, p_decision text) RETURNS jsonb
LANGUAGE plpgsql AS $f$
declare v jsonb;
begin
  perform tap.login(p_who); perform tap._aal247();
  v := ops.approve_action(p_action, p_decision, 'pgTAP 247 ' || p_decision);
  perform tap.logout();
  return v;
end $f$;
CREATE FUNCTION tap._claim247(p_action uuid) RETURNS jsonb
LANGUAGE plpgsql AS $f$
declare v jsonb;
begin
  perform tap.login_service();
  v := ops.executor_claim(p_action, 300);
  perform tap.logout();
  return v;
end $f$;
-- the buyer confirms receipt or opens a dispute (the app's RPCs)
CREATE FUNCTION tap._buyer247(p_verb text, n int) RETURNS void
LANGUAGE plpgsql AS $f$
begin
  perform tap.login(tap.buyer());
  if p_verb = 'confirm' then
    perform public.confirm_transfer_received(tap._t247(n), tap.buyer());
  else
    perform public.buyer_dispute_transfer(tap._t247(n), tap.buyer(), 'never_received', NULL, 'pgTAP 247');
  end if;
  perform tap.logout();
end $f$;
-- the payout worker's protocol (claim -> mark requested -> record), as postgres
CREATE FUNCTION tap._attempt247(n int) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM public.payout_attempts WHERE transfer_id = tap._t247(n) ORDER BY attempt_no DESC LIMIT 1 $f$;
CREATE FUNCTION tap._payout247(n int, p_upto text) RETURNS text
LANGUAGE plpgsql AS $f$
declare v_att uuid;
begin
  perform public.claim_payout_attempt(tap._t247(n), 'pgtap-247');
  v_att := tap._attempt247(n);
  if p_upto = 'claimed' then return 'claimed'; end if;
  if not public.mark_payout_requested(v_att) then return 'mark_payout_requested refused'; end if;
  if p_upto = 'requested' then return 'requested'; end if;
  return public.record_payout_attempt_result(v_att,
           case when p_upto = 'succeeded' then 'tr_fixture_247_' || n end,
           case p_upto when 'succeeded' then 'succeeded' when 'failed' then 'failed_not_created' else 'unknown' end,
           NULL) ->> 'state';
end $f$;
-- the payout state of order n, read from the tables (independent of the code under test)
CREATE FUNCTION tap._fx247(n int) RETURNS text LANGUAGE sql AS $f$
  SELECT concat_ws('/', t.status, coalesce((SELECT a.state FROM public.payout_attempts a WHERE a.transfer_id = t.id
                                             ORDER BY a.attempt_no DESC LIMIT 1), 'no_attempt'),
                   CASE WHEN t.payout_released_at IS NULL THEN 'unrecorded' ELSE 'recorded' END,
                   coalesce(t.stripe_transfer_id, 'no_tr'))
    FROM public.transfers t WHERE t.id = tap._t247(n) $f$;

-- the contract (for F): wording of the refusal, and a one-line summary of an answer
CREATE FUNCTION tap._msg247(p_stage text, p_why text) RETURNS text LANGUAGE sql IMMUTABLE AS $f$
  SELECT format(CASE WHEN p_stage = 'approval'
                     THEN 'Refund refused at approval: the seller payout for this order is now released or in flight (%s). '
                     ELSE 'Refund refused: the seller payout for this order is released or in flight (%s). ' END
                || 'Owner decision 2026-10-21: refunds stay manual, and the console never refunds automatically after a released payout. '
                || 'Follow the manual refund SOP (docs/admin-console/MANUAL_REFUND_SOP.md, §2 row 8 and §9) and escalate to the owner. Nothing was refunded.',
                p_why) $f$;
CREATE FUNCTION tap._rec247() RETURNS text LANGUAGE sql STABLE AS $f$
  SELECT 'payout recorded ' || to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI "UTC"') $f$;
CREATE FUNCTION tap._sum247(r jsonb) RETURNS text LANGUAGE sql IMMUTABLE AS $f$
  SELECT concat_ws('|', r ->> 'status', coalesce(r ->> 'reject_reason', '-'), coalesce(r #>> '{result,stage}', '-'),
                   coalesce(r #>> '{result,payout,transfer_status}', '-'), coalesce(r #>> '{result,payout,basis}', '-')) $f$;

SELECT tap._s247('set_on', tap._setting247('k247-set-refund-on', true));
SELECT is(tap._g247('set_on') ->> 'status', 'succeeded', 'S0: setting_set refund_execute_enabled=true succeeds inside the test');

-- ── P1 — refund after a SETTLED console payout_release (order 1; 224 T5.16's shape) ──
SELECT tap._order247(1);
SELECT tap._s247('p1pr', tap._ex247(tap.admin_user(), 'k247-p1-payout-a01', 'payout_release', 'transfer', tap._t247(1)));
SELECT tap._s247('p1ap', tap._ap247(tap.other_user(), tap._id247('p1pr'), 'approve'));
SELECT is((tap._g247('p1pr') ->> 'status', tap._g247('p1ap') ->> 'status', tap._fx247(1)),
          ('awaiting_approval'::text, 'succeeded'::text, 'auto_released/no_attempt/unrecorded/no_tr'::text),
  'P1.1: payout_release parked, approved by founder B => succeeded; the transfer is auto_released (the worker pays it on its next run)');
SELECT tap._s247('p1r', tap._refund247(tap.admin_user(), 'k247-p1-refund-a01', 1));
SELECT is((tap._g247('p1r') ->> 'status', tap._g247('p1r') ->> 'reject_reason'), ('rejected'::text, 'payout_released'::text),
  'P1.2: a refund_execute after the settled payout_release is refused: rejected / payout_released');
SELECT is(tap._g247('p1r') ->> 'message', tap._msg247('request', 'transfer auto_released'),
  'P1.3: message (contract wording: the owner decision and the manual refund SOP)');
SELECT is(tap._g247('p1r') -> 'result',
          jsonb_build_object('status', 'rejected', 'reject_reason', 'payout_released',
                             'message', tap._msg247('request', 'transfer auto_released'), 'stage', 'request',
                             'payout', jsonb_build_object('transfer_id', tap._t247(1), 'transfer_status', 'auto_released',
                                                          'payout_released_at', NULL, 'stripe_transfer_id', NULL,
                                                          'attempt_id', NULL, 'attempt_no', NULL, 'attempt_state', NULL,
                                                          'basis', '["status_auto_released"]'::jsonb)),
  'P1.4: result = the full refusal envelope (status, reject_reason, message, stage, payout evidence)');
SELECT is((SELECT (state, reject_reason, idempotency_key, completed_at IS NOT NULL, approval_id IS NULL, result ->> 'reject_reason', requested_by)
             FROM ops.action WHERE id = tap._id247('p1r')),
          ('rejected'::text, 'payout_released'::text, 'k247-p1-refund-a01'::text, true, true, 'payout_released'::text, tap.admin_user()),
  'P1.5: the action row: rejected / payout_released, key bound, completed, no approval, requested_by founder A');
SELECT is((SELECT count(*)::int FROM ops.approval WHERE action_id = tap._id247('p1r')), 0, 'P1.6: no approval was parked');
SELECT is((SELECT array_agg(action || ':' || outcome ORDER BY action) FROM ops.audit WHERE action_id = tap._id247('p1r')),
          ARRAY['action.refund_execute:rejected', 'action.requested:requested'],
  'P1.7: audited like every precheck rejection (action.requested, action.refund_execute / rejected)');
SELECT is((SELECT after ->> 'reject_reason' FROM ops.audit WHERE action_id = tap._id247('p1r') AND action = 'action.refund_execute'),
          'payout_released', 'P1.8: the rejection audit carries the envelope');
SELECT tap._s247('p1rr', tap._refund247(tap.admin_user(), 'k247-p1-refund-a01', 1));
SELECT is((tap._g247('p1rr') ->> 'status', tap._g247('p1rr') ->> 'state', tap._g247('p1rr') ->> 'action_id', tap._g247('p1rr') #>> '{result,reject_reason}'),
          ('idempotent_replay'::text, 'rejected'::text, tap._g247('p1r') ->> 'action_id', 'payout_released'::text),
  'P1.9: replaying the key returns the same refusal (no new row)');
SELECT is((SELECT (status, coalesce(amount_refunded_cents, 0), stripe_refund_id IS NULL) FROM public.payments WHERE id = tap._p247(1)),
          ('succeeded'::text, 0, true), 'P1.10: nothing refunded: the payment is untouched');

-- ── P2 — every released / in-flight shape, through its production writer ──
-- 2.1 buyer confirmation (confirm_transfer_received; confirm-and-release pays straight away)
SELECT tap._order247(2);
SELECT tap._buyer247('confirm', 2);
SELECT is(tap._fx247(2), 'buyer_confirmed/no_attempt/unrecorded/no_tr', 'P2.1a: fixture: the buyer confirmed (confirm_transfer_received)');
SELECT tap._s247('p2_1', tap._refund247(tap.admin_user(), 'k247-p2-refund-01', 2));
SELECT is(tap._sum247(tap._g247('p2_1')), 'rejected|payout_released|request|buyer_confirmed|["status_buyer_confirmed"]',
  'P2.1b: buyer_confirmed => refused, basis status_buyer_confirmed');
SELECT is(tap._g247('p2_1') ->> 'message', tap._msg247('request', 'transfer buyer_confirmed'), 'P2.1c: message');
-- 2.2 the auto-release cron (apply_auto_release)
SELECT tap._order247(3);
SELECT is(public.apply_auto_release(tap._t247(3)), true, 'P2.2a: fixture: the cron''s apply_auto_release releases transfer 3');
SELECT tap._s247('p2_2', tap._refund247(tap.admin_user(), 'k247-p2-refund-02', 3));
SELECT is(tap._sum247(tap._g247('p2_2')), 'rejected|payout_released|request|auto_released|["status_auto_released"]',
  'P2.2b: auto_released (cron) => refused, basis status_auto_released');
-- 2.3 a payout attempt claimed (claim_payout_attempt)
SELECT tap._order247(4);
SELECT public.apply_auto_release(tap._t247(4));
SELECT is(tap._payout247(4, 'claimed'), 'claimed', 'P2.3a: fixture: the worker claimed payout attempt #1');
SELECT tap._s247('p2_3', tap._refund247(tap.admin_user(), 'k247-p2-refund-03', 4));
SELECT is(tap._sum247(tap._g247('p2_3')), 'rejected|payout_released|request|auto_released|["payout_attempt_claimed", "status_auto_released"]',
  'P2.3b: claimed attempt => refused');
SELECT is((tap._g247('p2_3') ->> 'message', tap._g247('p2_3') #>> '{result,payout,attempt_id}', tap._g247('p2_3') #>> '{result,payout,attempt_no}'),
          (tap._msg247('request', 'transfer auto_released; payout attempt #1 claimed'), tap._attempt247(4)::text, '1'::text),
  'P2.3c: message names the attempt; payout.attempt_id / attempt_no');
-- 2.4 requested (mark_payout_requested: the POST is about to go)
SELECT tap._order247(5);
SELECT public.apply_auto_release(tap._t247(5));
SELECT is(tap._payout247(5, 'requested'), 'requested', 'P2.4a: fixture: attempt #1 marked requested');
SELECT tap._s247('p2_4', tap._refund247(tap.admin_user(), 'k247-p2-refund-04', 5));
SELECT is(tap._sum247(tap._g247('p2_4')), 'rejected|payout_released|request|auto_released|["payout_attempt_requested", "status_auto_released"]',
  'P2.4b: requested attempt => refused');
-- 2.5 unknown (record_payout_attempt_result 'unknown': Stripe may have created the transfer)
SELECT tap._order247(6);
SELECT public.apply_auto_release(tap._t247(6));
SELECT is(tap._payout247(6, 'unknown'), 'unknown', 'P2.5a: fixture: attempt #1 outcome unknown');
SELECT tap._s247('p2_5', tap._refund247(tap.admin_user(), 'k247-p2-refund-05', 6));
SELECT is((tap._sum247(tap._g247('p2_5')), tap._g247('p2_5') ->> 'message'),
          ('rejected|payout_released|request|auto_released|["payout_attempt_unknown", "status_auto_released"]'::text,
           tap._msg247('request', 'transfer auto_released; payout attempt #1 unknown')),
  'P2.5b: unknown attempt => refused (message names it)');
-- 2.6 succeeded (record_payout_attempt_result: payout_released_at + stripe_transfer_id)
SELECT tap._order247(7);
SELECT public.apply_auto_release(tap._t247(7));
SELECT is((tap._payout247(7, 'succeeded'), tap._fx247(7)), ('succeeded'::text, 'auto_released/succeeded/recorded/tr_fixture_247_7'::text),
  'P2.6a: fixture: the payout succeeded and is recorded on the transfer');
SELECT tap._s247('p2_6', tap._refund247(tap.admin_user(), 'k247-p2-refund-06', 7));
SELECT is(tap._sum247(tap._g247('p2_6')),
          'rejected|payout_released|request|auto_released|["payout_released_at", "stripe_transfer_id", "payout_attempt_succeeded", "status_auto_released"]',
  'P2.6b: paid out => refused, every basis listed');
SELECT is((tap._g247('p2_6') ->> 'message', tap._g247('p2_6') #>> '{result,payout,stripe_transfer_id}',
           (tap._g247('p2_6') #>> '{result,payout,payout_released_at}')::timestamptz = now()),
          (tap._msg247('request', 'transfer auto_released; ' || tap._rec247() || '; Stripe transfer tr_fixture_247_7; payout attempt #1 succeeded'),
           'tr_fixture_247_7'::text, true),
  'P2.6c: message and payout evidence (recorded at, Stripe transfer id)');
-- 2.7 reversal_required (PAID_DURING_DISPUTE: claim, a chargeback freezes the transfer, then Stripe reports the transfer)
SELECT tap._order247(8);
SELECT public.apply_auto_release(tap._t247(8));
SELECT tap._payout247(8, 'requested');
SELECT public.freeze_transfer_for_dispute(tap._t247(8));
SELECT public.record_payout_attempt_result(tap._attempt247(8), 'tr_fixture_247_8', 'succeeded', NULL);
SELECT is(tap._fx247(8), 'disputed/reversal_required/recorded/tr_fixture_247_8', 'P2.7a: fixture: paid during a dispute => attempt reversal_required, transfer disputed');
SELECT tap._s247('p2_7', tap._refund247(tap.admin_user(), 'k247-p2-refund-07', 8));
SELECT is(tap._sum247(tap._g247('p2_7')),
          'rejected|payout_released|request|disputed|["payout_released_at", "stripe_transfer_id", "payout_attempt_reversal_required"]',
  'P2.7b: reversal_required on a disputed transfer => refused (money moved)');
-- 2.8 reversed (mark_transfer_reversed: any reversal, partial or full)
SELECT tap._order247(9);
SELECT public.apply_auto_release(tap._t247(9));
SELECT tap._payout247(9, 'succeeded');
SELECT is(public.mark_transfer_reversed('tr_fixture_247_9'), true, 'P2.8a: fixture: the transfer.reversed webhook marks transfer 9 reversed');
SELECT tap._s247('p2_8', tap._refund247(tap.admin_user(), 'k247-p2-refund-08', 9));
SELECT is(tap._sum247(tap._g247('p2_8')),
          'rejected|payout_released|request|reversed|["payout_released_at", "stripe_transfer_id", "payout_attempt_succeeded", "status_reversed"]',
  'P2.8b: reversed => refused (a reversal may be partial: the owner decides, SOP §9)');
-- 2.9 the legacy writer record_transfer_payout on a seller_sent transfer: the money-moved columns alone
SELECT tap._order247(10);
SELECT is((public.record_transfer_payout(tap._t247(10), 'tr_fixture_247_10'), tap._fx247(10)),
          (true, 'seller_sent/no_attempt/recorded/tr_fixture_247_10'::text),
  'P2.9a: fixture: record_transfer_payout records a payout on a seller_sent transfer (no attempt row)');
SELECT tap._s247('p2_9', tap._refund247(tap.admin_user(), 'k247-p2-refund-09', 10));
SELECT is((tap._sum247(tap._g247('p2_9')), tap._g247('p2_9') ->> 'message'),
          ('rejected|payout_released|request|seller_sent|["payout_released_at", "stripe_transfer_id"]'::text,
           tap._msg247('request', 'transfer seller_sent; ' || tap._rec247() || '; Stripe transfer tr_fixture_247_10')),
  'P2.9b: payout_released_at / stripe_transfer_id alone => refused, whatever the status');
-- 2.10 an open attempt on a transfer frozen for a dispute: the attempt alone (claim reconciles it whatever the status)
SELECT tap._order247(11);
SELECT public.apply_auto_release(tap._t247(11));
SELECT tap._payout247(11, 'claimed');
SELECT is((public.freeze_transfer_for_dispute(tap._t247(11)), tap._fx247(11)), (true, 'disputed/claimed/unrecorded/no_tr'::text),
  'P2.10a: fixture: a chargeback freezes transfer 11 while attempt #1 is open');
SELECT tap._s247('p2_10', tap._refund247(tap.admin_user(), 'k247-p2-refund-10', 11));
SELECT is((tap._sum247(tap._g247('p2_10')), tap._g247('p2_10') ->> 'message'),
          ('rejected|payout_released|request|disputed|["payout_attempt_claimed"]'::text,
           tap._msg247('request', 'transfer disputed; payout attempt #1 claimed')),
  'P2.10b: an open attempt alone => refused (in flight)');

-- ── P3 — neither released nor in flight: still accepted ──
SELECT tap._order247(12);
SELECT is(tap._refund247(tap.admin_user(), 'k247-p3-refund-12', 12) ->> 'status', 'awaiting_approval', 'P3.1: seller_sent => accepted (parks)');
SELECT tap._order247(13, 'pending');
SELECT is(tap._refund247(tap.admin_user(), 'k247-p3-refund-13', 13) ->> 'status', 'awaiting_approval', 'P3.2: pending (seller never sent) => accepted');
SELECT tap._order247(14, 'expired');
SELECT is(tap._refund247(tap.admin_user(), 'k247-p3-refund-14', 14) ->> 'status', 'awaiting_approval', 'P3.3: expired => accepted');
SELECT tap._order247(15);
SELECT tap._buyer247('dispute', 15);
SELECT tap._s247('p3_bw', tap._ex247(tap.admin_user(), 'k247-p3-resolve-15', 'dispute_resolve', 'transfer', tap._t247(15), '{"outcome": "buyer_win"}'::jsonb));
SELECT is((tap._g247('p3_bw') ->> 'status', tap._fx247(15), (SELECT dispute_resolution FROM public.transfers WHERE id = tap._t247(15))),
          ('succeeded'::text, 'disputed/no_attempt/unrecorded/no_tr'::text, 'resolved_buyer_refunded'::text),
  'P3.4a: fixture: the buyer disputed, dispute_resolve buyer_win (refund_required)');
SELECT is(tap._refund247(tap.admin_user(), 'k247-p3-refund-15', 15) ->> 'status', 'awaiting_approval', 'P3.4b: buyer-win dispute => the follow-up refund is accepted');
SELECT tap._order247(16);
SELECT public.apply_auto_release(tap._t247(16));
SELECT tap._payout247(16, 'failed');
SELECT is((public.freeze_transfer_for_dispute(tap._t247(16)), tap._fx247(16)), (true, 'disputed/failed/unrecorded/no_tr'::text),
  'P3.5a: fixture: attempt #1 failed (no transfer created), then a chargeback froze the transfer (it can no longer be claimed)');
SELECT is(tap._refund247(tap.admin_user(), 'k247-p3-refund-16', 16) ->> 'status', 'awaiting_approval', 'P3.5b: a FAILED attempt is not in flight => accepted');
SELECT tap._order247(17, 'seller_sent', false);
SELECT is(tap._refund247(tap.admin_user(), 'k247-p3-refund-17', 17) ->> 'status', 'awaiting_approval', 'P3.6: a payment with no transfer row => accepted');

-- ── P4 — dispute_resolve seller_win releases the payout (order 18) ──
SELECT tap._order247(18);
SELECT tap._buyer247('dispute', 18);
SELECT tap._s247('p4r1', tap._refund247(tap.admin_user(), 'k247-p4-refund-a01', 18));
SELECT is((tap._fx247(18), tap._g247('p4r1') ->> 'status'), ('disputed/no_attempt/unrecorded/no_tr'::text, 'awaiting_approval'::text),
  'P4.1: the buyer disputes; a refund requested during the open dispute parks');
SELECT tap._s247('p4sw', tap._ex247(tap.admin_user(), 'k247-p4-resolve-18', 'dispute_resolve', 'transfer', tap._t247(18), '{"outcome": "seller_win"}'::jsonb));
SELECT is((tap._g247('p4sw') ->> 'status', tap._fx247(18), (SELECT (dispute_resolution, disputed_at IS NULL)::text FROM public.transfers WHERE id = tap._t247(18))),
          ('succeeded'::text, 'buyer_confirmed/no_attempt/unrecorded/no_tr'::text, '(resolved_seller_paid,t)'::text),
  'P4.2: dispute_resolve seller_win releases the payout (buyer_confirmed, resolved_seller_paid, unfrozen)');
SELECT tap._s247('p4ap', tap._ap247(tap.other_user(), tap._id247('p4r1'), 'approve'));
SELECT is(tap._sum247(tap._g247('p4ap')), 'rejected|payout_released|approval|buyer_confirmed|["status_buyer_confirmed"]',
  'P4.3: approving the refund parked during the dispute is refused at approval');
SELECT is(tap._g247('p4ap') ->> 'message', tap._msg247('approval', 'transfer buyer_confirmed'), 'P4.4: approval-stage message');
SELECT is((SELECT (state, reject_reason, completed_at IS NOT NULL, result ->> 'stage') FROM ops.action WHERE id = tap._id247('p4r1')),
          ('rejected'::text, 'payout_released'::text, true, 'approval'::text), 'P4.5: the parked action ends rejected / payout_released (stage approval)');
SELECT is(tap._sum247(tap._refund247(tap.other_user(), 'k247-p4-refund-b02', 18)),
          'rejected|payout_released|request|buyer_confirmed|["status_buyer_confirmed"]', 'P4.6: a new refund after the seller win is refused at request');

-- ── P5 — TOCTOU: released between the request and the approval ──
-- order 19: the auto-release cron runs while the refund waits for approval
SELECT tap._order247(19);
SELECT tap._s247('p5r', tap._refund247(tap.admin_user(), 'k247-p5-refund-a01', 19));
SELECT is(tap._g247('p5r') ->> 'status', 'awaiting_approval', 'P5.1: refund parked while transfer 19 is seller_sent');
SELECT is(public.apply_auto_release(tap._t247(19)), true, 'P5.2: then the cron auto-releases transfer 19');
SELECT tap._s247('p5ap', tap._ap247(tap.other_user(), tap._id247('p5r'), 'approve'));
SELECT is(tap._sum247(tap._g247('p5ap')), 'rejected|payout_released|approval|auto_released|["status_auto_released"]',
  'P5.3: founder B approves => refused at approval (dispatch re-check), not processing');
SELECT is(tap._g247('p5ap') ->> 'message', tap._msg247('approval', 'transfer auto_released'), 'P5.4: approval-stage message');
SELECT is((SELECT (a.state, a.reject_reason, a.completed_at IS NOT NULL, ap.state) FROM ops.action a JOIN ops.approval ap ON ap.id = a.approval_id
            WHERE a.id = tap._id247('p5r')),
          ('rejected'::text, 'payout_released'::text, true, 'approved'::text), 'P5.5: the action ends rejected / payout_released; its approval is consumed (approved)');
SELECT is(tap._claim247(tap._id247('p5r')), '{"status": "refused", "reason": "terminal", "state": "rejected"}'::jsonb,
  'P5.6: ops-refund-execute''s executor_claim refuses it (terminal): no money can move');
SELECT is((SELECT count(*)::int FROM ops.audit WHERE action_id = tap._id247('p5r') AND action = 'action.refund_execute' AND outcome = 'processing')
          + (SELECT count(*)::int FROM public.payments WHERE id = tap._p247(19) AND status <> 'succeeded'), 0,
  'P5.7: never processing, never handed off; the payment is still succeeded');
-- order 20: the buyer confirms and the payout is recorded (confirm-and-release) while the refund waits
SELECT tap._order247(20);
SELECT tap._s247('p5r2', tap._refund247(tap.admin_user(), 'k247-p5-refund-a02', 20));
SELECT tap._buyer247('confirm', 20);
SELECT is((tap._g247('p5r2') ->> 'status', tap._payout247(20, 'succeeded'), tap._fx247(20)),
          ('awaiting_approval'::text, 'succeeded'::text, 'buyer_confirmed/succeeded/recorded/tr_fixture_247_20'::text),
  'P5.8: refund parked; then the buyer confirms and the payout is paid and recorded');
SELECT tap._s247('p5ap2', tap._ap247(tap.other_user(), tap._id247('p5r2'), 'approve'));
SELECT is(tap._sum247(tap._g247('p5ap2')),
          'rejected|payout_released|approval|buyer_confirmed|["payout_released_at", "stripe_transfer_id", "payout_attempt_succeeded", "status_buyer_confirmed"]',
  'P5.9: approving it is refused at approval with the full basis');
SELECT is(tap._g247('p5ap2') ->> 'message',
          tap._msg247('approval', 'transfer buyer_confirmed; ' || tap._rec247() || '; Stripe transfer tr_fixture_247_20; payout attempt #1 succeeded'),
  'P5.10: approval-stage message names the recorded payout');

-- ── P6 — the refund dispatch locks the transfer row (order 21) ──
SELECT tap._order247(21);
SELECT tap._s247('p6r', tap._refund247(tap.admin_user(), 'k247-p6-refund-a01', 21));
SELECT tap._s247('p6x0', (SELECT jsonb_build_object('xmin', xmin::text, 'xmax', xmax::text) FROM public.transfers WHERE id = tap._t247(21)));
SELECT is((tap._g247('p6r') ->> 'status', tap._g247('p6x0') ->> 'xmax'), ('awaiting_approval'::text, '0'::text),
  'P6.1: refund parked; the transfer row is not locked yet (xmax 0)');
SELECT tap._s247('p6ap', tap._ap247(tap.other_user(), tap._id247('p6r'), 'approve'));
SELECT is(tap._g247('p6ap') -> 'result',
          jsonb_build_object('status', 'processing', 'handoff', 'ops-refund-execute', 'stripe_payment_intent_id', 'pi_fixture_247_21',
                             'amount_cents', 11000, 'currency', 'usd'),
  'P6.2: not released => the approval hands off exactly as before (processing, ops-refund-execute)');
SELECT is((SELECT (xmin::text = tap._g247('p6x0') ->> 'xmin', xmax::text <> '0', status) FROM public.transfers WHERE id = tap._t247(21)),
          (true, true, 'seller_sent'::text),
  'P6.3: the dispatch locked the transfer row (xmax set) without updating it (xmin unchanged)');
SELECT is((SELECT CASE WHEN lk = 0 THEN 'no locked transfer read' WHEN rd = 0 THEN 'no payout read' WHEN pr = 0 THEN 'no handoff'
                       WHEN lk < rd AND rd < pr THEN 'transfer locked, then payout read, then handoff' ELSE 'wrong order' END
             FROM (SELECT position('from public.transfers t where t.payment_id = a.subject_id for update' IN b) AS lk,
                          position('ops.refund_payout_refusal(' IN b) AS rd,
                          position('''handoff'',''ops-refund-execute''' IN b) AS pr
                     FROM (SELECT substring(d FROM 'when ''refund_execute'' then(.*?)when ''job_retry'' then') AS b
                             FROM (SELECT regexp_replace(regexp_replace(lower(pg_get_functiondef('ops.action_dispatch(ops.action)'::regprocedure)),
                                                                        '--[^\n]*', '', 'g'), '\s+', ' ', 'g') AS d) x) y) z),
          'transfer locked, then payout read, then handoff',
  'P6.4: static (comments stripped): the refund_execute branch locks the transfer FOR UPDATE before it reads the payout state');
-- P6.5 (review B1): P6.1-P6.4 and the two-session rehearsal cannot tell a waiting FOR UPDATE from FOR UPDATE SKIP LOCKED
-- (the lock text is still present; the row is still locked when it is free), and SKIP LOCKED reopens the TOCTOU 177 closes
-- (the approval reads the committed seller_sent row while the release is uncommitted). Pin the statement's exact tail.
SELECT is((SELECT position('from public.transfers t where t.payment_id = a.subject_id for update;' IN b) > 0
                  AND position('skip locked' IN b) = 0 AND position('nowait' IN b) = 0
             FROM (SELECT substring(d FROM 'when ''refund_execute'' then(.*?)when ''job_retry'' then') AS b
                     FROM (SELECT regexp_replace(regexp_replace(lower(pg_get_functiondef('ops.action_dispatch(ops.action)'::regprocedure)),
                                                                '--[^\n]*', '', 'g'), '\s+', ' ', 'g') AS d) x) z),
          true,
  'P6.5: static: the transfer lock is a plain FOR UPDATE that waits (the statement ends in "for update;", no SKIP LOCKED / NOWAIT)');

-- ── P7 — 157 interplay, both orders ──
-- order 22: payout_release first
SELECT tap._order247(22);
SELECT tap._s247('p7pr', tap._ex247(tap.admin_user(), 'k247-p7-payout-a01', 'payout_release', 'transfer', tap._t247(22)));
SELECT is(tap._g247('p7pr') ->> 'status', 'awaiting_approval', 'P7.1: payout_release on transfer 22 parks (unsettled)');
SELECT is(tap._sum247(tap._refund247(tap.other_user(), 'k247-p7-refund-b01', 22)), 'rejected|duplicate_unsettled|-|-|-',
  'P7.2: a refund while the payout_release is UNSETTLED: 157 answers (duplicate_unsettled), 177 is not reached');
SELECT is(tap._ap247(tap.other_user(), tap._id247('p7pr'), 'approve') ->> 'status', 'succeeded', 'P7.3: founder B approves the payout_release (settled)');
SELECT is(tap._sum247(tap._refund247(tap.other_user(), 'k247-p7-refund-b02', 22)),
          'rejected|payout_released|request|auto_released|["status_auto_released"]', 'P7.4: once SETTLED, a refund is payout_released (177)');
-- order 23: refund first
SELECT tap._order247(23);
SELECT tap._s247('p7r', tap._refund247(tap.admin_user(), 'k247-p7-refund-a03', 23));
SELECT is(tap._g247('p7r') ->> 'status', 'awaiting_approval', 'P7.5: refund on payment 23 parks');
SELECT is(tap._sum247(tap._ex247(tap.other_user(), 'k247-p7-payout-b02', 'payout_release', 'transfer', tap._t247(23))), 'rejected|duplicate_unsettled|-|-|-',
  'P7.6: a payout_release while the refund is unsettled: 157 refuses it (cross_type)');
SELECT is(tap._ap247(tap.other_user(), tap._id247('p7r'), 'deny') ->> 'reject_reason', 'denied', 'P7.7: founder B denies the refund');
SELECT tap._s247('p7pr2', tap._ex247(tap.admin_user(), 'k247-p7-payout-a03', 'payout_release', 'transfer', tap._t247(23)));
SELECT is((tap._g247('p7pr2') ->> 'status', tap._ap247(tap.other_user(), tap._id247('p7pr2'), 'approve') ->> 'status', tap._fx247(23)),
          ('awaiting_approval'::text, 'succeeded'::text, 'auto_released/no_attempt/unrecorded/no_tr'::text),
  'P7.8: then a payout_release parks and is approved (settled, auto_released)');
SELECT is(tap._sum247(tap._refund247(tap.admin_user(), 'k247-p7-refund-a04', 23)),
          'rejected|payout_released|request|auto_released|["status_auto_released"]', 'P7.9: a new refund is payout_released');

-- ── P8 — every existing answer first, byte for byte (released orders 24-27; order 28 at approval) ──
SELECT tap._order247(24); SELECT public.apply_auto_release(tap._t247(24));
SELECT tap._order247(25); SELECT public.apply_auto_release(tap._t247(25));
SELECT tap._order247(26); SELECT public.apply_auto_release(tap._t247(26));
SELECT tap._order247(27); SELECT public.apply_auto_release(tap._t247(27));
SELECT tap._order247(28);
SELECT tap._s247('p8r28', tap._refund247(tap.admin_user(), 'k247-p8-refund-28', 28));
SELECT public.apply_auto_release(tap._t247(28));
SELECT tap._s247('p8off', tap._setting247('k247-p8-set-off', false));
SELECT tap._s247('p8r24', tap._refund247(tap.admin_user(), 'k247-p8-refund-24', 24));
SELECT tap._s247('p8ap28', tap._ap247(tap.other_user(), tap._id247('p8r28'), 'approve'));
SELECT tap._s247('p8on', tap._setting247('k247-p8-set-on', true));
SELECT is((tap._g247('p8off') ->> 'status', tap._g247('p8on') ->> 'status', tap._g247('p8r28') ->> 'status'),
          ('succeeded'::text, 'succeeded'::text, 'awaiting_approval'::text), 'P8.1: fixture: setting switched off and on again; refund 28 parked before its release');
SELECT is((tap._g247('p8r24') ->> 'reject_reason', tap._g247('p8r24') ->> 'message'),
          ('disabled'::text, 'refund execution is disabled until the ops-refund-execute function is deployed (see runbook); use the Stripe Dashboard SOP'::text),
  'P8.2: switch off + released order => the existing disabled answer, byte for byte');
SELECT is((tap._g247('p8ap28') ->> 'reject_reason', tap._g247('p8ap28') ->> 'message'),
          ('disabled'::text, 'refund execution is disabled until the ops-refund-execute function is deployed (see runbook); use the Stripe Dashboard SOP'::text),
  'P8.3: at approval too: switch off + released => the dispatch''s existing disabled answer first');
SELECT is(public.record_payment_refund('pi_fixture_247_25', 're_fixture_247_25', NULL, NULL, 'dashboard') ->> 'status', 'refunded',
  'P8.4: fixture: payment 25 refunded in the Dashboard (record_payment_refund)');
SELECT is((SELECT (r ->> 'reject_reason', r ->> 'message') FROM (SELECT tap._refund247(tap.admin_user(), 'k247-p8-refund-25', 25) AS r) x),
          ('stale_state'::text, 'payment is refunded; only a succeeded payment can be refunded'::text),
  'P8.5: refunded payment + released order => the existing stale_state answer, byte for byte');
SELECT is((SELECT (r ->> 'reject_reason', r ->> 'message') FROM (SELECT tap._refund247(tap.admin_user(), 'k247-p8-refund-26', 26, '{"amount_cents": 5000}'::jsonb) AS r) x),
          ('not_supported'::text, 'partial refunds are not supported in this release: the local money model records refund status only (no refunded amount), so a partial refund would be reported as a full one. Request a full refund or use the Stripe Dashboard SOP.'::text),
  'P8.6: partial amount + released order => the existing not_supported answer, byte for byte');
SELECT is((SELECT (r ->> 'reject_reason', r ->> 'message') FROM (SELECT tap._refund247(tap.admin_user(), 'k247-p8-refund-27', 27, '{"amount_cents": 0}'::jsonb) AS r) x),
          ('precondition'::text, 'amount must be between 1 and the payment total'::text),
  'P8.7: out-of-range amount + released order => the existing precondition answer, byte for byte');
SELECT is(tap._sum247(tap._refund247(tap.admin_user(), 'k247-p8-refund-27b', 27, '{"amount_cents": 11000}'::jsonb)),
          'rejected|payout_released|request|auto_released|["status_auto_released"]', 'P8.8: a full amount stated explicitly reaches the payout check');

-- ── P9 — catalog ──
SELECT is((SELECT coalesce(array_to_string(p.proacl, ','), '<default>') || ':' || p.prosecdef || ':'
                   || coalesce(array_to_string(p.proconfig, ','), '') || ':' || p.provolatile::text
             FROM pg_proc p WHERE p.oid = to_regprocedure('ops.refund_payout_refusal(uuid,text)')),
          'postgres=X/postgres:true:search_path="":s',
  'P9.1: ops.refund_payout_refusal is internal: ACL postgres only, SECURITY DEFINER, search_path '''', STABLE');
SELECT ok(NOT has_function_privilege('anon', to_regprocedure('ops.refund_payout_refusal(uuid,text)'), 'EXECUTE'), 'P9.2: anon may not execute it');
SELECT ok(NOT has_function_privilege('authenticated', to_regprocedure('ops.refund_payout_refusal(uuid,text)'), 'EXECUTE'), 'P9.3: authenticated may not execute it');
SELECT is((SELECT array_agg(p.proname::text || ':' || coalesce(array_to_string(p.proacl, ','), '<default>') || ':' || p.prosecdef || ':'
                            || coalesce(array_to_string(p.proconfig, ','), '') || ':' || p.provolatile::text ORDER BY p.proname)
             FROM pg_proc p WHERE p.oid IN ('ops.action_precheck(ops.action)'::regprocedure, 'ops.action_dispatch(ops.action)'::regprocedure)),
          ARRAY['action_dispatch:postgres=X/postgres:true:search_path="":v', 'action_precheck:postgres=X/postgres:true:search_path="":s'],
  'P9.4: action_precheck / action_dispatch keep ACL (postgres only), SECURITY DEFINER, search_path '''' and volatility');
SELECT is((SELECT md5(substr(d, 1, s - 1) || substr(d, e + length('    -- 177 end') + 1))
             FROM (SELECT d, position('    -- 177 begin' IN d) AS s, position('    -- 177 end' IN d) AS e
                     FROM (SELECT pg_get_functiondef('ops.action_precheck(ops.action)'::regprocedure) AS d) x) y
            WHERE s > 0 AND e > s),
          'fbc3d08eae4de831ab3f085e170e8f10',
  'P9.5: action_precheck without the marked 177 block is production''s body byte for byte (md5 fbc3d08e)');
SELECT is((SELECT md5(substr(d, 1, s - 1) || substr(d, e + length('    -- 177 end') + 1))
             FROM (SELECT d, position('    -- 177 begin' IN d) AS s, position('    -- 177 end' IN d) AS e
                     FROM (SELECT pg_get_functiondef('ops.action_dispatch(ops.action)'::regprocedure) AS d) x) y
            WHERE s > 0 AND e > s),
          '7f507fc880c02617c53d1e4f679c608c',
  'P9.6: action_dispatch without the marked 177 block is 158''s body byte for byte (md5 7f507fc8): no other branch changed');
SELECT is((SELECT count(*)::int FROM (VALUES
             ('ops.action_precheck(ops.action)', 'fbc3d08eae4de831ab3f085e170e8f10'),
             ('ops.action_dispatch(ops.action)', '7f507fc880c02617c53d1e4f679c608c'),
             ('ops.action_dispatch(ops.action)', 'bfb8b9dcfaace5ff04009f96b6de7bef')) v(sig, old_md5)
            WHERE md5(pg_get_functiondef(v.sig::regprocedure)) <> v.old_md5), 3,
  'P9.7: both redefined bodies are live (neither the predecessor''s nor production''s md5)');
-- A signature may list more than one accepted md5: production's, and (for two writers) the clean repo chain's own
-- definer, which differs from production by comments only (BE-37 F-rows; CI builds the chain, A's replay is production).
-- A signature counts as changed only when its live md5 matches NONE of its listed values.
SELECT is((SELECT coalesce(array_agg(z.sig ORDER BY z.sig), '{}'::text[]) FROM (SELECT v.sig FROM (VALUES
             -- 158 / 157 bodies this file stacks on (unchanged by it)
             ('ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)', '24209d0697132d5df7bd12f5cf3e5c0c'),
             ('ops.approve_action(uuid,text,text)', 'ddcdcd1401839910726d20ddd206e40d'),
             ('ops.order_detail(uuid)', '4358f577291f84b25986b8904b38ab36'),
             -- production: the action pipeline around the two bodies, and the refund executor's functions
             ('ops.action_run(uuid)', '546693f1489c364de19e9416a92c07ed'),
             ('ops.action_requires_approval(text)', '44ab739b9db2c77ef8709fed6c1d5082'),
             ('ops.action_allowed_roles(text)', '972443bf571dc94ef1e1400602b28315'),
             ('ops.action_hash(text,text,uuid,text,jsonb)', 'ad280c19761b428d644281f6e336a7c5'),
             ('ops.executor_claim(uuid,integer)', '1cfa0290546ff36fe07389a9d13b7f9e'),
             ('ops.record_action_outcome(uuid,text,jsonb,text,text)', 'c4fb902ec1f0d0166955993b4cfe96df'),
             ('ops.detect_refunds()', '6a4727f4f39ced0a6078ac639b38de16'),
             ('ops.funds_state(transfers,payments)', 'b73cae88e18c3fc62b1fcfce70722301'),
             -- production: every payout / transfer writer this file reads the result of
             ('public.claim_payout_attempt(uuid,text,interval)', 'b6aae8680e1891892dd0d42f62b9531b'),
             ('public.mark_payout_requested(uuid)', '4c6b3cf979f54450d21decd453c47017'),
             ('public.record_payout_attempt_result(uuid,text,text,jsonb)', '255e9022cd3ef39a20835ae18cc4196e'),
             ('public.reconcile_payout_attempt(uuid,text)', '3d9f95f1d697a4932dfb942c68af12d5'),
             ('public.record_transfer_payout(uuid,text)', '30622f9196dfae1ccec6e503492f8e03'),
             ('public.record_transfer_payout(uuid,text)', '464d2299d60c9ad8394ea89fc8e16df5'),   -- chain (BE-37, comments only)
             ('public.admin_release_held_payout(uuid,uuid,text)', '41b3487b3a6c30f5ba80739d1d523406'),
             ('public.apply_auto_release(uuid)', '989e89ddc5d48f80f0bc844c88f8500d'),
             ('public.flag_payout_reversal_required(uuid,text,jsonb)', '0d692f3262b234fed9c492a8204b5d01'),
             ('public.mark_transfer_reversed(text)', 'd7650290139e377646cfcbd7094d2376'),
             ('public.freeze_transfer_for_dispute(uuid)', 'ae88b2ed854811a0d4462acd4050aa9e'),
             ('public.resolve_transfer_dispute(uuid,text,uuid,text,text)', '7d18f1d80991e78d1dfea9e8ad7bb209'),
             ('public.resolve_transfer_dispute(uuid,text,uuid,text,text)', '7b9e17a54ec065195a7969d8b107d61d'),   -- chain (BE-37, comments only)
             ('public.confirm_transfer_received(uuid,uuid)', 'a009719657758db9d117d91108b09cbd'),
             ('public.confirm_transfer_received(uuid,uuid)', '2628bda3533c447295ae153e3e276f9a'),   -- 171 (20261021131000) redefines it from production's body
             ('public.buyer_dispute_transfer(uuid,uuid,text,text,text)', 'ea1aa60569a74bc13f4bf62fb1d898c9'),
             ('public.record_payment_refund(text,text,text,integer,text)', '8ce828e3461f97844faa36450241dc8f')),
             ('public.record_payment_refund(text,text,text,integer,text)', 'aadd3cca365aae33b1903daaf9ff67d7'   -- 175 (20261021135000) redefines it from production's body) v(sig, md5)
            GROUP BY v.sig
            HAVING bool_and(md5(pg_get_functiondef(to_regprocedure(v.sig))) IS DISTINCT FROM v.md5)) z),
          '{}'::text[],
  'P9.8: unchanged: 158''s execute_action, 157''s approve_action / order_detail, the production action pipeline, executor and every payout writer (production md5, or the chain''s for the two BE-37 comment-drifted writers)');
SELECT is((SELECT count(*)::int FROM pg_proc WHERE pronamespace = 'ops'::regnamespace AND proname = 'refund_payout_refusal'), 1,
  'P9.9: exactly one ops.refund_payout_refusal (no overload)');

SELECT * FROM finish();
ROLLBACK;

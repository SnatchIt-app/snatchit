-- ============================================================================
-- 224_ops_money_action_unsettled_guard.sql — migration 20261021100000 (registry 157):
-- one unsettled refund_execute / payout_release per order.
--
--   T1  same-type refund duplicate: the second request (another founder, a new key) is refused
--       up front as a 'rejected' row (reject_reason duplicate_unsettled) naming the first as
--       blocking.action_id; no second approval; audited; the order advisory lock is taken.
--   T2  the same for payout_release on a transfer; the request locks the ORDER (its payment id), not the transfer
--       id, so a refund on P and a payout on P's transfer serialize on one key.
--   T3  replaying the refused key returns idempotent_replay, state rejected, the same action id.
--   T4  cross-type, both directions: refund on payment P vs payout_release on P's transfer.
--   T5  in-flight states block (processing, unknown, succeeded_at_provider); once the blocker is
--       terminal (failed, succeeded, rejected/denied) a new request is accepted. A refund after a
--       SETTLED payout is not blocked by 157's guard (no duplicate_unsettled); 177 (20261022001000, stacked on 158)
--       refuses it as payout_released, so T5.16 asserts 157's answer without 177 and 177's with it.
--   T6  expired approvals: a new request on the order sweeps them exactly as ops.approve_action
--       expires one (cross-type and same-type), and is accepted; other orders are not swept; the
--       swept row equals an approve_action-expired row field by field, and its approval.expired audit
--       names the action's own subject (the transfer, not the order's payment); the boundary
--       expires_at = now() is swept (<=).
--   T7  the backstop index: a direct second unsettled same-subject INSERT raises 23505 naming
--       action_money_unsettled_uidx; execute_action maps an index collision to duplicate_unsettled
--       (never idempotent_replay with a NULL action_id). The collision path is reached through a
--       subject that resolves to no order (no transfers row), where the order lock does not apply.
--   T8  approve-time recheck on a legacy cross pair (rows written directly, as before 157):
--       approving #1 hands off (processing); approving #2 is refused duplicate_unsettled with NO
--       state change (approval stays pending); once #1 is terminal, #2 approves normally;
--       approve_action took the order advisory lock. Orders 9 and 10: #1 is moved to unknown /
--       succeeded_at_provider by the executor; approving #2 is refused (blocking.state = that state, the
--       message stamps #1's requested_at, a day old), #2 stays awaiting with its approval pending, the
--       transfer is NOT released; a deny is never blocked; order_detail.unsettled_money_actions lists the
--       in-flight refund next to the awaiting payout.
--   T9  non-money action types are unchanged: no lock, no guard, same result shape, replays. T9.6's listing_relist
--       sends the listing's own updated_at as expected (158, 20261021110000, refuses a relist without it), so T9.6
--       asserts the same on 157 alone and on 157 + 158.
--   T10 ops.order_detail.unsettled_money_actions is uncapped: a blocker 56 deep (55 newer
--       terminal actions on the order's listing) is listed with its approval; 'actions' is still
--       the production 50-row list, byte for byte; a refusal's message stamps the blocker's
--       requested_at (2 days old), not now(); approval_expired is shown, a read sweeps nothing.
--   T11 ACLs: the three helpers are postgres-only like ops.action_precheck; execute_action,
--       approve_action and order_detail keep the production ACL; definer + search_path ''.
--   T12 catalog: every other ops function keeps its production md5 (prod_functions.json,
--       2026-10-21). build_daily_summary, money_overview and refresh_metrics exist in production
--       with different bodies than the repo chain (126 refund metrics): each must carry its
--       production md5 or its chain md5 (replay/fp_chain/functions.json), nothing else.
--       refund_facts is the one ops function production lacks (chain only) and the only exclusion.
--       action_dispatch: production's md5 or 158's (158 is stacked on 157 and replaces only its listing_relist branch)
--       or 177's (stacked on 158: its refund_execute branch); action_precheck: production's or 177's.
--       The three redefined bodies are live; the index definition is exact. T12.4 pins approve_action's LOCK
--       ORDER statically (no single-session test can observe it): in its live definition, comments stripped, the
--       first pg_advisory_xact_lock comes before the first FOR UPDATE (an approve_action that locks the row first
--       could deadlock against execute_action's sweep).
--
-- Fixtures: ten orders (listing + succeeded payment + seller_sent transfer) under fixed ids
-- aaaaaaaa/bbbbbbbb/cccccccc-0224-...; founders A = tap.admin_user() (seed_core), B =
-- tap.other_user() (admin_users below), both platform_admin with aal2 claims via tap.login.
-- refund_execute_enabled is switched on INSIDE this transaction (setting_set, founder A).
-- Direct ops.action INSERTs (T7, T8, T10) run as postgres and stand for rows written before 157
-- or by a writer that bypasses execute_action; every other row comes from the RPCs.
-- ============================================================================
BEGIN;
SELECT plan(141);
SELECT tap.seed_core();

INSERT INTO public.admin_users (user_id, label) VALUES (tap.other_user(), 'FOUNDER B') ON CONFLICT (user_id) DO NOTHING;

CREATE TABLE tap.memo_224 (k text PRIMARY KEY, v jsonb);
CREATE FUNCTION tap._s224(k text, v jsonb) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_224 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v $m$;
CREATE FUNCTION tap._g224(k text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_224 WHERE k = $1 $m$;
CREATE FUNCTION tap._id224(k text) RETURNS uuid
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT (v ->> 'action_id')::uuid FROM tap.memo_224 WHERE k = $1 $m$;
CREATE FUNCTION tap._aal2() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;

-- fixture ids
CREATE FUNCTION tap._l224(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT ('aaaaaaaa-0224-0000-0000-' || lpad(n::text, 12, '0'))::uuid $f$;
CREATE FUNCTION tap._p224(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT ('bbbbbbbb-0224-0000-0000-' || lpad(n::text, 12, '0'))::uuid $f$;
CREATE FUNCTION tap._t224(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT ('cccccccc-0224-0000-0000-' || lpad(n::text, 12, '0'))::uuid $f$;
-- a transfer-shaped id that has NO transfers row (T7's unresolvable subject)
CREATE FUNCTION tap._orphan224() RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT 'cccccccc-0224-0000-0000-0000000000ff'::uuid $f$;

-- persona wrappers (the 184 pattern): each call logs in, runs one RPC, logs out
CREATE FUNCTION tap._ex224(p_who uuid, p_key text, p_type text, p_kind text, p_subject uuid,
                           p_params jsonb DEFAULT '{}'::jsonb, p_ref text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql AS $f$
declare v jsonb;
begin
  perform tap.login(p_who); perform tap._aal2();
  v := ops.execute_action(p_key, p_type, p_kind, p_subject, p_params, 'pgTAP 224 ' || p_type, NULL, p_ref);
  perform tap.logout();
  return v;
end $f$;
CREATE FUNCTION tap._ap224(p_who uuid, p_action uuid, p_decision text) RETURNS jsonb
LANGUAGE plpgsql AS $f$
declare v jsonb;
begin
  perform tap.login(p_who); perform tap._aal2();
  v := ops.approve_action(p_action, p_decision, 'pgTAP 224 ' || p_decision);
  perform tap.logout();
  return v;
end $f$;
CREATE FUNCTION tap._out224(p_action uuid, p_state text, p_ref text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql AS $f$
declare v jsonb;
begin
  perform tap.login_service();
  v := ops.record_action_outcome(p_action, p_state,
         case when p_ref is null then NULL else jsonb_build_object('stripe_refund_id', p_ref) end,
         case when p_state in ('failed','unknown') then 'pgTAP 224 ' || p_state end, p_ref);
  perform tap.logout();
  return v;
end $f$;
CREATE FUNCTION tap._od224(p_payment uuid) RETURNS jsonb
LANGUAGE plpgsql AS $f$
declare v jsonb;
begin
  perform tap.login(tap.admin_user()); perform tap._aal2();
  v := ops.order_detail(p_payment);
  perform tap.logout();
  return v;
end $f$;
-- advisory locks this backend holds for one order key (the 157 lock key)
CREATE FUNCTION tap._orderlock224(p_order uuid) RETURNS int LANGUAGE sql AS $f$
  SELECT count(*)::int FROM pg_locks
   WHERE locktype = 'advisory' AND pid = pg_backend_pid() AND objsubid = 1 AND granted
     AND ((classid::bigint << 32) | objid::bigint) = hashtextextended('ops_money_order:' || p_order::text, 0) $f$;
CREATE FUNCTION tap._advisory224() RETURNS int LANGUAGE sql AS $f$
  SELECT count(*)::int FROM pg_locks WHERE locktype = 'advisory' AND pid = pg_backend_pid() AND granted $f$;
-- the expected refusal wording (contract for F)
CREATE FUNCTION tap._msg224(p_type text, p_scope text, p_state text, p_label text) RETURNS text LANGUAGE sql STABLE AS $f$
  SELECT format('A %s for this %s is already %s (requested %s by %s). A new request is refused until it settles.',
                p_type, p_scope, p_state, to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI "UTC"'), p_label) $f$;
CREATE FUNCTION tap._hint224(p_blocker uuid) RETURNS text LANGUAGE sql IMMUTABLE AS $f$
  SELECT format('Decide it (System → Approvals), resume it (/actions/%s), or wait. A new request is accepted once it is succeeded, failed or rejected. An expired approval is cleared automatically on your next request.', p_blocker) $f$;

-- ten orders: listing + succeeded payment + seller_sent transfer (as postgres, the seed_core way)
INSERT INTO public.listings
  (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
   starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
SELECT tap._l224(n), tap.seller(), 'Fixture 224 #' || n, 'Club 224', 'wynwood', current_date + 30, '21:00', 'GA', 2, 'mobile_transfer',
       100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/224.jpg', 'active'
  FROM generate_series(1, 10) n;
INSERT INTO public.payments
  (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at)
SELECT tap._p224(n), tap._l224(n), tap.buyer(), tap.seller(), 10000, 1000, 1000, 11000, 'pi_fixture_224_' || n, 'succeeded', 'buy_now', now()
  FROM generate_series(1, 10) n;
INSERT INTO public.transfers
  (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status, seller_sent_at, auto_release_at, transfer_evidence_path, expires_at)
SELECT tap._t224(n), tap._l224(n), tap._p224(n), tap.seller(), tap.buyer(), 'mobile_transfer', 'seller_sent', now(), now() + interval '72 hours',
       'fixtures/evidence-224.jpg', now() + interval '24 hours'
  FROM generate_series(1, 10) n;

-- refund execution ON for this transaction only (the real path: setting_set by a founder)
SELECT tap._s224('set_on', tap._ex224(tap.admin_user(), 'k224-set-refund-on', 'setting_set', 'setting', NULL,
                                      '{"value": true}'::jsonb, 'refund_execute_enabled'));
SELECT is(tap._g224('set_on') ->> 'status', 'succeeded', 'S0: setting_set refund_execute_enabled=true succeeds inside the test');

-- ── T1 — same-type refund duplicate (order 1) ───────────────────────────────
SELECT tap._s224('t1a', tap._ex224(tap.admin_user(), 'k224-t1-refund-a01', 'refund_execute', 'payment', tap._p224(1)));
SELECT is(tap._g224('t1a') ->> 'status', 'awaiting_approval', 'T1.1: first refund_execute on P1 parks for approval');
SELECT is(tap._orderlock224(tap._p224(1)), 1, 'T1.2: the request took the order advisory lock (ops_money_order:<payment id>)');
SELECT tap._s224('t1b', tap._ex224(tap.other_user(), 'k224-t1-refund-b01', 'refund_execute', 'payment', tap._p224(1)));
SELECT is(tap._g224('t1b') ->> 'status', 'rejected', 'T1.3: a second refund_execute on P1 (founder B, new key) is rejected');
SELECT is(tap._g224('t1b') ->> 'reject_reason', 'duplicate_unsettled', 'T1.4: ...reject_reason = duplicate_unsettled');
SELECT is(tap._g224('t1b') #>> '{blocking,action_id}', tap._g224('t1a') ->> 'action_id', 'T1.5: blocking.action_id = the first request');
SELECT is((tap._g224('t1b') #>> '{blocking,conflict}', tap._g224('t1b') #>> '{blocking,state}', tap._g224('t1b') #>> '{blocking,subject_kind}',
           tap._g224('t1b') #>> '{blocking,approval_id}', tap._g224('t1b') #>> '{blocking,requested_by_label}'),
          ('same_type'::text, 'awaiting_approval'::text, 'payment'::text, tap._g224('t1a') ->> 'approval_id', 'TEST ADMIN'::text),
  'T1.6: blocking carries conflict same_type, state, subject_kind, the approval id and the requester label');
SELECT ok(tap._g224('t1b') ? 'blocking' AND tap._g224('t1b') -> 'result' -> 'blocking' = tap._g224('t1b') -> 'blocking'
          AND tap._g224('t1b') #>> '{result,reject_reason}' = 'duplicate_unsettled',
  'T1.7: result repeats the refusal payload (reject_reason, blocking)');
SELECT is(tap._g224('t1b') ->> 'message',
          tap._msg224('refund_execute', 'payment', 'awaiting approval', 'TEST ADMIN'), 'T1.8: message (contract wording)');
SELECT is(tap._g224('t1b') ->> 'hint', tap._hint224(tap._id224('t1a')), 'T1.9: hint (contract wording, links the blocker)');
SELECT ok(tap._id224('t1b') IS NOT NULL AND tap._id224('t1b') <> tap._id224('t1a'), 'T1.10: the refusal has its own action id');
SELECT is((SELECT count(*)::int FROM ops.approval ap JOIN ops.action a ON a.id = ap.action_id
            WHERE a.action_type = 'refund_execute' AND a.subject_id = tap._p224(1)), 1,
  'T1.11: still exactly one approval row for refunds on P1');
SELECT is((SELECT count(*)::int FROM ops.action WHERE action_type = 'refund_execute' AND subject_id = tap._p224(1)
            AND state IN ('requested','awaiting_approval','processing','unknown','succeeded_at_provider')), 1,
  'T1.12: exactly one unsettled refund_execute on P1 (not two awaiting rows)');
SELECT is((SELECT (state, reject_reason, idempotency_key, completed_at IS NOT NULL, approval_id IS NULL, result ->> 'reject_reason', requested_by)
             FROM ops.action WHERE id = tap._id224('t1b')),
          ('rejected'::text, 'duplicate_unsettled'::text, 'k224-t1-refund-b01'::text, true, true, 'duplicate_unsettled'::text, tap.other_user()),
  'T1.13: the refusal row: rejected / duplicate_unsettled, key bound, completed, no approval, requested_by founder B');
SELECT is((SELECT count(*)::int FROM ops.audit WHERE action_id = tap._id224('t1b') AND action = 'action.requested' AND outcome = 'requested'), 1,
  'T1.14: audit action.requested for the refusal');
SELECT is((SELECT count(*)::int FROM ops.audit WHERE action_id = tap._id224('t1b') AND action = 'action.refund_execute' AND outcome = 'rejected'
            AND after ->> 'reject_reason' = 'duplicate_unsettled' AND after #>> '{blocking,action_id}' = tap._g224('t1a') ->> 'action_id'), 1,
  'T1.15: audit action.refund_execute (rejected) carries the blocking payload');

-- ── T3 — replay of the refused key ──────────────────────────────────────────
SELECT tap._s224('t3', tap._ex224(tap.other_user(), 'k224-t1-refund-b01', 'refund_execute', 'payment', tap._p224(1)));
SELECT is((tap._g224('t3') ->> 'status', tap._g224('t3') ->> 'state', tap._g224('t3') ->> 'action_id'),
          ('idempotent_replay'::text, 'rejected'::text, tap._g224('t1b') ->> 'action_id'),
  'T3.1: replaying the refused key => idempotent_replay, state rejected, same action id');
SELECT is(tap._g224('t3') #>> '{result,reject_reason}', 'duplicate_unsettled', 'T3.2: ...result.reject_reason = duplicate_unsettled');
SELECT is((SELECT count(*)::int FROM ops.action WHERE idempotency_key = 'k224-t1-refund-b01'), 1, 'T3.3: no new row for the replay');

-- ── T2 — same-type payout_release duplicate (order 2) ───────────────────────
SELECT tap._s224('t2a', tap._ex224(tap.admin_user(), 'k224-t2-payout-a01', 'payout_release', 'transfer', tap._t224(2)));
SELECT is(tap._g224('t2a') ->> 'status', 'awaiting_approval', 'T2.1: first payout_release on T2 parks for approval');
SELECT tap._s224('t2b', tap._ex224(tap.other_user(), 'k224-t2-payout-b01', 'payout_release', 'transfer', tap._t224(2)));
SELECT is((tap._g224('t2b') ->> 'status', tap._g224('t2b') ->> 'reject_reason'), ('rejected'::text, 'duplicate_unsettled'::text),
  'T2.2: a second payout_release on T2 => rejected / duplicate_unsettled');
SELECT is((tap._g224('t2b') #>> '{blocking,action_id}', tap._g224('t2b') #>> '{blocking,conflict}', tap._g224('t2b') #>> '{blocking,subject_kind}',
           tap._g224('t2b') #>> '{blocking,subject_id}'),
          (tap._g224('t2a') ->> 'action_id', 'same_type'::text, 'transfer'::text, tap._t224(2)::text),
  'T2.3: blocking = the first payout_release (same_type, transfer T2)');
SELECT is(tap._g224('t2b') ->> 'message', tap._msg224('payout_release', 'transfer', 'awaiting approval', 'TEST ADMIN'), 'T2.4: message names the transfer');
SELECT is((SELECT count(*)::int FROM ops.approval ap JOIN ops.action a ON a.id = ap.action_id
            WHERE a.action_type = 'payout_release' AND a.subject_id = tap._t224(2)), 1, 'T2.5: one approval row for payouts on T2');
SELECT is((SELECT count(*)::int FROM ops.action WHERE action_type = 'payout_release' AND subject_id = tap._t224(2)
            AND state IN ('requested','awaiting_approval','processing','unknown','succeeded_at_provider')), 1,
  'T2.6: exactly one unsettled payout_release on T2');
SELECT is((SELECT count(*)::int FROM ops.audit WHERE action_id = tap._id224('t2b') AND action = 'action.payout_release' AND outcome = 'rejected'), 1,
  'T2.7: the refusal is audited (action.payout_release, rejected)');
-- Only T2.1 / T2.2 (payout_release on T2) have touched order 2, and a transaction-level advisory lock is held until
-- this test's ROLLBACK: the ORDER key being held proves the payout requests locked on P2, not on the transfer id.
SELECT is(tap._orderlock224(tap._p224(2)), 1, 'T2.8: payout_release on T2 took the ORDER lock (ops_money_order:<P2>), not a lock on the transfer id');

-- ── T4 — cross-type, both directions (order 3) ──────────────────────────────
SELECT tap._s224('t4a', tap._ex224(tap.admin_user(), 'k224-t4-refund-a01', 'refund_execute', 'payment', tap._p224(3)));
SELECT is(tap._g224('t4a') ->> 'status', 'awaiting_approval', 'T4.1: refund_execute on P3 parks');
SELECT tap._s224('t4b', tap._ex224(tap.other_user(), 'k224-t4-payout-b01', 'payout_release', 'transfer', tap._t224(3)));
SELECT is((tap._g224('t4b') ->> 'status', tap._g224('t4b') ->> 'reject_reason'), ('rejected'::text, 'duplicate_unsettled'::text),
  'T4.2: payout_release on T3 (P3''s transfer) is refused while the refund is unsettled');
SELECT is((tap._g224('t4b') #>> '{blocking,action_id}', tap._g224('t4b') #>> '{blocking,action_type}', tap._g224('t4b') #>> '{blocking,conflict}'),
          (tap._g224('t4a') ->> 'action_id', 'refund_execute'::text, 'cross_type'::text),
  'T4.3: blocking = the refund (cross_type)');
SELECT is(tap._g224('t4b') ->> 'message', tap._msg224('refund_execute', 'order', 'awaiting approval', 'TEST ADMIN'), 'T4.4: cross-type message says "this order"');
SELECT is((SELECT count(*)::int FROM ops.approval ap JOIN ops.action a ON a.id = ap.action_id WHERE a.subject_id IN (tap._p224(3), tap._t224(3))), 1,
  'T4.5: no approval was parked for the refused payout');
SELECT tap._s224('t4deny', tap._ap224(tap.other_user(), tap._id224('t4a'), 'deny'));
SELECT is((tap._g224('t4deny') ->> 'status', tap._g224('t4deny') ->> 'reject_reason'), ('rejected'::text, 'denied'::text), 'T4.6: founder B denies the refund');
SELECT tap._s224('t4c', tap._ex224(tap.admin_user(), 'k224-t4-payout-a02', 'payout_release', 'transfer', tap._t224(3)));
SELECT is(tap._g224('t4c') ->> 'status', 'awaiting_approval', 'T4.7: after the deny (terminal rejected) a payout_release on T3 is accepted');
SELECT tap._s224('t4d', tap._ex224(tap.other_user(), 'k224-t4-refund-b02', 'refund_execute', 'payment', tap._p224(3)));
SELECT is((tap._g224('t4d') ->> 'status', tap._g224('t4d') ->> 'reject_reason'), ('rejected'::text, 'duplicate_unsettled'::text),
  'T4.8: reverse direction: refund_execute on P3 is refused while the payout is unsettled');
SELECT is((tap._g224('t4d') #>> '{blocking,action_id}', tap._g224('t4d') #>> '{blocking,action_type}', tap._g224('t4d') #>> '{blocking,conflict}'),
          (tap._g224('t4c') ->> 'action_id', 'payout_release'::text, 'cross_type'::text),
  'T4.9: blocking = the payout_release (cross_type)');
SELECT is((SELECT count(*)::int FROM ops.action WHERE subject_id IN (tap._p224(3), tap._t224(3))
            AND action_type IN ('refund_execute','payout_release')
            AND state IN ('requested','awaiting_approval','processing','unknown','succeeded_at_provider')), 1,
  'T4.10: order 3 never holds more than one unsettled money action');

-- ── T5 — in-flight states block; terminal states free the order ─────────────
-- order 1 refund: approve -> processing -> unknown -> failed; then a new one -> succeeded_at_provider -> succeeded
SELECT tap._s224('t5ap1', tap._ap224(tap.other_user(), tap._id224('t1a'), 'approve'));
SELECT is((tap._g224('t5ap1') ->> 'status', tap._g224('t5ap1') #>> '{result,handoff}'), ('processing'::text, 'ops-refund-execute'::text),
  'T5.1: founder B approves the first refund => processing (edge handoff)');
SELECT tap._s224('t5a', tap._ex224(tap.admin_user(), 'k224-t5-refund-a02', 'refund_execute', 'payment', tap._p224(1)));
SELECT is((tap._g224('t5a') ->> 'reject_reason', tap._g224('t5a') #>> '{blocking,state}', tap._g224('t5a') #>> '{blocking,action_id}'),
          ('duplicate_unsettled'::text, 'processing'::text, tap._g224('t1a') ->> 'action_id'),
  'T5.2: processing blocks a new refund');
SELECT is(tap._out224(tap._id224('t1a'), 'unknown') ->> 'status', 'ok', 'T5.3: executor reports unknown');
SELECT tap._s224('t5b', tap._ex224(tap.admin_user(), 'k224-t5-refund-a03', 'refund_execute', 'payment', tap._p224(1)));
SELECT is((tap._g224('t5b') ->> 'reject_reason', tap._g224('t5b') #>> '{blocking,state}'), ('duplicate_unsettled'::text, 'unknown'::text),
  'T5.4: unknown blocks a new refund');
SELECT is(tap._g224('t5b') ->> 'message', tap._msg224('refund_execute', 'payment', 'outcome unknown', 'TEST ADMIN'), 'T5.5: message says outcome unknown');
SELECT is(tap._out224(tap._id224('t1a'), 'failed') ->> 'status', 'ok', 'T5.6: executor reports failed (terminal)');
SELECT tap._s224('t5c', tap._ex224(tap.admin_user(), 'k224-t5-refund-a04', 'refund_execute', 'payment', tap._p224(1)));
SELECT is(tap._g224('t5c') ->> 'status', 'awaiting_approval', 'T5.7: after failed, a new refund on P1 is accepted');
SELECT tap._s224('t5ap2', tap._ap224(tap.other_user(), tap._id224('t5c'), 'approve'));
SELECT is(tap._g224('t5ap2') ->> 'status', 'processing', 'T5.8: approved => processing');
SELECT is(tap._out224(tap._id224('t5c'), 'succeeded_at_provider', 're_224_t5') ->> 'status', 'ok', 'T5.9: executor reports succeeded_at_provider');
SELECT tap._s224('t5d', tap._ex224(tap.other_user(), 'k224-t5-refund-b05', 'refund_execute', 'payment', tap._p224(1)));
SELECT is((tap._g224('t5d') ->> 'reject_reason', tap._g224('t5d') #>> '{blocking,state}', tap._g224('t5d') #>> '{blocking,action_id}'),
          ('duplicate_unsettled'::text, 'succeeded_at_provider'::text, tap._g224('t5c') ->> 'action_id'),
  'T5.10: succeeded_at_provider blocks a new refund');
SELECT is(tap._g224('t5d') ->> 'message', tap._msg224('refund_execute', 'payment', 'succeeded at Stripe, awaiting webhook', 'TEST ADMIN'),
  'T5.11: message says succeeded at Stripe, awaiting webhook');
SELECT is(tap._out224(tap._id224('t5c'), 'succeeded') ->> 'status', 'ok', 'T5.12: webhook completion => succeeded (terminal)');
SELECT tap._s224('t5e', tap._ex224(tap.other_user(), 'k224-t5-refund-b06', 'refund_execute', 'payment', tap._p224(1)));
SELECT is(tap._g224('t5e') ->> 'status', 'awaiting_approval', 'T5.13: after succeeded, a new refund request is accepted by the guard');
-- order 2 payout: approve -> succeeded (synchronous)
SELECT tap._s224('t5ap3', tap._ap224(tap.other_user(), tap._id224('t2a'), 'approve'));
SELECT is(tap._g224('t5ap3') ->> 'status', 'succeeded', 'T5.14: founder B approves the payout => succeeded (transfer released)');
SELECT tap._s224('t5f', tap._ex224(tap.admin_user(), 'k224-t5-payout-a02', 'payout_release', 'transfer', tap._t224(2)));
SELECT is((tap._g224('t5f') ->> 'status', tap._g224('t5f') ->> 'reject_reason'), ('rejected'::text, 'stale_state'::text),
  'T5.15: a new payout after a succeeded one is not a duplicate: the domain precheck answers stale_state');
SELECT tap._s224('t5g', tap._ex224(tap.admin_user(), 'k224-t5-refund-a07', 'refund_execute', 'payment', tap._p224(2)));
SELECT is(tap._g224('t5g') ->> 'status' || '/' || coalesce(tap._g224('t5g') ->> 'reject_reason', ''),
          CASE WHEN to_regprocedure('ops.refund_payout_refusal(uuid,text)') IS NULL THEN 'awaiting_approval/' ELSE 'rejected/payout_released' END,
  'T5.16: a refund after a SETTLED payout is not refused by 157''s guard; with 177 (20261022001000) applied it is refused payout_released');

-- ── T6 — expired approvals are swept by the next request on the order ───────
-- order 8: an expired awaiting payout that NO request touches (scope control), later expired by approve_action
SELECT tap._s224('t8x', tap._ex224(tap.admin_user(), 'k224-t6-payout-o8', 'payout_release', 'transfer', tap._t224(8)));
UPDATE ops.approval SET expires_at = now() - interval '1 minute' WHERE id = (tap._g224('t8x') ->> 'approval_id')::uuid;
-- order 4: cross-type sweep, then same-type sweep
SELECT tap._s224('t6a', tap._ex224(tap.admin_user(), 'k224-t6-payout-a01', 'payout_release', 'transfer', tap._t224(4)));
SELECT is(tap._g224('t6a') ->> 'status', 'awaiting_approval', 'T6.1: payout_release on T4 parks');
UPDATE ops.approval SET expires_at = now() - interval '1 minute' WHERE id = (tap._g224('t6a') ->> 'approval_id')::uuid;
SELECT tap._s224('t6b', tap._ex224(tap.other_user(), 'k224-t6-refund-b01', 'refund_execute', 'payment', tap._p224(4)));
SELECT is(tap._g224('t6b') ->> 'status', 'awaiting_approval', 'T6.2: a refund on P4 sweeps the expired payout approval and is accepted');
SELECT is((SELECT (state, reject_reason, completed_at IS NOT NULL) FROM ops.action WHERE id = tap._id224('t6a')),
          ('rejected'::text, 'approval_expired'::text, true), 'T6.3: the expired payout is rejected / approval_expired');
SELECT is((SELECT state FROM ops.approval WHERE id = (tap._g224('t6a') ->> 'approval_id')::uuid), 'expired', 'T6.4: its approval is expired');
SELECT is((SELECT count(*)::int FROM ops.audit WHERE action_id = tap._id224('t6a') AND action = 'approval.expired' AND outcome = 'expired'), 1,
  'T6.5: one approval.expired audit row for it');
UPDATE ops.approval SET expires_at = now() - interval '1 minute' WHERE id = (tap._g224('t6b') ->> 'approval_id')::uuid;
SELECT tap._s224('t6c', tap._ex224(tap.admin_user(), 'k224-t6-refund-a02', 'refund_execute', 'payment', tap._p224(4)));
SELECT is(tap._g224('t6c') ->> 'status', 'awaiting_approval', 'T6.6: same type: a new refund sweeps the expired refund approval and is accepted');
SELECT is((SELECT (state, reject_reason) FROM ops.action WHERE id = tap._id224('t6b')), ('rejected'::text, 'approval_expired'::text),
  'T6.7: the expired refund is rejected / approval_expired');
SELECT is((SELECT (a.state, ap.state) FROM ops.action a JOIN ops.approval ap ON ap.id = a.approval_id WHERE a.id = tap._id224('t8x')),
          ('awaiting_approval'::text, 'pending'::text), 'T6.8: an expired approval on ANOTHER order is not swept');
SELECT tap._s224('t8ap', tap._ap224(tap.other_user(), tap._id224('t8x'), 'approve'));
SELECT is((tap._g224('t8ap') ->> 'status', tap._g224('t8ap') ->> 'reject_reason'), ('rejected'::text, 'approval_expired'::text),
  'T6.9: approve_action on order 8''s expired approval => approval_expired (the reference transition)');
SELECT is((SELECT (a.state, a.reject_reason, a.completed_at IS NOT NULL, a.version, a.result IS NULL, a.error IS NULL,
                   ap.state, ap.decided_by IS NULL, ap.decided_at IS NULL, ap.reason IS NULL)
             FROM ops.action a JOIN ops.approval ap ON ap.id = a.approval_id WHERE a.id = tap._id224('t6a')),
          (SELECT (a.state, a.reject_reason, a.completed_at IS NOT NULL, a.version, a.result IS NULL, a.error IS NULL,
                   ap.state, ap.decided_by IS NULL, ap.decided_at IS NULL, ap.reason IS NULL)
             FROM ops.action a JOIN ops.approval ap ON ap.id = a.approval_id WHERE a.id = tap._id224('t8x')),
  'T6.10: the swept row and approval equal an approve_action-expired one field by field');
SELECT is((SELECT (au.action, au.outcome, au.before IS NULL, au.after IS NULL, au.subject_kind, au.correlation_id = a.correlation_id,
                   au.subject_id = a.subject_id, au.subject_ref IS NOT DISTINCT FROM a.subject_ref)
             FROM ops.audit au JOIN ops.action a ON a.id = au.action_id WHERE au.action_id = tap._id224('t6a') AND au.action = 'approval.expired'),
          (SELECT (au.action, au.outcome, au.before IS NULL, au.after IS NULL, au.subject_kind, au.correlation_id = a.correlation_id,
                   au.subject_id = a.subject_id, au.subject_ref IS NOT DISTINCT FROM a.subject_ref)
             FROM ops.audit au JOIN ops.action a ON a.id = au.action_id WHERE au.action_id = tap._id224('t8x') AND au.action = 'approval.expired'),
  'T6.11: the sweep''s audit row has the same shape as approve_action''s, subject = the action''s own subject_id / subject_ref');
SELECT is((SELECT (au.subject_kind, au.subject_id) FROM ops.audit au
            WHERE au.action_id = tap._id224('t6a') AND au.action = 'approval.expired'),
          ('transfer'::text, tap._t224(4)),
  'T6.12: ...the swept payout''s audit names transfer T4 (its own subject), not the order''s payment P4');
-- boundary: an approval whose expires_at = now() can no longer be decided (ops.action_detail.can_decide needs
-- expires_at > now()), so the sweep clears it (<=). Order 8's first payout was expired by approve_action in T6.9.
SELECT tap._s224('t6d', tap._ex224(tap.admin_user(), 'k224-t6-payout-o8b', 'payout_release', 'transfer', tap._t224(8)));
UPDATE ops.approval SET expires_at = now() WHERE id = (tap._g224('t6d') ->> 'approval_id')::uuid;
SELECT tap._s224('t6e', tap._ex224(tap.other_user(), 'k224-t6-refund-o8', 'refund_execute', 'payment', tap._p224(8)));
SELECT is((tap._g224('t6d') ->> 'status', tap._g224('t6e') ->> 'status'), ('awaiting_approval'::text, 'awaiting_approval'::text),
  'T6.13: boundary expires_at = now(): a refund on P8 sweeps the payout whose approval expires exactly now (<=) and is accepted');
SELECT is((SELECT (a.state, a.reject_reason, ap.state) FROM ops.action a JOIN ops.approval ap ON ap.id = a.approval_id WHERE a.id = tap._id224('t6d')),
          ('rejected'::text, 'approval_expired'::text, 'expired'::text),
  'T6.14: ...the boundary payout is rejected / approval_expired, its approval expired');

-- ── T7 — the backstop index and the constraint-aware handler (order 5) ──────
SELECT tap._s224('t7a', tap._ex224(tap.admin_user(), 'k224-t7-refund-a01', 'refund_execute', 'payment', tap._p224(5)));
SELECT is(tap._g224('t7a') ->> 'status', 'awaiting_approval', 'T7.1: refund_execute on P5 parks');
SELECT throws_ok(
  format($$INSERT INTO ops.action (idempotency_key, action_type, subject_kind, subject_id, requested_by, state)
           VALUES ('k224-t7-direct-dup1', 'refund_execute', 'payment', %L, %L, 'awaiting_approval')$$, tap._p224(5), tap.admin_user()),
  '23505', 'duplicate key value violates unique constraint "action_money_unsettled_uidx"',
  'T7.2: a direct second unsettled refund_execute on P5 hits action_money_unsettled_uidx (23505)');
SELECT throws_ok(
  format($$INSERT INTO ops.action (idempotency_key, action_type, subject_kind, subject_id, requested_by, state)
           VALUES ('k224-t7-direct-dup2', 'refund_execute', 'payment', %L, %L, 'requested')$$, tap._p224(5), tap.admin_user()),
  '23505', 'duplicate key value violates unique constraint "action_money_unsettled_uidx"',
  'T7.3: ...also in state requested');
SELECT lives_ok(
  format($$INSERT INTO ops.action (idempotency_key, action_type, subject_kind, subject_id, requested_by, state, completed_at)
           VALUES ('k224-t7-direct-fail', 'refund_execute', 'payment', %L, %L, 'failed', now())$$, tap._p224(5), tap.admin_user()),
  'T7.4: a terminal (failed) row on the same subject is outside the index');
-- a payout_release on a transfer id with no transfers row: it resolves to no order, so no order lock applies
SELECT lives_ok(
  format($$INSERT INTO ops.action (idempotency_key, action_type, subject_kind, subject_id, requested_by, state)
           VALUES ('k224-t7-orphan-d01', 'payout_release', 'transfer', %L, %L, 'awaiting_approval')$$, tap._orphan224(), tap.admin_user()),
  'T7.5: fixture: an unsettled payout_release on a transfer id that has no transfers row (direct write)');
SELECT tap._s224('t7c', tap._ex224(tap.admin_user(), 'k224-t7-orphan-a02', 'payout_release', 'transfer', tap._orphan224()));
SELECT isnt(tap._g224('t7c') ->> 'status', 'idempotent_replay', 'T7.6: an index collision is never reported as idempotent_replay');
SELECT is((tap._g224('t7c') ->> 'status', tap._g224('t7c') ->> 'reject_reason'), ('rejected'::text, 'duplicate_unsettled'::text),
  'T7.7: execute_action maps the action_money_unsettled_uidx collision to rejected / duplicate_unsettled');
SELECT is(tap._g224('t7c') #>> '{blocking,action_id}', (SELECT id::text FROM ops.action WHERE idempotency_key = 'k224-t7-orphan-d01'),
  'T7.8: ...blocking names the colliding row');
SELECT is((SELECT (state, reject_reason, idempotency_key) FROM ops.action WHERE id = tap._id224('t7c')),
          ('rejected'::text, 'duplicate_unsettled'::text, 'k224-t7-orphan-a02'::text),
  'T7.9: ...with its own action id: a rejected row bound to the key');
SELECT tap._s224('t7d', tap._ex224(tap.admin_user(), 'k224-t7-orphan-a02', 'payout_release', 'transfer', tap._orphan224()));
SELECT is((tap._g224('t7d') ->> 'status', tap._g224('t7d') ->> 'action_id', tap._g224('t7d') ->> 'state'),
          ('idempotent_replay'::text, tap._g224('t7c') ->> 'action_id', 'rejected'::text),
  'T7.10: replaying that key returns the same refusal (idempotent_replay, rejected)');
SELECT is((SELECT count(*)::int FROM ops.action WHERE subject_id = tap._orphan224()), 2, 'T7.11: two rows on the orphan subject: the direct one and the refusal');

-- ── T8 — approve-time recheck on a legacy cross pair (order 6) ──────────────
SELECT lives_ok(format($q$DO $d$ DECLARE v_a uuid; v_ap uuid; BEGIN
  INSERT INTO ops.action (idempotency_key, action_type, subject_kind, subject_id, params, reason, requested_by, state)
  VALUES ('k224-t8-legacy-ref', 'refund_execute', 'payment', %1$L, '{}'::jsonb, 'legacy refund', %3$L, 'awaiting_approval') RETURNING id INTO v_a;
  INSERT INTO ops.approval (action_id, action_hash, requested_by, expires_at)
  VALUES (v_a, ops.action_hash('refund_execute', 'payment', %1$L::uuid, NULL, '{}'::jsonb), %3$L, now() + interval '72 hours') RETURNING id INTO v_ap;
  UPDATE ops.action SET approval_id = v_ap, version = version + 1 WHERE id = v_a;
END $d$$q$, tap._p224(6), tap._t224(6), tap.admin_user()),
  'T8.1: fixture: a legacy awaiting refund_execute on P6 with a pending approval (direct write)');
SELECT lives_ok(format($q$DO $d$ DECLARE v_a uuid; v_ap uuid; BEGIN
  INSERT INTO ops.action (idempotency_key, action_type, subject_kind, subject_id, params, reason, requested_by, state)
  VALUES ('k224-t8-legacy-pay', 'payout_release', 'transfer', %2$L, '{}'::jsonb, 'legacy payout', %3$L, 'awaiting_approval') RETURNING id INTO v_a;
  INSERT INTO ops.approval (action_id, action_hash, requested_by, expires_at)
  VALUES (v_a, ops.action_hash('payout_release', 'transfer', %2$L::uuid, NULL, '{}'::jsonb), %3$L, now() + interval '72 hours') RETURNING id INTO v_ap;
  UPDATE ops.action SET approval_id = v_ap, version = version + 1 WHERE id = v_a;
END $d$$q$, tap._p224(6), tap._t224(6), tap.admin_user()),
  'T8.2: fixture: a legacy awaiting payout_release on T6 (the index does not cover cross-type pairs)');
SELECT tap._s224('l1', jsonb_build_object('action_id', (SELECT id FROM ops.action WHERE idempotency_key = 'k224-t8-legacy-ref')));
SELECT tap._s224('l2', (SELECT jsonb_build_object('action_id', id, 'approval_id', approval_id, 'version', version)
                         FROM ops.action WHERE idempotency_key = 'k224-t8-legacy-pay'));
SELECT tap._s224('t8ap1', tap._ap224(tap.other_user(), tap._id224('l1'), 'approve'));
SELECT is((tap._g224('t8ap1') ->> 'status', tap._g224('t8ap1') #>> '{result,handoff}'), ('processing'::text, 'ops-refund-execute'::text),
  'T8.3: approving #1 (refund) succeeds into processing / handoff (an awaiting sibling does not block)');
SELECT tap._s224('t8ap2', tap._ap224(tap.other_user(), tap._id224('l2'), 'approve'));
SELECT is((tap._g224('t8ap2') ->> 'status', tap._g224('t8ap2') ->> 'reject_reason'), ('rejected'::text, 'duplicate_unsettled'::text),
  'T8.4: approving #2 (payout) while #1 is processing => rejected / duplicate_unsettled');
SELECT is((tap._g224('t8ap2') #>> '{blocking,action_id}', tap._g224('t8ap2') #>> '{blocking,state}', tap._g224('t8ap2') #>> '{blocking,conflict}',
           tap._g224('t8ap2') ->> 'action_id', tap._g224('t8ap2') ->> 'state'),
          (tap._g224('l1') ->> 'action_id', 'processing'::text, 'cross_type'::text, tap._g224('l2') ->> 'action_id', 'awaiting_approval'::text),
  'T8.5: ...blocking = #1 (processing, cross_type); the answer names #2 and its unchanged state');
SELECT is(tap._g224('t8ap2') ->> 'message',
          format('A refund_execute for this order is already processing (requested %s by TEST ADMIN). This approval is refused until it settles; the approval stays pending.',
                 to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI "UTC"')),
  'T8.6: approve-time message (contract wording)');
SELECT is((SELECT (a.state, a.version, a.reject_reason IS NULL, a.completed_at IS NULL, a.approval_id::text, ap.state, ap.decided_by IS NULL, ap.decided_at IS NULL)
             FROM ops.action a JOIN ops.approval ap ON ap.action_id = a.id WHERE a.id = tap._id224('l2')),
          ('awaiting_approval'::text, (tap._g224('l2') ->> 'version')::int, true, true, tap._g224('l2') ->> 'approval_id', 'pending'::text, true, true),
  'T8.7: NO state change: #2 is still awaiting_approval (same version) and its approval is still pending, undecided');
SELECT is((SELECT (status, payout_released_at IS NULL) FROM public.transfers WHERE id = tap._t224(6)), ('seller_sent'::text, true),
  'T8.8: T6 is untouched');
SELECT is((SELECT count(*)::int FROM ops.audit WHERE action_id = tap._id224('l2')), 0, 'T8.9: the refusal wrote no audit row for #2 (nothing changed)');
SELECT is(tap._out224(tap._id224('l1'), 'failed') ->> 'status', 'ok', 'T8.10: #1 fails at the provider (terminal)');
SELECT tap._s224('t8ap3', tap._ap224(tap.other_user(), tap._id224('l2'), 'approve'));
SELECT is(tap._g224('t8ap3') ->> 'status', 'succeeded', 'T8.11: the pending approval of #2 is still decidable: approved => succeeded');
-- No execute_action call has touched order 6 (T8 only approves and reports outcomes), and a transaction-level
-- advisory lock is held until this test's ROLLBACK: the order key being held proves approve_action took it.
SELECT is(tap._orderlock224(tap._p224(6)), 1, 'T8.12: approve_action took the order advisory lock (ops_money_order:<P6>)');

-- orders 9 and 10: the same legacy pair, the refund requested a day earlier (approval TTL 72 h from then). #1 (the
-- refund) is approved and the executor reports unknown (order 9) / succeeded_at_provider (order 10) through
-- ops.record_action_outcome; approving #2 (the payout) must then be refused without any state change.
CREATE FUNCTION tap._legacy224(n int) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_a uuid; v_ap uuid;
BEGIN
  INSERT INTO ops.action (idempotency_key, action_type, subject_kind, subject_id, params, reason, requested_by, requested_at, state)
  VALUES ('k224-t8-legacy-ref-' || n, 'refund_execute', 'payment', tap._p224(n), '{}'::jsonb, 'legacy refund', tap.admin_user(),
          now() - interval '1 day', 'awaiting_approval') RETURNING id INTO v_a;
  INSERT INTO ops.approval (action_id, action_hash, requested_by, created_at, expires_at)
  VALUES (v_a, ops.action_hash('refund_execute', 'payment', tap._p224(n), NULL, '{}'::jsonb), tap.admin_user(),
          now() - interval '1 day', now() - interval '1 day' + interval '72 hours') RETURNING id INTO v_ap;
  UPDATE ops.action SET approval_id = v_ap, version = version + 1 WHERE id = v_a;
  INSERT INTO ops.action (idempotency_key, action_type, subject_kind, subject_id, params, reason, requested_by, state)
  VALUES ('k224-t8-legacy-pay-' || n, 'payout_release', 'transfer', tap._t224(n), '{}'::jsonb, 'legacy payout', tap.admin_user(),
          'awaiting_approval') RETURNING id INTO v_a;
  INSERT INTO ops.approval (action_id, action_hash, requested_by, expires_at)
  VALUES (v_a, ops.action_hash('payout_release', 'transfer', tap._t224(n), NULL, '{}'::jsonb), tap.admin_user(), now() + interval '72 hours')
  RETURNING id INTO v_ap;
  UPDATE ops.action SET approval_id = v_ap, version = version + 1 WHERE id = v_a;
END $f$;
SELECT tap._legacy224(9);
SELECT tap._legacy224(10);
SELECT tap._s224('l9r',  jsonb_build_object('action_id', (SELECT id FROM ops.action WHERE idempotency_key = 'k224-t8-legacy-ref-9')));
SELECT tap._s224('l10r', jsonb_build_object('action_id', (SELECT id FROM ops.action WHERE idempotency_key = 'k224-t8-legacy-ref-10')));
SELECT tap._s224('l9p',  (SELECT jsonb_build_object('action_id', id, 'approval_id', approval_id, 'version', version)
                            FROM ops.action WHERE idempotency_key = 'k224-t8-legacy-pay-9'));
SELECT tap._s224('l10p', (SELECT jsonb_build_object('action_id', id, 'approval_id', approval_id, 'version', version)
                            FROM ops.action WHERE idempotency_key = 'k224-t8-legacy-pay-10'));
-- order 9: refund approved -> processing -> unknown
SELECT is(tap._ap224(tap.other_user(), tap._id224('l9r'), 'approve') ->> 'status', 'processing', 'T8.13: order 9: approving the legacy refund hands off (processing)');
SELECT is(tap._out224(tap._id224('l9r'), 'unknown') ->> 'status', 'ok', 'T8.14: ...the executor reports unknown');
SELECT tap._s224('l9ap2', tap._ap224(tap.other_user(), tap._id224('l9p'), 'approve'));
SELECT is((tap._g224('l9ap2') ->> 'status', tap._g224('l9ap2') ->> 'reject_reason', tap._g224('l9ap2') #>> '{blocking,action_id}',
           tap._g224('l9ap2') #>> '{blocking,state}', tap._g224('l9ap2') #>> '{blocking,conflict}'),
          ('rejected'::text, 'duplicate_unsettled'::text, tap._g224('l9r') ->> 'action_id', 'unknown'::text, 'cross_type'::text),
  'T8.15: approving the payout while the refund is UNKNOWN => rejected / duplicate_unsettled, blocking = the refund (unknown)');
SELECT is(tap._g224('l9ap2') ->> 'message',
          format('A refund_execute for this order is already outcome unknown (requested %s by TEST ADMIN). This approval is refused until it settles; the approval stays pending.',
                 to_char((now() - interval '1 day') AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI "UTC"')),
  'T8.16: ...the approve-time message stamps the BLOCKER''s requested_at (a day old), not now()');
SELECT is((SELECT (a.state, a.version, a.approval_id::text, ap.state, ap.decided_by IS NULL)
             FROM ops.action a JOIN ops.approval ap ON ap.action_id = a.id WHERE a.id = tap._id224('l9p')),
          ('awaiting_approval'::text, (tap._g224('l9p') ->> 'version')::int, tap._g224('l9p') ->> 'approval_id', 'pending'::text, true),
  'T8.17: ...NO state change: the payout is still awaiting_approval (same version), its approval pending, undecided');
SELECT is((SELECT (status, payout_released_at IS NULL) FROM public.transfers WHERE id = tap._t224(9)), ('seller_sent'::text, true),
  'T8.18: ...T9 is not released');
SELECT is((SELECT array_agg(e ->> 'state' ORDER BY e ->> 'state') FROM jsonb_array_elements(tap._od224(tap._p224(9)) -> 'unsettled_money_actions') e),
          ARRAY['awaiting_approval','unknown'],
  'T8.19: order_detail.unsettled_money_actions lists the UNKNOWN refund next to the awaiting payout');
SELECT tap._s224('l9deny', tap._ap224(tap.other_user(), tap._id224('l9p'), 'deny'));
SELECT is((tap._g224('l9deny') ->> 'status', tap._g224('l9deny') ->> 'reject_reason',
           (SELECT ap.state FROM ops.approval ap WHERE ap.id = (tap._g224('l9p') ->> 'approval_id')::uuid)),
          ('rejected'::text, 'denied'::text, 'denied'::text),
  'T8.20: a deny is never blocked: denying the payout while the refund is unknown => rejected / denied');
-- order 10: refund approved -> processing -> succeeded_at_provider (the buyer's money has moved at Stripe)
SELECT is(tap._ap224(tap.other_user(), tap._id224('l10r'), 'approve') ->> 'status', 'processing', 'T8.21: order 10: approving the legacy refund hands off (processing)');
SELECT is(tap._out224(tap._id224('l10r'), 'succeeded_at_provider', 're_224_t8_10') ->> 'status', 'ok', 'T8.22: ...the executor reports succeeded_at_provider');
SELECT tap._s224('l10ap2', tap._ap224(tap.other_user(), tap._id224('l10p'), 'approve'));
SELECT is((tap._g224('l10ap2') ->> 'status', tap._g224('l10ap2') ->> 'reject_reason', tap._g224('l10ap2') #>> '{blocking,action_id}',
           tap._g224('l10ap2') #>> '{blocking,state}'),
          ('rejected'::text, 'duplicate_unsettled'::text, tap._g224('l10r') ->> 'action_id', 'succeeded_at_provider'::text),
  'T8.23: approving the payout while the refund SUCCEEDED AT STRIPE => rejected / duplicate_unsettled, blocking = the refund');
SELECT is((SELECT (a.state, a.version, a.approval_id::text, ap.state, ap.decided_by IS NULL)
             FROM ops.action a JOIN ops.approval ap ON ap.action_id = a.id WHERE a.id = tap._id224('l10p')),
          ('awaiting_approval'::text, (tap._g224('l10p') ->> 'version')::int, tap._g224('l10p') ->> 'approval_id', 'pending'::text, true),
  'T8.24: ...NO state change: the payout is still awaiting_approval (same version), its approval pending, undecided');
SELECT is((SELECT (status, payout_released_at IS NULL) FROM public.transfers WHERE id = tap._t224(10)), ('seller_sent'::text, true),
  'T8.25: ...T10 is not released (the seller is not paid after the buyer was refunded)');
SELECT is((SELECT array_agg(e ->> 'state' ORDER BY e ->> 'state') FROM jsonb_array_elements(tap._od224(tap._p224(10)) -> 'unsettled_money_actions') e),
          ARRAY['awaiting_approval','succeeded_at_provider'],
  'T8.26: order_detail.unsettled_money_actions lists the SUCCEEDED_AT_PROVIDER refund next to the awaiting payout');

-- ── T9 — non-money action types are unchanged ───────────────────────────────
SELECT tap._s224('adv0', jsonb_build_object('n', tap._advisory224()));
SELECT tap._s224('t9a', tap._ex224(tap.admin_user(), 'k224-t9-case-a01', 'case_create', 'none', NULL, '{"title":"224 case"}'::jsonb));
SELECT tap._s224('t9b', tap._ex224(tap.other_user(), 'k224-t9-case-b01', 'case_create', 'none', NULL, '{"title":"224 case"}'::jsonb));
SELECT is((tap._g224('t9a') ->> 'status', tap._g224('t9b') ->> 'status'), ('succeeded'::text, 'succeeded'::text),
  'T9.1: two case_create with the same title and new keys both succeed (no guard on non-money types)');
SELECT is((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(tap._g224('t9a')) k), ARRAY['action_id','message','reject_reason','result','status'],
  'T9.2: the case_create answer has the production shape');
SELECT tap._s224('t9c', tap._ex224(tap.admin_user(), 'k224-t9-note-a01', 'case_note', 'case', (tap._g224('t9a') #>> '{result,case_id}')::uuid, '{"body":"one"}'::jsonb));
SELECT tap._s224('t9d', tap._ex224(tap.admin_user(), 'k224-t9-note-a02', 'case_note', 'case', (tap._g224('t9a') #>> '{result,case_id}')::uuid, '{"body":"two"}'::jsonb));
SELECT is((tap._g224('t9c') ->> 'status', tap._g224('t9d') ->> 'status'), ('succeeded'::text, 'succeeded'::text), 'T9.3: two case_note on one case both succeed');
SELECT tap._s224('t9e', tap._ex224(tap.other_user(), 'k224-t9-case-a01', 'case_create', 'none', NULL, '{"title":"other"}'::jsonb));
SELECT is((tap._g224('t9e') ->> 'status', tap._g224('t9e') ->> 'action_id'), ('idempotent_replay'::text, tap._g224('t9a') ->> 'action_id'),
  'T9.4: a reused key on a non-money type is still idempotent_replay of the original');
SELECT is(tap._advisory224(), (tap._g224('adv0') ->> 'n')::int, 'T9.5: non-money actions take no advisory lock');
-- 158 (20261021110000) requires expected.updated_at for listing_relist (invalid_input without it). This call sends the
-- listing's own updated_at, read as postgres before the login, so T9.6 asserts the same thing with or without 158:
-- no approval, no money guard (listing_c is a real seller's, so both versions answer rejected / precondition).
CREATE FUNCTION tap._rl224(p_key text, p_subject uuid) RETURNS jsonb
LANGUAGE plpgsql AS $f$
declare
  e jsonb := jsonb_build_object('updated_at', (SELECT l.updated_at FROM public.listings l WHERE l.id = p_subject));
  v jsonb;
begin
  perform tap.login(tap.admin_user()); perform tap._aal2();
  v := ops.execute_action(p_key, 'listing_relist', 'listing', p_subject, '{}'::jsonb, 'pgTAP 224 listing_relist', e, NULL);
  perform tap.logout();
  return v;
end $f$;
SELECT tap._s224('t9f', tap._rl224('k224-t9-relist-a01', tap.listing_c()));
SELECT is((SELECT (state, approval_id IS NULL) FROM ops.action WHERE id = tap._id224('t9f')), (tap._g224('t9f') ->> 'status', true),
  'T9.6: listing_relist runs without approval or guard (state = the returned status)');
SELECT is(tap._g224('set_on') #>> '{result,after}', 'true', 'T9.7: setting_set returned before/after as before 157');

-- ── T10 — order_detail.unsettled_money_actions is uncapped (order 7) ────────
SELECT tap._s224('t10a', tap._ex224(tap.admin_user(), 'k224-t10-payout-a01', 'payout_release', 'transfer', tap._t224(7)));
UPDATE ops.action SET requested_at = now() - interval '2 days' WHERE id = tap._id224('t10a');
INSERT INTO ops.action (idempotency_key, action_type, subject_kind, subject_id, reason, requested_by, requested_at, state, reject_reason, completed_at)
SELECT 'k224-t10-relist-' || lpad(n::text, 3, '0'), 'listing_relist', 'listing', tap._l224(7), 'older relist', tap.admin_user(),
       now() - interval '1 day' + n * interval '1 minute', 'rejected', 'stale_state', now() - interval '1 day' + n * interval '1 minute'
  FROM generate_series(1, 55) n;
INSERT INTO ops.action (idempotency_key, action_type, subject_kind, subject_id, reason, requested_by, requested_at, state, error, completed_at)
VALUES ('k224-t10-refund-old', 'refund_execute', 'payment', tap._p224(7), 'old failed refund', tap.admin_user(), now() - interval '3 days',
        'failed', 'card_declined', now() - interval '3 days');
SELECT tap._s224('od7', tap._od224(tap._p224(7)));
SELECT is(jsonb_array_length(tap._g224('od7') -> 'actions'), 50, 'T10.1: the capped actions list still holds 50');
SELECT ok(NOT (tap._g224('od7') -> 'actions') @> jsonb_build_array(jsonb_build_object('id', tap._id224('t10a'))),
  'T10.2: the blocker is 56 deep: not in the capped list');
SELECT is(jsonb_array_length(tap._g224('od7') -> 'unsettled_money_actions'), 1, 'T10.3: unsettled_money_actions holds exactly the one unsettled action');
SELECT is((tap._g224('od7') #>> '{unsettled_money_actions,0,id}', tap._g224('od7') #>> '{unsettled_money_actions,0,approval_id}',
           tap._g224('od7') #>> '{unsettled_money_actions,0,approval_expired}', tap._g224('od7') #>> '{unsettled_money_actions,0,state}'),
          (tap._g224('t10a') ->> 'action_id', tap._g224('t10a') ->> 'approval_id', 'false'::text, 'awaiting_approval'::text),
  'T10.4: ...the blocker, with its approval id and approval_expired=false');
SELECT is((tap._g224('od7') #>> '{unsettled_money_actions,0,approval_expires_at}')::timestamptz,
          (SELECT expires_at FROM ops.approval WHERE id = (tap._g224('t10a') ->> 'approval_id')::uuid),
  'T10.5: ...approval_expires_at = the approval''s expires_at');
SELECT is((tap._g224('od7') #>> '{unsettled_money_actions,0,requested_by_label}', (tap._g224('od7') #> '{unsettled_money_actions,0}') ? 'subject_label'),
          ('TEST ADMIN'::text, true), 'T10.6: ...shaped by ops.action_row (requested_by_label, subject_label)');
SELECT is(tap._g224('od7') -> 'actions',
          (SELECT coalesce(jsonb_agg(ops.action_row(a) ORDER BY a.requested_at DESC), '[]'::jsonb) FROM (
             SELECT * FROM ops.action a
              WHERE (a.subject_kind = 'payment'  AND a.subject_id = tap._p224(7))
                 OR (a.subject_kind = 'transfer' AND a.subject_id = tap._t224(7))
                 OR (a.subject_kind = 'listing'  AND a.subject_id = tap._l224(7))
              ORDER BY a.requested_at DESC LIMIT 50) a),
  'T10.7: actions is unchanged (the production query, byte for byte)');
SELECT is((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(tap._g224('od7')) k),
          ARRAY['actions','bank_payout','buyer','cases','dispute_resolutions','disputes','evidence','listing','payment','payout_decisions',
                'refund','seller','seller_funds_state','transfer','unsettled_money_actions'],
  'T10.8: order_detail keys = production keys + unsettled_money_actions');
-- now() is frozen in this transaction and every other blocker here was requested in it: only a blocker requested
-- earlier (t10a, 2 days ago) can tell the blocker's requested_at from the current time in the message
SELECT tap._s224('t10x', tap._ex224(tap.admin_user(), 'k224-t10-refund-a02', 'refund_execute', 'payment', tap._p224(7)));
SELECT is((tap._g224('t10x') ->> 'reject_reason', tap._g224('t10x') #>> '{blocking,action_id}', tap._g224('t10x') ->> 'message'),
          ('duplicate_unsettled'::text, tap._g224('t10a') ->> 'action_id',
           format('A payout_release for this order is already awaiting approval (requested %s by TEST ADMIN). A new request is refused until it settles.',
                  to_char((now() - interval '2 days') AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI "UTC"'))),
  'T10.9: a refund on P7 is refused by t10a; the message stamps the BLOCKER''s requested_at (2 days ago), not now()');
UPDATE ops.approval SET expires_at = now() - interval '1 minute' WHERE id = (tap._g224('t10a') ->> 'approval_id')::uuid;
SELECT tap._s224('od7b', tap._od224(tap._p224(7)));
SELECT is((tap._g224('od7b') #>> '{unsettled_money_actions,0,id}', tap._g224('od7b') #>> '{unsettled_money_actions,0,approval_expired}'),
          (tap._g224('t10a') ->> 'action_id', 'true'::text), 'T10.10: an expired approval shows approval_expired=true');
SELECT is((SELECT state FROM ops.action WHERE id = tap._id224('t10a')), 'awaiting_approval', 'T10.11: reading order_detail sweeps nothing');

-- ── T11 — ACLs ──────────────────────────────────────────────────────────────
SELECT is((SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = to_regprocedure('ops.money_order_id(text,uuid)')),
          (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = 'ops.action_precheck(ops.action)'::regprocedure),
  'T11.1: money_order_id ACL = action_precheck''s (postgres only)');
SELECT is((SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = to_regprocedure('ops.money_unsettled_blocker(uuid,uuid,text[],text,uuid)')),
          (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = 'ops.action_precheck(ops.action)'::regprocedure),
  'T11.2: money_unsettled_blocker ACL = action_precheck''s');
SELECT is((SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = to_regprocedure('ops.expire_stale_money_approvals(uuid)')),
          (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = 'ops.action_precheck(ops.action)'::regprocedure),
  'T11.3: expire_stale_money_approvals ACL = action_precheck''s');
SELECT is((SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = 'ops.action_precheck(ops.action)'::regprocedure), 'postgres=X/postgres',
  'T11.4: ...which is postgres=X/postgres');
SELECT ok(NOT has_function_privilege('anon', to_regprocedure('ops.money_order_id(text,uuid)'), 'EXECUTE'), 'T11.5: anon may not execute money_order_id');
SELECT ok(NOT has_function_privilege('authenticated', to_regprocedure('ops.money_order_id(text,uuid)'), 'EXECUTE'), 'T11.6: authenticated may not execute money_order_id');
SELECT ok(NOT has_function_privilege('anon', to_regprocedure('ops.money_unsettled_blocker(uuid,uuid,text[],text,uuid)'), 'EXECUTE'), 'T11.7: anon may not execute money_unsettled_blocker');
SELECT ok(NOT has_function_privilege('authenticated', to_regprocedure('ops.money_unsettled_blocker(uuid,uuid,text[],text,uuid)'), 'EXECUTE'), 'T11.8: authenticated may not execute money_unsettled_blocker');
SELECT ok(NOT has_function_privilege('anon', to_regprocedure('ops.expire_stale_money_approvals(uuid)'), 'EXECUTE'), 'T11.9: anon may not execute expire_stale_money_approvals');
SELECT ok(NOT has_function_privilege('authenticated', to_regprocedure('ops.expire_stale_money_approvals(uuid)'), 'EXECUTE'), 'T11.10: authenticated may not execute expire_stale_money_approvals');
SELECT is((SELECT array_agg(p.proname::text || ':' || p.prosecdef || ':' || coalesce(array_to_string(p.proconfig, ','), '') ORDER BY p.proname)
             FROM pg_proc p WHERE p.oid IN (to_regprocedure('ops.money_order_id(text,uuid)'),
                                            to_regprocedure('ops.money_unsettled_blocker(uuid,uuid,text[],text,uuid)'),
                                            to_regprocedure('ops.expire_stale_money_approvals(uuid)'))),
          ARRAY['expire_stale_money_approvals:true:search_path=""', 'money_order_id:true:search_path=""', 'money_unsettled_blocker:true:search_path=""'],
  'T11.11: the three helpers are SECURITY DEFINER with search_path ''''');
SELECT is((SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = 'ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)'::regprocedure),
          'postgres=X/postgres,authenticated=X/postgres', 'T11.12: execute_action ACL = production');
SELECT is((SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = 'ops.approve_action(uuid,text,text)'::regprocedure),
          'postgres=X/postgres,authenticated=X/postgres', 'T11.13: approve_action ACL = production');
SELECT is((SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = 'ops.order_detail(uuid)'::regprocedure),
          'postgres=X/postgres,authenticated=X/postgres', 'T11.14: order_detail ACL = production');
SELECT is((SELECT array_agg(p.proname::text || ':' || p.prosecdef || ':' || coalesce(array_to_string(p.proconfig, ','), '') ORDER BY p.proname)
             FROM pg_proc p WHERE p.oid IN ('ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)'::regprocedure,
                                            'ops.approve_action(uuid,text,text)'::regprocedure, 'ops.order_detail(uuid)'::regprocedure)),
          ARRAY['approve_action:true:search_path=""', 'execute_action:true:search_path=""', 'order_detail:true:search_path=""'],
  'T11.15: the three redefined functions stay SECURITY DEFINER with search_path ''''');

-- ── T12 — catalog ───────────────────────────────────────────────────────────
SELECT is((
  WITH prod(fn, args, md5) AS (VALUES
    ('action_allowed_roles', 'p_action_type text', '972443bf571dc94ef1e1400602b28315'),
    ('action_detail', 'p_action_id uuid', 'd1dcd69386f8f8dce5b03f37c9c3eeb6'),
    ('action_dispatch', 'p_action ops.action', 'bfb8b9dcfaace5ff04009f96b6de7bef'),   -- or 158's md5 (chain_alt below)
    ('action_hash', 'p_action_type text, p_subject_kind text, p_subject_id uuid, p_subject_ref text, p_params jsonb', 'ad280c19761b428d644281f6e336a7c5'),
    ('action_precheck', 'p_action ops.action', 'fbc3d08eae4de831ab3f085e170e8f10'),
    ('action_requires_approval', 'p_action_type text', '44ab739b9db2c77ef8709fed6c1d5082'),
    ('action_row', 'a ops.action', 'a4b777b65af858902b139f1f415192b2'),
    ('action_run', 'p_action_id uuid', '546693f1489c364de19e9416a92c07ed'),
    ('actor_label', 'p_user uuid', 'a8a3ceb39128a9665c4907f8dc721969'),
    ('actor_role', '', '846f9e1b30b3a621258071d08b650ca5'),
    ('alert_ack', 'p_alert_key text, p_note text', '0a7ac76ff1ea71c78725093edbe83351'),
    ('alert_fire', 'p_key text, p_kind text, p_payload jsonb', 'd42f697b39f4c8e43b87f28a2ac56101'),
    ('alert_post', 'p_body jsonb', '93be8afb0e9cf2ebc9961a612b184ffb'),
    ('alert_recover', 'p_key text', 'b3bfd4a03ea8852da974a508772afa93'),
    ('alert_recover_stale', 'p_prefix text, p_active_suffixes text[]', '2453448949fc145b253d53ec7f5bdbb5'),
    ('alert_response', 'p_request_id bigint', '6366f2117c9ad6c5abb870bb06d1a15f'),
    ('assert_actions_enabled', '', 'cd2b4c6d9ed5bb8a65eedd36fa2d8d4d'),
    ('assert_reader', '', '24c003a983cb577b6ad178fc595c17c5'),
    ('assert_role', 'p_roles text[]', '0b3bf7d903322c5ec83964a3a6c00907'),
    ('audit_log', 'p_cursor text, p_limit integer', '2a97902bea2e6e7d96accf1b1f6ce267'),
    ('audit_write', 'p_action text, p_subject_kind text, p_subject_id uuid, p_subject_ref text, p_reason text, p_before jsonb, p_after jsonb, p_outcome text, p_correlation_id uuid, p_action_id uuid', '3ff26aea06f5dc27f02708b60e2a2918'),
    ('case_auto_resolve', 'p_case_type text, p_active_keys text[]', 'e6c83a2c39e2b668941615dae82cd39c'),
    ('case_auto_resolve_subject', 'p_case_type text, p_subject_id uuid, p_action_id uuid', '41a9a4aa9613b41052eb77bf36ffc7d8'),
    ('case_detail', 'p_case_id uuid', '5f6645a0d52d0e58948ff9ae0defdd94'),
    ('case_row', 'c ops."case"', 'f13730132ee10d8904f086a7ece3167b'),
    ('case_upsert', 'p_case_type text, p_subject_kind text, p_subject_id uuid, p_subject_ref text, p_title text, p_summary text, p_priority text, p_due_at timestamp with time zone, p_detector text', '0cfd4ee823064fcf57c5c8244cfdb287'),
    ('clamp_limit', 'p_limit integer', '94083e8cafefb9460207d055e74c4f83'),
    ('cron_expected_gap_minutes', 'p_schedule text', '3071f3c34e8b7a4f69e095eedd330072'),
    ('cron_interval_minutes', 'p_schedule text', '4af784a3163d44a7d53edebecc12b8f0'),
    ('current_aal', '', '33c0f6adc066ddb1bda8e21996cc38ac'),
    ('cursor_decode', 'p_cursor text, OUT ts timestamp with time zone, OUT id uuid', 'a44bf6d7ce724e7f457b8517fb06d2d0'),
    ('cursor_encode', 'p_ts timestamp with time zone, p_id uuid', '6e629458d923da440456dfcac5a1f564'),
    ('detect_case', 'p_case_type text, p_subject_kind text, p_subject_id uuid, p_subject_ref text, p_title text, p_summary text, p_priority text, p_due_at timestamp with time zone, p_detector text', '0325bb2a2182972fed154f7fb14a51de'),
    ('detect_disputes', '', 'eacc23ccfa6955cb2ac5ea37c5cff90c'),
    ('detect_jobs', '', '37574d2ce87b26176e66b309ffe26932'),
    ('detect_notifications', '', 'a4f3cfb188a555448c49e16c1dc9b398'),
    ('detect_paid_unsettled', '', '3c6908d3ca8e089a5e7deb7f69cde93c'),
    ('detect_payout_review', '', '6e72285fa663c1cadc706b072d91046b'),
    ('detect_reconciliation', '', 'ae48931902b21f8354505af1005fa537'),
    ('detect_refund_resolution', '', 'e2f88fb509f611926227391d61564da6'),
    ('detect_refunds', '', '6a4727f4f39ced0a6078ac639b38de16'),
    ('detect_release_stuck', '', '98f435510c6db4ffecf0c3977e81471c'),
    ('detect_reports', '', '9f51769f7bf480ae65cece5040dd6424'),
    ('detect_sweep', 'p_case_type text, p_active_keys text[]', 'ad706285cabab8da46eb428b42bcb302'),
    ('detect_transfer_deadlines', '', '549751af4f93519dd5bc10bf225b4603'),
    ('detect_webhooks', '', '3bf16058fd2a0ee88450e155d47f04e3'),
    ('dispatch_alerts', 'p_limit integer', '322d8b37d180beb9d9719a2be9ce1299'),
    ('evidence_access', 'p_subject_kind text, p_subject_id uuid, p_slot text', 'c7a87282d0193c12c20dc2ef23b918ed'),
    ('evidence_operator_may_read', '', '76a71c68d1934d532f6ef4bfc906c53a'),
    ('evidence_path_is_referenced', 'p_name text', 'f46d7baa8dfc011c788c1b8660e3e80a'),
    ('executor_claim', 'p_action_id uuid, p_lease_seconds integer', '1cfa0290546ff36fe07389a9d13b7f9e'),
    ('funds_state', 't transfers, p payments', 'b73cae88e18c3fc62b1fcfce70722301'),
    ('job_health', '', 'da349c0b79362907d1604d759c1886c9'),
    ('jsonb_text_array', 'p jsonb', 'cbb21ecb6c1ba43ea655b9336dd86d01'),
    ('latest_summary', '', '70c510f7ec8a63812b19d78f3f13c4e3'),
    ('list_actions', 'p_filters jsonb, p_cursor text, p_limit integer', '16a213ecc0b118f5562969d9ebaab8a6'),
    ('list_approvals', 'p_state text', 'fffda19ae1499d4a89284ff84cf73b94'),
    ('list_cases', 'p_filters jsonb, p_cursor text, p_limit integer', '96177f2e77b88b58a05f8527a568550a'),
    ('list_listings', 'p_filters jsonb, p_cursor text, p_limit integer', 'a9d99c85727437888a526e6d994b45cb'),
    ('list_orders', 'p_filters jsonb, p_cursor text, p_limit integer', '0a66c02369840233f5ce485dcbb4e386'),
    ('list_payouts', 'p_filters jsonb, p_cursor text, p_limit integer', 'c1c81cc8c2f526f2a48bc5b3f060197e'),
    ('list_reports', 'p_filters jsonb, p_cursor text, p_limit integer', 'b41569ac86023709e7f93d039f06f84b'),
    ('list_users', 'p_filters jsonb, p_cursor text, p_limit integer', '279198faddd8f8197d8ccb3f81f8c13c'),
    ('listing_detail', 'p_listing_id uuid', '5208dbb14d749db54c2fdd62e50ab800'),
    ('listing_summary', 'p_listing uuid', 'df7ad2ec8405348f40560ae0e9bb3d0f'),
    ('mask_email', 'p text', '96c33e525d73719111b80ac5050f0480'),
    ('mask_phone', 'p text', '94a37ddf957cc36028a876fe4976b4b0'),
    ('normalize_summary_body', 'p_body jsonb', '95e65220deeabe31664d49736d347d12'),
    ('operators', '', '4c914e4679c441cf667012b29c300a01'),
    ('order_row', 'p payments, t transfers', '70cf6885643e4eab1370117c65f854de'),
    ('order_timeline', 'p_payment_id uuid', '1ac47ec8cf7c04459b3307611f8d5c13'),
    ('payment_json', 'p payments', '1a27396df495164c7492568751bcfce3'),
    ('raise_append_only', '', '7d2467456297a4753f25513ca76539f4'),
    ('reconciliation_queue', 'p_cursor text, p_limit integer', 'b8cfac065c780f07e77e6abf7f8eb129'),
    ('record_action_outcome', 'p_action_id uuid, p_state text, p_result jsonb, p_error text, p_provider_ref text', 'c4fb902ec1f0d0166955993b4cfe96df'),
    ('run_all_detectors', '', 'd42b1260fc7dba696af2785a593210e4'),
    ('run_job', 'p_job_name text, p_trigger text', '916408cb5c758a727f9e8cd6a8f0e057'),
    ('search', 'p_q text, p_limit integer', '8e99fcbe8f57472a54724f8a6be41eaf'),
    ('set_updated_at', '', '57c725da1c339fba5e7463900c075e12'),
    ('setting_bool', 'p_key text, p_default boolean', 'feae98c6603b8ece6e2e6099e027d61d'),
    ('setting_int', 'p_key text, p_default integer', '6613ad4434bdf567d8199d8bc9180a1e'),
    ('settings', '', 'b60165efb0deed858202ffff33605499'),
    ('subject_label', 'p_kind text, p_id uuid, p_ref text', 'f3a8ced4fd30583e61fec18493414180'),
    ('subject_summary', 'p_kind text, p_id uuid, p_ref text', '4e506d528c05aed76311b911cf32cb1e'),
    ('today', '', 'da8289c36caf73d76b929eb14feaaaad'),
    ('transfer_json', 't transfers', '0019c2fd1fdd3712c482fcdcf00a2bff'),
    ('user_detail', 'p_user_id uuid', '2efcb5a57b60d5b3d28a17d3e37a00b4'),
    ('user_summary', 'p_user uuid', '795f00abd87286c86c182690a3ad6848'),
    ('uuid_prefix_range', 'p_q text, OUT lo uuid, OUT hi uuid', '89f99d340abd1725879ffcb70350d984'),
    ('whoami', '', 'e3de6980a9b8c5c172627acbb256d2bb'),
    -- in production with a body that differs from the repo chain's (126 refund metrics): production md5 here,
    -- the chain md5 in chain_alt below (replay/fp_chain/functions.json); any third value fails
    ('build_daily_summary', 'p_date date', 'cc2e6085528cb74e0c233bded189dedf'),
    ('money_overview', 'p_from date, p_to date', '2903d6deb3a9949cb317ba9d05b860ab'),
    ('refresh_metrics', '', '60ee7526afd18e411744492c4ccae0f7')
  ), chain_alt(fn, args, md5) AS (VALUES
    ('build_daily_summary', 'p_date date', '0b5eefaea2b976c46cbd906e1703695f'),
    ('money_overview', 'p_from date, p_to date', '895b0fa065d7fbdae1cd192d92219b0e'),
    ('refresh_metrics', '', '97be33e2546438353533ec75d0eaa52f'),
    -- 158 (20261021110000, stacked on 157) replaces action_dispatch's listing_relist branch. This suite runs on 157
    -- alone (production's dispatch, bfb8b9dc above: the state between the two applies and after a 158 rollback) and
    -- on 157 + 158 (this md5, pg_get_functiondef of 158's body); any third value still fails.
    ('action_dispatch', 'p_action ops.action', '7f507fc880c02617c53d1e4f679c608c'),
    -- 177 (20261022001000, stacked on 158) redefines action_dispatch (refund_execute branch) and action_precheck
    -- and adds the internal ops.refund_payout_refusal (excluded below).
    ('action_dispatch', 'p_action ops.action', '530105443dff97cdf1639c12d2bf24f1'),
    ('action_precheck', 'p_action ops.action', '20a5ae0386be0644293f5230fad84dde')
  ), live AS (
    SELECT p.proname::text AS fn, pg_get_function_identity_arguments(p.oid) AS args, md5(pg_get_functiondef(p.oid)) AS md5
      FROM pg_proc p WHERE p.pronamespace = 'ops'::regnamespace AND p.prokind IN ('f','p'))
  SELECT coalesce(array_agg(x ORDER BY x), '{}'::text[]) FROM (
    SELECT 'changed or missing: ' || pr.fn || '(' || pr.args || ')' AS x FROM prod pr
     WHERE (pr.fn, pr.args, pr.md5) NOT IN (SELECT fn, args, md5 FROM live)
       AND NOT EXISTS (SELECT 1 FROM chain_alt c JOIN live l ON (l.fn, l.args, l.md5) = (c.fn, c.args, c.md5)
                        WHERE (c.fn, c.args) = (pr.fn, pr.args))
    UNION ALL
    SELECT 'not in production: ' || fn || '(' || args || ')' FROM live
     WHERE (fn, args) NOT IN (SELECT fn, args FROM prod)
       AND fn NOT IN ('execute_action','approve_action','order_detail',
                      'money_order_id','money_unsettled_blocker','expire_stale_money_approvals',
                      'refund_facts','refund_payout_refusal')) d),
  '{}'::text[],
  'T12.1: every other ops function keeps its production md5 (prod_functions.json 2026-10-21; the 3 metric bodies: production or chain md5; action_dispatch: production, 158''s or 177''s md5; action_precheck: production or 177''s)');
SELECT is((SELECT count(*)::int FROM (VALUES
             ('ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)', 'e59c158453adabc662431cac9dca1040'),
             ('ops.approve_action(uuid,text,text)', '5de6235288b38792c31dca3e6b3f89af'),
             ('ops.order_detail(uuid)', '04d4e05f6c533fa428c4f7123d20eba8')) v(sig, prod_md5)
            WHERE md5(pg_get_functiondef(v.sig::regprocedure)) <> v.prod_md5), 3,
  'T12.2: the three redefined bodies are live (none still has its production md5)');
SELECT is((SELECT pg_get_indexdef(to_regclass('ops.action_money_unsettled_uidx'))),
          'CREATE UNIQUE INDEX action_money_unsettled_uidx ON ops.action USING btree (action_type, subject_kind, subject_id) WHERE ((action_type = ANY (ARRAY[''refund_execute''::text, ''payout_release''::text])) AND (state = ANY (ARRAY[''requested''::text, ''awaiting_approval''::text, ''processing''::text, ''unknown''::text, ''succeeded_at_provider''::text])))',
  'T12.3: action_money_unsettled_uidx has the exact definition');
-- T12.4: static lock order. Comments are stripped first (the 157 comment above the lock says "FOR UPDATE" in prose)
-- and whitespace is collapsed, so "for update" matches however the clause is wrapped.
SELECT is((SELECT CASE WHEN lk = 0 THEN 'no pg_advisory_xact_lock' WHEN fu = 0 THEN 'no FOR UPDATE'
                       WHEN lk < fu THEN 'advisory lock first' ELSE 'FOR UPDATE first' END
             FROM (SELECT position('pg_advisory_xact_lock(' IN d) AS lk, position('for update' IN d) AS fu
                     FROM (SELECT regexp_replace(regexp_replace(lower(pg_get_functiondef('ops.approve_action(uuid,text,text)'::regprocedure)),
                                                                '--[^\n]*', '', 'g'), '\s+', ' ', 'g') AS d) x) y),
          'advisory lock first',
  'T12.4: approve_action takes the order advisory lock before its first FOR UPDATE (static lock order, comments stripped)');

SELECT * FROM finish();
ROLLBACK;

-- ============================================================================
-- 211_ops_refund_resolution_detector.sql — migration 144 (refund-resolution detector).
--   Section G: the owner's switch — seeded false; run_job skips it for cron AND manual; run_all_detectors lists it.
--   Section S: one fixture per state through ops.run_job('refund_resolution') (the real entry point): R1, R2 in five
--     variants (incl. the NULL-safe and the documented false-R2), the expiry job's own refund (no case), R3 ×3, the
--     exclusions (disputed; a payout exists → reconciliation_mismatch owns it), the case shape, idempotency.
--   Section T: transitions — while open (state events, one case per transfer, R4 pointer, never auto-resolved) and
--     after support closes a case (design §4: suppressed and opening cells, each its own fixture).
--   Section C: closure through ops.execute_action('case_status') as platform_support — classification required
--     (none / 'D' refused), stored in the event and the note; a pre-existing case type still dispatches unchanged.
-- Fixture writes bypass the 055/056 transfer guard exactly as the other suites do (transaction-local).
-- ============================================================================
BEGIN;
SELECT plan(46);
SELECT tap.seed_core();

CREATE FUNCTION tap._aal2() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;
CREATE FUNCTION tap._run211(p_job text DEFAULT 'refund_resolution', p_trigger text DEFAULT 'cron') RETURNS jsonb
LANGUAGE plpgsql AS $f$ declare v jsonb; begin perform tap.login_service(); v := ops.run_job(p_job, p_trigger);
perform tap.logout(); return v; end $f$;
-- Fixture n: its own listing, payment and transfer (ids end in n). Payment status 'refunded' unless given.
CREATE FUNCTION tap._rr(n int, p_tstatus text, p_refunded_at timestamptz, p_refund_id text,
                        p_expired_at timestamptz DEFAULT NULL, p_pstatus text DEFAULT 'refunded',
                        p_stripe_transfer_id text DEFAULT NULL) RETURNS uuid LANGUAGE plpgsql AS $f$
declare v_l uuid := ('dddddddd-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid;
        v_p uuid := ('eeeeeeee-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid;
        v_t uuid := ('ffffffff-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid;
begin
  insert into public.listings (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type,
    quantity, transfer_method, starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at,
    current_bid, cover_image_path)
  values (v_l, tap.seller(), 'RR Event ' || n, 'Club RR', 'wynwood', current_date + 30, '21:00', 'GA', 2,
    'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/rr.jpg');
  insert into public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total,
    stripe_payment_intent_id, status, mode, paid_at, refunded_at, stripe_refund_id)
  values (v_p, v_l, tap.buyer(), tap.seller(), 10000, 1000, 1000, 11000, 'pi_rr_' || n, p_pstatus, 'buy_now',
    now() - interval '2 days', p_refunded_at, p_refund_id);
  insert into public.transfers (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status,
    seller_sent_at, expires_at, expired_at, stripe_transfer_id)
  values (v_t, v_l, v_p, tap.seller(), tap.buyer(), 'mobile_transfer', p_tstatus,
    case when p_tstatus in ('seller_sent','buyer_confirmed','auto_released','disputed') then now() - interval '1 day' end,
    coalesce(p_expired_at, now() + interval '20 hours'), p_expired_at, p_stripe_transfer_id);
  return v_t;
end $f$;
CREATE FUNCTION tap._t(n int) RETURNS uuid LANGUAGE sql AS $f$ select ('ffffffff-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid $f$;
CREATE FUNCTION tap._open(n int) RETURNS ops."case" LANGUAGE sql AS $f$
  select c.* from ops."case" c where c.case_type = 'refund_resolution' and c.subject_id = tap._t(n)
     and c.status not in ('resolved','dismissed') $f$;
CREATE FUNCTION tap._state(p_case uuid) RETURNS text LANGUAGE sql AS $f$
  select e.data ->> 'to' from ops.case_event e where e.case_id = p_case and e.kind = 'state_changed'
   order by e.created_at desc limit 1 $f$;
CREATE FUNCTION tap._ncases(n int) RETURNS int LANGUAGE sql AS $f$
  select count(*)::int from ops."case" c where c.case_type = 'refund_resolution' and c.subject_id = tap._t(n) $f$;
-- close the fixture's open case as platform_support, through the real action entry point
INSERT INTO kernel.platform_role (identity_id, role, granted_by) VALUES (tap.other_user(), 'platform_support', tap.admin_user());
CREATE FUNCTION tap._close(n int, p_class text, p_key text) RETURNS jsonb LANGUAGE plpgsql AS $f$
declare v jsonb; v_case uuid := (tap._open(n)).id;
begin
  if v_case is null then return '{"status":"no_open_case"}'::jsonb; end if;   -- keeps a failure a failure, not an abort
  perform tap.login(tap.other_user()); perform tap._aal2();
  v := ops.execute_action(p_key, 'case_status', 'case', v_case,
         case when p_class is null then '{"status":"resolved"}'::jsonb
              else jsonb_build_object('status', 'resolved', 'classification', p_class) end,
         'checked in Stripe');
  perform tap.logout();
  return v;
end $f$;
CREATE FUNCTION tap._tx(n int, p_status text) RETURNS void LANGUAGE plpgsql AS $f$ begin
  perform set_config('app.bypass_transfer_guard', 'on', true);
  update public.transfers set status = p_status,
         expired_at = case when p_status = 'expired' then now() else expired_at end,
         seller_sent_at = case when p_status = 'seller_sent' then now() else seller_sent_at end
   where id = tap._t(n);
end $f$;

-- ── Section G — the owner's switch ──────────────────────────────────────────
SELECT is((SELECT value FROM ops.setting WHERE key = 'refund_resolution_detector_enabled'), 'false'::jsonb,
  'G1: the switch is seeded false (a boolean, so setting_set can flip it)');
SELECT tap._rr(1, 'pending', now() - interval '1 hour', NULL);
SELECT ok((SELECT r ->> 'status' = 'skipped' AND r #>> '{detail,reason}' = 'refund_resolution_disabled'
             FROM (SELECT tap._run211() AS r) x),
  'G2: while off, a cron run is skipped (refund_resolution_disabled)');
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT is(ops.run_job('refund_resolution', 'manual') #>> '{detail,reason}', 'refund_resolution_disabled',
  'G3: while off, a MANUAL run is skipped too (the owner''s switch, not an operator choice)');
SELECT tap.logout();
SELECT is(tap._ncases(1), 0, 'G4: while off, nothing is detected (R1 fixture present, no case)');
SELECT tap.login_service();
SELECT ok((SELECT r #>> '{results,refund_resolution,status}' = 'skipped' AND (r ->> 'jobs')::int = 13
             FROM (SELECT ops.run_all_detectors() AS r) x),
  'G5: run_all_detectors runs it in its order (13 jobs) and it reports skipped while off');
SELECT tap.logout();
UPDATE ops.setting SET value = 'true'::jsonb WHERE key = 'refund_resolution_detector_enabled';

-- ── Section S — one fixture per state ───────────────────────────────────────
-- 2: refunded BEFORE expiry (expiry skipped it)       3: the expiry job's own refund (id, +5 s) → no case
-- 4: webhook after expiry, no refund id               5: id + inside the window, but a console refund_execute
-- 6: self-heal at +11 min (the documented false R2)   7: refunded_at NULL (NULL-safe → R2)
-- 8/9/12: R3 seller_sent / buyer_confirmed / auto_released   10: disputed (excluded)   11: payout exists (R4)
SELECT tap._rr(2, 'expired', now() - interval '2 hours', 're_web_2', now() - interval '1 hour');
SELECT tap._rr(3, 'expired', now() - interval '1 hour' + interval '5 seconds', 're_exp_3', now() - interval '1 hour');
SELECT tap._rr(4, 'expired', now() - interval '1 hour' + interval '30 seconds', NULL, now() - interval '1 hour');
SELECT tap._rr(5, 'expired', now() - interval '1 hour' + interval '5 seconds', 're_con_5', now() - interval '1 hour');
INSERT INTO ops.action (idempotency_key, action_type, subject_kind, subject_id, requested_by, state)
VALUES ('k211-console-refund-5', 'refund_execute', 'payment', 'eeeeeeee-0000-0000-0000-000000000005', tap.admin_user(), 'succeeded');
SELECT tap._rr(6, 'expired', now() - interval '1 hour' + interval '11 minutes', 're_heal_6', now() - interval '1 hour');
SELECT tap._rr(7, 'expired', NULL, 're_x_7', now() - interval '1 hour');
SELECT tap._rr(8, 'seller_sent', now() - interval '3 hours', NULL);
SELECT tap._rr(9, 'buyer_confirmed', now() - interval '3 hours', NULL);
SELECT tap._rr(10, 'disputed', now() - interval '3 hours', NULL);
SELECT tap._rr(11, 'auto_released', now() - interval '3 hours', NULL, NULL, 'refunded', 'tr_paid_11');
SELECT tap._rr(12, 'auto_released', now() - interval '3 hours', NULL);

SELECT is(tap._run211() ->> 'status', 'succeeded', 'S1: with the switch on, run_job(refund_resolution) succeeds');
SELECT is(tap._state((tap._open(1)).id), 'R1', 'S2: pending + refunded → an open case in R1');
SELECT ok((SELECT c.priority = 'p2' AND c.due_at IS NULL AND c.detector = 'refund_resolution' AND c.subject_kind = 'transfer'
                  AND c.title = 'Refund recorded — support action needed' FROM tap._open(1) c),
  'S3: the case is p2, has NO due time, subject = the transfer');
SELECT is(tap._state((tap._open(2)).id), 'R2', 'S4: refunded before expiry (expiry skipped) → R2');
SELECT is(tap._ncases(3), 0, 'S5: the expiry job''s own refund (id, 5 s after expired_at) → no case');
SELECT is(tap._state((tap._open(4)).id), 'R2', 'S6: webhook refund after expiry without a refund id → R2');
SELECT is(tap._state((tap._open(5)).id), 'R2', 'S7: a console refund_execute for the payment → R2 even inside the window');
SELECT is(tap._state((tap._open(6)).id), 'R2', 'S8: a refund 11 min after expiry → R2 (documented false R2, safe side)');
SELECT is(tap._state((tap._open(7)).id), 'R2', 'S9: refunded_at NULL → R2 (uncertain never hides a case)');
SELECT is(tap._state((tap._open(8)).id), 'R3', 'S10: seller_sent + refunded, no payout → R3');
SELECT is(tap._state((tap._open(9)).id), 'R3', 'S11: buyer_confirmed + refunded, no payout → R3');
SELECT is(tap._state((tap._open(12)).id), 'R3', 'S12: auto_released + refunded, no payout → R3');
SELECT is(tap._ncases(10), 0, 'S13: a disputed transfer is excluded (the dispute flow owns it)');
SELECT is(tap._ncases(11), 0, 'S14: a payout exists + refunded → no refund-resolution case (R4 is not duplicated)');
SELECT is(tap._run211('reconciliation') ->> 'status', 'succeeded', 'S15: (witness) the reconciliation detector runs');
SELECT is((SELECT count(*)::int FROM ops."case" WHERE case_type = 'reconciliation_mismatch'
             AND subject_id = 'eeeeeeee-0000-0000-0000-000000000011' AND status = 'open'), 1,
  'S16: …and it owns fixture 11 (reconciliation_mismatch on the payment)');
SELECT ok((SELECT c.summary LIKE '%amount refunded: unknown%' AND c.summary LIKE 'R1:%' AND c.summary LIKE '%pi_rr_1%'
                  AND c.summary NOT LIKE '%@%' AND c.summary NOT LIKE '%+1305%' FROM tap._open(1) c),
  'S17: the summary states the state, the payment and "amount refunded: unknown", and no contact details');
SELECT ok((SELECT r #>> '{detail,opened}' = '0' AND r #>> '{detail,resolved}' = '0' FROM (SELECT tap._run211() AS r) x),
  'S18: a second run opens nothing and resolves nothing');
SELECT is((SELECT count(*)::int FROM ops.case_event e JOIN ops."case" c ON c.id = e.case_id
             WHERE c.case_type = 'refund_resolution' AND e.kind = 'state_changed'), 9,
  'S19: one state event per case (9 cases), none added by the second run');

-- ── Section T — transitions ─────────────────────────────────────────────────
-- while open: R1 → R2 on the same case; R3 → R4 pointer; leaving the states never resolves
SELECT tap._rr(18, 'pending', now() - interval '1 hour', NULL);
SELECT tap._rr(19, 'seller_sent', now() - interval '3 hours', NULL);
SELECT tap._rr(20, 'pending', now() - interval '1 hour', NULL);
SELECT tap._run211();
SELECT tap._tx(18, 'expired');
SELECT set_config('app.bypass_transfer_guard', 'on', true);
UPDATE public.transfers SET stripe_transfer_id = 'tr_late_19' WHERE id = tap._t(19);
SELECT tap._tx(20, 'disputed');
SELECT tap._run211();
SELECT ok((SELECT tap._state(c.id) = 'R2' AND tap._ncases(18) = 1 FROM tap._open(18) c),
  'T1: an open R1 case whose order expires moves to R2 — same case, still open (one case per transfer)');
SELECT ok((SELECT e.data ->> 'from' = 'R1' FROM ops.case_event e WHERE e.case_id = (tap._open(18)).id
             AND e.kind = 'state_changed' ORDER BY e.created_at DESC LIMIT 1),
  'T2: the state event records from R1 to R2');
SELECT ok((SELECT tap._state(c.id) = 'R4' AND c.summary LIKE 'R4:%reconciliation_mismatch%' FROM tap._open(19) c),
  'T3: an open R3 case whose transfer gets a payout records R4, points to reconciliation_mismatch, stays open');
SELECT is((SELECT status FROM tap._open(20)), 'open',
  'T4: a case whose transfer leaves the states (now disputed) is NEVER auto-resolved');

-- after closure (design §4). 13/14/15: R1 closed A / C / B, then the order expires. 16: R1 closed A, then sent.
-- 17: R1 closed A, still R1.
SELECT tap._rr(13, 'pending', now() - interval '1 hour', NULL);
SELECT tap._rr(14, 'pending', now() - interval '1 hour', NULL);
SELECT tap._rr(15, 'pending', now() - interval '1 hour', NULL);
SELECT tap._rr(16, 'pending', now() - interval '1 hour', NULL);
SELECT tap._rr(17, 'pending', now() - interval '1 hour', NULL);
SELECT tap._run211();
SELECT tap._close(13, 'A', 'k211-close-13-a');
SELECT tap._close(14, 'C', 'k211-close-14-c');
SELECT tap._close(15, 'B', 'k211-close-15-b');
SELECT tap._close(16, 'A', 'k211-close-16-a');
SELECT tap._close(17, 'A', 'k211-close-17-a');
SELECT tap._tx(13, 'expired');
SELECT tap._tx(14, 'expired');
SELECT tap._tx(15, 'expired');
SELECT tap._tx(16, 'seller_sent');
SELECT tap._run211();
SELECT ok(tap._ncases(13) = 1 AND tap._open(13) IS NULL,
  'T5: R1 closed as A (full) → the expiry (R2) does not reopen it');
SELECT ok(tap._ncases(14) = 1 AND tap._open(14) IS NULL,
  'T6: R1 closed as C (partial, cancelled, remainder refunded) → R2 does not reopen');
SELECT ok(tap._ncases(15) = 2 AND tap._state((tap._open(15)).id) = 'R2',
  'T7: R1 closed as B (fulfilment continues) → the expiry OPENS a new R2 case');
SELECT ok(tap._ncases(16) = 2 AND tap._state((tap._open(16)).id) = 'R3',
  'T8: R1 closed as A → tickets then marked sent OPENS a new R3 case');
SELECT ok(tap._ncases(17) = 1 AND tap._open(17) IS NULL,
  'T9: the same state after closure (still R1) is never reopened');
SELECT tap._run211();
SELECT ok(tap._ncases(15) = 2 AND tap._ncases(16) = 2 AND tap._ncases(17) = 1,
  'T10: another run changes nothing after those decisions');

-- ── Section C — closure through the real action entry point ─────────────────
SELECT tap._rr(21, 'pending', now() - interval '1 hour', NULL);
SELECT tap._run211();
SELECT ok((SELECT r ->> 'status' = 'rejected' AND r ->> 'message' LIKE '%classification (A, B or C)%'
             FROM (SELECT tap._close(21, NULL, 'k211-close-21-none') AS r) x),
  'C1: platform_support cannot close a refund-resolution case without a classification');
SELECT ok((SELECT r ->> 'status' = 'rejected' FROM (SELECT tap._close(21, 'D', 'k211-close-21-d') AS r) x),
  'C2: "D" (unresolved) is not a closing value');
SELECT is((SELECT status FROM tap._open(21)), 'open', 'C3: both refusals leave the case open');
SELECT is(tap._close(21, 'B', 'k211-close-21-b') ->> 'status', 'succeeded', 'C4: classification B closes it');
SELECT ok((SELECT c.status = 'resolved' AND c.resolution_note = '[B] checked in Stripe' AND c.resolved_by = tap.other_user()
             FROM ops."case" c WHERE c.case_type = 'refund_resolution' AND c.subject_id = tap._t(21)),
  'C5: resolved by support, the note carries the classification');
SELECT is((SELECT e.data ->> 'classification' FROM ops.case_event e JOIN ops."case" c ON c.id = e.case_id
             WHERE c.subject_id = tap._t(21) AND e.kind = 'status_changed' AND e.data ->> 'to' = 'resolved'), 'B',
  'C6: the status_changed event stores the classification');
-- R7: a pre-existing case type still dispatches exactly as before (A: pin one from 118; rebase note in the header)
CREATE TABLE tap.m211 (k text PRIMARY KEY, v jsonb);
CREATE FUNCTION tap._manual211() RETURNS jsonb LANGUAGE plpgsql AS $f$
declare r1 jsonb; r2 jsonb;
begin
  perform tap.login(tap.admin_user()); perform tap._aal2();
  r1 := ops.execute_action('k211-manual-create', 'case_create', 'none', NULL, '{"title":"211 manual","priority":"p3"}'::jsonb, 'test');
  r2 := ops.execute_action('k211-manual-close', 'case_status', 'case', (r1 #>> '{result,case_id}')::uuid,
                           '{"status":"resolved"}'::jsonb, 'done');
  perform tap.logout();
  return jsonb_build_object('create', r1, 'close', r2);
end $f$;
INSERT INTO tap.m211 SELECT 'manual', tap._manual211();
SELECT is((SELECT v #>> '{create,status}' FROM tap.m211 WHERE k = 'manual'), 'succeeded', 'C7: case_create still dispatches');
SELECT is((SELECT v #>> '{close,status}' FROM tap.m211 WHERE k = 'manual'), 'succeeded',
  'C8: a manual case still resolves with a reason only (no classification needed)');
SELECT ok((SELECT c.resolution_note = 'done' AND c.status = 'resolved' AND NOT (e.data ? 'classification')
             FROM ops."case" c JOIN ops.case_event e ON e.case_id = c.id AND e.kind = 'status_changed'
            WHERE c.id = (SELECT (v #>> '{create,result,case_id}')::uuid FROM tap.m211 WHERE k = 'manual')),
  'C9: …with its note and event unchanged (no classification key)');

-- ── catalogue ───────────────────────────────────────────────────────────────
SELECT ok((SELECT p.prosecdef AND p.proconfig = '{"search_path=\"\""}'
                  AND NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')
                  AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
                  AND NOT has_function_privilege('service_role', p.oid, 'EXECUTE')
             FROM pg_proc p WHERE p.oid = 'ops.detect_refund_resolution()'::regprocedure),
  'K1: the detector is SECURITY DEFINER, search_path empty, not executable by client roles (run_job calls it)');
SELECT ok((SELECT pg_get_constraintdef(oid) LIKE '%refund_resolution%' FROM pg_constraint WHERE conname = 'case_case_type_check')
      AND (SELECT pg_get_constraintdef(oid) LIKE '%state_changed%' FROM pg_constraint WHERE conname = 'case_event_kind_check'),
  'K2: both checks widened');
SELECT is((SELECT count(*)::int FROM ops."case" WHERE case_type = 'refund_resolution' AND due_at IS NOT NULL), 0,
  'K3: no refund-resolution case ever carries a due time');

SELECT * FROM finish();
ROLLBACK;

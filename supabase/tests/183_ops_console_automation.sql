-- ============================================================================
-- 183_ops_console_automation.sql — migration 117 (Operating Console automation).
--   Section A: transfer_deadlines — overdue case opened once (dedupe), the
--     p1 alert fires, the case auto-resolves when the condition clears, the
--     soon case carries due_at = expires_at.
--   Section B–K: one live scenario per detector (paid_unsettled, payout_review,
--     disputes ×2, refunds ×2, release_stuck both branches, reconciliation,
--     webhooks + backlog alert, reports incl. `reviewing` keep-alive,
--     notifications, jobs from ops.job_state).
--   Section L: the runner — unknown name, non-operator 42501, platform_admin
--     needs aal2, detectors_enabled=false → skipped (manual overrides),
--     backoff honoured for cron / ignored for manual, a body failure is
--     RECORDED (job_run failed, consecutive_failures, backoff_until) not raised.
--   Section M: refresh_metrics + build_daily_summary.
--   Section N: run_all_detectors, grants, cron registration, job_state seed.
-- Fixture writes bypass the 055/056 state guards exactly as the other suites
-- do (app.bypass_*_guard, transaction-local, reset by the 056c statement
-- trigger after every transfers UPDATE).
-- ============================================================================
BEGIN;
SELECT plan(65);
SELECT tap.seed_core();   -- inserts tap.admin_user() into public.admin_users

CREATE FUNCTION tap._aal2() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;
-- run one job as the service path (pg_cron / edge), then drop back to postgres
CREATE FUNCTION tap._run183(p_job text, p_trigger text DEFAULT 'cron') RETURNS jsonb LANGUAGE plpgsql AS $f$
declare v jsonb; begin perform tap.login_service(); v := ops.run_job(p_job, p_trigger); perform tap.logout(); return v; end $f$;
CREATE TABLE tap.memo_183 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store183(k text, v text) RETURNS void
LANGUAGE sql AS $m$ INSERT INTO tap.memo_183 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fetch183(k text) RETURNS text LANGUAGE sql AS $m$ SELECT v FROM tap.memo_183 WHERE k=$1 $m$;
CREATE FUNCTION tap._case183(p_type text, p_subject uuid) RETURNS ops."case" LANGUAGE sql AS $f$
  select c.* from ops."case" c where c.case_type = p_type and c.subject_id = p_subject order by c.created_at desc limit 1 $f$;

-- ── Section A — transfer_deadlines ──────────────────────────────────────────
SELECT set_config('app.bypass_transfer_guard', 'on', true);
UPDATE public.transfers SET expires_at = now() - interval '1 hour' WHERE id = tap.transfer_a();

SELECT is(tap._run183('transfer_deadlines') ->> 'status', 'succeeded',
  'A1: run_job(transfer_deadlines, cron) as service_role succeeds');
SELECT is((SELECT count(*)::int FROM ops."case"
            WHERE case_type = 'transfer_overdue' AND subject_id = tap.transfer_a() AND subject_kind = 'transfer'
              AND status = 'open' AND priority = 'p1' AND detector = 'transfer_deadlines'), 1,
  'A2: exactly one OPEN p1 transfer_overdue case for transfer_a');
SELECT ok(EXISTS (SELECT 1 FROM ops.case_event e JOIN ops."case" c ON c.id = e.case_id
                   WHERE c.case_type = 'transfer_overdue' AND c.subject_id = tap.transfer_a() AND e.kind = 'created'),
  'A3: the case carries a `created` event');
SELECT is((SELECT state FROM ops.alert WHERE alert_key = 'case:transfer_overdue:' || tap.transfer_a()::text), 'firing',
  'A4: a p1 case opening fires alert case:<dedupe_key>');
SELECT is(tap._run183('transfer_deadlines') #>> '{detail,opened}', '0',
  'A5: a second run opens nothing (dedupe by case_type:subject)');
SELECT is((SELECT count(*)::int FROM ops."case" WHERE dedupe_key = 'transfer_overdue:' || tap.transfer_a()::text), 1,
  'A6: still exactly one case row for that dedupe key');

SELECT set_config('app.bypass_transfer_guard', 'on', true);
UPDATE public.transfers SET expires_at = now() + interval '48 hours' WHERE id = tap.transfer_a();
SELECT tap._run183('transfer_deadlines');
SELECT is((tap._case183('transfer_overdue', tap.transfer_a())).status, 'resolved',
  'A7: condition cleared → the case auto-resolves');
SELECT ok(EXISTS (SELECT 1 FROM ops.case_event e WHERE e.case_id = (tap._case183('transfer_overdue', tap.transfer_a())).id
                   AND e.kind = 'auto_resolved' AND e.actor IS NULL),
  'A8: an actor-less `auto_resolved` event was appended');
SELECT is((SELECT state FROM ops.alert WHERE alert_key = 'case:transfer_overdue:' || tap.transfer_a()::text), 'recovered',
  'A9: the case alert recovered with it');

SELECT set_config('app.bypass_transfer_guard', 'on', true);
UPDATE public.transfers SET expires_at = now() + interval '2 hours' WHERE id = tap.transfer_a();
SELECT tap._run183('transfer_deadlines');
SELECT is((tap._case183('transfer_deadline_soon', tap.transfer_a())).due_at,
          (SELECT expires_at FROM public.transfers WHERE id = tap.transfer_a()),
  'A10: inside the soon window → transfer_deadline_soon with due_at = expires_at');
SELECT is((tap._case183('transfer_deadline_soon', tap.transfer_a())).priority, 'p2', 'A11: …at p2');

-- ── Section B — paid_unsettled ──────────────────────────────────────────────
-- payment_a is succeeded but listing_a is still `active` (fixture). Age it past
-- the grace window; payment_b stays fresh and must NOT be flagged.
UPDATE public.payments SET paid_at = now() - interval '1 hour' WHERE id = tap.payment_a();
SELECT is(tap._run183('paid_unsettled') #>> '{detail,opened}', '1',
  'B1: one paid_unsettled case opened (payment_b is inside the grace window)');
SELECT ok((tap._case183('paid_unsettled', tap.payment_a())).priority = 'p1'
          AND (tap._case183('paid_unsettled', tap.payment_a())).summary LIKE '%listing.status is active%'
          AND (tap._case183('paid_unsettled', tap.payment_a())).summary LIKE '%$110.00%',
  'B2: p1, summary names the failed invariant and the amount');
SELECT set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.listings SET status = 'sold', sold_at = now() WHERE id = tap.listing_a();
SELECT set_config('app.bypass_listing_guard', 'off', true);
SELECT tap._run183('paid_unsettled');
SELECT is((tap._case183('paid_unsettled', tap.payment_a())).status, 'resolved',
  'B3: listing sold → paid_unsettled auto-resolves');

-- ── Section C — payout_review ───────────────────────────────────────────────
SELECT set_config('app.bypass_transfer_guard', 'on', true);
UPDATE public.transfers SET payout_review_status = 'manual_review' WHERE id = tap.transfer_b();
SELECT tap._run183('payout_review');
SELECT is((tap._case183('payout_review', tap.transfer_b())).due_at,
          (SELECT auto_release_at FROM public.transfers WHERE id = tap.transfer_b()),
  'C1: manual_review seller_sent transfer → payout_review case, due_at = auto_release_at');

-- ── Section D — disputes ────────────────────────────────────────────────────
SELECT set_config('app.bypass_transfer_guard', 'on', true);
UPDATE public.transfers SET status = 'disputed', disputed_at = now(), dispute_reason = 'never_received' WHERE id = tap.transfer_b();
SELECT tap._run183('disputes');
SELECT ok((tap._case183('dispute_open', tap.transfer_b())).status = 'open'
          AND (tap._case183('dispute_open', tap.transfer_b())).priority = 'p1'
          AND (tap._case183('dispute_open', tap.transfer_b())).due_at BETWEEN now() + interval '71 hours' AND now() + interval '73 hours',
  'D1: open dispute → p1 dispute_open with due_at = disputed_at + dispute_sla_hours (72)');

INSERT INTO public.disputes (id, stripe_dispute_id, stripe_charge_id, payment_id, transfer_id, amount, reason, status, evidence_due_by)
VALUES ('dddddddd-0000-0000-0000-000000000183', 'dp_tap183', 'ch_tap183', tap.payment_b(), tap.transfer_b(), 11000, 'fraudulent', 'needs_response', now() + interval '24 hours');
SELECT tap._run183('disputes');
SELECT ok((tap._case183('dispute_evidence_due', 'dddddddd-0000-0000-0000-000000000183')).priority = 'p1'
          AND (tap._case183('dispute_evidence_due', 'dddddddd-0000-0000-0000-000000000183')).subject_kind = 'dispute'
          AND (tap._case183('dispute_evidence_due', 'dddddddd-0000-0000-0000-000000000183')).due_at
              = (SELECT evidence_due_by FROM public.disputes WHERE stripe_dispute_id = 'dp_tap183'),
  'D2: Stripe dispute with evidence due < 72h → p1 dispute_evidence_due, due_at = evidence_due_by');

SELECT set_config('app.bypass_transfer_guard', 'on', true);
UPDATE public.transfers SET dispute_resolution = 'resolved_buyer_refunded', dispute_resolved_at = now(), dispute_resolved_by = tap.admin_user()
 WHERE id = tap.transfer_b();
SELECT tap._run183('disputes');
SELECT is((tap._case183('dispute_open', tap.transfer_b())).status, 'resolved',
  'D3: dispute resolved → dispute_open auto-resolves');

-- ── Section E — refunds ─────────────────────────────────────────────────────
SELECT tap._run183('refunds');
SELECT ok((tap._case183('refund_pending', tap.payment_b())).status = 'open'
          AND (tap._case183('refund_pending', tap.payment_b())).priority = 'p1'
          AND (tap._case183('refund_pending', tap.payment_b())).summary LIKE '%resolved_buyer_refunded%',
  'E1: buyer-win resolution with payment still succeeded → p1 refund_pending on the payment');
INSERT INTO ops.action (idempotency_key, action_type, subject_kind, subject_id, requested_by, state, error, completed_at)
VALUES ('tap183-refund-fail', 'refund_execute', 'payment', tap.payment_a(), tap.admin_user(), 'failed', 'stripe: card_declined', now());
SELECT tap._run183('refunds');
SELECT ok((tap._case183('refund_failed', tap.payment_a())).status = 'open'
          AND (tap._case183('refund_failed', tap.payment_a())).summary LIKE '%card_declined%',
  'E2: a failed refund_execute action → refund_failed case naming the error');

-- ── Section F — release_stuck (both branches, same dedupe key) ──────────────
SELECT set_config('app.bypass_transfer_guard', 'on', true);
UPDATE public.transfers SET status = 'buyer_confirmed', seller_sent_at = now() - interval '3 hours', buyer_confirmed_at = now() - interval '2 hours'
 WHERE id = tap.transfer_a();
SELECT tap._run183('release_stuck');
SELECT ok((tap._case183('release_stuck', tap.transfer_a())).status = 'open'
          AND (tap._case183('release_stuck', tap.transfer_a())).summary LIKE '%awaiting release%',
  'F1: buyer_confirmed 2h ago, not released → release_stuck');
SELECT set_config('app.bypass_transfer_guard', 'on', true);
UPDATE public.transfers SET payout_released_at = now() - interval '1 hour' WHERE id = tap.transfer_a();
SELECT tap._run183('release_stuck');
SELECT ok((SELECT count(*) FROM ops."case" WHERE dedupe_key = 'release_stuck:' || tap.transfer_a()::text) = 1
          AND (tap._case183('release_stuck', tap.transfer_a())).status = 'open'
          AND (tap._case183('release_stuck', tap.transfer_a())).summary LIKE '%no provider transfer id%',
  'F2: released locally without stripe_transfer_id → SAME case, summary re-labelled');
SELECT set_config('app.bypass_transfer_guard', 'on', true);
UPDATE public.transfers SET stripe_transfer_id = 'tr_tap183' WHERE id = tap.transfer_a();
SELECT tap._run183('release_stuck');
SELECT is((tap._case183('release_stuck', tap.transfer_a())).status, 'resolved',
  'F3: provider transfer id landed → release_stuck auto-resolves');

-- ── Section G — reconciliation ──────────────────────────────────────────────
UPDATE public.payments SET total = 12345 WHERE id = tap.payment_d();   -- amount 10000 + buyer_fee 1000 ≠ 12345
SELECT tap._run183('reconciliation');
SELECT ok((tap._case183('reconciliation_mismatch', tap.payment_d())).priority = 'p1'
          AND (tap._case183('reconciliation_mismatch', tap.payment_d())).summary LIKE '%total 12345 <> amount 10000 + buyer_fee 1000%',
  'G1: total ≠ amount + buyer_fee → p1 reconciliation_mismatch');

-- ── Section H — webhooks + backlog alert ────────────────────────────────────
INSERT INTO public.stripe_webhook_events (event_id, event_type, received_at, processed)
VALUES ('evt_tap183_stuck', 'charge.refunded', now() - interval '1 hour', false);
SELECT tap._run183('webhooks');
SELECT is((SELECT count(*)::int FROM ops."case"
            WHERE case_type = 'webhook_stuck' AND subject_kind = 'webhook_event' AND subject_ref = 'evt_tap183_stuck'
              AND subject_id IS NULL AND status = 'open' AND priority = 'p2'), 1,
  'H1: unprocessed event older than webhook_stuck_minutes → webhook_stuck keyed by event_id');
SELECT ok((SELECT state = 'firing' AND (payload ->> 'count') = '1' FROM ops.alert WHERE alert_key = 'webhook_backlog'),
  'H2: webhook_backlog alert firing with the backlog count');
UPDATE public.stripe_webhook_events SET processed = true, processed_at = now() WHERE event_id = 'evt_tap183_stuck';
SELECT tap._run183('webhooks');
SELECT ok((SELECT status FROM ops."case" WHERE dedupe_key = 'webhook_stuck:evt_tap183_stuck') = 'resolved'
          AND (SELECT state FROM ops.alert WHERE alert_key = 'webhook_backlog') = 'recovered',
  'H3: processed → case auto-resolved and the backlog alert recovered');

-- ── Section I — reports ─────────────────────────────────────────────────────
INSERT INTO public.reports (id, reporter_id, target_type, target_id, reason, status)
VALUES ('eeeeeeee-0000-0000-0000-000000000183', tap.buyer(), 'listing', tap.listing_b(), 'fraud_or_scam', 'pending');
SELECT tap._run183('reports');
SELECT is((tap._case183('report_review', 'eeeeeeee-0000-0000-0000-000000000183')).priority, 'p3',
  'I1: pending report → p3 report_review');
UPDATE public.reports SET status = 'reviewing' WHERE id = 'eeeeeeee-0000-0000-0000-000000000183';
SELECT tap._run183('reports');
SELECT is((tap._case183('report_review', 'eeeeeeee-0000-0000-0000-000000000183')).status, 'open',
  'I2: a report moved to `reviewing` keeps its case open (report_resolve closes it on actioned/dismissed)');
UPDATE public.reports SET status = 'dismissed', resolved_at = now() WHERE id = 'eeeeeeee-0000-0000-0000-000000000183';
SELECT tap._run183('reports');
SELECT is((tap._case183('report_review', 'eeeeeeee-0000-0000-0000-000000000183')).status, 'resolved',
  'I3: dismissed → auto-resolved');

-- ── Section J — notifications ───────────────────────────────────────────────
INSERT INTO notify.notification (notification_id, recipient_id, type_key, template_key, params, target_kind)
VALUES ('ffffffff-0000-0000-0000-000000000183', tap.buyer(), 'purchase_confirmed', 'purchase_confirmed', '{}'::jsonb, 'none');
INSERT INTO notify.delivery (delivery_id, notification_id, channel, state, attempt, last_error)
VALUES ('ffffffff-0000-0000-0000-000000000184', 'ffffffff-0000-0000-0000-000000000183', 'push', 'dead', 5, 'DeviceNotRegistered');
SELECT tap._run183('notifications');
SELECT ok((tap._case183('notification_failure', 'ffffffff-0000-0000-0000-000000000184')).priority = 'p3'
          AND (tap._case183('notification_failure', 'ffffffff-0000-0000-0000-000000000184')).subject_kind = 'notification'
          AND (tap._case183('notification_failure', 'ffffffff-0000-0000-0000-000000000184')).summary LIKE '%DeviceNotRegistered%',
  'J1: dead delivery → p3 notification_failure per delivery');

-- ── Section K — jobs (ops.job_state arm; cron.job_run_details is optional) ──
UPDATE ops.job_state SET consecutive_failures = 3, last_error = 'boom' WHERE job_name = 'notifications';
SELECT tap._run183('jobs');
SELECT is((SELECT count(*)::int FROM ops."case"
            WHERE case_type = 'job_failure' AND subject_kind = 'job' AND subject_ref = 'ops:notifications' AND status = 'open'), 1,
  'K1: ops job with ≥3 consecutive failures → job_failure keyed ops:<job_name>');
SELECT is((SELECT state FROM ops.alert WHERE alert_key = 'job_failure:ops:notifications'), 'firing',
  'K2: job_failure alert firing');
UPDATE ops.job_state SET consecutive_failures = 0, last_error = NULL WHERE job_name = 'notifications';
SELECT tap._run183('jobs');
SELECT ok((SELECT status FROM ops."case" WHERE dedupe_key = 'job_failure:ops:notifications') = 'resolved'
          AND (SELECT state FROM ops.alert WHERE alert_key = 'job_failure:ops:notifications') = 'recovered',
  'K3: recovered → case auto-resolved, alert recovered');

-- ── Section L — the runner ──────────────────────────────────────────────────
SELECT tap.login_service();
SELECT throws_like($$SELECT ops.run_job('nonexistent', 'cron')$$, '%invalid_input%',
  'L1: unknown job name → invalid_input');
SELECT throws_like($$SELECT ops.run_job('reports', 'whenever')$$, '%invalid_input%',
  'L2: unknown trigger → invalid_input');
SELECT tap.logout();

SELECT tap.login(tap.other_user());
SELECT throws_ok($$SELECT ops.run_job('reports', 'manual')$$, '42501',
  NULL, 'L3: a non-operator authenticated user is refused (42501)');
SELECT tap.logout();

SELECT tap.login(tap.admin_user());   -- platform_admin, no aal claim
SELECT throws_like($$SELECT ops.run_job('reports', 'manual')$$, '%step_up%',
  'L4: platform_admin without aal2 → step-up required');
SELECT tap._aal2();
SELECT is(ops.run_job('reports', 'manual') ->> 'status', 'succeeded',
  'L5: platform_admin + aal2 may run a job manually (the job_retry path)');
SELECT tap.logout();

UPDATE ops.setting SET value = 'false'::jsonb WHERE key = 'detectors_enabled';
SELECT is(tap._run183('reports', 'cron') ->> 'status', 'skipped',
  'L6: detectors_enabled=false → cron run skipped');
SELECT is((SELECT detail ->> 'reason' FROM ops.job_run WHERE job_name = 'reports' AND status = 'skipped'
            ORDER BY started_at DESC LIMIT 1), 'detectors_disabled',
  'L7: …recorded as a job_run row status=skipped, reason detectors_disabled');
SELECT is(tap._run183('reports', 'manual') ->> 'status', 'succeeded',
  'L8: a manual trigger ignores detectors_enabled');
UPDATE ops.setting SET value = 'true'::jsonb WHERE key = 'detectors_enabled';

UPDATE ops.job_state SET consecutive_failures = 2, backoff_until = now() + interval '1 hour' WHERE job_name = 'payout_review';
SELECT is(tap._run183('payout_review', 'cron') #>> '{detail,reason}', 'backoff',
  'L9: cron trigger honours job_state.backoff_until');
SELECT is(tap._run183('payout_review', 'manual') ->> 'status', 'succeeded',
  'L10a: manual trigger ignores backoff');
SELECT ok((SELECT consecutive_failures = 0 AND backoff_until IS NULL AND last_success_at IS NOT NULL
             FROM ops.job_state WHERE job_name = 'payout_review'),
  'L10b: …and its success resets failures and clears backoff');

-- a real body failure: make the reports detector's INSERT violate a check
INSERT INTO public.reports (id, reporter_id, target_type, target_id, reason, status)
VALUES ('eeeeeeee-0000-0000-0000-000000000184', tap.buyer(), 'listing', tap.listing_d(), 'misleading', 'pending');
ALTER TABLE ops."case" ADD CONSTRAINT tap183_fail CHECK (case_type <> 'report_review') NOT VALID;
SELECT tap._store183('fail_run', tap._run183('reports', 'cron')::text);
SELECT is(tap._fetch183('fail_run')::jsonb ->> 'status', 'failed',
  'L11: a body error is returned as status=failed, never raised');
SELECT ok((SELECT status = 'failed' AND error LIKE '23514%' AND finished_at IS NOT NULL
             FROM ops.job_run WHERE id = (tap._fetch183('fail_run')::jsonb ->> 'job_run_id')::uuid)
          AND (SELECT consecutive_failures = 1 AND last_error LIKE '23514%'
                     AND backoff_until BETWEEN now() + interval '1 minute' AND now() + interval '3 minutes'
                 FROM ops.job_state WHERE job_name = 'reports'),
  'L12: job_run failed + error; job_state failures=1, backoff_until ≈ now()+2 min (2^1)');
ALTER TABLE ops."case" DROP CONSTRAINT tap183_fail;
SELECT is(tap._run183('reports', 'manual') ->> 'status', 'succeeded', 'L13a: the body succeeds once the fault is gone');
SELECT ok((SELECT consecutive_failures = 0 AND backoff_until IS NULL AND last_error IS NULL FROM ops.job_state WHERE job_name = 'reports'),
  'L13b: …resetting failures and clearing the backoff');

-- ── Section M — metrics + daily summary ─────────────────────────────────────
SELECT is(tap._run183('refresh_metrics') ->> 'status', 'succeeded', 'M1: refresh_metrics runs through run_job');
SELECT cmp_ok((SELECT count(*)::int FROM ops.metric_snapshot), '>=', 6, 'M2: ≥ 6 metric_snapshot rows');
SELECT is((SELECT (value #>> '{all_time,cents}')::int FROM ops.metric_snapshot WHERE key = 'money.gross_captured'), 22000,
  'M3: gross captured = Σ total of succeeded+refunded payments (pending payment_d excluded)');
SELECT is(tap._run183('daily_summary') ->> 'status', 'succeeded', 'M4: daily_summary runs through run_job');
SELECT ok((SELECT body ? 'cases' AND body ? 'money' AND body ? 'deadlines' AND body ? 'jobs' AND body ? 'alerts_firing'
             AND delivery_state = 'portal_only'
             FROM ops.daily_summary WHERE summary_date = (now() at time zone 'utc')::date),
  'M5: today''s row written with the documented body sections, portal_only');
SELECT ok((SELECT (body #>> '{cases,opened_24h}')::int >= 10 AND (body #>> '{money,live_24h,captured_cents}')::int = 22000
             AND (body #>> '{money,live_24h,refunds_pending_count}')::int = 1
             FROM ops.daily_summary WHERE summary_date = (now() at time zone 'utc')::date),
  'M6: summary counts reflect this transaction''s cases and money');

-- ── Section N — run_all_detectors, grants, registration, seed ───────────────
SELECT tap.login_service();
SELECT ok((r ->> 'jobs')::int = 12 AND (r ->> 'failed')::int = 0 AND (r ->> 'skipped')::int = 0,
  'N1: run_all_detectors runs the 11 detectors + refresh_metrics, none failing or skipped')
  FROM (SELECT ops.run_all_detectors() AS r) x;
SELECT tap.logout();
SELECT is(has_function_privilege('anon', 'ops.run_job(text,text)', 'EXECUTE'), false, 'N2: anon cannot execute run_job');
SELECT is(has_function_privilege('authenticated', 'ops.run_job(text,text)', 'EXECUTE'), true, 'N3: authenticated can (it authorizes itself)');
SELECT is(has_function_privilege('service_role', 'ops.run_job(text,text)', 'EXECUTE'), true, 'N4: service_role can');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'ops' AND p.proname LIKE 'detect\_%'), 13,
  'N5: 11 detect_* bodies + detect_case + detect_sweep exist');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'ops'
              AND (p.proname LIKE 'detect\_%' OR p.proname IN ('refresh_metrics','build_daily_summary','alert_fire','alert_recover',
                                                              'alert_recover_stale','setting_int','setting_bool','cron_interval_minutes'))
              AND (has_function_privilege('authenticated', p.oid, 'EXECUTE')
                   OR has_function_privilege('anon', p.oid, 'EXECUTE')
                   OR has_function_privilege('service_role', p.oid, 'EXECUTE'))), 0,
  'N6: no job body or helper is executable by any client role');
SELECT is(has_function_privilege('authenticated', 'ops.run_all_detectors()', 'EXECUTE'), false,
  'N7: run_all_detectors is the cron entry — not an authenticated surface');
SELECT is((SELECT count(*)::int FROM cron.job WHERE (jobname, schedule) IN (('ops-detect-tick', '*/5 * * * *'), ('ops-daily-summary', '0 13 * * *'))), 2,
  'N8: both cron jobs registered with the documented schedules');
SELECT is((SELECT count(*)::int FROM cron.job WHERE jobname LIKE 'ops-%'), 2, 'N9: …and no duplicates');
SELECT is((SELECT count(*)::int FROM ops.job_state WHERE enabled), 13, 'N10: job_state seeded for all 13 job names');

SELECT * FROM finish();
ROLLBACK;

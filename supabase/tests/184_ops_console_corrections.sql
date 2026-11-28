-- ============================================================================
-- 184_ops_console_corrections.sql — migration 118 (Operating Console corrections).
--   A: denial + approval contract at the RPC — an unknown decision never
--      approves; deny leaves the domain untouched (transfer, payout_decisions);
--      a later approve on a denied action is stale_state; executor_claim is
--      refund-only (wrong_type).
--   C: refunds are full-only — amount_cents <> total is rejected up front
--      (not_supported, no approval parked); {} parks an approval; the second
--      founder's approval hands off to ops-refund-execute with the payment total.
--   B: console pause (ops.setting actions_enabled=false) — every mutation
--      throws console_actions_paused, reads (whoami, list_cases) still work,
--      the executor is refused `paused`.
--   D: executor_claim — lease (claim_busy), service_role only, resume after an
--      expired lease reports previously_sent, re-checks disabled / paused /
--      approval hash at claim time.
--   E: record_action_outcome is monotonic — terminal states never regress,
--      provider_ref is pinned, replays are idempotent; processing⇄unknown is
--      the only two-way edge.
--   F: detect_refunds — a crash left at `processing` with an expired lease
--      opens refund_failed; a live lease does not; succeeded_at_provider is
--      completed to succeeded once the payment is refunded (webhook).
--   G: money honesty — refunded_volume carries no value_cents (uncertain,
--      upper bound only), in money_overview and in the metric snapshot.
--   H: founder evidence access — the `proof-docs operator read` storage
--      policy (operator + aal2 + referenced object only) and
--      ops.evidence_access() (record-resolved path, audited, slot-validated).
--
-- Founders: A = tap.admin_user() (seed_core), B = tap.other_user() (inserted
-- into public.admin_users below). Stranger = a fresh auth.users row that is
-- neither an operator nor a party to any transfer.
-- Every ops table is unreadable by client roles, so table-level assertions run
-- as postgres (after tap.logout()); RPC results are parked in a memo table.
-- Sections run in the order A, C, B, D, E, F, G, H: B needs the processing
-- refund action that C creates.
-- ============================================================================
BEGIN;
SELECT plan(90);
SELECT tap.seed_core();

INSERT INTO public.admin_users (user_id, label) VALUES (tap.other_user(), 'FOUNDER B') ON CONFLICT (user_id) DO NOTHING;

CREATE TABLE tap.memo_184 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store184(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_184 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fetch184(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_184 WHERE k=$1 $m$;
CREATE FUNCTION tap._j184(k text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v::jsonb FROM tap.memo_184 WHERE k=$1 $m$;
CREATE FUNCTION tap._aal2() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;
-- service-path wrappers (edge function / pg_cron), called from the postgres state
CREATE FUNCTION tap._run184(p_job text, p_trigger text DEFAULT 'manual') RETURNS jsonb LANGUAGE plpgsql AS $f$
declare v jsonb; begin perform tap.login_service(); v := ops.run_job(p_job, p_trigger); perform tap.logout(); return v; end $f$;
CREATE FUNCTION tap._claim184(p_action uuid) RETURNS jsonb LANGUAGE plpgsql AS $f$
declare v jsonb; begin perform tap.login_service(); v := ops.executor_claim(p_action); perform tap.logout(); return v; end $f$;
CREATE FUNCTION tap._outcome184(p_action uuid, p_state text, p_result jsonb, p_error text, p_ref text) RETURNS jsonb LANGUAGE plpgsql AS $f$
declare v jsonb; begin perform tap.login_service(); v := ops.record_action_outcome(p_action, p_state, p_result, p_error, p_ref); perform tap.logout(); return v; end $f$;

-- ── Section A — denial + approval contract ──────────────────────────────────
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store184('r_a1', ops.execute_action('k184-payout-b-0001','payout_release','transfer',tap.transfer_b(),
  '{}'::jsonb, 'release after evidence review')::text);
SELECT is((tap._j184('r_a1') ->> 'status'), 'awaiting_approval', 'A1: payout_release on transfer_b => awaiting_approval');
SELECT tap._store184('act_a1', tap._j184('r_a1') ->> 'action_id');
SELECT tap._store184('appr_a1', tap._j184('r_a1') ->> 'approval_id');
SELECT tap.logout();

SELECT tap.login(tap.other_user()); SELECT tap._aal2();
SELECT throws_like(format($$SELECT ops.approve_action(%L,'reject','x')$$, tap._fetch184('act_a1')), '%invalid_input%',
  'A2: an unknown decision (reject) is refused as invalid_input — it never approves');
SELECT tap.logout();
SELECT is((SELECT (state, decided_by) FROM ops.approval WHERE id = tap._fetch184('appr_a1')::uuid), ('pending'::text, NULL::uuid),
  'A3: the approval is still pending and undecided after the bad decision');

SELECT tap.login(tap.other_user()); SELECT tap._aal2();
SELECT tap._store184('r_a2', ops.approve_action(tap._fetch184('act_a1')::uuid, 'deny', 'no')::text);
SELECT is((tap._j184('r_a2') ->> 'status'), 'rejected', 'A4: deny => status rejected');
SELECT is((tap._j184('r_a2') ->> 'reject_reason'), 'denied', 'A5: ...reject_reason = denied');
SELECT tap.logout();
SELECT is((SELECT (state, decided_by, reason) FROM ops.approval WHERE id = tap._fetch184('appr_a1')::uuid),
  ('denied'::text, tap.other_user(), 'no'::text), 'A6: ops.approval denied, decided_by founder B, reason recorded');
SELECT is((SELECT (state, reject_reason, completed_at IS NOT NULL) FROM ops.action WHERE id = tap._fetch184('act_a1')::uuid),
  ('rejected'::text, 'denied'::text, true), 'A7: ops.action rejected / denied / completed');
SELECT is((SELECT (status, payout_released_at) FROM public.transfers WHERE id = tap.transfer_b()), ('seller_sent'::text, NULL::timestamptz),
  'A8: transfer_b is still seller_sent with payout_released_at null (domain op did not run)');
SELECT is((SELECT count(*)::int FROM public.payout_decisions WHERE transfer_id = tap.transfer_b()), 0,
  'A9: no payout_decisions row for transfer_b');
SELECT is((SELECT count(*)::int FROM ops.audit WHERE action = 'approval.denied' AND action_id = tap._fetch184('act_a1')::uuid
             AND actor = tap.other_user() AND outcome = 'denied'), 1,
  'A10: audit has approval.denied for the action, actor = founder B');

SELECT tap.login(tap.other_user()); SELECT tap._aal2();
SELECT tap._store184('r_a3', ops.approve_action(tap._fetch184('act_a1')::uuid, 'approve', 'changed my mind')::text);
SELECT is((tap._j184('r_a3') ->> 'status'), 'rejected', 'A11: a later approve on the denied action => rejected');
SELECT is((tap._j184('r_a3') ->> 'reject_reason'), 'stale_state', 'A12: ...reject_reason = stale_state (no pending approval)');
SELECT tap.logout();
SELECT is((SELECT (status, payout_released_at IS NULL) FROM public.transfers WHERE id = tap.transfer_b()), ('seller_sent'::text, true),
  'A13: transfer_b still untouched after the late approve');
SELECT tap._store184('r_a4', tap._claim184(tap._fetch184('act_a1')::uuid)::text);
SELECT is((tap._j184('r_a4') ->> 'status', tap._j184('r_a4') ->> 'reason'), ('refused'::text, 'wrong_type'::text),
  'A14: executor_claim on a payout_release action => refused wrong_type (refund-only)');

-- ── Section C — refunds: full only ──────────────────────────────────────────
UPDATE ops.setting SET value = 'true'::jsonb WHERE key = 'refund_execute_enabled';
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store184('r_c1', ops.execute_action('k184-refund-part-01','refund_execute','payment',tap.payment_a(),
  '{"amount_cents": 1}'::jsonb, 'partial refund attempt')::text);
SELECT is((tap._j184('r_c1') ->> 'status'), 'rejected', 'C1: refund_execute with amount_cents <> total => rejected');
SELECT is((tap._j184('r_c1') ->> 'reject_reason'), 'not_supported', 'C2: ...reject_reason = not_supported (partials refused)');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM ops.approval WHERE action_id = (tap._j184('r_c1') ->> 'action_id')::uuid), 0,
  'C3: ...and no approval row was parked for the partial');

SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store184('r_c2', ops.execute_action('k184-refund-full-01','refund_execute','payment',tap.payment_a(),
  '{}'::jsonb, 'buyer never received tickets')::text);
SELECT is((tap._j184('r_c2') ->> 'status'), 'awaiting_approval', 'C4: refund_execute with {} (full) => awaiting_approval');
SELECT tap._store184('act_c2', tap._j184('r_c2') ->> 'action_id');
SELECT tap.logout();
SELECT tap.login(tap.other_user()); SELECT tap._aal2();
SELECT tap._store184('r_c3', ops.approve_action(tap._fetch184('act_c2')::uuid, 'approve', 'ok')::text);
SELECT is((tap._j184('r_c3') ->> 'status'), 'processing', 'C5: founder B approves => processing (edge handoff)');
SELECT is((tap._j184('r_c3') #>> '{result,handoff}'), 'ops-refund-execute', 'C6: result.handoff = ops-refund-execute');
SELECT tap.logout();
SELECT is((tap._j184('r_c3') #>> '{result,amount_cents}')::int, (SELECT total FROM public.payments WHERE id = tap.payment_a()),
  'C7: result.amount_cents = the payment total (read as postgres; payments is RLS-hidden from founders)');
SELECT is((SELECT (state, claimed_until, attempt) FROM ops.action WHERE id = tap._fetch184('act_c2')::uuid),
  ('processing'::text, NULL::timestamptz, 0), 'C8: action row is processing, unclaimed, attempt 0');

-- ── Section B — console pause ───────────────────────────────────────────────
UPDATE ops.setting SET value = 'false'::jsonb WHERE key = 'actions_enabled';
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT throws_like($$SELECT ops.execute_action('k184-paused-case-01','case_create','none',NULL,'{"title":"x"}'::jsonb,'r')$$,
  '%console_actions_paused%', 'B1: execute_action while paused throws console_actions_paused');
SELECT throws_like(format($$SELECT ops.approve_action(%L,'approve','x')$$, tap._fetch184('act_c2')),
  '%console_actions_paused%', 'B2: approve_action while paused throws console_actions_paused');
SELECT is((ops.whoami() ->> 'role'), 'platform_admin', 'B3: ops.whoami() still works while paused');
SELECT is(jsonb_typeof(ops.list_cases()), 'object', 'B4: ops.list_cases() still works while paused (reads available)');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM ops.action WHERE idempotency_key = 'k184-paused-case-01'), 0,
  'B5: the paused request left no action row');
SELECT tap._store184('r_b1', tap._claim184(tap._fetch184('act_c2')::uuid)::text);
SELECT is((tap._j184('r_b1') ->> 'status', tap._j184('r_b1') ->> 'reason'), ('refused'::text, 'paused'::text),
  'B6: executor_claim while paused => refused paused');
UPDATE ops.setting SET value = 'true'::jsonb WHERE key = 'actions_enabled';
SELECT is((SELECT value FROM ops.setting WHERE key = 'actions_enabled'), 'true'::jsonb, 'B7: actions_enabled restored to true');

-- ── Section D — executor_claim ──────────────────────────────────────────────
SELECT tap._store184('r_d1', tap._claim184(tap._fetch184('act_c2')::uuid)::text);
SELECT is((tap._j184('r_d1') ->> 'status'), 'claimed', 'D1: first claim => claimed');
SELECT is((tap._j184('r_d1') ->> 'amount_cents', tap._j184('r_d1') ->> 'currency'), ('11000'::text, 'usd'::text),
  'D2: claim carries amount_cents = payments.total and currency usd');
SELECT is((tap._j184('r_d1') ->> 'previously_sent')::boolean, false, 'D3: previously_sent = false on the first attempt');
SELECT is((tap._j184('r_d1') ->> 'attempt')::int, 1, 'D4: attempt = 1');
SELECT tap._store184('r_d2', tap._claim184(tap._fetch184('act_c2')::uuid)::text);
SELECT is((tap._j184('r_d2') ->> 'status', tap._j184('r_d2') ->> 'reason'), ('refused'::text, 'claim_busy'::text),
  'D5: an immediate second claim => refused claim_busy (lease held)');
SELECT is((SELECT (state, attempt, claimed_until > now()) FROM ops.action WHERE id = tap._fetch184('act_c2')::uuid),
  ('processing'::text, 1, true), 'D6: action row: processing, attempt 1, lease in the future');
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT throws_ok(format($$SELECT ops.executor_claim(%L)$$, tap._fetch184('act_c2')), '42501', NULL,
  'D7: an authenticated founder cannot executor_claim (42501)');
SELECT tap.logout();
SELECT tap._store184('r_d3', tap._outcome184(tap._fetch184('act_c2')::uuid, 'processing', '{"stripe_request_started_at":"t"}'::jsonb, NULL, NULL)::text);
SELECT is((tap._j184('r_d3') ->> 'status'), 'ok', 'D8: record_action_outcome(processing) with stripe_request_started_at => ok');
SELECT is((SELECT (state, result ? 'stripe_request_started_at', claimed_until IS NOT NULL) FROM ops.action WHERE id = tap._fetch184('act_c2')::uuid),
  ('processing'::text, true, true), 'D9: still processing, result merged, lease untouched by a processing outcome');
UPDATE ops.action SET claimed_until = now() - interval '1 minute' WHERE id = tap._fetch184('act_c2')::uuid;
SELECT tap._store184('r_d4', tap._claim184(tap._fetch184('act_c2')::uuid)::text);
SELECT is((tap._j184('r_d4') ->> 'status'), 'claimed', 'D10: after the lease expired the claim succeeds again');
SELECT is((tap._j184('r_d4') ->> 'previously_sent')::boolean, true, 'D11: ...previously_sent = true (a request was started)');
SELECT is((tap._j184('r_d4') ->> 'attempt')::int, 2, 'D12: ...attempt = 2');
UPDATE ops.setting SET value = 'false'::jsonb WHERE key = 'refund_execute_enabled';
SELECT tap._store184('r_d5', tap._claim184(tap._fetch184('act_c2')::uuid)::text);
SELECT is((tap._j184('r_d5') ->> 'status', tap._j184('r_d5') ->> 'reason'), ('refused'::text, 'disabled'::text),
  'D13: refund_execute_enabled=false at claim time => refused disabled');
UPDATE ops.setting SET value = 'true'::jsonb WHERE key = 'refund_execute_enabled';
UPDATE ops.setting SET value = 'false'::jsonb WHERE key = 'actions_enabled';
SELECT tap._store184('r_d6', tap._claim184(tap._fetch184('act_c2')::uuid)::text);
SELECT is((tap._j184('r_d6') ->> 'status', tap._j184('r_d6') ->> 'reason'), ('refused'::text, 'paused'::text),
  'D14: actions_enabled=false at claim time => refused paused');
UPDATE ops.setting SET value = 'true'::jsonb WHERE key = 'actions_enabled';
UPDATE ops.action SET params = params || '{"x":1}'::jsonb WHERE id = tap._fetch184('act_c2')::uuid;
SELECT tap._store184('r_d7', tap._claim184(tap._fetch184('act_c2')::uuid)::text);
SELECT is((tap._j184('r_d7') ->> 'status', tap._j184('r_d7') ->> 'reason'), ('refused'::text, 'approval_stale'::text),
  'D15: tampered params at claim time => refused approval_stale');
UPDATE ops.action SET params = params - 'x' WHERE id = tap._fetch184('act_c2')::uuid;
SELECT is((SELECT count(*)::int FROM ops.audit WHERE action = 'action.claim.refund_execute' AND action_id = tap._fetch184('act_c2')::uuid), 2,
  'D16: exactly two claim audit rows (the refused attempts write none)');

-- ── Section E — record_action_outcome is monotonic ──────────────────────────
SELECT tap._store184('r_e1', tap._outcome184(tap._fetch184('act_c2')::uuid, 'succeeded_at_provider', '{"stripe_refund_id":"re_184_1"}'::jsonb, NULL, 're_184_1')::text);
SELECT is((tap._j184('r_e1') ->> 'status'), 'ok', 'E1: processing -> succeeded_at_provider (re_184_1) => ok');
SELECT tap._store184('r_e2', tap._outcome184(tap._fetch184('act_c2')::uuid, 'failed', NULL, 'late failure', NULL)::text);
SELECT is((tap._j184('r_e2') ->> 'status', tap._j184('r_e2') ->> 'reason'), ('refused'::text, 'terminal'::text),
  'E2: succeeded_at_provider -> failed => refused terminal');
SELECT is((SELECT (state, provider_ref, error, completed_at) FROM ops.action WHERE id = tap._fetch184('act_c2')::uuid),
  ('succeeded_at_provider'::text, 're_184_1'::text, NULL::text, NULL::timestamptz), 'E3: state unchanged by the refused regression');
SELECT tap._store184('r_e3', tap._outcome184(tap._fetch184('act_c2')::uuid, 'succeeded_at_provider', NULL, NULL, 're_OTHER')::text);
SELECT is((tap._j184('r_e3') ->> 'status', tap._j184('r_e3') ->> 'reason'), ('refused'::text, 'provider_ref_mismatch'::text),
  'E4: a different provider_ref => refused provider_ref_mismatch');
SELECT is((SELECT count(*)::int FROM ops.audit WHERE action = 'action.outcome.refused' AND action_id = tap._fetch184('act_c2')::uuid
             AND after ->> 'attempted_provider_ref' = 're_OTHER'), 1,
  'E5: ops.audit has action.outcome.refused naming the attempted provider_ref');
SELECT tap._store184('r_e4', tap._outcome184(tap._fetch184('act_c2')::uuid, 'succeeded', NULL, NULL, NULL)::text);
SELECT is((tap._j184('r_e4') ->> 'status'), 'ok', 'E6: succeeded_at_provider -> succeeded => ok');
SELECT is((SELECT (state, provider_ref, completed_at IS NOT NULL, claimed_until) FROM ops.action WHERE id = tap._fetch184('act_c2')::uuid),
  ('succeeded'::text, 're_184_1'::text, true, NULL::timestamptz), 'E7: succeeded, provider_ref retained, completed, lease released');
SELECT tap._store184('r_e5', tap._outcome184(tap._fetch184('act_c2')::uuid, 'unknown', NULL, NULL, NULL)::text);
SELECT is((tap._j184('r_e5') ->> 'status', tap._j184('r_e5') ->> 'reason'), ('refused'::text, 'terminal'::text),
  'E8: succeeded -> unknown => refused terminal');
SELECT tap._store184('r_e6', tap._outcome184(tap._fetch184('act_c2')::uuid, 'succeeded', NULL, NULL, NULL)::text);
SELECT is((tap._j184('r_e6') ->> 'status'), 'idempotent_replay', 'E9: replaying succeeded => idempotent_replay');

INSERT INTO ops.action (idempotency_key, action_type, subject_kind, subject_id, requested_by, state)
VALUES ('k184-direct-proc-01', 'refund_execute', 'payment', tap.payment_b(), tap.admin_user(), 'processing');
SELECT tap._store184('act_e2', (SELECT id::text FROM ops.action WHERE idempotency_key = 'k184-direct-proc-01'));
SELECT is((tap._outcome184(tap._fetch184('act_e2')::uuid, 'unknown', NULL, 'timeout', NULL)) ->> 'status', 'ok',
  'E10: processing -> unknown => ok');
SELECT is((tap._outcome184(tap._fetch184('act_e2')::uuid, 'processing', NULL, NULL, NULL)) ->> 'status', 'ok',
  'E11: unknown -> processing => ok');
SELECT is((tap._outcome184(tap._fetch184('act_e2')::uuid, 'failed', NULL, 'stripe: card_declined', NULL)) ->> 'status', 'ok',
  'E12: processing -> failed => ok');
SELECT is((SELECT (state, error, completed_at IS NOT NULL) FROM ops.action WHERE id = tap._fetch184('act_e2')::uuid),
  ('failed'::text, 'stripe: card_declined'::text, true), 'E13: failed with the error and completed_at');
SELECT tap._store184('r_e7', tap._outcome184(tap._fetch184('act_e2')::uuid, 'succeeded', NULL, NULL, NULL)::text);
SELECT is((tap._j184('r_e7') ->> 'status', tap._j184('r_e7') ->> 'reason'), ('refused'::text, 'terminal'::text),
  'E14: failed -> succeeded => refused terminal (failed is terminal)');
SELECT is((tap._outcome184(tap._fetch184('act_e2')::uuid, 'failed', NULL, NULL, NULL)) ->> 'status', 'idempotent_replay',
  'E15: replaying failed => idempotent_replay');

-- ── Section F — detector: crash recovery + webhook completion ───────────────
-- crash: claimed, never reported back, lease long expired
INSERT INTO ops.action (idempotency_key, action_type, subject_kind, subject_id, requested_by, state)
VALUES ('k184-crash-proc-01', 'refund_execute', 'payment', tap.payment_d(), tap.admin_user(), 'processing');
UPDATE ops.action SET claimed_until = now() - interval '1 hour' WHERE idempotency_key = 'k184-crash-proc-01';
SELECT tap._store184('act_f1', (SELECT id::text FROM ops.action WHERE idempotency_key = 'k184-crash-proc-01'));
-- live: an executor is working on it right now
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total,
                             stripe_payment_intent_id, status, mode, paid_at)
VALUES ('bbbbbbbb-0000-0000-0000-000000000184', tap.listing_c(), tap.buyer(), tap.seller(), 10000, 1000, 1000, 11000,
        'pi_fixture_184', 'succeeded', 'buy_now', now());
INSERT INTO ops.action (idempotency_key, action_type, subject_kind, subject_id, requested_by, state)
VALUES ('k184-live-proc-01', 'refund_execute', 'payment', 'bbbbbbbb-0000-0000-0000-000000000184', tap.admin_user(), 'processing');
UPDATE ops.action SET claimed_until = now() + interval '5 minutes' WHERE idempotency_key = 'k184-live-proc-01';
-- webhook landed: succeeded at Stripe, payment now refunded locally
INSERT INTO ops.action (idempotency_key, action_type, subject_kind, subject_id, requested_by, state, provider_ref)
VALUES ('k184-sap-webhook-01', 'refund_execute', 'payment', tap.payment_a(), tap.admin_user(), 'succeeded_at_provider', 're_184_wh');
SELECT tap._store184('act_f3', (SELECT id::text FROM ops.action WHERE idempotency_key = 'k184-sap-webhook-01'));
UPDATE public.payments SET status = 'refunded', refunded_at = now(), stripe_refund_id = 're_184_wh' WHERE id = tap.payment_a();

SELECT tap._store184('r_f1', tap._run184('refunds', 'manual')::text);
SELECT is((tap._j184('r_f1') ->> 'status'), 'succeeded', 'F1: run_job(refunds, manual) as service_role succeeds');
SELECT is((SELECT count(*)::int FROM ops."case" WHERE case_type = 'refund_failed' AND subject_kind = 'payment' AND subject_id = tap.payment_d()
             AND status = 'open' AND priority = 'p1' AND summary LIKE '%' || tap._fetch184('act_f1') || '%processing%'), 1,
  'F2: a processing action with an expired lease => open p1 refund_failed case naming the action');
SELECT is((SELECT count(*)::int FROM ops."case" WHERE case_type = 'refund_failed' AND subject_id = 'bbbbbbbb-0000-0000-0000-000000000184'), 0,
  'F3: a processing action with a live lease opens nothing');
SELECT is((SELECT (state, completed_at IS NOT NULL, claimed_until) FROM ops.action WHERE id = tap._fetch184('act_f3')::uuid),
  ('succeeded'::text, true, NULL::timestamptz), 'F4: succeeded_at_provider + payment refunded => action completed to succeeded');
SELECT is((SELECT count(*)::int FROM ops.audit WHERE action = 'action.outcome.refund_execute' AND action_id = tap._fetch184('act_f3')::uuid
             AND after ->> 'confirmed_by' LIKE '%webhook%' AND outcome = 'succeeded'), 1,
  'F5: ...with an audit row confirmed_by the charge.refunded webhook');
SELECT is((SELECT count(*)::int FROM ops."case" WHERE case_type = 'refund_failed' AND subject_id = tap.payment_a()), 0,
  'F6: the refunded payment carries no refund_failed case');

-- ── Section G — money honesty ───────────────────────────────────────────────
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store184('r_g1', (ops.money_overview(NULL, NULL) -> 'metrics' -> 'refunded_volume')::text);
SELECT tap.logout();
SELECT is(jsonb_typeof(tap._j184('r_g1') -> 'value_cents'), 'null', 'G1: refunded_volume.value_cents is jsonb null');
SELECT is((tap._j184('r_g1') ->> 'certainty'), 'uncertain', 'G2: refunded_volume.certainty = uncertain');
SELECT is((jsonb_typeof(tap._j184('r_g1') -> 'upper_bound_cents'), jsonb_typeof(tap._j184('r_g1') -> 'count')), ('number'::text, 'number'::text),
  'G3: upper_bound_cents and count are numbers');
SELECT is(((tap._j184('r_g1') ->> 'upper_bound_cents')::int, (tap._j184('r_g1') ->> 'count')::int), (11000, 1),
  'G4: upper bound = Σ total of the refunded payment, count 1');
SELECT is(tap._run184('refresh_metrics', 'manual') ->> 'status', 'succeeded', 'G5: refresh_metrics runs through run_job');
SELECT is((SELECT (value ->> 'certainty', jsonb_typeof(value -> 'value_cents')) FROM ops.metric_snapshot WHERE key = 'money.refunded'),
  ('uncertain'::text, 'null'::text), 'G6: snapshot money.refunded is uncertain with value_cents null');

-- ── Section H — founder evidence access ─────────────────────────────────────
SELECT tap._store184('ev_name', tap.seller()::text || '/ev-184.jpg');
-- path_tokens is a generated column (locally and on Supabase storage); id/created_at/updated_at default.
INSERT INTO storage.objects (id, bucket_id, name, owner, metadata) VALUES
  (gen_random_uuid(), 'proof-docs',    tap._fetch184('ev_name'),               NULL, '{}'::jsonb),
  (gen_random_uuid(), 'proof-docs',    tap.seller()::text || '/unref-184.jpg', NULL, '{}'::jsonb),
  (gen_random_uuid(), 'auction-media', tap.seller()::text || '/cover-184.jpg', NULL, '{}'::jsonb);
SELECT set_config('app.bypass_transfer_guard', 'on', true);
UPDATE public.transfers SET transfer_evidence_path = tap._fetch184('ev_name') WHERE id = tap.transfer_b();
SELECT tap.reset_guards();
SELECT is((SELECT transfer_evidence_path FROM public.transfers WHERE id = tap.transfer_b()), tap._fetch184('ev_name'),
  'H1: transfer_b references the evidence object (fixture)');
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id = 'proof-docs'), 2,
  'H1b: as postgres both proof-docs objects exist (so the founder counts below are RLS filtering, not an empty table)');
-- a stranger: authenticated, not an operator, not a party to any transfer
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, phone, phone_confirmed_at, created_at, updated_at)
VALUES ('99999999-9999-9999-9999-999999999184', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'stranger184@test.local', '{"provider":"email","providers":["email"]}', '{}', NULL, NULL, now(), now());

SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id = 'proof-docs'), 1,
  'H2: founder A (aal2) sees exactly one proof-docs object');
SELECT is((SELECT name FROM storage.objects WHERE bucket_id = 'proof-docs'), tap._fetch184('ev_name'),
  'H3: ...the referenced one only');
SELECT tap.logout();
SELECT tap.login(tap.admin_user());   -- aal1
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id = 'proof-docs'), 0,
  'H4: founder A at aal1 sees none');
SELECT tap.logout();
SELECT tap.login(tap.other_user()); SELECT tap._aal2();
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id = 'proof-docs'), 1,
  'H5: founder B (aal2) sees the referenced object');
SELECT tap.logout();
SELECT tap.login('99999999-9999-9999-9999-999999999184'); SELECT tap._aal2();
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id = 'proof-docs'), 0,
  'H6: a non-party non-operator (even at aal2) sees none');
SELECT tap.logout();

SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store184('r_h1', ops.evidence_access('transfer', tap.transfer_b(), 'transfer_evidence')::text);
SELECT is((tap._j184('r_h1') ->> 'bucket', tap._j184('r_h1') ->> 'path', (tap._j184('r_h1') ->> 'expires_in_seconds')::int),
  ('proof-docs'::text, tap._fetch184('ev_name'), 300), 'H7: evidence_access resolves bucket/path from the transfer, 300s expiry');
SELECT throws_like(format($$SELECT ops.evidence_access('transfer', %L, 'dispute_evidence')$$, tap.transfer_b()), '%no_evidence%',
  'H8: an empty slot (dispute_evidence) => no_evidence');
SELECT throws_like(format($$SELECT ops.evidence_access('transfer', %L, 'cover_image')$$, tap.transfer_b()), '%invalid_input%',
  'H9: an unknown slot (cover_image) => invalid_input');
SELECT throws_like(format($$SELECT ops.evidence_access('payment', %L, 'transfer_evidence')$$, tap.payment_a()), '%invalid_input%',
  'H10: subject_kind payment => invalid_input (evidence lives on transfers and listings only)');
SELECT throws_like(format($$SELECT ops.evidence_access('listing', %L, 'proof_of_ownership')$$, tap.listing_a()), '%no_evidence%',
  'H11: a listing without proof_of_ownership_path => no_evidence');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM ops.audit WHERE action = 'evidence.viewed' AND actor = tap.admin_user()
             AND subject_kind = 'transfer' AND subject_id = tap.transfer_b()
             AND after ->> 'path' = tap._fetch184('ev_name') AND after ->> 'slot' = 'transfer_evidence'), 1,
  'H12: one evidence.viewed audit row with the resolved path (the refused calls wrote none)');
SELECT tap.login('99999999-9999-9999-9999-999999999184'); SELECT tap._aal2();
SELECT throws_ok(format($$SELECT ops.evidence_access('transfer', %L, 'transfer_evidence')$$, tap.transfer_b()), '42501', NULL,
  'H13: a non-operator is refused (42501)');
SELECT tap.logout();
SELECT tap.login(tap.admin_user());   -- aal1
SELECT throws_like(format($$SELECT ops.evidence_access('transfer', %L, 'transfer_evidence')$$, tap.transfer_b()), '%step_up%',
  'H14: an operator at aal1 must step up');
SELECT tap.logout();
SELECT ok(has_function_privilege('authenticated', 'ops.evidence_access(text,uuid,text)', 'EXECUTE'),
  'H15: authenticated may EXECUTE ops.evidence_access');
SELECT ok(NOT has_function_privilege('anon', 'ops.evidence_access(text,uuid,text)', 'EXECUTE'),
  'H16: anon may NOT EXECUTE ops.evidence_access');
SELECT is((SELECT count(*)::int FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects'
             AND policyname = 'proof-docs operator read' AND cmd = 'SELECT' AND roles = '{authenticated}'::name[]), 1,
  'H17: policy "proof-docs operator read" exists on storage.objects (SELECT, authenticated)');

SELECT * FROM finish();
ROLLBACK;

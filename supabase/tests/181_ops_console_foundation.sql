-- ============================================================================
-- 181_ops_console_foundation.sql — migration 115 (Operating Console, part 1).
--   A: authorization — anon / non-operator refused (42501); operator at aal1
--      may whoami() but every write demands step_up; EXECUTE + RLS + table
--      grant posture of the `ops` schema.
--   B: idempotency — same key => idempotent_replay, one row, across operators.
--   C: case engine — optimistic concurrency (expected.version), notes,
--      resolve-requires-reason.
--   D: role matrix — platform_support may case_note but not payout_release /
--      setting_set.
--   E: two-founder approval binding — pending, self-approval refused, second
--      founder approves and the domain function runs (transfer released via
--      public.admin_release_held_payout), tamper => approval_stale, deny path.
--   F: audit — rows present, actor/correlation set, append-only triggers.
--   G: record_action_outcome — service_role-only async outcome callback for a
--      refund_execute handoff; disabled-setting rejection first.
--   H: user_restrict / user_unrestrict on seller_risk_scores.
--   I: report_resolve with expected.status.
--
-- Founders: A = tap.admin_user() (seeded into public.admin_users by seed_core),
--           B = tap.other_user() (inserted into public.admin_users below).
-- Every ops table is unreadable by `authenticated`, so table-level assertions
-- run as postgres (after tap.logout()); RPC results are parked in a memo table.
-- ============================================================================
BEGIN;
SELECT plan(128);
SELECT tap.seed_core();

-- seed_core() puts tap.admin_user() into public.admin_users (founder A).
-- Founder B: a second platform_admin via the same bootstrap allowlist.
INSERT INTO public.admin_users (user_id, label) VALUES (tap.other_user(), 'FOUNDER B') ON CONFLICT (user_id) DO NOTHING;

CREATE TABLE tap.memo_181 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store181(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_181 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fetch181(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_181 WHERE k=$1 $m$;
CREATE FUNCTION tap._j181(k text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v::jsonb FROM tap.memo_181 WHERE k=$1 $m$;
CREATE FUNCTION tap._aal2() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;

-- ── Section A — authorization ───────────────────────────────────────────────
SELECT tap.login_anon();
SELECT throws_ok($$SELECT ops.whoami()$$, '42501',
  NULL, 'A1: anon cannot call ops.whoami() (42501)');
SELECT tap.logout();

SELECT tap.login(tap.buyer());   -- authenticated, not an operator
SELECT throws_ok($$SELECT ops.whoami()$$, '42501',
  'insufficient_privilege: operator role required',
  'A2: an authenticated non-operator is refused by ops.whoami() (42501)');
SELECT throws_ok($$SELECT ops.execute_action('k181-buyer-00001','case_create','none',NULL,'{"title":"x"}'::jsonb)$$, '42501',
  'insufficient_privilege: operator role required',
  'A3: an authenticated non-operator is refused by ops.execute_action() (42501)');
SELECT tap.logout();

SELECT tap.login(tap.admin_user());   -- operator, aal1 (no aal claim)
SELECT is((ops.whoami() ->> 'role'), 'platform_admin',
  'A4: an operator at aal1 can whoami() and is platform_admin');
SELECT is((ops.whoami() ->> 'user_id')::uuid, tap.admin_user(),
  'A5: whoami().user_id is re-derived from auth.uid()');
SELECT throws_like($$SELECT ops.execute_action('k181-aal1-000001','case_create','none',NULL,'{"title":"x"}'::jsonb)$$,
  '%step_up%',
  'A6: an operator WITHOUT aal2 cannot execute_action (step_up_%)');

SELECT tap._aal2();
SELECT tap._store181('r_case1', ops.execute_action('k181-case-create-1','case_create','none',NULL,
  '{"title":"Fixture manual case","summary":"opened by 181","priority":"p2"}'::jsonb, 'test')::text);
SELECT is((tap._j181('r_case1') ->> 'status'), 'succeeded',
  'A7: operator + aal2: case_create succeeds');
SELECT ok((tap._j181('r_case1') #>> '{result,case_id}') IS NOT NULL,
  'A8: case_create returns result.case_id');
SELECT tap._store181('case1', tap._j181('r_case1') #>> '{result,case_id}');
SELECT tap.logout();

SELECT is((SELECT count(*)::int FROM ops."case" WHERE id = tap._fetch181('case1')::uuid AND case_type='manual'
             AND status='open' AND priority='p2' AND version=1 AND dedupe_key = 'manual:' || id::text), 1,
  'A9: the manual case row exists (open, p2, version 1, self-keyed dedupe)');

-- EXECUTE grants
SELECT ok(has_function_privilege('authenticated', 'ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)', 'EXECUTE'),
  'A10: authenticated may EXECUTE ops.execute_action');
SELECT ok(NOT has_function_privilege('anon', 'ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)', 'EXECUTE'),
  'A11: anon may NOT EXECUTE ops.execute_action');
SELECT ok(NOT has_function_privilege('authenticated', 'ops.record_action_outcome(uuid,text,jsonb,text,text)', 'EXECUTE'),
  'A12: authenticated may NOT EXECUTE ops.record_action_outcome');
SELECT ok(has_function_privilege('service_role', 'ops.record_action_outcome(uuid,text,jsonb,text,text)', 'EXECUTE'),
  'A13: service_role may EXECUTE ops.record_action_outcome');
SELECT ok(NOT has_function_privilege('authenticated', 'ops.action_dispatch(ops.action)', 'EXECUTE'),
  'A14: authenticated may NOT EXECUTE ops.action_dispatch (internal)');
SELECT ok(NOT has_function_privilege('authenticated', 'ops.case_upsert(text,text,uuid,text,text,text,text,timestamptz,text)', 'EXECUTE'),
  'A15: authenticated may NOT EXECUTE ops.case_upsert (internal)');
SELECT ok(NOT has_function_privilege('authenticated', 'ops.audit_write(text,text,uuid,text,text,jsonb,jsonb,text,uuid,uuid)', 'EXECUTE'),
  'A16: authenticated may NOT EXECUTE ops.audit_write (internal)');
SELECT ok(NOT has_function_privilege('authenticated', 'ops.action_run(uuid)', 'EXECUTE'),
  'A17: authenticated may NOT EXECUTE ops.action_run (internal)');
-- RLS + table grants
SELECT is((SELECT relrowsecurity FROM pg_class WHERE oid = 'ops."case"'::regclass), true,
  'A18: ops."case" has RLS enabled');
SELECT is((SELECT relrowsecurity FROM pg_class WHERE oid = 'ops.audit'::regclass), true,
  'A19: ops.audit has RLS enabled');
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='ops' AND c.relkind='r' AND NOT c.relrowsecurity), 0,
  'A20: every ops table has RLS enabled');
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='ops' AND c.relkind='r'), 13,
  'A21: 13 ops tables (migration verification count)');
SELECT is((SELECT count(*)::int FROM information_schema.role_table_grants
            WHERE table_schema='ops' AND grantee IN ('authenticated','anon','PUBLIC')), 0,
  'A22: authenticated/anon/PUBLIC hold no table privileges on any ops table');
SELECT is((SELECT count(*)::int FROM information_schema.role_table_grants
            WHERE table_schema='ops' AND table_name='audit' AND grantee='service_role'
              AND privilege_type IN ('UPDATE','DELETE')), 0,
  'A23: service_role cannot UPDATE/DELETE ops.audit');

-- ── Section B — idempotency ─────────────────────────────────────────────────
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store181('r_idem1', ops.execute_action('k181-idem-000001','case_create','none',NULL,'{"title":"idem"}'::jsonb)::text);
SELECT is((tap._j181('r_idem1') ->> 'status'), 'succeeded', 'B1: first call with a fresh key succeeds');
SELECT tap._store181('r_idem2', ops.execute_action('k181-idem-000001','case_create','none',NULL,'{"title":"idem"}'::jsonb)::text);
SELECT is((tap._j181('r_idem2') ->> 'status'), 'idempotent_replay', 'B2: same key again => idempotent_replay');
SELECT is((tap._j181('r_idem2') ->> 'action_id'), (tap._j181('r_idem1') ->> 'action_id'),
  'B3: the replay returns the SAME action_id');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM ops.action WHERE idempotency_key='k181-idem-000001'), 1,
  'B4: exactly one ops.action row for the key');
SELECT tap.login(tap.other_user()); SELECT tap._aal2();   -- founder B reuses founder A's key
SELECT tap._store181('r_idem3', ops.execute_action('k181-idem-000001','case_create','none',NULL,'{"title":"idem-b"}'::jsonb)::text);
SELECT is((tap._j181('r_idem3') ->> 'status'), 'idempotent_replay', 'B5: a second operator reusing the key gets idempotent_replay');
SELECT is((tap._j181('r_idem3') ->> 'action_id'), (tap._j181('r_idem1') ->> 'action_id'), 'B6: ...bound to the original action');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM ops.action WHERE idempotency_key='k181-idem-000001'), 1,
  'B7: still exactly one row (no new action for the reused key)');
SELECT is((SELECT count(*)::int FROM ops."case" WHERE title='idem-b'), 0,
  'B8: the replay did not create a second case');

-- ── Section C — optimistic concurrency + case verbs ─────────────────────────
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store181('r_c1', ops.execute_action('k181-assign-stale1','case_assign','case',tap._fetch181('case1')::uuid,
  jsonb_build_object('assignee', tap.admin_user()), NULL, '{"version": 99}'::jsonb)::text);
SELECT is((tap._j181('r_c1') ->> 'status'), 'rejected', 'C1: case_assign with a stale expected.version is rejected');
SELECT is((tap._j181('r_c1') ->> 'reject_reason'), 'stale_state', 'C2: ...reject_reason = stale_state');
SELECT tap._store181('r_c2', ops.execute_action('k181-assign-ok0001','case_assign','case',tap._fetch181('case1')::uuid,
  jsonb_build_object('assignee', tap.admin_user()), NULL, '{"version": 1}'::jsonb)::text);
SELECT is((tap._j181('r_c2') ->> 'status'), 'succeeded', 'C3: case_assign with the current version succeeds');
SELECT is((tap._j181('r_c2') #>> '{result,version}')::int, 2, 'C4: ...result.version is incremented to 2');
SELECT tap.logout();
SELECT is((SELECT (version, status, assignee) FROM ops."case" WHERE id = tap._fetch181('case1')::uuid),
  (2, 'in_progress'::text, tap.admin_user()),
  'C5: case row: version 2, in_progress, assigned to founder A');
SELECT is((SELECT count(*)::int FROM ops.case_event WHERE case_id = tap._fetch181('case1')::uuid AND kind='assigned'), 1,
  'C6: one assigned case_event');

SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store181('r_c3', ops.execute_action('k181-note-000001','case_note','case',tap._fetch181('case1')::uuid,
  '{"body":"first note"}'::jsonb)::text);
SELECT is((tap._j181('r_c3') ->> 'status'), 'succeeded', 'C7: case_note succeeds');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM ops.case_note WHERE case_id = tap._fetch181('case1')::uuid AND body='first note' AND author=tap.admin_user()), 1,
  'C8: the note row exists with the actor as author');
SELECT is((SELECT count(*)::int FROM ops.case_event WHERE case_id = tap._fetch181('case1')::uuid AND kind='note_added'), 1,
  'C9: a note_added case_event was appended');
SELECT is((SELECT version FROM ops."case" WHERE id = tap._fetch181('case1')::uuid), 3,
  'C10: a note bumps the case version (3)');

SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store181('r_c4', ops.execute_action('k181-status-noreas','case_status','case',tap._fetch181('case1')::uuid,
  '{"status":"resolved"}'::jsonb)::text);
SELECT is((tap._j181('r_c4') ->> 'status'), 'rejected', 'C11: case_status resolved WITHOUT a reason is rejected');
SELECT is((tap._j181('r_c4') ->> 'reject_reason'), 'precondition', 'C12: ...reject_reason = precondition');
SELECT tap._store181('r_c5', ops.execute_action('k181-status-resolv','case_status','case',tap._fetch181('case1')::uuid,
  '{"status":"resolved"}'::jsonb, 'handled in 181')::text);
SELECT is((tap._j181('r_c5') ->> 'status'), 'succeeded', 'C13: case_status resolved WITH a reason succeeds');
SELECT tap.logout();
SELECT is((SELECT (status, resolved_by, resolved_at IS NOT NULL, resolution_note) FROM ops."case" WHERE id = tap._fetch181('case1')::uuid),
  ('resolved'::text, tap.admin_user(), true, 'handled in 181'::text),
  'C14: case is resolved, resolved_by = actor, resolved_at set, note recorded');
SELECT is((SELECT count(*)::int FROM ops.case_event WHERE case_id = tap._fetch181('case1')::uuid AND kind='status_changed'
             AND data ->> 'to' = 'resolved'), 1,
  'C15: status_changed(open->resolved) case_event appended');

-- ── Section D — role matrix (platform_support) ──────────────────────────────
INSERT INTO kernel.platform_role (identity_id, role, granted_by) VALUES (tap.seller(), 'platform_support', tap.admin_user());
SELECT tap.login(tap.seller()); SELECT tap._aal2();
SELECT is((ops.whoami() ->> 'role'), 'platform_support', 'D1: seller is now platform_support');
SELECT tap._store181('r_d1', ops.execute_action('k181-support-note1','case_note','case',tap._fetch181('case1')::uuid,
  '{"body":"support note"}'::jsonb)::text);
SELECT is((tap._j181('r_d1') ->> 'status'), 'succeeded', 'D2: platform_support may case_note');
SELECT throws_ok(
  format($$SELECT ops.execute_action('k181-support-payout','payout_release','transfer',%L,'{}'::jsonb,'try')$$, tap.transfer_b()),
  '42501', 'insufficient_privilege: platform_support may not perform payout_release',
  'D3: platform_support may NOT payout_release (42501, exact message)');
SELECT throws_ok(
  $$SELECT ops.execute_action('k181-support-settng','setting_set','setting',NULL,'{"value":true}'::jsonb,'try',NULL,'refund_execute_enabled')$$,
  '42501', 'insufficient_privilege: platform_support may not perform setting_set',
  'D4: platform_support may NOT setting_set (42501)');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM ops.action WHERE idempotency_key IN ('k181-support-payout','k181-support-settng')), 0,
  'D5: refused requests leave no action row');

-- ── Section E — approval binding (payout_release) ───────────────────────────
-- transfer_b fixture: seller_sent, payout_released_at null — satisfies
-- public.admin_release_held_payout's guard as-is.
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store181('r_e1', ops.execute_action('k181-payout-b-0001','payout_release','transfer',tap.transfer_b(),
  '{}'::jsonb, 'manual release after evidence review')::text);
SELECT is((tap._j181('r_e1') ->> 'status'), 'awaiting_approval', 'E1: payout_release => awaiting_approval');
SELECT tap._store181('act_e1', tap._j181('r_e1') ->> 'action_id');
SELECT tap._store181('appr_e1', tap._j181('r_e1') ->> 'approval_id');
SELECT throws_like(
  format($$SELECT ops.approve_action(%L,'approve','lgtm')$$, tap._fetch181('act_e1')),
  '%self_approval%',
  'E2: the requester cannot approve their own action');
SELECT tap.logout();
SELECT is((SELECT (state, requested_by, decided_by, action_id::text) FROM ops.approval WHERE id = tap._fetch181('appr_e1')::uuid),
  ('pending'::text, tap.admin_user(), NULL::uuid, tap._fetch181('act_e1')),
  'E3: ops.approval row is pending, requested_by founder A, undecided');
SELECT is((SELECT state FROM ops.action WHERE id = tap._fetch181('act_e1')::uuid), 'awaiting_approval',
  'E4: action row is awaiting_approval (self-approval attempt changed nothing)');
SELECT is((SELECT status FROM public.transfers WHERE id = tap.transfer_b()), 'seller_sent',
  'E5: transfer_b untouched before approval');

SELECT tap.login(tap.other_user()); SELECT tap._aal2();   -- founder B
SELECT tap._store181('r_e2', ops.approve_action(tap._fetch181('act_e1')::uuid, 'approve', 'second founder ok')::text);
SELECT is((tap._j181('r_e2') ->> 'status'), 'succeeded', 'E6: founder B approves => the action runs and succeeds');
SELECT is((tap._j181('r_e2') ->> 'action_id'), tap._fetch181('act_e1'), 'E7: ...for the same action_id');
SELECT tap.logout();
SELECT is((SELECT (status, payout_review_status, payout_released_at IS NULL) FROM public.transfers WHERE id = tap.transfer_b()),
  ('auto_released'::text, NULL::text, true),
  'E8: transfer_b is now auto_released with payout_review_status null (via admin_release_held_payout)');
SELECT is((SELECT count(*)::int FROM public.payout_decisions WHERE transfer_id = tap.transfer_b()
             AND 'ADMIN_MANUAL_RELEASE' = ANY(reason_codes) AND decision='release'
             AND actor = 'admin:' || tap.admin_user()::text), 1,
  'E9: a payout_decisions row with ADMIN_MANUAL_RELEASE exists; domain actor = founder A (the REQUESTER is attributed; the approver is on ops.approval)');
SELECT is((SELECT (state, decided_by) FROM ops.approval WHERE id = tap._fetch181('appr_e1')::uuid), ('approved'::text, tap.other_user()),
  'E10: approval is approved, decided_by founder B');
SELECT is((SELECT (state, approval_id::text, completed_at IS NOT NULL) FROM ops.action WHERE id = tap._fetch181('act_e1')::uuid),
  ('succeeded'::text, tap._fetch181('appr_e1'), true),
  'E11: action succeeded, bound to the approval, completed_at set');

-- A NEW payout_release on the already-released transfer. ops.action_precheck
-- runs BEFORE an approval is parked, so the request is rejected immediately
-- and no second founder is bothered.
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store181('r_e3', ops.execute_action('k181-payout-b-0002','payout_release','transfer',tap.transfer_b(),
  '{}'::jsonb, 'release again')::text);
SELECT is((tap._j181('r_e3') ->> 'status'), 'rejected', 'E12: a second payout_release request is rejected up front (precheck, no approval parked)');
SELECT is((tap._j181('r_e3') ->> 'reject_reason'), 'stale_state', 'E13: ...reject_reason = stale_state');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM ops.approval WHERE action_id = (tap._j181('r_e3') ->> 'action_id')::uuid), 0,
  'E14: ...and no approval row was created for it');
SELECT is((SELECT count(*)::int FROM public.payout_decisions WHERE transfer_id = tap.transfer_b()), 1,
  'E15: no second payout_decisions row');

-- Tamper test on transfer_a: move it to seller_sent through the transfer
-- state guard bypass (the fixture's pending transfer would otherwise be
-- refused by the domain guard before the hash check could be observed).
SELECT set_config('app.bypass_transfer_guard', 'on', true);
UPDATE public.transfers
   SET status='seller_sent', seller_sent_at=now(), auto_release_at=now()+interval '72 hours',
       transfer_evidence_path='fixtures/evidence-a.jpg'
 WHERE id = tap.transfer_a();
SELECT tap.reset_guards();
SELECT is((SELECT status FROM public.transfers WHERE id = tap.transfer_a()), 'seller_sent', 'E16: transfer_a moved to seller_sent (fixture)');

SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store181('r_e5', ops.execute_action('k181-payout-a-0001','payout_release','transfer',tap.transfer_a(),
  '{}'::jsonb, 'release a')::text);
SELECT is((tap._j181('r_e5') ->> 'status'), 'awaiting_approval', 'E17: payout_release on transfer_a => awaiting_approval');
SELECT tap.logout();
UPDATE ops.action SET params = params || '{"tampered":true}'::jsonb WHERE id = (tap._j181('r_e5') ->> 'action_id')::uuid;
SELECT tap.login(tap.other_user()); SELECT tap._aal2();
SELECT tap._store181('r_e6', ops.approve_action((tap._j181('r_e5') ->> 'action_id')::uuid, 'approve', 'ok')::text);
SELECT is((tap._j181('r_e6') ->> 'status'), 'rejected', 'E18: approving a tampered action is rejected');
SELECT is((tap._j181('r_e6') ->> 'reject_reason'), 'approval_stale', 'E19: ...reject_reason = approval_stale');
SELECT tap.logout();
SELECT is((SELECT state FROM ops.approval WHERE id = (tap._j181('r_e5') ->> 'approval_id')::uuid), 'stale',
  'E20: approval.state = stale');
SELECT is((SELECT (state, reject_reason) FROM ops.action WHERE id = (tap._j181('r_e5') ->> 'action_id')::uuid),
  ('rejected'::text, 'approval_stale'::text),
  'E21: action.state = rejected / approval_stale');
SELECT is((SELECT status FROM public.transfers WHERE id = tap.transfer_a()), 'seller_sent',
  'E22: the tampered action did NOT touch transfer_a');

-- Deny path
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store181('r_e7', ops.execute_action('k181-payout-a-0002','payout_release','transfer',tap.transfer_a(),
  '{}'::jsonb, 'release a again')::text);
SELECT is((tap._j181('r_e7') ->> 'status'), 'awaiting_approval', 'E23: a fresh payout_release request is parked');
SELECT tap.logout();
SELECT tap.login(tap.other_user()); SELECT tap._aal2();
SELECT tap._store181('r_e8', ops.approve_action((tap._j181('r_e7') ->> 'action_id')::uuid, 'deny', 'not convinced')::text);
SELECT is((tap._j181('r_e8') ->> 'status'), 'rejected', 'E24: deny => rejected');
SELECT is((tap._j181('r_e8') ->> 'reject_reason'), 'denied', 'E25: ...reject_reason = denied');
SELECT tap.logout();
SELECT is((SELECT (state, reject_reason) FROM ops.action WHERE id = (tap._j181('r_e7') ->> 'action_id')::uuid),
  ('rejected'::text, 'denied'::text), 'E26: action.state rejected / denied');
SELECT is((SELECT (state, decided_by, reason) FROM ops.approval WHERE id = (tap._j181('r_e7') ->> 'approval_id')::uuid),
  ('denied'::text, tap.other_user(), 'not convinced'::text), 'E27: approval denied by founder B with the reason');
SELECT is((SELECT status FROM public.transfers WHERE id = tap.transfer_a()), 'seller_sent',
  'E28: the denied action did NOT touch transfer_a');

-- ── Section F — audit ───────────────────────────────────────────────────────
SELECT ok(EXISTS (SELECT 1 FROM ops.audit WHERE action='action.requested'),        'F1: audit has action.requested');
SELECT ok(EXISTS (SELECT 1 FROM ops.audit WHERE action='approval.approved'),       'F2: audit has approval.approved');
SELECT ok(EXISTS (SELECT 1 FROM ops.audit WHERE action='approval.denied'),         'F3: audit has approval.denied');
SELECT ok(EXISTS (SELECT 1 FROM ops.audit WHERE action='approval.stale'),          'F4: audit has approval.stale');
SELECT ok(EXISTS (SELECT 1 FROM ops.audit WHERE action='action.payout_release' AND outcome='succeeded'
                    AND subject_id = tap.transfer_b() AND action_id = tap._fetch181('act_e1')::uuid),
  'F5: audit has action.payout_release (succeeded) for transfer_b bound to the action');
SELECT is((SELECT count(*)::int FROM ops.audit WHERE actor IS NULL OR correlation_id IS NULL), 0,
  'F6: every audit row so far has an actor and a correlation_id');
SELECT is((SELECT count(*)::int FROM ops.audit WHERE actor_role IS NULL), 0,
  'F7: every audit row carries the actor role');
SELECT is((SELECT count(DISTINCT correlation_id)::int FROM ops.audit WHERE action_id = tap._fetch181('act_e1')::uuid), 1,
  'F8: all audit rows of one action share its correlation_id');
SELECT is((SELECT count(*)::int FROM ops.audit WHERE action_id = tap._fetch181('act_e1')::uuid), 3,
  'F9: the approved payout has exactly 3 audit rows (requested, approved, executed)');
SELECT throws_like($$UPDATE ops.audit SET outcome='x'$$, '%append_only%', 'F10: ops.audit is append-only (UPDATE refused)');
SELECT throws_like($$DELETE FROM ops.audit$$, '%append_only%', 'F11: ops.audit is append-only (DELETE refused)');
SELECT throws_like($$DELETE FROM ops.case_note$$, '%append_only%', 'F12: ops.case_note is append-only (DELETE refused)');
SELECT throws_like($$UPDATE ops.case_note SET body='x'$$, '%append_only%', 'F13: ops.case_note is append-only (UPDATE refused)');
SELECT throws_ok($$DELETE FROM ops.case_event$$, 'P0001', NULL, 'F14: ops.case_event is append-only (DELETE refused)');

-- ── Section G — record_action_outcome (refund_execute handoff) ──────────────
-- G0: refund_execute while refund_execute_enabled = false => rejected/disabled
-- up front by ops.action_precheck (no approval is parked for a disabled action).
SELECT is((SELECT value FROM ops.setting WHERE key='refund_execute_enabled'), 'false'::jsonb, 'G1: refund_execute_enabled starts false');
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store181('r_g0', ops.execute_action('k181-refund-off-01','refund_execute','payment',tap.payment_a(),
  '{}'::jsonb, 'buyer never received tickets')::text);
SELECT is((tap._j181('r_g0') ->> 'status'), 'rejected', 'G2: refund_execute while disabled => rejected immediately');
SELECT is((tap._j181('r_g0') ->> 'reject_reason'), 'disabled', 'G3: ...reject_reason = disabled');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM ops.approval WHERE action_id = (tap._j181('r_g0') ->> 'action_id')::uuid), 0,
  'G4: ...and no approval row was parked');

-- flip the setting as founder A
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store181('r_g1', ops.execute_action('k181-setting-00001','setting_set','setting',NULL,
  '{"value": true}'::jsonb, 'ops-refund-execute deployed', NULL, 'refund_execute_enabled')::text);
SELECT is((tap._j181('r_g1') ->> 'status'), 'succeeded', 'G5: setting_set succeeds');
SELECT tap.logout();
SELECT is((SELECT (value, updated_by) FROM ops.setting WHERE key='refund_execute_enabled'), ('true'::jsonb, tap.admin_user()),
  'G6: ops.setting refund_execute_enabled is now true, updated_by founder A');

SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store181('r_g2', ops.execute_action('k181-refund-000001','refund_execute','payment',tap.payment_a(),
  '{}'::jsonb, 'buyer never received tickets')::text);
SELECT is((tap._j181('r_g2') ->> 'status'), 'awaiting_approval', 'G7: refund_execute (enabled) => awaiting_approval');
SELECT tap._store181('act_g2', tap._j181('r_g2') ->> 'action_id');
SELECT tap.logout();
SELECT tap.login(tap.other_user()); SELECT tap._aal2();
SELECT tap._store181('r_g3', ops.approve_action(tap._fetch181('act_g2')::uuid, 'approve', 'ok')::text);
SELECT is((tap._j181('r_g3') ->> 'status'), 'processing', 'G8: approved refund_execute => processing (edge handoff)');
SELECT is((tap._j181('r_g3') #>> '{result,handoff}'), 'ops-refund-execute', 'G9: result.handoff = ops-refund-execute');
SELECT is((tap._j181('r_g3') #>> '{result,amount_cents}')::int, 11000, 'G10: result.amount_cents defaults to the payment total');
SELECT tap.logout();
SELECT is((SELECT (state, completed_at) FROM ops.action WHERE id = tap._fetch181('act_g2')::uuid), ('processing'::text, NULL::timestamptz),
  'G11: action row is processing, not completed');

-- authenticated founder A may not report outcomes
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT throws_ok(
  format($$SELECT ops.record_action_outcome(%L,'succeeded','{}'::jsonb,NULL,'re_x')$$, tap._fetch181('act_g2')),
  '42501', NULL, 'G12: authenticated (even a founder) cannot call record_action_outcome (42501)');
SELECT tap.logout();

SELECT tap.login_service();
SELECT tap._store181('r_g4', ops.record_action_outcome(tap._fetch181('act_g2')::uuid, 'succeeded_at_provider',
  '{"stripe_refund_id":"re_test_1"}'::jsonb, NULL, 're_test_1')::text);
SELECT is((tap._j181('r_g4') ->> 'status'), 'ok', 'G13: service_role record_action_outcome(succeeded_at_provider) => ok');
SELECT tap.logout();
SELECT is((SELECT (state, provider_ref, result ->> 'stripe_refund_id', result ->> 'handoff') FROM ops.action WHERE id = tap._fetch181('act_g2')::uuid),
  ('succeeded_at_provider'::text, 're_test_1'::text, 're_test_1'::text, 'ops-refund-execute'::text),
  'G14: action is succeeded_at_provider, provider_ref set, result merged (handoff kept)');
SELECT tap.login_service();
SELECT tap._store181('r_g5', ops.record_action_outcome(tap._fetch181('act_g2')::uuid, 'succeeded', NULL, NULL, NULL)::text);
SELECT is((tap._j181('r_g5') ->> 'status'), 'ok', 'G15: second outcome (succeeded) => ok');
SELECT tap._store181('r_g6', ops.record_action_outcome(tap._fetch181('act_g2')::uuid, 'succeeded', NULL, NULL, NULL)::text);
SELECT is((tap._j181('r_g6') ->> 'status'), 'idempotent_replay', 'G16: a third outcome on a terminal action => idempotent_replay');
SELECT tap.logout();
SELECT is((SELECT (state, provider_ref, completed_at IS NOT NULL) FROM ops.action WHERE id = tap._fetch181('act_g2')::uuid),
  ('succeeded'::text, 're_test_1'::text, true),
  'G17: action is succeeded, provider_ref retained, completed_at set');
SELECT is((SELECT count(*)::int FROM ops.audit WHERE action='action.outcome.refund_execute' AND action_id = tap._fetch181('act_g2')::uuid), 2,
  'G18: two outcome audit rows (the replay writes none)');

-- ── Section H — user_restrict / user_unrestrict ─────────────────────────────
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store181('r_h1', ops.execute_action('k181-restrict-0001','user_restrict','user',tap.seller(),
  '{}'::jsonb, 'duplicate evidence pattern')::text);
SELECT is((tap._j181('r_h1') ->> 'status'), 'succeeded', 'H1: user_restrict succeeds');
SELECT tap.logout();
SELECT is((SELECT (is_listing_blocked, listing_blocked_reason) FROM public.seller_risk_scores WHERE seller_id = tap.seller()),
  (true, 'duplicate evidence pattern'::text), 'H2: seller_risk_scores.is_listing_blocked = true with the reason');
SELECT is((SELECT count(*)::int FROM ops.user_restriction WHERE user_id = tap.seller() AND kind='listing_blocked'
             AND lifted_at IS NULL AND actor = tap.admin_user()), 1,
  'H3: one active ops.user_restriction row');
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store181('r_h2', ops.execute_action('k181-restrict-0002','user_restrict','user',tap.seller(),
  '{}'::jsonb, 'again')::text);
SELECT is((tap._j181('r_h2') ->> 'status'), 'rejected', 'H4: restricting an already-blocked user is rejected');
SELECT is((tap._j181('r_h2') ->> 'reject_reason'), 'stale_state', 'H5: ...reject_reason = stale_state');
SELECT tap._store181('r_h3', ops.execute_action('k181-unrestrict-001','user_unrestrict','user',tap.seller(),
  '{}'::jsonb, 'cleared')::text);
SELECT is((tap._j181('r_h3') ->> 'status'), 'succeeded', 'H6: user_unrestrict succeeds');
SELECT tap.logout();
SELECT is((SELECT is_listing_blocked FROM public.seller_risk_scores WHERE seller_id = tap.seller()), false,
  'H7: is_listing_blocked back to false');
SELECT is((SELECT (lifted_at IS NOT NULL, lifted_by, lift_reason) FROM ops.user_restriction WHERE user_id = tap.seller() AND kind='listing_blocked'),
  (true, tap.admin_user(), 'cleared'::text), 'H8: the restriction is lifted (lifted_at, lifted_by, lift_reason)');
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store181('r_h4', ops.execute_action('k181-restrict-susp','user_restrict','user',tap.seller(),
  '{"kind":"suspend"}'::jsonb, 'suspend')::text);
SELECT is((tap._j181('r_h4') ->> 'status'), 'rejected', 'H9: user_restrict kind=suspend is rejected');
SELECT is((tap._j181('r_h4') ->> 'reject_reason'), 'not_supported', 'H10: ...reject_reason = not_supported');
SELECT tap._store181('r_h5', ops.execute_action('k181-unrestrict-002','user_unrestrict','user',tap.seller(),
  '{}'::jsonb, 'again')::text);
SELECT is((tap._j181('r_h5') ->> 'reject_reason'), 'stale_state', 'H11: unrestricting a non-blocked user => stale_state');
SELECT tap.logout();
SELECT is((SELECT is_listing_blocked FROM public.seller_risk_scores WHERE seller_id = tap.seller()), false,
  'H12: the refused suspend left the seller unblocked');

-- ── Section I — report_resolve ──────────────────────────────────────────────
INSERT INTO public.reports (id, reporter_id, target_type, target_id, reason, notes, status)
VALUES ('dddddddd-0000-0000-0000-000000000181', tap.buyer(), 'listing', tap.listing_a(), 'other', 'fixture report', 'pending');
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store181('r_i1', ops.execute_action('k181-report-000001','report_resolve','report','dddddddd-0000-0000-0000-000000000181',
  '{"status":"actioned"}'::jsonb, 'listing removed', '{"status":"pending"}'::jsonb)::text);
SELECT is((tap._j181('r_i1') ->> 'status'), 'succeeded', 'I1: report_resolve actioned with expected.status=pending succeeds');
SELECT tap.logout();
SELECT is((SELECT (status, resolved_at IS NOT NULL) FROM public.reports WHERE id = 'dddddddd-0000-0000-0000-000000000181'),
  ('actioned'::text, true), 'I2: report is actioned with resolved_at set');
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store181('r_i2', ops.execute_action('k181-report-000002','report_resolve','report','dddddddd-0000-0000-0000-000000000181',
  '{"status":"dismissed"}'::jsonb, 'second look', '{"status":"pending"}'::jsonb)::text);
SELECT is((tap._j181('r_i2') ->> 'status'), 'rejected', 'I3: report_resolve again with expected.status=pending is rejected');
SELECT is((tap._j181('r_i2') ->> 'reject_reason'), 'stale_state', 'I4: ...reject_reason = stale_state');
SELECT tap.logout();
SELECT is((SELECT status FROM public.reports WHERE id = 'dddddddd-0000-0000-0000-000000000181'), 'actioned',
  'I5: the report stays actioned');

SELECT * FROM finish();
ROLLBACK;

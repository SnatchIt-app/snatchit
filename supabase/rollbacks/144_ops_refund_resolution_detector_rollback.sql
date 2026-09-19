-- ROLLBACK for 144_ops_refund_resolution_detector.sql. Restores the bodies 144 replaced (117: run_job,
-- run_all_detectors; 118: action_dispatch — rebase with the migration if 138 lands first), drops the detector, deletes
-- the setting row and narrows both checks. REFUSES if any refund_resolution case or state_changed event exists:
-- that is case history, and removing it is an owner decision, not a rollback step.
begin;
set local lock_timeout = '3s';
do $rb$ begin
  if exists (select 1 from ops."case" where case_type = 'refund_resolution')
     or exists (select 1 from ops.case_event where kind = 'state_changed') then
    raise exception 'rollback 144 refused: refund_resolution case history exists (owner decision)';
  end if;
end $rb$;

create or replace function ops.run_job(p_job_name text, p_trigger text default 'cron')
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  c_jobs   constant text[] := array['paid_unsettled','transfer_deadlines','release_stuck','refunds','disputes',
                                    'payout_review','reports','webhooks','jobs','notifications','reconciliation',
                                    'refresh_metrics','daily_summary'];
  v_uid    uuid := auth.uid();
  v_state  ops.job_state%rowtype;
  v_run_id uuid;
  v_body   jsonb;
  v_skip   text;
  v_err    text;
  v_errstate text;
  v_n      integer;
begin
  if not public.request_is_service_role() then
    perform ops.assert_role(array['platform_admin']);
  end if;
  if p_job_name is null or not (p_job_name = any(c_jobs)) then
    raise exception 'invalid_input: unknown job %', coalesce(p_job_name, '(null)');
  end if;
  if p_trigger is null or p_trigger not in ('cron', 'manual', 'test') then
    raise exception 'invalid_input: trigger must be cron, manual or test';
  end if;

  insert into ops.job_state (job_name) values (p_job_name) on conflict (job_name) do nothing;
  select * into v_state from ops.job_state where job_name = p_job_name for update;

  -- skip rules (cron / test only; a manual run is an operator's explicit choice)
  if p_trigger <> 'manual' then
    if not ops.setting_bool('detectors_enabled', true) then
      v_skip := 'detectors_disabled';
    elsif not v_state.enabled then
      v_skip := 'job_disabled';
    elsif v_state.backoff_until is not null and v_state.backoff_until > now() then
      v_skip := 'backoff';
    end if;
  end if;
  if v_skip is null and not pg_try_advisory_xact_lock(hashtext('ops.run_job:' || p_job_name)) then
    v_skip := 'overlap';
  end if;
  if v_skip is not null then
    insert into ops.job_run (job_name, trigger, triggered_by, finished_at, status, detail)
    values (p_job_name, p_trigger, v_uid, now(), 'skipped',
            jsonb_build_object('reason', v_skip, 'backoff_until', v_state.backoff_until))
    returning id into v_run_id;
    return jsonb_build_object('status', 'skipped', 'job_run_id', v_run_id,
                              'detail', jsonb_build_object('reason', v_skip, 'backoff_until', v_state.backoff_until));
  end if;

  insert into ops.job_run (job_name, trigger, triggered_by, status, attempt)
  values (p_job_name, p_trigger, v_uid, 'running', v_state.consecutive_failures + 1)
  returning id into v_run_id;
  update ops.job_state set last_run_at = now(), updated_at = now() where job_name = p_job_name;

  begin
    v_body := case p_job_name
      when 'paid_unsettled'     then ops.detect_paid_unsettled()
      when 'transfer_deadlines' then ops.detect_transfer_deadlines()
      when 'release_stuck'      then ops.detect_release_stuck()
      when 'refunds'            then ops.detect_refunds()
      when 'disputes'           then ops.detect_disputes()
      when 'payout_review'      then ops.detect_payout_review()
      when 'reports'            then ops.detect_reports()
      when 'webhooks'           then ops.detect_webhooks()
      when 'jobs'               then ops.detect_jobs()
      when 'notifications'      then ops.detect_notifications()
      when 'reconciliation'     then ops.detect_reconciliation()
      when 'refresh_metrics'    then ops.refresh_metrics()
      when 'daily_summary'      then ops.build_daily_summary()
    end;
  exception when others then
    v_err := sqlerrm; v_errstate := sqlstate;
  end;

  if v_err is not null then
    v_n := v_state.consecutive_failures + 1;
    update ops.job_run
       set status = 'failed', finished_at = now(), error = left(v_errstate || ': ' || v_err, 4000),
           detail = jsonb_build_object('sqlstate', v_errstate, 'consecutive_failures', v_n)
     where id = v_run_id;
    update ops.job_state
       set consecutive_failures = v_n,
           last_error = left(v_errstate || ': ' || v_err, 4000),
           backoff_until = now() + make_interval(mins => least(power(2, v_n)::integer, 60)),
           updated_at = now()
     where job_name = p_job_name;
    return jsonb_build_object('status', 'failed', 'job_run_id', v_run_id,
                              'detail', jsonb_build_object('error', v_err, 'sqlstate', v_errstate,
                                                           'consecutive_failures', v_n));
  end if;

  update ops.job_run
     set status = 'succeeded', finished_at = now(),
         items_scanned  = coalesce((v_body ->> 'scanned')::integer, 0),
         cases_opened   = coalesce((v_body ->> 'opened')::integer, 0),
         cases_resolved = coalesce((v_body ->> 'resolved')::integer, 0),
         detail = v_body
   where id = v_run_id;
  update ops.job_state
     set last_success_at = now(), consecutive_failures = 0, backoff_until = null, last_error = null, updated_at = now()
   where job_name = p_job_name;
  return jsonb_build_object('status', 'succeeded', 'job_run_id', v_run_id, 'detail', v_body);
end;
$ops$;
revoke all on function ops.run_job(text,text) from public, anon, authenticated;
grant execute on function ops.run_job(text,text) to authenticated, service_role;   -- authorizes itself

create or replace function ops.run_all_detectors()
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  c_order constant text[] := array['paid_unsettled','transfer_deadlines','release_stuck','refunds','disputes',
                                   'payout_review','reports','webhooks','jobs','notifications','reconciliation',
                                   'refresh_metrics'];
  v_name  text;
  v_res   jsonb;
  v_out   jsonb := '{}'::jsonb;
  v_fail  integer := 0;
  v_skip  integer := 0;
begin
  if not public.request_is_service_role() then
    perform ops.assert_role(array['platform_admin']);
  end if;
  foreach v_name in array c_order loop
    v_res := ops.run_job(v_name, 'cron');
    v_out := v_out || jsonb_build_object(v_name, jsonb_build_object('status', v_res ->> 'status', 'job_run_id', v_res ->> 'job_run_id',
                                                                    'opened', v_res #>> '{detail,opened}', 'resolved', v_res #>> '{detail,resolved}'));
    if v_res ->> 'status' = 'failed'  then v_fail := v_fail + 1; end if;
    if v_res ->> 'status' = 'skipped' then v_skip := v_skip + 1; end if;
  end loop;
  return jsonb_build_object('ran_at', now(), 'jobs', cardinality(c_order), 'failed', v_fail, 'skipped', v_skip, 'results', v_out);
end;
$ops$;
revoke all on function ops.run_all_detectors() from public, anon, authenticated;
grant execute on function ops.run_all_detectors() to service_role;

create or replace function ops.action_dispatch(p_action ops.action)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  a        alias for p_action;
  -- Domain attribution is the REQUESTER (the founder who decided). For an
  -- approval-gated action the executing session is the approver; the approval
  -- row and the audit actor record that separately.
  v_uid    uuid := p_action.requested_by;
  v_case   ops."case"%rowtype;
  v_ver    integer;
  v_n      integer;
  v_res    jsonb;
  v_ok     boolean;
  v_row    record;
  v_note   uuid;
  v_status text;
  v_before jsonb;
begin
  -- ── case_* ──────────────────────────────────────────────────────────────
  if a.action_type like 'case_%' and a.action_type <> 'case_create' then
    select * into v_case from ops."case" where id = a.subject_id for update;
    if not found then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','case not found');
    end if;
    v_ver := nullif(a.expected ->> 'version', '')::integer;
    if v_ver is not null and v_ver <> v_case.version then
      return jsonb_build_object('status','rejected','reject_reason','stale_state',
                                'message', format('case changed since you loaded it (version %s, you had %s)', v_case.version, v_ver),
                                'current_version', v_case.version);
    end if;
    v_before := jsonb_build_object('status', v_case.status, 'assignee', v_case.assignee,
                                   'priority', v_case.priority, 'due_at', v_case.due_at, 'version', v_case.version);
  end if;

  case a.action_type
  when 'case_create' then
    if (a.params ->> 'title') is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','title required');
    end if;
    v_res := ops.case_upsert('manual', coalesce(a.params ->> 'subject_kind','none'),
               nullif(a.params ->> 'subject_id','')::uuid, a.params ->> 'subject_ref',
               a.params ->> 'title', a.params ->> 'summary', coalesce(a.params ->> 'priority','p3'),
               nullif(a.params ->> 'due_at','')::timestamptz, 'manual');
    -- a manual case is never auto-resolved and dedupes on its own id
    update ops."case" set dedupe_key = 'manual:' || id::text, assignee = coalesce(nullif(a.params ->> 'assignee','')::uuid, assignee)
     where id = (v_res ->> 'case_id')::uuid;
    return jsonb_build_object('status','succeeded','case_id', v_res ->> 'case_id');

  when 'case_assign' then
    update ops."case" set assignee = nullif(a.params ->> 'assignee','')::uuid,
           status = case when status = 'open' and (a.params ->> 'assignee') is not null then 'in_progress' else status end,
           version = version + 1
     where id = a.subject_id returning * into v_case;
    insert into ops.case_event (case_id, actor, kind, data)
    values (a.subject_id, v_uid, 'assigned', jsonb_build_object('assignee', v_case.assignee, 'before', v_before, 'action_id', a.id));
    return jsonb_build_object('status','succeeded','version', v_case.version);

  when 'case_status' then
    v_status := a.params ->> 'status';
    if v_status not in ('open','in_progress','waiting','resolved','dismissed') then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','invalid status');
    end if;
    if v_status in ('resolved','dismissed') and coalesce(trim(a.reason),'') = '' then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','a reason is required to resolve or dismiss');
    end if;
    update ops."case"
       set status = v_status,
           resolved_at = case when v_status in ('resolved','dismissed') then now() else null end,
           resolved_by = case when v_status in ('resolved','dismissed') then v_uid else null end,
           resolution_note = case when v_status in ('resolved','dismissed') then a.reason else resolution_note end,
           version = version + 1
     where id = a.subject_id returning * into v_case;
    insert into ops.case_event (case_id, actor, kind, data)
    values (a.subject_id, v_uid, case when v_before ->> 'status' in ('resolved','dismissed') and v_status not in ('resolved','dismissed') then 'reopened' else 'status_changed' end,
            jsonb_build_object('from', v_before ->> 'status', 'to', v_status, 'reason', a.reason, 'action_id', a.id));
    return jsonb_build_object('status','succeeded','version', v_case.version);

  when 'case_priority' then
    if (a.params ->> 'priority') not in ('p1','p2','p3','p4') then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','invalid priority');
    end if;
    update ops."case" set priority = a.params ->> 'priority', version = version + 1
     where id = a.subject_id returning * into v_case;
    insert into ops.case_event (case_id, actor, kind, data)
    values (a.subject_id, v_uid, 'priority_changed', jsonb_build_object('from', v_before ->> 'priority', 'to', v_case.priority, 'action_id', a.id));
    return jsonb_build_object('status','succeeded','version', v_case.version);

  when 'case_due' then
    update ops."case" set due_at = nullif(a.params ->> 'due_at','')::timestamptz, version = version + 1
     where id = a.subject_id returning * into v_case;
    insert into ops.case_event (case_id, actor, kind, data)
    values (a.subject_id, v_uid, 'due_changed', jsonb_build_object('from', v_before ->> 'due_at', 'to', v_case.due_at, 'action_id', a.id));
    return jsonb_build_object('status','succeeded','version', v_case.version);

  when 'case_note' then
    if coalesce(trim(a.params ->> 'body'),'') = '' then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','note body required');
    end if;
    insert into ops.case_note (case_id, author, body) values (a.subject_id, v_uid, a.params ->> 'body')
    returning id into v_note;
    update ops."case" set version = version + 1 where id = a.subject_id returning version into v_ver;
    insert into ops.case_event (case_id, actor, kind, data)
    values (a.subject_id, v_uid, 'note_added', jsonb_build_object('note_id', v_note, 'action_id', a.id));
    return jsonb_build_object('status','succeeded','note_id', v_note, 'version', v_ver);

  -- ── money / marketplace: published domain functions only ───────────────
  when 'dispute_resolve' then
    if (a.params ->> 'outcome') not in ('seller_win','buyer_win','partial_refund') then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','outcome must be seller_win, buyer_win or partial_refund');
    end if;
    select status, disputed_at, dispute_resolved_at into v_row from public.transfers where id = a.subject_id;
    if not found then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','transfer not found');
    end if;
    if v_row.disputed_at is null or v_row.dispute_resolved_at is not null then
      return jsonb_build_object('status','rejected','reject_reason','stale_state','message','transfer has no open dispute');
    end if;
    if a.expected is not null and (a.expected ->> 'status') is not null and (a.expected ->> 'status') <> v_row.status then
      return jsonb_build_object('status','rejected','reject_reason','stale_state','message', format('transfer status is %s, you saw %s', v_row.status, a.expected ->> 'status'));
    end if;
    v_res := public.resolve_transfer_dispute(a.subject_id, a.params ->> 'outcome', v_uid, a.reason, a.params ->> 'notes');
    perform ops.case_auto_resolve_subject('dispute_open', a.subject_id, a.id);
    return jsonb_build_object('status','succeeded','result', v_res,
             'follow_up', case when (v_res ->> 'refund_required')::boolean
                               then 'refund_required: a refund is NOT executed by this action' else null end);

  when 'payout_release' then
    select status, payout_released_at, payout_review_status, disputed_at, dispute_resolved_at
      into v_row from public.transfers where id = a.subject_id for update;
    if not found then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','transfer not found');
    end if;
    if v_row.status <> 'seller_sent' or v_row.payout_released_at is not null then
      return jsonb_build_object('status','rejected','reject_reason','stale_state',
               'message', format('transfer is %s (released_at %s); only an unreleased seller_sent transfer can be released', v_row.status, v_row.payout_released_at));
    end if;
    if v_row.disputed_at is not null and v_row.dispute_resolved_at is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','transfer has an open dispute');
    end if;
    if a.expected is not null and (a.expected ->> 'payout_review_status') is distinct from v_row.payout_review_status then
      return jsonb_build_object('status','rejected','reject_reason','stale_state','message','payout review state changed since you loaded it');
    end if;
    v_ok := public.admin_release_held_payout(a.subject_id, v_uid, a.reason);
    if not v_ok then
      return jsonb_build_object('status','rejected','reject_reason','stale_state','message','release refused by domain guard (state changed)');
    end if;
    perform ops.case_auto_resolve_subject('payout_review', a.subject_id, a.id);
    return jsonb_build_object('status','succeeded','note','Transfer marked released; the payout worker moves funds on its next run (this is not a bank payout).');

  when 'listing_relist' then
    v_res := public.admin_relist_listing(a.subject_id, (a.params ->> 'new_ends_at')::timestamptz, v_uid);
    return jsonb_build_object('status','succeeded','result', v_res);

  when 'report_resolve' then
    v_status := a.params ->> 'status';
    if v_status not in ('reviewing','actioned','dismissed') then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','status must be reviewing, actioned or dismissed');
    end if;
    select status into v_row from public.reports where id = a.subject_id for update;
    if not found then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','report not found');
    end if;
    if a.expected is not null and (a.expected ->> 'status') is not null and (a.expected ->> 'status') <> v_row.status then
      return jsonb_build_object('status','rejected','reject_reason','stale_state','message', format('report is %s, you saw %s', v_row.status, a.expected ->> 'status'));
    end if;
    if v_row.status in ('actioned','dismissed') then
      return jsonb_build_object('status','rejected','reject_reason','stale_state','message','report already closed');
    end if;
    update public.reports set status = v_status,
           resolved_at = case when v_status in ('actioned','dismissed') then now() else null end
     where id = a.subject_id;
    if v_status in ('actioned','dismissed') then
      perform ops.case_auto_resolve_subject('report_review', a.subject_id, a.id);
    end if;
    return jsonb_build_object('status','succeeded','from', v_row.status, 'to', v_status);

  when 'user_restrict' then
    if coalesce(a.params ->> 'kind','listing_blocked') <> 'listing_blocked' then
      return jsonb_build_object('status','rejected','reject_reason','not_supported','message','only listing_blocked is enforceable (can_create_listing); account suspension has no backend mechanism');
    end if;
    if not exists (select 1 from public.profiles where id = a.subject_id) then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','user not found');
    end if;
    insert into public.seller_risk_scores (seller_id, is_listing_blocked, listing_blocked_at, listing_blocked_reason)
    values (a.subject_id, true, now(), a.reason)
    on conflict (seller_id) do update
      set is_listing_blocked = true, listing_blocked_at = now(), listing_blocked_reason = excluded.listing_blocked_reason
      where public.seller_risk_scores.is_listing_blocked = false;
    get diagnostics v_n = row_count;
    if v_n = 0 then
      return jsonb_build_object('status','rejected','reject_reason','stale_state','message','user is already listing-blocked');
    end if;
    insert into ops.user_restriction (user_id, kind, reason, actor) values (a.subject_id, 'listing_blocked', a.reason, v_uid)
    on conflict do nothing;
    return jsonb_build_object('status','succeeded','kind','listing_blocked',
             'enforcement','public.can_create_listing() returns listing_blocked; clients check it before creating a listing');

  when 'user_unrestrict' then
    update public.seller_risk_scores set is_listing_blocked = false
     where seller_id = a.subject_id and is_listing_blocked = true;
    get diagnostics v_n = row_count;
    if v_n = 0 then
      return jsonb_build_object('status','rejected','reject_reason','stale_state','message','user is not listing-blocked');
    end if;
    update ops.user_restriction set lifted_at = now(), lifted_by = v_uid, lift_reason = a.reason
     where user_id = a.subject_id and kind = 'listing_blocked' and lifted_at is null;
    return jsonb_build_object('status','succeeded','kind','listing_blocked');

  when 'refund_execute' then
    if not coalesce((select (value #>> '{}')::boolean from ops.setting where key = 'refund_execute_enabled'), false) then
      return jsonb_build_object('status','rejected','reject_reason','disabled',
               'message','refund execution is disabled until the ops-refund-execute function is deployed (see runbook); use the Stripe Dashboard SOP');
    end if;
    select status, total, stripe_payment_intent_id into v_row from public.payments where id = a.subject_id for update;
    if not found then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','payment not found');
    end if;
    if v_row.status <> 'succeeded' then
      return jsonb_build_object('status','rejected','reject_reason','stale_state', 'message', format('payment is %s; only a succeeded payment can be refunded', v_row.status));
    end if;
    if (a.params ->> 'amount_cents') is not null and ((a.params ->> 'amount_cents')::integer <= 0 or (a.params ->> 'amount_cents')::integer > v_row.total) then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','amount must be between 1 and the payment total');
    end if;
    if (a.params ->> 'amount_cents') is not null
       and (a.params ->> 'amount_cents')::integer <> v_row.total then
      return jsonb_build_object('status','rejected','reject_reason','not_supported',
               'message','partial refunds are not supported in this release: the local money model records refund status only (no refunded amount), so a partial refund would be reported as a full one. Request a full refund or use the Stripe Dashboard SOP.');
    end if;
    -- The money leg runs in the ops-refund-execute edge function (Stripe
    -- idempotency key = ops_action_<id>); it reports back through
    -- ops.record_action_outcome. Until then the action is `processing`.
    return jsonb_build_object('status','processing','handoff','ops-refund-execute',
             'stripe_payment_intent_id', v_row.stripe_payment_intent_id,
             'amount_cents', v_row.total, 'currency', 'usd');

  when 'job_retry' then
    if coalesce(a.subject_ref, a.params ->> 'job_name') is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','job_name required');
    end if;
    if to_regprocedure('ops.run_job(text,text)') is null then
      return jsonb_build_object('status','rejected','reject_reason','not_supported','message','ops.run_job not installed (migration 117)');
    end if;
    execute 'select ops.run_job($1, $2)' into v_res using coalesce(a.subject_ref, a.params ->> 'job_name'), 'manual';
    return jsonb_build_object('status', case when v_res ->> 'status' = 'failed' then 'failed' else 'succeeded' end, 'result', v_res);

  when 'setting_set' then
    if not exists (select 1 from ops.setting where key = a.subject_ref) then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','unknown setting');
    end if;
    if a.params -> 'value' is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','value required');
    end if;
    select value into v_before from ops.setting where key = a.subject_ref for update;
    if jsonb_typeof(v_before) <> jsonb_typeof(a.params -> 'value') then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message', format('setting is %s, not %s', jsonb_typeof(v_before), jsonb_typeof(a.params -> 'value')));
    end if;
    update ops.setting set value = a.params -> 'value', updated_at = now(), updated_by = v_uid where key = a.subject_ref;
    return jsonb_build_object('status','succeeded','before', v_before, 'after', a.params -> 'value');

  else
    return jsonb_build_object('status','rejected','reject_reason','not_supported','message','unknown action type');
  end case;
end;
$ops$;
revoke all on function ops.action_dispatch(ops.action) from public, anon, authenticated;

drop function ops.detect_refund_resolution();
delete from ops.setting where key = 'refund_resolution_detector_enabled';
alter table ops."case" drop constraint case_case_type_check;
alter table ops."case" add constraint case_case_type_check
  check (case_type = any (array['paid_unsettled', 'transfer_deadline_soon', 'transfer_overdue', 'release_stuck', 'refund_pending', 'refund_failed', 'dispute_open', 'dispute_evidence_due', 'payout_review', 'report_review', 'webhook_stuck', 'job_failure', 'notification_failure', 'reconciliation_mismatch', 'manual']));
alter table ops.case_event drop constraint case_event_kind_check;
alter table ops.case_event add constraint case_event_kind_check
  check (kind = any (array['created', 'seen', 'assigned', 'status_changed', 'priority_changed', 'due_changed', 'note_added', 'action_requested', 'action_outcome', 'auto_resolved', 'reopened']));
commit;

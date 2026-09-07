-- ============================================================================
-- 118_ops_console_corrections.sql — Operating Console package, corrections
-- from the independent review of PR #55 (findings 1, 2, 4, 6).
--
-- WHAT THIS MIGRATION IS. Additive / body-only re-creates inside `ops`, plus
-- ONE storage policy. It fixes:
--   F2  founder evidence access — a `proof-docs operator read` storage policy
--       (operator role + aal2 + the object must be referenced by a transfer or
--       listing row) and ops.evidence_access(), which resolves the eligible
--       path from the ACTUAL record and writes an `evidence.viewed` audit row.
--       No arbitrary bucket/path can be signed; buyer/seller policies untouched.
--   F4  refunds — full refunds only (partials rejected in precheck AND
--       dispatch); ops.executor_claim() re-checks the enabled flag, the console
--       pause, the approval and its hash at execution/resume time and fences
--       concurrent attempts with a lease; ops.record_action_outcome() is
--       monotonic (terminal states never regress; provider_ref is pinned);
--       the refund detector opens a case for a crash left at `processing` and
--       completes succeeded_at_provider → succeeded once the webhook lands;
--       the refunded-volume metric stops claiming an amount it cannot know.
--   F6  containment — ops.setting `actions_enabled` (console-wide pause of
--       every mutation; reads stay available).
--
-- ZERO changes to public.* definitions (Gate-2 parity untouched). The storage
-- policy is a new row on storage.objects (test 132's production fixture is
-- updated in the same PR).
--
-- Rollback: supabase/rollbacks/118_ops_console_corrections_rollback.sql
-- Verification: select to_regprocedure('ops.executor_claim(uuid,integer)') is not null;
--               select polname from pg_policy where polrelid='storage.objects'::regclass and polname='proof-docs operator read';
-- Locks/runtime: ALTER TABLE ops.action ADD COLUMN (no rewrite); function re-creates.
-- ============================================================================
begin;

-- ----------------------------------------------------------------------------
-- PART 1 — console pause + executor lease columns
-- ----------------------------------------------------------------------------
insert into ops.setting (key, value) values ('actions_enabled', 'true'::jsonb) on conflict (key) do nothing;

alter table ops.action add column if not exists claimed_until timestamptz;
alter table ops.action add column if not exists attempt integer not null default 0;

create or replace function ops.assert_actions_enabled()
returns void language plpgsql stable security definer set search_path = ''
as $ops$
begin
  if not coalesce((select (value #>> '{}')::boolean from ops.setting where key = 'actions_enabled'), true) then
    raise exception 'precondition_failed: console_actions_paused — a founder paused console actions (ops.setting actions_enabled = false); reads remain available';
  end if;
end;
$ops$;
revoke all on function ops.assert_actions_enabled() from public, anon, authenticated;

create or replace function ops.execute_action(
  p_idempotency_key text, p_action_type text, p_subject_kind text, p_subject_id uuid,
  p_params jsonb default '{}'::jsonb, p_reason text default null, p_expected jsonb default null,
  p_subject_ref text default null)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_uid   uuid := auth.uid();
  v_role  text;
  a       ops.action%rowtype;
  v_appr  uuid;
  v_ttl   integer;
  v_res   jsonb;
begin
  perform ops.assert_reader();
  -- The pause switch itself stays operable, so a founder can un-pause from
  -- the console (platform_admin only; audited like every setting change).
  if not (p_action_type = 'setting_set' and p_subject_ref = 'actions_enabled') then
    perform ops.assert_actions_enabled();
  end if;
  v_role := ops.actor_role();

  if p_idempotency_key is null or p_idempotency_key !~ '^[A-Za-z0-9._:-]{8,80}$' then
    raise exception 'invalid_input: idempotency key must be 8-80 chars of [A-Za-z0-9._:-]';
  end if;
  if p_action_type is null or p_action_type not in (
      'case_create','case_assign','case_status','case_priority','case_due','case_note',
      'dispute_resolve','payout_release','listing_relist','report_resolve',
      'user_restrict','user_unrestrict','refund_execute','job_retry','setting_set') then
    raise exception 'invalid_input: unknown action_type %', coalesce(p_action_type, '(null)');
  end if;
  if p_subject_kind is null or p_subject_kind not in ('case','payment','transfer','listing','user','report','job','setting','none') then
    raise exception 'invalid_input: unknown subject_kind %', coalesce(p_subject_kind, '(null)');
  end if;

  -- action ↔ subject pairing (a case verb may only target a case, etc.)
  if not (case p_action_type
            when 'case_create'     then p_subject_kind in ('none','payment','transfer','listing','user','report','job')
            when 'dispute_resolve' then p_subject_kind = 'transfer'
            when 'payout_release'  then p_subject_kind = 'transfer'
            when 'listing_relist'  then p_subject_kind = 'listing'
            when 'report_resolve'  then p_subject_kind = 'report'
            when 'user_restrict'   then p_subject_kind = 'user'
            when 'user_unrestrict' then p_subject_kind = 'user'
            when 'refund_execute'  then p_subject_kind = 'payment'
            when 'job_retry'       then p_subject_kind = 'job'
            when 'setting_set'     then p_subject_kind = 'setting'
            else p_subject_kind = 'case' end) then
    raise exception 'invalid_input: % cannot target a %', p_action_type, p_subject_kind;
  end if;
  if p_subject_id is null and p_action_type not in ('case_create','job_retry','setting_set') then
    raise exception 'invalid_input: subject_id required for %', p_action_type;
  end if;

  -- idempotency: the same key always returns the same action
  select * into a from ops.action where idempotency_key = p_idempotency_key;
  if found then
    return jsonb_build_object('status','idempotent_replay','action_id', a.id, 'state', a.state,
                              'result', a.result, 'approval_id', a.approval_id);
  end if;

  if not (v_role = any(ops.action_allowed_roles(p_action_type))) then
    raise exception 'insufficient_privilege: % may not perform %', v_role, p_action_type using errcode = '42501';
  end if;
  if p_action_type in ('dispute_resolve','payout_release','listing_relist','report_resolve','user_restrict',
                       'user_unrestrict','refund_execute','setting_set')
     and coalesce(trim(p_reason), '') = '' then
    raise exception 'invalid_input: a reason is required for %', p_action_type;
  end if;

  begin
    insert into ops.action (idempotency_key, action_type, subject_kind, subject_id, subject_ref, params, expected, reason, requested_by)
    values (p_idempotency_key, p_action_type, p_subject_kind, p_subject_id, p_subject_ref,
            coalesce(p_params, '{}'::jsonb), p_expected, nullif(trim(p_reason), ''), v_uid)
    returning * into a;
  exception when unique_violation then
    select * into a from ops.action where idempotency_key = p_idempotency_key;
    return jsonb_build_object('status','idempotent_replay','action_id', a.id, 'state', a.state,
                              'result', a.result, 'approval_id', a.approval_id);
  end;

  perform ops.audit_write('action.requested', a.subject_kind, a.subject_id, a.subject_ref, a.reason,
                          a.expected, jsonb_build_object('action_type', a.action_type, 'params', a.params),
                          'requested', a.correlation_id, a.id);
  if a.subject_kind = 'case' and a.action_type <> 'case_create' then
    insert into ops.case_event (case_id, actor, kind, data)
    select a.subject_id, v_uid, 'action_requested', jsonb_build_object('action_id', a.id, 'action_type', a.action_type)
     where exists (select 1 from ops."case" where id = a.subject_id);
  end if;

  if ops.action_requires_approval(a.action_type) then
    v_res := ops.action_precheck(a);
    if v_res is not null then
      update ops.action set state = 'rejected', reject_reason = v_res ->> 'reject_reason', result = v_res,
             completed_at = now(), version = version + 1 where id = a.id;
      perform ops.audit_write('action.' || a.action_type, a.subject_kind, a.subject_id, a.subject_ref, a.reason,
                              a.expected, v_res, 'rejected', a.correlation_id, a.id);
      return jsonb_build_object('status','rejected','action_id', a.id, 'result', v_res,
                                'reject_reason', v_res ->> 'reject_reason', 'message', v_res ->> 'message');
    end if;
    v_ttl := coalesce((select (value #>> '{}')::integer from ops.setting where key = 'approval_ttl_hours'), 72);
    insert into ops.approval (action_id, action_hash, requested_by, expires_at)
    values (a.id, ops.action_hash(a.action_type, a.subject_kind, a.subject_id, a.subject_ref, a.params),
            v_uid, now() + make_interval(hours => v_ttl))
    returning id into v_appr;
    update ops.action set state = 'awaiting_approval', approval_id = v_appr, version = version + 1 where id = a.id;
    return jsonb_build_object('status','awaiting_approval','action_id', a.id, 'approval_id', v_appr,
                              'message','a second founder must approve this action');
  end if;

  return ops.action_run(a.id);
end;
$ops$;
revoke all on function ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text) from public, anon, authenticated;
grant execute on function ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text) to authenticated;

create or replace function ops.approve_action(p_action_id uuid, p_decision text, p_reason text)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_uid uuid := auth.uid();
  a     ops.action%rowtype;
  ap    ops.approval%rowtype;
begin
  perform ops.assert_role(array['platform_admin']);
  perform ops.assert_actions_enabled();
  if p_decision not in ('approve','deny') then
    raise exception 'invalid_input: decision must be approve or deny';
  end if;
  if coalesce(trim(p_reason),'') = '' then
    raise exception 'invalid_input: a reason is required';
  end if;
  select * into a from ops.action where id = p_action_id for update;
  if not found then
    raise exception 'precondition_failed: action not found';
  end if;
  select * into ap from ops.approval where action_id = a.id and state = 'pending' for update;
  if not found then
    return jsonb_build_object('status','rejected','reject_reason','stale_state','message','no pending approval for this action', 'state', a.state);
  end if;
  if ap.requested_by = v_uid then
    raise exception 'precondition_failed: self_approval — the requester cannot approve their own action';
  end if;
  if ap.expires_at < now() then
    update ops.approval set state = 'expired' where id = ap.id;
    update ops.action set state = 'rejected', reject_reason = 'approval_expired', completed_at = now(), version = version + 1 where id = a.id;
    perform ops.audit_write('approval.expired', a.subject_kind, a.subject_id, a.subject_ref, p_reason, null, null, 'expired', a.correlation_id, a.id);
    return jsonb_build_object('status','rejected','reject_reason','approval_expired');
  end if;
  if ap.action_hash <> ops.action_hash(a.action_type, a.subject_kind, a.subject_id, a.subject_ref, a.params) then
    update ops.approval set state = 'stale' where id = ap.id;
    update ops.action set state = 'rejected', reject_reason = 'approval_stale', completed_at = now(), version = version + 1 where id = a.id;
    perform ops.audit_write('approval.stale', a.subject_kind, a.subject_id, a.subject_ref, p_reason, null, null, 'stale', a.correlation_id, a.id);
    return jsonb_build_object('status','rejected','reject_reason','approval_stale','message','the action terms changed after approval was requested');
  end if;

  if p_decision = 'deny' then
    update ops.approval set state = 'denied', decided_by = v_uid, decided_at = now(), reason = p_reason where id = ap.id;
    update ops.action set state = 'rejected', reject_reason = 'denied', completed_at = now(), version = version + 1 where id = a.id;
    perform ops.audit_write('approval.denied', a.subject_kind, a.subject_id, a.subject_ref, p_reason, null,
                            jsonb_build_object('action_id', a.id), 'denied', a.correlation_id, a.id);
    return jsonb_build_object('status','rejected','reject_reason','denied','action_id', a.id);
  end if;

  update ops.approval set state = 'approved', decided_by = v_uid, decided_at = now(), reason = p_reason where id = ap.id;
  perform ops.audit_write('approval.approved', a.subject_kind, a.subject_id, a.subject_ref, p_reason, null,
                          jsonb_build_object('action_id', a.id, 'action_hash', ap.action_hash), 'approved', a.correlation_id, a.id);
  return ops.action_run(a.id);
end;
$ops$;
revoke all on function ops.approve_action(uuid,text,text) from public, anon, authenticated;
grant execute on function ops.approve_action(uuid,text,text) to authenticated;

-- ----------------------------------------------------------------------------
-- PART 2 — refunds: full only; claim; monotonic outcomes; detector
-- ----------------------------------------------------------------------------
create or replace function ops.action_precheck(p_action ops.action)
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare v_row record;
begin
  case p_action.action_type
  when 'payout_release' then
    select status, payout_released_at, disputed_at, dispute_resolved_at, payout_review_status
      into v_row from public.transfers where id = p_action.subject_id;
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
    if p_action.expected is not null and (p_action.expected ->> 'payout_review_status') is distinct from v_row.payout_review_status then
      return jsonb_build_object('status','rejected','reject_reason','stale_state','message','payout review state changed since you loaded it');
    end if;
  when 'refund_execute' then
    if not coalesce((select (value #>> '{}')::boolean from ops.setting where key = 'refund_execute_enabled'), false) then
      return jsonb_build_object('status','rejected','reject_reason','disabled',
               'message','refund execution is disabled until the ops-refund-execute function is deployed (see runbook); use the Stripe Dashboard SOP');
    end if;
    select status, total into v_row from public.payments where id = p_action.subject_id;
    if not found then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','payment not found');
    end if;
    if v_row.status <> 'succeeded' then
      return jsonb_build_object('status','rejected','reject_reason','stale_state', 'message', format('payment is %s; only a succeeded payment can be refunded', v_row.status));
    end if;
    if (p_action.params ->> 'amount_cents') is not null
       and ((p_action.params ->> 'amount_cents')::integer <= 0 or (p_action.params ->> 'amount_cents')::integer > v_row.total) then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','amount must be between 1 and the payment total');
    end if;
    if (p_action.params ->> 'amount_cents') is not null
       and (p_action.params ->> 'amount_cents')::integer <> v_row.total then
      return jsonb_build_object('status','rejected','reject_reason','not_supported',
               'message','partial refunds are not supported in this release: the local money model records refund status only (no refunded amount), so a partial refund would be reported as a full one. Request a full refund or use the Stripe Dashboard SOP.');
    end if;
  else
    null;
  end case;
  return null;
end;
$ops$;
revoke all on function ops.action_precheck(ops.action) from public, anon, authenticated;

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

create or replace function ops.record_action_outcome(
  p_action_id uuid, p_state text, p_result jsonb, p_error text, p_provider_ref text)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  a ops.action%rowtype;
  v_allowed text[];
begin
  if not public.request_is_service_role() then
    raise exception 'insufficient_privilege: service_role only' using errcode = '42501';
  end if;
  if p_state not in ('succeeded','succeeded_at_provider','failed','unknown','processing') then
    raise exception 'invalid_input: bad state %', p_state;
  end if;
  select * into a from ops.action where id = p_action_id for update;
  if not found then
    raise exception 'precondition_failed: action not found';
  end if;

  -- Monotonic lifecycle. Terminal facts are never rewritten by a later or
  -- out-of-order callback; a replay of the same terminal state is a no-op.
  v_allowed := case a.state
    when 'processing'            then array['processing','succeeded_at_provider','failed','unknown','succeeded']
    when 'unknown'               then array['processing','succeeded_at_provider','failed','unknown','succeeded']
    when 'succeeded_at_provider' then array['succeeded']
    else array[]::text[] end;
  -- One action ↔ one provider object: a different refund id is never adopted
  -- silently, whatever the state; it is surfaced as a mismatch for a founder.
  if a.provider_ref is not null and p_provider_ref is not null and a.provider_ref <> p_provider_ref then
    perform ops.audit_write('action.outcome.refused', a.subject_kind, a.subject_id, a.subject_ref, null,
                            jsonb_build_object('provider_ref', a.provider_ref), jsonb_build_object('attempted_provider_ref', p_provider_ref, 'attempted_state', p_state),
                            'refused', a.correlation_id, a.id);
    return jsonb_build_object('status','refused','reason','provider_ref_mismatch','state', a.state, 'provider_ref', a.provider_ref);
  end if;
  if a.state = p_state and a.state in ('succeeded','failed','rejected','succeeded_at_provider') then
    return jsonb_build_object('status','idempotent_replay','state', a.state);
  end if;
  if not (p_state = any(v_allowed)) then
    perform ops.audit_write('action.outcome.refused', a.subject_kind, a.subject_id, a.subject_ref, null,
                            jsonb_build_object('state', a.state), jsonb_build_object('attempted_state', p_state, 'provider_ref', p_provider_ref),
                            'refused', a.correlation_id, a.id);
    return jsonb_build_object('status','refused','reason','terminal','state', a.state);
  end if;

  update ops.action
     set state = p_state,
         result = coalesce(a.result, '{}'::jsonb) || coalesce(p_result, '{}'::jsonb),
         error = p_error,
         provider_ref = coalesce(p_provider_ref, a.provider_ref),
         completed_at = case when p_state in ('succeeded','failed') then now() else completed_at end,
         claimed_until = case when p_state = 'processing' then claimed_until else null end,
         version = version + 1
   where id = a.id;
  perform ops.audit_write('action.outcome.' || a.action_type, a.subject_kind, a.subject_id, a.subject_ref, null,
                          jsonb_build_object('state', a.state), jsonb_build_object('state', p_state, 'provider_ref', p_provider_ref, 'error', p_error),
                          p_state, a.correlation_id, a.id);
  return jsonb_build_object('status','ok','action_id', a.id, 'state', p_state);
end;
$ops$;
revoke all on function ops.record_action_outcome(uuid,text,jsonb,text,text) from public, anon, authenticated;
grant execute on function ops.record_action_outcome(uuid,text,jsonb,text,text) to service_role;

-- Executor claim: the ONLY way an executor learns the terms of a refund. Every
-- gate that mattered at request time is re-evaluated here, at execution or
-- resumption: enabled flag, console pause, approval present and still bound to
-- the exact action terms, lifecycle state, and a lease against concurrent
-- attempts. Terms come from the payment row, never from the caller.
create or replace function ops.executor_claim(p_action_id uuid, p_lease_seconds integer default 300)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  a    ops.action%rowtype;
  ap   ops.approval%rowtype;
  p    public.payments%rowtype;
  v_prev_sent boolean;
begin
  if not public.request_is_service_role() then
    raise exception 'insufficient_privilege: service_role only' using errcode = '42501';
  end if;
  select * into a from ops.action where id = p_action_id for update;
  if not found then
    return jsonb_build_object('status','refused','reason','not_found');
  end if;
  if a.action_type <> 'refund_execute' then
    return jsonb_build_object('status','refused','reason','wrong_type','state', a.state);
  end if;
  if a.state in ('succeeded','failed','rejected') then
    return jsonb_build_object('status','refused','reason','terminal','state', a.state);
  end if;
  if a.state = 'succeeded_at_provider' then
    return jsonb_build_object('status','refused','reason','succeeded_at_provider','state', a.state, 'provider_ref', a.provider_ref);
  end if;
  if a.state not in ('processing','unknown') then
    return jsonb_build_object('status','refused','reason','not_executable','state', a.state);
  end if;
  if not coalesce((select (value #>> '{}')::boolean from ops.setting where key = 'actions_enabled'), true) then
    return jsonb_build_object('status','refused','reason','paused','state', a.state);
  end if;
  if not coalesce((select (value #>> '{}')::boolean from ops.setting where key = 'refund_execute_enabled'), false) then
    return jsonb_build_object('status','refused','reason','disabled','state', a.state);
  end if;
  select * into ap from ops.approval where action_id = a.id and state = 'approved' order by decided_at desc limit 1;
  if not found then
    return jsonb_build_object('status','refused','reason','approval_missing','state', a.state);
  end if;
  if ap.action_hash <> ops.action_hash(a.action_type, a.subject_kind, a.subject_id, a.subject_ref, a.params) then
    return jsonb_build_object('status','refused','reason','approval_stale','state', a.state);
  end if;
  if a.claimed_until is not null and a.claimed_until > now() then
    return jsonb_build_object('status','refused','reason','claim_busy','state', a.state, 'claimed_until', a.claimed_until);
  end if;
  select * into p from public.payments where id = a.subject_id;
  if not found then
    return jsonb_build_object('status','refused','reason','payment_missing','state', a.state);
  end if;
  if p.status = 'refunded' then
    return jsonb_build_object('status','refused','reason','already_refunded_locally','state', a.state, 'stripe_refund_id', p.stripe_refund_id);
  end if;
  if p.status <> 'succeeded' or p.stripe_payment_intent_id is null then
    return jsonb_build_object('status','refused','reason','payment_not_refundable','state', a.state, 'payment_status', p.status);
  end if;

  v_prev_sent := a.attempt > 0 or a.provider_ref is not null or (a.result ? 'stripe_request_started_at');
  update ops.action
     set claimed_until = now() + make_interval(secs => greatest(coalesce(p_lease_seconds, 300), 30)),
         attempt = attempt + 1,
         state = 'processing',
         version = version + 1
   where id = a.id;
  perform ops.audit_write('action.claim.refund_execute', a.subject_kind, a.subject_id, a.subject_ref, null,
                          jsonb_build_object('state', a.state, 'attempt', a.attempt),
                          jsonb_build_object('attempt', a.attempt + 1, 'previously_sent', v_prev_sent),
                          'claimed', a.correlation_id, a.id);
  return jsonb_build_object(
    'status', 'claimed', 'action_id', a.id, 'payment_id', p.id,
    'stripe_payment_intent_id', p.stripe_payment_intent_id,
    'amount_cents', p.total, 'payment_total_cents', p.total, 'currency', 'usd',
    'reason_code', a.params ->> 'reason_code',
    'previously_sent', v_prev_sent, 'provider_ref', a.provider_ref, 'attempt', a.attempt + 1,
    'stripe_livemode', p.stripe_livemode);
end;
$ops$;
revoke all on function ops.executor_claim(uuid,integer) from public, anon, authenticated;
grant execute on function ops.executor_claim(uuid,integer) to service_role;

create or replace function ops.detect_refunds()
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_pending_keys text[] := array[]::text[];
  v_failed_keys  text[] := array[]::text[];
  v_scanned integer := 0;
  v_opened  integer := 0;
  v_resolved integer := 0;
  r         record;
  v_res     jsonb;
begin
  for r in
    select p.id as payment_id, p.status as payment_status, p.total, p.stripe_payment_intent_id, t.id as transfer_id,
           l.event_name,
           case when t.dispute_resolution in ('resolved_buyer_refunded', 'resolved_partial_refund')
                then format('dispute resolved %s at %s', t.dispute_resolution,
                            to_char(t.dispute_resolved_at at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'))
                else format('transfer expired at %s and the payment is still succeeded',
                            to_char(coalesce(t.expired_at, t.expires_at) at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"')) end as why
      from public.transfers t
      join public.payments p on p.id = t.payment_id
      left join public.listings l on l.id = t.listing_id
     where p.status <> 'refunded'
       and ((t.dispute_resolution in ('resolved_buyer_refunded', 'resolved_partial_refund'))
            or (t.status = 'expired' and p.status = 'succeeded'
                and coalesce(t.expired_at, t.expires_at, t.created_at) < now() - interval '60 minutes'))
  loop
    v_scanned := v_scanned + 1;
    v_res := ops.detect_case('refund_pending', 'payment', r.payment_id, null,
               'Refund owed to buyer',
               format('Payment %s ($%s, status %s) for "%s": %s. No refund has landed (payments.status <> refunded).',
                      r.stripe_payment_intent_id, to_char(coalesce(r.total, 0) / 100.0, 'FM999999990.00'),
                      r.payment_status, coalesce(r.event_name, '?'), r.why),
               'p1', null, 'refunds');
    v_pending_keys := v_pending_keys || (v_res ->> 'dedupe_key');
    if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
  end loop;

  -- Completion: a refund that succeeded at the provider is confirmed locally
  -- once the charge.refunded webhook has marked the payment refunded.
  for r in
    select a.id as action_id
      from ops.action a
      join public.payments p on p.id = a.subject_id
     where a.action_type = 'refund_execute' and a.state = 'succeeded_at_provider' and p.status = 'refunded'
  loop
    update ops.action set state = 'succeeded', completed_at = now(), claimed_until = null, version = version + 1
     where id = r.action_id and state = 'succeeded_at_provider';
    perform ops.audit_write('action.outcome.refund_execute', 'payment', null, null, null,
                            jsonb_build_object('state', 'succeeded_at_provider'),
                            jsonb_build_object('state', 'succeeded', 'confirmed_by', 'charge.refunded webhook'),
                            'succeeded', null, r.action_id);
  end loop;

  for r in
    select a.id as action_id, a.subject_id as payment_id, a.state, a.error, a.provider_ref, a.updated_at, a.completed_at
      from ops.action a
     where a.action_type = 'refund_execute'
       and a.subject_id is not null
       and (a.state in ('failed', 'unknown')
            or (a.state = 'succeeded_at_provider' and a.updated_at < now() - interval '60 minutes')
            -- a crash between the claim and the outcome callback leaves the
            -- action at `processing` with an expired (or no) lease
            or (a.state = 'processing'
                and ((a.claimed_until is not null and a.claimed_until < now() - interval '30 minutes')
                     or (a.claimed_until is null and a.updated_at < now() - interval '30 minutes'))))
       and not exists (select 1 from public.payments p where p.id = a.subject_id and p.status = 'refunded')
  loop
    v_scanned := v_scanned + 1;
    v_res := ops.detect_case('refund_failed', 'payment', r.payment_id, null,
               'Refund execution needs attention',
               format('ops action %s (refund_execute) is %s%s%s; the payment is not refunded locally.',
                      r.action_id, r.state,
                      case when r.provider_ref is not null then format(' (provider ref %s)', r.provider_ref) else '' end,
                      case when r.error is not null then format(': %s', left(r.error, 500)) else '' end),
               'p1', null, 'refunds');
    v_failed_keys := v_failed_keys || (v_res ->> 'dedupe_key');
    if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
  end loop;

  v_resolved := ops.detect_sweep('refund_pending', v_pending_keys) + ops.detect_sweep('refund_failed', v_failed_keys);
  return jsonb_build_object('scanned', v_scanned, 'opened', v_opened, 'resolved', v_resolved);
end;
$ops$;
revoke all on function ops.detect_refunds() from public, anon, authenticated, service_role;

create or replace function ops.money_overview(p_from date default null, p_to date default null)
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare
  v_to    date := coalesce(p_to,   (now() at time zone 'UTC')::date);
  v_from  date := coalesce(p_from, v_to - 30);
  lo      timestamptz;
  hi      timestamptz;
  m       jsonb;
  v_val   bigint; v_cnt bigint;
begin
  perform ops.assert_reader();
  if v_from > v_to then
    raise exception 'invalid_input: from must not be after to';
  end if;
  if v_to - v_from > 400 then
    raise exception 'invalid_input: range must be 400 days or fewer';
  end if;
  lo := (v_from::timestamp) at time zone 'UTC';
  hi := ((v_to + 1)::timestamp) at time zone 'UTC';
  m := '{}'::jsonb;

  -- Gross captured volume
  select coalesce(sum(p.total), 0), count(*) into v_val, v_cnt
    from public.payments p
   where p.status in ('succeeded','refunded') and p.paid_at >= lo and p.paid_at < hi;
  m := m || jsonb_build_object('gross_captured_volume', jsonb_build_object(
         'value_cents', v_val, 'count', v_cnt, 'currency', 'USD', 'from', v_from, 'to', v_to,
         'definition', 'Sum of payments.total where status in (succeeded, refunded). Captured card volume including buyer fees; refunds are NOT netted out — see refunded_volume.',
         'source', 'public.payments', 'basis', 'paid_at, UTC calendar day'));

  -- Refunded volume
  select coalesce(sum(p.total), 0), count(*) into v_val, v_cnt
    from public.payments p
   where p.status = 'refunded' and p.refunded_at >= lo and p.refunded_at < hi;
  -- The local model records refund STATUS only: charge.refunded (which Stripe
  -- also sends for partial refunds) flips payments.status to refunded and no
  -- refunded amount is stored. The amount is therefore an UPPER BOUND, never a
  -- headline figure.
  m := m || jsonb_build_object('refunded_volume', jsonb_build_object(
         'value_cents', null, 'upper_bound_cents', v_val, 'count', v_cnt, 'certainty', 'uncertain',
         'currency', 'USD', 'from', v_from, 'to', v_to,
         'definition', 'Count of payments with status = refunded. The amount is not available locally: payments records refund status only, and Stripe sends charge.refunded for partial refunds too, so Σ payments.total is only an upper bound. Verify amounts in the Stripe Dashboard.',
         'note', 'upper_bound_cents = Σ payments.total over refunded rows; the true refunded amount may be lower.',
         'source', 'public.payments', 'basis', 'refunded_at, UTC calendar day'));

  -- Platform fees (gross, pre-refund)
  select coalesce(sum(p.buyer_fee + coalesce(p.seller_fee, 0)), 0), count(*) into v_val, v_cnt
    from public.payments p
   where p.status = 'succeeded' and p.paid_at >= lo and p.paid_at < hi;
  m := m || jsonb_build_object('platform_fees_gross', jsonb_build_object(
         'value_cents', v_val, 'count', v_cnt, 'currency', 'USD', 'from', v_from, 'to', v_to,
         'definition', 'Sum of buyer_fee + seller_fee on succeeded payments. Gross and pre-refund; not revenue.',
         'source', 'public.payments', 'basis', 'paid_at, UTC calendar day'));

  -- Seller funds released to connected account
  select coalesce(sum(p.amount - coalesce(p.seller_fee, 0)), 0), count(*) into v_val, v_cnt
    from public.transfers t join public.payments p on p.id = t.payment_id
   where t.stripe_transfer_id is not null and t.payout_released_at >= lo and t.payout_released_at < hi;
  m := m || jsonb_build_object('seller_funds_released', jsonb_build_object(
         'value_cents', v_val, 'count', v_cnt, 'currency', 'USD', 'from', v_from, 'to', v_to,
         'definition', 'Sum of payments.amount - seller_fee for transfers whose stripe_transfer_id is set (a Stripe Transfer to the seller''s connected account exists). Not a bank payout.',
         'source', 'public.transfers + public.payments', 'basis', 'payout_released_at, UTC calendar day'));

  -- Seller funds pending (point in time)
  select coalesce(sum(p.amount - coalesce(p.seller_fee, 0)), 0), count(*) into v_val, v_cnt
    from public.transfers t join public.payments p on p.id = t.payment_id
   where t.status in ('seller_sent','buyer_confirmed','auto_released') and t.stripe_transfer_id is null
     and p.status = 'succeeded';
  m := m || jsonb_build_object('seller_funds_pending', jsonb_build_object(
         'value_cents', v_val, 'count', v_cnt, 'currency', 'USD', 'from', null, 'to', null,
         'definition', 'Seller share (amount - seller_fee) of transfers in seller_sent / buyer_confirmed / auto_released with no Stripe Transfer yet. Point-in-time, not a date range.',
         'source', 'public.transfers + public.payments', 'basis', 'now()'));

  -- Bank payouts — not tracked
  m := m || jsonb_build_object('bank_payouts', jsonb_build_object(
         'value_cents', null, 'count', null, 'currency', 'USD', 'from', null, 'to', null,
         'definition', 'Not tracked. Payouts from connected accounts to sellers'' banks are Stripe-side; the payout.paid webhook is only logged.',
         'source', null, 'basis', 'not_tracked'));

  return jsonb_build_object(
    'from', v_from, 'to', v_to, 'currency', 'USD', 'computed_at', now(),
    'metrics', m,
    'snapshot', coalesce((select jsonb_agg(jsonb_build_object('key', s.key, 'value', s.value, 'computed_at', s.computed_at) order by s.key)
                            from ops.metric_snapshot s), '[]'::jsonb),
    'snapshot_computed_at', (select max(computed_at) from ops.metric_snapshot));
end;
$ops$;
revoke all on function ops.money_overview(date,date) from public, anon, authenticated;
grant execute on function ops.money_overview(date,date) to authenticated;

create or replace function ops.refresh_metrics()
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_now   timestamptz := now();
  v_from  timestamptz := (date_trunc('day', now() at time zone 'utc') - interval '30 days') at time zone 'utc';
  v_rows  jsonb := '{}'::jsonb;
  v_n     integer := 0;
  v_key   text;
  v_val   jsonb;
begin
  -- Gross captured volume: Σ payments.total, status ∈ (succeeded, refunded), by paid_at.
  select jsonb_build_object(
           'definition', 'Sum of payments.total where status in (succeeded, refunded); refunds are NOT netted here',
           'basis', 'paid_at (UTC date)', 'currency', 'USD',
           'window_30d', jsonb_build_object('count', count(*) filter (where p.paid_at >= v_from),
                                            'cents', coalesce(sum(p.total) filter (where p.paid_at >= v_from), 0)),
           'all_time',   jsonb_build_object('count', count(*), 'cents', coalesce(sum(p.total), 0)))
    into v_val
    from public.payments p where p.status in ('succeeded', 'refunded');
  v_rows := v_rows || jsonb_build_object('money.gross_captured', v_val);

  -- Refunded volume: Σ payments.total, status = refunded, by refunded_at.
  select jsonb_build_object(
           'definition', 'Count of payments with status = refunded; amount NOT available locally (status-only model, partial refunds indistinguishable) — cents below are an upper bound',
           'basis', 'refunded_at (UTC date)', 'currency', 'USD', 'certainty', 'uncertain', 'value_cents', null,
           'window_30d', jsonb_build_object('count', count(*) filter (where coalesce(p.refunded_at, p.paid_at) >= v_from),
                                            'upper_bound_cents', coalesce(sum(p.total) filter (where coalesce(p.refunded_at, p.paid_at) >= v_from), 0)),
           'all_time',   jsonb_build_object('count', count(*), 'upper_bound_cents', coalesce(sum(p.total), 0)))
    into v_val
    from public.payments p where p.status = 'refunded';
  v_rows := v_rows || jsonb_build_object('money.refunded', v_val);

  -- Platform fees (gross, pre-refund): Σ buyer_fee + seller_fee on succeeded, by paid_at.
  select jsonb_build_object(
           'definition', 'Sum of buyer_fee + seller_fee on succeeded payments (gross, before refunds)',
           'basis', 'paid_at (UTC date)', 'currency', 'USD',
           'window_30d', jsonb_build_object('count', count(*) filter (where p.paid_at >= v_from),
                                            'cents', coalesce(sum(p.buyer_fee + p.seller_fee) filter (where p.paid_at >= v_from), 0)),
           'all_time',   jsonb_build_object('count', count(*), 'cents', coalesce(sum(p.buyer_fee + p.seller_fee), 0)))
    into v_val
    from public.payments p where p.status = 'succeeded';
  v_rows := v_rows || jsonb_build_object('money.platform_fees', v_val);

  -- Seller funds released to connected account: transfers.stripe_transfer_id set, Σ amount - seller_fee, by payout_released_at.
  select jsonb_build_object(
           'definition', 'Transfers with a Stripe connected-account transfer id; sum of payments.amount - seller_fee. Not a bank payout.',
           'basis', 'payout_released_at (UTC date)', 'currency', 'USD',
           'window_30d', jsonb_build_object('count', count(*) filter (where t.payout_released_at >= v_from),
                                            'cents', coalesce(sum(p.amount - coalesce(p.seller_fee, 0)) filter (where t.payout_released_at >= v_from), 0)),
           'all_time',   jsonb_build_object('count', count(*), 'cents', coalesce(sum(p.amount - coalesce(p.seller_fee, 0)), 0)))
    into v_val
    from public.transfers t join public.payments p on p.id = t.payment_id
   where t.stripe_transfer_id is not null;
  v_rows := v_rows || jsonb_build_object('money.released_to_connected', v_val);

  -- Seller funds pending: seller_sent / buyer_confirmed / auto_released without stripe_transfer_id (now).
  select jsonb_build_object(
           'definition', 'Transfers in seller_sent, buyer_confirmed or auto_released with no connected-account transfer yet; sum of payments.amount - seller_fee',
           'basis', 'now', 'currency', 'USD',
           'now', jsonb_build_object('count', count(*), 'cents', coalesce(sum(p.amount - coalesce(p.seller_fee, 0)), 0)),
           'by_status', coalesce((select jsonb_object_agg(s.status, s.n) from (
                          select t2.status, count(*) as n from public.transfers t2
                           where t2.status in ('seller_sent', 'buyer_confirmed', 'auto_released') and t2.stripe_transfer_id is null
                           group by t2.status) s), '{}'::jsonb))
    into v_val
    from public.transfers t join public.payments p on p.id = t.payment_id
   where t.status in ('seller_sent', 'buyer_confirmed', 'auto_released') and t.stripe_transfer_id is null;
  v_rows := v_rows || jsonb_build_object('money.seller_funds_pending', v_val);

  v_rows := v_rows || jsonb_build_object('money.bank_payouts', jsonb_build_object(
              'definition', 'Bank payouts from connected accounts are not tracked (payout.paid webhook is only logged)',
              'tracked', false));

  -- Queue counts (point in time).
  v_rows := v_rows || jsonb_build_object('queue.cases_open', (
    select jsonb_build_object('total', count(*),
             'by_priority', coalesce(jsonb_object_agg(pr, n) filter (where pr is not null), '{}'::jsonb))
      from (select c.priority as pr, count(*) as n from ops."case" c
             where c.status not in ('resolved', 'dismissed') group by c.priority) q));
  v_rows := v_rows || jsonb_build_object('queue.cases_open_by_type', coalesce((
    select jsonb_object_agg(c.case_type, c.n) from (
      select case_type, count(*) as n from ops."case" where status not in ('resolved', 'dismissed') group by case_type) c), '{}'::jsonb));
  v_rows := v_rows || jsonb_build_object('queue.refunds_pending', (
    select count(*) from ops."case" where case_type = 'refund_pending' and status not in ('resolved', 'dismissed')));
  v_rows := v_rows || jsonb_build_object('queue.webhook_backlog', (
    select count(*) from public.stripe_webhook_events e
     where e.processed_at is null
       and (e.received_at < now() - make_interval(mins => ops.setting_int('webhook_stuck_minutes', 15)) or e.failed_at is not null)));
  v_rows := v_rows || jsonb_build_object('queue.notify_failed_7d', (
    select jsonb_build_object('failed', count(*) filter (where d.state = 'failed'), 'dead', count(*) filter (where d.state = 'dead'))
      from notify.delivery d where d.state in ('failed', 'dead') and d.created_at > now() - interval '7 days'));
  v_rows := v_rows || jsonb_build_object('queue.disputes_open', (
    select jsonb_build_object(
             'transfers', (select count(*) from public.transfers t where t.disputed_at is not null and t.dispute_resolved_at is null),
             'stripe',    (select count(*) from public.disputes d where d.status not in ('won', 'lost', 'warning_closed', 'charge_refunded')))));
  v_rows := v_rows || jsonb_build_object('queue.transfers_pending', (
    select jsonb_build_object('pending', count(*) filter (where t.status = 'pending'),
                              'seller_sent', count(*) filter (where t.status = 'seller_sent'),
                              'manual_review', count(*) filter (where t.payout_review_status = 'manual_review' and t.payout_released_at is null))
      from public.transfers t));
  v_rows := v_rows || jsonb_build_object('queue.alerts_firing', (select count(*) from ops.alert where state = 'firing'));

  for v_key, v_val in select * from jsonb_each(v_rows) loop
    insert into ops.metric_snapshot (key, value, computed_at) values (v_key, v_val, v_now)
    on conflict (key) do update set value = excluded.value, computed_at = excluded.computed_at;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('scanned', v_n, 'opened', 0, 'resolved', 0, 'keys', v_n, 'computed_at', v_now);
end;
$ops$;
revoke all on function ops.refresh_metrics() from public, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- PART 3 — founder evidence access
-- ----------------------------------------------------------------------------
-- Policy predicates run as the requesting role (authenticated) and would be
-- subject to transfers/listings RLS, which hides other people's rows from a
-- founder; the reference check is therefore a SECURITY DEFINER helper that
-- answers exactly one question: is this object path referenced by a record?
create or replace function ops.evidence_path_is_referenced(p_name text)
returns boolean language sql stable security definer set search_path = ''
as $ops$
  select p_name is not null and (
    exists (select 1 from public.transfers t
             where t.transfer_evidence_path = p_name
                or t.dispute_evidence_path = p_name
                or (to_jsonb(t) ->> 'transfer_screenshot_path') = p_name)
    or exists (select 1 from public.listings l where l.proof_of_ownership_path = p_name));
$ops$;
revoke all on function ops.evidence_path_is_referenced(text) from public, anon;
grant execute on function ops.evidence_path_is_referenced(text) to authenticated;

create or replace function ops.evidence_operator_may_read()
returns boolean language sql stable security definer set search_path = ''
as $ops$
  select kernel.is_platform(array['platform_admin','platform_support','platform_risk'])
     and ops.current_aal() = 'aal2';
$ops$;
revoke all on function ops.evidence_operator_may_read() from public, anon;
grant execute on function ops.evidence_operator_may_read() to authenticated;

drop policy if exists "proof-docs operator read" on storage.objects;
create policy "proof-docs operator read" on storage.objects
  for select to authenticated
  using (bucket_id = 'proof-docs'
         and ops.evidence_operator_may_read()
         and ops.evidence_path_is_referenced(name));

-- Resolve the eligible object for a review slot from the record itself, audit
-- the access, and hand back what the app may sign (short-lived).
create or replace function ops.evidence_access(p_subject_kind text, p_subject_id uuid, p_slot text)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_path   text;
  v_bucket text := 'proof-docs';
  t        public.transfers%rowtype;
begin
  perform ops.assert_reader();
  if p_subject_kind = 'transfer' then
    select * into t from public.transfers where id = p_subject_id;
    if not found then raise exception 'precondition_failed: transfer not found'; end if;
    v_path := case p_slot
      when 'transfer_evidence'   then t.transfer_evidence_path
      when 'dispute_evidence'    then t.dispute_evidence_path
      when 'transfer_screenshot' then to_jsonb(t) ->> 'transfer_screenshot_path'
      else null end;
    if p_slot not in ('transfer_evidence','dispute_evidence','transfer_screenshot') then
      raise exception 'invalid_input: unknown slot % for a transfer', p_slot;
    end if;
  elsif p_subject_kind = 'listing' then
    if p_slot <> 'proof_of_ownership' then
      raise exception 'invalid_input: unknown slot % for a listing', p_slot;
    end if;
    select l.proof_of_ownership_path into v_path from public.listings l where l.id = p_subject_id;
    if not found then raise exception 'precondition_failed: listing not found'; end if;
  else
    raise exception 'invalid_input: evidence lives on transfers and listings only';
  end if;
  if v_path is null or v_path = '' then
    raise exception 'precondition_failed: no_evidence — nothing is recorded in slot %', p_slot;
  end if;
  perform ops.audit_write('evidence.viewed', p_subject_kind, p_subject_id, null, null, null,
                          jsonb_build_object('slot', p_slot, 'bucket', v_bucket, 'path', v_path), 'ok', null, null);
  return jsonb_build_object('bucket', v_bucket, 'path', v_path, 'expires_in_seconds', 300,
                            'slot', p_slot, 'subject_kind', p_subject_kind, 'subject_id', p_subject_id);
end;
$ops$;
revoke all on function ops.evidence_access(text,uuid,text) from public, anon, authenticated;
grant execute on function ops.evidence_access(text,uuid,text) to authenticated;

commit;

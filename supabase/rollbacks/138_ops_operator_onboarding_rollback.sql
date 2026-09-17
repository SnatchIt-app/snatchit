-- =============================================================================
-- 138_ops_operator_onboarding_rollback.sql — reverse 138.
--
-- EACH OBJECT IS RESTORED FROM ITS OWN APPLIED BODY, not from one baseline for
-- all five. 115 defines all five; 118 redefines execute_action, action_dispatch
-- and action_precheck. Restoring 115's body for any of those three would
-- silently revert 118's corrections — the failure this file exists to avoid.
--
-- A ROLLBACK RESTORES CODE, NOT DATA. Organisations, members, invites, venues and
-- staff roles written by dispatched onboarding actions stay where the domain verbs
-- put them, and their ops.audit / kernel.admin_audit rows stay too.
--
--   ops.execute_action           <- 118's body  (verbatim)  [the front door]
--   ops.action_dispatch          <- 118's body  (verbatim)
--   ops.action_precheck          <- 118's body  (verbatim)
--   ops.action_allowed_roles     <- 115's body  (verbatim)
--   ops.action_requires_approval <- 115's body  (verbatim)
--   ops.action CHECK constraints <- 115's lists
--   the nine ops functions 138 added -> dropped
--
-- ops.audit_write is not touched here because 138 does not touch it.
-- Rows already written with a 138 action_type would violate the narrowed CHECK,
-- so the constraint restore is guarded: it refuses rather than silently leaving
-- the wide constraint in place, and names what to do.
-- =============================================================================
begin;

drop function if exists ops.get_org_contact_email(uuid, text);
drop function if exists ops.list_venue_staff(uuid);
drop function if exists ops.list_org_invites(uuid);
drop function if exists ops.list_org_members(uuid);
drop function if exists ops.list_venues(uuid, text, integer);
drop function if exists ops.get_organization(uuid);
drop function if exists ops.list_organizations(text, text, integer);
drop function if exists ops.identity_display_name(uuid);
drop function if exists ops.org_connect_readiness(kernel.organization);

-- Refuse rather than fail obscurely on the ALTER: a 138 action row already in
-- ops.action cannot satisfy 115's narrower list.
do $rb$
declare v_n integer;
begin
  select count(*) into v_n from ops.action
   where action_type in ('org_create','org_update','org_status_set','org_member_invite',
                         'org_member_invite_admin','org_member_role_change','org_member_elevate',
                         'org_member_remove','org_invite_revoke','platform_role_grant',
                         'venue_create','venue_approve','venue_staff_grant','venue_staff_revoke');
  if v_n > 0 then
    raise exception '138 rollback: % onboarding action row(s) exist; archive or delete them before narrowing the CHECK', v_n;
  end if;
end $rb$;

alter table ops.action drop constraint action_action_type_check;
alter table ops.action add constraint action_action_type_check check (action_type in (
  'case_create','case_assign','case_status','case_priority','case_due','case_note',
  'dispute_resolve','payout_release','listing_relist','report_resolve',
  'user_restrict','user_unrestrict','refund_execute','job_retry','setting_set'));
alter table ops.action drop constraint action_subject_kind_check;
alter table ops.action add constraint action_subject_kind_check check (subject_kind in (
  'case','payment','transfer','listing','user','report','job','setting','none'));

-- ── the five bodies, each from its own baseline ─────────────────────────────
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

create or replace function ops.action_allowed_roles(p_action_type text)
returns text[] language sql immutable
as $ops$
  select case p_action_type
    when 'payout_release'  then array['platform_admin']
    when 'refund_execute'  then array['platform_admin']
    when 'dispute_resolve' then array['platform_admin','platform_risk']
    when 'listing_relist'  then array['platform_admin']
    when 'setting_set'     then array['platform_admin']
    when 'job_retry'       then array['platform_admin']
    when 'user_restrict'   then array['platform_admin','platform_risk','platform_support']
    when 'user_unrestrict' then array['platform_admin','platform_risk']
    else array['platform_admin','platform_risk','platform_support']   -- case_*, report_resolve
  end;
$ops$;
revoke all on function ops.action_allowed_roles(text) from public, anon, authenticated;

create or replace function ops.action_requires_approval(p_action_type text)
returns boolean language sql immutable
as $ops$
  select p_action_type in ('payout_release','refund_execute');
$ops$;
revoke all on function ops.action_requires_approval(text) from public, anon, authenticated;

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

commit;

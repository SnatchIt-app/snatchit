-- =============================================================================
-- 138_ops_operator_onboarding.sql — the operator-onboarding surface: the console
-- can SEE organisations, venues, members and staff, and can ACT on them only
-- through the existing audited, role-gated, approval-capable action framework.
--
-- WHY. Every onboarding verb already exists (077 kernel, 078 catalog, 080 venue)
-- and half of them are unreachable from a browser: catalog and venue are NOT
-- PostgREST-exposed and stay that way. `ops` meanwhile holds NO organisation,
-- venue, staff or event read at all, so the console cannot list an organisation
-- and therefore cannot offer one to act on. The write side was finished; the read
-- side did not exist. Bespoke screens calling the verbs directly would bypass the
-- console's own two-person approval, role gating and audit trail — the machinery
-- every other privileged console action already goes through. Contract:
-- docs/venue-dashboard/OPERATOR_ONBOARDING_CONTRACT_D_20260917.md.
--
-- NO NEW DOORS. ops.action_dispatch is SECURITY DEFINER owned by postgres, so it
-- reaches catalog and venue as the definer; the browser never does. Schema
-- exposure is a PostgREST setting, not a privilege, and that asymmetry is what
-- lets the framework be the only door. 138 adds no schema exposure.
--
-- OWNER RULINGS (2026-09-17, relayed by A).
--   * Visible: organisation id, legal and display name, status, venue details,
--     member display name and ACCOUNT IDENTIFIER = the identity UUID (not email),
--     roles, invitation status, Connect READINESS STATUS. Contact email is
--     restricted to workflows that need it. Excluded: gender, bank/tax details,
--     secrets, unrelated account data.
--   * Two-person approval: venue approval, platform-role grants, and any change
--     elevating someone to organisation ownership/admin authority.
--   * Preserve stronger existing controls; use the audited action framework and
--     narrow wrappers; do not expose catalog or venue.
--
-- THE ELEVATION RULE IS PARAMS-DEPENDENT AND THE FRAMEWORK'S PREDICATE IS NOT.
-- ops.action_requires_approval(text) sees only the action type, so "elevating to
-- owner/admin" cannot be expressed as a property of one type. Ruling (A, ①(a)):
-- SPLIT the types — org_member_role_change / org_member_elevate and
-- org_member_invite / org_member_invite_admin — and refuse a type/role MISMATCH
-- IN BOTH DIRECTIONS in ops.action_precheck. Without the second direction the
-- caller would choose whether approval applies, which is not a control.
-- Widening action_requires_approval to the action row was rejected deliberately:
-- it is a change to the approval model every other action depends on, and would
-- be its own migration with its own review.
--
-- ATTRIBUTION IS SPLIT, DELIBERATELY (owner ruling ③). The onboarding verbs take
-- no actor: each resolves auth.uid() itself. Called from the framework that is the
-- EXECUTING session, which for an approval-gated action is the APPROVER. So the
-- domain's own audit records the approver while ops.action records requester and
-- approver separately. Two trails, one event. ops.action is the authoritative
-- record of who decided, and the console shows both. Giving the verbs an actor
-- parameter is a later migration on kernel/catalog/venue, not this one.
--
-- CONTACT EMAIL IS A SEPARATE AUDITED VERB, NOT A COLUMN. A field an operator is
-- asked to read "only when needed" but which arrives in every list is not
-- restricted, only labelled. ops.get_org_contact_email writes an ops.audit row
-- with a closed reason code on every call.
--
-- TWO BASELINES IN ONE MIGRATION — the part most likely to go wrong.
--   ops.action_dispatch, ops.action_precheck        redefined from 118's APPLIED body
--   ops.action_allowed_roles, action_requires_approval  redefined from 115's body
-- 115 defines all four; 118 redefines only the first two. Restoring 115's body for
-- dispatch or precheck would silently revert 118's corrections. The rollback
-- restores EACH object from its own applied body, not one baseline for all four.
-- ops.audit_write is NOT touched: it takes p_action text and ops.audit.subject_kind
-- has no CHECK, so new action names and subject kinds flow through as data.
-- Verified by searching the whole chain: no other migration defines any of them,
-- and all twelve onboarding verbs are single-defined (077 / 078 / 080).
--
-- THE TWO CHECK CONSTRAINTS ARE 115'S INLINE, AUTO-NAMED ONES. Nothing alters them
-- afterwards (118 adds columns only). They are dropped BY NAME and WITHOUT
-- `if exists`: a drop that matches nothing does not fail — it would leave the old
-- constraint standing, 138 would apply "successfully", and the first onboarding
-- action of a new type would be rejected at insert, in the window, in front of the
-- owner. A bare drop fails at migration time, which is the right moment to learn
-- the name differs. The widening is proved in this file's own do-block.
--
-- Census: ops routines +8 (6 reads + the contact-email verb + the invite mask is
-- reused, not new — ops.mask_email already exists in 115 and the console already
-- shows email_masked on every user card). public census UNCHANGED: nothing here is
-- public, so the grant-decision manifest and expected_grants.txt are untouched.
-- pgTAP 206. Applied nowhere by this file.
-- =============================================================================
begin;

-- ── 1. widen the two CHECK constraints (see the header on `if exists`) ───────
alter table ops.action drop constraint action_action_type_check;
alter table ops.action add constraint action_action_type_check check (action_type in (
  'case_create','case_assign','case_status','case_priority','case_due','case_note',
  'dispute_resolve','payout_release','listing_relist','report_resolve',
  'user_restrict','user_unrestrict','refund_execute','job_retry','setting_set',
  -- 138 operator onboarding
  'org_create','org_update','org_status_set',
  'org_member_invite','org_member_invite_admin',
  'org_member_role_change','org_member_elevate',
  'org_member_remove','org_invite_revoke','platform_role_grant',
  'venue_create','venue_approve','venue_staff_grant','venue_staff_revoke'));

alter table ops.action drop constraint action_subject_kind_check;
alter table ops.action add constraint action_subject_kind_check check (subject_kind in (
  'case','payment','transfer','listing','user','report','job','setting','none',
  -- 138 operator onboarding
  'organization','venue','org_invite'));

-- ── 2. role gating and the approval set (redefined from 115's bodies) ────────
-- 115 defines these; 118 does NOT redefine them. The rollback restores 115's.
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
    -- 138 operator onboarding. Everything that creates or changes an organisation,
    -- a venue or a platform role is platform_admin. Support may invite a member at
    -- a non-elevating role, revoke a pending invite, and grant or revoke venue
    -- staff — the day-to-day of standing a venue up — and nothing else.
    when 'org_create'              then array['platform_admin']
    when 'org_update'              then array['platform_admin']
    when 'org_status_set'          then array['platform_admin']
    when 'org_member_invite'       then array['platform_admin','platform_support']
    when 'org_member_invite_admin' then array['platform_admin']
    when 'org_member_role_change'  then array['platform_admin']
    when 'org_member_elevate'      then array['platform_admin']
    when 'org_member_remove'       then array['platform_admin']
    when 'org_invite_revoke'       then array['platform_admin','platform_support']
    when 'platform_role_grant'     then array['platform_admin']
    when 'venue_create'            then array['platform_admin']
    when 'venue_approve'           then array['platform_admin']
    when 'venue_staff_grant'       then array['platform_admin','platform_support']
    when 'venue_staff_revoke'      then array['platform_admin','platform_support']
    else array['platform_admin','platform_risk','platform_support']   -- case_*, report_resolve
  end;
$ops$;
revoke all on function ops.action_allowed_roles(text) from public, anon, authenticated;

create or replace function ops.action_requires_approval(p_action_type text)
returns boolean language sql immutable
as $ops$
  -- 138 adds the owner's three (2026-09-17): venue approval, platform-role grants,
  -- and elevation to organisation ownership/admin authority. Elevation is a
  -- property of the target ROLE, not of the action, and this predicate sees only
  -- the type — hence the split types, whose type/role agreement ops.action_precheck
  -- enforces in both directions.
  select p_action_type in ('payout_release','refund_execute',
                           'venue_approve','platform_role_grant',
                           'org_member_elevate','org_member_invite_admin');
$ops$;
revoke all on function ops.action_requires_approval(text) from public, anon, authenticated;

-- ── 3. precheck: the guard that makes the split a control (from 118) ────────
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

  -- ── 138: the guard that makes the routine/elevating split a CONTROL ──────
  -- Without the second direction the split is cosmetic: the CALLER would choose
  -- whether two-person approval applies by choosing a type. Both directions are
  -- refused here, before anything is dispatched or approved.
  when 'org_member_role_change' then
    if (p_action.params ->> 'new_role') in ('org_owner','org_admin') then
      return jsonb_build_object('status','rejected','reject_reason','precondition',
               'message','elevating a member to org_owner or org_admin requires two-person approval: request org_member_elevate');
    end if;
  when 'org_member_elevate' then
    if (p_action.params ->> 'new_role') is distinct from 'org_owner'
       and (p_action.params ->> 'new_role') is distinct from 'org_admin' then
      return jsonb_build_object('status','rejected','reject_reason','precondition',
               'message','org_member_elevate is only for org_owner or org_admin: request org_member_role_change');
    end if;
  when 'org_member_invite' then
    if (p_action.params ->> 'role') in ('org_owner','org_admin') then
      return jsonb_build_object('status','rejected','reject_reason','precondition',
               'message','inviting someone as org_owner or org_admin requires two-person approval: request org_member_invite_admin');
    end if;
  when 'org_member_invite_admin' then
    if (p_action.params ->> 'role') is distinct from 'org_owner'
       and (p_action.params ->> 'role') is distinct from 'org_admin' then
      return jsonb_build_object('status','rejected','reject_reason','precondition',
               'message','org_member_invite_admin is only for org_owner or org_admin: request org_member_invite');
    end if;

  else
    null;
  end case;
  return null;
end;
$ops$;

-- ── 4. dispatch: the onboarding arms (from 118) ──────────────────────────────
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


  -- ── operator onboarding (138) ───────────────────────────────────────────
  -- Every verb below lives in kernel / catalog / venue. catalog and venue are
  -- NOT PostgREST-exposed and stay that way: this definer function reaches them,
  -- the browser never does. Schema exposure is a PostgREST setting, not a
  -- privilege, and that asymmetry is what makes the framework the only door.
  --
  -- Each verb resolves auth.uid() itself and applies its own kernel.is_platform /
  -- kernel.has_org_role check, which still runs here (138 ADDS approval, it never
  -- replaces a domain control). For an approval-gated action the executing
  -- session is the APPROVER, so the domain's own audit records the approver while
  -- ops.action records requester and approver separately — two trails, one event.
  -- ops.action is the authoritative record of who decided (owner ruling 2026-09-17).
  --
  -- p_command_key is a.idempotency_key: the framework's own declared identity for
  -- this command, already shaped by ops.action's CHECK, so a retried dispatch of
  -- the same action row reaches the domain with the same key.

  when 'org_create' then
    if coalesce(trim(a.params ->> 'legal_name'), '') = '' or coalesce(trim(a.params ->> 'display_name'), '') = '' then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','legal_name and display_name are required');
    end if;
    v_res := kernel.create_organization(a.params ->> 'legal_name', a.params ->> 'display_name', a.idempotency_key);
    return jsonb_build_object('status','succeeded','result', v_res);

  when 'org_update' then
    if a.subject_id is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','subject_id (org) required');
    end if;
    if a.params -> 'patch' is null or jsonb_typeof(a.params -> 'patch') <> 'object' then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','params.patch must be an object');
    end if;
    v_res := kernel.update_organization(a.subject_id, a.params -> 'patch', a.idempotency_key);
    return jsonb_build_object('status','succeeded','result', v_res);

  when 'org_status_set' then
    if a.subject_id is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','subject_id (org) required');
    end if;
    if (a.params ->> 'target_status') not in ('applied','approved','active','suspended','closed') then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','target_status must be applied|approved|active|suspended|closed');
    end if;
    v_res := kernel.set_org_status(a.subject_id, a.params ->> 'target_status', a.params ->> 'reason_code', a.idempotency_key);
    return jsonb_build_object('status','succeeded','result', v_res);

  -- invite: the routine type and the elevating type call the SAME verb. The split
  -- exists so ops.action_requires_approval (which sees only the type) can gate the
  -- elevating one; ops.action_precheck refuses a type/role mismatch in BOTH
  -- directions, so the caller never chooses whether approval applies.
  when 'org_member_invite', 'org_member_invite_admin' then
    if a.subject_id is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','subject_id (org) required');
    end if;
    if coalesce(trim(a.params ->> 'invitee_ref'), '') = '' then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','invitee_ref required');
    end if;
    if (a.params ->> 'role') not in ('org_owner','org_admin','org_finance','org_marketing','org_promoter_manager','org_member') then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','role is not an organisation role');
    end if;
    v_res := kernel.invite_org_member(a.subject_id, a.params ->> 'invitee_ref', a.params ->> 'role', a.idempotency_key);
    return jsonb_build_object('status','succeeded','result', v_res);

  when 'org_member_role_change', 'org_member_elevate' then
    if a.subject_id is null or (a.params ->> 'identity_id') is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','subject_id (org) and params.identity_id required');
    end if;
    if (a.params ->> 'new_role') not in ('org_owner','org_admin','org_finance','org_marketing','org_promoter_manager','org_member') then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','new_role is not an organisation role');
    end if;
    v_res := kernel.change_org_role(a.subject_id, (a.params ->> 'identity_id')::uuid, a.params ->> 'new_role', a.idempotency_key);
    return jsonb_build_object('status','succeeded','result', v_res);

  when 'org_member_remove' then
    if a.subject_id is null or (a.params ->> 'identity_id') is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','subject_id (org) and params.identity_id required');
    end if;
    v_res := kernel.remove_org_member(a.subject_id, (a.params ->> 'identity_id')::uuid, a.idempotency_key);
    return jsonb_build_object('status','succeeded','result', v_res);

  when 'org_invite_revoke' then
    if a.subject_id is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','subject_id (invite) required');
    end if;
    v_res := kernel.revoke_org_invite(a.subject_id, a.idempotency_key);
    return jsonb_build_object('status','succeeded','result', v_res);

  when 'platform_role_grant' then
    if (a.params ->> 'identity_id') is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','params.identity_id required');
    end if;
    if (a.params ->> 'role') not in ('platform_admin','platform_support','platform_risk') then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','role must be platform_admin|platform_support|platform_risk');
    end if;
    v_res := kernel.grant_platform_role((a.params ->> 'identity_id')::uuid, a.params ->> 'role', a.params ->> 'reason_code', a.idempotency_key);
    return jsonb_build_object('status','succeeded','result', v_res);

  when 'venue_create' then
    if a.subject_id is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','subject_id (org) required');
    end if;
    if coalesce(trim(a.params ->> 'name'), '') = '' or coalesce(trim(a.params ->> 'neighborhood'), '') = '' then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','name and neighborhood are required');
    end if;
    v_res := catalog.create_venue(a.subject_id, a.params ->> 'name', a.params ->> 'neighborhood', a.params ->> 'address', a.idempotency_key);
    return jsonb_build_object('status','succeeded','result', v_res);

  when 'venue_approve' then
    if a.subject_id is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','subject_id (venue) required');
    end if;
    if (a.params ->> 'decision') not in ('approved','archived','pending') then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','decision must be approved|archived|pending');
    end if;
    v_res := catalog.approve_venue(a.subject_id, a.params ->> 'decision', a.params ->> 'reason_code', a.idempotency_key);
    return jsonb_build_object('status','succeeded','result', v_res);

  when 'venue_staff_grant', 'venue_staff_revoke' then
    if a.subject_id is null or (a.params ->> 'identity_id') is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','subject_id (venue) and params.identity_id required');
    end if;
    if (a.params ->> 'role') not in ('venue_manager','venue_finance','venue_box_office','venue_marketing','venue_promoter_manager','venue_scanner') then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','role is not a venue staff role');
    end if;
    if a.action_type = 'venue_staff_grant' then
      v_res := venue.grant_staff_role(a.subject_id, (a.params ->> 'identity_id')::uuid, a.params ->> 'role', a.idempotency_key);
    else
      v_res := venue.revoke_staff_role(a.subject_id, (a.params ->> 'identity_id')::uuid, a.params ->> 'role', a.idempotency_key);
    end if;
    return jsonb_build_object('status','succeeded','result', v_res);

  else
    return jsonb_build_object('status','rejected','reject_reason','not_supported','message','unknown action type');
  end case;
end;
$ops$;
-- ── 5. the read surface ──────────────────────────────────────────────────────
-- `ops` IS PostgREST-exposed, so every function here is reachable by anyone with
-- a session. The boundary is ops.assert_reader(): an operator role AND an aal2
-- (MFA) session, the same guard every 116 read uses. Grants follow that pattern —
-- execute to `authenticated`, authorization inside the function, never a grant on
-- a kernel/catalog/venue table.
--
-- FIELDS ARE THE OWNER'S ALLOWLIST (2026-09-17). identity_id IS the account
-- identifier. No email in any list; no bank, tax, gender or Connect account
-- reference anywhere. Connect is flattened to a readiness WORD: returning the
-- account ref would put a payment-provider identifier into a list view for no
-- operator benefit.
--
-- Never cached across requests or users: these are authorization-scoped reads.

create or replace function ops.org_connect_readiness(p_org kernel.organization)
returns text language sql stable
as $ops$
  -- A word, never the ref. 'ready' means a destination is set and not locked out.
  select case
    when p_org.stripe_connect_account_ref is null then 'not_started'
    when p_org.payout_destination_locked_until is not null
     and p_org.payout_destination_locked_until > now() then 'restricted'
    when p_org.payout_destination_set_by is null then 'pending'
    else 'ready' end;
$ops$;
revoke all on function ops.org_connect_readiness(kernel.organization) from public, anon, authenticated;

-- A display name or nothing. NOT ops.actor_label: that falls back to
-- ops.mask_email(auth.users.email), so an accepted member with no profile
-- display name would surface a masked address on a list where the owner ruled
-- the identifier is the identity UUID (2026-09-17). The mask is approved for
-- PENDING invites only, where there is no identity yet.
create or replace function ops.identity_display_name(p_user uuid)
returns text language sql stable security definer set search_path = ''
as $ops$
  select coalesce(
    (select a.label from public.admin_users a where a.user_id = p_user),
    (select nullif(p.display_name, '') from public.profiles p where p.id = p_user));
$ops$;
revoke all on function ops.identity_display_name(uuid) from public, anon, authenticated;

create or replace function ops.list_organizations(p_status text default null, p_q text default null, p_limit integer default 50)
returns table (org_id uuid, legal_name text, display_name text, status text,
               venue_count integer, member_count integer, created_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $ops$
begin
  perform ops.assert_reader();
  if p_status is not null and p_status not in ('applied','approved','active','suspended','closed') then
    raise exception 'invalid_input: status must be applied|approved|active|suspended|closed';
  end if;
  return query
    select o.org_id, o.legal_name, o.display_name, o.status,
           (select count(*)::integer from catalog.venue v where v.org_id = o.org_id),
           (select count(*)::integer from kernel.org_member m where m.org_id = o.org_id),
           o.created_at
      from kernel.organization o
     where (p_status is null or o.status = p_status)
       and (nullif(trim(coalesce(p_q, '')), '') is null
            or o.display_name ilike '%' || trim(p_q) || '%'
            or o.legal_name   ilike '%' || trim(p_q) || '%')
     order by o.created_at desc, o.org_id desc
     limit ops.clamp_limit(p_limit);
end $ops$;

create or replace function ops.get_organization(p_org_id uuid)
returns table (org_id uuid, legal_name text, display_name text, status text,
               connect_readiness text, venue_count integer, member_count integer,
               pending_invite_count integer, created_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $ops$
begin
  perform ops.assert_reader();
  return query
    select o.org_id, o.legal_name, o.display_name, o.status,
           ops.org_connect_readiness(o),
           (select count(*)::integer from catalog.venue v where v.org_id = o.org_id),
           (select count(*)::integer from kernel.org_member m where m.org_id = o.org_id),
           (select count(*)::integer from kernel.org_invite i where i.org_id = o.org_id and i.status = 'pending'),
           o.created_at
      from kernel.organization o
     where o.org_id = p_org_id;
end $ops$;

create or replace function ops.list_venues(p_org_id uuid default null, p_status text default null, p_limit integer default 50)
returns table (venue_id uuid, org_id uuid, org_display_name text, name text,
               neighborhood text, address text, approval_status text, created_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $ops$
begin
  perform ops.assert_reader();
  if p_status is not null and p_status not in ('draft','pending','approved','archived') then
    raise exception 'invalid_input: status must be draft|pending|approved|archived';
  end if;
  -- p_status => 'pending' IS the approval queue; it needs no separate verb.
  return query
    select v.venue_id, v.org_id, o.display_name, v.name, v.neighborhood, v.address,
           v.approval_status, v.created_at
      from catalog.venue v
      join kernel.organization o on o.org_id = v.org_id
     where (p_org_id is null or v.org_id = p_org_id)
       and (p_status is null or v.approval_status = p_status)
     order by v.created_at desc, v.venue_id desc
     limit ops.clamp_limit(p_limit);
end $ops$;

create or replace function ops.list_org_members(p_org_id uuid)
returns table (identity_id uuid, display_name text, role text, granted_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $ops$
begin
  perform ops.assert_reader();
  -- identity_id IS the account identifier (owner ruling). No email here at all.
  return query
    select m.identity_id, ops.identity_display_name(m.identity_id), m.role, m.granted_at
      from kernel.org_member m
     where m.org_id = p_org_id
     order by m.role, m.granted_at;
end $ops$;

create or replace function ops.list_org_invites(p_org_id uuid)
returns table (invite_id uuid, invitee_identity_id uuid, invitee_label text,
               role text, status text, invited_by_label text,
               expires_at timestamptz, created_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $ops$
begin
  perform ops.assert_reader();
  -- A PENDING invite has no identity_id yet (invitee_identity_id is null until it
  -- is accepted) and kernel.org_invite.invitee_ref IS the address — you invite by
  -- email. So the owner's two rules (identity UUID as the identifier; email behind
  -- the audited verb) leave a pending invite with no handle at all.
  --
  -- invitee_label is the ONE expression that resolves this, and it is deliberately
  -- the only place the question is answered: ops.mask_email gives 'j***@domain',
  -- the same masking ops.user_summary already applies to every user card in this
  -- console. If the owner rules against showing even a mask, replace this single
  -- expression with NULL and nothing else in this migration changes.
  -- Full address: ops.get_org_contact_email, audited and reason-coded.
  return query
    select i.invite_id, i.invitee_identity_id,
           -- accepted: the display name (identity UUID is the identifier, returned beside it).
           -- pending: the approved mask, ALWAYS with invite_id above so two identical
           -- masks stay distinguishable (owner, 2026-09-17). No filter parameter takes
           -- the mask: it is displayable, never searchable.
           -- Conditioned on invitee_identity_id, NOT on the display name being null (A, review
           -- of 523333b). With a coalesce, an ACCEPTED invite whose identity has no profile
           -- display name falls through to the masked address — the same leak removed from
           -- list_org_members, reappearing here. Accepted rows show a name or nothing, never
           -- an address; the mask is for pending invites, which have no identity yet.
           case when i.invitee_identity_id is null then ops.mask_email(i.invitee_ref)
                else ops.identity_display_name(i.invitee_identity_id) end,
           i.role, i.status, ops.identity_display_name(i.invited_by), i.expires_at, i.created_at
      from kernel.org_invite i
     where i.org_id = p_org_id
     order by (i.status = 'pending') desc, i.created_at desc;
end $ops$;

create or replace function ops.list_venue_staff(p_venue_id uuid)
returns table (identity_id uuid, display_name text, role text, created_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $ops$
begin
  perform ops.assert_reader();
  return query
    select s.identity_id, ops.identity_display_name(s.identity_id), s.role, s.created_at
      from venue.staff_role s
     where s.venue_id = p_venue_id
     order by s.role, s.created_at;
end $ops$;

-- ── 6. contact email: a separate, audited, purpose-limited verb ─────────────
create or replace function ops.get_org_contact_email(p_org_id uuid, p_reason_code text)
returns text language plpgsql volatile security definer set search_path = ''
as $ops$
declare v_email text;
begin
  perform ops.assert_role(array['platform_admin','platform_support']);
  if p_reason_code not in ('onboarding_contact','payout_problem','legal_request','support_escalation') then
    raise exception 'invalid_input: reason_code must be onboarding_contact|payout_problem|legal_request|support_escalation';
  end if;
  -- The owner's contact is the org_owner's address. Read it, then RECORD the read:
  -- the restriction is this verb and its audit row, not a convention about columns.
  select u.email into v_email
    from kernel.org_member m
    join auth.users u on u.id = m.identity_id
   where m.org_id = p_org_id and m.role = 'org_owner'
   order by m.granted_at
   limit 1;
  perform ops.audit_write('org_contact_email_read', 'organization', p_org_id, null,
                          p_reason_code, null,
                          jsonb_build_object('found', v_email is not null), 'ok', null, null);
  return v_email;
end $ops$;

-- ── 7. grants: execute to authenticated, authorization inside (116 pattern) ──
revoke all on function ops.list_organizations(text, text, integer)      from public, anon, authenticated;
revoke all on function ops.get_organization(uuid)                        from public, anon, authenticated;
revoke all on function ops.list_venues(uuid, text, integer)              from public, anon, authenticated;
revoke all on function ops.list_org_members(uuid)                        from public, anon, authenticated;
revoke all on function ops.list_org_invites(uuid)                        from public, anon, authenticated;
revoke all on function ops.list_venue_staff(uuid)                        from public, anon, authenticated;
revoke all on function ops.get_org_contact_email(uuid, text)             from public, anon, authenticated;
grant execute on function ops.list_organizations(text, text, integer)    to authenticated;
grant execute on function ops.get_organization(uuid)                     to authenticated;
grant execute on function ops.list_venues(uuid, text, integer)           to authenticated;
grant execute on function ops.list_org_members(uuid)                     to authenticated;
grant execute on function ops.list_org_invites(uuid)                     to authenticated;
grant execute on function ops.list_venue_staff(uuid)                     to authenticated;
grant execute on function ops.get_org_contact_email(uuid, text)          to authenticated;

-- ── 8. sanity inside the migration ───────────────────────────────────────────
-- The constraint widening is proved HERE rather than left to pgTAP: a drop that
-- matched nothing, or a re-add that lost the old values, both apply cleanly and
-- only surface at the first insert. Asserted against pg_get_constraintdef rather
-- than by inserting a row: an insert needs a real auth.users row for requested_by,
-- and a failure for the wrong reason proves nothing. The insert-based proof is
-- pgTAP 206 C1/C2, where the fixtures exist.
do $chk$
declare
  v_type text := (select pg_get_constraintdef(c.oid) from pg_constraint c
                   where c.conname = 'action_action_type_check' and c.conrelid = 'ops.action'::regclass);
  v_kind text := (select pg_get_constraintdef(c.oid) from pg_constraint c
                   where c.conname = 'action_subject_kind_check' and c.conrelid = 'ops.action'::regclass);
  v_new  text;
  v_bad  text;
begin
  if v_type is null or v_kind is null then
    raise exception '138: a CHECK constraint is missing after the widening (type=%, kind=%)', v_type is not null, v_kind is not null;
  end if;
  -- every new value admitted...
  foreach v_new in array array['org_create','org_update','org_status_set','org_member_invite',
                               'org_member_invite_admin','org_member_role_change','org_member_elevate',
                               'org_member_remove','org_invite_revoke','platform_role_grant',
                               'venue_create','venue_approve','venue_staff_grant','venue_staff_revoke'] loop
    if position(v_new in v_type) = 0 then
      raise exception '138: action_type CHECK does not admit %', v_new;
    end if;
  end loop;
  foreach v_new in array array['organization','venue','org_invite'] loop
    if position(v_new in v_kind) = 0 then
      raise exception '138: subject_kind CHECK does not admit %', v_new;
    end if;
  end loop;
  -- ...and every old value still admitted (a re-add that lost the existing list
  -- applies cleanly and breaks every action the console already performs)
  foreach v_bad in array array['payout_release','refund_execute','dispute_resolve','case_create',
                               'listing_relist','report_resolve','user_restrict','user_unrestrict',
                               'job_retry','setting_set'] loop
    if position(v_bad in v_type) = 0 then
      raise exception '138: action_type CHECK lost the existing value %', v_bad;
    end if;
  end loop;
  foreach v_bad in array array['case','payment','transfer','listing','user','report','job','setting','none'] loop
    if position('''' || v_bad || '''' in v_kind) = 0 then
      raise exception '138: subject_kind CHECK lost the existing value %', v_bad;
    end if;
  end loop;

  -- the approval set is exactly the owner's three plus the two money actions
  if not (ops.action_requires_approval('venue_approve')
          and ops.action_requires_approval('platform_role_grant')
          and ops.action_requires_approval('org_member_elevate')
          and ops.action_requires_approval('org_member_invite_admin')
          and ops.action_requires_approval('payout_release')
          and ops.action_requires_approval('refund_execute')) then
    raise exception '138: an action that must be approved is not in the approval set';
  end if;
  if ops.action_requires_approval('org_member_role_change')
     or ops.action_requires_approval('org_member_invite')
     or ops.action_requires_approval('venue_create')
     or ops.action_requires_approval('org_create') then
    raise exception '138: a routine action was placed behind two-person approval';
  end if;

  -- the reads exist, are definer, pin search_path, and are authenticated-only
  declare v_bad_fn text;
  begin
    select string_agg(p.oid::regprocedure::text, ', ') into v_bad_fn
      from pg_proc p
     where p.oid in ('ops.list_organizations(text,text,integer)'::regprocedure,
                     'ops.get_organization(uuid)'::regprocedure,
                     'ops.list_venues(uuid,text,integer)'::regprocedure,
                     'ops.list_org_members(uuid)'::regprocedure,
                     'ops.list_org_invites(uuid)'::regprocedure,
                     'ops.list_venue_staff(uuid)'::regprocedure,
                     'ops.get_org_contact_email(uuid,text)'::regprocedure)
       and not (p.prosecdef
                and coalesce(p.proconfig @> array['search_path=""'], false)
                and has_function_privilege('authenticated', p.oid, 'EXECUTE')
                and not has_function_privilege('anon', p.oid, 'EXECUTE'));
    if v_bad_fn is not null then
      raise exception '138: read surface is not definer / search_path-pinned / authenticated-only: %', v_bad_fn;
    end if;
  end;
end $chk$;

commit;

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
-- IN BOTH DIRECTIONS in ops.execute_action, the path every action takes (F-138-5;
-- ops.action_precheck keeps a copy as a second layer, but it runs only for gated
-- types). The guard reads exactly the params key its dispatch arm reads and refuses
-- the other key (F-138-6). Without the second direction the caller would choose
-- whether approval applies, which is not a control. The beneficiary of an elevating
-- action may not be its requester (F-138-8): the kernel's self-promotion checks see
-- the APPROVER as the caller when the action finally runs.
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
-- AN INVITEE'S ADDRESS IS NEVER STORED WHERE AN OPERATOR CAN READ IT (owner item 1,
-- 2026-09-17). ops.action.params and ops.audit are returned whole by action_detail,
-- list_actions, list_approvals and audit_log. Invite actions store a label (masked
-- address, or the identity UUID the owner ruled displayable); the raw reference is
-- held in ops.action_invitee (no API role can read it; UPDATE refused) until dispatch
-- hands it to kernel.invite_org_member and deletes it; a verb message quoting it is
-- recorded with the label instead. kernel.org_invite keeps the delivery copy.
-- ops.get_action_invitee is the audited way to see it, shaped like the contact verb.
--
-- A CONSOLE-CREATED VENUE REACHES THE QUEUE BY venue_submit (owner item 3). create_venue
-- writes draft; the frozen verb's own 'pending' decision (RPC §3.2) is the submission,
-- taken by one platform_admin. venue_approve decides approved|archived only, and only
-- for a pending venue — checked when requested and again when the approval runs.
--
-- TWO BASELINES, FIVE OBJECTS — the part most likely to go wrong.
--   ops.execute_action, ops.action_dispatch, ops.action_precheck   redefined from 118's APPLIED body
--   ops.action_allowed_roles, ops.action_requires_approval          redefined from 115's body
-- 115 defines all five; 118 redefines the first three. Restoring 115's body for any
-- of those three would silently revert 118's corrections. The rollback restores
-- EACH object from its own applied body, not one baseline for all five.
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
-- Census (measured on a replay, not asserted): ops functions +10 — six reads
-- (list_organizations, get_organization, list_venues, list_org_members, list_org_invites,
-- list_venue_staff), two audited verbs (get_org_contact_email, get_action_invitee) and two
-- internal helpers (org_connect_readiness, identity_display_name); ops tables +1
-- (action_invitee) with its one trigger. ops.mask_email is reused from 115. public census
-- UNCHANGED (Gate-2 32|107|37|38 on the 138 branch = e9b52ce's EXPECT): nothing here is
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
  'venue_create','venue_submit','venue_approve','venue_staff_grant','venue_staff_revoke'));

alter table ops.action drop constraint action_subject_kind_check;
alter table ops.action add constraint action_subject_kind_check check (subject_kind in (
  'case','payment','transfer','listing','user','report','job','setting','none',
  -- 138 operator onboarding
  'organization','venue','org_invite'));

-- ── 1b. where a raw invitee reference is held (owner item 1, F-138-3) ────────
-- ops.action.params is returned whole by ops.action_detail, ops.list_actions and ops.list_approvals,
-- and ops.audit by ops.audit_log, to every operator at aal2. An invite's address therefore never goes
-- there. It is held here from the request until dispatch passes it to kernel.invite_org_member, then
-- deleted; kernel.org_invite keeps the copy delivery and acceptance use. No API role can read this table,
-- no function returns it except ops.get_action_invitee (audited), and a held reference cannot be changed.
create table if not exists ops.action_invitee (
  action_id   uuid primary key references ops.action(id) on delete cascade,
  invitee_ref text not null check (length(invitee_ref) between 1 and 320),
  created_at  timestamptz not null default now()
);
alter table ops.action_invitee enable row level security;
revoke all on table ops.action_invitee from public, anon, authenticated, service_role;
drop trigger if exists action_invitee_no_update on ops.action_invitee;
create trigger action_invitee_no_update before update on ops.action_invitee
  for each row execute function ops.raise_append_only();

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
    when 'venue_submit'            then array['platform_admin']
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

-- ── 2b. the FRONT DOOR (from 118's applied body) ─────────────────────────────
-- ops.execute_action is the only way into the framework and it validates against
-- hardcoded lists. A type absent from them is unreachable however complete its dispatch
-- arm is — 138's first cut widened the CHECK constraints and added the arms and left this
-- untouched, so all fourteen types answered 'invalid_input: unknown action_type' and the
-- migration did nothing. Found by A (F-138-2) by asking what the tests actually execute.
-- Five edits: the known-type list, the known subject kinds, the action<->subject pairing,
-- the subject_id exemptions, and the reason requirement.
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
  v_role_key    text;   -- 138: the params key this member/invite type's dispatch arm reads
  v_target_role text;
  v_params      jsonb;  -- 138: what is STORED; for invites the raw address is replaced by a label
  v_invitee     text;   -- 138: the raw invitee reference, held only in ops.action_invitee
  v_self_email  text;
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
      'user_restrict','user_unrestrict','refund_execute','job_retry','setting_set',
      -- 138 operator onboarding. execute_action is the ONLY door into the framework and it
      -- validates against these lists, so a type absent here is unreachable however complete
      -- its dispatch arm is (D, found by A's F-138-2: the arms were live and no call could
      -- reach them).
      'org_create','org_update','org_status_set',
      'org_member_invite','org_member_invite_admin',
      'org_member_role_change','org_member_elevate',
      'org_member_remove','org_invite_revoke','platform_role_grant',
      'venue_create','venue_submit','venue_approve','venue_staff_grant','venue_staff_revoke') then
    raise exception 'invalid_input: unknown action_type %', coalesce(p_action_type, '(null)');
  end if;
  if p_subject_kind is null or p_subject_kind not in ('case','payment','transfer','listing','user','report','job','setting','none',
                                                      'organization','venue','org_invite') then
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
            -- 138: every onboarding verb names the thing it acts on. org_create has no
            -- subject (it makes one); member and staff changes name the org or venue they
            -- happen inside, with the identity in params.
            when 'org_create'              then p_subject_kind = 'none'
            when 'org_update'              then p_subject_kind = 'organization'
            when 'org_status_set'          then p_subject_kind = 'organization'
            when 'org_member_invite'       then p_subject_kind = 'organization'
            when 'org_member_invite_admin' then p_subject_kind = 'organization'
            when 'org_member_role_change'  then p_subject_kind = 'organization'
            when 'org_member_elevate'      then p_subject_kind = 'organization'
            when 'org_member_remove'       then p_subject_kind = 'organization'
            when 'org_invite_revoke'       then p_subject_kind = 'org_invite'
            when 'platform_role_grant'     then p_subject_kind = 'none'
            when 'venue_create'            then p_subject_kind = 'organization'
            when 'venue_submit'            then p_subject_kind = 'venue'
            when 'venue_approve'           then p_subject_kind = 'venue'
            when 'venue_staff_grant'       then p_subject_kind = 'venue'
            when 'venue_staff_revoke'      then p_subject_kind = 'venue'
            else p_subject_kind = 'case' end) then
    raise exception 'invalid_input: % cannot target a %', p_action_type, p_subject_kind;
  end if;
  -- ── 138: the type<->role agreement, HERE because here is where it always runs ──────
  -- ops.action_precheck is only invoked for types that require approval (118: the call sits
  -- inside `if ops.action_requires_approval(...)`). So a guard placed only in precheck is
  -- inert for org_member_role_change and org_member_invite — the two ROUTINE types whose
  -- whole purpose is to be refused when they carry an elevating role. That is the security
  -- half of the split, and it must be checked on the path every action takes. (D, found by
  -- following A's F-138-2 question one layer down: precheck's copies pass their direct tests
  -- and never run in production for these two types.)
  -- The role is read from EXACTLY the key the type's dispatch arm reads: role_change and elevate
  -- dispatch kernel.change_org_role(params.new_role); invite and invite_admin dispatch
  -- kernel.invite_org_member(params.role). F-138-6 (D): an earlier coalesce over both keys let a
  -- routine invite carry a decoy new_role 'org_member' past this guard while dispatch invited at
  -- params.role = 'org_owner', with no second approver. The other key is refused outright, so the
  -- guard and the arm can never read different values.
  if p_action_type in ('org_member_role_change', 'org_member_elevate', 'org_member_invite', 'org_member_invite_admin') then
    v_role_key := case when p_action_type in ('org_member_invite', 'org_member_invite_admin') then 'role' else 'new_role' end;
    if coalesce(p_params, '{}'::jsonb) ? (case when v_role_key = 'role' then 'new_role' else 'role' end) then
      raise exception 'invalid_input: % takes params.% only; params.% is not accepted', p_action_type, v_role_key,
        case when v_role_key = 'role' then 'new_role' else 'role' end;
    end if;
    v_target_role := p_params ->> v_role_key;
    if p_action_type in ('org_member_role_change', 'org_member_invite')
       and v_target_role in ('org_owner', 'org_admin') then
      raise exception 'invalid_input: % to org_owner or org_admin requires two-person approval: request %',
        case when p_action_type = 'org_member_invite' then 'inviting' else 'changing a role' end,
        case when p_action_type = 'org_member_invite' then 'org_member_invite_admin' else 'org_member_elevate' end;
    end if;
    if p_action_type in ('org_member_elevate', 'org_member_invite_admin')
       and v_target_role is distinct from 'org_owner'
       and v_target_role is distinct from 'org_admin' then
      raise exception 'invalid_input: % is only for org_owner or org_admin: request %', p_action_type,
        case when p_action_type = 'org_member_invite_admin' then 'org_member_invite' else 'org_member_role_change' end;
    end if;
  end if;

  -- 138: org_create makes the organisation and platform_role_grant names its target in
  -- params (an identity, not an ops subject), so neither carries a subject_id.
  if p_subject_id is null and p_action_type not in ('case_create','job_retry','setting_set',
                                                    'org_create','platform_role_grant') then
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
  -- 138 adds the decisions someone will ask about later: the four that need two people,
  -- plus suspending or closing an organisation.
  if p_action_type in ('dispute_resolve','payout_release','listing_relist','report_resolve','user_restrict',
                       'user_unrestrict','refund_execute','setting_set',
                       'venue_approve','platform_role_grant','org_member_elevate',
                       'org_member_invite_admin','org_status_set','org_member_remove')
     and coalesce(trim(p_reason), '') = '' then
    raise exception 'invalid_input: a reason is required for %', p_action_type;
  end if;

  -- ── 138: checks that name params, after authorization so a refused caller learns nothing ──
  v_params := coalesce(p_params, '{}'::jsonb);
  -- F-138-8 (A): the BENEFICIARY of an elevating action may not be its requester. The kernel's own
  -- self-promotion checks see auth.uid() = the APPROVER when the action finally runs, so without this
  -- an org_admin could request org_owner for themselves and any second operator's approval would grant it.
  if p_action_type = 'org_member_elevate' and (v_params ->> 'identity_id') = v_uid::text then
    raise exception 'invalid_input: org_member_elevate cannot target the requester: another operator must request it';
  end if;
  if p_action_type = 'venue_approve' and coalesce(v_params ->> 'decision', '') not in ('approved', 'archived') then
    raise exception 'invalid_input: venue_approve decides approved or archived; a draft venue reaches the approval queue by venue_submit';
  end if;
  -- F-138-3 / owner item 1: the raw invitee reference is NEVER stored in a row an operator can read.
  -- ops.action.params, its audit copy and every console read carry a label instead (the masked address,
  -- or the identity UUID the owner ruled displayable). The raw value is held in ops.action_invitee, which
  -- no API role can read, until dispatch hands it to kernel.invite_org_member; kernel.org_invite keeps it
  -- for delivery exactly as before. The approval hash covers the stored params, and ops.action_invitee
  -- refuses UPDATE, so what was approved is what is dispatched.
  if p_action_type in ('org_member_invite', 'org_member_invite_admin') then
    v_invitee := nullif(trim(v_params ->> 'invitee_ref'), '');
    if v_invitee is null then
      raise exception 'invalid_input: invitee_ref required for %', p_action_type;
    end if;
    if p_action_type = 'org_member_invite_admin' then
      select lower(u.email) into v_self_email from auth.users u where u.id = v_uid;
      if lower(v_invitee) = v_uid::text or lower(v_invitee) = v_self_email then
        raise exception 'invalid_input: org_member_invite_admin cannot invite the requester: another operator must request it';
      end if;
    end if;
    v_params := (v_params - 'invitee_ref' - 'invitee_label') || jsonb_build_object('invitee_label',
      case when v_invitee ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then lower(v_invitee)
           else coalesce(ops.mask_email(v_invitee), '(reference withheld)') end);
  end if;

  begin
    insert into ops.action (idempotency_key, action_type, subject_kind, subject_id, subject_ref, params, expected, reason, requested_by)
    values (p_idempotency_key, p_action_type, p_subject_kind, p_subject_id, p_subject_ref,
            v_params, p_expected, nullif(trim(p_reason), ''), v_uid)
    returning * into a;
  exception when unique_violation then
    select * into a from ops.action where idempotency_key = p_idempotency_key;
    return jsonb_build_object('status','idempotent_replay','action_id', a.id, 'state', a.state,
                              'result', a.result, 'approval_id', a.approval_id);
  end;

  if v_invitee is not null then
    insert into ops.action_invitee (action_id, invitee_ref) values (a.id, v_invitee);
  end if;
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
      delete from ops.action_invitee where action_id = a.id;   -- 138: a refused request holds nothing
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
  -- 138: approval is decided from the queue. A venue is approved only once it has been submitted, so
  -- no second operator is asked to approve a draft (venue_submit moves draft -> pending).
  when 'venue_approve' then
    if (p_action.params ->> 'decision') = 'approved'
       and (select v.approval_status from catalog.venue v where v.venue_id = p_action.subject_id) is distinct from 'pending' then
      return jsonb_build_object('status','rejected','reject_reason','precondition',
               'message','only a pending venue can be approved: submit it first (venue_submit)');
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
  v_invitee text;   -- 138
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
    -- The raw reference was never in a.params (see execute_action); it is held beside the action.
    -- Take it and delete it FIRST: whatever this dispatch decides, the action is then terminal, and
    -- the domain invite row is the only copy delivery needs.
    select i.invitee_ref into v_invitee from ops.action_invitee i where i.action_id = a.id;
    delete from ops.action_invitee where action_id = a.id;
    if a.subject_id is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','subject_id (org) required');
    end if;
    if (a.params ->> 'role') not in ('org_owner','org_admin','org_finance','org_marketing','org_promoter_manager','org_member') then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','role is not an organisation role');
    end if;
    if v_invitee is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','no invitee reference is held for this action');
    end if;
    begin
      v_res := kernel.invite_org_member(a.subject_id, v_invitee, a.params ->> 'role', a.idempotency_key);
    exception when others then
      -- a verb message may quote the reference (077: 'an open invite already exists for %'); the
      -- outcome is recorded in ops.action and ops.audit, so it carries the label, never the address
      return jsonb_build_object('status', case when sqlstate = 'P0001' then 'rejected' else 'failed' end,
                                'reject_reason', case when sqlstate = 'P0001' then 'precondition' end,
                                'message', replace(sqlerrm, v_invitee, coalesce(a.params ->> 'invitee_label', '(reference withheld)')),
                                'sqlstate', sqlstate);
    end;
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

  -- 138: draft -> pending is the frozen verb's own 'pending' decision (RPC §3.2), taken by a single
  -- platform_admin as the explicit submission; approval and archiving stay two-person (venue_approve).
  when 'venue_submit' then
    if a.subject_id is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','subject_id (venue) required');
    end if;
    select v.approval_status into v_status from catalog.venue v where v.venue_id = a.subject_id;
    if v_status is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','venue not found');
    end if;
    if v_status <> 'draft' then
      return jsonb_build_object('status','rejected','reject_reason','precondition',
               'message', format('only a draft venue can be submitted for approval (this venue is %s)', v_status));
    end if;
    v_res := catalog.approve_venue(a.subject_id, 'pending', coalesce(nullif(trim(a.params ->> 'reason_code'), ''), 'submitted_for_approval'), a.idempotency_key);
    return jsonb_build_object('status','succeeded','result', v_res);

  when 'venue_approve' then
    if a.subject_id is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','subject_id (venue) required');
    end if;
    if (a.params ->> 'decision') not in ('approved','archived') then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','decision must be approved|archived');
    end if;
    -- re-checked when the approval runs: the venue may have left the queue since it was requested
    select v.approval_status into v_status from catalog.venue v where v.venue_id = a.subject_id;
    if (a.params ->> 'decision') = 'approved' and v_status is distinct from 'pending' then
      return jsonb_build_object('status','rejected','reject_reason','precondition',
               'message', format('only a pending venue can be approved (this venue is %s)', coalesce(v_status, 'missing')));
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

-- ── 6b. an invite's address, for the people who must see it — audited like 6 ─────
-- A second operator approving an org_owner invite should be able to see exactly who is invited, and
-- support may need the address to help with delivery. Neither needs it in every list. Same shape as the
-- contact-email verb: operator at aal2, closed reason set, one ops.audit row per call that names the
-- action and whether a reference was found, never the reference itself.
create or replace function ops.get_action_invitee(p_action_id uuid, p_reason_code text)
returns text language plpgsql volatile security definer set search_path = ''
as $ops$
declare
  a      ops.action%rowtype;
  v_ref  text;
begin
  perform ops.assert_role(array['platform_admin','platform_support']);
  if p_reason_code is null or p_reason_code not in ('approval_review','invite_delivery_support') then
    raise exception 'invalid_input: reason_code must be approval_review|invite_delivery_support';
  end if;
  select * into a from ops.action where id = p_action_id;
  if not found or a.action_type not in ('org_member_invite','org_member_invite_admin') then
    raise exception 'not_found: no invite action %', p_action_id using errcode = 'P0002';
  end if;
  -- held until dispatch; afterwards the domain invite the action created is the only copy
  select i.invitee_ref into v_ref from ops.action_invitee i where i.action_id = a.id;
  if v_ref is null and (a.result -> 'result' ->> 'invite_id') is not null then
    select oi.invitee_ref into v_ref from kernel.org_invite oi
     where oi.invite_id = (a.result -> 'result' ->> 'invite_id')::uuid;
  end if;
  perform ops.audit_write('action_invitee_read', a.subject_kind, a.subject_id, null,
                          p_reason_code, null,
                          jsonb_build_object('action_id', a.id, 'found', v_ref is not null), 'ok', a.correlation_id, a.id);
  return v_ref;
end $ops$;

-- ── 7. grants: execute to authenticated, authorization inside (116 pattern) ──
revoke all on function ops.list_organizations(text, text, integer)      from public, anon, authenticated;
revoke all on function ops.get_organization(uuid)                        from public, anon, authenticated;
revoke all on function ops.list_venues(uuid, text, integer)              from public, anon, authenticated;
revoke all on function ops.list_org_members(uuid)                        from public, anon, authenticated;
revoke all on function ops.list_org_invites(uuid)                        from public, anon, authenticated;
revoke all on function ops.list_venue_staff(uuid)                        from public, anon, authenticated;
revoke all on function ops.get_org_contact_email(uuid, text)             from public, anon, authenticated;
revoke all on function ops.get_action_invitee(uuid, text)                from public, anon, authenticated;
grant execute on function ops.list_organizations(text, text, integer)    to authenticated;
grant execute on function ops.get_organization(uuid)                     to authenticated;
grant execute on function ops.list_venues(uuid, text, integer)           to authenticated;
grant execute on function ops.list_org_members(uuid)                     to authenticated;
grant execute on function ops.list_org_invites(uuid)                     to authenticated;
grant execute on function ops.list_venue_staff(uuid)                     to authenticated;
grant execute on function ops.get_org_contact_email(uuid, text)          to authenticated;
grant execute on function ops.get_action_invitee(uuid, text)             to authenticated;

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
                               'venue_create','venue_submit','venue_approve','venue_staff_grant','venue_staff_revoke'] loop
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
     or ops.action_requires_approval('venue_submit')
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
                     'ops.get_org_contact_email(uuid,text)'::regprocedure,
                     'ops.get_action_invitee(uuid,text)'::regprocedure)
       and not (p.prosecdef
                and coalesce(p.proconfig @> array['search_path=""'], false)
                and has_function_privilege('authenticated', p.oid, 'EXECUTE')
                and not has_function_privilege('anon', p.oid, 'EXECUTE'));
    if v_bad_fn is not null then
      raise exception '138: read surface is not definer / search_path-pinned / authenticated-only: %', v_bad_fn;
    end if;
  end;

  -- the held invitee reference is readable by no API role
  if has_table_privilege('anon', 'ops.action_invitee', 'SELECT') or has_table_privilege('authenticated', 'ops.action_invitee', 'SELECT')
     or has_table_privilege('service_role', 'ops.action_invitee', 'SELECT') then
    raise exception '138: ops.action_invitee is readable by an API role';
  end if;
end $chk$;

commit;

-- ============================================================================
-- 115_ops_console_foundation.sql — Operating Console package, part 1 of 3.
--
-- WHAT THIS MIGRATION IS. Additive only. Creates the `ops` schema — the founder
-- operating console's own leaf context: cases (exception queue + ownership),
-- notes, durable action records, second-founder approvals, an append-only
-- audit, user restrictions, job bookkeeping, daily summaries, metric snapshots
-- and console settings — plus the action engine (`ops.execute_action`) that is
-- the ONLY write path the console UI has. Every entry point re-derives the
-- actor from auth.uid(), requires an operator role via kernel.is_platform()
-- (public.admin_users ∪ kernel.platform_role) and an aal2 (MFA) session, in the
-- 085/096/106 step-up idiom. Domain state (payments, transfers, listings,
-- reports, risk scores) is only ever changed by calling the already-published
-- domain functions: public.resolve_transfer_dispute,
-- public.admin_release_held_payout, public.admin_relist_listing — never by
-- direct status writes from the console.
--
-- ZERO changes to public.* objects (Gate-2 parity untouched). No policies are
-- created: ops tables are reachable only through SECURITY DEFINER functions.
-- PostgREST exposure of `ops` is an owner dashboard step (see
-- docs/admin-console/RUNBOOK.md) — nothing here depends on it.
--
-- DEPLOYMENT POSTURE: LOCAL / REHEARSAL. Production numeric tip is 109;
-- 110–114 are unapplied. This file does not reference any 110–114 object.
--
-- Rollback: supabase/rollbacks/115_ops_console_foundation_rollback.sql
-- Verification: select count(*) from information_schema.tables where table_schema='ops';  -- 13
--               select ops.whoami();  -- as an operator with aal2
-- Locks/runtime: DDL on new objects only; no rewrite of existing tables.
-- ============================================================================
begin;

create schema if not exists ops;
revoke all on schema ops from public, anon, authenticated;
grant usage on schema ops to authenticated;      -- EXECUTE is per-function
grant usage on schema ops to service_role;
alter default privileges in schema ops revoke all on tables from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- PART 1 — helpers
-- ----------------------------------------------------------------------------
create or replace function ops.raise_append_only()
returns trigger language plpgsql security definer set search_path = ''
as $ops$
begin
  raise exception 'append_only: ops.% is immutable — % is not permitted', tg_table_name, tg_op
    using errcode = 'P0001';
end;
$ops$;
revoke all on function ops.raise_append_only() from public, anon, authenticated;

create or replace function ops.set_updated_at()
returns trigger language plpgsql security definer set search_path = ''
as $ops$
begin
  new.updated_at := now();
  return new;
end;
$ops$;
revoke all on function ops.set_updated_at() from public, anon, authenticated;

-- Highest operator role of the current JWT subject, or null.
create or replace function ops.actor_role()
returns text language sql stable security definer set search_path = ''
as $ops$
  select case
    when kernel.is_platform(array['platform_admin'])   then 'platform_admin'
    when kernel.is_platform(array['platform_risk'])    then 'platform_risk'
    when kernel.is_platform(array['platform_support']) then 'platform_support'
    else null end;
$ops$;
revoke all on function ops.actor_role() from public, anon, authenticated;
grant execute on function ops.actor_role() to authenticated;

create or replace function ops.current_aal()
returns text language sql stable security definer set search_path = ''
as $ops$
  select coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb ->> 'aal';
$ops$;
revoke all on function ops.current_aal() from public, anon, authenticated;

-- Reader gate: any operator role + aal2. Raises 42501 / step_up_*.
create or replace function ops.assert_reader()
returns void language plpgsql stable security definer set search_path = ''
as $ops$
declare v_aal text;
begin
  if auth.uid() is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if ops.actor_role() is null then
    raise exception 'insufficient_privilege: operator role required' using errcode = '42501';
  end if;
  v_aal := ops.current_aal();
  if v_aal is null then
    raise exception 'step_up_unavailable: the session carries no aal claim';
  end if;
  if v_aal <> 'aal2' then
    raise exception 'step_up_required: an aal2 (MFA) session is required for the operating console';
  end if;
end;
$ops$;
revoke all on function ops.assert_reader() from public, anon, authenticated;

create or replace function ops.assert_role(p_roles text[])
returns void language plpgsql stable security definer set search_path = ''
as $ops$
begin
  perform ops.assert_reader();
  if not (ops.actor_role() = any(p_roles)) then
    raise exception 'insufficient_privilege: requires one of % (you are %)', p_roles, ops.actor_role()
      using errcode = '42501';
  end if;
end;
$ops$;
revoke all on function ops.assert_role(text[]) from public, anon, authenticated;

create or replace function ops.mask_email(p text)
returns text language sql immutable
as $ops$
  select case when p is null or position('@' in p) < 2 then null
              else left(p, 1) || '***@' || split_part(p, '@', 2) end;
$ops$;
revoke all on function ops.mask_email(text) from public, anon, authenticated;

create or replace function ops.mask_phone(p text)
returns text language sql immutable
as $ops$
  select case when p is null or length(p) < 4 then null else '•••' || right(p, 4) end;
$ops$;
revoke all on function ops.mask_phone(text) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- PART 2 — tables
-- ----------------------------------------------------------------------------
create table if not exists ops.setting (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);
alter table ops.setting enable row level security;
revoke all on ops.setting from public, anon, authenticated;
insert into ops.setting (key, value) values
  ('refund_execute_enabled', 'false'::jsonb),      -- flips only when ops-refund-execute is deployed
  ('detectors_enabled',      'true'::jsonb),
  ('dispute_sla_hours',      '72'::jsonb),
  ('transfer_deadline_soon_hours', '6'::jsonb),
  ('paid_unsettled_grace_minutes', '10'::jsonb),
  ('webhook_stuck_minutes',  '15'::jsonb),
  ('release_stuck_minutes',  '30'::jsonb),
  ('approval_ttl_hours',     '72'::jsonb)
on conflict (key) do nothing;

create table if not exists ops."case" (
  id              uuid primary key default gen_random_uuid(),
  case_type       text not null check (case_type in (
                    'paid_unsettled','transfer_deadline_soon','transfer_overdue','release_stuck',
                    'refund_pending','refund_failed','dispute_open','dispute_evidence_due',
                    'payout_review','report_review','webhook_stuck','job_failure',
                    'notification_failure','reconciliation_mismatch','manual')),
  subject_kind    text not null check (subject_kind in (
                    'payment','transfer','listing','user','dispute','report','job',
                    'webhook_event','notification','none')),
  subject_id      uuid,
  subject_ref     text,
  dedupe_key      text not null,
  title           text not null check (char_length(title) <= 200),
  summary         text check (char_length(summary) <= 4000),
  status          text not null default 'open'
                  check (status in ('open','in_progress','waiting','resolved','dismissed')),
  priority        text not null default 'p3' check (priority in ('p1','p2','p3','p4')),
  assignee        uuid references auth.users(id) on delete set null,
  due_at          timestamptz,
  detector        text not null default 'manual',
  detected_at     timestamptz not null default now(),
  last_seen_at    timestamptz not null default now(),
  resolved_at     timestamptz,
  resolved_by     uuid references auth.users(id) on delete set null,
  resolution_note text,
  version         integer not null default 1,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint case_subject_ck check (subject_id is not null or subject_ref is not null or subject_kind = 'none'),
  constraint case_resolved_ck check ((status in ('resolved','dismissed')) = (resolved_at is not null))
);
-- one OPEN case per (type, subject); a resolved one may be re-opened by a new row
create unique index if not exists case_open_dedupe_uidx on ops."case" (dedupe_key)
  where status not in ('resolved','dismissed');
create index if not exists case_queue_idx on ops."case" (status, priority, due_at nulls last, detected_at)
  where status not in ('resolved','dismissed');
create index if not exists case_assignee_idx on ops."case" (assignee, status);
create index if not exists case_subject_idx on ops."case" (subject_kind, subject_id);
create index if not exists case_type_idx on ops."case" (case_type, status);
drop trigger if exists tg_case_updated_at on ops."case";
create trigger tg_case_updated_at before update on ops."case"
  for each row execute function ops.set_updated_at();
alter table ops."case" enable row level security;
revoke all on ops."case" from public, anon, authenticated;

create table if not exists ops.case_note (
  id         uuid primary key default gen_random_uuid(),
  case_id    uuid not null references ops."case"(id) on delete cascade,
  author     uuid not null references auth.users(id) on delete restrict,
  body       text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index if not exists case_note_case_idx on ops.case_note (case_id, created_at);
drop trigger if exists tg_case_note_append_only on ops.case_note;
create trigger tg_case_note_append_only before update or delete on ops.case_note
  for each row execute function ops.raise_append_only();
alter table ops.case_note enable row level security;
revoke all on ops.case_note from public, anon, authenticated;

create table if not exists ops.case_event (
  id         uuid primary key default gen_random_uuid(),
  case_id    uuid not null references ops."case"(id) on delete cascade,
  actor      uuid references auth.users(id) on delete set null,   -- null = automation
  kind       text not null check (kind in (
               'created','seen','assigned','status_changed','priority_changed','due_changed',
               'note_added','action_requested','action_outcome','auto_resolved','reopened')),
  data       jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists case_event_case_idx on ops.case_event (case_id, created_at);
drop trigger if exists tg_case_event_append_only on ops.case_event;
create trigger tg_case_event_append_only before update or delete on ops.case_event
  for each row execute function ops.raise_append_only();
alter table ops.case_event enable row level security;
revoke all on ops.case_event from public, anon, authenticated;

create table if not exists ops.action (
  id              uuid primary key default gen_random_uuid(),
  idempotency_key text not null unique check (idempotency_key ~ '^[A-Za-z0-9._:-]{8,80}$'),
  action_type     text not null check (action_type in (
                    'case_create','case_assign','case_status','case_priority','case_due','case_note',
                    'dispute_resolve','payout_release','listing_relist','report_resolve',
                    'user_restrict','user_unrestrict','refund_execute','job_retry','setting_set')),
  subject_kind    text not null check (subject_kind in (
                    'case','payment','transfer','listing','user','report','job','setting','none')),
  subject_id      uuid,
  subject_ref     text,
  params          jsonb not null default '{}'::jsonb,
  expected        jsonb,
  reason          text check (char_length(reason) <= 2000),
  requested_by    uuid not null references auth.users(id) on delete restrict,
  requested_at    timestamptz not null default now(),
  state           text not null default 'requested' check (state in (
                    'requested','awaiting_approval','processing','succeeded','succeeded_at_provider',
                    'failed','unknown','rejected')),
  reject_reason   text,
  approval_id     uuid,
  correlation_id  uuid not null default gen_random_uuid(),
  result          jsonb,
  error           text,
  provider_ref    text,
  completed_at    timestamptz,
  version         integer not null default 1,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists action_subject_idx on ops.action (subject_kind, subject_id, requested_at desc);
create index if not exists action_state_idx on ops.action (state, requested_at desc);
create index if not exists action_requested_by_idx on ops.action (requested_by, requested_at desc);
drop trigger if exists tg_action_updated_at on ops.action;
create trigger tg_action_updated_at before update on ops.action
  for each row execute function ops.set_updated_at();
alter table ops.action enable row level security;
revoke all on ops.action from public, anon, authenticated;

create table if not exists ops.approval (
  id           uuid primary key default gen_random_uuid(),
  action_id    uuid not null references ops.action(id) on delete restrict,
  action_hash  text not null,        -- binds the approval to the exact action terms
  requested_by uuid not null references auth.users(id) on delete restrict,
  decided_by   uuid references auth.users(id) on delete restrict,
  state        text not null default 'pending'
               check (state in ('pending','approved','denied','expired','stale','cancelled')),
  reason       text,
  expires_at   timestamptz not null,
  decided_at   timestamptz,
  created_at   timestamptz not null default now(),
  constraint approval_sod_ck check (decided_by is null or decided_by <> requested_by),
  constraint approval_decided_ck check ((state in ('approved','denied')) = (decided_by is not null))
);
create unique index if not exists approval_one_pending_uidx on ops.approval (action_id) where state = 'pending';
do $ops$
begin
  if not exists (select 1 from pg_constraint where conname = 'action_approval_fk'
                   and conrelid = 'ops.action'::regclass) then
    alter table ops.action add constraint action_approval_fk
      foreign key (approval_id) references ops.approval(id) on delete set null
      deferrable initially deferred;
  end if;
end $ops$;
alter table ops.approval enable row level security;
revoke all on ops.approval from public, anon, authenticated;

create table if not exists ops.audit (
  id             uuid primary key default gen_random_uuid(),
  actor          uuid references auth.users(id) on delete restrict,   -- null = automation
  actor_role     text,
  action         text not null,
  subject_kind   text not null,
  subject_id     uuid,
  subject_ref    text,
  reason         text,
  before         jsonb,
  after          jsonb,
  outcome        text not null default 'ok',
  correlation_id uuid,
  action_id      uuid,
  occurred_at    timestamptz not null default now()
);
create index if not exists audit_occurred_idx on ops.audit (occurred_at desc);
create index if not exists audit_subject_idx on ops.audit (subject_kind, subject_id);
create index if not exists audit_action_id_idx on ops.audit (action_id);
drop trigger if exists tg_audit_append_only on ops.audit;
create trigger tg_audit_append_only before update or delete on ops.audit
  for each row execute function ops.raise_append_only();
alter table ops.audit enable row level security;
revoke all on ops.audit from public, anon, authenticated;
revoke update, delete on ops.audit from service_role;

create table if not exists ops.user_restriction (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  kind        text not null check (kind in ('listing_blocked')),
  reason      text not null,
  actor       uuid not null references auth.users(id) on delete restrict,
  created_at  timestamptz not null default now(),
  lifted_at   timestamptz,
  lifted_by   uuid references auth.users(id) on delete restrict,
  lift_reason text
);
create unique index if not exists user_restriction_active_uidx on ops.user_restriction (user_id, kind)
  where lifted_at is null;
alter table ops.user_restriction enable row level security;
revoke all on ops.user_restriction from public, anon, authenticated;

create table if not exists ops.job_state (
  job_name             text primary key,
  enabled              boolean not null default true,
  last_run_at          timestamptz,
  last_success_at      timestamptz,
  last_error           text,
  consecutive_failures integer not null default 0,
  backoff_until        timestamptz,
  updated_at           timestamptz not null default now()
);
alter table ops.job_state enable row level security;
revoke all on ops.job_state from public, anon, authenticated;

create table if not exists ops.job_run (
  id            uuid primary key default gen_random_uuid(),
  job_name      text not null,
  trigger       text not null default 'cron' check (trigger in ('cron','manual','test')),
  triggered_by  uuid references auth.users(id) on delete set null,
  started_at    timestamptz not null default now(),
  finished_at   timestamptz,
  status        text not null default 'running' check (status in ('running','succeeded','failed','skipped')),
  attempt       integer not null default 1,
  items_scanned integer not null default 0,
  cases_opened  integer not null default 0,
  cases_resolved integer not null default 0,
  error         text,
  detail        jsonb
);
create index if not exists job_run_name_idx on ops.job_run (job_name, started_at desc);
alter table ops.job_run enable row level security;
revoke all on ops.job_run from public, anon, authenticated;

create table if not exists ops.alert (
  alert_key      text primary key,
  kind           text not null,
  state          text not null default 'firing' check (state in ('firing','recovered')),
  payload        jsonb not null default '{}'::jsonb,
  first_fired_at timestamptz not null default now(),
  last_fired_at  timestamptz not null default now(),
  recovered_at   timestamptz,
  fire_count     integer not null default 1
);
alter table ops.alert enable row level security;
revoke all on ops.alert from public, anon, authenticated;

create table if not exists ops.daily_summary (
  summary_date   date primary key,
  generated_at   timestamptz not null default now(),
  body           jsonb not null,
  delivery_state text not null default 'portal_only'
                 check (delivery_state in ('portal_only','queued','sent','failed'))
);
alter table ops.daily_summary enable row level security;
revoke all on ops.daily_summary from public, anon, authenticated;

create table if not exists ops.metric_snapshot (
  key         text primary key,
  value       jsonb not null,
  computed_at timestamptz not null default now()
);
alter table ops.metric_snapshot enable row level security;
revoke all on ops.metric_snapshot from public, anon, authenticated;

-- Executors (edge functions running as service_role) read the action and its
-- approval directly; everything else they touch goes through
-- ops.record_action_outcome. No default privileges exist for ops in this
-- project, so the grants are explicit and read-only.
grant select on ops.action, ops.approval to service_role;

-- ----------------------------------------------------------------------------
-- PART 3 — audit writer (internal; owner-executed only)
-- ----------------------------------------------------------------------------
create or replace function ops.audit_write(
  p_action text, p_subject_kind text, p_subject_id uuid, p_subject_ref text,
  p_reason text, p_before jsonb, p_after jsonb, p_outcome text,
  p_correlation_id uuid, p_action_id uuid)
returns uuid language plpgsql security definer set search_path = ''
as $ops$
declare v_id uuid;
begin
  insert into ops.audit (actor, actor_role, action, subject_kind, subject_id, subject_ref, reason,
                         before, after, outcome, correlation_id, action_id)
  values (auth.uid(), ops.actor_role(), p_action, p_subject_kind, p_subject_id, p_subject_ref, p_reason,
          p_before, p_after, coalesce(p_outcome, 'ok'), p_correlation_id, p_action_id)
  returning id into v_id;
  return v_id;
end;
$ops$;
revoke all on function ops.audit_write(text,text,uuid,text,text,jsonb,jsonb,text,uuid,uuid) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- PART 4 — case engine (internal writers used by the action engine and the
-- detectors in 117)
-- ----------------------------------------------------------------------------
create or replace function ops.case_upsert(
  p_case_type text, p_subject_kind text, p_subject_id uuid, p_subject_ref text,
  p_title text, p_summary text, p_priority text, p_due_at timestamptz, p_detector text)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_key text := p_case_type || ':' || coalesce(p_subject_id::text, p_subject_ref, 'none');
  v_id  uuid;
  v_opened boolean := false;
begin
  select id into v_id from ops."case"
   where dedupe_key = v_key and status not in ('resolved','dismissed')
   for update;
  if found then
    update ops."case"
       set last_seen_at = now(),
           summary = coalesce(p_summary, summary),
           due_at = coalesce(p_due_at, due_at),
           -- a detector may only raise urgency, never lower a human's choice
           priority = case when p_priority < priority then p_priority else priority end
     where id = v_id;
  else
    begin
      insert into ops."case" (case_type, subject_kind, subject_id, subject_ref, dedupe_key, title, summary,
                              priority, due_at, detector)
      values (p_case_type, p_subject_kind, p_subject_id, p_subject_ref, v_key, left(p_title, 200), p_summary,
              coalesce(p_priority, 'p3'), p_due_at, coalesce(p_detector, 'manual'))
      returning id into v_id;
      v_opened := true;
      insert into ops.case_event (case_id, actor, kind, data)
      values (v_id, auth.uid(), 'created', jsonb_build_object('detector', p_detector, 'dedupe_key', v_key));
    exception when unique_violation then
      -- a concurrent detector run opened it first: converge on that row
      select id into v_id from ops."case"
       where dedupe_key = v_key and status not in ('resolved','dismissed');
    end;
  end if;
  return jsonb_build_object('case_id', v_id, 'opened', v_opened, 'dedupe_key', v_key);
end;
$ops$;
revoke all on function ops.case_upsert(text,text,uuid,text,text,text,text,timestamptz,text) from public, anon, authenticated;

-- Resolve every open detector-owned case of p_case_type whose dedupe_key is NOT
-- in the still-active set (the condition cleared). Returns the count.
create or replace function ops.case_auto_resolve(p_case_type text, p_active_keys text[])
returns integer language plpgsql security definer set search_path = ''
as $ops$
declare v_n integer;
begin
  with closed as (
    update ops."case" c
       set status = 'resolved', resolved_at = now(), resolved_by = null,
           resolution_note = 'auto: condition no longer detected', version = version + 1
     where c.case_type = p_case_type
       and c.detector <> 'manual'
       and c.status not in ('resolved','dismissed')
       and not (c.dedupe_key = any(coalesce(p_active_keys, array[]::text[])))
    returning c.id)
  insert into ops.case_event (case_id, actor, kind, data)
  select id, null, 'auto_resolved', jsonb_build_object('reason', 'condition_cleared') from closed;
  get diagnostics v_n = row_count;
  return v_n;
end;
$ops$;
revoke all on function ops.case_auto_resolve(text,text[]) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- PART 5 — action engine
-- ----------------------------------------------------------------------------
create or replace function ops.action_hash(p_action_type text, p_subject_kind text, p_subject_id uuid,
                                           p_subject_ref text, p_params jsonb)
returns text language sql immutable
as $ops$
  select encode(extensions.digest(
           p_action_type || '|' || p_subject_kind || '|' || coalesce(p_subject_id::text, '') || '|' ||
           coalesce(p_subject_ref, '') || '|' || coalesce(p_params::text, '{}'), 'sha256'), 'hex');
$ops$;
revoke all on function ops.action_hash(text,text,uuid,text,jsonb) from public, anon, authenticated;

-- Which roles may request which action.
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

-- Internal: perform the domain effect of an action row. Returns jsonb with
-- status ∈ succeeded | processing | rejected. Raises only on unexpected errors
-- (the caller classifies P0001 from domain RPCs as a precondition rejection).
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
    -- The money leg runs in the ops-refund-execute edge function (Stripe
    -- idempotency key = ops_action_<id>); it reports back through
    -- ops.record_action_outcome. Until then the action is `processing`.
    return jsonb_build_object('status','processing','handoff','ops-refund-execute',
             'stripe_payment_intent_id', v_row.stripe_payment_intent_id,
             'amount_cents', coalesce((a.params ->> 'amount_cents')::integer, v_row.total));

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

-- Resolve open cases of a type for one subject as the consequence of an action.
create or replace function ops.case_auto_resolve_subject(p_case_type text, p_subject_id uuid, p_action_id uuid)
returns integer language plpgsql security definer set search_path = ''
as $ops$
declare v_n integer;
begin
  with closed as (
    update ops."case" c
       set status = 'resolved', resolved_at = now(), resolved_by = auth.uid(),
           resolution_note = 'resolved by action ' || p_action_id::text, version = version + 1
     where c.case_type = p_case_type and c.subject_id = p_subject_id
       and c.status not in ('resolved','dismissed')
    returning c.id)
  insert into ops.case_event (case_id, actor, kind, data)
  select id, auth.uid(), 'action_outcome', jsonb_build_object('action_id', p_action_id, 'resolved', true) from closed;
  get diagnostics v_n = row_count;
  return v_n;
end;
$ops$;
revoke all on function ops.case_auto_resolve_subject(text,uuid,uuid) from public, anon, authenticated;

-- Internal: run dispatch for a stored action, classify, persist outcome, audit.
create or replace function ops.action_run(p_action_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  a      ops.action%rowtype;
  v_res  jsonb;
  v_state text;
begin
  select * into a from ops.action where id = p_action_id for update;
  if a.state not in ('requested','awaiting_approval','processing') then
    return jsonb_build_object('status','idempotent_replay','action_id', a.id, 'state', a.state, 'result', a.result);
  end if;
  update ops.action set state = 'processing', version = version + 1 where id = a.id;
  begin
    v_res := ops.action_dispatch(a);
  exception
    when others then
      if sqlstate = 'P0001' then
        v_res := jsonb_build_object('status','rejected','reject_reason','precondition','message', sqlerrm);
      else
        v_res := jsonb_build_object('status','failed','message', sqlerrm, 'sqlstate', sqlstate);
      end if;
  end;
  v_state := case v_res ->> 'status'
               when 'succeeded'  then 'succeeded'
               when 'processing' then 'processing'
               when 'rejected'   then 'rejected'
               else 'failed' end;
  update ops.action
     set state = v_state,
         result = v_res,
         reject_reason = case when v_state = 'rejected' then v_res ->> 'reject_reason' end,
         error = case when v_state = 'failed' then v_res ->> 'message' end,
         completed_at = case when v_state in ('succeeded','rejected','failed') then now() end,
         version = version + 1
   where id = a.id;
  perform ops.audit_write('action.' || a.action_type, a.subject_kind, a.subject_id, a.subject_ref, a.reason,
                          a.expected, v_res, v_state, a.correlation_id, a.id);
  if a.subject_kind = 'case' and a.subject_id is not null
     and exists (select 1 from ops."case" where id = a.subject_id) then
    insert into ops.case_event (case_id, actor, kind, data)
    values (a.subject_id, auth.uid(), 'action_outcome',
            jsonb_build_object('action_id', a.id, 'action_type', a.action_type, 'state', v_state));
  end if;
  return jsonb_build_object('status', v_state, 'action_id', a.id, 'result', v_res,
                            'reject_reason', v_res ->> 'reject_reason', 'message', v_res ->> 'message');
end;
$ops$;
revoke all on function ops.action_run(uuid) from public, anon, authenticated;

-- Cheap precondition check run BEFORE an approval is parked, so a second
-- founder is never asked to approve something that can no longer happen.
-- Returns null when the action may proceed, else the rejection jsonb.
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
  else
    null;
  end case;
  return null;
end;
$ops$;
revoke all on function ops.action_precheck(ops.action) from public, anon, authenticated;

-- PUBLIC ENTRY POINT — the console's single write path.
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

-- Second-founder approval. Bound to the action hash; approver ≠ requester.
create or replace function ops.approve_action(p_action_id uuid, p_decision text, p_reason text)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_uid uuid := auth.uid();
  a     ops.action%rowtype;
  ap    ops.approval%rowtype;
begin
  perform ops.assert_role(array['platform_admin']);
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

-- Outcome callback for asynchronous executors (edge functions, service_role only).
create or replace function ops.record_action_outcome(
  p_action_id uuid, p_state text, p_result jsonb, p_error text, p_provider_ref text)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare a ops.action%rowtype;
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
  if a.state in ('succeeded','rejected') then
    return jsonb_build_object('status','idempotent_replay','state', a.state);
  end if;
  update ops.action
     set state = p_state,
         result = coalesce(a.result, '{}'::jsonb) || coalesce(p_result, '{}'::jsonb),
         error = p_error,
         provider_ref = coalesce(p_provider_ref, a.provider_ref),
         completed_at = case when p_state in ('succeeded','failed') then now() else completed_at end,
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

-- ----------------------------------------------------------------------------
-- PART 6 — identity readers
-- ----------------------------------------------------------------------------
create or replace function ops.whoami()
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare v_role text; v_email text;
begin
  if auth.uid() is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  v_role := ops.actor_role();
  if v_role is null then
    raise exception 'insufficient_privilege: operator role required' using errcode = '42501';
  end if;
  select email into v_email from auth.users where id = auth.uid();
  return jsonb_build_object('user_id', auth.uid(), 'role', v_role, 'aal', ops.current_aal(),
                            'email_masked', ops.mask_email(v_email));
end;
$ops$;
revoke all on function ops.whoami() from public, anon, authenticated;
grant execute on function ops.whoami() to authenticated;

create or replace function ops.operators()
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
begin
  perform ops.assert_reader();
  return coalesce((
    select jsonb_agg(jsonb_build_object('user_id', s.user_id, 'label', s.label, 'role', s.role,
                                        'email_masked', ops.mask_email(u.email)) order by s.role, s.label)
      from (
        select a.user_id, a.label, 'platform_admin'::text as role from public.admin_users a
        union
        select r.identity_id, coalesce(p.display_name, ''), r.role
          from kernel.platform_role r left join public.profiles p on p.id = r.identity_id
      ) s
      left join auth.users u on u.id = s.user_id), '[]'::jsonb);
end;
$ops$;
revoke all on function ops.operators() from public, anon, authenticated;
grant execute on function ops.operators() to authenticated;

commit;

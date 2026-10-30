-- 077_kernel_identity_orgs_and_roles.sql
-- =============================================================================
-- Phase-2 package 077 — the tenant + identity-extension + scope-qualified role
-- substrate (C36), the privileged audit backbone, the generic dual-control
-- object, and the OR-17 deletion state machine (F-P0-1 Option A).
--
-- FROZEN SOURCES (architecture frozen at 06fd5ecccc405f416e8f27591ccbbf709771f8ef,
-- tag phase2-architecture-v2; implementer mode — no redesign):
--   plan §8/077 row (the derived closed world; §8 wins over §5) · registry JSON
--   row 077 + hooks array (11 of the 19 SEAM-2 hooks stub here) · schema-spec
--   §0/§1.1-§1.15 · DEMOG §10.2/§8 · CRM §11.2/§11.3 · RPC contracts §0, §1.1,
--   §2, §20.1, §17.20/§17.20a/§17.21, §20.17 · RLS spec (8-policy register,
--   zero-policy register, §11 EXEC classes, I-12 INV-NOFORCE) ·
--   _governance/DELETION_STATE_MACHINE_SPEC.md (OR-13) ·
--   _governance/CRON_SCHEDULE_REGISTER.md (both 077 jobs) ·
--   _governance/R2_EMITTER_CLASSIFICATION.md rows 22/31/32 (all BEST-EFFORT).
--
-- POST-FREEZE AMENDMENTS EXERCISED HERE (filed in
-- docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md BEFORE this commit):
--   PFA-3 — OPEN-3 erased-marker cell exercised as representation (i): the
--           terminal deletion_state literal is 'ERASED'; no companion column.
--   PFA-4 — kernel.grant_platform_role's §20.1.4 dual-control parking is
--           impossible against the frozen kernel.approval_request closed sets
--           (action CHECK, pairing CHECK, T-RPC-AUTHZ-15 writer fence). The
--           grant arm FAILS CLOSED pending the owner's signature; revocation
--           executes per contract. OWNER SIGNATURE REQUIRED: YES.
--   PFA-5 — §20.17.3's "STABLE + FOR SHARE" pair is a PostgreSQL impossibility
--           (0A000: SELECT FOR SHARE is not allowed in a non-volatile function,
--           proven on 17.11). is_deletion_pending is VOLATILE and KEEPS the
--           F-11 serialization lock.
--
-- WHAT THIS PACKAGE DELIBERATELY DOES NOT CONTAIN (boundary, frozen):
--   kernel.money_role_grant_matured (078 — SEAM-1 avoided edge 077→078) ·
--   has_venue_role/has_event_role/has_org_role_over_* (080) ·
--   list_approval_requests, record_money_denial, the approval/refund RPCs (085)
--   · org_contact_consent(+_event) and the org-consent RPCs (082) ·
--   SN-VOID/SN-SYSTEM sentinel seeds (078, MB-5) · crm_export_builder, any
--   _sel_svc_export policy, any auth.users grant (OR-1: never built) ·
--   kernel.org_money_policy (COND-C — unratified, recommendation No) ·
--   the outbox drainer (092) · the delete-account edge switch + the F-5
--   live-rail guards (DEPLOY ARTIFACTS on this package's release train, FR-9 —
--   edge/RN-layer code, not database objects; they remain owed on the release
--   train BEFORE any production apply of 077, per OR-17 §1.8a).
--
-- LOCKS / RUNTIME: new-table DDL only; every CREATE INDEX runs on an empty
-- table (instant). GRANT/REVOKE touch catalog only. Runtime: seconds.
-- BACKFILL: none. kernel.identity_ext is lazily created per identity on first
-- write — no bulk backfill of auth.users (plan §0.5).
--
-- ROLLBACK: supabase/rollbacks/077_kernel_identity_orgs_and_roles_rollback.sql
-- Posture: CLEAN-WHILE-EMPTY (plan §8/077). admin_audit and approval_request
-- become forward-fix once they hold real audit/adjudication rows.
--
-- VERIFICATION QUERY (post-apply):
--   select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
--    where n.nspname='kernel' and c.relkind='r';                     -- 12
--   select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--    where n.nspname='kernel';                                       -- 40 (38 + the two 076 helpers)
--   select jobname from cron.job where jobname like 'sweep-%';       -- 2 rows
-- =============================================================================

-- =============================================================================
-- PART 1 — TABLES (twelve; deny-by-default at birth; explicit ON DELETE on
-- every FK — RESTRICT is the ODR-16 corpus default, CASCADE only on the D-3/D-9
-- named exceptions)
-- =============================================================================

-- 1.1 kernel.identity_ext (schema §1.1) --------------------------------------
create table if not exists kernel.identity_ext (
  identity_id           uuid primary key
                        references auth.users(id) on delete restrict,
  residency_region      text not null default 'us-east'
                        check (residency_region in ('us-east')),
  kyc_ref               text,
  -- Δ-N2: preferred render locale; NULL means "not stated" (third link of the
  -- resolution chain), never a default written into every row.
  locale                text,
  -- OR-17 deletion-machine substrate. Third CHECK literal 'ERASED' is the
  -- PFA-3 exercise of OPEN-3 (representation (i) — the ruled B3 column itself
  -- reaches the terminal value; the corpus's own "natural reading").
  deletion_state        text not null default 'ACTIVE'
                        check (deletion_state in ('ACTIVE','DELETION_PENDING','ERASED')),
  deletion_requested_at timestamptz,   -- RETAINED at terminal (dsm §4.1)
  deletion_block_reason text,          -- first-failing BP, written each sweep pass
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

-- OR-17: the sweep's access path over open deletion requests.
create index if not exists identity_ext_deletion_pending_idx
  on kernel.identity_ext (identity_id)
  where deletion_state = 'DELETION_PENDING';

alter table kernel.identity_ext enable row level security;
revoke all on kernel.identity_ext from public, anon, authenticated;
-- Owner-scoped read of own row (incl. own deletion state — schema §1.1 write-
-- authority note: "the user reads own state via the owner-scoped row policy").
grant select on kernel.identity_ext to authenticated;

drop trigger if exists tg_identity_ext_updated_at on kernel.identity_ext;
create trigger tg_identity_ext_updated_at
  before update on kernel.identity_ext
  for each row execute function kernel.set_updated_at();

-- 1.2 kernel.organization (schema §1.2) --------------------------------------
create table if not exists kernel.organization (
  org_id                          uuid primary key default gen_random_uuid(),
  legal_name                      text not null check (length(trim(legal_name)) > 0),
  display_name                    text not null check (length(trim(display_name)) > 0),
  status                          text not null default 'applied'
                                  check (status in ('applied','approved','active','suspended','closed')),
  -- reuses the existing Stripe Connect account id (Phase-0 payout discipline);
  -- NOT a new Connect integration.
  stripe_connect_account_ref      text,
  payout_destination_locked_until timestamptz,
  -- MONEY §12 ADDITIVE-3: the SoD-1 operand — who last set the payout
  -- destination. 16d: RETAINED at tombstone, never nulled.
  payout_destination_set_by       uuid references auth.users(id) on delete restrict,
  home_region                     text not null default 'us-east',
  created_at                      timestamptz not null default now(),
  updated_at                      timestamptz not null default now()
);

create unique index if not exists organization_connect_ref_key
  on kernel.organization (stripe_connect_account_ref)
  where stripe_connect_account_ref is not null;

create index if not exists organization_active_idx
  on kernel.organization (org_id)
  where status = 'active';

alter table kernel.organization enable row level security;
revoke all on kernel.organization from public, anon, authenticated;
-- Column-scoped SELECT (RLS §7.2 note 4: org_member/org_admin see
-- display_name/status only). The payout-ref/legal_name cells for
-- org_owner/org_finance are grant-inexpressible inside the single
-- `authenticated` role and ride later scoped RPCs — recorded errata E-1.
grant select (org_id, display_name, status) on kernel.organization to authenticated;

drop trigger if exists tg_organization_updated_at on kernel.organization;
create trigger tg_organization_updated_at
  before update on kernel.organization
  for each row execute function kernel.set_updated_at();

-- 1.3 kernel.org_member (schema §1.3; M-5 canonical SIX labels; X-11 granted_at)
create table if not exists kernel.org_member (
  org_id      uuid not null references kernel.organization(org_id) on delete restrict,
  identity_id uuid not null references auth.users(id) on delete restrict,
  role        text not null
              check (role in ('org_owner','org_admin','org_finance',
                              'org_marketing','org_promoter_manager','org_member')),
  granted_by  uuid references auth.users(id) on delete restrict,
  -- C-1c / X-11: the maturity clock of the CURRENT role. Written by
  -- accept_org_invite; RESET by change_org_role on promotion INTO a money role.
  granted_at  timestamptz not null default now(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (org_id, identity_id)
);

create index if not exists org_member_identity_idx
  on kernel.org_member (identity_id);

-- I-12 / INV-NOFORCE: RLS ENABLED, never FORCED — the predicate helpers rely
-- on owner-bypass to terminate (asserted positively in the test suite).
alter table kernel.org_member enable row level security;
revoke all on kernel.org_member from public, anon, authenticated;
grant select (org_id, identity_id, role) on kernel.org_member to authenticated;

drop trigger if exists tg_org_member_updated_at on kernel.org_member;
create trigger tg_org_member_updated_at
  before update on kernel.org_member
  for each row execute function kernel.set_updated_at();

-- 1.4 kernel.org_invite (schema §1.3b; OR-18: 'declined' STRUCK) -------------
create table if not exists kernel.org_invite (
  invite_id               uuid primary key default gen_random_uuid(),
  org_id                  uuid not null references kernel.organization(org_id) on delete restrict,
  invitee_ref             text not null,
  invitee_identity_id     uuid references auth.users(id) on delete restrict,
  role                    text not null
                          check (role in ('org_owner','org_admin','org_finance',
                                          'org_marketing','org_promoter_manager','org_member')),
  status                  text not null default 'pending'
                          check (status in ('pending','accepted','expired','revoked')),
  invited_by              uuid not null references auth.users(id) on delete restrict,
  expires_at              timestamptz not null,
  command_idempotency_key text not null,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  check (expires_at > created_at)
);

create unique index if not exists org_invite_pending_key
  on kernel.org_invite (org_id, invitee_ref)
  where status = 'pending';

create unique index if not exists org_invite_command_key
  on kernel.org_invite (org_id, command_idempotency_key);

create index if not exists org_invite_invitee_idx
  on kernel.org_invite (invitee_identity_id, status);

alter table kernel.org_invite enable row level security;
revoke all on kernel.org_invite from public, anon, authenticated;
grant select (invite_id, org_id, invitee_ref, invitee_identity_id, role, status,
              invited_by, expires_at, created_at)
  on kernel.org_invite to authenticated;

drop trigger if exists tg_org_invite_updated_at on kernel.org_invite;
create trigger tg_org_invite_updated_at
  before update on kernel.org_invite
  for each row execute function kernel.set_updated_at();

-- 1.5 kernel.platform_role (schema §1.4) -------------------------------------
create table if not exists kernel.platform_role (
  identity_id uuid not null references auth.users(id) on delete restrict,
  role        text not null
              check (role in ('platform_admin','platform_support','platform_risk')),
  granted_by  uuid references auth.users(id) on delete restrict,
  -- a grant is a row, so created_at IS the grant time (C-1c: the platform
  -- plane needs no granted_at column).
  created_at  timestamptz not null default now(),
  primary key (identity_id, role)
);

create index if not exists platform_role_role_idx
  on kernel.platform_role (role);

-- I-12 / INV-NOFORCE (second of the two 077 tables under the exemption).
alter table kernel.platform_role enable row level security;
revoke all on kernel.platform_role from public, anon, authenticated;
grant select on kernel.platform_role to authenticated;

-- 1.6 kernel.admin_audit (schema §1.12 — AO) ---------------------------------
create table if not exists kernel.admin_audit (
  id             uuid primary key default gen_random_uuid(),
  actor_identity uuid not null references auth.users(id) on delete restrict,
  action         text not null,   -- namespaced, open vocabulary (deliberate — §1.12)
  subject_kind   text not null,
  subject_id     uuid not null,
  reason_code    text not null,
  before         jsonb,
  after          jsonb,
  occurred_at    timestamptz not null default now(),
  created_at     timestamptz not null default now()
);

create index if not exists admin_audit_subject_idx
  on kernel.admin_audit (subject_kind, subject_id);
create index if not exists admin_audit_actor_idx
  on kernel.admin_audit (actor_identity);
create index if not exists admin_audit_occurred_idx
  on kernel.admin_audit (occurred_at);

alter table kernel.admin_audit enable row level security;
revoke all on kernel.admin_audit from public, anon, authenticated;
-- AO: additionally no UPDATE/DELETE for anyone, incl. service_role.
revoke update, delete on kernel.admin_audit from service_role;

drop trigger if exists tg_admin_audit_append_only on kernel.admin_audit;
create trigger tg_admin_audit_append_only
  before update or delete on kernel.admin_audit
  for each row execute function kernel.raise_append_only();

-- 1.7 kernel.approval_request (schema §1.13 — the generic dual-control object)
create table if not exists kernel.approval_request (
  request_id              uuid primary key default gen_random_uuid(),
  action                  text not null
                          check (action in ('refund.issue','payout.request','config.set_money_key')),
  -- C-1a: the STORED, PINNED authority discriminator; written server-side at
  -- request time by the requesting function (078/085/087), never recomputed.
  required_approver_class text not null
                          check (required_approver_class in ('org','platform','platform_admin')),
  subject_kind            text not null
                          check (subject_kind in ('order','settlement','config_key')),
  subject_id              uuid not null,   -- deliberately soft (APPR-SUBJ-1/2)
  org_id                  uuid references kernel.organization(org_id) on delete restrict,
  payload                 jsonb not null,  -- evidence, never authority (T-RPC-AUTHZ-01)
  -- R-27 / MB-1: the parked term of the cumulative tier operand.
  amount_minor            integer,
  config_versions         jsonb not null,
  requested_by            uuid not null references auth.users(id) on delete restrict,
  approved_by             uuid references auth.users(id) on delete restrict,
  state                   text not null default 'pending'
                          check (state in ('pending','approved','denied','cancelled','expired','stale')),
  reason_code             text,
  expires_at              timestamptz not null,
  command_idempotency_key text not null,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  -- schema §1.13 CHECKs (1)-(8), verbatim semantics:
  constraint approval_request_sod_check
    check (approved_by is null or approved_by <> requested_by),                      -- (1)
  constraint approval_request_approved_attributed_check
    check (state <> 'approved' or approved_by is not null),                          -- (2)
  constraint approval_request_denied_attributed_check
    check (state <> 'denied' or approved_by is not null),                            -- (3)
  constraint approval_request_action_subject_pairing_check
    check (   (action = 'refund.issue'         and subject_kind = 'order')
           or (action = 'payout.request'       and subject_kind = 'settlement')
           or (action = 'config.set_money_key' and subject_kind = 'config_key')),    -- (4)
  constraint approval_request_money_key_class_check
    check (action <> 'config.set_money_key' or required_approver_class = 'platform_admin'), -- (5)
  constraint approval_request_org_arm_scoped_check
    check (required_approver_class <> 'org' or org_id is not null),                  -- (6)
  constraint approval_request_amount_present_check
    check (action = 'config.set_money_key' or amount_minor is not null),             -- (7)
  constraint approval_request_amount_positive_check
    check (amount_minor is null or amount_minor > 0),                                -- (8)
  -- plus, unchanged (§1.13): the org-scope arm and the expiry bound
  constraint approval_request_org_scope_check
    check (   (action in ('refund.issue','payout.request') and org_id is not null)
           or (action = 'config.set_money_key' and org_id is null)),
  constraint approval_request_expiry_check
    check (expires_at > created_at),
  constraint approval_request_command_key_key
    unique (requested_by, command_idempotency_key)                                   -- C16
);

create index if not exists approval_request_org_state_idx
  on kernel.approval_request (org_id, state);
create index if not exists approval_request_expiry_idx
  on kernel.approval_request (expires_at)
  where state = 'pending';
create index if not exists approval_request_subject_idx
  on kernel.approval_request (subject_kind, subject_id);
create index if not exists approval_request_authority_idx
  on kernel.approval_request (action, required_approver_class, state);
-- X-10: the platform-review queue carries org_id IS NULL and is invisible to
-- the (org_id, state) index.
create index if not exists approval_request_platform_queue_idx
  on kernel.approval_request (required_approver_class, created_at)
  where state = 'pending';

alter table kernel.approval_request enable row level security;
revoke all on kernel.approval_request from public, anon, authenticated;

drop trigger if exists tg_approval_request_updated_at on kernel.approval_request;
create trigger tg_approval_request_updated_at
  before update on kernel.approval_request
  for each row execute function kernel.set_updated_at();

-- 1.8 kernel.identity_demographic (DEMOG §10.2 — MUT, not a ledger) ----------
-- D-9 named exception: ON DELETE CASCADE from auth.users (house pattern
-- 012/023/033); GP-2 excepted for clear_my_demographics' definer DELETE only.
create table if not exists kernel.identity_demographic (
  identity_id       uuid primary key references auth.users(id) on delete cascade,
  gender_identity   text
                    check (gender_identity in ('woman','man','non_binary',
                                               'another_gender_identity','prefer_not_to_say')),
  notice_version    text not null,
  first_answered_at timestamptz not null,
  updated_at        timestamptz not null default now()
);

alter table kernel.identity_demographic enable row level security;
revoke all on kernel.identity_demographic from public, anon, authenticated;
-- The grant set is EMPTY, not reduced (DEMOG §10.3).

drop trigger if exists tg_identity_demographic_updated_at on kernel.identity_demographic;
create trigger tg_identity_demographic_updated_at
  before update on kernel.identity_demographic
  for each row execute function kernel.set_updated_at();
-- (the BEFORE DELETE erasure trigger is attached in Part 4, after its function)

-- 1.9 kernel.identity_demographic_erasure (DEMOG §10.2 — AO, value-free) -----
-- Append-many: surrogate PK, one immutable row per erasure (§17.20a).
-- identity_id deliberately carries NO FK (a CASCADE would delete the tombstone
-- in the statement that creates the need for it; RESTRICT would block deletion).
-- purge_after is NULLABLE: OR-16/F-P1-3 failsafe — key absent => NULL =
-- never-purgeable (supersedes the older NOT NULL cell; recorded errata E-2).
create table if not exists kernel.identity_demographic_erasure (
  id          uuid primary key default gen_random_uuid(),
  identity_id uuid not null,
  erased_at   timestamptz not null,
  purge_after timestamptz
);

create index if not exists identity_demographic_erasure_identity_idx
  on kernel.identity_demographic_erasure (identity_id);

alter table kernel.identity_demographic_erasure enable row level security;
revoke all on kernel.identity_demographic_erasure from public, anon, authenticated;
revoke update, delete on kernel.identity_demographic_erasure from service_role;

drop trigger if exists tg_identity_demographic_erasure_append_only on kernel.identity_demographic_erasure;
create trigger tg_identity_demographic_erasure_append_only
  before update or delete on kernel.identity_demographic_erasure
  for each row execute function kernel.raise_append_only();

-- 1.10 kernel.identity_contact_pref (CRM §11.2 — MUT; kill switch) -----------
create table if not exists kernel.identity_contact_pref (
  identity_id         uuid primary key references auth.users(id) on delete cascade,  -- D-3
  venue_email_contact text not null default 'allow'
                      check (venue_email_contact in ('allow','block')),
  updated_at          timestamptz not null default now()
);

alter table kernel.identity_contact_pref enable row level security;
revoke all on kernel.identity_contact_pref from public, anon, authenticated;

drop trigger if exists tg_identity_contact_pref_updated_at on kernel.identity_contact_pref;
create trigger tg_identity_contact_pref_updated_at
  before update on kernel.identity_contact_pref
  for each row execute function kernel.set_updated_at();

-- 1.11 kernel.identity_contact_pref_event (schema §1.15.1 — K-2, AO) ---------
create table if not exists kernel.identity_contact_pref_event (
  id                  uuid primary key default gen_random_uuid(),
  identity_id         uuid not null references auth.users(id) on delete cascade,     -- D-3
  venue_email_contact text not null
                      check (venue_email_contact in ('allow','block')),
  occurred_at         timestamptz not null default now()
  -- deliberately NO occurred_at monotonicity CHECK (§1.15.1: a legitimate
  -- same-instant pair must not fail)
);

-- the consent gate's whole access path (as-of read)
create index if not exists identity_contact_pref_event_asof_idx
  on kernel.identity_contact_pref_event (identity_id, occurred_at desc);

alter table kernel.identity_contact_pref_event enable row level security;
revoke all on kernel.identity_contact_pref_event from public, anon, authenticated;
-- AO enforced by grant, not convention — incl. service_role (RLS §16.6).
revoke update, delete on kernel.identity_contact_pref_event from service_role;

drop trigger if exists tg_identity_contact_pref_event_append_only on kernel.identity_contact_pref_event;
create trigger tg_identity_contact_pref_event_append_only
  before update or delete on kernel.identity_contact_pref_event
  for each row execute function kernel.raise_append_only();

-- 1.12 kernel.org_customer_key (CRM §11.2 — secret, definer-only) ------------
-- key_material is never returned by any RPC, never logged, never exported.
-- rotated_at has NO Phase-2 writer (OR-20: rotation is the incident-response
-- runbook's manual, audited act).
create table if not exists kernel.org_customer_key (
  org_id       uuid primary key references kernel.organization(org_id) on delete restrict,
  key_material bytea not null,
  created_at   timestamptz not null default now(),
  rotated_at   timestamptz
);

alter table kernel.org_customer_key enable row level security;
revoke all on kernel.org_customer_key from public, anon, authenticated;
-- no human role, including platform_admin (CRM §11.3)

-- =============================================================================
-- PART 2 — PREDICATE HELPERS (RPC §1.1/§1.1b; STABLE, definer, live-table
-- reads, never JWT claims; the ONLY sanctioned role tests — C36)
-- =============================================================================

create or replace function kernel.has_org_role(p_org_id uuid, p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from kernel.org_member m
     where m.org_id      = p_org_id
       and m.identity_id = auth.uid()
       and m.role        = any(p_roles)
  );
$$;

create or replace function kernel.is_platform(p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  -- kernel.platform_role plus the public.admin_users bootstrap: the frozen
  -- Phase-0 table is read (never written) and satisfies only the
  -- platform_admin arm — "the first platform_admin cannot be granted by a
  -- platform_admin" (§20.1.4).
  select exists (
    select 1 from kernel.platform_role r
     where r.identity_id = auth.uid()
       and r.role        = any(p_roles)
  )
  or (
    'platform_admin' = any(p_roles)
    and exists (select 1 from public.admin_users a where a.user_id = auth.uid())
  );
$$;

create or replace function kernel.is_org_affiliate(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  -- RM-6: affiliation is a SCOPING input, never an AUTHORIZING one.
  select exists (
    select 1 from kernel.org_member m
     where m.org_id = p_org_id and m.identity_id = auth.uid()
  );
$$;

-- =============================================================================
-- PART 3 — RLS POLICIES (the frozen 8-name register, exactly; FOR SELECT only;
-- zero policies on admin_audit, approval_request, and the five demographic/CRM
-- tables — RLS enabled with no policy IS the deny; GP-3)
-- =============================================================================

drop policy if exists kernel_identity_ext_sel_owner on kernel.identity_ext;
create policy kernel_identity_ext_sel_owner
  on kernel.identity_ext for select to authenticated
  using (identity_id = auth.uid());

drop policy if exists kernel_organization_sel_org on kernel.organization;
create policy kernel_organization_sel_org
  on kernel.organization for select to authenticated
  using (kernel.is_org_affiliate(org_id));

drop policy if exists kernel_organization_sel_platform on kernel.organization;
create policy kernel_organization_sel_platform
  on kernel.organization for select to authenticated
  using (kernel.is_platform(array['platform_admin','platform_support','platform_risk']));

drop policy if exists kernel_org_member_sel_org on kernel.org_member;
create policy kernel_org_member_sel_org
  on kernel.org_member for select to authenticated
  using (kernel.is_org_affiliate(org_id));

drop policy if exists kernel_org_member_sel_platform on kernel.org_member;
create policy kernel_org_member_sel_platform
  on kernel.org_member for select to authenticated
  using (kernel.is_platform(array['platform_admin','platform_support','platform_risk']));

drop policy if exists kernel_org_invite_sel_invitee on kernel.org_invite;
create policy kernel_org_invite_sel_invitee
  on kernel.org_invite for select to authenticated
  using (invitee_identity_id = auth.uid());

drop policy if exists kernel_org_invite_sel_org on kernel.org_invite;
create policy kernel_org_invite_sel_org
  on kernel.org_invite for select to authenticated
  using (kernel.has_org_role(org_id, array['org_owner','org_admin']));

drop policy if exists kernel_platform_role_sel_platform on kernel.platform_role;
create policy kernel_platform_role_sel_platform
  on kernel.platform_role for select to authenticated
  using (kernel.is_platform(array['platform_admin']));

-- =============================================================================
-- PART 4 — DEMOGRAPHICS (DEMOG §10.4, RPC §17.20/§17.20a)
-- =============================================================================

-- §17.20a: the single tombstone writer — BEFORE DELETE, append-many, value-free.
-- Body references NO gender column (DEMOG §13 assertion 25).
create or replace function kernel.write_demographic_erasure_tombstone()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_window_days integer;
  v_purge_after timestamptz;
begin
  -- OR-16 formula: erased_at + documented backup window + 30 days margin,
  -- carried by catalog.platform_config key 'retention.backup_window_days'
  -- (078 seed, ABSENT-BY-DESIGN). F-8 guarded read: relation/key/value absent
  -- or unreadable (incl. 42P01 pre-078) => purge_after NULL = never-purgeable
  -- failsafe. Never a raise on the deletion path.
  begin
    execute 'select nullif(trim(value::text, ''"''), '''')::int
               from catalog.platform_config where key = $1'
      into v_window_days
      using 'retention.backup_window_days';
  exception when others then
    v_window_days := null;
  end;
  if v_window_days is not null then
    v_purge_after := now() + make_interval(days => v_window_days) + interval '30 days';
  else
    v_purge_after := null;
  end if;

  insert into kernel.identity_demographic_erasure (identity_id, erased_at, purge_after)
  values (old.identity_id, now(), v_purge_after);
  return old;
end;
$$;

revoke execute on function kernel.write_demographic_erasure_tombstone() from public, anon, authenticated;

drop trigger if exists tg_identity_demographic_erasure on kernel.identity_demographic;
create trigger tg_identity_demographic_erasure
  before delete on kernel.identity_demographic
  for each row execute function kernel.write_demographic_erasure_tombstone();

create or replace function kernel.get_my_demographics()
returns table (gender_identity text, notice_version text, updated_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  return query
    select d.gender_identity, d.notice_version, d.updated_at
      from kernel.identity_demographic d
     where d.identity_id = auth.uid();
end;
$$;

create or replace function kernel.set_my_demographics(p_gender_identity text, p_notice_version text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_gender_identity is null
     or p_gender_identity not in ('woman','man','non_binary',
                                  'another_gender_identity','prefer_not_to_say') then
    raise exception 'precondition_failed: invalid gender_identity value';
  end if;
  if p_notice_version is null or length(trim(p_notice_version)) = 0 then
    raise exception 'precondition_failed: notice_version required';
  end if;

  insert into kernel.identity_demographic
         (identity_id, gender_identity, notice_version, first_answered_at, updated_at)
  values (auth.uid(), p_gender_identity, p_notice_version, now(), now())
  on conflict (identity_id) do update
     set gender_identity = excluded.gender_identity,
         notice_version  = excluded.notice_version,
         updated_at      = now();
  -- §8.3: NO audit row of any kind on the fan-side demographic write path.
  return jsonb_build_object('status', 'ok');
end;
$$;

create or replace function kernel.clear_my_demographics()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted integer;
begin
  if auth.uid() is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  -- MD-9: the single GP-2 exception — a definer DELETE of the caller's own row.
  -- The BEFORE DELETE trigger appends the value-free erasure tombstone.
  delete from kernel.identity_demographic where identity_id = auth.uid();
  get diagnostics v_deleted = row_count;
  if v_deleted = 0 then
    return jsonb_build_object('status', 'noop_replay');
  end if;
  return jsonb_build_object('status', 'ok');
end;
$$;

-- =============================================================================
-- PART 5 — CONTACT PREFERENCES (RPC §17.21 — the two 077-resident members of
-- the five; the org-consent trio is 082)
-- =============================================================================

create or replace function kernel.get_my_contact_prefs()
returns table (venue_email_contact text, updated_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  -- GATE-DEFAULT-1: no row resolves to 'allow' — the master switch is a kill
  -- switch, not a consent (CRM §5.3).
  return query
    select coalesce(p.venue_email_contact, 'allow'), p.updated_at
      from (select 1) one
      left join kernel.identity_contact_pref p on p.identity_id = auth.uid();
end;
$$;

create or replace function kernel.set_my_contact_prefs(p_venue_email_contact text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_effective text;
  v_audit_id  uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_venue_email_contact is null
     or p_venue_email_contact not in ('allow','block') then
    raise exception 'precondition_failed: invalid venue_email_contact value';
  end if;
  -- rate-limited per identity (§17.21; production check_rate_limit is
  -- fail-closed per migration 021; numeric bounds implementation-chosen, E-6)
  if not public.check_rate_limit(v_uid, 'set_my_contact_prefs', 30, 3600) then
    raise exception 'policy_violation: rate limit exceeded for contact preference changes';
  end if;

  -- effective current value (no row = 'allow', GATE-DEFAULT-1)
  select coalesce(
           (select p.venue_email_contact from kernel.identity_contact_pref p
             where p.identity_id = v_uid),
           'allow')
    into v_effective;

  if v_effective = p_venue_email_contact then
    -- "A no-op appends no event" — the log records decisions, not retries.
    -- Materialize the current-state row if absent (same effective value).
    insert into kernel.identity_contact_pref (identity_id, venue_email_contact)
    values (v_uid, p_venue_email_contact)
    on conflict (identity_id) do nothing;
    return jsonb_build_object('status', 'noop_replay');
  end if;

  insert into kernel.identity_contact_pref (identity_id, venue_email_contact, updated_at)
  values (v_uid, p_venue_email_contact, now())
  on conflict (identity_id) do update
     set venue_email_contact = excluded.venue_email_contact,
         updated_at          = now();

  -- AUTHZ-CRM1: the event append is the function's contract, same transaction.
  insert into kernel.identity_contact_pref_event (identity_id, venue_email_contact)
  values (v_uid, p_venue_email_contact);

  -- audited (crm_contact.pref_changed) — actor is the data subject.
  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'crm_contact.pref_changed', 'identity', v_uid, 'self_service',
          jsonb_build_object('venue_email_contact', v_effective),
          jsonb_build_object('venue_email_contact', p_venue_email_contact))
  returning id into v_audit_id;

  return jsonb_build_object('status', 'ok');
end;
$$;

-- =============================================================================
-- PART 6 — ORGANIZATION WRITE SURFACE (RPC §2.1–§2.5, §20.1.1/.2/.5–.7)
-- =============================================================================

create or replace function kernel.create_organization(
  p_legal_name text, p_display_name text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid;
  v_org_id uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  -- OR-17 F-6: creating an org makes the caller a sole org_owner by
  -- construction — an instant self-inflicted completion blocker.
  if kernel.is_deletion_pending(v_uid) then
    raise exception 'precondition_failed: deletion_pending — a pending-deletion account cannot acquire new roles or organizations (OR-17 F-6)';
  end if;
  -- dsm §1.3: ERASED is terminal and sits OUTSIDE the pending freeze operand,
  -- yet sessions can outlive erasure while OPEN-7 is unresolved — the
  -- acquisition gate refuses the erased caller too (the E-8 defensive twin;
  -- red-team C blocker 2).
  if exists (select 1 from kernel.identity_ext e
              where e.identity_id = v_uid and e.deletion_state = 'ERASED') then
    raise exception 'precondition_failed: identity is erased — acquisition is forbidden (dsm §1.3)';
  end if;
  if p_legal_name is null or length(trim(p_legal_name)) = 0
     or p_display_name is null or length(trim(p_display_name)) = 0 then
    raise exception 'precondition_failed: names must be non-empty';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  -- E-3: kernel.organization carries no command-key column in the frozen DDL,
  -- so replay dedupe here is non-structural; a duplicate apply yields a second
  -- inert 'applied' row (recorded errata).

  insert into kernel.organization (legal_name, display_name, status, home_region)
  values (trim(p_legal_name), trim(p_display_name), 'applied', 'us-east')
  returning org_id into v_org_id;

  insert into kernel.org_member (org_id, identity_id, role, granted_by, granted_at)
  values (v_org_id, v_uid, 'org_owner', v_uid, now());

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'org.create', 'organization', v_org_id, 'self_service',
          null, jsonb_build_object('status', 'applied'));

  return jsonb_build_object('status', 'ok', 'org_id', v_org_id);
end;
$$;

create or replace function kernel.update_organization(
  p_org_id uuid, p_patch jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid;
  v_key  text;
  v_name text;
  v_old  text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if not kernel.has_org_role(p_org_id, array['org_owner','org_admin']) then
    raise exception 'insufficient_privilege: org_owner or org_admin required'
      using errcode = '42501';
  end if;
  -- §20.1.5: the patch set is closed — writable: display_name ONLY. A key
  -- outside the writable set raises; it is never silently ignored.
  for v_key in select jsonb_object_keys(coalesce(p_patch, '{}'::jsonb)) loop
    if v_key <> 'display_name' then
      raise exception 'invalid_input: unwritable_key % — display_name is the only org self-service field', v_key;
    end if;
  end loop;
  v_name := p_patch->>'display_name';
  if v_name is null or length(trim(v_name)) = 0 then
    raise exception 'precondition_failed: empty_name';
  end if;

  select o.display_name into v_old
    from kernel.organization o where o.org_id = p_org_id for update;
  if not found then
    raise exception 'not_found: organization %', p_org_id;
  end if;
  if v_old = trim(v_name) then
    return jsonb_build_object('status', 'noop_replay', 'org_id', p_org_id);
  end if;

  update kernel.organization
     set display_name = trim(v_name)
   where org_id = p_org_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'org.update', 'organization', p_org_id, 'self_service',
          jsonb_build_object('display_name', v_old),
          jsonb_build_object('display_name', trim(v_name)));

  return jsonb_build_object('status', 'ok', 'org_id', p_org_id);
end;
$$;

create or replace function kernel.set_org_status(
  p_org_id uuid, p_target_status text, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_cur text;
  v_legal boolean;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if not kernel.is_platform(array['platform_admin']) then
    raise exception 'insufficient_privilege: platform_admin required (an org cannot approve itself)'
      using errcode = '42501';
  end if;
  if p_target_status is null
     or p_target_status not in ('applied','approved','active','suspended','closed') then
    raise exception 'precondition_failed: illegal_transition — unknown status %', p_target_status;
  end if;

  select o.status into v_cur
    from kernel.organization o where o.org_id = p_org_id for update;
  if not found then
    raise exception 'not_found: organization %', p_org_id;
  end if;

  if v_cur = p_target_status then
    return jsonb_build_object('status', 'noop_replay', 'org_id', p_org_id, 'org_status', v_cur);
  end if;
  if v_cur = 'closed' then
    raise exception 'precondition_failed: terminal_state — closed is terminal; re-opening is a new org';
  end if;

  -- legal transitions (§20.1.2): applied→approved→active;
  -- {approved,active}→suspended; suspended→active; any(non-closed)→closed.
  v_legal := (v_cur = 'applied'   and p_target_status = 'approved')
          or (v_cur = 'approved'  and p_target_status in ('active','suspended'))
          or (v_cur = 'active'    and p_target_status = 'suspended')
          or (v_cur = 'suspended' and p_target_status = 'active')
          or (p_target_status = 'closed');
  if not v_legal then
    raise exception 'precondition_failed: illegal_transition — % -> %', v_cur, p_target_status;
  end if;
  -- reason mandatory on every non-forward transition
  if p_target_status in ('suspended','closed')
     and (p_reason_code is null or length(trim(p_reason_code)) = 0) then
    raise exception 'precondition_failed: reason_required';
  end if;

  update kernel.organization set status = p_target_status where org_id = p_org_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'org.status.change', 'organization', p_org_id,
          coalesce(nullif(trim(p_reason_code), ''), 'forward_transition'),
          jsonb_build_object('status', v_cur),
          jsonb_build_object('status', p_target_status));

  return jsonb_build_object('status', 'ok', 'org_id', p_org_id, 'org_status', p_target_status);
end;
$$;

create or replace function kernel.set_org_connect_ref(
  p_org_id uuid, p_connect_account_id text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid;
  v_ref    text;
  v_status text;
begin
  -- §20.1.1 / §0.1a: EDGE-CALLER-JWT bound — a service-role invocation has
  -- auth.uid() NULL and must RAISE rather than bind (T-RPC-CONNECT-04).
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: caller JWT required — connect-onboarding must use the caller''s Authorization header'
      using errcode = '42501';
  end if;
  if not kernel.has_org_role(p_org_id, array['org_owner','org_finance']) then
    raise exception 'insufficient_privilege: org_owner or org_finance required'
      using errcode = '42501';
  end if;
  if p_connect_account_id is null or p_connect_account_id !~ '^acct_[A-Za-z0-9]+$' then
    raise exception 'precondition_failed: malformed_account_ref';
  end if;

  select o.stripe_connect_account_ref, o.status into v_ref, v_status
    from kernel.organization o where o.org_id = p_org_id for update;
  if not found then
    raise exception 'not_found: organization %', p_org_id;
  end if;
  if v_status not in ('applied','approved','active') then
    raise exception 'precondition_failed: org_not_bindable — a % org may not bind a payee', v_status;
  end if;

  if v_ref is not null and v_ref = p_connect_account_id then
    -- the "reuse existing connect ids" re-onboarding retry path
    return jsonb_build_object('status', 'noop_replay', 'org_id', p_org_id,
                              'connect_account_id', v_ref, 'newly_bound', false);
  end if;
  if v_ref is not null then
    -- BIND-ONCE: a re-point is never an onboarding event; the only path is
    -- kernel.set_org_payout_destination (§17.7, a later package).
    raise exception 'precondition_failed: destination_already_set — re-pointing rides kernel.set_org_payout_destination only';
  end if;

  begin
    update kernel.organization
       set stripe_connect_account_ref = p_connect_account_id,
           -- SoD-1 applies from the very first destination
           payout_destination_set_by  = v_uid
     where org_id = p_org_id;
  exception when unique_violation then
    raise exception 'conflict_locked: connect account already bound to another org';
  end;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'org.connect_ref.bind', 'organization', p_org_id, 'onboarding',
          null, jsonb_build_object('connect_account_id', p_connect_account_id));

  return jsonb_build_object('status', 'ok', 'org_id', p_org_id,
                            'connect_account_id', p_connect_account_id, 'newly_bound', true);
end;
$$;

create or replace function kernel.invite_org_member(
  p_org_id uuid, p_invitee_ref text, p_role text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_invite_id uuid;
  v_invitee   uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if not kernel.has_org_role(p_org_id, array['org_owner','org_admin']) then
    raise exception 'insufficient_privilege: org_owner or org_admin required'
      using errcode = '42501';
  end if;
  if p_role is null or p_role not in ('org_owner','org_admin','org_finance',
                                      'org_marketing','org_promoter_manager','org_member') then
    raise exception 'precondition_failed: bad tier — role must be an org-plane label';
  end if;
  -- tier guard: an org_admin cannot invite at org_owner
  if p_role = 'org_owner' and not kernel.has_org_role(p_org_id, array['org_owner']) then
    raise exception 'precondition_failed: bad tier — only an org_owner may invite at org_owner';
  end if;
  if p_invitee_ref is null or length(trim(p_invitee_ref)) = 0 then
    raise exception 'precondition_failed: invitee_ref required';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  -- I-11: no self-invite to a higher tier (checkable only for a uuid-form ref)
  if p_invitee_ref = v_uid::text and p_role in ('org_owner','org_admin')
     and not kernel.has_org_role(p_org_id, array['org_owner']) then
    raise exception 'precondition_failed: self_invite — no self-invite to a higher tier (I-11)';
  end if;

  -- serialize roster changes on the org row
  perform 1 from kernel.organization o where o.org_id = p_org_id for update;
  if not found then
    raise exception 'not_found: organization %', p_org_id;
  end if;

  -- C16 replay: same (org_id, command_idempotency_key) returns the original
  begin
    v_invitee := case when p_invitee_ref ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                      then p_invitee_ref::uuid end;
    insert into kernel.org_invite
           (org_id, invitee_ref, invitee_identity_id, role, status, invited_by,
            expires_at, command_idempotency_key)
    values (p_org_id, trim(p_invitee_ref), v_invitee, p_role, 'pending', v_uid,
            now() + interval '14 days', p_command_key)
    returning invite_id into v_invite_id;
  exception when unique_violation then
    select i.invite_id into v_invite_id
      from kernel.org_invite i
     where i.org_id = p_org_id and i.command_idempotency_key = p_command_key;
    if v_invite_id is not null then
      return jsonb_build_object('status', 'noop_replay', 'invite_id', v_invite_id);
    end if;
    -- the partial unique: one open invite per invitee per org
    raise exception 'precondition_failed: an open invite already exists for % in this org', p_invitee_ref;
  end;

  -- AUTHZ-C1B legibility: the audit row records the money-role class.
  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'org.invite', 'org_invite', v_invite_id,
          case when p_role in ('org_owner','org_finance') then 'money_role_invite' else 'invite' end,
          null, jsonb_build_object('org_id', p_org_id, 'role', p_role));

  return jsonb_build_object('status', 'ok', 'invite_id', v_invite_id);
end;
$$;

create or replace function kernel.accept_org_invite(p_invite_id uuid, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_inv record;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  -- OR-17 F-6: an accepted invite creates org_member obligations and can mint
  -- a new BP-11.
  if kernel.is_deletion_pending(v_uid) then
    raise exception 'precondition_failed: deletion_pending — a pending-deletion account cannot acquire new roles or organizations (OR-17 F-6)';
  end if;
  -- dsm §1.3 ERASED acquisition refusal — the E-8 defensive twin (red-team C).
  if exists (select 1 from kernel.identity_ext e
              where e.identity_id = v_uid and e.deletion_state = 'ERASED') then
    raise exception 'precondition_failed: identity is erased — acquisition is forbidden (dsm §1.3)';
  end if;

  select * into v_inv from kernel.org_invite where invite_id = p_invite_id for update;
  if not found then
    raise exception 'not_found: invite %', p_invite_id;
  end if;
  if v_inv.status = 'accepted' then
    return jsonb_build_object('status', 'noop_replay', 'org_id', v_inv.org_id, 'role', v_inv.role);
  end if;
  if v_inv.status <> 'pending' then
    raise exception 'precondition_failed: invite is % — only a pending invite can be accepted', v_inv.status;
  end if;
  if v_inv.expires_at <= now() then
    raise exception 'precondition_failed: invite expired';
  end if;
  -- authority = being the addressed invitee (RLS §7.3b)
  if not (v_inv.invitee_identity_id = v_uid
          or (v_inv.invitee_identity_id is null
              and exists (select 1 from auth.users u
                           where u.id = v_uid
                             and lower(u.email) = lower(v_inv.invitee_ref)))) then
    raise exception 'insufficient_privilege: not the addressed invitee'
      using errcode = '42501';
  end if;

  -- serialize the roster on the org row
  perform 1 from kernel.organization o where o.org_id = v_inv.org_id for update;

  -- granted_at is the maturity clock and is set HERE, not at invite (AUTHZ-C1B)
  insert into kernel.org_member (org_id, identity_id, role, granted_by, granted_at)
  values (v_inv.org_id, v_uid, v_inv.role, v_inv.invited_by, now())
  on conflict (org_id, identity_id) do update
     set role       = excluded.role,
         granted_by = excluded.granted_by,
         granted_at = now();

  update kernel.org_invite
     set status = 'accepted', invitee_identity_id = v_uid
   where invite_id = p_invite_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'org.invite.accept', 'org_invite', p_invite_id, 'invite_accept',
          null, jsonb_build_object('org_id', v_inv.org_id, 'role', v_inv.role));

  return jsonb_build_object('status', 'ok', 'org_id', v_inv.org_id, 'role', v_inv.role);
end;
$$;

create or replace function kernel.change_org_role(
  p_org_id uuid, p_identity_id uuid, p_new_role text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_old_role  text;
  v_owners    integer;
  v_audit_id  uuid;
  v_sensitive constant text[] := array['org_owner','org_admin','org_finance'];
  v_money     constant text[] := array['org_owner','org_finance'];
  v_tier_old  integer;
  v_tier_new  integer;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if not kernel.has_org_role(p_org_id, array['org_owner','org_admin']) then
    raise exception 'insufficient_privilege: org_owner or org_admin required'
      using errcode = '42501';
  end if;
  if p_new_role is null or p_new_role not in ('org_owner','org_admin','org_finance',
                                              'org_marketing','org_promoter_manager','org_member') then
    raise exception 'precondition_failed: bad tier — role must be an org-plane label';
  end if;
  -- an org_admin cannot set anyone to org_owner
  if p_new_role = 'org_owner' and not kernel.has_org_role(p_org_id, array['org_owner']) then
    raise exception 'precondition_failed: bad tier — only an org_owner may grant org_owner';
  end if;

  -- serialize the roster; re-count owners under the lock
  perform 1 from kernel.organization o where o.org_id = p_org_id for update;
  if not found then
    raise exception 'not_found: organization %', p_org_id;
  end if;

  select m.role into v_old_role
    from kernel.org_member m
   where m.org_id = p_org_id and m.identity_id = p_identity_id
   for update;
  if not found then
    raise exception 'precondition_failed: target is not a member of this org';
  end if;
  if v_old_role = p_new_role then
    return jsonb_build_object('status', 'noop_replay');
  end if;

  -- I-11: no self-promotion. Tier is the AUTHORITY ladder (owner > admin >
  -- the rest); an org_admin self-assigning org_finance is a tier-DEMOTION and
  -- passes — that is the ratified design, not a gap: money-role acquisition
  -- is priced by the granted_at maturity floor (AUTHZ-C1B, reset below) plus
  -- SoD, never by tier prohibition ("inviting at a money role is permitted
  -- and unchanged — the grant simply starts immature", §2.2).
  v_tier_old := case v_old_role when 'org_owner' then 3 when 'org_admin' then 2 else 1 end;
  v_tier_new := case p_new_role when 'org_owner' then 3 when 'org_admin' then 2 else 1 end;
  if p_identity_id = v_uid and v_tier_new > v_tier_old then
    raise exception 'precondition_failed: self_promotion is not permitted (I-11)';
  end if;
  -- an org_admin cannot change an org_owner's role (tier)
  if v_old_role = 'org_owner' and not kernel.has_org_role(p_org_id, array['org_owner']) then
    raise exception 'precondition_failed: bad tier — only an org_owner may change an org_owner';
  end if;
  -- the ">=1 org_owner" invariant: cannot demote the last owner
  if v_old_role = 'org_owner' and p_new_role <> 'org_owner' then
    select count(*) into v_owners
      from kernel.org_member m
     where m.org_id = p_org_id and m.role = 'org_owner' and m.identity_id <> p_identity_id;
    if v_owners = 0 then
      raise exception 'precondition_failed: last-owner — cannot demote the last org_owner';
    end if;
  end if;

  update kernel.org_member m
     set role       = p_new_role,
         granted_by = v_uid,
         -- AUTHZ-C1B: the clock resets on promotion INTO a money role, and
         -- only then — a lateral/demotion move acquires nothing.
         granted_at = case when p_new_role = any(v_money) and not (v_old_role = any(v_money))
                           then now() else m.granted_at end
   where m.org_id = p_org_id and m.identity_id = p_identity_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'org.role.change', 'org_member', p_identity_id,
          case when p_new_role = any(v_money) then 'money_role_change' else 'role_change' end,
          jsonb_build_object('org_id', p_org_id, 'role', v_old_role),
          jsonb_build_object('org_id', p_org_id, 'role', p_new_role))
  returning id into v_audit_id;

  -- R2 row 22 (BEST-EFFORT): only SENSITIVE role changes notify (NOTIF Group S)
  begin
    if p_new_role = any(v_sensitive) then
      perform notify.emit_event(
        'security_org_role_granted', 'identity', p_identity_id,
        'security_role_grant:' || v_audit_id::text,
        jsonb_build_object('org_id', p_org_id, 'role_label', p_new_role,
                           'actor_identity', v_uid));
    elsif v_old_role = any(v_sensitive) then
      perform notify.emit_event(
        'security_org_role_revoked', 'identity', p_identity_id,
        'security_role_revoke:' || v_audit_id::text,
        jsonb_build_object('org_id', p_org_id, 'role_label', v_old_role,
                           'actor_identity', v_uid));
    end if;
  exception when others then
    -- N-A30 (BE producers): the grant/revoke and the maturity control never
    -- read the envelope; a failed emit warns and the transaction commits.
    raise warning 'change_org_role: best-effort security notice emit failed: %', sqlerrm;
  end;

  return jsonb_build_object('status', 'ok');
end;
$$;

create or replace function kernel.remove_org_member(
  p_org_id uuid, p_identity_id uuid, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid;
  v_old_role text;
  v_owners   integer;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if not kernel.has_org_role(p_org_id, array['org_owner','org_admin']) then
    raise exception 'insufficient_privilege: org_owner or org_admin required'
      using errcode = '42501';
  end if;

  perform 1 from kernel.organization o where o.org_id = p_org_id for update;
  if not found then
    raise exception 'not_found: organization %', p_org_id;
  end if;

  select m.role into v_old_role
    from kernel.org_member m
   where m.org_id = p_org_id and m.identity_id = p_identity_id
   for update;
  if not found then
    -- removal is idempotent
    return jsonb_build_object('status', 'noop_replay');
  end if;
  -- cannot remove a higher tier than caller
  if v_old_role = 'org_owner' and not kernel.has_org_role(p_org_id, array['org_owner']) then
    raise exception 'precondition_failed: bad tier — only an org_owner may remove an org_owner';
  end if;
  if v_old_role = 'org_owner' then
    select count(*) into v_owners
      from kernel.org_member m
     where m.org_id = p_org_id and m.role = 'org_owner' and m.identity_id <> p_identity_id;
    if v_owners = 0 then
      raise exception 'precondition_failed: last-owner — cannot remove the last org_owner';
    end if;
  end if;

  -- role-remove via RPC, never a client DELETE (GP-2 is satisfied because the
  -- audit row carries the removed grant — the §20.1.4 construction).
  delete from kernel.org_member m
   where m.org_id = p_org_id and m.identity_id = p_identity_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'org.member.remove', 'org_member', p_identity_id, 'member_remove',
          jsonb_build_object('org_id', p_org_id, 'role', v_old_role), null);

  return jsonb_build_object('status', 'ok');
end;
$$;

create or replace function kernel.revoke_org_invite(p_invite_id uuid, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_inv record;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;

  select * into v_inv from kernel.org_invite where invite_id = p_invite_id for update;
  if not found then
    raise exception 'not_found: invite %', p_invite_id;
  end if;
  -- AUTHZ-C1C: org_id is read from the invite row under its lock, never a parameter
  if not (kernel.has_org_role(v_inv.org_id, array['org_owner','org_admin'])
          or kernel.is_platform(array['platform_admin'])) then
    raise exception 'insufficient_privilege: inviter tier or platform_admin required'
      using errcode = '42501';
  end if;
  -- tier guard: an org_admin may not revoke an org_owner-tier invite
  if v_inv.role = 'org_owner'
     and not (kernel.has_org_role(v_inv.org_id, array['org_owner'])
              or kernel.is_platform(array['platform_admin'])) then
    raise exception 'precondition_failed: tier — only an org_owner (or platform) may revoke an org_owner-tier invite';
  end if;
  if v_inv.status = 'revoked' then
    return jsonb_build_object('status', 'noop_replay');
  end if;
  if v_inv.status <> 'pending' then
    -- an accepted invite is membership; membership is removed only by
    -- kernel.remove_org_member (the ">=1 org_owner" invariant lives there)
    raise exception 'precondition_failed: invite_not_pending';
  end if;

  update kernel.org_invite set status = 'revoked' where invite_id = p_invite_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'org.invite.revoke', 'org_invite', p_invite_id,
          case when v_inv.role in ('org_owner','org_finance') then 'money_role_invite_revoke' else 'invite_revoke' end,
          jsonb_build_object('org_id', v_inv.org_id, 'role', v_inv.role, 'status', v_inv.status),
          jsonb_build_object('status', 'revoked'));

  return jsonb_build_object('status', 'ok');
end;
$$;

create or replace function kernel.sweep_expired_org_invites(p_limit int default 500)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_swept integer := 0;
  v_row   record;
begin
  -- EXEC: DEF — scheduler only; auth.uid() NULL by construction. The sweep is
  -- never the enforcement (accept refuses on the row arithmetic regardless);
  -- the tick makes the stored label agree AND releases the partial unique.
  for v_row in
    select i.invite_id
      from kernel.org_invite i
     where i.status = 'pending' and i.expires_at < now()
     order by i.expires_at
     limit p_limit
     for update skip locked
  loop
    begin
      update kernel.org_invite set status = 'expired' where invite_id = v_row.invite_id;
      v_swept := v_swept + 1;
    exception when others then
      -- poison-quarantine (§20.3.3): one bad row never stops the tick
      raise warning 'sweep_expired_org_invites: invite % failed: %', v_row.invite_id, sqlerrm;
    end;
  end loop;
  -- No audit rows — a TTL lapse is not an administrative action (§12.2).
  return jsonb_build_object('swept', v_swept);
end;
$$;

-- =============================================================================
-- PART 7 — IDENTITY EXTENSION WRITERS (RPC §20.1.3 — the contracted split pair)
-- =============================================================================

create or replace function kernel.upsert_identity_ext(p_patch jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid;
  v_key    text;
  v_locale text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  -- self branch: writes ONLY locale on its own row; no identity parameter
  -- exists on this branch, so "edit someone else's row" is unexpressible.
  for v_key in select jsonb_object_keys(coalesce(p_patch, '{}'::jsonb)) loop
    if v_key <> 'locale' then
      raise exception 'invalid_input: unwritable_key % — the self branch writes locale only (region/kyc ride kernel.admin_set_identity_ext)', v_key;
    end if;
  end loop;
  v_locale := p_patch->>'locale';
  -- NULL is meaningful ("not stated"); otherwise a well-formed BCP-47 tag
  if v_locale is not null and v_locale !~ '^[A-Za-z]{2,3}(-[A-Za-z0-9]{1,8})*$' then
    raise exception 'precondition_failed: bad_locale';
  end if;

  insert into kernel.identity_ext (identity_id, locale)
  values (v_uid, v_locale)
  on conflict (identity_id) do update set locale = excluded.locale;

  -- a fan setting their own locale is not a privileged mutation (§0.3 does not reach it)
  return jsonb_build_object('status', 'ok', 'identity_id', v_uid);
end;
$$;

create or replace function kernel.admin_set_identity_ext(
  p_identity_id uuid, p_patch jsonb, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid;
  v_key    text;
  v_region text;
  v_kyc    text;
  v_before jsonb := '{}'::jsonb;
  v_after  jsonb := '{}'::jsonb;
  v_row    record;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if not kernel.is_platform(array['platform_admin']) then
    raise exception 'insufficient_privilege: platform_admin required'
      using errcode = '42501';
  end if;
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: reason_required';
  end if;
  for v_key in select jsonb_object_keys(coalesce(p_patch, '{}'::jsonb)) loop
    if v_key not in ('residency_region','kyc_ref') then
      raise exception 'invalid_input: unwritable_key % — the platform branch writes residency_region/kyc_ref only', v_key;
    end if;
  end loop;

  insert into kernel.identity_ext (identity_id) values (p_identity_id)
  on conflict (identity_id) do nothing;

  select * into v_row from kernel.identity_ext where identity_id = p_identity_id for update;

  if p_patch ? 'residency_region' then
    v_region := p_patch->>'residency_region';
    if v_region is null or v_region <> 'us-east' then
      raise exception 'precondition_failed: bad_region — allowed set is (us-east) in MVP (C14)';
    end if;
    v_before := v_before || jsonb_build_object('residency_region', v_row.residency_region);
    v_after  := v_after  || jsonb_build_object('residency_region', v_region);
    update kernel.identity_ext set residency_region = v_region
     where identity_id = p_identity_id;
  end if;
  if p_patch ? 'kyc_ref' then
    v_kyc := p_patch->>'kyc_ref';
    -- the audit row records THAT it changed, never its value (§20.1.3)
    v_before := v_before || jsonb_build_object('kyc_ref', case when v_row.kyc_ref is null then '(unset)' else '(set)' end);
    v_after  := v_after  || jsonb_build_object('kyc_ref', case when v_kyc is null then '(cleared)' else '(changed)' end);
    update kernel.identity_ext set kyc_ref = v_kyc
     where identity_id = p_identity_id;
  end if;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'identity_ext.update', 'identity', p_identity_id,
          trim(p_reason_code), v_before, v_after);

  return jsonb_build_object('status', 'ok', 'identity_id', p_identity_id);
end;
$$;

-- =============================================================================
-- PART 8 — PLATFORM ROLES (RPC §20.1.4; PFA-4 posture on the grant arm)
-- =============================================================================

create or replace function kernel.grant_platform_role(
  p_identity_id uuid, p_role text, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if not kernel.is_platform(array['platform_admin']) then
    raise exception 'insufficient_privilege: platform_admin (or the admin_users bootstrap) required'
      using errcode = '42501';
  end if;
  -- C36: the platform enum only, re-validated in-body; org/venue labels raise
  -- (T-RPC-ROLE-09).
  if p_role is null or p_role not in ('platform_admin','platform_support','platform_risk') then
    raise exception 'precondition_failed: bad_role — % is not a platform-plane label', coalesce(p_role, '(null)');
  end if;
  -- I-11: no self-grant.
  if p_identity_id = v_uid then
    raise exception 'precondition_failed: self_grant';
  end if;

  -- ==========================================================================
  -- PFA-4 (OWNER SIGNATURE REQUIRED — filed in POST_FREEZE_AMENDMENTS.md).
  -- §20.1.4 contracts this grant as parking a kernel.approval_request row
  -- (action='platform_role.grant') for a second distinct platform_admin. That
  -- row is IMPOSSIBLE against the frozen table: the action CHECK admits
  -- exactly three labels, the action↔subject pairing CHECK has no
  -- platform_role arm, T-RPC-AUTHZ-15 pins the INSERT writer set to exactly
  -- {request_order_refund, request_org_payout, set_platform_config}, and no
  -- approver verb exists before 085. Until the owner signs a resolution the
  -- grant arm FAILS CLOSED: no platform_role row can be minted by anyone,
  -- which preserves the dual-control purpose (C11) maximally. The
  -- public.admin_users bootstrap remains the platform_admin authority.
  -- ==========================================================================
  raise exception 'precondition_failed: dual_control_unavailable — platform-role grants are fail-closed pending owner signature on PFA-4 (see docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md)';
end;
$$;

create or replace function kernel.revoke_platform_role(
  p_identity_id uuid, p_role text, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_remaining integer;
  v_removed   integer;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if not kernel.is_platform(array['platform_admin']) then
    raise exception 'insufficient_privilege: platform_admin required'
      using errcode = '42501';
  end if;
  if p_role is null or p_role not in ('platform_admin','platform_support','platform_risk') then
    raise exception 'precondition_failed: bad_role — % is not a platform-plane label', coalesce(p_role, '(null)');
  end if;
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: reason_required';
  end if;

  -- lock the target's rows, then re-count under the lock (§20.1.4)
  perform 1 from kernel.platform_role r
    where r.identity_id = p_identity_id for update;

  -- no last-admin revoke: count kernel.platform_role UNION public.admin_users
  if p_role = 'platform_admin' then
    select count(*) into v_remaining from (
      select r.identity_id from kernel.platform_role r
       where r.role = 'platform_admin' and r.identity_id <> p_identity_id
      union
      select a.user_id from public.admin_users a
       where a.user_id <> p_identity_id
    ) s;
    if v_remaining = 0 then
      raise exception 'precondition_failed: last_platform_admin';
    end if;
  end if;

  delete from kernel.platform_role r
   where r.identity_id = p_identity_id and r.role = p_role;
  get diagnostics v_removed = row_count;
  if v_removed = 0 then
    return jsonb_build_object('status', 'noop_replay', 'identity_id', p_identity_id, 'role', p_role);
  end if;

  -- revocation executes directly; only a grant needs the second approver
  -- (§20.1.4 direction asymmetry). GP-2 satisfied: the audit row carries the
  -- removed grant.
  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'platform_role.revoke', 'identity', p_identity_id, trim(p_reason_code),
          jsonb_build_object('role', p_role), null);

  return jsonb_build_object('status', 'ok', 'identity_id', p_identity_id, 'role', p_role);
end;
$$;

-- =============================================================================
-- PART 9 — THE DELETION STATE MACHINE (RPC §20.17; dsm-spec OR-13; OR-17)
-- =============================================================================

-- 9.1 kernel.is_deletion_pending — the single freeze operand (§20.17.3).
-- PFA-5: VOLATILE, not STABLE — PostgreSQL forbids FOR SHARE in a non-volatile
-- function, and the F-11 serialization lock is the ratified, load-bearing half
-- of the contract: an F-clause host holds FOR SHARE on the caller's
-- identity_ext row (taken here) so an acquisition that read ACTIVE commits
-- before the sweep's FOR UPDATE terminal arm can begin.
create or replace function kernel.is_deletion_pending(p_identity uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_state text;
begin
  if p_identity is null then
    return false;
  end if;
  -- F-11 (§20.17.3): the predicate itself takes the serialization lock — an
  -- F-clause host that read ACTIVE holds this row until it commits, so the
  -- sweep's FOR UPDATE terminal arm cannot begin underneath it and the new
  -- matter is seen by the re-evaluation. "The lazy-create path takes the
  -- insert lock": when no row exists yet, the predicate materializes the lazy
  -- identity_ext row (ACTIVE) — the inserted row is exclusively locked by
  -- this transaction, which closes the row-less three-transaction interleave
  -- (a concurrent request_account_deletion blocks until the acquisition
  -- commits).
  insert into kernel.identity_ext (identity_id) values (p_identity)
  on conflict (identity_id) do nothing;
  select e.deletion_state into v_state
    from kernel.identity_ext e
   where e.identity_id = p_identity
   for share;
  return coalesce(v_state, '') = 'DELETION_PENDING';
end;
$$;

-- 9.2 The ELEVEN SEAM-2 stubs (§20.17.5 — signatures frozen verbatim, SEAM-2a:
-- parameter list, parameter NAMES and return type may never change; the
-- replacing package CREATE OR REPLACEs ONLY the body and asserts COUNT(*)=1
-- over pg_proc for the name. Each neutral result is the TRUE value over an
-- empty world — the operand table does not exist before the replacing package.)

create or replace function kernel.deletion_blockers_custody(p_identity uuid)
returns text language sql volatile security definer set search_path = ''
as $$ select null::text $$;   -- BP-1; real body 079 (kernel.tickets)

create or replace function kernel.deletion_blockers_orders(p_identity uuid)
returns text language sql volatile security definer set search_path = ''
as $$ select null::text $$;   -- BP-12 pending-order arm; real body 082

create or replace function kernel.deletion_blockers_wallet(p_identity uuid)
returns text language sql volatile security definer set search_path = ''
as $$ select null::text $$;   -- BP-2; real body 083 (kernel.wallet_pass)

create or replace function kernel.deletion_blockers_money(p_identity uuid)
returns text language sql volatile security definer set search_path = ''
as $$ select null::text $$;   -- BP-5 + BP-6 kernel arm + BP-12 refund/window arm; 085

create or replace function kernel.deletion_blockers_market(p_identity uuid)
returns text language sql volatile security definer set search_path = ''
as $$ select null::text $$;   -- BP-3 + BP-4 + BP-7/BP-8 native twins; 088

create or replace function kernel.on_identity_erased_staff(p_identity uuid)
returns void language sql volatile security definer set search_path = ''
as $$ select $$;              -- INV #23/#24; real body 080

create or replace function kernel.on_identity_erased_door(p_identity uuid)
returns void language sql volatile security definer set search_path = ''
as $$ select $$;              -- INV #29-#31; real body 086

create or replace function kernel.on_identity_erased_market(p_identity uuid)
returns void language sql volatile security definer set search_path = ''
as $$ select $$;              -- 16d hard-delete allowance ONLY; real body 088

create or replace function kernel.on_identity_erased_promoter(p_identity uuid)
returns void language sql volatile security definer set search_path = ''
as $$ select $$;              -- INV #36; venue.promoter row SURVIVES; 090

create or replace function kernel.has_outstanding_obligations(p_identity_id uuid)
returns boolean language sql volatile security definer set search_path = ''
as $$ select false $$;        -- BP-10 (OR-21); true-not-inert; real body 085

create or replace function kernel.on_deletion_q5_release(p_identity uuid)
returns void language sql volatile security definer set search_path = ''
as $$ select $$;              -- Q5 release side-effects (§17.4); real body 085

-- 9.3 kernel.request_account_deletion (§20.17.1 — ALWAYS ACCEPTS)
create or replace function kernel.request_account_deletion(p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid;
  v_state text;
  v_at    timestamptz;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;

  -- lazy identity_ext create (plan §0.5: no backfill; the insert lock is the
  -- lazy-create path's serialization, F-11)
  insert into kernel.identity_ext (identity_id) values (v_uid)
  on conflict (identity_id) do nothing;

  select e.deletion_state, e.deletion_requested_at into v_state, v_at
    from kernel.identity_ext e where e.identity_id = v_uid for update;

  if v_state = 'DELETION_PENDING' then
    -- re-request while pending -> noop_replay (the timestamp is NOT rewritten)
    return jsonb_build_object('status', 'noop_replay',
                              'deletion_state', 'DELETION_PENDING',
                              'deletion_requested_at', v_at);
  end if;
  if v_state = 'ERASED' then
    -- contract: unreachable (no session exists). Defensive fail-closed while
    -- OPEN-7 (credential revocation) is unresolved — errata E-8.
    raise exception 'precondition_failed: identity is erased';
  end if;

  v_at := now();
  update kernel.identity_ext
     set deletion_state        = 'DELETION_PENDING',
         deletion_requested_at = v_at,
         deletion_block_reason = null
   where identity_id = v_uid;

  -- Q5 (16c, OR-13 §3.1.2): auto-expire pending approvals naming the deleter.
  -- "Naming" resolves to requested_by only (a pending row has approved_by NULL
  -- by CHECK). Decided rows are immutable — only pending is touched.
  update kernel.approval_request
     set state = 'expired'
   where requested_by = v_uid and state = 'pending';

  -- Q5 release side-effects ride the SEAM-2 hook (no-op until 085 — F-2)
  perform kernel.on_deletion_q5_release(v_uid);

  -- BE-emit account_deletion_pending (OR-14, R2 row 31) — same-txn, LAST write
  begin
    perform notify.emit_event(
      'account_deletion_pending', 'identity', v_uid,
      'account_deletion_pending:' || v_uid::text || ':' || v_at::text,
      jsonb_build_object('deletion_requested_at', v_at,
                         'deletion_block_reason', null));
  exception when others then
    raise warning 'request_account_deletion: best-effort notice emit failed: %', sqlerrm;
  end;

  return jsonb_build_object('status', 'ok',
                            'deletion_state', 'DELETION_PENDING',
                            'deletion_requested_at', v_at);
end;
$$;

-- 9.4 kernel.withdraw_account_deletion (§20.17.2)
create or replace function kernel.withdraw_account_deletion(p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid;
  v_state text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;

  select e.deletion_state into v_state
    from kernel.identity_ext e where e.identity_id = v_uid for update;

  if not found or v_state = 'ACTIVE' then
    return jsonb_build_object('status', 'noop_replay', 'deletion_state', 'ACTIVE');
  end if;
  if v_state = 'ERASED' then
    -- ERASED is terminal: no exit to ACTIVE exists in Phase 2 (dsm §1.3).
    raise exception 'precondition_failed: identity is erased — no resurrection path exists';
  end if;

  update kernel.identity_ext
     set deletion_state        = 'ACTIVE',
         deletion_requested_at = null,
         deletion_block_reason = null
   where identity_id = v_uid;

  -- Expired Q5 approvals are NOT resurrected (§3.1.2: expiry is a release).
  return jsonb_build_object('status', 'ok', 'deletion_state', 'ACTIVE');
end;
$$;

-- 9.5 kernel.sweep_deletion_pending (§20.17.4 — cron definer, the half-
-- completion detector; terminal entry idempotent)
create or replace function kernel.sweep_deletion_pending(p_limit int default 100)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row        record;
  v_reason     text;
  v_swept      integer := 0;
  v_blocked    integer := 0;
  v_tombstoned integer := 0;
begin
  for v_row in
    select e.identity_id, e.deletion_requested_at
      from kernel.identity_ext e
     where e.deletion_state = 'DELETION_PENDING'
     limit p_limit
     for update skip locked   -- SKIP LOCKED over the pending partial index;
                              -- FOR UPDATE is the F-11 terminal-entry lock
  loop
    begin
      v_swept := v_swept + 1;

      -- BP-1..BP-12 in order (dsm §2; routing per §20.17.4 + hooks §20.17.5).
      -- First true predicate is recorded; the pass moves on.
      v_reason := coalesce(
        -- BP-1 live custody (hook; kernel.tickets is 079)
        kernel.deletion_blockers_custody(v_row.identity_id),
        -- BP-2 live wallet pass (hook; 083)
        kernel.deletion_blockers_wallet(v_row.identity_id),
        -- BP-3/BP-4 (+ BP-7/BP-8 native twins from 088) (hook)
        kernel.deletion_blockers_market(v_row.identity_id),
        -- BP-5 (+ BP-6 kernel arm, BP-12 refund/window arm from 085) (hook)
        kernel.deletion_blockers_money(v_row.identity_id),
        -- BP-6 live arm: unresolved payout hold/probation on the live rail
        (select 'BP-6: unresolved payout hold/probation on a live transfer — resolves via review resolution or hold lapse'
          where exists (select 1 from public.transfers t
                         where t.seller_id = v_row.identity_id
                           and (t.payout_review_status in ('held','manual_review')
                                or t.payout_hold_until > now()))),
        -- BP-7 live arm: open or disputed transfer (incl. expired-in-dispute)
        (select 'BP-7: an open or disputed live transfer must reach a terminal state first'
          where exists (select 1 from public.transfers t
                         where (t.seller_id = v_row.identity_id or t.buyer_id = v_row.identity_id)
                           and (t.status in ('pending','seller_sent','disputed')
                                or (t.status = 'expired'
                                    and exists (select 1 from public.disputes d
                                                 where d.transfer_id = t.id
                                                   and d.status not in ('won','lost','warning_closed','charge_refunded')))))),
        -- BP-8 live arm: in-flight buy-now reservation
        (select 'BP-8: a live buy-now reservation is in flight — it must land or be released'
          where exists (select 1 from public.listings l
                         where l.reserved_by = v_row.identity_id)),
        -- BP-9 live arm: won-unsettled auction, plus live-auction high bidder
        (select 'BP-9: a won auction has not settled (or a live auction carries this account as high bidder)'
          where exists (select 1 from public.listings l
                         where l.winner_user_id = v_row.identity_id
                           and not exists (select 1 from public.transfers t
                                            where t.listing_id = l.id
                                              and t.status in ('buyer_confirmed','auto_released')))
             or exists (select 1 from public.listings l
                         where l.highest_bidder_id = v_row.identity_id
                           and l.auction_status = 'active')),
        -- BP-10 negative settlement obligation (hook predicate, OR-21)
        (select 'BP-10: an outstanding settlement obligation must be recovered or written off'
          where kernel.has_outstanding_obligations(v_row.identity_id)),
        -- BP-11 sole org_owner (direct — 077 tables)
        (select 'BP-11: sole org_owner of organization ' || m.org_id::text
                || ' — transfer ownership or close the org first'
           from kernel.org_member m
          where m.identity_id = v_row.identity_id and m.role = 'org_owner'
            and not exists (select 1 from kernel.org_member m2
                             where m2.org_id = m.org_id and m2.role = 'org_owner'
                               and m2.identity_id <> m.identity_id)
          limit 1),
        -- BP-12 pending-order arm (hook; venue.order is 082)
        kernel.deletion_blockers_orders(v_row.identity_id)
      );

      if v_reason is not null then
        v_blocked := v_blocked + 1;
        update kernel.identity_ext
           set deletion_block_reason = v_reason
         where identity_id = v_row.identity_id;
        continue;
      end if;

      -- ===== TERMINAL ENTRY (idempotent; dsm §4) ============================
      -- (a0) close the BP-11 write-skew (red-team C blocker 1): the RPC-side
      --     last-owner re-counts serialize on the ORGANIZATION row, so the
      --     terminal member-delete must too — lock every org the identity
      --     belongs to (ascending org_id; identity_ext -> organization is the
      --     existing accept_org_invite direction, no new deadlock class) and
      --     RE-VERIFY BP-11 under those locks. The unlocked coalesce pass
      --     above is the cheap early-out; THIS is the enforcement.
      perform 1
        from (select o.org_id
                from kernel.organization o
               where o.org_id in (select m.org_id from kernel.org_member m
                                   where m.identity_id = v_row.identity_id)
               order by o.org_id
                 for update) locked_orgs;
      if exists (select 1
                   from kernel.org_member m
                  where m.identity_id = v_row.identity_id and m.role = 'org_owner'
                    and not exists (select 1 from kernel.org_member m2
                                     where m2.org_id = m.org_id
                                       and m2.role = 'org_owner'
                                       and m2.identity_id <> m.identity_id)) then
        v_blocked := v_blocked + 1;
        update kernel.identity_ext
           set deletion_block_reason =
               'BP-11: sole org_owner (re-verified under the org locks) — transfer ownership first'
         where identity_id = v_row.identity_id;
        continue;
      end if;

      -- (a) the erased marker write — PFA-3: deletion_state := 'ERASED';
      --     deletion_requested_at is RETAINED (the durable record).
      update kernel.identity_ext
         set deletion_state        = 'ERASED',
             deletion_block_reason = null
       where identity_id = v_row.identity_id;

      -- (b) 077-plane role/invite clears (dsm §4.5 class 1; INV #1/#4-#8).
      --     BP-11 just proved no sole-ownership under this transaction's lock.
      --     No admin_audit rows: the sweep has no human actor and the
      --     SN-SYSTEM sentinel is a 078 seed (forward reference — E-5).
      delete from kernel.org_member    where identity_id = v_row.identity_id;
      delete from kernel.platform_role where identity_id = v_row.identity_id;
      update kernel.org_invite
         set status = 'revoked'
       where status = 'pending'
         and (invitee_identity_id = v_row.identity_id
              or invited_by = v_row.identity_id);

      -- (c) live public.* clears: the PR#28/020 cleanup semantics MINUS every
      --     sentinel repointing (dsm §4.5/§5; §20.15 write set transcribed —
      --     the own-live-auction cancel arm; CUSTODY-DEL-1 untouched; storage
      --     is the edge layer's step; auth.admin.deleteUser called by NOTHING).
      perform set_config('app.bypass_listing_guard', 'on', true);
      update public.listings
         set auction_status = 'cancelled',
             status         = 'active',
             reserved_by    = null,
             reserved_until = null,
             ended_at       = now()
       where seller_id = v_row.identity_id
         and auction_status in ('active','ended');
      perform set_config('app.bypass_listing_guard', 'off', true);

      -- (d) the four terminal cleanup hooks (no-ops until their packages)
      perform kernel.on_identity_erased_staff(v_row.identity_id);
      perform kernel.on_identity_erased_door(v_row.identity_id);
      perform kernel.on_identity_erased_market(v_row.identity_id);
      perform kernel.on_identity_erased_promoter(v_row.identity_id);

      -- (e) OPEN-6a: whether ERASED entry hard-deletes the demographic row is
      --     unruled — recorded here, deliberately NOT implemented.

      -- (f) BE-emit account_deletion_completed (R2 row 32) — last write. A
      --     failed PASS (quarantined exception above) re-runs terminal entry
      --     next tick and re-emits, collapsed by the once-ever key. A
      --     SWALLOWED emit beneath a committed tombstone is the accepted
      --     BEST-EFFORT loss (OR-14: the notice never gates the machine) —
      --     warning-visible; recorded in the 077 errata.
      begin
        perform notify.emit_event(
          'account_deletion_completed', 'identity', v_row.identity_id,
          'account_deletion_completed:' || v_row.identity_id::text,
          jsonb_build_object('deletion_requested_at', v_row.deletion_requested_at));
      exception when others then
        raise warning 'sweep_deletion_pending: best-effort completion emit failed for %: %',
          v_row.identity_id, sqlerrm;
      end;

      v_tombstoned := v_tombstoned + 1;
    exception when others then
      -- half-completion is re-detected next pass (the sweep is the detector);
      -- one poison identity never stops the tick
      raise warning 'sweep_deletion_pending: identity % failed: %', v_row.identity_id, sqlerrm;
    end;
  end loop;

  return jsonb_build_object('swept', v_swept, 'blocked', v_blocked,
                            'tombstoned', v_tombstoned);
end;
$$;

-- =============================================================================
-- PART 10 — EXECUTE POSTURE (RLS §11: explicit REVOKE-then-GRANT, 066/067;
-- caller-authorized => authenticated; DEF => service_role only; the trigger
-- writer and helpers => nobody)
-- =============================================================================

do $$
declare
  f text;
begin
  -- strip default PUBLIC EXECUTE + client roles from every 077 function
  foreach f in array array[
    'kernel.has_org_role(uuid, text[])',
    'kernel.is_platform(text[])',
    'kernel.is_org_affiliate(uuid)',
    'kernel.get_my_demographics()',
    'kernel.set_my_demographics(text, text)',
    'kernel.clear_my_demographics()',
    'kernel.get_my_contact_prefs()',
    'kernel.set_my_contact_prefs(text)',
    'kernel.create_organization(text, text, text)',
    'kernel.update_organization(uuid, jsonb, text)',
    'kernel.set_org_status(uuid, text, text, text)',
    'kernel.set_org_connect_ref(uuid, text, text)',
    'kernel.invite_org_member(uuid, text, text, text)',
    'kernel.accept_org_invite(uuid, text)',
    'kernel.change_org_role(uuid, uuid, text, text)',
    'kernel.remove_org_member(uuid, uuid, text)',
    'kernel.revoke_org_invite(uuid, text)',
    'kernel.sweep_expired_org_invites(int)',
    'kernel.upsert_identity_ext(jsonb, text)',
    'kernel.admin_set_identity_ext(uuid, jsonb, text, text)',
    'kernel.grant_platform_role(uuid, text, text, text)',
    'kernel.revoke_platform_role(uuid, text, text, text)',
    'kernel.request_account_deletion(text)',
    'kernel.withdraw_account_deletion(text)',
    'kernel.is_deletion_pending(uuid)',
    'kernel.sweep_deletion_pending(int)',
    'kernel.deletion_blockers_custody(uuid)',
    'kernel.deletion_blockers_orders(uuid)',
    'kernel.deletion_blockers_wallet(uuid)',
    'kernel.deletion_blockers_money(uuid)',
    'kernel.deletion_blockers_market(uuid)',
    'kernel.on_identity_erased_staff(uuid)',
    'kernel.on_identity_erased_door(uuid)',
    'kernel.on_identity_erased_market(uuid)',
    'kernel.on_identity_erased_promoter(uuid)',
    'kernel.has_outstanding_obligations(uuid)',
    'kernel.on_deletion_q5_release(uuid)',
    'kernel.write_demographic_erasure_tombstone()'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
  end loop;

  -- caller-authorized class: GRANT EXECUTE TO authenticated (in-body re-check)
  foreach f in array array[
    'kernel.has_org_role(uuid, text[])',
    'kernel.is_platform(text[])',
    'kernel.is_org_affiliate(uuid)',
    'kernel.get_my_demographics()',
    'kernel.set_my_demographics(text, text)',
    'kernel.clear_my_demographics()',
    'kernel.get_my_contact_prefs()',
    'kernel.set_my_contact_prefs(text)',
    'kernel.create_organization(text, text, text)',
    'kernel.update_organization(uuid, jsonb, text)',
    'kernel.set_org_status(uuid, text, text, text)',
    'kernel.set_org_connect_ref(uuid, text, text)',
    'kernel.invite_org_member(uuid, text, text, text)',
    'kernel.accept_org_invite(uuid, text)',
    'kernel.change_org_role(uuid, uuid, text, text)',
    'kernel.remove_org_member(uuid, uuid, text)',
    'kernel.revoke_org_invite(uuid, text)',
    'kernel.upsert_identity_ext(jsonb, text)',
    'kernel.admin_set_identity_ext(uuid, jsonb, text, text)',
    'kernel.grant_platform_role(uuid, text, text, text)',
    'kernel.revoke_platform_role(uuid, text, text, text)',
    'kernel.request_account_deletion(text)',
    'kernel.withdraw_account_deletion(text)'
  ] loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;

  -- DEF class: GRANT EXECUTE TO service_role only (RLS §11 intro + :1911 —
  -- the sweeps, the freeze predicate and the eleven hooks carry no client
  -- grant of any kind; D-F2)
  foreach f in array array[
    'kernel.sweep_expired_org_invites(int)',
    'kernel.sweep_deletion_pending(int)',
    'kernel.is_deletion_pending(uuid)',
    'kernel.deletion_blockers_custody(uuid)',
    'kernel.deletion_blockers_orders(uuid)',
    'kernel.deletion_blockers_wallet(uuid)',
    'kernel.deletion_blockers_money(uuid)',
    'kernel.deletion_blockers_market(uuid)',
    'kernel.on_identity_erased_staff(uuid)',
    'kernel.on_identity_erased_door(uuid)',
    'kernel.on_identity_erased_market(uuid)',
    'kernel.on_identity_erased_promoter(uuid)',
    'kernel.has_outstanding_obligations(uuid)',
    'kernel.on_deletion_q5_release(uuid)'
  ] loop
    execute format('grant execute on function %s to service_role', f);
  end loop;

  -- kernel.write_demographic_erasure_tombstone(): trigger writer — no grants.
end $$;

-- =============================================================================
-- PART 11 — CRON (register: per-job cron.schedule BY THE OWNING PACKAGE;
-- P0-1: no shared heartbeat exists. Job names follow the 014/032/075 kebab
-- convention; cron.schedule is idempotent by jobname. No collision with
-- auto-finalize-auctions / enforce-transfer-expiry / sweep-auth-password-changes.)
-- =============================================================================

select cron.schedule(
  'sweep-deletion-pending',
  '*/2 * * * *',
  $$select kernel.sweep_deletion_pending();$$
);

select cron.schedule(
  'sweep-expired-org-invites',
  '*/2 * * * *',
  $$select kernel.sweep_expired_org_invites();$$
);

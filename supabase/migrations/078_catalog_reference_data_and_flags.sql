-- 078_catalog_reference_data_and_flags.sql
-- =============================================================================
-- Phase-2 package 078 — kernel-owned, world-readable catalog reference data
-- (venues / events / sessions), the versioned two-class platform config table,
-- the resale-policy register, and EVERY SEED ROW IN THE CHAIN: the single
-- auditable answer to "is every gate seeded and every flag OFF?"
--
-- FROZEN SOURCES (architecture frozen at 06fd5ecccc405f416e8f27591ccbbf709771f8ef,
-- tag phase2-architecture-v2; implementer mode — no redesign):
--   plan §5/§8 `078_catalog_reference_data_and_flags` (the package-authoritative
--   object set; §8 wins over §5) · registry JSON row 078 · schema spec
--   §0, §1.13.4, §1.16 (MB-5), §2.1–§2.5, §2.4.1 (AUTHZ-CFG1), §13.2 (FR-2,
--   FR-2b, FR-6, FR-7, FR-10…FR-13 + SEAM-1/SEAM-2/SEAM-3) · RPC contracts
--   §1.1e, §3.1–§3.3, §4.1, §4.3, §12.4a, §17.0a, §20.2.1–§20.2.3 · RLS spec
--   §8.1–§8.5, §11.1/§11.1a/§11.1b/§11.2/§11.3, §16.10, §16.10a, §17 X-11/X-12 ·
--   MONEY §7.2/§7.3 · DOOR §10.6 · WALLET §11.5 · NOTIF §7.3/§7.4/§10.2 ·
--   CRM §X-9 · ratification OR-22 (resale.buy_now_reservation_ttl_minutes),
--   OR-16/DEMOG §8.5 (retention.backup_window_days ABSENT-BY-DESIGN).
--
-- POST-FREEZE AMENDMENTS EXERCISED HERE (filed in
-- docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md BEFORE this commit):
--   PFA-7  — the frozen constants falsify the frozen cross-config invariant
--            (12h + 6h > 12h). credential.wallet_default_span seeds at '6 hours',
--            the MAXIMUM the invariant admits with the other two byte-exact.
--            PROVISIONAL, pinned to OD-25; the Wallet rail is dark.
--   PFA-8  — visibility: RLS §8.4's six-namespace rule + §2.4.1's explicit public
--            list govern over §11.3's seven-namespace sentence (which would fail
--            two frozen tests). The seven-namespace DUAL-CONTROL set is unchanged.
--   PFA-9  — the config-key closed world cannot be closed from frozen bytes.
--            Nothing is invented: value-open keys ship as rows carrying a JSON
--            `null` value (the retention.backup_window_days pattern), so the
--            registry precondition of RPC §20.2.1 holds and every X-12 consumer
--            still reads restrictively.
--   PFA-10 — five RPCs here call kernel.has_venue_role (080). Placement kept per
--            plan §8; the org arm is evaluated in its OWN statement FIRST so the
--            deferred name is never parsed on the authorised path. The venue arm
--            fails closed (42883) until 080 — the SEAM-3 posture. DO NOT "fix"
--            this by re-inlining the venue-role join: RM-3 forbids it explicitly.
--
-- WHAT THIS PACKAGE DELIBERATELY DOES NOT CONTAIN (boundary, frozen):
--   catalog.publish_event (081 — §13.2 FR-2: it reads venue.ticket_type /
--   venue.inventory_batch) · catalog.cancel_event (088 — FR-2b) ·
--   kernel.is_transfer_frozen + kernel.door_freeze_override (079 — FR-7) ·
--   catalog.update_event_session (079 — SEAM-1: its time guard reads
--   kernel.tickets) · catalog.engage_door_freeze and the door_open_at
--   ledger-head trigger (086 — FR-6, attached to THIS package's table) ·
--   the three venue-plane read policies catalog_{venue,event,event_session}_sel_venue
--   (080 — FR-10…FR-12 / SEAM-3; between here and 080 the venue plane cannot read
--   these tables: intended, fail-closed, closes one package later) ·
--   the approve/deny verb for kernel.approval_request (085) — so between here and
--   085 NO money-namespace config key can be changed at all, which is fail-closed
--   and is the intended posture · every native Buy-Now object (088): this package
--   seeds the reservation TTL and NOTHING else of that rail · the CRM limit keys
--   (087 — PFA-9 CLASS B) · any platform-role grant path (077, fail-closed under
--   PFA-4; nothing here touches it).
--
-- HARDENING-1 (owner-approved 2026-08-31, POST_FREEZE_AMENDMENTS.md) rides this
-- migration as Part 11 — a CREATE OR REPLACE of kernel.sweep_deletion_pending's
-- BODY ONLY, adding the recorded isolation guard. Migration 077 is immutable and
-- is not touched. See Part 11's own header for the carrier rationale.
--
-- LOCKS / RUNTIME: new-table DDL only; every CREATE INDEX runs on an empty table
-- (instant). The seeds are 41 config rows + 6 sentinel rows, all
-- ON CONFLICT DO NOTHING. GRANT/REVOKE touch catalog only. Runtime: seconds.
-- BACKFILL: seed rows only (idempotent).
--
-- AUTHOR'S DISCRETION, DOCUMENTED HERE AS PLAN §7 REQUIRES:
--   catalog.platform_config uses the COMPOSITE PK (key, version) — plan §7's
--   primary option — not a surrogate config_id.
--   kernel.approval_request.subject_id is uuid NOT NULL and a config key is text,
--   so for subject_kind='config_key' the id is the deterministic
--   md5(key)::uuid and the literal key travels in `payload` (APPR-SUBJ-1 has no
--   FK to satisfy — the residual is accepted on the record in RPC §17.0a).
--   A parked config request expires 72 hours after it is created; no config
--   parking horizon exists in the frozen corpus (recorded errata).
--
-- ROLLBACK: supabase/rollbacks/078_catalog_reference_data_and_flags_rollback.sql
-- Posture: CLEAN-WHILE-EMPTY (plan §8/078). The rollback also restores the
-- pre-HARDENING-1 body of kernel.sweep_deletion_pending verbatim, without
-- modifying migration 077.
--
-- VERIFICATION QUERY (post-apply):
--   select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
--    where n.nspname='catalog' and c.relkind='r';                          -- 5
--   select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--    where n.nspname='catalog';                                            -- 9
--   select count(*) from catalog.platform_config;                          -- 41
--   select count(*) from catalog.platform_config where visibility='public';-- 8
--   select count(*) from pg_policy p join pg_class c on c.oid=p.polrelid
--     join pg_namespace n on n.oid=c.relnamespace where n.nspname='catalog';-- 9
-- =============================================================================

-- =============================================================================
-- PART 1 — TABLES (schema §2.1–§2.5), with deny-by-default + column GRANTs (I-7)
-- =============================================================================

-- 1.1 catalog.venue (schema §2.1)
create table if not exists catalog.venue (
  venue_id        uuid primary key default gen_random_uuid(),
  org_id          uuid not null references kernel.organization(org_id) on delete restrict,
  name            text not null,
  -- CONFLICTS #7: the frozen public.listings neighborhood check-set, duplicated
  -- by decision rather than joined to a lookup table.
  neighborhood    text not null
                  check (neighborhood in (
                    'south beach','wynwood','brickell','downtown miami',
                    'design district','coconut grove','little havana',
                    'miami beach','midtown')),
  address         text,
  capacity_hint   integer,          -- informational; NOT the oversell guard
  approval_status text not null default 'draft'
                  check (approval_status in ('draft','pending','approved','archived')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists venue_org_idx           on catalog.venue (org_id);
create index if not exists venue_neighborhood_idx  on catalog.venue (neighborhood);
create index if not exists venue_approved_idx      on catalog.venue (venue_id)
  where approval_status = 'approved';

alter table catalog.venue enable row level security;
revoke all on catalog.venue from public, anon, authenticated;
grant select (venue_id, org_id, name, neighborhood, address, capacity_hint,
              approval_status, created_at, updated_at)
  on catalog.venue to anon, authenticated;

drop trigger if exists tg_venue_set_updated_at on catalog.venue;
create trigger tg_venue_set_updated_at
  before update on catalog.venue
  for each row execute function kernel.set_updated_at();

-- 1.2 catalog.event (schema §2.2, incl. the S-5/D3/H4 marketing columns)
create table if not exists catalog.event (
  event_id       uuid primary key default gen_random_uuid(),
  venue_id       uuid not null references catalog.venue(venue_id) on delete restrict,
  org_id         uuid not null references kernel.organization(org_id) on delete restrict,
  title          text not null,
  status         text not null default 'draft'
                 check (status in ('draft','announced','on_sale','live','completed','cancelled')),
  -- Marketing columns (schema §2.2). `category` ships WITHOUT a membership CHECK:
  -- the frozen corpus enumerates no members (PFA-9 CLASS C). hero_image_ref is an
  -- OPAQUE STORAGE OBJECT REFERENCE, never a URL and never bytes — a URL column on
  -- a world-readable table is an unvalidated egress vector.
  description    text,
  hero_image_ref text,
  category       text,
  genre_tags     text[] not null default '{}'
                 check (array_length(genre_tags, 1) is null
                        or array_length(genre_tags, 1) <= 10),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists event_venue_idx on catalog.event (venue_id);
create index if not exists event_org_idx   on catalog.event (org_id);
create index if not exists event_live_idx  on catalog.event (event_id)
  where status in ('on_sale','live');

alter table catalog.event enable row level security;
revoke all on catalog.event from public, anon, authenticated;
grant select (event_id, venue_id, org_id, title, status, description,
              hero_image_ref, category, genre_tags, created_at, updated_at)
  on catalog.event to anon, authenticated;

drop trigger if exists tg_event_set_updated_at on catalog.event;
create trigger tg_event_set_updated_at
  before update on catalog.event
  for each row execute function kernel.set_updated_at();

-- 1.3 catalog.event_session (schema §2.3) — the admission grain, and the
-- toward-reference target for kernel.tickets.event_session_id (A7/C7).
create table if not exists catalog.event_session (
  session_id      uuid primary key default gen_random_uuid(),
  event_id        uuid not null references catalog.event(event_id) on delete restrict,
  session_label   text,
  starts_at       timestamptz not null,
  ends_at         timestamptz,
  doors_at        timestamptz,
  -- A2/A3: the CANONICAL door-freeze signal, set when the offline door manifest
  -- opens. Distinct from the informational doors_at. Its SOLE writer is
  -- catalog.engage_door_freeze (086, RPC §17.12) and the ledger-head trigger that
  -- enforces that independently of grants is created in 086 (FR-6).
  door_open_at    timestamptz,
  status          text not null default 'scheduled'
                  check (status in ('scheduled','live','completed','cancelled')),
  home_region     text not null default 'us-east',
  -- Δ-N1, CORRECTNESS-BLOCKING (NOTIF §2.2 Group E): three notification dedupe
  -- keys embed it. Bumped ONLY by catalog.update_event_session (079), in the same
  -- transaction as the change it describes, under the row's FOR UPDATE.
  session_version integer not null default 1,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint event_session_label_uq unique (event_id, session_label),
  constraint event_session_time_check
    check (ends_at is null or starts_at is null or ends_at > starts_at)
);

create index if not exists event_session_event_idx  on catalog.event_session (event_id);
create index if not exists event_session_starts_idx on catalog.event_session (starts_at);

alter table catalog.event_session enable row level security;
revoke all on catalog.event_session from public, anon, authenticated;
grant select (session_id, event_id, session_label, starts_at, ends_at, doors_at,
              door_open_at, status, home_region, session_version,
              created_at, updated_at)
  on catalog.event_session to anon, authenticated;

drop trigger if exists tg_event_session_set_updated_at on catalog.event_session;
create trigger tg_event_session_set_updated_at
  before update on catalog.event_session
  for each row execute function kernel.set_updated_at();

-- 1.4 catalog.platform_config (schema §2.4 + §2.4.1 AUTHZ-CFG1)
-- AO PER VERSION: a change INSERTs (key, version+1); no row is ever updated or
-- deleted, so an object governed by an old version stays interpretable (C11/O3).
create table if not exists catalog.platform_config (
  key            text    not null,
  version        integer not null,
  value          jsonb   not null,   -- a semantically-absent value is the JSON null
  visibility     text    not null default 'restricted'
                 check (visibility in ('public','restricted')),
  effective_from timestamptz not null default now(),
  created_at     timestamptz not null default now(),
  constraint platform_config_pkey primary key (key, version),
  constraint platform_config_version_check check (version >= 1)
);

create index if not exists platform_config_key_idx on catalog.platform_config (key);
-- The anon discovery read never touches a restricted row (schema §2.4).
create index if not exists platform_config_public_idx on catalog.platform_config (key)
  where visibility = 'public';

alter table catalog.platform_config enable row level security;
revoke all on catalog.platform_config from public, anon, authenticated;
grant select (key, version, value, visibility, effective_from, created_at)
  on catalog.platform_config to anon, authenticated;

-- T-RPC-CFG-04: the table has ZERO UPDATE and ZERO DELETE paths, asserted as
-- postgres and as service_role. Only a trigger can hold that against a superuser.
drop trigger if exists tg_platform_config_append_only on catalog.platform_config;
create trigger tg_platform_config_append_only
  before update or delete on catalog.platform_config
  for each row execute function kernel.raise_append_only();

-- 1.5 catalog.resale_policy (schema §2.5)
create table if not exists catalog.resale_policy (
  policy_id      uuid primary key default gen_random_uuid(),
  scope_kind     text not null check (scope_kind in ('venue','event')),
  venue_id       uuid references catalog.venue(venue_id) on delete restrict,
  event_id       uuid references catalog.event(event_id) on delete restrict,
  -- C11: default `off`. The storage set is schema §2.5's seven modes; RPC
  -- §20.2.2's three-label sketch {off, capped, free} is the stale surface
  -- (recorded errata) — `fixed_cap` is its `capped`.
  mode           text not null default 'off'
                 check (mode in ('off','transfers_only','fixed_cap',
                                 'face_value_queue','buy_now','auction','offer')),
  price_cap_bps  integer check (price_cap_bps is null
                                or (price_cap_bps between 0 and 10000)),
  royalty_bps    integer check (royalty_bps is null
                                or (royalty_bps between 0 and 10000)),
  version        integer not null,
  effective_from timestamptz not null default now(),
  created_at     timestamptz not null default now(),
  constraint resale_policy_scope_coherence_check
    check (   (scope_kind = 'venue' and venue_id is not null and event_id is null)
           or (scope_kind = 'event' and event_id is not null and venue_id is null)),
  constraint resale_policy_version_check check (version >= 1),
  -- NULLS NOT DISTINCT is load-bearing: the coherence CHECK forces exactly one
  -- of venue_id/event_id to be NULL in EVERY row, so under Postgres's default
  -- NULLS DISTINCT this constraint could never fire on any row the table can
  -- hold — and schema §2.5's stated property ("at most one active policy per
  -- scope target per version") would be enforced by nothing.
  constraint resale_policy_scope_version_uq
    unique nulls not distinct (scope_kind, venue_id, event_id, version)
);

create index if not exists resale_policy_event_idx on catalog.resale_policy (event_id, version);
create index if not exists resale_policy_venue_idx on catalog.resale_policy (venue_id, version);

alter table catalog.resale_policy enable row level security;
revoke all on catalog.resale_policy from public, anon, authenticated;
grant select (policy_id, scope_kind, venue_id, event_id, mode, price_cap_bps,
              royalty_bps, version, effective_from, created_at)
  on catalog.resale_policy to anon, authenticated;

-- AO per version (schema §2.5): listings snapshot policy_id+version, so a live
-- version must never mutate under a listing that already references it.
drop trigger if exists tg_resale_policy_append_only on catalog.resale_policy;
create trigger tg_resale_policy_append_only
  before update or delete on catalog.resale_policy
  for each row execute function kernel.raise_append_only();

-- =============================================================================
-- PART 2 — RLS POLICIES (the frozen §16.10 register for catalog; FOR SELECT only;
-- GP-1/GP-2: no client principal holds INSERT/UPDATE/DELETE anywhere, and DELETE
-- is denied for every role on every table)
--
-- THREE POLICIES ARE DELIBERATELY ABSENT — catalog_venue_sel_venue,
-- catalog_event_sel_venue, catalog_event_session_sel_venue. They call
-- kernel.has_venue_role / kernel.has_event_role, which do not exist until 080,
-- and RM-3 forbids re-inlining the join. Writing them here fails the replay with
-- 42883. They are created in 080; their full USING clauses are in RLS §16.10a.
-- =============================================================================

drop policy if exists catalog_venue_sel_anon on catalog.venue;
create policy catalog_venue_sel_anon
  on catalog.venue for select to anon, authenticated
  using (approval_status = 'approved');

drop policy if exists catalog_venue_sel_org on catalog.venue;
create policy catalog_venue_sel_org
  on catalog.venue for select to authenticated
  using (kernel.has_org_role(org_id, array['org_owner','org_admin','org_finance','org_member'])
         or kernel.is_platform(array['platform_admin','platform_support','platform_risk']));

-- R3-3a: the visibility test is `status <> 'draft'`, NOT `status >= 'announced'`.
-- status is TEXT with a CHECK (no native enum exists anywhere in the model —
-- T-SCHEMA-ROLE-02), so `>=` is a LEXICOGRAPHIC comparison over
-- {announced, cancelled, completed, draft, live, on_sale}; 'announced' sorts
-- FIRST, so `>= 'announced'` is true for every label INCLUDING 'draft'.
drop policy if exists catalog_event_sel_anon on catalog.event;
create policy catalog_event_sel_anon
  on catalog.event for select to anon, authenticated
  using (status <> 'draft');

drop policy if exists catalog_event_sel_org on catalog.event;
create policy catalog_event_sel_org
  on catalog.event for select to authenticated
  using (kernel.has_org_role(org_id, array['org_owner','org_admin','org_finance','org_member'])
         or kernel.is_platform(array['platform_admin','platform_support','platform_risk']));

-- "Sessions of visible events" resolves THROUGH catalog.event, so it inherits the
-- corrected predicate rather than restating it (§16.10a).
drop policy if exists catalog_event_session_sel_anon on catalog.event_session;
create policy catalog_event_session_sel_anon
  on catalog.event_session for select to anon, authenticated
  using (exists (select 1 from catalog.event e
                  where e.event_id = catalog.event_session.event_id
                    and e.status <> 'draft'));

drop policy if exists catalog_event_session_sel_org on catalog.event_session;
create policy catalog_event_session_sel_org
  on catalog.event_session for select to authenticated
  using (exists (select 1 from catalog.event e
                  where e.event_id = catalog.event_session.event_id
                    and (kernel.has_org_role(e.org_id,
                             array['org_owner','org_admin','org_finance','org_member'])
                         or kernel.is_platform(
                             array['platform_admin','platform_support','platform_risk']))));

-- AUTHZ-CFG1 (schema §2.4.1 / RLS §8.4): TWO classes, not one.
drop policy if exists catalog_platform_config_sel_public on catalog.platform_config;
create policy catalog_platform_config_sel_public
  on catalog.platform_config for select to anon, authenticated
  using (visibility = 'public');

drop policy if exists catalog_platform_config_sel_restricted on catalog.platform_config;
create policy catalog_platform_config_sel_restricted
  on catalog.platform_config for select to authenticated
  using (kernel.is_platform(array['platform_admin','platform_risk']));

-- RLS §8.5: A(policy in force). NARROW, never USING(true) — I-2 forbids a broad
-- clause on a catalog table and T-RLS-POL-02 asserts unconditionally that no
-- USING(true) exists anywhere in the Phase-2 schemas. Two conjuncts:
-- The predicate is the PARENT'S VISIBILITY: set_resale_policy gates on org
-- authority only and never on the parent's status, so without this a draft
-- event's or an unapproved venue's commercial terms (mode, price cap, royalty)
-- would be world-readable while the parent row itself is hidden. It resolves
-- THROUGH the parent's own predicate rather than restating it, the shape
-- catalog_event_session_sel_anon already uses.
--
-- §8.5's cell reads A(policy in force). A "greatest version for this scope
-- target" conjunct is NOT expressible here: it must read catalog.resale_policy
-- itself, which re-enters this policy and raises 42P17 infinite recursion. The
-- two ways out are a new column or a SECURITY DEFINER helper, and BOTH are
-- objects the frozen closed world does not carry (parity EXTRA = 0). So every
-- version of a VISIBLE parent is readable — which is also what a client needs to
-- interpret the (policy_id, version) pair market.listing_native snapshots.
-- Recorded in the 078 errata; the I-2 ban on USING(true) is satisfied either way.
drop policy if exists catalog_resale_policy_sel_public on catalog.resale_policy;
create policy catalog_resale_policy_sel_public
  on catalog.resale_policy for select to anon, authenticated
  using (
    (
      (scope_kind = 'venue'
        and exists (select 1 from catalog.venue v
                     where v.venue_id = catalog.resale_policy.venue_id
                       and v.approval_status = 'approved'))
      or
      (scope_kind = 'event'
        and exists (select 1 from catalog.event e
                     where e.event_id = catalog.resale_policy.event_id
                       and e.status <> 'draft'))
    ));

-- =============================================================================
-- PART 3 — PREDICATE / DERIVATION HELPERS
-- =============================================================================

-- 3.1 catalog.effective_freeze_at (RPC §12.4a) — TOTAL by construction.
-- starts_at is NOT NULL, so there is NO input for which this returns NULL and
-- therefore NO input for which the freeze silently never engages. That is
-- fail-closed expressed as a type, not as a promise (T-RPC-DOOR-08).
create or replace function catalog.effective_freeze_at(p_session_id uuid)
returns timestamptz
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row    record;
  v_offset interval;
begin
  select s.starts_at, s.doors_at, s.door_open_at
    into v_row
    from catalog.event_session s
   where s.session_id = p_session_id;

  if not found then
    -- A predicate that silently tolerates an unknown session FAILS OPEN on the
    -- transfer path (the withdrawn escape hatch, plan §5/078 correction 3).
    raise exception 'not_found: event_session % does not exist', p_session_id
      using errcode = 'P0002';
  end if;

  -- An absent or unparseable offset means NO offset — the implicit backstop
  -- engages at COALESCE(doors_at, starts_at) exactly, never later.
  begin
    v_offset := (select (c.value #>> '{}')::interval
                   from catalog.platform_config c
                  where c.key = 'door.implicit_freeze_offset_interval'
                  order by c.version desc
                  limit 1);
  exception when others then
    v_offset := null;                    -- unparseable is the absent case
  end;
  v_offset := coalesce(v_offset, interval '0 minutes');

  return least(
    v_row.door_open_at,                                  -- explicit, nullable
    coalesce(v_row.doors_at, v_row.starts_at) + v_offset -- implicit, NEVER null
  );
end;
$$;

-- 3.2 kernel.money_role_grant_matured (RPC §1.1e, AUTHZ-C1C).
-- AUTHORED HERE, NOT IN 077: it reads kernel.org_member (077) AND
-- catalog.platform_config together with its authn.money_role_maturity_hours seed
-- (this package), so SEAM-1 gives max(077, 078) = 078. 078 already depends on
-- 077, so no dependency edge is added.
-- ONE ARGUMENT, AND IT IS THE SCOPE, NOT THE ACTOR (C35).
create or replace function kernel.money_role_grant_matured(p_org_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_hours integer;
  v_uid   uuid;
begin
  -- 1. READ THE KEY FIRST, AND FAIL CLOSED ON IT BEFORE ANY ARITHMETIC.
  --    now() - NULL is NULL and granted_at <= NULL is NULL; whether NULL admits
  --    or denies would then be decided by whether the author wrote `matured` or
  --    `NOT immature`. The early return removes the question (X-12, AUTHZ-M4).
  --    A body that reaches make_interval with a NULL is a defect regardless of
  --    what it then returns.
  begin
    v_hours := (select (c.value #>> '{}')::integer
                  from catalog.platform_config c
                 where c.key = 'authn.money_role_maturity_hours'
                 order by c.version desc
                 limit 1);
  exception when others then
    v_hours := null;                       -- unparseable => no grant is mature
  end;
  if v_hours is null then
    return false;
  end if;

  v_uid := auth.uid();
  if v_uid is null then
    return false;
  end if;

  -- 2. THE GRANT MUST BE A MONEY GRANT, AND IT MUST BE OLD ENOUGH.
  --    granted_at, NEVER created_at: role is single-valued and changed by UPDATE,
  --    so created_at records when the person JOINED, not when they acquired money
  --    authority. EXISTS, not a count and not a join — (org_id, identity_id) is
  --    the org grant key, so this is a primary-key point probe.
  return exists (
    select 1
      from kernel.org_member m
     where m.org_id      = p_org_id
       and m.identity_id = v_uid
       and m.role in ('org_owner','org_finance')
       and m.granted_at <= now() - make_interval(hours => v_hours)
  );
end;
$$;

-- =============================================================================
-- PART 4 — VENUE WRITE SURFACE (RPC §3.1–§3.3)
-- =============================================================================

-- 4.1 catalog.create_venue (RPC §3.1)
create or replace function catalog.create_venue(
  p_org_id uuid, p_name text, p_neighborhood text, p_address text,
  p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid;
  v_status   text;
  v_venue_id uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if not kernel.has_org_role(p_org_id, array['org_owner','org_admin']) then
    raise exception 'insufficient_privilege: org_owner or org_admin required'
      using errcode = '42501';
  end if;

  select o.status into v_status
    from kernel.organization o where o.org_id = p_org_id;
  if v_status is null then
    raise exception 'not_found: organization %', p_org_id using errcode = 'P0002';
  end if;
  if v_status not in ('approved','active') then
    raise exception 'precondition_failed: organization is not approved/active';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'precondition_failed: venue name required';
  end if;

  -- approval_status is SERVER-DERIVED: 'draft'. It is not a parameter.
  insert into catalog.venue (org_id, name, neighborhood, address, approval_status)
  values (p_org_id, trim(p_name), p_neighborhood, p_address, 'draft')
  returning venue_id into v_venue_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'venue.create', 'venue', v_venue_id, 'self_service',
          null, jsonb_build_object('approval_status','draft','org_id',p_org_id));

  return jsonb_build_object('status','ok','venue_id',v_venue_id);
end;
$$;

-- 4.2 catalog.approve_venue (RPC §3.2; schema alias set_venue_approval)
create or replace function catalog.approve_venue(
  p_venue_id uuid, p_decision text, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_old text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  -- The Miami approved-venues gate: everyone except platform_admin is forbidden.
  if not kernel.is_platform(array['platform_admin']) then
    raise exception 'insufficient_privilege: platform_admin required'
      using errcode = '42501';
  end if;
  if p_decision is null or p_decision not in ('approved','archived','pending') then
    raise exception 'precondition_failed: decision must be approved|archived|pending';
  end if;
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: reason_required';
  end if;

  select v.approval_status into v_old
    from catalog.venue v where v.venue_id = p_venue_id for update;
  if v_old is null then
    raise exception 'not_found: venue %', p_venue_id using errcode = 'P0002';
  end if;

  if v_old = p_decision then
    return jsonb_build_object('status','noop_replay','approval_status',v_old);
  end if;

  update catalog.venue
     set approval_status = p_decision, updated_at = now()
   where venue_id = p_venue_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'venue.approve', 'venue', p_venue_id, trim(p_reason_code),
          jsonb_build_object('approval_status', v_old),
          jsonb_build_object('approval_status', p_decision));

  return jsonb_build_object('status','ok','approval_status',p_decision);
end;
$$;

-- 4.3 catalog.update_venue (RPC §3.3 + RLS §11.1a)
-- PFA-10: the org arm is evaluated in its OWN statement first; the venue arm's
-- statement is only ever prepared when the org arm has already failed, so an
-- org_owner/org_admin caller never parses kernel.has_venue_role (080).
create or replace function catalog.update_venue(
  p_venue_id uuid, p_patch jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_org_id    uuid;
  v_before    jsonb;
  v_key       text;
  v_new_org   uuid;
  v_reason    text;
  v_allowed   boolean := false;
  v_changed   boolean := false;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'invalid_input: patch must be a json object';
  end if;

  select v.org_id,
         jsonb_build_object('name', v.name, 'neighborhood', v.neighborhood,
                            'address', v.address, 'capacity_hint', v.capacity_hint,
                            'org_id', v.org_id)
    into v_org_id, v_before
    from catalog.venue v where v.venue_id = p_venue_id for update;
  if v_org_id is null then
    raise exception 'not_found: venue %', p_venue_id using errcode = 'P0002';
  end if;

  -- Arm 1 (078-resolvable): org_owner / org_admin over the operating org.
  if kernel.has_org_role(v_org_id, array['org_owner','org_admin']) then
    v_allowed := true;
  end if;
  -- Arm 2 (DEFERRED to 080 — PFA-10 / SEAM-3): venue_manager on this venue.
  if not v_allowed then
    v_allowed := kernel.has_venue_role(p_venue_id, array['venue_manager']);
  end if;
  if not v_allowed then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  for v_key in select jsonb_object_keys(p_patch) loop
    -- reason_code is a patch-CARRIED field, not a column: the operatorship arm
    -- below REQUIRES it, so omitting it here made that arm unreachable in both
    -- directions (no reason => reason_required; reason => unwritable_key).
    if v_key not in ('name','neighborhood','address','capacity_hint','org_id',
                     'reason_code') then
      raise exception 'invalid_input: unwritable_key %', v_key;
    end if;
  end loop;

  -- Operatorship (org_id) is a TENANCY MOVE, not a benign profile edit: it is
  -- is_platform([platform_admin]) only, and audited (RLS §11.1a — it was
  -- authorized nowhere in the §8.1 matrix).
  if p_patch ? 'org_id' then
    if not kernel.is_platform(array['platform_admin']) then
      raise exception 'insufficient_privilege: operatorship change is platform_admin only'
        using errcode = '42501';
    end if;
    v_reason := p_patch ->> 'reason_code';
    if v_reason is null or length(trim(v_reason)) = 0 then
      raise exception 'precondition_failed: reason_required for an operatorship change';
    end if;
    v_new_org := (p_patch ->> 'org_id')::uuid;
    if not exists (select 1 from kernel.organization o where o.org_id = v_new_org) then
      raise exception 'not_found: organization %', v_new_org using errcode = 'P0002';
    end if;
    update catalog.venue set org_id = v_new_org, updated_at = now()
     where venue_id = p_venue_id;
    v_changed := true;
  end if;

  if p_patch ? 'name' then
    update catalog.venue set name = p_patch ->> 'name', updated_at = now()
     where venue_id = p_venue_id; v_changed := true;
  end if;
  if p_patch ? 'neighborhood' then
    update catalog.venue set neighborhood = p_patch ->> 'neighborhood', updated_at = now()
     where venue_id = p_venue_id; v_changed := true;
  end if;
  if p_patch ? 'address' then
    update catalog.venue set address = p_patch ->> 'address', updated_at = now()
     where venue_id = p_venue_id; v_changed := true;
  end if;
  if p_patch ? 'capacity_hint' then
    update catalog.venue set capacity_hint = (p_patch ->> 'capacity_hint')::integer,
                             updated_at = now()
     where venue_id = p_venue_id; v_changed := true;
  end if;

  if not v_changed then
    return jsonb_build_object('status','noop_replay');
  end if;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'venue.update', 'venue', p_venue_id,
          coalesce(nullif(trim(coalesce(v_reason,'')),''), 'profile_edit'),
          v_before,
          (select jsonb_build_object('name', v.name, 'neighborhood', v.neighborhood,
                                     'address', v.address,
                                     'capacity_hint', v.capacity_hint,
                                     'org_id', v.org_id)
             from catalog.venue v where v.venue_id = p_venue_id));

  return jsonb_build_object('status','ok');
end;
$$;

-- =============================================================================
-- PART 5 — EVENT / SESSION WRITE SURFACE (RPC §4.1, §4.3, §20.2.3)
-- =============================================================================

-- 5.1 catalog.create_event_session (RPC §4.3) — declared first because
-- create_event calls it for the implicit one-night session (A1).
create or replace function catalog.create_event_session(
  p_event_id uuid, p_session jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid;
  v_org_id     uuid;
  v_venue_id   uuid;
  v_status     text;
  v_allowed    boolean := false;
  v_session_id uuid;
  v_starts     timestamptz;
  v_ends       timestamptz;
  v_doors      timestamptz;
  v_label      text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_session is null or jsonb_typeof(p_session) <> 'object' then
    raise exception 'invalid_input: session must be a json object';
  end if;

  select e.org_id, e.venue_id, e.status
    into v_org_id, v_venue_id, v_status
    from catalog.event e where e.event_id = p_event_id for update;
  if v_org_id is null then
    raise exception 'not_found: event %', p_event_id using errcode = 'P0002';
  end if;
  if v_status in ('completed','cancelled') then
    raise exception 'precondition_failed: event_terminal';
  end if;

  if kernel.has_org_role(v_org_id, array['org_owner','org_admin']) then
    v_allowed := true;
  end if;
  if not v_allowed then                                    -- PFA-10 deferred arm
    v_allowed := kernel.has_venue_role(v_venue_id, array['venue_manager']);
  end if;
  if not v_allowed then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  v_label  :=  p_session ->> 'session_label';
  v_starts := (p_session ->> 'starts_at')::timestamptz;
  v_ends   := (p_session ->> 'ends_at')::timestamptz;
  v_doors  := (p_session ->> 'doors_at')::timestamptz;
  if v_starts is null then
    raise exception 'invalid_input: starts_at required';
  end if;
  if v_ends is not null and v_ends <= v_starts then
    raise exception 'precondition_failed: ends_at must be after starts_at';
  end if;

  -- home_region and status are SERVER-DERIVED; session_version defaults to 1 and
  -- is never a parameter (its sole writer is catalog.update_event_session, 079).
  insert into catalog.event_session
         (event_id, session_label, starts_at, ends_at, doors_at, status, home_region)
  values (p_event_id, v_label, v_starts, v_ends, v_doors, 'scheduled', 'us-east')
  returning session_id into v_session_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'session.create', 'event_session', v_session_id, 'self_service',
          null, jsonb_build_object('event_id', p_event_id, 'starts_at', v_starts));

  return jsonb_build_object('status','ok','session_id',v_session_id);
end;
$$;

-- 5.2 catalog.create_event (RPC §4.1) — auto-creates the implicit first session.
create or replace function catalog.create_event(
  p_venue_id uuid, p_title text, p_first_session jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid;
  v_org_id   uuid;
  v_approval text;
  v_allowed  boolean := false;
  v_event_id uuid;
  v_session  jsonb;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_title is null or length(trim(p_title)) = 0 then
    raise exception 'precondition_failed: title required';
  end if;

  select v.org_id, v.approval_status
    into v_org_id, v_approval
    from catalog.venue v where v.venue_id = p_venue_id;
  if v_org_id is null then
    raise exception 'not_found: venue %', p_venue_id using errcode = 'P0002';
  end if;
  if v_approval <> 'approved' then
    raise exception 'precondition_failed: venue is not approved';
  end if;

  if kernel.has_org_role(v_org_id, array['org_owner','org_admin']) then
    v_allowed := true;
  end if;
  if not v_allowed then                                    -- PFA-10 deferred arm
    v_allowed := kernel.has_venue_role(p_venue_id, array['venue_manager']);
  end if;
  if not v_allowed then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  -- org_id is SERVER-DERIVED from catalog.venue.org_id (denormalised for the
  -- authz hot path and kept consistent by THIS function); status := 'draft'.
  insert into catalog.event (venue_id, org_id, title, status)
  values (p_venue_id, v_org_id, trim(p_title), 'draft')
  returning event_id into v_event_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'event.create', 'event', v_event_id, 'self_service',
          null, jsonb_build_object('venue_id', p_venue_id, 'status', 'draft'));

  -- A1: an event has >= 1 session, enforced by the create flow rather than by a
  -- table constraint.
  v_session := coalesce(p_first_session, '{}'::jsonb);
  return jsonb_build_object(
    'status','ok',
    'event_id', v_event_id,
    'session_id',
    (catalog.create_event_session(v_event_id, v_session,
                                  p_command_key || ':implicit-session') ->> 'session_id')::uuid);
end;
$$;

-- 5.3 catalog.update_event (RPC §20.2.3, U-9/G-12)
create or replace function catalog.update_event(
  p_event_id uuid, p_patch jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_org_id    uuid;
  v_venue_id  uuid;
  v_status    text;
  v_before    jsonb;
  v_key       text;
  v_reason    text;
  v_allowed   boolean := false;
  v_marketing boolean := false;
  v_title_chg boolean := false;
  v_changed   boolean := false;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'invalid_input: patch must be a json object';
  end if;

  select e.org_id, e.venue_id, e.status,
         jsonb_build_object('title', e.title, 'description', e.description,
                            'hero_image_ref', e.hero_image_ref,
                            'category', e.category, 'genre_tags', e.genre_tags)
    into v_org_id, v_venue_id, v_status, v_before
    from catalog.event e where e.event_id = p_event_id for update;
  if v_org_id is null then
    raise exception 'not_found: event %', p_event_id using errcode = 'P0002';
  end if;

  -- The unwritable set is checked BEFORE authority so that a patch naming
  -- venue_id / org_id / status raises invalid_input for every caller (T-RPC-CAT-01).
  for v_key in select jsonb_object_keys(p_patch) loop
    if v_key not in ('title','description','hero_image_ref','category',
                     'genre_tags','reason_code') then
      raise exception 'invalid_input: unwritable_key %', v_key;
    end if;
  end loop;

  -- Editability is bounded by LIFECYCLE, not by role, and the boundary is draft.
  if v_status in ('completed','cancelled') then
    raise exception 'precondition_failed: event_terminal';
  end if;

  v_title_chg := p_patch ? 'title';
  v_marketing := not v_title_chg;   -- marketing-only patch (D3)

  if kernel.has_org_role(v_org_id, array['org_owner','org_admin']) then
    v_allowed := true;
  elsif v_marketing
        and kernel.has_org_role(v_org_id, array['org_marketing']) then
    v_allowed := true;              -- marketing-only columns additionally admit
  end if;                           -- org_marketing; no other column does
  if not v_allowed then             -- PFA-10 deferred arm (venue_manager, and
    v_allowed := kernel.has_venue_role(                -- venue_marketing on the
      v_venue_id,                                      -- marketing-only patch)
      case when v_marketing then array['venue_manager','venue_marketing']
           else array['venue_manager'] end);
  end if;
  if not v_allowed then
    raise exception 'insufficient_privilege: venue_manager/org_owner/org_admin required'
      using errcode = '42501';
  end if;

  -- A title change after `announced` is what a buyer saw on the receipt for a
  -- ticket they already hold: it requires a reason code and is audited.
  v_reason := p_patch ->> 'reason_code';
  if v_title_chg and v_status <> 'draft'
     and (v_reason is null or length(trim(v_reason)) = 0) then
    raise exception 'precondition_failed: reason_required for a title change after draft';
  end if;

  if v_title_chg then
    update catalog.event set title = p_patch ->> 'title', updated_at = now()
     where event_id = p_event_id; v_changed := true;
  end if;
  if p_patch ? 'description' then
    update catalog.event set description = p_patch ->> 'description', updated_at = now()
     where event_id = p_event_id; v_changed := true;
  end if;
  if p_patch ? 'hero_image_ref' then
    update catalog.event set hero_image_ref = p_patch ->> 'hero_image_ref', updated_at = now()
     where event_id = p_event_id; v_changed := true;
  end if;
  if p_patch ? 'category' then
    update catalog.event set category = p_patch ->> 'category', updated_at = now()
     where event_id = p_event_id; v_changed := true;
  end if;
  if p_patch ? 'genre_tags' then
    update catalog.event
       set genre_tags = coalesce(
             (select array_agg(t) from jsonb_array_elements_text(p_patch -> 'genre_tags') t),
             '{}'),
           updated_at = now()
     where event_id = p_event_id; v_changed := true;
  end if;

  if not v_changed then
    return jsonb_build_object('status','noop_replay','event_id',p_event_id);
  end if;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'event.update', 'event', p_event_id,
          coalesce(nullif(trim(coalesce(v_reason,'')),''), 'marketing_edit'),
          v_before,
          (select jsonb_build_object('title', e.title, 'description', e.description,
                                     'hero_image_ref', e.hero_image_ref,
                                     'category', e.category, 'genre_tags', e.genre_tags)
             from catalog.event e where e.event_id = p_event_id));

  return jsonb_build_object('status','ok','event_id',p_event_id);
end;
$$;

-- =============================================================================
-- PART 6 — CONFIG / POLICY WRITE SURFACE (RPC §20.2.1, §20.2.2)
-- =============================================================================

-- 6.1 catalog.set_platform_config (RPC §20.2.1, G-6)
--
-- Dual control is MANDATORY, not a seam, for SEVEN key namespaces: refund.*,
-- payout.*, authn.*, comp.*, wallet.*, credential.* and door.session_*. For those
-- keys the call CREATES a kernel.approval_request which a second distinct
-- platform_admin must approve, and ONLY THE APPROVAL inserts the new
-- (key, version+1) row. The approving verb is authored in 085 — so between this
-- package and 085 no money-namespace key can be changed at all. That is
-- fail-closed and it is the intended posture.
--
-- DIRECTION ASYMMETRY: lowering a limit executes directly; only raising one needs
-- the second approver. The direction is computed SERVER-SIDE from the key's
-- declared polarity, NEVER supplied by the caller. A key with no declared
-- polarity, a non-scalar value, or an incomparable pair PARKS — the third arm,
-- because "not comparable" must fail toward the approver or a jsonb object
-- becomes the door through which a threshold is raised without one.
create or replace function catalog.set_platform_config(
  p_key text, p_value jsonb, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid;
  v_cur_ver    integer;
  v_cur_val    jsonb;
  v_visibility text;
  v_dual       boolean;
  v_polarity   text;
  v_restrictive boolean;
  v_old_num    numeric;
  v_new_num    numeric;
  v_span       interval;
  v_skew       interval;
  v_ttl        interval;
  v_request_id uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  -- reason_code is mandatory for EVERY key, not only the money namespaces.
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: reason_required';
  end if;
  -- platform_support and platform_risk hold NO authority here: risk holds
  -- hold_payout, not the thresholds that decide when a payout needs approval.
  if not kernel.is_platform(array['platform_admin']) then
    raise exception 'insufficient_privilege: platform_admin required'
      using errcode = '42501';
  end if;
  if p_value is null then
    raise exception 'precondition_failed: bad_value — use the JSON null literal';
  end if;

  -- APPR-SUBJ-1: resolve the subject under its own lock, in the same transaction
  -- that writes the row. THIS FUNCTION CREATES NO NEW KEY — a key that no code
  -- reads is a config row that lies (078 seeds every key).
  select c.version, c.value, c.visibility
    into v_cur_ver, v_cur_val, v_visibility
    from catalog.platform_config c
   where c.key = p_key
   order by c.version desc
   limit 1
     for update;
  if v_cur_ver is null then
    raise exception 'precondition_failed: unknown_key %', p_key;
  end if;

  if v_cur_val = p_value then
    return jsonb_build_object('status','noop_replay','key',p_key,
                              'version',v_cur_ver,'request_id',null);
  end if;

  -- RPC §20.2.1 precondition: "p_value passes the key's declared TYPE/RANGE".
  -- TYPE: a key never changes shape. The seeded row is the type witness; a key
  -- seeded absent-by-design (JSON null) has no witness yet and accepts the first
  -- typed value, after which the witness exists.
  if jsonb_typeof(v_cur_val) <> 'null'
     and jsonb_typeof(p_value) <> jsonb_typeof(v_cur_val) then
    raise exception 'precondition_failed: bad_value — % is %, not %',
      p_key, jsonb_typeof(v_cur_val), jsonb_typeof(p_value);
  end if;
  -- RANGE: enforced for every key whose admissible range the frozen corpus
  -- actually states. A key with no stated range is not invented one here.
  if p_key = 'authn.money_role_maturity_hours'
     and jsonb_typeof(p_value) = 'number'
     and ((p_value #>> '{}')::numeric < 24 or (p_value #>> '{}')::numeric > 72) then
    -- RLS MD-14 / RPC §1.1e: "the admissible range as 24-72 hours".
    raise exception 'precondition_failed: bad_value — authn.money_role_maturity_hours is outside MD-14''s admissible 24-72 hours';
  end if;
  if p_key = 'notify.announcement_hold_seconds'
     and jsonb_typeof(p_value) = 'number'
     and (p_value #>> '{}')::numeric < 120 then
    -- NOTIF §7.5: "seed 300 s, FLOOR 120 s".
    raise exception 'precondition_failed: bad_value — notify.announcement_hold_seconds is below NOTIF §7.5''s 120 s floor';
  end if;
  if p_key = 'authn.money_action_required_aal'
     and jsonb_typeof(p_value) = 'string'
     and (p_value #>> '{}') not in ('aal1','aal2') then
    raise exception 'precondition_failed: bad_value — authn.money_action_required_aal must be aal1|aal2';
  end if;
  if p_key = 'refund.scanned_atom_policy'
     and jsonb_typeof(p_value) = 'string'
     and (p_value #>> '{}') not in ('refuse','platform_review') then
    raise exception 'precondition_failed: bad_value — refund.scanned_atom_policy must be refuse|platform_review';
  end if;

  v_dual := p_key like 'refund.%' or p_key like 'payout.%' or p_key like 'authn.%'
         or p_key like 'comp.%'   or p_key like 'wallet.%' or p_key like 'credential.%'
         or p_key like 'door.session\_%';

  -- The declared polarity map. A key absent from it has NO declared polarity and
  -- therefore parks (when dual-controlled). Booleans, enums and every non-scalar
  -- are incomparable by construction and park for the same reason.
  v_polarity := case
    -- LOWER IS RESTRICTIVE: every one of these is a CEILING or a span whose
    -- reduction narrows what may happen without a second human.
    when p_key in ('refund.org_auto_execute_max_minor',
                   'refund.org_dual_control_max_minor',
                   'refund.buyer_self_service_max_minor',
                   'refund.buyer_self_service_window_hours',
                   'refund.platform_support_max_minor',
                   'payout.request_auto_max_minor',
                   -- payout.dual_control_min_minor is the amount ABOVE WHICH a
                   -- payout parks (MONEY §7.2), so RAISING it REMOVES payouts
                   -- from dual control. T-RPC-CFG-01 names this exact key:
                   -- "raising ... parks and inserts no version; lowering it
                   -- executes". It is a ceiling in disguise, not a floor.
                   'payout.dual_control_min_minor',
                   'comp.per_staff_step_up_max_units',
                   'authn.money_action_max_age_seconds',
                   'door.session_ttl_interval',
                   'door.session_absolute_max_interval',
                   'door.session_post_session_grace',
                   'credential.wallet_exp_skew',
                   'credential.wallet_default_span',
                   'credential.app_ttl_interval')          then 'lower_is_restrictive'
    -- HIGHER IS RESTRICTIVE: a longer cooldown, a longer probation and a longer
    -- maturity floor each narrow what may happen (RPC §20.2.1: "a longer
    -- probation"). comp.per_staff_step_up_window_hours is DELIBERATELY ABSENT:
    -- the window is the COUNTING period of the C39 insider-fraud gate, so
    -- shortening it counts fewer units and fires step-up LESS often — the
    -- corpus declares a direction only for its _max_units half (RLS §11.1
    -- AUTHZ-M8), so this key has NO declared polarity and takes §20.2.1's third
    -- arm: not comparable => PARK. Failing toward the approver is the whole
    -- point of that arm.
    when p_key in ('payout.destination_cooldown_hours',
                   'payout.destination_probation_days',
                   'authn.money_role_maturity_hours')      then 'higher_is_restrictive'
    -- FALSE IS RESTRICTIVE: a kill switch. WALLET §11.5b — "Setting
    -- wallet.apple.enabled := false ... needs ONE admin and no approval round.
    -- A kill switch that needs a quorum is not a kill switch."
    when p_key = 'wallet.apple.enabled'                    then 'false_is_restrictive'
    -- HIGHER AAL IS RESTRICTIVE: RPC §20.2.1 enumerates "a higher required AAL"
    -- among the restrictive directions by name, so raising it during a
    -- session-theft incident must execute in one transaction.
    when p_key = 'authn.money_action_required_aal'         then 'aal_higher_is_restrictive'
    else null
  end;

  v_restrictive := false;
  if v_polarity is not null
     and jsonb_typeof(v_cur_val) = 'number' and jsonb_typeof(p_value) = 'number' then
    v_old_num := (v_cur_val #>> '{}')::numeric;
    v_new_num := (p_value  #>> '{}')::numeric;
    v_restrictive := case v_polarity
                       when 'lower_is_restrictive'  then v_new_num < v_old_num
                       when 'higher_is_restrictive' then v_new_num > v_old_num
                     end;
  elsif v_polarity = 'false_is_restrictive'
     and jsonb_typeof(p_value) = 'boolean' then
    -- Pulling the switch is a tightening; flipping it on is the mandatory-
    -- dual-control write WALLET §11.5 describes.
    v_restrictive := (p_value = 'false'::jsonb);
  elsif v_polarity = 'aal_higher_is_restrictive'
     and jsonb_typeof(v_cur_val) in ('string','null') and jsonb_typeof(p_value) = 'string' then
    -- aal1 < aal2. An absent current value is the weakest state, so ANY named
    -- level is a tightening against it.
    v_restrictive := case
      when p_value #>> '{}' not in ('aal1','aal2') then false      -- unknown => park
      when jsonb_typeof(v_cur_val) = 'null'        then true
      else (p_value #>> '{}') > (v_cur_val #>> '{}')
    end;
  elsif v_polarity in ('lower_is_restrictive','higher_is_restrictive')
     and jsonb_typeof(v_cur_val) = 'string' and jsonb_typeof(p_value) = 'string' then
    begin
      v_restrictive := case v_polarity
        when 'lower_is_restrictive'
          then (p_value #>> '{}')::interval < (v_cur_val #>> '{}')::interval
        when 'higher_is_restrictive'
          then (p_value #>> '{}')::interval > (v_cur_val #>> '{}')::interval
      end;
    exception when others then
      v_restrictive := false;                       -- not comparable => park
    end;
  end if;

  -- The cross-config invariant (door §10.6): a Wallet token may never outlive the
  -- offline window any manifest could authorise. Validated whenever EITHER side
  -- changes, and the write is rejected otherwise. Evaluated INLINE rather than in
  -- a helper: a helper would be a catalog object the frozen closed world does not
  -- carry, and package parity is EXTRA = 0.
  if p_key in ('credential.wallet_default_span','credential.wallet_exp_skew',
               'door.manifest_ttl_interval') then
    begin
      select coalesce(
               case when p_key = 'credential.wallet_default_span' then (p_value #>> '{}')::interval end,
               (select (c.value #>> '{}')::interval from catalog.platform_config c
                 where c.key = 'credential.wallet_default_span'
                 order by c.version desc limit 1)),
             coalesce(
               case when p_key = 'credential.wallet_exp_skew' then (p_value #>> '{}')::interval end,
               (select (c.value #>> '{}')::interval from catalog.platform_config c
                 where c.key = 'credential.wallet_exp_skew'
                 order by c.version desc limit 1)),
             coalesce(
               case when p_key = 'door.manifest_ttl_interval' then (p_value #>> '{}')::interval end,
               (select (c.value #>> '{}')::interval from catalog.platform_config c
                 where c.key = 'door.manifest_ttl_interval'
                 order by c.version desc limit 1))
        into v_span, v_skew, v_ttl;
    exception when others then
      v_span := null; v_skew := null; v_ttl := null;    -- unparseable => reject
    end;
    -- An absent operand cannot be shown to satisfy the invariant, so it does not.
    if v_span is null or v_skew is null or v_ttl is null or v_span + v_skew > v_ttl then
      raise exception 'precondition_failed: bad_value — wallet_default_span + wallet_exp_skew must not exceed door.manifest_ttl_interval';
    end if;
  end if;

  if v_dual and not v_restrictive then
    insert into kernel.approval_request
           (action, required_approver_class, subject_kind, subject_id, org_id,
            payload, config_versions, requested_by, state, reason_code,
            expires_at, command_idempotency_key)
    values ('config.set_money_key', 'platform_admin', 'config_key',
            md5(p_key)::uuid, null,
            jsonb_build_object('key', p_key, 'proposed_value', p_value,
                               'current_value', v_cur_val),
            jsonb_build_object(p_key, v_cur_ver),
            v_uid, 'pending', trim(p_reason_code),
            now() + interval '72 hours', p_command_key)
    returning request_id into v_request_id;

    insert into kernel.admin_audit
           (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
    values (v_uid, 'config.money_key_proposed', 'config_key', md5(p_key)::uuid,
            trim(p_reason_code),
            jsonb_build_object('key', p_key, 'version', v_cur_ver, 'value', v_cur_val),
            jsonb_build_object('key', p_key, 'value', p_value));

    -- version UNCHANGED: the UI must say "waiting for a second approver",
    -- never "saved".
    return jsonb_build_object('status','parked','key',p_key,
                              'version',v_cur_ver,'request_id',v_request_id);
  end if;

  -- Direct path. visibility is COPIED FORWARD: set_platform_config may not change
  -- it — a function that can flip a key to public is a function that can publish
  -- the ceilings.
  insert into catalog.platform_config (key, version, value, visibility)
  values (p_key, v_cur_ver + 1, p_value, v_visibility);

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'config.change', 'config_key', md5(p_key)::uuid, trim(p_reason_code),
          jsonb_build_object('key', p_key, 'version', v_cur_ver, 'value', v_cur_val),
          jsonb_build_object('key', p_key, 'version', v_cur_ver + 1, 'value', p_value));

  return jsonb_build_object('status','ok','key',p_key,
                            'version',v_cur_ver + 1,'request_id',null);
end;
$$;

-- 6.2 catalog.set_resale_policy (RPC §20.2.2)
-- VERSIONING IS THE WHOLE CONTRACT: a policy change INSERTS a new version and
-- NEVER mutates a live one, because market.listing_native snapshots
-- (resale_policy_id, resale_policy_version) at listing creation. Retroactive
-- tightening is not offered — it would change the terms of an offer a seller
-- already published and a buyer may already have acted on.
create or replace function catalog.set_resale_policy(
  p_scope_kind text, p_scope_id uuid, p_policy jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_org_id    uuid;
  v_venue_id  uuid;
  v_event_id  uuid;
  v_allowed   boolean := false;
  v_mode      text;
  v_cap       integer;
  v_royalty   integer;
  v_ver       integer;
  v_policy_id uuid;
  v_cur       record;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_policy is null or jsonb_typeof(p_policy) <> 'object' then
    raise exception 'invalid_input: policy must be a json object';
  end if;
  -- The STORAGE scope set is schema §2.5's: venue | event. RPC §20.2.2's `org`
  -- has no column to land in (recorded errata).
  if p_scope_kind is null or p_scope_kind not in ('venue','event') then
    raise exception 'precondition_failed: bad_scope — scope_kind must be venue|event';
  end if;

  if p_scope_kind = 'venue' then
    v_venue_id := p_scope_id;
    select v.org_id into v_org_id from catalog.venue v where v.venue_id = p_scope_id;
  else
    v_event_id := p_scope_id;
    select e.org_id, e.venue_id into v_org_id, v_venue_id
      from catalog.event e where e.event_id = p_scope_id;
  end if;
  if v_org_id is null then
    raise exception 'not_found: % %', p_scope_kind, p_scope_id using errcode = 'P0002';
  end if;

  -- Authority covers the scope. RLS §11.1a and RPC §20.2.2 both name
  -- kernel.has_org_role_over_venue for this arm and forbid a re-inlined
  -- inheritance join (RM-3) — but that helper is authored in 080, so at 078 the
  -- org arm is resolved from the row's own denormalised org_id and the venue arm
  -- is deferred. PFA-10 §B records this second arm of the same seam; the comment
  -- that used to sit here claimed the opposite of what the code does.
  if kernel.has_org_role(v_org_id, array['org_owner','org_admin'])
     or kernel.is_platform(array['platform_admin']) then
    v_allowed := true;
  end if;
  if not v_allowed then                                    -- PFA-10 deferred arm
    v_allowed := kernel.has_venue_role(v_venue_id, array['venue_manager']);
  end if;
  if not v_allowed then
    raise exception 'insufficient_privilege: scope_out_of_authority'
      using errcode = '42501';
  end if;

  v_mode := p_policy ->> 'mode';
  if v_mode is null or v_mode not in ('off','transfers_only','fixed_cap',
                                      'face_value_queue','buy_now','auction','offer') then
    raise exception 'precondition_failed: bad_mode';
  end if;
  v_cap     := (p_policy ->> 'price_cap_bps')::integer;
  v_royalty := (p_policy ->> 'royalty_bps')::integer;
  if v_mode = 'fixed_cap' and v_cap is null then
    raise exception 'precondition_failed: bad_mode — fixed_cap requires price_cap_bps';
  end if;
  if v_cap is not null and (v_cap < 0 or v_cap > 10000) then
    raise exception 'precondition_failed: bad_value — price_cap_bps outside [0,10000]';
  end if;
  if v_royalty is not null and (v_royalty < 0 or v_royalty > 10000) then
    raise exception 'precondition_failed: bad_value — royalty_bps outside [0,10000]';
  end if;
  -- PFA-9 CLASS B: RPC §20.2.2's "platform ceiling read from
  -- catalog.platform_config" names no key anywhere in the frozen corpus. The
  -- structural ceiling (bps in [0,10000]) is enforced above; the configurable one
  -- is filed against 087 and is NOT invented here.

  select p.version, p.mode, p.price_cap_bps, p.royalty_bps
    into v_cur
    from catalog.resale_policy p
   -- Match on the column the scope ACTUALLY stores. The previous form filtered
   -- event-scoped rows on p.venue_id, which the coherence CHECK forces to NULL,
   -- so the lookup matched zero rows: every event-scoped call re-inserted
   -- version 1, noop_replay was unreachable and the FOR UPDATE locked nothing.
   where p.scope_kind = p_scope_kind
     and (   (p_scope_kind = 'venue' and p.venue_id = v_venue_id)
          or (p_scope_kind = 'event' and p.event_id = v_event_id))
   order by p.version desc
   limit 1
     for update;

  if found and v_cur.mode = v_mode
     and v_cur.price_cap_bps is not distinct from v_cap
     and v_cur.royalty_bps   is not distinct from v_royalty then
    -- Version churn on a no-op edit would make the snapshot references unreadable.
    return jsonb_build_object('status','noop_replay','version',v_cur.version);
  end if;

  v_ver := coalesce(v_cur.version, 0) + 1;

  insert into catalog.resale_policy
         (scope_kind, venue_id, event_id, mode, price_cap_bps, royalty_bps, version)
  values (p_scope_kind,
          case when p_scope_kind = 'venue' then v_venue_id end,
          case when p_scope_kind = 'event' then v_event_id end,
          v_mode, v_cap, v_royalty, v_ver)
  returning policy_id into v_policy_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'resale_policy.change', 'resale_policy', v_policy_id, 'policy_set',
          case when v_cur.version is null then null
               else jsonb_build_object('version', v_cur.version, 'mode', v_cur.mode) end,
          jsonb_build_object('version', v_ver, 'mode', v_mode));

  return jsonb_build_object('status','ok','policy_id',v_policy_id,'version',v_ver);
end;
$$;

-- =============================================================================
-- PART 7 — EXECUTE POSTURE (RLS §11; the 067 discipline: REVOKE from
-- public/anon/authenticated over the constant array, then GRANT by class)
-- =============================================================================

do $$
declare
  v_all constant text[] := array[
    'catalog.create_venue(uuid,text,text,text,text)',
    'catalog.approve_venue(uuid,text,text,text)',
    'catalog.update_venue(uuid,jsonb,text)',
    'catalog.create_event(uuid,text,jsonb,text)',
    'catalog.create_event_session(uuid,jsonb,text)',
    'catalog.update_event(uuid,jsonb,text)',
    'catalog.set_platform_config(text,jsonb,text,text)',
    'catalog.set_resale_policy(text,uuid,jsonb,text)',
    'catalog.effective_freeze_at(uuid)',
    'kernel.money_role_grant_matured(uuid)'
  ];
  -- Caller-authorized (EDGE-CALLER-JWT bound): every RPC whose body derives the
  -- actor from auth.uid(). effective_freeze_at and money_role_grant_matured are
  -- STABLE read predicates with an explicit authenticated grant (RLS §11.2).
  v_auth constant text[] := array[
    'catalog.create_venue(uuid,text,text,text,text)',
    'catalog.approve_venue(uuid,text,text,text)',
    'catalog.update_venue(uuid,jsonb,text)',
    'catalog.create_event(uuid,text,jsonb,text)',
    'catalog.create_event_session(uuid,jsonb,text)',
    'catalog.update_event(uuid,jsonb,text)',
    'catalog.set_platform_config(text,jsonb,text,text)',
    'catalog.set_resale_policy(text,uuid,jsonb,text)',
    'catalog.effective_freeze_at(uuid)',
    'kernel.money_role_grant_matured(uuid)'
  ];
  -- service_role holds NOTHING here. RLS §11.4 grants effective_freeze_at to
  -- `authenticated` and RPC §1.1e grants money_role_grant_matured to
  -- `authenticated`; neither carries a service_role class, definer callers in
  -- later packages reach both by ownership rather than by grant, and 076 gives
  -- service_role no USAGE on catalog or kernel anyway — so the grants this
  -- package previously issued were both uncontracted AND inert. A migration is
  -- also not a config change (plan §4), and RPC §20.2.1 forbids every
  -- service_role path on set_platform_config explicitly.
  v_svc constant text[] := '{}'::text[];
  f text;
begin
  foreach f in array v_all loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
  foreach f in array v_auth loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  foreach f in array v_svc loop
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;

-- =============================================================================
-- PART 8 — CONFIG SEEDS (41 keys at version 1; 8 public / 33 restricted)
--
-- "The production-OFF anchor" — the single auditable answer to "is every gate
-- seeded and every flag OFF?". Values are seeded here; FLIPS ARE NEVER A
-- MIGRATION (plan §4).
--
-- READ THIS BEFORE CHANGING A VALUE BELOW:
--   * a JSON `null` value is DELIBERATE and is the frozen
--     retention.backup_window_days pattern (PFA-9): the ROW exists so
--     set_platform_config's registry precondition holds, the VALUE is absent so
--     every X-12 consumer takes the RESTRICTIVE reading. It is not an oversight
--     and it must not be "filled in" without the owner decision named beside it.
--   * PROVISIONAL marks a value the corpus states but the owner has not ruled.
-- =============================================================================

insert into catalog.platform_config (key, version, value, visibility) values
  -- ---- feature flags (public; the three native gates + the two plane switches)
  ('feature.native_issuance_enabled',        1, 'false'::jsonb,  'public'),      -- Gate P / 15.A
  ('feature.native_scanning_enabled',        1, 'false'::jsonb,  'public'),      -- 2B door gate
  ('feature.native_resale_enabled',          1, 'false'::jsonb,  'public'),      -- Gate M + 2C
  ('wallet.apple.enabled',                   1, 'false'::jsonb,  'public'),      -- WALLET §11.5 kill switch
  ('notify.announcements_enabled',           1, 'false'::jsonb,  'public'),      -- NOTIF §7.4 kill switch
  -- ---- credential client spans (public: a client must honour them to render a pass)
  ('credential.wallet_exp_skew',             1, '"6 hours"'::jsonb,  'public'),
  ('credential.wallet_default_span',         1, '"6 hours"'::jsonb,  'public'),  -- PFA-7 (frozen text said 12h)
  ('credential.app_ttl_interval',            1, '"4 hours"'::jsonb,  'public'),
  -- ---- wallet operational thresholds (restricted: not client spans, PFA-8)
  ('wallet.apple.push_retry_max',            1, '5'::jsonb,          'restricted'),
  ('wallet.apple.cert_expiry_warn_interval', 1, '"45 days"'::jsonb,  'restricted'),
  -- ---- door (restricted: they state how long a door may operate on stale data)
  ('door.implicit_freeze_offset_interval',   1, '"0 minutes"'::jsonb,'restricted'),
  ('door.manifest_ttl_interval',             1, '"12 hours"'::jsonb, 'restricted'),
  ('door.manifest_early_open_window',        1, '"12 hours"'::jsonb, 'restricted'),
  ('door.max_override_interval',             1, '"2 hours"'::jsonb,  'restricted'),
  ('door.session_ttl_interval',              1, '"12 hours"'::jsonb, 'restricted'),
  ('door.session_absolute_max_interval',     1, '"24 hours"'::jsonb, 'restricted'),
  ('door.session_post_session_grace',        1, '"4 hours"'::jsonb,  'restricted'),
  -- ---- money: refund (MONEY §7.2). Every *_max_minor is a CUMULATIVE ceiling.
  --      The NUMBERS are owner decision D-3 and are NOT invented here.
  ('refund.org_auto_execute_max_minor',      1, 'null'::jsonb,       'restricted'),  -- D-3
  ('refund.org_dual_control_max_minor',      1, 'null'::jsonb,       'restricted'),  -- D-3
  ('refund.request_ttl_hours',               1, 'null'::jsonb,       'restricted'),  -- D-3
  ('refund.scanned_atom_policy',             1, '"platform_review"'::jsonb, 'restricted'), -- PROVISIONAL (MONEY §7.2 recommended default)
  ('refund.buyer_self_service_window_hours', 1, 'null'::jsonb,       'restricted'),  -- D-3
  ('refund.buyer_self_service_max_minor',    1, 'null'::jsonb,       'restricted'),  -- D-3
  ('refund.buyer_fee_refundable',            1, 'null'::jsonb,       'restricted'),  -- D-3
  ('refund.platform_support_max_minor',      1, 'null'::jsonb,       'restricted'),  -- D-3; X-12 fail-to-safe: support may approve NOTHING
  -- ---- money: payout (MONEY §7.2)
  ('payout.destination_cooldown_hours',      1, 'null'::jsonb,       'restricted'),  -- D-3
  ('payout.destination_probation_days',      1, 'null'::jsonb,       'restricted'),  -- D-3
  ('payout.request_auto_max_minor',          1, 'null'::jsonb,       'restricted'),  -- D-3 / MB-1b
  ('payout.dual_control_min_minor',          1, 'null'::jsonb,       'restricted'),  -- D-3 / MB-1b
  -- ---- money: authn (MONEY §7.2 + schema §1.13.4)
  ('authn.money_action_max_age_seconds',     1, 'null'::jsonb,       'restricted'),  -- D-3
  ('authn.money_action_required_aal',        1, 'null'::jsonb,       'restricted'),  -- D-3; absent => step-up demanded
  ('authn.money_role_maturity_hours',        1, '72'::jsonb,         'restricted'),  -- PROVISIONAL: MD-14 range 24-72h, RESTRICTIVE end (RPC §1.1e)
  -- ---- comp (C39 / AUTHZ-M8; X-12 fail-to-safe: absent => EVERY comp needs step-up)
  ('comp.per_staff_step_up_max_units',       1, 'null'::jsonb,       'restricted'),
  ('comp.per_staff_step_up_window_hours',    1, 'null'::jsonb,       'restricted'),
  -- ---- notify announcement thresholds (NOTIF §7.3/§7.4)
  ('notify.announcement_hold_seconds',       1, '300'::jsonb,        'restricted'),  -- PROVISIONAL (ODR-56 silence; floor 120)
  ('notify.announcement_dual_control_threshold', 1, '500'::jsonb,    'restricted'),  -- PROVISIONAL (ODR-56 silence)
  ('notify.announcement_max_per_session',    1, '3'::jsonb,          'restricted'),
  ('notify.announcement_min_interval_seconds', 1, '1800'::jsonb,     'restricted'),
  -- ---- CRM (X-9). The unnamed rate-limit/cap keys stay with 087 (PFA-9 CLASS B).
  ('crm_export.constraint_set_version',      1, '"demographics-constraints/X1-X9@v1"'::jsonb, 'restricted'),
  -- ---- native Buy-Now reservation TTL (R-37 / OR-22). SEEDING IT ACTIVATES
  --      NOTHING: the rail is market.* in 088 and is gated by
  --      feature.native_resale_enabled, seeded false above.
  ('resale.buy_now_reservation_ttl_minutes', 1, '10'::jsonb,         'restricted'),
  -- ---- retention: ABSENT BY DESIGN (DEMOG §8.5 / OR-16; freeze red-team F-8).
  --      The value is OPS VERIFICATION REQUIRED. Key-or-value absent =>
  --      purge_after = NULL = NEVER PURGEABLE. This row is the auditable carrier
  --      of that absence; DO NOT FILL IT IN without verified backup/PITR reality.
  ('retention.backup_window_days',           1, 'null'::jsonb,       'restricted')
on conflict (key, version) do nothing;

-- =============================================================================
-- PART 9 — THE TWO PLATFORM SENTINEL IDENTITIES (schema §1.16, defect MB-5)
--
-- kernel.ticket_ownership_log.to_identity and .actor_identity are NOT NULL
-- FK->auth.users and are relied on by kernel.void_ticket_atom and every custody
-- sweep. No package seeded either row, so the first refund would fail 23503 on
-- to_identity and every cron sweep on actor_identity.
--
-- TWO sentinels, not one and not three: SN-VOID answers "who holds this atom
-- now", SN-SYSTEM answers "who did this". Merging them would make an
-- actor_identity filter return every void ever performed, including every
-- human-initiated refund.
--
-- 00000000-0000-0000-0000-000000000000 (the 019 anonymization sentinel) IS NOT
-- REUSABLE and MUST NOT APPEAR in kernel.tickets.current_owner_id or in any
-- kernel.ticket_ownership_log identity column, ever: it means "a person who
-- asked to be forgotten", it renders as "Deleted User" on the dispute surface,
-- it is owned by a public-schema deletion path outside the kernel's write
-- authority, and it is person-shaped.
-- =============================================================================

insert into auth.users
  (id, email, raw_app_meta_data, raw_user_meta_data, role, instance_id, aud,
   encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000000f0', 'void@snatchit.internal',
   '{"provider":"sentinel","providers":["sentinel"]}', '{}',
   'sentinel', '00000000-0000-0000-0000-000000000000', 'authenticated',
   null, null, now(), now()),
  ('00000000-0000-0000-0000-0000000000f1', 'system@snatchit.internal',
   '{"provider":"sentinel","providers":["sentinel"]}', '{}',
   'sentinel', '00000000-0000-0000-0000-000000000000', 'authenticated',
   null, null, now(), now())
on conflict (id) do nothing;

-- Production's handle_new_user trigger may or may not fire on the INSERT above
-- (019's own comment says exactly this), so the label is inserted explicitly —
-- otherwise the Transfer View renders a blank where it must render
-- "Voided - returned to issuer".
-- ON CONFLICT DO **UPDATE**, and the deviation from §1.16's "ON CONFLICT DO
-- NOTHING, exactly as 019 does" is forced and recorded (078 errata): the
-- production trigger `on_auth_user_created` fires on the auth.users INSERT above
-- and creates the profiles row FIRST, with a NULL display_name — so DO NOTHING
-- makes the explicit label a no-op and the Transfer View renders the blank
-- §1.16 says it must never render. 019's own comment anticipates the race; its
-- resolution does not survive it. The UPDATE is scoped to display_name, touches
-- only the two sentinel ids, and converges on replay, so the replay-safety
-- property DO NOTHING was chosen FOR is preserved in full.
insert into public.profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000000000f0', 'Voided — returned to issuer'),
  ('00000000-0000-0000-0000-0000000000f1', 'Snatch It (automated)')
on conflict (id) do update
  set display_name = excluded.display_name
 where public.profiles.display_name is distinct from excluded.display_name;

-- A kernel.identity_ext row for each, so every kernel-side identity join is total
-- and no reader has to special-case a missing extension row.
insert into kernel.identity_ext (identity_id)
values
  ('00000000-0000-0000-0000-0000000000f0'),
  ('00000000-0000-0000-0000-0000000000f1')
on conflict (identity_id) do nothing;

-- NEITHER SENTINEL IS EVER GRANTED a kernel.platform_role or a kernel.org_member
-- row, and is_platform / has_org_role / has_venue_role return false for both.
-- Asserted POSITIVELY in the suite, because an identity that appears in the audit
-- ledger as an actor is exactly the one someone later "fixes" by granting it a
-- role so a query stops erroring.

-- =============================================================================
-- PART 11 — HARDENING-1 (cross-package, owner-authorized 2026-08-31)
--
-- THIS IS NOT A PACKAGE-078 ARCHITECTURE OBJECT. kernel.sweep_deletion_pending is
-- owned by package 077 and its migration is immutable; this is a CREATE OR
-- REPLACE of the BODY ONLY, adding the one recorded isolation guard at the
-- recorded insertion point and changing nothing else. The sweep is NOT a SEAM-2
-- hook, so the body-replacement rationale is stated rather than assumed: merge
-- review C of PR #30 live-reproduced the zero-owner write skew by wrapping the
-- sweep in REPEATABLE READ, the guard closes it structurally, and the owner
-- ruled that "the carrier must make the recorded guard and witness executable
-- before any supported caller may invoke kernel.sweep_deletion_pending outside
-- its current READ COMMITTED-only operating contract"
-- (docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md, HARDENING-1 +
-- its OWNER APPROVAL block). 078 is the next band package, it already depends on
-- 077, the guard introduces no relation and therefore no 079+ dependency, and it
-- requires none of 079's deletion-blocker bodies. Signature, parameter names and
-- return type are unchanged.
-- =============================================================================

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
  -- HARDENING-1 (merge review C of PR #30, recorded in the 077 errata): the
  -- BP-11 re-check-under-org-locks below is correct ONLY under READ COMMITTED,
  -- where each statement takes a fresh snapshot — under REPEATABLE READ the
  -- re-check reads the transaction snapshot and the zero-owner write skew
  -- returns (live-reproduced). The sweep's sole contracted caller is the cron
  -- register entry under default isolation; this guard makes the dependency
  -- structural instead of conventional.
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'sweep_deletion_pending requires read committed isolation (the BP-11 re-check depends on per-statement snapshots)';
  end if;

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

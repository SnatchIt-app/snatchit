-- ============================================================================
-- 081_venue_inventory.sql
-- Phase-2 package 081 (PHASE E — venue ticket-type / inventory substrate).
--
-- Frozen sources: plan §8/081 + PHASE E body; schema §3.1-§3.5, §3.3.1 (the
-- oversell proof); RPC §4.2 (publish_event), §5.1-§5.5, §20.3.1/§20.3.2/§20.3.3
-- (G-24 hold sweep); RLS §9.1-§9.5, §16.10; CRON_SCHEDULE_REGISTER row 081;
-- OR-17 rider (F-1 on reserve_primary_inventory); registry depends_on
-- {077,078,080} (080 = has_venue_role for RLS).
--
-- The oversell-safe substrate: the priced product (ticket_type), the
-- authoritative capacity counter (inventory_batch, C27), the AO audit ledger
-- (inventory_movement), and time-boxed holds (inventory_hold) with the
-- LOAD-BEARING expiry sweep (G-24). SHARDING (the MVP-optional hot-row
-- mitigation, schema §3.3) is DEFERRED — create_inventory_batch refuses
-- shard_count>0; the aggregate batch counter delivers full oversell-safety and
-- there is no thundering herd to relieve while native issuance is dark (E-32).
--
-- NATIVE ISSUANCE STAYS DARK: feature.native_issuance_enabled seeds false;
-- the real-draw path (reserve/create-hold) refuses feature_disabled while it is
-- false, and NO mint engine exists here (kernel.issue_ticket_atoms moved to 083,
-- C114). The substrate alone cannot write a kernel.tickets row.
--
-- 081 owns NO SEAM-2 blocker replacement (deletion_blockers_orders is 082's).
-- It hosts ONE F-clause: F-1 on reserve_primary_inventory. venue.inventory_unit
-- is NOT created (EXT/C42). The kernel.tickets ticket_type_id FK is 084's adopt
-- step, NOT here.
-- ============================================================================

-- ============================================================================
-- PART 1 — venue.ticket_type (schema §3.1)
-- ============================================================================

create table if not exists venue.ticket_type (
  ticket_type_id uuid primary key default gen_random_uuid(),
  event_id       uuid not null references catalog.event(event_id) on delete restrict,
  kind           text not null check (kind in ('admission','table')),
  name           text not null,
  price_minor    integer not null check (price_minor > 0),   -- server-authoritative snapshot
  currency       text not null default 'USD',
  visibility     text not null default 'hidden'
                 check (visibility in ('hidden','public','door_only')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint ticket_type_event_name_uq unique (event_id, name)
);
create index if not exists ticket_type_event_idx on venue.ticket_type (event_id);

drop trigger if exists tg_ticket_type_set_updated_at on venue.ticket_type;
create trigger tg_ticket_type_set_updated_at
  before update on venue.ticket_type
  for each row execute function kernel.set_updated_at();

-- ============================================================================
-- PART 2 — venue.inventory_batch (schema §3.2; the C27 authoritative counter)
-- ============================================================================

create table if not exists venue.inventory_batch (
  batch_id         uuid primary key default gen_random_uuid(),
  ticket_type_id   uuid not null references venue.ticket_type(ticket_type_id) on delete restrict,
  event_session_id uuid not null references catalog.event_session(session_id) on delete restrict,
  release_kind     text not null
                   check (release_kind in ('public_sale','promoter_hold','comp','door','presale')),
  capacity         integer not null,
  held             integer not null default 0,
  sold             integer not null default 0,
  is_sharded       boolean not null default false,
  -- remaining is COMPUTED, never a stored writable value (C27: one authoritative
  -- counter, the rest derived). Even when sharded the functions keep held/sold
  -- as the running sum of the shards, so this holds in both modes.
  remaining        integer generated always as (capacity - held - sold) stored,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  -- THE OVERSELL GUARD (C4/C27): non-negativity, NOT a sum=capacity trigger.
  constraint inventory_batch_oversell_check
    check (held >= 0 and sold >= 0 and held + sold <= capacity)
);
create index if not exists inventory_batch_avail_idx
  on venue.inventory_batch (event_session_id, ticket_type_id);
create index if not exists inventory_batch_type_idx on venue.inventory_batch (ticket_type_id);

drop trigger if exists tg_inventory_batch_set_updated_at on venue.inventory_batch;
create trigger tg_inventory_batch_set_updated_at
  before update on venue.inventory_batch
  for each row execute function kernel.set_updated_at();

-- ============================================================================
-- PART 3 — venue.inventory_batch_shard (schema §3.3; C4/C22 sub-counter)
-- ============================================================================

create table if not exists venue.inventory_batch_shard (
  batch_id   uuid not null references venue.inventory_batch(batch_id) on delete cascade,
  shard_no   integer not null,
  capacity   integer not null,
  held       integer not null default 0,
  sold       integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint inventory_batch_shard_pk primary key (batch_id, shard_no),
  constraint inventory_batch_shard_oversell_check
    check (held >= 0 and sold >= 0 and held + sold <= capacity)
);

drop trigger if exists tg_inventory_batch_shard_set_updated_at on venue.inventory_batch_shard;
create trigger tg_inventory_batch_shard_set_updated_at
  before update on venue.inventory_batch_shard
  for each row execute function kernel.set_updated_at();

-- ============================================================================
-- PART 4 — venue.inventory_movement (schema §3.4; AO audit ledger)
-- ============================================================================

create table if not exists venue.inventory_movement (
  id             uuid primary key default gen_random_uuid(),
  batch_id       uuid not null references venue.inventory_batch(batch_id) on delete restrict,
  shard_no       integer,
  movement_kind  text not null
                 check (movement_kind in ('hold','release','issue','void_return','capacity_change')),
  delta_held     integer not null default 0,
  delta_sold     integer not null default 0,
  cause          text not null check (cause in
                   ('issue','primary_sale','comp','door_sale','p2p_transfer','market_sale',
                    'auction_sale','admin_action','refund_void','import','promoter_commission',
                    'settlement','chargeback')),
  cause_ref      uuid not null,
  actor_identity uuid references auth.users(id) on delete restrict,
  occurred_at    timestamptz not null default now(),
  created_at     timestamptz not null default now(),
  -- the C26 idempotency shape: a replayed reserve/issue does not double-log.
  constraint inventory_movement_cause_uq unique (cause, cause_ref, batch_id, movement_kind)
);
create index if not exists inventory_movement_batch_idx on venue.inventory_movement (batch_id);
create index if not exists inventory_movement_cause_ref_idx on venue.inventory_movement (cause_ref);

-- AO: INSERT-only (guard trigger + REVOKE below).
drop trigger if exists tg_inventory_movement_append_only on venue.inventory_movement;
create trigger tg_inventory_movement_append_only
  before update or delete on venue.inventory_movement
  for each row execute function kernel.raise_append_only();

-- ============================================================================
-- PART 5 — venue.inventory_hold (schema §3.5)
-- ============================================================================

create table if not exists venue.inventory_hold (
  hold_id                 uuid primary key default gen_random_uuid(),
  batch_id                uuid not null references venue.inventory_batch(batch_id) on delete restrict,
  shard_no                integer,
  identity_id             uuid not null references auth.users(id) on delete restrict,
  quantity                integer not null check (quantity > 0),
  status                  text not null default 'active'
                          check (status in ('active','converted','released','expired')),
  expires_at              timestamptz not null,           -- server-max TTL, never client-set
  command_idempotency_key text not null,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  constraint inventory_hold_command_uq unique (identity_id, command_idempotency_key)
);
-- the hot-path of the G-24 sweep (§3.5.1): the index existed for a sweep no
-- package created; 081 builds both the index AND the sweep.
create index if not exists inventory_hold_expiry_idx
  on venue.inventory_hold (expires_at) where status = 'active';
create index if not exists inventory_hold_identity_status_idx
  on venue.inventory_hold (identity_id, status);

drop trigger if exists tg_inventory_hold_set_updated_at on venue.inventory_hold;
create trigger tg_inventory_hold_set_updated_at
  before update on venue.inventory_hold
  for each row execute function kernel.set_updated_at();

-- ============================================================================
-- PART 6 — venue.create_ticket_type (RPC §5.1)
-- ============================================================================

create or replace function venue.create_ticket_type(
  p_event_id uuid, p_kind text, p_name text, p_price_minor integer,
  p_visibility text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid;
  v_org_id  uuid;
  v_venue   uuid;
  v_status  text;
  v_tt_id   uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_kind not in ('admission','table') then
    raise exception 'invalid_input: bad kind %', p_kind;
  end if;
  if p_visibility not in ('hidden','public','door_only') then
    raise exception 'invalid_input: bad visibility %', p_visibility;
  end if;
  if p_price_minor is null or p_price_minor <= 0 then
    raise exception 'precondition_failed: bad_price';
  end if;

  select e.org_id, e.venue_id, e.status into v_org_id, v_venue, v_status
    from catalog.event e where e.event_id = p_event_id;
  if v_org_id is null then
    raise exception 'not_found: event %', p_event_id using errcode = 'P0002';
  end if;
  if v_status in ('completed','cancelled') then
    raise exception 'precondition_failed: event_terminal';
  end if;

  -- RM-3: org->venue inheritance is expressed ONLY through the sanctioned
  -- helper, never a direct has_org_role on the denormalised event.org_id
  -- (which IS the venue's org). Reconciles §5.1's has_org_role spelling to the
  -- ratified helper-derived discipline; functionally identical (E-31 note).
  if not (kernel.has_org_role_over_venue(v_venue, array['org_owner','org_admin'])
          or kernel.has_venue_role(v_venue, array['venue_manager'])) then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  insert into venue.ticket_type (event_id, kind, name, price_minor, visibility)
  values (p_event_id, p_kind, p_name, p_price_minor, coalesce(p_visibility,'hidden'))
  returning ticket_type_id into v_tt_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'ticket_type.create', 'ticket_type', v_tt_id, 'self_service',
          null, jsonb_build_object('event_id', p_event_id, 'kind', p_kind,
                                   'price_minor', p_price_minor, 'visibility', p_visibility));

  return jsonb_build_object('status','ok','ticket_type_id',v_tt_id);
exception when unique_violation then
  raise exception 'precondition_failed: duplicate_name';
end;
$$;

-- ============================================================================
-- PART 7 — venue.set_ticket_type_price (RPC §20.3.1; C9 live-recheck)
-- ============================================================================

create or replace function venue.set_ticket_type_price(
  p_ticket_type_id uuid, p_price_minor integer, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid;
  v_org_id uuid;
  v_venue  uuid;
  v_status text;
  v_old    integer;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_price_minor is null or p_price_minor <= 0 then
    raise exception 'precondition_failed: bad_price';
  end if;
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: reason_required';
  end if;

  select tt.price_minor, e.org_id, e.venue_id, e.status
    into v_old, v_org_id, v_venue, v_status
    from venue.ticket_type tt
    join catalog.event e on e.event_id = tt.event_id
   where tt.ticket_type_id = p_ticket_type_id
   for update of tt;                                    -- rank 2, Inventory class
  if v_org_id is null then
    raise exception 'not_found: ticket type %', p_ticket_type_id using errcode = 'P0002';
  end if;
  if v_status in ('completed','cancelled') then
    raise exception 'precondition_failed: event_terminal';
  end if;

  -- C9 money-consequential live-table recheck (never a JWT claim); RM-3 helper.
  if not (kernel.has_org_role_over_venue(v_venue, array['org_owner','org_admin'])
          or kernel.has_venue_role(v_venue, array['venue_manager'])) then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  if v_old = p_price_minor then
    return jsonb_build_object('status','noop_replay','ticket_type_id',p_ticket_type_id,
                              'price_minor',v_old);
  end if;

  -- Binds only orders created AFTER it — orders snapshot unit_price_minor at
  -- checkout (§6.1), so this cannot re-price a pending/paid order, a refund or a
  -- settlement line. That property lives in venue.order_item (082), not here.
  update venue.ticket_type set price_minor = p_price_minor, updated_at = now()
   where ticket_type_id = p_ticket_type_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'ticket_type.price_change', 'ticket_type', p_ticket_type_id, p_reason_code,
          jsonb_build_object('price_minor', v_old),
          jsonb_build_object('price_minor', p_price_minor));

  return jsonb_build_object('status','ok','ticket_type_id',p_ticket_type_id,
                            'price_minor',p_price_minor);
end;
$$;

-- ============================================================================
-- PART 8 — venue.create_inventory_batch (RPC §5.2)
-- ============================================================================

create or replace function venue.create_inventory_batch(
  p_ticket_type_id uuid, p_session_id uuid, p_release_kind text,
  p_capacity integer, p_shard_count integer, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_org_id    uuid;
  v_venue     uuid;
  v_tt_event  uuid;
  v_s_event   uuid;
  v_batch_id  uuid;
  v_evstatus  text;
  v_sharded   boolean;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_release_kind not in ('public_sale','promoter_hold','comp','door','presale') then
    raise exception 'invalid_input: bad release_kind %', p_release_kind;
  end if;
  if p_capacity is null or p_capacity <= 0 then
    raise exception 'precondition_failed: bad_capacity';
  end if;

  -- Sharding is deferred (E-32): the aggregate counter is oversell-safe and no
  -- contention exists while native issuance is dark. Refuse rather than create
  -- inert shard rows that would break the §3.3 Σshard==batch reconciliation.
  if coalesce(p_shard_count, 0) > 0 then
    raise exception 'precondition_failed: sharding_deferred (MVP ships the unsharded counter; schema §3.3 is MVP-optional)';
  end if;

  select tt.event_id, e.org_id, e.venue_id, e.status into v_tt_event, v_org_id, v_venue, v_evstatus
    from venue.ticket_type tt join catalog.event e on e.event_id = tt.event_id
   where tt.ticket_type_id = p_ticket_type_id;
  if v_tt_event is null then
    raise exception 'not_found: ticket type %', p_ticket_type_id using errcode = 'P0002';
  end if;
  -- refuse a batch on a terminal event (symmetry with create_ticket_type; a
  -- batch on a completed/cancelled event can never reach on_sale anyway).
  if v_evstatus in ('completed','cancelled') then
    raise exception 'precondition_failed: event_terminal';
  end if;
  select s.event_id into v_s_event from catalog.event_session s where s.session_id = p_session_id;
  if v_s_event is null then
    raise exception 'not_found: session %', p_session_id using errcode = 'P0002';
  end if;
  -- type & session must belong to the SAME event.
  if v_tt_event <> v_s_event then
    raise exception 'precondition_failed: type_session_event_mismatch';
  end if;

  if not (kernel.has_org_role_over_venue(v_venue, array['org_owner','org_admin'])
          or kernel.has_venue_role(v_venue, array['venue_manager'])) then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  -- sharding deferred: is_sharded is always false, no shard rows (E-32).
  v_sharded := false;
  insert into venue.inventory_batch
         (ticket_type_id, event_session_id, release_kind, capacity, held, sold, is_sharded)
  values (p_ticket_type_id, p_session_id, p_release_kind, p_capacity, 0, 0, v_sharded)
  returning batch_id into v_batch_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'inventory.batch.create', 'inventory_batch', v_batch_id, 'self_service',
          null, jsonb_build_object('ticket_type_id', p_ticket_type_id, 'session_id', p_session_id,
                                   'release_kind', p_release_kind, 'capacity', p_capacity,
                                   'shards', coalesce(p_shard_count,0)));

  return jsonb_build_object('status','ok','batch_id',v_batch_id,
                            'capacity',p_capacity,'is_sharded',v_sharded);
end;
$$;

-- ============================================================================
-- PART 9 — venue.set_batch_capacity (RPC §20.3.2; U-8/G-12)
-- ============================================================================

create or replace function venue.set_batch_capacity(
  p_batch_id uuid, p_new_capacity integer, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid;
  v_org_id   uuid;
  v_venue    uuid;
  v_cap      integer;
  v_held     integer;
  v_sold     integer;
  v_sharded  boolean;
  v_delta    integer;
  v_room     integer;
  v_take     integer;
  r          record;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: reason_required';
  end if;
  if p_new_capacity is null or p_new_capacity <= 0 then
    raise exception 'precondition_failed: bad_capacity';
  end if;

  select b.capacity, b.held, b.sold, b.is_sharded, e.org_id, e.venue_id
    into v_cap, v_held, v_sold, v_sharded, v_org_id, v_venue
    from venue.inventory_batch b
    join venue.ticket_type tt on tt.ticket_type_id = b.ticket_type_id
    join catalog.event e on e.event_id = tt.event_id
   where b.batch_id = p_batch_id
   for update of b;                                     -- rank 2
  if v_org_id is null then
    raise exception 'not_found: batch %', p_batch_id using errcode = 'P0002';
  end if;

  -- Authority: venue_manager OR org_owner/admin. NO platform arm — a platform
  -- capacity edit on a venue's room is not a support action (§20.3.2).
  if not (kernel.has_org_role_over_venue(v_venue, array['org_owner','org_admin'])
          or kernel.has_venue_role(v_venue, array['venue_manager'])) then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  -- THE REFUSAL FLOOR (C27, absolute): capacity may never drop below what is
  -- already committed. No force flag, no override role, no platform bypass.
  if p_new_capacity < v_held + v_sold then
    raise exception 'precondition_failed: below_committed (new=% < held+sold=%)',
      p_new_capacity, v_held + v_sold;
  end if;

  if v_cap = p_new_capacity then
    return jsonb_build_object('status','noop_replay','batch_id',p_batch_id,
                              'capacity',v_cap,'held',v_held,'sold',v_sold,
                              'remaining',v_cap - v_held - v_sold);
  end if;

  v_delta := p_new_capacity - v_cap;
  if v_sharded then
    if v_delta > 0 then
      -- grow: put the whole delta on the lowest shard (Σ shard.capacity stays = batch).
      update venue.inventory_batch_shard
         set capacity = capacity + v_delta, updated_at = now()
       where batch_id = p_batch_id and shard_no = (
         select min(shard_no) from venue.inventory_batch_shard where batch_id = p_batch_id);
    else
      -- shrink: draw down ascending shard_no, only from each shard's own room
      -- (capacity - held - sold); raise if the distribution can't be satisfied.
      v_take := -v_delta;
      for r in select shard_no, capacity, held, sold from venue.inventory_batch_shard
                where batch_id = p_batch_id order by shard_no for update loop
        exit when v_take = 0;
        v_room := r.capacity - r.held - r.sold;
        if v_room > 0 then
          declare v_cut integer := least(v_room, v_take);
          begin
            update venue.inventory_batch_shard set capacity = capacity - v_cut, updated_at = now()
             where batch_id = p_batch_id and shard_no = r.shard_no;
            v_take := v_take - v_cut;
          end;
        end if;
      end loop;
      if v_take > 0 then
        raise exception 'precondition_failed: shard_distribution_unsatisfiable';
      end if;
    end if;
  end if;

  update venue.inventory_batch set capacity = p_new_capacity, updated_at = now()
   where batch_id = p_batch_id;

  -- C27: every capacity delta has a ledger row — an edit IS a delta.
  insert into venue.inventory_movement
         (batch_id, movement_kind, delta_held, delta_sold, cause, cause_ref, actor_identity)
  values (p_batch_id, 'capacity_change', 0, 0, 'admin_action', gen_random_uuid(), v_uid);

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'inventory.capacity.change', 'inventory_batch', p_batch_id, p_reason_code,
          jsonb_build_object('capacity', v_cap), jsonb_build_object('capacity', p_new_capacity));

  return jsonb_build_object('status','ok','batch_id',p_batch_id,'capacity',p_new_capacity,
                            'held',v_held,'sold',v_sold,'remaining',p_new_capacity - v_held - v_sold);
end;
$$;

-- ============================================================================
-- PART 10 — venue.reserve_primary_inventory (RPC §5.3; F-1 host; C27 choke-point)
-- ============================================================================

create or replace function venue.reserve_primary_inventory(
  p_batch_id uuid, p_quantity integer, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid;
  v_flag     boolean;
  v_held     integer;
  v_cap      integer;
  v_sold     integer;
  v_s_status   text;
  v_sess_status text;
  v_ttl      interval;
  v_cap_max  integer;
  v_active   integer;
  v_hold_id  uuid;
  v_expires  timestamptz;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'precondition_failed: bad_quantity';
  end if;

  -- OR-17 F-1: a pending-deletion caller may not ACQUIRE new inventory.
  if kernel.is_deletion_pending(v_uid) then
    raise exception 'precondition_failed: deletion_pending';
  end if;

  -- Idempotency short-circuit (§5.3): a replay of a SUCCEEDED reserve returns
  -- the original hold, not oversell_rejected (the caller's own committed hold
  -- fills the batch, so the oversell gate below would misreport it).
  declare v_ex_hold uuid; v_ex_exp timestamptz;
  begin
    select hold_id, expires_at into v_ex_hold, v_ex_exp
      from venue.inventory_hold
     where identity_id = v_uid and command_idempotency_key = p_command_key;
    if v_ex_hold is not null then
      return jsonb_build_object('status','idempotency_replay','hold_id',v_ex_hold,
                                'expires_at',v_ex_exp);
    end if;
  end;

  -- NATIVE ISSUANCE GATE (§4): real draws are gated behind the flag, false for
  -- the entire life of 081. The flag is checked BEFORE any counter mutation, so
  -- the substrate provably cannot draw while native issuance is dark.
  select (c.value #>> '{}')::boolean into v_flag
    from catalog.platform_config c
   where c.key = 'feature.native_issuance_enabled'
   order by c.version desc limit 1;
  if not coalesce(v_flag, false) then
    raise exception 'precondition_failed: feature_disabled';
  end if;

  -- the batch's EVENT must be on_sale/live AND its SESSION must not be terminal
  -- (§5.3: "batch's session/event on_sale/live"; a session carries its own
  -- cancelled/completed state, 078).
  select e.status, s.status into v_s_status, v_sess_status
    from venue.inventory_batch b
    join venue.ticket_type tt on tt.ticket_type_id = b.ticket_type_id
    join catalog.event e on e.event_id = tt.event_id
    join catalog.event_session s on s.session_id = b.event_session_id
   where b.batch_id = p_batch_id;
  if v_s_status is null then
    raise exception 'not_found: batch %', p_batch_id using errcode = 'P0002';
  end if;
  if v_s_status not in ('on_sale','live') then
    raise exception 'precondition_failed: not_on_sale';
  end if;
  if v_sess_status in ('completed','cancelled') then
    raise exception 'precondition_failed: session_terminal';
  end if;

  -- Per-user active-hold cap (C5) via an advisory xact lock on the identity —
  -- NEVER a COUNT(*)<limit trigger (write-skew). The cap key is a PFA-9 CLASS A
  -- key with NO frozen spelling (erratum E-28): unseeded => fail-to-ZERO
  -- (AUTHZ-M8 precedent), so a missing seed refuses every reserve loudly rather
  -- than admitting unbounded holds silently. Unreachable while the flag is off.
  perform pg_advisory_xact_lock(hashtext('inv_hold_cap:'||v_uid::text));
  begin
    select (c.value #>> '{}')::integer into v_cap_max
      from catalog.platform_config c
     where c.key = 'inventory.per_user_active_hold_max'
     order by c.version desc limit 1;
  exception when others then v_cap_max := null;
  end;
  v_cap_max := coalesce(v_cap_max, 0);
  select count(*) into v_active from venue.inventory_hold h
   where h.identity_id = v_uid and h.status = 'active';
  if v_active + 1 > v_cap_max then
    raise exception 'precondition_failed: hold_cap_exceeded';
  end if;

  -- Hold TTL is a PFA-9 CLASS A key with NO frozen spelling (E-28): unseeded =>
  -- REFUSE rather than invent a business policy (a TTL is policy, not a default).
  begin
    select (c.value #>> '{}')::interval into v_ttl
      from catalog.platform_config c
     where c.key = 'inventory.hold_ttl_interval'
     order by c.version desc limit 1;
  exception when others then v_ttl := null;
  end;
  if v_ttl is null then
    raise exception 'precondition_failed: hold_ttl_unset';
  end if;
  v_expires := now() + v_ttl;

  -- THE OVERSELL CHOKE-POINT: FOR UPDATE on the counter row, then the CHECK.
  select b.held, b.capacity, b.sold into v_held, v_cap, v_sold
    from venue.inventory_batch b where b.batch_id = p_batch_id for update;
  if v_held + v_sold + p_quantity > v_cap then
    raise exception 'precondition_failed: oversell_rejected';
  end if;

  update venue.inventory_batch set held = held + p_quantity, updated_at = now()
   where batch_id = p_batch_id;

  insert into venue.inventory_hold
         (batch_id, identity_id, quantity, status, expires_at, command_idempotency_key)
  values (p_batch_id, v_uid, p_quantity, 'active', v_expires, p_command_key)
  returning hold_id into v_hold_id;

  insert into venue.inventory_movement
         (batch_id, movement_kind, delta_held, delta_sold, cause, cause_ref, actor_identity)
  values (p_batch_id, 'hold', p_quantity, 0, 'primary_sale', v_hold_id, v_uid);

  return jsonb_build_object('status','ok','hold_id',v_hold_id,'expires_at',v_expires,
                            'remaining',v_cap - (v_held + p_quantity) - v_sold);
exception when unique_violation then
  raise exception 'precondition_failed: idempotency_replay';
end;
$$;

-- ============================================================================
-- PART 11 — venue.create_inventory_hold (RPC §5.4; staff hold)
-- ============================================================================

create or replace function venue.create_inventory_hold(
  p_batch_id uuid, p_quantity integer, p_hold_kind text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid;
  v_flag    boolean;
  v_org_id  uuid;
  v_venue   uuid;
  v_held    integer;
  v_cap     integer;
  v_sold    integer;
  v_ttl     interval;
  v_hold_id uuid;
  v_expires timestamptz;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'precondition_failed: bad_quantity';
  end if;

  select (c.value #>> '{}')::boolean into v_flag
    from catalog.platform_config c where c.key = 'feature.native_issuance_enabled'
   order by c.version desc limit 1;
  if not coalesce(v_flag, false) then
    raise exception 'precondition_failed: feature_disabled';
  end if;

  select e.org_id, e.venue_id, b.held, b.capacity, b.sold
    into v_org_id, v_venue, v_held, v_cap, v_sold
    from venue.inventory_batch b
    join venue.ticket_type tt on tt.ticket_type_id = b.ticket_type_id
    join catalog.event e on e.event_id = tt.event_id
   where b.batch_id = p_batch_id
   for update of b;
  if v_org_id is null then
    raise exception 'not_found: batch %', p_batch_id using errcode = 'P0002';
  end if;

  -- Staff authority (distinct from the buyer hold, never fans).
  if not (kernel.has_org_role_over_venue(v_venue, array['org_owner','org_admin'])
          or kernel.has_venue_role(v_venue, array['venue_manager'])) then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  begin
    select (c.value #>> '{}')::interval into v_ttl from catalog.platform_config c
     where c.key = 'inventory.hold_ttl_interval' order by c.version desc limit 1;
  exception when others then v_ttl := null;
  end;
  if v_ttl is null then
    raise exception 'precondition_failed: hold_ttl_unset';
  end if;
  v_expires := now() + v_ttl;

  if v_held + v_sold + p_quantity > v_cap then
    raise exception 'precondition_failed: oversell_rejected';
  end if;

  update venue.inventory_batch set held = held + p_quantity, updated_at = now()
   where batch_id = p_batch_id;

  insert into venue.inventory_hold
         (batch_id, identity_id, quantity, status, expires_at, command_idempotency_key)
  values (p_batch_id, v_uid, p_quantity, 'active', v_expires, p_command_key)
  returning hold_id into v_hold_id;

  insert into venue.inventory_movement
         (batch_id, movement_kind, delta_held, delta_sold, cause, cause_ref, actor_identity)
  values (p_batch_id, 'hold', p_quantity, 0,
          case p_hold_kind when 'comp' then 'comp' else 'admin_action' end, v_hold_id, v_uid);

  return jsonb_build_object('status','ok','hold_id',v_hold_id);
exception when unique_violation then
  raise exception 'precondition_failed: idempotency_replay';
end;
$$;

-- ============================================================================
-- PART 12 — venue.release_inventory_hold (RPC §5.5; returns held)
-- ============================================================================

create or replace function venue.release_inventory_hold(
  p_hold_id uuid, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid;
  v_batch   uuid;
  v_qty     integer;
  v_status  text;
  v_holder  uuid;
  v_venue   uuid;
  v_new     text := 'released';
  v_rem     integer;
begin
  v_uid := auth.uid();
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;

  -- Resolve the batch id (holds never move batches, so an unlocked read is
  -- safe), then lock the BATCH first (rank 2, the frozen §5.5 order), THEN
  -- lock and RE-READ the hold row. The prior form read status on an unlocked
  -- SELECT and checked the STALE snapshot — two concurrent releases both saw
  -- 'active' and both decremented held; benign in 081 (the movement UNIQUE
  -- aborts the second) but a latent oversell once a converter lands (082/083).
  select h.batch_id into v_batch from venue.inventory_hold h where h.hold_id = p_hold_id;
  if v_batch is null then
    raise exception 'not_found: hold %', p_hold_id using errcode = 'P0002';
  end if;
  perform 1 from venue.inventory_batch b where b.batch_id = v_batch for update;  -- rank 2
  select h.quantity, h.status, h.identity_id
    into v_qty, v_status, v_holder
    from venue.inventory_hold h where h.hold_id = p_hold_id
    for update;                                          -- authoritative under lock

  -- terminal-state idempotency: a double-release is a no-op.
  if v_status <> 'active' then
    return jsonb_build_object('status','noop_replay','hold_status',v_status);
  end if;

  -- Authority: the holder, OR venue staff, OR the definer sweep (auth.uid() NULL
  -- inside the scheduler-invoked sweep — the sweep is service_role/DEF, so it
  -- passes the NULL-uid branch below).
  select e.venue_id into v_venue
    from venue.inventory_batch b
    join venue.ticket_type tt on tt.ticket_type_id = b.ticket_type_id
    join catalog.event e on e.event_id = tt.event_id
   where b.batch_id = v_batch;
  if v_uid is not null
     and v_uid <> v_holder
     and not kernel.has_venue_role(v_venue, array['venue_manager','venue_scanner']) then
    raise exception 'insufficient_privilege: not the holder or venue staff'
      using errcode = '42501';
  end if;

  -- the sweep passes 'sweep:'||hold_id and drives the 'expired' transition.
  if p_command_key like 'sweep:%' then v_new := 'expired'; end if;

  update venue.inventory_hold set status = v_new, updated_at = now()
   where hold_id = p_hold_id;
  update venue.inventory_batch set held = held - v_qty, updated_at = now()
   where batch_id = v_batch
  returning (capacity - held - sold) into v_rem;

  insert into venue.inventory_movement
         (batch_id, movement_kind, delta_held, delta_sold, cause, cause_ref, actor_identity)
  values (v_batch, 'release', -v_qty, 0, 'admin_action', p_hold_id, v_uid);

  return jsonb_build_object('status','ok','remaining',v_rem);
exception when unique_violation then
  -- the movement idempotency key already exists: this hold was released by a
  -- concurrent path. Report the no-op, do not surface a raw 23505.
  return jsonb_build_object('status','noop_replay','hold_status','released');
end;
$$;

-- ============================================================================
-- PART 13 — venue.sweep_expired_inventory_holds (RPC §20.3.3; G-24; DEF/cron)
-- ============================================================================

-- LOAD-BEARING (§3.5.1): held is a STORED counter and nothing recomputes it, so
-- a disabled tick is permanently lost capacity, not lag. It performs no counter
-- arithmetic of its own — per row it calls release_inventory_hold under
-- FOR UPDATE SKIP LOCKED, keeping the single-writer property; a hold
-- mid-conversion is skipped, not fought over.
create or replace function venue.sweep_expired_inventory_holds(p_limit int default 500)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row      record;
  v_swept    integer := 0;
  v_released integer := 0;
  v_errors   integer := 0;
  v_batches  uuid[] := '{}';
begin
  for v_row in
    select h.hold_id, h.quantity, h.batch_id
      from venue.inventory_hold h
     where h.status = 'active' and h.expires_at < now()
     order by h.batch_id, h.hold_id
     limit p_limit
     for update of h skip locked
  loop
    -- Each row is its own subtransaction (§20.3.3): a poisoned or racing hold
    -- rolls back ONLY its own release and is skipped, so one bad row cannot
    -- block the tick — this sweep is the ONLY writer that returns the stored
    -- `held`, so a blocked tick is permanent lost capacity (§3.5.1).
    begin
      perform venue.release_inventory_hold(v_row.hold_id, 'sweep:'||v_row.hold_id::text);
      v_swept := v_swept + 1;
      v_released := v_released + v_row.quantity;
      if not (v_row.batch_id = any(v_batches)) then
        v_batches := array_append(v_batches, v_row.batch_id);
      end if;
    exception when others then
      v_errors := v_errors + 1;
      raise warning 'inventory.hold.sweep_error: hold % skipped: %', v_row.hold_id, sqlerrm;
    end;
  end loop;
  return jsonb_build_object('swept', v_swept, 'released_qty', v_released,
                            'batches_touched', coalesce(array_length(v_batches,1), 0),
                            'errors', v_errors);
end;
$$;

-- ============================================================================
-- PART 14 — catalog.publish_event (RPC §4.2; SEAM-1: reads ticket_type+batch)
-- ============================================================================

create or replace function catalog.publish_event(
  p_event_id uuid, p_target_status text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid;
  v_org_id  uuid;
  v_venue   uuid;
  v_status  text;
  v_ok      boolean;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_target_status not in ('announced','on_sale','live','completed') then
    raise exception 'invalid_input: bad target_status % (cancellation is catalog.cancel_event)', p_target_status;
  end if;

  select e.org_id, e.venue_id, e.status into v_org_id, v_venue, v_status
    from catalog.event e where e.event_id = p_event_id for update;
  if v_org_id is null then
    raise exception 'not_found: event %', p_event_id using errcode = 'P0002';
  end if;

  if not (kernel.has_org_role(v_org_id, array['org_owner','org_admin'])
          or kernel.has_venue_role(v_venue, array['venue_manager'])) then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  -- legal FORWARD transition only (draft→announced→on_sale→live→completed).
  v_ok := (v_status = 'draft'     and p_target_status = 'announced')
       or (v_status = 'announced' and p_target_status = 'on_sale')
       or (v_status = 'on_sale'   and p_target_status = 'live')
       or (v_status = 'live'      and p_target_status = 'completed');
  if not v_ok then
    raise exception 'precondition_failed: illegal_transition (% -> %)', v_status, p_target_status;
  end if;

  -- on_sale requires >=1 ticket_type WITH a batch — no empty on-sale.
  if p_target_status = 'on_sale' then
    if not exists (
      select 1 from venue.ticket_type tt
       join venue.inventory_batch b on b.ticket_type_id = tt.ticket_type_id
      where tt.event_id = p_event_id) then
      raise exception 'precondition_failed: empty_inventory';
    end if;
  end if;

  update catalog.event set status = p_target_status, updated_at = now()
   where event_id = p_event_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'event.status', 'event', p_event_id, 'publish',
          jsonb_build_object('status', v_status), jsonb_build_object('status', p_target_status));

  return jsonb_build_object('status','ok','event_status',p_target_status);
end;
$$;

-- ============================================================================
-- PART 15 — RLS + GRANTS (RLS §9.1-§9.5, §16.10; I-7)
-- ============================================================================

alter table venue.ticket_type            enable row level security;
alter table venue.inventory_batch         enable row level security;
alter table venue.inventory_batch_shard   enable row level security;
alter table venue.inventory_movement      enable row level security;
alter table venue.inventory_hold          enable row level security;

revoke all on venue.ticket_type          from anon, authenticated;
revoke all on venue.inventory_batch       from anon, authenticated;
revoke all on venue.inventory_batch_shard from anon, authenticated;
revoke all on venue.inventory_movement    from anon, authenticated;
revoke all on venue.inventory_hold        from anon, authenticated;

-- ticket_type: `public`-visibility read to ANY authenticated principal; venue-
-- scoped for hidden/door_only. RLS §9.1's `anon` arm is NOT deliverable here:
-- 076 (immutable) grants schema venue USAGE to `authenticated` only, so anon
-- cannot reach the venue schema at all — the policy is scoped to what the
-- frozen GRANT boundary permits, fail-closed (erratum E-30).
grant select on venue.ticket_type to authenticated;
drop policy if exists venue_ticket_type_sel_public on venue.ticket_type;
create policy venue_ticket_type_sel_public
  on venue.ticket_type for select to authenticated
  using (visibility = 'public');
-- §9.1 is a TWO-TIER grant and the tier is load-bearing: ONLY org_owner/admin
-- and venue_manager read HIDDEN types ("incl. hidden" qualifies exactly those
-- rows). Every other role reads public+door_only only (visibility <> 'hidden').
-- The prior single-arm form leaked hidden name+price_minor to seven
-- lower-privilege roles — the R3-3a shape §16.10a exists to catch.
drop policy if exists venue_ticket_type_sel_venue on venue.ticket_type;
create policy venue_ticket_type_sel_venue
  on venue.ticket_type for select to authenticated
  using (
        kernel.has_org_role_over_event(event_id, array['org_owner','org_admin'])
     or kernel.has_event_role(event_id, array['venue_manager'])
     or (visibility <> 'hidden'
         and (kernel.has_org_role_over_event(event_id, array['org_finance','org_member'])
              or kernel.has_event_role(event_id,
                   array['venue_finance','venue_box_office',
                         'venue_marketing','venue_promoter_manager','venue_scanner'])))
  );

-- inventory_batch: `remaining` is the only client-readable counter (footnote 23).
-- Raw capacity/held/sold are withheld from EVERY client role via the column
-- grant — per-sub-role column visibility within `authenticated` is not
-- expressible (the E-24 impossibility; recorded E-29). Venue staff read the raw
-- counters through the batch/capacity RPC RESULT JSON, never a table SELECT.
grant select (batch_id, ticket_type_id, event_session_id, release_kind, is_sharded,
              remaining, created_at, updated_at)
  on venue.inventory_batch to authenticated;             -- anon walled by 076 (E-30)
drop policy if exists venue_inventory_batch_sel_public on venue.inventory_batch;
create policy venue_inventory_batch_sel_public
  on venue.inventory_batch for select to authenticated
  using (exists (select 1 from venue.ticket_type tt
                  where tt.ticket_type_id = venue.inventory_batch.ticket_type_id
                    and tt.visibility = 'public'));
drop policy if exists venue_inventory_batch_sel_venue on venue.inventory_batch;
create policy venue_inventory_batch_sel_venue
  on venue.inventory_batch for select to authenticated
  using (
    kernel.has_org_role_over_event(
      (select tt.event_id from venue.ticket_type tt
        where tt.ticket_type_id = venue.inventory_batch.ticket_type_id),
      array['org_owner','org_admin','org_finance'])
    or kernel.has_event_role(
      (select tt.event_id from venue.ticket_type tt
        where tt.ticket_type_id = venue.inventory_batch.ticket_type_id),
      array['venue_manager','venue_finance','venue_scanner'])
  );

-- inventory_batch_shard + inventory_movement: money-custody-RPC-only, deny-all
-- (RLS on, ZERO policies — §9.3/§9.4; the zero-policy register).

-- inventory_hold: owner-scoped + venue-scoped read; writes RPC-only.
grant select on venue.inventory_hold to authenticated;
drop policy if exists venue_inventory_hold_sel_owner on venue.inventory_hold;
create policy venue_inventory_hold_sel_owner
  on venue.inventory_hold for select to authenticated
  using (identity_id = auth.uid());
-- §9.5: venue ops (manager/scanner) + the org plane (owner/admin/finance).
drop policy if exists venue_inventory_hold_sel_venue on venue.inventory_hold;
create policy venue_inventory_hold_sel_venue
  on venue.inventory_hold for select to authenticated
  using (
    kernel.has_org_role_over_event(
      ( select s.event_id
          from venue.inventory_batch b
          join catalog.event_session s on s.session_id = b.event_session_id
         where b.batch_id = venue.inventory_hold.batch_id ),
      array['org_owner','org_admin','org_finance'])
    or kernel.has_event_role(
      ( select s.event_id
          from venue.inventory_batch b
          join catalog.event_session s on s.session_id = b.event_session_id
         where b.batch_id = venue.inventory_hold.batch_id ),
      array['venue_manager','venue_scanner'])
  );

-- AO / counter integrity: REVOKE UPDATE,DELETE on the movement ledger (I-7).
revoke update, delete on venue.inventory_movement from anon, authenticated;

-- ============================================================================
-- PART 16 — function ACLs (I-7: strip PUBLIC, grant exactly)
-- ============================================================================

do $$
declare
  v_fn text;
  v_all constant text[] := array[
    'venue.create_ticket_type(uuid, text, text, integer, text, text)',
    'venue.set_ticket_type_price(uuid, integer, text, text)',
    'venue.create_inventory_batch(uuid, uuid, text, integer, integer, text)',
    'venue.set_batch_capacity(uuid, integer, text, text)',
    'venue.reserve_primary_inventory(uuid, integer, text)',
    'venue.create_inventory_hold(uuid, integer, text, text)',
    'venue.release_inventory_hold(uuid, text)',
    'venue.sweep_expired_inventory_holds(int)',
    'catalog.publish_event(uuid, text, text)'
  ];
  -- caller-authorized RPCs -> authenticated (authority lives in the bodies).
  v_auth constant text[] := array[
    'venue.create_ticket_type(uuid, text, text, integer, text, text)',
    'venue.set_ticket_type_price(uuid, integer, text, text)',
    'venue.create_inventory_batch(uuid, uuid, text, integer, integer, text)',
    'venue.set_batch_capacity(uuid, integer, text, text)',
    'venue.reserve_primary_inventory(uuid, integer, text)',
    'venue.create_inventory_hold(uuid, integer, text, text)',
    'venue.release_inventory_hold(uuid, text)',
    'catalog.publish_event(uuid, text, text)'
  ];
  -- the hold sweep is DEF scheduler-only (RPC §20.3.3): service_role only.
  v_svc constant text[] := array[
    'venue.sweep_expired_inventory_holds(int)'
  ];
begin
  foreach v_fn in array v_all loop
    execute format('revoke all on function %s from public, anon, authenticated', v_fn);
  end loop;
  foreach v_fn in array v_auth loop
    execute format('grant execute on function %s to authenticated', v_fn);
  end loop;
  foreach v_fn in array v_svc loop
    execute format('grant execute on function %s to service_role', v_fn);
  end loop;
end $$;

-- ============================================================================
-- PART 17 — CRON (CRON_SCHEDULE_REGISTER row 081; per-job, owning package)
-- ============================================================================

select cron.schedule(
  'sweep-expired-inventory-holds',
  '*/2 * * * *',
  $$select venue.sweep_expired_inventory_holds();$$
);

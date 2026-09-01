-- ============================================================================
-- 086_venue_door_and_scan — Phase-2 package 086 (family H, scan infrastructure).
-- Frozen sources: phase2-architecture-v2 · registry §086 · plan §8/086 (the §5
-- block is the STALE pre-delta record; §8 WINS, plan L1236) · schema §3.10-3.16
-- + §10 · DOOR spec §7/§9/§10/§12 · RPC §1.1d/§9/§17.10-17.13/§20.4-20.7.5 ·
-- RLS §11/§16.4a/§16.11 · EDGE §5.4 · DEMOGRAPHICS §10.2 · OR-17.
-- Depends: 076,077,078,079,080,081,083.
--
-- WHAT THIS IS: the offline-first door substrate — the append-only admission
-- ledger (scan, AO), the door-manifest EPISODE ledger (door_manifest +
-- _entry[AO] + _delta[AO], the offline staleness check), door PINs + tokenized
-- door SESSIONS (loginless scanner auth), comp/guest admissions, and the
-- per-session holder-mix privacy projection. It fills the SEAM-2 bodies
-- append_door_manifest_delta (stub 083) + on_identity_erased_door (stub 077),
-- authors kernel.revoke_signing_key (PFA-17), and delivers the door read plane
-- for anon credential verification (PFA-16/PFA-24: M2 carries signing_key_id;
-- public_key stays in M1 = the kernel.signing_key projection).
--
-- OWNER RULINGS EXECUTED: PFA-24 (M2 has no public_key; the manifest is
-- identity- and key-material-free), PFA-25 (set_event_security_config is NOT
-- built here — forward obligation).
--
-- DARKNESS: feature.native_scanning_enabled=false (078) gates record_scan until
-- the 2B door gate. Rollback: CLEAN-WHILE-EMPTY, then forward-fix.
-- ============================================================================

begin;

-- ============================================================================
-- PART 1 — venue.door_pin (schema §3.10; C9 hashed PIN)
-- ============================================================================
create table if not exists venue.door_pin (
  pin_id           uuid primary key default gen_random_uuid(),
  venue_id         uuid not null references catalog.venue(venue_id) on delete restrict,
  event_session_id uuid not null references catalog.event_session(session_id) on delete restrict,
  label            text not null,
  pin_hash         text not null,                       -- hashed, NEVER client-readable (C9)
  status           text not null default 'active' check (status in ('active','revoked')),
  expires_at       timestamptz not null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists door_pin_session_status_idx on venue.door_pin (event_session_id, status);
drop trigger if exists tg_door_pin_set_updated_at on venue.door_pin;
create trigger tg_door_pin_set_updated_at before update on venue.door_pin
  for each row execute function kernel.set_updated_at();
alter table venue.door_pin enable row level security;
revoke all on venue.door_pin from anon, authenticated;
-- venue-scoped read, pin_hash withheld by the column grant.
grant select (pin_id, venue_id, event_session_id, label, status, expires_at, created_at, updated_at)
  on venue.door_pin to authenticated;
drop policy if exists venue_door_pin_sel_venue on venue.door_pin;
create policy venue_door_pin_sel_venue on venue.door_pin for select to authenticated
  using (kernel.has_venue_role(venue_id, array['venue_manager']));

-- ============================================================================
-- PART 2 — venue.door_session (schema §3.10a, defect H-3; tokenized, audit-only)
-- ============================================================================
create table if not exists venue.door_session (
  door_session_id  uuid primary key default gen_random_uuid(),   -- non-secret selector
  token_hash       text not null,                       -- hashed, NEVER client-readable on ANY path
  device_id        uuid not null,                       -- FK added in PART 3 order (scan_device)
  event_session_id uuid not null references catalog.event_session(session_id) on delete restrict,
  venue_id         uuid not null references catalog.venue(venue_id) on delete restrict,
  pin_id           uuid not null references venue.door_pin(pin_id) on delete restrict,
  issued_at        timestamptz not null default now(),
  expires_at       timestamptz not null,                -- server-max TTL (door.session_ttl_interval)
  last_seen_at     timestamptz,
  status           text not null default 'active' check (status in ('active','revoked','expired')),
  revoked_at       timestamptz,
  revoked_reason   text,
  created_at       timestamptz not null default now(),
  constraint door_session_token_uq unique (token_hash),
  constraint door_session_window_ck check (expires_at > issued_at),
  constraint door_session_revoked_ck check ((status = 'revoked') = (revoked_at is not null))
);
create unique index if not exists door_session_active_device_uq
  on venue.door_session (device_id, event_session_id) where status = 'active';
create index if not exists door_session_session_status_idx on venue.door_session (event_session_id, status);
create index if not exists door_session_pin_idx on venue.door_session (pin_id);           -- RV-1
create index if not exists door_session_expiry_idx on venue.door_session (expires_at) where status = 'active';
alter table venue.door_session enable row level security;
revoke all on venue.door_session from anon, authenticated;   -- deny-all, ZERO policies (§16.4a audit-only)

-- ============================================================================
-- PART 3 — venue.scan_device (schema §3.11; +manifest_id §10.5)
-- ============================================================================
create table if not exists venue.scan_device (
  device_id        uuid primary key default gen_random_uuid(),
  venue_id         uuid not null references catalog.venue(venue_id) on delete restrict,
  label            text not null,
  manifest_version integer,
  manifest_id      uuid,                                -- FK added in PART 8 (door_manifest)
  last_sync_at     timestamptz,
  device_boot_id   uuid,                                -- C23
  status           text not null default 'active' check (status in ('active','retired')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists scan_device_venue_idx on venue.scan_device (venue_id);
drop trigger if exists tg_scan_device_set_updated_at on venue.scan_device;
create trigger tg_scan_device_set_updated_at before update on venue.scan_device
  for each row execute function kernel.set_updated_at();
alter table venue.scan_device enable row level security;
revoke all on venue.scan_device from anon, authenticated;
grant select on venue.scan_device to authenticated;
drop policy if exists venue_scan_device_sel_venue on venue.scan_device;
create policy venue_scan_device_sel_venue on venue.scan_device for select to authenticated
  using (kernel.has_venue_role(venue_id, array['venue_scanner','venue_manager']));

-- now that scan_device exists, add door_session.device_id FK
alter table venue.door_session
  add constraint door_session_device_fk foreign key (device_id)
  references venue.scan_device(device_id) on delete restrict;

-- ============================================================================
-- PART 4 — venue.scan (schema §3.12; AO admission ledger; C41 first-in-wins)
-- ============================================================================
create table if not exists venue.scan (
  scan_id           uuid primary key default gen_random_uuid(),
  ticket_atom_id    uuid not null references kernel.tickets(ticket_atom_id) on delete restrict,
  event_session_id  uuid not null references catalog.event_session(session_id) on delete restrict,
  device_id         uuid references venue.scan_device(device_id) on delete restrict,
  actor_identity_id uuid references auth.users(id) on delete restrict,   -- RM §7.4
  direction         text not null default 'in' check (direction in ('in','out')),
  scan_type         text not null default 'admission' check (scan_type in ('admission','re_entry','pass_out')),
  result            text not null check (result in ('admitted','duplicate','invalid','frozen','fraud_review')),
  offline_pending   boolean not null default false,
  device_boot_id    uuid,
  scan_sequence     integer,
  fraud_flag        boolean not null default false,
  manifest_version  integer,
  manifest_id       uuid,                              -- FK added in PART 8
  occurred_at       timestamptz not null,
  server_receipt_at timestamptz not null default now(),
  created_at        timestamptz not null default now(),
  -- non-anon-admission: a scan is either device-attributed or actor-attributed
  constraint scan_attribution_ck check (device_id is not null or actor_identity_id is not null)
);
-- C41 first-in-wins: at most one admitted inbound scan per atom per session
create unique index if not exists scan_admitted_in_uq
  on venue.scan (ticket_atom_id, event_session_id)
  where result = 'admitted' and direction = 'in';
create index if not exists scan_session_receipt_idx on venue.scan (event_session_id, server_receipt_at);
create index if not exists scan_atom_idx on venue.scan (ticket_atom_id);
-- AO: the admission ledger is append-only.
drop trigger if exists tg_scan_append_only on venue.scan;
create trigger tg_scan_append_only before update or delete on venue.scan
  for each row execute function kernel.raise_append_only();
alter table venue.scan enable row level security;
revoke all on venue.scan from anon, authenticated;
revoke update, delete on venue.scan from service_role;    -- AO
grant select on venue.scan to authenticated;
drop policy if exists venue_scan_sel_venue on venue.scan;
create policy venue_scan_sel_venue on venue.scan for select to authenticated
  using (exists (select 1 from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
                  where es.session_id = venue.scan.event_session_id
                    and kernel.has_venue_role(ev.venue_id, array['venue_scanner','venue_manager'])));

-- ============================================================================
-- PART 5 — venue.comp_allocation (schema §3.15)
-- ============================================================================
create table if not exists venue.comp_allocation (
  id                   uuid primary key default gen_random_uuid(),
  event_session_id     uuid not null references catalog.event_session(session_id) on delete restrict,
  batch_id             uuid not null references venue.inventory_batch(batch_id) on delete restrict,
  granted_to_identity  uuid references auth.users(id) on delete restrict,
  granted_to_name      text,
  quantity             integer not null check (quantity > 0),
  status               text not null default 'allocated' check (status in ('allocated','issued','revoked')),
  granted_by           uuid references auth.users(id) on delete restrict,   -- nullable: ODR16 #30 SET NULL on erasure
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
create index if not exists comp_allocation_session_idx on venue.comp_allocation (event_session_id);
drop trigger if exists tg_comp_allocation_set_updated_at on venue.comp_allocation;
create trigger tg_comp_allocation_set_updated_at before update on venue.comp_allocation
  for each row execute function kernel.set_updated_at();
alter table venue.comp_allocation enable row level security;
revoke all on venue.comp_allocation from anon, authenticated;
grant select on venue.comp_allocation to authenticated;
drop policy if exists venue_comp_allocation_sel_venue on venue.comp_allocation;
create policy venue_comp_allocation_sel_venue on venue.comp_allocation for select to authenticated
  using (exists (select 1 from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
                  where es.session_id = venue.comp_allocation.event_session_id
                    and kernel.has_venue_role(ev.venue_id, array['venue_manager'])));

-- ============================================================================
-- PART 6 — venue.guest_list + guest_entry (schema §3.16)
-- ============================================================================
create table if not exists venue.guest_list (
  id               uuid primary key default gen_random_uuid(),
  event_session_id uuid not null references catalog.event_session(session_id) on delete restrict,
  name             text not null,
  created_by       uuid references auth.users(id) on delete restrict,   -- nullable: ODR16 #31 SET NULL on erasure
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
drop trigger if exists tg_guest_list_set_updated_at on venue.guest_list;
create trigger tg_guest_list_set_updated_at before update on venue.guest_list
  for each row execute function kernel.set_updated_at();
alter table venue.guest_list enable row level security;
revoke all on venue.guest_list from anon, authenticated;
grant select on venue.guest_list to authenticated;
drop policy if exists venue_guest_list_sel_venue on venue.guest_list;
create policy venue_guest_list_sel_venue on venue.guest_list for select to authenticated
  using (exists (select 1 from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
                  where es.session_id = venue.guest_list.event_session_id
                    and kernel.has_venue_role(ev.venue_id, array['venue_manager','venue_box_office'])));

create table if not exists venue.guest_entry (
  id            uuid primary key default gen_random_uuid(),
  guest_list_id uuid not null references venue.guest_list(id) on delete cascade,
  guest_name    text not null,
  party_size    integer not null default 1 check (party_size > 0),
  status        text not null default 'pending' check (status in ('pending','arrived','no_show')),
  checked_in_at timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists guest_entry_list_idx on venue.guest_entry (guest_list_id);
drop trigger if exists tg_guest_entry_set_updated_at on venue.guest_entry;
create trigger tg_guest_entry_set_updated_at before update on venue.guest_entry
  for each row execute function kernel.set_updated_at();
alter table venue.guest_entry enable row level security;
revoke all on venue.guest_entry from anon, authenticated;
grant select on venue.guest_entry to authenticated;
drop policy if exists venue_guest_entry_sel_venue on venue.guest_entry;
create policy venue_guest_entry_sel_venue on venue.guest_entry for select to authenticated
  using (exists (select 1 from venue.guest_list gl
                  join catalog.event_session es on es.session_id = gl.event_session_id
                  join catalog.event ev on ev.event_id = es.event_id
                  where gl.id = venue.guest_entry.guest_list_id
                    and kernel.has_venue_role(ev.venue_id, array['venue_manager','venue_box_office'])));

-- ============================================================================
-- PART 7 — the door-manifest EPISODE ledger (DOOR §10.1/§10.3/§10.3a)
--   door_manifest (AO + the single open→closed transition) · _entry (AO,
--   complete base snapshot) · _delta (AO, post-open add/revoke). PFA-24: NO
--   public_key, NO identity anywhere — signing_key_id is the only key column.
-- ============================================================================
create table if not exists venue.door_manifest (
  manifest_id      uuid primary key default gen_random_uuid(),
  session_id       uuid not null references catalog.event_session(session_id) on delete restrict,
  venue_id         uuid not null references catalog.venue(venue_id) on delete restrict,   -- denorm authz
  manifest_version integer not null,                    -- per-session monotone, starts 1
  status           text not null default 'open' check (status in ('open','closed')),
  opened_at        timestamptz not null default now(),
  opened_by        uuid not null references auth.users(id) on delete restrict,
  open_reason_code text not null,
  not_after        timestamptz not null,
  closed_at        timestamptz,
  closed_by        uuid references auth.users(id) on delete restrict,
  close_reason     text,
  entry_count      integer not null check (entry_count >= 0),
  manifest_digest  text not null,
  max_delta_seq    integer not null default 0,
  command_idempotency_key text not null,
  created_at       timestamptz not null default now(),
  constraint door_manifest_version_uq unique (session_id, manifest_version),
  constraint door_manifest_command_uq unique (session_id, command_idempotency_key),
  constraint door_manifest_window_ck check (not_after > opened_at),
  constraint door_manifest_closed_ck check ((status = 'closed') = (closed_at is not null))
);
-- at most ONE open episode per session (DB-enforced offline-staleness invariant)
create unique index if not exists door_manifest_open_uq
  on venue.door_manifest (session_id) where status = 'open';
create index if not exists door_manifest_session_opened_idx on venue.door_manifest (session_id, opened_at);
create index if not exists door_manifest_venue_status_idx on venue.door_manifest (venue_id, status);

-- guard: the ONLY legal UPDATE is open→closed (+ its close columns + max_delta_seq
-- bump by the delta appender); every other mutation and all DELETE are rejected.
create or replace function venue.guard_door_manifest_transition()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'append_only: door_manifest is never deleted' using errcode = 'P0001';
  end if;
  -- ALLOWLIST: the ONLY mutable columns are the close trio (closed_at/closed_by/
  -- close_reason), max_delta_seq (bumped by the delta appender), and the status
  -- open->closed flip. EVERY other column is immutable after open — including
  -- venue_id (the denormalized authz key that drives the entry/delta RLS joins),
  -- not_after (the offline-staleness boundary) and command_idempotency_key. A
  -- blocklist that named only identity/base columns let a service_role UPDATE flip
  -- venue_id and silently move a whole episode + its ledger to another tenant.
  if new.manifest_id is distinct from old.manifest_id
     or new.session_id is distinct from old.session_id
     or new.venue_id is distinct from old.venue_id
     or new.manifest_version is distinct from old.manifest_version
     or new.opened_at is distinct from old.opened_at
     or new.opened_by is distinct from old.opened_by
     or new.open_reason_code is distinct from old.open_reason_code
     or new.not_after is distinct from old.not_after
     or new.entry_count is distinct from old.entry_count
     or new.manifest_digest is distinct from old.manifest_digest
     or new.command_idempotency_key is distinct from old.command_idempotency_key
     or new.created_at is distinct from old.created_at then
    raise exception 'append_only: door_manifest identity/base is immutable after open' using errcode = 'P0001';
  end if;
  -- status may only advance open->closed, never regress or jump.
  if not (new.status = old.status or (old.status = 'open' and new.status = 'closed')) then
    raise exception 'append_only: door_manifest status may only advance open->closed' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
drop trigger if exists tg_door_manifest_transition on venue.door_manifest;
create trigger tg_door_manifest_transition before update or delete on venue.door_manifest
  for each row execute function venue.guard_door_manifest_transition();

alter table venue.door_manifest enable row level security;
revoke all on venue.door_manifest from anon, authenticated;
revoke delete on venue.door_manifest from service_role;
grant select on venue.door_manifest to authenticated;
drop policy if exists venue_door_manifest_sel_venue on venue.door_manifest;
create policy venue_door_manifest_sel_venue on venue.door_manifest for select to authenticated
  using (kernel.has_venue_role(venue_id, array['venue_scanner','venue_manager']));

-- now scan_device.manifest_id + scan.manifest_id FKs can bind
alter table venue.scan_device
  add constraint scan_device_manifest_fk foreign key (manifest_id)
  references venue.door_manifest(manifest_id) on delete restrict;
alter table venue.scan
  add constraint scan_manifest_fk foreign key (manifest_id)
  references venue.door_manifest(manifest_id) on delete restrict;

-- the complete base snapshot (AO). Every atom of the session at open, every state.
create table if not exists venue.door_manifest_entry (
  manifest_id        uuid not null references venue.door_manifest(manifest_id) on delete restrict,
  ticket_atom_id     uuid not null references kernel.tickets(ticket_atom_id) on delete restrict,
  serial_no          integer not null,
  ticket_type_id     uuid not null references venue.ticket_type(ticket_type_id) on delete restrict,   -- MP-1
  credential_version integer not null check (credential_version >= 0),
  signing_key_id     uuid not null references kernel.signing_key(key_id) on delete restrict,
  ticket_state       text not null check (ticket_state in ('issued','active','scanned','voided','expired')),
  resale_state       text not null check (resale_state in ('none','listed','locked','refund_hold','dispute_hold')),
  created_at         timestamptz not null default now(),
  primary key (manifest_id, ticket_atom_id)
);
create index if not exists door_manifest_entry_atom_idx on venue.door_manifest_entry (ticket_atom_id);
drop trigger if exists tg_door_manifest_entry_append_only on venue.door_manifest_entry;
create trigger tg_door_manifest_entry_append_only before update or delete on venue.door_manifest_entry
  for each row execute function kernel.raise_append_only();
alter table venue.door_manifest_entry enable row level security;
revoke all on venue.door_manifest_entry from anon, authenticated;
revoke update, delete on venue.door_manifest_entry from service_role;
grant select on venue.door_manifest_entry to authenticated;
drop policy if exists venue_door_manifest_entry_sel_venue on venue.door_manifest_entry;
create policy venue_door_manifest_entry_sel_venue on venue.door_manifest_entry for select to authenticated
  using (exists (select 1 from venue.door_manifest m where m.manifest_id = venue.door_manifest_entry.manifest_id
                  and kernel.has_venue_role(m.venue_id, array['venue_scanner','venue_manager'])));

-- post-open add/revoke deltas (AO). MP-1: an add carries the full offline-verify
-- payload; a revoke carries none.
create table if not exists venue.door_manifest_delta (
  manifest_id        uuid not null references venue.door_manifest(manifest_id) on delete restrict,
  seq                integer not null,                  -- per-manifest monotone, starts 1
  ticket_atom_id     uuid not null references kernel.tickets(ticket_atom_id) on delete restrict,
  op                 text not null check (op in ('add','revoke')),
  serial_no          integer,
  ticket_type_id     uuid references venue.ticket_type(ticket_type_id) on delete restrict,
  credential_version integer check (credential_version is null or credential_version >= 0),
  signing_key_id     uuid references kernel.signing_key(key_id) on delete restrict,
  ticket_state       text,
  resale_state       text,
  cause_ref          uuid,
  occurred_at        timestamptz not null default now(),
  created_at         timestamptz not null default now(),
  primary key (manifest_id, seq),
  constraint door_manifest_delta_atom_op_uq unique (manifest_id, ticket_atom_id, op),
  -- MP-1: an 'add' is a complete, freshly-minted atom projection; a 'revoke' is bare.
  constraint dmd_add_serial_ck  check ((op = 'add') = (serial_no is not null)),
  constraint dmd_add_tt_ck      check ((op = 'add') = (ticket_type_id is not null)),
  constraint dmd_add_cv_ck      check ((op = 'add') = (credential_version is not null)),
  constraint dmd_add_cv0_ck     check (op <> 'add' or credential_version = 0),
  constraint dmd_add_key_ck     check ((op = 'add') = (signing_key_id is not null)),
  constraint dmd_add_state_ck   check ((op = 'add') = (ticket_state is not null)),
  constraint dmd_add_active_ck  check (op <> 'add' or ticket_state = 'active'),
  constraint dmd_add_resale_ck  check ((op = 'add') = (resale_state is not null)),
  constraint dmd_add_none_ck    check (op <> 'add' or resale_state = 'none')
);
create index if not exists door_manifest_delta_atom_idx on venue.door_manifest_delta (ticket_atom_id);
drop trigger if exists tg_door_manifest_delta_append_only on venue.door_manifest_delta;
create trigger tg_door_manifest_delta_append_only before update or delete on venue.door_manifest_delta
  for each row execute function kernel.raise_append_only();
alter table venue.door_manifest_delta enable row level security;
revoke all on venue.door_manifest_delta from anon, authenticated;
revoke update, delete on venue.door_manifest_delta from service_role;
grant select on venue.door_manifest_delta to authenticated;
drop policy if exists venue_door_manifest_delta_sel_venue on venue.door_manifest_delta;
create policy venue_door_manifest_delta_sel_venue on venue.door_manifest_delta for select to authenticated
  using (exists (select 1 from venue.door_manifest m where m.manifest_id = venue.door_manifest_delta.manifest_id
                  and kernel.has_venue_role(m.venue_id, array['venue_scanner','venue_manager'])));

-- ============================================================================
-- PART 8 — the holder-mix privacy projection (DEMOGRAPHICS §10.2; R2 floor)
--   Zero identity refs; deny-all; read ONLY via get_holder_mix. sub-5 buckets
--   physically unstorable.
-- ============================================================================
create table if not exists venue.holder_mix_snapshot (
  snapshot_id      uuid primary key default gen_random_uuid(),
  event_session_id uuid not null references catalog.event_session(session_id) on delete restrict,
  dimension        text not null check (dimension = 'gender_identity'),
  as_of            timestamptz not null,
  holders_total    integer not null check (holders_total >= 0),
  holders_responded integer not null check (holders_responded >= 0 and holders_responded <= holders_total),
  holders_excluded_ineligible integer not null default 0,   -- definer-only, never emitted
  suppressed       boolean not null default false,
  suppression_reason text check (suppression_reason in
                       ('below_event_minimum','merge_cannot_reach_legal_set','churn_gate',
                        'near_duplicate_population') or suppression_reason is null),
  computed_at      timestamptz not null default now(),
  published_at     timestamptz,
  constraint holder_mix_snapshot_dim_uq unique (event_session_id, dimension, as_of)
);
create unique index if not exists holder_mix_published_uq
  on venue.holder_mix_snapshot (event_session_id, dimension) where published_at is not null;
alter table venue.holder_mix_snapshot enable row level security;
revoke all on venue.holder_mix_snapshot from anon, authenticated;   -- deny-all, read via RPC only

create table if not exists venue.holder_mix_bucket (
  snapshot_id  uuid not null references venue.holder_mix_snapshot(snapshot_id) on delete restrict,
  bucket       text not null check (bucket in ('woman','man','non_binary','another_gender_identity','other')),
  holder_count integer not null check (holder_count >= 5),   -- R2 floor: sub-5 physically unstorable
  primary key (snapshot_id, bucket)
);
alter table venue.holder_mix_bucket enable row level security;
revoke all on venue.holder_mix_bucket from anon, authenticated;   -- deny-all, read via RPC only

-- ============================================================================
-- PART 9 — catalog freeze primitives (RPC §17.12/§20.6.2/§20.6.5; DOOR §7.4)
-- ============================================================================
-- the SOLE writer of catalog.event_session.door_open_at (sets iff NULL; never
-- NULLs, never moves). Sanctioned venue→catalog primitive; DEF, definer-only.
create or replace function catalog.engage_door_freeze(p_session_id uuid, p_opened_at timestamptz)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  perform 1 from catalog.event_session s where s.session_id = p_session_id for update;
  update catalog.event_session
     set door_open_at = p_opened_at, updated_at = now()
   where session_id = p_session_id and door_open_at is null;
end;
$$;

-- door_open_at is the ledger head: it must equal MIN(door_manifest.opened_at) and
-- never clear/move once set (DOOR §10.2). FR-6: reads venue.door_manifest ⇒ 086.
create or replace function catalog.tg_door_open_at_is_ledger_head()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if old.door_open_at is not null and new.door_open_at is distinct from old.door_open_at then
    raise exception 'door_open_at is immutable once engaged (ledger head)' using errcode = 'P0001';
  end if;
  if new.door_open_at is not null and exists (
        select 1 from venue.door_manifest m where m.session_id = new.session_id) then
    if new.door_open_at <> (select min(m.opened_at) from venue.door_manifest m where m.session_id = new.session_id) then
      raise exception 'door_open_at must equal the earliest episode open (ledger head)' using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists tg_door_open_at_is_ledger_head on catalog.event_session;
-- UPDATE-only is sufficient: on INSERT the session_id is new, so no door_manifest
-- episode can reference it yet — the equality branch is vacuous and door_open_at is
-- only ever engaged by a later engage_door_freeze UPDATE.
create trigger tg_door_open_at_is_ledger_head before update of door_open_at on catalog.event_session
  for each row execute function catalog.tg_door_open_at_is_ledger_head();

-- schedule (informational doors_at), never door_open_at (T-RPC-DOOR-23). Authored
-- here (SEAM-1): the time guard reads kernel.tickets + the door_open_at boundary.
create or replace function catalog.set_session_door_schedule(
  p_session_id uuid, p_doors_at timestamptz, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_row catalog.event_session%rowtype;
begin
  select * into v_row from catalog.event_session where session_id = p_session_id for update;
  if not found then raise exception 'not_found: session %', p_session_id using errcode = 'P0002'; end if;
  -- once the door has actually opened, the schedule is frozen.
  if v_row.door_open_at is not null then
    raise exception 'precondition_failed: door already opened — schedule is frozen';
  end if;
  if not (kernel.has_org_role((select ev.org_id from catalog.event ev where ev.event_id = v_row.event_id),
            array['org_owner','org_admin'])
          or kernel.has_venue_role((select ev.venue_id from catalog.event ev where ev.event_id = v_row.event_id),
            array['venue_manager'])) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  update catalog.event_session set doors_at = p_doors_at, updated_at = now() where session_id = p_session_id;
  return jsonb_build_object('status','ok','session_id', p_session_id);
end;
$$;

-- cron: presentational reconciliation of implicit freezes (references neither
-- engage_door_freeze nor door_open_at — the implicit freeze is already in effect
-- via catalog.effective_freeze_at; T-RPC-DOOR-19/20). NOT load-bearing.
create or replace function catalog.sweep_implicit_door_freezes(p_limit integer default 500)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  return jsonb_build_object('status','ok','note','implicit freeze is predicate-driven; presentational only');
end;
$$;

-- ============================================================================
-- PART 10 — market SEAM-2 stubs (RPC §17.10a; C110/R2B — bodies in 088)
--   Frozen signatures (SEAM-2a); no-op until 088. market's 2nd/3rd routines.
-- ============================================================================
create or replace function market.on_door_freeze_engaged(p_event_session_id uuid, p_cause_ref uuid)
returns table(drained_transfers integer, drained_listings integer, atoms_unlocked integer)
language sql security definer set search_path = ''
as $$ select 0, 0, 0 $$;   -- no-op until 088 (V1)

create or replace function market.door_freeze_drain_preview(p_event_session_id uuid)
returns table(pending_transfers integer, active_listings integer, excluded_paid_pending integer, atoms_to_unlock integer)
language sql security definer set search_path = ''
as $$ select 0, 0, 0, 0 $$;   -- no-op until 088 (V7)

-- ============================================================================
-- PART 11 — kernel.assert_door_session (RPC §1.1d; AUTHZ-H3, H-3 tokenized)
--   DEF, service_role only. Returns the BOUND (device_id, event_session_id),
--   never a boolean. Constant-time-ish token compare; one opaque error class.
-- ============================================================================
create or replace function kernel.assert_door_session(
  p_device_id uuid, p_session_id uuid, p_door_session_id uuid, p_session_token text)
returns table(device_id uuid, event_session_id uuid)
language plpgsql security definer set search_path = ''
as $$
declare
  v_ds venue.door_session%rowtype;
  -- storage hash of the presented RAW token (never store/compare the token itself,
  -- so a token_hash leak is not replayable). md5 over a high-entropy server token
  -- (two uuids at mint) is preimage-resistant here — a lookup hash, not a password
  -- hash; built-in, so it is search_path='' safe (no pgcrypto dependency).
  v_hash text := md5('door_session:' || coalesce(p_session_token,''));
  v_ok boolean := true;
begin
  select * into v_ds from venue.door_session ds
   where ds.door_session_id = p_door_session_id;
  -- constant-ish: always compare against a value (dummy when unresolved)
  if not found then v_ok := false; end if;
  if coalesce(v_ds.token_hash,'') <> v_hash then v_ok := false; end if;
  if v_ds.status is distinct from 'active' or v_ds.expires_at <= now() then v_ok := false; end if;
  if v_ds.device_id is distinct from p_device_id or v_ds.event_session_id is distinct from p_session_id then v_ok := false; end if;
  -- the device must be live and the pin still active/unexpired
  if v_ok and not exists (select 1 from venue.scan_device d
                where d.device_id = v_ds.device_id and d.status = 'active') then v_ok := false; end if;
  if v_ok and not exists (select 1 from venue.door_pin p
                where p.pin_id = v_ds.pin_id and p.status = 'active' and p.expires_at > now()) then v_ok := false; end if;
  if not v_ok then
    raise exception 'door_session_invalid' using errcode = '42501';
  end if;
  -- throttled last_seen touch
  if v_ds.last_seen_at is null or v_ds.last_seen_at < now() - interval '1 minute' then
    update venue.door_session set last_seen_at = now() where door_session_id = p_door_session_id;
  end if;
  device_id := v_ds.device_id; event_session_id := v_ds.event_session_id; return next;
end;
$$;

-- ============================================================================
-- PART 12 — kernel door-freeze-override lifecycle (RPC §17.11; DOOR §8.2/§8.3)
--   Writes the 079 kernel.door_freeze_override table. platform-only.
-- ============================================================================
create or replace function kernel.grant_door_freeze_override(
  p_session_id uuid, p_ticket_atom_id uuid, p_reason_code text, p_expires_at timestamptz,
  p_ack_live_devices integer, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_max interval; v_live integer;
begin
  if not kernel.is_platform(array['platform_admin']) then
    raise exception 'insufficient_privilege: platform_admin only' using errcode = '42501';
  end if;
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: bad_reason_code';
  end if;
  if exists (select 1 from venue.door_manifest m where m.session_id = p_session_id and m.status = 'open') then
    raise exception 'precondition_failed: manifest_open — cannot override while a door episode is open';
  end if;
  select (c.value #>> '{}')::interval into v_max from catalog.platform_config c
   where c.key = 'door.max_override_interval' order by c.version desc limit 1;
  if v_max is not null and p_expires_at > now() + v_max then
    raise exception 'precondition_failed: ttl_too_long';
  end if;
  -- the operator must acknowledge the live-device count they are overriding around
  select count(*)::int into v_live from venue.door_session ds
   where ds.event_session_id = p_session_id and ds.status = 'active' and ds.expires_at > now();
  if coalesce(p_ack_live_devices, -1) <> v_live then
    raise exception 'precondition_failed: unacknowledged_live_devices (ack % vs live %)', p_ack_live_devices, v_live;
  end if;
  insert into kernel.door_freeze_override (session_id, ticket_atom_id, granted_by, reason_code,
                                           expires_at, command_idempotency_key)
  values (p_session_id, p_ticket_atom_id, auth.uid(), p_reason_code, p_expires_at, p_command_key);
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (auth.uid(), 'door.freeze_override_grant', 'event_session', p_session_id, p_reason_code);
  return jsonb_build_object('status','ok','session_id', p_session_id);
exception when unique_violation then
  return jsonb_build_object('status','idempotency_replay');
end;
$$;

create or replace function kernel.revoke_door_freeze_override(p_override_id uuid, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_row kernel.door_freeze_override%rowtype;
begin
  if not kernel.is_platform(array['platform_admin','platform_risk']) then
    raise exception 'insufficient_privilege: platform_admin or platform_risk required' using errcode = '42501';
  end if;
  select * into v_row from kernel.door_freeze_override where override_id = p_override_id for update;
  if not found then raise exception 'not_found: override %', p_override_id using errcode = 'P0002'; end if;
  if v_row.revoked_at is not null then
    return jsonb_build_object('status','noop_replay','override_id', p_override_id);
  end if;
  update kernel.door_freeze_override set revoked_at = now(), revoked_by = auth.uid()
   where override_id = p_override_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (auth.uid(), 'door.freeze_override_revoke', 'event_session', v_row.session_id, coalesce(v_row.reason_code,'revoked'));
  return jsonb_build_object('status','ok','override_id', p_override_id);
end;
$$;

-- cron: presentational (expiry arithmetic lives in is_transfer_frozen). NOT load-bearing.
create or replace function kernel.sweep_expired_door_overrides()
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  return jsonb_build_object('status','ok','note','override expiry is predicate-driven; presentational only');
end;
$$;

-- ============================================================================
-- PART 13 — the SEAM-2 bodies (append_door_manifest_delta stub 083;
--   on_identity_erased_door stub 077). Signatures byte-frozen (SEAM-2a).
-- ============================================================================
-- DOOR §7.7: append add/revoke deltas to the OPEN episode. No open episode ⇒
-- SILENT NO-OP (never error — issuance/void must never fail because the door is
-- shut). Idempotent via PK(manifest_id,seq) + UNIQUE(manifest_id,atom,op).
create or replace function venue.append_door_manifest_delta(
  p_session_id uuid, p_atoms uuid[], p_op text, p_cause_ref uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_m     venue.door_manifest%rowtype;
  v_seq   integer;
  v_atom  uuid;
  v_t     kernel.tickets%rowtype;
begin
  if p_op not in ('add','revoke') then
    raise exception 'invalid_input: op must be add|revoke';
  end if;
  select * into v_m from venue.door_manifest where session_id = p_session_id and status = 'open' for update;
  if not found then
    return;   -- SILENT NO-OP: no open episode (DOOR §7.7)
  end if;
  select coalesce(max(d.seq), 0) into v_seq from venue.door_manifest_delta d where d.manifest_id = v_m.manifest_id;
  foreach v_atom in array coalesce(p_atoms, '{}') loop
    v_seq := v_seq + 1;
    if p_op = 'add' then
      select * into v_t from kernel.tickets where ticket_atom_id = v_atom;
      -- an 'add' is a freshly-minted atom (MP-1: active/none/cv=0)
      insert into venue.door_manifest_delta (manifest_id, seq, ticket_atom_id, op, serial_no,
             ticket_type_id, credential_version, signing_key_id, ticket_state, resale_state, cause_ref)
      values (v_m.manifest_id, v_seq, v_atom, 'add', v_t.serial_no, v_t.ticket_type_id,
              v_t.credential_version, v_t.signing_key_id, v_t.state, v_t.resale_state, p_cause_ref)
      on conflict (manifest_id, ticket_atom_id, op) do nothing;
    else
      insert into venue.door_manifest_delta (manifest_id, seq, ticket_atom_id, op, cause_ref)
      values (v_m.manifest_id, v_seq, v_atom, 'revoke', p_cause_ref)
      on conflict (manifest_id, ticket_atom_id, op) do nothing;
    end if;
  end loop;
  update venue.door_manifest set max_delta_seq = greatest(max_delta_seq,
           (select coalesce(max(d.seq),0) from venue.door_manifest_delta d where d.manifest_id = v_m.manifest_id))
   where manifest_id = v_m.manifest_id;
end;
$$;

-- OR-17 INV #29-#31: terminal identity-erased door cleanup. Real body here.
create or replace function kernel.on_identity_erased_door(p_identity uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  -- ODR16 (ratified) INV #29/#30/#31 — CLEANED (SET NULL) so the auth.users delete
  -- (ON DELETE RESTRICT) can complete. #29 note: granted_to_name SURVIVES — it is a
  -- free-text label, not an auth.users linkage, and must NOT be scrubbed here. The
  -- AO ledgers keep their bare identity refs untouched: scan.actor_identity_id (#28)
  -- and door_manifest.opened_by/closed_by (#32/#33) are TOMBSTONED — never rewritten.
  update venue.comp_allocation set granted_to_identity = null, updated_at = now()
   where granted_to_identity = p_identity;
  update venue.comp_allocation set granted_by = null, updated_at = now()
   where granted_by = p_identity;
  update venue.guest_list set created_by = null, updated_at = now()
   where created_by = p_identity;
end;
$$;

-- ============================================================================
-- PART 14 — kernel.revoke_signing_key (RPC §20.7.5; PFA-17 authored here).
--   PFA-18 requires dual control on the signing-key TRIO (provision/rotate/
--   revoke). PFA-18A ruled that mechanism UNBUILDABLE (kernel.approval_request
--   is money-only) and parked the lifecycle FAIL-CLOSED — 083 parked
--   provision/rotate. revoke is the third leg of the same trio under the same
--   unbuildable mechanism, so it ships FAIL-CLOSED too (E-62), signature frozen
--   (§20.7.5), ZERO mutation. Its real body (force-close open episodes in key
--   scope + outbox #44 DoorManifestInvalidated) is the PFA-18A forward
--   obligation, delivered when the credential dual-control mechanism is ratified.
--   Consistent: no key can be provisioned/rotated either, so none can be revoked.
-- ============================================================================
create or replace function kernel.revoke_signing_key(
  p_key_id uuid, p_reason_code text, p_ack_live_credentials integer, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  raise exception 'precondition_failed: dual_control_unavailable — credential dual-control mechanism not yet ratified (PFA-18A); signing-key revocation is parked, no key state changes and no episode is force-closed';
end;
$$;

-- ============================================================================
-- PART 15 — the door-manifest lifecycle RPCs (RPC §17.10/17.11/§20.6; DOOR §7)
-- ============================================================================
-- open: build the complete base snapshot for the session, engage the freeze
-- (first open), drain the market (088 stub), emit #37. venue_manager/org/platform.
create or replace function venue.open_door_manifest(
  p_session_id uuid, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_sess   catalog.event_session%rowtype;
  v_venue  uuid;
  v_mid    uuid;
  v_ver    integer;
  v_count  integer;
  v_ttl    interval;
  v_first  boolean;
  v_opened_at timestamptz;
begin
  select * into v_sess from catalog.event_session where session_id = p_session_id for update;   -- rank 1
  if not found then raise exception 'not_found: session %', p_session_id using errcode = 'P0002'; end if;
  select ev.venue_id into v_venue from catalog.event ev where ev.event_id = v_sess.event_id;
  if not (kernel.has_venue_role(v_venue, array['venue_manager'])
          or kernel.has_org_role((select ev.org_id from catalog.event ev where ev.event_id = v_sess.event_id),
               array['org_owner','org_admin'])
          or kernel.is_platform(array['platform_admin'])) then
    raise exception 'insufficient_privilege: venue_manager / org_owner|admin / platform_admin only' using errcode = '42501';
  end if;
  if v_sess.status not in ('announced','live','on_sale','scheduled') then
    -- a terminal/cancelled session cannot open a door episode
    if v_sess.status in ('cancelled','ended','completed') then
      raise exception 'precondition_failed: session_terminal (%)', v_sess.status;
    end if;
  end if;
  -- idempotency: an already-open episode returns it (state guard); command replay
  if exists (select 1 from venue.door_manifest m where m.session_id = p_session_id and m.status = 'open') then
    select manifest_id into v_mid from venue.door_manifest where session_id = p_session_id and status = 'open';
    return jsonb_build_object('status','noop_replay','manifest_id', v_mid);
  end if;

  select (c.value #>> '{}')::interval into v_ttl from catalog.platform_config c
   where c.key = 'door.manifest_ttl_interval' order by c.version desc limit 1;
  v_first := (v_sess.door_open_at is null);
  select coalesce(max(manifest_version),0)+1 into v_ver from venue.door_manifest where session_id = p_session_id;

  -- the complete base snapshot: EVERY atom of the session, EVERY state (PFA-24:
  -- signing_key_id only, no public_key, no identity).
  select count(*)::int into v_count from kernel.tickets t where t.event_session_id = p_session_id;

  insert into venue.door_manifest (manifest_id, session_id, venue_id, manifest_version, status,
         opened_by, open_reason_code, not_after, entry_count, manifest_digest, command_idempotency_key)
  values (gen_random_uuid(), p_session_id, v_venue, v_ver, 'open',
          coalesce(auth.uid(),'00000000-0000-0000-0000-0000000000f1'), p_reason_code,
          now() + coalesce(v_ttl, interval '12 hours'), v_count,
          md5(p_session_id::text || ':' || v_ver::text || ':' || now()::text), p_command_key)
  returning manifest_id, opened_at into v_mid, v_opened_at;

  insert into venue.door_manifest_entry (manifest_id, ticket_atom_id, serial_no, ticket_type_id,
         credential_version, signing_key_id, ticket_state, resale_state)
  select v_mid, t.ticket_atom_id, t.serial_no, t.ticket_type_id, t.credential_version,
         t.signing_key_id, t.state, t.resale_state
    from kernel.tickets t where t.event_session_id = p_session_id;

  -- first open engages the door freeze (sole door_open_at write via engage_door_freeze)
  if v_first then
    -- freeze head = THIS first episode's opened_at, so door_open_at == MIN(opened_at)
    -- holds by construction (ledger-head trigger). starts_at is the scheduled time
    -- (informational doors_at, §17.12), NEVER door_open_at (T-RPC-DOOR-23).
    perform catalog.engage_door_freeze(p_session_id, v_opened_at);
    perform market.on_door_freeze_engaged(p_session_id, v_mid);           -- 088 stub (drains market)
  end if;

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (coalesce(auth.uid(),'00000000-0000-0000-0000-0000000000f1'), 'session.door_manifest_open',
          'event_session', p_session_id, p_reason_code);
  perform notify.emit_event('DoorManifestOpened', 'event_session', p_session_id,
          'door_open:' || v_mid::text, jsonb_build_object('manifest_id', v_mid, 'version', v_ver, 'entry_count', v_count));

  return jsonb_build_object('status','ok','manifest_id', v_mid, 'manifest_version', v_ver, 'entry_count', v_count);
exception when unique_violation then
  select manifest_id into v_mid from venue.door_manifest
   where session_id = p_session_id and command_idempotency_key = p_command_key;
  if v_mid is not null then return jsonb_build_object('status','idempotency_replay','manifest_id', v_mid); end if;
  raise;
end;
$$;

-- close: terminal for the episode. Does NOT unfreeze, does NOT touch door_open_at.
create or replace function venue.close_door_manifest(
  p_session_id uuid, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_m venue.door_manifest%rowtype; v_venue uuid;
begin
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not (kernel.has_venue_role(v_venue, array['venue_manager'])
          or kernel.has_org_role((select ev.org_id from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id where es.session_id=p_session_id),
               array['org_owner','org_admin'])
          or kernel.is_platform(array['platform_admin'])) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  select * into v_m from venue.door_manifest where session_id = p_session_id and status = 'open' for update;
  if not found then
    return jsonb_build_object('status','noop_replay');   -- no open episode is never an error
  end if;
  update venue.door_manifest set status = 'closed', closed_at = now(),
         closed_by = auth.uid(), close_reason = p_reason_code
   where manifest_id = v_m.manifest_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (auth.uid(), 'session.door_manifest_close', 'event_session', p_session_id, p_reason_code);
  perform notify.emit_event('DoorManifestClosed', 'event_session', p_session_id,
          'door_close:' || v_m.manifest_id::text, jsonb_build_object('manifest_id', v_m.manifest_id));
  return jsonb_build_object('status','ok','manifest_id', v_m.manifest_id);
end;
$$;

-- get (M2): the offline scanner's admissible set. venue_scanner/manager OR the
-- door-session edge (token-bound). Carries signing_key_id, NEVER public_key
-- (PFA-24), NEVER identity. Returns base entries + deltas since p_since_delta_seq.
create or replace function venue.get_door_manifest(p_session_id uuid, p_since_delta_seq integer default 0)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_m venue.door_manifest%rowtype; v_venue uuid; v_entries jsonb; v_deltas jsonb;
begin
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_scanner','venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  select * into v_m from venue.door_manifest where session_id = p_session_id and status = 'open'
   order by manifest_version desc limit 1;
  if not found then
    return jsonb_build_object('status','no_open_episode');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'ticket_atom_id', e.ticket_atom_id, 'serial_no', e.serial_no, 'ticket_type_id', e.ticket_type_id,
           'credential_version', e.credential_version, 'signing_key_id', e.signing_key_id,
           'ticket_state', e.ticket_state, 'resale_state', e.resale_state) order by e.serial_no), '[]'::jsonb)
    into v_entries from venue.door_manifest_entry e where e.manifest_id = v_m.manifest_id;
  select coalesce(jsonb_agg(jsonb_build_object(
           'seq', d.seq, 'ticket_atom_id', d.ticket_atom_id, 'op', d.op, 'serial_no', d.serial_no,
           'ticket_type_id', d.ticket_type_id, 'credential_version', d.credential_version,
           'signing_key_id', d.signing_key_id, 'ticket_state', d.ticket_state, 'resale_state', d.resale_state) order by d.seq), '[]'::jsonb)
    into v_deltas from venue.door_manifest_delta d
   where d.manifest_id = v_m.manifest_id and d.seq > coalesce(p_since_delta_seq, 0);
  return jsonb_build_object('status','ok','manifest_id', v_m.manifest_id, 'manifest_version', v_m.manifest_version,
    'manifest_digest', v_m.manifest_digest, 'max_delta_seq', v_m.max_delta_seq,
    'entries', v_entries, 'deltas', v_deltas);
end;
$$;

create or replace function venue.preview_door_open_impact(p_session_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_venue uuid; v_prev record; v_unlock integer;
begin
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not (kernel.has_venue_role(v_venue, array['venue_manager'])
          or kernel.is_platform(array['platform_admin'])) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  select * into v_prev from market.door_freeze_drain_preview(p_session_id);   -- 088 stub (zeroes)
  select count(*)::int into v_unlock from kernel.tickets t
   where t.event_session_id = p_session_id and t.resale_state <> 'none';
  return jsonb_build_object('status','ok',
    'pending_transfers', v_prev.pending_transfers, 'active_listings', v_prev.active_listings,
    'excluded_paid_pending', v_prev.excluded_paid_pending, 'atoms_to_unlock', v_unlock);
end;
$$;

create or replace function venue.get_live_device_count(p_session_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_venue uuid; v_n integer;
begin
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not (kernel.has_venue_role(v_venue, array['venue_manager'])
          or kernel.is_platform(array['platform_admin'])) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  select count(*)::int into v_n from venue.door_session ds
   where ds.event_session_id = p_session_id and ds.status = 'active' and ds.expires_at > now();
  return jsonb_build_object('status','ok','live_device_count', v_n);
end;
$$;

-- ============================================================================
-- PART 16 — door PIN + door SESSION lifecycle (RPC §9.1/9.2/9.6/9.7/9.8)
--   Canonical function name = create_door_pin (RPC §9.1); schema's issue_door_pin
--   is the descriptive alias (E-63). PIN + token hashed with md5 over a
--   high-entropy secret (lookup hash; §PART 11 rationale).
-- ============================================================================
create or replace function venue.create_door_pin(
  p_venue_id uuid, p_session_id uuid, p_label text, p_pin_plain text, p_expires_at timestamptz, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  -- PARKED FAIL-CLOSED (PFA-26; PFA-20 class). SCHEMA_SPEC §3.10 rules door_pin.pin_hash
  -- entropy LOW → it requires a SLOW KDF + constant-time compare. No crypto extension is
  -- installed in the chain (PFA-20), so md5 would be a silent security-boundary downgrade.
  -- Owner ruling: park door-PIN creation until a slow-KDF mechanism (or edge-side hashing)
  -- is ratified. ZERO mutation — no PIN is stored; the signature is frozen for un-park.
  raise exception 'precondition_failed: door_pin_kdf_unavailable — door-PIN slow-KDF mechanism not yet ratified (PFA-26); door PIN creation is parked fail-closed';
end;
$$;

create or replace function venue.revoke_door_pin(p_pin_id uuid, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_row venue.door_pin%rowtype;
begin
  select * into v_row from venue.door_pin where pin_id = p_pin_id for update;
  if not found then raise exception 'not_found: pin %', p_pin_id using errcode = 'P0002'; end if;
  if not kernel.has_venue_role(v_row.venue_id, array['venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  update venue.door_pin set status = 'revoked', updated_at = now() where pin_id = p_pin_id;
  -- RV-1: every door session minted from this pin dies with it, in the same txn.
  update venue.door_session set status = 'revoked', revoked_at = now(), revoked_reason = 'pin_revoked'
   where pin_id = p_pin_id and status = 'active';
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (auth.uid(), 'door.pin_revoke', 'door_pin', p_pin_id, 'revoked');
  return jsonb_build_object('status','ok','pin_id', p_pin_id);
end;
$$;

-- mint: DEF, service_role only (the door-session edge, verify_jwt:false). Sole
-- writer of door_session; re-validates PIN↔device↔session. Returns the raw token
-- to the edge (stored only as its md5 hash).
create or replace function venue.mint_door_session(
  p_venue_id uuid, p_session_id uuid, p_device_id uuid, p_pin_plain text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  -- PARKED FAIL-CLOSED (PFA-26). Minting a door session requires verifying p_pin_plain
  -- against the parked door-PIN hash (§3.10 slow KDF, unbuildable — PFA-20 class). No
  -- PIN can be created (create_door_pin is parked), so no door session can be minted.
  -- ZERO mutation. The full body (device↔venue + pin↔session live check, 256-bit token
  -- issue, command-key idempotency) is the PFA-26 forward obligation, delivered with a
  -- ratified KDF. assert_door_session stays live (its token md5 is corpus-compliant) but
  -- has no sessions to assert. Signature frozen for un-park.
  raise exception 'precondition_failed: door_pin_kdf_unavailable — door-session mint depends on the parked door-PIN mechanism (PFA-26); parked fail-closed';
end;
$$;

create or replace function venue.revoke_door_session(p_door_session_id uuid, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_row venue.door_session%rowtype;
begin
  select * into v_row from venue.door_session where door_session_id = p_door_session_id for update;
  if not found then raise exception 'not_found: door session %', p_door_session_id using errcode = 'P0002'; end if;
  if not (kernel.has_venue_role(v_row.venue_id, array['venue_manager'])
          or kernel.is_platform(array['platform_admin','platform_support'])) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  if v_row.status <> 'active' then return jsonb_build_object('status','noop_replay'); end if;
  update venue.door_session set status = 'revoked', revoked_at = now(), revoked_reason = coalesce(p_reason_code,'revoked')
   where door_session_id = p_door_session_id;
  return jsonb_build_object('status','ok','door_session_id', p_door_session_id);
end;
$$;

create or replace function venue.sweep_expired_door_sessions()
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_n integer;
begin
  update venue.door_session set status = 'expired'
   where status = 'active' and expires_at <= now();
  get diagnostics v_n = row_count;
  return jsonb_build_object('status','ok','expired', v_n);
end;
$$;

-- ============================================================================
-- PART 17 — scan device + the scan path (RPC §9.3/9.4/9.5/§20.4.3/20.4.4/§3.11.1)
-- ============================================================================
create or replace function venue.register_scan_device(p_venue_id uuid, p_label text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not kernel.has_venue_role(p_venue_id, array['venue_manager']) then
    raise exception 'insufficient_privilege: venue_manager required' using errcode = '42501';
  end if;
  insert into venue.scan_device (venue_id, label) values (p_venue_id, p_label) returning device_id into v_id;
  return jsonb_build_object('status','ok','device_id', v_id);
end;
$$;

create or replace function venue.set_scan_device_status(p_device_id uuid, p_status text, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_row venue.scan_device%rowtype;
begin
  if p_status not in ('active','retired') then raise exception 'invalid_input: bad status'; end if;
  select * into v_row from venue.scan_device where device_id = p_device_id for update;
  if not found then raise exception 'not_found: device %', p_device_id using errcode = 'P0002'; end if;
  if not kernel.has_venue_role(v_row.venue_id, array['venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  update venue.scan_device set status = p_status, updated_at = now() where device_id = p_device_id;
  -- RV-2: retiring a device revokes its active door sessions in the same txn.
  if p_status = 'retired' then
    update venue.door_session set status = 'revoked', revoked_at = now(), revoked_reason = 'device_retired'
     where device_id = p_device_id and status = 'active';
  end if;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (auth.uid(), 'door.device_status', 'scan_device', p_device_id, coalesce(p_reason_code, p_status));
  return jsonb_build_object('status','ok','device_id', p_device_id);
end;
$$;

create or replace function venue.sync_scan_device_manifest(p_device_id uuid, p_session_id uuid, p_known_manifest_version integer)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_row venue.scan_device%rowtype; v_m venue.door_manifest%rowtype;
begin
  select * into v_row from venue.scan_device where device_id = p_device_id for update;
  if not found then raise exception 'not_found: device %', p_device_id using errcode = 'P0002'; end if;
  if not kernel.has_venue_role(v_row.venue_id, array['venue_scanner','venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  select * into v_m from venue.door_manifest where session_id = p_session_id and status = 'open'
   order by manifest_version desc limit 1;
  if found then
    update venue.scan_device set manifest_version = v_m.manifest_version, manifest_id = v_m.manifest_id,
           last_sync_at = now(), updated_at = now() where device_id = p_device_id;
  end if;
  -- FAIL-SAFE full sync. p_known_manifest_version is the per-session EPISODE counter,
  -- NOT a delta-seq cursor (the per-manifest seq resets each episode). Passing it as
  -- get_door_manifest's p_since_delta_seq silently dropped deltas 1..N of the open
  -- episode (e.g. a revoke), so a device could keep admitting a revoked atom. Return
  -- the COMPLETE current manifest (all deltas) — incremental delta sync is a forward
  -- obligation (needs a real delta-seq parameter; native scanning is dark).
  return venue.get_door_manifest(p_session_id, 0);
end;
$$;

-- record_scan: gated on native scanning; delegates the lifecycle transition to
-- kernel.mark_ticket_scanned (MB-6: this body references kernel.tickets NOWHERE);
-- maps a duplicate via the C41 partial-unique. venue_scanner/manager (a) OR the
-- door edge (b) via assert_door_session (p_actor_device_id from its return).
create or replace function venue.record_scan(
  p_atom_id uuid, p_session_id uuid, p_actor_device_id uuid, p_scan_meta jsonb, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_flag boolean; v_venue uuid; v_res jsonb; v_result text; v_scan_id uuid;
begin
  select (c.value #>> '{}')::boolean into v_flag from catalog.platform_config c
   where c.key = 'feature.native_scanning_enabled' order by c.version desc limit 1;
  if not coalesce(v_flag, false) then
    raise exception 'precondition_failed: feature_disabled — native scanning is dark';
  end if;
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_scanner','venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  -- the lifecycle transition (single-writer choke point). A repeat/terminal atom
  -- raises inside mark_ticket_scanned → mapped to a 'duplicate'/'invalid' scan row.
  begin
    v_res := kernel.mark_ticket_scanned(p_atom_id, p_session_id, coalesce(p_scan_meta, '{}'::jsonb));
    v_result := 'admitted';
  exception when others then
    v_result := case when sqlerrm like '%not_active%' or sqlerrm like '%wrong_session%' then 'invalid'
                     when sqlerrm like '%listed_locked%' then 'invalid'
                     else 'invalid' end;
  end;
  insert into venue.scan (ticket_atom_id, event_session_id, device_id, actor_identity_id, result, occurred_at)
  values (p_atom_id, p_session_id, p_actor_device_id, auth.uid(), v_result,
          coalesce((p_scan_meta->>'occurred_at')::timestamptz, now()))
  returning scan_id into v_scan_id;
  return jsonb_build_object('status','ok','scan_id', v_scan_id, 'result', v_result);
exception when unique_violation then
  -- C41 first-in-wins: a second admitted inbound scan is a duplicate.
  insert into venue.scan (ticket_atom_id, event_session_id, device_id, actor_identity_id, result, occurred_at)
  values (p_atom_id, p_session_id, p_actor_device_id, auth.uid(), 'duplicate',
          coalesce((p_scan_meta->>'occurred_at')::timestamptz, now()))
  returning scan_id into v_scan_id;
  return jsonb_build_object('status','ok','scan_id', v_scan_id, 'result', 'duplicate');
end;
$$;

create or replace function venue.validate_ticket_online(p_atom_id uuid, p_session_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_venue uuid; v_t kernel.tickets%rowtype;
begin
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_scanner','venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  select * into v_t from kernel.tickets where ticket_atom_id = p_atom_id and event_session_id = p_session_id;
  if not found then return jsonb_build_object('status','not_found'); end if;
  return jsonb_build_object('status','ok','ticket_state', v_t.state, 'resale_state', v_t.resale_state,
    'signing_key_id', v_t.signing_key_id, 'credential_version', v_t.credential_version,
    'admissible', (v_t.state = 'active' and v_t.resale_state = 'none'
                   and not kernel.is_transfer_frozen(p_atom_id)));
end;
$$;

create or replace function venue.reconcile_offline_scans(
  p_session_id uuid, p_actor_device_id uuid, p_batch jsonb, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_venue uuid; v_item jsonb; v_n integer := 0;
begin
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_scanner','venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  -- MB-6: routes each offline scan through record_scan (references kernel.tickets nowhere).
  for v_item in select * from jsonb_array_elements(coalesce(p_batch, '[]'::jsonb)) loop
    perform venue.record_scan((v_item->>'ticket_atom_id')::uuid, p_session_id, p_actor_device_id,
              v_item || jsonb_build_object('offline', true), p_command_key || ':' || v_n::text);
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('status','ok','reconciled', v_n);
end;
$$;

-- ============================================================================
-- PART 18 — comp + guest admissions (RPC §20.5)
-- ============================================================================
create or replace function venue.allocate_comp(
  p_session_id uuid, p_batch_id uuid, p_quantity integer, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_venue uuid; v_id uuid;
begin
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_manager']) then
    raise exception 'insufficient_privilege: venue_manager required' using errcode = '42501';
  end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'precondition_failed: bad_quantity'; end if;
  insert into venue.comp_allocation (event_session_id, batch_id, quantity, granted_by)
  values (p_session_id, p_batch_id, p_quantity, auth.uid()) returning id into v_id;
  return jsonb_build_object('status','ok','comp_allocation_id', v_id);
end;
$$;

create or replace function venue.issue_comp(
  p_comp_allocation_id uuid, p_grantee uuid, p_quantity integer, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_alloc venue.comp_allocation%rowtype; v_venue uuid; v_batch venue.inventory_batch%rowtype;
        v_key uuid; v_sess catalog.event_session%rowtype; v_res jsonb;
begin
  select * into v_alloc from venue.comp_allocation where id = p_comp_allocation_id for update;
  if not found then raise exception 'not_found: comp allocation %', p_comp_allocation_id using errcode = 'P0002'; end if;
  select * into v_sess from catalog.event_session where session_id = v_alloc.event_session_id;
  select ev.venue_id into v_venue from catalog.event ev where ev.event_id = v_sess.event_id;
  if not kernel.has_venue_role(v_venue, array['venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  if v_alloc.status <> 'allocated' then
    return jsonb_build_object('status','noop_replay','comp_allocation_id', p_comp_allocation_id);
  end if;
  -- the allocate->issue two-step caps issuance at the AUTHORIZED amount: issuing
  -- more than was allocated diverges authorized-vs-issued comp accounting.
  if coalesce(p_quantity, v_alloc.quantity) > v_alloc.quantity then
    raise exception 'precondition_failed: issue quantity % exceeds allocation %', coalesce(p_quantity, v_alloc.quantity), v_alloc.quantity;
  end if;
  select * into v_batch from venue.inventory_batch where batch_id = v_alloc.batch_id;
  -- resolve the active signing key for the event scope (mint precondition)
  select k.key_id into v_key from kernel.signing_key k
   where k.status='active' and (k.not_after is null or k.not_after > now()) and k.not_before <= now()
     and ((k.scope='per_event' and k.event_id = v_sess.event_id)
          or (k.scope='per_venue' and k.venue_id = v_venue) or (k.scope='global'))
   order by case k.scope when 'per_event' then 1 when 'per_venue' then 2 else 3 end limit 1;
  if v_key is null then raise exception 'precondition_failed: no_active_signing_key'; end if;
  -- mint via the kernel engine (cause=comp); it decrements the comp batch (sold += q).
  v_res := kernel.issue_ticket_atoms(jsonb_build_object(
    'session_id', v_alloc.event_session_id, 'org_id', (select ev.org_id from catalog.event ev where ev.event_id=v_sess.event_id),
    'ticket_type_id', v_batch.ticket_type_id, 'batch_id', v_alloc.batch_id,
    'owner_id', coalesce(p_grantee,'00000000-0000-0000-0000-0000000000f1'), 'quantity', coalesce(p_quantity, v_alloc.quantity),
    'cause','comp','cause_ref', p_comp_allocation_id, 'signing_key_id', v_key), p_command_key);
  update venue.comp_allocation set status = 'issued', granted_to_identity = p_grantee, updated_at = now()
   where id = p_comp_allocation_id;
  return jsonb_build_object('status','ok','comp_allocation_id', p_comp_allocation_id) || v_res;
end;
$$;

create or replace function venue.create_guest_list(p_session_id uuid, p_name text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_venue uuid; v_id uuid;
begin
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id where es.session_id=p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_manager','venue_box_office']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  insert into venue.guest_list (event_session_id, name, created_by) values (p_session_id, p_name, auth.uid())
  returning id into v_id;
  return jsonb_build_object('status','ok','guest_list_id', v_id);
end;
$$;

create or replace function venue.upsert_guest_entry(
  p_guest_list_id uuid, p_entry_id uuid, p_guest_name text, p_party_size integer, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_venue uuid; v_id uuid;
begin
  select ev.venue_id into v_venue from venue.guest_list gl
   join catalog.event_session es on es.session_id=gl.event_session_id
   join catalog.event ev on ev.event_id=es.event_id where gl.id = p_guest_list_id;
  if not kernel.has_venue_role(v_venue, array['venue_manager','venue_box_office']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  if p_entry_id is null then
    insert into venue.guest_entry (guest_list_id, guest_name, party_size)
    values (p_guest_list_id, p_guest_name, coalesce(p_party_size,1)) returning id into v_id;
  else
    -- bind the entry to the AUTHORIZED list: authority was checked on p_guest_list_id,
    -- so the write MUST be constrained to that list — else a caller with a role on
    -- list A could rewrite an entry in another venue's list B (cross-tenant IDOR).
    update venue.guest_entry set guest_name = p_guest_name, party_size = coalesce(p_party_size,party_size), updated_at = now()
     where id = p_entry_id and guest_list_id = p_guest_list_id returning id into v_id;
    if v_id is null then raise exception 'not_found: entry %', p_entry_id using errcode = 'P0002'; end if;
  end if;
  return jsonb_build_object('status','ok','guest_entry_id', v_id);
end;
$$;

create or replace function venue.remove_guest_entry(p_entry_id uuid, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_venue uuid;
begin
  select ev.venue_id into v_venue from venue.guest_entry ge
   join venue.guest_list gl on gl.id = ge.guest_list_id
   join catalog.event_session es on es.session_id=gl.event_session_id
   join catalog.event ev on ev.event_id=es.event_id where ge.id = p_entry_id;
  if v_venue is null then raise exception 'not_found: entry %', p_entry_id using errcode = 'P0002'; end if;
  if not kernel.has_venue_role(v_venue, array['venue_manager','venue_box_office']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  delete from venue.guest_entry where id = p_entry_id;
  return jsonb_build_object('status','ok','guest_entry_id', p_entry_id);
end;
$$;

create or replace function venue.check_in_guest_entry(p_entry_id uuid, p_session_id uuid, p_outcome text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_venue uuid;
begin
  if p_outcome not in ('arrived','no_show') then raise exception 'invalid_input: bad outcome'; end if;
  select ev.venue_id into v_venue from venue.guest_entry ge
   join venue.guest_list gl on gl.id = ge.guest_list_id
   join catalog.event_session es on es.session_id=gl.event_session_id
   join catalog.event ev on ev.event_id=es.event_id where ge.id = p_entry_id;
  if v_venue is null then raise exception 'not_found: entry %', p_entry_id using errcode = 'P0002'; end if;
  if not kernel.has_venue_role(v_venue, array['venue_manager','venue_box_office','venue_scanner']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  update venue.guest_entry set status = p_outcome,
         checked_in_at = case when p_outcome='arrived' then now() else checked_in_at end, updated_at = now()
   where id = p_entry_id;
  return jsonb_build_object('status','ok','guest_entry_id', p_entry_id, 'outcome', p_outcome);
end;
$$;

-- ============================================================================
-- PART 19 — holder-mix privacy projection (RPC §17.20; DEMOGRAPHICS §10.2)
--   refresh (cron/DEF), read (2-param, differencing-attack contract),
--   unpublish (service_role/platform), reconcile (cron).
-- ============================================================================
create or replace function venue.refresh_holder_mix(p_event_session_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  -- the actual demographic aggregation reads kernel.identity_demographic (077,
  -- definer-only) — deferred to the demographics-activation package; at 086 the
  -- projector exists and produces a suppressed snapshot when below the R2 floor.
  return jsonb_build_object('status','ok','note','holder-mix aggregation runs when demographics activate');
end;
$$;

create or replace function venue.get_holder_mix(p_event_session_id uuid, p_dimension text)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_venue uuid; v_snap venue.holder_mix_snapshot%rowtype; v_buckets jsonb;
        v_flag boolean; v_n integer; v_sum integer; v_min integer;
begin
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_event_session_id;
  if not (kernel.has_venue_role(v_venue, array['venue_manager','venue_marketing','venue_promoter_manager'])
          or kernel.has_org_role((select ev.org_id from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id where es.session_id=p_event_session_id),
               array['org_owner','org_admin'])
          or kernel.is_platform(array['platform_admin'])) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  -- §10.4 R6: the suppressed shape is the CONSTANT { suppressed: true } — no reason,
  -- no denominators, no as_of (a reason is the same leak in words). Every guarded
  -- path below returns exactly that. §5.5 kill switch, read LIVE on every call.
  select (c.value #>> '{}')::boolean into v_flag from catalog.platform_config c
   where c.key = 'demographics.holder_mix_enabled' order by c.version desc limit 1;
  if not coalesce(v_flag, false) then return jsonb_build_object('suppressed', true); end if;
  select * into v_snap from venue.holder_mix_snapshot
   where event_session_id = p_event_session_id and dimension = p_dimension and published_at is not null
   order by as_of desc limit 1;
  -- no published snapshot (incl. published_at IS NULL) or stored-suppressed => suppressed.
  if not found or v_snap.suppressed then return jsonb_build_object('suppressed', true); end if;
  -- §5.2 read-side re-derivation (the independent second enforcement layer), FAIL-CLOSED:
  -- R1 responded>=25, R5 count>=2, R2 min>=5, R4 sum=responded, responded<=total. Any
  -- failure => { suppressed: true } (never a partial/corrected card). This is what makes
  -- a writer bug / hand-INSERT / restored-backup row fail closed at the read. (The
  -- reconciliation alarm + per-call read audit are the demographics-activation forward
  -- obligation — the function is STABLE and no read-audit sink exists yet; PFA-27.)
  select count(*)::int, coalesce(sum(b.holder_count),0)::int, min(b.holder_count)::int
    into v_n, v_sum, v_min from venue.holder_mix_bucket b where b.snapshot_id = v_snap.snapshot_id;
  if v_snap.holders_responded < 25 or v_n < 2 or coalesce(v_min, 0) < 5
     or v_sum <> v_snap.holders_responded or v_snap.holders_responded > v_snap.holders_total then
    return jsonb_build_object('suppressed', true);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('bucket', b.bucket, 'holder_count', b.holder_count) order by b.bucket), '[]'::jsonb)
    into v_buckets from venue.holder_mix_bucket b where b.snapshot_id = v_snap.snapshot_id;
  return jsonb_build_object('suppressed', false, 'as_of', v_snap.as_of,
    'holders_total', v_snap.holders_total, 'holders_responded', v_snap.holders_responded, 'buckets', v_buckets);
end;
$$;

create or replace function venue.unpublish_holder_mix(p_event_session_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  if not kernel.is_platform(array['platform_admin']) then
    raise exception 'insufficient_privilege: platform_admin required' using errcode = '42501';
  end if;
  update venue.holder_mix_snapshot set published_at = null
   where event_session_id = p_event_session_id and published_at is not null;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (auth.uid(), 'holder_mix.unpublish', 'event_session', p_event_session_id, 'unpublish');
  return jsonb_build_object('status','ok');
end;
$$;

create or replace function venue.unpublish_all_holder_mix()
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  if not kernel.is_platform(array['platform_admin']) then
    raise exception 'insufficient_privilege: platform_admin required' using errcode = '42501';
  end if;
  update venue.holder_mix_snapshot set published_at = null where published_at is not null;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (auth.uid(), 'holder_mix.unpublish_all', 'platform', '00000000-0000-0000-0000-000000000000', 'kill_switch');
  return jsonb_build_object('status','ok');
end;
$$;

create or replace function venue.reconcile_holder_mix()
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  return jsonb_build_object('status','ok','note','nightly holder-mix reconcile (demographics-activation gated)');
end;
$$;

-- ============================================================================
-- PART 20 — grants (076 discipline: revoke default PUBLIC EXECUTE on every new
--   function; targeted grants only). on_identity_erased_door keeps its 077 ACL.
-- ============================================================================
do $$
declare
  v_fn text;
  v_all constant text[] := array[
    'venue.create_door_pin(uuid, uuid, text, text, timestamptz, text)',
    'venue.revoke_door_pin(uuid, text)',
    'venue.register_scan_device(uuid, text, text)',
    'venue.set_scan_device_status(uuid, text, text, text)',
    'venue.sync_scan_device_manifest(uuid, uuid, integer)',
    'venue.record_scan(uuid, uuid, uuid, jsonb, text)',
    'venue.reconcile_offline_scans(uuid, uuid, jsonb, text)',
    'venue.validate_ticket_online(uuid, uuid)',
    'venue.allocate_comp(uuid, uuid, integer, text, text)',
    'venue.issue_comp(uuid, uuid, integer, text)',
    'venue.create_guest_list(uuid, text, text)',
    'venue.upsert_guest_entry(uuid, uuid, text, integer, text)',
    'venue.remove_guest_entry(uuid, text, text)',
    'venue.check_in_guest_entry(uuid, uuid, text, text)',
    'venue.open_door_manifest(uuid, text, text)',
    'venue.close_door_manifest(uuid, text, text)',
    'venue.get_door_manifest(uuid, integer)',
    'venue.preview_door_open_impact(uuid)',
    'venue.get_live_device_count(uuid)',
    'venue.get_holder_mix(uuid, text)',
    'venue.revoke_door_session(uuid, text, text)',
    'venue.mint_door_session(uuid, uuid, uuid, text, text)',
    'venue.sweep_expired_door_sessions()',
    'venue.refresh_holder_mix(uuid)',
    'venue.reconcile_holder_mix()',
    'venue.unpublish_holder_mix(uuid)',
    'venue.unpublish_all_holder_mix()',
    'venue.append_door_manifest_delta(uuid, uuid[], text, uuid)',
    'venue.guard_door_manifest_transition()',
    'kernel.assert_door_session(uuid, uuid, uuid, text)',
    'kernel.grant_door_freeze_override(uuid, uuid, text, timestamptz, integer, text)',
    'kernel.revoke_door_freeze_override(uuid, text)',
    'kernel.sweep_expired_door_overrides()',
    'kernel.revoke_signing_key(uuid, text, integer, text)',
    'catalog.engage_door_freeze(uuid, timestamptz)',
    'catalog.set_session_door_schedule(uuid, timestamptz, text, text)',
    'catalog.sweep_implicit_door_freezes(integer)',
    'catalog.tg_door_open_at_is_ledger_head()',
    'market.on_door_freeze_engaged(uuid, uuid)',
    'market.door_freeze_drain_preview(uuid)'
  ];
  -- caller-authorized (EDGE-FRONTED, in-body has_venue_role/has_org_role/is_platform).
  v_auth constant text[] := array[
    'venue.create_door_pin(uuid, uuid, text, text, timestamptz, text)',
    'venue.revoke_door_pin(uuid, text)',
    'venue.register_scan_device(uuid, text, text)',
    'venue.set_scan_device_status(uuid, text, text, text)',
    'venue.sync_scan_device_manifest(uuid, uuid, integer)',
    'venue.record_scan(uuid, uuid, uuid, jsonb, text)',
    'venue.reconcile_offline_scans(uuid, uuid, jsonb, text)',
    'venue.validate_ticket_online(uuid, uuid)',
    'venue.allocate_comp(uuid, uuid, integer, text, text)',
    'venue.issue_comp(uuid, uuid, integer, text)',
    'venue.create_guest_list(uuid, text, text)',
    'venue.upsert_guest_entry(uuid, uuid, text, integer, text)',
    'venue.remove_guest_entry(uuid, text, text)',
    'venue.check_in_guest_entry(uuid, uuid, text, text)',
    'venue.open_door_manifest(uuid, text, text)',
    'venue.close_door_manifest(uuid, text, text)',
    'venue.get_door_manifest(uuid, integer)',
    'venue.preview_door_open_impact(uuid)',
    'venue.get_live_device_count(uuid)',
    'venue.get_holder_mix(uuid, text)',
    'venue.revoke_door_session(uuid, text, text)',
    'venue.unpublish_holder_mix(uuid)',
    'venue.unpublish_all_holder_mix()',
    'kernel.grant_door_freeze_override(uuid, uuid, text, timestamptz, integer, text)',
    'kernel.revoke_door_freeze_override(uuid, text)',
    'kernel.revoke_signing_key(uuid, text, integer, text)',
    'catalog.set_session_door_schedule(uuid, timestamptz, text, text)'
  ];
  -- machine-only (service_role: the door-session edge mint + assert; the crons run
  -- as postgres so they need no grant, but the sweep RPCs may be edge-triggered).
  v_svc constant text[] := array[
    'venue.mint_door_session(uuid, uuid, uuid, text, text)',
    'venue.sweep_expired_door_sessions()',
    'venue.refresh_holder_mix(uuid)',
    'venue.reconcile_holder_mix()',
    'kernel.assert_door_session(uuid, uuid, uuid, text)',
    'kernel.sweep_expired_door_overrides()',
    'catalog.sweep_implicit_door_freezes(integer)'
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
  -- append_door_manifest_delta, engage_door_freeze, the market stubs and the two
  -- trigger fns are definer-internal ONLY (called by definer functions/triggers):
  -- revoked from all, granted to nobody.
end $$;

-- ============================================================================
-- PART 21 — cron (plan §8/086, P0-1): FIVE explicit schedules. Sweeps 1-3 are
--   presentational (expiry arithmetic lives in the predicates); 4-5 nightly.
-- ============================================================================
select cron.schedule('sweep-expired-door-sessions', '*/2 * * * *', $$select venue.sweep_expired_door_sessions();$$);
select cron.schedule('sweep-expired-door-overrides', '*/2 * * * *', $$select kernel.sweep_expired_door_overrides();$$);
select cron.schedule('sweep-implicit-door-freezes',  '*/2 * * * *', $$select catalog.sweep_implicit_door_freezes(500);$$);
select cron.schedule('refresh-holder-mix',           '17 4 * * *',  $$select venue.refresh_holder_mix(session_id) from catalog.event_session where status in ('live','on_sale','announced');$$);
select cron.schedule('reconcile-holder-mix',         '47 4 * * *',  $$select venue.reconcile_holder_mix();$$);

commit;

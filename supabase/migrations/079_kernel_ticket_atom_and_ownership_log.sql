-- ============================================================================
-- 079_kernel_ticket_atom_and_ownership_log.sql
-- Phase-2 package 079 (PHASE D — ticket kernel).
--
-- Frozen sources: plan §8/079 + PHASE D body; schema §1.5/§1.5.1/§1.6/§1.6.1/
-- §1.6.2/§7.6; DOOR §8.1 (+§13.5-B move); RPC §7.4/§7.5/§12.4a-c/§12.5/§20.2.4/
-- §20.17.5; RLS §7.5/§7.6/§11/§16.10; SPEC_FOUNDATION D3;
-- CRON_SCHEDULE_REGISTER row 079; registry entry 079 (depends_on 076/077/078).
--
-- The custody core: the ticket atom (SoT), its append-only ownership ledger
-- with the fixed C26 idempotency, the complete input set of the transfer-freeze
-- predicate (kernel.door_freeze_override moved here by §13.5-B / FR-7), the
-- MB-4 verify trigger, the MN-4 expiry sweep, catalog.update_event_session
-- (SEAM-1: its time guard reads kernel.tickets), and the OR-17 rider: the REAL
-- BP-1 body replaces the 077 kernel.deletion_blockers_custody stub.
--
-- NOT here (deferred by name):
--   * kernel_tickets_sel_venue policy            -> 080 (AUTHZ-PKG1)
--   * FKs tickets.ticket_type_id / signing_key_id -> 084 (adopt)
--   * issuance/transfer/void engines             -> 083/085/088
--   * unlock_ticket's R-40 dispute_hold re-arm   -> 088 (PFA-13: its operand
--     kernel.dispute_native is an 088 table; release resolves to 'none' here,
--     which is the true value over the empty world)
-- Production stays OFF: feature.native_issuance_enabled=false (078 seed); no
-- caller of any custody writer exists in this package.
-- ============================================================================

-- ============================================================================
-- PART 1 — kernel.tickets (schema §1.5)
-- ============================================================================

create table if not exists kernel.tickets (
  ticket_atom_id     uuid primary key default gen_random_uuid(),
  event_session_id   uuid not null references catalog.event_session(session_id) on delete restrict,
  org_id             uuid not null references kernel.organization(org_id) on delete restrict,
  -- FK -> venue.ticket_type added by 084 (target is an 081 table); the column
  -- is NOT NULL now because no row can exist before the mint engine (083).
  ticket_type_id     uuid not null,
  serial_no          integer not null,
  current_owner_id   uuid not null references auth.users(id) on delete restrict,
  state              text not null default 'issued'
                     check (state in ('issued','active','scanned','voided','expired')),
  -- refund_hold: MONEY §12 ADDITIVE-2. dispute_hold: R-40 overlay (schema §1.5).
  resale_state       text not null default 'none'
                     check (resale_state in ('none','listed','locked','refund_hold','dispute_hold')),
  credential_version integer not null default 0 check (credential_version >= 0),
  -- FK -> kernel.signing_key added by 084 (target is an 083 table).
  signing_key_id     uuid not null,
  home_region        text not null default 'us-east',
  seat_ref           text,
  -- bare uuid: FK target venue.inventory_unit is EXT (never built in MVP).
  unit_row_id        uuid,
  external_seat_ref  text,
  issued_at          timestamptz not null default now(),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint tickets_session_serial_uq unique (event_session_id, serial_no)
);

-- C17 cross-rail dedup: external_seat_ref unique per session where not null.
create unique index if not exists tickets_session_external_seat_uq
  on kernel.tickets (event_session_id, external_seat_ref)
  where external_seat_ref is not null;

create index if not exists tickets_owner_idx    on kernel.tickets (current_owner_id);
create index if not exists tickets_session_idx  on kernel.tickets (event_session_id);
create index if not exists tickets_type_idx     on kernel.tickets (ticket_type_id);
create index if not exists tickets_resale_partial_idx
  on kernel.tickets (resale_state) where resale_state <> 'none';

-- R-35 / RPC §20.16: the global updated_at maintainer.
drop trigger if exists tg_tickets_set_updated_at on kernel.tickets;
create trigger tg_tickets_set_updated_at
  before update on kernel.tickets
  for each row execute function kernel.set_updated_at();

-- ============================================================================
-- PART 2 — kernel.ticket_ownership_log (schema §1.6, AO; C26 keys)
-- ============================================================================

create table if not exists kernel.ticket_ownership_log (
  ticket_atom_id           uuid not null references kernel.tickets(ticket_atom_id) on delete restrict,
  sequence                 integer not null check (sequence >= 1),
  from_identity            uuid references auth.users(id) on delete restrict,
  to_identity              uuid not null references auth.users(id) on delete restrict,
  cause                    text not null check (cause in
                             ('issue','primary_sale','comp','door_sale','p2p_transfer',
                              'market_sale','auction_sale','admin_action','refund_void',
                              'import','promoter_commission','settlement','chargeback')),
  cause_ref                uuid not null,
  actor_identity           uuid not null references auth.users(id) on delete restrict,
  command_idempotency_key  text not null,
  occurred_at              timestamptz not null default now(),
  credential_version_after integer not null check (credential_version_after >= 0),
  state_transition         jsonb not null,
  created_at               timestamptz not null default now(),
  constraint ticket_ownership_log_pk primary key (ticket_atom_id, sequence),
  -- THE C26 idempotency key (fixed 3-column form; §1.6.1 a/b/c/d).
  constraint ownership_log_cause_uq unique (cause, cause_ref, ticket_atom_id),
  -- C16 command-level replay guard.
  constraint ownership_log_command_uq unique (ticket_atom_id, command_idempotency_key),
  -- "minted from nothing" exactly at the issuance entry.
  constraint ownership_log_from_identity_check
    check (
      (from_identity is null and cause = 'issue' and sequence = 1)
      or (from_identity is not null and not (cause = 'issue' and sequence = 1))
    )
);

create index if not exists ownership_log_cause_ref_idx on kernel.ticket_ownership_log (cause_ref);
create index if not exists ownership_log_to_identity_idx on kernel.ticket_ownership_log (to_identity);

-- AO: INSERT-only. Guard trigger + REVOKE below (I-7).
drop trigger if exists tg_ownership_log_append_only on kernel.ticket_ownership_log;
create trigger tg_ownership_log_append_only
  before update or delete on kernel.ticket_ownership_log
  for each row execute function kernel.raise_append_only();

-- ============================================================================
-- PART 3 — kernel.door_freeze_override (DOOR §8.1; moved here by §13.5-B/FR-7)
-- ============================================================================

create table if not exists kernel.door_freeze_override (
  override_id             uuid primary key default gen_random_uuid(),
  session_id              uuid not null references catalog.event_session(session_id) on delete restrict,
  -- NULL = whole session; non-NULL = single atom (the narrower grant, preferred).
  ticket_atom_id          uuid references kernel.tickets(ticket_atom_id) on delete restrict,
  granted_by              uuid not null references auth.users(id) on delete restrict,
  reason_code             text not null check (reason_code in
                            ('operator_error_reopen','ticket_stranded_at_door',
                             'fraud_investigation','platform_incident_recovery')),
  granted_at              timestamptz not null default now(),
  expires_at              timestamptz not null,
  revoked_at              timestamptz,
  revoked_by              uuid references auth.users(id) on delete restrict,
  command_idempotency_key text not null,
  created_at              timestamptz not null default now(),
  constraint door_freeze_override_grantor_command_uq unique (granted_by, command_idempotency_key),
  constraint door_freeze_override_ttl_check check (expires_at > granted_at)
  -- DOOR §8.1 additionally bounds expires_at by config('door.max_override_interval').
  -- A CHECK cannot read a table (platform impossibility), so that ceiling is
  -- enforced as precondition 2 of kernel.grant_door_freeze_override (086), the
  -- table's sole INSERT writer. Recorded as erratum E-19.
);

-- DOOR §8.1 names WHERE ... AND expires_at > now(); an index predicate cannot
-- call now() (platform impossibility, erratum E-19). The live-row filter stays
-- in the reader; the partial index carries the revocation predicate.
create index if not exists door_freeze_override_live_idx
  on kernel.door_freeze_override (session_id, expires_at)
  where revoked_at is null;

-- AO variant: the ONLY permitted UPDATE is the revoked_at/revoked_by forward
-- transition (NULL -> value, together, once). Everything else, and DELETE, raises.
create or replace function kernel.raise_override_forward_only()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'append_only: door_freeze_override is immutable — DELETE is not permitted';
  end if;
  if old.revoked_at is not null then
    raise exception 'append_only: door_freeze_override % is already revoked — no further transition', old.override_id;
  end if;
  if new.revoked_at is null or new.revoked_by is null then
    raise exception 'append_only: the only permitted UPDATE is the revoked_at/revoked_by forward transition';
  end if;
  if row(new.override_id, new.session_id, new.ticket_atom_id, new.granted_by,
         new.reason_code, new.granted_at, new.expires_at,
         new.command_idempotency_key, new.created_at)
     is distinct from
     row(old.override_id, old.session_id, old.ticket_atom_id, old.granted_by,
         old.reason_code, old.granted_at, old.expires_at,
         old.command_idempotency_key, old.created_at) then
    raise exception 'append_only: door_freeze_override grant columns are immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists tg_door_freeze_override_forward_only on kernel.door_freeze_override;
create trigger tg_door_freeze_override_forward_only
  before update or delete on kernel.door_freeze_override
  for each row execute function kernel.raise_override_forward_only();

-- ============================================================================
-- PART 4 — MB-4: kernel.tg_custody_head_is_ledger_tail (schema §1.6.2)
-- The verify trigger the constitution names three times and no package built.
-- ============================================================================

create or replace function kernel.tg_custody_head_is_ledger_tail()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_head record;
  v_tail record;
begin
  -- The invariant is over the state AT COMMIT (§1.6.2: "asserts, at COMMIT").
  -- A deferred queue holds one event per ROW VERSION, so a transaction that
  -- moves the same atom twice (each move correctly paired) queues an event
  -- whose NEW is an intermediate version. Checking NEW against the final tail
  -- would raise on a correct multi-move transaction; the property named is
  -- head-equals-tail of the COMMITTED state, so read the LIVE head.
  select t.current_owner_id, t.credential_version
    into v_head
    from kernel.tickets t
   where t.ticket_atom_id = new.ticket_atom_id;
  if v_head is null then
    return null;                -- row removed before commit (pre-go-live only)
  end if;
  select l.to_identity, l.credential_version_after
    into v_tail
    from kernel.ticket_ownership_log l
   where l.ticket_atom_id = new.ticket_atom_id
   order by l.sequence desc
   limit 1;
  -- (1) an atom with no custody entry is not a custody fact
  if v_tail is null then
    raise exception 'custody_head_violation: atom % has no ownership-log entry at COMMIT', new.ticket_atom_id;
  end if;
  -- (2) the head must be the tail's holder
  if v_tail.to_identity <> v_head.current_owner_id then
    raise exception 'custody_head_violation: atom % head owner % <> ledger tail %',
      new.ticket_atom_id, v_head.current_owner_id, v_tail.to_identity;
  end if;
  -- (3) the credential head must be the tail's
  if v_tail.credential_version_after <> v_head.credential_version then
    raise exception 'custody_head_violation: atom % credential_version % <> ledger tail %',
      new.ticket_atom_id, v_head.credential_version, v_tail.credential_version_after;
  end if;
  return null;
end;
$$;

-- DEFERRABLE INITIALLY DEFERRED: checks at COMMIT, so the property holds in
-- whatever statement order a future engine edit uses. Fires on INSERT and on
-- UPDATE OF current_owner_id/credential_version, AND ON NOTHING ELSE — a write
-- touching only state/resale_state/signing_key_id/seat_ref/updated_at is not a
-- custody move and appends no log row (§1.6.2's non-vacuity clause; the clause
-- that keeps this from bricking the door).
drop trigger if exists tg_custody_head_is_ledger_tail on kernel.tickets;
create constraint trigger tg_custody_head_is_ledger_tail
  after insert or update of current_owner_id, credential_version
  on kernel.tickets
  deferrable initially deferred
  for each row execute function kernel.tg_custody_head_is_ledger_tail();

-- ============================================================================
-- PART 5 — kernel.is_transfer_frozen (RPC §12.4a; complete corrected body)
-- ============================================================================

-- TOTAL and FAIL-CLOSED: TRUE for an unknown atom id — the "helper tolerates a
-- not-yet-existing atom id" escape hatch is WITHDRAWN (FR-7): a predicate that
-- silently returns false for an unknown atom fails open on the transfer path.
-- Session-wide (§12.4b): every atom of a session is frozen once
-- now() >= catalog.effective_freeze_at(session), subject only to an active,
-- unexpired, unrevoked kernel.door_freeze_override covering the atom.
create or replace function kernel.is_transfer_frozen(p_ticket_atom_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when not exists (select 1 from kernel.tickets t
                      where t.ticket_atom_id = p_ticket_atom_id)
      then true                       -- unknown atom: fail closed
    else (
      select now() >= catalog.effective_freeze_at(t.event_session_id)
             and not exists (
               select 1 from kernel.door_freeze_override o
                where o.session_id = t.event_session_id
                  and (o.ticket_atom_id is null
                       or o.ticket_atom_id = t.ticket_atom_id)
                  and o.revoked_at is null
                  and o.expires_at > now())
        from kernel.tickets t
       where t.ticket_atom_id = p_ticket_atom_id
    )
  end
$$;

-- ============================================================================
-- PART 6 — kernel.lock_ticket / kernel.unlock_ticket (RPC §7.4; SSCAS #6/#7
-- overlays, definer primitives — NOT client-callable)
-- ============================================================================

create or replace function kernel.lock_ticket(
  p_atom_id uuid, p_reason text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid;
  v_state  text;
  v_resale text;
  v_owner  uuid;
begin
  v_uid := auth.uid();
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  -- p_reason selects the overlay target: 'listed' (#6 create_listing),
  -- 'locked' (#7 create_p2p_transfer), 'refund_hold' (§17.1 parked refund).
  if p_reason not in ('listed','locked','refund_hold') then
    raise exception 'invalid_input: bad overlay reason %', p_reason;
  end if;

  select t.state, t.resale_state, t.current_owner_id
    into v_state, v_resale, v_owner
    from kernel.tickets t
   where t.ticket_atom_id = p_atom_id
   for update;                                   -- Ticket Atom lock (rank 5)
  if v_state is null then
    raise exception 'not_found: atom %', p_atom_id using errcode = 'P0002';
  end if;

  -- §7.4: current owner = the acting seller/sender. The caller is always a
  -- definer RPC, so auth.uid() is the end principal.
  if v_uid is null or v_uid <> v_owner then
    raise exception 'insufficient_privilege: caller is not the atom''s current owner'
      using errcode = '42501';
  end if;
  if v_state <> 'active' then
    raise exception 'precondition_failed: atom is %, not active', v_state;
  end if;
  -- Overlay is state-guarded: re-set of the SAME target is a no-op.
  if v_resale = p_reason then
    return jsonb_build_object('status','noop_replay','resale_state',v_resale);
  end if;
  if v_resale <> 'none' then
    -- already listed/locked/held under a DIFFERENT overlay: double-sell guard.
    raise exception 'precondition_failed: conflict_locked (resale_state=%)', v_resale;
  end if;
  -- Freeze ENFORCEMENT point (§12.4c): a choke-point nothing bypasses.
  if kernel.is_transfer_frozen(p_atom_id) then
    raise exception 'precondition_failed: frozen';
  end if;

  update kernel.tickets set resale_state = p_reason, updated_at = now()
   where ticket_atom_id = p_atom_id;
  return jsonb_build_object('status','ok','resale_state',p_reason);
end;
$$;

create or replace function kernel.unlock_ticket(
  p_atom_id uuid, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state  text;
  v_resale text;
begin
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;

  select t.state, t.resale_state
    into v_state, v_resale
    from kernel.tickets t
   where t.ticket_atom_id = p_atom_id
   for update;
  if v_state is null then
    raise exception 'not_found: atom %', p_atom_id using errcode = 'P0002';
  end if;
  if v_resale = 'none' then
    return jsonb_build_object('status','noop_replay','resale_state','none');
  end if;

  -- NO owner precondition and NO freeze recheck: unlock is a RELEASE. Its
  -- callers (cancel_listing, cancel_p2p_transfer, the TTL sweeps, the door
  -- drain, on_deletion_q5_release) carry their own authority, and the drain
  -- runs precisely while the freeze is engaged.
  --
  -- R-40 re-arm (PFA-13): §7.4 resolves the release to 'dispute_hold' while an
  -- open kernel.dispute_native row joins the atom's originating payment. BOTH
  -- operands (dispute_native, payment_native) are 085/088 tables, so at 079
  -- resolving to 'none' is the true value over the empty world; 088 carries
  -- the body-only CREATE OR REPLACE that adds the arm (SEAM-2a discipline).
  update kernel.tickets set resale_state = 'none', updated_at = now()
   where ticket_atom_id = p_atom_id;
  return jsonb_build_object('status','ok','resale_state','none');
end;
$$;

-- ============================================================================
-- PART 7 — kernel.mark_ticket_scanned (RPC §7.5)
-- ============================================================================

-- SPEC CORRECTION (CRITICAL, §7.5): this function MUST NOT consult
-- kernel.is_transfer_frozen. The freeze is a custody-move guard; a scan is not
-- a custody move, and a recheck here rejects every valid ticket from doors-open
-- to end of night. T-RPC-DOOR-01 pins the absence STRUCTURALLY over prosrc.
-- The delist-first rule (resale_state='none') independently covers every case
-- the freeze check was reaching for.
create or replace function kernel.mark_ticket_scanned(
  p_atom_id uuid, p_session_id uuid, p_scan_ctx jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state   text;
  v_resale  text;
  v_session uuid;
begin
  select t.state, t.resale_state, t.event_session_id
    into v_state, v_resale, v_session
    from kernel.tickets t
   where t.ticket_atom_id = p_atom_id
   for update;
  if v_state is null then
    raise exception 'not_found: atom %', p_atom_id using errcode = 'P0002';
  end if;
  if v_session <> p_session_id then
    raise exception 'precondition_failed: wrong_session';
  end if;
  if v_state <> 'active' then
    -- terminal atoms stay terminal; record_scan (086) maps a repeat to
    -- 'duplicate' via the scan partial-unique (first-in-wins).
    raise exception 'precondition_failed: not_active (state=%)', v_state;
  end if;
  if v_resale <> 'none' then
    -- "delist first" — a listed/locked/held atom cannot be scanned.
    raise exception 'precondition_failed: listed_locked (resale_state=%)', v_resale;
  end if;

  -- A scan is a lifecycle transition, not a custody move: no ownership-log row,
  -- no credential bump. state is outside the MB-4 trigger's clause set.
  update kernel.tickets set state = 'scanned', updated_at = now()
   where ticket_atom_id = p_atom_id;
  return jsonb_build_object('status','ok','atom_state','scanned');
end;
$$;

-- ============================================================================
-- PART 8 — kernel.sweep_expired_ticket_atoms (RPC §12.5; MN-4/S-22/C109)
-- ============================================================================

-- PRESENTATIONAL, NOT LOAD-BEARING: is_transfer_frozen already freezes every
-- atom of a session at doors, strictly before the session ends. No path may
-- trust state <> 'expired' because this tick was supposed to have run (§4.3.1).
create or replace function kernel.sweep_expired_ticket_atoms(p_limit int default 100)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_grace interval;
  v_swept integer := 0;
  v_row   record;
begin
  -- config('ticket.expiry_grace'): a CLASS A key under PFA-9's applied ruling
  -- (spelled + consumed, in NO authoritative seed table — completeness
  -- correction E-18): NOT seeded, and the consumer is fail-to-safe. Here the
  -- safe direction is INERT: expiry is a terminal label, and stamping it
  -- without an owner-ruled grace could terminal-ize an atom a refund path
  -- still needs; not stamping it is explicitly harmless ("lateness is
  -- harmless by construction", plan §8/079).
  begin
    v_grace := (select (c.value #>> '{}')::interval
                  from catalog.platform_config c
                 where c.key = 'ticket.expiry_grace'
                 order by c.version desc
                 limit 1);
  exception when others then
    v_grace := null;
  end;
  if v_grace is null then
    return jsonb_build_object('swept_count', 0);
  end if;

  for v_row in
    select t.ticket_atom_id
      from kernel.tickets t
      join catalog.event_session s on s.session_id = t.event_session_id
     where t.state = 'active'
       -- a session with no ends_at has not verifiably ended: fail-inert.
       and s.ends_at is not null
       and now() > s.ends_at + v_grace
     limit p_limit
     for update of t skip locked
  loop
    -- active -> expired ONLY; scanned/voided/expired are terminal (§7.6) and a
    -- sweep that re-writes a terminal state is a second writer of somebody
    -- else's column. NO ownership-log row, NO credential bump: expiry is a
    -- lifecycle fact, not a custody move — the MB-4 trigger does not fire.
    update kernel.tickets
       set state = 'expired', updated_at = now()
     where ticket_atom_id = v_row.ticket_atom_id
       and state = 'active';
    v_swept := v_swept + 1;
  end loop;

  return jsonb_build_object('swept_count', v_swept);
end;
$$;

-- ============================================================================
-- PART 9 — catalog.update_event_session (RPC §20.2.4; SEAM-1: the time guard
-- reads kernel.tickets, so 078 would have been a forward reference)
-- ============================================================================

create or replace function catalog.update_event_session(
  p_session_id uuid, p_patch jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid;
  v_org_id     uuid;
  v_venue_id   uuid;
  v_event_id   uuid;
  v_status     text;
  v_starts     timestamptz;
  v_ends       timestamptz;
  v_doors      timestamptz;
  v_door_open  timestamptz;
  v_before     jsonb;
  v_key        text;
  v_reason     text;
  v_allowed    boolean := false;
  v_marketing  boolean := false;
  v_has_atoms  boolean := false;
  v_grace      interval;
  v_new_starts timestamptz;
  v_new_doors  timestamptz;
  v_new_ends   timestamptz;
  v_time_chg   boolean := false;
  v_changed    boolean := false;
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

  select s.event_id, s.status, s.starts_at, s.ends_at, s.doors_at, s.door_open_at,
         jsonb_build_object('session_label', s.session_label, 'starts_at', s.starts_at,
                            'ends_at', s.ends_at, 'doors_at', s.doors_at)
    into v_event_id, v_status, v_starts, v_ends, v_doors, v_door_open, v_before
    from catalog.event_session s
   where s.session_id = p_session_id
   for update;                                          -- rank 1
  if v_event_id is null then
    raise exception 'not_found: session %', p_session_id using errcode = 'P0002';
  end if;

  select e.org_id, e.venue_id into v_org_id, v_venue_id
    from catalog.event e where e.event_id = v_event_id;

  -- The unwritable set FIRST, for every caller (T-RPC-CAT-02): door_open_at has
  -- a sole writer (catalog.engage_door_freeze, 086, ruling O-5); session_version
  -- is bumped by THIS BODY, never named by a client; event_id re-parents atoms.
  for v_key in select jsonb_object_keys(p_patch) loop
    if v_key not in ('session_label','starts_at','ends_at','doors_at','reason_code') then
      raise exception 'invalid_input: unwritable_key %', v_key;
    end if;
  end loop;

  if v_status in ('completed','cancelled') then
    raise exception 'precondition_failed: session_terminal';
  end if;

  -- Marketing-only patch (RLS §11.1's D3 extension for this verb): the label is
  -- display; the time columns are freeze INPUTS and never marketing.
  v_marketing := not (p_patch ? 'starts_at' or p_patch ? 'ends_at' or p_patch ? 'doors_at');

  if kernel.has_org_role(v_org_id, array['org_owner','org_admin']) then
    v_allowed := true;
  elsif v_marketing
        and kernel.has_org_role(v_org_id, array['org_marketing']) then
    v_allowed := true;
  end if;
  if not v_allowed then             -- PFA-10 deferred arm (has_venue_role, 080)
    v_allowed := kernel.has_venue_role(
      v_venue_id,
      case when v_marketing then array['venue_manager','venue_marketing']
           else array['venue_manager'] end);
  end if;
  if not v_allowed then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  v_new_starts := coalesce((p_patch ->> 'starts_at')::timestamptz, v_starts);
  v_new_doors  := case when p_patch ? 'doors_at'
                       then (p_patch ->> 'doors_at')::timestamptz else v_doors end;
  v_new_ends   := case when p_patch ? 'ends_at'
                       then (p_patch ->> 'ends_at')::timestamptz else v_ends end;
  if v_new_starts is null then
    raise exception 'invalid_input: starts_at cannot be null';
  end if;
  if v_new_ends is not null and v_new_ends <= v_new_starts then
    raise exception 'precondition_failed: ends_at must be after starts_at';
  end if;
  v_time_chg := (v_new_starts is distinct from v_starts)
             or (v_new_doors  is distinct from v_doors)
             or (v_new_ends   is distinct from v_ends);

  -- THE TIME GUARD — a custody property (§20.2.4). starts_at/doors_at are the
  -- inputs to catalog.effective_freeze_at, which decides when transfers stop.
  if (v_new_starts is distinct from v_starts) or (v_new_doors is distinct from v_doors) then
    -- once the boundary is taken, the schedule that produced it is evidence.
    if v_door_open is not null then
      raise exception 'precondition_failed: boundary_engaged';
    end if;
    select exists (select 1 from kernel.tickets t
                    where t.event_session_id = p_session_id)
      into v_has_atoms;
    if v_has_atoms then
      -- config('door.schedule_move_grace_interval') is a PFA-9 CLASS A key:
      -- NOT seeded, and 079 is directed to implement it FAIL-TO-SAFE — absent
      -- means NO later move is permitted (the X-12 shape, ruled in PFA-9).
      begin
        v_grace := (select (c.value #>> '{}')::interval
                      from catalog.platform_config c
                     where c.key = 'door.schedule_move_grace_interval'
                     order by c.version desc
                     limit 1);
      exception when others then
        v_grace := null;
      end;
      if (v_new_starts > v_starts
          and (v_grace is null or v_new_starts - v_starts >= v_grace))
         or (v_doors is not null and v_new_doors is not null and v_new_doors > v_doors
             and (v_grace is null or v_new_doors - v_doors >= v_grace))
         or (v_doors is null and v_new_doors is not null and v_new_doors > v_new_starts
             and (v_grace is null or v_new_doors - v_new_starts >= v_grace)) then
        raise exception 'precondition_failed: move_exceeds_grace';
      end if;
      -- any move with atoms issued is audited with a MANDATORY reason code.
      v_reason := p_patch ->> 'reason_code';
      if v_reason is null or length(trim(v_reason)) = 0 then
        raise exception 'precondition_failed: reason_required';
      end if;
    end if;
  end if;

  if p_patch ? 'session_label' then
    update catalog.event_session
       set session_label = p_patch ->> 'session_label', updated_at = now()
     where session_id = p_session_id;
    v_changed := true;
  end if;
  if v_time_chg then
    update catalog.event_session
       set starts_at = v_new_starts, doors_at = v_new_doors, ends_at = v_new_ends,
           -- Δ-N1 (NOTIF Group E): bumped IN THIS TRANSACTION, under the row's
           -- FOR UPDATE, whenever starts/doors/ends change — never a patch key.
           session_version = session_version + 1,
           updated_at = now()
     where session_id = p_session_id;
    v_changed := true;
  end if;

  if not v_changed then
    return jsonb_build_object('status','noop_replay','session_id',p_session_id,
                              'effective_freeze_at', catalog.effective_freeze_at(p_session_id));
  end if;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'session.update', 'event_session', p_session_id,
          coalesce(nullif(trim(coalesce(p_patch ->> 'reason_code','')),''), 'self_service'),
          v_before,
          (select jsonb_build_object('session_label', s.session_label, 'starts_at', s.starts_at,
                                     'ends_at', s.ends_at, 'doors_at', s.doors_at,
                                     'session_version', s.session_version)
             from catalog.event_session s where s.session_id = p_session_id));

  -- the recomputed boundary is returned, so the operator sees the consequence
  -- of the edit in the same round trip rather than discovering it at the door.
  return jsonb_build_object('status','ok','session_id',p_session_id,
                            'effective_freeze_at', catalog.effective_freeze_at(p_session_id));
end;
$$;

-- ============================================================================
-- PART 10 — OR-17 rider: the REAL BP-1 body (SEAM-2a: body-only replacement;
-- signature, parameter names and return type verbatim from 077)
-- ============================================================================

create or replace function kernel.deletion_blockers_custody(p_identity uuid)
returns text language sql volatile security definer set search_path = ''
as $$
  -- BP-1 LIVE CUSTODY (dsm §2): any kernel.tickets row with
  -- current_owner_id = :id and state in the non-terminal half of the enum.
  -- Drains: scanned · voided to SN-VOID · expired · transferred out. A listed
  -- or locked atom still blocks (the overlay keeps state='active').
  select 'BP-1: live custody — issued/active atom(s) held; clears via scan, void, expiry or transfer-out'
   where exists (select 1 from kernel.tickets t
                  where t.current_owner_id = p_identity
                    and t.state in ('issued','active'))
$$;

-- ============================================================================
-- PART 11 — RLS + GRANTS (RLS §7.5/§7.6/§11/§16.10; I-7: REVOKE ALL first)
-- ============================================================================

alter table kernel.tickets enable row level security;
alter table kernel.ticket_ownership_log enable row level security;
alter table kernel.door_freeze_override enable row level security;

revoke all on kernel.tickets from anon, authenticated;
revoke all on kernel.ticket_ownership_log from anon, authenticated;
revoke all on kernel.door_freeze_override from anon, authenticated;

-- kernel.tickets: owner-scoped + platform read. kernel_tickets_sel_venue is
-- DEFERRED TO 080 (AUTHZ-PKG1): it needs kernel.has_event_role to resolve the
-- atom's session to its venue. Writes are RPC-only (no INSERT/UPDATE/DELETE
-- grant, no write policy).
grant select on kernel.tickets to authenticated;

drop policy if exists kernel_tickets_sel_owner on kernel.tickets;
create policy kernel_tickets_sel_owner
  on kernel.tickets for select to authenticated
  using (current_owner_id = auth.uid());

drop policy if exists kernel_tickets_sel_platform on kernel.tickets;
create policy kernel_tickets_sel_platform
  on kernel.tickets for select to authenticated
  using (kernel.is_platform(array['platform_admin','platform_support','platform_risk']));

-- kernel.ticket_ownership_log: money-custody-RPC-only — DENY-ALL to clients
-- (RLS on, zero policies). Reads arrive later via the redacted
-- market.get_ticket_history RPC (088).
-- kernel.door_freeze_override: audit-only — RLS on, ZERO policies, no grants.

-- Function ACLs. Functions default EXECUTE to PUBLIC: strip, then grant exactly.
do $$
declare
  v_fn text;
  v_all constant text[] := array[
    'kernel.is_transfer_frozen(uuid)',
    'kernel.lock_ticket(uuid, text, text)',
    'kernel.unlock_ticket(uuid, text)',
    'kernel.mark_ticket_scanned(uuid, uuid, jsonb)',
    'kernel.sweep_expired_ticket_atoms(int)',
    'catalog.update_event_session(uuid, jsonb, text)',
    'kernel.tg_custody_head_is_ledger_tail()',
    'kernel.raise_override_forward_only()'
  ];
  -- RLS §11.4: is_transfer_frozen is the RN eligibility boolean — authenticated.
  -- RLS §11.1: update_event_session is caller-authorized — authenticated.
  v_auth constant text[] := array[
    'kernel.is_transfer_frozen(uuid)',
    'catalog.update_event_session(uuid, jsonb, text)'
  ];
  -- §12.5 / S-22 / CRON register: the atom-expiry sweep's EXEC row is DEF,
  -- service_role/pg_cron only. This adds the FIFTEENTH name to the 077 DEF
  -- closure (test 141 F3 re-scoped by this package).
  v_svc constant text[] := array[
    'kernel.sweep_expired_ticket_atoms(int)'
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
  -- lock_ticket / unlock_ticket / mark_ticket_scanned: EXEC DEF — definer→definer
  -- callers only (ownership reaches them; no grant to any client class).
  -- kernel.deletion_blockers_custody: ACL untouched by CREATE OR REPLACE — it
  -- keeps 077's class (service_role EXECUTE, the DEF closure).
end $$;

-- ============================================================================
-- PART 12 — CRON (CRON_SCHEDULE_REGISTER row 079; P0-1: per-job entry BY THE
-- OWNING PACKAGE; cron.schedule is idempotent by jobname)
-- ============================================================================

select cron.schedule(
  'sweep-expired-ticket-atoms',
  '*/2 * * * *',
  $$select kernel.sweep_expired_ticket_atoms();$$
);

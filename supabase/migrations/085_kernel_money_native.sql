-- ============================================================================
-- 085_kernel_money_native — Phase-2 package 085 (family F/I bridge).
-- Frozen sources: phase2-architecture-v2 · registry §085 (row 416, JSON 678) ·
-- plan §8/085 · schema §1.8/§1.9(+.1/.2)/§1.10(+.1)/§1.10a/§1.12.1 · RPC §6.3,
-- §7.3, §11.1-11.4, §17.1-17.9, §17.14, §20.7.1/.6/.7/.10-.12, §20.11.3/.5 ·
-- RLS §7.8-§7.10a + §11 money rows · MONEY spec (authority model) · OR-17/OR-21.
-- Depends: 077, 078, 079, 081, 082, 083 (+ the declared edges 081→085, 083→085,
-- 078→085). Owner rulings executed here: PFA-15 (venue USAGE → service_role),
-- PFA-21 (kernel USAGE → service_role), PFA-22 (OPEN-2: the dedicated
-- deletion.refund_possible_window_hours operand + candidate-scoped NULL).
--
-- WHAT THIS IS: the additive money-native kernel — four ledger tables that LINK
-- to the frozen public.payments (NEVER re-charge; OBS-1: zero changes to
-- public.*), the void engine (SSCAS #3), the refund authority set (tiered
-- dual-control via kernel.approval_request — money approvals ARE representable,
-- unlike 083's credential ones), the payout hold pair (hold_state ONLY, never
-- status — S-15/C105), the Stripe state-sync pair (DEF/service_role only), the
-- OR-21 obligation pair, and venue.finalize_primary_order — SSCAS member #1,
-- authored HERE not 082 (R2B/C111), the only function that turns money into
-- tickets.
--
-- DARKNESS: native issuance + Buy Now stay OFF; the finalize/mint path is
-- doubly dark (flag false AND no activatable signing key under PFA-18A — E-48).
-- Every money threshold key is seeded NULL (078, D-3): under C61/X-12/AUTHZ-M3
-- an unset key authorizes NOTHING — the tier ladder fails closed until the
-- owner sets values at activation.
--
-- ROLLBACK POSTURE: FORWARD-FIX ONLY FROM FIRST ROW — these are money ledgers
-- (strictest in the chain; see the rollback script's refusal guard).
-- ============================================================================

begin;

-- ============================================================================
-- PART 1 — kernel.payment_native (schema §1.8; the R-34 link ledger)
--   Links order↔public.payments (or sale↔payments from 088). Effectively AO —
--   enforced with the standing raise_append_only guard (the schema declares the
--   property; the plan's trigger row under-enumerates — recorded E-50).
-- ============================================================================
create table if not exists kernel.payment_native (
  id                     uuid primary key default gen_random_uuid(),
  payment_id             uuid not null references public.payments(id) on delete restrict,
  order_id               uuid references venue."order"(order_id) on delete restrict,
  -- sale_id: COLUMN ONLY — fk_payment_native_sale → market.market_sale is 089's
  -- adopt step (NOT VALID + VALIDATE; the target is an 088 table).
  sale_id                uuid,
  amount_minor           integer not null check (amount_minor > 0),
  currency               text not null default 'USD',
  linked_at              timestamptz not null default now(),
  -- C112 (column-follows-writer): the promoter self-deal detector's ONLY input.
  -- Untrusted, opaque, never validated, never logged, NULL = no-signal (PROMO
  -- §1.8). Written by finalize_primary_order here; read by 090's resolver.
  -- NEVER client-readable (RLS §7.8 — excluded from every scoped projection).
  instrument_fingerprint text,
  created_at             timestamptz not null default now(),
  constraint payment_native_payment_uq unique (payment_id),
  constraint payment_native_subject_xor_ck check (
    (order_id is not null and sale_id is null) or (order_id is null and sale_id is not null)
  )
);
create index if not exists payment_native_order_idx on kernel.payment_native (order_id);
create index if not exists payment_native_sale_idx  on kernel.payment_native (sale_id);

drop trigger if exists tg_payment_native_append_only on kernel.payment_native;
create trigger tg_payment_native_append_only before update or delete on kernel.payment_native
  for each row execute function kernel.raise_append_only();

alter table kernel.payment_native enable row level security;
revoke all on kernel.payment_native from anon, authenticated;

-- ============================================================================
-- PART 2 — kernel.refund (schema §1.10 + §1.10.1/S-24)
-- ============================================================================
create table if not exists kernel.refund (
  refund_id         uuid primary key default gen_random_uuid(),
  payment_id        uuid not null references public.payments(id) on delete restrict,
  reason_code       text not null check (reason_code in
                      ('buyer_request','event_cancelled','oversell_correction',
                       'dispute','admin_action','auto_compensation')),
  amount_minor      integer not null check (amount_minor > 0),
  currency          text not null default 'USD',
  -- forward-only pending→submitted→succeeded|failed, enforced by mark_refund_state
  -- under FOR UPDATE (state machines live in functions, never triggers — plan §8/085).
  status            text not null default 'pending'
                    check (status in ('pending','submitted','succeeded','failed')),
  -- S-24: write-once; the pairing CHECK below makes the WRONG reading of
  -- 'failed' unstorable — failed = Stripe ACCEPTED then couldn't settle (carries
  -- re_…); a create-call error leaves the row 'pending' with no ref.
  stripe_refund_ref text,
  idempotency_key   text not null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint refund_idempotency_uq unique (idempotency_key),
  constraint refund_ref_pairing_ck check (status = 'pending' or stripe_refund_ref is not null)
);
create unique index if not exists refund_stripe_ref_uq
  on kernel.refund (stripe_refund_ref) where stripe_refund_ref is not null;
create index if not exists refund_payment_idx on kernel.refund (payment_id);

drop trigger if exists tg_refund_set_updated_at on kernel.refund;
create trigger tg_refund_set_updated_at before update on kernel.refund
  for each row execute function kernel.set_updated_at();

alter table kernel.refund enable row level security;
revoke all on kernel.refund from anon, authenticated;

-- ============================================================================
-- PART 3 — kernel.payout (schema §1.9 + §1.9.1 MB-2a + §1.9.2 MB-2b)
--   'held' is NOT a status member (MB-2a) — the hold is the four-column overlay.
-- ============================================================================
create table if not exists kernel.payout (
  payout_id          uuid primary key default gen_random_uuid(),
  payee_kind         text not null check (payee_kind in ('organization','identity')),
  payee_org_id       uuid references kernel.organization(org_id) on delete restrict,
  payee_identity_id  uuid references auth.users(id) on delete restrict,
  -- cause: the payout-relevant D3 labels — the §1.9 named set; every contracted
  -- writer (close_settlement/native-sale/pay_promoter_commission/request_org_payout)
  -- writes one of these four. Widening is additive if a later package needs it
  -- (recorded E-51).
  cause              text not null check (cause in
                       ('settlement','market_sale','promoter_commission','refund_void')),
  cause_ref          uuid not null,   -- deliberately NO FK (cross-schema pointer, no cycle)
  amount_minor       integer not null check (amount_minor > 0),
  currency           text not null default 'USD',
  status             text not null default 'pending'
                     check (status in ('pending','submitted','paid','failed','reversed')),
  -- MB-2: the hold overlay — hold_state NEVER touches status (S-15/C105).
  hold_state         text not null default 'none'
                     check (hold_state in ('none','held','probation_hold')),
  hold_reason_code   text,
  held_by            uuid references auth.users(id) on delete restrict,
  held_at            timestamptz,
  stripe_transfer_ref text,           -- written ONLY by mark_payout_transfer_state, write-once
  source_transaction_ref text,
  idempotency_key    text not null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint payout_idempotency_uq unique (idempotency_key),
  constraint payout_payee_xor_ck check (
    (payee_kind = 'organization' and payee_org_id is not null and payee_identity_id is null)
    or (payee_kind = 'identity' and payee_identity_id is not null and payee_org_id is null)
  ),
  constraint payout_hold_pairing_ck check (
    (hold_state = 'none') = (hold_reason_code is null and held_at is null)
  ),
  constraint payout_held_by_ck check (held_by is null or hold_state = 'held')
);
create index if not exists payout_org_status_idx      on kernel.payout (payee_org_id, status);
create index if not exists payout_identity_status_idx on kernel.payout (payee_identity_id, status);
create index if not exists payout_cause_ref_idx       on kernel.payout (cause_ref);
-- the Control-5 risk queue (T-SCHEMA-PAYOUT-04)
create index if not exists payout_hold_queue_idx
  on kernel.payout (hold_state, created_at) where hold_state <> 'none';

drop trigger if exists tg_payout_set_updated_at on kernel.payout;
create trigger tg_payout_set_updated_at before update on kernel.payout
  for each row execute function kernel.set_updated_at();

alter table kernel.payout enable row level security;
revoke all on kernel.payout from anon, authenticated;

-- ============================================================================
-- PART 4 — kernel.identity_obligation (schema §1.10a; F-P2-1/OR-21)
-- ============================================================================
create table if not exists kernel.identity_obligation (
  obligation_id          uuid primary key default gen_random_uuid(),
  debtor_identity_id     uuid not null references auth.users(id) on delete restrict,
  origin_kind            text not null check (origin_kind in ('chargeback','refund_clawback')),
  origin_ref             uuid not null,   -- soft ref (cause_ref discipline)
  stripe_dispute_ref     text,
  amount_minor           integer not null check (amount_minor > 0),
  currency               text not null default 'USD',
  status                 text not null default 'outstanding'
                         check (status in ('outstanding','recovered','written_off')),
  resolution_reason_code text,
  resolved_by            uuid references auth.users(id) on delete restrict,
  resolved_at            timestamptz,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  constraint identity_obligation_origin_uq unique (origin_kind, origin_ref),
  constraint identity_obligation_resolution_ck check (
    (status = 'outstanding') = (resolution_reason_code is null and resolved_at is null)
  )
);
create unique index if not exists identity_obligation_dispute_uq
  on kernel.identity_obligation (stripe_dispute_ref) where stripe_dispute_ref is not null;
-- "this index IS the BP-10 operand read" (schema §1.10a)
create index if not exists identity_obligation_outstanding_idx
  on kernel.identity_obligation (debtor_identity_id) where status = 'outstanding';

drop trigger if exists tg_identity_obligation_set_updated_at on kernel.identity_obligation;
create trigger tg_identity_obligation_set_updated_at before update on kernel.identity_obligation
  for each row execute function kernel.set_updated_at();

alter table kernel.identity_obligation enable row level security;
revoke all on kernel.identity_obligation from anon, authenticated;
-- GP-2: no DELETE ever, from anyone reachable by grant.
revoke delete on kernel.identity_obligation from service_role;

-- ============================================================================
-- PART 5 — the three SEAM-2 stubs 085 creates (SEAM-2a: parameter names/types/
--   return frozen HERE; bodies land in 090 / 088 / 087 as CREATE OR REPLACE).
-- ============================================================================
-- §17.14: NEVER raises — "a raise here would roll back the money and the
-- tickets". Body 090. The neutral result is the callee's own contract.
create or replace function venue.resolve_order_attribution(p_order_id uuid)
returns void language sql volatile security definer set search_path = ''
as $$ select $$;   -- no-op; writes NO venue.attribution row (T-SCHEMA-ISSUE-03)

-- §20.11.3 (C117/S2-B): THREE parameters, p_-prefixed — canonical; the
-- two-param summaries in plan §0.4b / schema §13.2 are ruled stale. Body 088
-- (compensate arm under the sale lock, rank 4 — called BEFORE the atom lock).
create or replace function market.on_atom_voided(p_atom_id uuid, p_refund_id uuid, p_cause text)
returns void language sql volatile security definer set search_path = ''
as $$ select $$;   -- no-op until 088

-- §20.11.5 (the fifth seam): body 087 (settlement closed→paid negative
-- predicate). Takes the payout, not the settlement (attacker-shaped otherwise).
create or replace function venue.on_payout_settled(p_payout_id uuid)
returns void language sql volatile security definer set search_path = ''
as $$ select $$;   -- no-op until 087

-- ============================================================================
-- PART 6 — the three 077 stub bodies REPLACED (SEAM-2; signatures byte-frozen)
-- ============================================================================
-- BP-5 / BP-6 / BP-12 (OR-17). PFA-22 executes OPEN-2's owner ruling verbatim:
-- the window operand is the DEDICATED key deletion.refund_possible_window_hours;
-- NULL is fail-closed ONLY when a qualifying candidate order exists.
create or replace function kernel.deletion_blockers_money(p_identity uuid)
returns text language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_window numeric;
begin
  -- BP-5: an IN-FLIGHT identity payout (pending/submitted). Terminal failed/
  -- reversed do NOT block forever (R1 P3 — no transition exits them).
  if exists (select 1 from kernel.payout p
              where p.payee_identity_id = p_identity and p.status in ('pending','submitted')) then
    return 'BP-5: identity payout in flight';
  end if;
  -- BP-6: a payout under hold/probation for this identity.
  if exists (select 1 from kernel.payout p
              where p.payee_identity_id = p_identity and p.hold_state <> 'none') then
    return 'BP-6: identity payout under hold';
  end if;
  -- BP-12 arm 1: an in-flight refund on the identity's orders (non-terminal
  -- refund row, or a pending refund approval request on one of their orders).
  if exists (
       select 1
         from kernel.refund r
         join kernel.payment_native pn on pn.payment_id = r.payment_id
         join venue."order" o on o.order_id = pn.order_id
        where o.buyer_id = p_identity and r.status in ('pending','submitted'))
     or exists (
       select 1
         from kernel.approval_request ar
         join venue."order" o on o.order_id = ar.subject_id
        where ar.action = 'refund.issue' and ar.subject_kind = 'order'
          and ar.state = 'pending' and o.buyer_id = p_identity) then
    return 'BP-12: refund in flight';
  end if;
  -- BP-12 arm 2 (PFA-22): the refund-possible window over candidate orders.
  -- Candidates = the identity's paid/partially_refunded orders. With NO
  -- candidate, NULL must NOT block (owner ruling). With candidates present:
  -- NULL window ⇒ BLOCK (fail-closed); set window ⇒ block only inside it
  -- (measured from created_at — the only stable timestamp on the immutable 082
  -- table; the in-flight arm above covers active requests independently).
  if exists (select 1 from venue."order" o
              where o.buyer_id = p_identity
                and o.status in ('paid','partially_refunded')) then
    select (c.value #>> '{}')::numeric into v_window
      from catalog.platform_config c
     where c.key = 'deletion.refund_possible_window_hours'
     order by c.version desc limit 1;
    if v_window is null then
      return 'BP-12: refund-possible window unset (deletion.refund_possible_window_hours) with candidate orders present';
    end if;
    if exists (select 1 from venue."order" o
                where o.buyer_id = p_identity
                  and o.status in ('paid','partially_refunded')
                  and o.created_at > now() - make_interval(hours => v_window::int)) then
      return 'BP-12: order inside the refund-possible window';
    end if;
  end if;
  return null;
end;
$$;

-- BP-10 (OR-21): EXISTS over the §1.10a partial index. The 077 stub returned
-- false — true-not-inert (no origin object existed before 085).
create or replace function kernel.has_outstanding_obligations(p_identity_id uuid)
returns boolean language sql stable security definer set search_path = ''   -- §20.7.12: STABLE
as $$
  select exists (select 1 from kernel.identity_obligation o
                  where o.debtor_identity_id = p_identity_id
                    and o.status = 'outstanding');
$$;

-- Q5 release (OR-17 / DSM §3.1 frozen, RATREC): "every kernel.approval_request
-- row with requested_by = :id and state='pending'" — the deleter NAMES the
-- requests it AUTHORED (requested_by), across ALL actions, not requests on
-- orders it bought (P0-5). Expire each, release the refund_hold overlays pinned
-- on that request's payload atoms, audit, emit the notice (best-effort).
create or replace function kernel.on_deletion_q5_release(p_identity uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_req record;
begin
  for v_req in
    select ar.request_id, ar.action, ar.payload
      from kernel.approval_request ar
     where ar.requested_by = p_identity and ar.state = 'pending'
     for update of ar
  loop
    update kernel.approval_request set state = 'expired', updated_at = now()
     where request_id = v_req.request_id;
    -- release the refund_hold overlays this request pinned (refund.issue only)
    if v_req.action = 'refund.issue' and v_req.payload ? 'atom_ids' then
      update kernel.tickets set resale_state = 'none', updated_at = now()
       where ticket_atom_id in (select (jsonb_array_elements_text(v_req.payload->'atom_ids'))::uuid)
         and resale_state = 'refund_hold';
    end if;
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
    values ('00000000-0000-0000-0000-0000000000f1', v_req.action || '.request_expired', 'approval_request',
            v_req.request_id, 'deletion_q5_release');
    perform notify.emit_event('refund_request_expired', 'approval_request', v_req.request_id,
            'q5:' || v_req.request_id::text,
            jsonb_build_object('action', v_req.action, 'cause', 'deletion_q5'));
  end loop;
end;
$$;

-- ============================================================================
-- PART 7 — kernel.void_ticket_atom (RPC §7.3; SSCAS #3 void leg; FR-4: born
--   HERE with kernel.refund, whose signature it takes). DEF — definer-only
--   (refund flows / sweeps); no client EXECUTE ever.
-- ============================================================================
create or replace function kernel.void_ticket_atom(
  p_atom_id uuid, p_refund_id uuid, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row    kernel.tickets%rowtype;
  v_seq    integer;
  v_cv     integer;
  v_batch  uuid;
  v_actor  uuid;
begin
  v_actor := coalesce(auth.uid(), '00000000-0000-0000-0000-0000000000f1');  -- SN-SYSTEM
  -- §20.11.3 ordering (T-RPC-SEAM-03): the market hook fires BEFORE the atom
  -- lock (rank 4 → 5). A no-op stub until 088.
  perform market.on_atom_voided(p_atom_id, p_refund_id, 'refund_void');

  select * into v_row from kernel.tickets where ticket_atom_id = p_atom_id for update;
  if not found then
    raise exception 'not_found: atom %', p_atom_id using errcode = 'P0002';
  end if;
  if v_row.state = 'voided' then
    -- replay of THIS void → noop, matched by EITHER the refund cause_ref OR the
    -- command key (force_void mints a fresh cause_ref per call, so the command
    -- key is its only stable replay anchor — E-56); a genuinely different void of
    -- an already-voided atom is a conflict.
    if exists (select 1 from kernel.ticket_ownership_log l
                where l.ticket_atom_id = p_atom_id
                  and (   (l.cause = 'refund_void' and l.cause_ref = p_refund_id)
                       or l.command_idempotency_key = p_command_key || ':' || p_atom_id::text)) then
      return jsonb_build_object('status','noop_replay','atom_id', p_atom_id);
    end if;
    raise exception 'state_conflict: atom % already voided under a different cause', p_atom_id;
  end if;
  if v_row.state = 'scanned' then
    -- the consumed partition: a scanned atom is never voided (the money leg is
    -- the caller's concern; §11.4 result names the split).
    raise exception 'precondition_failed: consumed atom cannot be voided';
  end if;
  if v_row.state = 'expired' then
    raise exception 'precondition_failed: expired atom cannot be voided';
  end if;

  select coalesce(max(l.sequence), 0) + 1 into v_seq
    from kernel.ticket_ownership_log l where l.ticket_atom_id = p_atom_id;
  v_cv := v_row.credential_version + 1;

  -- ledger first (the idempotency anchors live here: ownership_log_cause_uq +
  -- ownership_log_command_uq — a concurrent replay lands in the handler below).
  insert into kernel.ticket_ownership_log (ticket_atom_id, sequence, from_identity, to_identity,
                                           cause, cause_ref, actor_identity, command_idempotency_key,
                                           credential_version_after, state_transition)
  values (p_atom_id, v_seq, v_row.current_owner_id,
          '00000000-0000-0000-0000-0000000000f0',                 -- SN-VOID (S-18/C107)
          'refund_void', p_refund_id, v_actor, p_command_key || ':' || p_atom_id::text,
          v_cv, jsonb_build_object('from', v_row.state, 'to', 'voided'));

  -- head: terminal void + SN-VOID owner + credential bump (omitting the owner
  -- write aborts at 079's deferred custody trigger). resale_state is NEVER
  -- cleared here (stated non-goal, §20.7.12 note).
  update kernel.tickets
     set state = 'voided',
         current_owner_id = '00000000-0000-0000-0000-0000000000f0',
         credential_version = v_cv,
         updated_at = now()
   where ticket_atom_id = p_atom_id;

  -- inventory return: the mint batch is derived from the atom's own issuance
  -- fact (seq-1 cause_ref → the 'issue' movement row names the batch).
  select m.batch_id into v_batch
    from kernel.ticket_ownership_log l1
    join venue.inventory_movement m
      on m.cause_ref = l1.cause_ref and m.movement_kind = 'issue'
   where l1.ticket_atom_id = p_atom_id and l1.sequence = 1
   limit 1;
  if v_batch is not null then
    perform 1 from venue.inventory_batch b where b.batch_id = v_batch for update;
    update venue.inventory_batch set sold = sold - 1, updated_at = now()
     where batch_id = v_batch;
    insert into venue.inventory_movement (batch_id, movement_kind, delta_held, delta_sold,
                                          cause, cause_ref, actor_identity)
    values (v_batch, 'void_return', 0, -1, 'refund_void', p_atom_id, v_actor);
  end if;

  -- §12.4c: every voiding path writes a 'revoke' delta — a silent no-op until
  -- 086's body lands / when no episode is open (T-RPC-MONEY-15).
  perform venue.append_door_manifest_delta(v_row.event_session_id, array[p_atom_id], 'revoke', p_refund_id);

  return jsonb_build_object('status','ok','atom_id', p_atom_id, 'credential_version', v_cv);
exception when unique_violation then
  -- concurrent/committed replay: the ledger anchor (cause or command key) already
  -- holds this void. Partial work rolls back to the block savepoint.
  if exists (select 1 from kernel.ticket_ownership_log l
              where l.ticket_atom_id = p_atom_id
                and (   (l.cause = 'refund_void' and l.cause_ref = p_refund_id)
                     or l.command_idempotency_key = p_command_key || ':' || p_atom_id::text)) then
    return jsonb_build_object('status','noop_replay','atom_id', p_atom_id);
  end if;
  raise;
end;
$$;

-- ============================================================================
-- PART 8 — the refund executors (RPC §11.4, §20.7.1, §11.1)
-- ============================================================================
-- §11.4 (PFA-23) — the sole ORDER-scoped kernel.refund writer. EXEC DEF
-- (service_role/edge-fronted, NEVER authenticated). Two authority arms:
--   DIRECT   (command_key not 'req:%'): is_platform([support (cap ALWAYS
--            evaluated on the cumulative operand under the payment lock),
--            admin]). A full refund voids all voidable atoms; a partial platform
--            refund is money-only (atom-specific voids go through admin_refund).
--   DELEGATED (command_key = 'req:'||request_id): reachable only definer->definer
--            (approve/request, dual-control already enforced) or the refund edge.
--            Bound to THAT approved request (amount + payload atoms); single-use
--            because refund.idempotency_key = command_key is UNIQUE. No bare
--            exists(approved) gate; the refund row IS the consumption record.
create or replace function kernel.refund_primary_order(
  p_order_id uuid, p_amount_minor integer, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order      venue."order"%rowtype;
  v_pn         kernel.payment_native%rowtype;
  v_total      integer;
  v_prior      integer;
  v_refund_id  uuid;
  v_atom       record;
  v_voided     integer := 0;
  v_consumed   uuid[] := '{}';
  v_is_admin   boolean;
  v_is_support boolean;
  v_delegated  boolean := false;
  v_deleg_req  uuid;
  v_ar         kernel.approval_request%rowtype;
  v_targets    uuid[];          -- delegated: the request's payload atoms; direct: NULL (=whole order)
  v_full       boolean;
  v_cap        numeric;
  v_existing   kernel.refund%rowtype;
begin
  -- idempotency pre-check (webhook/operator replay; the delegated key is single-use here)
  select * into v_existing from kernel.refund where idempotency_key = p_command_key;
  if found then
    return jsonb_build_object('status','idempotency_replay','refund_id', v_existing.refund_id);
  end if;
  if p_reason_code not in ('buyer_request','event_cancelled','oversell_correction',
                           'dispute','admin_action','auto_compensation') then
    raise exception 'precondition_failed: bad_reason_code %', p_reason_code;
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'precondition_failed: bad_amount';
  end if;

  -- AUTHORITY (PFA-23)
  if p_command_key like 'req:%' then
    -- DELEGATED: bind to the specific approved request named by the key.
    begin
      v_deleg_req := substring(p_command_key from 5)::uuid;
    exception when others then
      raise exception 'insufficient_privilege: malformed delegated key' using errcode = '42501';
    end;
    select * into v_ar from kernel.approval_request
     where request_id = v_deleg_req and action = 'refund.issue' and subject_kind = 'order'
       and subject_id = p_order_id and state = 'approved' and amount_minor = p_amount_minor;
    if not found then
      raise exception 'insufficient_privilege: no matching approved request for this delegated refund'
        using errcode = '42501';
    end if;
    v_delegated := true;
    v_targets := array(select (jsonb_array_elements_text(v_ar.payload->'atom_ids'))::uuid);
  else
    v_is_admin   := kernel.is_platform(array['platform_admin']);
    v_is_support := (not v_is_admin) and kernel.is_platform(array['platform_support']);
    if not (v_is_admin or v_is_support) then
      raise exception 'insufficient_privilege: refund_primary_order is platform (direct) or dual-control-delegated only'
        using errcode = '42501';
    end if;
  end if;

  select * into v_order from venue."order" where order_id = p_order_id for update;
  if not found then
    raise exception 'not_found: order %', p_order_id using errcode = 'P0002';
  end if;
  if v_order.status not in ('paid','partially_refunded') then
    raise exception 'precondition_failed: order % is % — only a paid order refunds', p_order_id, v_order.status;
  end if;

  select * into v_pn from kernel.payment_native where order_id = p_order_id;
  if not found then
    raise exception 'precondition_failed: order % carries no native payment link', p_order_id;
  end if;

  -- payment lock (rank 6): the Σ-guard AND the support cap both serialize here.
  perform 1 from public.payments p where p.id = v_pn.payment_id for update;
  select coalesce(sum(r.amount_minor), 0) into v_prior
    from kernel.refund r where r.payment_id = v_pn.payment_id and r.status <> 'failed';
  select p.total into v_total from public.payments p where p.id = v_pn.payment_id;

  -- support cap ALWAYS evaluated for a direct support caller (R7 Floor-1a):
  -- cumulative = prior refunds + parked pending requests + this; unset key = ZERO.
  if v_is_support then
    select (c.value #>> '{}')::numeric into v_cap
      from catalog.platform_config c
     where c.key = 'refund.platform_support_max_minor' order by c.version desc limit 1;
    if v_cap is null
       or (v_prior
           + coalesce((select sum(ar.amount_minor) from kernel.approval_request ar
                        where ar.action='refund.issue' and ar.subject_kind='order'
                          and ar.subject_id=p_order_id and ar.state='pending'),0)
           + p_amount_minor) > v_cap then
      raise exception 'insufficient_privilege: platform_support cap exceeded (cumulative vs %)',
        coalesce(v_cap::text,'UNSET') using errcode = '42501';
    end if;
  end if;

  if v_prior + p_amount_minor > v_total then
    raise exception 'precondition_failed: over_refund (% + % > %)', v_prior, p_amount_minor, v_total;
  end if;

  -- VOID SCOPE. Delegated: exactly the request's payload atoms. Direct-full
  -- (amount covers the order total): all voidable atoms. Direct-partial: money
  -- only (voids nothing — atom-specific platform voids use admin_refund).
  v_full := (p_amount_minor >= v_order.total_minor);
  v_refund_id := gen_random_uuid();

  if v_delegated or v_full then
    for v_atom in
      select t.ticket_atom_id, t.state, t.current_owner_id, t.resale_state
        from kernel.tickets t
        join kernel.ticket_ownership_log l1
          on l1.ticket_atom_id = t.ticket_atom_id and l1.sequence = 1
       where l1.cause_ref in (select oi.id from venue.order_item oi where oi.order_id = p_order_id)
         and (v_targets is null or t.ticket_atom_id = any(v_targets))
       order by t.ticket_atom_id
       for update of t
    loop
      if v_atom.state = 'scanned' then
        v_consumed := v_consumed || v_atom.ticket_atom_id;   -- money completes; never voided
      elsif v_atom.state in ('voided','expired') then
        null;                                                -- terminal already (skip; R1 P2)
      else
        if v_atom.current_owner_id <> v_order.buyer_id then
          raise exception 'custody_moved: atom % left the buyer — use admin_refund', v_atom.ticket_atom_id;
        end if;
        if v_atom.resale_state not in ('none','refund_hold') then
          raise exception 'conflict_locked: atom % is % — delist before refunding', v_atom.ticket_atom_id, v_atom.resale_state;
        end if;
        if kernel.is_transfer_frozen(v_atom.ticket_atom_id) then
          raise exception 'frozen: atom % is transfer-frozen — routine refund parked until the episode closes', v_atom.ticket_atom_id;
        end if;
        perform kernel.void_ticket_atom(v_atom.ticket_atom_id, v_refund_id, p_command_key);
        v_voided := v_voided + 1;
      end if;
    end loop;
  end if;

  insert into kernel.refund (refund_id, payment_id, reason_code, amount_minor, idempotency_key)
  values (v_refund_id, v_pn.payment_id, p_reason_code, p_amount_minor, p_command_key);

  update venue."order"
     set status = case when v_prior + p_amount_minor >= v_order.total_minor
                       then 'refunded' else 'partially_refunded' end,
         updated_at = now()
   where order_id = p_order_id;

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (coalesce(auth.uid(),'00000000-0000-0000-0000-0000000000f1'), 'refund.issue', 'order', p_order_id,
          p_reason_code,
          jsonb_build_object('order_status', v_order.status),
          jsonb_build_object('refund_id', v_refund_id, 'amount_minor', p_amount_minor,
                            'delegated', v_delegated, 'voided', v_voided, 'consumed', to_jsonb(v_consumed)));

  return jsonb_build_object('status','ok','refund_id', v_refund_id,
                            'voided', v_voided, 'consumed', to_jsonb(v_consumed));
exception when unique_violation then
  select * into v_existing from kernel.refund where idempotency_key = p_command_key;
  if found then
    return jsonb_build_object('status','idempotency_replay','refund_id', v_existing.refund_id);
  end if;
  raise;
end;
$$;

-- §20.7.1 — payment-scoped break-glass (dispute/fee-only reversal; the
-- sanctioned custody_moved destination). platform_risk/platform_admin ONLY;
-- freeze-EXEMPT (§12.4c — the revoke delta is written by the void engine).
create or replace function kernel.admin_refund(
  p_payment_id uuid, p_atom_ids uuid[], p_amount_minor integer, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_total     integer;
  v_status    text;
  v_prior     integer;
  v_refund_id uuid;
  v_atom      record;
  v_voided    integer := 0;
  v_consumed  uuid[] := '{}';
  v_existing  kernel.refund%rowtype;
begin
  if not kernel.is_platform(array['platform_risk','platform_admin']) then
    raise exception 'insufficient_privilege: platform_risk or platform_admin required' using errcode = '42501';
  end if;
  if p_reason_code not in ('dispute','admin_action') then
    raise exception 'precondition_failed: bad_reason_code % (admin_refund takes dispute|admin_action)', p_reason_code;
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'precondition_failed: bad_amount';
  end if;
  select * into v_existing from kernel.refund where idempotency_key = p_command_key;
  if found then
    return jsonb_build_object('status','idempotency_replay','refund_id', v_existing.refund_id);
  end if;

  select p.total, p.status into v_total, v_status from public.payments p where p.id = p_payment_id;
  if not found then
    raise exception 'not_found: payment %', p_payment_id using errcode = 'P0002';
  end if;
  if v_status not in ('succeeded','refunded') then
    raise exception 'payment_unverified: payment % is %', p_payment_id, v_status;
  end if;

  v_refund_id := gen_random_uuid();

  for v_atom in
    select t.ticket_atom_id, t.state from kernel.tickets t
     where t.ticket_atom_id = any(coalesce(p_atom_ids, '{}'))
       -- LINKAGE (E-57): the atoms must belong to an order paid by THIS payment —
       -- money leg and ticket leg cannot be decoupled even for break-glass.
       and exists (
         select 1 from kernel.ticket_ownership_log l1
         join venue.order_item oi on oi.id = l1.cause_ref
         join kernel.payment_native pn on pn.order_id = oi.order_id
        where l1.ticket_atom_id = t.ticket_atom_id and l1.sequence = 1
          and pn.payment_id = p_payment_id)
     order by t.ticket_atom_id
     for update of t
  loop
    if v_atom.state = 'scanned' then
      v_consumed := v_consumed || v_atom.ticket_atom_id;   -- money-only leg
    elsif v_atom.state in ('voided','expired') then
      null;
    else
      -- freeze-exempt: no is_transfer_frozen recheck; the void engine writes
      -- the mandatory 'revoke' delta (T-RPC-MONEY-15).
      perform kernel.void_ticket_atom(v_atom.ticket_atom_id, v_refund_id, p_command_key);
      v_voided := v_voided + 1;
    end if;
  end loop;
  if coalesce(array_length(p_atom_ids,1),0) > 0 and v_voided = 0 and array_length(v_consumed,1) is null then
    raise exception 'precondition_failed: none of the atoms belong to payment % (linkage, E-57)', p_payment_id;
  end if;

  perform 1 from public.payments p where p.id = p_payment_id for update;
  select coalesce(sum(r.amount_minor), 0) into v_prior
    from kernel.refund r where r.payment_id = p_payment_id and r.status <> 'failed';
  if v_prior + p_amount_minor > v_total then
    raise exception 'precondition_failed: over_refund (% + % > %)', v_prior, p_amount_minor, v_total;
  end if;

  insert into kernel.refund (refund_id, payment_id, reason_code, amount_minor, idempotency_key)
  values (v_refund_id, p_payment_id, p_reason_code, p_amount_minor, p_command_key);

  -- reflect the money on the linked order's status when one resolves (R1 P2).
  update venue."order" o
     set status = case when v_prior + p_amount_minor >= o.total_minor then 'refunded' else 'partially_refunded' end,
         updated_at = now()
    from kernel.payment_native pn
   where pn.payment_id = p_payment_id and o.order_id = pn.order_id
     and o.status in ('paid','partially_refunded');

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (auth.uid(), 'refund.admin', 'payment', p_payment_id, p_reason_code,
          jsonb_build_object('payment_status', v_status, 'prior_refunded', v_prior),
          jsonb_build_object('refund_id', v_refund_id, 'amount_minor', p_amount_minor,
                            'voided', v_voided, 'consumed', to_jsonb(v_consumed)));

  return jsonb_build_object('status','ok','refund_id', v_refund_id,
                            'voided', v_voided, 'consumed', to_jsonb(v_consumed));
exception when unique_violation then
  select * into v_existing from kernel.refund where idempotency_key = p_command_key;
  if found then
    return jsonb_build_object('status','idempotency_replay','refund_id', v_existing.refund_id);
  end if;
  raise;
end;
$$;

-- §11.1 — break-glass single-atom void, no money leg at 085 (the optional
-- kernel.refund pairing rides the refund executors). The void's cause_ref is a
-- DETERMINISTIC synthetic derived from the command key (E-56) so a replayed
-- command returns noop_replay via the void engine's command-key arm, not a
-- state_conflict.
create or replace function kernel.force_void_ticket(
  p_atom_id uuid, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_res jsonb;
begin
  if not kernel.is_platform(array['platform_admin','platform_risk']) then
    raise exception 'insufficient_privilege: platform_admin or platform_risk required' using errcode = '42501';
  end if;
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: bad_reason_code (mandatory)';
  end if;
  v_res := kernel.void_ticket_atom(p_atom_id, md5('force:' || p_command_key)::uuid, p_command_key);
  -- audit only a real void — a noop_replay wrote nothing, so it records nothing.
  if v_res->>'status' = 'ok' then
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
    values (auth.uid(), 'ticket.force_void', 'ticket_atom', p_atom_id, p_reason_code, v_res);
  end if;
  return v_res;
end;
$$;

-- ============================================================================
-- PART 9 — the payout hold pair (RPC §11.2/§11.3; MB-2: hold_state ONLY,
--   status NEVER written — S-15/C105).
-- ============================================================================
create or replace function kernel.hold_payout(
  p_payout_id uuid, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row kernel.payout%rowtype;
begin
  if not kernel.is_platform(array['platform_risk','platform_admin']) then
    raise exception 'insufficient_privilege: platform_risk or platform_admin required' using errcode = '42501';
  end if;
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: bad_reason_code (mandatory)';
  end if;
  select * into v_row from kernel.payout where payout_id = p_payout_id for update;
  if not found then
    raise exception 'not_found: payout %', p_payout_id using errcode = 'P0002';
  end if;
  if v_row.status not in ('pending','submitted') then
    raise exception 'precondition_failed: payout % is % — only an unexecuted payout holds', p_payout_id, v_row.status;
  end if;
  if v_row.hold_state = 'held' then
    return jsonb_build_object('status','noop_replay','payout_id', p_payout_id);
  end if;
  update kernel.payout
     set hold_state = 'held', hold_reason_code = p_reason_code,
         held_by = auth.uid(), held_at = now(), updated_at = now()
   where payout_id = p_payout_id;                 -- status NOT written (S-15/C105)
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (auth.uid(), 'payout.hold', 'payout', p_payout_id, p_reason_code,
          jsonb_build_object('hold_state', v_row.hold_state),
          jsonb_build_object('hold_state', 'held'));
  return jsonb_build_object('status','ok','payout_id', p_payout_id);
end;
$$;

create or replace function kernel.release_payout(
  p_payout_id uuid, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row kernel.payout%rowtype;
begin
  if not kernel.is_platform(array['platform_risk','platform_admin']) then
    raise exception 'insufficient_privilege: platform_risk or platform_admin required' using errcode = '42501';
  end if;
  select * into v_row from kernel.payout where payout_id = p_payout_id for update;
  if not found then
    raise exception 'not_found: payout %', p_payout_id using errcode = 'P0002';
  end if;
  if v_row.hold_state = 'none' then
    return jsonb_build_object('status','noop_replay','payout_id', p_payout_id);
  end if;
  -- releases 'held' AND 'probation_hold' — the sole release path (Control-5);
  -- status neither written nor read (T-SCHEMA-PAYOUT-02: equal to pre-hold).
  update kernel.payout
     set hold_state = 'none', hold_reason_code = null, held_by = null, held_at = null,
         updated_at = now()
   where payout_id = p_payout_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (auth.uid(), 'payout.release', 'payout', p_payout_id, coalesce(v_row.hold_reason_code,'released'),
          jsonb_build_object('hold_state', v_row.hold_state),
          jsonb_build_object('hold_state', 'none'));
  return jsonb_build_object('status','ok','payout_id', p_payout_id);
end;
$$;

-- ============================================================================
-- PART 10 — the money-authority RPCs (MONEY §6/§8; RPC §17.1-17.9)
--   The tier ladder reads the D-3 keys, ALL seeded NULL: under C61/X-12/AUTHZ-M3
--   an unset key authorizes NOTHING — nothing auto-executes, support approves
--   nothing, everything parks to the strictest class — until the owner sets
--   values at activation.
-- ============================================================================
-- §17.1 — the tiered entry verb. EDGE-FRONTED; EXEC authenticated; the tier is
-- decided SERVER-SIDE on the CUMULATIVE payment operand (§17.1a/MB-1).
create or replace function kernel.request_order_refund(
  p_order_id uuid, p_atom_ids uuid[], p_amount_minor integer, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid;
  v_order      venue."order"%rowtype;
  v_pn         kernel.payment_native%rowtype;
  v_total      integer;
  v_prior      integer;
  v_parked     integer;
  v_cum        integer;
  v_is_buyer   boolean;
  v_is_orgrole boolean;
  v_is_plat    boolean;
  v_is_admin_risk boolean;
  v_has_consumed boolean := false;
  v_atom       record;
  v_targets    uuid[] := '{}';
  v_class      text;
  v_execute    boolean := false;
  v_bmax numeric; v_bwin numeric; v_oauto numeric; v_odual numeric; v_scap numeric;
  v_ttl numeric; v_spolicy text;
  v_request_id uuid;
  v_res        jsonb;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: no principal' using errcode = '42501';
  end if;
  if not public.check_rate_limit(v_uid, 'request_order_refund', 30, 3600) then
    raise exception 'policy_violation: rate limit exceeded for refund requests';
  end if;
  -- idempotency FIRST (before the status gate): a replay of a request that
  -- already executed/parked returns the original, even once the order has moved
  -- to refunded/partially_refunded.
  select ar.request_id into v_request_id from kernel.approval_request ar
   where ar.requested_by = v_uid and ar.command_idempotency_key = p_command_key;
  if v_request_id is not null then
    return jsonb_build_object('status','idempotency_replay','request_id', v_request_id);
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'precondition_failed: bad_amount';
  end if;
  if p_reason_code not in ('buyer_request','event_cancelled','oversell_correction',
                           'dispute','admin_action','auto_compensation') then
    raise exception 'precondition_failed: bad_reason_code %', p_reason_code;
  end if;

  select * into v_order from venue."order" where order_id = p_order_id;
  if not found then
    raise exception 'not_found: order %', p_order_id using errcode = 'P0002';
  end if;

  -- caller class (org_admin + every venue role FORBIDDEN — MONEY §6.1)
  v_is_buyer   := (v_order.buyer_id = v_uid);
  v_is_orgrole := kernel.has_org_role(v_order.org_id, array['org_owner','org_finance']);
  v_is_admin_risk := kernel.is_platform(array['platform_risk','platform_admin']);
  v_is_plat    := v_is_admin_risk or kernel.is_platform(array['platform_support']);
  if not (v_is_buyer or v_is_orgrole or v_is_plat) then
    raise exception 'insufficient_privilege: buyer, org money role, or platform required' using errcode = '42501';
  end if;
  -- C58: an IMMATURE org money grant fails as sod_violation
  if v_is_orgrole and not v_is_buyer and not v_is_plat
     and not kernel.money_role_grant_matured(v_order.org_id) then
    raise exception 'sod_violation: org money grant not yet matured';
  end if;
  -- §6.1 reason-code caller policy (R7 P2): only platform may cite the
  -- privileged causes; org/buyer callers are confined to their two.
  if not v_is_plat and p_reason_code not in ('buyer_request','oversell_correction') then
    raise exception 'policy_violation: reason_code % is platform-only', p_reason_code;
  end if;

  -- ladder rank 1: the session read-gate
  perform 1 from catalog.event_session s where s.session_id = v_order.event_session_id for share;
  -- rank 3: the order
  select * into v_order from venue."order" where order_id = p_order_id for update;
  if v_order.status not in ('paid','partially_refunded') then
    raise exception 'precondition_failed: order % is % — only a paid order refunds', p_order_id, v_order.status;
  end if;
  select * into v_pn from kernel.payment_native where order_id = p_order_id;
  if not found then
    raise exception 'precondition_failed: order % carries no native payment link', p_order_id;
  end if;

  -- rank 5: targeted atoms (ascending) — validate membership + partition
  for v_atom in
    select t.ticket_atom_id, t.state, t.current_owner_id, t.resale_state
      from kernel.tickets t
      join kernel.ticket_ownership_log l1
        on l1.ticket_atom_id = t.ticket_atom_id and l1.sequence = 1
     where t.ticket_atom_id = any(coalesce(p_atom_ids, '{}'))
       and l1.cause_ref in (select oi.id from venue.order_item oi where oi.order_id = p_order_id)
     order by t.ticket_atom_id
     for update of t
  loop
    if v_atom.state = 'scanned' then
      v_has_consumed := true;
    elsif v_atom.state in ('issued','active') then
      if v_atom.current_owner_id <> v_order.buyer_id then
        raise exception 'custody_moved: atom % left the buyer — platform review required', v_atom.ticket_atom_id;
      end if;
      -- §17.1 precond 5: a listed/locked atom must be delisted first; an atom
      -- already under refund_hold is covered by ANOTHER pending request (R6 P2).
      if v_atom.resale_state <> 'none' then
        raise exception 'conflict_locked: atom % is % — delist / no overlapping refund request', v_atom.ticket_atom_id, v_atom.resale_state;
      end if;
      if kernel.is_transfer_frozen(v_atom.ticket_atom_id) then
        raise exception 'frozen: atom % is transfer-frozen', v_atom.ticket_atom_id;
      end if;
      v_targets := v_targets || v_atom.ticket_atom_id;
    end if;
  end loop;

  -- rank 6: the payment lock — taken BEFORE the cumulative/tier computation so
  -- the operand is serialized (MB-1; P0-4), not a stale snapshot.
  perform 1 from public.payments p where p.id = v_pn.payment_id for update;
  -- the CUMULATIVE operand (MB-1): succeeded/in-flight refunds + parked pending
  -- requests on this order + this request
  select p.total into v_total from public.payments p where p.id = v_pn.payment_id;
  select coalesce(sum(r.amount_minor), 0) into v_prior
    from kernel.refund r where r.payment_id = v_pn.payment_id and r.status <> 'failed';
  select coalesce(sum(ar.amount_minor), 0) into v_parked
    from kernel.approval_request ar
   where ar.action = 'refund.issue' and ar.subject_kind = 'order'
     and ar.subject_id = p_order_id and ar.state = 'pending';
  v_cum := v_prior + v_parked + p_amount_minor;
  if v_cum > v_total then
    raise exception 'precondition_failed: over_refund (cumulative % > payment total %)', v_cum, v_total;
  end if;

  -- D-3 keys (latest version; NULL = that arm authorizes NOTHING)
  select (c.value #>> '{}')::numeric into v_bmax  from catalog.platform_config c where c.key='refund.buyer_self_service_max_minor'   order by c.version desc limit 1;
  select (c.value #>> '{}')::numeric into v_bwin  from catalog.platform_config c where c.key='refund.buyer_self_service_window_hours' order by c.version desc limit 1;
  select (c.value #>> '{}')::numeric into v_oauto from catalog.platform_config c where c.key='refund.org_auto_execute_max_minor'      order by c.version desc limit 1;
  select (c.value #>> '{}')::numeric into v_odual from catalog.platform_config c where c.key='refund.org_dual_control_max_minor'      order by c.version desc limit 1;
  select (c.value #>> '{}')::numeric into v_scap  from catalog.platform_config c where c.key='refund.platform_support_max_minor'      order by c.version desc limit 1;
  select (c.value #>> '{}')::numeric into v_ttl   from catalog.platform_config c where c.key='refund.request_ttl_hours'               order by c.version desc limit 1;
  select (c.value #>> '{}')          into v_spolicy from catalog.platform_config c where c.key='refund.scanned_atom_policy'           order by c.version desc limit 1;

  -- tier decision. The consumed-atom row takes PRECEDENCE over every amount row.
  if v_has_consumed and coalesce(v_spolicy, 'platform_review') = 'refuse' then
    raise exception 'policy_violation: a consumed (scanned) atom is not refundable (scanned_atom_policy=refuse)';
  elsif v_has_consumed and coalesce(v_spolicy, 'platform_review') = 'platform_review' then
    v_class := 'platform'; v_execute := false;
  elsif v_is_admin_risk then
    v_execute := true;
  elsif v_is_plat then      -- platform_support: capped, unset = ZERO (AUTHZ-M3)
    if v_scap is not null and v_cum <= v_scap then v_execute := true;
    else v_class := 'platform'; v_execute := false; end if;
  elsif v_is_buyer and v_bmax is not null and v_cum <= v_bmax
        and v_bwin is not null
        and v_order.created_at > now() - make_interval(hours => v_bwin::int) then
    v_execute := true;      -- buyer self-service tier (capped + windowed)
  elsif v_is_orgrole and v_oauto is not null and v_cum <= v_oauto then
    v_execute := true;      -- org auto-execute tier
  else
    v_class := case when v_odual is not null and v_cum <= v_odual then 'org' else 'platform' end;
    v_execute := false;
  end if;

  if v_execute then
    -- E-52: the executed tier is WITNESSED by an auto-approved intent record —
    -- the same class the parked branch writes; the tier check above IS the
    -- authority, SN-SYSTEM approver satisfies SoD. expires_at MUST be > now()
    -- (077 CHECK; P0-1/R3) even though the row is born approved+executed. The
    -- executor is then called with the DELEGATED key 'req:'||request_id
    -- (PFA-23) so the refund is bound to THIS record and single-use.
    insert into kernel.approval_request
           (action, required_approver_class, subject_kind, subject_id, org_id, payload,
            amount_minor, config_versions, requested_by, approved_by, state, reason_code,
            expires_at, command_idempotency_key)
    values ('refund.issue', case when v_is_plat or v_is_buyer then 'platform' else 'org' end,
            'order', p_order_id, v_order.org_id,
            jsonb_build_object('atom_ids', to_jsonb(v_targets), 'reason_code', p_reason_code,
                               'auto_executed', true),
            p_amount_minor,
            jsonb_build_object('refund.platform_support_max_minor', null),
            v_uid, '00000000-0000-0000-0000-0000000000f1', 'approved', 'auto_execute_tier',
            now() + interval '1 hour', p_command_key)
    returning request_id into v_request_id;
    v_res := kernel.refund_primary_order(p_order_id, p_amount_minor, p_reason_code,
                                         'req:' || v_request_id::text);
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
    values (v_uid, 'refund.request', 'order', p_order_id, p_reason_code,
            jsonb_build_object('tier', 'auto_execute', 'request_id', v_request_id) || v_res);
    return v_res || jsonb_build_object('request_id', v_request_id, 'status', 'executed');
  end if;

  -- PARKED branch: the dual-control intent + the refund_hold overlay. A parked
  -- request MUST expire (P0-1) — an unset TTL cannot mint an immortal hold.
  if v_ttl is null then
    raise exception 'precondition_failed: config_unset refund.request_ttl_hours — parked requests need a bounded life (C61 fail-closed)';
  end if;
  insert into kernel.approval_request
         (action, required_approver_class, subject_kind, subject_id, org_id, payload,
          amount_minor, config_versions, requested_by, state, reason_code,
          expires_at, command_idempotency_key)
  values ('refund.issue', v_class, 'order', p_order_id, v_order.org_id,
          jsonb_build_object('atom_ids', to_jsonb(v_targets), 'reason_code', p_reason_code,
                             'has_consumed', v_has_consumed),
          p_amount_minor,
          jsonb_build_object(
            'refund.buyer_self_service_max_minor',   (select max(c.version) from catalog.platform_config c where c.key='refund.buyer_self_service_max_minor'),
            'refund.buyer_self_service_window_hours',(select max(c.version) from catalog.platform_config c where c.key='refund.buyer_self_service_window_hours'),
            'refund.org_auto_execute_max_minor',     (select max(c.version) from catalog.platform_config c where c.key='refund.org_auto_execute_max_minor'),
            'refund.org_dual_control_max_minor',     (select max(c.version) from catalog.platform_config c where c.key='refund.org_dual_control_max_minor'),
            'refund.platform_support_max_minor',     (select max(c.version) from catalog.platform_config c where c.key='refund.platform_support_max_minor'),
            'refund.scanned_atom_policy',            (select max(c.version) from catalog.platform_config c where c.key='refund.scanned_atom_policy')),
          v_uid, 'pending', p_reason_code,
          now() + make_interval(hours => v_ttl::int), p_command_key)
  returning request_id into v_request_id;

  update kernel.tickets set resale_state = 'refund_hold', updated_at = now()
   where ticket_atom_id = any(v_targets) and resale_state = 'none';

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values (v_uid, 'refund.request', 'order', p_order_id, p_reason_code,
          jsonb_build_object('tier', 'parked', 'required_approver_class', v_class,
                            'request_id', v_request_id, 'amount_minor', p_amount_minor));

  return jsonb_build_object('status','parked','request_id', v_request_id,
                            'required_approver_class', v_class);
exception when unique_violation then
  -- (requested_by, command_idempotency_key) replay → return the original request
  select ar.request_id into v_request_id from kernel.approval_request ar
   where ar.requested_by = v_uid and ar.command_idempotency_key = p_command_key;
  if v_request_id is not null then
    return jsonb_build_object('status','idempotency_replay','request_id', v_request_id);
  end if;
  raise;
end;
$$;

-- §17.2 — the approve/deny verb, keyed on (action, required_approver_class)
-- and NOTHING else (AUTHZ-C1A). EDGE-FRONTED; EXEC authenticated.
create or replace function kernel.approve_refund_request(
  p_request_id uuid, p_decision text, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid;
  v_ar     kernel.approval_request%rowtype;
  v_order  venue."order"%rowtype;
  v_pn     kernel.payment_native%rowtype;
  v_prior  integer; v_parked integer; v_cum integer;
  v_scap   numeric;
  v_class  text;
  v_odual  numeric; v_oauto numeric; v_spolicy text;
  v_setter uuid;
  v_res    jsonb;
  v_key    text; v_next integer;
  v_aal    text;
  v_live_consumed boolean;
  v_atom   record;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: no principal' using errcode = '42501';
  end if;
  if p_decision not in ('approve','deny') then
    raise exception 'invalid_input: decision must be approve|deny';
  end if;
  if not public.check_rate_limit(v_uid, 'approve_refund_request', 60, 3600) then
    raise exception 'policy_violation: rate limit exceeded';
  end if;

  select * into v_ar from kernel.approval_request where request_id = p_request_id for update;
  if not found then
    raise exception 'not_found: request %', p_request_id using errcode = 'P0002';
  end if;
  if v_ar.state <> 'pending' then
    if v_ar.state = 'approved' and p_decision = 'approve' then
      return jsonb_build_object('status','noop_replay','request_id', p_request_id, 'state', v_ar.state);
    end if;
    if v_ar.state = 'denied' and p_decision = 'deny' then
      return jsonb_build_object('status','noop_replay','request_id', p_request_id, 'state', v_ar.state);
    end if;
    raise exception 'precondition_failed: request % is % — only a pending request decides', p_request_id, v_ar.state;
  end if;
  -- Q5 lifetime (R1 P1): an expired-but-unswept request never decides.
  if v_ar.expires_at is not null and v_ar.expires_at <= now() then
    update kernel.approval_request set state = 'expired', updated_at = now() where request_id = p_request_id;
    if v_ar.action = 'refund.issue' and v_ar.payload ? 'atom_ids' then
      update kernel.tickets set resale_state = 'none', updated_at = now()
       where ticket_atom_id in (select (jsonb_array_elements_text(v_ar.payload->'atom_ids'))::uuid)
         and resale_state = 'refund_hold';
    end if;
    raise exception 'precondition_failed: request % has expired', p_request_id;
  end if;
  -- SoD-2: the requester may never decide their own token
  if v_uid = v_ar.requested_by then
    raise exception 'self_approval: the requester cannot decide their own request';
  end if;
  -- refund.issue: the buyer of the order may never approve a refund of their own
  -- purchase (SoD — money would land on the approver's card; R1 P2).
  if v_ar.action = 'refund.issue' then
    select * into v_order from venue."order" where order_id = v_ar.subject_id;
    if found and v_order.buyer_id = v_uid then
      raise exception 'sod_violation: the order buyer cannot approve a refund of their own purchase';
    end if;
  end if;
  -- AUTHZ-M4 step-up: an approval decision is a money action and requires a
  -- step-up (aal2) session. Absent claim ⇒ step_up_unavailable (never evaluated
  -- as satisfied); aal1 ⇒ step_up_required. Denials are exempt (S-3 spirit —
  -- refusing money is not a money movement).
  if p_decision = 'approve' then
    v_aal := coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb ->> 'aal';
    if v_aal is null then
      raise exception 'step_up_unavailable: the session carries no aal claim';
    end if;
    if v_aal <> 'aal2' then
      raise exception 'step_up_required: a step-up (aal2) session is required to approve money';
    end if;
  end if;

  -- the FIVE-ROW branch table — (action, required_approver_class), nothing else
  if v_ar.action = 'refund.issue' and v_ar.required_approver_class = 'org' then
    if not kernel.has_org_role(v_ar.org_id, array['org_owner','org_finance']) then
      raise exception 'insufficient_privilege: org money role required' using errcode = '42501';
    end if;
    if p_decision = 'approve' and not kernel.money_role_grant_matured(v_ar.org_id) then
      raise exception 'sod_violation: org money grant not yet matured';   -- S-3: never gates a denial
    end if;
  elsif v_ar.action = 'refund.issue' then   -- required_approver_class = 'platform'
    if kernel.is_platform(array['platform_risk','platform_admin']) then
      null;
    elsif kernel.is_platform(array['platform_support']) then
      -- support cap re-evaluated on the SELF-EXCLUDED cumulative (T-RPC-MONEY-23);
      -- unset key = ZERO (AUTHZ-M3)
      select * into v_pn from kernel.payment_native where order_id = v_ar.subject_id;
      select coalesce(sum(r.amount_minor),0) into v_prior
        from kernel.refund r where r.payment_id = v_pn.payment_id and r.status <> 'failed';
      select coalesce(sum(a2.amount_minor),0) into v_parked
        from kernel.approval_request a2
       where a2.action='refund.issue' and a2.subject_kind='order' and a2.subject_id = v_ar.subject_id
         and a2.state='pending' and a2.request_id <> p_request_id;
      v_cum := v_prior + v_parked + v_ar.amount_minor;
      -- AUTHZ-M3: the cap is read at the version PINNED in the request (R3 P1-6),
      -- not the live latest.
      select (c.value #>> '{}')::numeric into v_scap from catalog.platform_config c
       where c.key='refund.platform_support_max_minor'
         and c.version = coalesce((v_ar.config_versions->>'refund.platform_support_max_minor')::int, -1);
      if v_scap is null or v_cum > v_scap then
        raise exception 'insufficient_privilege: platform_support cap (cumulative % vs %)',
          v_cum, coalesce(v_scap::text,'UNSET') using errcode = '42501';
      end if;
    else
      raise exception 'insufficient_privilege: platform role required' using errcode = '42501';
    end if;
  elsif v_ar.action = 'payout.request' and v_ar.required_approver_class = 'org' then
    if not kernel.has_org_role(v_ar.org_id, array['org_owner','org_finance']) then
      raise exception 'insufficient_privilege: org money role required' using errcode = '42501';
    end if;
    if p_decision = 'approve' and not kernel.money_role_grant_matured(v_ar.org_id) then
      raise exception 'sod_violation: org money grant not yet matured';   -- S-3: never gates a denial
    end if;
    -- §8.2: the destination SETTER may never approve the payout — read under the
    -- org lock so a concurrent set_org_payout_destination cannot slip past (R6 P1).
    select o.payout_destination_set_by into v_setter from kernel.organization o
     where o.org_id = v_ar.org_id for update;
    if v_setter is not null and v_setter = v_uid then
      raise exception 'sod_violation: the payout-destination setter cannot approve a payout';
    end if;
  elsif v_ar.action = 'payout.request' then   -- 'platform': risk/admin ONLY, support DENIED
    if not kernel.is_platform(array['platform_risk','platform_admin']) then
      raise exception 'insufficient_privilege: platform_risk or platform_admin required (support may not approve payouts)' using errcode = '42501';
    end if;
  elsif v_ar.action = 'config.set_money_key' then   -- 'platform_admin': a SECOND distinct admin
    if not kernel.is_platform(array['platform_admin']) then
      raise exception 'insufficient_privilege: platform_admin required' using errcode = '42501';
    end if;
  else
    raise exception 'precondition_failed: unrecognized approval branch (%, %)', v_ar.action, v_ar.required_approver_class;
  end if;

  if p_decision = 'deny' then
    if p_reason_code is null or length(trim(p_reason_code)) = 0 then
      raise exception 'precondition_failed: bad_reason_code (a denial carries its reason)';
    end if;
    update kernel.approval_request
       set state = 'denied', approved_by = v_uid, reason_code = p_reason_code, updated_at = now()
     where request_id = p_request_id;
    if v_ar.action = 'refund.issue' then
      update kernel.tickets set resale_state = 'none', updated_at = now()
       where ticket_atom_id in (select (jsonb_array_elements_text(v_ar.payload->'atom_ids'))::uuid)
         and resale_state = 'refund_hold';
    end if;
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
    values (v_uid, v_ar.action || '.request_denied', 'approval_request', p_request_id, p_reason_code);
    return jsonb_build_object('status','denied','request_id', p_request_id);
  end if;

  -- APPROVE. For refund.issue: re-derive the tier from the PINNED config —
  -- a drifted tier is 'stale', never re-routed (T-RPC-AUTHZ-02).
  if v_ar.action = 'refund.issue' then
    select * into v_pn from kernel.payment_native where order_id = v_ar.subject_id;
    select coalesce(sum(r.amount_minor),0) into v_prior
      from kernel.refund r where r.payment_id = v_pn.payment_id and r.status <> 'failed';
    select coalesce(sum(a2.amount_minor),0) into v_parked
      from kernel.approval_request a2
     where a2.action='refund.issue' and a2.subject_kind='order' and a2.subject_id = v_ar.subject_id
       and a2.state='pending' and a2.request_id <> p_request_id;
    v_cum := v_prior + v_parked + v_ar.amount_minor;
    select (c.value #>> '{}')::numeric into v_oauto from catalog.platform_config c
     where c.key='refund.org_auto_execute_max_minor'
       and c.version = coalesce((v_ar.config_versions->>'refund.org_auto_execute_max_minor')::int, -1);
    select (c.value #>> '{}')::numeric into v_odual from catalog.platform_config c
     where c.key='refund.org_dual_control_max_minor'
       and c.version = coalesce((v_ar.config_versions->>'refund.org_dual_control_max_minor')::int, -1);
    select (c.value #>> '{}') into v_spolicy from catalog.platform_config c
     where c.key='refund.scanned_atom_policy'
       and c.version = coalesce((v_ar.config_versions->>'refund.scanned_atom_policy')::int, -1);
    -- T-RPC-AUTHZ-01 (P0-3): re-derive consumed from LIVE atom state under lock,
    -- never from the request-time payload snapshot — an atom scanned while parked
    -- must re-tier to platform (the MD-6 collusion control). Also re-check custody.
    v_live_consumed := false;
    for v_atom in
      select t.ticket_atom_id, t.state, t.current_owner_id from kernel.tickets t
       where t.ticket_atom_id in (select (jsonb_array_elements_text(v_ar.payload->'atom_ids'))::uuid)
       for update of t
    loop
      if v_atom.state = 'scanned' then v_live_consumed := true; end if;
      if v_atom.state in ('issued','active') and v_order.order_id is not null
         and v_atom.current_owner_id <> v_order.buyer_id then
        raise exception 'custody_moved: atom % left the buyer since the request', v_atom.ticket_atom_id;
      end if;
    end loop;
    if v_live_consumed and coalesce(v_spolicy,'platform_review') = 'refuse' then
      raise exception 'policy_violation: a consumed atom is not refundable (scanned_atom_policy=refuse)';
    elsif v_live_consumed and coalesce(v_spolicy,'platform_review') = 'platform_review' then
      v_class := 'platform';
    else
      v_class := case when v_odual is not null and v_cum <= v_odual then 'org' else 'platform' end;
    end if;
    if v_class <> v_ar.required_approver_class then
      update kernel.approval_request set state = 'stale', updated_at = now()
       where request_id = p_request_id;
      update kernel.tickets set resale_state = 'none', updated_at = now()
       where ticket_atom_id in (select (jsonb_array_elements_text(v_ar.payload->'atom_ids'))::uuid)
         and resale_state = 'refund_hold';
      insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
      values (v_uid, 'refund.request_stale', 'approval_request', p_request_id, 'tier_drift');
      return jsonb_build_object('status','stale','request_id', p_request_id);
    end if;

    update kernel.approval_request
       set state = 'approved', approved_by = v_uid, updated_at = now()
     where request_id = p_request_id;
    update kernel.tickets set resale_state = 'none', updated_at = now()
     where ticket_atom_id in (select (jsonb_array_elements_text(v_ar.payload->'atom_ids'))::uuid)
       and resale_state = 'refund_hold';
    -- PFA-23: execute via the DELEGATED key bound to THIS request — single-use
    -- (refund.idempotency_key = 'req:'||request_id), amount + payload-atom bound.
    v_res := kernel.refund_primary_order(v_ar.subject_id,
               v_ar.amount_minor, coalesce(v_ar.payload->>'reason_code','buyer_request'),
               'req:' || p_request_id::text);
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
    values (v_uid, 'refund.request_approved', 'approval_request', p_request_id,
            coalesce(p_reason_code,'approved'), v_res);
    return v_res || jsonb_build_object('status','approved','request_id', p_request_id);
  end if;

  if v_ar.action = 'payout.request' then
    update kernel.approval_request
       set state = 'approved', approved_by = v_uid, updated_at = now()
     where request_id = p_request_id;
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
    values (v_uid, 'payout.request_approved', 'approval_request', p_request_id, coalesce(p_reason_code,'approved'));
    return jsonb_build_object('status','approved','request_id', p_request_id);
  end if;

  -- config.set_money_key: the approved LOOSENING applies here (078 parks it;
  -- the applied write is the next version of the key, values from the payload).
  v_key := v_ar.payload->>'key';
  select coalesce(max(c.version), 0) + 1 into v_next from catalog.platform_config c where c.key = v_key;
  insert into catalog.platform_config (key, version, value, visibility)
  values (v_key, v_next, v_ar.payload->'proposed_value', 'restricted');
  update kernel.approval_request
     set state = 'approved', approved_by = v_uid, updated_at = now()
   where request_id = p_request_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'config.money_key_approved', 'approval_request', p_request_id,   -- MONEY §7.3 name
          coalesce(p_reason_code,'approved'),
          jsonb_build_object('key', v_key, 'value', v_ar.payload->'current_value'),
          jsonb_build_object('key', v_key, 'value', v_ar.payload->'proposed_value', 'version', v_next));
  return jsonb_build_object('status','approved','request_id', p_request_id, 'applied_version', v_next);
end;
$$;

-- §17.3 — cancel. Requester · org money roles (NO maturity conjunct — never
-- applied to deny/cancel, S-3) · platform. DB-RPC; EXEC authenticated.
create or replace function kernel.cancel_refund_request(
  p_request_id uuid, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_ar  kernel.approval_request%rowtype;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: no principal' using errcode = '42501';
  end if;
  select * into v_ar from kernel.approval_request where request_id = p_request_id for update;
  if not found then
    raise exception 'not_found: request %', p_request_id using errcode = 'P0002';
  end if;
  if not (v_uid = v_ar.requested_by
          or kernel.has_org_role(v_ar.org_id, array['org_owner','org_finance'])
          or kernel.is_platform(array['platform_support','platform_risk','platform_admin'])) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  if v_ar.state = 'cancelled' then
    return jsonb_build_object('status','noop_replay','request_id', p_request_id);
  end if;
  if v_ar.state <> 'pending' then
    raise exception 'precondition_failed: request % is % — only a pending request cancels', p_request_id, v_ar.state;
  end if;
  update kernel.approval_request
     set state = 'cancelled', reason_code = coalesce(p_reason_code,'cancelled'), updated_at = now()
   where request_id = p_request_id;
  if v_ar.action = 'refund.issue' then
    update kernel.tickets set resale_state = 'none', updated_at = now()
     where ticket_atom_id in (select (jsonb_array_elements_text(v_ar.payload->'atom_ids'))::uuid)
       and resale_state = 'refund_hold';
  end if;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (v_uid, 'refund.request_cancelled', 'approval_request', p_request_id, coalesce(p_reason_code,'cancelled'));
  perform notify.emit_event('refund_request_cancelled', 'approval_request', p_request_id,
          'cancel:' || p_request_id::text, jsonb_build_object('by', v_uid));
  return jsonb_build_object('status','cancelled','request_id', p_request_id);
end;
$$;

-- §17.4 — the expiry sweep. DEF/scheduler-only; NOT optional (P0-1: a hold with
-- no tick is a bricked ticket on a paying customer).
create or replace function kernel.sweep_expired_refund_requests()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req record;
  v_swept integer := 0;
  v_holds integer := 0;
  v_n integer;
begin
  -- ALL actions expire (R1 P1) — a stale payout/config request must not remain
  -- approvable forever; refund holds release only for refund.issue.
  for v_req in
    select ar.request_id, ar.action, ar.payload
      from kernel.approval_request ar
     where ar.state = 'pending' and ar.expires_at <= now()
     order by ar.expires_at
     for update skip locked
  loop
    update kernel.approval_request set state = 'expired', updated_at = now()
     where request_id = v_req.request_id;
    if v_req.action = 'refund.issue' and v_req.payload ? 'atom_ids' then
      update kernel.tickets set resale_state = 'none', updated_at = now()
       where ticket_atom_id in (select (jsonb_array_elements_text(v_req.payload->'atom_ids'))::uuid)
         and resale_state = 'refund_hold';
      get diagnostics v_n = row_count;
      v_holds := v_holds + v_n;
    end if;
    v_swept := v_swept + 1;
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
    values ('00000000-0000-0000-0000-0000000000f1', v_req.action || '.request_expired', 'approval_request',
            v_req.request_id, 'ttl_expired');
    perform notify.emit_event('refund_request_expired', 'approval_request', v_req.request_id,
            'expire:' || v_req.request_id::text, jsonb_build_object('action', v_req.action));
  end loop;
  return jsonb_build_object('status','ok','swept_count', v_swept, 'holds_released', v_holds);
end;
$$;

-- §17.5/§17.6/§17.8 — the scoped money reads (closed filter sets; no scope-free
-- form; stripe refs surface as PRESENCE booleans only; no buyer PII).
create or replace function kernel.list_org_payouts(
  p_org_id uuid, p_venue_id uuid, p_filters jsonb, p_cursor text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_rows jsonb;
begin
  v_uid := auth.uid();
  if p_org_id is not null then
    if not (kernel.has_org_role(p_org_id, array['org_owner','org_finance'])
            or kernel.is_platform(array['platform_support','platform_risk','platform_admin'])) then
      raise exception 'insufficient_privilege' using errcode = '42501';
    end if;
    select coalesce(jsonb_agg(row order by row->>'created_at' desc), '[]'::jsonb) into v_rows
      from (
        select jsonb_build_object(
                 'payout_id', p.payout_id, 'cause', p.cause, 'cause_ref', p.cause_ref,
                 'amount_minor', p.amount_minor, 'currency', p.currency,
                 'status', p.status, 'hold_state', p.hold_state,
                 'has_transfer_ref', (p.stripe_transfer_ref is not null),
                 'created_at', p.created_at) as row
          from kernel.payout p
         where p.payee_org_id = p_org_id
           and (p_filters->>'status' is null or p.status = p_filters->>'status')
         order by p.created_at desc
         limit 100
      ) q;
    return jsonb_build_object('status','ok','payouts', v_rows);
  end if;
  -- the venue_finance arm scopes through settlement (087); it FAILS CLOSED
  -- until that join exists — an authorized caller sees an empty page, never
  -- an unscoped one.
  if p_venue_id is not null then
    if not (kernel.has_venue_role(p_venue_id, array['venue_finance'])
            or kernel.is_platform(array['platform_support','platform_risk','platform_admin'])) then
      raise exception 'insufficient_privilege' using errcode = '42501';
    end if;
    return jsonb_build_object('status','ok','payouts', '[]'::jsonb);
  end if;
  raise exception 'invalid_input: an org or venue scope is required (no scope-free form)';
end;
$$;

create or replace function kernel.list_org_refunds(
  p_org_id uuid, p_venue_id uuid, p_filters jsonb, p_cursor text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  if p_org_id is null then
    raise exception 'invalid_input: an org scope is required (the sale_id arm fails closed in MVP)';
  end if;
  if not (kernel.has_org_role(p_org_id, array['org_owner','org_finance'])
          or kernel.is_platform(array['platform_support','platform_risk','platform_admin'])) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  -- the CONTRACTED two-hop join: refund.payment_id → payment_native → order →
  -- org (§4.4 — the join direction is the contract). sale-linked refunds are
  -- deliberately unreachable here (T-RPC-MONEY-11).
  select coalesce(jsonb_agg(row order by row->>'created_at' desc), '[]'::jsonb) into v_rows
    from (
      select jsonb_build_object(
               'refund_id', r.refund_id, 'reason_code', r.reason_code,
               'amount_minor', r.amount_minor, 'currency', r.currency,
               'status', r.status, 'has_stripe_ref', (r.stripe_refund_ref is not null),
               'order_id', o.order_id, 'created_at', r.created_at) as row
        from kernel.refund r
        join kernel.payment_native pn on pn.payment_id = r.payment_id
        join venue."order" o on o.order_id = pn.order_id
       where o.org_id = p_org_id
         and (p_filters->>'status' is null or r.status = p_filters->>'status')
       order by r.created_at desc
       limit 100
    ) q;
  return jsonb_build_object('status','ok','refunds', v_rows);
end;
$$;

create or replace function kernel.list_approval_requests(
  p_org_id uuid, p_filters jsonb, p_cursor text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  if p_org_id is null then
    raise exception 'invalid_input: an org scope is required';
  end if;
  if not (kernel.has_org_role(p_org_id, array['org_owner','org_finance'])
          or kernel.is_platform(array['platform_support','platform_risk','platform_admin'])) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(row order by row->>'created_at' desc), '[]'::jsonb) into v_rows
    from (
      select jsonb_build_object(
               'request_id', ar.request_id, 'action', ar.action,
               'required_approver_class', ar.required_approver_class,
               'subject_kind', ar.subject_kind, 'subject_id', ar.subject_id,
               'amount_minor', ar.amount_minor, 'state', ar.state,
               'requested_by', ar.requested_by, 'expires_at', ar.expires_at,
               'created_at', ar.created_at) as row
        from kernel.approval_request ar
       where ar.org_id = p_org_id
         and (p_filters->>'state' is null or ar.state = p_filters->>'state')
       order by ar.created_at desc
       limit 100
    ) q;
  return jsonb_build_object('status','ok','requests', v_rows);
end;
$$;

-- §17.9 / schema §1.12.1 (R-28/C93/C106) — the denial witness. EXEC
-- `authenticated` ONLY — never anon, NEVER service_role; the actor is
-- auth.uid() and NOTHING else can set it (T-SCHEMA-AUDIT-01/-02).
create or replace function kernel.record_money_denial(
  p_action text, p_subject_kind text, p_subject_id uuid, p_error_code text)
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
    raise exception 'insufficient_privilege: record_money_denial requires a human principal (auth.uid() is NULL)'
      using errcode = '42501';
  end if;
  if p_action not in ('refund.request','refund.approve','refund.cancel','refund.execute',
                      'payout.hold','payout.release','payout.destination','obligation.resolve') then
    raise exception 'invalid_input: % is not a money denial action', p_action;
  end if;
  if p_subject_kind not in ('order','payment','payout','approval_request','organization','ticket_atom','obligation') then
    raise exception 'invalid_input: bad subject_kind %', p_subject_kind;
  end if;
  if not public.check_rate_limit(v_uid, 'record_money_denial', 60, 3600) then
    raise exception 'policy_violation: rate limit exceeded';
  end if;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (v_uid, p_action || '.denied', p_subject_kind, p_subject_id, coalesce(p_error_code,'denied'));
  return jsonb_build_object('status','ok');
end;
$$;

-- §17.7 / MONEY §8.2 — the payout-destination change. org_owner ONLY (SoD-1:
-- org_finance excluded), step-up REQUIRED (AUTHZ-M4: an absent claim is
-- step_up_unavailable, never evaluated), maturity binds the SETTER.
create or replace function kernel.set_org_payout_destination(
  p_org_id uuid, p_connect_account_ref text, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid;
  v_org    kernel.organization%rowtype;
  v_aal    text;
  v_cool   numeric;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: no principal' using errcode = '42501';
  end if;
  if not kernel.has_org_role(p_org_id, array['org_owner']) then
    raise exception 'insufficient_privilege: org_owner only (SoD-1)' using errcode = '42501';
  end if;
  if not kernel.money_role_grant_matured(p_org_id) then
    raise exception 'sod_violation: org money grant not yet matured';
  end if;
  -- AUTHZ-M4: step-up demanded (the key's NULL seed DEMANDS it — fail closed);
  -- an absent claim can never be evaluated as satisfied.
  v_aal := coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb ->> 'aal';
  if v_aal is null then
    raise exception 'step_up_unavailable: the session carries no aal claim';
  end if;
  if v_aal <> 'aal2' then
    raise exception 'step_up_required: a step-up (aal2) session is required for money-destination changes';
  end if;
  if p_connect_account_ref is null or p_connect_account_ref !~ '^acct_[A-Za-z0-9]+$' then
    raise exception 'precondition_failed: bad connect account ref';
  end if;

  select * into v_org from kernel.organization where org_id = p_org_id for update;
  if not found then
    raise exception 'not_found: org %', p_org_id using errcode = 'P0002';
  end if;
  if v_org.payout_destination_locked_until is not null and v_org.payout_destination_locked_until > now() then
    raise exception 'precondition_failed: destination cool-down until %', v_org.payout_destination_locked_until;
  end if;
  select (c.value #>> '{}')::numeric into v_cool from catalog.platform_config c
   where c.key = 'payout.destination_cooldown_hours' order by c.version desc limit 1;

  update kernel.organization
     set stripe_connect_account_ref = p_connect_account_ref,
         payout_destination_set_by = v_uid,
         payout_destination_locked_until = case when v_cool is null then null
                                                else now() + make_interval(hours => v_cool::int) end,
         updated_at = now()
   where org_id = p_org_id;

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'org.payout_destination.change', 'organization', p_org_id,
          coalesce(p_reason_code,'destination_change'),
          jsonb_build_object('connect_ref', v_org.stripe_connect_account_ref),
          jsonb_build_object('connect_ref', p_connect_account_ref));
  return jsonb_build_object('status','ok','org_id', p_org_id);
end;
$$;

-- ============================================================================
-- PART 11 — the Stripe state-sync pair (RPC §20.7.6/.7; MB-2b/S-24; R-31:
--   DEF, service_role only, NO human path — none may ever be added).
-- ============================================================================
create or replace function kernel.mark_payout_transfer_state(
  p_payout_id uuid, p_new_status text, p_stripe_transfer_ref text, p_failure_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row kernel.payout%rowtype;
begin
  -- O16: form (a) — 'paid' asserts the executor's synchronous transfer result;
  -- 'submitted' belongs to 087's request path and is REFUSED here (a second
  -- door past the money controls otherwise).
  if p_new_status not in ('paid','failed','reversed') then
    raise exception 'invalid_input: mark_payout_transfer_state takes paid|failed|reversed';
  end if;
  select * into v_row from kernel.payout where payout_id = p_payout_id for update;
  if not found then
    raise exception 'not_found: payout %', p_payout_id using errcode = 'P0002';
  end if;
  -- Control-4-by-webhook defense: a HELD payout refuses the sync, BOTH columns
  -- untouched (T-SCHEMA-PAYOUT-06).
  if v_row.hold_state <> 'none' then
    raise exception 'precondition_failed: payout_held';
  end if;
  -- replay: same terminal + same ref = noop, never a raise
  if v_row.status = p_new_status
     and (p_stripe_transfer_ref is null or v_row.stripe_transfer_ref = p_stripe_transfer_ref) then
    return jsonb_build_object('status','noop_replay','payout_id', p_payout_id);
  end if;
  -- forward-only: submitted→paid|failed; paid→reversed (the one legal
  -- terminal-to-terminal edge). Everything else is backwards.
  if not ( (v_row.status = 'submitted' and p_new_status in ('paid','failed'))
        or (v_row.status = 'paid'      and p_new_status = 'reversed') ) then
    raise exception 'precondition_failed: payout_state_backwards (% → %)', v_row.status, p_new_status;
  end if;
  if p_new_status in ('paid','reversed') and p_stripe_transfer_ref is null then
    raise exception 'invalid_input: stripe_transfer_ref is mandatory for %', p_new_status;
  end if;
  if p_new_status = 'failed' and (p_failure_code is null or length(trim(p_failure_code)) = 0) then
    raise exception 'invalid_input: failure_code is mandatory for failed';
  end if;
  -- write-once ref: equal-on-replay, conflict otherwise
  if v_row.stripe_transfer_ref is not null and p_stripe_transfer_ref is not null
     and v_row.stripe_transfer_ref <> p_stripe_transfer_ref then
    raise exception 'conflict_locked: stripe_transfer_ref is write-once (% vs %)',
      v_row.stripe_transfer_ref, p_stripe_transfer_ref;
  end if;

  update kernel.payout
     set status = p_new_status,
         stripe_transfer_ref = coalesce(v_row.stripe_transfer_ref, p_stripe_transfer_ref),
         updated_at = now()
   where payout_id = p_payout_id;

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (coalesce(auth.uid(),'00000000-0000-0000-0000-0000000000f1'), 'payout.state_sync', 'payout',
          p_payout_id, coalesce(p_failure_code, p_new_status),
          jsonb_build_object('status', v_row.status),
          jsonb_build_object('status', p_new_status));

  if p_new_status = 'paid' then
    -- the FIFTH seam: settlement closed→paid rides this hook (body 087).
    perform venue.on_payout_settled(p_payout_id);
  end if;
  return jsonb_build_object('status','ok','payout_id', p_payout_id, 'new_status', p_new_status);
end;
$$;

create or replace function kernel.mark_refund_state(
  p_refund_id uuid, p_new_status text, p_stripe_refund_ref text, p_failure_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row kernel.refund%rowtype;
begin
  if p_new_status not in ('submitted','succeeded','failed') then
    raise exception 'invalid_input: mark_refund_state takes submitted|succeeded|failed';
  end if;
  select * into v_row from kernel.refund where refund_id = p_refund_id for update;
  if not found then
    raise exception 'not_found: refund %', p_refund_id using errcode = 'P0002';
  end if;
  if v_row.status = p_new_status
     and (p_stripe_refund_ref is null or v_row.stripe_refund_ref = p_stripe_refund_ref) then
    return jsonb_build_object('status','noop_replay','refund_id', p_refund_id);
  end if;
  -- forward-only pending→submitted→succeeded|failed. 'failed' = Stripe ACCEPTED
  -- then couldn't settle (carries re_…); a create-call error leaves 'pending'
  -- (the S-24 pairing CHECK makes the wrong reading unstorable).
  if not ( (v_row.status = 'pending'   and p_new_status = 'submitted')
        or (v_row.status = 'submitted' and p_new_status in ('succeeded','failed')) ) then
    raise exception 'precondition_failed: refund_state_backwards (% → %)', v_row.status, p_new_status;
  end if;
  if p_stripe_refund_ref is null then
    raise exception 'invalid_input: stripe_refund_ref is mandatory (non-pending rows carry it)';
  end if;
  if v_row.stripe_refund_ref is not null and v_row.stripe_refund_ref <> p_stripe_refund_ref then
    raise exception 'conflict_locked: stripe_refund_ref is write-once';
  end if;
  if p_new_status = 'failed' and (p_failure_code is null or length(trim(p_failure_code)) = 0) then
    raise exception 'invalid_input: failure_code is mandatory for failed';
  end if;

  update kernel.refund
     set status = p_new_status,
         stripe_refund_ref = coalesce(v_row.stripe_refund_ref, p_stripe_refund_ref),
         updated_at = now()
   where refund_id = p_refund_id;      -- touches NO atom, NO public.* table

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (coalesce(auth.uid(),'00000000-0000-0000-0000-0000000000f1'), 'refund.state_sync', 'refund',
          p_refund_id, coalesce(p_failure_code, p_new_status),
          jsonb_build_object('status', v_row.status),
          jsonb_build_object('status', p_new_status));
  return jsonb_build_object('status','ok','refund_id', p_refund_id, 'new_status', p_new_status);
end;
$$;

-- ============================================================================
-- PART 12 — the OR-21 obligation pair (RPC §20.7.10/.11)
-- ============================================================================
create or replace function kernel.record_identity_obligation(
  p_debtor_identity_id uuid, p_origin_kind text, p_origin_ref uuid, p_stripe_dispute_ref text,
  p_amount_minor integer, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_refund kernel.refund%rowtype;
begin
  if p_origin_kind not in ('chargeback','refund_clawback') then
    raise exception 'invalid_input: bad origin_kind %', p_origin_kind;
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'invalid_input: bad_amount';
  end if;
  -- NO debtor-state precondition: recording against ERASED is the Q2 path
  -- working as designed. Native refund_clawback needs the refund fact.
  if p_origin_kind = 'refund_clawback' then
    select * into v_refund from kernel.refund where refund_id = p_origin_ref;
    if found and (v_refund.status <> 'succeeded' or v_refund.reason_code = 'buyer_request') then
      raise exception 'precondition_failed: a clawback records only a succeeded non-buyer_request refund';
    end if;
  end if;
  insert into kernel.identity_obligation
         (debtor_identity_id, origin_kind, origin_ref, stripe_dispute_ref, amount_minor)
  values (p_debtor_identity_id, p_origin_kind, p_origin_ref, p_stripe_dispute_ref, p_amount_minor)
  on conflict (origin_kind, origin_ref) do nothing
  returning obligation_id into v_id;
  if v_id is null then
    select o.obligation_id into v_id from kernel.identity_obligation o
     where o.origin_kind = p_origin_kind and o.origin_ref = p_origin_ref;
    return jsonb_build_object('status','noop_replay','obligation_id', v_id);
  end if;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (coalesce(auth.uid(),'00000000-0000-0000-0000-0000000000f1'), 'obligation.record', 'obligation',
          v_id, coalesce(p_reason_code, p_origin_kind));
  return jsonb_build_object('status','ok','obligation_id', v_id);
end;
$$;

create or replace function kernel.resolve_identity_obligation(
  p_obligation_id uuid, p_resolution text, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row kernel.identity_obligation%rowtype;
begin
  if not kernel.is_platform(array['platform_risk','platform_admin']) then
    raise exception 'insufficient_privilege: platform_risk or platform_admin required' using errcode = '42501';
  end if;
  if p_resolution not in ('recovered','written_off') then
    raise exception 'invalid_input: resolution must be recovered|written_off';
  end if;
  select * into v_row from kernel.identity_obligation where obligation_id = p_obligation_id for update;
  if not found then
    raise exception 'not_found: obligation %', p_obligation_id using errcode = 'P0002';
  end if;
  if v_row.status = p_resolution then
    return jsonb_build_object('status','noop_replay','obligation_id', p_obligation_id);
  end if;
  if v_row.status <> 'outstanding' then
    raise exception 'state_conflict: obligation % already % — terminals are exclusive', p_obligation_id, v_row.status;
  end if;
  update kernel.identity_obligation
     set status = p_resolution,
         resolution_reason_code = coalesce(p_reason_code, p_resolution),
         resolved_by = auth.uid(), resolved_at = now(), updated_at = now()
   where obligation_id = p_obligation_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (auth.uid(), 'obligation.resolve', 'obligation', p_obligation_id,
          coalesce(p_reason_code, p_resolution),
          jsonb_build_object('status','outstanding'), jsonb_build_object('status', p_resolution));
  return jsonb_build_object('status','ok','obligation_id', p_obligation_id);
end;
$$;

-- ============================================================================
-- PART 13 — venue.finalize_primary_order (RPC §6.3; SSCAS member #1 — authored
--   HERE, not 082: R2B/C111). The only function that turns money into tickets.
--   DEF — service_role only; "an authenticated grant here is the single
--   highest-severity migration defect available in this schema" (RLS §11).
-- ============================================================================
create or replace function venue.finalize_primary_order(
  p_order_id uuid, p_payment_id uuid, p_command_key text, p_instrument_fingerprint text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order   venue."order"%rowtype;
  v_pay     record;
  v_state   text;
  v_item    record;
  v_batch   record;
  v_hold    record;
  v_dec     integer;
  v_need    integer;
  v_key     uuid;
  v_event   uuid;
  v_venue   uuid;
  v_atoms   uuid[] := '{}';
  v_res     jsonb;
begin
  select * into v_order from venue."order" where order_id = p_order_id;
  if not found then
    raise exception 'not_found: order %', p_order_id using errcode = 'P0002';
  end if;

  -- E-23 (085 arm), the F-6/E-8 defensive twin: an ERASED buyer acquires
  -- NOTHING — is_deletion_pending returns FALSE for ERASED and cannot carry
  -- this refusal. DELETION_PENDING COMPLETES (F-1 tests the caller — this is
  -- the service_role money path; 16b preserves mid-flight money processing).
  select ie.deletion_state into v_state
    from kernel.identity_ext ie where ie.identity_id = v_order.buyer_id;
  if v_state = 'ERASED' then
    raise exception 'precondition_failed: buyer identity is erased — no acquisition';
  end if;

  -- C35: the payment IS the authority — verified, succeeded, and the buyer's.
  select p.buyer_id, p.total, p.status into v_pay from public.payments p where p.id = p_payment_id;
  if not found then
    raise exception 'payment_unverified: payment % not found', p_payment_id;
  end if;
  if v_pay.status <> 'succeeded' then
    raise exception 'payment_unverified: payment % is %', p_payment_id, v_pay.status;
  end if;
  if v_pay.buyer_id <> v_order.buyer_id then
    raise exception 'payment_unverified: payment buyer does not match order buyer';
  end if;
  -- the payment must at least COVER the order (R1 P1 — a $1 charge cannot
  -- finalize a $500 order; the link ledger must not self-certify a mismatch).
  if v_pay.total < v_order.total_minor then
    raise exception 'payment_unverified: payment % (% minor) does not cover order % (% minor)',
      p_payment_id, v_pay.total, p_order_id, v_order.total_minor;
  end if;
  -- a payment already carrying a refund is not a finalize target (R6 P2 — a
  -- delayed webhook must not mint tickets for money that was refunded).
  if exists (select 1 from kernel.refund r where r.payment_id = p_payment_id and r.status <> 'failed') then
    raise exception 'payment_unverified: payment % already carries a refund', p_payment_id;
  end if;

  -- rank 1: the Event/Session lock (also serializes the mint's serial draw and
  -- excludes update_event_session's schedule guard — E-46(a)).
  perform 1 from catalog.event_session s where s.session_id = v_order.event_session_id for update;
  select s.event_id into v_event from catalog.event_session s where s.session_id = v_order.event_session_id;
  select e.venue_id into v_venue from catalog.event e where e.event_id = v_event;

  -- signing-key resolution (§7.1): the activation-boundary predicate, most
  -- specific scope first. NO key ⇒ fail closed (the mint would refuse anyway;
  -- resolving here yields the cleaner token at the contracted boundary).
  select k.key_id into v_key
    from kernel.signing_key k
   where k.status = 'active'
     and (k.not_after is null or k.not_after > now()) and k.not_before <= now()
     and (   (k.scope = 'per_event' and k.event_id = v_event)
          or (k.scope = 'per_venue' and k.venue_id = v_venue)
          or (k.scope = 'global'))
   order by case k.scope when 'per_event' then 1 when 'per_venue' then 2 else 3 end
   limit 1;
  if v_key is null then
    raise exception 'precondition_failed: no_active_signing_key — an active signing key must resolve for the event scope before any atom is minted';
  end if;

  -- rank 3: the order — re-check state UNDER the lock; replay short-circuits.
  select * into v_order from venue."order" where order_id = p_order_id for update;
  if v_order.status = 'paid' then
    select coalesce(array_agg(t.ticket_atom_id order by t.ticket_atom_id), '{}') into v_atoms
      from kernel.tickets t
      join kernel.ticket_ownership_log l1
        on l1.ticket_atom_id = t.ticket_atom_id and l1.sequence = 1
     where l1.cause_ref in (select oi.id from venue.order_item oi where oi.order_id = p_order_id);
    return jsonb_build_object('status','idempotency_replay','atom_ids', to_jsonb(v_atoms),
                              'order_status','paid');
  end if;
  if v_order.status <> 'pending' then
    raise exception 'precondition_failed: order % is % — only a pending order finalizes', p_order_id, v_order.status;
  end if;

  -- DETERMINISTIC batch pre-lock (R6 P1): resolve every item's batch, then take
  -- the batch locks ascending by batch_id BEFORE any per-item work, so two
  -- concurrent finalizes over the same batch set can never AB-BA deadlock.
  -- Batch attribution is HEURISTIC (E-58): 082's checkout persists no order->hold
  -- linkage on the immutable order_item, so the batch is named by the buyer's
  -- reservation for this tt/session, preferring an ACTIVE unexpired hold; a
  -- future package that persists hold_ids on the order discharges the heuristic.
  perform 1 from venue.inventory_batch b
   where b.batch_id in (
     select distinct (
       select b2.batch_id
         from venue.inventory_hold h
         join venue.inventory_batch b2 on b2.batch_id = h.batch_id
        where h.identity_id = v_order.buyer_id
          and b2.ticket_type_id = oi.ticket_type_id
          and b2.event_session_id = v_order.event_session_id
        order by (h.status = 'active' and h.expires_at > now()) desc, h.created_at desc
        limit 1)
       from venue.order_item oi where oi.order_id = p_order_id)
   order by b.batch_id
   for update;

  -- per item: the E-40 hold re-read, the E-47(b) ordering (held -= live-backed
  -- BEFORE the mint's sold += q, same txn), then the mint. Batches already locked.
  for v_item in
    select oi.id, oi.ticket_type_id, oi.quantity
      from venue.order_item oi where oi.order_id = p_order_id order by oi.id
  loop
    select b.* into v_batch
      from venue.inventory_hold h
      join venue.inventory_batch b on b.batch_id = h.batch_id
     where h.identity_id = v_order.buyer_id
       and b.ticket_type_id = v_item.ticket_type_id
       and b.event_session_id = v_order.event_session_id
     order by (h.status = 'active' and h.expires_at > now()) desc, h.created_at desc
     limit 1;
    if v_batch.batch_id is null then
      raise exception 'precondition_failed: no reservation names a batch for item % (checkout guarantees coverage)', v_item.id;
    end if;

    -- E-40: only LIVE holds back the held-decrement — a blind held -= q on a
    -- swept hold double-decrements. Convert ALL of the buyer's active-unexpired
    -- holds on this batch WHOLE; held -= their sum (any over-held remainder
    -- returns to free capacity). The un-backed part draws free capacity (C27).
    v_dec := 0; v_need := v_item.quantity;
    for v_hold in
      select h.hold_id, h.quantity
        from venue.inventory_hold h
       where h.identity_id = v_order.buyer_id and h.batch_id = v_batch.batch_id
         and h.status = 'active' and h.expires_at > now()
       order by h.hold_id
       for update
    loop
      update venue.inventory_hold set status = 'converted', updated_at = now()
       where hold_id = v_hold.hold_id;
      v_dec := v_dec + v_hold.quantity;
    end loop;

    -- clean oversell token BEFORE the arithmetic; C27 remains the backstop.
    if (v_batch.capacity - (v_batch.held - v_dec) - v_batch.sold) < v_item.quantity then
      raise exception 'oversell_rejected: item % needs % — batch % has no headroom', v_item.id, v_item.quantity, v_batch.batch_id;
    end if;
    if v_dec > 0 then
      update venue.inventory_batch set held = held - v_dec, updated_at = now()
       where batch_id = v_batch.batch_id;                       -- E-47(b): BEFORE the mint's sold += q
    end if;

    v_res := kernel.issue_ticket_atoms(
      jsonb_build_object(
        'session_id', v_order.event_session_id, 'org_id', v_order.org_id,
        'ticket_type_id', v_item.ticket_type_id, 'batch_id', v_batch.batch_id,
        'owner_id', v_order.buyer_id, 'quantity', v_item.quantity,
        'cause', 'issue', 'cause_ref', v_item.id, 'signing_key_id', v_key),
      p_command_key || ':' || v_item.id::text);
    v_atoms := v_atoms || (select coalesce(array_agg(x.v::uuid), '{}')
                             from jsonb_array_elements_text(v_res -> 'atom_ids') x(v));
  end loop;

  update venue."order" set status = 'paid', updated_at = now() where order_id = p_order_id;

  -- the payment link — INSERTED BEFORE the resolver call (load-bearing: §17.14's
  -- read sees the fingerprint in-snapshot; SEAM-2a bars it as a parameter).
  insert into kernel.payment_native (payment_id, order_id, amount_minor, instrument_fingerprint)
  values (p_payment_id, p_order_id, v_order.total_minor, p_instrument_fingerprint);

  -- attribution freezes at order-paid (the money event). The stub NEVER raises
  -- (§17.14 — a raise here would roll back the money and the tickets).
  perform venue.resolve_order_attribution(p_order_id);

  return jsonb_build_object('status','ok','atom_ids', to_jsonb(v_atoms), 'order_status','paid');
exception when unique_violation then
  -- concurrent webhook redelivery: the winner finalized; return its atom set.
  select * into v_order from venue."order" where order_id = p_order_id;
  if v_order.status = 'paid' then
    select coalesce(array_agg(t.ticket_atom_id order by t.ticket_atom_id), '{}') into v_atoms
      from kernel.tickets t
      join kernel.ticket_ownership_log l1
        on l1.ticket_atom_id = t.ticket_atom_id and l1.sequence = 1
     where l1.cause_ref in (select oi.id from venue.order_item oi where oi.order_id = p_order_id);
    return jsonb_build_object('status','idempotency_replay','atom_ids', to_jsonb(v_atoms),
                              'order_status','paid');
  end if;
  raise;
end;
$$;

-- ============================================================================
-- PART 14 — grants (076 discipline: every new function's default PUBLIC
--   EXECUTE is revoked explicitly; targeted grants only). PFA-15 + PFA-21.
-- ============================================================================
-- PFA-15 (owner-signed): the venue schema opens to service_role — USAGE ONLY.
-- Makes cancel_pending_order (082) + finalize_primary_order (here) reachable
-- through the immutable 076 wall. No table/DML grants; anon unchanged.
grant usage on schema venue to service_role;
-- PFA-21 (owner-signed): the kernel schema opens to service_role — USAGE ONLY.
-- Makes the state-sync pair + record_identity_obligation reachable. No
-- table/DML grants; anon unchanged; catalog untouched.
grant usage on schema kernel to service_role;

do $$
declare
  v_fn text;
  v_all constant text[] := array[
    'kernel.void_ticket_atom(uuid, uuid, text)',
    'kernel.refund_primary_order(uuid, integer, text, text)',
    'kernel.admin_refund(uuid, uuid[], integer, text, text)',
    'kernel.force_void_ticket(uuid, text, text)',
    'kernel.hold_payout(uuid, text, text)',
    'kernel.release_payout(uuid, text)',
    'kernel.request_order_refund(uuid, uuid[], integer, text, text)',
    'kernel.approve_refund_request(uuid, text, text, text)',
    'kernel.cancel_refund_request(uuid, text, text)',
    'kernel.sweep_expired_refund_requests()',
    'kernel.list_org_payouts(uuid, uuid, jsonb, text)',
    'kernel.list_org_refunds(uuid, uuid, jsonb, text)',
    'kernel.list_approval_requests(uuid, jsonb, text)',
    'kernel.record_money_denial(text, text, uuid, text)',
    'kernel.set_org_payout_destination(uuid, text, text, text)',
    'kernel.mark_payout_transfer_state(uuid, text, text, text, text)',
    'kernel.mark_refund_state(uuid, text, text, text, text)',
    'kernel.record_identity_obligation(uuid, text, uuid, text, integer, text, text)',
    'kernel.resolve_identity_obligation(uuid, text, text, text)',
    'venue.finalize_primary_order(uuid, uuid, text, text)',
    'venue.resolve_order_attribution(uuid)',
    'venue.on_payout_settled(uuid)',
    'market.on_atom_voided(uuid, uuid, text)'
    -- deletion_blockers_money / has_outstanding_obligations / on_deletion_q5_release
    -- keep their 077 grants (CREATE OR REPLACE preserves ACLs).
  ];
  -- caller-authorized (EDGE-FRONTED, EDGE-CALLER-JWT verbs + reads + the R-28
  -- denial witness). refund_primary_order is NOT here — PFA-23 makes it EXEC DEF.
  v_auth constant text[] := array[
    'kernel.request_order_refund(uuid, uuid[], integer, text, text)',
    'kernel.approve_refund_request(uuid, text, text, text)',
    'kernel.cancel_refund_request(uuid, text, text)',
    'kernel.list_org_payouts(uuid, uuid, jsonb, text)',
    'kernel.list_org_refunds(uuid, uuid, jsonb, text)',
    'kernel.list_approval_requests(uuid, jsonb, text)',
    'kernel.record_money_denial(text, text, uuid, text)',
    'kernel.set_org_payout_destination(uuid, text, text, text)',
    'kernel.admin_refund(uuid, uuid[], integer, text, text)',
    'kernel.force_void_ticket(uuid, text, text)',
    'kernel.hold_payout(uuid, text, text)',
    'kernel.release_payout(uuid, text)',
    'kernel.resolve_identity_obligation(uuid, text, text, text)'
  ];
  -- machine-only (service_role edge sessions; PFA-15/PFA-21 deliver USAGE).
  -- refund_primary_order (PFA-23, §11.4 EXEC DEF): the refund-execute edge (as
  -- service_role, forwarding the platform JWT for the direct arm) + definer->definer.
  v_svc constant text[] := array[
    'venue.finalize_primary_order(uuid, uuid, text, text)',
    'kernel.refund_primary_order(uuid, integer, text, text)',
    'kernel.sweep_expired_refund_requests()',
    'kernel.mark_payout_transfer_state(uuid, text, text, text, text)',
    'kernel.mark_refund_state(uuid, text, text, text, text)',
    'kernel.record_identity_obligation(uuid, text, uuid, text, integer, text, text)'
  ];
  -- R2 P1 / PFA-21 disclosure (E-59): 085's kernel USAGE grant makes RUNTIME-live
  -- the pre-existing service_role EXECUTE grants that 077/081/082/083 authored
  -- (the deletion machinery, the sweeps, the mint/wallet DEF set). Those grants
  -- are the ESTABLISHED machine-caller boundary — asserted by A30/A41 and the F3
  -- register — so 085 does NOT narrow them (a revoke here would contradict the
  -- frozen ACL). The activation is accepted and disclosed; issue_ticket_atoms'
  -- comp/door/import service_role path stays darkness-gated (re-verify at
  -- native-issuance activation — forward obligation).
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
  -- R-28 hard edge: the denial witness must NEVER be service_role-reachable.
  execute 'revoke execute on function kernel.record_money_denial(text, text, uuid, text) from service_role';
end $$;

-- ============================================================================
-- PART 15 — the 085 cron entry (P0-1: the refund-request TTL tick, 2-minute).
-- ============================================================================
select cron.schedule('sweep-expired-refund-requests', '*/2 * * * *',
                     $$select kernel.sweep_expired_refund_requests();$$);

-- ============================================================================
-- PART 16 — PFA-22: the dedicated BP-12 operand, seeded NULL / owner-unset.
--   NULL is fail-closed ONLY when a qualifying candidate order exists; the key
--   controls DELETION SAFETY only — never refund eligibility.
-- ============================================================================
insert into catalog.platform_config (key, version, value, visibility)
values ('deletion.refund_possible_window_hours', 1, 'null'::jsonb, 'restricted')
on conflict do nothing;

commit;

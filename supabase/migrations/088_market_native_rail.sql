-- ============================================================================
-- 088_market_native_rail.sql — Phase-2 package 088 (family J, phase J1).
-- Frozen sources: plan §8/088 · schema §0.9/§1.10b/§4.1-§4.5 · RPC §1.2/§1.4/§4.4/
--   §7.2/§7.4/§8.1-§8.3/§12.2-§12.3/§17.10a/§20.7.13-§20.7.15/§20.8.1-§20.8.12/
--   §20.11.1/§20.11.3 · RLS §7.10b/§10.1-§10.5/§11 · OR-11 (no native auctions in
--   MVP) · OR-17 (F-2/F-3/F-4 clauses) · OR-22 (buy-now set) · OR-24 (R-40) ·
--   PFA-13 (unlock re-arm) · PFA-29 (O-C: the royalty seam carries royalty AND
--   chargeback candidates) · PFA-30 (the 3-way split PARKED fail-closed) ·
--   PFA-31 (dispute resolution dual control PARKED fail-closed) · E-22 (atom
--   FOR UPDATE across head + ledger) · E-23 (ERASED counterparties refused) ·
--   E-73/E-90 (sign-derived buckets; royalty is a POSITIVE venue earning).
-- The native resale rail is ARCHITECTURE-COMPLETE and FEATURE-DARK:
--   feature.native_resale_enabled = false (078 seed) gates every client entry;
--   native issuance is dark, so no native atom exists to list; the split and the
--   dispute resolution are parked by owner ruling. Nothing here turns a dark
--   object into a live money rail.
-- Deps: 076, 077, 078, 079, 081, 085, 086, 087.
-- Rollback posture: CLEAN-WHILE-EMPTY for the market tables; FORWARD-FIX from
--   first row for market_sale and kernel.dispute_native (a chargeback ledger
--   inside a live Stripe evidence window is permanent evidence).
-- ============================================================================

begin;

-- ============================================================================
-- PART 1 — the market tables (schema §4.1-§4.5) + kernel.dispute_native (§1.10b)
-- ============================================================================

-- 4.1 listing_native — a native resale offer that LOCKS a ticket atom.
--   listing_mode / reason_code are written by RPC §20.8.1/§20.8.2 (recorded
--   E-91: absent from §4.1's column list). status: draft·active·reserved·sold·
--   cancelled·expired. The policy snapshot (id + version) is immutable for the
--   listing's life (O3/C11).
create table if not exists market.listing_native (
  listing_id              uuid primary key default gen_random_uuid(),
  ticket_atom_id          uuid not null references kernel.tickets(ticket_atom_id) on delete restrict,
  seller_id               uuid not null references auth.users(id) on delete restrict,
  event_session_id        uuid references catalog.event_session(session_id) on delete restrict,
  inventory_kind          text not null default 'native' check (inventory_kind in ('native')),
  listing_mode            text not null check (listing_mode in ('buy_now','auction','offer')),
  price_minor             integer not null check (price_minor > 0),
  currency                text not null default 'USD',
  resale_policy_id        uuid references catalog.resale_policy(policy_id) on delete restrict,
  resale_policy_version   integer not null,
  status                  text not null default 'draft'
                          check (status in ('draft','active','reserved','sold','cancelled','expired')),
  reason_code             text,
  command_idempotency_key text not null,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  constraint listing_native_policy_snapshot_ck check (resale_policy_id is not null and resale_policy_version >= 1),
  constraint listing_native_seller_command_uq unique (seller_id, command_idempotency_key)   -- C16
);
-- an atom is listed ONCE at a time (CDM §3 "1:0..1 native") — the index, never a NOT EXISTS
create unique index if not exists listing_native_atom_active_uq on market.listing_native (ticket_atom_id) where status = 'active';
create index if not exists listing_native_session_idx on market.listing_native (event_session_id);
create index if not exists listing_native_seller_status_idx on market.listing_native (seller_id, status);
drop trigger if exists tg_listing_native_set_updated_at on market.listing_native;
create trigger tg_listing_native_set_updated_at before update on market.listing_native
  for each row execute function kernel.set_updated_at();

-- 4.2 auction — MVP-DORMANT substrate (OR-11): create_auction rejects every
--   native listing, so this table can hold no rows in MVP.
create table if not exists market.auction (
  auction_id                uuid primary key default gen_random_uuid(),
  listing_id                uuid not null references market.listing_native(listing_id) on delete restrict,
  reserve_minor             integer check (reserve_minor is null or reserve_minor >= 0),
  min_increment_minor       integer not null check (min_increment_minor > 0),
  anti_snipe_seconds        integer not null default 0 check (anti_snipe_seconds >= 0),
  deposit_mode              boolean not null default false,
  current_highest_bid_minor integer,
  ends_at                   timestamptz not null,
  status                    text not null default 'active' check (status in ('active','ended','cancelled')),
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  constraint auction_listing_uq unique (listing_id)
);
create index if not exists auction_status_ends_idx on market.auction (status, ends_at);
drop trigger if exists tg_auction_set_updated_at on market.auction;
create trigger tg_auction_set_updated_at before update on market.auction
  for each row execute function kernel.set_updated_at();

-- 4.3 offer — a stated intent; moves no money, takes no hold, locks no atom.
create table if not exists market.offer (
  offer_id                uuid primary key default gen_random_uuid(),
  listing_id              uuid not null references market.listing_native(listing_id) on delete restrict,
  buyer_id                uuid not null references auth.users(id) on delete restrict,
  amount_minor            integer not null check (amount_minor > 0),
  currency                text not null default 'USD',
  status                  text not null default 'pending'
                          check (status in ('pending','accepted','declined','expired','withdrawn')),
  expires_at              timestamptz,
  command_idempotency_key text not null,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  constraint offer_buyer_command_uq unique (buyer_id, command_idempotency_key)   -- C16
);
create index if not exists offer_listing_status_idx on market.offer (listing_id, status);
create index if not exists offer_buyer_status_idx on market.offer (buyer_id, status);
drop trigger if exists tg_offer_set_updated_at on market.offer;
create trigger tg_offer_set_updated_at before update on market.offer
  for each row execute function kernel.set_updated_at();

-- 4.4 market_sale — the consummation fact (SoT; C26 compensate-XOR-complete).
--   The split columns are NULLABLE together: PFA-30 parks every split writer, so
--   no 088 path stores a split; when a ratified policy lands, the three must sum
--   EXACTLY to price_minor (the rounding bearer absorbs the residual by
--   construction — the residual never leaves the triple).
create table if not exists market.market_sale (
  sale_id                 uuid primary key default gen_random_uuid(),
  listing_id              uuid not null references market.listing_native(listing_id) on delete restrict,
  ticket_atom_id          uuid not null references kernel.tickets(ticket_atom_id) on delete restrict,
  buyer_id                uuid not null references auth.users(id) on delete restrict,
  seller_id               uuid not null references auth.users(id) on delete restrict,
  price_minor             integer not null check (price_minor > 0),
  currency                text not null default 'USD',
  platform_fee_minor      integer,
  venue_royalty_minor     integer,
  seller_proceeds_minor   integer,
  payment_id              uuid references public.payments(id) on delete restrict,
  terminal_state          text not null default 'pending' check (terminal_state in ('pending','completed','compensated')),
  sale_state              text not null default 'initiated'
                          check (sale_state in ('initiated','paid_pending_transfer','settled','cancelled')),
  paid_pending_since      timestamptz,
  reservation_expires_at  timestamptz,
  payment_intent_ref      text,
  command_idempotency_key text not null,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  constraint market_sale_buyer_command_uq unique (buyer_id, command_idempotency_key),   -- C16
  -- num_nulls first: a PARTIAL split must be unstorable, and `NULL >= 0` is NULL
  -- (a CHECK passes on NULL) — the three-way disjunction alone admits one NULL.
  constraint market_sale_split_ck check (
    num_nulls(platform_fee_minor, venue_royalty_minor, seller_proceeds_minor) in (0, 3)
    and (platform_fee_minor is null
         or (platform_fee_minor >= 0 and venue_royalty_minor >= 0 and seller_proceeds_minor >= 0
             and platform_fee_minor + venue_royalty_minor + seller_proceeds_minor = price_minor))),
  -- a cancelled sale is a never-paid checkout: it can hold no dwell clock and no terminal.
  constraint market_sale_cancelled_ck check (sale_state <> 'cancelled' or (terminal_state = 'pending' and paid_pending_since is null))
);
create index if not exists market_sale_listing_idx on market.market_sale (listing_id);
create index if not exists market_sale_atom_idx on market.market_sale (ticket_atom_id);
create index if not exists market_sale_seller_idx on market.market_sale (seller_id);
create index if not exists market_sale_buyer_idx on market.market_sale (buyer_id);
-- the C25 sweep hot-path (terminal conjunct keeps completed/compensated rows out — red-team F-2b)
create index if not exists market_sale_paid_pending_idx on market.market_sale (paid_pending_since)
  where sale_state = 'paid_pending_transfer' and terminal_state = 'pending';
-- at most ONE live checkout per listing — the index, not a NOT EXISTS (R-37/OR-22)
create unique index if not exists market_sale_listing_initiated_uq on market.market_sale (listing_id) where sale_state = 'initiated';
create index if not exists market_sale_reservation_idx on market.market_sale (reservation_expires_at) where sale_state = 'initiated';
-- one succeeded payment settles ONE sale (C35 / R-34; §20.8.7 write-once) — the structural backstop (E-105)
create unique index if not exists market_sale_payment_uq on market.market_sale (payment_id) where payment_id is not null;
drop trigger if exists tg_market_sale_set_updated_at on market.market_sale;
create trigger tg_market_sale_set_updated_at before update on market.market_sale
  for each row execute function kernel.set_updated_at();

-- 4.5 p2p_transfer — request/accept wrapper over the kernel transfer engine.
create table if not exists market.p2p_transfer (
  transfer_id             uuid primary key default gen_random_uuid(),
  ticket_atom_id          uuid not null references kernel.tickets(ticket_atom_id) on delete restrict,
  from_identity           uuid not null references auth.users(id) on delete restrict,
  to_identity             uuid references auth.users(id) on delete restrict,
  to_handle               text,
  price_minor             integer check (price_minor is null or price_minor > 0),
  currency                text not null default 'USD',
  status                  text not null default 'initiated'
                          check (status in ('initiated','accepted','completed','declined','expired','cancelled')),
  reason_code             text,
  expires_at              timestamptz,
  command_idempotency_key text not null,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  constraint p2p_transfer_from_command_uq unique (from_identity, command_idempotency_key),   -- C16
  constraint p2p_transfer_addressee_ck check (to_identity is not null or to_handle is not null)
);
create unique index if not exists p2p_transfer_atom_initiated_uq on market.p2p_transfer (ticket_atom_id) where status = 'initiated';
create index if not exists p2p_transfer_to_status_idx on market.p2p_transfer (to_identity, status);
create index if not exists p2p_transfer_from_status_idx on market.p2p_transfer (from_identity, status);
drop trigger if exists tg_p2p_transfer_set_updated_at on market.p2p_transfer;
create trigger tg_p2p_transfer_set_updated_at before update on market.p2p_transfer
  for each row execute function kernel.set_updated_at();

-- 1.10b kernel.dispute_native — the native chargeback record + freeze operand
--   (R-40). Records, freezes, releases; moves NO money. payment_id FKs the frozen
--   public.payments row DIRECTLY (recordable before any payment_native link).
--   Terminal set {won, lost, warning_closed, charge_refunded}; terminal absorbing.
--   No DELETE ever (GP-2). Deny-all (RLS §7.10b).
create table if not exists kernel.dispute_native (
  dispute_id              uuid primary key default gen_random_uuid(),
  stripe_dispute_ref      text not null,
  stripe_charge_ref       text not null,
  stripe_pi_ref           text,
  payment_id              uuid not null references public.payments(id) on delete restrict,
  amount_minor            integer not null check (amount_minor >= 0),
  currency                text not null default 'USD',
  reason                  text not null,
  evidence_due_at         timestamptz,
  status                  text not null check (status in (
                            'warning_needs_response','warning_under_review','warning_closed',
                            'needs_response','under_review','won','lost','charge_refunded')),
  resolution_outcome      text check (resolution_outcome is null or resolution_outcome in ('seller_win','buyer_win','partial_refund')),
  resolution_reason_code  text,
  resolved_by             uuid references auth.users(id) on delete restrict,   -- ODR16 SPEC-SILENT class → RESTRICT, TOMBSTONED (E-93)
  resolved_at             timestamptz,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  constraint dispute_native_stripe_ref_uq unique (stripe_dispute_ref),
  -- the resolution quadruple: all four NULL ⇔ none set
  constraint dispute_native_resolution_pairing_ck check (
    (resolution_outcome is null and resolution_reason_code is null and resolved_by is null and resolved_at is null)
    or (resolution_outcome is not null and resolution_reason_code is not null and resolved_by is not null and resolved_at is not null))
);
-- the open-set index IS the BP-7 native-twin operand
create index if not exists dispute_native_open_idx on kernel.dispute_native (created_at desc)
  where status not in ('won','lost','warning_closed','charge_refunded');
create index if not exists dispute_native_payment_idx on kernel.dispute_native (payment_id);
drop trigger if exists tg_dispute_native_set_updated_at on kernel.dispute_native;
create trigger tg_dispute_native_set_updated_at before update on kernel.dispute_native
  for each row execute function kernel.set_updated_at();

-- ── grants + RLS ────────────────────────────────────────────────────────────
alter table market.listing_native enable row level security;
alter table market.auction        enable row level security;
alter table market.offer          enable row level security;
alter table market.market_sale    enable row level security;
alter table market.p2p_transfer   enable row level security;
alter table kernel.dispute_native enable row level security;
revoke all on market.listing_native, market.auction, market.offer, market.market_sale, market.p2p_transfer from public, anon, authenticated;
revoke all on kernel.dispute_native from public, anon, authenticated;
revoke delete on kernel.dispute_native from service_role;   -- no DELETE ever (GP-2)

-- listing_native: discovery columns to authenticated (no idempotency key ever;
-- seller_id resolves to a display through the 068 public-safe profile columns).
-- anon holds NO USAGE on any walled schema (the 076 wall) — no anon grant is
-- written here (a dormant grant would only invite a later accidental USAGE);
-- anonymous discovery, if ever offered, is a wall decision, not 088's. The
-- public arm surfaces ONLY while the rail's flag is ON (plan §8/088 Tests;
-- NULL ⇒ dark, X-12); the owner arm is unconditional.
grant select (listing_id, ticket_atom_id, seller_id, event_session_id, inventory_kind, listing_mode, price_minor, currency,
              resale_policy_id, resale_policy_version, status, reason_code, created_at, updated_at) on market.listing_native to authenticated;
drop policy if exists market_listing_native_sel_public on market.listing_native;
create policy market_listing_native_sel_public on market.listing_native for select to authenticated
  using (status in ('active','reserved')
         and coalesce((select (c.value #>> '{}')::boolean from catalog.platform_config c
                        where c.key = 'feature.native_resale_enabled' order by c.version desc limit 1), false));
drop policy if exists market_listing_native_sel_owner on market.listing_native;
create policy market_listing_native_sel_owner on market.listing_native for select to authenticated
  using (seller_id = auth.uid());

-- auction: read of active auctions (dormant substrate; authenticated only — the wall)
grant select on market.auction to authenticated;
drop policy if exists market_auction_sel_public on market.auction;
create policy market_auction_sel_public on market.auction for select to authenticated
  using (status = 'active');

-- offer: buyer's own offers + the listing seller's offers-on-own-listing
grant select (offer_id, listing_id, buyer_id, amount_minor, currency, status, expires_at, created_at, updated_at) on market.offer to authenticated;
drop policy if exists market_offer_sel_owner on market.offer;
create policy market_offer_sel_owner on market.offer for select to authenticated
  using (buyer_id = auth.uid()
         or exists (select 1 from market.listing_native l where l.listing_id = market.offer.listing_id and l.seller_id = auth.uid()));

-- market_sale: ZERO client policies (RLS §16.10) — reads only via get_market_sale_status.
-- p2p_transfer: owner-scoped (sender or resolved recipient)
grant select (transfer_id, ticket_atom_id, from_identity, to_identity, to_handle, price_minor, currency, status, reason_code, expires_at, created_at, updated_at) on market.p2p_transfer to authenticated;
drop policy if exists market_p2p_transfer_sel_owner on market.p2p_transfer;
create policy market_p2p_transfer_sel_owner on market.p2p_transfer for select to authenticated
  using (from_identity = auth.uid() or to_identity = auth.uid());

-- ============================================================================
-- PART 2 — the R-40 resale_state overlay label (verify-only). Plan §8/088 asks
--   for a DROP/ADD CHECK pair adding 'dispute_hold' on kernel.tickets and
--   venue.door_manifest_entry; the 079 and 086 bytes ALREADY carry the five-label
--   form, so 088 PROVES it rather than re-adding it (E-92) — a fail-loud check.
-- ============================================================================
do $$
begin
  if not exists (select 1 from pg_constraint c where c.conrelid = 'kernel.tickets'::regclass and c.contype = 'c'
                  and pg_get_constraintdef(c.oid) like '%resale_state%' and pg_get_constraintdef(c.oid) like '%dispute_hold%') then
    raise exception 'kernel.tickets.resale_state CHECK lacks dispute_hold — the 079 bytes changed (R-40 precondition)';
  end if;
  if not exists (select 1 from pg_constraint c where c.conrelid = 'venue.door_manifest_entry'::regclass and c.contype = 'c'
                  and pg_get_constraintdef(c.oid) like '%resale_state%' and pg_get_constraintdef(c.oid) like '%dispute_hold%') then
    raise exception 'venue.door_manifest_entry.resale_state CHECK lacks dispute_hold — the 086 bytes changed (R-40 precondition)';
  end if;
end $$;

-- ============================================================================
-- PART 3 — the SEAM-2 bodies (body-only CREATE OR REPLACE; every signature,
--   parameter name and return type verbatim from its stub — SEAM-2a) + the
--   PFA-13 body-only replacement of kernel.unlock_ticket.
-- ============================================================================

-- 3a — kernel.settlement_royalty_lines (RPC §20.11.1; stub 087). PFA-29 / O-C:
--   THE 088 settlement-line-source seam — it returns BOTH 088-owned candidate
--   classes for the settlement being closed. Deterministic, NEVER raises (a raise
--   rolls back a settlement close). VOLATILE + a per-org TRANSACTION advisory lock
--   (E-104): two settlements of one org closing concurrently must not both pass
--   the NOT EXISTS dedupe — a STABLE body keeps the caller's statement snapshot
--   and cannot see a sibling close committed while it waited; the lock is released
--   at commit and the Gate-M cross-settlement unique (PFA-29 / §3.14.1) is the
--   structural successor.
--   ROYALTY ARM (E-90: a POSITIVE venue earning, credit +, lands in GROSS under
--     087's sign-derived buckets): completed native sales whose atom belongs to
--     the settlement's scope (event, or venue+period) and whose stored
--     venue_royalty_minor is present and > 0. PFA-30 stores NO split, so this
--     arm emits nothing until the split policy is ratified — no royalty is
--     guessed. A sale already lined by any settlement is not offered again.
--   CHARGEBACK ARM (RPC §10.2 arm, transcribed here): every kernel.dispute_native
--     row terminal lost/charge_refunded whose disputed payment settled to THIS
--     org — the primary-order arm (payment_native.order_id → venue.order.org_id)
--     — with amount_minor > 0, as an append-only NEGATIVE candidate
--     (cause='chargeback', cause_ref = dispute_id) in the org's NEXT settlement
--     to close; never offered twice (NOT EXISTS over settlement_line under the
--     caller's settlement lock — PFA-29). Native-resale (sale-arm) disputes are
--     NOT booked against the org: the org held only the royalty share and org
--     debt on the resale rail is BP-11/C31 Gate-M (§20.7.14) — recorded E-94.
create or replace function kernel.settlement_royalty_lines(p_settlement_id uuid)
returns setof kernel.settlement_line_candidate
language plpgsql volatile security definer set search_path = ''
as $$
declare v_org uuid;
begin
  select st.org_id into v_org from venue.settlement st where st.settlement_id = p_settlement_id;
  if v_org is null then return; end if;
  -- E-104: serialize this org's candidate emission for the calling transaction
  -- (released at commit). After the wait, every query below takes a fresh
  -- snapshot (VOLATILE), so a line committed by the sibling close is SEEN.
  perform pg_advisory_xact_lock(hashtext('settlement.seam.org:' || v_org::text));
  return query
  with s as (
    select st.settlement_id, st.org_id, st.venue_id, st.event_id, st.period_start, st.period_end, st.currency
      from venue.settlement st where st.settlement_id = p_settlement_id
  ),
  royalty as (
    select 'market_sale'::text as cause, ms.sale_id as cause_ref,
           ms.venue_royalty_minor::bigint as amount_minor, ms.currency, 'organization'::text as payee_kind, s.org_id as payee_id
      from s
      join market.market_sale ms on ms.terminal_state = 'completed' and ms.venue_royalty_minor is not null and ms.venue_royalty_minor > 0
      join kernel.tickets t on t.ticket_atom_id = ms.ticket_atom_id and t.org_id = s.org_id
      join catalog.event_session es on es.session_id = t.event_session_id
      join catalog.event e on e.event_id = es.event_id
     where ms.currency = s.currency
       and ((s.event_id is not null and e.event_id = s.event_id)
            or (s.event_id is null and e.venue_id = s.venue_id
                and (s.period_start is null or es.starts_at >= s.period_start)
                and (s.period_end is null or es.starts_at < s.period_end)))
       and not exists (select 1 from venue.settlement_line l where l.cause = 'market_sale' and l.cause_ref = ms.sale_id)
  ),
  chargeback as (
    select 'chargeback'::text as cause, d.dispute_id as cause_ref,
           (-d.amount_minor)::bigint as amount_minor, d.currency, 'organization'::text as payee_kind, s.org_id as payee_id
      from s
      join kernel.dispute_native d on d.status in ('lost','charge_refunded') and d.amount_minor > 0
      join kernel.payment_native pn on pn.payment_id = d.payment_id and pn.order_id is not null
      join venue."order" o on o.order_id = pn.order_id and o.org_id = s.org_id
     where d.currency = s.currency
       and not exists (select 1 from venue.settlement_line l where l.cause = 'chargeback' and l.cause_ref = d.dispute_id)
  )
  select * from royalty
  union all
  select * from chargeback
  order by 1, 2;
end;
$$;

-- 3b — market.on_atom_voided (RPC §20.11.3; stub 085). The C26 compensate arm:
--   the kernel calls this market-owned primitive BEFORE it takes the rank-5 atom
--   lock (T-RPC-SEAM-03). Locates the atom's LATEST non-cancelled sale under its
--   own FOR UPDATE (rank 4): pending → compensated; compensated → no-op;
--   COMPLETED → no-op (E-95: the void of a successfully-resold atom — an event
--   cancellation, a later refund — is a fact AFTER the consummation, and raising
--   here would abort catalog.cancel_event on every resold atom; the XOR holds
--   because a completed sale is never flipped). No sale → silent no-op.
create or replace function market.on_atom_voided(p_atom_id uuid, p_refund_id uuid, p_cause text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_sale market.market_sale%rowtype; v_sys constant uuid := '00000000-0000-0000-0000-0000000000f1';
begin
  -- EVERY non-terminal, non-cancelled sale on the atom (rank 4, before the caller's rank-5 atom lock).
  for v_sale in select * from market.market_sale ms
                 where ms.ticket_atom_id = p_atom_id and ms.sale_state <> 'cancelled' and ms.terminal_state = 'pending'
                 order by ms.created_at for update loop
    if v_sale.payment_id is null then
      -- an UNPAID reservation dies with the atom (a late payment then meets the cancelled arm: alert + reverse).
      update market.market_sale set sale_state = 'cancelled', updated_at = now() where sale_id = v_sale.sale_id;
      insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
      values (v_sys, 'market_sale.cancelled', 'market_sale', v_sale.sale_id, coalesce(p_cause, 'refund_void'),
              jsonb_build_object('atom_id', p_atom_id, 'refund_id', p_refund_id, 'reason', 'atom_voided_unpaid'));
    elsif exists (select 1 from kernel.refund r where r.payment_id = v_sale.payment_id and r.status <> 'failed') then
      -- the buyer's money carries a refund intent: the C26 compensate arm (compensated ⇔ refunded).
      update market.market_sale set terminal_state = 'compensated', updated_at = now() where sale_id = v_sale.sale_id;
      insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
      values (v_sys, 'market_sale.compensated', 'market_sale', v_sale.sale_id, coalesce(p_cause, 'refund_void'),
              jsonb_build_object('atom_id', p_atom_id, 'refund_id', p_refund_id));
    else
      -- PAID and NO refund for the buyer's payment: NEVER terminalize (money would be stranded
      -- behind a 'compensated' label nobody revisits). Leave pending; alert platform_risk.
      insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
      values (v_sys, 'market_sale.alert', 'market_sale', v_sale.sale_id, 'compensation_refund_missing',
              jsonb_build_object('atom_id', p_atom_id, 'refund_id', p_refund_id, 'payment_id', v_sale.payment_id, 'audience', 'platform_risk'));
    end if;
  end loop;
end;
$$;

-- 3c — market.on_door_freeze_engaged (RPC §17.10a; stub 086). The drain, in the
--   caller's (venue.open_door_manifest) transaction under its rank-1 session
--   lock: initiated p2p transfers → cancelled (reason door_freeze); active AND
--   reserved listings → cancelled (reason door_freeze) with their pending offers
--   withdrawn and any auction cancelled — EXCLUDING a listing whose sale is
--   paid_pending_transfer (money taken; §12.3 owns it — T-RPC-DOOR-12); the
--   drained atoms are released through kernel.unlock_ticket (which re-arms
--   dispute_hold where a dispute is open — PFA-13). No ledger row, no
--   credential bump (C43-exempt).
create or replace function market.on_door_freeze_engaged(p_event_session_id uuid, p_cause_ref uuid)
returns table(drained_transfers integer, drained_listings integer, atoms_unlocked integer)
language plpgsql security definer set search_path = ''
as $$
declare v_r record; v_t integer := 0; v_l integer := 0; v_u integer := 0; v_key text := 'door_freeze:' || p_cause_ref::text;
begin
  for v_r in select p.transfer_id, p.ticket_atom_id from market.p2p_transfer p
              join kernel.tickets t on t.ticket_atom_id = p.ticket_atom_id
             where t.event_session_id = p_event_session_id and p.status = 'initiated'
             order by p.ticket_atom_id for update of p loop
    update market.p2p_transfer set status = 'cancelled', reason_code = 'door_freeze', updated_at = now() where transfer_id = v_r.transfer_id;
    perform kernel.unlock_ticket(v_r.ticket_atom_id, v_key || ':t:' || v_r.transfer_id::text);
    v_t := v_t + 1; v_u := v_u + 1;
  end loop;
  for v_r in select l.listing_id, l.ticket_atom_id from market.listing_native l
              join kernel.tickets t on t.ticket_atom_id = l.ticket_atom_id
             where t.event_session_id = p_event_session_id and l.status in ('active','reserved')
               and not exists (select 1 from market.market_sale ms where ms.listing_id = l.listing_id
                                 and ms.sale_state = 'paid_pending_transfer' and ms.terminal_state = 'pending')
             order by l.ticket_atom_id for update of l loop
    update market.listing_native set status = 'cancelled', reason_code = 'door_freeze', updated_at = now() where listing_id = v_r.listing_id;
    update market.offer set status = 'withdrawn', updated_at = now() where listing_id = v_r.listing_id and status = 'pending';
    update market.auction set status = 'cancelled', updated_at = now() where listing_id = v_r.listing_id and status = 'active';
    perform kernel.unlock_ticket(v_r.ticket_atom_id, v_key || ':l:' || v_r.listing_id::text);
    v_l := v_l + 1; v_u := v_u + 1;
  end loop;
  drained_transfers := v_t; drained_listings := v_l; atoms_unlocked := v_u;
  return next;
end;
$$;

-- 3d — market.door_freeze_drain_preview (RPC §17.10a; stub 086). The same
--   predicates as a COUNT; writes nothing.
create or replace function market.door_freeze_drain_preview(p_event_session_id uuid)
returns table(pending_transfers integer, active_listings integer, excluded_paid_pending integer, atoms_to_unlock integer)
language sql stable security definer set search_path = ''
as $$
  with tr as (select count(*)::integer as n from market.p2p_transfer p join kernel.tickets t on t.ticket_atom_id = p.ticket_atom_id
               where t.event_session_id = p_event_session_id and p.status = 'initiated'),
       li as (select l.listing_id from market.listing_native l join kernel.tickets t on t.ticket_atom_id = l.ticket_atom_id
               where t.event_session_id = p_event_session_id and l.status in ('active','reserved')),
       ex as (select count(*)::integer as n from li where exists (select 1 from market.market_sale ms where ms.listing_id = li.listing_id
                                 and ms.sale_state = 'paid_pending_transfer' and ms.terminal_state = 'pending')),
       ok as (select count(*)::integer as n from li where not exists (select 1 from market.market_sale ms where ms.listing_id = li.listing_id
                                 and ms.sale_state = 'paid_pending_transfer' and ms.terminal_state = 'pending'))
  select tr.n, ok.n, ex.n, tr.n + ok.n from tr, ex, ok
$$;

-- 3e — kernel.deletion_blockers_market (RPC §20.17.3; stub 077). The ordered
--   BP-3 · BP-4 · BP-7 native twin · BP-8 native twin predicates (DSM §2):
--   the first failing blocker's code, NULL when none.
create or replace function kernel.deletion_blockers_market(p_identity uuid)
returns text language plpgsql security definer set search_path = ''
as $$
begin
  -- BP-3: an unsettled native sale as buyer or seller (a cancelled never-paid checkout is no obligation)
  if exists (select 1 from market.market_sale ms where (ms.buyer_id = p_identity or ms.seller_id = p_identity)
               and ms.terminal_state = 'pending' and ms.sale_state <> 'cancelled') then
    return 'BP-3: unsettled native sale';
  end if;
  -- BP-4: an open native p2p transfer as sender or recipient
  if exists (select 1 from market.p2p_transfer p where (p.from_identity = p_identity or p.to_identity = p_identity)
               and p.status in ('initiated','accepted')) then
    return 'BP-4: open native transfer';
  end if;
  -- BP-7 native twin: an OPEN dispute on a payment this identity bought, or (resale arm) sold as an identity.
  if exists (select 1 from kernel.dispute_native d
              join public.payments p on p.id = d.payment_id
             where d.status not in ('won','lost','warning_closed','charge_refunded')
               and (p.buyer_id = p_identity
                    or exists (select 1 from kernel.payment_native pn join market.market_sale ms on ms.sale_id = pn.sale_id
                                where pn.payment_id = d.payment_id and ms.seller_id = p_identity))) then
    return 'BP-7: open native dispute';
  end if;
  -- BP-8 native twin: an in-flight native purchase as buyer
  if exists (select 1 from market.market_sale ms where ms.buyer_id = p_identity
               and ms.sale_state in ('initiated','paid_pending_transfer') and ms.terminal_state = 'pending') then
    return 'BP-8: in-flight native purchase';
  end if;
  return null;
end;
$$;

-- 3f — kernel.on_identity_erased_market (OR-17 terminal hook; stub 077). The
--   16d hard-delete allowance ONLY: never-sold listings (draft/cancelled) and
--   non-accepted offers of the erased identity. Sold/completed listings,
--   accepted offers, every market_sale and p2p_transfer row are RETAINED (never
--   repointed — CUSTODY-DEL-1). A dead listing is deleted only when no row still
--   references it (offers of other identities are their own rows and survive).
create or replace function kernel.on_identity_erased_market(p_identity uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  delete from market.offer o where o.buyer_id = p_identity and o.status in ('pending','declined','expired','withdrawn');
  delete from market.listing_native l
   where l.seller_id = p_identity and l.status in ('draft','cancelled')
     and not exists (select 1 from market.offer o where o.listing_id = l.listing_id)
     and not exists (select 1 from market.auction a where a.listing_id = l.listing_id)
     and not exists (select 1 from market.market_sale ms where ms.listing_id = l.listing_id);
end;
$$;

-- 3g — kernel.unlock_ticket (RPC §7.4; 079 body, PFA-13 replacement — signature
--   verbatim). The release resolves to 'dispute_hold' — NOT 'none' — while an
--   open kernel.dispute_native row joins the atom's ORIGINATING payment (the
--   issuance order's payment, or the completed native sale's payment); every
--   088 release path (cancel_listing, the door drain, cancel/expire/decline p2p,
--   cancel_event) routes through this one primitive. NOTE: 085's refund-hold
--   release paths write resale_state = 'none' directly (immutable bytes) and do
--   not re-arm — the engine's R-40 mirror still refuses the move; recorded as
--   REFUND_HOLD_RELEASE_REARM (forward obligation). A 'dispute_hold' atom is
--   released by NOTHING here (PFA-31: resolution only). Everything else is the
--   079 body unchanged: no owner precondition, no freeze recheck, noop on 'none'.
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
  v_owner  uuid;
  v_target text := 'none';
begin
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;

  select t.state, t.resale_state, t.current_owner_id
    into v_state, v_resale, v_owner
    from kernel.tickets t
   where t.ticket_atom_id = p_atom_id
   for update;
  if v_state is null then
    raise exception 'not_found: atom %', p_atom_id using errcode = 'P0002';
  end if;
  if v_resale = 'none' then
    return jsonb_build_object('status','noop_replay','resale_state','none');
  end if;
  if v_resale = 'dispute_hold' then
    -- PFA-31: a dispute hold is released ONLY by dispute resolution (parked) —
    -- never by a market release, and not by a Stripe-reported terminal.
    return jsonb_build_object('status','noop_replay','resale_state','dispute_hold');
  end if;

  -- R-40 RE-ARM (PFA-13): an open dispute on the atom's originating payment —
  -- order arm (the seq-1 'issue' row's cause_ref is the venue.order_item id —
  -- 085 finalize_primary_order — → its order → payment_native.order_id) or the
  -- sale arm (a completed market_sale of this atom → payment_native.sale_id).
  -- Either arm binds ONLY while the CURRENT holder is that payment's buyer —
  -- the payment that acquired the atom for its present holder (the same
  -- custody-moved rule record_dispute_native applies on the freeze side).
  if exists (
       select 1 from kernel.dispute_native d
        where d.status not in ('won','lost','warning_closed','charge_refunded')
          and d.payment_id in (
                select pn.payment_id from kernel.payment_native pn
                  join venue.order_item oi on oi.order_id = pn.order_id
                  join venue."order" o on o.order_id = oi.order_id
                 where oi.id = (select l.cause_ref from kernel.ticket_ownership_log l
                                 where l.ticket_atom_id = p_atom_id and l.sequence = 1 and l.cause = 'issue')
                   and o.buyer_id = v_owner
                union all
                select pn.payment_id from kernel.payment_native pn
                  join market.market_sale ms on ms.sale_id = pn.sale_id
                 where ms.ticket_atom_id = p_atom_id and ms.terminal_state = 'completed' and ms.buyer_id = v_owner)) then
    v_target := 'dispute_hold';
  end if;

  update kernel.tickets set resale_state = v_target, updated_at = now()
   where ticket_atom_id = p_atom_id;
  return jsonb_build_object('status','ok','resale_state', v_target);
end;
$$;

-- ============================================================================
-- PART 4 — kernel.transfer_ticket_ownership (RPC §7.2; SSCAS #2; FR-3). THE
--   sole custody-move engine and THE freeze enforcement point. E-22: the atom's
--   kernel.tickets row is held FOR UPDATE across validation, the ledger append,
--   the head mutation and the dependent sale transition, in one transaction.
--   E-23: the recipient must be ACTIVE (never DELETION_PENDING, never ERASED),
--   verified here independently of any caller. R-40: refuses while an open
--   dispute joins the atom's originating payment. Locks ascending: Event/Session
--   FOR SHARE (1) → [Listing (4) is the market caller's] → Ticket Atom FOR UPDATE
--   (5) → Payment (6). Idempotent on ownership_log UNIQUE(cause, cause_ref, atom).
--   signing_key_id stays pinned (E-97: no ratified resolver exists; re-pinning
--   is the rotation un-park's). REQUIRED-emits ownership_changed (R2 row 1).
-- ============================================================================
create or replace function kernel.transfer_ticket_ownership(
  p_atom_id uuid, p_to_identity uuid, p_cause text, p_cause_ref uuid, p_payment_id uuid, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_t kernel.tickets%rowtype; v_session uuid; v_seq integer; v_cv integer; v_state text; v_pay public.payments%rowtype;
  v_sale market.market_sale%rowtype; v_pn kernel.payment_native%rowtype; v_actor uuid := coalesce(auth.uid(), '00000000-0000-0000-0000-0000000000f1');
begin
  if p_cause is null or p_cause not in ('market_sale','auction_sale','p2p_transfer','admin_action') then
    raise exception 'invalid_input: % is not a transfer cause', coalesce(p_cause,'<null>');
  end if;
  if p_to_identity is null or p_cause_ref is null or p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'invalid_input: recipient, cause_ref and command_key are required';
  end if;
  select t.event_session_id into v_session from kernel.tickets t where t.ticket_atom_id = p_atom_id;
  if v_session is null then raise exception 'not_found: atom %', p_atom_id using errcode = 'P0002'; end if;
  perform 1 from catalog.event_session s where s.session_id = v_session for share;         -- rank 1: the freeze read
  -- rank 4 BEFORE rank 5 (§14.2): the sale row of a native sale is taken here (a
  -- market caller already holds it — re-locking is free; a direct call is ordered).
  if p_cause in ('market_sale','auction_sale') then
    select * into v_sale from market.market_sale ms where ms.sale_id = p_cause_ref for update;
    if not found then raise exception 'not_found: sale %', p_cause_ref using errcode = 'P0002'; end if;
  end if;
  select * into v_t from kernel.tickets t where t.ticket_atom_id = p_atom_id for update;   -- rank 5 (E-22: held to commit)
  -- C26/C16 replay: the same custody move already recorded ⇒ the original result.
  if exists (select 1 from kernel.ticket_ownership_log l
              where l.ticket_atom_id = p_atom_id and l.cause = p_cause and l.cause_ref = p_cause_ref) then
    return jsonb_build_object('status','noop_replay','atom_id', p_atom_id, 'new_owner', v_t.current_owner_id,
                              'credential_version', v_t.credential_version);
  end if;
  -- E-23: the recipient is ACTIVE — never DELETION_PENDING, never ERASED (the
  -- engine's own check; a caller's F-clause is not relied on). FOR SHARE: a
  -- concurrent erasure / deletion request holds this row FOR UPDATE, so the
  -- engine WAITS and re-reads the committed state instead of a stale ACTIVE.
  select ie.deletion_state into v_state from kernel.identity_ext ie where ie.identity_id = p_to_identity for share;
  if coalesce(v_state, 'ACTIVE') <> 'ACTIVE' then
    raise exception 'precondition_failed: recipient identity is % — no acquisition', lower(v_state);
  end if;
  if v_t.current_owner_id = p_to_identity then
    raise exception 'precondition_failed: recipient already holds the atom';
  end if;
  if v_t.state <> 'active' then
    raise exception 'precondition_failed: atom is %, not transferable', v_t.state;
  end if;
  -- the sanctioned overlays: a native sale moves a LISTED atom, a p2p moves a
  -- LOCKED one; the break-glass admin_action moves only a FREE atom (a live
  -- listing/transfer must be cancelled first — never orphaned under a moved atom).
  if (p_cause in ('market_sale','auction_sale') and v_t.resale_state <> 'listed')
     or (p_cause = 'p2p_transfer' and v_t.resale_state <> 'locked')
     or (p_cause = 'admin_action' and v_t.resale_state <> 'none') then
    raise exception 'precondition_failed: conflict_locked (resale_state=%)', v_t.resale_state;
  end if;
  -- R-40 mirror: no open dispute on the payment that acquired the atom for its
  -- CURRENT holder (order arm: the holder is the order's buyer; sale arm: the
  -- holder is that completed sale's buyer) — the unlock re-arm's exact predicate.
  if exists (
       select 1 from kernel.dispute_native d
        where d.status not in ('won','lost','warning_closed','charge_refunded')
          and d.payment_id in (
                select pn.payment_id from kernel.payment_native pn
                  join venue.order_item oi on oi.order_id = pn.order_id
                  join venue."order" o on o.order_id = oi.order_id
                 where oi.id = (select l.cause_ref from kernel.ticket_ownership_log l
                                 where l.ticket_atom_id = p_atom_id and l.sequence = 1 and l.cause = 'issue')
                   and o.buyer_id = v_t.current_owner_id
                union all
                select pn.payment_id from kernel.payment_native pn
                  join market.market_sale ms on ms.sale_id = pn.sale_id
                 where ms.ticket_atom_id = p_atom_id and ms.terminal_state = 'completed' and ms.buyer_id = v_t.current_owner_id)) then
    raise exception 'precondition_failed: open_dispute';
  end if;
  -- THE freeze enforcement point (§12.4): under the atom lock.
  if kernel.is_transfer_frozen(p_atom_id) then
    raise exception 'precondition_failed: frozen';
  end if;
  -- C35: a native sale's payment belongs to the RECIPIENT, is real (succeeded), and settles ONE custody move.
  if p_cause in ('market_sale','auction_sale') then
    if v_sale.ticket_atom_id <> p_atom_id or v_sale.buyer_id <> p_to_identity then
      raise exception 'precondition_failed: sale does not bind this atom and recipient';
    end if;
    if v_sale.terminal_state = 'compensated' then
      raise exception 'state_conflict: sale % was compensated — complete-XOR-compensate', p_cause_ref;
    end if;
    if p_payment_id is null then raise exception 'payment_unverified: a native sale requires its payment'; end if;
  end if;
  if p_payment_id is not null then
    select * into v_pay from public.payments p where p.id = p_payment_id;
    if not found or v_pay.buyer_id <> p_to_identity or v_pay.status <> 'succeeded' then
      raise exception 'payment_unverified: payment does not belong to the recipient or is not succeeded';
    end if;
    -- a payment already linked to ANOTHER order/sale never funds a second move (R-34 one link)
    select * into v_pn from kernel.payment_native pn where pn.payment_id = p_payment_id;
    if found and (v_pn.order_id is not null or v_pn.sale_id is distinct from p_cause_ref) then
      raise exception 'payment_unverified: payment % already settled another custody move', p_payment_id;
    end if;
  end if;
  -- ledger FIRST (the idempotency anchors live here), then the head — one txn under the atom lock.
  select coalesce(max(l.sequence), 0) + 1 into v_seq from kernel.ticket_ownership_log l where l.ticket_atom_id = p_atom_id;
  v_cv := v_t.credential_version + 1;
  insert into kernel.ticket_ownership_log (ticket_atom_id, sequence, from_identity, to_identity, cause, cause_ref,
                                           actor_identity, command_idempotency_key, credential_version_after, state_transition)
  values (p_atom_id, v_seq, v_t.current_owner_id, p_to_identity, p_cause, p_cause_ref, v_actor,
          p_command_key || ':' || p_atom_id::text, v_cv,
          jsonb_build_object('from', 'active', 'to', 'active', 'resale_from', v_t.resale_state, 'resale_to', 'none'));
  update kernel.tickets
     set current_owner_id = p_to_identity, credential_version = v_cv, resale_state = 'none', updated_at = now()
   where ticket_atom_id = p_atom_id;
  -- the payment link (R-34: born at transfer, instrument_fingerprint NULL — no webhook context here).
  if p_payment_id is not null and p_cause in ('market_sale','auction_sale') and v_pn.payment_id is null then
    insert into kernel.payment_native (payment_id, sale_id, amount_minor, currency, instrument_fingerprint)
    values (p_payment_id, p_cause_ref, v_pay.total, v_sale.currency, null);
  end if;
  if p_cause in ('market_sale','auction_sale') then
    update market.market_sale set terminal_state = 'completed', updated_at = now()
     where sale_id = p_cause_ref and terminal_state = 'pending';
  end if;
  -- R2 row 1: REQUIRED — a custody change is always announced (the envelope is the credential's supersession signal).
  perform notify.emit_event_required('ownership_changed', 'ticket_atom', p_atom_id,
            'ownership:' || p_atom_id::text || ':' || v_cv::text,
            jsonb_build_object('to_identity', p_to_identity, 'cause', p_cause, 'credential_version', v_cv));
  return jsonb_build_object('status','ok','atom_id', p_atom_id, 'new_owner', p_to_identity, 'credential_version', v_cv);
exception when unique_violation then
  if exists (select 1 from kernel.ticket_ownership_log l
              where l.ticket_atom_id = p_atom_id and l.cause = p_cause and l.cause_ref = p_cause_ref) then
    return jsonb_build_object('status','noop_replay','atom_id', p_atom_id,
             'new_owner', (select t.current_owner_id from kernel.tickets t where t.ticket_atom_id = p_atom_id),
             'credential_version', (select t.credential_version from kernel.tickets t where t.ticket_atom_id = p_atom_id));
  end if;
  raise;
end;
$$;

-- ============================================================================
-- PART 5 — the R-40 native dispute surface (RPC §20.7.13-§20.7.15; OR-24).
-- ============================================================================

-- 5a — kernel.record_dispute_native (SSCAS #9; service_role: the stripe-webhook
--   charge.dispute.created native branch). UPSERT on stripe_dispute_ref; when the
--   recorded status is OPEN: the atom leg (dispute_hold where the buyer still
--   holds the atom, live, no other overlay — else skip + alert) and the payout leg
--   (every reachable pending/submitted payout → hold_state 'held', reason
--   'dispute', held_by NULL, status untouched — settlement AND commission payouts
--   alike). NO-LINK ARM: a payment with no payment_native row yet is recorded with
--   zero freeze legs + an alert. Dispute row first, then Session FOR SHARE (1) →
--   Atom (5, ascending) → Payout (6). BE-emits payout_on_hold per held payout.
create or replace function kernel.record_dispute_native(
  p_stripe_dispute_ref text, p_stripe_charge_ref text, p_stripe_pi_ref text, p_amount_minor integer, p_currency text,
  p_reason text, p_status text, p_evidence_due_at timestamptz, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_sys constant uuid := '00000000-0000-0000-0000-0000000000f1';
  v_pay public.payments%rowtype; v_pn kernel.payment_native%rowtype; v_d kernel.dispute_native%rowtype;
  v_open boolean; v_atom record; v_row record; v_po record; v_held integer := 0; v_atoms integer := 0; v_skipped integer := 0;
  v_ccy text;
begin
  if p_stripe_dispute_ref is null or p_stripe_charge_ref is null or p_reason is null or p_command_key is null then
    raise exception 'invalid_input: dispute ref, charge ref, reason and command_key are required';
  end if;
  if p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-] (it lands in the immutable audit)';
  end if;
  if p_status is null or p_status not in ('warning_needs_response','warning_under_review','warning_closed',
                                           'needs_response','under_review','won','lost','charge_refunded') then
    raise exception 'invalid_input: % is not a dispute status', coalesce(p_status,'<null>');
  end if;
  if p_amount_minor is null or p_amount_minor < 0 then raise exception 'invalid_input: amount_minor must be >= 0'; end if;
  -- currency: Stripe reports lowercase ISO codes; the seam compares by equality — normalize, never guess.
  v_ccy := upper(coalesce(p_currency, 'USD'));
  if v_ccy !~ '^[A-Z]{3}$' then raise exception 'invalid_input: currency must be a 3-letter ISO code'; end if;
  -- replay: the same Stripe dispute is recorded once; a status change is mark_dispute_state's.
  select * into v_d from kernel.dispute_native d where d.stripe_dispute_ref = p_stripe_dispute_ref for update;
  if found then
    return jsonb_build_object('status','noop_replay','dispute_id', v_d.dispute_id);
  end if;
  -- the frozen money-in row (the dispute FKs it directly — recordable before any link).
  select * into v_pay from public.payments p where p.stripe_payment_intent_id = p_stripe_pi_ref;
  if not found then
    raise exception 'not_found: no payment for payment intent %', coalesce(p_stripe_pi_ref,'<null>') using errcode = 'P0002';
  end if;
  begin
    insert into kernel.dispute_native (stripe_dispute_ref, stripe_charge_ref, stripe_pi_ref, payment_id, amount_minor, currency,
                                       reason, evidence_due_at, status)
    values (p_stripe_dispute_ref, p_stripe_charge_ref, p_stripe_pi_ref, v_pay.id, p_amount_minor, v_ccy,
            p_reason, p_evidence_due_at, p_status)
    returning * into v_d;
  exception when unique_violation then
    -- a concurrent first record of the same Stripe dispute won: this call is its replay (UPSERT semantics).
    select * into v_d from kernel.dispute_native d where d.stripe_dispute_ref = p_stripe_dispute_ref;
    return jsonb_build_object('status','noop_replay','dispute_id', v_d.dispute_id);
  end;
  v_open := p_status not in ('won','lost','warning_closed','charge_refunded');
  select * into v_pn from kernel.payment_native pn where pn.payment_id = v_pay.id;
  if v_open and found then
    -- ATOM LEG: the disputed payment's atoms (order arm via the issuance ledger; sale arm via the sale).
    for v_atom in
      select t.ticket_atom_id, t.event_session_id
        from kernel.tickets t
       where t.ticket_atom_id in (
               select l.ticket_atom_id from kernel.ticket_ownership_log l
                 join venue.order_item oi on oi.id = l.cause_ref
                where v_pn.order_id is not null and l.sequence = 1 and l.cause = 'issue' and oi.order_id = v_pn.order_id
               union
               select ms.ticket_atom_id from market.market_sale ms where v_pn.sale_id is not null and ms.sale_id = v_pn.sale_id)
       order by t.ticket_atom_id loop
      perform 1 from catalog.event_session s where s.session_id = v_atom.event_session_id for share;   -- rank 1
      -- decide UNDER the atom lock (rank 5): a concurrent custody move, unlock or
      -- listing is WAITED FOR, never judged from a pre-lock snapshot (E-22 race).
      select t.state, t.resale_state, t.current_owner_id into v_row
        from kernel.tickets t where t.ticket_atom_id = v_atom.ticket_atom_id for update;
      if v_row.current_owner_id = v_pay.buyer_id and v_row.state in ('issued','active') and v_row.resale_state = 'none' then
        update kernel.tickets set resale_state = 'dispute_hold', updated_at = now()
         where ticket_atom_id = v_atom.ticket_atom_id;
        v_atoms := v_atoms + 1;
      else
        -- custody moved on, or the overlay is occupied: skip, record, alert (never mutate a live market machine).
        v_skipped := v_skipped + 1;
        insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
        values (v_sys, 'dispute.alert', 'ticket_atom', v_atom.ticket_atom_id,
                case when v_row.current_owner_id <> v_pay.buyer_id then 'custody_moved' else 'overlay_occupied' end,
                jsonb_build_object('dispute_id', v_d.dispute_id, 'resale_state', v_row.resale_state, 'state', v_row.state, 'audience', 'platform_risk'));
      end if;
    end loop;
    -- PAYOUT LEG: every pending/submitted payout reachable from the disputed payment that is
    -- not already under a dispute hold (a probation hold is upgraded: its own release path
    -- is reason-scoped and never releases a 'dispute' hold — 087).
    for v_po in
      select po.payout_id, po.payee_org_id, po.payee_identity_id, po.amount_minor from kernel.payout po
       where po.status in ('pending','submitted') and po.hold_state in ('none','probation_hold')
         and (   (v_pn.sale_id is not null and po.cause_ref = v_pn.sale_id)
              or po.cause_ref in (select sl.settlement_id from venue.settlement_line sl
                                   where sl.cause_ref = coalesce(v_pn.order_id, v_pn.sale_id)))
       order by po.payout_id for update loop                                                    -- rank 6
      update kernel.payout set hold_state = 'held', hold_reason_code = 'dispute', held_at = now(), held_by = null, updated_at = now()
       where payout_id = v_po.payout_id;
      v_held := v_held + 1;
      begin   -- BE: a notice failure never blocks the freeze (OR-14)
        perform notify.emit_event('payout_on_hold', 'payout', v_po.payout_id, 'payout_on_hold:' || v_po.payout_id::text || ':' || v_d.dispute_id::text,
                  jsonb_build_object('dispute_id', v_d.dispute_id, 'reason', 'dispute', 'amount_minor', v_po.amount_minor));
      exception when others then null; end;
    end loop;
  elsif v_open then
    -- NO-LINK ARM: recorded, zero freeze legs, alerted (the dwell-window refusal rides finalize_market_sale).
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
    values (v_sys, 'dispute.alert', 'dispute_native', v_d.dispute_id, 'no_link',
            jsonb_build_object('payment_id', v_pay.id, 'audience', 'platform_risk'));
  end if;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values (v_sys, 'dispute.record', 'dispute_native', v_d.dispute_id, p_command_key,
          jsonb_build_object('status', p_status, 'atoms_held', v_atoms, 'atoms_skipped', v_skipped, 'payouts_held', v_held,
                             'linked', (v_pn.id is not null)));
  return jsonb_build_object('status','ok','dispute_id', v_d.dispute_id, 'atoms_held', v_atoms, 'atoms_skipped', v_skipped,
                            'payouts_held', v_held, 'linked', (v_pn.id is not null));
end;
$$;

-- 5b — kernel.mark_dispute_state (service_role; charge.dispute.updated/.closed).
--   STATE ONLY — moves no money, releases nothing. Forward-only under FOR UPDATE:
--   open ↔ open free; open → terminal once; terminal ABSORBING (same → noop_replay,
--   different → state_conflict). Unknown ref → not_found (the handler then records
--   at terminal via record_dispute_native with zero freeze legs). A Stripe-reported
--   terminal is a fact, not a release: holds persist until resolution (PFA-31).
create or replace function kernel.mark_dispute_state(p_stripe_dispute_ref text, p_new_status text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_d kernel.dispute_native%rowtype; v_sys constant uuid := '00000000-0000-0000-0000-0000000000f1';
  v_terminal constant text[] := array['won','lost','warning_closed','charge_refunded'];
begin
  if p_new_status is null or p_new_status not in ('warning_needs_response','warning_under_review','warning_closed',
                                                   'needs_response','under_review','won','lost','charge_refunded') then
    raise exception 'invalid_input: % is not a dispute status', coalesce(p_new_status,'<null>');
  end if;
  select * into v_d from kernel.dispute_native d where d.stripe_dispute_ref = p_stripe_dispute_ref for update;
  if not found then raise exception 'not_found: dispute %', p_stripe_dispute_ref using errcode = 'P0002'; end if;
  if v_d.status = any(v_terminal) then
    if v_d.status = p_new_status then
      return jsonb_build_object('status','noop_replay','dispute_id', v_d.dispute_id,'dispute_status', v_d.status);
    end if;
    raise exception 'state_conflict: dispute % is terminal (%) — % refused', v_d.dispute_id, v_d.status, p_new_status;
  end if;
  if v_d.status = p_new_status then
    return jsonb_build_object('status','noop_replay','dispute_id', v_d.dispute_id,'dispute_status', v_d.status);
  end if;
  update kernel.dispute_native set status = p_new_status, updated_at = now() where dispute_id = v_d.dispute_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_sys, 'dispute.state_sync', 'dispute_native', v_d.dispute_id, coalesce(p_command_key,'state_sync'),
          jsonb_build_object('status', v_d.status), jsonb_build_object('status', p_new_status));
  return jsonb_build_object('status','ok','dispute_id', v_d.dispute_id,'dispute_status', p_new_status);
end;
$$;

-- 5c — kernel.resolve_dispute_native (SSCAS #11; edge-fronted). PFA-31 (OWNER-
--   SIGNED 2026-09-02): the frozen B7 shape is propose-only (platform_risk /
--   platform_support park a kernel.approval_request, class platform_admin) and
--   platform_admin executes with step-up + DUAL CONTROL — and 077's immutable
--   approval_request CHECKs admit no dispute action/subject, so the mechanism is
--   unbuildable. PARKED FAIL-CLOSED: authority is checked first, the outcome is
--   validated, then the call raises dual_control_unavailable with ZERO mutation.
--   Holds persist; nothing releases; nothing resolves; nothing is fabricated.
--   Signature frozen for the un-park (DISPUTE_DUAL_CONTROL).
create or replace function kernel.resolve_dispute_native(p_dispute_id uuid, p_outcome text, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if not kernel.is_platform(array['platform_risk','platform_support','platform_admin']) then
    raise exception 'insufficient_privilege: platform_risk / platform_support (propose) or platform_admin (execute) only' using errcode = '42501';
  end if;
  if p_outcome is null or p_outcome not in ('seller_win','buyer_win','partial_refund') then
    raise exception 'invalid_input: outcome must be seller_win | buyer_win | partial_refund';
  end if;
  if not exists (select 1 from kernel.dispute_native d where d.dispute_id = p_dispute_id) then
    raise exception 'not_found: dispute %', p_dispute_id using errcode = 'P0002';
  end if;
  -- ── PFA-31 FAIL-CLOSED PARK (zero mutation) ─────────────────────────────────
  raise exception 'precondition_failed: dual_control_unavailable — dispute resolution requires a dual-control mechanism the immutable approval substrate cannot park (PFA-31); the dispute stays held, nothing is resolved or released'
    using errcode = 'P0001';
end;
$$;

-- ============================================================================
-- PART 6 — the native market verbs (RPC §20.8; §8; §12; §1). Every verb is
--   SECURITY DEFINER, search_path pinned, auth.uid() server-derived, untrusted
--   params re-validated under lock. X-12: the rail is DARK — the flag read
--   coalesces NULL to false. PFA-30: the two split-writing points fail closed.
-- ============================================================================

-- 6.1 market.create_listing (SSCAS #6). Owner-only. Governing policy = the
--   event-scope policy's latest version when one exists, else the venue's (C11:
--   no policy ⇒ off ⇒ refused). The 078 CHECK set is the storage truth (its own
--   comment names RPC §20.2.2's {off, capped, free} sketch stale): off /
--   transfers_only / face_value_queue / auction refuse a listing; buy_now and
--   offer bind listing_mode; fixed_cap requires a cap. A present price_cap_bps
--   ALWAYS binds: price ≤ floor(face × bps / 10000), integer minor units (E-98).
--   Lock order RPC §14.2: Session FOR SHARE (1) → Listing INSERT (4) → Atom (5)
--   via kernel.lock_ticket('listed') — which owns the owner/active/none/freeze rechecks.
create or replace function market.create_listing(p_atom_id uuid, p_price_minor integer, p_listing_mode text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid(); v_t kernel.tickets%rowtype; v_ev record; v_pol record; v_tt record; v_cap bigint; v_id uuid; v_ex uuid;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then raise exception 'precondition_failed: command key required'; end if;
  if not coalesce((select (c.value #>> '{}')::boolean from catalog.platform_config c
                    where c.key = 'feature.native_resale_enabled' order by c.version desc limit 1), false) then
    raise exception 'precondition_failed: feature_disabled';
  end if;
  if p_listing_mode is null or p_listing_mode not in ('buy_now','offer','auction') then
    raise exception 'invalid_input: listing_mode must be buy_now | offer | auction';
  end if;
  if p_listing_mode = 'auction' then raise exception 'precondition_failed: native_auction_not_offered'; end if;   -- OR-11
  if p_price_minor is null or p_price_minor <= 0 then raise exception 'invalid_input: price_minor must be > 0'; end if;
  select l.listing_id into v_ex from market.listing_native l where l.seller_id = v_uid and l.command_idempotency_key = p_command_key;
  if v_ex is not null then return jsonb_build_object('status','noop_replay','listing_id', v_ex); end if;
  select * into v_t from kernel.tickets t where t.ticket_atom_id = p_atom_id;
  if not found then raise exception 'not_found: atom %', p_atom_id using errcode = 'P0002'; end if;
  if v_t.current_owner_id <> v_uid then
    raise exception 'insufficient_privilege: only the current owner may list' using errcode = '42501';
  end if;
  select es.session_id, es.event_id, e.venue_id into v_ev
    from catalog.event_session es join catalog.event e on e.event_id = es.event_id
   where es.session_id = v_t.event_session_id for share of es;                                   -- rank 1
  select rp.policy_id, rp.version, rp.mode, rp.price_cap_bps into v_pol
    from catalog.resale_policy rp
   where (rp.scope_kind = 'event' and rp.event_id = v_ev.event_id) or (rp.scope_kind = 'venue' and rp.venue_id = v_ev.venue_id)
   order by (rp.scope_kind = 'event') desc, rp.version desc limit 1;
  if not found then raise exception 'precondition_failed: policy_violation (no resale policy — C11 default off)'; end if;
  if v_pol.mode in ('off','transfers_only','face_value_queue','auction') then
    raise exception 'precondition_failed: policy_violation (mode % does not admit a native listing)', v_pol.mode;
  end if;
  if (v_pol.mode = 'buy_now' and p_listing_mode <> 'buy_now') or (v_pol.mode = 'offer' and p_listing_mode <> 'offer') then
    raise exception 'precondition_failed: policy_violation (listing_mode % not permitted under policy mode %)', p_listing_mode, v_pol.mode;
  end if;
  if v_pol.mode = 'fixed_cap' and v_pol.price_cap_bps is null then
    raise exception 'precondition_failed: policy_violation (fixed_cap policy carries no cap — refused)';
  end if;
  select tt.price_minor, tt.currency into v_tt from venue.ticket_type tt where tt.ticket_type_id = v_t.ticket_type_id;
  if not found then raise exception 'precondition_failed: policy_violation (atom has no face price)'; end if;
  if v_pol.price_cap_bps is not null then
    v_cap := (v_tt.price_minor::bigint * v_pol.price_cap_bps) / 10000;
    if p_price_minor > v_cap then
      raise exception 'precondition_failed: policy_violation (price % exceeds cap % = face % × % bps)', p_price_minor, v_cap, v_tt.price_minor, v_pol.price_cap_bps;
    end if;
  end if;
  insert into market.listing_native (ticket_atom_id, seller_id, event_session_id, listing_mode, price_minor, currency,
                                     resale_policy_id, resale_policy_version, status, command_idempotency_key)
  values (p_atom_id, v_uid, v_t.event_session_id, p_listing_mode, p_price_minor, coalesce(v_tt.currency,'USD'),
          v_pol.policy_id, v_pol.version, 'active', p_command_key)
  returning listing_id into v_id;                                                                -- rank 4
  perform kernel.lock_ticket(p_atom_id, 'listed', p_command_key);                                 -- rank 5 (owner/active/none/freeze)
  return jsonb_build_object('status','ok','listing_id', v_id);
exception when unique_violation then
  select l.listing_id into v_ex from market.listing_native l where l.seller_id = v_uid and l.command_idempotency_key = p_command_key;
  if v_ex is not null then return jsonb_build_object('status','noop_replay','listing_id', v_ex); end if;
  raise exception 'precondition_failed: conflict_locked (atom already listed)';
end;
$$;

-- 6.2 market.cancel_listing (member #6 reverse). Seller, or platform_admin /
--   platform_risk (RPC §20.8.2 — support excluded). Refuses while a checkout is
--   in flight (sale_in_flight); cascades pending offers → withdrawn, auction →
--   cancelled; releases the atom through kernel.unlock_ticket (PFA-13 re-arm).
create or replace function market.cancel_listing(p_listing_id uuid, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_l market.listing_native%rowtype; v_platform boolean;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then raise exception 'precondition_failed: command key required'; end if;
  select * into v_l from market.listing_native l where l.listing_id = p_listing_id for update;   -- rank 4
  if not found then raise exception 'not_found: listing %', p_listing_id using errcode = 'P0002'; end if;
  v_platform := kernel.is_platform(array['platform_admin','platform_risk']);
  if v_l.seller_id <> v_uid and not v_platform then
    raise exception 'insufficient_privilege: seller, platform_admin or platform_risk only' using errcode = '42501';
  end if;
  if p_reason_code is not null and (p_reason_code !~ '^[A-Za-z0-9._:-]{1,64}$' or p_reason_code in ('door_freeze','event_cancelled')) then
    raise exception 'invalid_input: reason_code must be 1-64 chars of [A-Za-z0-9._:-] and not a system reason';
  end if;
  if v_l.status = 'cancelled' then return jsonb_build_object('status','noop_replay','listing_id', p_listing_id,'final_state','cancelled'); end if;
  if v_l.status not in ('draft','active','reserved') then
    raise exception 'state_conflict: listing % is %', p_listing_id, v_l.status;
  end if;
  if exists (select 1 from market.market_sale ms where ms.listing_id = p_listing_id
              and ms.sale_state in ('initiated','paid_pending_transfer') and ms.terminal_state = 'pending') then
    raise exception 'precondition_failed: sale_in_flight';
  end if;
  update market.listing_native set status = 'cancelled', reason_code = coalesce(p_reason_code, case when v_platform then 'platform_cancel' else 'seller_cancel' end),
         updated_at = now() where listing_id = p_listing_id;
  update market.offer set status = 'withdrawn', updated_at = now() where listing_id = p_listing_id and status = 'pending';
  update market.auction set status = 'cancelled', updated_at = now() where listing_id = p_listing_id and status = 'active';
  if v_l.status in ('active','reserved') then
    perform kernel.unlock_ticket(v_l.ticket_atom_id, p_command_key);                              -- rank 5
  end if;
  if v_platform and v_l.seller_id <> v_uid then
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
    values (v_uid, 'listing.cancel', 'listing_native', p_listing_id, coalesce(p_reason_code,'platform_cancel'),
            jsonb_build_object('status', v_l.status), jsonb_build_object('status','cancelled'));
  end if;
  return jsonb_build_object('status','ok','listing_id', p_listing_id,'final_state','cancelled');
end;
$$;

-- 6.3 market.create_auction — OR-11: every native listing is refused
--   (native_auction_not_offered) after authority is checked; zero mutation.
create or replace function market.create_auction(p_listing_id uuid, p_reserve_minor integer, p_min_increment_minor integer,
                                                 p_anti_snipe_seconds integer, p_ends_at timestamptz, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_seller uuid;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  select l.seller_id into v_seller from market.listing_native l where l.listing_id = p_listing_id;
  if v_seller is null then raise exception 'not_found: listing %', p_listing_id using errcode = 'P0002'; end if;
  if v_seller <> v_uid then raise exception 'insufficient_privilege: seller only' using errcode = '42501'; end if;
  raise exception 'precondition_failed: native_auction_not_offered';
end;
$$;

-- 6.4 market.place_bid — feature-dark (OR-11): no native auction can exist.
create or replace function market.place_bid(p_auction_id uuid, p_amount_minor integer, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  raise exception 'precondition_failed: native_auction_not_offered';
end;
$$;

-- 6.5 market.make_offer. F-3 (caller DELETION_PENDING refused). A stated intent
--   only: no hold, no lock, no money. The expiry is CALLER-SUPPLIED and required
--   (no TTL key is named — PFA-9: nothing is invented). Replaces the buyer's
--   prior pending offer on the same listing (S-12).
create or replace function market.make_offer(p_listing_id uuid, p_amount_minor integer, p_expires_at timestamptz, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_l market.listing_native%rowtype; v_ex market.offer%rowtype; v_replaced uuid; v_id uuid; v_cap bigint;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then raise exception 'precondition_failed: command key required'; end if;
  if not coalesce((select (c.value #>> '{}')::boolean from catalog.platform_config c
                    where c.key = 'feature.native_resale_enabled' order by c.version desc limit 1), false) then
    raise exception 'precondition_failed: feature_disabled';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then raise exception 'invalid_input: amount_minor must be > 0'; end if;
  if p_expires_at is null or p_expires_at <= now() then raise exception 'invalid_input: expires_at must be a future instant'; end if;
  if kernel.is_deletion_pending(v_uid) then raise exception 'precondition_failed: deletion_pending'; end if;   -- OR-17 F-3
  select * into v_ex from market.offer o where o.buyer_id = v_uid and o.command_idempotency_key = p_command_key;
  if found then return jsonb_build_object('status','noop_replay','offer_id', v_ex.offer_id,'expires_at', v_ex.expires_at); end if;
  select * into v_l from market.listing_native l where l.listing_id = p_listing_id for update;   -- rank 4 (serialises with cancel)
  if not found then raise exception 'not_found: listing %', p_listing_id using errcode = 'P0002'; end if;
  if v_l.seller_id = v_uid then raise exception 'precondition_failed: self_offer'; end if;
  if v_l.status <> 'active' then raise exception 'precondition_failed: listing_not_active (%)', v_l.status; end if;
  if v_l.listing_mode not in ('buy_now','offer') then raise exception 'precondition_failed: offers_not_accepted (listing_mode %)', v_l.listing_mode; end if;
  if kernel.is_transfer_frozen(v_l.ticket_atom_id) then raise exception 'precondition_failed: frozen'; end if;
  -- the LISTING's snapshot policy governs the offer (§20.8.5 above_cap): price ≤ floor(face × bps / 10000)
  select (tt.price_minor::bigint * rp.price_cap_bps) / 10000 into v_cap
    from catalog.resale_policy rp
    join kernel.tickets t on t.ticket_atom_id = v_l.ticket_atom_id
    join venue.ticket_type tt on tt.ticket_type_id = t.ticket_type_id
   where rp.policy_id = v_l.resale_policy_id and rp.price_cap_bps is not null;
  if v_cap is not null and p_amount_minor > v_cap then
    raise exception 'precondition_failed: policy_violation (above_cap: offer % exceeds cap %)', p_amount_minor, v_cap;
  end if;
  update market.offer set status = 'withdrawn', updated_at = now()
   where listing_id = p_listing_id and buyer_id = v_uid and status = 'pending' returning offer_id into v_replaced;
  insert into market.offer (listing_id, buyer_id, amount_minor, currency, status, expires_at, command_idempotency_key)
  values (p_listing_id, v_uid, p_amount_minor, v_l.currency, 'pending', p_expires_at, p_command_key)
  returning offer_id into v_id;
  return jsonb_build_object('status','ok','offer_id', v_id,'expires_at', p_expires_at,'replaced_offer_id', v_replaced);
end;
$$;

-- 6.6 market.respond_offer (SSCAS #2 on accept). Seller only. Expiry is
--   ARITHMETIC (expires_at <= now() ⇒ expired, the sweep is presentational —
--   T-RPC-MARKET-07). F-2: an accept of a DELETION_PENDING buyer's offer is
--   refused (a decline is disposal and stays allowed). ACCEPT = PFA-30 PARK
--   POINT: every validation runs, then the split INSERT fails closed —
--   resale_split_unavailable — with zero rows written and no custody move.
create or replace function market.respond_offer(p_offer_id uuid, p_decision text, p_payment_id uuid, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_o market.offer%rowtype; v_l market.listing_native%rowtype; v_pay public.payments%rowtype;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then raise exception 'precondition_failed: command key required'; end if;
  if p_decision is null or p_decision not in ('accept','decline') then raise exception 'invalid_input: decision must be accept | decline'; end if;
  select * into v_o from market.offer o where o.offer_id = p_offer_id;
  if not found then raise exception 'not_found: offer %', p_offer_id using errcode = 'P0002'; end if;
  select * into v_l from market.listing_native l where l.listing_id = v_o.listing_id for update;   -- rank 4
  select * into v_o from market.offer o where o.offer_id = p_offer_id for update;
  if v_l.seller_id <> v_uid then raise exception 'insufficient_privilege: seller only' using errcode = '42501'; end if;
  if v_o.status <> 'pending' then
    if (v_o.status = 'accepted' and p_decision = 'accept') or (v_o.status = 'declined' and p_decision = 'decline') then
      return jsonb_build_object('status','noop_replay','offer_id', p_offer_id,'final_state', v_o.status);
    end if;
    raise exception 'state_conflict: offer % is %', p_offer_id, v_o.status;
  end if;
  if v_o.expires_at is not null and v_o.expires_at <= now() then
    update market.offer set status = 'expired', updated_at = now() where offer_id = p_offer_id;
    raise exception 'precondition_failed: offer_expired';
  end if;
  if p_decision = 'decline' then
    update market.offer set status = 'declined', updated_at = now() where offer_id = p_offer_id;
    return jsonb_build_object('status','ok','offer_id', p_offer_id,'final_state','declined');
  end if;
  -- ACCEPT
  if not coalesce((select (c.value #>> '{}')::boolean from catalog.platform_config c
                    where c.key = 'feature.native_resale_enabled' order by c.version desc limit 1), false) then
    raise exception 'precondition_failed: feature_disabled';
  end if;
  if kernel.is_deletion_pending(v_o.buyer_id) then raise exception 'precondition_failed: deletion_pending (buyer)'; end if;   -- OR-17 F-2
  if v_l.status <> 'active' then raise exception 'precondition_failed: listing_not_active (%)', v_l.status; end if;
  if kernel.is_transfer_frozen(v_l.ticket_atom_id) then raise exception 'precondition_failed: frozen'; end if;
  if p_payment_id is null then raise exception 'payment_unverified: an accepted offer requires the buyer''s payment'; end if;
  select * into v_pay from public.payments p where p.id = p_payment_id;
  if not found or v_pay.buyer_id <> v_o.buyer_id or v_pay.status <> 'succeeded' then
    raise exception 'payment_unverified: payment does not belong to the offer''s buyer or is not succeeded';
  end if;
  -- ── PFA-30 FAIL-CLOSED PARK: the split INSERT point (market_sale with
  --    platform_fee / venue_royalty / seller_proceeds). No ratified fee rate,
  --    royalty basis or rounding bearer exists; nothing is guessed, nothing is
  --    written, custody does not move. Un-park = NATIVE_RESALE_SPLIT_POLICY.
  raise exception 'precondition_failed: resale_split_unavailable — no ratified native resale split policy (PFA-30); the offer stays pending, no sale row is written'
    using errcode = 'P0001';
end;
$$;

-- 6.7 market.mark_sale_paid_state (service_role; the resale-checkout webhook
--   branch). initiated → paid_pending_transfer under the listing → sale locks,
--   the payment re-verified as the sale buyer's succeeded row. Idempotent; a
--   payment landing on a CANCELLED sale returns state_conflict (non-raising)
--   with an idempotent money alert — the edge reverses it.
create or replace function market.mark_sale_paid_state(p_sale_id uuid, p_payment_id uuid, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_s market.market_sale%rowtype; v_pay public.payments%rowtype; v_sys constant uuid := '00000000-0000-0000-0000-0000000000f1'; v_reason text;
begin
  if p_command_key is null or length(trim(p_command_key)) = 0 then raise exception 'precondition_failed: command key required'; end if;
  select * into v_s from market.market_sale ms where ms.sale_id = p_sale_id;
  if not found then raise exception 'not_found: sale %', p_sale_id using errcode = 'P0002'; end if;
  perform 1 from market.listing_native l where l.listing_id = v_s.listing_id for update;         -- rank 4
  select * into v_s from market.market_sale ms where ms.sale_id = p_sale_id for update;
  select * into v_pay from public.payments p where p.id = p_payment_id;
  if not found or v_pay.buyer_id <> v_s.buyer_id or v_pay.status <> 'succeeded' then
    raise exception 'payment_unverified: payment does not belong to the sale buyer or is not succeeded';
  end if;
  -- true replay: the SAME payment on an already-paid sale.
  if v_s.sale_state in ('paid_pending_transfer','settled') and v_s.payment_id = p_payment_id then
    return jsonb_build_object('status','noop_replay','sale_id', p_sale_id,'sale_state', v_s.sale_state);
  end if;
  -- money landing where it cannot be consumed: NOT a raise (a raise would roll the
  -- alert back and make the webhook retry forever). One alert per (sale, payment);
  -- the result names the reversal action for the edge (E-107).
  v_reason := case
    when v_s.sale_state = 'cancelled'                                   then 'late_payment_on_cancelled'
    when v_s.terminal_state <> 'pending'                                then 'late_payment_on_terminal'
    when v_s.sale_state in ('paid_pending_transfer','settled')          then 'second_payment_on_paid_sale'   -- write-once (§20.8.7)
    when v_s.payment_intent_ref is not null
         and v_pay.stripe_payment_intent_id is distinct from v_s.payment_intent_ref then 'payment_intent_mismatch'  -- §20.8.9 binding
    when exists (select 1 from market.market_sale o where o.payment_id = p_payment_id and o.sale_id <> p_sale_id) then 'payment_reused'
    else null end;
  if v_reason is not null then
    if not exists (select 1 from kernel.admin_audit a where a.subject_id = p_sale_id and a.action = 'market_sale.alert'
                    and a.reason_code = v_reason and (a.after ->> 'payment_id') = p_payment_id::text) then
      insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
      values (v_sys, 'market_sale.alert', 'market_sale', p_sale_id, v_reason,
              jsonb_build_object('payment_id', p_payment_id, 'audience', 'platform_risk'));
    end if;
    return jsonb_build_object('status', case when v_reason = 'late_payment_on_cancelled' then 'state_conflict' else 'conflict_locked' end,
                              'sale_id', p_sale_id,'sale_state', v_s.sale_state,'reason', v_reason,'action','reverse_payment');
  end if;
  update market.market_sale
     set sale_state = 'paid_pending_transfer', paid_pending_since = now(), payment_id = p_payment_id, updated_at = now()
   where sale_id = p_sale_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_sys, 'market_sale.state_sync', 'market_sale', p_sale_id, p_command_key,
          jsonb_build_object('sale_state', v_s.sale_state), jsonb_build_object('sale_state','paid_pending_transfer','payment_id', p_payment_id));
  return jsonb_build_object('status','ok','sale_id', p_sale_id,'sale_state','paid_pending_transfer');
end;
$$;

-- 6.8 market.checkout_buy_now (R-37/OR-22). Validation order ① flag ② listing
--   status ③ mode ④ self ⑤ atom ⑥ freeze ⑦ split. F-2 rider: caller
--   DELETION_PENDING refused. ⑦ is the PFA-30 PARK POINT: the reservation row
--   IS the split-bearing market_sale INSERT, so the checkout fails closed before
--   any row exists — no reservation, no reserved listing, no PaymentIntent.
create or replace function market.checkout_buy_now(p_listing_id uuid, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_l market.listing_native%rowtype; v_t kernel.tickets%rowtype; v_ex uuid;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then raise exception 'precondition_failed: command key required'; end if;
  if kernel.is_deletion_pending(v_uid) then raise exception 'precondition_failed: deletion_pending'; end if;   -- OR-17 F-2 rider
  select ms.sale_id into v_ex from market.market_sale ms where ms.buyer_id = v_uid and ms.command_idempotency_key = p_command_key;
  if v_ex is not null then return jsonb_build_object('status','noop_replay','sale_id', v_ex); end if;
  if not coalesce((select (c.value #>> '{}')::boolean from catalog.platform_config c
                    where c.key = 'feature.native_resale_enabled' order by c.version desc limit 1), false) then
    raise exception 'precondition_failed: feature_disabled';                                          -- ①
  end if;
  select * into v_l from market.listing_native l where l.listing_id = p_listing_id for update;      -- rank 4
  if not found then raise exception 'not_found: listing %', p_listing_id using errcode = 'P0002'; end if;
  if v_l.status = 'reserved' then raise exception 'precondition_failed: listing_reserved'; end if;   -- ②
  if v_l.status <> 'active' then raise exception 'precondition_failed: listing_not_active (%)', v_l.status; end if;
  if v_l.listing_mode <> 'buy_now' then raise exception 'precondition_failed: not_buy_now (listing_mode %)', v_l.listing_mode; end if;   -- ③
  if v_l.seller_id = v_uid then raise exception 'precondition_failed: self_purchase'; end if;         -- ④
  select * into v_t from kernel.tickets t where t.ticket_atom_id = v_l.ticket_atom_id;               -- ⑤ (read; the engine locks)
  if v_t.state <> 'active' or v_t.resale_state <> 'listed' or v_t.current_owner_id <> v_l.seller_id then
    raise exception 'precondition_failed: conflict_locked (atom %/%)', v_t.state, v_t.resale_state;
  end if;
  if kernel.is_transfer_frozen(v_l.ticket_atom_id) then raise exception 'precondition_failed: frozen'; end if;   -- ⑥
  -- ── ⑦ PFA-30 FAIL-CLOSED PARK: the reservation = the split-bearing sale row.
  raise exception 'precondition_failed: resale_split_unavailable — no ratified native resale split policy (PFA-30); no reservation is taken'
    using errcode = 'P0001';
end;
$$;

-- 6.9 market.bind_checkout_payment_ref (service_role; resale-checkout edge).
--   Binds the PaymentIntent ref to an initiated sale; write-once.
create or replace function market.bind_checkout_payment_ref(p_sale_id uuid, p_payment_intent_ref text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_s market.market_sale%rowtype;
begin
  if p_payment_intent_ref is null or length(trim(p_payment_intent_ref)) = 0 then raise exception 'invalid_input: payment_intent_ref required'; end if;
  select * into v_s from market.market_sale ms where ms.sale_id = p_sale_id for update;
  if not found then raise exception 'not_found: sale %', p_sale_id using errcode = 'P0002'; end if;
  if v_s.payment_intent_ref = p_payment_intent_ref then return jsonb_build_object('status','noop_replay','sale_id', p_sale_id); end if;
  if v_s.payment_intent_ref is not null then raise exception 'precondition_failed: conflict_locked (sale % already bound to a payment intent — write-once)', p_sale_id; end if;
  if v_s.sale_state <> 'initiated' then raise exception 'state_conflict: sale % is %', p_sale_id, v_s.sale_state; end if;
  update market.market_sale set payment_intent_ref = p_payment_intent_ref, updated_at = now() where sale_id = p_sale_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values ('00000000-0000-0000-0000-0000000000f1', 'market_sale.bind_ref', 'market_sale', p_sale_id, coalesce(p_command_key,'bind'),
          jsonb_build_object('payment_intent_ref', p_payment_intent_ref));
  return jsonb_build_object('status','ok','sale_id', p_sale_id);
end;
$$;

-- 6.10 market.finalize_market_sale (SSCAS #2 "market checkout"; service_role —
--   the one completer body, webhook-prompt or sweep-late). Refuses while the
--   sale's payment has an OPEN dispute (R-40). Listing (4) → Sale (4) → the
--   engine (1 → 5 → 6). listing → sold, pending offers → withdrawn, sale_state →
--   settled; terminal_state is the engine's write. BE-emits purchase_confirmed.
create or replace function market.finalize_market_sale(p_sale_id uuid, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_s market.market_sale%rowtype; v_l market.listing_native%rowtype; v_res jsonb;
begin
  if p_command_key is null or length(trim(p_command_key)) = 0 then raise exception 'precondition_failed: command key required'; end if;
  select * into v_s from market.market_sale ms where ms.sale_id = p_sale_id;
  if not found then raise exception 'not_found: sale %', p_sale_id using errcode = 'P0002'; end if;
  perform 1 from catalog.event_session s where s.session_id = (select t.event_session_id from kernel.tickets t where t.ticket_atom_id = v_s.ticket_atom_id) for share;   -- rank 1
  select * into v_l from market.listing_native l where l.listing_id = v_s.listing_id for update;    -- rank 4
  select * into v_s from market.market_sale ms where ms.sale_id = p_sale_id for update;
  if v_s.terminal_state = 'completed' then
    return jsonb_build_object('status','noop_replay','sale_id', p_sale_id,'terminal_state','completed');
  end if;
  if v_s.terminal_state = 'compensated' then raise exception 'state_conflict: sale % was compensated', p_sale_id; end if;
  if v_s.sale_state = 'cancelled' then raise exception 'state_conflict: sale % is cancelled', p_sale_id; end if;
  if v_s.sale_state <> 'paid_pending_transfer' or v_s.payment_id is null then
    raise exception 'precondition_failed: not_paid (sale_state %)', v_s.sale_state;
  end if;
  if v_l.status <> 'reserved' then raise exception 'precondition_failed: listing % is % (reserved required)', v_l.listing_id, v_l.status; end if;
  if exists (select 1 from kernel.dispute_native d where d.payment_id = v_s.payment_id
              and d.status not in ('won','lost','warning_closed','charge_refunded')) then
    raise exception 'precondition_failed: open_dispute';                                           -- R-40
  end if;
  v_res := kernel.transfer_ticket_ownership(v_s.ticket_atom_id, v_s.buyer_id, 'market_sale', p_sale_id, v_s.payment_id, p_command_key);
  update market.listing_native set status = 'sold', updated_at = now() where listing_id = v_l.listing_id;
  update market.offer set status = 'withdrawn', updated_at = now() where listing_id = v_l.listing_id and status = 'pending';
  update market.market_sale set sale_state = 'settled', updated_at = now() where sale_id = p_sale_id;
  begin   -- BE
    perform notify.emit_event('purchase_confirmed', 'market_sale', p_sale_id, 'purchase_confirmed:' || p_sale_id::text,
              jsonb_build_object('atom_id', v_s.ticket_atom_id, 'credential_version', v_res -> 'credential_version'));
  exception when others then null; end;
  return jsonb_build_object('status','ok','sale_id', p_sale_id,'terminal_state','completed','credential_version', v_res -> 'credential_version');
end;
$$;

-- 6.11 market.cancel_buy_now_sale (service_role). initiated → cancelled ONLY;
--   the listing returns reserved → active when still reserved.
create or replace function market.cancel_buy_now_sale(p_sale_id uuid, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_s market.market_sale%rowtype;
begin
  if p_reason_code is null or p_reason_code not in ('buyer_released','reservation_expired','payment_failed','payment_cancelled') then
    raise exception 'invalid_input: reason_code must be buyer_released | reservation_expired | payment_failed | payment_cancelled';
  end if;
  select * into v_s from market.market_sale ms where ms.sale_id = p_sale_id;
  if not found then raise exception 'not_found: sale %', p_sale_id using errcode = 'P0002'; end if;
  perform 1 from market.listing_native l where l.listing_id = v_s.listing_id for update;            -- rank 4
  select * into v_s from market.market_sale ms where ms.sale_id = p_sale_id for update;
  if v_s.sale_state = 'cancelled' then return jsonb_build_object('status','noop_replay','sale_id', p_sale_id,'sale_state','cancelled'); end if;
  if v_s.sale_state <> 'initiated' then raise exception 'state_conflict: sale % is % — only an initiated checkout can be released', p_sale_id, v_s.sale_state; end if;
  update market.market_sale set sale_state = 'cancelled', updated_at = now() where sale_id = p_sale_id;
  update market.listing_native set status = 'active', updated_at = now() where listing_id = v_s.listing_id and status = 'reserved';
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values ('00000000-0000-0000-0000-0000000000f1', 'market_sale.state_sync', 'market_sale', p_sale_id, p_reason_code,
          jsonb_build_object('sale_state','initiated'), jsonb_build_object('sale_state','cancelled'));
  return jsonb_build_object('status','ok','sale_id', p_sale_id,'sale_state','cancelled','reason_code', p_reason_code);
end;
$$;

-- 6.12 market.list_lapsed_checkouts (read; service_role). STABLE.
create or replace function market.list_lapsed_checkouts(p_limit integer default 100)
returns table(sale_id uuid, listing_id uuid, payment_intent_ref text, reservation_expires_at timestamptz)
language sql stable security definer set search_path = ''
as $$
  select ms.sale_id, ms.listing_id, ms.payment_intent_ref, ms.reservation_expires_at
    from market.market_sale ms
   where ms.sale_state = 'initiated' and ms.reservation_expires_at is not null and ms.reservation_expires_at < now()
   order by ms.reservation_expires_at
   limit greatest(coalesce(p_limit, 100), 1)
$$;

-- 6.13 market.create_p2p_transfer (SSCAS #7 start). Owner-only; the policy
--   must not be 'off' (transfers_only admits a send); a PRICED send honours a
--   present cap. THE TTL IS UNNAMED in the frozen corpus (`expires_at :=
--   now()+TTL`, no key) — PFA-9/X-12: nothing is invented; after full
--   validation the verb FAILS CLOSED (p2p_ttl_unavailable) with zero mutation.
--   Un-park = P2P_TRANSFER_TTL (forward obligation).
create or replace function market.create_p2p_transfer(p_atom_id uuid, p_to_ref text, p_price_minor integer, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_t kernel.tickets%rowtype; v_ev record; v_pol record; v_tt record; v_cap bigint; v_ex uuid;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then raise exception 'precondition_failed: command key required'; end if;
  if p_to_ref is null or length(trim(p_to_ref)) = 0 then raise exception 'invalid_input: to_ref required'; end if;
  if p_price_minor is not null and p_price_minor <= 0 then raise exception 'invalid_input: price_minor must be > 0 or null (gift)'; end if;
  select p.transfer_id into v_ex from market.p2p_transfer p where p.from_identity = v_uid and p.command_idempotency_key = p_command_key;
  if v_ex is not null then return jsonb_build_object('status','noop_replay','transfer_id', v_ex); end if;
  select * into v_t from kernel.tickets t where t.ticket_atom_id = p_atom_id;
  if not found then raise exception 'not_found: atom %', p_atom_id using errcode = 'P0002'; end if;
  if v_t.current_owner_id <> v_uid then raise exception 'insufficient_privilege: only the current owner may transfer' using errcode = '42501'; end if;
  if v_t.state <> 'active' then raise exception 'precondition_failed: atom is %', v_t.state; end if;
  if v_t.resale_state <> 'none' then raise exception 'precondition_failed: conflict_locked (resale_state %)', v_t.resale_state; end if;
  if kernel.is_transfer_frozen(p_atom_id) then raise exception 'precondition_failed: frozen'; end if;
  select es.session_id, es.event_id, e.venue_id into v_ev
    from catalog.event_session es join catalog.event e on e.event_id = es.event_id where es.session_id = v_t.event_session_id;
  select rp.policy_id, rp.version, rp.mode, rp.price_cap_bps into v_pol
    from catalog.resale_policy rp
   where (rp.scope_kind = 'event' and rp.event_id = v_ev.event_id) or (rp.scope_kind = 'venue' and rp.venue_id = v_ev.venue_id)
   order by (rp.scope_kind = 'event') desc, rp.version desc limit 1;
  if not found or v_pol.mode = 'off' then raise exception 'precondition_failed: policy_violation (resale off)'; end if;
  if p_price_minor is not null then
    if v_pol.mode = 'fixed_cap' and v_pol.price_cap_bps is null then raise exception 'precondition_failed: policy_violation (fixed_cap policy carries no cap)'; end if;
    if v_pol.price_cap_bps is not null then
      select tt.price_minor into v_tt from venue.ticket_type tt where tt.ticket_type_id = v_t.ticket_type_id;
      v_cap := (v_tt.price_minor::bigint * v_pol.price_cap_bps) / 10000;
      if p_price_minor > v_cap then raise exception 'precondition_failed: policy_violation (price % exceeds cap %)', p_price_minor, v_cap; end if;
    end if;
  end if;
  -- ── PFA-9 / X-12 FAIL-CLOSED: no TTL key is named; expires_at cannot be derived.
  raise exception 'precondition_failed: p2p_ttl_unavailable — the p2p transfer TTL is unnamed in the frozen corpus (PFA-9/X-12); no transfer is opened'
    using errcode = 'P0001';
end;
$$;

-- 6.14 market.accept_p2p_transfer (SSCAS #8). The addressed recipient accepts
--   (custody moves via the engine, cause p2p_transfer, cause_ref transfer_id) or
--   DECLINES — §8.3's explicit decline owner is "accept_p2p_transfer with
--   p_decision='decline'", so the third parameter is DEFAULTED to 'accept'
--   (E-99: the two-argument §8.2 shape stays callable; overload count 1). F-4:
--   a DELETION_PENDING recipient may not accept (decline stays allowed). A
--   handle-addressed transfer has no ratified resolver — refused (E-100). A PRICED
--   acceptance has no contracted payment binding — refused payment_unverified
--   (E-101); gifts complete. Session FOR SHARE (1) → Transfer (4) → engine (5, 6).
create or replace function market.accept_p2p_transfer(p_transfer_id uuid, p_command_key text, p_decision text default 'accept')
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_p market.p2p_transfer%rowtype; v_session uuid; v_res jsonb;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then raise exception 'precondition_failed: command key required'; end if;
  if p_decision is null or p_decision not in ('accept','decline') then raise exception 'invalid_input: decision must be accept | decline'; end if;
  select * into v_p from market.p2p_transfer p where p.transfer_id = p_transfer_id;
  if not found then raise exception 'not_found: transfer %', p_transfer_id using errcode = 'P0002'; end if;
  select t.event_session_id into v_session from kernel.tickets t where t.ticket_atom_id = v_p.ticket_atom_id;
  perform 1 from catalog.event_session s where s.session_id = v_session for share;               -- rank 1
  select * into v_p from market.p2p_transfer p where p.transfer_id = p_transfer_id for update;    -- rank 4
  if v_p.to_identity is null then
    raise exception 'precondition_failed: handle_resolution_unavailable — a handle-addressed transfer has no ratified resolver (E-100)';
  end if;
  if v_p.to_identity <> v_uid then raise exception 'insufficient_privilege: addressed recipient only' using errcode = '42501'; end if;
  if v_p.status <> 'initiated' then
    if (v_p.status in ('accepted','completed') and p_decision = 'accept') or (v_p.status = 'declined' and p_decision = 'decline') then
      return jsonb_build_object('status','noop_replay','transfer_id', p_transfer_id,'final_state', v_p.status,'atom_id', v_p.ticket_atom_id);
    end if;
    raise exception 'state_conflict: transfer % is %', p_transfer_id, v_p.status;
  end if;
  if v_p.expires_at is not null and v_p.expires_at <= now() then raise exception 'precondition_failed: expired'; end if;
  if p_decision = 'decline' then
    update market.p2p_transfer set status = 'declined', reason_code = 'recipient_declined', updated_at = now() where transfer_id = p_transfer_id;
    perform kernel.unlock_ticket(v_p.ticket_atom_id, p_command_key);                                -- rank 5 (PFA-13 re-arm)
    return jsonb_build_object('status','ok','transfer_id', p_transfer_id,'final_state','declined','atom_id', v_p.ticket_atom_id);
  end if;
  if kernel.is_deletion_pending(v_uid) then raise exception 'precondition_failed: deletion_pending'; end if;   -- OR-17 F-4
  if kernel.is_transfer_frozen(v_p.ticket_atom_id) then raise exception 'precondition_failed: frozen'; end if;
  if v_p.price_minor is not null then
    raise exception 'payment_unverified: a priced p2p acceptance has no contracted payment binding (E-101) — refused';
  end if;
  v_res := kernel.transfer_ticket_ownership(v_p.ticket_atom_id, v_uid, 'p2p_transfer', p_transfer_id, null, p_command_key);
  update market.p2p_transfer set status = 'completed', updated_at = now() where transfer_id = p_transfer_id;
  return jsonb_build_object('status','ok','transfer_id', p_transfer_id,'final_state','completed','atom_id', v_p.ticket_atom_id,
                            'credential_version', v_res -> 'credential_version');
end;
$$;

-- 6.15 market.cancel_p2p_transfer (owns `expired`). The sender cancels; the
--   definer sweep (no auth.uid()) may ONLY write 'expired'. The recipient is
--   refused (they decline). Releases through kernel.unlock_ticket (PFA-13).
create or replace function market.cancel_p2p_transfer(p_transfer_id uuid, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_p market.p2p_transfer%rowtype; v_final text;
begin
  if p_command_key is null or length(trim(p_command_key)) = 0 then raise exception 'precondition_failed: command key required'; end if;
  select * into v_p from market.p2p_transfer p where p.transfer_id = p_transfer_id for update;    -- rank 4
  if not found then raise exception 'not_found: transfer %', p_transfer_id using errcode = 'P0002'; end if;
  if v_uid is null then
    if coalesce(p_reason_code,'') <> 'expired' then
      raise exception 'insufficient_privilege: the definer arm may only expire' using errcode = '42501';
    end if;
    if v_p.status = 'initiated' and (v_p.expires_at is null or v_p.expires_at > now()) then
      raise exception 'precondition_failed: transfer % has not lapsed', p_transfer_id;   -- §8.3: expired = TTL-lapsed rows only
    end if;
  elsif v_p.from_identity <> v_uid then
    raise exception 'insufficient_privilege: sender only (the recipient declines)' using errcode = '42501';
  elsif p_reason_code is not null and (p_reason_code !~ '^[A-Za-z0-9._:-]{1,64}$' or p_reason_code in ('expired','door_freeze','event_cancelled')) then
    raise exception 'invalid_input: reason_code must be 1-64 chars of [A-Za-z0-9._:-] and not a system reason';
  end if;
  v_final := case when p_reason_code = 'expired' then 'expired' else 'cancelled' end;
  if v_p.status <> 'initiated' then
    if v_p.status = v_final then return jsonb_build_object('status','noop_replay','transfer_id', p_transfer_id,'final_state', v_p.status); end if;
    raise exception 'state_conflict: transfer % is %', p_transfer_id, v_p.status;
  end if;
  update market.p2p_transfer set status = v_final, reason_code = coalesce(p_reason_code,'sender_cancel'), updated_at = now()
   where transfer_id = p_transfer_id;
  perform kernel.unlock_ticket(v_p.ticket_atom_id, p_command_key);                                  -- rank 5
  return jsonb_build_object('status','ok','transfer_id', p_transfer_id,'final_state', v_final);
end;
$$;

-- 6.16 market.sweep_expired_p2p_transfers (definer batch; recon #1). Per row
--   Transfer → Atom ascending via cancel_p2p_transfer('expired'); SECOND
--   STATEMENT: pending offers past expires_at → expired (presentational).
create or replace function market.sweep_expired_p2p_transfers()
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_r record; v_n integer := 0; v_err integer := 0; v_o integer;
begin
  for v_r in select p.transfer_id from market.p2p_transfer p
              where p.status = 'initiated' and p.expires_at is not null and p.expires_at < now()
              order by p.ticket_atom_id limit 500 loop
    begin   -- one row's conflict (a concurrent accept/cancel) never aborts the tick
      perform market.cancel_p2p_transfer(v_r.transfer_id, 'expired', 'sweep:' || v_r.transfer_id::text);
      v_n := v_n + 1;
    exception when others then v_err := v_err + 1; end;
  end loop;
  update market.offer set status = 'expired', updated_at = now() where status = 'pending' and expires_at is not null and expires_at < now();
  get diagnostics v_o = row_count;
  return jsonb_build_object('swept_count', v_n, 'errors', v_err, 'offers_expired', v_o);
end;
$$;

-- 6.17 market.sweep_paid_pending_sales (definer batch; C25). THE DWELL SLO IS
--   UNNAMED ("named in the Edge/ops spec" — no key in the frozen corpus): PFA-9/
--   X-12 — the tick is INERT (selects nothing, writes nothing) and says so. The
--   webhook-prompt completer (finalize_market_sale) is unaffected. Un-park =
--   PAID_PENDING_DWELL_SLO (forward obligation). Signature frozen.
create or replace function market.sweep_paid_pending_sales()
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  return jsonb_build_object('completed', 0, 'compensated', 0, 'status', 'inert', 'reason', 'dwell_slo_unnamed');
end;
$$;

-- 6.18 market.get_ticket_history (read; §1.2). Current owner only. Plain verbs,
--   no cause-codes, no keys, no versions, no counterpart identity.
create or replace function market.get_ticket_history(p_ticket_atom_id uuid)
returns table(sequence integer, verb text, occurred_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_owner uuid;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  select t.current_owner_id into v_owner from kernel.tickets t where t.ticket_atom_id = p_ticket_atom_id;
  if v_owner is null then raise exception 'not_found: atom %', p_ticket_atom_id using errcode = 'P0002'; end if;
  if v_owner <> v_uid then raise exception 'insufficient_privilege: current owner only' using errcode = '42501'; end if;
  return query
    select l.sequence,
           case l.cause
             when 'issue' then case coalesce(l.state_transition ->> 'mint_cause', 'issue')
                                 when 'comp' then 'received' when 'import' then 'imported' else 'bought' end
             when 'market_sale'   then case when l.to_identity = v_uid then 'bought' else 'sold' end
             when 'auction_sale'  then case when l.to_identity = v_uid then 'bought' else 'sold' end
             when 'p2p_transfer'  then case when l.to_identity = v_uid then 'transferred to you' else 'you transferred' end
             when 'refund_void'   then 'refunded'
             when 'admin_action'  then 'adjusted'
             else 'transferred' end,
           l.occurred_at
      from kernel.ticket_ownership_log l
     where l.ticket_atom_id = p_ticket_atom_id
    union all
    select 2147483647, 'listed', ln.created_at
      from market.listing_native ln
     where ln.ticket_atom_id = p_ticket_atom_id and ln.status in ('active','reserved') and ln.seller_id = v_uid
    order by 1, 3;
end;
$$;

-- 6.19 market.get_market_sale_status (read; §1.4). Buyer or seller. The three
--   fields ONLY — no cause-codes, no split, no counterpart.
create or replace function market.get_market_sale_status(p_sale_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_s market.market_sale%rowtype;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  select * into v_s from market.market_sale ms where ms.sale_id = p_sale_id;
  if not found then raise exception 'not_found: sale %', p_sale_id using errcode = 'P0002'; end if;
  if v_uid not in (v_s.buyer_id, v_s.seller_id) then raise exception 'insufficient_privilege: buyer or seller only' using errcode = '42501'; end if;
  return jsonb_build_object('terminal_state', v_s.terminal_state, 'sale_state', v_s.sale_state, 'paid_pending_since', v_s.paid_pending_since);
end;
$$;

-- ============================================================================
-- PART 7 — catalog.cancel_event (RPC §4.4; a bounded batch of SSCAS #3).
--   org_owner/org_admin · venue_manager · platform_admin. Event/Session FOR
--   UPDATE (1) → market drain (4 → 5 via unlock) → per ISSUED atom ascending:
--   one kernel.refund per originating ORDER (reason event_cancelled, amount = Σ
--   order-item unit prices of the atoms voided here, §11.4 sum-guarded against
--   prior refunds) → kernel.void_ticket_atom (which returns capacity, appends the
--   revoke delta and runs the C26 compensate hook). Atoms with NO refund lineage
--   (comp / import mints — no order item) are NOT voided: an event cancellation
--   is a void+refund cascade and nothing is refundable, so they are skipped and
--   alerted (E-102) — the cancelled session already denies their scan. Re-entrant.
--   REQUIRED-emits event_cancelled (once) and refund_requested (per refund).
-- ============================================================================
create or replace function catalog.cancel_event(p_event_id uuid, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid(); v_e catalog.event%rowtype; v_s record; v_a record; v_r record; v_ms record; v_atom uuid;
  v_voided integer := 0; v_refunds integer := 0; v_skipped integer := 0; v_refund_id uuid; v_prior bigint; v_total bigint; v_amt bigint; v_res jsonb;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-] (it lands in the immutable audit)';
  end if;
  if p_reason_code is not null and p_reason_code !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: reason_code must be 1-64 chars of [A-Za-z0-9._:-]';
  end if;
  select * into v_e from catalog.event e where e.event_id = p_event_id;
  if not found then raise exception 'not_found: event %', p_event_id using errcode = 'P0002'; end if;
  -- E-76: a venue-role arm also requires the venue's CURRENT operator to be the event's org.
  if not (kernel.has_org_role(v_e.org_id, array['org_owner','org_admin'])
          or (kernel.has_venue_role(v_e.venue_id, array['venue_manager'])
              and exists (select 1 from catalog.venue v where v.venue_id = v_e.venue_id and v.org_id = v_e.org_id))
          or kernel.is_platform(array['platform_admin'])) then
    raise exception 'insufficient_privilege: org_owner / org_admin / venue_manager (current operator) / platform_admin only' using errcode = '42501';
  end if;
  select * into v_e from catalog.event e where e.event_id = p_event_id for update;              -- rank 1
  for v_s in select es.session_id from catalog.event_session es where es.event_id = p_event_id order by es.session_id for update loop
    perform 1 from venue.inventory_batch b where b.event_session_id = v_s.session_id for update;   -- rank 2 (Inventory before Atom — §14.2)
    -- market drain (reason event_cancelled) — every open native machine on the session (rank 4 → 5).
    for v_r in select p.transfer_id, p.ticket_atom_id from market.p2p_transfer p join kernel.tickets t on t.ticket_atom_id = p.ticket_atom_id
                where t.event_session_id = v_s.session_id and p.status = 'initiated' order by p.ticket_atom_id for update of p loop
      update market.p2p_transfer set status = 'cancelled', reason_code = 'event_cancelled', updated_at = now() where transfer_id = v_r.transfer_id;
      perform kernel.unlock_ticket(v_r.ticket_atom_id, p_command_key || ':t:' || v_r.transfer_id::text);
    end loop;
    for v_r in select l.listing_id, l.ticket_atom_id from market.listing_native l join kernel.tickets t on t.ticket_atom_id = l.ticket_atom_id
                where t.event_session_id = v_s.session_id and l.status in ('active','reserved') order by l.ticket_atom_id for update of l loop
      update market.listing_native set status = 'cancelled', reason_code = 'event_cancelled', updated_at = now() where listing_id = v_r.listing_id;
      update market.offer set status = 'withdrawn', updated_at = now() where listing_id = v_r.listing_id and status = 'pending';
      update market.auction set status = 'cancelled', updated_at = now() where listing_id = v_r.listing_id and status = 'active';
      perform kernel.unlock_ticket(v_r.ticket_atom_id, p_command_key || ':l:' || v_r.listing_id::text);
    end loop;
    -- RESALE BUYERS FIRST: every PAID, untransferred native sale on the session gets its refund
    -- intent under the payment lock (rank 6) BEFORE the void, so the C26 hook can compensate
    -- (compensated ⇔ the buyer's money carries a refund — never a stranded 'compensated').
    for v_ms in select ms.sale_id, ms.payment_id, ms.price_minor from market.market_sale ms join kernel.tickets t on t.ticket_atom_id = ms.ticket_atom_id
                 where t.event_session_id = v_s.session_id and ms.sale_state = 'paid_pending_transfer' and ms.terminal_state = 'pending' and ms.payment_id is not null
                 order by ms.sale_id for update of ms loop
      perform 1 from public.payments p where p.id = v_ms.payment_id for update;
      select p.total into v_total from public.payments p where p.id = v_ms.payment_id;
      select coalesce(sum(r.amount_minor), 0) + coalesce((select sum(d.amount_minor) from kernel.dispute_native d
                                                            where d.payment_id = v_ms.payment_id and d.status in ('lost','charge_refunded')), 0)
        into v_prior from kernel.refund r where r.payment_id = v_ms.payment_id and r.status <> 'failed';
      v_amt := least(v_ms.price_minor::bigint, greatest(v_total - v_prior, 0));
      if v_amt > 0 then
        insert into kernel.refund (payment_id, reason_code, amount_minor, currency, idempotency_key)
        values (v_ms.payment_id, 'event_cancelled', v_amt, 'USD', p_command_key || ':sale:' || v_ms.sale_id::text)
        on conflict (idempotency_key) do nothing
        returning refund_id into v_refund_id;
        if v_refund_id is not null then
          v_refunds := v_refunds + 1;
          perform notify.emit_event_required('refund_requested', 'refund', v_refund_id, 'refund_requested:' || v_refund_id::text,
                    jsonb_build_object('event_id', p_event_id, 'sale_id', v_ms.sale_id, 'amount_minor', v_amt, 'reason', 'event_cancelled'));
        end if;
      end if;
    end loop;
    -- PRIMARY ORDERS: one refund per originating order (amount = Σ voided item prices, §11.4-guarded
    -- against prior refunds AND lost/charge_refunded disputes, operand = the payment's total).
    -- The refund id is fixed BEFORE the voids and the row is inserted AFTER them (Atom 5 → Refund 6).
    for v_r in
      select o.order_id, pn.payment_id, pn.currency,
             array_agg(t.ticket_atom_id order by t.ticket_atom_id) as atoms, sum(oi.unit_price_minor)::bigint as amount
        from kernel.tickets t
        join kernel.ticket_ownership_log l1 on l1.ticket_atom_id = t.ticket_atom_id and l1.sequence = 1 and l1.cause = 'issue'
        join venue.order_item oi on oi.id = l1.cause_ref
        join venue."order" o on o.order_id = oi.order_id
        join kernel.payment_native pn on pn.order_id = o.order_id
       where t.event_session_id = v_s.session_id and t.state in ('issued','active')
       group by o.order_id, pn.payment_id, pn.currency
       order by o.order_id loop
      select r.refund_id into v_refund_id from kernel.refund r where r.idempotency_key = p_command_key || ':order:' || v_r.order_id::text;
      if v_refund_id is null then
        -- pre-void read of the guard (the re-check under the payment lock follows the voids)
        select p.total into v_total from public.payments p where p.id = v_r.payment_id;
        select coalesce(sum(r.amount_minor), 0) + coalesce((select sum(d.amount_minor) from kernel.dispute_native d
                                                              where d.payment_id = v_r.payment_id and d.status in ('lost','charge_refunded')), 0)
          into v_prior from kernel.refund r where r.payment_id = v_r.payment_id and r.status <> 'failed';
        v_amt := least(v_r.amount, greatest(v_total - v_prior, 0));
        if v_amt <= 0 then
          -- the money already went back (refunds and/or a chargeback): nothing to refund, so no void
          -- rides a refund that does not exist — skipped + audited (the held/disputed atom stays as it is).
          v_skipped := v_skipped + coalesce(array_length(v_r.atoms, 1), 0);
          insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
          values (v_uid, 'event.cancel_skip', 'order', v_r.order_id, 'money_already_returned',
                  jsonb_build_object('event_id', p_event_id, 'atoms', to_jsonb(v_r.atoms), 'prior_minor', v_prior, 'total_minor', v_total));
          continue;
        end if;
        v_refund_id := gen_random_uuid();
      else
        v_amt := 0;   -- replay: the refund row already exists; only re-void what is still live
      end if;
      foreach v_atom in array v_r.atoms loop
        v_res := kernel.void_ticket_atom(v_atom, v_refund_id, p_command_key);                  -- rank 5 → hook → ledger → head
        if coalesce(v_res ->> 'status', '') = 'ok' then v_voided := v_voided + 1; end if;
      end loop;
      if v_amt > 0 then
        perform 1 from public.payments p where p.id = v_r.payment_id for update;                 -- rank 6: the guard re-checked under the lock
        select p.total into v_total from public.payments p where p.id = v_r.payment_id;
        select coalesce(sum(r.amount_minor), 0) + coalesce((select sum(d.amount_minor) from kernel.dispute_native d
                                                              where d.payment_id = v_r.payment_id and d.status in ('lost','charge_refunded')), 0)
          into v_prior from kernel.refund r where r.payment_id = v_r.payment_id and r.status <> 'failed';
        if v_amt > greatest(v_total - v_prior, 0) then
          raise exception 'precondition_failed: refund_sum_guard — payment % headroom changed concurrently (retry)', v_r.payment_id;
        end if;
        insert into kernel.refund (refund_id, payment_id, reason_code, amount_minor, currency, idempotency_key)
        values (v_refund_id, v_r.payment_id, 'event_cancelled', v_amt, coalesce(v_r.currency,'USD'), p_command_key || ':order:' || v_r.order_id::text);
        v_refunds := v_refunds + 1;
        perform notify.emit_event_required('refund_requested', 'refund', v_refund_id, 'refund_requested:' || v_refund_id::text,
                  jsonb_build_object('event_id', p_event_id, 'order_id', v_r.order_id, 'amount_minor', v_amt, 'reason', 'event_cancelled'));
      end if;
    end loop;
    -- atoms with no refund lineage (comp / import): not voided, alerted (E-102).
    for v_a in select t.ticket_atom_id from kernel.tickets t
                where t.event_session_id = v_s.session_id and t.state in ('issued','active')
                  and not exists (select 1 from kernel.ticket_ownership_log l1 join venue.order_item oi on oi.id = l1.cause_ref
                                   where l1.ticket_atom_id = t.ticket_atom_id and l1.sequence = 1 and l1.cause = 'issue')
                order by t.ticket_atom_id loop
      v_skipped := v_skipped + 1;
      if not exists (select 1 from kernel.admin_audit a where a.subject_id = v_a.ticket_atom_id and a.action = 'event.cancel_skip' and a.reason_code = 'no_refund_lineage') then
        insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
        values (v_uid, 'event.cancel_skip', 'ticket_atom', v_a.ticket_atom_id, 'no_refund_lineage', jsonb_build_object('event_id', p_event_id));
      end if;
    end loop;
    update catalog.event_session set status = 'cancelled', updated_at = now() where session_id = v_s.session_id and status <> 'cancelled';
  end loop;
  if v_e.status = 'cancelled' and v_voided = 0 and v_refunds = 0 then
    return jsonb_build_object('status','noop_replay','event_id', p_event_id,'atoms_voided', 0,'refunds_created', 0);
  end if;
  update catalog.event set status = 'cancelled', updated_at = now() where event_id = p_event_id and status <> 'cancelled';
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'event.cancel', 'event', p_event_id, coalesce(p_reason_code,'event_cancelled'),
          jsonb_build_object('status', v_e.status),
          jsonb_build_object('status','cancelled','atoms_voided', v_voided,'refunds_created', v_refunds,'atoms_skipped', v_skipped));
  if v_e.status <> 'cancelled' then
    perform notify.emit_event_required('event_cancelled', 'event', p_event_id, 'event_cancelled:' || p_event_id::text,
              jsonb_build_object('reason_code', coalesce(p_reason_code,'event_cancelled'), 'atoms_voided', v_voided));
  end if;
  return jsonb_build_object('status','ok','event_id', p_event_id,'atoms_voided', v_voided,'refunds_created', v_refunds,'atoms_skipped', v_skipped);
end;
$$;

-- ============================================================================
-- PART 8 — EXECUTE grants (RLS §11 / RPC §20.8 EXEC lines). Every new routine:
--   REVOKE from PUBLIC/anon first, then the exact grantee. The seven SEAM-2 /
--   PFA-13 bodies keep the ACLs their stubs were granted (CREATE OR REPLACE
--   preserves ACLs) — asserted by the suite, not re-granted here.
-- ============================================================================
do $$
declare r text;
begin
  foreach r in array array[
    'market.create_listing(uuid,integer,text,text)', 'market.cancel_listing(uuid,text,text)',
    'market.create_auction(uuid,integer,integer,integer,timestamptz,text)', 'market.place_bid(uuid,integer,text)',
    'market.make_offer(uuid,integer,timestamptz,text)', 'market.respond_offer(uuid,text,uuid,text)',
    'market.mark_sale_paid_state(uuid,uuid,text)', 'market.checkout_buy_now(uuid,text)',
    'market.bind_checkout_payment_ref(uuid,text,text)', 'market.finalize_market_sale(uuid,text)',
    'market.cancel_buy_now_sale(uuid,text,text)', 'market.list_lapsed_checkouts(integer)',
    'market.create_p2p_transfer(uuid,text,integer,text)', 'market.accept_p2p_transfer(uuid,text,text)',
    'market.cancel_p2p_transfer(uuid,text,text)', 'market.sweep_expired_p2p_transfers()', 'market.sweep_paid_pending_sales()',
    'market.get_ticket_history(uuid)', 'market.get_market_sale_status(uuid)',
    'kernel.transfer_ticket_ownership(uuid,uuid,text,uuid,uuid,text)',
    'kernel.record_dispute_native(text,text,text,integer,text,text,text,timestamptz,text)',
    'kernel.mark_dispute_state(text,text,text)', 'kernel.resolve_dispute_native(uuid,text,text,text)',
    'catalog.cancel_event(uuid,text,text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', r);
  end loop;
end $$;
grant execute on function market.create_listing(uuid,integer,text,text)                                   to authenticated;
grant execute on function market.cancel_listing(uuid,text,text)                                           to authenticated;
grant execute on function market.create_auction(uuid,integer,integer,integer,timestamptz,text)            to authenticated;
grant execute on function market.place_bid(uuid,integer,text)                                             to authenticated;
grant execute on function market.make_offer(uuid,integer,timestamptz,text)                                to authenticated;
grant execute on function market.respond_offer(uuid,text,uuid,text)                                       to authenticated;
grant execute on function market.checkout_buy_now(uuid,text)                                              to authenticated;
grant execute on function market.create_p2p_transfer(uuid,text,integer,text)                              to authenticated;
grant execute on function market.accept_p2p_transfer(uuid,text,text)                                      to authenticated;
grant execute on function market.cancel_p2p_transfer(uuid,text,text)                                      to authenticated, service_role;
grant execute on function market.get_ticket_history(uuid)                                                 to authenticated;
grant execute on function market.get_market_sale_status(uuid)                                             to authenticated;
grant execute on function catalog.cancel_event(uuid,text,text)                                            to authenticated;
grant execute on function kernel.resolve_dispute_native(uuid,text,text,text)                              to authenticated;
grant execute on function market.mark_sale_paid_state(uuid,uuid,text)                                     to service_role;
grant execute on function market.bind_checkout_payment_ref(uuid,text,text)                                to service_role;
grant execute on function market.finalize_market_sale(uuid,text)                                          to service_role;
grant execute on function market.cancel_buy_now_sale(uuid,text,text)                                      to service_role;
grant execute on function market.list_lapsed_checkouts(integer)                                           to service_role;
grant execute on function market.sweep_expired_p2p_transfers()                                            to service_role;
grant execute on function market.sweep_paid_pending_sales()                                               to service_role;
grant execute on function kernel.transfer_ticket_ownership(uuid,uuid,text,uuid,uuid,text)                 to service_role;
grant execute on function kernel.record_dispute_native(text,text,text,integer,text,text,text,timestamptz,text) to service_role;
grant execute on function kernel.mark_dispute_state(text,text,text)                                       to service_role;

-- ============================================================================
-- PART 9 — cron (plan §8/088; CRON_SCHEDULE_REGISTER rows 088). Two pure-DB
--   ticks every 2 minutes: the p2p/offer expiry sweep (recon #1; the offer arm
--   is presentational — respond_offer's arithmetic is the enforcement) and the
--   C25 paid-pending sweep (INERT until PAID_PENDING_DWELL_SLO names the bound).
--   The resale-checkout /sweep-lapsed edge tick (R-37) is NOT scheduled here: the
--   087 pattern posts only under a Vault-named second-factor secret sent in a
--   dedicated header; the Edge spec names the worker's ENV var
--   (INTERNAL_CRON_SECRET, §3 "copy notify-dispatch") but no Vault secret name
--   and no header name exist in any byte, and notify-dispatch's tick is not in
--   migration bytes either — PFA-9/E-79: nothing is invented, so no tick is armed
--   (RESALE_CHECKOUT_SWEEP_TICK). Nothing is lost: checkout_buy_now is parked
--   (PFA-30), so no initiated reservation can exist for the tick to release.
-- ============================================================================
select cron.schedule('market-sweep-expired-p2p-transfers', '*/2 * * * *', $$select market.sweep_expired_p2p_transfers();$$)
 where not exists (select 1 from cron.job where jobname = 'market-sweep-expired-p2p-transfers');   -- idempotent re-apply
select cron.schedule('market-sweep-paid-pending-sales',    '*/2 * * * *', $$select market.sweep_paid_pending_sales();$$)
 where not exists (select 1 from cron.job where jobname = 'market-sweep-paid-pending-sales');

commit;

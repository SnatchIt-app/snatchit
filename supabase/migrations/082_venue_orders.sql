-- ============================================================================
-- 082_venue_orders.sql — PHASE 2, PACKAGE 082 (family F — orders)
--
-- Frozen baseline: phase2-architecture-v2 (06fd5ec). Branch base: 262a716 (080/081
-- merged). Migrations 076–081 are hash-locked and untouched.
--
-- WHAT THIS PACKAGE IS (derived from plan §8/082, registry row 082, schema
-- §3.7/§3.8/§1.15.2/§13.2, RPC §6.1/§20.7.9/§17.21, RLS §9.7/§9.8/§16.6/§16.10,
-- CRM §11.2, dsm §2 BP-12/§3.2 F-1, ODR16, PARITY_SPEC 082):
--
--   the primary-purchase ORDER container. `venue.create_primary_checkout` builds a
--   `pending` order + immutable order_items from inventory the buyer already HELD
--   (081). NO money moves here and NO atoms are minted here — the paid-order
--   finalize (SSCAS #1, `venue.finalize_primary_order`) and the mint engine
--   (`kernel.issue_ticket_atoms`) are LATER packages (085 / 083). This package owns
--   the container they will write, plus the per-org CRM contact-consent surface.
--
-- DARK: native issuance and Buy Now stay OFF. The purchase rail is dark because a
--   checkout can only be built from live `venue.inventory_hold` rows, and 081
--   refuses hold creation while `feature.native_issuance_enabled` is false (E-28).
--   No mint path exists (issue_ticket_atoms is 083; finalize is 085). So no order
--   can be created, and none could be finalized even if it were. §6.1 defines no
--   independent native-issuance gate on checkout, and adding one would deviate from
--   the frozen contract — the darkness is enforced at the 081 hold layer.
--
-- OBJECTS (PARITY_SPEC 082 required = 8: 4 tables + create_primary_checkout +
--   cancel_pending_order + grant_/withdraw_org_contact_consent; plus, authored per
--   plan §8/082 + CRM §11.1-8 + RPC §17.21, list_my_org_contact_consents [E-35];
--   plus the 2 bespoke trigger fns and the SEAM-2 body replacement):
--     tables      venue.order, venue.order_item, kernel.org_contact_consent,
--                 kernel.org_contact_consent_event
--     functions   venue.create_primary_checkout, venue.cancel_pending_order,
--                 kernel.grant_org_contact_consent, kernel.withdraw_org_contact_consent,
--                 kernel.list_my_org_contact_consents
--     hook body   kernel.deletion_blockers_orders  (CREATE OR REPLACE; born 077;
--                 BP-12 pending-order arm — SEAM-2)
--     triggers    order_item IMM-after-issuance guard; order attribution-candidate
--                 freeze guard; set_updated_at ×2; raise_append_only ×1
--     policies    6 SELECT (order ×3, order_item ×3); consent tables deny-all/zero-policy
--     cron        NONE
--
-- RESERVED WORD: `order` is a SQL reserved keyword, so the table is created and
--   referenced as venue."order" throughout. venue.order_item is not reserved.
--
-- E-23 (governance register): `kernel.is_deletion_pending` returns FALSE for an
--   ERASED identity, so it is NOT a complete recipient-validity gate. Package 082
--   is one of the acquisition engines (082/085/088). `create_primary_checkout` is
--   the checkout-buyer entry verb (dsm §3.2 F-1), so it proves the buyer ACTIVE:
--   the F-1 pending refusal PLUS an explicit ERASED refusal, using the SAME idiom
--   077's F-6 gate uses (the E-8 defensive twin). buyer_id = auth.uid() (no client
--   buyer parameter exists), and an ERASED identity cannot authenticate, so the
--   ERASED arm is defensive — mandated present, as E-23 requires ("cannot be
--   discharged by is_deletion_pending alone"). E-23 remains forward for 085/088.
--
-- OR-17: this package replaces the neutral 077 stub kernel.deletion_blockers_orders
--   with the BP-12 pending-order arm ONLY (any venue.order buyer_id=:id status=
--   'pending'). The BP-12 refund/paid-window arm is kernel.deletion_blockers_money
--   (085) — kernel.refund does not exist here, so 082 cannot and must not test it.
--
-- R2B/C112: the two venue.order.attribution_candidate_* columns are BORN here as
--   plain uuid NULL (their FK targets venue.promoter_code/_link are 090). 090 adopts
--   the FKs (NOT VALID + VALIDATE). At 082 they are INERT (no promoter tables exist
--   to reference), so create_primary_checkout leaves them NULL — no forward
--   reference. The candidate-freeze guard is authored here with the columns.
--   (Schema §13.2's parity row still credits these to 090 — E-34, stale; the
--   governing R2B/C112 ruling births them here.)
-- ============================================================================

begin;

-- ============================================================================
-- PART 1 — venue."order" (schema §3.7)
-- ============================================================================
create table if not exists venue."order" (
  order_id                       uuid primary key default gen_random_uuid(),
  buyer_id                       uuid not null references auth.users(id) on delete restrict,
  event_session_id               uuid not null references catalog.event_session(session_id) on delete restrict,
  org_id                         uuid not null references kernel.organization(org_id) on delete restrict,
  status                         text not null default 'pending'
                                 check (status in ('pending','paid','partially_refunded','refunded','cancelled')),
  source                         text not null
                                 check (source in ('app','web','door','promoter_link')),
  total_minor                    integer not null check (total_minor > 0),
  currency                       text not null default 'USD',
  command_idempotency_key        text not null,
  -- R2B/C112: born here as plain uuid NULL; FK targets (venue.promoter_code /
  -- venue.promoter_link) are created in 090, which ADOPTS these FKs. Inert (NULL)
  -- until 090 — create_primary_checkout does not populate them at this package.
  attribution_candidate_code_id  uuid,
  attribution_candidate_link_id  uuid,
  created_at                     timestamptz not null default now(),
  updated_at                     timestamptz not null default now(),
  constraint order_buyer_command_uq unique (buyer_id, command_idempotency_key)   -- C16
);

create index if not exists order_buyer_idx    on venue."order" (buyer_id);
create index if not exists order_session_idx  on venue."order" (event_session_id);
create index if not exists order_org_status_idx on venue."order" (org_id, status);

drop trigger if exists tg_order_updated_at on venue."order";
create trigger tg_order_updated_at
  before update on venue."order"
  for each row execute function kernel.set_updated_at();

-- Attribution-candidate freeze guard (R2B/C112): the two candidate columns are
-- mutable ONLY while status='pending' and freeze the instant the order leaves it.
create or replace function venue.guard_order_candidate_freeze()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if old.status <> 'pending'
     and (new.attribution_candidate_code_id is distinct from old.attribution_candidate_code_id
          or new.attribution_candidate_link_id is distinct from old.attribution_candidate_link_id) then
    raise exception 'append_only: order attribution candidate is frozen once the order leaves pending (status=%)', old.status
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists tg_order_candidate_freeze on venue."order";
create trigger tg_order_candidate_freeze
  before update on venue."order"
  for each row execute function venue.guard_order_candidate_freeze();

alter table venue."order" enable row level security;
revoke all on venue."order" from anon, authenticated;
grant select on venue."order" to authenticated;   -- money writes are RPC/definer-only

-- RLS §9.7 — owner (buyer) + org back office + venue ops + platform; all reads.
drop policy if exists venue_order_sel_owner on venue."order";
create policy venue_order_sel_owner on venue."order" for select to authenticated
  using (buyer_id = auth.uid());

drop policy if exists venue_order_sel_org on venue."order";
create policy venue_order_sel_org on venue."order" for select to authenticated
  using (
    kernel.has_org_role(org_id, array['org_owner','org_admin','org_finance'])
    or kernel.is_platform(array['platform_support','platform_risk','platform_admin'])
  );

drop policy if exists venue_order_sel_venue on venue."order";
create policy venue_order_sel_venue on venue."order" for select to authenticated
  using (
    exists (
      select 1 from catalog.event_session s
        join catalog.event e on e.event_id = s.event_id
       where s.session_id = venue."order".event_session_id
         and kernel.has_venue_role(e.venue_id, array['venue_manager','venue_finance','venue_scanner'])
    )
  );

-- ============================================================================
-- PART 2 — venue.order_item (schema §3.8)
-- ============================================================================
create table if not exists venue.order_item (
  id                uuid primary key default gen_random_uuid(),
  order_id          uuid not null references venue."order"(order_id) on delete restrict,
  ticket_type_id    uuid not null references venue.ticket_type(ticket_type_id) on delete restrict,
  quantity          integer not null check (quantity > 0),
  unit_price_minor  integer not null check (unit_price_minor > 0),   -- snapshot at purchase
  currency          text not null default 'USD',
  created_at        timestamptz not null default now(),
  constraint order_item_order_type_uq unique (order_id, ticket_type_id)
);

create index if not exists order_item_order_idx on venue.order_item (order_id);

-- IMM-after-issuance (schema §3.8): once the parent order is paid (or beyond),
-- the purchase snapshot is frozen — no UPDATE/DELETE. Before payment (pending or
-- a pending order that was cancelled) it is mutable so a checkout can be revised.
create or replace function venue.guard_order_item_immutable()
returns trigger language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  select o.status into v_status
    from venue."order" o
   where o.order_id = coalesce(new.order_id, old.order_id);
  if v_status in ('paid','partially_refunded','refunded') then
    raise exception 'append_only: order_item is immutable once the order is issued (order status=%)', v_status
      using errcode = 'P0001';
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists tg_order_item_immutable on venue.order_item;
create trigger tg_order_item_immutable
  before update or delete on venue.order_item
  for each row execute function venue.guard_order_item_immutable();

alter table venue.order_item enable row level security;
revoke all on venue.order_item from anon, authenticated;
grant select on venue.order_item to authenticated;

-- RLS §9.8 — inherits the order's scope.
drop policy if exists venue_order_item_sel_owner on venue.order_item;
create policy venue_order_item_sel_owner on venue.order_item for select to authenticated
  using (exists (select 1 from venue."order" o
                  where o.order_id = venue.order_item.order_id
                    and o.buyer_id = auth.uid()));

drop policy if exists venue_order_item_sel_org on venue.order_item;
create policy venue_order_item_sel_org on venue.order_item for select to authenticated
  using (exists (select 1 from venue."order" o
                  where o.order_id = venue.order_item.order_id
                    and (kernel.has_org_role(o.org_id, array['org_owner','org_admin','org_finance'])
                         or kernel.is_platform(array['platform_support','platform_risk','platform_admin']))));

drop policy if exists venue_order_item_sel_venue on venue.order_item;
create policy venue_order_item_sel_venue on venue.order_item for select to authenticated
  using (exists (
    select 1 from venue."order" o
      join catalog.event_session s on s.session_id = o.event_session_id
      join catalog.event e on e.event_id = s.event_id
     where o.order_id = venue.order_item.order_id
       and kernel.has_venue_role(e.venue_id, array['venue_manager','venue_finance','venue_scanner'])));

-- ============================================================================
-- PART 3 — kernel.org_contact_consent (current-state, CRM §11.2; MUT)
--   PK (identity_id, org_id). Deny-all, ZERO policies (§16.6/§16.10, OR-1):
--   reached only via the 082 consent RPCs + the definer-internal export gate (087).
--   D-3: identity_id CASCADEs with the account, never repointed to a sentinel.
-- ============================================================================
create table if not exists kernel.org_contact_consent (
  identity_id      uuid not null references auth.users(id) on delete cascade,       -- D-3
  org_id           uuid not null references kernel.organization(org_id) on delete restrict,
  state            text not null check (state in ('granted','withdrawn')),
  notice_version   text not null,
  granted_at       timestamptz,
  withdrawn_at     timestamptz,
  source_order_id  uuid references venue."order"(order_id) on delete restrict,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint org_contact_consent_pk primary key (identity_id, org_id),
  -- withdrawn iff withdrawn_at is stamped (schema §1.15 sibling discipline).
  constraint org_contact_consent_withdrawn_ck check ((state = 'withdrawn') = (withdrawn_at is not null))
);

create index if not exists org_contact_consent_org_state_idx
  on kernel.org_contact_consent (org_id, state);

drop trigger if exists tg_org_contact_consent_updated_at on kernel.org_contact_consent;
create trigger tg_org_contact_consent_updated_at
  before update on kernel.org_contact_consent
  for each row execute function kernel.set_updated_at();

alter table kernel.org_contact_consent enable row level security;
revoke all on kernel.org_contact_consent from anon, authenticated;
-- deny-all: EMPTY client grant set, ZERO policies (OR-1). No client SELECT.

-- ============================================================================
-- PART 4 — kernel.org_contact_consent_event (AO ledger, schema §1.15.2; K-2)
--   First physical definition. Deny-all, ZERO policies, AO (REVOKE UPDATE,DELETE
--   + raise_append_only). ODR16 row #22: the identity_id CASCADE ABORTS inside the
--   cascade via the append-only trigger — this abort is the mechanism that blocks
--   a physical auth.users delete (a design-load-bearing property).
-- ============================================================================
create table if not exists kernel.org_contact_consent_event (
  id              uuid primary key default gen_random_uuid(),
  identity_id     uuid not null references auth.users(id) on delete cascade,        -- D-3
  org_id          uuid not null references kernel.organization(org_id) on delete restrict,
  event           text not null check (event in ('granted','withdrawn')),
  occurred_at     timestamptz not null default now(),
  notice_version  text,
  source_order_id uuid references venue."order"(order_id) on delete restrict,
  -- a grant with no notice version is unprovable consent; a withdrawal has no
  -- notice to record and is never caused by a purchase (schema §1.15.2).
  constraint org_contact_consent_event_notice_ck check (event <> 'granted' or notice_version is not null),
  constraint org_contact_consent_event_source_ck check (event = 'granted' or source_order_id is null)
);

create index if not exists org_contact_consent_event_org_idx
  on kernel.org_contact_consent_event (org_id, identity_id, occurred_at desc);
create index if not exists org_contact_consent_event_identity_idx
  on kernel.org_contact_consent_event (identity_id, occurred_at desc);

drop trigger if exists tg_org_contact_consent_event_append_only on kernel.org_contact_consent_event;
create trigger tg_org_contact_consent_event_append_only
  before update or delete on kernel.org_contact_consent_event
  for each row execute function kernel.raise_append_only();

alter table kernel.org_contact_consent_event enable row level security;
revoke all on kernel.org_contact_consent_event from anon, authenticated;
revoke update, delete on kernel.org_contact_consent_event from service_role;   -- AO
-- deny-all: EMPTY client grant set, ZERO policies (OR-1).

-- ============================================================================
-- PART 5 — venue.create_primary_checkout (RPC §6.1; schema alias create_order)
--   Builds a pending order + immutable items from HELD inventory. No money, no
--   mint. F-1 (OR-17) + E-23 buyer-ACTIVE gate. Idempotent on (buyer, command_key).
-- ============================================================================
create or replace function venue.create_primary_checkout(
  p_session_id uuid, p_items jsonb, p_hold_ids uuid[], p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_sess_status text;
  v_evt_status  text;
  v_org_id    uuid;
  v_order_id  uuid;
  v_total     integer := 0;
  v_ex_id     uuid;
  v_ex_total  integer;
  v_ex_curr   text;
  v_item      jsonb;
  v_tt_id     uuid;
  v_qty       integer;
  v_price     integer;
  v_held      integer;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;

  -- OR-17 F-1 + E-23 gate FIRST — an acquisition refusal fires before ANY work
  -- (as 081's reserve does), so a non-ACTIVE buyer is turned away regardless of
  -- what else is in the request. F-1 (dsm §3.2, tests the caller; buyer_id =
  -- auth.uid()): refuse DELETION_PENDING. E-23: is_deletion_pending returns FALSE
  -- for ERASED, so the checkout buyer must be proven ACTIVE, not merely
  -- not-pending — the 077 F-6 / E-8 defensive-twin idiom. (Defensive: an ERASED
  -- identity cannot authenticate, but E-23 mandates the refusal be present and
  -- NOT dischargeable by is_deletion_pending alone.)
  if kernel.is_deletion_pending(v_uid) then
    raise exception 'precondition_failed: deletion_pending';
  end if;
  if exists (select 1 from kernel.identity_ext e
              where e.identity_id = v_uid and e.deletion_state = 'ERASED') then
    raise exception 'precondition_failed: identity_erased';
  end if;

  -- Idempotency short-circuit (C16): a replay of a succeeded checkout returns the
  -- original order, not a second one.
  select order_id, total_minor, currency into v_ex_id, v_ex_total, v_ex_curr
    from venue."order"
   where buyer_id = v_uid and command_idempotency_key = p_command_key;
  if v_ex_id is not null then
    return jsonb_build_object('status','idempotency_replay','order_id',v_ex_id,
                              'total_minor',v_ex_total,'currency',v_ex_curr);
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'precondition_failed: no items';
  end if;

  -- Session must be sellable (event on_sale/live) and not terminal (§6.1). org_id
  -- is server-derived from the session's event; never client-trusted.
  select e.status, s.status, e.org_id
    into v_evt_status, v_sess_status, v_org_id
    from catalog.event_session s
    join catalog.event e on e.event_id = s.event_id
   where s.session_id = p_session_id;
  if v_sess_status is null then
    raise exception 'not_found: session %', p_session_id using errcode = 'P0002';
  end if;
  if v_evt_status not in ('on_sale','live') then
    raise exception 'precondition_failed: not_on_sale';
  end if;
  if v_sess_status in ('completed','cancelled') then
    raise exception 'precondition_failed: session_terminal';
  end if;

  -- Validate items and snapshot server-authoritative prices from venue.ticket_type,
  -- then prove the buyer's ACTIVE holds cover each item's quantity for THIS session
  -- (holds belong to the buyer, are active, not expired — §6.1). Money never moves;
  -- the authoritative held→sold conversion + oversell backstop (C27) is 085/finalize.
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_tt_id := (v_item->>'ticket_type_id')::uuid;
    v_qty   := (v_item->>'quantity')::integer;
    if v_tt_id is null or v_qty is null or v_qty <= 0 then
      raise exception 'precondition_failed: bad_item';
    end if;

    select tt.price_minor into v_price
      from venue.ticket_type tt
     where tt.ticket_type_id = v_tt_id;
    if v_price is null then
      raise exception 'not_found: ticket type %', v_tt_id using errcode = 'P0002';
    end if;

    -- coverage: sum of the buyer's active, unexpired holds for batches of this
    -- ticket_type in this session must be >= the requested quantity.
    select coalesce(sum(h.quantity), 0) into v_held
      from venue.inventory_hold h
      join venue.inventory_batch b on b.batch_id = h.batch_id
     where h.hold_id = any(p_hold_ids)
       and h.identity_id = v_uid
       and h.status = 'active'
       and h.expires_at > now()
       and b.ticket_type_id = v_tt_id
       and b.event_session_id = p_session_id;
    if v_held < v_qty then
      raise exception 'precondition_failed: holds do not cover item (type %, need %, held %)', v_tt_id, v_qty, v_held;
    end if;

    v_total := v_total + (v_price * v_qty);
  end loop;

  -- Create the pending order. source is server-tagged; with no client source hint
  -- in the frozen signature and the rail dark, the default self-serve tag is 'web'.
  -- Attribution candidates stay NULL (R2B/C112 — no promoter tables until 090).
  insert into venue."order" (buyer_id, event_session_id, org_id, status, source,
                             total_minor, currency, command_idempotency_key)
  values (v_uid, p_session_id, v_org_id, 'pending', 'web', v_total, 'USD', p_command_key)
  returning order_id into v_order_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_tt_id := (v_item->>'ticket_type_id')::uuid;
    v_qty   := (v_item->>'quantity')::integer;
    select tt.price_minor into v_price from venue.ticket_type tt where tt.ticket_type_id = v_tt_id;
    insert into venue.order_item (order_id, ticket_type_id, quantity, unit_price_minor, currency)
    values (v_order_id, v_tt_id, v_qty, v_price, 'USD');
  end loop;

  return jsonb_build_object('status','ok','order_id',v_order_id,
                            'total_minor',v_total,'currency','USD');
end;
$$;

-- ============================================================================
-- PART 6 — venue.cancel_pending_order (RPC §20.7.9) — service_role only.
--   The webhook terminal-failure writer: pending -> cancelled, forward-only.
--   Redelivery on a cancelled order is a noop_replay (never raises — a raising
--   webhook is retried forever). Actor is the SN-SYSTEM sentinel (078 §1.16).
-- ============================================================================
create or replace function venue.cancel_pending_order(
  p_order_id uuid, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  if p_order_id is null then
    raise exception 'invalid_input: order id required';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'invalid_input: command key required';
  end if;

  select status into v_status from venue."order" where order_id = p_order_id for update;
  if v_status is null then
    raise exception 'not_found: order %', p_order_id using errcode = 'P0002';
  end if;
  if v_status = 'cancelled' then
    return jsonb_build_object('status','noop_replay','order_id',p_order_id);
  end if;
  if v_status <> 'pending' then
    raise exception 'precondition_failed: order_not_pending (status=%)', v_status;
  end if;

  update venue."order" set status = 'cancelled' where order_id = p_order_id;

  -- SN-SYSTEM is the system-actor sentinel: "who did this" for scheduler/webhook
  -- writes (078 §1.16, uuid ...f1). Capacity returns via the 081 hold TTL sweep.
  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values ('00000000-0000-0000-0000-0000000000f1', 'order.cancel', 'order', p_order_id,
          coalesce(p_reason_code, 'webhook_terminal'),
          jsonb_build_object('status', v_status), jsonb_build_object('status','cancelled'));

  return jsonb_build_object('status','ok','order_id',p_order_id);
end;
$$;

-- ============================================================================
-- PART 7 — CRM contact consent (RPC §17.21) — own-row only, NO p_identity_id.
--   Each write appends one AO event row in the SAME transaction (AUTHZ-CRM1).
--   A no-op appends no event (re-grant/re-withdraw of the same state).
-- ============================================================================
create or replace function kernel.grant_org_contact_consent(
  p_org_id uuid, p_notice_version text, p_source_order_id uuid)
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
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_notice_version is null or length(trim(p_notice_version)) = 0 then
    raise exception 'precondition_failed: notice version required';
  end if;
  if not exists (select 1 from kernel.organization o where o.org_id = p_org_id) then
    raise exception 'not_found: organization %', p_org_id using errcode = 'P0002';
  end if;

  select state into v_state from kernel.org_contact_consent
   where identity_id = v_uid and org_id = p_org_id;

  -- no-op: already granted -> no state change, no event (do not log a retry).
  if v_state = 'granted' then
    return jsonb_build_object('status','noop_replay');
  end if;

  insert into kernel.org_contact_consent (identity_id, org_id, state, notice_version,
                                          granted_at, withdrawn_at, source_order_id)
  values (v_uid, p_org_id, 'granted', p_notice_version, now(), null, p_source_order_id)
  on conflict (identity_id, org_id) do update
    set state = 'granted', notice_version = excluded.notice_version,
        granted_at = now(), withdrawn_at = null, source_order_id = excluded.source_order_id;

  insert into kernel.org_contact_consent_event (identity_id, org_id, event, notice_version, source_order_id)
  values (v_uid, p_org_id, 'granted', p_notice_version, p_source_order_id);

  return jsonb_build_object('status','ok');
end;
$$;

create or replace function kernel.withdraw_org_contact_consent(p_org_id uuid)
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
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;

  select state into v_state from kernel.org_contact_consent
   where identity_id = v_uid and org_id = p_org_id;

  -- idempotent: nothing to withdraw, or already withdrawn -> no event.
  if v_state is null or v_state = 'withdrawn' then
    return jsonb_build_object('status','noop_replay');
  end if;

  update kernel.org_contact_consent
     set state = 'withdrawn', withdrawn_at = now()
   where identity_id = v_uid and org_id = p_org_id;

  insert into kernel.org_contact_consent_event (identity_id, org_id, event, notice_version, source_order_id)
  values (v_uid, p_org_id, 'withdrawn', null, null);

  return jsonb_build_object('status','ok');
end;
$$;

-- parameterless own-rows reader (RPC §17.21; current state only — the history
-- read is an undecided owner question, OWNER-DECISION-K2-READ, not built here).
create or replace function kernel.list_my_org_contact_consents()
returns table (org_id uuid, state text, notice_version text,
               granted_at timestamptz, withdrawn_at timestamptz)
language sql
security definer
set search_path = ''
stable
as $$
  select c.org_id, c.state, c.notice_version, c.granted_at, c.withdrawn_at
    from kernel.org_contact_consent c
   where c.identity_id = auth.uid()
   order by c.org_id;
$$;

-- ============================================================================
-- PART 8 — kernel.deletion_blockers_orders — SEAM-2 body (born 077).
--   BP-12 PENDING-ORDER arm ONLY (dsm §2). The refund/paid-window arm is
--   kernel.deletion_blockers_money (085); kernel.refund does not exist here.
--   Signature is the 077 stub's, byte-for-byte (SEAM-2a).
-- ============================================================================
create or replace function kernel.deletion_blockers_orders(p_identity uuid)
returns text language sql volatile security definer set search_path = ''
as $$
  select 'BP-12: open pending order — resolves when the order reaches a terminal status (paid/cancelled)'
   where exists (
     select 1 from venue."order" o
      where o.buyer_id = p_identity
        and o.status = 'pending'
   );
$$;

-- ============================================================================
-- PART 9 — function EXECUTE grants (STANDARDS §5 / SEC-2 discipline)
-- ============================================================================
do $$
declare
  v_fn text;
  v_all constant text[] := array[
    'venue.create_primary_checkout(uuid, jsonb, uuid[], text)',
    'venue.cancel_pending_order(uuid, text, text)',
    'kernel.grant_org_contact_consent(uuid, text, uuid)',
    'kernel.withdraw_org_contact_consent(uuid)',
    'kernel.list_my_org_contact_consents()',
    'venue.guard_order_candidate_freeze()',
    'venue.guard_order_item_immutable()'
    -- kernel.deletion_blockers_orders keeps its 077 grant (definer, no client EXEC).
  ];
  -- caller-authorized client RPCs.
  v_auth constant text[] := array[
    'venue.create_primary_checkout(uuid, jsonb, uuid[], text)',
    'kernel.grant_org_contact_consent(uuid, text, uuid)',
    'kernel.withdraw_org_contact_consent(uuid)',
    'kernel.list_my_org_contact_consents()'
  ];
  -- machine-only: the webhook terminal-failure writer.
  v_svc constant text[] := array[
    'venue.cancel_pending_order(uuid, text, text)'
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

commit;

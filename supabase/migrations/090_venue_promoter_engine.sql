-- ============================================================================
-- 090_venue_promoter_engine.sql — Phase-2 package 090 (registry §2 row 090;
-- plan §8/090; schema §3.17/§3.17.1/§3.17.2/§3.14.1; PROMOTER_CODES_SPEC
-- §1–§10; RPC §1.1c/§17.14–§17.19/§20.7.2/§20.9.1–§20.9.5/§20.11.2/§20.11.4/
-- §20.17.5; RLS §9.17 (AUTHZ-M9/M10)/§11.5/§11.8/§17 X-13; OR-13 (ODR-16)
-- INV #35–#38; OR-17 F-7; OR-14 (BE emits); G-25 #31/#32; PFA-9; X-12; E-73;
-- E-80; E-104 (seam volatility + per-org xact lock); E-120–E-131 (this pkg).
-- ----------------------------------------------------------------------------
-- THE CLOSED WORLD (plan §8/090 Tables/Functions rows — the parity file is a
-- DEMO seed and defers to plan §8): SIX tables (venue.promoter, promoter_link,
-- attribution, promoter_code, promoter_code_scope, attribution_review);
-- TWENTY-ONE routines created here (normalize_promoter_code · create_promoter ·
-- update_promoter · create_promoter_link · set_promoter_link_status ·
-- check_promoter_slug_available · create_promoter_code · create_promoter_codes_bulk
-- · set_promoter_code_status · set_promoter_code_scope · set_promoter_code_window
-- · preview_promoter_code · bind_order_attribution · review_attribution_flag ·
-- get_my_promoter_summary · list_my_attributions · list_promoter_attributions ·
-- kernel.is_promoter_for_event · kernel.pay_promoter_commission · two trigger
-- functions = 21); THREE SEAM-2 body-only replacements (venue.resolve_order_attribution
-- [085 stub] · kernel.settlement_commission_lines [087 stub] ·
-- kernel.on_identity_erased_promoter [077 stub]) — signatures, parameter names,
-- return types and overload count (1) FROZEN (SEAM-2a); the money constraint
-- attribution_one_commission_line_ever on venue.settlement_line (§3.14.1);
-- the two ADOPTED venue.order candidate FKs (NOT VALID → VALIDATE, the 084/089
-- construction). NO new cron row, NO new config key (PFA-9), NO edge bytes
-- (promoter-code-preview / primary-checkout code+link are deploy artifacts,
-- not SQL — recorded in governance).
--
-- MONEY (PROMOTER §4 / §6, schema §3.17.1): basis = Σ order_item.unit_price_minor
-- × quantity (face subtotal — ODR-30 corpus default, E-121); credited =
-- floor(basis × bps / 10000) | flat × Σqty; rounding FLOOR, residual stays with
-- the org; terms SNAPSHOTTED on the attribution row at freeze; PAYABLE is
-- recomputed at close from SURVIVING (non-voided) atoms; a flagged, unreviewed
-- attribution yields NO line (a HOLD, never a zero line); one commission line
-- per attribution EVER (partial unique); one payout per (attribution, payee)
-- (idempotency_key 'promoter_commission:<attribution_id>:<payee_identity_id>'
-- — PROMOTER §4.2(3) byte-for-byte). Commission lines are NEGATIVE (E-73: an
-- org debit lands in the fees bucket; the promoter's payout carries the +).
--
-- LOCKS: the resolver takes NONE of its own (Order rank-3 held by the caller);
-- bind_order_attribution: Order(3) FOR UPDATE; the seam: per-org xact advisory
-- lock (E-104) then Settlement(6) re-lock (NOWAIT — asserts the caller's lock);
-- payout inserts after Settlement (rank 6 fixed sub-rank). No new locked class
-- (C28 unamended). The resolver NEVER raises (§7.11 / §17.14).
-- ============================================================================
begin;

-- ============================================================================
-- PART 1 — venue.normalize_promoter_code (§1.3; RPC §20.11.4). IMMUTABLE STRICT.
--   FROZEN ONCE 090 APPLIES WITH LIVE CODES (its output is a unique-index key).
-- ============================================================================
create or replace function venue.normalize_promoter_code(p_code text)
returns text
language sql immutable strict parallel safe
set search_path = ''
as $$
  -- 1 strip every non-[A-Za-z0-9] byte · 2 upper() (pure ASCII now, locale-free)
  -- · 3 Crockford confusable fold O→0, I→1, L→1. 'U' is NOT folded: it is
  -- outside the alphabet and is rejected at issue time by the CHECK.
  select translate(upper(regexp_replace(p_code, '[^A-Za-z0-9]', '', 'g')), 'OIL', '011')
$$;
revoke all on function venue.normalize_promoter_code(text) from public, anon, authenticated;

-- ============================================================================
-- PART 2 — TABLES (schema §3.17 + §3.17.1 + §3.17.2; PROMOTER §1.1–§1.6)
-- ============================================================================
-- 2a — venue.promoter
create table if not exists venue.promoter (
  promoter_id           uuid primary key default gen_random_uuid(),
  -- NULL admissible ONLY for party_kind='affiliate' (schema §3.17, ODR-16 1.5)
  identity_id           uuid references auth.users(id) on delete restrict,
  org_id                uuid not null references kernel.organization(org_id) on delete restrict,
  event_id              uuid references catalog.event(event_id) on delete restrict,   -- single-event promoter
  terms_version         integer not null default 1 check (terms_version > 0),
  status                text not null default 'active' check (status in ('active','inactive')),
  tier                  text not null default 'professional_invited'
                        check (tier in ('professional_invited','public_ambassador')),
  party_kind            text not null default 'promoter'
                        check (party_kind in ('promoter','affiliate')),
  commission_kind       text not null default 'bps'
                        check (commission_kind in ('bps','flat_per_ticket')),
  commission_bps        integer,
  commission_flat_minor integer,
  currency              text not null default 'USD',
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint promoter_identity_for_promoter_ck check (party_kind <> 'promoter' or identity_id is not null),
  -- §3.17.1: the XOR is load-bearing — never relax to "at least one"
  constraint promoter_terms_xor_ck check (
    (commission_kind = 'bps'
       and commission_bps is not null and commission_bps between 0 and 10000
       and commission_flat_minor is null)
    or
    (commission_kind = 'flat_per_ticket'
       and commission_flat_minor is not null and commission_flat_minor > 0
       and commission_bps is null)
  )
);
create index if not exists promoter_org_status_idx on venue.promoter (org_id, status);
create index if not exists promoter_identity_idx   on venue.promoter (identity_id) where identity_id is not null;

-- 2b — venue.promoter_link (+status trio §3.17.2; event_id — E-122)
create table if not exists venue.promoter_link (
  link_id           uuid primary key default gen_random_uuid(),
  promoter_id       uuid not null references venue.promoter(promoter_id) on delete restrict,
  -- E-122: RPC §20.9.3 takes p_event_id and §1.1c reads l.event_id; schema
  -- §3.17's column list omits it. A link is per event (the only shape both
  -- contracts admit) — NOT NULL.
  event_id          uuid not null references catalog.event(event_id) on delete restrict,
  slug              text not null,
  status            text not null default 'active' check (status in ('active','inactive')),
  status_changed_at timestamptz,
  status_changed_by uuid references auth.users(id) on delete restrict,   -- INV #36 CLEANED (SET NULL) on erasure
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint promoter_link_slug_uq unique (slug),                         -- GLOBAL namespace
  -- E-123: the "format CHECK" §20.9.3 cites is stated nowhere; a conservative
  -- URL-slug form (lower-case alnum + inner hyphens, 3–64) — widening is additive.
  constraint promoter_link_slug_format_ck check (slug ~ '^[a-z0-9](?:[a-z0-9-]{1,62}[a-z0-9])$')
);
create index if not exists promoter_link_promoter_active_idx on venue.promoter_link (promoter_id) where status = 'active';
create index if not exists promoter_link_event_idx on venue.promoter_link (event_id);

-- 2c — venue.promoter_code (§1.1)
create table if not exists venue.promoter_code (
  code_id         uuid primary key default gen_random_uuid(),
  promoter_id     uuid not null references venue.promoter(promoter_id) on delete restrict,
  org_id          uuid not null references kernel.organization(org_id) on delete restrict,   -- denormalized; trigger-asserted
  code_display    text not null,
  code_normalized text not null generated always as (venue.normalize_promoter_code(code_display)) stored,
  status          text not null default 'active' check (status in ('active','inactive')),
  valid_from      timestamptz,
  valid_until     timestamptz,
  kind            text not null check (kind in ('vanity','generated')),
  created_by      uuid not null references auth.users(id) on delete restrict,   -- INV #37: survives erasure
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint promoter_code_normalized_uq unique (code_normalized),           -- GLOBAL (§10.2)
  constraint promoter_code_window_ck check (valid_until is null or valid_from is null or valid_until > valid_from),
  constraint promoter_code_length_ck check (length(code_normalized) between 4 and 16),
  constraint promoter_code_alphabet_ck check (code_normalized ~ '^[0-9A-HJKMNP-TV-Z]+$')
);
create index if not exists promoter_code_promoter_status_idx on venue.promoter_code (promoter_id, status);
create index if not exists promoter_code_org_status_created_idx on venue.promoter_code (org_id, status, created_at desc);
create index if not exists promoter_code_normalized_pattern_idx on venue.promoter_code (code_normalized text_pattern_ops);

-- 2d — venue.promoter_code_scope (§1.2)
create table if not exists venue.promoter_code_scope (
  code_id  uuid not null references venue.promoter_code(code_id) on delete restrict,
  event_id uuid not null references catalog.event(event_id) on delete restrict,
  added_by uuid not null references auth.users(id) on delete restrict,
  added_at timestamptz not null default now(),
  primary key (code_id, event_id)
);
create index if not exists promoter_code_scope_event_idx on venue.promoter_code_scope (event_id);

-- 2e — venue.attribution (schema §3.17 + PROMOTER §1.5; AO; UNIQUE(order_id))
create table if not exists venue.attribution (
  id                            uuid primary key default gen_random_uuid(),
  link_id                       uuid references venue.promoter_link(link_id) on delete restrict,   -- NULL for a code-sourced row
  order_id                      uuid not null references venue."order"(order_id) on delete restrict,
  promoter_id                   uuid not null references venue.promoter(promoter_id) on delete restrict,
  org_id                        uuid not null references kernel.organization(org_id) on delete restrict,
  event_id                      uuid not null references catalog.event(event_id) on delete restrict,
  code_id                       uuid references venue.promoter_code(code_id) on delete restrict,
  method                        text not null check (method in ('link','code')),
  touch_corroborated            boolean not null,
  self_deal_flag                boolean not null default false,
  self_deal_reasons             text[] not null default '{}',
  displaced_promoter_id         uuid references venue.promoter(promoter_id) on delete restrict,
  terms_version                 integer not null,
  commission_kind               text not null check (commission_kind in ('bps','flat_per_ticket')),
  commission_bps_applied        integer,
  commission_flat_minor_applied integer,
  basis_minor                   integer not null check (basis_minor >= 0),
  credited_amount_minor         integer not null check (credited_amount_minor >= 0),
  currency                      text not null default 'USD',
  resolution_reason             text not null check (resolution_reason in (
                                  'code_corroborated_by_link','code_over_link','code_only_link_ineligible','code_only',
                                  'link_after_code_ineligible','link_only','none_eligible','no_attribution_presented')),
  occurred_at                   timestamptz not null default now(),
  order_paid_at                 timestamptz not null,
  created_at                    timestamptz not null default now(),
  constraint attribution_one_per_order unique (order_id),                                  -- §4.2 (1)
  constraint attribution_method_ck check (
    (method = 'code' and code_id is not null) or (method = 'link' and link_id is not null and code_id is null)),
  constraint attribution_terms_xor_ck check (
    (commission_kind = 'bps' and commission_bps_applied is not null and commission_flat_minor_applied is null)
    or (commission_kind = 'flat_per_ticket' and commission_flat_minor_applied is not null and commission_bps_applied is null))
);
create index if not exists attribution_promoter_paid_idx  on venue.attribution (promoter_id, order_paid_at desc, id desc);
create index if not exists attribution_org_event_paid_idx on venue.attribution (org_id, event_id, order_paid_at desc);
create index if not exists attribution_code_idx           on venue.attribution (code_id) where code_id is not null;
create index if not exists attribution_link_idx           on venue.attribution (link_id) where link_id is not null;
create index if not exists attribution_self_deal_idx      on venue.attribution (org_id) where self_deal_flag;

-- 2f — venue.attribution_review (§1.6; AO; effective decision = max(seq))
create table if not exists venue.attribution_review (
  review_id      uuid primary key default gen_random_uuid(),
  attribution_id uuid not null references venue.attribution(id) on delete restrict,
  seq            integer not null check (seq > 0),
  decision       text not null check (decision in ('release','deny')),
  reason_code    text not null check (reason_code in (
                   'legitimate_guest_purchase','self_purchase_confirmed','shared_instrument_explained',
                   'policy_violation','duplicate_account_suspected','other')),
  note           text,
  decided_by     uuid not null references auth.users(id) on delete restrict,   -- INV #38 TOMBSTONED
  decided_at     timestamptz not null default now(),
  constraint attribution_review_seq_uq unique (attribution_id, seq)
);

-- 2g — THE MONEY CONSTRAINT (schema §3.14.1; PROMOTER §4.2 (2)): one
--   promoter_commission line per attribution, platform-wide, for all time.
create unique index if not exists attribution_one_commission_line_ever
  on venue.settlement_line (cause_ref) where cause = 'promoter_commission';


-- ============================================================================
-- PART 3 — TRIGGERS (plan §8/090 Triggers row): immutability guards (PL-1 and
--   the code no-reassignment rule), org/order consistency assertions, AO on the
--   two ledgers, set_updated_at on promoter/promoter_link/promoter_code.
-- ============================================================================
-- 3a — one guard for the two IMMUTABLE-EXCEPT classes. TG_ARGV = the MUTABLE
--   column list; any other column changing raises (regardless of caller).
create or replace function venue.guard_promoter_engine_immutable()
returns trigger language plpgsql
set search_path = ''
as $$
declare v_old jsonb := to_jsonb(old); v_new jsonb := to_jsonb(new); v_k text; v_mutable text[] := tg_argv;
begin
  -- a GENERATED column is not yet computed in a BEFORE trigger's NEW (it reads NULL);
  -- it is derived from an immutable column and is skipped rather than compared.
  for v_k in select a.attname::text from pg_attribute a
              where a.attrelid = tg_relid and a.attnum > 0 and not a.attisdropped and a.attgenerated = '' loop
    if not (v_k = any(v_mutable)) and (v_new -> v_k) is distinct from (v_old -> v_k) then
      raise exception 'immutable: %.% is IMMUTABLE once created (no reassignment — PROMOTER §1.1 / PL-1)', tg_table_name, v_k
        using errcode = 'P0001';
    end if;
  end loop;
  return new;
end;
$$;

-- 3b — consistency assertions (org locality, event locality, order agreement)
create or replace function venue.assert_promoter_engine_consistency()
returns trigger language plpgsql
set search_path = ''
as $$
declare v_org uuid; v_order venue."order"%rowtype; v_event uuid;
begin
  if tg_table_name = 'promoter' then
    if new.event_id is not null then
      select e.org_id into v_org from catalog.event e where e.event_id = new.event_id;
      if v_org is distinct from new.org_id then
        raise exception 'precondition_failed: event_out_of_org — promoter.event_id belongs to another org' using errcode = 'P0001';
      end if;
    end if;
  elsif tg_table_name = 'promoter_link' then
    select p.org_id into v_org from venue.promoter p where p.promoter_id = new.promoter_id;
    if not exists (select 1 from catalog.event e where e.event_id = new.event_id and e.org_id = v_org) then
      raise exception 'precondition_failed: event_out_of_org — a link binds only an event of the promoter''s org' using errcode = 'P0001';
    end if;
  elsif tg_table_name = 'promoter_code' then
    select p.org_id into v_org from venue.promoter p where p.promoter_id = new.promoter_id;
    if v_org is distinct from new.org_id then
      raise exception 'precondition_failed: promoter_code.org_id must equal promoter.org_id' using errcode = 'P0001';
    end if;
  elsif tg_table_name = 'promoter_code_scope' then
    if not exists (select 1 from venue.promoter_code c join catalog.event e on e.org_id = c.org_id
                    where c.code_id = new.code_id and e.event_id = new.event_id) then
      raise exception 'precondition_failed: event_out_of_org — a code can never be scoped to another org''s event' using errcode = 'P0001';
    end if;
  elsif tg_table_name = 'attribution' then
    select * into v_order from venue."order" o where o.order_id = new.order_id;
    if v_order.order_id is null or v_order.status = 'pending' then
      raise exception 'precondition_failed: an attribution binds only an economically committed (non-pending) order' using errcode = 'P0001';
    end if;
    select es.event_id into v_event from catalog.event_session es where es.session_id = v_order.event_session_id;
    if v_order.org_id is distinct from new.org_id or v_event is distinct from new.event_id then
      raise exception 'precondition_failed: attribution.org_id/event_id disagree with the order' using errcode = 'P0001';
    end if;
    if not exists (select 1 from venue.promoter p where p.promoter_id = new.promoter_id and p.org_id = new.org_id) then
      raise exception 'precondition_failed: attribution.promoter_id is not a promoter of the order''s org' using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

-- promoter: event locality + updated_at
drop trigger if exists tg_promoter_consistency on venue.promoter;
create trigger tg_promoter_consistency before insert or update on venue.promoter
  for each row execute function venue.assert_promoter_engine_consistency();
drop trigger if exists tg_promoter_set_updated_at on venue.promoter;
create trigger tg_promoter_set_updated_at before update on venue.promoter
  for each row execute function kernel.set_updated_at();
-- promoter_link: PL-1 (status trio + updated_at are the ONLY mutable columns)
drop trigger if exists tg_promoter_link_consistency on venue.promoter_link;
create trigger tg_promoter_link_consistency before insert on venue.promoter_link
  for each row execute function venue.assert_promoter_engine_consistency();
drop trigger if exists tg_promoter_link_immutable on venue.promoter_link;
create trigger tg_promoter_link_immutable before update on venue.promoter_link
  for each row execute function venue.guard_promoter_engine_immutable('status','status_changed_at','status_changed_by','updated_at');
drop trigger if exists tg_promoter_link_set_updated_at on venue.promoter_link;
create trigger tg_promoter_link_set_updated_at before update on venue.promoter_link
  for each row execute function kernel.set_updated_at();
-- promoter_code: org locality; no-reassignment (only status/window/updated_at mutable)
drop trigger if exists tg_promoter_code_consistency on venue.promoter_code;
create trigger tg_promoter_code_consistency before insert on venue.promoter_code
  for each row execute function venue.assert_promoter_engine_consistency();
drop trigger if exists tg_promoter_code_immutable on venue.promoter_code;
create trigger tg_promoter_code_immutable before update on venue.promoter_code
  for each row execute function venue.guard_promoter_engine_immutable('status','valid_from','valid_until','updated_at');
drop trigger if exists tg_promoter_code_set_updated_at on venue.promoter_code;
create trigger tg_promoter_code_set_updated_at before update on venue.promoter_code
  for each row execute function kernel.set_updated_at();
-- promoter_code_scope: org locality (rows are operational config — add/remove)
drop trigger if exists tg_promoter_code_scope_consistency on venue.promoter_code_scope;
create trigger tg_promoter_code_scope_consistency before insert on venue.promoter_code_scope
  for each row execute function venue.assert_promoter_engine_consistency();
drop trigger if exists tg_promoter_code_scope_immutable on venue.promoter_code_scope;
create trigger tg_promoter_code_scope_immutable before update on venue.promoter_code_scope
  for each row execute function kernel.raise_append_only();
-- attribution: consistency on insert; AO (UPDATE/DELETE raise for EVERY caller)
drop trigger if exists tg_attribution_consistency on venue.attribution;
create trigger tg_attribution_consistency before insert on venue.attribution
  for each row execute function venue.assert_promoter_engine_consistency();
drop trigger if exists tg_attribution_append_only on venue.attribution;
create trigger tg_attribution_append_only before update or delete on venue.attribution
  for each row execute function kernel.raise_append_only();
-- attribution_review: AO
drop trigger if exists tg_attribution_review_append_only on venue.attribution_review;
create trigger tg_attribution_review_append_only before update or delete on venue.attribution_review
  for each row execute function kernel.raise_append_only();

-- ============================================================================
-- PART 4 — RLS + TABLE GRANTS (RLS §9.17 matrices; PROMOTER §8.1/§8.4;
--   AUTHZ-M9 / T-RLS-ATTR-06: venue.attribution and attribution_review carry
--   an EMPTY client grant set — every read is a definer RPC projection;
--   E-124: the promoter-manager labels hold EXEC on the code RPCs (§11.5) but
--   no SELECT cell in any frozen matrix → deny-by-default (RLS :712).
-- ============================================================================
alter table venue.promoter            enable row level security;
alter table venue.promoter_link       enable row level security;
alter table venue.promoter_code       enable row level security;
alter table venue.promoter_code_scope enable row level security;
alter table venue.attribution         enable row level security;
alter table venue.attribution_review  enable row level security;
revoke all on venue.promoter, venue.promoter_link, venue.promoter_code, venue.promoter_code_scope,
              venue.attribution, venue.attribution_review from public, anon, authenticated, service_role;
grant select on venue.promoter, venue.promoter_link, venue.promoter_code, venue.promoter_code_scope to authenticated;
-- venue.attribution / attribution_review: NO grant to any client role (AUTHZ-M9).

-- 4a — venue.promoter: org back office (own-org) · venue staff over the org's
--   venues (own-venue: the promoter's event venue, or any org venue for an
--   org-wide promoter) · the promoter's OWN row · platform.
drop policy if exists venue_promoter_sel_org on venue.promoter;
create policy venue_promoter_sel_org on venue.promoter for select to authenticated
  using (kernel.has_org_role(org_id, array['org_owner','org_admin','org_finance'])
         or kernel.is_platform(array['platform_support','platform_risk','platform_admin']));
drop policy if exists venue_promoter_sel_venue on venue.promoter;
create policy venue_promoter_sel_venue on venue.promoter for select to authenticated
  using (exists (select 1 from catalog.venue v
                  where v.org_id = venue.promoter.org_id
                    and (venue.promoter.event_id is null
                         or exists (select 1 from catalog.event e where e.event_id = venue.promoter.event_id and e.venue_id = v.venue_id))
                    and kernel.has_venue_role(v.venue_id, array['venue_manager','venue_finance'])));
drop policy if exists venue_promoter_sel_own on venue.promoter;
create policy venue_promoter_sel_own on venue.promoter for select to authenticated
  using (identity_id is not null and identity_id = auth.uid());

-- 4b — venue.promoter_link: org · venue (the link's event venue) · own (via the
--   promoter row — the §9.17 predicate shape, never promoter_id = auth.uid())
drop policy if exists venue_promoter_link_sel_org on venue.promoter_link;
create policy venue_promoter_link_sel_org on venue.promoter_link for select to authenticated
  using (exists (select 1 from venue.promoter p where p.promoter_id = venue.promoter_link.promoter_id
                   and (kernel.has_org_role(p.org_id, array['org_owner','org_admin','org_finance'])
                        or kernel.is_platform(array['platform_support','platform_risk','platform_admin']))));
drop policy if exists venue_promoter_link_sel_venue on venue.promoter_link;
create policy venue_promoter_link_sel_venue on venue.promoter_link for select to authenticated
  using (exists (select 1 from catalog.event e where e.event_id = venue.promoter_link.event_id
                   and kernel.has_venue_role(e.venue_id, array['venue_manager','venue_finance'])));
drop policy if exists venue_promoter_link_sel_own on venue.promoter_link;
create policy venue_promoter_link_sel_own on venue.promoter_link for select to authenticated
  using (promoter_id in (select p.promoter_id from venue.promoter p where p.identity_id = auth.uid() and p.status = 'active'));

-- 4c — venue.promoter_code (PROMOTER §8.1 mirrors §9.17)
drop policy if exists venue_promoter_code_sel_org on venue.promoter_code;
create policy venue_promoter_code_sel_org on venue.promoter_code for select to authenticated
  using (kernel.has_org_role(org_id, array['org_owner','org_admin','org_finance'])
         or kernel.is_platform(array['platform_support','platform_risk','platform_admin']));
drop policy if exists venue_promoter_code_sel_venue on venue.promoter_code;
create policy venue_promoter_code_sel_venue on venue.promoter_code for select to authenticated
  using (exists (select 1 from catalog.venue v where v.org_id = venue.promoter_code.org_id
                   and kernel.has_venue_role(v.venue_id, array['venue_manager','venue_finance'])));
drop policy if exists venue_promoter_code_sel_own on venue.promoter_code;
create policy venue_promoter_code_sel_own on venue.promoter_code for select to authenticated
  using (promoter_id in (select p.promoter_id from venue.promoter p where p.identity_id = auth.uid() and p.status = 'active'));

-- 4d — venue.promoter_code_scope: visible exactly where its code is
drop policy if exists venue_promoter_code_scope_sel on venue.promoter_code_scope;
create policy venue_promoter_code_scope_sel on venue.promoter_code_scope for select to authenticated
  using (exists (select 1 from venue.promoter_code c where c.code_id = venue.promoter_code_scope.code_id));

-- ============================================================================
-- PART 5 — PROMOTER RECORDS + LINKS (RPC §20.9.1–§20.9.5). Authority (§11.5,
--   the "promoter-program manager" allow-list, scoped to the promoter's org):
--   has_org_role(org,[org_owner,org_admin,org_promoter_manager]) OR a venue label
--   [venue_manager,venue_promoter_manager] over a venue of that org (the
--   promoter's event venue when single-event). A promoter satisfies NEITHER
--   (they hold no staff/org row — O-2). Command keys: E-80 bounded; replay via
--   the immutable audit (087's C16 pattern).
-- ============================================================================
create or replace function venue.create_promoter(p_org_id uuid, p_identity_ref text, p_terms jsonb, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_identity uuid; v_id uuid; v_state text; v_prev jsonb;
        v_kind text; v_bps integer; v_flat integer; v_tier text; v_party text; v_ccy text; v_event uuid;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-]' using errcode = '22023';
  end if;
  if not exists (select 1 from kernel.organization o where o.org_id = p_org_id) then
    raise exception 'not_found: org %', p_org_id using errcode = 'P0002';
  end if;
  if not (kernel.has_org_role(p_org_id, array['org_owner','org_admin','org_promoter_manager'])
          or exists (select 1 from catalog.venue v where v.org_id = p_org_id
                       and kernel.has_venue_role(v.venue_id, array['venue_manager','venue_promoter_manager']))) then
    raise exception 'insufficient_privilege: promoter-program manager only (§11.5)' using errcode = '42501';
  end if;
  -- terms (re-validated in-body; the CHECKs are the backstop)
  v_kind  := coalesce(p_terms ->> 'commission_kind', 'bps');
  v_tier  := coalesce(p_terms ->> 'tier', 'professional_invited');
  v_party := coalesce(p_terms ->> 'party_kind', 'promoter');
  v_ccy   := coalesce(p_terms ->> 'currency', 'USD');
  v_bps   := (p_terms ->> 'commission_bps')::integer;
  v_flat  := (p_terms ->> 'commission_flat_minor')::integer;
  if v_tier not in ('professional_invited','public_ambassador') then raise exception 'precondition_failed: bad_tier' using errcode = 'P0001'; end if;
  if v_party not in ('promoter','affiliate') then raise exception 'precondition_failed: bad_party_kind' using errcode = 'P0001'; end if;
  if not ((v_kind = 'bps' and v_bps is not null and v_bps between 0 and 10000 and v_flat is null)
          or (v_kind = 'flat_per_ticket' and v_flat is not null and v_flat > 0 and v_bps is null)) then
    raise exception 'precondition_failed: terms_xor_violation' using errcode = 'P0001';
  end if;
  if v_ccy !~ '^[A-Z]{3}$' then raise exception 'precondition_failed: bad_currency' using errcode = 'P0001'; end if;
  v_event := (p_terms ->> 'event_id')::uuid;
  -- C16 replay, BOUND to the parameters (087's idempotency_conflict discipline — red-team B2)
  perform pg_advisory_xact_lock(hashtext('promoter.create:' || v_uid::text || ':' || p_command_key));
  select a.subject_id, a.after into v_id, v_prev from kernel.admin_audit a
   where a.action = 'promoter.create' and a.actor_identity = v_uid and a.reason_code = p_command_key limit 1;
  if v_id is not null then
    if (v_prev ->> 'org_id')::uuid is distinct from p_org_id or (v_prev ->> 'identity_ref') is distinct from nullif(trim(coalesce(p_identity_ref,'')),'')
       or (v_prev ->> 'tier') is distinct from v_tier or (v_prev ->> 'party_kind') is distinct from v_party
       or (v_prev ->> 'commission_kind') is distinct from v_kind or (v_prev ->> 'commission_bps')::integer is distinct from v_bps
       or (v_prev ->> 'commission_flat_minor')::integer is distinct from v_flat or (v_prev ->> 'currency') is distinct from v_ccy
       or (v_prev ->> 'event_id')::uuid is distinct from v_event then
      raise exception 'precondition_failed: idempotency_conflict — command key reused with different parameters' using errcode = 'P0001';
    end if;
    return jsonb_build_object('status','idempotency_replay','promoter_id', v_id,
      'terms_version', (select terms_version from venue.promoter where promoter_id = v_id));
  end if;
  -- identity_ref: untrusted; resolved server-side (uid text, else email). NULL only for an affiliate.
  if p_identity_ref is not null and length(trim(p_identity_ref)) > 0 then
    if p_identity_ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      select u.id into v_identity from auth.users u where u.id = p_identity_ref::uuid;
    else
      select u.id into v_identity from auth.users u where lower(u.email) = lower(trim(p_identity_ref)) limit 1;
    end if;
    if v_identity is null then raise exception 'not_found: identity_ref does not resolve' using errcode = 'P0002'; end if;
    -- OR-17 F-7 (+ E-23 class): no NEW commission entitlement for a deleting/erased identity.
    -- ONE message for both states (red-team J: the state of a third party is not disclosed by email).
    select ie.deletion_state into v_state from kernel.identity_ext ie where ie.identity_id = v_identity;
    if kernel.is_deletion_pending(v_identity) or coalesce(v_state,'ACTIVE') <> 'ACTIVE' then
      raise exception 'precondition_failed: identity_ineligible' using errcode = 'P0001';
    end if;
  elsif v_party = 'promoter' then
    raise exception 'precondition_failed: a promoter (party_kind=promoter) requires an identity' using errcode = 'P0001';
  end if;
  insert into venue.promoter (identity_id, org_id, event_id, terms_version, status, tier, party_kind, commission_kind, commission_bps, commission_flat_minor, currency)
  values (v_identity, p_org_id, v_event, 1, 'active', v_tier, v_party, v_kind, v_bps, v_flat, v_ccy)
  returning promoter_id into v_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values (v_uid, 'promoter.create', 'promoter', v_id, p_command_key,
          jsonb_build_object('org_id', p_org_id, 'tier', v_tier, 'party_kind', v_party, 'commission_kind', v_kind,
                             'commission_bps', v_bps, 'commission_flat_minor', v_flat, 'currency', v_ccy, 'terms_version', 1,
                             'identity_ref', nullif(trim(coalesce(p_identity_ref,'')),''), 'event_id', v_event));
  return jsonb_build_object('status','ok','promoter_id', v_id, 'terms_version', 1);
end;
$$;

create or replace function venue.update_promoter(p_promoter_id uuid, p_patch jsonb, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_p venue.promoter%rowtype; v_k text; v_terms_change boolean := false;
        v_kind text; v_bps integer; v_flat integer; v_tier text; v_party text; v_ccy text; v_status text; v_ver integer;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-]' using errcode = '22023';
  end if;
  select * into v_p from venue.promoter where promoter_id = p_promoter_id for update;   -- admin plane
  if not found then raise exception 'not_found: promoter %', p_promoter_id using errcode = 'P0002'; end if;
  if not (kernel.has_org_role(v_p.org_id, array['org_owner','org_admin','org_promoter_manager'])
          or exists (select 1 from catalog.venue v where v.org_id = v_p.org_id
                       and (v_p.event_id is null or exists (select 1 from catalog.event e where e.event_id = v_p.event_id and e.venue_id = v.venue_id))
                       and kernel.has_venue_role(v.venue_id, array['venue_manager','venue_promoter_manager']))) then
    raise exception 'insufficient_privilege: promoter-program manager only (§11.5)' using errcode = '42501';
  end if;
  if exists (select 1 from kernel.admin_audit a where a.action = 'promoter.update' and a.actor_identity = v_uid
              and a.subject_id = p_promoter_id and a.reason_code = p_command_key) then
    return jsonb_build_object('status','idempotency_replay','promoter_id', p_promoter_id, 'terms_version', v_p.terms_version);
  end if;
  for v_k in select jsonb_object_keys(coalesce(p_patch, '{}'::jsonb)) loop
    if v_k not in ('tier','party_kind','commission_kind','commission_bps','commission_flat_minor','currency','status') then
      raise exception 'invalid_input: unwritable_key %', v_k using errcode = '22023';
    end if;
  end loop;
  v_tier   := coalesce(p_patch ->> 'tier', v_p.tier);
  v_party  := coalesce(p_patch ->> 'party_kind', v_p.party_kind);
  v_kind   := coalesce(p_patch ->> 'commission_kind', v_p.commission_kind);
  v_ccy    := coalesce(p_patch ->> 'currency', v_p.currency);
  v_status := coalesce(p_patch ->> 'status', v_p.status);
  -- an explicit kind switch replaces the amount arm wholesale; otherwise patch the present arm
  if p_patch ? 'commission_kind' and (p_patch ->> 'commission_kind') <> v_p.commission_kind then
    v_bps := (p_patch ->> 'commission_bps')::integer; v_flat := (p_patch ->> 'commission_flat_minor')::integer;
  else
    v_bps  := case when p_patch ? 'commission_bps' then (p_patch ->> 'commission_bps')::integer else v_p.commission_bps end;
    v_flat := case when p_patch ? 'commission_flat_minor' then (p_patch ->> 'commission_flat_minor')::integer else v_p.commission_flat_minor end;
  end if;
  if v_tier not in ('professional_invited','public_ambassador') then raise exception 'precondition_failed: bad_tier' using errcode = 'P0001'; end if;
  if v_party not in ('promoter','affiliate') then raise exception 'precondition_failed: bad_party_kind' using errcode = 'P0001'; end if;
  if v_party = 'promoter' and v_p.identity_id is null then raise exception 'precondition_failed: bad_party_kind — an identity-less row is an affiliate' using errcode = 'P0001'; end if;
  if v_status not in ('active','inactive') then raise exception 'invalid_input: bad_status' using errcode = '22023'; end if;
  if not ((v_kind = 'bps' and v_bps is not null and v_bps between 0 and 10000 and v_flat is null)
          or (v_kind = 'flat_per_ticket' and v_flat is not null and v_flat > 0 and v_bps is null)) then
    raise exception 'precondition_failed: terms_xor_violation' using errcode = 'P0001';
  end if;
  if v_ccy !~ '^[A-Z]{3}$' then raise exception 'precondition_failed: bad_currency' using errcode = 'P0001'; end if;
  v_terms_change := (v_tier, v_party, v_kind, v_ccy, coalesce(v_bps,-1), coalesce(v_flat,-1))
                    is distinct from (v_p.tier, v_p.party_kind, v_p.commission_kind, v_p.currency, coalesce(v_p.commission_bps,-1), coalesce(v_p.commission_flat_minor,-1));
  if not v_terms_change and v_status = v_p.status then
    return jsonb_build_object('status','noop_replay','promoter_id', p_promoter_id, 'terms_version', v_p.terms_version);   -- no version churn
  end if;
  if v_terms_change and (p_reason_code is null or p_reason_code !~ '^[A-Za-z0-9._:-]{1,64}$') then
    raise exception 'precondition_failed: reason_required — a terms change carries a reason code' using errcode = 'P0001';
  end if;
  v_ver := case when v_terms_change then v_p.terms_version + 1 else v_p.terms_version end;   -- VERSIONED, never overwritten
  update venue.promoter
     set tier = v_tier, party_kind = v_party, commission_kind = v_kind, commission_bps = v_bps, commission_flat_minor = v_flat,
         currency = v_ccy, status = v_status, terms_version = v_ver
   where promoter_id = p_promoter_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'promoter.update', 'promoter', p_promoter_id, p_command_key,
          jsonb_build_object('tier', v_p.tier, 'party_kind', v_p.party_kind, 'commission_kind', v_p.commission_kind, 'commission_bps', v_p.commission_bps,
                             'commission_flat_minor', v_p.commission_flat_minor, 'currency', v_p.currency, 'status', v_p.status, 'terms_version', v_p.terms_version),
          jsonb_build_object('tier', v_tier, 'party_kind', v_party, 'commission_kind', v_kind, 'commission_bps', v_bps,
                             'commission_flat_minor', v_flat, 'currency', v_ccy, 'status', v_status, 'terms_version', v_ver,
                             'reason_code', p_reason_code));
  return jsonb_build_object('status','ok','promoter_id', p_promoter_id, 'terms_version', v_ver);
end;
$$;

create or replace function venue.create_promoter_link(p_promoter_id uuid, p_event_id uuid, p_slug text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_p venue.promoter%rowtype; v_id uuid; v_slug text := lower(trim(p_slug)); v_prev jsonb; v_ok boolean;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-]' using errcode = '22023';
  end if;
  select * into v_p from venue.promoter where promoter_id = p_promoter_id;
  if not found then raise exception 'not_found: promoter %', p_promoter_id using errcode = 'P0002'; end if;
  if not (kernel.has_org_role(v_p.org_id, array['org_owner','org_admin','org_promoter_manager'])
          or exists (select 1 from catalog.venue v join catalog.event e on e.venue_id = v.venue_id
                      where v.org_id = v_p.org_id and e.event_id = p_event_id
                        and kernel.has_venue_role(v.venue_id, array['venue_manager','venue_promoter_manager']))) then
    raise exception 'insufficient_privilege: promoter-program manager only (§11.5) — a promoter may not mint their own link' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtext('promoter_link.create:' || v_uid::text || ':' || p_command_key));
  select a.subject_id, a.after into v_id, v_prev from kernel.admin_audit a
   where a.action = 'promoter_link.create' and a.actor_identity = v_uid and a.reason_code = p_command_key limit 1;
  if v_id is not null then
    if (v_prev ->> 'promoter_id')::uuid is distinct from p_promoter_id or (v_prev ->> 'event_id')::uuid is distinct from p_event_id or (v_prev ->> 'slug') is distinct from v_slug then
      raise exception 'precondition_failed: idempotency_conflict — command key reused with different parameters' using errcode = 'P0001';
    end if;
    return jsonb_build_object('status','idempotency_replay','link_id', v_id, 'slug', (select slug from venue.promoter_link where link_id = v_id));
  end if;
  if v_p.status <> 'active' then raise exception 'precondition_failed: promoter_inactive' using errcode = 'P0001'; end if;
  if not exists (select 1 from catalog.event e where e.event_id = p_event_id and e.org_id = v_p.org_id) then
    raise exception 'precondition_failed: event_out_of_org' using errcode = 'P0001';
  end if;
  if v_p.event_id is not null and v_p.event_id <> p_event_id then
    raise exception 'precondition_failed: event_out_of_org — a single-event promoter binds only their event' using errcode = 'P0001';
  end if;
  if v_slug is null or v_slug !~ '^[a-z0-9](?:[a-z0-9-]{1,62}[a-z0-9])$' then
    raise exception 'precondition_failed: invalid_slug_format' using errcode = 'P0001';
  end if;
  -- the global namespace makes slug_taken an existence signal: the same per-principal limiter as the availability check (red-team J)
  begin v_ok := public.check_rate_limit(v_uid, 'promoter-issue', 30, 60); exception when others then v_ok := false; end;
  if not coalesce(v_ok, false) then raise exception 'rate_limited: promoter-issue' using errcode = 'P0001'; end if;
  begin
    insert into venue.promoter_link (promoter_id, event_id, slug) values (p_promoter_id, p_event_id, v_slug) returning link_id into v_id;
  exception when unique_violation then
    raise exception 'slug_taken: % is already a promoter link', v_slug using errcode = '23505';
  end;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values (v_uid, 'promoter_link.create', 'promoter_link', v_id, p_command_key,
          jsonb_build_object('promoter_id', p_promoter_id, 'event_id', p_event_id, 'slug', v_slug));
  return jsonb_build_object('status','ok','link_id', v_id, 'slug', v_slug);
end;
$$;

create or replace function venue.set_promoter_link_status(p_link_id uuid, p_status text, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_l venue.promoter_link%rowtype; v_org uuid;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-]' using errcode = '22023';
  end if;
  if p_status not in ('active','inactive') then raise exception 'invalid_input: bad_status' using errcode = '22023'; end if;
  select * into v_l from venue.promoter_link where link_id = p_link_id for update;   -- admin plane
  if not found then raise exception 'not_found: link %', p_link_id using errcode = 'P0002'; end if;
  select p.org_id into v_org from venue.promoter p where p.promoter_id = v_l.promoter_id;
  if not (kernel.has_org_role(v_org, array['org_owner','org_admin','org_promoter_manager'])
          or exists (select 1 from catalog.event e where e.event_id = v_l.event_id
                       and kernel.has_venue_role(e.venue_id, array['venue_manager','venue_promoter_manager']))) then
    raise exception 'insufficient_privilege: promoter-program manager only (§11.5)' using errcode = '42501';
  end if;
  if v_l.status = p_status then return jsonb_build_object('status','noop_replay','link_id', p_link_id, 'link_status', v_l.status); end if;
  if p_reason_code is null or p_reason_code !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'precondition_failed: reason_required' using errcode = 'P0001';
  end if;
  -- FORWARD-ONLY in effect: no recorded attribution is touched (PL-1 / §3.17.2)
  update venue.promoter_link set status = p_status, status_changed_at = now(), status_changed_by = v_uid where link_id = p_link_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'promoter_link.status', 'promoter_link', p_link_id, p_command_key,
          jsonb_build_object('status', v_l.status), jsonb_build_object('status', p_status, 'reason_code', p_reason_code));
  return jsonb_build_object('status','ok','link_id', p_link_id, 'link_status', p_status);
end;
$$;

-- §20.9.5: {available} and NOTHING else; the §20.9.3 allow-list (never plain
--   authenticated — a global namespace is a cross-tenant oracle); rate-limited
--   per principal, fail-closed (the definer reaches the service_role-only
--   limiter as owner — E-125).
create or replace function venue.check_promoter_slug_available(p_slug text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_slug text := lower(trim(p_slug)); v_ok boolean;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if not (exists (select 1 from kernel.org_member m where m.identity_id = v_uid and m.role in ('org_owner','org_admin','org_promoter_manager'))
          or exists (select 1 from venue.staff_role s where s.identity_id = v_uid and s.role in ('venue_manager','venue_promoter_manager'))) then
    raise exception 'insufficient_privilege: promoter-program manager only (§20.9.5)' using errcode = '42501';
  end if;
  begin
    v_ok := public.check_rate_limit(v_uid, 'promoter-slug-check', 30, 60);
  exception when others then v_ok := false;   -- fail-closed
  end;
  if not coalesce(v_ok, false) then raise exception 'rate_limited: promoter-slug-check' using errcode = 'P0001'; end if;
  if v_slug is null or v_slug !~ '^[a-z0-9](?:[a-z0-9-]{1,62}[a-z0-9])$' then
    raise exception 'invalid_input: bad_slug_format' using errcode = '22023';
  end if;
  return jsonb_build_object('available', not exists (select 1 from venue.promoter_link l where l.slug = v_slug));
end;
$$;

-- ============================================================================
-- PART 6 — PROMOTER CODES (RPC §17.15; PROMOTER §7.1–§7.4, §9.3). Same
--   allow-list as PART 5. A promoter can never mint their own code (§8.2).
-- ============================================================================
create or replace function venue.create_promoter_code(
  p_promoter_id uuid, p_code_display text, p_event_ids uuid[], p_valid_from timestamptz, p_valid_until timestamptz,
  p_kind text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_p venue.promoter%rowtype; v_id uuid; v_norm text; v_ev uuid; v_prev jsonb; v_ok boolean;
        v_alpha constant text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ'; v_variants text[] := '{}'; i int; j int; v_conf text[];
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-]' using errcode = '22023';
  end if;
  select * into v_p from venue.promoter where promoter_id = p_promoter_id;
  if not found then raise exception 'not_found: promoter %', p_promoter_id using errcode = 'P0002'; end if;
  if not (kernel.has_org_role(v_p.org_id, array['org_owner','org_admin','org_promoter_manager'])
          or exists (select 1 from catalog.venue v where v.org_id = v_p.org_id
                       and (v_p.event_id is null or exists (select 1 from catalog.event e where e.event_id = v_p.event_id and e.venue_id = v.venue_id))
                       and kernel.has_venue_role(v.venue_id, array['venue_manager','venue_promoter_manager']))) then
    raise exception 'insufficient_privilege: promoter-program manager only (§11.5) — a promoter may not mint their own code' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtext('promoter_code.issue:' || v_uid::text || ':' || p_command_key));
  select a.subject_id, a.after into v_id, v_prev from kernel.admin_audit a
   where a.action = 'promoter_code.issue' and a.actor_identity = v_uid and a.reason_code = p_command_key limit 1;
  if v_id is not null then
    if (v_prev ->> 'promoter_id')::uuid is distinct from p_promoter_id or (v_prev ->> 'code_normalized') is distinct from venue.normalize_promoter_code(coalesce(p_code_display,''))
       or (v_prev ->> 'kind') is distinct from p_kind
       or (select coalesce(array_agg(x::uuid order by x), '{}') from jsonb_array_elements_text(v_prev -> 'scope') x) is distinct from (select coalesce(array_agg(y order by y), '{}') from unnest(coalesce(p_event_ids,'{}'::uuid[])) y)
       or (v_prev ->> 'valid_from')::timestamptz is distinct from p_valid_from or (v_prev ->> 'valid_until')::timestamptz is distinct from p_valid_until then
      raise exception 'precondition_failed: idempotency_conflict — command key reused with different parameters' using errcode = 'P0001';
    end if;
    return (select jsonb_build_object('status','idempotency_replay','code_id', c.code_id, 'code_display', c.code_display,
                                      'code_normalized', c.code_normalized, 'confusable_with', '[]'::jsonb)
              from venue.promoter_code c where c.code_id = v_id);
  end if;
  if v_p.status <> 'active' then raise exception 'precondition_failed: promoter_inactive' using errcode = 'P0001'; end if;
  if p_kind not in ('vanity','generated') then raise exception 'invalid_input: bad_kind' using errcode = '22023'; end if;
  v_norm := venue.normalize_promoter_code(coalesce(p_code_display, ''));
  if v_norm is null or length(v_norm) not between 4 and 16 or v_norm !~ '^[0-9A-HJKMNP-TV-Z]+$' then
    raise exception 'precondition_failed: invalid_code_format' using errcode = 'P0001';
  end if;
  if p_kind = 'generated' and length(v_norm) < 8 then raise exception 'precondition_failed: entropy_below_floor' using errcode = 'P0001'; end if;
  if p_valid_until is not null and p_valid_from is not null and p_valid_until <= p_valid_from then
    raise exception 'precondition_failed: invalid_window' using errcode = 'P0001';
  end if;
  foreach v_ev in array coalesce(p_event_ids, '{}'::uuid[]) loop
    if not exists (select 1 from catalog.event e where e.event_id = v_ev and e.org_id = v_p.org_id) then
      raise exception 'precondition_failed: event_out_of_org' using errcode = 'P0001';
    end if;
  end loop;
  begin v_ok := public.check_rate_limit(v_uid, 'promoter-issue', 30, 60); exception when others then v_ok := false; end;
  if not coalesce(v_ok, false) then raise exception 'rate_limited: promoter-issue' using errcode = 'P0001'; end if;
  begin
    insert into venue.promoter_code (promoter_id, org_id, code_display, status, valid_from, valid_until, kind, created_by)
    values (p_promoter_id, v_p.org_id, trim(p_code_display), 'active', p_valid_from, p_valid_until, p_kind, v_uid)
    returning code_id into v_id;
  exception when unique_violation then
    raise exception 'code_taken: % normalizes to an existing code', trim(p_code_display) using errcode = '23505';
  end;
  insert into venue.promoter_code_scope (code_id, event_id, added_by)
  select v_id, x, v_uid from unnest(coalesce(p_event_ids, '{}'::uuid[])) x on conflict do nothing;
  -- issue-time confusable warning: every edit-distance-1 neighbour over the alphabet
  for i in 1..length(v_norm) loop
    v_variants := v_variants || (substr(v_norm,1,i-1) || substr(v_norm,i+1));                       -- deletion
    for j in 1..32 loop
      v_variants := v_variants || (substr(v_norm,1,i-1) || substr(v_alpha,j,1) || substr(v_norm,i+1));   -- substitution
      v_variants := v_variants || (substr(v_norm,1,i-1) || substr(v_alpha,j,1) || substr(v_norm,i));     -- insertion before i
    end loop;
  end loop;
  for j in 1..32 loop v_variants := v_variants || (v_norm || substr(v_alpha,j,1)); end loop;             -- insertion at end
  -- OWN-ORG ONLY: another org's roster is never disclosed (red-team D — §9.4(4) / PROMO §8.1 A(own-org))
  select coalesce(array_agg(c.code_display order by c.code_display), '{}') into v_conf
    from venue.promoter_code c where c.code_normalized = any(v_variants) and c.code_id <> v_id and c.org_id = v_p.org_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values (v_uid, 'promoter_code.issue', 'promoter_code', v_id, p_command_key,
          jsonb_build_object('promoter_id', p_promoter_id, 'kind', p_kind, 'code_normalized', v_norm,
                             'scope', to_jsonb(coalesce(p_event_ids, '{}'::uuid[])), 'valid_from', p_valid_from, 'valid_until', p_valid_until));
  return jsonb_build_object('status','ok','code_id', v_id, 'code_display', trim(p_code_display), 'code_normalized', v_norm,
                            'confusable_with', to_jsonb(v_conf));
end;
$$;

create or replace function venue.create_promoter_codes_bulk(
  p_promoter_id uuid, p_count integer, p_kind text, p_event_ids uuid[], p_valid_from timestamptz, p_valid_until timestamptz,
  p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_p venue.promoter%rowtype; v_ev uuid; v_ids uuid[] := '{}'; v_codes text[] := '{}';
        v_alpha constant text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ'; n int; k int; v_try int; v_code text; v_id uuid; v_hex text; v_done boolean;
        v_replay uuid; v_prev jsonb; v_ok boolean;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-]' using errcode = '22023';
  end if;
  select * into v_p from venue.promoter where promoter_id = p_promoter_id;
  if not found then raise exception 'not_found: promoter %', p_promoter_id using errcode = 'P0002'; end if;
  if not (kernel.has_org_role(v_p.org_id, array['org_owner','org_admin','org_promoter_manager'])
          or exists (select 1 from catalog.venue v where v.org_id = v_p.org_id
                       and (v_p.event_id is null or exists (select 1 from catalog.event e where e.event_id = v_p.event_id and e.venue_id = v.venue_id))
                       and kernel.has_venue_role(v.venue_id, array['venue_manager','venue_promoter_manager']))) then
    raise exception 'insufficient_privilege: promoter-program manager only (§11.5)' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtext('promoter_code.issue_bulk:' || v_uid::text || ':' || p_command_key));
  select a.subject_id, a.after into v_replay, v_prev from kernel.admin_audit a
   where a.action = 'promoter_code.issue_bulk' and a.actor_identity = v_uid and a.reason_code = p_command_key limit 1;
  if v_replay is not null then
    if (v_prev ->> 'promoter_id')::uuid is distinct from p_promoter_id or (v_prev ->> 'count')::int is distinct from p_count
       or (v_prev ->> 'kind') is distinct from p_kind
       or (v_prev ->> 'valid_from')::timestamptz is distinct from p_valid_from or (v_prev ->> 'valid_until')::timestamptz is distinct from p_valid_until
       or (select coalesce(array_agg(x::uuid order by x), '{}') from jsonb_array_elements_text(v_prev -> 'scope') x) is distinct from (select coalesce(array_agg(y order by y), '{}') from unnest(coalesce(p_event_ids,'{}'::uuid[])) y) then
      raise exception 'precondition_failed: idempotency_conflict — command key reused with different parameters' using errcode = 'P0001';
    end if;
    return (select jsonb_build_object('status','idempotency_replay','count', (a.after ->> 'count')::int, 'code_ids', a.after -> 'code_ids', 'codes', a.after -> 'codes')
              from kernel.admin_audit a where a.action = 'promoter_code.issue_bulk' and a.actor_identity = v_uid and a.reason_code = p_command_key limit 1);
  end if;
  if v_p.status <> 'active' then raise exception 'precondition_failed: promoter_inactive' using errcode = 'P0001'; end if;
  if p_kind is distinct from 'generated' then raise exception 'invalid_input: bulk issuance is kind=generated only' using errcode = '22023'; end if;
  if p_count is null or p_count < 1 then raise exception 'invalid_input: count must be >= 1' using errcode = '22023'; end if;
  if p_count > 1000 then raise exception 'precondition_failed: count_exceeds_cap (1000 per call)' using errcode = 'P0001'; end if;
  if p_valid_until is not null and p_valid_from is not null and p_valid_until <= p_valid_from then
    raise exception 'precondition_failed: invalid_window' using errcode = 'P0001';
  end if;
  foreach v_ev in array coalesce(p_event_ids, '{}'::uuid[]) loop
    if not exists (select 1 from catalog.event e where e.event_id = v_ev and e.org_id = v_p.org_id) then
      raise exception 'precondition_failed: event_out_of_org' using errcode = 'P0001';
    end if;
  end loop;
  begin v_ok := public.check_rate_limit(v_uid, 'promoter-issue', 30, 60); exception when others then v_ok := false; end;
  if not coalesce(v_ok, false) then raise exception 'rate_limited: promoter-issue' using errcode = 'P0001'; end if;
  for n in 1..p_count loop
    v_done := false;
    for v_try in 1..5 loop
      -- 8 symbols × 5 bits from a CSPRNG-backed uuid (32 hex nibbles ⇒ 40 bits used)
      v_hex := replace(gen_random_uuid()::text, '-', ''); v_code := '';
      for k in 1..8 loop
        v_code := v_code || substr(v_alpha, (('x' || substr(v_hex, k*2-1, 2))::bit(8)::int % 32) + 1, 1);
      end loop;
      begin
        insert into venue.promoter_code (promoter_id, org_id, code_display, status, valid_from, valid_until, kind, created_by)
        values (p_promoter_id, v_p.org_id, v_code, 'active', p_valid_from, p_valid_until, 'generated', v_uid)
        returning code_id into v_id;
        v_done := true; exit;
      exception when unique_violation then null;   -- retry this one code
      end;
    end loop;
    if not v_done then raise exception 'precondition_failed: generation_exhausted — never silently fewer codes than requested' using errcode = 'P0001'; end if;
    v_ids := v_ids || v_id; v_codes := v_codes || v_code;
    insert into venue.promoter_code_scope (code_id, event_id, added_by)
    select v_id, x, v_uid from unnest(coalesce(p_event_ids, '{}'::uuid[])) x on conflict do nothing;
  end loop;
  -- ONE audit row for the whole program (not N)
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values (v_uid, 'promoter_code.issue_bulk', 'promoter', p_promoter_id, p_command_key,
          jsonb_build_object('promoter_id', p_promoter_id, 'count', p_count, 'kind', 'generated', 'scope', to_jsonb(coalesce(p_event_ids,'{}'::uuid[])),
                             'valid_from', p_valid_from, 'valid_until', p_valid_until,
                             'code_ids', to_jsonb(v_ids), 'codes', to_jsonb(v_codes)));
  return jsonb_build_object('status','ok','count', p_count, 'code_ids', to_jsonb(v_ids), 'codes', to_jsonb(v_codes));
end;
$$;

create or replace function venue.set_promoter_code_status(p_code_id uuid, p_status text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_c venue.promoter_code%rowtype; v_p venue.promoter%rowtype;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-]' using errcode = '22023';
  end if;
  if p_status not in ('active','inactive') then raise exception 'invalid_input: bad_status' using errcode = '22023'; end if;
  select * into v_c from venue.promoter_code where code_id = p_code_id for update;
  if not found then raise exception 'not_found: code %', p_code_id using errcode = 'P0002'; end if;
  select * into v_p from venue.promoter where promoter_id = v_c.promoter_id;
  if not (kernel.has_org_role(v_c.org_id, array['org_owner','org_admin','org_promoter_manager'])
          or exists (select 1 from catalog.venue v where v.org_id = v_c.org_id
                       and (v_p.event_id is null or exists (select 1 from catalog.event e where e.event_id = v_p.event_id and e.venue_id = v.venue_id))
                       and kernel.has_venue_role(v.venue_id, array['venue_manager','venue_promoter_manager']))) then
    raise exception 'insufficient_privilege: promoter-program manager only (§11.5)' using errcode = '42501';
  end if;
  if v_c.status = p_status then return jsonb_build_object('status','noop_replay','code_id', p_code_id, 'code_status', v_c.status); end if;
  update venue.promoter_code set status = p_status where code_id = p_code_id;   -- NOT retroactive
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, case when p_status = 'active' then 'promoter_code.activate' else 'promoter_code.deactivate' end, 'promoter_code', p_code_id, p_command_key,
          jsonb_build_object('status', v_c.status), jsonb_build_object('status', p_status));
  return jsonb_build_object('status','ok','code_id', p_code_id, 'code_status', p_status);
end;
$$;

create or replace function venue.set_promoter_code_scope(p_code_id uuid, p_add_event_ids uuid[], p_remove_event_ids uuid[], p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_c venue.promoter_code%rowtype; v_p venue.promoter%rowtype; v_ev uuid; v_added int := 0; v_removed int := 0;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-]' using errcode = '22023';
  end if;
  select * into v_c from venue.promoter_code where code_id = p_code_id for update;
  if not found then raise exception 'not_found: code %', p_code_id using errcode = 'P0002'; end if;
  select * into v_p from venue.promoter where promoter_id = v_c.promoter_id;
  if not (kernel.has_org_role(v_c.org_id, array['org_owner','org_admin','org_promoter_manager'])
          or exists (select 1 from catalog.venue v where v.org_id = v_c.org_id
                       and (v_p.event_id is null or exists (select 1 from catalog.event e where e.event_id = v_p.event_id and e.venue_id = v.venue_id))
                       and kernel.has_venue_role(v.venue_id, array['venue_manager','venue_promoter_manager']))) then
    raise exception 'insufficient_privilege: promoter-program manager only (§11.5)' using errcode = '42501';
  end if;
  if exists (select 1 from kernel.admin_audit a where a.action = 'promoter_code.scope' and a.actor_identity = v_uid
              and a.subject_id = p_code_id and a.reason_code = p_command_key) then
    return jsonb_build_object('status','idempotency_replay','code_id', p_code_id);
  end if;
  foreach v_ev in array coalesce(p_add_event_ids, '{}'::uuid[]) loop
    if not exists (select 1 from catalog.event e where e.event_id = v_ev and e.org_id = v_c.org_id) then
      raise exception 'precondition_failed: event_out_of_org' using errcode = 'P0001';
    end if;
    insert into venue.promoter_code_scope (code_id, event_id, added_by) values (p_code_id, v_ev, v_uid) on conflict do nothing;
    if found then v_added := v_added + 1; end if;
  end loop;
  -- removal changes FUTURE eligibility only; no recorded attribution is touched
  delete from venue.promoter_code_scope s where s.code_id = p_code_id and s.event_id = any(coalesce(p_remove_event_ids, '{}'::uuid[]));
  get diagnostics v_removed = row_count;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values (v_uid, 'promoter_code.scope', 'promoter_code', p_code_id, p_command_key,
          jsonb_build_object('added', to_jsonb(coalesce(p_add_event_ids,'{}'::uuid[])), 'removed', to_jsonb(coalesce(p_remove_event_ids,'{}'::uuid[]))));
  return jsonb_build_object('status','ok','code_id', p_code_id, 'added', v_added, 'removed', v_removed);
end;
$$;

create or replace function venue.set_promoter_code_window(p_code_id uuid, p_valid_from timestamptz, p_valid_until timestamptz, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_c venue.promoter_code%rowtype; v_p venue.promoter%rowtype;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-]' using errcode = '22023';
  end if;
  select * into v_c from venue.promoter_code where code_id = p_code_id for update;
  if not found then raise exception 'not_found: code %', p_code_id using errcode = 'P0002'; end if;
  select * into v_p from venue.promoter where promoter_id = v_c.promoter_id;
  if not (kernel.has_org_role(v_c.org_id, array['org_owner','org_admin','org_promoter_manager'])
          or exists (select 1 from catalog.venue v where v.org_id = v_c.org_id
                       and (v_p.event_id is null or exists (select 1 from catalog.event e where e.event_id = v_p.event_id and e.venue_id = v.venue_id))
                       and kernel.has_venue_role(v.venue_id, array['venue_manager','venue_promoter_manager']))) then
    raise exception 'insufficient_privilege: promoter-program manager only (§11.5)' using errcode = '42501';
  end if;
  if p_valid_until is not null and p_valid_from is not null and p_valid_until <= p_valid_from then
    raise exception 'precondition_failed: invalid_window' using errcode = 'P0001';
  end if;
  if v_c.valid_from is not distinct from p_valid_from and v_c.valid_until is not distinct from p_valid_until then
    return jsonb_build_object('status','noop_replay','code_id', p_code_id);
  end if;
  update venue.promoter_code set valid_from = p_valid_from, valid_until = p_valid_until where code_id = p_code_id;   -- NOT retroactive
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'promoter_code.window', 'promoter_code', p_code_id, p_command_key,
          jsonb_build_object('valid_from', v_c.valid_from, 'valid_until', v_c.valid_until),
          jsonb_build_object('valid_from', p_valid_from, 'valid_until', p_valid_until));
  return jsonb_build_object('status','ok','code_id', p_code_id);
end;
$$;

-- ============================================================================
-- PART 7 — ELIGIBILITY, PREVIEW, BINDING, THE RESOLVER, ADJUDICATION
--   (PROMOTER §1.2 E1–E7, §2.3 P0–P10/M1–M4, §3, §7.5–§7.8, §7.11, §9.5;
--   RPC §17.14/§17.16/§17.18). Eligibility is evaluated at the SAME points the
--   spec names (preview: advisory; bind: advisory; resolver: authoritative).
--   E-126: E1 additionally treats a promoter whose identity is DELETION_PENDING
--   or ERASED as ineligible (E-23 class; fail-to-safe — the org keeps the
--   commission rather than accruing an obligation to a tombstone).
-- ============================================================================
-- 7a — preview (§17.16): exactly one of two payloads. Authenticated callers are
--   additionally limited in-body (E-125 — a direct PostgREST call would
--   otherwise bypass the edge limiter); the edge wrapper (service_role, anon
--   path) carries its own limiter and is not double-counted (auth.uid() NULL).
create or replace function venue.preview_promoter_code(p_code_display text, p_session_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_ok boolean; v_norm text; v_event uuid; v_event_org uuid; v_row record; v_name text;
begin
  if v_uid is not null then
    begin v_ok := public.check_rate_limit(v_uid, 'promoter-code-preview', 10, 60);
    exception when others then v_ok := false; end;
    if not coalesce(v_ok, false) then raise exception 'rate_limited: promoter-code-preview' using errcode = 'P0001'; end if;
  end if;
  v_norm := venue.normalize_promoter_code(coalesce(p_code_display, ''));
  select es.event_id, e.org_id into v_event, v_event_org
    from catalog.event_session es join catalog.event e on e.event_id = es.event_id where es.session_id = p_session_id;
  if v_event is null or v_norm is null or length(v_norm) not between 4 and 16 then
    return jsonb_build_object('status','not_applicable');
  end if;
  select c.code_id, p.promoter_id, p.identity_id, p.status as p_status, c.status as c_status into v_row
    from venue.promoter_code c join venue.promoter p on p.promoter_id = c.promoter_id
   where c.code_normalized = v_norm
     and p.status = 'active' and c.status = 'active'                                                    -- E1 · E2
     and (c.valid_from is null or c.valid_from <= now()) and (c.valid_until is null or now() < c.valid_until)   -- E3 (half-open)
     and c.org_id = v_event_org                                                                          -- E4
     and (p.event_id is null or p.event_id = v_event)                                                    -- E5
     and (not exists (select 1 from venue.promoter_code_scope s where s.code_id = c.code_id)
          or exists (select 1 from venue.promoter_code_scope s where s.code_id = c.code_id and s.event_id = v_event))   -- E6/E7
     and (p.identity_id is null or coalesce((select ie.deletion_state from kernel.identity_ext ie where ie.identity_id = p.identity_id), 'ACTIVE') = 'ACTIVE');   -- E-126
  if v_row.code_id is null then return jsonb_build_object('status','not_applicable'); end if;
  select pr.display_name into v_name from public.profiles pr where pr.id = v_row.identity_id;
  -- never the request parameter (red-team H-2): an identity-less affiliate previews as a neutral label
  return jsonb_build_object('status','eligible','promoter_display_name', coalesce(nullif(v_name,''), 'Promoter'), 'method_hint','code');
end;
$$;

-- 7b — bind (§17.18): the candidate on a PENDING order; last-write-wins, audited,
--   never fails the order; M4 ⇒ attribution_frozen. Scalar parameters make M1/M2
--   (two codes / two links in one request) structurally unpresentable here.
create or replace function venue.bind_order_attribution(p_order_id uuid, p_code_display text, p_link_slug text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_o venue."order"%rowtype; v_event uuid; v_event_org uuid; v_venue uuid;
        v_code uuid; v_link uuid; v_norm text; v_bound boolean := false;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-]' using errcode = '22023';
  end if;
  select * into v_o from venue."order" where order_id = p_order_id for update;   -- Order (rank 3) — the only lock
  if not found then raise exception 'not_found: order %', p_order_id using errcode = 'P0002'; end if;
  select es.event_id, e.org_id, e.venue_id into v_event, v_event_org, v_venue
    from catalog.event_session es join catalog.event e on e.event_id = es.event_id where es.session_id = v_o.event_session_id;
  if not (v_o.buyer_id = v_uid
          or (v_o.source = 'door' and kernel.has_venue_role(v_venue, array['venue_box_office','venue_manager']))) then
    raise exception 'insufficient_privilege: the order''s buyer, or a box-office principal for an on-behalf (door) order' using errcode = '42501';
  end if;
  if exists (select 1 from kernel.admin_audit a where a.action = 'attribution.candidate_changed' and a.actor_identity = v_uid
              and a.subject_id = p_order_id and a.reason_code = p_command_key) then
    return jsonb_build_object('status','idempotency_replay','order_id', p_order_id);
  end if;
  if v_o.status <> 'pending' then raise exception 'attribution_frozen: order % is % — the candidate froze at paid', p_order_id, v_o.status using errcode = 'P0001'; end if;
  -- code channel (advisory eligibility now; the resolver re-evaluates at freeze)
  if p_code_display is not null and length(trim(p_code_display)) > 0 then
    v_norm := venue.normalize_promoter_code(p_code_display);
    select c.code_id into v_code
      from venue.promoter_code c join venue.promoter p on p.promoter_id = c.promoter_id
     where c.code_normalized = v_norm and p.status = 'active' and c.status = 'active'
       and (c.valid_from is null or c.valid_from <= now()) and (c.valid_until is null or now() < c.valid_until)
       and c.org_id = v_event_org and (p.event_id is null or p.event_id = v_event)
       and (not exists (select 1 from venue.promoter_code_scope s where s.code_id = c.code_id)
            or exists (select 1 from venue.promoter_code_scope s where s.code_id = c.code_id and s.event_id = v_event))
       and (p.identity_id is null or coalesce((select ie.deletion_state from kernel.identity_ext ie where ie.identity_id = p.identity_id), 'ACTIVE') = 'ACTIVE');
  end if;
  -- link channel
  if p_link_slug is not null and length(trim(p_link_slug)) > 0 then
    select l.link_id into v_link
      from venue.promoter_link l join venue.promoter p on p.promoter_id = l.promoter_id
     where l.slug = lower(trim(p_link_slug)) and l.status = 'active' and p.status = 'active'
       and l.event_id = v_event and p.org_id = v_event_org
       and (p.identity_id is null or coalesce((select ie.deletion_state from kernel.identity_ext ie where ie.identity_id = p.identity_id), 'ACTIVE') = 'ACTIVE');
  end if;
  -- each channel is written ONLY when presented (red-team H-1): a code-only call never wipes a
  -- bound link and vice versa — P3/P5/P9 stay reachable for the natural client call.
  update venue."order"
     set attribution_candidate_code_id = case when p_code_display is null then attribution_candidate_code_id else v_code end,
         attribution_candidate_link_id = case when p_link_slug is null then attribution_candidate_link_id else v_link end,
         updated_at = now()
   where order_id = p_order_id
   returning attribution_candidate_code_id, attribution_candidate_link_id into v_code, v_link;
  v_bound := (case when p_code_display is not null then v_code is not null else false end)
             or (case when p_link_slug is not null then v_link is not null else false end);
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'attribution.candidate_changed', 'order', p_order_id, p_command_key,
          jsonb_build_object('code_id', v_o.attribution_candidate_code_id, 'link_id', v_o.attribution_candidate_link_id),
          jsonb_build_object('code_id', v_code, 'link_id', v_link));
  if v_bound then return jsonb_build_object('status','ok','bound', true, 'order_id', p_order_id); end if;
  return jsonb_build_object('status','ok','bound', false, 'reason','not_applicable', 'order_id', p_order_id);
end;
$$;

-- 7c — THE RESOLVER (§17.14 / PROMOTER §2.3): SEAM-2 body-only replacement of the
--   085 stub. Signature (p_order_id uuid) RETURNS void FROZEN. Sole writer of
--   venue.attribution. NEVER raises: every non-happy path is "no row"; an
--   unexpected error is caught, landed in kernel.admin_audit as
--   attribution.resolver_error (system actor), and swallowed.
create or replace function venue.resolve_order_attribution(p_order_id uuid)
returns void language plpgsql volatile security definer set search_path = ''
as $$
declare v_sys constant uuid := '00000000-0000-0000-0000-0000000000f1';
        v_o venue."order"%rowtype; v_event uuid; v_event_org uuid;
        -- scalars, NOT record variables: a record never assigned in a session cannot be
        -- type-resolved on first use ("record is not assigned yet") — caught by the race harness.
        v_code_cid uuid; v_code_pid uuid; v_link_lid uuid; v_link_pid uuid; v_code_e boolean := false; v_link_e boolean := false;
        -- the promoter row is read IN the eligibility statement (one snapshot — no torn read of
        -- status vs terms between two statements; red-team A1)
        v_pc venue.promoter%rowtype; v_pl venue.promoter%rowtype;
        v_winner uuid; v_method text; v_touch boolean; v_reason text; v_displaced uuid; v_code_id uuid; v_link_id uuid;
        v_p venue.promoter%rowtype; v_basis bigint; v_qty bigint; v_credited bigint; v_fp text;
        v_reasons text[] := '{}'; v_id uuid;
begin
  begin
    if exists (select 1 from venue.attribution a where a.order_id = p_order_id) then return; end if;   -- P0 (replay)
    select * into v_o from venue."order" where order_id = p_order_id;
    if v_o.order_id is null or v_o.status = 'pending' then return; end if;                            -- freeze is at paid (D7)
    if v_o.attribution_candidate_code_id is null and v_o.attribution_candidate_link_id is null then return; end if;   -- P10
    select es.event_id, e.org_id into v_event, v_event_org
      from catalog.event_session es join catalog.event e on e.event_id = es.event_id where es.session_id = v_o.event_session_id;
    -- CODE channel → E / X (no locks: the snapshot decides — §3.5)
    if v_o.attribution_candidate_code_id is not null then
      select p.* into v_pc
        from venue.promoter_code c join venue.promoter p on p.promoter_id = c.promoter_id
       where c.code_id = v_o.attribution_candidate_code_id
         and p.status = 'active' and c.status = 'active'
         and (c.valid_from is null or c.valid_from <= now()) and (c.valid_until is null or now() < c.valid_until)
         and c.org_id = v_event_org and (p.event_id is null or p.event_id = v_event)
         and (not exists (select 1 from venue.promoter_code_scope s where s.code_id = c.code_id)
              or exists (select 1 from venue.promoter_code_scope s where s.code_id = c.code_id and s.event_id = v_event))
         and (p.identity_id is null or coalesce((select ie.deletion_state from kernel.identity_ext ie where ie.identity_id = p.identity_id), 'ACTIVE') = 'ACTIVE');
      v_code_e := (v_pc.promoter_id is not null);
      if v_code_e then v_code_cid := v_o.attribution_candidate_code_id; v_code_pid := v_pc.promoter_id; end if;
    end if;
    -- LINK channel → E / X
    if v_o.attribution_candidate_link_id is not null then
      select p.* into v_pl
        from venue.promoter_link l join venue.promoter p on p.promoter_id = l.promoter_id
       where l.link_id = v_o.attribution_candidate_link_id
         and l.status = 'active' and p.status = 'active' and l.event_id = v_event and p.org_id = v_event_org
         and (p.identity_id is null or coalesce((select ie.deletion_state from kernel.identity_ext ie where ie.identity_id = p.identity_id), 'ACTIVE') = 'ACTIVE');
      v_link_e := (v_pl.promoter_id is not null);
      if v_link_e then v_link_lid := v_o.attribution_candidate_link_id; v_link_pid := v_pl.promoter_id; end if;
    end if;
    -- THE TABLE (first matching row wins; P7–P9 fall through to "no row")
    if v_code_e and v_link_e and v_code_pid = v_link_pid then
      v_winner := v_code_pid; v_method := 'code'; v_touch := true;  v_reason := 'code_corroborated_by_link'; v_code_id := v_code_cid; v_link_id := v_link_lid;   -- P1
    elsif v_code_e and v_link_e then
      v_winner := v_code_pid; v_method := 'code'; v_touch := false; v_reason := 'code_over_link'; v_code_id := v_code_cid; v_displaced := v_link_pid;   -- P2
    elsif v_code_e and v_o.attribution_candidate_link_id is not null then
      v_winner := v_code_pid; v_method := 'code'; v_touch := false; v_reason := 'code_only_link_ineligible'; v_code_id := v_code_cid;   -- P3
    elsif v_code_e then
      v_winner := v_code_pid; v_method := 'code'; v_touch := false; v_reason := 'code_only'; v_code_id := v_code_cid;   -- P4
    elsif v_link_e and v_o.attribution_candidate_code_id is not null then
      v_winner := v_link_pid; v_method := 'link'; v_touch := true;  v_reason := 'link_after_code_ineligible'; v_link_id := v_link_lid;   -- P5
    elsif v_link_e then
      v_winner := v_link_pid; v_method := 'link'; v_touch := true;  v_reason := 'link_only'; v_link_id := v_link_lid;   -- P6
    else
      return;   -- P7 · P8 · P9: none_eligible — no row
    end if;
    v_p := case when v_method = 'code' then v_pc else v_pl end;   -- the SAME snapshot the eligibility was decided on
    -- §6.2: the order's currency must be the promoter's terms currency — otherwise no attribution (never a raise; red-team B1)
    if v_o.currency is distinct from v_p.currency then return; end if;
    -- basis (§6.1 face subtotal) and accrual (§6.2, FLOOR)
    select coalesce(sum(oi.unit_price_minor::bigint * oi.quantity), 0), coalesce(sum(oi.quantity), 0) into v_basis, v_qty
      from venue.order_item oi where oi.order_id = p_order_id;
    v_credited := case when v_p.commission_kind = 'bps' then floor(v_basis * v_p.commission_bps / 10000.0)::bigint
                       else v_p.commission_flat_minor::bigint * v_qty end;
    -- self-deal detectors (§9.5): flag, never block
    if v_p.identity_id is not null and v_o.buyer_id = v_p.identity_id then v_reasons := array_append(v_reasons, 'same_identity'); end if;
    select pn.instrument_fingerprint into v_fp from kernel.payment_native pn where pn.order_id = p_order_id order by pn.linked_at desc limit 1;
    if v_fp is not null and v_p.identity_id is not null and exists (
         select 1 from kernel.payment_native pn2 join venue."order" o2 on o2.order_id = pn2.order_id
          where pn2.instrument_fingerprint = v_fp and pn2.order_id <> p_order_id and o2.buyer_id = v_p.identity_id) then
      v_reasons := array_append(v_reasons, 'same_instrument');
    end if;
    insert into venue.attribution (link_id, order_id, promoter_id, org_id, event_id, code_id, method, touch_corroborated,
      self_deal_flag, self_deal_reasons, displaced_promoter_id, terms_version, commission_kind, commission_bps_applied,
      commission_flat_minor_applied, basis_minor, credited_amount_minor, currency, resolution_reason, occurred_at, order_paid_at)
    values (v_link_id, p_order_id, v_winner, v_o.org_id, v_event, v_code_id, v_method, v_touch,
      cardinality(v_reasons) > 0, v_reasons, v_displaced, v_p.terms_version, v_p.commission_kind, v_p.commission_bps,
      v_p.commission_flat_minor, v_basis::integer, v_credited::integer, v_o.currency, v_reason, now(), v_o.updated_at)
    returning id into v_id;
    -- G-25 #31 AttributionRecorded — BE emit (OR-14), keyed on order_id (§14.5)
    begin
      perform notify.emit_event('attribution_recorded', 'order', p_order_id, 'attribution_recorded:' || p_order_id::text,
        jsonb_build_object('attribution_id', v_id, 'promoter_id', v_winner, 'method', v_method, 'credited_amount_minor', v_credited));
    exception when others then null; end;
  exception when unique_violation then
    return;   -- a concurrent finalize won: P0 — the existing row stands
  when others then
    -- §7.11: an attribution failure NEVER fails a sale. Land it, swallow it.
    begin
      insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
      -- transient classes (40 = txn rollback/deadlock/serialization, 57 = operator intervention/cancel)
      -- are landed under a distinct reason so they are separable from logic failures (red-team A3)
      values (v_sys, 'attribution.resolver_error', 'order', p_order_id,
              case when sqlstate like '40%' or sqlstate like '57%' then 'transient.' || sqlstate else coalesce(nullif(sqlstate,''), 'XX000') end,
              jsonb_build_object('message', left(sqlerrm, 200), 'audience', 'platform_support'));
    exception when others then null; end;
    return;
  end;
end;
$$;

-- 7d — adjudication (§17.18 AUTHZ-H10): the SOLE writer of venue.attribution_review.
--   BOTH promoter-manager labels DENIED; platform_admin holds no EXEC.
create or replace function venue.review_attribution_flag(p_attribution_id uuid, p_decision text, p_reason_code text, p_note text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_a venue.attribution%rowtype; v_venue uuid; v_seq integer; v_id uuid; v_prev jsonb;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-]' using errcode = '22023';
  end if;
  select * into v_a from venue.attribution where id = p_attribution_id;
  if not found then raise exception 'not_found: attribution %', p_attribution_id using errcode = 'P0002'; end if;
  select e.venue_id into v_venue from catalog.event e where e.event_id = v_a.event_id;
  -- E-76: the venue arm binds only while the venue is still operated by the attribution's org;
  -- the org arm is the ATTRIBUTION's org (whose money this is), never the venue's current operator
  if not ((kernel.has_venue_role(v_venue, array['venue_manager'])
             and (select v.org_id from catalog.venue v where v.venue_id = v_venue) = v_a.org_id)
          or kernel.has_org_role(v_a.org_id, array['org_owner','org_admin'])
          or kernel.is_platform(array['platform_risk'])) then
    raise exception 'insufficient_privilege: venue_manager / org_owner / org_admin / platform_risk only (AUTHZ-H10 — both promoter-manager labels denied)' using errcode = '42501';
  end if;
  -- separation of duties: the decider is never the attributed promoter's own identity
  if v_uid = (select p.identity_id from venue.promoter p where p.promoter_id = v_a.promoter_id) then
    raise exception 'insufficient_privilege: a promoter cannot adjudicate a flag on their own attribution' using errcode = '42501';
  end if;
  if p_decision not in ('release','deny') then raise exception 'invalid_input: bad_decision' using errcode = '22023'; end if;
  if p_reason_code is null or p_reason_code not in ('legitimate_guest_purchase','self_purchase_confirmed','shared_instrument_explained',
                                                    'policy_violation','duplicate_account_suspected','other') then
    raise exception 'invalid_reason_code: %', coalesce(p_reason_code,'<null>') using errcode = '22023';
  end if;
  if not v_a.self_deal_flag then raise exception 'not_flagged: attribution % carries no self-deal flag', p_attribution_id using errcode = 'P0001'; end if;
  perform pg_advisory_xact_lock(hashtext('attribution.review:' || p_attribution_id::text));   -- seq assignment serialized; pay_promoter_commission takes the SAME key
  -- replay BEFORE the settled gate (red-team B4): a retried, already-applied review replays instead of erroring
  select a.subject_id, a.after into v_id, v_prev from kernel.admin_audit a
   where a.action = 'attribution.review' and a.actor_identity = v_uid and a.reason_code = p_command_key
     and a.after ->> 'attribution_id' = p_attribution_id::text limit 1;
  if v_id is not null then
    if (v_prev ->> 'decision') is distinct from p_decision or (v_prev ->> 'reason_code') is distinct from p_reason_code then
      raise exception 'precondition_failed: idempotency_conflict — command key reused with different parameters' using errcode = 'P0001';
    end if;
    return jsonb_build_object('status','idempotency_replay','review_id', v_id, 'attribution_id', p_attribution_id);
  end if;
  if exists (select 1 from venue.settlement_line l where l.cause = 'promoter_commission' and l.cause_ref = p_attribution_id) then
    raise exception 'attribution_settled: the commission line exists — the money and the decision froze together' using errcode = 'P0001';
  end if;
  select coalesce(max(r.seq), 0) + 1 into v_seq from venue.attribution_review r where r.attribution_id = p_attribution_id;
  insert into venue.attribution_review (attribution_id, seq, decision, reason_code, note, decided_by)
  values (p_attribution_id, v_seq, p_decision, p_reason_code, p_note, v_uid) returning review_id into v_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values (v_uid, 'attribution.review', 'attribution_review', v_id, p_command_key,
          jsonb_build_object('attribution_id', p_attribution_id, 'seq', v_seq, 'decision', p_decision, 'reason_code', p_reason_code));
  return jsonb_build_object('status','ok','review_id', v_id, 'attribution_id', p_attribution_id, 'seq', v_seq, 'decision', p_decision);
end;
$$;

-- ============================================================================
-- PART 8 — READS (RPC §17.19 / PROMOTER §8.5–§8.6) + the promoter predicate
--   (RPC §1.1c). Promoter authority = a LIVE venue.promoter row (identity_id =
--   auth.uid(), status='active'); the promoter id set is derived, never accepted.
-- ============================================================================
-- 8a — kernel.is_promoter_for_event (§1.1c, AUTHZ-M10): link OR code route.
--   E-127: §1.1c's sketch joins scope rows; an unscoped org-wide code is eligible
--   for every org event (E7) — the predicate carries E4–E7 exactly as the resolver does.
create or replace function kernel.is_promoter_for_event(p_event_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from venue.promoter p
     where p.identity_id = auth.uid() and p.status = 'active'
       and coalesce((select ie.deletion_state from kernel.identity_ext ie where ie.identity_id = p.identity_id), 'ACTIVE') = 'ACTIVE'   -- E1′ (E-126)
       and (p.event_id is null or p.event_id = p_event_id)
       and exists (select 1 from catalog.event e where e.event_id = p_event_id and e.org_id = p.org_id)
       and ( exists (select 1 from venue.promoter_link l
                      where l.promoter_id = p.promoter_id and l.event_id = p_event_id and l.status = 'active')
          or exists (select 1 from venue.promoter_code c
                      where c.promoter_id = p.promoter_id and c.status = 'active'
                        and (c.valid_from is null or c.valid_from <= now()) and (c.valid_until is null or now() < c.valid_until)   -- E3
                        and (not exists (select 1 from venue.promoter_code_scope s where s.code_id = c.code_id)
                             or exists (select 1 from venue.promoter_code_scope s where s.code_id = c.code_id and s.event_id = p_event_id))) ) )
$$;

-- 8b — get_my_promoter_summary: per-event + total, own rows only. Never buyer
--   identity/contact, order ids, org totals, instrument_fingerprint.
create or replace function venue.get_my_promoter_summary(p_org_id uuid, p_event_id uuid, p_window jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_from timestamptz; v_to timestamptz; v_total jsonb; v_events jsonb;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if not exists (select 1 from venue.promoter p where p.identity_id = v_uid and p.status = 'active' and p.org_id = p_org_id) then
    raise exception 'insufficient_privilege: no live promoter row for this org' using errcode = '42501';
  end if;
  v_from := (p_window ->> 'from')::timestamptz; v_to := (p_window ->> 'to')::timestamptz;
  with mine as (
    select a.* from venue.attribution a
     where a.promoter_id in (select p.promoter_id from venue.promoter p where p.identity_id = v_uid and p.status = 'active')
       and a.org_id = p_org_id
       and (p_event_id is null or a.event_id = p_event_id)
       and (v_from is null or a.order_paid_at >= v_from) and (v_to is null or a.order_paid_at < v_to)
  ),
  held as (
    select m.id from mine m where m.self_deal_flag
       and coalesce((select r.decision from venue.attribution_review r where r.attribution_id = m.id order by r.seq desc limit 1), 'held') <> 'release'
  ),
  paid as (
    select po.cause_ref, po.amount_minor from kernel.payout po
     where po.cause = 'promoter_commission' and po.status = 'paid' and po.cause_ref in (select id from mine)
  ),
  per_event as (
    select m.event_id, e.title,
           (select coalesce(sum(oi.quantity),0) from venue.order_item oi where oi.order_id in (select order_id from mine x where x.event_id = m.event_id)) as tickets_attributed,
           sum(m.basis_minor) as gross_attributed_minor,
           sum(m.credited_amount_minor) as commission_accrued_minor,
           sum(m.credited_amount_minor) filter (where m.id in (select id from held)) as commission_held_minor,
           (select coalesce(sum(p.amount_minor),0) from paid p where p.cause_ref in (select id from mine x where x.event_id = m.event_id)) as commission_paid_minor
      from mine m join catalog.event e on e.event_id = m.event_id
     group by m.event_id, e.title
  )
  select jsonb_build_object(
           'tickets_attributed', (select coalesce(sum(oi.quantity),0) from venue.order_item oi where oi.order_id in (select order_id from mine)),
           'gross_attributed_minor', (select coalesce(sum(basis_minor),0) from mine),
           'commission_accrued_minor', (select coalesce(sum(credited_amount_minor),0) from mine),
           'commission_held_minor', (select coalesce(sum(m.credited_amount_minor),0) from mine m where m.id in (select id from held)),
           'commission_paid_minor', (select coalesce(sum(amount_minor),0) from paid),
           'code_count', (select count(*) from venue.promoter_code c where c.promoter_id in (select p.promoter_id from venue.promoter p where p.identity_id = v_uid and p.status = 'active' and p.org_id = p_org_id)),
           'link_count', (select count(*) from venue.promoter_link l where l.promoter_id in (select p.promoter_id from venue.promoter p where p.identity_id = v_uid and p.status = 'active' and p.org_id = p_org_id))),
         coalesce((select jsonb_agg(jsonb_build_object('event_id', pe.event_id, 'event_title', pe.title, 'tickets_attributed', pe.tickets_attributed,
                    'gross_attributed_minor', pe.gross_attributed_minor, 'commission_accrued_minor', pe.commission_accrued_minor,
                    'commission_held_minor', coalesce(pe.commission_held_minor,0), 'commission_paid_minor', pe.commission_paid_minor) order by pe.event_id) from per_event pe), '[]'::jsonb)
    into v_total, v_events;
  return v_total || jsonb_build_object('per_event', v_events);
end;
$$;

-- 8c — list_my_attributions: EXACT projection; keyset (order_paid_at DESC, id DESC).
--   Redacted: buyer name/email/id, order ref, displaced_promoter_id, note,
--   touch_corroborated, instrument_fingerprint.
create or replace function venue.list_my_attributions(p_org_id uuid, p_filters jsonb, p_cursor jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_limit int := least(greatest(coalesce((p_filters ->> 'limit')::int, 50), 1), 200);
        v_c_at timestamptz := (p_cursor ->> 'order_paid_at')::timestamptz; v_c_id uuid := (p_cursor ->> 'id')::uuid;
        v_event uuid := (p_filters ->> 'event_id')::uuid; v_rows jsonb; v_last record;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if not exists (select 1 from venue.promoter p where p.identity_id = v_uid and p.status = 'active' and p.org_id = p_org_id) then
    raise exception 'insufficient_privilege: no live promoter row for this org' using errcode = '42501';
  end if;
  with page as (
    select a.id, a.order_paid_at, a.event_id, a.order_id, a.basis_minor, a.credited_amount_minor, a.method, a.terms_version,
           a.self_deal_flag, a.self_deal_reasons
      from venue.attribution a
     where a.promoter_id in (select p.promoter_id from venue.promoter p where p.identity_id = v_uid and p.status = 'active')
       and a.org_id = p_org_id and (v_event is null or a.event_id = v_event)
       and (v_c_at is null or (a.order_paid_at, a.id) < (v_c_at, v_c_id))
     order by a.order_paid_at desc, a.id desc limit v_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'occurred_at', pg.order_paid_at,
           'event_title', (select e.title from catalog.event e where e.event_id = pg.event_id),
           'ticket_type', (select string_agg(tt.name, ', ' order by tt.name) from venue.order_item oi join venue.ticket_type tt on tt.ticket_type_id = oi.ticket_type_id where oi.order_id = pg.order_id),
           'qty', (select coalesce(sum(oi.quantity),0) from venue.order_item oi where oi.order_id = pg.order_id),
           'basis_minor', pg.basis_minor, 'credited_amount_minor', pg.credited_amount_minor, 'method', pg.method,
           'terms_version', pg.terms_version, 'self_deal_flag', pg.self_deal_flag, 'self_deal_reasons', to_jsonb(pg.self_deal_reasons),
           'review_decision', (select r.decision from venue.attribution_review r where r.attribution_id = pg.id order by r.seq desc limit 1),
           'review_reason_code', (select r.reason_code from venue.attribution_review r where r.attribution_id = pg.id order by r.seq desc limit 1),
           'payout_status', (select po.status from kernel.payout po where po.cause = 'promoter_commission' and po.cause_ref = pg.id order by po.created_at desc limit 1),
           'cursor', jsonb_build_object('order_paid_at', pg.order_paid_at, 'id', pg.id)) order by pg.order_paid_at desc, pg.id desc), '[]'::jsonb)
    into v_rows from page pg;
  return jsonb_build_object('rows', v_rows, 'next_cursor', case when jsonb_array_length(v_rows) = v_limit then v_rows -> (v_limit - 1) -> 'cursor' else null end);
end;
$$;

-- 8d — list_promoter_attributions: the dash §10.6 view (order REFERENCE, never an
--   attendee); scope venue | event | org; the back-office allow-list (§11.5).
create or replace function venue.list_promoter_attributions(p_scope_kind text, p_scope_id uuid, p_filters jsonb, p_cursor jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_limit int := least(greatest(coalesce((p_filters ->> 'limit')::int, 50), 1), 200);
        v_c_at timestamptz := (p_cursor ->> 'order_paid_at')::timestamptz; v_c_id uuid := (p_cursor ->> 'id')::uuid;
        v_org uuid; v_venue uuid; v_event uuid; v_promoter uuid := (p_filters ->> 'promoter_id')::uuid; v_rows jsonb;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_scope_kind = 'venue' then
    select v.org_id into v_org from catalog.venue v where v.venue_id = p_scope_id; v_venue := p_scope_id;
  elsif p_scope_kind = 'event' then
    select e.org_id, e.venue_id into v_org, v_venue from catalog.event e where e.event_id = p_scope_id; v_event := p_scope_id;
  elsif p_scope_kind = 'org' then
    select o.org_id into v_org from kernel.organization o where o.org_id = p_scope_id;
  else
    raise exception 'invalid_input: scope_kind must be venue | event | org' using errcode = '22023';
  end if;
  if v_org is null then raise exception 'not_found: scope %', p_scope_id using errcode = 'P0002'; end if;
  -- platform_risk (A) / platform_support (V) / platform_admin read the ledger ONLY through this projection (AUTHZ-M9; RLS §9.17)
  if not ((v_venue is not null and kernel.has_venue_role(v_venue, array['venue_manager','venue_finance','venue_promoter_manager']))
          or kernel.has_org_role(v_org, array['org_owner','org_admin','org_finance','org_promoter_manager'])
          or kernel.is_platform(array['platform_support','platform_risk','platform_admin'])) then
    raise exception 'insufficient_privilege: venue_manager / venue_finance / venue_promoter_manager or org_owner / org_admin / org_finance / org_promoter_manager' using errcode = '42501';
  end if;
  with page as (
    select a.* from venue.attribution a
     where a.org_id = v_org
       and (v_event is null or a.event_id = v_event)
       and (v_venue is null or exists (select 1 from catalog.event e where e.event_id = a.event_id and e.venue_id = v_venue))
       and (v_promoter is null or a.promoter_id = v_promoter)
       and (v_c_at is null or (a.order_paid_at, a.id) < (v_c_at, v_c_id))
     order by a.order_paid_at desc, a.id desc limit v_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'when', pg.order_paid_at,
           'order_ref', left(replace(pg.order_id::text,'-',''), 8),
           'event_id', pg.event_id, 'promoter_id', pg.promoter_id,
           'ticket_type', (select string_agg(tt.name, ', ' order by tt.name) from venue.order_item oi join venue.ticket_type tt on tt.ticket_type_id = oi.ticket_type_id where oi.order_id = pg.order_id),
           'qty', (select coalesce(sum(oi.quantity),0) from venue.order_item oi where oi.order_id = pg.order_id),
           'gross_attributed_minor', pg.basis_minor, 'commission_minor', pg.credited_amount_minor,
           'method', pg.method, 'touch_corroborated', pg.touch_corroborated,
           'self_deal_flag', pg.self_deal_flag, 'self_deal_reasons', to_jsonb(pg.self_deal_reasons),
           'terms_version', pg.terms_version, 'resolution_reason', pg.resolution_reason,
           'displaced_promoter', case when pg.displaced_promoter_id is null then null else
             coalesce((select pr.display_name from venue.promoter dp join public.profiles pr on pr.id = dp.identity_id where dp.promoter_id = pg.displaced_promoter_id), 'promoter ' || left(pg.displaced_promoter_id::text, 8)) end,
           'review_decision', (select r.decision from venue.attribution_review r where r.attribution_id = pg.id order by r.seq desc limit 1),
           'settled', exists (select 1 from venue.settlement_line l where l.cause = 'promoter_commission' and l.cause_ref = pg.id),
           'cursor', jsonb_build_object('order_paid_at', pg.order_paid_at, 'id', pg.id)) order by pg.order_paid_at desc, pg.id desc), '[]'::jsonb)
    into v_rows from page pg;
  return jsonb_build_object('rows', v_rows, 'next_cursor', case when jsonb_array_length(v_rows) = v_limit then v_rows -> (v_limit - 1) -> 'cursor' else null end);
end;
$$;

-- ============================================================================
-- PART 9 — THE COMMISSION LEG (RPC §20.7.2 / §20.11.2; PROMOTER §6.3):
--   kernel.pay_promoter_commission (authored HERE — SEAM-1: reads venue.
--   attribution/promoter) and the SEAM-2 body of kernel.settlement_commission_lines.
--   kernel.close_settlement (087, immutable) reaches the leg ONLY through the
--   seam; the seam computes the payable set, calls pay_promoter_commission
--   (payout rows, audit, BE emit), and returns the candidate LINES that 087
--   inserts under UNIQUE(settlement_id,cause,cause_ref) + the 090 partial unique.
--   Payable is recomputed from LIVE state (surviving = non-voided atoms; a
--   refunded order ⇒ 0 ⇒ NO line); a flagged attribution whose effective
--   review is not 'release' ⇒ NO line (HOLD); an identity-less payee or a
--   currency mismatch ⇒ NO line (held; E-128). Lines are NEGATIVE (E-73 org
--   debit); the payout is +payable to the promoter's identity.
-- ============================================================================
create or replace function kernel.pay_promoter_commission(p_settlement_id uuid, p_attribution_ids uuid[], p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_s venue.settlement%rowtype; v_ctx text; v_a venue.attribution%rowtype; v_p venue.promoter%rowtype; v_o venue."order"%rowtype;
        v_basis bigint; v_qty bigint; v_payable bigint; v_decision text; v_po uuid; v_key text;
        v_lines jsonb := '[]'::jsonb; v_held jsonb := '[]'::jsonb; v_ids uuid[] := '{}'; v_n int := 0; v_id uuid;
        v_sys constant uuid := '00000000-0000-0000-0000-0000000000f1';
begin
  -- FORBIDDEN CALLERS: every client and human role. Structural: the call stack
  -- must carry the seam AND the 087 close (asserted, not assumed).
  get diagnostics v_ctx = pg_context;
  if v_ctx !~ 'kernel\.settlement_commission_lines' or v_ctx !~ 'kernel\.close_settlement' then
    raise exception 'insufficient_privilege: pay_promoter_commission is reachable only from kernel.close_settlement via the commission seam' using errcode = '42501';
  end if;
  -- the settlement is being closed in THIS transaction: the call-stack guard above is the enforcement;
  -- the NOWAIT re-lock only refuses a settlement another transaction holds (it cannot prove the
  -- caller's own lock — a self-held row lock is immediate). Rank 6, same txn.
  begin
    select * into v_s from venue.settlement where settlement_id = p_settlement_id for update nowait;
  exception when lock_not_available then
    raise exception 'precondition_failed: settlement_not_locked' using errcode = 'P0001';
  end;
  if v_s.settlement_id is null or v_s.status <> 'open' then
    raise exception 'precondition_failed: settlement_not_locked (not an open settlement in this transaction)' using errcode = 'P0001';
  end if;
  foreach v_id in array coalesce(p_attribution_ids, '{}'::uuid[]) loop
    select * into v_a from venue.attribution where id = v_id;
    if v_a.id is null or v_a.org_id <> v_s.org_id then
      v_held := v_held || jsonb_build_object('attribution_id', v_id, 'reason', 'out_of_scope'); continue;
    end if;
    if exists (select 1 from venue.settlement_line l where l.cause = 'promoter_commission' and l.cause_ref = v_a.id) then
      v_held := v_held || jsonb_build_object('attribution_id', v_id, 'reason', 'already_lined'); continue;   -- conflict_locked class
    end if;
    -- the SAME advisory key review_attribution_flag takes: a release/deny cannot interleave between
    -- this decision read and the line commit (red-team E1 — "the money and the decision freeze together")
    perform pg_advisory_xact_lock(hashtext('attribution.review:' || v_a.id::text));
    -- HOLD: flagged and not released at max(seq)
    if v_a.self_deal_flag then
      select r.decision into v_decision from venue.attribution_review r where r.attribution_id = v_a.id order by r.seq desc limit 1;
      if coalesce(v_decision, 'held') <> 'release' then
        v_held := v_held || jsonb_build_object('attribution_id', v_id, 'reason', case when v_decision = 'deny' then 'denied' else 'unreviewed_flag' end); continue;
      end if;
    end if;
    select * into v_p from venue.promoter where promoter_id = v_a.promoter_id;
    -- terms resolve from the ATTRIBUTION's snapshot (never the promoter's current terms)
    if not ((v_a.commission_kind = 'bps' and v_a.commission_bps_applied is not null)
            or (v_a.commission_kind = 'flat_per_ticket' and v_a.commission_flat_minor_applied is not null)) then
      raise exception 'precondition_failed: terms_unresolvable for attribution %', v_id using errcode = 'P0001';
    end if;
    if v_p.identity_id is null then
      v_held := v_held || jsonb_build_object('attribution_id', v_id, 'reason', 'payee_unresolvable'); continue;   -- E-128
    end if;
    if v_a.currency <> v_s.currency then
      v_held := v_held || jsonb_build_object('attribution_id', v_id, 'reason', 'currency_mismatch'); continue;    -- E-128
    end if;
    -- PAYABLE from live state: surviving (non-voided) atoms per item; a refunded order ⇒ 0
    select * into v_o from venue."order" where order_id = v_a.order_id;
    if v_o.status = 'refunded' then
      v_held := v_held || jsonb_build_object('attribution_id', v_id, 'reason', 'basis_zero'); continue;
    end if;
    select coalesce(sum(oi.unit_price_minor::bigint * surv.n), 0), coalesce(sum(surv.n), 0) into v_basis, v_qty
      from venue.order_item oi
      cross join lateral (select count(*) as n from kernel.ticket_ownership_log l join kernel.tickets t on t.ticket_atom_id = l.ticket_atom_id
                            where l.sequence = 1 and l.cause = 'issue' and l.cause_ref = oi.id and t.state <> 'voided') surv
     where oi.order_id = v_a.order_id;
    v_payable := case when v_a.commission_kind = 'bps' then floor(v_basis * v_a.commission_bps_applied / 10000.0)::bigint
                      else v_a.commission_flat_minor_applied::bigint * v_qty end;
    if v_payable <= 0 then
      v_held := v_held || jsonb_build_object('attribution_id', v_id, 'reason', 'basis_zero'); continue;
    end if;
    if v_payable > 2147483647 then
      v_held := v_held || jsonb_build_object('attribution_id', v_id, 'reason', 'amount_overflow'); continue;   -- never an opaque 22003 out of the close
    end if;
    -- ONE payout per (attribution, payee) — PROMOTER §4.2 (3), byte for byte.
    -- MINTED UNDER A SYSTEM HOLD (E-138 / X-12): the org's debit is a negative settlement line
    -- that 087's close never collects (no primary-revenue line exists in Phase 2, so the net is
    -- negative and no org payout is minted), and no advance path for a promoter_commission payout
    -- is contracted (request_org_payout is cause='settlement' only). Until the owner rules the
    -- funding source (COMMISSION_FUNDING_SOURCE) the liability is recorded but no money can leave:
    -- mark_payout_transfer_state refuses a held payout; kernel.release_payout (platform_risk /
    -- platform_admin, Control-5) is the release path once funded.
    v_key := 'promoter_commission:' || v_a.id::text || ':' || v_p.identity_id::text;
    insert into kernel.payout (payee_kind, payee_identity_id, cause, cause_ref, amount_minor, currency, status, idempotency_key,
                               hold_state, hold_reason_code, held_by, held_at)
    values ('identity', v_p.identity_id, 'promoter_commission', v_a.id, v_payable::integer, v_s.currency, 'pending', v_key,
            'held', 'unfunded_settlement', null, now())
    on conflict (idempotency_key) do nothing
    returning payout_id into v_po;
    if v_po is null then select payout_id into v_po from kernel.payout where idempotency_key = v_key; end if;
    begin   -- BE (OR-14): the hold notice never gates the close (088's dispute-hold precedent)
      perform notify.emit_event('payout_on_hold', 'payout', v_po, 'payout_on_hold:' || v_po::text || ':unfunded_settlement',
        jsonb_build_object('reason', 'unfunded_settlement', 'amount_minor', v_payable, 'settlement_id', p_settlement_id));
    exception when others then null; end;
    v_ids := v_ids || v_po; v_n := v_n + 1;
    v_lines := v_lines || jsonb_build_object('attribution_id', v_a.id, 'amount_minor', v_payable, 'payee_identity_id', v_p.identity_id, 'payout_id', v_po);
    -- G-25 #32 PromoterCommissionAccrued — BE emit, dedup commission:<attribution_id> (NOTIF §5)
    begin
      perform notify.emit_event('promoter_commission_accrued', 'attribution', v_a.id, 'commission:' || v_a.id::text,
        jsonb_build_object('settlement_id', p_settlement_id, 'payout_id', v_po, 'amount_minor', v_payable, 'promoter_id', v_a.promoter_id));
    exception when others then null; end;
  end loop;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values (coalesce(auth.uid(), v_sys), 'settlement.commission', 'settlement', p_settlement_id, coalesce(p_command_key, 'close'),
          jsonb_build_object('lines_written', v_n, 'payout_ids', to_jsonb(v_ids), 'held', v_held));
  return jsonb_build_object('status','ok','lines_written', v_n, 'payout_ids', to_jsonb(v_ids), 'held', v_held, 'lines', v_lines);
end;
$$;

-- SEAM-2 body (087 stub replaced; signature FROZEN). VOLATILE + per-org xact
-- advisory lock (E-104 — the same discipline as the royalty seam).
create or replace function kernel.settlement_commission_lines(p_settlement_id uuid)
returns setof kernel.settlement_line_candidate
language plpgsql volatile security definer set search_path = ''
as $$
declare v_s venue.settlement%rowtype; v_ids uuid[]; v_res jsonb;
begin
  select * into v_s from venue.settlement st where st.settlement_id = p_settlement_id;
  if v_s.settlement_id is null then return; end if;
  perform pg_advisory_xact_lock(hashtext('settlement.seam.org:' || v_s.org_id::text));
  -- the eligible set: this org, this settlement's scope (event, or venue + period),
  -- never lined before (fresh snapshot after the lock — VOLATILE)
  select coalesce(array_agg(a.id order by a.order_paid_at, a.id), '{}') into v_ids
    from venue.attribution a
    join venue."order" o on o.order_id = a.order_id
    join catalog.event_session es on es.session_id = o.event_session_id
    join catalog.event e on e.event_id = a.event_id
   where a.org_id = v_s.org_id
     and ((v_s.event_id is not null and a.event_id = v_s.event_id)
          or (v_s.event_id is null and e.venue_id = v_s.venue_id
              and (v_s.period_start is null or es.starts_at >= v_s.period_start)
              and (v_s.period_end is null or es.starts_at < v_s.period_end)))
     and not exists (select 1 from venue.settlement_line l where l.cause = 'promoter_commission' and l.cause_ref = a.id)
     -- terminal classes are excluded HERE so a permanently-held attribution is not re-walked at every
     -- close under the settlement lock (red-team B5); pay_promoter_commission keeps its own defensive arms
     and o.status not in ('refunded','cancelled')
     and a.currency = v_s.currency
     and exists (select 1 from venue.promoter p where p.promoter_id = a.promoter_id and p.identity_id is not null)
     and coalesce((select r.decision from venue.attribution_review r where r.attribution_id = a.id order by r.seq desc limit 1), 'held') <> 'deny';
  if cardinality(v_ids) = 0 then return; end if;
  v_res := kernel.pay_promoter_commission(p_settlement_id, v_ids, 'seam:' || p_settlement_id::text);
  return query
    select 'promoter_commission'::text, (x ->> 'attribution_id')::uuid, -((x ->> 'amount_minor')::bigint), v_s.currency,
           'identity'::text, (x ->> 'payee_identity_id')::uuid
      from jsonb_array_elements(coalesce(v_res -> 'lines', '[]'::jsonb)) x
     order by 2;
end;
$$;

-- ============================================================================
-- PART 10 — ODR-16 (OR-13): kernel.on_identity_erased_promoter — SEAM-2 body of
--   the 077 stub. INV #35 the promoter row SURVIVES (commission entitlement key);
--   INV #36 promoter_link.status_changed_by CLEANED (SET NULL); INV #37
--   promoter_code.created_by survives; INV #38 attribution_review.decided_by
--   TOMBSTONED (untouched). Accrued commissions: 16c Q6 (pay if payable else
--   hold) — owned by the payout machinery, not this hook.
-- ============================================================================
create or replace function kernel.on_identity_erased_promoter(p_identity uuid)
returns void language sql volatile security definer set search_path = ''
as $$
  update venue.promoter_link l set status_changed_by = null where l.status_changed_by = p_identity;
$$;

-- ============================================================================
-- PART 11 — EXEC POSTURE (RLS §11.5; PFA-1: no PUBLIC/anon anywhere)
-- ============================================================================
do $$ declare f text; begin
  foreach f in array array[
    'venue.create_promoter(uuid,text,jsonb,text)', 'venue.update_promoter(uuid,jsonb,text,text)',
    'venue.create_promoter_link(uuid,uuid,text,text)', 'venue.set_promoter_link_status(uuid,text,text,text)',
    'venue.check_promoter_slug_available(text)',
    'venue.create_promoter_code(uuid,text,uuid[],timestamptz,timestamptz,text,text)',
    'venue.create_promoter_codes_bulk(uuid,integer,text,uuid[],timestamptz,timestamptz,text)',
    'venue.set_promoter_code_status(uuid,text,text)', 'venue.set_promoter_code_scope(uuid,uuid[],uuid[],text)',
    'venue.set_promoter_code_window(uuid,timestamptz,timestamptz,text)',
    'venue.preview_promoter_code(text,uuid)', 'venue.bind_order_attribution(uuid,text,text,text)',
    'venue.review_attribution_flag(uuid,text,text,text,text)',
    'venue.get_my_promoter_summary(uuid,uuid,jsonb)', 'venue.list_my_attributions(uuid,jsonb,jsonb)',
    'venue.list_promoter_attributions(text,uuid,jsonb,jsonb)',
    'kernel.is_promoter_for_event(uuid)',
    'kernel.pay_promoter_commission(uuid,uuid[],text)',
    'venue.guard_promoter_engine_immutable()', 'venue.assert_promoter_engine_consistency()'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
  -- caller-authorized verbs and reads: authenticated only (in-body authz)
  foreach f in array array[
    'venue.create_promoter(uuid,text,jsonb,text)', 'venue.update_promoter(uuid,jsonb,text,text)',
    'venue.create_promoter_link(uuid,uuid,text,text)', 'venue.set_promoter_link_status(uuid,text,text,text)',
    'venue.check_promoter_slug_available(text)',
    'venue.create_promoter_code(uuid,text,uuid[],timestamptz,timestamptz,text,text)',
    'venue.create_promoter_codes_bulk(uuid,integer,text,uuid[],timestamptz,timestamptz,text)',
    'venue.set_promoter_code_status(uuid,text,text)', 'venue.set_promoter_code_scope(uuid,uuid[],uuid[],text)',
    'venue.set_promoter_code_window(uuid,timestamptz,timestamptz,text)',
    'venue.preview_promoter_code(text,uuid)', 'venue.bind_order_attribution(uuid,text,text,text)',
    'venue.review_attribution_flag(uuid,text,text,text,text)',
    'venue.get_my_promoter_summary(uuid,uuid,jsonb)', 'venue.list_my_attributions(uuid,jsonb,jsonb)',
    'venue.list_promoter_attributions(text,uuid,jsonb,jsonb)',
    'kernel.is_promoter_for_event(uuid)'
  ] loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  -- the edge wrapper's unauthenticated path (RLS §11.5/§11.8): service_role on preview ONLY
  grant execute on function venue.preview_promoter_code(text,uuid) to service_role;
  -- kernel.pay_promoter_commission: EXEC: DEF — definer-internal, NO client or
  -- machine grant (087's treatment of the seams; E-129 records the §20.7.2 wording).
end $$;
-- the three replaced hooks keep their frozen ACLs (CREATE OR REPLACE preserves them);
-- resolve_order_attribution stays revoked from anon/authenticated (085 PART 5).

-- ============================================================================
-- PART 12 — ADOPT the two 082 candidate FKs (NOT VALID → VALIDATE; 084/089
--   construction). LAST in the transaction: ADD CONSTRAINT takes ACCESS EXCLUSIVE
--   on venue."order" (the checkout hot table) and NOT VALID skips only the scan,
--   so the lock is held for the shortest tail (red-team G-3).
-- ============================================================================
do $$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'venue."order"'::regclass and conname = 'fk_order_attr_cand_code') then
    alter table venue."order" add constraint fk_order_attr_cand_code
      foreign key (attribution_candidate_code_id) references venue.promoter_code(code_id) on delete restrict not valid;
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'venue."order"'::regclass and conname = 'fk_order_attr_cand_link') then
    alter table venue."order" add constraint fk_order_attr_cand_link
      foreign key (attribution_candidate_link_id) references venue.promoter_link(link_id) on delete restrict not valid;
  end if;
end $$;
alter table venue."order" validate constraint fk_order_attr_cand_code;
alter table venue."order" validate constraint fk_order_attr_cand_link;

commit;

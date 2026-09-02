-- ============================================================================
-- 088_market_native_rail_rollback.sql — REVERSES 088_market_native_rail.sql
-- ----------------------------------------------------------------------------
-- POSTURE (plan §8/088; 087 precedent): CLEAN-WHILE-EMPTY. The two money/custody
-- facts 088 introduces — market.market_sale (the consummation fact, C26) and
-- kernel.dispute_native (the chargeback record, R-40; DELETE is revoked from
-- every role by design, GP-2) — must be FORWARD-FIXED from their first row: a
-- rollback that dropped a consummated sale or a recorded dispute would erase a
-- money fact that Stripe, a ledger row, or a settlement line still references.
-- The guard below refuses in that case; every other 088 row (listings, offers,
-- p2p transfers) is a market intent and is dropped with its table.
--
-- ORDER: 1 guard · 2 cron · 3 the 24 new routines · 4 the SEVEN body-only
-- replacements restored to their EXACT prior bytes (six SEAM-2 stubs + the 079
-- kernel.unlock_ticket body; signatures untouched — SEAM-2a) · 5 tables
-- children-first (policies, grants, triggers, indexes go with them).
-- The resale_state CHECKs on kernel.tickets / venue.door_manifest_entry are NOT
-- touched: 088 only VERIFIED the 079/086 five-label form (E-92).
-- ============================================================================
begin;

-- 1 — CLEAN-WHILE-EMPTY guard
do $$
declare v_sales bigint; v_disputes bigint; v_live bigint; v_pinned bigint; v_facts bigint;
begin
  if to_regclass('market.market_sale') is null and to_regclass('kernel.dispute_native') is null then
    raise notice '088 rollback: already rolled back (no 088 table present) — the remaining statements are no-ops';
    return;
  end if;
  -- ROLLBACK_GUARD_ROW_SECURITY (obligation opened by 091's E-151, CLOSED at the 2026-09-02
  -- release-readiness pass): the guard counts RLS-enabled zero-policy tables; run by a
  -- non-owner, non-BYPASSRLS role it would read 0 rows and FAIL OPEN. Count with row
  -- security off — same house pattern as the 091/092 rollbacks.
  set local row_security = off;
  -- close the count→drop window on the four tables this rollback drops (090/091/092 house
  -- pattern; the maintenance-window precondition in the runbook covers kernel.tickets /
  -- ticket_ownership_log, which are counted here but owned by 079 and not dropped).
  lock table market.market_sale, kernel.dispute_native, market.listing_native, market.p2p_transfer in access exclusive mode;
  select count(*) into v_sales from market.market_sale;
  select count(*) into v_disputes from kernel.dispute_native;
  -- a LIVE overlay (an active/reserved listing, an open transfer) pins kernel.tickets.resale_state
  -- to listed/locked; dropping its table with every release caller would strand the atom forever.
  select (select count(*) from market.listing_native where status in ('active','reserved'))
       + (select count(*) from market.p2p_transfer where status in ('initiated','accepted')) into v_live;
  -- a PINNED overlay with no live row (a stranded atom) is just as stuck without the 088 release verbs
  select count(*) into v_pinned from kernel.tickets where resale_state in ('listed','locked');
  -- immutable custody facts that name 088 rows (a native sale / transfer already moved custody)
  select count(*) into v_facts from kernel.ticket_ownership_log where cause in ('market_sale','auction_sale','p2p_transfer');
  if v_sales > 0 or v_disputes > 0 or v_live > 0 or v_pinned > 0 or v_facts > 0 then
    raise exception 'rollback_refused: 088 is not clean — % market_sale row(s), % dispute_native row(s), % live listing/transfer overlay(s), % pinned atom overlay(s), % ledger custody fact(s) naming 088 rows; forward-fix instead (CLEAN-WHILE-EMPTY)', v_sales, v_disputes, v_live, v_pinned, v_facts;
  end if;
end $$;

-- 2 — cron (guarded: a partially-applied 088 may carry neither row)
select cron.unschedule(jobname) from cron.job where jobname in ('market-sweep-expired-p2p-transfers','market-sweep-paid-pending-sales');

-- 3 — the 24 routines 088 CREATED (never the hooks — they are RESTORED in 4)
drop function if exists market.create_listing(uuid,integer,text,text);
drop function if exists market.cancel_listing(uuid,text,text);
drop function if exists market.create_auction(uuid,integer,integer,integer,timestamptz,text);
drop function if exists market.place_bid(uuid,integer,text);
drop function if exists market.make_offer(uuid,integer,timestamptz,text);
drop function if exists market.respond_offer(uuid,text,uuid,text);
drop function if exists market.mark_sale_paid_state(uuid,uuid,text);
drop function if exists market.checkout_buy_now(uuid,text);
drop function if exists market.bind_checkout_payment_ref(uuid,text,text);
drop function if exists market.finalize_market_sale(uuid,text);
drop function if exists market.cancel_buy_now_sale(uuid,text,text);
drop function if exists market.list_lapsed_checkouts(integer);
drop function if exists market.create_p2p_transfer(uuid,text,integer,text);
drop function if exists market.accept_p2p_transfer(uuid,text,text);
drop function if exists market.cancel_p2p_transfer(uuid,text,text);
drop function if exists market.sweep_expired_p2p_transfers();
drop function if exists market.sweep_paid_pending_sales();
drop function if exists market.get_ticket_history(uuid);
drop function if exists market.get_market_sale_status(uuid);
drop function if exists kernel.transfer_ticket_ownership(uuid,uuid,text,uuid,uuid,text);
drop function if exists kernel.record_dispute_native(text,text,text,integer,text,text,text,timestamptz,text);
drop function if exists kernel.mark_dispute_state(text,text,text);
drop function if exists kernel.resolve_dispute_native(uuid,text,text,text);
drop function if exists catalog.cancel_event(uuid,text,text);

-- 4 — the seven body-only replacements restored to their PRIOR BYTES
-- 4a — 087 stub (kernel.settlement_royalty_lines) — verbatim from 087
create or replace function kernel.settlement_royalty_lines(p_settlement_id uuid)
returns setof kernel.settlement_line_candidate
language sql stable security definer set search_path = ''
as $$ select * from (values (null::text, null::uuid, null::bigint, null::text, null::text, null::uuid)) v
      where false $$;   -- zero rows; real body 088 (market_sale royalty)

-- 4b — 085 stub (market.on_atom_voided) — verbatim from 085
create or replace function market.on_atom_voided(p_atom_id uuid, p_refund_id uuid, p_cause text)
returns void language sql volatile security definer set search_path = ''
as $$ select $$;   -- no-op until 088

-- 4c/4d — 086 stubs (the two door hooks) — verbatim from 086
create or replace function market.on_door_freeze_engaged(p_event_session_id uuid, p_cause_ref uuid)
returns table(drained_transfers integer, drained_listings integer, atoms_unlocked integer)
language sql security definer set search_path = ''
as $$ select 0, 0, 0 $$;   -- no-op until 088 (V1)

create or replace function market.door_freeze_drain_preview(p_event_session_id uuid)
returns table(pending_transfers integer, active_listings integer, excluded_paid_pending integer, atoms_to_unlock integer)
language sql security definer set search_path = ''
as $$ select 0, 0, 0, 0 $$;   -- no-op until 088 (V7)

-- 4e/4f — 077 stubs (the two deletion hooks) — verbatim from 077
create or replace function kernel.deletion_blockers_market(p_identity uuid)
returns text language sql volatile security definer set search_path = ''
as $$ select null::text $$;   -- BP-3 + BP-4 + BP-7/BP-8 native twins; 088

create or replace function kernel.on_identity_erased_market(p_identity uuid)
returns void language sql volatile security definer set search_path = ''
as $$ select $$;              -- 16d hard-delete allowance ONLY; real body 088

-- 4g — 079 body (kernel.unlock_ticket) — verbatim from 079
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

-- 5 — tables, children first (policies / column grants / triggers / indexes ride along)
drop table if exists market.p2p_transfer;
drop table if exists market.market_sale;
drop table if exists market.offer;
drop table if exists market.auction;
drop table if exists market.listing_native;
drop table if exists kernel.dispute_native;

commit;

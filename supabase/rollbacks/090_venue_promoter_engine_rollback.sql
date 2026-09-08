-- ============================================================================
-- 090_venue_promoter_engine_rollback.sql — REVERSES 090_venue_promoter_engine.sql
-- ----------------------------------------------------------------------------
-- POSTURE (plan §8/090): CLEAN-WHILE-EMPTY, then forward-fix for venue.attribution.
-- An attribution is an append-only commission ledger (CDM §1.3) and a
-- promoter_commission settlement line / payout names it; dropping a table that a
-- settlement line or a payout references by cause_ref would orphan money facts.
-- The guard refuses when ANY attribution row, ANY promoter_commission line, or
-- ANY promoter_commission payout exists. Empty promoter/link/code/scope/review
-- rows are configuration and are dropped with their tables.
--
-- ORDER: 1 guard (the three money/ledger tables are LOCKED ACCESS EXCLUSIVE
-- before the counts — a concurrent finalize/close cannot slip a row between the
-- count and the drop; red-team G-2) · 2 the three SEAM-2 hooks restored to their
-- EXACT prior bytes (085 resolver stub · 087 commission stub · 077 promoter stub;
-- signatures untouched — SEAM-2a) · 3 the 090-created routines · 4 the two
-- ADOPTED venue.order FKs (the columns belong to 082 and stay) and the CANDIDATE
-- VALUES they pointed at are CLEARED under the 082 freeze guard (a pointer into
-- a dropped table has no meaning; without this the next apply's VALIDATE fails
-- 23503 — red-team G-1) · 5 the money index · 6 tables children-first · 7 the
-- normalizer.
-- ORDERING WITH LATER PACKAGES: none yet (090 is the chain tip).
-- ============================================================================
begin;

-- 1 — CLEAN-WHILE-EMPTY guard
do $$
declare v_attr bigint; v_lines bigint; v_payouts bigint;
begin
  if to_regclass('venue.attribution') is null or to_regclass('venue.promoter') is null then
    raise notice '090 rollback: already rolled back (no 090 table present) — the remaining statements are no-ops';
    return;
  end if;
  -- ROLLBACK_GUARD_ROW_SECURITY (obligation opened by 091's E-151, CLOSED at the 2026-09-02
  -- release-readiness pass): the guard counts RLS-enabled zero-policy tables; run by a
  -- non-owner, non-BYPASSRLS role it would read 0 rows and FAIL OPEN. Count with row
  -- security off — same house pattern as the 091/092 rollbacks.
  set local row_security = off;
  -- close the count→drop window: no concurrent finalize (attribution) or close (line/payout) can land
  -- venue."order" FIRST (step 4 clears its candidates): a concurrent finalize holds order → waits on
  -- attribution; locking attribution before order would form the cycle (re-review NEW-3)
  lock table venue."order", venue.attribution, venue.settlement_line, kernel.payout in access exclusive mode;
  select count(*) into v_attr from venue.attribution;
  select count(*) into v_lines from venue.settlement_line where cause = 'promoter_commission';
  select count(*) into v_payouts from kernel.payout where cause = 'promoter_commission';
  if v_attr > 0 or v_lines > 0 or v_payouts > 0 then
    raise exception 'rollback_refused: 090 is not clean — % attribution row(s), % promoter_commission line(s), % promoter_commission payout(s); forward-fix instead (CLEAN-WHILE-EMPTY)', v_attr, v_lines, v_payouts;
  end if;
end $$;

-- 2 — the three SEAM-2 hooks restored to their PRIOR BYTES
-- 2a — 085 stub (venue.resolve_order_attribution) — verbatim from 085
create or replace function venue.resolve_order_attribution(p_order_id uuid)
returns void language sql volatile security definer set search_path = ''
as $$ select $$;   -- no-op; writes NO venue.attribution row (T-SCHEMA-ISSUE-03)

-- 2b — 087 stub (kernel.settlement_commission_lines) — verbatim from 087
create or replace function kernel.settlement_commission_lines(p_settlement_id uuid)
returns setof kernel.settlement_line_candidate
language sql stable security definer set search_path = ''
as $$ select * from (values (null::text, null::uuid, null::bigint, null::text, null::text, null::uuid)) v
      where false $$;   -- zero rows; real body 090 (venue.attribution commission)

-- 2c — 077 stub (kernel.on_identity_erased_promoter) — verbatim from 077
create or replace function kernel.on_identity_erased_promoter(p_identity uuid)
returns void language sql volatile security definer set search_path = ''
as $$ select $$;              -- INV #36; venue.promoter row SURVIVES; 090

-- 3 — the routines 090 CREATED (never the hooks — they are RESTORED in 2)
drop function if exists kernel.pay_promoter_commission(uuid,uuid[],text);
drop function if exists kernel.is_promoter_for_event(uuid);
drop function if exists venue.list_promoter_attributions(text,uuid,jsonb,jsonb);
drop function if exists venue.list_my_attributions(uuid,jsonb,jsonb);
drop function if exists venue.get_my_promoter_summary(uuid,uuid,jsonb);
drop function if exists venue.review_attribution_flag(uuid,text,text,text,text);
drop function if exists venue.bind_order_attribution(uuid,text,text,text);
drop function if exists venue.preview_promoter_code(text,uuid);
drop function if exists venue.set_promoter_code_window(uuid,timestamptz,timestamptz,text);
drop function if exists venue.set_promoter_code_scope(uuid,uuid[],uuid[],text);
drop function if exists venue.set_promoter_code_status(uuid,text,text);
drop function if exists venue.create_promoter_codes_bulk(uuid,integer,text,uuid[],timestamptz,timestamptz,text);
drop function if exists venue.create_promoter_code(uuid,text,uuid[],timestamptz,timestamptz,text,text);
drop function if exists venue.check_promoter_slug_available(text);
drop function if exists venue.set_promoter_link_status(uuid,text,text,text);
drop function if exists venue.create_promoter_link(uuid,uuid,text,text);
drop function if exists venue.update_promoter(uuid,jsonb,text,text);
drop function if exists venue.create_promoter(uuid,text,jsonb,text);

-- 4 — the two ADOPTED FKs (082's columns stay — R2B/C112) and the candidate VALUES:
--   a candidate is a pre-freeze pointer into promoter_code/promoter_link; once those
--   tables are gone it points at nothing, and 082's freeze guard would refuse to clear
--   it on any non-pending order — so the guard is set aside for exactly this statement.
alter table venue."order" drop constraint if exists fk_order_attr_cand_code;
alter table venue."order" drop constraint if exists fk_order_attr_cand_link;
do $$ begin
  if to_regclass('venue."order"') is not null then
    alter table venue."order" disable trigger tg_order_candidate_freeze;
    update venue."order" set attribution_candidate_code_id = null, attribution_candidate_link_id = null
     where attribution_candidate_code_id is not null or attribution_candidate_link_id is not null;
    alter table venue."order" enable trigger tg_order_candidate_freeze;
  end if;
end $$;

-- 5 — the money constraint
drop index if exists venue.attribution_one_commission_line_ever;

-- 6 — tables, children first (policies / grants / triggers / indexes ride along)
drop table if exists venue.attribution_review;
drop table if exists venue.attribution;
drop table if exists venue.promoter_code_scope;
drop table if exists venue.promoter_code;
drop table if exists venue.promoter_link;
drop table if exists venue.promoter;

-- 7 — the two trigger functions and the normalizer (last: the generated column depended on it)
drop function if exists venue.assert_promoter_engine_consistency();
drop function if exists venue.guard_promoter_engine_immutable();
drop function if exists venue.normalize_promoter_code(text);

commit;

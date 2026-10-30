-- ============================================================================
-- ROLLBACK for 085_kernel_money_native.sql
-- POSTURE: FORWARD-FIX ONLY FROM FIRST ROW — the strictest in the chain
-- (plan §8/085). These are MONEY LEDGERS: a clean drop is admissible ONLY while
-- every one of the four tables is EMPTY. One row anywhere ⇒ REFUSE; live money
-- facts are forward-fix territory, always.
--
-- ORDERING (reverse-order rollout guarantees it; stated because these objects
-- span packages): 090's rollback restores the resolve_order_attribution stub
-- body FIRST; 088's restores on_atom_voided; 087's restores on_payout_settled.
-- At 085 all three ARE the stubs, so this script stands alone on a chain head.
--
-- Restores post-084 state EXACTLY: the three 077 deletion/obligation stubs come
-- back VERBATIM (F-5); the PFA-15/PFA-21 schema USAGE grants are revoked; the
-- cron entry and the PFA-22 seed row are removed; 076-084 untouched.
-- ============================================================================

begin;

-- PART 0 — refusal guard (row_security off: the deny-all zero-policy tables
-- would count 0 for a non-BYPASSRLS runner and false-negative).
do $$
declare
  v_pn bigint := 0; v_r bigint := 0; v_p bigint := 0; v_o bigint := 0;
begin
  set local row_security = off;
  if to_regclass('kernel.payment_native')     is not null then execute 'select count(*) from kernel.payment_native'     into v_pn; end if;
  if to_regclass('kernel.refund')             is not null then execute 'select count(*) from kernel.refund'             into v_r;  end if;
  if to_regclass('kernel.payout')             is not null then execute 'select count(*) from kernel.payout'             into v_p;  end if;
  if to_regclass('kernel.identity_obligation') is not null then execute 'select count(*) from kernel.identity_obligation' into v_o; end if;
  if v_pn > 0 or v_r > 0 or v_p > 0 or v_o > 0 then
    raise exception 'REFUSED: 085 holds MONEY rows (payment_native=%, refund=%, payout=%, identity_obligation=%). FORWARD-FIX ONLY (plan §8/085) — money ledgers are never clean-deletable once written.',
      v_pn, v_r, v_p, v_o;
  end if;
  -- R4 P1: money INTENT can exist with all four ledgers empty — a parked refund
  -- request (077 table) + its refund_hold overlays on 079 tickets. Dropping the
  -- verbs + the real Q5 body would strand them (P0-1 "bricked ticket"). Refuse.
  if exists (select 1 from kernel.approval_request
              where action='refund.issue' and state='pending')
     or exists (select 1 from kernel.tickets where resale_state='refund_hold') then
    raise exception 'REFUSED: 085 has parked refund intent (a pending refund.issue request or a refund_hold overlay). Sweep/decide it first — FORWARD-FIX ONLY.';
  end if;
  -- R4 P1: the owner may have set a later version of the PFA-22 key; deleting only
  -- v1 would orphan v2. Refuse rather than corrupt the version chain.
  if exists (select 1 from catalog.platform_config
              where key='deletion.refund_possible_window_hours' and version > 1) then
    raise exception 'REFUSED: deletion.refund_possible_window_hours has an owner-set version > 1. FORWARD-FIX ONLY.';
  end if;
end $$;

-- PART 1 — the cron entry.
select cron.unschedule('sweep-expired-refund-requests')
 where exists (select 1 from cron.job where jobname = 'sweep-expired-refund-requests');

-- PART 2 — restore the three 077 stub bodies VERBATIM (F-5).
create or replace function kernel.deletion_blockers_money(p_identity uuid)
returns text language sql volatile security definer set search_path = ''
as $$ select null::text $$;   -- BP-5 + BP-6 kernel arm + BP-12 refund/window arm; 085

create or replace function kernel.has_outstanding_obligations(p_identity_id uuid)
returns boolean language sql volatile security definer set search_path = ''
as $$ select false $$;        -- BP-10 (OR-21); true-not-inert; real body 085

create or replace function kernel.on_deletion_q5_release(p_identity uuid)
returns void language sql volatile security definer set search_path = ''
as $$ select $$;              -- Q5 release side-effects (§17.4); real body 085

-- PART 3 — the 085-authored functions (exact signatures).
drop function if exists venue.finalize_primary_order(uuid, uuid, text, text);
drop function if exists venue.resolve_order_attribution(uuid);
drop function if exists venue.on_payout_settled(uuid);
drop function if exists market.on_atom_voided(uuid, uuid, text);
drop function if exists kernel.void_ticket_atom(uuid, uuid, text);
drop function if exists kernel.refund_primary_order(uuid, integer, text, text);
drop function if exists kernel.admin_refund(uuid, uuid[], integer, text, text);
drop function if exists kernel.force_void_ticket(uuid, text, text);
drop function if exists kernel.hold_payout(uuid, text, text);
drop function if exists kernel.release_payout(uuid, text);
drop function if exists kernel.request_order_refund(uuid, uuid[], integer, text, text);
drop function if exists kernel.approve_refund_request(uuid, text, text, text);
drop function if exists kernel.cancel_refund_request(uuid, text, text);
drop function if exists kernel.sweep_expired_refund_requests();
drop function if exists kernel.list_org_payouts(uuid, uuid, jsonb, text);
drop function if exists kernel.list_org_refunds(uuid, uuid, jsonb, text);
drop function if exists kernel.list_approval_requests(uuid, jsonb, text);
drop function if exists kernel.record_money_denial(text, text, uuid, text);
drop function if exists kernel.set_org_payout_destination(uuid, text, text, text);
drop function if exists kernel.mark_payout_transfer_state(uuid, text, text, text, text);
drop function if exists kernel.mark_refund_state(uuid, text, text, text, text);
drop function if exists kernel.record_identity_obligation(uuid, text, uuid, text, integer, text, text);
drop function if exists kernel.resolve_identity_obligation(uuid, text, text, text);

-- PART 4 — the four money tables (guard proved them empty; children-first is
-- moot — no FK links them to each other).
drop table if exists kernel.identity_obligation;
drop table if exists kernel.payout;
drop table if exists kernel.refund;
drop table if exists kernel.payment_native;

-- PART 5 — the owner-ruled schema grants (PFA-15 / PFA-21) and the PFA-22 seed.
revoke usage on schema venue  from service_role;
revoke usage on schema kernel from service_role;
-- catalog.platform_config is APPEND-ONLY (078 tg_platform_config_append_only on
-- UPDATE OR DELETE). The guard above proved no owner-set v2 exists, so removing
-- the lone v1 PFA-22 seed is safe — but the AO trigger must be lifted for the
-- delete (R4 P0). Same txn; re-enabled immediately.
alter table catalog.platform_config disable trigger tg_platform_config_append_only;
delete from catalog.platform_config
 where key = 'deletion.refund_possible_window_hours' and version = 1;
alter table catalog.platform_config enable trigger tg_platform_config_append_only;

commit;

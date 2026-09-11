-- ============================================================================
-- 122_transfers_profiles_fk_parity.sql — restore transfers↔profiles FK parity.
--
-- THE DRIFT. Production carries
--   transfers_buyer_id_fkey  FOREIGN KEY (buyer_id)  REFERENCES public.profiles(id)
--   transfers_seller_id_fkey FOREIGN KEY (seller_id) REFERENCES public.profiles(id)
-- while a fresh replay of this repo's chain builds both against auth.users(id).
-- Read from production 2026-09-10 (read-only): both NO ACTION on update and
-- delete, MATCH SIMPLE, VALIDATED, NOT DEFERRABLE. Constraint NAMES are already
-- identical in both worlds; only confrelid differs.
--
-- WHY IT MATTERS. PostgREST resolves an embedded resource through a foreign
-- key. `transfers?select=...,seller:profiles!seller_id(display_name)` — the
-- query app/transfer/receive/[id].tsx issues, and its mirror in
-- app/transfer/send/[id].tsx — therefore works in production and returns
-- HTTP 400 PGRST200 ("Could not find a relationship between 'transfers' and
-- 'profiles'") in every environment built from the chain: the sandbox, CI's
-- fresh DB, the local rehearsal. The buyer sees "Transfer not found" for a
-- transfer that exists. The app code is correct; the chain is not.
--
-- CONDITIONAL BY DESIGN. Each constraint is rewritten ONLY when its current
-- target is not public.profiles. Against a production-equivalent schema this
-- migration takes no lock, drops nothing and changes no catalog row — a true
-- no-op rather than a drop-and-identical-recreate.
--
-- FAILS CLOSED ON ORPHANS. If any transfers row references a buyer or seller
-- with no profiles row, the migration raises instead of dropping a live
-- constraint and leaving the table unprotected. Checked 2026-09-10: production
-- 36 transfers / 0 orphans, sandbox 31 / 0, and auth.users with no profile = 0
-- in both.
--
-- NOT CHANGED: no column, no data, no grant, no RLS policy, no trigger, no
-- other constraint (transfers_dispute_resolved_by_fkey stays on auth.users,
-- matching production). Census: 0 objects added or removed.
--
-- KNOWN SIBLING, DELIBERATELY OUT OF SCOPE: bids_bidder_id_fkey drifts the same
-- way (production → profiles, chain → auth.users). No code embeds profiles off
-- bids today, so it is latent; it is reported rather than fixed here because
-- this change was scoped to transfers.
--
-- Rollback: supabase/rollbacks/122_transfers_profiles_fk_parity_rollback.sql
-- Verification: supabase/tests/190_transfers_profiles_fk_parity.sql
-- ============================================================================
begin;

do $$
declare
  v_orphan_buyer  bigint;
  v_orphan_seller bigint;
begin
  if to_regclass('public.transfers') is null or to_regclass('public.profiles') is null then
    raise exception '122: public.transfers or public.profiles is absent — refusing';
  end if;

  select count(*) into v_orphan_buyer
    from public.transfers t
   where t.buyer_id is not null
     and not exists (select 1 from public.profiles p where p.id = t.buyer_id);
  select count(*) into v_orphan_seller
    from public.transfers t
   where t.seller_id is not null
     and not exists (select 1 from public.profiles p where p.id = t.seller_id);

  if v_orphan_buyer > 0 or v_orphan_seller > 0 then
    raise exception '122 REFUSED — orphaned references: buyer=%, seller=%. Reconcile the rows first; this migration will not drop a live constraint and leave the table unprotected.',
      v_orphan_buyer, v_orphan_seller;
  end if;

  -- buyer_id
  if exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.transfers'::regclass
       and c.conname  = 'transfers_buyer_id_fkey'
       and c.confrelid is distinct from 'public.profiles'::regclass)
  then
    alter table public.transfers drop constraint transfers_buyer_id_fkey;
    alter table public.transfers
      add constraint transfers_buyer_id_fkey
      foreign key (buyer_id) references public.profiles(id)
      match simple on update no action on delete no action;
    raise notice '122: transfers_buyer_id_fkey retargeted to public.profiles(id)';
  else
    raise notice '122: transfers_buyer_id_fkey already targets public.profiles(id) — no change';
  end if;

  -- seller_id
  if exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.transfers'::regclass
       and c.conname  = 'transfers_seller_id_fkey'
       and c.confrelid is distinct from 'public.profiles'::regclass)
  then
    alter table public.transfers drop constraint transfers_seller_id_fkey;
    alter table public.transfers
      add constraint transfers_seller_id_fkey
      foreign key (seller_id) references public.profiles(id)
      match simple on update no action on delete no action;
    raise notice '122: transfers_seller_id_fkey retargeted to public.profiles(id)';
  else
    raise notice '122: transfers_seller_id_fkey already targets public.profiles(id) — no change';
  end if;
end $$;

commit;

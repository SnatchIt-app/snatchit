-- ============================================================================
-- ROLLBACK for 123_transfers_profiles_fk_parity.sql.
--
-- Returns both constraints to auth.users(id) — the CHAIN's pre-123 shape, which
-- is NOT production's shape. Running this against production would CREATE the
-- drift 123 exists to remove; it is here for an environment built from the
-- chain (sandbox, CI, local rehearsal) where 123 was applied and must be undone.
--
-- Conditional and orphan-guarded in the same way, so it is a no-op wherever the
-- constraints already point at auth.users.
-- ============================================================================
begin;

do $$
declare v_orphan bigint;
begin
  select count(*) into v_orphan
    from public.transfers t
   where (t.buyer_id  is not null and not exists (select 1 from auth.users u where u.id = t.buyer_id))
      or (t.seller_id is not null and not exists (select 1 from auth.users u where u.id = t.seller_id));
  if v_orphan > 0 then
    raise exception '123 rollback REFUSED — % transfers row(s) reference a buyer or seller with no auth.users row', v_orphan;
  end if;

  if exists (select 1 from pg_constraint c where c.conrelid='public.transfers'::regclass
               and c.conname='transfers_buyer_id_fkey' and c.confrelid is distinct from 'auth.users'::regclass) then
    alter table public.transfers drop constraint transfers_buyer_id_fkey;
    alter table public.transfers add constraint transfers_buyer_id_fkey
      foreign key (buyer_id) references auth.users(id) match simple on update no action on delete no action;
  end if;

  if exists (select 1 from pg_constraint c where c.conrelid='public.transfers'::regclass
               and c.conname='transfers_seller_id_fkey' and c.confrelid is distinct from 'auth.users'::regclass) then
    alter table public.transfers drop constraint transfers_seller_id_fkey;
    alter table public.transfers add constraint transfers_seller_id_fkey
      foreign key (seller_id) references auth.users(id) match simple on update no action on delete no action;
  end if;
end $$;

commit;

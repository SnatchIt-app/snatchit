-- Rollback for 124: return bids_bidder_id_fkey to the chain's pre-124 target.
-- Restores auth.users(id) with NO referential action, i.e. 000_baseline_schema.sql:144.
-- NOTE: running this against production would CREATE the drift 124 removes.
do $rb$
begin
  if exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.bids'::regclass
       and c.conname  = 'bids_bidder_id_fkey'
       and c.confrelid = 'public.profiles'::regclass
  ) then
    alter table public.bids drop constraint bids_bidder_id_fkey;
    alter table public.bids add constraint bids_bidder_id_fkey
      foreign key (bidder_id) references auth.users(id)
      match simple on update no action on delete no action;
    raise notice '124 rollback: bids_bidder_id_fkey returned to auth.users(id)';
  else
    raise notice '124 rollback: not pointing at profiles — no change';
  end if;
end
$rb$;

-- ============================================================================
-- 124_bids_profiles_fk_parity.sql — restore bids↔profiles FK parity.
--
-- THE DRIFT. Production carries
--   bids_bidder_id_fkey FOREIGN KEY (bidder_id) REFERENCES public.profiles(id) ON DELETE CASCADE
-- while a fresh replay of this chain builds it against auth.users(id) with no
-- referential action (000_baseline_schema.sql:144). Read read-only 2026-09-12:
-- production 98 bids / 0 orphans against profiles; sandbox 0 bids / 0 orphans.
-- Constraint NAME matches in both worlds; confrelid AND confdeltype differ.
--
-- NOTE THE CASCADE. Unlike 123's transfers constraints (NO ACTION), production's
-- bids constraint is ON DELETE CASCADE. This migration reproduces production
-- exactly, cascade included — parity, not an improvement.
--
-- WHY IT MATTERS. PostgREST resolves an embedded resource through a foreign key.
-- src/hooks/useListingRealtime.ts:64 issues
--   bids?select=*,profiles(display_name,avatar_url)
-- on every listing screen, so bid history loads in production and returns
-- HTTP 400 PGRST200 in every environment built from this chain. Observed in the
-- sandbox on 2026-09-11 at 02:50:35.025 and on each later listing load.
--
-- CORRECTION TO 123's HEADER. 123 recorded this sibling as latent, "no code
-- embeds profiles off bids today". That was wrong: the listing screen has always
-- embedded it. The drift is live, not latent — sandbox-only in effect, because
-- production's constraint is already correct.
--
-- CONDITIONAL BY DESIGN. Rewritten ONLY when the current target is not
-- public.profiles. Against a production-equivalent schema this takes no lock,
-- drops nothing and changes no catalog row — a true no-op. Production therefore
-- needs no apply; this exists so a fresh replay reproduces production.
--
-- FAILS CLOSED ON ORPHANS. If any bids row references a bidder with no profiles
-- row, it raises instead of dropping a live constraint and leaving the table
-- unprotected.
--
-- NOT CHANGED: no column, no data, no grant, no RLS policy, no trigger, no other
-- constraint (bids_listing_id_fkey stays on listings). Census: 0 objects added
-- or removed.
-- ============================================================================

do $mig$
declare
  v_orphans bigint;
begin
  if exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.bids'::regclass
       and c.conname  = 'bids_bidder_id_fkey'
       and (c.confrelid is distinct from 'public.profiles'::regclass
            or c.confdeltype is distinct from 'c')
  ) then
    select count(*) into v_orphans
      from public.bids b
     where b.bidder_id is not null
       and not exists (select 1 from public.profiles p where p.id = b.bidder_id);

    if v_orphans > 0 then
      raise exception '124 REFUSED — % bids row(s) reference a bidder with no profiles row. '
                      'Reconcile those rows first; this migration will not drop a live constraint '
                      'and leave bids unprotected.', v_orphans;
    end if;

    alter table public.bids drop constraint bids_bidder_id_fkey;
    alter table public.bids add constraint bids_bidder_id_fkey
      foreign key (bidder_id) references public.profiles(id)
      match simple on update no action on delete cascade;

    raise notice '124: bids_bidder_id_fkey retargeted to public.profiles(id) ON DELETE CASCADE';
  else
    raise notice '124: bids_bidder_id_fkey already matches production (profiles(id) ON DELETE CASCADE) — no change';
  end if;
end
$mig$;

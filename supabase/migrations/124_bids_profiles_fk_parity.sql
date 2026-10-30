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
--
-- THREE STATES, not two (fixed after the 2026-09-12 rehearsal caught it):
--   correct  → no-op;
--   wrong    → orphan check, drop, recreate;
--   ABSENT   → orphan check, create.
-- The first draft used `if exists (… and target is distinct from profiles …)`,
-- which silently did nothing when the constraint was missing and then printed
-- "already matches production". 123 carries the same shape; its absent-case
-- never arose, and it is recorded rather than edited because it is applied.
-- ============================================================================

do $mig$
declare
  v_orphans  bigint;
  v_present  boolean;
  v_matches  boolean;
begin
  select true,
         (c.confrelid = 'public.profiles'::regclass and c.confdeltype = 'c')
    into v_present, v_matches
    from pg_constraint c
   where c.conrelid = 'public.bids'::regclass
     and c.conname  = 'bids_bidder_id_fkey';

  v_present := coalesce(v_present, false);
  v_matches := coalesce(v_matches, false);

  if v_present and v_matches then
    raise notice '124: bids_bidder_id_fkey already matches production (profiles(id) ON DELETE CASCADE) — no change';
    return;
  end if;

  -- Orphans are checked before any DDL, whether the constraint is being
  -- retargeted or created from absent. Failing closed beats leaving bids
  -- unprotected or creating a constraint that cannot validate.
  select count(*) into v_orphans
    from public.bids b
   where b.bidder_id is not null
     and not exists (select 1 from public.profiles p where p.id = b.bidder_id);

  if v_orphans > 0 then
    raise exception '124 REFUSED — % bids row(s) reference a bidder with no profiles row. '
                    'Reconcile those rows first; this migration will not drop or create a '
                    'constraint that leaves bids unprotected or fails validation.', v_orphans;
  end if;

  if v_present then
    alter table public.bids drop constraint bids_bidder_id_fkey;
  else
    -- ABSENT is a real state: an earlier rollback, or a partial repair, can
    -- leave bidder_id unconstrained. Recreating it is the parity fix, and the
    -- pre-fix version of this migration silently skipped it.
    raise notice '124: bids_bidder_id_fkey was ABSENT — creating it';
  end if;

  alter table public.bids add constraint bids_bidder_id_fkey
    foreign key (bidder_id) references public.profiles(id)
    match simple on update no action on delete cascade;

  raise notice '124: bids_bidder_id_fkey now references public.profiles(id) ON DELETE CASCADE';
end
$mig$;

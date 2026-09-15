-- 192_bids_profiles_fk_parity.sql — asserts bids↔profiles parity with production.
-- Read-only: BEGIN … ROLLBACK, no writes, no DDL.
begin;
select plan(11);

-- C1 the constraint exists under the production name
select has_fk('public', 'bids', 'bids has a foreign key');
select is(
  (select count(*)::int from pg_constraint
    where conrelid = 'public.bids'::regclass and conname = 'bids_bidder_id_fkey'),
  1, 'C1: bids_bidder_id_fkey exists');

-- C2 target is public.profiles (the production target)
select is(
  (select confrelid::regclass::text from pg_constraint
    where conrelid = 'public.bids'::regclass and conname = 'bids_bidder_id_fkey'),
  'profiles', 'C2: bidder_id references public.profiles');

-- C3 exact production semantics: ON DELETE CASCADE, NO ACTION on update,
--    MATCH SIMPLE, validated, not deferrable
select is((select confdeltype from pg_constraint
            where conrelid='public.bids'::regclass and conname='bids_bidder_id_fkey'),
          'c'::"char", 'C3a: ON DELETE CASCADE, as in production');
select is((select confupdtype from pg_constraint
            where conrelid='public.bids'::regclass and conname='bids_bidder_id_fkey'),
          'a'::"char", 'C3b: ON UPDATE NO ACTION');
select is((select confmatchtype from pg_constraint
            where conrelid='public.bids'::regclass and conname='bids_bidder_id_fkey'),
          's'::"char", 'C3c: MATCH SIMPLE');
select ok((select convalidated and not condeferrable from pg_constraint
            where conrelid='public.bids'::regclass and conname='bids_bidder_id_fkey'),
          'C3d: validated and not deferrable');

-- C4 the full definition matches production's verbatim string
select is(
  (select pg_get_constraintdef(oid) from pg_constraint
    where conrelid='public.bids'::regclass and conname='bids_bidder_id_fkey'),
  'FOREIGN KEY (bidder_id) REFERENCES profiles(id) ON DELETE CASCADE',
  'C4: definition is byte-identical to production''s');

-- C5 no orphans — the invariant the migration refuses to break
select is(
  (select count(*)::int from public.bids b
    where b.bidder_id is not null
      and not exists (select 1 from public.profiles p where p.id = b.bidder_id)),
  0, 'C5: no bids row references a missing profile');

-- C6 nothing else on bids moved: the sibling FK and the RLS policy count
select is(
  (select confrelid::regclass::text from pg_constraint
    where conrelid='public.bids'::regclass and conname='bids_listing_id_fkey'),
  'listings', 'C6a: bids_listing_id_fkey still references listings');
select is(
  (select count(*)::int from pg_policies where schemaname='public' and tablename='bids'),
  3, 'C6b: bids still carries its three RLS policies');

select * from finish();
rollback;

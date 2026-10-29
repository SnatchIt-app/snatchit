-- state_anon.sql — the second read-only request of `pkg.py state`: what a client role SEES, under RLS.
-- anon_*     : SET LOCAL ROLE anon with claims {"role":"anon"} — the publishable key, i.e. every logged-out
--              surface and every installed build.
-- nonparty_* : SET LOCAL ROLE authenticated with a fixed sub that is no user (so a party to nothing) —
--              any signed-in stranger.
-- One implicit, read-only transaction; the role switches die with it. The first SELECT stashes the anon
-- counts in transaction-local settings; its own output row has no '=' and pkg.py ignores it.
SET TRANSACTION READ ONLY;
SET LOCAL TimeZone = 'UTC';
SET LOCAL "request.jwt.claims" = '{"role":"anon"}';
SET LOCAL ROLE anon;
SELECT set_config('pkg.anon_listings', (SELECT count(*) FROM public.listings)::text, true)
    || set_config('pkg.anon_bids', (SELECT count(*) FROM public.bids)::text, true) AS stash;
RESET ROLE;
SET LOCAL "request.jwt.claims" = '{"role":"authenticated","sub":"00000000-0000-4000-8000-000000000154"}';
SET LOCAL ROLE authenticated;
SELECT 'anon_listings=' || current_setting('pkg.anon_listings')
UNION ALL SELECT 'anon_bids=' || current_setting('pkg.anon_bids')
UNION ALL SELECT 'nonparty_listings=' || (SELECT count(*) FROM public.listings)
UNION ALL SELECT 'nonparty_bids=' || (SELECT count(*) FROM public.bids);

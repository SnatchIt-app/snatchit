-- ============================================================================
-- 130_replay_parity.sql — SOURCE == FRESH REPLAY == PRODUCTION.
--
-- This file exists because the pgTAP suite runs against a FRESHLY REPLAYED
-- database, which makes it the only place in the project that can observe a
-- replay-only divergence. Two were found, and migration 075 closes both:
--
--   SEC-4  000_baseline_schema.sql creates six storage.objects policies
--          (blocks 5 and 12) that no later migration drops. Production does not
--          have them — its 11 policies all come from 033/034/048/049/051/053 —
--          so a rebuild got 17 policies, six of them TO PUBLIC, two of them
--          unguarded DELETE policies that OR together with (and therefore
--          defeat) the "unreferenced" guards 048 and 049 added. A rebuild was
--          strictly WEAKER than the database it was supposed to reproduce.
--
--   D-5    'sweep-auth-password-changes' runs in production (jobid 10) but is
--          scheduled by no migration; 0600 only mentions it in a comment. A
--          rebuild silently lost password-change security notifications
--          entirely — function present, nothing ever calling it.
--
-- RED->GREEN, observable in CI: before 075 assertions 1-3 fail on a fresh
-- replay (six orphans present, 17 policies) and assertions 8-10 fail (no job).
-- After 075 the replay reports the same 11 policies and the same one cron job
-- as production.
--
-- CATALOG-LEVEL ONLY, for the same reason 100_storage.sql is: asserting
-- behaviour here would mean INSERTing into storage.objects, whose column set
-- and INSERT triggers vary across storage-api versions, and cron.job_run_details
-- would require actually waiting for a scheduled tick.
--
-- Ground truth for every expected value below is the PRODUCTION catalog, read
-- 2026-08-27.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(12);

-- ── SEC-4 ───────────────────────────────────────────────────────────────────

-- 1. The six baseline orphans are gone. This is the assertion that fails on an
--    un-migrated fresh replay and passes on production unchanged.
SELECT is_empty(
  $$ SELECT policyname FROM pg_policies
      WHERE schemaname = 'storage' AND tablename = 'objects'
        AND policyname IN ('storage: public read','storage: owner upload',
                           'storage: owner delete','avatars: public read',
                           'avatars: owner upload','avatars: owner delete') $$,
  'SEC-4: none of the six 000_baseline storage.objects policies survive (075)');

-- 2. The count matches production exactly. 17 on an un-migrated replay.
SELECT is(
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'),
  11::bigint,
  'SEC-4: storage.objects has exactly 11 policies, as production does');

-- 3. And they are the SAME eleven, not merely eleven of something. Set
--    equality catches a rename or a swap that a count would miss.
SELECT set_eq(
  $$ SELECT policyname FROM pg_policies
      WHERE schemaname = 'storage' AND tablename = 'objects' $$,
  ARRAY['auction-media owner delete unreferenced',
        'auction-media owner insert',
        'auction-media owner update',
        'avatars owner insert',
        'avatars owner update',
        'proof-docs owner delete unreferenced',
        'proof-docs owner insert',
        'proof-docs owner read',
        'proof-docs owner update',
        'proof-docs transfer party read',
        'public read public buckets'],
  'SEC-4: the storage.objects policy set is exactly production''s eleven');

-- 4. Exactly one policy reaches PUBLIC/anon, and it is 051's scoped public
--    read. The six orphans carried no TO clause, so each defaulted to PUBLIC.
SELECT set_eq(
  $$ SELECT policyname FROM pg_policies
      WHERE schemaname = 'storage' AND tablename = 'objects'
        AND roles::text[] && ARRAY['public','anon'] $$,
  ARRAY['public read public buckets'],
  'SEC-4: only "public read public buckets" is reachable by public/anon');

-- 5. No WRITE path on storage.objects is reachable by public/anon. This is the
--    concrete widening the orphans introduced: "storage: owner upload" and
--    "avatars: owner upload" gave anon an INSERT policy, and the two orphan
--    DELETE policies gave anon a DELETE policy.
SELECT is_empty(
  $$ SELECT policyname FROM pg_policies
      WHERE schemaname = 'storage' AND tablename = 'objects'
        AND cmd IN ('INSERT','UPDATE','DELETE')
        AND roles::text[] && ARRAY['public','anon'] $$,
  'SEC-4: no INSERT/UPDATE/DELETE policy on storage.objects reaches public/anon');

-- 6. Exactly two DELETE policies, matching production (048 + 049).
SELECT is(
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND cmd = 'DELETE'),
  2::bigint,
  'SEC-4: exactly two DELETE policies on storage.objects (048, 049)');

-- 7. Every one of them carries the "unreferenced" guard. RLS policies OR
--    together within a command, so a single unguarded DELETE policy silently
--    repeals 048 — a seller could delete the cover image out from under a live
--    listing. Both orphan DELETE policies were unguarded.
SELECT is_empty(
  $$ SELECT policyname FROM pg_policies
      WHERE schemaname = 'storage' AND tablename = 'objects'
        AND cmd = 'DELETE'
        AND (qual IS NULL OR qual NOT ILIKE '%NOT (EXISTS%') $$,
  'SEC-4: every storage.objects DELETE policy keeps the unreferenced guard (048/049 not defeated)');

-- ── D-5 ─────────────────────────────────────────────────────────────────────

-- 8. The job is scheduled at all. Fails on an un-migrated fresh replay, where
--    password-change notifications simply never fire.
SELECT is(
  (SELECT count(*) FROM cron.job WHERE jobname = 'sweep-auth-password-changes'),
  1::bigint,
  'D-5: exactly one "sweep-auth-password-changes" cron job exists');

-- 9. The full four-way match the 075 guard keys on: jobname + schedule +
--    command + active. This is the byte-for-byte command literal proven equal
--    to production's jobid 10 (md5 a8688b5b2add782b9a988d1f3850cd07, length 44).
SELECT is(
  (SELECT count(*) FROM cron.job
    WHERE jobname  = 'sweep-auth-password-changes'
      AND schedule = '*/5 * * * *'
      AND command  = 'select public.sweep_auth_password_changes();'
      AND active),
  1::bigint,
  'D-5: the job matches production on schedule, command and active exactly');

-- 10. No drifted sibling under the same name.
SELECT is_empty(
  $$ SELECT jobname FROM cron.job
      WHERE jobname = 'sweep-auth-password-changes'
        AND (schedule <> '*/5 * * * *'
             OR command <> 'select public.sweep_auth_password_changes();'
             OR NOT active) $$,
  'D-5: no drifted or inactive duplicate of the sweep job');

-- 11. The function the job calls exists and is SECURITY DEFINER. It must be:
--     only postgres can read auth.audit_log_entries — service_role cannot —
--     which is why this is a cron job and not an edge function. A scheduled
--     job pointing at a missing or INVOKER function is a silent no-op.
SELECT is(
  (SELECT p.prosecdef FROM pg_proc p
     JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'sweep_auth_password_changes'),
  true,
  'D-5: public.sweep_auth_password_changes() exists and is SECURITY DEFINER');

-- 12. The watermark row the sweep reads FOR UPDATE is seeded (0600). Without
--     it the function returns immediately on NOT FOUND and the schedule
--     restored by 075 would still deliver nothing.
SELECT is(
  (SELECT count(*) FROM public.auth_audit_sweep_state
    WHERE sweep_name = 'auth_password_changed'),
  1::bigint,
  'D-5: the auth_password_changed sweep watermark row is seeded (0600)');

SELECT * FROM finish();
ROLLBACK;

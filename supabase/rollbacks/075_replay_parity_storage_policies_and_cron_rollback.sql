-- 075_replay_parity_storage_policies_and_cron_rollback.sql
-- =============================================================================
-- ROLLBACK FOR 075 — AND AN HONEST STATEMENT THAT IT IS ONLY HALF POSSIBLE.
--
-- Running this file is SAFE and does NOTHING. It prints guidance and exits.
-- That is deliberate. Read on before overriding it.
--
-- First, the fact that governs everything below:
--
--   075 IS A NO-OP ON PRODUCTION. Both of its blocks were proven to
--   short-circuit against the live catalog before they were written (storage
--   orphan count 0; cron four-way guard FALSE, command md5-identical). Applying
--   075 to production changes nothing, so there is NOTHING to roll back there.
--   The only environment 075 changes is a fresh replay.
--
-- Which means: if you are here because production looks wrong, 075 is not the
-- cause and rolling it back will not help. Reach for this file only for a
-- rebuilt / replayed database.
--
--
-- =============================================================================
-- PART 1 — SEC-4 (the six baseline storage.objects policies): NOT REVERSIBLE.
-- =============================================================================
--
-- This is refused on purpose, and no SQL is provided for it.
--
-- 075 dropped six policies that 000_baseline_schema.sql creates:
--   "storage: public read", "storage: owner upload", "storage: owner delete",
--   "avatars: public read",  "avatars: owner upload",  "avatars: owner delete"
--
-- Recreating them would not restore a prior good state. It would REINTRODUCE A
-- WEAKER AUTHORIZATION SURFACE than production has:
--
--   * All six are TO PUBLIC (no TO clause -> PUBLIC). Production grants these
--     paths to `authenticated` only. Recreating them hands `anon` INSERT and
--     DELETE into the auction-media and avatars buckets.
--
--   * "storage: owner delete" and "avatars: owner delete" have no
--     "unreferenced" predicate. RLS policies OR together within a command, so
--     recreating either one UNIONS with — and therefore defeats — the guard
--     that 048 added ("auction-media owner delete unreferenced", which refuses
--     to delete a file still referenced by listings.cover_image_path). A seller
--     could again delete the cover image out from under a live listing.
--
-- A rollback script whose effect is "make the database less safe than
-- production, and quietly undo migration 048" is not a rollback. Writing the
-- CREATE POLICY statements here so the file looks symmetrical would be
-- pretending, and this file will not pretend.
--
-- If you genuinely need those six policies back — the only honest reason being
-- forensic reproduction of the pre-075 replay artifact, on a throwaway database
-- — copy them out of 000_baseline_schema.sql lines 252-272 and 850-871. Do not
-- run them anywhere that holds real data.
--
-- The correct forward fix, if 075 is judged wrong, is a NEW migration that
-- states what the storage surface should be — not a restoration of these six.
--
--
-- =============================================================================
-- PART 2 — D-5 (the sweep-auth-password-changes cron job): REVERSIBLE, BUT THE
-- REVERSAL IS DESTRUCTIVE AND PROVENANCE CANNOT BE DETERMINED.
-- =============================================================================
--
-- Unscheduling the job is mechanically trivial. The problem is that cron.job
-- carries no record of WHO created a row, so this script cannot distinguish:
--
--   (a) a fresh replay, where 075 created the job  -> unscheduling is a correct
--       rollback; and
--   (b) PRODUCTION, where jobid 10 was created BY HAND on 2026-08-05 and 075
--       left it untouched -> unscheduling would DESTROY a live job, its jobid
--       identity and its cron.job_run_details history, and would silently
--       switch off password-change security notifications for every user.
--
-- Case (b) is an outage caused by a rollback script, which is why nothing runs
-- automatically here.
--
-- To reverse D-5 on a REPLAYED database only, after confirming by hand that the
-- database you are connected to is not production, run:
--
--     -- SELECT cron.unschedule(jobid)
--     --   FROM cron.job
--     --  WHERE jobname = 'sweep-auth-password-changes';
--
-- Note that even in case (a) this leaves the replay diverged from production
-- again — it restores the D-5 defect. There is no state in which unscheduling
-- this job is an improvement.
--
--
-- =============================================================================
-- What this file actually executes: nothing but NOTICEs.
-- =============================================================================

DO $rollback$
DECLARE
  v_orphans int;
  v_job     int;
BEGIN
  SELECT count(*) INTO v_orphans
    FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects'
     AND policyname IN ('storage: public read','storage: owner upload','storage: owner delete',
                        'avatars: public read','avatars: owner upload','avatars: owner delete');

  SELECT count(*) INTO v_job
    FROM cron.job
   WHERE jobname = 'sweep-auth-password-changes';

  RAISE NOTICE '=============================================================';
  RAISE NOTICE '075 ROLLBACK: nothing was changed. This script is a no-op.';
  RAISE NOTICE 'Current state: % of the six baseline storage orphan policies present; % sweep cron job(s).', v_orphans, v_job;
  RAISE NOTICE '';
  RAISE NOTICE 'SEC-4 is NOT reversible. Recreating those six policies would grant';
  RAISE NOTICE 'anon INSERT/DELETE on auction-media and avatars and would defeat the';
  RAISE NOTICE 'unreferenced-delete guard from migration 048. Refused by design.';
  RAISE NOTICE '';
  RAISE NOTICE 'D-5 is reversible but destructive: cron.job records no provenance,';
  RAISE NOTICE 'so this script cannot tell a replay-created job from production''s';
  RAISE NOTICE 'hand-created jobid 10. Unschedule by hand only, and only after';
  RAISE NOTICE 'confirming you are NOT connected to production.';
  RAISE NOTICE '';
  RAISE NOTICE 'Reminder: 075 is a proven no-op on production, so there is nothing';
  RAISE NOTICE 'for it to have broken there. See the header of this file.';
  RAISE NOTICE '=============================================================';
END
$rollback$;

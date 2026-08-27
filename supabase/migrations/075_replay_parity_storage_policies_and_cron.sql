-- 075_replay_parity_storage_policies_and_cron.sql
-- =============================================================================
-- REPRODUCIBILITY / PARITY (SEC-4 + D-5). Pre-Phase-2. NOT a behavioural change.
--
-- PURPOSE
-- Make SOURCE == FRESH REPLAY == PRODUCTION for two objects where the migration
-- chain and the live catalog have silently diverged. Every statement in this
-- file is a no-op against production and closes a real gap on a rebuild. If any
-- statement here would change live production behaviour, this migration is
-- wrong and must be reclassified — it is deliberately authored so that it
-- cannot.
--
-- This migration introduces ZERO new user-facing behaviour, grants nothing,
-- widens nothing, and creates no new object that production does not already
-- have.
--
--
-- =============================================================================
-- SEC-4 — six orphan storage.objects policies that exist only in SOURCE
-- =============================================================================
--
-- THE DEFECT
-- 000_baseline_schema.sql creates six policies on storage.objects and no later
-- migration ever drops them:
--
--   block 5  (auction-media), lines 252-272:
--     "storage: public read"    SELECT  using  (bucket_id = 'auction-media')
--     "storage: owner upload"   INSERT  check  (bucket_id = 'auction-media'
--                                        and auth.uid()::text = (storage.foldername(name))[1])
--     "storage: owner delete"   DELETE  using  (bucket_id = 'auction-media'
--                                        and auth.uid()::text = (storage.foldername(name))[1])
--
--   block 12 (avatars), lines 850-871:
--     "avatars: public read"    SELECT  using  (bucket_id = 'avatars')
--     "avatars: owner upload"   INSERT  check  (bucket_id = 'avatars'
--                                        and auth.uid()::text = (storage.foldername(name))[1])
--     "avatars: owner delete"   DELETE  using  (bucket_id = 'avatars'
--                                        and auth.uid()::text = (storage.foldername(name))[1])
--
-- None of the six carries a TO clause, so PostgreSQL defaults them to
-- TO PUBLIC — they apply to anon as well as authenticated.
--
-- The later storage migrations (033, 034, 048, 049, 051, 053) reconciled the
-- live surface by dropping the DASHBOARD-created legacy names
-- ("allow uploads v2 51etwa_0", "Allow authenticated avatar upload 1oj01fe_0",
-- "allow public read 51etwa_0", …) and their own names before recreating them.
-- Verified by grep over supabase/migrations: not one of those files mentions
-- any of the six colon-named baseline policies. They are dropped by nothing.
--
-- WHY PRODUCTION DOES NOT HAVE THEM AND A REPLAY DOES
-- Production's storage surface was reconciled out-of-band (Supabase dashboard /
-- SQL editor) before 051 and 053 codified it; 000_baseline_schema.sql is a
-- RECONSTRUCTED baseline, not a transcript of what was actually executed
-- against production. The live catalog therefore holds only the 11 policies
-- that 033/034/048/049/051/053 create. A fresh replay, which really does
-- execute block 5 and block 12, gets those 11 PLUS the six baseline orphans.
--
-- VERIFIED against the production catalog 2026-08-27 (pg_policies, schemaname
-- 'storage', tablename 'objects'):
--   * total policy count = 11
--   * count of the six baseline names present = 0
--
-- WHY IT MATTERS (this is a security divergence, not cosmetic)
-- A from-source rebuild has a STRICTLY WEAKER storage authorization surface
-- than production, in two specific ways:
--
--   1. ROLE WIDENING. All 11 production policies except "public read public
--      buckets" are TO authenticated. The six orphans are TO PUBLIC, so on a
--      replay `anon` gains INSERT and DELETE paths into auction-media and
--      avatars that production does not grant to anon at all.
--
--   2. MISSING "UNREFERENCED" GUARD ON DELETE. 048 and 049 deliberately
--      narrowed deletion so a file still referenced by a live row cannot be
--      removed:
--        "auction-media owner delete unreferenced" adds
--            NOT EXISTS (SELECT 1 FROM listings l WHERE l.cover_image_path = objects.name)
--        "proof-docs owner delete unreferenced" adds the equivalent over
--            listings.proof_of_ownership_path and transfers.transfer_evidence_path
--      The baseline's "storage: owner delete" and "avatars: owner delete" have
--      NO such guard. RLS policies are OR-ed together within a command, so on a
--      replay the unguarded baseline DELETE policy UNIONS with — and therefore
--      completely defeats — the guard 048 added. A seller could delete the
--      cover image out from under a live listing on a rebuilt stack and not on
--      production.
--
-- So this is not "extra rows in a catalog". A rebuild from source produces a
-- database that is less safe than the one it is supposed to reproduce, which is
-- exactly what a rebuild must never do.
--
-- THE FIX: drop the six. Not "recreate them TO authenticated" — 051 and 053
-- already own the correct, narrower replacements, and adding a seventh through
-- twelfth policy would be new behaviour. Convergence here means SUBTRACTION.
--
-- WHY THIS IS A NO-OP ON PRODUCTION
-- The DO block below reads pg_policies FIRST and RETURNs before executing any
-- DDL when none of the six is present. On production that count is 0
-- (verified above), so ZERO DROP statements are ever reached. On a fresh replay
-- the count is 6 and all six are dropped.
--
-- WHY THE GUARD IS AN EXPLICIT pg_policies LOOKUP AND NOT `DROP POLICY IF EXISTS`
-- This is the important part, and it is a hard production-safety requirement,
-- not a style choice. On hosted Supabase:
--
--   storage.objects is OWNED BY supabase_storage_admin
--   postgres is NOT a member of supabase_storage_admin  (pg_has_role = false)
--   postgres is NOT a superuser                         (pg_roles.rolsuper = false)
--
-- (all three verified against the production catalog 2026-08-27). The migration
-- runner connects as postgres. A bare `DROP POLICY IF EXISTS … ON
-- storage.objects` therefore names a relation this role does not own, and
-- whether IF EXISTS short-circuits ahead of the ownership check is a detail of
-- the backend's drop path that this migration deliberately does not bet on — a
-- sibling migration was aborted by exactly this. Reading pg_policies first and
-- never emitting the DDL at all removes the question: on production the DROP is
-- not skipped, it is never parsed.
--
-- The block additionally refuses to proceed — loudly — if the six ARE present
-- but the current role could not drop them, rather than aborting on a cryptic
-- "must be owner of relation objects".
--
-- LOCKS / RUNTIME
-- On production: none. No DDL is executed; the block performs two catalog
-- SELECTs. On a fresh replay: six DROP POLICY statements, each taking a brief
-- ACCESS EXCLUSIVE lock on storage.objects on an empty table. Sub-millisecond.
--
--
-- =============================================================================
-- D-5 — cron job that runs in production and is scheduled by no migration
-- =============================================================================
--
-- THE DEFECT
-- Production runs jobid 10, jobname 'sweep-auth-password-changes',
-- schedule '*/5 * * * *', command 'select public.sweep_auth_password_changes();',
-- active, username postgres (verified from cron.job, 2026-08-27). No migration
-- in the chain schedules it. 0600_auth_password_change_notifications.sql line 55
-- only MENTIONS it, in a comment:
--     -- Scheduled: sweep-auth-password-changes @ */5 * * * *, active.
-- It was scheduled by hand and never written down as SQL. 0600 and 0601 create
-- and fix the FUNCTION; nothing schedules the JOB.
--
-- WHAT THE FUNCTION DOES, AND WHAT A REBUILD LOSES
-- public.sweep_auth_password_changes() (0600, fixed by 0601) is a watermark
-- sweep over auth.audit_log_entries. Every run it takes an advisory xact lock,
-- reads {floor_at, watermark} FOR UPDATE from public.auth_audit_sweep_state for
-- sweep_name 'auth_password_changed', and scans the window
-- (greatest(watermark - 60 minutes, floor_at), now()] for entries whose payload
-- action is 'user_updated_password', excluding the all-zeros actor and
-- requiring the actor_id to match a uuid regex. For each such entry it calls
-- public.enqueue_notification() for the matching non-deleted, non-anonymous
-- auth.users row, emitting a 'security_password_changed' inbox notification
-- ("Your password was changed …") linked to /account/security and deduplicated
-- on the key 'auth_pwd:<audit_id>'. The watermark advances only on success, so
-- a failure retries the window instead of dropping events; failures are
-- recorded in auth_audit_sweep_state.last_error.
--
-- It is SECURITY DEFINER because only postgres can read auth.audit_log_entries
-- (service_role cannot), which is why this is a cron job and not an edge
-- function.
--
-- So a rebuilt stack silently loses password-change security notifications
-- ENTIRELY. The function is present and correct; nothing ever calls it. The
-- watermark sits unadvanced and no user is ever told that the password on their
-- account changed. There is no error, no log line, and no failing test — the
-- feature is simply absent. That is the worst shape a reproducibility gap can
-- take.
--
-- THE FOUR-WAY EXACT GUARD
-- The block below (re)schedules ONLY when there is no job matching all four of
-- jobname AND schedule AND command AND active. Production matches all four, so
-- the "diverged" predicate is FALSE and neither unschedule nor schedule runs —
-- jobid 10 keeps its identity, its ownership and its cron.job_run_details
-- history. This was not reasoned about; it was EXECUTED against production as a
-- read-only SELECT on 2026-08-27:
--
--   select NOT EXISTS (
--     SELECT 1 FROM cron.job
--      WHERE jobname  = 'sweep-auth-password-changes'
--        AND schedule = '*/5 * * * *'
--        AND command  = 'select public.sweep_auth_password_changes();'
--        AND active   = true) as d5_guard_would_fire;
--   -> d5_guard_would_fire = false
--
-- The command literal was additionally proven byte-for-byte identical to the
-- live one rather than merely "looks the same":
--   md5(cron.job.command WHERE jobid=10) = a8688b5b2add782b9a988d1f3850cd07
--   md5('select public.sweep_auth_password_changes();')
--                                        = a8688b5b2add782b9a988d1f3850cd07
--   length both 44
-- A guard that did not match byte-for-byte would have fired ON PRODUCTION and
-- destroyed jobid 10, which is precisely the failure this shape prevents.
--
-- On a fresh replay no such job exists, the predicate is TRUE, and the job is
-- created with exactly production's schedule and command.
--
-- WHY unschedule-then-schedule RATHER THAN cron.alter_job
-- The unschedule path is reached only when a job with this NAME exists but
-- differs in schedule, command or active — i.e. an environment that has drifted
-- and must be forced onto the canonical definition. Deleting by jobid and
-- recreating is the idiom 014 and 032 already use in this repo. It is never
-- reached on production.
--
-- pg_cron availability: 014_frequent_cron_schedules.sql runs earlier in the
-- chain and does `create extension if not exists pg_cron`, so cron.job exists
-- by the time this migration runs in any full replay. The block fails loudly
-- rather than silently skipping if it does not.
--
-- LOCKS / RUNTIME
-- On production: none. Two catalog SELECTs, no write to cron.job. On a fresh
-- replay: one row inserted into cron.job. Sub-millisecond.
--
--
-- =============================================================================
-- COMPATIBILITY
-- =============================================================================
-- Mobile client, web client and edge functions: unaffected. No RPC, table,
-- column, grant, trigger or public-schema policy is touched. The six dropped
-- policies do not exist in production, so no production request path can be
-- referencing them. The cron job is left byte-identical.
--
-- Gate-2: the CI Gate-2 parity check counts pg_policies WHERE schemaname =
-- 'public' only, so this migration's storage-schema change is INVISIBLE to it
-- and EXPECT_POLICIES stays 37. That is a gap in the check, not in this
-- migration; see the PR description.
--
-- Tests:    supabase/tests/130_replay_parity.sql (12 assertions)
-- Rollback: supabase/rollbacks/075_replay_parity_storage_policies_and_cron_rollback.sql
--           (SEC-4 is deliberately NOT reversible — see that file)
--
-- VERIFICATION QUERY (safe to run anywhere; expect identical output on
-- production and on a post-075 fresh replay):
--
--   select
--     (select count(*) from pg_policies
--       where schemaname='storage' and tablename='objects')            as storage_policies,   -- 11
--     (select count(*) from pg_policies
--       where schemaname='storage' and tablename='objects'
--         and policyname in ('storage: public read','storage: owner upload',
--                            'storage: owner delete','avatars: public read',
--                            'avatars: owner upload','avatars: owner delete')) as sec4_orphans, -- 0
--     (select count(*) from cron.job
--       where jobname  = 'sweep-auth-password-changes'
--         and schedule = '*/5 * * * *'
--         and command  = 'select public.sweep_auth_password_changes();'
--         and active)                                                  as d5_job;             -- 1
-- =============================================================================

BEGIN;

-- ── SEC-4 ───────────────────────────────────────────────────────────────────
DO $sec4$
DECLARE
  c_orphans constant text[] := ARRAY[
    'storage: public read',
    'storage: owner upload',
    'storage: owner delete',
    'avatars: public read',
    'avatars: owner upload',
    'avatars: owner delete'
  ];
  v_present  text[];
  v_may_drop boolean;
  v_name     text;
BEGIN
  -- Read the catalog BEFORE emitting any DDL. On production this returns an
  -- empty array and the block returns without ever naming storage.objects in a
  -- DROP — which is what makes it safe under a role that does not own the table.
  SELECT coalesce(array_agg(policyname ORDER BY policyname), ARRAY[]::text[])
    INTO v_present
    FROM pg_policies
   WHERE schemaname = 'storage'
     AND tablename  = 'objects'
     AND policyname = ANY (c_orphans);

  IF cardinality(v_present) = 0 THEN
    RAISE NOTICE '075/SEC-4: none of the six baseline storage.objects policies present — nothing to drop. (This is the production path.)';
    RETURN;
  END IF;

  -- Present. Confirm this role can actually drop them before trying, so a
  -- privilege problem surfaces as an explicit, actionable message.
  SELECT r.rolsuper OR pg_has_role(current_user, c.relowner, 'USAGE')
    INTO v_may_drop
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_roles     r ON r.rolname = current_user
   WHERE n.nspname = 'storage' AND c.relname = 'objects';

  IF NOT coalesce(v_may_drop, false) THEN
    RAISE EXCEPTION '075/SEC-4: % orphan baseline policies exist on storage.objects but role % cannot drop them (table is owned by another role and this role is neither owner, member, nor superuser).',
      cardinality(v_present), current_user
      USING DETAIL = 'Present: ' || array_to_string(v_present, ', '),
            HINT   = 'Re-run as the storage.objects owner (supabase_storage_admin) or as a superuser.';
  END IF;

  FOREACH v_name IN ARRAY v_present LOOP
    EXECUTE format('DROP POLICY %I ON storage.objects', v_name);
    RAISE NOTICE '075/SEC-4: dropped orphan policy "%" on storage.objects', v_name;
  END LOOP;
END
$sec4$;

-- ── D-5 ─────────────────────────────────────────────────────────────────────
DO $d5$
DECLARE
  c_jobname  constant text := 'sweep-auth-password-changes';
  c_schedule constant text := '*/5 * * * *';
  c_command  constant text := 'select public.sweep_auth_password_changes();';
  v_jobid    bigint;
BEGIN
  IF to_regclass('cron.job') IS NULL THEN
    RAISE EXCEPTION '075/D-5: cron.job does not exist — pg_cron is not installed.'
      USING HINT = '014_frequent_cron_schedules.sql installs it; replay the full chain in order.';
  END IF;

  -- Four-way exact match: jobname AND schedule AND command AND active.
  -- TRUE on production -> return, leaving jobid 10 and its run history intact.
  IF EXISTS (
    SELECT 1 FROM cron.job
     WHERE jobname  = c_jobname
       AND schedule = c_schedule
       AND command  = c_command
       AND active
  ) THEN
    RAISE NOTICE '075/D-5: "%" already scheduled with the exact canonical schedule, command and active flag — left untouched. (This is the production path.)', c_jobname;
    RETURN;
  END IF;

  -- Either absent (fresh replay) or drifted. Force onto the canonical definition.
  FOR v_jobid IN SELECT jobid FROM cron.job WHERE jobname = c_jobname LOOP
    PERFORM cron.unschedule(v_jobid);
    RAISE NOTICE '075/D-5: unscheduled drifted job "%" (jobid %)', c_jobname, v_jobid;
  END LOOP;

  PERFORM cron.schedule(c_jobname, c_schedule, c_command);
  RAISE NOTICE '075/D-5: scheduled "%" @ % — password-change security notifications are now swept.', c_jobname, c_schedule;
END
$d5$;

COMMIT;

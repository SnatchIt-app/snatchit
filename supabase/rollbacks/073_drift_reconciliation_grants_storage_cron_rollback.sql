-- Rollback for 073.
--
-- READ THIS BEFORE RUNNING ANY OF IT. This migration is not uniformly
-- reversible, and the parts that ARE reversible are the parts you least want to
-- reverse. Three of the five sections restore a weaker security posture; one
-- cannot be honestly reversed at all. Each section below states which it is.
-- Run sections INDIVIDUALLY. Do not run this file top to bottom as a unit —
-- there is no scenario in which reverting all five at once is the right move.
--
-- Preferred alternative in almost every case: 073 is metadata-only, so a
-- corrected forward migration is safer than a revert.

-- =============================================================================
-- §1. SEC-1 — webhook_retries client DML
--
-- *** THIS IS A SECURITY REGRESSION. DO NOT RUN IT TO "TIDY UP". ***
--
-- Running this re-grants anon and authenticated SELECT/INSERT/UPDATE/DELETE on
-- public.webhook_retries — restoring exactly the drifted state that 073 §1 was
-- written to close, and that migration 069 line 22 had already tried to close.
-- The table is deny-all (RLS on, zero policies) and empty, so the immediate
-- blast radius is small, but this hands the client roles a table-level DML
-- grant whose only remaining barrier is RLS. It is a defence-in-depth
-- regression, and it is the ONE state this repo has already decided twice it
-- does not want.
--
-- There is no plausible operational failure of 073 §1 that this fixes: a REVOKE
-- of privileges nobody uses cannot break a caller. If something broke after
-- 073, it was §2 or §5, not this. Leave this section alone.
-- =============================================================================
-- BEGIN;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON public.webhook_retries TO anon, authenticated;
-- COMMIT;
--   ^ intentionally left commented out. Uncomment only with a written decision
--     from the owner recording that the regression is accepted.

-- =============================================================================
-- §2. SEC-3 — storage bucket constraints
--
-- REVERSIBLE, and this is the section most likely to actually be needed: if a
-- legitimate upload starts failing with a 413 or a content-type rejection after
-- 073, the fastest safe move is to drop the constraint back to NULL while the
-- allowlist is corrected forward.
--
-- Reverting restores NULL/NULL, i.e. NO server-side size or MIME enforcement on
-- uploads — which is the pre-073 production state, not a new hazard, but it does
-- reopen the direct-to-storage-API bypass described in 073 §2. Prefer reverting
-- only the ONE bucket that is failing.
--
-- No stored object is affected either way: these constraints are evaluated at
-- upload time and are not retroactive.
-- =============================================================================
BEGIN;

UPDATE storage.buckets
   SET file_size_limit = NULL, allowed_mime_types = NULL
 WHERE id IN ('auction-media', 'avatars', 'proof-docs');

COMMIT;

-- =============================================================================
-- §3. SEC-4 — six orphan storage.objects policies
--
-- *** NOT HONESTLY REVERSIBLE, AND DELIBERATELY NOT ATTEMPTED. ***
--
-- On PRODUCTION there is nothing to revert. 073 §3 attempted zero DDL there
-- (the guard found none of the six policies present), so no rollback exists
-- because no change was made. This is the whole section, as far as production
-- is concerned.
--
-- On a FRESH REPLAY the six policies were dropped, and they could be recreated
-- verbatim from 000_baseline_schema.sql blocks 5 and 12. This file does not do
-- so, and that is a judgement, not an omission: recreating them would restore
-- SIX POLICIES THAT PRODUCTION DOES NOT HAVE AND HAS NOT HAD FOR MONTHS. They
-- are TO PUBLIC where the live policies are TO authenticated, and their DELETE
-- variants lack the "unreferenced" guard that 048/049 added specifically to stop
-- a seller deleting media a live listing still points at. Writing a rollback
-- that re-widens a rebuild's storage authorization surface would be writing SQL
-- that pretends to be a safety net while being the hazard.
--
-- If a rebuild genuinely needs them back, take them from
-- 000_baseline_schema.sql lines ~252-272 and ~850-872 as a conscious act, and
-- record why. There is no supported path here.
-- =============================================================================

-- =============================================================================
-- §4. D-5 — sweep-auth-password-changes cron schedule
--
-- REVERSIBLE, but on PRODUCTION there is again nothing to revert: 073 §4's
-- guard matched production's existing jobid 10 exactly (name, schedule, command,
-- active) and took no action, so the job was never unscheduled or recreated and
-- still carries its original jobid and run history.
--
-- Running the statement below on production would DELETE a job that 073 did not
-- create and that production has been running since before this migration
-- existed — stopping password-change security notifications entirely. That is a
-- real user-facing security regression, not a cleanup.
--
-- Only meaningful on a database where 073 actually created the job (a fresh
-- replay) and where the job is now causing harm.
-- =============================================================================
-- SELECT cron.unschedule(jobname)
--   FROM cron.job
--  WHERE jobname = 'sweep-auth-password-changes';
--   ^ intentionally left commented out. On production this deletes a live
--     security-notification job that 073 never touched.

-- =============================================================================
-- §5. PUBLIC EXECUTE cleanup
--
-- REVERSIBLE. This restores PUBLIC + anon EXECUTE on the six functions.
--
-- Group A (the four trigger functions) is the safest thing in this file to
-- revert and also the most pointless: those functions cannot be invoked
-- directly at all (RETURNS trigger), and trigger firing never consults EXECUTE,
-- so neither 073 §5 nor this revert can change any behaviour. Reverting them
-- buys nothing.
--
-- Group B is the one with a real, if narrow, failure mode: if some caller this
-- investigation did not find relies on ANON executing is_winner or
-- is_blocked_by_me over PostgREST, it now gets a 403. The evidence says no such
-- caller exists (no RLS policy, no other function body, view or constraint
-- references them in production, and neither appears among the 33 distinct RPC
-- names the mobile/web/edge codebases call), but evidence of absence from a
-- grep is not proof. If a signed-out browse path breaks immediately after 073,
-- this is the section to run — and then find the caller and re-grant narrowly
-- rather than leaving PUBLIC restored.
--
-- Note this does NOT restore the `=X/postgres` PUBLIC entry's provenance, only
-- an equivalent grant. That distinction has no practical effect.
-- =============================================================================
BEGIN;

GRANT EXECUTE ON FUNCTION public.dispute_resolutions_append_only()       TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.guard_transfer_state_columns()          TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reset_transfer_guard_bypass()           TO PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_ambassador_application_updated_at() TO PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.is_blocked_by_me(uuid)                  TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_winner(uuid, uuid)                   TO PUBLIC, anon;

COMMIT;

-- =============================================================================
-- §6. SEC-2 — nothing to roll back.
--
-- 073 §6 contains no SQL. The pg_default_acl entries were deliberately left
-- untouched (they are vendor-managed). The countermeasures are a documented
-- standing rule and a CI assertion, both of which are reverted by reverting the
-- commit, not by running SQL.
-- =============================================================================

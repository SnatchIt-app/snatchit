-- =============================================================================
-- Migration 032: Pre-TestFlight blocker fixes (C1 cron collision, C2/C3 grants)
-- =============================================================================
-- Source: PRE_TESTFLIGHT_FINAL_AUDIT.md — all three findings re-verified live
-- on 2026-06-11 before writing this migration.
--
--   C2: public.admin_resolve_dispute(uuid,text,uuid)
--       SECURITY DEFINER, EXECUTE granted to PUBLIC/anon/authenticated, and
--       the body has NO auth.uid() guard — it trusts caller-supplied
--       p_admin_id. Anyone with the anon key could resolve any dispute.
--       → revoke all client grants; service_role/postgres only.
--
--   C3: public.delete_account_cleanup(uuid)
--       SECURITY DEFINER, same open grants, NO auth.uid() guard. Body comment
--       says "only called from the service-role delete-account edge function"
--       but nothing enforced it: anyone with the anon key could cancel any
--       seller's live listings and anonymize their records.
--       → revoke all client grants; service_role only (the delete-account
--         edge function authenticates the user itself, then calls this with
--         the service-role key — unaffected by the revoke).
--
--   C1: Expired-transfer refunds broken by a cron collision.
--       jobid 8 'enforce-transfer-expiry'      → net.http_post → edge function
--         (expiry RPC + STRIPE REFUNDS). Fails EVERY run with:
--         ERROR: unrecognized configuration parameter "app.settings.supabase_url"
--       jobid 6 'enforce-transfer-expiry-job'  → SELECT public.enforce_transfer_expiry();
--         Succeeds every 2 min. The RPC is UPDATE…RETURNING — pg_cron discards
--         the returned rows, so transfers flip pending→expired and the refund
--         step NEVER runs. Two live buyers are expired+paid+unrefunded.
--       → unschedule the refund-less shadow job (6) and RESCHEDULE the HTTP
--         job with the (public, non-secret) project URL inlined and the
--         service-role key read from Supabase Vault at runtime. ALTER DATABASE
--         SET is NOT used — the managed `postgres` role lacks permission to
--         set custom GUCs at database level (v1 of this migration failed on
--         exactly that), and Vault is the Supabase-recommended pattern.
--       Fail-safe note: until the Vault secret 'service_role_key' is created
--       (manual step below), transfer expiry PAUSES entirely (transfers stay
--       'pending' a little longer). That is the correct failure mode — no
--       transition without its refund.
--
--   Bonus (verified identical commands): jobid 1 'finalize-auctions' is an
--   exact duplicate of jobid 7 'auto-finalize-auctions' (both run
--   public.auto_finalize_expired_auctions() every 2 min; SKIP LOCKED makes
--   the dup harmless but noisy). The older duplicate is removed.
--
-- NO SECRETS ARE COMMITTED IN THIS FILE. See MANUAL STEP at the bottom.
-- Idempotent: re-running is a no-op.
-- =============================================================================

BEGIN;

-- ── C2: lock down admin_resolve_dispute ─────────────────────────────────────
REVOKE ALL ON FUNCTION public.admin_resolve_dispute(uuid, text, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_resolve_dispute(uuid, text, uuid)
  TO service_role;

-- ── C3: lock down delete_account_cleanup ────────────────────────────────────
REVOKE ALL ON FUNCTION public.delete_account_cleanup(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_account_cleanup(uuid)
  TO service_role;

-- Defense in depth: the bare expiry RPC should also not be client-callable.
-- It is only ever invoked by the edge function (service role) / cron.
REVOKE ALL ON FUNCTION public.enforce_transfer_expiry()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enforce_transfer_expiry()
  TO service_role;

-- ── C1a: remove the refund-less shadow cron job ─────────────────────────────
-- 'enforce-transfer-expiry-job' (jobid 6) expires transfers WITHOUT refunds.
-- The HTTP job 'enforce-transfer-expiry' (kept) performs expiry AND refunds.
SELECT cron.unschedule(jobname)
  FROM cron.job
 WHERE jobname = 'enforce-transfer-expiry-job';

-- ── C1b: remove the duplicate auction finalizer ─────────────────────────────
-- 'finalize-auctions' (jobid 1) duplicates 'auto-finalize-auctions' (jobid 7).
SELECT cron.unschedule(jobname)
  FROM cron.job
 WHERE jobname = 'finalize-auctions';

-- ── C1c: reschedule the HTTP refund cron without GUC dependencies ───────────
-- Old command read current_setting('app.settings.supabase_url') and
-- current_setting('app.settings.service_role_key') — GUCs that were never set
-- and that the managed postgres role cannot set via ALTER DATABASE.
-- New command: project URL inlined (it is public — already shipped in the
-- client bundle / eas.json); service-role key resolved AT RUNTIME from
-- Supabase Vault (extension verified installed). NO SECRET IS COMMITTED HERE.
-- If the Vault secret does not exist yet, each run errors harmlessly until
-- the manual step below is performed (same fail-safe pause as today).
SELECT cron.unschedule(jobname)
  FROM cron.job
 WHERE jobname = 'enforce-transfer-expiry';

SELECT cron.schedule(
  'enforce-transfer-expiry',
  '*/2 * * * *',
  $cron$
  SELECT net.http_post(
    url     := 'https://hqycwntpfoztoinemqns.supabase.co/functions/v1/enforce-transfer-expiry',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (
        SELECT decrypted_secret
          FROM vault.decrypted_secrets
         WHERE name = 'service_role_key'
         ORDER BY created_at DESC
         LIMIT 1
      ),
      'Content-Type', 'application/json'
    ),
    body    := '{}'::jsonb
  );
  $cron$
);

COMMIT;

-- =============================================================================
-- MANUAL STEP (REQUIRED — DO NOT COMMIT THE VALUE):
-- Store the service-role key in Supabase Vault. Run ONCE in the Supabase
-- Dashboard SQL Editor (Dashboard → Project Settings → API → service_role):
--
--   SELECT vault.create_secret('<SERVICE_ROLE_KEY_FROM_DASHBOARD>', 'service_role_key');
--
--   The cron job reads it at runtime on every tick, so the next 2-minute run
--   picks it up automatically. No GUCs, no ALTER DATABASE, nothing committed.
--
-- VERIFICATION (run after the manual step, wait ≥4 minutes):
--
--   1. Cron health — expect 'enforce-transfer-expiry' → succeeded, and no
--      rows for the two unscheduled jobs:
--        SELECT j.jobname, d.status, d.return_message, d.start_time
--          FROM cron.job_run_details d JOIN cron.job j ON j.jobid = d.jobid
--         WHERE d.start_time > now() - interval '10 minutes'
--         ORDER BY d.start_time DESC;
--
--   2. Grants — all four must return FALSE:
--        SELECT
--          has_function_privilege('anon',          'public.admin_resolve_dispute(uuid,text,uuid)', 'EXECUTE'),
--          has_function_privilege('authenticated', 'public.admin_resolve_dispute(uuid,text,uuid)', 'EXECUTE'),
--          has_function_privilege('anon',          'public.delete_account_cleanup(uuid)',          'EXECUTE'),
--          has_function_privilege('authenticated', 'public.delete_account_cleanup(uuid)',          'EXECUTE');
--
--   3. After the two manual Stripe refunds (see audit refund plan) — expect 0:
--        SELECT COUNT(*) FROM public.transfers t
--          JOIN public.payments p ON p.id = t.payment_id
--         WHERE t.status = 'expired' AND p.refunded_at IS NULL;
-- =============================================================================

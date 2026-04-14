-- 014_frequent_cron_schedules.sql
-- Change auction finalization and transfer expiry from nightly to every 2 minutes.
-- Requires pg_cron extension (enabled by default on Supabase).

-- Enable pg_cron + pg_net if not already enabled
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net  with schema extensions;

-- ─── Auto-finalize auctions: every 2 minutes ─────────────────────────────────
-- Remove any existing job with the same name to avoid duplicates
select cron.unschedule(jobname)
  from cron.job
 where jobname = 'auto-finalize-auctions';

select cron.schedule(
  'auto-finalize-auctions',
  '*/2 * * * *',                       -- every 2 minutes
  $$select public.auto_finalize_expired_auctions();$$
);

-- ─── Enforce transfer expiry: every 2 minutes ────────────────────────────────
select cron.unschedule(jobname)
  from cron.job
 where jobname = 'enforce-transfer-expiry';

select cron.schedule(
  'enforce-transfer-expiry',
  '*/2 * * * *',                       -- every 2 minutes
  $$select net.http_post(
      url     := current_setting('app.settings.supabase_url') || '/functions/v1/enforce-transfer-expiry',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
        'Content-Type',  'application/json'
      ),
      body    := '{}'::jsonb
    );$$
);

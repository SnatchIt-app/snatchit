-- 057_notifications_dedupe_and_enqueue_helper.sql   APPLIED 2026-08-05, verified.
--
-- public.notifications had 0 rows and ZERO producers. Migrations 034/035 are
-- push-only (pg_net -> Edge Function) and never touch the inbox table, so the
-- inbox has never shown anything since launch.
--
-- Adds the idempotency key the table lacked (nothing could serve as an
-- ON CONFLICT arbiter) plus enqueue_notification(): the single trusted insert
-- path, SECURITY DEFINER owned by postgres.
--
-- enqueue_notification NEVER RAISES. Every producer is a trigger on the
-- bidding / transfer / payout path, so the EXCEPTION block opens a plpgsql
-- subtransaction and a failure rolls back only the INSERT, never the parent
-- marketplace transaction.
--
-- `link` must be a WEB-RELATIVE path. The inbox passes it through
-- safeInternalPath (web/src/lib/auth/redirect.ts), which silently falls back
-- unless it matches ^/(?!/)[^\s\\]*$ and does not start with /auth/. Mobile
-- routes off the push `data` payload instead -- a separate address space.
--
-- Client-insert stays impossible: authenticated holds SELECT + UPDATE(read_at)
-- only, anon holds nothing, RLS has no INSERT policy, and EXECUTE on the helper
-- is granted only to service_role. Verified post-apply.
--
-- Rollback: supabase/rollbacks/057_notifications_dedupe_and_enqueue_helper_rollback.sql

-- ---------------------------------------------------------------------------
-- SQL below recovered verbatim from supabase_migrations.schema_migrations
-- version 20260805044106. This file previously contained documentation only.
-- ---------------------------------------------------------------------------
-- 057: idempotency key + the single trusted insert path for notifications.
--
-- public.notifications has 0 rows and ZERO producers today. Migrations 034/035
-- are push-only (pg_net -> Edge Function) and never touch the inbox table.
-- There is no unique constraint, so nothing can serve as an ON CONFLICT arbiter.
--
-- Client-insert is already impossible and must stay that way: `authenticated`
-- holds SELECT on the 9 columns and UPDATE on read_at ONLY, `anon` holds
-- nothing, and RLS has no INSERT policy. The helper below is SECURITY DEFINER
-- owned by postgres, so it is the ONLY way a row is created.

ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS dedupe_key text;

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_dedupe_key_check;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_dedupe_key_check
  CHECK (dedupe_key IS NULL OR char_length(dedupe_key) <= 200);

-- Partial: keeps the index off any future non-deduped notification.
CREATE UNIQUE INDEX IF NOT EXISTS notifications_dedupe_key_uidx
  ON public.notifications (dedupe_key) WHERE dedupe_key IS NOT NULL;

-- The one trusted producer entry point.
--
-- NEVER RAISES. Every producer is a trigger on the bidding / transfer / payout
-- path, and a notification must never abort a marketplace transaction. The
-- EXCEPTION block opens a plpgsql subtransaction, so a failure here rolls back
-- only this INSERT and the parent statement proceeds.
--
-- `link` must be a web-relative path: the web inbox passes it through
-- safeInternalPath (web/src/lib/auth/redirect.ts), which silently falls back
-- unless it matches ^/(?!/)[^\s\\]*$ and does not start with /auth/. Never
-- store a snatchit:// deep link or an absolute URL here -- mobile routes off
-- the push `data` payload, which is a separate address space.
CREATE OR REPLACE FUNCTION public.enqueue_notification(
  p_user_id    uuid,
  p_type       text,
  p_title      text,
  p_body       text,
  p_link       text,
  p_dedupe_key text,
  p_metadata   jsonb DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF p_user_id IS NULL OR p_dedupe_key IS NULL THEN RETURN; END IF;

  BEGIN
    INSERT INTO public.notifications (user_id, type, title, body, link, metadata, dedupe_key)
    VALUES (p_user_id, p_type, left(p_title,140), left(p_body,1000), p_link,
            coalesce(p_metadata,'{}'::jsonb), p_dedupe_key)
    ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'enqueue_notification failed (parent transaction preserved): %', SQLERRM;
  END;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.enqueue_notification(uuid,text,text,text,text,text,jsonb) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.enqueue_notification(uuid,text,text,text,text,text,jsonb) TO service_role;

-- 060_auth_password_change_notifications.sql   APPLIED 2026-08-05, verified.
-- (applied as 060 + 060b)
--
-- Password-change inbox notifications via a watermark sweep of
-- auth.audit_log_entries. No trigger is added to the auth schema: GoTrue owns
-- it and recreates objects across platform upgrades, and an error in such a
-- trigger would abort signup and login.
--
-- EMAIL CHANGE IS DELIBERATELY NOT SHIPPED. Empirical verdict, five lines of
-- evidence: all 3 `user_modified` rows in production have `traits` entirely
-- absent (no key to test); email change has never been exercised here (14/14
-- users have email_change_sent_at NULL, confirm_status 0); GoTrue in this
-- project has never emitted an email-change-specific action; profiles has no
-- email column to diff against; and every observed `user_modified` was
-- something else -- one a password-reset side-effect firing 0.76ms later, two
-- post-login metadata updates. Shipping on `user_modified` would have produced
-- a 100% false-positive rate: three bogus "your email was changed" security
-- alerts and zero true ones. A false security alert is worse than none.
-- If wanted later, the sound path is a separate sha256(auth.users.email)
-- mirror sweep -- true positives, no guessing, no PII duplicated outside auth.
--
-- DESIGN NOTES
--  * floor_at and watermark are seeded to now() in the same statement that
--    creates the row, and v_lower = greatest(watermark - lookback, floor_at),
--    so the first run cannot reach a historical row. No backfill, by construction.
--  * dedupe_key = 'auth_pwd:' || <audit row uuid>. The audit id is immutable and
--    unique, so the 60-minute overlap re-presents the same key every run and
--    notifications_dedupe_key_uidx absorbs it. Correctness does not depend on
--    the advisory lock.
--  * The 60-minute overlap is mandatory: created_at is GoTrue's application
--    clock, not commit time, so a row stamped T can become visible later.
--    postgres can neither own nor index auth.audit_log_entries (not superuser),
--    so the scan is a seq scan regardless -- widening the window costs no I/O.
--    Measured 17.5ms over 2,489 rows. Revisit past ~500k rows.
--  * Zero-uuid actor excluded explicitly: admin/service_role-initiated resets
--    carry '00000000-...' and a row with that id genuinely exists in auth.users,
--    so a join alone would not filter it.
--  * Inner join auth.users: some audit rows reference deleted users, and
--    notifications.user_id has FK -> auth.users ON DELETE CASCADE.
--  * The watermark advances only on the success path, so a failure retries the
--    window rather than dropping events.
--  * postgres already holds SELECT WITH GRANT OPTION on auth.audit_log_entries
--    from supabase_auth_admin -- no new grant needed. service_role canNOT read
--    it, so this must not be routed through an edge function.
--
-- 060b fixed a real bug the sweep's own error handler caught on first run: the
-- batch was a bare SELECT inside plpgsql ("query has no destination for result
-- data"). It recorded last_error and left the watermark unadvanced, so nothing
-- was skipped. Now SELECT count(*) INTO, which also supplies the row count.
--
-- VERIFIED: clean run on the empty window; temporarily lowering the barrier
-- past the one historical user_updated_password row produced exactly 1
-- notification; replaying produced still exactly 1 (idempotent); correct type
-- and link. Test row deleted and the barrier reset to now() afterwards.
-- Scheduled: sweep-auth-password-changes @ */5 * * * *, active.
--
-- CAVEAT: only one user_updated_password row exists in production and it is the
-- recovery-link path. The authenticated-change path is inferred from the
-- dedicated action name, not observed. Copy deliberately does not assert which
-- path was used.
--
-- Rollback: supabase/rollbacks/060_auth_password_change_notifications_rollback.sql

-- ---------------------------------------------------------------------------
-- SQL below recovered verbatim from supabase_migrations.schema_migrations
-- version 20260805045437. This file previously contained documentation only.
-- ---------------------------------------------------------------------------
-- 060: password-change inbox notifications via a watermark sweep of
-- auth.audit_log_entries. No trigger is added to the auth schema: GoTrue owns
-- it and recreates objects across upgrades, and an error in such a trigger
-- would abort signup/login.
--
-- EMAIL CHANGE IS DELIBERATELY NOT INCLUDED. Empirically there is no reliable
-- discriminator: all 3 `user_modified` rows in production have `traits`
-- entirely absent, email change has never been exercised (14/14 users have
-- email_change_sent_at NULL), GoTrue here has never emitted an
-- email-change-specific action, and profiles has no email column to diff.
-- Every observed `user_modified` was something else -- one a password-reset
-- side-effect, two post-login metadata updates -- so shipping on it would have
-- produced a 100% false-positive rate. A false "your email was changed"
-- security alert is worse than none.

CREATE TABLE IF NOT EXISTS public.auth_audit_sweep_state (
  sweep_name  text PRIMARY KEY,
  floor_at    timestamptz NOT NULL,   -- immutable no-backfill barrier
  watermark   timestamptz NOT NULL,
  last_run_at timestamptz,
  last_error  text,
  sent_count  bigint NOT NULL DEFAULT 0
);
ALTER TABLE public.auth_audit_sweep_state ENABLE ROW LEVEL SECURITY;  -- no policies => no client access
REVOKE ALL ON public.auth_audit_sweep_state FROM anon, authenticated;

-- floor_at and watermark both seeded to now(), so the first run cannot reach
-- any historical row.
INSERT INTO public.auth_audit_sweep_state (sweep_name, floor_at, watermark)
VALUES ('auth_password_changed', now(), now())
ON CONFLICT (sweep_name) DO NOTHING;

CREATE OR REPLACE FUNCTION public.sweep_auth_password_changes()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_catalog
AS $function$
DECLARE
  -- auth.audit_log_entries.created_at is GoTrue's application clock, not commit
  -- time, so a row stamped T can become visible later. The overlap covers that.
  -- postgres cannot index that table (not owner, not superuser), so the scan is
  -- a seq scan regardless and a wider window costs no extra I/O.
  c_lookback constant interval := interval '60 minutes';
  v_floor timestamptz; v_wm timestamptz; v_lower timestamptz;
  v_upper timestamptz := now();
  v_n int := 0;
BEGIN
  -- a slow run must never pile up behind itself
  IF NOT pg_try_advisory_xact_lock(hashtext('sweep_auth_password_changes')) THEN
    RETURN;
  END IF;

  SELECT floor_at, watermark INTO v_floor, v_wm
    FROM public.auth_audit_sweep_state
   WHERE sweep_name = 'auth_password_changed' FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;

  v_lower := greatest(v_wm - c_lookback, v_floor);

  BEGIN
    WITH cand AS MATERIALIZED (
      SELECT e.id, e.created_at, e.payload->>'actor_id' AS actor_txt
        FROM auth.audit_log_entries e
       WHERE e.created_at >  v_lower
         AND e.created_at <= v_upper
         AND e.payload->>'action' = 'user_updated_password'
         -- admin/service_role-initiated resets carry the zero uuid, and a row
         -- with that id genuinely exists in auth.users, so a join alone would
         -- not filter it.
         AND e.payload->>'actor_id' <> '00000000-0000-0000-0000-000000000000'
         AND e.payload->>'actor_id' ~*
             '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    )
    SELECT public.enqueue_notification(
             u.id,
             'security_password_changed',
             'Your password was changed',
             'The password on your Snatch It account was changed. If this was not you, '
             || 'reset your password immediately and contact support.',
             '/account/security',
             'auth_pwd:' || c.id::text,   -- audit row uuid: immutable, unique
             jsonb_build_object('source','auth_audit_sweep','audit_id', c.id,
                                'occurred_at', c.created_at))
      FROM cand c
      -- inner join: some audit rows reference deleted users, and
      -- notifications.user_id has FK -> auth.users ON DELETE CASCADE
      JOIN auth.users u ON u.id = c.actor_txt::uuid
     WHERE u.deleted_at IS NULL
       AND coalesce(u.is_anonymous,false) = false;

    GET DIAGNOSTICS v_n = ROW_COUNT;

    UPDATE public.auth_audit_sweep_state
       SET watermark = v_upper, last_run_at = now(),
           last_error = null, sent_count = sent_count + v_n
     WHERE sweep_name = 'auth_password_changed';

  EXCEPTION WHEN OTHERS THEN
    -- watermark deliberately NOT advanced: the window is retried next tick, so
    -- a failure cannot silently drop events.
    UPDATE public.auth_audit_sweep_state
       SET last_run_at = now(), last_error = left(sqlerrm, 500)
     WHERE sweep_name = 'auth_password_changed';
    RAISE WARNING 'sweep_auth_password_changes failed: %', sqlerrm;
  END;
END;
$function$;

REVOKE ALL ON FUNCTION public.sweep_auth_password_changes() FROM PUBLIC, anon, authenticated;

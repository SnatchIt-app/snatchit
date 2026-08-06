-- 060b_fix_sweep_query_destination.sql
-- Fixes sweep_auth_password_changes(): the bare SELECT inside plpgsql raised
-- "query has no destination for result data". Wrapping it in SELECT count(*) INTO
-- gives it a destination and yields the processed-row count directly, replacing the
-- GET DIAGNOSTICS that followed. The MATERIALIZED CTE stays inside the subquery so
-- the ::uuid cast cannot be reordered ahead of the regex guard.
-- Recovered from supabase_migrations.schema_migrations version 20260805045525; applied 20260805045525. Not re-applied.

-- 060b: the batch statement was a bare `SELECT ... FROM ...` inside plpgsql,
-- which raises "query has no destination for result data". Wrapping it in
-- SELECT count(*) INTO gives it a destination AND yields the processed-row
-- count directly, replacing the GET DIAGNOSTICS that followed. The MATERIALIZED
-- CTE is kept inside the subquery so the ::uuid cast still cannot be reordered
-- ahead of the regex guard.
--
-- Caught by the sweep's own error handler on first run: it recorded last_error
-- and left the watermark unadvanced, so no events were skipped.
CREATE OR REPLACE FUNCTION public.sweep_auth_password_changes()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_catalog
AS $function$
DECLARE
  c_lookback constant interval := interval '60 minutes';
  v_floor timestamptz; v_wm timestamptz; v_lower timestamptz;
  v_upper timestamptz := now();
  v_n int := 0;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('sweep_auth_password_changes')) THEN
    RETURN;
  END IF;

  SELECT floor_at, watermark INTO v_floor, v_wm
    FROM public.auth_audit_sweep_state
   WHERE sweep_name = 'auth_password_changed' FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;

  v_lower := greatest(v_wm - c_lookback, v_floor);

  BEGIN
    SELECT count(*) INTO v_n FROM (
      WITH cand AS MATERIALIZED (
        SELECT e.id, e.created_at, e.payload->>'actor_id' AS actor_txt
          FROM auth.audit_log_entries e
         WHERE e.created_at >  v_lower
           AND e.created_at <= v_upper
           AND e.payload->>'action' = 'user_updated_password'
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
               'auth_pwd:' || c.id::text,
               jsonb_build_object('source','auth_audit_sweep','audit_id', c.id,
                                  'occurred_at', c.created_at)) AS r
        FROM cand c
        JOIN auth.users u ON u.id = c.actor_txt::uuid
       WHERE u.deleted_at IS NULL
         AND coalesce(u.is_anonymous,false) = false
    ) s;

    UPDATE public.auth_audit_sweep_state
       SET watermark = v_upper, last_run_at = now(),
           last_error = null, sent_count = sent_count + v_n
     WHERE sweep_name = 'auth_password_changed';

  EXCEPTION WHEN OTHERS THEN
    UPDATE public.auth_audit_sweep_state
       SET last_run_at = now(), last_error = left(sqlerrm, 500)
     WHERE sweep_name = 'auth_password_changed';
    RAISE WARNING 'sweep_auth_password_changes failed: %', sqlerrm;
  END;
END;
$function$;

REVOKE ALL ON FUNCTION public.sweep_auth_password_changes() FROM PUBLIC, anon, authenticated;

-- Rollback for 060 / 060b.
BEGIN;
SELECT cron.unschedule('sweep-auth-password-changes');
DROP FUNCTION IF EXISTS public.sweep_auth_password_changes();
DROP TABLE IF EXISTS public.auth_audit_sweep_state;
-- Existing security_password_changed notifications are left in place; they are
-- accurate history. Remove with:
--   DELETE FROM public.notifications WHERE dedupe_key LIKE 'auth_pwd:%';
COMMIT;

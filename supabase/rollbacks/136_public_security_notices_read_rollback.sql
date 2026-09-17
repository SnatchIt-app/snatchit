-- ============================================================================
-- 136_public_security_notices_read_rollback.sql — drops the two wrappers and the
-- template v2 row. True inverse: 136 created exactly three things (two functions,
-- one notify.template row at version 2) and changed nothing else (no table, no
-- type row, no grant on any pre-existing object; 135's template v1 was never
-- touched and becomes the rendered copy again). Deploy order
-- on the way back: a client calling public.get_my_security_notices after this
-- runs gets PGRST202; the batch-1 client treats that as "no notices" (the
-- notice screen fails to empty, never to an error). notify.notification rows
-- and their read_at values are untouched. Census −2 functions (107 → 105).
-- ============================================================================
begin;
drop function if exists public.mark_security_notices_read(uuid[]);
drop function if exists public.get_my_security_notices();
delete from notify.template where template_key = 'security_device_rebound' and locale = 'en-US' and channel = 'in_app' and version = 2;
commit;

-- ============================================================================
-- 129_public_revoke_push_token_rollback.sql — drops the wrapper. True inverse:
-- 129 created exactly one object and changed nothing else. Deploy order on
-- the way back: a client calling public.revoke_push_token after this runs
-- gets PGRST202; the candidate client treats that as a non-blocking sign-out
-- failure (contract v2 §2.4), so sign-out itself still completes — but the
-- token is then NOT revoked until the next provider failure or re-registration.
-- Census -1 function (93).
-- ============================================================================
begin;
drop function if exists public.revoke_push_token(text);
commit;

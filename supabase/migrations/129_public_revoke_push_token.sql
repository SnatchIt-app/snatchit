-- ============================================================================
-- 129_public_revoke_push_token.sql — the client's sign-out revoke, reachable.
--
-- WHY. Contract v2 §2.4 (PUSH_TOKEN_CONTRACT_V2.md) told the client to sign
-- out through `notify.revoke_push_token`. `notify` is not in PostgREST's
-- exposed schemas — sandbox pre-flight: `public, graphql_public, kernel`;
-- production: unverified — and the shipped app has never called the notify
-- schema over PostgREST (no `schema('notify')` anywhere in Build 16). So the
-- frozen contract named a function the client could not reach; C found it
-- while implementing it. Exposing `notify` would be a per-environment dashboard
-- change, repeated at every environment and widening the exposed surface; a
-- public wrapper is code, reviewed once, identical everywhere, and PostgREST
-- already publishes `public`. Erratum to the frozen contract: the reply shape
-- `{ revoked: 0|1 }` is unchanged, only the schema the client addresses.
--
-- WHAT. One SECURITY DEFINER wrapper that delegates to the single writer of
-- revoked_at / revoked_reason (092 §5.15). auth.uid() is a request-level
-- claim, so the inner verb sees the same caller: own tokens only, and the
-- count is the only thing disclosed. EXECUTE: authenticated only. Census +1
-- function in public (94); manifest row authenticated-execute; pgTAP 196.
-- Applied nowhere by this file.
-- ============================================================================
begin;

create or replace function public.revoke_push_token(p_token text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  return notify.revoke_push_token(p_token);
end;
$$;

comment on function public.revoke_push_token(text) is
  '129: PostgREST-reachable sign-out revoke. Delegates to notify.revoke_push_token (own tokens only; sets revoked_at, revoked_reason = signed_out, is_active = false; returns {revoked: n}). Exists because the notify schema is not exposed over PostgREST.';

revoke execute on function public.revoke_push_token(text) from public, anon, service_role;
grant  execute on function public.revoke_push_token(text) to authenticated;

commit;

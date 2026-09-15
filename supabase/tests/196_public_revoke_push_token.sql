-- 196_public_revoke_push_token.sql — migration 129: the client's sign-out
-- revoke is reachable through `public`, delegates to notify's single writer,
-- revokes own tokens only, and is callable by authenticated only.
-- Runs as postgres inside BEGIN … ROLLBACK like every suite here.
BEGIN;
SELECT plan(9);

-- ── A. shape and grants ─────────────────────────────────────────────────────
SELECT has_function('public', 'revoke_push_token', ARRAY['text'],
  'A1: public.revoke_push_token(text) exists');
SELECT is_definer('public', 'revoke_push_token', ARRAY['text'],
  'A2: ...SECURITY DEFINER (it must reach notify on the caller''s behalf)');
SELECT ok((SELECT p.proconfig @> ARRAY['search_path=""'] FROM pg_proc p WHERE p.oid = 'public.revoke_push_token(text)'::regprocedure),
  'A3: search_path is pinned to EMPTY (the exact proconfig entry, as 195 A5 asserts — a LIKE would pass for public)');
SELECT ok(has_function_privilege('authenticated', 'public.revoke_push_token(text)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.revoke_push_token(text)', 'EXECUTE')
      AND NOT has_function_privilege('service_role', 'public.revoke_push_token(text)', 'EXECUTE'),
  'A4: EXECUTE authenticated only — anon and service_role refused');

-- ── B. behaviour as a real client ───────────────────────────────────────────
SELECT tap.seed_core();   -- the fixture users; runs as postgres
SELECT tap.login(tap.buyer());
SELECT is((public.register_push_token('ExponentPushToken[196-buyer-aaaaaaaaaaaa]', 'ios', 'secret-196-buyer-0123456789', 'iPhone') ->> 'outcome'),
  'registered', 'B1: the buyer registers a device through the 128 verb');
SELECT is((public.revoke_push_token('ExponentPushToken[196-buyer-aaaaaaaaaaaa]') ->> 'revoked'), '1',
  'B2: ...and revokes it through the public wrapper — reply shape {revoked} as contract v2 §2.4');
SELECT tap.logout();
SELECT is((SELECT revoked_reason || ':' || (NOT is_active)::text FROM public.push_tokens WHERE token = 'ExponentPushToken[196-buyer-aaaaaaaaaaaa]'),
  'signed_out:true', 'B3: the row carries signed_out and is inactive — written by notify''s single writer, not by the client');

-- ── C. IDOR and anon ────────────────────────────────────────────────────────
SELECT tap.login(tap.other_user());
SELECT is((public.revoke_push_token('ExponentPushToken[196-buyer-aaaaaaaaaaaa]') ->> 'revoked'), '0',
  'C1: another account revoking the buyer''s token touches 0 rows and learns nothing else');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$ SELECT public.revoke_push_token('ExponentPushToken[196-buyer-aaaaaaaaaaaa]') $$, '42501',
  NULL, 'C2: anon cannot call it');
SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;

-- ============================================================================
-- 195_register_push_token_secure_rebind.sql — migration 128 v2 (F7).
--
-- The property is a SECURITY one: possession of the DEVICE may claim a push
-- token; knowledge of the token string may not. Sections are the six scenarios
-- the owner named — unauthorized capture (§C), account switching (§D), ordinary
-- sign-out (§E), provider revocation (§F), legacy rows (§G), lost local secrets
-- (§H) — plus the write guard on the proof column (§I).
--
-- Fixture helpers are SECURITY DEFINER on purpose: read under the attacker's own
-- RLS, "the victim's row was deleted" and "the victim's row is invisible to me"
-- are indistinguishable, and the capture assertions would pass for the wrong
-- reason. §I is the exception — it acts as a real client, which is the point.
-- ============================================================================
BEGIN;
SELECT plan(38);
SELECT tap.seed_core();

CREATE TABLE tap.memo_195 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._s195(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_195 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._f195(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_195 WHERE k=$1 $m$;

SELECT tap._s195('tok', 'ExponentPushToken[195-device-aaaaaaaaaaaa]');
SELECT tap._s195('sec', 'device-secret-0123456789abcdef');
SELECT tap._s195('bad', 'wrong-secret-0123456789abcdef');
SELECT tap._s195('nea', 'device-secret-0123456789abcdeg');  -- one character off

CREATE FUNCTION tap._h195(p_secret text) RETURNS text LANGUAGE sql IMMUTABLE AS
$f$ SELECT encode(pg_catalog.sha256(pg_catalog.convert_to(p_secret, 'utf8')), 'hex') $f$;

-- Craft any row state directly, past RLS and past the write guard.
CREATE FUNCTION tap._mkrow195(p_user uuid, p_hash text, p_active boolean,
                              p_reason text, p_revoked_ago interval, p_made_ago interval)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $f$
begin
  perform set_config('app.push_token_verb', 'on', true);
  delete from public.push_tokens where token = tap._f195('tok');
  insert into public.push_tokens (user_id, token, platform, last_used, is_active,
                                  device_secret_hash, revoked_reason, revoked_at, created_at)
  values (p_user, tap._f195('tok'), 'ios', now(), p_active, p_hash, p_reason,
          case when p_revoked_ago is null then null else now() - p_revoked_ago end,
          now() - p_made_ago);
end $f$;

CREATE FUNCTION tap._owner195() RETURNS uuid LANGUAGE sql SECURITY DEFINER AS
$f$ SELECT user_id FROM public.push_tokens WHERE token = tap._f195('tok') $f$;
CREATE FUNCTION tap._rows195() RETURNS int LANGUAGE sql SECURITY DEFINER AS
$f$ SELECT count(*)::int FROM public.push_tokens WHERE token = tap._f195('tok') $f$;
CREATE FUNCTION tap._hash195() RETURNS text LANGUAGE sql SECURITY DEFINER AS
$f$ SELECT device_secret_hash FROM public.push_tokens WHERE token = tap._f195('tok') $f$;
CREATE FUNCTION tap._active195() RETURNS boolean LANGUAGE sql SECURITY DEFINER AS
$f$ SELECT is_active AND revoked_at IS NULL FROM public.push_tokens WHERE token = tap._f195('tok') $f$;
CREATE FUNCTION tap._del195() RETURNS void LANGUAGE sql SECURITY DEFINER AS
$f$ DELETE FROM public.push_tokens WHERE token = tap._f195('tok') $f$;
-- Capture the message so §C can assert the paths are indistinguishable.
CREATE FUNCTION tap._try195(p_secret text) RETURNS text LANGUAGE plpgsql AS $f$
begin
  perform public.register_push_token(tap._f195('tok'), 'ios', p_secret, 'iPhone');
  return 'ok';
exception when others then return SQLSTATE || '|' || SQLERRM;
end $f$;

-- ── A. shape, grants, and the headline claim ────────────────────────────────
SELECT has_function('public'::name, 'register_push_token'::name,
  ARRAY['text','text','text','text']::name[], 'A1: public.register_push_token(text,text,text,text) exists');
SELECT ok(has_function_privilege('authenticated', 'public.register_push_token(text,text,text,text)', 'EXECUTE'),
  'A2: authenticated may EXECUTE it');
SELECT ok(NOT has_function_privilege('anon', 'public.register_push_token(text,text,text,text)', 'EXECUTE'),
  'A3: anon may NOT');
SELECT ok(NOT has_function_privilege('service_role', 'public.register_push_token(text,text,text,text)', 'EXECUTE'),
  'A4: service_role may NOT — no server path registers a handset');
SELECT ok((SELECT p.prosecdef AND p.proconfig::text LIKE '%search_path=%' AND (p.prorettype::regtype)::text = 'jsonb'
             FROM pg_proc p WHERE p.oid = 'public.register_push_token(text,text,text,text)'::regprocedure),
  'A5: SECURITY DEFINER, search_path pinned, returns jsonb');
SELECT has_column('public'::name, 'push_tokens'::name, 'device_secret_hash'::name, 'A6: the proof column exists');
SELECT has_table('public'::name, 'push_token_rebind_epoch'::name, 'A7: the epoch table exists');
SELECT ok(has_function_privilege('service_role', 'public.unbind_push_token(text)', 'EXECUTE'),
  'A8: service_role may unbind (support recovery for a squatted token)');
SELECT ok(NOT has_function_privilege('authenticated', 'public.unbind_push_token(text)', 'EXECUTE'),
  'A9: authenticated may NOT unbind');
-- 128's headline claim, previously asserted nowhere.
SELECT ok(NOT has_function_privilege('authenticated', 'notify.register_push_token(text,text,text,text)', 'EXECUTE'),
  'A10: the insecure notify verb is REVOKED from authenticated — the claim is enforced, not left to a setting');

-- ── B. the owning device ────────────────────────────────────────────────────
SELECT tap._del195();
SELECT tap.logout();
SELECT throws_ok(
  format('SELECT public.register_push_token(%L, %L, %L)', tap._f195('tok'), 'ios', tap._f195('sec')),
  '42501', NULL, 'B1: an unauthenticated caller is refused');
SELECT tap.login(tap.buyer());
SELECT is((public.register_push_token(tap._f195('tok'), 'ios', tap._f195('sec'), 'iPhone') ->> 'outcome'),
  'registered', 'B2: an unclaimed token binds to the caller');
SELECT is(tap._owner195(), tap.buyer(), 'B3: ...owned by the registering account');
SELECT is(tap._hash195(), tap._h195(tap._f195('sec')), 'B4: only the SHA-256 is stored, never the raw secret');
SELECT is((public.register_push_token(tap._f195('tok'), 'ios', tap._f195('bad'), 'iPhone') ->> 'outcome'),
  'refreshed', 'B5: a SECOND secret from the owner still refreshes...');
SELECT is(tap._hash195(), tap._h195(tap._f195('sec')),
  'B6: ...but the stored hash is UNCHANGED — plant-then-claim is blocked');
SELECT is((public.register_push_token(tap._f195('tok'), 'ios', tap._f195('sec')) ->> 'contract_version'), '2',
  'B7: every reply carries contract_version 2');

-- ── C. UNAUTHORIZED CAPTURE ─────────────────────────────────────────────────
SELECT tap.login(tap.other_user());
SELECT is(left(tap._try195(tap._f195('bad')), 5), '42501',
  'C1: knowing the token but not the secret is refused');
SELECT is(tap._owner195(), tap.buyer(), 'C2: ...the victim''s binding is untouched');
SELECT ok(tap._active195(), 'C3: ...still active and unrevoked — nothing was written');
SELECT is(tap._try195(tap._f195('nea')), tap._try195(tap._f195('bad')),
  'C4: a near-miss secret and a wild guess return the IDENTICAL error — no oracle');

-- ── D. ACCOUNT SWITCHING on the same device ─────────────────────────────────
SELECT is((public.register_push_token(tap._f195('tok'), 'ios', tap._f195('sec'), 'iPhone') ->> 'outcome'),
  'rebound', 'D1: presenting the device secret rebinds — a real handover');
SELECT is(tap._owner195(), tap.other_user(), 'D2: ...the token now belongs to the new account');
SELECT is(tap._rows195(), 1, 'D3: ...still exactly one row; the client never fights UNIQUE(token)');

-- ── E. ORDINARY SIGN-OUT ────────────────────────────────────────────────────
-- A binding that HAS a proof stays protected after sign-out: the secret decides.
SELECT tap._mkrow195(tap.buyer(), tap._h195(tap._f195('sec')), false, 'signed_out', interval '1 hour', interval '90 days');
SELECT tap.login(tap.other_user());
SELECT is(left(tap._try195(tap._f195('bad')), 5), '42501',
  'E1: a signed-out binding that HAS a hash is still not claimable without the secret');
-- A pre-epoch binding with no proof, signed out recently, is the handover case.
SELECT tap._mkrow195(tap.buyer(), NULL, false, 'signed_out', interval '1 hour', interval '90 days');
SELECT is((public.register_push_token(tap._f195('tok'), 'ios', tap._f195('sec'), 'iPhone') ->> 'outcome'),
  'rebound_legacy', 'E2: a pre-epoch hash-less binding, signed out recently, IS claimable');
-- The shipped client writes 'sign_out'; notify.revoke_push_token writes
-- 'signed_out'. Accepting one spelling only would fail silently for half the fleet.
SELECT tap._mkrow195(tap.buyer(), NULL, false, 'sign_out', interval '1 hour', interval '90 days');
SELECT is((public.register_push_token(tap._f195('tok'), 'ios', tap._f195('sec'), 'iPhone') ->> 'outcome'),
  'rebound_legacy', 'E3: BOTH sign-out spellings are honoured (client ''sign_out'', server ''signed_out'')');

-- ── F. PROVIDER REVOCATION — the V2 core ────────────────────────────────────
-- notify.record_delivery_result revokes on device_not_registered with no user
-- involvement. That must never open the door.
SELECT tap._mkrow195(tap.buyer(), NULL, false, 'device_not_registered', interval '1 hour', interval '90 days');
SELECT tap.login(tap.other_user());
SELECT is(left(tap._try195(tap._f195('sec')), 5), '42501',
  'F1: a PROVIDER-revoked binding is NOT claimable — a provider signal is not a handover');
SELECT is(tap._owner195(), tap.buyer(), 'F2: ...and it still belongs to its owner');

-- ── G. LEGACY ROWS — the window is transitional, not standing ───────────────
-- Written by the legacy client path AFTER 128: never claimable.
SELECT tap._mkrow195(tap.buyer(), NULL, false, 'signed_out', interval '1 minute', interval '0 seconds');
SELECT is(left(tap._try195(tap._f195('sec')), 5), '42501',
  'G1: a hash-less row created AFTER the epoch is never claimable (the legacy client path)');
-- Signed out long ago: not a handover.
SELECT tap._mkrow195(tap.buyer(), NULL, false, 'signed_out', interval '400 days', interval '500 days');
SELECT is(left(tap._try195(tap._f195('sec')), 5), '42501',
  'G2: a binding signed out long ago is not claimable — the window is bounded');
-- Still signed in.
SELECT tap._mkrow195(tap.buyer(), NULL, true, NULL, NULL, interval '90 days');
SELECT is(left(tap._try195(tap._f195('sec')), 5), '42501',
  'G3: an ACTIVE hash-less binding is not claimable');

-- ── H. LOST LOCAL SECRET ────────────────────────────────────────────────────
SELECT tap._mkrow195(tap.buyer(), tap._h195(tap._f195('sec')), true, NULL, NULL, interval '1 day');
SELECT tap.login(tap.buyer());
SELECT is((public.register_push_token(tap._f195('tok'), 'ios', tap._f195('bad'), 'iPhone') ->> 'outcome'),
  'refreshed', 'H1: an owner presenting a new secret is refreshed (the reply cannot reveal the mismatch)');
SELECT is(tap._hash195(), tap._h195(tap._f195('sec')), 'H2: ...and the stored hash is still the original');
SELECT tap._del195();
SELECT is((public.register_push_token(tap._f195('tok'), 'ios', tap._f195('bad'), 'iPhone') ->> 'outcome'),
  'registered', 'H3: recovery is delete-your-own-row then register — never rotation');

-- ── I. THE PROOF COLUMN IS NOT CLIENT-WRITABLE (acts as a real client) ──────
SELECT tap._mkrow195(tap.buyer(), tap._h195(tap._f195('sec')), true, NULL, NULL, interval '1 day');
-- The verb's flag is transaction-LOCAL, and this whole suite is one transaction,
-- so the fixture helper's own set_config would still be in force here and the
-- guard would not fire. PostgREST gives each request its own transaction, so
-- this reset is a test artefact, not a production concern.
SELECT set_config('app.push_token_verb', '', true);
SELECT tap.login(tap.buyer());
SELECT throws_ok(
  format('UPDATE public.push_tokens SET device_secret_hash = NULL WHERE token = %L', tap._f195('tok')),
  '42501', NULL, 'I1: a client cannot NULL its own hash to forge a claimable legacy row');
SELECT throws_ok(
  format('INSERT INTO public.push_tokens (user_id, token, platform, device_secret_hash) VALUES (%L, %L, %L, %L)',
         tap.buyer(), 'ExponentPushToken[195-other-bbbbbbbbbbbb]', 'ios', 'deadbeef'),
  '42501', NULL, 'I2: a client cannot insert a row carrying a hash of its choosing');
-- Sign-out must keep working: it touches is_active/revoked_*, never the hash.
UPDATE public.push_tokens SET is_active = false, revoked_at = now(), revoked_reason = 'sign_out'
 WHERE token = tap._f195('tok');
SELECT ok(NOT tap._active195(), 'I3: the client CAN still revoke its own binding — sign-out is unaffected');
SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;

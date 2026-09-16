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
SELECT plan(58);
-- [135] a cross-account bind now requires a session claim and answers challenge_required; these helpers give the tests one
CREATE FUNCTION tap._sess195(p_uid uuid) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v uuid := gen_random_uuid();
BEGIN INSERT INTO auth.sessions (id, user_id, created_at, updated_at, aal) VALUES (v, p_uid, clock_timestamp(), clock_timestamp(), 'aal1'); RETURN v; END $$;
CREATE FUNCTION tap._login195s(p_uid uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN PERFORM tap.login(p_uid);
  PERFORM set_config('request.jwt.claims', (coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb || jsonb_build_object('session_id', tap._sess195(p_uid)::text))::text, true); END $$;
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
CREATE FUNCTION tap._agee195() RETURNS void LANGUAGE sql SECURITY DEFINER AS
$f$ UPDATE public.push_token_rebind_epoch SET applied_at = now() - interval '120 days' $f$;
CREATE FUNCTION tap._resete195() RETURNS void LANGUAGE sql SECURITY DEFINER AS
$f$ UPDATE public.push_token_rebind_epoch SET applied_at = now() - interval '1 day' $f$;
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
-- `LIKE '%search_path=%'` would pass for search_path=public, so assert the value.
SELECT ok((SELECT p.prosecdef AND p.proconfig @> ARRAY['search_path=""'] AND (p.prorettype::regtype)::text = 'jsonb'
             FROM pg_proc p WHERE p.oid = 'public.register_push_token(text,text,text,text)'::regprocedure),
  'A5: SECURITY DEFINER, search_path pinned to EMPTY, returns jsonb');
SELECT has_column('public'::name, 'push_tokens'::name, 'device_secret_hash'::name, 'A6: the proof column exists');
SELECT has_table('public'::name, 'push_token_rebind_epoch'::name, 'A7: the epoch table exists');
SELECT ok(has_function_privilege('service_role', 'public.unbind_push_token(text)', 'EXECUTE'),
  'A8: service_role may unbind (support recovery for a squatted token)');
SELECT ok(NOT has_function_privilege('authenticated', 'public.unbind_push_token(text)', 'EXECUTE'),
  'A9: authenticated may NOT unbind');
-- 128's headline claim, previously asserted nowhere.
SELECT ok(NOT has_function_privilege('authenticated', 'notify.register_push_token(text,text,text,text)', 'EXECUTE'),
  'A10: the insecure notify verb is REVOKED from authenticated — the claim is enforced, not left to a setting');

-- The epoch is the ONLY thing making rule 5 transitional. A table created in
-- `public` inherits the default ACL granting anon/authenticated DML, and `public`
-- is PostgREST-exposed — so without an explicit REVOKE this gate was writable
-- with the anon key, which restores V2 entirely. These two assertions are the
-- ones whose absence let that ship.
SELECT ok((SELECT NOT has_table_privilege('authenticated','public.push_token_rebind_epoch', priv)
             FROM unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE']) priv
            ORDER BY 1 LIMIT 1) IS NOT FALSE
          AND NOT has_table_privilege('authenticated','public.push_token_rebind_epoch','UPDATE')
          AND NOT has_table_privilege('authenticated','public.push_token_rebind_epoch','INSERT')
          AND NOT has_table_privilege('authenticated','public.push_token_rebind_epoch','DELETE')
          AND NOT has_table_privilege('anon','public.push_token_rebind_epoch','UPDATE')
          AND NOT has_table_privilege('anon','public.push_token_rebind_epoch','INSERT')
          AND NOT has_table_privilege('anon','public.push_token_rebind_epoch','DELETE'),
  'A11: the epoch table holds NO client DML — anon/authenticated cannot move the gate');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.push_token_rebind_epoch'::regclass),
  'A12: ...and RLS is enabled on it');

-- Third-review residuals, closed in the fold-in round. The proof column must not
-- be READABLE by a client (an unsalted hash of a client-chosen value is an
-- offline oracle), and the epoch row must not be MOVABLE by anyone — deleting it
-- and re-applying 128 would mint a new epoch and reopen rule 5 for 90 days.
SELECT ok(NOT has_table_privilege('authenticated','public.push_tokens','SELECT')
      AND NOT has_table_privilege('anon','public.push_tokens','SELECT'),
  'A13: push_tokens carries no table-level client SELECT (column-scoped instead)');
SELECT ok(has_column_privilege('authenticated','public.push_tokens','token','SELECT')
      AND has_column_privilege('authenticated','public.push_tokens','id','SELECT')
      AND NOT has_column_privilege('authenticated','public.push_tokens','device_secret_hash','SELECT')
      AND NOT has_column_privilege('anon','public.push_tokens','device_secret_hash','SELECT'),
  'A14: the client may read its row columns but NOT device_secret_hash');
SELECT has_trigger('public','push_token_rebind_epoch','trg_guard_push_token_rebind_epoch',
  'A15: the epoch table carries the immutability trigger');
SELECT throws_ok($$ DELETE FROM public.push_token_rebind_epoch $$, '42501',
  'push_token_rebind_epoch is immutable: moving or removing the epoch would reopen the legacy rebind path (128). Restore from the ledger instead.',
  'A16: the epoch row cannot be deleted — even as postgres');
SELECT throws_ok($$ UPDATE public.push_token_rebind_epoch SET applied_at = now() $$, '42501',
  'push_token_rebind_epoch is immutable: moving or removing the epoch would reopen the legacy rebind path (128). Restore from the ledger instead.',
  'A17: the epoch row cannot be moved — even as postgres');
SELECT is((SELECT count(*) FROM public.push_token_rebind_epoch), 1::bigint,
  'A18: exactly one epoch row exists');
-- ...and the same two facts observed as a REAL client, not from the catalog.
SELECT tap.login('11111111-1111-1111-1111-000000000195');
SELECT throws_ok($$ SELECT device_secret_hash FROM public.push_tokens $$, '42501',
  NULL, 'A19: a signed-in client selecting device_secret_hash is refused (permission denied for column)');
SELECT lives_ok($$ SELECT id, token, is_active FROM public.push_tokens $$,
  'A20: ...while its ordinary columns stay readable, so the shipped client (select id) survives');
-- D review G-2: the write guard lets an UNCHANGED hash through, so with a
-- table-level UPDATE `SET device_secret_hash = <guess>` succeeded exactly when
-- the guess was right — an online equality oracle on the secret. UPDATE is now
-- column-scoped; the refusal must come from the GRANT, for any value.
SELECT throws_ok($$ UPDATE public.push_tokens SET device_secret_hash = device_secret_hash $$, '42501',
  NULL, 'A21: a client cannot UPDATE device_secret_hash even to its current value — the equality oracle is closed by grant, not by the guard');
SELECT lives_ok($$ UPDATE public.push_tokens SET last_used = now(), is_active = true WHERE user_id = '11111111-1111-1111-1111-000000000195' $$,
  'A22: ...while the shipped client''s own writes (last_used, is_active) still work');
SELECT tap.logout();
SELECT ok(NOT has_table_privilege('authenticated','public.push_tokens','UPDATE')
      AND has_column_privilege('authenticated','public.push_tokens','last_used','UPDATE')
      AND has_column_privilege('authenticated','public.push_tokens','is_active','UPDATE')
      AND NOT has_column_privilege('authenticated','public.push_tokens','device_secret_hash','UPDATE')
      AND NOT has_column_privilege('authenticated','public.push_tokens','user_id','UPDATE')
      AND NOT has_column_privilege('authenticated','public.push_tokens','token','UPDATE'),
  'A23: UPDATE is column-scoped — last_used/is_active/platform/device_name only; never the hash, the owner, or the token');

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
SELECT is(current_setting('app.push_token_verb', true), '',
  'B8: the write-guard bypass is disarmed before the verb returns (pg_graphql runs a multi-field mutation in one transaction)');
-- §17.24 heal — independent review finding F1. Valid state, produced the way
-- production produces it: a provider DeviceNotRegistered leaves the row with a
-- provider error and the identity push-unreachable; notify.enqueue then
-- suppresses EVERY push. Registration must heal both, as the legacy verb did.
SELECT tap.logout();
UPDATE public.push_tokens SET last_provider_error = 'DeviceNotRegistered' WHERE token = tap._f195('tok');
INSERT INTO notify.identity_channel_state (identity_id, channel, state, since, reason)
VALUES (tap.buyer(), 'push', 'unreachable', now(), 'device_not_registered')
ON CONFLICT (identity_id, channel) DO UPDATE SET state = 'unreachable', reason = 'device_not_registered';
SELECT tap.login(tap.buyer());
SELECT is((public.register_push_token(tap._f195('tok'), 'ios', tap._f195('sec'), 'iPhone') ->> 'outcome'), 'refreshed',
  'B9: the owner re-registers after a provider failure');
SELECT tap.logout();
SELECT is((SELECT last_provider_error FROM public.push_tokens WHERE token = tap._f195('tok')), NULL,
  'B10 (§17.24): ...the provider error is cleared');
SELECT is((SELECT state FROM notify.identity_channel_state WHERE identity_id = tap.buyer() AND channel = 'push'), 'ok',
  'B11 (§17.24): ...and the identity''s push channel is healed to ok — without this every later push, mandatory included, is suppressed');
SELECT tap.login(tap.buyer());

-- ── C. UNAUTHORIZED CAPTURE ─────────────────────────────────────────────────
SELECT tap.login(tap.other_user());
SELECT is(left(tap._try195(tap._f195('bad')), 5), '42501',
  'C1: knowing the token but not the secret is refused');
SELECT is(tap._owner195(), tap.buyer(), 'C2: ...the victim''s binding is untouched');
SELECT ok(tap._active195(), 'C3: ...still active and unrevoked — nothing was written');
SELECT is(tap._try195(tap._f195('nea')), tap._try195(tap._f195('bad')),
  'C4: a near-miss secret and a wild guess return the IDENTICAL error — no oracle');

-- ── D. ACCOUNT SWITCHING on the same device ─────────────────────────────────
-- [135, contract v3] presenting the device secret no longer rebinds by itself: every ownership change
-- must be proven through the push provider (202 covers the confirm). The verb answers challenge_required
-- and the row stays the owner's until then.
SELECT tap._login195s(tap.other_user());
SELECT is((public.register_push_token(tap._f195('tok'), 'ios', tap._f195('sec'), 'iPhone') ->> 'outcome'),
  'challenge_required', 'D1 (under 135): presenting the device secret from another account starts a possession challenge, not a rebind');
SELECT is(tap._owner195(), tap.buyer(), 'D2 (under 135): ...the token still belongs to its owner until the challenge is confirmed');
SELECT is(tap._rows195(), 1, 'D3: ...still exactly one row; the client never fights UNIQUE(token)');

-- ── E. ORDINARY SIGN-OUT ────────────────────────────────────────────────────
-- A binding that HAS a proof stays protected after sign-out: the secret decides.
SELECT tap._mkrow195(tap.buyer(), tap._h195(tap._f195('sec')), false, 'signed_out', interval '1 hour', interval '90 days');
SELECT tap.login(tap.other_user());
SELECT is(left(tap._try195(tap._f195('bad')), 5), '42501',
  'E1: a signed-out binding that HAS a hash is still not claimable without the secret');
-- A pre-epoch binding with no proof, signed out recently, is the handover case.
SELECT tap._mkrow195(tap.buyer(), NULL, false, 'signed_out', interval '1 hour', interval '90 days');
SELECT tap._login195s(tap.other_user());
SELECT is((public.register_push_token(tap._f195('tok'), 'ios', tap._f195('sec'), 'iPhone') ->> 'outcome'),
  'challenge_required', 'E2 (under 135): a pre-epoch hash-less binding, signed out recently, is claimable only by proof — a challenge, not rebound_legacy');
-- ONE spelling. 'signed_out' is what notify.revoke_push_token writes and the only
-- server writer there is; a second accepted value only a client can author would
-- be surface for nothing.
SELECT tap._mkrow195(tap.buyer(), NULL, false, 'sign_out', interval '1 hour', interval '90 days');
SELECT is((public.register_push_token(tap._f195('tok'), 'ios', tap._f195('sec'), 'iPhone') ->> 'outcome'),
  'challenge_required', 'E3 (under 135): the client-only ''sign_out'' spelling grants nothing — the same possession challenge as any foreign row, never a bind');

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

-- The sunset: without it, revoked_at is re-armed by every sign-out and the
-- pre-128 cohort never shrinks, so "transitional" would be untrue forever.
-- Ageing the epoch is exactly the write trg_guard_push_token_rebind_epoch
-- exists to refuse (A15–A17), so the sunset can only be exercised by the
-- deliberate act the guard demands of an operator: the trigger is disabled for
-- these two statements only, as postgres, inside this rolled-back transaction.
SELECT tap.logout();
ALTER TABLE public.push_token_rebind_epoch DISABLE TRIGGER trg_guard_push_token_rebind_epoch;
SELECT tap._agee195();
SELECT tap._mkrow195(tap.buyer(), NULL, false, 'signed_out', interval '1 hour', interval '200 days');
SELECT is(left(tap._try195(tap._f195('sec')), 5), '42501',
  'G4: past the 90-day sunset the legacy path is closed for good');
SELECT tap._resete195();
ALTER TABLE public.push_token_rebind_epoch ENABLE TRIGGER trg_guard_push_token_rebind_epoch;

-- ── H. LOST LOCAL SECRET ────────────────────────────────────────────────────
SELECT tap._mkrow195(tap.buyer(), tap._h195(tap._f195('sec')), true, NULL, NULL, interval '1 day');
SELECT tap.login(tap.buyer());
SELECT is((public.register_push_token(tap._f195('tok'), 'ios', tap._f195('bad'), 'iPhone') ->> 'outcome'),
  'refreshed', 'H1: an owner presenting a new secret is refreshed (the reply cannot reveal the mismatch)');
SELECT is(tap._hash195(), tap._h195(tap._f195('sec')), 'H2: ...and the stored hash is still the original');
-- [135] a client DELETE under RLS is now a revoke with history (the row stays, tombstoned), so recovery is simply
-- register again: the owner's row is re-activated (`refreshed`). The stored proof no longer decides ownership
-- (every cross-account bind is a possession challenge, 202), so a stale stored hash after a lost local secret is
-- harmless to the owner and grants nothing to anyone else.
DELETE FROM public.push_tokens WHERE token = tap._f195('tok');
SELECT is((public.register_push_token(tap._f195('tok'), 'ios', tap._f195('bad'), 'iPhone') ->> 'outcome'),
  'refreshed', 'H3 (under 135): a client delete is a revoke, not a removal; recovery is register → refreshed — never rotation, never a fresh registered');

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
-- Sign-out must keep working. The shipped client signs out through the server
-- verb notify.revoke_push_token (src/lib/auth/signOut.ts), which is the ONLY
-- writer of revoked_at/revoked_reason — and since the fold-in those two columns
-- are outside the client's column-scoped UPDATE on purpose (a client that could
-- write revoked_reason = 'signed_out' could forge rule 5's precondition on its
-- own row). So this exercises the real path, not a direct UPDATE.
SELECT is((notify.revoke_push_token(tap._f195('tok')) ->> 'revoked'), '1',
  'I3: the client CAN still revoke its own binding through the server verb — sign-out is unaffected');
SELECT ok(NOT tap._active195(), 'I4: ...and the binding is inactive afterwards');
SELECT throws_ok(
  format('UPDATE public.push_tokens SET revoked_reason = %L WHERE token = %L', 'signed_out', tap._f195('tok')),
  '42501', NULL, 'I5: ...while a DIRECT client write of revoked_reason is refused — rule 5''s precondition cannot be forged');
SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;

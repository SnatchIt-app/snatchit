-- 202_push_token_proof_of_possession.sql — pgTAP for migration 135 (b2, contract v3).
-- Negative control: on the stack without 135 the shape section fails and the cross-account
-- case answers 42501 "bound to another account" (128/131) instead of challenge_required.
-- Helpers mirror 198 (sessions with session_id claims). The nonce is recovered in-test by
-- planting a KNOWN nonce hash on the challenge row as postgres (the harness's pg_net stub does not
-- expose the dispatched body), which is exactly the state the issue verb produces; the verb's
-- randomness is asserted separately (two issues differ). Memo helpers are SECURITY DEFINER so they
-- work while the test is logged in as authenticated (197's pattern).
BEGIN;
SELECT plan(57);
SELECT tap.seed_core();

CREATE TABLE tap.kv202 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._s202(k text, v text) RETURNS void LANGUAGE sql SECURITY DEFINER AS $$ INSERT INTO tap.kv202 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v $$;
CREATE FUNCTION tap._g202(k text) RETURNS text LANGUAGE sql SECURITY DEFINER AS $$ SELECT v FROM tap.kv202 WHERE kv202.k = _g202.k $$;
CREATE FUNCTION tap._u202(k text) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS $$ SELECT v::uuid FROM tap.kv202 WHERE kv202.k = _u202.k $$;
CREATE FUNCTION tap._sess202(p_uid uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid := gen_random_uuid();
BEGIN INSERT INTO auth.sessions (id, user_id, created_at, updated_at, aal) VALUES (v, p_uid, clock_timestamp(), clock_timestamp(), 'aal1'); RETURN v; END $$;
CREATE FUNCTION tap._login202(p_uid uuid, p_sid uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN PERFORM tap.login(p_uid);
  PERFORM set_config('request.jwt.claims', (coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb || jsonb_build_object('session_id', p_sid::text))::text, true); END $$;
CREATE FUNCTION tap._h202(s text) RETURNS text LANGUAGE sql IMMUTABLE AS $$ SELECT encode(pg_catalog.sha256(pg_catalog.convert_to(s, 'utf8')), 'hex') $$;
CREATE FUNCTION tap._row202(t text) RETURNS public.push_tokens LANGUAGE sql AS $$ SELECT * FROM public.push_tokens WHERE token = t $$;
CREATE FUNCTION tap._try202(stmt text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE stmt; RETURN 'ok'; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE || ' ' || SQLERRM; END $$;
-- plant a known nonce on the caller's open challenge (as postgres); returns the challenge id
CREATE FUNCTION tap._plant202(p_token text, p_uid uuid, p_nonce text) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v uuid;
BEGIN
  UPDATE notify.push_token_challenges c SET nonce_hash = tap._h202(p_nonce)
   WHERE c.token_id = (SELECT id FROM public.push_tokens WHERE token = p_token) AND c.requesting_user = p_uid AND c.consumed_at IS NULL
   RETURNING c.id INTO v;
  RETURN v;
END $$;

-- ── A. shape and grants ─────────────────────────────────────────────────────
SELECT has_table('notify', 'push_token_challenges', 'A1: the pending-claim table exists (notify)');
SELECT ok(NOT has_table_privilege('authenticated', 'notify.push_token_challenges', 'SELECT')
      AND NOT has_table_privilege('anon', 'notify.push_token_challenges', 'SELECT')
      AND NOT has_table_privilege('service_role', 'notify.push_token_challenges', 'SELECT')
      AND has_function_privilege('service_role', 'notify.get_push_token_challenge(uuid)', 'execute')
      AND NOT has_function_privilege('authenticated', 'notify.get_push_token_challenge(uuid)', 'execute'), 'A2: no table grants at all (notify discipline); send-push reads through get_push_token_challenge (service_role)');
SELECT ok(has_function_privilege('authenticated', 'public.confirm_push_token_challenge(uuid, text)', 'execute')
      AND has_function_privilege('authenticated', 'public.request_push_token_challenge(text, text, text)', 'execute')
      AND NOT has_function_privilege('anon', 'public.confirm_push_token_challenge(uuid, text)', 'execute'), 'A3: the two client verbs — authenticated only');
SELECT ok(NOT has_function_privilege('authenticated', 'notify.issue_push_token_challenge(uuid, uuid, uuid, text, text, text, text)', 'execute')
      AND NOT has_function_privilege('service_role', 'notify.issue_push_token_challenge(uuid, uuid, uuid, text, text, text, text)', 'execute'), 'A4: issue is internal');
SELECT ok(has_function_privilege('service_role', 'notify.record_push_token_challenge_delivery(uuid, text, text, text)', 'execute')
      AND NOT has_function_privilege('authenticated', 'notify.record_push_token_challenge_delivery(uuid, text, text, text)', 'execute'), 'A5: delivery recording — service_role only');
SELECT has_trigger('public', 'push_tokens', 'trg_guard_push_token_client_delete', 'A6: the client-DELETE tombstone trigger exists');
SELECT is((SELECT count(*)::int FROM notify.notification_type WHERE type_key = 'security_device_rebound' AND allowed_channels = '{}'::text[]), 1, 'A7: the previous-owner notice type exists with NO push/email channel (in-app only, never push)');
SELECT is((SELECT count(*)::int FROM notify.template WHERE template_key = 'security_device_rebound' AND channel = 'in_app' AND locale = 'en-US'), 1, 'A7b: ...and an en-US in_app template (the centre can always render it)');

-- ── B. unchanged paths stamp contract_version 2 (D, V3-1) ───────────────────
SELECT tap._s202('SB', tap._sess202(tap.buyer())::text);
SELECT tap._login202(tap.buyer(), tap._u202('SB'));
SELECT is((public.register_push_token('ExponentPushToken[202-buyer-aaaaaaaaaaaa]', 'ios', 'secret-202-buyer-0123456789', 'iPhone') ->> 'outcome'), 'registered', 'B1: no history → registered');
SELECT is((public.register_push_token('ExponentPushToken[202-buyer-aaaaaaaaaaaa]', 'ios', 'secret-202-buyer-0123456789', 'iPhone') ->> 'contract_version'), '2', 'B2: refreshed stamps contract_version 2 (the shipped v2 client keeps working)');
SELECT tap.logout();
SELECT is((tap._row202('ExponentPushToken[202-buyer-aaaaaaaaaaaa]')).device_secret_hash, tap._h202('secret-202-buyer-0123456789'), 'B3: the registering device''s proof is stored');

-- ── C. a cross-account bind is a CHALLENGE; nothing changes on the live row (C1, C4) ──
SELECT tap._s202('SO', tap._sess202(tap.other_user())::text);
SELECT tap._login202(tap.other_user(), tap._u202('SO'));
SELECT tap._s202('C1', public.register_push_token('ExponentPushToken[202-buyer-aaaaaaaaaaaa]', 'ios', 'secret-202-other-0123456789', 'Pixel')::text);
SELECT is(tap._g202('C1')::jsonb ->> 'outcome', 'challenge_required', 'C1: another account registering the buyer''s token gets challenge_required (rule 3 with a matching hash is gone too)');
SELECT is(tap._g202('C1')::jsonb ->> 'contract_version', '3', 'C2: a challenge reply stamps contract_version 3');
SELECT is(tap._g202('C1')::jsonb -> 'challenge' ->> 'mode', 'silent', 'C3: the first challenge is silent');
SELECT tap.logout();
SELECT ok((tap._row202('ExponentPushToken[202-buyer-aaaaaaaaaaaa]')).user_id = tap.buyer() AND (tap._row202('ExponentPushToken[202-buyer-aaaaaaaaaaaa]')).is_active
      AND (tap._row202('ExponentPushToken[202-buyer-aaaaaaaaaaaa]')).device_secret_hash = tap._h202('secret-202-buyer-0123456789'),
  'C4: the buyer''s row is untouched — still the buyer''s, active, with the buyer''s proof (a claim is not a denial)');
SELECT is((SELECT count(*)::int FROM notify.push_token_challenges c WHERE c.requesting_user = tap.other_user() AND c.consumed_at IS NULL), 1, 'C5: exactly one open challenge for (token, requester)');
SELECT ok((SELECT length(c.nonce_hash) = 64 AND c.secret_hash = tap._h202('secret-202-other-0123456789') AND c.requesting_session = tap._u202('SO') AND c.expires_at > now()
            FROM notify.push_token_challenges c WHERE c.requesting_user = tap.other_user() AND c.consumed_at IS NULL),
  'C6: the challenge carries only the nonce HASH, the requester''s secret hash, and the requesting session');
SELECT tap._s202('H1', (SELECT nonce_hash FROM notify.push_token_challenges WHERE requesting_user = tap.other_user() AND consumed_at IS NULL));
SELECT tap._login202(tap.other_user(), tap._u202('SO'));
SELECT tap._s202('C7', public.register_push_token('ExponentPushToken[202-buyer-aaaaaaaaaaaa]', 'ios', 'secret-202-other-0123456789', 'Pixel')::text);
SELECT tap.logout();
SELECT ok((SELECT count(*) = 1 AND bool_and(nonce_hash <> tap._g202('H1')) FROM notify.push_token_challenges WHERE requesting_user = tap.other_user() AND consumed_at IS NULL),
  'C7: a re-request re-issues the nonce on the SAME open row (still one row; the hash changed — CSPRNG)');

-- ── C′. a stale echo (a push from before a re-issue) is free: no attempt, no bind ──
SELECT tap._s202('CS', tap._plant202('ExponentPushToken[202-buyer-aaaaaaaaaaaa]', tap.other_user(), 'nonce-202-stale-value')::text);
SELECT tap._login202(tap.other_user(), tap._u202('SO'));
SELECT tap._s202('C8', public.register_push_token('ExponentPushToken[202-buyer-aaaaaaaaaaaa]', 'ios', 'secret-202-other-0123456789', 'Pixel')::text);   -- re-issue: the planted nonce becomes prev
SELECT is((public.confirm_push_token_challenge(tap._u202('CS'), 'nonce-202-stale-value') ->> 'outcome'), 'stale_nonce', 'C8: echoing the superseded nonce answers stale_nonce');
SELECT tap.logout();
SELECT is((SELECT attempts FROM notify.push_token_challenges WHERE id = tap._u202('CS')), 0, 'C9: ...and costs no attempt (the client waits for the current push)');

-- ── D. confirm: wrong session, wrong nonce, attempts, the fifth consumes ─────
SELECT tap._s202('CH', tap._plant202('ExponentPushToken[202-buyer-aaaaaaaaaaaa]', tap.other_user(), 'nonce-202-known-value')::text);
SELECT tap._s202('SO2', tap._sess202(tap.other_user())::text);            -- a second session of the same user
SELECT tap._login202(tap.other_user(), tap._u202('SO2'));
SELECT throws_ok(format($$ SELECT public.confirm_push_token_challenge(%L::uuid, 'nonce-202-known-value') $$, tap._g202('CH')),
  '42501', 'insufficient_privilege: challenge belongs to another session', 'D1: the right user from a DIFFERENT session cannot confirm (C3)');
SELECT tap.logout();
SELECT tap._login202(tap.buyer(), tap._u202('SB'));
SELECT throws_ok(format($$ SELECT public.confirm_push_token_challenge(%L::uuid, 'nonce-202-known-value') $$, tap._g202('CH')),
  '42501', 'insufficient_privilege: challenge belongs to another session', 'D2: another user cannot confirm');
SELECT tap.logout();
SELECT tap._login202(tap.other_user(), tap._u202('SO'));
SELECT is((public.confirm_push_token_challenge(tap._u202('CH'), 'wrong-1') ->> 'outcome') || '|' || (public.confirm_push_token_challenge(tap._u202('CH'), 'wrong-2') ->> 'attempts_left'),
  'nonce_mismatch|3', 'D3: a wrong nonce RETURNS nonce_mismatch and the attempt count persists (2 used, 3 left)');
SELECT tap.logout();
SELECT ok((tap._row202('ExponentPushToken[202-buyer-aaaaaaaaaaaa]')).user_id = tap.buyer(), 'D4: two wrong attempts changed nothing on the row');
SELECT tap._login202(tap.other_user(), tap._u202('SO'));
SELECT is((SELECT (public.confirm_push_token_challenge(tap._u202('CH'), 'wrong-3') ->> 'outcome')), 'nonce_mismatch', 'D5: third wrong');
SELECT is((SELECT (public.confirm_push_token_challenge(tap._u202('CH'), 'wrong-4') ->> 'attempts_left')), '1', 'D6: fourth wrong → 1 left');
SELECT is((SELECT (public.confirm_push_token_challenge(tap._u202('CH'), 'wrong-5') ->> 'outcome')), 'challenge_consumed', 'D7: the fifth wrong consumes the challenge');
SELECT throws_ok(format($$ SELECT public.confirm_push_token_challenge(%L::uuid, 'nonce-202-known-value') $$, tap._g202('CH')),
  'P0001', 'precondition_failed: challenge consumed', 'D8: the right nonce after consumption is refused');
-- P3-1 (D): a re-request after exhaustion issues a FRESH challenge (the requester's 3-per-(token,user) allowance is
-- already spent by C1/C7/C8 — a real limit, tested in H — so reset it here as postgres before the re-request)
SELECT tap.logout();
DELETE FROM public.rate_limits WHERE user_id = tap.other_user() AND action LIKE 'push_challenge%';
SELECT tap._login202(tap.other_user(), tap._u202('SO'));
SELECT tap._s202('C9', public.register_push_token('ExponentPushToken[202-buyer-aaaaaaaaaaaa]', 'ios', 'secret-202-other-0123456789', 'Pixel')::text);
SELECT tap.logout();
SELECT ok((tap._g202('C9')::jsonb ->> 'outcome') = 'challenge_required' AND (tap._g202('C9')::jsonb -> 'challenge' ->> 'id') <> tap._g202('CH'),
  'D9: after exhaustion a new request gets a NEW challenge (P3-1), not the dead one');
SELECT is((SELECT count(*)::int FROM notify.push_token_challenges WHERE requesting_user = tap.other_user() AND consumed_at IS NULL), 1, 'D10: exactly one open challenge again');

-- ── E. confirm with the right nonce = the atomic bind (C5), previous owner notified by email ──
SELECT tap._s202('CH2', tap._plant202('ExponentPushToken[202-buyer-aaaaaaaaaaaa]', tap.other_user(), 'nonce-202-second-value')::text);
SELECT tap._login202(tap.other_user(), tap._u202('SO'));
SELECT is((public.confirm_push_token_challenge(tap._u202('CH2'), 'nonce-202-second-value') ->> 'outcome'), 'rebound', 'E1: the right nonce from the requesting session binds → rebound');
SELECT tap.logout();
SELECT ok((tap._row202('ExponentPushToken[202-buyer-aaaaaaaaaaaa]')).user_id = tap.other_user()
      AND (tap._row202('ExponentPushToken[202-buyer-aaaaaaaaaaaa]')).is_active
      AND (tap._row202('ExponentPushToken[202-buyer-aaaaaaaaaaaa]')).device_secret_hash = tap._h202('secret-202-other-0123456789')
      AND (tap._row202('ExponentPushToken[202-buyer-aaaaaaaaaaaa]')).session_id = tap._u202('SO'),
  'E2: the row is the requester''s, active, with the PROVING device''s proof superseding the old one (C5), stamped with the requesting session');
SELECT is((SELECT count(*)::int FROM notify.notification n WHERE n.recipient_id = tap.buyer() AND n.type_key = 'security_device_rebound'), 1, 'E3: the previous owner has one security_device_rebound notice queued');
SELECT is((SELECT count(*)::int FROM notify.push_token_challenges WHERE id = tap._u202('CH2') AND confirmed_at IS NOT NULL AND consumed_at IS NOT NULL), 1, 'E4: the challenge is confirmed and consumed');
SELECT tap._login202(tap.other_user(), tap._u202('SO'));
SELECT throws_ok(format($$ SELECT public.confirm_push_token_challenge(%L::uuid, 'nonce-202-second-value') $$, tap._g202('CH2')),
  'P0001', 'precondition_failed: challenge consumed', 'E5: a replayed confirm is refused');
SELECT tap.logout();
-- the victim's device takes it back by proof (the completed-redirect case, closed)
SELECT tap._login202(tap.buyer(), tap._u202('SB'));
SELECT is((public.register_push_token('ExponentPushToken[202-buyer-aaaaaaaaaaaa]', 'ios', 'secret-202-buyer-0123456789', 'iPhone') ->> 'outcome'), 'challenge_required', 'E6: the previous owner''s device now gets a challenge (proof, not the stored secret, decides)');
SELECT tap.logout();
SELECT tap._s202('CH3', tap._plant202('ExponentPushToken[202-buyer-aaaaaaaaaaaa]', tap.buyer(), 'nonce-202-third-value')::text);
SELECT tap._login202(tap.buyer(), tap._u202('SB'));
SELECT is((public.confirm_push_token_challenge(tap._u202('CH3'), 'nonce-202-third-value') ->> 'outcome'), 'rebound', 'E7: ...and takes the binding back by proof (C5 — the completed redirect is reversible by the device)');
SELECT tap.logout();
SELECT ok((tap._row202('ExponentPushToken[202-buyer-aaaaaaaaaaaa]')).user_id = tap.buyer(), 'E8: the row is the buyer''s again');

-- ── F. the fallback verb (visible code, with the device secret) ─────────────
-- sections C–E used the requester's 3-per-(token,user) allowance (a real limit, tested in H); reset it as postgres
DELETE FROM public.rate_limits WHERE user_id = tap.other_user() AND action LIKE 'push_challenge%';
SELECT tap._login202(tap.other_user(), tap._u202('SO'));
SELECT tap._s202('F1', public.request_push_token_challenge('ExponentPushToken[202-buyer-aaaaaaaaaaaa]', 'secret-202-other-0123456789', 'visible')::text);
SELECT is(tap._g202('F1')::jsonb -> 'challenge' ->> 'mode', 'visible', 'F1: the fallback issues a visible-code challenge');
SELECT throws_ok($$ SELECT public.request_push_token_challenge('ExponentPushToken[202-nonexistent-zzzz]', 'secret-202-other-0123456789', 'visible') $$,
  'P0001', 'precondition_failed: no binding to challenge — register instead', 'F2: no row → register instead');
SELECT tap.logout();
SELECT ok((SELECT c.secret_hash = tap._h202('secret-202-other-0123456789') AND c.mode = 'visible' FROM notify.push_token_challenges c WHERE c.requesting_user = tap.other_user() AND c.consumed_at IS NULL),
  'F3: the visible challenge carries the requester''s secret hash (V3-3) — a confirm always stores a proof');
SELECT tap._login202(tap.buyer(), tap._u202('SB'));
SELECT throws_ok($$ SELECT public.request_push_token_challenge('ExponentPushToken[202-buyer-aaaaaaaaaaaa]', 'secret-202-buyer-0123456789', 'visible') $$,
  'P0001', 'precondition_failed: the caller already owns this binding — register instead', 'F4: the owner cannot challenge their own row');
SELECT tap.logout();

-- ── G. client DELETE → revoke with history (C2) ─────────────────────────────
SELECT tap._login202(tap.buyer(), tap._u202('SB'));
DELETE FROM public.push_tokens WHERE token = 'ExponentPushToken[202-buyer-aaaaaaaaaaaa]';
SELECT tap.logout();
SELECT ok((tap._row202('ExponentPushToken[202-buyer-aaaaaaaaaaaa]')).id IS NOT NULL
      AND NOT (tap._row202('ExponentPushToken[202-buyer-aaaaaaaaaaaa]')).is_active
      AND (tap._row202('ExponentPushToken[202-buyer-aaaaaaaaaaaa]')).revoked_reason = 'deleted_by_client'
      AND (tap._row202('ExponentPushToken[202-buyer-aaaaaaaaaaaa]')).device_secret_hash IS NOT NULL,
  'G1: a client DELETE leaves the row as a revoked tombstone with its proof (history survives)');
SELECT tap._login202(tap.other_user(), tap._u202('SO'));
SELECT is(left(tap._try202($$ INSERT INTO public.push_tokens (user_id, token, platform, is_active) VALUES (tap.other_user(), 'ExponentPushToken[202-buyer-aaaaaaaaaaaa]', 'android', true) $$), 5),
  '23505', 'G2: a client INSERT of a token with history is refused by the unique token (the tombstone holds it)');
SELECT is((public.register_push_token('ExponentPushToken[202-buyer-aaaaaaaaaaaa]', 'android', 'secret-202-other-0123456789', 'Pixel') ->> 'outcome'), 'challenge_required',
  'G3: ...and the verb answers challenge_required, never registered (route (1) closed)');
SELECT tap.logout();
-- a service path may still delete (unbind_push_token etc.)
SELECT lives_ok($$ DELETE FROM public.push_tokens WHERE token = 'ExponentPushToken[202-buyer-aaaaaaaaaaaa]' $$, 'G4: a non-client delete (postgres here) still removes the row');
SELECT is((SELECT count(*)::int FROM public.push_tokens WHERE token = 'ExponentPushToken[202-buyer-aaaaaaaaaaaa]'), 0, 'G5: ...gone, and its challenges cascade');

-- ── G′. support unbind tombstones (D, RB-1): the next binder must still prove ────
SELECT tap._login202(tap.buyer(), tap._u202('SB'));
SELECT is((public.register_push_token('ExponentPushToken[202-unbind-cccccccccccc]', 'ios', 'secret-202-buyer-0123456789', 'iPhone') ->> 'outcome'), 'registered', 'G6: fixture row for the support-unbind case');
SELECT tap.logout();
SELECT is((public.unbind_push_token('ExponentPushToken[202-unbind-cccccccccccc]') ->> 'unbound'), '1', 'G7: support unbind reports one binding unbound');
SELECT ok((tap._row202('ExponentPushToken[202-unbind-cccccccccccc]')).id IS NOT NULL
      AND NOT (tap._row202('ExponentPushToken[202-unbind-cccccccccccc]')).is_active
      AND (tap._row202('ExponentPushToken[202-unbind-cccccccccccc]')).device_secret_hash IS NULL
      AND (tap._row202('ExponentPushToken[202-unbind-cccccccccccc]')).revoked_reason = 'support_unbound',
  'G8: ...the row is KEPT as a revoked tombstone with the proof cleared (RB-1: support is not a bypass)');
SELECT tap._login202(tap.other_user(), tap._u202('SO'));
SELECT is((public.register_push_token('ExponentPushToken[202-unbind-cccccccccccc]', 'android', 'secret-202-other-0123456789', 'Pixel') ->> 'outcome'), 'challenge_required',
  'G9: after a support unbind another account still gets challenge_required, never registered');
SELECT tap.logout();

-- ── H. rate limits (per user, per (token, user)) ────────────────────────────
DELETE FROM public.rate_limits WHERE user_id = tap.other_user() AND action LIKE 'push_challenge%';   -- isolate: H2 measures the per-(token,user) limit alone
SELECT tap._login202(tap.buyer(), tap._u202('SB'));
SELECT is((public.register_push_token('ExponentPushToken[202-rl-bbbbbbbbbbbb]', 'ios', 'secret-202-buyer-0123456789', 'iPhone') ->> 'outcome'), 'registered', 'H1: fixture row for rate-limit tests');
SELECT tap.logout();
SELECT tap._login202(tap.other_user(), tap._u202('SO'));
SELECT tap._s202('H2', tap._try202($$ SELECT public.request_push_token_challenge('ExponentPushToken[202-rl-bbbbbbbbbbbb]', 'secret-202-other-0123456789', 'silent') $$)
                    || '|' || tap._try202($$ SELECT public.request_push_token_challenge('ExponentPushToken[202-rl-bbbbbbbbbbbb]', 'secret-202-other-0123456789', 'silent') $$)
                    || '|' || tap._try202($$ SELECT public.request_push_token_challenge('ExponentPushToken[202-rl-bbbbbbbbbbbb]', 'secret-202-other-0123456789', 'silent') $$)
                    || '|' || tap._try202($$ SELECT public.request_push_token_challenge('ExponentPushToken[202-rl-bbbbbbbbbbbb]', 'secret-202-other-0123456789', 'silent') $$));
SELECT tap.logout();
SELECT matches(tap._g202('H2'), '^ok\|ok\|ok\|P0001 precondition_failed: too many challenge requests$', 'H2: the fourth request for the same (token, user) inside 10 min is refused (3 per token per user)');

-- ── I. send-push''s verbs: read the challenge (token-addressed, no identity) and record delivery ──
SELECT ok((SELECT (j ? 'token') AND (j ? 'token_id') AND (j ? 'mode') AND (j ->> 'requesting_user') = tap.other_user()::text AND NOT (j ? 'user_id') AND NOT (j ? 'owner') AND NOT (j ? 'secret_hash') AND NOT (j ? 'nonce_hash') AND NOT (j ? 'prev_nonce_hash')
            FROM notify.get_push_token_challenge((SELECT id FROM notify.push_token_challenges WHERE requesting_user = tap.other_user() ORDER BY created_at DESC LIMIT 1)) j),
  'I0: get_push_token_challenge returns the token to address, token_id and the requester (for the edge''s ownership check), the state — and NO owner identity, secret or nonce hash');
SELECT is((notify.record_push_token_challenge_delivery((SELECT id FROM notify.push_token_challenges WHERE requesting_user = tap.other_user() ORDER BY created_at DESC LIMIT 1), 'sent', 'expo-ticket-1', null) ->> 'recorded'), 'true', 'I1: delivery outcome recorded on the challenge row');
SELECT is((notify.record_push_token_challenge_delivery(gen_random_uuid(), 'sent', null, null) ->> 'recorded'), 'false', 'I2: an unknown challenge records nothing');

-- ── J. 131 still holds through the new verbs ────────────────────────────────
SELECT tap.login(tap.other_user());                                      -- no session claim
SELECT throws_ok($$ SELECT public.request_push_token_challenge('ExponentPushToken[202-rl-bbbbbbbbbbbb]', 'secret-202-other-0123456789', 'visible') $$,
  '42501', 'insufficient_privilege: session predates a credential change', 'J1: a token without a session claim cannot request a challenge (fail closed)');
SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;

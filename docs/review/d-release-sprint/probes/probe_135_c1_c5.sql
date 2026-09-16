-- D: 135 @ b49a012 — the six proof-of-possession conditions (C1..C6), run against a FRESH replay of the
-- whole tree. BEGIN…ROLLBACK; every result SELECTed inline (a savepoint rollback would discard temp-table rows).
-- net.http_post is replaced by a RECORDING stub so the probe can read the nonce the real send-push would carry;
-- the stub is created inside the transaction and dies with it.
\set ON_ERROR_STOP 0
BEGIN;
-- no tap.seed_core(): this probe needs auth.users and push_tokens only, not the listing fixtures.

-- ── helpers ────────────────────────────────────────────────────────────────
CREATE FUNCTION pg_temp.u(i int) RETURNS uuid LANGUAGE sql AS $$ SELECT ('d1350000-0000-4000-8000-00000000000'||i)::uuid $$;
CREATE FUNCTION pg_temp.sess(p_uid uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid := gen_random_uuid(); BEGIN
  INSERT INTO auth.sessions (id, user_id, created_at, updated_at, aal)
  VALUES (v, p_uid, clock_timestamp() - interval '1 hour', clock_timestamp() - interval '1 hour', 'aal1'); RETURN v; END $$;
CREATE FUNCTION pg_temp.login(p_uid uuid, p_sid uuid) RETURNS void LANGUAGE plpgsql AS $$ BEGIN
  PERFORM tap.login(p_uid);
  PERFORM set_config('request.jwt.claims',
    (coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb
       || jsonb_build_object('session_id', p_sid::text))::text, true); END $$;
CREATE FUNCTION pg_temp.login_nosid(p_uid uuid) RETURNS void LANGUAGE plpgsql AS $$ BEGIN
  PERFORM tap.login(p_uid);
  PERFORM set_config('request.jwt.claims',
    ((current_setting('request.jwt.claims', true))::jsonb - 'session_id')::text, true); END $$;
CREATE FUNCTION pg_temp.try(q text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE r text; BEGIN EXECUTE q INTO r; RETURN coalesce(r, 'ok');
EXCEPTION WHEN others THEN RETURN 'ERR '||SQLSTATE||': '||left(SQLERRM, 90); END $$;
-- the live row's identity: everything a claim must not disturb
CREATE FUNCTION pg_temp.row_id(p_token text) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce((SELECT (SELECT email FROM auth.users WHERE id = t.user_id)
                          ||'|active='||t.is_active
                          ||'|hash='||coalesce(left(t.device_secret_hash, 8), '-')
                          ||'|reason='||coalesce(t.revoked_reason,'-')
                          ||'|sid='||coalesce(left(t.session_id::text, 8), '-')
                          ||'|plat='||t.platform
                          ||'|name='||coalesce(t.device_name,'-')
                     FROM public.push_tokens t WHERE t.token = p_token), 'absent') $$;
GRANT EXECUTE ON FUNCTION pg_temp.login(uuid,uuid), pg_temp.login_nosid(uuid), pg_temp.try(text),
                          pg_temp.row_id(text), pg_temp.u(int) TO authenticated, service_role;

-- recording stub for pg_net: capture what send-push would receive (the nonce lives ONLY here)
CREATE TEMP TABLE net_posts (id bigserial, url text, body jsonb, at timestamptz default clock_timestamp());
GRANT SELECT ON net_posts TO authenticated, service_role;
-- the harness ships net.http_post(url text, headers jsonb, body jsonb) returning 1; replace it with a recorder
CREATE OR REPLACE FUNCTION net.http_post(url text, headers jsonb default '{}', body jsonb default '{}')
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE n bigint; BEGIN
  INSERT INTO net_posts (url, body) VALUES (url, body) RETURNING id INTO n; RETURN n; END $$;
-- 133's configured base URL (no Vault row ⇒ no post at all, and then no nonce to read)
INSERT INTO vault.decrypted_secrets (name, decrypted_secret) VALUES ('project_url', 'https://stub.local');

CREATE FUNCTION pg_temp.nonce_of(p_challenge uuid) RETURNS text LANGUAGE sql AS $$
  SELECT body->>'nonce' FROM net_posts WHERE (body->>'challenge_id')::uuid = p_challenge ORDER BY id DESC LIMIT 1 $$;
GRANT EXECUTE ON FUNCTION pg_temp.nonce_of(uuid) TO authenticated, service_role;

-- ── fixtures ───────────────────────────────────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES (pg_temp.u(1),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','owner@d135.local','h','{"provider":"email"}','{}',now(),now()),
       (pg_temp.u(2),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','claimer@d135.local','h','{"provider":"email"}','{}',now(),now()),
       (pg_temp.u(3),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','third@d135.local','h','{"provider":"email"}','{}',now(),now()),
       (pg_temp.u(4),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','prover@d135.local','h','{"provider":"email"}','{}',now(),now());
SELECT set_config('d.s1', pg_temp.sess(pg_temp.u(1))::text, false);
SELECT set_config('d.s2', pg_temp.sess(pg_temp.u(2))::text, false);
SELECT set_config('d.s2b', pg_temp.sess(pg_temp.u(2))::text, false);   -- u2's OTHER device/session
SELECT set_config('d.s3', pg_temp.sess(pg_temp.u(3))::text, false);
SELECT set_config('d.s4', pg_temp.sess(pg_temp.u(4))::text, false);
SELECT set_config('d.s4b', pg_temp.sess(pg_temp.u(4))::text, false);   -- u4's OTHER device/session

-- owner registers the device through the verb (the ordinary path)
SELECT pg_temp.login(pg_temp.u(1), current_setting('d.s1')::uuid);
SELECT 'F0.owner_registers', public.register_push_token('ExponentPushToken[d135-main]','ios','owner-secret-0000000000','Owner iPhone')::text;
SELECT tap.logout();
SELECT 'F0.row', pg_temp.row_id('ExponentPushToken[d135-main]');

-- ════════════════════════════════════════════════════════════════════════════
-- C1 — proof is required on EVERY ownership-changing bind
-- ════════════════════════════════════════════════════════════════════════════
SELECT pg_temp.login(pg_temp.u(2), current_setting('d.s2')::uuid);
SELECT 'C1a.cross_account_register', pg_temp.try($q$SELECT (public.register_push_token('ExponentPushToken[d135-main]','android','claimer-secret-000000000','Claimer Pixel') - 'challenge')::text$q$);
SELECT tap.logout();
SELECT 'C1a.row_unchanged', pg_temp.row_id('ExponentPushToken[d135-main]');

-- legacy: a pre-epoch row with NO stored proof (128 rule 5 used to hand this over on token knowledge alone)
SET LOCAL session_replication_role = replica;
INSERT INTO public.push_tokens (user_id, token, platform, is_active, created_at)
VALUES (pg_temp.u(1), 'ExponentPushToken[d135-legacy]', 'android', true,
        (SELECT applied_at FROM public.push_token_rebind_epoch) - interval '10 days');
SET LOCAL session_replication_role = origin;
SELECT pg_temp.login(pg_temp.u(2), current_setting('d.s2')::uuid);
SELECT 'C1b.legacy_no_hash', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[d135-legacy]','android','claimer-secret-000000000','x')->>'outcome'$q$);
SELECT tap.logout();
SELECT 'C1b.row_unchanged', pg_temp.row_id('ExponentPushToken[d135-legacy]');

-- a row the owner revoked (client delete path), and a support-unbound tombstone
SELECT pg_temp.login(pg_temp.u(1), current_setting('d.s1')::uuid);
SELECT 'F1.owner_registers_2', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[d135-rev]','ios','owner-secret-0000000000','Owner iPad')->>'outcome'$q$);
SELECT 'C2b.client_delete_rows_removed', pg_temp.try($q$WITH x AS (DELETE FROM public.push_tokens WHERE token = 'ExponentPushToken[d135-rev]' RETURNING 1) SELECT count(*)::text FROM x$q$);
SELECT tap.logout();
SELECT 'C2b.row_after_client_delete', pg_temp.row_id('ExponentPushToken[d135-rev]');
SELECT pg_temp.login(pg_temp.u(2), current_setting('d.s2')::uuid);
SELECT 'C1c.revoked_row', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[d135-rev]','android','claimer-secret-000000000','x')->>'outcome'$q$);
SELECT tap.logout();

SET LOCAL ROLE service_role;
SELECT 'C2g.unbind_is_tombstone', public.unbind_push_token('ExponentPushToken[d135-legacy]')::text;
RESET ROLE;
SELECT 'C2g.row_after_unbind', pg_temp.row_id('ExponentPushToken[d135-legacy]');
SELECT pg_temp.login(pg_temp.u(2), current_setting('d.s2')::uuid);
SELECT 'C1d.support_unbound_row', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[d135-legacy]','android','claimer-secret-000000000','x')->>'outcome'$q$);
-- no row at all: a first bind is still `registered` (there is no prior owner to prove anything to)
SELECT 'C1e.no_prior_row', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[d135-virgin]','android','claimer-secret-000000000','x')->>'outcome'$q$);
SELECT tap.logout();

-- ════════════════════════════════════════════════════════════════════════════
-- C2 — no bypass by writing the tables directly
-- ════════════════════════════════════════════════════════════════════════════
SELECT pg_temp.login(pg_temp.u(2), current_setting('d.s2')::uuid);
SELECT 'C2a.direct_insert_plant', pg_temp.try($q$WITH x AS (INSERT INTO public.push_tokens (user_id, token, platform, is_active) VALUES (auth.uid(), 'ExponentPushToken[d135-plant]', 'android', true) RETURNING 1) SELECT count(*)::text FROM x$q$);
SELECT 'C2d.direct_update_owner', pg_temp.try($q$WITH x AS (UPDATE public.push_tokens SET user_id = auth.uid() WHERE token = 'ExponentPushToken[d135-main]' RETURNING 1) SELECT count(*)::text FROM x$q$);
SELECT 'C2d.direct_update_hash', pg_temp.try($q$WITH x AS (UPDATE public.push_tokens SET device_secret_hash = 'deadbeef' WHERE token = 'ExponentPushToken[d135-main]' RETURNING 1) SELECT count(*)::text FROM x$q$);
SELECT 'C2e.select_challenges', pg_temp.try($q$SELECT count(*)::text FROM notify.push_token_challenges$q$);
SELECT 'C2e.insert_challenge', pg_temp.try($q$WITH x AS (INSERT INTO notify.push_token_challenges (token_id, requesting_user, requesting_session, nonce_hash, mode, secret_hash, platform, expires_at) VALUES ((SELECT id FROM public.push_tokens WHERE token='ExponentPushToken[d135-main]'), auth.uid(), current_setting('d.s2')::uuid, 'x', 'silent', 'x', 'android', now()+interval '5 min') RETURNING 1) SELECT count(*)::text FROM x$q$);
SELECT 'C2f.issue_verb_direct', pg_temp.try($q$SELECT notify.issue_push_token_challenge((SELECT id FROM public.push_tokens WHERE token='ExponentPushToken[d135-main]'), auth.uid(), current_setting('d.s2')::uuid, 'x', 'android', 'x', 'silent')::text$q$);
SELECT 'C2g.unbind_as_client', pg_temp.try($q$SELECT public.unbind_push_token('ExponentPushToken[d135-main]')::text$q$);
SELECT 'C2h.get_challenge_as_client', pg_temp.try($q$SELECT notify.get_push_token_challenge(gen_random_uuid())::text$q$);
SELECT 'C2i.record_delivery_as_client', pg_temp.try($q$SELECT notify.record_push_token_challenge_delivery(gen_random_uuid(),'sent',null,null)::text$q$);
SELECT tap.logout();

-- ════════════════════════════════════════════════════════════════════════════
-- C3 — confirmation is bound to the initiating user AND session
-- C4 — the pending claim never disturbs the live row
-- ════════════════════════════════════════════════════════════════════════════
SELECT 'C4.row_before_claim', pg_temp.row_id('ExponentPushToken[d135-main]');
SELECT pg_temp.login(pg_temp.u(4), current_setting('d.s4')::uuid);
SELECT set_config('d.ch', (public.register_push_token('ExponentPushToken[d135-main]','android','prover-secret-0000000000','Prover Pixel')->'challenge'->>'id'), false);
SELECT tap.logout();
SELECT 'C3.challenge_issued', current_setting('d.ch') IS NOT NULL;
SELECT 'C3.nonce_reached_only_the_post', (pg_temp.nonce_of(current_setting('d.ch')::uuid) IS NOT NULL)::text;
SELECT 'C4.row_after_claim', pg_temp.row_id('ExponentPushToken[d135-main]');
-- the nonce itself is nowhere in the challenge row (only its hash)
SELECT 'C4.nonce_not_stored', (NOT EXISTS (SELECT 1 FROM notify.push_token_challenges c
   WHERE c.id = current_setting('d.ch')::uuid
     AND (c.nonce_hash = pg_temp.nonce_of(current_setting('d.ch')::uuid)
          OR coalesce(c.delivery_error,'') LIKE '%'||pg_temp.nonce_of(current_setting('d.ch')::uuid)||'%')))::text;

-- a third account with the right nonce
SELECT pg_temp.login(pg_temp.u(3), current_setting('d.s3')::uuid);
SELECT 'C3a.other_user_confirms', pg_temp.try(format($q$SELECT public.confirm_push_token_challenge(%L::uuid, %L)->>'outcome'$q$, current_setting('d.ch'), pg_temp.nonce_of(current_setting('d.ch')::uuid)));
SELECT tap.logout();
-- the SAME account on its other session
SELECT pg_temp.login(pg_temp.u(4), current_setting('d.s4b')::uuid);
SELECT 'C3b.same_user_other_session', pg_temp.try(format($q$SELECT public.confirm_push_token_challenge(%L::uuid, %L)->>'outcome'$q$, current_setting('d.ch'), pg_temp.nonce_of(current_setting('d.ch')::uuid)));
SELECT tap.logout();
-- the same account with no session claim at all
SELECT pg_temp.login_nosid(pg_temp.u(4));
SELECT 'C3c.same_user_no_session', pg_temp.try(format($q$SELECT public.confirm_push_token_challenge(%L::uuid, %L)->>'outcome'$q$, current_setting('d.ch'), pg_temp.nonce_of(current_setting('d.ch')::uuid)));
SELECT tap.logout();
SELECT 'C4.row_after_foreign_confirms', pg_temp.row_id('ExponentPushToken[d135-main]');

-- wrong nonce four times: outcomes, and the row still untouched
SELECT pg_temp.login(pg_temp.u(4), current_setting('d.s4')::uuid);
SELECT 'C4.mismatch_1', pg_temp.try(format($q$SELECT public.confirm_push_token_challenge(%L::uuid, 'not-the-nonce')::text$q$, current_setting('d.ch')));
SELECT 'C4.mismatch_2', pg_temp.try(format($q$SELECT public.confirm_push_token_challenge(%L::uuid, 'not-the-nonce')::text$q$, current_setting('d.ch')));
SELECT 'C4.mismatch_3', pg_temp.try(format($q$SELECT public.confirm_push_token_challenge(%L::uuid, 'not-the-nonce')::text$q$, current_setting('d.ch')));
SELECT 'C4.mismatch_4', pg_temp.try(format($q$SELECT public.confirm_push_token_challenge(%L::uuid, 'not-the-nonce')::text$q$, current_setting('d.ch')));
SELECT tap.logout();
SELECT 'C4.row_after_4_mismatches', pg_temp.row_id('ExponentPushToken[d135-main]');
-- the CORRECT nonce still binds on attempt five (attempts are only spent by wrong answers)
SELECT pg_temp.login(pg_temp.u(4), current_setting('d.s4')::uuid);
SELECT 'C3d.correct_nonce_binds', pg_temp.try(format($q$SELECT public.confirm_push_token_challenge(%L::uuid, %L)->>'outcome'$q$, current_setting('d.ch'), pg_temp.nonce_of(current_setting('d.ch')::uuid)));
SELECT tap.logout();
SELECT 'C5.row_after_rebound', pg_temp.row_id('ExponentPushToken[d135-main]');

-- ════════════════════════════════════════════════════════════════════════════
-- C5 — the proof is superseded by the proving device's; the old one buys nothing
-- ════════════════════════════════════════════════════════════════════════════
SELECT 'C5.hash_is_claimers', (SELECT (device_secret_hash = encode(pg_catalog.sha256(convert_to('prover-secret-0000000000','utf8')),'hex'))::text
                                 FROM public.push_tokens WHERE token = 'ExponentPushToken[d135-main]');
SELECT 'C5.session_is_claimers', (SELECT (session_id = current_setting('d.s4')::uuid)::text
                                    FROM public.push_tokens WHERE token = 'ExponentPushToken[d135-main]');
SELECT pg_temp.login(pg_temp.u(1), current_setting('d.s1')::uuid);
SELECT 'C5.old_owner_with_old_secret', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[d135-main]','ios','owner-secret-0000000000','Owner iPhone')->>'outcome'$q$);
SELECT tap.logout();
SELECT 'C5.row_after_old_owner_try', pg_temp.row_id('ExponentPushToken[d135-main]');
-- the previous owner is told, in the notification centre and not by push
SELECT 'C5.prev_owner_notified', coalesce((SELECT n.type_key||'|title='||coalesce(n.title,'-')||'|dedupe='||coalesce(left(n.dedupe_key,28),'-')
    FROM notify.notification n WHERE n.recipient_id = pg_temp.u(1) AND n.type_key = 'security_device_rebound'
    ORDER BY n.created_at DESC LIMIT 1), 'none');
SELECT 'C5.new_owner_not_notified', (SELECT count(*)::text FROM notify.notification n
    WHERE n.recipient_id = pg_temp.u(4) AND n.type_key = 'security_device_rebound');
SELECT 'C5.rebound_type_channels', (SELECT allowed_channels::text||'|'||default_channels::text||'|'||delivery_class
    FROM notify.notification_type WHERE type_key = 'security_device_rebound');
SELECT 'C5.rebound_templates', (SELECT string_agg(channel, ',' ORDER BY channel) FROM notify.template WHERE template_key = 'security_device_rebound');

-- ════════════════════════════════════════════════════════════════════════════
-- C6 — rate limits on the challenge path
-- ════════════════════════════════════════════════════════════════════════════
SELECT pg_temp.login(pg_temp.u(3), current_setting('d.s3')::uuid);
SELECT 'C6.t1', pg_temp.try($q$SELECT public.request_push_token_challenge('ExponentPushToken[d135-main]','third-secret-00000000','visible')->>'outcome'$q$);
SELECT 'C6.t2', pg_temp.try($q$SELECT public.request_push_token_challenge('ExponentPushToken[d135-main]','third-secret-00000000','visible')->>'outcome'$q$);
SELECT 'C6.t3', pg_temp.try($q$SELECT public.request_push_token_challenge('ExponentPushToken[d135-main]','third-secret-00000000','visible')->>'outcome'$q$);
SELECT 'C6.t4_over_token_limit', pg_temp.try($q$SELECT public.request_push_token_challenge('ExponentPushToken[d135-main]','third-secret-00000000','visible')->>'outcome'$q$);
SELECT 'C6.own_row_refused', pg_temp.try($q$SELECT public.request_push_token_challenge('ExponentPushToken[d135-virgin]','third-secret-00000000','visible')->>'outcome'$q$);
SELECT 'C6.absent_row_refused', pg_temp.try($q$SELECT public.request_push_token_challenge('ExponentPushToken[d135-nothing-here]','third-secret-00000000','visible')->>'outcome'$q$);
SELECT tap.logout();
SELECT 'C6.posts_are_one_per_issue', (SELECT count(*)::text FROM net_posts);

-- ── the visible-mode nonce: shape, and the one input that makes it raise ─────
SELECT 'V1.visible_code_shape', (SELECT body->>'nonce' ~ '^[0-9]{6}$' FROM net_posts WHERE body->>'nonce' ~ '^[0-9]{6}$' LIMIT 1);
SELECT 'V1.abs_int_min', pg_temp.try($q$SELECT lpad((abs(('x' || '80000000')::bit(32)::int) % 1000000)::text, 6, '0')$q$);
SELECT 'V1.abs_int_min_neighbour', pg_temp.try($q$SELECT lpad((abs(('x' || '80000001')::bit(32)::int) % 1000000)::text, 6, '0')$q$);

-- ── C7: the fifth mismatch consumes; a superseded nonce is free; an expired one is refused ──
INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES (pg_temp.u(5),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','five@d135.local','h','{"provider":"email"}','{}',now(),now());
SELECT set_config('d.s5', pg_temp.sess(pg_temp.u(5))::text, false);
SELECT pg_temp.login(pg_temp.u(5), current_setting('d.s5')::uuid);
SELECT set_config('d.ch5', (public.register_push_token('ExponentPushToken[d135-rev]','android','five-secret-00000000000','Five')->'challenge'->>'id'), false);
SELECT 'C7.m1', pg_temp.try(format($q$SELECT public.confirm_push_token_challenge(%L::uuid,'x')->>'outcome'$q$, current_setting('d.ch5')));
SELECT 'C7.m2', pg_temp.try(format($q$SELECT public.confirm_push_token_challenge(%L::uuid,'x')->>'outcome'$q$, current_setting('d.ch5')));
SELECT 'C7.m3', pg_temp.try(format($q$SELECT public.confirm_push_token_challenge(%L::uuid,'x')->>'outcome'$q$, current_setting('d.ch5')));
SELECT 'C7.m4', pg_temp.try(format($q$SELECT public.confirm_push_token_challenge(%L::uuid,'x')->>'outcome'$q$, current_setting('d.ch5')));
SELECT 'C7.m5_consumes', pg_temp.try(format($q$SELECT public.confirm_push_token_challenge(%L::uuid,'x')::text$q$, current_setting('d.ch5')));
SELECT 'C7.correct_nonce_after_consumed', pg_temp.try(format($q$SELECT public.confirm_push_token_challenge(%L::uuid, %L)->>'outcome'$q$, current_setting('d.ch5'), pg_temp.nonce_of(current_setting('d.ch5')::uuid)));
SELECT tap.logout();
SELECT 'C7.row_after_exhaustion', pg_temp.row_id('ExponentPushToken[d135-rev]');
-- P3-1: a re-request on the exhausted challenge consumes it and issues a fresh one; the OLD nonce is then stale
SELECT pg_temp.login(pg_temp.u(5), current_setting('d.s5')::uuid);
SELECT set_config('d.old5', pg_temp.nonce_of(current_setting('d.ch5')::uuid), false);
SELECT set_config('d.ch5b', (public.request_push_token_challenge('ExponentPushToken[d135-rev]','five-secret-00000000000','visible')->'challenge'->>'id'), false);
SELECT 'C7.p3_1_fresh_challenge_is_new_row', (current_setting('d.ch5b') <> current_setting('d.ch5'))::text;
SELECT tap.logout();
SELECT 'C7.p3_1_old_row_consumed', (SELECT (consumed_at IS NOT NULL)::text FROM notify.push_token_challenges WHERE id = current_setting('d.ch5')::uuid);
SELECT pg_temp.login(pg_temp.u(5), current_setting('d.s5')::uuid);
-- a re-issue in place (same row) rotates the nonce and keeps the previous one for one generation
SELECT set_config('d.gen1', pg_temp.nonce_of(current_setting('d.ch5b')::uuid), false);
SELECT 'C7.reissue_same_row', (public.request_push_token_challenge('ExponentPushToken[d135-rev]','five-secret-00000000000','visible')->'challenge'->>'id' = current_setting('d.ch5b'))::text;
SELECT 'C7.nonce_rotated', (pg_temp.nonce_of(current_setting('d.ch5b')::uuid) <> current_setting('d.gen1'))::text;
SELECT 'C7.stale_echo_is_free', pg_temp.try(format($q$SELECT public.confirm_push_token_challenge(%L::uuid, %L)::text$q$, current_setting('d.ch5b'), current_setting('d.gen1')));
SELECT tap.logout();
SELECT 'C7.stale_costs_no_attempt', (SELECT attempts::text FROM notify.push_token_challenges WHERE id = current_setting('d.ch5b')::uuid);
-- expiry
UPDATE notify.push_token_challenges SET expires_at = now() - interval '1 second' WHERE id = current_setting('d.ch5b')::uuid;
SELECT pg_temp.login(pg_temp.u(5), current_setting('d.s5')::uuid);
SELECT 'C7.expired_refused', pg_temp.try(format($q$SELECT public.confirm_push_token_challenge(%L::uuid, %L)->>'outcome'$q$, current_setting('d.ch5b'), pg_temp.nonce_of(current_setting('d.ch5b')::uuid)));
SELECT tap.logout();
SELECT 'C7.row_after_all_of_that', pg_temp.row_id('ExponentPushToken[d135-rev]');

-- ── C2a follow-ups: what a direct client INSERT can and cannot plant ─────────
SELECT pg_temp.login(pg_temp.u(3), current_setting('d.s3')::uuid);
SELECT 'C2a2.plant_over_existing_token', pg_temp.try($q$WITH x AS (INSERT INTO public.push_tokens (user_id, token, platform, is_active) VALUES (auth.uid(), 'ExponentPushToken[d135-main]', 'android', true) RETURNING 1) SELECT count(*)::text FROM x$q$);
SELECT 'C2a3.plant_with_chosen_proof', pg_temp.try($q$WITH x AS (INSERT INTO public.push_tokens (user_id, token, platform, is_active, device_secret_hash) VALUES (auth.uid(), 'ExponentPushToken[d135-plant2]', 'android', true, 'aa00') RETURNING 1) SELECT count(*)::text FROM x$q$);
SELECT tap.logout();
SELECT 'C2a3.planted_row', pg_temp.row_id('ExponentPushToken[d135-plant2]');

-- ── what the challenge row exposes to send-push ──────────────────────────────
SELECT set_config('d.anych', (SELECT id::text FROM notify.push_token_challenges ORDER BY created_at DESC LIMIT 1), false);
SET LOCAL ROLE service_role;
SELECT 'X1.get_challenge_fields', (SELECT string_agg(k, ',' ORDER BY k)
    FROM jsonb_object_keys(notify.get_push_token_challenge(current_setting('d.anych')::uuid)) k);
SELECT 'X1b.no_owner_identity', (notify.get_push_token_challenge(current_setting('d.anych')::uuid) ? 'user_id'
                              OR notify.get_push_token_challenge(current_setting('d.anych')::uuid) ? 'secret_hash'
                              OR notify.get_push_token_challenge(current_setting('d.anych')::uuid) ? 'nonce_hash')::text;
SELECT 'X2.direct_table_read_as_service_role', pg_temp.try($q$SELECT count(*)::text FROM notify.push_token_challenges$q$);
RESET ROLE;
ROLLBACK;

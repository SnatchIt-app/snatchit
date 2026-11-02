-- ============================================================================
-- 271_primary_fee_read_alignment.sql — migration 20261102160000 (registry 202 / pgTAP 271, D).
--
-- Guarantee under test: every reader of catalog.platform_config 'fee.buyer_service_bps' accepts exactly the values
-- venue.create_primary_checkout quotes on (188): the NEWEST version only, a JSON number, an integer 0..10000.
--   public.get_primary_session(uuid)       prices a tier (buyer_fee_minor, all_in_price_minor) exactly when checkout
--                                           quotes, with checkout's numbers; otherwise both NULL (same keys).
--   catalog.publish_event(uuid,text,text)  goes on_sale exactly when checkout would quote; otherwise refuses with the
--                                           'precondition_failed: fee_policy_unset' prefix (null text unchanged).
-- Checkout itself is the reference and is not changed; it is called for real in every state below.
--
-- Fixture style: 258 (synthetic rows as postgres, the org made payable, the global ES256 key through the live 110
-- guard when no active global key exists, every rate a NEW VERSION of the append-only config row; everything dies
-- with the ROLLBACK). Ids are letter-bearing (a271fee0-…). Calls that may succeed go through tap._probe271, which
-- runs the call in a subtransaction, keeps its result and rolls it back, so one announced event and one hold serve
-- every state; tap._try271 runs a call for real. Neither aborts the file: a refusal comes back as {error, message}.
-- Plans are forced with SET LOCAL enable_* through tap helpers, with DISCARD PLANS before every plan-specific run
-- (plpgsql caches a statement's plan for the session; a GUC change alone does not re-plan it).
--
--   F   fixture (one assertion)
--   A   posture: SECURITY DEFINER, volatility, language, search_path='', owner, one overload, return type, the
--       EXECUTE posture of both functions (unchanged); 202's md5s; 202's COMMENT on get_primary_session.
--   C   the value matrix, newest version = 1000 (number), "1000" (string), null, 10.5, 10001, -1, 0, 10000, true,
--       and c10 = JSON null written directly over a valid 1000 (an explicit unset counts: no reader skips it to
--       price or publish on the version below, as checkout refuses on it).
--       K checkout's outcome in that state (the reference); R the read agrees with checkout (computed: checkout's
--       buyer_fee_minor / charge_total_minor when it quotes, both NULL when it refuses on the rate); P publish's
--       outcome (exact text); X1 publish accepts exactly when checkout quotes, over the whole matrix (computed).
--   L   plan independence. L1-L3 the forced plans are real and the old cast-in-an-ordered-LIMIT read raises 22P02
--       on the seq-scan plan with this history; L4 the 202 read's statement is a seq scan under the same settings;
--       then a valid newest over older non-numbers (L5-L8) and a non-number newest over an older valid one
--       (L9-L12), each on the seq-scan and the index plan.
--   O   gate order unchanged: Connect not ready refuses before an invalid rate is read.
--   S   refusal before side effect (real calls, index plan): a refused publish leaves the event announced with no
--       audit row; the accepted publish after it writes exactly one.
--   Z   the probes left no order behind.
--
-- NOT in-suite (runner, evidence dir D/s17-202/): pre-flight refusal of a foreign body with nothing changed,
-- idempotent re-apply, rollback to both predecessor md5s and its re-run, rollback refusal of a foreign body.
--
-- Expected on main WITHOUT 202 (RED, predicted before the run; the file runs to the end): not ok (18) — A5 A6 A7;
-- R2 (the read prices "1000"); P2 P4 P5 P6 (publish accepts "1000", 10.5, 10001, -1) P9 (raw 22P02 on true); X1;
-- L5 L9 (raw 22P02 on the seq-scan plan) L10 L11 L12; S1 S2 S3. Passing on RED by design: the checkout reference
-- K1-K10, the controls F1 A1-A4 L1-L4 Z1, and the cases where the old readers already agree (R1 R3-R10, P1 P3 P7
-- P8 P10, L6-L8, O1); the runner's mutants each fail at least one of them (D/s17-202/run_202.log; R10 / P10 against
-- a read / publish that skips a JSON-null version: D/s17-202/fix-r1/run_202f.log).
-- ============================================================================
BEGIN;
SELECT plan(56);

CREATE TABLE tap.memo_271 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store271(k text, v text) RETURNS text LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_271 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch271(k text) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER AS
$m$ SELECT v::jsonb FROM tap.memo_271 WHERE k = $1 $m$;
-- the caller's own call, for real, never aborting the file: the result, or {error, message}
CREATE FUNCTION tap._try271(p_sql text) RETURNS jsonb LANGUAGE plpgsql AS
$m$ DECLARE r jsonb; BEGIN EXECUTE p_sql INTO r; RETURN r;
    EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('error', SQLSTATE, 'message', SQLERRM); END $m$;
-- the caller's own call in a subtransaction that is always rolled back: the result it returned, or {error, message}
CREATE FUNCTION tap._probe271(p_sql text) RETURNS jsonb LANGUAGE plpgsql AS
$m$ DECLARE r jsonb; v_done boolean := false;
BEGIN
  BEGIN
    EXECUTE p_sql INTO r;
    v_done := true;
    RAISE EXCEPTION 'probe271: the probed call is rolled back';
  EXCEPTION WHEN OTHERS THEN
    IF v_done THEN RETURN r; END IF;
    RETURN jsonb_build_object('error', SQLSTATE, 'message', SQLERRM);
  END;
END $m$;
-- a new version of the rate on top (append-only table)
CREATE FUNCTION tap._rate271(v jsonb) RETURNS void LANGUAGE sql SECURITY DEFINER AS $m$
  INSERT INTO catalog.platform_config (key, version, value, visibility)
  SELECT 'fee.buyer_service_bps', max(version) + 1, v, 'restricted' FROM catalog.platform_config WHERE key = 'fee.buyer_service_bps' $m$;
-- one state, three callers: the read as anon, checkout as the fan (her hold), publish as the org owner (probes)
CREATE FUNCTION tap._run271(k text) RETURNS void LANGUAGE plpgsql AS $m$
BEGIN
  PERFORM tap.login_anon();
  PERFORM tap._store271('r_' || k, tap._try271($q$
    SELECT jsonb_build_object('fee', e -> 'buyer_fee_minor', 'all_in', e -> 'all_in_price_minor')
      FROM public.get_primary_session('a271fee0-e0b0-4c00-a0d0-0000000c0f01') g, jsonb_array_elements(g.ticket_types) e
     WHERE e ->> 'ticket_type_id' = 'a271fee0-e0b0-4c00-a0d0-0000000c1101'$q$)::text);
  PERFORM tap.logout();
  PERFORM tap.login('a271fee0-e0b0-4c00-a0d0-0000000c0b02');
  PERFORM tap._store271('k_' || k, tap._probe271(format($q$
    SELECT venue.create_primary_checkout('a271fee0-e0b0-4c00-a0d0-0000000c0f01',
             '[{"ticket_type_id":"a271fee0-e0b0-4c00-a0d0-0000000c1101","quantity":1}]'::jsonb,
             ARRAY['a271fee0-e0b0-4c00-a0d0-0000000c3101']::uuid[], %L)$q$, 'ck271-k-' || k))::text);
  PERFORM tap.logout();
  PERFORM tap.login('a271fee0-e0b0-4c00-a0d0-0000000c0b01');
  PERFORM tap._store271('p_' || k, tap._probe271(format($q$
    SELECT catalog.publish_event('a271fee0-e0b0-4c00-a0d0-0000000c0e02', 'on_sale', %L)$q$, 'ck271-p-' || k))::text);
  PERFORM tap.logout();
END $m$;
-- renderings: checkout (status total fee charge | SQLSTATE token), publish (status event_status | SQLSTATE message),
-- the read (fee= all_in=), and what the read must show given checkout's outcome
CREATE FUNCTION tap._k271(k text) RETURNS text LANGUAGE sql STABLE AS $m$
  SELECT CASE WHEN j IS NULL THEN '<no result>'
              WHEN j ? 'error' THEN (j ->> 'error') || ' ' || coalesce(substring(j ->> 'message' from '^precondition_failed: ([a-z_]+)'), j ->> 'message')
              ELSE concat_ws(' ', j ->> 'status', j ->> 'total_minor', j ->> 'buyer_fee_minor', j ->> 'charge_total_minor') END
    FROM (SELECT tap._fetch271('k_' || k) AS j) x $m$;
CREATE FUNCTION tap._p271(k text) RETURNS text LANGUAGE sql STABLE AS $m$
  SELECT CASE WHEN j IS NULL THEN '<no result>'
              WHEN j ? 'error' THEN (j ->> 'error') || ' ' || (j ->> 'message')
              ELSE concat_ws(' ', j ->> 'status', j ->> 'event_status') END
    FROM (SELECT tap._fetch271('p_' || k) AS j) x $m$;
CREATE FUNCTION tap._r271(k text) RETURNS text LANGUAGE sql STABLE AS $m$
  SELECT CASE WHEN j IS NULL THEN '<no tier row>'
              WHEN j ? 'error' THEN 'read error ' || (j ->> 'error') || ' ' || (j ->> 'message')
              ELSE 'fee=' || coalesce(j ->> 'fee', 'null') || ' all_in=' || coalesce(j ->> 'all_in', 'null') END
    FROM (SELECT tap._fetch271('r_' || k) AS j) x $m$;
CREATE FUNCTION tap._want271(k text) RETURNS text LANGUAGE sql STABLE AS $m$
  SELECT CASE WHEN j IS NULL THEN '<no checkout result>'
              WHEN j ->> 'message' ~ '^precondition_failed: service_fee_(unset|out_of_range) ' THEN 'fee=null all_in=null'
              WHEN j ? 'error' THEN 'checkout refused for another reason: ' || (j ->> 'message')
              ELSE 'fee=' || (j ->> 'buyer_fee_minor') || ' all_in=' || (j ->> 'charge_total_minor') END
    FROM (SELECT tap._fetch271('k_' || k) AS j) x $m$;
-- the forced plans (SET LOCAL) and EXPLAIN text (as postgres: no RLS qual, the definer bodies' plan shape)
CREATE FUNCTION tap._seqplan271() RETURNS void LANGUAGE plpgsql AS $m$ BEGIN
  PERFORM set_config('enable_seqscan', 'on', true);  PERFORM set_config('enable_indexscan', 'off', true);
  PERFORM set_config('enable_bitmapscan', 'off', true); PERFORM set_config('enable_indexonlyscan', 'off', true);
END $m$;
CREATE FUNCTION tap._idxplan271() RETURNS void LANGUAGE plpgsql AS $m$ BEGIN
  PERFORM set_config('enable_seqscan', 'off', true); PERFORM set_config('enable_indexscan', 'on', true);
  PERFORM set_config('enable_bitmapscan', 'off', true); PERFORM set_config('enable_indexonlyscan', 'on', true);
END $m$;
CREATE FUNCTION tap._anyplan271() RETURNS void LANGUAGE plpgsql AS $m$ BEGIN
  PERFORM set_config('enable_seqscan', 'on', true);  PERFORM set_config('enable_indexscan', 'on', true);
  PERFORM set_config('enable_bitmapscan', 'on', true); PERFORM set_config('enable_indexonlyscan', 'on', true);
END $m$;
CREATE FUNCTION tap._explain271(q text) RETURNS text LANGUAGE plpgsql AS $m$
DECLARE l text; r text := ''; BEGIN FOR l IN EXECUTE 'EXPLAIN (COSTS OFF) ' || q LOOP r := r || l || E'\n'; END LOOP; RETURN r; END $m$;
GRANT EXECUTE ON FUNCTION tap._store271(text, text), tap._fetch271(text), tap._try271(text), tap._probe271(text) TO anon, authenticated;
-- throwaway P-256 SPKI PEM (suite 176's; no private half anywhere)
CREATE FUNCTION tap._pem271() RETURNS text LANGUAGE sql IMMUTABLE AS $f$ SELECT $p$-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEo7hfdCPypem8qEenAzd0mmD0GgSS
OF3URrfCTerouHSWiARzxx7TdWySJhKwFvhcdh8MkgdjmysEJXFDVa8Nuw==
-----END PUBLIC KEY-----
$p$ $f$;

-- ── Fixture (synthetic; never a migration) ─────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at) VALUES
  ('a271fee0-e0b0-4c00-a0d0-0000000c0b01', repeat('0', 32)::uuid, 'authenticated', 'authenticated', 'owner.271@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('a271fee0-e0b0-4c00-a0d0-0000000c0b02', repeat('0', 32)::uuid, 'authenticated', 'authenticated', 'fan.271@test.local',   '{"provider":"email","providers":["email"]}', '{}', now(), now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('a271fee0-e0b0-4c00-a0d0-0000000c0a01', 'Org 271', 'Org 271', 'active');
UPDATE kernel.organization SET stripe_connect_account_ref = 'acct_test271fee', connect_transfers_active = true
 WHERE org_id = 'a271fee0-e0b0-4c00-a0d0-0000000c0a01';
INSERT INTO kernel.org_member (org_id, identity_id, role) VALUES
  ('a271fee0-e0b0-4c00-a0d0-0000000c0a01', 'a271fee0-e0b0-4c00-a0d0-0000000c0b01', 'org_owner');
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status) VALUES
  ('a271fee0-e0b0-4c00-a0d0-0000000c0c01', 'a271fee0-e0b0-4c00-a0d0-0000000c0a01', 'Room 271', 'wynwood', 'approved');
-- E1 on_sale: the buyer read and checkout; E2 announced: publish (probed on_sale until Section S)
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  ('a271fee0-e0b0-4c00-a0d0-0000000c0e01', 'a271fee0-e0b0-4c00-a0d0-0000000c0c01', 'a271fee0-e0b0-4c00-a0d0-0000000c0a01', 'Fee read 271', 'on_sale'),
  ('a271fee0-e0b0-4c00-a0d0-0000000c0e02', 'a271fee0-e0b0-4c00-a0d0-0000000c0c01', 'a271fee0-e0b0-4c00-a0d0-0000000c0a01', 'Fee gate 271', 'announced');
INSERT INTO catalog.event_session (session_id, event_id, starts_at, status) VALUES
  ('a271fee0-e0b0-4c00-a0d0-0000000c0f01', 'a271fee0-e0b0-4c00-a0d0-0000000c0e01', now() + interval '40 days', 'scheduled'),
  ('a271fee0-e0b0-4c00-a0d0-0000000c0f02', 'a271fee0-e0b0-4c00-a0d0-0000000c0e02', now() + interval '41 days', 'scheduled');
-- 1005 face: 1000 bps is a .5-cent fee (100.5 -> 101, half-up), so the agreement covers checkout's rounding
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility) VALUES
  ('a271fee0-e0b0-4c00-a0d0-0000000c1101', 'a271fee0-e0b0-4c00-a0d0-0000000c0e01', 'admission', 'GA 271', 1005, 'public'),
  ('a271fee0-e0b0-4c00-a0d0-0000000c1102', 'a271fee0-e0b0-4c00-a0d0-0000000c0e02', 'admission', 'GA 271b', 1005, 'public');
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold) VALUES
  ('a271fee0-e0b0-4c00-a0d0-0000000c2101', 'a271fee0-e0b0-4c00-a0d0-0000000c1101', 'a271fee0-e0b0-4c00-a0d0-0000000c0f01', 'public_sale', 50, 1, 0),
  ('a271fee0-e0b0-4c00-a0d0-0000000c2102', 'a271fee0-e0b0-4c00-a0d0-0000000c1102', 'a271fee0-e0b0-4c00-a0d0-0000000c0f02', 'public_sale', 10, 0, 0);
INSERT INTO venue.inventory_hold (hold_id, batch_id, identity_id, quantity, status, expires_at, command_idempotency_key) VALUES
  ('a271fee0-e0b0-4c00-a0d0-0000000c3101', 'a271fee0-e0b0-4c00-a0d0-0000000c2101', 'a271fee0-e0b0-4c00-a0d0-0000000c0b02', 1, 'active', now() + interval '1 hour', 'h-271');
-- the global ES256 bootstrap key THROUGH THE LIVE 110 GUARD, only when no active global key resolves (the ruling-B
-- key_id and an all-zero-account key ARN, both built at run time)
INSERT INTO kernel.signing_key (key_id, scope, public_key, kms_handle_ref, algorithm, status, not_before)
SELECT (repeat('0', 30) || 'b0')::uuid, 'global', tap._pem271(),
       'arn:aws:kms:us-east-1:' || repeat('0', 12) || ':key/1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b', 'ES256', 'active', now()
 WHERE NOT EXISTS (SELECT 1 FROM kernel.signing_key k WHERE k.scope = 'global' AND k.status = 'active');
SELECT is((SELECT ARRAY[(SELECT count(*) FROM kernel.signing_key k WHERE k.scope = 'global' AND k.status = 'active' AND k.not_before <= now())::integer,
                        (SELECT (c.value = 'null'::jsonb)::integer FROM catalog.platform_config c WHERE c.key = 'fee.buyer_service_bps' ORDER BY c.version DESC LIMIT 1),
                        (SELECT count(*) FROM catalog.event e WHERE e.org_id = 'a271fee0-e0b0-4c00-a0d0-0000000c0a01' AND e.status IN ('on_sale', 'announced'))::integer,
                        (SELECT count(*) FROM venue.inventory_hold h WHERE h.hold_id = 'a271fee0-e0b0-4c00-a0d0-0000000c3101' AND h.status = 'active')::integer]),
          ARRAY[1, 1, 2, 1],
  'F1: fixture — one active global key resolves; the rate is unset (newest JSON null); E1 on_sale + E2 announced; the fan''s hold is active');

-- ── Section A — posture, md5, comment ────────────────────────────────────────
SELECT ok(coalesce((SELECT p.prosecdef AND p.provolatile = 's' AND l.lanname = 'sql' AND p.proconfig = ARRAY['search_path=""']
                           AND p.proowner = 'postgres'::regrole
                           AND pg_get_function_result(p.oid) = 'TABLE(session jsonb, event jsonb, venue jsonb, ticket_types jsonb)'
                           AND (SELECT count(*) FROM pg_proc x WHERE x.pronamespace = 'public'::regnamespace AND x.proname = 'get_primary_session') = 1
                      FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang WHERE p.oid = to_regprocedure('public.get_primary_session(uuid)')), false),
  'A1: get_primary_session(uuid) is still one postgres-owned SECURITY DEFINER STABLE sql body, search_path='''', same RETURNS TABLE');
SELECT ok(coalesce(has_function_privilege('anon', to_regprocedure('public.get_primary_session(uuid)'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('public.get_primary_session(uuid)'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('service_role', to_regprocedure('public.get_primary_session(uuid)'), 'EXECUTE'), false)
      AND coalesce((SELECT p.proacl IS NOT NULL AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0)
                      FROM pg_proc p WHERE p.oid = to_regprocedure('public.get_primary_session(uuid)')), false),
  'A2: get_primary_session EXECUTE posture unchanged — anon + authenticated + service_role, explicit, no PUBLIC entry');
SELECT ok(coalesce((SELECT p.prosecdef AND p.provolatile = 'v' AND l.lanname = 'plpgsql' AND p.proconfig = ARRAY['search_path=""']
                           AND p.proowner = 'postgres'::regrole AND p.prorettype = 'jsonb'::regtype
                           AND (SELECT count(*) FROM pg_proc x WHERE x.pronamespace = 'catalog'::regnamespace AND x.proname = 'publish_event') = 1
                      FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang WHERE p.oid = to_regprocedure('catalog.publish_event(uuid,text,text)')), false),
  'A3: publish_event(uuid,text,text) is still one postgres-owned SECURITY DEFINER VOLATILE plpgsql body, search_path='''', returns jsonb');
SELECT ok(coalesce(has_function_privilege('authenticated', to_regprocedure('catalog.publish_event(uuid,text,text)'), 'EXECUTE'), false)
      AND NOT coalesce(has_function_privilege('anon', to_regprocedure('catalog.publish_event(uuid,text,text)'), 'EXECUTE'), true)
      AND coalesce((SELECT p.proacl IS NOT NULL AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0)
                      FROM pg_proc p WHERE p.oid = to_regprocedure('catalog.publish_event(uuid,text,text)')), false),
  'A4: publish_event EXECUTE posture unchanged — authenticated, not anon, no PUBLIC entry');
SELECT is(md5(pg_get_functiondef(to_regprocedure('public.get_primary_session(uuid)'))), 'ac639b649b510ef089ea55c3c70068fa',
  'A5: get_primary_session body = 202''s (md5(pg_get_functiondef) ac639b64; 182''s was 8915bf3d)');
SELECT is(md5(pg_get_functiondef(to_regprocedure('catalog.publish_event(uuid,text,text)'))), 'f30eaca23ae71a33243e39a6c8c5a8fd',
  'A6: publish_event body = 202''s (md5(pg_get_functiondef) f30eaca2; e76''s was 18e96244)');
SELECT is(md5(obj_description(to_regprocedure('public.get_primary_session(uuid)'), 'pg_proc')), '1af9f2294f0523662bad51d59f5dd00b',
  'A7: the COMMENT on get_primary_session is 202''s (it names the JSON-number and integer 0..10000 rule)');

-- ── Section C — the value matrix (one state per newest value; default plan settings) ───────────────────
SELECT tap._rate271('1000'::jsonb);
SELECT tap._run271('c1');
-- c10: JSON null written DIRECTLY over c1's valid 1000, before any older non-number exists (so on a tree without 202
-- the old cast-in-an-ordered-LIMIT publish read has nothing to raise on here; plan traps are Section L's subject).
-- The two newest versions are kept for K10, which proves the state.
SELECT tap._rate271('null'::jsonb);
SELECT tap._store271('h_c10', (SELECT jsonb_agg(x.value ORDER BY x.version DESC)
                                 FROM (SELECT c.value, c.version FROM catalog.platform_config c
                                        WHERE c.key = 'fee.buyer_service_bps' ORDER BY c.version DESC LIMIT 2) x)::text);
SELECT tap._run271('c10');
SELECT tap._rate271('"1000"'::jsonb);
SELECT tap._run271('c2');
SELECT tap._rate271('null'::jsonb);
SELECT tap._run271('c3');
SELECT tap._rate271('10.5'::jsonb);
SELECT tap._run271('c4');
SELECT tap._rate271('10001'::jsonb);
SELECT tap._run271('c5');
SELECT tap._rate271('-1'::jsonb);
SELECT tap._run271('c6');
SELECT tap._rate271('0'::jsonb);
SELECT tap._run271('c7');
SELECT tap._rate271('10000'::jsonb);
SELECT tap._run271('c8');
SELECT tap._rate271('true'::jsonb);
SELECT tap._run271('c9');

SELECT is(tap._k271('c1'), 'ok 1005 101 1106',               'K1: newest 1000 (JSON number) — checkout quotes 1005 + 101 (100.5 half-up) = 1106');
SELECT is(tap._k271('c2'), 'P0001 service_fee_unset',        'K2: newest "1000" (JSON string) — checkout refuses service_fee_unset');
SELECT is(tap._k271('c3'), 'P0001 service_fee_unset',        'K3: newest JSON null — checkout refuses service_fee_unset');
SELECT is(tap._k271('c4'), 'P0001 service_fee_out_of_range', 'K4: newest 10.5 (fractional) — checkout refuses service_fee_out_of_range');
SELECT is(tap._k271('c5'), 'P0001 service_fee_out_of_range', 'K5: newest 10001 (above 10000) — checkout refuses service_fee_out_of_range');
SELECT is(tap._k271('c6'), 'P0001 service_fee_out_of_range', 'K6: newest -1 (negative) — checkout refuses service_fee_out_of_range');
SELECT is(tap._k271('c7'), 'ok 1005 0 1005',                 'K7: newest 0 — checkout ACCEPTS a zero rate (0..10000) and quotes face value');
SELECT is(tap._k271('c8'), 'ok 1005 1005 2010',              'K8: newest 10000 (the upper bound) — checkout quotes 1005 + 1005');
SELECT is(tap._k271('c9'), 'P0001 service_fee_unset',        'K9: newest true (JSON boolean) — checkout refuses service_fee_unset');
SELECT is(tap._k271('c10') || ' | ' || tap._fetch271('h_c10')::text, 'P0001 service_fee_unset | [null, 1000]',
  'K10: newest JSON null written directly over a valid 1000 (the two newest versions) — checkout refuses service_fee_unset on the explicit unset');

SELECT is(tap._r271('c1'), tap._want271('c1'), 'R1: newest 1000 — the read''s (buyer_fee_minor, all_in_price_minor) = checkout''s (buyer_fee_minor, charge_total_minor)');
SELECT is(tap._r271('c2'), tap._want271('c2'), 'R2: newest "1000" (a JSON string) — the read prices nothing (both NULL), as checkout refuses');
SELECT is(tap._r271('c3'), tap._want271('c3'), 'R3: newest null — both NULL, as checkout refuses');
SELECT is(tap._r271('c4'), tap._want271('c4'), 'R4: newest 10.5 — both NULL, as checkout refuses');
SELECT is(tap._r271('c5'), tap._want271('c5'), 'R5: newest 10001 — both NULL, as checkout refuses');
SELECT is(tap._r271('c6'), tap._want271('c6'), 'R6: newest -1 — both NULL, as checkout refuses');
SELECT is(tap._r271('c7'), tap._want271('c7'), 'R7: newest 0 — the read prices a zero fee (0, 1005), as checkout quotes');
SELECT is(tap._r271('c8'), tap._want271('c8'), 'R8: newest 10000 — the read = checkout''s quote (1005, 2010)');
SELECT is(tap._r271('c9'), tap._want271('c9'), 'R9: newest true — both NULL, as checkout refuses');
SELECT is(tap._r271('c10'), tap._want271('c10'), 'R10: newest null directly over a valid 1000 — both NULL, as checkout refuses (the read does not price the 1000 below the unset)');

SELECT is(tap._p271('c1'), 'ok on_sale', 'P1: newest 1000 — publish goes on_sale');
SELECT is(tap._p271('c2'), 'P0001 precondition_failed: fee_policy_unset — fee.buyer_service_bps is a JSON string, not a number; this event cannot go on sale until the owner sets an integer',
  'P2: newest "1000" (a JSON string) — publish refuses fee_policy_unset (it is not a JSON number)');
SELECT is(tap._p271('c3'), 'P0001 precondition_failed: fee_policy_unset — fee.buyer_service_bps has no value; this event cannot go on sale until the owner sets it',
  'P3: newest null — publish refuses fee_policy_unset with the unchanged text');
SELECT is(tap._p271('c4'), 'P0001 precondition_failed: fee_policy_unset — fee.buyer_service_bps must be an integer 0..10000, got 10.5; this event cannot go on sale until the owner corrects it',
  'P4: newest 10.5 — publish refuses fee_policy_unset (fractional)');
SELECT is(tap._p271('c5'), 'P0001 precondition_failed: fee_policy_unset — fee.buyer_service_bps must be an integer 0..10000, got 10001; this event cannot go on sale until the owner corrects it',
  'P5: newest 10001 — publish refuses fee_policy_unset (above 10000)');
SELECT is(tap._p271('c6'), 'P0001 precondition_failed: fee_policy_unset — fee.buyer_service_bps must be an integer 0..10000, got -1; this event cannot go on sale until the owner corrects it',
  'P6: newest -1 — publish refuses fee_policy_unset (negative)');
SELECT is(tap._p271('c7'), 'ok on_sale', 'P7: newest 0 — publish goes on_sale, as checkout quotes on 0');
SELECT is(tap._p271('c8'), 'ok on_sale', 'P8: newest 10000 — publish goes on_sale');
SELECT is(tap._p271('c9'), 'P0001 precondition_failed: fee_policy_unset — fee.buyer_service_bps is a JSON boolean, not a number; this event cannot go on sale until the owner sets an integer',
  'P9: newest true — publish refuses fee_policy_unset cleanly (no raw 22P02)');
SELECT is(tap._p271('c10'), 'P0001 precondition_failed: fee_policy_unset — fee.buyer_service_bps has no value; this event cannot go on sale until the owner sets it',
  'P10: newest null directly over a valid 1000 — publish refuses fee_policy_unset with the unchanged text (it does not go on sale on the 1000 below the unset)');
SELECT is((SELECT coalesce(string_agg(c.k, ' ' ORDER BY c.k), '')
             FROM (SELECT 'c' || g AS k FROM generate_series(1, 10) g) c
            WHERE (tap._p271(c.k) = 'ok on_sale') IS DISTINCT FROM (tap._k271(c.k) LIKE 'ok %')
               OR (tap._p271(c.k) <> 'ok on_sale' AND tap._p271(c.k) NOT LIKE 'P0001 precondition_failed: fee_policy_unset — %')
               OR (tap._k271(c.k) NOT LIKE 'ok %' AND tap._k271(c.k) NOT IN ('P0001 service_fee_unset', 'P0001 service_fee_out_of_range'))), '',
  'X1: over the whole matrix publish goes on_sale exactly when checkout quotes, and refuses with fee_policy_unset exactly when checkout refuses on the rate (lists the disagreeing cases)');

-- ── Section L — plan independence. History so far: null (seed), 1000, null, "1000", null, 10.5, 10001, -1, 0,
--    10000, true; now "ten percent" and a valid newest 1000 on top (L5-L8), then "1000" on top of that (L9-L12) ──
SELECT tap._rate271('"ten percent"'::jsonb);
SELECT tap._rate271('1000'::jsonb);
SELECT tap._seqplan271();
SELECT ok(tap._explain271($q$SELECT (c.value #>> '{}')::numeric FROM catalog.platform_config c WHERE c.key = 'fee.buyer_service_bps' ORDER BY c.version DESC LIMIT 1$q$)
            ~ 'Seq Scan on platform_config'
          AND tap._explain271($q$SELECT (c.value #>> '{}')::numeric FROM catalog.platform_config c WHERE c.key = 'fee.buyer_service_bps' ORDER BY c.version DESC LIMIT 1$q$)
            !~ 'Index',
  'L1: forced plan 1 is real — the old cast-in-an-ordered-LIMIT read is a seq scan + sort');
SELECT tap._idxplan271();
SELECT ok(tap._explain271($q$SELECT (c.value #>> '{}')::numeric FROM catalog.platform_config c WHERE c.key = 'fee.buyer_service_bps' ORDER BY c.version DESC LIMIT 1$q$)
            ~ 'Index Scan Backward using \S+ on platform_config',
  'L2: forced plan 2 is real — the same statement is a backward index scan');
SELECT tap._seqplan271();
SELECT is(tap._try271($q$SELECT to_jsonb((c.value #>> '{}')::numeric) FROM catalog.platform_config c WHERE c.key = 'fee.buyer_service_bps' ORDER BY c.version DESC LIMIT 1$q$) ->> 'error',
  '22P02',
  'L3: the trap is armed — the old read, run directly on the seq-scan plan, raises 22P02 on an older non-number although the newest is 1000');
DISCARD PLANS;
SELECT tap._run271('ls');
SELECT tap._idxplan271();
DISCARD PLANS;
SELECT tap._run271('li');
SELECT tap._anyplan271();
DISCARD PLANS;
SELECT tap._rate271('"1000"'::jsonb);
SELECT tap._seqplan271();
DISCARD PLANS;
SELECT tap._run271('vs');
SELECT tap._idxplan271();
DISCARD PLANS;
SELECT tap._run271('vi');
SELECT tap._seqplan271();
SELECT ok(tap._explain271($q$SELECT (SELECT c.value FROM catalog.platform_config c WHERE c.key = 'fee.buyer_service_bps' ORDER BY c.version DESC LIMIT 1)$q$)
            ~ 'Seq Scan on platform_config',
  'L4: the 202 read''s own rate statement is a seq scan under the L5/L6/L9/L10 settings too (it carries no cast to fail)');
SELECT tap._anyplan271();
DISCARD PLANS;

SELECT is(tap._p271('ls'), 'ok on_sale',
  'L5: valid newest 1000 over older non-numbers, SEQ-SCAN plan — publish goes on_sale (no 22P02 from an older version)');
SELECT is(tap._r271('ls') || ' | ' || tap._k271('ls'), tap._want271('ls') || ' | ok 1005 101 1106',
  'L6: …and the read = checkout''s quote on the same plan (101, 1106)');
SELECT is(tap._p271('li'), 'ok on_sale',
  'L7: valid newest 1000 over older non-numbers, INDEX plan — publish goes on_sale');
SELECT is(tap._r271('li') || ' | ' || tap._k271('li'), tap._want271('li') || ' | ok 1005 101 1106',
  'L8: …and the read = checkout''s quote on the same plan');
SELECT is(tap._p271('vs'), 'P0001 precondition_failed: fee_policy_unset — fee.buyer_service_bps is a JSON string, not a number; this event cannot go on sale until the owner sets an integer',
  'L9: newest "1000" over an older valid 1000, SEQ-SCAN plan — publish refuses fee_policy_unset (not a raw 22P02)');
SELECT is(tap._r271('vs') || ' | ' || tap._k271('vs'), 'fee=null all_in=null | P0001 service_fee_unset',
  'L10: …the read prices nothing and checkout refuses on the same plan');
SELECT is(tap._p271('vi'), 'P0001 precondition_failed: fee_policy_unset — fee.buyer_service_bps is a JSON string, not a number; this event cannot go on sale until the owner sets an integer',
  'L11: newest "1000" over an older valid 1000, INDEX plan — publish refuses fee_policy_unset');
SELECT is(tap._r271('vi') || ' | ' || tap._k271('vi'), 'fee=null all_in=null | P0001 service_fee_unset',
  'L12: …the read prices nothing and checkout refuses on the same plan');

-- ── Section O — the ladder order is unchanged (newest rate is still the invalid "1000") ─────────────────
UPDATE kernel.organization SET connect_transfers_active = false WHERE org_id = 'a271fee0-e0b0-4c00-a0d0-0000000c0a01';
SELECT tap.login('a271fee0-e0b0-4c00-a0d0-0000000c0b01');
SELECT tap._store271('p_o1', tap._probe271($q$SELECT catalog.publish_event('a271fee0-e0b0-4c00-a0d0-0000000c0e02', 'on_sale', 'ck271-o1')$q$)::text);
SELECT tap.logout();
UPDATE kernel.organization SET connect_transfers_active = true WHERE org_id = 'a271fee0-e0b0-4c00-a0d0-0000000c0a01';
SELECT is(tap._p271('o1'), 'P0001 precondition_failed: connect_not_ready',
  'O1: Connect not ready refuses connect_not_ready before the (invalid) rate is read — the fee gate is still last');

-- ── Section S — refusal before side effect (real calls; INDEX plan forced, so on a tree without 202 the old
--    read casts only the newest "1000", accepts it and writes: S1/S2 then fail for that reason, not on a 22P02) ──
SELECT tap._idxplan271();
DISCARD PLANS;
SELECT tap.login('a271fee0-e0b0-4c00-a0d0-0000000c0b01');
SELECT tap._store271('p_s1', tap._try271($q$SELECT catalog.publish_event('a271fee0-e0b0-4c00-a0d0-0000000c0e02', 'on_sale', 'ck271-s1')$q$)::text);
SELECT tap.logout();
SELECT is(tap._p271('s1'), 'P0001 precondition_failed: fee_policy_unset — fee.buyer_service_bps is a JSON string, not a number; this event cannot go on sale until the owner sets an integer',
  'S1: a real publish with newest "1000" is refused fee_policy_unset');
SELECT is((SELECT (e.status, (SELECT count(*) FROM kernel.admin_audit a WHERE a.subject_id = e.event_id AND a.action = 'event.status')::integer)::text
             FROM catalog.event e WHERE e.event_id = 'a271fee0-e0b0-4c00-a0d0-0000000c0e02'),
          ('announced', 0)::text,
  'S2: …and wrote nothing — E2 is still announced, no event.status audit row');
SELECT tap._rate271('1000'::jsonb);
SELECT tap.login('a271fee0-e0b0-4c00-a0d0-0000000c0b01');
SELECT tap._store271('p_s3', tap._try271($q$SELECT catalog.publish_event('a271fee0-e0b0-4c00-a0d0-0000000c0e02', 'on_sale', 'ck271-s3')$q$)::text);
SELECT tap.logout();
SELECT tap._anyplan271();
DISCARD PLANS;
SELECT is((SELECT (tap._p271('s3'), e.status,
                   (SELECT count(*) FROM kernel.admin_audit a WHERE a.subject_id = e.event_id AND a.action = 'event.status'
                       AND a.after = '{"status":"on_sale"}'::jsonb)::integer)::text
             FROM catalog.event e WHERE e.event_id = 'a271fee0-e0b0-4c00-a0d0-0000000c0e02'),
          ('ok on_sale', 'on_sale', 1)::text,
  'S3: with newest 1000 the same real call goes on_sale and writes exactly one event.status audit row (S2''s zero is not vacuous)');

-- ── Section Z — the probes left nothing behind ───────────────────────────────
SELECT is((SELECT count(*)::integer FROM venue."order" o WHERE o.buyer_id = 'a271fee0-e0b0-4c00-a0d0-0000000c0b02'), 0,
  'Z1: no order exists for the fan — every probed checkout (including the accepted quotes) was rolled back');

SELECT * FROM finish();
ROLLBACK;

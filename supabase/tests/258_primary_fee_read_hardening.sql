-- ============================================================================
-- 258_primary_fee_read_hardening.sql — migration 20261027031000 (registry 188 / pgTAP 258, A).
--
-- (a) venue.create_primary_checkout reads fee.buyer_service_bps NEWEST-ROW-FIRST (a LIMIT subquery) and
--     casts only that value; a newest value that is neither a JSON number nor JSON null refuses
--     'precondition_failed: service_fee_unset — … is a JSON <type>, not a number …'. 093's read (cast in an
--     ordered target list: every version cast before the LIMIT on a seq-scan plan) stays in the text, dead.
-- (b) catalog.set_platform_config refuses a write of fee.buyer_service_bps unless a JSON integer 0..10000
--     (create_primary_checkout's service_fee_out_of_range bounds, 093:4110-4112; the edge maps the code at
--     index.ts:558), and of inventory.per_user_active_hold_max unless a JSON integer >= 1 (fits integer).
--
-- Fixture style: 252 Section F (synthetic rows as postgres, fixed ids tagged 25800000-…, the fan's hold
-- inserted as a row with the batch held raised to match, the org made payable, the global ES256 key through
-- the live 110 guard when no active global key exists, every rate a NEW VERSION of the append-only config
-- row; everything dies with the ROLLBACK). Plans are forced with SET LOCAL enable_* through tap helpers and
-- DISCARD PLANS before every plan-specific call (plpgsql caches a parameterless statement's generic plan
-- for the session; a GUC change alone does not re-plan it).
--
--   F   fixtures (one assertion)
--   A   shape: SECURITY DEFINER + search_path='' + the exact ACLs (unchanged) on both; one overload each;
--       block markers (checkout D/R1/R2, config V); md5 = 188's; strip = the predecessor byte for byte;
--       the 093 read sits only inside the never-taken branch.
--   P   plan independence. History: null (seed) < "ten percent" < 1000 (newest). P1/P2 the two forced plans
--       really are a seq scan + sort and an index scan (EXPLAIN of 093's statement); P3/P4 the defect is
--       real on this fixture — 093's statement run directly raises 22P02 on the seq-scan plan and returns
--       1000 on the index scan (version-agnostic probes); P5/P6 checkout as the fan prices 2500 + 250 on
--       BOTH plans; P7 the 188 read's own statement is a seq scan under the same settings.
--   N   (index-scan plan forced) newest value not a number: "750" (string), true, {"bps":750} ->
--       service_fee_unset (the new message); JSON null -> 093's own service_fee_unset (unchanged text);
--       10001 and 7.5 -> service_fee_out_of_range (unchanged); no order written by any refusal.
--   V   set_platform_config as a platform_admin, current value reset to JSON null before every write:
--       fee.buyer_service_bps — "750", 7.5, 750.0, 10001, -1 refused bad_value, nothing parked or written;
--       750, 0, 10000 accepted (parked for the second admin, fee.% dual control unchanged);
--       inventory.per_user_active_hold_max — "5", 2.5, 0, -3, 2147483648 refused, nothing written; 5 and 1
--       accepted (executed: a new version).
--
-- NOT in-suite (runner, evidence dir a188_189/): pre-flight refusal of a foreign body with nothing changed,
-- idempotent re-apply, rollback to both predecessor md5s with every other function unchanged, rollback
-- refusal and re-run (CI mounts supabase/tests only — the 250/253/255 precedent).
--
-- Expected on the stacked tree WITHOUT 188 (RED, predicted before the run): the file runs to the end
-- (tap._try258 and throws_ok never abort). not ok (22): A6 A7 A8 A11 A12 (no blocks / md5s / the 188 read);
-- P5 (seq-scan checkout raises 22P02); N1 ("750" prices at 750 bps) N2 N3 (22P02, not service_fee_unset)
-- N7 (the "750" checkout wrote an order); V1-V5 and V9 (fee: nothing refused; 8 proposals park);
-- V10-V14 and V18 (hold max: every value accepted, 5 more versions written). Vacuous on RED: A9/A10 (the
-- strip of a block-less body is the body itself — A7/A8 distinguish); V8 (a parked proposal writes no
-- version either way — V9 distinguishes). Negative controls (runner mutants): M1 checkout = 093 (cast before
-- the LIMIT live) -> A6 A7 A11 A12 P5 N1 N2 N3 N7; M2 config = 102 -> A6 A8 V1-V5 V9 V10-V14 V18.
-- ============================================================================
BEGIN;
SELECT plan(45);

CREATE TABLE tap.memo_258 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store258(k text, v text) RETURNS text LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_258 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch258(k text) RETURNS text LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_258 WHERE k = $1 $m$;
-- the caller's own call, never aborting the file: the result, or {error, message}
CREATE FUNCTION tap._try258(p_sql text) RETURNS jsonb LANGUAGE plpgsql AS
$m$ DECLARE r jsonb; BEGIN EXECUTE p_sql INTO r; RETURN r;
    EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('error', SQLSTATE, 'message', SQLERRM); END $m$;
-- the forced plans (SET LOCAL) and the plan-cache reset
CREATE FUNCTION tap._seqplan258() RETURNS void LANGUAGE plpgsql AS $m$ BEGIN
  PERFORM set_config('enable_seqscan', 'on', true);  PERFORM set_config('enable_indexscan', 'off', true);
  PERFORM set_config('enable_bitmapscan', 'off', true); PERFORM set_config('enable_indexonlyscan', 'off', true);
END $m$;
CREATE FUNCTION tap._idxplan258() RETURNS void LANGUAGE plpgsql AS $m$ BEGIN
  PERFORM set_config('enable_seqscan', 'off', true); PERFORM set_config('enable_indexscan', 'on', true);
  PERFORM set_config('enable_bitmapscan', 'off', true); PERFORM set_config('enable_indexonlyscan', 'on', true);
END $m$;
CREATE FUNCTION tap._anyplan258() RETURNS void LANGUAGE plpgsql AS $m$ BEGIN
  PERFORM set_config('enable_seqscan', 'on', true);  PERFORM set_config('enable_indexscan', 'on', true);
  PERFORM set_config('enable_bitmapscan', 'on', true); PERFORM set_config('enable_indexonlyscan', 'on', true);
END $m$;
-- EXPLAIN (COSTS OFF) text of a statement, as postgres (the definer reads the table as its owner, so no
-- RLS qual: the same plan the function body gets under the same settings)
CREATE FUNCTION tap._explain258(q text) RETURNS text LANGUAGE plpgsql AS $m$
DECLARE l text; r text := ''; BEGIN FOR l IN EXECUTE 'EXPLAIN (COSTS OFF) ' || q LOOP r := r || l || E'\n'; END LOOP; RETURN r; END $m$;
-- a new JSON-null version of a key on top (the "current value is null" precondition of the V writes)
CREATE FUNCTION tap._unset258(k text) RETURNS void LANGUAGE sql SECURITY DEFINER AS $m$
  INSERT INTO catalog.platform_config (key, version, value, visibility)
  SELECT c.key, c.version + 1, 'null'::jsonb, c.visibility FROM catalog.platform_config c
   WHERE c.key = k ORDER BY c.version DESC LIMIT 1 $m$;
CREATE FUNCTION tap._rate258(v jsonb) RETURNS void LANGUAGE sql SECURITY DEFINER AS $m$
  INSERT INTO catalog.platform_config (key, version, value, visibility)
  SELECT 'fee.buyer_service_bps', max(version) + 1, v, 'restricted' FROM catalog.platform_config WHERE key = 'fee.buyer_service_bps' $m$;
CREATE FUNCTION tap._versions258(k text) RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER AS
$m$ SELECT count(*)::integer FROM catalog.platform_config WHERE key = k $m$;
CREATE FUNCTION tap._parked258(k text) RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER AS
$m$ SELECT count(*)::integer FROM kernel.approval_request WHERE action = 'config.set_money_key' AND payload ->> 'key' = k $m$;
CREATE FUNCTION tap._orders258(p_prefix text) RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER AS
$m$ SELECT count(*)::integer FROM venue."order" WHERE buyer_id = '25800000-0000-4000-8000-000000000199' AND command_idempotency_key LIKE p_prefix || '%' $m$;
CREATE FUNCTION tap._top258(k text) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER AS
$m$ SELECT c.value FROM catalog.platform_config c WHERE c.key = k ORDER BY c.version DESC LIMIT 1 $m$;
-- strip rule (188 header): every line from a '-- ── 188 BLOCK <X> …' marker through its
-- '-- ── 188 BLOCK <X> END' marker (both included) goes; everything else is kept byte for byte.
CREATE FUNCTION tap._strip258(p_sig text) RETURNS text LANGUAGE sql STABLE AS $m$
  WITH l AS (
    SELECT t.line, t.n,
           CASE WHEN t.line ~ '^ *-- ── 188 BLOCK [A-Z0-9]+ END *$' THEN -1
                WHEN t.line ~ '^ *-- ── 188 BLOCK [A-Z0-9]+( |$)'   THEN 1 ELSE 0 END AS d,
           t.line ~ '^ *-- ── 188 BLOCK ' AS marker
      FROM regexp_split_to_table(pg_get_functiondef(to_regprocedure(p_sig)), E'\n') WITH ORDINALITY AS t(line, n))
  SELECT md5(string_agg(x.line, E'\n' ORDER BY x.n))
    FROM (SELECT l.line, l.n, l.marker, sum(l.d) OVER (ORDER BY l.n) AS depth FROM l) x
   WHERE x.depth = 0 AND NOT x.marker $m$;
CREATE FUNCTION tap._markers258(p_sig text, p_end boolean) RETURNS integer LANGUAGE sql STABLE AS $m$
  SELECT count(*)::integer
    FROM regexp_split_to_table(pg_get_functiondef(to_regprocedure(p_sig)), E'\n') AS t(line)
   WHERE CASE WHEN p_end THEN t.line ~ '^ *-- ── 188 BLOCK [A-Z0-9]+ END *$'
              ELSE t.line ~ '^ *-- ── 188 BLOCK [A-Z0-9]+ ' AND t.line !~ ' END *$' END $m$;
GRANT EXECUTE ON FUNCTION tap._store258(text, text), tap._fetch258(text), tap._try258(text),
  tap._seqplan258(), tap._idxplan258(), tap._anyplan258(), tap._unset258(text), tap._rate258(jsonb),
  tap._versions258(text), tap._parked258(text), tap._orders258(text), tap._top258(text) TO authenticated;
-- throwaway P-256 SPKI PEM (suite 176's; no private half anywhere)
CREATE FUNCTION tap._pem258() RETURNS text LANGUAGE sql IMMUTABLE AS $f$ SELECT $p$-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEo7hfdCPypem8qEenAzd0mmD0GgSS
OF3URrfCTerouHSWiARzxx7TdWySJhKwFvhcdh8MkgdjmysEJXFDVa8Nuw==
-----END PUBLIC KEY-----
$p$ $f$;

-- ── Fixture (synthetic; never a migration) ─────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at) VALUES
  ('25800000-0000-4000-8000-000000000101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin.258@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('25800000-0000-4000-8000-000000000199', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fan.258@test.local',   '{"provider":"email","providers":["email"]}', '{}', now(), now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.platform_role (identity_id, role) VALUES ('25800000-0000-4000-8000-000000000101', 'platform_admin');
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('25800000-0000-4000-8000-00000000000a', 'Org A 258', 'Org A 258', 'active');
UPDATE kernel.organization SET stripe_connect_account_ref = 'acct_258FEETEST', connect_transfers_active = true
 WHERE org_id = '25800000-0000-4000-8000-00000000000a';
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status) VALUES
  ('25800000-0000-4000-8000-0000000000a1', '25800000-0000-4000-8000-00000000000a', 'Room 258', 'wynwood', 'approved');
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  ('25800000-0000-4000-8000-0000000000e1', '25800000-0000-4000-8000-0000000000a1', '25800000-0000-4000-8000-00000000000a', 'Fee 258', 'on_sale');
INSERT INTO catalog.event_session (session_id, event_id, starts_at, status) VALUES
  ('25800000-0000-4000-8000-0000000000f1', '25800000-0000-4000-8000-0000000000e1', now() + interval '40 days', 'scheduled');
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility) VALUES
  ('25800000-0000-4000-8000-000000000011', '25800000-0000-4000-8000-0000000000e1', 'admission', 'GA 258', 2500, 'public');
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold) VALUES
  ('25800000-0000-4000-8000-000000000021', '25800000-0000-4000-8000-000000000011', '25800000-0000-4000-8000-0000000000f1', 'public_sale', 50, 1, 0);
INSERT INTO venue.inventory_hold (hold_id, batch_id, identity_id, quantity, status, expires_at, command_idempotency_key) VALUES
  ('25800000-0000-4000-8000-000000000031', '25800000-0000-4000-8000-000000000021', '25800000-0000-4000-8000-000000000199', 1, 'active', now() + interval '1 hour', 'h-258');
-- the global ES256 bootstrap key THROUGH THE LIVE 110 GUARD (B's recipe), only when no active global key resolves
INSERT INTO kernel.signing_key (key_id, scope, public_key, kms_handle_ref, algorithm, status, not_before)
SELECT '00000000-0000-0000-0000-0000000000b0', 'global', tap._pem258(),
       'arn:aws:kms:us-east-1:000000000000:key/1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b', 'ES256', 'active', now()
 WHERE NOT EXISTS (SELECT 1 FROM kernel.signing_key k WHERE k.scope = 'global' AND k.status = 'active');
-- the rate history: whatever the chain carries, then "ten percent" (a non-numeric version), then 1000 on top
SELECT tap._rate258('"ten percent"'::jsonb);
SELECT tap._rate258('1000'::jsonb);
SELECT is((SELECT ARRAY[(SELECT count(*) FROM kernel.signing_key k WHERE k.scope = 'global' AND k.status = 'active' AND k.not_before <= now())::integer,
                        (SELECT count(*) FROM catalog.platform_config c WHERE c.key = 'fee.buyer_service_bps' AND jsonb_typeof(c.value) = 'string')::integer,
                        (tap._top258('fee.buyer_service_bps') = '1000'::jsonb)::integer]),
          ARRAY[1, 1, 1],
  'F1: fixtures — one active global key resolves; the fee history holds one non-numeric version under a numeric newest (1000)');

-- ── Section A — shape, ACL, body text ────────────────────────────────────────
SELECT is((SELECT prosecdef AND proconfig = ARRAY['search_path=""'] AND prorettype = 'jsonb'::regtype
             FROM pg_proc WHERE oid = to_regprocedure('venue.create_primary_checkout(uuid, jsonb, uuid[], text)')), true,
  'A1: create_primary_checkout(uuid, jsonb, uuid[], text) is still SECURITY DEFINER, search_path='''', returns jsonb');
SELECT is((SELECT prosecdef AND proconfig = ARRAY['search_path=""'] AND prorettype = 'jsonb'::regtype
             FROM pg_proc WHERE oid = to_regprocedure('catalog.set_platform_config(text, jsonb, text, text)')), true,
  'A2: set_platform_config(text, jsonb, text, text) is still SECURITY DEFINER, search_path='''', returns jsonb');
SELECT is((SELECT coalesce(proacl::text, '<default>') FROM pg_proc WHERE oid = to_regprocedure('venue.create_primary_checkout(uuid, jsonb, uuid[], text)')),
  '{postgres=X/postgres,authenticated=X/postgres}',
  'A3: create_primary_checkout EXECUTE ACL is exactly the applied one (188 restates no grant)');
SELECT is((SELECT coalesce(proacl::text, '<default>') FROM pg_proc WHERE oid = to_regprocedure('catalog.set_platform_config(text, jsonb, text, text)')),
  '{postgres=X/postgres,authenticated=X/postgres}',
  'A4: set_platform_config EXECUTE ACL is exactly the applied one (188 restates no grant)');
SELECT is((SELECT count(*)::integer FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE (n.nspname, p.proname) IN (('venue', 'create_primary_checkout'), ('catalog', 'set_platform_config'))), 2,
  'A5: one overload each — 188 replaces at the exact signatures, adds none');
SELECT is(ARRAY[tap._markers258('venue.create_primary_checkout(uuid, jsonb, uuid[], text)', false),
                tap._markers258('venue.create_primary_checkout(uuid, jsonb, uuid[], text)', true),
                tap._markers258('catalog.set_platform_config(text, jsonb, text, text)', false),
                tap._markers258('catalog.set_platform_config(text, jsonb, text, text)', true)], ARRAY[3, 3, 1, 1],
  'A6: 188 blocks — checkout carries three (D, R1, R2), set_platform_config one (V); every opening has its END');
SELECT is(md5(pg_get_functiondef(to_regprocedure('venue.create_primary_checkout(uuid, jsonb, uuid[], text)'))),
  '77004331198b9dad2e51e1ed2ceaef35',
  'A7: create_primary_checkout body = 188''s (md5(pg_get_functiondef) 77004331)');
SELECT is(md5(pg_get_functiondef(to_regprocedure('catalog.set_platform_config(text, jsonb, text, text)'))),
  '2ece44b98c73af1e8c2b5d930b0a5895',
  'A8: set_platform_config body = 188''s (md5(pg_get_functiondef) 2ece44b9)');
SELECT is(tap._strip258('venue.create_primary_checkout(uuid, jsonb, uuid[], text)'), 'a629b41216397da48f71a7c6cc4fd298',
  'A9: create_primary_checkout minus the 188 blocks = the 093 predecessor byte for byte (md5 a629b412)');
SELECT is(tap._strip258('catalog.set_platform_config(text, jsonb, text, text)'), 'd0aaada87856b8579f7e19fcd9934fbf',
  'A10: set_platform_config minus the 188 block = the 102 predecessor byte for byte (md5 d0aaada8)');
SELECT ok(pg_get_functiondef(to_regprocedure('venue.create_primary_checkout(uuid, jsonb, uuid[], text)'))
            ~ 'select l\.value into v_fee_raw\s+from \(select c\.value\s+from catalog\.platform_config c\s+where c\.key = ''fee\.buyer_service_bps''\s+order by c\.version desc\s+limit 1\) l;'
          AND pg_get_functiondef(to_regprocedure('venue.create_primary_checkout(uuid, jsonb, uuid[], text)'))
            ~ 'v_fee_bps := case when jsonb_typeof\(v_fee_raw\) = ''number'' then \(v_fee_raw #>> ''\{\}''\)::numeric end;',
  'A11: checkout picks the newest row in a LIMIT subquery and casts only that value, only when it is a JSON number');
SELECT ok(pg_get_functiondef(to_regprocedure('venue.create_primary_checkout(uuid, jsonb, uuid[], text)'))
            ~ E'  if false then\n  -- ── 188 BLOCK R1 END\n  select \\(c\\.value #>> ''\\{\\}''\\)::numeric into v_fee_bps\n    from catalog\\.platform_config c\n   where c\\.key = ''fee\\.buyer_service_bps''\n   order by c\\.version desc limit 1;\n  -- ── 188 BLOCK R2 '
          AND (SELECT count(*) FROM regexp_matches(pg_get_functiondef(to_regprocedure('venue.create_primary_checkout(uuid, jsonb, uuid[], text)')), '::numeric into v_fee_bps', 'g')) = 1,
  'A12: 093''s cast-before-LIMIT read appears once, only inside the never-taken `if false` branch');

-- ── Section P — plan independence (history: … "ten percent" < 1000 newest) ─────
SELECT tap._seqplan258();
SELECT ok(tap._explain258($q$SELECT (c.value #>> '{}')::numeric FROM catalog.platform_config c WHERE c.key = 'fee.buyer_service_bps' ORDER BY c.version DESC LIMIT 1$q$)
            ~ 'Seq Scan on platform_config'
          AND tap._explain258($q$SELECT (c.value #>> '{}')::numeric FROM catalog.platform_config c WHERE c.key = 'fee.buyer_service_bps' ORDER BY c.version DESC LIMIT 1$q$)
            !~ 'Index',
  'P1: forced plan 1 — 093''s statement is a seq scan + sort (no index)');
SELECT tap._idxplan258();
SELECT ok(tap._explain258($q$SELECT (c.value #>> '{}')::numeric FROM catalog.platform_config c WHERE c.key = 'fee.buyer_service_bps' ORDER BY c.version DESC LIMIT 1$q$)
            ~ 'Index Scan Backward using \S+ on platform_config',
  'P2: forced plan 2 — 093''s statement is a backward index scan');
SELECT tap._seqplan258();
SELECT is(tap._try258($q$SELECT to_jsonb((c.value #>> '{}')::numeric) FROM catalog.platform_config c WHERE c.key = 'fee.buyer_service_bps' ORDER BY c.version DESC LIMIT 1$q$) ->> 'error',
  '22P02',
  'P3: THE DEFECT — 093''s read, run directly on the seq-scan plan, raises 22P02 on the older "ten percent" although the newest version is 1000');
SELECT tap._idxplan258();
SELECT is(tap._try258($q$SELECT to_jsonb((c.value #>> '{}')::numeric) FROM catalog.platform_config c WHERE c.key = 'fee.buyer_service_bps' ORDER BY c.version DESC LIMIT 1$q$),
  '1000'::jsonb,
  'P4: …and on the index scan the same statement returns 1000 — the old read was plan-dependent');
DISCARD PLANS;
SELECT tap._seqplan258();
SELECT tap.login('25800000-0000-4000-8000-000000000199');
SELECT tap._store258('p5', tap._try258($q$SELECT venue.create_primary_checkout('25800000-0000-4000-8000-0000000000f1', '[{"ticket_type_id":"25800000-0000-4000-8000-000000000011","quantity":1}]'::jsonb, ARRAY['25800000-0000-4000-8000-000000000031']::uuid[], 'ck258-p5-seq')$q$)::text);
SELECT tap.logout();
SELECT is((SELECT (j ->> 'status', (j ->> 'total_minor')::int, (j ->> 'buyer_fee_minor')::int, (j ->> 'charge_total_minor')::int)::text FROM (SELECT tap._fetch258('p5')::jsonb j) x),
  ('ok', 2500, 250, 2750)::text,
  'P5: checkout as the fan on the SEQ-SCAN plan prices from the newest version: ok, 2500 face + 250 fee (1000 bps) = 2750 — no 22P02');
DISCARD PLANS;
SELECT tap._idxplan258();
SELECT tap.login('25800000-0000-4000-8000-000000000199');
SELECT tap._store258('p6', tap._try258($q$SELECT venue.create_primary_checkout('25800000-0000-4000-8000-0000000000f1', '[{"ticket_type_id":"25800000-0000-4000-8000-000000000011","quantity":1}]'::jsonb, ARRAY['25800000-0000-4000-8000-000000000031']::uuid[], 'ck258-p6-idx')$q$)::text);
SELECT tap.logout();
SELECT is((SELECT (j ->> 'status', (j ->> 'total_minor')::int, (j ->> 'buyer_fee_minor')::int, (j ->> 'charge_total_minor')::int)::text FROM (SELECT tap._fetch258('p6')::jsonb j) x),
  ('ok', 2500, 250, 2750)::text,
  'P6: …and on the INDEX-SCAN plan the same quote — pricing no longer depends on the plan');
SELECT tap._seqplan258();
SELECT ok(tap._explain258($q$SELECT l.value FROM (SELECT c.value FROM catalog.platform_config c WHERE c.key = 'fee.buyer_service_bps' ORDER BY c.version DESC LIMIT 1) l$q$)
            ~ 'Seq Scan on platform_config',
  'P7: the 188 read''s own statement is a seq scan under the P5 settings too (its subquery carries no cast to fail)');
SELECT tap._anyplan258();
DISCARD PLANS;

-- ── Section N — the newest value is not a number (index-scan plan forced, so on the tree WITHOUT 188 the
--    older "ten percent" cannot mask what 093's read does with the NEWEST value) ─────────────────────────
SELECT tap._idxplan258();
DISCARD PLANS;
SELECT tap._rate258('"750"'::jsonb);
SELECT tap.login('25800000-0000-4000-8000-000000000199');
SELECT throws_ok($q$SELECT venue.create_primary_checkout('25800000-0000-4000-8000-0000000000f1', '[{"ticket_type_id":"25800000-0000-4000-8000-000000000011","quantity":1}]'::jsonb, ARRAY['25800000-0000-4000-8000-000000000031']::uuid[], 'ck258-n1')$q$,
  'P0001', 'precondition_failed: service_fee_unset — fee.buyer_service_bps is a JSON string, not a number; selling cannot be activated until the owner sets an integer',
  'N1: newest "750" (a JSON STRING) -> service_fee_unset (093 cast the text and priced 750 bps)');
SELECT tap.logout();
SELECT tap._rate258('true'::jsonb);
SELECT tap.login('25800000-0000-4000-8000-000000000199');
SELECT throws_ok($q$SELECT venue.create_primary_checkout('25800000-0000-4000-8000-0000000000f1', '[{"ticket_type_id":"25800000-0000-4000-8000-000000000011","quantity":1}]'::jsonb, ARRAY['25800000-0000-4000-8000-000000000031']::uuid[], 'ck258-n2')$q$,
  'P0001', 'precondition_failed: service_fee_unset — fee.buyer_service_bps is a JSON boolean, not a number; selling cannot be activated until the owner sets an integer',
  'N2: newest true -> service_fee_unset (093: 22P02)');
SELECT tap.logout();
SELECT tap._rate258('{"bps": 750}'::jsonb);
SELECT tap.login('25800000-0000-4000-8000-000000000199');
SELECT throws_ok($q$SELECT venue.create_primary_checkout('25800000-0000-4000-8000-0000000000f1', '[{"ticket_type_id":"25800000-0000-4000-8000-000000000011","quantity":1}]'::jsonb, ARRAY['25800000-0000-4000-8000-000000000031']::uuid[], 'ck258-n3')$q$,
  'P0001', 'precondition_failed: service_fee_unset — fee.buyer_service_bps is a JSON object, not a number; selling cannot be activated until the owner sets an integer',
  'N3: newest {"bps":750} -> service_fee_unset (093: 22P02)');
SELECT tap.logout();
SELECT tap._rate258('null'::jsonb);
SELECT tap.login('25800000-0000-4000-8000-000000000199');
SELECT throws_ok($q$SELECT venue.create_primary_checkout('25800000-0000-4000-8000-0000000000f1', '[{"ticket_type_id":"25800000-0000-4000-8000-000000000011","quantity":1}]'::jsonb, ARRAY['25800000-0000-4000-8000-000000000031']::uuid[], 'ck258-n4')$q$,
  'P0001', 'precondition_failed: service_fee_unset — fee.buyer_service_bps has no value; selling cannot be activated until the owner sets it',
  'N4: newest JSON null -> 093''s own service_fee_unset, text unchanged');
SELECT tap.logout();
SELECT tap._rate258('10001'::jsonb);
SELECT tap.login('25800000-0000-4000-8000-000000000199');
SELECT throws_ok($q$SELECT venue.create_primary_checkout('25800000-0000-4000-8000-0000000000f1', '[{"ticket_type_id":"25800000-0000-4000-8000-000000000011","quantity":1}]'::jsonb, ARRAY['25800000-0000-4000-8000-000000000031']::uuid[], 'ck258-n5')$q$,
  'P0001', 'precondition_failed: service_fee_out_of_range — fee.buyer_service_bps must be an integer 0..10000, got 10001',
  'N5: newest 10001 -> service_fee_out_of_range, unchanged');
SELECT tap.logout();
SELECT tap._rate258('7.5'::jsonb);
SELECT tap.login('25800000-0000-4000-8000-000000000199');
SELECT throws_ok($q$SELECT venue.create_primary_checkout('25800000-0000-4000-8000-0000000000f1', '[{"ticket_type_id":"25800000-0000-4000-8000-000000000011","quantity":1}]'::jsonb, ARRAY['25800000-0000-4000-8000-000000000031']::uuid[], 'ck258-n6')$q$,
  'P0001', 'precondition_failed: service_fee_out_of_range — fee.buyer_service_bps must be an integer 0..10000, got 7.5',
  'N6: newest 7.5 -> service_fee_out_of_range, unchanged');
SELECT tap.logout();
SELECT is(ARRAY[tap._orders258('ck258-n'), tap._orders258('ck258-p')], ARRAY[0, 2],
  'N7: no refused quote (N1-N6) wrote an order; the fan''s only orders are the two P quotes');
SELECT tap._anyplan258();
DISCARD PLANS;

-- ── Section V — set_platform_config write validation (as a platform_admin) ────
SELECT tap.login('25800000-0000-4000-8000-000000000101');
SELECT tap._store258('fee_v0', tap._versions258('fee.buyer_service_bps')::text);
SELECT tap._unset258('fee.buyer_service_bps');
SELECT throws_ok($q$SELECT catalog.set_platform_config('fee.buyer_service_bps', '"750"'::jsonb, 'rate', 'ck258-v1')$q$,
  'P0001', 'precondition_failed: bad_value — fee.buyer_service_bps must be a JSON integer 0..10000 (basis points), got "750"',
  'V1: fee "750" (a string) on a null current value -> bad_value');
SELECT throws_ok($q$SELECT catalog.set_platform_config('fee.buyer_service_bps', '7.5'::jsonb, 'rate', 'ck258-v2')$q$,
  'P0001', 'precondition_failed: bad_value — fee.buyer_service_bps must be a JSON integer 0..10000 (basis points), got 7.5',
  'V2: fee 7.5 (a float) -> bad_value');
SELECT throws_ok($q$SELECT catalog.set_platform_config('fee.buyer_service_bps', '750.0'::jsonb, 'rate', 'ck258-v3')$q$,
  'P0001', 'precondition_failed: bad_value — fee.buyer_service_bps must be a JSON integer 0..10000 (basis points), got 750.0',
  'V3: fee 750.0 (not the integer text form) -> bad_value — write 750');
SELECT throws_ok($q$SELECT catalog.set_platform_config('fee.buyer_service_bps', '10001'::jsonb, 'rate', 'ck258-v4')$q$,
  'P0001', 'precondition_failed: bad_value — fee.buyer_service_bps must be a JSON integer 0..10000 (basis points), got 10001',
  'V4: fee 10001 (above 093''s 0..10000) -> bad_value');
SELECT throws_ok($q$SELECT catalog.set_platform_config('fee.buyer_service_bps', '-1'::jsonb, 'rate', 'ck258-v5')$q$,
  'P0001', 'precondition_failed: bad_value — fee.buyer_service_bps must be a JSON integer 0..10000 (basis points), got -1',
  'V5: fee -1 (below 0) -> bad_value');
SELECT is(ARRAY[(catalog.set_platform_config('fee.buyer_service_bps', '750'::jsonb, 'rate', 'ck258-v6') ->> 'status'),
                (catalog.set_platform_config('fee.buyer_service_bps', '0'::jsonb, 'rate', 'ck258-v7') ->> 'status'),
                (catalog.set_platform_config('fee.buyer_service_bps', '10000'::jsonb, 'rate', 'ck258-v8') ->> 'status')],
          ARRAY['parked', 'parked', 'parked'],
  'V6: fee 750, 0 and 10000 (integers, both bounds) are accepted — they PARK for the second platform_admin (fee.% dual control unchanged)');
SELECT is(tap._top258('fee.buyer_service_bps'), 'null'::jsonb, 'V7: …and nothing executed: the current fee value is still the JSON null');
SELECT is(tap._versions258('fee.buyer_service_bps'), tap._fetch258('fee_v0')::integer + 1,
  'V8: the only new fee version is the test''s own null reset — no refused write and no parked proposal wrote a version');
SELECT is(tap._parked258('fee.buyer_service_bps'), 3,
  'V9: exactly the three valid proposals parked — no refused value (V1-V5) parked an approval request');
SELECT tap._store258('hold_v0', tap._versions258('inventory.per_user_active_hold_max')::text);
SELECT tap._unset258('inventory.per_user_active_hold_max');
SELECT throws_ok($q$SELECT catalog.set_platform_config('inventory.per_user_active_hold_max', '"5"'::jsonb, 'cap', 'ck258-v10')$q$,
  'P0001', 'precondition_failed: bad_value — inventory.per_user_active_hold_max must be a JSON integer >= 1, got "5"',
  'V10: hold max "5" (a string) on a null current value -> bad_value');
SELECT tap._unset258('inventory.per_user_active_hold_max');
SELECT throws_ok($q$SELECT catalog.set_platform_config('inventory.per_user_active_hold_max', '2.5'::jsonb, 'cap', 'ck258-v11')$q$,
  'P0001', 'precondition_failed: bad_value — inventory.per_user_active_hold_max must be a JSON integer >= 1, got 2.5',
  'V11: hold max 2.5 (a float) -> bad_value');
SELECT tap._unset258('inventory.per_user_active_hold_max');
SELECT throws_ok($q$SELECT catalog.set_platform_config('inventory.per_user_active_hold_max', '0'::jsonb, 'cap', 'ck258-v12')$q$,
  'P0001', 'precondition_failed: bad_value — inventory.per_user_active_hold_max must be a JSON integer >= 1, got 0',
  'V12: hold max 0 (out of range: every reserve would refuse) -> bad_value');
SELECT tap._unset258('inventory.per_user_active_hold_max');
SELECT throws_ok($q$SELECT catalog.set_platform_config('inventory.per_user_active_hold_max', '-3'::jsonb, 'cap', 'ck258-v13')$q$,
  'P0001', 'precondition_failed: bad_value — inventory.per_user_active_hold_max must be a JSON integer >= 1, got -3',
  'V13: hold max -3 -> bad_value');
SELECT tap._unset258('inventory.per_user_active_hold_max');
SELECT throws_ok($q$SELECT catalog.set_platform_config('inventory.per_user_active_hold_max', '2147483648'::jsonb, 'cap', 'ck258-v14')$q$,
  'P0001', 'precondition_failed: bad_value — inventory.per_user_active_hold_max must be a JSON integer >= 1, got 2147483648',
  'V14: hold max 2147483648 (does not fit the reader''s ::integer) -> bad_value');
SELECT tap._unset258('inventory.per_user_active_hold_max');
SELECT is((catalog.set_platform_config('inventory.per_user_active_hold_max', '5'::jsonb, 'cap', 'ck258-v15') ->> 'status'), 'ok',
  'V15: hold max 5 (an integer) is accepted and executes for one admin (not dual-controlled, 142 H18t)');
SELECT is(tap._top258('inventory.per_user_active_hold_max'), '5'::jsonb, 'V16: …the current hold max is 5');
SELECT tap._unset258('inventory.per_user_active_hold_max');
SELECT is((catalog.set_platform_config('inventory.per_user_active_hold_max', '1'::jsonb, 'cap', 'ck258-v17') ->> 'status'), 'ok',
  'V17: hold max 1 (the lower bound) is accepted');
SELECT is(tap._versions258('inventory.per_user_active_hold_max'), tap._fetch258('hold_v0')::integer + 9,
  'V18: hold max versions = 7 test null resets + the two accepted writes — no refused value (V10-V14) wrote a version');
SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;

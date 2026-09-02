-- ============================================================================
-- 152_crm_export_x6.sql — X-6 assurance suite under the postgres-owned builder
-- (OR-1). Sources: CRM EXPORT SPEC §10.3/§10.4/§12 25-28 ·
-- _governance/X6_POSTGRES_OWNED_ASSURANCE_PLAN.md R1/R2/R6/R8 (T-RPC-CRM-14/15/19).
-- The plan names this file 140_crm_export_x6.sql; 140 is taken by the outbox
-- suite, so it lands as 152 (recorded in POST_FREEZE_AMENDMENTS, package 087).
-- The two embedded lists below are DIFFED against supabase/ci/x6_entry_points.json
-- and x6_forbidden.json by scripts/ci/x6_gate.sh on every PR (pgTAP cannot read
-- the repo), so there is one truth and a drift detector, not two copies.
-- BEGIN … plan(N) … finish() … ROLLBACK.
-- ============================================================================
BEGIN;
SELECT plan(27);

-- ── the manifests (mirrored; gate-diffed) ────────────────────────────────────
CREATE TEMP TABLE x6_entry_points (sig text PRIMARY KEY, oid oid);
-- X6-ENTRY-POINTS-BEGIN
INSERT INTO x6_entry_points (sig) VALUES
  ('venue.assert_may_request(uuid,text,uuid,text,boolean)'),
  ('venue.request_export(text,uuid,text,jsonb,text)'),
  ('venue.build_export_rows(uuid,text,integer)'),
  ('venue.finalize_export(uuid,integer,integer,text,text)'),
  ('venue.authorize_export_download(uuid)'),
  ('venue.revoke_export(uuid,text)'),
  ('venue.claim_artifacts_for_purge(integer)'),
  ('venue.confirm_artifact_purged(uuid,text)'),
  ('venue.reconcile_export_orphans(uuid,text[])'),
  ('venue.list_export_jobs(text,uuid,text)'),
  ('venue.sweep_expired_exports()'),
  ('venue.list_attendees(uuid,jsonb,text,text)'),
  ('venue.lookup_attendee(uuid,text,text)');
-- X6-ENTRY-POINTS-END
UPDATE x6_entry_points SET oid = to_regprocedure(sig)::oid;

CREATE TEMP TABLE x6_terms (term text PRIMARY KEY);
-- X6-TERMS-BEGIN
INSERT INTO x6_terms (term) VALUES
  ('kernel.identity_demographic'), ('identity_demographic'),
  ('kernel.identity_demographic_erasure'), ('identity_demographic_erasure'),
  ('venue.holder_mix_snapshot'), ('venue.holder_mix_bucket'), ('holder_mix'),
  ('gender_identity'), ('another_gender_identity'), ('prefer_not_to_say'), ('non_binary'),
  ('holders_responded'), ('holder_count'), ('suppression_reason'),
  ('phone_number'), ('full_name'), ('stripe_payment_intent_id'), ('stripe_charge_id'),
  ('stripe_customer_id'), ('stripe_connect_account_ref'), ('payment_method_id'),
  ('pin_hash'), ('device_boot_id'), ('wallet_balance'), ('is_verified_seller'),
  ('stripe_onboarding_complete'), ('residency_region'), ('kyc_ref'),
  ('ownership_log_id'), ('credential_id'), ('signing_key_id'), ('scan_device_id'),
  -- 2026-09-02 (package 088): the native dispute / checkout Stripe-reference spellings (R-40, R-37)
  ('stripe_dispute_ref'), ('stripe_charge_ref'), ('stripe_pi_ref'), ('payment_intent_ref');
-- X6-TERMS-END

CREATE TEMP TABLE x6_prohibited (rel text PRIMARY KEY, oid oid);
INSERT INTO x6_prohibited (rel) VALUES
  ('kernel.identity_demographic'), ('kernel.identity_demographic_erasure'),
  ('venue.holder_mix_snapshot'), ('venue.holder_mix_bucket');
UPDATE x6_prohibited SET oid = to_regclass(rel)::oid;

-- ── the closure walker (R2): catalog ∪ text ∪ trigger hops, views through pg_rewrite ──
CREATE FUNCTION pg_temp.x6_closure(p_seeds oid[], p_maxiter int, OUT procs oid[], OUT rels oid[], OUT iters int)
LANGUAGE plpgsql AS $w$
DECLARE
  v_c oid[] := p_seeds; v_r oid[] := '{}'; v_prev_c oid[]; v_prev_r oid[]; v_p oid; v_tok text; v_def text;
  v_schema text; v_name text; v_r2 oid;
BEGIN
  iters := 0;
  LOOP
    iters := iters + 1;
    IF iters > p_maxiter THEN RAISE EXCEPTION 'x6 closure did not converge within % iterations', p_maxiter; END IF;
    v_prev_c := v_c; v_prev_r := v_r;
    FOREACH v_p IN ARRAY v_prev_c LOOP
      -- catalog hop: pg_depend edges from the procedure
      SELECT coalesce(array_agg(DISTINCT d.refobjid), '{}') INTO STRICT v_c
        FROM (SELECT unnest(v_c) AS refobjid
              UNION SELECT d.refobjid FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=v_p AND d.refclassid='pg_proc'::regclass) d;
      SELECT coalesce(array_agg(DISTINCT d.refobjid), '{}') INTO STRICT v_r
        FROM (SELECT unnest(v_r) AS refobjid
              UNION SELECT d.refobjid FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=v_p AND d.refclassid='pg_class'::regclass) d;
      -- trigger limb: a trigger function reaches its table without naming it
      SELECT coalesce(array_agg(DISTINCT x), '{}') INTO STRICT v_r
        FROM (SELECT unnest(v_r) AS x UNION SELECT t.tgrelid FROM pg_trigger t WHERE t.tgfoid = v_p) s;
      -- text hop over the definition: every schema-qualified identifier, resolved with the pinned search_path
      v_def := CASE WHEN (SELECT p.prokind FROM pg_proc p WHERE p.oid = v_p) = 'f' THEN pg_get_functiondef(v_p) ELSE '' END;
      -- unquoted identifiers FOLD to lower case (so Kernel.Identity_Demographic is the prohibited
      -- relation) and quoted ones are taken verbatim: both spellings are tokenised.
      FOR v_tok IN SELECT DISTINCT lower(m[1]) FROM regexp_matches(v_def, '([a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*)', 'gi') m
                   UNION SELECT DISTINCT m[1] || '.' || m[2] FROM regexp_matches(v_def, '"([^"]+)"\s*\.\s*"([^"]+)"', 'g') m LOOP
        v_schema := split_part(v_tok, '.', 1); v_name := split_part(v_tok, '.', 2);
        IF v_schema IN ('pg_catalog','information_schema','pg_temp') THEN CONTINUE; END IF;
        v_r2 := to_regclass(v_tok)::oid;
        IF v_r2 IS NOT NULL THEN v_r := array(SELECT DISTINCT x FROM unnest(v_r || v_r2) x); END IF;
        v_c := array(SELECT DISTINCT x FROM unnest(v_c || coalesce((SELECT array_agg(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                                                                        WHERE n.nspname=v_schema AND p.proname=v_name), '{}')) x);
      END LOOP;
    END LOOP;
    -- view expansion through the rewrite rule (catalog), never through the view's text
    FOR v_p IN SELECT unnest(v_r) LOOP
      IF (SELECT c.relkind FROM pg_class c WHERE c.oid=v_p) IN ('v','m') THEN
        v_r := array(SELECT DISTINCT x FROM (SELECT unnest(v_r) x UNION
                 SELECT d.refobjid FROM pg_rewrite rw JOIN pg_depend d ON d.classid='pg_rewrite'::regclass AND d.objid=rw.oid
                  WHERE rw.ev_class=v_p AND d.refclassid='pg_class'::regclass AND d.refobjid<>v_p) s);
        v_c := array(SELECT DISTINCT x FROM (SELECT unnest(v_c) x UNION
                 SELECT d.refobjid FROM pg_rewrite rw JOIN pg_depend d ON d.classid='pg_rewrite'::regclass AND d.objid=rw.oid
                  WHERE rw.ev_class=v_p AND d.refclassid='pg_proc'::regclass) s);
      END IF;
    END LOOP;
    EXIT WHEN v_c <@ v_prev_c AND v_r <@ v_prev_r;   -- fixed point
  END LOOP;
  procs := v_c; rels := v_r;
END $w$;

-- ============================================================================
-- SECTION A — NON-VACUITY (the floors from supabase/ci/x6_floors.env)
-- ============================================================================
SELECT is((SELECT count(*)::int FROM x6_entry_points), 13, 'A1: exactly 13 entry points (X6_MIN_ENTRY_POINTS — D-X6-a)');
SELECT is((SELECT count(*)::int FROM x6_entry_points WHERE oid IS NULL), 0, 'A2: every entry point resolves to a live pg_proc (an unresolvable name is a failure, never a skip)');
SELECT ok((SELECT count(*) FROM x6_terms) >= 36, 'A3: the term list is not truncated (X6_MIN_FORBIDDEN_TERMS; 088 added the four native Stripe-reference spellings)');
SELECT is((SELECT count(*)::int FROM x6_prohibited WHERE oid IS NULL), 0, 'A4: all four prohibited relations resolve (a NULL would make the intersection trivially empty)');

-- ============================================================================
-- SECTION B — T-RPC-CRM-14: no DIRECT reference, text limb AND catalog limb
-- ============================================================================
SELECT is((SELECT count(*)::int FROM x6_entry_points e CROSS JOIN x6_terms t
            WHERE (CASE WHEN e.oid IS NOT NULL THEN pg_get_functiondef(e.oid) END) ~* ('\m' || replace(t.term, '.', '\.') || '\M')
              AND position('-- x6-allow: naming-only' IN pg_get_functiondef(e.oid)) = 0), 0,
  'B1: text limb — no entry point''s definition mentions any forbidden term (X-6; §12 27)');
SELECT is((SELECT count(*)::int FROM pg_depend d JOIN x6_entry_points e ON e.oid = d.objid AND d.classid='pg_proc'::regclass
            JOIN x6_prohibited p ON p.oid = d.refobjid AND d.refclassid='pg_class'::regclass), 0,
  'B2: catalog limb — no entry point has a pg_depend edge to a prohibited relation');
SELECT is((SELECT count(*)::int FROM x6_entry_points e
            WHERE pg_get_functiondef(e.oid) ~* '(identity_demographic|holder_mix|gender_identity)'), 0,
  'B3: §10.3 (a) verbatim — the nine-name regex over all thirteen (superset of the spec''s nine)');
-- positive control for the TEXT limb: the same predicate over a probe body that names a term must hit.
CREATE FUNCTION venue.__x6_text_probe() RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$ BEGIN RETURN length('holder_mix'); END $f$;
SELECT is((SELECT count(*)::int FROM x6_terms t
            WHERE pg_get_functiondef('venue.__x6_text_probe()'::regprocedure) ~* ('\m' || replace(t.term, '.', '\.') || '\M')), 1,
  'B4: text-limb positive control — a body naming one forbidden term is matched exactly once by the B1 predicate (the limb can see)');

-- ============================================================================
-- SECTION C — T-RPC-CRM-15: the TRANSITIVE closure is disjoint from the prohibited set
-- ============================================================================
CREATE TEMP TABLE x6_cl AS SELECT * FROM pg_temp.x6_closure((SELECT array_agg(oid) FROM x6_entry_points), 32);
SELECT ok((SELECT iters FROM x6_cl) <= 32, 'C1: the closure converged (X6_MAX_CLOSURE_ITERS)');
SELECT ok((SELECT cardinality(procs) FROM x6_cl) >= 16, 'C2: |C| >= X6_MIN_CLOSURE_PROCS — the walk left the seed set (' || (SELECT cardinality(procs) FROM x6_cl) || ' procs)');
SELECT ok((SELECT cardinality(rels) FROM x6_cl) >= 12, 'C3: |R| >= X6_MIN_CLOSURE_RELS — relations were reached (' || (SELECT cardinality(rels) FROM x6_cl) || ' rels)');
SELECT is((SELECT count(*)::int FROM x6_prohibited p WHERE p.oid = ANY ((SELECT rels FROM x6_cl)::oid[])), 0,
  'C4: T-RPC-CRM-15 — R ∩ P = ∅: no helper, view or nested function on any export path reaches a demographic relation');
SELECT ok('venue.export_job'::regclass::oid = ANY ((SELECT rels FROM x6_cl)::oid[]) AND 'kernel.admin_audit'::regclass::oid = ANY ((SELECT rels FROM x6_cl)::oid[])
       AND 'kernel.org_member'::regclass::oid = ANY ((SELECT rels FROM x6_cl)::oid[]) AND 'venue.staff_role'::regclass::oid = ANY ((SELECT rels FROM x6_cl)::oid[]),
  'C5: the closure contains the relations the surface must read (job row, audit, the two grant tables) — the walk is not vacuous');
-- depth witness: l1 → l2 → l3 → target, reached ONLY by a 3-hop text walk
CREATE TABLE venue.__x6_probe_target (id int);
CREATE FUNCTION venue.__x6_probe_l3() RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$ BEGIN RETURN (SELECT count(*) FROM venue.__x6_probe_target); END $f$;
CREATE FUNCTION venue.__x6_probe_l2() RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$ BEGIN RETURN venue.__x6_probe_l3(); END $f$;
CREATE FUNCTION venue.__x6_probe_l1() RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$ BEGIN RETURN venue.__x6_probe_l2(); END $f$;
SELECT ok('venue.__x6_probe_target'::regclass::oid = ANY ((pg_temp.x6_closure((SELECT array_agg(oid) FROM x6_entry_points) || 'venue.__x6_probe_l1()'::regprocedure::oid, 32)).rels),
  'C6: depth witness — a target three plpgsql hops below a seed is reached (a walk that stops at hop 1 or 2 fails here)');
-- view witness: reached only through pg_rewrite expansion
CREATE TABLE venue.__x6_probe_target2 (id int);
CREATE VIEW venue.__x6_probe_view AS SELECT id FROM venue.__x6_probe_target2;
CREATE FUNCTION venue.__x6_probe_v1() RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$ BEGIN RETURN (SELECT count(*) FROM venue.__x6_probe_view); END $f$;
SELECT ok('venue.__x6_probe_target2'::regclass::oid = ANY ((pg_temp.x6_closure(ARRAY['venue.__x6_probe_v1()'::regprocedure::oid], 32)).rels),
  'C7: view witness — a base table reached only through a view''s rewrite rule is in R');
-- poison pill (positive control): a helper that DOES read a prohibited relation, called from a wrapper
CREATE FUNCTION venue.__x6_poison_helper() RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$ BEGIN RETURN (SELECT count(*) FROM kernel.identity_demographic); END $f$;
CREATE FUNCTION venue.__x6_poison_wrap() RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$ BEGIN RETURN venue.__x6_poison_helper(); END $f$;
SELECT ok((SELECT count(*) FROM x6_prohibited p WHERE p.oid = ANY ((pg_temp.x6_closure(ARRAY['venue.__x6_poison_wrap()'::regprocedure::oid], 32)).rels)) = 1,
  'C8: T-VERIFY-X6-05 positive control — the closure check FAILS as required when a nested helper reads kernel.identity_demographic');
-- the same poison spelled in MIXED CASE and QUOTED — both must be caught (case folding / quoted identifiers)
CREATE FUNCTION venue.__x6_poison_mixed() RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$ BEGIN RETURN (SELECT count(*) FROM Kernel.Identity_Demographic); END $f$;
CREATE FUNCTION venue.__x6_poison_quoted() RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$ BEGIN RETURN (SELECT count(*) FROM "venue"."holder_mix_snapshot"); END $f$;
SELECT ok((SELECT count(*) FROM x6_prohibited p WHERE p.oid = ANY ((pg_temp.x6_closure(ARRAY['venue.__x6_poison_mixed()'::regprocedure::oid], 32)).rels)) = 1
       AND (SELECT count(*) FROM x6_prohibited p WHERE p.oid = ANY ((pg_temp.x6_closure(ARRAY['venue.__x6_poison_quoted()'::regprocedure::oid], 32)).rels)) = 1,
  'C8b: positive controls — a mixed-case spelling and a quoted spelling of a prohibited relation are BOTH caught by the walker');
SELECT is((SELECT count(*)::int FROM x6_prohibited p WHERE p.oid = ANY ((SELECT rels FROM x6_cl)::oid[])), 0,
  'C9: … while the REAL closure (computed before the probes existed) stays clean — the probes are outside it');

-- ============================================================================
-- SECTION D — T-RPC-CRM-19: no dynamic SQL anywhere in the closure
-- ============================================================================
CREATE TEMP TABLE x6_dyn AS
  SELECT p.oid, p.oid::regprocedure::text AS sig FROM pg_proc p
   WHERE p.oid = ANY ((SELECT procs FROM x6_cl)::oid[])
     AND (p.prosrc ~* '\mEXECUTE\M' OR p.prosrc ~* '\mformat\s*\(' OR p.prosrc ~* '\mquote_ident\s*\('
       OR p.prosrc ~* '\mquote_literal\s*\(' OR p.prosrc ~* '\mquote_nullable\s*\('
       OR p.prosrc ~* '\mto_regclass\s*\(' OR p.prosrc ~* '\mto_regprocedure\s*\(');
SELECT is((SELECT count(*)::int FROM x6_dyn), 0,
  'D1: T-RPC-CRM-19 — no procedure in the export closure assembles SQL at runtime (' || coalesce((SELECT string_agg(sig, ', ') FROM x6_dyn), 'none') || ')');
SELECT ok((SELECT count(*) FROM pg_proc p WHERE p.oid = ANY ((SELECT procs FROM x6_cl)::oid[])) >= 16, 'D2: the scan set is the R2 fixed point, not a name list (floor)');
-- positive control: a helper containing EXECUTE inside a probe closure is detected
CREATE FUNCTION venue.__x6_dyn_helper() RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$ DECLARE v int; BEGIN EXECUTE 'select 1' INTO v; RETURN v; END $f$;
CREATE FUNCTION venue.__x6_dyn_wrap() RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$ BEGIN RETURN venue.__x6_dyn_helper(); END $f$;
SELECT ok((SELECT count(*) FROM pg_proc p WHERE p.oid = ANY ((pg_temp.x6_closure(ARRAY['venue.__x6_dyn_wrap()'::regprocedure::oid], 32)).procs) AND p.prosrc ~* '\mEXECUTE\M') = 1,
  'D3: positive control — an EXECUTE one hop below a seed is caught by the closure-scoped scan');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='venue' AND p.proname='build_export_rows'
              AND (p.prosrc ~* '\mEXECUTE\M' OR p.prosrc ~* '\mformat\s*\(' OR p.prosrc ~* '\mquote_ident\s*\(')), 0,
  'D4: T-RPC-CRM-02 — build_export_rows itself contains no EXECUTE / format( / quote_ident(');

-- ============================================================================
-- SECTION E — the reader enumerations (§10.4; §12 25/26) and ownership (OR-1)
-- ============================================================================
SELECT is((SELECT count(*)::int FROM x6_entry_points e
            WHERE pg_get_functiondef(e.oid) ~* 'identity_demographic'), 0,
  'E1: §12 25 — no export function is among the readers of kernel.identity_demographic');
SELECT is((SELECT count(*)::int FROM x6_entry_points e
            WHERE pg_get_functiondef(e.oid) ~* 'holder_mix'), 0,
  'E2: §12 26 — no export function is among the readers of the holder-mix rollup');
SELECT ok((SELECT bool_and(p.prosecdef AND p.proowner = 'postgres'::regrole AND 'search_path=""' = ANY (coalesce(p.proconfig,'{}')))
             FROM pg_proc p JOIN x6_entry_points e ON e.oid=p.oid),
  'E3: OR-1 — every entry point is a postgres-owned SECURITY DEFINER with an EMPTY pinned search_path (no second definer owner exists)');
SELECT is((SELECT count(*)::int FROM pg_roles WHERE rolname='crm_export_builder'), 0,
  'E4: OR-1 — the crm_export_builder role is NOT created');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN x6_entry_points e ON e.oid=p.oid WHERE p.prolang = (SELECT oid FROM pg_language WHERE lanname='sql')), 0,
  'E5: every entry point is PL/pgSQL — the text limb (B1/C4) is the load-bearing cover for each (R2 table), and R8''s dynamic-SQL ban (D1) is therefore not defence-in-depth');

SELECT * FROM finish();
ROLLBACK;

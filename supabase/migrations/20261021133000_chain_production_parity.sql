-- ============================================================================
-- 20261021133000_chain_production_parity.sql — registry 173 (pgTAP 243). BE-37 F7 (R-1), S1 (R-2), S4 (R-3).
--
-- DRAFT. OWNER-GATED. Applied nowhere. A BYTE-LEVEL NO-OP ON PRODUCTION: against production's shape this file
--   executes no DDL statement at all — it reads the catalog, finds production's shape and returns. It takes no lock
--   on public.profiles or public.payments, writes nothing (no transaction id is ever assigned; it succeeds under
--   default_transaction_read_only=on) and changes no catalog row (proof: private-evidence/A-sprint-20261021/a173/03:
--   fingerprint.py + fpdiff.py and an extended catalog read on a production-replay clone, identical to an untouched
--   clone down to every catalog row's xmin and relfilenode). The naive unconditional form (ADD COLUMN IF NOT EXISTS /
--   CREATE INDEX IF NOT EXISTS / DROP COLUMN IF EXISTS / CREATE OR REPLACE with the identical text) is NOT a no-op
--   there: it takes ACCESS EXCLUSIVE on profiles and payments and rewrites handle_new_user's pg_proc row (03b N1).
--   It changes environments built from the repo chain (CI, local rehearsal, a branch, the sandbox if it is in the
--   chain's shape) so that they match production on three items.
--
-- SOURCE OF TRUTH = PRODUCTION (BE-37 §3.1 production-body rule). Read 2026-10-21 from a clone of
--   a_sprint_prod_template (the 10-15 production dump + 154-156 applied from production's own bytes; fingerprint-equal
--   to A's read-only production catalog snapshot of 2026-10-21 for every function, table column list and ACL —
--   replay/30_fpdiff_replay_vs_prod.txt). Column defaults, column ACLs and index definitions are not in the 10-21
--   snapshot; they are the replay's (= production as of the 10-15 dump; BE-37 limit 1).
--
-- F7  public.handle_new_user() (trigger function of auth.users on_auth_user_created).
--     Production: md5(pg_get_functiondef) c29bf692b5227d9185a264dc65cc31f6 (stable 10-13, 10-15, 10-21),
--     md5(prosrc) faf4c1844c9e27238050efddba46303f: inserts (id, full_name, display_name, avatar_url) from
--     raw_user_meta_data — full_name; display_name falling back to full_name; avatar_url — each coalesced to ''.
--     Chain bfc5cf97: md5 30bf73f28d7cde7398261676a02aac43 (000_baseline_schema.sql:21 + 0660's search_path),
--     inserts (id) only, so no chain-built environment ever filled names or avatars on sign-up. No migration or
--     rollback file on any ref held production's body (BE-37 F7, F-BASELINE-HANDLE-NEW-USER-1). The text below is
--     pg_get_functiondef's output from the production replay, byte for byte (its md5 is c29bf692…); header,
--     SECURITY DEFINER, search_path and ACL are already identical on both sides (postgres + service_role EXECUTE on
--     production and the local chain), and CREATE OR REPLACE keeps whatever ACL it finds: the postcondition checks the
--     ACL is unchanged rather than equal to a constant, since a CI stack's function default privileges may differ. Consequence on the chain (production's behaviour, now testable): a sign-up
--     whose display_name is over 50 characters (or full_name over 100) aborts the auth.users insert
--     (profiles_display_name_length / profiles_full_name_length, present on both sides) — owner decision O-6.
-- S1  public.profiles Stripe status columns, production-only (PAYMENTS_AUDIT_REPORT §F SQL, run in the Dashboard;
--     in the 040 snapshot and the 10-13/10-15 dumps):
--       stripe_connect_status  text    NOT NULL DEFAULT 'not_started'::text   (production attnum 14)
--       stripe_payouts_enabled boolean NOT NULL DEFAULT false                 (production attnum 15)
--       stripe_charges_enabled boolean NOT NULL DEFAULT false                 (production attnum 16)
--       idx_profiles_stripe_connect_id: CREATE INDEX … USING btree (stripe_connect_id) WHERE (stripe_connect_id IS NOT NULL)
--     Column ACLs: none in production (attacl NULL; anon/authenticated hold no privilege on them; service_role through
--     its table grant). ADD COLUMN creates no column ACL, so the chain gets exactly that; nothing is granted here.
--     Why: create-connect-account (index.ts:285-292) and stripe-webhook account.updated (index.ts:929-940) on
--     origin/release/production-gate-20260918 (identical at bfc5cf97) write the three columns in the SAME update as
--     stripe_onboarding_complete. On the chain that update failed (undefined column), so a seller never became
--     onboarded and could not list (036/038); the webhook ACKs and Stripe does not retry. 243 B8-B10 run both update
--     shapes as service_role: RED on the chain without 173, GREEN with it.
-- S4  public.payments.stripe_client_secret, chain-only (000_baseline_schema.sql:989, vendored from schema.sql).
--     Production has no such column. Every ref grepped 2026-10-21 (all 280 origin refs: SQL, edge functions, app,
--     web, admin console, packages, tests; and the landing-page repo): no writer; no reader in any SQL, edge function,
--     app, web or console code; no function body on the chain or the production replay names it except the strip.
--     The only mentions are ops.payment_json's key strip (to_jsonb(p) - 'stripe_client_secret', KEPT: removing an
--     absent key is a no-op), 182 B12 (asserts the strip; still passes), two TypeScript type declarations
--     (packages/types/src/index.ts:194, src/types/index.ts:211 — no code reads the field; their removal is R-3's
--     separate no-number code change, not in this file), the vendored schema.sql/000 text and docs. In the chain it
--     has no pg_depend dependents, no policy, view or function references it as a column. anon and authenticated could
--     SELECT/INSERT/UPDATE it through the payments table grant. Dropped only when every stored value is NULL (refused
--     otherwise), so the rollback's re-added all-NULL column restores the data exactly.
--
-- CONDITIONAL BY DESIGN (the 123/124 parity style; BE-37 §3.1 rule 2). One catalog read classifies the database:
--   PRODUCTION SHAPE  the three columns exist with production's exact type, NOT NULL, default and no column ACL;
--                     idx_profiles_stripe_connect_id has production's exact definition; handle_new_user has
--                     production's body, SECURITY DEFINER and search_path; payments.stripe_client_secret is absent.
--                     -> no DDL at all (also the state after 173 on the chain, so a re-run is a no-op).
--   CHAIN SHAPE       none of the three columns and no idx_profiles_stripe_connect_id; handle_new_user has the
--                     chain's id-only body (prosrc 7946dc44c2a7ac3bc0a09cbb6a2a5db9), SECURITY DEFINER, search_path;
--                     payments.stripe_client_secret exists as text, nullable, no default, and holds no non-NULL value.
--                     -> the DDL below, then postconditions that the result is production's shape.
--   ANYTHING ELSE     -> RAISE before any DDL; nothing changes. A mixed state means 173 cannot know what it would be
--                     replacing, and its rollback could not know what to restore.
--   The all-or-nothing classification is what makes the rollback exact: after 173 every environment looks like
--   production for these items, and the one durable difference is column order — columns 173 adds are appended after
--   stripe_onboarding_complete and stripe_customer_id, whereas production's three precede both (attnums 14-16 < 20,
--   21). The rollback reads that order to decide whether 173 changed anything in the database it runs in.
--   ORDER vs R-5c (O-1): if production's idx_profiles_stripe_connect_id is replaced before 173 is applied there, 173
--   refuses on production (by design); R-5c written after 173 must change the index on both sides.
--
-- NOT TOUCHED (owner decisions): profiles.is_admin (O-2), profiles.trust_status_override and its CHECK (O-3), every
--   constraint — including the chain-only UNIQUE profiles_stripe_connect_id_key (S3 / O-1 R-5c; the chain now carries it
--   AND production's partial index, redundant until R-5c) and the 10 production-only duplicate CHECKs (S16 / O-7) —
--   column order (S20), and every other BE-37 row. No data row is written. No grant, policy or trigger changes.
-- GATE-2 census (public) unchanged: tables 35, functions 126 (handle_new_user redefined in place), policies 37,
--   triggers 49; indexes are not counted. supabase/ci/expected_grants.txt unchanged: it is the table-level matrix
--   (information_schema.role_table_grants), and adding or dropping a column changes no table grant; the CI
--   profiles check (no client table grant, client column SELECT > 0) is unaffected because the new columns carry no
--   client grant. assert_public_table_grant_decisions.sql unchanged (no new table or function).
--   Test 020's assertions 7-8 become non-vacuous for the three Stripe status columns (and pass).
-- ROLLBACK: supabase/rollbacks/20261021133000_chain_production_parity_rollback.sql — restores the pre-173 state of the
--   database it runs in: on production (and any production-lineage copy) it executes no DDL; on a chain-lineage
--   database it drops the three columns and the index, restores the chain's id-only handle_new_user and re-adds
--   payments.stripe_client_secret (text, all NULL). It refuses anything that is not 173's exact post-state.
-- VERIFY (read-only; expect c29bf692b5227d9185a264dc65cc31f6 | 3 | idx_profiles_stripe_connect_id | 0):
--   select md5(pg_get_functiondef('public.handle_new_user()'::regprocedure)),
--          (select count(*) from pg_attribute where attrelid = 'public.profiles'::regclass and not attisdropped
--             and attname in ('stripe_connect_status','stripe_payouts_enabled','stripe_charges_enabled')),
--          to_regclass('public.idx_profiles_stripe_connect_id'),
--          (select count(*) from pg_attribute where attrelid = 'public.payments'::regclass and not attisdropped
--             and attname = 'stripe_client_secret');
-- FAILURE BEHAVIOUR: one transaction; the classification RAISEs before any DDL, and any postcondition failure rolls
--   all of it back. On the chain path ALTER TABLE takes a brief ACCESS EXCLUSIVE lock on profiles and on payments
--   (no rewrite: constant defaults, DROP COLUMN only marks the attribute) and CREATE INDEX a SHARE lock on profiles;
--   lock_timeout 3s, so it fails cleanly rather than queue behind traffic. On production no statement locks either table.
-- OWNER APPROVAL POINT: prepared and tested locally only (A sprint 2026-10-21, item a173). Applying it anywhere,
--   production included, is a separate owner approval.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $m173$
DECLARE
  c_prod_src   constant text := 'faf4c1844c9e27238050efddba46303f';  -- production handle_new_user prosrc
  c_chain_src  constant text := '7946dc44c2a7ac3bc0a09cbb6a2a5db9';  -- chain bfc5cf97 handle_new_user prosrc
  c_cols       constant text := 'stripe_charges_enabled:boolean:true:false:<none>,'
                                 'stripe_connect_status:text:true:''not_started''::text:<none>,'
                                 'stripe_payouts_enabled:boolean:true:false:<none>';
  c_idx        constant text := 'CREATE INDEX idx_profiles_stripe_connect_id ON public.profiles USING btree (stripe_connect_id) WHERE (stripe_connect_id IS NOT NULL)';
  v_cols       text;     -- the three columns as found, name order: name:type:notnull:default:acl
  v_ncols      int;
  v_idx        text;     -- pg_get_indexdef of idx_profiles_stripe_connect_id, or NULL
  v_hnu        text;     -- handle_new_user prosrc md5 | secdef | config, or NULL
  v_secret     text;     -- payments.stripe_client_secret type:notnull:default, or NULL
  v_secret_nn  bigint := 0;
  v_late       int;
  v_acl        text;     -- handle_new_user's ACL before any DDL: 173 must leave it exactly as found
BEGIN
  SELECT string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull || ':'
                    || coalesce(pg_get_expr(d.adbin, d.adrelid), '<none>') || ':'
                    || coalesce(array_to_string(a.attacl, ','), '<none>'), ',' ORDER BY a.attname),
         count(*)
    INTO v_cols, v_ncols
    FROM pg_catalog.pg_attribute a
    LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
   WHERE a.attrelid = 'public.profiles'::regclass AND a.attnum > 0 AND NOT a.attisdropped
     AND a.attname IN ('stripe_connect_status', 'stripe_payouts_enabled', 'stripe_charges_enabled');
  SELECT pg_catalog.pg_get_indexdef(i.indexrelid) INTO v_idx
    FROM pg_catalog.pg_index i
   WHERE i.indexrelid = to_regclass('public.idx_profiles_stripe_connect_id') AND i.indrelid = 'public.profiles'::regclass;
  SELECT md5(p.prosrc) || '|' || p.prosecdef || '|' || coalesce(array_to_string(p.proconfig, ';'), '<none>'),
         coalesce(array_to_string(p.proacl, ','), '<default>')
    INTO v_hnu, v_acl
    FROM pg_catalog.pg_proc p WHERE p.oid = to_regprocedure('public.handle_new_user()');
  SELECT format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull || ':' || coalesce(pg_get_expr(d.adbin, d.adrelid), '<none>')
    INTO v_secret
    FROM pg_catalog.pg_attribute a
    LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
   WHERE a.attrelid = 'public.payments'::regclass AND a.attname = 'stripe_client_secret' AND a.attnum > 0 AND NOT a.attisdropped;
  IF v_secret IS NOT NULL THEN
    EXECUTE 'SELECT count(stripe_client_secret) FROM public.payments' INTO v_secret_nn;
  END IF;

  IF v_ncols = 3 AND v_cols = c_cols AND v_idx = c_idx
     AND v_hnu = c_prod_src || '|true|search_path=public, pg_temp' AND v_secret IS NULL THEN
    RAISE NOTICE '173: production shape found (handle_new_user = production body, the three Stripe status columns and idx_profiles_stripe_connect_id present, payments.stripe_client_secret absent): no change, no DDL executed';
    RETURN;
  END IF;

  IF NOT (v_ncols = 0 AND v_idx IS NULL AND to_regclass('public.idx_profiles_stripe_connect_id') IS NULL
          AND v_hnu = c_chain_src || '|true|search_path=public, pg_temp'
          AND v_secret = 'text:false:<none>' AND v_secret_nn = 0) THEN
    RAISE EXCEPTION '173 REFUSED (nothing changed): neither production''s shape nor the chain''s. Found: Stripe status columns [%] (% of 3); idx_profiles_stripe_connect_id [%]; handle_new_user [%]; payments.stripe_client_secret [%] with % non-NULL value(s)',
      coalesce(v_cols, 'none'), v_ncols, coalesce(v_idx, coalesce(to_regclass('public.idx_profiles_stripe_connect_id')::text, 'none')),
      coalesce(v_hnu, 'absent'), coalesce(v_secret, 'absent'), v_secret_nn
      USING ERRCODE = 'P0001',
            HINT = 'Production: ' || c_prod_src || '|true|search_path=public, pg_temp, the three columns, the index, no secret column. Chain bfc5cf97: ' || c_chain_src || ', none of them, the secret column empty.';
  END IF;

  -- ── chain shape: make it production's ─────────────────────────────────────
  -- S1: production's exact columns, in production's relative order; no grant (production has no column ACL on them).
  ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS stripe_connect_status  text    NOT NULL DEFAULT 'not_started'::text,
    ADD COLUMN IF NOT EXISTS stripe_payouts_enabled boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS stripe_charges_enabled boolean NOT NULL DEFAULT false;
  CREATE INDEX IF NOT EXISTS idx_profiles_stripe_connect_id ON public.profiles USING btree (stripe_connect_id) WHERE (stripe_connect_id IS NOT NULL);
  -- S4: the chain-only column (verified empty above).
  ALTER TABLE public.payments DROP COLUMN IF EXISTS stripe_client_secret;
  -- F7: production's handle_new_user, pg_get_functiondef from the production replay byte for byte (md5 c29bf692…).
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  insert into public.profiles (id, full_name, display_name, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'display_name', new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'avatar_url', '')
  )
  on conflict (id) do nothing;

  return new;
end;
$function$;

  -- ── postconditions: production's shape, and the lineage marker the rollback reads ──
  SELECT string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull || ':'
                    || coalesce(pg_get_expr(d.adbin, d.adrelid), '<none>') || ':'
                    || coalesce(array_to_string(a.attacl, ','), '<none>'), ',' ORDER BY a.attname)
    INTO v_cols
    FROM pg_catalog.pg_attribute a
    LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
   WHERE a.attrelid = 'public.profiles'::regclass AND a.attnum > 0 AND NOT a.attisdropped
     AND a.attname IN ('stripe_connect_status', 'stripe_payouts_enabled', 'stripe_charges_enabled');
  SELECT count(*) INTO v_late
    FROM pg_catalog.pg_attribute a
   WHERE a.attrelid = 'public.profiles'::regclass AND NOT a.attisdropped
     AND a.attname IN ('stripe_connect_status', 'stripe_payouts_enabled', 'stripe_charges_enabled')
     AND a.attnum > ALL (SELECT b.attnum FROM pg_catalog.pg_attribute b
                          WHERE b.attrelid = 'public.profiles'::regclass AND NOT b.attisdropped
                            AND b.attname IN ('stripe_onboarding_complete', 'stripe_customer_id'))
     AND (SELECT count(*) FROM pg_catalog.pg_attribute c WHERE c.attrelid = 'public.profiles'::regclass AND NOT c.attisdropped
            AND c.attname IN ('stripe_onboarding_complete', 'stripe_customer_id')) = 2;   -- both lineage markers exist
  IF v_cols IS DISTINCT FROM c_cols
     OR (SELECT pg_catalog.pg_get_indexdef('public.idx_profiles_stripe_connect_id'::regclass)) IS DISTINCT FROM c_idx
     OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute WHERE attrelid = 'public.payments'::regclass
                   AND attname = 'stripe_client_secret' AND NOT attisdropped)
     OR (SELECT md5(p.prosrc) || '|' || p.prosecdef || '|' || array_to_string(p.proconfig, ';') || '|'
               || coalesce(array_to_string(p.proacl, ','), '<default>')
           FROM pg_catalog.pg_proc p WHERE p.oid = 'public.handle_new_user()'::regprocedure)
        IS DISTINCT FROM c_prod_src || '|true|search_path=public, pg_temp|' || v_acl   -- CREATE OR REPLACE keeps the ACL
     OR v_late <> 3 THEN
    RAISE EXCEPTION '173 postcondition failed (rolled back): columns [%], late=% of 3', v_cols, v_late USING ERRCODE = 'P0001';
  END IF;
  RAISE NOTICE '173: chain shape converted to production''s: handle_new_user md5 %, three Stripe status columns (appended), idx_profiles_stripe_connect_id, payments.stripe_client_secret dropped',
    md5(pg_get_functiondef('public.handle_new_user()'::regprocedure));
END
$m173$;

COMMIT;

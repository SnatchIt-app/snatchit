-- ============================================================================
-- supabase/rollbacks/20261030094000_venue_api_venues_settings_columns_rollback.sql
-- Rollback for registry 195: restores 159's seven-column venue_api.venues (20261021120000:105)
-- VERBATIM, with its options, its comment and its single grant (SELECT to authenticated).
-- A view cannot drop columns in place, so this is DROP VIEW + CREATE VIEW in one transaction.
-- Guards: the pre-flight accepts 195's view (definition md5 383f313b…, ten columns) or 159's
-- (27cc812f…, seven columns — an idempotent re-run) and refuses if any object depends on the view
-- (a DROP would fail or need CASCADE; this file never cascades). The post-check asserts 159's
-- md5, the seven columns, the options, the ACL and the comment.
-- WARNING, stated plainly: rolling back removes address / capacity_hint / timezone from the view,
-- so the venue dashboard's Settings page loses its read path again. Redeploy the dashboard build
-- that does not read them BEFORE running this, or prefer a forward fix.
-- ============================================================================
BEGIN;

DO $pf$
DECLARE v_sp text := current_setting('search_path'); v_md5 text; v_cols text; v_deps int;
BEGIN
  IF to_regclass('venue_api.venues') IS NULL THEN
    RAISE EXCEPTION 'ROLLBACK_195_REFUSED: venue_api.venues is missing';
  END IF;
  PERFORM set_config('search_path', '', true);
  v_md5 := md5(pg_get_viewdef('venue_api.venues'::regclass));
  PERFORM set_config('search_path', v_sp, true);
  SELECT string_agg(a.attname, ',' ORDER BY a.attnum) INTO v_cols
    FROM pg_attribute a WHERE a.attrelid = 'venue_api.venues'::regclass AND a.attnum > 0 AND NOT a.attisdropped;
  IF NOT ((v_md5 = '383f313b3c15e6291e6fab9aa6e456ca'
           AND v_cols = 'venue_id,org_id,name,neighborhood,approval_status,created_at,updated_at,address,capacity_hint,timezone')
       OR (v_md5 = '27cc812fb0b82be5162ca61e7ee0d0a6'
           AND v_cols = 'venue_id,org_id,name,neighborhood,approval_status,created_at,updated_at')) THEN
    RAISE EXCEPTION 'ROLLBACK_195_REFUSED: venue_api.venues is neither 195''s nor 159''s view (md5 %, columns %)', v_md5, v_cols;
  END IF;
  SELECT count(*) INTO v_deps
    FROM pg_depend d JOIN pg_rewrite r ON r.oid = d.objid
   WHERE d.refobjid = 'venue_api.venues'::regclass AND r.ev_class <> 'venue_api.venues'::regclass;
  IF v_deps <> 0 THEN
    RAISE EXCEPTION 'ROLLBACK_195_REFUSED: % object(s) depend on venue_api.venues — resolve them first (no CASCADE)', v_deps;
  END IF;
END $pf$;

DROP VIEW venue_api.venues;
CREATE VIEW venue_api.venues
  WITH (security_invoker = true, security_barrier = true) AS
  SELECT v.venue_id, v.org_id, v.name, v.neighborhood, v.approval_status, v.created_at, v.updated_at
    FROM catalog.venue v;
COMMENT ON VIEW venue_api.venues IS 'catalog.venue, granted columns only; caller''s RLS applies.';
REVOKE ALL ON venue_api.venues FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON venue_api.venues TO authenticated;

DO $pc$
DECLARE v_sp text := current_setting('search_path'); v_md5 text; v_cols text; v_opts text; v_acl text; v_cmt text;
BEGIN
  PERFORM set_config('search_path', '', true);
  v_md5 := md5(pg_get_viewdef('venue_api.venues'::regclass));
  PERFORM set_config('search_path', v_sp, true);
  SELECT string_agg(a.attname, ',' ORDER BY a.attnum) INTO v_cols
    FROM pg_attribute a WHERE a.attrelid = 'venue_api.venues'::regclass AND a.attnum > 0 AND NOT a.attisdropped;
  SELECT array_to_string(array(SELECT o FROM unnest(c.reloptions) o ORDER BY o), ','),
         (SELECT string_agg(e.entry, ',' ORDER BY e.entry)
            FROM (SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type AS entry
                    FROM aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
                   WHERE a.grantee <> c.relowner) e),
         obj_description(c.oid, 'pg_class')
    INTO v_opts, v_acl, v_cmt
    FROM pg_class c WHERE c.oid = 'venue_api.venues'::regclass;
  IF v_md5 <> '27cc812fb0b82be5162ca61e7ee0d0a6'
     OR v_cols <> 'venue_id,org_id,name,neighborhood,approval_status,created_at,updated_at'
     OR v_opts <> 'security_barrier=true,security_invoker=true'
     OR v_acl IS DISTINCT FROM 'authenticated:SELECT'
     OR v_cmt IS DISTINCT FROM 'catalog.venue, granted columns only; caller''s RLS applies.' THEN
    RAISE EXCEPTION 'ROLLBACK_195_POSTCHECK_FAILED: md5 %, columns %, options %, acl %, comment %', v_md5, v_cols, v_opts, v_acl, v_cmt;
  END IF;
END $pc$;

COMMIT;

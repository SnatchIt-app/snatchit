-- ============================================================================
-- 20261030094000_venue_api_venues_settings_columns.sql — registry 195 / pgTAP 263.
-- (D writes; A allocated 2026-10-30 after the production Settings finding; E reviews.)
-- DRAFT: applied nowhere.
--
-- WHAT THIS MIGRATION IS. `CREATE OR REPLACE VIEW venue_api.venues` with three columns APPENDED
-- LAST — address, capacity_hint, timezone — after 159's seven, which keep their names, types and
-- order. Options re-stated (security_invoker = true, security_barrier = true). CREATE OR REPLACE
-- keeps the view's ACL (SELECT to authenticated only) and its comment; the post-flight asserts
-- both. No other object, no grant, nothing in `public`; Gate-2 counters unchanged.
--
-- WHY. The venue dashboard's Settings page has no read path for a room's address, capacity hint
-- or time zone ("not wired to the database yet" in production): 159's view (20261021120000:105)
-- projects only venue_id, org_id, name, neighborhood, approval_status, created_at, updated_at.
-- catalog.venue carries all three, and `authenticated` already holds column SELECT on every
-- catalog.venue column (078's list + 162's timezone; read on a production-equal clone), so the
-- view's own contract — "catalog.venue, granted columns only; caller's RLS applies" — already
-- covers them. `catalog` is never exposed to PostgREST, so this view is the path.
--
-- WHAT A CALLER CAN NOW READ. Exactly what catalog.venue's RLS already lets them read, three more
-- columns per visible row: security_invoker means the caller's own column grants and policies
-- apply (catalog_venue_sel_anon: approved venues; _sel_org: the org's members; _sel_venue: the
-- venue's staff). A non-member sees no draft/pending/archived room; any authenticated user sees
-- an APPROVED room's address, capacity hint and time zone — the same rows and columns they could
-- already SELECT from catalog.venue in SQL. anon has no USAGE on venue_api (unchanged).
--
-- Discipline: PRE-FLIGHT accepts 159's view (seven columns, definition md5 27cc812f…) or 195's
-- own (ten columns, re-apply); the definition md5 is read under search_path = '' (pinned: a view's
-- deparse depends on the path). POST-FLIGHT asserts the ten columns in order, both options, the
-- ACL, the owner (postgres, 159's applied owner), the comment and 195's definition md5. The rollback restores 159's seven-column view
-- (DROP + CREATE: a view cannot drop columns in place), re-granting and re-commenting it, and
-- refuses if anything depends on the view.
-- ============================================================================
BEGIN;

-- ── PRE-FLIGHT ───────────────────────────────────────────────────────────────
DO $pf$
DECLARE v_sp text := current_setting('search_path'); v_md5 text; v_cols text;
BEGIN
  IF to_regclass('venue_api.venues') IS NULL THEN
    RAISE EXCEPTION 'MIGRATION_195_REFUSED: venue_api.venues is missing (159 not applied)';
  END IF;
  PERFORM set_config('search_path', '', true);
  v_md5 := md5(pg_get_viewdef('venue_api.venues'::regclass));
  PERFORM set_config('search_path', v_sp, true);
  SELECT string_agg(a.attname, ',' ORDER BY a.attnum) INTO v_cols
    FROM pg_attribute a WHERE a.attrelid = 'venue_api.venues'::regclass AND a.attnum > 0 AND NOT a.attisdropped;
  IF NOT ((v_md5 = '27cc812fb0b82be5162ca61e7ee0d0a6'
           AND v_cols = 'venue_id,org_id,name,neighborhood,approval_status,created_at,updated_at')
       OR (v_md5 = '383f313b3c15e6291e6fab9aa6e456ca'
           AND v_cols = 'venue_id,org_id,name,neighborhood,approval_status,created_at,updated_at,address,capacity_hint,timezone')) THEN
    RAISE EXCEPTION 'MIGRATION_195_REFUSED: venue_api.venues is neither 159''s nor 195''s view (md5 %, columns %) — re-examine the order', v_md5, v_cols;
  END IF;
END $pf$;

CREATE OR REPLACE VIEW venue_api.venues
  WITH (security_invoker = true, security_barrier = true) AS
  SELECT v.venue_id, v.org_id, v.name, v.neighborhood, v.approval_status, v.created_at, v.updated_at,
         v.address, v.capacity_hint, v.timezone
    FROM catalog.venue v;

-- ── POST-FLIGHT ──────────────────────────────────────────────────────────────
DO $pc$
DECLARE v_sp text := current_setting('search_path'); v_md5 text; v_cols text; v_opts text; v_acl text; v_cmt text; v_owner text;
BEGIN
  PERFORM set_config('search_path', '', true);
  v_md5 := md5(pg_get_viewdef('venue_api.venues'::regclass));
  PERFORM set_config('search_path', v_sp, true);
  SELECT string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' ORDER BY a.attnum) INTO v_cols
    FROM pg_attribute a WHERE a.attrelid = 'venue_api.venues'::regclass AND a.attnum > 0 AND NOT a.attisdropped;
  SELECT array_to_string(array(SELECT o FROM unnest(c.reloptions) o ORDER BY o), ','),
         (SELECT string_agg(e.entry, ',' ORDER BY e.entry)
            FROM (SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type AS entry
                    FROM aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
                   WHERE a.grantee <> c.relowner) e),
         obj_description(c.oid, 'pg_class'),
         c.relowner::regrole::text
    INTO v_opts, v_acl, v_cmt, v_owner
    FROM pg_class c WHERE c.oid = 'venue_api.venues'::regclass;
  IF v_cols <> 'venue_id:uuid,org_id:uuid,name:text,neighborhood:text,approval_status:text,created_at:timestamp with time zone,updated_at:timestamp with time zone,address:text,capacity_hint:integer,timezone:text' THEN
    RAISE EXCEPTION 'POSTFLIGHT_195_FAILED: venue_api.venues columns are %', v_cols;
  END IF;
  IF v_opts <> 'security_barrier=true,security_invoker=true' THEN
    RAISE EXCEPTION 'POSTFLIGHT_195_FAILED: venue_api.venues options are %', v_opts;
  END IF;
  IF v_acl IS DISTINCT FROM 'authenticated:SELECT' THEN
    RAISE EXCEPTION 'POSTFLIGHT_195_FAILED: venue_api.venues ACL is % (must be SELECT to authenticated only)', v_acl;
  END IF;
  IF v_owner IS DISTINCT FROM 'postgres' THEN
    RAISE EXCEPTION 'POSTFLIGHT_195_FAILED: venue_api.venues is owned by % (159''s owner is postgres; the ACL check excludes the owner)', v_owner;
  END IF;
  IF v_cmt IS DISTINCT FROM 'catalog.venue, granted columns only; caller''s RLS applies.' THEN
    RAISE EXCEPTION 'POSTFLIGHT_195_FAILED: venue_api.venues comment changed (%)', v_cmt;
  END IF;
  IF v_md5 <> '383f313b3c15e6291e6fab9aa6e456ca' THEN
    RAISE EXCEPTION 'POSTFLIGHT_195_FAILED: venue_api.venues definition md5 % is not 195''s — this file was modified', v_md5;
  END IF;
END $pc$;

COMMIT;

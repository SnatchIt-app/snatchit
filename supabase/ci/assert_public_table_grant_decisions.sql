-- ============================================================================
-- supabase/ci/assert_public_table_grant_decisions.sql — CI ASSERTION ONLY.
--
-- THIS IS NOT A MIGRATION AND MUST NEVER BE APPLIED TO PRODUCTION.
-- It grants nothing and revokes nothing. Run it against the freshly-replayed CI
-- database AFTER parity_grants.sql. It raises an exception, and therefore fails
-- the build, if the replay contains a public table whose client-grant posture
-- nobody has recorded a decision for.
--
-- ---------------------------------------------------------------------------
-- THE HOLE THIS CLOSES (finding SEC-2)
-- ---------------------------------------------------------------------------
-- parity_grants.sql + expected_grants.txt compare the fresh replay against a
-- hand-transcribed production snapshot. That comparison is sound for tables
-- that exist on both sides — and VACUOUS for a table that exists on neither.
--
-- Add a new table in a Phase-2 migration and watch what happens:
--   * fresh replay  — the migration creates it; no migration grants anything;
--                     the CI stack has no TABLE entries in pg_default_acl, so
--                     the table appears with ZERO client grants;
--   * fixture       — nobody added a line for it, so it expects zero;
--   * diff          — zero vs zero. GREEN.
--   * production    — pg_default_acl on schema public says otherwise:
--                       public/r/postgres       -> anon=arwdm,    authenticated=arwdm
--                       public/r/supabase_admin -> anon=arwdDxtm, authenticated=arwdDxtm
--                     so the table ships with anon and authenticated holding
--                     SELECT/INSERT/UPDATE/DELETE. Wide open, gate green.
--
-- That is not hypothetical. It is exactly how public.webhook_retries came to
-- grant anon and authenticated full DML in production (finding SEC-1) while
-- migration 069 line 22 revoked them and the ledger recorded 069 as executed.
--
-- The default ACLs are vendor-managed and are NOT removed — Supabase's
-- provisioning depends on them. So the countermeasure is: every public table
-- must have a recorded decision, and an unrecorded one FAILS CLOSED.
--
-- ---------------------------------------------------------------------------
-- HOW TO SATISFY IT WHEN YOU ADD A TABLE
-- ---------------------------------------------------------------------------
-- 1. In the migration that creates the table, end with an explicit
--        REVOKE ALL ON public.<table> FROM PUBLIC, anon, authenticated;
--    followed by only the grants the table actually needs. This is mandatory —
--    see SNATCH_IT_ENGINEERING_STANDARDS.md §5. Without it the default ACL has
--    already granted the client roles by the time your migration finishes.
-- 2. Add one row to the manifest below.
-- 3. If the decision is anything other than 'no-client-access', also add the
--    corresponding line(s) to expected_grants.txt and the GRANT to
--    parity_grants.sql, so the existing diff keeps covering it.
--
-- Decisions:
--   no-client-access  deny-all. RLS on, service_role only. ASSERTED below:
--                     anon and authenticated must hold zero table privileges.
--   client-dml        anon and/or authenticated hold DML; covered by the
--                     expected_grants.txt diff.
--   client-read       client roles hold SELECT only; covered by that diff.
--   column-grants     no table-level client grant at all; access is column-
--                     scoped. Only public.profiles. A table-level grant here
--                     would silently defeat 041/052/062/068 — the existing
--                     privilege-parity step asserts that separately.
-- ============================================================================

\set ON_ERROR_STOP on

CREATE TEMP TABLE _grant_decisions (table_name text PRIMARY KEY, decision text NOT NULL);

INSERT INTO _grant_decisions (table_name, decision) VALUES
  -- deny-all: RLS on, zero policies, service_role only.
  ('admin_users',                  'no-client-access'),
  ('auth_audit_sweep_state',       'no-client-access'),
  ('dispute_resolutions',          'no-client-access'),
  ('rate_limits',                  'no-client-access'),
  ('stripe_webhook_events',        'no-client-access'),
  ('transfer_notifications',       'no-client-access'),
  -- webhook_retries is the table this whole assertion exists because of.
  ('webhook_retries',              'no-client-access'),

  -- column-scoped only; never a table-level client grant.
  ('profiles',                     'column-grants'),

  -- read-only to the client; all writes go through RPCs.
  ('notifications',                'client-read'),
  ('transfers',                    'client-read'),

  -- client DML, bounded by RLS.
  ('ambassador_applications',      'client-dml'),
  ('bids',                         'client-dml'),
  ('disputes',                     'client-dml'),
  ('investor_leads',               'client-dml'),
  ('listings',                     'client-dml'),
  ('notification_preferences',     'client-dml'),
  ('payments',                     'client-dml'),
  ('payout_decisions',             'client-dml'),
  ('payout_policy',                'client-dml'),
  ('push_tokens',                  'client-dml'),
  ('reports',                      'client-dml'),
  ('saved_listings',               'client-dml'),
  ('seller_flags',                 'client-dml'),
  ('seller_risk_scores',           'client-dml'),
  ('stripe_connect_archive',       'client-dml'),
  ('user_blocks',                  'client-dml'),
  ('venue_partnership_inquiries',  'client-dml');

-- ---------------------------------------------------------------------------
-- 0. SELF-TEST of the fail-closed logic.
--
-- Every other check here is a negative assertion — "nothing unrecorded exists"
-- — and a negative assertion is exactly the kind that passes when it is broken.
-- If the comparison below were subtly wrong (a join that drops rows, a NOT IN
-- against a NULL), this file would report a clean sheet forever and the hole it
-- was written to close would be open again with a green check over it.
--
-- So: run the same comparison against a synthetic list containing one known
-- table and one table that is definitely not in the manifest, and require it to
-- flag exactly the second one. If the detector cannot catch a planted unknown,
-- the build fails here rather than pretending.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  caught text[];
BEGIN
  SELECT coalesce(array_agg(t.tname ORDER BY t.tname), '{}')
    INTO caught
    FROM (VALUES ('listings'), ('__planted_unknown_table__')) AS t(tname)
   WHERE NOT EXISTS (
     SELECT 1 FROM _grant_decisions d WHERE d.table_name = t.tname
   );

  IF caught IS DISTINCT FROM ARRAY['__planted_unknown_table__'] THEN
    RAISE EXCEPTION
      'GUARD SELF-TEST FAILED: unknown-table detection returned %, expected exactly {__planted_unknown_table__}. The fail-closed check is not working; do not trust a green result from this file.',
      caught;
  END IF;

  RAISE NOTICE 'self-test OK: planted unknown table was detected.';
END $$;

-- ---------------------------------------------------------------------------
-- 1. FAIL CLOSED — a public table with no recorded decision.
-- This is the assertion that a Phase-2 table cannot slip past. Views, foreign
-- tables and partitions are excluded deliberately: pg_tables lists ordinary and
-- partitioned tables, which is the object class the default ACL applies to.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  missing text;
BEGIN
  SELECT string_agg(t.tablename, ', ' ORDER BY t.tablename)
    INTO missing
    FROM pg_tables t
   WHERE t.schemaname = 'public'
     AND NOT EXISTS (
       SELECT 1 FROM _grant_decisions d WHERE d.table_name = t.tablename
     );

  IF missing IS NOT NULL THEN
    RAISE EXCEPTION
      E'Public table(s) with NO recorded client-grant decision: %.\n'
      'On production, pg_default_acl grants anon and authenticated full DML to every new table in public, so this table ships OPEN while CI stays green (that is finding SEC-1 / SEC-2 exactly).\n'
      'Fix: (1) end the creating migration with REVOKE ALL ON public.<table> FROM PUBLIC, anon, authenticated plus only the grants it needs; (2) add a row to the manifest in supabase/ci/assert_public_table_grant_decisions.sql; (3) if it is client-reachable, add it to expected_grants.txt and parity_grants.sql too.',
      missing;
  END IF;

  RAISE NOTICE 'every public table has a recorded grant decision.';
END $$;

-- ---------------------------------------------------------------------------
-- 2. FAIL CLOSED the other way — a manifest row for a table that is gone.
-- A stale entry is how the manifest rots into decoration: it keeps asserting a
-- decision about nothing while a renamed table slips in unrecorded next to it.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  stale text;
BEGIN
  SELECT string_agg(d.table_name, ', ' ORDER BY d.table_name)
    INTO stale
    FROM _grant_decisions d
   WHERE NOT EXISTS (
     SELECT 1 FROM pg_tables t
      WHERE t.schemaname = 'public' AND t.tablename = d.table_name
   );

  IF stale IS NOT NULL THEN
    RAISE EXCEPTION
      'Manifest records a decision for table(s) that no longer exist in public: %. Remove the row, or restore the table. A manifest that describes tables that are not there stops describing the ones that are.',
      stale;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 3. Enforce the strongest decision. 'no-client-access' is the only value that
-- makes a checkable promise on its own (the others are covered by the
-- expected_grants.txt diff), so it is checked here: those tables must hold zero
-- table-level privileges for anon and authenticated.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  leaked text;
BEGIN
  SELECT string_agg(format('%s -> %s: %s', g.table_name, g.grantee, g.privilege_type),
                    '; ' ORDER BY g.table_name, g.grantee, g.privilege_type)
    INTO leaked
    FROM information_schema.role_table_grants g
    JOIN _grant_decisions d ON d.table_name = g.table_name
   WHERE g.table_schema = 'public'
     AND d.decision = 'no-client-access'
     AND g.grantee IN ('anon', 'authenticated', 'PUBLIC');

  IF leaked IS NOT NULL THEN
    RAISE EXCEPTION
      'Table(s) recorded as no-client-access hold client privileges: %. Either the migration is missing its REVOKE, or the decision in the manifest is wrong. Do not "fix" this by changing the manifest without establishing that a client genuinely needs the access.',
      leaked;
  END IF;

  RAISE NOTICE 'all no-client-access tables are clean.';
END $$;

DROP TABLE _grant_decisions;

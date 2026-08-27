-- ============================================================================
-- supabase/ci/assert_public_table_grant_decisions.sql — CI ASSERTION ONLY.
--
-- THIS IS NOT A MIGRATION AND MUST NEVER BE APPLIED TO PRODUCTION.
-- It grants nothing and revokes nothing. Run it against the freshly-replayed CI
-- database AFTER parity_grants.sql. It raises an exception, and therefore fails
-- the build, if the replay contains a public TABLE or FUNCTION whose client
-- authorization posture nobody has recorded a decision for.
--
-- THE FILENAME UNDERSTATES THE SCOPE, deliberately and unavoidably. This file
-- began as a table-only gate; review finding F2 established that the FUNCTION
-- half is the more exposed one, and Part B was added. It was not renamed to
-- match, because migration 073 §6 references this exact path and migrations are
-- append-only — 073 is already present at the integration base, so editing even
-- a comment in it trips the immutability check in migrations-guard.yml.
-- Renaming would have left a dangling reference inside the very migration that
-- introduced the rule. Read the scope from this header, not from the filename.
--
-- ---------------------------------------------------------------------------
-- THE HOLE THIS CLOSES (finding SEC-2)
-- ---------------------------------------------------------------------------
-- parity_grants.sql + expected_grants.txt compare the fresh replay against a
-- hand-transcribed production snapshot. That comparison is sound for objects
-- that exist on both sides — and VACUOUS for one that exists on neither.
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
-- and every public function must have a recorded decision, and an unrecorded
-- one FAILS CLOSED.
--
-- ---------------------------------------------------------------------------
-- WHY FUNCTIONS MATTER MORE THAN TABLES HERE (finding F2)
-- ---------------------------------------------------------------------------
-- The same pg_default_acl carries FUNCTION entries:
--     public/f/postgres       -> anon=X, authenticated=X
--     public/f/supabase_admin -> anon=X, authenticated=X
-- so every new function in public ships anon-EXECUTE, which PostgREST exposes
-- at POST /rest/v1/rpc/<name> — callable by anyone holding the publishable
-- anon key. A new TABLE at least still has RLS in front of it. A new FUNCTION
-- has nothing.
--
-- The failure this closes concretely: a Phase-2 migration adds
-- public.admin_resolve_dispute(uuid, text) and forgets the REVOKE. Fresh replay
-- has no function default-ACL entry, so proacl is unset and nothing complains;
-- no manifest row, so nothing complains. Green. In production the default ACL
-- grants anon=X and the admin RPC answers to the anon key.
--
-- The standing rule in SNATCH_IT_ENGINEERING_STANDARDS.md §5 is not sufficient
-- on its own and this repo has the receipts: 069 followed the rule and the
-- revoke still did not land (SEC-1), migration 073 §5 exists purely to sweep
-- five functions that migration 067 missed, and
-- 20260730212326_ambassador_applications_website_form.sql creates a function
-- with no revoke at all. Rules get skipped. This does not.
--
-- KEY POINT — the function check is NOT vacuous on the CI replay, unlike a
-- naive table check. has_function_privilege('anon', oid, 'EXECUTE') returns
-- TRUE when proacl IS NULL, because a NULL ACL means "defaults apply" and the
-- default for a function IS EXECUTE TO PUBLIC — and every role, anon included,
-- is implicitly a member of PUBLIC. So a function created without a REVOKE
-- reads as anon-executable on the fresh replay too, and this file catches it
-- there. That is why the posture below is asserted directly rather than merely
-- recorded.
--
-- ---------------------------------------------------------------------------
-- HOW TO SATISFY IT
-- ---------------------------------------------------------------------------
-- Adding a TABLE:
--   1. End the creating migration with
--          REVOKE ALL ON public.<table> FROM PUBLIC, anon, authenticated;
--      plus only the grants it needs (mandatory — STANDARDS §5).
--   2. Add a row to the table manifest below.
--   3. If it is client-reachable, add the line(s) to expected_grants.txt and
--      the GRANT to parity_grants.sql so the existing diff keeps covering it.
--
-- Adding a FUNCTION:
--   1. End the creating migration with
--          REVOKE EXECUTE ON FUNCTION public.<fn>(<argtypes>) FROM PUBLIC, anon, authenticated;
--      then GRANT EXECUTE to exactly the roles that call it. A bare
--      REVOKE FROM PUBLIC is NOT enough once explicit role grants exist —
--      migration 067's header records that being learned the hard way.
--   2. Add a row to the function manifest below, keyed
--      name(argtypes) — argument TYPES only, no parameter names, so a rename
--      cannot silently orphan the entry.
--
-- Table decisions:
--   no-client-access  deny-all. RLS on, service_role only. ASSERTED: anon and
--                     authenticated must hold zero table privileges.
--   client-dml        anon and/or authenticated hold DML; covered by the
--                     expected_grants.txt diff.
--   client-read       client roles hold SELECT only; covered by that diff.
--   column-grants     no table-level client grant at all; access is column-
--                     scoped. Only public.profiles. A table-level grant here
--                     would silently defeat 041/052/062/068 — the existing
--                     privilege-parity step asserts that separately.
--
-- Function decisions (all ASSERTED directly against the replay catalog):
--   no-client-execute        neither anon nor authenticated may EXECUTE, no
--                            PUBLIC grant, and proacl must not be defaulted.
--   authenticated-execute    authenticated may EXECUTE; anon and PUBLIC may not.
--   anon-execute             deliberately reachable signed-out. CURRENTLY ZERO
--                            MEMBERS — after migration 073 no function in public
--                            is anon-executable except the known gap below.
--                            Adding a member needs written justification in the
--                            migration: it publishes an unauthenticated RPC.
--   public-execute-known-gap a tracked, accepted exception. Exactly one member,
--                            asserted by name. Not a category to grow.
-- ============================================================================

\set ON_ERROR_STOP on

-- ===========================================================================
-- PART A — TABLES
-- ===========================================================================

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
-- A0. SELF-TEST of the fail-closed logic.
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
      'GUARD SELF-TEST FAILED (tables): unknown-object detection returned %, expected exactly {__planted_unknown_table__}. The fail-closed check is not working; do not trust a green result from this file.',
      caught;
  END IF;

  RAISE NOTICE 'self-test OK (tables): planted unknown table was detected.';
END $$;

-- ---------------------------------------------------------------------------
-- A1. FAIL CLOSED — a public table with no recorded decision.
-- Views, foreign tables and partitions are excluded deliberately: pg_tables
-- lists ordinary and partitioned tables, which is the object class the default
-- ACL applies to.
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
      'Fix: (1) end the creating migration with REVOKE ALL ON public.<table> FROM PUBLIC, anon, authenticated plus only the grants it needs; (2) add a row to the table manifest in supabase/ci/assert_public_table_grant_decisions.sql; (3) if it is client-reachable, add it to expected_grants.txt and parity_grants.sql too.',
      missing;
  END IF;

  RAISE NOTICE 'every public table has a recorded grant decision.';
END $$;

-- ---------------------------------------------------------------------------
-- A2. FAIL CLOSED the other way — a manifest row for a table that is gone.
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
-- A3. Enforce the strongest table decision. 'no-client-access' is the only
-- value that makes a checkable promise on its own (the others are covered by
-- the expected_grants.txt diff), so it is checked here: those tables must hold
-- zero table-level privileges for anon and authenticated.
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

-- ===========================================================================
-- PART B — FUNCTIONS   (finding F2)
--
-- Keyed on name(argtypes) using pg_catalog.oidvectortypes(proargtypes):
-- argument TYPES only, never parameter names. pg_get_function_identity_arguments
-- would have included the names, so renaming a parameter — a change with no
-- authorization meaning whatsoever — would orphan the manifest row and either
-- fail the build for nothing or, worse, be "fixed" by pasting in a new row
-- while the old one silently became a stale allowance. Types are the identity
-- PostgreSQL itself overloads on, which is why mark_transfer_sent appears
-- twice below and correctly so.
-- ===========================================================================

CREATE TEMP TABLE _function_decisions (fn_sig text PRIMARY KEY, decision text NOT NULL);

INSERT INTO _function_decisions (fn_sig, decision) VALUES
  -- ── no-client-execute ────────────────────────────────────────────────────
  -- Trigger functions, cron/maintenance entry points, and service-role-only
  -- money and webhook internals. Nothing a browser may call.
  ('admin_release_held_payout(uuid, uuid, text)',                    'no-client-execute'),
  ('admin_resolve_dispute(uuid, text, uuid)',                        'no-client-execute'),
  ('apply_auto_release(uuid)',                                       'no-client-execute'),
  ('apply_manual_review(uuid, text, text[])',                        'no-client-execute'),
  ('apply_payout_hold(uuid, timestamp with time zone, text, text[])','no-client-execute'),
  ('auto_finalize_expired_auctions()',                               'no-client-execute'),
  ('check_rate_limit(uuid, text, integer, integer)',                 'no-client-execute'),
  ('claim_stripe_webhook_event(text, text, integer)',                'no-client-execute'),
  ('cleanup_expired_reservations()',                                 'no-client-execute'),
  ('complete_stripe_webhook_event(text)',                            'no-client-execute'),
  ('delete_account_cleanup(uuid)',                                   'no-client-execute'),
  ('dispute_resolutions_append_only()',                              'no-client-execute'),
  ('disputes_set_updated_at()',                                      'no-client-execute'),
  ('enforce_auto_release()',                                         'no-client-execute'),
  ('enforce_transfer_expiry()',                                      'no-client-execute'),
  ('enqueue_notification(uuid, text, text, text, text, text, jsonb)','no-client-execute'),
  ('fail_stripe_webhook_event(text, text)',                          'no-client-execute'),
  ('freeze_transfer_for_dispute(uuid)',                              'no-client-execute'),
  ('get_auto_release_candidates()',                                  'no-client-execute'),
  ('get_disputes_awaiting_refund()',                                 'no-client-execute'),
  ('get_incomplete_webhook_events(integer, integer)',                'no-client-execute'),
  ('get_payout_review_queue()',                                      'no-client-execute'),
  ('guard_listing_identity_columns()',                               'no-client-execute'),
  ('guard_listing_insert_columns()',                                 'no-client-execute'),
  ('guard_listing_state_columns()',                                  'no-client-execute'),
  ('guard_proof_status()',                                           'no-client-execute'),
  ('guard_transfer_state_columns()',                                 'no-client-execute'),
  ('handle_new_user()',                                              'no-client-execute'),
  ('handle_new_user_notification_prefs()',                           'no-client-execute'),
  ('is_admin()',                                                     'no-client-execute'),
  ('mark_transfer_reversed(text)',                                   'no-client-execute'),
  ('notify_auction_won_inbox()',                                     'no-client-execute'),
  ('notify_bid_inbox()',                                             'no-client-execute'),
  ('notify_bid_placed()',                                            'no-client-execute'),
  ('notify_moderation_event()',                                      'no-client-execute'),
  ('notify_outbid()',                                                'no-client-execute'),
  ('notify_transfer_created_inbox()',                                'no-client-execute'),
  ('notify_transfer_event()',                                        'no-client-execute'),
  ('notify_transfer_state_inbox()',                                  'no-client-execute'),
  ('record_transfer_payout(uuid, text)',                             'no-client-execute'),
  ('refresh_all_seller_risk_scores()',                               'no-client-execute'),
  ('refresh_seller_risk_score(uuid)',                                'no-client-execute'),
  ('request_is_service_role()',                                      'no-client-execute'),
  ('reset_transfer_guard_bypass()',                                  'no-client-execute'),
  ('resolve_transfer_dispute(uuid, text, uuid, text, text)',         'no-client-execute'),
  ('set_updated_at()',                                               'no-client-execute'),
  ('sweep_auth_password_changes()',                                  'no-client-execute'),
  ('sync_listing_current_bid()',                                     'no-client-execute'),
  ('validate_and_apply_bid()',                                       'no-client-execute'),

  -- ── authenticated-execute ────────────────────────────────────────────────
  -- Signed-in RPCs. Each derives caller identity from auth.uid() internally;
  -- anon is stripped so an unauthenticated key cannot reach them.
  ('buyer_dispute_transfer(uuid, uuid, text, text, text)',           'authenticated-execute'),
  ('can_create_listing(uuid)',                                       'authenticated-execute'),
  ('cancel_listing(uuid, uuid)',                                     'authenticated-execute'),
  ('complete_auction_payment(uuid, uuid)',                           'authenticated-execute'),
  ('confirm_transfer_received(uuid, uuid)',                          'authenticated-execute'),
  ('ensure_transfer_exists(uuid, uuid)',                             'authenticated-execute'),
  ('finalize_auction(uuid)',                                         'authenticated-execute'),
  ('get_my_profile()',                                               'authenticated-execute'),
  ('get_profile_trust_stats(uuid)',                                  'authenticated-execute'),
  -- is_blocked_by_me / is_winner: 073 §5 stripped anon+PUBLIC and kept
  -- authenticated. is_blocked_by_me is a designed listings-feed RLS predicate
  -- and its user_blocks table is live; if that predicate ships, authenticated
  -- MUST hold EXECUTE or every signed-in listing read fails.
  ('is_blocked_by_me(uuid)',                                         'authenticated-execute'),
  ('is_winner(uuid, uuid)',                                          'authenticated-execute'),
  ('mark_listing_sold(uuid, uuid)',                                  'authenticated-execute'),
  ('mark_transfer_sent(uuid, uuid)',                                 'authenticated-execute'),
  ('mark_transfer_sent(uuid, uuid, text)',                           'authenticated-execute'),
  ('mark_transfer_viewed(uuid)',                                     'authenticated-execute'),
  -- phone_verified() is used in the `listings: auth insert` RLS WITH CHECK —
  -- authenticated MUST retain EXECUTE or listing creation breaks (067 group C).
  ('phone_verified()',                                               'authenticated-execute'),
  ('release_reservation(uuid, uuid)',                                'authenticated-execute'),
  ('reserve_buy_now(uuid, uuid, integer)',                           'authenticated-execute'),
  ('set_transfer_delivery_info(uuid, text, text)',                   'authenticated-execute'),

  -- ── public-execute-known-gap ─────────────────────────────────────────────
  -- Exactly one member. See B4 for the full reasoning and the exit condition.
  ('set_ambassador_application_updated_at()',                        'public-execute-known-gap');

-- ---------------------------------------------------------------------------
-- B0. SELF-TEST — same discipline as A0, on the function detector.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  caught text[];
BEGIN
  SELECT coalesce(array_agg(t.sig ORDER BY t.sig), '{}')
    INTO caught
    FROM (VALUES ('get_my_profile()'), ('__planted_unknown_fn__(uuid, text)')) AS t(sig)
   WHERE NOT EXISTS (
     SELECT 1 FROM _function_decisions d WHERE d.fn_sig = t.sig
   );

  IF caught IS DISTINCT FROM ARRAY['__planted_unknown_fn__(uuid, text)'] THEN
    RAISE EXCEPTION
      'GUARD SELF-TEST FAILED (functions): unknown-object detection returned %, expected exactly {__planted_unknown_fn__(uuid, text)}. The fail-closed check is not working; do not trust a green result from this file.',
      caught;
  END IF;

  RAISE NOTICE 'self-test OK (functions): planted unknown function was detected.';
END $$;

-- ---------------------------------------------------------------------------
-- B1. FAIL CLOSED — a public function with no recorded decision.
-- This is the assertion that a Phase-2 RPC cannot slip past. Aggregates and
-- window functions are included deliberately: prokind is not filtered, because
-- the default ACL does not filter on it either.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  missing text;
BEGIN
  SELECT string_agg(sig, ', ' ORDER BY sig) INTO missing FROM (
    SELECT p.proname || '(' || pg_catalog.oidvectortypes(p.proargtypes) || ')' AS sig
      FROM pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace
  ) f
  WHERE NOT EXISTS (SELECT 1 FROM _function_decisions d WHERE d.fn_sig = f.sig);

  IF missing IS NOT NULL THEN
    RAISE EXCEPTION
      E'Public function(s) with NO recorded EXECUTE decision: %.\n'
      'On production, pg_default_acl grants anon EXECUTE on every new function in public, and PostgREST publishes it at POST /rest/v1/rpc/<name> — so this function answers to the publishable anon key while CI stays green. A new function is MORE exposed than a new table: a table still has RLS in front of it.\n'
      'Fix: (1) end the creating migration with REVOKE EXECUTE ON FUNCTION public.<fn>(<argtypes>) FROM PUBLIC, anon, authenticated, then GRANT EXECUTE to exactly the roles that call it (a bare REVOKE FROM PUBLIC is not enough once explicit role grants exist — see migration 067); (2) add a row to the function manifest in supabase/ci/assert_public_table_grant_decisions.sql.',
      missing;
  END IF;

  RAISE NOTICE 'every public function has a recorded EXECUTE decision.';
END $$;

-- ---------------------------------------------------------------------------
-- B2. FAIL CLOSED the other way — a manifest row for a function that is gone.
-- Same rot risk as A2, with an extra edge: a changed argument TYPE creates a
-- new signature. The old row would linger as a stale allowance while the new
-- overload arrives unrecorded, so both halves must move together.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  stale text;
BEGIN
  SELECT string_agg(d.fn_sig, ', ' ORDER BY d.fn_sig)
    INTO stale
    FROM _function_decisions d
   WHERE NOT EXISTS (
     SELECT 1 FROM pg_proc p
      WHERE p.pronamespace = 'public'::regnamespace
        AND p.proname || '(' || pg_catalog.oidvectortypes(p.proargtypes) || ')' = d.fn_sig
   );

  IF stale IS NOT NULL THEN
    RAISE EXCEPTION
      'Function manifest records a decision for signature(s) that no longer exist in public: %. Either the function was dropped (remove the row) or its argument types changed (update the row AND check the new signature got its REVOKE).',
      stale;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- B3. Enforce the recorded posture against the live catalog.
--
-- This is the half that is genuinely non-vacuous on the fresh replay:
-- has_function_privilege('anon', oid, 'EXECUTE') is TRUE for a function whose
-- proacl is NULL, because NULL means "defaults apply" and the function default
-- is EXECUTE TO PUBLIC — of which anon is a member. So a missing REVOKE is
-- visible HERE, on CI, not only in production.
--
-- proacl IS NULL is called out separately anyway, so the failure message names
-- the actual cause ("never revoked") instead of the symptom.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  bad text;
BEGIN
  SELECT string_agg(
           format('%s [%s]: %s', f.sig, f.decision, f.why), E'\n  ' ORDER BY f.sig)
    INTO bad
    FROM (
      SELECT p.proname || '(' || pg_catalog.oidvectortypes(p.proargtypes) || ')' AS sig,
             d.decision,
             concat_ws(', ',
               CASE WHEN p.proacl IS NULL
                    THEN 'proacl is DEFAULTED (never revoked) — this is PUBLIC EXECUTE' END,
               CASE WHEN has_function_privilege('anon', p.oid, 'EXECUTE')
                    THEN 'anon has EXECUTE' END,
               CASE WHEN has_function_privilege('authenticated', p.oid, 'EXECUTE')
                     AND d.decision = 'no-client-execute'
                    THEN 'authenticated has EXECUTE' END,
               CASE WHEN NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')
                     AND d.decision = 'authenticated-execute'
                    THEN 'authenticated LACKS EXECUTE (its callers will 403)' END,
               CASE WHEN EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
                                  WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
                    THEN 'PUBLIC has an explicit EXECUTE grant' END
             ) AS why
        FROM pg_proc p
        JOIN _function_decisions d
          ON d.fn_sig = p.proname || '(' || pg_catalog.oidvectortypes(p.proargtypes) || ')'
       WHERE p.pronamespace = 'public'::regnamespace
         AND d.decision IN ('no-client-execute', 'authenticated-execute')
    ) f
   WHERE f.why <> '';

  IF bad IS NOT NULL THEN
    RAISE EXCEPTION
      E'Function EXECUTE posture does not match the recorded decision:\n  %\n'
      'A function whose proacl is DEFAULTED was created without a REVOKE — in production the pg_default_acl has already granted anon=X and PostgREST is serving it at /rest/v1/rpc/. Fix the migration, not the manifest, unless a client genuinely needs the access.',
      bad;
  END IF;

  RAISE NOTICE 'every recorded function posture matches the catalog.';
END $$;

-- ---------------------------------------------------------------------------
-- B4. The known gap is exactly one function, and it is still the gap.
--
-- public.set_ambassador_application_updated_at() carries PUBLIC + anon +
-- authenticated EXECUTE in both source and production. Migration 073 §5 could
-- not revoke it: the function is created by
-- 20260730212326_ambassador_applications_website_form.sql, a TIMESTAMP-scheme
-- migration that the CLI orders AFTER 073, so it does not exist yet at that
-- point in a rebuild. An unguarded revoke aborts the chain; a guarded one is
-- worse, because it would succeed on production and silently skip on every
-- rebuild — manufacturing exactly the drift 073 exists to remove.
--
-- It is accepted rather than fixed because it RETURNS trigger: PostgreSQL
-- refuses a direct call whoever holds EXECUTE, and trigger firing never
-- consults the privilege. That reasoning is asserted, not assumed —
-- supabase/tests/120_drift_reconciliation.sql pins the return type of all four
-- group-A trigger functions.
--
-- Two ways this fails, both wanted:
--   * a SECOND function claims this decision — the category is not a dumping
--     ground; the next one needs its own analysis;
--   * the gap gets fixed and the manifest is not updated — a stale "known gap"
--     is an allowance nobody is watching any more.
-- Exit condition: revoke it in a timestamp-scheme migration sorting after
-- 20260731224653, then move this row to no-client-execute.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  gaps    text;
  still   boolean;
BEGIN
  SELECT string_agg(fn_sig, ', ' ORDER BY fn_sig) INTO gaps
    FROM _function_decisions WHERE decision = 'public-execute-known-gap';

  IF gaps IS DISTINCT FROM 'set_ambassador_application_updated_at()' THEN
    RAISE EXCEPTION
      'The public-execute-known-gap category must contain exactly set_ambassador_application_updated_at(), but contains: %. It is a tracked exception, not a category to grow — a new entrant needs its own written analysis.',
      coalesce(gaps, '(nothing)');
  END IF;

  SELECT has_function_privilege('anon', p.oid, 'EXECUTE') INTO still
    FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND p.proname = 'set_ambassador_application_updated_at'
     AND pg_catalog.oidvectortypes(p.proargtypes) = '';

  IF still IS NULL THEN
    RAISE EXCEPTION 'set_ambassador_application_updated_at() is missing from public — remove its known-gap row.';
  END IF;

  IF NOT still THEN
    RAISE EXCEPTION
      'set_ambassador_application_updated_at() is no longer anon-executable — the known gap has been CLOSED. Move its manifest row from public-execute-known-gap to no-client-execute, and add it to the trigger-function assertions in supabase/tests/120_drift_reconciliation.sql.';
  END IF;

  RAISE NOTICE 'known gap unchanged: set_ambassador_application_updated_at() (harmless — RETURNS trigger).';
END $$;

DROP TABLE _grant_decisions;
DROP TABLE _function_decisions;

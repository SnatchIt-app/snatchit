-- ============================================================================
-- 20261021134000_revoke_anon_dml.sql — registry 174 (pgTAP 244). A sprint 2026-10-21. DRAFT, owner-gated.
-- Source: sprint-control/LEGACY_CLIENT_API_SURFACE_AUDIT_20261021.md §5 P1, widened to §7's "out of scope, noticed"
-- tables (the same pattern). Evidence: private-evidence/A-sprint-20261021/a174/.
--
-- WHY. anon (the signed-out PostgREST role, i.e. anyone holding the publishable key) holds INSERT/UPDATE/DELETE on
--   14 public tables through Supabase's default ACL (public/r/postgres -> anon=arwdm). Only RLS refuses those writes:
--   every write policy on them compares a row column with auth.uid() (NULL for anon), or the table has no write policy
--   at all. That is one control where two belong: a policy edit that forgets auth.uid() (or a new permissive policy)
--   would open the table to the whole internet. No client of any age writes these tables while signed out.
--
-- WHAT. Exactly the anon write privileges production holds on these tables are revoked; nothing else:
--   REVOKE INSERT, UPDATE, DELETE FROM anon on bids, disputes, listings, notification_preferences, payments,
--     payout_decisions, payout_policy, reports, saved_listings, seller_flags, seller_risk_scores,
--     stripe_connect_archive, user_blocks              (production relacl entry anon=arwdm/postgres -> anon=rm/postgres)
--   REVOKE INSERT, DELETE FROM anon on push_tokens     (anon=adm/postgres -> anon=m/postgres; anon never held UPDATE)
--   RLS, every policy, every authenticated and service_role privilege, every column grant, anon's SELECT and MAINTAIN
--   are untouched. No table, function, policy or trigger is created or dropped (Gate-2 census unchanged).
--
-- KEPT EXACTLY AS THEY ARE (signed-out website forms on snatchitapp.com, POST /rest/v1/<table> with the publishable
--   key, Prefer: return=minimal; each has an INSERT TO anon WITH CHECK (true) policy): ambassador_applications,
--   investor_leads, venue_partnership_inquiries. Their anon grants are not mentioned below.
--
-- CALLERS (this narrows what is accepted, so every producer was enumerated; a174/20-23):
--   current native e46fc203, web a111fb06, console 07100a35, edge functions at release/production-gate-20260918
--   (6f982f36), the website (snatch-it-landing-page af51c25a) and the database itself (anon-executable SECURITY INVOKER
--   functions, trigger functions, auth/storage triggers). Every write to the 14 tables runs with a signed-in user id
--   (native/web: bidder_id/seller_id/user_id/reporter_id/blocker_id = the session user, guarded by an early return when
--   signed out) or a service_role client (edge, scripts). The console writes no public table. The website writes only
--   the three kept tables. No anon-executable invoker function or invoker trigger function writes or locks the 14.
--
-- EFFECT. An anon INSERT on the 14 already failed (42501 'new row violates row-level security policy', or a trigger /
--   policy-function refusal first); it now fails at the grant: 42501 'permission denied for table <t>'. An anon UPDATE
--   or DELETE used to succeed silently on zero rows; it now fails with the same 42501. Client error handling keyed on
--   42501 is unchanged (native push registration.ts, web create-listing.ts / seller-listings.ts match both messages).
--   Not a live hole today, so this is defence in depth, not an incident fix.
--
-- SELF-CHECK (same transaction; any failure RAISEs and the whole file changes nothing):
--   1. anon holds no INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER on the 14 tables, at table or column level
--      (has_table_privilege / has_any_column_privilege, so a grant via PUBLIC or another grantor is caught too);
--   2. nothing else moved: every ACL entry on every public relation and every column ACL equals the snapshot taken at
--      the top of this file, except anon's INSERT/UPDATE/DELETE entries on the 14 tables.
--   Works on production (pre-state above), on the CI replay (anon holds nothing yet: the REVOKEs are no-ops and
--   parity_grants.sql, applied after the chain, now grants anon SELECT only on these tables) and on a chain clone.
--
-- ROLLBACK: supabase/rollbacks/20261021134000_revoke_anon_dml_rollback.sql re-grants exactly the revoked set and
--   verifies anon's relacl entry on each of the 14 equals production's pre-state verbatim. Re-granting restores
--   today's RLS-only posture (every anon write still refused by RLS), not an exploitable hole.
-- CI files moved with this migration: supabase/ci/parity_grants.sql, supabase/ci/expected_grants.txt,
--   supabase/ci/assert_public_table_grant_decisions.sql (A4 anon-write allowlist), supabase/tests/030 (two
--   assertions that pinned the old zero-row behaviour), supabase/tests/244. ci.yml Gate-2 census and suite 162's
--   census pins do not change (no object added or removed).
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ── snapshot: every ACL entry on every public relation and column, before ──
DO $pre174$
BEGIN
  PERFORM set_config('a174.acl_before', (
    SELECT coalesce(jsonb_agg(e ORDER BY e), '[]'::jsonb)::text FROM (
      SELECT jsonb_build_array('rel', c.relname, '', x.grantee::regrole::text, x.grantor::regrole::text, x.privilege_type, x.is_grantable) AS e
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace,
             LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) x
       WHERE n.nspname = 'public' AND c.relkind IN ('r','p','v','m','f')
      UNION ALL
      SELECT jsonb_build_array('col', c.relname, a.attname, x.grantee::regrole::text, x.grantor::regrole::text, x.privilege_type, x.is_grantable)
        FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace,
             LATERAL aclexplode(a.attacl) x
       WHERE n.nspname = 'public' AND c.relkind IN ('r','p','v','m','f') AND a.attnum > 0 AND NOT a.attisdropped
         AND a.attacl IS NOT NULL) s), true);
END
$pre174$;

-- ── the change ──────────────────────────────────────────────────────────────
REVOKE INSERT, UPDATE, DELETE ON TABLE
  public.bids,
  public.disputes,
  public.listings,
  public.notification_preferences,
  public.payments,
  public.payout_decisions,
  public.payout_policy,
  public.reports,
  public.saved_listings,
  public.seller_flags,
  public.seller_risk_scores,
  public.stripe_connect_archive,
  public.user_blocks
FROM anon;
REVOKE INSERT, DELETE ON TABLE public.push_tokens FROM anon;

-- ── self-check ──────────────────────────────────────────────────────────────
DO $post174$
DECLARE
  v_t constant text[] := ARRAY['bids','disputes','listings','notification_preferences','payments','payout_decisions',
                               'payout_policy','push_tokens','reports','saved_listings','seller_flags','seller_risk_scores',
                               'stripe_connect_archive','user_blocks'];
  v_left    text;
  v_before  jsonb := current_setting('a174.acl_before')::jsonb;
  v_after   jsonb;
  v_expect  jsonb;
BEGIN
  -- 1. no anon write-class privilege left on the 14, table or column level
  SELECT string_agg(t || ':' || p, ', ' ORDER BY t, p) INTO v_left
    FROM unnest(v_t) t, unnest(ARRAY['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) p
   WHERE has_table_privilege('anon', ('public.' || t)::regclass, p)
      OR (p IN ('INSERT','UPDATE','REFERENCES') AND has_any_column_privilege('anon', ('public.' || t)::regclass, p));
  IF v_left IS NOT NULL THEN
    RAISE EXCEPTION '174 refused (nothing changed): anon still holds % after the REVOKEs (a grant via PUBLIC, another grantor or a column grant); investigate before applying', v_left
      USING ERRCODE = 'P0001';
  END IF;

  -- 2. nothing else moved
  SELECT coalesce(jsonb_agg(e ORDER BY e), '[]'::jsonb) INTO v_after FROM (
    SELECT jsonb_build_array('rel', c.relname, '', x.grantee::regrole::text, x.grantor::regrole::text, x.privilege_type, x.is_grantable) AS e
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace,
           LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) x
     WHERE n.nspname = 'public' AND c.relkind IN ('r','p','v','m','f')
    UNION ALL
    SELECT jsonb_build_array('col', c.relname, a.attname, x.grantee::regrole::text, x.grantor::regrole::text, x.privilege_type, x.is_grantable)
      FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace,
           LATERAL aclexplode(a.attacl) x
     WHERE n.nspname = 'public' AND c.relkind IN ('r','p','v','m','f') AND a.attnum > 0 AND NOT a.attisdropped
       AND a.attacl IS NOT NULL) s;
  SELECT coalesce(jsonb_agg(e ORDER BY e), '[]'::jsonb) INTO v_expect
    FROM jsonb_array_elements(v_before) e
   WHERE NOT (e->>0 = 'rel' AND e->>1 = ANY (v_t) AND e->>3 = 'anon' AND e->>5 IN ('INSERT','UPDATE','DELETE'));
  IF v_after IS DISTINCT FROM v_expect THEN
    RAISE EXCEPTION '174 refused (nothing changed): an ACL entry other than anon INSERT/UPDATE/DELETE on the 14 tables moved; removed %, added %',
      (SELECT jsonb_agg(e) FROM jsonb_array_elements(v_expect) e WHERE NOT v_after @> jsonb_build_array(e)),
      (SELECT jsonb_agg(e) FROM jsonb_array_elements(v_after) e WHERE NOT v_expect @> jsonb_build_array(e))
      USING ERRCODE = 'P0001';
  END IF;
  RAISE NOTICE '174: anon write privileges revoked on % tables; % ACL entries removed, every other entry unchanged',
    cardinality(v_t), jsonb_array_length(v_before) - jsonb_array_length(v_after);
END
$post174$;

COMMIT;

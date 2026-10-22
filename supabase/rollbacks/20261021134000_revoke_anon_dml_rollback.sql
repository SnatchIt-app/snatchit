-- ============================================================================
-- ROLLBACK for 20261021134000_revoke_anon_dml.sql (registry 174, pgTAP 244). Run only under owner approval.
--
-- TARGET = production's pre-174 state, verbatim (prod_tables.json, A's read-only snapshot 2026-10-21; equal on the
--   a_sprint_prod_template replay): anon's relacl entry on each of the 14 tables is
--     anon=arwdm/postgres  bids, disputes, listings, notification_preferences, payments, payout_decisions,
--                          payout_policy, reports, saved_listings, seller_flags, seller_risk_scores,
--                          stripe_connect_archive, user_blocks
--     anon=adm/postgres    push_tokens
-- APPLIED (174): anon=rm/postgres on the 13, anon=m/postgres on push_tokens.
--
-- GUARDS (first statement; each RAISEs with nothing changed):
--   1. STACKING / PARTIAL: all 14 entries must be in 174's applied state (then this file re-grants) or all 14 already
--      in the target state (a re-run: no-op that re-verifies). A mix is a partial state (a hand re-grant of some
--      tables, or a half-applied rollback): refused, naming each table and its live entry. Any third entry (missing,
--      extra privileges, another grantor, a later change on top of 174) is refused the same way: restoring over it
--      would silently discard it.
--   2. NO HOLE: re-granting is only the pre-174 posture if RLS still refuses every anon write, so RLS must be enabled
--      on all 14 and the 14 INSERT/UPDATE/DELETE/ALL policies on them must be byte-identical to the set 174 was
--      verified against (fingerprint ff86befac58d8b98f9f0bceee26ca878 = production 2026-10-21; no policy admits anon:
--      each compares a column with auth.uid(), and 7 tables have no write policy). If a policy changed since, this
--      file refuses: re-verify with a174/30_probe that no anon write succeeds, and re-pin under owner review.
--
-- WHAT: GRANT INSERT, UPDATE, DELETE ON the 13 TO anon; GRANT INSERT, DELETE ON push_tokens TO anon. Run as the
--   table owner (postgres) so the grantor is postgres, as in production.
-- VERIFY (same transaction; any mismatch RAISEs, so a partial or drifted rollback changes nothing):
--   anon's entry on each of the 14 equals the TARGET text exactly, and every other ACL entry on every public relation
--   and column equals the snapshot taken before the GRANTs.
-- NOT A SECURITY HOLE: the result is exactly today's production posture, where RLS refuses every anon write on these
--   tables (a174/31_probe_pre_174.txt; guard 2 proves the RLS is the same). It reopens nothing production does not
--   already have open today.
-- CI: rolling back the database also needs the repo side reverted (parity_grants.sql, expected_grants.txt, the A4
--   allowlist, tests 030 and 244), i.e. revert the 174 commit; otherwise CI keeps asserting the post-174 surface.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $guard174$
DECLARE
  v_t constant text[] := ARRAY['bids','disputes','listings','notification_preferences','payments','payout_decisions',
                               'payout_policy','push_tokens','reports','saved_listings','seller_flags','seller_risk_scores',
                               'stripe_connect_archive','user_blocks'];
  v_applied int := 0;
  v_target  int := 0;
  v_other   text;
  v_pol     text;
  v_rls     int;
BEGIN
  WITH live AS (
    SELECT t, (SELECT string_agg(a::text, ',') FROM unnest(c.relacl) a WHERE a::text LIKE 'anon=%') AS entry
      FROM unnest(v_t) t JOIN pg_class c ON c.oid = ('public.' || t)::regclass
  ), cls AS (
    SELECT t, entry,
           CASE WHEN t = 'push_tokens' THEN
                  CASE entry WHEN 'anon=m/postgres' THEN 'applied' WHEN 'anon=adm/postgres' THEN 'target' END
                ELSE
                  CASE entry WHEN 'anon=rm/postgres' THEN 'applied' WHEN 'anon=arwdm/postgres' THEN 'target' END
           END AS state
      FROM live
  )
  SELECT count(*) FILTER (WHERE state = 'applied'), count(*) FILTER (WHERE state = 'target'),
         string_agg(format('%s=%s', t, coalesce(entry, '<no anon entry>')), ', ' ORDER BY t) FILTER (WHERE state IS NULL)
    INTO v_applied, v_target, v_other FROM cls;
  IF v_other IS NOT NULL THEN
    RAISE EXCEPTION '174 rollback refused (nothing changed): anon entry is neither 174''s applied state nor production''s pre-state on: %; a change sits on top of 174: resolve it first', v_other
      USING ERRCODE = 'P0001';
  END IF;
  IF v_applied > 0 AND v_target > 0 THEN
    RAISE EXCEPTION '174 rollback refused (nothing changed): partial state, % table(s) already re-granted and % still revoked: %',
      v_target, v_applied,
      (SELECT string_agg(format('%s=%s', t, (SELECT string_agg(a::text, ',') FROM unnest(c.relacl) a WHERE a::text LIKE 'anon=%')), ', ' ORDER BY t)
         FROM unnest(v_t) t JOIN pg_class c ON c.oid = ('public.' || t)::regclass)
      USING ERRCODE = 'P0001';
  END IF;

  SELECT count(*) INTO v_rls FROM unnest(v_t) t JOIN pg_class c ON c.oid = ('public.' || t)::regclass WHERE c.relrowsecurity;
  SELECT md5(string_agg(format('%s|%s|%s|%s|%s|%s|%s', tablename, policyname, cmd, permissive, array_to_string(roles, ','),
                               coalesce(qual, '<null>'), coalesce(with_check, '<null>')), E'\n' ORDER BY tablename, policyname))
    INTO v_pol
    FROM pg_policies
   WHERE schemaname = 'public' AND tablename = ANY (v_t) AND cmd IN ('INSERT','UPDATE','DELETE','ALL');
  IF v_rls <> 14 OR v_pol IS DISTINCT FROM 'ff86befac58d8b98f9f0bceee26ca878' THEN
    RAISE EXCEPTION '174 rollback refused (nothing changed): re-granting anon writes is only safe under the RLS 174 was verified against; RLS enabled on %/14 tables, write-policy fingerprint % (expected ff86befac58d8b98f9f0bceee26ca878)', v_rls, coalesce(v_pol, '<none>')
      USING ERRCODE = 'P0001';
  END IF;

  -- snapshot of every other ACL entry, for the verification below
  PERFORM set_config('a174rb.acl_before', (
    SELECT coalesce(jsonb_agg(e ORDER BY e), '[]'::jsonb)::text FROM (
      SELECT jsonb_build_array('rel', c.relname, '', x.grantee::regrole::text, x.grantor::regrole::text, x.privilege_type, x.is_grantable) AS e
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace,
             LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) x
       WHERE n.nspname = 'public' AND c.relkind IN ('r','p','v','m','f')
         AND NOT (c.relname = ANY (v_t) AND x.grantee = 'anon'::regrole)
      UNION ALL
      SELECT jsonb_build_array('col', c.relname, a.attname, x.grantee::regrole::text, x.grantor::regrole::text, x.privilege_type, x.is_grantable)
        FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace,
             LATERAL aclexplode(a.attacl) x
       WHERE n.nspname = 'public' AND c.relkind IN ('r','p','v','m','f') AND a.attnum > 0 AND NOT a.attisdropped
         AND a.attacl IS NOT NULL) s), true);
  RAISE NOTICE '174 rollback: % table(s) in the applied state, % already restored', v_applied, v_target;
END
$guard174$;

GRANT INSERT, UPDATE, DELETE ON TABLE
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
TO anon;
GRANT INSERT, DELETE ON TABLE public.push_tokens TO anon;

DO $verify174$
DECLARE
  v_t constant text[] := ARRAY['bids','disputes','listings','notification_preferences','payments','payout_decisions',
                               'payout_policy','push_tokens','reports','saved_listings','seller_flags','seller_risk_scores',
                               'stripe_connect_archive','user_blocks'];
  v_bad   text;
  v_after jsonb;
BEGIN
  SELECT string_agg(format('%s=%s', t, coalesce(entry, '<no anon entry>')), ', ' ORDER BY t) INTO v_bad FROM (
    SELECT t, (SELECT string_agg(a::text, ',') FROM unnest(c.relacl) a WHERE a::text LIKE 'anon=%') AS entry
      FROM unnest(v_t) t JOIN pg_class c ON c.oid = ('public.' || t)::regclass) s
   WHERE entry IS DISTINCT FROM CASE WHEN t = 'push_tokens' THEN 'anon=adm/postgres' ELSE 'anon=arwdm/postgres' END;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '174 rollback failed verification (nothing changed): anon entry is not production''s pre-state on: %', v_bad
      USING ERRCODE = 'P0001';
  END IF;
  SELECT coalesce(jsonb_agg(e ORDER BY e), '[]'::jsonb) INTO v_after FROM (
    SELECT jsonb_build_array('rel', c.relname, '', x.grantee::regrole::text, x.grantor::regrole::text, x.privilege_type, x.is_grantable) AS e
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace,
           LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) x
     WHERE n.nspname = 'public' AND c.relkind IN ('r','p','v','m','f')
       AND NOT (c.relname = ANY (v_t) AND x.grantee = 'anon'::regrole)
    UNION ALL
    SELECT jsonb_build_array('col', c.relname, a.attname, x.grantee::regrole::text, x.grantor::regrole::text, x.privilege_type, x.is_grantable)
      FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace,
           LATERAL aclexplode(a.attacl) x
     WHERE n.nspname = 'public' AND c.relkind IN ('r','p','v','m','f') AND a.attnum > 0 AND NOT a.attisdropped
       AND a.attacl IS NOT NULL) s;
  IF v_after IS DISTINCT FROM current_setting('a174rb.acl_before')::jsonb THEN
    RAISE EXCEPTION '174 rollback failed verification (nothing changed): an ACL entry other than anon''s on the 14 tables moved'
      USING ERRCODE = 'P0001';
  END IF;
  RAISE NOTICE '174 rollback verified: anon entries equal production''s pre-state on all 14 tables; every other ACL entry unchanged';
END
$verify174$;

COMMIT;

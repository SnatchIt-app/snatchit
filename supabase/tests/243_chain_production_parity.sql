-- ============================================================================
-- 243_chain_production_parity.sql — registry 173 (20261021133000), BE-37 F7 / S1 / S4.
-- DRAFT suite for a DRAFT migration (owner-gated; a byte-level no-op on production).
--
-- What it pins is PRODUCTION's shape (read 2026-10-21 from the production replay = production's 10-21 catalog
-- snapshot for every fingerprinted object; BE-37 §1.1):
--   F7  public.handle_new_user() — production's body (md5(pg_get_functiondef) c29bf692b5227d9185a264dc65cc31f6,
--       md5(prosrc) faf4c1844c9e27238050efddba46303f): a sign-up copies full_name, display_name (falling back to
--       full_name) and avatar_url from raw_user_meta_data, each coalesced to ''. The chain at bfc5cf97 inserted
--       (id) only (md5 30bf73f28d7cde7398261676a02aac43), so no chain-built environment ever filled them.
--       A display_name over 50 characters aborts the sign-up (profiles_display_name_length, on both sides):
--       today's production behaviour, pinned here until owner decision O-6 says otherwise.
--   S1  public.profiles.stripe_connect_status text NOT NULL DEFAULT 'not_started'::text,
--       stripe_payouts_enabled / stripe_charges_enabled boolean NOT NULL DEFAULT false, no column ACL (clients
--       hold no privilege on them; service_role through its table grant), and the partial index
--       idx_profiles_stripe_connect_id. The edge functions create-connect-account and stripe-webhook
--       (account.updated) write the three columns in the SAME update as stripe_onboarding_complete, so on the
--       chain that whole update failed (undefined column) and a seller never became able to list.
--   S4  public.payments.stripe_client_secret does not exist (chain-only before 173); ops.payment_json keeps its
--       strip of that key (182 B12) as defence in depth.
--
-- Expected results (private-evidence/A-sprint-20261021/a173): production replay clone WITHOUT 173 = all pass
-- (the suite describes production); chain clone (bfc5cf97) WITHOUT 173 = the F7/S1/S4 assertions fail (RED);
-- both WITH 173 = all pass. A0 is the precondition that keeps the sign-up assertions from passing vacuously:
-- the production replay carries no auth-schema triggers, so a replay clone needs
-- replay/60_optional_auth_storage_supplement.sql first (CI and the chain have the trigger from 000).
-- Version-agnostic probe: every write goes through tap._try243 / tap._edge243 and every catalog read through
-- pg_attribute / pg_index lookups, so on a database WITHOUT 173 the suite runs to the end and each gap is its
-- own `not ok`, never an abort that hides the assertions after it.
-- ============================================================================
BEGIN;
SELECT plan(21);

CREATE FUNCTION tap._try243(p_sql text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE v_state text; v_msg text;
BEGIN
  EXECUTE p_sql;
  RETURN 'ok';
EXCEPTION WHEN others THEN
  GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  RETURN 'error ' || v_state || ': ' || v_msg;
END $f$;
-- An edge-function update, run as the caller's role (service_role below): 'matched=<rows>' or the error.
CREATE FUNCTION tap._edge243(p_sql text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE v_n bigint; v_state text; v_msg text;
BEGIN
  EXECUTE p_sql INTO v_n;
  RETURN 'matched=' || v_n;
EXCEPTION WHEN others THEN
  GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  RETURN 'error ' || v_state || ': ' || v_msg;
END $f$;
GRANT EXECUTE ON FUNCTION tap._edge243(text) TO service_role;
CREATE FUNCTION tap._u243(p_n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$
  SELECT ('eeeeeeee-0243-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $f$;
-- A sign-up as GoTrue writes it (the seed_core shape), with the given raw_user_meta_data.
CREATE FUNCTION tap._signup243(p_n int, p_meta jsonb) RETURNS text LANGUAGE sql AS $f$
  SELECT tap._try243(format(
    'INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
     VALUES (%L, %L, %L, %L, %L, %L, %L, now(), now())',
    tap._u243(p_n), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'tap243-' || p_n || '@test.local', '{"provider":"email","providers":["email"]}', p_meta::text)) $f$;
-- What the sign-up stored in profiles: full_name|display_name|avatar_url, NULL shown as <null>; 'no profile'.
CREATE FUNCTION tap._prof243(p_n int) RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce((SELECT coalesce(p.full_name, '<null>') || '|' || coalesce(p.display_name, '<null>') || '|'
                          || coalesce(p.avatar_url, '<null>')
                     FROM public.profiles p WHERE p.id = tap._u243(p_n)), 'no profile') $f$;
-- One profiles column as production has it: type|notnull|default|column ACL, or 'absent'.
CREATE FUNCTION tap._col243(p_tbl regclass, p_col name) RETURNS text LANGUAGE sql AS $f$
  SELECT coalesce((SELECT format_type(a.atttypid, a.atttypmod) || '|' || a.attnotnull || '|'
                          || coalesce(pg_get_expr(d.adbin, d.adrelid), '<no default>') || '|'
                          || coalesce(array_to_string(a.attacl, ','), '<no column acl>')
                     FROM pg_attribute a
                     LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
                    WHERE a.attrelid = p_tbl AND a.attname = p_col AND a.attnum > 0 AND NOT a.attisdropped), 'absent') $f$;

-- ── F7: handle_new_user is production's body ────────────────────────────────
SELECT is(
  (SELECT string_agg(t.tgname || ':' || t.tgfoid::regprocedure::text || ':' || t.tgenabled::text, ',')
     FROM pg_trigger t WHERE t.tgrelid = 'auth.users'::regclass AND NOT t.tgisinternal
      AND t.tgfoid = to_regprocedure('public.handle_new_user()')),
  'on_auth_user_created:handle_new_user():O',
  'A0: precondition: the sign-up trigger on auth.users runs public.handle_new_user() (else A4-A7 would be vacuous)');
SELECT is(md5(pg_get_functiondef(to_regprocedure('public.handle_new_user()'))), 'c29bf692b5227d9185a264dc65cc31f6',
  'A1: handle_new_user md5(pg_get_functiondef) = production''s c29bf692 (chain bfc5cf97 was 30bf73f2)');
SELECT is((SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.handle_new_user()')),
  'faf4c1844c9e27238050efddba46303f', 'A2: handle_new_user body (prosrc) = production''s byte for byte');
SELECT is((SELECT p.prosecdef || '|' || array_to_string(p.proconfig, ';') || '|' || p.provolatile::text || '|'
                  || p.prorettype::regtype::text || '|anon:' || has_function_privilege('anon', p.oid, 'EXECUTE')
                  || '|authenticated:' || has_function_privilege('authenticated', p.oid, 'EXECUTE')
             FROM pg_proc p WHERE p.oid = to_regprocedure('public.handle_new_user()')),
  'true|search_path=public, pg_temp|v|trigger|anon:false|authenticated:false',
  'A3: SECURITY DEFINER, search_path, volatility = production''s; no client role can EXECUTE it (067)');

SELECT is(tap._signup243(1, '{"full_name":"Ana Full","display_name":"Ana D","avatar_url":"https://img.test/a.png"}'), 'ok',
  'A4a: a sign-up with full metadata succeeds');
SELECT is(tap._prof243(1), 'Ana Full|Ana D|https://img.test/a.png',
  'A4b: full_name, display_name and avatar_url are copied from the sign-up metadata (display_name wins over full_name)');
SELECT is(tap._signup243(2, '{"full_name":"Only Full"}') || ' / ' || tap._prof243(2), 'ok / Only Full|Only Full|',
  'A5: display_name falls back to full_name; a missing avatar_url is stored as ''''');
SELECT is(tap._signup243(3, '{}') || ' / ' || tap._prof243(3), 'ok / ||',
  'A6: no metadata: all three are stored as '''' (never NULL)');
SELECT is(split_part(tap._signup243(4, jsonb_build_object('display_name', repeat('x', 51))), ':', 1)
          || ' / ' || (SELECT count(*) FROM auth.users WHERE id = tap._u243(4)) || ' / ' || tap._prof243(4),
  'error 23514 / 0 / no profile',
  'A7: a display_name over 50 characters aborts the whole sign-up (check_violation; production today, owner O-6)');

-- ── S1: the production-only Stripe status columns and index ─────────────────
SELECT is(tap._col243('public.profiles', 'stripe_connect_status'), 'text|true|''not_started''::text|<no column acl>',
  'B1: profiles.stripe_connect_status text NOT NULL DEFAULT ''not_started'', no column ACL (production''s)');
SELECT is(tap._col243('public.profiles', 'stripe_payouts_enabled'), 'boolean|true|false|<no column acl>',
  'B2: profiles.stripe_payouts_enabled boolean NOT NULL DEFAULT false, no column ACL (production''s)');
SELECT is(tap._col243('public.profiles', 'stripe_charges_enabled'), 'boolean|true|false|<no column acl>',
  'B3: profiles.stripe_charges_enabled boolean NOT NULL DEFAULT false, no column ACL (production''s)');
SELECT is(
  (SELECT count(*) FROM unnest(ARRAY['stripe_connect_status','stripe_payouts_enabled','stripe_charges_enabled']) c(col)
     CROSS JOIN unnest(ARRAY['anon','authenticated']) r(role) CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE']) v(priv)
     LEFT JOIN pg_attribute a ON a.attrelid = 'public.profiles'::regclass AND a.attname = c.col AND NOT a.attisdropped
    WHERE CASE WHEN a.attnum IS NULL THEN false ELSE NOT has_column_privilege(r.role, 'public.profiles', c.col, v.priv) END),
  18::bigint, 'B4: anon and authenticated hold no SELECT, INSERT or UPDATE on any of the three (18 denials, none vacuous)');
SELECT is(
  (SELECT count(*) FROM unnest(ARRAY['stripe_connect_status','stripe_payouts_enabled','stripe_charges_enabled']) c(col)
     CROSS JOIN unnest(ARRAY['SELECT','UPDATE']) v(priv)
     LEFT JOIN pg_attribute a ON a.attrelid = 'public.profiles'::regclass AND a.attname = c.col AND NOT a.attisdropped
    WHERE CASE WHEN a.attnum IS NULL THEN false ELSE has_column_privilege('service_role', 'public.profiles', c.col, v.priv) END),
  6::bigint, 'B5: service_role (the edge functions) can SELECT and UPDATE all three');
SELECT is(
  (SELECT pg_get_indexdef(i.indexrelid) FROM pg_index i
     WHERE i.indrelid = 'public.profiles'::regclass AND i.indexrelid = to_regclass('public.idx_profiles_stripe_connect_id')),
  'CREATE INDEX idx_profiles_stripe_connect_id ON public.profiles USING btree (stripe_connect_id) WHERE (stripe_connect_id IS NOT NULL)',
  'B6: idx_profiles_stripe_connect_id = production''s definition (non-unique, partial)');
SELECT is(
  tap._try243($q$SELECT 1 FROM public.profiles p WHERE p.id = 'eeeeeeee-0243-0000-0000-000000000003'
                 AND p.stripe_connect_status = 'not_started' AND NOT p.stripe_payouts_enabled AND NOT p.stripe_charges_enabled$q$)
  || ' / ' || (SELECT count(*) FROM public.profiles WHERE to_jsonb(profiles) @> '{"stripe_connect_status":"not_started","stripe_payouts_enabled":false,"stripe_charges_enabled":false}'
                AND id = tap._u243(3)),
  'ok / 1', 'B7: a new sign-up''s profile starts at the defaults (not_started, false, false)');

-- The two edge writers, as service_role, in PostgREST's update shape (body through json_to_record).
-- Fixture (as postgres): user 1 is a seller whose Connect account is acct_tap243_seller.
UPDATE public.profiles SET stripe_connect_id = 'acct_tap243_seller' WHERE id = tap._u243(1);
SELECT tap.login_service();
-- create-connect-account (origin/release/production-gate-20260918 index.ts:285-292; identical at bfc5cf97):
--   .update({ stripe_onboarding_complete: true (details_submitted), stripe_charges_enabled, stripe_payouts_enabled,
--             stripe_connect_status: 'connected' | 'onboarding_required' }).eq('id', userId)
SELECT is(tap._edge243(format($q$
  WITH s AS (
    UPDATE public.profiles SET stripe_charges_enabled = b.stripe_charges_enabled,
                               stripe_payouts_enabled = b.stripe_payouts_enabled,
                               stripe_connect_status  = b.stripe_connect_status
      FROM json_to_record(%L::json) AS b(stripe_charges_enabled boolean, stripe_payouts_enabled boolean, stripe_connect_status text)
     WHERE public.profiles.id = %L
    RETURNING 1)
  SELECT count(*) FROM s$q$, '{"stripe_charges_enabled":false,"stripe_payouts_enabled":false,"stripe_connect_status":"onboarding_required"}',
  tap._u243(1))), 'matched=1',
  'B8: create-connect-account''s profiles update (details not yet submitted) succeeds and matches the seller''s row');
-- stripe-webhook account.updated (index.ts:929-940): .update({ stripe_onboarding_complete, stripe_charges_enabled,
--   stripe_payouts_enabled, stripe_connect_status }).eq('stripe_connect_id', accountId).select('id')
SELECT is(tap._edge243(format($q$
  WITH s AS (
    UPDATE public.profiles SET stripe_onboarding_complete = b.stripe_onboarding_complete,
                               stripe_charges_enabled     = b.stripe_charges_enabled,
                               stripe_payouts_enabled     = b.stripe_payouts_enabled,
                               stripe_connect_status      = b.stripe_connect_status
      FROM json_to_record(%L::json) AS b(stripe_onboarding_complete boolean, stripe_charges_enabled boolean,
                                          stripe_payouts_enabled boolean, stripe_connect_status text)
     WHERE public.profiles.stripe_connect_id = %L
    RETURNING public.profiles.id)
  SELECT count(*) FROM s$q$,
  '{"stripe_onboarding_complete":true,"stripe_charges_enabled":true,"stripe_payouts_enabled":true,"stripe_connect_status":"connected"}',
  'acct_tap243_seller')), 'matched=1',
  'B9: stripe-webhook account.updated''s profiles update succeeds and matches the seller by stripe_connect_id');
SELECT tap.logout();
SELECT is(
  (SELECT to_jsonb(p) ->> 'stripe_onboarding_complete' || '|' || coalesce(to_jsonb(p) ->> 'stripe_connect_status', '<absent>') || '|'
          || coalesce(to_jsonb(p) ->> 'stripe_charges_enabled', '<absent>') || '|' || coalesce(to_jsonb(p) ->> 'stripe_payouts_enabled', '<absent>')
     FROM public.profiles p WHERE p.id = tap._u243(1)),
  'true|connected|true|true',
  'B10: after account.updated the seller is onboarded (stripe_onboarding_complete true: listing creation opens) and the flags are synced');

-- ── S4: the chain-only payments.stripe_client_secret is gone ────────────────
SELECT is(tap._col243('public.payments', 'stripe_client_secret'), 'absent',
  'C1: payments.stripe_client_secret does not exist (production has none; no reader or writer needs it)');
SELECT is(
  (SELECT (j ? 'id') || '|' || (j ? 'stripe_client_secret')
     FROM (SELECT ops.payment_json(jsonb_populate_record(NULL::public.payments,
                   '{"id":"eeeeeeee-0243-0000-0000-0000000000c1","stripe_client_secret":"pi_x_secret_y"}'::jsonb)) AS j) s),
  'true|false', 'C2: ops.payment_json still returns the payment and never a stripe_client_secret key (182 B12 strip kept)');

SELECT * FROM finish();
ROLLBACK;

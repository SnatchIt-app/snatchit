-- ============================================================================
-- ROLLBACK for 20261021133000_chain_production_parity.sql (registry 173, pgTAP 243). DRAFT, owner-gated.
-- Restores the PRE-173 STATE OF THE DATABASE IT RUNS IN — never production's state on the chain, never the chain's
-- state on production — with ONE DELIBERATE EXCEPTION, payments.stripe_client_secret (below). Run only under owner
-- approval.
--
-- DELIBERATE EXCEPTION (A's technical ruling, 2026-10-21): this file NEVER re-adds payments.stripe_client_secret. On
--   chain lineage 173 dropped it; re-adding it would restore BE-37 S4, a latent secret-shaped column that anon and
--   authenticated can SELECT/INSERT/UPDATE through the payments table grant — and a rollback must never restore a
--   security hole. Nothing is lost by leaving it out: 173 dropped it only while every value was NULL and it carried no
--   column ACL, and no SQL, edge, app, web or console code reads or writes it (the 173 header's S4 grep). Everything
--   else is restored exactly. After this file, on BOTH lineages, the column is ABSENT, and the verification requires it.
--
-- HOW IT KNOWS WHAT 173 DID HERE. 173 changes all three items or none (it refuses any mixed state), and after 173
-- every database looks like production for these items. The one durable difference is column order: a column that
-- 173 added is appended, so its attnum is above stripe_onboarding_complete's and stripe_customer_id's; production's
-- three Stripe status columns were created before both (production attnums 14, 15, 16 < 20, 21; preserved by
-- dump/restore, never renumbered). Hence, on public.profiles:
--   all three columns ABOVE both markers  -> chain lineage: 173 added them, and with them it replaced handle_new_user,
--                                            created idx_profiles_stripe_connect_id and dropped stripe_client_secret.
--                                            Restore exactly that (stripe_client_secret aside: exception above),
--                                            after checking the state is still 173's post-state.
--   all three columns BELOW both markers  -> production lineage (production, a branch or restore of it): 173 executed
--                                            no DDL here, so the rollback executes none either (no lock, no write).
--   none of the three columns             -> 173 is not applied here (or was rolled back): no-op if the rest is the
--                                            chain's pre-173 state (stripe_client_secret present and empty, or absent
--                                            as this file leaves it), refused otherwise.
--   anything else                         -> refused, nothing changed.
-- PRECONDITION of the column-order marker: on a chain-lineage database, appended Stripe status columns are taken as
--   173's. A chain-lineage database that reached production's shape by other means BEFORE 173 (173 is then a no-op
--   there) looks exactly like 173's post-state, and this file would revert it to the chain's state; do not run it
--   there (r173/r08). Production and its copies are not affected: their columns precede both markers.
--
-- THE ROLLBACK'S OWN LINEAGE VERIFICATION. The production-lineage branch is the only thing that stops this file from
--   dropping production's columns, and CI never runs rollback files. So the verification re-derives lineage from the
--   catalog AFTER the DDL, independently of that branch: the three attributes this transaction dropped from profiles
--   (dropped-column placeholders not present before it ran) must all sit after both markers. On a production clone, a
--   copy of this file with the lineage branch removed (mutant RB_no_lineage_guard) fails here and rolls back with
--   nothing changed (private-evidence/A-sprint-20261021/a173/w4/04_negctl_lineage.out).
--
-- CHAIN LINEAGE, what it restores (the chain at bfc5cf97, read from a clone of a_sprint_chain):
--   DROP INDEX idx_profiles_stripe_connect_id; DROP the three Stripe status columns (any values written to them since
--   173 go with them; stripe_onboarding_complete keeps its values); handle_new_user back to the chain's id-only body
--   (pg_get_functiondef from the chain byte for byte, md5 30bf73f28d7cde7398261676a02aac43; the ACL is kept as found —
--   173 never changed it — and verified unchanged). payments.stripe_client_secret is NOT re-added (exception above).
--   It refuses (nothing changed) unless the state is 173's exact post-state, so a later change — an O-6 handle_new_user,
--   a grant on a Stripe status column, a re-created stripe_client_secret — is never reverted silently, and a partial
--   rollback is impossible: all of it or none of it, in one transaction.
-- RESIDUE (chain lineage only): pg_attribute keeps dropped-column placeholders for the four dropped columns, and
--   payments has no stripe_client_secret (deliberate; the only logical difference from the untouched chain, so
--   fingerprint.py's cols_md5 for payments differs by that one column). Every other name, type, nullability, default,
--   ACL, index, function, constraint, policy and trigger is identical to the untouched chain, and payments' remaining
--   columns keep their order: nothing is re-appended (private-evidence/A-sprint-20261021/a173/w4/03_rollback.out).
-- AFTER A CHAIN-LINEAGE ROLLBACK two BE-37 defects return there: S1 (the edge functions' profiles update fails, a
--   seller never becomes onboarded) and F7 (sign-ups store no names or avatars). S4 does not return. 173 can be applied
--   again afterwards: it accepts the chain's shape with stripe_client_secret absent.
-- ORDER: independent of every other rollback. If R-5c (O-1: unique index on stripe_connect_id, drop the partial index)
--   lands after 173, roll R-5c back first: this file refuses while idx_profiles_stripe_connect_id is not 173's.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $rb173$
DECLARE
  c_prod_src   constant text := 'faf4c1844c9e27238050efddba46303f';  -- production handle_new_user prosrc (173's body)
  c_chain_src  constant text := '7946dc44c2a7ac3bc0a09cbb6a2a5db9';  -- chain bfc5cf97 handle_new_user prosrc
  c_hdr        constant text := '|true|search_path=public, pg_temp';  -- SECURITY DEFINER, search_path (ACL: kept as found)
  c_cols       constant text := 'stripe_charges_enabled:boolean:true:false:<none>,'
                                 'stripe_connect_status:text:true:''not_started''::text:<none>,'
                                 'stripe_payouts_enabled:boolean:true:false:<none>';
  c_idx        constant text := 'CREATE INDEX idx_profiles_stripe_connect_id ON public.profiles USING btree (stripe_connect_id) WHERE (stripe_connect_id IS NOT NULL)';
  c_secret     constant text := 'text:false:<none>:<none>';
  v_cols   text;  v_ncols int;  v_late int;  v_early int;  v_pos text;
  v_idx    text;  v_hnu   text; v_secret text;  v_acl text;  v_markers int;
  v_dropped_pre int[];   -- profiles' dropped-column placeholders before this file ran (for the lineage verification)
  v_dropped_new int[];   -- the ones this transaction created
  v_marker_last int;  v_markers_post int;
BEGIN
  SELECT string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull || ':'
                    || coalesce(pg_get_expr(d.adbin, d.adrelid), '<none>') || ':'
                    || coalesce(array_to_string(a.attacl, ','), '<none>'), ',' ORDER BY a.attname),
         count(*),
         count(*) FILTER (WHERE a.attnum > ALL (SELECT b.attnum FROM pg_catalog.pg_attribute b
                                                 WHERE b.attrelid = 'public.profiles'::regclass AND NOT b.attisdropped
                                                   AND b.attname IN ('stripe_onboarding_complete', 'stripe_customer_id'))),
         count(*) FILTER (WHERE a.attnum < ALL (SELECT b.attnum FROM pg_catalog.pg_attribute b
                                                 WHERE b.attrelid = 'public.profiles'::regclass AND NOT b.attisdropped
                                                   AND b.attname IN ('stripe_onboarding_complete', 'stripe_customer_id'))),
         string_agg(a.attname || '@' || a.attnum, ',' ORDER BY a.attnum)
    INTO v_cols, v_ncols, v_late, v_early, v_pos
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
         || ':' || coalesce(array_to_string(a.attacl, ','), '<none>') INTO v_secret
    FROM pg_catalog.pg_attribute a
    LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
   WHERE a.attrelid = 'public.payments'::regclass AND a.attname = 'stripe_client_secret' AND a.attnum > 0 AND NOT a.attisdropped;
  -- Read for the lineage VERIFICATION after the DDL; deliberately separate from (and not used by) the lineage branch.
  SELECT coalesce(array_agg(a.attnum::int ORDER BY a.attnum), '{}') INTO v_dropped_pre
    FROM pg_catalog.pg_attribute a WHERE a.attrelid = 'public.profiles'::regclass AND a.attnum > 0 AND a.attisdropped;

  SELECT count(*) INTO v_markers FROM pg_catalog.pg_attribute
   WHERE attrelid = 'public.profiles'::regclass AND NOT attisdropped AND attname IN ('stripe_onboarding_complete', 'stripe_customer_id');
  IF v_ncols > 0 AND v_markers <> 2 THEN
    RAISE EXCEPTION '173 rollback REFUSED (nothing changed): the lineage markers stripe_onboarding_complete and stripe_customer_id are not both present (% of 2), so the column order cannot tell what 173 did here', v_markers
      USING ERRCODE = 'P0001';
  END IF;

  IF v_ncols = 0 THEN
    IF v_idx IS NULL AND to_regclass('public.idx_profiles_stripe_connect_id') IS NULL
       AND v_hnu = c_chain_src || c_hdr AND v_secret = c_secret THEN
      RAISE NOTICE '173 rollback: nothing to do — this database is in the chain''s pre-173 state (no Stripe status columns, no idx_profiles_stripe_connect_id, the chain''s handle_new_user, payments.stripe_client_secret present); no DDL executed';
      RETURN;
    END IF;
    IF v_idx IS NULL AND to_regclass('public.idx_profiles_stripe_connect_id') IS NULL
       AND v_hnu = c_chain_src || c_hdr AND v_secret IS NULL THEN
      RAISE NOTICE '173 rollback: nothing to do — this database is in the chain''s state after 173''s rollback (no Stripe status columns, no idx_profiles_stripe_connect_id, the chain''s handle_new_user, payments.stripe_client_secret absent: this file never re-adds it); no DDL executed';
      RETURN;
    END IF;
    RAISE EXCEPTION '173 rollback REFUSED (nothing changed): no Stripe status columns, but the rest is not the chain''s pre-173 state: idx [%], handle_new_user [%], stripe_client_secret [%]',
      coalesce(v_idx, coalesce(to_regclass('public.idx_profiles_stripe_connect_id')::text, 'none')), coalesce(v_hnu, 'absent'), coalesce(v_secret, 'absent')
      USING ERRCODE = 'P0001';
  END IF;

  IF v_ncols = 3 AND v_early = 3 THEN
    RAISE NOTICE '173 rollback: production lineage (Stripe status columns at %, before stripe_onboarding_complete and stripe_customer_id): 173 executed no DDL in this database, so there is nothing to restore; no DDL executed', v_pos;
    RETURN;
  END IF;

  IF NOT (v_ncols = 3 AND v_late = 3) THEN
    RAISE EXCEPTION '173 rollback REFUSED (nothing changed): the Stripe status columns are neither all production''s (before stripe_onboarding_complete/stripe_customer_id) nor all appended by 173: %', coalesce(v_pos, 'none')
      USING ERRCODE = 'P0001';
  END IF;

  -- Chain lineage: 173 added the columns here. Act only on 173's exact post-state.
  IF v_cols IS DISTINCT FROM c_cols OR v_idx IS DISTINCT FROM c_idx OR v_hnu IS DISTINCT FROM c_prod_src || c_hdr OR v_secret IS NOT NULL THEN
    RAISE EXCEPTION '173 rollback REFUSED (nothing changed): 173 added the Stripe status columns here (%), but the state is no longer 173''s post-state: columns [%], idx [%], handle_new_user [%], stripe_client_secret [%]',
      v_pos, v_cols, coalesce(v_idx, coalesce(to_regclass('public.idx_profiles_stripe_connect_id')::text, 'none')), coalesce(v_hnu, 'absent'), coalesce(v_secret, 'absent')
      USING ERRCODE = 'P0001',
            HINT = '173 post-state: columns ' || c_cols || '; ' || c_idx || '; handle_new_user ' || c_prod_src || c_hdr || '; no stripe_client_secret. Roll back whatever changed it after 173 first.';
  END IF;

  DROP INDEX public.idx_profiles_stripe_connect_id;
  ALTER TABLE public.profiles
    DROP COLUMN stripe_connect_status,
    DROP COLUMN stripe_payouts_enabled,
    DROP COLUMN stripe_charges_enabled;
  -- the chain's handle_new_user (bfc5cf97: 000_baseline_schema.sql:21 + 0660's search_path), pg_get_functiondef byte for byte
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  insert into public.profiles (id)
  values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$function$;
  -- payments.stripe_client_secret: deliberately NOT re-added (header: a rollback never restores a security hole).

  -- ── verify lineage from the post-DDL catalog, independently of the lineage branch above ──
  -- The attributes this transaction dropped from profiles must be exactly three, all after both markers (173 appended
  -- them). Production's three precede the markers: if the lineage branch were ever bypassed there, this rolls it back.
  SELECT coalesce(array_agg(a.attnum::int ORDER BY a.attnum), '{}') INTO v_dropped_new
    FROM pg_catalog.pg_attribute a
   WHERE a.attrelid = 'public.profiles'::regclass AND a.attnum > 0 AND a.attisdropped AND NOT (a.attnum = ANY (v_dropped_pre));
  SELECT count(*), max(a.attnum) INTO v_markers_post, v_marker_last FROM pg_catalog.pg_attribute a
   WHERE a.attrelid = 'public.profiles'::regclass AND NOT a.attisdropped AND a.attname IN ('stripe_onboarding_complete', 'stripe_customer_id');
  IF cardinality(v_dropped_new) <> 3 OR v_markers_post <> 2 OR v_marker_last IS NULL
     OR NOT (v_marker_last < ALL (v_dropped_new)) THEN
    RAISE EXCEPTION '173 rollback verification failed (rolled back): the profiles attributes this rollback dropped (attnums %) are not three columns appended after both lineage markers (% of 2 present, last at %): this is not the chain lineage 173 converted, so nothing is changed', v_dropped_new, v_markers_post, v_marker_last
      USING ERRCODE = 'P0001';
  END IF;

  -- ── verify (same transaction): the chain's pre-173 state minus stripe_client_secret, or nothing changes ──
  SELECT count(*) INTO v_ncols FROM pg_catalog.pg_attribute
   WHERE attrelid = 'public.profiles'::regclass AND NOT attisdropped
     AND attname IN ('stripe_connect_status', 'stripe_payouts_enabled', 'stripe_charges_enabled');
  SELECT md5(p.prosrc) || '|' || p.prosecdef || '|' || array_to_string(p.proconfig, ';') INTO v_hnu
    FROM pg_catalog.pg_proc p WHERE p.oid = 'public.handle_new_user()'::regprocedure
     AND coalesce(array_to_string(p.proacl, ','), '<default>') = v_acl;   -- CREATE OR REPLACE kept the ACL
  SELECT format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull || ':' || coalesce(pg_get_expr(d.adbin, d.adrelid), '<none>')
         || ':' || coalesce(array_to_string(a.attacl, ','), '<none>') INTO v_secret
    FROM pg_catalog.pg_attribute a
    LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
   WHERE a.attrelid = 'public.payments'::regclass AND a.attname = 'stripe_client_secret' AND NOT a.attisdropped;
  IF v_ncols <> 0 OR to_regclass('public.idx_profiles_stripe_connect_id') IS NOT NULL
     OR v_hnu IS DISTINCT FROM c_chain_src || c_hdr OR v_secret IS NOT NULL THEN   -- stripe_client_secret must be ABSENT
    RAISE EXCEPTION '173 rollback verification failed (rolled back): columns %, handle_new_user [%], stripe_client_secret [%]', v_ncols, v_hnu, v_secret
      USING ERRCODE = 'P0001';
  END IF;
  RAISE NOTICE '173 rollback: chain lineage restored to the pre-173 state: handle_new_user md5 %, Stripe status columns (attnums %) and idx_profiles_stripe_connect_id dropped; payments.stripe_client_secret deliberately NOT re-added (absent: a rollback never restores the S4 secret column)',
    md5(pg_get_functiondef('public.handle_new_user()'::regprocedure)), v_dropped_new;
END
$rb173$;

COMMIT;

-- Read-only re-check after COMMIT. Chain lineage: 30bf73f28d7cde7398261676a02aac43 | 0 | <NULL> | 0 (column ABSENT).
-- Production lineage: c29bf692b5227d9185a264dc65cc31f6 | 3 | idx_profiles_stripe_connect_id | 0 (unchanged).
SELECT md5(pg_get_functiondef('public.handle_new_user()'::regprocedure)) AS handle_new_user_md5,
       (SELECT count(*) FROM pg_catalog.pg_attribute WHERE attrelid = 'public.profiles'::regclass AND NOT attisdropped
          AND attname IN ('stripe_connect_status', 'stripe_payouts_enabled', 'stripe_charges_enabled')) AS stripe_status_columns,
       to_regclass('public.idx_profiles_stripe_connect_id') AS idx,
       (SELECT count(*) FROM pg_catalog.pg_attribute WHERE attrelid = 'public.payments'::regclass AND NOT attisdropped
          AND attname = 'stripe_client_secret') AS stripe_client_secret_column;

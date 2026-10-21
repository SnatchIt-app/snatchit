-- ============================================================================
-- ROLLBACK for 20261021132000_bid_created_at_server_owned.sql (registry 172, pgTAP 242). DRAFT, owner-gated.
-- Not for use before 172 itself is applied. 172: not for apply before 2026-10-28 03:47:04Z (four live listings) and
--   before build 29's review settles; owner-gated. Bid-path change.
-- Pre-172 state = production 2026-10-21 (A's read-only catalog snapshot; the production replay's pg_trigger/pg_proc):
--   BEFORE INSERT triggers on public.bids, in firing (name) order:
--     before_bid_guard_parties    -> public.guard_bid_parties()             md5 97922d8250651fa09f58e1479a2f3014
--     before_bid_insert           -> public.validate_and_apply_bid()        md5 d237200eb6a4cc6a2400b217e25e0618
--     trg_bid_requires_disclosure -> public.guard_bid_requires_disclosure() md5 b56fed711d89c17c2060b745ae5d189c
--   each with ACL postgres=X/postgres,service_role=X/postgres; no public.set_bid_created_at_server_clock().
--   172 redefined NO existing function, so there is no body to restore: this file drops the two objects 172 added
--   and then VERIFIES the production state above inside the same transaction. The chain at bfc5cf97 carries a
--   different validate_and_apply_bid (md5 e22bd09f1ba1341b7baae647ad584c18, BE-37 F18, parked); the check accepts
--   exactly those two values, so the file also runs on a CI/chain rehearsal. Any mismatch RAISEs and, because it
--   runs before COMMIT, a partial or drifted rollback (one DROP missing, a body changed underneath) changes nothing.
-- KEEPS: every bids row as stored (rows inserted while 172 was applied keep their server timestamps).
-- AFTER ROLLBACK: bids.created_at is client-set again — the BE-37 S2 defect returns (a NULL in production, or a
--   backdated value on either side, switches the 3-second bid rate limit off for that bidder on that listing).
-- ORDER: independent of every other rollback (172 touches only public.bids' trigger list). Run only under owner approval.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

DROP TRIGGER IF EXISTS before_bid_created_at_server_owned ON public.bids;
DROP FUNCTION IF EXISTS public.set_bid_created_at_server_clock();

-- ── verify (same transaction): refuse unless the production state is fully back ──
DO $verify172$
DECLARE
  v_trg text;
  v_bad text;
BEGIN
  IF to_regprocedure('public.set_bid_created_at_server_clock()') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_catalog.pg_trigger WHERE tgrelid = 'public.bids'::regclass AND tgname = 'before_bid_created_at_server_owned') THEN
    RAISE EXCEPTION '172 rollback verification failed (nothing changed): the trigger or function of 172 is still present'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT string_agg(t.tgname || '->' || p.proname, ',' ORDER BY t.tgname COLLATE "C")
    INTO v_trg
    FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_proc p ON p.oid = t.tgfoid
   WHERE t.tgrelid = 'public.bids'::regclass AND NOT t.tgisinternal AND t.tgtype & 6 = 6;
  IF v_trg IS DISTINCT FROM 'before_bid_guard_parties->guard_bid_parties,before_bid_insert->validate_and_apply_bid,trg_bid_requires_disclosure->guard_bid_requires_disclosure' THEN
    RAISE EXCEPTION '172 rollback verification failed (nothing changed): BEFORE INSERT triggers on bids are % (production: before_bid_guard_parties, before_bid_insert, trg_bid_requires_disclosure)', coalesce(v_trg, '<none>')
      USING ERRCODE = 'P0001';
  END IF;

  SELECT string_agg(c.sig || ': '
                    || CASE WHEN c.live_md5 IS NULL OR NOT (c.live_md5 = ANY (c.ok_md5))
                            THEN 'md5 ' || coalesce(c.live_md5, '<missing>') || ' not in ' || array_to_string(c.ok_md5, '|')
                            ELSE 'md5 ok' END
                    || ', '
                    || CASE WHEN c.live_acl IS DISTINCT FROM 'postgres=X/postgres,service_role=X/postgres'
                            THEN 'ACL ' || coalesce(c.live_acl, '<default>') || ' <> production postgres=X/postgres,service_role=X/postgres'
                            ELSE 'ACL ok' END, '; ' ORDER BY c.sig)
    INTO v_bad
    FROM (SELECT v.sig, v.ok_md5,
                 md5(pg_get_functiondef(to_regprocedure(v.sig))) AS live_md5,
                 (SELECT array_to_string(p.proacl, ',') FROM pg_catalog.pg_proc p WHERE p.oid = to_regprocedure(v.sig)) AS live_acl
            FROM (VALUES ('public.guard_bid_parties()',             ARRAY['97922d8250651fa09f58e1479a2f3014']),
                         ('public.validate_and_apply_bid()',        ARRAY['d237200eb6a4cc6a2400b217e25e0618',    -- production
                                                                          'e22bd09f1ba1341b7baae647ad584c18']),  -- chain bfc5cf97 (F18)
                         ('public.guard_bid_requires_disclosure()', ARRAY['b56fed711d89c17c2060b745ae5d189c'])) v(sig, ok_md5)) c
   WHERE c.live_md5 IS NULL OR NOT (c.live_md5 = ANY (c.ok_md5))
      OR c.live_acl IS DISTINCT FROM 'postgres=X/postgres,service_role=X/postgres';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '172 rollback verification failed (nothing changed): %', v_bad USING ERRCODE = 'P0001';
  END IF;
  RAISE NOTICE '172 rollback verified: trigger and function gone; bids BEFORE INSERT = production set; guard_bid_parties and guard_bid_requires_disclosure = production md5s; validate_and_apply_bid md5 % (%); all three ACLs = production''s',
    md5(pg_get_functiondef('public.validate_and_apply_bid()'::regprocedure)),
    CASE md5(pg_get_functiondef('public.validate_and_apply_bid()'::regprocedure))
      WHEN 'd237200eb6a4cc6a2400b217e25e0618' THEN 'production' ELSE 'chain bfc5cf97, F18 parked' END;
END
$verify172$;

COMMIT;

-- Read-only re-check after COMMIT (expect one row: f | before_bid_guard_parties < before_bid_insert < trg_bid_requires_disclosure | d237200eb6a4cc6a2400b217e25e0618 in production):
SELECT to_regprocedure('public.set_bid_created_at_server_clock()') IS NOT NULL AS fn_present,
       (SELECT string_agg(tgname, ' < ' ORDER BY tgname COLLATE "C") FROM pg_catalog.pg_trigger
         WHERE tgrelid = 'public.bids'::regclass AND NOT tgisinternal AND tgtype & 6 = 6) AS before_insert_triggers,
       md5(pg_get_functiondef('public.validate_and_apply_bid()'::regprocedure)) AS validate_and_apply_bid_md5;

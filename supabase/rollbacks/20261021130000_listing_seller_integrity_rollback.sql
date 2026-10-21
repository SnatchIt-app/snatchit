-- ============================================================================
-- ROLLBACK for 20261021130000_listing_seller_integrity.sql (registry 170, pgTAP 240). DRAFT, owner-gated, like 170.
-- Pre-170 state = production 2026-10-21 (A's read-only snapshot, private-evidence/A-sprint-20261021/
-- prod_ops_action_defs.json / prod_functions.json):
--   public.cancel_listing(uuid, uuid)  md5 ba31642267e65fefbf9485a144efc753, SECURITY DEFINER, search_path=public,
--                                      ACL postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres
--   no public.guard_listing_edit_lock(); no trg_guard_listing_edit_lock on public.listings.
-- STACKING GUARD (first): refuses unless the installed objects are exactly 170's (cancel_listing md5
--   137f680cff0d54d6c07af2bf49975b6c, guard_listing_edit_lock md5 9640ef298bb32af8b6cff3b4299404b5, the trigger bound to it). A later
--   migration that redefined either must be rolled back first; this file never silently reverts it.
-- WHAT: drops the trigger and the function; restores cancel_listing VERBATIM (the production pg_get_functiondef
--   text, byte for byte — not a repo migration's text); then VERIFIES inside the same transaction that the md5,
--   definer flag, search_path and ACL equal production and that the trigger and function are gone. Any mismatch
--   RAISEs, so a partial or drifted rollback changes nothing.
-- AFTER ROLLBACK: a seller (and every service path) can again cancel a listing under a live Buy Now hold or an
--   ended auction with a winner, and edit a listing's content after bids, a hold or a sale (the pre-170
--   defects). The six HINTs disappear; message texts are unchanged either way, so clients that key on text
--   are unaffected. No row is read or written.
-- ORDER: independent of 157/158 (ops.* only) and of 154-156 (170 adds nothing they own). Run only under owner
--   approval.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ── 0. stacking guard (read-only) ───────────────────────────────────────────
DO $pre170rb$
DECLARE
  v_cl  text := md5(pg_get_functiondef('public.cancel_listing(uuid,uuid)'::regprocedure));
  v_fn  text := md5(pg_get_functiondef(to_regprocedure('public.guard_listing_edit_lock()')));
BEGIN
  IF v_cl = 'ba31642267e65fefbf9485a144efc753' AND v_fn IS NULL
     AND NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.listings'::regclass AND tgname = 'trg_guard_listing_edit_lock') THEN
    RAISE EXCEPTION '170 rollback refused: 170 is not installed (cancel_listing already has the production body; no lock function or trigger). Nothing changed.';
  END IF;
  IF v_cl IS DISTINCT FROM '137f680cff0d54d6c07af2bf49975b6c' THEN
    RAISE EXCEPTION '170 rollback refused: public.cancel_listing is not the 170 body (md5 %). Roll back the later change first. Nothing changed.', v_cl;
  END IF;
  IF v_fn IS DISTINCT FROM '9640ef298bb32af8b6cff3b4299404b5'
     OR NOT EXISTS (SELECT 1 FROM pg_trigger t
                     WHERE t.tgrelid = 'public.listings'::regclass AND t.tgname = 'trg_guard_listing_edit_lock'
                       AND t.tgfoid = to_regprocedure('public.guard_listing_edit_lock()')) THEN
    RAISE EXCEPTION '170 rollback refused: guard_listing_edit_lock (md5 %) or its trigger is not 170''s. Nothing changed.', coalesce(v_fn, '<missing>');
  END IF;
END
$pre170rb$;

-- ── 1. the content lock ─────────────────────────────────────────────────────
DROP TRIGGER trg_guard_listing_edit_lock ON public.listings;
DROP FUNCTION public.guard_listing_edit_lock();

-- ── 2. cancel_listing: the production body, verbatim ───────────────────────
CREATE OR REPLACE FUNCTION public.cancel_listing(p_listing_id uuid, p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_caller_id uuid; v_seller_id uuid; v_status text; v_auction_status text;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL AND public.request_is_service_role() THEN v_caller_id := p_user_id; END IF;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.'; END IF;

  SELECT seller_id, status, auction_status INTO v_seller_id, v_status, v_auction_status
    FROM public.listings WHERE id = p_listing_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Listing not found.'; END IF;
  IF v_seller_id IS DISTINCT FROM v_caller_id THEN RAISE EXCEPTION 'You can only cancel your own listings.'; END IF;
  IF v_status = 'sold' THEN RAISE EXCEPTION 'This listing has already been sold and cannot be cancelled.'; END IF;
  IF v_auction_status = 'cancelled' THEN RETURN; END IF;

  PERFORM set_config('app.bypass_listing_guard', 'on', true);
  UPDATE public.listings
     SET auction_status='cancelled', status='active', reserved_by=NULL,
         reserved_until=NULL, ended_at=now()
   WHERE id = p_listing_id;
END; $function$
;

-- ── 3. verification (inside the transaction: a mismatch aborts the whole rollback) ─
DO $verify170rb$
DECLARE
  v_bad text;
BEGIN
  SELECT CASE WHEN md5(pg_get_functiondef(p.oid)) IS DISTINCT FROM 'ba31642267e65fefbf9485a144efc753'
                THEN 'cancel_listing md5 ' || md5(pg_get_functiondef(p.oid)) || ' <> production ba31642267e65fefbf9485a144efc753; ' ELSE '' END
      || CASE WHEN p.prosecdef::text || '|' || array_to_string(p.proconfig, ',') || '|' || array_to_string(p.proacl, ',')
                   IS DISTINCT FROM 'true|search_path=public|postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres'
                THEN 'cancel_listing definer/search_path/ACL differ from production; ' ELSE '' END
    INTO v_bad
    FROM pg_proc p WHERE p.oid = 'public.cancel_listing(uuid,uuid)'::regprocedure;
  IF to_regprocedure('public.guard_listing_edit_lock()') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.listings'::regclass AND tgname = 'trg_guard_listing_edit_lock') THEN
    v_bad := coalesce(v_bad, '') || 'guard_listing_edit_lock or its trigger is still present; ';
  END IF;
  IF coalesce(v_bad, '') <> '' THEN
    RAISE EXCEPTION '170 rollback verification failed (nothing changed): %', v_bad USING ERRCODE = 'P0001';
  END IF;
  RAISE NOTICE '170 rollback verified: cancel_listing = production md5 ba31642267e65fefbf9485a144efc753 and ACL; lock function and trigger gone';
END
$verify170rb$;

COMMIT;

-- Read-only re-check after COMMIT (expect: ok = true, lock_fn = false, lock_trigger = false):
SELECT md5(pg_get_functiondef('public.cancel_listing(uuid,uuid)'::regprocedure)) = 'ba31642267e65fefbf9485a144efc753' AS ok,
       to_regprocedure('public.guard_listing_edit_lock()') IS NOT NULL AS lock_fn,
       EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_guard_listing_edit_lock') AS lock_trigger;

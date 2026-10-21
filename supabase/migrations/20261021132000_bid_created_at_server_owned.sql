-- ============================================================================
-- 20261021132000_bid_created_at_server_owned.sql — registry 172 (pgTAP 242). BE-37 S2 (R-4).
--
-- DRAFT. BID-PATH CHANGE. OWNER-GATED. Applied nowhere.
--   not for apply before 2026-10-28 03:47:04Z (four live listings) and before build 29's review settles; owner-gated.
--   Not for apply before 2026-10-28 03:47:04Z (the four live listings end then; STATUS 88: no release-bound
--   change to listing-state RPCs, guards or bid rules while they are live) and not before build 29's App
--   Review settles. Applying it to production, and its order relative to any build, are separate owner approvals.
--
-- DEFECT (reproduced locally on the production replay and on the chain at bfc5cf97 through the real client path:
--   private-evidence/A-sprint-20261021/a2/p3/01_repro_prod_replay.out, 02_repro_chain.out).
--   validate_and_apply_bid() (trigger before_bid_insert) enforces "Please wait before bidding again." by reading
--   the bidder's LAST STORED bid:  SELECT created_at ... ORDER BY created_at DESC LIMIT 1, then
--   NOW() - v_last_bid_at < 3 s. bids.created_at is client-writable (anon/authenticated hold table-level INSERT;
--   the RLS check is bidder_id = auth.uid() only; no trigger assigned NEW.created_at), so the client decides it:
--     * created_at NULL — production only (the column is NULL-able there, NOT NULL in the chain): DESC sorts NULLs
--       first, v_last_bid_at is NULL, and the limit is off for that bidder on that listing while the row exists;
--     * a backdated created_at — both sides: every bid looks old enough;
--     * a future created_at — both sides: not a bypass but a lock-out of the bidder and a bid dated in the future.
--   No shipped producer sends created_at: PlaceBidScreen (e46fc203) and web lib/bids.ts insert
--   {listing_id, bidder_id, amount}; scripts/seed-demo.ts the same; no database function inserts into bids.
--
-- WHAT. One new plain trigger function and one new trigger; nothing else changes.
--   public.set_bid_created_at_server_clock() — SECURITY INVOKER (no definer rights: it reads no table), search_path ''.
--     NEW.created_at := now(), unconditionally: client, service_role and claims-less postgres inserts alike. now() is
--     the transaction timestamp, the same clock as the column default and as validate_and_apply_bid's NOW().
--   Trigger before_bid_created_at_server_owned, BEFORE INSERT ... FOR EACH ROW. PostgreSQL fires same-timing
--     triggers in name order; this name sorts before every existing BEFORE INSERT trigger on bids
--     (before_bid_guard_parties < before_bid_insert < trg_bid_requires_disclosure, read from pg_trigger on the
--     production replay), so every later trigger, and the stored row, see the server's value. It assigns only:
--     it cannot refuse, locks nothing and writes no other table, so 152's rule that the parties guard refuses
--     before validate_and_apply_bid locks the listing still holds (219 A2 now names this stamp as the one
--     trigger allowed ahead of the guard).
--   INSERT only: existing rows are never rewritten (no UPDATE in this file; an UPDATE of created_at is kept).
--   UNCHANGED: validate_and_apply_bid (production md5 d237200eb6a4cc6a2400b217e25e0618; F10 parked) and every
--   refusal message; guard_bid_parties, guard_bid_requires_disclosure; bids columns, defaults, nullability
--   (production's NOT NULL is R-5a, owner, after this), constraints, indexes, policies, table grants.
--
-- GATE-2 census (public): functions 126 -> 127 (+set_bid_created_at_server_clock, no-client-execute);
--   triggers 49 -> 50 (+before_bid_created_at_server_owned). Tables 35 and policies 37 unchanged.
--   expected_grants.txt unchanged (table grants unchanged). The function's own REVOKE below is the
--   no-client-execute convention for every new public function (proacl must not stay defaulted).
-- ROLLBACK: supabase/rollbacks/20261021132000_bid_created_at_server_owned_rollback.sql drops the trigger and the
--   function in one transaction and verifies the production state (BEFORE INSERT set and the three bid trigger
--   function md5s); a partial rollback is refused. After a rollback created_at is client-set again (the defect).
-- VERIFY (read-only):
--   select string_agg(tgname, ' < ' order by tgname collate "C") from pg_trigger
--    where tgrelid = 'public.bids'::regclass and not tgisinternal and tgtype & 6 = 6;
--     -- before_bid_created_at_server_owned < before_bid_guard_parties < before_bid_insert < trg_bid_requires_disclosure
--   select md5(pg_get_functiondef('public.validate_and_apply_bid()'::regprocedure));  -- unchanged
-- FAILURE BEHAVIOUR: one transaction; any failure rolls all of it back. CREATE TRIGGER takes a brief
--   SHARE ROW EXCLUSIVE lock on bids; lock_timeout 3s, so it fails cleanly rather than queue behind traffic.
-- OWNER APPROVAL POINT: prepared and tested locally only (A sprint 2026-10-21, item P3).
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE FUNCTION public.set_bid_created_at_server_clock()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  NEW.created_at := now();   -- the server's clock, never the client's: the 3-second bid rate limit reads this column
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.set_bid_created_at_server_clock() FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public.set_bid_created_at_server_clock() IS
  '172: BEFORE INSERT on public.bids (before_bid_created_at_server_owned, the first BEFORE INSERT trigger by name): '
  'created_at := now() on every insert, whatever the caller sent, so validate_and_apply_bid''s 3-second rate limit '
  'reads server time. Existing rows are never rewritten.';

DROP TRIGGER IF EXISTS before_bid_created_at_server_owned ON public.bids;
CREATE TRIGGER before_bid_created_at_server_owned
  BEFORE INSERT ON public.bids
  FOR EACH ROW EXECUTE FUNCTION public.set_bid_created_at_server_clock();

-- Postcondition: the stamp is the first BEFORE INSERT trigger on bids (firing order is name order).
DO $$
DECLARE v_first name;
BEGIN
  SELECT t.tgname INTO v_first FROM pg_catalog.pg_trigger t
   WHERE t.tgrelid = 'public.bids'::regclass AND NOT t.tgisinternal AND t.tgtype & 6 = 6
   ORDER BY t.tgname COLLATE "C" LIMIT 1;
  IF v_first IS DISTINCT FROM 'before_bid_created_at_server_owned' THEN
    RAISE EXCEPTION '172: before_bid_created_at_server_owned is not the first BEFORE INSERT trigger on public.bids (first: %)', v_first;
  END IF;
END $$;

COMMIT;

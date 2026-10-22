-- ============================================================================
-- 20261021130000_listing_seller_integrity.sql — registry 170 (pgTAP 240). Listing seller integrity.
-- DRAFT — not for apply before 2026-10-28 03:47:04Z (four live listings) and before build 29's review
-- settles; owner-gated. STATUS 88 holds release-bound changes to listing-state RPCs and guards while the four
-- relisted production listings are live and build 29 is in App Review. Prepared and tested on the local
-- production replay only (a_sprint_prod_template); applied nowhere.
-- Source finding: sprint-control/SERVER_REFUSAL_CATALOGUE_C_20261021.md §9, "Surprising" 2 and 4; the DELETE guard (c):
-- sprint-control/LEGACY_CLIENT_API_SURFACE_AUDIT_20261021.md §3 / §5 P2 (evidence private-evidence/A-sprint-20261021/leg/).
--
-- WHY.
--   (a) public.cancel_listing refused only status 'sold'. A seller (or any service path) could cancel
--       - a listing under a LIVE Buy Now hold: the cancel cleared reserved_by/reserved_until while the buyer
--         was paying; the payment then settles as 'unfulfillable' (settle_listing_for_payment returns it for
--         a cancelled listing) and becomes a refund;
--       - an ended auction WITH a winner: the winner's auction payment settles as 'unfulfillable' too.
--       Reproduced on a production-replay clone: private-evidence/A-sprint-20261021/a2/p1/01_red.out
--       (pgTAP 240 A9/A11/A14/A16/A25/A27).
--   (b) No server guard stopped a seller changing a listing's content after bids, a hold or a sale: RLS on
--       listings checks ownership only (listings_update_own, listings_update_own_meta, "listings: seller update
--       own": seller_id = auth.uid()), authenticated holds table-level UPDATE on every column (relacl
--       authenticated=arwdm, no column ACLs), and guard_listing_state_columns covers only the 11 state columns.
--       The app's "edit until the first bid" rule is client-only (app/listing/edit/[id].tsx at e46fc203: the
--       editRefusal gate, src/lib/listing/editAccess.ts:69-70, refuses bid_count > 0 or auction_status <> 'active'
--       only — NOT a Buy Now hold; the save at :157-167 PATCHes event_name, venue, restrictions, ticket_platform;
--       web/src/lib/seller-listings.ts:166-201 the same four after its badge gate and a real bid count). A stale
--       form saved after the first bid, the app's own edit screen during a live hold, or any direct PATCH,
--       succeeded (01_red.out, pgTAP 240 B1-B18, B27).
--   (c) A seller could HARD-DELETE their own listing after bids or under a live Buy Now hold. authenticated holds
--       DELETE on listings, the one DELETE policy (listings_delete_own) checks ownership only, and no DELETE trigger
--       existed; the "no delete once there is activity" rule lived only in the clients (app/my-listings.tsx:152,
--       src/screens/ListingDetailScreen.tsx:911 read a bid_count that can be stale; web seller-listings.ts:227-232
--       counts bids, then deletes a moment later). The delete then CASCADEs the bids (bids_listing_id_fkey) and the
--       buyers' saves (saved_listings_listing_id_fkey) and unlinks moderation flags (seller_flags_listing_id_fkey SET
--       NULL); a live hold is destroyed while the buyer is checking out. Only payments, transfers, webhook_retries
--       (NO ACTION) and listing_visibility (RESTRICT) block it. The 10-15 snapshot has 23 listings with bid rows and no
--       blocking row. Reproduced through a real PostgREST 16.2 with the app's exact request
--       (private-evidence/A-sprint-20261021/a2/p1/w4/W01_red_postgrest_base.out) and in pgTAP 240 E1-E13.
--
-- WHAT.
--   1. Pre-flight (read-only DO block): cancel_listing must be the PRODUCTION body (md5
--      ba31642267e65fefbf9485a144efc753, prod_functions.json; the chain at bfc5cf97 carries the same body), none of
--      the four new objects may exist, and public.listings must have no DELETE trigger (production has none).
--      Otherwise RAISE; nothing changes.
--   2. public.cancel_listing(uuid, uuid), from the PRODUCTION body (pg_get_functiondef of
--      a_sprint_prod_template, fingerprint-identical to production). Same signature, definer, search_path
--      'public', ACL (CREATE OR REPLACE keeps the grants; the post-check compares grants, definer flag and search_path
--      with the state captured BEFORE the replacement, so the file provably changes none of them wherever it runs:
--      the 171 pattern, b84c8e05; the production values stay documented in the post-check).
--        - The four existing refusals keep their MESSAGE text byte for byte (app my-listings.tsx:178 and
--          ListingDetailScreen show it raw; web mapSellerError matches "only cancel your own", "already been
--          sold", "Listing not found" by substring). Each gains ERRCODE P0001 (unchanged SQLSTATE) and a HINT:
--          no caller -> CALLER_UNKNOWN, not found -> LISTING_NOT_FOUND, not the seller -> NOT_LISTING_OWNER,
--          sold -> LISTING_ALREADY_SOLD.
--        - New, after the existing "already cancelled -> RETURN" (an already-cancelled listing, including the
--          cancelled-with-winner rows pre-170 cancels left behind, stays a silent no-op):
--            live hold: status = 'reserved' AND reserved_until > now() ->
--              'This listing has a buyer checking out right now and can''t be cancelled.' HINT LISTING_HELD
--              (the HINT 154's listing_visibility guard already uses for a live hold). reserved_by is not in the
--              predicate: every writer sets it together with reserved_until (reserve_buy_now) and clears both
--              together (release_reservation*, cleanup_expired_reservations, cancel_listing,
--              settle_listing_for_payment), so it adds no reachable case.
--              An EXPIRED hold (reserved_until <= now(), cleanup_expired_reservations' boundary) stays
--              cancellable and is cleared by the cancel, exactly as before.
--            winner: winner_user_id IS NOT NULL ->
--              'This auction already has a winner and can''t be cancelled.' HINT LISTING_HAS_WINNER.
--          Both apply to EVERY caller, the claims-less SQL-editor path and service_role included: a hold is at
--          most 10 minutes, and a winner's payment must settle (or the winner path be resolved) first.
--        - An OPEN auction with bids and no winner yet stays voidable (web cancelSellerListing: "Voids a listing
--          that already has bids"). The UPDATE is unchanged.
--   3. public.guard_listing_edit_lock() — NEW, trigger function, SECURITY DEFINER, search_path '', EXECUTE
--      revoked from PUBLIC, anon, authenticated (no client EXECUTE; the 155/156 guards' shape).
--        Locked: OLD.bid_count > 0 OR OLD.status IN ('reserved','sold') OR OLD.sold_at IS NOT NULL.
--        Unlocked rows, and UPDATEs that leave all 17 content columns NOT DISTINCT FROM OLD (the edit screen
--        re-sends all four fields; RPC and sweep writes touch none), pass.
--        Trusted, as-is: the trust test of 155/156 (set_listing_ends_at_from_duration,
--        guard_listing_proof_waiver, guard_reservation_requires_disclosure), read the 119 way: the role GUC
--        (PostgREST's SET ROLE; 'none' on a direct connection, where current_user is the owner) is
--        service_role with claims absent or service_role, or postgres with NO request claims (migrations,
--        cron, the SQL editor). A postgres or service_role session carrying authenticated claims is untrusted.
--        Untrusted change of a content column on a locked row ->
--          'This listing can''t be edited after it has bids, a buyer checking out, or a sale.'
--          HINT LISTING_LOCKED_FOR_EDIT (ERRCODE P0001).
--      Trigger trg_guard_listing_edit_lock BEFORE UPDATE OF <the 17 columns> ON public.listings FOR EACH ROW.
--      THE 17 COLUMNS, derived from the grants: authenticated may UPDATE all 39 listings columns. 21 are
--        already guarded or server-set: state (current_bid, bid_count, highest_bidder_id, status,
--        auction_status, winner_user_id, winning_bid_amount, reserved_by, reserved_until, sold_at, ended_at —
--        guard_listing_state_columns), identity (id, seller_id, created_at — guard_listing_identity_columns),
--        end time (ends_at, duration_hours — set_listing_ends_at_from_duration, LISTING_END_TIME_FIXED),
--        proof_status (guard_proof_status), the waiver (proof_waived_at/by/reason — guard_listing_proof_waiver)
--        and updated_at (set_updated_at overwrites it). Of the remaining 18, proof_of_ownership_path is the one
--        documented EXCLUSION: suite 223 L2 asserts a seller may replace the proof of a non-waived listing
--        after a bid (a review artifact, not buyer-facing content; a waived listing's proof is already frozen
--        by guard_listing_proof_waiver) — changing that is a separate owner decision. Locked (17), in table
--        order: event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity,
--        transfer_method, restrictions, starting_bid, buy_now_enabled, buy_now_price, starts_at,
--        cover_image_path, ticket_platform, seller_commitment_accepted_at, category. pgTAP 240 D4 re-derives
--        this split from has_column_privilege, so a future client-updatable column fails CI until classified.
--   4. public.guard_listing_delete() — NEW, trigger function, SECURITY DEFINER (it reads public.bids past RLS),
--      search_path '', EXECUTE revoked from PUBLIC, anon, authenticated (no client EXECUTE; the same shape as 3).
--        Locked: OLD.bid_count > 0 OR a bid row exists for the listing OR OLD.status IN ('reserved','sold')
--          OR OLD.sold_at IS NOT NULL OR a live hold (reserved_until > now()). The bid counter and the bid rows are
--          read separately (defense in depth: no RPC lets them disagree, and the replay has 0 such rows, but a
--          delete must never cascade a bid row). status 'reserved' includes a hold that lapsed but is not yet swept:
--          it is refused until cleanup_expired_reservations (auto_finalize_expired_auctions) returns the listing to
--          'active', then it is deletable; the seller can cancel it meanwhile (cancel_listing clears a lapsed hold).
--          The live-hold disjunct is null-safe (reserved_until IS NOT NULL AND ...), so an unlocked row is never
--          refused by a NULL.
--        Unlocked rows pass: an active, ended or cancelled listing with no bid, no hold and no sale is the clients'
--        normal delete and keeps working (RETURN OLD).
--        Trusted, as-is: the same trust test as 3 (service_role with claims absent or service_role; postgres with NO
--        request claims). A postgres or service_role session carrying authenticated claims is untrusted.
--        Untrusted delete of a locked row ->
--          'This listing can''t be deleted after it has bids, a buyer checking out, or a sale. Cancel it instead.'
--          HINT LISTING_DELETE_LOCKED (ERRCODE P0001). Raised, not filtered: an RLS refusal of DELETE is a silent
--          0-row success the shipped app would report as "Deleted" (catalogue DEL-5); both apps show error.message.
--      Trigger trg_guard_listing_delete BEFORE DELETE ON public.listings FOR EACH ROW. It is the only DELETE trigger
--      on listings; the foreign-key actions are AFTER ROW (RI) triggers, so the guard decides before any CASCADE
--      or SET NULL runs, and a refusal rolls the whole statement back.
--      Interplay with the existing refusals (unchanged): RLS first — a non-owner's DELETE matches 0 rows and the
--      guard never runs (no state oracle, no error, as today). Where the guard lets a delete through, the foreign
--      keys answer exactly as before: a listing with a payment, transfer or webhook_retries row stays 23503, a
--      hidden listing (listing_visibility, RESTRICT) stays 23503 (suite 221 K1-K5 identical), for clients and the
--      trusted path alike. Where both apply (a sold listing), the guard's sentence now answers before the raw 23503.
--
-- FIRING ORDER (BEFORE UPDATE row triggers on public.listings fire in name order; pgTAP 240 C5):
--   guard_listing_state < trg_guard_listing_content < trg_guard_listing_edit_lock < trg_guard_listing_identity
--   < trg_guard_listing_proof_waiver < trg_guard_listing_reservation_parties < trg_guard_proof_status
--   < trg_hidden_listing_not_live < trg_listing_ends_at_from_duration < trg_listings_updated_at
--   < trg_reservation_requires_disclosure.
--   The name sorts the lock AFTER the two guards whose refusals clients already handle and BEFORE the guards it
--   never overlaps (identity, proof, visibility, end time: none of their columns is in the 17):
--     - a state-column change is still answered by guard_listing_state first (EDT-8 unchanged, 240 C3);
--     - on a locked listing, prohibited text still gets PROHIBITED_CONTENT and a suspended seller still gets
--       ACCOUNT_SUSPENDED first — the hints readServerRefusal maps today — exactly as before (240 C1/C4; suite
--       219 G4 is per-assertion identical with and without 170). The lock answers only an edit those accept.
--   A first draft named the trigger trg_guard_listing_activity_lock (sorting BEFORE the content guard); the
--   regression run showed 219 G4 flip from ACCOUNT_SUSPENDED to the lock's hint, so the order was changed
--   (private-evidence/A-sprint-20261021/a2/p1/03_regress_prod_try1.out).
--   DELETE: trg_guard_listing_delete is the only BEFORE DELETE (and the only non-internal DELETE) trigger on listings;
--   the seven foreign-key actions on listings are AFTER ROW RI triggers and run only if it returns OLD (240 E30).
--
-- CALLERS (enumerated 2026-10-21; producers whose accepted inputs narrow):
--   cancel_listing:
--     - app/my-listings.tsx:177 and src/screens/ListingDetailScreen.tsx:970 (e46fc203; :977 on next 61edd69f):
--       Cancel on an own listing. New refusals reach them only on a held listing or an ended-with-winner one;
--       they show error.message, which is a user-presentable sentence. C can key on the HINTs (CFT-703).
--     - web/src/lib/seller-listings.ts:204-218 cancelSellerListing: already refuses ENDED/SOLD client-side;
--       a held listing now gets the new sentence (mapSellerError passes unknown text through).
--     - sprint-control/RELIST_FOUR_LISTINGS_7D_20261021.sql: claims-less postgres, cancel_listing ->
--       admin_relist_listing on ENDED listings with no winner, no hold, no bid (its own pre-checks): unaffected
--       (pgTAP 240 A1-A7 run that exact shape).
--     - scripts/appreview-hide-stale-listings.sql (one-off, 2026-07-24): cancels EVERY active/ended listing in
--       one SELECT. After 170 that SELECT aborts if any such row has a winner; add "AND l.winner_user_id IS
--       NULL" before any re-use.
--     - Not callers: market.cancel_listing(uuid, text, text) (native rail, own table); ops.action_dispatch
--       (listing_relist calls admin_relist_listing only); no edge function; the admin console has no cancel.
--     - Internal UPDATEs that cancel without this RPC (kernel.sweep_deletion_pending, delete_account_cleanup)
--       are unchanged.
--   listings DELETE (the guard narrows what is accepted; every producer enumerated 2026-10-21 at e46fc203):
--     - app/my-listings.tsx:158 and src/screens/ListingDetailScreen.tsx:927-931:
--       supabase.from('listings').delete().eq('id', id).eq('seller_id', uid). Their own gates (:152, :911) already
--       refuse bid_count > 0 / sold; the guard adds what they miss: a stale bid_count (a tab loaded before the first
--       bid), a live or unswept hold (status 'reserved', auction_status still 'active'), a once-sold row. They show
--       error.message raw ("Delete failed"); the sentence is user-presentable, and C can key on LISTING_DELETE_LOCKED.
--     - web/src/lib/seller-listings.ts:235 deleteSellerListing, after its badge gate and countRealBids (:227-232):
--       mapSellerError (:141-153) passes unknown text through, so a bid or hold that lands between its count and its DELETE
--       now gets the sentence instead of a cascade.
--     - the legacy web bundle (G's call list, 1 site): the same request, same outcome.
--     - Not callers: no SQL function in any schema deletes from listings and no foreign key cascades into listings
--       (listings_seller_id_fkey is NO ACTION) — W00_catalog.out; no edge function and no console code deletes a
--       listing; claims-less operator SQL stays trusted. Existing suites that delete listings (030 anon 0-row, 185
--       claims-less cleanups, 221 K1-K5) are unaffected (W04 regression).
--   listings content UPDATEs: only the two edit paths above. The lock is reached through a stale form, a direct
--     request, the APP's edit screen on a held listing (its gate ignores status 'reserved'), and either client on
--     a lapsed hold not yet swept (status still 'reserved' until cleanup_expired_reservations runs; the web badge
--     reads that as ACTIVE). Both show error.message raw today: the new sentence is user-presentable, and C can
--     key on HINT LISTING_LOCKED_FOR_EDIT (CFT-703). No definer RPC, edge function, cron job or ops
--     action writes a locked column (every UPDATE public.listings in the replay catalog was read: state,
--     end-time and seller_id columns only); service_role and the claims-less path stay trusted.
--
-- NOT CHANGED (report only): the F10-adjacent starting_bid / current_bid floor (bid rules unchanged; an edit of
--   starting_bid while bid_count = 0 stays allowed); a hold that lapsed with a succeeded but unsettled payment
--   (webhook lag) stays cancellable; a winner who never pays keeps the listing uncancellable by its seller (the
--   unpaid-winner path is an owner decision). Table grants: anon and authenticated keep DELETE on listings (anon's,
--   refused by RLS today, is registry 174's revoke, not this file's); the delete guard works inside that grant.
--
-- ROLLOUT (each step an owner decision, after 2026-10-28 03:47:04Z and build 29's review):
--   1. Apply this file (one transaction; lock_timeout 3s; each CREATE TRIGGER takes SHARE ROW EXCLUSIVE on
--      public.listings for an instant; no row is read or written).
--   2. Clients: none required. C may map the eight HINTs (CFT-703 catalogue): cancel_listing's six,
--      LISTING_LOCKED_FOR_EDIT and LISTING_DELETE_LOCKED.
-- ROLLBACK: supabase/rollbacks/20261021130000_listing_seller_integrity_rollback.sql — refuses unless the 170
--   bodies are the ones installed (no silent revert of a later change; a partial 170 is refused too), drops both
--   triggers and both functions, restores cancel_listing VERBATIM from production and verifies its md5 and ACL; any
--   mismatch RAISEs and nothing changes.
-- CI (four-file rule, read from the files):
--   - supabase/ci/assert_public_table_grant_decisions.sql:474-479: +('guard_listing_edit_lock()', 'no-client-execute'),
--     +('guard_listing_delete()', 'no-client-execute') (the SEC-2/F2 gate fails closed on a public function with no
--     row; cancel_listing keeps its row at :493).
--   - .github/workflows/ci.yml Gate-2 census (public schema only, :605-615): EXPECT_FUNCS 126 -> 128 (:688-694),
--     EXPECT_TRIGGERS 49 -> 51 (:707-710); EXPECT_TABLES 35 (:661) and EXPECT_POLICIES 37 (:697) unchanged. The same
--     census is pinned in pgTAP 162 P2/P4 (supabase/tests/162_payout_reversal_and_obligation_recovery.sql:697-709),
--     moved with it. CENSUS COLLISION: 172 (20261021132000, PR #128) moves the same two lines and the same two 162
--     pins 126 -> 127 / 49 -> 50 from the same base (bfc5cf97); whichever of 170 (PR #126) and 172 merges second
--     rebases all four to 129 functions / 52 triggers (170 +2/+2, 172 +1/+1). 128/51 alone does not say which set
--     landed: 170 as extended here alone and 170 as first reviewed (+1/+1) plus 172 both give 128/51, so a rebase
--     must recount from the replay, never add to whatever number is on the line. 175 (20261021135000, local draft at
--     2026-10-21) also moves functions 126 -> 127; 170 + 172 + 175 together = 130 functions / 52 triggers.
--   - supabase/ci/expected_grants.txt: unchanged. It is the TABLE grant matrix (information_schema.role_table_grants,
--     ci.yml:735-746); 170 creates no table and changes no table or column grant (listings rows :5, :23, :48 stand:
--     the guard refuses inside the DELETE the grant still allows).
--   - supabase/rollbacks/20261021130000_listing_seller_integrity_rollback.sql: below.
-- VERIFY (read-only):
--   select md5(pg_get_functiondef('public.cancel_listing(uuid,uuid)'::regprocedure));        -- 170 body, see 240 D6
--   select md5(pg_get_functiondef('public.guard_listing_edit_lock()'::regprocedure));
--   select md5(pg_get_functiondef('public.guard_listing_delete()'::regprocedure));           -- see 240 E31
--   select pg_get_triggerdef(oid) from pg_trigger where tgname in ('trg_guard_listing_edit_lock', 'trg_guard_listing_delete');
-- FAILURE BEHAVIOUR: one transaction. The pre-flight RAISE, a lock timeout or any error leaves the database
--   exactly as it was.
-- OWNER APPROVAL POINT: prepared and tested locally only; applying it is a separate owner approval.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ── 1. pre-flight (read-only) ───────────────────────────────────────────────
DO $pre170$
DECLARE
  v_md5 text := md5(pg_get_functiondef('public.cancel_listing(uuid,uuid)'::regprocedure));
BEGIN
  IF v_md5 IS DISTINCT FROM 'ba31642267e65fefbf9485a144efc753' THEN
    RAISE EXCEPTION '170 pre-flight refused: public.cancel_listing is not the production body (md5 %, expected ba31642267e65fefbf9485a144efc753). Re-derive 170 from the live body. Nothing changed.', v_md5;
  END IF;
  IF to_regprocedure('public.guard_listing_edit_lock()') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.listings'::regclass AND tgname = 'trg_guard_listing_edit_lock') THEN
    RAISE EXCEPTION '170 pre-flight refused: guard_listing_edit_lock or trg_guard_listing_edit_lock already exists. Nothing changed.';
  END IF;
  IF to_regprocedure('public.guard_listing_delete()') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.listings'::regclass AND tgname = 'trg_guard_listing_delete') THEN
    RAISE EXCEPTION '170 pre-flight refused: guard_listing_delete or trg_guard_listing_delete already exists. Nothing changed.';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.listings'::regclass AND NOT tgisinternal AND (tgtype & 8) = 8) THEN
    RAISE EXCEPTION '170 pre-flight refused: public.listings already has a DELETE trigger (production has none). Re-derive 170. Nothing changed.';
  END IF;
END
$pre170$;

-- Capture cancel_listing's grants, definer flag and search_path BEFORE the replacement, so the post-check proves this
-- file changed none of them in WHATEVER environment it runs in (171's b84c8e05 pattern). On production these are
-- postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres / SECURITY DEFINER / search_path=public (the
-- values an earlier draft of the post-check pinned literally); CI's fresh chain may carry a different pre-existing ACL
-- (BE-37 drift), which 170 must not touch either.
CREATE TEMP TABLE m170_pre ON COMMIT DROP AS
SELECT 'public.cancel_listing(uuid,uuid)'::text AS sig, array_to_string(p.proacl, ',') AS acl, p.prosecdef AS secdef,
       array_to_string(p.proconfig, ',') AS config
  FROM pg_catalog.pg_proc p WHERE p.oid = 'public.cancel_listing(uuid,uuid)'::regprocedure;

-- ── 2. cancel_listing (production body + HINTs + two refusals) ──────────────
CREATE OR REPLACE FUNCTION public.cancel_listing(p_listing_id uuid, p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_caller_id uuid; v_seller_id uuid; v_status text; v_auction_status text;
        v_reserved_until timestamptz; v_winner_user_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL AND public.request_is_service_role() THEN v_caller_id := p_user_id; END IF;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.'
    USING ERRCODE = 'P0001', HINT = 'CALLER_UNKNOWN'; END IF;

  SELECT seller_id, status, auction_status, reserved_until, winner_user_id
    INTO v_seller_id, v_status, v_auction_status, v_reserved_until, v_winner_user_id
    FROM public.listings WHERE id = p_listing_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Listing not found.' USING ERRCODE = 'P0001', HINT = 'LISTING_NOT_FOUND'; END IF;
  IF v_seller_id IS DISTINCT FROM v_caller_id THEN RAISE EXCEPTION 'You can only cancel your own listings.'
    USING ERRCODE = 'P0001', HINT = 'NOT_LISTING_OWNER'; END IF;
  IF v_status = 'sold' THEN RAISE EXCEPTION 'This listing has already been sold and cannot be cancelled.'
    USING ERRCODE = 'P0001', HINT = 'LISTING_ALREADY_SOLD'; END IF;
  IF v_auction_status = 'cancelled' THEN RETURN; END IF;
  -- 170: a live Buy Now hold (the buyer may be paying). A lapsed hold (reserved_until <= now()) is cleared below.
  IF v_status = 'reserved' AND v_reserved_until > now() THEN
    RAISE EXCEPTION 'This listing has a buyer checking out right now and can''t be cancelled.'
      USING ERRCODE = 'P0001', HINT = 'LISTING_HELD';
  END IF;
  -- 170: an ended auction whose winner may be paying.
  IF v_winner_user_id IS NOT NULL THEN
    RAISE EXCEPTION 'This auction already has a winner and can''t be cancelled.'
      USING ERRCODE = 'P0001', HINT = 'LISTING_HAS_WINNER';
  END IF;

  PERFORM set_config('app.bypass_listing_guard', 'on', true);
  UPDATE public.listings
     SET auction_status='cancelled', status='active', reserved_by=NULL,
         reserved_until=NULL, ended_at=now()
   WHERE id = p_listing_id;
END; $function$;

-- ── 3. the content lock ─────────────────────────────────────────────────────
CREATE FUNCTION public.guard_listing_edit_lock()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_role       text;
  v_claims     text;
  v_claim_role text;
BEGIN
  -- Not locked: no bid, no Buy Now hold, no sale.
  IF NOT (OLD.bid_count > 0 OR OLD.status IN ('reserved', 'sold') OR OLD.sold_at IS NOT NULL) THEN
    RETURN NEW;
  END IF;
  -- Nothing the buyers saw changes (the edit screen re-sends unchanged fields).
  IF  NEW.event_name                    IS NOT DISTINCT FROM OLD.event_name
  AND NEW.venue                         IS NOT DISTINCT FROM OLD.venue
  AND NEW.neighborhood                  IS NOT DISTINCT FROM OLD.neighborhood
  AND NEW.event_date                    IS NOT DISTINCT FROM OLD.event_date
  AND NEW.event_time                    IS NOT DISTINCT FROM OLD.event_time
  AND NEW.ticket_type                   IS NOT DISTINCT FROM OLD.ticket_type
  AND NEW.quantity                      IS NOT DISTINCT FROM OLD.quantity
  AND NEW.transfer_method               IS NOT DISTINCT FROM OLD.transfer_method
  AND NEW.restrictions                  IS NOT DISTINCT FROM OLD.restrictions
  AND NEW.starting_bid                  IS NOT DISTINCT FROM OLD.starting_bid
  AND NEW.buy_now_enabled               IS NOT DISTINCT FROM OLD.buy_now_enabled
  AND NEW.buy_now_price                 IS NOT DISTINCT FROM OLD.buy_now_price
  AND NEW.starts_at                     IS NOT DISTINCT FROM OLD.starts_at
  AND NEW.cover_image_path              IS NOT DISTINCT FROM OLD.cover_image_path
  AND NEW.ticket_platform               IS NOT DISTINCT FROM OLD.ticket_platform
  AND NEW.seller_commitment_accepted_at IS NOT DISTINCT FROM OLD.seller_commitment_accepted_at
  AND NEW.category                      IS NOT DISTINCT FROM OLD.category THEN
    RETURN NEW;
  END IF;
  -- The guards' trust test (155/156), read the 119 way (role GUC + request claims; never current_user alone).
  v_role   := coalesce(nullif(current_setting('role', true), 'none'), current_user::text);
  v_claims := nullif(current_setting('request.jwt.claims', true), '');
  IF v_claims IS NOT NULL THEN
    BEGIN
      v_claim_role := v_claims::jsonb ->> 'role';
    EXCEPTION WHEN others THEN
      v_claim_role := NULL;   -- unparseable claims assert nothing
    END;
  END IF;
  IF v_role = 'service_role' AND coalesce(v_claim_role, 'service_role') = 'service_role' THEN
    RETURN NEW;
  END IF;
  IF v_role = 'postgres' AND v_claims IS NULL THEN
    RETURN NEW;               -- migrations, cron, the SQL editor: no request context
  END IF;
  RAISE EXCEPTION 'This listing can''t be edited after it has bids, a buyer checking out, or a sale.'
    USING ERRCODE = 'P0001', HINT = 'LISTING_LOCKED_FOR_EDIT';
END;
$function$;
REVOKE ALL ON FUNCTION public.guard_listing_edit_lock() FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public.guard_listing_edit_lock() IS
  '170: once a listing has a bid, a Buy Now hold or a sale, an untrusted change of its 17 content columns is refused (LISTING_LOCKED_FOR_EDIT). Trusted: service_role, claims-less postgres.';

CREATE TRIGGER trg_guard_listing_edit_lock
  BEFORE UPDATE OF event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
                   restrictions, starting_bid, buy_now_enabled, buy_now_price, starts_at, cover_image_path,
                   ticket_platform, seller_commitment_accepted_at, category
  ON public.listings
  FOR EACH ROW EXECUTE FUNCTION public.guard_listing_edit_lock();

-- ── 4. the delete lock ──────────────────────────────────────────────────────
CREATE FUNCTION public.guard_listing_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_role       text;
  v_claims     text;
  v_claim_role text;
BEGIN
  -- Not locked: no bid (counter or row), no Buy Now hold (live, or lapsed but not yet swept), no sale.
  IF NOT (OLD.bid_count > 0
          OR OLD.status IN ('reserved', 'sold')
          OR OLD.sold_at IS NOT NULL
          OR (OLD.reserved_until IS NOT NULL AND OLD.reserved_until > now())
          OR EXISTS (SELECT 1 FROM public.bids b WHERE b.listing_id = OLD.id)) THEN
    RETURN OLD;
  END IF;
  -- The guards' trust test (155/156), read the 119 way (role GUC + request claims; never current_user alone).
  v_role   := coalesce(nullif(current_setting('role', true), 'none'), current_user::text);
  v_claims := nullif(current_setting('request.jwt.claims', true), '');
  IF v_claims IS NOT NULL THEN
    BEGIN
      v_claim_role := v_claims::jsonb ->> 'role';
    EXCEPTION WHEN others THEN
      v_claim_role := NULL;   -- unparseable claims assert nothing
    END;
  END IF;
  IF v_role = 'service_role' AND coalesce(v_claim_role, 'service_role') = 'service_role' THEN
    RETURN OLD;
  END IF;
  IF v_role = 'postgres' AND v_claims IS NULL THEN
    RETURN OLD;               -- migrations, cron, the SQL editor: no request context
  END IF;
  RAISE EXCEPTION 'This listing can''t be deleted after it has bids, a buyer checking out, or a sale. Cancel it instead.'
    USING ERRCODE = 'P0001', HINT = 'LISTING_DELETE_LOCKED';
END;
$function$;
REVOKE ALL ON FUNCTION public.guard_listing_delete() FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public.guard_listing_delete() IS
  '170: once a listing has a bid (counter or row), a Buy Now hold or a sale, an untrusted DELETE is refused before any cascade (LISTING_DELETE_LOCKED). Trusted: service_role, claims-less postgres.';

CREATE TRIGGER trg_guard_listing_delete
  BEFORE DELETE ON public.listings
  FOR EACH ROW EXECUTE FUNCTION public.guard_listing_delete();

-- ── 5. post-check (inside the transaction: a mismatch aborts the whole apply) ─
DO $post170$
DECLARE
  v_bad text;
BEGIN
  -- Production values (verified on the production replay; informational): cancel_listing(uuid,uuid)
  --   postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres / secdef true / search_path=public.
  -- The check compares with the captured pre-apply state (m170_pre), not with these literals.
  IF (SELECT count(*) FROM m170_pre) <> 1 THEN
    RAISE EXCEPTION '170 post-check failed: the pre-apply state of cancel_listing was not captured. Nothing changed.';
  END IF;
  SELECT 'acl ' || coalesce(v.acl, '<null>') || ' -> ' || coalesce(array_to_string(p.proacl, ','), '<null>')
         || ' secdef ' || coalesce(v.secdef::text, '<null>') || ' -> ' || coalesce(p.prosecdef::text, '<missing>')
         || ' config ' || coalesce(v.config, '<null>') || ' -> ' || coalesce(array_to_string(p.proconfig, ','), '<null>')
    INTO v_bad
    FROM m170_pre v LEFT JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure(v.sig)
   WHERE array_to_string(p.proacl, ',') IS DISTINCT FROM v.acl
      OR p.prosecdef IS DISTINCT FROM v.secdef
      OR array_to_string(p.proconfig, ',') IS DISTINCT FROM v.config;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '170 post-check failed: cancel_listing grant, definer or search_path changed by this file: %. Nothing changed.', v_bad;
  END IF;
  IF has_function_privilege('anon', 'public.guard_listing_edit_lock()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.guard_listing_edit_lock()', 'EXECUTE') THEN
    RAISE EXCEPTION '170 post-check failed: a client role can EXECUTE guard_listing_edit_lock. Nothing changed.';
  END IF;
  IF has_function_privilege('anon', 'public.guard_listing_delete()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.guard_listing_delete()', 'EXECUTE') THEN
    RAISE EXCEPTION '170 post-check failed: a client role can EXECUTE guard_listing_delete. Nothing changed.';
  END IF;
  IF (SELECT count(*) FROM pg_trigger WHERE tgrelid = 'public.listings'::regclass AND NOT tgisinternal AND (tgtype & 8) = 8) <> 1
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.listings'::regclass AND tgname = 'trg_guard_listing_delete'
                       AND tgfoid = 'public.guard_listing_delete()'::regprocedure AND tgenabled = 'O') THEN
    RAISE EXCEPTION '170 post-check failed: trg_guard_listing_delete is not the one enabled DELETE trigger on listings. Nothing changed.';
  END IF;
  RAISE NOTICE '170 applied: cancel_listing md5 % (grants, definer and search_path unchanged from the pre-apply state), guard_listing_edit_lock md5 %, guard_listing_delete md5 %',
    md5(pg_get_functiondef('public.cancel_listing(uuid,uuid)'::regprocedure)),
    md5(pg_get_functiondef('public.guard_listing_edit_lock()'::regprocedure)),
    md5(pg_get_functiondef('public.guard_listing_delete()'::regprocedure));
END
$post170$;

COMMIT;

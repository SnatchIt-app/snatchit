-- =============================================================================
-- 046_guard_bid_count_columns.sql
--
-- Closes a privilege gap found while building the web seller-management
-- surface (2026-08-04).
--
-- guard_listing_state_columns() blocks direct seller writes to the auction
-- state columns, but it omitted `bid_count` and `highest_bidder_id`. The
-- listings UPDATE policy is ownership-only, so a seller could run
--
--     update listings set bid_count = 0 where id = <own listing>
--
-- and thereby satisfy every "no bids yet" gate — edit-after-bids and
-- delete-after-bids are enforced only by client-side checks that key off
-- bid_count (mobile app/listing/edit/[id].tsx and my-listings.tsx; the web
-- server actions now count real `bids` rows instead). Zeroing bid_count also
-- silently corrupts the listing card and the seller dashboard.
--
-- The only function that legitimately writes these columns is
-- validate_and_apply_bid(), which already sets app.bypass_listing_guard
-- before its UPDATE (verified live: it is the sole public function
-- referencing either column), so tightening the guard breaks no server path.
--
-- Step 1 reconciles any existing drift from the real `bids` rows. One row is
-- currently drifted (bid_count = 2 with zero bid rows, left over from
-- deleted test bids). This is a corrective write, not a destructive one:
-- bid_count/highest_bidder_id are derived values, and `bids` is the source
-- of truth.
--
-- Step 2 adds both columns to the guard.
--
-- Rollback: supabase/rollbacks/046_guard_bid_count_columns_rollback.sql
-- =============================================================================

BEGIN;

-- ── Step 1: reconcile derived bid state from the authoritative bids rows ────
DO $reconcile$
BEGIN
  PERFORM set_config('app.bypass_listing_guard', 'on', true);

  UPDATE public.listings l
     SET bid_count         = s.real_count,
         highest_bidder_id = s.top_bidder
    FROM (
      SELECT l2.id,
             (SELECT count(*)
                FROM public.bids b
               WHERE b.listing_id = l2.id) AS real_count,
             (SELECT b.bidder_id
                FROM public.bids b
               WHERE b.listing_id = l2.id
               ORDER BY b.amount DESC, b.created_at DESC
               LIMIT 1)                    AS top_bidder
        FROM public.listings l2
    ) s
   WHERE l.id = s.id
     AND (l.bid_count         IS DISTINCT FROM s.real_count
       OR l.highest_bidder_id IS DISTINCT FROM s.top_bidder);
END
$reconcile$;

-- ── Step 2: extend the guard ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.guard_listing_state_columns()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF current_setting('app.bypass_listing_guard', true) = 'on' THEN
    RETURN NEW;
  END IF;

  IF NEW.current_bid        IS DISTINCT FROM OLD.current_bid
  OR NEW.bid_count          IS DISTINCT FROM OLD.bid_count
  OR NEW.highest_bidder_id  IS DISTINCT FROM OLD.highest_bidder_id
  OR NEW.status             IS DISTINCT FROM OLD.status
  OR NEW.auction_status     IS DISTINCT FROM OLD.auction_status
  OR NEW.winner_user_id     IS DISTINCT FROM OLD.winner_user_id
  OR NEW.winning_bid_amount IS DISTINCT FROM OLD.winning_bid_amount
  OR NEW.reserved_by        IS DISTINCT FROM OLD.reserved_by
  OR NEW.reserved_until     IS DISTINCT FROM OLD.reserved_until
  OR NEW.sold_at            IS DISTINCT FROM OLD.sold_at
  OR NEW.ended_at           IS DISTINCT FROM OLD.ended_at
  THEN
    RAISE EXCEPTION 'Cannot directly modify auction state columns. Use the appropriate RPC.';
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.guard_listing_state_columns() IS
  'Blocks direct client writes to auction state columns on public.listings. bid_count and highest_bidder_id added in migration 046 — they are derived from public.bids and were previously seller-writable. Server paths set app.bypass_listing_guard.';

COMMIT;

-- Rollback for 046_guard_bid_count_columns.sql
--
-- Restores guard_listing_state_columns() to its pre-046 column list, i.e.
-- makes bid_count and highest_bidder_id directly writable by the owning
-- seller again. The Step-1 data reconciliation is NOT reverted — it corrected
-- derived values to match the authoritative `bids` rows, and re-introducing
-- drift would be a regression, not a restoration.

BEGIN;

CREATE OR REPLACE FUNCTION public.guard_listing_state_columns()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF current_setting('app.bypass_listing_guard', true) = 'on' THEN
    RETURN NEW;
  END IF;

  IF NEW.current_bid        IS DISTINCT FROM OLD.current_bid
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

COMMIT;

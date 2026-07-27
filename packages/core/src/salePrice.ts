/**
 * salePrice — derive the ACTUAL final sale price of a sold listing.
 *
 * Why: `mark_listing_sold` (Buy Now path, migration 003) never touches
 * `current_bid` or `winning_bid_amount`, so a Buy Now sale leaves
 * `current_bid` at the last auction bid (or starting bid). Any UI that
 * shows "Sold for ${current_bid}" is therefore wrong for Buy Now sales.
 *
 * Source priority:
 *   1. winning_bid_amount — stamped by finalize_auction; present ⟺ the
 *      listing sold through the auction path. This equals the amount the
 *      winner was charged (pre buyer-fee), so it doubles as the "actual
 *      payment amount" — payments rows themselves are RLS-restricted to
 *      the buyer/seller and unavailable to public viewers of sold cards.
 *   2. buy_now_price — no winning bid stamped ⇒ the sale went through
 *      Buy Now; the charge base was exactly buy_now_price.
 *   3. current_bid — legacy/fallback only.
 *
 * All three fields share the same unit (whole dollars, as displayed).
 */

type SoldPriceFields = {
  buy_now_enabled: boolean;
  buy_now_price: number | null;
  current_bid: number;
  winning_bid_amount?: number | null;
};

export function finalSoldPrice(l: SoldPriceFields): number {
  // Auction sale — finalize_auction stamped the winning bid.
  if (l.winning_bid_amount != null && l.winning_bid_amount > 0) {
    return l.winning_bid_amount;
  }
  // Buy Now sale — no winning bid stamped; the charge was buy_now_price.
  if (l.buy_now_enabled && l.buy_now_price != null && l.buy_now_price > 0) {
    return l.buy_now_price;
  }
  return l.current_bid;
}

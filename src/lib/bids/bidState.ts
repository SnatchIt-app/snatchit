/**
 * src/lib/bids/bidState.ts — what one row on the Bids screen means.
 *
 * The Bids screen carries two things the product deliberately merged into one
 * list: auction bids the user placed, and purchases the user made (Buy Now, or an
 * auction win that completed checkout). A purchase is tracked by its transfer
 * lifecycle, a bid by the auction. This module is the single, pure, tested mapping
 * from a row to its status, its group, its copy, its next action and the one price
 * worth showing — the counterpart to detailState and cardState.
 *
 * IT DECIDES NO MONEY. It selects which existing WHOLE-DOLLAR column the displayed
 * amount comes from; formatting stays with allInFromDollars at the call site.
 *
 * kernel.tickets IS NOT TOUCHED. Everything here is derived from bids, listings
 * and transfers, which is all the authenticated client is granted today. There is
 * no ticket object and no ownership model beyond the transfer state machine.
 */

export type BidStatus =
  | 'winning'
  | 'outbid'
  | 'won'                // auction ended, this user won, payment not yet completed
  | 'lost'
  | 'sold'               // the listing sold via Buy Now to someone (or this user, pre-transfer)
  | 'awaiting_transfer'  // purchased; transfer.status = 'pending'
  | 'seller_sent'        // transfer.status = 'seller_sent'
  | 'purchase_disputed'  // transfer.status = 'disputed'
  | 'purchase_confirmed'; // 'buyer_confirmed' | 'auto_released'

export type TransferStatusLike =
  | 'pending' | 'seller_sent' | 'disputed' | 'buyer_confirmed' | 'auto_released';

/** The minimal row shape the mapping needs. Mirrors the screen's BidRow. */
export interface BidRowInput {
  amount: number;                 // WHOLE DOLLARS — the user's max bid, or the sale price for a purchase row
  purchaseTransferStatus?: TransferStatusLike;
  needsDeliveryInfo?: boolean;
  transferId?: string | null;
  listing: {
    status: string;
    auction_status?: string | null;
    ends_at: string;
    current_bid: number;          // WHOLE DOLLARS
    winner_user_id?: string | null;
    winning_bid_amount?: number | null; // WHOLE DOLLARS
    buy_now_enabled?: boolean;
    buy_now_price?: number | null; // WHOLE DOLLARS
  } | null;
}

/**
 * The status of a row. This is the previous screen's getBidStatus, unchanged in
 * behaviour, made pure and testable. Purchase state takes precedence over bid
 * state: once the user owns the ticket, the transfer is the source of truth.
 */
export function bidStatusOf(row: BidRowInput, userId: string): BidStatus {
  switch (row.purchaseTransferStatus) {
    case 'pending':         return 'awaiting_transfer';
    case 'seller_sent':     return 'seller_sent';
    case 'disputed':        return 'purchase_disputed';
    case 'buyer_confirmed':
    case 'auto_released':   return 'purchase_confirmed';
  }

  const l = row.listing;
  if (!l) return 'lost';
  if (l.status === 'sold') return 'sold';
  if (l.auction_status === 'ended') {
    return l.winner_user_id === userId ? 'won' : 'lost';
  }
  // Clock run out but not finalised yet — conservative until finalize_auction.
  if (new Date(l.ends_at).getTime() <= Date.now()) return 'lost';
  return row.amount >= l.current_bid ? 'winning' : 'outbid';
}

export type BidGroup = 'active' | 'past';
export type BidTone = 'brand' | 'success' | 'warning' | 'danger' | 'neutral';

/**
 * Active = anything live or awaiting the user's attention; Past = settled history.
 * Replaces the previous six-pill filter strip: the dataset is small and the six
 * states collapse cleanly into "needs me / does not".
 */
export function bidGroupOf(status: BidStatus): BidGroup {
  switch (status) {
    case 'lost':
    case 'sold':
    case 'purchase_confirmed':
      return 'past';
    default:
      return 'active';
  }
}

/** Whether the row needs an action from the user right now (for ordering and a count). */
export function needsAction(status: BidStatus): boolean {
  return status === 'won'
    || status === 'outbid'
    || status === 'awaiting_transfer'
    || status === 'seller_sent'
    || status === 'purchase_disputed';
}

export interface BidPresentation {
  status: BidStatus;
  group: BidGroup;
  /** Short badge word. No emoji, no color-only meaning. */
  label: string;
  tone: BidTone;
  /** The one action the row leads with. */
  actionHint: string;
  /** True when the row routes to the transfer flow rather than the listing. */
  routesToTransfer: boolean;
  /** Lower sorts higher within a group, so the most urgent card is on top. */
  priority: number;
  /** Primary amount to show, WHOLE DOLLARS, formatted all-in by the caller. */
  priceLabel: string;
  priceDollars: number;
  /** Optional secondary amount (e.g. the user's own max under the current bid). */
  secondaryLabel?: string;
  secondaryDollars?: number;
}

/** Sale price by the same priority the rest of the app uses (see salePrice.ts). */
function saleDollars(l: NonNullable<BidRowInput['listing']>): number {
  if (l.winning_bid_amount != null && l.winning_bid_amount > 0) return l.winning_bid_amount;
  if (l.buy_now_enabled && l.buy_now_price != null && l.buy_now_price > 0) return l.buy_now_price;
  return l.current_bid;
}

export function bidPresentation(row: BidRowInput, userId: string): BidPresentation {
  const status = bidStatusOf(row, userId);
  const group = bidGroupOf(status);
  const l = row.listing;

  const base = (over: Partial<BidPresentation>): BidPresentation => ({
    status, group,
    label: '', tone: 'neutral', actionHint: 'View listing',
    routesToTransfer: false, priority: 9,
    priceLabel: 'Current bid', priceDollars: l?.current_bid ?? 0,
    ...over,
  });

  switch (status) {
    case 'purchase_disputed':
      return base({ label: 'Disputed', tone: 'danger', actionHint: 'View dispute',
        routesToTransfer: true, priority: 0,
        priceLabel: 'Paid', priceDollars: row.amount });
    case 'won':
      return base({ label: 'Won', tone: 'brand', actionHint: 'Pay to claim', priority: 1,
        priceLabel: 'You pay', priceDollars: l ? saleDollars(l) : row.amount });
    case 'seller_sent':
      return base({ label: 'Tickets sent', tone: 'warning', actionHint: 'Confirm receipt',
        routesToTransfer: true, priority: 2,
        priceLabel: 'Paid', priceDollars: row.amount });
    case 'awaiting_transfer':
      return base({
        label: 'Purchased', tone: 'warning',
        actionHint: row.needsDeliveryInfo ? 'Add transfer info' : 'Waiting for the seller',
        routesToTransfer: true, priority: 3,
        priceLabel: 'Paid', priceDollars: row.amount });
    case 'outbid':
      return base({ label: 'Outbid', tone: 'danger', actionHint: 'Bid again', priority: 4,
        priceLabel: 'Current bid', priceDollars: l?.current_bid ?? 0,
        secondaryLabel: 'Your max', secondaryDollars: row.amount });
    case 'winning':
      return base({ label: 'Winning', tone: 'success', actionHint: "You're leading", priority: 5,
        priceLabel: 'Current bid', priceDollars: l?.current_bid ?? 0,
        secondaryLabel: 'Your max', secondaryDollars: row.amount });
    case 'purchase_confirmed':
      return base({ label: 'Confirmed', tone: 'success', actionHint: 'View transfer',
        routesToTransfer: true, priority: 6,
        priceLabel: 'Paid', priceDollars: row.amount });
    case 'sold':
      return base({ label: 'Sold', tone: 'neutral', actionHint: 'View listing', priority: 7,
        priceLabel: 'Sold for', priceDollars: l ? saleDollars(l) : row.amount });
    case 'lost':
    default:
      return base({ label: 'Ended', tone: 'neutral', actionHint: 'View listing', priority: 8,
        priceLabel: l?.winning_bid_amount ? 'Winning bid' : 'Final bid',
        priceDollars: l?.winning_bid_amount ?? l?.current_bid ?? 0 });
  }
}

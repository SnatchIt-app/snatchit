/**
 * src/lib/listing/detailState.ts — what a listing detail screen is currently OFFERING.
 *
 * WHY THIS IS A MODULE AND NOT JSX
 * The old screen decided all of this inline, spread across a dozen booleans that
 * were then re-combined at five different render sites. Two consequences it
 * actually shipped: Buy Now was rendered as the visually weaker of the two
 * actions on every dual-mode listing, and a seller looking at their own listing
 * was shown an enabled "Place Bid" button whose only possible outcome is the
 * database raising "You cannot bid on your own listing" (`schema.sql`, the
 * `validate_and_apply_bid` shill-bid guard).
 *
 * Pure functions, no React and no React Native, so the mapping can be tested
 * directly. This file decides WHAT is offered. The components decide how it looks.
 *
 * IT COMPUTES NO MONEY. Every amount is a preformatted string produced by the
 * established helpers in `src/lib/money.ts` and handed in. There is exactly one
 * dollars-to-cents conversion in this app and it is not here.
 */

import type { TransferStatus } from '@/src/types';

/** Who is looking. A listing means something different to each of them. */
export type ViewerRole = 'seller' | 'buyer' | 'visitor';

/**
 * What this listing is selling, right now. `closed` covers every terminal or
 * blocked case: sold, cancelled, the clock run out, or held by someone else.
 */
export type TransactionMode = 'auction_only' | 'buy_now_only' | 'auction_and_buy_now' | 'closed';

export type ActionKind =
  | 'buy_now'
  | 'continue_reservation'
  | 'place_bid'
  | 'pay_now'
  | 'send_tickets'
  | 'review_transfer'
  | 'view_transfer'
  | 'view_dispute'
  | 'unavailable';

export interface ListingAction {
  kind: ActionKind;
  label: string;
  /** Rendered, but not tappable: the state is worth showing, the action is not available. */
  disabled?: boolean;
}

/**
 * One status at a time, chosen by priority. The old screen could stack five
 * banner rows above the artwork — SOLD, a refresh hint, a transfer button, the
 * owner-actions block and a reservation notice — which pushed the image off the
 * first screen and left the user to work out which one mattered.
 */
export type StatusKind =
  | 'sold'
  | 'won'
  | 'lost'
  | 'reserved_by_you'
  | 'reserved_by_other'
  | 'ended'
  | 'cancelled'
  | 'winning'
  | 'outbid'
  | 'finalizing'
  | 'transfer_pending';

export type StatusTone = 'brand' | 'success' | 'warning' | 'danger' | 'neutral';

export interface ListingStatus {
  kind: StatusKind;
  /** Short. It sits above the artwork and competes with nothing else. */
  label: string;
  /** One sentence of consequence, or nothing. Never a second headline. */
  detail?: string;
  tone: StatusTone;
}

export interface DetailStateInput {
  listing: {
    status: string;
    auction_status?: string | null;
    buy_now_enabled: boolean;
    buy_now_price: number | null;
    seller_id: string;
    reserved_by: string | null;
    winner_user_id?: string | null;
    bid_count?: number | null;
  };
  userId?: string;
  /** The auction clock has passed `ends_at`. */
  clockEnded: boolean;
  /** A reservation exists and has not expired. */
  reservationActive: boolean;
  /** `finalize_auction` is running right now. */
  finalizing: boolean;
  /** A Buy Now reservation is being taken right now. */
  reserving: boolean;
  transfer: { id: string | null; status: TransferStatus | null; buyerId: string | null };
  /** The viewer has bid, and their highest bid is at or above the current price. */
  isHighestBidder: boolean;
  /** The viewer has bid at all. */
  hasBid: boolean;
  /** Preformatted, all-in. From `allInFromDollars`. Never computed here. */
  buyNowAllIn: string | null;
}

export interface DetailState {
  role: ViewerRole;
  mode: TransactionMode;
  /** The one action the sticky bar leads with. */
  primary: ListingAction;
  /** At most one alternative, and only when it is genuinely a different choice. */
  secondary: ListingAction | null;
  status: ListingStatus | null;
  /** Whether the bid history section has any reason to exist on this listing. */
  showsBidActivity: boolean;
  /** Seller-only controls belong behind the overflow menu, never in the buyer flow. */
  showsOwnerActions: boolean;
}

export function viewerRole(input: DetailStateInput): ViewerRole {
  const { listing, userId, transfer } = input;
  if (userId && listing.seller_id === userId) return 'seller';
  if (userId && transfer.buyerId && transfer.buyerId === userId) return 'buyer';
  return 'visitor';
}

export function transactionMode(input: DetailStateInput): TransactionMode {
  const { listing, clockEnded, reservationActive, userId } = input;
  const auctionEnded = (listing.auction_status ?? 'active') === 'ended';
  const cancelled = listing.auction_status === 'cancelled';
  const reservedByOther =
    reservationActive && !!listing.reserved_by && listing.reserved_by !== userId;

  if (listing.status === 'sold' || cancelled || auctionEnded || clockEnded || reservedByOther) {
    return 'closed';
  }

  const buyNow = listing.buy_now_enabled && listing.buy_now_price != null;
  // A listing always carries an auction: `starting_bid` and `ends_at` are NOT
  // NULL on every row. Buy Now is the addition, never the replacement — which is
  // why there is no branch here that drops bidding.
  return buyNow ? 'auction_and_buy_now' : 'auction_only';
}

/**
 * The single status. Ordered by what a user most needs to know, not by what the
 * database most recently changed.
 */
export function listingStatus(input: DetailStateInput): ListingStatus | null {
  const { listing, userId, clockEnded, reservationActive, finalizing, transfer } = input;
  const role = viewerRole(input);
  const auctionEnded = (listing.auction_status ?? 'active') === 'ended';
  const iAmWinner = auctionEnded && !!userId && listing.winner_user_id === userId;

  if (finalizing) {
    return { kind: 'finalizing', label: 'Closing the auction', tone: 'neutral' };
  }

  if (listing.status === 'sold') {
    // For the two people in the trade, the transfer is the live fact. For
    // everyone else the listing is simply gone.
    if (role === 'seller' && transfer.status === 'pending') {
      return {
        kind: 'transfer_pending',
        label: 'Send the tickets',
        detail: 'The buyer has paid. Payment is held until they confirm.',
        tone: 'warning',
      };
    }
    if (role === 'buyer' && transfer.status === 'seller_sent') {
      return {
        kind: 'transfer_pending',
        label: 'Tickets sent',
        detail: 'Check them, then confirm so the seller gets paid.',
        tone: 'warning',
      };
    }
    if (role === 'buyer' && transfer.status === 'disputed') {
      return { kind: 'transfer_pending', label: 'Issue reported', detail: 'Support is reviewing this transfer.', tone: 'danger' };
    }
    return { kind: 'sold', label: 'Sold', tone: 'neutral' };
  }

  if (listing.auction_status === 'cancelled') {
    return { kind: 'cancelled', label: 'Listing cancelled', tone: 'neutral' };
  }

  if (auctionEnded) {
    if (iAmWinner) {
      return {
        kind: 'won',
        label: 'You won',
        detail: 'Pay to claim your tickets.',
        tone: 'success',
      };
    }
    if (input.hasBid) {
      return { kind: 'lost', label: 'Auction ended', detail: 'You did not win this one.', tone: 'neutral' };
    }
    return { kind: 'ended', label: 'Auction ended', tone: 'neutral' };
  }

  if (clockEnded) return { kind: 'ended', label: 'Auction ended', tone: 'neutral' };

  if (reservationActive && listing.reserved_by) {
    if (listing.reserved_by === userId) {
      return {
        kind: 'reserved_by_you',
        label: 'Held for you',
        detail: 'Finish checkout before the hold expires.',
        tone: 'brand',
      };
    }
    return {
      kind: 'reserved_by_other',
      label: 'Held for another buyer',
      detail: 'It comes back if they do not finish checkout.',
      tone: 'warning',
    };
  }

  // Live auction, and the viewer is in it. Both states are worth carrying at the
  // top of the screen; neither is worth a modal.
  if (input.hasBid && role !== 'seller') {
    return input.isHighestBidder
      ? { kind: 'winning', label: "You're the highest bidder", tone: 'success' }
      : { kind: 'outbid', label: "You've been outbid", detail: 'Bid again to get back in front.', tone: 'danger' };
  }

  return null;
}

/**
 * The actions the sticky bar offers.
 *
 * TWO RULES, both of which the old screen broke:
 *  1. Buy Now leads when it exists. Instant purchase is the stronger offer and
 *     was styled as the weaker button.
 *  2. Nothing is offered that cannot work. A seller was shown an enabled bid
 *     button; the database refuses that bid by design.
 */
export function listingActions(input: DetailStateInput): {
  primary: ListingAction;
  secondary: ListingAction | null;
} {
  const { listing, userId, transfer, reserving, finalizing, reservationActive } = input;
  const role = viewerRole(input);
  const mode = transactionMode(input);
  const auctionEnded = (listing.auction_status ?? 'active') === 'ended';
  const iAmWinner = auctionEnded && !!userId && listing.winner_user_id === userId;
  const reservedByMe = reservationActive && !!userId && listing.reserved_by === userId;

  // The trade is done and the ticket is moving. That outranks everything.
  if (listing.status === 'sold' && transfer.id) {
    if (role === 'seller' && transfer.status === 'pending') {
      return { primary: { kind: 'send_tickets', label: 'Send tickets' }, secondary: null };
    }
    if (role === 'seller' && transfer.status === 'seller_sent') {
      return { primary: { kind: 'view_transfer', label: 'View transfer' }, secondary: null };
    }
    if (role === 'buyer' && transfer.status === 'seller_sent') {
      return { primary: { kind: 'review_transfer', label: 'Review transfer' }, secondary: null };
    }
    if (role === 'buyer' && transfer.status === 'disputed') {
      return { primary: { kind: 'view_dispute', label: 'View dispute' }, secondary: null };
    }
    if (role === 'buyer' || role === 'seller') {
      return { primary: { kind: 'view_transfer', label: 'View transfer' }, secondary: null };
    }
  }

  if (iAmWinner) {
    return { primary: { kind: 'pay_now', label: 'Pay now' }, secondary: null };
  }

  if (mode === 'closed' || finalizing) {
    const label =
      listing.status === 'sold'
        ? 'Sold'
        : listing.auction_status === 'cancelled'
          ? 'Cancelled'
          : reservationActive && listing.reserved_by && listing.reserved_by !== userId
            ? 'On hold'
            : 'Ended';
    return { primary: { kind: 'unavailable', label, disabled: true }, secondary: null };
  }

  // The seller of a live listing is not a buyer. No bid button, no Buy Now: the
  // database refuses both, and offering them is how a screen teaches a user that
  // its buttons cannot be trusted.
  if (role === 'seller') {
    return { primary: { kind: 'unavailable', label: 'Your listing', disabled: true }, secondary: null };
  }

  if (reservedByMe) {
    return {
      primary: { kind: 'continue_reservation', label: 'Finish checkout' },
      secondary: null,
    };
  }

  const bid: ListingAction = { kind: 'place_bid', label: 'Place bid', disabled: reserving };

  if (mode === 'auction_and_buy_now') {
    return {
      primary: {
        kind: 'buy_now',
        label: input.buyNowAllIn ? `Buy now · ${input.buyNowAllIn}` : 'Buy now',
        disabled: reserving,
      },
      secondary: bid,
    };
  }

  return { primary: bid, secondary: null };
}

export function detailState(input: DetailStateInput): DetailState {
  const role = viewerRole(input);
  const mode = transactionMode(input);
  const { primary, secondary } = listingActions(input);
  return {
    role,
    mode,
    primary,
    secondary,
    status: listingStatus(input),
    // Bid history is auction information. A sold listing keeps it — how the
    // price got there is part of what the buyer bought.
    showsBidActivity: true,
    showsOwnerActions: role === 'seller',
  };
}

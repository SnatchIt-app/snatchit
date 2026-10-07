/**
 * src/lib/sell/sellState.ts — the pure, tested core of Create Listing.
 *
 * The Create screen carries a long gate chain (phone, payout, risk) and two image
 * uploads, and none of that belongs in a render function. What CAN be pulled out
 * of the component and proven in isolation lives here:
 *
 *   • validation — the exact field rules the screen submits against;
 *   • content moderation — the banned-lexicon gate (Apple 1.4.3);
 *   • risk-check parsing — the shape/'`can_create_listing`' RPC interpreter;
 *   • the money PREVIEW — which authoritative helpers feed the seller-proceeds and
 *     buyer-all-in lines, so a future edit can't silently swap in the wrong one.
 *
 * Nothing here reads React, Supabase or the theme. The screen owns the effects;
 * this owns the decisions. Money is untouched: every amount routes through
 * src/lib/money.ts and the whole-dollars listing contract is preserved.
 */

import {
  allInFromDollarsV3,
  formatDollarsV3,
  sellerNetDollars,
} from '@/src/lib/money';
import type {
  CanCreateListingReason,
  DurationHours,
  Neighborhood,
  RiskTier,
  TicketType,
  TransferMethod,
} from '@/src/types';

// ─── Amount parsing ─────────────────────────────────────────────────────────

/** Strip everything but digits. The price fields store this, never formatted text. */
export function digitsOnly(s: string): string {
  return s.replace(/\D/g, '');
}

/**
 * The integer a price string represents, or NaN when empty/non-numeric. Matches
 * the screen's historic `parseInt(value, 10)` over already-digits-only input, so
 * the number that is validated is the number that is submitted.
 */
export function parseAmount(s: string): number {
  return parseInt(s, 10);
}

// ─── Validation ───────────────────────────────────────────────────────────────

export interface SellInput {
  eventName: string;
  venue: string;
  neighborhood: Neighborhood | null;
  ticketType: TicketType | null;
  transferMethod: TransferMethod | null;
  startingBid: string;
  buyNowEnabled: boolean;
  buyNowPrice: string;
  durationHours: DurationHours | null;
  coverLocalUri: string | null;
  proofLocalUri: string | null;
  commitmentAccepted: boolean;
}

export interface SellErrors {
  eventName: string;
  venue: string;
  neighborhood: string;
  ticketType: string;
  transferMethod: string;
  startingBid: string;
  buyNowPrice: string;
  durationHours: string;
  coverImage: string;
  proofImage: string;
  commitment: string;
}

/**
 * The field rules, unchanged from the screen they came from. Buy Now must clear
 * the starting bid, and only matters when Buy Now is on. Every string here is the
 * exact message shown under the field.
 */
export function sellErrors(input: SellInput): SellErrors {
  const startingBidNum = parseAmount(input.startingBid);
  const buyNowPriceNum = parseAmount(input.buyNowPrice);
  return {
    eventName:     !input.eventName.trim()   ? 'Event name is required.'   : '',
    venue:         !input.venue.trim()       ? 'Venue is required.'        : '',
    neighborhood:  !input.neighborhood       ? 'Select a neighborhood.'    : '',
    ticketType:    !input.ticketType         ? 'Select a ticket type.'     : '',
    transferMethod:!input.transferMethod     ? 'Select a transfer method.' : '',
    startingBid:   (!input.startingBid || startingBidNum < 1)
                     ? 'Starting bid must be ≥ $1.'
                     : '',
    buyNowPrice:   input.buyNowEnabled && (!input.buyNowPrice || buyNowPriceNum <= startingBidNum)
                     ? `Buy Now must be > starting bid ($${startingBidNum || 0}).`
                     : '',
    durationHours: !input.durationHours      ? 'Select an auction duration.' : '',
    coverImage:    !input.coverLocalUri      ? 'Cover image is required.'    : '',
    proofImage:    !input.proofLocalUri      ? 'Proof of ownership is required.' : '',
    commitment:    !input.commitmentAccepted ? 'You must accept the commitment.' : '',
  };
}

export function isSellValid(errors: SellErrors): boolean {
  return Object.values(errors).every((e) => !e);
}

// ─── Selling method + CTA copy ─────────────────────────────────────────────────

/** One truthful sentence describing how the sale works given the Buy Now toggle. */
/**
 * What stops a publish BEFORE the phone, payout and risk gates run.
 *
 * `CreateListingScreen` used to spell this `if (!isValid || !user) return;` — two unrelated
 * conditions behind one silent return (E, 2026-10-05). The invalid half is not silent, because the
 * fields show their own errors; the signed-out half had nothing to say, so a seller with a complete
 * form and an ended session tapped Publish and the screen did not move.
 *
 * The session is answered first, which is the order `handleBuyNow` already uses: correcting the
 * form does not help someone who is signed out. The sentence is the app's existing one, from the
 * four places that already refuse an action to a signed-out viewer.
 */
export const PUBLISH_SIGNED_OUT = {
  title: 'Sign in required',
  body: 'You need to be signed in to publish a listing.',
} as const;

export type PublishBlock =
  /** The fields say so, and they say it themselves — this is not a dialog. */
  | { kind: 'invalid' }
  | { kind: 'signed-out'; title: string; body: string };

export function publishBlock(i: { valid: boolean; signedIn: boolean }): PublishBlock | null {
  if (!i.signedIn) return { kind: 'signed-out', ...PUBLISH_SIGNED_OUT };
  if (!i.valid) return { kind: 'invalid' };
  return null;
}

export function sellingMethodBlurb(buyNowEnabled: boolean): string {
  return buyNowEnabled
    ? 'Buyers bid until the auction ends. Buy Now also lets someone take it instantly at your set price.'
    : 'Buyers bid until the auction ends. The highest bid wins.';
}

/** The publish action says what it does, and agrees with quantity. */
export function submitCtaLabel(quantity: number): string {
  return quantity > 1 ? 'List tickets' : 'List ticket';
}

// ─── Money preview (composition only — the helpers are the authority) ──────────

export interface PriceSummary {
  /** False when the dollar amount is not a usable positive number. */
  valid: boolean;
  /** What the seller nets for the listing after the seller fee, e.g. "$81.00". */
  sellerNet: string;
  /** Seller net as a number, for the sticky bar's "You get" line. */
  sellerNetValue: number;
  /** What a buyer pays all-in for the listing, e.g. "$99.00". */
  buyerAllIn: string;
  /** The all-in with its trailing word, e.g. "$99.00 total". */
  buyerAllInLabel: string;
}

/**
 * The seller- and buyer-facing amounts for a whole-dollar listing price. This does
 * NO arithmetic of its own: it names which money helper produces each line, so the
 * preview can never drift from what the seller is actually paid or the buyer
 * actually charged. An unusable amount returns `valid: false` and empty strings.
 *
 * V3 (pkg8-create boards, 2026-09-24): the DISPLAY faces go through the V3
 * formatters — every shown amount carries its two decimals ("Buyers pay $99.00
 * total", "$81.00"). Display only: the amounts are the same seller-net and
 * buyer-all-in numbers as before, the listing is still validated, previewed and
 * submitted as whole dollars, and nothing stored or sent changes shape.
 */
export function priceSummary(dollars: number): PriceSummary {
  if (!Number.isFinite(dollars) || dollars < 1) {
    return { valid: false, sellerNet: '', sellerNetValue: 0, buyerAllIn: '', buyerAllInLabel: '' };
  }
  return {
    valid: true,
    sellerNet: formatDollarsV3(sellerNetDollars(dollars)),
    sellerNetValue: sellerNetDollars(dollars),
    buyerAllIn: allInFromDollarsV3(dollars),
    buyerAllInLabel: `${allInFromDollarsV3(dollars)} total`,
  };
}

// ─── Content moderation (Apple Guideline 1.4.3) ────────────────────────────────

const BANNED_CONTENT_PATTERNS: { pattern: RegExp; label: string }[] = [
  { pattern: /\balcohol\b/i,             label: 'alcohol' },
  { pattern: /\bdrugs?\b/i,              label: 'drugs' },
  { pattern: /\bweed\b/i,                label: 'weed' },
  { pattern: /\bcocaine\b/i,             label: 'cocaine' },
  { pattern: /\bmolly\b/i,               label: 'molly' },
  { pattern: /\bopen[\s-]?bar\b/i,       label: 'open bar' },
  { pattern: /\bbottle[\s-]?service\b/i, label: 'bottle service' },
  { pattern: /\bfake[\s-]?tickets?\b/i,  label: 'fake ticket' },
  { pattern: /\bcounterfeit\b/i,         label: 'counterfeit' },
  { pattern: /\bunderage\b/i,            label: 'underage' },
];

/** The first banned term found across the given free-text fields, or null. */
export function findBannedContent(fields: (string | null | undefined)[]): string | null {
  const haystack = fields.filter(Boolean).join(' \n ');
  for (const { pattern, label } of BANNED_CONTENT_PATTERNS) {
    if (pattern.test(haystack)) return label;
  }
  return null;
}

// ─── Risk-check parsing (can_create_listing RPC) ───────────────────────────────

export type RiskCheckResult =
  | { status: 'ok';        reason: 'ok';                   tier: RiskTier | null }
  | { status: 'warn';      reason: CanCreateListingReason; tier: RiskTier | null }
  | { status: 'block';     reason: CanCreateListingReason; tier: RiskTier | null }
  | { status: 'transient'; message: string }
  | { status: 'bad_shape'; raw: unknown };

const VALID_REASONS = new Set<CanCreateListingReason>([
  'ok', 'medium_risk_warning', 'high_risk_warning', 'critical_risk', 'listing_blocked',
]);

/**
 * Interpret the `can_create_listing` response. Fail-OPEN on a transient RPC error
 * (a listing must not be blocked because the network hiccuped), fail-CLOSED on an
 * unrecognised shape. Supabase returns RETURNS TABLE as an array, so the first row
 * is unwrapped. Behaviour is identical to the screen this came from.
 */
export function parseRiskCheckResponse(
  data: unknown,
  error: { message: string } | null,
): RiskCheckResult {
  if (error) {
    return { status: 'transient', message: error.message };
  }

  const row = Array.isArray(data) ? data[0] : data;

  if (
    !row ||
    typeof row !== 'object' ||
    typeof (row as Record<string, unknown>).allowed !== 'boolean' ||
    typeof (row as Record<string, unknown>).reason !== 'string' ||
    !VALID_REASONS.has((row as Record<string, unknown>).reason as CanCreateListingReason)
  ) {
    return { status: 'bad_shape', raw: row };
  }

  const { allowed, reason, risk_tier } = row as {
    allowed: boolean;
    reason: CanCreateListingReason;
    risk_tier: RiskTier | null;
  };

  if (!allowed) return { status: 'block', reason, tier: risk_tier };
  if (reason === 'high_risk_warning' || reason === 'medium_risk_warning') {
    return { status: 'warn', reason, tier: risk_tier };
  }
  return { status: 'ok', reason: 'ok', tier: risk_tier };
}

/**
 * The seller-facing copy for each risk reason.
 *
 * `check_unavailable` is NOT a server reason: it is the client's own state for "the check did not
 * answer". It exists because a transient failure used to borrow `medium_risk_warning`, telling a
 * seller the app had noticed recent issues on their account when in fact the request never arrived.
 * Submission still proceeds on a transient failure — only the sentence changed.
 */
export const RISK_COPY = {
  check_unavailable:   "We couldn't check your account status just now. You can still publish.",
  medium_risk_warning: "We've noticed some recent issues. Please double-check your listing details.",
  high_risk_warning:   'Your account is under review. Incorrect listings may result in restrictions.',
  critical_risk:       'You cannot create listings at this time. Contact support.',
  listing_blocked:     'You cannot create listings at this time. Contact support.',
} as const;

/**
 * Whole-listing pricing (owner ruling, 2026-09-14): the price, the fee and the
 * payout all apply to the listing as a whole, however many tickets it holds.
 * The seller's proceeds are therefore labelled for the listing, never "per
 * ticket" — the old copy said per ticket while the server paid per listing.
 */
export function proceedsLabel(sellerNet: string, quantity: number): string {
  return quantity > 1 ? `${sellerNet} for all ${quantity} tickets` : sellerNet;
}

export function proceedsKicker(quantity: number): string {
  return quantity > 1 ? `You get for ${quantity} tickets` : 'You get';
}

/**
 * WHAT THE PROCEEDS FIGURE IS (A's ruling, 2026-09-24). The sticky preview's net is computed from the
 * Buy Now price, falling back to the starting bid — but an auction settles on the WINNING bid, so for
 * an auction-only listing the figure is a FLOOR, not the amount. The old sub-line said only "after the
 * seller fee", which named the deduction and left the basis unstated, so an auction's preview read as
 * a promise of that exact net.
 *
 * The floor claim is sound: `listings` opens with `current_bid = starting_bid` (migration 072's insert
 * guard requires it, and the create screen sets it), and `canPlaceBid` accepts only `selected >=
 * minimum` where the minimum is the current bid plus the increment — so a winning bid can never be
 * below the starting bid.
 *
 * B owns the layout; this owns the claim.
 */
export function proceedsBasis(i: { buyNowEnabled: boolean; buyNowPriceSet: boolean }): string {
  return i.buyNowEnabled && i.buyNowPriceSet
    ? 'at the Buy Now price, after the seller fee'
    : 'the least you get, after the seller fee — a higher winning bid pays more';
}

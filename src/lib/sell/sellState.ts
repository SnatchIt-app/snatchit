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
  allInFromDollars,
  allInLabel,
  sellerNetFromDollars,
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
  /** What the seller nets per ticket after the seller fee, e.g. "$90". */
  sellerNet: string;
  /** Seller net as a number, for the sticky bar's "You get" line. */
  sellerNetValue: number;
  /** What a buyer pays all-in per ticket, e.g. "$110". */
  buyerAllIn: string;
  /** The all-in with its trailing word, e.g. "$110 total". */
  buyerAllInLabel: string;
}

/**
 * The seller- and buyer-facing amounts for a whole-dollar listing price. This does
 * NO arithmetic of its own: it names which money helper produces each line, so the
 * preview can never drift from what the seller is actually paid or the buyer
 * actually charged. An unusable amount returns `valid: false` and empty strings.
 */
export function priceSummary(dollars: number): PriceSummary {
  if (!Number.isFinite(dollars) || dollars < 1) {
    return { valid: false, sellerNet: '', sellerNetValue: 0, buyerAllIn: '', buyerAllInLabel: '' };
  }
  return {
    valid: true,
    sellerNet: sellerNetFromDollars(dollars),
    sellerNetValue: sellerNetDollars(dollars),
    buyerAllIn: allInFromDollars(dollars),
    buyerAllInLabel: allInLabel(dollars),
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

/** The seller-facing copy for each risk reason. Unchanged wording. */
export const RISK_COPY = {
  medium_risk_warning: "We've noticed some recent issues. Please double-check your listing details.",
  high_risk_warning:   'Your account is under review. Incorrect listings may result in restrictions.',
  critical_risk:       'You cannot create listings at this time. Contact support.',
  listing_blocked:     'You cannot create listings at this time. Contact support.',
} as const;

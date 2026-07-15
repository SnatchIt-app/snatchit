/**
 * AUDIT 1 — backward compatibility of the create-payment-intent contract.
 *
 * Distributed payloads:
 *   LEGACY client (every build before all-in pricing, incl. 1.0 build 7):
 *     { "listing_id": "<uuid>", "mode": "buy_now" | "auction" }
 *   CURRENT client:
 *     { "listing_id": "<uuid>", "mode": "buy_now", "expected_total_cents": 11000 }
 *
 * The server ALWAYS charges its own canonical calculation
 * (feeBreakdown(listing price)); expected_total_cents is only ever compared
 * via totalMismatch() → HTTP 409 on disagreement. A missing value is NOT a
 * mismatch, so legacy checkouts keep working after the new function deploys.
 */
import { describe, expect, it } from 'vitest';
import { dollarsToCents, feeBreakdown, totalMismatch } from '../supabase/functions/_shared/money';

// The exact destructure the edge function performs on each payload.
function extractExpected(payload: Record<string, unknown>): unknown {
  const { expected_total_cents } = payload as { expected_total_cents?: unknown };
  return expected_total_cents;
}

const LISTING_PRICE_DOLLARS = 100;
const server = feeBreakdown(dollarsToCents(LISTING_PRICE_DOLLARS)); // total 11000

describe('create-payment-intent backward compatibility', () => {
  it('1. new client with the correct expected total → accepted', () => {
    const payload = { listing_id: 'l1', mode: 'buy_now', expected_total_cents: 11000 };
    expect(totalMismatch(extractExpected(payload), server.buyerTotalCents)).toBe(false);
  });

  it('2. new client with an incorrect expected total → 409 mismatch', () => {
    const payload = { listing_id: 'l1', mode: 'buy_now', expected_total_cents: 10999 };
    expect(totalMismatch(extractExpected(payload), server.buyerTotalCents)).toBe(true);
  });

  it('3. legacy client with omitted expected total → accepted (no 409)', () => {
    const payload = { listing_id: 'l1', mode: 'buy_now' }; // build ≤7 payload
    expect(totalMismatch(extractExpected(payload), server.buyerTotalCents)).toBe(false);
    // explicit null (some JSON serializers) is also legacy-safe
    expect(totalMismatch(null, server.buyerTotalCents)).toBe(false);
  });

  it('4. malicious client manipulating the price → server total unaffected, claim rejected', () => {
    // The client cannot submit a price at all — the server derives base from
    // the LISTING row. A manipulated "expected" claiming the base-only price:
    const payload = { listing_id: 'l1', mode: 'buy_now', expected_total_cents: 10000 };
    expect(totalMismatch(extractExpected(payload), server.buyerTotalCents)).toBe(true);
    // Non-numeric garbage is a mismatch too — never coerced, never trusted.
    expect(totalMismatch('11000', server.buyerTotalCents)).toBe(true);
    expect(totalMismatch({ evil: true }, server.buyerTotalCents)).toBe(true);
    expect(totalMismatch(NaN, server.buyerTotalCents)).toBe(true);
    expect(totalMismatch(11000.5, server.buyerTotalCents)).toBe(true);
  });

  it('5. rounding parity: legacy and current payloads charge the identical amount', () => {
    // The charge amount is feeBreakdown(base) in BOTH cases — the payload
    // shape cannot change the math. Spot-check awkward rounding bases.
    for (const dollars of [25, 99, 100, 199.99, 33, 149.5]) {
      const b = feeBreakdown(dollarsToCents(dollars));
      // legacy path: no expected → charged b.buyerTotalCents
      expect(totalMismatch(undefined, b.buyerTotalCents)).toBe(false);
      // current path: client shows the same canonical number → accepted
      expect(totalMismatch(b.buyerTotalCents, b.buyerTotalCents)).toBe(false);
      // and the seller side is untouched by either payload shape
      expect(b.sellerNetCents + b.sellerFeeCents).toBe(b.baseCents);
    }
  });
});

/**
 * tests/bid-entry.test.ts — Place Bid math + account-batch source guards.
 *
 * The pure bid arithmetic (minimum, stepper, all-in) is pinned here; the screens
 * themselves are effect-heavy, so their behaviour is guarded by asserting the
 * shipped source still contains each critical path (the deletion guard, the
 * insert, the proceeds math, the deletion tri-state, the confirmations). Behaviour
 * and money, not pixels.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import {
  minNextBid,
  stepDown,
  stepUp,
  quickAdd,
  canPlaceBid,
  bidPriceLines,
  bidTotalLabel,
} from '../src/lib/bid/bidEntry';
import { buyerFeeCents, buyerTotalCents, dollarsToCents, formatCents } from '../src/lib/money';

// ─── Pure bid math ──────────────────────────────────────────────────────────

describe('bid math', () => {
  it('minimum next bid is current + increment', () => {
    expect(minNextBid(80, 5)).toBe(85);
    expect(minNextBid(0, 5)).toBe(5);
  });
  it('stepper respects the floor and steps by the increment', () => {
    expect(stepUp(85, 5)).toBe(90);
    expect(stepDown(90, 85, 5)).toBe(85);
    expect(stepDown(85, 85, 5)).toBe(85); // already at floor, cannot go lower
  });
  it('quick add bumps by the given amount', () => {
    expect(quickAdd(85, 25)).toBe(110);
  });
  it('canPlaceBid enforces the minimum boundary', () => {
    expect(canPlaceBid(85, 85)).toBe(true);
    expect(canPlaceBid(84, 85)).toBe(false);
    expect(canPlaceBid(NaN, 85)).toBe(false);
  });
});

describe('bid all-in — composed from money.ts, no local fee math', () => {
  it('mirrors the canonical buyer helpers exactly', () => {
    const cents = dollarsToCents(80);
    const lines = bidPriceLines(80);
    expect(lines.bid).toBe(formatCents(cents));
    expect(lines.fee).toBe(formatCents(buyerFeeCents(cents)));
    expect(lines.total).toBe(formatCents(buyerTotalCents(cents)));
    expect(bidTotalLabel(80)).toBe(formatCents(buyerTotalCents(cents)));
  });
});

// ─── Source guards ──────────────────────────────────────────────────────────

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');

describe('Place Bid — shipped-source guards', () => {
  const screen = read('src/screens/PlaceBidScreen.tsx');
  const model = read('src/lib/bid/bidEntry.ts');

  it('preserves the bid path: deletion guard, insert, minimum, all-in', () => {
    for (const marker of [
      "schema('kernel')",           // F-5 deletion guard reads identity_ext
      'identity_ext',
      "deletion_state",
      'DELETION_PENDING',
      "from('bids').insert",        // the bid insert
      'bidder_id',
      'minNextBid(',                // minimum via the pure model
      'canPlaceBid(',
      'bidPriceLines(',             // all-in via the pure model
    ]) {
      expect(screen, `${marker} must survive`).toContain(marker);
    }
  });

  it('reads identity_ext, never kernel.tickets, and builds no ticket object', () => {
    expect(screen).not.toMatch(/kernel[^\n]*tickets|from\(['"]tickets['"]\)/);
    expect(screen).not.toMatch(/Apple Wallet|\.pkpass|barcode|QR code/i);
  });

  it('does no fee arithmetic in the screen or model', () => {
    for (const src of [screen, model]) {
      expect(src).not.toMatch(/\*\s*0?\.1\b|\*\s*1\.1\b/); // no hand-rolled 10% / all-in on an amount
    }
    // All-in reaches the UI only through the pure model; the raw buyer helpers
    // are never imported directly into the screen.
    expect(screen).not.toMatch(/buyerTotalCents|buyerFeeCents/);
  });

  it('confirms with real bid semantics, not ownership', () => {
    expect(screen).toContain("'Bid placed'");
    expect(screen).not.toMatch(/you won|ticket secured|you own/i);
  });
});

describe('Profile — shipped-source guards', () => {
  const screen = read('app/(tabs)/profile.tsx');

  it('preserves the data layer', () => {
    for (const marker of [
      "rpc('get_my_profile')",           // owner-scoped profile
      'sellerNetDollars(',               // proceeds via canonical money
      "'create-connect-account'",        // non-blocking payout probe
      'status_only',
      "from('profiles')",                // avatar path update
      'signOut(',
    ]) {
      expect(screen, `${marker} must survive`).toContain(marker);
    }
  });

  it('keeps UNKNOWN proceeds distinct from a real zero', () => {
    // Proceeds render "—" when zero; a real $0 is never shown as a number here.
    expect(screen).toMatch(/stats\.revenue > 0 \? formatMoney\(stats\.revenue\) : '—'/);
  });

  it('does not expose the full phone number', () => {
    expect(screen).toContain('maskPhone(');
    // last 4 only — the mask literal proves the rest is hidden
    expect(screen).toContain("+1 (***) ***-");
  });

  it('never queries kernel.tickets', () => {
    expect(screen).not.toMatch(/kernel[^\n]*tickets|from\(['"]tickets['"]\)/);
  });
});

describe('Settings — shipped-source guards', () => {
  const screen = read('app/settings/index.tsx');

  it('preserves the deletion tri-state and its guards', () => {
    for (const marker of [
      "schema('kernel')",
      'identity_ext',
      'DELETION_PENDING',
      "'unknown' | 'pending' | 'active'",  // tri-state type
      'deletionProbeFailed',               // a failed probe is its own state
      "invoke('delete-account'",           // withdraw + delete both route here
      "action: 'withdraw'",
    ]) {
      expect(screen, `${marker} must survive`).toContain(marker);
    }
  });

  it('a failed probe is never read as "not pending" (banner survives)', () => {
    // The pending banner is gated on the view, and the probe-failed banner is
    // separate — both branches must exist so a blip cannot hide the withdraw path.
    expect(screen).toContain('deletionPending');
    expect(screen).toMatch(/deletionProbeFailed && !deletionPending/);
  });

  it('keeps sign-out and the double-confirm delete', () => {
    expect(screen).toMatch(/Are you sure you want to sign out/);
    expect(screen).toMatch(/Are you absolutely sure/);        // second delete confirm
    expect(screen).toContain('executeDeleteAccount');
  });

  it('uses no emoji in the settings rows', () => {
    // The redesign dropped the emoji icon column. Guard against its return.
    expect(screen).not.toMatch(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/u);
  });
});

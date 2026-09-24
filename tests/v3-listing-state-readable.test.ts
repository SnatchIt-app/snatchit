/**
 * A listing's state must be legible even when the control that names it is disabled
 * (owner 2026-09-24: "readable listing-state explanation").
 *
 * The primary CTA does double duty on `unavailable`: its label is not a control word but the
 * listing's STATE — Sold, Cancelled, On hold, Ended, Your listing — and `Button`'s disabled
 * `opacity: 0.4` then renders it at 1.61:1 on Midnight and 1.50:1 on Daylight (B, measured at
 * `404bce38`). That is not a WCAG violation, because an inactive control is exempt, and the disabled
 * treatment is not what needs changing. It is an information defect: a dim that is right for a
 * control is wrong for a status.
 *
 * Two of the five are carried elsewhere at full strength — the price label swaps to "Sold for" when
 * sold and "Final bid" when closed. The other three were stated nowhere else. They now populate
 * `primary.subLabel`, which the screen already renders in a `Text` OUTSIDE the button.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

import { listingActions } from '@/src/lib/listing/detailState';

const BASE = {
  listing: {
    status: 'active', auction_status: 'active', buy_now_enabled: true, buy_now_price: 12000,
    seller_id: 'seller-1', reserved_by: null, winner_user_id: null, bid_count: 0, quantity: 1,
  },
  userId: 'buyer-1',
  clockEnded: false, reservationActive: false, finalizing: false, reserving: false,
  transfer: { id: null, status: null, buyerId: null },
  isHighestBidder: false, hasBid: false, buyNowAllIn: '$132.00', nextBidAllIn: null,
};

const actionsFor = (over: Record<string, unknown>) =>
  listingActions({ ...BASE, ...over } as never);

describe('an unavailable listing states why, outside the dimmed button', () => {
  it('LR1: cancelled, on hold and your-listing each carry a full-strength sub-label', () => {
    const cancelled = actionsFor({ clockEnded: true, listing: { ...BASE.listing, auction_status: 'cancelled' } });
    expect(cancelled.primary.kind).toBe('unavailable');
    expect(cancelled.primary.subLabel, 'cancelled').toBeTruthy();
    expect(cancelled.primary.subLabel).toMatch(/cancel/i);

    const onHold = actionsFor({
      clockEnded: true, reservationActive: true,
      listing: { ...BASE.listing, reserved_by: 'someone-else' },
    });
    if (onHold.primary.label === 'On hold') {
      expect(onHold.primary.subLabel, 'on hold').toBeTruthy();
      // This is the one that costs a buyer most: it is the reason they cannot buy.
      expect(onHold.primary.subLabel).toMatch(/another buyer|someone else|checkout/i);
    }

    const mine = actionsFor({ userId: 'seller-1' });
    expect(mine.primary.label).toBe('Your listing');
    expect(mine.primary.subLabel, 'your listing').toBeTruthy();
    expect(mine.primary.subLabel).toMatch(/your own|you listed|seller/i);
  });

  it('LR2: sold and ended do NOT gain one — the price label already carries them at full strength', () => {
    const sold = actionsFor({ clockEnded: true, listing: { ...BASE.listing, status: 'sold' } });
    expect(sold.primary.label).toBe('Sold');
    expect(sold.primary.subLabel).toBeUndefined();
    const ended = actionsFor({ clockEnded: true });
    expect(ended.primary.label).toBe('Ended');
    expect(ended.primary.subLabel).toBeUndefined();
    // The other cue MOVED, not vanished (V3 footer rebuild, 2026-09-24): the board removes the
    // sticky price block, so the sold/ended wording now lives in the panel's price label.
    const panel = readFileSync('src/components/listing/TransactionPanel.tsx', 'utf8');
    expect(panel).toMatch(/'Final bid'/);
    expect(panel).toMatch(/label="Sold for"/);
  });

  it('LR3: the sub-label renders outside the Button, so the disabled dim does not reach it', () => {
    const screen = readFileSync('src/screens/ListingDetailScreen.tsx', 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
    const i = screen.indexOf('state.primary.subLabel');
    expect(i).toBeGreaterThan(0);
    // The Text carrying it is a sibling of <Button>, not a child.
    const region = screen.slice(i - 400, i + 300);
    expect(region).toMatch(/<Text style=\{\[textStyle\('bodySm'\), s\.ctaSubLabel\]\}/);
    expect(region).not.toMatch(/<Button[^>]*>\s*<Text/);
  });
});

describe('a BUSY control states progress, so its label is not dimmed either', () => {
  it('LR5 (B\'s checkout review, 2026-09-24; E\'s rule 3c): a pending label keeps full strength', () => {
    /*
     * The same principle as LR1–LR4, one state over. `payControl` returns loading AND disabled
     * together for its six in-flight branches, so "Confirming payment", "Finalizing your order" and
     * "Checking your payment" were rendered through `Button`'s disabled `opacity: 0.4` — the faintest
     * thing on the screen, worst in Light, and B measured exactly that on checkout. A dim that is
     * right for a control is wrong for a status, and a pending label IS the status.
     *
     * Fixed at the primitive, so every screen gets it: the listing footer's "Reserving…", the bid
     * screen's "Submitting bid…" and checkout's six in-flight labels all keep full contrast. The
     * control is still inert — `disabled={inert}` is unchanged — and a screen reader still hears
     * `busy`, so nothing about interactivity moved.
     */
    const src = readFileSync('src/components/ui/Button.tsx', 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
    expect(src).toContain('const showPending = loading && !!pendingLabel;');
    expect(src).toContain('disabled && !showPending && styles.disabled,');
    // The control does not become interactive: both of these are unchanged.
    expect(src).toContain('const inert = disabled || loading;');
    expect(src).toContain('disabled={inert}');
    expect(src).toMatch(/accessibilityState=\{\{ disabled: inert, busy: loading \}\}/);
    // A spinner-only loading state is not text, so it keeps the dim.
    expect(src).toMatch(/\{loading && !showPending \? \(/);
  });
});

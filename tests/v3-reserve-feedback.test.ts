/**
 * tests/v3-reserve-feedback.test.ts — the reserve button says it is working, wherever it sits.
 *
 * THE DEFECT (B, at 3c6f15a4; owner-confirmed 2026-09-25). The owner's Option B ruling made the bid
 * the primary action and Buy Now the secondary. The screen computed its busy state for the PRIMARY
 * only — `state.primary.kind === 'buy_now' || … === 'continue_reservation'` — and passed
 * `pendingLabel` and `loading` to the primary BarAction alone. That was correct for exactly as long
 * as Buy Now was the primary. After the flip, Buy Now still started a reservation and showed
 * nothing at all while the network call was in flight.
 *
 * TWO CLAIMS, TESTED SEPARATELY, because conflating them is how the fix would be over-sold:
 *
 *   FEEDBACK was broken. `reserveBusy` now derives the pending state from the resolved ACTIONS, so
 *   whichever button carries the reserve call is the button that shows "Reserving…".
 *
 *   REPEAT ACTIVATION was NOT broken, and this suite proves that rather than asserting it. Both
 *   buttons dispatch through one `useSingleFlight` lock held in a ref. A ref-based lock is the only
 *   kind that holds a same-tick double press: a React `reserving` state disables a button only after
 *   the re-render, and two taps can land before it. So the lock is exercised here directly, with a
 *   deliberately un-settled promise, which is the only way to observe the window the lock exists to
 *   close.
 *
 * NO RESERVATION IS MADE. Nothing here touches Supabase, an RPC, a payment intent or the network:
 * the lock is driven with local promises, and the presentation rule is a pure function of resolved
 * actions. What that leaves unproven is stated at the bottom of the file.
 */

import { describe, expect, it } from 'vitest';

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { createSingleFlight } from '../src/lib/async/singleFlight';
import {
  isReserveAction,
  listingActions,
  reserveBusy,
  transactionMode,
  type DetailStateInput,
} from '../src/lib/listing/detailState';

const root = resolve(__dirname, '..');
const code = (rel: string) =>
  readFileSync(resolve(root, rel), 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/.*$/gm, '$1');

const ME = 'viewer-1';

/** A listing that offers BOTH actions, which is the state the owner's ruling re-ordered. */
function bothAvailable(over: Partial<DetailStateInput> = {}): DetailStateInput {
  return {
    listing: {
      id: 'l-1',
      seller_id: 'seller-1',
      status: 'active',
      auction_status: 'active',
      buy_now_enabled: true,
      buy_now_price: 60,
      quantity: 2,
      starting_bid: 40,
      current_bid: 90,
      winner_user_id: null,
      reserved_by: null,
    },
    userId: ME,
    transfer: { buyerId: null, sellerId: null, status: null },
    reserving: false,
    finalizing: false,
    reservationActive: false,
    clockEnded: false,
    nextBidAllIn: '$104.50',
    buyNowAllIn: '$66',
    ...over,
  } as DetailStateInput;
}

describe('the reserve action is the busy one — not the first one', () => {
  it('RF1: with both actions offered, the SECOND button is the one that reserves', () => {
    const actions = listingActions(bothAvailable());
    expect(transactionMode(bothAvailable())).toBe('auction_and_buy_now');
    // The owner's Option B ordering. Asserted here because everything below depends on it.
    expect(actions.primary.kind).toBe('place_bid');
    expect(actions.secondary?.kind).toBe('buy_now');
    expect(isReserveAction(actions.secondary)).toBe(true);
    expect(isReserveAction(actions.primary)).toBe(false);
  });

  it('RF2: while reserving, the busy state lands on the SECOND button and not the first', () => {
    const actions = listingActions(bothAvailable({ reserving: true }));
    const busy = reserveBusy(actions, true);
    expect(busy.secondary).toBe(true);
    // The regression, as an assertion: the bid must NOT claim to be reserving. A screen that marked
    // the primary busy would show "Reserving…" on a control that only opens bid entry.
    expect(busy.primary).toBe(false);
  });

  it('RF3: when the reserve action IS the primary, the busy state moves with it', () => {
    // A buyer holding a reservation gets `continue_reservation` as the only action, so the same
    // predicate has to mark the primary. This is the control for RF2: if `reserveBusy` simply
    // hard-coded "secondary", RF2 would pass and this would fail.
    const held = bothAvailable({
      listing: { ...bothAvailable().listing, status: 'reserved', reserved_by: ME },
      reservationActive: true,
      reserving: true,
    });
    const actions = listingActions(held);
    expect(actions.primary.kind).toBe('continue_reservation');
    expect(actions.secondary).toBeNull();
    const busy = reserveBusy(actions, true);
    expect(busy.primary).toBe(true);
    expect(busy.secondary).toBe(false);
  });

  it('RF4: nothing is busy when no reservation is in flight', () => {
    const actions = listingActions(bothAvailable());
    expect(reserveBusy(actions, false)).toEqual({ primary: false, secondary: false });
  });
});

describe('repeat activation, and recovery — driven through the real lock', () => {
  it('RF5: a second press while the first is in flight does NOT start a second reservation', async () => {
    const flight = createSingleFlight();
    let starts = 0;
    let release!: () => void;
    const pending = new Promise<void>((r) => { release = r; });
    const reserve = () => { starts += 1; return pending; };

    // Two presses in the same tick — the window a React `reserving` state cannot close, because no
    // re-render has happened between them.
    const first = flight.run(reserve);
    const second = flight.run(reserve);

    expect(await second).toBe(false);          // the second press was dropped by the lock
    expect(starts).toBe(1);                    // and the reserve call ran exactly once
    expect(flight.inFlight).toBe(true);

    release();
    expect(await first).toBe(true);
    expect(flight.inFlight).toBe(false);
  });

  it('RF6: after a FAILED reservation the button works again — the lock is released', async () => {
    const flight = createSingleFlight();
    let starts = 0;
    const failing = () => { starts += 1; return Promise.reject(new Error('network')); };

    await expect(flight.run(failing)).rejects.toThrow('network');
    // The lock must not survive the failure, or a buyer whose first attempt failed could never
    // retry without leaving the screen.
    expect(flight.inFlight).toBe(false);

    let secondRan = false;
    await flight.run(async () => { secondRan = true; });
    expect(secondRan).toBe(true);
    expect(starts).toBe(1);
  });
});

describe('the screen is wired to both of the above', () => {
  const screen = code('src/screens/ListingDetailScreen.tsx');

  it('RF7: BOTH bar actions carry the pending label and a loading flag from the one predicate', () => {
    // One predicate, consumed once.
    expect(screen).toContain('const busy = reserveBusy(state, reserving);');
    expect(screen).toContain('loading={busy.primary}');
    expect(screen).toContain('loading={busy.secondary}');
    // Two pending labels, one per button. The secondary had none, which is the whole finding.
    expect(screen.match(/pendingLabel="Reserving…"/g) ?? []).toHaveLength(2);
    // And the screen no longer carries its own copy of the rule.
    expect(screen).not.toMatch(/primaryBusy\s*=/);
    expect(screen).not.toMatch(/state\.primary\.kind === 'buy_now'/);
  });

  it('RF8: both buttons dispatch through the same handler, so one lock covers both', () => {
    expect(screen).toContain('onPress={() => runAction(state.primary.kind)}');
    expect(screen).toContain('onPress={() => runAction(state.secondary!.kind)}');
    // runAction routes both reserve kinds into the locked handler.
    expect(screen).toMatch(/case 'buy_now':\s*case 'continue_reservation':\s*handleBuyNow\(\);/);
    expect(screen).toContain('buyFlight.run(reserveAndCheckout)');
    // The lock is the ref-based one, not a state guard.
    expect(screen).toContain('useSingleFlight()');
  });

  it('RF9: presentation order did not change eligibility — disabled still comes from the resolver', () => {
    // The owner's constraint: "Keep action eligibility separate from presentation order and fill."
    expect(screen).toContain('disabled={state.secondary.disabled}');
    expect(screen).toMatch(/disabled=\{state\.primary\.disabled \|\| state\.primary\.kind === 'unavailable'\}/);
    // A busy control is not the same thing as an ineligible one, so `loading` never feeds `disabled`.
    expect(screen).not.toMatch(/disabled=\{[^}]*busy\./);
  });
});

/*
 * WHAT THIS DOES NOT PROVE, so a green run is not mistaken for more than it is:
 *  - that the pending label is legible, or fits, at native Dynamic Type sizes;
 *  - that the stacked footer clears the safe area on a device;
 *  - anything about the server's own duplicate-reservation guards (A-06), which are not the client's
 *    half of this and are not exercised here;
 *  - that a real `reserve_buy_now` call behaves as the lock assumes — no reservation was made.
 */

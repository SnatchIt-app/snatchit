/**
 * The reservation (listing) lookup in re-validation fails CLOSED (owner, 2026-09-19, direct; D's R2).
 *
 * Owner: "A failed read must not claim the reservation is lost or that nothing was charged. Keep Pay unavailable while
 * reservation status is unknown. Retrying should only recheck status; it must not submit payment. Cover both failure
 * and successful recovery, including the legitimate unpaid-buyer path."
 *
 * WHAT WAS WRONG. Re-validation's listing read kept `data` and dropped `error`, so a failed read became null → 'lost'
 * → setHoldLost → "This listing is no longer held for you. Nothing was charged…" — claims no read established. A
 * thrown read rejected decideRevalidation, which no caller caught (on the margin path Pay stayed armed). Setup's own
 * listing read already mapped an error to `reservation_unverifiable`; this gives re-validation the same outcome.
 *
 * A's invariants: J1 a listing-read error (returned or thrown) never yields 'lost'/setHoldLost or 'held', and never
 * escapes decideRevalidation; J2 it yields an unverifiable outcome — Pay withheld, copy says only that the reservation
 * couldn't be checked, the one action re-runs the check; J3 a successful read is unchanged (no row, someone else's or
 * an expired hold → 'lost'; a live hold → 'held'); J5 the read is an importable function for A's E2E.
 *
 * UNIFIED (owner, 2026-09-19, direct; D's recommendation): "unify both unknown-reservation states as 'We couldn't
 * check your reservation.' with 'Check again.' Neither state may offer Pay until a successful check establishes
 * eligibility." Setup's and re-validation's unverifiable paths both set statusUnknown, so payControl's rank — not one
 * line in the screen — keeps Pay away; "Try again" stays for genuine setup failures.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { notHeldCopy, RESERVATION_UNVERIFIABLE_COPY } from '../src/lib/checkout/holdState';
import { payControl } from '../src/lib/checkout/payControl';
import { readListingHold } from '../src/lib/checkout/settledRead';
import {
  _resetSetupInFlight,
  decideCheckoutSetup,
  decideRevalidation,
  type SetupDeps,
} from '../src/lib/checkout/setupDecision';

beforeEach(() => _resetSetupInFlight());

const NOW = new Date('2026-09-19T18:00:00Z');
const LIVE = { status: 'reserved', reserved_by: 'buyer', reserved_until: '2026-09-19T18:09:00Z' };
const PG_5XX = { code: 'PGRST000', message: 'Could not connect to the database' };

function fakeClient(result: { data?: unknown; error?: unknown } | { throws: unknown }) {
  const calls: [string, ...unknown[]][] = [];
  const q = {
    select: (c: string) => { calls.push(['select', c]); return q; },
    eq: (c: string, v: unknown) => { calls.push(['eq', c, v]); return q; },
    maybeSingle: () => {
      calls.push(['maybeSingle']);
      return 'throws' in result ? Promise.reject(result.throws) : Promise.resolve({ data: result.data ?? null, error: result.error ?? null });
    },
  };
  return { client: { from: (t: string) => { calls.push(['from', t]); return q; } }, calls };
}

// ── The importable read (J5) ───────────────────────────────────────────────────────────────────────────────────
describe('readListingHold returns the listing (or no row) OR an error', () => {
  it('Q1: success returns the listing, from exactly the hold query', async () => {
    const { client, calls } = fakeClient({ data: LIVE });
    expect(await readListingHold(client, 'L')).toEqual({ listing: LIVE });
    expect(calls).toEqual([['from', 'listings'], ['select', 'status, reserved_by, reserved_until'], ['eq', 'id', 'L'], ['maybeSingle']]);
  });

  it('Q1b: a successful read with no row is { listing: null } — not an error (J3)', async () => {
    expect(await readListingHold(fakeClient({ data: null }).client, 'L')).toEqual({ listing: null });
  });

  it('Q2: a returned PostgREST error is an error', async () => {
    expect(await readListingHold(fakeClient({ error: PG_5XX }).client, 'L')).toEqual({ error: { code: 'PGRST000', message: PG_5XX.message } });
  });

  it('Q3: a thrown request is an error, not thrown and not "no row"', async () => {
    expect(await readListingHold(fakeClient({ throws: new TypeError('Network request failed') }).client, 'L'))
      .toEqual({ error: { code: null, message: 'Network request failed' } });
  });

  it.each([['a string', 'ok'], ['a list', [LIVE]]])('Q3b (%s): a reply that is neither a row nor null is an error', async (_n, data) => {
    expect(await readListingHold(fakeClient({ data }).client, 'L')).toEqual({ error: { code: null, message: 'unexpected response: not a row' } });
  });
});

// ── Re-validation (J1/J2/J3) ───────────────────────────────────────────────────────────────────────────────────
function deps(readListing: () => Promise<unknown>) {
  return {
    readSettled: vi.fn(async () => ({ rows: [] })),   // the buyer has NOT paid: the case where the hold decides
    readListing: vi.fn(readListing),
  } as unknown as Parameters<typeof decideRevalidation>[1];
}
const revalidate = (d: Parameters<typeof decideRevalidation>[1]) => decideRevalidation({ buyerId: 'buyer', isBuyNow: true, now: NOW }, d);

describe('re-validation: a failed listing read is unverifiable — never lost, never held', () => {
  it('Q4 (returned error): reservation_unverifiable with the code', async () => {
    expect(await revalidate(deps(async () => ({ error: { code: 'PGRST000', message: PG_5XX.message } }))))
      .toEqual({ kind: 'reservation_unverifiable', detail: `PGRST000: ${PG_5XX.message}` });
  });

  it('Q5 (thrown): reservation_unverifiable, and decideRevalidation still resolves', async () => {
    await expect(revalidate(deps(async () => { throw new TypeError('Network request failed'); })))
      .resolves.toEqual({ kind: 'reservation_unverifiable', detail: 'no-code: Network request failed' });
  });

  it('Q6: a successful read is unchanged — no row, someone else\'s, expired → lost; live → held (J3)', async () => {
    expect(await revalidate(deps(async () => ({ listing: null })))).toEqual({ kind: 'lost' });
    expect(await revalidate(deps(async () => ({ listing: { ...LIVE, reserved_by: 'someone-else' } })))).toEqual({ kind: 'lost' });
    expect(await revalidate(deps(async () => ({ listing: { ...LIVE, reserved_until: '2026-09-19T17:59:00Z' } })))).toEqual({ kind: 'lost' });
    expect(await revalidate(deps(async () => ({ listing: LIVE })))).toEqual({ kind: 'held', reservedUntilMs: Date.parse(LIVE.reserved_until) });
  });
});

describe('recovery: a re-check that succeeds proceeds; the legitimate unpaid buyer can still pay', () => {
  it('Q7: unverifiable first, then held on a successful re-check', async () => {
    let fail = true;
    const d = deps(async () => (fail ? { error: { code: null, message: 'offline' } } : { listing: LIVE }));
    expect((await revalidate(d)).kind).toBe('reservation_unverifiable');
    fail = false;
    expect(await revalidate(d)).toEqual({ kind: 'held', reservedUntilMs: Date.parse(LIVE.reserved_until) });
  });

  it('Q8: the retry re-runs setup — an unpaid buyer with a live hold gets exactly one intent, only after good reads', async () => {
    // Retry = setupPaymentRef (W5 in the settled-read suite). Setup's listing read maps a failure to
    // reservation_unverifiable (unchanged); on a good re-read the legitimate unpaid path is ready.
    let listingFails = true;
    const d = {
      fetchSettledPayment: vi.fn(async () => []),
      fetchListing: vi.fn(async () => (listingFails ? null : LIVE)),
      createIntent: vi.fn(async () => 'pi_new'),
      now: () => NOW,
    } as unknown as SetupDeps<string> & { createIntent: ReturnType<typeof vi.fn> };
    expect((await decideCheckoutSetup({ listingId: 'L', buyerId: 'buyer', mode: 'buy_now' }, d)).kind).toBe('reservation_unverifiable');
    expect(d.createIntent).not.toHaveBeenCalled();
    listingFails = false;
    expect(await decideCheckoutSetup({ listingId: 'L', buyerId: 'buyer', mode: 'buy_now' }, d)).toEqual({ kind: 'ready', intent: 'pi_new' });
    expect(d.createIntent).toHaveBeenCalledTimes(1);
  });

  it('Q9: while the reservation is unknown the control is "Check again", never Pay — even with a stale ready flag or inside the margin', () => {
    // D's rank pin: statusUnknown outranks paymentReady, so no screen path that leaves paymentReady true can show Pay.
    const unknown = {
      authLoading: false, paymentLoading: false, confirming: false, paymentReady: false, paymentError: true, statusUnknown: true, formattedTotal: '$110',
    };
    const want = { label: 'Check again', loading: false, disabled: false, action: 'retry' };
    expect(payControl(unknown)).toEqual(want);
    expect(payControl({ ...unknown, paymentReady: true })).toEqual(want);
    expect(payControl({ ...unknown, paymentReady: true, reservationMsLeft: 1_000 })).toEqual(want);
    // Witness: without the flag the same stale ready flag IS Pay, and a genuine setup failure keeps "Try again".
    expect(payControl({ ...unknown, statusUnknown: false, paymentReady: true }).action).toBe('pay');
    expect(payControl({ ...unknown, statusUnknown: false }).label).toBe('Try again');
  });
});

// ── What the buyer sees ────────────────────────────────────────────────────────────────────────────────────────
const HOLD_OR_CHARGE_CLAIM = /no longer held|lost|released|ran out|expired|nothing was charged|charged|sold/i;
const INVITES_PAYMENT = /\bpa(?:y|id)/i;

describe('the copy claims nothing about the hold or a charge', () => {
  it('Q10 (witness): the patterns match what they must catch — the not-held copy, and the Pay label', () => {
    for (const r of ['released_by_us', 'ran_out', 'unknown'] as const) {
      const c = notHeldCopy(r);
      expect(`${c.title} ${c.body}`).toMatch(HOLD_OR_CHARGE_CLAIM);
    }
    const ready = { authLoading: false, paymentLoading: false, confirming: false, paymentReady: true, paymentError: false, formattedTotal: '$110' };
    expect(payControl(ready).label).toMatch(INVITES_PAYMENT);
  });

  it('Q11: the reservation-unknown copy is the owner\'s sentence; it claims nothing about the hold or a charge and does not invite payment', () => {
    expect(RESERVATION_UNVERIFIABLE_COPY).toBe("We couldn't check your reservation.");
    expect(RESERVATION_UNVERIFIABLE_COPY).not.toMatch(HOLD_OR_CHARGE_CLAIM);
    expect(RESERVATION_UNVERIFIABLE_COPY).not.toMatch(INVITES_PAYMENT);
  });
});

// ── The screen's wiring (no CheckoutNative render harness) ─────────────────────────────────────────────────────
const src = () => readFileSync(resolve(__dirname, '../src/screens/checkout/CheckoutNative.tsx'), 'utf8');
const between = (s: string, from: string, to: string) => {
  const a = s.indexOf(from), b = s.indexOf(to, a + 1);
  expect(a, from).toBeGreaterThan(-1);
  expect(b, to).toBeGreaterThan(a);
  return s.slice(a, b);
};

describe('the screen applies it fail-closed', () => {
  it('Q12: re-validation reads the listing only through readListingHold', () => {
    const body = between(src(), 'async function revalidateAgainstServer()', 'async function recheckPayment()');
    expect(body).toContain('readListing: () => readListingHold(supabase, listingId)');
    expect(body).not.toContain(".from('listings')");
  });

  it('Q13: an unverifiable reservation is the unknown state — Pay withheld, says only that, reports, no lost hold', () => {
    const block = between(src(), "if (outcome.kind === 'reservation_unverifiable') {", '}\n');
    expect(block).toContain("reportCheckoutFailure('reservation-check', outcome.detail);");
    expect(block).toContain('setPaymentReady(false);');
    expect(block).toContain('setStatusUnknown(true);');
    expect(block).toContain('setPaymentError(RESERVATION_UNVERIFIABLE_COPY);');
    expect(block).toContain("return 'unknown';");
    expect(block).not.toMatch(/setHoldLost|setPaymentReady\(true\)|payHandler/);
  });

  it('Q14: setup\'s unverifiable path is the same unknown state — same sentence, no hold claim, nothing created', () => {
    const block = between(src(), "if (decision.kind === 'reservation_unverifiable') {", "if (decision.kind === 'not_held')");
    expect(block).toContain('setStatusUnknown(true);');
    expect(block).toContain('setPaymentError(RESERVATION_UNVERIFIABLE_COPY);');
    expect(block).toContain('return;');
    expect(block).not.toMatch(/setHoldLost|setPaymentReady\(true\)|createPaymentIntent|initPaymentSheet/);
  });
});

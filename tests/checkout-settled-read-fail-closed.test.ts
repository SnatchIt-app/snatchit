/**
 * F-CHK-READERR — the settled-payment lookup fails CLOSED (owner, 2026-09-18, direct).
 *
 * Owner: "If the payment lookup fails, show that payment status couldn't be checked and withhold payment
 * creation/submission until a successful read establishes the appropriate state. Retrying the lookup must not itself
 * initiate payment."
 *
 * WHAT WAS WRONG. Both reads of the buyer's own settled payments — at setup and in the server re-validation — kept
 * `data` and discarded `error`. A failed read (the pre-142 database's 42703, a 5xx, a dropped connection) looked
 * exactly like "no payment": a paid buy_now buyer still holding the listing went on to create an intent; a paid buyer
 * whose listing had sold was told the hold was lost and "Nothing was charged"; re-validation could re-arm Pay.
 *
 * A's payment-boundary invariants: I1 an error never reaches fetchListing/createIntent and never re-arms Pay; I2 it
 * never produces not_held/hold-lost copy, a refund state, already_settled or success; I3 the state says only that the
 * status couldn't be checked, and its one action re-runs the CHECK (a re-check that succeeds and finds nothing
 * settled proceeds exactly as today); I4 the error is reported with stage and code, no PII; I5 success is unchanged.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { payControl, type PayControlInput } from '../src/lib/checkout/payControl';
import { notHeldCopy, PAYMENT_STATUS_UNKNOWN_COPY } from '../src/lib/checkout/holdState';
import { readSettledPayments, SettledReadError } from '../src/lib/checkout/settledRead';
import {
  _resetSetupInFlight,
  decideCheckoutSetup,
  decideRevalidation,
  type SetupDeps,
} from '../src/lib/checkout/setupDecision';

beforeEach(() => _resetSetupInFlight());

const NOW = new Date('2026-09-18T18:00:00Z');
const LIVE_HOLD = { status: 'reserved', reserved_by: 'buyer', reserved_until: '2026-09-18T18:09:00Z' };
const PG_42703 = { code: '42703', message: 'column payments.amount_refunded_cents does not exist' };

/** A PostgREST-shaped fake: records the query, answers with `result` (or rejects with `throws`). */
function fakeClient(result: { data?: unknown; error?: unknown } | { throws: unknown }) {
  const calls: [string, ...unknown[]][] = [];
  const q = {
    select: (c: string) => { calls.push(['select', c]); return q; },
    eq: (c: string, v: unknown) => { calls.push(['eq', c, v]); return q; },
    in: (c: string, v: unknown) => { calls.push(['in', c, v]); return q; },
    limit: (n: number) => {
      calls.push(['limit', n]);
      return 'throws' in result ? Promise.reject(result.throws) : Promise.resolve({ data: result.data ?? null, error: result.error ?? null });
    },
  };
  return { client: { from: (t: string) => { calls.push(['from', t]); return q; } }, calls };
}

// ── The shared read ────────────────────────────────────────────────────────────────────────────────────────────
describe('readSettledPayments returns rows OR an error — never an error disguised as "no payment"', () => {
  it('R1: success returns the rows, from exactly the buyer-own settled-payment query', async () => {
    const { client, calls } = fakeClient({ data: [{ status: 'succeeded' }] });
    expect(await readSettledPayments(client, 'L', 'buyer')).toEqual({ rows: [{ status: 'succeeded' }] });
    expect(calls).toEqual([
      ['from', 'payments'],
      ['select', 'status, refunded_at, amount_refunded_cents, total'],
      ['eq', 'listing_id', 'L'],
      ['eq', 'buyer_id', 'buyer'],
      ['in', 'status', ['succeeded', 'refunded']],
      ['limit', 5],
    ]);
  });

  it('R1b: an empty LIST is a successful read with no rows', async () => {
    expect(await readSettledPayments(fakeClient({ data: [] }).client, 'L', 'b')).toEqual({ rows: [] });
  });

  it.each([['null', null], ['an object', { status: 'succeeded' }], ['a string', 'ok']])(
    'R1c (%s): a reply that is not a list establishes nothing — it is an error, never "no payment"',
    async (_name, data) => {
      // D's review (RQ1): only an array establishes "no settled payment"; anything else used to become rows [] and
      // reach createIntent.
      expect(await readSettledPayments(fakeClient({ data }).client, 'L', 'b'))
        .toEqual({ error: { code: null, message: 'unexpected response: not a list' } });
    },
  );

  it('R2: a PostgREST error (the pre-142 42703) is returned as an error with its code', async () => {
    expect(await readSettledPayments(fakeClient({ error: PG_42703 }).client, 'L', 'b'))
      .toEqual({ error: { code: '42703', message: PG_42703.message } });
  });

  it('R3: a request that throws (network) is returned as an error, not thrown and not "no rows"', async () => {
    expect(await readSettledPayments(fakeClient({ throws: new TypeError('Network request failed') }).client, 'L', 'b'))
      .toEqual({ error: { code: null, message: 'Network request failed' } });
  });
});

// ── Entry path 1: setup ────────────────────────────────────────────────────────────────────────────────────────
function setupDeps(fetchSettledPayment: () => Promise<unknown>) {
  return {
    fetchSettledPayment: vi.fn(fetchSettledPayment),
    fetchListing: vi.fn(async () => LIVE_HOLD),
    createIntent: vi.fn(async () => 'pi_new'),
    now: () => NOW,
  } as unknown as SetupDeps<string> & { fetchListing: ReturnType<typeof vi.fn>; createIntent: ReturnType<typeof vi.fn> };
}

const FAILURES: [string, unknown, string][] = [
  ['42703', new SettledReadError({ code: '42703', message: PG_42703.message }), `42703: ${PG_42703.message}`],
  ['network', new SettledReadError({ code: null, message: 'Network request failed' }), 'no-code: Network request failed'],
  ['unexpected throw', new Error('boom'), 'boom'],
];

describe('setup: a failed lookup stops before the hold and before any intent', () => {
  it.each((['buy_now', 'auction'] as const).flatMap((mode) => FAILURES.map(([name, err, detail]) => [mode, name, err, detail] as const)))(
    'R4 (%s, %s): payment_status_unknown; fetchListing and createIntent never called',
    async (mode, _name, err, detail) => {
      const d = setupDeps(async () => { throw err; });
      const r = await decideCheckoutSetup({ listingId: 'L', buyerId: 'buyer', mode }, d);

      expect(r).toEqual({ kind: 'payment_status_unknown', detail });
      expect(d.fetchListing).not.toHaveBeenCalled();
      expect(d.createIntent).not.toHaveBeenCalled();
    },
  );

  it('R5: a re-check that succeeds and finds nothing settled proceeds exactly as before (I3/I5)', async () => {
    let fail = true;
    const d = setupDeps(async () => { if (fail) throw new SettledReadError({ code: null, message: 'offline' }); return null; });
    expect((await decideCheckoutSetup({ listingId: 'L', buyerId: 'buyer', mode: 'buy_now' }, d)).kind).toBe('payment_status_unknown');
    fail = false;
    expect(await decideCheckoutSetup({ listingId: 'L', buyerId: 'buyer', mode: 'buy_now' }, d)).toEqual({ kind: 'ready', intent: 'pi_new' });
    expect(d.createIntent).toHaveBeenCalledTimes(1);   // only after the successful read
  });
});

// ── Entry path 2: the server re-validation ─────────────────────────────────────────────────────────────────────
function revalidateDeps(read: unknown) {
  return {
    readSettled: vi.fn(async () => read),
    fetchListing: vi.fn(async () => LIVE_HOLD),
  } as unknown as Parameters<typeof decideRevalidation>[1] & { fetchListing: ReturnType<typeof vi.fn> };
}

describe('re-validation: a failed lookup never re-arms Pay and never reports a lost hold', () => {
  it.each([true, false])('R6 (isBuyNow=%s): payment_status_unknown; the listing is never read', async (isBuyNow) => {
    const d = revalidateDeps({ error: { code: '42703', message: PG_42703.message } });
    const r = await decideRevalidation({ buyerId: 'buyer', isBuyNow, now: NOW }, d);

    expect(r).toEqual({ kind: 'payment_status_unknown', detail: `42703: ${PG_42703.message}` });
    expect(d.fetchListing).not.toHaveBeenCalled();
  });

  it('R7: a successful read behaves as before — settled, refund, held, lost, auction', async () => {
    const run = (read: unknown, isBuyNow = true, listing: unknown = LIVE_HOLD) => {
      const d = revalidateDeps(read);
      d.fetchListing.mockImplementation(async () => listing);
      return decideRevalidation({ buyerId: 'buyer', isBuyNow, now: NOW }, d).then((r) => ({ r, listingReads: d.fetchListing.mock.calls.length }));
    };
    expect(await run({ rows: [{ status: 'succeeded' }] })).toEqual({ r: { kind: 'already_settled' }, listingReads: 0 });
    expect(await run({ rows: [{ status: 'refunded', refunded_at: '2026-09-13T10:00:00Z', amount_refunded_cents: null, total: 11000 }] }))
      .toEqual({ r: { kind: 'refund_unconfirmed', refundedCents: null }, listingReads: 0 });
    expect(await run({ rows: [] })).toEqual({ r: { kind: 'held', reservedUntilMs: Date.parse(LIVE_HOLD.reserved_until) }, listingReads: 1 });
    expect(await run({ rows: [] }, true, { status: 'active', reserved_by: null, reserved_until: null })).toEqual({ r: { kind: 'lost' }, listingReads: 1 });
    expect(await run({ rows: [] }, false)).toEqual({ r: { kind: 'held', reservedUntilMs: null }, listingReads: 0 });
  });
});

// ── What the buyer sees ────────────────────────────────────────────────────────────────────────────────────────
// Claims a failed lookup cannot back: anything about a charge, a refund, the hold, the listing, or paying now.
const UNBACKED = /charg|refund|nothing|hold|expired|released|sold|pay now|try paying|complete|confirmed/i;

describe('the state says only that the status could not be checked', () => {
  it('W1 (witness): the pattern matches what the old swallowing actually showed', () => {
    // A paid buyer whose listing had sold saw the not-held copy.
    for (const r of ['released_by_us', 'ran_out', 'unknown'] as const) expect(notHeldCopy(r).body).toMatch(UNBACKED);
  });

  it('R8: the copy is exactly the check-failed sentence, and claims nothing else', () => {
    expect(PAYMENT_STATUS_UNKNOWN_COPY).toBe("We couldn't check the status of this payment.");
    expect(PAYMENT_STATUS_UNKNOWN_COPY).not.toMatch(UNBACKED);
  });
});

const BASE: PayControlInput = {
  authLoading: false, paymentLoading: false, confirming: false, paymentReady: false, paymentError: true, formattedTotal: '$110',
};

describe('the only action re-runs the check', () => {
  it('R9: "Check again" (retry) — never Pay, even with a stale ready flag or a lost hold', () => {
    const want = { label: 'Check again', loading: false, disabled: false, action: 'retry' };
    expect(payControl({ ...BASE, statusUnknown: true })).toEqual(want);
    expect(payControl({ ...BASE, statusUnknown: true, paymentReady: true })).toEqual(want);
    expect(payControl({ ...BASE, statusUnknown: true, holdLost: true })).toEqual(want);
  });

  it('R9b: an in-flight state still outranks it, and without it nothing changes (I5)', () => {
    expect(payControl({ ...BASE, statusUnknown: true, checking: true }).label).toBe('Checking your payment');
    expect(payControl({ ...BASE, statusUnknown: true, paymentLoading: true }).label).toBe('Setting up payment');
    expect(payControl({ ...BASE, paymentReady: true }).action).toBe('pay');
  });
});

// ── The screen's wiring (no CheckoutNative render harness; these pin how it applies the two decisions) ─────────
const src = () => readFileSync(resolve(__dirname, '../src/screens/checkout/CheckoutNative.tsx'), 'utf8');
const between = (s: string, from: string, to: string) => {
  const a = s.indexOf(from), b = s.indexOf(to, a + 1);
  expect(a, from).toBeGreaterThan(-1);
  expect(b, to).toBeGreaterThan(a);
  return s.slice(a, b);
};

describe('the screen applies both decisions fail-closed', () => {
  it('W2: both reads go through readSettledPayments; the screen queries payments nowhere itself', () => {
    const s = src();
    expect(s.split('readSettledPayments(supabase, ').length - 1).toBe(2);
    expect(s).not.toContain(".from('payments')");
  });

  it('W6: the setup dependency turns a failed read into a throw — never into "no rows"', () => {
    const dep = between(src(), 'fetchSettledPayment: async (lid, bid) => {', 'fetchListing: async (lid) => {');
    expect(dep).toContain('const read = await readSettledPayments(supabase, lid, bid);');
    expect(dep).toContain("if ('error' in read) throw new SettledReadError(read.error);");
    expect(dep).toContain('return read.rows;');
  });

  it('W3: setup reports the failure, marks the status unknown, shows the copy and stops', () => {
    const block = between(src(), "if (decision.kind === 'payment_status_unknown') {", "if (decision.kind === 'already_settled')");
    expect(block).toContain("reportCheckoutFailure('payment-status', decision.detail);");
    expect(block).toContain('setStatusUnknown(true);');
    expect(block).toContain('setPaymentError(PAYMENT_STATUS_UNKNOWN_COPY);');
    expect(block).toContain('return;');
    expect(block).not.toMatch(/setPaymentReady\(true\)|setHoldLost|createPaymentIntent|initPaymentSheet/);
  });

  it('W4: re-validation turns Pay off on an unknown status and never reports a lost hold for it', () => {
    const block = between(src(), "if (outcome.kind === 'payment_status_unknown') {", '}\n');
    expect(block).toContain("reportCheckoutFailure('payment-status', outcome.detail);");
    expect(block).toContain('setPaymentReady(false);');
    expect(block).toContain('setStatusUnknown(true);');
    expect(block).toContain("return 'unknown';");
    expect(block).not.toMatch(/setHoldLost|setPaymentReady\(true\)/);
  });

  it('W5: the retry re-runs setup (the check), never the pay handler; a new setup clears the unknown state', () => {
    const s = src();
    expect(s).toContain("pay.action === 'retry' ? () => setupPaymentRef.current?.()");
    const setupStart = between(s, 'async function setupPayment() {', 'const decision = await decideCheckoutSetup(');
    expect(setupStart).toContain('setStatusUnknown(false);');
    expect(s).toContain('statusUnknown,');   // fed to payControl
  });
});

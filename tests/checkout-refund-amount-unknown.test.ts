/**
 * The checkout refund state when the refunded amount is unknown (owner's remedy (i), 2026-09-18).
 *
 * WHY. Production's stripe-webhook (a16a16dc, `charge.refunded`) sets `status = 'refunded'` and `refunded_at` on ANY
 * refund, partial or full, and never writes an amount. So every production refund reaches this client as
 * `{ status: 'refunded', refunded_at: <date>, amount_refunded_cents: null, total: N }` — and at 8f45e9bb
 * `isRefundConfirmed` returned `true` for that row, so the screen said "This payment was refunded … No purchase was
 * made." Its fallback (`refund_pending`) claimed "No purchase was made" and "being processed", which no row reaching
 * it establishes either.
 *
 * THE OWNER'S RULES (2026-09-18, direct): unknown amount → "A refund was recorded for this payment. We can't confirm
 * the refunded amount here." Confirmed partial or full → describe only what the recorded amounts establish. Remove
 * "No purchase was made" from refund messaging entirely (even a confirmed full refund can follow a completed
 * purchase). Infer no processing, cancellation, bank timing or order status. Keep the Tickets route; offer no payment
 * retry from an unresolved refund state.
 *
 * A's payment-boundary contract (R1–R6), with one deliberate difference recorded here: a `refunded`-status row whose
 * recorded amount is known and below a known total is `partially_refunded` (the amounts establish exactly that),
 * where A's R1 routed it to the neutral kind. The owner's "describe what the recorded amounts establish" decides it.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import {
  _resetSetupInFlight,
  decideCheckoutSetup,
  refundStateFor,
  settledKind,
  type SetupDeps,
} from '../src/lib/checkout/setupDecision';
import { REFUND_COPY, refundViewModel } from '../src/lib/checkout/holdState';

beforeEach(() => _resetSetupInFlight());

const DATE = '2026-09-13T10:00:00Z';
const TOTAL = 11000;

/** The exact shape every production refund has today (webhook a16a16dc; migration 142 column always NULL). */
const PRODUCTION_REFUND = { status: 'refunded', refunded_at: DATE, amount_refunded_cents: null, total: TOTAL };

function deps(row: unknown) {
  return {
    fetchSettledPayment: vi.fn(async () => row),
    fetchListing: vi.fn(async () => ({ status: 'reserved', reserved_by: 'buyer', reserved_until: '2099-01-01T00:00:00Z' })),
    createIntent: vi.fn(async () => 'pi_new'),
    now: () => new Date('2026-09-18T18:00:00Z'),
  } as unknown as SetupDeps<string> & { createIntent: ReturnType<typeof vi.fn>; fetchListing: ReturnType<typeof vi.fn> };
}

// ── The matrix: status × refunded_at × amount × total ──────────────────────────────────────────────────────────
// Amounts, against a total of 11000: null, zero, partial, equal to the total, above the total.
const AMOUNTS = [null, 0, 5000, 11000, 12000] as const;
const U = 'refund_unconfirmed', P = 'partially_refunded', F = 'refunded', S = 'already_settled';
const MATRIX: [string, string | null, number | null, string[]][] = [
  // status       refunded_at total   null  0   5000  11000 12000
  ['succeeded', null, TOTAL, [S, S, P, U, U]],
  ['succeeded', DATE, TOTAL, [S, S, P, U, U]],
  ['succeeded', null, null,  [S, S, U, U, U]],   // an amount with no known total cannot be called "part"
  ['succeeded', DATE, null,  [S, S, U, U, U]],
  ['refunded',  DATE, TOTAL, [U, U, P, F, F]],   // [0] is the production row
  ['refunded',  null, TOTAL, [U, U, P, U, U]],   // a full amount without a date is not a confirmed full refund
  ['refunded',  DATE, null,  [U, U, U, U, U]],
  ['refunded',  null, null,  [U, U, U, U, U]],
];

describe('the refund kind is decided only by what the row establishes', () => {
  it.each(MATRIX.map(([status, at, total, want], i) => [`M${i + 1}`, status, at, total, want] as const))(
    '%s: %s, refunded_at=%s, total=%s',
    (_id, status, at, total, want) => {
      AMOUNTS.forEach((amount, j) => {
        const row = { status, refunded_at: at, amount_refunded_cents: amount, total };
        expect(settledKind(row), `amount=${amount}`).toBe(want[j]);
      });
    },
  );

  it('M9: other statuses are not settled at all', () => {
    for (const status of ['pending', 'failed', 'requires_action', 'processing']) {
      expect(settledKind({ status, refunded_at: DATE, amount_refunded_cents: TOTAL, total: TOTAL }), status).toBeNull();
    }
  });
});

describe('the production refund row', () => {
  it.each(['buy_now', 'auction'] as const)(
    'P1 (%s): neutral kind, no amount, and nothing that could take another payment is called',
    async (mode) => {
      const d = deps(PRODUCTION_REFUND);
      const r = await decideCheckoutSetup({ listingId: 'L', buyerId: 'buyer', mode }, d);

      expect(r).toEqual({ kind: 'refund_unconfirmed', refundedCents: null });
      expect(d.createIntent).not.toHaveBeenCalled();
      expect(d.fetchListing).not.toHaveBeenCalled();
    },
  );

  it('P2: the screen path (refundStateFor, used by revalidation) reaches the same state', () => {
    expect(refundStateFor(PRODUCTION_REFUND)).toEqual({ kind: 'refund_unconfirmed', refundedCents: null });
  });

  it('P3: a known partial and a confirmed full refund carry their recorded amounts', async () => {
    const partial = { status: 'succeeded', amount_refunded_cents: 5000, total: TOTAL };
    const full = { status: 'refunded', refunded_at: DATE, amount_refunded_cents: TOTAL, total: TOTAL };
    expect(await decideCheckoutSetup({ listingId: 'L1', buyerId: 'b', mode: 'auction' }, deps(partial)))
      .toEqual({ kind: 'partially_refunded', refundedCents: 5000 });
    expect(await decideCheckoutSetup({ listingId: 'L2', buyerId: 'b', mode: 'auction' }, deps(full)))
      .toEqual({ kind: 'refunded', refundedCents: TOTAL });
  });

  it('P4: the neutral state never carries an amount, whatever the row holds', () => {
    // A full amount on a succeeded row, or an amount with no total: the row holds a number, but the screen may not
    // present it as established.
    expect(refundStateFor({ status: 'succeeded', amount_refunded_cents: TOTAL, total: TOTAL })).toEqual({ kind: U, refundedCents: null });
    expect(refundStateFor({ status: 'succeeded', amount_refunded_cents: 5000, total: null })).toEqual({ kind: U, refundedCents: null });
    expect(refundStateFor({ status: 'succeeded', amount_refunded_cents: 0, total: TOTAL })).toBeNull();   // no refund
  });
});

// ── What the screen says ──────────────────────────────────────────────────────────────────────────────────────
// Claims no refund row can establish: that nothing was bought, cancellation, processing, bank/card timing, and
// the order's status.
const FORBIDDEN = /no purchase|cancel|in progress|being (processed|refunded)|processing|bank|card provider|when it appears|business day|order stands|your order/i;
const KINDS = ['refund_unconfirmed', 'partially_refunded', 'refunded'] as const;
const viewFor = (k: (typeof KINDS)[number]) => refundViewModel(k, k === 'refund_unconfirmed' ? null : k === 'refunded' ? TOTAL : 5000);
const allText = (v: ReturnType<typeof refundViewModel>) => [v.kicker, v.title, v.body, v.pointer, v.cta.label].join(' | ');

describe('the copy says only what the recorded amounts establish', () => {
  it('W1 (witness): the forbidden-claims pattern matches every claim the old copy made', () => {
    // Without this, the absence checks below could pass against a pattern that matches nothing.
    for (const old of [
      'The refund has been issued to your original payment method. When it appears depends on your bank or card provider. No purchase was made.',
      "This payment is being refunded. No purchase was made and there is nothing you need to do. We'll update this order once the refund is complete.",
      'Refund in progress',
      'A refund is being processed',
      'Your order stands. $20 has been returned to your original payment method; when it appears depends on your bank or card provider.',
    ]) expect(old).toMatch(FORBIDDEN);
  });

  it.each(KINDS)('K1 (%s): makes none of those claims', (k) => {
    expect(allText(viewFor(k))).not.toMatch(FORBIDDEN);
    for (const c of Object.values(REFUND_COPY[k])) expect(c).not.toMatch(FORBIDDEN);
  });

  it('K2: unknown amount — the owner\'s words, and no amount at all', () => {
    const v = refundViewModel('refund_unconfirmed', null);
    expect(v.body).toBe("A refund was recorded for this payment. We can't confirm the refunded amount here.");
    expect(allText(v)).not.toMatch(/\$|\d/);
    expect(v.kicker).not.toBe('Payment refunded');
  });

  it('K3: an amount handed to the neutral kind is still not shown', () => {
    expect(allText(refundViewModel('refund_unconfirmed', 5000))).not.toMatch(/\$|\d/);
  });

  it('K4: partial and full state the recorded amount, nothing more', () => {
    expect(refundViewModel('partially_refunded', 5000).body).toBe('A partial refund of $50 was recorded for this payment.');
    expect(refundViewModel('refunded', TOTAL).body).toBe('A full refund of $110 was recorded for this payment.');
    for (const k of KINDS) expect(viewFor(k).kicker).not.toBe('Payment refunded');
  });
});

describe('where the screen sends the buyer', () => {
  it.each(KINDS)('C1 (%s): to Tickets — never back to the listing, never a retry', (k) => {
    const v = viewFor(k);
    expect(v.cta.href).toBe('/(tabs)/tickets');
    expect(v.cta.href).not.toMatch(/listing|back/i);
    expect(v.cta.label).not.toMatch(/listing|try again|pay|retry|back/i);
  });

  it('C2: the pointer is an instruction, not a claim about the order', () => {
    expect(refundViewModel('refund_unconfirmed', null).pointer).toBe("Check Tickets for this order's current status.");
  });
});

// ── The screen's wiring (there is no RefundView render test; these pin the source the view model feeds) ────────
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const screenSrc = () => readFileSync(resolve(__dirname, '../src/screens/checkout/CheckoutNative.tsx'), 'utf8');
const slice = (src: string, from: string, to: string) => {
  const a = src.indexOf(from), b = src.indexOf(to, a + 1);
  expect(a, from).toBeGreaterThan(-1);
  expect(b, to).toBeGreaterThan(a);
  return src.slice(a, b);
};

describe('the screen uses the view model and the shared refund state', () => {
  it('S1: RefundView\'s only control goes where the view model says — never back(), never the listing', () => {
    const view = slice(screenSrc(), 'function RefundView(', '// -- Sub-components');
    expect(view).toContain('refundViewModel(state.kind, state.refundedCents)');
    expect(view).toContain('label={view.cta.label}');
    expect(view).toContain('onPress={() => router.replace(view.cta.href)}');
    expect(view).not.toMatch(/router\.back\(\)|Back to listing|Try again/);
  });

  it('S2: re-validation lands every refund row in the refund state with Pay turned off', () => {
    const body = slice(screenSrc(), 'async function revalidateAgainstServer()', 'async function recheckPayment()');
    expect(body).toContain('const refund = refundStateFor(settled);');
    expect(body).toContain("if (refund) { setRefundState(refund); setPaymentReady(false); return 'refund'; }");
  });
});

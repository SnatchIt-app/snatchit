/**
 * The fourth gated read — dispute outcomes — implemented against A's conditions RESTATED VERBATIM
 * on 2026-09-24 (A's 16:47Z conditions (a)–(d) plus the owner's 16:51Z refinement, which governs
 * where they differ). The separations under test, in the owner's words:
 *
 *   DECISION   = transfers.dispute_resolution — only an operator's ruling. (a) keys everything on
 *                this column; dispute_resolved_at is display only.
 *   OBLIGATION = "A refund is due" — supported ONLY when (i) status='expired' OR resolution ∈
 *                {resolved_buyer_refunded, resolved_partial_refund}, AND (ii) the payment was
 *                captured (payments.status='succeeded') with no recorded refund.
 *   EXECUTION  = a recorded refund on the payment row (refundLine non-null) — the only source of
 *                "Refunded …" / "Partly refunded …". (b) the value's NAME never maps to money copy.
 *
 * Five outcomes per (c), including seller-win AFTER payout, where "released" may come only from
 * payout_released_at and the buyer reads "resolved", never "under review".
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

import {
  disputeDecision,
  disputedStateCopy,
  disputedStateMeta,
} from '@/src/lib/transfer/disputeOutcome';
import {
  refundStateLine,
  REFUND_CHECKING_LINE,
  REFUND_UNREADABLE_LINE,
  type RefundRead,
} from '@/src/lib/transfer/refundState';
import {
  REFUND_DUE_POLICY,
  REFUND_PARTIAL_DUE_POLICY,
  REFUND_PENDING_LINE,
} from '@/src/lib/transfer/transferState';

const strip = (rel: string) => readFileSync(rel, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

const row = (over: Partial<{ status: string; dispute_resolution: string | null; dispute_resolved_at: string | null }> = {}) => ({
  status: 'disputed', dispute_resolution: null, dispute_resolved_at: null, ...over,
});

const loaded = (facts: Record<string, unknown> | null): RefundRead =>
  ({ kind: 'loaded', facts } as RefundRead);

const SUCCEEDED_NO_REFUND = { status: 'succeeded', amount_refunded_cents: null, refunded_at: null, total: 11000 };
const FULLY_REFUNDED = { status: 'refunded', amount_refunded_cents: 11000, refunded_at: 'x', total: 11000 };
const PARTLY_REFUNDED = { status: 'succeeded', amount_refunded_cents: 4000, refunded_at: 'x', total: 11000 };

describe('(a) the decision is keyed on dispute_resolution alone', () => {
  it('D1: null resolution on a disputed row is OPEN — resolved_at cannot decide anything by itself', () => {
    expect(disputeDecision(row())).toEqual({ kind: 'open' });
    // A stray timestamp without a ruling is still open: the column pair is written in one UPDATE,
    // so this shape is a server anomaly and the client must not invent a decision from it.
    expect(disputeDecision(row({ dispute_resolved_at: '2026-09-24T00:00:00Z' }))).toEqual({ kind: 'open' });
  });
  it('D2: a non-disputed, undecided row has no dispute state at all', () => {
    expect(disputeDecision(row({ status: 'seller_sent' }))).toEqual({ kind: 'none' });
  });
  it('D3: a recognised ruling is DECIDED, whatever the status column says', () => {
    const d = disputeDecision(row({ dispute_resolution: 'resolved_seller_paid', dispute_resolved_at: 'x' }));
    expect(d.kind).toBe('decided');
    expect(d.kind === 'decided' && d.resolution).toBe('resolved_seller_paid');
  });
  it('D4: an UNRECOGNISED ruling is decided-unknown — never mapped to any money or outcome copy', () => {
    const d = disputeDecision(row({ dispute_resolution: 'resolved_split_the_difference' }));
    expect(d.kind === 'decided' && d.resolution).toBe('unknown');
    for (const role of ['buyer', 'seller'] as const) {
      const c = disputedStateCopy(d, role);
      expect(`${c.title} ${c.body}`).not.toMatch(/refund|paid|payout|favour|released/i);
      expect(c.title).toMatch(/resolved|decision/i);
    }
  });
});

describe('(c) the five outcomes', () => {
  it('O1 open: the existing under-review copy and the Issue badge are untouched', () => {
    const d = disputeDecision(row());
    expect(disputedStateCopy(d, 'buyer').title).toBe('Issue reported');
    expect(disputedStateCopy(d, 'seller').title).toBe('Dispute in progress');
    expect(disputedStateMeta(d, 'buyer')).toEqual({ label: 'Issue', tone: 'warning' });
  });

  it('O2 seller-win, no payout yet: resolved copy, and the sentence claims nothing about the payout', () => {
    const d = disputeDecision(row({ dispute_resolution: 'resolved_seller_paid' }));
    const buyer = disputedStateCopy(d, 'buyer');
    expect(buyer.title).toBe('Dispute resolved');
    expect(buyer.body).toMatch(/seller'?s favour/i);
    expect(`${buyer.title} ${buyer.body}`).not.toMatch(/under review|24 hours|refund/i);
    const seller = disputedStateCopy(d, 'seller');
    expect(seller.title).toBe('Dispute resolved in your favour');
    expect(`${seller.title} ${seller.body}`).not.toMatch(/payout (has been |is )?(released|being processed)/i);
    for (const role of ['buyer', 'seller'] as const) {
      expect(disputedStateMeta(d, role)).toEqual({ label: 'Resolved', tone: 'neutral' });
    }
  });

  it('O3 seller-win AFTER payout: released comes only from payout_released_at; the buyer reads resolved', () => {
    // The screen source is the contract here: the seller block for a decided dispute derives its
    // payout line from the payout fields, never from the resolution name.
    const src = strip('app/transfer/send/[id].tsx');
    const idx = src.lastIndexOf("status === 'disputed'"); // the RENDER block, not the badge line
    expect(idx, 'the seller screen must branch a decided dispute').toBeGreaterThan(-1);
    const block = src.slice(idx, idx + 2600);
    expect(block).toMatch(/disputeDecision|disputedState/);
    expect(block).toMatch(/payout_released_at/);
    expect(block).not.toMatch(/resolved_seller_paid'?\s*\?\s*['"`][^'"`]*released/i);
    // A's (c) change (2026-09-24, verified against 065:129): inside status==='disputed', a
    // decided seller-win is by construction ALREADY PAID (unpaid seller-wins move to
    // buyer_confirmed), so the only rulings that can sit here unpaid are buyer-win, partial and
    // unknown — for whom payout_review_status / payout_hold_until can be STALE leftovers from the
    // seller_sent hold. A held-line here would tell a seller who lost the dispute that a payout
    // is coming. So the decided block derives from payout_released_at ALONE.
    expect(block).not.toMatch(/sellerHoldLine|heldLine|payout_review_status|payout_hold_until/);
    // …and the buyer's decided copy never reads as an open review (O2 already pinned the words).
    const d = disputeDecision(row({ dispute_resolution: 'resolved_seller_paid', dispute_resolved_at: 'x' }));
    expect(disputedStateCopy(d, 'buyer').body).not.toMatch(/under review|reviews within/i);
  });

  it('O4 buyer-win: the decision sentence carries no money claim; "Refunded" needs the payment row', () => {
    const d = disputeDecision(row({ dispute_resolution: 'resolved_buyer_refunded' }));
    const buyer = disputedStateCopy(d, 'buyer');
    expect(buyer.title).toBe('Dispute resolved in your favour');
    // (b): the VALUE IS NAMED "resolved_buyer_refunded" and the sentence still must not say it.
    expect(`${buyer.title} ${buyer.body}`).not.toMatch(/refunded|refund is due|returned|sent back/i);
    const seller = disputedStateCopy(d, 'seller');
    expect(seller.body).toMatch(/buyer'?s favour/i);
    expect(`${seller.title} ${seller.body}`).not.toMatch(/payout|reversed|refunded/i);
  });

  it('O5 partial: the decision names a partial outcome and invents no amount and no remainder', () => {
    const d = disputeDecision(row({ dispute_resolution: 'resolved_partial_refund' }));
    for (const role of ['buyer', 'seller'] as const) {
      const c = disputedStateCopy(d, role);
      expect(`${c.title} ${c.body}`).toMatch(/part/i);
      expect(`${c.title} ${c.body}`).not.toMatch(/\$|remaining|balance|rest of/i);
    }
  });
});

describe("the owner's obligation rule — 'due' needs a source AND a captured, unrefunded payment", () => {
  it('B1 shows: expired + succeeded + nothing recorded', () => {
    expect(refundStateLine(loaded(SUCCEEDED_NO_REFUND), 'expired')).toBe(REFUND_DUE_POLICY);
  });
  it('B2 shows: buyer-win + succeeded + nothing recorded', () => {
    expect(refundStateLine(loaded(SUCCEEDED_NO_REFUND), 'buyer_win')).toBe(REFUND_DUE_POLICY);
  });
  it('B3 shows the PARTIAL wording, with no amount, for a partial decision', () => {
    const line = refundStateLine(loaded(SUCCEEDED_NO_REFUND), 'partial');
    expect(line).toBe(REFUND_PARTIAL_DUE_POLICY);
    expect(line).not.toMatch(/\$/);
  });
  it('B4 never: a recorded refund replaces every due line with the recorded fact', () => {
    for (const ctx of ['expired', 'buyer_win', 'partial'] as const) {
      expect(refundStateLine(loaded(FULLY_REFUNDED), ctx)).toBe('Refunded $110');
      expect(refundStateLine(loaded(PARTLY_REFUNDED), ctx)).toBe('Partly refunded $40 of $110');
    }
  });
  it('B5 never: expired with a payment that is not succeeded — the capture is the ground of the claim', () => {
    expect(refundStateLine(loaded({ status: 'pending', amount_refunded_cents: null, refunded_at: null, total: 11000 }), 'expired'))
      .toBe(REFUND_PENDING_LINE);
    // The (ii) change from today's code: NO payment row read at all is not a capture either.
    expect(refundStateLine(loaded(null), 'expired')).toBe(REFUND_PENDING_LINE);
  });
  it('B6 never: reversed keeps its neutral line; loading and error keep their own states', () => {
    expect(refundStateLine(loaded(SUCCEEDED_NO_REFUND), 'reversed')).toBe(REFUND_PENDING_LINE);
    expect(refundStateLine({ kind: 'loading' }, 'buyer_win')).toBe(REFUND_CHECKING_LINE);
    expect(refundStateLine({ kind: 'error' }, 'partial')).toBe(REFUND_UNREADABLE_LINE);
  });
  it('B7 MAJOR-1: expired + partly refunded shows the recorded partial — and claims no remainder', () => {
    const line = refundStateLine(loaded(PARTLY_REFUNDED), 'expired');
    expect(line).toBe('Partly refunded $40 of $110');
    expect(line).not.toMatch(/remaining|still owed|balance/i);
  });
});

describe('(d) the read itself — both screens, exactly two new columns, and the buyer read runs for decided disputes', () => {
  it('R1: both selects carry dispute_resolution and dispute_resolved_at on the same one-row query', () => {
    for (const rel of ['app/transfer/receive/[id].tsx', 'app/transfer/send/[id].tsx']) {
      const src = strip(rel);
      expect(src, rel).toMatch(/dispute_resolution, dispute_resolved_at/);
    }
  });
  it("R3: buyer-win with a STALE hold (payout_review_status 'held', future payout_hold_until) gets NO payout sentence", () => {
    // The A-required case, structurally: the decided-dispute block's only payout derivation is
    // payout_released_at, so a stale hold cannot produce a sentence. (The source pin above is the
    // enforcement; this test documents the exact scenario A named.)
    const src = strip('app/transfer/send/[id].tsx');
    const idx = src.lastIndexOf("status === 'disputed'");
    const block = src.slice(idx, idx + 2600);
    const derivation = block.slice(block.indexOf('payoutLine'), block.indexOf('return ('));
    expect(derivation).toMatch(/payout_released_at/);
    expect(derivation).not.toMatch(/held|review/i);
  });

  it("R4: NO unreleased, unheld payout ever reads 'being processed' — genuine confirmation included", () => {
    // RETARGETED (A, 2026-09-24, owner 16:51Z verbatim): "This applies to genuine confirmations
    // and to auto-released rows too." The only per-transfer evidence of a payout in flight is
    // payout_attempts, which is service_role-only; confirm-and-release's 'processing' reply is
    // unstored and also returned on a claim db_error. So BOTH paths render the pending state;
    // the genuine confirmation may keep the Settings nudge as GUIDANCE, a separate sentence,
    // never as a progress claim.
    const src = strip('app/transfer/send/[id].tsx');
    const idx = src.indexOf("'buyer_confirmed'");
    const block = src.slice(idx, idx + 3200);
    expect(block).not.toMatch(/being processed/);
    expect(block).toContain("'Payout pending.'");
    expect(block).toMatch(/Make sure your payout account is set up in Settings\./);
  });

  it('R2: the buyer screen runs the settled read for a decided buyer-win or partial dispute', () => {
    const src = strip('app/transfer/receive/[id].tsx');
    expect(src).toMatch(/closedForRefund/);
    expect(src).toMatch(/resolved_buyer_refunded|refundDueContext|disputeDecision/);
  });
});

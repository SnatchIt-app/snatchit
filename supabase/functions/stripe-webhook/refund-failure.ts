/**
 * stripe-webhook/refund-failure.ts — refunds-4 (DESIGN-199-FINAL §5.1).
 *
 * A Stripe refund that FAILS or is CANCELED converges kernel.refund through
 * exactly one verb, `kernel.record_refund_stripe_failure` (199). Nothing
 * else can: mark_refund_state only moves forward, and the executor's claim
 * never revisits a `succeeded` row. Without this call a refund that
 * succeeded and then failed stays `succeeded` forever — no
 * `refund.failed_after_success` audit row, no page, a venue refund_void
 * debit for money that never reached the buyer, and a buyer holding voided
 * tickets and no money.
 *
 * The two decisions live here, import-free apart from `isUuid`, so they are
 * pinned without a network (tests/refund-webhook-refunds4.test.ts). Same
 * split as native.ts: a non-2xx asks Stripe to deliver again, which is only
 * right when a redelivery could plausibly succeed. A deterministic refusal
 * is ACKed and paged, never looped for three days.
 */

import { isUuid } from './native.ts';

/**
 * How long a `not_bound` answer on one of OUR refunds is retried. The
 * executor POSTs the refund and only then binds its `re_…` through
 * mark_refund_state, so a fast failure can reach us first. This is A's
 * engineering constant, not policy (DESIGN-199 §5.1).
 */
export const REFUND_FAILURE_UNBOUND_GRACE_SECONDS = 3600;

/**
 * How long a retryable fault is retried silently before it also pages. A blip
 * must not page on every delivery attempt, but a persistent fault (a lost
 * grant, a rotated key) retried silently until Stripe gives up would lose the
 * convergence with no alert. Past this age a transient no longer explains it.
 * The same window as the not_bound grace, deliberately (E review of 17d48073).
 */
export const REFUND_FAILURE_RETRY_PAGE_AFTER_SECONDS = REFUND_FAILURE_UNBOUND_GRACE_SECONDS;

/**
 * Must this observation reach the verb? Yes when Stripe now says the refund
 * failed or was canceled, and also when record_refund_state refused it as a
 * `stale_observation`: that refusal means a failure was ALREADY recorded,
 * and the delivery that recorded it may have died before converging.
 */
export function needsRefundFailureConvergence(status: string | null | undefined, recordResult: unknown): boolean {
  if (status === 'failed' || status === 'canceled') return true;
  return (recordResult as { reason?: unknown } | null)?.reason === 'stale_observation';
}

type Page = { tag: string; facts: Record<string, unknown> };

export type RefundFailureDecision =
  | { ack: true; page: Page | null; log: string }
  | { ack: false; reason: string; page?: Page };

/**
 * The verb's own refusals: deterministic, so a redelivery cannot change them.
 * Classified on SQLSTATE: every raise in the verb sets it (P0001 for
 * invalid_input / precondition_failed / conflict_locked, P0002 for not_found).
 * A code is stabler than the text PostgREST relays, which it may wrap or
 * truncate. The message tokens are only a fallback for an error with no code.
 * (E review of ab41ab78.)
 */
const REFUSAL_SQLSTATES = new Set(['P0001', 'P0002']);
const DETERMINISTIC_REFUSAL = /precondition_failed|conflict_locked|invalid_input|not_found/;

type Obj = Record<string, unknown>;
const obj = (v: unknown): Obj | null => (v !== null && typeof v === 'object' && !Array.isArray(v) ? v as Obj : null);
const idOf = (v: unknown, key: string): unknown => obj(v)?.[key] ?? null;
const count = (v: unknown): number => (Array.isArray(v) ? v.length : 0);

/**
 * What the verb's answer means for this delivery. Page facts are ids, counts
 * and flags only: no buyer data ever leaves in a page.
 */
export function classifyRefundFailureResult(
  res: { data: unknown; error: { message?: string; code?: string } | null },
  ctx: { metadata: Record<string, string> | null | undefined; ageSeconds: number; stripeRefundRef: string },
): RefundFailureDecision {
  if (res.error) {
    const message = res.error.message ?? '';
    const code = res.error.code ?? '';
    if (code === 'PGRST202') {
      // The verb is not there: this webhook was deployed before 199 was
      // applied, or 199 was rolled back. The one error that heals itself — the
      // same call succeeds the moment 199 is live — so it is retried, never
      // ACKed (which would lose this refund's convergence for good), and paged
      // with the ref so the gap is visible.
      return {
        ack: false,
        reason: 'record_refund_stripe_failure missing (199 not applied?)',
        page: { tag: 'refund-webhook:verb_missing', facts: { stripe_refund_ref: ctx.stripeRefundRef } },
      };
    }
    const refusal = code ? (REFUSAL_SQLSTATES.has(code) ? code : null) : DETERMINISTIC_REFUSAL.exec(message)?.[0] ?? null;
    if (refusal) {
      return {
        ack: true,
        page: { tag: 'refund-webhook:verb_refused', facts: { refusal, stripe_refund_ref: ctx.stripeRefundRef } },
        log: message,
      };
    }
    // Transport, 5xx, 57P01, a statement timeout: both SQL steps replay
    // idempotently, so let Stripe deliver again. Silent while the event is
    // young; paged once it is old enough to be a persistent fault, which also
    // covers an undatable event (ageSeconds is Infinity).
    const reason = `record_refund_stripe_failure: ${message || code || 'error'}`;
    if (ctx.ageSeconds >= REFUND_FAILURE_RETRY_PAGE_AFTER_SECONDS) {
      return {
        ack: false,
        reason,
        page: { tag: 'refund-webhook:convergence_stalled', facts: { code: code || null, stripe_refund_ref: ctx.stripeRefundRef } },
      };
    }
    return { ack: false, reason };
  }

  const d = obj(res.data);
  switch (d?.status) {
    case 'ok': {
      if (d.transition === 'succeeded_to_failed') {
        return {
          ack: true,
          log: 'refund failed after success',
          page: {
            tag: 'refund-webhook:failed_after_success',
            facts: {
              refund_id: d.refund_id ?? null,
              failure_code: d.failure_code ?? null,
              settlement_review_required: d.settlement_review_required === true,
              settlement_id: idOf(d.refund_void_line, 'settlement_id'),
              settlement_shortfall_obligation_id: idOf(d.settlement_shortfall_obligation, 'obligation_id'),
              unlined_reversal_obligation_id: idOf(d.unlined_reversal_obligation, 'obligation_id'),
              refund_clawback_obligation_id: idOf(d.refund_clawback_obligation, 'obligation_id'),
              atoms_voided: count(d.atoms_voided),
              compensated_market_sales: count(d.compensated_market_sale_ids),
              promoter_commission_lined: d.promoter_commission_lined === true,
            },
          },
        };
      }
      // submitted_to_failed: the buyer may still hold voided tickets and no money.
      return {
        ack: true,
        log: 'refund failed',
        page: { tag: 'refund-webhook:refund_failed', facts: { refund_id: d.refund_id ?? null, failure_code: d.failure_code ?? null } },
      };
    }
    case 'noop_replay':
    case 'in_flight':
    case 'not_failed':
      return { ack: true, page: null, log: `refund failure: ${d.status}` };
    case 'not_bound': {
      const ours = ctx.metadata?.source === 'refund-execute';
      const refundId = isUuid(ctx.metadata?.refund_id) ? ctx.metadata!.refund_id : null;
      if (ours && refundId && ctx.ageSeconds < REFUND_FAILURE_UNBOUND_GRACE_SECONDS) {
        return { ack: false, reason: 'refund_failure_unbound: awaiting the executor\'s ref binding' };
      }
      if (ours) {
        return { ack: true, page: { tag: 'refund-webhook:failure_unbound', facts: { refund_id: refundId } }, log: 'refund failure unbound' };
      }
      // Dashboard, expiry-sweep and ops-rail refunds have no kernel row.
      return { ack: true, page: null, log: 'refund failure: no kernel refund' };
    }
    default:
      return { ack: true, page: { tag: 'refund-webhook:verb_unrecognized', facts: { status: String(d?.status ?? typeof res.data) } }, log: 'unrecognized verb answer' };
  }
}

/**
 * stripe-webhook/sibling-guard.ts — pre-terminal-cancel sibling inspection.
 *
 * WHY THIS EXISTS
 *   `payment_intent.canceled` is per-attempt. Cancelling the pending order when
 *   ANY sibling PI of the same order succeeded or is processing charges the
 *   buyer and destroys the order before finalize. This module reads every
 *   candidate payments row for the order's (buyer, native rail, face amount),
 *   confirms each candidate PI's own metadata with Stripe, and returns a
 *   fail-closed order-level decision. It never cancels a PI or writes a row.
 *
 * IMPORT-FREE by construction (deps are passed in), like ./native.ts, so the
 * edge VM can load the real module and tests can exercise the handler wiring.
 * The DB query is paginated; a page/read/Stripe failure is an error, never
 * "clear". The current PI is excluded by PI id, not trusted from the event.
 *
 * RESIDUAL RACE: this read is not atomic with `cancel_pending_order`. A
 * sibling can transition to succeeded/processing, or a new PI can be inserted,
 * after the last read and before the cancel RPC. The existing DB/Stripe APIs
 * provide no shared transaction for that comparison; this guard narrows the
 * window but cannot prove the property race-free. A later finalize of a paid
 * sibling still produces its existing alert/review instead of silence.
 */

export const NATIVE_PRIMARY = 'native_primary';
export const SIBLING_PAGE_SIZE = 50;
export const SIBLING_MAX_PAGES = 20;

export type StripeRawFetch = (
  path: string,
  init?: { method?: 'GET' | 'POST' | 'DELETE'; body?: Record<string, string>; idempotencyKey?: string },
) => Promise<{ ok: boolean; status: number; data: unknown }>;

// deno-lint-ignore no-explicit-any
export type ServiceClient = { from: (table: string) => any };

export type SiblingInspection =
  | { kind: 'clear' }
  | { kind: 'succeeded'; piId: string; detail: string }
  | { kind: 'processing'; piId: string; detail: string }
  | { kind: 'live'; piId: string; status: string; detail: string }
  | { kind: 'unknown'; piId: string; detail: string }
  | { kind: 'error'; detail: string };

type PaymentCandidate = {
  stripe_payment_intent_id?: unknown;
  status?: unknown;
  total?: unknown;
};

const SUCCESS_OR_INFLIGHT = new Set(['succeeded', 'processing']);
const LIVE = new Set(['requires_payment_method', 'requires_confirmation', 'requires_action', 'requires_capture']);

function text(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

async function readCandidates(
  service: ServiceClient,
  q: { buyerId: string; faceMinor: number; currentPiId: string },
): Promise<{ kind: 'ok'; rows: PaymentCandidate[] } | { kind: 'error'; detail: string }> {
  const rows: PaymentCandidate[] = [];
  for (let page = 0; page < SIBLING_MAX_PAGES; page++) {
    const from = page * SIBLING_PAGE_SIZE;
    let data: unknown;
    let error: unknown;
    try {
      const result = await service
        .from('payments')
        .select('stripe_payment_intent_id,status,total')
        .eq('buyer_id', q.buyerId)
        .eq('mode', NATIVE_PRIMARY)
        .eq('amount', q.faceMinor)
        .neq('stripe_payment_intent_id', q.currentPiId)
        .order('created_at', { ascending: false })
        .order('id', { ascending: false })
        .range(from, from + SIBLING_PAGE_SIZE - 1);
      data = result?.data;
      error = result?.error;
    } catch (err) {
      return { kind: 'error', detail: err instanceof Error ? err.message : String(err) };
    }
    if (error) {
      return { kind: 'error', detail: (error as { message?: string })?.message ?? String(error) };
    }
    if (!Array.isArray(data)) {
      return { kind: 'error', detail: `candidate page is not an array (${data === null ? 'null' : typeof data})` };
    }
    const pageRows = data as unknown[];
    for (const row of pageRows) {
      if (!row || typeof row !== 'object' || Array.isArray(row)) {
        return { kind: 'error', detail: 'candidate row is not an object' };
      }
      const candidate = row as PaymentCandidate;
      if (!text(candidate.stripe_payment_intent_id) || !text(candidate.status)) {
        return { kind: 'error', detail: 'candidate row lacks stripe_payment_intent_id or status' };
      }
      rows.push(candidate);
    }
    if (pageRows.length < SIBLING_PAGE_SIZE) return { kind: 'ok', rows };
  }
  return { kind: 'error', detail: `more than ${SIBLING_MAX_PAGES} candidate pages` };
}

/** Every candidate is confirmed against its own PI metadata, never the event payload alone. */
export async function inspectTerminalSiblings(
  deps: { service: ServiceClient; stripeFetchRaw: StripeRawFetch },
  q: { orderId: string; buyerId: string; faceMinor: number; currency: string; currentPiId: string },
): Promise<SiblingInspection> {
  if (!Number.isInteger(q.faceMinor) || q.faceMinor < 0) {
    return { kind: 'error', detail: 'event amount is not a non-negative integer' };
  }
  if (!q.orderId || !q.buyerId || !q.currentPiId || !q.currency) {
    return { kind: 'error', detail: 'order, buyer or current PI id is missing' };
  }

  const found = await readCandidates(deps.service, q);
  if (found.kind === 'error') return found;

  const seen = new Set<string>();
  for (const row of found.rows) {
    const piId = text(row.stripe_payment_intent_id);
    const rowStatus = text(row.status);
    if (!piId) return { kind: 'unknown', piId: '<missing>', detail: 'candidate row has no PaymentIntent id' };
    if (piId === q.currentPiId || seen.has(piId)) continue;
    seen.add(piId);

    let probe: Awaited<ReturnType<StripeRawFetch>>;
    try {
      probe = await deps.stripeFetchRaw(`/payment_intents/${piId}`);
    } catch (err) {
      return { kind: 'error', detail: `stripe GET ${piId} threw: ${err instanceof Error ? err.message : String(err)}` };
    }
    if (probe.status === 404) {
      return { kind: 'unknown', piId, detail: `Stripe has no PaymentIntent ${piId}; authoritative status unavailable` };
    }
    if (!probe.ok) return { kind: 'error', detail: `stripe GET ${piId} answered ${probe.status}` };

    const pi = probe.data as {
      id?: unknown;
      status?: unknown;
      amount?: unknown;
      currency?: unknown;
      metadata?: Record<string, unknown> | null;
    } | null;
    if (!pi || typeof pi !== 'object' || Array.isArray(pi)) {
      return { kind: 'error', detail: `stripe GET ${piId} returned a malformed body` };
    }
    const gotId = text(pi?.id);
    const piStatus = text(pi?.status);
    if (gotId !== piId) return { kind: 'unknown', piId, detail: `Stripe returned id ${gotId || '<missing>'}` };
    if (text(pi?.metadata?.order_id) !== q.orderId || text(pi?.metadata?.rail) !== NATIVE_PRIMARY) {
      return { kind: 'unknown', piId, detail: 'candidate PI metadata names another order or rail' };
    }
    if (text(pi?.metadata?.buyer_id) !== q.buyerId) {
      return { kind: 'unknown', piId, detail: 'candidate PI metadata names another buyer' };
    }
    // The row was selected by ticket face value. Stripe charges each attempt's
    // own total, including its buyer fee, which can differ from the event's.
    if (typeof row.total !== 'number' || !Number.isSafeInteger(row.total)
        || row.total < q.faceMinor || pi.amount !== row.total || text(pi.currency) !== q.currency) {
      return { kind: 'unknown', piId, detail: 'candidate PI amount or currency does not match its payment quote' };
    }

    // A locally succeeded/processing row is a second authoritative signal; a
    // conflict with Stripe is not permission to cancel.
    if (SUCCESS_OR_INFLIGHT.has(rowStatus) && !SUCCESS_OR_INFLIGHT.has(piStatus)) {
      return { kind: 'unknown', piId, detail: `payments row is ${rowStatus} but PI is ${piStatus || '<missing>'}` };
    }
    if (rowStatus === 'succeeded' || piStatus === 'succeeded') {
      return { kind: 'succeeded', piId, detail: `succeeded sibling ${piId}` };
    }
    if (rowStatus === 'processing' || piStatus === 'processing') {
      return { kind: 'processing', piId, detail: `processing sibling ${piId}` };
    }
    if (piStatus === 'canceled') continue;
    if (LIVE.has(piStatus)) {
      return { kind: 'live', piId, status: piStatus, detail: `live sibling ${piId} is ${piStatus}` };
    }
    return { kind: 'unknown', piId, detail: `unknown sibling PI status ${piStatus || '<missing>'}` };
  }
  return { kind: 'clear' };
}

export function decideSiblingInspection(result: SiblingInspection): { ack: boolean; alert: boolean; reason: string } {
  switch (result.kind) {
    case 'clear':
      return { ack: true, alert: false, reason: 'native_sibling_clear' };
    case 'succeeded':
      return { ack: true, alert: true, reason: 'native_sibling_succeeded_order_pending' };
    case 'processing':
      return { ack: true, alert: false, reason: 'native_sibling_processing_order_pending' };
    case 'live':
      return { ack: true, alert: false, reason: 'native_sibling_live_order_pending' };
    case 'unknown':
      return { ack: true, alert: true, reason: 'native_sibling_unknown_order_pending' };
    case 'error':
      return { ack: false, alert: true, reason: 'native_sibling_lookup_error' };
  }
}

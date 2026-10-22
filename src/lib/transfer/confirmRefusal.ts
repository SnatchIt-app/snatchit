/**
 * src/lib/transfer/confirmRefusal.ts — what the buyer reads when confirm-and-release does not answer
 * 2xx (CFT-703; A's refusal catalogue SERVER_REFUSAL_CATALOGUE_C_20261021, §5–§8).
 *
 * The edge function's JSON `error` is never shown: it carries status enums (CNF-1, CRE-400b),
 * "Internal server error" (CRE-500) and, through CRE-401, whatever a parser threw. The one exception
 * is CRE-403a, whose sentence is user-facing by design and is keyed on its `code`.
 *
 * Matching recipe (catalogue): the edge's `code` first, then the HTTP status, then a CNF message
 * prefix for a 400 (no hint or code exists for those yet); anything unmatched gets the generic line.
 * The caller logs the raw text, and re-reads the order before calling this: the edge can answer 404
 * or 500 AFTER the confirmation is recorded (CRE-404, CRE-500), and a confirmed row is a success.
 */
import { isNetworkError } from '@/src/lib/ui/loadState';

export interface ConfirmFailure {
  /** The HTTP status, or null when there was no response (a throw, a network failure). */
  httpStatus: number | null;
  /** The body's `error` — for the log, and for CRE-403a only on screen. */
  error: string | null;
  /** The body's machine `code` (only CRE-403a has one today). */
  code: string | null;
  network: boolean;
}

export const CONFIRM_REFUSAL_COPY = {
  title: "Couldn't confirm receipt",
  // CNF-1 by status, each followed by a refresh (catalogue §5a).
  notSentYet: "The seller hasn't marked this as sent yet. Pull down to refresh.",
  underReview: 'This order is under review. Pull down to refresh.',
  closed: 'This order has been closed. Pull down to refresh.',
  notFound: "We couldn't find this order. Pull down to refresh.",           // CNF-2
  changed: 'This order changed. Pull down to refresh.',                     // CRE-400b
  rateLimited: 'Please wait a few minutes and try again.',                   // CRE-429
  signIn: 'Please sign in again.',                                           // CRE-401
  disputeHold: 'This order is under review, so payment is on hold.',         // CRE-409
  unavailable: "We couldn't confirm right now. Please try again shortly.",   // CRE-503
  notConfirmedYet: "We couldn't confirm yet. Pull down to refresh.",         // CRE-404
  internal: "We couldn't confirm receipt. Pull down to refresh before trying again.", // CRE-500
  offline: 'Check your connection and try again.',                           // §6
  generic: 'Something went wrong. Please try again.',
} as const;

/** A row that says the buyer's confirmation landed, whatever the edge replied. */
export function confirmationLanded(status: string | null | undefined): boolean {
  return status === 'buyer_confirmed' || status === 'auto_released';
}

function bodyFields(body: unknown): { error: string | null; code: string | null } {
  if (!body || typeof body !== 'object') return { error: null, code: null };
  const b = body as Record<string, unknown>;
  return {
    error: typeof b.error === 'string' && b.error ? b.error : null,
    code: typeof b.code === 'string' && b.code ? b.code : null,
  };
}

/** The failure `functions.invoke` returned: its status and JSON body when they can be read. */
export async function readConfirmFailure(fnError: unknown, data: unknown): Promise<ConfirmFailure> {
  const err = (fnError ?? {}) as { name?: string; message?: string; context?: unknown };
  const ctx = err.context as { status?: unknown; json?: () => Promise<unknown> } | undefined;
  if (err.name === 'FunctionsFetchError' || isNetworkError(err) || isNetworkError(ctx)) {
    return { httpStatus: null, error: null, code: null, network: true };
  }
  const httpStatus = ctx && typeof ctx.status === 'number' ? ctx.status : null;
  let fields: { error: string | null; code: string | null } = { error: null, code: null };
  try {
    if (ctx && typeof ctx.json === 'function') fields = bodyFields(await ctx.json());
    else fields = bodyFields(typeof data === 'string' ? JSON.parse(data) : data);
  } catch { /* an unreadable body keeps the status */ }
  return { httpStatus, ...fields, network: false };
}

/** The call threw instead of answering. */
export function confirmFailureFromThrow(e: unknown): ConfirmFailure {
  return { httpStatus: null, error: null, code: null, network: isNetworkError(e) };
}

/** CNF-1, matched by text until A's TRANSFER_NOT_CONFIRMABLE hint lands (catalogue §7). */
function cnfStatus(message: string): string | null {
  const m = /cannot be confirmed from current status:\s*([a-z_]+)/i.exec(message);
  return m ? m[1].toLowerCase() : null;
}

/** The buyer's line for a refusal. Never the server's text, except CRE-403a. */
export function confirmRefusalCopy(f: ConfirmFailure): string {
  const c = CONFIRM_REFUSAL_COPY;
  if (f.code === 'account_deletion_pending') return f.error ?? c.generic;   // CRE-403a
  if (f.network) return c.offline;
  switch (f.httpStatus) {
    case 401: return c.signIn;
    case 404: return c.notConfirmedYet;
    case 409: return c.disputeHold;
    case 429: return c.rateLimited;
    case 500: return c.internal;
    case 503: return c.unavailable;
    case 400:
    case null: {
      const msg = (f.error ?? '').trim();
      const status = cnfStatus(msg);
      if (status === 'pending') return c.notSentYet;
      if (status === 'disputed') return c.underReview;
      if (status === 'expired' || status === 'reversed') return c.closed;
      if (/^Transfer not found\.?$/.test(msg)) return c.notFound;
      if (/^Transfer is in unexpected state:/.test(msg)) return c.changed;
      return c.generic;
    }
    default: return c.generic;
  }
}

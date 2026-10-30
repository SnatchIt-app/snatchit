/**
 * src/lib/checkout/settledRead.ts — the ONE read of a buyer's own settled payments for a listing (F-CHK-READERR).
 *
 * Both checkout call sites (setup and the server re-validation) used to run this query inline and keep `data` while
 * discarding `error`, so a failed read — the pre-142 database's 42703, a 5xx, a dropped connection — looked exactly
 * like "no payment": setup went on to the hold and the intent, and re-validation could re-arm Pay. This returns the
 * rows OR the error, and never turns an error into "no rows". A thrown request is caught and returned as an error too.
 *
 * Kept free of React Native and path aliases (like setupDecision.ts) so A's end-to-end rehearsal can call it with a
 * real PostgREST client.
 */
import { SETTLED_STATUSES, type ListingHold, type ListingRead, type SettledPayment, type SettledRead } from './setupDecision';

interface SettledQuery {
  eq(column: string, value: string): SettledQuery;
  in(column: string, values: readonly string[]): SettledQuery;
  limit(count: number): PromiseLike<{ data: unknown; error: { code?: string | null; message?: string } | null }>;
}

/**
 * The part of a Supabase/PostgREST client this read uses. Typed loosely at the boundary on purpose: checking the full
 * generated client type against a structural interface is too deep for tsc (TS2589), and the query shape is pinned by
 * R1 instead.
 */
export interface SettledReadClient {
  from(table: 'payments'): unknown;
}

/** Thrown by the screen's setup dependency so decideCheckoutSetup stops; its message is `<code>: <message>`, no PII. */
export class SettledReadError extends Error {
  readonly code: string | null;
  constructor(e: { code: string | null; message: string }) {
    super(`${e.code ?? 'no-code'}: ${e.message}`);
    this.name = 'SettledReadError';
    this.code = e.code;
  }
}

export async function readSettledPayments(client: SettledReadClient, listingId: string, buyerId: string): Promise<SettledRead> {
  try {
    const { data, error } = await (client.from('payments') as { select(columns: string): SettledQuery })
      .select('status, refunded_at, amount_refunded_cents, total')
      .eq('listing_id', listingId)
      .eq('buyer_id', buyerId)
      .in('status', [...SETTLED_STATUSES])
      .limit(5);
    if (error) return { error: { code: error.code ?? null, message: error.message ?? 'unknown error' } };
    // Only a list establishes "no settled payment"; any other reply (null, an object, a string) establishes nothing.
    if (!Array.isArray(data)) return { error: { code: null, message: 'unexpected response: not a list' } };
    return { rows: data as SettledPayment[] };
  } catch (e) {
    return { error: { code: null, message: e instanceof Error ? e.message : String(e) } };
  }
}

/** The part of a Supabase/PostgREST client the listing read uses (typed loosely for the same TS2589 reason). */
export interface ListingReadClient {
  from(table: 'listings'): unknown;
}

interface ListingQuery {
  eq(column: string, value: string): ListingQuery;
  maybeSingle(): PromiseLike<{ data: unknown; error: { code?: string | null; message?: string } | null }>;
}

/**
 * The re-validation read of a listing's hold (D's R2). A successful read with no row is `{ listing: null }` (the hold
 * is not ours: 'lost'); a returned error, a thrown request, or a reply that is neither a row nor null is an error —
 * the hold is then UNKNOWN, never lost. Kept free of React Native and path aliases for A's E2E.
 */
export async function readListingHold(client: ListingReadClient, listingId: string): Promise<ListingRead> {
  try {
    const { data, error } = await (client.from('listings') as { select(columns: string): ListingQuery })
      .select('status, reserved_by, reserved_until')
      .eq('id', listingId)
      .maybeSingle();
    if (error) return { error: { code: error.code ?? null, message: error.message ?? 'unknown error' } };
    if (data === null || data === undefined) return { listing: null };
    if (typeof data !== 'object' || Array.isArray(data)) return { error: { code: null, message: 'unexpected response: not a row' } };
    return { listing: data as ListingHold };
  } catch (e) {
    return { error: { code: null, message: e instanceof Error ? e.message : String(e) } };
  }
}

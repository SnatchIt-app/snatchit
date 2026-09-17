/**
 * src/lib/transfer/markSent.ts — how "Mark as sent" decides what happened (F-IMG-1,
 * 2026-09-18). Contract (A, from 0553 + B's measured replay): `mark_transfer_sent`
 * is NOT idempotent — it raises "Transfer cannot be marked as sent from current
 * status: seller_sent." on any call after the first — and returns void. So the
 * client never infers success from "no error", and never shows that raise as a
 * failure without reading the transfer's status:
 *
 *   1. read status first: already sent (a lost response last time) → sent, with no
 *      upload and no call; not pending (expired, cancelled…) → no call;
 *   2. upload (the hook reuses an object already uploaded for this exact selection);
 *   3. call the verb — a thrown or timed-out call only makes the outcome uncertain;
 *   4. read status again: sent → sent; anything else → unconfirmed, which the screen
 *      shows as "refresh" — never success, never a plain failure.
 *
 * A button guard (single-flight) prevents a double tap in one session; only this
 * read settles an uncertain outcome across a lost response or a relaunch.
 */

export type MarkSentOutcome =
  | { kind: 'sent'; path: string | null }
  | { kind: 'not_pending'; status: string }
  | { kind: 'upload_failed' }
  | { kind: 'failed'; message: string }
  | { kind: 'unconfirmed' };

export interface MarkSentDeps {
  /** The transfer's current status, or null when the read failed. */
  readStatus(): Promise<string | null>;
  /** The storage path of the evidence, or null when the upload failed (the hook shows why). */
  upload(): Promise<string | null>;
  call(path: string): Promise<{ error: { message: string } | null }>;
}

const SENT = new Set(['seller_sent', 'buyer_confirmed', 'auto_released']);

export function isAlreadySentRaise(message: string | null | undefined): boolean {
  return /cannot be marked as sent from current status:\s*(seller_sent|buyer_confirmed|auto_released)/i.test(message ?? '');
}

export const MARK_SENT_COPY = {
  unconfirmed: "We couldn't confirm this transfer was marked as sent. Pull down to refresh before trying again.",
  notPending: 'This transfer can no longer be marked as sent. Pull down to refresh to see its current status.',
  failedFallback: "Couldn't mark this transfer as sent. Try again.",
} as const;

async function safeRead(deps: MarkSentDeps): Promise<string | null> {
  try { return await deps.readStatus(); } catch { return null; }
}

export async function runMarkSent(deps: MarkSentDeps): Promise<MarkSentOutcome> {
  const before = await safeRead(deps);
  if (before !== null && SENT.has(before)) return { kind: 'sent', path: null };
  if (before !== null && before !== 'pending') return { kind: 'not_pending', status: before };
  // before === null: the status read failed; proceed — the verb itself refuses anything not pending,
  // and step 4 settles the outcome.

  let path: string | null = null;
  try { path = await deps.upload(); } catch { path = null; }
  if (!path) return { kind: 'upload_failed' };

  // A thrown or timed-out call is not a failure by itself: the transfer may have been marked.
  let error: { message: string } | null = null;
  let uncertain = false;
  try { ({ error } = await deps.call(path)); } catch { uncertain = true; }
  const after = await safeRead(deps);
  if (after !== null && SENT.has(after)) return { kind: 'sent', path };
  if (!uncertain && error && !isAlreadySentRaise(error.message)) return { kind: 'failed', message: error.message || MARK_SENT_COPY.failedFallback };
  return { kind: 'unconfirmed' };
}

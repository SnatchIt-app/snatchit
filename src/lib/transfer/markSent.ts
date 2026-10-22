/**
 * src/lib/transfer/markSent.ts — how "Mark as sent" and "Add proof" decide what happened.
 *
 * Contract (140, A's literals 2026-09-18):
 *  - `mark_transfer_sent(p_transfer_id, p_user_id, p_transfer_evidence_path)` returns
 *    `{outcome: 'transitioned' | 'already_sent', status, seller_sent_at, transfer_evidence_path,
 *    evidence_replaced: false}`. A retry on a seller_sent transfer answers `already_sent` and
 *    keeps the original proof. The one seller_sent case that raises is a stored NULL proof with
 *    a proof supplied: "transfer already sent without evidence — use attach_transfer_evidence".
 *    Every other non-pending status raises "cannot be marked as sent from current status: …".
 *  - `attach_transfer_evidence(p_transfer_id, p_transfer_evidence_path)` returns
 *    `{outcome: 'attached' | 'already_attached', status, transfer_evidence_path, …}`; only for
 *    status seller_sent with no proof. A different proof on a row that has one is refused by the
 *    append-only guard ("transfer_evidence_path is append-only.").
 *
 * Product truth held here: success is shown only on an authoritative answer — the transfer read
 * back as sent (with the proof), or, when that read fails, the server's own reply saying so. A
 * reply and a read that disagree are "unconfirmed", never success. A thrown or timed-out call
 * only makes the outcome uncertain; the read decides. Nothing is uploaded or called for a
 * transfer that is already settled, and a sent transfer without proof is routed to the explicit
 * Add proof action rather than attached silently.
 */

export interface TransferSnapshot { status: string; evidencePath: string | null }

export interface ProofReply { outcome: string; status: string | null; path: string | null }

type RpcError = { message: string } | null;

export type MarkSentOutcome =
  | { kind: 'sent'; path: string | null }
  | { kind: 'needs_proof' }
  | { kind: 'not_pending'; status: string }
  | { kind: 'upload_failed' }
  | { kind: 'failed'; message: string }
  | { kind: 'unconfirmed' };

export interface MarkSentDeps {
  /** The transfer's status and stored proof, or null when the read failed. */
  readTransfer(): Promise<TransferSnapshot | null>;
  /** The storage path of the evidence, or null when the upload failed (the hook shows why). */
  upload(): Promise<string | null>;
  call(path: string): Promise<{ data?: unknown; error: RpcError }>;
}

export type AttachOutcome =
  | { kind: 'attached'; path: string }
  | { kind: 'has_proof'; path: string | null }
  | { kind: 'not_eligible'; status: string | null }
  | { kind: 'upload_failed' }
  | { kind: 'failed'; message: string }
  | { kind: 'unconfirmed' };

export interface AttachDeps {
  readTransfer(): Promise<TransferSnapshot | null>;
  upload(): Promise<string | null>;
  attach(path: string): Promise<{ data?: unknown; error: RpcError }>;
}

const SENT = new Set(['seller_sent', 'buyer_confirmed', 'auto_released']);
const MARK_OUTCOMES = new Set(['transitioned', 'already_sent']);
const ATTACH_OUTCOMES = new Set(['attached', 'already_attached']);

export const PROOF_LITERALS = {
  sentWithoutProof: 'transfer already sent without evidence — use attach_transfer_evidence',
  cannotMarkFrom: 'cannot be marked as sent from current status:',
  attachNotSent: 'evidence can only be attached to a sent transfer',
  appendOnly: 'transfer_evidence_path is append-only',
} as const;

export function isAlreadySentRaise(message: string | null | undefined): boolean {
  return /cannot be marked as sent from current status:\s*(seller_sent|buyer_confirmed|auto_released)/i.test(message ?? '');
}

export function isSentWithoutProofRaise(message: string | null | undefined): boolean {
  return (message ?? '').includes(PROOF_LITERALS.sentWithoutProof);
}

/** The verbs' jsonb reply, or null when it is not one. */
export function parseProofReply(data: unknown): ProofReply | null {
  if (!data || typeof data !== 'object' || Array.isArray(data)) return null;
  const d = data as Record<string, unknown>;
  if (typeof d.outcome !== 'string' || !d.outcome) return null;
  return {
    outcome: d.outcome,
    status: typeof d.status === 'string' ? d.status : null,
    path: typeof d.transfer_evidence_path === 'string' && d.transfer_evidence_path ? d.transfer_evidence_path : null,
  };
}

export const MARK_SENT_COPY = {
  unconfirmed: "We couldn't confirm this transfer was marked as sent. Pull down to refresh before trying again.",
  notPending: 'This transfer can no longer be marked as sent. Pull down to refresh to see its current status.',
  failedFallback: "Couldn't mark this transfer as sent. Try again.",
  needsProof: 'This transfer was already marked as sent, without a screenshot. You can add the screenshot below.',
  // CFT-703, A's refusal catalogue (2026-10-21) §4a: SNT-2 per status, SNT-3.
  notPendingExpired: 'This order closed before it was marked as sent.',
  notPendingDisputed: "This order is under review, so it can't be marked as sent.",
  notPendingReversed: 'This order has been closed.',
  notFound: "We couldn't find this order. Pull down to refresh.",
} as const;

export const ATTACH_COPY = {
  title: 'Add transfer proof',
  body: 'This transfer was marked as sent without a screenshot of the transfer confirmation. You can add one here.',
  cta: 'Add proof',
  added: 'The screenshot was added to this transfer.',
  hasProof: "This transfer already has a transfer screenshot. It can't be replaced.",
  notEligible: "Proof can't be added to this transfer now. Pull down to refresh to see its current status.",
  unconfirmed: "We couldn't confirm the screenshot was added. Pull down to refresh before trying again.",
  failedFallback: "Couldn't add the screenshot. Try again.",
  // PRF-3 (catalogue §4b).
  notFound: "We couldn't find this order. Pull down to refresh.",
} as const;

/** What a seller reads when the transfer is no longer pending (SNT-2, per status). */
export function notPendingCopy(status: string | null): string {
  if (status === 'expired') return MARK_SENT_COPY.notPendingExpired;
  if (status === 'disputed') return MARK_SENT_COPY.notPendingDisputed;
  if (status === 'reversed') return MARK_SENT_COPY.notPendingReversed;
  return MARK_SENT_COPY.notPending;
}

/** SNT-3 / PRF-3, matched by text: the server gives no hint or code for it (catalogue §7). */
const NOT_FOUND_RAISE = /^Transfer not found\.?$/;

/** The status named by an SNT-2 raise, or null when the message is not one. */
export function cannotMarkFromStatus(message: string | null | undefined): string | null {
  // Anchored to the raise's own opening (catalogue recipe: a message PREFIX).
  const m = /^Transfer cannot be marked as sent from current status:\s*([a-z_]+)/i.exec((message ?? '').trim());
  return m ? m[1].toLowerCase() : null;
}

/**
 * A refusal in the seller's words. The server's text is never shown (catalogue §8: it leaks status
 * enums, column, function and bucket names); the caller logs it. Unmatched → the action's generic line.
 */
export function markSentFailureCopy(message: string, fallback: string, opts: { readBackPending?: boolean } = {}): string {
  if (NOT_FOUND_RAISE.test(message.trim())) return MARK_SENT_COPY.notFound;
  // When the read-back says pending, the read-back is the authority: a raise naming another status
  // is not turned into "this order closed" (delta review nit 4).
  if (opts.readBackPending) return fallback;
  const status = cannotMarkFromStatus(message);
  if (status && !SENT.has(status)) return notPendingCopy(status);
  return fallback;
}

function attachFailureCopy(message: string): string {
  return NOT_FOUND_RAISE.test(message.trim()) ? ATTACH_COPY.notFound : ATTACH_COPY.failedFallback;
}

async function safeRead(read: () => Promise<TransferSnapshot | null>): Promise<TransferSnapshot | null> {
  try { return await read(); } catch { return null; }
}

async function safeCall(fn: () => Promise<{ data?: unknown; error: RpcError }>): Promise<{ reply: ProofReply | null; error: RpcError; uncertain: boolean }> {
  try {
    const r = await fn();
    return { reply: parseProofReply(r.data), error: r.error, uncertain: false };
  } catch {
    return { reply: null, error: null, uncertain: true };
  }
}

function sentOutcome(s: { status: string; path: string | null }): MarkSentOutcome {
  if (s.status === 'seller_sent' && s.path === null) return { kind: 'needs_proof' };
  return { kind: 'sent', path: s.path };
}

export async function runMarkSent(deps: MarkSentDeps): Promise<MarkSentOutcome> {
  const before = await safeRead(() => deps.readTransfer());
  if (before && SENT.has(before.status)) return sentOutcome({ status: before.status, path: before.evidencePath });
  if (before && before.status !== 'pending') return { kind: 'not_pending', status: before.status };
  // before === null: the read failed; the verb refuses anything it must, and the read-back settles it.

  let path: string | null = null;
  try { path = await deps.upload(); } catch { path = null; }
  if (!path) return { kind: 'upload_failed' };
  const uploaded = path;

  const { reply, error, uncertain } = await safeCall(() => deps.call(uploaded));
  if (error && isSentWithoutProofRaise(error.message)) return { kind: 'needs_proof' };

  const after = await safeRead(() => deps.readTransfer());
  if (after) {
    if (SENT.has(after.status)) return sentOutcome({ status: after.status, path: after.evidencePath });
    // CFT-703 SNT-2: the read-back is authoritative — expired, disputed, reversed (or any other
    // non-pending status) is "no longer pending", never a failure carrying the server's text.
    if (after.status !== 'pending') return { kind: 'not_pending', status: after.status };
    if (!uncertain && error && !isAlreadySentRaise(error.message)) {
      return { kind: 'failed', message: markSentFailureCopy(error.message, MARK_SENT_COPY.failedFallback, { readBackPending: true }) };
    }
    return { kind: 'unconfirmed' };   // includes a reply claiming "sent" that the read contradicts
  }
  // The read-back failed: the server's own reply is the only authoritative answer left.
  if (!error && reply && MARK_OUTCOMES.has(reply.outcome) && reply.status && SENT.has(reply.status)) {
    return sentOutcome({ status: reply.status, path: reply.path });
  }
  if (!uncertain && error && !isAlreadySentRaise(error.message)) {
    const status = cannotMarkFromStatus(error.message);
    if (status) return { kind: 'not_pending', status };   // the server named a non-sent status
    return { kind: 'failed', message: markSentFailureCopy(error.message, MARK_SENT_COPY.failedFallback) };
  }
  return { kind: 'unconfirmed' };
}

export async function runAttachEvidence(deps: AttachDeps): Promise<AttachOutcome> {
  const before = await safeRead(() => deps.readTransfer());
  if (before && before.evidencePath) return { kind: 'has_proof', path: before.evidencePath };
  if (before && before.status !== 'seller_sent') return { kind: 'not_eligible', status: before.status };

  let path: string | null = null;
  try { path = await deps.upload(); } catch { path = null; }
  if (!path) return { kind: 'upload_failed' };
  const uploaded = path;

  const { reply, error, uncertain } = await safeCall(() => deps.attach(uploaded));

  const after = await safeRead(() => deps.readTransfer());
  if (after) {
    if (after.evidencePath === uploaded) return { kind: 'attached', path: uploaded };
    if (after.evidencePath) return { kind: 'has_proof', path: after.evidencePath };
    if (after.status !== 'seller_sent') return { kind: 'not_eligible', status: after.status };
    if (!uncertain && error && !error.message.includes(PROOF_LITERALS.appendOnly)) {
      return { kind: 'failed', message: attachFailureCopy(error.message) };
    }
    return { kind: 'unconfirmed' };   // an append-only refusal the read contradicts, a claimed attach it doesn't show, or a throw
  }
  // The read-back failed.
  if (!error && reply && ATTACH_OUTCOMES.has(reply.outcome) && reply.path === uploaded) return { kind: 'attached', path: uploaded };
  if (!uncertain && error) {
    if (error.message.includes(PROOF_LITERALS.appendOnly)) return { kind: 'has_proof', path: null };
    if (error.message.includes(PROOF_LITERALS.attachNotSent)) return { kind: 'not_eligible', status: null };
    return { kind: 'failed', message: attachFailureCopy(error.message) };
  }
  return { kind: 'unconfirmed' };
}

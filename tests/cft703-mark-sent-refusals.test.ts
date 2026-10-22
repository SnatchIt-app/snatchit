/**
 * CFT-703 (A's refusal catalogue, 2026-10-21, §4): Mark as sent and Add proof never show the server's
 * text. Before this, `runMarkSent` returned `failed` with the raw message whenever the read-back was
 * not a sent status, so a seller racing a cron expiry saw "Couldn't mark as sent: Transfer cannot be
 * marked as sent from current status: expired." (SNT-2, a status enum leak, §8). "Transfer not found."
 * (SNT-3 / PRF-3) and every unmatched message were shown raw too.
 *
 * Now:
 *  - a read-back status other than pending (and not a sent status) is `not_pending`, never `failed`;
 *  - `not_pending` says the catalogue's sentence per status (expired, disputed, reversed);
 *  - SNT-3 / PRF-3 say "We couldn't find this order. Pull down to refresh.";
 *  - anything else gets the action's generic line. The raw text goes to console.warn at the call site.
 * SNT-1, PRF-1, PRF-2 and the needs_proof route are unchanged.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

import {
  ATTACH_COPY,
  MARK_SENT_COPY,
  PROOF_LITERALS,
  markSentFailureCopy,
  notPendingCopy,
  runAttachEvidence,
  runMarkSent,
  type TransferSnapshot,
} from '@/src/lib/transfer/markSent';

const P = 'u1/transfer-evidence/1.jpg';
const snap = (status: string, evidencePath: string | null = null): TransferSnapshot => ({ status, evidencePath });
const seq = (...xs: (TransferSnapshot | null)[]) => async () => (xs.length ? xs.shift()! : null);
const sntTwo = (s: string) => `Transfer cannot be marked as sent from current status: ${s}.`;

const markDeps = (read: () => Promise<TransferSnapshot | null>, msg: string | null) => ({
  readTransfer: read,
  upload: async () => P,
  call: async () => ({ error: msg === null ? null : { message: msg } }),
});
const attachDeps = (read: () => Promise<TransferSnapshot | null>, msg: string | null) => ({
  readTransfer: read,
  upload: async () => P,
  attach: async () => ({ error: msg === null ? null : { message: msg } }),
});

describe('MS1: the catalogue copy, verbatim', () => {
  it('per-status not-pending lines (SNT-2) and the not-found line (SNT-3 / PRF-3)', () => {
    expect(notPendingCopy('expired')).toBe('This order closed before it was marked as sent.');
    expect(notPendingCopy('disputed')).toBe("This order is under review, so it can't be marked as sent.");
    expect(notPendingCopy('reversed')).toBe('This order has been closed.');
    // Any other status keeps the existing line.
    expect(notPendingCopy('cancelled')).toBe(MARK_SENT_COPY.notPending);
    expect(MARK_SENT_COPY.notFound).toBe("We couldn't find this order. Pull down to refresh.");
    expect(ATTACH_COPY.notFound).toBe("We couldn't find this order. Pull down to refresh.");
  });

  it('the SNT-1 literal keeps its em dash (U+2014), byte for byte', () => {
    expect(PROOF_LITERALS.sentWithoutProof).toBe('transfer already sent without evidence — use attach_transfer_evidence');
  });

  it('markSentFailureCopy: SNT-3 → not found; SNT-2 → per status; anything else → generic, never raw', () => {
    expect(markSentFailureCopy('Transfer not found.', MARK_SENT_COPY.failedFallback)).toBe(MARK_SENT_COPY.notFound);
    expect(markSentFailureCopy(sntTwo('expired'), MARK_SENT_COPY.failedFallback)).toBe('This order closed before it was marked as sent.');
    for (const raw of ['Only the seller can mark a transfer as sent.', 'Unable to identify caller. Ensure the request is authenticated.',
      'precondition_failed: something internal', 'new row violates row-level security policy', '']) {
      expect(markSentFailureCopy(raw, MARK_SENT_COPY.failedFallback), raw).toBe(MARK_SENT_COPY.failedFallback);
    }
  });
});

describe('MS2: runMarkSent never returns raw server text', () => {
  it.each(['expired', 'disputed', 'reversed'])('read-back %s after the SNT-2 raise → not_pending, not failed', async (s) => {
    expect(await runMarkSent(markDeps(seq(snap('pending'), snap(s)), sntTwo(s)))).toEqual({ kind: 'not_pending', status: s });
  });

  it('read-back not pending with no error (the call threw) → not_pending, not unconfirmed', async () => {
    const d = { readTransfer: seq(null, snap('expired')), upload: async () => P, call: async () => { throw new Error('timeout'); } };
    expect(await runMarkSent(d)).toEqual({ kind: 'not_pending', status: 'expired' });
  });

  it('read-back failed and the raise names a non-sent status → not_pending with that status', async () => {
    expect(await runMarkSent(markDeps(seq(snap('pending'), null), sntTwo('disputed')))).toEqual({ kind: 'not_pending', status: 'disputed' });
  });

  it('SNT-3 "Transfer not found." → the not-found line, whether or not the read-back worked', async () => {
    expect(await runMarkSent(markDeps(seq(snap('pending'), snap('pending')), 'Transfer not found.'))).toEqual({ kind: 'failed', message: MARK_SENT_COPY.notFound });
    expect(await runMarkSent(markDeps(seq(null, null), 'Transfer not found.'))).toEqual({ kind: 'failed', message: MARK_SENT_COPY.notFound });
  });

  it('an unmatched message → the generic line (read-back ok or failed)', async () => {
    expect(await runMarkSent(markDeps(seq(snap('pending'), snap('pending')), 'Only the seller can mark a transfer as sent.'))).toEqual({ kind: 'failed', message: MARK_SENT_COPY.failedFallback });
    expect(await runMarkSent(markDeps(seq(null, null), 'Some new server sentence.'))).toEqual({ kind: 'failed', message: MARK_SENT_COPY.failedFallback });
  });

  it('kept: buyer_confirmed / auto_released are already sent; SNT-1 still routes to needs_proof', async () => {
    expect(await runMarkSent(markDeps(seq(snap('pending'), snap('buyer_confirmed', P)), sntTwo('buyer_confirmed')))).toEqual({ kind: 'sent', path: P });
    expect(await runMarkSent(markDeps(seq(null, null), sntTwo('auto_released')))).toEqual({ kind: 'unconfirmed' });
    expect(await runMarkSent(markDeps(seq(null, null), `precondition_failed: ${PROOF_LITERALS.sentWithoutProof}`))).toEqual({ kind: 'needs_proof' });
  });
});

describe('MS3: runAttachEvidence never returns raw server text', () => {
  it('PRF-3 "Transfer not found." → the not-found line', async () => {
    expect(await runAttachEvidence(attachDeps(seq(snap('seller_sent'), snap('seller_sent')), 'Transfer not found.'))).toEqual({ kind: 'failed', message: ATTACH_COPY.notFound });
    expect(await runAttachEvidence(attachDeps(seq(null, null), 'Transfer not found.'))).toEqual({ kind: 'failed', message: ATTACH_COPY.notFound });
  });

  it('an unmatched message → the generic line', async () => {
    expect(await runAttachEvidence(attachDeps(seq(null, null), 'Some new server sentence.'))).toEqual({ kind: 'failed', message: ATTACH_COPY.failedFallback });
  });

  it('kept: PRF-1 and PRF-2 when the read-back fails', async () => {
    expect(await runAttachEvidence(attachDeps(seq(null, null), 'transfer_evidence_path is append-only.'))).toEqual({ kind: 'has_proof', path: null });
    expect(await runAttachEvidence(attachDeps(seq(null, null), 'precondition_failed: evidence can only be attached to a sent transfer (status: disputed)'))).toEqual({ kind: 'not_eligible', status: null });
  });
});

// ── Source pins on the Send screen's handlers ─────────────────────────────────────────────────────
const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
const SEND = strip(readFileSync('app/transfer/send/[id].tsx', 'utf8'));
const body = (src: string, start: string, end: string) => {
  const i = src.indexOf(start);
  return i < 0 ? '' : src.slice(i, src.indexOf(end, i + start.length));
};
const markBody = (src: string) => body(src, 'async function handleMarkSent()', 'async function readTransfer()');
const attachBody = (src: string) => body(src, 'async function handleAttachProof()', 'const onRefresh = useCallback(');

const PIN_NOT_PENDING = "Alert.alert('Transfer updated', notPendingCopy(outcome.status));";
const PIN_WARN_MARK = "if (rpcErr) console.warn('[send] mark_transfer_sent failed:', rpcErr.message);";
const PIN_WARN_ATTACH = "if (rpcErr) console.warn('[send] attach_transfer_evidence failed:', rpcErr.message);";

/** Each pin, and the witness that removing the change fails it. */
function pinMark(src: string): void {
  const b = markBody(src);
  expect(b, 'handleMarkSent body').not.toBe('');
  expect(b).toContain(PIN_NOT_PENDING);
  expect(b).not.toContain('MARK_SENT_COPY.notPending');
  expect(b).toContain(PIN_WARN_MARK);
}
function pinAttach(src: string): void {
  const b = attachBody(src);
  expect(b, 'handleAttachProof body').not.toBe('');
  expect(b).toContain(PIN_WARN_ATTACH);
}

describe('MS4: the Send screen pins (anchored to the handler bodies)', () => {
  it('handleMarkSent shows the per-status line and logs the raw text', () => { pinMark(SEND); });
  it('handleAttachProof logs the raw text', () => { pinAttach(SEND); });

  it('negative controls: each mutation of the source fails its pin', () => {
    expect(() => pinMark(SEND.replace(PIN_NOT_PENDING, "Alert.alert('Transfer updated', MARK_SENT_COPY.notPending);"))).toThrow();
    expect(() => pinMark(SEND.replace(PIN_WARN_MARK, ''))).toThrow();
    // The warn moved out of the mark handler (into attach) must not satisfy the mark pin.
    expect(() => pinMark(SEND.replace(PIN_WARN_MARK, '').replace(PIN_WARN_ATTACH, `${PIN_WARN_ATTACH}\n${PIN_WARN_MARK}`))).toThrow();
    expect(() => pinAttach(SEND.replace(PIN_WARN_ATTACH, ''))).toThrow();
  });
});

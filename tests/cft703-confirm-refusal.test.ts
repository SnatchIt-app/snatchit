/**
 * CFT-703 (A's refusal catalogue, 2026-10-21, §5–§6): what the buyer reads when confirm-and-release
 * does not answer 2xx. The screen showed `Alert.alert('Error', body.error)` — the edge's JSON `error`
 * raw, including "Transfer cannot be confirmed from current status: disputed." (CNF-1, a status-enum
 * leak), "Internal server error" (CRE-500) and parser text echoed through CRE-401.
 *
 * The mapping is a pure function: key on the edge's `code` first (only CRE-403a has one), then the
 * HTTP status, then the CNF message prefix for a 400; anything unmatched is the generic line. The
 * caller logs the raw text. Only CRE-403a's server sentence is shown (user-facing by design).
 */
import { describe, expect, it } from 'vitest';

import {
  CONFIRM_REFUSAL_COPY,
  confirmationLanded,
  confirmFailureFromThrow,
  confirmRefusalCopy,
  readConfirmFailure,
  type ConfirmFailure,
} from '@/src/lib/transfer/confirmRefusal';

const f = (httpStatus: number | null, error: string | null = null, code: string | null = null, network = false): ConfirmFailure =>
  ({ httpStatus, error, code, network });

describe('CR1: the catalogue copy, verbatim', () => {
  it('holds every line in one place', () => {
    expect(CONFIRM_REFUSAL_COPY).toEqual({
      title: "Couldn't confirm receipt",
      notSentYet: "The seller hasn't marked this as sent yet. Pull down to refresh.",
      underReview: 'This order is under review. Pull down to refresh.',
      closed: 'This order has been closed. Pull down to refresh.',
      notFound: "We couldn't find this order. Pull down to refresh.",
      changed: 'This order changed. Pull down to refresh.',
      rateLimited: 'Please wait a few minutes and try again.',
      signIn: 'Please sign in again.',
      disputeHold: 'This order is under review, so payment is on hold.',
      unavailable: "We couldn't confirm right now. Please try again shortly.",
      notConfirmedYet: "We couldn't confirm yet. Pull down to refresh.",
      internal: "We couldn't confirm receipt. Pull down to refresh before trying again.",
      offline: 'Check your connection and try again.',
      generic: 'Something went wrong. Please try again.',
    });
  });
});

describe('CR2: confirmRefusalCopy', () => {
  const cnf1 = (s: string) => `Transfer cannot be confirmed from current status: ${s}.`;

  it('CNF-1 by status (400)', () => {
    expect(confirmRefusalCopy(f(400, cnf1('pending')))).toBe("The seller hasn't marked this as sent yet. Pull down to refresh.");
    expect(confirmRefusalCopy(f(400, cnf1('disputed')))).toBe('This order is under review. Pull down to refresh.');
    expect(confirmRefusalCopy(f(400, cnf1('expired')))).toBe('This order has been closed. Pull down to refresh.');
    expect(confirmRefusalCopy(f(400, cnf1('reversed')))).toBe('This order has been closed. Pull down to refresh.');
    expect(confirmRefusalCopy(f(400, cnf1('something_new')))).toBe(CONFIRM_REFUSAL_COPY.generic);
  });

  it('CNF-2 and CRE-400b (400)', () => {
    expect(confirmRefusalCopy(f(400, 'Transfer not found.'))).toBe("We couldn't find this order. Pull down to refresh.");
    expect(confirmRefusalCopy(f(400, 'Transfer is in unexpected state: reversed'))).toBe('This order changed. Pull down to refresh.');
  });

  it('the edge statuses', () => {
    expect(confirmRefusalCopy(f(429, 'Too many requests. Please try again later.'))).toBe('Please wait a few minutes and try again.');
    expect(confirmRefusalCopy(f(401, 'Unexpected token < in JSON at position 0'))).toBe('Please sign in again.');
    expect(confirmRefusalCopy(f(409, 'This order is under review. Payout is frozen until the dispute is resolved.'))).toBe('This order is under review, so payment is on hold.');
    expect(confirmRefusalCopy(f(503, 'Service temporarily unavailable. Please try again shortly.'))).toBe("We couldn't confirm right now. Please try again shortly.");
    expect(confirmRefusalCopy(f(500, 'Internal server error'))).toBe("We couldn't confirm receipt. Pull down to refresh before trying again.");
    expect(confirmRefusalCopy(f(404, 'Transfer not found'))).toBe("We couldn't confirm yet. Pull down to refresh.");
  });

  it('CRE-403a shows the server sentence, keyed on its code', () => {
    const msg = 'Your account deletion request is pending. Withdraw it in Settings to accept new transfers.';
    expect(confirmRefusalCopy(f(403, msg, 'account_deletion_pending'))).toBe(msg);
    expect(confirmRefusalCopy(f(403, null, 'account_deletion_pending'))).toBe(CONFIRM_REFUSAL_COPY.generic);
    // Without the code a 403 (CRE-403b, dead code) is never shown raw.
    expect(confirmRefusalCopy(f(403, 'Only the buyer can release payout'))).toBe(CONFIRM_REFUSAL_COPY.generic);
  });

  it('a network failure (§6) and anything unmatched', () => {
    expect(confirmRefusalCopy(f(null, null, null, true))).toBe('Check your connection and try again.');
    for (const x of [f(null), f(400, 'Only the buyer can confirm transfer receipt.'), f(400, 'invalid input syntax for type uuid: "x"'),
      f(400, 'Missing transfer_id'), f(418, 'teapot'), f(400, null)]) {
      expect(confirmRefusalCopy(x), JSON.stringify(x)).toBe(CONFIRM_REFUSAL_COPY.generic);
    }
  });

  it('never returns the server text except CRE-403a', () => {
    const raw = ['Transfer cannot be confirmed from current status: disputed.', 'Internal server error', 'Transfer not found',
      'Too many requests. Please try again later.', 'Invalid or expired token'];
    for (const status of [400, 401, 403, 404, 409, 429, 500, 503, null]) {
      for (const r of raw) expect(confirmRefusalCopy(f(status, r))).not.toBe(r);
    }
  });
});

describe('CR3: reading the failure', () => {
  it('a FunctionsHttpError: status and JSON body from its Response context', async () => {
    const err = { name: 'FunctionsHttpError', message: 'Edge Function returned a non-2xx status code',
      context: { status: 403, json: async () => ({ error: 'E', code: 'account_deletion_pending' }) } };
    expect(await readConfirmFailure(err, null)).toEqual(f(403, 'E', 'account_deletion_pending'));
  });

  it('an unreadable body keeps the status', async () => {
    const err = { message: 'x', context: { status: 500, json: async () => { throw new Error('bad json'); } } };
    expect(await readConfirmFailure(err, null)).toEqual(f(500));
  });

  it('a FunctionsFetchError is a network failure', async () => {
    const err = { name: 'FunctionsFetchError', message: 'Failed to send a request to the Edge Function', context: new TypeError('Network request failed') };
    expect(await readConfirmFailure(err, null)).toEqual(f(null, null, null, true));
  });

  it('no context: the body may come back as data', async () => {
    expect(await readConfirmFailure({ message: 'x' }, '{"error":"Transfer not found."}')).toEqual(f(null, 'Transfer not found.'));
  });

  it('a thrown error', () => {
    expect(confirmFailureFromThrow(new TypeError('Network request failed'))).toEqual(f(null, null, null, true));
    expect(confirmFailureFromThrow(new Error('boom'))).toEqual(f(null));
  });

  it('confirmationLanded: buyer_confirmed and auto_released only', () => {
    expect(confirmationLanded('buyer_confirmed')).toBe(true);
    expect(confirmationLanded('auto_released')).toBe(true);
    for (const s of ['pending', 'seller_sent', 'disputed', 'expired', 'reversed', '']) expect(confirmationLanded(s), s).toBe(false);
  });
});

describe('CR4: delta-review nit 3', () => {
  it('N3: a CNF-1 phrase embedded in another sentence falls to the generic line (anchored to the raise)', () => {
    const f = (error: string) => ({ httpStatus: 400, error, code: null, network: false });
    expect(confirmRefusalCopy(f('Transfer cannot be confirmed from current status: pending.'))).toBe(CONFIRM_REFUSAL_COPY.notSentYet);
    expect(confirmRefusalCopy(f('Note: Transfer cannot be confirmed from current status: pending.'))).toBe(CONFIRM_REFUSAL_COPY.generic);
  });
});

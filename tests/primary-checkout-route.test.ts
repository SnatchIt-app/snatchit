/**
 * Primary checkout — route params, the 3-D Secure return URL, and the 167 hold reply (lane C, 2026-10-26).
 *
 * Pinned:
 *   - the return URL resolves to the screen that owns THIS purchase and carries its attempt id, so the
 *     remount after a 3-D Secure challenge replays the same command key (same order, same PaymentIntent);
 *   - params are validated; a malformed session / tier / quantity / attempt is refused, never coerced;
 *   - the 167 hold reply (`public.reserve_primary_tier`, DARK) maps to a hold or a named refusal; a missing
 *     function (PGRST202) is "checkout not available yet", never a crash and never a fake hold.
 *
 * Negative controls (run by hand, each must FAIL): drop `attempt` from the return URL (R1); accept quantity
 * 0 (P2); map PGRST202 to `unavailable` (H3); drop the hold_ttl_unset / feature_disabled mapping (H5).
 */
import { describe, expect, it, vi } from 'vitest';

import { PRIMARY_CHECKOUT_COPY } from '@/src/lib/primary/checkout';
import {
  buildPrimaryReturnURL,
  HOLD_COPY,
  parseHoldReply,
  parsePrimaryCheckoutParams,
} from '@/src/lib/primary/checkoutRoute';

vi.mock('@/src/lib/supabase', () => ({ supabase: { rpc: () => { throw new Error('not used in tests'); } } }));

const SESSION = '44444444-4444-4444-8444-444444444444';
const TT = '66666666-6666-4666-8666-666666666666';
const HOLD = '77777777-7777-4777-8777-777777777777';

describe('buildPrimaryReturnURL', () => {
  it('R1: returns to the primary-checkout route for this session with tier, quantity and the attempt id', () => {
    const url = buildPrimaryReturnURL({ sessionId: SESSION, ticketTypeId: TT, quantity: 2, attemptId: 'abc123' });
    expect(url.startsWith(`snatchit://primary-checkout/${SESSION}?`)).toBe(true);
    const q = new URLSearchParams(url.split('?')[1]);
    expect(q.get('tt')).toBe(TT);
    expect(q.get('qty')).toBe('2');
    expect(q.get('attempt')).toBe('abc123');
  });
});

describe('parsePrimaryCheckoutParams', () => {
  it('P1: valid params parse; the attempt id is optional (the screen draws one if absent)', () => {
    expect(parsePrimaryCheckoutParams({ session: SESSION, tt: TT, qty: '2', attempt: 'abc123' }))
      .toEqual({ ok: true, sessionId: SESSION, ticketTypeId: TT, quantity: 2, attemptId: 'abc123' });
    expect(parsePrimaryCheckoutParams({ session: SESSION, tt: TT, qty: '1' }))
      .toEqual({ ok: true, sessionId: SESSION, ticketTypeId: TT, quantity: 1, attemptId: null });
  });

  it('P2: malformed values are refused', () => {
    expect(parsePrimaryCheckoutParams({ session: 'x', tt: TT, qty: '1' }).ok).toBe(false);
    expect(parsePrimaryCheckoutParams({ session: SESSION, tt: 'x', qty: '1' }).ok).toBe(false);
    expect(parsePrimaryCheckoutParams({ session: SESSION, tt: TT, qty: '0' }).ok).toBe(false);
    expect(parsePrimaryCheckoutParams({ session: SESSION, tt: TT, qty: '1.5' }).ok).toBe(false);
    expect(parsePrimaryCheckoutParams({ session: SESSION, tt: TT, qty: '11' }).ok).toBe(false);
    expect(parsePrimaryCheckoutParams({ session: SESSION, tt: TT, qty: '1', attempt: 'bad id!' }).ok).toBe(false);
  });
});

describe('parseHoldReply — public.reserve_primary_tier (167)', () => {
  it('H1: ok and idempotency_replay both give the hold', () => {
    expect(parseHoldReply({ data: { status: 'ok', hold_id: HOLD, expires_at: '2026-11-30T22:10:00Z', quantity: 2 }, error: null }))
      .toEqual({ ok: true, holdId: HOLD, expiresAt: '2026-11-30T22:10:00Z', quantity: 2 });
    expect(parseHoldReply({ data: { status: 'idempotency_replay', hold_id: HOLD, expires_at: null, quantity: 2 }, error: null }))
      .toEqual({ ok: true, holdId: HOLD, expiresAt: null, quantity: 2 });
  });

  it('H2: the server’s refusals are named — sold out, not on sale, hold limit, signed out', () => {
    expect(parseHoldReply({ data: null, error: { code: 'P0001', message: 'oversell_rejected: not enough inventory' } })).toEqual({ ok: false, reason: 'sold_out' });
    expect(parseHoldReply({ data: null, error: { code: 'P0001', message: 'precondition_failed: tier_not_on_sale' } })).toEqual({ ok: false, reason: 'not_on_sale' });
    expect(parseHoldReply({ data: null, error: { code: 'P0001', message: 'precondition_failed: hold_limit_reached' } })).toEqual({ ok: false, reason: 'hold_limit' });
    expect(parseHoldReply({ data: null, error: { code: '42501', message: 'x' } })).toEqual({ ok: false, reason: 'signed_out' });
  });

  it('H3: a missing function (167 not applied) is not_ready; other errors are unavailable', () => {
    expect(parseHoldReply({ data: null, error: { code: 'PGRST202', message: 'Could not find the function' } })).toEqual({ ok: false, reason: 'not_ready' });
    expect(parseHoldReply({ data: null, error: { code: 'XX000', message: 'boom' } })).toEqual({ ok: false, reason: 'unavailable' });
  });

  it('H5: before the hold config or the flag is set, ticket sales are not available yet — Back, not a retry loop', () => {
    const err = (message: string) => parseHoldReply({ data: null, error: { code: 'P0001', message } });
    expect(err('precondition_failed: hold_ttl_unset')).toEqual({ ok: false, reason: 'sales_unavailable' });
    expect(err('precondition_failed: feature_disabled')).toEqual({ ok: false, reason: 'sales_unavailable' });
    expect(HOLD_COPY.sales_unavailable).toBe(PRIMARY_CHECKOUT_COPY.refusal.sales_unavailable);
  });

  it('H6: the cap refusal stays hold_limit, and its copy is true when the cap is unseeded (0) — it never says the buyer holds tickets', () => {
    expect(parseHoldReply({ data: null, error: { code: 'P0001', message: 'precondition_failed: hold_cap_exceeded' } })).toEqual({ ok: false, reason: 'hold_limit' });
    expect(HOLD_COPY.hold_limit).not.toMatch(/you already have/i);
  });

  it('H4: a reply without a hold id is unavailable — never a fake hold', () => {
    expect(parseHoldReply({ data: { status: 'ok' }, error: null })).toEqual({ ok: false, reason: 'unavailable' });
    expect(parseHoldReply({ data: [{ status: 'ok', hold_id: HOLD, expires_at: null, quantity: 1 }], error: null }))
      .toEqual({ ok: true, holdId: HOLD, expiresAt: null, quantity: 1 });   // a one-row table reply is accepted too
  });
});

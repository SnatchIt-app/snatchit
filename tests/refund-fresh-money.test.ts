import { describe, expect, it, vi } from 'vitest';
import { postFreshRefund } from '../supabase/functions/refund-execute/fresh-money';

describe('native refund fresh money authorization', () => {
  it('waits for DB authorization before sending money', async () => {
    let release!: (value: { data: unknown; error: null }) => void;
    const gate = new Promise<{ data: unknown; error: null }>((r) => { release = r; });
    const post = vi.fn(async () => ({ id: 're_fixture' }));
    const result = postFreshRefund(() => gate, post);
    await Promise.resolve();
    expect(post).not.toHaveBeenCalled();
    release({ data: { allowed: true }, error: null });
    expect(await result).toEqual({ kind: 'posted', response: { id: 're_fixture' } });
    expect(post).toHaveBeenCalledTimes(1);
  });

  it.each(['payout_exposure', 'console_refund_exposure', 'provider_refund_exposure', 'executor_hold', 'reconcile_only'])(
    'never POSTs when the DB refuses %s', async (reason) => {
      const post = vi.fn();
      expect(await postFreshRefund(async () => ({ data: { allowed: false, reason }, error: null }), post)).toEqual({ kind: 'refused', reason });
      expect(post).not.toHaveBeenCalled();
    },
  );

  it.each([null, {}, { allowed: 'true' }, { allowed: 1 }])('fails closed on malformed verdict %j', async (data) => {
    const post = vi.fn();
    expect((await postFreshRefund(async () => ({ data, error: null }), post)).kind).toBe('refused');
    expect(post).not.toHaveBeenCalled();
  });

  it('fails closed on missing RPC and thrown transport errors', async () => {
    const post = vi.fn();
    expect((await postFreshRefund(async () => ({ data: { allowed: true }, error: { message: 'missing RPC' } }), post)).kind).toBe('refused');
    expect((await postFreshRefund(async () => { throw Error('network'); }, post)).kind).toBe('refused');
    expect(post).not.toHaveBeenCalled();
  });

  it('rechecks after awaited provider search instead of reusing an earlier verdict', async () => {
    const post = vi.fn(async () => 'created');
    let exposure = false;
    const authorize = vi.fn(async () => ({ data: { allowed: !exposure, reason: 'payout_exposure' }, error: null }));
    expect((await postFreshRefund(authorize, post)).kind).toBe('posted');
    await Promise.resolve(); // Provider search or other I/O can yield to another worker.
    exposure = true;
    expect(await postFreshRefund(authorize, post)).toEqual({ kind: 'refused', reason: 'payout_exposure' });
    expect(authorize).toHaveBeenCalledTimes(2);
    expect(post).toHaveBeenCalledTimes(1);
  });
});

import { describe, expect, it, vi } from 'vitest';
import fs from 'node:fs';
import { URL } from 'node:url';
import vm from 'node:vm';
import ts from 'typescript';
import * as executor from '../supabase/functions/refund-execute/executor';
import * as freshMoney from '../supabase/functions/refund-execute/fresh-money';

const refund = '11111111-1111-4111-8111-111111111111';
function harness(options: { allowed: boolean; found?: boolean; submitted?: boolean; afterSearch?: boolean; livemode?: boolean | null; env?: Record<string, string> }) {
  const events: string[] = [];
  const ctx = {
    refund_id: refund, payment_id: '22222222-2222-4222-8222-222222222222',
    order_id: '33333333-3333-4333-8333-333333333333', sale_id: null,
    amount_minor: 100, currency: 'USD', reason_code: 'admin_action',
    status: options.submitted ? 'submitted' : 'pending', stripe_refund_ref: options.submitted ? 're_fixture' : null,
    payment_total_minor: 11000, payment_status: 'succeeded', stripe_payment_intent_id: 'pi_fixture',
    stripe_livemode: options.livemode === undefined ? true : options.livemode, prior_non_failed_minor: 0, disputed_minor: 0,
  };
  let allowed = options.afterSearch ? true : options.allowed;
  const providerObject = { id: 're_fixture', status: 'succeeded', metadata: { refund_id: refund } };
  const stripe = vi.fn(async (path: string, init: { method: string }) => {
    events.push(`${init.method} ${path}`);
    if (init.method === 'GET' && path.startsWith('/refunds?')) {
      allowed = options.allowed;
      return { ok: true, status: 200, data: { data: options.found ? [providerObject] : [], has_more: false } };
    }
    return { ok: true, status: 200, data: providerObject };
  });
  const rpc = vi.fn(async (name: string) => {
    events.push(name);
    if (name === 'get_refund_execution_context') return { data: ctx, error: null };
    if (name === 'authorize_fresh_refund') return { data: { allowed, reason: 'payout_exposure' }, error: null };
    if (name === 'mark_refund_state') return { data: { status: 'ok' }, error: null };
    throw Error(`Unexpected RPC ${name}`);
  });
  const source = fs.readFileSync(new URL('../supabase/functions/refund-execute/index.ts', import.meta.url), 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  const module = { exports: {} as { executeOne: (...args: unknown[]) => Promise<{ outcome: string }> } };
  vm.runInNewContext(code, {
    module, exports: module.exports, console: { log() {}, warn() {}, error() {} },
    Deno: { env: { get: (name: string) => options.env?.[name] ?? 'local-fixture' } },
    require(name: string) {
      if (name.endsWith('/http/server.ts')) return { serve() {} };
      if (name.includes('supabase-js')) return { createClient() { throw Error('Unexpected client'); } };
      if (name.endsWith('sentry.ts')) return { captureException: async () => {} };
      if (name.endsWith('stripe.ts')) return { stripeFetchRaw: stripe };
      if (name === './executor.ts') return executor;
      if (name === './fresh-money.ts') return freshMoney;
      throw Error(`Unexpected import ${name}`);
    },
  });
  return { execute: (mode = 'create') => module.exports.executeOne({ rpc }, refund, 'local214', {}, mode), events, stripe, rpc };
}

describe('actual native refund edge POST seams', () => {
  it('executes a test refund only under approved server-side sandbox settings', async () => {
    const env = { SUPABASE_URL: 'https://ofaidukbieeekqaboscm.supabase.co', STRIPE_SECRET_KEY: 'sk_test_local_fixture', ALLOW_TEST_MODE_MONEY: '1' };
    const h = harness({ allowed: true, livemode: false, env });
    expect((await h.execute()).outcome).toBe('succeeded');
    expect(h.events).toContain('POST /refunds');
    const reconcile = harness({ allowed: true, livemode: false, env });
    expect((await reconcile.execute('reconcile')).outcome).toBe('succeeded');
    expect(reconcile.events).toContain('POST /refunds');
    for (const changed of [{ ALLOW_TEST_MODE_MONEY: '0' }, { STRIPE_SECRET_KEY: 'sk_live_local_fixture' }, { SUPABASE_URL: 'https://hqycwntpfoztoinemqns.supabase.co' }]) {
      const denied = harness({ allowed: true, livemode: false, env: { ...env, ...changed } });
      expect((await denied.execute()).outcome).toBe('refused');
      expect(denied.events).not.toContain('POST /refunds');
    }
    const unknown = harness({ allowed: true, livemode: null, env });
    expect((await unknown.execute()).outcome).toBe('refused');
    expect(unknown.events).not.toContain('POST /refunds');
  });

  it('authorizes an ordinary create immediately before POST', async () => {
    const h = harness({ allowed: true });
    expect((await h.execute()).outcome).toBe('succeeded');
    const index = h.events.indexOf('POST /refunds');
    expect(h.events[index - 1]).toBe('authorize_fresh_refund');
  });

  it('adopts an existing provider refund when fresh money is refused', async () => {
    const h = harness({ allowed: false, found: true });
    expect((await h.execute()).outcome).toBe('succeeded');
    expect(h.events.some((e) => e.startsWith('GET /refunds?'))).toBe(true);
    expect(h.events).not.toContain('POST /refunds');
    expect(h.events).toContain('mark_refund_state');
  });

  it('refuses search-notfound create under payout exposure', async () => {
    const h = harness({ allowed: false });
    expect((await h.execute('reconcile')).outcome).toBe('refused');
    expect(h.events.some((e) => e.startsWith('GET /refunds?'))).toBe(true);
    expect(h.events).not.toContain('POST /refunds');
  });

  it('rechecks after the awaited provider search before reconcile can POST', async () => {
    const h = harness({ allowed: false, afterSearch: true });
    expect((await h.execute('reconcile')).outcome).toBe('refused');
    const gate = h.events.indexOf('authorize_fresh_refund');
    expect(h.events[gate - 1]).toMatch(/^GET \/refunds\?/);
    expect(h.events).not.toContain('POST /refunds');
  });

  it('allows search-notfound create when the final DB gate approves', async () => {
    const h = harness({ allowed: true });
    expect((await h.execute('reconcile')).outcome).toBe('succeeded');
    const index = h.events.indexOf('POST /refunds');
    expect(h.events[index - 1]).toBe('authorize_fresh_refund');
  });

  it('fetches and syncs a known submitted refund despite opposite exposure', async () => {
    const h = harness({ allowed: false, submitted: true });
    expect((await h.execute('reconcile')).outcome).toBe('succeeded');
    expect(h.events).toContain('GET /refunds/re_fixture');
    expect(h.events).not.toContain('authorize_fresh_refund');
    expect(h.events).not.toContain('POST /refunds');
  });
});

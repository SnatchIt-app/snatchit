import { describe, expect, it, vi } from 'vitest';
import fs from 'node:fs';
import vm from 'node:vm';
import { webcrypto } from 'node:crypto';
import { URL } from 'node:url';
import ts from 'typescript';
import * as executor from '../supabase/functions/refund-execute/executor';
import * as freshMoney from '../supabase/functions/refund-execute/fresh-money';

const serviceKey = 'sb_secret_fixture_only';
function harness() {
  let handler: (req: Request) => Promise<Response>;
  const rpc = vi.fn(async () => ({ data: { refunds: [] }, error: null }));
  const provider = vi.fn(() => { throw Error('No provider call allowed'); });
  const env: Record<string, string> = {
    SUPABASE_URL: 'https://ofaidukbieeekqaboscm.supabase.co',
    SUPABASE_SERVICE_ROLE_KEY: serviceKey, SUPABASE_ANON_KEY: 'public-fixture',
    INTERNAL_CRON_SECRET: 'cron-fixture-only',
  };
  const code = ts.transpileModule(fs.readFileSync(new URL('../supabase/functions/refund-execute/index.ts', import.meta.url), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(code, {
    module, exports: module.exports, Request, Response, Headers, URL, crypto: webcrypto,
    console: { log() {}, warn() {}, error() {} },
    Deno: { env: { get: (name: string) => env[name] } },
    require(name: string) {
      if (name.endsWith('/http/server.ts')) return { serve(fn: typeof handler) { handler = fn; } };
      if (name.includes('supabase-js')) return { createClient: () => ({ rpc, auth: { getUser: async () => ({ data: { user: null }, error: null }) } }) };
      if (name.endsWith('sentry.ts')) return { captureException: async () => {} };
      if (name.endsWith('stripe.ts')) return { stripeFetchRaw: provider };
      if (name === './executor.ts') return executor;
      if (name === './fresh-money.ts') return freshMoney;
      throw Error(`Unexpected import ${name}`);
    },
  });
  return { rpc, provider, call: (headers: Record<string, string>, body: Record<string, unknown> = { action: 'sweep', limit: 1 }) =>
    handler(new Request('https://local.test/refund-execute', { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body) })) };
}

describe('actual refund machine authentication', () => {
  it('accepts the configured service secret on apikey without treating a different Bearer JWT as the secret', async () => {
    const h = harness();
    const res = await h.call({ Authorization: 'Bearer gateway-valid-jwt-fixture', apikey: serviceKey });
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ attempted: 0 });
    expect(h.rpc).toHaveBeenCalledExactlyOnceWith('claim_refunds_for_execution', { p_limit: 1, p_lease_seconds: 900 });
    expect(h.provider).not.toHaveBeenCalled();
  });
  it.each([{}, { apikey: 'public-fixture' }, { apikey: 'wrong-secret' }, { Authorization: 'Bearer user-jwt-fixture', apikey: 'public-fixture' }, { 'x-service-key': serviceKey }] as Record<string, string>[])('rejects a caller without the configured credential: %j', async (headers) => {
    const h = harness();
    expect((await h.call(headers)).status).toBe(401);
    expect(h.rpc).not.toHaveBeenCalled();
    expect(h.provider).not.toHaveBeenCalled();
  });
  it.each([serviceKey, 'cron-fixture-only'])('preserves the existing Bearer credential path', async (key) => {
    const h = harness();
    expect((await h.call({ Authorization: `Bearer ${key}` })).status).toBe(200);
    expect(h.rpc).toHaveBeenCalledTimes(1);
  });
  it('does not accept a credential smuggled in JSON', async () => {
    const h = harness();
    expect((await h.call({}, { action: 'sweep', apikey: serviceKey })).status).toBe(401);
    expect(h.rpc).not.toHaveBeenCalled();
  });
});

/**
 * Old-build safeguard (owner via A, 2026-10-15): builds 25/27 cannot show the owner proof-waiver disclosure, so
 * migration 156 refuses a bid insert or a Buy Now reservation on a waived listing unless the request carries
 * `x-snatchit-caps: proof-disclosure-v1`. RC9 shows the disclosure and must send that header on EVERY request.
 * Drives the REAL supabase-js client with a fake fetch to prove the header reaches the two guarded paths
 * (PostgREST insert into bids, RPC reserve_buy_now) and the auth endpoints. Not device evidence.
 */
import { createClient } from '@supabase/supabase-js';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { CLIENT_CAPS_HEADER, clientCapsHeaders } from '../src/config/clientCapabilities';

describe('the capability header', () => {
  it('CH1: one header, one token', () => {
    expect(CLIENT_CAPS_HEADER).toBe('x-snatchit-caps');
    expect(clientCapsHeaders).toEqual({ 'x-snatchit-caps': 'proof-disclosure-v1' });
  });

  it('CH2: supabase-js sends it on a bids insert, an RPC and an auth call', async () => {
    const seen: Array<{ path: string; caps: string | null }> = [];
    const fetchImpl: typeof fetch = async (input, init) => {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
      const h = new Headers(init?.headers);
      seen.push({ path: new URL(url).pathname, caps: h.get('x-snatchit-caps') });
      return new Response('{}', { status: 200, headers: { 'content-type': 'application/json' } });
    };
    const client = createClient('http://sandbox.test', 'anon-key', {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
      global: { headers: clientCapsHeaders, fetch: fetchImpl },
    });
    await client.from('bids').insert({ listing_id: 'l', bidder_id: 'u', amount: 10 });
    await client.rpc('reserve_buy_now', { p_listing_id: 'l', p_user_id: 'u', p_minutes: 10 });
    await client.auth.resetPasswordForEmail('x@example.com');
    const by = (p: string) => seen.find((s) => s.path.endsWith(p));
    expect(by('/rest/v1/bids')?.caps).toBe('proof-disclosure-v1');
    expect(by('/rest/v1/rpc/reserve_buy_now')?.caps).toBe('proof-disclosure-v1');
    expect(by('/auth/v1/recover')?.caps).toBe('proof-disclosure-v1');
  });

  it('CH3: the app\'s one client is built with it', () => {
    const src = readFileSync(resolve(__dirname, '..', 'src/lib/supabase.ts'), 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
    expect(src).toMatch(/createClient\(_safeSupabaseUrl, _safeSupabaseAnon, \{[\s\S]*global: \{ headers: clientCapsHeaders \},/);
  });
});

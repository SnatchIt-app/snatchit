/**
 * Credential client + owner-scoped reads (Q03–Q05, lane C, 2026-10-26).
 *
 * The network is injected (an `Invoker` for the edge function, an `AtomsReader`/`OrdersReader` for
 * the two registry-182 RPCs), so these run without Supabase. Pinned:
 *   - the edge is called with exactly `{ ticket_atom_id }` and never with a client version/key id;
 *   - a malformed atom id never reaches the network;
 *   - RPC errors map to offline / signed_out / unavailable, never to an empty list;
 *   - rows that do not have the contract shape are dropped, never guessed;
 *   - the issuance hint follows A's rule: pending order + succeeded payment = pending issuance.
 *
 * Negative controls (run by hand, each must FAIL): send `credential_version` in the body (M2);
 * map a 42501 to `{kind:'ready', atoms: []}` (R2); treat `processing` as `paid_pending` (H2).
 */
import { describe, expect, it, vi } from 'vitest';


import {
  bindOwnerFromAuthEvent,
  issuanceHint,
  mintCredential,
  readMyAtoms,
  readMyPrimaryOrders,
  type Invoker,
  type PrimaryOrderRow,
} from '@/src/lib/tickets/entitlementReads';
import { bindEntitlementOwner, readAtoms, storeAtoms } from '@/src/lib/tickets/entitlementStore';

// The module under test imports the app's Supabase client (which pulls in React Native); every
// transport here is injected, so the client is a minimal stand-in and is never called.
vi.mock('@/src/lib/supabase', () => ({
  supabase: {
    functions: { invoke: async () => { throw new Error('not used in tests'); } },
    rpc: () => { throw new Error('not used in tests'); },
    auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }) },
  },
}));

const ATOM = '11111111-1111-4111-8111-111111111111';
const SESSION = '22222222-2222-4222-8222-222222222222';
const token = `${'a'.repeat(107)}.${'b'.repeat(154)}.${'c'.repeat(86)}`;
const okBody = { token, credential_version: 1, signing_key_id: 'k', not_after: '2026-11-30T05:00:00Z', ttl_seconds: 900 };

describe('mintCredential — the edge is the only source of a code', () => {
  it('M1: calls credential-sign with exactly { ticket_atom_id } and returns the parsed credential', async () => {
    const calls: { name: string; body: unknown }[] = [];
    const invoke: Invoker = async (name, body) => { calls.push({ name, body }); return { status: 200, body: okBody }; };
    const r = await mintCredential(invoke, ATOM);
    expect(calls).toEqual([{ name: 'credential-sign', body: { ticket_atom_id: ATOM } }]);
    expect(r).toEqual({ ok: true, credential: okBody });
  });

  it('M2: the body never carries a version or key id, whatever the caller knows', async () => {
    let sent: unknown = null;
    const invoke: Invoker = async (_n, body) => { sent = body; return { status: 200, body: okBody }; };
    await mintCredential(invoke, ATOM);
    expect(Object.keys(sent as object)).toEqual(['ticket_atom_id']);
  });

  it('M3: a malformed atom id is refused locally and nothing is sent', async () => {
    let called = 0;
    const invoke: Invoker = async () => { called++; return { status: 200, body: okBody }; };
    expect(await mintCredential(invoke, 'not-a-uuid')).toEqual({ ok: false, reason: 'unavailable' });
    expect(await mintCredential(invoke, `${ATOM}/../x`)).toEqual({ ok: false, reason: 'unavailable' });
    expect(called).toBe(0);
  });

  it('M4: a thrown invoker is offline, not a code and not a crash', async () => {
    const invoke: Invoker = async () => { throw new Error('Network request failed'); };
    expect(await mintCredential(invoke, ATOM)).toEqual({ ok: false, reason: 'offline' });
  });
});

describe('readMyAtoms — owner-scoped rows or an honest failure', () => {
  const rows = [
    { ticket_atom_id: ATOM, serial_no: 1, ticket_type_id: 't', ticket_type_name: 'GA', state: 'active', resale_state: 'none', credential_version: 1, issued_at: null },
    { ticket_atom_id: 'x', serial_no: 'two', ticket_type_id: 't', ticket_type_name: 'GA', state: 'active', resale_state: 'none', credential_version: 1, issued_at: null },
  ];

  it('R1: the contract rows come back; a row without the contract shape is dropped, not guessed', async () => {
    const r = await readMyAtoms(async () => ({ data: rows, error: null }), SESSION, false);
    expect(r).toEqual({ kind: 'ready', atoms: [rows[0]] });
  });

  it('R2: auth failures are signed_out, connectivity is offline, anything else is unavailable — never an empty list', async () => {
    expect(await readMyAtoms(async () => ({ data: null, error: { code: '42501', message: 'permission denied' } }), SESSION, false)).toEqual({ kind: 'failed', failure: 'signed_out' });
    expect(await readMyAtoms(async () => ({ data: null, error: { code: '28000' } }), SESSION, false)).toEqual({ kind: 'failed', failure: 'signed_out' });
    expect(await readMyAtoms(async () => ({ data: null, error: { message: 'Network request failed' } }), SESSION, true)).toEqual({ kind: 'failed', failure: 'offline' });
    expect(await readMyAtoms(async () => ({ data: null, error: { code: 'PGRST202', message: 'function not found' } }), SESSION, false)).toEqual({ kind: 'failed', failure: 'unavailable' });
    expect(await readMyAtoms(async () => { throw new Error('boom'); }, SESSION, false)).toEqual({ kind: 'failed', failure: 'unavailable' });
  });

  it('R3: a null data with no error is unavailable, not empty', async () => {
    expect(await readMyAtoms(async () => ({ data: null, error: null }), SESSION, false)).toEqual({ kind: 'failed', failure: 'unavailable' });
  });
});

describe('issuanceHint — A’s rule, nothing more', () => {
  const order = (over: Partial<PrimaryOrderRow>): PrimaryOrderRow => ({ order_id: 'o', status: 'pending', total_minor: 1000, currency: 'usd', created_at: 'x', atoms_issued: 0, payment_state: 'succeeded', ...over });

  it('H1: pending order with succeeded payment = paid_pending; no orders = none; no read = unknown', () => {
    expect(issuanceHint([order({})])).toBe('paid_pending');
    expect(issuanceHint([])).toBe('none');
    expect(issuanceHint(null)).toBe('unknown');
  });

  it('H2: a processing payment is payment_processing, never paid_pending; failed/none payments give none', () => {
    expect(issuanceHint([order({ payment_state: 'processing' })])).toBe('payment_processing');
    expect(issuanceHint([order({ payment_state: 'failed' })])).toBe('none');
    expect(issuanceHint([order({ payment_state: 'none' })])).toBe('none');
  });

  it('H3: an issued order (atoms_issued > 0 or status issued) is none — the atoms read carries it', () => {
    expect(issuanceHint([order({ status: 'issued', atoms_issued: 2 })])).toBe('none');
  });

  it('H4: readMyPrimaryOrders returns null on any failure so the hint is unknown, not none', async () => {
    expect(await readMyPrimaryOrders(async () => ({ data: null, error: { code: 'PGRST202' } }), SESSION)).toBeNull();
    expect(await readMyPrimaryOrders(async () => ({ data: [order({})], error: null }), SESSION)).toEqual([order({})]);
  });
});

describe('bindOwnerFromAuthEvent — the cache follows the session, not the screen', () => {
  it('A1: SIGNED_OUT empties; a session binds its user; a different user replaces', () => {
    bindOwnerFromAuthEvent('SIGNED_IN', { user: { id: 'u-A' } });
    storeAtoms('u-A', SESSION, []);
    expect(readAtoms('u-A', SESSION)).toEqual([]);
    bindOwnerFromAuthEvent('TOKEN_REFRESHED', { user: { id: 'u-A' } });
    expect(readAtoms('u-A', SESSION)).toEqual([]);   // a refresh of the same user keeps the cache
    bindOwnerFromAuthEvent('SIGNED_IN', { user: { id: 'u-B' } });
    expect(readAtoms('u-A', SESSION)).toBeNull();
    bindOwnerFromAuthEvent('SIGNED_OUT', null);
    expect(readAtoms('u-B', SESSION)).toBeNull();
    bindEntitlementOwner(null);
  });
});

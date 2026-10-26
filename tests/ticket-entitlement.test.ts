/**
 * Buyer entitlement state + credential parsing + per-account cache (Q02–Q05, lane C, 2026-10-26).
 *
 * Pure logic, no React Native. The product truths pinned here:
 *   - a QR is shown ONLY for a server-issued credential on a ready atom; never synthesised;
 *   - a failed read is never "no tickets"; paid-but-unissued is "pending", not empty, not success;
 *   - another account never reads this account's atoms or tokens, and sign-out empties the cache;
 *   - a token is stale after its server TTL (monotonic, not the wall clock) or a version change.
 *
 * Negative controls (run by hand, each must FAIL): return 'ready' for a `listed` atom (D3);
 * map a failed load to 'empty' (S2); skip the owner check in `readAtoms` (C2).
 */
import { describe, expect, it } from 'vitest';

import {
  CREDENTIAL_COPY,
  ENTITLEMENT_COPY,
  canRequestCredential,
  credentialStale,
  detailState,
  entitlementDisplay,
  parseCredentialResponse,
  type MyTicketAtom,
} from '@/src/lib/tickets/entitlement';
import {
  bindEntitlementOwner,
  entitlementGeneration,
  readAtoms,
  readCredential,
  storeAtoms,
  storeCredential,
} from '@/src/lib/tickets/entitlementStore';

const atom = (over: Partial<MyTicketAtom> = {}): MyTicketAtom => ({
  ticket_atom_id: '11111111-1111-4111-8111-111111111111',
  serial_no: 1,
  ticket_type_id: 'tt-1',
  ticket_type_name: 'GA',
  state: 'active',
  resale_state: 'none',
  credential_version: 1,
  issued_at: '2026-11-01T00:00:00Z',
  ...over,
});

const token = (n = 349) => {
  const seg = (k: number) => 'a'.repeat(k);
  return `${seg(Math.floor(n * 0.3))}.${seg(Math.floor(n * 0.45))}.${seg(n - Math.floor(n * 0.3) - Math.floor(n * 0.45) - 2)}`;
};

describe('entitlementDisplay — the atom facts decide, never the client', () => {
  it('D1: issued and active atoms with no resale hold are ready for a code', () => {
    expect(entitlementDisplay(atom({ state: 'issued' }))).toBe('ready');
    expect(entitlementDisplay(atom({ state: 'active' }))).toBe('ready');
    expect(canRequestCredential('ready')).toBe(true);
  });

  it('D2: scanned is used, voided is revoked, expired is expired — none can request a code', () => {
    expect(entitlementDisplay(atom({ state: 'scanned' }))).toBe('used');
    expect(entitlementDisplay(atom({ state: 'voided' }))).toBe('revoked');
    expect(entitlementDisplay(atom({ state: 'expired' }))).toBe('expired');
    for (const d of ['used', 'revoked', 'expired', 'held', 'unknown'] as const) expect(canRequestCredential(d)).toBe(false);
  });

  it('D3: a live atom that is listed, locked or on a refund/dispute hold is held, not ready', () => {
    for (const r of ['listed', 'locked', 'refund_hold', 'dispute_hold'] as const) {
      expect(entitlementDisplay(atom({ resale_state: r })), r).toBe('held');
    }
  });

  it('D4: a state the client does not know is unknown, never ready', () => {
    expect(entitlementDisplay({ state: 'minted' as never, resale_state: 'none' })).toBe('unknown');
    expect(entitlementDisplay({ state: 'active', resale_state: 'frozen' as never })).toBe('unknown');
  });

  it('D5: copy never claims more than the state: no "valid"/"admitted" words outside ready, and ready says ID is still checked', () => {
    expect(ENTITLEMENT_COPY.ready.body).toMatch(/ID/);
    for (const k of ['used', 'revoked', 'expired', 'held', 'unknown'] as const) {
      expect(ENTITLEMENT_COPY[k].badge.toLowerCase()).not.toMatch(/ready|valid|admit/);
    }
    expect(ENTITLEMENT_COPY.unknown.body.toLowerCase()).not.toMatch(/no tickets/);
  });
});

describe('detailState — a failed or inconsistent read is never "no tickets"', () => {
  it('S1: loading and failures pass through unchanged', () => {
    expect(detailState({ kind: 'loading' }, 'unknown', 2)).toEqual({ kind: 'loading' });
    expect(detailState({ kind: 'failed', failure: 'offline' }, 'unknown', 2)).toEqual({ kind: 'failed', failure: 'offline' });
    expect(detailState({ kind: 'failed', failure: 'signed_out' }, 'paid_pending', 0)).toEqual({ kind: 'failed', failure: 'signed_out' });
  });

  it('S2: atoms present → atoms; a group that says 2 but a read of 0 is inconsistent, not empty', () => {
    const a = [atom(), atom({ serial_no: 2, ticket_atom_id: '22222222-2222-4222-8222-222222222222' })];
    expect(detailState({ kind: 'ready', atoms: a }, 'unknown', 2)).toEqual({ kind: 'atoms', atoms: a });
    expect(detailState({ kind: 'ready', atoms: [] }, 'unknown', 2)).toEqual({ kind: 'inconsistent' });
  });

  it('S3: paid but not yet issued is pending issuance; a processing payment is its own state — neither is empty or a code', () => {
    expect(detailState({ kind: 'ready', atoms: [] }, 'paid_pending', 0)).toEqual({ kind: 'pending_issuance' });
    expect(detailState({ kind: 'ready', atoms: [] }, 'payment_processing', 0)).toEqual({ kind: 'payment_processing' });
  });

  it('S4: empty only when nothing is expected and nothing is pending', () => {
    expect(detailState({ kind: 'ready', atoms: [] }, 'none', 0)).toEqual({ kind: 'empty' });
    expect(detailState({ kind: 'ready', atoms: [] }, 'unknown', 0)).toEqual({ kind: 'empty' });
  });
});

describe('parseCredentialResponse — only a well-formed server token becomes a code', () => {
  it('P1: a 200 with the documented body is ready, token kept opaque', () => {
    const t = token();
    const r = parseCredentialResponse(200, { token: t, credential_version: 3, signing_key_id: 'k', not_after: '2026-11-30T05:00:00Z', ttl_seconds: 900 });
    expect(r).toEqual({ ok: true, credential: { token: t, credential_version: 3, signing_key_id: 'k', not_after: '2026-11-30T05:00:00Z', ttl_seconds: 900 } });
  });

  it('P2: the documented refusals map to their reasons; raw server text is never surfaced', () => {
    expect(parseCredentialResponse(403, { error: 'You do not own this ticket.', code: 'not_owner' })).toEqual({ ok: false, reason: 'not_owner' });
    expect(parseCredentialResponse(409, { error: 'x', code: 'atom_terminal' })).toEqual({ ok: false, reason: 'atom_terminal' });
    expect(parseCredentialResponse(503, { error: 'x', code: 'signing_key_unavailable' })).toEqual({ ok: false, reason: 'signing_unavailable' });
    expect(parseCredentialResponse(500, { error: 'x', code: 'signing_unhealthy' })).toEqual({ ok: false, reason: 'signing_unavailable' });
    expect(parseCredentialResponse(429, { error: 'x' })).toEqual({ ok: false, reason: 'rate_limited' });
    expect(parseCredentialResponse(401, { error: 'x' })).toEqual({ ok: false, reason: 'signed_out' });
    expect(parseCredentialResponse(null, undefined)).toEqual({ ok: false, reason: 'offline' });
    expect(parseCredentialResponse(500, { error: 'An unexpected error occurred.' })).toEqual({ ok: false, reason: 'unavailable' });
    for (const k of Object.keys(CREDENTIAL_COPY) as (keyof typeof CREDENTIAL_COPY)[]) {
      expect(CREDENTIAL_COPY[k].toLowerCase()).not.toMatch(/no tickets|you do not own/);
    }
  });

  it('P3: a 200 whose token is not a 3-segment base64url string under 8192 chars is unavailable — never drawn', () => {
    const base = { credential_version: 1, signing_key_id: 'k', not_after: '2026-11-30T05:00:00Z', ttl_seconds: 900 };
    expect(parseCredentialResponse(200, { ...base, token: 'only.two' })).toEqual({ ok: false, reason: 'unavailable' });
    expect(parseCredentialResponse(200, { ...base, token: 'a.b=.c' })).toEqual({ ok: false, reason: 'unavailable' });
    expect(parseCredentialResponse(200, { ...base, token: `${'a'.repeat(8000)}.${'b'.repeat(200)}.${'c'.repeat(100)}` })).toEqual({ ok: false, reason: 'unavailable' });
    expect(parseCredentialResponse(200, { ...base, token: 42 })).toEqual({ ok: false, reason: 'unavailable' });
    expect(parseCredentialResponse(200, { token: token(), credential_version: '1', signing_key_id: 'k', not_after: 'x', ttl_seconds: 900 })).toEqual({ ok: false, reason: 'unavailable' });
  });

  it('P4: a token is stale after its server TTL (monotonic ms) or when the atom version moved on', () => {
    const ready = { kind: 'ready' as const, credential: { token: token(), credential_version: 2, signing_key_id: 'k', not_after: 'x', ttl_seconds: 600 }, receivedAtMs: 1_000 };
    expect(credentialStale(ready, 1_000 + 599_999, 2)).toBe(false);
    expect(credentialStale(ready, 1_000 + 600_000, 2)).toBe(true);
    expect(credentialStale(ready, 1_000, 3)).toBe(true);
    expect(credentialStale({ kind: 'idle' }, 0, 2)).toBe(false);
  });
});

describe('entitlementStore — one account, memory only, emptied on any owner change', () => {
  const SESSION = 'sess-1';

  it('C1: the bound owner reads back its atoms and credentials', () => {
    bindEntitlementOwner('u-A');
    storeAtoms('u-A', SESSION, [atom()]);
    storeCredential('u-A', atom().ticket_atom_id, { token: token(), credential_version: 1, signing_key_id: 'k', not_after: 'x', ttl_seconds: 900 }, 5);
    expect(readAtoms('u-A', SESSION)?.length).toBe(1);
    expect(readCredential('u-A', atom().ticket_atom_id)?.credential.credential_version).toBe(1);
  });

  it('C2: another account reads nothing, and a write for a non-owner is dropped', () => {
    bindEntitlementOwner('u-A');
    storeAtoms('u-A', SESSION, [atom()]);
    expect(readAtoms('u-B', SESSION)).toBeNull();
    expect(readCredential('u-B', atom().ticket_atom_id)).toBeNull();
    storeAtoms('u-B', SESSION, [atom(), atom()]);
    expect(readAtoms('u-A', SESSION)?.length).toBe(1);
  });

  it('C3: sign-out empties everything and bumps the generation; a late write for the old owner is dropped', () => {
    bindEntitlementOwner('u-A');
    storeAtoms('u-A', SESSION, [atom()]);
    const g = entitlementGeneration();
    bindEntitlementOwner(null);
    expect(entitlementGeneration()).toBe(g + 1);
    storeAtoms('u-A', SESSION, [atom()]);   // late result from the signed-out account
    bindEntitlementOwner('u-A');
    expect(readAtoms('u-A', SESSION)).toBeNull();
  });

  it('C4: switching accounts empties the previous account; nothing of A is visible to B', () => {
    bindEntitlementOwner('u-A');
    storeAtoms('u-A', SESSION, [atom()]);
    storeCredential('u-A', atom().ticket_atom_id, { token: token(), credential_version: 1, signing_key_id: 'k', not_after: 'x', ttl_seconds: 900 }, 5);
    bindEntitlementOwner('u-B');
    expect(readAtoms('u-B', SESSION)).toBeNull();
    expect(readCredential('u-B', atom().ticket_atom_id)).toBeNull();
    expect(readAtoms('u-A', SESSION)).toBeNull();
  });
});

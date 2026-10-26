/**
 * Primary discovery + session detail (CONTRACTS C1; D's 182 `list_primary_sessions_on_sale` and
 * `get_primary_session`, PR #170, DARK until applied). Pure parsing and display rules.
 *
 * Pinned:
 *   - rows outside the contract shape are dropped, never guessed;
 *   - 0 rows from get_primary_session is "not available" (draft/announced/cancelled/unknown — no
 *     existence leak), distinct from a failed read;
 *   - tier status says only what the server said: on sale now / sold out / not on sale yet / sales ended;
 *     no availability counts (no invented scarcity);
 *   - A's all-in rule (US live-event ticket pricing): a tier shows ONLY the server's `all_in_price_minor`
 *     (face + buyer fee, server rounding). Face value is never shown as the price. While 182 does not
 *     carry it, or the fee is unset (null), the tier shows no price and is not purchasable;
 *   - times come from the session's `*_local` strings and named venue zone (A's rule).
 *
 * Negative controls (run by hand, each must FAIL): treat `remaining: 0` with `on_sale_now: true`
 * as 'on_sale' (T2); return { kind: 'failed' } for 0 rows (D2); render price_minor 2000 as "$2,000" (T5).
 */
import { describe, expect, it, vi } from 'vitest';

import {
  DISCOVERY_COPY,
  parseDiscoveryRows,
  parsePrimarySession,
  readPrimarySessionDetail,
  tierLine,
  type PrimaryTier,
} from '@/src/lib/primary/discovery';

// The module under test imports the app's Supabase client (React Native); every transport here is
// injected, so the client is a minimal stand-in and is never called.
vi.mock('@/src/lib/supabase', () => ({
  supabase: {
    rpc: () => { throw new Error('not used in tests'); },
    functions: { invoke: async () => { throw new Error('not used in tests'); } },
    auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }) },
  },
}));

const SESSION = '44444444-4444-4444-8444-444444444444';
const EVENT = '55555555-5555-4555-8555-555555555555';

const listRow = (over: Record<string, unknown> = {}) => ({
  event_id: EVENT, session_id: SESSION, title: 'Snatch It Pop-Up', venue_name: 'Venue TBA', neighborhood: 'Wynwood',
  starts_at: '2026-12-01T04:00:00+00:00', doors_at: '2026-12-01T03:00:00+00:00', age_restriction: '21_plus', status: 'on_sale', ...over,
});

const tier = (over: Partial<PrimaryTier> = {}): PrimaryTier => ({
  ticket_type_id: '66666666-6666-4666-8666-666666666666', name: 'GA', price_minor: 2000, currency: 'USD', visibility: 'public',
  display_rank: 1, sale_starts_at: null, sale_ends_at: null, on_sale_now: true, remaining: 40, all_in_price_minor: 2200, ...over,
});

const sessionRow = (over: Record<string, unknown> = {}) => ({
  session: {
    session_id: SESSION, event_id: EVENT, session_label: null, starts_at: '2026-12-01T04:00:00+00:00', ends_at: '2026-12-01T09:00:00+00:00',
    doors_at: '2026-12-01T03:00:00+00:00', status: 'scheduled', timezone: 'America/New_York',
    starts_at_local: '2026-11-30 23:00', ends_at_local: '2026-12-01 04:00', doors_at_local: '2026-11-30 22:00',
  },
  event: { event_id: EVENT, title: 'Snatch It Pop-Up', description: 'House music, two DJs.', hero_image_ref: null, category: 'nightlife', genre_tags: ['house'], status: 'on_sale', age_restriction: '21_plus' },
  venue: { venue_id: 'v', name: 'Venue TBA', neighborhood: 'Wynwood', address: null, timezone: 'America/New_York' },
  ticket_types: [tier({ display_rank: 2, name: 'Final GA' }), tier({ display_rank: 1, name: 'Early GA' })],
  ...over,
});

describe('parseDiscoveryRows', () => {
  it('D1: contract rows pass; a row missing a field or with a bad id is dropped', () => {
    const rows = parseDiscoveryRows([listRow(), listRow({ session_id: 'nope' }), { title: 'x' }]) ?? [];
    expect(rows).toHaveLength(1);
    expect(rows[0].sessionId).toBe(SESSION);
    expect(rows[0].ageRestriction).toBe('21_plus');
  });

  it('D1b: a non-array answer is not a list', () => {
    expect(parseDiscoveryRows(null)).toBeNull();
    expect(parseDiscoveryRows({})).toBeNull();
  });
});

describe('parsePrimarySession / readPrimarySessionDetail', () => {
  it('D2: a contract row parses, tiers are ordered by display_rank; 0 rows is not_available (not a failure)', async () => {
    const s = parsePrimarySession(sessionRow());
    expect(s?.facts.title).toBe('Snatch It Pop-Up');
    expect(s?.facts.startsAtLocal).toBe('2026-11-30 23:00');
    expect(s?.tiers.map((t) => t.name)).toEqual(['Early GA', 'Final GA']);
    expect(await readPrimarySessionDetail(async () => ({ data: [], error: null }), SESSION, false)).toEqual({ kind: 'not_available' });
  });

  it('D3: errors are offline / unavailable, never not_available', async () => {
    expect(await readPrimarySessionDetail(async () => ({ data: null, error: { message: 'Network request failed' } }), SESSION, true)).toEqual({ kind: 'failed', failure: 'offline' });
    expect(await readPrimarySessionDetail(async () => ({ data: null, error: { code: 'PGRST202' } }), SESSION, false)).toEqual({ kind: 'failed', failure: 'unavailable' });
    expect(await readPrimarySessionDetail(async () => { throw new Error('x'); }, SESSION, false)).toEqual({ kind: 'failed', failure: 'unavailable' });
  });

  it('D4: a tier without the contract shape is dropped; a session without event/session objects is unavailable', async () => {
    const s = parsePrimarySession(sessionRow({ ticket_types: [tier(), { name: 'broken' }] }));
    expect(s?.tiers).toHaveLength(1);
    expect(await readPrimarySessionDetail(async () => ({ data: [{ session: null }], error: null }), SESSION, false)).toEqual({ kind: 'failed', failure: 'unavailable' });
  });

  it('D5: a malformed session id never reaches the network', async () => {
    let called = 0;
    expect(await readPrimarySessionDetail(async () => { called++; return { data: [], error: null }; }, 'nope', false)).toEqual({ kind: 'not_available' });
    expect(called).toBe(0);
  });
});

describe('tierLine — what the server said, nothing more', () => {
  const nowMs = Date.parse('2026-11-10T12:00:00Z');

  it('T1: on sale now with stock reads "On sale" and the ALL-IN price from the server', () => {
    expect(tierLine(tier(), nowMs)).toEqual({ name: 'GA', price: '$22.00', status: 'On sale', available: true });
  });

  it('T2: remaining 0 is "Sold out" even if the window is open; no counts are shown', () => {
    expect(tierLine(tier({ remaining: 0 }), nowMs)).toMatchObject({ status: 'Sold out', available: false });
    expect(tierLine(tier({ remaining: 3 }), nowMs).status).not.toMatch(/\d/);
  });

  it('T3: not on sale yet / sales ended come from the window the server sent, decided by on_sale_now first', () => {
    expect(tierLine(tier({ on_sale_now: false, sale_starts_at: '2026-11-20T15:00:00Z' }), nowMs)).toMatchObject({ status: 'Not on sale yet', available: false });
    expect(tierLine(tier({ on_sale_now: false, sale_ends_at: '2026-11-01T00:00:00Z' }), nowMs)).toMatchObject({ status: 'Sales ended', available: false });
    expect(tierLine(tier({ on_sale_now: false }), nowMs)).toMatchObject({ status: 'Not on sale', available: false });
  });

  it('T4: the device clock never puts a tier on sale — on_sale_now false wins even inside its window', () => {
    expect(tierLine(tier({ on_sale_now: false, sale_starts_at: '2026-11-01T00:00:00Z', sale_ends_at: '2026-12-01T00:00:00Z' }), nowMs).available).toBe(false);
  });

  it('T5: the face price is never the price; all-in is integer cents in USD, anything else shows no price', () => {
    expect(tierLine(tier({ price_minor: 2000, all_in_price_minor: 2200 }), nowMs).price).toBe('$22.00');
    expect(tierLine(tier({ all_in_price_minor: 123456 }), nowMs).price).toBe('$1,234.56');
    expect(tierLine(tier({ currency: 'EUR' }), nowMs).price).toBeNull();
    expect(tierLine(tier({ all_in_price_minor: 19.99 as never }), nowMs).price).toBeNull();
    expect(tierLine(tier({ all_in_price_minor: 2200 }), nowMs).price).not.toBe('$20.00');
  });

  it('T5b: no all-in from the server (field absent, or null while the fee is unset) → no price and not on sale yet, even inside the window', () => {
    const absent = tier();
    delete (absent as Partial<PrimaryTier>).all_in_price_minor;
    expect(tierLine(absent, nowMs)).toEqual({ name: 'GA', price: null, status: 'Not on sale yet', available: false });
    expect(tierLine(tier({ all_in_price_minor: null }), nowMs)).toEqual({ name: 'GA', price: null, status: 'Not on sale yet', available: false });
  });

  it('T6: the price note says the figure includes all fees; it never promises a price that is not shown', () => {
    expect(DISCOVERY_COPY.priceNote).toBe('Prices include all fees.');
});
});

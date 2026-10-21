/**
 * Seller "one clear next action" (item 39 / CFT-408) — the My Listings surface.
 *
 * The rule lives in src/lib/seller/nextAction.ts (tests/seller-next-action.test.ts). This file holds
 * the two consumers to it:
 *  - app/my-listings.tsx reads expires_at and transfer_evidence_path with the transfer status
 *    (both deployed columns, seller-readable under 0550's table grant and 070's seller_id RLS), hands
 *    each row the helper's result, and opens the order for the send and proof actions;
 *  - src/components/SellerListingCard.tsx renders that ONE line where "Action needed — send the
 *    tickets" was, and says it to VoiceOver as part of the row.
 *
 * The REAL screen and card run through the hook dispatcher with the network reads under test
 * control. Not a device result.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { findElement, HookHost, type Element } from './helpers/nav-stack-harness';

const h = vi.hoisted(() => ({
  listings: [] as Record<string, unknown>[],
  transfers: [] as Record<string, unknown>[],
  selects: [] as { table: string; cols: string }[],
  pushes: [] as string[],
}));

vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return {
    useTheme: () => ({ scheme: 'dark', palette: dark }),
    useAppearancePreference: () => ({ preference: 'system', setPreference: () => {} }),
  };
});
vi.mock('react-native', () => ({
  Alert: { alert: () => {} },
  FlatList: 'FlatList', Pressable: 'Pressable', RefreshControl: 'RefreshControl', ScrollView: 'ScrollView',
  Text: 'Text', View: 'View', StyleSheet: { create: <T,>(s: T) => s, hairlineWidth: 1 },
}));
vi.mock('expo-image', () => ({ Image: 'Image' }));
vi.mock('expo-router', () => ({
  router: { push: (href: string) => { h.pushes.push(href); }, back: () => {} },
  useLocalSearchParams: () => ({}),
}));
vi.mock('@react-navigation/native', () => ({ useFocusEffect: () => {} }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: { id: 'seller-1' }, session: { user: { id: 'seller-1' } } }) }));
vi.mock('@/src/hooks/useNetworkStatus', () => ({ useNetworkStatus: () => ({ isOffline: false }), isNetworkError: () => false }));
vi.mock('@/src/components/ScreenState', () => ({ default: 'ScreenState' }));
vi.mock('@/src/components/ui', () => ({
  Chip: 'Chip', EmptyState: 'EmptyState', Skeleton: 'Skeleton', Spinner: 'Spinner', Button: 'Button',
  Tappable: 'Tappable', Badge: 'Badge', IconButton: 'IconButton',
}));
vi.mock('@/src/lib/nav/navInsets', () => ({ useDockClearance: () => 0, useTopInset: () => 0 }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3, AMOUNT_MIN_FONT_SCALE: 0.6 }));
vi.mock('@/src/components/media/EventMedia', () => ({ EventMedia: 'EventMedia' }));
vi.mock('@/src/components/VerifiedSellerBadge', () => ({ default: 'VerifiedSellerBadge' }));
vi.mock('@/src/lib/supabase', () => {
  const table = (name: string) => {
    const q: Record<string, unknown> = {};
    q.select = (cols: string) => { h.selects.push({ table: name, cols }); return q; };
    for (const m of ['order', 'limit', 'in', 'neq', 'or', 'gte', 'lte', 'eq', 'maybeSingle', 'single']) q[m] = () => q;
    q.then = (ok: (v: unknown) => unknown) =>
      Promise.resolve({ data: name === 'listings' ? h.listings : name === 'transfers' ? h.transfers : [], error: null }).then(ok);
    return q;
  };
  return {
    supabase: {
      from: (name: string) => table(name),
      auth: { getUser: async () => ({ data: { user: { id: 'seller-1' } } }) },
      storage: { from: () => ({ remove: async () => ({ error: null }) }) },
      rpc: () => Promise.resolve({ error: null }),
    },
  };
});

const ROOT = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(ROOT, rel), 'utf8');
const code = (rel: string) => read(rel).replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

const flush = async () => { for (let i = 0; i < 6; i++) await new Promise((r) => setImmediate(r)); };

const FUTURE = new Date(Date.now() + 6 * 3_600_000).toISOString();
const PAST = new Date(Date.now() - 3_600_000).toISOString();

const listing = (id: string, extra: Record<string, unknown> = {}) => ({
  id, event_name: `Event ${id}`, venue: 'Club Device', status: 'sold', auction_status: 'ended',
  bid_count: 2, current_bid: 80, starting_bid: 50, ends_at: '2026-10-01T00:00:00Z', sold_at: '2026-10-01T00:00:00Z',
  cover_image_path: null, seller_id: 'seller-1', created_at: '2026-09-01T00:00:00Z', event_date: '2026-11-08',
  event_time: '21:00', ticket_type: 'GA', neighborhood: 'Wynwood', winner_user_id: 'buyer-1', ...extra,
});
const transfer = (id: string, listingId: string, status: string, extra: Record<string, unknown> = {}) => ({
  id, listing_id: listingId, status, expires_at: FUTURE, transfer_evidence_path: null, ...extra,
});

async function mountMyListings(): Promise<HookHost> {
  const mod = await import('@/app/my-listings');
  const Screen = (mod.default ?? mod) as () => unknown;
  const host = new HookHost(() => Screen(), new Map());
  host.mount();
  await flush();
  host.flush();
  return host;
}

function list(host: HookHost): Element {
  return findElement(host.output, (el) => el.type === 'FlatList') as Element;
}

/** The props the screen hands each visible row, keyed by listing id. */
function rows(host: HookHost): Map<string, Record<string, unknown>> {
  const fl = list(host);
  const data = (fl.props.data ?? []) as { id: string }[];
  const render = fl.props.renderItem as (a: { item: unknown }) => Element;
  return new Map(data.map((item) => [item.id, render({ item }).props]));
}

/** Every string rendered inside a Text element. */
function texts(node: unknown, out: string[] = []): string[] {
  if (Array.isArray(node)) { for (const n of node) texts(n, out); return out; }
  if (!node || typeof node !== 'object' || !('props' in node)) return out;
  const el = node as Element;
  if (el.type === 'Text') {
    const kids = ([] as unknown[]).concat(el.props.children as unknown);
    const s = kids.filter((k) => typeof k === 'string' || typeof k === 'number').join('');
    if (s) out.push(s);
  }
  texts(el.props.children, out);
  return out;
}

/** Every column the migrations chain ever gives `public.transfers` (as order-select-schema does for listings). */
function transfersColumnsFromMigrations(): Set<string> {
  const cols = new Set<string>();
  const dir = resolve(ROOT, 'supabase/migrations');
  for (const f of readdirSync(dir)) {
    if (!f.endsWith('.sql')) continue;
    const sql = readFileSync(join(dir, f), 'utf8');
    const create = sql.match(/create\s+table[^(]*\btransfers\b[^(]*\(/i);
    if (create) {
      let depth = 1;
      let i = (create.index ?? 0) + create[0].length;
      const start = i;
      while (i < sql.length && depth > 0) {
        if (sql[i] === '(') depth++;
        if (sql[i] === ')') depth--;
        i++;
      }
      const body = sql.slice(start, i - 1).replace(/--[^\n]*/g, '');
      for (const rawLine of body.split(/,(?![^(]*\))/)) {
        const m = rawLine.trim().match(/^"?([a-z_][a-z0-9_]*)"?\s/i);
        const kw = m?.[1]?.toLowerCase();
        if (m && kw && !['primary', 'unique', 'constraint', 'check', 'foreign', 'like'].includes(kw)) cols.add(kw);
      }
    }
    // ALTER TABLE [IF EXISTS] [ONLY] [public.]transfers ... — one statement can carry many ADD COLUMNs (011).
    for (const stmt of sql.matchAll(/alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(?:public\.)?"?transfers"?\s[^;]*;/gis)) {
      for (const m of stmt[0].matchAll(/add\s+column\s+(?:if\s+not\s+exists\s+)?"?([a-z_][a-z0-9_]*)"?/gi)) {
        cols.add(m[1].toLowerCase());
      }
    }
  }
  return cols;
}

beforeEach(() => {
  h.listings = []; h.transfers = []; h.selects.length = 0; h.pushes.length = 0;
  vi.resetModules();
});

describe('My Listings reads the two deadline/proof facts with the status', () => {
  it('SA1: the transfers select adds expires_at and transfer_evidence_path — every column exists in the schema', async () => {
    h.listings = [listing('l-1')];
    await mountMyListings();
    const tx = h.selects.find((s) => s.table === 'transfers');
    expect(tx, 'the screen must still read transfers').toBeTruthy();
    const cols = tx!.cols.split(',').map((c) => c.trim()).filter(Boolean);
    expect(cols).toEqual(expect.arrayContaining(['id', 'listing_id', 'status', 'expires_at', 'transfer_evidence_path']));

    const schema = transfersColumnsFromMigrations();
    // Witness: the extractor sees the real table and can tell a fake column from a real one.
    expect(schema.size).toBeGreaterThan(10);
    expect(schema.has('not_a_column')).toBe(false);
    // ...and sees a column added by a LATER clause of a multi-column ALTER (011), not only the first.
    expect(schema.has('dispute_resolved_by')).toBe(true);
    // PostgREST rejects the WHOLE read on one missing column, so each one is checked.
    for (const c of cols) expect(schema.has(c), `transfers.${c} is selected but no migration creates it`).toBe(true);
  });

  it('SA2: no buyer contact, dispute or payout-risk column is read for the list', async () => {
    h.listings = [listing('l-1')];
    await mountMyListings();
    const cols = h.selects.find((s) => s.table === 'transfers')!.cols;
    for (const pii of ['delivery_email', 'delivery_phone', 'dispute_notes', 'dispute_evidence_path', 'payout_risk_tier', 'payout_reason_codes', '*']) {
      expect(cols, pii).not.toContain(pii);
    }
  });
});

describe('each row gets exactly the helper\'s one action', () => {
  beforeEach(() => {
    h.listings = [
      listing('l-send'), listing('l-late'), listing('l-proof'), listing('l-proofed'),
      listing('l-expired'), listing('l-disputed'), listing('l-reversed'), listing('l-nodate'),
    ];
    h.transfers = [
      transfer('t-send', 'l-send', 'pending'),
      transfer('t-late', 'l-late', 'pending', { expires_at: PAST }),
      transfer('t-proof', 'l-proof', 'seller_sent'),
      transfer('t-proofed', 'l-proofed', 'seller_sent', { transfer_evidence_path: 'seller-1/t-proofed/proof.jpg' }),
      transfer('t-expired', 'l-expired', 'expired', { expires_at: PAST }),
      transfer('t-disputed', 'l-disputed', 'disputed'),
      transfer('t-reversed', 'l-reversed', 'reversed'),
      transfer('t-nodate', 'l-nodate', 'pending', { expires_at: null }),
    ];
  });

  it('SA3: send / window-passed / proof / do-not-send / nothing — by server status first', async () => {
    const { sellerNextAction } = await import('@/src/lib/seller/nextAction');
    const host = await mountMyListings();
    const r = rows(host);
    const kind = (id: string) => (r.get(id)!.nextAction as { kind: string } | null | undefined)?.kind ?? null;
    expect(kind('l-send')).toBe('send_by');
    expect(kind('l-late')).toBe('window_passed');
    expect(kind('l-proof')).toBe('add_proof');
    expect(kind('l-proofed')).toBeNull();
    expect(kind('l-expired')).toBe('do_not_send');
    expect(kind('l-disputed')).toBeNull();
    expect(kind('l-reversed')).toBeNull();
    expect(kind('l-nodate')).toBe('send');
    // The row's line is the helper's line, not a second copy of the rule.
    const send = r.get('l-send')!.nextAction as { line: string };
    expect(send.line).toBe(sellerNextAction({ listingStatus: 'sold', transfer: { status: 'pending', expires_at: FUTURE } }, Date.now())?.line);
    // The old boolean prop is gone: one source for the line.
    expect(r.get('l-send')!.needsTicketSend).toBeUndefined();
  });

  it('SA4: the send and proof actions open the order; closed and finished rows open the listing', async () => {
    const host = await mountMyListings();
    const r = rows(host);
    const open = (id: string) => { h.pushes.length = 0; (r.get(id)!.onPress as () => void)(); return h.pushes[0]; };
    expect(open('l-send')).toBe('/transfer/send/t-send');
    expect(open('l-late')).toBe('/transfer/send/t-late');     // the order screen does the fresh read
    expect(open('l-nodate')).toBe('/transfer/send/t-nodate');
    expect(open('l-proof')).toBe('/transfer/send/t-proof');   // where the Add proof button lives
    expect(open('l-proofed')).toBe('/listing/l-proofed');
    expect(open('l-expired')).toBe('/listing/l-expired');
    expect(open('l-disputed')).toBe('/listing/l-disputed');
  });

  it('SA5: the "Send tickets" filter is unchanged — pending rows only, proof rows stay out', async () => {
    const host = await mountMyListings();
    const chip = findElement(host.output, (el) => el.type === 'Chip' && el.props.label === 'Send tickets') as Element;
    (chip.props.onPress as () => void)();
    host.flush();
    expect([...rows(host).keys()].sort()).toEqual(['l-late', 'l-nodate', 'l-send']);
  });

  it('SA5b: an empty "Send tickets" filter says only that nothing is waiting to be sent — not "All caught up" while an Add proof row is open', async () => {
    // Only the proof rows: the filter keeps pending rows, so it is empty, yet one row still shows an action.
    h.listings = [listing('l-proof'), listing('l-proofed')];
    h.transfers = [
      transfer('t-proof', 'l-proof', 'seller_sent'),
      transfer('t-proofed', 'l-proofed', 'seller_sent', { transfer_evidence_path: 'seller-1/t-proofed/proof.jpg' }),
    ];
    const host = await mountMyListings();
    // Witness: the open action really is on the All list before the filter is chosen.
    expect((rows(host).get('l-proof')!.nextAction as { kind: string }).kind).toBe('add_proof');
    const chip = findElement(host.output, (el) => el.type === 'Chip' && el.props.label === 'Send tickets') as Element;
    (chip.props.onPress as () => void)();
    host.flush();
    expect(rows(host).size).toBe(0);
    const empty = list(host).props.ListEmptyComponent as Element;
    expect(empty.type).toBe('EmptyState');
    expect(empty.props.title).toBe('Nothing to send');
    expect(empty.props.body).toBe('No tickets waiting to be sent.');
    // Nothing in the empty state claims the seller has no open task at all.
    expect(`${empty.props.title} ${empty.props.body}`).not.toMatch(/caught up|nothing to do|all done/i);
  });
});

describe('SellerListingCard renders the one line', () => {
  async function renderCard(props: Record<string, unknown>) {
    const { default: SellerListingCard } = await import('@/src/components/SellerListingCard');
    const host = new HookHost(
      () => (SellerListingCard as (p: Record<string, unknown>) => unknown)({ listing: listing('l-1'), onPress: () => {}, ...props }),
      new Map(),
    );
    host.mount();
    return host;
  }

  it('SA6: a send action shows its line once, in the action colour, and VoiceOver hears it', async () => {
    const { dark } = await import('@/src/theme/palette');
    const action = { kind: 'send_by', line: 'Send by Wed 21 Oct · 21:14', tone: 'warning' };
    const host = await renderCard({ nextAction: action });
    const all = texts(host.output);
    expect(all.filter((t) => t === action.line)).toHaveLength(1);
    expect(all.some((t) => /Action needed/.test(t))).toBe(false);
    const line = findElement(host.output, (el) => el.type === 'Text' && el.props.children === action.line) as Element;
    expect(JSON.stringify(line.props.style)).toContain(dark.status.warning);
    const row = findElement(host.output, (el) => typeof el.props.accessibilityLabel === 'string' && /Event l-1/.test(el.props.accessibilityLabel as string)) as Element;
    expect(row.props.accessibilityLabel).toContain('Send by Wed 21 Oct · 21:14.');
  });

  it('SA7: the neutral past-window line is not dressed as an action', async () => {
    const { dark } = await import('@/src/theme/palette');
    const action = { kind: 'window_passed', line: 'Send window has passed — open this order to see its current status', tone: 'neutral' };
    const host = await renderCard({ nextAction: action });
    const line = findElement(host.output, (el) => el.type === 'Text' && el.props.children === action.line) as Element;
    expect(line, 'the line renders').toBeTruthy();
    const style = JSON.stringify(line.props.style);
    expect(style).not.toContain(dark.status.warning);
    expect(style).toContain(dark.text.secondary);
  });

  it('SA8: a sentence that already ends in a full stop is not given a second one', async () => {
    const action = { kind: 'do_not_send', line: "This order expired before it was marked as sent. Don't transfer the tickets for this order.", tone: 'warning' };
    const host = await renderCard({ nextAction: action });
    const row = findElement(host.output, (el) => typeof el.props.accessibilityLabel === 'string' && /Event l-1/.test(el.props.accessibilityLabel as string)) as Element;
    expect(row.props.accessibilityLabel).toContain("Don't transfer the tickets for this order.");
    expect(row.props.accessibilityLabel).not.toContain('order..');
  });

  it('SA9: no action → no line', async () => {
    const none = await renderCard({ nextAction: null });
    expect(texts(none.output).some((t) => /^Send |Add proof|Action needed/.test(t))).toBe(false);
  });

  it('SA9b: the line is only ever on a sold row — rows that reach the action slot without a sold badge show and say nothing', async () => {
    const action = { kind: 'send', line: 'Send the tickets', tone: 'warning' };
    const rowLabel = (host: HookHost, id: string) =>
      (findElement(host.output, (el) => typeof el.props.accessibilityLabel === 'string'
        && (el.props.accessibilityLabel as string).startsWith(`Event ${id}.`)) as Element).props.accessibilityLabel as string;

    // Witness: the same action on a sold row IS shown and spoken, so an absence below is the gate, not the harness.
    const sold = await renderCard({ nextAction: action });
    expect(texts(sold.output)).toContain(action.line);
    expect(rowLabel(sold, 'l-1')).toContain(`${action.line}.`);

    // Each of these falls past the countdown and "Winner selected" branches to the action slot itself
    // (or, for an ended row with a winner, would add the line to VoiceOver only).
    const notSold: [string, Record<string, unknown>, string][] = [
      ['ended, no winner', { status: 'ended', auction_status: 'ended', winner_user_id: null, sold_at: null }, 'Ended'],
      ['reserved', { status: 'reserved', auction_status: 'ended', reserved_until: FUTURE, winner_user_id: null, sold_at: null }, 'Reserved'],
      ['cancelled after sale', { status: 'sold', auction_status: 'cancelled' }, 'Cancelled'],
      ['ended, winner selected', { status: 'ended', auction_status: 'ended', sold_at: null }, 'Ended'],
      ['active', { status: 'active', auction_status: 'active', ends_at: FUTURE, sold_at: null, winner_user_id: null }, 'Active'],
    ];
    for (const [why, extra, badgeWord] of notSold) {
      const host = await renderCard({ listing: listing('l-2', extra), nextAction: action });
      const label = rowLabel(host, 'l-2');
      // The fixture really lands on the intended badge (else the case proves nothing).
      expect(label, why).toContain(`. ${badgeWord}.`);
      expect(texts(host.output), why).not.toContain(action.line);
      expect(label, why).not.toContain(action.line);
    }
  });
});

describe('source pins', () => {
  it('SA10: the old generic line is gone, and neither consumer reuses the "checking" copy', () => {
    const card = code('src/components/SellerListingCard.tsx');
    expect(card).not.toContain('Action needed — send the tickets');
    expect(card).toContain('nextAction.line');
    for (const rel of ['src/components/SellerListingCard.tsx', 'app/my-listings.tsx', 'src/lib/seller/nextAction.ts']) {
      expect(code(rel), rel).not.toContain('TRANSFER_EXPIRY_COPY');
      expect(code(rel), rel).not.toContain('sellerWindowView');
    }
  });

  it('SA11: the deadline is formatted by the shared row formatter, not a new one', () => {
    const helper = code('src/lib/seller/nextAction.ts');
    expect(helper).toMatch(/import \{[^}]*rowWhenLabel[^}]*\} from '@\/src\/lib\/listing\/feedRowState'/);
    expect(helper).not.toMatch(/toLocale(Date|Time)?String/);
  });
});

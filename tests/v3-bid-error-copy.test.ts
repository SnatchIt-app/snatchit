/**
 * tests/v3-bid-error-copy.test.ts — the bidder never reads the server's own error string.
 *
 * `src/screens/PlaceBidScreen.tsx` showed `Alert.alert('Bid failed', error.message)` when the `bids`
 * insert came back with an error: a raw PostgREST / Postgres string, on the screen where money is
 * committed. Two defects in one line — it is not product copy (it can name tables and policies), and
 * "Bid failed" asserts an outcome the client does not know, because supabase-js returns transport
 * failures in the same `error` channel as a server rejection, so the row may have committed while the
 * response was lost.
 *
 * These tests drive the REAL screen through the hook dispatcher with the insert under test control
 * and read what the bidder would actually be shown — not the source alone. The source guards that
 * follow then hold the shape: the constant is module-level, it is the one used at the insert-error
 * branch, and no OTHER alert on the screen reads a server string either.
 *
 * Not a device result. The Alert is captured from the react-native mock.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { beforeEach, describe, expect, it, vi } from 'vitest';

import { findElement, HookHost, type Element } from './helpers/nav-stack-harness';

/** The kind of string that used to reach the bidder verbatim. */
const RAW_SERVER_MESSAGE = 'new row violates row-level security policy for table "bids"';

type Alerted = { title: string; body?: string };

const h = vi.hoisted(() => ({
  alerts: [] as { title: string; body?: string }[],
  insertError: null as { message: string } | null,
  tables: [] as string[],
  user: { id: 'bidder-1' } as { id: string } | null,
  network: { isOffline: false },
}));

vi.mock('react-native', () => ({
  Alert: { alert: (title: string, body?: string) => { h.alerts.push({ title, body }); } },
  ScrollView: 'ScrollView', Text: 'Text', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('expo-router', () => ({ router: { push: () => {}, back: () => {}, replace: () => {} } }));
vi.mock('react-native-safe-area-context', () => ({ useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }) }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: h.user }) }));
vi.mock('@/src/hooks/useNetworkStatus', () => ({ useNetworkStatus: () => h.network }));
vi.mock('@/src/components/ScreenState', () => ({ default: 'ScreenState' }));
vi.mock('@/src/components/ui', () => ({
  Button: 'Button', IconButton: 'IconButton', Spinner: 'Spinner', StickyBar: 'StickyBar', Tappable: 'Tappable',
}));
vi.mock('@/src/lib/feedback/haptics', () => ({ hapticConfirm: () => {} }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useTopInset: () => 0 }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3 }));
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});

vi.mock('@/src/lib/supabase', () => {
  /** A query object that is awaitable and answers `select/eq/insert/single/maybeSingle`. */
  const thenable = (result: unknown) => {
    const q: Record<string, unknown> = {};
    for (const m of ['select', 'eq', 'insert']) q[m] = () => q;
    q.single = () => Promise.resolve(result);
    q.maybeSingle = () => Promise.resolve(result);
    q.then = (ok: (v: unknown) => unknown, bad?: (e: unknown) => unknown) => Promise.resolve(result).then(ok, bad);
    q.catch = (bad: (e: unknown) => unknown) => Promise.resolve(result).catch(bad);
    return q;
  };
  return {
    supabase: {
      from: (table: string) => {
        h.tables.push(table);
        // The insert under test control; the post-insert re-read answers a normal fresh floor.
        if (table === 'bids') return thenable({ data: null, error: h.insertError });
        return thenable({ data: { current_bid: 105 }, error: null });
      },
      // The F-5 deletion probe: no kernel row, so the guard passes and the insert is reached.
      schema: () => ({ from: () => thenable({ data: null, error: null }) }),
    },
  };
});

const flush = async () => { for (let i = 0; i < 6; i++) await new Promise((r) => setImmediate(r)); };

/** The fixture prop short-circuits the READ only (the screen's own documented dev path). */
const LISTING = {
  id: 'l-1', event_name: 'Sandbox L6', venue: 'The Venue', current_bid: 100, starting_bid: 50,
  quantity: 1, ticket_type: 'Standard', bid_count: 2,
  event_date: '2099-01-01', event_time: '19:30', ends_at: '2099-01-01T00:00:00Z',
};

const SCREEN = resolve(__dirname, '..', 'src/screens/PlaceBidScreen.tsx');
const source = () => readFileSync(SCREEN, 'utf8');
const stripComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

/** The copy as the SHIPPED source declares it — so the assertions below read the screen's own strings. */
function declaredCopy(): { title: string; body: string } {
  const m = /const BID_UNCONFIRMED_COPY = \{\s*title: (["'])([\s\S]*?)\1,\s*body: (["'])([\s\S]*?)\3,\s*\} as const;/
    .exec(stripComments(source()));
  expect(m, 'BID_UNCONFIRMED_COPY is not a module-level object literal with title + body').not.toBeNull();
  return { title: m![2], body: m![4] };
}

/** Every `Alert.alert(...)` call on the screen, as its raw argument text (balanced parens). */
function alertCallArgs(code: string): string[] {
  const out: string[] = [];
  const needle = 'Alert.alert(';
  for (let i = code.indexOf(needle); i !== -1; i = code.indexOf(needle, i + 1)) {
    let depth = 0;
    let j = i + needle.length - 1;
    for (; j < code.length; j++) {
      if (code[j] === '(') depth++;
      else if (code[j] === ')' && --depth === 0) break;
    }
    out.push(code.slice(i + needle.length, j));
  }
  return out;
}

async function mountScreen(): Promise<HookHost> {
  const { default: PlaceBidScreen } = await import('@/src/screens/PlaceBidScreen');
  const host = new HookHost(
    () => (PlaceBidScreen as (p: { id: string; fixture?: unknown }) => unknown)({ id: 'l-1', fixture: LISTING }),
    new Map(),
  );
  host.mount();
  await flush();
  host.flush();
  return host;
}

/** Press "Place bid" and let the submission settle. */
async function placeBid(host: HookHost): Promise<Alerted[]> {
  const button = findElement(host.output, (el) => el.type === 'Button' && el.props.label === 'Place bid') as Element;
  expect(button, 'the bid form did not render — nothing to press').toBeDefined();
  void (button.props.onPress as () => void)();
  await flush();
  host.flush();
  return h.alerts as Alerted[];
}

beforeEach(() => {
  h.alerts.length = 0;
  h.tables.length = 0;
  h.insertError = null;
  h.user = { id: 'bidder-1' };
  h.network.isOffline = false;
  vi.resetModules();
});

describe('a failed bid insert never shows the server string', () => {
  it('BE1: the raw message is not in the alert, anywhere in it', async () => {
    h.insertError = { message: RAW_SERVER_MESSAGE };
    const alerts = await placeBid(await mountScreen());

    expect(h.tables).toContain('bids');                 // the insert really was attempted
    expect(alerts).toHaveLength(1);
    const shown = `${alerts[0].title} | ${alerts[0].body ?? ''}`;
    expect(shown).not.toContain(RAW_SERVER_MESSAGE);
    // …and not a fragment of it either: no schema, table or policy vocabulary reaches the bidder.
    expect(shown).not.toMatch(/row-level security|policy|violates|constraint|relation|table "/i);
  });

  it('BE2: what is shown is exactly the screen\'s BID_UNCONFIRMED_COPY constant', async () => {
    h.insertError = { message: RAW_SERVER_MESSAGE };
    const alerts = await placeBid(await mountScreen());
    const copy = declaredCopy();

    expect(alerts[0].title).toBe(copy.title);
    expect(alerts[0].body).toBe(copy.body);
    // Pinned wording: a reword is a deliberate change to this line, not a silent drift.
    expect(copy.title).toBe("We couldn't confirm your bid");
  });

  it('BE3: the copy claims neither that the bid landed nor that it did not', async () => {
    const { title, body } = declaredCopy();
    const both = `${title} ${body}`;
    // The client knows only that no confirmation came back. Anything stronger, in either direction,
    // is a claim about a row it could not read.
    expect(both).not.toMatch(/\bfailed\b/i);
    expect(both).not.toMatch(/wasn'?t (placed|sent|submitted|received|accepted)/i);
    expect(both).not.toMatch(/(was|has been) (placed|accepted|received)\b/i);
    expect(both).not.toMatch(/\b(no bid|nothing) (was|has been) (placed|sent|submitted)/i);
    expect(both).not.toMatch(/success/i);
    expect(both).not.toMatch(/\bdid not (go through|land|work)\b/i);
    // And it is USEFUL: it admits the uncertainty and names where the bidder can settle it.
    expect(both).toMatch(/confirm/i);
    expect(both).toMatch(/current bid/i);
  });

  it('BE4: a successful insert is unaffected — the outcome copy still runs (regression guard)', async () => {
    h.insertError = null;
    const alerts = await placeBid(await mountScreen());
    const copy = declaredCopy();

    expect(alerts).toHaveLength(1);
    expect(alerts[0].title).not.toBe(copy.title);
    // 105 is both the bid and the fresh floor, so the position is "leading" — bidOutcomeCopy's words.
    expect(`${alerts[0].title} ${alerts[0].body}`).toMatch(/leading/i);
  });
});

describe('shipped-source guards — no Alert on this screen reads a server string', () => {
  const code = stripComments(source());

  it('BE5: the old raw-message fallback is gone and `.message` is not read at all', () => {
    expect(code).not.toContain("Alert.alert('Bid failed', error.message)");
    expect(code).not.toMatch(/Alert\.alert\([^)]*\.message/);
    // Nothing on this screen reads a server message any more, so none can reach a dialog by a new route.
    expect(code).not.toMatch(/\.message\b/);
  });

  it('BE6: every Alert argument is product copy — no error object reaches one', () => {
    const calls = alertCallArgs(code);
    expect(calls.length).toBeGreaterThanOrEqual(4);   // signed-in, too-low, flight catch, deletion, insert, outcome
    for (const args of calls) {
      expect(args, args).not.toMatch(/\.message\b/);
      expect(args, args).not.toMatch(/\b(error|err)\b/);
    }
  });

  it('BE7: the constant is module-level, sits with the other bid copy, and is used at the insert-error branch', () => {
    expect(code).toMatch(/^const BID_UNCONFIRMED_COPY = \{/m);            // module scope, column 0
    const chips = code.indexOf('const QUICK_CHIPS');
    const copy = code.indexOf('const BID_UNCONFIRMED_COPY');
    const component = code.indexOf('export default function PlaceBidScreen');
    expect(chips).toBeGreaterThan(0);
    expect(copy).toBeGreaterThan(chips);
    expect(copy).toBeLessThan(component);

    // Used at the insert error, after the insert and before the success path. Searched FROM the
    // insert, because the same copy now also serves the THROW path above submitBid (E's finding: a
    // transport exception outside the `{ error }` channel has the same unknown outcome), so a plain
    // indexOf would measure the wrong arm.
    const insert = code.indexOf("from('bids').insert(");
    const used = code.indexOf('Alert.alert(BID_UNCONFIRMED_COPY.title, BID_UNCONFIRMED_COPY.body)', insert);
    const haptic = code.indexOf('hapticConfirm();');
    expect(insert).toBeGreaterThan(0);
    expect(used).toBeGreaterThan(insert);
    expect(haptic).toBeGreaterThan(used);
  });

  it('BE8: the F-5 deletion guard keeps its own specific copy — only the unknown fallback changed', () => {
    // The one KNOWN case this handler maps stays mapped, and it still returns before the insert.
    expect(code).toContain("'DELETION_PENDING'");
    expect(code).toContain("'Account deletion pending'");
    expect(code.indexOf("'DELETION_PENDING'")).toBeLessThan(code.indexOf("from('bids').insert("));
  });
});

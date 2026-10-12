/**
 * tests/v3-money-rows-a3xl.test.ts — B-D7: money digits are never clipped at the largest text size.
 *
 * B measured the 48d20ca1 Release binary at A3XL: clipped money digits on Bids (BidCard), auction
 * Checkout (the breakdown rows), PlaceBid (market / Bid / Fee rows) and Order (the "You paid" row
 * and the detail rows). The owner's rule is explicit: clipped money digits are a defect. Fix: the
 * SAME approved stacking rule the batch already applies (TransactionPanel, FeedRow, the profile
 * hero, SettingsRow) — nothing new:
 *
 *   stacked = identityStacks(fontScale)            // one shared threshold, 1.3×
 *   row container: column above the threshold, the original row below it
 *   amount: ALWAYS one line; above the threshold adjustsFontSizeToFit + AMOUNT_MIN_FONT_SCALE,
 *           so the LAYOUT bounds it; below the threshold the props are exactly what they were
 *
 * Default size stays pixel-identical: the unstacked branch renders the original style objects and
 * the original props, and this file pins both (A's condition 2; B re-measures on the RC2 binary).
 * PlaceBid's Total is NOT touched: its 1.3× cap is B-D6, the owner's decision.
 *
 * Mutant this file must kill: revert the stacking in any one of the four surfaces.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';

import { HookHost, type Element } from './helpers/nav-stack-harness';

const rn = vi.hoisted(() => ({ fontScale: 1 }));
vi.mock('react-native', () => ({
  Text: 'Text', View: 'View', Pressable: 'Pressable', Image: 'Image',
  Animated: { View: 'Animated.View', Text: 'Animated.Text', Value: class { interpolate() { return 0; } setValue() {} }, timing: () => ({ start: (cb?: () => void) => cb?.() }) },
  StyleSheet: { create: <T,>(s: T) => s, hairlineWidth: 1, absoluteFillObject: {} },
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
  useWindowDimensions: () => ({ width: 393, height: 852, scale: 3, fontScale: rn.fontScale }),
}));
vi.mock('@/src/components/media/EventMedia', () => ({ EventMedia: 'EventMedia' }));
vi.mock('@/src/components/ui', () => ({
  Badge: 'Badge', Tappable: 'Tappable', Button: 'Button',
  usePressScale: () => ({ style: {}, onPressIn: () => {}, onPressOut: () => {} }),
}));
vi.mock('@/src/components/NameText', () => ({ NameText: 'NameText' }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3, AMOUNT_MIN_FONT_SCALE: 0.6 }));
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});
vi.mock('@/src/lib/feedback/haptics', () => ({ hapticSelect: () => {}, hapticSuccess: () => {} }));

const strip = (rel: string) => readFileSync(rel, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

function nodes(root: unknown): Element[] {
  const out: Element[] = [];
  const walk = (n: unknown): void => {
    if (Array.isArray(n)) { n.forEach(walk); return; }
    const el = n as Element | null;
    if (!el || typeof el !== 'object' || !('props' in el)) return;
    out.push(el);
    walk((el.props as { children?: unknown }).children);
  };
  walk(root);
  return out;
}

const PRICE = '$104.50';

async function mountBidCard(fontScale: number) {
  rn.fontScale = fontScale;
  const mod = await import('@/src/components/bids/BidCard') as Record<string, unknown>;
  const exported = mod.BidCard as { type?: (p: unknown) => unknown } | ((p: unknown) => unknown);
  const Fn = (typeof exported === 'function' ? exported : exported.type!) as (p: unknown) => unknown;
  const host = new HookHost(() => Fn({
    eventName: 'Weekend pool party', venue: 'LIV Miami', whenLabel: 'Sat 17 Oct', coverPath: null,
    presentation: { label: 'Leading', tone: 'live', actionHint: 'View listing' },
    priceAllIn: PRICE, urgencyLabel: null, onPress: () => {},
  }), new Map());
  host.mount(); host.flush();
  return nodes(host.output);
}

const priceText = (els: Element[]) => els.find((el) => el.type === 'Text' && el.props.children === PRICE);

beforeEach(() => { rn.fontScale = 1; vi.resetModules(); });

describe('B-D7 · BidCard (behavioural)', () => {
  it('MR1: at the default size the amount keeps exactly its original props — one line, no fit, no cap', async () => {
    const els = await mountBidCard(1);
    const price = priceText(els);
    expect(price, 'the amount should render').toBeTruthy();
    expect(price!.props.numberOfLines).toBe(1);
    expect(price!.props.adjustsFontSizeToFit).toBeUndefined();
    expect(price!.props.minimumFontScale).toBeUndefined();
    expect(price!.props.maxFontSizeMultiplier).toBeUndefined();
    // and no stacked wrapper exists at default — the row is the row it always was
    expect(els.find((el) => el.props.testID === 'bidcard-body')).toBeUndefined();
  });

  it('MR2: at A3XL the amount owns a full-width line and shrinks to fit instead of clipping', async () => {
    const els = await mountBidCard(3.1);
    const price = priceText(els);
    expect(price, 'the amount should render').toBeTruthy();
    expect(price!.props.numberOfLines, 'a split amount misreads as badly as a clipped one').toBe(1);
    expect(price!.props.adjustsFontSizeToFit).toBe(true);
    expect(price!.props.minimumFontScale).toBe(0.6);
    expect(els.find((el) => el.props.testID === 'bidcard-body'), 'the text and amount blocks stack into one column').toBeTruthy();
  });

  it('MR3: the threshold is the shared one — 1.3× stacks, 1.29× does not', async () => {
    const at129 = await mountBidCard(1.29);
    expect(priceText(at129)!.props.adjustsFontSizeToFit).toBeUndefined();
    const at130 = await mountBidCard(1.3);
    expect(priceText(at130)!.props.adjustsFontSizeToFit).toBe(true);
  });
});

/** The four screens pin their wiring by source: each row stacks above the threshold and keeps its original style below it. */
describe('B-D7 · the shared rule is wired into each surface, and the default styles are untouched', () => {
  // `count` is how many rows of that kind carry money and must stack — a mutant that reverts ONE of
  // two summary rows (Bid, Fee) survived a presence-only pin, so the count is asserted, and no bare
  // `style={container}>` may remain (the PlaceBid Total uses `[s.summaryRow, s.summaryTotalRow]`,
  // a different literal, and is deliberately excluded).
  const cases: { rel: string; rows: { container: string; stacked: string; count: number }[]; originalStyles: string[]; amountFit: string }[] = [
    {
      rel: 'src/screens/checkout/CheckoutView.tsx',
      rows: [{ container: 's.row', stacked: 's.rowStacked', count: 1 }, { container: 's.totalRow', stacked: 's.totalRowStacked', count: 1 }],
      originalStyles: [
        "row: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline', gap: v2.space.md },",
        "totalRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline' },",
      ],
      amountFit: 'amountFit',
    },
    {
      rel: 'src/screens/PlaceBidScreen.tsx',
      rows: [{ container: 's.marketRow', stacked: 's.marketRowStacked', count: 1 }, { container: 's.summaryRow', stacked: 's.summaryRowStacked', count: 2 }],
      originalStyles: [
        "summaryRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline', gap: v2.space.md },",
      ],
      amountFit: 'amountFit',
    },
    {
      rel: 'app/transfer/receive/[id].tsx',
      rows: [{ container: 's.paidRow', stacked: 's.paidRowStacked', count: 1 }, { container: 's.row', stacked: 's.rowStacked', count: 1 }],
      originalStyles: [
        "paidRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: v2.space.lg },",
        "row: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: v2.space.md, paddingVertical: v2.space.xs },",
      ],
      amountFit: 'amountFit',
    },
    {
      rel: 'app/transfer/send/[id].tsx',
      rows: [{ container: 's.row', stacked: 's.rowStacked', count: 1 }],
      originalStyles: [],
      amountFit: 'amountFit',
    },
  ];

  for (const c of cases) {
    it(`MR4 ${c.rel}: reads the shared threshold and stacks each money row above it`, () => {
      const src = strip(c.rel);
      expect(src).toContain('identityStacks(');
      expect(src).toContain('useWindowDimensions');
      for (const r of c.rows) {
        const esc = (x: string) => x.replace('.', '\\.');
        const ternaries = src.match(new RegExp(`stacked \\? ${esc(r.stacked)} : ${esc(r.container)}`, 'g')) ?? [];
        expect(ternaries, `${r.container} must switch to ${r.stacked} on every money row of that kind`).toHaveLength(r.count);
        // No money row of that kind may still render the bare container (one reverted row is a clipped amount).
        const bare = src.match(new RegExp(`style=\\{${esc(r.container)}\\}`, 'g')) ?? [];
        expect(bare, `a bare style={${r.container}} is a row that does not stack`).toHaveLength(0);
      }
    });

    it(`MR5 ${c.rel}: the amount is one line and fits only when stacked; the unstacked props are untouched`, () => {
      const src = strip(c.rel);
      // The approved shape: fit props exist only in the stacked branch, and nothing is added below it.
      expect(src).toMatch(/const amountFit = stacked\s*\?\s*\{ adjustsFontSizeToFit: true, minimumFontScale: AMOUNT_MIN_FONT_SCALE \}\s*:\s*(null|\{\})/);
      expect(src).toContain('{...amountFit}');
    });

    if (c.originalStyles.length) {
      it(`MR6 ${c.rel}: the default-size style objects are byte-identical to before`, () => {
        const raw = readFileSync(c.rel, 'utf8');
        for (const line of c.originalStyles) expect(raw, line).toContain(line);
      });
    }
  }

  it('MR7: PlaceBid\'s Total is untouched — B-D6 stays the owner\'s decision', () => {
    const src = strip('src/screens/PlaceBidScreen.tsx');
    const total = src.slice(src.indexOf('testID="bid-summary-total"'), src.indexOf('</View>', src.indexOf('testID="bid-summary-total"')));
    expect(total).toContain('maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}');
    expect(total).not.toContain('adjustsFontSizeToFit');
    expect(total).not.toContain('amountFit');
  });

  it('MR8: no copy changed on any of the four surfaces', () => {
    expect(strip('src/screens/checkout/CheckoutView.tsx')).toContain('label="Service fee"');
    expect(strip('src/screens/PlaceBidScreen.tsx')).toContain("'Current bid' : 'Starting bid'");
    expect(strip('app/transfer/receive/[id].tsx')).toContain('{YOU_PAID_LABEL}');
  });
});

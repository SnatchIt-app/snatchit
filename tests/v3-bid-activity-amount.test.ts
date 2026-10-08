/**
 * tests/v3-bid-activity-amount.test.ts — the bid history's amounts survive the text size.
 *
 * B's batch-6 finding: at the largest accessibility size the LEADING row's amount loses its
 * cents. The leading row is the one that loses them because it is the only row carrying the
 * "Leading" chip, so three elements compete for the width instead of two — the name block, the
 * chip and the amount — and the amount is last in the row.
 *
 * A clipped amount states a different number from the one that was bid. This is the same defect
 * the Home feature, the feed row and the transaction panel each had, so it takes the same
 * treatment rather than a fourth invention: above the shared threshold the row stacks, the amount
 * owns its line and is bounded by that line, and the compact form keeps its cap.
 *
 * This component had no test file at all before this one.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { findElement, HookHost, type Element } from './helpers/nav-stack-harness';

const rn = vi.hoisted(() => ({ fontScale: 1 }));
vi.mock('react-native', () => ({
  useWindowDimensions: () => ({ width: 393, height: 852, scale: 3, fontScale: rn.fontScale }),
  Text: 'Text',
  View: 'View',
  StyleSheet: { create: <T,>(s: T) => s, hairlineWidth: 1 },
}));
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});
vi.mock('@/src/theme/typography', () => ({
  textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3, AMOUNT_MIN_FONT_SCALE: 0.6,
}));
vi.mock('@/src/components/ui', () => ({ EmptyState: 'EmptyState' }));

const BIDS = [
  { id: 'b1', bidder_id: 'k7f2aaaa', created_at: '2026-10-08T00:00:00Z', amount: 90, profiles: null },
  { id: 'b2', bidder_id: 'viewer-1', created_at: '2026-10-08T00:00:00Z', amount: 85, profiles: null },
];

async function mountActivity(amount = '$99.00') {
  const mod = await import('@/src/components/listing/BidActivity');
  const Activity = mod.BidActivity as unknown as (p: unknown) => unknown;
  const host = new HookHost(() => Activity({
    bids: BIDS,
    amountFor: () => amount,
    timeFor: () => '3m ago',
    viewerId: 'viewer-1',
    highlightTop: true,
  }), new Map());
  host.mount();
  host.flush();
  return host;
}

const amountNodes = (host: HookHost) => {
  const out: Element[] = [];
  const walk = (n: unknown): void => {
    if (Array.isArray(n)) { n.forEach(walk); return; }
    const el = n as Element | null;
    if (!el || typeof el !== 'object' || !('props' in el)) return;
    if (el.type === 'Text' && String(el.props.children).startsWith('$')) out.push(el);
    walk(el.props.children);
  };
  walk(host.output);
  return out;
};
const leadingChip = (host: HookHost) =>
  findElement(host.output, (el) => el.type === 'Text' && el.props.children === 'Leading');
const nameNode = (host: HookHost, text: string) =>
  findElement(host.output, (el) => el.type === 'Text' && el.props.children === text);

beforeEach(() => { vi.resetModules(); rn.fontScale = 1; });

describe('BA · the bid history keeps its amounts whole', () => {
  it('BA1: at the default size the row is unchanged and the amount keeps the compact cap', async () => {
    const host = await mountActivity();
    const amounts = amountNodes(host);
    expect(amounts).toHaveLength(2);
    for (const a of amounts) {
      expect(a.props.maxFontSizeMultiplier).toBe(1.3);
      expect(a.props.adjustsFontSizeToFit).toBeFalsy();
    }
    // The chip is what makes the leading row the tight one; it must still be there.
    expect(leadingChip(host)).toBeDefined();
  });

  it('BA2: at a large scale the row stacks and the amount is bounded by its line, not a cap', async () => {
    rn.fontScale = 3.1;
    const host = await mountActivity();
    for (const a of amountNodes(host)) {
      expect(a.props.maxFontSizeMultiplier, 'no multiplier cap once it owns the line').toBeUndefined();
      expect(a.props.numberOfLines, 'an amount never wraps').toBe(1);
      expect(a.props.adjustsFontSizeToFit).toBe(true);
      expect(a.props.minimumFontScale).toBeGreaterThan(0);
    }
  });

  it('BA3: the LEADING row — the one B measured — stacks with the others', async () => {
    rn.fontScale = 3.1;
    const host = await mountActivity();
    // Every row is a column at this scale, so the chip no longer takes width from the amount.
    const stackedRows = (() => {
      let n = 0;
      const walk = (x: unknown): void => {
        if (Array.isArray(x)) { x.forEach(walk); return; }
        const el = x as Element | null;
        if (!el || typeof el !== 'object' || !('props' in el)) return;
        const st = el.props.style as { flexDirection?: string } | Array<{ flexDirection?: string }> | undefined;
        const flat = Array.isArray(st) ? Object.assign({}, ...st.filter(Boolean)) : st;
        if (el.type === 'View' && flat?.flexDirection === 'column') n += 1;
        walk(el.props.children);
      };
      walk(host.output);
      return n;
    })();
    expect(stackedRows, 'both rows stack').toBeGreaterThanOrEqual(2);
    expect(leadingChip(host), 'the chip is kept, not dropped to make room').toBeDefined();
  });

  it('BA4: the bidder is not clipped either — "You" became "Y…" on the device', async () => {
    rn.fontScale = 3.1;
    const host = await mountActivity();
    expect(nameNode(host, 'You')?.props.numberOfLines).toBeUndefined();
  });

  it('BA5: a four-figure amount passes through untouched, separator and cents included', async () => {
    rn.fontScale = 3.1;
    const host = await mountActivity('$1,716.00');
    for (const a of amountNodes(host)) expect(a.props.children).toBe('$1,716.00');
  });

  it('BA6: the spoken row still carries the whole amount, separately from the visible one', async () => {
    rn.fontScale = 3.1;
    const host = await mountActivity('$1,716.00');
    const row = findElement(host.output, (el) =>
      typeof el.props.accessibilityLabel === 'string' && el.props.accessibilityLabel.includes('$1,716.00'));
    expect(row, 'a row announces the full amount').toBeDefined();
    expect(String(row!.props.accessibilityLabel)).toContain('Highest bid');
  });
});

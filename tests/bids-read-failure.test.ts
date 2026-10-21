/**
 * B-D1 (B's RC2 verdict; A's ruling 2026-10-21): a failed bids-list read must not restate the floor
 * or claim "No bids yet".
 *
 * Before: `useListingRealtime` turned a failed read into [], so its currentBid fell back to
 * starting_bid. The listing then said "minimum $20.00" over a $40 current bid, and Bid activity
 * painted "No bids yet". A's rules:
 *  - the listing row's current_bid is server-owned (only validate_and_apply_bid moves it), so the
 *    displayed floor is max(listing current_bid, the bids list's highest). A failed list read falls
 *    back to the listing row, never to starting_bid. Same current + MIN_BID_INCREMENT (F10 untouched).
 *  - Bid activity says "Couldn't load bids" with Retry, never "No bids yet".
 *  - Bid entry stays on: PlaceBidScreen reads current_bid from the listing row itself.
 * Outbid / highest-bidder detection stays on the bids list. The listing row can lead it by a moment,
 * and would call a bidder's own fresh bid "outbid".
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';

import { displayedBidFloor, minNextBid } from '@/src/lib/bid/bidEntry';
import { findElement, HookHost } from './helpers/nav-stack-harness';
import { byLabel, screenText } from './helpers/screen-view';

const code = (rel: string) => readFileSync(rel, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});
vi.mock('react-native', () => ({
  useWindowDimensions: () => ({ width: 393, height: 852, scale: 3, fontScale: 1 }),
  Pressable: 'Pressable', Text: 'Text', View: 'View', StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('@/src/components/ui', () => ({ EmptyState: 'EmptyState' }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3, AMOUNT_MIN_FONT_SCALE: 0.6 }));

beforeEach(() => { vi.resetModules(); });

async function renderActivity(props: Record<string, unknown>): Promise<HookHost> {
  const { BidActivity } = await import('@/src/components/listing/BidActivity');
  const host = new HookHost(() => (BidActivity as (p: unknown) => unknown)({
    bids: [], amountFor: () => '', timeFor: () => '', viewerId: null, highlightTop: true, ...props,
  }), new Map());
  host.mount();
  host.flush();
  return host;
}

describe('B-D1: a failed bids read', () => {
  it('BF1: the floor falls back to the listing row, never starting_bid (control: the old list-only floor)', () => {
    // starting_bid 15; the server's current_bid is 40; the list read failed, so the list says 15.
    expect(displayedBidFloor(40, 15)).toBe(40);
    expect(minNextBid(displayedBidFloor(40, 15), 5)).toBe(45);
    // Negative control: build 29 used the list's figure alone.
    expect(minNextBid(15, 5)).toBe(20);
    // A successful list read that's ahead of the row (an insert landed first) still wins.
    expect(displayedBidFloor(40, 50)).toBe(50);
  });

  it('BF2: Bid activity says it could not load, with Retry, and never "No bids yet"', async () => {
    let retried = 0;
    const host = await renderActivity({ loadFailed: true, onRetry: () => { retried++; } });
    const text = screenText(host.output);
    expect(text).toContain("Couldn't load bids");
    expect(text).not.toContain('No bids yet');
    expect(findElement(host.output, (el) => el.type === 'EmptyState')).toBeUndefined();
    const retry = byLabel(host.output, 'Retry loading bids');
    expect(retry).toBeDefined();
    (retry?.props.onPress as () => void)();
    expect(retried).toBe(1);
  });

  it('BF3: a successful empty read still says "No bids yet" (control for BF2)', async () => {
    const host = await renderActivity({ loadFailed: false });
    expect(findElement(host.output, (el) => el.type === 'EmptyState' && el.props.title === 'No bids yet')).toBeDefined();
    expect(screenText(host.output)).not.toContain("Couldn't load bids");
  });

  it('BF4: the hook reports a failed read instead of returning []', () => {
    const hook = code('src/hooks/useListingRealtime.ts');
    expect(hook).toMatch(/if \(error\) \{[\s\S]{0,120}return null;/);
    expect(hook).toMatch(/setLoadError\(rows === null\)/);
    expect(hook).toMatch(/loadError,\s*\n\s*refetch,/);
  });

  it('BF5: the listing prices the minimum from the displayed floor; outbid stays on the list', () => {
    const screen = code('src/screens/ListingDetailScreen.tsx');
    expect(screen).toContain('const priceFloor = displayedBidFloor(listing?.current_bid ?? 0, rt.currentBid);');
    expect(screen).toContain('listingPriceLinesV3(priceFloor + APP_CONFIG.MIN_BID_INCREMENT)');
    expect(screen).toContain('allInFromDollars(priceFloor + APP_CONFIG.MIN_BID_INCREMENT)');
    expect(screen).toContain('nextBidAllIn:      listingAllInV3(priceFloor + APP_CONFIG.MIN_BID_INCREMENT)');
    expect(screen).not.toMatch(/MIN_BID_INCREMENT\)[^\n]*currentHighest|currentHighest \+ APP_CONFIG\.MIN_BID_INCREMENT/);
    expect(screen).toContain('myMaxBid < currentHighest;');
    expect(screen).toContain('const currentHighest = rt.currentBid;');
    expect(screen).toMatch(/loadFailed=\{!fixture && rt\.loadError\}/);
  });
});

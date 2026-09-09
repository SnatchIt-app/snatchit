/**
 * tests/home-header.test.ts — Home header + quick-filter bar.
 *
 * The scroll tests drive the SAME pure controller the screen uses
 * (src/lib/home/filterBarMachine), including the partial-collapse-then-reverse
 * case the owner hit on device. Source guards pin the three-control quick row,
 * the centred SN mark, the single market label, and that the bottom dock and the
 * full filter taxonomy are untouched.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import {
  initialFilterBarState,
  reduceFilterBarScroll,
  showFilterBar,
  HIDE_AFTER,
  HIDE_TRAVEL,
  SHOW_TRAVEL,
  TOP_RESET,
  type FilterBarState,
} from '../src/lib/home/filterBarMachine';
import {
  CHIP_GROUPS,
  DEFAULT_FILTERS,
  activeFilterCount,
  hasPriceFilter,
  hasSheetFilters,
  sheetFilterCount,
} from '../src/lib/home/filterModel';
import { CURRENT_MARKET, useCurrentMarket } from '../src/lib/market/currentMarket';
import { navItems } from '../src/lib/nav/navItems';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');

const run = (offsets: number[], from: FilterBarState = initialFilterBarState()) =>
  offsets.reduce((s, y) => reduceFilterBarScroll(s, y), from);

/** Shown, parked deep in the feed — the state a mid-feed reversal starts from. */
const deepShown = (y = 200): FilterBarState => ({ y, hidden: false, downAcc: 0, upAcc: 0 });
const deepHidden = (y = 300): FilterBarState => ({ y, hidden: true, downAcc: 0, upAcc: 0 });

describe('quick-filter bar controller', () => {
  it('1. is shown near the top', () => {
    expect(run([0]).hidden).toBe(false);
    expect(run([TOP_RESET]).hidden).toBe(false);
  });

  it('2. sustained downward travel hides it', () => {
    expect(run([0, HIDE_AFTER + 10, HIDE_AFTER + 10 + HIDE_TRAVEL + 5]).hidden).toBe(true);
  });

  it('3. upward travel shows it again mid-feed (no need to reach the top)', () => {
    const s = reduceFilterBarScroll(deepHidden(300), 300 - SHOW_TRAVEL - 2);
    expect(s.hidden).toBe(false);
    expect(s.y).toBeGreaterThan(TOP_RESET);
  });

  it('4. PARTIAL DOWN THEN UP: never sticks, and no stale travel is held', () => {
    // Down, but not far enough to hide.
    const partial = reduceFilterBarScroll(deepShown(200), 200 + HIDE_TRAVEL - 18);
    expect(partial.hidden).toBe(false);
    expect(partial.downAcc).toBeLessThan(HIDE_TRAVEL);

    // Reverse: the downward accumulator is dropped immediately.
    const reversed = reduceFilterBarScroll(partial, partial.y - 25);
    expect(reversed.hidden).toBe(false);
    expect(reversed.downAcc).toBe(0);

    // A later, genuine downward browse still hides normally (no corruption).
    const after = reduceFilterBarScroll(reversed, reversed.y + HIDE_TRAVEL + 5);
    expect(after.hidden).toBe(true);
  });

  it('5. COLLAPSED THEN SMALL UP: noise below the threshold does not show it', () => {
    let s = deepHidden(300);
    s = reduceFilterBarScroll(s, 295); // up 5
    s = reduceFilterBarScroll(s, 291); // up 4  (cumulative 9 < SHOW_TRAVEL)
    expect(s.hidden).toBe(true);
  });

  it('6. COLLAPSED THEN INTENTIONAL UP: returns predictably', () => {
    let s = deepHidden(300);
    s = reduceFilterBarScroll(s, 288); // up 12
    s = reduceFilterBarScroll(s, 278); // up 10 -> 22 >= SHOW_TRAVEL
    expect(s.hidden).toBe(false);
  });

  it('7. RAPID DIRECTION REVERSAL: down/up/down/up ends valid, accumulators clean', () => {
    let s = deepShown(200);
    s = reduceFilterBarScroll(s, 200 + HIDE_TRAVEL + 5); expect(s.hidden).toBe(true);
    s = reduceFilterBarScroll(s, s.y - SHOW_TRAVEL - 5);  expect(s.hidden).toBe(false);
    s = reduceFilterBarScroll(s, s.y + HIDE_TRAVEL + 5);  expect(s.hidden).toBe(true);
    s = reduceFilterBarScroll(s, s.y - SHOW_TRAVEL - 5);  expect(s.hidden).toBe(false);
    expect(s.downAcc).toBe(0);
    expect(s.upAcc).toBe(0);
  });

  it('8. TOP RESET: returning near the top always shows it', () => {
    expect(reduceFilterBarScroll(deepHidden(500), 0).hidden).toBe(false);
    expect(showFilterBar(deepHidden(500)).hidden).toBe(false);
  });

  it('9. negative iOS overscroll stays shown', () => {
    expect(reduceFilterBarScroll(deepHidden(300), -80).hidden).toBe(false);
  });

  it('10. empty / short feed is stable: repeated zero offsets never toggle or loop', () => {
    let s = initialFilterBarState();
    for (let i = 0; i < 25; i++) s = reduceFilterBarScroll(s, 0);
    expect(s.hidden).toBe(false);
    expect(s.downAcc).toBe(0);
  });

  it('jitter below the deadband never accumulates toward a threshold', () => {
    let s = deepShown(200);
    for (let i = 0; i < 40; i++) s = reduceFilterBarScroll(s, 200 + (i % 2 ? 1 : 0));
    expect(s.hidden).toBe(false);
  });

  it('showing costs less travel than hiding (responsive return)', () => {
    expect(SHOW_TRAVEL).toBeLessThan(HIDE_TRAVEL);
  });
});

describe('filter model', () => {
  it('12/13. the sheet owns the taxonomy; All is not a control', () => {
    const keys = CHIP_GROUPS.flatMap((g) => g.options.map((o) => o.key));
    expect(keys).toEqual(expect.arrayContaining(['buy_now', 'auction', 'ga', 'vip', 'ended', 'recently_sold']));
    expect(keys).not.toContain('all');        // the unfiltered feed IS "all"
    expect(keys).not.toContain('your_scene'); // it has its own quick control
  });

  it('active-state helpers do not double-count price or your scene', () => {
    const f = { ...DEFAULT_FILTERS, priceMin: '20', chip: 'your_scene' as const };
    expect(hasPriceFilter(f)).toBe(true);
    expect(sheetFilterCount(f)).toBe(0);   // price + your scene have own controls
    expect(hasSheetFilters(f)).toBe(false);
    expect(activeFilterCount(f)).toBe(2);  // but both still count as "filtered"
    const g = { ...DEFAULT_FILTERS, chip: 'ga' as const, categories: new Set(['music']) };
    expect(sheetFilterCount(g)).toBe(2);
  });
});

describe('Home — shipped-source guards', () => {
  const header = read('src/components/discovery/HomeHeader.tsx');
  const home = read('app/(tabs)/home.tsx');
  const sheet = read('src/components/discovery/FilterSheet.tsx');

  it('12. exactly three quick controls', () => {
    const labels = [...home.matchAll(/<Chip\s+label="([^"]+)"/g)].map((m) => m[1]);
    expect(labels).toEqual(['Your scene', 'Price', 'Filters']);
  });

  it('13/14. removed chips are gone from Home but live in the sheet', () => {
    for (const gone of ['label="All"', 'label="Clear"', 'label="GA"', 'label="VIP"', 'label="Buy now"', 'label="Auction"']) {
      expect(home).not.toContain(gone);
    }
    expect(sheet).toContain('CHIP_GROUPS');
    expect(sheet).toContain('onApply({ chip,'); // the sheet applies the taxonomy
    expect(sheet).toContain('setChip(\'all\')'); // Clear/reset lives in the sheet
  });

  it('PRICE opens the existing sheet directly on the price section', () => {
    expect(home).toContain("setSheetFocus('price')");
    expect(home).toContain('focus={sheetFocus}');
    // FILTERS opens the same sheet, unfocused
    expect(home).toContain('setSheetFocus(undefined)');
    // one sheet, one state — no second price implementation
    expect((home.match(/<FilterSheet/g) ?? []).length).toBe(1);
    expect(sheet).toContain("focus !== 'price'");
    expect(sheet).toContain('scrollRef.current?.scrollTo');
  });

  it('11. hidden controls are not tappable or focusable', () => {
    expect(home).toMatch(/pointerEvents=\{filterBar\.hidden \? 'none' : 'auto'\}/);
    expect(home).toContain('accessibilityElementsHidden={filterBar.hidden}');
  });

  it('the bar is a transform overlay, not an animated layout height', () => {
    expect(home).toContain('useNativeDriver: true');
    expect(home).toContain('translateY');
    expect(home).toContain("position: 'absolute'");
    // the feed's own layout must not be animated during the gesture
    expect(home).not.toMatch(/height: filterAnim/);
    expect(home).not.toMatch(/useNativeDriver: false/);
  });

  it('uses its own controller, not the dock machine', () => {
    expect(home).toContain('reduceFilterBarScroll');
    expect(home).not.toContain('reduceDockScroll');
  });

  it('SN mark stays centred to the screen and there is one market label', () => {
    expect(header).toContain('markRow: { alignItems: \'center\' }');
    expect(header).toContain('useCurrentMarket');
    expect(header).not.toMatch(/['"]Miami['"]/);
    expect(home).not.toMatch(/['"]Miami['"]/);
    expect(header).toContain("textStyle('micro')");
    expect(header).toContain('place: { color: v2.brand.red }');
  });

  it('search preserved on Home, not a primary destination', () => {
    expect(header).toContain('glyph="search"');
    expect(home).toContain("router.push('/(tabs)/explore')");
    expect(navItems({ tickets: true }).map((i) => i.key)).not.toContain('search');
  });

  it('reduced motion handled, no new animation library', () => {
    expect(home).toContain('useReducedMotion');
    expect(home).toMatch(/duration: reduceMotion \? 0/);
    expect(home).not.toMatch(/react-native-reanimated|moti|lottie/);
  });

  it('15. the bottom dock is untouched and still fed by Home', () => {
    expect(home).toContain("useDockScroll('home')");
    expect(home).toContain('onHomeScroll(e)');
    expect(navItems({ tickets: true }).map((i) => i.key))
      .toEqual(['home', 'create', 'bids', 'tickets', 'profile']);
  });

  it('market value drives the label', () => {
    expect(CURRENT_MARKET.label).toBe('Miami');
    expect(useCurrentMarket()).toEqual(CURRENT_MARKET);
  });
});

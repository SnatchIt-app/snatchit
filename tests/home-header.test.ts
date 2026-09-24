/**
 * tests/home-header.test.ts — the Home header and the one filter control on it.
 *
 * RETARGETED 2026-09-24 (B's H1 at pin 911f65fd, under the owner's ruling "preserve useful filter
 * functionality, but propose its placement within the approved Home composition"). B's finding: the
 * quick-filter chip row "is not in the approved Home composition at all — the board goes header →
 * section heading → feature." Deleting the functionality was explicitly not an option either, so the
 * three controls collapse into ONE on the header line, and everything they reached moves inside the
 * sheet that already owned the rest of the taxonomy:
 *
 *   Your scene → a sheet group of its own (it selects `chip`, so it belongs in that single-select
 *                family rather than beside the neighbourhood multi-select)
 *   Price      → the sheet's price section, which already existed
 *   Filters    → the header control, now signalling EVERY active filter, since it is the only one
 *
 * With no floating bar there is nothing to hide on scroll, so `src/lib/home/filterBarMachine` and
 * the thirteen scroll-controller tests that drove it are gone with it: the machine existed only to
 * keep an overlay out of the way. The dock's own scroll machine is untouched and is now the feed's
 * only scroll consumer.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

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

describe('filter model', () => {
  it('12/13. the sheet owns the taxonomy; All is not a control', () => {
    const keys = CHIP_GROUPS.flatMap((g) => g.options.map((o) => o.key));
    expect(keys).toEqual(expect.arrayContaining(['buy_now', 'auction', 'ga', 'vip', 'ended', 'recently_sold']));
    expect(keys).not.toContain('all');        // the unfiltered feed IS "all"
    // RETARGETED: `your_scene` no longer has a control of its own, so the sheet must offer it —
    // and it must sit in THIS single-select family, because it selects the same `chip` field.
    expect(keys).toContain('your_scene');
    // One option per key: a chip that appeared in two groups could be cleared by the wrong one.
    expect(new Set(keys).size).toBe(keys.length);
  });

  it('the one control signals every active filter — nothing is silently on', () => {
    // RETARGETED: the count used to exclude price and your scene BECAUSE they had their own
    // controls. They do not any more, so a filter the header does not count is a filter the user
    // cannot see is applied.
    const f = { ...DEFAULT_FILTERS, priceMin: '20', chip: 'your_scene' as const };
    expect(hasPriceFilter(f)).toBe(true);
    expect(sheetFilterCount(f)).toBe(2);
    expect(hasSheetFilters(f)).toBe(true);
    // Both bounds of one price range are still ONE filter on the control.
    expect(sheetFilterCount({ ...DEFAULT_FILTERS, priceMin: '20', priceMax: '80' })).toBe(1);
    const g = { ...DEFAULT_FILTERS, chip: 'ga' as const, categories: new Set(['music']) };
    expect(sheetFilterCount(g)).toBe(2);
    // Nothing selected reads as nothing selected, in both helpers.
    expect(sheetFilterCount(DEFAULT_FILTERS)).toBe(0);
    expect(hasSheetFilters(DEFAULT_FILTERS)).toBe(false);
    // activeFilterCount drives the EMPTY-state copy and still counts each bound separately.
    expect(activeFilterCount(f)).toBe(2);
  });
});

describe('Home — shipped-source guards', () => {
  const header = read('src/components/discovery/HomeHeader.tsx');
  const home = read('app/(tabs)/home.tsx');
  const sheet = read('src/components/discovery/FilterSheet.tsx');

  it("H1: ONE filter control, and it is on the header line — not a row in the feed's composition", () => {
    // B's H1 at 911f65fd: "the filter-chip row is not in the approved Home composition at all."
    expect([...home.matchAll(/<Chip\s+label="([^"]+)"/g)].map((m) => m[1])).toEqual([]);
    expect(home).not.toContain('quickRow');
    /*
     * The owner's acceptance terms (2026-09-24): always visible, visually quiet, the count when
     * applicable, and — their caution — "a search glyph must not unexpectedly become a Filters
     * action". So the header carries TWO controls of equal weight with DIFFERENT marks: the magnifier
     * opens Search, the filter mark opens the sheet in place. Neither is a bordered pill.
     */
    expect(header).toMatch(/glyph="filter"/);
    expect(header).toMatch(/glyph="search"/);
    expect(header).not.toMatch(/<Chip/);
    // Always rendered — the entry point is never hidden, whether or not filters are active.
    expect(header).not.toMatch(/filterCount > 0 \? \(?\s*<IconButton/);
    // The count rides on the control, and the spoken name carries it too.
    expect(header).toMatch(/count=\{filterCount/);
    expect(header).toMatch(/accessibilityLabel=\{filterCount > 0 \? `Filters, \$\{filterCount\} active` : 'Filters'\}/);
    expect(home).toMatch(/<HomeHeader[\s\S]*?onFilters=\{/);
    expect(home).toMatch(/<HomeHeader[\s\S]*?filterCount=\{/);
    // Nothing floats over the feed any more, and the feed carries no inset for a bar.
    expect(home).not.toContain('filterBarHeight');
    expect(home).not.toContain('Animated.View');
    expect(home).not.toContain("position: 'absolute'");
  });

  it('H1c: the two marks are distinct, and each says what it opens', () => {
    const icon = read('src/components/ui/IconButton.tsx');
    const glyphs = Object.fromEntries([...icon.matchAll(/^\s{2}(\w+): ('[^']*'|"[^"]*"),/gm)].map((m) => [m[1], m[2]]));
    expect(glyphs.search, 'the search mark').toBeDefined();
    expect(glyphs.filter, 'the filter mark').toBeDefined();
    expect(glyphs.filter).not.toBe(glyphs.search);
    // Search leaves for the Search screen; Filters opens the sheet where the user already is.
    expect(home).toMatch(/onSearch=\{\(\) => router\.push\('\/\(tabs\)\/explore'\)\}/);
    expect(home).toMatch(/onFilters=\{\(\) => setModalOpen\(true\)\}/);
  });

  it('H1b: the composition the board draws is what remains — header, then headings and rows', () => {
    // The order in source is the order the screen paints: header first, then the list.
    expect(home.indexOf('<HomeHeader')).toBeLessThan(home.indexOf('<FlatList'));
    // The section heading and the feature are the list's own content, unchanged by this move.
    expect(home).toContain('accessibilityRole="header"');
    expect(home).toContain('<HomeFeature');
  });

  it('13/14. removed chips are gone from Home but live in the sheet', () => {
    for (const gone of ['label="All"', 'label="Clear"', 'label="GA"', 'label="VIP"', 'label="Buy now"', 'label="Auction"']) {
      expect(home).not.toContain(gone);
    }
    expect(sheet).toContain('CHIP_GROUPS');
    expect(sheet).toContain('onApply({ chip,'); // the sheet applies the taxonomy
    expect(sheet).toContain('setChip(\'all\')'); // Clear/reset lives in the sheet
  });

  it('everything the removed controls reached is still reachable, through the one sheet', () => {
    // Price: the sheet's own section, with the focus capability it always had (nothing on Home
    // focuses it now, and the sheet is still the only price implementation).
    expect((home.match(/<FilterSheet/g) ?? []).length).toBe(1);
    expect(sheet).toContain("focus !== 'price'");
    expect(sheet).toContain('scrollRef.current?.scrollTo');
    expect(sheet).toMatch(/Price/);
    // Your scene: a sheet group, so tapping it still selects the same `chip` the quick control set.
    expect(sheet).toContain('CHIP_GROUPS');
    expect(read('src/lib/home/filterModel.ts')).toContain("key: 'your_scene'");
    // The lazy sold/ended datasets still load on selection — that was the quick row's other job.
    expect(home).toMatch(/onFiltersApply[\s\S]*?fetchSoldListings\(\)/);
    expect(home).toMatch(/onFiltersApply[\s\S]*?fetchEndedListings\(\)/);
  });

  it('the filter-bar machine is gone, and the dock keeps its own', () => {
    expect(home).not.toContain('reduceFilterBarScroll');
    expect(home).not.toContain('filterBarMachine');
    expect(() => read('src/lib/home/filterBarMachine.ts')).toThrow();
    // The dock's scroll machine is untouched and is the feed's only scroll consumer.
    expect(home).toContain("useDockScroll('home')");
    expect(home).not.toContain('reduceDockScroll');
  });

  it('V3: the SN mark is LEFT-ALIGNED on one line with search, and no market label is drawn', () => {
    /*
     * RETARGETED (owner 2026-09-24). This used to pin the mark CENTRED to the screen on its own
     * line with the market label and search below it. The owner's finding on the implemented Home
     * is that this V2 centred-logo composition had been retained instead of the approved V3 header
     * drawn on `pkg8-home-dark.png`: one line, the SN mark left-aligned to the gutter, the search
     * control right. The pin follows the approved board.
     */
    expect(header).toContain("flexDirection: 'row'");
    expect(header).toContain("justifyContent: 'space-between'");
    expect(header).not.toContain('markRow');
    // No second line, and no market label on it. The market module itself is untouched.
    expect(header).not.toContain('useCurrentMarket');
    expect(header).not.toContain('metaRow');
    expect(header).not.toMatch(/['"]Miami['"]/);
    expect(home).not.toMatch(/['"]Miami['"]/);
    // The mark is still the official asset, tinted so it survives Daylight's white canvas.
    expect(header).toContain("require('@/brand/sn-logo-white.png')");
    expect(header).toContain('tintColor: p.text.primary');
  });

  it('search preserved on Home, not a primary destination', () => {
    expect(header).toContain('glyph="search"');
    expect(home).toContain("router.push('/(tabs)/explore')");
    expect(navItems({ tickets: true }).map((i) => i.key)).not.toContain('search');
  });

  it('no animation library, and no animation left to reduce', () => {
    // RETARGETED: `useReducedMotion` was here for the bar's slide. With the bar gone Home animates
    // nothing, which is the strongest form of the same guarantee.
    expect(home).not.toContain('Animated');
    expect(home).not.toContain('useReducedMotion');
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

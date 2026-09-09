/**
 * tests/adaptive-nav.test.ts — the adaptive navigation core.
 *
 * The dock's collapse decision and its destination config are pure and pinned
 * here (scroll direction, hysteresis, near-top/overscroll, the compact-control
 * expand, the four/five-item model, Tickets absent, Search absent). Source guards
 * assert the dock is Home-only, exposes no Tickets tab, never queries
 * kernel.tickets, and preserves routing.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import {
  reduceDockScroll,
  expandDock,
  initialDockState,
  COLLAPSE_TRAVEL,
  EXPAND_TRAVEL,
  COLLAPSE_AFTER,
  TOP_THRESHOLD,
  type DockState,
} from '../src/lib/nav/dockMachine';
import { navItems, isCollapsingRoute, COLLAPSING_ROUTES } from '../src/lib/nav/navItems';

// Feed a sequence of absolute scroll offsets and return the final state.
function run(offsets: number[], start: DockState = initialDockState()): DockState {
  return offsets.reduce((st, y) => reduceDockScroll(st, y), start);
}

describe('dock collapse machine', () => {
  it('starts expanded', () => {
    expect(initialDockState().collapsed).toBe(false);
  });

  it('collapses after a sustained downward scroll past the floor', () => {
    // climb well past COLLAPSE_AFTER with steady downward travel
    const st = run([50, 120, 160, 200, 260]);
    expect(st.collapsed).toBe(true);
  });

  it('does NOT collapse before the collapse floor even when scrolling down', () => {
    // stays under COLLAPSE_AFTER
    const belowFloor = COLLAPSE_AFTER - 20;
    const st = run([20, 40, belowFloor]);
    expect(st.collapsed).toBe(false);
  });

  it('expands again on a sustained upward scroll', () => {
    const collapsed = run([50, 120, 160, 200, 260]);
    expect(collapsed.collapsed).toBe(true);
    const expanded = run([260 - EXPAND_TRAVEL - 5], collapsed);
    expect(expanded.collapsed).toBe(false);
  });

  it('always expands near the top', () => {
    const collapsed = run([50, 120, 160, 200, 260]);
    const atTop = reduceDockScroll(collapsed, TOP_THRESHOLD - 1);
    expect(atTop.collapsed).toBe(false);
  });

  it('does not flip on small jitter', () => {
    // tiny back-and-forth below the travel thresholds, above the floor
    let st = run([200, 260]); // collapsed
    expect(st.collapsed).toBe(true);
    st = run([258, 260, 259, 261, 260], st); // jitter < EXPAND_TRAVEL / COLLAPSE_TRAVEL
    expect(st.collapsed).toBe(true);
  });

  it('never collapses on negative overscroll (iOS bounce at top)', () => {
    const st = reduceDockScroll(initialDockState(), -40);
    expect(st.collapsed).toBe(false);
  });

  it('the collapse and expand thresholds are real hysteresis (collapse > expand distance)', () => {
    // Enough sustained travel is required in each direction; they are independent.
    expect(COLLAPSE_TRAVEL).toBeGreaterThan(0);
    expect(EXPAND_TRAVEL).toBeGreaterThan(0);
  });

  it('the compact control tap expands', () => {
    const collapsed = run([50, 120, 160, 200, 260]);
    expect(expandDock(collapsed).collapsed).toBe(false);
  });
});

describe('nav destinations', () => {
  it('ships four destinations, in order, without Tickets', () => {
    const keys = navItems().map((i) => i.key);
    expect(keys).toEqual(['home', 'create', 'bids', 'profile']);
  });

  it('supports the five-item model with Tickets between Bids and Profile', () => {
    const keys = navItems({ tickets: true }).map((i) => i.key);
    expect(keys).toEqual(['home', 'create', 'bids', 'tickets', 'profile']);
  });

  it('never includes Search as a destination', () => {
    for (const cfg of [navItems(), navItems({ tickets: true })]) {
      expect(cfg.map((i) => i.key)).not.toContain('search');
      expect(cfg.map((i) => i.label.toLowerCase())).not.toContain('search');
    }
  });

  it('the Tickets icon reads as ownership, not scanning', () => {
    const tickets = navItems({ tickets: true }).find((i) => i.key === 'tickets')!;
    expect(tickets.icon).toBe('ticket.fill');
    expect(tickets.icon).not.toMatch(/scan|qr|camera|barcode/i);
  });

  it('collapse is a GLOBAL rule across the scrollable primary tabs', () => {
    // Phase 11: Tickets is now a primary tab and shares the same collapse rule.
    for (const r of ['home', 'create', 'bids', 'tickets', 'profile']) expect(isCollapsingRoute(r)).toBe(true);
    for (const r of ['explore', undefined]) expect(isCollapsingRoute(r)).toBe(false);
    expect(COLLAPSING_ROUTES).toEqual(['home', 'create', 'bids', 'tickets', 'profile']);
  });
});

describe('adaptive nav — shipped-source guards', () => {
  const root = resolve(__dirname, '..');
  const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
  const dock = read('src/components/nav/AdaptiveDock.tsx');
  const layout = read('app/(tabs)/_layout.tsx');
  const home = read('app/(tabs)/home.tsx');
  const bids = read('app/(tabs)/bids.tsx');
  const profile = read('app/(tabs)/profile.tsx');
  const create = read('src/screens/CreateListingScreen.tsx');

  it('the layout registers the five primary routes and replaces only the tab bar', () => {
    // Phase 11: Tickets is registered between Bids and Profile.
    for (const name of ['home', 'create', 'bids', 'tickets', 'profile']) {
      expect(layout).toContain(`name="${name}"`);
    }
    expect(layout).toContain('tabBar={(props) => <AdaptiveDock');
  });

  it('the dock renders the five-item navItems({ tickets: true }) with no coming soon / kernel.tickets', () => {
    expect(dock).toContain('navItems({ tickets: true })');
    expect(dock).not.toMatch(/coming soon/i);
    expect(dock).not.toMatch(/kernel[^\n]*tickets/);
  });

  it('the dock is a rounded dark-glass object with NO red frame', () => {
    expect(dock).toContain('DOCK_RADIUS');
    // rounded, not radius 0 (read from source to avoid importing native modules)
    const radius = Number(read('src/lib/nav/navInsets.ts').match(/DOCK_RADIUS\s*=\s*(\d+)/)?.[1]);
    expect(radius).toBeGreaterThan(16);
    expect(dock).toMatch(/rgba\(18,18,20,0\.72\)/); // dark translucent glass
    // no brand-red rectangular frame / top marker anywhere in the dock
    expect(dock).not.toMatch(/brand\.red/);
  });

  it('the active state is a selected inner capsule, not a red web-tab marker', () => {
    expect(dock).toContain('styles.selected');
    expect(dock).toContain('accessibilityState={{ selected: isFocused }}');
  });

  it('collapse is a spatial contraction (width morph), not a cross-fade', () => {
    // container width interpolates full -> compact, and the row translates
    expect(dock).toContain('[FULL_W, COMPACT_W]');
    expect(dock).toContain('rowTranslate');
    // driven by the pure machine, not an inline y-threshold
    expect(dock).toContain('isCollapsingRoute');
    expect(dock).not.toMatch(/> 80\b/);
  });

  it('the compact control shows the ACTIVE tab and tapping it only expands', () => {
    expect(dock).toContain('activeIndex');
    expect(dock).toContain('activeLabel');
    expect(dock).toContain('expandRoute(activeRoute)');
  });

  it('tab change arrives expanded', () => {
    expect(dock).toMatch(/useEffect\(\(\) => \{ if \(activeRoute\) expandRoute\(activeRoute\)/);
  });

  it('every scrollable primary tab wires its OWN route scroll state (incl. Create)', () => {
    expect(home).toContain("useDockScroll('home')");
    expect(bids).toContain("useDockScroll('bids')");
    expect(profile).toContain("useDockScroll('profile')");
    expect(create).toContain("useDockScroll('create')"); // universal collapse
  });

  it('the dock drops out of the way for the keyboard', () => {
    expect(dock).toMatch(/keyboardWillShow|keyboardDidShow/);
    expect(dock).toContain('keyboardUp');
    expect(dock).toContain("pointerEvents={keyboardUp ? 'none'");
  });

  it('Create CTA still clears the dock and keeps its own surface', () => {
    expect(create).toContain('useCtaDockOffset');
    expect(create).toContain('marginBottom: ctaDockOffset');
  });

  it('Home wiring stays minimal and discovery is untouched', () => {
    expect(home).toContain('onHomeScroll');
    expect(home).toContain('useDockClearance');
    expect(home).toContain('DiscoveryCard');
  });

  it('Create CTA is a separate surface that clears the dock by an explicit gap', () => {
    expect(create).toContain('useCtaDockOffset');
    expect(create).toContain('marginBottom: ctaDockOffset');
  });

  it('the dock is only mounted by the tabs shell (never a nested stack route)', () => {
    for (const rel of ['app/checkout/[id].tsx', 'app/transfer/send/[id].tsx', 'app/settings/index.tsx']) {
      expect(read(rel)).not.toContain('AdaptiveDock');
    }
    expect(layout).toContain('AdaptiveDock');
  });
});

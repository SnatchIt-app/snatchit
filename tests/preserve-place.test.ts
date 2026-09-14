/**
 * tests/preserve-place.test.ts — the user's place survives a refresh (CFT-107,
 * first slice).
 *
 * Two ways the feeds lost the user's place: Tickets unmounted its SectionList on
 * every refocus (the loading phase, closed by CFT-103), and Home's realtime
 * INSERT prepends a listing, which shifted whatever the user was reading by a
 * row. Source guards, because both are properties of the shipped list props;
 * the realtime handlers themselves are pinned verbatim so that "no change" is
 * checked rather than assumed.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
const code = (rel: string) =>
  read(rel)
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/.*$/gm, '$1');

describe('tickets — the list stays mounted across tab switches', () => {
  const screen = code('app/(tabs)/tickets.tsx');
  const layout = code('app/(tabs)/_layout.tsx');

  it('renders one SectionList, gated on the phase and the rows only', () => {
    expect(screen.match(/<SectionList/g) ?? []).toHaveLength(1);
    const branch = screen.slice(screen.indexOf("phase === 'loading' ? ("), screen.indexOf('<SectionList'));
    // The only things that can replace the list are a first-load state or an
    // empty result — never the refreshing flag, which drives RefreshControl.
    expect(branch).not.toMatch(/refreshing/);
    expect(branch).toMatch(/sections\.length === 0 \?/);
  });

  it('never re-enters the loading phase over rows, so a refocus is not a remount', () => {
    expect(screen).toMatch(/if \(shouldShowLoading\([^)]*\)\) setPhase\('loading'\)/);
    expect(screen.match(/setPhase\('loading'\)/g) ?? []).toHaveLength(1);
    expect(screen).toMatch(/useFocusEffect\(useCallback\(\(\) => \{ load\(\); \}, \[load\]\)\)/);
  });

  it('is not unmounted or reset by the tab navigator on blur', () => {
    expect(layout).not.toMatch(/unmountOnBlur/);
    expect(layout).not.toMatch(/popToTopOnBlur/);
    expect(layout).not.toMatch(/freezeOnBlur/);
  });
});

describe('home — an insert at the top does not move what is on screen', () => {
  const home = code('app/(tabs)/home.tsx');

  it('anchors the visible content on the feed list', () => {
    const list = home.slice(home.indexOf('<FlatList'), home.indexOf('renderItem={'));
    expect(list).toMatch(/maintainVisibleContentPosition=\{\{ minIndexForVisible: 0 \}\}/);
    expect(home.match(/maintainVisibleContentPosition/g) ?? []).toHaveLength(1);
  });

  it('keeps the realtime INSERT prepend exactly as it was', () => {
    expect(home).toContain(".channel('home-listings-feed')");
    expect(home).toContain("{ event: 'INSERT', schema: 'public', table: 'listings' }");
    expect(home).toContain("if (payload.new.status !== 'active') return;");
    expect(home).toContain('setAllListings(prev => [nl, ...prev]);');
  });

  it('keeps every realtime removal exactly as it was', () => {
    expect(home).toContain("{ event: 'UPDATE', schema: 'public', table: 'listings' }");
    const update = home.slice(home.indexOf("event: 'UPDATE'"), home.indexOf('.subscribe()'));
    // Blocked seller, sold, and any non-active status each drop the row.
    expect(update).toContain('if (updated.seller_id && blockedIdsRef.current.has(updated.seller_id)) {');
    expect(update).toContain("if (updated.status === 'sold') {");
    expect(update).toContain("if (updated.status && updated.status !== 'active') {");
    expect(update.match(/setAllListings\(prev => prev\.filter\(l => l\.id !== updated\.id\)\);/g) ?? []).toHaveLength(3);
    // ...and an in-place update patches rather than re-orders.
    expect(update).toContain('setAllListings(prev => prev.map(l => l.id === updated.id ? { ...l, ...updated } : l));');
  });
});

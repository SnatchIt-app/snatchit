/**
 * The four date-only labels read New York's calendar, never the phone's (owner, 2026-11-02: Snatch It operates in
 * Eastern Time; A's rulings, A/TIMEZONE-DECISION-20261102.md). Each site keeps its own visible format — only the
 * calendar it reads changes:
 *
 *   D1  app/(tabs)/bids.tsx             whenLabel      auction end in a Bid row's spoken label   "Nov 2"
 *   D2  app/profile/[id].tsx            memberSince    the public profile's trust row            "October 2026"
 *   D3  app/settings/blocked-users.tsx  blockedOnLabel the blocked list's meta line              "Blocked 11/2/2026"
 *   D4  src/components/SellerListingCard soldOnLabel   a sold row's meta line on My listings     "Sold Mon 2 Nov"
 *
 * Dates only, no clock — so no EST / EDT label is shown at any of them.
 *
 * Every case runs with the process zone set to UTC, America/Los_Angeles and America/New_York in turn and must give
 * the same answer. Each anchor carries a WITNESS: the device-zone reading of the same instant really is a different
 * day there, so a helper that fell back to the phone's calendar could not pass.
 *
 * Anchors (A): 2026-11-02 04:59:59Z | 05:00:00Z (ET midnight in EST); 2026-11-01 03:59:59Z | 04:00:00Z (ET midnight
 * in EDT); the 25-hour 2026-11-01 (01:30 EDT at 05:30Z, 01:30 EST at 06:30Z); the 23-hour 2026-03-08; and the
 * evening 2026-11-03T02:14Z (Mon 2 Nov 21:14 EST = Mon 18:14 LA = Tue 02:14 UTC).
 *
 * Negative controls (run by hand, each must FAIL): put each site's device-zone code back (toLocaleDateString with no
 * timeZone, or the Date's local getters) — D1–D4 fail under the UTC and LA process zones.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { afterEach, describe, expect, it, vi } from 'vitest';

// The four modules are imported for their pure helpers; their render-only and network imports are stubbed (vi.mock
// hoists above the imports) so nothing here parses react-native's Flow sources or reaches a client.
vi.mock('react-native', () => ({
  FlatList: 'FlatList', Pressable: 'Pressable', RefreshControl: 'RefreshControl', ScrollView: 'ScrollView',
  Text: 'Text', View: 'View', Alert: { alert: () => {} },
  StyleSheet: { create: <T,>(s: T) => s, hairlineWidth: 1 },
  useWindowDimensions: () => ({ width: 393, height: 852, scale: 3, fontScale: 1 }),
  AccessibilityInfo: { announceForAccessibility: () => {} },
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios ?? o.default },
}));
vi.mock('expo-image', () => ({ Image: 'Image' }));
vi.mock('expo-router', () => ({ router: { push: () => {} }, useLocalSearchParams: () => ({ id: 'fixture' }) }));
vi.mock('@react-navigation/native', () => ({ useFocusEffect: () => {} }));
vi.mock('@/src/lib/supabase', () => ({
  supabase: new Proxy({}, { get() { throw new Error('a date label must not touch supabase'); } }),
}));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: null, session: null }) }));
vi.mock('@/src/hooks/useNetworkStatus', () => ({ useNetworkStatus: () => ({ isOffline: false }) }));
vi.mock('@/src/lib/coverImage', () => ({ getCoverImageUrl: () => null }));
vi.mock('@/src/lib/avatarImage', () => ({ getAvatarUrl: () => null }));
vi.mock('@/src/components/ScreenState', () => ({ default: 'ScreenState' }));
vi.mock('@/src/components/ui', () => ({
  Badge: 'Badge', Button: 'Button', Chip: 'Chip', EmptyState: 'EmptyState', Skeleton: 'Skeleton', Spinner: 'Spinner', Tappable: 'Tappable',
}));
vi.mock('@/src/components/nav/dockContext', () => ({ useDockScroll: () => ({ onScroll: () => {}, expand: () => {} }) }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useDockClearance: () => 0, useTopInset: () => 0 }));
vi.mock('@/src/components/bids/BidCard', () => ({ BidCard: 'BidCard', BID_ROW_ART_H: 72, BID_ROW_ART_W: 58 }));
vi.mock('@/src/components/media/EventMedia', () => ({ EventMedia: 'EventMedia' }));
vi.mock('@/src/components/NameText', () => ({ NameText: 'NameText' }));
vi.mock('@/src/components/VerifiedSellerBadge', () => ({ default: 'VerifiedSellerBadge' }));
vi.mock('@/src/components/account/AccountSection', () => ({ AccountSection: 'AccountSection' }));
vi.mock('@/src/components/account/SettingsHeader', () => ({ SettingsHeader: 'SettingsHeader' }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3, AMOUNT_MIN_FONT_SCALE: 0.6 }));
vi.mock('@/src/theme/appearance', () => ({ useTheme: () => ({ scheme: 'dark', palette: {} }) }));

import { whenLabel } from '@/app/(tabs)/bids';
import { memberSince } from '@/app/profile/[id]';
import { blockedOnLabel } from '@/app/settings/blocked-users';
import { soldOnLabel } from '@/src/components/SellerListingCard';

const ZONES = ['UTC', 'America/Los_Angeles', 'America/New_York'] as const;
const original = process.env.TZ;
afterEach(() => { if (original === undefined) delete process.env.TZ; else process.env.TZ = original; });

/** Runs `fn` under each process zone and returns the answer, which must be the same under all three. */
function underEveryZone<T>(fn: () => T): T {
  const answers = ZONES.map((z) => { process.env.TZ = z; return fn(); });
  for (const a of answers) expect(a).toEqual(answers[0]);
  return answers[0];
}
/** The device-zone calendar day of an instant, as the old code read it: 'YYYY-MM-DD Www'. */
function deviceDay(iso: string, zone: string): string {
  process.env.TZ = zone;
  const d = new Date(iso);
  const wd = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][d.getDay()];
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')} ${wd}`;
}

const read = (p: string) => readFileSync(resolve(__dirname, '..', p), 'utf8');
const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

describe('D1 — a Bid row speaks the auction end as New York\'s month and day', () => {
  it('ET midnight in EST (2026-11-02 05:00Z) and in EDT (2026-11-01 04:00Z), the evening anchor, the 23-hour day', () => {
    expect(underEveryZone(() => whenLabel('2026-11-02T04:59:59Z'))).toBe('Nov 1');
    expect(underEveryZone(() => whenLabel('2026-11-02T05:00:00Z'))).toBe('Nov 2');
    expect(underEveryZone(() => whenLabel('2026-11-01T03:59:59Z'))).toBe('Oct 31');
    expect(underEveryZone(() => whenLabel('2026-11-01T04:00:00Z'))).toBe('Nov 1');
    expect(underEveryZone(() => whenLabel('2026-11-03T02:14:00Z'))).toBe('Nov 2');
    expect(underEveryZone(() => whenLabel('2026-03-09T03:59:59Z'))).toBe('Mar 8');
    expect(underEveryZone(() => whenLabel('2026-03-09T04:00:00Z'))).toBe('Mar 9');
    // Witness: the phone's calendar disagrees at these instants.
    expect(deviceDay('2026-11-02T04:59:59Z', 'UTC')).toBe('2026-11-02 Mon');
    expect(deviceDay('2026-11-02T05:00:00Z', 'America/Los_Angeles')).toBe('2026-11-01 Sun');
    expect(deviceDay('2026-11-03T02:14:00Z', 'UTC')).toBe('2026-11-03 Tue');
  });

  it('no date, or an unreadable one, is no label', () => {
    expect(underEveryZone(() => whenLabel(undefined))).toBe('');
    expect(underEveryZone(() => whenLabel('not-a-date'))).toBe('');
  });
});

describe('D2 — "Member since" is New York\'s month and year', () => {
  it('the month and the year turn at New York\'s midnight', () => {
    expect(underEveryZone(() => memberSince('2026-11-01T03:59:59Z'))).toBe('October 2026');
    expect(underEveryZone(() => memberSince('2026-11-01T04:00:00Z'))).toBe('November 2026');
    expect(underEveryZone(() => memberSince('2027-01-01T04:59:59Z'))).toBe('December 2026');
    expect(underEveryZone(() => memberSince('2027-01-01T05:00:00Z'))).toBe('January 2027');
    expect(deviceDay('2026-11-01T03:59:59Z', 'UTC')).toBe('2026-11-01 Sun');
    expect(deviceDay('2026-11-01T04:00:00Z', 'America/Los_Angeles')).toBe('2026-10-31 Sat');
    expect(deviceDay('2027-01-01T04:59:59Z', 'UTC')).toBe('2027-01-01 Fri');
    expect(deviceDay('2027-01-01T05:00:00Z', 'America/Los_Angeles')).toBe('2026-12-31 Thu');
  });

  it('no date, or an unreadable one, keeps the dash', () => {
    expect(underEveryZone(() => memberSince(null))).toBe('—');
    expect(underEveryZone(() => memberSince('not-a-date'))).toBe('—');
  });
});

describe('D3 — the blocked list dates a block on New York\'s calendar, in a fixed M/D/YYYY', () => {
  it('ET midnight, the evening anchor, the year boundary', () => {
    expect(underEveryZone(() => blockedOnLabel('2026-11-02T04:59:59Z'))).toBe('Blocked 11/1/2026');
    expect(underEveryZone(() => blockedOnLabel('2026-11-02T05:00:00Z'))).toBe('Blocked 11/2/2026');
    // daylight time too (EDT midnight is 04:00Z): a fixed −05:00 rewrite would put these a day apart (review of 1d054bad)
    expect(underEveryZone(() => blockedOnLabel('2026-11-01T03:59:59Z'))).toBe('Blocked 10/31/2026');
    expect(underEveryZone(() => blockedOnLabel('2026-11-01T04:00:00Z'))).toBe('Blocked 11/1/2026');
    expect(underEveryZone(() => blockedOnLabel('2026-11-03T02:14:00Z'))).toBe('Blocked 11/2/2026');
    expect(underEveryZone(() => blockedOnLabel('2027-01-01T04:59:59Z'))).toBe('Blocked 12/31/2026');
    expect(deviceDay('2026-11-02T04:59:59Z', 'UTC')).toBe('2026-11-02 Mon');
    expect(deviceDay('2026-11-02T05:00:00Z', 'America/Los_Angeles')).toBe('2026-11-01 Sun');
    expect(deviceDay('2026-11-03T02:14:00Z', 'UTC')).toBe('2026-11-03 Tue');
  });

  it('an unreadable date is no line, never "Blocked Invalid Date"', () => {
    expect(underEveryZone(() => blockedOnLabel('not-a-date'))).toBe('');
  });
});

describe('D4 — a sold row dates the sale on New York\'s calendar', () => {
  it('the evening anchor, ET midnight, the 25-hour and the 23-hour days', () => {
    expect(underEveryZone(() => soldOnLabel('2026-11-03T02:14:00Z'))).toBe('Sold Mon 2 Nov');
    expect(underEveryZone(() => soldOnLabel('2026-11-02T04:59:59Z'))).toBe('Sold Sun 1 Nov');
    expect(underEveryZone(() => soldOnLabel('2026-11-02T05:00:00Z'))).toBe('Sold Mon 2 Nov');
    // 01:30 happens twice on 1 Nov (EDT, then EST): both are Sunday the 1st in New York.
    expect(underEveryZone(() => soldOnLabel('2026-11-01T05:30:00Z'))).toBe('Sold Sun 1 Nov');
    expect(underEveryZone(() => soldOnLabel('2026-11-01T06:30:00Z'))).toBe('Sold Sun 1 Nov');
    // 8 Mar is 23 hours long: its last second is 03:59:59Z the next morning, not 04:59:59Z.
    expect(underEveryZone(() => soldOnLabel('2026-03-09T03:59:59Z'))).toBe('Sold Sun 8 Mar');
    expect(underEveryZone(() => soldOnLabel('2026-03-09T04:00:00Z'))).toBe('Sold Mon 9 Mar');
    expect(deviceDay('2026-11-03T02:14:00Z', 'UTC')).toBe('2026-11-03 Tue');
    expect(deviceDay('2026-11-02T05:00:00Z', 'America/Los_Angeles')).toBe('2026-11-01 Sun');
    expect(deviceDay('2026-11-01T06:30:00Z', 'America/Los_Angeles')).toBe('2026-10-31 Sat');
    expect(deviceDay('2026-03-09T04:00:00Z', 'America/Los_Angeles')).toBe('2026-03-08 Sun');
  });
});

describe('the four sites read their date through easternParts, and nothing else', () => {
  const SITES: [string, RegExp][] = [
    ['app/(tabs)/bids.tsx', /whenLabel=\{whenLabel\(item\.listing\?\.ends_at\)\}/],
    ['app/profile/[id].tsx', /value=\{memberSince\(trustStats\?\.member_since \?\? profile\.created_at\)\}/],
    ['app/settings/blocked-users.tsx', /blockedOnLabel\(item\.created_at\)/],
    ['src/components/SellerListingCard.tsx', /soldOnLabel\(listing\.sold_at\)/],
  ];
  it.each(SITES)('%s', (path, callSite) => {
    const s = strip(read(path));
    expect(s).toMatch(/import \{ easternParts \} from '@\/src\/lib\/time\/eastern';/);
    expect(s).toMatch(callSite);
    expect(s).not.toMatch(/toLocale(Date|Time)?String\(/);
    expect(s).not.toMatch(/\.get(Day|Date|Month|FullYear|Hours|Minutes)\(\)/);
    expect(s).not.toMatch(/Intl\./);
  });
});

/**
 * app/_dev/v3-home.tsx — the V3 Home rendering harness (owner 2026-09-24).
 *
 * WHY IT EXISTS. The V3 Home has to be compared against `pkg8-home-dark.png` and
 * `pkg8-home-light.png` as the ACTUAL APP RENDERS IT, and the real feed sits behind
 * authentication and behind live listings the sandbox may not hold — a board with a feature, a
 * "Tonight" section and a "This week" section cannot be reproduced by waiting for the data to
 * cooperate. So this route mounts the REAL `app/(tabs)/home.tsx` with fixture rows supplied in
 * place of its feed read. Same pattern, same gate and same rules as `app/_dev/v3-screens.tsx`.
 *
 * WHAT A RENDER HERE PROVES, AND WHAT IT DOES NOT. It proves what the screen paints from the
 * given rows: the header composition, the section headings and their rule, the full-bleed feature,
 * the row thumbnails and their radius, spacing, type, colour roles, both appearances. It proves
 * nothing about the feed query, the realtime channel, the blocked-seller filter, native iOS
 * rendering, or anything that needs a server.
 *
 * THE FIXTURE IS NOT PRODUCTION DATA. The event names, venues, prices and dates below are the
 * board's own sample content (owner: "Sample event names, prices and photographs in the boards are
 * not production data"). Dates are computed RELATIVE TO NOW so the section rule has something real
 * to bucket: one event today (→ "Tonight", and the feature), three inside the next seven days
 * (→ "This week"). Nothing is hard-coded to a heading; if the rule changed, these rows would move.
 *
 * WHAT `?variant=` REACHES — read this before planning a capture.
 * The seam (`HomeFixture`) stands in for the THREE reads and the realtime subscription, and for
 * nothing else. Which "nothing here" surface you get is still decided by the screen's own state and
 * by how its own reads went; the fixture only decides what those reads returned.
 *
 *   • `feed`        — the populated feed: one event today (→ "Tonight", and the feature), three in
 *                     the next seven days (→ "This week").
 *   • `empty`       — an empty feed with no filter applied: "Nothing live right now".
 *   • `nomatches`   — ONE TAP. The copy needs `activeFilterCount(filters) > 0`, and `filters` is the
 *                     screen's own state, changed only through its filter sheet. The rows are chosen
 *                     so that ONE selection there ("VIP", or any neighbourhood but Wynwood) empties
 *                     the feed: every row is GA, auction-only, Wynwood, nightlife.
 *   • `sold-empty`  — starts on the "Sold" chip with that dataset returning nothing: "Nothing sold
 *                     yet". The copy is still gated on `mayShowEmptyCopy`, so what it proves is that
 *                     the read RAN and came back empty — not that a read was skipped.
 *   • `ended-empty` — the same for "Ended": "No ended auctions".
 *   • `error` /
 *     `offline`     — a FIRST-LOAD failure of the live feed, through the screen's own `setLoadError`,
 *                     so what paints is ScreenState with its retry, exactly as a real failure would.
 *
 * HISTORY: the last three were unreachable while the seam replaced only the live feed's rows, and the
 * route painted a note saying so. The seam now carries the two lazy datasets, a first-load failure
 * and a starting chip.
 *
 * NOT REACHABLE IN PRODUCTION. Like `_dev/v3-screens`, the route renders a redirect unless this is
 * a paired sandbox build or a `__DEV__` bundle, so a production binary cannot show it through
 * navigation or a deep link.
 *
 * NO WRITES, NO READS. The fixtures are literals in this file.
 */

import { Redirect, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import HomeScreen, { type HomeFixture } from '@/app/(tabs)/home';
import { IS_SANDBOX_BUILD } from '@/src/config/envGuard';
// The `?art=` vocabulary and the featured-row rule live in one module so this route and the
// listing harness cannot drift apart, and so the selection is testable without importing a route.
import { ART_KEYS, withArt } from '@/src/lib/media/harnessArt';
import { useAppearancePreference, useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import type { Listing } from '@/src/types';

declare const __DEV__: boolean;

function pad(n: number): string {
  return String(n).padStart(2, '0');
}

/** A local calendar date `days` from today, in the stored `YYYY-MM-DD` shape. */
function dateIn(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** An `ends_at` `hours` from now. */
function endsIn(hours: number): string {
  return new Date(Date.now() + hours * 3_600_000).toISOString();
}

function fixtureRow(n: number, over: Partial<Listing>): Listing {
  return {
    id: `v3-home-${n}`,
    seller_id: 'fixture-seller',
    status: 'active',
    auction_status: 'active',
    neighborhood: 'Wynwood',
    category: 'nightlife',
    ticket_type: 'GA',
    quantity: 2,
    starting_bid: 40,
    current_bid: 90,
    bid_count: 6,
    buy_now_enabled: false,
    buy_now_price: null,
    cover_image_path: null,
    created_at: new Date().toISOString(),
    ...over,
  } as Listing;
}

/**
 * The board's five listings. The first is tonight (the feature under "Tonight"); the rest fall
 * inside the next seven days, so the section rule puts them under "This week".
 */
export const HOME_FIXTURE: Listing[] = [
  fixtureRow(1, {
    event_name: 'Neon Choir',
    venue: 'Lantern Room',
    event_date: dateIn(0),
    event_time: '19:30',
    quantity: 2,
    ticket_type: 'GA',
    current_bid: 90,
    bid_count: 6,
    ends_at: endsIn(2.25),
  }),
  fixtureRow(2, {
    event_name: 'Midnight Arcade presents The Foundry Warehouse Sessions',
    venue: 'The Foundry',
    event_date: dateIn(1),
    event_time: '22:00',
    quantity: 2,
    ticket_type: 'GA',
    current_bid: 120,
    bid_count: 11,
    // Under the §5 fifteen-minute window, so the board's amber "Ending in 11m" is exercised.
    ends_at: endsIn(11 / 60),
  }),
  fixtureRow(3, {
    event_name: 'Björk: Cornucopia',
    venue: 'Halcyon Hall',
    event_date: dateIn(1),
    event_time: '21:00',
    quantity: 1,
    ticket_type: 'VIP',
    current_bid: 64,
    bid_count: 2,
    ends_at: endsIn(30),
  }),
  fixtureRow(4, {
    event_name: 'Neon Choir — Late Set with Special Guests',
    venue: 'Lantern Room',
    event_date: dateIn(2),
    event_time: '01:00',
    quantity: 1,
    ticket_type: 'GA',
    current_bid: 130,
    // No bids yet: the row must read "no bids yet", never "0 bids".
    bid_count: 0,
    ends_at: endsIn(48),
  }),
  fixtureRow(5, {
    event_name: 'Harbour Session',
    venue: 'Pier Seven',
    event_date: dateIn(6),
    event_time: '21:30',
    quantity: 4,
    ticket_type: 'GA',
    current_bid: 44,
    bid_count: 3,
    ends_at: endsIn(120),
  }),
];

/**
 * `variant=nomatches` — a feed that ONE sheet selection can empty. Every row is GA, auction-only,
 * Wynwood, nightlife and priced at $90, so selecting "VIP", "Buy now", any other neighbourhood, any
 * other category, or a price floor above $90 leaves nothing and raises the applied-filter count. The
 * fixture's job is to make that one tap deterministic; the emptiness and the copy stay the screen's.
 */
export const NARROW_FIXTURE: Listing[] = [
  fixtureRow(6, {
    event_name: 'Neon Choir',
    venue: 'Lantern Room',
    event_date: dateIn(0),
    event_time: '19:30',
    ticket_type: 'GA',
    ends_at: endsIn(2.25),
  }),
  fixtureRow(7, {
    event_name: 'Harbour Session',
    venue: 'Pier Seven',
    event_date: dateIn(3),
    event_time: '21:30',
    ticket_type: 'GA',
    ends_at: endsIn(60),
  }),
];

/** Every key this route accepts. The three marked below paint the note, not a state. */
const VARIANTS = ['feed', 'empty', 'nomatches', 'sold-empty', 'ended-empty', 'error', 'offline'] as const;

/**
 * Why a key cannot be reached, said on screen where it is asked for, so a variant the seam cannot
 * produce never quietly paints the populated feed under the requested name.
 *
 * HISTORY: `sold-empty`, `ended-empty` and `error` lived here until the seam carried the two lazy
 * datasets, a first-load failure and a starting chip. All three are reachable by URL now.
 */
const UNREACHABLE: Record<string, string> = {};

/**
 * `null` means "there is no fixture that reaches this"; the caller paints the note instead.
 *
 * `sold-empty`, `ended-empty` and `error` USED to be null here, and the note explained what was
 * missing: the seam replaced only the live feed's read, while those three states each need a read
 * that actually ran — the settled-empty copy is gated on `mayShowEmptyCopy`, which is what stops a
 * slow or failed read from telling a shopper the marketplace is empty. The seam now carries the two
 * lazy datasets, a first-load failure and a starting chip, so all three are reachable by URL and
 * nothing about how the screen decides what to paint changed.
 */
/**
 * `?amounts=long` — the same rows, priced into four figures.
 *
 * WHY IT EXISTS. Every fixture amount was five or six characters ($99.00, $132.00), so no capture
 * could show what the price treatment does with a realistic premium ticket. The owner asked for
 * representative LONGER amounts to be checked alongside $99.00, and none existed.
 *
 * It multiplies the rows' BASE prices and lets the app's own money module do the rest — the all-in
 * figures, the separators and the rounding are all `allInFromDollars`, untouched. ×13 keeps the
 * feed's variety and lands the longest at nine characters ("$1,859.00"), which is the shape that
 * actually tests the line: a four-figure amount with a thousands separator and cents.
 */
const LONG_AMOUNT_FACTOR = 13;

function withLongAmounts(rows: Listing[], amounts: string | undefined): Listing[] {
  if (amounts !== 'long') return rows;
  const up = (v: number | null | undefined) => (typeof v === 'number' ? v * LONG_AMOUNT_FACTOR : v);
  return rows.map((l) => ({
    ...l,
    starting_bid: up(l.starting_bid),
    current_bid: up(l.current_bid),
    buy_now_price: up(l.buy_now_price),
  })) as Listing[];
}

function fixtureFor(variant: string | undefined): HomeFixture | null {
  switch (variant) {
    case 'empty':
      // The settled empty feed: no rows, no filter applied → "Nothing live right now".
      return { rows: [] };
    case 'nomatches':
      return { rows: NARROW_FIXTURE };
    case 'sold-empty':
      // The Sold dataset read, and returned nothing: "Nothing sold yet".
      return { rows: HOME_FIXTURE, sold: [], chip: 'recently_sold' };
    case 'ended-empty':
      // The Ended dataset read, and returned nothing: "No ended auctions".
      return { rows: HOME_FIXTURE, ended: [], chip: 'ended' };
    case 'error':
      // A FIRST-LOAD failure of the live feed, which is the state that shows ScreenState + Retry.
      return { failure: 'error' };
    case 'offline':
      return { failure: 'offline' };
    default:
      return { rows: HOME_FIXTURE };
  }
}

export default function V3HomeHarness() {
  const { variant, appearance, art, amounts } = useLocalSearchParams<{
    variant?: string; appearance?: string; art?: string; amounts?: string;
  }>();
  // `?appearance=light|dark` drives the comparison capture deterministically from the app's own
  // preference — the same one Settings writes — rather than from a browser emulation flag, so a
  // dark and a light capture differ only in the value the app resolved.
  const { setPreference } = useAppearancePreference();
  useEffect(() => {
    if (appearance === 'light' || appearance === 'dark' || appearance === 'system') {
      setPreference(appearance);
    }
  }, [appearance]);

  // Stable per variant: the screen's fetch closes over the fixture, so an identity that changed
  // every render would re-run its focus effect for nothing.
  const fixture = useMemo(() => {
    const base = fixtureFor(variant);
    if (!base?.rows) return base;
    // Local midnight, the same basis the screen keys its bucketing to, so the harness and the
    // screen agree about which row is first.
    const midnight = new Date();
    midnight.setHours(0, 0, 0, 0);
    return { ...base, rows: withArt(withLongAmounts(base.rows, amounts), art, midnight.getTime()) };
  }, [variant, art, amounts]);

  if (!IS_SANDBOX_BUILD && !__DEV__) return <Redirect href="/" />;

  if (!fixture) {
    return (
      <HarnessNote
        title={`?variant=${variant ?? ''} cannot be reached from a fixture`}
        body={UNREACHABLE[variant ?? ''] ?? ''}
      />
    );
  }

  return <HomeScreen fixture={fixture} />;
}

/**
 * A harness message, never a screen. It exists so a variant the seam cannot produce says what is
 * missing instead of quietly painting the populated feed under the requested name.
 */
function HarnessNote({ title, body }: { title: string; body: string }) {
  const { palette } = useTheme();
  const s = useMemo(() => noteStyles(palette), [palette]);
  return (
    <View style={s.wrap}>
      <Text style={[textStyle('screenTitle'), s.title]}>{title}</Text>
      <Text style={[textStyle('body'), s.body]}>{body}</Text>
      <Text style={[textStyle('micro'), s.foot]}>
        {`Harness note — not an app state. Variants: ${VARIANTS.join(', ')}.`}
      </Text>
    </View>
  );
}

function noteStyles(p: Palette) {
  return StyleSheet.create({
    wrap: {
      flex: 1,
      backgroundColor: p.surface.canvas,
      justifyContent: 'center',
      gap: v2.space.md,
      paddingHorizontal: v2.space.xl,
    },
    title: { color: p.text.primary },
    body: { color: p.text.secondary },
    foot: { color: p.text.muted },
  });
}

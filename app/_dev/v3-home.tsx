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
 * NOT REACHABLE IN PRODUCTION. Like `_dev/v3-screens`, the route renders a redirect unless this is
 * a paired sandbox build or a `__DEV__` bundle, so a production binary cannot show it through
 * navigation or a deep link.
 *
 * NO WRITES, NO READS. The fixtures are literals in this file.
 */

import { Redirect, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo } from 'react';

import HomeScreen from '@/app/(tabs)/home';
import { IS_SANDBOX_BUILD } from '@/src/config/envGuard';
import { useAppearancePreference } from '@/src/theme/appearance';
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

export default function V3HomeHarness() {
  const { appearance } = useLocalSearchParams<{ appearance?: string }>();
  // `?appearance=light|dark` drives the comparison capture deterministically from the app's own
  // preference — the same one Settings writes — rather than from a browser emulation flag, so a
  // dark and a light capture differ only in the value the app resolved.
  const { setPreference } = useAppearancePreference();
  useEffect(() => {
    if (appearance === 'light' || appearance === 'dark' || appearance === 'system') {
      setPreference(appearance);
    }
  }, [appearance]);

  const fixture = useMemo(() => HOME_FIXTURE, []);

  if (!IS_SANDBOX_BUILD && !__DEV__) return <Redirect href="/" />;

  return <HomeScreen fixture={fixture} />;
}

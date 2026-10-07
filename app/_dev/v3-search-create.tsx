/**
 * app/_dev/v3-search-create.tsx — the V3 Search + Sell/Create rendering harness
 * (owner 2026-09-24; same pattern, same gate and same rules as `app/_dev/v3-screens.tsx`).
 *
 * WHY IT EXISTS. The V3 Search and Create surfaces have to be compared against
 * `pkg8-search-dark/light.png` and `pkg8-create-dark/light.png` as the ACTUAL APP renders them,
 * and both screens sit behind authentication and live data. This route mounts the REAL screen
 * components with fixture data supplied in place of their network read.
 *
 * WHAT A RENDER HERE PROVES, AND WHAT IT DOES NOT. It proves what the components paint from the
 * given state: composition, spacing, type, colour roles, shapes, both appearances. It proves
 * nothing about the search query, the blocked-seller filter, the publish gate chain, native iOS
 * rendering, or anything that needs a server.
 *
 * THE CREATE RENDER IS PREVIEW-ONLY. The create screen's live path submits to the server; here
 * the `fixture` prop makes `handlePublish` return before its first gate, so this route can NEVER
 * fire the phone/payout/risk gates, the uploads or the insert. The live route
 * (`app/(tabs)/create.tsx`) passes no fixture and is untouched. Known harness limits: the two
 * photo slots render their empty state (their state lives in the upload hook, which is not
 * injectable), so the board's "Image added" rows are a device/build comparison, not a harness one.
 *
 * NOT REACHABLE IN PRODUCTION. The route renders a redirect unless this is a paired sandbox
 * build or a `__DEV__` bundle, so a production binary cannot show it through navigation or a
 * deep link.
 *
 * NO WRITES. Nothing here reads or writes a server. The fixtures are literals in this file, and
 * the sample content is the boards' own ("Sample event names, prices, photographs and dates are
 * not production data").
 *
 * ROUTES
 *   /_dev/v3-search-create?screen=search                    — board results state (2 rows)
 *   /_dev/v3-search-create?screen=search&variant=empty      — §5 filtered-empty state
 *   /_dev/v3-search-create?screen=create                    — filled, valid form (board state)
 *   /_dev/v3-search-create?screen=create&variant=invalid    — pkg3-create-invalid state
 *   /_dev/v3-search-create?screen=create&risk=unavailable|medium|high|blocked — banner states
 *   …all take &appearance=light|dark.
 */

import { Redirect, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo } from 'react';

import SearchScreen, { type SearchFixture } from '@/app/(tabs)/explore';
import CreateListingScreen, { type CreateFixture } from '@/src/screens/CreateListingScreen';
import { IS_SANDBOX_BUILD } from '@/src/config/envGuard';
import { listArt } from '@/src/lib/media/harnessArt';
import { useAppearancePreference } from '@/src/theme/appearance';
import type { Listing, Neighborhood, RiskTier } from '@/src/types';

declare const __DEV__: boolean;

/** An `ends_at` `hours` from now, so countdown labels have something real to count. */
function endsIn(hours: number): string {
  return new Date(Date.now() + hours * 3_600_000).toISOString();
}

function searchRow(n: number, over: Partial<Listing>): Listing {
  return {
    id: `v3-search-${n}`,
    seller_id: 'fixture-seller',
    status: 'active',
    auction_status: 'active',
    neighborhood: 'Wynwood',
    category: 'nightlife',
    ticket_type: 'GA',
    transfer_method: 'mobile_transfer',
    quantity: 2,
    starting_bid: 90,
    current_bid: 90,
    bid_count: 6,
    buy_now_enabled: false,
    buy_now_price: null,
    // No stored artwork: the SN monogram plate stands in (CFT-106), as on the board's
    // second row. The first row's photograph needs a storage read, which this file bans.
    cover_image_path: null,
    created_at: new Date().toISOString(),
    ...over,
  } as Listing;
}

/**
 * The board's two "neon" results: both GA, both under $150 all-in, so both pass the two
 * selected chips (GA · Under $150) — nothing a filter excludes is returned.
 */
export const SEARCH_FIXTURE_ROWS: Listing[] = [
  searchRow(1, {
    event_name: 'Neon Choir',
    venue: 'Lantern Room',
    event_date: '2026-10-24',
    event_time: '19:30',
    quantity: 2,
    current_bid: 90,      // → $99.00 all-in on the row
    bid_count: 6,
    ends_at: endsIn(2.24), // → "2h 14m left"
  }),
  searchRow(2, {
    event_name: 'Neon Choir — Late Set with Special Guests', // 41 chars: wraps, never truncates mid-word
    venue: 'Lantern Room',
    event_date: '2026-10-25',
    event_time: '01:00',
    quantity: 1,
    starting_bid: 130,
    current_bid: 130,     // no bids yet → judged on the shown price → $143.00 all-in
    bid_count: 0,
    ends_at: endsIn(26.5),
  }),
];

/** The board's chip state: GA and Under $150 selected, Mobile transfer off. */
const SEARCH_FILTERS_ON = { ga: true, under150: true, mobileTransfer: false };

export const SEARCH_FIXTURE: SearchFixture = {
  rows: SEARCH_FIXTURE_ROWS,
  query: 'neon',
  filters: SEARCH_FILTERS_ON,
};

/** Nothing matched: same query, same filters, no rows — the §5 empty state. */
export const SEARCH_FIXTURE_EMPTY: SearchFixture = {
  rows: [],
  query: 'neon',
  filters: SEARCH_FILTERS_ON,
};

/** The board's filled form: Neon Choir, 2 × GA, mobile transfer via DICE, $90 ask, 1d. */
export const CREATE_FIXTURE: CreateFixture = {
  form: {
    eventName: 'Neon Choir',
    venue: 'Lantern Room',
    neighborhood: 'wynwood' as Neighborhood,
    eventDate: new Date(2026, 9, 24),
    eventTime: new Date(2026, 9, 24, 19, 30),
    ticketType: 'GA',
    quantity: 2,
    transferMethod: 'mobile_transfer',
    ticketPlatform: 'dice',
    startingBid: '90', // → "Buyers pay $99.00 total" · "$81.00" at the sticky
    durationHours: 24, // the board's selected "1d"
    commitmentAccepted: true,
  },
};

/**
 * pkg3-create-invalid: a submit already happened, the neighborhood was never picked and the
 * commitment is unchecked. The proof-of-ownership error is real here too — the harness cannot
 * hold an uploaded image — which is the state that board draws.
 */
export const CREATE_FIXTURE_INVALID: CreateFixture = {
  form: { ...CREATE_FIXTURE.form, neighborhood: null, commitmentAccepted: false },
  submitted: true,
};

const RISK_FIXTURES: Record<string, CreateFixture['riskBanner']> = {
  unavailable: { reason: 'check_unavailable', tier: null },
  medium: { reason: 'medium_risk_warning', tier: 'medium' as RiskTier },
  high: { reason: 'high_risk_warning', tier: 'high' as RiskTier },
  blocked: { reason: 'listing_blocked', tier: 'critical' as RiskTier },
};

export default function V3SearchCreateHarness() {
  const { screen, variant, risk, appearance, art } = useLocalSearchParams<{
    screen?: string; variant?: string; risk?: string; appearance?: string; art?: string;
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

  const createFixture = useMemo<CreateFixture>(() => {
    const base = variant === 'invalid' ? CREATE_FIXTURE_INVALID : CREATE_FIXTURE;
    const banner = risk ? RISK_FIXTURES[risk] : undefined;
    return banner ? { ...base, riskBanner: banner } : base;
  }, [variant, risk]);

  /*
   * `?art=` gives every result row the selected poster (`all` cycles the shapes). The default stays
   * what it was — SEARCH_FIXTURE_ROWS carries no artwork on purpose (CFT-106), so the monogram
   * plate is still what an unparameterised capture shows.
   */
  const searchFixture = useMemo(() => {
    const base = variant === 'empty' ? SEARCH_FIXTURE_EMPTY : SEARCH_FIXTURE;
    const covers = listArt(art, base.rows.length);
    return { ...base, rows: base.rows.map((l, i) => (covers[i] ? { ...l, cover_image_path: covers[i] } : l)) };
  }, [variant, art]);

  if (!IS_SANDBOX_BUILD && !__DEV__) return <Redirect href="/" />;

  switch (screen) {
    case 'search':
      return <SearchScreen fixture={searchFixture} />;
    case 'create':
      return <CreateListingScreen fixture={createFixture} />;
    default:
      return <Redirect href="/" />;
  }
}

/**
 * app/_dev/v3-listing.tsx — the V3 LISTING DETAIL rendering harness (owner 2026-09-24).
 *
 * WHY IT EXISTS. Same reason as `app/_dev/v3-screens.tsx`, which this copies: the V3 corrections
 * have to be compared against the approved boards as the ACTUAL APP RENDERS THEM, and this screen
 * sits behind authentication, a listing row, a seller profile and a live bid channel that the
 * sandbox may not hold. The owner authorised "safe local rendering fixtures for otherwise
 * unreachable visual states" and required the real application components rather than a recreated
 * mock, so this route mounts the REAL `ListingDetailScreen` with fixture rows supplied in place of
 * its reads — the same component `/listing/[id]` pushes.
 *
 * WHAT A RENDER HERE PROVES, AND WHAT IT DOES NOT. It proves what the component paints from the
 * given rows: composition, spacing, type, colour roles, shapes, wrapping, both appearances. It
 * proves nothing about the data path that normally supplies those rows, nothing about native iOS
 * rendering, and nothing about behaviour that needs a server — a tap on "Place a bid" still pushes
 * the real route, which has no fixture behind it.
 *
 * NOT REACHABLE IN PRODUCTION. Like `_dev/transfer-states` and `_dev/v3-screens`, the route
 * renders a redirect unless this is a paired sandbox build or a `__DEV__` bundle, so a production
 * binary cannot show it through navigation or a deep link.
 *
 * NO WRITES. Nothing here reads or writes a server. The fixtures are literals in this file.
 */

import { Redirect, useLocalSearchParams } from 'expo-router';
import { useEffect } from 'react';

import { IS_SANDBOX_BUILD } from '@/src/config/envGuard';
import { useAppearancePreference } from '@/src/theme/appearance';
import ListingDetailScreen, { type ListingDetailFixture } from '@/src/screens/ListingDetailScreen';
import type { Bid, Listing } from '@/src/types';

declare const __DEV__: boolean;

/** The board's sample listing — "Sample event names, prices, photographs and dates are not
 *  production data" (owner). Values chosen so a render can be laid beside `pkg8-listing-dark.png`
 *  figure for figure: $90 + 10% = $99.00 all-in, $120 + 10% = $132.00 buy-now, a $95.00 / $9.50 /
 *  $104.50 minimum. The clock is relative so the panel shows a live "left" form rather than a
 *  frozen string; everything else is a literal. */
const ENDS_AT = new Date(Date.now() + ((2 * 60 + 14) * 60 + 30) * 1000).toISOString();

const LISTING_FIXTURE = {
  id: 'fixture-listing',
  seller_id: 'fixture-seller',
  event_name: 'Neon Choir',
  event_date: '2026-10-24',
  event_time: '19:30',
  venue: 'Lantern Room',
  neighborhood: null,
  category: 'nightlife',
  quantity: 2,
  ticket_type: 'GA',
  transfer_method: 'mobile_transfer',
  ticket_platform: 'dice',
  // The live price on this screen comes from `useListingRealtime`, which falls back to
  // `starting_bid` when it has no bid rows — and it has none here, because nothing reads a
  // server. Both are the board's $90 base ($99.00 all-in) so the fixture paints one price.
  starting_bid: 90,
  current_bid: 90,
  bid_count: 6,
  buy_now_enabled: true,
  buy_now_price: 120,
  status: 'active',
  auction_status: 'active',
  ends_at: ENDS_AT,
  reserved_by: null,
  reserved_until: null,
  winner_user_id: null,
  cover_image_path: null,
  cover_image_url: null,
  restrictions: null,
  proof_status: null,
} as unknown as Listing;

const VIEWER = 'fixture-viewer';

/** The board's two rows: a leading bid from another bidder, and the viewer's earlier one. */
const BIDS_FIXTURE = [
  {
    id: 'fixture-bid-1',
    listing_id: 'fixture-listing',
    bidder_id: 'k7f2aaaa-0000-0000-0000-000000000000',
    amount: 90,
    created_at: new Date(Date.now() - 2 * 60 * 1000).toISOString(),
  },
  {
    id: 'fixture-bid-2',
    listing_id: 'fixture-listing',
    bidder_id: VIEWER,
    // Whole dollars, as every bid in this app is. The board's sample "$93.00" is not the all-in
    // of any whole-dollar bid, so the nearest legal one is used rather than an illegal amount.
    amount: 85,
    created_at: new Date(Date.now() - 11 * 60 * 1000).toISOString(),
  },
] as unknown as Bid[];

const SELLER_FIXTURE = {
  display_name: 'the seller',
  is_verified_seller: false,
  avatar_url: null,
  avatar_path: null,
};

const LIVE: ListingDetailFixture = {
  listing: LISTING_FIXTURE,
  seller: SELLER_FIXTURE,
  bids: BIDS_FIXTURE,
  viewerId: VIEWER,
};

/** The closed board: no minimum to break down, no bid to place, one dimmed action. */
const SOLD: ListingDetailFixture = {
  ...LIVE,
  listing: { ...LISTING_FIXTURE, status: 'sold', auction_status: 'ended' } as Listing,
};

/**
 * The state that has something to SAY while its control is dead. A disabled pill dims to 0.4, so
 * the sentence explaining the state renders outside it at full strength — this variant is how that
 * is checked rather than assumed.
 */
const CANCELLED: ListingDetailFixture = {
  ...LIVE,
  listing: { ...LISTING_FIXTURE, auction_status: 'cancelled' } as Listing,
};

export default function V3ListingHarness() {
  const { screen, variant, appearance } = useLocalSearchParams<{
    screen?: string; variant?: string; appearance?: string;
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

  if (!IS_SANDBOX_BUILD && !__DEV__) return <Redirect href="/" />;

  switch (screen) {
    case 'listing':
      return (
        <ListingDetailScreen
          id="fixture-listing"
          fixture={variant === 'sold' ? SOLD : variant === 'cancelled' ? CANCELLED : LIVE}
        />
      );
    default:
      return <Redirect href="/" />;
  }
}

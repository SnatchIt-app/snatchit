/**
 * app/_dev/v3-mylistings-bids.tsx — the V3 MY LISTINGS + BIDS rendering harness (owner 2026-09-24).
 *
 * WHY IT EXISTS. Same reason as `app/_dev/v3-screens.tsx`, which this copies: the V3 corrections
 * have to be compared against the approved boards as the ACTUAL APP RENDERS THEM, and both
 * screens sit behind authentication and behind rows the sandbox may not hold (a seller with a
 * sold-pending-transfer listing, a buyer simultaneously won/outbid/leading). The owner authorised
 * "safe local rendering fixtures for otherwise unreachable visual states" and required the real
 * application components rather than a recreated mock, so this route mounts the REAL
 * `MyListingsScreen` and `BidsScreen` with fixture rows supplied in place of their network reads.
 *
 * WHAT A RENDER HERE PROVES, AND WHAT IT DOES NOT. It proves what the components paint from the
 * given rows: composition, spacing, type, colour roles, shapes, wrapping, both appearances. It
 * proves nothing about the data path that normally supplies those rows, nothing about native iOS
 * rendering, and nothing about behaviour that needs a server.
 *
 * NOT REACHABLE IN PRODUCTION. The `_dev` segment layout gates the whole group and this file
 * redirects on its own too: a production binary cannot show it through navigation or a deep link.
 *
 * NO WRITES. Nothing here reads or writes a server. The fixtures are literals in this file, and
 * both screens' destructive/network paths are guarded on the fixture prop.
 *
 * Boards: `pkg3-my-listings-{clean,empty}.png` + `pkg8-mylistings-{dark,light}.png`;
 * `pkg6-bids-{clean,active,past,empty,refresh_failed}.png` (dark only). Sample content only
 * (owner: "Sample event names, prices, photographs and dates are not production data").
 */

import { Redirect, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo } from 'react';

import { IS_SANDBOX_BUILD } from '@/src/config/envGuard';
import { useAppearancePreference } from '@/src/theme/appearance';
import MyListingsScreen, { type MyListingsFixture } from '@/app/my-listings';
import BidsScreen, { type BidsFixture, type BidRow } from '@/app/(tabs)/bids';
import type { Listing } from '@/src/types';

declare const __DEV__: boolean;

const HOUR = 3600_000;
/** The harness viewer's identity: fixture winner/bidder ids resolve against this, no session. */
const FIXTURE_USER = 'fixture-user';

// ─── My listings (pkg3/pkg8 boards: active, ending soon, sold + send, cancelled) ────────────────

const SELLER_BASE: Partial<Listing> = {
  seller_id: FIXTURE_USER,
  venue: 'Lantern Room',
  status: 'active',
  auction_status: 'active',
  quantity: 2,
  ticket_type: 'GA',
  winner_user_id: null,
  sold_at: null,
  reserved_until: null,
};

/** The board's four rows: Active · Ending soon (no bids) · Sold, tickets to send · Cancelled. */
const SELLER_LISTINGS = [
  {
    ...SELLER_BASE, id: 'fixture-sl1', event_name: 'Neon Choir',
    bid_count: 6, current_bid: 90, starting_bid: 60,
    ends_at: new Date(Date.now() + 28 * HOUR).toISOString(),          // "1d 4h left"
  },
  {
    ...SELLER_BASE, id: 'fixture-sl2', event_name: 'Neon Choir — Late Set with Special Guests',
    bid_count: 0, current_bid: 55, starting_bid: 55,
    ends_at: new Date(Date.now() + 12 * 60_000).toISOString(),        // "12m left" — Ending soon
  },
  {
    ...SELLER_BASE, id: 'fixture-sl3', event_name: 'Midnight Arcade presents The Foundry Warehouse Sessions',
    status: 'sold', auction_status: 'ended', bid_count: 9, current_bid: 120, starting_bid: 80,
    ends_at: '2026-10-16T23:00:00-04:00', sold_at: '2026-10-17T21:00:00-04:00',  // "Sold Fri 17 Oct"
    winner_user_id: 'fixture-buyer',
  },
  {
    ...SELLER_BASE, id: 'fixture-sl4', event_name: 'Harbour Session',
    auction_status: 'cancelled', bid_count: 2, current_bid: 48, starting_bid: 30,
    ends_at: '2026-10-30T21:00:00-04:00',
  },
] as Listing[];

function myListingsFixtureFor(variant: string | undefined): MyListingsFixture {
  switch (variant) {
    case 'empty': return { listings: [] };
    case 'error': return { failure: 'error' };
    case 'offline': return { failure: 'offline' };
    default:
      return {
        listings: SELLER_LISTINGS,
        // The sold row's pending transfer — drives "Action needed — send the tickets".
        transfers: [{ listing_id: 'fixture-sl3', transferId: 'fixture-tr1', status: 'pending' }],
      };
  }
}

// ─── Bids (pkg6 boards: won, outbid+urgent, winning, marked sent; past; failed refresh) ─────────

const BID_LISTING = {
  id: 'fixture-bl0',
  event_name: 'Neon Choir',
  venue: 'Lantern Room',
  ends_at: '2099-01-01T00:00:00Z',
  current_bid: 90,
  status: 'active',
  auction_status: 'active' as const,
  winner_user_id: null as string | null,
  winning_bid_amount: null as number | null,
  cover_image_path: null as string | null,
  reserved_until: null as string | null,
  reserved_by: null as string | null,
};

/** Board rows, top to bottom: Won ($99.00) · Outbid + 12m left ($132.00) · Winning ($70.40) · Marked sent ($48.40). */
const BIDS_ACTIVE: BidRow[] = [
  {
    id: 'fixture-b1', created_at: '2026-10-20T12:00:00Z', amount: 90, listing_id: 'fixture-bl1', coverUrl: null,
    listing: {
      ...BID_LISTING, id: 'fixture-bl1', auction_status: 'ended',
      winner_user_id: FIXTURE_USER, winning_bid_amount: 90, ends_at: '2026-10-20T11:00:00Z',
    },
  },
  {
    id: 'fixture-b2', created_at: '2026-10-20T10:00:00Z', amount: 110, listing_id: 'fixture-bl2', coverUrl: null,
    listing: {
      ...BID_LISTING, id: 'fixture-bl2', event_name: 'Midnight Arcade presents The Foundry Warehouse Sessions',
      current_bid: 120, ends_at: new Date(Date.now() + 12 * 60_000).toISOString(),   // urgency line
    },
  },
  {
    id: 'fixture-b3', created_at: '2026-10-19T22:00:00Z', amount: 64, listing_id: 'fixture-bl3', coverUrl: null,
    listing: {
      ...BID_LISTING, id: 'fixture-bl3', event_name: 'Björk: Cornucopia',
      current_bid: 64, ends_at: new Date(Date.now() + 30 * HOUR).toISOString(),
    },
  },
  {
    id: 'fixture-b4', created_at: '2026-10-18T20:00:00Z', amount: 44, listing_id: 'fixture-bl4', coverUrl: null,
    transferId: 'fixture-tr-b4', purchaseTransferStatus: 'seller_sent', purchaseBuyerConfirmedAt: null,
    listing: { ...BID_LISTING, id: 'fixture-bl4', event_name: 'Harbour Session', status: 'sold', auction_status: 'sold' },
  },
];

/**
 * Past rows: Received (the buyer's own confirmation), Released (auto_released — DR12),
 * Resolved (operator decision — DR9), Ended, Cancelled. The pkg6 board flattens the first
 * three into 'Received'; the ruled labels are staged deliberately so a capture shows them.
 */
const BIDS_PAST: BidRow[] = [
  {
    id: 'fixture-b5', created_at: '2026-10-12T20:00:00Z', amount: 130, listing_id: 'fixture-bl5', coverUrl: null,
    transferId: 'fixture-tr-b5', purchaseTransferStatus: 'buyer_confirmed',
    purchaseBuyerConfirmedAt: '2026-10-14T18:00:00Z',
    listing: { ...BID_LISTING, id: 'fixture-bl5', event_name: 'Neon Choir — Late Set with Special Guests', status: 'sold' },
  },
  {
    id: 'fixture-b6', created_at: '2026-10-08T20:00:00Z', amount: 72, listing_id: 'fixture-bl6', coverUrl: null,
    transferId: 'fixture-tr-b6', purchaseTransferStatus: 'auto_released', purchaseBuyerConfirmedAt: null,
    listing: { ...BID_LISTING, id: 'fixture-bl6', event_name: 'Winter Warehouse', status: 'sold' },
  },
  {
    id: 'fixture-b7', created_at: '2026-10-05T20:00:00Z', amount: 58, listing_id: 'fixture-bl7', coverUrl: null,
    transferId: 'fixture-tr-b7', purchaseTransferStatus: 'buyer_confirmed', purchaseBuyerConfirmedAt: null,
    listing: { ...BID_LISTING, id: 'fixture-bl7', event_name: 'Autumn Sessions', status: 'sold' },
  },
  {
    id: 'fixture-b8', created_at: '2026-10-02T20:00:00Z', amount: 58, listing_id: 'fixture-bl8', coverUrl: null,
    listing: {
      ...BID_LISTING, id: 'fixture-bl8', event_name: 'Lantern Sessions', auction_status: 'ended',
      winner_user_id: 'fixture-someone-else', winning_bid_amount: 58, ends_at: '2026-10-03T02:00:00Z',
    },
  },
  {
    id: 'fixture-b9', created_at: '2026-09-28T20:00:00Z', amount: 47, listing_id: 'fixture-bl9', coverUrl: null,
    listing: { ...BID_LISTING, id: 'fixture-bl9', event_name: 'Pier Seven Night Two', auction_status: 'cancelled' },
  },
];

function bidsFixtureFor(variant: string | undefined): BidsFixture {
  switch (variant) {
    case 'empty': return { userId: FIXTURE_USER, rows: [] };
    case 'past': return { userId: FIXTURE_USER, rows: BIDS_PAST };
    case 'all': return { userId: FIXTURE_USER, rows: [...BIDS_ACTIVE, ...BIDS_PAST] };
    case 'failed': return { userId: FIXTURE_USER, rows: BIDS_ACTIVE, refreshFailed: 'error' };
    case 'error': return { failure: 'error' };
    case 'offline': return { failure: 'offline' };
    default: return { userId: FIXTURE_USER, rows: BIDS_ACTIVE };
  }
}

export default function V3MyListingsBidsHarness() {
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

  // Stable per variant: each screen's load closes over the fixture, so an identity that
  // changed every render would re-run its focus effect for nothing.
  const myListingsFixture = useMemo(() => myListingsFixtureFor(variant), [variant]);
  const bidsFixture = useMemo(() => bidsFixtureFor(variant), [variant]);

  if (!IS_SANDBOX_BUILD && !__DEV__) return <Redirect href="/" />;

  switch (screen) {
    case 'mylistings':
      return <MyListingsScreen fixture={myListingsFixture} />;
    case 'bids':
      return <BidsScreen fixture={bidsFixture} />;
    default:
      return <Redirect href="/" />;
  }
}

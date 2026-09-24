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
 * WHO "YOU" IS, AND WHY THIS FILE READS THE REAL VIEWER. Four of the states below are decided by
 * the viewer's own identity: `src/lib/listing/detailState.ts` resolves `won`, `reserved_by_you` and
 * the seller's own view by comparing the row's `winner_user_id` / `reserved_by` / `seller_id`
 * against `useAuth().user?.id` — the SCREEN's auth, which no prop can stand in for (`viewerId` in
 * the fixture is display-only: it marks a row "You" inside Bid activity and decides nothing). So
 * this route reads the same `useAuth()` the mounted screen already reads and puts that real id into
 * the fixture row, which is why the resolver genuinely resolves those branches. Nothing is
 * fabricated and no gate is bypassed: signed out there is no id to put anywhere, the resolver would
 * quietly fall to a DIFFERENT state ("Auction ended" instead of "You won"), and rather than let a
 * capture circulate under the wrong name the route says so on screen and paints nothing.
 *
 * TWO OF THE SEVEN REQUESTED STATES ARE NOT PRODUCIBLE FROM A FIXTURE, and are deliberately absent
 * rather than approximated: `lost` and `outbid` both require `hasBid` — the screen derives that
 * from `rt.bids` (the live `useListingRealtime` rows), never from `fixture.bids`, so producing them
 * needs a real bid row by the real viewer on this listing. The resolver's own vocabulary for what
 * the harness CAN reach is used everywhere below, so a capture's filename can be checked against
 * `StatusKind`.
 *
 * NOT REACHABLE IN PRODUCTION. Like `_dev/transfer-states` and `_dev/v3-screens`, the route
 * renders a redirect unless this is a paired sandbox build or a `__DEV__` bundle, so a production
 * binary cannot show it through navigation or a deep link.
 *
 * NO WRITES. Nothing here writes anything, anywhere. The fixtures are literals in this file; the
 * only read in this file is the local auth state above, which the mounted screen performs anyway.
 */

import { Redirect, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { IS_SANDBOX_BUILD } from '@/src/config/envGuard';
import { useAuth } from '@/src/hooks/useAuth';
import { useAppearancePreference, useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import ListingDetailScreen, { type ListingDetailFixture } from '@/src/screens/ListingDetailScreen';
import type { Bid, Listing } from '@/src/types';

declare const __DEV__: boolean;

/** The board's sample listing — "Sample event names, prices, photographs and dates are not
 *  production data" (owner). Values chosen so a render can be laid beside `pkg8-listing-dark.png`
 *  figure for figure: $90 + 10% = $99.00 all-in, $120 + 10% = $132.00 buy-now, a $95.00 / $9.50 /
 *  $104.50 minimum. The clock is relative so the panel shows a live "left" form rather than a
 *  frozen string; everything else is a literal. */
const ENDS_AT = new Date(Date.now() + ((2 * 60 + 14) * 60 + 30) * 1000).toISOString();

/** Relative clocks for the states whose whole point is a clock: a hold that still has time on it,
 *  and an auction whose clock has already run out. Computed per mount, not at module load, so a
 *  capture taken twenty minutes into a session still shows a live hold instead of an expired one. */
function minutesFromNow(minutes: number): string {
  return new Date(Date.now() + minutes * 60_000).toISOString();
}

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

/** Another buyer, for the hold that is not yours. A literal uuid-shaped id, never a real one. */
const OTHER_BUYER = 'b41d0000-0000-0000-0000-000000000000';

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

/**
 * The same two rows, attributed to whoever is actually looking, so Bid activity marks one "You"
 * on the states that only exist for a known viewer. Display only — `BidActivity` prints these and
 * nothing else reads them (the price, the minimum and every gate read the live hook).
 */
function bidsAsViewer(viewerId: string): Bid[] {
  return BIDS_FIXTURE.map((b) => (b.bidder_id === VIEWER ? { ...b, bidder_id: viewerId } : b));
}

/** A won auction's history has the winner in front: the viewer's bid leads, the other trails. */
function winningBids(viewerId: string): Bid[] {
  return [
    { ...BIDS_FIXTURE[0], id: 'fixture-bid-3', bidder_id: viewerId, amount: 90 },
    { ...BIDS_FIXTURE[1], id: 'fixture-bid-4', bidder_id: BIDS_FIXTURE[0].bidder_id, amount: 85 },
  ];
}

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

/**
 * `variant=not-found` — the row that isn't there. `fetchData` assigns `fixture.listing` straight
 * into the screen's state, so a null row here IS the state the real read produces for a listing
 * that was deleted (`if (listingRes.data === null) { setListing(null); setLoading(false); }`), and
 * the screen's own `if (!listing)` branch paints "Listing not found" with its browse action. The
 * fixture type says non-null because every other case is; this single cast is the whole variant,
 * and no copy is duplicated to produce it.
 */
const NOT_FOUND: ListingDetailFixture = {
  listing: null as unknown as Listing,
  seller: null,
  bids: [],
};

/**
 * Every state this route can select. The names are the resolver's own (`StatusKind` in
 * `src/lib/listing/detailState.ts`), hyphenated for a URL: `reserved_by_you` → `reserved-by-you`,
 * `reserved_by_other` → `on-hold` (the label the sticky bar actually prints), plus the seller's own
 * view and the absent row, which are action/branch states rather than statuses.
 */
const VARIANTS = [
  'live',
  'sold',
  'cancelled',
  'won',
  'reserved-by-you',
  'on-hold',
  'own-listing',
  'not-found',
] as const;

/** The states the resolver decides from the VIEWER's id, so they need a signed-in one. */
const NEEDS_VIEWER: readonly string[] = ['won', 'reserved-by-you', 'own-listing'];

/**
 * `null` means "this variant needs a viewer and there is none" — the caller paints the note rather
 * than a state the resolver would have named differently.
 */
function fixtureFor(variant: string | undefined, viewerId: string | undefined): ListingDetailFixture | null {
  switch (variant) {
    case 'sold':
      return SOLD;
    case 'cancelled':
      return CANCELLED;
    case 'not-found':
      return NOT_FOUND;
    case 'on-hold':
      // `reserved_by_other`: status 'reserved', a live hold, held by someone who is not the viewer.
      // The only identity-bearing state that needs no session — "not you" is true of nobody too.
      return {
        ...LIVE,
        listing: {
          ...LISTING_FIXTURE,
          status: 'reserved',
          reserved_by: OTHER_BUYER,
          reserved_until: minutesFromNow(7),
        } as Listing,
      };
    case 'won':
      // `won` + `pay_now`: the auction is ENDED (not sold) and the row's winner is the viewer.
      // `ends_at` is in the past, which is what the board shows; with a fixture the screen runs no
      // `finalize_auction` and — because `auction_status` is already 'ended' — no result poll.
      // ONE SIDE EFFECT TO EXPECT, and it is the real screen's: this is the state whose effect
      // fires the success haptic and the LOCAL "You Snatched It" notification (no server, nothing
      // stored), so a capture may catch that banner over the top of the screen. Take it twice.
      return viewerId
        ? {
            ...LIVE,
            viewerId,
            bids: winningBids(viewerId),
            listing: {
              ...LISTING_FIXTURE,
              auction_status: 'ended',
              ends_at: minutesFromNow(-6),
              winner_user_id: viewerId,
            } as Listing,
          }
        : null;
    case 'reserved-by-you':
      // `reserved_by_you` + `continue_reservation` ("Finish checkout"): the hold is the viewer's and
      // still alive, so the banner carries the screen's own live countdown.
      return viewerId
        ? {
            ...LIVE,
            viewerId,
            bids: bidsAsViewer(viewerId),
            listing: {
              ...LISTING_FIXTURE,
              status: 'reserved',
              reserved_by: viewerId,
              reserved_until: minutesFromNow(7),
            } as Listing,
          }
        : null;
    case 'own-listing':
      // The seller's own view: `role === 'seller'`, so the resolver offers "Your listing" disabled
      // with its sentence outside the pill, and the overflow menu becomes the owner's menu.
      return viewerId
        ? {
            ...LIVE,
            viewerId,
            bids: bidsAsViewer(viewerId),
            listing: { ...LISTING_FIXTURE, seller_id: viewerId } as Listing,
          }
        : null;
    default:
      return LIVE;
  }
}

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

  // The real viewer, read from the same hook the mounted screen reads. Only the four
  // identity-decided variants use it; see the header.
  const { user } = useAuth();

  // Stable per variant and per viewer: the screen's effects close over the fixture, so an identity
  // that changed every render would re-run them for nothing.
  const fixture = useMemo(() => fixtureFor(variant, user?.id), [variant, user?.id]);

  if (!IS_SANDBOX_BUILD && !__DEV__) return <Redirect href="/" />;

  switch (screen) {
    case 'listing':
      return fixture ? (
        <ListingDetailScreen id="fixture-listing" fixture={fixture} />
      ) : (
        <HarnessNote
          title={`?variant=${variant ?? ''} needs a signed-in viewer`}
          body={
            'This state is decided by comparing the row against the viewer’s own id, which comes ' +
            'from the app’s auth and not from the fixture. Sign in on this build and reload, or ' +
            'capture one of the states that needs no viewer.'
          }
        />
      );
    default:
      return <Redirect href="/" />;
  }
}

/**
 * A harness message, never a screen. It exists so a variant that cannot be produced says so
 * instead of silently painting a DIFFERENT state under the requested name.
 */
function HarnessNote({ title, body }: { title: string; body: string }) {
  const { palette } = useTheme();
  const s = useMemo(() => noteStyles(palette), [palette]);
  return (
    <View style={s.wrap}>
      <Text style={[textStyle('screenTitle'), s.title]}>{title}</Text>
      <Text style={[textStyle('body'), s.body]}>{body}</Text>
      <Text style={[textStyle('micro'), s.foot]}>
        {`Harness note — not an app state. Variants: ${VARIANTS.join(', ')} (${NEEDS_VIEWER.join(', ')} need a viewer).`}
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

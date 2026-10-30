/**
 * app/_dev/v3-screens.tsx — the V3 rendering harness (owner 2026-09-24).
 *
 * WHY IT EXISTS. The V3 corrections have to be compared against the approved boards as the
 * ACTUAL APP RENDERS THEM, and every screen that matters sits behind authentication and behind
 * rows the sandbox may not hold. The owner authorised "safe local rendering fixtures for
 * otherwise unreachable visual states" and required real application components rather than a
 * recreated mock. So this route mounts the REAL screen components with fixture data supplied in
 * place of their network read — the same components `/bid/[id]` and the rest push.
 *
 * WHAT A RENDER HERE PROVES, AND WHAT IT DOES NOT. It proves what the component paints from the
 * given props: composition, spacing, type, colour roles, shapes, wrapping, both appearances. It
 * proves nothing about the data path that normally supplies those props, nothing about native
 * iOS rendering, and nothing about behaviour that needs a server.
 *
 * NOT REACHABLE IN PRODUCTION. Like `_dev/transfer-states`, the route renders a redirect unless
 * this is a paired sandbox build or a `__DEV__` bundle, so a production binary cannot show it
 * through navigation or a deep link.
 *
 * NO WRITES. Nothing here reads or writes a server. The fixtures are literals in this file.
 */

import { Redirect, useLocalSearchParams } from 'expo-router';
import { useEffect } from 'react';

import { IS_SANDBOX_BUILD } from '@/src/config/envGuard';
import { useAppearancePreference } from '@/src/theme/appearance';
import PlaceBidScreen from '@/src/screens/PlaceBidScreen';
import type { Listing } from '@/src/types';

declare const __DEV__: boolean;

/**
 * The board's sample content (owner: "Sample event names, prices, photographs and dates are not
 * production data"), so a render can be laid beside `pkg8-bid-dark.png` value for value.
 */
export const BID_FIXTURE: Partial<Listing> = {
  id: 'fixture-bid',
  event_name: 'Neon Choir',
  event_date: '2026-10-24',
  event_time: '19:30',
  venue: 'Lantern Room',
  quantity: 2,
  ticket_type: 'GA',
  current_bid: 90,
  bid_count: 3,
  auction_status: 'active',
};

/** The same listing with no bids, which is the screen's "Starting bid" branch. */
export const BID_FIXTURE_NO_BIDS: Partial<Listing> = {
  ...BID_FIXTURE,
  current_bid: 90,
  bid_count: 0,
};

export default function V3ScreensHarness() {
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
    case 'bid':
      return (
        <PlaceBidScreen
          id="fixture-bid"
          fixture={(variant === 'nobids' ? BID_FIXTURE_NO_BIDS : BID_FIXTURE) as Listing}
        />
      );
    default:
      return <Redirect href="/" />;
  }
}

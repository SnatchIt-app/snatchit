/**
 * app/_dev/v3-profile.tsx — the public seller profile, rendered by the real screen.
 *
 * WHY IT EXISTS. `app/profile/[id].tsx` renders an event image (`CHECKOUT_THUMBNAIL`, line 64) and
 * was mounted by no dev route at all, so it was the one poster surface the 4:5 review could not
 * reach — and its blocked and stats-unavailable states had never been looked at either.
 *
 * WHAT THE FIXTURE STANDS IN FOR. The four reads the screen makes: the block row, the profile, the
 * trust-stats RPC and the seller's active listings. The viewer still comes from the screen's own
 * `useAuth()`, which no prop may replace (v3-listing's rule), and Block short-circuits under a
 * fixture, so nothing here can write a `user_blocks` row. This route imports no client.
 *
 * `?art=` puts a bundled poster on the listing rows, same vocabulary as every other harness.
 *
 * NOT REACHABLE IN PRODUCTION: a paired sandbox build or a `__DEV__` bundle only.
 */

import { Redirect, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo } from 'react';

import PublicProfileScreen, { type PublicProfileFixture } from '@/app/profile/[id]';
import { IS_SANDBOX_BUILD } from '@/src/config/envGuard';
import { listArt } from '@/src/lib/media/harnessArt';
import { useAppearancePreference } from '@/src/theme/appearance';
import type { Listing, ProfileTrustStats } from '@/src/types';

declare const __DEV__: boolean;

/** Sample content, not production data (the owner's standing caveat on every fixture). */
const PROFILE = {
  id: 'fixture-seller',
  display_name: 'Lantern Room Regulars',
  avatar_url: null,
  avatar_path: null,
  bio: 'Two or three nights a month, mostly around the harbour.',
  created_at: '2026-02-11T00:00:00Z',
  is_verified_seller: true,
  stripe_onboarding_complete: true,
};

const TRUST: ProfileTrustStats = {
  completed_sales: 14,
  on_time_rate: 0.93,
  disputes: 0,
  cancellations: 1,
} as unknown as ProfileTrustStats;

const LISTING_BASE = {
  seller_id: 'fixture-seller',
  venue: 'Lantern Room',
  status: 'active',
  auction_status: 'active',
  quantity: 2,
  ticket_type: 'GA',
  bid_count: 3,
  current_bid: 90,
  starting_bid: 60,
} as const;

function listings(art: string | undefined): Listing[] {
  const rows = [
    { ...LISTING_BASE, id: 'fixture-pl1', event_name: 'Neon Choir', ends_at: '2026-10-24T23:00:00-04:00' },
    { ...LISTING_BASE, id: 'fixture-pl2', event_name: 'Midnight Arcade', ends_at: '2026-11-06T23:00:00-05:00' },
  ];
  // Every row takes the selected poster; `all` cycles the shapes. Same rule as the other lists.
  const covers = listArt(art, rows.length);
  return rows.map((l, i) => ({ ...l, cover_image_path: covers[i] })) as unknown as Listing[];
}

function fixtureFor(variant: string | undefined, art: string | undefined): PublicProfileFixture {
  switch (variant) {
    // A row-less answer: the screen's "Profile unavailable" state.
    case 'not-found': return { profile: null };
    // The viewer has blocked this seller: stats and listings are withheld by the SCREEN, which is
    // why the fixture still carries both — a harness that omitted them would prove nothing.
    case 'blocked': return { profile: PROFILE, blocked: true, trust: TRUST, listings: listings(art) };
    // The stats read FAILED. Not the same fact as a seller with no history, and worth a look.
    case 'stats-unavailable': return { profile: PROFILE, statsUnavailable: true, listings: listings(art) };
    // A seller with history but nothing live right now.
    case 'no-listings': return { profile: PROFILE, trust: TRUST, listings: [] };
    default: return { profile: PROFILE, trust: TRUST, listings: listings(art) };
  }
}

export default function V3ProfileHarness() {
  const { variant, appearance, art } = useLocalSearchParams<{
    variant?: string; appearance?: string; art?: string;
  }>();
  // `?appearance=light|dark` drives the capture from the app's own stored preference.
  const { setPreference } = useAppearancePreference();
  useEffect(() => {
    if (appearance === 'light' || appearance === 'dark' || appearance === 'system') {
      setPreference(appearance);
    }
  }, [appearance]);

  const fixture = useMemo(() => fixtureFor(variant, art), [variant, art]);

  if (!IS_SANDBOX_BUILD && !__DEV__) return <Redirect href="/" />;

  return <PublicProfileScreen fixture={fixture} />;
}

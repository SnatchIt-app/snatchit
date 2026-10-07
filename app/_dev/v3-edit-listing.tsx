/**
 * app/_dev/v3-edit-listing.tsx — Edit listing's refusals, rendered by the real screen.
 *
 * WHY IT EXISTS. `app/listing/edit/[id].tsx` was in no harness, so the refusal state added in
 * 6c562dcf had behavioural tests and nothing a reviewer could look at. E's finding was that two of
 * those paths left the screen spinning for ever; the fix replaced the spinner with a state that
 * carries one action, and an action is exactly the kind of thing that has to be SEEN to be
 * believed — a spinner swapped for a dead button is not a fix.
 *
 * WHAT THE FIXTURE STANDS IN FOR, AND WHAT IT MUST NOT. It seeds the READ only. The viewer still
 * comes from the screen's own `useAuth()`, which no prop may replace (v3-listing's rule), so this
 * route reads the same session the screen reads and puts that real id on the row for the cases
 * where the seller owns the listing. Two consequences worth stating rather than discovering:
 *
 *   - `signed-out` is NOT offered here. Seeding it would mean a prop standing in for
 *     authentication, which is the one thing these harnesses may not do. It keeps its behavioural
 *     coverage (EL2e) instead.
 *   - open this route without a session and you will see the signed-out refusal rather than the
 *     variant you asked for. That is not the harness failing; it is the real screen telling the
 *     truth about the real session.
 *
 * NO WRITES. Save short-circuits under a fixture (`if (fixture) return;` in the screen), so
 * nothing here can update a listing, and this route imports no client.
 *
 * NOT REACHABLE IN PRODUCTION: a paired sandbox build or a `__DEV__` bundle only.
 */

import { Redirect, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo } from 'react';

import EditListingScreen, { type EditListingFixture } from '@/app/listing/edit/[id]';
import { IS_SANDBOX_BUILD } from '@/src/config/envGuard';
import { useAuth } from '@/src/hooks/useAuth';
import { useAppearancePreference } from '@/src/theme/appearance';
import type { Listing } from '@/src/types';

declare const __DEV__: boolean;

/** Sample content, not production data (the owner's standing caveat on every fixture). */
const BASE = {
  id: 'fixture-edit-1',
  event_name: 'Neon Choir',
  venue: 'Lantern Room',
  restrictions: null,
  ticket_platform: 'dice',
  bid_count: 0,
  status: 'active',
  auction_status: 'active',
  quantity: 2,
  ticket_type: 'GA',
} as const;

/**
 * The four refusals a READ can produce, plus the row that opens the form.
 *
 * `viewerId` is the screen's own session id, so `ok`, `has-bids` and `inactive` are the viewer's
 * OWN listing — the eligibility check is the screen's, and these cases have to pass its ownership
 * test on the way to the one being reviewed.
 */
function fixtureFor(variant: string | undefined, viewerId: string): EditListingFixture {
  const row = (over: Record<string, unknown> = {}) =>
    ({ ...BASE, seller_id: viewerId, ...over }) as unknown as Listing;
  switch (variant) {
    // A row-less answer. The read's own sentence is what the screen shows, as it does live.
    case 'not-found': return { row: null, readError: 'No listing with that id' };
    // Someone else's listing: the ownership refusal.
    case 'not-owner': return { row: row({ seller_id: 'fixture-other-seller' }) };
    // Bidding has started, so the metadata is no longer the seller's to change.
    case 'has-bids': return { row: row({ bid_count: 6, current_bid: 90 }) };
    // The auction is over or cancelled.
    case 'inactive': return { row: row({ auction_status: 'ended' }) };
    // A failed read, which is a refusal of its own and carries the server's sentence.
    case 'read-failed': return { row: null, readError: 'The listing could not be read' };
    default: return { row: row() };
  }
}

export default function V3EditListingHarness() {
  const { variant, appearance } = useLocalSearchParams<{ variant?: string; appearance?: string }>();
  // `?appearance=light|dark` drives the capture from the app's own stored preference — the one
  // Settings writes — rather than a browser emulation flag.
  const { setPreference } = useAppearancePreference();
  useEffect(() => {
    if (appearance === 'light' || appearance === 'dark' || appearance === 'system') {
      setPreference(appearance);
    }
  }, [appearance]);

  // The screen's own auth, read here only so the owner cases can be the viewer's own listing.
  const { user } = useAuth();
  const viewerId = user?.id ?? '';
  const fixture = useMemo(() => fixtureFor(variant, viewerId), [variant, viewerId]);

  if (!IS_SANDBOX_BUILD && !__DEV__) return <Redirect href="/" />;

  return <EditListingScreen fixture={fixture} />;
}

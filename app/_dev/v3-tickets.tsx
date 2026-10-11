/**
 * app/_dev/v3-tickets.tsx — the V3 TICKETS rendering harness (owner 2026-09-24).
 *
 * WHY IT EXISTS. Same reason as `app/_dev/v3-screens.tsx`, which this copies: the V3 corrections
 * have to be compared against the approved boards as the ACTUAL APP RENDERS THEM, and the Tickets
 * tab sits behind authentication and behind an RPC that legitimately returns `[]` for every user
 * today — the populated and past states are otherwise unreachable. The owner authorised "safe
 * local rendering fixtures for otherwise unreachable visual states" and required the real
 * application components rather than a recreated mock, so this route mounts the REAL
 * `TicketsScreen` with fixture rows supplied in place of its one network read — the same
 * component the Tickets tab renders. Fixture rows render under the owner-ruled sample caveat
 * ("Sample tickets — no server data"), so a capture can never circulate as issuance working.
 *
 * WHAT A RENDER HERE PROVES, AND WHAT IT DOES NOT. It proves what the component paints from the
 * given rows: composition, spacing, type, colour roles, shapes, wrapping, both appearances. It
 * proves nothing about the data path that normally supplies those rows, nothing about native iOS
 * rendering, and nothing about behaviour that needs a server.
 *
 * NOT REACHABLE IN PRODUCTION. Like the other `_dev` routes, the segment layout gates the whole
 * group and this file redirects on its own too: a production binary cannot show it through
 * navigation or a deep link.
 *
 * NO WRITES. Nothing here reads or writes a server. The fixtures are literals in this file.
 */

import { Redirect, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo } from 'react';

import { IS_SANDBOX_BUILD } from '@/src/config/envGuard';
import { listArt } from '@/src/lib/media/harnessArt';
import { useAppearancePreference } from '@/src/theme/appearance';
import TicketsScreen, { type TicketsFixture } from '@/app/(tabs)/tickets';
import TransferReceiveScreen, { type OrderFixture } from '@/app/transfer/receive/[id]';
import TransferSendScreen, { type SendFixture } from '@/app/transfer/send/[id]';
import type { MyTicketGroup } from '@/src/lib/tickets/types';

declare const __DEV__: boolean;

/** Shared literal base — every row is a complete `MyTicketGroup`, exactly the RPC's shape. */
const BASE: MyTicketGroup = {
  event_id: 'fixture-e1', event_session_id: 'fixture-s1',
  event_title: 'Neon Choir', session_label: null,
  starts_at: '2026-10-24T19:30:00-04:00', ends_at: null, doors_at: null,
  venue_id: 'fixture-v1', venue_name: 'Lantern Room',
  artwork_ref: null,
  ticket_type_id: 'fixture-t1', ticket_type_name: 'GA', ticket_type_kind: 'admission',
  quantity: 2, ownership_status: 'valid', fulfillment_status: 'held', time_class: 'upcoming',
};

/**
 * The board's populated state (`pkg8-account-tickets-{dark,light}.png`): "Neon Choir · 2 x GA ·
 * Valid" and "Midnight Arcade · 1 x VIP · Transfer in progress". Sample content only (owner:
 * "Sample event names, prices, photographs and dates are not production data").
 */
const POPULATED: MyTicketGroup[] = [
  BASE,
  {
    ...BASE,
    event_id: 'fixture-e2', event_session_id: 'fixture-s2',
    event_title: 'Midnight Arcade', venue_id: 'fixture-v2', venue_name: 'Arcade Hall',
    starts_at: '2026-11-06T22:00:00-05:00',
    ticket_type_id: 'fixture-t2', ticket_type_name: 'VIP', ticket_type_kind: 'admission',
    quantity: 1, fulfillment_status: 'in_transfer',
  },
];

/** Past/expired coverage: both sections mounted, every past ownership word on screen. */
const PAST: MyTicketGroup[] = [
  BASE,
  {
    ...BASE,
    event_id: 'fixture-e3', event_session_id: 'fixture-s3',
    event_title: 'Winter Warehouse', venue_name: 'Lantern Room',
    starts_at: '2026-08-30T21:00:00-04:00', ends_at: '2026-08-31T02:00:00-04:00',
    ticket_type_id: 'fixture-t3', quantity: 2,
    ownership_status: 'used', time_class: 'past',
  },
  {
    ...BASE,
    event_id: 'fixture-e4', event_session_id: 'fixture-s4',
    event_title: 'Autumn Sessions', venue_name: 'Arcade Hall',
    starts_at: '2026-07-12T20:00:00-04:00', ends_at: '2026-07-13T01:00:00-04:00',
    ticket_type_id: 'fixture-t4', quantity: 1,
    ownership_status: 'expired', time_class: 'past',
  },
  {
    ...BASE,
    event_id: 'fixture-e5', event_session_id: 'fixture-s5',
    event_title: 'Cancelled Showcase', venue_name: 'Lantern Room',
    starts_at: '2026-09-18T20:00:00-04:00', ends_at: '2026-09-19T01:00:00-04:00',
    ticket_type_id: 'fixture-t5', quantity: 1,
    ownership_status: 'void', time_class: 'past',
  },
];

/**
 * `?art=` for the ticket board: every group takes the selected poster (`all` cycles the shapes).
 *
 * A bundled poster asserts nothing about where real ticket artwork comes from. These rows are on
 * a different media contract from listings — `{ bucket: 'event-media', contract: 'v2' }` in
 * TicketEventGroup — and the dev branch in `resolveImage` runs before anything storage-shaped
 * happens, so the marker renders the same either way. What `artwork_ref` is MEANT to carry is a
 * contract question for A and is untouched here.
 */
function withTicketArt(rows: MyTicketGroup[], art: string | undefined): MyTicketGroup[] {
  const covers = listArt(art, rows.length);
  return rows.map((g, i) => (covers[i] ? { ...g, artwork_ref: covers[i] } : g));
}

function fixtureFor(variant: string | undefined, art: string | undefined): TicketsFixture {
  switch (variant) {
    case 'empty': return { rows: [] };          // the state that ships today
    case 'past': return { rows: withTicketArt(PAST, art) };
    case 'error': return { failure: 'error' };  // first-load failure, F-22's other half
    case 'offline': return { failure: 'offline' };
    default: return { rows: withTicketArt(POPULATED, art) };
  }
}

/**
 * `screen=order` and `screen=send` mount the REAL Transfer screens, whose lead poster reads the
 * listing cover rather than the ticket artwork — a different field, so it takes its own override.
 */
function withTransferArt<T extends { transfer: { listing?: { cover_image_path?: string | null } | null } }>(
  fixture: T,
  art: string | undefined,
): T {
  const covers = listArt(art, 1);
  if (!covers[0] || !fixture.transfer.listing) return fixture;
  return {
    ...fixture,
    transfer: { ...fixture.transfer, listing: { ...fixture.transfer.listing, cover_image_path: covers[0] } },
  };
}

export default function V3TicketsHarness() {
  const { screen, variant, appearance, art } = useLocalSearchParams<{
    screen?: string; variant?: string; appearance?: string; art?: string;
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

  // Stable per variant: the screen's `load` closes over the fixture, so an identity that
  // changed every render would re-run its focus effect for nothing.
  const fixture = useMemo(() => fixtureFor(variant, art), [variant, art]);

  if (!IS_SANDBOX_BUILD && !__DEV__) return <Redirect href="/" />;

  switch (screen) {
    case 'tickets':
      return <TicketsScreen fixture={fixture} />;
    case 'order':
      // The board's order state: seller_sent, mobile transfer via DICE, a $99.00 settled charge,
      // the review deadline from the server. Reads only; every action still needs the real server.
      return <TransferReceiveScreen fixture={withTransferArt(ORDER_FIXTURE, art)} />;
    case 'send':
      // The seller's marked-sent state from pkg8-send. Read short-circuit only.
      return <TransferSendScreen fixture={withTransferArt(SEND_FIXTURE, art)} />;
    default:
      return <Redirect href="/" />;
  }
}

/** The board's sample order (sample content, not production data). */
const ORDER_FIXTURE: OrderFixture = {
  transfer: {
    id: 'fixture-order',
    listing_id: 'fixture-listing',
    status: 'seller_sent',
    transfer_method: 'mobile_transfer',
    expires_at: null,
    auto_release_at: new Date(Date.now() + 40 * 3600_000).toISOString(),
    buyer_confirmed_at: null,
    payout_released_at: null,
    dispute_resolution: null,
    dispute_resolved_at: null,
    delivery_email: 'buyer@example.test',
    delivery_phone: null,
    transfer_evidence_path: 'fixtures/proof.jpg',
    seller: { display_name: 'the seller' },
    listing: {
      event_name: 'Neon Choir',
      ticket_platform: 'dice',
      event_date: '2026-10-24',
      event_time: '19:30',
      venue: 'Lantern Room',
      quantity: 2,
      ticket_type: 'GA',
      cover_image_path: null,
    },
  },
  settled: [{ status: 'succeeded', amount_refunded_cents: null, refunded_at: null, total: 9900 }],
};

/** The seller's side of the same sample order (pkg8-send: marked sent, phone delivery). */
const SEND_FIXTURE: SendFixture = {
  transfer: {
    ...ORDER_FIXTURE.transfer,
    status: 'seller_sent',
    delivery_email: null,
    delivery_phone: '(305) 555-4417',
    payout_review_status: null,
    payout_hold_until: null,
    buyer: { display_name: 'Buyer One' },
  } as SendFixture['transfer'],
};

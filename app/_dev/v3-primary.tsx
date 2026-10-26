/**
 * app/_dev/v3-primary.tsx — rendering harness for primary discovery and event detail.
 *
 * Renders the REAL `PrimaryEventsView` / `PrimarySessionView` from literals shaped like D's 182 rows,
 * so every state can be captured at every type size and appearance without the (dark) reads. It proves
 * layout, copy and contrast only — nothing about the reads, availability or prices on any server — and
 * every variant carries a visible sample caveat. NO WRITES. Gated like every `_dev` route.
 *
 *   /_dev/v3-primary?screen=event&variant=on-sale|sold-out|not-yet|ended|no-fee|not-available|offline|error
 *   /_dev/v3-primary?screen=list&variant=list|empty|offline
 */
import { Redirect, useLocalSearchParams } from 'expo-router';
import { useMemo } from 'react';

import { IS_SANDBOX_BUILD } from '@/src/config/envGuard';
import { parsePrimarySession, type DiscoveryLoad, type PrimaryTier, type SessionDetailLoad } from '@/src/lib/primary/discovery';
import { whenFromLocal } from '@/src/lib/tickets/ticketWhen';
import { PrimaryEventsView } from '@/src/screens/primary/PrimaryEventsView';
import { PrimarySessionView } from '@/src/screens/primary/PrimarySessionView';

declare const __DEV__: boolean;

const SESSION = '00000000-0000-4000-8000-0000000000a1';
const NOW = Date.parse('2026-11-10T17:00:00Z');

/** Sample all-in figures for layout only — NOT the configured fee (which is unset). */
const tier = (over: Partial<PrimaryTier>): PrimaryTier => ({
  ticket_type_id: `00000000-0000-4000-8000-0000000000b${over.display_rank ?? 1}`, name: 'GA', price_minor: 2000, currency: 'USD',
  visibility: 'public', display_rank: 1, sale_starts_at: null, sale_ends_at: null, on_sale_now: true, remaining: 40, all_in_price_minor: 2200, ...over,
});

function sessionRow(tiers: PrimaryTier[]) {
  return {
    session: {
      session_id: SESSION, event_id: 'sample-event', session_label: null, starts_at: '2026-12-01T04:00:00Z', ends_at: '2026-12-01T09:00:00Z',
      doors_at: '2026-12-01T03:00:00Z', status: 'scheduled', timezone: 'America/New_York',
      starts_at_local: '2026-11-30 23:00', ends_at_local: '2026-12-01 04:00', doors_at_local: '2026-11-30 22:00',
    },
    event: { event_id: 'sample-event', title: 'Sample pop-up (not a real event)', description: 'House music, two DJs. Sample text for layout only.', hero_image_ref: null, category: 'nightlife', genre_tags: ['house'], status: 'on_sale', age_restriction: '21_plus' },
    venue: { venue_id: 'sample-venue', name: 'Venue to be announced', neighborhood: 'Wynwood', address: null, timezone: 'America/New_York' },
    ticket_types: tiers,
  };
}

function eventFixture(variant: string | undefined): SessionDetailLoad {
  const ready = (tiers: PrimaryTier[]): SessionDetailLoad => {
    const detail = parsePrimarySession(sessionRow(tiers));
    return detail ? { kind: 'ready', detail } : { kind: 'failed', failure: 'unavailable' };
  };
  switch (variant) {
    case 'sold-out': return ready([tier({ name: 'Early GA', remaining: 0 }), tier({ name: 'GA', display_rank: 2, remaining: 0 })]);
    case 'not-yet': return ready([tier({ name: 'Final GA', on_sale_now: false, sale_starts_at: '2026-11-20T15:00:00Z' })]);
    case 'ended': return ready([tier({ name: 'Early GA', on_sale_now: false, sale_ends_at: '2026-11-01T00:00:00Z' })]);
    case 'no-fee': return ready([tier({ name: 'GA', all_in_price_minor: null })]);
    case 'not-available': return { kind: 'not_available' };
    case 'offline': return { kind: 'failed', failure: 'offline' };
    case 'error': return { kind: 'failed', failure: 'unavailable' };
    default: return ready([
      tier({ name: 'Early GA', display_rank: 1, remaining: 0 }),
      tier({ name: 'GA', display_rank: 2, price_minor: 2500, all_in_price_minor: 2750 }),
      tier({ name: 'Final GA', display_rank: 3, price_minor: 3000, all_in_price_minor: 3300, on_sale_now: false, sale_starts_at: '2026-11-25T15:00:00Z' }),
    ]);
  }
}

function listFixture(variant: string | undefined): DiscoveryLoad {
  if (variant === 'empty') return { kind: 'ready', rows: [] };
  if (variant === 'offline') return { kind: 'failed', failure: 'offline' };
  return {
    kind: 'ready',
    rows: [{
      eventId: 'sample-event', sessionId: SESSION, title: 'Sample pop-up (not a real event)', venueName: 'Venue to be announced',
      neighborhood: 'Wynwood', startsAt: '2026-12-01T04:00:00Z', doorsAt: '2026-12-01T03:00:00Z', ageRestriction: '21_plus', status: 'on_sale',
    }],
  };
}

export default function V3PrimaryHarness() {
  const { screen, variant } = useLocalSearchParams<{ screen?: string; variant?: string }>();
  const event = useMemo(() => eventFixture(variant), [variant]);
  const list = useMemo(() => listFixture(variant), [variant]);
  if (!(IS_SANDBOX_BUILD || __DEV__)) return <Redirect href="/(tabs)/home" />;
  if (screen === 'list') {
    const when = whenFromLocal({ startsAtLocal: '2026-11-30 23:00', doorsAtLocal: '2026-11-30 22:00', timezone: 'America/New_York', startsAt: '2026-12-01T04:00:00Z' });
    return (
      <PrimaryEventsView load={list} whenBySession={{ [SESSION]: when }} refreshing={false} onRefresh={() => {}} onOpen={() => {}} sampleCaveat />
    );
  }
  return <PrimarySessionView load={event} nowMs={NOW} refreshing={false} onRefresh={() => {}} sampleCaveat />;
}

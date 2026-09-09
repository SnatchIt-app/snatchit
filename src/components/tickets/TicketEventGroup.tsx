/**
 * src/components/tickets/TicketEventGroup.tsx — one owned event, event-first.
 *
 * Renders a session's owned tickets as a single card. Distinct contract rows
 * (ownership x fulfillment x type) stay distinct inside it — a "2 held / 1 listed"
 * holding shows two clear lines under one event, never a merged number. Upcoming
 * is the loud, artwork-led state; Past is a quieter row. Non-tappable: there is no
 * truthful Ticket Detail action yet (Core gate), so the card does not navigate.
 *
 * Ownership/fulfillment words come from ticketState (truthful to the Core
 * vocabulary); state is never color-only — every badge carries its word.
 */

import { memo } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { Badge } from '@/src/components/ui';
import { EventMedia } from '@/src/components/media/EventMedia';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import {
  eventDateLabel,
  fulfillmentLabel,
  fulfillmentTone,
  ownershipLabel,
  ownershipTone,
  showFulfillmentBadge,
  ticketTypeLine,
  type EventGroup,
} from '@/src/lib/tickets/ticketState';
import type { MyTicketGroup } from '@/src/lib/tickets/types';

function rowA11yLabel(r: MyTicketGroup): string {
  const parts = [ticketTypeLine(r), ownershipLabel(r.ownership_status)];
  if (showFulfillmentBadge(r.fulfillment_status)) parts.push(fulfillmentLabel(r.fulfillment_status));
  return parts.join(', ');
}

function groupA11yLabel(g: EventGroup): string {
  const head = [g.event_title, eventDateLabel(g.starts_at), g.venue_name].filter(Boolean).join(', ');
  return `${head}. ${g.rows.map(rowA11yLabel).join('. ')}`;
}

function StateRow({ row, quiet }: { row: MyTicketGroup; quiet?: boolean }) {
  return (
    <View style={s.row} accessible accessibilityLabel={rowA11yLabel(row)}>
      <Text style={[textStyle('body'), quiet ? s.rowTextQuiet : s.rowText]} numberOfLines={1}>
        {ticketTypeLine(row)}
      </Text>
      <View style={s.badges}>
        <Badge label={ownershipLabel(row.ownership_status)} tone={ownershipTone(row.ownership_status)} />
        {showFulfillmentBadge(row.fulfillment_status) ? (
          <Badge label={fulfillmentLabel(row.fulfillment_status)} tone={fulfillmentTone(row.fulfillment_status)} />
        ) : null}
      </View>
    </View>
  );
}

export const TicketEventGroup = memo(function TicketEventGroup({
  group,
  emphasis,
}: {
  group: EventGroup;
  emphasis: 'upcoming' | 'past';
}) {
  const asset = { path: group.artwork_ref, bucket: 'event-media' as const, contract: 'v2' as const };
  const dateLine = eventDateLabel(group.starts_at);

  if (emphasis === 'past') {
    return (
      <View style={s.pastCard} accessible accessibilityLabel={groupA11yLabel(group)}>
        <View style={s.pastThumb}>
          <EventMedia asset={asset} slot="SEARCH_RESULT" width={64} />
        </View>
        <View style={s.pastBody}>
          <Text style={[textStyle('title'), s.pastTitle]} numberOfLines={1}>{group.event_title}</Text>
          {dateLine ? <Text style={[textStyle('bodySm'), s.metaQuiet]} numberOfLines={1}>{dateLine}</Text> : null}
          <Text style={[textStyle('bodySm'), s.metaQuiet]} numberOfLines={1}>{group.venue_name}</Text>
          <View style={s.pastRows}>
            {group.rows.map((r, i) => (
              <StateRow key={`${r.ticket_type_id}:${r.ownership_status}:${r.fulfillment_status}:${i}`} row={r} quiet />
            ))}
          </View>
        </View>
      </View>
    );
  }

  return (
    <View style={s.card} accessible accessibilityLabel={groupA11yLabel(group)}>
      <EventMedia asset={asset} slot="TICKET_ART" fluid />
      <View style={s.body}>
        <Text style={[textStyle('title'), s.title]} numberOfLines={2}>{group.event_title}</Text>
        {dateLine ? <Text style={[textStyle('body'), s.meta]} numberOfLines={1}>{dateLine}</Text> : null}
        <Text style={[textStyle('body'), s.meta]} numberOfLines={1}>
          {group.venue_name}{group.session_label ? `  -  ${group.session_label}` : ''}
        </Text>
        <View style={s.rows}>
          {group.rows.map((r, i) => (
            <StateRow key={`${r.ticket_type_id}:${r.ownership_status}:${r.fulfillment_status}:${i}`} row={r} />
          ))}
        </View>
      </View>
    </View>
  );
});

const s = StyleSheet.create({
  // Upcoming — artwork-led card.
  card: {
    backgroundColor: v2.surface.surface,
    borderWidth: 1,
    borderColor: v2.border.default,
    marginBottom: v2.space.lg,
  },
  body: { padding: v2.space.lg, gap: v2.space.xs },
  title: { color: v2.text.primary },
  meta: { color: v2.text.secondary },
  rows: { marginTop: v2.space.md, gap: v2.space.sm },

  row: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: v2.space.md, minHeight: 32 },
  rowText: { color: v2.text.primary, flexShrink: 1 },
  rowTextQuiet: { color: v2.text.secondary, flexShrink: 1 },
  badges: { flexDirection: 'row', alignItems: 'center', gap: v2.space.xs, flexShrink: 0 },

  // Past — quieter row.
  pastCard: {
    flexDirection: 'row',
    gap: v2.space.md,
    paddingVertical: v2.space.md,
    borderBottomWidth: 1,
    borderBottomColor: v2.border.default,
    opacity: 0.92,
  },
  pastThumb: { width: 64, height: 64, overflow: 'hidden' },
  pastBody: { flex: 1, gap: 2 },
  pastTitle: { color: v2.text.primary },
  metaQuiet: { color: v2.text.muted },
  pastRows: { marginTop: v2.space.xs, gap: v2.space.xs },
});

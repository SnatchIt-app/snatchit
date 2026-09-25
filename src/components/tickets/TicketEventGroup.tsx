/**
 * src/components/tickets/TicketEventGroup.tsx — one owned event, event-first.
 *
 * Renders a session's owned tickets as a single card. Distinct contract rows
 * (ownership x fulfillment x type) stay distinct inside it — a "2 held / 1 listed"
 * holding shows two clear lines under one event, never a merged number. Upcoming
 * is the loud, artwork-led state; Past is a quieter row. Non-tappable: there is no
 * truthful Ticket Detail action yet (Core gate), so the card does not navigate.
 *
 * Both artwork slots are 4:5 posters (owner 2026-09-24). The upcoming card's poster is the card's
 * width, so its height follows the ratio and it is much taller than the 16:9 strip it replaces; the
 * past row's is the row's 64pt height, so its width follows. Neither shape is written here — the
 * slot owns the frame, its fit and its radius.
 *
 * Ownership/fulfillment words come from ticketState (truthful to the Core
 * vocabulary); state is never color-only — every badge carries its word.
 */

import { memo, useMemo } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { Badge } from '@/src/components/ui';
import { EventMedia } from '@/src/components/media/EventMedia';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';
import {
  eventDateLabel,
  fulfillmentLabel,
  fulfillmentTone,
  ownershipLabel,
  ownershipTone,
  showFulfillmentBadge,
  showOwnershipBadge,
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

function StateRow({ s, row, quiet }: { s: Styles; row: MyTicketGroup; quiet?: boolean }) {
  return (
    <View style={s.row} accessible accessibilityLabel={rowA11yLabel(row)}>
      <Text style={[textStyle('body'), quiet ? s.rowTextQuiet : s.rowText]} numberOfLines={1}>
        {ticketTypeLine(row)}
      </Text>
      <View style={s.badges}>
        {/* V3 (pkg8-account-tickets): one meaningful word per row — 'Valid' yields to a
            surfaced fulfillment state; a non-valid ownership word always shows. The full
            state pair stays in the a11y label above, which never hides a true word. */}
        {showOwnershipBadge(row.ownership_status, row.fulfillment_status) ? (
          <Badge label={ownershipLabel(row.ownership_status)} tone={ownershipTone(row.ownership_status)} />
        ) : null}
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
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const asset = { path: group.artwork_ref, bucket: 'event-media' as const, contract: 'v2' as const };
  const dateLine = eventDateLabel(group.starts_at);

  if (emphasis === 'past') {
    return (
      <View style={s.pastCard} accessible accessibilityLabel={groupA11yLabel(group)}>
        {/* 64 is the row's HEIGHT budget, so it goes to EventMedia as `height` and the 4:5 poster
            takes the width the ratio gives it. The wrapper carries the dim and nothing else — see
            `pastThumb`. */}
        <View style={s.pastThumb}>
          <EventMedia asset={asset} slot="SEARCH_RESULT" height={64} />
        </View>
        <View style={s.pastBody}>
          {/* V3: event names carry the mixed-case display voice (owner amendment 2026-09-22);
              the quiet past row takes the row step. */}
          <Text style={[textStyle('nameRow'), s.pastTitle]} numberOfLines={1}>{group.event_title}</Text>
          {dateLine ? <Text style={[textStyle('bodySm'), s.metaQuiet]} numberOfLines={1}>{dateLine}</Text> : null}
          <Text style={[textStyle('bodySm'), s.metaQuiet]} numberOfLines={1}>{group.venue_name}</Text>
          <View style={s.pastRows}>
            {group.rows.map((r, i) => (
              <StateRow key={`${r.ticket_type_id}:${r.ownership_status}:${r.fulfillment_status}:${i}`} s={s} row={r} quiet />
            ))}
          </View>
        </View>
      </View>
    );
  }

  return (
    <View style={s.card} accessible accessibilityLabel={groupA11yLabel(group)}>
      {/* Here the WIDTH is the constrained edge — the card's — so `fluid` stays and the poster's
          height follows the ratio: at a 343pt card that is a 429pt frame where the 16:9 strip was
          193, flush with the top edge. No radius is passed and none belongs here: the card clips it
          (`overflow: 'hidden'`), which is why TICKET_ART's slot radius is 0. */}
      <EventMedia asset={asset} slot="TICKET_ART" fluid />
      <View style={s.body}>
        {/* V3: the loud upcoming card leads with the name in the order-tier display step. */}
        <Text style={[textStyle('nameOrder'), s.title]} numberOfLines={2}>{group.event_title}</Text>
        {dateLine ? <Text style={[textStyle('body'), s.meta]} numberOfLines={1}>{dateLine}</Text> : null}
        <Text style={[textStyle('body'), s.meta]} numberOfLines={1}>
          {group.venue_name}{group.session_label ? `  -  ${group.session_label}` : ''}
        </Text>
        <View style={s.rows}>
          {group.rows.map((r, i) => (
            <StateRow key={`${r.ticket_type_id}:${r.ownership_status}:${r.fulfillment_status}:${i}`} s={s} row={r} />
          ))}
        </View>
      </View>
    </View>
  );
});

type Styles = ReturnType<typeof makeStyles>;

function makeStyles(p: Palette) {
  return StyleSheet.create({
  // Upcoming — artwork-led card. V3 (pkg8-account-tickets): cards round at the card step
  // (A-3 radius-by-role); overflow clips the artwork to the same corners.
  card: {
    backgroundColor: p.surface.surface,
    borderWidth: 1,
    borderColor: p.border.default,
    borderRadius: v2.radius.md,
    overflow: 'hidden',
    marginBottom: v2.space.lg,
  },
  body: { padding: v2.space.lg, gap: v2.space.xs },
  title: { color: p.text.primary },
  meta: { color: p.text.secondary },
  rows: { marginTop: v2.space.md, gap: v2.space.sm },

  row: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: v2.space.md, minHeight: 32 },
  rowText: { color: p.text.primary, flexShrink: 1 },
  rowTextQuiet: { color: p.text.secondary, flexShrink: 1 },
  badges: { flexDirection: 'row', alignItems: 'center', gap: v2.space.xs, flexShrink: 0 },

  // Past — quieter row. The dim belongs on the ARTWORK, not on the card: an ancestor opacity is a
  // contrast multiplier on everything below it, and 0.92 over the Daylight canvas took `text.muted`
  // — the date line and the venue name — from 5.27:1 to 4.44:1, under the bar the token was solved
  // for. The recession is carried by the layout swap and the quieter ink tokens anyway (TP1/TP2).
  pastCard: {
    flexDirection: 'row',
    gap: v2.space.md,
    paddingVertical: v2.space.md,
    borderBottomWidth: 1,
    borderBottomColor: p.border.default,
  },
  // The dim, and ONLY the dim. The 4:5 poster direction (owner 2026-09-24) puts the frame and its
  // radius in the slot: a 64-square wrapper clipping with `overflow: 'hidden'` would crop the poster
  // back to the shape the direction removes, and its own radius would draw a second arc inside the
  // frame's. `alignSelf` keeps the dimmed layer exactly the artwork's size now that the box is the
  // poster's, not the wrapper's — a stretched layer would dim empty space down the row.
  pastThumb: { alignSelf: 'flex-start', opacity: 0.92 },
  pastBody: { flex: 1, gap: 2 },
  pastTitle: { color: p.text.primary },
  metaQuiet: { color: p.text.muted },
  pastRows: { marginTop: v2.space.xs, gap: v2.space.xs },
  });
}

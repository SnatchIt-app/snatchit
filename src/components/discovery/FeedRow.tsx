/**
 * src/components/discovery/FeedRow.tsx — the §3 feed/search row (owner 2026-09-22; V3 package).
 *
 * 62×62 artwork at radius 8 on the left, the name in the display voice beside it, the all-in
 * price right-aligned. The row GROWS with its contents: no height is hard-coded anywhere here,
 * and the last metadata line keeps ROW_META_CLEARANCE of clear space before whatever is drawn
 * below (the list's own divider). Same truth rules as DiscoveryCard: cardState decides what the
 * price is and whether a clock exists; feedRowState formats the §5 words; this file does neither.
 */

import { memo } from 'react';
import { Animated, Pressable, StyleSheet, Text, View } from 'react-native';

import { EventMedia } from '@/src/components/media/EventMedia';
import { NameText } from '@/src/components/NameText';
import { usePressScale } from '@/src/components/ui';
import { ROW_ART, ROW_ART_GAP, ROW_GUTTER } from '@/src/lib/design/featureMetrics';
import { ROW_META_CLEARANCE } from '@/src/lib/design/rowMetrics';
import type { CardPresentation } from '@/src/lib/listing/cardState';
import { clockLabel, rowMeta } from '@/src/lib/listing/feedRowState';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

export interface FeedRowProps {
  eventName: string;
  venue: string;
  eventDate: string;
  eventTime: string;
  quantity: number;
  ticketType: string;
  /** Raw stored cover value; EventMedia resolves and sizes it. */
  coverPath: string | null;
  presentation: CardPresentation;
  bidCount: number | null;
  /** All-in, preformatted by `allInFromDollars`. This component does no math. */
  priceAllIn: string;
  endsAt: string;
  nowMs: number;
  onPress: () => void;
}

function FeedRowImpl({
  eventName,
  venue,
  eventDate,
  eventTime,
  quantity,
  ticketType,
  coverPath,
  presentation,
  bidCount,
  priceAllIn,
  endsAt,
  nowMs,
  onPress,
}: FeedRowProps) {
  const press = usePressScale();
  const meta = rowMeta({ eventDate, eventTime, venue, quantity, ticketType, bidCount });
  const dimmed = presentation.status === 'sold' || presentation.status === 'ended';

  // Every price is captioned "all-in" — its basis, once. On a sold or ended row the CLAIM
  // lives in the status line below (plus the dimmed treatment); repeating it in the caption
  // said the same thing twice in one column (de-dup, owner 2026-09-23).
  const caption = 'all-in';

  // Third price-column line: a live clock when cardState says one is worth showing, else the
  // status word. `clockLabel` returns null for a dead clock, so nothing here counts down past 0.
  const clock = presentation.showsCountdown ? clockLabel(endsAt, nowMs) : null;
  const statusLine = clock ? null : presentation.statusLabel;

  return (
    <Animated.View style={press.style}>
      <Pressable
        onPress={onPress}
        onPressIn={press.onPressIn}
        onPressOut={press.onPressOut}
        accessibilityRole="button"
        accessibilityLabel={
          `${eventName}. ${meta.meta1}. ${meta.meta2}. ${priceAllIn} ${caption}.` +
          (clock ? ` ${clock.text}.` : statusLine ? ` ${statusLine}.` : '')
        }
        accessibilityHint={presentation.actionHint}
      >
        <View style={[s.row, dimmed && s.dimmed]}>
          <EventMedia
            asset={{ path: coverPath, contract: 'legacy', bucket: 'auction-media' }}
            slot="FEED_ROW_ART"
            width={ROW_ART}
            title={eventName}
            decorative
          />

          <View style={s.text}>
            <NameText token="nameRow" maxLines={2} style={s.title}>
              {eventName}
            </NameText>
            <Text style={[textStyle('bodySm'), s.meta, s.metaFirst]} numberOfLines={1}>
              {meta.meta1}
            </Text>
            <Text style={[textStyle('bodySm'), s.meta]} numberOfLines={1}>
              {meta.meta2}
            </Text>
          </View>

          <View style={s.price}>
            <Text style={[textStyle('price'), s.priceValue, dimmed && s.priceDimmed]} numberOfLines={1}>
              {priceAllIn}
            </Text>
            <Text style={[textStyle('bodySm'), s.caption]} numberOfLines={1}>
              {caption}
            </Text>
            {clock ? (
              <Text
                style={[textStyle('bodySm'), clock.urgent ? s.clockUrgent : s.clock]}
                numberOfLines={1}
              >
                {clock.text}
              </Text>
            ) : statusLine ? (
              <Text style={[textStyle('bodySm'), s.clock]} numberOfLines={1}>
                {statusLine}
              </Text>
            ) : null}
          </View>
        </View>
      </Pressable>
    </Animated.View>
  );
}

export const FeedRow = memo(FeedRowImpl);

const s = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    paddingHorizontal: ROW_GUTTER,
    gap: ROW_ART_GAP,
  },
  dimmed: { opacity: 0.55 },
  // Content-driven height: the clearance under the LAST metadata line is the §3 rule, pinned to
  // the shared constant. Nothing in this sheet sets a row height.
  text: { flex: 1, paddingBottom: ROW_META_CLEARANCE },
  title: { color: v2.text.primary },
  meta: { color: v2.text.muted },
  metaFirst: { marginTop: 4 },
  price: { alignItems: 'flex-end' },
  priceValue: { color: v2.text.primary, fontVariant: ['tabular-nums'] },
  priceDimmed: { color: v2.text.secondary },
  caption: { color: v2.text.muted },
  clock: { color: v2.text.secondary, fontVariant: ['tabular-nums'] },
  // §5: amber, and ONLY under 15 minutes — feedRowState owns the threshold. Never brand red.
  clockUrgent: { color: v2.status.warning, fontVariant: ['tabular-nums'] },
});

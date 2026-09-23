/**
 * src/components/discovery/HomeFeature.tsx — the §3 full-bleed home feature (owner 2026-09-22).
 *
 * One listing, artwork edge to edge, its name in the feature voice over the measured curve scrim
 * (the slot carries both the height formula and the scrim — nothing here sizes or darkens
 * anything). The name block's bottom sits FEATURE_NAME_BLOCK_BOTTOM above the image bottom with
 * the two metadata lines below it; the price and its §5 caption ("current bid, all-in") sit
 * right-aligned on the same band. Same division of truth as FeedRow: cardState decides, the
 * feedRowState vocabulary speaks, this file draws.
 */

import { memo } from 'react';
import { Animated, Pressable, StyleSheet, Text, View } from 'react-native';

import { EventMedia } from '@/src/components/media/EventMedia';
import { NameText } from '@/src/components/NameText';
import { usePressScale } from '@/src/components/ui';
import {
  FEATURE_CONTENT_BOTTOM,
  FEATURE_GUTTER,
  FEATURE_META1_BELOW_NAME,
  FEATURE_META_LINE,
} from '@/src/lib/design/featureMetrics';
import type { CardPresentation } from '@/src/lib/listing/cardState';
import { clockLabel, featureMetaLine, priceCaption, rowMeta } from '@/src/lib/listing/feedRowState';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

export interface HomeFeatureProps {
  eventName: string;
  venue: string;
  eventDate: string;
  eventTime: string;
  quantity: number;
  ticketType: string;
  /** Raw stored cover value; EventMedia resolves, sizes and scrims it. */
  coverPath: string | null;
  presentation: CardPresentation;
  bidCount: number | null;
  /** All-in, preformatted by `allInFromDollars`. This component does no math. */
  priceAllIn: string;
  endsAt: string;
  nowMs: number;
  onPress: () => void;
}

function HomeFeatureImpl({
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
}: HomeFeatureProps) {
  const press = usePressScale();

  // "19:30 · Lantern Room" only when the event is genuinely today; the full dated line otherwise.
  const meta1 = featureMetaLine({ eventDate, eventTime, venue }, nowMs);
  const { meta2 } = rowMeta({ eventDate, eventTime, venue, quantity, ticketType, bidCount });
  const clock = presentation.showsCountdown ? clockLabel(endsAt, nowMs) : null;
  const meta2Line = clock ? `${meta2} · ${clock.text}` : meta2;
  const caption = priceCaption(presentation.priceLabel);

  return (
    <Animated.View style={press.style}>
      <Pressable
        onPress={onPress}
        onPressIn={press.onPressIn}
        onPressOut={press.onPressOut}
        accessibilityRole="button"
        accessibilityLabel={`${eventName}. ${meta1}. ${meta2Line}. ${priceAllIn} ${caption}.`}
        accessibilityHint={presentation.actionHint}
      >
        <EventMedia
          asset={{ path: coverPath, contract: 'legacy', bucket: 'auction-media' }}
          slot="HOME_FEATURE_V3"
          title={eventName}
          fluid
          decorative
        >
          <View style={s.content} pointerEvents="none">
            <View style={s.textCol}>
              <NameText token="nameFeature" maxLines={2} style={s.title}>
                {eventName}
              </NameText>
              <Text style={[textStyle('bodySm'), s.meta, s.metaFirst]} numberOfLines={1}>
                {meta1}
              </Text>
              <Text
                style={[textStyle('bodySm'), clock?.urgent ? s.metaUrgent : s.meta]}
                numberOfLines={1}
              >
                {meta2Line}
              </Text>
            </View>
            <View style={s.priceCol}>
              <Text style={[textStyle('price'), s.priceValue]} numberOfLines={1}>
                {priceAllIn}
              </Text>
              <Text style={[textStyle('bodySm'), s.caption]} numberOfLines={1}>
                {caption}
              </Text>
            </View>
          </View>
        </EventMedia>
      </Pressable>
    </Animated.View>
  );
}

export const HomeFeature = memo(HomeFeatureImpl);

const s = StyleSheet.create({
  // Bottom-anchored per §3: the name block's bottom lands FEATURE_NAME_BLOCK_BOTTOM above the
  // image bottom because the two 17pt meta lines and this padding sit under it. All arithmetic
  // lives in featureMetrics; the slot's formula sets the frame, so no height appears here.
  content: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    flexDirection: 'row',
    alignItems: 'flex-end',
    paddingHorizontal: FEATURE_GUTTER,
    paddingBottom: FEATURE_CONTENT_BOTTOM,
    gap: v2.space.md,
  },
  textCol: { flex: 1 },
  title: { color: v2.text.primary },
  meta: { color: v2.text.secondary, lineHeight: FEATURE_META_LINE },
  metaFirst: { marginTop: FEATURE_META1_BELOW_NAME },
  metaUrgent: { color: v2.status.warning, lineHeight: FEATURE_META_LINE },
  priceCol: { alignItems: 'flex-end' },
  priceValue: { color: v2.text.primary, fontVariant: ['tabular-nums'] },
  caption: { color: v2.text.secondary },
});

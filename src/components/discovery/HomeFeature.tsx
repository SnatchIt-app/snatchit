/**
 * src/components/discovery/HomeFeature.tsx — the full-bleed home feature.
 *
 * One listing: the complete event poster in a 4:5 frame, and the app's own words in a separate
 * block BENEATH it.
 *
 * OWNER RULING 2026-09-25, which is why this file no longer overlays anything: "show the complete
 * event poster in a 4:5 frame. Fit other image shapes inside it without cropping or stretching,
 * using a deliberate background. Move the app's event name, date, venue, price and listing details
 * into a separate area beneath the poster. No app text or badges should overlap the poster's
 * printed content. Remove the gradient used to support the old text overlay." Full 4:5, and NOT the
 * proposed ~45% screen-height cap — the owner asked to see the full version first.
 *
 * WHAT THAT REPLACED, and why the replacement is not a style preference. The §3 design put the
 * name, two metadata lines and the price ON the artwork, over a measured gradient. A poster already
 * carries its own printed name, date, venue and lineup, usually set at the bottom edge — so the
 * overlay landed our type on theirs, and the gradient existed to make our type readable by
 * darkening theirs. Both of those are ways of damaging the thing the feature exists to show. B's
 * comparison panels showed the overlay landing squarely on a flyer's own text band.
 *
 * Two consequences worth naming:
 *  - the inks changed FAMILY, not just value. Text over artwork uses `onArt`, which is white in
 *    both appearances by contract; text on the canvas must follow the appearance or Light paints
 *    white on near-white. This block uses the same canvas vocabulary as FeedRow.
 *  - the frame is no longer `overlaid`, so the missing-artwork plate goes back to the
 *    appearance-following surface instead of the invariant dark plate that only exists to sit
 *    under white ink.
 *
 * The bottom-anchored §3 offsets (FEATURE_NAME_BLOCK_BOTTOM and its meta steps) are gone with the
 * overlay they positioned: they measured a distance from the IMAGE's bottom edge, which is not a
 * thing a block below the image has. Same division of truth as FeedRow: cardState decides, the
 * feedRowState vocabulary speaks, this file draws.
 */

import { memo, useMemo } from 'react';
import { Animated, Pressable, StyleSheet, Text, useWindowDimensions, View } from 'react-native';

import { EventMedia } from '@/src/components/media/EventMedia';
import { NameText } from '@/src/components/NameText';
import { usePressScale } from '@/src/components/ui';
import { FEATURE_GUTTER, identityStacks } from '@/src/lib/design/featureMetrics';
import type { CardPresentation } from '@/src/lib/listing/cardState';
import { clockLabel, featureMetaLine, priceCaption, rowMeta } from '@/src/lib/listing/feedRowState';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

export interface HomeFeatureProps {
  eventName: string;
  venue: string;
  eventDate: string;
  eventTime: string;
  quantity: number;
  ticketType: string;
  /** Raw stored cover value; EventMedia resolves and sizes it. Nothing is drawn over it. */
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
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const press = usePressScale();

  // "19:30 · Lantern Room" only when the event is genuinely today; the full dated line otherwise.
  const meta1 = featureMetaLine({ eventDate, eventTime, venue }, nowMs);
  const { meta2 } = rowMeta({ eventDate, eventTime, venue, quantity, ticketType, bidCount });
  const clock = presentation.showsCountdown ? clockLabel(endsAt, nowMs) : null;
  const meta2Line = clock ? `${meta2} · ${clock.text}` : meta2;
  const caption = priceCaption(presentation.priceLabel);
  /*
   * At a large text scale the two columns cannot both fit and the caption was the line that lost
   * "all-in" (B, d5217530). Above the threshold the block stacks and every line gets the full
   * width. `useWindowDimensions` rather than `PixelRatio.getFontScale()` so a change while the app
   * is open re-renders.
   */
  const { fontScale } = useWindowDimensions();
  const stacked = identityStacks(fontScale);

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
        {/* The poster, and nothing else. No children: a child of EventMedia draws INSIDE the
            frame, which is exactly what the owner ruled out. */}
        <EventMedia
          asset={{ path: coverPath, contract: 'legacy', bucket: 'auction-media' }}
          slot="HOME_FEATURE_V3"
          title={eventName}
          fluid
          decorative
        />

        {/* The app's words, in their own area beneath the poster. */}
        <View style={stacked ? s.contentStacked : s.content}>
          <View style={s.textCol}>
            <NameText token="nameFeature" maxLines={2} style={s.title}>
              {eventName}
            </NameText>
            <Text style={[textStyle('bodySm'), s.meta, s.metaFirst]} numberOfLines={1}>
              {meta1}
            </Text>
            <Text
              style={[textStyle('bodySm'), clock?.urgent ? s.metaUrgent : s.meta]}
              numberOfLines={2}
            >
              {meta2Line}
            </Text>
          </View>
          <View style={stacked ? s.priceColStacked : s.priceCol}>
            <Text style={[textStyle('price'), s.priceValue]} numberOfLines={1}>
              {priceAllIn}
            </Text>
            {/* Two lines, never one: "current bid, all-in" wraps rather than losing "all-in". */}
            <Text style={[textStyle('bodySm'), s.caption]} numberOfLines={2}>
              {caption}
            </Text>
          </View>
        </View>
      </Pressable>
    </Animated.View>
  );
}

export const HomeFeature = memo(HomeFeatureImpl);

function makeStyles(p: Palette) {
  return StyleSheet.create({
  /*
   * The identity block, BELOW the poster and no longer positioned against it (owner 2026-09-25).
   * It keeps the feature's own gutter so the text still lines up with the artwork's edges, and it
   * borrows FeedRow's vertical vocabulary — the same 4pt step under the name, the same alignment of
   * price against text — rather than inventing a second set of spacings for one block. `flex-start`
   * on the row so a two-line name does not drag the price down with it.
   */
  content: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    paddingHorizontal: FEATURE_GUTTER,
    paddingTop: v2.space.md,
    paddingBottom: v2.space.lg,
    gap: v2.space.md,
  },
  /*
   * The stacked form, above IDENTITY_STACK_SCALE: one column, so the price and its caption sit
   * beneath the name and each line has the full width. Same gutter, same vertical step — it is the
   * block's own vocabulary rearranged, not a second design.
   */
  contentStacked: {
    flexDirection: 'column',
    alignItems: 'stretch',
    paddingHorizontal: FEATURE_GUTTER,
    paddingTop: v2.space.md,
    paddingBottom: v2.space.lg,
    gap: v2.space.sm,
  },
  textCol: { flex: 1, minWidth: 0 },
  /*
   * CANVAS inks, not `onArt`. This is the half of the ruling that a screenshot in Dark would not
   * catch: `onArt.*` is white in BOTH appearances by contract, because it is designed to sit on
   * artwork. Left unchanged here, every line of this block would have been white-on-near-white in
   * Light. These are the same tokens FeedRow uses for the same four roles.
   */
  title: { color: p.text.primary },
  meta: { color: p.text.muted },
  metaFirst: { marginTop: 4 },
  metaUrgent: { color: p.status.warning },
  priceCol: { alignItems: 'flex-end' },
  /* Stacked, the price reads left-aligned under the name rather than adrift on the right. */
  priceColStacked: { alignItems: 'flex-start' },
  priceValue: { color: p.text.primary, fontVariant: ['tabular-nums'] },
  caption: { color: p.text.muted },
  });
}

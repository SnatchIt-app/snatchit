/**
 * src/components/discovery/FeedRow.tsx — the §3 feed/search row (owner 2026-09-22; V3 package).
 *
 * A 4:5 POSTER 62pt TALL on the left (owner 2026-09-24) at the approved thumbnail radius
 * (`ROW_ART_RADIUS`, B's drawn 8 since the owner's 2026-09-24 finding that row thumbnails must
 * read as ROUNDED, not square — the value lives in featureMetrics and reaches the artwork through
 * the FEED_ROW_ART slot, never from this file), the name in the display voice beside it, the all-in
 * price right-aligned. The row GROWS with its contents: no height is hard-coded anywhere here,
 * and the last metadata line keeps ROW_META_CLEARANCE of clear space before whatever is drawn
 * below (the list's own divider). Same truth rules as DiscoveryCard: cardState decides what the
 * price is and whether a clock exists; feedRowState formats the §5 words; this file does neither.
 */

import { memo, useMemo } from 'react';
import { Animated, Pressable, StyleSheet, Text, useWindowDimensions, View } from 'react-native';

import { EventMedia } from '@/src/components/media/EventMedia';
import { NameText } from '@/src/components/NameText';
import { usePressScale } from '@/src/components/ui';
import { identityStacks, ROW_ART, ROW_ART_GAP, ROW_GUTTER } from '@/src/lib/design/featureMetrics';
import { ROW_META_CLEARANCE } from '@/src/lib/design/rowMetrics';
import type { CardPresentation } from '@/src/lib/listing/cardState';
import { clockLabel, rowMeta } from '@/src/lib/listing/feedRowState';
import { MAX_DISPLAY_FONT_SCALE, textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';

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
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const press = usePressScale();
  const meta = rowMeta({ eventDate, eventTime, venue, quantity, ticketType, bidCount });
  const dimmed = presentation.status === 'sold' || presentation.status === 'ended';

  // Every price is captioned "all-in" — its basis, once. On a sold or ended row the CLAIM
  // lives in the status line below (plus the dimmed treatment); repeating it in the caption
  // said the same thing twice in one column (de-dup, owner 2026-09-23).
  const caption = 'all-in';
  /*
   * At a large text scale the price column and the text column cannot both fit, and the price is
   * the half that loses: E found "$132.0…" and "all-i…" in a C-operated a3xl capture. A clipped
   * amount states a different number, so the price moves UNDER the text — the artwork stays
   * where it is, because this is a width problem in the two text columns, not the whole row.
   *
   * The NUMERAL also takes `MAX_DISPLAY_FONT_SCALE`, which is the app's existing treatment for
   * display type (chips, badges, buttons, the bid stepper). Stacking alone stopped it clipping but
   * let it wrap mid-number — "$132.0" then "0" — which is nearly as misleading as losing a digit.
   * A capped numeral fits on one line and is complete; everything around it still scales all the
   * way, and the spoken label carries the full amount regardless.
   */
  const { fontScale } = useWindowDimensions();
  const stacked = identityStacks(fontScale);

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
        <View style={s.row}>
          {/* The dim belongs to the artwork. Wrapping the row scaled the status word too — "Sold"
              and "Ended" measure 2.71:1 in Daylight at 0.55 — on a row that stays tappable. */}
          <EventMedia
            style={dimmed ? s.dimmed : undefined}
            asset={{ path: coverPath, contract: 'legacy', bucket: 'auction-media' }}
            slot="FEED_ROW_ART"
            // The row's constrained edge is VERTICAL, so the poster is given the approved ROW_ART
            // as its height and EventMedia derives the 50pt width from the 4:5 ratio. Passing this
            // as `width` (what it was) made a 62-wide poster 78 tall, which pushes the approved
            // one-line row past 80pt and re-opens a rhythm the owner has accepted.
            height={ROW_ART}
            title={eventName}
            decorative
          />

          {(() => {
            const cap = stacked ? undefined : 1;
            const blocks = (
              <>
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

                <View style={stacked ? s.priceStacked : s.price}>
                  <Text style={[textStyle('price'), s.priceValue, dimmed && s.priceDimmed]} numberOfLines={cap} maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}>
                    {priceAllIn}
                  </Text>
                  <Text style={[textStyle('bodySm'), s.caption]} numberOfLines={cap}>
                    {caption}
                  </Text>
                  {clock ? (
                    <Text
                      style={[textStyle('bodySm'), clock.urgent ? s.clockUrgent : s.clock]}
                      numberOfLines={cap}
                    >
                      {clock.text}
                    </Text>
                  ) : statusLine ? (
                    <Text style={[textStyle('bodySm'), s.clock]} numberOfLines={cap}>
                      {statusLine}
                    </Text>
                  ) : null}
                </View>
              </>
            );
            // Stacked, the two text blocks share one column so the price has the row's width
            // instead ofcompeting for it. The artwork is untouched either way.
            return stacked ? <View style={s.bodyStacked} testID="feedrow-body">{blocks}</View> : blocks;
          })()}
        </View>
      </Pressable>
    </Animated.View>
  );
}

export const FeedRow = memo(FeedRowImpl);

function makeStyles(p: Palette) {
  return StyleSheet.create({
  // The gutter, the poster and the gap ARE the text column's offset: 20 + 50 + 12 is ROW_TEXT_X,
  // so the 82 arrives from the poster's own width instead of being typed here — and the 94 this
  // row used to start at moved on its own when the artwork became 50 wide. Nothing else in this
  // sheet carries a width, so there was no second place to correct.
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
  title: { color: p.text.primary },
  meta: { color: p.text.muted },
  metaFirst: { marginTop: 4 },
  price: { alignItems: 'flex-end' },
  /* Stacked above IDENTITY_STACK_SCALE: under the text, left-aligned, full width. */
  bodyStacked: { flex: 1, flexDirection: 'column', gap: 4 },
  priceStacked: { alignItems: 'flex-start' },
  priceValue: { color: p.text.primary, fontVariant: ['tabular-nums'] },
  priceDimmed: { color: p.text.secondary },
  caption: { color: p.text.muted },
  clock: { color: p.text.secondary, fontVariant: ['tabular-nums'] },
  // §5: amber, and ONLY under 15 minutes — feedRowState owns the threshold. Never brand red.
  clockUrgent: { color: p.status.warning, fontVariant: ['tabular-nums'] },
  });
}

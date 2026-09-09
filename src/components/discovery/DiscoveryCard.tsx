/**
 * src/components/discovery/DiscoveryCard.tsx — the one card in the feed.
 *
 * The app previously had four unrelated listing-card geometries: a full-width
 * 180pt band in the feed, a 64pt row in explore, a 2.6:1 thumbnail in bids and an
 * 80pt square in my listings. One asset, four crops, four layouts, four sets of
 * local styles. This is the canonical one.
 *
 * SHAPE: 4:5 artwork, text BELOW it, never on it. Event flyers already contain
 * typography, and a title layer over someone else's poster reads as a mistake —
 * the same reasoning the approved listing detail hero follows. The card is a
 * single tap target that opens that screen; there is no button on it, which is
 * also how the old "Bid now" label stopped appearing on Buy Now listings.
 */

import { memo } from 'react';
import { Animated, Pressable, StyleSheet, Text, View } from 'react-native';

import { EventMedia } from '@/src/components/media/EventMedia';
import { Badge, usePressScale } from '@/src/components/ui';
import type { CardPresentation } from '@/src/lib/listing/cardState';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

export interface DiscoveryCardProps {
  eventName: string;
  venue: string;
  /** Preformatted by the caller: "Sat, Oct 17 · 10:00 PM". */
  whenLabel: string;
  /** Raw stored cover value. EventMedia resolves, encodes and sizes it. */
  coverPath: string | null;
  presentation: CardPresentation;
  /** All-in, preformatted by `allInFromDollars`. This component does no math. */
  priceAllIn: string;
  altAllIn?: string | null;
  /** Live clock, already formatted. Omitted when the listing has no clock left. */
  countdown?: string | null;
  onPress: () => void;
}

const TONE: Record<CardPresentation['statusTone'], 'neutral' | 'warning' | 'danger'> = {
  neutral: 'neutral',
  warning: 'warning',
  danger: 'danger',
  brand: 'neutral',
};

function DiscoveryCardImpl({
  eventName,
  venue,
  whenLabel,
  coverPath,
  presentation,
  priceAllIn,
  altAllIn,
  countdown,
  onPress,
}: DiscoveryCardProps) {
  const press = usePressScale();
  const dimmed = presentation.status === 'sold' || presentation.status === 'ended';

  return (
    <Animated.View style={[styles.wrap, press.style]}>
      <Pressable
        onPress={onPress}
        onPressIn={press.onPressIn}
        onPressOut={press.onPressOut}
        accessibilityRole="button"
        // One announcement per card, in the order a person would read it, rather
        // than eight unlabelled fragments.
        accessibilityLabel={
          `${eventName}. ${venue}. ${whenLabel}. ` +
          `${presentation.priceLabel} ${priceAllIn} all in.` +
          (presentation.statusLabel ? ` ${presentation.statusLabel}.` : '') +
          (countdown && presentation.showsCountdown ? ` ${countdown}.` : '')
        }
        accessibilityHint={presentation.actionHint}
      >
        <View style={dimmed ? styles.dimmed : undefined}>
          {/* `fluid` measures the real column width and requests a derivative at
              exactly that size, so the two-up grid fits a 375pt phone. */}
          <EventMedia
            asset={{ path: coverPath, contract: 'legacy', bucket: 'auction-media' }}
            slot="DISCOVERY_CARD"
            title={eventName}
            fluid
            decorative
          >
            {presentation.statusLabel ? (
              <View style={styles.badge} pointerEvents="none">
                <Badge label={presentation.statusLabel} tone={TONE[presentation.statusTone]} />
              </View>
            ) : null}
          </EventMedia>
        </View>

        <View style={styles.body}>
          {/* Inter, sentence case, two lines. Not Oswald: this is the venue's
              content, not Snatch It's voice. */}
          <Text style={[textStyle('title'), styles.title]} numberOfLines={2}>
            {eventName}
          </Text>
          <Text style={[textStyle('bodySm'), styles.meta]} numberOfLines={1}>
            {venue}
          </Text>
          <Text style={[textStyle('bodySm'), styles.meta]} numberOfLines={1}>
            {whenLabel}
          </Text>

          <View style={styles.priceRow}>
            <Text style={[textStyle('micro'), styles.priceLabel]} numberOfLines={1}>
              {presentation.priceLabel}
            </Text>
            <Text
              style={[textStyle('price'), styles.price, dimmed && styles.priceDimmed]}
              numberOfLines={1}
            >
              {priceAllIn}
              <Text style={[textStyle('bodySm'), styles.allIn]}> all in</Text>
            </Text>
          </View>

          {altAllIn && presentation.altLabel ? (
            <Text style={[textStyle('bodySm'), styles.alt]} numberOfLines={1}>
              {presentation.altLabel} {altAllIn}
            </Text>
          ) : null}

          {countdown && presentation.showsCountdown ? (
            <Text
              style={[
                textStyle('bodySm'),
                styles.clock,
                presentation.status === 'ending_soon' && styles.clockUrgent,
              ]}
              numberOfLines={1}
            >
              {countdown}
            </Text>
          ) : null}
        </View>
      </Pressable>
    </Animated.View>
  );
}

export const DiscoveryCard = memo(DiscoveryCardImpl);

const styles = StyleSheet.create({
  wrap: { flex: 1 },
  // Sold and ended listings stay in the feed but stop competing with what is
  // still buyable.
  dimmed: { opacity: 0.55 },
  badge: { position: 'absolute', left: v2.space.sm, bottom: v2.space.sm },
  body: { paddingTop: v2.space.sm, gap: 2 },
  title: { color: v2.text.primary },
  meta: { color: v2.text.muted },
  priceRow: { marginTop: v2.space.xs },
  priceLabel: { color: v2.text.muted },
  price: { color: v2.text.primary, fontVariant: ['tabular-nums'] },
  priceDimmed: { color: v2.text.secondary },
  // "all in" rides on the same line, smaller and quieter, so the number keeps
  // the hierarchy while the promise stays visible.
  allIn: { color: v2.text.muted },
  alt: { color: v2.text.muted },
  clock: { color: v2.text.secondary, fontVariant: ['tabular-nums'] },
  clockUrgent: { color: v2.status.error },
});

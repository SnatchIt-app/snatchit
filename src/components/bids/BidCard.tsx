/**
 * src/components/bids/BidCard.tsx — one row on the Bids screen.
 *
 * A horizontal card: event artwork on the left, then the event, its state and the
 * one price that matters for that state. The whole row is a single tap target —
 * to the transfer flow for an in-flight purchase, otherwise to the listing, which
 * is where the next action (bid again, pay to claim) lives.
 *
 * State is a word (Badge) plus, for the states that need the user to act, a short
 * red action line — never colour alone. Money is passed in preformatted; this
 * component does no arithmetic.
 */

import { memo, useMemo } from 'react';
import { Animated, Pressable, StyleSheet, Text, View } from 'react-native';

import { EventMedia } from '@/src/components/media/EventMedia';
import { Badge, usePressScale } from '@/src/components/ui';
import type { BidPresentation, BidTone } from '@/src/lib/bids/bidState';
import { needsAction } from '@/src/lib/bids/bidState';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

export interface BidCardProps {
  eventName: string;
  venue: string;
  whenLabel: string;
  coverPath: string | null;
  presentation: BidPresentation;
  /** All-in, preformatted by allInFromDollars. */
  priceAllIn: string;
  secondaryAllIn?: string | null;
  /** "Ends in 42m" while a live auction the user is in closes within the hour (CFT-505). */
  urgencyLabel?: string | null;
  onPress: () => void;
}

const TONE: Record<BidTone, 'neutral' | 'success' | 'warning' | 'danger'> = {
  brand: 'neutral', neutral: 'neutral', success: 'success', warning: 'warning', danger: 'danger',
};

function BidCardImpl({
  eventName, venue, whenLabel, coverPath, presentation, priceAllIn, secondaryAllIn, urgencyLabel, onPress,
}: BidCardProps) {
  const { palette } = useTheme();
  const styles = useMemo(() => makeStyles(palette), [palette]);
  const press = usePressScale();
  const act = needsAction(presentation.status);
  const dimmed = presentation.group === 'past';

  return (
    <Animated.View style={[styles.wrap, press.style]}>
      <Pressable
        onPress={onPress}
        onPressIn={press.onPressIn}
        onPressOut={press.onPressOut}
        style={styles.row}
        accessibilityRole="button"
        accessibilityLabel={
          `${eventName}. ${venue}. ${presentation.label}. ` +
          `${urgencyLabel ? `${urgencyLabel}. ` : ''}` +
          `${presentation.priceLabel} ${priceAllIn} all in.`
        }
        accessibilityHint={presentation.actionHint}
      >
        <View style={dimmed ? styles.dimmed : undefined}>
          <EventMedia
            asset={{ path: coverPath, contract: 'legacy', bucket: 'auction-media' }}
            slot="CHECKOUT_THUMBNAIL"
            title={eventName}
            width={72}
            decorative
          />
        </View>

        <View style={styles.body}>
          <View style={styles.badgeRow}>
            <Badge label={presentation.label} tone={TONE[presentation.tone]} />
          </View>
          <Text style={[textStyle('title'), styles.name]} numberOfLines={1}>{eventName}</Text>
          <Text style={[textStyle('bodySm'), styles.meta]} numberOfLines={1}>
            {venue}{whenLabel ? ` · ${whenLabel}` : ''}
          </Text>
          {urgencyLabel ? (
            <Text style={[textStyle('label'), styles.urgency]} numberOfLines={1}>{urgencyLabel}</Text>
          ) : null}

          <View style={styles.priceRow}>
            <Text style={[textStyle('bodySm'), styles.priceLabel]}>{presentation.priceLabel}</Text>
            <Text style={[textStyle('price'), styles.price]} numberOfLines={1}>
              {priceAllIn}
              <Text style={[textStyle('bodySm'), styles.allIn]}> all in</Text>
            </Text>
          </View>
          {presentation.secondaryLabel && secondaryAllIn ? (
            <Text style={[textStyle('bodySm'), styles.secondary]} numberOfLines={1}>
              {presentation.secondaryLabel} {secondaryAllIn}
            </Text>
          ) : null}

          {/* The action line, only where the user actually has a next step, in
              red because it IS the action. Winning/ended carry no action line. */}
          {act ? (
            <Text style={[textStyle('label'), styles.action]} numberOfLines={1}>
              {presentation.actionHint}
            </Text>
          ) : null}
        </View>

        <Text style={styles.chevron}>{'›'}</Text>
      </Pressable>
    </Animated.View>
  );
}

export const BidCard = memo(BidCardImpl);

function makeStyles(p: Palette) {
  return StyleSheet.create({
  urgency: { color: p.status.warning, marginTop: 2 },
  wrap: { marginBottom: v2.space.md },
  row: {
    flexDirection: 'row',
    gap: v2.space.md,
    alignItems: 'center',
    paddingVertical: v2.space.md,
    borderBottomWidth: 1,
    borderBottomColor: p.border.default,
  },
  dimmed: { opacity: 0.55 },
  body: { flex: 1, minWidth: 0, gap: 3 },
  badgeRow: { flexDirection: 'row' },
  name: { color: p.text.primary },
  meta: { color: p.text.muted },
  priceRow: { flexDirection: 'row', alignItems: 'baseline', gap: v2.space.sm, marginTop: 2 },
  priceLabel: { color: p.text.muted },
  price: { color: p.text.primary, fontVariant: ['tabular-nums'] },
  allIn: { color: p.text.muted },
  secondary: { color: p.text.muted },
  action: { color: p.brand.red, marginTop: 2 },
  chevron: { color: p.text.muted, fontSize: 22, lineHeight: 24 },
  });
}

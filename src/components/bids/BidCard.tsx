/**
 * src/components/bids/BidCard.tsx — one row on the Bids screen (V3).
 *
 * Board: `pkg6-bids-{clean,active,past}.png` (dark only; Daylight is the same composition
 * through palette roles). Event artwork on the left; the event name in the display voice with
 * the state word (Badge) and, inside the closing hour, the amber urgency beside it; on the
 * right the one price that matters, its "all-in" basis, and the state's action hint in the
 * uppercase eyebrow voice — the board draws the hint on every row ("the hint says what the row
 * will do, never what has happened to money"). The whole row is a single tap target — to the
 * transfer flow for an in-flight purchase, otherwise to the listing.
 *
 * State is a word plus the hint — never colour alone. Money is passed in preformatted; this
 * component does no arithmetic. Venue and date leave the drawn row (the board omits them) but
 * stay in the spoken label, with the price's basis word, so nothing a V2 user heard is lost.
 *
 * DELIBERATE DIFFERENCES FROM THE BOARD, each with its reason:
 *  - The urgency words are bidState's own ("Ends in 12m"), not the board's "12M LEFT":
 *    endingSoonLabel is owner/A-ruled territory this task does not touch.
 *  - The state words include 'Released' (auto_released) and 'Resolved' (operator decision),
 *    which the board's ten-word list flattens into 'Received'. DR12/DR9 rule those labels;
 *    the board is recorded as deviating, not followed.
 */

import { memo, useMemo } from 'react';
import { Animated, Pressable, StyleSheet, Text, View } from 'react-native';

import { EventMedia } from '@/src/components/media/EventMedia';
import { NameText } from '@/src/components/NameText';
import { Badge, usePressScale } from '@/src/components/ui';
import type { BidPresentation, BidTone } from '@/src/lib/bids/bidState';
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

// Board tone for 'brand': "Won" wears the buying-path red — "red marks the buying path…
// not a claim that money moves when you tap it" — and Badge has no brand slot, so the red
// outline is the danger tone's ink.
const TONE: Record<BidTone, 'neutral' | 'success' | 'warning' | 'danger'> = {
  brand: 'danger', neutral: 'neutral', success: 'success', warning: 'warning', danger: 'danger',
};

function BidCardImpl({
  eventName, venue, whenLabel, coverPath, presentation, priceAllIn, secondaryAllIn, urgencyLabel, onPress,
}: BidCardProps) {
  const { palette } = useTheme();
  const styles = useMemo(() => makeStyles(palette), [palette]);
  const press = usePressScale();
  const dimmed = presentation.group === 'past';

  return (
    <Animated.View style={press.style}>
      <Pressable
        onPress={onPress}
        onPressIn={press.onPressIn}
        onPressOut={press.onPressOut}
        style={styles.row}
        accessibilityRole="button"
        accessibilityLabel={
          `${eventName}. ${venue}${whenLabel ? ` · ${whenLabel}` : ''}. ${presentation.label}. ` +
          `${urgencyLabel ? `${urgencyLabel}. ` : ''}` +
          `${presentation.priceLabel} ${priceAllIn} all in.` +
          `${presentation.secondaryLabel && secondaryAllIn ? ` ${presentation.secondaryLabel} ${secondaryAllIn}.` : ''}`
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
          <NameText token="nameRow" maxLines={2} style={styles.name}>{eventName}</NameText>
          <View style={styles.badgeRow}>
            <Badge label={presentation.label} tone={TONE[presentation.tone]} />
            {urgencyLabel ? (
              <Text style={[textStyle('label'), styles.urgency]} numberOfLines={1}>{urgencyLabel}</Text>
            ) : null}
          </View>
        </View>

        <View style={styles.right}>
          <Text style={[textStyle('price'), styles.price]} numberOfLines={1}>{priceAllIn}</Text>
          <Text style={[textStyle('bodySm'), styles.allIn]} numberOfLines={1}>all-in</Text>
          {/* The board's hint, on every row, in the eyebrow voice — state metadata, not a
              control: the row is the control, and the hint is also the spoken hint above. */}
          <Text style={[textStyle('label'), styles.hint]} numberOfLines={1}>
            {presentation.actionHint}
          </Text>
        </View>
      </Pressable>
    </Animated.View>
  );
}

export const BidCard = memo(BidCardImpl);

function makeStyles(p: Palette) {
  return StyleSheet.create({
  row: {
    flexDirection: 'row',
    gap: v2.space.md,
    alignItems: 'center',
    paddingVertical: v2.space.md,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: p.border.default,
  },
  dimmed: { opacity: 0.55 },
  body: { flex: 1, minWidth: 0, gap: v2.space.xs },
  name: { color: p.text.primary },
  badgeRow: { flexDirection: 'row', alignItems: 'center', gap: v2.space.sm },
  urgency: { color: p.status.warning },
  right: { alignItems: 'flex-end', gap: 2, flexShrink: 0 },
  price: { color: p.text.primary, fontVariant: ['tabular-nums'] },
  allIn: { color: p.text.muted },
  hint: { color: p.text.secondary, marginTop: v2.space.xs },
  });
}

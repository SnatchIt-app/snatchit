/**
 * src/components/listing/TransactionPanel.tsx — price, clock, and what is on offer.
 *
 * THE ONE THING THIS SCREEN HAS TO GET RIGHT. The old layout put the current bid
 * and the countdown in a single grey card and left Buy Now to be discovered as a
 * grey outlined button in the sticky bar, weaker than the red Place Bid beside
 * it. Instant purchase was the strongest offer on the listing and looked like the
 * afterthought.
 *
 * Here both offers are stated as prices, with Buy Now first when it exists,
 * because that is the decision the user is making: pay this and it is yours, or
 * bid this and wait.
 *
 * EVERY AMOUNT IS ALL-IN AND PREFORMATTED BY THE CALLER. This component does no
 * arithmetic. `PriceDisplay` renders it, which is the canonical primitive and
 * guarantees the amount never wraps and the digits never jitter.
 */

import { StyleSheet, Text, View } from 'react-native';

import { PriceDisplay } from '@/src/components/PriceDisplay';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import type { TransactionMode } from '@/src/lib/listing/detailState';

export interface TransactionPanelProps {
  mode: TransactionMode;
  /** All-in, preformatted. The live price of the auction. */
  currentAllIn: string;
  /** All-in, preformatted. Present only when Buy Now is on offer. */
  buyNowAllIn?: string | null;
  /** All-in, preformatted. What the next bid has to clear. */
  nextBidAllIn?: string | null;
  /** Already-formatted countdown, or null when there is no clock left to run. */
  countdown: string | null;
  /** Sold listings show what it went for, not what it is worth. */
  soldAllIn?: string | null;
  bidCount: number;
}

export function TransactionPanel({
  mode,
  currentAllIn,
  buyNowAllIn,
  nextBidAllIn,
  countdown,
  soldAllIn,
  bidCount,
}: TransactionPanelProps) {
  const closed = mode === 'closed';

  if (soldAllIn) {
    return (
      <View style={styles.wrap}>
        <PriceDisplay size="detail" label="Sold for" amount={soldAllIn} muted />
        <Text style={[textStyle('bodySm'), styles.note]}>
          Price includes the 10% service fee.
        </Text>
      </View>
    );
  }

  return (
    <View style={styles.wrap}>
      {/* Buy Now leads when it exists. It is the stronger offer. */}
      {buyNowAllIn ? (
        <View style={styles.primaryPrice}>
          <PriceDisplay size="detail" label="Buy now" amount={buyNowAllIn} />
          <Text style={[textStyle('bodySm'), styles.note]}>
            Yours immediately. No waiting for the auction.
          </Text>
        </View>
      ) : null}

      <View style={[styles.bidRow, buyNowAllIn ? styles.bidRowSecondary : null]}>
        <View style={styles.bidPrice}>
          <PriceDisplay
            size={buyNowAllIn ? 'sticky' : 'detail'}
            label={
              closed ? 'Final bid' : bidCount > 0 ? 'Current bid' : 'Starting bid'
            }
            amount={currentAllIn}
            muted={closed}
          />
          {nextBidAllIn && !closed ? (
            <Text style={[textStyle('bodySm'), styles.note]}>
              Next bid from {nextBidAllIn}
            </Text>
          ) : null}
        </View>

        {countdown ? (
          <View style={styles.clock}>
            <Text style={[textStyle('micro'), styles.clockLabel]}>Time left</Text>
            <Text
              style={[textStyle('price'), styles.clockValue]}
              numberOfLines={1}
              // The countdown updates every second; announcing each tick would
              // make the screen unusable with a reader.
              accessibilityLiveRegion="none"
            >
              {countdown}
            </Text>
          </View>
        ) : null}
      </View>

      {/*
        The fee is stated once, in a sentence, and not as an accounting table.
        Every price above already includes it, which is the product's promise and
        the reason the number never grows at checkout.
      */}
      <Text style={[textStyle('bodySm'), styles.note]}>
        All prices include the 10% service fee.
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: {
    paddingHorizontal: v2.space.lg,
    paddingVertical: v2.space.lg,
    gap: v2.space.md,
  },
  primaryPrice: { gap: 2 },
  bidRow: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    gap: v2.space.md,
  },
  // When Buy Now is present the bid sits under a hairline, one step down the
  // hierarchy. Separation by line and size, never by a second card.
  bidRowSecondary: {
    borderTopWidth: 1,
    borderTopColor: v2.border.default,
    paddingTop: v2.space.md,
  },
  bidPrice: { flex: 1, minWidth: 0, gap: 2 },
  clock: { alignItems: 'flex-end', flexShrink: 0 },
  clockLabel: { color: v2.text.muted },
  clockValue: { color: v2.text.primary },
  note: { color: v2.text.muted },
});

/**
 * src/components/listing/TransactionPanel.tsx — price, clock, and what is on offer.
 *
 * V3 (owner 2026-09-22; §5 + the freeze reconciliation §2). Two different numbers, never
 * merged: the PANEL states what the listing stands at now — one all-in price, the ticket
 * count it buys, the bid count and the clock — and says nothing about the buyer's total. The
 * BREAKDOWN below it belongs to the bid being offered ("If you bid the minimum"), every row
 * preformatted by the caller through the one money module. The buy-now amount lives on its own
 * CTA in the sticky bar (which keeps Buy Now primary — the owner reaffirmed the hierarchy);
 * printing it here as well made the panel a second, competing statement of the offer.
 *
 * EVERY AMOUNT IS ALL-IN AND PREFORMATTED BY THE CALLER. This component does no arithmetic.
 * "Current bid" is never claimed with zero bids, and a dead clock is simply absent.
 */

import { Animated, StyleSheet, Text, View } from 'react-native';

import { PriceDisplay } from '@/src/components/PriceDisplay';
import { usePulseOnChange } from '@/src/hooks/usePulseOnChange';
import { bidCountText } from '@/src/lib/listing/feedRowState';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import type { TransactionMode } from '@/src/lib/listing/detailState';

export interface TransactionPanelProps {
  mode: TransactionMode;
  /** All-in, preformatted. The live price of the auction. */
  currentAllIn: string;
  /** All-in, preformatted. What the next bid has to clear — the breakdown's total. */
  nextBidAllIn?: string | null;
  /** Preformatted breakdown rows for the minimum bid. Null hides the block. */
  minBidBase?: string | null;
  minBidFee?: string | null;
  /** The §5 clock forms, built by the caller from the server's ends_at. Null = no clock. */
  clock: { text: string; urgent: boolean } | null;
  /** Sold listings show what it went for, not what it is worth. */
  soldAllIn?: string | null;
  bidCount: number;
  quantity: number;
  ticketType: string;
}

export function TransactionPanel({
  mode,
  currentAllIn,
  nextBidAllIn,
  minBidBase,
  minBidFee,
  clock,
  soldAllIn,
  bidCount,
  quantity,
  ticketType,
}: TransactionPanelProps) {
  const closed = mode === 'closed';
  // A new bid moves the amount in place: a brief dip-and-return, never a
  // rebuild of the panel (CFT-502). Under Reduce Motion the value just changes.
  const pulse = usePulseOnChange(currentAllIn);

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

  const subLine = `all-in · ${bidCountText(bidCount)}${clock ? ` · ${clock.text}` : ''}`;
  const showBreakdown = !closed && nextBidAllIn != null && minBidBase != null && minBidFee != null;

  return (
    <View style={styles.wrap}>
      {/* The panel card: what the listing stands at NOW. Nothing about the buyer's total. */}
      <View style={styles.card}>
        <View style={styles.cardRow}>
          <Animated.View style={[styles.cardPrice, { opacity: pulse.opacity }]}>
            <PriceDisplay
              size="detail"
              label={closed ? 'Final bid' : bidCount > 0 ? 'Current bid' : 'Starting bid'}
              amount={currentAllIn}
              muted={closed}
            />
          </Animated.View>
          <View style={styles.qtyCol}>
            <Text style={[textStyle('label'), styles.qty]} numberOfLines={1}>
              {`${quantity} × ${ticketType} ticket${quantity === 1 ? '' : 's'}`}
            </Text>
            {quantity > 1 ? (
              // Whole-listing pricing is the product promise; two tickets are one purchase.
              <Text style={[textStyle('bodySm'), styles.qtyNote]}>sold together</Text>
            ) : null}
          </View>
        </View>
        <Text
          style={[textStyle('bodySm'), clock?.urgent ? styles.subLineUrgent : styles.subLine]}
          numberOfLines={1}
        >
          {subLine}
        </Text>
      </View>

      {/* The breakdown belongs to the BID BEING OFFERED — the buyer's would-be total. De-dup
          (owner 2026-09-23): each number once. The quantity is stated in the panel above, so
          the row is "Tickets"; the total appears only on its own row; and the fee row IS the
          fee explanation — no trailing sentence repeats it. */}
      {showBreakdown ? (
        <View style={styles.breakdown}>
          <Text style={[textStyle('micro'), styles.bEyebrow]}>If you bid the minimum</Text>
          <View style={styles.bRow}>
            <Text style={[textStyle('bodySm'), styles.bLabel]}>Tickets</Text>
            <Text style={[textStyle('bodySm'), styles.bValue]} numberOfLines={1}>{minBidBase}</Text>
          </View>
          <View style={styles.bRow}>
            <Text style={[textStyle('bodySm'), styles.bLabel]}>Service fee (10%)</Text>
            <Text style={[textStyle('bodySm'), styles.bValue]} numberOfLines={1}>{minBidFee}</Text>
          </View>
          <View style={[styles.bRow, styles.bTotalRow]}>
            <Text style={[textStyle('label'), styles.bLabel]}>Your total if you win</Text>
            <Text style={[textStyle('price'), styles.bTotal]} numberOfLines={1}>{nextBidAllIn}</Text>
          </View>
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: {
    paddingHorizontal: v2.space.lg,
    paddingVertical: v2.space.lg,
    gap: v2.space.md,
  },
  card: {
    backgroundColor: v2.surface.surface,
    padding: v2.space.lg,
    gap: v2.space.sm,
  },
  cardRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: v2.space.md,
  },
  cardPrice: { flexShrink: 1, minWidth: 0 },
  qtyCol: { alignItems: 'flex-end', flexShrink: 0 },
  qty: { color: v2.text.primary },
  qtyNote: { color: v2.text.muted },
  subLine: { color: v2.text.secondary },
  // §5: amber only for a real sub-15-minute close; the caller's clock carries that decision.
  subLineUrgent: { color: v2.status.warning },
  breakdown: { gap: v2.space.xs },
  bRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
    justifyContent: 'space-between',
    gap: v2.space.md,
  },
  bEyebrow: { color: v2.text.muted, textTransform: 'uppercase', letterSpacing: 0.6 },
  bLabel: { color: v2.text.secondary },
  bValue: { color: v2.text.primary, fontVariant: ['tabular-nums'] },
  bTotalRow: {
    borderTopWidth: 1,
    borderTopColor: v2.border.default,
    paddingTop: v2.space.xs,
  },
  bTotal: { color: v2.text.primary, fontVariant: ['tabular-nums'] },
  note: { color: v2.text.muted },
});

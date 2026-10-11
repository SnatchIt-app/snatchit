/**
 * src/components/listing/TransactionPanel.tsx — price, clock, and what is on offer.
 *
 * V3 (owner 2026-09-22; §5 + the freeze reconciliation §2). Two different numbers, never
 * merged: the PANEL states what the listing stands at now — one all-in price, the ticket
 * count it buys, the bid count and the clock — and says nothing about the buyer's total. The
 * BREAKDOWN below it belongs to the bid being offered ("If you bid the minimum"), every row
 * preformatted by the caller through the one money module. R-2 (B, 2026-09-23): the would-be
 * total is NOT repeated here — the bid CTA's sub-label already states the minimum all-in. The buy-now amount lives on its own
 * CTA in the sticky bar (which keeps Buy Now primary — the owner reaffirmed the hierarchy);
 * printing it here as well made the panel a second, competing statement of the offer.
 *
 * EVERY AMOUNT IS ALL-IN AND PREFORMATTED BY THE CALLER. This component does no arithmetic.
 * "Current bid" is never claimed with zero bids, and a dead clock is simply absent.
 */

import { useMemo } from 'react';
import { Animated, StyleSheet, Text, useWindowDimensions, View } from 'react-native';

import { PriceDisplay } from '@/src/components/PriceDisplay';
import { usePulseOnChange } from '@/src/hooks/usePulseOnChange';
import { RESALE_FEE_LABEL } from '@/src/lib/listing/detailState';
import { bidCountText } from '@/src/lib/listing/feedRowState';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import { identityStacks } from '@/src/lib/design/featureMetrics';
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
  const { palette } = useTheme();
  const styles = useMemo(() => makeStyles(palette), [palette]);
  /*
   * Three two-column rows here could not fit at accessibility-extra-extra-extra-large and all
   * three lost text — including the breakdown VALUE, which rendered "$95.0" on the device. A
   * clipped amount states a different number from the one the buyer would pay, so this uses the
   * same rule as the Home feature's identity block rather than a second one.
   */
  const { fontScale } = useWindowDimensions();
  const stacked = identityStacks(fontScale);
  const closed = mode === 'closed';
  // A new bid moves the amount in place: a brief dip-and-return, never a
  // rebuild of the panel (CFT-502). Under Reduce Motion the value just changes.
  const pulse = usePulseOnChange(currentAllIn);

  if (soldAllIn) {
    return (
      <View style={styles.wrap}>
        <PriceDisplay size="detail" label="Sold for" amount={soldAllIn} muted />
        <Text style={[textStyle('bodySm'), styles.note]}>
          Price includes the service fee.
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
        <View style={stacked ? styles.cardRowStacked : styles.cardRow} testID="panel-card-row">
          <Animated.View style={[styles.cardPrice, { opacity: pulse.opacity }]}>
            <PriceDisplay
              size="detail"
              label={closed ? 'Final bid' : bidCount > 0 ? 'Current bid' : 'Starting bid'}
              amount={currentAllIn}
              muted={closed}
              // The board says "all-in" exactly once, in the sub-line below; the suffix here
              // doubled it (pkg8-listing-*: "$99.00", then "all-in · 6 bids · 2h 14m left").
              showTotal={false}
            />
          </Animated.View>
          <View style={stacked ? styles.qtyColStacked : styles.qtyCol}>
            {/* Mixed case per the board — `label` uppercased "2 × GA TICKETS". */}
            <Text style={[textStyle('title'), styles.qty]} numberOfLines={stacked ? undefined : 2}>
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
          numberOfLines={stacked ? undefined : 2}
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
          <View style={stacked ? styles.bRowStacked : styles.bRow} testID="panel-breakdown-row">
            <Text style={[textStyle('bodySm'), styles.bLabel]}>Tickets</Text>
            <Text style={[textStyle('bodySm'), styles.bValue]} numberOfLines={stacked ? undefined : 2}>{minBidBase}</Text>
          </View>
          <View style={stacked ? styles.bRowStacked : styles.bRow} testID="panel-breakdown-row">
            <Text style={[textStyle('bodySm'), styles.bLabel]}>{RESALE_FEE_LABEL}</Text>
            <Text style={[textStyle('bodySm'), styles.bValue]} numberOfLines={stacked ? undefined : 2}>{minBidFee}</Text>
          </View>
        </View>
      ) : null}
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  wrap: {
    paddingHorizontal: v2.space.lg,
    paddingVertical: v2.space.lg,
    gap: v2.space.md,
  },
  card: {
    backgroundColor: p.surface.surface,
    padding: v2.space.lg,
    gap: v2.space.sm,
  },
  cardRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: v2.space.md,
  },
  /* Stacked above IDENTITY_STACK_SCALE: one column, so no line is competing for width. */
  cardRowStacked: {
    flexDirection: 'column',
    alignItems: 'stretch',
    gap: v2.space.xs,
  },
  cardPrice: { flexShrink: 1, minWidth: 0 },
  qtyCol: { alignItems: 'flex-end', flexShrink: 0 },
  qtyColStacked: { alignItems: 'flex-start', flexShrink: 0 },
  qty: { color: p.text.primary },
  qtyNote: { color: p.text.muted },
  subLine: { color: p.text.secondary },
  // §5: amber only for a real sub-15-minute close; the caller's clock carries that decision.
  subLineUrgent: { color: p.status.warning },
  breakdown: { gap: v2.space.xs },
  bRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
    justifyContent: 'space-between',
    gap: v2.space.md,
  },
  bRowStacked: {
    flexDirection: 'column',
    alignItems: 'flex-start',
    gap: 2,
  },
  bEyebrow: { color: p.text.muted, textTransform: 'uppercase', letterSpacing: 0.6 },
  bLabel: { color: p.text.secondary },
  bValue: { color: p.text.primary, fontVariant: ['tabular-nums'] },
  note: { color: p.text.muted },
  });
}

/**
 * src/components/listing/BidActivity.tsx — how the price got here.
 *
 * Bid history is evidence, not a leaderboard. It sits below the price and the
 * actions and is styled quieter than both, because a long list of rows should
 * never out-weigh the number the user is deciding about.
 *
 * PRIVACY IS INHERITED, NOT DECIDED HERE. A bidder is shown by display name, or
 * by a short tag derived from their id when they have none. A legal name has no
 * business being shown to the other bidders and is not fetched.
 */

import { useMemo } from 'react';
import { Pressable, StyleSheet, Text, useWindowDimensions, View } from 'react-native';

import { EmptyState } from '@/src/components/ui';
import { useAnnounceOnce } from '@/src/hooks/useAnnounceOnce';
import { TEXT_LINK_HIT_SLOP } from '@/src/lib/a11y/touch';
import { identityStacks } from '@/src/lib/design/featureMetrics';
import { AMOUNT_MIN_FONT_SCALE, MAX_DISPLAY_FONT_SCALE, textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';
import type { Bid } from '@/src/types';

export const BIDS_LOAD_FAILED_COPY = "Couldn't load bids.";

export interface BidActivityProps {
  bids: Bid[];
  /** Preformatted amounts, keyed by bid id. The caller owns money formatting. */
  amountFor: (bid: Bid) => string;
  /** Preformatted relative time. */
  timeFor: (bid: Bid) => string;
  /** The viewer's own id, so their rows are marked. */
  viewerId?: string;
  /** Live auction: the top row is the one to beat. */
  highlightTop: boolean;
  /** The bids read failed: the list is unknown, so it is never painted as "No bids yet" (B-D1). */
  loadFailed?: boolean;
  onRetry?: () => void;
  /** A read is in flight: an empty list is not yet a fact, so "No bids yet" waits (A's B-D1 rule). */
  loading?: boolean;
}

export function BidActivity({ bids, amountFor, timeFor, viewerId, highlightTop, loadFailed, onRetry, loading }: BidActivityProps) {
  // Spoken on iOS like the other failure notices (useAnnounceOnce).
  useAnnounceOnce(loadFailed && bids.length === 0 ? BIDS_LOAD_FAILED_COPY : null);
  const { palette } = useTheme();
  const styles = useMemo(() => makeStyles(palette), [palette]);
  /*
   * B's batch-6 finding: at the largest accessibility size the LEADING row's amount lost its
   * cents. That row is the one that loses them because it is the only row carrying the "Leading"
   * chip, so three things compete for the width instead of two and the amount is last.
   *
   * Same treatment as the feature, the feed row and the transaction panel, not a fourth: above
   * the shared threshold the row becomes a column, the amount owns its line, and the LINE bounds
   * it — one line always, shrinking to fit only if that line genuinely runs out. The compact form
   * keeps the display cap, which is what leaves the default row exactly as it was.
   */
  const { fontScale } = useWindowDimensions();
  const stacked = identityStacks(fontScale);
  const amountFit = stacked
    ? { adjustsFontSizeToFit: true, minimumFontScale: AMOUNT_MIN_FONT_SCALE }
    : { maxFontSizeMultiplier: MAX_DISPLAY_FONT_SCALE };
  return (
    <View style={styles.wrap}>
      {/* Board (pkg8-listing): bold sans, mixed case — not the uppercase Oswald displaySm. */}
      <Text style={[textStyle('screenTitle'), styles.head]} accessibilityRole="header">
        Bid activity
      </Text>

      {loadFailed && bids.length === 0 ? (
        // The Bids tab's inline notice, not an empty state: an unread list is not an empty one.
        <View style={styles.notice} accessibilityRole="alert">
          <View style={styles.noticeEdge} />
          <Text style={[textStyle('bodySm'), styles.noticeText]}>{BIDS_LOAD_FAILED_COPY}</Text>
          {onRetry ? (
            <Pressable onPress={onRetry} hitSlop={TEXT_LINK_HIT_SLOP} accessibilityRole="button" accessibilityLabel="Retry loading bids">
              <Text style={[textStyle('action'), styles.noticeAction]}>Retry</Text>
            </Pressable>
          ) : null}
        </View>
      ) : bids.length === 0 && loading ? (
        // In flight: nothing is claimed yet, neither empty nor failed.
        null
      ) : bids.length === 0 ? (
        <EmptyState title="No bids yet" body="Be the first to bid on this one." />
      ) : (
        bids.map((bid, i) => {
          const isMine = !!viewerId && bid.bidder_id === viewerId;
          const isTop = i === 0 && highlightTop;
          const short = bid.bidder_id ? bid.bidder_id.slice(0, 4).toUpperCase() : '----';
          // The board prints the bare code (K7F2); a screen reader still hears "Bidder K7F2"
          // through the row label below, so the visible economy costs no comprehension.
          const name = bid.profiles?.display_name ?? short;
          const spokenName = bid.profiles?.display_name ?? `Bidder ${short}`;
          return (
            <View
              key={bid.id}
              style={[stacked ? styles.rowStacked : styles.row, i === bids.length - 1 && styles.last]}
              accessible
              accessibilityLabel={
                `${isMine ? 'Your bid' : spokenName}, ${amountFor(bid)}, ${timeFor(bid)}` +
                (isTop ? '. Highest bid.' : '')
              }
            >
              <View style={styles.who}>
                <Text style={[textStyle('body'), styles.name]} numberOfLines={stacked ? undefined : 1}>
                  {isMine ? 'You' : name}
                </Text>
                <Text style={[textStyle('bodySm'), styles.time]}>{timeFor(bid)}</Text>
              </View>
              {/*
                The top bid is marked with a word as well as a colour, so the
                state survives a screenshot and a colourblind reader.
              */}
              {isTop ? (
                <View style={styles.leadingChip}>
                  <Text style={[textStyle('micro'), styles.leading]}>Leading</Text>
                </View>
              ) : null}
              <Text
                style={[textStyle('price'), styles.amount, isTop && styles.amountTop]}
                numberOfLines={1}
                {...amountFit}
              >
                {amountFor(bid)}
              </Text>
            </View>
          );
        })
      )}
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  wrap: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.xl },
  notice: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: v2.space.md,
    backgroundColor: p.surface.surface,
    borderRadius: v2.radius.sm,
    paddingVertical: v2.space.md,
    paddingRight: v2.space.md,
    overflow: 'hidden',
  },
  noticeEdge: { alignSelf: 'stretch', width: 3, backgroundColor: p.status.warning },
  noticeText: { color: p.text.secondary, flex: 1 },
  noticeAction: { color: p.text.primary },
  head: { color: p.text.primary, marginBottom: v2.space.sm },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: v2.space.md,
    paddingVertical: v2.space.md,
    borderBottomWidth: 1,
    borderBottomColor: p.border.default,
  },
  /*
   * Stacked above IDENTITY_STACK_SCALE: the bidder, the chip and the amount each get the row's
   * full width in turn, so nothing is competing for it. Same padding and the same rule below, so
   * it is this row rearranged rather than a second design.
   */
  rowStacked: {
    flexDirection: 'column',
    alignItems: 'flex-start',
    gap: v2.space.xs,
    paddingVertical: v2.space.md,
    borderBottomWidth: 1,
    borderBottomColor: p.border.default,
  },
  last: { borderBottomWidth: 0 },
  who: { flex: 1, minWidth: 0 },
  name: { color: p.text.primary },
  time: { color: p.text.muted },
  // The board's chip: soft green fill, success ink, the same pair in both appearances. Green,
  // not brand red — leading is a STATUS; red stays reserved for actions.
  leadingChip: {
    backgroundColor: p.status.successSoft,
    borderRadius: v2.radius.sm,
    paddingHorizontal: v2.space.sm,
    paddingVertical: 3,
  },
  leading: { color: p.status.onSuccessSoft },
  amount: { color: p.text.secondary, fontVariant: ['tabular-nums'] },
  amountTop: { color: p.text.primary },
  });
}

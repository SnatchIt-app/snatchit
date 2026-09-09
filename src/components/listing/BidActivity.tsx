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

import { StyleSheet, Text, View } from 'react-native';

import { EmptyState } from '@/src/components/ui';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import type { Bid } from '@/src/types';

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
}

export function BidActivity({ bids, amountFor, timeFor, viewerId, highlightTop }: BidActivityProps) {
  return (
    <View style={styles.wrap}>
      <Text style={[textStyle('displaySm'), styles.head]} accessibilityRole="header">
        Bid activity
      </Text>

      {bids.length === 0 ? (
        <EmptyState title="No bids yet" body="Be the first to bid on this one." />
      ) : (
        bids.map((bid, i) => {
          const isMine = !!viewerId && bid.bidder_id === viewerId;
          const isTop = i === 0 && highlightTop;
          const short = bid.bidder_id ? bid.bidder_id.slice(0, 4).toUpperCase() : '----';
          const name = bid.profiles?.display_name ?? `Bidder ${short}`;
          return (
            <View
              key={bid.id}
              style={[styles.row, i === bids.length - 1 && styles.last]}
              accessible
              accessibilityLabel={
                `${isMine ? 'Your bid' : name}, ${amountFor(bid)}, ${timeFor(bid)}` +
                (isTop ? '. Highest bid.' : '')
              }
            >
              <View style={styles.who}>
                <Text style={[textStyle('body'), styles.name]} numberOfLines={1}>
                  {isMine ? 'You' : name}
                </Text>
                <Text style={[textStyle('bodySm'), styles.time]}>{timeFor(bid)}</Text>
              </View>
              {/*
                The top bid is marked with a word as well as a colour, so the
                state survives a screenshot and a colourblind reader.
              */}
              {isTop ? (
                <Text style={[textStyle('micro'), styles.leading]}>Leading</Text>
              ) : null}
              <Text style={[textStyle('price'), styles.amount, isTop && styles.amountTop]}>
                {amountFor(bid)}
              </Text>
            </View>
          );
        })
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.xl },
  head: { color: v2.text.primary, marginBottom: v2.space.sm },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: v2.space.md,
    paddingVertical: v2.space.md,
    borderBottomWidth: 1,
    borderBottomColor: v2.border.default,
  },
  last: { borderBottomWidth: 0 },
  who: { flex: 1, minWidth: 0 },
  name: { color: v2.text.primary },
  time: { color: v2.text.muted },
  leading: { color: v2.brand.red },
  amount: { color: v2.text.secondary, fontVariant: ['tabular-nums'] },
  amountTop: { color: v2.text.primary },
});

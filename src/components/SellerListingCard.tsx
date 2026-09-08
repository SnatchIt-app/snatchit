/**
 * src/components/SellerListingCard.tsx — the seller's My Listings row (V2).
 *
 * A horizontal event-first card: cover, event, venue, a status Badge, the bid
 * count / current bid, and a contextual bottom line with the seller's next action
 * (time left, winner, "send the tickets", or the edit/delete/cancel affordance).
 *
 * The status and the edit/delete/cancel gates come from
 * src/lib/listing/sellerListing.ts, which mirrors the server rule: a listing with
 * bids or a non-active auction can only be cancelled. Behaviour is unchanged from
 * the legacy card; only the surface moved to V2.
 */

import { Image } from 'expo-image';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { Badge } from '@/src/components/ui';
import VerifiedSellerBadge from '@/src/components/VerifiedSellerBadge';
import {
  canCancelListing,
  canDeleteListing,
  canEditListing,
  sellerBadge,
  sellerBadgeLabel,
  sellerBadgeTone,
  timeLeftLabel,
} from '@/src/lib/listing/sellerListing';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import type { Listing } from '@/src/types';

type Props = {
  listing: Listing;
  coverUrl: string | null;
  onPress: () => void;
  onDelete?: () => void;
  onEdit?: () => void;
  isVerifiedSeller?: boolean;
  /** Sold but tickets not sent yet — surfaces the "send the tickets" line. */
  needsTicketSend?: boolean;
};

function fmt$(n: number) { return `$${Math.round(n).toLocaleString('en-US')}`; }

function titleCase(s: string | null | undefined): string {
  return (s ?? '').replace(/\b\w/g, (c) => c.toUpperCase());
}

export default function SellerListingCard({ listing, coverUrl, onPress, onDelete, onEdit, isVerifiedSeller, needsTicketSend }: Props) {
  const badge = sellerBadge(listing);
  const cancelled = badge === 'cancelled';
  const canEdit = canEditListing(listing);
  const canDelete = canDeleteListing(listing);
  const canCancel = canCancelListing(listing);

  // Compose one spoken label: the grouped Pressable otherwise announces only the
  // event name, dropping the status badge and bid/price a sighted user sees.
  const bidMeta = listing.bid_count === 0
    ? 'No bids'
    : `${listing.bid_count} bid${listing.bid_count !== 1 ? 's' : ''}, ${fmt$(listing.current_bid)}`;
  const a11yLabel = `${listing.event_name}. ${sellerBadgeLabel(badge)}. ${bidMeta}.`;

  return (
    <Pressable style={[s.card, cancelled && s.cardCancelled]} onPress={onPress} accessibilityRole="button" accessibilityLabel={a11yLabel}>
      {coverUrl ? (
        <Image source={{ uri: coverUrl }} style={s.thumb} contentFit="cover" />
      ) : (
        <View style={[s.thumb, s.thumbEmpty]} />
      )}

      <View style={s.content}>
        <View style={s.titleRow}>
          <Text style={[textStyle('title'), s.event]} numberOfLines={1}>{listing.event_name}</Text>
          {isVerifiedSeller != null ? <VerifiedSellerBadge isVerified={isVerifiedSeller} /> : null}
        </View>

        <Text style={[textStyle('bodySm'), s.venue]} numberOfLines={1}>
          {listing.venue}{listing.neighborhood ? ` · ${titleCase(listing.neighborhood)}` : ''}
        </Text>

        <View style={s.metaRow}>
          <Badge label={sellerBadgeLabel(badge)} tone={sellerBadgeTone(badge)} />
          <Text style={[textStyle('bodySm'), s.meta]}>
            {listing.bid_count === 0 ? 'No bids' : `${listing.bid_count} bid${listing.bid_count !== 1 ? 's' : ''}`}
            {listing.bid_count > 0 ? ` · ${fmt$(listing.current_bid)}` : ''}
          </Text>
        </View>

        <View style={s.bottomRow}>
          <View style={s.bottomLeft}>
            {cancelled ? (
              <Text style={[textStyle('bodySm'), s.dim]}>Cancelled</Text>
            ) : badge === 'active' || badge === 'ending_soon' ? (
              <Text style={[textStyle('bodySm'), badge === 'ending_soon' ? s.urgent : s.dim]}>{timeLeftLabel(listing.ends_at)}</Text>
            ) : badge === 'ended' && listing.winner_user_id ? (
              <Text style={[textStyle('bodySm'), s.ok]}>Winner selected</Text>
            ) : badge === 'sold' && needsTicketSend ? (
              <Text style={[textStyle('bodySm'), s.action]}>Action needed — send the tickets</Text>
            ) : badge === 'sold' && listing.sold_at ? (
              <Text style={[textStyle('bodySm'), s.dim]}>Sold {new Date(listing.sold_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}</Text>
            ) : null}
          </View>

          <View style={s.actions}>
            {canEdit && onEdit ? (
              <Pressable onPress={onEdit} hitSlop={8} accessibilityRole="button" accessibilityLabel="Edit listing">
                <Text style={[textStyle('label'), s.edit]}>Edit</Text>
              </Pressable>
            ) : null}
            {canDelete && onDelete ? (
              <Pressable onPress={onDelete} hitSlop={8} accessibilityRole="button" accessibilityLabel="Delete listing">
                <Text style={[textStyle('label'), s.delete]}>Delete</Text>
              </Pressable>
            ) : null}
            {canCancel && onDelete ? (
              <Pressable onPress={onDelete} hitSlop={8} accessibilityRole="button" accessibilityLabel="Cancel listing">
                <Text style={[textStyle('label'), s.cancel]}>Cancel</Text>
              </Pressable>
            ) : null}
          </View>
        </View>
      </View>
    </Pressable>
  );
}

const s = StyleSheet.create({
  card: {
    flexDirection: 'row',
    gap: v2.space.md,
    borderWidth: 1,
    borderColor: v2.border.default,
    backgroundColor: v2.surface.surface,
    padding: v2.space.md,
    marginBottom: v2.space.sm,
  },
  cardCancelled: { opacity: 0.55 },

  thumb: { width: 76, height: 76 },
  thumbEmpty: { backgroundColor: v2.surface.elevated, borderWidth: 1, borderColor: v2.border.default },

  content: { flex: 1, minWidth: 0, justifyContent: 'center', gap: v2.space.xs },
  titleRow: { flexDirection: 'row', alignItems: 'center', gap: v2.space.xs },
  event: { color: v2.text.primary, flexShrink: 1 },
  venue: { color: v2.text.muted },

  metaRow: { flexDirection: 'row', alignItems: 'center', gap: v2.space.sm, flexWrap: 'wrap' },
  meta: { color: v2.text.muted },

  bottomRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: v2.space.sm },
  bottomLeft: { flexShrink: 1, minWidth: 0 },
  dim: { color: v2.text.faint },
  urgent: { color: v2.status.error },
  ok: { color: v2.status.success },
  action: { color: v2.status.warning },

  actions: { flexDirection: 'row', gap: v2.space.md },
  edit: { color: v2.brand.red },
  delete: { color: v2.status.error },
  cancel: { color: v2.status.warning },
});

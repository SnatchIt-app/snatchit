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
 *
 * The cover goes through EventMedia like every other event image: it takes the
 * RAW stored path and provides the frame, the branded fallback (missing or
 * failed), the slot-sized derivative and the recycling key a raw Image never had.
 */

import { StyleSheet, Text, View } from 'react-native';

import { EventMedia } from '@/src/components/media/EventMedia';
import { Badge, Tappable } from '@/src/components/ui';
import { NameText } from '@/src/components/NameText';
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
import { formatDollars } from '@/src/lib/money';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import type { Listing } from '@/src/types';

/** The row's thumbnail edge, in points. Passed to EventMedia as the laid-out width. */
const THUMB = 76;

type Props = {
  listing: Listing;
  onPress: () => void;
  onDelete?: () => void;
  /** F-DESTRUCT-1: a destructive request is running for this listing — the actions stand down. */
  busy?: boolean;
  onEdit?: () => void;
  isVerifiedSeller?: boolean;
  /** Sold but tickets not sent yet — surfaces the "send the tickets" line. */
  needsTicketSend?: boolean;
};

/** Whole-dollar bid display through the one formatter (CFT-207). */
const fmt$ = formatDollars;

function titleCase(s: string | null | undefined): string {
  return (s ?? '').replace(/\b\w/g, (c) => c.toUpperCase());
}

export default function SellerListingCard({ listing, onPress, onDelete, onEdit, isVerifiedSeller, needsTicketSend, busy }: Props) {
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
    // The row carries the product's press response like every other tappable (CFT-201).
    <Tappable style={[s.card, cancelled && s.cardCancelled]} onPress={onPress} accessibilityRole="button" accessibilityLabel={a11yLabel}>
      {/* A dense list: recognition, not persuasion — the SEARCH_RESULT slot at
          the row's own 76pt edge. Decorative: the row text already names the event. */}
      <EventMedia
        asset={{ path: listing.cover_image_path, contract: 'legacy', bucket: 'auction-media' }}
        slot="SEARCH_RESULT"
        width={THUMB}
        title={listing.event_name}
        decorative
      />

      <View style={s.content}>
        <View style={s.titleRow}>
          <NameText token="nameRow" maxLines={1} style={s.event}>{listing.event_name}</NameText>
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
              <Tappable onPress={onEdit} hitSlop={8} accessibilityRole="button" accessibilityLabel="Edit listing">
                <Text style={[textStyle('label'), s.edit]}>Edit</Text>
              </Tappable>
            ) : null}
            {canDelete && onDelete ? (
              <Tappable onPress={onDelete} disabled={busy} hitSlop={8} accessibilityRole="button" accessibilityLabel="Delete listing">
                <Text style={[textStyle('label'), s.delete]}>Delete</Text>
              </Tappable>
            ) : null}
            {canCancel && onDelete ? (
              <Tappable onPress={onDelete} disabled={busy} hitSlop={8} accessibilityRole="button" accessibilityLabel="Cancel listing">
                <Text style={[textStyle('label'), s.cancel]}>Cancel</Text>
              </Tappable>
            ) : null}
          </View>
        </View>
      </View>
    </Tappable>
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

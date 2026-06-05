/**
 * src/components/SellerListingCard.tsx
 *
 * Compact horizontal card for the seller's "My Listings" screen.
 * Layout: 80×80 cover thumbnail (left) + stacked info (right).
 *
 * Differences from the home-feed ListingCard:
 *  - Horizontal (not tall vertical)
 *  - Seller-oriented status: ACTIVE / ENDING SOON / ENDED / RESERVED / SOLD
 *  - Shows bid_count, current_bid pills
 *  - Conditional bottom row: countdown, winner info, sold date, delete action
 */

import { Image } from 'expo-image';
import { Pressable, StyleSheet, Text, TouchableOpacity, View } from 'react-native';

import { colors, fontSize, radius, spacing } from '@/src/theme';
import VerifiedSellerBadge from '@/src/components/VerifiedSellerBadge';
import type { Listing } from '@/src/types';

// ─── Props ───────────────────────────────────────────────────────────────────

type Props = {
  listing: Listing;
  coverUrl: string | null;
  onPress: () => void;
  onDelete?: () => void;
  onEdit?: () => void;
  isVerifiedSeller?: boolean;
};

// ─── Status badge ────────────────────────────────────────────────────────────

type Badge = 'ACTIVE' | 'ENDING SOON' | 'ENDED' | 'RESERVED' | 'SOLD' | 'CANCELLED';

function getBadge(listing: Listing): Badge {
  if (listing.auction_status === 'cancelled') return 'CANCELLED';
  if (listing.status === 'sold') return 'SOLD';
  if (
    listing.status === 'reserved' &&
    listing.reserved_until &&
    new Date(listing.reserved_until).getTime() > Date.now()
  ) return 'RESERVED';
  const clockExpired = new Date(listing.ends_at).getTime() <= Date.now();
  if (listing.auction_status === 'ended' || clockExpired) return 'ENDED';
  const msLeft = new Date(listing.ends_at).getTime() - Date.now();
  if (msLeft <= 15 * 60 * 1000) return 'ENDING SOON';
  return 'ACTIVE';
}

const BADGE_STYLE: Record<Badge, { bg: string; text: string }> = {
  'ACTIVE':      { bg: 'rgba(74,222,128,0.15)', text: colors.success },
  'ENDING SOON': { bg: 'rgba(255,77,109,0.15)', text: colors.error },
  'ENDED':       { bg: 'rgba(255,255,255,0.06)', text: colors.textMuted },
  'RESERVED':    { bg: 'rgba(251,191,36,0.12)',  text: colors.warning },
  'SOLD':        { bg: 'rgba(255,215,0,0.12)',   text: '#FFD700' },
  'CANCELLED':   { bg: 'rgba(255,255,255,0.06)', text: colors.textDim },
};

// ─── Helpers ─────────────────────────────────────────────────────────────────

function fmt$(n: number) { return `$${Math.round(n).toLocaleString('en-US')}`; }

function timeLabel(endsAt: string): string {
  const diff = new Date(endsAt).getTime() - Date.now();
  if (diff <= 0) return 'Ended';
  const h = Math.floor(diff / 3_600_000);
  const m = Math.floor((diff % 3_600_000) / 60_000);
  if (h > 23) return `${Math.floor(h / 24)}d ${h % 24}h left`;
  if (h > 0) return `${h}h ${m}m left`;
  return `${m}m left`;
}

function shortDate(iso: string): string {
  return new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

// ─── Component ───────────────────────────────────────────────────────────────

export default function SellerListingCard({ listing, coverUrl, onPress, onDelete, onEdit, isVerifiedSeller }: Props) {
  const badge      = getBadge(listing);
  const badgeS     = BADGE_STYLE[badge];
  const ended      = badge === 'ENDED' || badge === 'SOLD' || badge === 'CANCELLED';
  const cancelled  = badge === 'CANCELLED';
  // Edit allowed only when no bids have come in AND the auction is active.
  // Once bids exist, listings become contractual — sellers must Cancel.
  const canEdit    = !ended && listing.bid_count === 0 && listing.auction_status === 'active';
  const canDelete  = !ended && listing.bid_count === 0 && listing.auction_status === 'active';
  const canCancel  = !ended && listing.bid_count > 0 && listing.auction_status === 'active';

  return (
    <Pressable
      style={[s.card, cancelled && s.cardCancelled]}
      onPress={onPress}
      android_ripple={{ color: colors.primarySoft }}
    >

      {/* ── Thumbnail ───────────────────────────────────────────── */}
      {coverUrl ? (
        <Image source={{ uri: coverUrl }} style={s.thumb} contentFit="cover" />
      ) : (
        <View style={[s.thumb, s.thumbPlaceholder]}>
          <Text style={s.thumbEmoji}>🎟️</Text>
        </View>
      )}

      {/* ── Content ─────────────────────────────────────────────── */}
      <View style={s.content}>
        {/* Row 1: event name + verified badge */}
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, marginBottom: 2 }}>
          <Text style={[s.eventName, { marginBottom: 0 }]} numberOfLines={1}>{listing.event_name}</Text>
          {isVerifiedSeller != null && <VerifiedSellerBadge isVerified={isVerifiedSeller} />}
        </View>

        {/* Row 2: venue + neighborhood */}
        <Text style={s.venue} numberOfLines={1}>
          {listing.venue} · {listing.neighborhood?.replace(/\b\w/g, c => c.toUpperCase()) ?? ''}
        </Text>

        {/* Row 3: info pills */}
        <View style={s.pillRow}>
          <View style={[s.pill, { backgroundColor: badgeS.bg }]}>
            <Text style={[s.pillText, { color: badgeS.text }]}>{badge}</Text>
          </View>
          <View style={s.infoPill}>
            <Text style={s.infoPillText}>
              {listing.bid_count === 0 ? 'No bids' : `${listing.bid_count} bid${listing.bid_count !== 1 ? 's' : ''}`}
            </Text>
          </View>
          <View style={s.infoPill}>
            <Text style={s.infoPillText}>
              {listing.bid_count > 0 ? fmt$(listing.current_bid) : '—'}
            </Text>
          </View>
        </View>

        {/* Row 4: contextual bottom line */}
        <View style={s.bottomRow}>
          {cancelled ? (
            <Text style={[s.bottomText, { color: colors.textDim }]}>Cancelled</Text>
          ) : badge === 'ACTIVE' || badge === 'ENDING SOON' ? (
            <Text style={[s.bottomText, badge === 'ENDING SOON' && { color: colors.error }]}>
              {timeLabel(listing.ends_at)}
            </Text>
          ) : badge === 'ENDED' && listing.winner_user_id ? (
            <Text style={[s.bottomText, { color: colors.success }]}>Winner selected</Text>
          ) : badge === 'SOLD' && listing.sold_at ? (
            <Text style={s.bottomText}>Sold {shortDate(listing.sold_at)}</Text>
          ) : (
            <Text style={s.bottomText}>{ended ? 'No winner' : ''}</Text>
          )}

          {/* Edit — no bids, active */}
          {canEdit && onEdit && (
            <TouchableOpacity onPress={onEdit} hitSlop={8}>
              <Text style={s.editText}>Edit</Text>
            </TouchableOpacity>
          )}

          {/* Delete — no bids, active */}
          {canDelete && onDelete && (
            <TouchableOpacity onPress={onDelete} hitSlop={8}>
              <Text style={s.deleteText}>Delete</Text>
            </TouchableOpacity>
          )}

          {/* Cancel — has bids, active */}
          {canCancel && onDelete && (
            <TouchableOpacity onPress={onDelete} hitSlop={8}>
              <Text style={s.cancelText}>Cancel</Text>
            </TouchableOpacity>
          )}
        </View>
      </View>

    </Pressable>
  );
}

// ─── Styles ──────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  card: {
    flexDirection: 'row',
    backgroundColor: colors.bgCard,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.border,
    padding: spacing.md,
    marginBottom: spacing.sm,
  },
  cardCancelled: {
    opacity: 0.6,
  },

  // Thumbnail
  thumb:            { width: 80, height: 80, borderRadius: radius.sm },
  thumbPlaceholder: { backgroundColor: colors.bgInput, alignItems: 'center', justifyContent: 'center' },
  thumbEmoji:       { fontSize: 28 },

  // Content area
  content:   { flex: 1, marginLeft: spacing.md, justifyContent: 'center' },
  eventName: { fontSize: fontSize.sm, fontWeight: '700', color: colors.text, marginBottom: 2 },
  venue:     { fontSize: fontSize.xs, color: colors.textMuted, marginBottom: spacing.xs },

  // Info pills row
  pillRow:      { flexDirection: 'row', gap: 6, marginBottom: spacing.xs, flexWrap: 'wrap' },
  pill:         { paddingHorizontal: 7, paddingVertical: 2, borderRadius: radius.sm },
  pillText:     { fontSize: 10, fontWeight: '700', letterSpacing: 0.4 },
  infoPill:     { backgroundColor: 'rgba(255,255,255,0.06)', paddingHorizontal: 7, paddingVertical: 2, borderRadius: radius.sm },
  infoPillText: { fontSize: 10, fontWeight: '600', color: colors.textMuted },

  // Bottom contextual row
  bottomRow:  { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  bottomText: { fontSize: fontSize.xs, color: colors.textDim, fontWeight: '600' },
  deleteText: { fontSize: fontSize.xs, color: colors.error, fontWeight: '700' },
  cancelText: { fontSize: fontSize.xs, color: colors.warning, fontWeight: '700' },
  editText:   { fontSize: fontSize.xs, color: colors.primary, fontWeight: '700', marginRight: spacing.sm },
});

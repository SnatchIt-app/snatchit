/**
 * src/components/SellerListingCard.tsx — the seller's My Listings row (V3).
 *
 * Board: composition `pkg3-my-listings-clean.png`, tokens `pkg8-mylistings-{dark,light}.png`.
 * A hairline-separated list row, not a boxed card: cover on the left, the event name in the
 * display voice with the status Badge at the row's right edge, one meta line ("6 bids · $90.00",
 * or "Sold Fri 17 Oct" once sold), and a contextual bottom line — the live countdown in the
 * status's own colour, "Winner selected", or "Action needed — send the tickets".
 *
 * The status and the edit/delete/cancel gates come from src/lib/listing/sellerListing.ts,
 * which mirrors the server rule: a listing with bids or a non-active auction can only be
 * cancelled. Behaviour is unchanged from V2; only the surface moved to the approved boards.
 *
 * DELIBERATE DIFFERENCES FROM THE BOARD, each with its reason:
 *  - Edit / Delete / Cancel stay on the row. The board draws no affordance, but this row is
 *    the ONLY place a seller can edit, delete or cancel today (the listing detail offers
 *    none); removing them is a functional change that needs its own ruling, not a re-skin.
 *    They speak the V3 action voice, not the V2 tracked uppercase.
 *  - EC7 (owner-pinned): a cancelled row says "Cancelled" ONCE — the Badge. The board prints
 *    it a second time as a bottom line; the ruling wins over the board.
 *  - The cancelled recession dims the ARTWORK and recedes the name to secondary ink instead
 *    of scaling the whole row to 0.55 as pkg3 annotation ③ draws: the owner ruled 2026-09-24
 *    "keep meaningful text outside dimmed artwork layers" after 0.55 text measured 2.71:1 on
 *    the Daylight canvas (tests/v3-dimmed-layers.test.ts walks the tree for this).
 *
 * The cover goes through EventMedia like every other event image: it takes the RAW stored
 * path and provides the frame, the branded fallback, the slot-sized derivative and the
 * recycling key a raw Image never had.
 */

import { useMemo } from 'react';
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
  timeLeftLabel,
  type SellerBadge,
} from '@/src/lib/listing/sellerListing';
import { MEDIA_SLOTS } from '@/src/lib/media/slots';
import { formatDollars } from '@/src/lib/money';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';
import type { Listing } from '@/src/types';

/**
 * The row's thumbnail box — 76 is its HEIGHT, not its edge (owner 2026-09-24, the 4:5 poster).
 *
 * `THUMB = 76` was passed to EventMedia as `width` and read as a 76pt square. Under the poster
 * direction only one of the two edges can stay fixed, and it has to be the height: 76 is the row's
 * VERTICAL budget — the row's height is content-driven from this image plus its padding, and every
 * My Listings row the owner accepted was measured against a 76pt-tall thumbnail. Holding the width
 * instead would make the poster 95 tall and grow every row by 19pt. So the height stays 76 and the
 * width comes down to 61.
 *
 * The width is DERIVED from the slot this card actually renders, using the same expression
 * EventMedia uses internally (`round(height × aspectRatio)`), so the skeleton that stands in for
 * this box cannot drift from the box by a rounding point. Exported for that skeleton
 * (app/my-listings.tsx) — the screen must not compute a poster edge of its own.
 */
export const SELLER_THUMB_H = 76;
export const SELLER_THUMB_W = Math.round(SELLER_THUMB_H * MEDIA_SLOTS.SEARCH_RESULT.aspectRatio);

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

/**
 * Board badge tones (pkg8-mylistings-{dark,light}): Ending soon and Sold are the AMBER words —
 * one urgency, one action pending — where V2 had red and green. Local to this card because
 * src/lib/listing/sellerListing.ts is outside this task's files; the label still comes from
 * sellerBadgeLabel, so the WORD cannot drift.
 */
const V3_BADGE_TONE: Record<SellerBadge, 'neutral' | 'success' | 'warning' | 'danger'> = {
  active: 'success',
  ending_soon: 'warning',
  ended: 'neutral',
  reserved: 'warning',
  sold: 'warning',
  cancelled: 'neutral',
};

const WEEKDAY = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'] as const;
const MONTH = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'] as const;

/**
 * "Sold Fri 17 Oct" — the board's meta line for a sold row. Fixed tables, not
 * toLocaleDateString, for the same reason as feedRowState: the row must read identically on
 * every device locale. Empty when unparseable, so the row never shows "Sold Invalid Date".
 */
export function soldOnLabel(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return `Sold ${WEEKDAY[d.getDay()]} ${d.getDate()} ${MONTH[d.getMonth()]}`;
}

export default function SellerListingCard({ listing, onPress, onDelete, onEdit, isVerifiedSeller, needsTicketSend, busy }: Props) {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const badge = sellerBadge(listing);
  const cancelled = badge === 'cancelled';
  const canEdit = canEditListing(listing);
  const canDelete = canDeleteListing(listing);
  const canCancel = canCancelListing(listing);

  const bidMeta = listing.bid_count === 0
    ? 'No bids'
    : `${listing.bid_count} bid${listing.bid_count !== 1 ? 's' : ''} · ${fmt$(listing.current_bid)}`;
  // Board meta line: the sale date once sold, otherwise the bid activity.
  const metaLine = badge === 'sold' && listing.sold_at ? soldOnLabel(listing.sold_at) : bidMeta;

  // Compose one spoken label: the grouped Pressable otherwise announces only the
  // event name, dropping the status badge and bid/price a sighted user sees.
  const a11yLabel = `${listing.event_name}. ${sellerBadgeLabel(badge)}. ${metaLine}.`;

  return (
    // The row carries the product's press response like every other tappable (CFT-201).
    <Tappable style={s.card} onPress={onPress} accessibilityRole="button" accessibilityLabel={a11yLabel}>
      {/* A dense list: recognition, not persuasion — the SEARCH_RESULT poster at the row's own
          76pt HEIGHT, the width taken from the 4:5 ratio. Decorative: the row text already names
          the event. */}
      {/* Cancelled recedes by dimming the artwork and shifting the name to secondary ink; the
          words never sit under an opacity layer (owner 2026-09-24, v3-dimmed-layers). */}
      <EventMedia
        asset={{ path: listing.cover_image_path, contract: 'legacy', bucket: 'auction-media' }}
        slot="SEARCH_RESULT"
        height={SELLER_THUMB_H}
        title={listing.event_name}
        decorative
        style={cancelled ? s.cardCancelled : undefined}
      />

      <View style={s.content}>
        <View style={s.titleRow}>
          <NameText token="nameRow" maxLines={2} style={cancelled ? s.eventCancelled : s.event}>
            {listing.event_name}
          </NameText>
          {isVerifiedSeller != null ? <VerifiedSellerBadge isVerified={isVerifiedSeller} /> : null}
          <Badge label={sellerBadgeLabel(badge)} tone={V3_BADGE_TONE[badge]} />
        </View>

        <Text style={[textStyle('bodySm'), s.meta]} numberOfLines={1}>{metaLine}</Text>

        <View style={s.bottomRow}>
          <View style={s.bottomLeft}>
            {/* No `cancelled` branch: the Badge beside it already reads "Cancelled" (EC7) and the
                word is in a11yLabel through sellerBadgeLabel(badge). The sold date lives on the
                meta line above (board), so this slot carries only what the badge does not say. */}
            {badge === 'active' || badge === 'ending_soon' ? (
              <Text style={[textStyle('bodySm'), badge === 'ending_soon' ? s.urgent : s.live]}>{timeLeftLabel(listing.ends_at)}</Text>
            ) : badge === 'ended' && listing.winner_user_id ? (
              <Text style={[textStyle('bodySm'), s.ok]}>Winner selected</Text>
            ) : badge === 'sold' && needsTicketSend ? (
              <Text style={[textStyle('bodySm'), s.action]}>Action needed — send the tickets</Text>
            ) : null}
          </View>

          <View style={s.actions}>
            {canEdit && onEdit ? (
              <Tappable onPress={onEdit} hitSlop={8} accessibilityRole="button" accessibilityLabel="Edit listing">
                <Text style={[textStyle('action'), s.edit]}>Edit</Text>
              </Tappable>
            ) : null}
            {canDelete && onDelete ? (
              <Tappable onPress={onDelete} disabled={busy} hitSlop={8} accessibilityRole="button" accessibilityLabel="Delete listing">
                <Text style={[textStyle('action'), s.delete]}>Delete</Text>
              </Tappable>
            ) : null}
            {canCancel && onDelete ? (
              <Tappable onPress={onDelete} disabled={busy} hitSlop={8} accessibilityRole="button" accessibilityLabel="Cancel listing">
                <Text style={[textStyle('action'), s.cancel]}>Cancel</Text>
              </Tappable>
            ) : null}
          </View>
        </View>
      </View>
    </Tappable>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  // Board: a hairline-separated row on the canvas, not a bordered box.
  card: {
    flexDirection: 'row',
    gap: v2.space.md,
    paddingVertical: v2.space.md,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: p.border.default,
  },
  cardCancelled: { opacity: 0.55 },

  content: { flex: 1, minWidth: 0, justifyContent: 'center', gap: v2.space.xs },
  titleRow: { flexDirection: 'row', alignItems: 'flex-start', gap: v2.space.sm },
  event: { color: p.text.primary, flex: 1 },
  // Receded, not scaled: secondary ink keeps the cancelled name legible on both canvases.
  eventCancelled: { color: p.text.secondary, flex: 1 },

  meta: { color: p.text.muted },

  bottomRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: v2.space.sm },
  bottomLeft: { flexShrink: 1, minWidth: 0 },
  // Board: the live countdown wears the status colour — green while active, amber under 15m.
  live: { color: p.status.success },
  urgent: { color: p.status.warning },
  ok: { color: p.status.success },
  action: { color: p.status.warning },

  actions: { flexDirection: 'row', gap: v2.space.md },
  edit: { color: p.brand.redText },
  delete: { color: p.status.error },
  cancel: { color: p.status.warning },
  });
}

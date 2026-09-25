/**
 * src/components/listing/ListingHero.tsx — the poster, its navigation, and the identity beneath it.
 *
 * OWNER RULING 2026-09-25, the listing half of the Home ruling a day earlier: the event name, the
 * date line and the From-a-fan provenance label go BENEATH the complete 4:5 poster; no app text or
 * badges over the printed content; the text-supporting gradient is removed; navigation stays
 * reachable without obscuring important poster content.
 *
 * WHY THE OVERLAY WAS WRONG, and it is the same argument as the Home feature's. A flyer prints its
 * own name, date, venue and lineup, usually set at the bottom edge — so an overlaid identity block
 * put our type on theirs, and the gradient existed to darken theirs enough for ours to read. B's
 * comparison panels showed exactly that collision. The measured contrast figures this file used to
 * quote (name band 15.91, date line 5.94) were true and beside the point: they measured our text
 * against a scrim we had added, not against the poster we were covering.
 *
 * WHAT STAYS ON THE ARTWORK: the back and overflow controls, which the owner classes as NAVIGATION
 * rather than app text. They keep their `onArt` treatment, and they do not depend on the deleted
 * scrim for legibility — `IconButton onArt` paints its own `rgba(0,0,0,0.55)` chip behind the
 * glyph, so each control carries its own contrast floor. That was checked before the scrim was
 * removed, not assumed.
 *
 * A CONSEQUENCE TO LOOK AT RATHER THAN HIDE: the controls sit at the poster's top-left and
 * top-right, so on a flyer whose type reaches those corners they cover printed content. The
 * `markers-*` and `flyer-dense-4x5` fixtures deliberately print a word in every corner so a review
 * can see precisely what a chip covers.
 *
 * THE INK FAMILY CHANGED with the position: `onArt` is white in BOTH appearances by contract, so
 * the moved block uses canvas inks. Left as `onArt` it would have been white-on-near-white in
 * Light and would have passed every Dark capture — the same trap as the Home feature.
 *
 * NOTHING TRANSACTIONAL IS OVER THE IMAGE — that V2 rule survives, and now nothing at all is.
 */

import { useMemo } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { useTopInset } from '@/src/lib/nav/navInsets';

import { EventMedia } from '@/src/components/media/EventMedia';
import { NameText } from '@/src/components/NameText';
import { FromAFanBadge, IconButton } from '@/src/components/ui';
import { FEATURE_GUTTER, HERO_NAME_GAP } from '@/src/lib/design/featureMetrics';
import { rowWhenLabel } from '@/src/lib/listing/feedRowState';
import type { MediaAsset } from '@/src/lib/media/url';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

export interface ListingHeroProps {
  asset: MediaAsset;
  eventName: string;
  venue: string;
  /** Stored values; the §3 dated line is built here so home, search and this hero agree. */
  eventDate: string;
  eventTime: string;
  onBack: () => void;
  /** Omitted for the seller's own listing: there is no point reporting yourself. */
  onOverflow?: () => void;
}

/*
 * HERO_DATE_BOTTOM is gone from this file with the overlay it positioned: it measured a distance
 * from the IMAGE's bottom edge, which is not a thing a block below the image has. HERO_NAME_GAP
 * survives because it is a gap between two lines of OUR type, which is unchanged by where they sit.
 */

export function ListingHero({
  asset,
  eventName,
  venue,
  eventDate,
  eventTime,
  onBack,
  onOverflow,
}: ListingHeroProps) {
  const { palette } = useTheme();
  const styles = useMemo(() => makeStyles(palette), [palette]);
  // The artwork runs under the status bar on purpose — a safe-area gap above it
  // would frame the image like a card. The CONTROLS still have to clear the
  // notch, so the inset is applied to them rather than to the frame.
  // F-SELL-2: the badge-aware top inset (status bar + the SANDBOX badge on sandbox builds).
  const topPad = useTopInset();

  return (
    <>
      {/* The poster, carrying NAVIGATION only. Nothing else is a child of the frame, because a
          child of EventMedia draws inside it. */}
      <EventMedia asset={asset} slot="LISTING_HERO_V3" title={eventName} fluid>
        <View
          style={[styles.controls, { top: topPad + v2.space.sm }]}
          pointerEvents="box-none"
        >
          <IconButton glyph="back" accessibilityLabel="Go back" onPress={onBack} onArt />
          {onOverflow ? (
            <IconButton
              glyph="more"
              accessibilityLabel="More actions"
              onPress={onOverflow}
              onArt
            />
          ) : null}
        </View>
      </EventMedia>

      {/* The app's identity for this listing, in its own area beneath the poster. */}
      <View style={styles.identity}>
        {/*
          Provenance says "From a fan" and never "Direct from event": migration 093 is not
          deployed and every native rail flag is false, so no venue-issued ticket exists for
          that claim to be true about. The owner treats this label as APP TEXT, so it moved off the
          artwork with the rest of the block — and it drops `onArt` for the same reason the lines
          below it do.
        */}
        <View style={styles.badge}>
          <FromAFanBadge />
        </View>
        <Text style={[textStyle('bodySm'), styles.when]} numberOfLines={1}>
          {`${rowWhenLabel(eventDate, eventTime)} · ${venue}`}
        </Text>
        <NameText token="nameDetail" maxLines={2} style={styles.title}>
          {eventName}
        </NameText>
      </View>
    </>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  controls: {
    position: 'absolute',
    left: v2.space.sm,
    right: v2.space.sm,
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  /*
   * Beneath the poster now, so it is a normal block rather than an absolutely positioned overlay.
   * It keeps the poster's gutter so the type still lines up with the artwork's edges.
   */
  identity: {
    paddingHorizontal: FEATURE_GUTTER,
    paddingTop: v2.space.md,
    paddingBottom: v2.space.sm,
  },
  badge: { alignSelf: 'flex-start', marginBottom: v2.space.sm },
  /* CANVAS inks — `onArt` is white in both appearances and would vanish on Light's canvas. */
  when: { color: p.text.muted, marginBottom: HERO_NAME_GAP - v2.space.xs },
  title: { color: p.text.primary },
  });
}

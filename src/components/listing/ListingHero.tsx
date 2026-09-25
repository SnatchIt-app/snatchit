/**
 * src/components/listing/ListingHero.tsx — artwork, controls, identity.
 *
 * V3 (owner 2026-09-22; §3 + the midnight-listing mockup). The artwork runs full-bleed, and the
 * IDENTITY — the dated line and the name in the display voice — sits over its bottom band, under
 * the measured curve scrim the slot carries (B measured the name band at 3:1 worst 15.91 and the
 * date line at 4.5:1 worst 5.94 with this curve; real uploads are device check D-2).
 *
 * THE FRAME IS A 4:5 POSTER (owner 2026-09-24), not the retired §3 formula. `heroHeight(w) =
 * w × 0.62 + 24` is deleted from featureMetrics, so LISTING_HERO_V3's ratio is the only height
 * authority: at a 393pt device the frame is ~491pt tall where the formula gave ~268.
 *
 * NO GEOMETRY HERE MOVED, and that is the point of how it was written. The frame has always been
 * `fluid` — it measures the real width and takes its height from the slot — so this file never held
 * the formula to begin with. And every identity value is measured from the image's BOTTOM edge, so
 * a taller frame only moves the artwork's TOP up: the approved date/name block stays exactly where
 * it was approved (HERO_DATE_BOTTOM 78, HERO_NAME_GAP 19).
 *
 * NOTHING TRANSACTIONAL IS OVER THE IMAGE — that V2 rule survives. The price, the breakdown
 * and the actions all live below in solid type; only identity moved onto the artwork, and only
 * because the scrim now guarantees it a floor. Provenance stays on the artwork too (a label,
 * not a decision), stacked above the date line so nothing collides.
 */

import { useMemo } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { useTopInset } from '@/src/lib/nav/navInsets';

import { EventMedia } from '@/src/components/media/EventMedia';
import { NameText } from '@/src/components/NameText';
import { FromAFanBadge, IconButton } from '@/src/components/ui';
import { FEATURE_GUTTER, HERO_DATE_BOTTOM, HERO_NAME_GAP } from '@/src/lib/design/featureMetrics';
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

// §3: the date line sits HERO_DATE_BOTTOM above the image bottom and the name HERO_NAME_GAP
// below it. Bottom-anchoring the stack with the remainder as padding lets a two-line name grow
// UPWARD instead of running off the image; the name's own line step comes from its token.
const CONTENT_BOTTOM = HERO_DATE_BOTTOM - HERO_NAME_GAP - v2.type.nameDetail.lineHeight;

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

      <View style={styles.identity} pointerEvents="none">
        {/*
          Provenance says "From a fan" and never "Direct from event": migration 093 is not
          deployed and every native rail flag is false, so no venue-issued ticket exists for
          that claim to be true about.
        */}
        <View style={styles.badge}>
          <FromAFanBadge onArt />
        </View>
        <Text style={[textStyle('bodySm'), styles.when]} numberOfLines={1}>
          {`${rowWhenLabel(eventDate, eventTime)} · ${venue}`}
        </Text>
        <NameText token="nameDetail" maxLines={2} style={styles.title}>
          {eventName}
        </NameText>
      </View>
    </EventMedia>
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
  identity: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    paddingHorizontal: FEATURE_GUTTER,
    paddingBottom: CONTENT_BOTTOM,
  },
  badge: { alignSelf: 'flex-start', marginBottom: v2.space.sm },
  when: { color: p.onArt.secondary, marginBottom: HERO_NAME_GAP - v2.space.xs },
  title: { color: p.onArt.primary },
  });
}

/**
 * src/components/listing/ListingHero.tsx — artwork, controls, identity.
 *
 * The artwork is the product, so it runs full width at the top of the screen and
 * at full strength. Only the bottom band carries a scrim, and only because the
 * back and overflow controls and the provenance badge sit over it.
 *
 * NOTHING TRANSACTIONAL IS OVER THE IMAGE. The price, the actions and the event
 * identity all live below it in solid type. Artwork is unpredictable — a dark
 * flyer, a white poster, someone's phone screenshot — and a price that is legible
 * on one is invisible on the next.
 *
 * The event title is INTER, SENTENCE CASE. Oswald is Snatch It's voice; an event
 * name is the venue's. Both first-party benchmarks set event titles at normal
 * weight next to artwork for the same reason: the poster already contains display
 * type, and a second headline reads as a mistake.
 */

import { StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { EventMedia } from '@/src/components/media/EventMedia';
import { FromAFanBadge, IconButton } from '@/src/components/ui';
import type { MediaAsset } from '@/src/lib/media/url';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

export interface ListingHeroProps {
  asset: MediaAsset;
  eventName: string;
  venue: string;
  /** Already formatted for display by the caller. */
  whenLabel: string;
  neighborhood?: string | null;
  onBack: () => void;
  /** Omitted for the seller's own listing: there is no point reporting yourself. */
  onOverflow?: () => void;
}

export function ListingHero({
  asset,
  eventName,
  venue,
  whenLabel,
  neighborhood,
  onBack,
  onOverflow,
}: ListingHeroProps) {
  // The artwork runs under the status bar on purpose — a safe-area gap above it
  // would frame the image like a card. The CONTROLS still have to clear the
  // notch, so the inset is applied to them rather than to the frame.
  const insets = useSafeAreaInsets();

  return (
    <View>
      {/*
        `fluid` measures the real laid-out width and requests a derivative at
        exactly that size. No screen width is hardcoded anywhere in this file, so
        it fits a 375pt SE and a 430pt Pro Max without a breakpoint.
      */}
      <EventMedia asset={asset} slot="EVENT_HERO" title={eventName} fluid>
        <View
          style={[styles.controls, { top: insets.top + v2.space.sm }]}
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

        {/*
          Provenance sits on the artwork because it is a label, not a decision.
          It says "From a fan" and never "Direct from event": migration 093 is not
          deployed and every native rail flag is false, so no venue-issued ticket
          exists for that claim to be true about.
        */}
        <View style={styles.badge} pointerEvents="none">
          <FromAFanBadge />
        </View>
      </EventMedia>

      <View style={styles.identity}>
        <Text style={[textStyle('title'), styles.title]} accessibilityRole="header">
          {eventName}
        </Text>
        <Text style={[textStyle('body'), styles.venue]} numberOfLines={2}>
          {venue}
          {neighborhood ? ` · ${neighborhood}` : ''}
        </Text>
        <Text style={[textStyle('bodySm'), styles.when]}>{whenLabel}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  controls: {
    position: 'absolute',
    left: v2.space.sm,
    right: v2.space.sm,
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  badge: {
    position: 'absolute',
    left: v2.space.lg,
    bottom: v2.space.lg,
  },
  identity: {
    paddingHorizontal: v2.space.lg,
    paddingTop: v2.space.lg,
    gap: v2.space.xs,
  },
  // Inter, sentence case, two lines. A long lineup name wraps rather than
  // truncating: the title is what the user came to read.
  title: { color: v2.text.primary, fontSize: 22, lineHeight: 28 },
  venue: { color: v2.text.secondary },
  when: { color: v2.text.muted },
});

/**
 * src/components/media/EventMedia.tsx — the one component that renders event artwork.
 *
 * Every event image in the product goes through this. Screens pass a slot name
 * and an asset; they never pass a width, a height, an aspect ratio or a resize
 * mode again. Those live in `src/lib/media/slots.ts`.
 *
 * WHAT IT FIXES, all of which are live defects today:
 *  - Six different container ratios crop one asset, discarding up to 58.5% of it.
 *  - Multi-megabyte originals are shipped into small cards. Now a slot-sized
 *    derivative is requested.
 *  - Dark artwork dissolves into the near-black canvas. Now every image carries a
 *    hairline edge, and any image with text over it carries a scrim.
 *  - A missing image renders as a broken image. Now it renders a branded plate.
 *  - Three lists flash the previous row's image while scrolling, because no
 *    recycling key is set. Now the URI is the key.
 *
 * FIT BEHAVIOUR
 * `cover` crops to the frame using the focal point. `fit` contains the whole
 * image and fills the remaining space with a blurred, scaled copy of the SAME
 * artwork, which is what lets a uniform grid hold a poster whose type runs to the
 * edge without cropping it and without black letterbox bars. The original artwork
 * always remains visible on top; nothing is generated or invented.
 */

import { Image } from 'expo-image';
import { memo } from 'react';
import { StyleSheet, Text, View, type ViewStyle } from 'react-native';

import {
  MEDIA_SLOTS,
  slotHeight,
  type Breakpoint,
  type MediaSlotName,
} from '@/src/lib/media/slots';
import { resolveImage, type MediaAsset } from '@/src/lib/media/url';
import { fontFamily } from '@/src/theme/fonts';
import * as v2 from '@/src/theme/v2';

export interface EventMediaProps {
  asset: MediaAsset;
  slot: MediaSlotName;
  breakpoint?: Breakpoint;
  /** Overrides the slot width. Use only for a genuinely fluid container. */
  width?: number;
  /** Used by the fallback plate and as the accessibility label. */
  title?: string;
  style?: ViewStyle;
  /** Decorative images (a backdrop behind text that repeats it) pass true. */
  decorative?: boolean;
}

/** A deterministic, brand-safe plate for when there is no renderable image. */
function FallbackPlate({ title, height }: { title?: string; height: number }) {
  const initial = (title ?? '').trim().charAt(0).toUpperCase();
  return (
    <View style={[styles.fallback, { height }]}>
      <Text
        style={[styles.fallbackInitial, { fontFamily: fontFamily('display') }]}
        // The plate is decoration; the accessible name comes from the wrapper.
        accessibilityElementsHidden
        importantForAccessibility="no"
      >
        {initial || 'S'}
      </Text>
    </View>
  );
}

function EventMediaImpl({
  asset,
  slot,
  breakpoint = 'mobile',
  width,
  title,
  style,
  decorative = false,
}: EventMediaProps) {
  const spec = MEDIA_SLOTS[slot];
  const boxWidth = width ?? spec.layoutWidth[breakpoint];
  const boxHeight = width ? Math.round(width / spec.aspectRatio) : slotHeight(slot, breakpoint);

  const resolved = resolveImage(asset, slot, { breakpoint });

  // Accessibility: artwork that duplicates adjacent text is decorative. Artwork
  // that IS the information gets a real label.
  const a11y = decorative
    ? { accessibilityElementsHidden: true, importantForAccessibility: 'no' as const }
    : {
        accessible: true,
        accessibilityRole: 'image' as const,
        accessibilityLabel: title ? `Artwork for ${title}` : 'Event artwork',
      };

  const frame: ViewStyle = {
    width: boxWidth,
    height: boxHeight,
    borderRadius: spec.radius,
    overflow: 'hidden',
    backgroundColor: v2.surface.surface,
  };

  if (resolved.kind === 'fallback') {
    return (
      <View style={[frame, styles.edge, style]} {...a11y}>
        <FallbackPlate title={title} height={boxHeight} />
      </View>
    );
  }

  const isFit = resolved.fit === 'fit';

  return (
    <View style={[frame, styles.edge, style]} {...a11y}>
      {/*
        The `fit` backdrop: a heavily blurred copy of the same artwork filling the
        slack, so a portrait poster in a landscape frame never shows black bars.
        `cover` needs no backdrop because the image already fills the frame.
      */}
      {isFit ? (
        <Image
          source={{ uri: resolved.backdropUri }}
          style={StyleSheet.absoluteFill}
          contentFit="cover"
          blurRadius={54}
          cachePolicy="memory-disk"
          recyclingKey={`${resolved.backdropUri}:bg`}
          accessibilityElementsHidden
          importantForAccessibility="no"
          transition={0}
        />
      ) : null}

      <Image
        source={{ uri: resolved.uri }}
        style={StyleSheet.absoluteFill}
        contentFit={isFit ? 'contain' : 'cover'}
        // Focal point: keeps the subject rather than the geometric centre.
        contentPosition={{
          left: `${Math.round(resolved.focal.x * 100)}%`,
          top: `${Math.round(resolved.focal.y * 100)}%`,
        }}
        // Prevents the stale-image flash when a list row is recycled.
        recyclingKey={resolved.uri}
        cachePolicy="memory-disk"
        transition={v2.motion.swift}
        priority={spec.preload ? 'high' : 'normal'}
        accessibilityElementsHidden
        importantForAccessibility="no"
      />

      {/*
        Scrim. Only where text sits on the artwork. Without it, nightlife
        photography (which is dark) makes white text unreadable at the top and
        bright artwork makes it vanish at the bottom.
      */}
      {spec.scrim !== 'none' ? (
        <View
          style={[
            StyleSheet.absoluteFill,
            spec.scrim === 'strong' ? styles.scrimStrong : styles.scrimBottom,
          ]}
          pointerEvents="none"
        />
      ) : null}
    </View>
  );
}

export const EventMedia = memo(EventMediaImpl);

const styles = StyleSheet.create({
  /**
   * A hairline edge so a dark image does not dissolve into the black canvas.
   * Neutral rather than red: over artwork a red hairline fights the image.
   */
  edge: {
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: v2.border.overArt,
  },
  fallback: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: v2.surface.surface,
  },
  fallbackInitial: {
    fontSize: 32,
    color: 'rgba(255,255,255,0.20)',
  },
  /*
   * Approximated with a stacked translucent block rather than a gradient, because
   * a gradient needs expo-linear-gradient and this pass does not add dependencies.
   * The gradient is specified in EVENT_MEDIA_SYSTEM.md and should replace this
   * when the dependency lands.
   */
  scrimBottom: {
    backgroundColor: 'rgba(0,0,0,0.28)',
  },
  scrimStrong: {
    backgroundColor: 'rgba(0,0,0,0.45)',
  },
});

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
import { memo, useState, type ReactNode } from 'react';
import {
  PixelRatio,
  StyleSheet,
  Text,
  View,
  type LayoutChangeEvent,
  type ViewStyle,
} from 'react-native';

import { MEDIA_SLOTS, type Breakpoint, type MediaSlotName } from '@/src/lib/media/slots';
import { resolveImage, type MediaAsset } from '@/src/lib/media/url';
import { fontFamily } from '@/src/theme/fonts';
import * as v2 from '@/src/theme/v2';

export interface EventMediaProps {
  asset: MediaAsset;
  slot: MediaSlotName;
  breakpoint?: Breakpoint;
  /**
   * The width this instance is ACTUALLY laid out at, in points.
   *
   * The slot's own `layoutWidth` is a REFERENCE, not a layout: the hero slots
   * carry a nominal 390, which overflows a 375pt iPhone SE and under-fills a
   * 430pt Pro Max. Pass a measured width, or set `fluid` and let this component
   * measure itself.
   */
  width?: number;
  /**
   * Fill the parent's width and derive the height from the slot ratio, measuring
   * the real width before any image is requested. This is the correct mode for
   * anything full-bleed or grid-sized, and it is why no screen has to know a
   * device width.
   */
  fluid?: boolean;
  /** Used by the fallback plate and as the accessibility label. */
  title?: string;
  style?: ViewStyle;
  /** Decorative images (a backdrop behind text that repeats it) pass true. */
  decorative?: boolean;
  /**
   * Content layered over the artwork, inside the frame and above the scrim —
   * a title over a hero, a badge in a corner.
   *
   * The layer is `box-none`, so it never swallows a touch that belongs to the
   * card underneath; a child that wants a press must be pressable itself. This
   * component still owns media presentation only. If you find yourself passing an
   * event's information architecture in here, build a card component instead.
   */
  children?: ReactNode;
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
  fluid = false,
  title,
  style,
  decorative = false,
  children,
}: EventMediaProps) {
  const spec = MEDIA_SLOTS[slot];

  // Fluid frames measure themselves. Nothing is requested until the real width is
  // known, because requesting the slot's nominal width and then laying out at a
  // different one is the defect this mode exists to remove.
  const [measured, setMeasured] = useState<number | null>(null);
  const onLayout = (e: LayoutChangeEvent) => {
    const w = Math.round(e.nativeEvent.layout.width);
    if (w > 0 && w !== measured) setMeasured(w);
  };

  const resolvedWidth = fluid ? measured : (width ?? spec.layoutWidth[breakpoint]);

  if (fluid && resolvedWidth == null) {
    // One frame, at the right shape, before the width is known. It holds the exact
    // geometry the image will occupy, so nothing shifts when the image arrives.
    return (
      <View
        onLayout={onLayout}
        style={[
          styles.edge,
          {
            width: '100%',
            aspectRatio: spec.aspectRatio,
            borderRadius: spec.radius,
            overflow: 'hidden',
            backgroundColor: v2.surface.surface,
          },
          style,
        ]}
        accessibilityElementsHidden
        importantForAccessibility="no"
      />
    );
  }

  const boxWidth = resolvedWidth as number;
  const boxHeight = Math.round(boxWidth / spec.aspectRatio);

  const resolved = resolveImage(asset, slot, {
    breakpoint,
    // The real laid-out width and the real screen density, so the request
    // matches the box instead of the slot default.
    layoutWidth: boxWidth,
    devicePixelRatio: PixelRatio.get(),
  });

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
    // Fluid frames keep a percentage width so they reflow on rotation; the
    // measured width still drives the pixel request above.
    width: fluid ? '100%' : boxWidth,
    height: boxHeight,
    borderRadius: spec.radius,
    overflow: 'hidden',
    backgroundColor: v2.surface.surface,
  };

  if (resolved.kind === 'fallback') {
    return (
      <View style={[frame, styles.edge, style]} onLayout={fluid ? onLayout : undefined} {...a11y}>
        <FallbackPlate title={title} height={boxHeight} />
        {children ? (
          <View style={StyleSheet.absoluteFill} pointerEvents="box-none">
            {children}
          </View>
        ) : null}
      </View>
    );
  }

  const isFit = resolved.fit === 'fit';

  return (
    <View style={[frame, styles.edge, style]} onLayout={fluid ? onLayout : undefined} {...a11y}>
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
            styles.scrimBase,
            spec.scrim === 'strong' ? styles.scrimStrong : styles.scrimBottom,
          ]}
          pointerEvents="none"
        />
      ) : null}

      {/*
        The content layer. Above the scrim — which is the whole reason the scrim
        exists — and `box-none`, so it never intercepts a touch meant for the row
        this artwork sits in.
      */}
      {children ? (
        <View style={StyleSheet.absoluteFill} pointerEvents="box-none">
          {children}
        </View>
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
  scrimBase: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
  },
  fallbackInitial: {
    fontSize: 32,
    color: 'rgba(255,255,255,0.20)',
  },
  /*
   * A real gradient band, not a flat wash over the whole image.
   *
   * React Native 0.81 ships `experimental_backgroundImage`, so no dependency is
   * needed. A flat overlay would darken the entire artwork uniformly, which is
   * precisely what the scrim is supposed to avoid: it exists to make text legible
   * at the bottom, not to dim the picture.
   */
  scrimBottom: {
    top: '55%',
    experimental_backgroundImage:
      'linear-gradient(to bottom, rgba(0,0,0,0) 0%, rgba(0,0,0,0.78) 100%)',
  },
  scrimStrong: {
    top: '35%',
    experimental_backgroundImage:
      'linear-gradient(to bottom, rgba(0,0,0,0) 0%, rgba(0,0,0,0.88) 100%)',
  },
});

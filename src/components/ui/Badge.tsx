/**
 * src/components/ui/Badge.tsx — status and provenance badge.
 *
 * THE RULE THIS COMPONENT EXISTS TO ENFORCE: meaning is carried by a WORD, never
 * by colour alone. Colour fails for colourblind users, in screenshots, in
 * high-contrast modes, and in a photograph of a phone screen. Every variant here
 * renders text, and the text is the meaning.
 *
 * PROVENANCE, AND WHAT IS DELIBERATELY MISSING
 * Snatch It will carry venue-direct inventory and fan resale in one product, and
 * a resale ticket must never be presented as venue-issued. `marketplace` ("FROM A
 * FAN") ships now because every listing in the product today is exactly that.
 * The direct variant does NOT ship: migration 093 is not deployed and all three
 * native feature flags are false, so there is no venue-issued ticket in existence
 * for it to describe. A badge that can lie is worse than no badge.
 */

import { StyleSheet, Text, View, type ViewStyle } from 'react-native';
import { useMemo } from 'react';

import { textStyle, MAX_DISPLAY_FONT_SCALE } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

export type BadgeTone = 'neutral' | 'success' | 'warning' | 'danger' | 'count';

export interface BadgeProps {
  label: string;
  tone?: BadgeTone;
  /**
   * Drawn OVER artwork — a hero, a feature — where the canvas inks do not apply. E's finding on B's
   * Light listing render (2026-09-24): the neutral badge takes `text.primary` for its border and
   * label, which is near-black, and over the hero's dark plate it vanished in Light exactly as the
   * back control did. Over art the label takes the appearance-invariant over-artwork ink; the WORD
   * still carries the meaning, which is this component's own rule, so a status tone loses only its
   * hue there and nothing a reader needs.
   */
  onArt?: boolean;
  style?: ViewStyle;
  testID?: string;
}

function toneFor(p: Palette): Record<BadgeTone, { border: string; fill: string; text: string }> {
  return {
  neutral: { border: p.text.primary, fill: 'transparent', text: p.text.primary },
  success: { border: p.status.success, fill: 'transparent', text: p.status.success },
  warning: { border: p.status.warning, fill: 'transparent', text: p.status.warning },
  danger: { border: p.status.error, fill: 'transparent', text: p.status.error },
  // The one filled variant: a count is a quantity, not a state, and it needs to
  // be found at a glance.
  count: { border: p.brand.red, fill: p.brand.red, text: p.text.inverse },
  };
}

export function Badge({ label, tone = 'neutral', onArt = false, style, testID }: BadgeProps) {
  const { palette } = useTheme();
  const styles = useMemo(() => makeStyles(palette), [palette]);
  const base = toneFor(palette)[tone];
  // Urgency keeps its own over-art hue (the amber the palette carries for both appearances);
  // everything else reads in the over-art primary.
  const t = onArt
    ? { ...base, fill: 'transparent', border: tone === 'warning' ? palette.onArt.urgent : palette.onArt.primary, text: tone === 'warning' ? palette.onArt.urgent : palette.onArt.primary }
    : base;
  return (
    <View
      style={[styles.base, { borderColor: t.border, backgroundColor: t.fill }, style]}
      accessibilityRole="text"
      accessibilityLabel={label}
      testID={testID}
    >
      {/* V3 (pkg8 boards: "Marked sent", "Valid", "Transfer in progress"): badges read in the
          quiet mixed-case voice, rounded — not the uppercase tracked micro in a square. */}
      <Text style={[textStyle('navLabel'), { color: t.text }]} numberOfLines={1} maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}>
        {label}
      </Text>
    </View>
  );
}

/**
 * The marketplace provenance badge. A fixed string, not a prop, because the whole
 * point is that this claim is not something a call site gets to word differently.
 *
 * Copy is inherited from the brand, which says "direct" and "marketplace" to
 * customers and never says primary, secondary, rail or inventory.
 */
export function FromAFanBadge({ onArt = false, style }: { onArt?: boolean; style?: ViewStyle }) {
  return <Badge label="From a fan" tone="neutral" onArt={onArt} style={style} />;
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  base: {
    minHeight: 20,
    paddingHorizontal: v2.space.sm,
    borderRadius: v2.radius.sm,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
    alignSelf: 'flex-start',
  },
  });
}

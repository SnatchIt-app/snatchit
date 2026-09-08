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

import { textStyle, MAX_DISPLAY_FONT_SCALE } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

export type BadgeTone = 'neutral' | 'success' | 'warning' | 'danger' | 'count';

export interface BadgeProps {
  label: string;
  tone?: BadgeTone;
  style?: ViewStyle;
  testID?: string;
}

const TONE: Record<BadgeTone, { border: string; fill: string; text: string }> = {
  neutral: { border: v2.text.primary, fill: 'transparent', text: v2.text.primary },
  success: { border: v2.status.success, fill: 'transparent', text: v2.status.success },
  warning: { border: v2.status.warning, fill: 'transparent', text: v2.status.warning },
  danger: { border: v2.status.error, fill: 'transparent', text: v2.status.error },
  // The one filled variant: a count is a quantity, not a state, and it needs to
  // be found at a glance.
  count: { border: v2.brand.red, fill: v2.brand.red, text: v2.text.inverse },
};

export function Badge({ label, tone = 'neutral', style, testID }: BadgeProps) {
  const t = TONE[tone];
  return (
    <View
      style={[styles.base, { borderColor: t.border, backgroundColor: t.fill }, style]}
      accessibilityRole="text"
      accessibilityLabel={label}
      testID={testID}
    >
      <Text style={[textStyle('micro'), { color: t.text }]} numberOfLines={1} maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}>
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
export function FromAFanBadge({ style }: { style?: ViewStyle }) {
  return <Badge label="From a fan" tone="neutral" style={style} />;
}

const styles = StyleSheet.create({
  base: {
    minHeight: 20,
    paddingHorizontal: v2.space.sm,
    borderRadius: v2.radius.none,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
    alignSelf: 'flex-start',
  },
});

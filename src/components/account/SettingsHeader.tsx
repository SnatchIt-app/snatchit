/**
 * src/components/account/SettingsHeader.tsx — the account/settings screen header.
 *
 * A back button, an Oswald title, and a spacer to keep the title centred. Every
 * settings subroute wears the same header, so it lives here rather than being
 * hand-rolled nine times. Matches the Settings hub.
 */

import { router } from 'expo-router';
import { useMemo } from 'react';
import { StyleSheet, Text, useWindowDimensions, View } from 'react-native';
import { useTopInset } from '@/src/lib/nav/navInsets';
import { identityStacks } from '@/src/lib/design/featureMetrics';

import { IconButton } from '@/src/components/ui';
import { AMOUNT_MIN_FONT_SCALE, textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

export interface SettingsHeaderProps {
  title: string;
  /** Defaults to router.back(). */
  onBack?: () => void;
}

export function SettingsHeader({ title, onBack }: SettingsHeaderProps) {
  const { palette } = useTheme();
  const styles = useMemo(() => makeStyles(palette), [palette]);
  // F-SELL-2: the badge-aware top inset (status bar + the SANDBOX badge on sandbox builds; production unchanged).
  const topPad = useTopInset();
  /*
   * The title is ONE WORD, and at the largest accessibility sizes a clamped line cut it:
   * "SETTIN…", "APPEA…", "PRIVAC…" — the last of those long before this batch touched anything.
   * Letting it wrap instead produced "SETTING / S", a word split across lines, which is the same
   * fault wearing different clothes. A single word cannot break on a space, so above the shared
   * threshold it keeps its line and shrinks to fit, the treatment the amounts already use.
   * Below the threshold nothing moves.
   */
  const { fontScale } = useWindowDimensions();
  const stacked = identityStacks(fontScale);
  return (
    <View style={[styles.header, { paddingTop: topPad + v2.space.sm }]}>
      <IconButton glyph="back" onPress={onBack ?? (() => router.back())} accessibilityLabel="Back" />
      <Text
        style={[textStyle('displaySm'), styles.title]}
        accessibilityRole="header"
        numberOfLines={1}
        {...(stacked ? { adjustsFontSizeToFit: true, minimumFontScale: AMOUNT_MIN_FONT_SCALE } : null)}
      >
        {title}
      </Text>
      <View style={styles.spacer} />
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: v2.space.md,
    paddingBottom: v2.space.sm,
    borderBottomWidth: 1,
    borderBottomColor: p.border.default,
  },
  title: { color: p.text.primary, flex: 1, textAlign: 'center', marginHorizontal: v2.space.sm },
  spacer: { width: 44 },
  });
}

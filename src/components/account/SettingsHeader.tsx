/**
 * src/components/account/SettingsHeader.tsx — the account/settings screen header.
 *
 * A back button, an Oswald title, and a spacer to keep the title centred. Every
 * settings subroute wears the same header, so it lives here rather than being
 * hand-rolled nine times. Matches the Settings hub.
 */

import { router } from 'expo-router';
import { StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { IconButton } from '@/src/components/ui';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

export interface SettingsHeaderProps {
  title: string;
  /** Defaults to router.back(). */
  onBack?: () => void;
}

export function SettingsHeader({ title, onBack }: SettingsHeaderProps) {
  const insets = useSafeAreaInsets();
  return (
    <View style={[styles.header, { paddingTop: insets.top + v2.space.sm }]}>
      <IconButton glyph="back" onPress={onBack ?? (() => router.back())} accessibilityLabel="Back" />
      <Text style={[textStyle('displaySm'), styles.title]} accessibilityRole="header" numberOfLines={1}>
        {title}
      </Text>
      <View style={styles.spacer} />
    </View>
  );
}

const styles = StyleSheet.create({
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: v2.space.md,
    paddingBottom: v2.space.sm,
    borderBottomWidth: 1,
    borderBottomColor: v2.border.default,
  },
  title: { color: v2.text.primary, flex: 1, textAlign: 'center', marginHorizontal: v2.space.sm },
  spacer: { width: 44 },
});

/**
 * src/components/account/SettingsRow.tsx — the one navigation row for account
 * surfaces.
 *
 * A title, an optional compact value or description, and a chevron, over a bottom
 * hairline. No emoji, no icon tile, no rounded card — the row IS the control. One
 * treatment for every row so a Settings screen reads as a list, not a collage.
 *
 * `tone="destructive"` recolours only the title (a different red from the brand),
 * for a Sign out row that must read as destructive without a red block.
 */

import { Animated, Pressable, StyleSheet, Text, View } from 'react-native';

import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import { usePressScale } from '@/src/components/ui';

export interface SettingsRowProps {
  label: string;
  /** A compact value or one-line description shown under the label. */
  description?: string;
  /** A trailing value (e.g. a current selection) shown before the chevron. */
  value?: string;
  onPress?: () => void;
  tone?: 'default' | 'destructive';
  /** Hide the trailing chevron (e.g. a terminal action rather than navigation). */
  showChevron?: boolean;
  disabled?: boolean;
  testID?: string;
}

export function SettingsRow({
  label,
  description,
  value,
  onPress,
  tone = 'default',
  showChevron = true,
  disabled = false,
  testID,
}: SettingsRowProps) {
  const press = usePressScale(!disabled && !!onPress);
  const titleColor = tone === 'destructive' ? v2.status.error : v2.text.primary;

  return (
    <Animated.View style={press.style}>
      <Pressable
        onPress={disabled ? undefined : onPress}
        onPressIn={press.onPressIn}
        onPressOut={press.onPressOut}
        disabled={disabled || !onPress}
        style={styles.row}
        accessibilityRole="button"
        accessibilityLabel={value ? `${label}, ${value}` : label}
        accessibilityState={{ disabled }}
        testID={testID}
      >
        <View style={styles.textCol}>
          <Text style={[textStyle('title'), { color: titleColor }]} numberOfLines={1}>{label}</Text>
          {description ? (
            <Text style={[textStyle('bodySm'), styles.description]} numberOfLines={2}>{description}</Text>
          ) : null}
        </View>
        {value ? (
          <Text style={[textStyle('bodySm'), styles.value]} numberOfLines={1}>{value}</Text>
        ) : null}
        {showChevron ? <Text style={styles.chevron}>{'›'}</Text> : null}
      </Pressable>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  row: {
    minHeight: 56,
    flexDirection: 'row',
    alignItems: 'center',
    gap: v2.space.md,
    paddingVertical: v2.space.md,
    borderBottomWidth: 1,
    borderBottomColor: v2.border.default,
  },
  textCol: { flex: 1, minWidth: 0 },
  description: { color: v2.text.muted, marginTop: 2 },
  value: { color: v2.text.muted, flexShrink: 1, textAlign: 'right' },
  chevron: { color: v2.text.faint, fontSize: 22 },
});

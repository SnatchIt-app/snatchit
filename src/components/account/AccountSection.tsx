/**
 * src/components/account/AccountSection.tsx — a labelled group on an account
 * surface (Profile, Settings).
 *
 * An Oswald eyebrow over a hairline-topped stack. It replaces the rounded
 * "settings card" the account screens used to draw a box around every group: the
 * brand separates with a line and vertical rhythm, not a container.
 */

import { useMemo } from 'react';
import { StyleSheet, Text, View, type ViewStyle } from 'react-native';

import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

export interface AccountSectionProps {
  title: string;
  children: React.ReactNode;
  style?: ViewStyle;
}

export function AccountSection({ title, children, style }: AccountSectionProps) {
  const { palette } = useTheme();
  const styles = useMemo(() => makeStyles(palette), [palette]);
  return (
    <View style={[styles.wrap, style]}>
      <Text style={[textStyle('micro'), styles.label]}>{title}</Text>
      <View style={styles.group}>{children}</View>
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  wrap: { marginTop: v2.space.xl },
  label: { color: p.text.muted, marginBottom: v2.space.sm },
  group: {
    borderTopWidth: 1,
    borderTopColor: p.border.default,
  },
  });
}

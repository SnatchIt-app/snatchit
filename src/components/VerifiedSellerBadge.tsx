import { useMemo } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { fontSize, spacing } from '@/src/theme';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';

type Props = { isVerified: boolean };

export default function VerifiedSellerBadge({ isVerified }: Props) {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  if (!isVerified) return null;

  return (
    <View style={s.badge}>
      <Ionicons name="checkmark-circle" size={14} color={palette.status.info} />
      <Text style={s.text}>Verified Seller</Text>
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
    badge: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs },
    text:  { fontSize: fontSize.xs, fontWeight: '600', color: p.status.info },
  });
}

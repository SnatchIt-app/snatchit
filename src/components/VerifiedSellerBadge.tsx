import { StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { fontSize, spacing } from '@/src/theme';

type Props = { isVerified: boolean };

export default function VerifiedSellerBadge({ isVerified }: Props) {
  if (!isVerified) return null;

  return (
    <View style={s.badge}>
      <Ionicons name="checkmark-circle" size={14} color="#60a5fa" />
      <Text style={s.text}>Verified Seller</Text>
    </View>
  );
}

const s = StyleSheet.create({
  badge: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs },
  text:  { fontSize: fontSize.xs, fontWeight: '600', color: '#60a5fa' },
});

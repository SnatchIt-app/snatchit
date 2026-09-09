/**
 * src/components/listing/SellerTrustRow.tsx — who is selling this.
 *
 * This is marketplace inventory: a stranger is promising to hand over a ticket.
 * The row answers one question, "can I trust who is selling this", and then stops.
 * It is not a social profile.
 *
 * It invents nothing. There is no score, no star rating and no derived rank here.
 * The only claim it makes beyond the name is the verified badge, which the
 * database sets.
 */

import { Image } from 'expo-image';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import VerifiedSellerBadge from '@/src/components/VerifiedSellerBadge';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

export interface SellerTrustRowProps {
  displayName: string;
  avatarUrl: string | null;
  isVerified: boolean;
  onPress: () => void;
}

export function SellerTrustRow({ displayName, avatarUrl, isVerified, onPress }: SellerTrustRowProps) {
  const initial = displayName.trim().charAt(0).toUpperCase() || 'S';

  return (
    <Pressable
      onPress={onPress}
      style={styles.row}
      accessibilityRole="button"
      accessibilityLabel={`Seller ${displayName}${isVerified ? ', verified' : ''}. View profile.`}
    >
      {avatarUrl ? (
        <Image source={{ uri: avatarUrl }} style={styles.avatar} contentFit="cover" />
      ) : (
        <View style={[styles.avatar, styles.avatarFallback]}>
          <Text style={[textStyle('label'), styles.initial]}>{initial}</Text>
        </View>
      )}

      <View style={styles.text}>
        <Text style={[textStyle('micro'), styles.eyebrow]}>Seller</Text>
        <View style={styles.nameRow}>
          <Text style={[textStyle('title'), styles.name]} numberOfLines={1}>
            {displayName}
          </Text>
          <VerifiedSellerBadge isVerified={isVerified} />
        </View>
      </View>

      <Text style={styles.chevron}>{'›'}</Text>
    </Pressable>
  );
}

const AVATAR = 44;

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: v2.space.md,
    minHeight: 64,
    paddingHorizontal: v2.space.lg,
    paddingVertical: v2.space.md,
    borderTopWidth: 1,
    borderBottomWidth: 1,
    borderColor: v2.border.default,
  },
  // The one circle in the product. People are round; everything else is square.
  avatar: { width: AVATAR, height: AVATAR, borderRadius: v2.radius.pill },
  avatarFallback: {
    backgroundColor: v2.surface.elevated,
    alignItems: 'center',
    justifyContent: 'center',
  },
  initial: { color: v2.text.muted },
  text: { flex: 1, minWidth: 0, gap: 2 },
  eyebrow: { color: v2.text.muted },
  nameRow: { flexDirection: 'row', alignItems: 'center', gap: v2.space.sm },
  name: { color: v2.text.primary, flexShrink: 1 },
  chevron: { color: v2.text.muted, fontSize: 22, lineHeight: 24 },
});

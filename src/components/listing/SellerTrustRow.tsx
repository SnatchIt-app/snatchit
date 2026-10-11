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
import { useMemo } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import VerifiedSellerBadge from '@/src/components/VerifiedSellerBadge';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

export interface SellerTrustRowProps {
  displayName: string;
  avatarUrl: string | null;
  isVerified: boolean;
  onPress: () => void;
}

export function SellerTrustRow({ displayName, avatarUrl, isVerified, onPress }: SellerTrustRowProps) {
  const { palette } = useTheme();
  const styles = useMemo(() => makeStyles(palette), [palette]);
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

function makeStyles(p: Palette) {
  return StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: v2.space.md,
    minHeight: 64,
    paddingHorizontal: v2.space.lg,
    paddingVertical: v2.space.md,
    borderTopWidth: 1,
    borderBottomWidth: 1,
    borderColor: p.border.default,
  },
  // The one circle in the product. People are round; everything else is square.
  avatar: { width: AVATAR, height: AVATAR, borderRadius: v2.radius.pill },
  avatarFallback: {
    backgroundColor: p.surface.elevated,
    alignItems: 'center',
    justifyContent: 'center',
  },
  initial: { color: p.text.muted },
  text: { flex: 1, minWidth: 0, gap: 2 },
  eyebrow: { color: p.text.muted },
  nameRow: { flexDirection: 'row', alignItems: 'center', gap: v2.space.sm },
  name: { color: p.text.primary, flexShrink: 1 },
  chevron: { color: p.text.muted, fontSize: 22, lineHeight: 24 },
  });
}

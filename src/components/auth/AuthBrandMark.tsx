/**
 * src/components/auth/AuthBrandMark.tsx — the SN mark on the auth screens.
 *
 * The three auth screens each inlined this Image as a bare child of a column, so
 * the mark sat at the LEFT edge. It is now the sole child of a full-width,
 * centre-aligned row — the same construction the approved Home header uses — so
 * it is mathematically centred to the SCREEN and no sibling control can push it
 * off centre.
 *
 * Asset, size (30pt tall, intrinsic 1024x371 ratio pinned so it can never squash)
 * and the spacing beneath it are unchanged. No background, plate, wordmark or glow.
 *
 * It IS tinted, to the primary ink. The asset is white on transparent, which was
 * right while every screen was Midnight; on Daylight's white canvas an untinted
 * white monogram is invisible. The Home header tints the same asset the same way.
 */

import { Image } from 'expo-image';
import { useMemo } from 'react';
import { StyleSheet, View } from 'react-native';

import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';

const SN_MARK = require('@/brand/sn-logo-white.png');
const SN_MARK_RATIO = 1024 / 371;
const SN_MARK_HEIGHT = 30;

export function AuthBrandMark() {
  const { palette } = useTheme();
  const styles = useMemo(() => makeStyles(palette), [palette]);
  return (
    <View style={styles.row}>
      <Image
        source={SN_MARK}
        style={styles.mark}
        contentFit="contain"
        accessibilityLabel="Snatch It"
      />
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
    // Full width + centred: exact screen centring for the mark.
    row: { alignItems: 'center' },
    mark: { height: SN_MARK_HEIGHT, aspectRatio: SN_MARK_RATIO, tintColor: p.text.primary },
  });
}

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
 * and the spacing beneath it are unchanged. No background, plate, wordmark, glow
 * or tint: the asset is already white on transparent.
 */

import { Image } from 'expo-image';
import { StyleSheet, View } from 'react-native';

const SN_MARK = require('@/brand/sn-logo-white.png');
const SN_MARK_RATIO = 1024 / 371;
const SN_MARK_HEIGHT = 30;

export function AuthBrandMark() {
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

const styles = StyleSheet.create({
  // Full width + centred: exact screen centring for the mark.
  row: { alignItems: 'center' },
  mark: { height: SN_MARK_HEIGHT, aspectRatio: SN_MARK_RATIO },
});

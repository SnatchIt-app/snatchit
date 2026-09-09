/**
 * src/components/discovery/DiscoveryGridSkeleton.tsx — the feed, before it loads.
 *
 * It mirrors the real grid exactly: same two columns, same 4:5 frame, same three
 * text lines. That is the point of a skeleton — when the data arrives nothing
 * moves. A centred spinner over an empty black screen tells the user nothing
 * about what is coming.
 */

import { StyleSheet, View } from 'react-native';

import { Skeleton } from '@/src/components/ui';
import * as v2 from '@/src/theme/v2';

export function DiscoveryGridSkeleton({ rows = 3 }: { rows?: number }) {
  return (
    <View style={styles.grid} accessibilityElementsHidden importantForAccessibility="no-hide-descendants">
      {Array.from({ length: rows * 2 }).map((_, i) => (
        <View key={i} style={styles.cell}>
          <Skeleton aspectRatio={v2.ratio.portrait} />
          <Skeleton height={16} style={styles.line} />
          <Skeleton height={12} width="70%" style={styles.lineTight} />
          <Skeleton height={12} width="45%" style={styles.lineTight} />
        </View>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  grid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    paddingHorizontal: v2.space.lg,
    gap: v2.space.lg,
  },
  // Two up, matching the real grid's column maths.
  cell: { width: '47%' },
  line: { marginTop: v2.space.sm },
  lineTight: { marginTop: 6 },
});

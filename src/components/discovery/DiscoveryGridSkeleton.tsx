/**
 * src/components/discovery/DiscoveryGridSkeleton.tsx — a feed, before it loads.
 *
 * It mirrors the real content exactly: the same frames, in the same places, at the same sizes.
 * That is the point of a skeleton — when the data arrives nothing moves. A centred spinner over an
 * empty black screen tells the user nothing about what is coming.
 *
 * THREE SHAPES, because the surfaces this stands in for are not one shape. Home paints a full-bleed
 * feature poster above §3 rows and Search paints rows only; the two-up card grid is DiscoveryCard's
 * geometry. Both screens were drawing the GRID here, which was already the wrong geometry and
 * became visibly wrong under the 4:5 poster direction (owner 2026-09-24): the feature it stands in
 * for is now ~491pt tall on a 393pt screen, so a two-up grid in its place moves the whole page on
 * arrival. Callers say which shape is coming, because only they know.
 *
 * Every poster box here is DERIVED — the frame ratios and radii are read from MEDIA_SLOTS, and the
 * row poster's pair from featureMetrics, the same pair FeedRow hands to EventMedia. No ratio, no
 * radius and no poster edge is typed in this file, so a slot change reaches the placeholder without
 * anyone editing it.
 */

import { StyleSheet, View } from 'react-native';

import { Skeleton } from '@/src/components/ui';
import { ROW_ART, ROW_ART_GAP, ROW_ART_W, ROW_GUTTER } from '@/src/lib/design/featureMetrics';
import { ROW_META_CLEARANCE } from '@/src/lib/design/rowMetrics';
import { MEDIA_SLOTS } from '@/src/lib/media/slots';
import * as v2 from '@/src/theme/v2';

/**
 * `grid` — the two-up DiscoveryCard grid. `rows` — §3 feed/search rows (Search, and any of Home's
 * lazy datasets, which never feature a row that cannot be bought). `feature-then-rows` — Home's
 * live feed, whose first item is the full-bleed feature.
 */
export type DiscoverySkeletonShape = 'grid' | 'rows' | 'feature-then-rows';

export function DiscoveryGridSkeleton({
  rows = 3,
  shape = 'grid',
}: {
  rows?: number;
  shape?: DiscoverySkeletonShape;
}) {
  if (shape === 'grid') {
    return (
      <View style={styles.grid} accessibilityElementsHidden importantForAccessibility="no-hide-descendants">
        {Array.from({ length: rows * 2 }).map((_, i) => (
          <View key={i} style={styles.cell}>
            {/* The card's own frame, read from its slot: the ratio fills the measured column and
                the radius matches the frame EventMedia will draw in the same place. */}
            <Skeleton aspectRatio={MEDIA_SLOTS.DISCOVERY_CARD.aspectRatio} style={styles.cardArt} />
            <Skeleton height={16} style={styles.line} />
            <Skeleton height={12} width="70%" style={styles.lineTight} />
            <Skeleton height={12} width="45%" style={styles.lineTight} />
          </View>
        ))}
      </View>
    );
  }

  return (
    <View accessibilityElementsHidden importantForAccessibility="no-hide-descendants">
      {shape === 'feature-then-rows' ? (
        // Edge to edge, at the feature slot's ratio — so the placeholder is the poster the screen
        // is about to paint, not the landscape band the retired formula used to give it. The radius
        // is the slot's 0, which is what full-bleed means here.
        <Skeleton aspectRatio={MEDIA_SLOTS.HOME_FEATURE_V3.aspectRatio} style={styles.featureArt} />
      ) : null}
      {Array.from({ length: rows }).map((_, i) => (
        <View key={i} style={styles.row}>
          {/* The row poster: the approved ROW_ART is the HEIGHT and featureMetrics derives the
              width from it, exactly as FeedRow does. */}
          <Skeleton width={ROW_ART_W} height={ROW_ART} style={styles.rowArt} />
          {/* The three line boxes stand in for type, which no constant owns and which a skeleton
              can only approximate. The poster box, the gutter, the gap and the clearance below are
              the real row's, to the point. */}
          <View style={styles.rowText}>
            <Skeleton height={16} />
            <Skeleton height={12} width="70%" style={styles.lineTight} />
            <Skeleton height={12} width="45%" style={styles.lineTight} />
          </View>
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
  // The frames' radii are their slots', read rather than typed — including the feature's 0.
  cardArt: { borderRadius: MEDIA_SLOTS.DISCOVERY_CARD.radius },
  featureArt: { borderRadius: MEDIA_SLOTS.HOME_FEATURE_V3.radius, marginBottom: v2.space.md },
  rowArt: { borderRadius: MEDIA_SLOTS.FEED_ROW_ART.radius },
  /*
   * The §3 row as FeedRow composes it: the 20pt gutter, the poster, the 12pt gap, then the text
   * column — which lands the text at ROW_TEXT_X without this file typing 82.
   *
   * The space below a row is the real row's ROW_META_CLEARANCE plus the 10pt the list's divider
   * carries under itself. The divider's own hairline is not drawn: a skeleton stands in for
   * content, and a rule that appears before the data does would be chrome inventing itself.
   */
  row: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    paddingHorizontal: ROW_GUTTER,
    gap: ROW_ART_GAP,
    paddingBottom: ROW_META_CLEARANCE + 10,
  },
  rowText: { flex: 1 },
});

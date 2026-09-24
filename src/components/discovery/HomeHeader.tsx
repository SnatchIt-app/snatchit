/**
 * src/components/discovery/HomeHeader.tsx — the top of the feed.
 *
 * Compact on purpose. The original header was a 56pt hardcoded top pad, a 28pt wordmark and a
 * tagline, which cost roughly a fifth of the screen before a single event appeared.
 *
 * V3 LAYOUT (owner 2026-09-24, on `pkg8-home-dark.png` / `pkg8-home-light.png`). The approved
 * header is ONE line: the SN mark LEFT-ALIGNED to the 20pt gutter, the search control right.
 * That supersedes the previous revision's composition — the mark centred to the screen on its own
 * line with the market label and search on a second line below it — which the owner's finding
 * names as the V2 shape Home had retained.
 *
 * WHAT WENT WITH IT. The MIAMI market label is not on the approved boards and is not drawn. Its
 * source of truth (`src/lib/market/currentMarket`) is untouched and the moment the product has a
 * place for it again it reads the same value; this component simply stopped being that place.
 *
 * SIZE. Measured off the dark board (the light board renders the mark UNTINTED, so it is white on
 * white and invisible there — a defect in the board, not a design): the monogram's ink is 39 × 13
 * points. The asset carries ~10% transparent padding, so the rendered box is 15pt tall and the
 * pinned aspect ratio does the rest. It is a navigation brand mark sitting on a line with a
 * control, not a hero graphic.
 *
 * Brand mark: the official white "SN" monogram, `brand/sn-logo-white.png`, rendered directly on
 * the canvas — no plate, no border, no container — and tinted to the primary ink, because the
 * asset is white on transparent and a white monogram is invisible on Daylight's white canvas.
 *
 * THE FILTER CONTROL (B's H1 at pin 911f65fd; owner's placement ruling 2026-09-24). Home used to
 * carry three quick controls on a floating row between this header and the feature. B's finding is
 * that the row "is not in the approved Home composition at all" — the board goes header → section
 * heading → feature — and the owner's ruling is that the functionality must survive the correction.
 * So the three collapse into one control on THIS line, beside search: the whole taxonomy already
 * lived in the sheet it opens, and `your_scene` and price joined it there. It carries the count of
 * every active filter, so a filtered feed can never look unfiltered.
 *
 * THE ARRANGEMENT (the owner's acceptance terms, 2026-09-24): "an always-visible, visually quiet
 * Filters icon beside the separate Search control… show the active-filter count when applicable… do
 * not hide the only filter entry point when no filters are active", with the caution that "a search
 * glyph must not unexpectedly become a Filters action".
 *
 * So: two controls of equal weight on the header's right, with DIFFERENT marks and different
 * destinations — the magnifier LEAVES for the Search screen; the filter mark opens the sheet in
 * place, over the feed the shopper is already reading. Neither is a bordered pill. The filter mark
 * carries a small count when filters are applied and speaks the number in its name; at zero it is
 * the same control, undecorated, so the entry point never disappears.
 */

import { useMemo } from 'react';
import { Image, StyleSheet, View } from 'react-native';

import { IconButton } from '@/src/components/ui';
import { ROW_GUTTER } from '@/src/lib/design/featureMetrics';
import { useTopInset } from '@/src/lib/nav/navInsets';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

// The official SN mark. Intrinsic 1024×371; the aspect ratio is pinned in the
// style so the geometry can never be squashed regardless of the rendered height.
const SN_MARK = require('@/brand/sn-logo-white.png');
const SN_MARK_RATIO = 1024 / 371;
/** The board's 13pt ink, plus the asset's own transparent padding. */
const SN_MARK_HEIGHT = 15;
/**
 * EXPLICIT width, not `aspectRatio`. react-native-web does not apply aspectRatio to an Image
 * whose other dimension is fixed — the element fell back to its intrinsic 1024px, which shoved
 * the search control off the right edge of the screen (verified in the rendering harness,
 * 2026-09-24). Native honours both; the computed value is identical there.
 */
const SN_MARK_WIDTH = Math.round(SN_MARK_HEIGHT * SN_MARK_RATIO);

export function HomeHeader({
  onSearch,
  onFilters,
  filterCount = 0,
}: {
  onSearch: () => void;
  /** Opens the filter sheet. Omitted by any caller that has no filters to offer. */
  onFilters?: () => void;
  /** How many filters are currently applied. Drawn on the control only when it is above zero. */
  filterCount?: number;
}) {
  const { palette } = useTheme();
  const styles = useMemo(() => makeStyles(palette), [palette]);
  // The real inset, not a guessed 56. Every tab screen in this app hardcoded it.
  const topPad = useTopInset();

  return (
    <View style={[styles.header, { paddingTop: topPad }]}>
      {/* One line: mark left, controls right. Decorative mark — it is a brand
          mark with no interaction, and announcing it on every Home visit is noise. */}
      <View style={styles.row}>
        <Image
          source={SN_MARK}
          style={styles.mark}
          resizeMode="contain"
          accessibilityElementsHidden
          importantForAccessibility="no"
        />
        <View style={styles.controls}>
          {onFilters ? (
            <IconButton
              glyph="filter"
              // Spoken with the number, because the badge is decorative: "Filters, 2 active".
              accessibilityLabel={filterCount > 0 ? `Filters, ${filterCount} active` : 'Filters'}
              count={filterCount}
              onPress={onFilters}
            />
          ) : null}
          <IconButton glyph="search" accessibilityLabel="Search events" onPress={onSearch} />
        </View>
      </View>
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  // The board's header sits on the same 20pt gutter the feed rows and the feature's
  // overlaid text use, so the mark lines up with every title below it.
  header: {
    paddingHorizontal: ROW_GUTTER,
  },
  // Mark left, control right, on one baseline — the approved V3 header.
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  mark: { height: SN_MARK_HEIGHT, width: SN_MARK_WIDTH, tintColor: p.text.primary },
  // Filters then search, in that reading order, with the boards' small gap between controls.
  controls: { flexDirection: 'row', alignItems: 'center', gap: v2.space.sm },
  });
}

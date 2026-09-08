/**
 * src/components/discovery/HomeHeader.tsx — the top of the feed.
 *
 * Compact on purpose. The old header was a 56pt hardcoded top pad, a 28pt
 * wordmark and a tagline, which cost roughly a fifth of the screen before a
 * single event appeared.
 *
 * Brand mark: the official white "SN" monogram, `brand/sn-logo-white.png`,
 * rendered directly on the black header — no plate, no border, no container, and
 * no tint, because the asset is already white on transparent. It replaces the
 * "Snatch It" wordmark (owner request). This is a navigation brand mark, not a
 * hero graphic, so it is sized to sit on the header line with the search control.
 *
 * LAYOUT (owner revision): the SN mark is CENTRED TO THE SCREEN on its own line,
 * so nothing on the right can push it off centre — it is the only child of a
 * full-width, centre-aligned row, which is exact centring without an absolute
 * overlay. The market label sits below it on the left and the search control on
 * the right, preserving the previous size, treatment and spacing of both.
 *
 * The city label is the CURRENT MARKET, read from src/lib/market/currentMarket.
 * It is the single visible city label in this area; when markets become
 * switchable it updates from MIAMI to the selected city with no header change.
 */

import { Image, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { IconButton } from '@/src/components/ui';
import { useCurrentMarket } from '@/src/lib/market/currentMarket';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

// The official SN mark. Intrinsic 1024×371; the aspect ratio is pinned in the
// style so the geometry can never be squashed regardless of the rendered height.
const SN_MARK = require('@/brand/sn-logo-white.png');
const SN_MARK_RATIO = 1024 / 371;
const SN_MARK_HEIGHT = 24;

export function HomeHeader({ onSearch }: { onSearch: () => void }) {
  // The real inset, not a guessed 56. Every tab screen in this app hardcoded it.
  const insets = useSafeAreaInsets();
  const market = useCurrentMarket();

  return (
    <View style={[styles.header, { paddingTop: insets.top + v2.space.sm }]}>
      {/* The mark is alone on this full-width, centre-aligned line, so it is
          centred to the SCREEN — the search control below cannot displace it.
          Decorative: it is a brand mark with no interaction, and announcing it
          on every Home visit is noise. */}
      <View style={styles.markRow}>
        <Image
          source={SN_MARK}
          style={styles.mark}
          resizeMode="contain"
          accessibilityElementsHidden
          importantForAccessibility="no"
        />
      </View>

      <View style={styles.metaRow}>
        <Text
          style={[textStyle('micro'), styles.place]}
          accessibilityLabel={`Current market: ${market.label}`}
        >
          {market.label}
        </Text>
        <IconButton glyph="search" accessibilityLabel="Search events" onPress={onSearch} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  header: {
    paddingHorizontal: v2.space.lg,
    paddingBottom: v2.space.md,
  },
  // Full width + centred: exact screen centring for the mark.
  markRow: { alignItems: 'center' },
  mark: { height: SN_MARK_HEIGHT, aspectRatio: SN_MARK_RATIO },
  // The market label keeps its previous 4pt offset under the mark.
  metaRow: {
    marginTop: 4,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  place: { color: v2.brand.red },
});

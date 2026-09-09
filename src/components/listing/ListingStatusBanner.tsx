/**
 * src/components/listing/ListingStatusBanner.tsx — the ONE status row.
 *
 * It replaces five stacked banner rows. The old screen could render SOLD, a
 * "transfer loading, tap to refresh" hint, a transfer action button, an Owner
 * Actions block and a reservation notice all at once, above the artwork, which
 * pushed the image off the first screen and left the user to work out which of
 * the five mattered. `detailState()` now picks exactly one.
 *
 * Tone is carried by a hairline and a label colour, and the label is always a
 * WORD. A user who cannot distinguish the tones still reads "Sold" or "You won".
 */

import { StyleSheet, Text, View } from 'react-native';

import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import type { ListingStatus, StatusTone } from '@/src/lib/listing/detailState';

const TONE: Record<StatusTone, string> = {
  brand: v2.brand.red,
  success: v2.status.success,
  warning: v2.status.warning,
  danger: v2.status.error,
  neutral: v2.text.muted,
};

export function ListingStatusBanner({ status }: { status: ListingStatus | null }) {
  if (!status) return null;
  const color = TONE[status.tone];

  return (
    <View
      style={[styles.row, { borderLeftColor: color }]}
      accessibilityRole="text"
      // Read as one sentence rather than two fragments.
      accessibilityLabel={status.detail ? `${status.label}. ${status.detail}` : status.label}
    >
      <Text style={[textStyle('label'), { color }]} numberOfLines={1}>
        {status.label}
      </Text>
      {status.detail ? (
        <Text style={[textStyle('bodySm'), styles.detail]}>{status.detail}</Text>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  row: {
    paddingVertical: v2.space.md,
    paddingHorizontal: v2.space.lg,
    // A 2pt edge instead of a filled block: the status informs, it does not
    // shout, and it never competes with the artwork below it.
    borderLeftWidth: 2,
    backgroundColor: v2.surface.surface,
    gap: 2,
  },
  detail: { color: v2.text.secondary },
});

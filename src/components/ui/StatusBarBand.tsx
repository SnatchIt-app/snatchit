/**
 * src/components/ui/StatusBarBand.tsx — an opaque canvas band over the status-bar area.
 *
 * For a screen whose scroll view runs to the top of the screen with its navigation row INSIDE the
 * scroll (the listing): once that row scrolls away, nothing covers the clock, and build 28's scrolled
 * listing frames drew poster type and the listing's own text under it. Render it AFTER the scroll
 * view so it draws over what scrolls beneath; a toast with a zIndex still draws above it.
 *
 * It is an overlay, not spacing — it moves nothing. Its height is the same badge-aware inset the
 * hero's navigation row pads by, so at rest it covers only canvas. It owns that inset itself, so the
 * screens that host it still pay no top inset of their own (sandbox-header-inset's doubled-spacing
 * rule).
 */
import { View } from 'react-native';

import { useTopInset } from '@/src/lib/nav/navInsets';
import { useTheme } from '@/src/theme/appearance';

export function StatusBarBand() {
  const { palette } = useTheme();
  const height = useTopInset();
  return (
    <View
      pointerEvents="none"
      style={{ position: 'absolute', top: 0, left: 0, right: 0, height, backgroundColor: palette.surface.canvas }}
    />
  );
}

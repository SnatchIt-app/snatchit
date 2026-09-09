/**
 * src/components/ui/StickyBar.tsx — the bottom action bar.
 *
 * Price on the left, one primary action on the right, pinned above the home
 * indicator. This is the component the Jul 29 App Review screenshots were about:
 * a flex:1 price column crushed the amount into a vertical letter-stack on a
 * narrow phone.
 *
 * SO THE NARROW CASE IS STRUCTURAL, NOT A BREAKPOINT. Below `STACK_WIDTH` the bar
 * stacks — price on its own row, full-width action beneath — and it reads the real
 * window width rather than testing for a device. There is no iPhone dimension
 * anywhere in this file.
 */

import { StyleSheet, View, useWindowDimensions, type ViewStyle } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import * as v2 from '@/src/theme/v2';

/**
 * Below this, a price and a button cannot share a row without one of them being
 * squeezed. Derived from the layout, not from a device: gutters (32) + the
 * narrowest readable price column (150) + a button that still fits its label (170).
 */
export const STACK_WIDTH = 352;

export interface StickyBarProps {
  /** The price block. Keep it to one line; `PriceDisplay` guarantees that. */
  left?: React.ReactNode;
  /** The primary action, and nothing else. One bar, one decision. */
  children: React.ReactNode;
  style?: ViewStyle;
  testID?: string;
}

export function StickyBar({ left, children, style, testID }: StickyBarProps) {
  const insets = useSafeAreaInsets();
  const { width } = useWindowDimensions();
  const stacked = width < STACK_WIDTH;

  return (
    <View
      testID={testID}
      style={[
        styles.bar,
        stacked && styles.barStacked,
        // The home indicator is not a design decision, it is a fact about the
        // device. Every tab screen in this app currently hardcodes 56pt of top
        // padding and ignores the equivalent at the bottom.
        { paddingBottom: v2.space.md + insets.bottom },
        style,
      ]}
    >
      {left ? <View style={stacked ? styles.leftStacked : styles.left}>{left}</View> : null}
      <View style={stacked ? styles.actionsStacked : styles.actions}>{children}</View>
    </View>
  );
}

const styles = StyleSheet.create({
  bar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: v2.space.md,
    paddingHorizontal: v2.space.lg,
    paddingTop: v2.space.md,
    backgroundColor: v2.surface.surface,
    borderTopWidth: 1,
    borderTopColor: v2.border.strong,
  },
  barStacked: { flexDirection: 'column', alignItems: 'stretch', gap: v2.space.sm },
  // minWidth 0 so a long price shrinks instead of pushing the action off the bar.
  left: { flex: 1, minWidth: 0 },
  leftStacked: { alignSelf: 'stretch' },
  actions: { flexShrink: 0, flexDirection: 'row', gap: v2.space.sm },
  actionsStacked: { alignSelf: 'stretch', flexDirection: 'row', gap: v2.space.sm },
});

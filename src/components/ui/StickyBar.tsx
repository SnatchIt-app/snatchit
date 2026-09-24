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
 *
 * V3 (owner 2026-09-24, pkg8 listing board). `layout="stack"` is the board's footer:
 * full-width pill actions in a COLUMN at any width, on the canvas and without a rule,
 * each carrying its own sub-line INSIDE the pill (`BarAction`). It exists because the
 * horizontal `actions` row could only ever hold one control plus a label before it
 * clipped — the listing screen was pushing two actions and two sub-lines through it.
 */

import { StyleSheet, Text, View, useWindowDimensions, type ViewStyle } from 'react-native';
import { useMemo } from 'react';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { useKeyboardUp } from '@/src/hooks/useKeyboardUp';
import { stickyBottomPadding } from '@/src/lib/nav/keyboardLift';

import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import { textStyle, MAX_DISPLAY_FONT_SCALE } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

import { Button } from './Button';

/**
 * Below this, a price and a button cannot share a row without one of them being
 * squeezed. Derived from the layout, not from a device: gutters (32) + the
 * narrowest readable price column (150) + a button that still fits its label (170).
 */
export const STACK_WIDTH = 352;

/**
 * `row` is the V2 bar (price left, action right, stacking only when the window is too
 * narrow to hold both). `stack` is the V3 board footer: a column of full-width actions
 * on the canvas, at every width.
 */
export type StickyBarLayout = 'row' | 'stack';

export interface StickyBarProps {
  /** The price block. Keep it to one line; `PriceDisplay` guarantees that. */
  left?: React.ReactNode;
  /** The primary action, and nothing else. One bar, one decision. */
  children: React.ReactNode;
  layout?: StickyBarLayout;
  style?: ViewStyle;
  testID?: string;
}

export function StickyBar({ left, children, layout = 'row', style, testID }: StickyBarProps) {
  const { palette } = useTheme();
  const styles = useMemo(() => makeStyles(palette), [palette]);
  const insets = useSafeAreaInsets();
  const keyboardUp = useKeyboardUp();
  const { width } = useWindowDimensions();
  const column = layout === 'stack';
  const stacked = column || width < STACK_WIDTH;

  return (
    <View
      testID={testID}
      style={[
        styles.bar,
        stacked && styles.barStacked,
        column && styles.barCanvas,
        // The home indicator is not a design decision, it is a fact about the
        // device. Every tab screen in this app currently hardcodes 56pt of top
        // padding and ignores the equivalent at the bottom.
        // F-SELL-1: under a keyboard the home indicator is covered, so only the bar's own padding remains.
        { paddingBottom: stickyBottomPadding({ keyboardUp, insetBottom: insets.bottom, base: v2.space.md }) },
        style,
      ]}
    >
      {left ? <View style={stacked ? styles.leftStacked : styles.left}>{left}</View> : null}
      <View style={column ? styles.actionsColumn : stacked ? styles.actionsStacked : styles.actions}>
        {children}
      </View>
    </View>
  );
}

/**
 * The V3 pill action, with its sub-line INSIDE it (owner 2026-09-24, pkg8 listing board).
 *
 * IT IS THE ONE BUTTON, NOT A SECOND ONE. `Button` renders the control — its fill, its press
 * response, its disabled treatment, its pending label and its accessibility role all come from
 * there, unchanged. This adds room at the bottom of that pill and paints the sub-line into it,
 * hidden from the accessibility tree because the sentence is already on the control as its hint.
 *
 * A SUB-LINE IS NOT A STATE EXPLANATION. Only a live action's sub-line belongs in here: a
 * disabled control dims to 0.4, which is right for a control and wrong for the sentence that
 * says why a listing is unavailable. Those stay outside the pill at full strength, which is
 * where `ListingDetailScreen` renders them.
 */
export interface BarActionProps {
  label: string;
  /** One quiet line under the label, inside the pill. Informational — never what the tap submits. */
  subLabel?: string;
  variant?: 'primary' | 'secondary';
  disabled?: boolean;
  loading?: boolean;
  pendingLabel?: string;
  onPress?: () => void;
  testID?: string;
}

/** Pill geometry, from the tokens rather than from the board's pixels: pad, label, sub-line, pad. */
const SUB_PAD = v2.space.xs;
const SUB_LINE = v2.type.bodySm.lineHeight;
const TALL = SUB_PAD * 2 + v2.type.action.lineHeight + SUB_LINE;

export function BarAction({
  label,
  subLabel,
  variant = 'primary',
  disabled = false,
  loading = false,
  pendingLabel,
  onPress,
  testID,
}: BarActionProps) {
  const { palette } = useTheme();
  const styles = useMemo(() => makeStyles(palette), [palette]);

  return (
    <View style={styles.action}>
      <Button
        label={label}
        variant={variant}
        size="lg"
        block
        disabled={disabled}
        loading={loading}
        pendingLabel={pendingLabel}
        onPress={onPress}
        // The sub-line is read as the control's hint, so a screen reader hears the minimum or
        // the consequence without the sentence becoming a second focusable element.
        accessibilityHint={subLabel}
        style={subLabel ? styles.actionTall : undefined}
        testID={testID}
      />
      {subLabel ? (
        <View
          style={[styles.sub, disabled && styles.subDim]}
          pointerEvents="none"
          accessibilityElementsHidden
          importantForAccessibility="no-hide-descendants"
        >
          <Text
            style={[textStyle('bodySm'), variant === 'primary' ? styles.subOnFill : styles.subOnCanvas]}
            numberOfLines={1}
            maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}
          >
            {subLabel}
          </Text>
        </View>
      ) : null}
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  bar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: v2.space.md,
    paddingHorizontal: v2.space.lg,
    paddingTop: v2.space.md,
    backgroundColor: p.surface.surface,
    borderTopWidth: 1,
    borderTopColor: p.border.strong,
  },
  barStacked: { flexDirection: 'column', alignItems: 'stretch', gap: v2.space.sm },
  // The V3 footer sits ON the page (board: no rule, no raised panel) — the actions carry the
  // separation themselves. The bar is still opaque, so scrolled content passes cleanly under it.
  barCanvas: { backgroundColor: p.surface.canvas, borderTopWidth: 0 },
  // minWidth 0 so a long price shrinks instead of pushing the action off the bar.
  left: { flex: 1, minWidth: 0 },
  leftStacked: { alignSelf: 'stretch' },
  actions: { flexShrink: 0, flexDirection: 'row', gap: v2.space.sm },
  actionsStacked: { alignSelf: 'stretch', flexDirection: 'row', gap: v2.space.sm },
  actionsColumn: { alignSelf: 'stretch', flexDirection: 'column', gap: v2.space.md },

  action: { alignSelf: 'stretch' },
  // minHeight, not height: at large Dynamic Type the label grows the box downward and the
  // reserved bottom padding keeps the sub-line clear of it instead of letting them collide.
  actionTall: { minHeight: TALL, paddingTop: SUB_PAD, paddingBottom: SUB_PAD + SUB_LINE },
  sub: { position: 'absolute', left: v2.space.lg, right: v2.space.lg, bottom: SUB_PAD, alignItems: 'center' },
  // Disabled dims the control; the line inside it has to dim with it or it reads as live copy
  // floating on a dead button.
  subDim: { opacity: 0.4 },
  // Black on brand red is the signature ink; the weight and size do the de-emphasis.
  subOnFill: { color: p.text.inverse },
  subOnCanvas: { color: p.text.muted },
  });
}

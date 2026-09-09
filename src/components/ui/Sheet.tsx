/**
 * src/components/ui/Sheet.tsx — the bottom sheet.
 *
 * Built on React Native's own `Modal`, which is what the app already uses for the
 * home filter sheet and the create-listing pickers. No new dependency.
 *
 * WHAT IT FIXES relative to the sheets in the product today:
 *  - They are dismissible only by an `✕` glyph. This one also takes a tap on the
 *    scrim and the Android back button, and the scrim is a real button to a
 *    screen reader instead of an invisible view.
 *  - They ignore the home indicator. This one pads by the safe-area inset.
 *  - Their corners are rounded 24. Square is the brand.
 *
 * FOOTER CONTRACT. The footer is a ROW. React Native defaults `flexShrink: 0`,
 * so a child sized `width: '100%'` — which is what `<Button block>` is — takes
 * the whole row and refuses to give any of it back. Two of them ask for 200%
 * plus the gap, and the second one is pushed off the right edge of the screen.
 * That is what clipped Apply in the Home filter sheet. Wrap each action in
 * `<SheetAction>` so the row divides itself into equal shares instead.
 */

import {
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  View,
  useWindowDimensions,
  type ViewStyle,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

/**
 * One action in a Sheet footer. `flex: 1` with a zero basis makes every action an
 * equal share of whatever width the row actually has, and `minWidth: 0` lets that
 * share fall below the button's natural content width instead of overflowing.
 * No fixed widths and no screen measurements, so it holds at any device width and
 * in any orientation.
 */
export function SheetAction({ children }: { children: React.ReactNode }) {
  return <View style={styles.action}>{children}</View>;
}

export interface SheetProps {
  visible: boolean;
  onClose: () => void;
  /** Rendered in the display face. Keep it to two or three words. */
  title?: string;
  children: React.ReactNode;
  /** Pinned under the content, outside the scroll: apply, confirm, cancel. */
  footer?: React.ReactNode;
  style?: ViewStyle;
  testID?: string;
}

export function Sheet({ visible, onClose, title, children, footer, style, testID }: SheetProps) {
  const insets = useSafeAreaInsets();
  const { height } = useWindowDimensions();

  return (
    <Modal
      visible={visible}
      transparent
      // `slide` is the platform's own sheet motion; it already honours the OS
      // reduce-motion setting, which a hand-rolled translate would not.
      animationType="slide"
      // Android hardware back. Without this a sheet is a trap on Android.
      onRequestClose={onClose}
      statusBarTranslucent
    >
      <KeyboardAvoidingView
        style={styles.root}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        testID={testID}
      >
        <Pressable
          style={styles.scrim}
          onPress={onClose}
          accessibilityRole="button"
          accessibilityLabel="Close"
        />
        <View
          style={[
            styles.sheet,
            { maxHeight: height * 0.85, paddingBottom: v2.space.lg + insets.bottom },
            style,
          ]}
        >
          <View style={styles.handle} />
          {title ? (
            <Text style={[textStyle('displaySm'), styles.title]} accessibilityRole="header">
              {title}
            </Text>
          ) : null}
          <View style={styles.body}>{children}</View>
          {footer ? <View style={styles.footer}>{footer}</View> : null}
        </View>
      </KeyboardAvoidingView>
    </Modal>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, justifyContent: 'flex-end' },
  scrim: { ...StyleSheet.absoluteFillObject, backgroundColor: v2.surface.overlay },
  sheet: {
    backgroundColor: v2.surface.elevated,
    borderRadius: v2.radius.none,
    borderTopWidth: 1,
    borderTopColor: v2.border.strong,
    paddingHorizontal: v2.space.lg,
    paddingTop: v2.space.sm,
  },
  handle: {
    width: 36,
    height: 4,
    borderRadius: v2.radius.pill,
    backgroundColor: 'rgba(255,255,255,0.30)',
    alignSelf: 'center',
    marginBottom: v2.space.md,
  },
  title: { color: v2.text.primary, marginBottom: v2.space.md },
  body: { gap: v2.space.md },
  footer: {
    flexDirection: 'row',
    // Actions divide this row; nothing in it may size itself from the screen.
    alignItems: 'stretch',
    gap: v2.space.sm,
    marginTop: v2.space.lg,
    paddingTop: v2.space.md,
    borderTopWidth: 1,
    borderTopColor: v2.border.default,
  },
  action: { flex: 1, flexBasis: 0, minWidth: 0 },
});

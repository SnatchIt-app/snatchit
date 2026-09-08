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
    gap: v2.space.sm,
    marginTop: v2.space.lg,
    paddingTop: v2.space.md,
    borderTopWidth: 1,
    borderTopColor: v2.border.default,
  },
});

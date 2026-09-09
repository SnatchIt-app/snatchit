/**
 * src/components/auth/AuthScreen.tsx — the shell every auth screen sits in.
 *
 * THE BUG THIS FIXES: the SN mark used to live inside
 * `KeyboardAvoidingView > View{flex:1, justifyContent:'center'}` together with
 * the form. That container vertically centres its whole content, so when the
 * keyboard opened and KAV shrank the available height, the centred block — mark
 * included — slid upward. The mark appeared to "jump to a better position" on
 * focus and drop back on blur.
 *
 * THE ARCHITECTURE: the brand header is rendered OUTSIDE the keyboard-responsive
 * region, so nothing about the keyboard can move it. It is pinned to the top with
 * `insets.top + space.xl` — safe-area aware, so it clears the Dynamic Island on
 * every device without a hardcoded Y for one screen size.
 *
 * The FORM stays inside the KeyboardAvoidingView and is free to move; it is also
 * scrollable (`flexGrow: 1` + centred) so it still centres when there is room and
 * can be scrolled to when the keyboard takes the space. Only the mark is fixed.
 */

import type { ReactNode } from 'react';
import { KeyboardAvoidingView, Platform, ScrollView, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { AuthBrandMark } from './AuthBrandMark';
import * as v2 from '@/src/theme/v2';

export function AuthScreen({ children }: { children: ReactNode }) {
  const insets = useSafeAreaInsets();

  return (
    <View style={styles.root}>
      {/* Fixed: outside the KeyboardAvoidingView, so focus/keyboard never moves it. */}
      <View style={[styles.header, { paddingTop: insets.top + v2.space.xl }]}>
        <AuthBrandMark />
      </View>

      <KeyboardAvoidingView
        style={styles.flex}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      >
        <ScrollView
          contentContainerStyle={styles.body}
          keyboardShouldPersistTaps="handled"
          showsVerticalScrollIndicator={false}
        >
          {children}
        </ScrollView>
      </KeyboardAvoidingView>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: v2.surface.canvas },
  header: { paddingBottom: v2.space.lg },
  flex: { flex: 1 },
  // flexGrow keeps the previous centred composition when there is room, and lets
  // the form scroll instead of being trapped behind the keyboard when there isn't.
  body: {
    flexGrow: 1,
    paddingHorizontal: v2.space.lg,
    justifyContent: 'center',
    paddingBottom: v2.space.xl,
  },
});

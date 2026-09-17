/**
 * src/hooks/useUnsavedChangesGuard.ts — ask before a back gesture discards work.
 *
 * CFT-208 (item 52). Built on React Navigation's `usePreventRemove`, which does two things
 * the stack needs: it holds the removal in navigation state (`beforeRemove`), AND it registers
 * this screen with the navigator so native-stack sets `preventNativeDismiss`. On iOS that is
 * what stops a swipe back natively: without it UIKit finishes the pop before JavaScript hears
 * of it, and the dialog appears over the previous screen with nothing left to keep (F-NAV-1,
 * Build 18: "Keep editing" landed on My Listings). With it the swipe is cancelled, the screen
 * stays, and the same dialog decides. The Back button and Android's back key start in
 * JavaScript and are held the same way.
 *
 * When `when` is true the dialog decides: "stay" does nothing, "leave" replays the original
 * navigation action, so whatever gesture started it completes as it would have (the replayed
 * action carries React Navigation's mark that this screen already answered, so it is not asked
 * again). When `when` is false the hook is inert and leaving is never held.
 */

import { useNavigation, usePreventRemove } from '@react-navigation/native';
import { Alert } from 'react-native';

import type { UnsavedCopy } from '@/src/lib/nav/unsavedChanges';

export interface UnsavedChangesGuardOptions extends UnsavedCopy {
  /** Ask before leaving while this is true. */
  when: boolean;
}

export function useUnsavedChangesGuard(opts: UnsavedChangesGuardOptions): void {
  const navigation = useNavigation();
  // usePreventRemove always calls the latest callback, so the copy never goes stale.
  usePreventRemove(opts.when, ({ data }) => {
    Alert.alert(opts.title, opts.message, [
      { text: opts.stayLabel, style: 'cancel' },
      { text: opts.leaveLabel, style: 'destructive', onPress: () => navigation.dispatch(data.action) },
    ]);
  });
}

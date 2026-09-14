/**
 * src/hooks/useUnsavedChangesGuard.ts — ask before a back gesture discards work.
 *
 * CFT-208 (item 52). Subscribes to React Navigation's `beforeRemove`, the same
 * signal the listing screen uses for its reservation exit: it fires when THIS
 * screen is popped — swipe back, the back button, the hardware key — and not
 * when another screen is pushed on top. When `when` is true the removal is
 * held and a two-button dialog decides; "leave" replays the original
 * navigation action, so whatever gesture started it completes as it would
 * have. When `when` is false the hook is inert.
 */

import { useNavigation } from '@react-navigation/native';
import { useEffect, useRef } from 'react';
import { Alert } from 'react-native';

import type { UnsavedCopy } from '@/src/lib/nav/unsavedChanges';

export interface UnsavedChangesGuardOptions extends UnsavedCopy {
  /** Ask before leaving while this is true. */
  when: boolean;
}

export function useUnsavedChangesGuard(opts: UnsavedChangesGuardOptions): void {
  const navigation = useNavigation();
  // Read through a ref so the listener never goes stale and never resubscribes
  // on every keystroke.
  const optsRef = useRef(opts);
  optsRef.current = opts;

  useEffect(() => {
    return navigation.addListener('beforeRemove', (e) => {
      const o = optsRef.current;
      if (!o.when) return;
      e.preventDefault();
      Alert.alert(o.title, o.message, [
        { text: o.stayLabel, style: 'cancel' },
        { text: o.leaveLabel, style: 'destructive', onPress: () => navigation.dispatch(e.data.action) },
      ]);
    });
  }, [navigation]);
}

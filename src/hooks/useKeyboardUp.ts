/**
 * src/hooks/useKeyboardUp.ts — is a text keyboard occupying the bottom of the
 * screen? Same events AdaptiveDock uses to hide itself (iOS `will*` so the
 * layout moves with the keyboard, not after it). Restores on dismiss, so an
 * open → dismiss → reopen cycle always lands in the same layout.
 */
import { useEffect, useState } from 'react';
import { Keyboard, Platform } from 'react-native';

export function useKeyboardUp(): boolean {
  const [up, setUp] = useState(false);
  useEffect(() => {
    const showEvt = Platform.OS === 'ios' ? 'keyboardWillShow' : 'keyboardDidShow';
    const hideEvt = Platform.OS === 'ios' ? 'keyboardWillHide' : 'keyboardDidHide';
    const onShow = Keyboard.addListener(showEvt, () => setUp(true));
    const onHide = Keyboard.addListener(hideEvt, () => setUp(false));
    return () => { onShow.remove(); onHide.remove(); };
  }, []);
  return up;
}

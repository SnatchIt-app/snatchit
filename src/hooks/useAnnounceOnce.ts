/**
 * src/hooks/useAnnounceOnce.ts — speak `text` to VoiceOver when it appears or changes.
 *
 * iOS only: on Android the same elements already carry `accessibilityLiveRegion`, which speaks them,
 * and announcing as well would say everything twice. Pass null/'' when there is nothing to say.
 */
import { useEffect, useRef } from 'react';
import { AccessibilityInfo, Platform } from 'react-native';

import { announcementFor } from '@/src/lib/a11y/announce';

export function useAnnounceOnce(text: string | null | undefined): void {
  const last = useRef<string | null>(null);
  useEffect(() => {
    const next = announcementFor(last.current, text);
    last.current = next.last;
    if (next.say && Platform.OS === 'ios') AccessibilityInfo.announceForAccessibility(next.say);
  }, [text]);
}

/**
 * The same, as an element: for screens whose text is computed after an early return, where a hook
 * call there would change the hook order between renders. Renders nothing.
 */
export function Announce({ text }: { text: string | null | undefined }): null {
  useAnnounceOnce(text);
  return null;
}

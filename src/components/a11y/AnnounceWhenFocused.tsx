/**
 * src/components/a11y/AnnounceWhenFocused.tsx — `useAnnounceOnce` as an element, spoken only while
 * its screen is the focused one.
 *
 * For screens that compute the text after an early return (a hook call there would change the hook
 * order) and that stay mounted under a pushed screen. ListingDetail sits under Checkout and Place bid,
 * and its "reconnecting" notice was spoken over them (review m5). Renders nothing.
 */
import { useIsFocused } from '@react-navigation/native';

import { useAnnounceOnce } from '@/src/hooks/useAnnounceOnce';

export function AnnounceWhenFocused({ text }: { text: string | null | undefined }): null {
  const focused = useIsFocused();
  useAnnounceOnce(focused ? text : null);
  return null;
}

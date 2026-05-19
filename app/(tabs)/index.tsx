/**
 * app/(tabs)/index.tsx — Default route of the (tabs) group.
 *
 * Hidden from the tab bar (href: null in (tabs)/_layout.tsx). Should never be
 * the visible screen, but expo-router still resolves /(tabs) to this file when
 * navigation lands on the group without an explicit segment. Redirect to
 * /(tabs)/home so users always land on the real home screen.
 */
import { Redirect } from 'expo-router';

export default function TabsIndex() {
  return <Redirect href="/(tabs)/home" />;
}

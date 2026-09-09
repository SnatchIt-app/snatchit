/**
 * app/(tabs)/_layout.tsx — Primary navigation (V2 adaptive dock).
 *
 * Routing is Home · Create · Bids · Tickets · Profile (with the legacy index /
 * explore hidden). The default tab bar is replaced by the Snatch It floating
 * `AdaptiveDock` via the `tabBar` render prop — same routes, same lazy mounting,
 * same route names, so analytics/deep-links are unaffected. `NavDockProvider`
 * holds the per-route collapse state; the dock reads it.
 *
 * Tickets (Phase 11) is the fifth destination now that Core exposes the ownership
 * read (public.get_my_tickets). It slots between Bids and Profile — the order
 * `navItems({ tickets: true })` already returns — with no dock change.
 */

import { Tabs } from 'expo-router';

import { AdaptiveDock } from '@/src/components/nav/AdaptiveDock';
import { NavDockProvider } from '@/src/components/nav/dockContext';

export default function TabLayout() {
  return (
    <NavDockProvider>
      <Tabs
        screenOptions={{ headerShown: false }}
        tabBar={(props) => <AdaptiveDock {...props} />}
      >
        <Tabs.Screen name="home" options={{ title: 'Home' }} />
        <Tabs.Screen name="create" options={{ title: 'Create' }} />
        <Tabs.Screen name="bids" options={{ title: 'Bids' }} />
        <Tabs.Screen name="tickets" options={{ title: 'Tickets' }} />
        <Tabs.Screen name="profile" options={{ title: 'Profile' }} />

        {/* Hidden legacy screens (still reachable via router.push) */}
        <Tabs.Screen name="index" options={{ href: null }} />
        <Tabs.Screen name="explore" options={{ href: null }} />
      </Tabs>
    </NavDockProvider>
  );
}

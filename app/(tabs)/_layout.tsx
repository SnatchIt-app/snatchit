/**
 * app/(tabs)/_layout.tsx — Bottom tab navigator
 *
 * Tabs: Home · Create · Bids · Profile
 * The old `index` and `explore` files are hidden from the tab bar;
 * they still exist on disk but are not shown as tabs.
 */

import { Tabs } from 'expo-router';

import { HapticTab } from '@/components/haptic-tab';
import { IconSymbol } from '@/components/ui/icon-symbol';
import { colors } from '@/src/theme';

export default function TabLayout() {
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarButton: HapticTab,
        // Dark tab bar matching the app theme
        tabBarStyle: {
          backgroundColor: colors.bg,
          borderTopColor: colors.border,
        },
        tabBarActiveTintColor: colors.accent,
        tabBarInactiveTintColor: colors.textMuted,
      }}>

      {/* ── Home ── */}
      <Tabs.Screen
        name="home"
        options={{
          title: 'Home',
          tabBarIcon: ({ color }) => (
            <IconSymbol size={26} name="house.fill" color={color} />
          ),
        }}
      />

      {/* ── Create ── */}
      <Tabs.Screen
        name="create"
        options={{
          title: 'Create',
          tabBarIcon: ({ color }) => (
            <IconSymbol size={26} name="plus.circle.fill" color={color} />
          ),
        }}
      />

      {/* ── Bids ── */}
      <Tabs.Screen
        name="bids"
        options={{
          title: 'Bids',
          tabBarIcon: ({ color }) => (
            <IconSymbol size={26} name="tag.fill" color={color} />
          ),
        }}
      />

      {/* ── Profile ── */}
      <Tabs.Screen
        name="profile"
        options={{
          title: 'Profile',
          tabBarIcon: ({ color }) => (
            <IconSymbol size={26} name="person.fill" color={color} />
          ),
        }}
      />

      {/* ── Hidden legacy screens (still usable via router.push) ── */}
      <Tabs.Screen name="index"   options={{ href: null }} />
      <Tabs.Screen name="explore" options={{ href: null }} />

    </Tabs>
  );
}

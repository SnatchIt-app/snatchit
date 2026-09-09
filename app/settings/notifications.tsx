/**
 * app/settings/notifications.tsx — Notification preferences (V2).
 *
 * PRESENTATION rebuilt on the V2 account system; behaviour is unchanged: the same
 * `notification_preferences` fetch, the OPTIMISTIC toggle that flips immediately
 * and REVERTS with an alert on a failed write (a failed save never looks
 * successful), the device-permission banner with its focus re-check and the
 * "Open settings" recovery path.
 */

import * as Notifications from 'expo-notifications';
import { useCallback, useEffect, useState } from 'react';
import { Alert, Linking, Pressable, ScrollView, StyleSheet, Switch, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { Button, Spinner } from '@/src/components/ui';
import { AccountSection } from '@/src/components/account/AccountSection';
import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import type { NotificationPreferences } from '@/src/types';

type PrefKey = keyof Omit<NotificationPreferences, 'user_id' | 'updated_at'>;

const TOGGLES: { key: PrefKey; label: string; description: string }[] = [
  { key: 'notify_outbid',           label: 'Outbid alerts',        description: 'Get notified when someone outbids you' },
  { key: 'notify_auction_ending',   label: 'Auction ending soon',  description: 'Reminder when auctions you bid on are ending' },
  { key: 'notify_auction_won',      label: 'Auction won',          description: 'Know the moment you win an auction' },
  { key: 'notify_auction_lost',     label: 'Auction lost',         description: 'Know when an auction you bid on ends without you winning' },
  { key: 'notify_reservation_exp',  label: 'Reservation expiring', description: 'Reminder before your Buy Now reservation expires' },
  { key: 'notify_listing_sold',     label: 'Listing sold',         description: 'Get notified when your listing sells' },
];

export default function NotificationsScreen() {
  const { user } = useAuth();
  const userId = user?.id;

  const [prefs, setPrefs] = useState<NotificationPreferences | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [permissionGranted, setPermissionGranted] = useState<boolean | null>(null);

  async function checkPermission() {
    try {
      const { status } = await Notifications.getPermissionsAsync();
      setPermissionGranted(status === 'granted');
    } catch {
      setPermissionGranted(null);
    }
  }

  async function fetchPrefs() {
    if (!userId) return;
    setLoading(true);
    setError(null);
    const { data, error: fetchErr } = await supabase
      .from('notification_preferences')
      .select('*')
      .eq('user_id', userId)
      .single();
    if (fetchErr) {
      console.warn('[notifications] fetch error:', fetchErr.message);
      setError('Unable to load preferences');
      setLoading(false);
      return;
    }
    setPrefs(data as NotificationPreferences);
    setLoading(false);
  }

  useEffect(() => {
    checkPermission();
    fetchPrefs();
  }, [userId]);

  useFocusEffect(useCallback(() => { checkPermission(); }, []));

  // Optimistic: flip immediately, revert + alert on failure. A failed save must
  // never look successful.
  async function handleToggle(key: PrefKey, newValue: boolean) {
    if (!userId || !prefs) return;
    const prev = prefs[key];
    setPrefs({ ...prefs, [key]: newValue });
    const { error: updateErr } = await supabase
      .from('notification_preferences')
      .update({ [key]: newValue })
      .eq('user_id', userId);
    if (updateErr) {
      setPrefs((p) => (p ? { ...p, [key]: prev } : p));
      Alert.alert('Update failed', 'Could not save your preference. Please try again.');
    }
  }

  if (loading) {
    return (
      <View style={s.root}>
        <SettingsHeader title="Notifications" />
        <View style={s.center}><Spinner color={v2.brand.red} /></View>
      </View>
    );
  }

  if (error || !prefs) {
    return (
      <View style={s.root}>
        <SettingsHeader title="Notifications" />
        <View style={s.center}>
          <Text style={[textStyle('body'), s.errorText]}>{error ?? 'Unable to load preferences'}</Text>
          <Button label="Retry" variant="secondary" onPress={fetchPrefs} style={s.retry} />
        </View>
      </View>
    );
  }

  return (
    <View style={s.root}>
      <SettingsHeader title="Notifications" />
      <ScrollView contentContainerStyle={s.scroll} showsVerticalScrollIndicator={false}>
        {permissionGranted !== null ? (
          <View style={[s.permBanner, { borderColor: permissionGranted ? v2.status.success : v2.status.error }]} accessibilityRole="alert">
            <View style={[s.dot, { backgroundColor: permissionGranted ? v2.status.success : v2.status.error }]} />
            <View style={s.permBody}>
              <Text style={[textStyle('bodySm'), s.permText]}>
                {permissionGranted ? 'Notifications are enabled' : 'Notifications are disabled in your device settings'}
              </Text>
              {!permissionGranted ? (
                <Pressable onPress={() => Linking.openSettings()} style={s.openSettings} hitSlop={8} accessibilityRole="button" accessibilityLabel="Open device settings to enable notifications">
                  <Text style={[textStyle('label'), s.openSettingsText]}>Open settings</Text>
                </Pressable>
              ) : null}
            </View>
          </View>
        ) : null}

        <AccountSection title="Preferences">
          {TOGGLES.map((item) => (
            <View key={item.key} style={s.row}>
              <View style={s.rowText}>
                <Text style={[textStyle('title'), s.rowLabel]}>{item.label}</Text>
                <Text style={[textStyle('bodySm'), s.rowDesc]}>{item.description}</Text>
              </View>
              <Switch
                value={prefs[item.key] as boolean}
                onValueChange={(val) => handleToggle(item.key, val)}
                trackColor={{ false: v2.border.strong, true: v2.brand.red }}
                thumbColor={v2.text.primary}
                ios_backgroundColor={v2.border.strong}
                accessibilityLabel={item.label}
              />
            </View>
          ))}
        </AccountSection>
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: v2.surface.canvas },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: v2.space.md, padding: v2.space.xl },
  errorText: { color: v2.status.error, textAlign: 'center' },
  retry: { minWidth: 160 },

  scroll: { paddingHorizontal: v2.space.lg, paddingBottom: v2.space.xxxl },

  permBanner: { flexDirection: 'row', alignItems: 'flex-start', gap: v2.space.sm, borderWidth: 1, padding: v2.space.md, marginTop: v2.space.lg },
  dot: { width: 8, height: 8, borderRadius: 4, marginTop: 6 },
  permBody: { flex: 1 },
  permText: { color: v2.text.primary },
  openSettings: { marginTop: v2.space.sm, minHeight: 44, justifyContent: 'center', alignSelf: 'flex-start' },
  openSettingsText: { color: v2.brand.red },

  row: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: v2.space.md, paddingVertical: v2.space.md, borderBottomWidth: 1, borderBottomColor: v2.border.default },
  rowText: { flex: 1 },
  rowLabel: { color: v2.text.primary },
  rowDesc: { color: v2.text.muted, marginTop: 2 },
});

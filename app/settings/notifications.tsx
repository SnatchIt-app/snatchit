/**
 * app/settings/notifications.tsx — Notification Preferences
 *
 * Fetches the user's notification_preferences row from Supabase and
 * displays a toggle for each preference.  Updates are optimistic —
 * the switch flips immediately and the DB write happens in the background.
 * If the update fails the toggle is reverted and an alert is shown.
 *
 * The permission status banner at the top reflects the device-level
 * notification permission and offers a button to open device settings
 * when notifications have been denied.
 */

import { router } from 'expo-router';
import * as Notifications from 'expo-notifications';
import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Linking,
  Pressable,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useFocusEffect } from '@react-navigation/native';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { colors, fontSize, radius, spacing } from '@/src/theme';
import type { NotificationPreferences } from '@/src/types';

// ─── Toggle config ────────────────────────────────────────────────────────────

type PrefKey = keyof Omit<NotificationPreferences, 'user_id' | 'updated_at'>;

const TOGGLES: { key: PrefKey; label: string; description: string }[] = [
  {
    key: 'notify_outbid',
    label: 'Outbid alerts',
    description: 'Get notified when someone outbids you',
  },
  {
    key: 'notify_auction_ending',
    label: 'Auction ending soon',
    description: 'Reminder when auctions you bid on are ending',
  },
  {
    key: 'notify_auction_won',
    label: 'Auction won',
    description: 'Celebration when you win an auction',
  },
  {
    key: 'notify_auction_lost',
    label: 'Auction lost',
    description: 'Know when an auction you bid on ends without you winning',
  },
  {
    key: 'notify_reservation_exp',
    label: 'Reservation expiring',
    description: 'Reminder before your Buy Now reservation expires',
  },
  {
    key: 'notify_listing_sold',
    label: 'Listing sold',
    description: 'Get notified when your listing sells',
  },
];

// ─── Screen ───────────────────────────────────────────────────────────────────

export default function NotificationsScreen() {
  const { user } = useAuth();
  const userId = user?.id;

  const [prefs, setPrefs]               = useState<NotificationPreferences | null>(null);
  const [loading, setLoading]           = useState(true);
  const [error, setError]               = useState<string | null>(null);
  const [permissionGranted, setPermissionGranted] = useState<boolean | null>(null);

  // ── Check device notification permission ──────────────────────────────────
  async function checkPermission() {
    try {
      const { status } = await Notifications.getPermissionsAsync();
      setPermissionGranted(status === 'granted');
    } catch {
      // Can't determine — treat as unknown
      setPermissionGranted(null);
    }
  }

  // ── Fetch preferences from Supabase ───────────────────────────────────────
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

  // ── Initial load ──────────────────────────────────────────────────────────
  useEffect(() => {
    checkPermission();
    fetchPrefs();
  }, [userId]);

  // ── Re-check permission when screen comes back into focus ─────────────────
  // (e.g. user toggled notification setting in device Settings and returned)
  useFocusEffect(
    useCallback(() => {
      checkPermission();
    }, []),
  );

  // ── Optimistic toggle handler ─────────────────────────────────────────────
  async function handleToggle(key: PrefKey, newValue: boolean) {
    if (!userId || !prefs) return;

    // Optimistic: flip immediately
    const prev = prefs[key];
    setPrefs({ ...prefs, [key]: newValue });

    const { error: updateErr } = await supabase
      .from('notification_preferences')
      .update({ [key]: newValue })
      .eq('user_id', userId);

    if (updateErr) {
      // Revert
      setPrefs(p => p ? { ...p, [key]: prev } : p);
      Alert.alert('Update failed', 'Could not save your preference. Please try again.');
    }
  }

  // ── Guards ────────────────────────────────────────────────────────────────

  const renderTopBar = () => (
    <View style={s.topBar}>
      <Pressable onPress={() => router.back()} style={s.backBtn} hitSlop={8}>
        <Text style={s.backArrow}>{'\u2190'}</Text>
      </Pressable>
      <Text style={s.topTitle}>Notifications</Text>
      <View style={s.backBtn} />
    </View>
  );

  if (loading) {
    return (
      <SafeAreaView style={s.safe}>
        {renderTopBar()}
        <View style={s.centered}>
          <ActivityIndicator color={colors.primary} size="large" />
        </View>
      </SafeAreaView>
    );
  }

  if (error || !prefs) {
    return (
      <SafeAreaView style={s.safe}>
        {renderTopBar()}
        <View style={s.centered}>
          <Text style={s.errorText}>{error ?? 'Unable to load preferences'}</Text>
          <TouchableOpacity style={s.retryBtn} onPress={fetchPrefs}>
            <Text style={s.retryBtnText}>Retry</Text>
          </TouchableOpacity>
        </View>
      </SafeAreaView>
    );
  }

  // ── Render ────────────────────────────────────────────────────────────────

  return (
    <SafeAreaView style={s.safe}>
      {renderTopBar()}

      <ScrollView contentContainerStyle={s.scrollContent} showsVerticalScrollIndicator={false}>

        {/* ── Permission status banner ──────────────────────────────────── */}
        {permissionGranted !== null && (
          <View style={[s.permBanner, permissionGranted ? s.permGranted : s.permDenied]}>
            <View style={s.permDot}>
              <View style={[s.dot, { backgroundColor: permissionGranted ? colors.success : colors.error }]} />
            </View>
            <View style={{ flex: 1 }}>
              <Text style={s.permText}>
                {permissionGranted
                  ? 'Notifications are enabled'
                  : 'Notifications are disabled in your device settings'}
              </Text>
              {!permissionGranted && (
                <TouchableOpacity onPress={() => Linking.openSettings()} style={s.settingsBtn}>
                  <Text style={s.settingsBtnText}>Open Settings</Text>
                </TouchableOpacity>
              )}
            </View>
          </View>
        )}

        {/* ── Section header ─────────────────────────────────────────── */}
        <Text style={s.sectionHead}>PREFERENCES</Text>

        {/* ── Toggle rows ────────────────────────────────────────────── */}
        <View style={s.card}>
          {TOGGLES.map((item, idx) => (
            <View
              key={item.key}
              style={[s.row, idx < TOGGLES.length - 1 && s.rowBorder]}
            >
              <View style={s.rowText}>
                <Text style={s.rowLabel}>{item.label}</Text>
                <Text style={s.rowDesc}>{item.description}</Text>
              </View>
              <Switch
                value={prefs[item.key] as boolean}
                onValueChange={(val) => handleToggle(item.key, val)}
                trackColor={{ false: colors.bgInput, true: colors.primarySoft }}
                thumbColor={prefs[item.key] ? colors.primary : colors.textDim}
                ios_backgroundColor={colors.bgInput}
              />
            </View>
          ))}
        </View>

      </ScrollView>
    </SafeAreaView>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  safe:      { flex: 1, backgroundColor: colors.bg },
  topBar:    { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
               paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
               borderBottomWidth: 1, borderBottomColor: colors.border },
  backBtn:   { width: 44, height: 44, alignItems: 'flex-start', justifyContent: 'center' },
  backArrow: { color: colors.text, fontSize: fontSize.xl, fontWeight: '600' },
  topTitle:  { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },
  centered:  { flex: 1, justifyContent: 'center', alignItems: 'center', gap: spacing.md },
  errorText: { color: colors.error, fontSize: fontSize.sm, textAlign: 'center',
               paddingHorizontal: spacing.xl },
  retryBtn:  { backgroundColor: colors.primary, paddingHorizontal: spacing.xl,
               paddingVertical: spacing.sm, borderRadius: radius.md },
  retryBtnText: { color: colors.text, fontWeight: '700', fontSize: fontSize.sm },

  scrollContent: { paddingHorizontal: spacing.lg, paddingTop: spacing.lg, paddingBottom: spacing.xxl },

  // Permission banner
  permBanner:  { flexDirection: 'row', alignItems: 'center', borderRadius: radius.md,
                 borderWidth: 1, padding: spacing.md, marginBottom: spacing.lg, gap: spacing.sm },
  permGranted: { backgroundColor: 'rgba(74,222,128,0.08)', borderColor: 'rgba(74,222,128,0.25)' },
  permDenied:  { backgroundColor: 'rgba(255,77,109,0.08)', borderColor: 'rgba(255,77,109,0.25)' },
  permDot:     { width: 24, alignItems: 'center' },
  dot:         { width: 8, height: 8, borderRadius: 4 },
  permText:    { color: colors.text, fontSize: fontSize.sm, fontWeight: '600' },
  settingsBtn: { marginTop: 6 },
  settingsBtnText: { color: colors.primary, fontSize: fontSize.sm, fontWeight: '700' },

  // Section
  sectionHead: { fontSize: fontSize.xs, fontWeight: '700', color: colors.textDim,
                 letterSpacing: 1.4, textTransform: 'uppercase', marginBottom: spacing.sm },

  // Card + rows
  card:       { backgroundColor: colors.bgCard, borderRadius: radius.lg,
                borderWidth: 1, borderColor: colors.border, overflow: 'hidden' },
  row:        { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
                paddingVertical: 14, paddingHorizontal: spacing.md },
  rowBorder:  { borderBottomWidth: 1, borderBottomColor: colors.border },
  rowText:    { flex: 1, marginRight: spacing.md },
  rowLabel:   { color: colors.text, fontSize: fontSize.sm, fontWeight: '600' },
  rowDesc:    { color: colors.textMuted, fontSize: fontSize.xs, marginTop: 2, lineHeight: 16 },
});

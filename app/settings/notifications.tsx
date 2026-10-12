/**
 * app/settings/notifications.tsx — Notification preferences (V2).
 *
 * PRESENTATION rebuilt on the V2 account system; behaviour is unchanged: the same
 * `notification_preferences` fetch, the OPTIMISTIC toggle that flips immediately
 * and REVERTS on a failed write (a failed save never looks successful), the
 * device-permission banner with its focus re-check and the "Open settings"
 * recovery path.
 *
 * PREMIUM BATCH 2 (CFT-204, item 11). The revert now explains itself inline —
 * a short notice under the list, announced to a screen reader — instead of a
 * modal alert that interrupts the whole screen for one toggle.
 */

import * as Notifications from 'expo-notifications';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { AccessibilityInfo, Linking, Pressable, ScrollView, StyleSheet, Switch, Text, TextInput, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { CHALLENGE_COPY } from '@/src/lib/push/challenge';
import { REGISTRATION_REMEDY } from '@/src/lib/push/registration';
import { getRegistrationStatus, requestRegistrationRetry, submitChallengeCode, subscribeRegistrationStatus, type RegistrationStatus } from '@/src/lib/push/registrationStatus';
import { Button, Spinner } from '@/src/components/ui';
import { AccountSection } from '@/src/components/account/AccountSection';
import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';
import type { NotificationPreferences } from '@/src/types';
import { PREF_TOGGLES, visibleToggles, WIRED_PREF_KEYS, type PrefKey } from '@/src/lib/settings/notificationPrefs';

// Batch 1 (owner ruling 2026-09-17): only switches whose path exists are shown; the
// rest are hidden, their stored values preserved — hiding never writes.
const TOGGLES = visibleToggles(PREF_TOGGLES, WIRED_PREF_KEYS);

export default function NotificationsScreen() {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const { user } = useAuth();
  const userId = user?.id;

  const [prefs, setPrefs] = useState<NotificationPreferences | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [permissionGranted, setPermissionGranted] = useState<boolean | null>(null);
  // A failed toggle rolls back and says so here, briefly.
  const [notice, setNotice] = useState<string | null>(null);
  // Whether this device is registered for THIS account (128 client, A-08d).
  const [registration, setRegistration] = useState<RegistrationStatus>(getRegistrationStatus);
  useEffect(() => subscribeRegistrationStatus(setRegistration), []);
  const remedy =
    registration.state === 'failed' || registration.state === 'waiting'
      ? REGISTRATION_REMEDY[registration.kind] ?? null
      : null;
  // v3: proof-of-possession challenge for this device.
  const challenge = registration.state === 'challenge' ? registration.challenge : null;
  const [code, setCode] = useState('');
  const [codeBusy, setCodeBusy] = useState(false);
  async function handleSubmitCode() {
    if (codeBusy) return;
    setCodeBusy(true);
    try { await submitChallengeCode(code); setCode(''); } finally { setCodeBusy(false); }
  }

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

  // Optimistic: flip immediately, revert with a brief explanation on failure.
  // A failed save must never look successful.
  async function handleToggle(key: PrefKey, newValue: boolean) {
    if (!userId || !prefs) return;
    const prev = prefs[key];
    setNotice(null);
    setPrefs({ ...prefs, [key]: newValue });
    const { error: updateErr } = await supabase
      .from('notification_preferences')
      .update({ [key]: newValue })
      .eq('user_id', userId);
    if (updateErr) {
      setPrefs((p) => (p ? { ...p, [key]: prev } : p));
      const label = TOGGLES.find((t) => t.key === key)?.label ?? 'that setting';
      const msg = `Couldn't save ${label}. It's back to ${prev ? 'on' : 'off'}. Check your connection and try again.`;
      setNotice(msg);
      AccessibilityInfo.announceForAccessibility(msg);
    }
  }

  if (loading) {
    return (
      <View style={s.root}>
        <SettingsHeader title="Notifications" />
        <View style={s.center}><Spinner color={palette.brand.red} /></View>
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
          <View style={[s.permBanner, { borderColor: permissionGranted ? palette.status.success : palette.status.error }]} accessibilityRole="alert">
            <View style={[s.dot, { backgroundColor: permissionGranted ? palette.status.success : palette.status.error }]} />
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

        {challenge && (challenge.phase === 'awaiting_push' || challenge.phase === 'confirming') ? (
          <View style={[s.permBanner, { borderColor: palette.status.warning }]} accessibilityRole="alert">
            <Spinner />
            <View style={s.permBody}>
              <Text style={[textStyle('bodySm'), s.permText]}>{CHALLENGE_COPY.pending}</Text>
            </View>
          </View>
        ) : null}

        {challenge && challenge.phase === 'awaiting_code' ? (
          <View style={[s.permBanner, { borderColor: palette.status.warning }]} accessibilityRole="alert">
            <View style={[s.dot, { backgroundColor: palette.status.warning }]} />
            <View style={s.permBody}>
              <Text style={[textStyle('bodySm'), s.permText]}>{CHALLENGE_COPY.codePrompt}</Text>
              {challenge.lastError === 'stale_nonce' ? (
                <Text style={[textStyle('bodySm'), s.notice]}>{CHALLENGE_COPY.staleCode}</Text>
              ) : null}
              {challenge.lastError === 'nonce_mismatch' ? (
                <Text style={[textStyle('bodySm'), s.notice]}>{CHALLENGE_COPY.wrongCode(challenge.attemptsLeft)}</Text>
              ) : null}
              {/* A persistent name for the field. The prompt above states the format once and the
                  placeholder repeats it, but both are gone or unreferenced the moment a digit is
                  typed — and this screen is reached mid-challenge, with a timer running. */}
              <Text style={[textStyle('micro'), s.codeLabel]}>Verification code</Text>
              <TextInput
                value={code}
                onChangeText={(t) => setCode(t.replace(/[^0-9]/g, ''))}
                keyboardType="number-pad"
                textContentType="oneTimeCode"
                autoComplete="one-time-code"
                maxLength={6}
                placeholder="6-digit code"
                placeholderTextColor={palette.text.faint}
                style={s.codeInput}
                accessibilityLabel="Verification code"
                onSubmitEditing={handleSubmitCode}
              />
              <Button label="Confirm" pendingLabel="Confirming…" onPress={handleSubmitCode} loading={codeBusy} disabled={codeBusy || code.length !== 6} />
            </View>
          </View>
        ) : null}

        {challenge && challenge.phase === 'failed' ? (
          <View style={[s.permBanner, { borderColor: palette.status.error }]} accessibilityRole="alert">
            <View style={[s.dot, { backgroundColor: palette.status.error }]} />
            <View style={s.permBody}>
              <Text style={[textStyle('bodySm'), s.permText]}>{CHALLENGE_COPY.failed[challenge.kind]}</Text>
              <Pressable onPress={requestRegistrationRetry} style={s.openSettings} hitSlop={8} accessibilityRole="button" accessibilityLabel="Try again">
                <Text style={[textStyle('bodySm'), s.openSettingsText]}>Try again</Text>
              </Pressable>
            </View>
          </View>
        ) : null}

        {remedy ? (
          <View style={[s.permBanner, { borderColor: palette.status.warning }]} accessibilityRole="alert">
            <View style={[s.dot, { backgroundColor: palette.status.warning }]} />
            <View style={s.permBody}>
              <Text style={[textStyle('bodySm'), s.permText]}>{remedy}</Text>
              {registration.state === 'failed' ? (
                <Pressable onPress={requestRegistrationRetry} style={s.openSettings} hitSlop={8} accessibilityRole="button" accessibilityLabel="Try again">
                  <Text style={[textStyle('bodySm'), s.openSettingsText]}>Try again</Text>
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
                trackColor={{ false: palette.border.strong, true: palette.brand.red }}
                thumbColor={palette.onArt.primary}
                ios_backgroundColor={palette.border.strong}
                accessibilityLabel={item.label}
              />
            </View>
          ))}
        </AccountSection>
        {notice ? (
          <Text style={[textStyle('bodySm'), s.notice]} accessibilityRole="alert">{notice}</Text>
        ) : null}
      </ScrollView>
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  root: { flex: 1, backgroundColor: p.surface.canvas },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: v2.space.md, padding: v2.space.xl },
  errorText: { color: p.status.error, textAlign: 'center' },
  retry: { minWidth: 160 },

  scroll: { paddingHorizontal: v2.space.lg, paddingBottom: v2.space.xxxl },

  permBanner: { flexDirection: 'row', alignItems: 'flex-start', gap: v2.space.sm, borderWidth: 1, padding: v2.space.md, marginTop: v2.space.lg },
  dot: { width: 8, height: 8, borderRadius: 4, marginTop: 6 },
  permBody: { flex: 1 },
  codeLabel: { color: p.text.muted, textTransform: 'uppercase', marginBottom: v2.space.xs },
  permText: { color: p.text.primary },
  openSettings: { marginTop: v2.space.sm, minHeight: 44, justifyContent: 'center', alignSelf: 'flex-start' },
  openSettingsText: { color: p.brand.redText },

  row: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: v2.space.md, paddingVertical: v2.space.md, borderBottomWidth: 1, borderBottomColor: p.border.default },
  rowText: { flex: 1 },
  rowLabel: { color: p.text.primary },
  rowDesc: { color: p.text.muted, marginTop: 2 },
  notice: { color: p.status.error, marginTop: v2.space.md },
  codeInput: {
    marginTop: v2.space.sm, minHeight: 44, borderWidth: 1, borderColor: p.border.strong,
    paddingHorizontal: v2.space.md, color: p.text.primary, fontSize: 20, letterSpacing: 6,
  },
  });
}

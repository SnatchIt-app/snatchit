/**
 * app/settings/index.tsx — Settings Hub
 *
 * Navigated to from Profile header gear icon.
 * Groups all setting routes into labelled sections.
 *
 * Sections:
 *   ACCOUNT    — Edit Profile, Notifications
 *   PAYMENTS   — Payout Method
 *   PREFERENCES— Neighborhood
 *   SUPPORT    — Help & Support, Terms & Privacy
 *   DANGER     — Log Out
 */

import { router } from 'expo-router';
import {
  ActivityIndicator,
  Alert,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useState } from 'react';

import { supabase } from '@/src/lib/supabase';
import { colors, fontSize, radius, shadow, spacing } from '@/src/theme';

// ─── Types ────────────────────────────────────────────────────────────────────

type SettingsRoute =
  | '/settings/edit-profile'
  | '/settings/notifications'
  | '/settings/payout-setup'
  | '/settings/preferences'
  | '/settings/support'
  | '/settings/legal'
  | '/settings/privacy';

// ─── Sub-components ───────────────────────────────────────────────────────────

/** Section header label */
function SectionLabel({ text }: { text: string }) {
  return <Text style={s.sectionLabel}>{text}</Text>;
}

/** A single tappable settings row */
function SettingsRow({
  icon,
  label,
  onPress,
  showBorder = true,
}: {
  icon:        string;
  label:       string;
  onPress:     () => void;
  showBorder?: boolean;
}) {
  return (
    <Pressable
      style={[row.container, !showBorder && row.noBorder]}
      onPress={onPress}
      android_ripple={{ color: colors.primarySoft }}
    >
      <Text style={row.icon}>{icon}</Text>
      <Text style={row.label}>{label}</Text>
      <Text style={row.chevron}>›</Text>
    </Pressable>
  );
}

const row = StyleSheet.create({
  container: {
    flexDirection:     'row',
    alignItems:        'center',
    paddingVertical:   spacing.md,
    paddingHorizontal: spacing.md,
    gap:               spacing.md,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  noBorder: { borderBottomWidth: 0 },
  icon:     { fontSize: 18, width: 24, textAlign: 'center' },
  label:    { flex: 1, fontSize: fontSize.md, color: colors.text, fontWeight: '500' },
  chevron:  { color: colors.textMuted, fontSize: fontSize.lg, fontWeight: '300' },
});

/** Card container that wraps a group of rows */
function SettingsCard({ children }: { children: React.ReactNode }) {
  return <View style={s.card}>{children}</View>;
}

// ─── Screen ───────────────────────────────────────────────────────────────────

export default function SettingsScreen() {
  const [signingOut, setSigningOut] = useState(false);
  const [deleting, setDeleting] = useState(false);

  function nav(path: SettingsRoute) {
    router.push(path);
  }

  async function handleSignOut() {
    Alert.alert('Sign Out', 'Are you sure you want to sign out?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Sign Out',
        style: 'destructive',
        onPress: async () => {
          console.log('[settings] sign out start');
          setSigningOut(true);
          try {
            await supabase.auth.signOut();
            console.log('[settings] sign out success, navigating to login');
            router.replace('/(auth)/login');
          } catch (err) {
            console.error('[settings] sign out error:', err);
            alertWeb('Failed to sign out. Please try again.');
          } finally {
            console.log('[settings] finally clearing loading');
            setSigningOut(false);
          }
        },
      },
    ]);
  }

  function alertWeb(msg: string) {
    if (Platform.OS === 'web') { window.alert(msg); } else { Alert.alert('Error', msg); }
  }

  async function executeDeleteAccount() {
    console.log('[settings] delete start');
    setDeleting(true);
    try {
      const { data, error } = await supabase.functions.invoke('delete-account', { body: {} });
      console.log('[settings] delete function response', { data, error: error?.message });

      if (error) {
        let reason = 'Failed to delete account. Please try again or contact support.';
        try {
          const ctx = (error as any)?.context;
          if (ctx && typeof ctx.json === 'function') {
            const body = await ctx.json();
            reason = body.error ?? reason;
          }
        } catch {}
        alertWeb(reason);
        return;
      }

      const parsed = typeof data === 'string' ? JSON.parse(data) : data;
      if (parsed?.error) {
        alertWeb(parsed.error);
        return;
      }

      // Success — sign out locally and navigate immediately
      console.log('[settings] sign out after delete success');
      await supabase.auth.signOut();
      console.log('[settings] navigating to login');
      router.replace('/(auth)/login');
    } catch (err) {
      console.error('[settings] delete error:', err);
      alertWeb('Something went wrong. Please try again.');
    } finally {
      console.log('[settings] finally clearing loading');
      setDeleting(false);
    }
  }

  function handleDeleteAccount() {
    if (Platform.OS === 'web') {
      const first = window.confirm(
        'Delete Account\n\nThis will permanently delete your account, profile, and all associated data. Active listings will be cancelled. This cannot be undone.\n\nAre you sure?',
      );
      if (!first) return;
      const second = window.confirm(
        'Final Confirmation\n\nThis action is irreversible. Your account and data will be permanently deleted.\n\nProceed with deletion?',
      );
      if (!second) return;
      executeDeleteAccount();
    } else {
      Alert.alert(
        'Delete Account',
        'This will permanently delete your account, profile, and all associated data. Active listings will be cancelled.\n\nThis cannot be undone.',
        [
          { text: 'Cancel', style: 'cancel' },
          {
            text: 'Delete My Account',
            style: 'destructive',
            onPress: () => {
              Alert.alert(
                'Are you absolutely sure?',
                'This action is irreversible. Your account and data will be permanently deleted.',
                [
                  { text: 'Cancel', style: 'cancel' },
                  {
                    text: 'Yes, Delete Everything',
                    style: 'destructive',
                    onPress: executeDeleteAccount,
                  },
                ],
              );
            },
          },
        ],
      );
    }
  }

  return (
    <SafeAreaView style={s.safe}>

      {/* ── Top bar ───────────────────────────────────────────────────────── */}
      <View style={s.topBar}>
        <Pressable onPress={() => router.back()} style={s.backBtn} hitSlop={8}>
          <Text style={s.backArrow}>←</Text>
        </Pressable>
        <Text style={s.topTitle}>Settings</Text>
        <View style={s.backBtn} />
      </View>

      <ScrollView
        contentContainerStyle={s.scrollBody}
        showsVerticalScrollIndicator={false}
      >

        {/* ── ACCOUNT ─────────────────────────────────────────────────────── */}
        <SectionLabel text="Account" />
        <SettingsCard>
          <SettingsRow
            icon="👤"
            label="Edit Profile"
            onPress={() => nav('/settings/edit-profile')}
          />
          <SettingsRow
            icon="🔔"
            label="Notifications"
            onPress={() => nav('/settings/notifications')}
            showBorder={false}
          />
        </SettingsCard>

        {/* ── PAYMENTS ────────────────────────────────────────────────────── */}
        <SectionLabel text="Payments" />
        <SettingsCard>
          <SettingsRow
            icon="🏦"
            label="Payout Setup"
            onPress={() => nav('/settings/payout-setup')}
            showBorder={false}
          />
        </SettingsCard>

        {/* ── PREFERENCES ─────────────────────────────────────────────────── */}
        <SectionLabel text="Preferences" />
        <SettingsCard>
          <SettingsRow
            icon="📍"
            label="Your Scene"
            onPress={() => nav('/settings/preferences')}
            showBorder={false}
          />
        </SettingsCard>

        {/* ── SUPPORT ─────────────────────────────────────────────────────── */}
        <SectionLabel text="Support" />
        <SettingsCard>
          <SettingsRow
            icon="🙋"
            label="Help & Support"
            onPress={() => nav('/settings/support')}
          />
          <SettingsRow
            icon="📄"
            label="Terms of Service"
            onPress={() => nav('/settings/legal')}
          />
          <SettingsRow
            icon="🔒"
            label="Privacy Policy"
            onPress={() => nav('/settings/privacy')}
            showBorder={false}
          />
        </SettingsCard>

        {/* ── DANGER ──────────────────────────────────────────────────────── */}
        <SectionLabel text="Danger Zone" />
        <TouchableOpacity
          style={[s.signOutBtn, signingOut && { opacity: 0.6 }]}
          onPress={handleSignOut}
          disabled={signingOut}
          activeOpacity={0.8}
        >
          {signingOut
            ? <ActivityIndicator color={colors.error} size="small" />
            : <Text style={s.signOutText}>Sign Out</Text>
          }
        </TouchableOpacity>

        <TouchableOpacity
          style={[s.deleteBtn, deleting && { opacity: 0.6 }]}
          onPress={handleDeleteAccount}
          disabled={deleting}
          activeOpacity={0.8}
        >
          {deleting
            ? <ActivityIndicator color="#fff" size="small" />
            : <Text style={s.deleteText}>Delete Account</Text>
          }
        </TouchableOpacity>

        <View style={{ height: spacing.xxl }} />
      </ScrollView>
    </SafeAreaView>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.bg },

  // ── Top bar ────────────────────────────────────────────────────────────────
  topBar: {
    flexDirection:     'row',
    alignItems:        'center',
    justifyContent:    'space-between',
    paddingHorizontal: spacing.md,
    paddingVertical:   spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  backBtn:   { width: 44, height: 44, alignItems: 'flex-start', justifyContent: 'center' },
  backArrow: { color: colors.text, fontSize: fontSize.xl, fontWeight: '600' },
  topTitle:  { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },

  // ── Scroll body ───────────────────────────────────────────────────────────
  scrollBody: {
    paddingHorizontal: spacing.lg,
    paddingTop:        spacing.lg,
  },

  // ── Section label ─────────────────────────────────────────────────────────
  sectionLabel: {
    fontSize:      fontSize.xs,
    fontWeight:    '700',
    color:         colors.textDim,
    letterSpacing: 1.4,
    textTransform: 'uppercase',
    marginBottom:  spacing.sm,
    marginTop:     spacing.md,
  },

  // ── Card ──────────────────────────────────────────────────────────────────
  card: {
    backgroundColor: colors.bgCard,
    borderRadius:    radius.lg,
    borderWidth:     1,
    borderColor:     colors.border,
    overflow:        'hidden',   // clips ripple + last-row border
    marginBottom:    spacing.sm,
    ...shadow.card,
  },

  // ── Sign Out button ───────────────────────────────────────────────────────
  signOutBtn: {
    borderWidth:     1,
    borderColor:     colors.error,
    borderRadius:    radius.md,
    paddingVertical: spacing.md,
    alignItems:      'center',
    marginBottom:    spacing.sm,
  },
  signOutText: {
    color:         colors.error,
    fontWeight:    '700',
    fontSize:      fontSize.md,
    letterSpacing: 0.5,
  },

  // ── Delete Account button ─────────────────────────────────────────────
  deleteBtn: {
    backgroundColor: colors.error,
    borderRadius:    radius.md,
    paddingVertical: spacing.md,
    alignItems:      'center',
    marginBottom:    spacing.sm,
  },
  deleteText: {
    color:         '#fff',
    fontWeight:    '700',
    fontSize:      fontSize.md,
    letterSpacing: 0.5,
  },
});

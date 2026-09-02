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
import { useEffect, useState } from 'react';

import { supabase } from '@/src/lib/supabase';
import { colors, fontSize, radius, shadow, spacing } from '@/src/theme';

// ─── Types ────────────────────────────────────────────────────────────────────

type SettingsRoute =
  | '/settings/edit-profile'
  | '/settings/notifications'
  | '/settings/payout-setup'
  | '/settings/verify-phone'
  | '/settings/preferences'
  | '/settings/support'
  | '/settings/legal'
  | '/settings/privacy'
  | '/settings/blocked-users';

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
  // OR-17 tombstone deletion machine (Phase-2 cutover, 2026-09-02): own
  // deletion state, read from the caller's own kernel.identity_ext row
  // (owner-scoped SELECT policy; requires the kernel schema to be exposed via
  // PostgREST — live since the dark-substrate deploy). Pre-cutover backends
  // make the probe throw; we then show nothing, exactly like before.
  // Tri-state on purpose. A failed probe must NOT be read as "not pending":
  // the banner is the only route to withdrawing a deletion request, so hiding
  // it on a network blip would strand the user with no way to cancel.
  // 'unknown' keeps whatever we last knew and offers a retry instead.
  type DeletionView = 'unknown' | 'pending' | 'active';
  const [deletionView, setDeletionView] = useState<DeletionView>('unknown');
  const [deletionProbeFailed, setDeletionProbeFailed] = useState(false);
  const [withdrawing, setWithdrawing] = useState(false);
  const deletionPending = deletionView === 'pending';

  async function refreshDeletionState() {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) { setDeletionView('active'); setDeletionProbeFailed(false); return; }
      const { data: ext, error } = await (supabase as any)
        .schema('kernel')
        .from('identity_ext')
        .select('deletion_state')
        .eq('identity_id', user.id)
        .maybeSingle();
      if (error) {
        // Could not read. Hold the previous view and show a retry.
        setDeletionProbeFailed(true);
        return;
      }
      setDeletionProbeFailed(false);
      // A missing row is the lazy-create case and means no request exists.
      setDeletionView(ext?.deletion_state === 'DELETION_PENDING' ? 'pending' : 'active');
    } catch {
      setDeletionProbeFailed(true);
    }
  }

  useEffect(() => { refreshDeletionState(); }, []);

  async function handleWithdrawDeletion() {
    setWithdrawing(true);
    try {
      const { data, error } = await supabase.functions.invoke('delete-account', {
        body: { action: 'withdraw' },
      });
      const parsed = typeof data === 'string' ? JSON.parse(data) : data;
      if (error || parsed?.error) {
        alertWeb(parsed?.error ?? 'Could not withdraw the deletion request. Please try again.');
        return;
      }
      setDeletionView('active');
      setDeletionProbeFailed(false);
      if (Platform.OS === 'web') {
        window.alert('Your deletion request has been withdrawn. Your account stays active.');
      } else {
        Alert.alert('Request withdrawn', 'Your deletion request has been withdrawn. Your account stays active.');
      }
    } catch {
      alertWeb('Could not withdraw the deletion request. Please try again.');
    } finally {
      setWithdrawing(false);
    }
  }

  function nav(path: SettingsRoute) {
    // The new "/settings/blocked-users" route hasn't been picked up by
    // expo-router's typed-route manifest until the next dev-server
    // start / prebuild — cast through `any` so this compiles today.
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    router.push(path as any);
  }

  async function handleSignOut() {
    Alert.alert('Sign Out', 'Are you sure you want to sign out?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Sign Out',
        style: 'destructive',
        onPress: async () => {
          setSigningOut(true);
          try {
            await supabase.auth.signOut();
            router.replace('/(auth)/login');
          } catch {
            // Sign-out errors are surfaced to the user via the alert below.
            // The full error is captured by Sentry's auth state listener.
            alertWeb('Failed to sign out. Please try again.');
          } finally {
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
    setDeleting(true);
    try {
      const { data, error } = await supabase.functions.invoke('delete-account', { body: {} });

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
      await supabase.auth.signOut();
      router.replace('/(auth)/login');
    } catch {
      alertWeb('Something went wrong. Please try again.');
    } finally {
      setDeleting(false);
    }
  }

  function handleDeleteAccount() {
    if (Platform.OS === 'web') {
      const first = window.confirm(
        'Delete Account\n\nThis submits an account deletion request. Active listings will be cancelled and you will be signed out. While the request is pending you can sign back in and withdraw it from Settings. This cannot be undone.\n\nAre you sure?',
      );
      if (!first) return;
      const second = window.confirm(
        'Final Confirmation\n\nOnce the deletion request completes, this account can no longer be used to sign in.\n\nProceed with the deletion request?',
      );
      if (!second) return;
      executeDeleteAccount();
    } else {
      Alert.alert(
        'Delete Account',
        'This submits an account deletion request. Active listings will be cancelled and you will be signed out. While the request is pending you can sign back in and withdraw it from Settings.\n\nThis cannot be undone.',
        [
          { text: 'Cancel', style: 'cancel' },
          {
            text: 'Delete My Account',
            style: 'destructive',
            onPress: () => {
              Alert.alert(
                'Are you absolutely sure?',
                'Once the deletion request completes, this account can no longer be used to sign in.',
                [
                  { text: 'Cancel', style: 'cancel' },
                  {
                    text: 'Yes, Request Deletion',
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

        {deletionProbeFailed && !deletionPending && (
          <View style={{ borderColor: 'rgba(255,255,255,0.2)', borderWidth: 1, padding: 12, marginBottom: 16 }}>
            <Text style={{ color: 'rgba(255,255,255,0.7)', marginBottom: 8 }}>
              We could not check your account status.
            </Text>
            <Pressable onPress={refreshDeletionState}>
              <Text style={{ color: '#FF1A1A', fontWeight: '700' }}>Retry</Text>
            </Pressable>
          </View>
        )}

        {deletionPending && (
          <View style={{ backgroundColor: '#FFF4F4', borderColor: '#FF1A1A', borderWidth: 1, borderRadius: 0, padding: 14, marginBottom: 16 }}>
            <Text style={{ fontWeight: '700', marginBottom: 6 }}>Account deletion requested</Text>
            <Text style={{ marginBottom: 10 }}>
              Your account deletion request is pending. You can withdraw it to keep your account.
            </Text>
            <Pressable
              onPress={handleWithdrawDeletion}
              disabled={withdrawing}
              style={{ backgroundColor: '#FF1A1A', paddingVertical: 10, alignItems: 'center', opacity: withdrawing ? 0.6 : 1 }}
            >
              <Text style={{ color: '#FFFFFF', fontWeight: '700' }}>
                {withdrawing ? 'Withdrawing…' : 'Withdraw deletion request'}
              </Text>
            </Pressable>
          </View>
        )}

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
          />
          <SettingsRow
            icon="📱"
            label="Phone Verification"
            onPress={() => nav('/settings/verify-phone')}
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

        {/* ── SAFETY ──────────────────────────────────────────────────────── */}
        <SectionLabel text="Safety" />
        <SettingsCard>
          <SettingsRow
            icon="🚫"
            label="Blocked Users"
            onPress={() => nav('/settings/blocked-users')}
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

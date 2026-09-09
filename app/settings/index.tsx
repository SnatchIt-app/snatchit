/**
 * app/settings/index.tsx — Settings hub (V2).
 *
 * PRESENTATION rebuilt on the V2 account primitives (AccountSection + SettingsRow,
 * no emoji, no cards); ALL behaviour is unchanged. The OR-17 tombstone deletion
 * machine keeps its tri-state (unknown / pending / active) read from the caller's
 * own kernel.identity_ext row, the probe-failed retry, the withdraw flow, the
 * AppState foreground re-check, the sign-out confirm, and the double-confirm
 * delete-account flow — every edge-function call and confirmation is preserved. A
 * failed probe is still never read as "not pending".
 *
 * The settings SUB-screens (edit profile, notifications, preferences, blocked
 * users, payout setup, legal, privacy, support) are separate routes and keep their
 * current UI this batch; the hub only links to them.
 */

import { router } from 'expo-router';
import { Alert, AppState, Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useEffect, useState } from 'react';

import { supabase } from '@/src/lib/supabase';
import { Button, IconButton } from '@/src/components/ui';
import { AccountSection } from '@/src/components/account/AccountSection';
import { SettingsRow } from '@/src/components/account/SettingsRow';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

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

export default function SettingsScreen() {
  const insets = useSafeAreaInsets();

  const [signingOut, setSigningOut] = useState(false);
  const [deleting, setDeleting] = useState(false);

  // OR-17 tombstone deletion machine. Tri-state ON PURPOSE: a failed probe must
  // NOT be read as "not pending" — the banner is the only route to withdrawing,
  // so hiding it on a blip would strand the user. 'unknown' holds the last view
  // and offers a retry.
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
      if (error) { setDeletionProbeFailed(true); return; }
      setDeletionProbeFailed(false);
      if (ext?.deletion_state === 'DELETION_PENDING') { setDeletionView('pending'); return; }
      // A null row is ambiguous (lazy-created row, expired session, policy miss).
      // Never let that CANCEL a banner already shown.
      if (!ext && deletionView === 'pending') { setDeletionProbeFailed(true); return; }
      setDeletionView('active');
    } catch {
      setDeletionProbeFailed(true);
    }
  }

  useEffect(() => {
    refreshDeletionState();
    const sub = AppState.addEventListener('change', (st) => {
      if (st === 'active') refreshDeletionState();
    });
    return () => sub.remove();
  }, []);

  async function handleWithdrawDeletion() {
    setWithdrawing(true);
    try {
      const { data, error } = await supabase.functions.invoke('delete-account', { body: { action: 'withdraw' } });
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
    router.push(path as any);
  }

  function alertWeb(msg: string) {
    if (Platform.OS === 'web') { window.alert(msg); } else { Alert.alert('Error', msg); }
  }

  async function handleSignOut() {
    Alert.alert('Sign out', 'Are you sure you want to sign out?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Sign out',
        style: 'destructive',
        onPress: async () => {
          setSigningOut(true);
          try {
            await supabase.auth.signOut();
            router.replace('/(auth)/login');
          } catch {
            alertWeb('Failed to sign out. Please try again.');
          } finally {
            setSigningOut(false);
          }
        },
      },
    ]);
  }

  // Human labels for the live-rail obligation tokens returned by delete-account
  // (public.account_deletion_blockers → { kind, ref_id }). Unknown kinds fall
  // back to the token itself.
  const OBLIGATION_LABELS: Record<string, string> = {
    pending_payment: 'a payment that is still processing',
    paid_no_transfer: 'a paid order whose ticket transfer has not been created',
    active_transfer: 'a ticket transfer that has not completed',
    unsettled_transfer: 'a ticket transfer that has not completed',
    unpaid_seller_obligation: 'a seller payout that has not been paid',
    pending_refund: 'a refund that is still processing',
    reversal_required: 'a payout under review',
    open_manual_review: 'a payout under review',
  };
  function notifyDeletionAccepted(parsed: any): Promise<void> {
    const raw: unknown = parsed?.pending_obligations;
    const kinds: string[] = Array.isArray(raw)
      ? raw.map((o: any) => (typeof o === 'string' ? o : String(o?.kind ?? ''))).filter(Boolean)
      : [];
    const labels = Array.from(new Set(kinds.map((k) => OBLIGATION_LABELS[k] ?? k)));
    const title = 'Deletion request accepted';
    const body = labels.length > 0
      ? `Your account will be deleted automatically once the following settle:\n\n• ${labels.join('\n• ')}\n\nUntil then you can sign back in at any time to check on it or withdraw the request. You will be signed out now.`
      : 'Nothing is pending, so your account will be deleted automatically within a few minutes. You will be signed out now.';
    if (Platform.OS === 'web') {
      window.alert(`${title}\n\n${body}`);
      return Promise.resolve();
    }
    return new Promise((resolve) => {
      Alert.alert(title, body, [{ text: 'OK', onPress: () => resolve() }], { cancelable: false, onDismiss: () => resolve() });
    });
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

      // Accepted (OR-17: a request is always accepted). Say so, and say what is
      // still pending BEFORE signing out: the terminal step waits for every
      // money obligation to settle (option B, PFA-32) and the person must know
      // completion is not immediate. `pending_obligations` is additive — an
      // older edge simply omits it.
      await notifyDeletionAccepted(parsed);
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
        'Delete Account\n\nThis submits an account deletion request. Active listings will be cancelled and you will be signed out. While the request is pending you can sign back in and withdraw it from Settings. Until it completes you can withdraw it from Settings. After it completes this cannot be undone.\n\nAre you sure?',
      );
      if (!first) return;
      const second = window.confirm(
        'Final Confirmation\n\nOnce the deletion request completes, this account can no longer be used to sign in.\n\nProceed with the deletion request?',
      );
      if (!second) return;
      executeDeleteAccount();
    } else {
      Alert.alert(
        'Delete account',
        'This submits an account deletion request. Active listings will be cancelled and you will be signed out. While the request is pending you can sign back in and withdraw it from Settings.\n\nUntil it completes you can withdraw it from Settings. After it completes this cannot be undone.',
        [
          { text: 'Cancel', style: 'cancel' },
          {
            text: 'Delete my account',
            style: 'destructive',
            onPress: () => {
              Alert.alert(
                'Are you absolutely sure?',
                'Once the deletion request completes, this account can no longer be used to sign in.',
                [
                  { text: 'Cancel', style: 'cancel' },
                  { text: 'Yes, request deletion', style: 'destructive', onPress: executeDeleteAccount },
                ],
              );
            },
          },
        ],
      );
    }
  }

  return (
    <View style={s.root}>
      {/* ── Header ──────────────────────────────────────────── */}
      <View style={[s.header, { paddingTop: insets.top + v2.space.sm }]}>
        <IconButton glyph="back" onPress={() => router.back()} accessibilityLabel="Back" />
        <Text style={[textStyle('displaySm'), s.headerTitle]} accessibilityRole="header">Settings</Text>
        <View style={s.headerSpacer} />
      </View>

      <ScrollView contentContainerStyle={s.scroll} showsVerticalScrollIndicator={false}>
        {/* ── Deletion banners ──────────────────────────────── */}
        {deletionProbeFailed && !deletionPending ? (
          <View style={s.probeBanner} accessibilityRole="alert">
            <Text style={[textStyle('bodySm'), s.probeText]}>We could not check your account status.</Text>
            <Pressable onPress={refreshDeletionState} hitSlop={8} accessibilityRole="button" accessibilityLabel="Retry">
              <Text style={[textStyle('label'), s.retry]}>Retry</Text>
            </Pressable>
          </View>
        ) : null}

        {deletionPending ? (
          <View style={s.pendingBanner} accessibilityRole="alert">
            <Text style={[textStyle('title'), s.pendingTitle]}>Account deletion requested</Text>
            <Text style={[textStyle('bodySm'), s.pendingBody]}>
              Your account deletion request is pending. You can withdraw it to keep your account.
            </Text>
            <Button
              label="Withdraw deletion request"
              onPress={handleWithdrawDeletion}
              loading={withdrawing}
              disabled={withdrawing}
              block
            />
          </View>
        ) : null}

        {/* ── Account ───────────────────────────────────────── */}
        <AccountSection title="Account">
          <SettingsRow label="Edit profile" onPress={() => nav('/settings/edit-profile')} />
          <SettingsRow label="Notifications" onPress={() => nav('/settings/notifications')} />
          <SettingsRow label="Phone verification" onPress={() => nav('/settings/verify-phone')} />
        </AccountSection>

        {/* ── Payments ──────────────────────────────────────── */}
        <AccountSection title="Payments">
          <SettingsRow label="Payout setup" onPress={() => nav('/settings/payout-setup')} />
        </AccountSection>

        {/* ── Preferences ───────────────────────────────────── */}
        <AccountSection title="Preferences">
          <SettingsRow label="Your scene" description="Neighborhoods you follow" onPress={() => nav('/settings/preferences')} />
        </AccountSection>

        {/* ── Safety ────────────────────────────────────────── */}
        <AccountSection title="Safety">
          <SettingsRow label="Blocked users" onPress={() => nav('/settings/blocked-users')} />
        </AccountSection>

        {/* ── Support ───────────────────────────────────────── */}
        <AccountSection title="Support">
          <SettingsRow label="Help & support" onPress={() => nav('/settings/support')} />
          <SettingsRow label="Terms of service" onPress={() => nav('/settings/legal')} />
          <SettingsRow label="Privacy policy" onPress={() => nav('/settings/privacy')} />
        </AccountSection>

        {/* ── Account actions ───────────────────────────────── */}
        <View style={s.actions}>
          <Button label="Sign out" variant="secondary" onPress={handleSignOut} loading={signingOut} disabled={signingOut} block />
          <Button label="Delete account" variant="destructive" onPress={handleDeleteAccount} loading={deleting} disabled={deleting} block />
        </View>
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: v2.surface.canvas },

  header: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: v2.space.md, paddingBottom: v2.space.sm,
    borderBottomWidth: 1, borderBottomColor: v2.border.default,
  },
  headerTitle: { color: v2.text.primary },
  headerSpacer: { width: 44 },

  scroll: { paddingHorizontal: v2.space.lg, paddingBottom: v2.space.xxxl },

  probeBanner: {
    marginTop: v2.space.lg, padding: v2.space.md,
    borderWidth: 1, borderColor: v2.border.strong,
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: v2.space.md,
  },
  probeText: { color: v2.text.secondary, flex: 1 },
  retry: { color: v2.brand.red },

  pendingBanner: {
    marginTop: v2.space.lg, padding: v2.space.lg, gap: v2.space.sm,
    backgroundColor: v2.surface.surface, borderWidth: 1, borderColor: v2.brand.red,
  },
  pendingTitle: { color: v2.text.primary },
  pendingBody: { color: v2.text.secondary, marginBottom: v2.space.xs },

  actions: { marginTop: v2.space.xxl, gap: v2.space.md },
});

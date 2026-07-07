import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  AppState,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import type { AppStateStatus } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import * as WebBrowser from 'expo-web-browser';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { colors, fontSize, radius, shadow, spacing } from '@/src/theme';

// Deep-link the Stripe-hosted onboarding return back into the app via the
// `snatchit://` scheme (declared in app.json `scheme` + CFBundleURLSchemes
// in Info.plist). iOS's ASWebAuthenticationSession watches for any URL
// starting with this pattern and auto-closes the in-app browser as soon as
// it sees one — returning the seller seamlessly to the app.
//
// Stripe's actual `return_url` / `refresh_url` are HTTPS (per Stripe's
// requirements); the hosted /payout-return and /payout-refresh pages may
// optionally trigger the deep link via `window.location.href` to invoke
// auto-close. With or without that optimization, the session always
// terminates cleanly when the user taps Done, and we re-check status on
// every result type.
const PAYOUT_AUTH_CALLBACK = 'snatchit://payout-return';

type PayoutStatus = 'not_connected' | 'onboarding_required' | 'connected';

export default function PayoutSetupScreen() {
  const { session } = useAuth();
  const userId = session?.user.id ?? '';

  const [status, setStatus] = useState<PayoutStatus>('not_connected');
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);

  // ── Debounced status check ──────────────────────────────────────────────
  // Mount, focus, and AppState all call requestStatusCheck(). A debounce
  // timer ensures only one real network call fires per burst.
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const checkingRef = useRef(false);

  const checkStatusReal = useCallback(async () => {
    if (checkingRef.current) return;   // already in-flight
    checkingRef.current = true;

    if (!userId) {
      setLoading(false);
      checkingRef.current = false;
      return;
    }

    try {
      // Quick local check: does a stripe_connect_id even exist?
      const { data: profile } = await supabase
        .from('profiles')
        .select('stripe_connect_id')
        .eq('id', userId)
        .single();

      if (!profile?.stripe_connect_id) {
        setStatus('not_connected');
        setLoading(false);
        checkingRef.current = false;
        return;
      }

      // Account exists — ask the edge function for the real Stripe status
      // (details_submitted). 6 s hard timeout so a slow Stripe round-trip
      // can never freeze this screen behind the loading spinner.
      const result = await Promise.race([
        supabase.functions.invoke('create-connect-account', { body: { status_only: true } }),
        new Promise<{ data: null; error: { message: string } }>((resolve) =>
          setTimeout(() => resolve({ data: null, error: { message: 'timeout' } }), 6000),
        ),
      ]);
      const { data, error } = result as { data: unknown; error: { message: string } | null };

      if (!error && data) {
        const parsed = typeof data === 'string' ? JSON.parse(data) : data;
        const serverStatus = parsed?.status as PayoutStatus | undefined;
        if (serverStatus === 'connected' || serverStatus === 'onboarding_required' || serverStatus === 'not_connected') {
          setStatus(serverStatus);
        }
        // If serverStatus is unrecognised, keep previous status — don't regress
      }
      // On error: keep whatever status we already have. Never regress to
      // onboarding_required just because a network call failed.
    } catch {
      // Keep current status on network errors
    }

    setLoading(false);
    checkingRef.current = false;
  }, [userId]);

  const requestStatusCheck = useCallback(() => {
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      checkStatusReal();
    }, 300);
  }, [checkStatusReal]);

  // ── Refresh on mount ─────────────────────────────────────────────────────
  useEffect(() => {
    requestStatusCheck();
  }, [requestStatusCheck]);

  // ── Refresh when app returns to foreground ──────────────────────────────
  const appStateRef = useRef<AppStateStatus>(AppState.currentState);
  useEffect(() => {
    const sub = AppState.addEventListener('change', (nextState) => {
      if (appStateRef.current.match(/inactive|background/) && nextState === 'active') {
        requestStatusCheck();
      }
      appStateRef.current = nextState;
    });
    return () => sub.remove();
  }, [requestStatusCheck]);

  // ── Refresh when screen regains focus (e.g. navigating back) ───────────
  useFocusEffect(
    useCallback(() => {
      requestStatusCheck();
    }, [requestStatusCheck]),
  );

  // ── Handle button tap ───────────────────────────────────────────────────
  async function handleSetup() {
    setSubmitting(true);

    // Web: pre-open a blank tab BEFORE the async call so the browser treats
    // it as part of the user gesture. Popup blockers kill window.open()
    // calls that happen after an await.
    let webWindow: Window | null = null;
    if (Platform.OS === 'web' && typeof window !== 'undefined') {
      webWindow = window.open('', '_blank');
    }

    try {
      const { data, error: fnError } = await supabase.functions.invoke<{ url: string; status: string }>(
        'create-connect-account',
        {
          body: {},
        },
      );

      if (fnError || !data) {
        let reason = fnError?.message ?? 'Failed to set up payouts';
        try {
          const ctx = (fnError as any)?.context;
          if (ctx && typeof ctx.json === 'function') {
            const body = await ctx.json();
            reason = body.error ?? body.message ?? reason;
            if (body.status) {
              setStatus(body.status as PayoutStatus);
            }
          }
        } catch {}
        if (webWindow) webWindow.close();
        if (Platform.OS === 'web') {
          window.alert(reason);
        } else {
          Alert.alert('Error', reason);
        }
        setSubmitting(false);
        return;
      }

      const parsed = typeof data === 'string' ? JSON.parse(data) : data;
      const url: string | undefined = parsed?.url;
      const returnedStatus = parsed?.status as PayoutStatus | undefined;

      if (returnedStatus) {
        setStatus(returnedStatus);
      }

      if (!url || typeof url !== 'string' || !(url.startsWith('https://') || url.startsWith('http://'))) {
        if (webWindow) webWindow.close();
        if (Platform.OS === 'web') {
          window.alert('Unable to open payout dashboard right now. Please try again.');
        } else {
          Alert.alert('Error', 'Unable to open payout dashboard right now. Please try again.');
        }
        setSubmitting(false);
        return;
      }

      if (Platform.OS === 'web') {
        // Navigate the pre-opened tab to the Stripe URL.
        if (webWindow) {
          webWindow.location.href = url;
        } else {
          // Fallback: direct navigation if pre-open was blocked
          window.location.href = url;
        }
      } else {
        // ── In-app browser flow (iOS / Android native) ───────────────────
        // Use ASWebAuthenticationSession (iOS) / Chrome Custom Tabs (Android)
        // via expo-web-browser so the seller never leaves the app shell.
        // The session auto-closes if the in-browser page navigates to
        // PAYOUT_AUTH_CALLBACK, and resolves with `type: 'dismiss'` if the
        // user taps Done before that. We re-check Stripe status on every
        // outcome — success, cancel, or dismiss — so the visible state is
        // always derived from Stripe's authoritative `details_submitted`
        // rather than from the browser-session result.
        try {
          const result = await WebBrowser.openAuthSessionAsync(
            url,
            PAYOUT_AUTH_CALLBACK,
          );
          // result.type ∈ 'success' | 'cancel' | 'dismiss' | 'locked' | 'opened'
          // We log only for observability; do NOT branch behavior on it.
          console.log('[payout-setup] auth session ended:', result.type);
        } catch (browserErr) {
          // openAuthSessionAsync can throw if the OS denies the session
          // (e.g. another auth session already running). Treat exactly
          // like a dismiss and let the status check be the source of truth.
          console.warn('[payout-setup] openAuthSessionAsync threw:', browserErr);
        }
        // Force-refresh status now (not waiting on AppState change) so the
        // seller sees their new "Connected" state immediately on return.
        await checkStatusReal();
      }
      // AppState listener + useFocusEffect will also re-check when user returns
    } catch {
      if (webWindow) webWindow.close();
      if (Platform.OS === 'web') {
        window.alert('Something went wrong. Please try again.');
      } else {
        Alert.alert('Error', 'Something went wrong. Please try again.');
      }
    }

    setSubmitting(false);
  }

  // ── UI copy per state ───────────────────────────────────────────────────
  const uiMap: Record<PayoutStatus, {
    icon: string;
    title: string;
    description: string;
    dotColor: string;
    statusLabel: string;
    statusSub: string;
    btnLabel: string;
  }> = {
    not_connected: {
      icon: '\u{1F3E6}',
      title: 'Set Up Payouts',
      description: 'Verify your identity and add a bank account to get paid. This usually takes about 2 minutes. Anyone can sell — no business registration needed.',
      dotColor: colors.warning,
      statusLabel: 'Not connected',
      statusSub: 'Selling as an individual is the default.',
      btnLabel: 'Set Up Payouts',
    },
    onboarding_required: {
      icon: '\u{1F3E6}',
      title: 'Complete Payout Setup',
      description: 'Almost there — finish verifying your identity and adding a bank account to get paid. This usually takes about 2 minutes.',
      dotColor: colors.warning,
      statusLabel: 'Onboarding incomplete',
      statusSub: 'Tap below to continue where you left off.',
      btnLabel: 'Continue Setup',
    },
    connected: {
      icon: '\u2705',
      title: 'Payouts Connected',
      description: 'Your Stripe account is connected. Payouts will be deposited automatically when your listings sell.',
      dotColor: colors.success,
      statusLabel: 'Connected',
      statusSub: 'Your banking details are securely managed by Stripe.',
      btnLabel: 'Manage Payouts',
    },
  };

  const ui = uiMap[status];

  return (
    <SafeAreaView style={s.safe}>
      <View style={s.topBar}>
        <Pressable onPress={() => router.back()} style={s.backBtn} hitSlop={8}>
          <Text style={s.backArrow}>{'\u2190'}</Text>
        </Pressable>
        <Text style={s.topTitle}>Payout Setup</Text>
        <View style={s.backBtn} />
      </View>

      {loading ? (
        <View style={s.center}>
          <ActivityIndicator color={colors.primary} size="large" />
        </View>
      ) : (
        <View style={s.body}>
          <Text style={s.icon}>{ui.icon}</Text>
          <Text style={s.title}>{ui.title}</Text>
          <Text style={s.description}>{ui.description}</Text>

          <View style={s.statusCard}>
            <View style={s.statusRow}>
              <View style={[s.statusDot, { backgroundColor: ui.dotColor }]} />
              <Text style={[s.statusText, { color: ui.dotColor }]}>
                {ui.statusLabel}
              </Text>
            </View>
            <Text style={s.statusSub}>{ui.statusSub}</Text>
          </View>

          <Pressable
            style={[s.actionBtn, submitting && s.actionBtnDisabled]}
            onPress={handleSetup}
            disabled={submitting}
          >
            {submitting ? (
              <ActivityIndicator color={colors.text} size="small" />
            ) : (
              <Text style={s.actionBtnText}>{ui.btnLabel}</Text>
            )}
          </Pressable>

          {status !== 'connected' && (
            <Pressable
              style={s.refreshBtn}
              onPress={() => { setLoading(true); checkStatusReal(); }}
            >
              <Text style={s.refreshBtnText}>Refresh Status</Text>
            </Pressable>
          )}

          <View style={s.infoNote}>
            <Text style={s.infoNoteText}>
              Your banking details are never stored on our servers. All payouts are processed securely through Stripe Connect.
            </Text>
          </View>
        </View>
      )}
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe:   { flex: 1, backgroundColor: colors.bg },
  center: { flex: 1, justifyContent: 'center', alignItems: 'center' },

  topBar:    { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
               paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
               borderBottomWidth: 1, borderBottomColor: colors.border },
  backBtn:   { width: 44, height: 44, alignItems: 'flex-start', justifyContent: 'center' },
  backArrow: { color: colors.text, fontSize: fontSize.xl, fontWeight: '600' },
  topTitle:  { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },

  body: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: spacing.xl, gap: spacing.md },
  icon: { fontSize: 56 },
  title: { fontSize: fontSize.xl, fontWeight: '900', color: colors.text, textAlign: 'center' },
  description: { fontSize: fontSize.sm, color: colors.textMuted, textAlign: 'center', lineHeight: 22, paddingHorizontal: spacing.md },

  statusCard: { backgroundColor: colors.bgCard, borderRadius: radius.lg, borderWidth: 1, borderColor: colors.border,
                padding: spacing.lg, width: '100%', marginTop: spacing.sm, gap: spacing.sm, ...shadow.card },
  statusRow:  { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  statusDot:  { width: 8, height: 8, borderRadius: 4 },
  statusText: { fontSize: fontSize.sm, fontWeight: '700' },
  statusSub:  { fontSize: fontSize.xs, color: colors.textMuted, lineHeight: 18 },

  actionBtn:         { backgroundColor: colors.primary, borderRadius: radius.md, paddingVertical: 14, paddingHorizontal: spacing.xl, alignItems: 'center', width: '100%', marginTop: spacing.sm },
  actionBtnDisabled: { opacity: 0.6 },
  actionBtnText:     { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },

  refreshBtn:        { alignItems: 'center', paddingVertical: 10, width: '100%' },
  refreshBtnText:    { color: colors.textMuted, fontSize: fontSize.sm, fontWeight: '600', textDecorationLine: 'underline' },

  infoNote:     { paddingHorizontal: spacing.md, marginTop: spacing.sm },
  infoNoteText: { fontSize: fontSize.xs, color: colors.textDim, lineHeight: 16, textAlign: 'center' },
});

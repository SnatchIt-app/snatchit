/**
 * app/settings/payout-setup.tsx — Payout setup (V2).
 *
 * PRESENTATION-ONLY pass. Stripe Connect is untouched: the debounced status probe
 * (`get_my_profile` + the `create-connect-account` status_only edge function with
 * its 6s timeout), the mount/focus/AppState re-checks, the
 * `openAuthSessionAsync` deep-link onboarding flow with the `snatchit://`
 * callback, and the "never regress status on a network error" rule are all
 * preserved. Status is derived from Stripe's authoritative `details_submitted`;
 * the UI never implies money is available before that.
 */

import { useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, AppState, Platform, StyleSheet, Text, View } from 'react-native';
import type { AppStateStatus } from 'react-native';
import * as WebBrowser from 'expo-web-browser';

import { supabase } from '@/src/lib/supabase';
import type { MyProfileRPC } from '@/src/types';
import { useAuth } from '@/src/hooks/useAuth';
import { Badge, Button, Spinner } from '@/src/components/ui';
import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

const PAYOUT_AUTH_CALLBACK = 'snatchit://payout-return';

type PayoutStatus = 'not_connected' | 'onboarding_required' | 'connected';

export default function PayoutSetupScreen() {
  const { session } = useAuth();
  const userId = session?.user.id ?? '';

  const [status, setStatus] = useState<PayoutStatus>('not_connected');
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);

  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const checkingRef = useRef(false);

  const checkStatusReal = useCallback(async () => {
    if (checkingRef.current) return;
    checkingRef.current = true;
    if (!userId) { setLoading(false); checkingRef.current = false; return; }
    try {
      const { data: profile } = await supabase.rpc('get_my_profile').returns<MyProfileRPC[]>().maybeSingle();
      if (!profile?.stripe_connect_id) { setStatus('not_connected'); setLoading(false); checkingRef.current = false; return; }
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
      }
      // On error / unrecognised: keep the current status. Never regress on a blip.
    } catch {
      // keep current status
    }
    setLoading(false);
    checkingRef.current = false;
  }, [userId]);

  const requestStatusCheck = useCallback(() => {
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => { checkStatusReal(); }, 300);
  }, [checkStatusReal]);

  useEffect(() => { requestStatusCheck(); }, [requestStatusCheck]);

  const appStateRef = useRef<AppStateStatus>(AppState.currentState);
  useEffect(() => {
    const sub = AppState.addEventListener('change', (nextState) => {
      if (appStateRef.current.match(/inactive|background/) && nextState === 'active') requestStatusCheck();
      appStateRef.current = nextState;
    });
    return () => sub.remove();
  }, [requestStatusCheck]);

  useFocusEffect(useCallback(() => { requestStatusCheck(); }, [requestStatusCheck]));

  async function handleSetup() {
    setSubmitting(true);
    let webWindow: Window | null = null;
    if (Platform.OS === 'web' && typeof window !== 'undefined') webWindow = window.open('', '_blank');
    try {
      const { data, error: fnError } = await supabase.functions.invoke<{ url: string; status: string }>('create-connect-account', { body: {} });
      if (fnError || !data) {
        let reason = fnError?.message ?? 'Failed to set up payouts';
        try {
          const ctx = (fnError as any)?.context;
          if (ctx && typeof ctx.json === 'function') {
            const body = await ctx.json();
            reason = body.error ?? body.message ?? reason;
            if (body.status) setStatus(body.status as PayoutStatus);
          }
        } catch {}
        if (webWindow) webWindow.close();
        if (Platform.OS === 'web') window.alert(reason); else Alert.alert('Error', reason);
        setSubmitting(false);
        return;
      }
      const parsed = typeof data === 'string' ? JSON.parse(data) : data;
      const url: string | undefined = parsed?.url;
      const returnedStatus = parsed?.status as PayoutStatus | undefined;
      if (returnedStatus) setStatus(returnedStatus);
      if (!url || typeof url !== 'string' || !(url.startsWith('https://') || url.startsWith('http://'))) {
        if (webWindow) webWindow.close();
        const msg = 'Unable to open payout dashboard right now. Please try again.';
        if (Platform.OS === 'web') window.alert(msg); else Alert.alert('Error', msg);
        setSubmitting(false);
        return;
      }
      if (Platform.OS === 'web') {
        if (webWindow) webWindow.location.href = url; else window.location.href = url;
      } else {
        try {
          const result = await WebBrowser.openAuthSessionAsync(url, PAYOUT_AUTH_CALLBACK);
          console.log('[payout-setup] auth session ended:', result.type);
        } catch (browserErr) {
          console.warn('[payout-setup] openAuthSessionAsync threw:', browserErr);
        }
        await checkStatusReal();
      }
    } catch {
      if (webWindow) webWindow.close();
      const msg = 'Something went wrong. Please try again.';
      if (Platform.OS === 'web') window.alert(msg); else Alert.alert('Error', msg);
    }
    setSubmitting(false);
  }

  const uiMap: Record<PayoutStatus, { title: string; description: string; tone: 'success' | 'warning'; statusLabel: string; statusSub: string; btnLabel: string }> = {
    not_connected: {
      title: 'Set up payouts',
      description: 'Verify your identity and add a bank account to get paid. This usually takes about 2 minutes. Anyone can sell, no business registration needed.',
      tone: 'warning', statusLabel: 'Not connected', statusSub: 'Selling as an individual is the default.', btnLabel: 'Set up payouts',
    },
    onboarding_required: {
      title: 'Complete payout setup',
      description: 'Almost there. Finish verifying your identity and adding a bank account to get paid. This usually takes about 2 minutes.',
      tone: 'warning', statusLabel: 'Onboarding incomplete', statusSub: 'Continue where you left off.', btnLabel: 'Continue setup',
    },
    connected: {
      title: 'Payouts connected',
      description: 'Your account is connected. Payouts deposit automatically when your listings sell.',
      tone: 'success', statusLabel: 'Connected', statusSub: 'Your banking details are securely managed by Stripe.', btnLabel: 'Manage payouts',
    },
  };
  const ui = uiMap[status];

  return (
    <View style={s.root}>
      <SettingsHeader title="Payout setup" />
      {loading ? (
        <View style={s.center}><Spinner color={v2.brand.red} /></View>
      ) : (
        <View style={s.body}>
          <Text style={[textStyle('displayMd'), s.title]} accessibilityRole="header">{ui.title}</Text>
          <Text style={[textStyle('body'), s.description]}>{ui.description}</Text>

          <View style={s.statusCard}>
            <Badge label={ui.statusLabel} tone={ui.tone} />
            <Text style={[textStyle('bodySm'), s.statusSub]}>{ui.statusSub}</Text>
          </View>

          <View style={s.actions}>
            <Button label={ui.btnLabel} onPress={handleSetup} loading={submitting} disabled={submitting} block />
            {status !== 'connected' ? (
              <Button label="Refresh status" variant="ghost" onPress={() => { setLoading(true); checkStatusReal(); }} block />
            ) : null}
          </View>

          <Text style={[textStyle('bodySm'), s.note]}>
            Your banking details are never stored on our servers. Payouts are processed securely through Stripe Connect.
          </Text>
        </View>
      )}
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: v2.surface.canvas },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },

  body: { flex: 1, paddingHorizontal: v2.space.lg, paddingTop: v2.space.xxl, gap: v2.space.lg },
  title: { color: v2.text.primary },
  description: { color: v2.text.secondary },

  statusCard: {
    borderWidth: 1, borderColor: v2.border.default, backgroundColor: v2.surface.surface,
    padding: v2.space.lg, gap: v2.space.sm, alignItems: 'flex-start',
  },
  statusSub: { color: v2.text.muted },

  actions: { gap: v2.space.sm, marginTop: v2.space.sm },
  note: { color: v2.text.muted, marginTop: v2.space.md },
});

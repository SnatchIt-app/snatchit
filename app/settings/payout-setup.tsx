import { router } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Linking,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { supabase, supabaseUrl, supabaseAnonKey } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { colors, fontSize, radius, shadow, spacing } from '@/src/theme';

export default function PayoutSetupScreen() {
  const { session } = useAuth();
  const userId = session?.user.id ?? '';

  const [connected, setConnected] = useState(false);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);

  const checkStatus = useCallback(async () => {
    if (!userId) return;
    const { data } = await supabase
      .from('profiles')
      .select('stripe_connect_id')
      .eq('id', userId)
      .single();
    setConnected(!!data?.stripe_connect_id);
    setLoading(false);
  }, [userId]);

  useEffect(() => { checkStatus(); }, [checkStatus]);

  async function handleSetup() {
    setSubmitting(true);

    const { data: { session: currentSession } } = await supabase.auth.getSession();
    if (!currentSession?.access_token) {
      Alert.alert('Error', 'Not authenticated. Please sign in.');
      setSubmitting(false);
      return;
    }

    try {
      const res = await fetch(`${supabaseUrl}/functions/v1/create-connect-account`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${currentSession.access_token}`,
          'apikey': supabaseAnonKey!,
        },
        body: JSON.stringify({
          refresh_url: 'snatchit://settings/payout-setup',
          return_url: 'snatchit://settings/payout-setup',
        }),
      });

      const data = await res.json();

      if (!res.ok) {
        Alert.alert('Error', data.error || 'Failed to set up payouts');
        setSubmitting(false);
        return;
      }

      if (data.url) {
        await Linking.openURL(data.url);
        // Re-check status when they come back
        setTimeout(() => checkStatus(), 2000);
      }
    } catch (err) {
      Alert.alert('Error', 'Something went wrong. Please try again.');
    }

    setSubmitting(false);
  }

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
          <Text style={s.icon}>{connected ? '\u2705' : '\U0001F3E6'}</Text>
          <Text style={s.title}>{connected ? 'Payouts Connected' : 'Set Up Payouts'}</Text>
          <Text style={s.description}>
            {connected
              ? 'Your Stripe account is connected. Payouts will be deposited automatically when your listings sell.'
              : 'Connect your bank account via Stripe to receive payouts when your listings sell.'}
          </Text>

          <View style={s.statusCard}>
            <View style={s.statusRow}>
              <View style={[s.statusDot, { backgroundColor: connected ? colors.success : colors.warning }]} />
              <Text style={[s.statusText, { color: connected ? colors.success : colors.warning }]}>
                {connected ? 'Connected' : 'Not connected'}
              </Text>
            </View>
            <Text style={s.statusSub}>
              {connected
                ? 'Your banking details are securely managed by Stripe.'
                : 'Set up takes just a few minutes.'}
            </Text>
          </View>

          <Pressable
            style={[s.actionBtn, submitting && s.actionBtnDisabled]}
            onPress={handleSetup}
            disabled={submitting}
          >
            {submitting ? (
              <ActivityIndicator color={colors.text} size="small" />
            ) : (
              <Text style={s.actionBtnText}>
                {connected ? 'Manage Payouts' : 'Set Up Payouts'}
              </Text>
            )}
          </Pressable>

          {!connected && (
            <Pressable
              style={s.refreshBtn}
              onPress={() => { setLoading(true); checkStatus(); }}
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

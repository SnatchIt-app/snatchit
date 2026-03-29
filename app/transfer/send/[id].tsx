import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { colors, fontSize, radius, spacing } from '@/src/theme';

type Transfer = {
  id: string;
  listing_id: string;
  status: string;
  transfer_method: string;
  expires_at: string | null;
  buyer: { display_name: string | null; email: string | null };
  listing: { title: string | null; event_name: string | null };
};

function formatCountdown(expiresAt: string | null): string | null {
  if (!expiresAt) return null;
  const diff = new Date(expiresAt).getTime() - Date.now();
  if (diff <= 0) return 'Expired';
  const h = Math.floor(diff / 3_600_000);
  const m = Math.floor((diff % 3_600_000) / 60_000);
  if (h > 0) return `${h}h ${m}m remaining`;
  return `${m}m remaining`;
}

export default function TransferSendScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { session } = useAuth();
  const userId = session?.user.id ?? '';

  const [transfer, setTransfer] = useState<Transfer | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [code, setCode] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [countdown, setCountdown] = useState<string | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const fetchTransfer = useCallback(async () => {
    if (!userId || !id) return;
    setLoading(true);

    const { data, error: fetchErr } = await supabase
      .from('transfers')
      .select('id, listing_id, status, transfer_method, expires_at, buyer:profiles!buyer_id(display_name, email), listing:listings!listing_id(title, event_name)')
      .eq('id', id)
      .eq('seller_id', userId)
      .single();

    if (fetchErr || !data) {
      setError('Transfer not found');
    } else {
      setTransfer(data as unknown as Transfer);
    }
    setLoading(false);
  }, [id, userId]);

  useEffect(() => { fetchTransfer(); }, [fetchTransfer]);

  // Countdown timer
  useEffect(() => {
    if (!transfer?.expires_at) return;
    setCountdown(formatCountdown(transfer.expires_at));
    timerRef.current = setInterval(() => {
      setCountdown(formatCountdown(transfer.expires_at));
    }, 60_000);
    return () => { if (timerRef.current) clearInterval(timerRef.current); };
  }, [transfer?.expires_at]);

  async function handleSend() {
    if (!code.trim()) {
      Alert.alert('Required', 'Please enter the transfer confirmation code.');
      return;
    }
    setSubmitting(true);

    const { error: rpcErr } = await supabase.rpc('seller_send_transfer', {
      p_transfer_id: id,
      p_transfer_code: code.trim(),
    });

    setSubmitting(false);

    if (rpcErr) {
      Alert.alert('Error', rpcErr.message);
      return;
    }

    Alert.alert('Sent', 'Transfer has been marked as sent.', [
      { text: 'OK', onPress: () => router.back() },
    ]);
  }

  if (loading) {
    return (
      <SafeAreaView style={s.safe}>
        <View style={s.center}>
          <ActivityIndicator color={colors.primary} size="large" />
        </View>
      </SafeAreaView>
    );
  }

  if (error || !transfer) {
    return (
      <SafeAreaView style={s.safe}>
        <View style={s.topBar}>
          <Pressable onPress={() => router.back()} style={s.backBtn} hitSlop={8}>
            <Text style={s.backArrow}>{'\u2190'}</Text>
          </Pressable>
          <Text style={s.topTitle}>Send Transfer</Text>
          <View style={s.backBtn} />
        </View>
        <View style={s.center}>
          <Text style={s.errorText}>{error || 'Transfer not found'}</Text>
        </View>
      </SafeAreaView>
    );
  }

  const alreadySent = transfer.status === 'seller_sent' || transfer.status === 'buyer_confirmed';

  return (
    <SafeAreaView style={s.safe}>
      <View style={s.topBar}>
        <Pressable onPress={() => router.back()} style={s.backBtn} hitSlop={8}>
          <Text style={s.backArrow}>{'\u2190'}</Text>
        </Pressable>
        <Text style={s.topTitle}>Send Transfer</Text>
        <View style={s.backBtn} />
      </View>

      <View style={s.content}>
        {/* Step-by-step instructions */}
        {!alreadySent && (
          <View style={s.stepsCard}>
            <Text style={s.stepsTitle}>How to transfer</Text>
            <Text style={s.step}>1. Open your ticketing app (Ticketmaster, AXS, etc.)</Text>
            <Text style={s.step}>2. Find the ticket and tap "Transfer"</Text>
            <Text style={s.step}>3. Send the ticket to the buyer</Text>
            <Text style={s.step}>4. Enter the confirmation code below and tap "Mark as Sent"</Text>
          </View>
        )}

        {/* Countdown */}
        {countdown && !alreadySent && (
          <View style={[s.countdownBanner, countdown === 'Expired' && s.countdownExpired]}>
            <Text style={[s.countdownText, countdown === 'Expired' && s.countdownExpiredText]}>
              {countdown === 'Expired' ? '⚠️  Transfer window expired' : `⏱  ${countdown}`}
            </Text>
          </View>
        )}

        <View style={s.card}>
          <Text style={s.label}>Listing</Text>
          <Text style={s.value}>{transfer.listing?.title || transfer.listing?.event_name || 'Untitled'}</Text>

          <Text style={s.label}>Buyer</Text>
          <Text style={s.value}>{transfer.buyer?.display_name || transfer.buyer?.email || 'Unknown'}</Text>

          <Text style={s.label}>Transfer Method</Text>
          <Text style={s.value}>{transfer.transfer_method.replace('_', ' ')}</Text>

          <Text style={s.label}>Status</Text>
          <Text style={[s.value, alreadySent && s.statusSent]}>
            {transfer.status.replace('_', ' ')}
          </Text>
        </View>

        {alreadySent ? (
          <View style={s.sentBanner}>
            <Text style={s.sentText}>
              {transfer.status === 'buyer_confirmed'
                ? 'The buyer has confirmed receipt.'
                : 'Transfer has been sent. Waiting for buyer confirmation.'}
            </Text>
          </View>
        ) : (
          <>
            <Text style={s.inputLabel}>
              {transfer.transfer_method === 'email'
                ? 'Transfer confirmation code / details'
                : 'Transfer confirmation code'}
            </Text>
            <TextInput
              style={s.input}
              value={code}
              onChangeText={setCode}
              placeholder="Enter code"
              placeholderTextColor={colors.textPlaceholder}
              autoCapitalize="none"
              autoCorrect={false}
            />

            <Pressable
              style={[s.sendBtn, submitting && s.sendBtnDisabled]}
              onPress={handleSend}
              disabled={submitting}
            >
              {submitting ? (
                <ActivityIndicator color={colors.text} size="small" />
              ) : (
                <Text style={s.sendBtnText}>Mark as Sent</Text>
              )}
            </Pressable>
          </>
        )}
      </View>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe:    { flex: 1, backgroundColor: colors.bg },
  center:  { flex: 1, justifyContent: 'center', alignItems: 'center' },

  topBar:    { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
               paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
               borderBottomWidth: 1, borderBottomColor: colors.border },
  backBtn:   { width: 44, height: 44, alignItems: 'flex-start', justifyContent: 'center' },
  backArrow: { color: colors.text, fontSize: fontSize.xl, fontWeight: '600' },
  topTitle:  { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },

  content: { padding: spacing.md },
  card:    { backgroundColor: colors.bgCard, borderRadius: radius.md, padding: spacing.md, marginBottom: spacing.lg },

  label: { color: colors.textMuted, fontSize: fontSize.xs, fontWeight: '600', marginTop: spacing.sm },
  value: { color: colors.text, fontSize: fontSize.md, fontWeight: '500', marginTop: spacing.xs },
  statusSent: { color: colors.success },

  sentBanner: { backgroundColor: colors.bgCard, borderRadius: radius.md, padding: spacing.md, alignItems: 'center' },
  sentText:   { color: colors.success, fontSize: fontSize.sm, fontWeight: '600', textAlign: 'center' },

  inputLabel: { color: colors.textMuted, fontSize: fontSize.sm, fontWeight: '600', marginBottom: spacing.xs },
  input: {
    backgroundColor: colors.bgInput, borderRadius: radius.md, borderWidth: 1, borderColor: colors.borderInput,
    color: colors.text, fontSize: fontSize.md, padding: spacing.md, marginBottom: spacing.lg,
  },

  sendBtn:         { backgroundColor: colors.primary, borderRadius: radius.md, paddingVertical: 14, alignItems: 'center' },
  sendBtnDisabled: { opacity: 0.6 },
  sendBtnText:     { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },

  errorText: { color: colors.error, fontSize: fontSize.md },

  // Steps
  stepsCard: {
    backgroundColor: colors.bgCard, borderRadius: radius.md, padding: spacing.md,
    marginBottom: spacing.md, borderWidth: 1, borderColor: colors.border,
  },
  stepsTitle: { color: colors.text, fontSize: fontSize.sm, fontWeight: '700', marginBottom: spacing.sm },
  step: { color: colors.textMuted, fontSize: fontSize.xs, lineHeight: 20, marginBottom: 4 },

  // Countdown
  countdownBanner: {
    backgroundColor: 'rgba(251,191,36,0.12)', borderRadius: radius.md,
    padding: spacing.sm, alignItems: 'center', marginBottom: spacing.md,
    borderWidth: 1, borderColor: colors.warning,
  },
  countdownExpired: { backgroundColor: 'rgba(255,77,109,0.1)', borderColor: colors.error },
  countdownText: { color: colors.warning, fontSize: fontSize.sm, fontWeight: '700' },
  countdownExpiredText: { color: colors.error },
});

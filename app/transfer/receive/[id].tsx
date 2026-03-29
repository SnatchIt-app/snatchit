import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { colors, fontSize, radius, spacing } from '@/src/theme';

type Transfer = {
  id: string;
  status: string;
  transfer_method: string;
  transfer_code: string | null;
  expires_at: string | null;
  seller: { display_name: string | null };
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

export default function TransferReceiveScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { session } = useAuth();
  const userId = session?.user.id ?? '';

  const [transfer, setTransfer] = useState<Transfer | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [countdown, setCountdown] = useState<string | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const fetchTransfer = useCallback(async () => {
    if (!userId || !id) return;
    setLoading(true);

    const { data, error: fetchErr } = await supabase
      .from('transfers')
      .select('id, status, transfer_method, transfer_code, expires_at, seller:profiles!seller_id(display_name), listing:listings!listing_id(title, event_name)')
      .eq('id', id)
      .eq('buyer_id', userId)
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

  async function handleConfirm() {
    setSubmitting(true);
    const { error: rpcErr } = await supabase.rpc('buyer_confirm_transfer', {
      p_transfer_id: id,
    });
    setSubmitting(false);

    if (rpcErr) {
      Alert.alert('Error', rpcErr.message);
      return;
    }
    Alert.alert('Confirmed', 'Transfer marked as received.', [
      { text: 'OK', onPress: () => router.back() },
    ]);
  }

  async function handleDispute() {
    Alert.alert(
      'Report Issue',
      'Are you sure you want to report an issue with this transfer?',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Report',
          style: 'destructive',
          onPress: async () => {
            setSubmitting(true);
            const { error: rpcErr } = await supabase.rpc('buyer_dispute_transfer', {
              p_transfer_id: id,
            });
            setSubmitting(false);

            if (rpcErr) {
              Alert.alert('Error', rpcErr.message);
              return;
            }
            Alert.alert('Reported', 'Issue has been reported. We will look into it.', [
              { text: 'OK', onPress: () => router.back() },
            ]);
          },
        },
      ],
    );
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
          <Text style={s.topTitle}>Receive Transfer</Text>
          <View style={s.backBtn} />
        </View>
        <View style={s.center}>
          <Text style={s.errorText}>{error || 'Transfer not found'}</Text>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={s.safe}>
      <View style={s.topBar}>
        <Pressable onPress={() => router.back()} style={s.backBtn} hitSlop={8}>
          <Text style={s.backArrow}>{'\u2190'}</Text>
        </Pressable>
        <Text style={s.topTitle}>Receive Transfer</Text>
        <View style={s.backBtn} />
      </View>

      <View style={s.content}>
        {/* Step-by-step instructions */}
        {(transfer.status === 'pending' || transfer.status === 'seller_sent') && (
          <View style={s.stepsCard}>
            <Text style={s.stepsTitle}>
              {transfer.status === 'pending' ? 'What happens next' : 'How to receive your ticket'}
            </Text>
            {transfer.status === 'pending' ? (
              <>
                <Text style={s.step}>1. The seller will transfer the ticket to you</Text>
                <Text style={s.step}>2. You'll get a notification when it's sent</Text>
                <Text style={s.step}>3. Check your ticketing app and confirm receipt here</Text>
              </>
            ) : (
              <>
                <Text style={s.step}>1. Open your ticketing app (Ticketmaster, AXS, etc.)</Text>
                <Text style={s.step}>2. Check for the incoming transfer</Text>
                <Text style={s.step}>3. Accept the ticket in your app</Text>
                <Text style={s.step}>4. Tap "Confirm Received" below</Text>
              </>
            )}
          </View>
        )}

        {/* Countdown */}
        {countdown && transfer.status !== 'buyer_confirmed' && (
          <View style={[s.countdownBanner, countdown === 'Expired' && s.countdownExpired]}>
            <Text style={[s.countdownText, countdown === 'Expired' && s.countdownExpiredText]}>
              {countdown === 'Expired' ? '⚠️  Transfer window expired' : `⏱  ${countdown}`}
            </Text>
          </View>
        )}

        <View style={s.card}>
          <Text style={s.label}>Listing</Text>
          <Text style={s.value}>{transfer.listing?.title || transfer.listing?.event_name || 'Untitled'}</Text>

          <Text style={s.label}>Seller</Text>
          <Text style={s.value}>{transfer.seller?.display_name || 'Unknown'}</Text>

          <Text style={s.label}>Transfer Method</Text>
          <Text style={s.value}>{transfer.transfer_method.replace('_', ' ')}</Text>
        </View>

        {transfer.status === 'pending' && (
          <View style={s.banner}>
            <Text style={s.bannerText}>Waiting for seller to send the transfer</Text>
          </View>
        )}

        {transfer.status === 'seller_sent' && (
          <>
            {transfer.transfer_code && (
              <View style={s.codeBox}>
                <Text style={s.label}>Transfer Code</Text>
                <Text style={s.codeText}>{transfer.transfer_code}</Text>
              </View>
            )}

            <Pressable
              style={[s.confirmBtn, submitting && s.btnDisabled]}
              onPress={handleConfirm}
              disabled={submitting}
            >
              {submitting ? (
                <ActivityIndicator color={colors.text} size="small" />
              ) : (
                <Text style={s.btnText}>Confirm Received</Text>
              )}
            </Pressable>

            <Pressable
              style={[s.disputeBtn, submitting && s.btnDisabled]}
              onPress={handleDispute}
              disabled={submitting}
            >
              {submitting ? (
                <ActivityIndicator color={colors.error} size="small" />
              ) : (
                <Text style={s.disputeBtnText}>Report Issue</Text>
              )}
            </Pressable>
          </>
        )}

        {transfer.status === 'buyer_confirmed' && (
          <View style={s.banner}>
            <Text style={[s.bannerText, { color: colors.success }]}>Transfer complete!</Text>
          </View>
        )}

        {transfer.status === 'disputed' && (
          <View style={s.banner}>
            <Text style={[s.bannerText, { color: colors.warning }]}>Issue reported — we're looking into it</Text>
          </View>
        )}
      </View>
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

  content: { padding: spacing.md },
  card:    { backgroundColor: colors.bgCard, borderRadius: radius.md, padding: spacing.md, marginBottom: spacing.lg },

  label: { color: colors.textMuted, fontSize: fontSize.xs, fontWeight: '600', marginTop: spacing.sm },
  value: { color: colors.text, fontSize: fontSize.md, fontWeight: '500', marginTop: spacing.xs },

  banner:     { backgroundColor: colors.bgCard, borderRadius: radius.md, padding: spacing.lg, alignItems: 'center' },
  bannerText: { color: colors.textMuted, fontSize: fontSize.sm, fontWeight: '600', textAlign: 'center' },

  codeBox:  { backgroundColor: colors.bgCard, borderRadius: radius.md, padding: spacing.md, marginBottom: spacing.lg },
  codeText: { color: colors.text, fontSize: fontSize.lg, fontWeight: '700', marginTop: spacing.xs, letterSpacing: 1 },

  confirmBtn:  { backgroundColor: colors.primary, borderRadius: radius.md, paddingVertical: 14, alignItems: 'center', marginBottom: spacing.sm },
  disputeBtn:  { backgroundColor: 'transparent', borderRadius: radius.md, borderWidth: 1, borderColor: colors.border, paddingVertical: 14, alignItems: 'center', marginBottom: spacing.lg },
  btnDisabled: { opacity: 0.6 },
  btnText:        { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },
  disputeBtnText: { color: colors.error, fontSize: fontSize.md, fontWeight: '600' },

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

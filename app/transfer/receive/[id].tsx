/**
 * app/transfer/receive/[id].tsx — Buyer Transfer Receive Screen
 *
 * Phase A enhancements:
 *   - Collects buyer delivery info (email/phone) via DeliveryInfoForm
 *   - Shows platform-specific receiving instructions via PlatformInstructions
 *   - Preserves existing confirm / dispute / countdown behaviour
 */

import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Image,
  Linking,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import DeliveryInfoForm from '@/src/components/DeliveryInfoForm';
import PlatformInstructions from '@/src/components/PlatformInstructions';
import { normalizeUSPhone } from '@/src/utils/phone';
import { colors, fontSize, radius, spacing } from '@/src/theme';
import type { TicketPlatform, TransferMethod } from '@/src/types';

// ─── Local types ─────────────────────────────────────────────────────────────

type TransferData = {
  id: string;
  status: string;
  transfer_method: TransferMethod;
  expires_at: string | null;
  delivery_email: string | null;
  delivery_phone: string | null;
  transfer_evidence_path: string | null;
  seller: { display_name: string | null };
  listing: {
    event_name: string | null;
    ticket_platform: TicketPlatform | null;
  };
};

// ─── Helpers ─────────────────────────────────────────────────────────────────

function formatCountdown(expiresAt: string | null): string | null {
  if (!expiresAt) return null;
  const diff = new Date(expiresAt).getTime() - Date.now();
  if (diff <= 0) return 'Expired';
  const h = Math.floor(diff / 3_600_000);
  const m = Math.floor((diff % 3_600_000) / 60_000);
  if (h > 0) return `${h}h ${m}m remaining`;
  return `${m}m remaining`;
}

// ─── Screen ──────────────────────────────────────────────────────────────────

export default function TransferReceiveScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { session } = useAuth();
  const userId = session?.user.id ?? '';

  const [transfer, setTransfer] = useState<TransferData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [savingDelivery, setSavingDelivery] = useState(false);
  const [countdown, setCountdown] = useState<string | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Seller's sent-proof: signed URL into the PRIVATE proof-docs bucket. RLS
  // (migration 034) only lets this transfer's buyer/seller read the object.
  const [proofUrl, setProofUrl] = useState<string | null>(null);

  useEffect(() => {
    const path = transfer?.transfer_evidence_path;
    if (!path || transfer?.status !== 'seller_sent') { setProofUrl(null); return; }
    let active = true;
    supabase.storage.from('proof-docs').createSignedUrl(path, 60 * 60)
      .then(({ data }) => { if (active) setProofUrl(data?.signedUrl ?? null); })
      .catch(() => { if (active) setProofUrl(null); });
    return () => { active = false; };
  }, [transfer?.transfer_evidence_path, transfer?.status]);

  // ── Fetch ──────────────────────────────────────────────────────────────────

  const fetchTransfer = useCallback(async () => {
    if (!userId || !id) return;
    setLoading(true);

    const { data, error: fetchErr } = await supabase
      .from('transfers')
      .select(
        'id, status, transfer_method, expires_at, delivery_email, delivery_phone, transfer_evidence_path, ' +
        'seller:profiles!seller_id(display_name), ' +
        'listing:listings!listing_id(event_name, ticket_platform)',
      )
      .eq('id', id)
      .eq('buyer_id', userId)
      .single();

    if (fetchErr || !data) {
      setError('Transfer not found');
    } else {
      setTransfer(data as unknown as TransferData);
    }
    setLoading(false);
  }, [id, userId]);

  useEffect(() => { fetchTransfer(); }, [fetchTransfer]);

  // ── Countdown ──────────────────────────────────────────────────────────────

  useEffect(() => {
    if (!transfer?.expires_at) return;
    setCountdown(formatCountdown(transfer.expires_at));
    timerRef.current = setInterval(() => {
      setCountdown(formatCountdown(transfer.expires_at));
    }, 60_000);
    return () => { if (timerRef.current) clearInterval(timerRef.current); };
  }, [transfer?.expires_at]);

  // ── Delivery info submit ───────────────────────────────────────────────────

  async function handleDeliverySubmit(email: string | null, phone: string | null) {
    if (!id) return;
    setSavingDelivery(true);

    // Defense in depth: DeliveryInfoForm normalizes before calling us, but
    // re-normalize here so even programmatic callers (tests, future hooks)
    // can't push a malformed phone into the RPC.
    const safePhone = phone ? normalizeUSPhone(phone) : null;

    const { error: rpcErr } = await supabase.rpc('set_transfer_delivery_info', {
      p_transfer_id:    id,
      p_delivery_email: email,
      p_delivery_phone: safePhone,
    });

    setSavingDelivery(false);

    if (rpcErr) {
      Alert.alert('Error', rpcErr.message);
      return;
    }

    // Update local state immediately so the gate clears
    setTransfer(prev =>
      prev ? { ...prev, delivery_email: email, delivery_phone: safePhone } : prev,
    );

    // Also re-fetch to ensure server state is fully in sync
    fetchTransfer();
  }

  // ── Confirm received ───────────────────────────────────────────────────────

  async function handleConfirm() {
    if (!id) return;
    setSubmitting(true);

    try {
      const { data, error: fnError } = await supabase.functions.invoke(
        'confirm-and-release',
        { body: { transfer_id: id } },
      );

      setSubmitting(false);

      if (fnError) {
        let message = 'Something went wrong. Please try again.';
        try {
          const ctx = (fnError as any).context;
          if (ctx && typeof ctx.json === 'function') {
            const body = await ctx.json();
            if (body?.error) message = body.error;
          } else {
            const body = typeof data === 'string' ? JSON.parse(data) : data;
            if (body?.error) message = body.error;
          }
        } catch { /* ignore parse errors */ }
        Alert.alert('Error', message);
        return;
      }

      setTransfer(prev => prev ? { ...prev, status: 'buyer_confirmed' } : prev);
      Alert.alert('Confirmed!', 'Transfer complete. Enjoy the event!');
    } catch (err) {
      setSubmitting(false);
      Alert.alert('Error', 'Something went wrong. Please try again.');
    }
  }

  // ── Dispute ────────────────────────────────────────────────────────────────

  async function handleDispute() {
    Alert.alert(
      'Report Issue',
      'Are you sure you want to report a problem with this transfer? This will freeze the transfer and notify support.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Report Issue',
          style: 'destructive',
          onPress: async () => {
            setSubmitting(true);
            const { error: rpcErr } = await supabase.rpc('buyer_dispute_transfer', {
              p_transfer_id: id,
            });
            setSubmitting(false);

            if (rpcErr) {
              Alert.alert(
                "Couldn't submit dispute",
                'Please try again in a moment. If the problem persists, contact support.',
              );
              console.warn('[receive] buyer_dispute_transfer error:', rpcErr.message);
              return;
            }
            setTransfer(prev => prev ? { ...prev, status: 'disputed' } : prev);
            Alert.alert('Reported', 'The transfer has been flagged. Support will review.');
          },
        },
      ],
    );
  }

  // ── Derived values ─────────────────────────────────────────────────────────

  const platform: TicketPlatform = transfer?.listing?.ticket_platform ?? 'other';
  const transferMethod: TransferMethod = (transfer?.transfer_method as TransferMethod) ?? 'email';

  const needsDeliveryInfo =
    transfer != null &&
    (transfer.status === 'pending' || transfer.status === 'seller_sent') &&
    !transfer.delivery_email &&
    !transfer.delivery_phone;

  // ── Loading state ──────────────────────────────────────────────────────────

  if (loading) {
    return (
      <SafeAreaView style={s.safe}>
        <View style={s.center}>
          <ActivityIndicator color={colors.primary} size="large" />
        </View>
      </SafeAreaView>
    );
  }

  // ── Error state ────────────────────────────────────────────────────────────

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

  // ── Main render ────────────────────────────────────────────────────────────

  return (
    <SafeAreaView style={s.safe}>
      <View style={s.topBar}>
        <Pressable onPress={() => router.back()} style={s.backBtn} hitSlop={8}>
          <Text style={s.backArrow}>{'\u2190'}</Text>
        </Pressable>
        <Text style={s.topTitle}>Receive Transfer</Text>
        <View style={s.backBtn} />
      </View>

      <ScrollView contentContainerStyle={s.content} keyboardShouldPersistTaps="handled">

        {/* ── Delivery info form (REQUIRED before any other action) ── */}
        {needsDeliveryInfo && (
          <>
            <View style={s.deliveryGateBanner}>
              <Text style={s.deliveryGateText}>
                Please provide your delivery info so the seller knows where to send your tickets.
              </Text>
            </View>
            <DeliveryInfoForm
              transferMethod={transferMethod}
              onSubmit={handleDeliverySubmit}
              loading={savingDelivery}
            />
          </>
        )}

        {/* ── Platform-specific receiving instructions ────────────── */}
        {(transfer.status === 'pending' || transfer.status === 'seller_sent') && !needsDeliveryInfo && (
          <PlatformInstructions
            platform={platform}
            role="buyer"
            buyerEmail={transfer.delivery_email}
            buyerPhone={transfer.delivery_phone}
          />
        )}

        {/* ── Countdown ───────────────────────────────────────────── */}
        {countdown && transfer.status !== 'buyer_confirmed' && (
          <View style={[s.countdownBanner, countdown === 'Expired' && s.countdownExpired]}>
            <Text style={[s.countdownText, countdown === 'Expired' && s.countdownExpiredText]}>
              {countdown === 'Expired'
                ? '\u26A0\uFE0F  Transfer window expired'
                : `\u23F1  ${countdown}`}
            </Text>
          </View>
        )}

        {/* ── Transfer details card ───────────────────────────────── */}
        <View style={s.card}>
          <Text style={s.label}>Event</Text>
          <Text style={s.value}>{transfer.listing?.event_name || 'Untitled'}</Text>

          <Text style={s.label}>Seller</Text>
          <Text style={s.value}>{transfer.seller?.display_name || 'Unknown'}</Text>

          <Text style={s.label}>Transfer Method</Text>
          <Text style={s.value}>{transfer.transfer_method.replace('_', ' ')}</Text>

          {transfer.delivery_email && (
            <>
              <Text style={s.label}>Your Delivery Email</Text>
              <Text style={s.value}>{transfer.delivery_email}</Text>
            </>
          )}
          {transfer.delivery_phone && (
            <>
              <Text style={s.label}>Your Delivery Phone</Text>
              <Text style={s.value}>{transfer.delivery_phone}</Text>
            </>
          )}
        </View>

        {/* ── Pending state ───────────────────────────────────────── */}
        {transfer.status === 'pending' && !needsDeliveryInfo && (
          <View style={s.banner}>
            <Text style={s.bannerText}>
              Waiting for the seller to send the transfer
            </Text>
          </View>
        )}

        {/* ── Seller sent → confirm / dispute ─────────────────────── */}
        {transfer.status === 'seller_sent' && !needsDeliveryInfo && (
          <>
            {proofUrl && (
              <View style={s.proofBlock}>
                <Text style={s.proofLabel}>Seller's proof of transfer</Text>
                <Pressable onPress={() => Linking.openURL(proofUrl)}>
                  <Image source={{ uri: proofUrl }} style={s.proofImage} resizeMode="contain" />
                </Pressable>
                <Text style={s.proofHint}>Tap to open full size. Review it before confirming.</Text>
              </View>
            )}

            <View style={s.confirmPrompt}>
              <Text style={s.confirmPromptText}>
                By confirming, you release payment to the seller. Only confirm if
                you can see the tickets in your account.
              </Text>
            </View>

            <Pressable
              style={[s.confirmBtn, submitting && s.btnDisabled]}
              onPress={handleConfirm}
              disabled={submitting}
            >
              {submitting ? (
                <ActivityIndicator color={colors.text} size="small" />
              ) : (
                <Text style={s.btnText}>I Got My Tickets</Text>
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
                <Text style={s.disputeBtnText}>I Haven't Received Them</Text>
              )}
            </Pressable>
          </>
        )}

        {/* ── Confirmed state ─────────────────────────────────────── */}
        {transfer.status === 'buyer_confirmed' && (
          <View style={s.banner}>
            <Text style={[s.bannerText, { color: colors.success }]}>
              Transfer complete!
            </Text>
          </View>
        )}

        {/* ── Disputed state ──────────────────────────────────────── */}
        {transfer.status === 'disputed' && (
          <View style={s.banner}>
            <Text style={[s.bannerText, { color: colors.warning }]}>
              Issue reported — our team will review within 24 hours.{'\n'}
              Your payment is protected.
            </Text>
          </View>
        )}

        <View style={{ height: 48 }} />
      </ScrollView>
    </SafeAreaView>
  );
}

// ─── Styles ──────────────────────────────────────────────────────────────────

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
  card:    { backgroundColor: colors.bgCard, borderRadius: radius.md, padding: spacing.md,
             marginBottom: spacing.lg },

  label: { color: colors.textMuted, fontSize: fontSize.xs, fontWeight: '600', marginTop: spacing.sm },
  value: { color: colors.text, fontSize: fontSize.md, fontWeight: '500', marginTop: spacing.xs },

  banner:     { backgroundColor: colors.bgCard, borderRadius: radius.md, padding: spacing.lg,
                alignItems: 'center' },
  bannerText: { color: colors.textMuted, fontSize: fontSize.sm, fontWeight: '600',
                textAlign: 'center', lineHeight: 22 },

  proofBlock: {
    marginBottom: spacing.md,
  },
  proofLabel: {
    color: colors.text,
    fontSize: fontSize.sm,
    fontWeight: '600',
    marginBottom: spacing.xs,
  },
  proofImage: {
    width: '100%',
    height: 220,
    borderRadius: radius.md,
    backgroundColor: colors.bgCard,
  },
  proofHint: {
    color: colors.textMuted,
    fontSize: fontSize.xs,
    marginTop: spacing.xs,
  },

  confirmPrompt: {
    backgroundColor: 'rgba(251,191,36,0.10)',
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.warning,
    padding: spacing.sm,
    marginBottom: spacing.md,
  },
  confirmPromptText: {
    color: colors.warning,
    fontSize: fontSize.xs,
    lineHeight: 18,
    textAlign: 'center',
  },

  confirmBtn:  { backgroundColor: colors.primary, borderRadius: radius.md, paddingVertical: 14,
                 alignItems: 'center', marginBottom: spacing.sm },
  disputeBtn:  { backgroundColor: 'transparent', borderRadius: radius.md, borderWidth: 1,
                 borderColor: colors.border, paddingVertical: 14, alignItems: 'center',
                 marginBottom: spacing.lg },
  btnDisabled: { opacity: 0.6 },
  btnText:        { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },
  disputeBtnText: { color: colors.error, fontSize: fontSize.md, fontWeight: '600' },

  errorText: { color: colors.error, fontSize: fontSize.md },

  // Delivery info gate
  deliveryGateBanner: {
    backgroundColor: 'rgba(251,191,36,0.12)',
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.warning,
    padding: spacing.md,
    marginBottom: spacing.md,
  },
  deliveryGateText: {
    color: colors.warning,
    fontSize: fontSize.sm,
    fontWeight: '600',
    textAlign: 'center',
    lineHeight: 20,
  },

  // Countdown
  countdownBanner: {
    backgroundColor: 'rgba(251,191,36,0.12)', borderRadius: radius.md,
    padding: spacing.sm, alignItems: 'center', marginBottom: spacing.md,
    borderWidth: 1, borderColor: colors.warning,
  },
  countdownExpired: { backgroundColor: 'rgba(255,77,109,0.1)', borderColor: colors.error },
  countdownText:    { color: colors.warning, fontSize: fontSize.sm, fontWeight: '700' },
  countdownExpiredText: { color: colors.error },
});

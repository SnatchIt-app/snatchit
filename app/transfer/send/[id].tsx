/**
 * app/transfer/send/[id].tsx — Seller Transfer Send Screen
 *
 * Phase A enhancements:
 *   - Shows buyer delivery info (email / phone) so seller knows where to send
 *   - Shows platform-specific sending instructions via PlatformInstructions
 *   - Requires transfer evidence upload before marking as sent
 *   - Calls extended mark_transfer_sent RPC with evidence path
 *   - Shows post-send waiting state with auto-release countdown
 */

import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { useImageUpload } from '@/src/hooks/useImageUpload';
import { ImageUploadTile } from '@/src/components/ImageUploadTile';
import PlatformInstructions from '@/src/components/PlatformInstructions';
import ScreenState from '@/src/components/ScreenState';
import { isNetworkError } from '@/src/hooks/useNetworkStatus';
import { colors, fontSize, radius, spacing } from '@/src/theme';
import type { TicketPlatform, TransferMethod } from '@/src/types';

// ─── Local types ─────────────────────────────────────────────────────────────

type TransferData = {
  id: string;
  listing_id: string;
  status: string;
  transfer_method: TransferMethod;
  expires_at: string | null;
  auto_release_at: string | null;
  delivery_email: string | null;
  delivery_phone: string | null;
  transfer_evidence_path: string | null;
  buyer: { display_name: string | null };
  listing: {
    event_name: string | null;
    ticket_platform: TicketPlatform | null;
  };
};

// ─── Helpers ─────────────────────────────────────────────────────────────────

function formatCountdown(ts: string | null): string | null {
  if (!ts) return null;
  const diff = new Date(ts).getTime() - Date.now();
  if (diff <= 0) return 'Expired';
  const h = Math.floor(diff / 3_600_000);
  const m = Math.floor((diff % 3_600_000) / 60_000);
  if (h > 0) return `${h}h ${m}m remaining`;
  return `${m}m remaining`;
}

// ─── Screen ──────────────────────────────────────────────────────────────────

export default function TransferSendScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { session } = useAuth();
  const userId = session?.user.id ?? '';

  const [transfer, setTransfer] = useState<TransferData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);

  // Countdown timers
  const [expiryCountdown, setExpiryCountdown] = useState<string | null>(null);
  const [releaseCountdown, setReleaseCountdown] = useState<string | null>(null);
  const expiryTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const releaseTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Evidence upload
  const evidenceUpload = useImageUpload({
    userId,
    folder: 'transfer-evidence',
    aspect: null,
    quality: 0.85,
    bucket: 'proof-docs',   // PRIVATE — only buyer/seller/admin can read (migration 034)
  });

  // ── Fetch ──────────────────────────────────────────────────────────────────

  const fetchTransfer = useCallback(async () => {
    if (!userId || !id) return;
    setLoading(true);

    const { data, error: fetchErr } = await supabase
      .from('transfers')
      .select(
        'id, listing_id, status, transfer_method, expires_at, auto_release_at, ' +
        'delivery_email, delivery_phone, transfer_evidence_path, ' +
        'buyer:profiles!buyer_id(display_name), ' +
        'listing:listings!listing_id(event_name, ticket_platform)',
      )
      .eq('id', id)
      .eq('seller_id', userId)
      .single();

    if (fetchErr || !data) {
      // Connectivity failure gets the offline screen; a genuine miss
      // (bad id / not this seller's transfer) keeps "Transfer not found".
      setError(fetchErr && isNetworkError(fetchErr) ? '__offline__' : 'Transfer not found');
    } else {
      setError('');
      setTransfer(data as unknown as TransferData);
    }
    setLoading(false);
  }, [id, userId]);

  useEffect(() => { fetchTransfer(); }, [fetchTransfer]);

  // ── Expiry countdown (pending state — seller has 24h to send) ──────────────

  useEffect(() => {
    if (!transfer?.expires_at || transfer.status !== 'pending') return;
    setExpiryCountdown(formatCountdown(transfer.expires_at));
    expiryTimerRef.current = setInterval(() => {
      setExpiryCountdown(formatCountdown(transfer.expires_at));
    }, 60_000);
    return () => { if (expiryTimerRef.current) clearInterval(expiryTimerRef.current); };
  }, [transfer?.expires_at, transfer?.status]);

  // ── Auto-release countdown (seller_sent state — buyer has 72h to confirm) ──

  useEffect(() => {
    if (!transfer?.auto_release_at || transfer.status !== 'seller_sent') return;
    setReleaseCountdown(formatCountdown(transfer.auto_release_at));
    releaseTimerRef.current = setInterval(() => {
      setReleaseCountdown(formatCountdown(transfer.auto_release_at));
    }, 60_000);
    return () => { if (releaseTimerRef.current) clearInterval(releaseTimerRef.current); };
  }, [transfer?.auto_release_at, transfer?.status]);

  // ── Mark as sent ───────────────────────────────────────────────────────────

  async function handleMarkSent() {
    if (!id || !userId) return;

    // Evidence image is required
    if (!evidenceUpload.localUri) {
      Alert.alert('Evidence required', 'Please upload a screenshot of the transfer confirmation before marking as sent.');
      return;
    }

    setSubmitting(true);

    try {
      // 1. Upload evidence image
      const evidencePath = await evidenceUpload.uploadImage();
      if (!evidencePath) {
        const msg = evidenceUpload.error ?? 'Unknown upload error.';
        Alert.alert('Upload failed', msg);
        setSubmitting(false);
        return;
      }

      // 2. Call extended RPC
      const { error: rpcErr } = await supabase.rpc('mark_transfer_sent', {
        p_transfer_id: id,
        p_user_id: userId,
        p_transfer_evidence_path: evidencePath,
      });

      setSubmitting(false);

      if (rpcErr) {
        Alert.alert('Error', rpcErr.message);
        return;
      }

      // 3. Update local state
      setTransfer(prev => prev ? {
        ...prev,
        status: 'seller_sent',
        transfer_evidence_path: evidencePath,
      } : prev);
      Alert.alert('Sent!', 'Transfer marked as sent. Waiting for buyer to confirm receipt.');
    } catch (err) {
      setSubmitting(false);
      Alert.alert('Error', 'Something went wrong. Please try again.');
    }
  }

  // ── Derived values ─────────────────────────────────────────────────────────

  const platform: TicketPlatform = transfer?.listing?.ticket_platform ?? 'other';
  const alreadySent = transfer?.status === 'seller_sent'
    || transfer?.status === 'buyer_confirmed'
    || transfer?.status === 'auto_released';
  const busy = submitting || evidenceUpload.status === 'uploading';
  const buyerDeliveryMissing = !transfer?.delivery_email && !transfer?.delivery_phone;

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
          <Text style={s.topTitle}>Send Transfer</Text>
          <View style={s.backBtn} />
        </View>
        {error === '__offline__' ? (
          <ScreenState state="offline" onRetry={fetchTransfer} />
        ) : (
          <View style={s.center}>
            <Text style={s.errorText}>{error || 'Transfer not found'}</Text>
          </View>
        )}
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
        <Text style={s.topTitle}>Send Transfer</Text>
        <View style={s.backBtn} />
      </View>

      <ScrollView contentContainerStyle={s.content} keyboardShouldPersistTaps="handled">

        {/* ── Buyer delivery info card ────────────────────────────── */}
        <View style={s.deliveryCard}>
          <Text style={s.deliveryTitle}>Send tickets to</Text>
          {transfer.delivery_email ? (
            <View style={s.deliveryRow}>
              <Text style={s.deliveryLabel}>Email</Text>
              <Text style={s.deliveryValue}>{transfer.delivery_email}</Text>
            </View>
          ) : null}
          {transfer.delivery_phone ? (
            <View style={s.deliveryRow}>
              <Text style={s.deliveryLabel}>Phone</Text>
              <Text style={s.deliveryValue}>{transfer.delivery_phone}</Text>
            </View>
          ) : null}
          {buyerDeliveryMissing && (
            <View style={s.deliveryMissingBox}>
              <Text style={s.deliveryMissingTitle}>Delivery info not yet provided</Text>
              <Text style={s.deliveryMissingText}>
                {"The buyer must provide their delivery info before you can send tickets. They'll be prompted to do so when they open the transfer."}
              </Text>
            </View>
          )}
        </View>

        {/* ── Platform-specific sending instructions ──────────────── */}
        {!alreadySent && (
          <PlatformInstructions
            platform={platform}
            role="seller"
            buyerEmail={transfer.delivery_email}
            buyerPhone={transfer.delivery_phone}
          />
        )}

        {/* ── Expiry countdown (pending) ──────────────────────────── */}
        {expiryCountdown && transfer.status === 'pending' && (
          <View style={[s.countdownBanner, expiryCountdown === 'Expired' && s.countdownExpired]}>
            <Text style={[s.countdownText, expiryCountdown === 'Expired' && s.countdownExpiredText]}>
              {expiryCountdown === 'Expired'
                ? '\u26A0\uFE0F  Transfer window expired'
                : `\u23F1  ${expiryCountdown} to send`}
            </Text>
          </View>
        )}

        {/* ── Transfer details card ───────────────────────────────── */}
        <View style={s.card}>
          <Text style={s.label}>Event</Text>
          <Text style={s.value}>{transfer.listing?.event_name || 'Untitled'}</Text>

          <Text style={s.label}>Buyer</Text>
          <Text style={s.value}>{transfer.buyer?.display_name || 'Unknown'}</Text>

          <Text style={s.label}>Transfer Method</Text>
          <Text style={s.value}>{transfer.transfer_method.replace('_', ' ')}</Text>

          <Text style={s.label}>Status</Text>
          <Text style={[s.value, alreadySent && s.statusSent]}>
            {transfer.status.replace(/_/g, ' ')}
          </Text>
        </View>

        {/* ── PENDING: evidence upload + mark as sent ─────────────── */}
        {transfer.status === 'pending' && (
          <>
            <Text style={s.sectionLabel}>Transfer evidence *</Text>
            <Text style={s.sectionHint}>
              Upload a screenshot of the transfer confirmation from your ticketing app.
            </Text>
            <ImageUploadTile
              localUri={evidenceUpload.localUri}
              status={evidenceUpload.status}
              error={evidenceUpload.error}
              onPress={evidenceUpload.pickImage}
              label="Upload transfer proof"
              hint="Screenshot of transfer confirmation"
              icon={'\u{1F4F8}'}
              height={140}
              hasError={false}
              disabled={busy}
            />

            <View style={s.sendConfirmBox}>
              <Text style={s.sendConfirmText}>
                I have transferred the ticket(s) to the buyer using the instructions above.
              </Text>
            </View>

            {buyerDeliveryMissing && (
              <View style={s.sendBlockedBanner}>
                <Text style={s.sendBlockedText}>
                  Buyer must provide delivery info before you can send tickets.
                </Text>
              </View>
            )}

            <Pressable
              style={[s.sendBtn, (busy || buyerDeliveryMissing) && s.sendBtnDisabled]}
              onPress={handleMarkSent}
              disabled={busy || buyerDeliveryMissing}
            >
              {busy ? (
                <ActivityIndicator color={colors.text} size="small" />
              ) : (
                <Text style={s.sendBtnText}>Mark as Sent</Text>
              )}
            </Pressable>
          </>
        )}

        {/* ── SELLER_SENT: waiting for buyer ──────────────────────── */}
        {transfer.status === 'seller_sent' && (
          <View style={s.sentBanner}>
            <Text style={s.sentTitle}>Transfer sent</Text>
            <Text style={s.sentText}>
              Waiting for the buyer to confirm receipt.
            </Text>
            {releaseCountdown && releaseCountdown !== 'Expired' && (
              <Text style={s.releaseText}>
                Payment auto-releases in {releaseCountdown}{" if the buyer doesn't respond."}
              </Text>
            )}
            {releaseCountdown === 'Expired' && (
              <Text style={[s.releaseText, { color: colors.success }]}>
                Auto-release period has passed. Your payout should be released.
              </Text>
            )}
            <Text style={s.sentWarning}>
              If the buyer reports an issue, your payout will be held for review.
            </Text>
          </View>
        )}

        {/* ── BUYER_CONFIRMED: done ───────────────────────────────── */}
        {transfer.status === 'buyer_confirmed' && (
          <View style={s.sentBanner}>
            <Text style={[s.sentTitle, { color: colors.success }]}>
              Transfer complete
            </Text>
            <Text style={s.sentText}>
              The buyer has confirmed receipt. Your payout has been released.
            </Text>
          </View>
        )}

        {/* ── AUTO_RELEASED: done ─────────────────────────────────── */}
        {transfer.status === 'auto_released' && (
          <View style={s.sentBanner}>
            <Text style={[s.sentTitle, { color: colors.success }]}>
              Payout released
            </Text>
            <Text style={s.sentText}>
              The auto-release period passed without a dispute. Your payout has been released.
            </Text>
          </View>
        )}

        {/* ── DISPUTED ────────────────────────────────────────────── */}
        {transfer.status === 'disputed' && (
          <View style={s.sentBanner}>
            <Text style={[s.sentTitle, { color: colors.warning }]}>
              Dispute in progress
            </Text>
            <Text style={s.sentText}>
              The buyer has reported an issue with the transfer. Your payout is on hold pending review.
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

  // Delivery info card
  deliveryCard: {
    backgroundColor: colors.bgCard,
    borderRadius: radius.md,
    padding: spacing.md,
    marginBottom: spacing.md,
    borderWidth: 1,
    borderColor: colors.primary,
  },
  deliveryTitle: {
    color: colors.text,
    fontSize: fontSize.md,
    fontWeight: '700',
    marginBottom: spacing.sm,
  },
  deliveryRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: spacing.xs,
  },
  deliveryLabel: {
    color: colors.textMuted,
    fontSize: fontSize.xs,
    fontWeight: '600',
  },
  deliveryValue: {
    color: colors.text,
    fontSize: fontSize.md,
    fontWeight: '600',
  },
  deliveryMissingBox: {
    backgroundColor: 'rgba(255,77,109,0.08)',
    borderRadius: radius.sm,
    padding: spacing.sm,
  },
  deliveryMissingTitle: {
    color: colors.error,
    fontSize: fontSize.sm,
    fontWeight: '700',
    marginBottom: spacing.xs,
  },
  deliveryMissingText: {
    color: colors.textMuted,
    fontSize: fontSize.xs,
    lineHeight: 18,
  },

  // Details card
  card: {
    backgroundColor: colors.bgCard,
    borderRadius: radius.md,
    padding: spacing.md,
    marginBottom: spacing.lg,
  },
  label: { color: colors.textMuted, fontSize: fontSize.xs, fontWeight: '600', marginTop: spacing.sm },
  value: { color: colors.text, fontSize: fontSize.md, fontWeight: '500', marginTop: spacing.xs },
  statusSent: { color: colors.success },

  // Section labels (evidence)
  sectionLabel: {
    color: colors.text,
    fontSize: fontSize.sm,
    fontWeight: '700',
    marginBottom: spacing.xs,
  },
  sectionHint: {
    color: colors.textMuted,
    fontSize: fontSize.xs,
    marginBottom: spacing.sm,
    lineHeight: 18,
  },

  // Send confirmation
  sendConfirmBox: {
    backgroundColor: 'rgba(251,191,36,0.10)',
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.warning,
    padding: spacing.sm,
    marginTop: spacing.sm,
    marginBottom: spacing.md,
  },
  sendConfirmText: {
    color: colors.warning,
    fontSize: fontSize.xs,
    lineHeight: 18,
    textAlign: 'center',
  },

  sendBlockedBanner: {
    backgroundColor: 'rgba(255,77,109,0.10)',
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.error,
    padding: spacing.sm,
    marginBottom: spacing.md,
  },
  sendBlockedText: {
    color: colors.error,
    fontSize: fontSize.xs,
    fontWeight: '600',
    textAlign: 'center',
    lineHeight: 18,
  },

  sendBtn: {
    backgroundColor: colors.primary,
    borderRadius: radius.md,
    paddingVertical: 14,
    alignItems: 'center',
    marginBottom: spacing.lg,
  },
  sendBtnDisabled: { opacity: 0.6 },
  sendBtnText: { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },

  // Post-send banner
  sentBanner: {
    backgroundColor: colors.bgCard,
    borderRadius: radius.md,
    padding: spacing.md,
    alignItems: 'center',
    marginBottom: spacing.md,
  },
  sentTitle: {
    color: colors.text,
    fontSize: fontSize.md,
    fontWeight: '700',
    marginBottom: spacing.xs,
  },
  sentText: {
    color: colors.textMuted,
    fontSize: fontSize.sm,
    fontWeight: '500',
    textAlign: 'center',
    lineHeight: 22,
    marginBottom: spacing.xs,
  },
  releaseText: {
    color: colors.textMuted,
    fontSize: fontSize.xs,
    textAlign: 'center',
    marginTop: spacing.xs,
  },
  sentWarning: {
    color: colors.warning,
    fontSize: fontSize.xs,
    textAlign: 'center',
    marginTop: spacing.sm,
    lineHeight: 18,
  },

  errorText: { color: colors.error, fontSize: fontSize.md },

  // Countdown
  countdownBanner: {
    backgroundColor: 'rgba(251,191,36,0.12)',
    borderRadius: radius.md,
    padding: spacing.sm,
    alignItems: 'center',
    marginBottom: spacing.md,
    borderWidth: 1,
    borderColor: colors.warning,
  },
  countdownExpired: { backgroundColor: 'rgba(255,77,109,0.1)', borderColor: colors.error },
  countdownText:    { color: colors.warning, fontSize: fontSize.sm, fontWeight: '700' },
  countdownExpiredText: { color: colors.error },
});

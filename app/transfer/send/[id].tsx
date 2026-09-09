/**
 * app/transfer/send/[id].tsx — Seller transfer send (V2).
 *
 * PRESENTATION rebuilt on the V2 system; the transfer path is unchanged: the same
 * owner-scoped fetch, the expiry + auto-release countdowns, the required evidence
 * upload, the `mark_transfer_sent` RPC, and every post-send state (seller_sent
 * with its payout-review sub-states, buyer_confirmed, auto_released, disputed).
 * Countdown + status vocabulary come from src/lib/transfer/transferState.ts.
 * DeliveryInfo/PlatformInstructions and the proof bucket/paths are untouched.
 */

import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { useImageUpload } from '@/src/hooks/useImageUpload';
import PlatformInstructions from '@/src/components/PlatformInstructions';
import ScreenState from '@/src/components/ScreenState';
import { isNetworkError } from '@/src/hooks/useNetworkStatus';
import { Badge, Button, IconButton, MediaUpload, Spinner } from '@/src/components/ui';
import {
  formatCountdown,
  sellerAlreadySent,
  sellerDeliveryMissing,
  transferStatusMeta,
} from '@/src/lib/transfer/transferState';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import type { TicketPlatform, TransferMethod } from '@/src/types';

type TransferData = {
  id: string;
  listing_id: string;
  status: string;
  transfer_method: TransferMethod;
  expires_at: string | null;
  auto_release_at: string | null;
  payout_released_at: string | null;
  payout_review_status: 'held' | 'manual_review' | null;
  delivery_email: string | null;
  delivery_phone: string | null;
  transfer_evidence_path: string | null;
  buyer: { display_name: string | null };
  listing: { event_name: string | null; ticket_platform: TicketPlatform | null };
};

export default function TransferSendScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { session } = useAuth();
  const userId = session?.user.id ?? '';
  const insets = useSafeAreaInsets();

  const [transfer, setTransfer] = useState<TransferData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const [expiryCountdown, setExpiryCountdown] = useState<string | null>(null);
  const [releaseCountdown, setReleaseCountdown] = useState<string | null>(null);
  const expiryTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const releaseTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const evidenceUpload = useImageUpload({
    userId,
    folder: 'transfer-evidence',
    aspect: null,
    quality: 0.85,
    bucket: 'proof-docs', // PRIVATE — buyer/seller/admin only (migration 034)
  });

  const fetchTransfer = useCallback(async () => {
    if (!userId || !id) return;
    setLoading(true);
    const { data, error: fetchErr } = await supabase
      .from('transfers')
      .select(
        'id, listing_id, status, transfer_method, expires_at, auto_release_at, payout_released_at, payout_review_status, ' +
        'delivery_email, delivery_phone, transfer_evidence_path, ' +
        'buyer:profiles!buyer_id(display_name), ' +
        'listing:listings!listing_id(event_name, ticket_platform)',
      )
      .eq('id', id)
      .eq('seller_id', userId)
      .single();

    if (fetchErr || !data) {
      setError(fetchErr && isNetworkError(fetchErr) ? '__offline__' : 'Transfer not found');
    } else {
      setError('');
      setTransfer(data as unknown as TransferData);
    }
    setLoading(false);
  }, [id, userId]);

  useEffect(() => { fetchTransfer(); }, [fetchTransfer]);

  // Expiry countdown (pending — seller has 24h to send)
  useEffect(() => {
    if (!transfer?.expires_at || transfer.status !== 'pending') return;
    setExpiryCountdown(formatCountdown(transfer.expires_at));
    expiryTimerRef.current = setInterval(() => setExpiryCountdown(formatCountdown(transfer.expires_at)), 60_000);
    return () => { if (expiryTimerRef.current) clearInterval(expiryTimerRef.current); };
  }, [transfer?.expires_at, transfer?.status]);

  // Auto-release countdown (seller_sent — buyer review window)
  useEffect(() => {
    if (!transfer?.auto_release_at || transfer.status !== 'seller_sent') return;
    setReleaseCountdown(formatCountdown(transfer.auto_release_at));
    releaseTimerRef.current = setInterval(() => setReleaseCountdown(formatCountdown(transfer.auto_release_at)), 60_000);
    return () => { if (releaseTimerRef.current) clearInterval(releaseTimerRef.current); };
  }, [transfer?.auto_release_at, transfer?.status]);

  async function handleMarkSent() {
    if (!id || !userId) return;
    if (!evidenceUpload.localUri) {
      Alert.alert('Evidence required', 'Please upload a screenshot of the transfer confirmation before marking as sent.');
      return;
    }
    setSubmitting(true);
    try {
      const evidencePath = await evidenceUpload.uploadImage();
      if (!evidencePath) {
        Alert.alert('Upload failed', evidenceUpload.error ?? 'Unknown upload error.');
        setSubmitting(false);
        return;
      }
      const { error: rpcErr } = await supabase.rpc('mark_transfer_sent', {
        p_transfer_id: id,
        p_user_id: userId,
        p_transfer_evidence_path: evidencePath,
      });
      setSubmitting(false);
      if (rpcErr) { Alert.alert('Error', rpcErr.message); return; }
      setTransfer((prev) => (prev ? { ...prev, status: 'seller_sent', transfer_evidence_path: evidencePath } : prev));
      Alert.alert('Sent', 'Transfer marked as sent. Waiting for the buyer to confirm receipt.');
    } catch {
      setSubmitting(false);
      Alert.alert('Error', 'Something went wrong. Please try again.');
    }
  }

  const platform: TicketPlatform = transfer?.listing?.ticket_platform ?? 'other';
  const alreadySent = transfer ? sellerAlreadySent(transfer.status) : false;
  const busy = submitting || evidenceUpload.status === 'uploading';
  const buyerDeliveryMissing = transfer ? sellerDeliveryMissing(transfer) : false;

  function Header() {
    return (
      <View style={[s.header, { paddingTop: insets.top + v2.space.sm }]}>
        <IconButton glyph="back" onPress={() => router.back()} accessibilityLabel="Back" />
        <Text style={[textStyle('displaySm'), s.headerTitle]} accessibilityRole="header">Send transfer</Text>
        <View style={s.headerSpacer} />
      </View>
    );
  }

  if (loading) {
    return <View style={[s.root, s.center]}><Spinner color={v2.brand.red} /></View>;
  }

  if (error || !transfer) {
    return (
      <View style={s.root}>
        <Header />
        {error === '__offline__' ? (
          <ScreenState state="offline" onRetry={fetchTransfer} />
        ) : (
          <View style={s.center}><Text style={[textStyle('body'), s.errorText]}>{error || 'Transfer not found'}</Text></View>
        )}
      </View>
    );
  }

  const meta = transferStatusMeta(transfer.status);

  return (
    <View style={s.root}>
      <Header />
      <ScrollView contentContainerStyle={s.content} keyboardShouldPersistTaps="handled" showsVerticalScrollIndicator={false}>
        {/* Buyer delivery target */}
        <View style={s.section}>
          <Text style={[textStyle('micro'), s.sectionLabel]}>Send tickets to</Text>
          {transfer.delivery_email ? <Row label="Email" value={transfer.delivery_email} /> : null}
          {transfer.delivery_phone ? <Row label="Phone" value={transfer.delivery_phone} /> : null}
          {buyerDeliveryMissing ? (
            <View style={s.warnBox}>
              <Text style={[textStyle('bodySm'), s.warnTitle]}>Delivery info not yet provided</Text>
              <Text style={[textStyle('bodySm'), s.warnText]}>
                The buyer must provide their delivery info before you can send tickets. They are prompted for it when they open the transfer.
              </Text>
            </View>
          ) : null}
        </View>

        {!alreadySent ? (
          <PlatformInstructions platform={platform} role="seller" buyerEmail={transfer.delivery_email} buyerPhone={transfer.delivery_phone} />
        ) : null}

        {expiryCountdown && transfer.status === 'pending' ? (
          <View style={[s.countdown, expiryCountdown === 'Expired' && s.countdownExpired]}>
            <Text style={[textStyle('bodySm'), s.countdownText, expiryCountdown === 'Expired' && s.countdownExpiredText]}>
              {expiryCountdown === 'Expired' ? 'Transfer window expired' : `${expiryCountdown} to send`}
            </Text>
          </View>
        ) : null}

        {/* Details */}
        <View style={s.section}>
          <View style={s.detailHead}>
            <Text style={[textStyle('micro'), s.sectionLabel]}>Transfer</Text>
            <Badge label={meta.label} tone={meta.tone} />
          </View>
          <Row label="Event" value={transfer.listing?.event_name || 'Untitled'} />
          <Row label="Buyer" value={transfer.buyer?.display_name || 'Unknown'} />
          <Row label="Method" value={transfer.transfer_method.replace('_', ' ')} />
        </View>

        {/* PENDING — upload + mark sent */}
        {transfer.status === 'pending' ? (
          <View style={s.block}>
            <Text style={[textStyle('micro'), s.sectionLabel]}>Transfer evidence</Text>
            <MediaUpload
              variant="compact"
              localUri={evidenceUpload.localUri}
              status={evidenceUpload.status}
              error={evidenceUpload.error}
              onPress={evidenceUpload.pickImage}
              onRemove={evidenceUpload.reset}
              label="Transfer proof"
              helper="Screenshot of the transfer confirmation"
              icon="doc.text"
              disabled={busy}
            />
            <Text style={[textStyle('bodySm'), s.confirmNote]}>
              I have transferred the ticket(s) to the buyer using the instructions above.
            </Text>
            {buyerDeliveryMissing ? (
              <Text style={[textStyle('bodySm'), s.blockedText]}>Buyer must provide delivery info before you can send tickets.</Text>
            ) : null}
            <Button label="Mark as sent" onPress={handleMarkSent} loading={busy} disabled={busy || buyerDeliveryMissing} block style={s.cta} />
          </View>
        ) : null}

        {/* SELLER_SENT */}
        {transfer.status === 'seller_sent' ? (
          <StateBlock title="Transfer sent" tone="neutral">
            <Text style={[textStyle('bodySm'), s.stateText]}>Waiting for the buyer to confirm receipt.</Text>
            {transfer.payout_review_status == null && releaseCountdown && releaseCountdown !== 'Expired' ? (
              <Text style={[textStyle('bodySm'), s.stateSub]}>Buyer review window: {releaseCountdown}. Your payout releases once it clears review, sooner if the buyer confirms.</Text>
            ) : null}
            {transfer.payout_review_status == null && releaseCountdown === 'Expired' ? (
              <Text style={[textStyle('bodySm'), s.stateSub]}>The buyer review window has passed. Payout pending, it releases automatically once it clears review.</Text>
            ) : null}
            {transfer.payout_review_status === 'held' ? (
              <Text style={[textStyle('bodySm'), s.stateSub]}>Payout pending, funds are held until shortly after the event as a standard protection. No action needed unless the buyer reports an issue.</Text>
            ) : null}
            {transfer.payout_review_status === 'manual_review' ? (
              <Text style={[textStyle('bodySm'), s.stateSub]}>Payout pending, this transfer is under manual review. Our team may contact you; you can also reach support@snatchitapp.com.</Text>
            ) : null}
            <Text style={[textStyle('bodySm'), s.stateWarn]}>If the buyer reports an issue, your payout will be held for review.</Text>
          </StateBlock>
        ) : null}

        {/* BUYER_CONFIRMED */}
        {transfer.status === 'buyer_confirmed' ? (
          <StateBlock title="Transfer complete" tone="success">
            <Text style={[textStyle('bodySm'), s.stateText]}>
              {transfer.payout_released_at
                ? 'The buyer has confirmed receipt. Your payout has been released.'
                : 'The buyer has confirmed receipt. Your payout is being processed, make sure your payout account is set up in Settings.'}
            </Text>
          </StateBlock>
        ) : null}

        {/* AUTO_RELEASED */}
        {transfer.status === 'auto_released' ? (
          <StateBlock title="Payout released" tone="success">
            <Text style={[textStyle('bodySm'), s.stateText]}>The buyer review window passed without a dispute. Your payout has been released.</Text>
          </StateBlock>
        ) : null}

        {/* DISPUTED */}
        {transfer.status === 'disputed' ? (
          <StateBlock title="Dispute in progress" tone="warning">
            <Text style={[textStyle('bodySm'), s.stateText]}>The buyer has reported an issue with the transfer. Your payout is on hold pending review.</Text>
          </StateBlock>
        ) : null}

        <View style={{ height: v2.space.xxl }} />
      </ScrollView>
    </View>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <View style={s.row}>
      <Text style={[textStyle('bodySm'), s.rowLabel]}>{label}</Text>
      <Text style={[textStyle('body'), s.rowValue]} numberOfLines={1}>{value}</Text>
    </View>
  );
}

function StateBlock({ title, tone, children }: { title: string; tone: 'neutral' | 'success' | 'warning'; children: React.ReactNode }) {
  const color = tone === 'success' ? v2.status.success : tone === 'warning' ? v2.status.warning : v2.text.primary;
  return (
    <View style={s.stateBlock}>
      <Text style={[textStyle('title'), { color }]}>{title}</Text>
      {children}
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: v2.surface.canvas },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  errorText: { color: v2.status.error },

  header: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: v2.space.md, paddingBottom: v2.space.sm,
    borderBottomWidth: 1, borderBottomColor: v2.border.default,
  },
  headerTitle: { color: v2.text.primary },
  headerSpacer: { width: 44 },

  content: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.lg },

  section: {
    borderWidth: 1, borderColor: v2.border.default, backgroundColor: v2.surface.surface,
    padding: v2.space.md, marginBottom: v2.space.md,
  },
  sectionLabel: { color: v2.text.muted, marginBottom: v2.space.sm },
  detailHead: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: v2.space.sm },

  row: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: v2.space.md, paddingVertical: v2.space.xs },
  rowLabel: { color: v2.text.muted },
  rowValue: { color: v2.text.primary, flexShrink: 1, textAlign: 'right' },

  warnBox: { marginTop: v2.space.sm, borderWidth: 1, borderColor: v2.status.error, padding: v2.space.sm },
  warnTitle: { color: v2.status.error, marginBottom: v2.space.xs },
  warnText: { color: v2.text.muted },

  countdown: { borderWidth: 1, borderColor: v2.status.warning, padding: v2.space.sm, alignItems: 'center', marginBottom: v2.space.md },
  countdownExpired: { borderColor: v2.status.error },
  countdownText: { color: v2.status.warning },
  countdownExpiredText: { color: v2.status.error },

  block: { marginBottom: v2.space.md },
  hint: { color: v2.text.muted, marginBottom: v2.space.sm },
  confirmNote: { color: v2.text.secondary, marginTop: v2.space.md },
  blockedText: { color: v2.status.error, marginTop: v2.space.sm },
  cta: { marginTop: v2.space.md },

  stateBlock: {
    borderWidth: 1, borderColor: v2.border.default, backgroundColor: v2.surface.surface,
    padding: v2.space.lg, marginBottom: v2.space.md, gap: v2.space.xs,
  },
  stateText: { color: v2.text.secondary },
  stateSub: { color: v2.text.muted, marginTop: v2.space.xs },
  stateWarn: { color: v2.status.warning, marginTop: v2.space.sm },
});

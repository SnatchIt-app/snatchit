/**
 * app/transfer/receive/[id].tsx — Buyer transfer receive (V2).
 *
 * PRESENTATION rebuilt on the V2 system; the transfer path is unchanged: the
 * owner-scoped fetch, `mark_transfer_viewed`, the seller's signed proof URL, the
 * countdown, the delivery-info gate (`set_transfer_delivery_info` via
 * DeliveryInfoForm), confirm (`confirm-and-release` edge function) and dispute
 * (`buyer_dispute_transfer`). Countdown + status vocabulary come from
 * src/lib/transfer/transferState.ts. The proof viewer and platform instructions
 * are untouched. Ownership is never implied before authoritative confirmation.
 */

import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Image, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import DeliveryInfoForm from '@/src/components/DeliveryInfoForm';
import { ProofImageViewer } from '@/src/components/ProofImageViewer';
import PlatformInstructions from '@/src/components/PlatformInstructions';
import ScreenState from '@/src/components/ScreenState';
import { isNetworkError } from '@/src/hooks/useNetworkStatus';
import { normalizeUSPhone } from '@/src/utils/phone';
import { Badge, Button, IconButton, Spinner } from '@/src/components/ui';
import { formatCountdown, buyerNeedsDelivery, transferStatusMeta } from '@/src/lib/transfer/transferState';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import type { TicketPlatform, TransferMethod } from '@/src/types';

type TransferData = {
  id: string;
  status: string;
  transfer_method: TransferMethod;
  expires_at: string | null;
  delivery_email: string | null;
  delivery_phone: string | null;
  transfer_evidence_path: string | null;
  seller: { display_name: string | null };
  listing: { event_name: string | null; ticket_platform: TicketPlatform | null };
};

export default function TransferReceiveScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { session } = useAuth();
  const userId = session?.user.id ?? '';
  const insets = useSafeAreaInsets();

  const [transfer, setTransfer] = useState<TransferData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [savingDelivery, setSavingDelivery] = useState(false);
  const [countdown, setCountdown] = useState<string | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const [proofUrl, setProofUrl] = useState<string | null>(null);
  const [proofViewerOpen, setProofViewerOpen] = useState(false);

  useEffect(() => {
    const path = transfer?.transfer_evidence_path;
    if (!path || transfer?.status !== 'seller_sent') { setProofUrl(null); return; }
    let active = true;
    supabase.storage.from('proof-docs').createSignedUrl(path, 60 * 60)
      .then(({ data }) => { if (active) setProofUrl(data?.signedUrl ?? null); })
      .catch(() => { if (active) setProofUrl(null); });
    return () => { active = false; };
  }, [transfer?.transfer_evidence_path, transfer?.status]);

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
      setError(fetchErr && isNetworkError(fetchErr) ? '__offline__' : 'Transfer not found');
    } else {
      setError('');
      setTransfer(data as unknown as TransferData);
    }
    setLoading(false);
  }, [id, userId]);

  useEffect(() => { fetchTransfer(); }, [fetchTransfer]);

  // Record that the buyer opened the transfer (payout risk signal).
  useEffect(() => {
    if (!userId || !id) return;
    supabase.rpc('mark_transfer_viewed', { p_transfer_id: id }).then(({ error: rpcErr }) => {
      if (rpcErr) console.warn('[transfer] mark_transfer_viewed failed:', rpcErr.message);
    });
  }, [userId, id]);

  useEffect(() => {
    if (!transfer?.expires_at) return;
    setCountdown(formatCountdown(transfer.expires_at));
    timerRef.current = setInterval(() => setCountdown(formatCountdown(transfer.expires_at)), 60_000);
    return () => { if (timerRef.current) clearInterval(timerRef.current); };
  }, [transfer?.expires_at]);

  async function handleDeliverySubmit(email: string | null, phone: string | null) {
    if (!id) return;
    setSavingDelivery(true);
    // Re-normalize defensively even though DeliveryInfoForm already did.
    const safePhone = phone ? normalizeUSPhone(phone) : null;
    const { error: rpcErr } = await supabase.rpc('set_transfer_delivery_info', {
      p_transfer_id: id,
      p_delivery_email: email,
      p_delivery_phone: safePhone,
    });
    setSavingDelivery(false);
    if (rpcErr) { Alert.alert('Error', rpcErr.message); return; }
    setTransfer((prev) => (prev ? { ...prev, delivery_email: email, delivery_phone: safePhone } : prev));
    fetchTransfer();
  }

  async function handleConfirm() {
    if (!id) return;
    setSubmitting(true);
    try {
      const { data, error: fnError } = await supabase.functions.invoke('confirm-and-release', { body: { transfer_id: id } });
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
      setTransfer((prev) => (prev ? { ...prev, status: 'buyer_confirmed' } : prev));
      Alert.alert('Confirmed', 'Transfer complete. Enjoy the event.');
    } catch {
      setSubmitting(false);
      Alert.alert('Error', 'Something went wrong. Please try again.');
    }
  }

  function handleDispute() {
    Alert.alert(
      'Report issue',
      'Are you sure you want to report a problem with this transfer? This will freeze the transfer and notify support.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Report issue',
          style: 'destructive',
          onPress: async () => {
            setSubmitting(true);
            const { error: rpcErr } = await supabase.rpc('buyer_dispute_transfer', { p_transfer_id: id });
            setSubmitting(false);
            if (rpcErr) {
              Alert.alert("Couldn't submit dispute", 'Please try again in a moment. If the problem persists, contact support.');
              console.warn('[receive] buyer_dispute_transfer error:', rpcErr.message);
              return;
            }
            setTransfer((prev) => (prev ? { ...prev, status: 'disputed' } : prev));
            Alert.alert('Reported', 'The transfer has been flagged. Support will review.');
          },
        },
      ],
    );
  }

  const platform: TicketPlatform = transfer?.listing?.ticket_platform ?? 'other';
  const transferMethod: TransferMethod = (transfer?.transfer_method as TransferMethod) ?? 'email';
  const needsDeliveryInfo = transfer != null && buyerNeedsDelivery(transfer);

  function Header() {
    return (
      <View style={[s.header, { paddingTop: insets.top + v2.space.sm }]}>
        <IconButton glyph="back" onPress={() => router.back()} accessibilityLabel="Back" />
        <Text style={[textStyle('displaySm'), s.headerTitle]} accessibilityRole="header">Receive transfer</Text>
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
      <KeyboardAvoidingView style={s.flex} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView contentContainerStyle={s.content} keyboardShouldPersistTaps="handled" keyboardDismissMode="on-drag" showsVerticalScrollIndicator={false}>
        {/* Delivery info gate (required before any other action) */}
        {needsDeliveryInfo ? (
          <>
            <View style={s.gate}>
              <Text style={[textStyle('bodySm'), s.gateText]}>
                Please provide your delivery info so the seller knows where to send your tickets.
              </Text>
            </View>
            <DeliveryInfoForm transferMethod={transferMethod} onSubmit={handleDeliverySubmit} loading={savingDelivery} />
          </>
        ) : null}

        {(transfer.status === 'pending' || transfer.status === 'seller_sent') && !needsDeliveryInfo ? (
          <PlatformInstructions platform={platform} role="buyer" buyerEmail={transfer.delivery_email} buyerPhone={transfer.delivery_phone} />
        ) : null}

        {countdown && transfer.status !== 'buyer_confirmed' ? (
          <View style={[s.countdown, countdown === 'Expired' && s.countdownExpired]}>
            <Text style={[textStyle('bodySm'), s.countdownText, countdown === 'Expired' && s.countdownExpiredText]}>
              {countdown === 'Expired' ? 'Transfer window expired' : countdown}
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
          <Row label="Seller" value={transfer.seller?.display_name || 'Unknown'} />
          <Row label="Method" value={transfer.transfer_method.replace('_', ' ')} />
          {transfer.delivery_email ? <Row label="Delivery email" value={transfer.delivery_email} /> : null}
          {transfer.delivery_phone ? <Row label="Delivery phone" value={transfer.delivery_phone} /> : null}
        </View>

        {/* PENDING */}
        {transfer.status === 'pending' && !needsDeliveryInfo ? (
          <View style={s.stateBlock}>
            <Text style={[textStyle('bodySm'), s.stateText]}>Waiting for the seller to send the transfer.</Text>
          </View>
        ) : null}

        {/* SELLER_SENT — confirm / dispute */}
        {transfer.status === 'seller_sent' && !needsDeliveryInfo ? (
          <>
            {proofUrl ? (
              <View style={s.proofBlock}>
                <Text style={[textStyle('micro'), s.sectionLabel]}>{"Seller's proof of transfer"}</Text>
                <Pressable onPress={() => setProofViewerOpen(true)} accessibilityRole="imagebutton" accessibilityLabel="View proof of transfer full screen">
                  <Image source={{ uri: proofUrl }} style={s.proofImage} resizeMode="contain" />
                </Pressable>
                <Text style={[textStyle('bodySm'), s.hint]}>Tap to view full screen. Review it before confirming.</Text>
              </View>
            ) : null}

            <View style={s.confirmPrompt}>
              <Text style={[textStyle('bodySm'), s.confirmPromptText]}>
                By confirming, you release payment to the seller. Only confirm if you can see the tickets in your account.
              </Text>
            </View>

            <Button label="I got my tickets" onPress={handleConfirm} loading={submitting} disabled={submitting} block style={s.cta} />
            <Button label="I haven't received them" variant="destructive" onPress={handleDispute} disabled={submitting} block style={s.disputeCta} />
          </>
        ) : null}

        {/* CONFIRMED */}
        {transfer.status === 'buyer_confirmed' ? (
          <StateBlock title="Transfer complete" tone="success">
            <Text style={[textStyle('bodySm'), s.stateText]}>Enjoy the event.</Text>
          </StateBlock>
        ) : null}

        {/* DISPUTED */}
        {transfer.status === 'disputed' ? (
          <StateBlock title="Issue reported" tone="warning">
            <Text style={[textStyle('bodySm'), s.stateText]}>
              Our team typically reviews within 24 hours. Your payment stays on hold until this is resolved.
            </Text>
          </StateBlock>
        ) : null}

        <View style={{ height: v2.space.xxl }} />
      </ScrollView>
      </KeyboardAvoidingView>

      <ProofImageViewer uri={proofViewerOpen ? proofUrl : null} onClose={() => setProofViewerOpen(false)} />
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

function StateBlock({ title, tone, children }: { title: string; tone: 'success' | 'warning'; children: React.ReactNode }) {
  const color = tone === 'success' ? v2.status.success : v2.status.warning;
  return (
    <View style={s.stateBlock}>
      <Text style={[textStyle('title'), { color }]}>{title}</Text>
      {children}
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: v2.surface.canvas },
  flex: { flex: 1 },
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

  gate: { borderWidth: 1, borderColor: v2.status.warning, padding: v2.space.md, marginBottom: v2.space.md },
  gateText: { color: v2.status.warning },

  countdown: { borderWidth: 1, borderColor: v2.status.warning, padding: v2.space.sm, alignItems: 'center', marginBottom: v2.space.md },
  countdownExpired: { borderColor: v2.status.error },
  countdownText: { color: v2.status.warning },
  countdownExpiredText: { color: v2.status.error },

  proofBlock: { marginBottom: v2.space.md },
  proofImage: { width: '100%', height: 220, backgroundColor: v2.surface.surface, marginTop: v2.space.xs },
  hint: { color: v2.text.muted, marginTop: v2.space.xs },

  confirmPrompt: { borderWidth: 1, borderColor: v2.status.warning, padding: v2.space.sm, marginBottom: v2.space.md },
  confirmPromptText: { color: v2.status.warning },
  cta: { marginTop: v2.space.xs },
  disputeCta: { marginTop: v2.space.sm },

  stateBlock: {
    borderWidth: 1, borderColor: v2.border.default, backgroundColor: v2.surface.surface,
    padding: v2.space.lg, marginBottom: v2.space.md, gap: v2.space.xs,
  },
  stateText: { color: v2.text.secondary },
});

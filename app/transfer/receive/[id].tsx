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
 *
 * PREMIUM BATCH 2 (CFT-203/205). Confirm and Report are separate pending
 * states with visible labels ("Confirming receipt…", "Reporting…"), each held
 * by a single-flight lock so a double tap cannot invoke confirm-and-release
 * twice; the success haptic fires only after the edge function returned
 * success, paired with the "Tickets received" state block.
 *
 * PREMIUM BATCH 3 (CFT-402/404). The seller's claim ("Seller marked as sent")
 * and the buyer's possession ("Tickets received") never share a word. The
 * buyer can open the ticket provider from here; coming back re-reads the
 * order from the server and, only if the seller's claim is still the latest
 * state, asks "Did the tickets arrive?" — a question, never a confirmation.
 * "They're here" dismisses the question and leaves the buyer at the one
 * control that releases payment, which explains itself first.
 */

import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, AppState, Image, KeyboardAvoidingView, Linking, Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { useSingleFlight } from '@/src/hooks/useSingleFlight';
import { hapticSuccess } from '@/src/lib/feedback/haptics';
import DeliveryInfoForm from '@/src/components/DeliveryInfoForm';
import { ProofImageViewer } from '@/src/components/ProofImageViewer';
import PlatformInstructions from '@/src/components/PlatformInstructions';
import ScreenState from '@/src/components/ScreenState';
import { isNetworkError } from '@/src/hooks/useNetworkStatus';
import { normalizeUSPhone } from '@/src/utils/phone';
import { Badge, Button, IconButton, Spinner } from '@/src/components/ui';
import { formatCountdown, buyerNeedsDelivery, transferStatusCopy, transferStatusMeta } from '@/src/lib/transfer/transferState';
import {
  HANDOFF_IDLE,
  leaveForProvider,
  onForeground,
  providerLink,
  RETURN_PROMPT,
  returnPrompt,
  returnPromptBody,
  type HandoffState,
} from '@/src/lib/transfer/providerHandoff';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import type { TicketPlatform, TransferMethod } from '@/src/types';
import { useTopInset } from '@/src/lib/nav/navInsets';

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
  // F-SELL-2: the badge-aware top inset (status bar + the SANDBOX badge on sandbox builds; production unchanged).
  const topPad = useTopInset();

  const [transfer, setTransfer] = useState<TransferData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [confirming, setConfirming] = useState(false);
  const [disputing, setDisputing] = useState(false);
  const [savingDelivery, setSavingDelivery] = useState(false);
  // One money-moving call at a time (CFT-205): confirm and dispute share the
  // lock, so neither can start while the other is in flight.
  const flight = useSingleFlight();
  const busy = confirming || disputing;
  const [countdown, setCountdown] = useState<string | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const [proofUrl, setProofUrl] = useState<string | null>(null);
  const [proofViewerOpen, setProofViewerOpen] = useState(false);

  // Provider handoff (CFT-404): where the buyer went, and the question asked
  // on return — decided from the FRESH status, never from the tap.
  const [handoff, setHandoff] = useState<HandoffState>(HANDOFF_IDLE);
  const handoffRef = useRef<HandoffState>(HANDOFF_IDLE);
  handoffRef.current = handoff;
  const [arrivalPrompt, setArrivalPrompt] = useState(false);
  const [confirmHighlight, setConfirmHighlight] = useState(false);

  useEffect(() => {
    const path = transfer?.transfer_evidence_path;
    if (!path || transfer?.status !== 'seller_sent') { setProofUrl(null); return; }
    let active = true;
    supabase.storage.from('proof-docs').createSignedUrl(path, 60 * 60)
      .then(({ data }) => { if (active) setProofUrl(data?.signedUrl ?? null); })
      .catch(() => { if (active) setProofUrl(null); });
    return () => { active = false; };
  }, [transfer?.transfer_evidence_path, transfer?.status]);

  const fetchTransfer = useCallback(async (opts?: { quiet?: boolean }): Promise<TransferData | null> => {
    if (!userId || !id) return null;
    // Quiet: re-read behind the content (a return from the provider) instead
    // of replacing the order with a spinner.
    if (!opts?.quiet) setLoading(true);
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

    let fresh: TransferData | null = null;
    if (fetchErr || !data) {
      // A quiet re-read that fails keeps the order on screen; only a visible
      // load reports the failure.
      if (!opts?.quiet) setError(fetchErr && isNetworkError(fetchErr) ? '__offline__' : 'Transfer not found');
    } else {
      setError('');
      fresh = data as unknown as TransferData;
      setTransfer(fresh);
    }
    setLoading(false);
    return fresh;
  }, [id, userId]);

  useEffect(() => { fetchTransfer(); }, [fetchTransfer]);

  // Back from the provider: re-read the order, then decide whether to ask.
  // Returning from another app never implies receipt or payment.
  useEffect(() => {
    const sub = AppState.addEventListener('change', async (st) => {
      if (st !== 'active') return;
      const d = onForeground(handoffRef.current, Date.now());
      if (!d.refetch) return;
      setHandoff(d.next);
      const fresh = await fetchTransfer({ quiet: true });
      setArrivalPrompt(!!fresh && returnPrompt(fresh.status, buyerNeedsDelivery(fresh)));
    });
    return () => sub.remove();
  }, [fetchTransfer]);

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

  function handleConfirm() {
    if (!id) return;
    flight.run(confirmReceipt).catch(() => {
      setConfirming(false);
      Alert.alert('Error', 'Something went wrong. Please try again.');
    });
  }

  async function confirmReceipt() {
    setConfirming(true);
    try {
      const { data, error: fnError } = await supabase.functions.invoke('confirm-and-release', { body: { transfer_id: id } });
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
      // Authoritative: the edge function recorded the confirmation. Only now the
      // distinctive success haptic (CFT-202), paired with the state block below.
      hapticSuccess();
      setTransfer((prev) => (prev ? { ...prev, status: 'buyer_confirmed' } : prev));
      Alert.alert('Receipt confirmed', 'You confirmed you received the tickets. Enjoy the event.');
    } catch {
      Alert.alert('Error', 'Something went wrong. Please try again.');
    } finally {
      setConfirming(false);
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
          onPress: () => {
            flight.run(async () => {
              setDisputing(true);
              try {
                const { error: rpcErr } = await supabase.rpc('buyer_dispute_transfer', { p_transfer_id: id });
                if (rpcErr) {
                  Alert.alert("Couldn't submit dispute", 'Please try again in a moment. If the problem persists, contact support.');
                  console.warn('[receive] buyer_dispute_transfer error:', rpcErr.message);
                  return;
                }
                setTransfer((prev) => (prev ? { ...prev, status: 'disputed' } : prev));
                Alert.alert('Reported', 'The transfer has been flagged. Support will review.');
              } finally {
                setDisputing(false);
              }
            }).catch(() => {
              setDisputing(false);
              Alert.alert("Couldn't submit dispute", 'Please try again in a moment. If the problem persists, contact support.');
            });
          },
        },
      ],
    );
  }

  const platform: TicketPlatform = transfer?.listing?.ticket_platform ?? 'other';
  const transferMethod: TransferMethod = (transfer?.transfer_method as TransferMethod) ?? 'email';
  const needsDeliveryInfo = transfer != null && buyerNeedsDelivery(transfer);
  const link = providerLink(platform);

  function openProvider() {
    if (!link) return;
    setArrivalPrompt(false);
    setHandoff(leaveForProvider(Date.now()));
    // An official entry point only; universal links open the native app when installed.
    Linking.openURL(link.url).catch(() => setHandoff(HANDOFF_IDLE));
  }

  function Header() {
    return (
      <View style={[s.header, { paddingTop: topPad + v2.space.sm }]}>
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
          <ScreenState state="offline" onRetry={() => { void fetchTransfer(); }} />
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
          <>
            <PlatformInstructions platform={platform} role="buyer" buyerEmail={transfer.delivery_email} buyerPhone={transfer.delivery_phone} />
            {link ? (
              <View style={s.openProvider}>
                <Button
                  label={`Open ${link.name}`}
                  variant="secondary"
                  onPress={openProvider}
                  disabled={busy}
                  block
                  accessibilityHint="Opens the ticket provider. Come back here to confirm once you can see the tickets."
                />
              </View>
            ) : null}
          </>
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
            <Text style={[textStyle('bodySm'), s.stateText]}>{transferStatusCopy('pending', 'buyer').body}</Text>
          </View>
        ) : null}

        {/* SELLER_SENT — the seller's claim, then confirm / dispute */}
        {transfer.status === 'seller_sent' && !needsDeliveryInfo ? (
          <>
            <View style={s.stateBlock}>
              <Text style={[textStyle('title'), s.claimTitle]}>{transferStatusCopy('seller_sent', 'buyer').title}</Text>
              <Text style={[textStyle('bodySm'), s.stateText]}>{transferStatusCopy('seller_sent', 'buyer').body}</Text>
            </View>

            {arrivalPrompt ? (
              <View style={s.arrival} accessibilityLiveRegion="polite">
                <Text style={[textStyle('title'), s.arrivalTitle]}>{RETURN_PROMPT.title}</Text>
                <Text style={[textStyle('bodySm'), s.stateText]}>{returnPromptBody(link?.name ?? null)}</Text>
                <View style={s.arrivalActions}>
                  {/* Dismisses the question only; confirmation is the control below. */}
                  <Button label={RETURN_PROMPT.here} variant="secondary" size="sm" onPress={() => { setArrivalPrompt(false); setConfirmHighlight(true); }} disabled={busy} />
                  <Button label={RETURN_PROMPT.notYet} variant="ghost" size="sm" onPress={() => setArrivalPrompt(false)} disabled={busy} />
                  <Button label={RETURN_PROMPT.problem} variant="destructive" size="sm" onPress={() => { setArrivalPrompt(false); handleDispute(); }} disabled={busy} />
                </View>
              </View>
            ) : null}

            {proofUrl ? (
              <View style={s.proofBlock}>
                <Text style={[textStyle('micro'), s.sectionLabel]}>{"Seller's proof of transfer"}</Text>
                <Pressable onPress={() => setProofViewerOpen(true)} accessibilityRole="imagebutton" accessibilityLabel="View proof of transfer full screen">
                  <Image source={{ uri: proofUrl }} style={s.proofImage} resizeMode="contain" />
                </Pressable>
                <Text style={[textStyle('bodySm'), s.hint]}>Tap to view full screen. Review it before confirming.</Text>
              </View>
            ) : null}

            <View style={[s.confirmPrompt, confirmHighlight && s.confirmPromptHighlight]}>
              <Text style={[textStyle('bodySm'), s.confirmPromptText]}>
                By confirming, you release payment to the seller. Only confirm if you can see the tickets in your account.
              </Text>
            </View>

            <Button
              label="I got my tickets"
              pendingLabel="Confirming receipt…"
              onPress={handleConfirm}
              loading={confirming}
              disabled={busy}
              block
              style={s.cta}
            />
            <Button
              label="I haven't received them"
              pendingLabel="Reporting…"
              variant="destructive"
              onPress={handleDispute}
              loading={disputing}
              disabled={busy}
              block
              style={s.disputeCta}
            />
          </>
        ) : null}

        {/* CONFIRMED — the buyer's own statement of possession */}
        {transfer.status === 'buyer_confirmed' ? (
          <StateBlock title={transferStatusCopy('buyer_confirmed', 'buyer').title} tone="success">
            <Text style={[textStyle('bodySm'), s.stateText]}>{transferStatusCopy('buyer_confirmed', 'buyer').body}</Text>
          </StateBlock>
        ) : null}

        {/* AUTO_RELEASED — what happened to the money, not to the tickets */}
        {transfer.status === 'auto_released' ? (
          <StateBlock title={transferStatusCopy('auto_released', 'buyer').title} tone="success">
            <Text style={[textStyle('bodySm'), s.stateText]}>{transferStatusCopy('auto_released', 'buyer').body}</Text>
          </StateBlock>
        ) : null}

        {/* DISPUTED */}
        {transfer.status === 'disputed' ? (
          <StateBlock title={transferStatusCopy('disputed', 'buyer').title} tone="warning">
            <Text style={[textStyle('bodySm'), s.stateText]}>{transferStatusCopy('disputed', 'buyer').body}</Text>
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
  countdownText: { color: v2.status.warning, fontVariant: ['tabular-nums'] },
  countdownExpiredText: { color: v2.status.error },

  proofBlock: { marginBottom: v2.space.md },
  proofImage: { width: '100%', height: 220, backgroundColor: v2.surface.surface, marginTop: v2.space.xs },
  hint: { color: v2.text.muted, marginTop: v2.space.xs },

  confirmPrompt: { borderWidth: 1, borderColor: v2.status.warning, padding: v2.space.sm, marginBottom: v2.space.md },
  confirmPromptHighlight: { borderWidth: 2 },
  claimTitle: { color: v2.text.primary },
  openProvider: { marginBottom: v2.space.md },
  arrival: { borderWidth: 1, borderColor: v2.brand.red, backgroundColor: v2.brand.redSoft, padding: v2.space.md, marginBottom: v2.space.md, gap: v2.space.xs },
  arrivalTitle: { color: v2.text.primary },
  arrivalActions: { flexDirection: 'row', flexWrap: 'wrap', gap: v2.space.sm, marginTop: v2.space.sm },
  confirmPromptText: { color: v2.status.warning },
  cta: { marginTop: v2.space.xs },
  disputeCta: { marginTop: v2.space.sm },

  stateBlock: {
    borderWidth: 1, borderColor: v2.border.default, backgroundColor: v2.surface.surface,
    padding: v2.space.lg, marginBottom: v2.space.md, gap: v2.space.xs,
  },
  stateText: { color: v2.text.secondary },
});

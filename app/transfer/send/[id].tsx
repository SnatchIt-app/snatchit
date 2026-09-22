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
import { Alert, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { useImageUpload } from '@/src/hooks/useImageUpload';
import { useSingleFlight } from '@/src/hooks/useSingleFlight';
import { REQUEST_TIMEOUT_MS, UPLOAD_COPY, withUploadTimeout } from '@/src/lib/media/uploadFlow';
import { ATTACH_COPY, MARK_SENT_COPY, runAttachEvidence, runMarkSent, type TransferSnapshot } from '@/src/lib/transfer/markSent';
import PlatformInstructions from '@/src/components/PlatformInstructions';
import ScreenState from '@/src/components/ScreenState';
import { isNetworkError } from '@/src/hooks/useNetworkStatus';
import { Badge, Button, IconButton, MediaUpload, Spinner } from '@/src/components/ui';
import {
  formatCountdown,
  sellerAlreadySent,
  sellerDeliveryMissing,
  sellerWindowView,
  transferReadOutcome,
  transferStatusMeta,
} from '@/src/lib/transfer/transferState';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import type { TicketPlatform, TransferMethod } from '@/src/types';
import { useTopInset } from '@/src/lib/nav/navInsets';

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
  // F-SELL-2: the badge-aware top inset (status bar + the SANDBOX badge on sandbox builds; production unchanged).
  const topPad = useTopInset();

  const [transfer, setTransfer] = useState<TransferData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);
  // F-IMG-1d: one Mark as sent at a time; F-IMG-1: after a failed or unconfirmed attempt the CTA says Try again.
  const flight = useSingleFlight();
  const [lastFailed, setLastFailed] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  const [expiryCountdown, setExpiryCountdown] = useState<string | null>(null);
  // A server read landed after the device deadline (owner, 2026-09-19): before one does, the seller sees only neutral
  // "checking" wording. It is never a guarantee: the order can still close at any time.
  const [windowChecked, setWindowChecked] = useState(false);
  const windowRecheckRef = useRef(false);
  const windowFollowUpRef = useRef(false);
  const [releaseCountdown, setReleaseCountdown] = useState<string | null>(null);
  const expiryTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const releaseTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const evidenceUpload = useImageUpload({
    userId,
    folder: 'transfer-evidence',
    aspect: null,
    quality: 0.85,
    bucket: 'proof-docs', // PRIVATE — buyer/seller/admin only (migration 034)
    reuseKey: id,          // reuse and keep the selection only for THIS transfer
  });

  const fetchTransfer = useCallback(async (quiet = false) => {
    if (!userId || !id) return;
    if (!quiet) setLoading(true);
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

    // A failed read is never "not found" (owner, 2026-09-19): only a row-less answer supports that.
    const outcome = transferReadOutcome({
      isNetwork: !!fetchErr && isNetworkError(fetchErr),
      code: (fetchErr as { code?: string | null } | null)?.code,
      hasRow: !!data,
      failed: !!fetchErr,
    });
    if (outcome !== 'ok') {
      setError(outcome);
    } else {
      setError('');
      // Marked BEFORE the transfer is set, so no render sees a post-deadline row as unchecked (no redundant re-read).
      if (formatCountdown((data as unknown as TransferData).expires_at) === 'Expired') setWindowChecked(true);
      setTransfer(data as unknown as TransferData);
    }
    if (!quiet) setLoading(false);
  }, [id, userId]);

  useEffect(() => { fetchTransfer(); }, [fetchTransfer]);

  // Expiry countdown (pending — seller has 24h to send)
  useEffect(() => {
    if (!transfer?.expires_at || transfer.status !== 'pending') return;
    setExpiryCountdown(formatCountdown(transfer.expires_at));
    expiryTimerRef.current = setInterval(() => setExpiryCountdown(formatCountdown(transfer.expires_at)), 60_000);
    return () => { if (expiryTimerRef.current) clearInterval(expiryTimerRef.current); };
  }, [transfer?.expires_at, transfer?.status]);

  // The device clock passed the deadline while the screen was open: check the server once before saying more than
  // "checking". The read changes nothing on the server; a failed read shows the screen's existing error state.
  useEffect(() => {
    if (transfer?.status !== 'pending' || expiryCountdown !== 'Expired' || windowChecked || windowRecheckRef.current) return;
    windowRecheckRef.current = true;
    void fetchTransfer(true);
  }, [transfer?.status, expiryCountdown, windowChecked, fetchTransfer]);

  // A (2026-09-19): the expiry job runs every 2 minutes, so a read at the deadline almost always still says pending.
  // Once a post-deadline read says so, read ONE more time about 150 s later — at most two automatic reads per screen.
  // Still no guarantee: the order can close at any time, and the wording says so.
  useEffect(() => {
    if (!windowChecked || transfer?.status !== 'pending' || windowFollowUpRef.current) return;
    windowFollowUpRef.current = true;
    const t = setTimeout(() => { void fetchTransfer(true); }, 150_000);
    return () => clearTimeout(t);
  }, [windowChecked, transfer?.status, fetchTransfer]);

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
    await flight.run(async () => {
      setSubmitting(true);
      try {
        // 140: mark_transfer_sent answers transitioned | already_sent; success is shown only when the
        // transfer reads back as sent (or, if that read fails, when the reply itself says so).
        const outcome = await runMarkSent({
          readTransfer,
          upload: () => evidenceUpload.uploadImage(),
          call: async (path) => {
            const { data, error: rpcErr } = await withUploadTimeout(
              supabase.rpc('mark_transfer_sent', { p_transfer_id: id, p_user_id: userId, p_transfer_evidence_path: path }),
              REQUEST_TIMEOUT_MS,
            );
            return { data, error: rpcErr ? { message: rpcErr.message } : null };
          },
        });
        if (outcome.kind === 'sent') {
          setLastFailed(false);
          evidenceUpload.reset();
          await fetchTransfer(true);
          Alert.alert('Marked as sent', "You've marked this transfer as sent. The buyer still needs to confirm they received the tickets.");
          return;
        }
        if (outcome.kind === 'needs_proof') {
          // Already sent without a screenshot: keep the chosen photo and show the explicit Add proof action.
          setLastFailed(false);
          await fetchTransfer(true);
          Alert.alert('Already marked as sent', MARK_SENT_COPY.needsProof);
          return;
        }
        setLastFailed(true);
        if (outcome.kind === 'upload_failed') {
          Alert.alert("Couldn't upload the transfer proof", evidenceUpload.readError() ?? UPLOAD_COPY.uploadFailed);
        } else if (outcome.kind === 'not_pending') {
          await fetchTransfer(true);
          Alert.alert('Transfer updated', MARK_SENT_COPY.notPending);
        } else if (outcome.kind === 'failed') {
          Alert.alert("Couldn't mark as sent", outcome.message);
        } else {
          Alert.alert('Not confirmed yet', MARK_SENT_COPY.unconfirmed);
        }
      } finally {
        setSubmitting(false);
      }
    });
  }

  async function readTransfer(): Promise<TransferSnapshot | null> {
    const { data, error: readErr } = await withUploadTimeout(
      supabase.from('transfers').select('status, transfer_evidence_path').eq('id', id).eq('seller_id', userId).maybeSingle(),
      REQUEST_TIMEOUT_MS,
    );
    if (readErr || !data) return null;
    const row = data as { status: string; transfer_evidence_path: string | null };
    return { status: row.status, evidencePath: row.transfer_evidence_path ?? null };
  }

  /** 140: the seller's explicit recovery for a transfer marked sent with no screenshot. */
  async function handleAttachProof() {
    if (!id || !userId) return;
    if (!evidenceUpload.localUri) {
      Alert.alert('Evidence required', 'Choose a screenshot of the transfer confirmation first.');
      return;
    }
    await flight.run(async () => {
      setSubmitting(true);
      try {
        const outcome = await runAttachEvidence({
          readTransfer,
          upload: () => evidenceUpload.uploadImage(),
          attach: async (path) => {
            const { data, error: rpcErr } = await withUploadTimeout(
              supabase.rpc('attach_transfer_evidence', { p_transfer_id: id, p_transfer_evidence_path: path }),
              REQUEST_TIMEOUT_MS,
            );
            return { data, error: rpcErr ? { message: rpcErr.message } : null };
          },
        });
        if (outcome.kind === 'attached') {
          setLastFailed(false);
          evidenceUpload.reset();
          await fetchTransfer(true);
          Alert.alert('Proof added', ATTACH_COPY.added);
          return;
        }
        if (outcome.kind === 'has_proof' || outcome.kind === 'not_eligible') {
          setLastFailed(false);
          await fetchTransfer(true);
          Alert.alert('Transfer updated', outcome.kind === 'has_proof' ? ATTACH_COPY.hasProof : ATTACH_COPY.notEligible);
          return;
        }
        setLastFailed(true);
        if (outcome.kind === 'upload_failed') {
          Alert.alert("Couldn't upload the transfer proof", evidenceUpload.readError() ?? UPLOAD_COPY.uploadFailed);
        } else if (outcome.kind === 'failed') {
          Alert.alert("Couldn't add the screenshot", outcome.message);
        } else {
          Alert.alert('Not confirmed yet', ATTACH_COPY.unconfirmed);
        }
      } finally {
        setSubmitting(false);
      }
    });
  }

  // A refresh and a submit never overlap (D, 2026-09-18): a pre-submit read that lands after a confirmed
  // result would show the seller their proof vanishing. The submit re-reads on its own.
  const onRefresh = useCallback(async () => {
    if (flight.inFlight) return;
    setRefreshing(true);
    try { await fetchTransfer(true); } finally { setRefreshing(false); }
  }, [fetchTransfer, flight]);

  const platform: TicketPlatform = transfer?.listing?.ticket_platform ?? 'other';
  const alreadySent = transfer ? sellerAlreadySent(transfer.status) : false;
  const busy = submitting || evidenceUpload.busy;
  const buyerDeliveryMissing = transfer ? sellerDeliveryMissing(transfer) : false;
  const windowView = transfer
    ? sellerWindowView({ status: transfer.status, countdown: expiryCountdown, checkedSincePassed: windowChecked })
    : ({ kind: 'none' } as const);
  const orderClosed = windowView.kind === 'closed';

  function Header() {
    return (
      <View style={[s.header, { paddingTop: topPad + v2.space.sm }]}>
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
        {error === 'offline' ? (
          <ScreenState state="offline" onRetry={() => fetchTransfer()} />
        ) : error === 'unavailable' ? (
          // The read failed and said nothing about the order: the app's neutral error state, never "not found".
          <ScreenState state="error" onRetry={() => fetchTransfer()} />
        ) : (
          <View style={s.center}><Text style={[textStyle('body'), s.errorText]}>Transfer not found</Text></View>
        )}
      </View>
    );
  }

  const meta = transferStatusMeta(transfer.status);

  return (
    <View style={s.root}>
      <Header />
      <ScrollView
        contentContainerStyle={s.content}
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={v2.brand.red} />}
      >
        {/* Server-confirmed expiry: don't transfer (owner, 2026-09-19) */}
        {windowView.kind === 'closed' ? (
          <StateBlock title={windowView.title} tone="warning">
            <Text style={[textStyle('bodySm'), s.stateSub]}>{windowView.body}</Text>
          </StateBlock>
        ) : null}

        {/* Buyer delivery target. The details themselves are unchanged: whether fulfilment details (phone/email) show
            follows the final fulfilment policy (owner, 2026-09-19). On a closed order the heading is neutral, because
            "Send tickets to" would instruct the opposite of the block above it (owner, via D). */}
        <View style={s.section}>
          <Text style={[textStyle('micro'), s.sectionLabel]}>{orderClosed ? "Buyer's delivery details" : 'Send tickets to'}</Text>
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

        {!alreadySent && !orderClosed ? (
          <PlatformInstructions platform={platform} role="seller" buyerEmail={transfer.delivery_email} buyerPhone={transfer.delivery_phone} />
        ) : null}

        {windowView.kind === 'countdown' || windowView.kind === 'checking' || windowView.kind === 'last_checked_open' ? (
          <View style={[s.countdown, windowView.kind !== 'countdown' && s.countdownExpired]}>
            <Text style={[textStyle('bodySm'), s.countdownText, windowView.kind !== 'countdown' && s.countdownExpiredText]}>
              {windowView.line}
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
            <Button label={lastFailed ? 'Try again' : 'Mark as sent'} onPress={handleMarkSent} loading={busy} disabled={busy || refreshing || buyerDeliveryMissing} block style={s.cta} />
          </View>
        ) : null}

        {/* SELLER_SENT */}
        {transfer.status === 'seller_sent' ? (
          <StateBlock title="Marked as sent" tone="neutral">
            <Text style={[textStyle('bodySm'), s.stateText]}>Waiting for the buyer to confirm they received the tickets.</Text>
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

        {/* SELLER_SENT without a screenshot — 140's explicit recovery */}
        {transfer.status === 'seller_sent' && !transfer.transfer_evidence_path ? (
          <View style={s.block}>
            <Text style={[textStyle('micro'), s.sectionLabel]}>{ATTACH_COPY.title}</Text>
            <Text style={[textStyle('bodySm'), s.confirmNote]}>{ATTACH_COPY.body}</Text>
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
            <Button label={lastFailed ? 'Try again' : ATTACH_COPY.cta} onPress={handleAttachProof} loading={busy} disabled={busy || refreshing} block style={s.cta} />
          </View>
        ) : null}

        {/* BUYER_CONFIRMED */}
        {transfer.status === 'buyer_confirmed' ? (
          <StateBlock title="Tickets received" tone="success">
            <Text style={[textStyle('bodySm'), s.stateText]}>
              {transfer.payout_released_at
                ? 'The buyer confirmed they received the tickets. Your payout has been released.'
                : 'The buyer confirmed they received the tickets. Your payout is being processed, make sure your payout account is set up in Settings.'}
            </Text>
          </StateBlock>
        ) : null}

        {/* AUTO_RELEASED */}
        {transfer.status === 'auto_released' ? (
          // The status is the release DECISION; `payout_released_at` is written only after the Stripe transfer
          // succeeds, and the job can skip a payout and retry for ever. So the money claim waits for that field
          // (owner, 2026-09-19) — the same gate buyer_confirmed already uses.
          <StateBlock title={transfer.payout_released_at ? 'Payout released' : 'Review window passed'} tone={transfer.payout_released_at ? 'success' : 'neutral'}>
            <Text style={[textStyle('bodySm'), s.stateText]}>
              {transfer.payout_released_at
                ? 'The buyer review window passed without a dispute. Your payout has been released.'
                : 'The buyer review window passed without a dispute. Your payout has not been recorded as released yet. Contact support@snatchitapp.com if it does not arrive.'}
            </Text>
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

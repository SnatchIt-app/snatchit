/**
 * src/screens/primary/PrimaryCheckoutEntry.native.tsx — the primary checkout, native (CONTRACTS C3).
 *
 * A PAYMENTS SURFACE: reviewed by A before any merge. Reuses the app's Stripe module (the same
 * PaymentSheet the resale checkout uses); touches no gated file.
 *
 * Flow, all server-authoritative:
 *   1. hold    — `public.reserve_primary_tier` (D's 167, DARK; PGRST202 → "Checkout isn't available yet")
 *   2. quote   — edge `primary-checkout` WITHOUT expected_total_cents (first call); the server creates the
 *                order and the PaymentIntent for its own all-in total
 *   3. resume  — if the edge answers `already_paid` (409), or Stripe already reports that PaymentIntent
 *                paid (a 3-D Secure return or a killed app), no second sheet: go straight to the ticket page
 *   4. review  — the all-in total is the headline, itemised beneath; money moves only in the sheet
 *   5. sheet   — completed → the ticket page ("Awaiting payment confirmation" until the webhook issues
 *                tickets); canceled → back to review; failed → review with the failure line
 * A price change (409 total_mismatch) shows the server's new total; "Review new total" re-quotes WITH
 * expected_total_cents = that total, so the buyer only ever pays a total they were shown.
 *
 * One attempt id per purchase intent, kept in the route params so the remount after a 3-D Secure
 * challenge (the return URL carries it) replays the same command keys: same hold, same order, same
 * PaymentIntent. Double taps on Pay are absorbed by a ref latch.
 */
import { useStripe } from '@stripe/stripe-react-native';
import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { useAuth } from '@/src/hooks/useAuth';
import { useNetworkStatus } from '@/src/hooks/useNetworkStatus';
import {
  attemptCommandKey,
  intentAlreadyPaid,
  newAttemptId,
  requestPrimaryQuote,
  sheetOutcome,
  type PrimaryQuote,
} from '@/src/lib/primary/checkout';
import { buildPrimaryReturnURL, parsePrimaryCheckoutParams, reservePrimaryTier } from '@/src/lib/primary/checkoutRoute';
import { primarySessionRpc, readPrimarySessionDetail } from '@/src/lib/primary/discovery';
import { supabaseInvoker } from '@/src/lib/tickets/entitlementReads';
import { PrimaryCheckoutView, type PrimaryCheckoutViewState } from '@/src/screens/primary/PrimaryCheckoutView';

function randomBytes(n: number): Uint8Array {
  const out = new Uint8Array(n);
  globalThis.crypto.getRandomValues(out);   // react-native-get-random-values
  return out;
}

function clockText(iso: string | null): string | null {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  return new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit' }).format(d);
}

export default function PrimaryCheckoutNative() {
  const raw = useLocalSearchParams<{ session?: string; tt?: string; qty?: string; attempt?: string }>();
  const params = useMemo(() => parsePrimaryCheckoutParams(raw), [raw.session, raw.tt, raw.qty, raw.attempt]); // eslint-disable-line react-hooks/exhaustive-deps
  const { user, loading: authLoading } = useAuth();
  const { isOffline } = useNetworkStatus();
  const { initPaymentSheet, presentPaymentSheet, retrievePaymentIntent } = useStripe();

  // One attempt per purchase intent: from the URL (a 3-D Secure remount) or drawn once here.
  const drawnAttempt = useRef<string | null>(null);
  if (params.ok && !params.attemptId && !drawnAttempt.current) drawnAttempt.current = newAttemptId(randomBytes);
  const attemptId = params.ok ? params.attemptId ?? drawnAttempt.current : null;
  useEffect(() => {
    if (params.ok && !params.attemptId && attemptId) router.setParams({ attempt: attemptId });
  }, [params, attemptId]);

  const [state, setState] = useState<PrimaryCheckoutViewState>({ kind: 'preparing' });
  const [heldUntil, setHeldUntil] = useState<string | null>(null);
  const [eventTitle, setEventTitle] = useState<string | null>(null);
  const [tierName, setTierName] = useState<string | null>(null);
  const holdIdRef = useRef<string | null>(null);
  const payingRef = useRef(false);
  const runRef = useRef(0);

  const submitted = useCallback((sessionId: string) => {
    router.replace(`/ticket/${sessionId}`);
  }, []);

  /** Quote (optionally against a total the buyer was shown), resume if already paid, else prepare the sheet. */
  const quoteAndPrepare = useCallback(async (shownTotalMinor: number | null) => {
    if (!params.ok || !attemptId || !holdIdRef.current) return;
    const run = ++runRef.current;
    setState({ kind: 'preparing' });
    const result = await requestPrimaryQuote(supabaseInvoker, {
      sessionId: params.sessionId,
      items: [{ ticketTypeId: params.ticketTypeId, quantity: params.quantity }],
      holdIds: [holdIdRef.current],
      commandKey: attemptCommandKey(params.sessionId, attemptId),
      shownTotalMinor,
    });
    if (run !== runRef.current) return;
    if (!result.ok) {
      if (result.reason === 'already_paid') { submitted(params.sessionId); return; }
      if (result.reason === 'price_changed') setState({ kind: 'price_changed', serverTotalMinor: result.serverTotalMinor });
      else setState({ kind: 'quote_refused', reason: result.reason });
      return;
    }
    const quote: PrimaryQuote = result.quote;
    const existing = await retrievePaymentIntent(quote.clientSecret);
    if (run !== runRef.current) return;
    if (intentAlreadyPaid(existing.paymentIntent?.status)) { submitted(params.sessionId); return; }
    setState({ kind: 'review', quote, sheetReady: false, paying: false, paymentFailed: false });
    const { error } = await initPaymentSheet({
      paymentIntentClientSecret: quote.clientSecret,
      merchantDisplayName: 'Snatch It',
      returnURL: buildPrimaryReturnURL({ sessionId: params.sessionId, ticketTypeId: params.ticketTypeId, quantity: params.quantity, attemptId }),
      allowsDelayedPaymentMethods: false,
      customerId: quote.customerId,
      customerEphemeralKeySecret: quote.ephemeralKeySecret,
      ...(user?.email ? { defaultBillingDetails: { email: user.email } } : {}),
    });
    if (run !== runRef.current) return;
    if (error) { setState({ kind: 'quote_refused', reason: 'unavailable' }); return; }
    setState({ kind: 'review', quote, sheetReady: true, paying: false, paymentFailed: false });
  }, [params, attemptId, initPaymentSheet, retrievePaymentIntent, submitted, user?.email]);

  const start = useCallback(async () => {
    if (!params.ok) { setState({ kind: 'invalid' }); return; }
    if (!user) { setState({ kind: 'signed_out' }); return; }
    if (!attemptId) return;
    const run = ++runRef.current;
    setState({ kind: 'preparing' });
    void readPrimarySessionDetail(primarySessionRpc, params.sessionId, isOffline).then((d) => {
      if (d.kind !== 'ready') return;
      setEventTitle(d.detail.facts.title);
      setTierName(d.detail.tiers.find((t) => t.ticket_type_id === params.ticketTypeId)?.name ?? null);
    });
    const hold = await reservePrimaryTier({
      sessionId: params.sessionId,
      ticketTypeId: params.ticketTypeId,
      quantity: params.quantity,
      commandKey: `ph-${attemptCommandKey(params.sessionId, attemptId).slice(3)}`,
    });
    if (run !== runRef.current) return;
    if (!hold.ok) { setState({ kind: 'hold_refused', reason: hold.reason }); return; }
    holdIdRef.current = hold.holdId;
    setHeldUntil(clockText(hold.expiresAt));
    await quoteAndPrepare(null);
  }, [params, user, attemptId, isOffline, quoteAndPrepare]);

  useEffect(() => {
    if (authLoading) return;
    void start();
  }, [authLoading, start]);

  const onPay = useCallback(async () => {
    if (state.kind !== 'review' || !state.sheetReady || payingRef.current || !params.ok) return;
    payingRef.current = true;
    const quote = state.quote;
    setState({ kind: 'review', quote, sheetReady: true, paying: true, paymentFailed: false });
    const { error } = await presentPaymentSheet();
    payingRef.current = false;
    const outcome = sheetOutcome(error);
    if (outcome === 'completed') { submitted(params.sessionId); return; }
    setState({ kind: 'review', quote, sheetReady: true, paying: false, paymentFailed: outcome === 'failed' });
  }, [state, params, presentPaymentSheet, submitted]);

  return (
    <PrimaryCheckoutView
      state={state}
      eventTitle={eventTitle}
      tierName={tierName}
      quantity={params.ok ? params.quantity : 0}
      heldUntil={heldUntil}
      onPay={() => { void onPay(); }}
      onReviewAgain={() => { void quoteAndPrepare(state.kind === 'price_changed' ? state.serverTotalMinor : null); }}
      onRetry={() => { void start(); }}
      onSignIn={() => router.push('/(auth)/login')}
      onBack={() => (router.canGoBack() ? router.back() : params.ok ? router.replace(`/event/${params.sessionId}`) : router.replace('/(tabs)/home'))}
    />
  );
}

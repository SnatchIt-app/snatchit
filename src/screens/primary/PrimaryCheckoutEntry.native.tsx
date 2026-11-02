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
 *                tickets); canceled or failed → first the same key again and Stripe's reading of the
 *                intent (c35, D1: a sheet error is not proof the charge failed): paid → the ticket page;
 *                unreachable → no Pay, "Check again" or the ticket page; else review (the failure line
 *                only after `failed` with the intent back at requires_payment_method)
 * A price change (409 total_mismatch) shows the server's new total; "Review new total" re-quotes WITH
 * expected_total_cents = that total, so the buyer only ever pays a total they were shown.
 *
 * One attempt id per purchase intent, kept in the route params so the remount after a 3-D Secure
 * challenge (the return URL carries it) replays the same command keys: same hold, same order, same
 * PaymentIntent. Double taps on Pay are absorbed by a ref latch.
 *
 * c35 (D4/D5): the purchase starts once per mount. It is keyed on primitives and the user id — supabase-js
 * hands out a new session object on INITIAL_SESSION and every TOKEN_REFRESHED, and a re-run under an open
 * sheet re-initialised it (on Android that drops the sheet's result). Connectivity is read through a ref. A
 * screen that is closed or covered stops: the PaymentSheet is one per process and router.replace acts on
 * whichever screen is on top, so a stale run may neither configure the sheet nor navigate.
 */
import { isPlatformPaySupported, PlatformPay, useStripe } from '@stripe/stripe-react-native';
import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Platform } from 'react-native';

import { useAuth } from '@/src/hooks/useAuth';
import { useNetworkStatus } from '@/src/hooks/useNetworkStatus';
import {
  afterSheetVerdict,
  applePayCartItems,
  attemptCommandKey,
  intentAlreadyPaid,
  newAttemptId,
  requestPrimaryQuote,
  sheetOutcome,
  type PrimaryQuote,
} from '@/src/lib/primary/checkout';
import {
  buildPrimaryReturnURL,
  chooseAttempt,
  holdCommandKey,
  parsePrimaryCheckoutParams,
  reservePrimaryTier,
  type DrawnAttempt,
} from '@/src/lib/primary/checkoutRoute';
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
  const userId = user?.id ?? null;
  const userEmail = user?.email ?? null;
  const { isOffline } = useNetworkStatus();
  const offlineRef = useRef(isOffline);
  useEffect(() => { offlineRef.current = isOffline; }, [isOffline]);
  const { initPaymentSheet, presentPaymentSheet, retrievePaymentIntent } = useStripe();

  // One attempt per purchase intent: from the URL (a 3-D Secure remount) or drawn once here (checkoutRoute.ts).
  const drawnRef = useRef<DrawnAttempt | null>(null);
  const chosen = chooseAttempt(params, drawnRef.current, () => newAttemptId(randomBytes));
  drawnRef.current = chosen.drawn;
  const attemptId = chosen.attemptId;
  const ok = params.ok;
  const sessionId = params.ok ? params.sessionId : null;
  const ticketTypeId = params.ok ? params.ticketTypeId : null;
  const quantity = params.ok ? params.quantity : 0;
  const urlAttempt = params.ok ? params.attemptId : null;

  const [state, setState] = useState<PrimaryCheckoutViewState>({ kind: 'preparing' });
  const [heldUntil, setHeldUntil] = useState<string | null>(null);
  const [eventTitle, setEventTitle] = useState<string | null>(null);
  const [tierName, setTierName] = useState<string | null>(null);
  const holdIdRef = useRef<string | null>(null);
  const payingRef = useRef(false);
  const runRef = useRef(0);
  const detailRunRef = useRef(0);
  const submittedRef = useRef(false);

  // Declared first, so every later effect sees a live screen; the cleanup retires any run still in flight.
  const aliveRef = useRef(false);
  useEffect(() => {
    aliveRef.current = true;
    return () => { aliveRef.current = false; runRef.current += 1; };
  }, []);
  const live = useCallback((run: number) => aliveRef.current && run === runRef.current, []);

  useEffect(() => {
    if (aliveRef.current && sessionId && !urlAttempt && attemptId) router.setParams({ attempt: attemptId });
  }, [sessionId, urlAttempt, attemptId]);

  const submitted = useCallback(() => {
    // Once per screen, and never from a screen that is gone.
    if (submittedRef.current || !aliveRef.current) return;
    submittedRef.current = true;
    router.replace(`/ticket/${sessionId}`);
  }, [sessionId]);

  /**
   * Configure the one process-wide PaymentSheet for THIS quote (D5: another screen — a covered checkout, the
   * resale checkout — may have configured it since). `stillMine` is asked last, so a retired caller never
   * initialises it. True once the sheet is ready.
   */
  const initSheetFor = useCallback(async (quote: PrimaryQuote, stillMine: () => boolean): Promise<boolean> => {
    if (!sessionId || !ticketTypeId || !attemptId) return false;
    // Apple Pay as in the resale checkout: iOS only; a probe that throws is "unsupported", and the sheet
    // still offers cards. The Apple Pay lines carry the same all-in total as the review.
    let applePay = false;
    if (Platform.OS === 'ios') {
      try { applePay = await isPlatformPaySupported(); } catch { applePay = false; }
    }
    if (!stillMine()) return false;
    const { error } = await initPaymentSheet({
      paymentIntentClientSecret: quote.clientSecret,
      merchantDisplayName: 'Snatch It',
      returnURL: buildPrimaryReturnURL({ sessionId, ticketTypeId, quantity, attemptId }),
      allowsDelayedPaymentMethods: false,
      customerId: quote.customerId,
      customerEphemeralKeySecret: quote.ephemeralKeySecret,
      ...(userEmail ? { defaultBillingDetails: { email: userEmail } } : {}),
      ...(applePay ? { applePay: { merchantCountryCode: 'US', cartItems: applePayCartItems(quote).map((i): PlatformPay.CartSummaryItem => ({ ...i, paymentType: PlatformPay.PaymentType.Immediate })) } } : {}),
    });
    return !error;
  }, [sessionId, ticketTypeId, quantity, attemptId, initPaymentSheet, userEmail]);

  /** The review, then the sheet for THIS quote; Pay arms only once the sheet is ready. */
  const prepareSheet = useCallback(async (run: number, quote: PrimaryQuote, paymentFailed: boolean) => {
    setState({ kind: 'review', quote, sheetReady: false, paying: false, paymentFailed });
    const ready = await initSheetFor(quote, () => live(run));
    if (!live(run)) return;
    if (!ready) { setState({ kind: 'quote_refused', reason: 'unavailable' }); return; }
    setState({ kind: 'review', quote, sheetReady: true, paying: false, paymentFailed });
  }, [initSheetFor, live]);

  /** Quote (optionally against a total the buyer was shown), resume if already paid, else prepare the sheet. */
  const quoteAndPrepare = useCallback(async (shownTotalMinor: number | null) => {
    if (!sessionId || !ticketTypeId || !attemptId || !holdIdRef.current) return;
    const run = ++runRef.current;
    setState({ kind: 'preparing' });
    const result = await requestPrimaryQuote(supabaseInvoker, {
      sessionId,
      items: [{ ticketTypeId, quantity }],
      holdIds: [holdIdRef.current],
      commandKey: attemptCommandKey(sessionId, attemptId),
      shownTotalMinor,
    });
    if (!live(run)) return;
    if (!result.ok) {
      if (result.reason === 'already_paid') { submitted(); return; }
      if (result.reason === 'price_changed') setState({ kind: 'price_changed', serverTotalMinor: result.serverTotalMinor });
      else setState({ kind: 'quote_refused', reason: result.reason });
      return;
    }
    const quote: PrimaryQuote = result.quote;
    const existing = await retrievePaymentIntent(quote.clientSecret);
    if (!live(run)) return;
    if (intentAlreadyPaid(existing.paymentIntent?.status)) { submitted(); return; }
    await prepareSheet(run, quote, false);
  }, [sessionId, ticketTypeId, quantity, attemptId, retrievePaymentIntent, submitted, live, prepareSheet]);

  /**
   * After a sheet that did not complete (D1): the same key again, against the total the buyer was shown, then
   * Stripe's reading of the replayed intent — and only then a verdict (afterSheetVerdict, checkout.ts).
   */
  const checkAfterSheet = useCallback(async (quote: PrimaryQuote, outcome: 'canceled' | 'failed') => {
    if (!sessionId || !ticketTypeId || !attemptId || !holdIdRef.current) return;
    const run = ++runRef.current;
    setState({ kind: 'checking' });
    const replay = await requestPrimaryQuote(supabaseInvoker, {
      sessionId,
      items: [{ ticketTypeId, quantity }],
      holdIds: [holdIdRef.current],
      commandKey: attemptCommandKey(sessionId, attemptId),
      shownTotalMinor: quote.totalMinor,
    });
    if (!live(run)) return;
    let intent: { status: string | null; reachable: boolean } | null = null;
    if (replay.ok) {
      const read = await retrievePaymentIntent(replay.quote.clientSecret);
      if (!live(run)) return;
      intent = { status: read.paymentIntent?.status ?? null, reachable: !read.error };
    }
    const verdict = afterSheetVerdict(outcome, replay, intent);
    switch (verdict.kind) {
      case 'submitted': submitted(); return;
      case 'unverified': setState({ kind: 'unverified', quote, outcome }); return;
      case 'price_changed': setState({ kind: 'price_changed', serverTotalMinor: verdict.serverTotalMinor }); return;
      case 'refused': setState({ kind: 'quote_refused', reason: verdict.reason }); return;
      default: await prepareSheet(run, verdict.quote, verdict.paymentFailed);
    }
  }, [sessionId, ticketTypeId, quantity, attemptId, retrievePaymentIntent, submitted, live, prepareSheet]);

  const start = useCallback(async () => {
    if (!ok || !sessionId || !ticketTypeId) { setState({ kind: 'invalid' }); return; }
    if (!userId) { setState({ kind: 'signed_out' }); return; }
    if (!attemptId) return;
    const run = ++runRef.current;
    setState({ kind: 'preparing' });
    const detailRun = ++detailRunRef.current;
    void readPrimarySessionDetail(primarySessionRpc, sessionId, offlineRef.current).then((d) => {
      if (!aliveRef.current || detailRun !== detailRunRef.current || d.kind !== 'ready') return;
      setEventTitle(d.detail.facts.title);
      setTierName(d.detail.tiers.find((t) => t.ticket_type_id === ticketTypeId)?.name ?? null);
    });
    const hold = await reservePrimaryTier({
      sessionId,
      ticketTypeId,
      quantity,
      commandKey: holdCommandKey(sessionId, attemptId),
    });
    if (!live(run)) return;
    if (!hold.ok) { setState({ kind: 'hold_refused', reason: hold.reason }); return; }
    holdIdRef.current = hold.holdId;
    setHeldUntil(clockText(hold.expiresAt));
    await quoteAndPrepare(null);
  }, [ok, sessionId, ticketTypeId, quantity, attemptId, userId, quoteAndPrepare, live]);

  useEffect(() => {
    if (authLoading || payingRef.current) return;
    void start();
  }, [authLoading, start]);

  const onPay = useCallback(async () => {
    if (state.kind !== 'review' || !state.sheetReady || payingRef.current || !sessionId) return;
    payingRef.current = true;
    const quote = state.quote;
    setState({ kind: 'review', quote, sheetReady: true, paying: true, paymentFailed: false });
    const ready = await initSheetFor(quote, () => aliveRef.current);
    if (!aliveRef.current) { payingRef.current = false; return; }
    // The sheet could not be configured: nothing was presented and no money moved — quote again, same key.
    if (!ready) { payingRef.current = false; await quoteAndPrepare(quote.totalMinor); return; }
    const { error } = await presentPaymentSheet();
    payingRef.current = false;
    if (!aliveRef.current) return;
    const outcome = sheetOutcome(error);
    if (outcome === 'completed') { submitted(); return; }
    await checkAfterSheet(quote, outcome);
  }, [state, sessionId, initSheetFor, presentPaymentSheet, submitted, checkAfterSheet, quoteAndPrepare]);

  return (
    <PrimaryCheckoutView
      state={state}
      eventTitle={eventTitle}
      tierName={tierName}
      quantity={quantity}
      heldUntil={heldUntil}
      onPay={() => { void onPay(); }}
      onReviewAgain={() => { void quoteAndPrepare(state.kind === 'price_changed' ? state.serverTotalMinor : null); }}
      onRetry={() => { void start(); }}
      onCheckAgain={() => { if (state.kind === 'unverified') void checkAfterSheet(state.quote, state.outcome); }}
      onViewTickets={submitted}
      onSignIn={() => router.push('/(auth)/login')}
      onBack={() => (router.canGoBack() ? router.back() : sessionId ? router.replace(`/event/${sessionId}`) : router.replace('/(tabs)/home'))}
    />
  );
}

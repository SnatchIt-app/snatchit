/**
 * src/screens/checkout/CheckoutNative.tsx — the native Stripe checkout.
 *
 * V2 presentation over the release-candidate payment path: reservation
 * pre-check, createPaymentIntent, the Apple Pay probe and cart, initPaymentSheet
 * with saved cards, presentPaymentSheet, then finalizePurchase — the one
 * post-charge sequence for Buy Now and auctions alike (src/lib/payments.ts).
 * serverBreakdown remains the sole authority for every displayed amount; this
 * screen performs no money arithmetic of its own.
 *
 * What the redesign adds: the event artwork, name and date, so the buyer can see
 * what they are paying for (the old screen showed two text rows and no image); a
 * live reservation countdown for Buy Now; and the V2 primitives. The screen is
 * loaded only on native, through CheckoutEntry's platform resolution, so
 * @stripe/stripe-react-native never enters the web bundle.
 */

import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Alert, Platform } from 'react-native';
import {
  isPlatformPaySupported,
  PlatformPay,
  useStripe,
} from '@stripe/stripe-react-native';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import {
  confirmPaymentSuccess,
  createPaymentIntent,
  finalizePurchase,
  isExpectedCheckoutError,
  SETTLEMENT_COPY,
  type SettlementOutcome,
  PriceChangedError,
  reconcilePriceChange,
} from '@/src/lib/payments';
import * as Sentry from '@sentry/react-native';

import { buyerTotalCents, dollarsToCents, formatCents } from '@/src/lib/money';
import CheckoutView, {
  CheckoutShell,
  ConfirmationView,
  RefundView,
} from './CheckoutView';
import {
  LISTING_SUMMARY_COLUMNS,
  mapListingSummary,
  reservedUntilMs,
  type ListingSummary,
  type ListingSummaryRow,
} from '@/src/lib/checkout/listingSummary';
import { payControl, fmtCountdown, withinExpiryMargin } from '@/src/lib/checkout/payControl';
import { ESCROW_NOTE_COPY, fmtHoldUntil, notHeldCopy, notHeldReason, PAYMENT_STATUS_UNKNOWN_COPY, RESERVATION_UNVERIFIABLE_COPY, refundViewModel, showEscrowNote } from '@/src/lib/checkout/holdState';
import { paymentSheetErrorCopy } from '@/src/lib/checkout/paymentErrors';
import { createSingleFlight } from '@/src/lib/checkout/paymentGuard';
import { decideCheckoutSetup, decideRevalidation, type RefundState } from '@/src/lib/checkout/setupDecision';
import { readListingHold, readSettledPayments, SettledReadError } from '@/src/lib/checkout/settledRead';

// User-safe message for any non-actionable setup failure. The REAL error
// (stage + detail) goes to console + Sentry via reportCheckoutFailure so we
// can distinguish intent-creation vs customer/ephemeral vs sheet-init
// failures without ever surfacing raw Stripe internals to buyers.
const SAFE_PAYMENT_ERROR = "We couldn't start payment. Please try again.";

type CheckoutStage = 'reservation-check' | 'payment-intent' | 'sheet-init' | 'payment-status';

function reportCheckoutFailure(stage: CheckoutStage, detail: string) {
  console.error(`[checkout] setup failed at ${stage}:`, detail);
  Sentry.captureMessage(`checkout_setup_failed:${stage} \u2014 ${detail}`, 'error');
}


// --- Screen ----------------------------------------------------------------

export default function CheckoutScreen() {
  const { user, loading: authLoading } = useAuth();
  const { initPaymentSheet, presentPaymentSheet } = useStripe();

  const params = useLocalSearchParams<{
    id:         string;
    mode:       string;
    bidAmount:  string;
    totalCents: string;
    eventName:  string;
    venue:      string;
  }>();

  const listingId = params.id ?? '';
  const isBuyNow  = params.mode === 'buy_now';
  const bidAmount = parseInt(params.bidAmount ?? '0', 10);
  // Display estimate only \u2014 computed with the canonical money util by the
  // caller. The server result (below) is the authority for what is charged,
  // and create-payment-intent rejects a mismatched expected total.
  const estimatedTotalCents = parseInt(params.totalCents ?? '0', 10)
    || buyerTotalCents(dollarsToCents(bidAmount));
  const eventName = params.eventName ?? '\u2014';
  const venue     = params.venue     ?? '\u2014';

  // -- State ----------------------------------------------------------------

  const [confirming,      setConfirming]      = useState(false);
  // null until the PaymentSheet has settled one way or another. Replaces the
  // old boolean `sold`, which was set even when settlement had NOT completed.
  const [settlement,      setSettlement]      = useState<SettlementOutcome | null>(null);
  const [postPurchaseTransferId, setPostPurchaseTransferId] = useState<string | null>(null);
  const [paymentReady,    setPaymentReady]    = useState(false);
  const [paymentLoading,  setPaymentLoading]  = useState(false);
  const [paymentIntentId, setPaymentIntentId] = useState<string | null>(null);
  // Server-computed money (cents). Once loaded, the order summary and pay
  // buttons render ONLY these numbers — never a client-derived total.
  const [serverBreakdown, setServerBreakdown] = useState<{
    amount: number; buyerFee: number; total: number;
  } | null>(null);
  const [paymentError,    setPaymentError]    = useState<string | null>(null);
  // null = probe hasn't run yet; true/false = result. Used only for analytics
  // and to soften the payment-method subtext while applePay config flows
  // entirely through initPaymentSheet (no separate button rendered).
  const [applePayAvailable, setApplePayAvailable] = useState<boolean | null>(null);

  // ── Premium batch 1 state ──────────────────────────────────────────────
  // The total the buyer has explicitly accepted. Starts as the route estimate
  // and only changes through acceptNewTotal(); it is what the server verifies
  // (A-02). Kept in a ref too so the setup closure always sends the latest.
  const [acceptedTotalCents, setAcceptedTotalCents] = useState(estimatedTotalCents);
  const acceptedTotalRef = useRef(estimatedTotalCents);
  // A price change the buyer has not accepted yet.
  const [priceChange, setPriceChange] = useState<{ previousCents: number; nextCents: number } | null>(null);
  // The hold is known to be gone. `releasedByUs` is true only when THIS
  // screen's release call succeeded; the wording depends on it (CFT-301).
  const [holdLost, setHoldLost] = useState<{ releasedByUs: boolean; at: number } | null>(null);
  // A refund state found at setup (A-03). Never a purchase success.
  const [refundState, setRefundState] = useState<RefundState | null>(null);
  // F-CHK-READERR: the settled-payment lookup failed, so whether the buyer already paid is unknown. Pay is withheld
  // and the only action re-runs the check (setup), until a read succeeds.
  const [statusUnknown, setStatusUnknown] = useState(false);
  // The payment lookup itself failed (not the reservation's): hides the escrow line (owner, 2026-09-19).
  const [paymentStatusUnknown, setPaymentStatusUnknown] = useState(false);
  // The reservation lookup failed: also hides the escrow line until a listing read succeeds (owner, 2026-09-19).
  const [reservationStatusUnknown, setReservationStatusUnknown] = useState(false);
  // A payment result is being reconciled with the server (A-04).
  const [checking, setChecking] = useState(false);
  // CFT-306: the settlement record after the charge is a step of its own.
  const [finalizing, setFinalizing] = useState(false);
  // The server could not be reached to confirm a payment: no Pay is offered
  // until a reachable check says the money did not land.
  const [checkUnreachable, setCheckUnreachable] = useState(false);
  const holdRecheckedRef = useRef(false);

  const confirmedRef = useRef(false);
  const setupPaymentRef = useRef<(() => void) | null>(null);
  // Synchronous in-flight latch for the payment-sheet presentation. React state
  // (`confirming`) does not update before a second tap's handler runs, so a rapid
  // double-tap could call presentPaymentSheet() twice and the native module then
  // throws "Tried to resolve a promise more than once". This latch blocks re-entry
  // within the same frame; it is released in each handler's finally (so a cancel
  // or error cleanly allows a retry). See src/lib/checkout/paymentGuard.ts.
  const payLatchRef = useRef(createSingleFlight());

  // -- Listing display: what the buyer is paying for ------------------------
  // A read-only fetch of the event's display fields, independent of the payment
  // flow. It touches no money and never blocks or fails payment. The old screen
  // showed the event and venue as two text rows and no artwork at all, on the
  // one screen where the money actually leaves.
  const [display, setDisplay] = useState<ListingSummary | null>(null);
  const [reservedUntil, setReservedUntil] = useState<number | null>(null);

  useEffect(() => {
    let alive = true;
    (async () => {
      const { data, error } = await supabase
        .from('listings')
        .select(LISTING_SUMMARY_COLUMNS)
        .eq('id', listingId)
        .maybeSingle();
      if (!alive) return;
      if (error || !data) {
        // F1: this read is cosmetic — it must never block or fail the payment.
        // It stays quiet and the screen keeps the values navigation passed in.
        if (error) console.warn('[checkout] listing summary unavailable:', error.message);
        return;
      }
      const row = data as ListingSummaryRow;
      setDisplay(mapListingSummary(row, { eventName, venue }));
      if (isBuyNow) {
        const until = reservedUntilMs(row);
        if (until != null) setReservedUntil(until);
      }
    })();
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [listingId]);

  // Live reservation countdown for Buy Now.
  const [nowTs, setNowTs] = useState(() => Date.now());
  useEffect(() => {
    if (!isBuyNow) return;
    const t = setInterval(() => setNowTs(Date.now()), 1000);
    return () => clearInterval(t);
  }, [isBuyNow]);
  const reservationMsLeft = reservedUntil ? Math.max(0, reservedUntil - nowTs) : null;

  // -- Initialize Stripe PaymentSheet on mount ------------------------------

  useEffect(() => {
    if (authLoading) return;
    if (!user?.id) return;

    async function setupPayment() {
      try {
        setPaymentLoading(true);
        setPaymentError(null);
        setStatusUnknown(false);

        // Settled-first, then hold, then intent — see setupDecision.ts. The
        // 3-D Secure return can remount this screen after the charge landed;
        // that must render the completed settlement, never "reservation
        // expired", and must never create a second intent (auction included).
        const decision = await decideCheckoutSetup(
          { listingId, buyerId: user!.id, mode: isBuyNow ? 'buy_now' : 'auction' },
          {
            fetchSettledPayment: async (lid, bid) => {
              // Several rows may exist (a refunded one and a later succeeded one);
              // pickSettled prefers succeeded (A-03). F-CHK-READERR: the one shared
              // read; a failure throws, so setup stops before the hold and any intent.
              const read = await readSettledPayments(supabase, lid, bid);
              if ('error' in read) throw new SettledReadError(read.error);
              // The payment status is established again only now, so the escrow line stays hidden during a re-check.
              setPaymentStatusUnknown(false);
              return read.rows;
            },
            fetchListing: async (lid) => {
              const { data, error } = await supabase
                .from('listings')
                .select('status, reserved_by, reserved_until')
                .eq('id', lid)
                .single();
              if (!error) setReservationStatusUnknown(false);
              return error ? null : data;
            },
            createIntent: () =>
              createPaymentIntent({
                listingId: listingId,
                buyerId: user!.id,
                mode: isBuyNow ? 'buy_now' : 'auction',
                // Server authority: this is the total we showed the buyer; the
                // server 409s rather than charge a different number.
                expectedTotalCents: acceptedTotalRef.current || undefined,
              }),
          },
        );

        if (decision.kind === 'payment_status_unknown') {
          // F-CHK-READERR (owner, 2026-09-18): a failed lookup is not "no payment". Say only that the status
          // couldn't be checked; the one action re-runs this check. Nothing is created or submitted until a read
          // succeeds.
          reportCheckoutFailure('payment-status', decision.detail);
          setStatusUnknown(true);
          setPaymentStatusUnknown(true);
          setPaymentError(PAYMENT_STATUS_UNKNOWN_COPY);
          return;
        }
        if (decision.kind === 'already_settled') {
          confirmedRef.current = true;
          setSettlement('completed');
          return;
        }
        if (decision.kind === 'refunded' || decision.kind === 'partially_refunded' || decision.kind === 'refund_unconfirmed') {
          // A-03: a refund is never a success and never a reason to set up a
          // new intent here. Its own screen says only what the recorded
          // amounts establish (owner, 2026-09-18).
          setRefundState(decision);
          return;
        }
        if (decision.kind === 'reservation_unverifiable') {
          // The hold may still be live, so claim nothing about it. Owner (2026-09-19): the same unknown state as
          // re-validation's — "Check again" re-runs this check; no Pay until a check succeeds.
          setStatusUnknown(true);
          setReservationStatusUnknown(true);
          setPaymentError(RESERVATION_UNVERIFIABLE_COPY);
          return;
        }
        if (decision.kind === 'not_held') {
          // CFT-301 (D9-UX-1): the server cannot say whether the hold ran out
          // or was released, so the screen reports only what it knows and the
          // only way forward is the listing. No retry, no re-reserve here.
          setHoldLost({ releasedByUs: false, at: Date.now() });
          return;
        }
        const result = decision.intent;

        setPaymentIntentId(result.paymentIntentId);
        // The order summary renders these server-computed amounts.
        setServerBreakdown({
          amount: result.amount,
          buyerFee: result.buyer_fee,
          total: result.total,
        });

        // ── Apple Pay availability probe (iOS only) ──────────────────────
        // isPlatformPaySupported() returns false on:
        //   • iOS Simulator (no Wallet integration)
        //   • iPad without Apple Pay (older devices)
        //   • iOS devices in regions where Apple Pay is unavailable
        //   • devices where the user has explicitly disabled Apple Pay
        // In every false case PaymentSheet still works — it just shows
        // card-only (and Link if enabled). That's the desired fallback.
        // We never call this on Android; we don't surface Google Pay here.
        let applePayAvailable = false;
        if (Platform.OS === 'ios') {
          try {
            applePayAvailable = await isPlatformPaySupported();
          } catch (probeErr) {
            // Treat a probe failure exactly like "unsupported" — never block
            // the card-only fallback path because of a wallet probe error.
            console.warn('[checkout] isPlatformPaySupported threw:', probeErr);
            applePayAvailable = false;
          }
        }
        setApplePayAvailable(applePayAvailable);

        // ── Apple Pay cart line items ────────────────────────────────────
        // Stripe / PassKit convention: the LAST item is the grand total and
        // its label is the merchant name shown in the Apple Pay sheet
        // (e.g. "Snatch It — $55.00"). All amounts are decimal-dollar
        // strings; internal math stays in integer cents.
        const applePayCartItems: PlatformPay.CartSummaryItem[] = [
          {
            paymentType: PlatformPay.PaymentType.Immediate,
            label: 'Ticket',
            amount: (result.amount / 100).toFixed(2),
          },
          {
            paymentType: PlatformPay.PaymentType.Immediate,
            label: 'Service fee',
            amount: (result.buyer_fee / 100).toFixed(2),
          },
          {
            paymentType: PlatformPay.PaymentType.Immediate,
            label: 'Snatch It',
            amount: (result.total / 100).toFixed(2),
          },
        ];

        // Defensive invariant: Apple Pay sheet will hang or display wrong
        // total if items don't sum. With integer-cent math upstream this
        // should never fire; surface as Sentry breadcrumb if it ever does.
        const itemsSum =
          Math.round(parseFloat(applePayCartItems[0].amount) * 100) +
          Math.round(parseFloat(applePayCartItems[1].amount) * 100);
        if (itemsSum !== result.total) {
          console.warn('[checkout] cart items do not sum to total', {
            itemsSum, total: result.total,
          });
        }

        const { error } = await initPaymentSheet({
          paymentIntentClientSecret: result.clientSecret,
          merchantDisplayName: 'Snatch It',
          // Must resolve to a REAL route. `snatchit://checkout` matched nothing
          // (app/checkout has only [id].tsx), so a completed 3-D Secure
          // challenge returned the buyer to expo-router's unmatched/sitemap
          // screen while the charge had already succeeded. The id sends them
          // back to the screen that owns this payment.
          returnURL: `snatchit://checkout/${listingId}`,
          allowsDelayedPaymentMethods: false,
          defaultBillingDetails: { email: user!.email },
          // P1-03: passing both customerId and the ephemeral key activates
          // PaymentSheet's "saved cards" UI. On the first checkout the user
          // enters a card; on subsequent checkouts the same card appears
          // as a saved option at the top of the sheet.
          customerId:                 result.customerId,
          customerEphemeralKeySecret: result.customerEphemeralKeySecret,
          ...(applePayAvailable && {
            applePay: {
              merchantCountryCode: 'US',
              cartItems: applePayCartItems,
            },
          }),
        });

        if (error) {
          reportCheckoutFailure('sheet-init', `${error.code}: ${error.message}`);
          setPaymentError(SAFE_PAYMENT_ERROR);
          return;
        }

        setPaymentReady(true);
      } catch (err: unknown) {
        if (err instanceof PriceChangedError) {
          // A-02: the server would charge a different total. Re-read the listing,
          // recompute the all-in total with the canonical helper, and offer the
          // new number only if the two agree. The buyer must tap to accept it;
          // nothing is resent automatically.
          // Mirrors create-payment-intent exactly: buy_now_price for Buy Now,
          // winning_bid_amount ?? current_bid for an auction (index.ts:499).
          const { data: fresh } = await supabase
            .from('listings')
            .select('buy_now_price, current_bid, winning_bid_amount')
            .eq('id', listingId)
            .maybeSingle();
          const baseDollars = isBuyNow
            ? fresh?.buy_now_price
            : (fresh?.winning_bid_amount ?? fresh?.current_bid);
          const freshTotalCents =
            typeof baseDollars === 'number' ? buyerTotalCents(dollarsToCents(baseDollars)) : null;
          const r = reconcilePriceChange({
            serverTotalCents: err.serverTotalCents,
            freshTotalCents,
            acceptedTotalCents: acceptedTotalRef.current,
          });
          if (r.outcome === 'accept_required') {
            setPriceChange({ previousCents: r.previousCents, nextCents: r.nextAcceptedCents });
          } else {
            reportCheckoutFailure('payment-intent', `price changed but totals disagree: server=${err.serverTotalCents} fresh=${freshTotalCents}`);
            setPaymentError(SAFE_PAYMENT_ERROR);
          }
          return;
        }
        const msg = err instanceof Error ? err.message : 'Failed to initialize payment.';
        if (isExpectedCheckoutError(msg)) {
          // Actionable, user-authored messages (price changed, listing sold,
          // reservation expired) pass through verbatim.
          setPaymentError(msg);
        } else {
          reportCheckoutFailure('payment-intent', msg);
          setPaymentError(SAFE_PAYMENT_ERROR);
        }
      } finally {
        setPaymentLoading(false);
      }
    }

    setupPaymentRef.current = setupPayment;
    setupPayment();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id, authLoading, listingId]);

  // -- Abandoned Buy Now hold ------------------------------------------------
  //
  // Dismissing the sheet leaves the listing reserved for the rest of its
  // 10-minute TTL, which locks every other buyer out of a listing nobody is
  // buying. But `Canceled` only says the UI closed; it does NOT say the charge
  // failed — the PaymentIntent can already have succeeded (Apple Pay confirms
  // before the sheet animates away). So the backend is asked first and the hold
  // is released ONLY on a reachable "Stripe does not have the money" verdict,
  // the one case where the payment cannot still complete without a fresh sheet.
  // A verified payment keeps its hold and settles like any other success; an
  // unreachable backend tells us nothing, so the server TTL stays the backstop.
  //
  // Returns true when the payment did land and the caller should settle it
  // instead of treating this as a cancel.
  async function releaseAbandonedHold(): Promise<boolean> {
    // Nothing was created, so there is nothing to release or to settle.
    if (!paymentIntentId || !user) return false;

    const confirm = await confirmPaymentSuccess(paymentIntentId);
    if (confirm.reachable && confirm.verified) return true;
    if (!confirm.reachable) return false;

    const { error } = await supabase.rpc('release_reservation', {
      p_listing_id: listingId,
      p_user_id:    user.id,
    });
    // Non-fatal: the 10-minute server TTL releases the hold regardless.
    if (error) console.warn('[checkout] release_reservation failed:', error.message);

    // The hold is gone, so this sheet's intent can no longer settle. Drop it and
    // hand the control back as "Back to listing": only a fresh Buy Now can
    // re-reserve, so a retry here would be a dead end (CFT-301). "Released" is
    // claimed only when our own call succeeded.
    setPaymentReady(false);
    setPaymentIntentId(null);
    setPaymentError(null);
    setHoldLost({ releasedByUs: !error, at: Date.now() });
    return false;
  }

  // -- Post-payment settlement (Buy Now + auction) ---------------------------
  //
  // The card is already charged once presentPaymentSheet() returns without an
  // error, so the ONLY thing left to decide is what the buyer is told. That
  // decision lives in finalizePurchase / classifySettlement (src/lib/payments.ts)
  // and has exactly three answers:
  //   completed — success screen
  //   pending   — the settlement has not landed YET (Stripe hasn't flipped the
  //               PaymentIntent, or the RPC never reached us). Nothing is lost;
  //               the webhook and the reconciliation sweep settle it. Calm
  //               screen, no alert. This used to raise "contact support" on a
  //               perfectly good purchase.
  //   failed    — money captured, order unfulfillable. Alert + no success screen.

  async function runSettlement(mode: 'buy_now' | 'auction') {
    if (!paymentReady || !user) return;
    if (!payLatchRef.current.begin()) return; // synchronous double-invocation guard
    setConfirming(true);

    try {
      const { error: paymentError } = await presentPaymentSheet();

      if (paymentError) {
        if (paymentError.code === 'Canceled') {
          // Buy Now only — an auction winner holds no reservation to give back.
          const paid = mode === 'buy_now' ? await releaseAbandonedHold() : false;
          if (!paid) {
            setConfirming(false);
            return;
          }
          // Stripe has the money: fall through to the normal settlement path
          // rather than discard a real payment.
        } else {
          // Raw SDK text (e.g. kCFErrorDomainCFNetwork -1001) stays in the log;
          // the customer sees one short line in the product's own vocabulary.
          console.warn('[checkout] presentPaymentSheet failed:', paymentError.code, paymentError.message);
          // A-04: a sheet error is not proof the charge failed (the network can
          // drop after Stripe has the money). Ask the server before offering Pay
          // again. Verified → settle. Reachable and unverified → Pay stays
          // available while the hold is live. Unreachable → no Pay at all.
          const verdict = await reconcileAfterSheetError();
          if (verdict !== 'verified') {
            if (verdict === 'not_verified') Alert.alert('Payment failed', paymentSheetErrorCopy(paymentError));
            setConfirming(false);
            return;
          }
          // Stripe has the money: fall through to settlement.
        }
      }

      setFinalizing(true);
      let result: Awaited<ReturnType<typeof finalizePurchase>>;
      try {
        result = await finalizePurchase({
          listingId,
          userId: user.id,
          paymentIntentId,
          mode,
        });
      } finally {
        setFinalizing(false);
      }

      if (result.outcome === 'failed') {
        Sentry.captureMessage(
          `checkout_settlement_failed — ${result.detail ?? 'unknown'}`,
          'error',
        );
        Alert.alert(
          SETTLEMENT_COPY.failed.title,
          SETTLEMENT_COPY.failed.body,
        );
      }

      if (result.transferId) {
        setPostPurchaseTransferId(result.transferId);
      }

      confirmedRef.current = result.outcome === 'completed';
      setSettlement(result.outcome);
    } catch (err: unknown) {
      Alert.alert(
        'Error',
        err instanceof Error ? err.message : 'Something went wrong.',
      );
    } finally {
      payLatchRef.current.end();
      setConfirming(false);
    }
  }

  const handleConfirmPurchase = () => runSettlement('buy_now');
  const handleAuctionPayment  = () => runSettlement('auction');

  // ── A-04: reconcile a payment result with the server ──────────────────────
  // Returns what the server said. Only 'verified' may lead to settlement.
  async function reconcileAfterSheetError(): Promise<'verified' | 'not_verified' | 'unreachable'> {
    if (!paymentIntentId) return 'not_verified';
    setChecking(true);
    try {
      const confirm = await confirmPaymentSuccess(paymentIntentId);
      if (confirm.reachable && confirm.verified) { setCheckUnreachable(false); return 'verified'; }
      if (confirm.reachable) { setCheckUnreachable(false); return 'not_verified'; }
      // Unreachable: we know nothing. Withdraw Pay until a reachable check says
      // the money did not land. The webhook, the sweep and the hold's TTL are
      // the backstop; the buyer is told not to pay again.
      setPaymentReady(false);
      setCheckUnreachable(true);
      return 'unreachable';
    } finally {
      setChecking(false);
    }
  }

  // ── The one server-side re-validation (A-04) ──────────────────────────────
  // Settled-first, then the hold. Used at the expiry margin and after a
  // reachable "not verified" check, so Pay is never restored on the strength of
  // the device clock alone (review, required change 2).
  async function revalidateAgainstServer(): Promise<'settled' | 'refund' | 'held' | 'lost' | 'unknown'> {
    if (!user) return 'lost';
    const buyerId = user.id;
    const outcome = await decideRevalidation(
      { buyerId, isBuyNow, now: new Date() },
      {
        readSettled: () => readSettledPayments(supabase, listingId, buyerId),
        readListing: () => readListingHold(supabase, listingId),
      },
    );
    if (outcome.kind === 'payment_status_unknown') {
      // F-CHK-READERR: never re-arm Pay and never report a lost hold on a failed lookup.
      reportCheckoutFailure('payment-status', outcome.detail);
      setPaymentReady(false);
      setStatusUnknown(true);
      setPaymentStatusUnknown(true);
      setPaymentError(PAYMENT_STATUS_UNKNOWN_COPY);
      return 'unknown';
    }
    if (outcome.kind === 'reservation_unverifiable') {
      // D's R2 (owner, 2026-09-19): the listing read failed, so the hold is UNKNOWN, not lost. Withhold Pay; claim
      // nothing about the hold or a charge. statusUnknown makes the control "Check again", which re-runs setup (the
      // check), never payment, and outranks any stale ready flag.
      reportCheckoutFailure('reservation-check', outcome.detail);
      setPaymentReady(false);
      setStatusUnknown(true);
      setReservationStatusUnknown(true);
      setPaymentError(RESERVATION_UNVERIFIABLE_COPY);
      return 'unknown';
    }
    if (outcome.kind === 'already_settled') { confirmedRef.current = true; setSettlement('completed'); return 'settled'; }
    if (outcome.kind === 'held') {
      // Follow the server's deadline; Pay returns only if it is outside the margin.
      if (outcome.reservedUntilMs != null) setReservedUntil(outcome.reservedUntilMs);
      return 'held';
    }
    if (outcome.kind === 'lost') {
      setPaymentReady(false);
      setHoldLost({ releasedByUs: false, at: Date.now() });
      return 'lost';
    }
    setRefundState(outcome); setPaymentReady(false); return 'refund';
  }

  // Manual "Check status" after an unreachable check. Never re-offers Pay on
  // its own: a reachable "not verified" re-offers it only after the SERVER
  // says the hold is still live; "verified" settles.
  async function recheckPayment() {
    if (!user || !paymentIntentId) return;
    const verdict = await reconcileAfterSheetError();
    if (verdict === 'verified') {
      setFinalizing(true);
      try {
        const result = await finalizePurchase({ listingId, userId: user.id, paymentIntentId, mode: isBuyNow ? 'buy_now' : 'auction' });
        if (result.transferId) setPostPurchaseTransferId(result.transferId);
        confirmedRef.current = result.outcome === 'completed';
        setSettlement(result.outcome);
      } finally {
        setFinalizing(false);
      }
      return;
    }
    if (verdict === 'not_verified') {
      setChecking(true);
      try {
        const state = await revalidateAgainstServer();
        if (state === 'held') setPaymentReady(true);
      } finally {
        setChecking(false);
      }
    }
  }

  // ── A-04: re-check the hold when the countdown enters the margin ──────────
  useEffect(() => {
    if (!isBuyNow || !paymentReady || !user || holdRecheckedRef.current) return;
    if (reservationMsLeft == null || !withinExpiryMargin(reservationMsLeft)) return;
    holdRecheckedRef.current = true;
    (async () => {
      setChecking(true);
      try {
        await revalidateAgainstServer();
      } finally {
        setChecking(false);
      }
    })();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isBuyNow, paymentReady, reservationMsLeft, user?.id]);

  // After the server-confirmed deadline passes, the hold has run out.
  useEffect(() => {
    if (!isBuyNow || !paymentReady || !holdRecheckedRef.current) return;
    if (reservationMsLeft === 0 && !checking) {
      setPaymentReady(false);
      setHoldLost({ releasedByUs: false, at: Date.now() });
    }
  }, [isBuyNow, paymentReady, reservationMsLeft, checking]);

  // ── A-02: the buyer accepts the new total, then setup runs again ─────────
  function acceptNewTotal() {
    if (!priceChange) return;
    acceptedTotalRef.current = priceChange.nextCents;
    setAcceptedTotalCents(priceChange.nextCents);
    setPriceChange(null);
    setupPaymentRef.current?.();
  }

  // -- Shared display derivations ------------------------------------------

  const cover     = display?.cover ?? null;
  const showName  = display?.eventName ?? eventName;
  const showVenue = display?.venue ?? venue;

  // The total is always the server figure once loaded; the client estimate is a
  // placeholder before createPaymentIntent returns. Neither is computed here. This mixed
  // figure feeds the pay control only, which prints it solely when payment is ready — i.e.
  // after the server has answered. The itemised rows below never read it (A, 2026-09-24).
  const totalCents   = serverBreakdown ? serverBreakdown.total : acceptedTotalCents;

  // -- Settlement outcome UI ------------------------------------------------
  // One screen, three faces. Only `completed` is allowed to say the purchase is
  // complete; `pending` and `failed` speak with SETTLEMENT_COPY, so the screen
  // and the alert can never disagree.

  // The identity block's facts, shared by all three faces.
  const identity = {
    cover,
    eventName: showName,
    venue: showVenue,
    eventDate: display?.date || null,
    eventTime: display?.time || null,
    quantity: display?.quantity ?? null,
    ticketType: display?.ticketType ?? null,
  };

  if (refundState) {
    return (
      <CheckoutShell>
        <RefundView view={refundViewModel(refundState.kind, refundState.refundedCents)} identity={identity} />
      </CheckoutShell>
    );
  }

  if (settlement) {
    return (
      <CheckoutShell>
        <ConfirmationView
          outcome={settlement}
          // The same table the failure alert reads, so the screen and the alert cannot diverge.
          copy={SETTLEMENT_COPY[settlement]}
          identity={identity}
          isBuyNow={isBuyNow}
          transferId={postPurchaseTransferId}
          purchaseKey={listingId}
        />
      </CheckoutShell>
    );
  }

  // -- Normal checkout UI ---------------------------------------------------

  // The pay control's single source of truth. The onPress mapping is exactly the
  // original: ready -> the mode's handler; error/idle -> re-run setup.
  const payHandler = isBuyNow ? handleConfirmPurchase : handleAuctionPayment;
  const pay = payControl({
    authLoading,
    paymentLoading,
    confirming,
    finalizing,
    checking,
    paymentReady,
    paymentError: !!paymentError,
    holdLost: !!holdLost,
    statusUnknown,
    reservationMsLeft: isBuyNow ? reservationMsLeft : null,
    formattedTotal: formatCents(totalCents),
  });
  const payOnPress =
    pay.action === 'pay' ? payHandler
    : pay.action === 'retry' ? () => setupPaymentRef.current?.()
    // A plain back navigation, so the listing screen's own exit path runs.
    : pay.action === 'back' ? () => router.back()
    : undefined;

  const holdCopy = holdLost
    ? notHeldCopy(notHeldReason({ releasedByUs: holdLost.releasedByUs, reservedUntilMs: reservedUntil, nowMs: holdLost.at }))
    : null;
  const holdUntil = reservedUntil ? fmtHoldUntil(reservedUntil) : null;

  const preparing = authLoading || paymentLoading;

  return (
    <CheckoutView
      identity={identity}
      isBuyNow={isBuyNow}
      // The hold row speaks only while a hold exists and has not been reported lost.
      reservationMsLeft={isBuyNow && reservationMsLeft != null && !holdLost ? reservationMsLeft : null}
      countdown={reservationMsLeft != null ? fmtCountdown(reservationMsLeft) : null}
      holdUntil={holdUntil}
      // Server figures only, and only once the intent has answered with no change pending. Every
      // amount is formatted HERE, by the one money module; the view formats nothing.
      breakdown={serverBreakdown && !priceChange ? {
        item: isBuyNow ? 'Tickets' : 'Winning bid',
        amount: formatCents(serverBreakdown.amount),
        fee: formatCents(serverBreakdown.buyerFee),
        total: formatCents(serverBreakdown.total),
      } : null}
      preparing={preparing}
      paymentMethodLine={!preparing && paymentReady ? (applePayAvailable ? 'Apple Pay or card' : 'Card payment') : null}
      // Precedence unchanged: a lost hold, then an unaccepted total, then an unconfirmed payment.
      notice={
        holdCopy ? { title: holdCopy.title, body: holdCopy.body }
        : priceChange ? {
            title: 'The total changed',
            body: `It was ${formatCents(priceChange.previousCents)} and is now ${formatCents(priceChange.nextCents)}, service fee included. Nothing has been charged. Accept the new total to continue.`,
          }
        : checkUnreachable ? {
            title: "We couldn't confirm your payment yet",
            body: "Your last attempt may or may not have gone through. Please don't pay again. We'll keep checking; you can also check now.",
            action: { label: 'Check status', onPress: recheckPayment, loading: checking },
          }
        : null
      }
      errorLine={paymentError}
      escrowNote={showEscrowNote({ paymentStatusUnknown, reservationStatusUnknown, confirmUnreachable: checkUnreachable })
        ? ESCROW_NOTE_COPY : null}
      pay={{ label: pay.label, loading: pay.loading, disabled: pay.disabled }}
      onPay={payOnPress}
      acceptTotal={priceChange
        ? { label: `Accept ${formatCents(priceChange.nextCents)}`, onPress: acceptNewTotal }
        : null}
      onBack={() => router.back()}
    />
  );
}


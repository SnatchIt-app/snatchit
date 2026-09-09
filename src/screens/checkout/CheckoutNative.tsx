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
import { Alert, Platform, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
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
} from '@/src/lib/payments';
import * as Sentry from '@sentry/react-native';

import { buyerTotalCents, dollarsToCents, formatCents } from '@/src/lib/money';
import { EventMedia } from '@/src/components/media/EventMedia';
import { PriceDisplay } from '@/src/components/PriceDisplay';
import { Button, IconButton, Spinner } from '@/src/components/ui';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import { payControl, fmtCountdown } from '@/src/lib/checkout/payControl';
import { paymentSheetErrorCopy } from '@/src/lib/checkout/paymentErrors';
import { createSingleFlight } from '@/src/lib/checkout/paymentGuard';

// User-safe message for any non-actionable setup failure. The REAL error
// (stage + detail) goes to console + Sentry via reportCheckoutFailure so we
// can distinguish intent-creation vs customer/ephemeral vs sheet-init
// failures without ever surfacing raw Stripe internals to buyers.
const SAFE_PAYMENT_ERROR = "We couldn't start payment. Please try again.";

type CheckoutStage = 'reservation-check' | 'payment-intent' | 'sheet-init';

function reportCheckoutFailure(stage: CheckoutStage, detail: string) {
  console.error(`[checkout] setup failed at ${stage}:`, detail);
  Sentry.captureMessage(`checkout_setup_failed:${stage} \u2014 ${detail}`, 'error');
}


// --- Screen ----------------------------------------------------------------

export default function CheckoutScreen() {
  const { user, loading: authLoading } = useAuth();
  const { initPaymentSheet, presentPaymentSheet } = useStripe();
  const insets = useSafeAreaInsets();

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
  const [display, setDisplay] = useState<{
    cover: string | null; eventName: string; venue: string; date: string; time: string;
  } | null>(null);
  const [reservedUntil, setReservedUntil] = useState<number | null>(null);

  useEffect(() => {
    let alive = true;
    (async () => {
      const { data } = await supabase
        .from('listings')
        .select('cover_image_path, cover_image_url, event_name, venue, event_date, event_time, reserved_until')
        .eq('id', listingId)
        .maybeSingle();
      if (!alive || !data) return;
      const d = data as {
        cover_image_path?: string | null; cover_image_url?: string | null;
        event_name?: string | null; venue?: string | null;
        event_date?: string | null; event_time?: string | null; reserved_until?: string | null;
      };
      setDisplay({
        cover: d.cover_image_path ?? d.cover_image_url ?? null,
        eventName: d.event_name ?? eventName,
        venue: d.venue ?? venue,
        date: d.event_date ?? '',
        time: d.event_time ?? '',
      });
      if (isBuyNow && d.reserved_until) setReservedUntil(new Date(d.reserved_until).getTime());
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

        // Buy Now: pre-validate reservation
        if (isBuyNow) {
          const { data: freshListing, error: fetchErr } = await supabase
            .from('listings')
            .select('status, reserved_by, reserved_until')
            .eq('id', listingId)
            .single();

          if (fetchErr || !freshListing) {
            setPaymentError('Unable to verify reservation. Please go back and try again.');
            return;
          }

          const reservedUntil = freshListing.reserved_until
            ? new Date(freshListing.reserved_until)
            : null;
          const stillReservedForMe =
            freshListing.status === 'reserved' &&
            freshListing.reserved_by === user!.id &&
            reservedUntil != null &&
            reservedUntil > new Date();

          if (!stillReservedForMe) {
            setPaymentError(
              'Your reservation has expired. Please go back and reserve again.',
            );
            return;
          }
        }

        const result = await createPaymentIntent({
          listingId: listingId,
          buyerId: user!.id,
          mode: isBuyNow ? 'buy_now' : 'auction',
          // Server authority: this is the total we showed the buyer; the
          // server 409s rather than charge a different number.
          expectedTotalCents: estimatedTotalCents || undefined,
        });

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
          returnURL: 'snatchit://checkout',
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
    // hand the control back as "Try again" rather than a live Pay button, so a
    // retry re-runs setup (and a second Buy Now can re-reserve from scratch).
    setPaymentReady(false);
    setPaymentIntentId(null);
    setPaymentError('Your hold was released. Please go back and reserve again.');
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
          Alert.alert('Payment Failed', paymentSheetErrorCopy(paymentError));
          setConfirming(false);
          return;
        }
      }

      const result = await finalizePurchase({
        listingId,
        userId: user.id,
        paymentIntentId,
        mode,
      });

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

  // -- Shared display derivations ------------------------------------------

  const cover     = display?.cover ?? null;
  const showName  = display?.eventName ?? eventName;
  const showVenue = display?.venue ?? venue;
  const whenLabel = display?.date ? fmtWhen(display.date, display.time) : '';

  // The total is always the server figure once loaded; the client estimate is a
  // placeholder before createPaymentIntent returns. Neither is computed here.
  const totalCents   = serverBreakdown ? serverBreakdown.total : estimatedTotalCents;
  const ticketCents  = serverBreakdown ? serverBreakdown.amount : dollarsToCents(bidAmount);
  const feeCents     = serverBreakdown ? serverBreakdown.buyerFee : estimatedTotalCents - dollarsToCents(bidAmount);

  // -- Settlement outcome UI ------------------------------------------------
  // One screen, three faces. Only `completed` is allowed to say the purchase is
  // complete; `pending` and `failed` speak with SETTLEMENT_COPY, so the screen
  // and the alert can never disagree.

  if (settlement) {
    return (
      <View style={s.safe}>
        <ConfirmationView
          outcome={settlement}
          cover={cover}
          eventName={showName}
          venue={showVenue}
          whenLabel={whenLabel}
          isBuyNow={isBuyNow}
          transferId={postPurchaseTransferId}
        />
      </View>
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
    paymentReady,
    paymentError: !!paymentError,
    formattedTotal: formatCents(totalCents),
  });
  const payOnPress =
    pay.action === 'pay' ? payHandler
    : pay.action === 'retry' ? () => setupPaymentRef.current?.()
    : undefined;

  const reservationExpired = reservationMsLeft === 0;

  return (
    <View style={s.safe}>
      {/* Header */}
      <View style={[s.topBar, { paddingTop: insets.top + v2.space.sm }]}>
        <IconButton glyph="back" accessibilityLabel="Go back" onPress={() => router.back()} />
        <Text style={[textStyle('displaySm'), s.topTitle]} accessibilityRole="header">Checkout</Text>
        <View style={s.topSpacer} />
      </View>

      <ScrollView contentContainerStyle={s.scroll} showsVerticalScrollIndicator={false}>

        {/* What you are buying */}
        <View style={s.orderRow}>
          <EventMedia
            asset={{ path: cover, contract: 'legacy', bucket: 'auction-media' }}
            slot="CHECKOUT_THUMBNAIL"
            title={showName}
            width={72}
            decorative
          />
          <View style={s.orderText}>
            <Text style={[textStyle('title'), s.eventName]} numberOfLines={2}>{showName}</Text>
            <Text style={[textStyle('bodySm'), s.meta]} numberOfLines={1}>{showVenue}</Text>
            {whenLabel ? (
              <Text style={[textStyle('bodySm'), s.meta]} numberOfLines={1}>{whenLabel}</Text>
            ) : null}
          </View>
        </View>

        {/* Reservation countdown (Buy Now) */}
        {isBuyNow && reservationMsLeft != null ? (
          <View style={s.holdRow}>
            <Text
              style={[textStyle('label'), reservationExpired ? s.holdExpired : s.hold]}
              accessibilityLiveRegion="none"
            >
              {reservationExpired
                ? 'Reservation expired'
                : `Held for you · ${fmtCountdown(reservationMsLeft)} left`}
            </Text>
          </View>
        ) : null}

        {/* Price breakdown — the one screen where itemising is correct. Every
            number is the server figure once loaded. */}
        <View style={s.breakdown}>
          <Row label={isBuyNow ? 'Ticket' : 'Winning bid'} value={formatCents(ticketCents)} />
          <Row label="Service fee" value={formatCents(feeCents)} />
          <View style={s.hairline} />
          <View style={s.totalRow}>
            <Text style={[textStyle('label'), s.totalLabel]}>Total</Text>
            <Text style={[textStyle('price'), s.totalValue]} numberOfLines={1}>
              {formatCents(totalCents)}
            </Text>
          </View>
          <Text style={[textStyle('bodySm'), s.meta]}>The service fee is included in this total.</Text>
        </View>

        {/* Payment method state */}
        <View style={s.payState}>
          {authLoading || paymentLoading ? (
            <View style={s.payStateRow}>
              <Spinner label="Preparing secure payment" />
              <Text style={[textStyle('body'), s.payStateText]}>Preparing secure payment</Text>
            </View>
          ) : paymentReady ? (
            <View style={s.payStateRow}>
              <Text style={[textStyle('body'), s.payStateText]}>
                {applePayAvailable ? 'Apple Pay or card' : 'Card payment'}
              </Text>
            </View>
          ) : paymentError ? (
            <View>
              <Text style={[textStyle('body'), s.payError]}>{paymentError}</Text>
            </View>
          ) : (
            <View style={s.payStateRow}>
              <Spinner label="Initializing" />
              <Text style={[textStyle('body'), s.payStateText]}>Initializing</Text>
            </View>
          )}
        </View>

        <Text style={[textStyle('bodySm'), s.trust]}>
          Payment is held until your ticket reaches you. Secured by Stripe.
        </Text>

        <View style={{ height: 120 }} />
      </ScrollView>

      {/* Sticky pay bar */}
      <View style={[s.bar, { paddingBottom: v2.space.md + insets.bottom }]}>
        <View style={s.barPrice}>
          <PriceDisplay size="sticky" label="Total" amount={formatCents(totalCents)} showTotal={false} />
        </View>
        <Button
          label={pay.label}
          onPress={payOnPress}
          variant="primary"
          size="md"
          disabled={pay.disabled}
          loading={pay.loading}
        />
      </View>
    </View>
  );
}

// -- Sub-components ----------------------------------------------------------

function Row({ label, value }: { label: string; value: string }) {
  return (
    <View style={s.row} accessible accessibilityLabel={`${label}: ${value}`}>
      <Text style={[textStyle('body'), s.rowLabel]}>{label}</Text>
      <Text style={[textStyle('body'), s.rowValue]} numberOfLines={1}>{value}</Text>
    </View>
  );
}

// The post-charge screen, in all three of its faces. `completed` is the only
// one allowed to claim the purchase is done; `pending` and `failed` take their
// words from SETTLEMENT_COPY so this screen and the alert cannot diverge.
function ConfirmationView({
  outcome, cover, eventName, venue, whenLabel, isBuyNow, transferId,
}: {
  outcome: SettlementOutcome;
  cover: string | null; eventName: string; venue: string; whenLabel: string;
  isBuyNow: boolean; transferId: string | null;
}) {
  const insets = useSafeAreaInsets();
  const copy = SETTLEMENT_COPY[outcome];
  const completed = outcome === 'completed';
  // Only a recorded sale has a transfer to hand off.
  const showTransfer = completed && !!transferId;
  return (
    <View style={s.confirmWrap}>
      <View style={[s.confirmBody, { paddingTop: insets.top + v2.space.xxl }]}>
        <Text
          style={[
            textStyle('micro'),
            s.confirmKicker,
            outcome === 'pending' && s.confirmKickerPending,
            outcome === 'failed'  && s.confirmKickerFailed,
          ]}
        >
          {completed
            ? (isBuyNow ? 'Purchase complete' : 'Payment complete')
            : outcome === 'pending' ? 'Finalizing your order' : 'Needs attention'}
        </Text>
        <Text style={[textStyle('displayLg'), s.confirmTitle]} accessibilityRole="header">
          {completed ? "You're in." : copy.title}
        </Text>

        <View style={s.confirmCard}>
          <EventMedia
            asset={{ path: cover, contract: 'legacy', bucket: 'auction-media' }}
            slot="CHECKOUT_THUMBNAIL"
            title={eventName}
            width={72}
            decorative
          />
          <View style={s.orderText}>
            <Text style={[textStyle('title'), s.eventName]} numberOfLines={2}>{eventName}</Text>
            <Text style={[textStyle('bodySm'), s.meta]} numberOfLines={1}>{venue}</Text>
            {whenLabel ? (
              <Text style={[textStyle('bodySm'), s.meta]} numberOfLines={1}>{whenLabel}</Text>
            ) : null}
          </View>
        </View>

        <Text style={[textStyle('body'), s.confirmNote]}>
          {!completed
            ? copy.body
            : showTransfer
              ? 'Your ticket is confirmed. The seller sends it next, and your payment is held until it reaches you.'
              : 'Your ticket is confirmed. Check your email for transfer instructions.'}
        </Text>
      </View>

      <View style={[s.bar, { paddingBottom: v2.space.md + insets.bottom }]}>
        <Button
          label={showTransfer ? 'View transfer' : 'Back to home'}
          onPress={() =>
            showTransfer
              ? router.replace(`/transfer/receive/${transferId}`)
              : router.replace('/(tabs)/home')
          }
          variant="primary"
          size="lg"
          block
        />
      </View>
    </View>
  );
}

// -- Helpers ----------------------------------------------------------------

function fmtWhen(date: string, time: string): string {
  const d = new Date(`${date}T${time || '00:00:00'}`);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleDateString('en-US', {
    weekday: 'short', month: 'short', day: 'numeric',
    hour: 'numeric', minute: '2-digit', hour12: true,
  }).replace(/,([^,]*)$/, ' ·$1');
}


// --- Styles ----------------------------------------------------------------

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: v2.surface.canvas },

  topBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: v2.space.sm,
    paddingBottom: v2.space.sm,
  },
  topTitle: { color: v2.text.primary },
  topSpacer: { width: 44 },

  scroll: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.md },

  orderRow: { flexDirection: 'row', gap: v2.space.md, alignItems: 'center' },
  orderText: { flex: 1, minWidth: 0, gap: 2 },
  eventName: { color: v2.text.primary },
  meta: { color: v2.text.muted },

  holdRow: { marginTop: v2.space.lg },
  hold: { color: v2.status.warning },
  holdExpired: { color: v2.status.error },

  breakdown: {
    marginTop: v2.space.xl,
    borderTopWidth: 1,
    borderTopColor: v2.border.default,
    paddingTop: v2.space.md,
    gap: v2.space.sm,
  },
  row: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline', gap: v2.space.md },
  rowLabel: { color: v2.text.muted },
  rowValue: { color: v2.text.primary, fontVariant: ['tabular-nums'] },
  hairline: { height: 1, backgroundColor: v2.border.default, marginVertical: v2.space.xs },
  totalRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline' },
  totalLabel: { color: v2.text.primary },
  totalValue: { color: v2.text.primary },

  payState: {
    marginTop: v2.space.xl,
    borderTopWidth: 1,
    borderTopColor: v2.border.default,
    paddingTop: v2.space.md,
  },
  payStateRow: { flexDirection: 'row', alignItems: 'center', gap: v2.space.sm },
  payStateText: { color: v2.text.secondary },
  payError: { color: v2.status.error },

  trust: { color: v2.text.muted, marginTop: v2.space.lg },

  bar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: v2.space.md,
    paddingHorizontal: v2.space.lg,
    paddingTop: v2.space.md,
    borderTopWidth: 1,
    borderTopColor: v2.border.strong,
    backgroundColor: v2.surface.surface,
  },
  barPrice: { flex: 1, minWidth: 0 },

  // Confirmation
  confirmWrap: { flex: 1, backgroundColor: v2.surface.canvas },
  confirmBody: { flex: 1, paddingHorizontal: v2.space.lg, gap: v2.space.md },
  confirmKicker: { color: v2.status.success },
  // Same kicker, three readings: settled / not landed yet / unfulfillable.
  confirmKickerPending: { color: v2.status.warning },
  confirmKickerFailed:  { color: v2.status.error },
  confirmTitle: { color: v2.text.primary },
  confirmCard: {
    flexDirection: 'row',
    gap: v2.space.md,
    alignItems: 'center',
    marginTop: v2.space.md,
    borderTopWidth: 1,
    borderBottomWidth: 1,
    borderColor: v2.border.default,
    paddingVertical: v2.space.md,
  },
  confirmNote: { color: v2.text.secondary, marginTop: v2.space.md },
});

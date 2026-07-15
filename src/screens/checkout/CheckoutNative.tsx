/**
 * src/screens/checkout/CheckoutScreen.native.tsx
 *
 * Full native Stripe checkout — lives outside app/ so Expo Router's
 * require.context never touches the @stripe/stripe-react-native import.
 *
 * Re-exported by app/checkout/[id].tsx via platform resolution.
 */

import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import {
  isPlatformPaySupported,
  PlatformPay,
  useStripe,
} from '@stripe/stripe-react-native';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { createPaymentIntent, confirmPaymentSuccess, isExpectedCheckoutError } from '@/src/lib/payments';
import { colors, fontSize, radius, shadow, spacing } from '@/src/theme';
import { buyerTotalCents, dollarsToCents, formatCents } from '@/src/lib/money';

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
  const [sold,            setSold]            = useState(false);
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
          console.error('PaymentSheet init error:', error.code, error.message);
          setPaymentError('Unable to set up payment. Please try again.');
          return;
        }

        setPaymentReady(true);
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : 'Failed to initialize payment.';
        if (!isExpectedCheckoutError(msg)) {
          console.error('Payment setup error:', msg);
        }
        setPaymentError(msg);
      } finally {
        setPaymentLoading(false);
      }
    }

    setupPaymentRef.current = setupPayment;
    setupPayment();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id, authLoading, listingId]);

  // -- Confirm Buy Now purchase ---------------------------------------------

  async function handleConfirmPurchase() {
    if (!paymentReady || !user) return;
    setConfirming(true);

    try {
      const { error: paymentError } = await presentPaymentSheet();

      if (paymentError) {
        if (paymentError.code === 'Canceled') {
          setConfirming(false);
          return;
        }
        Alert.alert('Payment Failed', paymentError.message);
        setConfirming(false);
        return;
      }

      if (paymentIntentId) {
        await confirmPaymentSuccess(paymentIntentId);
      }

      const { error: rpcError } = await supabase.rpc('mark_listing_sold', {
        p_listing_id: listingId,
        p_user_id: user.id,
      });

      if (rpcError) {
        Alert.alert(
          'Payment Received',
          'Your payment was processed but we had trouble updating the listing. Please contact support.',
        );
        console.error('mark_listing_sold error after payment:', rpcError.message, rpcError.code);
      }

      const { error: transferErr } = await supabase.rpc('ensure_transfer_exists', {
        p_listing_id: listingId,
      });
      if (transferErr) {
        console.warn('[checkout] ensure_transfer_exists error:', transferErr.message);
      }

      const { data: transferRow } = await supabase
        .from('transfers')
        .select('id')
        .eq('listing_id', listingId)
        .maybeSingle();
      if (transferRow?.id) {
        setPostPurchaseTransferId(transferRow.id);
      }

      confirmedRef.current = true;
      setSold(true);
    } catch (err: unknown) {
      Alert.alert(
        'Error',
        err instanceof Error ? err.message : 'Something went wrong.',
      );
    } finally {
      setConfirming(false);
    }
  }

  // -- Auction winner payment -----------------------------------------------

  async function handleAuctionPayment() {
    if (!paymentReady || !user) return;
    setConfirming(true);

    try {
      const { error: paymentError } = await presentPaymentSheet();

      if (paymentError) {
        if (paymentError.code === 'Canceled') {
          setConfirming(false);
          return;
        }
        Alert.alert('Payment Failed', paymentError.message);
        setConfirming(false);
        return;
      }

      if (paymentIntentId) {
        await confirmPaymentSuccess(paymentIntentId);
      }

      const { error: rpcError } = await supabase.rpc('complete_auction_payment', {
        p_listing_id: listingId,
        p_user_id: user.id,
      });

      if (rpcError) {
        Alert.alert(
          'Payment Received',
          'Your payment was processed but we had trouble updating the listing. Please contact support.',
        );
        console.error('complete_auction_payment error after payment:', rpcError.message, rpcError.code);
      }

      const { error: transferErr2 } = await supabase.rpc('ensure_transfer_exists', {
        p_listing_id: listingId,
      });
      if (transferErr2) {
        console.warn('[checkout] ensure_transfer_exists error:', transferErr2.message);
      }

      const { data: transferRow2 } = await supabase
        .from('transfers')
        .select('id')
        .eq('listing_id', listingId)
        .maybeSingle();
      if (transferRow2?.id) {
        setPostPurchaseTransferId(transferRow2.id);
      }

      confirmedRef.current = true;
      setSold(true);
    } catch (err: unknown) {
      Alert.alert(
        'Error',
        err instanceof Error ? err.message : 'Something went wrong.',
      );
    } finally {
      setConfirming(false);
    }
  }

  // -- Sold UI --------------------------------------------------------------

  if (sold) {
    return (
      <SafeAreaView style={s.safe}>
        <View style={s.topBar}>
          <View style={s.backBtn} />
          <Text style={s.topTitle}>Checkout</Text>
          <View style={s.backBtn} />
        </View>

        <View style={s.soldWrap}>
          <View style={s.checkCircle}>
            <Text style={s.checkMark}>{'\u2713'}</Text>
          </View>
          <Text style={s.soldTitle}>Purchase complete!</Text>
          <Text style={s.soldSub}>
            {postPurchaseTransferId
              ? 'Your tickets are confirmed. View transfer details to receive them.'
              : 'Your tickets are confirmed. Check your email for transfer instructions.'}
          </Text>
          {postPurchaseTransferId ? (
            <TouchableOpacity
              style={s.homeBtn}
              onPress={() => {
                router.replace(`/transfer/receive/${postPurchaseTransferId}`);
              }}
              activeOpacity={0.88}
            >
              <Text style={s.homeBtnText}>View Transfer</Text>
            </TouchableOpacity>
          ) : (
            <TouchableOpacity
              style={s.homeBtn}
              onPress={() => {
                router.replace('/(tabs)/home');
              }}
              activeOpacity={0.88}
            >
              <Text style={s.homeBtnText}>Back to Home</Text>
            </TouchableOpacity>
          )}
        </View>
      </SafeAreaView>
    );
  }

  // -- Normal checkout UI ---------------------------------------------------

  return (
    <SafeAreaView style={s.safe}>

      {/* Header */}
      <View style={s.topBar}>
        <Pressable
          onPress={() => router.back()}
          style={s.backBtn}
          hitSlop={8}
        >
          <Text style={s.backArrow}>{'\u2190'}</Text>
        </Pressable>
        <Text style={s.topTitle}>Checkout</Text>
        <View style={s.backBtn} />
      </View>

      <ScrollView
        contentContainerStyle={s.scrollBody}
        showsVerticalScrollIndicator={false}
      >

        {/* Confirmed banner */}
        <View style={s.successBanner}>
          <Text style={s.successIcon}>{isBuyNow ? '\uD83D\uDED2' : '\uD83C\uDF89'}</Text>
          <Text style={s.successTitle}>
            {isBuyNow ? 'Purchase Confirmed!' : 'Bid Placed!'}
          </Text>
          <Text style={s.successSub}>
            {isBuyNow
              ? "You've secured this listing. Complete payment to receive your tickets."
              : "You're in the lead. Complete payment to secure your tickets."}
          </Text>
        </View>

        {/* Reservation notice (buy_now only) */}
        {isBuyNow && (
          <View style={s.reservationNotice}>
            <Text style={s.reservationNoticeText}>
              {'\uD83D\uDD12'}  This listing is reserved for you for 10 minutes. Complete payment before time runs out.
            </Text>
          </View>
        )}

        {/* Order summary card */}
        <View style={s.card}>
          <Text style={s.cardTitle}>ORDER SUMMARY</Text>

          <View style={s.summaryRow}>
            <Text style={s.summaryLabel}>Event</Text>
            <Text style={s.summaryValue} numberOfLines={2}>{eventName}</Text>
          </View>

          <View style={s.divider} />

          <View style={s.summaryRow}>
            <Text style={s.summaryLabel}>Venue</Text>
            <Text style={s.summaryValue} numberOfLines={1}>{venue}</Text>
          </View>

          <View style={s.divider} />

          {/* Server-computed once loaded; canonical client estimate before. */}
          <View style={s.summaryRow}>
            <Text style={s.summaryLabel}>
              {isBuyNow ? 'Buy Now price' : 'Winning bid'}
            </Text>
            <Text style={s.summaryValue}>
              {formatCents(serverBreakdown ? serverBreakdown.amount : dollarsToCents(bidAmount))}
            </Text>
          </View>

          <View style={s.divider} />

          <View style={s.summaryRow}>
            <Text style={s.summaryLabel}>Service fee (10%)</Text>
            <Text style={s.summaryValue}>
              {formatCents(serverBreakdown
                ? serverBreakdown.buyerFee
                : estimatedTotalCents - dollarsToCents(bidAmount))}
            </Text>
          </View>

          <View style={s.divider} />

          <View style={s.summaryRow}>
            <Text style={[s.summaryLabel, s.totalLabel]}>Total</Text>
            <Text style={[s.summaryValue, s.totalValue]}>
              {formatCents(serverBreakdown ? serverBreakdown.total : estimatedTotalCents)}
            </Text>
          </View>
        </View>

        {/* Payment card */}
        <View style={s.card}>
          <Text style={s.cardTitle}>PAYMENT</Text>

          <View style={s.paymentPlaceholder}>
            {authLoading ? (
              <>
                <ActivityIndicator color={colors.primary} size="small" />
                <View style={{ flex: 1 }}>
                  <Text style={s.paymentName}>Authenticating...</Text>
                  <Text style={s.paymentSub}>Verifying your session</Text>
                </View>
              </>
            ) : paymentLoading ? (
              <>
                <ActivityIndicator color={colors.primary} size="small" />
                <View style={{ flex: 1 }}>
                  <Text style={s.paymentName}>Preparing secure payment...</Text>
                  <Text style={s.paymentSub}>Connecting to Stripe</Text>
                </View>
              </>
            ) : paymentReady ? (
              <>
                <Text style={s.paymentIcon}>{'\uD83D\uDCB3'}</Text>
                <View style={{ flex: 1 }}>
                  <Text style={s.paymentName}>Secure checkout</Text>
                  <Text style={s.paymentSub}>
                    {applePayAvailable ? 'Apple Pay or card' : 'Card payment'}
                  </Text>
                </View>
              </>
            ) : paymentError ? (
              <>
                <Text style={s.paymentIcon}>{'\u26A0\uFE0F'}</Text>
                <View style={{ flex: 1 }}>
                  <Text style={[s.paymentName, { color: colors.error }]}>Setup Failed</Text>
                  <Text style={s.paymentSub}>{paymentError}</Text>
                </View>
                <TouchableOpacity
                  style={s.retryBtn}
                  onPress={() => setupPaymentRef.current?.()}
                  activeOpacity={0.8}
                >
                  <Text style={s.retryBtnText}>Retry</Text>
                </TouchableOpacity>
              </>
            ) : (
              <>
                <Text style={s.paymentIcon}>{'\uD83D\uDCB3'}</Text>
                <View style={{ flex: 1 }}>
                  <Text style={s.paymentName}>Secure checkout</Text>
                  <Text style={s.paymentSub}>Initializing{'\u2026'}</Text>
                </View>
              </>
            )}
          </View>
        </View>

        <View style={{ height: 100 }} />
      </ScrollView>

      {/* Sticky CTA */}
      <View style={s.stickyBar}>
        {isBuyNow ? (
          <TouchableOpacity
            style={[
              s.payBtn,
              paymentReady && !confirming && s.payBtnActive,
              confirming && s.payBtnBusy,
            ]}
            onPress={handleConfirmPurchase}
            disabled={!paymentReady || confirming || paymentLoading || authLoading}
            activeOpacity={0.88}
          >
            {authLoading ? (
              <View style={s.payBtnRow}>
                <ActivityIndicator color={colors.textMuted} size="small" />
                <Text style={[s.payBtnText, { color: colors.textMuted }]}>Authenticating...</Text>
              </View>
            ) : paymentLoading ? (
              <View style={s.payBtnRow}>
                <ActivityIndicator color={colors.textMuted} size="small" />
                <Text style={[s.payBtnText, { color: colors.textMuted }]}>Setting up payment...</Text>
              </View>
            ) : confirming ? (
              <View style={s.payBtnRow}>
                <ActivityIndicator color={colors.text} size="small" />
                <Text style={s.payBtnText}>Processing...</Text>
              </View>
            ) : paymentReady ? (
              <Text style={s.payBtnText}>{'\uD83D\uDD12'}  Pay {'\u00B7'} {formatCents(serverBreakdown ? serverBreakdown.total : estimatedTotalCents)} total</Text>
            ) : (
              <Text style={[s.payBtnText, { color: colors.textMuted }]}>Payment unavailable</Text>
            )}
          </TouchableOpacity>
        ) : (
          <TouchableOpacity
            style={[
              s.payBtn,
              paymentReady && !confirming && s.payBtnActive,
              confirming && s.payBtnBusy,
            ]}
            onPress={handleAuctionPayment}
            disabled={!paymentReady || confirming || paymentLoading || authLoading}
            activeOpacity={0.88}
          >
            {authLoading ? (
              <View style={s.payBtnRow}>
                <ActivityIndicator color={colors.textMuted} size="small" />
                <Text style={[s.payBtnText, { color: colors.textMuted }]}>Authenticating...</Text>
              </View>
            ) : paymentLoading ? (
              <View style={s.payBtnRow}>
                <ActivityIndicator color={colors.textMuted} size="small" />
                <Text style={[s.payBtnText, { color: colors.textMuted }]}>Setting up payment...</Text>
              </View>
            ) : confirming ? (
              <View style={s.payBtnRow}>
                <ActivityIndicator color={colors.text} size="small" />
                <Text style={s.payBtnText}>Processing...</Text>
              </View>
            ) : paymentReady ? (
              <Text style={s.payBtnText}>{'\uD83D\uDD12'}  Pay {'\u00B7'} {formatCents(serverBreakdown ? serverBreakdown.total : estimatedTotalCents)} total</Text>
            ) : (
              <Text style={[s.payBtnText, { color: colors.textMuted }]}>Payment unavailable</Text>
            )}
          </TouchableOpacity>
        )}
        <Text style={s.trustLine}>
          Payments are secure and encrypted via Stripe
        </Text>
      </View>

      {/* Processing overlay */}
      {confirming && (
        <View style={s.overlay}>
          <ActivityIndicator color={colors.primary} size="large" />
          <Text style={s.overlayText}>Processing payment{'\u2026'}</Text>
        </View>
      )}

    </SafeAreaView>
  );
}

// --- Styles ----------------------------------------------------------------

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.bg },

  topBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  backBtn:   { width: 44, height: 44, alignItems: 'flex-start', justifyContent: 'center' },
  backArrow: { color: colors.text, fontSize: fontSize.xl, fontWeight: '600' },
  topTitle:  { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },

  soldWrap: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: spacing.xl,
    gap: spacing.md,
  },
  checkCircle: {
    width: 72, height: 72, borderRadius: 36,
    backgroundColor: colors.success,
    alignItems: 'center', justifyContent: 'center',
    marginBottom: spacing.sm,
  },
  checkMark: {
    fontSize: 36, color: '#fff', fontWeight: '900', lineHeight: 40,
  },
  soldTitle: {
    fontSize: fontSize.xl,
    fontWeight: '900',
    color: colors.text,
    textAlign: 'center',
  },
  soldSub: {
    fontSize: fontSize.sm,
    color: colors.textMuted,
    textAlign: 'center',
    paddingHorizontal: spacing.lg,
  },
  homeBtn: {
    marginTop: spacing.md,
    backgroundColor: colors.primary,
    borderRadius: radius.md,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.xl,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.4,
    shadowRadius: 10,
    elevation: 6,
  },
  homeBtnText: { color: colors.text, fontWeight: '800', fontSize: fontSize.md },

  scrollBody: {
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.lg,
  },

  successBanner: {
    alignItems: 'center',
    paddingVertical: spacing.xl,
    marginBottom: spacing.md,
  },
  successIcon:  { fontSize: 48, marginBottom: spacing.sm },
  successTitle: {
    fontSize: fontSize.xl,
    fontWeight: '900',
    color: colors.text,
    marginBottom: spacing.xs,
  },
  successSub: {
    fontSize: fontSize.sm,
    color: colors.textMuted,
    textAlign: 'center',
    paddingHorizontal: spacing.lg,
  },

  reservationNotice: {
    backgroundColor: colors.bgInput,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.borderInput,
    padding: spacing.md,
    marginBottom: spacing.md,
  },
  reservationNoticeText: {
    fontSize: fontSize.xs,
    color: colors.textMuted,
    textAlign: 'center',
    lineHeight: 18,
  },

  card: {
    backgroundColor: colors.bgCard,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.border,
    padding: spacing.lg,
    marginBottom: spacing.md,
    ...shadow.card,
  },
  cardTitle: {
    fontSize: fontSize.xs,
    fontWeight: '700',
    color: colors.textDim,
    letterSpacing: 1.4,
    textTransform: 'uppercase',
    marginBottom: spacing.md,
  },

  summaryRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    paddingVertical: spacing.sm,
    gap: spacing.md,
  },
  summaryLabel: {
    fontSize: fontSize.sm,
    color: colors.textMuted,
    flexShrink: 0,
  },
  summaryValue: {
    fontSize: fontSize.sm,
    color: colors.text,
    fontWeight: '600',
    textAlign: 'right',
    flex: 1,
  },
  totalLabel: {
    color: colors.text,
    fontWeight: '700',
    fontSize: fontSize.md,
  },
  totalValue: {
    color: colors.primary,
    fontWeight: '800',
    fontSize: fontSize.md,
  },
  divider: {
    height: 1,
    backgroundColor: colors.border,
  },

  paymentPlaceholder: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
  },
  paymentIcon: { fontSize: 28 },
  paymentName: {
    color: colors.text,
    fontSize: fontSize.md,
    fontWeight: '700',
  },
  paymentSub: {
    color: colors.textMuted,
    fontSize: fontSize.xs,
    marginTop: 2,
  },

  stickyBar: {
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.md,
    paddingBottom: spacing.lg,
    borderTopWidth: 1,
    borderTopColor: colors.border,
    backgroundColor: colors.bg,
    gap: spacing.sm,
    alignItems: 'center',
  },
  payBtn: {
    width: '100%',
    backgroundColor: colors.borderInput,
    borderRadius: radius.md,
    paddingVertical: spacing.md + 2,
    alignItems: 'center',
    opacity: 0.6,
  },
  payBtnActive: {
    backgroundColor: colors.primary,
    opacity: 1,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.45,
    shadowRadius: 12,
    elevation: 8,
  },
  payBtnBusy: { opacity: 0.65 },
  payBtnRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  payBtnText: {
    color: colors.text,
    fontSize: fontSize.md,
    fontWeight: '800',
    letterSpacing: 0.5,
  },
  trustLine: {
    fontSize: fontSize.xs,
    color: colors.textDim,
    textAlign: 'center',
  },

  retryBtn: {
    backgroundColor: colors.primary,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.md,
    paddingVertical: 6,
  },
  retryBtnText: {
    color: colors.text,
    fontSize: fontSize.xs,
    fontWeight: '700',
  },

  overlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0,0,0,0.7)',
    justifyContent: 'center',
    alignItems: 'center',
    gap: spacing.md,
    zIndex: 10,
  },
  overlayText: {
    color: colors.text,
    fontSize: fontSize.md,
    fontWeight: '700',
  },
});

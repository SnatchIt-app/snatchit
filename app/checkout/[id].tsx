/**
 * app/checkout/[id].tsx — Checkout Screen
 *
 * Receives params from ListingDetailScreen (Buy Now) or ConfirmBidScreen (bid):
 *   id         — listing uuid
 *   mode       — "bid" | "buy_now"  (default: "bid")
 *   bidAmount  — bid or buy-now price (dollars, string)
 *   total      — bidAmount + service fee (dollars, string)
 *   eventName  — display only
 *   venue      — display only
 *
 * Payment flow (both modes):
 *   1. On mount: createPaymentIntent → edge function → Stripe PaymentIntent
 *   2. initPaymentSheet with clientSecret → setPaymentReady(true)
 *   3. User taps Pay → presentPaymentSheet → native Stripe UI
 *   4. Payment succeeds → mark listing sold via RPC
 *
 * Buy Now:  mark_listing_sold (requires status='reserved')
 * Auction:  complete_auction_payment (requires auction_status='ended' + winner)
 *
 * Cleanup (Buy Now only):
 *   On back / unmount without confirming → release_reservation RPC
 */

import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useStripe } from '@stripe/stripe-react-native';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { createPaymentIntent, confirmPaymentSuccess } from '@/src/lib/payments';
import { colors, fontSize, radius, shadow, spacing } from '@/src/theme';

// ─── Helper ───────────────────────────────────────────────────────────────────

function fmt$(n: number): string {
  return n % 1 === 0
    ? `$${n.toLocaleString('en-US')}`
    : `$${n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

// ─── Screen ───────────────────────────────────────────────────────────────────

export default function CheckoutScreen() {
  const { user, loading: authLoading } = useAuth();
  const { initPaymentSheet, presentPaymentSheet } = useStripe();

  const params = useLocalSearchParams<{
    id:        string;
    mode:      string;   // "bid" | "buy_now"
    bidAmount: string;
    total:     string;
    eventName: string;
    venue:     string;
  }>();

  const listingId = params.id ?? '';
  const isBuyNow  = params.mode === 'buy_now';
  const bidAmount = parseInt(params.bidAmount ?? '0', 10);
  const total     = parseInt(params.total     ?? '0', 10);
  const eventName = params.eventName ?? '—';
  const venue     = params.venue     ?? '—';

  // ── State ────────────────────────────────────────────────────────────────────

  const [confirming,      setConfirming]      = useState(false);
  const [sold,            setSold]            = useState(false);   // true after mark_listing_sold succeeds
  const [paymentReady,    setPaymentReady]    = useState(false);   // true after PaymentSheet init
  const [paymentLoading,  setPaymentLoading]  = useState(false);   // true while creating payment intent
  const [paymentIntentId, setPaymentIntentId] = useState<string | null>(null); // stored for confirmation
  const [paymentError,    setPaymentError]    = useState<string | null>(null); // setup error message

  // Track whether we navigated away via "Confirm" so the cleanup effect
  // knows NOT to call release_reservation (the listing is now sold).
  const confirmedRef = useRef(false);
  // Ref to retry payment setup
  const setupPaymentRef = useRef<(() => void) | null>(null);

  // ── Release reservation on unmount if not confirmed ──────────────────────────
  // This fires when the user presses the hardware/gesture back button or the
  // header back arrow, effectively cancelling the reservation.
  useEffect(() => {
    if (!isBuyNow || !user) return;

    return () => {
      if (!confirmedRef.current) {
        // Fire-and-forget — we don't need to await this on unmount.
        supabase.rpc('release_reservation', {
          p_listing_id: listingId,
          p_user_id:    user.id,
        }).then(({ error }) => {
          if (error) console.warn('[checkout] release_reservation error:', error.message);
          else       console.log('[checkout] reservation released on exit');
        });
      }
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isBuyNow, listingId, user?.id]);

  // ── Initialize Stripe PaymentSheet on mount (both modes) ────────────────────

  useEffect(() => {
    if (authLoading) return;   // Wait for auth to hydrate
    if (!user?.id) return;     // No user yet

    async function setupPayment() {
      try {
        setPaymentLoading(true);
        setPaymentError(null);

        // Call edge function to create payment intent
        const result = await createPaymentIntent({
          listingId: listingId,
          buyerId: user!.id,
          mode: isBuyNow ? 'buy_now' : 'auction',
        });

        // Store the payment intent ID for post-payment confirmation
        setPaymentIntentId(result.paymentIntentId);

        // Initialize the Stripe PaymentSheet
        const { error } = await initPaymentSheet({
          paymentIntentClientSecret: result.clientSecret,
          merchantDisplayName: 'SnatchIt',
          returnURL: 'snatchit://checkout',
          allowsDelayedPaymentMethods: false,
          defaultBillingDetails: {
            email: user!.email,
          },
        });

        if (error) {
          console.error('PaymentSheet init error:', error.code, error.message);
          setPaymentError('Unable to set up payment. Please try again.');
          return;
        }

        setPaymentReady(true);
      } catch (err: unknown) {
        console.error('Payment setup error:', err instanceof Error ? err.message : 'unknown');
        setPaymentError(
          err instanceof Error ? err.message : 'Failed to initialize payment.',
        );
      } finally {
        setPaymentLoading(false);
      }
    }

    setupPaymentRef.current = setupPayment;
    setupPayment();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id, authLoading, listingId]);

  // ── Confirm Buy Now purchase (Stripe PaymentSheet → mark_listing_sold) ─────

  async function handleConfirmPurchase() {
    if (!paymentReady || !user) return;
    setConfirming(true);

    try {
      // Step 1: Present the Stripe PaymentSheet
      const { error: paymentError } = await presentPaymentSheet();

      if (paymentError) {
        if (paymentError.code === 'Canceled') {
          // User dismissed the sheet — not an error
          setConfirming(false);
          return;
        }
        Alert.alert('Payment Failed', paymentError.message);
        setConfirming(false);
        return;
      }

      // Step 2: Record the successful payment in our DB (best-effort)
      if (paymentIntentId) {
        await confirmPaymentSuccess(paymentIntentId);
      }

      // Step 3: Mark listing as sold
      const { error: rpcError } = await supabase.rpc('mark_listing_sold', {
        p_listing_id: listingId,
        p_user_id: user.id,
      });

      if (rpcError) {
        // Payment went through but listing update failed
        // This is rare but needs handling
        Alert.alert(
          'Payment Received',
          'Your payment was processed but we had trouble updating the listing. Please contact support.',
        );
        console.error('mark_listing_sold error after payment:', rpcError.message, rpcError.code);
      }

      // TODO: Send push notification to seller via Edge Function
      // The seller's push token is in push_tokens table
      // This should be triggered server-side after payment confirmation

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

  // ── Auction winner payment (Stripe PaymentSheet → complete_auction_payment) ──

  async function handleAuctionPayment() {
    if (!paymentReady || !user) return;
    setConfirming(true);

    try {
      // Step 1: Present the Stripe PaymentSheet
      const { error: paymentError } = await presentPaymentSheet();

      if (paymentError) {
        if (paymentError.code === 'Canceled') {
          // User dismissed the sheet — not an error
          setConfirming(false);
          return;
        }
        Alert.alert('Payment Failed', paymentError.message);
        setConfirming(false);
        return;
      }

      // Step 2: Record the successful payment in our DB (best-effort)
      if (paymentIntentId) {
        await confirmPaymentSuccess(paymentIntentId);
      }

      // Step 3: Mark listing as sold via auction-specific RPC
      // complete_auction_payment checks auction_status='ended' + winner_user_id match
      const { error: rpcError } = await supabase.rpc('complete_auction_payment', {
        p_listing_id: listingId,
        p_user_id: user.id,
      });

      if (rpcError) {
        // Payment went through but listing update failed
        Alert.alert(
          'Payment Received',
          'Your payment was processed but we had trouble updating the listing. Please contact support.',
        );
        console.error('complete_auction_payment error after payment:', rpcError.message, rpcError.code);
      }

      // TODO: Send push notification to seller via Edge Function
      // The seller's push token is in push_tokens table
      // This should be triggered server-side after payment confirmation

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

  // ── Sold UI (shown after successful payment) ──────────────────────────────────

  if (sold) {
    return (
      <SafeAreaView style={s.safe}>
        <View style={s.topBar}>
          {/* No back button after purchase — use Go Home instead */}
          <View style={s.backBtn} />
          <Text style={s.topTitle}>Checkout</Text>
          <View style={s.backBtn} />
        </View>

        <View style={s.soldWrap}>
          <View style={s.checkCircle}>
            <Text style={s.checkMark}>✓</Text>
          </View>
          <Text style={s.soldTitle}>Purchase complete!</Text>
          <Text style={s.soldSub}>
            Your tickets are confirmed. Check your email for transfer instructions.
          </Text>
          <TouchableOpacity
            style={s.homeBtn}
            onPress={() => {
              // Replace so the user can't navigate back to checkout
              router.replace('/(tabs)/home');
            }}
            activeOpacity={0.88}
          >
            <Text style={s.homeBtnText}>Back to Home</Text>
          </TouchableOpacity>
        </View>
      </SafeAreaView>
    );
  }

  // ── Normal checkout UI ────────────────────────────────────────────────────────

  return (
    <SafeAreaView style={s.safe}>

      {/* ── Header ──────────────────────────────────────────────────────────── */}
      <View style={s.topBar}>
        <Pressable
          onPress={() => router.back()}
          style={s.backBtn}
          hitSlop={8}
        >
          <Text style={s.backArrow}>←</Text>
        </Pressable>
        <Text style={s.topTitle}>Checkout</Text>
        {/* Spacer to keep title centred */}
        <View style={s.backBtn} />
      </View>

      <ScrollView
        contentContainerStyle={s.scrollBody}
        showsVerticalScrollIndicator={false}
      >

        {/* ── Confirmed banner ─────────────────────────────────────────────── */}
        <View style={s.successBanner}>
          <Text style={s.successIcon}>{isBuyNow ? '🛒' : '🎉'}</Text>
          <Text style={s.successTitle}>
            {isBuyNow ? 'Purchase Confirmed!' : 'Bid Placed!'}
          </Text>
          <Text style={s.successSub}>
            {isBuyNow
              ? "You've secured this listing. Complete payment to receive your tickets."
              : "You're in the lead. Complete payment to secure your tickets."}
          </Text>
        </View>

        {/* ── Reservation notice (buy_now only) ────────────────────────────── */}
        {isBuyNow && (
          <View style={s.reservationNotice}>
            <Text style={s.reservationNoticeText}>
              🔒  This listing is reserved for you for 10 minutes. Complete payment before time runs out.
            </Text>
          </View>
        )}

        {/* ── Order summary card ───────────────────────────────────────────── */}
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

          <View style={s.summaryRow}>
            <Text style={s.summaryLabel}>
              {isBuyNow ? 'Buy Now price' : 'Winning bid'}
            </Text>
            <Text style={s.summaryValue}>{fmt$(bidAmount)}</Text>
          </View>

          <View style={s.divider} />

          <View style={s.summaryRow}>
            <Text style={s.summaryLabel}>Service fee (5%)</Text>
            <Text style={s.summaryValue}>{fmt$(total - bidAmount)}</Text>
          </View>

          <View style={s.divider} />

          <View style={s.summaryRow}>
            <Text style={[s.summaryLabel, s.totalLabel]}>Total charged</Text>
            <Text style={[s.summaryValue, s.totalValue]}>{fmt$(total)}</Text>
          </View>
        </View>

        {/* ── Payment card ─────────────────────────────────────────────────── */}
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
                <Text style={s.paymentIcon}>💳</Text>
                <View style={{ flex: 1 }}>
                  <Text style={s.paymentName}>Stripe Checkout</Text>
                  <Text style={s.paymentSub}>Tap Pay to enter card details</Text>
                </View>
              </>
            ) : paymentError ? (
              <>
                <Text style={s.paymentIcon}>⚠️</Text>
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
                <Text style={s.paymentIcon}>💳</Text>
                <View style={{ flex: 1 }}>
                  <Text style={s.paymentName}>Stripe Checkout</Text>
                  <Text style={s.paymentSub}>Initializing…</Text>
                </View>
              </>
            )}
          </View>
        </View>

        {/* Bottom padding so CTA doesn't overlap content */}
        <View style={{ height: 100 }} />
      </ScrollView>

      {/* ── Sticky CTA ──────────────────────────────────────────────────────── */}
      <View style={s.stickyBar}>
        {isBuyNow ? (
          // Buy Now: Stripe PaymentSheet flow
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
              <Text style={s.payBtnText}>🔒  Pay · {fmt$(total)}</Text>
            ) : (
              <Text style={[s.payBtnText, { color: colors.textMuted }]}>Payment unavailable</Text>
            )}
          </TouchableOpacity>
        ) : (
          // Auction winner: Stripe PaymentSheet flow
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
              <Text style={s.payBtnText}>🔒  Pay · {fmt$(total)}</Text>
            ) : (
              <Text style={[s.payBtnText, { color: colors.textMuted }]}>Payment unavailable</Text>
            )}
          </TouchableOpacity>
        )}
        <Text style={s.trustLine}>
          Payments are secure and encrypted via Stripe
        </Text>
      </View>

      {/* ── Processing overlay ───────────────────────────────────────────── */}
      {confirming && (
        <View style={s.overlay}>
          <ActivityIndicator color={colors.primary} size="large" />
          <Text style={s.overlayText}>Processing payment…</Text>
        </View>
      )}

    </SafeAreaView>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.bg },

  // ── Top bar ────────────────────────────────────────────────────────────────
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

  // ── Sold full-screen state ────────────────────────────────────────────────
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

  // ── Scroll body ───────────────────────────────────────────────────────────
  scrollBody: {
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.lg,
  },

  // ── Success banner ────────────────────────────────────────────────────────
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

  // ── Reservation notice (buy_now) ──────────────────────────────────────────
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

  // ── Generic card ─────────────────────────────────────────────────────────
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

  // ── Order summary rows ────────────────────────────────────────────────────
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

  // ── Payment placeholder ────────────────────────────────────────────────────
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

  // ── Sticky CTA bar ────────────────────────────────────────────────────────
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
    backgroundColor: colors.borderInput,  // muted — disabled state
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

  // ── Retry button (inside payment card) ──────────────────────────────
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

  // ── Processing overlay ──────────────────────────────────────────────
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

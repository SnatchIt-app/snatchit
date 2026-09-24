/**
 * src/screens/checkout/CheckoutView.tsx — checkout's presentation, and nothing else.
 *
 * WHY IT IS A FILE OF ITS OWN (owner 2026-09-24: "complete checkout presentation through a
 * rendering path that cannot mount payment setup"). The rest of the V3 work is compared against the
 * approved boards as the ACTUAL APP RENDERS IT. Checkout could not join that: the screen lives in
 * `CheckoutNative.tsx`, which imports `@stripe/stripe-react-native` at module scope, and that module
 * reaches `TurboModuleRegistry`. The platform split (`CheckoutEntry.tsx` vs `.native.tsx`) exists
 * precisely to keep it out of the web bundle, so no harness could render that file without breaking
 * the boundary that protects the web build — and mounting the real screen signed in would run the
 * setup effect, which creates or reuses a PaymentIntent.
 *
 * Splitting the presentation out is what makes the owner's instruction satisfiable rather than a
 * convenience: THIS module holds the markup and the styles, imports no native module, no supabase
 * client and none of the payment functions, and takes every value as a prop. A harness that mounts
 * it cannot create an intent — not because it declines to, but because nothing reachable from here
 * can. `tests/v3-checkout-view.test.ts` pins that as an import-graph property.
 *
 * WHAT STAYED IN CheckoutNative. Every effect, every read, every decision: the setup sequence
 * (settled-first, then hold, then intent), the PaymentSheet, revalidation, finalisation, the single
 * flight latch, the countdown ticker, and `payControl`'s inputs. This file receives the resolved
 * outcome of all of it and paints it. It performs NO money arithmetic and formats no amount: every
 * figure arrives preformatted from the caller, which took it from the server's breakdown.
 */

import { router } from 'expo-router';
import { useEffect, useMemo, type ReactNode } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { OrderIdentity } from '@/src/components/checkout/OrderIdentity';
import { Button, IconButton, Spinner } from '@/src/components/ui';
import { hapticSuccess } from '@/src/lib/feedback/haptics';
import { useTopInset } from '@/src/lib/nav/navInsets';
// TYPE ONLY, and deliberately: a value import from the payment module would put `src/lib/payments`
// — and through it the supabase client — inside this file's runtime import graph, which is exactly
// the property `tests/v3-checkout-view.test.ts` exists to guarantee. A type is erased at build, so
// nothing from the payment stack is reachable from here. The settlement WORDS arrive as a prop, from
// the same SETTLEMENT_COPY entry the alert uses, so the screen and the alert still cannot diverge.
import type { SettlementOutcome } from '@/src/lib/payments';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

/** What the buyer is paying for — the same block on all three faces. */
export interface CheckoutIdentity {
  cover: string | null;
  eventName: string;
  venue: string;
  eventDate: string | null;
  eventTime: string | null;
  quantity: number | null;
  ticketType: string | null;
}

/** A title/body state the screen shows instead of a payment method line. */
export interface CheckoutNotice {
  title: string;
  body: string;
  /** Rendered under the body — the one state that offers its own action. */
  action?: { label: string; onPress: () => void; loading?: boolean };
}

export interface CheckoutViewProps {
  identity: CheckoutIdentity;
  isBuyNow: boolean;

  /** ms left on the Buy Now hold, or null when there is no hold to speak of. */
  reservationMsLeft: number | null;
  /** The formatted countdown, from the caller's own formatter. */
  countdown: string | null;
  /** "until 7:34 pm", when the server gave a hold end. */
  holdUntil: string | null;

  /** Server figures, preformatted. Absent until create-payment-intent has answered. */
  breakdown: { item: string; amount: string; fee: string; total: string } | null;
  /** True while setup is actually running, which is the only time "Preparing your total" is true. */
  preparing: boolean;

  /** Exactly one of these paints in the payment-method slot, in this order. */
  paymentMethodLine: string | null;
  notice: CheckoutNotice | null;
  /** A setup failure the pay control already offers to retry. */
  errorLine: string | null;

  /** The escrow reassurance, when the reads behind it succeeded. */
  escrowNote: string | null;

  /** The pay control, resolved by `payControl` in the caller. */
  pay: { label: string; loading: boolean; disabled: boolean };
  onPay: (() => void) | undefined;
  /** When a new total awaits acceptance this replaces the pay control. */
  acceptTotal: { label: string; onPress: () => void } | null;
  onBack: () => void;
}

/** The screen title, in the V3 voice the other headers use. */
export const CHECKOUT_TITLE = 'Checkout';
export const PREPARING_TOTAL = 'Preparing your total';
export const TOTAL_LABEL = 'Total';

export default function CheckoutView({
  identity, isBuyNow, reservationMsLeft, countdown, holdUntil,
  breakdown, preparing, paymentMethodLine, notice, errorLine, escrowNote,
  pay, onPay, acceptTotal, onBack,
}: CheckoutViewProps) {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const insets = useSafeAreaInsets();
  // F-SELL-2: the badge-aware top inset (status bar + the SANDBOX badge on sandbox builds).
  const topPad = useTopInset();

  return (
    <View style={s.safe}>
      {/* V3 header, as the order and send screens draw it: the title in the screenTitle voice,
          the back control a chip disc, and a spacer keeping the title optically centred. */}
      <View style={[s.topBar, { paddingTop: topPad + v2.space.sm }]}>
        <IconButton glyph="back" chip accessibilityLabel="Go back" onPress={onBack} />
        <Text style={[textStyle('screenTitle'), s.topTitle]} accessibilityRole="header">{CHECKOUT_TITLE}</Text>
        <View style={s.topSpacer} />
      </View>

      <ScrollView contentContainerStyle={s.scroll} showsVerticalScrollIndicator={false}>
        <OrderIdentity
          cover={identity.cover}
          name={identity.eventName}
          venue={identity.venue}
          eventDate={identity.eventDate}
          eventTime={identity.eventTime}
          quantity={identity.quantity}
          ticketType={identity.ticketType}
        />

        {/* Reservation countdown (Buy Now). Tabular digits keep the m:ss from shifting width. */}
        {reservationMsLeft != null ? (
          <View style={s.holdRow}>
            <Text
              style={[textStyle('label'), reservationMsLeft === 0 ? s.holdExpired : s.hold]}
              accessibilityLiveRegion="none"
            >
              {reservationMsLeft === 0
                ? 'Checking your hold'
                : `Held for you · ${countdown}${holdUntil ? ` · until ${holdUntil}` : ''}`}
            </Text>
          </View>
        ) : null}

        {/* The one screen where itemising is correct, and SERVER FIGURES ONLY (A's ruling Q1–Q3,
            2026-09-24). The caller supplies the rows only once create-payment-intent has answered
            and no price change is pending, so the word "Total" never sits over a client estimate. */}
        {breakdown ? (
          <View style={s.breakdown}>
            {/* De-dup: the identity line above owns the count; this row is the money item. */}
            <Row label={breakdown.item} value={breakdown.amount} s={s} />
            <Row label="Service fee" value={breakdown.fee} s={s} />
            <View style={s.hairline} />
            <View style={s.totalRow}>
              <Text style={[textStyle('label'), s.totalLabel]}>{TOTAL_LABEL}</Text>
              <Text style={[textStyle('price'), s.totalValue]} numberOfLines={1}>{breakdown.total}</Text>
            </View>
          </View>
        ) : preparing ? (
          <View style={s.breakdown}>
            <Text style={[textStyle('body'), s.payStateText]}>{PREPARING_TOTAL}</Text>
          </View>
        ) : null}

        {/* The payment-method slot: a spinner while setup runs, the method line when ready, or the
            one state that replaced them. A state with a title reads as a QUOTE — the V3 StateBlock
            treatment the transfer screens use — so a buyer meets the same shape for the same job. */}
        <View style={s.payState}>
          {preparing ? (
            <View style={s.payStateRow}>
              <Spinner label="Preparing secure payment" />
              <Text style={[textStyle('body'), s.payStateText]}>Preparing secure payment</Text>
            </View>
          ) : paymentMethodLine ? (
            <View style={s.payStateRow}>
              <Text style={[textStyle('body'), s.payStateText]}>{paymentMethodLine}</Text>
            </View>
          ) : notice ? (
            <NoticeBlock notice={notice} s={s} palette={palette} />
          ) : errorLine ? (
            <View>
              <Text style={[textStyle('body'), s.payError]}>{errorLine}</Text>
            </View>
          ) : (
            <View style={s.payStateRow}>
              <Spinner label="Initializing" />
              <Text style={[textStyle('body'), s.payStateText]}>Initializing</Text>
            </View>
          )}
        </View>

        {/*
            THE STATUS IS NOT THE BUTTON'S JOB (B's checkout review at d374bd3f, via E). A disabled
            control drops to 40% opacity, so a state whose only words were the pay control's label —
            "Checking your payment", "Confirming payment", "Finalizing your order" — put the news in
            the faintest thing on the screen, worst in Light. The control keeps its label and stays
            disabled; the same words also appear here at full strength.

            AND ONLY ONCE (E's follow-up). The row is suppressed when the slot above it already
            states the status: `preparing` has its own spinner row, and a titled notice states its
            own state and carries its own action — in `unconfirmed` the status was appearing three
            times over.
        */}
        {!preparing && !notice && pay.loading ? (
          <View style={s.payStateRow} accessibilityLiveRegion="polite">
            {/* Decorative: the Text beside it says the same words, and a progressbar carrying the
                same label would make a screen reader read the status twice. */}
            <Spinner label={pay.label} decorative />
            <Text style={[textStyle('body'), s.payStatus]}>{pay.label}</Text>
          </View>
        ) : null}

        {escrowNote ? <Text style={[textStyle('bodySm'), s.trust]}>{escrowNote}</Text> : null}

        <View style={{ height: 120 }} />
      </ScrollView>

      {/* Sticky pay bar. No nearby Total (owner + A's N2, 2026-09-24): before the intent returns the
          figure is the client estimate, and once it returns the control itself reads "Pay $132.00".
          V3 sizing: the primary action is the 52pt pill the boards draw, full width. */}
      <View style={[s.bar, { paddingBottom: v2.space.md + insets.bottom }]}>
        {acceptTotal ? (
          <Button label={acceptTotal.label} onPress={acceptTotal.onPress} variant="primary" size="lg" block />
        ) : (
          <Button
            label={pay.label}
            // The pending states payControl already names ("Processing", "Checking your payment",
            // "Checking your hold") stay visible beside the spinner instead of hidden under it.
            pendingLabel={pay.loading ? pay.label : undefined}
            onPress={onPay}
            variant="primary"
            size="lg"
            block
            disabled={pay.disabled}
            loading={pay.loading}
          />
        )}
      </View>
    </View>
  );
}

/**
 * A checkout state, in the same quote treatment the transfer screens use: a filled rounded panel
 * with a 3pt left accent. Warning ink, because every state that reaches here is something the buyer
 * has to read before paying — a lost hold, a changed total, an unconfirmed payment.
 */
function NoticeBlock({ notice, s, palette }: { notice: CheckoutNotice; s: CheckoutStyles; palette: Palette }) {
  return (
    <View style={[s.notice, { borderLeftColor: palette.status.warning }]} accessibilityLiveRegion="polite">
      <Text style={[textStyle('title'), s.noticeTitle]}>{notice.title}</Text>
      <Text style={[textStyle('body'), s.payStateText]}>{notice.body}</Text>
      {notice.action ? (
        <View style={s.noticeAction}>
          <Button
            label={notice.action.label}
            variant="secondary"
            size="md"
            onPress={notice.action.onPress}
            loading={notice.action.loading}
            disabled={notice.action.loading}
          />
        </View>
      ) : null}
    </View>
  );
}

// A-03: a refund is its own screen. It says only what the recorded amounts establish (owner,
// 2026-09-18): never that the purchase succeeded or that none was made, never processing,
// cancellation, bank timing or the order's status. The only control is "Back to home".
export function RefundView({
  view, identity,
}: {
  /** Resolved by `refundViewModel` in the caller — this file decides no refund wording. */
  view: { kicker: string; title: string; body: string; cta: { label: string; href: string } };
  identity: CheckoutIdentity;
}) {
  return (
    <TerminalFace
      kicker={view.kicker}
      kickerTone="pending"
      title={view.title}
      body={view.body}
      identity={identity}
      cta={{ label: view.cta.label, onPress: () => router.replace(view.cta.href as never) }}
    />
  );
}

// One celebration per purchase for the life of the process: a settled checkout that remounts — a
// 3-D Secure return landing back on it — must not buzz a second time. A component ref would not
// survive the remount; this latch does.
const celebratedPurchases = new Set<string>();

/**
 * The post-charge screen, in all three of its faces. `completed` is the only one allowed to claim
 * the purchase is done; `pending` and `failed` take their words from SETTLEMENT_COPY so this screen
 * and the alert cannot diverge.
 */
export function ConfirmationView({
  outcome, copy, identity, isBuyNow, transferId, purchaseKey,
}: {
  outcome: SettlementOutcome;
  /** `SETTLEMENT_COPY[outcome]`, passed in by the screen that also raises the alert. */
  copy: { title: string; body: string };
  identity: CheckoutIdentity;
  isBuyNow: boolean;
  transferId: string | null;
  /** Identifies the purchase (the listing) so the success haptic fires once. */
  purchaseKey: string;
}) {
  const completed = outcome === 'completed';
  // The one distinctive haptic (CFT-202), only for the face that is allowed to claim the purchase is
  // done, and only once per purchase; its visible equivalent is the kicker below.
  useEffect(() => {
    if (!completed || celebratedPurchases.has(purchaseKey)) return;
    celebratedPurchases.add(purchaseKey);
    hapticSuccess();
  }, [completed, purchaseKey]);
  // Only a recorded sale has a transfer to hand off.
  const showTransfer = completed && !!transferId;
  return (
    <TerminalFace
      kicker={completed
        ? (isBuyNow ? 'Purchase complete' : 'Payment complete')
        : outcome === 'pending' ? 'Finalizing your order' : 'Needs attention'}
      kickerTone={completed ? 'success' : outcome === 'pending' ? 'pending' : 'failed'}
      title={completed ? "You're in." : copy.title}
      body={!completed
        ? copy.body
        : showTransfer
          // A's ruling §2f (2026-09-24): the old clause — "your payment is held until it reaches you" —
          // is withdrawn. Release never depends on delivery, which the system cannot observe; and
          // "held" reads as a card authorisation, while the card was charged at checkout. What is
          // true, and more useful to a buyer, is the recourse: a report freezes the seller's payout.
          ? "Your order is confirmed. The seller sends the tickets next. If they don't arrive, report it from your order; a report freezes the seller's payout."
          : 'Your ticket is confirmed. Check your email for transfer instructions.'}
      identity={identity}
      cta={{
        label: showTransfer ? 'View transfer' : 'Back to home',
        onPress: () => (showTransfer
          ? router.replace(`/transfer/receive/${transferId}`)
          : router.replace('/(tabs)/home')),
      }}
    />
  );
}

/** The shape both terminal faces share: kicker, title, the identity block, a sentence, one action. */
function TerminalFace({
  kicker, kickerTone, title, body, identity, cta,
}: {
  kicker: string;
  kickerTone: 'success' | 'pending' | 'failed';
  title: string;
  body: string;
  identity: CheckoutIdentity;
  cta: { label: string; onPress: () => void };
}) {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const insets = useSafeAreaInsets();
  const topPad = useTopInset();
  return (
    <View style={s.confirmWrap}>
      <View style={[s.confirmBody, { paddingTop: topPad + v2.space.xxl }]}>
        <Text
          style={[
            textStyle('micro'),
            s.confirmKicker,
            kickerTone === 'pending' && s.confirmKickerPending,
            kickerTone === 'failed' && s.confirmKickerFailed,
          ]}
        >
          {kicker}
        </Text>
        <Text style={[textStyle('displayLg'), s.confirmTitle]} accessibilityRole="header">{title}</Text>
        <View style={s.confirmCard}>
          <OrderIdentity
            cover={identity.cover}
            name={identity.eventName}
            venue={identity.venue}
            eventDate={identity.eventDate}
            eventTime={identity.eventTime}
            quantity={identity.quantity}
            ticketType={identity.ticketType}
          />
        </View>
        <Text style={[textStyle('body'), s.confirmNote]}>{body}</Text>
      </View>
      <View style={[s.bar, { paddingBottom: v2.space.md + insets.bottom }]}>
        <Button label={cta.label} onPress={cta.onPress} variant="primary" size="lg" block />
      </View>
    </View>
  );
}

/** The screen's shell, so a terminal face fills the canvas the same way the main view does. */
export function CheckoutShell({ children }: { children: ReactNode }) {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  return <View style={s.safe}>{children}</View>;
}

function Row({ label, value, s }: { label: string; value: string; s: CheckoutStyles }) {
  return (
    <View style={s.row} accessible accessibilityLabel={`${label}: ${value}`}>
      <Text style={[textStyle('body'), s.rowLabel]}>{label}</Text>
      <Text style={[textStyle('body'), s.rowValue]} numberOfLines={1}>{value}</Text>
    </View>
  );
}

// --- Styles ----------------------------------------------------------------

type CheckoutStyles = ReturnType<typeof makeStyles>;

function makeStyles(p: Palette) {
  return StyleSheet.create({
  safe: { flex: 1, backgroundColor: p.surface.canvas },

  topBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: v2.space.sm,
    paddingBottom: v2.space.sm,
  },
  topTitle: { color: p.text.primary },
  topSpacer: { width: 44 },

  scroll: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.md },

  holdRow: { marginTop: v2.space.lg },
  // Tabular digits: the m:ss countdown must not shift width as it ticks (CFT-207).
  hold: { color: p.status.warning, fontVariant: ['tabular-nums'] },
  holdExpired: { color: p.status.error },

  breakdown: {
    marginTop: v2.space.xl,
    borderTopWidth: 1,
    borderTopColor: p.border.default,
    paddingTop: v2.space.md,
    gap: v2.space.sm,
  },
  row: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline', gap: v2.space.md },
  rowLabel: { color: p.text.muted },
  rowValue: { color: p.text.primary, fontVariant: ['tabular-nums'] },
  hairline: { height: 1, backgroundColor: p.border.default, marginVertical: v2.space.xs },
  totalRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline' },
  totalLabel: { color: p.text.primary },
  totalValue: { color: p.text.primary },

  payState: {
    marginTop: v2.space.xl,
    borderTopWidth: 1,
    borderTopColor: p.border.default,
    paddingTop: v2.space.md,
  },
  payStateRow: { flexDirection: 'row', alignItems: 'center', gap: v2.space.sm },
  payStateText: { color: p.text.secondary },
  /** An in-flight status, at full strength: the primary ink, never the disabled control's 40%. */
  payStatus: { color: p.text.primary, marginTop: v2.space.md },
  payError: { color: p.status.error },

  // The V3 state treatment (pkg8): a filled panel with a 3pt accent, the shape the transfer
  // screens use for the same job.
  notice: {
    backgroundColor: p.surface.surface,
    borderRadius: v2.radius.md,
    borderLeftWidth: 3,
    padding: v2.space.lg,
    gap: v2.space.xs,
  },
  noticeTitle: { color: p.text.primary },
  noticeAction: { marginTop: v2.space.md },

  trust: { color: p.text.muted, marginTop: v2.space.lg },

  bar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: v2.space.md,
    paddingHorizontal: v2.space.lg,
    paddingTop: v2.space.md,
    borderTopWidth: 1,
    borderTopColor: p.border.strong,
    backgroundColor: p.surface.surface,
  },

  // Confirmation
  confirmWrap: { flex: 1, backgroundColor: p.surface.canvas },
  confirmBody: { flex: 1, paddingHorizontal: v2.space.lg, gap: v2.space.md },
  confirmKicker: { color: p.status.success },
  // Same kicker, three readings: settled / not landed yet / unfulfillable.
  confirmKickerPending: { color: p.status.warning },
  confirmKickerFailed: { color: p.status.error },
  confirmTitle: { color: p.text.primary },
  confirmCard: {
    flexDirection: 'row',
    gap: v2.space.md,
    alignItems: 'center',
    marginTop: v2.space.md,
    borderTopWidth: 1,
    borderBottomWidth: 1,
    borderColor: p.border.default,
    paddingVertical: v2.space.md,
  },
  confirmNote: { color: p.text.secondary, marginTop: v2.space.md },
});
}

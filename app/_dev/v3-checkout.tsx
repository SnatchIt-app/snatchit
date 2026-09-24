/**
 * app/_dev/v3-checkout.tsx — the V3 CHECKOUT rendering harness (owner 2026-09-24: "complete
 * checkout presentation through a rendering path that cannot mount payment setup").
 *
 * WHY THIS ROUTE IS DIFFERENT FROM THE OTHER HARNESSES. The other `_dev` routes mount the real
 * screen with its one network read short-circuited. Checkout cannot be mounted that way, twice over:
 * its setup effect creates or reuses a PaymentIntent (`decideCheckoutSetup` step 3 calls
 * `createIntent()` for auction mode), and `CheckoutNative.tsx` imports
 * `@stripe/stripe-react-native`, which the web bundle deliberately excludes.
 *
 * So this route renders `CheckoutView` — the real presentation the real screen renders, with the
 * effects left behind in `CheckoutNative`. The import graph of that module contains no Stripe
 * package, no payment module and no checkout decision module, which is asserted in
 * `tests/v3-checkout-view.test.ts`. Mounting this route cannot create a PaymentIntent because
 * nothing reachable from it can, rather than because it chooses not to.
 *
 * WHAT A RENDER HERE PROVES. What the presentation paints from a given state: composition, spacing,
 * type, colour roles, shapes, wrapping, both appearances. It proves nothing about the setup
 * sequence, the PaymentSheet, settlement, or native rendering — and the amounts below are sample
 * figures in the shape the server's breakdown supplies, never a real charge.
 *
 * NOT REACHABLE IN PRODUCTION. The segment layout gates the whole group and this file redirects on
 * its own too.
 *
 * NO WRITES, AND NO READS. Every value is a literal in this file.
 */

import { Redirect, useLocalSearchParams } from 'expo-router';
import { useEffect } from 'react';

import { IS_SANDBOX_BUILD } from '@/src/config/envGuard';
import { payControl, type PayControlInput } from '@/src/lib/checkout/payControl';
import CheckoutView, {
  CheckoutShell,
  ConfirmationView,
  RefundView,
  type CheckoutIdentity,
  type CheckoutViewProps,
} from '@/src/screens/checkout/CheckoutView';
import { useAppearancePreference } from '@/src/theme/appearance';

declare const __DEV__: boolean;

/** Sample content, not production data (owner's standing caveat on every fixture). */
const IDENTITY: CheckoutIdentity = {
  cover: null,
  eventName: 'Neon Choir',
  venue: 'Lantern Room',
  eventDate: '2026-10-24',
  eventTime: '19:30:00',
  quantity: 2,
  ticketType: 'GA',
};

/** The shape the server's breakdown arrives in, already formatted by the screen's money module. */
const BREAKDOWN = { item: 'Tickets', amount: '$90.00', fee: '$9.00', total: '$99.00' };
// A's §2f wording, the same string `ESCROW_NOTE_COPY` now holds.
const ESCROW = "You pay now. If the tickets don't arrive, report it from your order; a report freezes the seller's payout.";

/**
 * Every fixture's pay control is produced by the REAL `payControl`, from the inputs that select its
 * branch — never hand-typed (E's finding on `7e08d4d7`: a hand-typed 'Preparing…' meant payControl's
 * own `paymentLoading` label, "Setting up payment", was rendered by no fixture at all, while the
 * coverage test passed on the table in this header. A harness that retypes the function's output can
 * drift from it silently; one that calls it cannot).
 */
const pay = (over: Partial<PayControlInput> = {}) => payControl({
  authLoading: false, paymentLoading: false, confirming: false, paymentReady: false,
  paymentError: false, formattedTotal: '$99.00', ...over,
});

const BASE: CheckoutViewProps = {
  identity: IDENTITY,
  isBuyNow: true,
  reservationMsLeft: 7 * 60_000 + 12_000,
  countdown: '7:12',
  holdUntil: '7:34 pm',
  breakdown: BREAKDOWN,
  preparing: false,
  paymentMethodLine: 'Apple Pay or card',
  notice: null,
  errorLine: null,
  escrowNote: ESCROW,
  pay: pay({ paymentReady: true }),
  onPay: () => {},
  acceptTotal: null,
  onBack: () => {},
};

/**
 * Every state the presentation can be in, driven by `?state=`. Each one is the resolved OUTPUT of a
 * decision the real screen makes — the decisions themselves stay in the screen and its own suites.
 *
 * COVERAGE OF THE PAY CONTROL (B's review at d374bd3f, via E: a reviewer has to be able to see that
 * the set is complete). `payControl` resolves eleven outcomes, in this precedence. Each one has a
 * fixture here, and `tests/v3-checkout-view.test.ts` asserts the mapping stays total:
 *
 *   payControl outcome        │ ?state=
 *   ───────────────────────────┼──────────────────
 *   Finalizing your order     │ finalizing
 *   Confirming payment        │ confirming
 *   Checking your payment     │ unconfirmed
 *   Authenticating            │ authenticating
 *   Setting up payment        │ preparing
 *   Check again               │ status-unknown
 *   Back to listing           │ hold-lost
 *   Checking your hold        │ hold-checking
 *   Pay <total>               │ ready · auction
 *   Try again                 │ failed
 *   Payment unavailable       │ unavailable
 *
 * Plus the faces the screen reaches through its own early returns, which the control never paints:
 * complete · pending · settle-failed · refund. And `price-changed`, where the accept control
 * REPLACES the pay control entirely.
 */
export const CHECKOUT_STATES: Record<string, CheckoutViewProps> = {
  // Setup running: no figure anywhere, and the control says what it is doing.
  preparing: {
    ...BASE,
    breakdown: null,
    preparing: true,
    paymentMethodLine: null,
    reservationMsLeft: null,
    countdown: null,
    escrowNote: ESCROW,
    pay: pay({ paymentLoading: true }),
  },
  // Ready, Buy Now: the hold counts down and the control carries the server's total.
  ready: BASE,
  // Ready, auction: no hold, and the money row names the winning bid.
  auction: {
    ...BASE,
    isBuyNow: false,
    reservationMsLeft: null,
    countdown: null,
    holdUntil: null,
    breakdown: { ...BREAKDOWN, item: 'Winning bid' },
  },
  // The hold is gone. The copy is the real `notHeldCopy` wording for a hold that expired on its own.
  'hold-lost': {
    ...BASE,
    reservationMsLeft: null,
    countdown: null,
    paymentMethodLine: null,
    notice: {
      title: 'Your hold has expired',
      body: 'The reservation ran out before payment completed. Nothing was charged. You can try again if the listing is still available.',
    },
    pay: pay({ holdLost: true }),
  },
  // A new total awaits acceptance: the rows are withheld and the action carries the only figure.
  'price-changed': {
    ...BASE,
    breakdown: null,
    paymentMethodLine: null,
    notice: {
      title: 'The total changed',
      body: 'It was $99.00 and is now $104.00, service fee included. Nothing has been charged. Accept the new total to continue.',
    },
    acceptTotal: { label: 'Accept $104.00', onPress: () => {} },
  },
  // A payment result that could not be confirmed: no Pay, one check, and no escrow reassurance.
  unconfirmed: {
    ...BASE,
    paymentMethodLine: null,
    escrowNote: null,
    notice: {
      title: "We couldn't confirm your payment yet",
      body: "Your last attempt may or may not have gone through. Please don't pay again. We'll keep checking; you can also check now.",
      action: { label: 'Check status', onPress: () => {}, loading: false },
    },
    pay: pay({ checking: true }),
  },
  // A setup failure: the safe sentence, with the retry on the control itself.
  failed: {
    ...BASE,
    breakdown: null,
    paymentMethodLine: null,
    escrowNote: null,
    errorLine: "We couldn't start payment. Please try again.",
    pay: pay({ paymentError: true }),
  },
  // The hold hit zero while the screen re-checks it with the server.
  'hold-checking': {
    ...BASE,
    reservationMsLeft: 0,
    countdown: '0:00',
    paymentMethodLine: null,
    pay: pay({ paymentReady: true, reservationMsLeft: 0 }),
  },
  // The charge is in flight. The sheet is up over the app on a device, so this is what is behind it.
  confirming: {
    ...BASE,
    paymentMethodLine: null,
    pay: pay({ confirming: true }),
  },
  // Charged, and the settlement record is being written (CFT-306: its own step, its own words).
  finalizing: {
    ...BASE,
    paymentMethodLine: null,
    pay: pay({ finalizing: true }),
  },
  // The session is still resolving, so nothing about this buyer is known yet.
  authenticating: {
    ...BASE,
    breakdown: null,
    paymentMethodLine: null,
    escrowNote: null,
    reservationMsLeft: null,
    countdown: null,
    pay: pay({ authLoading: true }),
  },
  // The settled-payment read failed, so whether this buyer already paid is UNKNOWN: no Pay is
  // offered, the escrow line is withheld, and the only action re-runs the check.
  'status-unknown': {
    ...BASE,
    paymentMethodLine: null,
    escrowNote: null,
    notice: {
      title: "We couldn't check your payment status",
      body: "We could not confirm whether this order has already been paid. Please don't pay again — check again in a moment.",
    },
    pay: pay({ statusUnknown: true }),
  },
  // The floor of the precedence: nothing is ready and nothing failed loudly.
  unavailable: {
    ...BASE,
    breakdown: null,
    paymentMethodLine: null,
    escrowNote: null,
    reservationMsLeft: null,
    countdown: null,
    pay: pay(),
  },
};

export default function V3CheckoutHarness() {
  const { state, appearance } = useLocalSearchParams<{ state?: string; appearance?: string }>();
  // `?appearance=light|dark` drives the comparison capture from the app's own preference, the same
  // one Settings writes — never a browser emulation flag.
  const { setPreference } = useAppearancePreference();
  useEffect(() => {
    if (appearance === 'light' || appearance === 'dark' || appearance === 'system') setPreference(appearance);
  }, [appearance]);

  if (!IS_SANDBOX_BUILD && !__DEV__) return <Redirect href="/" />;

  // The two terminal faces, which the screen reaches through its own early returns.
  if (state === 'complete' || state === 'pending' || state === 'settle-failed') {
    const outcome = state === 'complete' ? 'completed' : state === 'pending' ? 'pending' : 'failed';
    return (
      <CheckoutShell>
        <ConfirmationView
          outcome={outcome}
          // The real SETTLEMENT_COPY entries, quoted as literals so this route imports no payment
          // module: `tests/v3-checkout-view.test.ts` pins that the screen passes the table itself.
          copy={outcome === 'pending'
            ? { title: 'Finishing your order', body: "Your payment went through and we are finishing the order. This can take a moment; don't pay again." }
            : { title: 'Payment received', body: "Your payment went through, but we couldn't complete this order. Please don't pay again — contact support and we'll sort it out right away." }}
          identity={IDENTITY}
          isBuyNow
          transferId={outcome === 'completed' ? 'fixture-transfer' : null}
          purchaseKey={`fixture-${state}`}
        />
      </CheckoutShell>
    );
  }
  if (state === 'refund') {
    return (
      <CheckoutShell>
        <RefundView
          // The shape `refundViewModel` returns; the model's own rules have their own suite.
          view={{
            kicker: 'Refund recorded',
            title: 'This order was refunded',
            body: 'A refund of $99.00 is recorded against this order. Nothing further is owed.',
            cta: { label: 'Back to home', href: '/(tabs)/home' },
          }}
          identity={IDENTITY}
        />
      </CheckoutShell>
    );
  }

  return <CheckoutView {...(CHECKOUT_STATES[state ?? 'ready'] ?? CHECKOUT_STATES.ready)} />;
}

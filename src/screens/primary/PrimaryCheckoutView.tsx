/**
 * src/screens/primary/PrimaryCheckoutView.tsx — the primary checkout's review step, as a pure view.
 *
 * A payments surface (reviewed by A). The headline is the ALL-IN total the server quoted (A's all-in
 * rule); tickets and the service fee are itemised beneath it, never shown as "the price". The pay
 * action opens Stripe's PaymentSheet; nothing on this screen is a success state — after the sheet the
 * route moves to the ticket page, which says "Awaiting payment confirmation" until tickets are issued.
 */
import { useMemo } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';

import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import { Button, EmptyState, Spinner } from '@/src/components/ui';
import { PRIMARY_CHECKOUT_COPY, formatUsd, type CheckoutRefusal, type PrimaryQuote } from '@/src/lib/primary/checkout';
import { HOLD_COPY, type HoldRefusal } from '@/src/lib/primary/checkoutRoute';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

export const PRIMARY_REVIEW_COPY = {
  screenTitle: 'Checkout',
  reviewTitle: 'Review your order',
  preparing: 'Holding your tickets',
  afterPay: 'Your tickets appear once your payment is confirmed.',
  heldUntil: (time: string) => `Held for you until ${time}`,
  invalid: { title: 'This checkout link isn’t valid', body: 'Go back to the event and choose your tickets again.' },
  signIn: { title: 'Sign in to buy tickets', body: 'You need an account to buy tickets.' },
  signInAction: 'Sign in',
  back: 'Back to event',
  reviewAgain: 'Review new total',
  tryAgain: 'Try again',
} as const;

export type PrimaryCheckoutViewState =
  | { kind: 'invalid' }
  | { kind: 'signed_out' }
  | { kind: 'preparing' }
  | { kind: 'hold_refused'; reason: HoldRefusal }
  | { kind: 'quote_refused'; reason: CheckoutRefusal }
  | { kind: 'price_changed'; serverTotalMinor: number | null }
  | { kind: 'review'; quote: PrimaryQuote; sheetReady: boolean; paying: boolean; paymentFailed: boolean };

export interface PrimaryCheckoutViewProps {
  state: PrimaryCheckoutViewState;
  eventTitle: string | null;
  tierName: string | null;
  quantity: number;
  /** Display text for the hold's server expiry, already formatted; null hides the line. */
  heldUntil: string | null;
  onPay: () => void;
  onReviewAgain: () => void;
  onRetry: () => void;
  onSignIn: () => void;
  onBack?: () => void;
}

export function PrimaryCheckoutView(props: PrimaryCheckoutViewProps) {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const { state } = props;

  const body = (() => {
    switch (state.kind) {
      case 'invalid':
        return <EmptyState title={PRIMARY_REVIEW_COPY.invalid.title} body={PRIMARY_REVIEW_COPY.invalid.body} action={props.onBack ? { label: PRIMARY_REVIEW_COPY.back, onPress: props.onBack } : undefined} />;
      case 'signed_out':
        return <EmptyState title={PRIMARY_REVIEW_COPY.signIn.title} body={PRIMARY_REVIEW_COPY.signIn.body} action={{ label: PRIMARY_REVIEW_COPY.signInAction, onPress: props.onSignIn }} />;
      case 'preparing':
        return <View style={s.center}><Spinner size="large" label={PRIMARY_REVIEW_COPY.preparing} /></View>;
      case 'hold_refused':
        return (
          <EmptyState
            title={HOLD_COPY[state.reason]}
            body=""
            action={state.reason === 'offline' || state.reason === 'unavailable'
              ? { label: PRIMARY_REVIEW_COPY.tryAgain, onPress: props.onRetry }
              : props.onBack ? { label: PRIMARY_REVIEW_COPY.back, onPress: props.onBack } : undefined}
          />
        );
      case 'quote_refused':
        return (
          <EmptyState
            title={PRIMARY_CHECKOUT_COPY.refusal[state.reason]}
            body=""
            action={state.reason === 'offline' || state.reason === 'unavailable' || state.reason === 'rate_limited'
              ? { label: PRIMARY_REVIEW_COPY.tryAgain, onPress: props.onRetry }
              : props.onBack ? { label: PRIMARY_REVIEW_COPY.back, onPress: props.onBack } : undefined}
          />
        );
      case 'price_changed':
        return (
          <View style={s.block}>
            <Text style={[textStyle('title'), s.title]} accessibilityRole="header">{PRIMARY_CHECKOUT_COPY.priceChanged.title}</Text>
            {state.serverTotalMinor !== null ? (
              <Text style={[textStyle('price'), s.total]}>{formatUsd(state.serverTotalMinor)}</Text>
            ) : null}
            <Text style={[textStyle('body'), s.meta]}>{PRIMARY_CHECKOUT_COPY.priceChanged.body}</Text>
            <Button label={PRIMARY_REVIEW_COPY.reviewAgain} variant="primary" onPress={props.onReviewAgain} />
          </View>
        );
      case 'review': {
        const q = state.quote;
        return (
          <View style={s.block}>
            <Text style={[textStyle('title'), s.title]} accessibilityRole="header">{PRIMARY_REVIEW_COPY.reviewTitle}</Text>
            {props.eventTitle ? <Text style={[textStyle('body'), s.meta]}>{props.eventTitle}</Text> : null}
            {props.tierName ? <Text style={[textStyle('body'), s.meta]}>{`${props.quantity} × ${props.tierName}`}</Text> : null}
            <View style={s.totalRow} accessible accessibilityLabel={`${PRIMARY_CHECKOUT_COPY.totalLabel}, ${formatUsd(q.totalMinor)}, including all fees`}>
              <Text style={[textStyle('label'), s.meta]}>{PRIMARY_CHECKOUT_COPY.totalLabel}</Text>
              <Text style={[textStyle('price'), s.total]}>{formatUsd(q.totalMinor)}</Text>
            </View>
            <Text style={[textStyle('bodySm'), s.meta]}>
              {`${PRIMARY_CHECKOUT_COPY.faceLabel} ${formatUsd(q.faceMinor)} · ${PRIMARY_CHECKOUT_COPY.feeLabel} ${formatUsd(q.buyerFeeMinor)}`}
            </Text>
            {props.heldUntil ? <Text style={[textStyle('bodySm'), s.meta]}>{PRIMARY_REVIEW_COPY.heldUntil(props.heldUntil)}</Text> : null}
            {state.paymentFailed ? (
              <Text style={[textStyle('body'), s.error]} accessibilityRole="alert">{PRIMARY_CHECKOUT_COPY.paymentFailed}</Text>
            ) : null}
            <Button
              label={`${PRIMARY_CHECKOUT_COPY.payAction} ${formatUsd(q.totalMinor)}`}
              variant="primary"
              onPress={props.onPay}
              disabled={!state.sheetReady || state.paying}
              loading={state.paying || !state.sheetReady}
            />
            <Text style={[textStyle('bodySm'), s.note]}>{PRIMARY_REVIEW_COPY.afterPay}</Text>
          </View>
        );
      }
      default:
        return null;
    }
  })();

  return (
    <View style={s.root}>
      <SettingsHeader title={PRIMARY_REVIEW_COPY.screenTitle} onBack={props.onBack} />
      <ScrollView contentContainerStyle={s.content}>{body}</ScrollView>
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
    root: { flex: 1, backgroundColor: p.surface.canvas },
    content: { padding: v2.space.lg, paddingBottom: v2.space.xxxl, flexGrow: 1 },
    center: { paddingVertical: v2.space.xxl, alignItems: 'center' },
    block: { gap: v2.space.md },
    title: { color: p.text.primary },
    meta: { color: p.text.secondary },
    totalRow: { flexDirection: 'row', alignItems: 'baseline', justifyContent: 'space-between', paddingVertical: v2.space.sm },
    total: { color: p.text.primary },
    error: { color: p.status.error },
    note: { color: p.text.muted, textAlign: 'center' },
  });
}

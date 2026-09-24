/**
 * src/components/transfer/TransferStateBlocks.tsx — the transfer-state blocks, ONE implementation.
 *
 * The receive (buyer) and send (seller) screens render these; so does the sandbox-only synthetic
 * gallery (`app/_dev/transfer-states.tsx`, owner 2026-09-24), which is why they live here and not
 * inside either screen: "render the same components used by the real screens … do not create
 * duplicate mock implementations."
 *
 * Every sentence comes from `src/lib/transfer/transferState.ts` — A's payment-state wording table
 * (2026-09-24): the ORDER fact from the transfer status; the REFUND fact only from the buyer's own
 * payment row; a HOLD only when held AND the server gives the date; never a payout claim before
 * `payout_released_at`; the word "reversed" never on the buyer's screen. Nothing here reads a
 * server or performs an action: the blocks are text over a palette surface.
 */

import { useMemo, type ReactNode } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import {
  BUYER_ORDER_CLOSED_COPY,
  REFUND_DUE_POLICY,
  REFUND_PENDING_LINE,
  SELLER_NO_PAYOUT_LINE,
  SELLER_REVERSED_COPY,
  buyerReviewDeadlineLine,
  refundLine,
  sellerHoldLine,
  sellerReleaseLine,
  transferStatusCopy,
  type PaymentRefundFacts,
} from '@/src/lib/transfer/transferState';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

export type StateTone = 'neutral' | 'success' | 'warning';

function useStyles() {
  const { palette } = useTheme();
  return { palette, s: useMemo(() => makeStyles(palette), [palette]) };
}

/** The shared frame: an optional title in the tone's ink, then whatever the state says. */
export function StateBlock({ title, tone, children }: { title?: string; tone: StateTone; children: ReactNode }) {
  const { palette, s } = useStyles();
  const color = tone === 'success' ? palette.status.success : tone === 'warning' ? palette.status.warning : palette.text.primary;
  return (
    <View style={s.block}>
      {title ? <Text style={[textStyle('title'), { color }]}>{title}</Text> : null}
      {children}
    </View>
  );
}

/**
 * The buyer's closed order — expired or reversed (A's table 2a / 2c). The order fact from the
 * status; the refund fact only from the payment row; nothing about the seller's payout event.
 * `expired` states the refund POLICY when nothing is recorded; `reversed` says only that a refund
 * will show if one is issued.
 */
export function BuyerClosedBlock({ status, refund }: { status: 'expired' | 'reversed'; refund: PaymentRefundFacts | null | undefined }) {
  const { s } = useStyles();
  const copy = BUYER_ORDER_CLOSED_COPY[status];
  const line = refundLine(refund) ?? (status === 'expired' ? REFUND_DUE_POLICY : REFUND_PENDING_LINE);
  return (
    <StateBlock title={copy.title} tone={status === 'expired' ? 'warning' : 'neutral'}>
      <Text style={[textStyle('bodySm'), s.text]}>{copy.body}</Text>
      <Text style={[textStyle('bodySm'), s.text]}>{line}</Text>
    </StateBlock>
  );
}

/**
 * The buyer's view of the seller's claim: "Seller marked as sent" is the seller's statement, not a
 * confirmation; then the review deadline from the server's `auto_release_at`, or nothing (B-5).
 * The confirm / report controls belong to the screen and are passed in as children.
 */
export function BuyerSellerSentBlock({ autoReleaseAt, children }: { autoReleaseAt: string | null | undefined; children?: ReactNode }) {
  const { s } = useStyles();
  const copy = transferStatusCopy('seller_sent', 'buyer');
  const deadline = buyerReviewDeadlineLine(autoReleaseAt);
  return (
    <View style={s.block}>
      <Text style={[textStyle('title'), s.claimTitle]}>{copy.title}</Text>
      <Text style={[textStyle('bodySm'), s.text]}>{copy.body}</Text>
      {deadline ? <Text style={[textStyle('bodySm'), s.sub]}>{deadline}</Text> : null}
      {children}
    </View>
  );
}

/** The seller's closed window (server-confirmed expiry): don't transfer; no payout ever moved (A's 2b). */
export function SellerClosedBlock({ title, body }: { title: string; body: string }) {
  const { s } = useStyles();
  return (
    <StateBlock title={title} tone="warning">
      <Text style={[textStyle('bodySm'), s.sub]}>{body}</Text>
      <Text style={[textStyle('bodySm'), s.sub]}>{SELLER_NO_PAYOUT_LINE}</Text>
    </StateBlock>
  );
}

/** The seller's reversed payout — checked BEFORE any payout claim (A's precedence). No amount is stored. */
export function SellerReversedBlock(_props: Record<string, never>) {
  const { s } = useStyles();
  return (
    <StateBlock title={SELLER_REVERSED_COPY.title} tone="warning">
      <Text style={[textStyle('bodySm'), s.text]}>{SELLER_REVERSED_COPY.body}</Text>
    </StateBlock>
  );
}

const SELLER_SENT_BODY = 'Waiting for the buyer to confirm they received the tickets.';
const SELLER_WINDOW_PASSED = 'The buyer review window has passed. Payout pending, it releases automatically once it clears review.';
const SELLER_HELD_FALLBACK = 'Payout pending, funds are held until shortly after the event as a standard protection. No action needed unless the buyer reports an issue.';
const SELLER_MANUAL_REVIEW = 'Payout pending, this transfer is under manual review. Our team may contact you; you can also reach support@snatchitapp.com.';
const SELLER_REPORT_WARNING = 'If the buyer reports an issue, your payout will be held for review.';

/**
 * The seller after marking sent (F-28: body only — the badge already reads "Marked sent"). Then
 * exactly one payout line: the release DECISION time while the window runs (A's 2e), the
 * window-passed sentence, the HOLD with the server's date (or the standard-protection fallback when
 * held without a date), or manual review. Never a payout claim.
 */
export function SellerSentBlock({
  payoutReviewStatus,
  payoutHoldUntil,
  autoReleaseAt,
  releaseCountdown,
}: {
  payoutReviewStatus: string | null | undefined;
  payoutHoldUntil: string | null | undefined;
  autoReleaseAt: string | null | undefined;
  /** The screen's formatted countdown to `auto_release_at`; 'Expired' once passed; null when absent. */
  releaseCountdown: string | null;
}) {
  const { s } = useStyles();
  const noReview = payoutReviewStatus == null;
  // A missing server date suppresses only the corresponding DATE line (owner 2026-09-24): the status
  // sentence, the held fallback and the warning never depend on it, and no empty line is painted.
  const releaseLine = noReview && releaseCountdown && releaseCountdown !== 'Expired' ? sellerReleaseLine(autoReleaseAt) : null;
  const holdLine = payoutReviewStatus === 'held' ? (sellerHoldLine(payoutReviewStatus, payoutHoldUntil) ?? SELLER_HELD_FALLBACK) : null;
  return (
    <StateBlock tone="neutral">
      <Text style={[textStyle('bodySm'), s.text]}>{SELLER_SENT_BODY}</Text>
      {releaseLine ? <Text style={[textStyle('bodySm'), s.sub]}>{releaseLine}</Text> : null}
      {noReview && releaseCountdown === 'Expired' ? (
        <Text style={[textStyle('bodySm'), s.sub]}>{SELLER_WINDOW_PASSED}</Text>
      ) : null}
      {holdLine ? <Text style={[textStyle('bodySm'), s.sub]}>{holdLine}</Text> : null}
      {payoutReviewStatus === 'manual_review' ? (
        <Text style={[textStyle('bodySm'), s.sub]}>{SELLER_MANUAL_REVIEW}</Text>
      ) : null}
      <Text style={[textStyle('bodySm'), s.warn]}>{SELLER_REPORT_WARNING}</Text>
    </StateBlock>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
    block: {
      backgroundColor: p.surface.surface,
      borderWidth: 1,
      borderColor: p.border.default,
      padding: v2.space.lg,
      marginBottom: v2.space.md,
      gap: v2.space.xs,
    },
    text: { color: p.text.secondary },
    sub: { color: p.text.muted, marginTop: v2.space.xs },
    warn: { color: p.status.warning, marginTop: v2.space.sm },
    claimTitle: { color: p.text.primary },
  });
}

/**
 * src/lib/payout/payoutStatusView.ts — what the payout screens may say, given what they actually know.
 *
 * Stripe's status arrives from the create-connect-account `status_only` probe (6 s timeout). Until it
 * answers — or when it fails, times out or says something unrecognised — the state is UNKNOWN. The
 * Profile row and Payout setup used to start at 'not_connected' and keep it on a failed probe, so a
 * connected seller read "Set up payouts — Not set up" (C, 2026-10-16). An unknown state now shows as
 * 'checking' or 'unavailable', and 'not_connected' only when the profile has no Connect account or the
 * server says so. A known status is never downgraded by a failed re-check. Presentation only: the
 * probe, the server and Stripe are untouched.
 */

export type ServerPayoutStatus = 'not_connected' | 'onboarding_required' | 'connected';
export type PayoutView = ServerPayoutStatus | 'checking' | 'unavailable';

const SERVER_STATUSES: readonly ServerPayoutStatus[] = ['not_connected', 'onboarding_required', 'connected'];

export function isServerPayoutStatus(value: unknown): value is ServerPayoutStatus {
  return typeof value === 'string' && (SERVER_STATUSES as readonly string[]).includes(value);
}

/** The status a status_only reply reports, or null when the reply says nothing usable. */
export function parsePayoutStatusReply(data: unknown): ServerPayoutStatus | null {
  let parsed: unknown = data;
  if (typeof data === 'string') {
    try { parsed = JSON.parse(data); } catch { return null; }
  }
  const status = (parsed as { status?: unknown } | null | undefined)?.status;
  return isServerPayoutStatus(status) ? status : null;
}

/** After the profile read: no Connect account is a definitive answer; a failed read or an account id is not. */
export function payoutViewAfterProfileRead(current: PayoutView, read: { connectId: string | null } | null): PayoutView {
  if (read === null) return isServerPayoutStatus(current) ? current : 'unavailable';
  if (!read.connectId) return 'not_connected';
  return isServerPayoutStatus(current) ? current : 'checking';
}

/** After the probe settles: a reported status wins; no answer keeps a known status and never invents a negative. */
export function settlePayoutView(current: PayoutView, reported: ServerPayoutStatus | null): PayoutView {
  if (reported) return reported;
  return isServerPayoutStatus(current) ? current : 'unavailable';
}

/** Profile → Payouts row. */
export const PAYOUT_ROW_COPY: Record<PayoutView, { title: string; state: string; tone: 'success' | 'warning' | 'neutral' }> = {
  connected:           { title: 'Connected to Stripe',   state: 'Payouts enabled',            tone: 'success' },
  onboarding_required: { title: 'Complete payout setup', state: 'Onboarding incomplete',      tone: 'warning' },
  not_connected:       { title: 'Set up payouts',        state: 'Not set up',                 tone: 'warning' },
  checking:            { title: 'Payouts',               state: 'Checking status…',           tone: 'neutral' },
  unavailable:         { title: 'Payouts',               state: 'Status unavailable — tap to check', tone: 'neutral' },
};

/** Payout setup while the status is unknown: say so, and offer a re-check instead of a setup call to action. */
export const PAYOUT_UNKNOWN_SETUP_COPY = {
  title: 'Payout status unavailable',
  description: "We couldn't reach Stripe to check your payout status just now. Nothing has changed with your account or your payouts.",
  statusLabel: 'Unknown',
  statusSub: 'Try again in a moment.',
  btnLabel: 'Try again',
} as const;

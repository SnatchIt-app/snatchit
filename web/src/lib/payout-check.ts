import type { PayoutStatus } from "@/lib/payouts";

export type PayoutCheckOutcome = { kind: "status"; status: PayoutStatus } | { kind: "failed" };

/**
 * What PayoutSetup may show after a status check. Only an answer without an error is a status:
 * an edge-function error used to come back as "not_connected" and render "Not connected" + "Set
 * up payouts" on the page Stripe returns to — a status nobody read. Errors and thrown checks are
 * "failed" (shown as "couldn't check", with Try again).
 */
export function payoutCheckOutcome(res: { status?: PayoutStatus; error?: string } | null | undefined): PayoutCheckOutcome {
  if (!res || res.error || !res.status) return { kind: "failed" };
  return { kind: "status", status: res.status };
}

import type { OpsResult } from "@/lib/ops-errors";
import { deniedReasonCode } from "@/lib/auth/messages";
import { toWhoami } from "@/lib/types";

export type MfaAccess = { type: "flow" } | { type: "redirect"; path: string };

/**
 * May this session see the TOTP enrol/verify flow on /mfa?
 *
 * The flow creates an authenticator factor on the account, so it is only for
 * operators. ops.whoami() (115:1134-1152) checks auth.uid() and
 * ops.actor_role() and has no aal requirement, so it answers at aal1:
 *  - an operator role → the flow (operators are unchanged);
 *  - 42501 (denied), or an answer without an operator role → /denied;
 *  - a step-up answer → the flow (stepping up is exactly what /mfa does, and
 *    refusing it would lock every operator out);
 *  - any other failure → /denied with the fixed reason code (fail closed,
 *    the same codes requireOperator uses).
 */
export function decideMfaAccess(input: { signedIn: boolean; whoami: OpsResult<unknown> | null }): MfaAccess {
  if (!input.signedIn) return { type: "redirect", path: "/login" };
  const res = input.whoami;
  if (!res) return { type: "redirect", path: `/denied?reason=${deniedReasonCode({})}` };
  if (res.ok) return toWhoami(res.data)?.role ? { type: "flow" } : { type: "redirect", path: "/denied" };
  if (res.kind === "denied") return { type: "redirect", path: "/denied" };
  if (res.kind === "mfa") return { type: "flow" };
  return { type: "redirect", path: `/denied?reason=${deniedReasonCode(res.kind === "error" ? res : {})}` };
}

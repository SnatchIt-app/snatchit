import type { ActionType, OperatorRole } from "@/lib/types";

/**
 * Mirror of `ops.action_allowed_roles()` (migration 115) so the UI can hide
 * forms an operator cannot submit. This is UX only — the database re-checks
 * the role on every call; a hidden form is not security.
 */
const ROLES_BY_ACTION: Partial<Record<ActionType | "setting_set", OperatorRole[]>> = {
  payout_release: ["platform_admin"],
  refund_execute: ["platform_admin"],
  dispute_resolve: ["platform_admin", "platform_risk"],
  listing_relist: ["platform_admin"],
  setting_set: ["platform_admin"],
  job_retry: ["platform_admin"],
  user_restrict: ["platform_admin", "platform_risk", "platform_support"],
  user_unrestrict: ["platform_admin", "platform_risk"],
};

const DEFAULT_ROLES: OperatorRole[] = ["platform_admin", "platform_risk", "platform_support"];

export function allowedRoles(actionType: ActionType | "setting_set" | string): OperatorRole[] {
  return ROLES_BY_ACTION[actionType as ActionType] ?? DEFAULT_ROLES;
}

export function canRequest(role: OperatorRole | null | undefined, actionType: ActionType | "setting_set" | string): boolean {
  if (!role) return false;
  return allowedRoles(actionType).includes(role);
}

/** Actions parked for a second founder (ops.action_requires_approval). */
export function requiresApproval(actionType: string): boolean {
  return actionType === "payout_release" || actionType === "refund_execute";
}

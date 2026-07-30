"use server";

import { requireAuthedUser } from "@/lib/auth/session";
import { getPayoutOnboardingUrl, getPayoutStatus, type PayoutStatus } from "@/lib/payouts";

export type PayoutActionResult = {
  status: PayoutStatus;
  url?: string;
  error?: string;
};

export async function checkPayoutStatusAction(): Promise<PayoutActionResult> {
  await requireAuthedUser();
  const { status, error } = await getPayoutStatus();
  return { status, error };
}

export async function startPayoutOnboardingAction(): Promise<PayoutActionResult> {
  await requireAuthedUser();
  const { url, status, error } = await getPayoutOnboardingUrl();
  if (error) return { status: status ?? "not_connected", error };
  return { status: status ?? "not_connected", url };
}

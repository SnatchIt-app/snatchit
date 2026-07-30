import "server-only";

import { callEdgeFunction } from "@/lib/edge-functions";

export type PayoutStatus = "not_connected" | "onboarding_required" | "connected";

type ConnectAccountResponse = { status?: PayoutStatus; url?: string };

export async function getPayoutStatus(): Promise<{ status: PayoutStatus; error?: string }> {
  const data = await callEdgeFunction<ConnectAccountResponse>("create-connect-account", { status_only: true });
  if (data.error) return { status: "not_connected", error: data.error };
  return { status: data.status ?? "not_connected" };
}

export async function getPayoutOnboardingUrl(): Promise<{ url?: string; status?: PayoutStatus; error?: string }> {
  return callEdgeFunction<ConnectAccountResponse>("create-connect-account", {});
}

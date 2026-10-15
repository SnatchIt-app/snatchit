import type { Metadata } from "next";
import { headers } from "next/headers";
import { getAuthedUser } from "@/lib/auth/session";
import { PayoutHandoff } from "@/components/account/PayoutHandoff";
import { isMobileUserAgent } from "@/lib/payout-handoff";

export const metadata: Metadata = {
  title: "Payouts",
  robots: { index: false, follow: false },
};

// Stripe Connect's refresh_url (the onboarding link expired or was reused). Public on purpose: the native app's
// in-app browser and other devices arrive without a web session, and must not be sent to a login
// page they can't use. See lib/payout-handoff.ts.
export default async function PayoutRefreshPage() {
  const [user, h] = await Promise.all([getAuthedUser(), headers()]);
  return <PayoutHandoff kind="refresh" signedIn={user !== null} mobile={isMobileUserAgent(h.get("user-agent"))} />;
}

import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getAuthedUser } from "@/lib/auth/session";
import { PhoneVerifyForm } from "@/components/account/PhoneVerifyForm";
import { AccountHeader } from "@/components/account/AccountHeader";

export const metadata: Metadata = {
  title: "Verify Phone",
  robots: { index: false, follow: true },
};

// Nested under app/account/layout.tsx, which already redirects unauthenticated
// visitors — this is a defensive second check (same rationale as that layout's
// own comment) that also preserves this page as the specific post-login
// destination, matching checkout/[id]/page.tsx's auth-gate pattern.
export default async function VerifyPhonePage() {
  const user = await getAuthedUser();
  if (!user) redirect(`/login?next=${encodeURIComponent("/account/verify-phone")}`);

  return (
    <div>
      {/* A pushed screen (the dock steps aside): the back chip stays on desktop too. */}
      <AccountHeader title="Verify your phone" back={{ href: "/account", label: "Back to your account", desktop: true }} />
      <PhoneVerifyForm />
    </div>
  );
}

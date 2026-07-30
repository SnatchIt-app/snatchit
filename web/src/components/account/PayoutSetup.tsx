"use client";

import { useEffect, useState } from "react";
import { checkPayoutStatusAction, startPayoutOnboardingAction } from "@/lib/payouts-actions";
import type { PayoutStatus } from "@/lib/payouts";
import { buttonClasses } from "@/components/ui/Button";
import { Alert } from "@/components/ui/Alert";

const COPY: Record<PayoutStatus, { title: string; description: string; dot: string; label: string; btn: string }> = {
  not_connected: {
    title: "Set up payouts",
    description:
      "Verify your identity and add a bank account to get paid. This usually takes about 2 minutes. Anyone can sell — no business registration needed.",
    dot: "bg-[#f5b942]",
    label: "Not connected",
    btn: "Set up payouts",
  },
  onboarding_required: {
    title: "Complete payout setup",
    description: "Almost there — finish verifying your identity and adding a bank account to get paid.",
    dot: "bg-[#f5b942]",
    label: "Onboarding incomplete",
    btn: "Continue setup",
  },
  connected: {
    title: "Payouts connected",
    description: "Your Stripe account is connected. Payouts are deposited automatically when your listings sell.",
    dot: "bg-[#3ecf8e]",
    label: "Connected",
    btn: "Manage payouts",
  },
};

export function PayoutSetup() {
  const [status, setStatus] = useState<PayoutStatus | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    checkPayoutStatusAction().then((res) => {
      setStatus(res.status);
      if (res.error) setError(res.error);
    });
  }, []);

  async function handleClick() {
    setSubmitting(true);
    setError(null);
    const res = await startPayoutOnboardingAction();
    setStatus(res.status);
    if (res.error) {
      setError(res.error);
      setSubmitting(false);
      return;
    }
    if (res.url) {
      // Full navigation, not a new tab — Stripe's return_url currently
      // brings the browser back to snatchitapp.com/payout-return (shared
      // with mobile), not back to this app. See settings page note.
      window.location.href = res.url;
      return;
    }
    setSubmitting(false);
  }

  if (status === null) {
    return <p className="text-[13.5px] text-white/50">Checking payout status…</p>;
  }

  const copy = COPY[status];

  return (
    <div className="max-w-[420px] space-y-4">
      {error ? <Alert tone="error">{error}</Alert> : null}
      <p className="text-[13.5px] leading-relaxed text-white/60">{copy.description}</p>
      <div className="flex items-center gap-2 border border-primary/15 px-4 py-3">
        <span className={`size-2 rounded-full ${copy.dot}`} />
        <span className="text-[13px] font-semibold text-ink">{copy.label}</span>
      </div>
      <button type="button" onClick={handleClick} disabled={submitting} className={buttonClasses("secondary", "md")}>
        {submitting ? "Opening Stripe…" : copy.btn}
      </button>
      <p className="text-[11.5px] leading-relaxed text-white/35">
        Your banking details are never stored on our servers. All payouts are processed securely through Stripe
        Connect.
      </p>
    </div>
  );
}

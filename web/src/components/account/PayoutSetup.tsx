"use client";

import { useEffect, useState } from "react";
import { checkPayoutStatusAction, startPayoutOnboardingAction } from "@/lib/payouts-actions";
import type { PayoutStatus } from "@/lib/payouts";
import { Button } from "@/components/ui/Button";
import { Alert } from "@/components/ui/Alert";
import { Badge, type Tone } from "@/components/ui/Badge";

const COPY: Record<PayoutStatus, { title: string; description: string; tone: Tone; label: string; btn: string }> = {
  not_connected: {
    title: "Set up payouts",
    description:
      "Verify your identity and add a bank account to get paid. This usually takes about 2 minutes. Anyone can sell — no business registration needed.",
    tone: "warning",
    label: "Not connected",
    btn: "Set up payouts",
  },
  onboarding_required: {
    title: "Complete payout setup",
    description: "Almost there — finish verifying your identity and adding a bank account to get paid.",
    tone: "warning",
    label: "Onboarding incomplete",
    btn: "Continue setup",
  },
  connected: {
    title: "Payouts connected",
    description: "Your Stripe account is connected. Payouts are deposited automatically when your listings sell.",
    tone: "success",
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
    return <p className="t-body text-muted">Checking payout status…</p>;
  }

  const copy = COPY[status];

  return (
    <div className="max-w-[480px] space-y-4">
      {error ? <Alert tone="error">{error}</Alert> : null}
      <div>
        <Badge tone={copy.tone}>
          <span aria-hidden="true" className="size-1.5 rounded-full bg-current" />
          {copy.label}
        </Badge>
      </div>
      <p className="t-body text-ink-2">{copy.description}</p>
      <Button
        type="button"
        variant={status === "connected" ? "secondary" : "primary"}
        className="self-start"
        onClick={handleClick}
        disabled={submitting}
        pending={submitting}
        pendingLabel="Opening Stripe…"
      >
        {copy.btn}
      </Button>
      <p className="t-body-sm text-muted">
        Your banking details are never stored on our servers. All payouts are processed securely through Stripe
        Connect.
      </p>
    </div>
  );
}

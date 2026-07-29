"use client";

import { useEffect, useState } from "react";
import { fmtEndsIn } from "@/lib/format";

/**
 * Coarse auction countdown (minute granularity — no per-second churn).
 * Re-syncs on tab focus to defeat background-tab timer throttling.
 */
export function Countdown({ endsAt }: { endsAt: string }) {
  const [label, setLabel] = useState(() => fmtEndsIn(endsAt));

  useEffect(() => {
    const update = () => setLabel(fmtEndsIn(endsAt));
    update();
    const id = setInterval(update, 30_000);
    document.addEventListener("visibilitychange", update);
    return () => {
      clearInterval(id);
      document.removeEventListener("visibilitychange", update);
    };
  }, [endsAt]);

  return (
    <span suppressHydrationWarning className="font-display text-[19px] font-bold leading-none text-ink">
      {label}
    </span>
  );
}

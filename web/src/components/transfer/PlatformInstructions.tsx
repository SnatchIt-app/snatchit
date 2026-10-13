"use client";

import { useState } from "react";
import { PLATFORM_INSTRUCTIONS, interpolateStep } from "@snatchit/core";
import type { TicketPlatform } from "@snatchit/types";

/**
 * Per-platform transfer steps, from the same @snatchit/core source mobile
 * uses. Every claim in there is grounded in official platform docs — do not
 * paraphrase or add steps here.
 *
 * {buyer_email} / {buyer_phone} placeholders are filled from the TRANSFER's
 * delivery fields (what the buyer typed), never from their profile.
 */
export function PlatformInstructions({
  platform,
  role,
  buyerEmail,
  buyerPhone,
}: {
  platform: string;
  role: "seller" | "buyer";
  buyerEmail?: string | null;
  buyerPhone?: string | null;
}) {
  const [tipsOpen, setTipsOpen] = useState(false);
  const entry = PLATFORM_INSTRUCTIONS[platform as TicketPlatform];
  if (!entry) return null;

  const side = role === "seller" ? entry.seller : entry.buyer;

  return (
    <section className="rounded-panel bg-surface p-5">
      <h2 className="t-title text-ink">{side.title}</h2>
      <p className="t-body-sm mt-1 text-muted">
        {entry.displayName} · about {side.estimatedTime}
      </p>

      <ol className="mt-4 space-y-3">
        {side.steps.map((step, i) => (
          <li key={i} className="t-body flex gap-3 text-ink-2">
            <span
              aria-hidden="true"
              className="inline-flex size-6 shrink-0 items-center justify-center rounded-full border border-control text-[12px] font-bold text-ink"
            >
              {i + 1}
            </span>
            <span className="min-w-0 break-words">{interpolateStep(step, buyerEmail, buyerPhone)}</span>
          </li>
        ))}
      </ol>

      {side.tips.length > 0 ? (
        <div className="mt-4 border-t border-line pt-2">
          <button
            type="button"
            onClick={() => setTipsOpen((v) => !v)}
            aria-expanded={tipsOpen}
            className="inline-flex min-h-11 items-center gap-1 text-[14px] font-semibold text-ink hover:underline underline-offset-4"
          >
            {tipsOpen ? "Hide tips" : "Show tips"}
            <svg aria-hidden="true" viewBox="0 0 24 24" className={`size-4 transition-transform ${tipsOpen ? "rotate-180" : ""}`} fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="m6 9 6 6 6-6" /></svg>
          </button>
          {tipsOpen ? (
            <ul className="mt-1 space-y-2">
              {side.tips.map((tip, i) => (
                <li key={i} className="t-body-sm flex gap-2.5 text-ink-2">
                  <span aria-hidden="true" className="text-muted">·</span>
                  {tip}
                </li>
              ))}
            </ul>
          ) : null}
        </div>
      ) : null}

      {entry.warnings.length > 0 ? (
        <ul className="mt-4 space-y-2 border-t border-line pt-3">
          {entry.warnings.map((w, i) => (
            <li key={i} className="t-body-sm flex gap-2.5 text-danger">
              <svg aria-hidden="true" viewBox="0 0 24 24" className="mt-0.5 size-4 shrink-0" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 4 2.8 19.5h18.4L12 4ZM12 10v4.5M12 17v.01" /></svg>
              {w}
            </li>
          ))}
        </ul>
      ) : null}
    </section>
  );
}

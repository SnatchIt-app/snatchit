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
    <section className="border border-primary/20 bg-card p-5">
      <p className="eyebrow text-primary/80">{side.title}</p>
      <p className="mt-2 text-[12px] text-white/45">
        {entry.displayName} · about {side.estimatedTime}
      </p>

      <ol className="mt-4 space-y-2.5">
        {side.steps.map((step, i) => (
          <li key={i} className="flex gap-3 text-[13.5px] leading-relaxed text-white/80">
            <span className="shrink-0 font-display text-[13px] font-bold text-primary">{i + 1}</span>
            <span>{interpolateStep(step, buyerEmail, buyerPhone)}</span>
          </li>
        ))}
      </ol>

      {side.tips.length > 0 ? (
        <div className="mt-4 border-t border-primary/10 pt-3">
          <button
            type="button"
            onClick={() => setTipsOpen((v) => !v)}
            aria-expanded={tipsOpen}
            className="text-[11px] font-medium uppercase tracking-[0.25em] text-white/50 hover:text-white/80"
          >
            {tipsOpen ? "Hide tips" : "Show tips"}
          </button>
          {tipsOpen ? (
            <ul className="mt-3 space-y-2">
              {side.tips.map((tip, i) => (
                <li key={i} className="flex gap-2.5 text-[12.5px] leading-relaxed text-white/60">
                  <span aria-hidden="true" className="text-primary">·</span>
                  {tip}
                </li>
              ))}
            </ul>
          ) : null}
        </div>
      ) : null}

      {entry.warnings.length > 0 ? (
        <ul className="mt-4 space-y-2 border-t border-primary/10 pt-3">
          {entry.warnings.map((w, i) => (
            <li key={i} className="flex gap-2.5 text-[12.5px] leading-relaxed text-[#ff8f8a]">
              <span aria-hidden="true">!</span>
              {w}
            </li>
          ))}
        </ul>
      ) : null}
    </section>
  );
}

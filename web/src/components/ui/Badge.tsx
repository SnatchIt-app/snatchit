import type { ReactNode } from "react";

type Variant = "live" | "soon" | "sold" | "neutral" | "buyNow";

/**
 * Status marks — compact pills with soft color fills. Over artwork they sit
 * on a near-black plate for legibility; uppercase is reserved for these
 * micro-labels only, with restrained tracking.
 */
const styles: Record<Variant, string> = {
  live: "bg-bg/85 text-[#ff7a75] border border-[#e1060050]",
  soon: "bg-bg/85 text-warning border border-[#fbbf2440]",
  sold: "bg-bg/85 text-muted border border-white/15",
  neutral: "bg-white/[0.06] text-muted border border-white/10",
  buyNow: "bg-bg/85 text-success border border-[#4ade8040]",
};

export function Badge({
  variant = "neutral",
  children,
  className = "",
}: {
  variant?: Variant;
  children: ReactNode;
  className?: string;
}) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-[6px] px-2.5 py-1.5 text-[10.5px] font-bold uppercase leading-none tracking-[0.05em] ${styles[variant]} ${className}`}
    >
      {children}
    </span>
  );
}

/** Soft color chip for inline emphasis (e.g. "Buy Now" on cards). */
export function Chip({
  tone = "neutral",
  children,
  className = "",
}: {
  tone?: "red" | "green" | "neutral";
  children: ReactNode;
  className?: string;
}) {
  const tones = {
    red: "bg-primary-soft text-[#ff7a75]",
    green: "bg-[#4ade8018] text-success",
    neutral: "bg-white/[0.07] text-muted",
  } as const;
  return (
    <span
      className={`inline-flex items-center gap-1 rounded-[6px] px-2 py-1 text-[12px] font-bold leading-none ${tones[tone]} ${className}`}
    >
      {children}
    </span>
  );
}

/** Small pulsing dot for LIVE state (static when reduced motion). */
export function LiveDot() {
  return (
    <span className="relative flex size-1.5" aria-hidden="true">
      <span className="absolute inline-flex size-full animate-ping rounded-full bg-[#ff6b66] opacity-60 motion-reduce:hidden" />
      <span className="relative inline-flex size-1.5 rounded-full bg-[#ff6b66]" />
    </span>
  );
}

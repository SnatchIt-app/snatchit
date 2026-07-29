import type { ReactNode } from "react";

type Variant = "live" | "soon" | "sold" | "neutral" | "buyNow";

/**
 * Status marks: rectangular plates in the uppercase micro-voice. Opaque near-
 * black backing keeps them legible over event artwork without glow or blur.
 */
const styles: Record<Variant, string> = {
  live: "bg-bg/90 text-[#ff7a75] border border-[#e1060045]",
  soon: "bg-bg/90 text-warning border border-[#fbbf2438]",
  sold: "bg-bg/90 text-muted border border-white/12",
  neutral: "text-muted border border-white/12",
  buyNow: "bg-bg/90 text-success border border-[#4ade8038]",
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
      className={`inline-flex items-center gap-1.5 rounded-[3px] px-2 py-[5px] text-[10px] font-semibold uppercase leading-none tracking-[0.12em] ${styles[variant]} ${className}`}
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

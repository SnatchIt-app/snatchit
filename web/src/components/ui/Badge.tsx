import type { ReactNode } from "react";

type Variant = "live" | "soon" | "sold" | "neutral" | "buyNow";

// Opaque dark backdrops so badges stay legible over event artwork.
const styles: Record<Variant, string> = {
  live: "bg-bg/85 backdrop-blur-sm text-[#ff7a75] border border-[#e1060055]",
  soon: "bg-bg/85 backdrop-blur-sm text-warning border border-[#fbbf2445]",
  sold: "bg-bg/85 backdrop-blur-sm text-muted border border-white/15",
  neutral: "bg-white/6 text-muted border border-white/10",
  buyNow: "bg-bg/85 backdrop-blur-sm text-success border border-[#4ade8045]",
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
      className={`inline-flex items-center gap-1.5 rounded-chip px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.08em] ${styles[variant]} ${className}`}
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

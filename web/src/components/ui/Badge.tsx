import type { ReactNode } from "react";

type Variant = "live" | "soon" | "sold" | "neutral" | "buyNow";

/**
 * Status marks in the brand voice: square black plates over artwork with
 * tracked uppercase micro type. Red and white only — the marketing site's
 * palette has no other hues.
 */
const styles: Record<Variant, string> = {
  live: "bg-black/85 text-primary border border-primary/40",
  soon: "bg-black/85 text-ink border border-white/25",
  sold: "bg-black/85 text-white/50 border border-white/15",
  neutral: "bg-white/[0.06] text-white/60 border border-white/10",
  buyNow: "bg-primary text-black border border-primary",
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
      className={`inline-flex items-center gap-1.5 px-2.5 py-1.5 text-[10px] font-bold uppercase leading-none tracking-[0.18em] ${styles[variant]} ${className}`}
    >
      {children}
    </span>
  );
}

/** Inline tracked micro-label (e.g. "Buy Now" on cards, "Verified" on sellers). */
export function Chip({
  tone = "neutral",
  children,
  className = "",
}: {
  tone?: "red" | "green" | "neutral";
  children: ReactNode;
  className?: string;
}) {
  // "green" is kept as an accepted tone name for call-site compatibility but
  // renders in the brand system (red) — the site's palette has no green.
  const tones = {
    red: "text-primary",
    green: "text-primary",
    neutral: "text-white/50",
  } as const;
  return (
    <span
      className={`inline-flex items-center gap-1.5 text-[10.5px] font-bold uppercase leading-none tracking-[0.22em] ${tones[tone]} ${className}`}
    >
      {children}
    </span>
  );
}

/** Small pulsing dot for LIVE state (halo pulse; static when reduced motion). */
export function LiveDot() {
  return (
    <span
      aria-hidden="true"
      className="pulse-red inline-flex size-1.5 rounded-full bg-primary motion-reduce:animate-none"
    />
  );
}

/** Static red dot for "unread" states in nav (header, account menu). */
export function UnreadDot() {
  return <span aria-hidden="true" className="inline-flex size-[7px] shrink-0 rounded-full bg-primary" />;
}

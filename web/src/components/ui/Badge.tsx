import type { ReactNode } from "react";

export type Tone = "neutral" | "success" | "warning" | "danger" | "info" | "brand";

/**
 * Native Badge (src/components/ui/Badge.tsx): a small outlined pill in the
 * tone colour on a transparent fill. Over artwork it sits on a dark plate so
 * it reads in both themes.
 */
const tones: Record<Tone, string> = {
  neutral: "border-control text-ink-2",
  success: "border-success text-success",
  warning: "border-warning text-warning",
  danger: "border-danger text-danger",
  info: "border-info text-info",
  brand: "border-brand-text text-brand-text",
};

export function Badge({
  tone = "neutral",
  onArt = false,
  children,
  className = "",
}: {
  tone?: Tone;
  onArt?: boolean;
  children: ReactNode;
  className?: string;
}) {
  const look = onArt ? "border-white/30 bg-black/60 text-white" : tones[tone];
  return (
    <span
      className={`inline-flex min-h-[22px] items-center gap-1.5 whitespace-nowrap rounded-[11px] border px-2 text-[12px] font-semibold leading-none ${look} ${className}`}
    >
      {children}
    </span>
  );
}

/** Quiet inline mark next to a name ("Verified seller"). */
export function Chip({ tone = "success", children, className = "" }: { tone?: Tone; children: ReactNode; className?: string }) {
  return (
    <Badge tone={tone} className={className}>
      {children}
    </Badge>
  );
}

/** Small red dot for a live auction (static under reduced motion). */
export function LiveDot() {
  return (
    <span aria-hidden="true" className="relative inline-flex size-2">
      <span className="absolute inset-0 rounded-full bg-brand opacity-60 motion-safe:[animation:sn-pulse_1.1s_ease-in-out_infinite_alternate]" />
      <span className="relative inline-flex size-2 rounded-full bg-brand" />
    </span>
  );
}

/** Static red dot for "unread". */
export function UnreadDot({ className = "" }: { className?: string }) {
  return <span aria-hidden="true" className={`inline-flex size-2 shrink-0 rounded-full bg-brand ${className}`} />;
}

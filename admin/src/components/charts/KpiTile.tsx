import type { ReactNode } from "react";
import type { Delta } from "@/lib/analytics-core";

/**
 * One business measure: label, value (proportional figures), comparison vs the previous
 * period, and its definition in plain text (never hover-only). `goodWhen` sets whether an
 * increase is good; the arrow glyph and the words carry direction, colour only reinforces.
 */
export function KpiTile({
  label,
  value,
  valueNote,
  delta,
  goodWhen = "up",
  definition,
  href,
  hrefLabel,
  muted = false,
}: {
  label: string;
  value: ReactNode;
  valueNote?: ReactNode;
  delta?: Delta | null;
  goodWhen?: "up" | "down" | "neutral";
  definition: ReactNode;
  href?: string;
  hrefLabel?: string;
  /** Not tracked / not available: de-emphasised value. */
  muted?: boolean;
}) {
  const tone =
    !delta || delta.kind === "none" || delta.kind === "flat" || delta.kind === "new" || goodWhen === "neutral"
      ? "text-dim"
      : (delta.kind === "up") === (goodWhen === "up")
        ? "text-success"
        : "text-danger";
  const glyph = delta?.kind === "up" ? "↑" : delta?.kind === "down" ? "↓" : "";
  return (
    <div className="flex h-full flex-col rounded-[var(--radius-card)] border border-line bg-card p-4">
      <p className="text-[13px] font-medium text-muted">{label}</p>
      <p className={`mt-1.5 leading-tight ${muted ? "text-[17px] font-medium text-dim" : "text-[26px] font-semibold text-ink"}`}>{value}</p>
      {valueNote ? <p className="mt-1 text-[13px] text-muted">{valueNote}</p> : null}
      {delta ? (
        <p className={`mt-1.5 text-[13px] ${tone}`}>
          {glyph ? <span aria-hidden="true">{glyph} </span> : null}
          <span className="font-medium">{delta.text}</span>
          {delta.kind === "up" || delta.kind === "down" ? <span className="text-dim"> vs previous period</span> : null}
        </p>
      ) : null}
      <p className="mt-auto pt-3 text-[12px] leading-relaxed text-dim">{definition}</p>
      {href ? (
        <a href={href} className="link mt-2 self-start text-[13px]">
          {hrefLabel ?? "Details"}
        </a>
      ) : null}
    </div>
  );
}

import type { ReactNode } from "react";
import type { Delta } from "@/lib/analytics-core";
import type { FigureState } from "@/lib/figure-meta";

const OK: FigureState = { kind: "ok" };

/**
 * One business measure: label, value (proportional figures), comparison vs the previous
 * period, and its definition in plain text (never hover-only). `goodWhen` sets whether an
 * increase is good; the arrow glyph and the words carry direction, colour only reinforces.
 *
 * Four states, each explicit (`data-state`): `ok` shows the figure; `empty` keeps the
 * genuine zero and says the period had no rows; `unavailable` shows no figure at all
 * (not a dash) because the server returned none; `error` shows "Not read". A delta is
 * shown only when there is a figure to compare.
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
  state = OK,
  meta,
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
  state?: FigureState;
  /** The surface's own labels (period, timezone, currency, freshness) when they differ from the group's. */
  meta?: ReactNode;
}) {
  const noFigure = state.kind === "unavailable" || state.kind === "error";
  const headline: ReactNode = state.kind === "unavailable" ? "Not available" : state.kind === "error" ? "Not read" : value;
  const showDelta = Boolean(delta) && !noFigure;
  const showNote = valueNote !== undefined && valueNote !== null && state.kind === "ok";
  const tone =
    !delta || delta.kind === "none" || delta.kind === "flat" || delta.kind === "new" || goodWhen === "neutral"
      ? "text-dim"
      : (delta.kind === "up") === (goodWhen === "up")
        ? "text-success"
        : "text-danger";
  const glyph = delta?.kind === "up" ? "↑" : delta?.kind === "down" ? "↓" : "";
  return (
    <div className="panel flex h-full flex-col p-5" data-state={state.kind}>
      <p className="text-[0.8125rem] font-medium text-muted">{label}</p>
      <p className={`mt-2 ${muted || noFigure ? "text-[1.0625rem] font-medium leading-tight text-dim" : "stat-num !text-[2rem] text-ink"}`}>{headline}</p>
      {state.kind !== "ok" ? <p className={`mt-1 text-[0.8125rem] ${state.kind === "error" ? "font-medium text-danger" : "text-muted"}`}>{state.message}</p> : null}
      {showNote ? <p className="mt-1 text-[0.8125rem] text-muted">{valueNote}</p> : null}
      {showDelta && delta ? (
        <p className={`mt-1.5 text-[0.8125rem] ${tone}`}>
          {glyph ? <span aria-hidden="true">{glyph} </span> : null}
          <span className="font-medium">{delta.text}</span>
          {delta.kind === "up" || delta.kind === "down" ? <span className="text-dim"> vs previous period</span> : null}
        </p>
      ) : null}
      <p className="mt-auto pt-3 text-[0.75rem] leading-relaxed text-dim">{definition}</p>
      {meta ? <div className="mt-2 border-t border-line pt-2">{meta}</div> : null}
      {href ? (
        <a href={href} className="link mt-2 self-start text-[0.8125rem]">
          {hrefLabel ?? "Details"}
        </a>
      ) : null}
    </div>
  );
}

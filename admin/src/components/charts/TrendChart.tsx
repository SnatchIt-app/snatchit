"use client";

import { useEffect, useId, useMemo, useRef, useState, type KeyboardEvent, type PointerEvent } from "react";
import { formatUsdCompact, formatUsdExact, niceTicks } from "@/lib/analytics-core";

export type TrendPoint = { label: string; detail: string; value: number };
export type TrendUnit = "usd_cents" | "count";

/**
 * One measure over time. `line` for trends (2px line, 10% wash, end dot + end label),
 * `column` for per-period counts (≤24px columns, 4px rounded tops, 2px gaps).
 * Hover: crosshair + tooltip (line) or per-column tooltip. Keyboard: focus the chart,
 * ←/→ move between periods, Home/End jump, Esc clears; the value is announced politely.
 * The accessible table twin is rendered by the surrounding ChartCard.
 */
export function TrendChart({
  kind,
  unit,
  points,
  title,
  height = 220,
  partialLast = false,
}: {
  kind: "line" | "column";
  unit: TrendUnit;
  points: TrendPoint[];
  title: string;
  height?: number;
  /** Mark the final period as incomplete (today so far). */
  partialLast?: boolean;
}) {
  const wrap = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(640);
  const [active, setActive] = useState<number | null>(null);
  const live = useId();

  useEffect(() => {
    const el = wrap.current;
    if (!el) return;
    const ro = new ResizeObserver(([entry]) => setWidth(Math.max(280, Math.round(entry.contentRect.width))));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const fmtAxis = (v: number) => (unit === "usd_cents" ? formatUsdCompact(v) : Math.round(v).toLocaleString("en-US"));
  const fmtExact = (v: number) => (unit === "usd_cents" ? formatUsdExact(v) : `${v.toLocaleString("en-US")}`);

  const m = { top: 20, right: kind === "line" ? 64 : 12, bottom: 30, left: unit === "usd_cents" ? 56 : 36 };
  const plotW = Math.max(40, width - m.left - m.right);
  const plotH = height - m.top - m.bottom;
  const max = Math.max(0, ...points.map((p) => p.value));
  const ticks = useMemo(() => niceTicks(max, 4, unit === "count"), [max, unit]);
  const top = ticks[ticks.length - 1] || 1;
  const n = points.length;
  const band = n > 0 ? plotW / n : plotW;
  const xAt = (i: number) => (kind === "line" ? (n <= 1 ? plotW / 2 : (i * plotW) / (n - 1)) : band * i + band / 2);
  const yAt = (v: number) => plotH - (v / top) * plotH;

  const labelEvery = Math.max(1, Math.ceil(n / Math.max(2, Math.floor(plotW / 72))));
  const xLabels = points.map((p, i) => ({ i, text: p.label })).filter(({ i }) => i % labelEvery === 0 || i === n - 1);
  // Avoid a collision between the last regular label and the forced final label.
  const trimmed = xLabels.filter((l, k) => !(k === xLabels.length - 2 && xLabels[xLabels.length - 1].i - l.i < labelEvery * 0.75));

  const linePath = points.map((p, i) => `${i === 0 ? "M" : "L"}${xAt(i).toFixed(1)},${yAt(p.value).toFixed(1)}`).join("");
  const areaPath = n > 0 ? `${linePath}L${xAt(n - 1).toFixed(1)},${plotH}L${xAt(0).toFixed(1)},${plotH}Z` : "";
  const barW = Math.min(24, Math.max(2, band - 2));

  const pick = (e: PointerEvent<SVGRectElement>) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const x = ((e.clientX - rect.left) / rect.width) * plotW;
    const i = kind === "line" ? Math.round((x / plotW) * (n - 1)) : Math.floor(x / band);
    setActive(Math.min(n - 1, Math.max(0, i)));
  };
  const onKey = (e: KeyboardEvent<HTMLDivElement>) => {
    if (n === 0) return;
    const cur = active ?? n - 1;
    const next = e.key === "ArrowRight" ? Math.min(n - 1, cur + 1) : e.key === "ArrowLeft" ? Math.max(0, cur - 1) : e.key === "Home" ? 0 : e.key === "End" ? n - 1 : e.key === "Escape" ? null : undefined;
    if (next === undefined) return;
    e.preventDefault();
    setActive(next);
  };

  const a = active !== null ? points[active] : null;
  const tipX = active !== null ? m.left + xAt(active) : 0;
  const tipLeft = Math.min(Math.max(tipX, 90), width - 90);
  const last = n > 0 ? points[n - 1] : null;

  return (
    <div
      ref={wrap}
      className="relative outline-none focus-visible:rounded-[var(--radius-control)] focus-visible:ring-2 focus-visible:ring-primary-ink/40"
      tabIndex={0}
      role="group"
      aria-label={`${title}. Use the left and right arrow keys to read each period.`}
      aria-describedby={live}
      onKeyDown={onKey}
      onFocus={() => setActive((v) => (v === null && n > 0 ? n - 1 : v))}
      onBlur={() => setActive(null)}
    >
      <svg width={width} height={height} className="block max-w-full" aria-hidden="true">
        <g transform={`translate(${m.left},${m.top})`}>
          {ticks.map((t) => (
            <g key={t} transform={`translate(0,${yAt(t)})`}>
              <line x1={0} x2={plotW} stroke={t === 0 ? "var(--color-axis)" : "var(--color-grid)"} strokeWidth={1} shapeRendering="crispEdges" />
              <text x={-8} dy="0.32em" textAnchor="end" className="fill-dim text-[11px] tabular-nums">
                {fmtAxis(t)}
              </text>
            </g>
          ))}
          {trimmed.map(({ i, text }) => (
            <text key={i} x={xAt(i)} y={plotH + 20} textAnchor={kind === "line" && i === 0 ? "start" : kind === "line" && i === n - 1 ? "end" : "middle"} className="fill-dim text-[11px]">
              {text}
            </text>
          ))}

          {kind === "line" ? (
            <>
              <path d={areaPath} fill="var(--color-series-1)" fillOpacity={0.1} />
              <path d={linePath} fill="none" stroke="var(--color-series-1)" strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />
              {partialLast && n > 1 ? (
                <line x1={xAt(n - 2)} y1={yAt(points[n - 2].value)} x2={xAt(n - 1)} y2={yAt(points[n - 1].value)} stroke="var(--color-card)" strokeWidth={2} strokeDasharray="3 3" />
              ) : null}
              {last ? (
                <>
                  <circle cx={xAt(n - 1)} cy={yAt(last.value)} r={5} fill="var(--color-series-1)" stroke="var(--color-card)" strokeWidth={2} />
                  <text x={xAt(n - 1) + 10} y={yAt(last.value)} dy="0.32em" className="fill-ink text-[12px] font-medium">
                    {fmtAxis(last.value)}
                  </text>
                </>
              ) : null}
              {a && active !== null ? (
                <>
                  <line x1={xAt(active)} x2={xAt(active)} y1={0} y2={plotH} stroke="var(--color-line-strong)" strokeWidth={1} />
                  <circle cx={xAt(active)} cy={yAt(a.value)} r={5} fill="var(--color-series-1)" stroke="var(--color-card)" strokeWidth={2} />
                </>
              ) : null}
            </>
          ) : (
            points.map((p, i) => {
              const h = plotH - yAt(p.value);
              const x = xAt(i) - barW / 2;
              const y = yAt(p.value);
              const r = Math.min(4, h, barW / 2);
              const d = h <= 0 ? "" : `M${x},${plotH}V${y + r}Q${x},${y} ${x + r},${y}H${x + barW - r}Q${x + barW},${y} ${x + barW},${y + r}V${plotH}Z`;
              return <path key={i} d={d} fill="var(--color-series-1)" fillOpacity={active === null || active === i ? 1 : 0.45} />;
            })
          )}
          <rect x={0} y={0} width={plotW} height={plotH} fill="transparent" onPointerMove={pick} onPointerLeave={() => setActive(null)} />
        </g>
      </svg>

      {a ? (
        <div
          className="pointer-events-none absolute top-0 z-10 min-w-[140px] -translate-x-1/2 rounded-[var(--radius-control)] border border-line bg-card px-3 py-2 shadow-[0_4px_16px_rgba(17,17,17,0.08)]"
          style={{ left: tipLeft }}
        >
          <p className="text-[15px] font-semibold text-ink">{fmtExact(a.value)}</p>
          <p className="text-[12px] text-dim">{a.detail}</p>
        </div>
      ) : null}
      <p id={live} className="sr-only" aria-live="polite">
        {a ? `${a.detail}: ${fmtExact(a.value)}` : ""}
      </p>
    </div>
  );
}

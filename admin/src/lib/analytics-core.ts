/**
 * Business analytics — pure, unit-tested helpers. No I/O.
 *
 * Every figure here comes from `ops.money_overview(from, to)` evaluated over a
 * real UTC period. A trend is a sequence of such periods, each aggregated from
 * transactions by the database; nothing is interpolated, projected or derived
 * from a current total. Measures keep the database's definitions and are never
 * netted against each other:
 *
 *   captured sales      Σ payments.total, status ∈ (succeeded, refunded), by paid_at   (incl. buyer fees)
 *   platform fees       Σ buyer_fee + seller_fee, status = succeeded, by paid_at       (gross, before refunds)
 *   refunds             count of payments marked refunded, by refunded_at             (amount NOT stored: upper bound only)
 *   seller funds        Σ amount − seller_fee with a Stripe transfer id, by payout_released_at (to connected account — not a bank payout)
 *   bank payouts        not tracked
 */
import type { MoneyOverview } from "@/lib/types";

export const DAY_MS = 86_400_000;

/** "2026-09-14" → Date at 00:00 UTC; null when malformed. */
export function parseIsoDay(v: string | null | undefined): Date | null {
  if (!v || !/^\d{4}-\d{2}-\d{2}$/.test(v)) return null;
  const d = new Date(`${v}T00:00:00Z`);
  return Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== v ? null : d;
}

export const isoDay = (d: Date): string => d.toISOString().slice(0, 10);

export type Grain = "day" | "week";

export type Bucket = { from: string; to: string; label: string };

/** Inclusive UTC day count between two ISO days. */
export function dayCount(from: string, to: string): number {
  const a = parseIsoDay(from);
  const b = parseIsoDay(to);
  if (!a || !b || b < a) return 0;
  return Math.round((b.getTime() - a.getTime()) / DAY_MS) + 1;
}

/** Daily buckets up to 31 days; weekly (Monday-start, clipped to the range) beyond. */
export function grainFor(from: string, to: string): Grain {
  return dayCount(from, to) <= 31 ? "day" : "week";
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
export const shortDay = (iso: string): string => {
  const d = parseIsoDay(iso);
  return d ? `${MONTHS[d.getUTCMonth()]} ${d.getUTCDate()}` : iso;
};

export function buckets(from: string, to: string, grain: Grain = grainFor(from, to)): Bucket[] {
  const a = parseIsoDay(from);
  const b = parseIsoDay(to);
  if (!a || !b || b < a) return [];
  const out: Bucket[] = [];
  if (grain === "day") {
    for (let t = a.getTime(); t <= b.getTime(); t += DAY_MS) {
      const d = isoDay(new Date(t));
      out.push({ from: d, to: d, label: shortDay(d) });
    }
    return out;
  }
  // Weekly: Monday-start weeks, first and last clipped to the requested range.
  let start = a.getTime();
  while (start <= b.getTime()) {
    const dow = (new Date(start).getUTCDay() + 6) % 7; // 0 = Monday
    const end = Math.min(start + (6 - dow) * DAY_MS, b.getTime());
    const f = isoDay(new Date(start));
    const t = isoDay(new Date(end));
    out.push({ from: f, to: t, label: f === t ? shortDay(f) : `${shortDay(f)}–${shortDay(t)}` });
    start = end + DAY_MS;
  }
  return out;
}

/** The same-length period immediately before [from, to]. */
export function previousPeriod(from: string, to: string): { from: string; to: string } | null {
  const a = parseIsoDay(from);
  const n = dayCount(from, to);
  if (!a || n === 0) return null;
  return { from: isoDay(new Date(a.getTime() - n * DAY_MS)), to: isoDay(new Date(a.getTime() - DAY_MS)) };
}

export type MoneyFigures = {
  capturedCents: number | null;
  capturedCount: number | null;
  feesCents: number | null;
  feesCount: number | null;
  refundCount: number | null;
  refundUpperBoundCents: number | null;
  /** Set only when the database states the refunded amount exactly (after refund exactness); null today. */
  refundKnownCents: number | null;
  refundCertainty: "exact" | "uncertain";
  releasedCents: number | null;
  releasedCount: number | null;
  pendingCents: number | null;
  pendingCount: number | null;
  bankPayoutsTracked: boolean;
};

/** Read the §5 metrics out of one ops.money_overview() payload, by key — never by position. */
export function figuresFrom(o: MoneyOverview): MoneyFigures {
  const m = (k: string) => o.metrics.find((x) => x.key === k);
  const cap = m("gross_captured_volume");
  const fee = m("platform_fees_gross");
  const ref = m("refunded_volume");
  const rel = m("seller_funds_released");
  const pen = m("seller_funds_pending");
  const bank = m("bank_payouts");
  return {
    capturedCents: cap?.value_cents ?? null,
    capturedCount: cap?.count ?? null,
    feesCents: fee?.value_cents ?? null,
    feesCount: fee?.count ?? null,
    refundCount: ref?.count ?? null,
    refundUpperBoundCents: ref?.upper_bound_cents ?? null,
    refundKnownCents: ref && ref.certainty === "exact" && ref.value_cents !== null ? ref.value_cents : null,
    refundCertainty: ref && ref.certainty === "exact" && ref.value_cents !== null ? "exact" : "uncertain",
    releasedCents: rel?.value_cents ?? null,
    releasedCount: rel?.count ?? null,
    pendingCents: pen?.value_cents ?? null,
    pendingCount: pen?.count ?? null,
    bankPayoutsTracked: bank ? bank.tracked : false,
  };
}

export type SeriesPoint = { bucket: Bucket; figures: MoneyFigures };

/** A series is empty when no bucket has a captured payment, a fee, a refund or a release. */
export function isEmptySeries(points: SeriesPoint[]): boolean {
  return points.every(
    (p) => !p.figures.capturedCount && !p.figures.feesCount && !p.figures.refundCount && !p.figures.releasedCount,
  );
}

export type Delta = { kind: "up" | "down" | "flat" | "new" | "none"; pct: number | null; text: string };

/** Change vs the previous period. "new" when the previous period was zero; "none" when either side is unknown. */
export function delta(current: number | null, previous: number | null): Delta {
  if (current === null || previous === null) return { kind: "none", pct: null, text: "no comparison" };
  if (previous === 0 && current === 0) return { kind: "flat", pct: 0, text: "no change" };
  if (previous === 0) return { kind: "new", pct: null, text: "none in previous period" };
  const pct = ((current - previous) / Math.abs(previous)) * 100;
  const rounded = Math.round(pct);
  if (rounded === 0) return { kind: "flat", pct: 0, text: "no change" };
  return { kind: rounded > 0 ? "up" : "down", pct: rounded, text: `${rounded > 0 ? "+" : "−"}${Math.abs(rounded)}%` };
}

/** Clean axis ticks: 0 .. a round max, 3–5 steps (1/2/2.5/5 × 10^n). `integer` keeps steps ≥ 1 and whole (counts). */
export function niceTicks(max: number, target = 4, integer = false): number[] {
  if (!Number.isFinite(max) || max <= 0) return [0, 1];
  const raw = max / target;
  const pow = 10 ** Math.floor(Math.log10(raw));
  let step = [1, 2, 2.5, 5, 10].map((m) => m * pow).find((s) => s >= raw) ?? 10 * pow;
  if (integer) step = Math.max(1, Math.ceil(step));
  const top = Math.ceil(max / step) * step;
  const ticks: number[] = [];
  for (let v = 0; v <= top + step / 2; v += step) ticks.push(Math.round(v * 1e6) / 1e6);
  return ticks;
}

/** "$1,234" (whole dollars) for tiles; cents → dollars. */
export function formatUsdWhole(cents: number | null): string {
  if (cents === null) return "—";
  return `$${Math.round(cents / 100).toLocaleString("en-US")}`;
}

/** Axis/tooltip compact: $0 · $950 · $1.2K · $3.4M. */
export function formatUsdCompact(cents: number): string {
  const d = cents / 100;
  const abs = Math.abs(d);
  if (abs >= 1_000_000) return `$${(d / 1_000_000).toFixed(abs >= 10_000_000 ? 0 : 1).replace(/\.0$/, "")}M`;
  if (abs >= 1_000) return `$${(d / 1_000).toFixed(abs >= 10_000 ? 0 : 1).replace(/\.0$/, "")}K`;
  return `$${Math.round(d).toLocaleString("en-US")}`;
}

/** Exact dollars and cents for tables and tooltips. */
export function formatUsdExact(cents: number | null): string {
  if (cents === null) return "—";
  return `$${(cents / 100).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

export type Freshness = { state: "fresh" | "stale" | "unknown"; ageMinutes: number | null };

/** Live queries are fresh when computed within `staleAfterMinutes`; a missing timestamp is unknown, never fresh. */
export function freshness(computedAt: string | null, now: Date, staleAfterMinutes = 15): Freshness {
  if (!computedAt) return { state: "unknown", ageMinutes: null };
  const t = new Date(computedAt).getTime();
  if (Number.isNaN(t)) return { state: "unknown", ageMinutes: null };
  const age = Math.max(0, Math.round((now.getTime() - t) / 60_000));
  return { state: age > staleAfterMinutes ? "stale" : "fresh", ageMinutes: age };
}

export const RANGE_PRESETS = [
  { key: "7d", label: "Last 7 days", days: 7 },
  { key: "14d", label: "Last 14 days", days: 14 },
  { key: "30d", label: "Last 30 days", days: 30 },
  { key: "90d", label: "Last 90 days", days: 90 },
] as const;

export type RangeSelection = { from: string; to: string; preset: string | null; days: number };

/** Resolve ?range=30d or ?from=&to= (UTC, inclusive, ≤ 366 days, never in the future). Default: last 30 days. */
export function resolveRange(sp: { range?: string; from?: string; to?: string }, now: Date): RangeSelection {
  const today = isoDay(now);
  const preset = RANGE_PRESETS.find((p) => p.key === sp.range);
  if (!preset && sp.from && sp.to) {
    const f = parseIsoDay(sp.from);
    const t = parseIsoDay(sp.to);
    if (f && t && f <= t) {
      const to = t.getTime() > parseIsoDay(today)!.getTime() ? today : sp.to;
      const n = dayCount(sp.from, to);
      if (n >= 1 && n <= 366) return { from: sp.from, to, preset: null, days: n };
    }
  }
  const p = preset ?? RANGE_PRESETS[2];
  return { from: isoDay(new Date(parseIsoDay(today)!.getTime() - (p.days - 1) * DAY_MS)), to: today, preset: p.key, days: p.days };
}

export type RefundAmount =
  | { state: "none"; count: 0 }
  | { state: "known"; count: number; knownCents: number }
  | { state: "unknown"; count: number; atMostCents: number | null }
  | { state: "mixed"; count: number; knownCents: number; atMostCents: number | null };

/**
 * Refund amount across one or more periods (migration 120: amounts are unknown until refund exactness lands).
 * Known and upper-bound parts are kept apart — never added into one figure.
 */
export function refundAmount(periods: MoneyFigures[]): RefundAmount {
  let count = 0;
  let known = 0;
  let knownPeriods = 0;
  let unknownPeriods = 0;
  let atMost: number | null = 0;
  for (const f of periods) {
    const n = f.refundCount ?? 0;
    count += n;
    if (n === 0) continue;
    if (f.refundCertainty === "exact" && f.refundKnownCents !== null) {
      known += f.refundKnownCents;
      knownPeriods++;
    } else {
      unknownPeriods++;
      atMost = atMost === null || f.refundUpperBoundCents === null ? null : atMost + f.refundUpperBoundCents;
    }
  }
  if (count === 0) return { state: "none", count: 0 };
  if (unknownPeriods === 0) return { state: "known", count, knownCents: known };
  if (knownPeriods === 0) return { state: "unknown", count, atMostCents: atMost };
  return { state: "mixed", count, knownCents: known, atMostCents: atMost };
}

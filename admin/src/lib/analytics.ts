import "server-only";

import { callOps, type OpsFailure } from "@/lib/ops";
import { toMoneyOverview, type MoneyOverview } from "@/lib/types";
import { buckets, figuresFrom, grainFor, type Grain, type MoneyFigures, type SeriesPoint } from "@/lib/analytics-core";

/**
 * Business analytics reads. INTERIM CONTRACT: there is no time-series RPC yet,
 * so a series is N calls to the existing `ops.money_overview(p_from, p_to)` —
 * one per UTC day (ranges ≤ 31 days) or per Monday-start week (longer ranges),
 * run with bounded concurrency. Each point is therefore a genuine database
 * aggregate over that period; nothing is interpolated or derived from totals.
 * The proposed replacement (one set-based query) is specified in
 * docs/ANALYTICS_DATA_CONTRACT.md for release integration.
 *
 * Failure policy: if ANY bucket fails, the whole series is reported as failed.
 * A chart with silently missing periods would read as zero sales.
 */
export type PeriodResult = { ok: true; overview: MoneyOverview; figures: MoneyFigures } | OpsFailure;

export async function readPeriod(from: string, to: string): Promise<PeriodResult> {
  const res = await callOps<unknown>("money_overview", { p_from: from, p_to: to });
  if (!res.ok) return res;
  const overview = toMoneyOverview(res.data);
  if (!overview) return { ok: false, kind: "error", message: "Unrecognised payload from ops.money_overview()" };
  return { ok: true, overview, figures: figuresFrom(overview) };
}

export type SeriesResult =
  | { ok: true; grain: Grain; points: SeriesPoint[]; computedAt: string | null; calls: number }
  | (OpsFailure & { failedBucket: string });

const CONCURRENCY = 6;

export async function readSeries(from: string, to: string): Promise<SeriesResult> {
  const grain = grainFor(from, to);
  const list = buckets(from, to, grain);
  const results: PeriodResult[] = new Array(list.length);
  let next = 0;
  async function worker() {
    while (next < list.length) {
      const i = next++;
      results[i] = await readPeriod(list[i].from, list[i].to);
    }
  }
  await Promise.all(Array.from({ length: Math.min(CONCURRENCY, list.length) }, worker));
  const points: SeriesPoint[] = [];
  let computedAt: string | null = null;
  for (let i = 0; i < list.length; i++) {
    const r = results[i];
    if (!r.ok) return { ...r, failedBucket: `${list[i].from}…${list[i].to}` };
    points.push({ bucket: list[i], figures: r.figures });
    const c = r.overview.computed_at;
    if (c && (!computedAt || c < computedAt)) computedAt = c; // oldest point bounds the series' freshness
  }
  return { ok: true, grain, points, computedAt, calls: list.length };
}

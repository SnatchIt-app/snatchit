"use client";

import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import { formatRelative, formatUtc, parseDate } from "@/lib/format";

type FreshnessValue = { at: string | null; label: string | null; relative: string | null; stale: boolean };
const EMPTY: FreshnessValue = { at: null, label: null, relative: null, stale: false };
const Ctx = createContext<{ value: FreshnessValue; set: (v: FreshnessValue) => void } | null>(null);

const STALE_AFTER_MS = 15 * 60 * 1000;
const TICK_MS = 30 * 1000;

/** Lets a page report "data as of …" into the header slot. */
export function FreshnessProvider({ children }: { children: ReactNode }) {
  const [value, set] = useState<FreshnessValue>(EMPTY);
  return <Ctx.Provider value={{ value, set }}>{children}</Ctx.Provider>;
}

/** Rendered by pages that know their `computed_at`. Clock reads happen in the effect, not in render. */
export function ReportFreshness({ at, label = "Data as of" }: { at: string | null | undefined; label?: string }) {
  const ctx = useContext(Ctx);
  const set = ctx?.set;
  useEffect(() => {
    if (!set) return;
    const d = parseDate(at ?? null);
    if (!d) {
      set(EMPTY);
      return;
    }
    const compute = () => {
      const now = new Date();
      set({ at: d.toISOString(), label, relative: formatRelative(d, now), stale: now.getTime() - d.getTime() > STALE_AFTER_MS });
    };
    compute();
    const timer = window.setInterval(compute, TICK_MS);
    return () => {
      window.clearInterval(timer);
      set(EMPTY);
    };
  }, [at, label, set]);
  return null;
}

export function FreshnessSlot() {
  const ctx = useContext(Ctx);
  const v = ctx?.value ?? EMPTY;
  if (!v.at) return <span className="text-[11px] text-dim">live</span>;
  return (
    <span className={`text-[11px] ${v.stale ? "text-warning" : "text-dim"}`} title={formatUtc(v.at, true)}>
      {v.stale ? "Stale · " : ""}
      {v.label ?? "As of"} <time dateTime={v.at}>{v.relative}</time>
    </span>
  );
}

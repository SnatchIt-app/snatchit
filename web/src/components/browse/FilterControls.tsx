"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";
import { CATEGORIES, CATEGORY_LABELS, NEIGHBORHOOD_GROUPS, NEIGHBORHOOD_LABELS } from "@snatchit/core";
import { Select } from "@/components/ui/Input";
import { Button } from "@/components/ui/Button";

const PRICE_PRESETS = [100, 250, 500, 1000] as const;
export const FILTER_KEYS = ["category", "neighborhood", "type", "max", "sort"] as const;
type FilterKey = (typeof FILTER_KEYS)[number];
type Draft = Partial<Record<FilterKey, string>>;

function draftFrom(params: URLSearchParams): Draft {
  return Object.fromEntries(FILTER_KEYS.map((k) => [k, params.get(k) ?? ""])) as Draft;
}

/** Builds /browse?… from the current params with `draft` applied; the search text (q) always carries over. */
export function browseHref(params: URLSearchParams, draft: Draft): string {
  const next = new URLSearchParams(params.toString());
  for (const k of FILTER_KEYS) {
    const v = draft[k];
    if (v) next.set(k, v);
    else next.delete(k);
  }
  if (next.get("sort") === "ending") next.delete("sort");
  return `/browse${next.size ? `?${next.toString()}` : ""}`;
}

/**
 * Filter controls driving URL search params — every combination is a
 * shareable, server-rendered URL.
 *   live   (desktop rail): each change navigates immediately
 *   draft  (phone sheet):  changes collect locally; Apply navigates, Clear resets
 *                          — the native FilterSheet's Clear / Apply footer
 */
export function FilterControls({
  idPrefix = "f",
  mode = "live",
  onApplied,
}: {
  idPrefix?: string;
  mode?: "live" | "draft";
  onApplied?: () => void;
}) {
  const router = useRouter();
  const params = useSearchParams();
  const [draft, setDraft] = useState<Draft>(() => draftFrom(params));
  const value = (k: FilterKey) => (mode === "live" ? (params.get(k) ?? "") : (draft[k] ?? ""));

  function set(k: FilterKey, v: string) {
    if (mode === "live") router.push(browseHref(params, { ...draftFrom(params), [k]: v }));
    else setDraft((d) => ({ ...d, [k]: v }));
  }

  const hasFilters = ["q", ...FILTER_KEYS.filter((k) => k !== "sort")].some((k) => params.get(k));

  return (
    <div className="flex flex-col gap-6">
      <ChipGroup
        label="Sale type"
        options={[
          { value: "", label: "All" },
          { value: "buy_now", label: "Buy Now" },
          { value: "auction", label: "Auction only" },
        ]}
        value={value("type")}
        onChange={(v) => set("type", v)}
      />
      <ChipGroup
        label="Price, all-in"
        options={[{ value: "", label: "Any" }, ...PRICE_PRESETS.map((p) => ({ value: String(p), label: `Under $${p}` }))]}
        value={value("max")}
        onChange={(v) => set("max", v)}
      />

      <div>
        <label htmlFor={`${idPrefix}-category`} className="t-micro block text-muted">
          Category
        </label>
        <Select id={`${idPrefix}-category`} value={value("category")} onChange={(e) => set("category", e.target.value)}>
          <option value="">All categories</option>
          {CATEGORIES.map((c) => (
            <option key={c} value={c}>
              {CATEGORY_LABELS[c]}
            </option>
          ))}
        </Select>
      </div>

      <div>
        <label htmlFor={`${idPrefix}-hood`} className="t-micro block text-muted">
          Neighborhood
        </label>
        <Select id={`${idPrefix}-hood`} value={value("neighborhood")} onChange={(e) => set("neighborhood", e.target.value)}>
          <option value="">All of Miami</option>
          {NEIGHBORHOOD_GROUPS.map((group) => (
            <optgroup key={group.title} label={group.title}>
              {group.items.map((n) => (
                <option key={n} value={n}>
                  {NEIGHBORHOOD_LABELS[n]}
                </option>
              ))}
            </optgroup>
          ))}
        </Select>
      </div>

      <div>
        <label htmlFor={`${idPrefix}-sort`} className="t-micro block text-muted">
          Sort by
        </label>
        <Select id={`${idPrefix}-sort`} value={value("sort") || "ending"} onChange={(e) => set("sort", e.target.value)}>
          <option value="ending">Ending soonest</option>
          <option value="newest">Newest</option>
          <option value="price_asc">Price: low to high</option>
          <option value="price_desc">Price: high to low</option>
        </Select>
      </div>

      {mode === "draft" ? (
        <div className="sticky bottom-0 -mx-5 mt-2 grid grid-cols-2 gap-3 border-t border-line bg-elevated px-5 pb-[max(env(safe-area-inset-bottom),16px)] pt-4">
          <Button variant="secondary" size="lg" onClick={() => setDraft(Object.fromEntries(FILTER_KEYS.map((k) => [k, ""])) as Draft)}>
            Clear
          </Button>
          <Button
            size="lg"
            onClick={() => {
              router.push(browseHref(params, draft));
              onApplied?.();
            }}
          >
            Apply
          </Button>
        </div>
      ) : hasFilters ? (
        <Button variant="ghost" className="self-start !px-0 underline-offset-4 hover:underline hover:bg-transparent" onClick={() => router.push("/browse")}>
          Clear all filters
        </Button>
      ) : null}
    </div>
  );
}

/** Native Chip group: pill chips, 1px control outline; selected fills with ink. */
export function ChipGroup({
  label,
  options,
  value,
  onChange,
}: {
  label: string;
  options: { value: string; label: string }[];
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <fieldset>
      <legend className="t-micro mb-2.5 text-muted">{label}</legend>
      <div className="flex flex-wrap gap-2">
        {options.map((o) => {
          const on = value === o.value;
          return (
            <button
              key={o.value || "all"}
              type="button"
              aria-pressed={on}
              onClick={() => onChange(o.value)}
              className={`pressable min-h-9 rounded-full border px-3.5 text-[14px] font-medium ${
                on ? "border-ink bg-ink text-canvas" : "border-control text-ink hover:border-ink"
              }`}
            >
              {o.label}
            </button>
          );
        })}
      </div>
    </fieldset>
  );
}

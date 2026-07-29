"use client";

import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import {
  CATEGORIES,
  CATEGORY_LABELS,
  NEIGHBORHOOD_GROUPS,
  NEIGHBORHOOD_LABELS,
} from "@snatchit/core";
import { Input, Select } from "@/components/ui/Input";

const PRICE_PRESETS = [100, 250, 500, 1000] as const;

/**
 * Filter controls driving URL search params — every filter combination is a
 * shareable, server-rendered URL. Used in the desktop sidebar and inside the
 * mobile filter sheet.
 */
export function FilterControls({ idPrefix = "f" }: { idPrefix?: string }) {
  const router = useRouter();
  const params = useSearchParams();

  function setParam(key: string, value: string) {
    const next = new URLSearchParams(params.toString());
    if (value) next.set(key, value);
    else next.delete(key);
    router.push(`/browse${next.size ? `?${next.toString()}` : ""}`);
  }

  const hasFilters = ["q", "category", "neighborhood", "type", "max"].some((k) => params.get(k));

  return (
    <div className="space-y-5">
      <form
        action="/browse"
        method="get"
        role="search"
        onSubmit={(e) => {
          e.preventDefault();
          const q = new FormData(e.currentTarget).get("q");
          setParam("q", String(q ?? "").trim());
        }}
      >
        <label htmlFor={`${idPrefix}-q`} className="mb-2.5 block text-[10px] font-medium uppercase tracking-[0.25em] text-white/50">
          Search
        </label>
        <Input
          id={`${idPrefix}-q`}
          type="search"
          name="q"
          placeholder="Event or venue"
          defaultValue={params.get("q") ?? ""}
        />
      </form>

      <Field label="Category" id={`${idPrefix}-category`}>
        <Select
          id={`${idPrefix}-category`}
          value={params.get("category") ?? ""}
          onChange={(e) => setParam("category", e.target.value)}
        >
          <option value="">All categories</option>
          {CATEGORIES.map((c) => (
            <option key={c} value={c}>
              {CATEGORY_LABELS[c]}
            </option>
          ))}
        </Select>
      </Field>

      <Field label="Neighborhood" id={`${idPrefix}-hood`}>
        <Select
          id={`${idPrefix}-hood`}
          value={params.get("neighborhood") ?? ""}
          onChange={(e) => setParam("neighborhood", e.target.value)}
        >
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
      </Field>

      <Field label="Listing type" id={`${idPrefix}-type`}>
        <Select
          id={`${idPrefix}-type`}
          value={params.get("type") ?? ""}
          onChange={(e) => setParam("type", e.target.value)}
        >
          <option value="">Auctions &amp; Buy Now</option>
          <option value="buy_now">Buy Now available</option>
          <option value="auction">Auction only</option>
        </Select>
      </Field>

      <Field label="Max price (all-in)" id={`${idPrefix}-max`}>
        <Select
          id={`${idPrefix}-max`}
          value={params.get("max") ?? ""}
          onChange={(e) => setParam("max", e.target.value)}
        >
          <option value="">Any price</option>
          {PRICE_PRESETS.map((p) => (
            <option key={p} value={p}>
              Under ${p}
            </option>
          ))}
        </Select>
      </Field>

      <Field label="Sort by" id={`${idPrefix}-sort`}>
        <Select
          id={`${idPrefix}-sort`}
          value={params.get("sort") ?? "ending"}
          onChange={(e) => setParam("sort", e.target.value)}
        >
          <option value="ending">Ending soonest</option>
          <option value="newest">Newest</option>
          <option value="price_asc">Price: low to high</option>
          <option value="price_desc">Price: high to low</option>
        </Select>
      </Field>

      {hasFilters ? (
        <Link
          href="/browse"
          className="inline-flex min-h-11 items-center gap-1.5 text-[11px] font-medium uppercase tracking-[0.3em] text-primary transition-colors duration-200 hover:text-[#ff5f5f] motion-reduce:transition-none"
        >
          Clear all filters →
        </Link>
      ) : null}
    </div>
  );
}

function Field({
  label,
  id,
  children,
}: {
  label: string;
  id: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <label htmlFor={id} className="mb-2.5 block text-[10px] font-medium uppercase tracking-[0.25em] text-white/50">
        {label}
      </label>
      {children}
    </div>
  );
}

"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { browseHref } from "@/components/browse/FilterControls";

/** Native Search quick chips — one tap toggles a common filter in the URL. */
const CHIPS = [
  { key: "type", value: "buy_now", label: "Buy Now" },
  { key: "type", value: "auction", label: "Auctions" },
  { key: "max", value: "100", label: "Under $100" },
  { key: "max", value: "250", label: "Under $250" },
] as const;

export function QuickChips() {
  const router = useRouter();
  const params = useSearchParams();
  return (
    <>
      {CHIPS.map((c) => {
        const on = params.get(c.key) === c.value;
        return (
          <button
            key={`${c.key}-${c.value}`}
            type="button"
            aria-pressed={on}
            onClick={() => router.push(browseHref(params, { [c.key]: on ? "" : c.value }))}
            className={`pressable min-h-10 shrink-0 whitespace-nowrap rounded-full border px-4 text-[14px] font-medium ${
              on ? "border-ink bg-ink text-canvas" : "border-control text-ink hover:border-ink"
            }`}
          >
            {c.label}
          </button>
        );
      })}
    </>
  );
}

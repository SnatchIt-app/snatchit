"use client";

import { useEffect, useRef } from "react";
import { useSearchParams } from "next/navigation";
import { Button } from "@/components/ui/Button";
import { FilterControls } from "@/components/browse/FilterControls";

/**
 * Mobile filter sheet on the native <dialog> element — free focus trap,
 * Escape handling, and ::backdrop. Applying a filter navigates (URL-driven),
 * so the sheet auto-closes when the search params change.
 */
export function FiltersSheet({ activeCount = 0 }: { activeCount?: number }) {
  const ref = useRef<HTMLDialogElement>(null);
  const params = useSearchParams();
  const paramsKey = params.toString();

  useEffect(() => {
    ref.current?.close();
  }, [paramsKey]);

  return (
    <>
      <Button
        variant="secondary"
        className="w-full"
        onClick={() => ref.current?.showModal()}
        aria-haspopup="dialog"
      >
        <svg aria-hidden="true" viewBox="0 0 20 20" fill="none" className="size-4">
          <path
            d="M3 5h14M6 10h8M8.5 15h3"
            stroke="currentColor"
            strokeWidth="1.7"
            strokeLinecap="round"
          />
        </svg>
        Filters &amp; sort{activeCount > 0 ? ` (${activeCount})` : ""}
      </Button>

      <dialog
        ref={ref}
        aria-label="Filters and sort"
        onClick={(e) => {
          if (e.target === ref.current) ref.current?.close();
        }}
        className="fixed inset-x-0 bottom-0 m-0 mt-auto w-full max-w-none border-t border-primary/30 bg-black p-0 text-ink"
        style={{ maxHeight: "85dvh" }}
      >
        <div className="flex items-center justify-between border-b border-primary/15 px-5 py-4">
          <h2 className="font-display text-[18px] font-bold uppercase tracking-[-0.01em] text-ink">
            Filters &amp; sort
          </h2>
          <button
            onClick={() => ref.current?.close()}
            className="flex size-11 items-center justify-center text-muted transition-colors duration-200 hover:bg-white/[0.06] hover:text-ink motion-reduce:transition-none"
            aria-label="Close filters"
          >
            <svg aria-hidden="true" viewBox="0 0 20 20" fill="none" className="size-[18px]">
              <path
                d="m5 5 10 10M15 5 5 15"
                stroke="currentColor"
                strokeWidth="1.7"
                strokeLinecap="round"
              />
            </svg>
          </button>
        </div>
        <div className="overflow-y-auto px-5 py-5 pb-[max(env(safe-area-inset-bottom),24px)]">
          <FilterControls idPrefix="sheet" />
        </div>
      </dialog>
    </>
  );
}

"use client";

import { useRef, useState } from "react";
import { iconButtonClasses } from "@/components/ui/Button";
import { Icon } from "@/components/ui/Icon";
import { FilterControls } from "@/components/browse/FilterControls";

/**
 * Phone filters — the native FilterSheet on the native <dialog> element (free
 * focus trap, Escape, ::backdrop): slides up over the overlay scrim, square
 * top edge with the strong border and a handle, title "Filters", and a
 * Clear / Apply footer. Edits stay local until Apply; each opening starts
 * from the filters currently in the URL.
 */
export function FiltersSheet({ activeCount = 0 }: { activeCount?: number }) {
  const ref = useRef<HTMLDialogElement>(null);
  const [opening, setOpening] = useState(0);

  return (
    <>
      <button
        type="button"
        onClick={() => {
          setOpening((n) => n + 1);
          ref.current?.showModal();
        }}
        aria-haspopup="dialog"
        className="pressable inline-flex min-h-10 items-center gap-2 rounded-full border border-control px-4 text-[14px] font-semibold text-ink hover:border-ink"
      >
        <Icon name="filter" size={18} strokeWidth={2} />
        Filters
        {activeCount > 0 ? (
          <span className="inline-flex min-w-5 items-center justify-center rounded-full bg-brand px-1.5 text-[12px] font-bold leading-5 text-inverse">
            {activeCount}
          </span>
        ) : null}
      </button>

      <dialog
        ref={ref}
        aria-labelledby="filters-title"
        onClick={(e) => {
          if (e.target === ref.current) ref.current?.close();
        }}
        className="fixed inset-x-0 bottom-0 m-0 mt-auto max-h-[85dvh] w-full max-w-none overflow-hidden border-0 border-t border-line-strong bg-elevated p-0 text-ink open:[animation:sn-sheet-up_280ms_var(--ease-swift)] sm:inset-x-auto sm:bottom-auto sm:m-auto sm:max-w-md sm:rounded-card sm:border"
      >
        <div className="flex max-h-[85dvh] flex-col">
          <div className="flex justify-center pt-2.5 sm:hidden" aria-hidden="true">
            <span className="h-1 w-9 rounded-full bg-line-strong" />
          </div>
          <div className="flex items-center justify-between px-5 pb-2 pt-3">
            <h2 id="filters-title" className="t-display-sm text-ink">
              Filters
            </h2>
            <button type="button" onClick={() => ref.current?.close()} className={iconButtonClasses("chip")} aria-label="Close filters">
              <Icon name="close" size={20} />
            </button>
          </div>
          <div className="overflow-y-auto px-5 pt-3">
            <FilterControls key={opening} idPrefix="sheet" mode="draft" onApplied={() => ref.current?.close()} />
          </div>
        </div>
      </dialog>
    </>
  );
}

"use client";

import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { SegmentedControl, SegmentedControlItem } from "@astryxdesign/core/SegmentedControl";

export type EventView = "list" | "cards" | "table" | "chart";

/** Change the presentation while keeping the same events and filters. */
export function EventViewSwitcher({ view, hrefs }: { view: EventView; hrefs: Record<EventView, string> }) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  return <div className="mb-5 overflow-x-auto py-1" aria-busy={pending}>
    <SegmentedControl value={view} label="Event view" size="lg" isDisabled={pending} onChange={(next) => {
      if (next in hrefs) startTransition(() => router.push(hrefs[next as EventView], { scroll: false }));
    }}>
      <SegmentedControlItem value="list" label="List" />
      <SegmentedControlItem value="cards" label="Cards" />
      <SegmentedControlItem value="table" label="Table" />
      <SegmentedControlItem value="chart" label="Status chart" />
    </SegmentedControl>
  </div>;
}

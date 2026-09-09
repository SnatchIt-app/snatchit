import type { EventStatus, InventoryBatch, TicketType } from "@/lib/types";

/** Spec §7.4 — forward-only lifecycle; the UI offers only the next legal transition. */
const FORWARD: EventStatus[] = ["draft", "announced", "on_sale", "live", "completed"];

export function nextStatus(s: EventStatus): EventStatus | null {
  if (s === "cancelled") return null;
  const i = FORWARD.indexOf(s);
  return i >= 0 && i < FORWARD.length - 1 ? FORWARD[i + 1] : null;
}

export const STATUS_LABEL: Record<EventStatus, string> = {
  draft: "Draft",
  announced: "Announced",
  on_sale: "On sale",
  live: "Live",
  completed: "Completed",
  cancelled: "Cancelled",
};

export const STATUS_HELP: Record<EventStatus, string> = {
  draft: "Not visible to anyone outside your team.",
  announced: "Visible publicly, not buyable.",
  on_sale: "Buyable.",
  live: "The night itself.",
  completed: "Terminal for sales.",
  cancelled: "Cancelled. Nothing is deleted.",
};

/**
 * Spec §7.4 — `on_sale` is blocked unless ≥1 ticket type with a batch exists.
 * Returns the missing requirement by name so the UI never shows a dead button.
 */
export function publishBlocker(types: TicketType[], batches: InventoryBatch[]): string | null {
  if (types.length === 0) return "Add a ticket type before going on sale.";
  const withBatch = types.some((t) => batches.some((b) => b.ticketTypeId === t.ticketTypeId));
  if (!withBatch) return "Add an inventory release to at least one ticket type before going on sale.";
  return null;
}

/** Spec §7.3 — while draft, everything is editable; once selling, price/capacity edits are confirmed operations. */
export function editMode(s: EventStatus): "free" | "confirmed" | "locked" {
  if (s === "draft" || s === "announced") return "free";
  if (s === "on_sale" || s === "live") return "confirmed";
  return "locked";
}

export const RESALE_LABEL = {
  off: "Off",
  transfers_only: "Transfers only",
  fixed_cap: "Fixed cap",
  face_value_queue: "Face-value queue",
  buy_now: "Buy now",
  auction: "Auction",
  offer: "Offer",
} as const;

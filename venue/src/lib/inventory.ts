/**
 * Capacity truth is one number, computed (spec §2.5, C27):
 *   remaining = capacity − held − sold
 * The dashboard never offers an editable remaining and never shows a second
 * availability figure derived any other way.
 */
import type { InventoryBatch, InventoryHold, ReleaseKind, TicketType } from "@/lib/types";

export function remaining(b: Pick<InventoryBatch, "capacity" | "held" | "sold">): number {
  return Math.max(0, b.capacity - b.held - b.sold);
}

/** Spec §8.4: a capacity change may not drop below held + sold. */
export function capacityFloor(b: Pick<InventoryBatch, "held" | "sold">): number {
  return b.held + b.sold;
}

/** Spec §8.8 — two distinct states, never merged. */
export type Availability = "available" | "sold_out" | "all_held";
export function availability(b: Pick<InventoryBatch, "capacity" | "held" | "sold">): Availability {
  if (remaining(b) > 0) return "available";
  // remaining = 0: which counter consumed it?
  return b.sold >= b.capacity ? "sold_out" : "all_held";
}

export const RELEASE_LABEL: Record<ReleaseKind, string> = {
  public_sale: "Public sale",
  promoter_hold: "Promoter hold",
  comp: "Comps",
  door: "Door",
  presale: "Presale",
};

export type WarningKind = "low" | "sold_out" | "all_held" | "door_untouched" | "holds_expiring";

export type InventoryWarning = {
  kind: WarningKind;
  batchId: string;
  ticketTypeName: string;
  release: string;
  detail: string;
};

const WARNING_COPY: Record<WarningKind, string> = {
  low: "Low",
  sold_out: "Sold out",
  all_held: "All held, none sold",
  door_untouched: "Door stock untouched",
  holds_expiring: "Holds expiring",
};
export function warningLabel(k: WarningKind): string {
  return WARNING_COPY[k];
}

/**
 * Spec §6.1 zone 6 — one row per (batch, condition). The batch's ticket type
 * and release are always named. `sessionLive` gates the door-stock rule; `now`
 * is injected so the rule is testable.
 */
export function inventoryWarnings(
  batches: InventoryBatch[],
  types: TicketType[],
  holds: InventoryHold[],
  opts: { liveSessionIds: Set<string>; now: Date },
): InventoryWarning[] {
  const typeName = (id: string) => types.find((t) => t.ticketTypeId === id)?.name ?? "Unknown type";
  const out: InventoryWarning[] = [];
  for (const b of batches) {
    const base = { batchId: b.batchId, ticketTypeName: typeName(b.ticketTypeId), release: RELEASE_LABEL[b.releaseKind] };
    const rem = remaining(b);
    const av = availability(b);
    if (av === "sold_out") out.push({ ...base, kind: "sold_out", detail: `${b.sold} of ${b.capacity} sold` });
    else if (av === "all_held") out.push({ ...base, kind: "all_held", detail: `${b.held} held, ${b.sold} sold — release holds to put tickets back on sale` });
    else if (rem < b.lowThreshold) out.push({ ...base, kind: "low", detail: `${rem} left (threshold ${b.lowThreshold})` });
    if (b.releaseKind === "door" && b.sold === 0 && opts.liveSessionIds.has(b.sessionId)) {
      out.push({ ...base, kind: "door_untouched", detail: `${b.capacity} held back for the door, none sold yet` });
    }
    const expiring = holds.filter(
      (h) => h.batchId === b.batchId && h.status === "active" && new Date(h.expiresAt).getTime() - opts.now.getTime() < 60 * 60 * 1000 && new Date(h.expiresAt).getTime() > opts.now.getTime(),
    );
    if (expiring.length > 0) {
      const qty = expiring.reduce((n, h) => n + h.quantity, 0);
      out.push({ ...base, kind: "holds_expiring", detail: `${expiring.length} hold${expiring.length === 1 ? "" : "s"} (${qty} tickets) expire within the hour` });
    }
  }
  return out;
}

/** Per-ticket-type roll-up across its batches for one session (never an event-level capacity — spec §7.6). */
export function sessionTotals(batches: InventoryBatch[], ticketTypeId: string, sessionId: string) {
  const mine = batches.filter((b) => b.ticketTypeId === ticketTypeId && b.sessionId === sessionId);
  const capacity = mine.reduce((n, b) => n + b.capacity, 0);
  const held = mine.reduce((n, b) => n + b.held, 0);
  const sold = mine.reduce((n, b) => n + b.sold, 0);
  return { capacity, held, sold, remaining: Math.max(0, capacity - held - sold) };
}

/** Spec §8.5 — "Held back for the door: 40 of 500" per session. */
export function doorHoldback(batches: InventoryBatch[], sessionId: string): { door: number; total: number } {
  const mine = batches.filter((b) => b.sessionId === sessionId);
  return { door: mine.filter((b) => b.releaseKind === "door").reduce((n, b) => n + b.capacity, 0), total: mine.reduce((n, b) => n + b.capacity, 0) };
}

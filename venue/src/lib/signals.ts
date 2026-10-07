/**
 * "What needs me now?" — the signals behind the Tonight overview.
 *
 * Audit DASHBOARD_USABILITY_AUDIT_D_20260917 §W1: the dashboard had no answer
 * to that question, so a manager landing at 9 PM on a show night could not see
 * that a scanner had stopped syncing or that holds were about to expire.
 *
 * Rules this file keeps to:
 *   - Every signal is computed from the same reads the surfaces use. Nothing is
 *     invented and nothing is a rolling total spread across a period.
 *   - Every signal says, in a manager's words, what it is, what happens if it
 *     is ignored, and exactly one next action.
 *   - A check that finds nothing is not silence: it is counted as clear, so an
 *     empty overview means "looked and found nothing", not "nothing ran".
 */
import { manifestAge } from "@/lib/door";
import { publishBlocker } from "@/lib/events";
import { inventoryWarnings, remaining } from "@/lib/inventory";
import type { Event, EventSession, FlagRow, InventoryBatch, InventoryHold, ScanDevice, TicketType } from "@/lib/types";

/** Ordered worst-first; the overview renders them in this order. */
export const SEVERITIES = ["act_now", "soon", "worth_knowing"] as const;
export type Severity = (typeof SEVERITIES)[number];

export const SEVERITY_LABEL: Record<Severity, string> = {
  act_now: "Needs you now",
  soon: "Before doors",
  worth_knowing: "Worth knowing",
};

export type Signal = {
  id: string;
  severity: Severity;
  /** Plain sentence naming the thing. No table names, no jargon. */
  title: string;
  /** What happens if it is left alone. */
  consequence: string;
  /** Exactly one next step. */
  action: { label: string; href: string };
};

/** A check that ran and found nothing — proof the overview looked. */
export type ClearCheck = { id: string; label: string };

export type SignalSet = { signals: Signal[]; clear: ClearCheck[] };

export type SignalInput = {
  events: Event[];
  types: TicketType[];
  batches: InventoryBatch[];
  holds: InventoryHold[];
  devices: ScanDevice[];
  flags: FlagRow[];
  tonight: { event: Event; session: EventSession }[];
  now: Date;
  basePath: string;
  /** Applies the current role/state to a link so the walk stays in one persona. */
  link: (href: string) => string;
};

const RANK: Record<Severity, number> = { act_now: 0, soon: 1, worth_knowing: 2 };

export function buildSignals(input: SignalInput): SignalSet {
  const { events, types, batches, holds, devices, flags, tonight, now, basePath, link } = input;
  const signals: Signal[] = [];
  const clear: ClearCheck[] = [];
  const add = (s: Signal) => signals.push(s);
  const ok = (id: string, label: string) => clear.push({ id, label });

  const eventHref = (eventId: string, tail = "") => link(`${basePath}/events/${eventId}${tail}`);
  const liveSessionIds = new Set(events.flatMap((e) => e.sessions.filter((s) => s.status === "live").map((s) => s.sessionId)));
  const sellingIds = new Set(events.filter((e) => e.status !== "completed" && e.status !== "cancelled").map((e) => e.eventId));
  const eventOfBatch = (batchId: string) => {
    const b = batches.find((x) => x.batchId === batchId);
    return b ? types.find((t) => t.ticketTypeId === b.ticketTypeId)?.eventId ?? null : null;
  };
  const titleOf = (eventId: string | null) => events.find((e) => e.eventId === eventId)?.title ?? "an event";

  // 1. A scanner that stopped talking to us. Worst case: a queue at the door.
  const stale = devices.filter((d) => manifestAge(d, now).stale || !d.online);
  if (stale.length > 0 && tonight.length > 0) {
    const d = stale[0];
    const mins = manifestAge(d, now).minutes;
    add({
      id: "device_stale",
      severity: "act_now",
      title: stale.length === 1 ? `${d.label} last synced ${mins} minutes ago` : `${stale.length} scanners are out of sync — longest ${mins} minutes`,
      consequence: "It still admits people from the list it already has, but tickets sold or refunded since then are not on that list. Anyone holding one gets turned away.",
      action: { label: "Go to check-in", href: eventHref(tonight[0].event.eventId, "/door") },
    });
  } else if (devices.length > 0) {
    ok("device_stale", `${devices.length} scanner${devices.length === 1 ? "" : "s"} in sync`);
  }

  // 2. Flagged scans nobody has looked at. Someone is standing at the door.
  const openFlags = flags.filter((f) => !f.escalated);
  if (openFlags.length > 0 && tonight.length > 0) {
    add({
      id: "flags_open",
      severity: "act_now",
      title: `${openFlags.length} scan${openFlags.length === 1 ? "" : "s"} flagged at the door and not yet reviewed`,
      consequence: "Each one is a person who was refused entry. Until someone looks, they are waiting outside with a ticket they believe is valid.",
      action: { label: "Review the flagged scans", href: eventHref(tonight[0].event.eventId, "/door#flags") },
    });
  } else if (tonight.length > 0) {
    ok("flags_open", "No flagged scans waiting");
  }

  // 3. Holds about to expire — seats that silently come back on sale.
  const warnings = inventoryWarnings(batches, types, holds, { liveSessionIds, now }).filter((w) => {
    const id = eventOfBatch(w.batchId);
    return id !== null && sellingIds.has(id);
  });
  const expiring = warnings.filter((w) => w.kind === "holds_expiring");
  if (expiring.length > 0) {
    const eid = eventOfBatch(expiring[0].batchId);
    add({
      id: "holds_expiring",
      severity: "act_now",
      title: `Holds on ${expiring[0].ticketTypeName} expire within the hour`,
      consequence: "When they expire the seats go back on public sale by themselves. If they were being held for someone, that is the moment you lose them.",
      action: { label: "Go to tickets", href: eventHref(eid ?? "", "/inventory") },
    });
  } else {
    ok("holds_expiring", "No holds expiring in the next hour");
  }

  // 4. Nothing left to sell on something still selling.
  const soldOut = warnings.filter((w) => w.kind === "sold_out");
  if (soldOut.length > 0) {
    const eid = eventOfBatch(soldOut[0].batchId);
    add({
      id: "sold_out",
      severity: "soon",
      title: `${soldOut[0].ticketTypeName} for ${titleOf(eid)} is sold out`,
      consequence: "People are still arriving at a page with nothing to buy. Putting more tickets on sale is the only way to sell more; nothing does it automatically.",
      action: { label: "Go to tickets", href: eventHref(eid ?? "", "/inventory") },
    });
  }
  const low = warnings.filter((w) => w.kind === "low");
  if (low.length > 0) {
    const eid = eventOfBatch(low[0].batchId);
    add({
      id: "low_stock",
      severity: "soon",
      title: `${low[0].ticketTypeName} is nearly gone — ${low[0].detail}`,
      consequence: "At this rate it sells out before doors, and the next person to look sees nothing available.",
      action: { label: "Go to tickets", href: eventHref(eid ?? "", "/inventory") },
    });
  }
  if (soldOut.length === 0 && low.length === 0) ok("stock", "Every release still has tickets");

  // 5. Door stock nobody has touched — the box office has nothing to sell late.
  const untouched = warnings.filter((w) => w.kind === "door_untouched");
  if (untouched.length > 0) {
    const eid = eventOfBatch(untouched[0].batchId);
    add({
      id: "door_untouched",
      severity: "worth_knowing",
      title: `Door stock for ${titleOf(eid)} has not sold a single ticket`,
      consequence: "Those seats were deliberately kept back off the internet for walk-ups. If the box office is not selling them, they stay empty.",
      action: { label: "Go to tickets", href: eventHref(eid ?? "", "/inventory") },
    });
  }

  // 6. An event that cannot go on sale, and the reason why.
  for (const e of events) {
    if (e.status !== "announced") continue;
    const mine = types.filter((t) => t.eventId === e.eventId);
    const blocker = publishBlocker(
      mine,
      batches.filter((b) => mine.some((t) => t.ticketTypeId === b.ticketTypeId)),
    );
    if (blocker) {
      add({
        id: `blocked_${e.eventId}`,
        severity: "soon",
        title: `${e.title} cannot go on sale yet`,
        consequence: `${blocker} Until that is done the event is announced but nobody can buy a ticket.`,
        action: { label: "Go to the event", href: eventHref(e.eventId) },
      });
    }
  }

  // 7. Drafts are not a problem, but a manager should know they are not selling.
  const drafts = events.filter((e) => e.status === "draft");
  if (drafts.length > 0) {
    add({
      id: "drafts",
      severity: "worth_knowing",
      title: `${drafts.length} event${drafts.length === 1 ? " is" : "s are"} still a draft`,
      consequence: "A draft is visible only to your staff. It is not announced and it is not selling.",
      action: { label: drafts.length === 1 ? `Go to ${drafts[0].title}` : "See all events", href: drafts.length === 1 ? eventHref(drafts[0].eventId) : link(`${basePath}/events`) },
    });
  }

  signals.sort((a, b) => RANK[a.severity] - RANK[b.severity]);
  return { signals, clear };
}

/** Tonight's door, in three numbers a manager reads without a legend. */
export type DoorSummary = {
  eventId: string;
  eventTitle: string;
  sessionLabel: string | null;
  doorsAt: string | null;
  startsAt: string;
  admitted: number;
  expected: number;
  devicesOnline: number;
  devicesTotal: number;
};

export function doorSummary(
  tonight: { event: Event; session: EventSession }[],
  counters: { admitted: number; issued: number } | null,
  devices: ScanDevice[],
): DoorSummary | null {
  if (tonight.length === 0 || !counters) return null;
  const { event, session } = tonight[0];
  return {
    eventId: event.eventId,
    eventTitle: event.title,
    sessionLabel: session.label,
    doorsAt: session.doorsAt,
    startsAt: session.startsAt,
    admitted: counters.admitted,
    expected: counters.issued,
    devicesOnline: devices.filter((d) => d.online).length,
    devicesTotal: devices.length,
  };
}

/** Seats still buyable across everything still selling — one number, one meaning. */
export function stillAvailable(events: Event[], types: TicketType[], batches: InventoryBatch[]): number {
  const selling = new Set(events.filter((e) => e.status === "on_sale" || e.status === "live").map((e) => e.eventId));
  const mine = new Set(types.filter((t) => selling.has(t.eventId)).map((t) => t.ticketTypeId));
  return batches.filter((b) => mine.has(b.ticketTypeId)).reduce((n, b) => n + remaining(b), 0);
}

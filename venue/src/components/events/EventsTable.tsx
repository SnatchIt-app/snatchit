import { EventArt } from "@/components/ui/EventArt";
import Link from "next/link";
import { RESALE_LABEL } from "@/lib/events";
import { sessionTotals } from "@/lib/inventory";
import { inventoryWarnings } from "@/lib/inventory";
import { venueDate } from "@/lib/format";
import { withPreview, type PreviewContext } from "@/lib/preview";
import { canEditEvents, canReadResalePolicy, showCounters } from "@/lib/roles";
import type { Event, InventoryBatch, InventoryHold, TicketType } from "@/lib/types";
import { Chip, StatusPill } from "@/components/ui/Bits";
import { EmptyState, PartialCell } from "@/components/ui/State";
import { Row, Rows } from "@/components/ui/Page";

/**
 * Spec §7.1 — columns: title · venue · next session date · status · sold / capacity · resale mode · promoter count.
 * Filters (closed set): status, date range; search: title substring. Sort default: next session.
 */
export function EventsTable({
  events,
  batches,
  types,
  holds,
  ctx,
  basePath,
  timeZone,
  now,
  filter,
}: {
  events: Event[];
  batches: InventoryBatch[];
  types: TicketType[];
  holds: InventoryHold[];
  ctx: PreviewContext;
  basePath: string;
  timeZone: string;
  now: Date;
  filter: { status?: string; q?: string };
}) {
  const counters = showCounters(ctx.role, ctx);
  const liveIds = new Set(events.flatMap((e) => e.sessions.filter((s) => s.status === "live").map((s) => s.sessionId)));
  // Warnings only matter for events that can still sell (spec §6.1 zone 6 is about tonight and upcoming).
  const sellingIds = new Set(events.filter((e) => e.status !== "completed" && e.status !== "cancelled").map((e) => e.eventId));
  const warnEventIds = new Set(
    inventoryWarnings(batches, types, holds, { liveSessionIds: liveIds, now })
      .map((w) => types.find((t) => t.ticketTypeId === batches.find((b) => b.batchId === w.batchId)?.ticketTypeId)?.eventId)
      .filter((id) => id && sellingIds.has(id)),
  );

  let rows = events;
  if (filter.status) rows = rows.filter((e) => e.status === filter.status);
  if (filter.q) rows = rows.filter((e) => e.title.toLowerCase().includes(filter.q!.toLowerCase()));
  const nextSession = (e: Event) => [...e.sessions].filter((s) => s.status !== "cancelled").sort((a, b) => a.startsAt.localeCompare(b.startsAt)).find((s) => new Date(s.startsAt) >= new Date(now.getTime() - 12 * 3600 * 1000)) ?? e.sessions[0];
  rows = [...rows].sort((a, b) => (nextSession(a)?.startsAt ?? "").localeCompare(nextSession(b)?.startsAt ?? ""));

  const soldCap = (e: Event) => {
    const s = nextSession(e);
    if (!s) return null;
    const mine = types.filter((t) => t.eventId === e.eventId);
    if (mine.length === 0) return { sold: 0, capacity: 0 };
    const tot = mine.map((t) => sessionTotals(batches, t.ticketTypeId, s.sessionId));
    return { sold: tot.reduce((n, x) => n + x.sold, 0), capacity: tot.reduce((n, x) => n + x.capacity, 0) };
  };

  // Audit §X2 — order these by cause, never by count. A manager who filtered to
  // nothing must never be told their events are gone, and must never be offered
  // a Create button that would duplicate an event they already have.
  const filtered = Boolean(filter.status || filter.q);
  if (rows.length === 0 && filtered) {
    return (
      <EmptyState title={`No events match these filters. Your ${events.length} ${events.length === 1 ? "event is" : "events are"} still here.`}>
        <Link className="btn btn-ghost btn-sm" href={withPreview(`${basePath}/events`, ctx)}>
          Clear filters
        </Link>
      </EmptyState>
    );
  }
  if (events.length === 0) {
    return (
      <EmptyState title="No events yet.">
        {canEditEvents(ctx.role) ? (
          <Link className="btn btn-primary btn-sm" href={withPreview(`${basePath}/events/new`, ctx)}>
            Create event
          </Link>
        ) : null}
      </EmptyState>
    );
  }

  return (
    /*
      One list, not a desktop table plus a separate phone card deck. The table
      carried two columns that could never say anything useful here: "Venue",
      which is the same venue on every row, and "Promoters", which this data
      source cannot read and so rendered a dash on every row. Resale mode moved
      into the row's meta line for the roles that can see it.
    */
    <Rows>
      {rows.map((e) => {
        const s = nextSession(e);
        const sc = soldCap(e);
        const sales = sc && sc.capacity > 0 ? (counters ? `${sc.sold} of ${sc.capacity} sold` : sc.capacity - sc.sold > 0 ? `${sc.capacity - sc.sold} still available` : "None available") : null;
        return (
          <Row
            key={e.eventId}
            title={e.title}
            serif
            leading={<EventArt title={e.title} variant="thumb" className="h-14 w-[4.5rem] overflow-hidden rounded-[6px]" />}
            href={withPreview(`${basePath}/events/${e.eventId}`, ctx)}
            badge={
              <>
                <StatusPill status={e.status} />
                {warnEventIds.has(e.eventId) ? <Chip tone="warning">Needs attention</Chip> : null}
              </>
            }
            meta={
              <>
                {s ? venueDate(s.startsAt, timeZone) : "No date set"}
                {s?.label ? ` · ${s.label}` : ""}
                {canReadResalePolicy(ctx.role) ? ` · ${RESALE_LABEL[e.resaleMode]}` : ""}
              </>
            }
            right={sales ? <span className="tabular-nums text-[0.875rem] text-muted">{sales}</span> : <PartialCell why="No releases yet" />}
          />
        );
      })}
    </Rows>
  );
}

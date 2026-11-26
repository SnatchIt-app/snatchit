import { Card } from "@astryxdesign/core/Card";
import { EventArt } from "@/components/ui/EventArt";
import Link from "next/link";
import { resaleLabel } from "@/lib/events";
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
  view = "list",
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
  view?: "list" | "cards" | "table" | "chart";
}) {
  const counters = showCounters(ctx.role, ctx);
  const liveIds = new Set(events.flatMap((e) => e.sessions.filter((s) => s.status === "live").map((s) => s.sessionId)));
  // Warnings only matter for events that can still sell (spec §6.1 zone 6 is about tonight and upcoming).
  const sellingIds = new Set(events.filter((e) => e.status !== "completed" && e.status !== "cancelled").map((e) => e.eventId));
  // Warnings are computed from sold/held counts; where those aren't readable (database mode) there are none to show.
  const warnEventIds = new Set(
    (counters ? inventoryWarnings(batches, types, holds, { liveSessionIds: liveIds, now }) : [])
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
        {/* Database mode wires no write path (ctx.writesEnabled false): offering Create would lead to a dead end. */}
        {canEditEvents(ctx.role) && ctx.writesEnabled !== false ? (
          <Link className="btn btn-primary btn-sm" href={withPreview(`${basePath}/events/new`, ctx)}>
            Create event
          </Link>
        ) : null}
      </EmptyState>
    );
  }

  if (view === "chart") {
    const statuses = [...new Set(rows.map((event) => event.status))];
    return <section className="py-5" aria-labelledby="event-status-chart">
      <h2 id="event-status-chart" className="text-lg font-semibold">Events by status</h2>
      <p className="mt-1 text-sm text-muted">{rows.length} matching events. Current status, across all dates.</p>
      <div className="my-6 space-y-4" aria-hidden="true">{statuses.map((status) => {
        const count = rows.filter((event) => event.status === status).length;
        return <div key={status} className="grid grid-cols-[6rem_1fr_2rem] items-center gap-3 text-sm"><span className="capitalize">{status.replace("_", " ")}</span><div className="h-7 rounded-md bg-black/5"><div className="h-full rounded-md bg-[#514432]" style={{ width: `${count / rows.length * 100}%` }} /></div><span className="text-right tabular-nums">{count}</span></div>;
      })}</div>
      <table className="w-full text-left text-sm"><caption className="sr-only">Event status counts for the current filters</caption><thead><tr className="border-b border-line"><th scope="col" className="py-2">Status</th><th scope="col" className="py-2 text-right">Events</th></tr></thead><tbody>{statuses.map((status) => <tr key={status} className="border-b border-line"><th scope="row" className="py-3 font-normal"><StatusPill status={status} /></th><td className="py-3 text-right tabular-nums">{rows.filter((event) => event.status === status).length}</td></tr>)}</tbody></table>
    </section>;
  }

  if (view === "cards") return <div className="grid gap-4 py-4 sm:grid-cols-2 xl:grid-cols-3">{rows.map((event) => {
    const session = nextSession(event);
    return <Card key={event.eventId} padding={4} className="h-full"><Link href={withPreview(`${basePath}/events/${event.eventId}`, ctx)} className="group block rounded-xl focus-visible:outline-2 focus-visible:outline-offset-4">
      <EventArt title={event.title} variant="thumb" className="mb-4 h-32 w-full overflow-hidden rounded-xl" />
      <StatusPill status={event.status} /><h2 className="serif mt-3 text-2xl group-hover:underline">{event.title}</h2>
      <p className="mt-2 text-sm text-muted">{session ? venueDate(session.startsAt, event.timeZone ?? timeZone) : "No date set"}</p>
      {warnEventIds.has(event.eventId) ? <p className="mt-3 text-sm text-warning">Needs attention</p> : null}
    </Link></Card>;
  })}</div>;

  if (view === "table") return <div className="overflow-x-auto py-4"><table className="w-full min-w-[35rem] text-left text-sm"><caption className="sr-only">Events matching the current filters</caption><thead><tr className="border-b border-line text-muted">{["Event", "Next date", "Status", "Ticket availability"].map((label) => <th key={label} scope="col" className="px-3 py-3 font-medium">{label}</th>)}</tr></thead><tbody>{rows.map((event) => {
    const session = nextSession(event); const sc = soldCap(event);
    return <tr key={event.eventId} className="border-b border-line"><th scope="row" className="px-3 py-4 font-medium"><Link className="link" href={withPreview(`${basePath}/events/${event.eventId}`, ctx)}>{event.title}</Link></th><td className="px-3 py-4">{session ? venueDate(session.startsAt, event.timeZone ?? timeZone) : "No date set"}</td><td className="px-3 py-4"><StatusPill status={event.status} /></td><td className="px-3 py-4 tabular-nums">{sc && sc.capacity > 0 ? counters ? `${sc.sold} of ${sc.capacity} sold` : `${Math.max(0, sc.capacity - sc.sold)} remaining, all releases` : "No releases yet"}</td></tr>;
  })}</tbody></table></div>;

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
        const sales = sc && sc.capacity > 0 ? (counters ? `${sc.sold} of ${sc.capacity} sold` : sc.capacity - sc.sold > 0 ? `${sc.capacity - sc.sold} remaining, all releases` : "None remaining, all releases") : null;
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
                {s ? venueDate(s.startsAt, e.timeZone ?? timeZone) : "No date set"}
                {s?.label ? ` · ${s.label}` : ""}
                {canReadResalePolicy(ctx.role) ? ` · ${resaleLabel(e)}` : ""}
              </>
            }
            right={sales ? <span className="tabular-nums text-[0.875rem] text-muted">{sales}</span> : <PartialCell why="No releases yet" />}
          />
        );
      })}
    </Rows>
  );
}

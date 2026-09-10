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
  venueName,
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
  venueName: string;
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
  if (rows.length === 0) {
    return (
      <EmptyState title="No events match these filters.">
        <Link className="btn btn-ghost btn-sm" href={withPreview(`${basePath}/events`, ctx)}>
          Clear filters
        </Link>
      </EmptyState>
    );
  }

  return (
    <>
      {/* xl / lg: table */}
      <div className="hidden overflow-x-auto md:block">
        <table className="data-table">
          <thead>
            <tr>
              <th>Title</th>
              <th className="hidden xl:table-cell">Venue</th>
              <th>Next session</th>
              <th>Status</th>
              <th className="num">Sold / capacity</th>
              {canReadResalePolicy(ctx.role) ? <th className="hidden lg:table-cell">Resale</th> : null}
              <th className="num hidden lg:table-cell">Promoters</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((e) => {
              const s = nextSession(e);
              const sc = soldCap(e);
              return (
                <tr key={e.eventId}>
                  <td>
                    <Link className="link" href={withPreview(`${basePath}/events/${e.eventId}`, ctx)}>
                      {e.title}
                    </Link>
                    {warnEventIds.has(e.eventId) ? (
                      <span className="ml-2">
                        <Chip tone="warning">Inventory warning</Chip>
                      </span>
                    ) : null}
                  </td>
                  <td className="hidden xl:table-cell text-muted">{venueName}</td>
                  <td className="whitespace-nowrap">
                    {s ? venueDate(s.startsAt, timeZone) : "—"}
                    {s?.label ? <span className="text-dim"> · {s.label}</span> : null}
                  </td>
                  <td>
                    <StatusPill status={e.status} />
                  </td>
                  <td className="num">{sc && sc.capacity > 0 ? (counters ? `${sc.sold} / ${sc.capacity}` : sc.capacity - sc.sold > 0 ? `${sc.capacity - sc.sold} available` : "None available") : <PartialCell why={sc ? "No releases yet" : "Sold/capacity unavailable"} />}</td>
                  {canReadResalePolicy(ctx.role) ? <td className="hidden lg:table-cell">{RESALE_LABEL[e.resaleMode]}</td> : null}
                  <td className="num hidden lg:table-cell">{e.promoterCount ?? <PartialCell why="Promoters are not readable from this data source yet" />}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      {/* sm: summary cards (events list is not a mobile-critical surface — read-only summary, spec §3.2) */}
      <ul className="space-y-2 md:hidden">
        {rows.map((e) => {
          const s = nextSession(e);
          const sc = soldCap(e);
          return (
            <li key={e.eventId} className="border border-line-neutral p-3">
              <div className="flex items-start justify-between gap-2">
                <Link className="link font-bold" href={withPreview(`${basePath}/events/${e.eventId}`, ctx)}>
                  {e.title}
                </Link>
                <StatusPill status={e.status} />
              </div>
              <p className="mt-1 text-xs text-muted">
                {s ? venueDate(s.startsAt, timeZone) : "—"} · {sc && sc.capacity > 0 ? (counters ? `${sc.sold} / ${sc.capacity} sold` : `${Math.max(0, sc.capacity - sc.sold)} available`) : "no releases yet"}
              </p>
            </li>
          );
        })}
      </ul>
    </>
  );
}

import Link from "next/link";
import { VENUE } from "@/fixtures/venue";
import { listBatches, listEvents, listHolds, listTicketTypes, PreviewReadError } from "@/lib/data";
import { readPage, type PageParams } from "@/lib/page";
import { withPreview, type SearchParams } from "@/lib/preview";
import { canEditEvents, canReadEvents } from "@/lib/roles";
import type { Event, InventoryBatch, InventoryHold, TicketType } from "@/lib/types";
import { EventsTable } from "@/components/events/EventsTable";
import { PreviewOutcome, Shell } from "@/components/shell/Shell";
import { DeniedState, ErrorState, Skeleton } from "@/components/ui/State";
import { PreviewHidden } from "@/components/events/EventSetup";

export const metadata = { title: "Events" };

type Loaded = { events: Event[]; types: TicketType[]; batches: InventoryBatch[]; holds: InventoryHold[] };

export default async function EventsPage({ params, searchParams }: { params: Promise<PageParams>; searchParams: Promise<SearchParams> }) {
  const p = await readPage(params, searchParams);
  if (!p.scope.ok) return <DeniedState />;
  const ctx = p.ctx;
  const basePath = p.scope.basePath;
  const readable = ctx.state !== "denied" && canReadEvents(ctx.role);

  // Reads happen here, outside JSX, so a simulated read failure renders the error card (spec §18).
  let loaded: Loaded | null = null;
  let failedRead: string | null = null;
  if (readable && ctx.state !== "loading") {
    try {
      const events = listEvents(ctx.state);
      loaded = {
        events,
        types: events.flatMap((e) => listTicketTypes("live", e.eventId)),
        batches: events.flatMap((e) => listBatches("live", e.eventId)),
        holds: events.flatMap((e) => listHolds("live", e.eventId)),
      };
    } catch (e) {
      failedRead = e instanceof PreviewReadError ? e.read : "catalog.event";
    }
  }

  return (
    <Shell ctx={ctx} event={null} active="events">
      <PreviewOutcome did={p.first("did")} />
      <header className="mb-4 flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="eyebrow text-dim">{VENUE.name}</p>
          <h1 className="text-2xl font-bold">Events</h1>
        </div>
        {readable && canEditEvents(ctx.role) ? (
          <Link className="btn btn-primary btn-sm" href={withPreview(`${basePath}/events/new`, ctx)}>
            Create event
          </Link>
        ) : null}
      </header>
      {readable ? (
        <form method="get" className="mb-3 flex flex-wrap gap-2">
          <PreviewHidden ctx={ctx} />
          <input className="field !w-auto" name="q" placeholder="Search title" defaultValue={p.first("q") ?? ""} aria-label="Search events" />
          <select className="field !w-auto" name="status" defaultValue={p.first("status") ?? ""} aria-label="Status filter">
            <option value="">Any status</option>
            {["draft", "announced", "on_sale", "live", "completed", "cancelled"].map((s) => (
              <option key={s} value={s}>
                {s.replace("_", " ")}
              </option>
            ))}
          </select>
          <button className="btn btn-ghost btn-sm" type="submit">
            Filter
          </button>
        </form>
      ) : null}
      {!readable ? (
        <DeniedState />
      ) : ctx.state === "loading" ? (
        <Skeleton rows={7} />
      ) : failedRead || !loaded ? (
        <ErrorState read={failedRead ?? "catalog.event"} retryHref={withPreview(`${basePath}/events`, ctx)} />
      ) : (
        <EventsTable
          events={loaded.events}
          batches={loaded.batches}
          types={loaded.types}
          holds={loaded.holds}
          ctx={ctx}
          basePath={basePath}
          venueName={VENUE.name}
          timeZone={p.timeZone}
          now={p.now}
          filter={{ status: ctx.state === "nodata" ? "zzz" : p.first("status"), q: p.first("q") }}
        />
      )}
    </Shell>
  );
}

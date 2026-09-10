import Link from "next/link";
import { VENUE } from "@/fixtures/venue";
import { listBatches, listEvents, listHolds, listTicketTypes, PreviewReadError } from "@/lib/data";
import { dbListBatches, dbListEvents, dbListTicketTypes } from "@/lib/db/adapters";
import type { ReadFailure } from "@/lib/db/read-result";
import { readPage, type PageParams } from "@/lib/page";
import { EntryGate } from "@/components/ui/EntryGate";
import { withPreview, type SearchParams } from "@/lib/preview";
import { canEditEvents, canReadEvents } from "@/lib/roles";
import type { Event, InventoryBatch, InventoryHold, TicketType } from "@/lib/types";
import { EventsTable } from "@/components/events/EventsTable";
import { PreviewOutcome, Shell } from "@/components/shell/Shell";
import { DataSourceError } from "@/components/ui/DataSourceError";
import { DeniedState, ErrorState, Skeleton } from "@/components/ui/State";
import { PreviewHidden } from "@/components/events/EventSetup";

export const metadata = { title: "Events" };
export const dynamic = "force-dynamic";

type Loaded = { events: Event[]; types: TicketType[]; batches: InventoryBatch[]; holds: InventoryHold[] };

export default async function EventsPage({ params, searchParams }: { params: Promise<PageParams>; searchParams: Promise<SearchParams> }) {
  const p = await readPage(params, searchParams);
  if (!p.scope.ok) return <DeniedState />;
  const ctx = p.ctx;
  const { basePath, venueId } = p.scope;
  const readable = ctx.state !== "denied" && canReadEvents(ctx.role);

  let loaded: Loaded | null = null;
  let failedRead: string | null = null;
  let dbFailure: ReadFailure | null = null;

  const entryOpen = p.entry.kind === "fixtures" || p.entry.kind === "ok";
  if (readable && ctx.state !== "loading" && entryOpen) {
    if (ctx.source === "database") {
      // Reads run as the signed-in user; RLS on the base tables is the only scoping.
      {
        const ev = await dbListEvents(venueId);
        if (!ev.ok) dbFailure = ev;
        else {
          const types: TicketType[] = [];
          const batches: InventoryBatch[] = [];
          for (const e of ev.data) {
            const t = await dbListTicketTypes(e.eventId);
            if (!t.ok) {
              dbFailure = t;
              break;
            }
            const b = await dbListBatches(e.eventId);
            if (!b.ok) {
              dbFailure = b;
              break;
            }
            types.push(...t.data);
            batches.push(...b.data);
          }
          if (!dbFailure) loaded = { events: ctx.state === "empty" ? [] : ev.data, types, batches, holds: [] };
        }
      }
    } else {
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
  }

  const venueName = ctx.source === "database" ? "Venue" : VENUE.name;
  return (
    <Shell ctx={ctx} event={null} active="events" signedInAs={p.signedInAs}>
      {ctx.source === "fixtures" ? <PreviewOutcome did={p.first("did")} /> : null}
      <header className="mb-4 flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="eyebrow text-dim">{venueName}</p>
          <h1 className="text-2xl font-bold">Events</h1>
        </div>
        {readable && entryOpen && canEditEvents(ctx.role) && ctx.writesEnabled !== false ? (
          <Link className="btn btn-primary btn-sm" href={withPreview(`${basePath}/events/new`, ctx)}>
            Create event
          </Link>
        ) : null}
      </header>
      {readable && entryOpen ? (
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
      {!entryOpen ? (
        <EntryGate entry={p.entry} loginHref={`/login?next=${encodeURIComponent(withPreview(`${basePath}/events`, ctx))}`} retryHref={withPreview(`${basePath}/events`, ctx)} />
      ) : !readable ? (
        <DeniedState />
      ) : ctx.state === "loading" ? (
        <Skeleton rows={7} />
      ) : dbFailure ? (
        <DataSourceError failure={dbFailure} loginHref={`/login?next=${encodeURIComponent(withPreview(`${basePath}/events`, ctx))}`} retryHref={withPreview(`${basePath}/events`, ctx)} />
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
          venueName={venueName}
          timeZone={p.timeZone}
          now={p.now}
          filter={{ status: ctx.state === "nodata" ? "zzz" : p.first("status"), q: p.first("q") }}
        />
      )}
    </Shell>
  );
}

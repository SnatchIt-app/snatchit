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
import { PRINCIPAL_LABEL } from "@/lib/roles";

export const metadata = { title: "Events" };
export const dynamic = "force-dynamic";

type Loaded = { events: Event[]; types: TicketType[]; batches: InventoryBatch[]; holds: InventoryHold[] };

export default async function EventsPage({ params, searchParams }: { params: Promise<PageParams>; searchParams: Promise<SearchParams> }) {
  const p = await readPage(params, searchParams);
  if (!p.scope.ok) return <DeniedState surface="This venue" reason="This account holds no role at the venue in this link." />;
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
      <header className="enter mb-8 flex flex-wrap items-end justify-between gap-x-8 gap-y-5">
        <div className="min-w-0">
          <p className="eyebrow-caps">{venueName}</p>
          <h1 className="title-page mt-3">Events</h1>
          <p className="mt-3 max-w-2xl text-[0.9375rem] leading-relaxed text-muted">Every event at this venue, the next date first. Open one to set it up, sell it and run its door.</p>
        </div>
        {readable && entryOpen && canEditEvents(ctx.role) && ctx.writesEnabled !== false ? (
          <Link className="btn btn-primary btn-lg" href={withPreview(`${basePath}/events/new`, ctx)}>
            Create event
          </Link>
        ) : null}
      </header>
      <section aria-label="Events" className="panel enter-2 px-5 pb-2 pt-4 md:px-6">
      {readable && entryOpen ? (
        <form method="get" role="search" className="mb-3 flex flex-wrap gap-2">
          <PreviewHidden ctx={ctx} />
          <label className="search-pill min-w-[14rem] flex-1 md:max-w-sm">
            <span className="sr-only">Search events</span>
            <svg aria-hidden="true" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" className="text-dim">
              <path d="M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16zM21 21l-4.3-4.3" />
            </svg>
            <input name="q" type="search" placeholder="Search title" defaultValue={p.first("q") ?? ""} />
          </label>
          <select className="field !w-auto" name="status" defaultValue={p.first("status") ?? ""} aria-label="Status filter">
            <option value="">Any status</option>
            {["draft", "announced", "on_sale", "live", "completed", "cancelled"].map((s) => (
              <option key={s} value={s}>
                {s.replace("_", " ")}
              </option>
            ))}
          </select>
          <button className="btn btn-ghost" type="submit">
            Filter
          </button>
        </form>
      ) : null}
      {!entryOpen ? (
        <EntryGate entry={p.entry} loginHref={`/login?next=${encodeURIComponent(withPreview(`${basePath}/events`, ctx))}`} retryHref={withPreview(`${basePath}/events`, ctx)} />
      ) : !readable ? (
        <DeniedState surface="The events list" roleLabel={PRINCIPAL_LABEL[ctx.role]} />
      ) : ctx.state === "loading" ? (
        <Skeleton rows={7} />
      ) : dbFailure ? (
        <DataSourceError failure={dbFailure} loginHref={`/login?next=${encodeURIComponent(withPreview(`${basePath}/events`, ctx))}`} retryHref={withPreview(`${basePath}/events`, ctx)} />
      ) : failedRead || !loaded ? (
        <ErrorState lost="The events list" read={failedRead ?? "catalog.event"} retryHref={withPreview(`${basePath}/events`, ctx)} />
      ) : (
        <EventsTable
          events={loaded.events}
          batches={loaded.batches}
          types={loaded.types}
          holds={loaded.holds}
          ctx={ctx}
          basePath={basePath}
          timeZone={p.timeZone}
          now={p.now}
          filter={{ status: ctx.state === "nodata" ? "zzz" : p.first("status"), q: p.first("q") }}
        />
      )}
      </section>
    </Shell>
  );
}

import { listBatches, listManifestEpisodes, listTicketTypes, PreviewReadError } from "@/lib/data";
import { dbListBatches, dbListTicketTypes } from "@/lib/db/adapters";
import type { ReadFailure } from "@/lib/db/read-result";
import { readPage, type PageParams } from "@/lib/page";
import { EntryGate } from "@/components/ui/EntryGate";
import { withPreview, type SearchParams } from "@/lib/preview";
import { canReadEvents } from "@/lib/roles";
import type { InventoryBatch, TicketType } from "@/lib/types";
import { EventSetup } from "@/components/events/EventSetup";
import { PreviewOutcome, Shell } from "@/components/shell/Shell";
import { DataSourceError } from "@/components/ui/DataSourceError";
import { DeniedState, ErrorState, Skeleton } from "@/components/ui/State";

export const metadata = { title: "Event setup" };
export const dynamic = "force-dynamic";

export default async function EventPage({ params, searchParams }: { params: Promise<PageParams>; searchParams: Promise<SearchParams> }) {
  const p = await readPage(params, searchParams);
  if (!p.scope.ok) return <DeniedState />;
  const { ctx } = p;
  const basePath = p.scope.basePath;
  const readable = ctx.state !== "denied" && canReadEvents(ctx.role);
  const self = `${basePath}/events/${p.params.event}`;

  // Database mode: session/config failures first, then the event by id (RLS decides visibility).
  const entryOpen = p.entry.kind === "fixtures" || p.entry.kind === "ok";
  const dbFailure: ReadFailure | null = ctx.source === "database" ? p.eventFailure : null;
  const event = p.event;

  let loaded: { types: TicketType[]; batches: InventoryBatch[]; open: Set<string> } | null = null;
  let failedRead: string | null = null;
  let dbLoadFailure: ReadFailure | null = null;
  if (readable && entryOpen && ctx.state !== "loading" && event && !dbFailure) {
    if (ctx.source === "database") {
      const t = await dbListTicketTypes(event.eventId);
      const b = t.ok ? await dbListBatches(event.eventId) : null;
      if (!t.ok) dbLoadFailure = t;
      else if (b && !b.ok) dbLoadFailure = b;
      else loaded = { types: ctx.state === "empty" ? [] : t.data, batches: ctx.state === "empty" ? [] : (b as { ok: true; data: InventoryBatch[] }).data, open: new Set() };
    } else {
      try {
        loaded = {
          types: listTicketTypes(ctx.state, event.eventId),
          batches: listBatches(ctx.state, event.eventId),
          open: new Set(event.sessions.filter((s) => listManifestEpisodes("live", s.sessionId).some((e) => e.closedAt === null)).map((s) => s.sessionId)),
        };
      } catch (e) {
        failedRead = e instanceof PreviewReadError ? e.read : "catalog.event";
      }
    }
  }

  return (
    <Shell ctx={ctx} event={event ? { eventId: event.eventId, title: event.title } : null} active="setup" signedInAs={p.signedInAs}>
      {ctx.source === "fixtures" ? <PreviewOutcome did={p.first("did")} /> : null}
      {!entryOpen ? (
        <EntryGate entry={p.entry} loginHref={`/login?next=${encodeURIComponent(withPreview(self, ctx))}`} retryHref={withPreview(self, ctx)} />
      ) : !readable ? (
        <DeniedState />
      ) : ctx.state === "loading" ? (
        <Skeleton rows={8} />
      ) : dbFailure ?? dbLoadFailure ? (
        <DataSourceError failure={(dbFailure ?? dbLoadFailure) as ReadFailure} loginHref={`/login?next=${encodeURIComponent(withPreview(self, ctx))}`} retryHref={withPreview(self, ctx)} />
      ) : !event ? (
        // Fail closed: an event you cannot read is indistinguishable from one that does not exist (spec §4.4 rule 5).
        <DeniedState alternative={{ label: "Back to events", href: withPreview(`${basePath}/events`, ctx) }} />
      ) : failedRead || !loaded ? (
        <ErrorState read={failedRead ?? "catalog.event"} retryHref={withPreview(self, ctx)} />
      ) : (
        <EventSetup event={event} types={loaded.types} batches={loaded.batches} ctx={ctx} basePath={basePath} timeZone={p.timeZone} openManifestSessionIds={loaded.open} />
      )}
    </Shell>
  );
}

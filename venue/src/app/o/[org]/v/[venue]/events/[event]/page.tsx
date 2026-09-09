import { listBatches, listManifestEpisodes, listTicketTypes, PreviewReadError } from "@/lib/data";
import { readPage, type PageParams } from "@/lib/page";
import { withPreview, type SearchParams } from "@/lib/preview";
import { canReadEvents } from "@/lib/roles";
import type { InventoryBatch, TicketType } from "@/lib/types";
import { EventSetup } from "@/components/events/EventSetup";
import { PreviewOutcome, Shell } from "@/components/shell/Shell";
import { DeniedState, ErrorState, Skeleton } from "@/components/ui/State";

export const metadata = { title: "Event setup" };

export default async function EventPage({ params, searchParams }: { params: Promise<PageParams>; searchParams: Promise<SearchParams> }) {
  const p = await readPage(params, searchParams);
  if (!p.scope.ok || !p.event) return <DeniedState />;
  const { ctx, event } = p;
  const basePath = p.scope.basePath;
  const readable = ctx.state !== "denied" && canReadEvents(ctx.role);

  let loaded: { types: TicketType[]; batches: InventoryBatch[]; open: Set<string> } | null = null;
  let failedRead: string | null = null;
  if (readable && ctx.state !== "loading") {
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

  return (
    <Shell ctx={ctx} event={{ eventId: event.eventId, title: event.title }} active="setup">
      <PreviewOutcome did={p.first("did")} />
      {!readable ? (
        <DeniedState />
      ) : ctx.state === "loading" ? (
        <Skeleton rows={8} />
      ) : failedRead || !loaded ? (
        <ErrorState read={failedRead ?? "catalog.event"} retryHref={withPreview(`${basePath}/events/${event.eventId}`, ctx)} />
      ) : (
        <EventSetup event={event} types={loaded.types} batches={loaded.batches} ctx={ctx} basePath={basePath} timeZone={p.timeZone} openManifestSessionIds={loaded.open} />
      )}
    </Shell>
  );
}

import { listBatches, listHolds, listTicketTypes, PreviewReadError } from "@/lib/data";
import { readPage, type PageParams } from "@/lib/page";
import { withPreview, type SearchParams } from "@/lib/preview";
import { canReadTicketTypes, inventoryView } from "@/lib/roles";
import type { InventoryBatch, InventoryHold, TicketType } from "@/lib/types";
import { InventoryOverview } from "@/components/inventory/InventoryOverview";
import { PreviewOutcome, Shell } from "@/components/shell/Shell";
import { DeniedState, ErrorState, Skeleton } from "@/components/ui/State";

export const metadata = { title: "Inventory" };

export default async function InventoryPage({ params, searchParams }: { params: Promise<PageParams>; searchParams: Promise<SearchParams> }) {
  const p = await readPage(params, searchParams);
  if (!p.scope.ok || !p.event) return <DeniedState />;
  const { ctx, event } = p;
  const basePath = p.scope.basePath;
  const readable = ctx.state !== "denied" && canReadTicketTypes(ctx.role) && inventoryView(ctx.role) !== "none";

  let loaded: { types: TicketType[]; batches: InventoryBatch[]; holds: InventoryHold[] } | null = null;
  let failedRead: string | null = null;
  if (readable && ctx.state !== "loading") {
    try {
      loaded = {
        types: listTicketTypes(ctx.state === "nodata" ? "live" : ctx.state, event.eventId),
        batches: listBatches(ctx.state, event.eventId),
        holds: listHolds(ctx.state, event.eventId),
      };
    } catch (e) {
      failedRead = e instanceof PreviewReadError ? e.read : "venue.inventory_batch";
    }
  }

  return (
    <Shell ctx={ctx} event={{ eventId: event.eventId, title: event.title }} active="inventory">
      <PreviewOutcome did={p.first("did")} />
      {!readable ? (
        <DeniedState />
      ) : ctx.state === "loading" ? (
        <Skeleton rows={9} />
      ) : failedRead || !loaded ? (
        <ErrorState read={failedRead ?? "venue.inventory_batch"} retryHref={withPreview(`${basePath}/events/${event.eventId}/inventory`, ctx)} />
      ) : (
        <InventoryOverview event={event} types={loaded.types} batches={loaded.batches} holds={loaded.holds} ctx={ctx} basePath={basePath} timeZone={p.timeZone} now={p.now} />
      )}
    </Shell>
  );
}

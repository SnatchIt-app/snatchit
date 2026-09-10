import { listBatches, listHolds, listTicketTypes, PreviewReadError } from "@/lib/data";
import { dbListBatches, dbListTicketTypes } from "@/lib/db/adapters";
import type { ReadFailure } from "@/lib/db/read-result";
import { readPage, type PageParams } from "@/lib/page";
import { EntryGate } from "@/components/ui/EntryGate";
import { withPreview, type SearchParams } from "@/lib/preview";
import { canReadTicketTypes, inventoryView } from "@/lib/roles";
import type { InventoryBatch, InventoryHold, TicketType } from "@/lib/types";
import { InventoryOverview } from "@/components/inventory/InventoryOverview";
import { PreviewOutcome, Shell } from "@/components/shell/Shell";
import { DataSourceError } from "@/components/ui/DataSourceError";
import { DeniedState, ErrorState, Skeleton } from "@/components/ui/State";

export const metadata = { title: "Inventory" };
export const dynamic = "force-dynamic";

export default async function InventoryPage({ params, searchParams }: { params: Promise<PageParams>; searchParams: Promise<SearchParams> }) {
  const p = await readPage(params, searchParams);
  if (!p.scope.ok) return <DeniedState />;
  const { ctx } = p;
  const basePath = p.scope.basePath;
  const self = `${basePath}/events/${p.params.event}/inventory`;
  const readable = ctx.state !== "denied" && canReadTicketTypes(ctx.role) && inventoryView(ctx.role) !== "none";
  const entryOpen = p.entry.kind === "fixtures" || p.entry.kind === "ok";
  const dbFailure: ReadFailure | null = ctx.source === "database" ? p.eventFailure : null;
  const event = p.event;

  let loaded: { types: TicketType[]; batches: InventoryBatch[]; holds: InventoryHold[] } | null = null;
  let failedRead: string | null = null;
  let dbLoadFailure: ReadFailure | null = null;
  if (readable && entryOpen && ctx.state !== "loading" && event && !dbFailure) {
    if (ctx.source === "database") {
      const t = await dbListTicketTypes(event.eventId);
      const b = t.ok ? await dbListBatches(event.eventId) : null;
      if (!t.ok) dbLoadFailure = t;
      else if (b && !b.ok) dbLoadFailure = b;
      else loaded = { types: t.data, batches: ctx.state === "empty" ? [] : (b as { ok: true; data: InventoryBatch[] }).data, holds: [] };
    } else {
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
  }

  return (
    <Shell ctx={ctx} event={event ? { eventId: event.eventId, title: event.title } : null} active="inventory" signedInAs={p.signedInAs}>
      {ctx.source === "fixtures" ? <PreviewOutcome did={p.first("did")} /> : null}
      {!entryOpen ? (
        <EntryGate entry={p.entry} loginHref={`/login?next=${encodeURIComponent(withPreview(self, ctx))}`} retryHref={withPreview(self, ctx)} />
      ) : !readable ? (
        <DeniedState />
      ) : ctx.state === "loading" ? (
        <Skeleton rows={9} />
      ) : dbFailure ?? dbLoadFailure ? (
        <DataSourceError failure={(dbFailure ?? dbLoadFailure) as ReadFailure} loginHref={`/login?next=${encodeURIComponent(withPreview(self, ctx))}`} retryHref={withPreview(self, ctx)} />
      ) : !event ? (
        <DeniedState alternative={{ label: "Back to events", href: withPreview(`${basePath}/events`, ctx) }} />
      ) : failedRead || !loaded ? (
        <ErrorState read={failedRead ?? "venue.inventory_batch"} retryHref={withPreview(self, ctx)} />
      ) : (
        <>
          {ctx.source === "database" ? <p className="mb-4 border border-line-neutral px-3 py-2 text-xs text-muted">Database mode shows <strong>remaining</strong> only. Capacity, held and sold are not readable by any client role until a counters read is contracted (081 E-29).</p> : null}
          <InventoryOverview event={event} types={loaded.types} batches={loaded.batches} holds={loaded.holds} ctx={ctx} basePath={basePath} timeZone={p.timeZone} now={p.now} />
        </>
      )}
    </Shell>
  );
}

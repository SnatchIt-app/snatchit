import { listBatches, listHolds, listTicketTypes, PreviewReadError } from "@/lib/data";
import { dbListBatches, dbListTicketTypes } from "@/lib/db/adapters";
import { mintCommandKey } from "@/lib/db/commands";
import { commandsGateOpen } from "@/lib/db/command-gate";
import { dbInventoryCounters } from "@/lib/db/counters";
import { mergeCounters } from "@/lib/db/counters-merge";
import { TierCommands, type TierCommandKeys } from "@/components/inventory/TierCommands";
import type { ReadFailure } from "@/lib/db/read-result";
import { readPage, type PageParams } from "@/lib/page";
import { EntryGate } from "@/components/ui/EntryGate";
import { withPreview, type SearchParams } from "@/lib/preview";
import { canChangeCapacity, canEditEvents, canReadTicketTypes, inventoryView } from "@/lib/roles";
import type { InventoryBatch, InventoryHold, TicketType } from "@/lib/types";
import { InventoryOverview } from "@/components/inventory/InventoryOverview";
import { PreviewOutcome, Shell } from "@/components/shell/Shell";
import { DataSourceError } from "@/components/ui/DataSourceError";
import { DeniedState, ErrorState, Skeleton } from "@/components/ui/State";
import { PRINCIPAL_LABEL } from "@/lib/roles";

export const metadata = { title: "Tickets" };
export const dynamic = "force-dynamic";

export default async function InventoryPage({ params, searchParams }: { params: Promise<PageParams>; searchParams: Promise<SearchParams> }) {
  const p = await readPage(params, searchParams);
  if (!p.scope.ok) return <DeniedState standalone surface="This venue" reason="This account holds no role at the venue in this link." />;
  let { ctx } = p;
  const basePath = p.scope.basePath;
  const self = `${basePath}/events/${p.params.event}/inventory`;
  const readable = ctx.state !== "denied" && canReadTicketTypes(ctx.role) && inventoryView(ctx.role) !== "none";
  const entryOpen = p.entry.kind === "fixtures" || p.entry.kind === "ok";
  const dbFailure: ReadFailure | null = ctx.source === "database" ? p.eventFailure : null;
  const event = p.event;

  let loaded: { types: TicketType[]; batches: InventoryBatch[]; holds: InventoryHold[] } | null = null;
  let failedRead: string | null = null;
  let dbLoadFailure: ReadFailure | null = null;
  /** Database mode: why the counters view is not shown (the staff read failed or was partial) — said, never zeroed. */
  let countersNote: string | null = null;
  let commands: { keys: TierCommandKeys; ids: { orgId: string; venueId: string; eventId: string } } | null = null;
  if (readable && entryOpen && ctx.state !== "loading" && event && !dbFailure) {
    if (ctx.source === "database") {
      const t = await dbListTicketTypes(event.eventId);
      const b = t.ok ? await dbListBatches(event.eventId) : null;
      if (!t.ok) dbLoadFailure = t;
      else if (b && !b.ok) dbLoadFailure = b;
      else {
        let batches = ctx.state === "empty" ? [] : (b as { ok: true; data: InventoryBatch[] }).data;
        // S1: the staff counters read (D's 160 via venue_cmd), only for the roles its authority admits.
        if (inventoryView(ctx.role) === "counters" && batches.length > 0) {
          const c = await dbInventoryCounters(event.eventId);
          if (c.ok) {
            const m = mergeCounters(batches, c.data);
            batches = m.batches;
            if (m.complete) ctx = { ...ctx, countersAvailable: true };
            else countersNote = "Capacity, held and sold are shown only where the counters read covered every release; the rest show remaining only.";
          } else {
            countersNote = c.kind === "not_exposed" ? "Capacity, held and sold are not readable on this project yet (the counters read is not exposed). Remaining is shown." : `Couldn't load capacity, held and sold (${c.message}). Remaining is shown; nothing here is a zero.`;
          }
        }
        loaded = { types: t.data, batches, holds: [] };
        // S1: the tier and capacity commands, rendered only when D's gate is open and the role may edit.
        if (commandsGateOpen() && (canEditEvents(ctx.role) || canChangeCapacity(ctx.role)) && p.scope.ok) {
          const keyFor = async (ids: string[]) => Object.fromEntries(await Promise.all(ids.map(async (id) => [id, await mintCommandKey()] as const)));
          const typeIds = t.data.map((x) => x.ticketTypeId);
          commands = {
            ids: { orgId: p.scope.orgId, venueId: p.scope.venueId, eventId: event.eventId },
            keys: { create: await mintCommandKey(), price: await keyFor(typeIds), visibility: await keyFor(typeIds), rank: await keyFor(typeIds), capacity: await keyFor(batches.map((x) => x.batchId)), release: await keyFor(typeIds), saleWindow: await keyFor(typeIds) },
          };
        }
      }
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
    <Shell ctx={ctx} event={event ? { eventId: event.eventId, title: event.title } : null} active="inventory" signedInAs={p.signedInAs} title={event && readable && ctx.state !== "loading" && !failedRead && loaded ? undefined : "Tickets"}>
      {ctx.source === "fixtures" ? <PreviewOutcome did={p.first("did")} /> : null}
      {!entryOpen ? (
        <EntryGate entry={p.entry} loginHref={`/login?next=${encodeURIComponent(withPreview(self, ctx))}`} retryHref={withPreview(self, ctx)} />
      ) : !readable ? (
        <DeniedState surface="Inventory" roleLabel={PRINCIPAL_LABEL[ctx.role]} alternative={{ label: "Back to events", href: withPreview(`${basePath}/events`, ctx) }} />
      ) : ctx.state === "loading" ? (
        <Skeleton rows={9} />
      ) : dbFailure ?? dbLoadFailure ? (
        <DataSourceError failure={(dbFailure ?? dbLoadFailure) as ReadFailure} loginHref={`/login?next=${encodeURIComponent(withPreview(self, ctx))}`} retryHref={withPreview(self, ctx)} />
      ) : !event ? (
        <DeniedState
          surface="This event"
          reason="Either it isn't yours to see, or it isn't there. The dashboard answers the same way to both on purpose."
          alternative={{ label: "Back to events", href: withPreview(`${basePath}/events`, ctx) }}
        />
      ) : failedRead || !loaded ? (
        <ErrorState lost="Inventory" read={failedRead ?? "venue.inventory_batch"} retryHref={withPreview(self, ctx)} />
      ) : (
        <>
          {ctx.source === "database" && (countersNote || ctx.countersAvailable !== true) ? <p className="mb-4 border border-line-neutral px-3 py-2 text-xs text-muted">{countersNote ?? "This role reads remaining only; capacity, held and sold are a staff read for owners, admins, finance and venue managers."}</p> : null}
          {ctx.source === "database" && !commands ? <p className="mb-4 text-xs text-dim">Tiers and inventory are read-only here for now: commands are not enabled on this project.</p> : null}
          {false ? <p className="mb-4 border border-line-neutral px-3 py-2 text-xs text-muted">Database mode shows <strong>remaining</strong> only. Capacity, held and sold are not readable by any client role until a counters read is contracted (081 E-29).</p> : null}
          <InventoryOverview
            event={event}
            types={loaded.types}
            batches={loaded.batches}
            holds={loaded.holds}
            ctx={ctx}
            basePath={basePath}
            timeZone={p.timeZone}
            now={p.now}
            commandsSlot={commands ? <TierCommands ids={commands.ids} types={loaded.types} batches={loaded.batches} keys={commands.keys} sessionId={event.sessions[0]?.sessionId ?? null} timeZone={p.timeZone} /> : undefined}
          />
        </>
      )}
    </Shell>
  );
}

import { listBatches, listManifestEpisodes, listTicketTypes, PreviewReadError } from "@/lib/data";
import { dbListBatches, dbListTicketTypes } from "@/lib/db/adapters";
import type { ReadFailure } from "@/lib/db/read-result";
import { readPage, type PageParams } from "@/lib/page";
import { EntryGate } from "@/components/ui/EntryGate";
import { withPreview, type SearchParams } from "@/lib/preview";
import { canReadEvents } from "@/lib/roles";
import type { InventoryBatch, TicketType } from "@/lib/types";
import { EventSetup } from "@/components/events/EventSetup";
import { EventCommandPanel, type EventCommandKeys } from "@/components/events/EventCommandPanel";
import { commandsGateOpen } from "@/lib/db/command-gate";
import { mintCommandKey } from "@/lib/db/event-commands";
import { DATA_SOURCE } from "@/lib/env";
import { venueTimeZone } from "@/lib/events/zone";
import { canEditEvents } from "@/lib/roles";
import { PreviewOutcome, Shell } from "@/components/shell/Shell";
import { Page } from "@/components/ui/Page";
import { DataSourceError } from "@/components/ui/DataSourceError";
import { DeniedState, ErrorState, Skeleton } from "@/components/ui/State";
import { PRINCIPAL_LABEL } from "@/lib/roles";

export const metadata = { title: "Event" };
export const dynamic = "force-dynamic";

export default async function EventPage({ params, searchParams }: { params: Promise<PageParams>; searchParams: Promise<SearchParams> }) {
  const p = await readPage(params, searchParams);
  if (!p.scope.ok) return <DeniedState standalone surface="This venue" reason="This account holds no role at the venue in this link." />;
  const { ctx } = p;
  const basePath = p.scope.basePath;
  const readable = ctx.state !== "denied" && canReadEvents(ctx.role);
  const self = `${basePath}/events/${p.params.event}`;

  // Database mode: session/config failures first, then the event by id (RLS decides visibility).
  const entryOpen = p.entry.kind === "fixtures" || p.entry.kind === "ok";
  const dbFailure: ReadFailure | null = ctx.source === "database" ? p.eventFailure : null;
  const event = p.event;

  // open: null = the check-in list state was not read (database mode) — never shown as closed.
  let loaded: { types: TicketType[]; batches: InventoryBatch[]; open: Set<string> | null } | null = null;
  let failedRead: string | null = null;
  let dbLoadFailure: ReadFailure | null = null;
  if (readable && entryOpen && ctx.state !== "loading" && event && !dbFailure) {
    if (ctx.source === "database") {
      const t = await dbListTicketTypes(event.eventId);
      const b = t.ok ? await dbListBatches(event.eventId) : null;
      if (!t.ok) dbLoadFailure = t;
      else if (b && !b.ok) dbLoadFailure = b;
      else loaded = { types: ctx.state === "empty" ? [] : t.data, batches: ctx.state === "empty" ? [] : (b as { ok: true; data: InventoryBatch[] }).data, open: null };
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

  // The organizer's commands (row 2), only when D's wrappers are exposed and the role may edit.
  let commands: { ids: { orgId: string; venueId: string; eventId: string }; keys: EventCommandKeys } | null = null;
  if (event && loaded && ctx.source === "database" && p.scope.ok && canEditEvents(ctx.role) && commandsGateOpen()) {
    const perSession = async () => Object.fromEntries(await Promise.all(event.sessions.map(async (s) => [s.sessionId, await mintCommandKey()] as const)));
    commands = {
      ids: { orgId: p.scope.orgId, venueId: p.scope.venueId, eventId: event.eventId },
      keys: { details: await mintCommandKey(), publish: await mintCommandKey(), cancel: await mintCommandKey(), sessionNew: await mintCommandKey(), session: await perSession(), capacity: await perSession() },
    };
  }

  return (
    <Shell ctx={ctx} event={event ? { eventId: event.eventId, title: event.title } : null} active="setup" signedInAs={p.signedInAs}>
      <Page eyebrow={event?.title ?? "Event"} title={event ? "Event setup" : "Event"} art={event?.title}>
        {ctx.source === "fixtures" ? <PreviewOutcome did={p.first("did")} /> : null}
        {!entryOpen ? (
        <EntryGate entry={p.entry} loginHref={`/login?next=${encodeURIComponent(withPreview(self, ctx))}`} retryHref={withPreview(self, ctx)} />
      ) : !readable ? (
        <DeniedState surface="Event setup" roleLabel={PRINCIPAL_LABEL[ctx.role]} alternative={{ label: "Back to events", href: withPreview(`${basePath}/events`, ctx) }} />
      ) : ctx.state === "loading" ? (
        <Skeleton rows={8} />
      ) : dbFailure ?? dbLoadFailure ? (
        <DataSourceError failure={(dbFailure ?? dbLoadFailure) as ReadFailure} loginHref={`/login?next=${encodeURIComponent(withPreview(self, ctx))}`} retryHref={withPreview(self, ctx)} />
      ) : !event ? (
        // Fail closed: an event you cannot read is indistinguishable from one that does not exist (spec §4.4 rule 5).
        <DeniedState
          surface="This event"
          reason="Either it isn't yours to see, or it isn't there. The dashboard deliberately answers the same way to both, so a link can never be used to find out which."
          alternative={{ label: "Back to events", href: withPreview(`${basePath}/events`, ctx) }}
        />
      ) : failedRead || !loaded ? (
        <ErrorState lost="This event" read={failedRead ?? "catalog.event"} retryHref={withPreview(self, ctx)} />
      ) : (
        <EventSetup
          event={event}
          types={loaded.types}
          batches={loaded.batches}
          ctx={ctx}
          basePath={basePath}
          timeZone={p.timeZone}
          openManifestSessionIds={loaded.open}
          commandsSlot={
            commands ? <EventCommandPanel ids={commands.ids} event={event} keys={commands.keys} zone={venueTimeZone(DATA_SOURCE, null)} /> : undefined
          }
        />
      )}
      </Page>
    </Shell>
  );
}

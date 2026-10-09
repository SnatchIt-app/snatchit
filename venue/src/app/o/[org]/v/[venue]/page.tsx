import { VENUE } from "@/fixtures/venue";
import { listBatches, listDevices, listEvents, listFlags, listHolds, listTicketTypes, scanCounters, tonightSessions, PreviewReadError } from "@/lib/data";
import { readPage, type PageParams } from "@/lib/page";
import { withPreview, type SearchParams } from "@/lib/preview";
import { canReadEvents, PRINCIPAL_LABEL, showCounters } from "@/lib/roles";
import { sessionTotals } from "@/lib/inventory";
import { buildSignals, doorSummary, eventStage, stillAvailable } from "@/lib/signals";
import { PreviewOutcome, Shell } from "@/components/shell/Shell";
import { Tonight, TodaySkeleton, type SalesLine } from "@/components/overview/Tonight";
import { NotWiredState } from "@/components/ui/DataSourceError";
import { EntryGate } from "@/components/ui/EntryGate";
import { DeniedState, EmptyState, ErrorState } from "@/components/ui/State";

export const metadata = { title: "Today" };
export const dynamic = "force-dynamic";

/**
 * The venue landing page — audit §W1. It answers "what needs me now?" before
 * it shows anything else, and every item links to the screen that owns the fix.
 *
 * Fixture-only for now: the signals it draws on (scanner sync, open flags,
 * expiring holds) have no contracted read yet, so in database mode this page
 * says so rather than showing sample numbers beside real ones. See
 * docs/venue-dashboard/DEMO.md, "still needs backend integration".
 */
export default async function OverviewPage({ params, searchParams }: { params: Promise<PageParams>; searchParams: Promise<SearchParams> }) {
  const p = await readPage(params, searchParams);
  if (!p.scope.ok) return <DeniedState surface="This venue" reason="This account holds no role at the venue in this link." />;
  const { ctx } = p;
  const { basePath } = p.scope;

  if (ctx.source === "database") {
    return (
      <Shell ctx={ctx} event={null} active="overview" signedInAs={p.signedInAs} title="Today">
        {p.entry.kind === "ok" ? <NotWiredState surface="Tonight overview" /> : <EntryGate entry={p.entry} loginHref={`/login?next=${encodeURIComponent(basePath)}`} retryHref={basePath} />}
      </Shell>
    );
  }

  const readable = ctx.state !== "denied" && canReadEvents(ctx.role);
  const self = withPreview(basePath, ctx);

  type Ready = {
    signals: ReturnType<typeof buildSignals>["signals"];
    clear: ReturnType<typeof buildSignals>["clear"];
    door: ReturnType<typeof doorSummary>;
    stageView: ReturnType<typeof eventStage>;
    events: ReturnType<typeof listEvents>;
    available: number;
    sales: SalesLine[];
    arrivals: number[];
    scanners: { online: number; total: number };
  };
  let ready: Ready | null = null;
  let failedRead: string | null = null;

  if (readable && ctx.state !== "loading") {
    try {
      const events = listEvents(ctx.state);
      const types = events.flatMap((e) => listTicketTypes("live", e.eventId));
      const batches = events.flatMap((e) => listBatches("live", e.eventId));
      const holds = events.flatMap((e) => listHolds("live", e.eventId));
      const devices = listDevices(ctx.state);
      const tonight = tonightSessions(p.now);
      const flags = tonight.length > 0 ? listFlags(ctx.state, tonight[0].session.sessionId) : [];
      const counters = tonight.length > 0 ? scanCounters(ctx.state, tonight[0].session.sessionId) : null;
      const built = buildSignals({ events, types, batches, holds, devices, flags, tonight, now: p.now, basePath, link: (href) => withPreview(href, ctx) });
      const stageView = eventStage(events, tonight, p.now);
      const stageSession = stageView.session;
      const sales: SalesLine[] = stageView.event && stageSession
        ? types
            .filter((t) => t.eventId === stageView.event!.eventId)
            .map((t) => ({ t, tot: sessionTotals(batches, t.ticketTypeId, stageSession.sessionId) }))
            .filter(({ tot }) => tot.capacity > 0)
            .map(({ t, tot }) => ({ ticketTypeId: t.ticketTypeId, name: t.name, priceMinor: t.priceMinor, sold: tot.sold, capacity: tot.capacity, remaining: tot.remaining, held: tot.held, visibility: t.visibility }))
        : [];
      const active = devices.filter((d) => d.status === "active");
      ready = {
        signals: built.signals,
        clear: built.clear,
        door: doorSummary(tonight, counters, devices),
        stageView,
        events,
        available: stillAvailable(events, types, batches),
        sales,
        arrivals: counters?.arrivalsPer5Min ?? [],
        scanners: { online: active.filter((d) => d.online).length, total: active.length },
      };
    } catch (e) {
      failedRead = e instanceof PreviewReadError ? e.read : "catalog.event";
    }
  }

  return (
    <Shell
      ctx={ctx}
      event={ready?.stageView.event ? { eventId: ready.stageView.event.eventId, title: ready.stageView.event.title } : null}
      active="overview"
      signedInAs={p.signedInAs}
      title={readable && ctx.state !== "loading" && ready && ready.events.length > 0 ? undefined : "Today"}
    >
      <PreviewOutcome did={p.first("did")} />
      {!readable ? (
        <DeniedState surface="This dashboard" roleLabel={PRINCIPAL_LABEL[ctx.role]} />
      ) : ctx.state === "loading" ? (
        <TodaySkeleton />
      ) : failedRead || !ready ? (
        <ErrorState lost="Tonight" read={failedRead ?? "catalog.event"} retryHref={self} />
      ) : ready.events.length === 0 ? (
        <EmptyState title="No events yet. Today fills in once your first event is set up — what is selling, who is arriving and what needs you.">
          <a className="btn btn-primary" href={withPreview(`${basePath}/events/new`, ctx)}>
            Create an event
          </a>
        </EmptyState>
      ) : (
        <Tonight
          signals={ready.signals}
          clear={ready.clear}
          door={ready.door}
          stageView={ready.stageView}
          events={ready.events}
          available={ready.available}
          ctx={ctx}
          basePath={basePath}
          timeZone={p.timeZone}
          now={p.now}
          sales={ready.sales}
          countersVisible={showCounters(ctx.role, ctx)}
          arrivals={ready.stageView.stage === "during" ? ready.arrivals : []}
          scanners={ready.scanners}
          venueName={VENUE.name}
        />
      )}
    </Shell>
  );
}

import { VENUE } from "@/fixtures/venue";
import { listBatches, listDevices, listEvents, listFlags, listHolds, listTicketTypes, scanCounters, tonightSessions, PreviewReadError } from "@/lib/data";
import { readPage, type PageParams } from "@/lib/page";
import { withPreview, type SearchParams } from "@/lib/preview";
import { canReadEvents, PRINCIPAL_LABEL } from "@/lib/roles";
import { buildSignals, doorSummary, stillAvailable } from "@/lib/signals";
import { PreviewOutcome, Shell } from "@/components/shell/Shell";
import { Tonight } from "@/components/overview/Tonight";
import { Page } from "@/components/ui/Page";
import { NotWiredState } from "@/components/ui/DataSourceError";
import { EntryGate } from "@/components/ui/EntryGate";
import { DeniedState, ErrorState, Skeleton } from "@/components/ui/State";

export const metadata = { title: "Tonight" };
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
      <Shell ctx={ctx} event={null} active="overview" signedInAs={p.signedInAs}>
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
    events: ReturnType<typeof listEvents>;
    available: number;
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
      ready = { signals: built.signals, clear: built.clear, door: doorSummary(tonight, counters, devices), events, available: stillAvailable(events, types, batches) };
    } catch (e) {
      failedRead = e instanceof PreviewReadError ? e.read : "catalog.event";
    }
  }

  return (
    <Shell ctx={ctx} event={null} active="overview" signedInAs={p.signedInAs}>
      <PreviewOutcome did={p.first("did")} />
      <Page eyebrow={VENUE.name} title="Today" lead="What is happening, what needs you, and the one thing to do about it.">
        {!readable ? (
        <DeniedState surface="This dashboard" roleLabel={PRINCIPAL_LABEL[ctx.role]} />
      ) : ctx.state === "loading" ? (
        <Skeleton rows={8} />
      ) : failedRead || !ready ? (
        <ErrorState lost="Tonight" read={failedRead ?? "catalog.event"} retryHref={self} />
      ) : (
        <Tonight signals={ready.signals} clear={ready.clear} door={ready.door} events={ready.events} available={ready.available} ctx={ctx} basePath={basePath} timeZone={p.timeZone} now={p.now} />
        )}
      </Page>
    </Shell>
  );
}

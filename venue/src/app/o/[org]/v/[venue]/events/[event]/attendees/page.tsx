import { listAttendees, listOrders, PreviewReadError } from "@/lib/data";
import { readPage, type PageParams } from "@/lib/page";
import { withPreview, type SearchParams } from "@/lib/preview";
import { canManualLookup, canReadOrders, rosterClasses } from "@/lib/roles";
import type { OrderRow, RosterRow } from "@/lib/types";
import { Attendees } from "@/components/attendees/Attendees";
import { PreviewOutcome, Shell } from "@/components/shell/Shell";
import { DeniedState, ErrorState, Skeleton } from "@/components/ui/State";
import { NotWiredState } from "@/components/ui/DataSourceError";

export const metadata = { title: "Attendees" };

export default async function AttendeesPage({ params, searchParams }: { params: Promise<PageParams>; searchParams: Promise<SearchParams> }) {
  const p = await readPage(params, searchParams);
  if (!p.scope.ok) return <DeniedState />;
  if (p.ctx.source === "database") {
    return (
      <Shell ctx={p.ctx} event={p.event ? { eventId: p.event.eventId, title: p.event.title } : null} active="attendees" signedInAs={p.signedInAs}>
        <NotWiredState surface="Attendees" />
      </Shell>
    );
  }
  if (!p.event) return <DeniedState />;
  const { ctx, event } = p;
  const basePath = p.scope.basePath;
  const session = event.sessions[0];
  const view = p.first("view") === "purchasers" && canReadOrders(ctx.role) ? "purchasers" : "holders";
  const hasRoster = rosterClasses(ctx.role) !== null && !!session;
  const alt = canManualLookup(ctx.role) ? { label: "Door access uses ticket lookup, not the attendee list.", href: withPreview(`${basePath}/events/${event.eventId}/door#lookup`, ctx) } : undefined;
  const dataState = ctx.state === "nodata" ? "live" : ctx.state;
  const filter = { q: ctx.state === "nodata" ? "zzz-no-match" : p.first("q"), checkIn: p.first("checkIn") };

  let loaded: { roster: RosterRow[]; total: number; orders: OrderRow[] } | null = null;
  let failedRead: string | null = null;
  if (ctx.state !== "denied" && ctx.state !== "loading" && hasRoster) {
    try {
      loaded = {
        roster: listAttendees(dataState, session.sessionId, filter),
        total: listAttendees(dataState, session.sessionId).length,
        orders: canReadOrders(ctx.role) ? listOrders(dataState, session.sessionId) : [],
      };
    } catch (e) {
      failedRead = e instanceof PreviewReadError ? e.read : "venue.list_attendees";
    }
  }

  return (
    <Shell ctx={ctx} event={{ eventId: event.eventId, title: event.title }} active="attendees">
      <PreviewOutcome did={p.first("did")} />
      {ctx.state === "denied" ? (
        <DeniedState alternative={alt} />
      ) : ctx.state === "loading" ? (
        <Skeleton rows={10} />
      ) : !hasRoster ? (
        <Attendees event={event} session={session} roster={[]} orders={[]} ctx={ctx} basePath={basePath} timeZone={p.timeZone} filter={{}} totalUnfiltered={0} view="holders" />
      ) : failedRead || !loaded ? (
        <ErrorState read={failedRead ?? "venue.list_attendees"} retryHref={withPreview(`${basePath}/events/${event.eventId}/attendees`, ctx)} />
      ) : (
        <Attendees event={event} session={session} roster={loaded.roster} orders={loaded.orders} ctx={ctx} basePath={basePath} timeZone={p.timeZone} filter={filter} totalUnfiltered={loaded.total} view={view} />
      )}
    </Shell>
  );
}

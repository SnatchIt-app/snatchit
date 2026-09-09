import { listAttendees, listDevices, listFlags, listManifestEpisodes, listPins, scanCounters, PreviewReadError } from "@/lib/data";
import { readPage, type PageParams } from "@/lib/page";
import { withPreview, type SearchParams } from "@/lib/preview";
import { canReadDoor } from "@/lib/roles";
import type { DoorPin, FlagRow, ManifestEpisode, RosterRow, ScanCounters, ScanDevice } from "@/lib/types";
import { DoorStatus } from "@/components/door/DoorStatus";
import { PreviewOutcome, Shell } from "@/components/shell/Shell";
import { DeniedState, ErrorState, Skeleton } from "@/components/ui/State";

export const metadata = { title: "Door" };

type Loaded = { pins: DoorPin[]; devices: ScanDevice[]; episodes: ManifestEpisode[]; scans: ScanCounters; flags: FlagRow[]; lookup: { q: string; result: RosterRow | null } | null };

export default async function DoorPage({ params, searchParams }: { params: Promise<PageParams>; searchParams: Promise<SearchParams> }) {
  const p = await readPage(params, searchParams);
  if (!p.scope.ok || !p.event) return <DeniedState />;
  const { ctx, event } = p;
  const basePath = p.scope.basePath;
  const session = event.sessions.find((s) => s.status === "live") ?? event.sessions[0];
  const readable = ctx.state !== "denied" && canReadDoor(ctx.role) && !!session;

  let loaded: Loaded | null = null;
  let failedRead: string | null = null;
  if (readable && ctx.state !== "loading") {
    try {
      const q = p.first("q");
      const hit = q ? listAttendees("live", session.sessionId, { q }).find((r) => r.name.toLowerCase().includes(q.toLowerCase()) || r.customerRef.toLowerCase() === q.toLowerCase()) ?? null : null;
      loaded = {
        pins: listPins(ctx.state, session.sessionId),
        devices: listDevices(ctx.state),
        episodes: listManifestEpisodes(ctx.state === "nodata" ? "live" : ctx.state, session.sessionId),
        scans: scanCounters(ctx.state, session.sessionId),
        flags: listFlags(ctx.state, session.sessionId),
        lookup: q ? { q, result: hit } : null,
      };
    } catch (e) {
      failedRead = e instanceof PreviewReadError ? e.read : "venue.scan";
    }
  }

  return (
    <Shell ctx={ctx} event={{ eventId: event.eventId, title: event.title }} active="door">
      <PreviewOutcome did={p.first("did")} />
      {!readable ? (
        <DeniedState />
      ) : ctx.state === "loading" ? (
        <Skeleton rows={10} />
      ) : failedRead || !loaded ? (
        <ErrorState read={failedRead ?? "venue.scan"} retryHref={withPreview(`${basePath}/events/${event.eventId}/door`, ctx)} />
      ) : (
        <DoorStatus
          event={event}
          session={session}
          pins={loaded.pins}
          devices={loaded.devices}
          episodes={loaded.episodes}
          scans={loaded.scans}
          flags={loaded.flags}
          lookup={loaded.lookup}
          ctx={ctx}
          basePath={basePath}
          timeZone={p.timeZone}
          now={p.now}
        />
      )}
    </Shell>
  );
}

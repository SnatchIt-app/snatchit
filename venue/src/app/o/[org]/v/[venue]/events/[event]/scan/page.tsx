import { ScannerClient, type ScannerSession } from "@/components/scan/ScannerClient";
import { Shell } from "@/components/shell/Shell";
import { EntryGate } from "@/components/ui/EntryGate";
import { DeniedState } from "@/components/ui/State";
import { readPage, type PageParams } from "@/lib/page";
import { withPreview, type SearchParams } from "@/lib/preview";
import { canScan, canScanGrants, PRINCIPAL_LABEL } from "@/lib/roles";

export const metadata = { title: "Scanner" };
export const dynamic = "force-dynamic";

/**
 * The online scanner for one event: a staff phone, this venue app's session,
 * the server's admission verb. Entry is the same fail-closed policy as every
 * event page; on top of it only the roles `venue.record_scan` admits
 * (venue_scanner, venue_manager) get the screen, and the server checks again
 * on every scan.
 */
export default async function ScanPage({ params, searchParams }: { params: Promise<PageParams>; searchParams: Promise<SearchParams> }) {
  const p = await readPage(params, searchParams);
  if (!p.scope.ok) return <DeniedState standalone surface="This venue" reason="This account holds no role at the venue in this link." />;
  const basePath = p.scope.basePath;
  const here = `${basePath}/events/${p.params.event ?? ""}/scan`;
  const loginHref = `/login?next=${encodeURIComponent(here)}`;
  const nav = p.event ? { eventId: p.event.eventId, title: p.event.title } : null;
  if (p.ctx.source === "database" && p.entry.kind !== "ok") {
    return (
      <Shell ctx={p.ctx} event={nav} active="scan" signedInAs={p.signedInAs} title="Scanner">
        <EntryGate entry={p.entry} loginHref={loginHref} retryHref={here} />
      </Shell>
    );
  }
  if (!p.event) {
    return (
      <Shell ctx={p.ctx} event={null} active="scan" signedInAs={p.signedInAs} title="Scanner">
        <DeniedState surface="This event" reason="Either it isn't yours to see, or it isn't there. The dashboard answers the same way to both on purpose." alternative={{ label: "Back to events", href: withPreview(`${basePath}/events`, p.ctx) }} />
      </Shell>
    );
  }
  // Database mode asks the grants (as the server does); fixtures mode has no
  // grants, only the previewed principal.
  const mayScan = p.ctx.source === "database" ? p.entry.kind === "ok" && canScanGrants(p.entry.grants) : canScan(p.ctx.role);
  if (!mayScan) {
    return (
      <Shell ctx={p.ctx} event={nav} active="scan" signedInAs={p.signedInAs} title="Scanner">
        <DeniedState surface="The scanner" reason="Scanning needs the venue scanner or venue manager role at this venue. The server refuses every other role, so this page does too. Ask a manager to grant it." alternative={{ label: "Back to check-in", href: withPreview(`${basePath}/events/${p.event.eventId}/door`, p.ctx) }} />
      </Shell>
    );
  }
  const sessions: ScannerSession[] = p.event.sessions.map((s) => ({ sessionId: s.sessionId, label: s.label, startsAt: s.startsAt, endsAt: s.endsAt, status: s.status }));
  const defaultSessionId = (sessions.find((s) => s.status === "live") ?? sessions[0])?.sessionId ?? null;
  return (
    <Shell ctx={p.ctx} event={nav} active="scan" signedInAs={p.signedInAs} title="Scanner">
      <ScannerClient
        demo={p.ctx.source !== "database"}
        ids={{ orgId: p.scope.orgId, venueId: p.scope.venueId, eventId: p.event.eventId }}
        eventTitle={p.event.title}
        sessions={sessions}
        defaultSessionId={defaultSessionId}
        staff={{ label: p.signedInAs, role: PRINCIPAL_LABEL[p.ctx.role] }}
        timeZone={p.ctx.source === "database" ? null : p.timeZone}
        loginHref={loginHref}
      />
    </Shell>
  );
}

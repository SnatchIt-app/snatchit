import { VENUE } from "@/fixtures/venue";
import { mintCommandKey } from "@/lib/db/event-commands";
import { commandsGateOpen } from "@/lib/db/command-gate";
import { DATA_SOURCE } from "@/lib/env";
import { venueTimeZone, zoneNote } from "@/lib/events/zone";
import { CreateEventForm } from "@/components/events/EventCommandForms";
import { readPage, type PageParams } from "@/lib/page";
import { withPreview, type SearchParams } from "@/lib/preview";
import { canEditEvents } from "@/lib/roles";
import { CreateEventWizard } from "@/components/events/CreateEventWizard";
import { PreviewOutcome, Shell } from "@/components/shell/Shell";
import { DeniedState, ErrorState, Skeleton } from "@/components/ui/State";
import { NotWiredState } from "@/components/ui/DataSourceError";
import { EntryGate } from "@/components/ui/EntryGate";
import { PRINCIPAL_LABEL } from "@/lib/roles";

export const metadata = { title: "Create event" };
export const dynamic = "force-dynamic";

export default async function NewEventPage({ params, searchParams }: { params: Promise<PageParams>; searchParams: Promise<SearchParams> }) {
  const p = await readPage(params, searchParams);
  if (!p.scope.ok) return <DeniedState standalone surface="This venue" reason="This account holds no role at the venue in this link." />;
  const ctx = p.ctx;
  const stepRaw = Number(p.first("step") ?? "1");
  const step = ([1, 2, 3, 4] as const).includes(stepRaw as 1 | 2 | 3 | 4) ? (stepRaw as 1 | 2 | 3 | 4) : 1;
  const denied = ctx.state === "denied" || !canEditEvents(ctx.role);
  // The wizard carries its own page heading; every other state screen gets it from the frame.
  const showsWizard = ctx.source !== "database" && !denied && ctx.state !== "loading" && ctx.state !== "error";
  // Database mode: the real command, when D's wrappers are exposed and the role may edit.
  const commands = ctx.source === "database" && !denied && p.entry.kind === "ok" && p.scope.ok && commandsGateOpen() ? { ids: { orgId: p.scope.orgId, venueId: p.scope.venueId }, key: await mintCommandKey() } : null;
  const zone = venueTimeZone(DATA_SOURCE, null);
  return (
    <Shell ctx={ctx} event={null} active="events" signedInAs={p.signedInAs} title={showsWizard ? undefined : "New event"}>
      {ctx.source === "fixtures" ? <PreviewOutcome did={p.first("did")} /> : null}
      {ctx.source === "database" && commands ? (
        <>
          <p className="mb-4 text-xs text-dim">{zoneNote(zone)}</p>
          <CreateEventForm ids={commands.ids} commandKey={commands.key} timeZone={zone.zone} />
        </>
      ) : ctx.source === "database" ? (p.entry.kind === "ok" ? <NotWiredState surface="Create event" /> : <EntryGate entry={p.entry} loginHref={`/login?next=${encodeURIComponent(`${p.scope.basePath}/events/new`)}`} retryHref={p.scope.basePath} />) : denied ? <DeniedState surface="Creating an event" roleLabel={PRINCIPAL_LABEL[p.ctx.role]} alternative={{ label: "Back to events", href: withPreview(`${p.scope.basePath}/events`, p.ctx) }} /> : ctx.state === "loading" ? <Skeleton rows={6} /> : ctx.state === "error" ? <ErrorState lost="Creating an event" read="catalog.create_event" retryHref={withPreview(`${p.scope.basePath}/events/new`, ctx)} /> : <CreateEventWizard ctx={ctx} basePath={p.scope.basePath} step={step} venueApproved={VENUE.approvalStatus === "approved"} venueName={VENUE.name} />}
    </Shell>
  );
}

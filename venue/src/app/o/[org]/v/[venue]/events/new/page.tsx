import { VENUE } from "@/fixtures/venue";
import { readPage, type PageParams } from "@/lib/page";
import { withPreview, type SearchParams } from "@/lib/preview";
import { canEditEvents } from "@/lib/roles";
import { CreateEventWizard } from "@/components/events/CreateEventWizard";
import { PreviewOutcome, Shell } from "@/components/shell/Shell";
import { DeniedState, Skeleton } from "@/components/ui/State";
import { NotWiredState } from "@/components/ui/DataSourceError";
import { EntryGate } from "@/components/ui/EntryGate";
import { PRINCIPAL_LABEL } from "@/lib/roles";

export const metadata = { title: "Create event" };
export const dynamic = "force-dynamic";

export default async function NewEventPage({ params, searchParams }: { params: Promise<PageParams>; searchParams: Promise<SearchParams> }) {
  const p = await readPage(params, searchParams);
  if (!p.scope.ok) return <DeniedState surface="This venue" reason="This account holds no role at the venue in this link." />;
  const ctx = p.ctx;
  const stepRaw = Number(p.first("step") ?? "1");
  const step = ([1, 2, 3, 4] as const).includes(stepRaw as 1 | 2 | 3 | 4) ? (stepRaw as 1 | 2 | 3 | 4) : 1;
  const denied = ctx.state === "denied" || !canEditEvents(ctx.role);
  return (
    <Shell ctx={ctx} event={null} active="events" signedInAs={p.signedInAs}>
      {ctx.source === "fixtures" ? <PreviewOutcome did={p.first("did")} /> : null}
      {ctx.source === "database" ? (p.entry.kind === "ok" ? <NotWiredState surface="Create event" /> : <EntryGate entry={p.entry} loginHref="/login" retryHref={p.scope.basePath} />) : denied ? <DeniedState surface="Creating an event" roleLabel={PRINCIPAL_LABEL[p.ctx.role]} alternative={{ label: "Back to events", href: withPreview(`${p.scope.basePath}/events`, p.ctx) }} /> : ctx.state === "loading" ? <Skeleton rows={6} /> : <CreateEventWizard ctx={ctx} basePath={p.scope.basePath} step={step} venueApproved={ctx.state === "error" ? false : VENUE.approvalStatus === "approved"} venueName={VENUE.name} />}
    </Shell>
  );
}

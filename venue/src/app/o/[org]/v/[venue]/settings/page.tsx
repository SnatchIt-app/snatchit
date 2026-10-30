import { VenueDetailsForm, VenueTimezoneForm } from "@/components/venue/VenueSettingsForms";
import { Shell } from "@/components/shell/Shell";
import { EntryGate } from "@/components/ui/EntryGate";
import { NotWiredState } from "@/components/ui/DataSourceError";
import { Page } from "@/components/ui/Page";
import { DeniedState } from "@/components/ui/State";
import { commandsGateOpen } from "@/lib/db/command-gate";
import { mintCommandKey } from "@/lib/db/event-commands";
import { DATA_SOURCE } from "@/lib/env";
import { venueTimeZone, zoneNote } from "@/lib/events/zone";
import { readPage, type PageParams } from "@/lib/page";
import { withPreview, type SearchParams } from "@/lib/preview";
import { canEditEvents, PRINCIPAL_LABEL } from "@/lib/roles";

export const metadata = { title: "Venue settings" };
export const dynamic = "force-dynamic";

/**
 * The venue's own details and its time zone (readiness row 2). The zone governs
 * every time the organizer types for this venue's nights, so it lives here
 * rather than in a platform screen. Approving a venue to sell stays a Snatch It
 * step, and moving a venue to another organization is refused by the server.
 */
export default async function VenueSettingsPage({ params, searchParams }: { params: Promise<PageParams>; searchParams: Promise<SearchParams> }) {
  const p = await readPage(params, searchParams);
  if (!p.scope.ok) return <DeniedState standalone surface="This venue" reason="This account holds no role at the venue in this link." />;
  const { ctx } = p;
  const basePath = p.scope.basePath;
  const self = `${basePath}/settings`;
  const mayEdit = ctx.state !== "denied" && canEditEvents(ctx.role);
  const entryOpen = p.entry.kind === "fixtures" || p.entry.kind === "ok";
  const zone = venueTimeZone(DATA_SOURCE, null);
  const gateOpen = ctx.source === "database" && commandsGateOpen();
  const ids = { orgId: p.scope.orgId, venueId: p.scope.venueId };
  const keys = gateOpen && mayEdit && entryOpen ? { details: await mintCommandKey(), zone: await mintCommandKey() } : null;

  return (
    <Shell ctx={ctx} event={null} active="events" signedInAs={p.signedInAs} title="Venue settings">
      <Page eyebrow="Venue" title="Venue settings" lead="What this venue is called, where it is, and the time zone every night is read in.">
        {!entryOpen ? (
          <EntryGate entry={p.entry} loginHref={`/login?next=${encodeURIComponent(withPreview(self, ctx))}`} retryHref={withPreview(self, ctx)} />
        ) : !mayEdit ? (
          <DeniedState surface="Venue settings" roleLabel={PRINCIPAL_LABEL[ctx.role]} alternative={{ label: "Back to events", href: withPreview(`${basePath}/events`, ctx) }} />
        ) : ctx.source !== "database" ? (
          <p className="panel px-5 py-4 text-sm text-muted">Demo — sample data. Editing a venue writes to the real record, so it is not simulated here.</p>
        ) : !keys ? (
          <NotWiredState surface="Venue settings" />
        ) : (
          <div className="space-y-6">
            <p className="text-xs text-dim">{zoneNote(zone)}</p>
            <section className="panel px-5 py-5" aria-labelledby="venue-details">
              <h2 id="venue-details" className="text-base font-semibold text-ink">Details</h2>
              <p className="mt-1 text-sm text-dim">
                The venue&apos;s name, area and address. Capacity here is a planning number; what each night may actually sell is set per night on the event.
              </p>
              <div className="mt-4">
                <VenueDetailsForm ids={ids} commandKey={keys.details} venue={{ name: p.venueName ?? null }} />
              </div>
            </section>
            <section className="panel px-5 py-5" aria-labelledby="venue-zone">
              <h2 id="venue-zone" className="text-base font-semibold text-ink">Time zone</h2>
              <p className="mt-1 text-sm text-dim">Every time you enter for this venue is read in this zone. Changing it does not move times already saved.</p>
              <div className="mt-4">
                <VenueTimezoneForm ids={ids} commandKey={keys.zone} timeZone={zone.zone} />
              </div>
            </section>
          </div>
        )}
      </Page>
    </Shell>
  );
}

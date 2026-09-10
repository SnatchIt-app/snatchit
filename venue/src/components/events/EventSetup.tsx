import Link from "next/link";
import { STATUS_HELP, STATUS_LABEL, editMode, nextStatus, publishBlocker, RESALE_LABEL } from "@/lib/events";
import { doorHoldback, sessionTotals } from "@/lib/inventory";
import { usd, venueTime } from "@/lib/format";
import { withPreview, type PreviewContext } from "@/lib/preview";
import { canEditEvents, canReadResalePolicy, showCounters } from "@/lib/roles";
import { MANIFEST_COPY, manifestState } from "@/lib/door";
import type { Event, InventoryBatch, TicketType } from "@/lib/types";
import { AuditNote, Metric, Panel, StatusPill } from "@/components/ui/Bits";
import { LargerScreenBanner } from "@/components/ui/State";

/** Spec §7.3–§7.9 — event detail: header counters, sessions, advance status, resale policy, danger zone. */
export function EventSetup({ event, types, batches, ctx, basePath, timeZone, openManifestSessionIds }: { event: Event; types: TicketType[]; batches: InventoryBatch[]; ctx: PreviewContext; basePath: string; timeZone: string; openManifestSessionIds: Set<string> }) {
  const editor = canEditEvents(ctx.role);
  const mode = editMode(event.status);
  const next = nextStatus(event.status);
  const blocker = next === "on_sale" ? publishBlocker(types, batches) : null;
  const counters = showCounters(ctx.role, ctx);
  const first = event.sessions[0];
  const totals = first ? types.map((t) => sessionTotals(batches, t.ticketTypeId, first.sessionId)) : [];
  const sold = totals.reduce((n, t) => n + t.sold, 0);
  const cap = totals.reduce((n, t) => n + t.capacity, 0);
  const gross = types.reduce((n, t) => n + t.priceMinor * (first ? sessionTotals(batches, t.ticketTypeId, first.sessionId).sold : 0), 0);
  const self = `${basePath}/events/${event.eventId}`;

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="eyebrow text-dim">Event setup</p>
          <h1 className="text-2xl font-bold">{event.title}</h1>
          <p className="mt-1 text-sm text-muted">
            <StatusPill status={event.status} /> <span className="ml-2">{STATUS_HELP[event.status]}</span>
          </p>
        </div>
        <div className="grid grid-cols-2 gap-2 md:grid-cols-3">
          {counters ? <Metric label="Sold / capacity" value={`${sold} / ${cap}`} sub="First session" /> : null}
          {counters ? <Metric label="Gross" value={usd(gross)} sub="Before fees and refunds. What you'll be paid is in Settlement." /> : null}
          {event.status === "live" ? <Metric label="Sessions" value={event.sessions.length} sub={first ? MANIFEST_COPY[manifestState(first, openManifestSessionIds.has(first.sessionId))] : undefined} /> : <Metric label="Sessions" value={event.sessions.length} />}
        </div>
      </header>

      {editor ? <LargerScreenBanner /> : null}

      <div className="grid gap-6 lg:grid-cols-2">
        <Panel title="Status" eyebrow="Advance status">
          {next ? (
            <div className="space-y-3">
              <p className="text-sm">
                Next step: <strong>{STATUS_LABEL[next]}</strong> — {STATUS_HELP[next]}
              </p>
              <p className="text-sm text-muted">You can&apos;t move an event backwards.</p>
              {next === "on_sale" ? <p className="text-sm text-muted">On-sale starts when you set it to On sale. Scheduling isn&apos;t available yet.</p> : null}
              {blocker ? (
                <p className="border border-warning bg-warning/10 px-3 py-2 text-sm text-warning">{blocker}</p>
              ) : editor && ctx.writesEnabled === false ? (
                <p className="text-sm text-dim">Status changes are not available in database mode: the write path (catalog.set_event_status / publish_event) is not wired in this slice. Nothing you see here is a saved change.</p>
              ) : editor ? (
                <form method="get" action={withPreview(self, ctx)} className="hidden space-y-2 lg:block">
                  <input type="hidden" name="did" value="catalog.set_event_status" />
                  <PreviewHidden ctx={ctx} />
                  <AuditNote rpc="catalog.set_event_status" />
                  <button className="btn btn-primary btn-sm" type="submit">
                    Set to {STATUS_LABEL[next]}
                  </button>
                </form>
              ) : (
                <p className="text-sm text-dim">Your role can view this event but not change its status.</p>
              )}
            </div>
          ) : (
            <p className="text-sm text-muted">{event.status === "cancelled" ? "This event was cancelled. Nothing was deleted." : "This event is complete. Sales are closed."}</p>
          )}
        </Panel>

        <Panel title="Sessions" eyebrow="Capacity is per session" action={editor && ctx.writesEnabled !== false && mode !== "locked" ? <span className="hidden text-xs text-dim lg:inline">Add session → catalog.create_event_session</span> : null}>
          <ul className="divide-y divide-line-neutral">
            {event.sessions.map((s) => {
              const hb = doorHoldback(batches, s.sessionId);
              return (
                <li key={s.sessionId} className="py-3">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div>
                      <p className="font-bold">{s.label ?? venueTime(s.startsAt, timeZone, { date: true, zone: false })}</p>
                      <p className="text-xs text-muted">
                        Starts {venueTime(s.startsAt, timeZone)}
                        {s.doorsAt ? ` · Doors ${venueTime(s.doorsAt, timeZone, { date: false, zone: true })}` : " · Doors time not set"}
                      </p>
                    </div>
                    <StatusPill status={s.status} />
                  </div>
                  <p className="mt-1 text-xs text-dim">{MANIFEST_COPY[manifestState(s, openManifestSessionIds.has(s.sessionId))]}</p>
                  {counters && hb.total > 0 ? (
                    <p className="mt-1 text-xs text-muted">
                      Held back for the door: <strong>{hb.door} of {hb.total}</strong>
                    </p>
                  ) : null}
                </li>
              );
            })}
          </ul>
        </Panel>

        <Panel title="Ticket types" eyebrow="What MVP has, said plainly">
          {types.length === 0 ? (
            <p className="text-sm text-muted">No ticket types yet.</p>
          ) : (
            <ul className="divide-y divide-line-neutral text-sm">
              {types.map((t) => (
                <li key={t.ticketTypeId} className="flex items-center justify-between py-2">
                  <span>
                    {t.name} <span className="text-dim">· {t.kind === "table" ? "Table" : "Admission"} · {t.visibility.replace("_", " ")}</span>
                  </span>
                  <span className="tabular-nums">{usd(t.priceMinor)}</span>
                </li>
              ))}
            </ul>
          )}
          <ul className="mt-3 space-y-1 text-xs text-muted">
            <li>Tiers are separate ticket types today. Turn the next one public when the first sells out.</li>
            <li>Snatch It handles the deposit. The balance at the table settles with you, off-platform.</li>
            <li>Purchase limit: 8 per person (set by Snatch It).</li>
          </ul>
          <Link className="link mt-3 inline-block text-sm" href={withPreview(`${self}/inventory`, ctx)}>
            Open inventory →
          </Link>
        </Panel>

        {canReadResalePolicy(ctx.role) ? (
          <Panel title="Resale policy" eyebrow="Per event · versioned">
            <p className="text-sm">
              In force: <strong>{RESALE_LABEL[event.resaleMode]}</strong>
            </p>
            <p className="mt-1 text-sm text-muted">Resale is off unless you turn it on.</p>
            <p className="mt-1 text-sm text-muted">Tickets already listed keep the policy they were listed under.</p>
            {editor && ctx.writesEnabled !== false ? <p className="mt-2 hidden text-xs text-dim lg:block">Change → catalog.set_resale_policy (creates a new version, never an edit)</p> : null}
          </Panel>
        ) : null}
      </div>

      {editor && ctx.writesEnabled !== false && event.status !== "cancelled" && event.status !== "completed" ? (
        <Panel title="Danger zone" eyebrow="Cancel event">
          <p className="text-sm text-muted">
            Cancelling shows the blast radius as counts before the confirm enables: sessions to cancel · tickets to void · orders to refund · open listings and transfers to cancel. A reason code and typing the event title are required. Nothing is deleted.
          </p>
          <p className="mt-2 text-xs text-dim">Preview: the blast-radius read is not contracted (spec Δ11 covers the door; cancel reads the tables directly). This control is intentionally not offered here.</p>
        </Panel>
      ) : null}
    </div>
  );
}

/** Keeps role/state through GET forms (the switchers live in the strip; forms must not drop them). */
export function PreviewHidden({ ctx }: { ctx: PreviewContext }) {
  return (
    <>
      {ctx.role !== "venue_manager" ? <input type="hidden" name="role" value={ctx.role} /> : null}
      {ctx.state !== "live" ? <input type="hidden" name="state" value={ctx.state} /> : null}
    </>
  );
}

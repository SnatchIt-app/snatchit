import { STATUS_HELP, STATUS_LABEL, nextStatus, publishBlocker, RESALE_LABEL } from "@/lib/events";
import { doorHoldback, sessionTotals } from "@/lib/inventory";
import { usd, venueTime } from "@/lib/format";
import { withPreview, type PreviewContext } from "@/lib/preview";
import { canEditEvents, canReadResalePolicy, showCounters } from "@/lib/roles";
import { MANIFEST_COPY, manifestState } from "@/lib/door";
import type { Event, InventoryBatch, TicketType } from "@/lib/types";
import { AuditNote, StatusPill } from "@/components/ui/Bits";
import { LargerScreenBanner } from "@/components/ui/State";
import { Action, ArrowLink, Block, Detail, Facts, Row, Rows } from "@/components/ui/Page";

/** Spec §7.3–§7.9 — event detail: header counters, sessions, advance status, resale policy, danger zone. */
export function EventSetup({ event, types, batches, ctx, basePath, timeZone, openManifestSessionIds }: { event: Event; types: TicketType[]; batches: InventoryBatch[]; ctx: PreviewContext; basePath: string; timeZone: string; openManifestSessionIds: Set<string> }) {
  const editor = canEditEvents(ctx.role);
  const next = nextStatus(event.status);
  const blocker = next === "on_sale" ? publishBlocker(types, batches) : null;
  const counters = showCounters(ctx.role, ctx);
  const first = event.sessions[0];
  const totals = first ? types.map((t) => sessionTotals(batches, t.ticketTypeId, first.sessionId)) : [];
  const sold = totals.reduce((n, t) => n + t.sold, 0);
  const cap = totals.reduce((n, t) => n + t.capacity, 0);
  const gross = types.reduce((n, t) => n + t.priceMinor * (first ? sessionTotals(batches, t.ticketTypeId, first.sessionId).sold : 0), 0);
  const self = `${basePath}/events/${event.eventId}`;

  // The page adapts to where the event is: getting ready, running, or finished.
  const phase: "prepare" | "running" | "finished" = event.status === "live" ? "running" : event.status === "completed" || event.status === "cancelled" ? "finished" : "prepare";
  const liveSession = event.sessions.find((x) => x.status === "live") ?? first;

  const statusAction =
    phase === "running" && liveSession ? (
      <Action href={withPreview(`${self}/door`, ctx)}>Open check-in</Action>
    ) : blocker ? null : editor && ctx.writesEnabled !== false && next ? (
      <form method="get" action={withPreview(self, ctx)} className="hidden lg:block">
        <input type="hidden" name="did" value="catalog.set_event_status" />
        <PreviewHidden ctx={ctx} />
        <button className="btn btn-primary" type="submit">
          Set to {STATUS_LABEL[next]}
        </button>
      </form>
    ) : null;

  return (
    <>
      {/* 1. Where this event is, and the single thing to do next. */}
      <Block id="status">
        <p className="eyebrow-accent">{phase === "running" ? "Happening now" : phase === "finished" ? "Finished" : "Getting ready"}</p>
        <p className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-2">
          <StatusPill status={event.status} />
          <span className="text-base text-muted">{STATUS_HELP[event.status]}</span>
        </p>
        {next ? (
          <p className="mt-4 max-w-2xl text-base leading-relaxed">
            Next step: <strong>{STATUS_LABEL[next]}</strong> — {STATUS_HELP[next]} You can&apos;t move an event backwards.
          </p>
        ) : (
          <p className="mt-4 max-w-2xl text-base leading-relaxed text-muted">{event.status === "cancelled" ? "This event was cancelled. Nothing was deleted." : "This event is complete. Sales are closed."}</p>
        )}
        {blocker ? <p className="mt-4 max-w-2xl border-l-2 border-warning bg-warning/5 py-2 pl-3 text-base text-warning">{blocker}</p> : null}
        {statusAction ? <div className="mt-5">{statusAction}</div> : null}
        {editor && ctx.writesEnabled !== false && next && !blocker ? (
          <div className="mt-3 max-w-2xl">
            <AuditNote />
          </div>
        ) : null}
        {!editor ? <p className="mt-3 text-sm text-dim">Your role can view this event but not change its status.</p> : null}
        {editor && ctx.writesEnabled === false && next ? (
          <p className="mt-3 max-w-2xl text-sm text-dim">Status changes are not available in database mode: the write path is not wired in this slice. Nothing you see here is a saved change.</p>
        ) : null}
        {editor ? <div className="mt-4"><LargerScreenBanner /></div> : null}
      </Block>

      {/* 2. The numbers, defined, once. */}
      {counters ? (
        <Block title={phase === "finished" ? "How it went" : "Where sales are"} id="numbers">
          <Facts
            items={[
              { label: "Sold of capacity", value: `${sold} of ${cap}`, meaning: "Tickets sold for the first session, against what that session holds." },
              { label: "Ticket sales", value: usd(gross), meaning: "Face value of what sold, before fees and before any refunds. This is not what you get paid — the payout screen that shows that is not built yet." },
            ]}
          />
          <p className="mt-4">
            <ArrowLink href={withPreview(`${self}/inventory`, ctx)}>Tickets and availability</ArrowLink>
          </p>
        </Block>
      ) : null}

      {/* 3. The nights. */}
      <Block title={event.sessions.length === 1 ? "The night" : "The nights"} lead="Each night has its own capacity." id="sessions">
        <Rows>
          {event.sessions.map((sx) => {
            const hb = doorHoldback(batches, sx.sessionId);
            return (
              <Row
                key={sx.sessionId}
                title={sx.label ?? venueTime(sx.startsAt, timeZone, { date: true, zone: false })}
                badge={<StatusPill status={sx.status} />}
                meta={
                  <>
                    Starts {venueTime(sx.startsAt, timeZone)}
                    {sx.doorsAt ? ` · Doors ${venueTime(sx.doorsAt, timeZone, { date: false, zone: true })}` : " · Doors time not set"}
                    {counters && hb.total > 0 ? ` · ${hb.door} of ${hb.total} held back for the door` : ""}
                  </>
                }
                right={<span className="text-sm text-dim">{MANIFEST_COPY[manifestState(sx, openManifestSessionIds.has(sx.sessionId))]}</span>}
              />
            );
          })}
        </Rows>
      </Block>

      {/* 4. What people can buy. */}
      <Block title="What people can buy" action={<ArrowLink href={withPreview(`${self}/inventory`, ctx)}>Tickets</ArrowLink>} id="types">
        {types.length === 0 ? (
          <p className="text-base text-muted">No ticket types yet. An event needs at least one before it can go on sale.</p>
        ) : (
          <Rows>
            {types.map((t) => (
              <Row
                key={t.ticketTypeId}
                title={t.name}
                meta={`${t.kind === "table" ? "Table" : "Admission"} · ${t.visibility.replace("_", " ")}`}
                right={<span className="tabular-nums text-base font-semibold">{usd(t.priceMinor)}</span>}
              />
            ))}
          </Rows>
        )}
      </Block>

      {/* 5. Everything else, out of the way but reachable. */}
      <div className="space-y-4">
        {canReadResalePolicy(ctx.role) ? (
          <Detail summary={`Can tickets be passed on? ${RESALE_LABEL[event.resaleMode]}`}>
            <p>Resale is off unless you turn it on. Tickets already listed keep the rules they were listed under.</p>
            {editor && ctx.writesEnabled !== false ? <p className="mt-2">Changing this writes a new version rather than editing the old one, so you can always see which rules a ticket was sold under.</p> : null}
          </Detail>
        ) : null}
        <Detail summary="Good to know about ticket types">
          <ul className="space-y-1">
            <li>Tiers are separate ticket types today. Turn the next one public when the first sells out.</li>
            <li>Snatch It handles the deposit on a table. The balance at the table settles with you, off-platform.</li>
            <li>Purchase limit: 8 per person, set by Snatch It.</li>
          </ul>
        </Detail>
        {editor && ctx.writesEnabled !== false && event.status !== "cancelled" && event.status !== "completed" ? (
          <Detail summary="Cancelling this event">
            <p>
              Before the confirm button turns on, cancelling shows you exactly what it would affect, as counts: sessions to cancel, tickets to void, orders to refund, and open resale listings and transfers to cancel. You also have to give a reason and type the event title. Nothing is deleted.
            </p>
            <p className="mt-2">Not offered in this demo, on purpose: the read that counts up what would be affected does not exist yet, and a cancel button that cannot show you the damage first is worse than no button.</p>
          </Detail>
        ) : null}
      </div>
    </>
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

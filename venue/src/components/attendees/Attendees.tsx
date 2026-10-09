import { EventHeader } from "@/components/ui/Event";
import { usd, venueTime } from "@/lib/format";
import { withPreview, type PreviewContext } from "@/lib/preview";
import { canManualLookup, canReadOrders, canSeeCheckIn, exportTemplate, rosterClasses, PRINCIPAL_LABEL } from "@/lib/roles";
import type { Event, EventSession, OrderRow, RosterRow } from "@/lib/types";
import { Chip, Panel } from "@/components/ui/Bits";
import { DeniedState, EmptyState, PartialCell } from "@/components/ui/State";
import { PreviewHidden } from "@/components/events/EventSetup";

const SOURCE_LABEL = { app: "App", web: "Web", door: "Door", promoter_link: "Promoter link" } as const;
const VIA_LABEL = { bought: "Bought", transferred: "Transferred to them", comp: "Comp" } as const;

function checkInText(r: RosterRow, tz: string): { label: string; tone: "success" | "warning" | "danger" | "neutral" } {
  switch (r.checkIn.kind) {
    case "admitted":
      return { label: `Admitted ${venueTime(r.checkIn.at, tz, { date: false, zone: false })}`, tone: "success" };
    case "already_used":
      return { label: `Already used · first ${venueTime(r.checkIn.firstAt, tz, { date: false, zone: false })}`, tone: "warning" };
    case "refused":
      return { label: r.checkIn.result === "frozen" ? "Blocked — check-in list is open" : r.checkIn.result === "fraud_review" ? "Needs review" : "Not recognised", tone: "danger" };
    default:
      return { label: "Not scanned", tone: "neutral" };
  }
}

/**
 * Spec §9 — grain: the session. Holder view (default): one row per current
 * holder. Purchaser view: one row per order (MONEY). Column CLASSES are
 * role-held; a denied class is absent, not null. Export hidden below `lg`.
 */
export function Attendees({
  event,
  session,
  roster,
  orders,
  ctx,
  basePath,
  timeZone,
  filter,
  totalUnfiltered,
  rosterSampled = true,
  view,
}: {
  event: Event;
  session: EventSession;
  roster: RosterRow[];
  orders: OrderRow[];
  ctx: PreviewContext;
  basePath: string;
  timeZone: string;
  filter: { q?: string; checkIn?: string };
  totalUnfiltered: number;
  /** false when the demo has no invented guest list for this session (see lib/data.ts rosterIsSampled). */
  rosterSampled?: boolean;
  view: "holders" | "purchasers";
}) {
  const classes = rosterClasses(ctx.role);
  const self = `${basePath}/events/${event.eventId}/attendees`;
  const door = `${basePath}/events/${event.eventId}/door`;

  if (classes === null) {
    // Spec §9.3 / §9.7 — the denial names the alternative for door and box office.
    return (
      <DeniedState
        surface="The attendee list"
        roleLabel={PRINCIPAL_LABEL[ctx.role]}
        reason={canManualLookup(ctx.role) ? "Door roles check one ticket at a time at the door, rather than reading the whole guest list." : undefined}
        alternative={canManualLookup(ctx.role) ? { label: "Look up a single ticket instead", href: withPreview(`${door}#lookup`, ctx) } : undefined}
      />
    );
  }
  const hasContact = classes.includes("CONTACT");
  const hasOps = classes.includes("OPS");
  const hasMoney = classes.includes("MONEY") && canReadOrders(ctx.role);
  const tpl = exportTemplate(ctx.role);
  const filtered = !!filter.q || !!filter.checkIn;

  return (
    <div className="space-y-6 [&>header]:mb-2">
      <EventHeader
        eventTitle={event.title}
        title={view === "holders" ? "Guest list" : "Who paid"}
        meta={
          <span>
            {view === "holders"
              ? "Everyone holding a ticket for this night — not who bought it. A table of six shows six people."
              : "The orders behind the tickets. A ticket that was refunded shows as voided."}{" "}
            {session.label ?? venueTime(session.startsAt, timeZone)}
          </span>
        }
        actions={
        <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
          {hasMoney ? (
            <nav className="seg" aria-label="List view">
              <a href={withPreview(self, ctx)} aria-current={view === "holders" ? "page" : undefined}>
                Guests
              </a>
              <a href={withPreview(`${self}?view=purchasers`, ctx)} aria-current={view === "purchasers" ? "page" : undefined}>
                Orders
              </a>
            </nav>
          ) : null}
          {tpl ? (
            <form method="get" action={self} className="hidden lg:block">
              <input type="hidden" name="did" value={`venue.request_export (${tpl})`} />
              <PreviewHidden ctx={ctx} />
              <button className="btn btn-ghost btn-sm" type="submit" title="The file is prepared in the background. When you come back to download it, your permission is checked again.">
                Download {tpl === "operations_v1" ? "the list your role can see" : "the contact list"}
              </button>
            </form>
          ) : null}
          </div>
        }
      />

      {view === "holders" ? (
        <>
          {/* Search sticky on md/sm; filters from a closed set. */}
          <form method="get" action={self} role="search" className="panel sticky top-[4.5rem] z-20 flex flex-wrap gap-2 p-2 md:static">
            <PreviewHidden ctx={ctx} />
            <input className="field flex-1 touch-row md:min-h-0" name="q" placeholder="Name, order ref, or exact email" defaultValue={filter.q ?? ""} aria-label="Search attendees" />
            {hasOps ? (
              <select className="field !w-auto" name="checkIn" defaultValue={filter.checkIn ?? ""} aria-label="Check-in filter">
                <option value="">Any check-in</option>
                <option value="not_scanned">Not scanned</option>
                <option value="admitted">Admitted</option>
              </select>
            ) : null}
            <button className="btn btn-ghost btn-sm" type="submit">
              Filter
            </button>
          </form>

          {totalUnfiltered === 0 && rosterSampled === false ? (
            <EmptyState title="The sample data doesn't include a guest list for this night.">
              <p className="max-w-prose text-sm text-muted">
                The demo invents ticket holders for one night only — Saturday Music Night. Sold counts shown elsewhere for this event are sample figures with no invented people behind them. It is not telling you that nobody bought.
              </p>
            </EmptyState>
          ) : totalUnfiltered === 0 ? (
            <EmptyState title="No tickets sold for this session yet." />
          ) : roster.length === 0 ? (
            <EmptyState title="No attendees match these filters.">
              <a className="btn btn-ghost btn-sm" href={withPreview(self, ctx)}>
                Clear filters
              </a>
            </EmptyState>
          ) : (
            <>
              {/* xl / lg table */}
              <div className="hidden overflow-x-auto md:block">
                <table className="data-table">
                  <thead>
                    <tr>
                      <th>Ref</th>
                      <th>Name</th>
                      <th className="num">Held</th>
                      {hasOps ? <th>Ticket types</th> : null}
                      {hasOps ? <th className="hidden xl:table-cell">Source</th> : null}
                      {hasOps ? <th className="hidden xl:table-cell">Acquired via</th> : null}
                      {hasOps ? <th>Check-in</th> : null}
                      {hasOps ? <th className="hidden lg:table-cell">Promoter</th> : null}
                      {hasContact ? <th>Email</th> : null}
                    </tr>
                  </thead>
                  <tbody>
                    {roster.map((r) => {
                      const ci = checkInText(r, timeZone);
                      return (
                        <tr key={r.customerRef}>
                          <td className="font-mono text-xs text-muted">{r.customerRef}</td>
                          <td>
                            {r.name} {r.isPurchaser ? <Chip tone="info">purchaser</Chip> : null}
                          </td>
                          <td className="num">{r.ticketsHeld}</td>
                          {hasOps ? <td>{r.ticketTypes.join(", ")}</td> : null}
                          {hasOps ? <td className="hidden xl:table-cell">{SOURCE_LABEL[r.source]}</td> : null}
                          {hasOps ? <td className="hidden xl:table-cell">{VIA_LABEL[r.acquiredVia]}</td> : null}
                          {hasOps ? (
                            <td>
                              <Chip tone={ci.tone}>{ci.label}</Chip>
                            </td>
                          ) : null}
                          {hasOps ? <td className="hidden lg:table-cell">{r.promoter ? `${r.promoter.name} · ${r.promoter.code}` : <PartialCell why="No promoter attribution" />}</td> : null}
                          {hasContact ? <td className="text-muted">{r.email ?? <span className="text-dim">—</span>}</td> : null}
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
              {/* md / sm card list, 56px rows */}
              <ul className="space-y-2 md:hidden">
                {roster.map((r) => {
                  const ci = checkInText(r, timeZone);
                  return (
                    <li key={r.customerRef} className="touch-row panel p-4">
                      <div className="flex items-center justify-between gap-2">
                        <p className="font-bold">{r.name}</p>
                        {hasOps ? <Chip tone={ci.tone}>{ci.label}</Chip> : null}
                      </div>
                      <p className="text-xs text-muted">
                        {r.ticketTypes.join(", ")} · {r.ticketsHeld} held
                      </p>
                      {hasMoney ? <p className="text-xs text-dim">{r.isPurchaser ? "Purchaser" : "Holder only"}</p> : null}
                    </li>
                  );
                })}
              </ul>
              {hasContact ? <p className="text-xs text-dim">Email is blank when the buyer didn&apos;t agree to share it with this organization.</p> : null}
              {!canSeeCheckIn(ctx.role) ? <p className="text-xs text-dim">Your role sees money and counts, never contact detail or check-in.</p> : null}
            </>
          )}
        </>
      ) : (
        <Panel title="Orders" eyebrow="Purchaser view · money">
          {orders.length === 0 ? (
            <p className="text-sm text-muted">No orders yet.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Order ref</th>
                    <th>Buyer</th>
                    <th>Status</th>
                    <th>Items</th>
                    <th className="num">Total</th>
                    <th className="num">Refunded to date</th>
                    <th>Tickets</th>
                    <th>Payment ref</th>
                  </tr>
                </thead>
                <tbody>
                  {orders.map((o) => (
                    <tr key={o.orderRef}>
                      <td className="font-mono text-xs">{o.orderRef}</td>
                      <td>
                        {o.buyerName} <span className="font-mono text-xs text-dim">{o.customerRef}</span>
                      </td>
                      <td>
                        <Chip tone={o.status === "paid" ? "success" : o.status === "refunded" ? "danger" : "warning"}>{o.status.replace("_", " ")}</Chip>
                      </td>
                      <td>{o.items.map((i) => `${i.qty} × ${i.ticketType} @ ${usd(i.unitPriceMinor)}`).join("; ")}</td>
                      <td className="num tabular-nums">{usd(o.totalMinor)}</td>
                      <td className="num tabular-nums">{o.refundedToDateMinor > 0 ? usd(o.refundedToDateMinor) : "—"}</td>
                      <td>{o.ticketsVoided > 0 ? <Chip tone="danger">{o.ticketsVoided} voided</Chip> : <span className="text-dim">—</span>}</td>
                      <td>{o.paymentRefPresent ? "present" : <PartialCell why="Couldn't load payment detail — refund disabled" />}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          <p className="mt-3 text-xs text-dim">A refunded order&apos;s tickets read &ldquo;Voided&rdquo;, never &ldquo;refunded&rdquo;. Refunds are initiated by your organization&apos;s owner or finance role; venue managers can see orders but cannot issue them.</p>
        </Panel>
      )}

      <p className="text-xs text-dim">
        Never on this list: phone, legal name, payment identifiers, transfer counterparty, any demographic value. Ticket holder mix (the aggregate card) is not part of this preview.
        {filtered ? " · filters applied" : ""}
      </p>
    </div>
  );
}

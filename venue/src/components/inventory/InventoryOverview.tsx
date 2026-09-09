import { RELEASE_LABEL, availability, capacityFloor, doorHoldback, inventoryWarnings, remaining, sessionTotals, warningLabel } from "@/lib/inventory";
import { usd, venueTime, relative } from "@/lib/format";
import { withPreview, type PreviewContext } from "@/lib/preview";
import { canChangeCapacity, canReadHolds, canReleaseHold, inventoryView } from "@/lib/roles";
import type { Event, InventoryBatch, InventoryHold, TicketType } from "@/lib/types";
import { AuditNote, CapacityBar, Chip, Panel } from "@/components/ui/Bits";
import { EmptyState, LargerScreenBanner } from "@/components/ui/State";
import { PreviewHidden } from "@/components/events/EventSetup";

/**
 * Spec §8 — xl: matrix (types down, releases across) · lg: one table per type ·
 * md/sm: read-only status cards with a segmented capacity bar. Holds beside.
 * Counters are staff-scoped; `remaining` is world-readable (note 4).
 */
export function InventoryOverview({ event, types, batches, holds, ctx, basePath, timeZone, now }: { event: Event; types: TicketType[]; batches: InventoryBatch[]; holds: InventoryHold[]; ctx: PreviewContext; basePath: string; timeZone: string; now: Date }) {
  const view = inventoryView(ctx.role);
  const session = event.sessions[0];
  const self = `${basePath}/events/${event.eventId}/inventory`;
  const releases = (["public_sale", "presale", "promoter_hold", "comp", "door"] as const).filter((k) => batches.some((b) => b.releaseKind === k));
  const liveIds = new Set(event.sessions.filter((s) => s.status === "live").map((s) => s.sessionId));
  const warnings = inventoryWarnings(batches, types, holds, { liveSessionIds: liveIds, now });
  const hb = session ? doorHoldback(batches, session.sessionId) : { door: 0, total: 0 };

  if (types.length === 0) return <EmptyState title="No ticket types yet" />;
  if (batches.length === 0) return <EmptyState title="No releases yet — add one so this type can sell." />;

  return (
    <div className="space-y-6">
      <header>
        <p className="eyebrow text-dim">Inventory · {event.title}</p>
        <h1 className="text-2xl font-bold">Ticket types &amp; inventory</h1>
        {session ? <p className="mt-1 text-sm text-muted">Session {session.label ?? venueTime(session.startsAt, timeZone)} · capacity is per session</p> : null}
      </header>

      {canChangeCapacity(ctx.role) ? <LargerScreenBanner /> : null}

      {view === "counters" && warnings.length > 0 ? (
        <Panel title="Inventory warnings" eyebrow="One row per release and condition">
          <ul className="divide-y divide-line-neutral text-sm">
            {warnings.map((w) => (
              <li key={`${w.batchId}-${w.kind}`} className="flex flex-wrap items-center gap-2 py-2">
                <Chip tone={w.kind === "sold_out" ? "danger" : "warning"}>{warningLabel(w.kind)}</Chip>
                <span className="font-bold">{w.ticketTypeName}</span>
                <span className="text-dim">· {w.release}</span>
                <span className="text-muted">— {w.detail}</span>
              </li>
            ))}
          </ul>
        </Panel>
      ) : null}

      {view === "counters" && hb.total > 0 ? (
        <p className="text-sm">
          <strong>Held back for the door: {hb.door} of {hb.total}</strong>
          <span className="text-muted"> — stock deliberately withheld from online sale so the box office has something to sell at 1 a.m.</span>
        </p>
      ) : null}

      {/* xl: matrix */}
      <div className="hidden overflow-x-auto xl:block">
        <table className="data-table">
          <thead>
            <tr>
              <th>Ticket type</th>
              <th className="num">Price</th>
              <th>Visibility</th>
              {releases.map((r) => (
                <th key={r}>{RELEASE_LABEL[r]}</th>
              ))}
              <th className="num">{view === "counters" ? "Sold / remaining" : "Available"}</th>
            </tr>
          </thead>
          <tbody>
            {types.map((t) => {
              const tot = session ? sessionTotals(batches, t.ticketTypeId, session.sessionId) : { capacity: 0, held: 0, sold: 0, remaining: 0 };
              return (
                <tr key={t.ticketTypeId}>
                  <td>
                    <span className="font-bold">{t.name}</span>
                    <span className="block text-xs text-dim">{t.kind === "table" ? "Table" : "Admission"}</span>
                  </td>
                  <td className="num tabular-nums">{usd(t.priceMinor)}</td>
                  <td className="text-muted">{t.visibility.replace("_", " ")}</td>
                  {releases.map((r) => {
                    const b = batches.find((x) => x.ticketTypeId === t.ticketTypeId && x.releaseKind === r && (!session || x.sessionId === session.sessionId));
                    if (!b) return <td key={r} className="text-dim">—</td>;
                    const rem = remaining(b);
                    const av = availability(b);
                    return (
                      <td key={r} className="min-w-44">
                        {view === "counters" ? (
                          <>
                            <CapacityBar capacity={b.capacity} held={b.held} sold={b.sold} remaining={rem} />
                            {av === "sold_out" ? <p className="mt-1 text-xs text-danger">Sold out.</p> : null}
                            {av === "all_held" ? <p className="mt-1 text-xs text-warning">Nothing available — everything is on hold. Release holds to put tickets back on sale.</p> : null}
                          </>
                        ) : (
                          <span className="tabular-nums">{rem} available</span>
                        )}
                      </td>
                    );
                  })}
                  <td className="num tabular-nums">{view === "counters" ? `${tot.sold} / ${tot.remaining}` : `${tot.remaining}`}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* lg: one table per ticket type */}
      <div className="hidden space-y-4 lg:block xl:hidden">
        {types.map((t) => (
          <Panel key={t.ticketTypeId} title={t.name} eyebrow={`${t.kind === "table" ? "Table" : "Admission"} · ${usd(t.priceMinor)} · ${t.visibility.replace("_", " ")}`}>
            <table className="data-table">
              <thead>
                <tr>
                  <th>Release</th>
                  {view === "counters" ? (
                    <>
                      <th className="num">Capacity</th>
                      <th className="num">Held</th>
                      <th className="num">Sold</th>
                    </>
                  ) : null}
                  <th className="num">Remaining</th>
                </tr>
              </thead>
              <tbody>
                {batches
                  .filter((b) => b.ticketTypeId === t.ticketTypeId)
                  .map((b) => (
                    <tr key={b.batchId}>
                      <td>{RELEASE_LABEL[b.releaseKind]}</td>
                      {view === "counters" ? (
                        <>
                          <td className="num">{b.capacity}</td>
                          <td className="num">{b.held}</td>
                          <td className="num">{b.sold}</td>
                        </>
                      ) : null}
                      <td className="num">{remaining(b)}</td>
                    </tr>
                  ))}
              </tbody>
            </table>
          </Panel>
        ))}
      </div>

      {/* md / sm: read-only status cards */}
      <ul className="space-y-3 lg:hidden">
        {types.map((t) => {
          const tot = session ? sessionTotals(batches, t.ticketTypeId, session.sessionId) : { capacity: 0, held: 0, sold: 0, remaining: 0 };
          const myWarnings = warnings.filter((w) => w.ticketTypeName === t.name);
          return (
            <li key={t.ticketTypeId} className="border border-line-neutral p-3">
              <div className="flex items-baseline justify-between">
                <p className="font-bold">{t.name}</p>
                <p className="tabular-nums text-muted">{usd(t.priceMinor)}</p>
              </div>
              {view === "counters" ? <div className="mt-2"><CapacityBar capacity={tot.capacity} held={tot.held} sold={tot.sold} remaining={tot.remaining} /></div> : <p className="mt-2 text-sm">{tot.remaining} available</p>}
              {view === "counters" && myWarnings.length > 0 ? (
                <ul className="mt-2 space-y-1 text-xs">
                  {myWarnings.map((w) => (
                    <li key={`${w.batchId}-${w.kind}`} className="text-warning">
                      {warningLabel(w.kind)} · {w.release} — {w.detail}
                    </li>
                  ))}
                </ul>
              ) : null}
            </li>
          );
        })}
      </ul>

      <div className="grid gap-6 lg:grid-cols-2">
        {view === "counters" ? (
          <Panel title="Capacity change" eyebrow="Guarded">
            <p className="text-sm text-muted">Changes are audited and refused below what is already held or sold. The floor for each release is shown before you type.</p>
            <ul className="mt-2 text-xs text-dim">
              {batches
                .filter((b) => !session || b.sessionId === session.sessionId)
                .map((b) => (
                  <li key={b.batchId}>
                    {types.find((t) => t.ticketTypeId === b.ticketTypeId)?.name} · {RELEASE_LABEL[b.releaseKind]}: you can&apos;t go below {capacityFloor(b)} — that&apos;s what&apos;s already held or sold.
                  </li>
                ))}
            </ul>
            <p className="mt-2 text-xs text-warning">Not offered in this preview: no capacity-change RPC is contracted (spec §20A.3 U-8). Creating a release is (venue.create_inventory_batch).</p>
          </Panel>
        ) : null}

        {canReadHolds(ctx.role) ? (
          <Panel title="Holds" eyebrow="venue.inventory_hold">
            {holds.filter((h) => h.status === "active").length === 0 ? (
              <p className="text-sm text-muted">No active holds</p>
            ) : (
              <ul className="divide-y divide-line-neutral text-sm">
                {holds
                  .filter((h) => h.status === "active")
                  .map((h) => {
                    const b = batches.find((x) => x.batchId === h.batchId);
                    const t = types.find((x) => x.ticketTypeId === b?.ticketTypeId);
                    const expired = new Date(h.expiresAt) <= now;
                    return (
                      <li key={h.holdId} className="flex flex-wrap items-center justify-between gap-2 py-2">
                        <div>
                          <p>
                            {h.holder} · <span className="tabular-nums">{h.quantity}</span> × {t?.name}
                          </p>
                          <p className="text-xs text-dim">
                            {RELEASE_LABEL[b?.releaseKind ?? "public_sale"]} · {h.kind} · {expired ? "expired" : `expires ${relative(h.expiresAt, now)}`}
                          </p>
                        </div>
                        {canReleaseHold(ctx.role) ? (
                          <form method="get" action={self} className="flex items-center gap-2">
                            <input type="hidden" name="did" value="venue.release_inventory_hold" />
                            <PreviewHidden ctx={ctx} />
                            <button className="btn btn-ghost btn-sm touch-row md:min-h-0" type="submit" title="Releasing this puts the tickets back on sale immediately.">
                              Release
                            </button>
                          </form>
                        ) : null}
                      </li>
                    );
                  })}
              </ul>
            )}
            {canReleaseHold(ctx.role) ? (
              <div className="mt-3">
                <AuditNote rpc="venue.release_inventory_hold" />
                <p className="mt-1 text-xs text-dim">Releasing this puts the tickets back on sale immediately. Double-release is a no-op.</p>
              </div>
            ) : null}
          </Panel>
        ) : null}
      </div>
      <p className="text-xs text-dim">
        Read-only link:{" "}
        <a className="link" href={withPreview(self, ctx)}>
          this view
        </a>
        . Shard rows are internal and never shown.
      </p>
    </div>
  );
}

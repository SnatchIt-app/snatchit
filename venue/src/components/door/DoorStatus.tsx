import { MANIFEST_COPY, REJECT_COPY, SCAN_RESULT_LABEL, WALLET_STALENESS_NOTE, effectiveFreeze, manifestAge, manifestState, normaliseReason } from "@/lib/door";
import { pct, relative, venueTime } from "@/lib/format";
import { withPreview, type PreviewContext } from "@/lib/preview";
import { canManagePins, canManualLookup, canOperateManifest, canReadFlagQueue, canReadScanBoard } from "@/lib/roles";
import type { DoorPin, Event, EventSession, FlagRow, ManifestEpisode, RosterRow, ScanCounters, ScanDevice } from "@/lib/types";
import { AuditNote, Chip, Panel } from "@/components/ui/Bits";
import { EmptyState } from "@/components/ui/State";
import { PreviewHidden } from "@/components/events/EventSetup";

/**
 * Spec §12 — the venue's view of the door, on the web. xl: three-pane
 * (sessions · live scan board · devices/PINs). md/sm: single column,
 * counter-first; manifest open/close is read-only status at `sm`.
 */
export function DoorStatus({
  event,
  session,
  pins,
  devices,
  episodes,
  scans,
  flags,
  lookup,
  ctx,
  basePath,
  timeZone,
  now,
}: {
  event: Event;
  session: EventSession;
  pins: DoorPin[];
  devices: ScanDevice[];
  episodes: ManifestEpisode[];
  scans: ScanCounters;
  flags: FlagRow[];
  lookup: { q: string; result: RosterRow | null } | null;
  ctx: PreviewContext;
  basePath: string;
  timeZone: string;
  now: Date;
}) {
  const self = `${basePath}/events/${event.eventId}/door`;
  const open = episodes.some((e) => e.closedAt === null);
  const ms = manifestState(session, open);
  const freeze = effectiveFreeze(session);
  const nonAdmit = scans.duplicate + scans.invalid + scans.frozen + scans.fraudReview;
  const maxBar = Math.max(1, ...scans.arrivalsPer5Min);

  const Counters = (
    <div>
      <p className="eyebrow text-dim">Admitted / issued</p>
      <p className="door-counter">
        {scans.admitted}
        <span className="text-dim"> / {scans.issued}</span>
      </p>
      <p className="mt-1 text-sm text-muted">
        {pct(scans.admitted, scans.issued)} · last scan {scans.lastScanAt ? relative(scans.lastScanAt, now) : "—"}
        {ctx.state === "error" ? " · stale" : ""}
      </p>
    </div>
  );

  const ScanBoard = (
    <Panel title="Live scan board" eyebrow="venue.scan">
      {scans.admitted === 0 && nonAdmit === 0 ? (
        <EmptyState title="No scans yet — doors haven't opened." />
      ) : (
        <>
          <div className="grid grid-cols-2 gap-2 md:grid-cols-5">
            {(
              [
                ["admitted", scans.admitted],
                ["duplicate", scans.duplicate],
                ["invalid", scans.invalid],
                ["frozen", scans.frozen],
                ["fraud_review", scans.fraudReview],
              ] as const
            ).map(([k, v]) => (
              <div key={k} className={`border p-2 ${k === "admitted" ? "border-success" : v > 0 ? "border-warning" : "border-line-neutral"}`}>
                <p className="text-[11px] uppercase tracking-wider text-dim">{SCAN_RESULT_LABEL[k]}</p>
                <p className="text-xl font-bold tabular-nums">{v}</p>
              </div>
            ))}
          </div>
          {scans.arrivalsPer5Min.length > 0 ? (
            <div className="mt-4">
              <p className="eyebrow text-dim">Arrivals per 5 minutes</p>
              <div className="mt-1 flex h-16 items-end gap-0.5" aria-label="Arrivals per five minutes">
                {scans.arrivalsPer5Min.map((n, i) => (
                  <span key={i} className="flex-1 bg-primary" style={{ height: `${(n / maxBar) * 100}%` }} title={`${n}`} />
                ))}
              </div>
            </div>
          ) : null}
          <ul className="mt-4 divide-y divide-line-neutral text-xs">
            {devices
              .filter((d) => d.status === "active")
              .map((d) => (
                <li key={d.deviceId} className="flex justify-between py-1">
                  <span>{d.label}</span>
                  <span className="tabular-nums text-muted">{d.admittedTonight} admitted</span>
                </li>
              ))}
          </ul>
        </>
      )}
    </Panel>
  );

  const Devices = (
    <Panel title="Devices" eyebrow="venue.scan_device">
      {devices.length === 0 ? (
        <p className="text-sm text-muted">No devices registered.</p>
      ) : (
        <ul className="divide-y divide-line-neutral text-sm">
          {devices.map((d) => {
            const age = manifestAge(d, now);
            return (
              <li key={d.deviceId} className="touch-row py-2">
                <div className="flex items-center justify-between gap-2">
                  <span className={d.status === "retired" ? "text-dim" : ""}>{d.label}</span>
                  {d.status === "retired" ? <Chip>retired</Chip> : d.online ? <Chip tone="success">online</Chip> : <Chip tone="warning">offline</Chip>}
                </div>
                {d.status === "active" ? (
                  <p className="text-xs text-muted">
                    Synced {age.minutes} min ago{age.stale ? <Chip tone="warning"> stale</Chip> : null} · queue {d.offlineQueueDepth} · last scan {d.lastScanAt ? relative(d.lastScanAt, now) : "—"}
                  </p>
                ) : null}
              </li>
            );
          })}
        </ul>
      )}
      <p className="mt-2 text-xs text-dim">Offline is a status, not an error. Register device → venue.register_scan_device.</p>
    </Panel>
  );

  const Pins = (
    <Panel title="Door PINs" eyebrow="venue.door_pin · never the hash">
      {pins.length === 0 ? (
        <p className="text-sm text-muted">No PINs for this session.</p>
      ) : (
        <ul className="divide-y divide-line-neutral text-sm">
          {pins.map((p) => (
            <li key={p.pinId} className="flex items-center justify-between gap-2 py-2">
              <div>
                <p className={p.status === "revoked" ? "text-dim line-through" : ""}>{p.label}</p>
                <p className="text-xs text-dim">Expires {venueTime(p.expiresAt, timeZone)}</p>
              </div>
              {p.status === "active" && canManagePins(ctx.role) ? (
                <form method="get" action={self} className="hidden lg:block">
                  <input type="hidden" name="did" value="venue.revoke_door_pin" />
                  <PreviewHidden ctx={ctx} />
                  <button className="btn btn-ghost btn-sm" type="submit">
                    Revoke
                  </button>
                </form>
              ) : p.status === "revoked" ? (
                <Chip tone="danger">revoked</Chip>
              ) : null}
            </li>
          ))}
        </ul>
      )}
      {canManagePins(ctx.role) ? (
        <div className="mt-3 hidden lg:block">
          <form method="get" action={self} className="flex gap-2">
            <input type="hidden" name="did" value="venue.create_door_pin" />
            <PreviewHidden ctx={ctx} />
            <input className="field" name="label" placeholder="Label, e.g. Main door iPad" aria-label="PIN label" />
            <button className="btn btn-primary btn-sm" type="submit">
              Issue PIN
            </button>
          </form>
          <p className="mt-2 text-xs text-dim">Write this down now. We can&apos;t show it again — we don&apos;t keep a copy you can read. PINs are session-scoped and expire by design; there is no resend.</p>
        </div>
      ) : null}
      <p className="mt-2 text-xs text-dim">A door PIN can never authorize a refund.</p>
    </Panel>
  );

  const Manifest = (
    <Panel title="Door manifest" eyebrow="catalog.event_session.door_open_at">
      <p className="font-bold">{MANIFEST_COPY[ms]}</p>
      <div className="mt-2 border border-line-neutral p-2 text-xs">
        <p className="eyebrow text-dim">Freeze status</p>
        <p className="mt-1">
          Transfers frozen since <strong>{venueTime(freeze.at, timeZone)}</strong> —{" "}
          {freeze.source === "manifest_open" ? "because the door manifest was opened." : "the doors-time backstop; no manifest was opened before doors."}
        </p>
      </div>
      {episodes.length > 0 ? (
        <ul className="mt-3 divide-y divide-line-neutral text-xs">
          {episodes.map((e) => (
            <li key={e.episodeId} className="py-1">
              Opened {venueTime(e.openedAt, timeZone, { date: false, zone: true })} by {e.openedBy}
              {e.closedAt ? ` · closed ${venueTime(e.closedAt, timeZone, { date: false, zone: false })}${e.reasonCode ? ` (${e.reasonCode})` : ""}` : " · open"} · {e.entryCount} entries · {e.admittedCount} admitted
            </li>
          ))}
        </ul>
      ) : null}
      {canOperateManifest(ctx.role) ? (
        <div className="mt-3">
          {/* md and above: operable; sm: read-only status (spec §3.3 rule 2) */}
          <form method="get" action={self} className="hidden md:block">
            <input type="hidden" name="did" value={open ? "venue.close_door_manifest" : "venue.open_door_manifest"} />
            <PreviewHidden ctx={ctx} />
            {!open ? <p className="mb-2 text-sm">Opening the door manifest stops ticket holders sending or reselling tickets for this session. Do it when doors open.</p> : <p className="mb-2 text-sm">Closing this episode does not reopen transfers.</p>}
            <p className="mb-2 text-xs text-warning">Blast-radius counts (pending transfers, active listings) are not available before the confirm: no dry-run read is contracted (spec Δ11). Shown after the fact only.</p>
            <AuditNote rpc={open ? "venue.close_door_manifest" : "venue.open_door_manifest"} />
            <button className="btn btn-primary btn-sm mt-2" type="submit">
              {open ? "Close manifest" : "Open door manifest"}
            </button>
          </form>
          <p className="text-xs text-dim md:hidden">Read-only on a phone. Opening the manifest freezes transfers for the whole session — not a phone-in-a-crowd action.</p>
        </div>
      ) : (
        <p className="mt-2 text-xs text-dim">Opening or closing the manifest is a manager action. Scanners scan against it; they never create it.</p>
      )}
    </Panel>
  );

  const Lookup = canManualLookup(ctx.role) ? (
    <Panel title="Manual lookup" eyebrow="One record · venue.validate_ticket_online + venue.lookup_attendee">
      <form method="get" action={self} id="lookup" className="flex gap-2">
        <PreviewHidden ctx={ctx} />
        <input className="field touch-row md:min-h-0" name="q" placeholder="Guest name, order ref, or ticket ref" defaultValue={lookup?.q ?? ""} aria-label="Lookup" />
        <button className="btn btn-primary btn-sm" type="submit">
          Look up
        </button>
      </form>
      {lookup ? (
        lookup.result ? (
          <div className="mt-3 border border-line-neutral p-3 text-sm">
            <p className="font-bold">{lookup.result.name}</p>
            <p className="text-xs text-muted">
              {lookup.result.ticketTypes.join(", ")} · {lookup.result.ticketsHeld} held · session {session.label ?? venueTime(session.startsAt, timeZone, { date: true, zone: false })}
            </p>
            <LookupVerdict row={lookup.result} timeZone={timeZone} />
          </div>
        ) : (
          <p className="mt-3 text-sm text-muted">No ticket matches that.</p>
        )
      ) : null}
      <p className="mt-2 text-xs text-dim">{WALLET_STALENESS_NOTE}</p>
      <p className="mt-1 text-xs text-dim">Single record only. No list mode, no export. Lookups are audited by query kind, never by the value.</p>
    </Panel>
  ) : null;

  const Flags = canReadFlagQueue(ctx.role) ? (
    <Panel title="Flag queue" eyebrow="Escalate, never resolve">
      {flags.length === 0 ? (
        <p className="text-sm text-muted">Nothing flagged.</p>
      ) : (
        <ul className="divide-y divide-line-neutral text-sm">
          {flags.map((f) => (
            <li key={f.scanId} className="py-2">
              <div className="flex flex-wrap items-center gap-2">
                <Chip tone={f.result === "fraud_review" ? "danger" : "warning"}>{SCAN_RESULT_LABEL[f.result]}</Chip>
                <span className="text-xs text-dim">
                  {venueTime(f.at, timeZone, { date: false, zone: false })} · {f.deviceLabel}
                </span>
                {f.escalated ? <Chip tone="info">escalated</Chip> : null}
              </div>
              <p className="mt-1 text-xs text-muted">{f.note}</p>
              {!f.escalated ? (
                <form method="get" action={self} className="mt-1 flex gap-2">
                  <input type="hidden" name="did" value="escalate (venue note on venue.scan; adjudication is platform_risk)" />
                  <PreviewHidden ctx={ctx} />
                  <input className="field" name="note" placeholder="What you saw at the door" aria-label="Escalation note" />
                  <button className="btn btn-ghost btn-sm" type="submit">
                    Escalate with a note
                  </button>
                </form>
              ) : null}
            </li>
          ))}
        </ul>
      )}
      <p className="mt-2 text-xs text-dim">Snatch It reviews these. Add what you saw at the door and we&apos;ll pick it up.</p>
    </Panel>
  ) : null;

  const Reasons = (
    <details className="border border-line-neutral p-3 text-xs">
      <summary className="cursor-pointer font-bold uppercase tracking-wider">Why a pass is refused (six reasons)</summary>
      <ul className="mt-2 space-y-1">
        {(Object.keys(REJECT_COPY) as (keyof typeof REJECT_COPY)[]).map((k) => (
          <li key={k}>
            <span className="font-mono text-dim">{k}</span> — {REJECT_COPY[k]}
          </li>
        ))}
      </ul>
    </details>
  );

  return (
    <div className="space-y-4">
      <header>
        <p className="eyebrow text-dim">Door · {event.title}</p>
        <h1 className="text-2xl font-bold">Door status</h1>
        <p className="mt-1 text-sm text-muted">
          Session {session.label ?? venueTime(session.startsAt, timeZone)} · doors {session.doorsAt ? venueTime(session.doorsAt, timeZone, { date: false, zone: true }) : "not set"}
        </p>
      </header>

      {/* xl: three panes */}
      <div className="hidden gap-4 xl:grid xl:grid-cols-[16rem_1fr_22rem]">
        <div className="space-y-4">
          <Panel title="Sessions" eyebrow="This event">
            <ul className="text-sm">
              {event.sessions.map((s) => (
                <li key={s.sessionId} className={s.sessionId === session.sessionId ? "font-bold" : "text-muted"}>
                  {s.label ?? venueTime(s.startsAt, timeZone, { date: true, zone: false })}
                </li>
              ))}
            </ul>
          </Panel>
          {Manifest}
        </div>
        <div className="space-y-4">
          {canReadScanBoard(ctx.role) ? (
            <>
              <div className="border border-line bg-card p-4">{Counters}</div>
              {ScanBoard}
            </>
          ) : null}
          {Lookup}
          {Flags}
          {Reasons}
        </div>
        <div className="space-y-4">
          {Devices}
          {Pins}
        </div>
      </div>

      {/* lg: two panes; md/sm: single column, counter-first */}
      <div className="space-y-4 xl:hidden">
        {canReadScanBoard(ctx.role) ? <div className="border border-line bg-card p-4">{Counters}</div> : null}
        <div className="grid gap-4 lg:grid-cols-[1fr_20rem]">
          <div className="space-y-4">
            {Devices}
            {Lookup}
            {Flags}
            {canReadScanBoard(ctx.role) ? ScanBoard : null}
            {Reasons}
          </div>
          <div className="space-y-4">
            {Manifest}
            <details className="border border-line-neutral lg:hidden">
              <summary className="cursor-pointer px-3 py-2 text-sm font-bold uppercase tracking-wider">Door PINs ({pins.filter((p) => p.status === "active").length} active)</summary>
              <div className="p-2">{Pins}</div>
            </details>
            <div className="hidden lg:block">{Pins}</div>
          </div>
        </div>
      </div>
      <p className="text-xs text-dim">
        This surface never goes offline; it reports device state. Nothing here caches a write.{" "}
        <a className="link" href={withPreview(self, ctx)}>
          Reload
        </a>
      </p>
    </div>
  );
}

/**
 * The admissibility answer comes from venue.validate_ticket_online (a read
 * that records nothing). The preview derives it from the fixture's latest
 * scan; `already_scanned` from the RPC and `duplicate` from the scan enum
 * both render as "Already used" (spec §22.5).
 */
function LookupVerdict({ row, timeZone }: { row: RosterRow; timeZone: string }) {
  const ci = row.checkIn;
  if (ci.kind === "not_scanned") return <p className="mt-2 text-success">Admit — pass is active ({normaliseReason("active")}).</p>;
  if (ci.kind === "admitted") return <p className="mt-2 text-warning">{REJECT_COPY[normaliseReason("already_scanned") as "duplicate"]} · admitted {venueTime(ci.at, timeZone, { date: false, zone: false })}</p>;
  if (ci.kind === "already_used") return <p className="mt-2 text-warning">{REJECT_COPY.duplicate} · first admit {venueTime(ci.firstAt, timeZone, { date: false, zone: false })}</p>;
  return (
    <p className="mt-2 text-danger">
      Refuse — {SCAN_RESULT_LABEL[ci.result]}.{ci.result === "invalid" ? ` ${REJECT_COPY.voided}` : ""}
    </p>
  );
}

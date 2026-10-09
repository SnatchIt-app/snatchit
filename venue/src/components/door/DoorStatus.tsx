import { MANIFEST_COPY, REJECT_COPY, REJECT_TITLE, SCAN_RESULT_LABEL, WALLET_STALENESS_NOTE, effectiveFreeze, manifestAction, manifestAge, manifestState, normaliseReason } from "@/lib/door";
import { pct, relative, venueTime } from "@/lib/format";
import { withPreview, type PreviewContext } from "@/lib/preview";
import { canManagePins, canManualLookup, canOperateManifest, canReadFlagQueue, canReadScanBoard } from "@/lib/roles";
import type { DoorPin, Event, EventSession, FlagRow, ManifestEpisode, RosterRow, ScanCounters, ScanDevice } from "@/lib/types";
import { AuditNote, Chip, Panel } from "@/components/ui/Bits";
import { EmptyState } from "@/components/ui/State";
import { PreviewHidden } from "@/components/events/EventSetup";
import { ArrivalsChart, EventHeader, Stats } from "@/components/ui/Event";

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
  // Audit follow-up U1 — the control is offered only where there is still a door.
  const action = manifestAction(session, ms);
  const freeze = effectiveFreeze(session);
  const nonAdmit = scans.duplicate + scans.invalid + scans.frozen + scans.fraudReview;
  const maxBar = Math.max(1, ...scans.arrivalsPer5Min);

  const counters = (
    <Stats
      label="At the door"
      items={[
        { label: "Admitted", value: scans.admitted, of: `of ${scans.issued} issued · ${pct(scans.admitted, scans.issued)}` },
        { label: SCAN_RESULT_LABEL.duplicate, value: scans.duplicate, tone: scans.duplicate > 0 ? "warn" : undefined },
        { label: SCAN_RESULT_LABEL.invalid, value: scans.invalid, tone: scans.invalid > 0 ? "warn" : undefined },
        { label: SCAN_RESULT_LABEL.frozen, value: scans.frozen, tone: scans.frozen > 0 ? "warn" : undefined },
        { label: SCAN_RESULT_LABEL.fraud_review, value: scans.fraudReview, tone: scans.fraudReview > 0 ? "danger" : undefined },
      ]}
    />
  );

  const ScanBoard = (
    <Panel title="Right now at the door" eyebrow={`Last scan ${scans.lastScanAt ? relative(scans.lastScanAt, now) : "—"}${ctx.state === "error" ? " · stale" : ""}`}>
      {scans.admitted === 0 && nonAdmit === 0 ? (
        <EmptyState title="No scans yet — doors haven't opened." />
      ) : (
        <>
          {scans.arrivalsPer5Min.length > 0 ? (
            <div>
              <p className="mb-3 text-[0.8125rem] text-muted">
                Arrivals every 5 minutes · peak <span className="font-semibold text-ink">{maxBar}</span>
              </p>
              <ArrivalsChart counts={scans.arrivalsPer5Min} now={now} timeZone={timeZone} />
            </div>
          ) : null}
          <ul className="mt-5 divide-y divide-line border-t border-line text-[0.875rem]">
            {devices
              .filter((d) => d.status === "active")
              .map((d) => (
                <li key={d.deviceId} className="flex justify-between py-2.5">
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
    <Panel title="Scanners in the room" eyebrow="Devices">
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
      <p className="mt-2 text-xs text-dim">Offline is a status, not an error. A new scanner has to be registered before it can admit anyone.</p>
    </Panel>
  );

  const Pins = (
    <Panel title="Door PINs" eyebrow="For staff scanning without a device">
      {pins.length === 0 ? (
        <p className="text-sm text-muted">No PINs for this session.</p>
      ) : (
        <ul className="divide-y divide-line-neutral text-sm">
          {pins.map((p) => (
            <li key={p.pinId} className="flex flex-wrap items-center justify-between gap-2 py-2">
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
    <Panel title="The list scanners work from" eyebrow="Also stops tickets being passed on">
      <p className="font-bold">{MANIFEST_COPY[ms]}</p>
      <div className="mt-2 border border-line-neutral p-2 text-xs">
        <p className="eyebrow text-dim">Freeze status</p>
        <p className="mt-1">
          Transfers frozen since <strong>{venueTime(freeze.at, timeZone)}</strong> —{" "}
          {freeze.source === "manifest_open" ? "because the check-in list was opened." : "automatically at doors time, because the list was never opened."}
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
        action.kind === "none" ? (
          <p className="mt-3 text-sm text-muted">{action.why}</p>
        ) : (
          <div className="mt-3">
            {/* md and above: operable; sm: read-only status (spec §3.3 rule 2) */}
            <form method="get" action={self} className="hidden md:block">
              <input type="hidden" name="did" value={action.kind === "close" ? "venue.close_door_manifest" : "venue.open_door_manifest"} />
              <PreviewHidden ctx={ctx} />
              {action.kind === "open" ? (
                <p className="mb-2 text-sm">Opening the check-in list stops ticket holders sending or reselling tickets for this night. Do it when doors open.</p>
              ) : (
                <p className="mb-2 text-sm">Closing this episode does not reopen transfers.</p>
              )}
              <p className="mb-2 text-xs text-warning">
                You cannot see the count of transfers and resale listings this would stop <em>before</em> you confirm — that read does not exist yet. The numbers appear afterwards.
              </p>
              <AuditNote />
              <button className="btn btn-primary btn-sm mt-2" type="submit">
                {action.kind === "close" ? "Close the check-in list" : "Open the check-in list"}
              </button>
            </form>
            <p className="text-xs text-dim md:hidden">Read-only on a phone. Opening it stops transfers for the whole night — not a phone-in-a-crowd decision.</p>
          </div>
        )
      ) : (
        <p className="mt-2 text-xs text-dim">Opening or closing this list is a manager&apos;s job. Scanners scan against it; they never create it.</p>
      )}
    </Panel>
  );

  const Lookup = canManualLookup(ctx.role) ? (
    <Panel title="Look up one guest" eyebrow="One at a time">
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
    <Panel title="Flagged at the door" eyebrow="You pass these on; you don't decide them">
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
    <details className="panel group px-5 py-4 text-[0.875rem] md:px-6">
      <summary className="flex min-h-9 items-center justify-between gap-3 rounded-lg font-medium">
        What to say when a pass is refused (six reasons)
        <svg aria-hidden="true" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" className="transition-transform group-open:rotate-180">
          <path d="M6 9l6 6 6-6" />
        </svg>
      </summary>
      <ul className="mt-3 space-y-2 text-muted">
        {(Object.keys(REJECT_COPY) as (keyof typeof REJECT_COPY)[]).map((k) => (
          <li key={k}>
            <strong>{REJECT_TITLE[k]}</strong> — {REJECT_COPY[k]}
          </li>
        ))}
      </ul>
    </details>
  );

  return (
    <div>
      <EventHeader
        eventTitle={event.title}
        title="Check-in"
        meta={
          <>
            <span>{session.label ?? venueTime(session.startsAt, timeZone)}</span>
            <span aria-hidden="true">·</span>
            <span>doors {session.doorsAt ? venueTime(session.doorsAt, timeZone, { date: false, zone: true }) : "not set"}</span>
            <span aria-hidden="true">·</span>
            <span>the screen for the people on the door</span>
          </>
        }
      >
        {canReadScanBoard(ctx.role) ? counters : null}
      </EventHeader>

      {/*
        One ordered column, not three panes rendered twice.
        The old layout built the whole screen twice — a three-pane xl version
        and a two-pane fallback — which is how the same panel ended up on the
        page in two places and why it read as a wall. Door staff want one
        order, and it is the same order on a phone and on a laptop:
        how many are in → what is happening → look someone up → what is stuck
        → the equipment → the list itself.
      */}
      <div className="enter-2 space-y-6">
        {canReadScanBoard(ctx.role) ? ScanBoard : null}
        {Lookup}
        {Flags}
        {Devices}
        {Pins}
        {Manifest}
        {Reasons}
      </div>

      <p className="mt-6 text-[0.75rem] text-dim">
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

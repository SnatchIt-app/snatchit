import Link from "next/link";
import { venueTime, relative } from "@/lib/format";
import { SEVERITY_LABEL, SEVERITIES, type ClearCheck, type DoorSummary, type Signal } from "@/lib/signals";
import { STATUS_LABEL } from "@/lib/events";
import { withPreview, type PreviewContext } from "@/lib/preview";
import type { Event } from "@/lib/types";
import { StatusPill } from "@/components/ui/Bits";

/**
 * The venue landing page (audit §W1).
 *
 * One question, answered top to bottom: what needs me now, then what is
 * happening tonight, then everything else. Nothing here is a control — every
 * item ends in a link to the screen where the work is actually done — so a
 * manager cannot cause anything from the overview by accident.
 */
export function Tonight({
  signals,
  clear,
  door,
  events,
  available,
  ctx,
  basePath,
  timeZone,
  now,
}: {
  signals: Signal[];
  clear: ClearCheck[];
  door: DoorSummary | null;
  events: Event[];
  available: number;
  ctx: PreviewContext;
  basePath: string;
  timeZone: string;
  now: Date;
}) {
  const link = (href: string) => withPreview(href, ctx);
  const upcoming = [...events]
    .filter((e) => e.status !== "completed" && e.status !== "cancelled")
    .map((e) => ({ e, s: [...e.sessions].sort((a, b) => a.startsAt.localeCompare(b.startsAt))[0] }))
    .sort((a, b) => (a.s?.startsAt ?? "").localeCompare(b.s?.startsAt ?? ""))
    .slice(0, 4);

  return (
    <div className="space-y-6">
      <section aria-labelledby="needs-you">
        <h2 id="needs-you" className="text-lg font-bold">
          What needs you
        </h2>
        {signals.length === 0 ? (
          <p className="mt-2 border border-success/40 bg-success/5 p-4 text-sm">
            <strong>Nothing needs you right now.</strong> Every check below ran and found nothing.
          </p>
        ) : (
          SEVERITIES.map((sev) => {
            const group = signals.filter((s) => s.severity === sev);
            if (group.length === 0) return null;
            return (
              <div key={sev} className="mt-3">
                <p className="eyebrow text-dim">{SEVERITY_LABEL[sev]}</p>
                <ul className="mt-1 space-y-2">
                  {group.map((s) => (
                    <SignalCard key={s.id} signal={s} />
                  ))}
                </ul>
              </div>
            );
          })
        )}
        {clear.length > 0 ? (
          <details className="mt-3 border border-line-neutral">
            <summary className="px-3 py-2 text-sm text-muted">{clear.length} other checks are clear</summary>
            <ul className="border-t border-line-neutral px-3 py-2 text-sm text-muted">
              {clear.map((c) => (
                <li key={c.id} className="py-0.5">
                  {c.label}
                </li>
              ))}
            </ul>
          </details>
        ) : null}
      </section>

      {door ? (
        <section aria-labelledby="tonight-door" className="border border-line bg-card">
          <header className="border-b border-line px-4 py-3">
            <p className="eyebrow text-dim">Happening tonight</p>
            <h2 id="tonight-door" className="text-base font-bold">
              {door.eventTitle}
              {door.sessionLabel ? <span className="font-normal text-muted"> · {door.sessionLabel}</span> : null}
            </h2>
          </header>
          <div className="grid gap-4 p-4 [grid-template-columns:repeat(auto-fit,minmax(min(11rem,100%),1fr))]">
            <Figure value={`${door.admitted}`} label="People inside" meaning={`Scanned in so far, out of ${door.expected} tickets issued for tonight.`} />
            <Figure value={`${Math.max(0, door.expected - door.admitted)}`} label="Still to arrive" meaning="Tickets issued that have not been scanned yet." />
            <Figure value={`${door.devicesOnline} of ${door.devicesTotal}`} label="Scanners online" meaning="A scanner that is offline keeps working from the list it already downloaded." />
          </div>
          <div className="flex flex-wrap items-center gap-3 border-t border-line-neutral px-4 py-3 text-sm">
            <span className="text-muted">
              {door.doorsAt ? `Doors ${venueTime(door.doorsAt, timeZone, { date: false, zone: false })} · ` : ""}
              starts {venueTime(door.startsAt, timeZone, { date: false, zone: true })} ({relative(door.startsAt, now)})
            </span>
            <Link className="btn btn-primary btn-sm ml-auto" href={link(`${basePath}/events/${door.eventId}/door`)}>
              Open the door screen
            </Link>
          </div>
        </section>
      ) : null}

      <section aria-labelledby="coming-up">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <h2 id="coming-up" className="text-lg font-bold">
            Coming up
          </h2>
          <Link className="link inline-flex min-h-6 items-center text-sm" href={link(`${basePath}/events`)}>
            See all events
          </Link>
        </div>
        <p className="mt-1 text-sm text-muted">
          {available.toLocaleString()} tickets are still available across everything on sale right now. <span className="text-dim">Counted at this moment, not a total for the week.</span>
        </p>
        <ul className="mt-2 divide-y divide-line-neutral border border-line-neutral">
          {upcoming.map(({ e, s }) => (
            <li key={e.eventId} className="flex flex-wrap items-center gap-x-3 gap-y-1 px-3 py-2.5">
              <Link className="link inline-flex min-h-6 items-center font-semibold" href={link(`${basePath}/events/${e.eventId}`)}>
                {e.title}
              </Link>
              <StatusPill status={e.status} />
              <span className="ml-auto text-sm text-muted">{s ? `${venueTime(s.startsAt, timeZone, { date: true, zone: false })} · ${relative(s.startsAt, now)}` : STATUS_LABEL[e.status]}</span>
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}

const TONE: Record<Signal["severity"], string> = {
  act_now: "border-danger/60 bg-primary-soft",
  soon: "border-warning/50 bg-warning/5",
  worth_knowing: "border-line-neutral bg-card",
};

function SignalCard({ signal }: { signal: Signal }) {
  return (
    <li className={`border p-3 ${TONE[signal.severity]}`}>
      <p className="font-bold">{signal.title}</p>
      <p className="mt-1 text-sm text-muted">{signal.consequence}</p>
      <Link className="btn btn-ghost btn-sm mt-2" href={signal.action.href}>
        {signal.action.label}
      </Link>
    </li>
  );
}

/** A number never appears without the sentence that says what it counts. */
function Figure({ value, label, meaning }: { value: string; label: string; meaning: string }) {
  return (
    <div>
      <p className="text-3xl font-extrabold tabular-nums">{value}</p>
      <p className="font-semibold">{label}</p>
      <p className="mt-0.5 text-sm text-muted">{meaning}</p>
    </div>
  );
}

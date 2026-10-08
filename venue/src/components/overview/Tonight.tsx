import Link from "next/link";
import { venueTime, relative, usd } from "@/lib/format";
import type { ClearCheck, DoorSummary, Severity, Signal, Stage, StageView } from "@/lib/signals";
import { STATUS_LABEL } from "@/lib/events";
import { withPreview, type PreviewContext } from "@/lib/preview";
import type { Event, EventStatus } from "@/lib/types";
import { Icon } from "@/components/ui/Icon";

/**
 * Today — the venue's landing page.
 *
 * Three questions, answered in this order and nothing before them:
 *   1. Where am I?               the event the venue is living through, in the
 *                                hero, with its stage named
 *   2. What needs my attention?  beside it, worst first, each with one action
 *   3. What can I do next?       one dark pill in the hero; one small pill per
 *                                attention item
 * Supporting detail (ticket sales, what is coming up) sits below, in panels
 * of their own, so it never competes with the three answers.
 */
const STAGE_LABEL: Record<Stage, string> = {
  before: "Next up",
  during: "Happening now",
  after: "Last event",
};

const SEVERITY_CHIP: Record<Severity, { label: string; tone: string }> = {
  act_now: { label: "Now", tone: "badge-red" },
  soon: { label: "Soon", tone: "badge-amber" },
  worth_knowing: { label: "Worth knowing", tone: "badge-muted" },
};

export type SalesLine = { ticketTypeId: string; name: string; priceMinor: number; sold: number; capacity: number; remaining: number };

export function Tonight({
  signals,
  clear,
  door,
  stageView,
  events,
  available,
  ctx,
  basePath,
  timeZone,
  now,
  sales = [],
  countersVisible = true,
  arrivals = [],
  scanners,
}: {
  signals: Signal[];
  clear: ClearCheck[];
  door: DoorSummary | null;
  stageView: StageView;
  events: Event[];
  available: number;
  ctx: PreviewContext;
  basePath: string;
  timeZone: string;
  now: Date;
  /** Per ticket type, for the stage event's session. */
  sales?: SalesLine[];
  /** false when this role may only see what is still available. */
  countersVisible?: boolean;
  /** Admissions per five minutes, oldest first. */
  arrivals?: number[];
  /** Active scanners only — a retired device is not "offline". */
  scanners?: { online: number; total: number };
}) {
  const link = (href: string) => withPreview(href, ctx);
  const urgent = signals.filter((s) => s.severity !== "worth_knowing");
  const rest = signals.filter((s) => s.severity === "worth_knowing");
  const ev = stageView.event;
  const sess = stageView.session;
  const evBase = ev ? `${basePath}/events/${ev.eventId}` : basePath;
  const scan = scanners ?? (door ? { online: door.devicesOnline, total: door.devicesTotal } : null);

  const primary =
    stageView.stage === "during"
      ? { label: "Open check-in", href: link(`${evBase}/door`), icon: "scan" as const }
      : stageView.stage === "after"
        ? { label: "Review this event", href: link(evBase), icon: "arrow" as const }
        : { label: "Get this event ready", href: link(evBase), icon: "arrow" as const };
  const secondary =
    stageView.stage === "during"
      ? { label: "Guest list", href: link(`${evBase}/attendees`) }
      : stageView.stage === "after"
        ? { label: "Who came", href: link(`${evBase}/attendees`) }
        : { label: "Tickets", href: link(`${evBase}/inventory`) };

  const upcoming = [...events]
    .filter((e) => e.status !== "completed" && e.status !== "cancelled" && e.eventId !== ev?.eventId)
    .map((e) => ({ e, s: [...e.sessions].sort((a, b) => a.startsAt.localeCompare(b.startsAt))[0] }))
    .sort((a, b) => (a.s?.startsAt ?? "").localeCompare(b.s?.startsAt ?? ""))
    .slice(0, 4);

  const totalSold = sales.reduce((n, l) => n + l.sold, 0);
  const totalCap = sales.reduce((n, l) => n + l.capacity, 0);

  return (
    <div className="grid items-start gap-4 lg:grid-cols-12">
      {/* 1. Where am I — the event the venue is living through. */}
      {ev ? (
        <section aria-labelledby="stage-title" id="stage" className="panel flex min-w-0 flex-col p-5 md:p-7 lg:col-span-7 lg:row-start-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className="badge">
              {stageView.stage === "during" ? <span aria-hidden="true" className="live-dot" /> : null}
              {STAGE_LABEL[stageView.stage]}
            </span>
            {sess ? (
              <span className="text-[0.8125rem] text-muted">
                {stageView.stage === "after"
                  ? `Ran ${venueTime(sess.startsAt, timeZone, { date: true, zone: false })}`
                  : stageView.stage === "during"
                    ? `Started ${venueTime(sess.startsAt, timeZone, { date: false, zone: false })}${sess.doorsAt ? ` · doors ${venueTime(sess.doorsAt, timeZone, { date: false, zone: false })}` : ""}`
                    : `${venueTime(sess.startsAt, timeZone, { date: true, zone: false })} · ${relative(sess.startsAt, now)}`}
              </span>
            ) : null}
          </div>
          <h2 id="stage-title" className="title-display mt-4 text-[2rem] md:text-[2.5rem]">
            {ev.title}
          </h2>

          <div className="mt-5 flex flex-wrap items-center gap-2">
            <Link href={primary.href} className="btn btn-primary">
              <Icon name={primary.icon} size={16} />
              {primary.label}
            </Link>
            <Link href={secondary.href} className="btn btn-ghost">
              {secondary.label}
            </Link>
          </div>

          {stageView.stage === "during" && door ? (
            <div className="mt-7 grid gap-5 border-t border-line pt-6 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end sm:gap-6">
              <div>
                <p className="text-[0.8125rem] font-medium text-muted">People inside</p>
                <p className="mt-1 flex items-baseline gap-2">
                  <span className="title-display text-[3.5rem] tabular-nums md:text-[4rem]">{door.admitted}</span>
                  <span className="text-sm text-muted">of {door.expected}</span>
                </p>
                <div className="meter mt-3 max-w-sm" role="img" aria-label={`${door.admitted} of ${door.expected} tickets scanned in`}>
                  <span style={{ width: `${Math.min(100, Math.round((door.admitted / Math.max(1, door.expected)) * 100))}%` }} />
                </div>
                <p className="mt-2 text-[0.8125rem] text-muted">Scanned in so far, of the tickets issued for tonight.</p>
              </div>
              {arrivals.length > 0 ? <Arrivals counts={arrivals} /> : null}
            </div>
          ) : stageView.stage === "after" ? (
            <p className="mt-3 max-w-xl text-[0.9375rem] leading-relaxed text-muted">Finished — sales are closed and nothing here is still selling.</p>
          ) : (
            <p className="mt-3 max-w-xl text-[0.9375rem] leading-relaxed text-muted">Doors have not opened. The work now is getting the night ready.</p>
          )}

          {stageView.stage === "during" && door ? (
            <dl className="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-3">
              <Stat label="Still to arrive" value={String(Math.max(0, door.expected - door.admitted))} />
              {scan ? <Stat label="Scanners online" value={`${scan.online} of ${scan.total}`} warn={scan.online < scan.total} /> : null}
              {sales.length > 0 && countersVisible ? <Stat label="Sold for tonight" value={`${totalSold} of ${totalCap}`} /> : null}
            </dl>
          ) : null}

        </section>
      ) : null}

      {/* 2. What needs my attention — worst first, one action each. */}
      <section aria-labelledby="attention-title" id="attention" className={`panel flex min-w-0 flex-col p-5 md:p-7 ${ev ? "lg:col-span-5 lg:col-start-8 lg:row-span-2 lg:row-start-1" : "lg:col-span-12"}`}>
        <div className="flex items-center justify-between gap-3">
          <h2 id="attention-title" className="title-section">
            {urgent.length > 0 ? "Needs your attention" : "Nothing needs your attention"}
          </h2>
          {urgent.length > 0 ? <span className="count bg-[#0f0f10] text-white">{urgent.length}</span> : null}
        </div>
        {urgent.length === 0 ? (
          <p className="mt-3 text-[0.9375rem] leading-relaxed text-muted">Every check ran and found nothing. This is where a problem would show up.</p>
        ) : (
          <ul className="mt-4 flex flex-col gap-2.5">
            {urgent.map((s) => (
              <AttentionItem key={s.id} s={s} />
            ))}
          </ul>
        )}
        <div className="mt-auto pt-5">
          {clear.length > 0 ? (
            <details className="group">
              <summary className="inline-flex items-center gap-1.5 text-[0.8125rem] text-muted hover:text-ink">
                <Icon name="check" size={15} />
                {clear.length} other {clear.length === 1 ? "check" : "checks"} ran and found nothing
                <Icon name="down" size={14} className="transition-transform group-open:rotate-180" />
              </summary>
              <ul className="mt-2 space-y-1 pl-6 text-[0.8125rem] text-muted">
                {clear.map((c) => (
                  <li key={c.id}>{c.label}</li>
                ))}
              </ul>
            </details>
          ) : null}
          {rest.length > 0 ? (
            <details className="group mt-2">
              <summary className="inline-flex items-center gap-1.5 text-[0.8125rem] text-muted hover:text-ink">
                <Icon name="alert" size={15} />
                {rest.length} more worth knowing
                <Icon name="down" size={14} className="transition-transform group-open:rotate-180" />
              </summary>
              <ul className="mt-3 flex flex-col gap-2.5">
                {rest.map((s) => (
                  <AttentionItem key={s.id} s={s} />
                ))}
              </ul>
            </details>
          ) : null}
        </div>
      </section>

      {/* Supporting: how the stage event's tickets are selling. */}
      {ev && sales.length > 0 ? (
        <section aria-labelledby="sales-title" className="panel min-w-0 p-5 md:p-7 lg:col-span-7 lg:row-span-2 lg:row-start-2">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h2 id="sales-title" className="title-section">
              Tickets {stageView.stage === "after" ? "sold" : stageView.stage === "during" ? "for tonight" : "on sale"}
            </h2>
            <Link href={link(`${evBase}/inventory`)} className="btn btn-soft btn-sm">
              Manage tickets
              <Icon name="chevron" size={14} />
            </Link>
          </div>
          <ul className="mt-4 divide-y divide-line">
            {sales.map((l) => (
              <li key={l.ticketTypeId} className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-4 gap-y-2 py-3.5 sm:grid-cols-[minmax(0,1.3fr)_minmax(0,1fr)_auto]">
                <div className="min-w-0">
                  <p className="truncate text-[0.9375rem] font-medium text-ink">{l.name}</p>
                  <p className="text-[0.8125rem] text-muted">{usd(l.priceMinor)}</p>
                </div>
                {countersVisible ? (
                  <div className="col-span-2 row-start-2 sm:col-span-1 sm:row-start-auto">
                    <div className="meter" role="img" aria-label={`${l.sold} of ${l.capacity} sold`}>
                      <span style={{ width: `${l.capacity > 0 ? Math.round((l.sold / l.capacity) * 100) : 0}%` }} />
                    </div>
                  </div>
                ) : null}
                <p className="text-right text-[0.8125rem] tabular-nums">
                  {countersVisible ? (
                    <>
                      <span className="font-semibold text-ink">{l.sold}</span>
                      <span className="text-muted"> / {l.capacity} sold</span>
                    </>
                  ) : null}
                  <span className={`block ${l.remaining === 0 ? "font-medium text-danger" : "text-muted"}`}>{l.remaining === 0 ? "None left" : `${l.remaining} left`}</span>
                </p>
              </li>
            ))}
          </ul>
          <p className="mt-3 text-[0.8125rem] text-muted">
            {available.toLocaleString()} tickets still available across everything on sale. Counted at this moment, not a total for the week.
          </p>
        </section>
      ) : null}

      {/* Supporting: what is coming up. */}
      <section aria-labelledby="upcoming-title" className={`panel min-w-0 p-5 md:p-7 ${ev ? "lg:col-span-5 lg:col-start-8 lg:row-start-3" : "lg:col-span-12"}`}>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 id="upcoming-title" className="title-section">
            Coming up
          </h2>
          <Link href={link(`${basePath}/events`)} className="btn btn-soft btn-sm">
            All events
            <Icon name="chevron" size={14} />
          </Link>
        </div>
        {upcoming.length === 0 ? (
          <p className="mt-3 text-[0.9375rem] text-muted">Nothing else is scheduled.</p>
        ) : (
          <ul className="mt-3 divide-y divide-line">
            {upcoming.map(({ e, s }) => (
              <li key={e.eventId}>
                <Link href={link(`${basePath}/events/${e.eventId}`)} className="group -mx-2 flex items-center gap-3.5 rounded-2xl px-2 py-3 hover:bg-[#fafaf9]">
                  {s ? <DateTile iso={s.startsAt} timeZone={timeZone} /> : null}
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[0.9375rem] font-medium text-ink">{e.title}</span>
                    <span className="block text-[0.8125rem] text-muted">{s ? `${venueTime(s.startsAt, timeZone, { date: false, zone: false })} · ${relative(s.startsAt, now)}` : "No date yet"}</span>
                  </span>
                  <StatusBadge status={e.status} />
                  <Icon name="chevron" size={16} className="text-dim group-hover:text-ink" />
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}

function AttentionItem({ s }: { s: Signal }) {
  const chip = SEVERITY_CHIP[s.severity];
  return (
    <li className="rounded-2xl bg-[#f6f6f5] px-4 py-3.5">
      <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
        <span className={`badge ${chip.tone} shrink-0`}>{chip.label}</span>
        <p className="min-w-0 flex-1 text-[0.875rem] font-semibold leading-snug text-ink">{s.title}</p>
      </div>
      <p className="mt-1.5 text-[0.8125rem] leading-relaxed text-muted">{s.consequence}</p>
      <Link href={s.action.href} className="mt-2 inline-flex min-h-8 items-center gap-1.5 text-[0.8125rem] font-semibold text-ink hover:underline hover:underline-offset-4">
        {s.action.label}
        <Icon name="arrow" size={14} />
      </Link>
    </li>
  );
}

function Stat({ label, value, warn = false }: { label: string; value: string; warn?: boolean }) {
  return (
    <div className="rounded-2xl bg-[#f6f6f5] px-4 py-3">
      <dt className="text-[0.75rem] text-muted">{label}</dt>
      <dd className={`figure mt-0.5 text-[1.25rem] ${warn ? "text-danger" : "text-ink"}`}>{value}</dd>
    </div>
  );
}

/** Admissions per five minutes — a shape, with its peak written down. */
function Arrivals({ counts }: { counts: number[] }) {
  const peak = Math.max(...counts, 1);
  const minutes = counts.length * 5;
  return (
    <figure className="min-w-0 sm:w-56">
      <div className="flex h-14 items-end gap-1 sm:h-20" role="img" aria-label={`Arrivals every five minutes over the last ${minutes} minutes; busiest five minutes had ${peak}.`}>
        {counts.map((c, i) => (
          <span key={i} className={`flex-1 rounded-full ${i === counts.length - 1 ? "bg-[#0f0f10]" : "bg-[#d9d9d7]"}`} style={{ height: `${Math.max(8, Math.round((c / peak) * 100))}%` }} />
        ))}
      </div>
      <figcaption className="mt-2 text-[0.75rem] text-muted">Arrivals, every 5 min · peak {peak}</figcaption>
    </figure>
  );
}

function DateTile({ iso, timeZone }: { iso: string; timeZone: string }) {
  const d = new Date(iso);
  const month = new Intl.DateTimeFormat("en-US", { month: "short", timeZone }).format(d);
  const day = new Intl.DateTimeFormat("en-US", { day: "numeric", timeZone }).format(d);
  return (
    <span aria-hidden="true" className="grid h-12 w-12 shrink-0 place-items-center rounded-2xl bg-[#f1f1f0] text-center leading-none">
      <span>
        <span className="block text-[0.6875rem] font-medium uppercase text-muted">{month}</span>
        <span className="block text-[1.125rem] font-semibold text-ink">{day}</span>
      </span>
    </span>
  );
}

const STATUS_TONE: Record<EventStatus, string> = {
  draft: "badge-muted",
  announced: "",
  on_sale: "badge-green badge-dot",
  live: "badge-red badge-dot",
  completed: "badge-muted",
  cancelled: "badge-muted",
};

function StatusBadge({ status }: { status: EventStatus }) {
  return <span className={`badge hidden sm:inline-flex ${STATUS_TONE[status]}`}>{STATUS_LABEL[status]}</span>;
}

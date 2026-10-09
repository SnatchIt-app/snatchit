import Link from "next/link";
import { venueDate, venueTime, relative, usd } from "@/lib/format";
import type { ClearCheck, DoorSummary, Signal, Stage, StageView } from "@/lib/signals";
import { STATUS_LABEL } from "@/lib/events";
import { withPreview, type PreviewContext } from "@/lib/preview";
import type { Event, EventStatus } from "@/lib/types";
import { Icon } from "@/components/ui/Icon";
import { EventArt } from "@/components/ui/EventArt";
import { AttentionQueue, TicketViews, type QueueItem } from "@/components/overview/TodayClient";

/**
 * Today — the venue's first screen, composed to the approved concept:
 *
 *   artwork · eyebrow · the event's name · stage and time      [primary] [secondary]
 *   one row of headline figures, hairline-divided
 *   needs attention (left)                          arrivals (right)
 *   tickets for this event (left)                   coming up (right)
 *
 * It answers, in order: what am I looking at (the event, its stage), what
 * matters (figures, then the attention list), what to do (one dark button),
 * and where the detail is (every figure and row opens its screen).
 */
const STAGE_EYEBROW: Record<Stage, string> = {
  before: "Next up at",
  during: "Tonight at",
  after: "Last event at",
};

export type SalesLine = { ticketTypeId: string; name: string; priceMinor: number; sold: number; capacity: number; remaining: number; held?: number; visibility?: string };

function areaOf(id: string): QueueItem["area"] {
  if (id === "device_stale" || id === "flags_open") return "door";
  if (id.startsWith("blocked_") || id === "drafts") return "events";
  return "tickets";
}

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
  venueName = null,
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
  sales?: SalesLine[];
  countersVisible?: boolean;
  arrivals?: number[];
  scanners?: { online: number; total: number };
  venueName?: string | null;
}) {
  const link = (href: string) => withPreview(href, ctx);
  const ev = stageView.event;
  const sess = stageView.session;
  const evBase = ev ? `${basePath}/events/${ev.eventId}` : basePath;
  const scan = scanners ?? (door ? { online: door.devicesOnline, total: door.devicesTotal } : null);
  const items: QueueItem[] = signals.map((s) => ({ ...s, area: areaOf(s.id) }));
  const inside = stageView.stage === "during" && door ? door : null;

  const primary =
    stageView.stage === "during"
      ? { label: "Open check-in", href: link(`${evBase}/door`), icon: "scan" as const }
      : stageView.stage === "after"
        ? { label: "Review this event", href: link(evBase), icon: "calendar" as const }
        : { label: "Get this event ready", href: link(evBase), icon: "settings" as const };
  const secondary =
    stageView.stage === "during"
      ? { label: "Guest list", href: link(`${evBase}/attendees`), icon: "users" as const }
      : stageView.stage === "after"
        ? { label: "Who came", href: link(`${evBase}/attendees`), icon: "users" as const }
        : { label: "Tickets", href: link(`${evBase}/inventory`), icon: "ticket" as const };

  const upcoming = [...events]
    .filter((e) => e.status !== "completed" && e.status !== "cancelled" && e.eventId !== ev?.eventId)
    .map((e) => ({ e, s: [...e.sessions].sort((a, b) => a.startsAt.localeCompare(b.startsAt))[0] }))
    .sort((a, b) => (a.s?.startsAt ?? "").localeCompare(b.s?.startsAt ?? ""))
    .slice(0, 3);

  const totalSold = sales.reduce((n, l) => n + l.sold, 0);
  const totalCap = sales.reduce((n, l) => n + l.capacity, 0);
  const doorsOpen = !!(sess?.doorsAt && new Date(sess.doorsAt).getTime() <= now.getTime());

  if (!ev) {
    return (
      <div className="flex flex-col gap-6">
        <header className="enter">
          <h1 className="title-page">Today</h1>
        </header>
        <AttentionQueue items={items} clear={clear} />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-7 md:gap-9">
      {/* 1 + 3 — the event, its stage, and the one thing to do. */}
      <header className="enter grid gap-x-9 gap-y-6 lg:grid-cols-[15.5rem_minmax(0,1fr)]">
        <EventArt title={ev.title} className="hidden aspect-[3/4] w-full rounded-[4px] shadow-[0_24px_40px_-24px_rgba(30,20,10,0.6)] lg:block" />
        <div className="flex min-w-0 flex-col">
          <div className="flex flex-wrap items-start justify-between gap-x-8 gap-y-6 xl:flex-nowrap">
            <div className="flex min-w-0 flex-1 gap-4">
              <EventArt title={ev.title} variant="thumb" className="h-20 w-20 shrink-0 overflow-hidden rounded-[6px] lg:hidden" />
              <div className="min-w-0">
                <p className="eyebrow-caps">
                  {STAGE_EYEBROW[stageView.stage]} {venueName ?? "your venue"}
                </p>
                <h1 className="display-hero mt-3 max-w-[14ch] text-balance">{ev.title}</h1>
                <p className="mt-4 flex flex-wrap items-center gap-x-3 gap-y-2 text-[0.9375rem]">
                  {stageView.stage === "during" ? (
                    <span className="badge badge-green px-3 py-1 text-[0.875rem]">
                      <span aria-hidden="true" className="live-dot text-[#3a8a3f]" />
                      {doorsOpen ? "Doors open" : "Live"}
                      <span className="sr-only"> — happening now</span>
                    </span>
                  ) : stageView.stage === "after" ? (
                    <span className="badge badge-muted px-3 py-1 text-[0.875rem]">Finished — sales are closed</span>
                  ) : (
                    <span className="badge px-3 py-1 text-[0.875rem]">{STATUS_LABEL[ev.status]}</span>
                  )}
                  {sess ? (
                    <>
                      <span aria-hidden="true" className="h-4 w-px bg-[rgba(35,30,26,0.35)]" />
                      <span className="text-muted">
                        {venueDate(sess.startsAt, timeZone)}
                        {" · "}
                        {venueTime(sess.startsAt, timeZone, { date: false, zone: false })}
                        {sess.endsAt ? ` – ${venueTime(sess.endsAt, timeZone, { date: false, zone: false })}` : ""}
                        {stageView.stage === "before" ? ` · ${relative(sess.startsAt, now)}` : ""}
                      </span>
                    </>
                  ) : null}
                </p>
              </div>
            </div>
            <div className="flex w-full shrink-0 flex-col gap-2.5 sm:w-auto sm:min-w-[14.5rem]">
              <Link href={primary.href} className="btn btn-primary btn-lg justify-between">
                <span className="flex items-center gap-3">
                  <Icon name={primary.icon} size={20} strokeWidth={1.6} />
                  {primary.label}
                </span>
                <Icon name="chevron" size={16} />
              </Link>
              <Link href={secondary.href} className="btn btn-ghost btn-lg justify-between">
                <span className="flex items-center gap-3">
                  <Icon name={secondary.icon} size={19} strokeWidth={1.6} />
                  {secondary.label}
                </span>
                <Icon name="chevron" size={16} />
              </Link>
            </div>
          </div>

          {/* 2 — headline figures, grouped in one row. Each opens its screen. */}
          <dl className="stat-row mt-8 gap-y-5">
            {inside ? (
              <Stat href={link(`${evBase}/door`)} label="Checked in" value={String(inside.admitted)} of={`of ${inside.expected} guests`} />
            ) : null}
            {inside ? <Stat href={link(`${evBase}/attendees?checkIn=not_scanned`)} label="Still to arrive" value={String(Math.max(0, inside.expected - inside.admitted))} /> : null}
            {sales.length > 0 && countersVisible ? <Stat href={link(`${evBase}/inventory`)} label="Tickets sold" value={String(totalSold)} of={`of ${totalCap}`} /> : null}
            {inside && scan ? (
              <Stat
                href={link(`${evBase}/door`)}
                label="Scanners online"
                value={`${scan.online} of ${scan.total}`}
                note={scan.online < scan.total ? `${scan.total - scan.online} needs attention` : undefined}
              />
            ) : null}
            {!inside ? <Stat href={link(`${basePath}/events`)} label="Still on sale" value={available.toLocaleString()} of="across your events" /> : null}
          </dl>
          <details className="group mt-3">
            <summary className="inline-flex min-h-7 items-center gap-1 rounded-md text-[0.75rem] text-dim hover:text-ink">
              How these are counted
              <Icon name="down" size={12} className="transition-transform group-open:rotate-180" />
            </summary>
            <ul className="mt-1 max-w-2xl space-y-1 text-[0.8125rem] leading-relaxed text-muted">
              {inside ? <li>Checked in (people inside): scanned in so far, of the tickets issued for tonight.</li> : null}
              {inside ? <li>Still to arrive: tickets issued that have not been scanned yet.</li> : null}
              {sales.length > 0 && countersVisible ? <li>Tickets sold: sold for this event&apos;s session, of its capacity across every release.</li> : null}
              {inside ? <li>Scanners online: active devices only. An offline scanner keeps admitting from the list it last downloaded.</li> : null}
            </ul>
          </details>
        </div>
      </header>

      {/* 2 — the work queue and this event's tickets; live context beside them. */}
      <div className="grid items-start gap-6 xl:grid-cols-[minmax(0,1fr)_25.5rem]">
        <div className="flex min-w-0 flex-col gap-6">
          <AttentionQueue items={items} clear={clear} />
          {sales.length > 0 ? (
            <TicketViews
              title={stageView.stage === "during" ? "Tickets tonight" : stageView.stage === "after" ? "Tickets sold" : "Tickets on sale"}
              lines={sales.map((l) => ({ ...l, held: l.held ?? 0, price: usd(l.priceMinor), visibility: l.visibility ?? "public" }))}
              countersVisible={countersVisible}
              manageHref={link(`${evBase}/inventory`)}
              available={available}
            />
          ) : null}
        </div>
        <div className="flex min-w-0 flex-col gap-6">
          {inside && arrivals.length > 0 && sess ? <ArrivalsCard counts={arrivals} now={now} timeZone={timeZone} href={link(`${evBase}/door`)} /> : null}
          <section aria-labelledby="upcoming-title" className="panel enter-3 min-w-0 px-5 pb-2 pt-5 md:px-6">
            <div className="flex items-center justify-between gap-3 pb-3">
              <h2 id="upcoming-title" className="title-section">
                Coming up
              </h2>
              <Link href={link(`${basePath}/events`)} className="arrow-link text-[0.8125rem]">
                View all
                <Icon name="chevron" size={14} />
              </Link>
            </div>
            {upcoming.length === 0 ? (
              <p className="border-t border-line py-6 text-[0.875rem] text-muted">Nothing else is scheduled.</p>
            ) : (
              <ul className="border-t border-line">
                {upcoming.map(({ e, s }) => (
                  <li key={e.eventId} className="border-b border-line last:border-b-0">
                    <Link href={link(`${basePath}/events/${e.eventId}`)} className="group -mx-2 flex items-center gap-4 rounded-[14px] px-2 py-3 transition-colors hover:bg-white/60">
                      <EventArt title={e.title} variant="thumb" className="h-16 w-[5.25rem] shrink-0 overflow-hidden rounded-[6px]" />
                      <span className="min-w-0 flex-1">
                        <span className="serif block truncate text-[1.0625rem] leading-tight">{e.title}</span>
                        <span className="mt-0.5 block text-[0.8125rem] text-muted">{s ? `${venueTime(s.startsAt, timeZone, { date: true, zone: false })}` : "No date yet"}</span>
                        <span className={`badge mt-1.5 ${STATUS_TONE[e.status]}`}>{STATUS_LABEL[e.status]}</span>
                      </span>
                      <Icon name="chevron" size={16} className="text-dim transition-transform group-hover:translate-x-0.5 group-hover:text-ink" />
                    </Link>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </div>
      </div>
    </div>
  );
}

const STATUS_TONE: Record<EventStatus, string> = {
  draft: "badge-muted",
  announced: "badge-muted",
  on_sale: "badge-green",
  live: "badge-red",
  completed: "badge-muted",
  cancelled: "badge-muted",
};

function Stat({ href, label, value, of, note }: { href: string; label: string; value: string; of?: string; note?: string }) {
  return (
    <div className="min-w-0">
      <Link href={href} className="group block rounded-[10px] outline-offset-4">
        <dt className="text-[0.875rem] text-muted transition-colors group-hover:text-ink">{label}</dt>
        <dd className="mt-2 flex flex-wrap items-baseline gap-x-2.5 gap-y-1">
          <span className="stat-num">{value}</span>
          {of ? <span className="text-[0.8125rem] text-muted">{of}</span> : null}
          {note ? (
            <span className="flex items-center gap-1.5 text-[0.8125rem] text-warning">
              <span aria-hidden="true" className="h-2 w-2 rounded-full bg-[#e08a2e]" />
              {note}
            </span>
          ) : null}
        </dd>
      </Link>
    </div>
  );
}

/** Admissions per five minutes, with a real axis — the peak named, the latest five minutes in red. */
function ArrivalsCard({ counts, now, timeZone, href }: { counts: number[]; now: Date; timeZone: string; href: string }) {
  const peak = Math.max(...counts, 1);
  const top = Math.max(10, Math.ceil(peak / 10) * 10);
  const minutes = counts.length * 5;
  const last = counts[counts.length - 1];
  const start = new Date(now.getTime() - minutes * 60000);
  const mid = new Date(now.getTime() - (minutes / 2) * 60000);
  const t = (d: Date) => venueTime(d.toISOString(), timeZone, { date: false, zone: false });
  return (
    <section aria-labelledby="arrivals-title" className="panel enter-2 px-5 pb-5 pt-5 md:px-6">
      <div className="flex items-baseline justify-between gap-3">
        <h2 id="arrivals-title" className="title-section">
          Arrivals
        </h2>
        <span className="text-[0.8125rem] text-muted">
          Peak <span className="font-semibold text-ink">{peak}</span>
        </span>
      </div>
      <p className="mt-3 flex items-baseline gap-2.5">
        <span className="stat-num">{last}</span>
        <span className="text-[1.0625rem] text-ink">in the last 5 min</span>
      </p>
      <div className="mt-5 grid grid-cols-[1.75rem_minmax(0,1fr)] gap-x-2">
        <div aria-hidden="true" className="flex h-32 flex-col justify-between text-right text-[0.6875rem] text-dim">
          <span>{top}</span>
          <span>{top / 2}</span>
          <span>0</span>
        </div>
        <div className="relative h-32">
          <div aria-hidden="true" className="absolute inset-x-0 top-0 border-t border-dashed border-line" />
          <div aria-hidden="true" className="absolute inset-x-0 top-1/2 border-t border-dashed border-line" />
          <div aria-hidden="true" className="absolute inset-x-0 bottom-0 border-t border-line" />
          <div
            className="relative flex h-full items-end gap-[3px]"
            role="img"
            aria-label={`Arrivals every five minutes over the last ${minutes} minutes: busiest five minutes ${peak}, latest five minutes ${last}.`}
          >
            {counts.map((c, i) => (
              <span
                key={i}
                title={`${c} in five minutes`}
                className={`flex-1 rounded-t-[3px] ${i === counts.length - 1 ? "bg-[#c8361f]" : "bg-[#b9aa9b] hover:bg-[#8f7f70]"}`}
                style={{ height: `${Math.max(3, Math.round((c / top) * 100))}%` }}
              />
            ))}
          </div>
        </div>
        <span />
        <div aria-hidden="true" className="mt-2 flex justify-between text-[0.6875rem] text-dim">
          <span>{t(start)}</span>
          <span>{t(mid)}</span>
          <span>now</span>
        </div>
      </div>
      <Link href={href} className="arrow-link mt-3 text-[0.8125rem]">
        Check-in
        <Icon name="chevron" size={14} />
      </Link>
    </section>
  );
}

/** Loading: the page's own shape, so nothing jumps when it arrives. */
export function TodaySkeleton() {
  return (
    <div className="flex flex-col gap-9" role="status" aria-live="polite" aria-label="Loading today">
      <div className="grid gap-9 lg:grid-cols-[15.5rem_minmax(0,1fr)]">
        <div className="skel hidden aspect-[3/4] w-full rounded-[4px] lg:block" />
        <div>
          <div className="skel h-3 w-56" />
          <div className="skel mt-5 h-14 w-[min(30rem,90%)]" />
          <div className="skel mt-3 h-14 w-[min(22rem,70%)]" />
          <div className="skel mt-6 h-7 w-64" />
          <div className="mt-9 grid grid-cols-2 gap-6 md:grid-cols-4">
            {[0, 1, 2, 3].map((i) => (
              <div key={i}>
                <div className="skel h-3 w-24" />
                <div className="skel mt-3 h-10 w-20" />
              </div>
            ))}
          </div>
        </div>
      </div>
      <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_25.5rem]">
        <div className="panel space-y-4 p-6">
          {[0, 1, 2].map((i) => (
            <div key={i} className="skel h-12" />
          ))}
        </div>
        <div className="panel p-6">
          <div className="skel h-32" />
        </div>
      </div>
      <span className="sr-only">Loading…</span>
    </div>
  );
}

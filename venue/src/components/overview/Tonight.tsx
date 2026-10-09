import Link from "next/link";
import { venueTime, relative, usd } from "@/lib/format";
import type { ClearCheck, DoorSummary, Signal, Stage, StageView } from "@/lib/signals";
import { STATUS_LABEL } from "@/lib/events";
import { withPreview, type PreviewContext } from "@/lib/preview";
import type { Event, EventStatus } from "@/lib/types";
import { Icon } from "@/components/ui/Icon";
import { AttentionQueue, TicketViews, type QueueItem } from "@/components/overview/TodayClient";

/**
 * Today — the venue's first screen. It answers four questions, in order:
 *
 *   1. What am I looking at?   the event, its stage and time, at the top
 *   2. What matters right now? four summary cards, then the attention queue
 *   3. What should I do next?  one dark button in the header; one action per
 *                              attention item
 *   4. Where is the detail?    every card and row links to the screen that
 *                              owns it (check-in, guest list, tickets, setup)
 */
const STAGE_LABEL: Record<Stage, string> = {
  before: "Next up",
  during: "Happening now",
  after: "Last event",
};

export type SalesLine = { ticketTypeId: string; name: string; priceMinor: number; sold: number; capacity: number; remaining: number; visibility?: string };

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
}) {
  const link = (href: string) => withPreview(href, ctx);
  const ev = stageView.event;
  const sess = stageView.session;
  const evBase = ev ? `${basePath}/events/${ev.eventId}` : basePath;
  const scan = scanners ?? (door ? { online: door.devicesOnline, total: door.devicesTotal } : null);
  const items: QueueItem[] = signals.map((s) => ({ ...s, area: areaOf(s.id) }));

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
  const inside = stageView.stage === "during" && door ? door : null;

  return (
    <div className="flex flex-col gap-5 md:gap-6">
      {/* 1 + 3 — the event, its stage, and the one thing to do. */}
      {ev ? (
        <header className="enter flex flex-wrap items-end justify-between gap-x-8 gap-y-5 pb-1">
          <div className="min-w-0">
            <p className="flex flex-wrap items-center gap-2">
              <span className={`badge ${stageView.stage === "during" ? "badge-red" : ""}`}>
                {stageView.stage === "during" ? <span aria-hidden="true" className="live-dot" /> : null}
                {STAGE_LABEL[stageView.stage]}
              </span>
              {sess ? (
                <span className="text-[0.8125rem] text-muted">
                  {stageView.stage === "after"
                    ? `Ran ${venueTime(sess.startsAt, timeZone, { date: true, zone: false })}`
                    : stageView.stage === "during"
                      ? `Started ${venueTime(sess.startsAt, timeZone, { date: false, zone: false })}${sess.doorsAt ? ` · doors opened ${venueTime(sess.doorsAt, timeZone, { date: false, zone: false })}` : ""}`
                      : `${venueTime(sess.startsAt, timeZone, { date: true, zone: false })} · ${relative(sess.startsAt, now)}`}
                </span>
              ) : null}
            </p>
            <h1 className="title-display mt-3 text-[2.25rem] md:text-[3.25rem]">{ev.title}</h1>
            <p className="mt-2 max-w-xl text-[0.9375rem] leading-relaxed text-muted">
              {stageView.stage === "during"
                ? "Doors are open. The work tonight is at the door."
                : stageView.stage === "after"
                  ? "Finished — sales are closed and nothing here is still selling."
                  : "Doors have not opened. The work now is getting the night ready."}
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <Link href={secondary.href} className="btn btn-ghost btn-lg">
              {secondary.label}
            </Link>
            <Link href={primary.href} className="btn btn-primary btn-lg">
              <Icon name={primary.icon} size={17} />
              {primary.label}
            </Link>
          </div>
        </header>
      ) : (
        <header className="enter">
          <h1 className="title-page">Today</h1>
        </header>
      )}

      {/* 2 — summaries before detail. Each card opens the screen that owns it. */}
      {ev ? (
        <ul className="enter-2 grid grid-cols-2 gap-3 md:gap-4 xl:grid-cols-4" aria-label="At a glance">
          {inside ? (
            <SummaryCard
              href={link(`${evBase}/door`)}
              label="People inside"
              value={String(inside.admitted)}
              of={`of ${inside.expected}`}
              meter={inside.admitted / Math.max(1, inside.expected)}
              note="Scanned in so far, of the tickets issued for tonight."
            />
          ) : null}
          {inside ? (
            <SummaryCard
              href={link(`${evBase}/attendees?checkIn=not_scanned`)}
              label="Still to arrive"
              value={String(Math.max(0, inside.expected - inside.admitted))}
              note="Tickets issued that have not been scanned yet."
            />
          ) : null}
          {sales.length > 0 && countersVisible ? (
            <SummaryCard href={link(`${evBase}/inventory`)} label={stageView.stage === "during" ? "Sold for tonight" : "Tickets sold"} value={String(totalSold)} of={`of ${totalCap}`} meter={totalSold / Math.max(1, totalCap)} note={`${Math.max(0, totalCap - totalSold)} not sold yet`} />
          ) : null}
          {inside && scan ? (
            <SummaryCard
              href={link(`${evBase}/door`)}
              label="Scanners online"
              value={`${scan.online} of ${scan.total}`}
              tone={scan.online < scan.total ? "warn" : "ok"}
              note={scan.online < scan.total ? "An offline scanner keeps admitting from the list it last downloaded." : "Every active scanner is syncing."}
            />
          ) : null}
          {!inside ? <SummaryCard href={link(`${basePath}/events`)} label="Still on sale" value={available.toLocaleString()} note="Across everything on sale, right now." /> : null}
          {!inside && sess && stageView.stage === "before" ? <SummaryCard href={link(evBase)} label="Doors" value={relative(sess.doorsAt ?? sess.startsAt, now).replace(/^in /, "")} of="to go" note={venueTime(sess.doorsAt ?? sess.startsAt, timeZone, { date: true, zone: false })} /> : null}
        </ul>
      ) : null}

      {/* 2 — the work queue, with live context beside it. */}
      <div className="grid items-start gap-5 md:gap-6 xl:grid-cols-[minmax(0,1fr)_22rem]">
        <AttentionQueue items={items} clear={clear} />
        <div className="flex min-w-0 flex-col gap-5 md:gap-6">
          {inside && arrivals.length > 0 ? <ArrivalsCard counts={arrivals} href={link(`${evBase}/door`)} /> : null}
          <section aria-labelledby="upcoming-title" className="panel enter-3 min-w-0 p-5 md:p-6">
            <div className="flex items-center justify-between gap-3">
              <h2 id="upcoming-title" className="title-section">
                Coming up
              </h2>
              <Link href={link(`${basePath}/events`)} className="arrow-link">
                All events
                <Icon name="chevron" size={14} />
              </Link>
            </div>
            {upcoming.length === 0 ? (
              <p className="mt-3 text-[0.875rem] text-muted">Nothing else is scheduled.</p>
            ) : (
              <ul className="mt-2 flex flex-col">
                {upcoming.map(({ e, s }) => (
                  <li key={e.eventId}>
                    <Link href={link(`${basePath}/events/${e.eventId}`)} className="group -mx-2 flex items-center gap-3 rounded-2xl px-2 py-2.5 transition-colors hover:bg-[#faf9f7]">
                      {s ? <DateTile iso={s.startsAt} timeZone={timeZone} /> : null}
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-[0.875rem] font-semibold tracking-[-0.01em]">{e.title}</span>
                        <span className="flex items-center gap-1.5 text-[0.75rem] text-muted">
                          <StatusDot status={e.status} />
                          {STATUS_LABEL[e.status]}
                          {s ? ` · ${relative(s.startsAt, now)}` : ""}
                        </span>
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

      {/* 4 — the detail for this event, filterable. */}
      {ev && sales.length > 0 ? (
        <TicketViews
          lines={sales.map((l) => ({ ...l, price: usd(l.priceMinor), visibility: l.visibility ?? "public" }))}
          countersVisible={countersVisible}
          manageHref={link(`${evBase}/inventory`)}
          available={available}
        />
      ) : null}
    </div>
  );
}

function SummaryCard({ href, label, value, of, note, meter, tone }: { href: string; label: string; value: string; of?: string; note: string; meter?: number; tone?: "warn" | "ok" }) {
  return (
    <li className="min-w-0">
      <Link href={href} className="panel card-link group flex h-full flex-col p-4 md:p-5">
        <span className="flex items-center justify-between gap-2">
          <span className="text-[0.8125rem] font-medium text-muted">{label}</span>
          <Icon name="arrow" size={14} className="text-dim opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100" />
        </span>
        <span className="mt-2 flex items-baseline gap-1.5">
          <span className={`figure text-[1.875rem] leading-none md:text-[2.25rem] ${tone === "warn" ? "text-danger" : ""}`}>{value}</span>
          {of ? <span className="text-[0.8125rem] text-muted">{of}</span> : null}
        </span>
        {meter !== undefined ? (
          <span className="meter mt-3 block" aria-hidden="true">
            <span style={{ width: `${Math.min(100, Math.round(meter * 100))}%` }} />
          </span>
        ) : null}
        <span className="mt-auto pt-3 text-[0.75rem] leading-snug text-muted">{note}</span>
      </Link>
    </li>
  );
}

function ArrivalsCard({ counts, href }: { counts: number[]; href: string }) {
  const peak = Math.max(...counts, 1);
  const minutes = counts.length * 5;
  const last = counts[counts.length - 1];
  return (
    <section aria-labelledby="arrivals-title" className="panel enter-2 p-5 md:p-6">
      <div className="flex items-center justify-between gap-3">
        <h2 id="arrivals-title" className="title-section">
          Arrivals
        </h2>
        <Link href={href} className="arrow-link">
          Check-in
          <Icon name="chevron" size={14} />
        </Link>
      </div>
      <p className="mt-1 text-[0.8125rem] text-muted">
        <span className="figure text-ink">{last}</span> in the last 5 minutes · peak {peak}
      </p>
      <div className="mt-4 flex h-24 items-end gap-1" role="img" aria-label={`Arrivals every five minutes over the last ${minutes} minutes; busiest five minutes had ${peak}; the last five minutes had ${last}.`}>
        {counts.map((c, i) => (
          <span
            key={i}
            className={`flex-1 rounded-full transition-colors ${i === counts.length - 1 ? "bg-[#e3261c]" : c === peak ? "bg-ink" : "bg-[#e2ddd5] hover:bg-[#cfc8be]"}`}
            style={{ height: `${Math.max(8, Math.round((c / peak) * 100))}%` }}
            title={`${c} in five minutes`}
          />
        ))}
      </div>
      <p className="mt-2 flex justify-between text-[0.6875rem] text-muted">
        <span>{minutes} min ago</span>
        <span>now</span>
      </p>
    </section>
  );
}

function DateTile({ iso, timeZone }: { iso: string; timeZone: string }) {
  const d = new Date(iso);
  const month = new Intl.DateTimeFormat("en-US", { month: "short", timeZone }).format(d);
  const day = new Intl.DateTimeFormat("en-US", { day: "numeric", timeZone }).format(d);
  return (
    <span aria-hidden="true" className="grid h-11 w-11 shrink-0 place-items-center rounded-[14px] bg-[#f5f3ef] text-center leading-none">
      <span>
        <span className="block text-[0.625rem] font-semibold uppercase tracking-wide text-muted">{month}</span>
        <span className="block text-[1rem] font-bold">{day}</span>
      </span>
    </span>
  );
}

const STATUS_DOT: Record<EventStatus, string> = {
  draft: "bg-[#a8a29e]",
  announced: "bg-[#1d4ed8]",
  on_sale: "bg-[#137333]",
  live: "bg-[#e3261c]",
  completed: "bg-[#a8a29e]",
  cancelled: "bg-[#a8a29e]",
};

function StatusDot({ status }: { status: EventStatus }) {
  return <span aria-hidden="true" className={`inline-block h-1.5 w-1.5 rounded-full ${STATUS_DOT[status]}`} />;
}

/** Loading: the same shape as the page, so nothing jumps when it arrives. */
export function TodaySkeleton() {
  return (
    <div className="flex flex-col gap-6" role="status" aria-live="polite" aria-label="Loading today">
      <div>
        <div className="skel h-6 w-32" />
        <div className="skel mt-4 h-12 w-[min(32rem,90%)]" />
        <div className="skel mt-3 h-4 w-[min(24rem,70%)]" />
      </div>
      <div className="grid grid-cols-2 gap-4 xl:grid-cols-4">
        {[0, 1, 2, 3].map((i) => (
          <div key={i} className="panel p-5">
            <div className="skel h-3 w-24" />
            <div className="skel mt-4 h-8 w-20" />
            <div className="skel mt-4 h-2 w-full" />
          </div>
        ))}
      </div>
      <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_22rem]">
        <div className="panel space-y-4 p-6">
          {[0, 1, 2, 3].map((i) => (
            <div key={i} className="skel h-12" />
          ))}
        </div>
        <div className="panel p-6">
          <div className="skel h-24" />
        </div>
      </div>
      <span className="sr-only">Loading…</span>
    </div>
  );
}

import { venueTime, relative } from "@/lib/format";
import type { ClearCheck, DoorSummary, Signal, Stage, StageView } from "@/lib/signals";
import { STATUS_LABEL } from "@/lib/events";
import { withPreview, type PreviewContext } from "@/lib/preview";
import type { Event } from "@/lib/types";
import { Action, ArrowLink, Block, Detail, Facts, Row, Rows } from "@/components/ui/Page";

/**
 * The venue landing page, rebuilt against the marketing site's white sections
 * (snatchitapp.com — see globals.css for the measured reference).
 *
 * What a first-time manager meets, in this order and nothing before it:
 *   1. the event that is happening — its name, date and status
 *   2. one obvious next action for it
 *   3. only the things that actually need them, worst first
 *   4. supporting numbers, below
 *   5. everything else, below that
 *
 * What was removed from the previous version: the severity sub-headings
 * ("Needs you now" / "Before doors" / "Worth knowing") which repeated what the
 * ordering and the copy already said; the three-figure card that duplicated
 * the door screen; the second "Open the door screen" button; and the separate
 * "Coming up" heading above a list that is self-evidently a list of events.
 */
const STAGE_EYEBROW: Record<Stage, string> = {
  before: "Next up",
  during: "Happening now",
  after: "Last event",
};

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
}) {
  const link = (href: string) => withPreview(href, ctx);
  const urgent = signals.filter((s) => s.severity !== "worth_knowing");
  const rest = signals.filter((s) => s.severity === "worth_knowing");

  const ev = stageView.event;
  const sess = stageView.session;
  const evBase = ev ? `${basePath}/events/${ev.eventId}` : basePath;

  // What the manager is told, and the one action offered, follow the stage.
  const stageLead =
    stageView.stage === "during"
      ? `${door ? `${door.admitted} of ${door.expected} people are inside. ` : ""}Doors are open — the work tonight is at the door.`
      : stageView.stage === "after"
        ? `This event has finished and sales are closed. ${sess ? `It ran ${venueTime(sess.startsAt, timeZone, { date: true, zone: false })}.` : ""} Nothing here is still selling.`
        : `${sess ? `${venueTime(sess.startsAt, timeZone, { date: true, zone: false })}, ${relative(sess.startsAt, now)}. ` : ""}Doors have not opened — the work now is getting the night ready.`;

  const stagePrimary =
    stageView.stage === "during"
      ? { label: "Open check-in", href: link(`${evBase}/door`) }
      : stageView.stage === "after"
        ? { label: "Review this event", href: link(evBase) }
        : { label: "Get this event ready", href: link(evBase) };

  const stageSecondary =
    stageView.stage === "during"
      ? { label: "Guest list", href: link(`${evBase}/attendees`) }
      : stageView.stage === "after"
        ? { label: "Who came", href: link(`${evBase}/attendees`) }
        : { label: "Tickets", href: link(`${evBase}/tickets`.replace("/tickets", "/inventory")) };

  const upcoming = [...events]
    .filter((e) => e.status !== "completed" && e.status !== "cancelled")
    .map((e) => ({ e, s: [...e.sessions].sort((a, b) => a.startsAt.localeCompare(b.startsAt))[0] }))
    .filter(({ e }) => e.eventId !== stageView.event?.eventId)
    .sort((a, b) => (a.s?.startsAt ?? "").localeCompare(b.s?.startsAt ?? ""))
    .slice(0, 4);

  return (
    <>
      {/* 1–2. Where the venue actually is, and the one thing to do about it. */}
      {stageView.event ? (
        <Block id="stage">
          <p className="eyebrow-accent">{STAGE_EYEBROW[stageView.stage]}</p>
          <h2 className="display display-lg mt-2">{stageView.event.title}</h2>
          <p className="mt-3 text-base leading-relaxed text-muted">{stageLead}</p>
          <div className="mt-5 flex flex-wrap items-center gap-x-6 gap-y-3">
            <Action href={stagePrimary.href}>{stagePrimary.label}</Action>
            {stageSecondary ? <ArrowLink href={stageSecondary.href}>{stageSecondary.label}</ArrowLink> : null}
          </div>
        </Block>
      ) : null}

      {/* 3. Only what needs them. Ordering and copy carry the urgency; no badges. */}
      <Block title={urgent.length > 0 ? "Needs your attention" : "Nothing needs your attention"} id="attention">
        {urgent.length === 0 ? (
          <p className="max-w-2xl text-base text-muted">
            Every check ran and found nothing{clear.length > 0 ? ` — ${clear.length} of them` : ""}. This is the page that would tell you otherwise.
          </p>
        ) : (
          <ul className="divide-y divide-line border-y border-line">
            {urgent.map((s) => (
              <li key={s.id} className="py-5">
                <p className="text-base font-semibold text-ink">{s.title}</p>
                <p className="mt-1.5 max-w-2xl text-sm leading-relaxed text-muted">{s.consequence}</p>
                <p className="mt-3">
                  <ArrowLink href={s.action.href}>{s.action.label}</ArrowLink>
                </p>
              </li>
            ))}
          </ul>
        )}
        {clear.length > 0 && urgent.length > 0 ? <p className="mt-4 text-sm text-dim">{clear.length} other {clear.length === 1 ? "check" : "checks"} ran and found nothing.</p> : null}
      </Block>

      {/* 4. Supporting numbers — below the thing they support, each defined. */}
      {door && stageView.stage !== "before" ? (
        <Block title={stageView.stage === "after" ? "How it went" : "Tonight by the numbers"} id="numbers">
          <Facts
            items={[
              { label: "People inside", value: String(door.admitted), meaning: `Scanned in so far, of ${door.expected} tickets issued for tonight.` },
              { label: "Still to arrive", value: String(Math.max(0, door.expected - door.admitted)), meaning: "Tickets issued that have not been scanned yet." },
              { label: "Scanners online", value: `${door.devicesOnline} of ${door.devicesTotal}`, meaning: "A scanner that is offline keeps working from the list it already downloaded." },
              { label: "Tickets still available", value: available.toLocaleString(), meaning: "Across everything on sale right now. Counted at this moment, not a total for the week." },
            ]}
          />
        </Block>
      ) : null}

      {/* 5. Everything else. */}
      <Block title="Other events" action={<ArrowLink href={link(`${basePath}/events`)}>All events</ArrowLink>} id="other">
        <Rows>
          {upcoming.map(({ e, s }) => (
            <Row
              key={e.eventId}
              title={e.title}
              href={link(`${basePath}/events/${e.eventId}`)}
              meta={
                <>
                  {s ? `${venueTime(s.startsAt, timeZone, { date: true, zone: false })} · ${relative(s.startsAt, now)}` : STATUS_LABEL[e.status]} · {STATUS_LABEL[e.status]}
                </>
              }
            />
          ))}
        </Rows>
        {rest.length > 0 ? (
          <div className="mt-6">
            <Detail summary={`${rest.length} ${rest.length === 1 ? "thing" : "things"} worth knowing`}>
              <ul className="space-y-4">
                {rest.map((s) => (
                  <li key={s.id}>
                    <p className="font-semibold text-ink">{s.title}</p>
                    <p className="mt-1 max-w-2xl leading-relaxed">{s.consequence}</p>
                    <p className="mt-2">
                      <ArrowLink href={s.action.href}>{s.action.label}</ArrowLink>
                    </p>
                  </li>
                ))}
              </ul>
            </Detail>
          </div>
        ) : null}
      </Block>
    </>
  );
}

"use client";

import Link from "next/link";
import { useState } from "react";
import type { Severity } from "@/lib/signals";
import { Icon, type IconName } from "@/components/ui/Icon";

/**
 * The two interactive pieces of Today. Both render every row on the server
 * (the first paint is the "All" view), then filter in place — no reload, no
 * lost scroll; the selected filter is a pressed button screen readers announce.
 */

export type QueueItem = {
  id: string;
  severity: Severity;
  area: "door" | "tickets" | "events";
  title: string;
  brief?: string;
  consequence: string;
  action: { label: string; href: string };
};

const AREA_LABEL = { door: "Door", tickets: "Tickets", events: "Events" } as const;
const SEVERITY: Record<Severity, { word: string; icon: IconName; tint: string }> = {
  act_now: { word: "Needs you now", icon: "alert", tint: "bg-[#f7e0da] text-[#a82d17]" },
  soon: { word: "Soon", icon: "clock", tint: "bg-[#fbead6] text-[#8f4605]" },
  worth_knowing: { word: "Worth knowing", icon: "flag", tint: "bg-[rgba(70,50,30,0.07)] text-[rgba(35,30,26,0.72)]" },
};

export function AttentionQueue({ items, clear }: { items: QueueItem[]; clear: { id: string; label: string }[] }) {
  const [area, setArea] = useState<"all" | QueueItem["area"]>("all");
  const urgent = items.filter((i) => i.severity !== "worth_knowing");
  const areas = (["door", "tickets", "events"] as const).filter((a) => urgent.some((i) => i.area === a));
  const shown = items.filter((i) => area === "all" || i.area === area);
  const shownUrgent = shown.filter((i) => i.severity !== "worth_knowing");
  const shownRest = shown.filter((i) => i.severity === "worth_knowing");

  return (
    <section aria-labelledby="attention-title" id="attention" className="panel enter-2 flex min-w-0 flex-col px-5 pb-3 pt-5 md:px-6">
      <div className="flex flex-wrap items-center justify-between gap-3 pb-3">
        <div className="flex items-center gap-3">
          <h2 id="attention-title" className="title-section">
            {urgent.length > 0 ? "Needs attention" : "Nothing needs attention"}
          </h2>
          {urgent.length > 0 ? <span className="count count-alert h-7 min-w-7 text-[0.8125rem]">{urgent.length}</span> : null}
        </div>
        {areas.length > 1 ? (
          <div className="seg min-w-0" role="group" aria-label="Show attention items for">
            <button type="button" aria-pressed={area === "all"} onClick={() => setArea("all")}>
              All
            </button>
            {areas.map((a) => (
              <button key={a} type="button" aria-pressed={area === a} onClick={() => setArea(a)}>
                {AREA_LABEL[a]}
                <span className="sr-only">, {urgent.filter((i) => i.area === a).length}</span>
              </button>
            ))}
          </div>
        ) : null}
      </div>

      {urgent.length === 0 ? (
        <div className="flex items-start gap-3 border-t border-line py-5">
          <span className="status-icon bg-[#e3eed8] text-[#2b6330]">
            <Icon name="check" size={16} />
          </span>
          <p className="text-[0.9375rem] leading-relaxed">
            <span className="font-medium">All clear.</span> <span className="text-muted">Every check ran and found nothing. This is where a problem would show up.</span>
          </p>
        </div>
      ) : (
        <ul className="border-t border-line" aria-live="polite">
          {shownUrgent.map((s) => (
            <QueueRow key={s.id} s={s} />
          ))}
          {shownUrgent.length === 0 ? <li className="py-6 text-center text-[0.875rem] text-muted">Nothing urgent in this area.</li> : null}
        </ul>
      )}

      {clear.length > 0 || shownRest.length > 0 ? (
        <div className="mt-1 flex flex-wrap gap-x-6 gap-y-1 border-t border-line pt-2.5">
          {clear.length > 0 ? (
            <details className="group">
              <summary className="inline-flex min-h-9 items-center gap-1.5 rounded-lg text-[0.8125rem] text-muted hover:text-ink">
                <Icon name="check" size={15} />
                {clear.length} other {clear.length === 1 ? "check" : "checks"} ran and found nothing
                <Icon name="down" size={14} className="transition-transform group-open:rotate-180" />
              </summary>
              <ul className="mb-2 mt-1 space-y-1 pl-6 text-[0.8125rem] text-muted">
                {clear.map((c) => (
                  <li key={c.id}>{c.label}</li>
                ))}
              </ul>
            </details>
          ) : null}
          {shownRest.length > 0 ? (
            <details className="group w-full">
              <summary className="inline-flex min-h-9 items-center gap-1.5 rounded-lg text-[0.8125rem] text-muted hover:text-ink">
                <Icon name="flag" size={15} />
                {shownRest.length} more worth knowing
                <Icon name="down" size={14} className="transition-transform group-open:rotate-180" />
              </summary>
              <ul>
                {shownRest.map((s) => (
                  <QueueRow key={s.id} s={s} />
                ))}
              </ul>
            </details>
          ) : null}
        </div>
      ) : null}
    </section>
  );
}

/** One task: tinted status icon, the problem, one line of detail, one action. */
function QueueRow({ s }: { s: QueueItem }) {
  const sev = SEVERITY[s.severity];
  return (
    <li className="group/row grid grid-cols-[auto_minmax(0,1fr)] items-start gap-x-4 border-b border-line py-3.5 last:border-b-0 sm:grid-cols-[auto_minmax(0,1fr)_auto] sm:items-center">
      <span className={`status-icon mt-0.5 sm:mt-0 ${sev.tint}`} title={sev.word}>
        <Icon name={sev.icon} size={16} strokeWidth={2} />
      </span>
      <div className="min-w-0">
        <p className="text-[0.9375rem] font-medium leading-snug">
          <span className="sr-only">{sev.word}, {AREA_LABEL[s.area]}: </span>
          {s.title}
        </p>
        {s.brief ? (
          <details className="group/why">
            <summary className="mt-0.5 inline flex-wrap items-center text-[0.8125rem] leading-snug text-muted [&::marker]:hidden">
              {s.brief}
              <span className="ml-1.5 inline-grid h-5 w-5 translate-y-[3px] place-items-center rounded-full text-dim ring-1 ring-[rgba(70,50,30,0.18)] transition-colors group-open/why:bg-[#26211d] group-open/why:text-white hover:text-ink">
                <span aria-hidden="true" className="text-[0.6875rem] font-semibold leading-none">i</span>
                <span className="sr-only">Why it matters</span>
              </span>
            </summary>
            <p className="mb-1 mt-1.5 max-w-xl rounded-[10px] bg-white/70 px-3 py-2 text-[0.8125rem] leading-relaxed text-muted">{s.consequence}</p>
          </details>
        ) : (
          <p className="mt-0.5 text-[0.8125rem] leading-snug text-muted">{s.consequence}</p>
        )}
      </div>
      <Link href={s.action.href} className="btn btn-soft btn-sm col-start-2 mt-2.5 justify-self-start sm:col-start-3 sm:mt-0">
        {s.action.label}
        <Icon name="chevron" size={14} className="transition-transform group-hover/row:translate-x-0.5" />
      </Link>
    </li>
  );
}

export type TicketLine = { ticketTypeId: string; name: string; priceMinor: number; price: string; sold: number; held: number; capacity: number; remaining: number; visibility: string };
type View = "all" | "low" | "out" | "door";

export function TicketViews({ lines, countersVisible, manageHref, available, title }: { lines: TicketLine[]; countersVisible: boolean; manageHref: string; available: number; title: string }) {
  const [view, setView] = useState<View>("all");
  const low = (l: TicketLine) => l.remaining > 0 && l.capacity > 0 && l.remaining / l.capacity <= 0.1;
  const views: { key: View; label: string; test: (l: TicketLine) => boolean }[] = [
    { key: "all", label: "All", test: () => true },
    { key: "low", label: "Running low", test: low },
    { key: "out", label: "Sold out", test: (l) => l.remaining === 0 },
    { key: "door", label: "Door only", test: (l) => l.visibility === "door_only" },
  ];
  const current = views.find((v) => v.key === view)!;
  const shown = lines.filter(current.test);

  return (
    <section aria-labelledby="tickets-title" className="panel enter-3 min-w-0 px-5 pb-2 pt-5 md:px-6">
      <div className="flex flex-wrap items-center justify-between gap-3 pb-3">
        <h2 id="tickets-title" className="title-section">
          {title}
        </h2>
        <div className="flex min-w-0 max-w-full flex-wrap items-center gap-3">
          <div className="seg min-w-0" role="group" aria-label="Saved views">
            {views.map((v) => (
              <button key={v.key} type="button" aria-pressed={view === v.key} onClick={() => setView(v.key)}>
                {v.label}
                <span className="sr-only">, </span>
                <span className="text-[0.75rem] text-dim">{lines.filter(v.test).length}</span>
              </button>
            ))}
          </div>
          <Link href={manageHref} className="arrow-link">
            Manage tickets
            <Icon name="chevron" size={14} />
          </Link>
        </div>
      </div>

      {shown.length === 0 ? (
        <p className="border-t border-line px-1 py-8 text-center text-[0.875rem] text-muted">No ticket types in “{current.label}”.</p>
      ) : (
        <table className="w-full border-t border-line text-[0.875rem]">
          <caption className="sr-only">
            {title}, {current.label.toLowerCase()}
          </caption>
          <thead>
            <tr>
              <th scope="col" className="col-head py-2.5 pl-3 text-left">
                Ticket
              </th>
              <th scope="col" className="col-head py-2.5 text-left">
                {countersVisible ? "Sold" : ""}
              </th>
              <th scope="col" className="col-head py-2.5 pr-3 text-right sm:text-left">
                Available
              </th>
            </tr>
          </thead>
          <tbody>
            {shown.map((l) => {
              const pct = l.capacity > 0 ? Math.round((l.sold / l.capacity) * 100) : 0;
              return (
                <tr key={l.ticketTypeId} className="border-t border-line">
                  <td className="py-3 pl-3 pr-4 align-top">
                    <span className="flex flex-wrap items-center gap-2">
                      <span className="font-medium">{l.name}</span>
                      {l.visibility === "door_only" ? <span className="badge badge-muted">Door only</span> : l.visibility === "hidden" ? <span className="badge badge-muted">Hidden</span> : null}
                    </span>
                    <span className="block text-[0.8125rem] text-muted">
                      {l.price}
                      {countersVisible && l.held > 0 ? ` · ${l.held} held` : ""}
                    </span>
                  </td>
                  <td className="w-[45%] py-3 pr-6 align-top">
                    {countersVisible ? (
                      <span className="flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-4">
                        <span className="shrink-0 tabular-nums">
                          {l.sold} <span className="text-muted">of {l.capacity}</span>
                          <span className="sr-only"> sold</span>
                        </span>
                        <span className="meter block min-w-[5rem] flex-1" aria-hidden="true">
                          <span style={{ width: `${pct}%`, background: l.remaining === 0 ? "#b8351d" : undefined }} />
                        </span>
                      </span>
                    ) : null}
                  </td>
                  <td className="py-3 pr-3 text-right align-top tabular-nums sm:text-left">
                    {l.remaining === 0 ? <span className="font-medium text-danger">Sold out</span> : <span>{l.remaining}</span>}
                    <span className="sr-only">{l.remaining === 0 ? " — none left" : " left"}</span>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
      <p className="border-t border-line px-1 py-3 text-[0.75rem] text-muted">
        {available.toLocaleString()} tickets still available across everything on sale. Counted at this moment, not a total for the week.
      </p>
    </section>
  );
}

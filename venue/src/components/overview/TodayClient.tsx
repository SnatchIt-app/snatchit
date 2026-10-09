"use client";

import Link from "next/link";
import { useState } from "react";
import type { Severity } from "@/lib/signals";
import { Icon } from "@/components/ui/Icon";

/**
 * The two interactive pieces of Today. Both render every row on the server
 * (the first paint is the "All" view), then filter in place — no reload, no
 * lost scroll, and the selected filter is a pressed button screen readers
 * announce.
 */

export type QueueItem = {
  id: string;
  severity: Severity;
  area: "door" | "tickets" | "events";
  title: string;
  consequence: string;
  action: { label: string; href: string };
};

const AREA_LABEL = { door: "Door", tickets: "Tickets", events: "Events" } as const;
const SEVERITY = {
  act_now: { label: "Now", tone: "badge-red", dot: "bg-[#e3261c]" },
  soon: { label: "Soon", tone: "badge-amber", dot: "bg-[#b4630f]" },
  worth_knowing: { label: "Worth knowing", tone: "badge-muted", dot: "bg-[#a8a29e]" },
} as const;

export function AttentionQueue({ items, clear }: { items: QueueItem[]; clear: { id: string; label: string }[] }) {
  const [area, setArea] = useState<"all" | QueueItem["area"]>("all");
  const urgent = items.filter((i) => i.severity !== "worth_knowing");
  const areas = (["door", "tickets", "events"] as const).filter((a) => items.some((i) => i.area === a));
  const shown = items.filter((i) => area === "all" || i.area === area);
  const shownUrgent = shown.filter((i) => i.severity !== "worth_knowing");
  const shownRest = shown.filter((i) => i.severity === "worth_knowing");

  return (
    <section aria-labelledby="attention-title" id="attention" className="panel enter-2 flex min-w-0 flex-col p-5 md:p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2.5">
          <h2 id="attention-title" className="title-section">
            {urgent.length > 0 ? "Needs your attention" : "Nothing needs your attention"}
          </h2>
          {urgent.length > 0 ? <span className="count count-alert">{urgent.length}</span> : null}
        </div>
        {areas.length > 1 ? (
          <div className="seg min-w-0" role="group" aria-label="Show attention items for">
            <button type="button" aria-pressed={area === "all"} onClick={() => setArea("all")}>
              All
            </button>
            {areas.map((a) => (
              <button key={a} type="button" aria-pressed={area === a} onClick={() => setArea(a)}>
                {AREA_LABEL[a]}
                <span className="sr-only">, </span>
                <span className="count">{items.filter((i) => i.area === a && i.severity !== "worth_knowing").length}</span>
              </button>
            ))}
          </div>
        ) : null}
      </div>

      {urgent.length === 0 ? (
        <div className="mt-4 flex items-start gap-3 rounded-2xl bg-[#f3f8f4] p-4">
          <span className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-white text-success shadow-[0_0_0_1px_rgba(19,115,51,0.2)]">
            <Icon name="check" size={16} />
          </span>
          <p className="text-[0.875rem] leading-relaxed">
            <span className="font-semibold">All clear.</span> <span className="text-muted">Every check ran and found nothing. This is where a problem would show up.</span>
          </p>
        </div>
      ) : (
        <ul className="mt-4 divide-y divide-line" aria-live="polite">
          {shownUrgent.map((s) => (
            <QueueRow key={s.id} s={s} />
          ))}
          {shownUrgent.length === 0 ? <li className="py-6 text-center text-[0.875rem] text-muted">Nothing urgent in this area.</li> : null}
        </ul>
      )}

      <div className="mt-auto flex flex-wrap gap-x-5 gap-y-2 border-t border-line pt-4">
        {clear.length > 0 ? (
          <details className="group">
            <summary className="inline-flex min-h-8 items-center gap-1.5 rounded-full text-[0.8125rem] text-muted hover:text-ink">
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
        {shownRest.length > 0 ? (
          <details className="group w-full">
            <summary className="inline-flex min-h-8 items-center gap-1.5 rounded-full text-[0.8125rem] text-muted hover:text-ink">
              <Icon name="alert" size={15} />
              {shownRest.length} more worth knowing
              <Icon name="down" size={14} className="transition-transform group-open:rotate-180" />
            </summary>
            <ul className="mt-1 divide-y divide-line">
              {shownRest.map((s) => (
                <QueueRow key={s.id} s={s} />
              ))}
            </ul>
          </details>
        ) : null}
      </div>
    </section>
  );
}

function QueueRow({ s }: { s: QueueItem }) {
  const sev = SEVERITY[s.severity];
  const full = s.severity === "act_now";
  return (
    <li className="group/row grid grid-cols-[auto_minmax(0,1fr)] gap-x-3.5 py-4 sm:grid-cols-[auto_minmax(0,1fr)_auto] sm:items-center">
      <span aria-hidden="true" className={`mt-1.5 h-2.5 w-2.5 rounded-full sm:mt-0 ${sev.dot}`} />
      <div className="min-w-0">
        <p className="flex flex-wrap items-center gap-x-2 gap-y-1">
          <span className={`badge ${sev.tone}`}>{sev.label}</span>
          <span className="badge badge-muted">{AREA_LABEL[s.area]}</span>
        </p>
        <p className="mt-1.5 text-[0.9375rem] font-semibold leading-snug tracking-[-0.01em]">{s.title}</p>
        {full ? <p className="mt-1 text-[0.8125rem] leading-relaxed text-muted">{s.consequence}</p> : <p className="sr-only">{s.consequence}</p>}
      </div>
      <Link href={s.action.href} className="btn btn-ghost btn-sm col-start-2 mt-3 justify-self-start sm:col-start-3 sm:mt-0">
        {s.action.label}
        <Icon name="arrow" size={14} className="transition-transform group-hover/row:translate-x-0.5" />
      </Link>
    </li>
  );
}

export type TicketLine = { ticketTypeId: string; name: string; priceMinor: number; price: string; sold: number; capacity: number; remaining: number; visibility: string };
type View = "all" | "low" | "out" | "door";

export function TicketViews({ lines, countersVisible, manageHref, available }: { lines: TicketLine[]; countersVisible: boolean; manageHref: string; available: number }) {
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
    <section aria-labelledby="tickets-title" className="panel enter-3 min-w-0 p-5 md:p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 id="tickets-title" className="title-section">
          Tickets for this event
        </h2>
        <div className="flex min-w-0 max-w-full flex-wrap items-center gap-2">
          <div className="seg min-w-0" role="group" aria-label="Saved views">
            {views.map((v) => (
              <button key={v.key} type="button" aria-pressed={view === v.key} onClick={() => setView(v.key)}>
                {v.label}
                <span className="sr-only">, </span>
                <span className="count">{lines.filter(v.test).length}</span>
              </button>
            ))}
          </div>
          <Link href={manageHref} className="btn btn-ghost btn-sm">
            Manage tickets
            <Icon name="chevron" size={14} />
          </Link>
        </div>
      </div>

      {shown.length === 0 ? (
        <p className="mt-6 rounded-2xl bg-[#faf9f7] px-4 py-8 text-center text-[0.875rem] text-muted">No ticket types in “{current.label}”.</p>
      ) : (
        <ul className="mt-3 divide-y divide-line">
          {shown.map((l) => {
            const pct = l.capacity > 0 ? Math.round((l.sold / l.capacity) * 100) : 0;
            return (
              <li key={l.ticketTypeId} className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-6 gap-y-2.5 py-4 md:grid-cols-[minmax(0,1.2fr)_minmax(0,1fr)_7.5rem]">
                <div className="min-w-0">
                  <p className="flex flex-wrap items-center gap-2">
                    <span className="truncate text-[0.9375rem] font-semibold tracking-[-0.01em]">{l.name}</span>
                    {l.visibility === "door_only" ? <span className="badge badge-muted">Door only</span> : l.visibility === "hidden" ? <span className="badge badge-muted">Hidden</span> : null}
                  </p>
                  <p className="text-[0.8125rem] text-muted">{l.price}</p>
                </div>
                {countersVisible ? (
                  <div className="col-span-2 row-start-2 md:col-span-1 md:row-start-auto">
                    <div className="meter" role="img" aria-label={`${l.sold} of ${l.capacity} sold`}>
                      <span style={{ width: `${pct}%`, background: l.remaining === 0 ? "#c41d15" : undefined }} />
                    </div>
                  </div>
                ) : null}
                <p className="text-right text-[0.8125rem] tabular-nums">
                  {countersVisible ? (
                    <span className="block">
                      <span className="font-semibold">{l.sold}</span>
                      <span className="text-muted"> / {l.capacity} sold</span>
                    </span>
                  ) : null}
                  <span className={`block ${l.remaining === 0 ? "font-semibold text-danger" : "text-muted"}`}>{l.remaining === 0 ? "None left" : `${l.remaining} left`}</span>
                </p>
              </li>
            );
          })}
        </ul>
      )}
      <p className="mt-2 border-t border-line pt-4 text-[0.8125rem] text-muted">
        {available.toLocaleString()} tickets still available across everything on sale. Counted at this moment, not a total for the week.
      </p>
    </section>
  );
}

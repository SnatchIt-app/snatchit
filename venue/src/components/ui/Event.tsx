import Link from "next/link";
import type { ReactNode } from "react";
import { venueTime } from "@/lib/format";
import { EventArt } from "@/components/ui/EventArt";

/**
 * Shared pieces of the approved concept, used by every event screen.
 *
 *   EventHeader — the event's artwork, whose screen this is, the title in the
 *                 editorial serif, one meta line, and the screen's actions
 *   Stats       — headline figures in one hairline-divided row
 *   ArrivalsChart — admissions per five minutes on a real axis
 */
export function EventHeader({
  eventTitle,
  title,
  meta,
  actions,
  children,
}: {
  /** The event this screen belongs to — shown as the eyebrow and drawn as the artwork. */
  eventTitle: string;
  /** What this screen is (Check-in, Guest list…). */
  title: string;
  meta?: ReactNode;
  actions?: ReactNode;
  /** Usually a <Stats>. */
  children?: ReactNode;
}) {
  return (
    <header className="enter mb-8 grid gap-x-6 gap-y-5 md:grid-cols-[6.5rem_minmax(0,1fr)]">
      <EventArt title={eventTitle} className="hidden aspect-[3/4] w-full rounded-[4px] shadow-[0_18px_30px_-20px_rgba(30,20,10,0.6)] md:block" />
      <div className="min-w-0">
        <div className="flex flex-wrap items-start justify-between gap-x-8 gap-y-5">
          <div className="flex min-w-0 gap-4">
            <EventArt title={eventTitle} variant="thumb" className="h-14 w-14 shrink-0 overflow-hidden rounded-[6px] md:hidden" />
            <div className="min-w-0">
              <p className="eyebrow-caps truncate">{eventTitle}</p>
              <h1 className="title-page mt-2">{title}</h1>
              {meta ? <div className="mt-2.5 flex flex-wrap items-center gap-x-3 gap-y-1.5 text-[0.9375rem] text-muted">{meta}</div> : null}
            </div>
          </div>
          {actions ? <div className="flex w-full shrink-0 flex-wrap gap-2.5 sm:w-auto">{actions}</div> : null}
        </div>
        {children ? <div className="mt-7">{children}</div> : null}
      </div>
    </header>
  );
}

export type StatItem = {
  label: string;
  value: ReactNode;
  of?: ReactNode;
  /** A short amber note beside the figure ("1 needs attention"). */
  note?: string;
  tone?: "warn" | "danger";
  href?: string;
};

export function Stats({ items, label }: { items: StatItem[]; label?: string }) {
  return (
    <dl className="stat-row gap-y-5" aria-label={label}>
      {items.map((s) => {
        const body = (
          <>
            <dt className="text-[0.875rem] text-muted transition-colors group-hover:text-ink">{s.label}</dt>
            <dd className="mt-2 flex flex-wrap items-baseline gap-x-2.5 gap-y-1">
              <span className={`stat-num ${s.tone === "danger" ? "text-danger" : s.tone === "warn" ? "text-warning" : ""}`}>{s.value}</span>
              {s.of ? <span className="text-[0.8125rem] text-muted">{s.of}</span> : null}
              {s.note ? (
                <span className="flex items-center gap-1.5 text-[0.8125rem] text-warning">
                  <span aria-hidden="true" className="h-2 w-2 rounded-full bg-[#e08a2e]" />
                  {s.note}
                </span>
              ) : null}
            </dd>
          </>
        );
        return (
          <div key={s.label} className="min-w-0">
            {s.href ? (
              <Link href={s.href} className="group block rounded-[10px]">
                {body}
              </Link>
            ) : (
              <div>{body}</div>
            )}
          </div>
        );
      })}
    </dl>
  );
}

/** Admissions per five minutes — y axis, start / middle / now on x, the latest five minutes in red. */
export function ArrivalsChart({ counts, now, timeZone, height = "h-32" }: { counts: number[]; now: Date; timeZone: string; height?: string }) {
  const peak = Math.max(...counts, 1);
  const top = Math.max(10, Math.ceil(peak / 10) * 10);
  const minutes = counts.length * 5;
  const last = counts[counts.length - 1] ?? 0;
  const t = (offsetMin: number) => venueTime(new Date(now.getTime() - offsetMin * 60000).toISOString(), timeZone, { date: false, zone: false });
  return (
    <div className="grid grid-cols-[1.75rem_minmax(0,1fr)] gap-x-2">
      <div aria-hidden="true" className={`flex ${height} flex-col justify-between text-right text-[0.6875rem] text-dim`}>
        <span>{top}</span>
        <span>{top / 2}</span>
        <span>0</span>
      </div>
      <div className={`relative ${height}`}>
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
        <span>{t(minutes)}</span>
        <span>{t(minutes / 2)}</span>
        <span>now</span>
      </div>
    </div>
  );
}

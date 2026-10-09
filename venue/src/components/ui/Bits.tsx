import type { ReactNode } from "react";
import type { EventStatus, SessionStatus } from "@/lib/types";
import { STATUS_LABEL } from "@/lib/events";

export function Eyebrow({ children }: { children: ReactNode }) {
  return <p className="eyebrow text-dim">{children}</p>;
}

/**
 * Audit §P3 — the eyebrow says what the panel is *for*, in a manager's words.
 *
 * No backend identifier reaches this component any more, in the heading or in a
 * tooltip: a hover tooltip is product UI a venue manager reads, not a place to
 * park schema names. Which panel stands on which read is developer
 * documentation — `docs/venue-dashboard/READS.md`, and the per-function
 * annotations in `lib/data.ts`.
 */
export function Panel({ title, eyebrow, action, children }: { title: string; eyebrow?: string; action?: ReactNode; children: ReactNode }) {
  return (
    <section className="panel">
      <header className="flex flex-wrap items-center justify-between gap-3 px-5 pb-3 pt-5 md:px-6">
        <div>
          {eyebrow ? <Eyebrow>{eyebrow}</Eyebrow> : null}
          <h2 className="title-section">{title}</h2>
        </div>
        {action}
      </header>
      <div className="border-t border-line px-5 pb-5 pt-4 md:px-6">{children}</div>
    </section>
  );
}

const STATUS_TONE: Record<EventStatus | SessionStatus, string> = {
  draft: "badge-muted",
  announced: "",
  on_sale: "badge-green badge-dot",
  scheduled: "badge-muted",
  live: "badge-red badge-dot",
  completed: "badge-muted",
  cancelled: "badge-red",
};

export function StatusPill({ status }: { status: EventStatus | SessionStatus }) {
  const label = status in STATUS_LABEL ? STATUS_LABEL[status as EventStatus] : status === "scheduled" ? "Scheduled" : status;
  return <span className={`badge ${STATUS_TONE[status]}`}>{label}</span>;
}

export function Chip({ tone = "neutral", children }: { tone?: "neutral" | "warning" | "danger" | "success" | "info"; children: ReactNode }) {
  const cls = { neutral: "badge-muted", warning: "badge-amber", danger: "badge-red", success: "badge-green", info: "" }[tone];
  return <span className={`badge ${cls}`}>{children}</span>;
}

export function Metric({ label, value, sub }: { label: string; value: ReactNode; sub?: ReactNode }) {
  return (
    <div className="min-w-0">
      <p className="text-[0.875rem] text-muted">{label}</p>
      <p className="stat-num mt-2">{value}</p>
      {sub ? <p className="mt-1.5 text-[0.75rem] text-muted">{sub}</p> : null}
    </div>
  );
}

/** Spec §3.3 rule 4 — capacity bar segmented sold | held | remaining with the three numbers written out. */
export function CapacityBar({ capacity, held, sold, remaining }: { capacity: number; held: number; sold: number; remaining: number }) {
  const w = (n: number) => (capacity > 0 ? `${(n / capacity) * 100}%` : "0%");
  return (
    <div>
      <div className="capbar" aria-hidden="true">
        <span className="sold" style={{ width: w(sold) }} />
        <span className="held" style={{ width: w(held) }} />
      </div>
      <p className="mt-1 text-xs text-muted tabular-nums">
        <span className="text-ink"><span className="legend-swatch sold" aria-hidden="true" />{sold} sold</span> · <span className="text-warning"><span className="legend-swatch held" aria-hidden="true" />{held} held</span> · <span><span className="legend-swatch remaining" aria-hidden="true" />{remaining} remaining</span> · of {capacity}
      </p>
    </div>
  );
}

/**
  * Spec §19.5 — any audited action shows a one-line "this will be recorded"
  * note on its confirm.
  *
  * It used to promise the reader a record in "your venue's activity". There is
  * no screen anywhere in this product on which to read that, so the promise
  * sent people looking for something that does not exist. It is qualified
  * rather than dropped, because the fact that these actions are attributable
  * is true and worth saying — what is not yet true is that you can go and
  * look. Building that screen is deliberately out of scope here
  * (docs/venue-dashboard/REMAINING_WORK.md, U2).
  */
export function AuditNote() {
  return (
    <p className="text-xs text-dim">
      <strong>In this demo nothing is saved.</strong> In the real dashboard an action like this is attributable — recorded against your name — though there is no screen to read that history on yet.
    </p>
  );
}

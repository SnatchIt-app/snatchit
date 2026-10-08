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
      <header className="flex items-start justify-between gap-3 border-b border-line px-5 py-4">
        <div>
          {eyebrow ? <Eyebrow>{eyebrow}</Eyebrow> : null}
          <h2 className="text-base font-bold">{title}</h2>
        </div>
        {action}
      </header>
      <div className="p-5">{children}</div>
    </section>
  );
}

const STATUS_TONE: Record<EventStatus | SessionStatus, string> = {
  draft: "border-line-neutral text-muted",
  announced: "border-info text-info",
  on_sale: "border-success text-success",
  scheduled: "border-line-neutral text-muted",
  live: "border-primary text-primary-ink",
  completed: "border-line-neutral text-dim",
  cancelled: "border-danger text-danger",
};

export function StatusPill({ status }: { status: EventStatus | SessionStatus }) {
  const label = status in STATUS_LABEL ? STATUS_LABEL[status as EventStatus] : status === "scheduled" ? "Scheduled" : status;
  return <span className={`inline-block border px-2 py-0.5 text-xs font-bold ${STATUS_TONE[status]}`}>{label}</span>;
}

export function Chip({ tone = "neutral", children }: { tone?: "neutral" | "warning" | "danger" | "success" | "info"; children: ReactNode }) {
  const cls = { neutral: "border-line-neutral text-muted", warning: "border-warning text-warning", danger: "border-danger text-danger", success: "border-success text-success", info: "border-info text-info" }[tone];
  return <span className={`inline-block border px-1.5 py-0.5 text-xs ${cls}`}>{children}</span>;
}

export function Metric({ label, value, sub }: { label: string; value: ReactNode; sub?: ReactNode }) {
  return (
    <div className="border border-line-neutral p-3">
      <p className="eyebrow text-dim">{label}</p>
      <p className="mt-1 text-2xl font-bold tabular-nums">{value}</p>
      {sub ? <p className="mt-1 text-xs text-muted">{sub}</p> : null}
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

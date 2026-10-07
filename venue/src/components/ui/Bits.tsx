import type { ReactNode } from "react";
import type { EventStatus, SessionStatus } from "@/lib/types";
import { STATUS_LABEL } from "@/lib/events";

export function Eyebrow({ children }: { children: ReactNode }) {
  return <p className="eyebrow text-dim">{children}</p>;
}

/**
 * Audit §P3 — the eyebrow says what the panel is *for*, in a manager's words.
 * The backend read it stands on is review detail: it goes on `data-read`, and
 * into the heading's tooltip, never into the visible heading. It used to be
 * rendered unconditionally, so raw table names showed in database mode too.
 */
export function Panel({ title, eyebrow, read, action, children }: { title: string; eyebrow?: string; read?: string; action?: ReactNode; children: ReactNode }) {
  return (
    <section className="border border-line bg-card" data-read={read}>
      <header className="flex items-start justify-between gap-3 border-b border-line px-4 py-3">
        <div>
          {eyebrow ? <Eyebrow>{eyebrow}</Eyebrow> : null}
          <h2 className="text-base font-bold" title={read ? `Reads ${read}` : undefined}>
            {title}
          </h2>
        </div>
        {action}
      </header>
      <div className="p-4">{children}</div>
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
  * note on its confirm. The backend call it stands on is review detail: it goes
  * in the title attribute, not in copy a venue manager has to read past.
  */
export function AuditNote({ rpc }: { rpc: string }) {
  return (
    <p className="text-xs text-dim" title={`Calls ${rpc}`}>
      In the real dashboard this is recorded in your venue&apos;s activity, with your name on it. <strong>In this demo nothing is saved.</strong>
    </p>
  );
}

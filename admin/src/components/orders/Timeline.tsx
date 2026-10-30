import Link from "next/link";
import { DateTime } from "@/components/ui/DateTime";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { Alert } from "@/components/ui/Alert";
import { timelineRefHref } from "@/lib/routes";
import { humanize } from "@/lib/format";
import type { Timeline as TimelineData } from "@/lib/types";

const SOURCE_LABELS: Record<string, string> = {
  payment: "payment",
  transfer: "transfer",
  payout_decision: "payout decision",
  dispute: "stripe dispute",
  dispute_resolution: "resolution",
  notification: "notification",
  ops_action: "ops action",
  ops_case: "ops case",
};

/** Merged chronology from ops.order_timeline — every internal record, oldest first. */
export function Timeline({ data }: { data: TimelineData }) {
  if (data.events.length === 0) return <Alert state="empty" title="No events recorded for this order." compact />;
  return (
    <div>
      <ol className="relative border-l border-line-neutral pl-4">
        {data.events.map((e, i) => {
          const href = timelineRefHref(e.source, e.kind, e.ref);
          const isPath = e.ref && /\//.test(e.ref) && !/^[a-z]+_/.test(e.ref);
          return (
            <li key={`${e.at}-${e.source}-${e.kind}-${i}`} className="relative mb-4 last:mb-0">
              <span aria-hidden="true" className="absolute -left-[21px] top-1.5 h-2 w-2 bg-primary" />
              <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1 text-[13px]">
                <DateTime value={e.at} withSeconds />
                <StatusBadge status={e.source} label={SOURCE_LABELS[e.source ?? ""] ?? humanize(e.source ?? "event")} variant="neutral" />
                <span className="text-ink">{e.label ?? humanize(e.kind ?? "event")}</span>
                {e.kind ? <span className="font-mono text-[11px] text-dim">{e.kind}</span> : null}
              </div>
              {e.ref ? (
                <p className="mt-0.5 font-mono text-[11px] text-dim">
                  ref{" "}
                  {href ? (
                    <Link href={href} className="link">
                      {e.ref}
                    </Link>
                  ) : isPath ? (
                    <span title="storage path — open it from the Evidence panel">{e.ref}</span>
                  ) : (
                    e.ref
                  )}
                </p>
              ) : null}
            </li>
          );
        })}
      </ol>
      {data.note ? <p className="mt-4 text-[11px] text-dim">{data.note}</p> : null}
    </div>
  );
}

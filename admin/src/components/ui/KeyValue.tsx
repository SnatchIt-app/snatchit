import type { ReactNode } from "react";
import { humanize } from "@/lib/format";

export type KeyValueItem = { key: string; label?: ReactNode; value: ReactNode };

/** Definition list, two columns on wide screens. Missing values render "—". */
export function KeyValue({ items, columns = 2 }: { items: KeyValueItem[]; columns?: 1 | 2 | 3 }) {
  if (items.length === 0) return <p className="text-dim">—</p>;
  const cols = columns === 1 ? "sm:grid-cols-1" : columns === 3 ? "sm:grid-cols-3" : "sm:grid-cols-2";
  return (
    <dl className={`grid grid-cols-1 gap-x-6 gap-y-3 ${cols}`}>
      {items.map((it) => (
        <div key={it.key} className="min-w-0 border-b border-line-neutral pb-2">
          <dt className="eyebrow text-dim">{it.label ?? humanize(it.key)}</dt>
          <dd className="mt-0.5 break-words text-[13px] text-ink">
            {it.value === null || it.value === undefined || it.value === "" ? <span className="text-dim">—</span> : it.value}
          </dd>
        </div>
      ))}
    </dl>
  );
}

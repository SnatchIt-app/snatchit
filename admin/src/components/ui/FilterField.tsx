import type { ReactNode } from "react";

/** Label + control used by every GET filter form. */
export function FilterField({ label, children, className = "" }: { label: ReactNode; children: ReactNode; className?: string }) {
  return <label className={`flex flex-col gap-1 text-[11px] uppercase tracking-wider text-dim ${className}`}>{label}{children}</label>;
}

export function FilterSelect({
  name,
  options,
  value,
  all = "Any",
  labels,
}: {
  name: string;
  options: string[];
  value: string | undefined;
  all?: string;
  labels?: Record<string, string>;
}) {
  return (
    <select name={name} defaultValue={value ?? ""} className="field min-w-[140px] py-1.5 text-[13px]">
      <option value="">{all}</option>
      {options.map((o) => (
        <option key={o} value={o}>
          {labels?.[o] ?? o.replace(/_/g, " ")}
        </option>
      ))}
    </select>
  );
}

export function FilterForm({ action, children, sticky }: { action: string; children: ReactNode; sticky?: Record<string, string | undefined> }) {
  return (
    <form method="get" action={action} className="mb-4 flex flex-wrap items-end gap-3 border border-line-neutral bg-card p-3">
      {children}
      {sticky
        ? Object.entries(sticky).map(([k, v]) => (v ? <input key={k} type="hidden" name={k} value={v} /> : null))
        : null}
      <button type="submit" className="btn btn-ghost btn-sm">
        Filter
      </button>
      <a href={action} className="link self-center text-[12px]">
        Clear
      </a>
    </form>
  );
}

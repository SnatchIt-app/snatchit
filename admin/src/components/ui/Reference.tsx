import type { ReactNode } from "react";

/**
 * The record references an operator needs to investigate or to answer support,
 * in one clearly labelled place instead of scattered through the prose.
 *
 * This is deliberately NOT the same thing as a schema name. Internal table and
 * function names stay out of the interface entirely; the ids of real records —
 * payment, transfer, case, order, Stripe objects — are evidence and belong
 * here, where they can be found and copied.
 * See docs/design/DASHBOARD_DESIGN_GUIDELINES.md §6.
 */
export function Reference({ items, title = "Reference", children }: { items: { label: string; value: string | null | undefined; href?: string }[]; title?: string; children?: ReactNode }) {
  const present = items.filter((i) => i.value);
  if (present.length === 0 && !children) return null;
  return (
    <details className="mt-6 border-t border-line pt-3">
      <summary className="cursor-pointer text-[0.8125rem] font-semibold text-muted hover:text-ink">{title} — ids you can copy</summary>
      <dl className="mt-3 grid gap-x-8 gap-y-2 sm:grid-cols-[12rem_1fr]">
        {present.map((i) => (
          <div key={i.label} className="contents">
            <dt className="text-[0.8125rem] text-dim">{i.label}</dt>
            <dd className="min-w-0 break-all font-mono text-[0.75rem] text-ink">
              {i.href ? (
                <a className="link" href={i.href}>
                  {i.value}
                </a>
              ) : (
                i.value
              )}
            </dd>
          </div>
        ))}
      </dl>
      {children ? <div className="mt-3">{children}</div> : null}
    </details>
  );
}

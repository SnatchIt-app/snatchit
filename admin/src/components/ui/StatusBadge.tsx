export type BadgeVariant = "neutral" | "ok" | "warn" | "danger" | "info" | "muted";

const VARIANT_CLASS: Record<BadgeVariant, string> = {
  neutral: "",
  ok: "badge-green",
  warn: "badge-amber",
  danger: "badge-red",
  info: "",
  muted: "badge-muted",
};

/** A shape per variant so status never relies on colour alone. */
const VARIANT_GLYPH: Record<BadgeVariant, string> = {
  neutral: "•",
  ok: "✓",
  warn: "!",
  danger: "✕",
  info: "i",
  muted: "–",
};

/**
 * Status vocabulary across payments, transfers, cases, and actions. Unknown
 * statuses render neutral with their raw text — never hidden, never colour-only.
 */
const STATUS_VARIANTS: Record<string, BadgeVariant> = {
  // payments
  succeeded: "ok",
  paid: "ok",
  refunded: "info",
  partially_refunded: "info",
  pending: "warn",
  requires_action: "warn",
  processing: "warn",
  failed: "danger",
  canceled: "muted",
  cancelled: "muted",
  disputed: "danger",
  // transfers
  awaiting_transfer: "warn",
  seller_sent: "info",
  buyer_confirmed: "ok",
  auto_released: "ok",
  released: "ok",
  expired: "danger",
  dispute_open: "danger",
  refund_required: "danger",
  manual_review: "warn",
  held: "warn",
  // cases
  open: "warn",
  in_progress: "info",
  waiting: "muted",
  resolved: "ok",
  dismissed: "muted",
  // priorities
  p1: "danger",
  p2: "warn",
  p3: "info",
  p4: "muted",
  // actions
  requested: "warn",
  awaiting_approval: "warn",
  approved: "info",
  rejected: "danger",
  unknown: "danger",
  idempotent_replay: "info",
  stale_state: "danger",
  precondition: "danger",
  not_allowed: "danger",
  disabled: "muted",
  // jobs
  ok: "ok",
  healthy: "ok",
  degraded: "warn",
  down: "danger",
  active: "ok",
  inactive: "muted",
  true: "ok",
  false: "muted",
};

export function statusVariant(status: string | null | undefined): BadgeVariant {
  if (!status) return "muted";
  return STATUS_VARIANTS[status.toLowerCase()] ?? "neutral";
}

/**
 * Splits a reviewed label into what goes in the pill and the qualifier that
 * must stay visible beside it — "Refund recorded (not confirmed settled)"
 * becomes pill "Refund recorded" + "not confirmed settled" underneath. Every
 * word of the label is still rendered; only the layout changes.
 */
export function splitLabel(label: string): { head: string; tail: string | null } {
  const paren = label.match(/^(.*?)\s*\((.+)\)\s*$/);
  if (paren && paren[1]) return { head: paren[1], tail: paren[2] };
  const dash = label.indexOf(" — ");
  if (dash > 0) return { head: label.slice(0, dash), tail: label.slice(dash + 3) };
  return { head: label, tail: null };
}

export function StatusBadge({
  status,
  label,
  variant,
  qualifier = "inline",
}: {
  status: string | null | undefined;
  /** Override the visible text (defaults to the status with underscores as spaces). */
  label?: string;
  variant?: BadgeVariant;
  /** "below": put a label's parenthetical / dash qualifier on its own line under the pill. */
  qualifier?: "inline" | "below";
}) {
  const raw = label ?? (status ? status.replace(/_/g, " ") : "—");
  const text = /^p[1-4]$/i.test(raw) ? raw.toUpperCase() : raw.charAt(0).toUpperCase() + raw.slice(1);
  const v = variant ?? statusVariant(status);
  const parts = qualifier === "below" ? splitLabel(text) : { head: text, tail: null };
  const pill = (
    <span className={`badge ${VARIANT_CLASS[v]} ${parts.head.length > 22 ? "badge-wrap" : ""}`} data-status={status ?? ""}>
      <span aria-hidden="true" className="text-[0.625rem] font-bold leading-none">
        {VARIANT_GLYPH[v]}
      </span>
      {parts.head}
    </span>
  );
  if (!parts.tail) return pill;
  return (
    <span className="inline-flex flex-col items-start gap-1">
      {pill}
      <span className="pl-1 text-[0.75rem] leading-snug text-muted">{parts.tail}</span>
    </span>
  );
}

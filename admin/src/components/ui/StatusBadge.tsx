export type BadgeVariant = "neutral" | "ok" | "warn" | "danger" | "info" | "muted";

const VARIANT_CLASS: Record<BadgeVariant, string> = {
  neutral: "border-line-neutral text-ink",
  ok: "border-success text-success",
  warn: "border-warning text-warning",
  danger: "border-danger text-danger",
  info: "border-info text-info",
  muted: "border-line-neutral text-dim",
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

export function StatusBadge({
  status,
  label,
  variant,
}: {
  status: string | null | undefined;
  /** Override the visible text (defaults to the status with underscores as spaces). */
  label?: string;
  variant?: BadgeVariant;
}) {
  const text = label ?? (status ? status.replace(/_/g, " ") : "—");
  const v = variant ?? statusVariant(status);
  return (
    <span
      className={`inline-flex items-center border px-1.5 py-0.5 text-[11px] font-semibold uppercase tracking-wider ${VARIANT_CLASS[v]}`}
      data-status={status ?? ""}
    >
      {text}
    </span>
  );
}

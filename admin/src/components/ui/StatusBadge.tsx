export type BadgeVariant = "neutral" | "ok" | "warn" | "danger" | "info" | "muted";

const VARIANT_CLASS: Record<BadgeVariant, string> = {
  neutral: "bg-raised text-ink",
  ok: "bg-success-soft text-success",
  warn: "bg-warning-soft text-warning",
  danger: "bg-danger-soft text-danger",
  info: "bg-info-soft text-info",
  muted: "bg-raised text-dim",
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
  const raw = label ?? (status ? status.replace(/_/g, " ") : "—");
  const text = /^p[1-4]$/i.test(raw) ? raw.toUpperCase() : raw.charAt(0).toUpperCase() + raw.slice(1);
  const v = variant ?? statusVariant(status);
  return (
    <span
      className={`inline-flex items-center gap-1 whitespace-nowrap rounded-full px-2 py-0.5 text-[12px] font-medium ${VARIANT_CLASS[v]}`}
      data-status={status ?? ""}
    >
      <span aria-hidden="true" className="text-[10px] font-bold leading-none">
        {VARIANT_GLYPH[v]}
      </span>
      {text}
    </span>
  );
}

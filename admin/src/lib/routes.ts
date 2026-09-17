/**
 * Pure routing helpers — one place that knows which console page shows a
 * subject. Unit-tested; no server-only imports so both server and client
 * components can use it.
 */

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(v: unknown): v is string {
  return typeof v === "string" && UUID_RE.test(v);
}

/**
 * Route a (kind, id[, ref]) subject to its detail page. `ref` is the
 * `subject_ref` used by subjects without a uuid (job names, setting keys,
 * Stripe webhook event ids). Returns null when no page exists.
 */
export function subjectHref(kind: string | null | undefined, id: string | null | undefined, ref?: string | null): string | null {
  const k = (kind ?? "").toLowerCase();
  switch (k) {
    case "payment":
    case "order":
      return id ? `/orders/${id}` : null;
    case "transfer":
      // Transfers have no page of their own; /transfers/:id resolves the
      // owning payment and redirects to the unified order page.
      return id ? `/transfers/${id}` : null;
    case "case":
      return id ? `/cases/${id}` : null;
    case "user":
    case "profile":
    case "buyer":
    case "seller":
    case "reporter":
    case "bidder":
      return id ? `/users/${id}` : null;
    case "listing":
      return id ? `/marketplace/${id}` : null;
    case "action":
      return id ? `/actions/${id}` : null;
    case "report":
      return id ? `/reports#report-${id}` : "/reports";
    case "dispute":
      return id ? `/search?q=${encodeURIComponent(id)}` : null;
    case "job":
      return ref ? `/system#job-${encodeURIComponent(ref)}` : "/system#jobs";
    case "setting":
      return ref ? `/system#setting-${encodeURIComponent(ref)}` : "/system#settings";
    case "webhook_event":
      return "/system#webhooks";
    case "notification":
      return "/system#notify";
    default:
      return null;
  }
}

/** Where a Today metric tile should take the operator. */
export function metricHref(key: string): string | null {
  switch (key) {
    case "open_cases":
      return "/cases";
    case "paid_unsettled":
      return "/cases?case_type=paid_unsettled";
    case "transfers_due_6h":
      return "/cases?case_type=transfer_deadline_soon";
    case "transfers_overdue":
      return "/cases?case_type=transfer_overdue";
    case "refunds_pending":
      return "/cases?case_type=refund_pending";
    case "disputes_open":
      return "/cases?case_type=dispute_open";
    case "stripe_disputes_open":
    case "evidence_due_72h":
      return "/cases?case_type=dispute_evidence_due";
    case "payout_review":
      return "/money?state=manual_review#payouts";
    case "reports_pending":
      return "/reports?status=pending";
    case "jobs_failing":
      return "/system#jobs";
    case "webhook_backlog":
      return "/system#webhooks";
    case "approvals_pending":
      return "/system#approvals";
    case "alerts_firing":
      return "/system#alerts";
    default:
      return null;
  }
}

/**
 * Timeline refs (ops.order_timeline) are strings: uuids of the source row,
 * Stripe ids (pi_/tr_/re_/dp_), storage paths, or null. Route by source.
 */
export function timelineRefHref(source: string | null | undefined, kind: string | null | undefined, ref: string | null | undefined): string | null {
  if (!ref) return null;
  const s = (source ?? "").toLowerCase();
  if (isUuid(ref)) {
    switch (s) {
      case "payment":
        return subjectHref("payment", ref);
      case "transfer":
        return kind === "dispute_resolved" ? subjectHref("user", ref) : subjectHref("transfer", ref);
      case "ops_action":
        return subjectHref("action", ref);
      case "ops_case":
        return subjectHref("case", ref);
      default:
        return null; // payout_decision / dispute_resolution / notification rows have no page
    }
  }
  if (/^(pi|tr|re|dp|ch)_/.test(ref)) return `/search?q=${encodeURIComponent(ref)}`;
  return null;
}

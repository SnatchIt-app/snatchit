/**
 * TypeScript shapes for the `ops.*` contracts in
 * docs/admin-console/DESIGN_AND_EXECUTION_PLAN.md §3. Every RPC returns
 * jsonb; pages treat it as `unknown` and narrow through the small guards
 * here. Shapes are deliberately tolerant (all fields optional) so a page
 * degrades to "—" rather than crashing when a field is renamed or absent.
 */

export type Json = string | number | boolean | null | Json[] | { [k: string]: Json };
export type JsonRecord = Record<string, unknown>;

// ---------- guards ----------

export function isRecord(v: unknown): v is JsonRecord {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}
export function asArray(v: unknown): unknown[] {
  return Array.isArray(v) ? v : [];
}
export function asRecords(v: unknown): JsonRecord[] {
  return asArray(v).filter(isRecord);
}
export function str(v: unknown): string | null {
  return typeof v === "string" ? v : null;
}
export function num(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string" && v.trim() !== "" && Number.isFinite(Number(v))) return Number(v);
  return null;
}
export function bool(v: unknown): boolean | null {
  return typeof v === "boolean" ? v : null;
}
/** Read the first present key from a record (contract name drift tolerance). */
export function pick(r: JsonRecord | null | undefined, ...keys: string[]): unknown {
  if (!r) return undefined;
  for (const k of keys) if (k in r && r[k] !== undefined) return r[k];
  return undefined;
}

// ---------- §3.1 / §3.3 whoami ----------

export type OperatorRole = "platform_admin" | "platform_support" | "platform_risk";

export type Whoami = {
  user_id?: string;
  role?: OperatorRole | null;
  aal?: "aal1" | "aal2" | string;
  email_masked?: string;
};

export function toWhoami(v: unknown): Whoami | null {
  if (!isRecord(v)) return null;
  const role = str(v.role);
  return {
    user_id: str(v.user_id) ?? undefined,
    role: role === "platform_admin" || role === "platform_support" || role === "platform_risk" ? role : null,
    aal: str(v.aal) ?? undefined,
    email_masked: str(v.email_masked) ?? undefined,
  };
}

// ---------- §3.3 search ----------

export type SearchHitKind =
  | "payment"
  | "transfer"
  | "listing"
  | "user"
  | "dispute"
  | "case"
  | "action"
  | (string & {});

export type SearchHit = {
  kind?: SearchHitKind;
  id?: string;
  label?: string;
  sub?: string;
  status?: string;
};

export function toSearchHits(v: unknown): SearchHit[] {
  const arr = isRecord(v) ? asArray(pick(v, "hits", "items", "results")) : asArray(v);
  return arr.filter(isRecord).map((h) => ({
    kind: str(h.kind) ?? undefined,
    id: str(h.id) ?? undefined,
    label: str(h.label) ?? undefined,
    sub: str(h.sub) ?? undefined,
    status: str(h.status) ?? undefined,
  }));
}

// ---------- §3.3 list_* keyset pages ----------

export type ListPage<T = JsonRecord> = { items: T[]; next_cursor: string | null };

export function toListPage(v: unknown): ListPage {
  if (Array.isArray(v)) return { items: asRecords(v), next_cursor: null };
  if (!isRecord(v)) return { items: [], next_cursor: null };
  const items = asRecords(pick(v, "items", "rows", "data"));
  return { items, next_cursor: str(pick(v, "next_cursor", "cursor")) };
}

// ---------- §3.2 ops.case ----------

export type CaseStatus = "open" | "in_progress" | "waiting" | "resolved" | "dismissed";
export type CasePriority = "p1" | "p2" | "p3" | "p4";
export const CASE_STATUSES: CaseStatus[] = ["open", "in_progress", "waiting", "resolved", "dismissed"];
export const CASE_PRIORITIES: CasePriority[] = ["p1", "p2", "p3", "p4"];

export type OpsCase = {
  id?: string;
  case_type?: string;
  subject_kind?: string;
  subject_id?: string;
  subject_ref?: string;
  dedupe_key?: string;
  title?: string;
  summary?: string;
  status?: CaseStatus | string;
  priority?: CasePriority | string;
  assignee?: string | null;
  assignee_email_masked?: string | null;
  /** ops.case_row() enrichment: human label for the assignee / subject. */
  assignee_label?: string | null;
  subject_label?: string | null;
  note_count?: number;
  due_at?: string | null;
  detector?: string;
  detected_at?: string;
  last_seen_at?: string;
  resolved_at?: string | null;
  resolved_by?: string | null;
  resolution_note?: string | null;
  version?: number;
  created_at?: string;
  updated_at?: string;
};

export function toCase(v: unknown): OpsCase | null {
  if (!isRecord(v)) return null;
  return {
    id: str(v.id) ?? undefined,
    case_type: str(v.case_type) ?? undefined,
    subject_kind: str(v.subject_kind) ?? undefined,
    subject_id: str(v.subject_id) ?? undefined,
    subject_ref: str(v.subject_ref) ?? undefined,
    dedupe_key: str(v.dedupe_key) ?? undefined,
    title: str(v.title) ?? undefined,
    summary: str(v.summary) ?? undefined,
    status: str(v.status) ?? undefined,
    priority: str(v.priority) ?? undefined,
    assignee: str(v.assignee) ?? (v.assignee === null ? null : undefined),
    assignee_email_masked: str(pick(v, "assignee_email_masked", "assignee_email")) ?? undefined,
    assignee_label: str(v.assignee_label) ?? undefined,
    subject_label: str(v.subject_label) ?? undefined,
    note_count: num(v.note_count) ?? undefined,
    due_at: str(v.due_at) ?? (v.due_at === null ? null : undefined),
    detector: str(v.detector) ?? undefined,
    detected_at: str(v.detected_at) ?? undefined,
    last_seen_at: str(v.last_seen_at) ?? undefined,
    resolved_at: str(v.resolved_at) ?? undefined,
    resolved_by: str(v.resolved_by) ?? undefined,
    resolution_note: str(v.resolution_note) ?? undefined,
    version: num(v.version) ?? undefined,
    created_at: str(v.created_at) ?? undefined,
    updated_at: str(v.updated_at) ?? undefined,
  };
}

export type CaseNote = {
  id?: string;
  body?: string;
  author?: string;
  author_email_masked?: string;
  created_at?: string;
};

export type CaseEvent = {
  id?: string;
  at?: string;
  kind?: string;
  label?: string;
  actor?: string;
  data?: unknown;
};

export type Operator = { user_id?: string; role?: string; email_masked?: string; display?: string };

export type CaseDetail = {
  case: OpsCase | null;
  notes: CaseNote[];
  events: CaseEvent[];
  operators: Operator[];
  actions: JsonRecord[];
  subject: JsonRecord | null;
  raw: JsonRecord;
};

export function toCaseDetail(v: unknown): CaseDetail | null {
  if (!isRecord(v)) return null;
  const caseRec = isRecord(v.case) ? v.case : v;
  return {
    case: toCase(caseRec),
    notes: asRecords(pick(v, "notes", "case_notes")).map((n) => ({
      id: str(n.id) ?? undefined,
      body: str(pick(n, "body", "note", "text")) ?? undefined,
      author: str(pick(n, "author", "created_by", "author_id")) ?? undefined,
      author_email_masked: str(pick(n, "author_label", "author_email_masked", "author_email")) ?? undefined,
      created_at: str(n.created_at) ?? undefined,
    })),
    events: asRecords(pick(v, "events", "case_events", "timeline")).map((e) => ({
      id: str(e.id) ?? undefined,
      at: str(pick(e, "at", "created_at", "occurred_at")) ?? undefined,
      kind: str(pick(e, "kind", "event_type", "type")) ?? undefined,
      label: str(pick(e, "label", "summary", "title")) ?? undefined,
      actor: str(pick(e, "actor_label", "actor_email_masked", "actor", "created_by")) ?? undefined,
      data: pick(e, "data", "payload"),
    })),
    operators: asRecords(pick(v, "operators", "assignees")).map((o) => ({
      user_id: str(pick(o, "user_id", "id")) ?? undefined,
      role: str(o.role) ?? undefined,
      email_masked: str(pick(o, "email_masked", "email")) ?? undefined,
      display: str(pick(o, "label", "display", "display_name")) ?? undefined,
    })),
    actions: asRecords(pick(v, "actions")),
    subject: isRecord(v.subject) ? v.subject : null,
    raw: v,
  };
}

// ---------- §3.3 today ----------

export type MetricTile = {
  key: string;
  label: string;
  value: unknown;
  definition?: string;
  format?: "money" | "count" | "text";
};

export type TodayPayload = {
  attention: OpsCase[];
  metrics: MetricTile[];
  computed_at: string | null;
  raw: JsonRecord;
};

export function toToday(v: unknown): TodayPayload | null {
  if (!isRecord(v)) return null;
  const attention = asRecords(pick(v, "attention", "attention_queue", "queue", "cases"))
    .map(toCase)
    .filter((c): c is OpsCase => c !== null);
  const metricsRaw = pick(v, "metrics", "tiles");
  let metrics: MetricTile[] = [];
  if (Array.isArray(metricsRaw)) {
    metrics = metricsRaw.filter(isRecord).map((m, i) => ({
      key: str(m.key) ?? str(m.id) ?? `m${i}`,
      label: str(m.label) ?? str(m.key) ?? `Metric ${i + 1}`,
      value: pick(m, "value", "count", "total"),
      definition: str(m.definition) ?? undefined,
      format: (str(m.format) as MetricTile["format"]) ?? undefined,
    }));
  } else if (isRecord(metricsRaw)) {
    // ops.today() returns a flat map of counts (plus nested breakdowns such as
    // open_cases_by_type, which are not tiles).
    metrics = Object.entries(metricsRaw).flatMap(([key, val]): MetricTile[] => {
      if (isRecord(val)) {
        const value = pick(val, "value", "count", "total");
        if (value === undefined) return [];
        return [
          {
            key,
            label: str(val.label) ?? key,
            value,
            definition: str(val.definition) ?? undefined,
            format: (str(val.format) as MetricTile["format"]) ?? undefined,
          },
        ];
      }
      return [{ key, label: key, value: val }];
    });
  }
  const freshness = pick(v, "freshness");
  const computed_at =
    str(pick(v, "computed_at", "as_of")) ??
    (isRecord(freshness) ? str(pick(freshness, "generated_at", "snapshot_computed_at", "computed_at")) : str(freshness));
  return { attention, metrics, computed_at, raw: v };
}

// ---------- §3.4 mutation results ----------

export type ActionType =
  | "case_assign"
  | "case_status"
  | "case_priority"
  | "case_due"
  | "case_note"
  | "dispute_resolve"
  | "payout_release"
  | "listing_relist"
  | "report_resolve"
  | "user_restrict"
  | "user_unrestrict"
  | "refund_execute"
  | "job_retry"
  | "setting_set"
  | "approval_decide"
  | "case_create";

export type RejectionReason = "stale_state" | "precondition" | "not_allowed" | "disabled" | (string & {});

export type ActionOutcome =
  | { status: "succeeded"; action_id?: string; result?: unknown; raw: JsonRecord }
  | { status: "idempotent_replay"; action_id?: string; state?: string; raw: JsonRecord }
  | { status: "awaiting_approval"; action_id?: string; raw: JsonRecord }
  | { status: "rejected"; reason: RejectionReason; message?: string; raw: JsonRecord }
  | { status: "failed"; action_id?: string; error?: string; raw: JsonRecord }
  | { status: "processing"; action_id?: string; raw: JsonRecord };

export function toActionOutcome(v: unknown): ActionOutcome | null {
  if (!isRecord(v)) return null;
  const status = str(v.status);
  const action_id = str(pick(v, "action_id", "id")) ?? undefined;
  switch (status) {
    case "succeeded":
      return { status, action_id, result: v.result, raw: v };
    case "idempotent_replay":
      return { status, action_id, state: str(v.state) ?? undefined, raw: v };
    case "awaiting_approval":
      return { status, action_id, raw: v };
    case "rejected":
      return {
        status,
        reason: (str(pick(v, "reject_reason", "reason", "code", "rejection")) ?? "precondition") as RejectionReason,
        message: str(pick(v, "message", "detail", "error")) ?? undefined,
        raw: v,
      };
    case "failed":
      return { status, action_id, error: str(pick(v, "error", "message")) ?? undefined, raw: v };
    case "processing":
      return { status, action_id, raw: v };
    default:
      return null;
  }
}

// ---------- §3.2 ops.action ----------

export type OpsAction = {
  id?: string;
  idempotency_key?: string;
  action_type?: ActionType | string;
  subject_kind?: string;
  subject_id?: string;
  subject_ref?: string;
  subject_label?: string;
  params?: unknown;
  expected?: unknown;
  reason?: string;
  requested_by?: string;
  requested_by_label?: string;
  requested_at?: string;
  state?: string;
  reject_reason?: string | null;
  approval_id?: string | null;
  correlation_id?: string | null;
  result?: unknown;
  error?: string | null;
  provider_ref?: string | null;
  completed_at?: string | null;
  version?: number;
  created_at?: string;
  updated_at?: string;
};

// ---------- shared: masked user card (ops.user_summary) ----------

export type UserSummary = {
  id?: string;
  display_name?: string | null;
  email_masked?: string | null;
  phone_masked?: string | null;
  is_verified_seller?: boolean | null;
  stripe_onboarding_complete?: boolean | null;
  stripe_payouts_enabled?: boolean | null;
  created_at?: string;
};

export function toUserSummary(v: unknown): UserSummary | null {
  if (!isRecord(v)) return null;
  return {
    id: str(v.id) ?? undefined,
    display_name: str(v.display_name),
    email_masked: str(v.email_masked),
    phone_masked: str(v.phone_masked),
    is_verified_seller: bool(v.is_verified_seller),
    stripe_onboarding_complete: bool(v.stripe_onboarding_complete),
    stripe_payouts_enabled: bool(v.stripe_payouts_enabled),
    created_at: str(v.created_at) ?? undefined,
  };
}

// ---------- §3.3 list_orders / ops.order_row ----------

export type OrderRow = {
  payment_id?: string;
  created_at?: string;
  payment_status?: string;
  mode?: string;
  amount?: number | null;
  buyer_fee?: number | null;
  seller_fee?: number | null;
  total?: number | null;
  stripe_payment_intent_id?: string | null;
  stripe_livemode?: boolean | null;
  paid_at?: string | null;
  failed_at?: string | null;
  refunded_at?: string | null;
  stripe_refund_id?: string | null;
  listing_id?: string | null;
  event_name?: string | null;
  event_date?: string | null;
  buyer?: { id?: string; display_name?: string | null };
  seller?: { id?: string; display_name?: string | null };
  transfer_id?: string | null;
  transfer_status?: string | null;
  transfer_method?: string | null;
  transfer_expires_at?: string | null;
  seller_sent_at?: string | null;
  buyer_confirmed_at?: string | null;
  auto_release_at?: string | null;
  disputed_at?: string | null;
  dispute_resolved_at?: string | null;
  payout_review_status?: string | null;
  payout_risk_tier?: string | null;
  payout_hold_until?: string | null;
  payout_released_at?: string | null;
  stripe_transfer_id?: string | null;
  seller_funds_state?: string | null;
  open_cases?: number | null;
};

function party(v: unknown): { id?: string; display_name?: string | null } | undefined {
  if (!isRecord(v)) return undefined;
  return { id: str(v.id) ?? undefined, display_name: str(v.display_name) };
}

export function toOrderRow(v: unknown): OrderRow | null {
  if (!isRecord(v)) return null;
  return {
    payment_id: str(pick(v, "payment_id", "id")) ?? undefined,
    created_at: str(v.created_at) ?? undefined,
    payment_status: str(v.payment_status) ?? undefined,
    mode: str(v.mode) ?? undefined,
    amount: num(v.amount),
    buyer_fee: num(v.buyer_fee),
    seller_fee: num(v.seller_fee),
    total: num(v.total),
    stripe_payment_intent_id: str(v.stripe_payment_intent_id),
    stripe_livemode: bool(v.stripe_livemode),
    paid_at: str(v.paid_at),
    failed_at: str(v.failed_at),
    refunded_at: str(v.refunded_at),
    stripe_refund_id: str(v.stripe_refund_id),
    listing_id: str(v.listing_id),
    event_name: str(v.event_name),
    event_date: str(v.event_date),
    buyer: party(v.buyer),
    seller: party(v.seller),
    transfer_id: str(v.transfer_id),
    transfer_status: str(v.transfer_status),
    transfer_method: str(v.transfer_method),
    transfer_expires_at: str(v.transfer_expires_at),
    seller_sent_at: str(v.seller_sent_at),
    buyer_confirmed_at: str(v.buyer_confirmed_at),
    auto_release_at: str(v.auto_release_at),
    disputed_at: str(v.disputed_at),
    dispute_resolved_at: str(v.dispute_resolved_at),
    payout_review_status: str(v.payout_review_status),
    payout_risk_tier: str(v.payout_risk_tier),
    payout_hold_until: str(v.payout_hold_until),
    payout_released_at: str(v.payout_released_at),
    stripe_transfer_id: str(v.stripe_transfer_id),
    seller_funds_state: str(v.seller_funds_state),
    open_cases: num(v.open_cases),
  };
}

export function toOrderRows(v: unknown): OrderRow[] {
  return asArray(v).map(toOrderRow).filter((r): r is OrderRow => r !== null);
}

// ---------- §3.3 order_detail ----------

export type Payment = {
  id?: string;
  status?: string;
  mode?: string;
  amount?: number | null;
  buyer_fee?: number | null;
  seller_fee?: number | null;
  total?: number | null;
  stripe_payment_intent_id?: string | null;
  stripe_refund_id?: string | null;
  stripe_livemode?: boolean | null;
  payment_method?: string | null;
  buyer_id?: string | null;
  seller_id?: string | null;
  listing_id?: string | null;
  created_at?: string | null;
  paid_at?: string | null;
  failed_at?: string | null;
  refunded_at?: string | null;
  raw: JsonRecord;
};

export function toPayment(v: unknown): Payment | null {
  if (!isRecord(v)) return null;
  return {
    id: str(v.id) ?? undefined,
    status: str(v.status) ?? undefined,
    mode: str(v.mode) ?? undefined,
    amount: num(v.amount),
    buyer_fee: num(v.buyer_fee),
    seller_fee: num(v.seller_fee),
    total: num(v.total),
    stripe_payment_intent_id: str(v.stripe_payment_intent_id),
    stripe_refund_id: str(v.stripe_refund_id),
    stripe_livemode: bool(v.stripe_livemode),
    payment_method: str(v.payment_method),
    buyer_id: str(v.buyer_id),
    seller_id: str(v.seller_id),
    listing_id: str(v.listing_id),
    created_at: str(v.created_at),
    paid_at: str(v.paid_at),
    failed_at: str(v.failed_at),
    refunded_at: str(v.refunded_at),
    raw: v,
  };
}

export type Transfer = {
  id?: string;
  status?: string;
  payment_id?: string | null;
  listing_id?: string | null;
  buyer_id?: string | null;
  seller_id?: string | null;
  transfer_method?: string | null;
  created_at?: string | null;
  expires_at?: string | null;
  expired_at?: string | null;
  seller_sent_at?: string | null;
  buyer_viewed_at?: string | null;
  buyer_confirmed_at?: string | null;
  auto_release_at?: string | null;
  disputed_at?: string | null;
  dispute_reason?: string | null;
  dispute_notes?: string | null;
  dispute_resolution?: string | null;
  dispute_resolved_at?: string | null;
  dispute_resolved_by?: string | null;
  delivery_email?: string | null;
  delivery_phone?: string | null;
  payout_review_status?: string | null;
  payout_risk_tier?: string | null;
  payout_reason_codes?: string[];
  payout_hold_until?: string | null;
  payout_released_at?: string | null;
  stripe_transfer_id?: string | null;
  transfer_evidence_path?: string | null;
  dispute_evidence_path?: string | null;
  raw: JsonRecord;
};

export function toTransfer(v: unknown): Transfer | null {
  if (!isRecord(v)) return null;
  return {
    id: str(v.id) ?? undefined,
    status: str(v.status) ?? undefined,
    payment_id: str(v.payment_id),
    listing_id: str(v.listing_id),
    buyer_id: str(v.buyer_id),
    seller_id: str(v.seller_id),
    transfer_method: str(v.transfer_method),
    created_at: str(v.created_at),
    expires_at: str(v.expires_at),
    expired_at: str(v.expired_at),
    seller_sent_at: str(v.seller_sent_at),
    buyer_viewed_at: str(v.buyer_viewed_at),
    buyer_confirmed_at: str(v.buyer_confirmed_at),
    auto_release_at: str(v.auto_release_at),
    disputed_at: str(v.disputed_at),
    dispute_reason: str(v.dispute_reason),
    dispute_notes: str(v.dispute_notes),
    dispute_resolution: str(v.dispute_resolution),
    dispute_resolved_at: str(v.dispute_resolved_at),
    dispute_resolved_by: str(v.dispute_resolved_by),
    delivery_email: str(v.delivery_email),
    delivery_phone: str(v.delivery_phone),
    payout_review_status: str(v.payout_review_status),
    payout_risk_tier: str(v.payout_risk_tier),
    payout_reason_codes: asArray(v.payout_reason_codes).filter((x): x is string => typeof x === "string"),
    payout_hold_until: str(v.payout_hold_until),
    payout_released_at: str(v.payout_released_at),
    stripe_transfer_id: str(v.stripe_transfer_id),
    transfer_evidence_path: str(v.transfer_evidence_path),
    dispute_evidence_path: str(v.dispute_evidence_path),
    raw: v,
  };
}

export type ListingSummary = {
  id?: string;
  event_name?: string | null;
  venue?: string | null;
  neighborhood?: string | null;
  event_date?: string | null;
  event_time?: string | null;
  ticket_type?: string | null;
  quantity?: number | null;
  category?: string | null;
  ticket_platform?: string | null;
  status?: string | null;
  auction_status?: string | null;
  proof_status?: string | null;
  seller_id?: string | null;
  seller_display_name?: string | null;
  buy_now_enabled?: boolean | null;
  buy_now_price?: number | null;
  starting_bid?: number | null;
  current_bid?: number | null;
  bid_count?: number | null;
  winner_user_id?: string | null;
  winning_bid_amount?: number | null;
  ends_at?: string | null;
  sold_at?: string | null;
  created_at?: string | null;
  /** list_listings enrichment */
  report_count?: number | null;
  payment_status?: string | null;
  open_cases?: number | null;
  raw: JsonRecord;
};

export function toListingSummary(v: unknown): ListingSummary | null {
  if (!isRecord(v)) return null;
  return {
    id: str(v.id) ?? undefined,
    event_name: str(v.event_name),
    venue: str(v.venue),
    neighborhood: str(v.neighborhood),
    event_date: str(v.event_date),
    event_time: str(v.event_time),
    ticket_type: str(v.ticket_type),
    quantity: num(v.quantity),
    category: str(v.category),
    ticket_platform: str(v.ticket_platform),
    status: str(v.status),
    auction_status: str(v.auction_status),
    proof_status: str(v.proof_status),
    seller_id: str(v.seller_id),
    seller_display_name: str(v.seller_display_name),
    buy_now_enabled: bool(v.buy_now_enabled),
    buy_now_price: num(v.buy_now_price),
    starting_bid: num(v.starting_bid),
    current_bid: num(v.current_bid),
    bid_count: num(v.bid_count),
    winner_user_id: str(v.winner_user_id),
    winning_bid_amount: num(v.winning_bid_amount),
    ends_at: str(v.ends_at),
    sold_at: str(v.sold_at),
    created_at: str(v.created_at),
    report_count: num(v.report_count),
    payment_status: str(v.payment_status),
    open_cases: num(v.open_cases),
    raw: v,
  };
}

export type EvidenceRef = { key: string; bucket: string | null; path: string | null };

export function toEvidence(v: unknown): EvidenceRef[] {
  if (!isRecord(v)) return [];
  return Object.entries(v).map(([key, val]) => ({
    key,
    bucket: isRecord(val) ? str(val.bucket) : null,
    path: isRecord(val) ? str(val.path) : typeof val === "string" ? val : null,
  }));
}

export type RefundFacts = {
  payment_status?: string | null;
  refunded_at?: string | null;
  stripe_refund_id?: string | null;
  refund_actions: OpsAction[];
};

export type OrderDetail = {
  payment: Payment | null;
  transfer: Transfer | null;
  listing: ListingSummary | null;
  buyer: UserSummary | null;
  seller: UserSummary | null;
  disputes: JsonRecord[];
  dispute_resolutions: JsonRecord[];
  payout_decisions: JsonRecord[];
  refund: RefundFacts;
  seller_funds_state: string | null;
  cases: OpsCase[];
  actions: OpsAction[];
  evidence: EvidenceRef[];
  bank_payout: { tracked: boolean; note: string | null };
  raw: JsonRecord;
};

export function toOrderDetail(v: unknown): OrderDetail | null {
  if (!isRecord(v)) return null;
  const refund = isRecord(v.refund) ? v.refund : {};
  const bank = isRecord(v.bank_payout) ? v.bank_payout : {};
  return {
    payment: toPayment(v.payment),
    transfer: toTransfer(v.transfer),
    listing: toListingSummary(v.listing),
    buyer: toUserSummary(v.buyer),
    seller: toUserSummary(v.seller),
    disputes: asRecords(v.disputes),
    dispute_resolutions: asRecords(v.dispute_resolutions),
    payout_decisions: asRecords(v.payout_decisions),
    refund: {
      payment_status: str(refund.payment_status),
      refunded_at: str(refund.refunded_at),
      stripe_refund_id: str(refund.stripe_refund_id),
      refund_actions: toActions(refund.refund_actions),
    },
    seller_funds_state: str(v.seller_funds_state),
    cases: asRecords(v.cases).map(toCase).filter((c): c is OpsCase => c !== null),
    actions: toActions(v.actions),
    evidence: toEvidence(v.evidence),
    bank_payout: { tracked: bool(bank.tracked) ?? false, note: str(bank.note) },
    raw: v,
  };
}

// ---------- §3.3 order_timeline ----------

export type TimelineEvent = { at?: string; source?: string; kind?: string; label?: string; ref?: string | null };

export type Timeline = { events: TimelineEvent[]; note: string | null };

export function toTimeline(v: unknown): Timeline {
  const arr = isRecord(v) ? asArray(pick(v, "events", "items")) : asArray(v);
  return {
    events: arr.filter(isRecord).map((e) => ({
      at: str(e.at) ?? undefined,
      source: str(e.source) ?? undefined,
      kind: str(e.kind) ?? undefined,
      label: str(e.label) ?? undefined,
      ref: str(e.ref),
    })),
    note: isRecord(v) ? str(v.note) : null,
  };
}

// ---------- §3.2 ops.action rows (ops.action_row) ----------

export function toAction(v: unknown): OpsAction | null {
  if (!isRecord(v)) return null;
  return {
    id: str(v.id) ?? undefined,
    idempotency_key: str(v.idempotency_key) ?? undefined,
    action_type: str(v.action_type) ?? undefined,
    subject_kind: str(v.subject_kind) ?? undefined,
    subject_id: str(v.subject_id) ?? undefined,
    subject_ref: str(v.subject_ref) ?? undefined,
    subject_label: str(v.subject_label) ?? undefined,
    params: v.params,
    expected: v.expected,
    reason: str(v.reason) ?? undefined,
    requested_by: str(v.requested_by) ?? undefined,
    requested_by_label: str(v.requested_by_label) ?? undefined,
    requested_at: str(v.requested_at) ?? undefined,
    state: str(v.state) ?? undefined,
    reject_reason: str(v.reject_reason),
    approval_id: str(v.approval_id),
    correlation_id: str(v.correlation_id),
    result: v.result,
    error: str(v.error),
    provider_ref: str(v.provider_ref),
    completed_at: str(v.completed_at),
    version: num(v.version) ?? undefined,
    created_at: str(v.created_at) ?? undefined,
    updated_at: str(v.updated_at) ?? undefined,
  };
}

export function toActions(v: unknown): OpsAction[] {
  return asArray(v).map(toAction).filter((a): a is OpsAction => a !== null);
}

// ---------- §3.3 action_detail / list_approvals ----------

export type Approval = {
  id?: string;
  action_id?: string;
  action_hash?: string;
  requested_by?: string;
  requested_by_label?: string | null;
  decided_by?: string | null;
  decided_by_label?: string | null;
  state?: string;
  reason?: string | null;
  expires_at?: string | null;
  decided_at?: string | null;
  created_at?: string;
  can_decide?: boolean | null;
  hash_current?: boolean | null;
  action?: OpsAction | null;
};

export function toApproval(v: unknown): Approval | null {
  if (!isRecord(v)) return null;
  return {
    id: str(v.id) ?? undefined,
    action_id: str(v.action_id) ?? undefined,
    action_hash: str(v.action_hash) ?? undefined,
    requested_by: str(v.requested_by) ?? undefined,
    requested_by_label: str(v.requested_by_label),
    decided_by: str(v.decided_by),
    decided_by_label: str(v.decided_by_label),
    state: str(v.state) ?? undefined,
    reason: str(v.reason),
    expires_at: str(v.expires_at),
    decided_at: str(v.decided_at),
    created_at: str(v.created_at) ?? undefined,
    can_decide: bool(v.can_decide),
    hash_current: bool(v.hash_current),
    action: toAction(v.action),
  };
}

export type AuditRow = {
  id?: string;
  actor?: string | null;
  actor_label?: string | null;
  actor_role?: string | null;
  action?: string;
  subject_kind?: string;
  subject_id?: string | null;
  subject_ref?: string | null;
  subject_label?: string | null;
  reason?: string | null;
  before?: unknown;
  after?: unknown;
  outcome?: string;
  correlation_id?: string | null;
  action_id?: string | null;
  occurred_at?: string;
};

export function toAuditRow(v: unknown): AuditRow | null {
  if (!isRecord(v)) return null;
  return {
    id: str(v.id) ?? undefined,
    actor: str(v.actor),
    actor_label: str(v.actor_label),
    actor_role: str(v.actor_role),
    action: str(v.action) ?? undefined,
    subject_kind: str(v.subject_kind) ?? undefined,
    subject_id: str(v.subject_id),
    subject_ref: str(v.subject_ref),
    subject_label: str(v.subject_label),
    reason: str(v.reason),
    before: v.before,
    after: v.after,
    outcome: str(v.outcome) ?? undefined,
    correlation_id: str(v.correlation_id),
    action_id: str(v.action_id),
    occurred_at: str(v.occurred_at) ?? undefined,
  };
}

export type ActionDetail = {
  action: OpsAction | null;
  approvals: Approval[];
  audit: AuditRow[];
  subject: JsonRecord | null;
  related_cases: OpsCase[];
  raw: JsonRecord;
};

export function toActionDetail(v: unknown): ActionDetail | null {
  if (!isRecord(v)) return null;
  return {
    action: toAction(v.action),
    approvals: asArray(v.approvals).map(toApproval).filter((a): a is Approval => a !== null),
    audit: asArray(v.audit).map(toAuditRow).filter((a): a is AuditRow => a !== null),
    subject: isRecord(v.subject) ? v.subject : null,
    related_cases: asRecords(v.related_cases).map(toCase).filter((c): c is OpsCase => c !== null),
    raw: v,
  };
}

// ---------- §3.3 users ----------

export type UserListItem = UserSummary & {
  is_listing_blocked?: boolean | null;
  risk_tier?: string | null;
  listing_count?: number | null;
  open_cases?: number | null;
};

export function toUserListItem(v: unknown): UserListItem | null {
  const base = toUserSummary(v);
  if (!base || !isRecord(v)) return null;
  return {
    ...base,
    is_listing_blocked: bool(v.is_listing_blocked),
    risk_tier: str(v.risk_tier),
    listing_count: num(v.listing_count),
    open_cases: num(v.open_cases),
  };
}

export type Report = {
  id?: string;
  reporter_id?: string | null;
  reporter_label?: string | null;
  target_type?: string | null;
  target_id?: string | null;
  target_label?: string | null;
  reason?: string | null;
  notes?: string | null;
  status?: string | null;
  created_at?: string | null;
  resolved_at?: string | null;
  open_cases?: number | null;
};

export function toReport(v: unknown): Report | null {
  if (!isRecord(v)) return null;
  return {
    id: str(v.id) ?? undefined,
    reporter_id: str(v.reporter_id),
    reporter_label: str(v.reporter_label),
    target_type: str(v.target_type),
    target_id: str(v.target_id),
    target_label: str(v.target_label),
    reason: str(v.reason),
    notes: str(v.notes),
    status: str(v.status),
    created_at: str(v.created_at),
    resolved_at: str(v.resolved_at),
    open_cases: num(v.open_cases),
  };
}

export function toReports(v: unknown): Report[] {
  return asArray(v).map(toReport).filter((r): r is Report => r !== null);
}

export type UserRestriction = {
  id?: string;
  kind?: string;
  reason?: string | null;
  actor?: string | null;
  actor_label?: string | null;
  created_at?: string | null;
  lifted_at?: string | null;
  lifted_by?: string | null;
  lift_reason?: string | null;
};

export type UserDetail = {
  profile: JsonRecord;
  id: string | null;
  display_name: string | null;
  full_name: string | null;
  email_masked: string | null;
  phone_masked: string | null;
  auth: { created_at?: string | null; last_sign_in_at?: string | null; email_confirmed_at?: string | null; phone_confirmed_at?: string | null };
  onboarding: Record<string, boolean | string | null>;
  listings: ListingSummary[];
  orders_as_buyer: OrderRow[];
  orders_as_seller: OrderRow[];
  reports_made: Report[];
  reports_received: Report[];
  seller_flags: JsonRecord[];
  seller_risk_score: JsonRecord | null;
  is_listing_blocked: boolean;
  restrictions: UserRestriction[];
  cases: OpsCase[];
  is_operator: boolean;
  raw: JsonRecord;
};

export function toUserDetail(v: unknown): UserDetail | null {
  if (!isRecord(v)) return null;
  const profile = isRecord(v.profile) ? v.profile : {};
  const auth = isRecord(v.auth) ? v.auth : {};
  const onb = isRecord(v.onboarding) ? v.onboarding : {};
  const risk = isRecord(v.seller_risk_score) ? v.seller_risk_score : null;
  const onboarding: Record<string, boolean | string | null> = {};
  for (const [k, val] of Object.entries(onb)) onboarding[k] = typeof val === "boolean" ? val : str(val);
  return {
    profile,
    id: str(profile.id),
    display_name: str(profile.display_name),
    full_name: str(profile.full_name),
    email_masked: str(profile.email_masked),
    phone_masked: str(profile.phone_masked),
    auth: {
      created_at: str(auth.created_at),
      last_sign_in_at: str(auth.last_sign_in_at),
      email_confirmed_at: str(auth.email_confirmed_at),
      phone_confirmed_at: str(auth.phone_confirmed_at),
    },
    onboarding,
    listings: asArray(v.listings).map(toListingSummary).filter((l): l is ListingSummary => l !== null),
    orders_as_buyer: toOrderRows(v.orders_as_buyer),
    orders_as_seller: toOrderRows(v.orders_as_seller),
    reports_made: toReports(v.reports_made),
    reports_received: toReports(v.reports_received),
    seller_flags: asRecords(v.seller_flags),
    seller_risk_score: risk,
    is_listing_blocked: bool(risk?.is_listing_blocked) ?? false,
    restrictions: asRecords(v.restrictions).map((r) => ({
      id: str(r.id) ?? undefined,
      kind: str(r.kind) ?? undefined,
      reason: str(r.reason),
      actor: str(r.actor),
      actor_label: str(r.actor_label),
      created_at: str(r.created_at),
      lifted_at: str(r.lifted_at),
      lifted_by: str(r.lifted_by),
      lift_reason: str(r.lift_reason),
    })),
    cases: asRecords(v.cases).map(toCase).filter((c): c is OpsCase => c !== null),
    is_operator: bool(v.is_operator) ?? false,
    raw: v,
  };
}

// ---------- §3.3 listing_detail ----------

export type Bid = { id?: string; amount?: number | null; bidder_id?: string | null; bidder_display_name?: string | null; created_at?: string | null };

export type ListingDetail = {
  listing: ListingSummary | null;
  seller: UserSummary | null;
  payments: OrderRow[];
  transfer: Transfer | null;
  bids: { count: number | null; highest: number | null; highest_bidder_id: string | null; recent: Bid[] };
  reports: Report[];
  seller_flags: JsonRecord[];
  cases: OpsCase[];
  actions: OpsAction[];
  evidence: EvidenceRef[];
  raw: JsonRecord;
};

export function toListingDetail(v: unknown): ListingDetail | null {
  if (!isRecord(v)) return null;
  const bids = isRecord(v.bids) ? v.bids : {};
  return {
    listing: toListingSummary(v.listing),
    seller: toUserSummary(v.seller),
    payments: toOrderRows(v.payments),
    transfer: toTransfer(v.transfer),
    bids: {
      count: num(bids.count),
      highest: num(bids.highest),
      highest_bidder_id: str(bids.highest_bidder_id),
      recent: asRecords(bids.recent).map((b) => ({
        id: str(b.id) ?? undefined,
        amount: num(b.amount),
        bidder_id: str(b.bidder_id),
        bidder_display_name: str(b.bidder_display_name),
        created_at: str(b.created_at),
      })),
    },
    reports: toReports(v.reports),
    seller_flags: asRecords(v.seller_flags),
    cases: asRecords(v.cases).map(toCase).filter((c): c is OpsCase => c !== null),
    actions: toActions(v.actions),
    evidence: toEvidence(v.evidence),
    raw: v,
  };
}

// ---------- §3.3 money ----------

export type MoneyMetric = {
  key: string;
  value_cents: number | null;
  count: number | null;
  currency: string | null;
  from: string | null;
  to: string | null;
  definition: string | null;
  source: string | null;
  basis: string | null;
  tracked: boolean;
};

export type MoneyOverview = {
  from: string | null;
  to: string | null;
  currency: string | null;
  computed_at: string | null;
  metrics: MoneyMetric[];
  snapshot: { key: string; value: unknown; computed_at: string | null }[];
  snapshot_computed_at: string | null;
  raw: JsonRecord;
};

/** Display order for the six §5 tiles; unknown keys append after. */
export const MONEY_METRIC_ORDER = [
  "gross_captured_volume",
  "refunded_volume",
  "platform_fees_gross",
  "seller_funds_released",
  "seller_funds_pending",
  "bank_payouts",
];

export function toMoneyOverview(v: unknown): MoneyOverview | null {
  if (!isRecord(v)) return null;
  const m = isRecord(v.metrics) ? v.metrics : {};
  const metrics: MoneyMetric[] = Object.entries(m)
    .filter((e): e is [string, JsonRecord] => isRecord(e[1]))
    .map(([key, val]) => ({
      key,
      value_cents: num(val.value_cents),
      count: num(val.count),
      currency: str(val.currency),
      from: str(val.from),
      to: str(val.to),
      definition: str(val.definition),
      source: str(val.source),
      basis: str(val.basis),
      tracked: str(val.basis) !== "not_tracked",
    }))
    .sort((a, b) => {
      const ia = MONEY_METRIC_ORDER.indexOf(a.key);
      const ib = MONEY_METRIC_ORDER.indexOf(b.key);
      return (ia === -1 ? 99 : ia) - (ib === -1 ? 99 : ib);
    });
  return {
    from: str(v.from),
    to: str(v.to),
    currency: str(v.currency),
    computed_at: str(v.computed_at),
    metrics,
    snapshot: asRecords(v.snapshot).map((s) => ({ key: str(s.key) ?? "", value: s.value, computed_at: str(s.computed_at) })),
    snapshot_computed_at: str(v.snapshot_computed_at),
    raw: v,
  };
}

export type PayoutRow = Transfer & {
  seller_funds_state?: string | null;
  seller?: UserSummary | null;
  event_name?: string | null;
  payment_status?: string | null;
  amount?: number | null;
  seller_fee?: number | null;
  seller_share_cents?: number | null;
  payout_decision?: JsonRecord | null;
};

export function toPayoutRow(v: unknown): PayoutRow | null {
  const t = toTransfer(v);
  if (!t || !isRecord(v)) return null;
  return {
    ...t,
    seller_funds_state: str(v.seller_funds_state),
    seller: toUserSummary(v.seller),
    event_name: str(v.event_name),
    payment_status: str(v.payment_status),
    amount: num(v.amount),
    seller_fee: num(v.seller_fee),
    seller_share_cents: num(v.seller_share_cents),
    payout_decision: isRecord(v.payout_decision) ? v.payout_decision : null,
  };
}

export type ReconItem = {
  kind?: string;
  subject_kind?: string;
  subject_id?: string;
  subject_label?: string | null;
  detail?: JsonRecord;
  since?: string | null;
};

export function toReconItem(v: unknown): ReconItem | null {
  if (!isRecord(v)) return null;
  return {
    kind: str(v.kind) ?? undefined,
    subject_kind: str(v.subject_kind) ?? undefined,
    subject_id: str(v.subject_id) ?? undefined,
    subject_label: str(v.subject_label),
    detail: isRecord(v.detail) ? v.detail : undefined,
    since: str(v.since),
  };
}

// ---------- §3.3 job_health ----------

export type JobRun = {
  id?: string;
  job_name?: string;
  trigger?: string | null;
  started_at?: string | null;
  finished_at?: string | null;
  status?: string | null;
  attempt?: number | null;
  items_scanned?: number | null;
  cases_opened?: number | null;
  cases_resolved?: number | null;
  error?: string | null;
};

export type OpsJob = {
  job_name: string;
  enabled: boolean | null;
  last_run_at: string | null;
  last_success_at: string | null;
  last_error: string | null;
  consecutive_failures: number | null;
  backoff_until: string | null;
  updated_at: string | null;
  recent_runs: JobRun[];
};

export type CronJob = {
  jobid?: number | null;
  jobname?: string | null;
  schedule?: string | null;
  active?: boolean | null;
  last_status?: string | null;
  last_end?: string | null;
  last_message?: string | null;
  runs_24h?: number | null;
  failures_24h?: number | null;
};

export type OpsAlert = {
  alert_key?: string;
  kind?: string | null;
  state?: string | null;
  payload?: JsonRecord;
  first_fired_at?: string | null;
  last_fired_at?: string | null;
  fire_count?: number | null;
};

export type JobHealth = {
  generated_at: string | null;
  cron: { available: boolean; note: string | null; items: CronJob[] };
  ops_jobs: OpsJob[];
  webhook_backlog: { unprocessed: number | null; failed: number | null; oldest_unprocessed_at: string | null; oldest_unprocessed_event_id: string | null };
  notify: { delivery: Record<string, number>; outbox: Record<string, number>; note: string | null };
  alerts: OpsAlert[];
  raw: JsonRecord;
};

function countMap(v: unknown): Record<string, number> {
  const out: Record<string, number> = {};
  if (!isRecord(v)) return out;
  for (const [k, val] of Object.entries(v)) {
    const n = num(val);
    if (n !== null) out[k] = n;
  }
  return out;
}

export function toJobHealth(v: unknown): JobHealth | null {
  if (!isRecord(v)) return null;
  const cron = isRecord(v.cron_jobs) ? v.cron_jobs : {};
  const wb = isRecord(v.webhook_backlog) ? v.webhook_backlog : {};
  const notify = isRecord(v.notify) ? v.notify : {};
  return {
    generated_at: str(v.generated_at),
    cron: {
      available: bool(cron.available) ?? false,
      note: str(cron.note),
      items: asRecords(cron.items).map((j) => ({
        jobid: num(j.jobid),
        jobname: str(j.jobname),
        schedule: str(j.schedule),
        active: bool(j.active),
        last_status: str(j.last_status),
        last_end: str(j.last_end),
        last_message: str(j.last_message),
        runs_24h: num(j.runs_24h),
        failures_24h: num(j.failures_24h),
      })),
    },
    ops_jobs: asRecords(v.ops_jobs)
      .filter((j) => typeof j.job_name === "string")
      .map((j) => ({
        job_name: j.job_name as string,
        enabled: bool(j.enabled),
        last_run_at: str(j.last_run_at),
        last_success_at: str(j.last_success_at),
        last_error: str(j.last_error),
        consecutive_failures: num(j.consecutive_failures),
        backoff_until: str(j.backoff_until),
        updated_at: str(j.updated_at),
        recent_runs: asRecords(j.recent_runs).map((r) => ({
          id: str(r.id) ?? undefined,
          job_name: str(r.job_name) ?? undefined,
          trigger: str(r.trigger),
          started_at: str(r.started_at),
          finished_at: str(r.finished_at),
          status: str(r.status),
          attempt: num(r.attempt),
          items_scanned: num(r.items_scanned),
          cases_opened: num(r.cases_opened),
          cases_resolved: num(r.cases_resolved),
          error: str(r.error),
        })),
      })),
    webhook_backlog: {
      unprocessed: num(wb.unprocessed),
      failed: num(wb.failed),
      oldest_unprocessed_at: str(wb.oldest_unprocessed_at),
      oldest_unprocessed_event_id: str(wb.oldest_unprocessed_event_id),
    },
    notify: { delivery: countMap(notify.delivery), outbox: countMap(notify.outbox), note: str(notify.note) },
    alerts: asRecords(v.alerts).map((a) => ({
      alert_key: str(a.alert_key) ?? undefined,
      kind: str(a.kind),
      state: str(a.state),
      payload: isRecord(a.payload) ? a.payload : undefined,
      first_fired_at: str(a.first_fired_at),
      last_fired_at: str(a.last_fired_at),
      fire_count: num(a.fire_count),
    })),
    raw: v,
  };
}

// ---------- §3.3 settings / latest_summary ----------

export type Setting = { key: string; value: unknown; updated_at: string | null; updated_by: string | null; updated_by_label: string | null };

export function toSettings(v: unknown): Setting[] {
  return asRecords(v)
    .filter((s) => typeof s.key === "string")
    .map((s) => ({
      key: s.key as string,
      value: s.value,
      updated_at: str(s.updated_at),
      updated_by: str(s.updated_by),
      updated_by_label: str(s.updated_by_label),
    }));
}

export type DailySummary = {
  summary_date: string | null;
  generated_at: string | null;
  delivery_state: string | null;
  body: JsonRecord;
};

export function toDailySummary(v: unknown): DailySummary | null {
  if (!isRecord(v)) return null;
  return {
    summary_date: str(v.summary_date),
    generated_at: str(v.generated_at),
    delivery_state: str(v.delivery_state),
    body: isRecord(v.body) ? v.body : {},
  };
}

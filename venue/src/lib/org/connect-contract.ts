/**
 * The organizer payout (Stripe Connect) contract, as pure functions: what the
 * database read returns, what the `connect-onboarding` edge returns, what each
 * refusal means in the operator's words, and which action the screen may offer.
 * No I/O here, so every rule below is a unit test.
 *
 * Two sources, deliberately different (migration 093 §6/§7):
 *   kernel.get_org_connect_state(p_org_id)  — "state for humans": org_owner or
 *     org_finance, granted to authenticated, returns last4 and never the full
 *     account id. This is the only Connect read a browser session may make.
 *   edge POST connect-onboarding             — the action: mints the Stripe
 *     account link (onboarding/reconnect) or the Express dashboard login link,
 *     and re-reads Stripe for a fresh snapshot. Undeployed everywhere today.
 *
 * The full account identifier is service_role-only by design and never reaches
 * this app in any mode; nothing here can display or send one.
 */

/** `kernel.get_org_connect_state` → jsonb. `connect_account_ref` is the literal mask, never an id. */
export type OrgConnectState = {
  orgId: string;
  orgStatus: string | null;
  bound: boolean;
  last4: string | null;
  /** `kernel.organization.connect_transfers_active` — the mirror, not a live Stripe read. */
  transfersActive: boolean | null;
  /** When the mirror was last synced from Stripe; null = never. */
  syncedAt: string | null;
};

type Rec = Record<string, unknown>;
const isRec = (v: unknown): v is Rec => !!v && typeof v === "object" && !Array.isArray(v);
const str = (v: unknown): string | null => (typeof v === "string" && v.length > 0 ? v : null);
const boolOrNull = (v: unknown): boolean | null => (v === true ? true : v === false ? false : null);

/** Parses the database read. Anything but a `status:'ok'` object is null — never a half-read state. */
export function parseOrgConnectState(v: unknown): OrgConnectState | null {
  if (!isRec(v) || v.status !== "ok") return null;
  const orgId = str(v.org_id);
  if (!orgId) return null;
  const last4 = str(v.connect_account_last4);
  // The masked ref is a constant in the function body; if it ever carries an
  // account id instead, that is a server bug and this app must not render it.
  const ref = str(v.connect_account_ref);
  const maskedOk = ref === null || ref.startsWith("masked:");
  return {
    orgId,
    orgStatus: str(v.org_status),
    bound: v.connect_bound === true,
    last4: maskedOk ? (last4 && /^[A-Za-z0-9]{1,8}$/.test(last4) ? last4 : null) : null,
    transfersActive: boolOrNull(v.connect_transfers_active),
    syncedAt: str(v.connect_state_synced_at),
  };
}

/** The edge's snapshot (its `snapshotPayload`), plus `url` on the link legs. */
export type ConnectSnapshot = {
  status: string;
  last4: string | null;
  transfersActive: boolean | null;
  payoutsEnabled: boolean | null;
  detailsSubmitted: boolean | null;
  requirementsDue: string[];
  disabledReason: string | null;
  requirementsDeadline: string | null;
  checkedAt: string | null;
  /** Present on the onboarding / reconnect / dashboard legs only. */
  url: string | null;
};

/** Only an https Stripe link is ever handed to the operator. */
export function safeStripeUrl(v: unknown): string | null {
  const s = str(v);
  if (!s) return null;
  try {
    const u = new URL(s);
    if (u.protocol !== "https:") return null;
    if (u.hostname !== "stripe.com" && !u.hostname.endsWith(".stripe.com")) return null;
    return u.toString();
  } catch {
    return null;
  }
}

export function parseConnectSnapshot(v: unknown): ConnectSnapshot | null {
  if (!isRec(v)) return null;
  const status = str(v.status);
  if (!status) return null;
  const due = Array.isArray(v.requirements_due) ? v.requirements_due.filter((x): x is string => typeof x === "string") : [];
  const last4 = str(v.connect_account_last4);
  return {
    status,
    last4: last4 && /^[A-Za-z0-9]{1,8}$/.test(last4) ? last4 : null,
    transfersActive: boolOrNull(v.transfers_active),
    payoutsEnabled: boolOrNull(v.payouts_enabled),
    detailsSubmitted: boolOrNull(v.details_submitted),
    requirementsDue: due,
    disabledReason: str(v.disabled_reason),
    requirementsDeadline: str(v.requirements_deadline),
    checkedAt: str(v.checked_at),
    url: safeStripeUrl(v.url),
  };
}

/**
 * Who may do what (093 §6 gate + SoD-1). The endpoint admits org_owner and
 * org_finance; BINDING the payee is org_owner on an aal2 session only, because
 * `kernel.set_org_connect_ref` stamps the SoD-1 operand. No venue role ever —
 * a venue_manager is an employee of the venue, not the org's money identity.
 */
export type ConnectActor = { isOrgOwner: boolean; isOrgFinance: boolean; aal: "aal1" | "aal2" | null };

export type ConnectCapability = {
  /** May see the panel at all. */
  mayView: boolean;
  /** May press a button that mints a link (the endpoint's own gate). */
  mayInitiate: boolean;
  /** May complete a bind: org_owner on aal2. */
  mayBind: boolean;
  /** org_owner, but the session is not aal2 yet: offer step-up rather than a refusal. */
  needsStepUp: boolean;
};

export function connectCapability(a: ConnectActor): ConnectCapability {
  const mayView = a.isOrgOwner || a.isOrgFinance;
  return {
    mayView,
    mayInitiate: mayView,
    mayBind: a.isOrgOwner && a.aal === "aal2",
    needsStepUp: a.isOrgOwner && a.aal !== "aal2",
  };
}

/** What the screen offers next, from the state alone. */
export type ConnectAction = "set_up" | "continue" | "reconnect" | "open_dashboard" | "none";

export function nextConnectAction(s: OrgConnectState | null): ConnectAction {
  if (!s) return "none";
  if (!s.bound) return "set_up";
  if (s.transfersActive === true) return "open_dashboard";
  // Bound but not active: either the organizer never finished, or Stripe wants more.
  return "continue";
}

export const ACTION_LABEL: Record<ConnectAction, string> = {
  set_up: "Set up payouts",
  continue: "Continue setting up payouts",
  reconnect: "Reconnect with Stripe",
  open_dashboard: "Open the Stripe dashboard",
  none: "Check again",
};

/** Every refusal the edge can answer with, in words an organizer can act on. */
export type ConnectFailureKind =
  | "not_enabled" // the edge is not deployed on this project
  | "forbidden" // the caller holds no org role here
  | "requires_owner" // org_finance pressed a bind-only button
  | "step_up_required" // org_owner, but the session is not aal2
  | "replacement_required" // 409: the account is bound and must be replaced through the audited verb
  | "rate_limited"
  | "state_unavailable" // the server could not read Stripe or the mirror
  | "invalid_request" // a client bug: bad body / unexpected field
  | "transport" // never sent, or no answer
  | "server_error";

export type ConnectFailure = { kind: ConnectFailureKind; detail?: string };

export const FAILURE_COPY: Record<ConnectFailureKind, string> = {
  not_enabled: "Payout setup is not enabled on this project yet. Nothing can be sent to Stripe from here.",
  forbidden: "This account holds no role in this organization, so it cannot see or change the payout destination.",
  requires_owner:
    "Only the organization's owner can name where money is paid. Finance can start the setup and read its state, but the binding step is the owner's.",
  step_up_required: "Confirm it is you with your authenticator before naming the payout destination.",
  replacement_required:
    "This organization already has a payout account that Stripe will not return. Replacing it is a separate, audited step with a cool-down; it is not done from this screen.",
  rate_limited: "Too many attempts. Wait a moment, then try again.",
  state_unavailable: "The payout state could not be read right now. Nothing changed. Try again.",
  invalid_request: "The request was refused as malformed. Nothing changed; this is a bug in the dashboard, not your setup.",
  transport: "The request did not get through. Nothing was sent to Stripe. Try again.",
  server_error: "The server could not complete that. Nothing changed.",
};

/** HTTP status + the edge's own `code` → the kind above. Unknown codes stay honest. */
export function failureFromEdge(status: number, code: string | null, message?: string | null): ConnectFailure {
  const detail = message ?? undefined;
  if (status === 404 || status === 501) return { kind: "not_enabled", detail };
  if (status === 429) return { kind: "rate_limited", detail };
  switch (code) {
    case "dashboard_requires_owner":
      return { kind: "requires_owner", detail };
    case "step_up_unavailable":
      return { kind: "step_up_required", detail };
    case "forbidden":
      return { kind: "forbidden", detail };
    case "connect_state_unavailable":
      return { kind: "state_unavailable", detail };
    case "invalid_body":
    case "unexpected_field":
    case "invalid_org_id":
    case "invalid_status_only":
    case "method_not_allowed":
      return { kind: "invalid_request", detail };
    case "malformed_account_ref":
      return { kind: "server_error", detail };
  }
  if (status === 403) return { kind: "forbidden", detail };
  if (status === 409) return { kind: "replacement_required", detail };
  if (status === 503) return { kind: "state_unavailable", detail };
  return { kind: "server_error", detail };
}

/**
 * The body the edge accepts: EXACTLY these keys, because any other key is
 * refused `unexpected_field`. `return_url`/`refresh_url` are built by the edge
 * and refused if sent, so this app never names a redirect target.
 */
export function onboardingBody(orgId: string, opts: { statusOnly?: boolean; commandKey?: string } = {}): Record<string, unknown> {
  const body: Record<string, unknown> = { org_id: orgId };
  if (opts.statusOnly === true) body.status_only = true;
  if (opts.commandKey) body.command_key = opts.commandKey;
  return body;
}

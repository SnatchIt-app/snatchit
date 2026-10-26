import { CREDENTIAL_TYP, decodeCredentialWire, type CredentialClaims } from "@/lib/scan/wire";

/**
 * The five things a door person can be told, and nothing else. Every outcome
 * is derived from the server's answer to the admission verb
 * (`venue_cmd.record_scan`, CONTRACTS.md C7) or from a refusal the client can
 * make on its own WITHOUT admitting anyone. There is no client-side admit:
 * "admitted" exists only when the server said so for THIS command key.
 */
export type ScanPrior = { scanId: string | null; occurredAt: string | null; actorLabel: string | null; deviceLabel: string | null };

export type CannotVerifyWhy =
  | "offline" // the phone reports no network
  | "timeout" // the request was sent and nothing came back in time
  | "transport" // the request failed before or while sending; unknown whether it arrived
  | "not_enabled" // venue_cmd is not exposed / native scanning is dark on this project
  | "session_not_admitting" // the session is not in an admitting status
  | "rate_limited"
  | "server_error"
  | "keyring" // the trusted keyring could not be read: no pass can be verified
  | "demo"; // fixtures mode: there is no admission server

export type ScanOutcome =
  | { kind: "admitted"; atomId: string; scanId: string | null }
  | { kind: "already_used"; atomId: string; prior: ScanPrior | null; possiblyThisPhone: boolean }
  | { kind: "wrong_event"; atomId: string; tokenSessionId: string }
  | { kind: "invalid"; why: InvalidWhy; reason?: string }
  | { kind: "cannot_verify"; why: CannotVerifyWhy; retrySameKey: boolean; detail?: string };

export type BlockedWhy = "signed_out" | "no_role" | "config";
export type ScanActionResult = { kind: "outcome"; outcome: ScanOutcome } | { kind: "blocked"; why: BlockedWhy };

/** Why a pass is INVALID: the server's reason (B's 183 vocabulary) or the scanner's own refusal before the call. */
export type InvalidWhy =
  | "server" // the server said invalid with no reason (pre-183)
  | "voided" // refunded or cancelled
  | "expired" // the ticket's own expiry (server) or the credential past its tolerance (verifier)
  | "not_active"
  | "listed_locked"
  | "credential_stale" // an old version of the pass (re-issued since)
  | "credential_claims_malformed"
  | "unknown_atom"
  | "other"
  | "malformed" // the code does not decode as a pass
  | "wrong_type" // a Snatch It credential of another kind
  | "stale_pass" // past its own exp beyond the tolerance (verifier)
  | "not_trusted"; // unknown key, revoked/out-of-window key, algorithm mismatch, bad signature

export type Classification =
  | { kind: "ok"; claims: CredentialClaims }
  | { kind: "wrong_event"; atomId: string; tokenSessionId: string }
  | { kind: "invalid"; why: "malformed" | "wrong_type" };

/**
 * What the client may decide on its own, all refusals: a pass that does not
 * decode, a pass of another credential type, a pass whose own session claim
 * is not the selected session (WRONG EVENT — the server would fold this into
 * `invalid`), and a pass past its own `exp` (the buyer app re-mints every
 * `credential.app_ttl_interval`; a screenshot does not — asking for a fresh
 * pass costs a tap, admitting an old one costs the door).
 */
/**
 * Expiry is NOT decided on the phone: the server action's verifier applies the reference tolerance with
 * its own clock (B §3 step 8), so a phone clock far ahead never refuses a valid pass on its own (E, F-R5).
 */
export function classifyToken(wire: unknown, selectedSessionId: string): Classification {
  const claims = decodeCredentialWire(wire);
  if (!claims) return { kind: "invalid", why: "malformed" };
  if (claims.typ !== CREDENTIAL_TYP) return { kind: "invalid", why: "wrong_type" };
  if (claims.sessionId.toLowerCase() !== selectedSessionId.toLowerCase()) return { kind: "wrong_event", atomId: claims.atomId, tokenSessionId: claims.sessionId };
  return { kind: "ok", claims };
}

type Rec = Record<string, unknown>;
const str = (v: unknown): string | null => (typeof v === "string" && v.length > 0 ? v : null);

function priorFrom(v: unknown): ScanPrior | null {
  if (!v || typeof v !== "object") return null;
  const p = v as Rec;
  return { scanId: str(p.scan_id), occurredAt: str(p.occurred_at), actorLabel: str(p.actor_label), deviceLabel: str(p.device_label) };
}

/**
 * The server's jsonb for the admission verb: `{status:'ok', scan_id, result}`
 * with `result ∈ admitted | duplicate | invalid`; after B's 183 a `duplicate`
 * may carry `prior`. Anything else is CANNOT VERIFY, never a green.
 * `retried` = this answer came back for a re-sent command key, so a
 * `duplicate` may be this phone's own earlier attempt landing (amber, with
 * that said).
 */
export function outcomeFromRpc(data: unknown, atomId: string, retried: boolean): ScanOutcome {
  if (!data || typeof data !== "object") return { kind: "cannot_verify", why: "server_error", retrySameKey: true, detail: "no receipt" };
  const d = data as Rec;
  if (d.status !== "ok") return { kind: "cannot_verify", why: "server_error", retrySameKey: true, detail: str(d.status) ?? "unexpected status" };
  switch (d.result) {
    case "admitted":
      return { kind: "admitted", atomId, scanId: str(d.scan_id) };
    case "duplicate":
      return { kind: "already_used", atomId, prior: priorFrom(d.prior), possiblyThisPhone: retried };
    case "invalid": {
      // 183 carries a reason; wrong_session is WRONG EVENT in the door's words. No reason = pre-183 "invalid".
      const reason = str(d.reason);
      if (reason === "wrong_session") return { kind: "wrong_event", atomId, tokenSessionId: "" };
      const known: InvalidWhy[] = ["voided", "expired", "not_active", "listed_locked", "credential_stale", "credential_claims_malformed", "unknown_atom", "other"];
      return reason ? { kind: "invalid", why: (known as string[]).includes(reason) ? (reason as InvalidWhy) : "other", reason } : { kind: "invalid", why: "server" };
    }
    default:
      return { kind: "cannot_verify", why: "server_error", retrySameKey: true, detail: `result ${String(d.result)}` };
  }
}

export type PgErrorLike = { code?: string | null; message?: string | null; details?: string | null } | null | undefined;

/**
 * PostgREST / Postgres failures of the admission call. The dark state
 * (`venue_cmd` not exposed → PGRST106, wrapper absent → PGRST202, native
 * scanning flag off → `feature_disabled`) is "not enabled", not an outage and
 * not a refusal of the pass. `42501` is the staff member's own problem
 * (no venue_scanner / venue_manager role here) and blocks the screen.
 */
export function outcomeFromRpcError(e: PgErrorLike, status?: number): ScanActionResult {
  const code = e?.code ?? "";
  const msg = (e?.message ?? "").toLowerCase();
  if (status === 401 || code === "PGRST301" || msg.includes("jwt expired") || msg.includes("invalid jwt")) return { kind: "blocked", why: "signed_out" };
  if (code === "42501" || msg.includes("insufficient_privilege")) return { kind: "blocked", why: "no_role" };
  if (code === "PGRST106" || code === "PGRST202" || msg.includes("feature_disabled")) return { kind: "outcome", outcome: { kind: "cannot_verify", why: "not_enabled", retrySameKey: false } };
  if (msg.includes("session_not_admitting")) return { kind: "outcome", outcome: { kind: "cannot_verify", why: "session_not_admitting", retrySameKey: false, detail: e?.message ?? undefined } };
  if (status === 429) return { kind: "outcome", outcome: { kind: "cannot_verify", why: "rate_limited", retrySameKey: true } };
  return { kind: "outcome", outcome: { kind: "cannot_verify", why: "server_error", retrySameKey: true, detail: e?.message ?? undefined } };
}

export type Tone = "success" | "warning" | "danger" | "neutral";

export const OUTCOME_TITLE: Record<ScanOutcome["kind"], string> = {
  admitted: "ADMITTED",
  already_used: "ALREADY USED",
  wrong_event: "WRONG EVENT",
  invalid: "INVALID",
  cannot_verify: "CANNOT VERIFY",
};

export const OUTCOME_TONE: Record<ScanOutcome["kind"], Tone> = {
  admitted: "success",
  already_used: "warning",
  wrong_event: "danger",
  invalid: "danger",
  cannot_verify: "neutral",
};

const CANNOT_VERIFY_COPY: Record<CannotVerifyWhy, string> = {
  offline: "This phone is offline. Nothing was checked; do not admit on the phone's word.",
  timeout: "Sent, no answer. The scan may or may not have been recorded. Check again with the same key before deciding.",
  transport: "The request did not get through. Check again with the same key; if that keeps failing, use another phone or hotspot.",
  not_enabled: "Scanning is not enabled on this project yet. Nothing can be verified here.",
  session_not_admitting: "This session is not admitting right now (not live, or doors are closed).",
  rate_limited: "Too many requests from this account. Wait a moment, then check again.",
  server_error: "The server could not answer. Check again with the same key.",
  keyring: "The trusted key list could not be read, so no pass can be verified right now. Check again.",
  demo: "Demo — sample data. There is no admission server behind this screen.",
};

const INVALID_COPY: Record<InvalidWhy, string> = {
  server: "Not valid for this session. Refunded, cancelled, listed for resale, or not a pass for tonight.",
  voided: "Refunded or cancelled. Not valid.",
  expired: "This ticket expired. Not valid.",
  not_active: "This ticket is not active (already used, voided or not yet issued). Not valid.",
  listed_locked: "Listed for resale and locked. Not valid until the listing ends.",
  credential_stale: "This is an old version of the pass (it was re-issued). Ask the guest to open the Snatch It app for the current one.",
  credential_claims_malformed: "The pass's claims do not match the ticket. Not valid.",
  unknown_atom: "Unknown ticket. Not valid.",
  other: "Not valid for this session.",
  malformed: "This code is not a Snatch It pass.",
  stale_pass: "This pass is out of date. Ask the guest to open it again in the Snatch It app and rescan.",
  wrong_type: "This code is a Snatch It credential of another kind, not a ticket pass.",
  not_trusted: "This pass is not signed by a trusted Snatch It key. Not valid.",
};

/** HH:MM in the given zone (the venue's where known, else the phone's). */
export function clock(iso: string | null, timeZone: string | null): string | null {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  try {
    return new Intl.DateTimeFormat("en-US", { hour: "2-digit", minute: "2-digit", hour12: false, ...(timeZone ? { timeZone } : {}) }).format(d);
  } catch {
    return null;
  }
}

/** The one line under the big word. */
export function outcomeDetail(o: ScanOutcome, timeZone: string | null): string {
  switch (o.kind) {
    case "admitted":
      return "Let them in.";
    case "already_used": {
      const at = clock(o.prior?.occurredAt ?? null, timeZone);
      const where = o.prior?.deviceLabel ?? o.prior?.actorLabel ?? null;
      const when = at ? `Already admitted at ${at}${where ? ` (${where})` : ""}.` : "Already admitted once for this session.";
      return o.possiblyThisPhone ? `${when} That may be this phone's previous attempt landing: confirm with the guest before refusing.` : when;
    }
    case "wrong_event":
      return "This pass is for a different session or event. Not valid at this door.";
    case "invalid":
      return INVALID_COPY[o.why];
    case "cannot_verify":
      return CANNOT_VERIFY_COPY[o.why];
  }
}

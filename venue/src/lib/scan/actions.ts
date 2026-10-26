"use server";

import "server-only";

import { probeSession } from "@/lib/auth/session";
import { dbGetEvent, dbMyGrants } from "@/lib/db/adapters";
import { mapReadError, type ReadResult } from "@/lib/db/read-result";
import { DATA_SOURCE } from "@/lib/env";
import { eventInScope, isUuid } from "@/lib/page";
import { canScan, derivePrincipal } from "@/lib/roles";
import { classifyToken, outcomeFromRpc, outcomeFromRpcError, type ScanActionResult, type ScanOutcome } from "@/lib/scan/outcome";
import { createSupabaseServerClient, SupabaseConfigError } from "@/lib/supabase/server";

/**
 * The admission call, server-side, under the signed-in staff member's own
 * session (CONTRACTS.md C7, A's P8 amendment of 2026-10-26: the staff-session
 * path). Nothing here admits: the server's receipt for THIS command key is
 * the only source of "admitted", and every refusal, failure or silence is
 * rendered as what it is.
 *
 *   venue_cmd.record_scan(p_atom_id, p_session_id, p_scan_meta, p_command_key)   (D, 163)
 *   venue_cmd.validate_ticket_online(p_atom_id, p_session_id)                   (D, 163 wrapper over 086)
 *   venue_api.session_admissions(session_id, admitted, duplicate, invalid, last_admitted_at)   (D, 163; final name 2026-10-26)
 *
 * Until `venue_cmd` is exposed on a project, PostgREST answers PGRST106 /
 * PGRST202 and the screen says scanning is not enabled — the dark state, not
 * an outage, not a refusal of the pass.
 */
const CMD = "venue_cmd";
const COUNTERS_VIEW = "session_admissions";
const SCAN_TIMEOUT_MS = 8000;

export type ScanInput = { orgId: string; venueId: string; eventId: string; sessionId: string; wire: string; commandKey: string; deviceLabel: string; retried: boolean };

type RpcResponse = { data: unknown; error: { code?: string; message?: string; details?: string } | null; status?: number };
type CmdClient = { rpc(fn: string, args: Record<string, unknown>): PromiseLike<RpcResponse> };

type Gate = { ok: true; client: CmdClient } | { ok: false; result: ScanActionResult };

/** Signed in, holding a scanning role at the route venue, and the session belongs to the route event. Fail closed. */
async function gate(input: Pick<ScanInput, "orgId" | "venueId" | "eventId" | "sessionId">): Promise<Gate> {
  const blocked = (why: "signed_out" | "no_role" | "config"): Gate => ({ ok: false, result: { kind: "blocked", why } });
  if (![input.orgId, input.venueId, input.eventId, input.sessionId].every(isUuid)) return blocked("no_role");
  const session = await probeSession();
  if (!session.ok) return blocked("config");
  if (!session.user) return blocked("signed_out");
  const grants = await dbMyGrants(input.venueId, input.orgId);
  if (!grants.ok) return grants.kind === "auth" ? blocked("signed_out") : grants.kind === "config" ? blocked("config") : blocked("no_role");
  const principal = derivePrincipal(grants.data);
  if (!principal || !canScan(principal)) return blocked("no_role");
  const event = await dbGetEvent(input.eventId);
  if (!event.ok) return event.kind === "auth" ? blocked("signed_out") : blocked("no_role");
  if (!event.data || !eventInScope(event.data, { venueId: input.venueId, orgId: input.orgId })) return blocked("no_role");
  if (!event.data.sessions.some((s) => s.sessionId.toLowerCase() === input.sessionId.toLowerCase())) return blocked("no_role");
  let client: CmdClient;
  try {
    client = (await createSupabaseServerClient()).schema(CMD) as unknown as CmdClient;
  } catch (e) {
    return e instanceof SupabaseConfigError ? blocked("config") : blocked("config");
  }
  return { ok: true, client };
}

function withTimeout<T>(p: PromiseLike<T>, ms: number): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error("timeout")), ms);
    p.then(
      (v) => {
        clearTimeout(t);
        resolve(v);
      },
      (e) => {
        clearTimeout(t);
        reject(e);
      },
    );
  });
}

/**
 * Today a sequential repeat of a scanned pass answers `invalid` (the kernel
 * raises not_active before any uniqueness check; B's 183 turns it into
 * `duplicate` + prior). So a server `invalid` is resolved through the read
 * before it is shown: a pass whose state is `scanned` is ALREADY USED, not
 * forged. The read is the same role gate; if it fails, the honest answer is
 * the server's own word.
 */
async function resolveInvalid(client: CmdClient, atomId: string, sessionId: string, retried: boolean): Promise<ScanOutcome> {
  try {
    const r = await withTimeout(client.rpc("validate_ticket_online", { p_atom_id: atomId, p_session_id: sessionId }), SCAN_TIMEOUT_MS);
    const d = r.data as { status?: unknown; ticket_state?: unknown } | null;
    if (!r.error && d && d.status === "ok" && d.ticket_state === "scanned") return { kind: "already_used", atomId, prior: null, possiblyThisPhone: retried };
  } catch {
    // fall through: the server said invalid and the read could not say more
  }
  return { kind: "invalid", why: "server" };
}

export async function scanAction(input: ScanInput): Promise<ScanActionResult> {
  if (DATA_SOURCE !== "database") return { kind: "outcome", outcome: { kind: "cannot_verify", why: "demo", retrySameKey: false } };
  const g = await gate(input);
  if (!g.ok) return g.result;
  const nowSeconds = Math.floor(Date.now() / 1000);
  const c = classifyToken(input.wire, input.sessionId, nowSeconds);
  if (c.kind === "invalid") return { kind: "outcome", outcome: { kind: "invalid", why: c.why } };
  if (c.kind === "wrong_event") return { kind: "outcome", outcome: { kind: "wrong_event", atomId: c.atomId, tokenSessionId: c.tokenSessionId } };
  const atomId = c.claims.atomId;
  if (typeof input.commandKey !== "string" || input.commandKey.length < 8 || input.commandKey.length > 128) return { kind: "outcome", outcome: { kind: "cannot_verify", why: "server_error", retrySameKey: false, detail: "bad command key" } };
  const deviceLabel = (input.deviceLabel ?? "").trim().slice(0, 40);
  let res: RpcResponse;
  try {
    res = await withTimeout(
      g.client.rpc("record_scan", {
        p_atom_id: atomId,
        p_session_id: input.sessionId,
        // No occurred_at on the online path: the server writes now() (108 coalesces a client value into
        // venue.scan.occurred_at, and D's last_admitted_at reads it), so the phone clock must never set it (E, F-R1).
        p_scan_meta: { device_label: deviceLabel || "phone", client: "venue-web-scanner/1" },
        p_command_key: input.commandKey,
      }),
      SCAN_TIMEOUT_MS,
    );
  } catch (e) {
    const timeout = e instanceof Error && e.message === "timeout";
    return { kind: "outcome", outcome: { kind: "cannot_verify", why: timeout ? "timeout" : "transport", retrySameKey: true } };
  }
  if (res.error) return outcomeFromRpcError(res.error, res.status);
  const outcome = outcomeFromRpc(res.data, atomId, input.retried);
  if (outcome.kind === "invalid") return { kind: "outcome", outcome: await resolveInvalid(g.client, atomId, input.sessionId, input.retried) };
  return { kind: "outcome", outcome };
}

export type SessionScanCounters = { sessionId: string; admitted: number; duplicate: number; invalid: number; lastAdmittedAt: string | null };

/** Measured attendance for one session (D's 163 view). Unavailable is reported as unavailable, never as zero. */
export async function readSessionScanCounters(input: { orgId: string; venueId: string; eventId: string; sessionId: string }): Promise<ReadResult<SessionScanCounters | null>> {
  const read = `venue_api.${COUNTERS_VIEW}`;
  if (DATA_SOURCE !== "database") return { ok: false, kind: "not_exposed", message: "Demo — sample data has no scan ledger.", read };
  const g = await gate(input);
  if (!g.ok) return { ok: false, kind: g.result.kind === "blocked" && g.result.why === "signed_out" ? "auth" : "permission", message: "Not readable for this account.", read };
  let c: { from(view: string): { select(cols: string): { eq(col: string, v: string): { limit(n: number): PromiseLike<RpcResponse> } } } };
  try {
    c = (await createSupabaseServerClient()).schema("venue_api") as unknown as typeof c;
  } catch (e) {
    return { ok: false, kind: "config", message: e instanceof Error ? e.message : "Supabase client unavailable", read };
  }
  let r: RpcResponse;
  try {
    r = await withTimeout(c.from(COUNTERS_VIEW).select("session_id,admitted,duplicate,invalid,last_admitted_at").eq("session_id", input.sessionId).limit(1), SCAN_TIMEOUT_MS);
  } catch (e) {
    return { ok: false, kind: "transport", message: e instanceof Error ? e.message : "request failed", read };
  }
  if (r.error) return mapReadError(read, r.error, r.status);
  const rows = Array.isArray(r.data) ? (r.data as Record<string, unknown>[]) : [];
  const row = rows[0];
  if (!row) return { ok: true, data: null };
  const n = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : Number.NaN);
  const out = { sessionId: String(row.session_id ?? input.sessionId), admitted: n(row.admitted), duplicate: n(row.duplicate), invalid: n(row.invalid), lastAdmittedAt: typeof row.last_admitted_at === "string" ? row.last_admitted_at : null };
  if ([out.admitted, out.duplicate, out.invalid].some(Number.isNaN)) return { ok: false, kind: "error", message: "Counters row has a non-numeric count.", read };
  return { ok: true, data: out };
}

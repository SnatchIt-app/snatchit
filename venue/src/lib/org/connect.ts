"use server";

import "server-only";

import { cookies } from "next/headers";

import { probeSession } from "@/lib/auth/session";
import { mapReadError, transportFailure, type ReadResult } from "@/lib/db/read-result";
import { DATA_SOURCE, SUPABASE_ANON_KEY, SUPABASE_URL } from "@/lib/env";
import { isUuid } from "@/lib/page";
import { connectCapability, failureFromEdge, onboardingBody, parseConnectSnapshot, parseOrgConnectState, type ConnectCapability, type ConnectFailure, type ConnectSnapshot, type OrgConnectState } from "@/lib/org/connect-contract";
import { connectContextCookieOptions, isPayoutsRole } from "@/lib/org/connect-return";
import { createSupabaseServerClient, SupabaseConfigError } from "@/lib/supabase/server";

/**
 * Organizer payouts (Stripe Connect), server side.
 *
 * The STATE comes from the database under the operator's own session:
 * `kernel.get_org_connect_state(p_org_id)` (093 §6) — org_owner or org_finance,
 * last4 only. `kernel` is PostgREST-exposed and `authenticated` holds USAGE, so
 * this read works today, with no edge deployed.
 *
 * The ACTIONS go to the `connect-onboarding` edge (verify_jwt true, undeployed
 * everywhere as of 2026-10-26), which mints the Stripe link and re-reads Stripe.
 * The request carries the operator's own access token, because the edge's
 * authority decisions and `kernel.set_org_connect_ref`'s SoD-1 stamp are made
 * from `auth.uid()` and the token's `aal`. Nothing here chooses a redirect
 * target: the edge refuses a caller-supplied return_url/refresh_url by design.
 *
 * Nothing in this module can bind a payout destination on its own, and the full
 * account identifier never reaches this app in any mode.
 */
const EDGE = "connect-onboarding";
const TIMEOUT_MS = 15_000;

export type OrgConnectView = {
  capability: ConnectCapability;
  state: OrgConnectState | null;
  /** Why the state could not be read, if it could not. */
  failure: ConnectFailure | null;
  /** False when the app is not in database mode: nothing to read or send. */
  live: boolean;
};

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

type RpcResponse = { data: unknown; error: { code?: string; message?: string } | null; status?: number };
type KernelClient = { rpc(fn: string, args: Record<string, unknown>): PromiseLike<RpcResponse> };
type OrgRoleRow = { org_id: string; role: string };

/** The caller's own org roles for this org, from `venue_api.my_org_roles` (RLS-scoped to the caller). */
async function orgRoles(orgId: string): Promise<{ ok: true; roles: string[] } | { ok: false; failure: ConnectFailure }> {
  let c: { from(v: string): { select(cols: string): { eq(col: string, v: string): PromiseLike<RpcResponse> } } };
  try {
    c = (await createSupabaseServerClient()).schema("venue_api") as unknown as typeof c;
  } catch {
    return { ok: false, failure: { kind: "state_unavailable", detail: "client unavailable" } };
  }
  let r: RpcResponse;
  try {
    r = await withTimeout(c.from("my_org_roles").select("org_id,role").eq("org_id", orgId), TIMEOUT_MS);
  } catch (e) {
    return { ok: false, failure: { kind: "transport", detail: e instanceof Error ? e.message : undefined } };
  }
  if (r.error) return { ok: false, failure: { kind: r.error.code === "PGRST106" ? "not_enabled" : "state_unavailable", detail: r.error.message } };
  const rows = Array.isArray(r.data) ? (r.data as OrgRoleRow[]) : [];
  return { ok: true, roles: rows.filter((x) => typeof x?.role === "string").map((x) => x.role) };
}

/**
 * Every org this caller may see payouts for. The return and refresh routes
 * need it because the edge's URLs carry no org — see lib/org/connect-return.ts.
 * Unfiltered on purpose; RLS scopes `my_org_roles` to the caller.
 */
export async function myPayoutOrgIds(): Promise<{ ok: true; orgIds: string[] } | { ok: false; failure: ConnectFailure }> {
  if (DATA_SOURCE !== "database") return { ok: true, orgIds: [] };
  const session = await probeSession();
  if (!session.ok) return { ok: false, failure: { kind: "state_unavailable", detail: session.message } };
  if (!session.user) return { ok: false, failure: { kind: "forbidden" } };
  let c: { from(v: string): { select(cols: string): PromiseLike<RpcResponse> } };
  try {
    c = (await createSupabaseServerClient()).schema("venue_api") as unknown as typeof c;
  } catch {
    return { ok: false, failure: { kind: "state_unavailable", detail: "client unavailable" } };
  }
  let r: RpcResponse;
  try {
    r = await withTimeout(c.from("my_org_roles").select("org_id,role"), TIMEOUT_MS);
  } catch (e) {
    return { ok: false, failure: { kind: "transport", detail: e instanceof Error ? e.message : undefined } };
  }
  if (r.error) return { ok: false, failure: { kind: r.error.code === "PGRST106" ? "not_enabled" : "state_unavailable", detail: r.error.message } };
  const rows = Array.isArray(r.data) ? (r.data as OrgRoleRow[]) : [];
  const ids = rows.filter((x) => typeof x?.org_id === "string" && typeof x?.role === "string" && isPayoutsRole(x.role)).map((x) => x.org_id);
  return { ok: true, orgIds: [...new Set(ids)] };
}

/** What the payouts page renders: the caller's capability and the org's Connect state. Fail closed. */
export async function readOrgConnect(orgId: string): Promise<OrgConnectView> {
  const closed = (failure: ConnectFailure | null, live = true): OrgConnectView => ({ capability: { mayView: false, mayInitiate: false, mayBind: false, needsStepUp: false }, state: null, failure, live });
  if (!isUuid(orgId)) return closed({ kind: "forbidden" });
  if (DATA_SOURCE !== "database") return closed(null, false);
  const session = await probeSession();
  if (!session.ok) return closed({ kind: "state_unavailable", detail: session.message });
  if (!session.user) return closed({ kind: "forbidden" });
  const roles = await orgRoles(orgId);
  if (!roles.ok) return closed(roles.failure);
  const capability = connectCapability({ isOrgOwner: roles.roles.includes("org_owner"), isOrgFinance: roles.roles.includes("org_finance"), aal: session.user.aal });
  if (!capability.mayView) return closed({ kind: "forbidden" });

  let c: KernelClient;
  try {
    c = (await createSupabaseServerClient()).schema("kernel") as unknown as KernelClient;
  } catch (e) {
    return { capability, state: null, failure: { kind: "state_unavailable", detail: e instanceof SupabaseConfigError ? e.message : "client unavailable" }, live: true };
  }
  let r: RpcResponse;
  try {
    r = await withTimeout(c.rpc("get_org_connect_state", { p_org_id: orgId }), TIMEOUT_MS);
  } catch (e) {
    return { capability, state: null, failure: { kind: "transport", detail: e instanceof Error ? e.message : undefined }, live: true };
  }
  if (r.error) {
    const f = mapReadError("kernel.get_org_connect_state", r.error, r.status);
    const kind = f.kind === "permission" ? "forbidden" : f.kind === "not_exposed" ? "not_enabled" : f.kind === "auth" ? "forbidden" : "state_unavailable";
    return { capability, state: null, failure: { kind, detail: f.message }, live: true };
  }
  const state = parseOrgConnectState(r.data);
  return { capability, state, failure: state ? null : { kind: "state_unavailable", detail: "unrecognised payload" }, live: true };
}

export type ConnectActionResult = { ok: true; snapshot: ConnectSnapshot } | { ok: false; failure: ConnectFailure };

/**
 * One POST to the edge with the operator's own token. `statusOnly` is the
 * refresh (no link minted); otherwise the edge decides between onboarding,
 * reconnect and the Express dashboard from the org's bound state — this app
 * does not choose, and cannot.
 */
export async function callOnboardingEdge(orgId: string, opts: { statusOnly?: boolean; commandKey?: string } = {}): Promise<ConnectActionResult> {
  if (!isUuid(orgId)) return { ok: false, failure: { kind: "invalid_request", detail: "org id" } };
  if (DATA_SOURCE !== "database") return { ok: false, failure: { kind: "not_enabled", detail: "fixtures mode" } };
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) return { ok: false, failure: { kind: "not_enabled", detail: "no project configured" } };
  // The caller's capability is re-read here, not trusted from the page: this is
  // a server action and a page's props are not an authorization.
  const view = await readOrgConnect(orgId);
  if (!view.capability.mayInitiate) return { ok: false, failure: view.failure ?? { kind: "forbidden" } };

  let token: string | null = null;
  try {
    const supabase = await createSupabaseServerClient();
    const { data } = await supabase.auth.getSession();
    token = data.session?.access_token ?? null;
  } catch {
    token = null;
  }
  if (!token) return { ok: false, failure: { kind: "forbidden", detail: "no session token" } };

  let res: Response;
  try {
    res = await withTimeout(
      fetch(`${SUPABASE_URL.replace(/\/+$/, "")}/functions/v1/${EDGE}`, {
        method: "POST",
        headers: { "content-type": "application/json", apikey: SUPABASE_ANON_KEY, authorization: `Bearer ${token}` },
        body: JSON.stringify(onboardingBody(orgId, opts)),
        cache: "no-store",
      }),
      TIMEOUT_MS,
    );
  } catch (e) {
    return { ok: false, failure: { kind: "transport", detail: e instanceof Error && e.message === "timeout" ? "no answer" : "not sent" } };
  }
  let body: unknown = null;
  try {
    body = await res.json();
  } catch {
    body = null;
  }
  if (!res.ok) {
    const rec = body && typeof body === "object" ? (body as Record<string, unknown>) : {};
    const code = typeof rec.code === "string" ? rec.code : null;
    const message = typeof rec.error === "string" ? rec.error : typeof rec.message === "string" ? rec.message : null;
    return { ok: false, failure: failureFromEdge(res.status, code, message) };
  }
  const snapshot = parseConnectSnapshot(body);
  if (!snapshot) return { ok: false, failure: { kind: "server_error", detail: "unrecognised payload" } };
  return { ok: true, snapshot };
}

/** The refresh button: re-reads Stripe without minting a link. */
export async function refreshOrgConnect(orgId: string): Promise<ConnectActionResult> {
  return callOnboardingEdge(orgId, { statusOnly: true });
}

/** The link button. The edge mints onboarding, reconnect or the dashboard link as the bound state dictates. */
export async function startOrgOnboarding(orgId: string, commandKey: string): Promise<ConnectActionResult> {
  if (typeof commandKey !== "string" || commandKey.length < 8 || commandKey.length > 128) return { ok: false, failure: { kind: "invalid_request", detail: "command key" } };
  const result = await callOnboardingEdge(orgId, { commandKey });
  // Remember which org this attempt was for. The edge's return and refresh URLs
  // may carry no query or fragment (Ruling G §3), so without this the way back
  // has nothing to go on but the caller's roles. Written only once the edge has
  // actually handed back a link, and only for a caller it just authorised.
  if (result.ok && result.snapshot.url) {
    try {
      const jar = await cookies();
      const { name, ...options } = connectContextCookieOptions();
      jar.set(name, orgId.toLowerCase(), options);
    } catch {
      // A render path with read-only cookies: the way back falls through to the
      // caller's own org roles, which is the designed fallback, not a failure.
    }
  }
  return result;
}

/**
 * E-F12: the shape guard that used to live here was `export const __transportFailureShape =
 * transportFailure`, and `transportFailure` is SYNCHRONOUS (read-result.ts:30). A file-level
 * "use server" module may export only async functions, so that was an illegal server-action export —
 * latent rather than build-breaking only because Next's static check cannot resolve asyncness across
 * modules, which is exactly how it survived review. The guard now lives in
 * tests/org-connect-contract.test.ts, where a shape assertion costs nothing at runtime and cannot
 * become a broken production build later.
 */
export type { ReadResult };

/**
 * Preview controls. Two query parameters drive every surface:
 *
 *   ?role=<principal>   who is looking (default venue_manager) — lib/roles.ts
 *   ?state=<state>      force a surface state: loading · empty · error · denied · nodata
 *
 * `nodata` is the "filtered to nothing" state, kept distinct from `empty`
 * ("no sales yet") on purpose — spec §9.7 says collapsing them makes an
 * operator think the event failed.
 */
import { DEFAULT_PRINCIPAL, isPrincipal, type Principal } from "@/lib/roles";

export const PREVIEW_STATES = ["live", "loading", "empty", "error", "denied", "nodata"] as const;
export type PreviewState = (typeof PREVIEW_STATES)[number];

export type SearchParams = Record<string, string | string[] | undefined>;

export type PreviewContext = { role: Principal; state: PreviewState };

function first(v: string | string[] | undefined): string | undefined {
  return Array.isArray(v) ? v[0] : v;
}

export function readPreviewContext(sp: SearchParams | undefined): PreviewContext {
  const roleRaw = first(sp?.role);
  const stateRaw = first(sp?.state);
  const role = isPrincipal(roleRaw) ? roleRaw : DEFAULT_PRINCIPAL;
  const state = (PREVIEW_STATES as readonly string[]).includes(stateRaw ?? "") ? (stateRaw as PreviewState) : "live";
  return { role, state };
}

/** Build a link that keeps the current role/state so the reviewer can walk the flow in one persona. */
export function withPreview(href: string, ctx: PreviewContext, overrides: Partial<PreviewContext> = {}): string {
  const role = overrides.role ?? ctx.role;
  const state = overrides.state ?? ctx.state;
  const params = new URLSearchParams();
  if (role !== DEFAULT_PRINCIPAL) params.set("role", role);
  if (state !== "live") params.set("state", state);
  const q = params.toString();
  return q ? `${href}?${q}` : href;
}

/** The label every surface shows so nobody mistakes the preview for live operations. */
export const PREVIEW_DATA_LABEL = "Preview data — sample fixtures, not live venue operations";

import { ORG, PREVIEW_NOW, VENUE } from "@/fixtures/venue";
import { getEvent } from "@/lib/data";
import { DATA_SOURCE } from "@/lib/env";
import { readPreviewContext, type PreviewContext, type SearchParams } from "@/lib/preview";
import { probeSession, type SessionProbe } from "@/lib/auth/session";
import { dbGetEvent, dbMyGrants } from "@/lib/db/adapters";
import type { ReadFailure } from "@/lib/db/read-result";
import { derivePrincipal, type GrantSet } from "@/lib/roles";
import type { Event } from "@/lib/types";

export type PageParams = { org: string; venue: string; event?: string };

/**
 * Spec §4.4 rule 5 — a deep link to another org/venue fails closed. In fixture
 * mode the only scope is the sample org/venue. In database mode the route ids
 * are untrusted parameters: the caller's own grants decide entry, and RLS
 * decides every row after that.
 */
export function resolveScope(params: PageParams): { ok: true; basePath: string; venueId: string; orgId: string } | { ok: false } {
  if (DATA_SOURCE === "fixtures") {
    if (params.org !== ORG.orgId || params.venue !== VENUE.venueId) return { ok: false };
    return { ok: true, basePath: `/o/${ORG.orgId}/v/${VENUE.venueId}`, venueId: VENUE.venueId, orgId: ORG.orgId };
  }
  if (!isUuid(params.org) || !isUuid(params.venue)) return { ok: false };
  return { ok: true, basePath: `/o/${params.org}/v/${params.venue}`, venueId: params.venue, orgId: params.org };
}

export function isUuid(v: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
}

/**
 * Database-mode entry policy (spec §5): the dashboard renders only for a
 * signed-in caller holding at least one grant at the route's venue or org.
 * Public catalog rows stay readable elsewhere (consumer surfaces); they are
 * not a reason to show an operator dashboard.
 */
export type Entry =
  | { kind: "fixtures" }
  | { kind: "failure"; failure: ReadFailure } // config / transport / auth (no session)
  | { kind: "denied" } // signed in, no grant here
  | { kind: "ok"; grants: GrantSet };

export async function readPage(paramsP: Promise<PageParams>, spP: Promise<SearchParams>) {
  const [params, sp] = await Promise.all([paramsP, spP]);
  let ctx: PreviewContext = readPreviewContext(sp);
  const scope = resolveScope(params);
  const first = (k: string) => {
    const v = sp[k];
    return Array.isArray(v) ? v[0] : v;
  };

  let session: SessionProbe | null = null;
  let entry: Entry = { kind: "fixtures" };
  let event: Event | null = null;
  let eventFailure: ReadFailure | null = null;

  if (ctx.source === "database") {
    session = await probeSession();
    if (!session.ok) entry = { kind: "failure", failure: { ok: false, kind: session.kind, message: session.message, read: "auth.getClaims" } };
    else if (!session.user) entry = { kind: "failure", failure: { ok: false, kind: "auth", message: "No session", read: "auth.getClaims" } };
    else if (scope.ok) {
      const g = await dbMyGrants(scope.venueId, scope.orgId);
      if (!g.ok) entry = { kind: "failure", failure: g };
      else {
        const principal = derivePrincipal(g.data);
        if (!principal) entry = { kind: "denied" };
        else {
          entry = { kind: "ok", grants: g.data };
          ctx = { ...ctx, role: principal };
          if (params.event && isUuid(params.event)) {
            const r = await dbGetEvent(params.event);
            if (r.ok) event = r.data;
            else eventFailure = r;
          }
        }
      }
    }
  } else if (params.event) {
    event = getEvent(params.event);
  }

  return {
    params,
    sp,
    ctx,
    scope,
    entry,
    event,
    eventFailure,
    session,
    signedInAs: session?.ok ? (session.user?.email ?? session.user?.id ?? null) : null,
    first,
    now: ctx.source === "database" ? new Date() : PREVIEW_NOW,
    timeZone: VENUE.timeZone,
  };
}

import { ORG, PREVIEW_NOW, VENUE } from "@/fixtures/venue";
import { getEvent } from "@/lib/data";
import { DATA_SOURCE } from "@/lib/env";
import { readPreviewContext, type PreviewContext, type SearchParams } from "@/lib/preview";
import { probeSession, type SessionProbe } from "@/lib/auth/session";
import { dbGetEvent } from "@/lib/db/adapters";
import type { ReadFailure } from "@/lib/db/read-result";
import type { Event } from "@/lib/types";

export type PageParams = { org: string; venue: string; event?: string };

/**
 * Spec §4.4 rule 5 — a deep link to another org/venue fails closed. In fixture
 * mode the only scope is the sample org/venue. In database mode the route ids
 * are passed to the reads as untrusted parameters and RLS decides; an
 * unreadable or nonexistent scope yields empty results / null, never a leak.
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

export type EventLookup = { event: Event | null; failure: ReadFailure | null };

export async function readPage(paramsP: Promise<PageParams>, spP: Promise<SearchParams>) {
  const [params, sp] = await Promise.all([paramsP, spP]);
  const ctx: PreviewContext = readPreviewContext(sp);
  const scope = resolveScope(params);
  const first = (k: string) => {
    const v = sp[k];
    return Array.isArray(v) ? v[0] : v;
  };

  // Database mode: who is signed in (verified claims), and the event by id via RLS.
  let session: SessionProbe | null = null;
  let eventLookup: EventLookup = { event: null, failure: null };
  if (ctx.source === "database") {
    session = await probeSession();
    if (params.event && isUuid(params.event) && session.ok && session.user) {
      const r = await dbGetEvent(params.event);
      eventLookup = r.ok ? { event: r.data, failure: null } : { event: null, failure: r };
    }
  } else if (params.event) {
    eventLookup = { event: getEvent(params.event), failure: null };
  }

  return {
    params,
    sp,
    ctx,
    scope,
    event: eventLookup.event,
    eventFailure: eventLookup.failure,
    session,
    signedInAs: session?.ok ? (session.user?.email ?? session.user?.id ?? null) : null,
    first,
    now: ctx.source === "database" ? new Date() : PREVIEW_NOW,
    timeZone: VENUE.timeZone,
  };
}

/** Database-mode gate shared by the pages: config/transport failures and missing sessions as typed failures. */
export function sessionFailure(session: SessionProbe | null, read: string): ReadFailure | null {
  if (!session) return null;
  if (!session.ok) return { ok: false, kind: session.kind, message: session.message, read };
  if (!session.user) return { ok: false, kind: "auth", message: "No session", read };
  return null;
}

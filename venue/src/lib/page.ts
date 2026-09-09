import { ORG, PREVIEW_NOW, VENUE } from "@/fixtures/venue";
import { getEvent } from "@/lib/data";
import { readPreviewContext, type PreviewContext, type SearchParams } from "@/lib/preview";

export type PageParams = { org: string; venue: string; event?: string };

/**
 * Spec §4.4 rule 5 — a deep link to another org/venue fails closed: the
 * standard denial, no partial content. The preview knows one org and one
 * venue; anything else is "not yours".
 */
export function resolveScope(params: PageParams): { ok: true; basePath: string } | { ok: false } {
  if (params.org !== ORG.orgId || params.venue !== VENUE.venueId) return { ok: false };
  return { ok: true, basePath: `/o/${ORG.orgId}/v/${VENUE.venueId}` };
}

export async function readPage(paramsP: Promise<PageParams>, spP: Promise<SearchParams>) {
  const [params, sp] = await Promise.all([paramsP, spP]);
  const ctx: PreviewContext = readPreviewContext(sp);
  const scope = resolveScope(params);
  const event = params.event ? getEvent(params.event) : null;
  const first = (k: string) => {
    const v = sp[k];
    return Array.isArray(v) ? v[0] : v;
  };
  return { params, sp, ctx, scope, event, first, now: PREVIEW_NOW, timeZone: VENUE.timeZone };
}

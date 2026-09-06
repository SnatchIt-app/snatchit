import { NextResponse } from "next/server";
import { getActiveListings } from "@/lib/listings";
import { SITE_URL } from "@/lib/env";
import { captureException } from "@/lib/observability";
import {
  clampLimit,
  inDateWindow,
  parseDateParam,
  parseSortParam,
  sortPublicEvents,
  toPublicEvent,
} from "@/lib/public-events";

/**
 * GET /api/public/events — the public event-discovery feed.
 *
 * Exists for the marketing site's homepage sections. It is a read-only
 * projection of EXACTLY what /browse shows: same getActiveListings call, same
 * predicate, same RLS — so there is one definition of "publicly discoverable"
 * and this route can never drift from the product. Marketing discovers;
 * snatchti.com transacts.
 *
 * Query params:
 *   limit  1–50 (default 12)
 *   from   YYYY-MM-DD inclusive  ─ event_date window, Miami-local wall-clock
 *   to     YYYY-MM-DD inclusive  ─ ("this weekend" = compute Fri–Sun in
 *                                   America/New_York and pass it here)
 *   sort   soonest (default) | ending | most_bids
 *
 * Zero qualifying listings returns { events: [], count: 0 } with HTTP 200 —
 * the marketing site renders its designed placeholders for that. Never fake
 * entries.
 *
 * Caching: CDN-cached 120s with a 10-minute stale-while-revalidate window.
 * Discovery cards do not need bid-level freshness; the product page is the
 * real-time surface. Errors are never cached.
 *
 * The date filter runs in-process rather than widening BrowseFilters: the
 * browsable catalog is capped at 50 rows here and /browse has no date filter
 * to stay consistent with. Revisit only if the catalog outgrows the fetch.
 */
export const dynamic = "force-dynamic";

const CACHE_HEADERS = {
  "Cache-Control": "public, s-maxage=120, stale-while-revalidate=600",
  // Public display data; the marketing site consumes server-side today, but a
  // GET-only public feed loses nothing by being fetchable from a browser.
  "Access-Control-Allow-Origin": "*",
} as const;

export async function GET(request: Request) {
  const params = new URL(request.url).searchParams;
  const limit = clampLimit(params.get("limit"));
  const from = parseDateParam(params.get("from"));
  const to = parseDateParam(params.get("to"));
  const sort = parseSortParam(params.get("sort"));

  try {
    // Over-fetch to the hard cap so a date window filters from the full
    // browsable set, then trim to the requested page size.
    const listings = await getActiveListings({}, 50);
    const events = sortPublicEvents(
      listings
        .filter((l) => inDateWindow(l.event_date, from, to))
        .map((l) => toPublicEvent(l, SITE_URL)),
      sort,
    ).slice(0, limit);

    return NextResponse.json(
      {
        city: "Miami",
        count: events.length,
        events,
        browseUrl: `${SITE_URL}/browse`,
        generatedAt: new Date().toISOString(),
      },
      { headers: CACHE_HEADERS },
    );
  } catch (error) {
    captureException("api/public/events", error);
    // No internals in the body, and no caching of failures — a cached error
    // would blank the marketing homepage for the full CDN window.
    return NextResponse.json(
      { error: "Event feed temporarily unavailable" },
      { status: 500, headers: { "Cache-Control": "no-store" } },
    );
  }
}

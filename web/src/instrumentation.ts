import { captureException } from "@/lib/observability";

/**
 * Server-side error reporting.
 *
 * lib/observability.ts is imported only by "use client" error boundaries, so
 * until now nothing reported a throw from a Server Component, a Route Handler,
 * or — the one that matters — a Server Action. That is where checkout,
 * bidding, listing creation and the transfer state machine all live. Those
 * failures reached the Vercel runtime log and nowhere else, and Next redacts
 * the message from the client, so the user saw a generic boundary and we saw
 * nothing actionable.
 *
 * onRequestError is Next's hook for exactly this and fires for every
 * server-side throw, including ones a client boundary then renders.
 */
export async function onRequestError(
  error: unknown,
  request: { path?: string; method?: string },
  context: { routerKind?: string; routePath?: string; routeType?: string },
) {
  // Awaited: a Vercel invocation can freeze as soon as it responds, so an
  // un-awaited POST here is simply dropped.
  await captureException("server", error, {
    // request.path can carry a query string with user input; routePath is the
    // parameterised form ("/listing/[id]"), which is what we actually want for
    // grouping and carries nothing identifying.
    route: context.routePath ?? request.path ?? "unknown",
    method: request.method ?? "unknown",
    routeType: context.routeType ?? "unknown",
    routerKind: context.routerKind ?? "unknown",
  });
}

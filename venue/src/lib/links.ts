/**
 * Operator deep links (S1).
 *
 * The dashboard's operator event route is src/app/o/[org]/v/[venue]/events/[event]/page.tsx (event setup;
 * its siblings are …/inventory, …/attendees and …/door). The S1 plan guessed /o/{org}/v/{venue}/events/{event}
 * and the app has exactly that shape. tests/operator-link.test.ts asserts against the folder on disk, so a
 * route move fails a test rather than a link.
 *
 * Rules:
 *   - every segment is encodeURIComponent'd, so an id can neither leave its slot nor smuggle a query;
 *   - never a query string: the ?role / ?state preview controls are fixture-mode only and must not ride on
 *     an operator link (lib/preview.ts), and a link with no parameters leaves nothing for a log to keep;
 *   - never a host: the CSP is connect-src 'self', and the same link must work on every deployment.
 */
export function operatorEventPath(orgId: string, venueId: string, eventId: string): string | null {
  const o = segment(orgId);
  const v = segment(venueId);
  const e = segment(eventId);
  if (o === null || v === null || e === null) return null;
  return `/o/${o}/v/${v}/events/${e}`;
}

/** An empty or blank id is refused (null) rather than producing a path with a hole in it. */
function segment(id: unknown): string | null {
  if (typeof id !== "string") return null;
  const t = id.trim();
  return t.length === 0 ? null : encodeURIComponent(t);
}

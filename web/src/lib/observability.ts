/**
 * Error reporting for the web app.
 *
 * Deliberately a hand-rolled Sentry envelope POST rather than @sentry/nextjs:
 * that package pulls in a large client bundle and an OpenTelemetry stack, and
 * wants build-time instrumentation. All this app needs is "a production
 * exception should reach Sentry instead of vanishing", and the edge functions
 * already do exactly this in supabase/functions/_shared/sentry.ts — same
 * approach, same project, one less dependency and no bundle cost.
 *
 * Never throws. An error path that can itself fail is worse than no error path.
 */

const DSN = process.env.NEXT_PUBLIC_SENTRY_DSN ?? process.env.SENTRY_DSN ?? null;
const ENVIRONMENT = process.env.NEXT_PUBLIC_VERCEL_ENV ?? process.env.NODE_ENV ?? "development";
const RELEASE = process.env.NEXT_PUBLIC_VERCEL_GIT_COMMIT_SHA ?? undefined;

/** Parsed once. Returns null for an absent or malformed DSN. */
const parsed = (() => {
  if (!DSN) return null;
  try {
    const u = new URL(DSN);
    const projectId = u.pathname.replace("/", "");
    if (!u.username || !projectId) return null;
    return {
      endpoint: `${u.protocol}//${u.host}/api/${projectId}/envelope/`,
      publicKey: u.username,
    };
  } catch {
    return null;
  }
})();

export const hasErrorReporting = parsed !== null;

/**
 * Turn an Error.stack string into Sentry stack frames.
 *
 * Sending `stacktrace: { frames: [] }` and stuffing the raw stack into `extra`
 * looks harmless but defeats the point of reporting: Sentry cannot symbolicate
 * an empty frame list, source maps never apply, and grouping falls back to
 * type+message — so every distinct minified message becomes its own issue and
 * none of them has a usable stack.
 *
 * Sentry expects frames oldest-first, the reverse of how V8 prints them.
 */
function parseFrames(stack: string | undefined) {
  if (!stack) return [];
  const frames = [];
  // "    at fnName (https://host/path.js:12:34)" and the anonymous
  // "    at https://host/path.js:12:34" form.
  const re = /^\s*at\s+(?:(.+?)\s+\()?(.+?):(\d+):(\d+)\)?\s*$/;
  for (const line of stack.split("\n")) {
    const m = re.exec(line);
    if (!m) continue;
    frames.push({
      function: m[1] ?? "?",
      filename: m[2],
      lineno: Number(m[3]),
      colno: Number(m[4]),
      in_app: !m[2].includes("/node_modules/"),
    });
  }
  return frames.reverse();
}

/**
 * Report an exception. Fire-and-forget by design — callers are usually error
 * boundaries that must render regardless.
 *
 * `context` is free-form and lands in Sentry tags. Do not put PII in it:
 * no emails, phone numbers, or payment identifiers.
 */
export function captureException(
  where: string,
  error: unknown,
  context: Record<string, string> = {},
): void {
  const err = error instanceof Error ? error : new Error(String(error));

  // Always log, so a deploy without a DSN still leaves a trace in the
  // platform logs rather than swallowing the failure entirely.
  console.error(`[${where}]`, err.message, err.stack);

  if (!parsed) return;

  try {
    const eventId = crypto.randomUUID().replace(/-/g, "");
    const sentAt = new Date().toISOString();
    const body =
      JSON.stringify({ event_id: eventId, sent_at: sentAt }) +
      "\n" +
      JSON.stringify({ type: "event" }) +
      "\n" +
      JSON.stringify({
        event_id: eventId,
        timestamp: sentAt,
        platform: "javascript",
        level: "error",
        environment: ENVIRONMENT,
        release: RELEASE,
        logger: where,
        tags: { where, ...context },
        exception: {
          values: [
            { type: err.name, value: err.message, stacktrace: { frames: parseFrames(err.stack) } },
          ],
        },
        // Kept as a raw fallback for the case where parseFrames finds nothing
        // (a non-V8 stack format, or an error with no stack at all).
        extra: { stack: err.stack },
      });

    void fetch(parsed.endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-sentry-envelope",
        "X-Sentry-Auth": `Sentry sentry_version=7, sentry_key=${parsed.publicKey}, sentry_client=snatchit-web/1.0`,
      },
      body,
      // Must not participate in Next's fetch cache, and must not keep a
      // serverless invocation alive waiting on Sentry.
      cache: "no-store",
      keepalive: true,
    }).catch(() => {
      /* reporting must never surface an error of its own */
    });
  } catch {
    /* same */
  }
}

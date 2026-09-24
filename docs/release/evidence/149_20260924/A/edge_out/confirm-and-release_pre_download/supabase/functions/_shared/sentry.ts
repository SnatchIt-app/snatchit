/**
 * supabase/functions/_shared/sentry.ts — minimal Deno-native Sentry capture.
 *
 * Why this and not @sentry/deno or @sentry/browser:
 *   - The official Sentry SDKs for Deno pull large transitive trees and
 *     have rough edges around fetch shims. For our needs — single fire-
 *     and-forget event when an edge function throws — a ~40-line direct
 *     POST to Sentry's `store/` endpoint is enough.
 *   - No background worker, no auto-instrumentation, no source maps
 *     (server-side stacks are bare). The Sentry dashboard still shows the
 *     event with tags, fingerprint, extras, and the raw stack lines.
 *
 * Environment:
 *   SENTRY_SERVER_DSN  — required. Set as Supabase secret. If empty,
 *                        captureException is a no-op apart from
 *                        console.error (which Supabase logs collects).
 *   SENTRY_ENV         — "production" by default. Set per-environment.
 *   SENTRY_RELEASE     — "snatchit-edge" by default.
 *
 * Usage:
 *   import { captureException } from '../_shared/sentry.ts';
 *   try { … } catch (err) {
 *     await captureException('create-payment-intent', err, { listing_id });
 *     return new Response(...500...);
 *   }
 */

const DSN     = Deno.env.get('SENTRY_SERVER_DSN') ?? '';
const ENV     = Deno.env.get('SENTRY_ENV')        ?? 'production';
const RELEASE = Deno.env.get('SENTRY_RELEASE')    ?? 'snatchit-edge';

type ParsedDsn = { publicKey: string; projectId: string; host: string };

const parsed: ParsedDsn | null = (() => {
  if (!DSN) return null;
  try {
    const u = new URL(DSN);
    const projectId = u.pathname.replace(/^\//, '');
    if (!u.username || !projectId) {
      console.warn('[sentry] SENTRY_SERVER_DSN missing public key or project id; captures disabled');
      return null;
    }
    return { publicKey: u.username, projectId, host: u.host };
  } catch (e) {
    console.warn('[sentry] invalid SENTRY_SERVER_DSN, captures disabled:', e);
    return null;
  }
})();

function eventId(): string {
  // Sentry expects 32-char hex without dashes
  return crypto.randomUUID().replace(/-/g, '');
}

/** Convert a JS stack trace into Sentry's frame list (newest-first → oldest-first). */
function framesFromStack(stack: string) {
  return stack
    .split('\n')
    .slice(1)                       // first line is the message; drop it
    .map(line => line.trim())
    .filter(Boolean)
    .reverse()                      // Sentry wants oldest-first (root cause)
    .map((line) => ({
      filename: line,
      function: line.startsWith('at ') ? line.slice(3).split(' ')[0] : '<unknown>',
    }));
}

/**
 * Capture an exception. Always logs to stdout (visible in Supabase logs
 * + the DAY8 admin SQL pack's webhook-events table for webhook handlers).
 * If SENTRY_SERVER_DSN is set, also fires the event to Sentry.
 *
 * Awaiting is optional — if your caller does not await, the function
 * returns immediately and the POST runs in the background. We accept
 * either pattern so handlers can choose between durability and latency.
 */
export async function captureException(
  fn: string,
  err: unknown,
  extra?: Record<string, unknown>,
): Promise<void> {
  const message = err instanceof Error ? err.message : String(err);
  const stack   = err instanceof Error ? err.stack   : undefined;
  const name    = err instanceof Error ? err.name    : 'Error';

  // 1. Always emit a structured console line — Supabase logs collects this.
  //    Single-line JSON so log search works cleanly.
  console.error(JSON.stringify({
    level:   'error',
    fn,
    message,
    extra:   extra ?? {},
  }));

  if (!parsed) return;

  // 2. Fire-and-forget POST to Sentry. Timeouts on the Sentry side don't
  //    block the edge function's response.
  const payload = {
    event_id:    eventId(),
    timestamp:   Date.now() / 1000,
    level:       'error',
    platform:    'javascript',
    logger:      'snatchit-edge',
    server_name: fn,
    environment: ENV,
    release:     RELEASE,
    tags:        { fn },
    exception:   {
      values: [{
        type:        name,
        value:       message,
        stacktrace:  stack ? { frames: framesFromStack(stack) } : undefined,
      }],
    },
    extra: extra ?? {},
  };

  try {
    await fetch(`https://${parsed.host}/api/${parsed.projectId}/store/`, {
      method:  'POST',
      headers: {
        'Content-Type': 'application/json',
        // X-Sentry-Auth identifies the project + sender. Field names per
        // https://develop.sentry.dev/sdk/overview/#authentication
        'X-Sentry-Auth':
          `Sentry sentry_version=7, sentry_key=${parsed.publicKey}, sentry_client=snatchit-edge/1.0`,
      },
      body: JSON.stringify(payload),
    });
  } catch (e) {
    // A failed capture must NEVER cascade into the caller's error path.
    console.warn('[sentry] capture POST failed (non-fatal):', e);
  }
}

/**
 * Lightweight message-level capture (info / warning), e.g. "Stripe API
 * returned 502 transiently but we recovered after retry." Use sparingly —
 * Sentry quota is meaningful, and Supabase logs are the right place for
 * routine events.
 */
export async function captureMessage(
  fn: string,
  message: string,
  level: 'info' | 'warning' = 'warning',
  extra?: Record<string, unknown>,
): Promise<void> {
  console.warn(JSON.stringify({ level, fn, message, extra: extra ?? {} }));
  if (!parsed) return;

  const payload = {
    event_id:    eventId(),
    timestamp:   Date.now() / 1000,
    level,
    platform:    'javascript',
    logger:      'snatchit-edge',
    server_name: fn,
    environment: ENV,
    release:     RELEASE,
    tags:        { fn },
    message:     { formatted: message },
    extra:       extra ?? {},
  };

  try {
    await fetch(`https://${parsed.host}/api/${parsed.projectId}/store/`, {
      method:  'POST',
      headers: {
        'Content-Type':  'application/json',
        'X-Sentry-Auth':
          `Sentry sentry_version=7, sentry_key=${parsed.publicKey}, sentry_client=snatchit-edge/1.0`,
      },
      body: JSON.stringify(payload),
    });
  } catch (e) {
    console.warn('[sentry] message POST failed (non-fatal):', e);
  }
}

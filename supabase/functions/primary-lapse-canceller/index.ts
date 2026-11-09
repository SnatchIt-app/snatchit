/**
 * supabase/functions/primary-lapse-canceller/index.ts
 * ═══════════════════════════════════════════════════════════════════════════
 * A-6 — THE LAPSE CANCELLER for native primary orders (registry 198).
 *
 * Contract:  DESIGN-198-FINAL §4.2 A-6 (steps 1-4), §3.3 (the sweep's report
 *            mode), §5 scenarios 5 / 9 / 11 / 13 / 14 / 19, races R3 / R9.
 * Owner:     O10 (lapses are exposed through the sweep's report mode, no new
 *            object), O11 (webhook, expiry or checkout replay may cancel an order
 *            only after every PaymentIntent is confirmed canceled), O13 (orders whose
 *            payment won after the lapse linger; alert once per order).
 *
 * ── WHY IT EXISTS ──────────────────────────────────────────────────────────
 * 198 binds each order's holds (§3.1 BLOCK B) and makes lapse DERIVED, never
 * written (I7): SQL never cancels an order because its hold lapsed. The 10-
 * minute checkout TTL therefore binds only the HOLD until something cancels the
 * PAYMENT. This job is that something: a lapsed order's PaymentIntent is
 * cancelled at Stripe, so a buyer confirming a sheet after the lapse gets a
 * decline instead of a charge for capacity that may already be someone
 * else's (§5 scenario 5: without this, the payment lands as `refund_required`).
 *
 * ── WHAT ONE RUN DOES ──────────────────────────────────────────────────────
 *   1. venue.sweep_expired_inventory_holds(p_limit => 0) — REPORT MODE (§3.3):
 *      runs no candidates, writes nothing, and returns `lapsed_orders[]`
 *      (pending orders with a bound hold that is released, expired, or active
 *      past its expiry; newest lapse first; at most 100). Any other p_limit
 *      returns `lapsed_orders: null`; the pre-198 body returns no such key, and
 *      that is refused (503 + activation-blocker alert), never read as "none".
 *   2-3. Per order, `cancelLapsedOrderPaymentIntents` (primary-checkout/
 *      order-pis.ts): recoverReplayQuote's own search (step 2 says to reuse
 *      it, and it is IMPORTED, not copied), the metadata order_id + session_id
 *      check, then the per-status action — requires_* → cancel with
 *      Idempotency-Key pi_lapse_cancel_{pi}; processing → skip; succeeded →
 *      nothing, alert once (below); canceled while pending → cancel_pending_
 *      order with buildCancelCommandKey(order, pi) — only when no sibling is
 *      processing, succeeded or requires_capture; none → A-4's default,
 *      leave it. requires_capture (an anomaly: this rail is automatic-
 *      capture) is cancelled with the same key to release the buyer's
 *      authorization unless a sibling is succeeded or processing, then
 *      alerted, once per order (D's C2; below).
 *      THREE DEVIATIONS from "steps 2-3 exactly", A's and sent to D for
 *      ratification, each with its reason in that function's header:
 *        D1 candidate statuses widened from pending|failed to pending|
 *           processing|succeeded|failed — the webhook marks the row succeeded
 *           BEFORE finalize, so the literal filter loses a paid lapsed order
 *           (O13 would never alert);
 *        D2 one ORDER-level precedence decides for all of an order's PIs —
 *           per-PI rules applied independently undo each other;
 *        D3 no sibling of a succeeded or processing PI is ever cancelled — its
 *           payment_intent.canceled would cancel the order the money is
 *           landing on (§10 risk 13).
 *   4. `buyer_id` never leaves this function (§4.2 A-6 step 4): it is used for
 *      the candidate read and is in no log line and no response. `lapsed_at`
 *      is a timezone-offset string; it is parsed, never compared as text.
 *
 * One order's failure never blocks the batch (the enforce-transfer-expiry /
 * refund-execute rule). Every Stripe write carries a deterministic key and
 * every DB write is idempotent by command key, so an overlapping or repeated
 * run is harmless.
 *
 * ── "ALERT lapsed_order_paid ONCE PER ORDER" (§4.2 A-6 step 3, O13) ────────
 * Such an order stays pending and stays in the report on EVERY run (O13), and
 * an edge isolate keeps no memory between runs, so "once" needs a durable
 * marker. 198 adds no object (O10), so the marker is a review row in the
 * existing ops queue `public.webhook_retries` (069) — the same table and the
 * same "record ONCE, WHERE NOT EXISTS" idiom settle_verified_payment uses
 * (20260906110000:159-166), with `payment_id` NULL and an `rpc_name` no
 * automated consumer selects on (the refund sweep reads only
 * 'settle_verified_payment', 20260923000000:62-70; the deletion blockers join
 * on payment_id, 20260906120000:962-966), exactly as stripe-webhook's
 * NATIVE_REVIEW_RPC_NAME rows do (stripe-webhook/index.ts:327-335). It also
 * leaves a record an operator can resolve: an alert alone can be lost. If the
 * marker cannot be read the alert fires anyway — never silent.
 *
 * THE ANOMALY ALERT IS ONCE PER ORDER TOO (reviewer E, round-3 review). An
 * anomaly order also stays pending and in the report on every run, and a
 * requires_capture cancel Stripe refused is REPLAYED, refusal and all, for the
 * same Idempotency-Key (pi_lapse_cancel_{pi}) for ~24h, so an unmarked alert
 * re-fires every 1-2 minutes: a pager loop from one anomaly. It takes the same
 * marker idiom (`alertOncePerOrder`, shared) under its own error_message
 * prefix, `lapsed_order_anomaly:` beside `lapsed_order_paid:`, so the two never
 * suppress each other for one order. The per-run log line and the response
 * still report `anomaly` on every run; only the alert is once. A later,
 * different anomaly detail for the same order (e.g. the authorization released
 * once the key expires) is therefore NOT re-alerted; the unresolved review row
 * is the standing record. The checkout path's anomaly alert is deliberately
 * NOT marked (primary-checkout/index.ts, A-2): it fires only on a buyer's own
 * same-key replay, not on a schedule.
 *
 * ── HOW IT IS INVOKED (deploy-time; NOT scheduled by this change) ──────────
 *   POST, empty JSON body, every 1-2 minutes (§4.2 A-6), from pg_cron + pg_net
 *   in the 032 pattern (032_pre_testflight_blocker_fixes.sql:97-115):
 *     net.http_post(url := '<project>/functions/v1/primary-lapse-canceller',
 *       headers := {Authorization: 'Bearer ' || <INTERNAL_CRON_SECRET or the
 *       service_role key, read from Vault at fire time>, Content-Type: json},
 *       body := '{}')
 *   Deploy with `--no-verify-jwt`: the bearer is compared HERE (below), and
 *   INTERNAL_CRON_SECRET is not a JWT the gateway could verify — the same
 *   posture as refund-execute (PRIMARY_TICKETING_PRODUCTION_ACTIVATION_RUNBOOK
 *   S-7). Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, STRIPE_SECRET_KEY,
 *   INTERNAL_CRON_SECRET (optional; the service key also authenticates).
 *   The cron row itself is a deploy-time item for the owner, after 198 and
 *   before the flag is turned on (§4.2 A-8).
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { captureException } from '../_shared/sentry.ts';
import { stripeFetchRaw } from '../_shared/stripe.ts';
import { cancelLapsedOrderPaymentIntents } from '../primary-checkout/order-pis.ts';

const SUPABASE_URL              = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const INTERNAL_CRON_SECRET      = Deno.env.get('INTERNAL_CRON_SECRET') ?? '';

const FN = 'primary-lapse-canceller';

/** `public.webhook_retries.rpc_name` for the once-per-order markers (see header). */
const REVIEW_RPC_NAME = FN;

// Any-version uuid: buyer ids are auth.users ids, order/session ids are ours.
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

// Copied from refund-execute/index.ts:145-150 (the house constant-time compare).
function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// One structured line per order. NEVER buyer_id (§4.2 A-6 step 4); order and
// PI ids are opaque handles and safe (primary-checkout's logging rule).
function logLine(detail: Record<string, unknown>) {
  console.log(JSON.stringify({ tag: 'primary-lapse-canceller', ...detail }));
}

/** service_role on `venue`: the sweep (ACL {postgres, service_role}, §3.3) and cancel_pending_order (PFA-15). */
function venueService() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
    db:   { schema: 'venue' },
  });
}

/** service_role on `public`: the payments candidate read and the review marker. */
function publicService() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

/**
 * `public.webhook_retries.error_message` prefixes of the once-per-order markers
 * (see the header). ONE PER ALERT, so a paid alert and an anomaly alert for the
 * same order never suppress each other: the read is an exact match on the
 * whole `<prefix><order_id>` string.
 */
const PAID_MARKER_PREFIX    = 'lapsed_order_paid:';
const ANOMALY_MARKER_PREFIX = 'lapsed_order_anomaly:';

/**
 * Send `alert` + `ctx` to Sentry unless `marker` says it already was sent for
 * this order (see the header), then leave the marker. Returns whether it
 * alerted. The paid and the anomaly alert both go through here, so the two
 * cannot drift apart.
 */
async function alertOncePerOrder(
  pub: ReturnType<typeof publicService>,
  orderId: string,
  marker: string,
  alert: Error,
  ctx: Record<string, unknown>,
): Promise<boolean> {
  try {
    const { data, error } = await pub
      .from('webhook_retries')
      .select('id')
      .eq('rpc_name', REVIEW_RPC_NAME)
      .eq('error_message', marker)
      .limit(1);
    if (!error && Array.isArray(data) && data.length > 0) return false;
    if (error) logLine({ order_id: orderId, marker_read_failed: error.message });
  } catch (err) {
    // Cannot prove it was alerted before → alert (never silent).
    logLine({ order_id: orderId, marker_read_failed: err instanceof Error ? err.message : String(err) });
  }
  await captureException(FN, alert, ctx);
  try {
    const { error } = await pub.from('webhook_retries').insert({
      payment_id:    null,
      listing_id:    null,
      rpc_name:      REVIEW_RPC_NAME,
      error_message: marker,
      resolved:      false,
    });
    // Unwritten marker ⇒ the next run alerts again: loud, never silent.
    if (error) logLine({ order_id: orderId, marker_write_failed: error.message });
  } catch (err) {
    logLine({ order_id: orderId, marker_write_failed: err instanceof Error ? err.message : String(err) });
  }
  return true;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok');
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  // ── Auth — refund-execute's sweep auth, copied (refund-execute/index.ts:
  // 630-633): the internal cron secret, or the runtime service-role key, each
  // only when non-empty, compared in constant time. Nothing else runs first.
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice('Bearer '.length) : '';
  const cronOk = INTERNAL_CRON_SECRET.length > 0 && constantTimeEqual(token, INTERNAL_CRON_SECRET);
  const svcOk = SUPABASE_SERVICE_ROLE_KEY.length > 0 && constantTimeEqual(token, SUPABASE_SERVICE_ROLE_KEY);
  if (!cronOk && !svcOk) return json({ error: 'Unauthorized' }, 401);

  try {
    // ── 1. The lapse report (§3.3 report mode, O10) ───────────────────────
    const { data: report, error: sweepErr } = await venueService().rpc('sweep_expired_inventory_holds', { p_limit: 0 });
    if (sweepErr) {
      await captureException(FN, new Error(`sweep_expired_inventory_holds(p_limit=>0) failed: ${sweepErr.message}`), {
        code: sweepErr.code ?? null,
      });
      return json({ error: 'sweep_report_failed' }, 500);
    }
    const lapsedOrders = (report as { lapsed_orders?: unknown } | null)?.lapsed_orders;
    if (!Array.isArray(lapsedOrders)) {
      // The pre-198 sweep (081:852-893) returns four keys and no report: it is
      // not "nothing lapsed", it is "this job cannot see". Fail closed, loudly.
      await captureException(FN, new Error('sweep report mode returned no lapsed_orders — registry 198 is not deployed (DESIGN-198-FINAL §3.3, §4.2 A-8)'), {
        activation_blocker: true,
      });
      return json({ error: 'lapse_report_unavailable' }, 503);
    }

    // ── 2-3. Each lapsed order, newest lapse first ────────────────────────
    const pub = publicService();
    const counts: Record<string, number> = {};
    const results: Array<{ order_id: string | null; outcome: string }> = [];
    const errors: Array<{ order_id: string; detail: string }> = [];

    for (const raw of lapsedOrders) {
      const e = (raw ?? {}) as Record<string, unknown>;
      const orderId = typeof e.order_id === 'string' && UUID_RE.test(e.order_id) ? e.order_id : null;
      const buyerId = typeof e.buyer_id === 'string' && UUID_RE.test(e.buyer_id) ? e.buyer_id : null;
      const sessionId = typeof e.event_session_id === 'string' && UUID_RE.test(e.event_session_id) ? e.event_session_id : null;
      const faceMinor = typeof e.total_minor === 'number' && Number.isSafeInteger(e.total_minor) && e.total_minor >= 0
        ? e.total_minor : null;

      if (orderId === null || buyerId === null || sessionId === null || faceMinor === null) {
        // Not a shape §3.3 produces. Nothing can be confirmed, so nothing is acted on.
        counts.anomaly = (counts.anomaly ?? 0) + 1;
        results.push({ order_id: orderId, outcome: 'anomaly' });
        await captureException(FN, new Error('malformed lapsed_orders entry'), { order_id: orderId });
        continue;
      }

      // §4.2 A-6 step 4: parsed, never compared as text.
      const lapsedMs = typeof e.lapsed_at === 'string' ? Date.parse(e.lapsed_at) : NaN;
      const lapsedForS = Number.isFinite(lapsedMs) ? Math.round((Date.now() - lapsedMs) / 1000) : null;

      let outcome: Awaited<ReturnType<typeof cancelLapsedOrderPaymentIntents>>;
      try {
        outcome = await cancelLapsedOrderPaymentIntents(
          { service: pub, venueService, stripeFetchRaw },
          { orderId, buyerId, faceMinor, sessionId },
        );
      } catch (err) {
        outcome = { kind: 'error', detail: err instanceof Error ? err.message : String(err) };
      }

      counts[outcome.kind] = (counts[outcome.kind] ?? 0) + 1;
      results.push({ order_id: orderId, outcome: outcome.kind });
      logLine({
        order_id: orderId, outcome: outcome.kind, lapse: typeof e.lapse === 'string' ? e.lapse : null,
        lapsed_for_s: lapsedForS,
        pi_ids: 'piIds' in outcome ? outcome.piIds : 'piId' in outcome ? [outcome.piId] : [],
        detail: 'detail' in outcome ? outcome.detail : null,
      });

      if (outcome.kind === 'paid') {
        await alertOncePerOrder(pub, orderId, `${PAID_MARKER_PREFIX}${orderId}`, new Error('lapsed_order_paid'), {
          order_id: orderId, pi_ids: outcome.piIds,
          note: 'a lapsed order\'s PaymentIntent succeeded; finalize decides (ticket, or refund_required). DESIGN-198-FINAL §4.2 A-6, O13.',
        });
      } else if (outcome.kind === 'anomaly') {
        // A state this rail never produces (a PI naming another session, a
        // status no automatic-capture PI reaches). Nothing was touched, except
        // a requires_capture PI's cancel (C2): `authorization` says whether
        // the buyer's hold was released or may still be held. ONCE per order,
        // like the paid alert (see the header): it recurs on every run.
        await alertOncePerOrder(pub, orderId, `${ANOMALY_MARKER_PREFIX}${orderId}`, new Error(`lapsed order anomaly: ${outcome.detail}`), {
          order_id: orderId, pi_id: outcome.piId,
          ...(outcome.authorization ? { authorization: outcome.authorization } : {}),
        });
      } else if (outcome.kind === 'error') {
        errors.push({ order_id: orderId, detail: outcome.detail });
      }
    }

    // Transient per-order failures retry next run by themselves; one alert per
    // run says they are happening, rather than one per order per run.
    if (errors.length > 0) {
      await captureException(FN, new Error(`lapse canceller: ${errors.length} order(s) not settled this run`), {
        errors: errors.slice(0, 10),
      });
    }

    return json({ status: 'ok', lapsed: lapsedOrders.length, counts, results }, 200);
  } catch (err) {
    await captureException(FN, err);
    return json({ error: 'Internal server error' }, 500);
  }
});

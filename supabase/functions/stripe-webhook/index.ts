// READY TO DEPLOY
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { captureException } from '../_shared/sentry.ts';
import { stripeFetchRaw } from '../_shared/stripe.ts';
// Pure decision logic for the NATIVE PRIMARY rail and the account.updated
// organization arm. Import-free by construction so vitest can exercise every
// branch below without loading a single https specifier — see native.ts's
// header and tests/stripe-webhook-native.test.ts.
import {
  type Decision,
  type PaymentRow,
  buildCancelCommandKey,
  buildFinalizeCommandKey,
  buildOrgSyncCommandKey,
  classifyCancelError,
  classifyFinalizeError,
  classifyOrgSyncError,
  decideAccountUpdatedOutcome,
  decideClaimOutcome,
  deriveTransfersActive,
  dispositionForRoute,
  eventAgeSeconds,
  extractInstrumentFingerprint,
  interpretPaymentClaim,
  isConnectAccountRef,
  isTerminalPaymentIntent,
  latestChargeId,
  observedAtIso,
  type OrgArmOutcome,
  readNativeMetadata,
  resolveRail,
  selectAccountPlane,
  verifyNativePaymentRow,
  CANCEL_REASON_PAYMENT_FAILED,
  type ConnectAccountLike,
} from './native.ts';
// Pure decision logic for the NATIVE arm of `charge.dispute.*` and the native
// routing of `transfer.reversed` (KH §4.5 / §4.6 decision tables). Import-free
// by construction — see native-dispute.ts's header and
// tests/stripe-webhook-dispute.test.ts.
import {
  type DisputeEventKind,
  type DisputeLike,
  type DisputePaymentRow,
  type MarkDisputeResult,
  type RecordDisputeResult,
  type RecordPayoutReversalResult,
  type ReversalFact,
  type TransferLike,
  DISPUTE_PAYMENT_COLUMNS,
  aggregateDecisions,
  buildDisputeCommandKey,
  classifyDisputeError,
  classifyReversalError,
  disputeMarkArgs,
  disputeRecordArgs,
  disputeStatusKnown,
  interpretMarkResult,
  interpretRecordResult,
  interpretReversalResult,
  isDisputeNotFound,
  mergeReversals,
  planDisputeVerb,
  planReversalRecording,
  readInlineReversals,
  resolveDisputeRail,
  resolveTransferRail,
} from './native-dispute.ts';

// ── 150: refund lifecycle ────────────────────────────────────────────────────
// A Stripe refund has its own status (pending, requires_action, succeeded,
// failed, canceled) that can change in any direction for ~30 days; a card
// refund can report succeeded and later fail (docs.stripe.com/refunds,
// /testing). Every refund fact is written through record_refund_state
// (migration 20260925000000) with the refund's OWN status — the SQL writer
// counts a refund toward the one-way payments record only while it is not
// failed/canceled. Nothing here calls record_payment_refund for a refund.
interface StripeRefund {
  id?: string;
  status?: string | null;
  amount?: number | null;
  payment_intent?: string | null;
  failure_reason?: string | null;
  metadata?: Record<string, string> | null;
}
const REFUND_STATUSES = new Set(['pending', 'requires_action', 'succeeded', 'failed', 'canceled']);
/** Our own refunds carry metadata.source = 'enforce-transfer-expiry…' (reason tells expiry from unfulfillable). */
function refundSource(r: StripeRefund): 'expiry' | 'unfulfillable' | 'dashboard' {
  if (!(r.metadata?.source ?? '').startsWith('enforce-transfer-expiry')) return 'dashboard';
  return r.metadata?.reason === 'unfulfillable' ? 'unfulfillable' : 'expiry';
}
/** The latest refund object from Stripe (events arrive out of order: docs.stripe.com/webhooks). */
async function fetchRefund(id: string): Promise<{ ok: true; refund: StripeRefund } | { ok: false; error: string }> {
  const probe = await stripeFetchRaw(`/refunds/${id}`);
  if (!probe.ok) {
    return { ok: false, error: (probe.data as { error?: { message?: string } })?.error?.message ?? `HTTP ${probe.status}` };
  }
  return { ok: true, refund: probe.data as StripeRefund };
}

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY')!;
const STRIPE_WEBHOOK_SECRET = Deno.env.get('STRIPE_WEBHOOK_SECRET')!;
// A Connect-type endpoint ("events on connected accounts") is the ONLY place
// Stripe delivers an organization account's account.updated, and every endpoint
// has its OWN signing secret. Both endpoints point at this one function, so a
// delivery is accepted if it verifies under either secret. Optional: unset (or
// empty) keeps the platform-only behaviour exactly as before.
const STRIPE_CONNECT_WEBHOOK_SECRET = Deno.env.get('STRIPE_CONNECT_WEBHOOK_SECRET') ?? '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

// ── CORS origin whitelist ────────────────────────────────────────────────────
const ALLOWED_ORIGINS = [
  'https://snatchitapp.com',
  'https://www.snatchitapp.com',
];

function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('origin') ?? '';
  const allowedOrigin = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    'Access-Control-Allow-Origin': allowedOrigin,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, stripe-signature',
  };
}

function getSecurityHeaders(): Record<string, string> {
  return {
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
    'X-DNS-Prefetch-Control': 'off',
    'X-Download-Options': 'noopen',
    'X-Permitted-Cross-Domain-Policies': 'none',
    'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload',
  };
}

function getResponseHeaders(req: Request): Record<string, string> {
  return {
    ...getCorsHeaders(req),
    ...getSecurityHeaders(),
  };
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  const encoder = new TextEncoder();
  const aBytes = encoder.encode(a);
  const bBytes = encoder.encode(b);
  let result = 0;
  for (let i = 0; i < aBytes.length; i++) {
    result |= aBytes[i] ^ bBytes[i];
  }
  return result === 0;
}

// Replay-attack window for Stripe webhooks. Matches the default tolerance
// used by Stripe's official server-side libraries. If `t` in the signature
// header is older than this many seconds vs. our wall clock, we reject.
const STRIPE_WEBHOOK_TOLERANCE_SECONDS = 300;

/**
 * How long one delivery may hold an event before another may steal the lease
 * (migration 064). Only matters when a handler dies without reaching either
 * complete or fail — a torn-down isolate. Comfortably above the observed
 * worst-case handler time of ~5.6s, and low enough that a stuck event
 * self-heals on Stripe's retry schedule rather than needing an operator.
 */
const LEASE_SECONDS = 300;

async function verifyStripeSignature(rawBody: string, sigHeader: string): Promise<boolean> {
  // Collect EVERY v1 entry: during a signing-secret rotation Stripe signs
  // with both old and new secrets and sends multiple v1= values. Keeping
  // only one (the old reduce-into-a-map bug) rejected valid deliveries for
  // the whole rotation window. Accept if ANY v1 matches.
  const parts: Record<string, string> = {};
  const v1Signatures: string[] = [];
  for (const part of sigHeader.split(',')) {
    const [key, val] = part.split('=');
    if (key === 'v1' && val) v1Signatures.push(val);
    else if (key && val) parts[key] = val;
  }

  const timestamp = parts['t'];
  if (!timestamp || v1Signatures.length === 0) return false;

  // ── Replay protection ──────────────────────────────────────────────────
  // Stripe sends `t` as a Unix epoch in seconds. Reject anything older than
  // our tolerance, OR anything skewed too far into the future (clock issues
  // / forged timestamps).
  const tsSeconds = parseInt(timestamp, 10);
  if (!Number.isFinite(tsSeconds)) return false;
  const nowSeconds = Math.floor(Date.now() / 1000);
  const delta      = Math.abs(nowSeconds - tsSeconds);
  if (delta > STRIPE_WEBHOOK_TOLERANCE_SECONDS) {
    console.warn('Webhook: signature timestamp outside tolerance', {
      delta_seconds: delta,
      tolerance:     STRIPE_WEBHOOK_TOLERANCE_SECONDS,
    });
    return false;
  }

  const payload = `${timestamp}.${rawBody}`;
  const encoder = new TextEncoder();
  const secrets = [STRIPE_WEBHOOK_SECRET, STRIPE_CONNECT_WEBHOOK_SECRET].filter((s) => s.length > 0);
  for (const secret of secrets) {
    const key = await crypto.subtle.importKey(
      'raw',
      encoder.encode(secret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign']
    );
    const sig = await crypto.subtle.sign('HMAC', key, encoder.encode(payload));
    const expected = Array.from(new Uint8Array(sig))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
    if (v1Signatures.some((candidate) => timingSafeEqual(expected, candidate))) return true;
  }
  return false;
}

/**
 * The columns the native branch reads off `public.payments`. Kept in one place
 * because the claim UPDATE and the follow-up SELECT must project identically —
 * `interpretPaymentClaim` compares the two.
 */
const NATIVE_PAYMENT_COLUMNS = 'id, status, mode, listing_id, seller_id, buyer_id, total';

/** How long the fingerprint read may take before issuance stops waiting for it. */
const CHARGE_READ_TIMEOUT_MS = 4000;

/**
 * ONE authenticated Stripe GET, used for exactly one thing: recovering the
 * promoter self-deal detector's `instrument_fingerprint` from the succeeded
 * PaymentIntent's `latest_charge` (spec §4, RPC §6.3). The pinned post-2022 API
 * version sends only the charge ID in the event payload.
 *
 * READ-ONLY BY CONSTRUCTION — `GET` only, no body, no idempotency key, and it
 * moves no money. Its result is advisory: per RPC §17.14 no attribution input
 * may delay or fail issuance, so every failure path here returns `null` and
 * finalize proceeds. The fingerprint is NEVER logged (PROMO §1.8).
 */
async function readInstrumentFingerprint(paymentIntent: unknown): Promise<string | null> {
  try {
    // If the endpoint is configured with expansion, or the payload already
    // carries the object, no network call happens at all.
    const inline = (paymentIntent as { latest_charge?: unknown })?.latest_charge;
    if (inline && typeof inline === 'object') return extractInstrumentFingerprint(inline);

    const chargeId = latestChargeId(paymentIntent as { latest_charge?: unknown });
    if (!chargeId || !STRIPE_SECRET_KEY) return null;

    const res = await fetch(`https://api.stripe.com/v1/charges/${encodeURIComponent(chargeId)}`, {
      method: 'GET',
      headers: { Authorization: `Bearer ${STRIPE_SECRET_KEY}` },
      signal: AbortSignal.timeout(CHARGE_READ_TIMEOUT_MS),
    });
    if (!res.ok) {
      console.warn('Webhook: charge read for fingerprint failed (non-fatal)', { status: res.status });
      return null;
    }
    return extractInstrumentFingerprint(await res.json());
  } catch (err) {
    console.warn('Webhook: charge read for fingerprint threw (non-fatal)', {
      error: err instanceof Error ? err.message : String(err),
    });
    return null;
  }
}

/** How long one page of a transfer's reversal list may take. */
const REVERSAL_READ_TIMEOUT_MS = 4000;
/** Hard cap on pages: 100 reversals per page × 10 is far beyond any real transfer. */
const REVERSAL_READ_MAX_PAGES = 10;

/**
 * READ-ONLY BY CONSTRUCTION — the `readInstrumentFingerprint` pattern: `GET`
 * only, no body, no idempotency key, a hard timeout, and it moves no money.
 *
 * `transfer.reversed` carries `reversals.data[]` inline, but the list is
 * paginated (`has_more`). A Σ over a SHORT list would under-record what came
 * back, and `record_payout_reversal`'s facts are the only ledger of it
 * (DESIGN §1.3 / §2.2) — so when `has_more` is true the remaining pages are
 * read here before any verb is called. Unlike the fingerprint read this one
 * is NOT advisory: a failed page makes the delivery RETRY (the caller maps
 * `ok:false` to `ack:false`), because a redelivery genuinely can succeed.
 */
async function readTransferReversalsAfter(
  transferId: string,
  startingAfter: string | null,
): Promise<{ ok: true; reversals: ReversalFact[] } | { ok: false; detail: string }> {
  try {
    if (!STRIPE_SECRET_KEY) return { ok: false, detail: 'no STRIPE_SECRET_KEY' };
    const collected: ReversalFact[] = [];
    let cursor = startingAfter;
    for (let page = 0; page < REVERSAL_READ_MAX_PAGES; page++) {
      const qs = new URLSearchParams({ limit: '100' });
      if (cursor) qs.set('starting_after', cursor);
      const res = await fetch(
        `https://api.stripe.com/v1/transfers/${encodeURIComponent(transferId)}/reversals?${qs.toString()}`,
        {
          method: 'GET',
          headers: { Authorization: `Bearer ${STRIPE_SECRET_KEY}` },
          signal: AbortSignal.timeout(REVERSAL_READ_TIMEOUT_MS),
        },
      );
      if (!res.ok) return { ok: false, detail: `HTTP ${res.status}` };
      const body = (await res.json()) as { data?: unknown; has_more?: unknown };
      const parsed = readInlineReversals({ reversals: { data: body.data, has_more: body.has_more } });
      if (!parsed.ok) return { ok: false, detail: parsed.detail };
      collected.push(...parsed.reversals);
      if (!parsed.hasMore) return { ok: true, reversals: collected };
      const last = parsed.reversals[parsed.reversals.length - 1];
      if (!last) return { ok: false, detail: 'has_more with an empty page' };
      cursor = last.id;
    }
    return { ok: false, detail: `more than ${REVERSAL_READ_MAX_PAGES} pages of reversals` };
  } catch (err) {
    return { ok: false, detail: err instanceof Error ? err.message : String(err) };
  }
}

/**
 * `public.webhook_retries.rpc_name` for the durable twin of an ACK + alert
 * native decision (see `recordNativeReview` inside the handler). Distinct from
 * every name an automated consumer selects on: the refund sweep reads only
 * `rpc_name = 'settle_verified_payment'` rows whose message starts
 * 'unfulfillable' (get_unsettled_payments), so a row under this name is a
 * human's to read and never a machine's to act on.
 */
const NATIVE_REVIEW_RPC_NAME = 'stripe-webhook:native';

async function sendPush(userId: string, title: string, body: string, data?: Record<string, string>) {
  try {
    await fetch(`${SUPABASE_URL}/functions/v1/send-push`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ user_id: userId, title, body, data }),
    });
  } catch (err) {
    console.error('Webhook: sendPush failed:', err);
  }
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { ...getResponseHeaders(req) } });
  }

  // Hoisted so the catch can release the lease for whatever event we were
  // working on. Stays null if we threw before parsing, in which case there is
  // no claim to release.
  let parsedEventId: string | null = null;

  try {
    const rawBody = await req.text();
    const sigHeader = req.headers.get('stripe-signature');

    if (!sigHeader || !(await verifyStripeSignature(rawBody, sigHeader))) {
      return new Response(
        JSON.stringify({ error: 'Invalid signature' }),
        { status: 400, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
      );
    }

    const event = JSON.parse(rawBody);
    parsedEventId = typeof event?.id === 'string' ? event.id : null;
    const paymentIntent = event.data.object;
    const piId = paymentIntent.id;
    const metadata = paymentIntent.metadata ?? {};

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // ─── Idempotency gate: claim/complete/fail lease (migration 064) ─────
    //
    // The old gate inserted a row here and treated "row exists" as "already
    // done". It never looked at `processed`. So an event that claimed the
    // payment row and then threw would return 500, Stripe would retry, the
    // retry hit 23505, and we answered 200 having done nothing — leaving the
    // buyer charged with no transfer, no mark_listing_sold, and the listing
    // still reserved, permanently and with no retry path.
    //
    // Now a claim is a lease. Only 'claimed' does work:
    //   already_processed -> 200, genuinely nothing to do
    //   in_flight         -> 409, another delivery holds a live lease, so let
    //                        Stripe retry rather than double-process
    // The claim is one atomic statement, so concurrent deliveries of the same
    // event cannot both win it.
    {
      const { data: claim, error: claimErr } = await supabase
        .rpc('claim_stripe_webhook_event', {
          p_event_id: event.id,
          p_event_type: event.type,
          p_lease_seconds: LEASE_SECONDS,
        });

      if (claimErr) {
        // Deliberately fail CLOSED, unlike the old gate which logged and
        // carried on without a dedup row — that let two concurrent deliveries
        // run every side effect during a database hiccup. A 500 costs us a
        // Stripe retry; failing open costs a double charge or double transfer.
        console.error('Webhook: claim failed, refusing to process:', {
          event_id: event.id, event_type: event.type, error: claimErr,
        });
        await captureException('stripe-webhook', claimErr);
        return new Response(
          JSON.stringify({ error: 'Could not claim event' }),
          { status: 500, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
        );
      }

      if (claim === 'already_processed') {
        console.log('Webhook: event already processed, skipping', {
          event_id: event.id, event_type: event.type,
        });
        return new Response(
          JSON.stringify({ received: true, duplicate: true }),
          { status: 200, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
        );
      }

      if (claim === 'in_flight') {
        console.warn('Webhook: event already in flight, asking Stripe to retry', {
          event_id: event.id, event_type: event.type,
        });
        return new Response(
          JSON.stringify({ error: 'Event already in flight' }),
          { status: 409, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
        );
      }
    }

    // Terminal success for this event. After this the event can never be
    // reprocessed, so it must only be called once the authoritative work is
    // genuinely done — including the benign no-op paths, which ARE complete.
    async function markProcessed(opts: { error?: string } = {}) {
      if (opts.error) {
        // Records the error and RELEASES the lease, so the next Stripe
        // delivery re-claims and reprocesses instead of being swallowed.
        const { error: failErr } = await supabase
          .rpc('fail_stripe_webhook_event', { p_event_id: event.id, p_error: opts.error });
        if (failErr) console.warn('Webhook: fail_stripe_webhook_event failed:', failErr.message);
        return;
      }
      const { error: doneErr } = await supabase
        .rpc('complete_stripe_webhook_event', { p_event_id: event.id });
      if (doneErr) console.warn('Webhook: complete_stripe_webhook_event failed:', doneErr.message);
    }

    /**
     * Ends the request. `ok: false` means the authoritative work did NOT
     * finish, so we answer non-2xx and Stripe retries — the event stays
     * reclaimable. Previously every one of these paths returned 200.
     */
    async function finish(
      ok: boolean,
      body: Record<string, unknown>,
      error?: string,
    ): Promise<Response> {
      await markProcessed(ok ? {} : { error: error ?? 'incomplete' });
      return new Response(
        JSON.stringify(ok ? { received: true, ...body } : { error: error ?? 'incomplete', ...body }),
        {
          status: ok ? 200 : 500,
          headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) },
        },
      );
    }

    /**
     * The durable twin of an ACK + alert native decision: one row in the ops
     * review queue `public.webhook_retries` (069), written BEFORE the event is
     * completed. An alert alone can be lost (no Sentry DSN, rate limit, nobody
     * watching); a row cannot. Restore, 2026-10-27: a native event that settles
     * nothing is never acknowledged without one.
     *
     * `payment_id` is deliberately NULL and the identifiers ride in
     * `error_message`: a linked row would start counting a kernel-rail payment
     * in the external-rail-only deletion blockers ('unresolved_review',
     * 20260906120000), which review round 2 (MAJOR-1) scoped away from it. The
     * `rpc_name` keeps the row out of the refund sweep (see
     * NATIVE_REVIEW_RPC_NAME). Returns the write's error message, or null.
     */
    async function recordNativeReview(reason: string, body: Record<string, unknown>): Promise<string | null> {
      const ref = ['order_id', 'pi_id', 'dispute_id', 'stripe_transfer_ref', 'account_id', 'payment_id']
        .map((k) => body[k])
        .find((v): v is string => typeof v === 'string' && v.length > 0) ?? 'none';
      const { error: reviewErr } = await supabase.from('webhook_retries').insert({
        payment_id:    null,
        listing_id:    null,
        rpc_name:      NATIVE_REVIEW_RPC_NAME,
        error_message: `${reason}:${event.type}:${event.id}:${ref}`,
        resolved:      false,
      });
      if (reviewErr) {
        console.error('Webhook: native review row could not be written', { reason, event_id: event.id, error: reviewErr.message });
        return reviewErr.message;
      }
      return null;
    }

    /**
     * Ends the request from a `Decision` produced by native.ts / native-dispute.ts.
     *
     * `ack:true`  → 200 + complete (terminal — Stripe never delivers it again)
     * `ack:false` → 500 + fail    (lease released — Stripe retries)
     * `alert:true` → Sentry, independently of which of the two it is.
     *
     * The two bits are orthogonal on purpose: the branch's most important
     * outcomes are "ACK loudly" (an event no redelivery can fix) and "retry
     * quietly" (a race we expect to win next time), and a single ok/error flag
     * cannot express either.
     *
     * "ACK loudly" also writes the review row (recordNativeReview). If that row
     * cannot be written the event is NOT acknowledged: 500 + fail, so Stripe
     * redelivers and the next delivery writes it.
     */
    async function finishDecision(
      decision: Decision,
      body: Record<string, unknown>,
      cause?: unknown,
    ): Promise<Response> {
      if (decision.alert) {
        await captureException(
          `stripe-webhook:${decision.reason}`,
          cause instanceof Error ? cause : new Error(decision.reason),
          { event_id: event.id, event_type: event.type, ...body },
        );
      }
      if (decision.ack && decision.alert) {
        const reviewErr = await recordNativeReview(decision.reason, body);
        if (reviewErr) {
          return await finish(false, { reason: decision.reason, ...body }, `native review row: ${reviewErr}`);
        }
      }
      return await finish(decision.ack, { reason: decision.reason, ...body }, decision.ack ? undefined : decision.reason);
    }

    // Schema-scoped service clients. PostgREST selects the schema at client
    // CONSTRUCTION time, so `venue.` / `kernel.` verbs each need their own
    // client (the house pattern — primary-checkout:914, connect-onboarding:680).
    // Built lazily so the legacy resale path constructs nothing new.
    const venueService = () =>
      createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
        auth: { autoRefreshToken: false, persistSession: false },
        db:   { schema: 'venue' },
      });
    const kernelService = () =>
      createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
        auth: { autoRefreshToken: false, persistSession: false },
        db:   { schema: 'kernel' },
      });

    /**
     * The alert half of `finishDecision`, WITHOUT ending the request. Used by
     * the native dispute / reversal arms on their ACK paths: the native work is
     * done and alerted, and the legacy arm below it still runs and produces the
     * response exactly as it does today (KH §4.3: the legacy `disputes` upsert
     * and the `payments.status='refunded'` write are kept for native rows).
     * A native `ack:false` never reaches here — it returns 500 through
     * `finishDecision` BEFORE the legacy arm runs (KH §4.5 ordering note).
     *
     * An alerted ACK also writes the review row (recordNativeReview). Returns
     * that write's error, or null; on an error the caller answers 500 BEFORE
     * the legacy arm runs, so an alerted native fact is never acknowledged
     * without its record. (On the redelivery the kernel verb answers
     * noop_replay without an alert, so the row is not re-attempted; the first
     * delivery's Sentry capture is then the only trace — a narrow, logged gap.)
     */
    async function alertDecision(
      decision: Decision,
      body: Record<string, unknown>,
      cause?: unknown,
    ): Promise<string | null> {
      if (!decision.alert) return null;
      await captureException(
        `stripe-webhook:${decision.reason}`,
        cause instanceof Error ? cause : new Error(decision.reason),
        { event_id: event.id, event_type: event.type, ...body },
      );
      return await recordNativeReview(decision.reason, body);
    }

    type NativeArmResult = { decision: Decision; body: Record<string, unknown>; cause?: Error } | null;

    /**
     * ═══════════════════════════════════════════════════════════════════════
     * NATIVE PRIMARY dispute arm — KH §4.5 is the normative table.
     *
     * Returns null when the event is legacy-only (no PaymentIntent, no
     * payments row, or `mode` is a resale mode) — the caller then runs the
     * legacy arm alone, exactly as today. Otherwise returns the Decision.
     *
     * THE DISCRIMINATOR IS DB-DERIVED (KH P1-2). A Dispute has no metadata of
     * its own; `public.payments.mode === 'native_primary'` for the dispute's
     * `payment_intent`, read through the service client, is the rail. Nothing
     * here reads metadata off the Dispute.
     *
     * THE VERBS: `created` ⇒ `record_dispute_native` (replay-safe by
     * `stripe_dispute_ref`; NEVER `mark`, which is unordered inside the open
     * set — KH P1-4). `updated` / `closed` / `funds_*` ⇒ `mark_dispute_state`;
     * P0002 ⇒ record at the payload's status; if THAT is `noop_replay` a
     * concurrent `created` won the insert race and `mark` is re-issued once.
     *
     * WHAT IS ACKED AND ALERTED, NEVER RETRIED: `state_conflict` (the row is
     * terminal — 088:887-892), `not_found` from record, `invalid_input`, an
     * unknown status, a non-live event or row. What is RETRIED: 42501 /
     * PGRST202 (with alert), transient Postgres classes.
     *
     * `won` releases nothing (PFA-31). No obligation is booked here (KH P1-6).
     * ═══════════════════════════════════════════════════════════════════════
     */
    async function runNativeDisputeArm(eventKind: DisputeEventKind): Promise<NativeArmResult> {
      const d = event.data.object as DisputeLike;
      const disputeRef = typeof d?.id === 'string' ? d.id : null;
      const piRef = typeof d?.payment_intent === 'string' && d.payment_intent.length > 0 ? d.payment_intent : null;
      const base: Record<string, unknown> = { stage: 'native_dispute', event_kind: eventKind, dispute_id: disputeRef, pi_id: piRef };

      if (!piRef) {
        console.log('Webhook: dispute carries no payment_intent — legacy arm only', base);
        return null;
      }

      // ── 0-2. the discriminator: public.payments by PI, service client ──────
      const { data: row, error: rowErr } = await supabase
        .from('payments')
        .select(DISPUTE_PAYMENT_COLUMNS)
        .eq('stripe_payment_intent_id', piRef)
        .maybeSingle();
      if (rowErr) {
        // We do not know which rail this is. Retryable: the read is idempotent.
        console.error('Webhook: native dispute payment read errored', { ...base, error: rowErr.message });
        return {
          decision: { ack: false, alert: true, reason: 'native_dispute_payment_read_error' },
          body: base,
          cause: new Error(rowErr.message),
        };
      }
      const paymentRow = (row as DisputePaymentRow | null) ?? null;
      const rail = resolveDisputeRail(paymentRow, d, event.livemode);
      if (rail.route === 'legacy') {
        console.log('Webhook: dispute routed to the legacy arm', { ...base, why: rail.why, mode: paymentRow?.mode ?? null });
        return null;
      }
      const body: Record<string, unknown> = { ...base, payment_id: rail.paymentId };

      // ── 3. the livemode gate — no native write; legacy still runs ──────────
      if (rail.route === 'not_livemode') {
        console.error('Webhook: native dispute refused — not livemode', {
          ...body, event_livemode: event.livemode ?? null, payment_livemode: paymentRow?.stripe_livemode ?? null,
        });
        return { decision: rail.decision, body };
      }

      // ── 4. the status must be one the kernel CHECK admits ─────────────────
      const status = d.status;
      if (!disputeStatusKnown(status)) {
        console.error('Webhook: native dispute status outside the kernel set', { ...body, status: String(status) });
        return {
          decision: { ack: true, alert: true, reason: 'native_dispute_unknown_status' },
          body: { ...body, status: String(status) },
        };
      }
      if (!disputeRef) {
        return {
          decision: { ack: true, alert: true, reason: 'native_dispute_event_malformed' },
          body: { ...body, detail: 'dispute.id missing' },
        };
      }

      const commandKey = buildDisputeCommandKey(eventKind, event.id);
      const recordArgs = disputeRecordArgs(d, commandKey);
      if (!recordArgs.ok) {
        console.error('Webhook: native dispute event malformed', { ...body, detail: recordArgs.detail });
        return { decision: recordArgs.decision, body: { ...body, detail: recordArgs.detail } };
      }
      const kernel = kernelService();

      const callRecord = async (): Promise<
        | { kind: 'error'; decision: Decision; cause: Error }
        | { kind: 'result'; outcome: ReturnType<typeof interpretRecordResult> }
      > => {
        const { data, error } = await kernel.rpc('record_dispute_native', recordArgs.args);
        if (error) {
          const decision = classifyDisputeError(error, { verb: 'record', eventKind });
          console.error('Webhook: record_dispute_native failed', {
            ...body, code: error.code, message: error.message, reason: decision.reason, ack: decision.ack,
          });
          return { kind: 'error', decision, cause: new Error(error.message) };
        }
        const result = (data as RecordDisputeResult | null) ?? null;
        const outcome = interpretRecordResult(result, { eventKind, payloadStatus: status });
        console.log('Webhook: record_dispute_native returned', {
          ...body, rpc_status: outcome.rpcStatus, dispute_row_id: outcome.disputeId, status,
          atoms_held: result?.atoms_held ?? null, atoms_skipped: result?.atoms_skipped ?? null,
          payouts_held: result?.payouts_held ?? null, linked: result?.linked ?? null,
          reason: outcome.decision.reason, flags: outcome.flags,
        });
        return { kind: 'result', outcome };
      };

      const callMark = async (): Promise<
        | { kind: 'error'; error: { code?: string | null; message: string } }
        | { kind: 'result'; outcome: ReturnType<typeof interpretMarkResult> }
      > => {
        const { data, error } = await kernel.rpc('mark_dispute_state', disputeMarkArgs(disputeRef, status, commandKey));
        if (error) return { kind: 'error', error };
        const outcome = interpretMarkResult((data as MarkDisputeResult | null) ?? null, { eventKind, newStatus: status });
        console.log('Webhook: mark_dispute_state returned', {
          ...body, rpc_status: outcome.rpcStatus, dispute_row_id: outcome.disputeId, status,
          reason: outcome.decision.reason,
        });
        return { kind: 'result', outcome };
      };

      const plan = planDisputeVerb(eventKind);

      if (plan.kind === 'record') {
        const r = await callRecord();
        if (r.kind === 'error') return { decision: r.decision, body, cause: r.cause };
        return { decision: r.outcome.decision, body: { ...body, rpc_status: r.outcome.rpcStatus, flags: r.outcome.flags } };
      }

      // mark_then_record
      const m1 = await callMark();
      if (m1.kind === 'result') {
        return { decision: m1.outcome.decision, body: { ...body, rpc_status: m1.outcome.rpcStatus } };
      }
      if (!isDisputeNotFound(m1.error)) {
        const decision = classifyDisputeError(m1.error, { verb: 'mark', eventKind });
        console.error('Webhook: mark_dispute_state failed', {
          ...body, code: m1.error.code, message: m1.error.message, reason: decision.reason, ack: decision.ack,
        });
        return { decision, body, cause: new Error(m1.error.message) };
      }
      // P0002: `updated`/`closed` arrived before `created`. Record at the
      // payload's status (KH B2/C2 — zero freeze legs at terminal, alerted by
      // interpretRecordResult).
      console.log('Webhook: mark_dispute_state not_found — recording at payload status', { ...body, status });
      const r = await callRecord();
      if (r.kind === 'error') return { decision: r.decision, body, cause: r.cause };
      if (r.outcome.rpcStatus === 'ok') {
        return { decision: r.outcome.decision, body: { ...body, rpc_status: 'ok', fallback: 'record', flags: r.outcome.flags } };
      }
      // noop_replay: a concurrent `created` won the insert race (088:799-803,
      // KH P2-7). The row exists now, so `mark` is re-issued exactly once.
      const m2 = await callMark();
      if (m2.kind === 'result') {
        return { decision: m2.outcome.decision, body: { ...body, rpc_status: m2.outcome.rpcStatus, fallback: 'record_then_mark' } };
      }
      const decision = classifyDisputeError(m2.error, { verb: 'mark', eventKind });
      console.error('Webhook: mark_dispute_state failed after record replay', {
        ...body, code: m2.error.code, message: m2.error.message, reason: decision.reason, ack: decision.ack,
      });
      return { decision, body: { ...body, fallback: 'record_then_mark' }, cause: new Error(m2.error.message) };
    }

    /**
     * ═══════════════════════════════════════════════════════════════════════
     * NATIVE `transfer.reversed` arm — KH §4.6 routing, DESIGN §2.2 verb.
     *
     * A Transfer carries its OWN metadata, so the rail is read off the object
     * (`metadata.source='payout-execute'` + `metadata.payout_id`, or
     * `transfer_group = payout_<uuid>`); the legacy rail is
     * `metadata.transfer_id` with no group. Both / neither / disagreeing ⇒
     * ACK + alert `transfer_rail_ambiguous`, nothing guessed; the legacy arm
     * then runs as today (its `mark_transfer_reversed` answers `false` for an
     * unknown `tr_` — harmless).
     *
     * One `kernel.record_payout_reversal` per reversal fact (`trr_`), paging
     * the list read-only when `has_more`. Replay is the verb's (`trr_` unique).
     * ═══════════════════════════════════════════════════════════════════════
     */
    async function runNativeTransferReversedArm(): Promise<NativeArmResult> {
      const tr = event.data.object as TransferLike;
      const trRef = typeof tr?.id === 'string' ? tr.id : null;
      const rail = resolveTransferRail(tr);
      const base: Record<string, unknown> = {
        stage: 'native_transfer_reversed', stripe_transfer_ref: trRef,
        transfer_group: typeof tr?.transfer_group === 'string' ? tr.transfer_group : null,
      };
      if (rail.route === 'legacy') return null;
      // Restore (2026-10-27): a Transfer carrying NO marker of either rail
      // (`neither`) is not a native payout — payout-execute stamps both
      // metadata.source/payout_id AND transfer_group payout_<uuid> on every
      // transfer it creates (executor.ts:538, :773-776). It stays on the
      // legacy arm alone, exactly as before native routing existed; only a
      // transfer that claims the native rail in SOME way is ambiguous.
      if (rail.route === 'ambiguous' && rail.why === 'neither') return null;
      if (rail.route === 'ambiguous') {
        console.error('Webhook: transfer.reversed rail ambiguous — nothing recorded', { ...base, why: rail.why });
        return { decision: rail.decision, body: { ...base, why: rail.why } };
      }
      const body: Record<string, unknown> = { ...base, payout_id: rail.payoutId, via: rail.via };

      // ── the reversal list: inline page, then the wire when has_more ────────
      const inline = readInlineReversals(tr);
      if (!inline.ok) {
        console.error('Webhook: transfer.reversed reversal list unreadable', { ...body, detail: inline.detail });
        return { decision: { ack: true, alert: true, reason: 'native_reversal_list_unreadable' }, body: { ...body, detail: inline.detail } };
      }
      let reversals = inline.reversals;
      if (inline.hasMore) {
        if (!trRef) {
          return { decision: { ack: true, alert: true, reason: 'native_reversal_transfer_ref_malformed' }, body };
        }
        const paged = await readTransferReversalsAfter(trRef, reversals[reversals.length - 1]?.id ?? null);
        if (!paged.ok) {
          console.error('Webhook: transfer.reversed reversal page read failed — retrying', { ...body, detail: paged.detail });
          return { decision: { ack: false, alert: true, reason: 'native_reversal_list_read_failed' }, body: { ...body, detail: paged.detail } };
        }
        reversals = mergeReversals(reversals, paged.reversals);
      }

      const plan = planReversalRecording(tr, rail.payoutId, reversals, event.id);
      if (plan.kind === 'decision') {
        console.error('Webhook: transfer.reversed not recordable', { ...body, reason: plan.decision.reason, detail: plan.detail });
        return { decision: plan.decision, body: { ...body, detail: plan.detail } };
      }

      const kernel = kernelService();
      const decisions: Decision[] = [];
      let cause: Error | undefined;
      for (const args of plan.calls) {
        const { data, error } = await kernel.rpc('record_payout_reversal', args);
        if (error) {
          const decision = classifyReversalError(error);
          console.error('Webhook: record_payout_reversal failed', {
            ...body, stripe_reversal_ref: args.p_stripe_reversal_ref, amount_minor: args.p_amount_minor,
            code: error.code, message: error.message, reason: decision.reason, ack: decision.ack,
          });
          decisions.push(decision);
          cause = cause ?? new Error(error.message);
          if (!decision.ack) break;
          continue;
        }
        const result = (data as RecordPayoutReversalResult | null) ?? null;
        const decision = interpretReversalResult(result);
        console.log('Webhook: record_payout_reversal returned', {
          ...body, stripe_reversal_ref: args.p_stripe_reversal_ref, amount_minor: args.p_amount_minor,
          rpc_status: result?.status ?? null, payout_status: result?.payout_status ?? null,
          total_reversed_minor: result?.total_reversed_minor ?? null, fully_reversed: result?.fully_reversed ?? null,
          reason: decision.reason,
        });
        decisions.push(decision);
      }
      return {
        decision: aggregateDecisions(decisions),
        body: { ...body, reversal_count: plan.calls.length, outcomes: decisions.map((x) => x.reason) },
        cause,
      };
    }

    if (event.type === 'payment_intent.succeeded') {
      // ═══════════════════════════════════════════════════════════════════
      // RAIL DISPATCH (spec §4:1206 — "all branches keyed off metadata.rail").
      //
      // THE THIRD BRANCH. Authored 2026-09-02 (471c863c), not carried by the
      // 2026-09-06 converged RC (733e114b, "paused expansion"), restored
      // 2026-10-27. Without it a `native_primary` PaymentIntent reaches
      // settle_verified_payment, which answers `not_external_rail` with no
      // write, and the event was ACKed: buyer charged, no order finalized, no
      // ticket minted, nothing recorded. That is the failure mode this block
      // removes.
      //
      // `resolveRail` is rail-first and asserts `mode === rail`; an absent
      // `rail` is the ONLY legitimate legacy signal, and every other value
      // fails closed rather than falling through to a resale money path.
      // ═══════════════════════════════════════════════════════════════════
      const route = resolveRail(metadata);

      if (route.route === 'rail_mode_mismatch' || route.route === 'unknown_rail') {
        const decision = dispositionForRoute(route);
        console.error('Webhook: rail dispatch refused', {
          pi_id: piId, route: route.route, reason: decision.reason, ack: decision.ack,
        });
        return await finishDecision(decision, { stage: 'rail_dispatch', pi_id: piId });
      }

      if (route.route === 'native_primary') {
        // ───────────────────────────────────────────────────────────────
        // NATIVE PRIMARY — money-in becomes tickets (rulings A2/A3).
        // ───────────────────────────────────────────────────────────────
        const meta = readNativeMetadata(metadata);
        if (!meta.ok) {
          // A redelivery carries the SAME metadata, so this can never resolve.
          console.error('Webhook: native_primary metadata incomplete', { pi_id: piId, reason: meta.reason });
          return await finishDecision(
            { ack: true, alert: true, reason: `native_${meta.reason}` },
            { stage: 'native_metadata', pi_id: piId },
          );
        }
        const ref = meta.ref;
        const ageSeconds = eventAgeSeconds(event.created, Date.now());

        // ── 1. Claim the payments row ───────────────────────────────────
        // Same idempotent-claim idiom as the legacy arm, plus one native-only
        // guard: `.neq('status','refunded')`. Without it an out-of-order
        // `charge.refunded` would be silently overwritten back to 'succeeded'.
        const { data: claimed, error: claimErr } = await supabase
          .from('payments')
          .update({ status: 'succeeded', paid_at: new Date().toISOString() })
          .eq('stripe_payment_intent_id', piId)
          .neq('status', 'succeeded')
          .neq('status', 'refunded')
          .select(NATIVE_PAYMENT_COLUMNS)
          .maybeSingle();

        if (claimErr) {
          // We do not know whether the claim landed. Retryable by construction:
          // the claim is idempotent, so a redelivery either claims or reads.
          console.error('Webhook: native payment claim errored', { pi_id: piId, error: claimErr });
          return await finishDecision(
            { ack: false, alert: true, reason: 'native_payment_claim_error' },
            { stage: 'native_payment_claim', pi_id: piId },
            new Error(claimErr.message),
          );
        }

        let existingPayment: PaymentRow | null = null;
        if (!claimed) {
          const { data: found, error: readErr } = await supabase
            .from('payments')
            .select(NATIVE_PAYMENT_COLUMNS)
            .eq('stripe_payment_intent_id', piId)
            .maybeSingle();
          if (readErr) {
            return await finishDecision(
              { ack: false, alert: true, reason: 'native_payment_read_error' },
              { stage: 'native_payment_read', pi_id: piId },
              new Error(readErr.message),
            );
          }
          existingPayment = (found as PaymentRow | null) ?? null;
        }

        const claimOutcome = interpretPaymentClaim((claimed as PaymentRow | null) ?? null, existingPayment);
        if (claimOutcome.kind !== 'claimed' && claimOutcome.kind !== 'already_succeeded') {
          const decision = decideClaimOutcome(claimOutcome, ageSeconds);
          console.error('Webhook: native payment row not finalizable', {
            pi_id: piId, order_id: ref.orderId, outcome: claimOutcome.kind,
            reason: decision.reason, ack: decision.ack, event_age_seconds: ageSeconds,
          });
          return await finishDecision(decision, {
            stage: 'native_payment_state', pi_id: piId, order_id: ref.orderId, outcome: claimOutcome.kind,
          });
        }
        const paymentRow = claimOutcome.row;

        // ── 2. The row must be a DIRECT-RAIL row for THIS buyer ─────────
        const verdict = verifyNativePaymentRow(paymentRow, ref);
        if (!verdict.ok) {
          console.error('Webhook: native payment row failed rail verification', {
            pi_id: piId, order_id: ref.orderId, payment_id: paymentRow.id, reason: verdict.decision.reason,
          });
          return await finishDecision(verdict.decision, {
            stage: 'native_payment_verify', pi_id: piId, order_id: ref.orderId, payment_id: paymentRow.id,
          });
        }

        // ── 3. Instrument fingerprint — advisory, never blocking ────────
        const fingerprint = await readInstrumentFingerprint(paymentIntent);

        // ── 4. Finalize: the ONLY function that turns money into tickets ─
        // The command key is derived from (order, PaymentIntent), NOT from
        // event.id — see buildFinalizeCommandKey. That is what makes the
        // domain-level dedupe survive a second event id for the same payment.
        const commandKey = buildFinalizeCommandKey(ref.orderId, piId);
        console.log('Webhook: finalizing native primary order', {
          order_id: ref.orderId, payment_id: paymentRow.id, pi_id: piId,
          claim: claimOutcome.kind, has_fingerprint: fingerprint !== null,
        });

        const { data: finalizeData, error: finalizeErr } = await venueService().rpc('finalize_primary_order', {
          p_order_id:               ref.orderId,
          p_payment_id:             paymentRow.id,
          p_command_key:            commandKey,
          p_instrument_fingerprint: fingerprint,
        });

        if (finalizeErr) {
          const decision = classifyFinalizeError(finalizeErr);
          console.error('Webhook: finalize_primary_order failed', {
            order_id: ref.orderId, payment_id: paymentRow.id, pi_id: piId,
            code: finalizeErr.code, reason: decision.reason, ack: decision.ack,
            message: finalizeErr.message,
          });
          return await finishDecision(
            decision,
            { stage: 'finalize_primary_order', order_id: ref.orderId, payment_id: paymentRow.id, pi_id: piId },
            new Error(finalizeErr.message),
          );
        }

        const finalizeStatus = (finalizeData as { status?: string } | null)?.status ?? 'ok';
        const atomCount = ((finalizeData as { atom_ids?: unknown[] } | null)?.atom_ids ?? []).length;
        console.log('Webhook: native primary order finalized', {
          order_id: ref.orderId, payment_id: paymentRow.id, pi_id: piId,
          status: finalizeStatus, atom_count: atomCount,
        });
        // No push here. There is no listing and no individual seller on this
        // rail; primary notification is `notify-dispatch`'s pipeline (spec
        // §3.13), and inventing a `send-push` call would create a contract this
        // branch is not entitled to define.
        return await finishDecision(
          { ack: true, alert: false, reason: `native_primary_${finalizeStatus}` },
          { order_id: ref.orderId, payment_id: paymentRow.id, atom_count: atomCount },
        );
      }

      // ═══════════════════════════════════════════════════════════════════
      // LEGACY RESALE — unchanged below, except the not_external_rail
      // outcome, which no resale row can produce.
      // ═══════════════════════════════════════════════════════════════════
      // ── Package 2: ONE call to the verified-settlement contract ─────────
      // settle_verified_payment (migration 20260906110000) verifies the
      // PaymentIntent's facts against the stored row (amount / currency /
      // livemode / metadata), enforces refund monotonicity, promotes only on
      // Stripe `succeeded`, settles the listing + transfer through the
      // Package 1 core, and records every non-settling outcome once in
      // webhook_retries. It replaces the old claim-UPDATE + client RPC +
      // transfer INSERT sequence AND the "already processed" fallback branch
      // (investigation F02: the retry used to skip the sale RPC forever).
      //
      // Acknowledgment: any RPC ERROR is NOT terminal — 500 + fail, so Stripe
      // redelivers and the retry calls the contract AGAIN (it is guarded by
      // current state, not by "did I run before"). Every RPC OUTCOME is
      // terminal — 200 + complete — because the contract already recorded
      // unknown_payment / binding_mismatch / unfulfillable for the sweep and
      // for ops; retrying a terminal outcome for three days helps nobody.
      // Refund facts arrive via charge.refunded (Package 3's branch), so this
      // event passes amount_refunded 0 / refund id NULL: the contract still
      // refuses to promote a row that is already refunded.
      const pi = paymentIntent as {
        status?: string; amount_received?: number; currency?: string; livemode?: boolean;
        payment_method_types?: string[]; metadata?: Record<string, string>;
      };
      const { data: settleRows, error: settleErr } = await supabase.rpc('settle_verified_payment', {
        p_payment_intent_id: piId,
        p_stripe_status:     pi.status ?? 'succeeded',
        p_amount_received:   typeof pi.amount_received === 'number' ? pi.amount_received : null,
        p_currency:          pi.currency ?? null,
        p_livemode:          typeof pi.livemode === 'boolean' ? pi.livemode : null,
        p_amount_refunded:   0,
        p_stripe_refund_id:  null,
        p_payment_method:    pi.payment_method_types?.[0] ?? 'card',
        p_metadata:          metadata,
        p_source:            `webhook:${event.id}`,
      });

      if (settleErr) {
        console.error('Webhook: settle_verified_payment failed', { pi_id: piId, event_id: event.id, error: settleErr });
        return await finish(false, { stage: 'settle_verified_payment' }, `settle_verified_payment: ${settleErr.message}`);
      }

      const settled = (Array.isArray(settleRows) ? settleRows[0] : settleRows) as
        | { payment_id: string | null; payment_status: string | null; listing_status: string | null; transfer_id: string | null; outcome: string }
        | null
        | undefined;
      if (!settled?.outcome) {
        // The contract always returns exactly one row; no row means the call
        // did not run to completion (PostgREST hiccup) — not terminal.
        console.error('Webhook: settle_verified_payment returned no row', { pi_id: piId, event_id: event.id });
        return await finish(false, { stage: 'settle_verified_payment' }, 'settle_verified_payment: no row');
      }

      const outcomeLog = {
        pi_id: piId, event_id: event.id, outcome: settled.outcome,
        payment_id: settled.payment_id, payment_status: settled.payment_status,
        listing_status: settled.listing_status, transfer_id: settled.transfer_id,
      };
      if (settled.outcome === 'settled' || settled.outcome === 'already_settled') {
        console.log('Webhook: settlement outcome', outcomeLog);
      } else {
        // unfulfillable / binding_mismatch / unknown_payment are in the
        // webhook_retries review queue (the sweep refunds unfulfillable);
        // refunded / not_succeeded / canceled are benign state facts.
        console.warn('Webhook: non-settling outcome (terminal, recorded by the contract)', outcomeLog);
      }

      if (settled.outcome === 'not_external_rail') {
        // ── A kernel-rail row the rail dispatch above did not classify ──────
        // settle_verified_payment answers not_external_rail — with NO write and
        // NO review row (20260906110000:176-182) — only for a payments row that
        // is not a resale row (mode 'native_primary' / listing_id NULL); a
        // buy_now or auction row can never produce it. Reaching it here means
        // the PaymentIntent's metadata did not route the event to the native
        // arm, so nothing finalized the order, and a redelivery carries the
        // same metadata. It used to be ACKed after the warn line above and
        // nothing else. Now: alert + durable review row, then ACK; if the row
        // cannot be written the event is not acknowledged (finishDecision).
        return await finishDecision(
          { ack: true, alert: true, reason: 'native_row_unrouted' },
          { stage: 'rail_dispatch', pi_id: piId, payment_id: settled.payment_id, outcome: settled.outcome },
        );
      }

      if (settled.outcome === 'settled' && metadata.buyer_id && metadata.seller_id) {
        // First and only time this sale settled: notify both parties. The
        // transfer id (from the contract) deep-links to the send/receive
        // screens; listingId remains the fallback route.
        const { data: listing } = await supabase
          .from('listings')
          .select('event_name')
          .eq('id', metadata.listing_id)
          .maybeSingle();
        const listingTitle = listing?.event_name || 'your listing';
        const transferIdData: Record<string, string> = settled.transfer_id ? { transferId: String(settled.transfer_id) } : {};

        sendPush(
          metadata.buyer_id,
          'Payment Confirmed!',
          `Your payment for ${listingTitle} was successful. Waiting for seller to transfer the ticket.`,
          { listingId: metadata.listing_id, type: 'payment_succeeded', ...transferIdData },
        );
        // Notification batch 1 (owner ruling 2026-09-17): honour the seller's
        // own "Listing sold" toggle, which has existed in the schema and the
        // app since the baseline and which nothing has ever read.
        //
        // An ABSENT row means true — the column's default is true and rows are
        // auto-created on profile insert, so absence means an older account,
        // not an opt-out. A FAILED read also means true, deliberately: this
        // push is what tells the seller to send the transfer, so losing it
        // stalls a paid sale, while the preference is a convenience. Fail
        // toward delivering, and say so in the log.
        //
        // The buyer's confirmation above is mandatory: it is never read from
        // preferences and never suppressed, and it is sent BEFORE this read so
        // that no preference failure can affect it.
        let sellerOptedOut = false;
        const { data: sellerPrefs, error: prefErr } = await supabase
          .from('notification_preferences')
          .select('notify_listing_sold')
          .eq('user_id', metadata.seller_id)
          .maybeSingle();
        if (prefErr) {
          // Stable token so "we are currently ignoring preferences" is greppable:
          // a fail-open that cannot be seen becomes a permanent degradation (D).
          console.warn('Webhook: seller sold-notification preference unreadable, defaulting to send', { reason: 'pref_read_failed', code: prefErr.code ?? null });
        } else if (sellerPrefs?.notify_listing_sold === false) {
          sellerOptedOut = true;
        }

        if (!sellerOptedOut) {
          sendPush(
            metadata.seller_id,
            'Your ticket sold!',
            `Send the transfer now for ${listingTitle}.`,
            { listingId: metadata.listing_id, type: 'ticket_sold', ...transferIdData },
          );
        }
      }

      return await finish(true, {
        outcome:     settled.outcome,
        payment_id:  settled.payment_id,
        transfer_id: settled.transfer_id,
      });

    } else if (event.type === 'payment_intent.payment_failed' || event.type === 'payment_intent.canceled') {
      // ═══════════════════════════════════════════════════════════════════
      // RAIL DISPATCH for the failure/cancel events.
      //
      // On the legacy rail `payment_intent.canceled` is handled by the L1 arm
      // below, untouched. On the native rail it is THE terminal signal, and
      // the only one: Stripe emits no other event from which "this
      // PaymentIntent can never be confirmed" can be read.
      // ═══════════════════════════════════════════════════════════════════
      const failRoute = resolveRail(metadata);

      if (failRoute.route === 'rail_mode_mismatch' || failRoute.route === 'unknown_rail') {
        const decision = dispositionForRoute(failRoute);
        console.error('Webhook: rail dispatch refused on failure event', {
          pi_id: piId, event_type: event.type, route: failRoute.route, reason: decision.reason,
        });
        return await finishDecision(decision, { stage: 'rail_dispatch', pi_id: piId });
      }

      if (failRoute.route === 'native_primary') {
        const meta = readNativeMetadata(metadata);
        if (!meta.ok) {
          console.error('Webhook: native_primary failure metadata incomplete', { pi_id: piId, reason: meta.reason });
          return await finishDecision(
            { ack: true, alert: true, reason: `native_${meta.reason}` },
            { stage: 'native_metadata', pi_id: piId },
          );
        }
        const ref = meta.ref;

        // Record the money fact first. Guarded against BOTH terminal states:
        // one PI legitimately goes failed→succeeded when the buyer retries in
        // the same PaymentSheet, and a refund must not be reopened as 'failed'.
        const { error: failErr } = await supabase
          .from('payments')
          .update({ status: 'failed' })
          .eq('stripe_payment_intent_id', piId)
          .neq('status', 'succeeded')
          .neq('status', 'refunded');
        if (failErr) {
          return await finishDecision(
            { ack: false, alert: true, reason: 'native_payment_fail_mark_error' },
            { stage: 'native_fail_mark', pi_id: piId, order_id: ref.orderId },
            new Error(failErr.message),
          );
        }

        // SPEC §4: cancel the pending order ONLY on a TERMINAL PaymentIntent.
        // A per-attempt decline cancels NOTHING — §3.1's retry contract lets
        // the buyer re-confirm the same PI in the same sheet, and cancelling
        // the order would destroy an order still being paid for. Capacity
        // returns via the §20.3.3 hold-TTL sweep, not from here: 082 persists
        // no order→hold linkage to release directly.
        if (!isTerminalPaymentIntent(paymentIntent)) {
          console.log('Webhook: native_primary payment attempt failed, order left pending', {
            pi_id: piId, order_id: ref.orderId, pi_status: paymentIntent?.status ?? null,
          });
          return await finishDecision(
            { ack: true, alert: false, reason: 'native_attempt_failed_order_pending' },
            { order_id: ref.orderId, pi_id: piId },
          );
        }

        const { data: cancelData, error: cancelErr } = await venueService().rpc('cancel_pending_order', {
          p_order_id:    ref.orderId,
          p_reason_code: CANCEL_REASON_PAYMENT_FAILED,
          p_command_key: buildCancelCommandKey(ref.orderId, piId),
        });

        if (cancelErr) {
          const decision = classifyCancelError(cancelErr);
          console.error('Webhook: cancel_pending_order failed', {
            order_id: ref.orderId, pi_id: piId, code: cancelErr.code,
            reason: decision.reason, ack: decision.ack, message: cancelErr.message,
          });
          return await finishDecision(
            decision,
            { stage: 'cancel_pending_order', order_id: ref.orderId, pi_id: piId },
            new Error(cancelErr.message),
          );
        }

        const cancelStatus = (cancelData as { status?: string } | null)?.status ?? 'cancelled';
        console.log('Webhook: native primary order cancelled', {
          order_id: ref.orderId, pi_id: piId, status: cancelStatus,
        });
        return await finishDecision(
          { ack: true, alert: false, reason: `native_order_${cancelStatus}` },
          { order_id: ref.orderId, pi_id: piId },
        );
      }

      // ═══════════════════════════════════════════════════════════════════
      // LEGACY RESALE payment_failed / canceled — unchanged below (L1).
      // ═══════════════════════════════════════════════════════════════════
      // Claim guard: Stripe does NOT guarantee event ordering, and one PI
      // legitimately goes failed→succeeded when the buyer retries in the
      // same PaymentSheet. Only a LIVE attempt (pending | processing) is
      // claimed. A late payment_failed / canceled must never overwrite a
      // payment that already succeeded (it would freeze the payout and release
      // the hold on a sold listing) or one already refunded — and (L1) never
      // re-claim a row that is already `failed`: create-payment-intent retires
      // a superseded intent itself, and Stripe's cancel event for it arrives
      // while the buyer's REPLACEMENT attempt is using the same hold.
      const { data: payment, error: lookupErr } = await supabase
        .from('payments')
        .update({ status: 'failed' })
        .eq('stripe_payment_intent_id', piId)
        .in('status', ['pending', 'processing'])
        .select('id, listing_id')
        .maybeSingle();

      if (lookupErr) {
        // The authoritative write did not happen; we do not know the row's
        // state. Non-terminal — Stripe redelivers (used to be ACKed with 200).
        console.error('Webhook: payment failed/canceled update errored', { pi_id: piId, event_type: event.type, error: lookupErr });
        return await finish(false, { stage: 'payment_failed_update' }, `${event.type}: ${lookupErr.message}`);
      }
      if (!payment) {
        // No claimable row — unknown PI, or the payment is no longer a live
        // attempt: succeeded / refunded / already failed (out-of-order,
        // duplicate, or a stale cancel of an intent checkout already retired).
        // Benign no-op: genuinely nothing left to do.
        console.log('Webhook: payment_failed/canceled ignored (no claimable row)', { pi_id: piId, event_type: event.type });
        return await finish(true, { skipped: 'no_claimable_row' });
      }

      if (metadata.mode === 'buy_now') {
        // Free the Buy-Now hold THIS payment was using — and only that (L1,
        // migration 127). release_reservation_for_payment is bound to the
        // payment: it refuses while another buy_now attempt by the buyer is
        // still pending/processing, when the hold is newer than the payment,
        // or when the listing has a succeeded payment, and reports why as
        // {released, reason}. The buyer-scoped release_reservation cannot
        // tell this payment's hold from the replacement's and is never called.
        // Best effort with a bounded backstop: the hold is server-owned
        // (10-minute TTL) and cleanup_expired_reservations frees it when it
        // lapses, so an RPC error — including a database that does not have
        // 127 yet (PGRST202) — is logged, not retried and not fatal.
        const { data: release, error: rpcErr } = await supabase.rpc('release_reservation_for_payment', {
          p_listing_id: metadata.listing_id,
          p_user_id:    metadata.buyer_id,
          p_payment_id: payment.id,
        });
        if (rpcErr) {
          console.error('Webhook RPC failed:', {
            listing_id: metadata.listing_id,
            payment_id: payment.id,
            rpc_name:   'release_reservation_for_payment',
            error:      rpcErr,
          });
        } else {
          const r = (release ?? {}) as { released?: boolean; reason?: string };
          console.log('Webhook: release_reservation_for_payment', {
            listing_id: metadata.listing_id,
            payment_id: payment.id,
            released:   r.released ?? null,
            reason:     r.reason ?? null,
          });
        }
      }
      return await finish(true, { path: event.type === 'payment_intent.canceled' ? 'canceled' : 'payment_failed', payment_id: payment.id });

    // ─────────────────────────────────────────────────────────────────────
    // P1-02 — Full event coverage with dedup at the top of the handler.
    //   • Dispute handlers freeze the related transfer so auto-release
    //     and confirm-and-release cannot fire while the case is pending.
    //   • Refund / payout / transfer events sync DB state for the
    //     admin SQL-pack ops queries (DAY8_P1_02_ADMIN_SQL_PACK.sql).
    //   • Every branch reaches markProcessed()/finish() so the
    //     public.stripe_webhook_events row reflects the actual outcome:
    //     success sets processed_at (terminal, never reprocessed), failure
    //     releases the lease so Stripe's retry reprocesses (migration 064).
    // ─────────────────────────────────────────────────────────────────────

    } else if (event.type === 'charge.dispute.created') {
      // ═══ NATIVE PRIMARY arm FIRST (KH §4.5) — the legacy arm below is unchanged ═══
      // A native `ack:false` returns 500 here, before the legacy arm runs; a
      // native ACK (with or without alert) lets the legacy arm run and answer.
      // A legacy dispute (resale row, no row, no PaymentIntent) returns null
      // from the native arm and takes only the legacy arm, as before.
      {
        const native = await runNativeDisputeArm('created');
        if (native && !native.decision.ack) return await finishDecision(native.decision, native.body, native.cause);
        if (native) {
          const reviewErr = await alertDecision(native.decision, native.body, native.cause);
          if (reviewErr) return await finish(false, { reason: native.decision.reason, ...native.body }, `native review row: ${reviewErr}`);
        }
      }
      // ── P1-02: real dispute handling + transfer freeze ────────────────
      // event.data.object is a Stripe Dispute, NOT a PaymentIntent.
      const dispute = event.data.object as {
        id:               string;
        charge:           string;
        payment_intent?:  string | null;
        amount:           number;
        currency:         string;
        reason:           string;
        status:           string;
        evidence_details?: { due_by?: number };
      };

      // 1. Find the related payment + transfer (best-effort; PI id may be
      //    missing on some Stripe API versions).
      let paymentId:  string | null = null;
      let transferId: string | null = null;
      if (dispute.payment_intent) {
        const { data: payment } = await supabase
          .from('payments')
          .select('id')
          .eq('stripe_payment_intent_id', dispute.payment_intent)
          .maybeSingle();
        paymentId = payment?.id ?? null;
        if (paymentId) {
          const { data: transfer } = await supabase
            .from('transfers')
            .select('id, status, payout_released_at')
            .eq('payment_id', paymentId)
            .maybeSingle();
          transferId = transfer?.id ?? null;

          // 2. Freeze the transfer so auto-release / confirm-and-release
          //    cannot fire while the dispute is open. Skip if already paid
          //    out — at that point we can only attempt a transfer reversal
          //    when the dispute is lost (handled in dispute.closed).
          if (transferId && !transfer!.payout_released_at && transfer!.status !== 'disputed') {
            // freeze_transfer_for_dispute (migration 056a) re-checks
            // payout_released_at IS NULL AND status <> 'disputed' inside the
            // statement, closing the read-then-write window the direct UPDATE
            // had, and bypasses guard_transfer_state_columns as SECURITY DEFINER.
            const { data: frozen, error: freezeErr } = await supabase
              .rpc('freeze_transfer_for_dispute', { p_transfer_id: transferId });
            if (freezeErr) {
              // Review round 2 (MINOR-5): a dispute we could not freeze is NOT
              // done — the transfer stays releasable while the dispute is open.
              // Answer non-2xx so Stripe redelivers; the upsert below is
              // idempotent and the lease is released by finish().
              console.error('Webhook: dispute transfer freeze failed:', {
                transfer_id: transferId, dispute_id: dispute.id, error: freezeErr,
              });
              return await finish(false, { dispute_id: dispute.id, transfer_id: transferId },
                `dispute freeze: ${freezeErr.message}`);
            } else if (!frozen) {
              // Not an error: the row was paid out or already frozen between
              // our read above and this call.
              console.log('Webhook: transfer freeze skipped — already frozen or already paid out', {
                transfer_id: transferId, dispute_id: dispute.id,
              });
            } else {
              console.log('Webhook: transfer frozen due to dispute', { transfer_id: transferId });
            }
          }
        }
      }

      // 3. Upsert disputes row (idempotent on stripe_dispute_id).
      const evidenceDueIso = dispute.evidence_details?.due_by
        ? new Date(dispute.evidence_details.due_by * 1000).toISOString()
        : null;
      const { error: upsertErr } = await supabase.from('disputes').upsert({
        stripe_dispute_id: dispute.id,
        stripe_charge_id:  dispute.charge,
        stripe_pi_id:      dispute.payment_intent ?? null,
        payment_id:        paymentId,
        transfer_id:       transferId,
        amount:            dispute.amount,
        currency:          dispute.currency ?? 'usd',
        reason:            dispute.reason,
        status:            dispute.status,
        evidence_due_by:   evidenceDueIso,
      }, { onConflict: 'stripe_dispute_id' });
      if (upsertErr) {
        // High-signal inner capture: a dispute event was received but we
        // failed to record it. Ops needs to know immediately so the
        // 7-day Stripe evidence window doesn't quietly close against us.
        await captureException(
          'stripe-webhook:charge.dispute.created',
          new Error(`dispute upsert failed: ${upsertErr.message}`),
          { dispute_id: dispute.id, charge_id: dispute.charge, payment_id: paymentId, transfer_id: transferId },
        );
        // Package 3: a dispute we failed to record is NOT done — answer
        // non-2xx so Stripe redelivers (the lease is released by finish).
        return await finish(false, { dispute_id: dispute.id }, `dispute upsert: ${upsertErr.message}`);
      } else {
        console.log('Webhook: dispute recorded', {
          dispute_id: dispute.id, charge_id: dispute.charge, amount: dispute.amount,
          reason: dispute.reason, status: dispute.status,
          evidence_due_by: evidenceDueIso,
          payment_id: paymentId, transfer_id: transferId,
        });
        await markProcessed();
      }

    } else if (
      event.type === 'charge.dispute.updated' ||
      event.type === 'charge.dispute.funds_withdrawn' ||
      event.type === 'charge.dispute.funds_reinstated'
    ) {
      // ═══ NEW BRANCH — native status sync (KH P2-4). No legacy write exists
      // for these types: before this branch they fell to the terminal `else`
      // (ack only), and for the legacy rail they still do, verbatim below. ═══
      {
        const native = await runNativeDisputeArm('updated');
        if (native) return await finishDecision(native.decision, native.body, native.cause);
      }
      console.log('Webhook: unhandled event type (ack only)', { event_type: event.type });
      await markProcessed();

    } else if (event.type === 'charge.dispute.closed') {
      // ═══ NATIVE PRIMARY arm FIRST (KH §4.5) — the legacy arm below is unchanged ═══
      {
        const native = await runNativeDisputeArm('closed');
        if (native && !native.decision.ack) return await finishDecision(native.decision, native.body, native.cause);
        if (native) {
          const reviewErr = await alertDecision(native.decision, native.body, native.cause);
          if (reviewErr) return await finish(false, { reason: native.decision.reason, ...native.body }, `native review row: ${reviewErr}`);
        }
      }
      // ── Package 3 (20260906120000): dispute outcome sync ───────────────
      // A LOST dispute is a chargeback: recorded through record_payment_refund
      // with the DISPUTE id (never as stripe_refund_id), monotonic amount, and
      // if the seller was already paid the attempt is flagged
      // reversal_required + manual_review DISPUTE_LOST_AFTER_PAYOUT for ops.
      // A dispute we never recorded (missed .created) is reconciled from this
      // event, not dropped. Every DB failure answers non-2xx (Stripe retries).
      const dispute = event.data.object as {
        id:     string;
        charge: string;
        payment_intent?: string | null;
        amount?: number;
        currency?: string;
        reason?: string;
        status: string; // 'won' | 'lost' | 'warning_closed' | 'charge_refunded'
      };

      let ourDispute: { id: string; payment_id: string | null; transfer_id: string | null } | null = null;
      {
        const { data, error: lookupErr } = await supabase
          .from('disputes')
          .update({ status: dispute.status })
          .eq('stripe_dispute_id', dispute.id)
          .select('id, payment_id, transfer_id')
          .maybeSingle();
        if (lookupErr) {
          console.error('Webhook: dispute status update failed:', lookupErr);
          return await finish(false, { dispute_id: dispute.id }, `dispute close update: ${lookupErr.message}`);
        }
        ourDispute = data ?? null;
      }

      if (!ourDispute) {
        // Unknown dispute: reconcile it from the event so the ledger is complete.
        console.warn('Webhook: dispute.closed for unknown dispute_id — upserting from event', { dispute_id: dispute.id });
        let paymentId: string | null = null;
        let transferId: string | null = null;
        if (dispute.payment_intent) {
          const { data: payment, error: payLookupErr } = await supabase
            .from('payments').select('id').eq('stripe_payment_intent_id', dispute.payment_intent).maybeSingle();
          if (payLookupErr) {
            return await finish(false, { dispute_id: dispute.id }, `dispute close payment lookup: ${payLookupErr.message}`);
          }
          paymentId = payment?.id ?? null;
          if (paymentId) {
            const { data: transfer, error: trLookupErr } = await supabase
              .from('transfers').select('id').eq('payment_id', paymentId).maybeSingle();
            if (trLookupErr) {
              return await finish(false, { dispute_id: dispute.id }, `dispute close transfer lookup: ${trLookupErr.message}`);
            }
            transferId = transfer?.id ?? null;
          }
        }
        const { error: upsertErr } = await supabase.from('disputes').upsert({
          stripe_dispute_id: dispute.id,
          stripe_charge_id:  dispute.charge,
          stripe_pi_id:      dispute.payment_intent ?? null,
          payment_id:        paymentId,
          transfer_id:       transferId,
          amount:            dispute.amount ?? 0,
          currency:          dispute.currency ?? 'usd',
          reason:            dispute.reason ?? 'unknown',
          status:            dispute.status,
        }, { onConflict: 'stripe_dispute_id' });
        if (upsertErr) {
          console.error('Webhook: dispute.closed upsert failed:', upsertErr);
          return await finish(false, { dispute_id: dispute.id }, `dispute close upsert: ${upsertErr.message}`);
        }
        ourDispute = { id: dispute.id, payment_id: paymentId, transfer_id: transferId };
      }

      if (dispute.status === 'lost' && ourDispute.payment_id) {
        // Resolve the PI id (event first, our payments row as fallback).
        let piId: string | null = dispute.payment_intent ?? null;
        if (!piId) {
          const { data: pay, error: piErr } = await supabase
            .from('payments').select('stripe_payment_intent_id').eq('id', ourDispute.payment_id).maybeSingle();
          if (piErr) return await finish(false, { dispute_id: dispute.id }, `dispute lost payment lookup: ${piErr.message}`);
          piId = pay?.stripe_payment_intent_id ?? null;
        }
        if (!piId) {
          return await finish(false, { dispute_id: dispute.id }, 'dispute lost: payment has no payment_intent id');
        }
        const { data: refundRes, error: refundErr } = await supabase.rpc('record_payment_refund', {
          p_payment_intent_id: piId,
          p_stripe_refund_id:  null,
          p_stripe_dispute_id: dispute.id,
          p_amount_cents:      typeof dispute.amount === 'number' ? dispute.amount : null,
          p_source:            'dispute_lost',
        });
        if (refundErr) {
          console.error('Webhook: dispute lost — record_payment_refund failed:', refundErr);
          return await finish(false, { dispute_id: dispute.id }, `dispute lost refund record: ${refundErr.message}`);
        }
        console.log('Webhook: dispute lost — chargeback recorded', { dispute_id: dispute.id, result: refundRes });

        // Seller already paid? The transfer must be reversed by an operator.
        if (ourDispute.transfer_id) {
          const { data: tr, error: trErr } = await supabase
            .from('transfers').select('id, payout_released_at, stripe_transfer_id')
            .eq('id', ourDispute.transfer_id).maybeSingle();
          if (trErr) return await finish(false, { dispute_id: dispute.id }, `dispute lost transfer lookup: ${trErr.message}`);
          if (tr && (tr.payout_released_at || tr.stripe_transfer_id)) {
            const { data: flagged, error: flagErr } = await supabase.rpc('flag_payout_reversal_required', {
              p_transfer_id: ourDispute.transfer_id,
              p_reason_code: 'DISPUTE_LOST_AFTER_PAYOUT',
              p_evidence:    { dispute_id: dispute.id, dispute_amount: dispute.amount ?? null },
            });
            if (flagErr) {
              console.error('Webhook: dispute lost — flag_payout_reversal_required failed:', flagErr);
              return await finish(false, { dispute_id: dispute.id }, `dispute lost reversal flag: ${flagErr.message}`);
            }
            console.error('Webhook: dispute LOST after payout — reversal required', {
              dispute_id: dispute.id, transfer_id: ourDispute.transfer_id, flagged,
            });
          }
        }
      }
      console.log('Webhook: dispute closed', {
        dispute_id: dispute.id, status: dispute.status,
        payment_id: ourDispute.payment_id, transfer_id: ourDispute.transfer_id,
      });
      await markProcessed();

    } else if (event.type === 'charge.refunded') {
      // ── Package 3 (20260906120000): refund sync ───────────────────────
      // Fires for partial AND full refunds. Each Stripe refund object is
      // recorded through record_refund_state (150) with its own status: the SQL
      // writer counts it toward the one-way payments record (record_payment_refund,
      // idempotent on re_ id) only while it is not failed/canceled, and keeps the
      // truthful per-refund state beside it. refund.created/updated/failed carry
      // every later change (branch below).
      // Recent API versions omit charge.refunds: fetch the charge with
      // expand[]=refunds rather than guessing. DB/Stripe failures → non-2xx.
      const charge = event.data.object as {
        id: string;
        payment_intent?: string | null;
        refunded?: boolean;
        amount_refunded?: number;
        refunds?: { data?: StripeRefund[] };
      };
      if (!charge.payment_intent) {
        console.warn('Webhook: charge.refunded with no payment_intent', { event_id: event.id });
        await markProcessed();
      } else {
        let refunds = charge.refunds?.data;
        if (!refunds) {
          const probe = await stripeFetchRaw(`/charges/${charge.id}?expand[]=refunds`);
          if (!probe.ok) {
            const msg = (probe.data as { error?: { message?: string } })?.error?.message ?? `HTTP ${probe.status}`;
            console.error('Webhook: charge.refunded — charge fetch failed:', { charge_id: charge.id, error: msg });
            return await finish(false, { charge_id: charge.id }, `refund sync charge fetch: ${msg}`);
          }
          refunds = (probe.data as typeof charge).refunds?.data ?? [];
        }
        // 150: each refund is written with ITS OWN status — a failed or canceled
        // refund in this list is never recorded as money returned. A listed
        // refund without a status is re-read from Stripe first.
        const results: unknown[] = [];
        for (const listed of refunds as StripeRefund[]) {
          if (!listed?.id) continue;
          let r: StripeRefund = listed;
          if (!r.status || !REFUND_STATUSES.has(r.status) || typeof r.amount !== 'number') {
            const got = await fetchRefund(listed.id);
            if (!got.ok) {
              console.error('Webhook: charge.refunded — refund fetch failed:', { refund_id: listed.id, error: got.error });
              return await finish(false, { charge_id: charge.id, refund_id: listed.id }, `refund fetch: ${got.error}`);
            }
            r = got.refund;
          }
          const { data: res, error: refErr } = await supabase.rpc('record_refund_state', {
            p_payment_intent_id: charge.payment_intent,
            p_stripe_refund_id:  listed.id,
            p_status:            r.status,
            p_amount_cents:      r.amount,
            p_failure_reason:    r.failure_reason ?? null,
            p_source:            refundSource(r),
            p_observed_via:      'webhook',
          });
          if (refErr) {
            console.error('Webhook: refund sync failed:', { refund_id: listed.id, error: refErr });
            return await finish(false, { charge_id: charge.id, refund_id: listed.id }, `refund sync: ${refErr.message}`);
          }
          results.push(res);
        }
        console.log('Webhook: refunds recorded', { pi_id: charge.payment_intent, count: results.length, refunded: charge.refunded === true });
        await markProcessed();
      }

    } else if (event.type === 'transfer.created') {
      // ── Package 3 (20260906120000): record the attempt from Stripe's side ─
      // Every payout this package creates carries metadata[attempt_id]. If the
      // edge crashed between the POST and record_payout_attempt_result, this
      // event records it (idempotent: unique stripe_transfer_id, same-id replay
      // is a no-op). Legacy transfers without an attempt id are logged only.
      const tr = event.data.object as { id: string; amount: number; destination?: string; metadata?: Record<string, string> };
      const attemptId = tr.metadata?.attempt_id ?? null;
      if (!attemptId) {
        console.log('Webhook: stripe Transfer created (no attempt id — legacy)', {
          stripe_transfer_id: tr.id, amount: tr.amount, destination: tr.destination,
        });
        await markProcessed();
      } else {
        const { data: recorded, error: recErr } = await supabase.rpc('record_payout_attempt_result', {
          p_attempt_id:         attemptId,
          p_stripe_transfer_id: tr.id,
          p_outcome:            'succeeded',
          p_error:              { source: 'webhook:transfer.created', event_id: event.id },
        });
        if (recErr) {
          // Review round 1 MINOR-5: an attempt id we do not know (a rollback
          // that destroyed payout_attempts, or a hand-made transfer carrying
          // our metadata) is not transient — retrying it for 3 days helps
          // nobody. Record it ONCE as a review row and acknowledge; only a
          // failure to write that row keeps the event retryable.
          if (/\bATTEMPT_NOT_FOUND\b/.test(recErr.message ?? '')) {
            const { error: reviewErr } = await supabase.from('webhook_retries').insert({
              payment_id:    null,
              listing_id:    null,
              rpc_name:      'transfer.created',
              error_message: `ATTEMPT_NOT_FOUND:${attemptId}:${tr.id}`,
              resolved:      false,
            });
            if (reviewErr) {
              console.error('Webhook: transfer.created — ATTEMPT_NOT_FOUND and the review row could not be written:', reviewErr);
              return await finish(false, { stripe_transfer_id: tr.id, attempt_id: attemptId }, `transfer created review row: ${reviewErr.message}`);
            }
            console.warn('Webhook: transfer.created — unknown attempt id, queued for review', {
              stripe_transfer_id: tr.id, attempt_id: attemptId, amount: tr.amount, destination: tr.destination,
            });
            return await finish(true, { stripe_transfer_id: tr.id, attempt_id: attemptId, review: 'ATTEMPT_NOT_FOUND' });
          }
          console.error('Webhook: transfer.created — record_payout_attempt_result failed:', recErr);
          return await finish(false, { stripe_transfer_id: tr.id, attempt_id: attemptId }, `transfer created record: ${recErr.message}`);
        }
        console.log('Webhook: stripe Transfer created — attempt recorded', {
          stripe_transfer_id: tr.id, attempt_id: attemptId, amount: tr.amount, destination: tr.destination, result: recorded,
        });
        await markProcessed();
      }

    } else if (event.type === 'transfer.reversed') {
      // ═══ NATIVE routing FIRST (KH §4.6, DESIGN §2.2) — legacy arm below unchanged ═══
      // A legacy transfer (metadata.transfer_id, transfer_group = the transfer
      // uuid — _shared/payouts.ts) resolves `legacy` and takes only the arm below.
      {
        const native = await runNativeTransferReversedArm();
        if (native && !native.decision.ack) return await finishDecision(native.decision, native.body, native.cause);
        if (native) {
          const reviewErr = await alertDecision(native.decision, native.body, native.cause);
          if (reviewErr) return await finish(false, { reason: native.decision.reason, ...native.body }, `native review row: ${reviewErr}`);
        }
      }
      // ── P1-02: mark our transfer 'reversed' when Stripe reverses ──────
      const tr = event.data.object as { id: string; amount_reversed?: number };
      // mark_transfer_reversed (migration 056a) carries the same
      // WHERE stripe_transfer_id = $1 AND status <> 'reversed' and bypasses
      // guard_transfer_state_columns as SECURITY DEFINER. `false` = zero rows
      // (unknown tr_ id, or already reversed) — the old no-op, not an error.
      const { data: reversed, error: revErr } = await supabase
        .rpc('mark_transfer_reversed', { p_stripe_transfer_id: tr.id });
      if (revErr) {
        console.error('Webhook: transfer.reversed mark failed:', revErr);
        return await finish(false, { stripe_transfer_id: tr.id }, `transfer reverse: ${revErr.message}`);
      } else if (!reversed) {
        console.log('Webhook: transfer.reversed no-op (unknown transfer id or already reversed)', {
          stripe_transfer_id: tr.id,
        });
        await markProcessed();
      } else {
        console.log('Webhook: transfer marked reversed', {
          stripe_transfer_id: tr.id, amount_reversed: tr.amount_reversed,
        });
        await markProcessed();
      }

    } else if (event.type === 'payout.paid') {
      // ── P1-02: log Stripe payout to seller's bank cleared ─────────────
      // Fires on the Connect account, not the platform. Use it for the
      // seller payout timeline in the admin view (DAY8 SQL pack).
      const po = event.data.object as { id: string; amount: number; arrival_date?: number };
      console.log('Webhook: stripe payout.paid', {
        payout_id: po.id, amount: po.amount, arrival_date: po.arrival_date,
        connect_account: (event as { account?: string }).account ?? null,
      });
      await markProcessed();

    } else if (event.type === 'payout.failed') {
      // ── P1-02: payout.failed — seller's bank rejected ─────────────────
      // Stripe will retry automatically; ops should reach out so the
      // seller updates their bank info via the in-app onboarding flow.
      const po = event.data.object as { id: string; amount: number; failure_message?: string; failure_code?: string };
      console.error('Webhook: stripe payout.FAILED', {
        payout_id: po.id, amount: po.amount,
        failure_code: po.failure_code, failure_message: po.failure_message,
        connect_account: (event as { account?: string }).account ?? null,
      });
      await markProcessed();

    } else if (event.type === 'account.updated') {
      // event.data.object is a Stripe Account (Connect Express seller).
      // Per Stripe docs, `details_submitted` flips true after onboarding
      // form submission; `charges_enabled` and `payouts_enabled` flip true
      // only after Stripe finishes verification. We gate listing creation
      // on the AND of all three to avoid sellers listing tickets before
      // Stripe is actually willing to accept funds for them.
      const account = event.data.object as {
        id?:                 string;
        details_submitted?:  boolean;
        charges_enabled?:    boolean;
        payouts_enabled?:    boolean;
      };
      const accountId = account.id;

      if (!accountId) {
        // Malformed but correctly signed. Retrying cannot fix it — terminal.
        console.warn('Webhook: account.updated received with no id', { event_id: event.id });
        return await finish(true, { skipped: 'account_without_id' });
      }

      const onboardingComplete =
        account.details_submitted === true &&
        account.charges_enabled   === true &&
        account.payouts_enabled   === true;

      // Persist the capability flags too, not just the derived AND. They were
      // previously written by NOTHING anywhere in the codebase, so every
      // profile sat at the column default (false / 'not_started') no matter
      // what Stripe reported — this handler already had both values in hand
      // and discarded them. stripe_onboarding_complete keeps its existing
      // semantics (the AND of all three), since listing creation gates on it.
      const { data: updatedProfiles, error: profileErr } = await supabase
        .from('profiles')
        .update({
          stripe_onboarding_complete: onboardingComplete,
          stripe_charges_enabled:     account.charges_enabled === true,
          stripe_payouts_enabled:     account.payouts_enabled === true,
          stripe_connect_status:      account.details_submitted === true
            ? 'connected'
            : 'onboarding_required',
        })
        .eq('stripe_connect_id', accountId)
        .select('id');

      // ═══════════════════════════════════════════════════════════════════
      // ORGANIZATION ARM (ruling A6/A8 · 093 §2) — authored 471c863c,
      // restored 2026-10-27.
      //
      // Runs ONLY for an account that says it is an organization account:
      // connect-onboarding stamps metadata[snatchit_plane]='organization' and
      // metadata[org_id] (selectAccountPlane). Every other account — every
      // seller account create-connect-account makes carries only
      // metadata[user_id] — skips this block and takes the individual-seller
      // handling below, byte-for-byte as before.
      //
      // `transfers_active` is derived from `capabilities.transfers`, NEVER
      // from charges_enabled/payouts_enabled. connect-onboarding requests
      // `transfers` and deliberately NOT `card_payments`, so `charges_enabled`
      // is false forever on a correct org account and a gate built on it would
      // keep every venue dark permanently.
      //
      // COEXISTENCE WITH connect-onboarding, which writes the same state through
      // the same kernel.sync_org_connect_state — no ordering is assumed:
      //   • p_observed_at is the EVENT's instant, not now(); the RPC keeps the
      //     newest observation and answers noop_replay for anything no newer
      //     (093 out-of-order guard), so a late or redelivered webhook never
      //     overwrites onboarding's fresher read, and a newer event wins.
      //   • an event that arrives before the org is bound is refused by the RPC
      //     (093 RT-A-5, "lands again after the bind") and is retried here.
      //   • both writers are idempotent; either order converges on the newest
      //     observation.
      // ═══════════════════════════════════════════════════════════════════
      const accountPlane = selectAccountPlane((account as { metadata?: Record<string, unknown> }).metadata ?? {});
      if (accountPlane.organization) {
        const transfersActive = deriveTransfersActive(account as ConnectAccountLike);

        if (profileErr) {
          // The individual-plane write did not land, so the cross-plane check
          // below cannot be made. Both writes are idempotent: retry the event.
          console.error('Webhook: account.updated profile update failed on an organization account', {
            account_id: accountId, org_id: accountPlane.orgId, error: profileErr.message,
          });
          return await finishDecision(
            { ack: false, alert: true, reason: 'account_updated_profile_update_error' },
            { stage: 'account_updated_profile', account_id: accountId, org_id: accountPlane.orgId },
            new Error(profileErr.message),
          );
        }

        let orgArm: OrgArmOutcome = 'skipped';
        let orgSyncDecision: Decision | null = null;
        let orgSyncCause: Error | null = null;

        if (!isConnectAccountRef(accountId)) {
          // The RPC refuses a malformed ref outright; refusing here keeps the
          // refusal legible and costs no round trip.
          orgArm = 'refused';
          orgSyncDecision = { ack: true, alert: true, reason: 'org_sync_malformed_account_ref' };
        } else {
          const { data: syncData, error: syncErr } = await kernelService().rpc('sync_org_connect_state', {
            p_org_id:              accountPlane.orgId,
            p_connect_account_ref: accountId,
            p_transfers_active:    transfersActive,
            p_observed_at:         observedAtIso(event.created),
            p_command_key:         buildOrgSyncCommandKey(event.id),
          });

          if (syncErr) {
            orgSyncDecision = classifyOrgSyncError(syncErr);
            orgSyncCause = new Error(syncErr.message);
            orgArm = orgSyncDecision.reason === 'org_sync_org_not_bound'
              ? 'org_not_bound'
              : (orgSyncDecision.ack ? 'refused' : 'failed');
            console.error('Webhook: sync_org_connect_state failed', {
              account_id: accountId, org_id: accountPlane.orgId, code: syncErr.code,
              reason: orgSyncDecision.reason, ack: orgSyncDecision.ack, message: syncErr.message,
            });
          } else {
            const status = (syncData as { status?: string } | null)?.status ?? 'ok';
            orgArm = status === 'noop_replay' ? 'noop_replay' : 'ok';
            console.log('Webhook: org connect state synced', {
              account_id:        accountId,
              org_id:            (syncData as { org_id?: string } | null)?.org_id ?? accountPlane.orgId,
              transfers_active:  transfersActive,
              status,
            });
          }
        }

        const matchedProfiles = updatedProfiles?.length ?? 0;
        const outcome = decideAccountUpdatedOutcome(matchedProfiles, orgArm);
        const summary = {
          account_id:           accountId,
          onboarding_complete:  onboardingComplete,
          details_submitted:    account.details_submitted ?? false,
          charges_enabled:      account.charges_enabled ?? false,
          payouts_enabled:      account.payouts_enabled ?? false,
          matched_profiles:     matchedProfiles,
          // Ruling A8's actual operand.
          transfers_active:     transfersActive,
          org_id:               accountPlane.orgId,
          org_arm:              orgArm,
          matched:              outcome.matched,
        };
        if (outcome.alert) console.error('Webhook: account.updated (organization) UNMATCHED or contested', summary);
        else console.log('Webhook: account.updated (organization) synced', summary);

        // A transient org-sync failure is worth retrying: losing a
        // capability-LOST observation leaves an organization selling tickets it
        // can no longer be paid for. Both arms are idempotent, so redelivery
        // re-runs them safely.
        if (orgSyncDecision && !orgSyncDecision.ack) {
          return await finishDecision(
            orgSyncDecision,
            { stage: 'sync_org_connect_state', account_id: accountId, org_id: accountPlane.orgId },
            orgSyncCause ?? undefined,
          );
        }

        // ACK + alert also writes the review row (finishDecision).
        return await finishDecision(
          { ack: true, alert: outcome.alert, reason: outcome.reason },
          {
            account_id: accountId, matched: outcome.matched,
            org_arm: orgArm, transfers_active: transfersActive,
          },
          orgSyncCause ?? undefined,
        );
      }

      if (profileErr) {
        // Log + ACK; Stripe will not retry account.updated and we don't
        // want to surface 5xx for transient DB errors on a non-critical
        // sync path.
        console.error('Webhook: account.updated profile update failed', {
          account_id: accountId,
          error:      profileErr.message,
        });
        await markProcessed({ error: `account.updated profile update: ${profileErr.message}` });
      } else {
        console.log('Webhook: account.updated synced', {
          account_id:           accountId,
          onboarding_complete:  onboardingComplete,
          details_submitted:    account.details_submitted ?? false,
          charges_enabled:      account.charges_enabled ?? false,
          payouts_enabled:      account.payouts_enabled ?? false,
          matched_profiles:     updatedProfiles?.length ?? 0,
        });
        await markProcessed();
      }

    } else if (event.type === 'account.application.deauthorized') {
      // A connected account disconnected this platform. Stripe delivers this
      // only on a Connect-type endpoint; `event.account` names the account and
      // data.object is the APPLICATION, so there is no account metadata and no
      // org id to read. Organization accounts are Express (connect-onboarding),
      // whose holders cannot revoke the platform themselves, so this is
      // defensive: whatever account it names, the organization bound to it must
      // stop being payable now.
      //
      // transfers_active=false goes through the same kernel.sync_org_connect_state
      // as every other writer, resolved by the account ref alone (p_org_id null).
      // EVERY outcome alerts: a deauthorized payout destination always needs an
      // operator (re-onboard or unbind), and the RPC's out-of-order guard may
      // decline to apply it (noop_replay) — that must be loud, never silent.
      const deauthAccount = (event as { account?: unknown }).account;
      if (!isConnectAccountRef(deauthAccount)) {
        return await finishDecision(
          { ack: true, alert: true, reason: 'deauth_malformed_account_ref' },
          { stage: 'account_deauthorized' },
        );
      }

      const { data: deauthData, error: deauthErr } = await kernelService().rpc('sync_org_connect_state', {
        p_org_id:              null,
        p_connect_account_ref: deauthAccount,
        p_transfers_active:    false,
        p_observed_at:         observedAtIso(event.created),
        p_command_key:         `wh_account_deauthorized:${event.id}`,
      });

      if (deauthErr) {
        // No organization holds this account (a seller account, or an account
        // never bound): nothing to write, but an operator must still see that a
        // payout destination was disconnected. classifyOrgSyncError answers a
        // quiet ACK for not_found — right for account.updated before a bind,
        // wrong here — so it is decided first.
        const notFound = deauthErr.code === 'P0002' || (deauthErr.message ?? '').toLowerCase().includes('not_found');
        const decision = notFound
          ? { ack: true, alert: true, reason: 'deauth_no_bound_organization' }
          : classifyOrgSyncError(deauthErr);
        return await finishDecision(
          { ...decision, alert: true },
          { stage: 'account_deauthorized', account_id: deauthAccount },
          new Error(deauthErr.message),
        );
      }

      const deauthStatus = (deauthData as { status?: string } | null)?.status ?? 'ok';
      return await finishDecision(
        {
          ack: true,
          alert: true,
          reason: deauthStatus === 'noop_replay' ? 'org_deauthorized_not_applied' : 'org_deauthorized',
        },
        {
          stage: 'account_deauthorized',
          account_id: deauthAccount,
          org_id: (deauthData as { org_id?: string } | null)?.org_id ?? null,
          status: deauthStatus,
        },
      );

    } else if (event.type === 'refund.created' || event.type === 'refund.updated' || event.type === 'refund.failed') {
      // ── 150: refund lifecycle ────────────────────────────────────────
      // Re-read the refund and record Stripe's CURRENT state (events can arrive
      // out of order; docs.stripe.com/webhooks). A failure here answers non-2xx
      // so Stripe redelivers.
      const evRefund = event.data.object as StripeRefund;
      if (!evRefund?.id) {
        console.warn('Webhook: refund event with no id', { event_id: event.id, event_type: event.type });
        await markProcessed();
      } else {
        const got = await fetchRefund(evRefund.id);
        if (!got.ok) {
          console.error('Webhook: refund fetch failed:', { refund_id: evRefund.id, error: got.error });
          return await finish(false, { refund_id: evRefund.id }, `refund fetch: ${got.error}`);
        }
        const r = got.refund;
        if (!r.payment_intent) {
          // A refund with no PaymentIntent is not one of our charges: acknowledged, never retried.
          console.warn('Webhook: refund without payment_intent (ack only)', { refund_id: evRefund.id });
          await markProcessed();
        } else {
          const { error: refErr } = await supabase.rpc('record_refund_state', {
            p_payment_intent_id: r.payment_intent,
            p_stripe_refund_id:  evRefund.id,
            p_status:            r.status,
            p_amount_cents:      r.amount,
            p_failure_reason:    r.failure_reason ?? null,
            p_source:            refundSource(r),
            p_observed_via:      'webhook',
          });
          if (refErr) {
            console.error('Webhook: refund state write failed:', { refund_id: evRefund.id, error: refErr });
            return await finish(false, { refund_id: evRefund.id }, `refund state: ${refErr.message}`);
          }
          console.log('Webhook: refund state recorded', { refund_id: evRefund.id, status: r.status, event_type: event.type });
          await markProcessed();
        }
      }

    } else {
      // Unknown / unhandled event type. Mark processed so ops doesn't
      // see it as a stuck-pending entry. (Stripe Dashboard configuration
      // determines which events even reach this endpoint.)
      console.log('Webhook: unhandled event type (ack only)', { event_type: event.type });
      await markProcessed();
    }

    return new Response(JSON.stringify({ received: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) },
    });
  } catch (err) {
    await captureException('stripe-webhook', err);

    // THE fix for the original bug. A throw here used to return 500 with the
    // dedup row still sitting there claimed, so Stripe's retry hit 23505 and
    // was answered 200 having done nothing. Release the lease so the retry
    // genuinely reprocesses.
    //
    // Best-effort and defensive: if this itself throws, or the throw happened
    // before the claim, we still return 500. An unreleased lease is recovered
    // by the LEASE_SECONDS timeout on a later delivery.
    try {
      const eventId = (parsedEventId ?? '') as string;
      if (eventId) {
        const supabaseFail = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
        await supabaseFail.rpc('fail_stripe_webhook_event', {
          p_event_id: eventId,
          p_error: err instanceof Error ? `${err.name}: ${err.message}` : String(err),
        });
      }
    } catch (releaseErr) {
      console.error('Webhook: could not release lease after throw:', releaseErr);
    }

    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
    );
  }
});

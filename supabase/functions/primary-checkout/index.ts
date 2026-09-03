/**
 * supabase/functions/primary-checkout/index.ts
 * ═══════════════════════════════════════════════════════════════════════════
 * VENUE-DIRECT PRIMARY CHECKOUT — mints the PaymentIntent for a native
 * primary (venue-direct) ticket order.
 *
 * Frozen contract: `docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md` §3.1.
 * Owner rulings:  `docs/phase2/PRIMARY_TICKETING_OWNER_RATIFICATION.md`
 *                 A2 (charge architecture), A5 (economics), A8 (payment gating).
 * Implementation notes + activation blockers: `docs/phase2/_impl/E2_primary_checkout.md`.
 *
 * Deploy posture: POST + OPTIONS, `verify_jwt: true`.
 *
 * ── WHAT THIS FUNCTION IS ──────────────────────────────────────────────────
 * It is a THIN, FAIL-CLOSED shell around `venue.create_primary_checkout`
 * (migration 082). The database creates the order, snapshots the price, proves
 * the holds, and proves the buyer. This function adds exactly three things the
 * database cannot do: it talks to Stripe, it applies the buyer-side service fee
 * from configuration, and it re-asserts the money gates as defence in depth.
 *
 * It does NOT reimplement pricing. It does NOT decide who may sell. It does NOT
 * confirm the payment — issuance happens when `payment_intent.succeeded` reaches
 * the extended `stripe-webhook` (§3.1's closing note, §4).
 *
 * ── RULING A2 — THE CHARGE MODEL, AND IT IS NOT NEGOTIABLE ─────────────────
 * Separate charges and transfers. The PaymentIntent is created on the SNATCH IT
 * PLATFORM Stripe account. Snatch It is the merchant of record for primary
 * sales; the venue organization is NOT.
 *
 *   NO `transfer_data[destination]`
 *   NO `on_behalf_of`
 *   NO `application_fee_amount`
 *   NO `Stripe-Account` header
 *
 * None of those four parameters appears anywhere below, and none may be added.
 * Adding any one of them converts this into a connected-account charge, which
 * A2 refused by name. Payment collection, internal obligation accounting, and
 * payout execution are three separate concepts here: a successful charge implies
 * NO venue payout. The venue's entitlement becomes a settlement fact later, via
 * `kernel.settlement_primary_lines`, never via a Stripe-side split.
 *
 * ── RULING A5 — ECONOMICS ARE BUYER-FUNDED, AND THIS FILE DOES NOT PRICE ───
 * Venue entitlement begins at the configured ticket FACE VALUE. Snatch It's
 * revenue is a *configurable buyer-side service fee* added on top, from
 * `catalog.platform_config` key `fee.buyer_service_bps`.
 *
 * THE RATE IS RESOLVED IN SQL, NOT HERE, AND THAT IS DELIBERATE. The key is
 * minted `visibility='restricted'`, and no credential this function can hold
 * can read it: a buyer is not `platform_admin`/`platform_risk`, so RLS
 * `catalog_platform_config_sel_restricted` (078:353-361) hides the row, and
 * `service_role` has no `catalog` USAGE (076:76). `venue.create_primary_checkout`
 * is SECURITY DEFINER, so its owner can — and does (093 slice 30). It returns:
 *
 *   total_minor         FACE VALUE. The venue's gross entitlement and what the
 *                       settlement seam reads. **NEVER the charge amount.**
 *   buyer_fee_minor     the buyer-funded platform revenue.
 *   charge_total_minor  the ONLY figure a PaymentIntent may be minted for.
 *
 * SO THERE IS EXACTLY ONE SOURCE OF TRUTH FOR THE BUYER'S PRICE, and it is the
 * RPC's return value. This function reads `charge_total_minor` or it refuses.
 * It must never compute, infer, round, or default a fee or a charge total — a
 * second pricing implementation is a second answer, and money with two answers
 * is a bug with a receipt.
 *
 * The unset-rate STOP is likewise the RPC's: it raises
 * `precondition_failed: service_fee_unset`, which this function surfaces as a
 * 503 ACTIVATION BLOCKER with its own code — never a silent zero, never a
 * generic 400. ("Until the owner sets a value, the platform's share on direct
 * sales is zero" describes the SETTLEMENT SEAM writing no revenue line; it is
 * not a licence for checkout to invent a 0% quote.)
 *
 * ON `idempotency_replay` THE FEE FIELDS ARE ABSENT, ON PURPOSE (R30-4). The
 * fee is derived and never stored, so re-deriving it on a replay would move the
 * price under an already-minted PaymentIntent if the owner changed the rate in
 * between. A replay means "you already have this order — reuse the quote you
 * already made", and §11 below reads that quote back from the `public.payments`
 * row and the PaymentIntent rather than reconstructing it. See
 * `recoverReplayQuote`.
 *
 * DO NOT import `buyerFeeCents` / `feeBreakdown` / `BUYER_FEE_RATE` from
 * `_shared/money.ts` here. Those encode the RESALE 10/10 model, which is a
 * different rail with a different owner ruling. Only `totalMismatch` is
 * rail-neutral, and it is the only thing imported from that module.
 *
 * ── RULING A8 — FOUR GATES, AND CHECKOUT FAILS CLOSED ─────────────────────
 * DRAFT / PUBLISHABLE need no Connect readiness. SALEABLE and PAYABLE do.
 * "Checkout must fail closed if the venue organization is not eligible for
 * primary-sale collection." The AUTHORITATIVE gate is the SQL precondition
 * inside `venue.create_primary_checkout` (093 slice 30 §3 — bound account
 * reference present AND `connect_transfers_active`, raising
 * `precondition_failed: payout_not_ready`), because that RPC is granted to
 * `authenticated` and is reachable through PostgREST in one call: an edge check
 * alone defends a door it does not stand in front of. It runs before any
 * inventory work, so an ineligible organization never gets an order row.
 *
 * THERE IS NO EDGE-SIDE ELIGIBILITY RE-CHECK, and that is deliberate (RT-A-6).
 * Any such check needs `kernel.organization`, which `service_role` cannot read
 * (USAGE without table privileges — 085:2088-2095), and the only definer
 * accessor, `kernel.get_org_connect_state`, is granted to `authenticated` and
 * explicitly never to service_role, with a body requiring `org_owner`/
 * `org_finance` — which a buyer is not. The SQL gate is not weakened by that:
 * it reads the same operands inside the same transaction as the price snapshot,
 * which is strictly stronger than an edge re-read taken moments later. See §9b.
 *
 * ── TAX — NOT MODELLED, DELIBERATELY NOT INVENTED ─────────────────────────
 * Neither rail models tax. `venue."order"` has no tax column (verified across
 * the whole table definition in 082, not inferred from one line), and no owner
 * ruling defines tax policy, nexus, rate sourcing, or remittance for the direct
 * rail. So this function collects NO tax and asserts NO tax position. The
 * response's `total` is the complete amount the card is charged under a
 * no-tax-collected policy. If tax ever becomes economically applicable (A5
 * lists taxes among the adjustments to venue entitlement), this function must
 * refuse rather than under-quote — mirroring `allInPrice`'s `tax-unmodelled`
 * refusal in `src/lib/pricing/allIn.ts:145-148`. That is an ACTIVATION BLOCKER,
 * recorded in the impl doc, not something this file may paper over.
 *
 * ── EA-1 / CLASS A — WHOSE CREDENTIALS TALK TO WHAT ───────────────────────
 * `venue.create_primary_checkout` derives EVERYTHING from `auth.uid()`: the
 * buyer, the hold ownership, the deletion-state gate. It is granted to
 * `authenticated`, NOT to `service_role`. Calling it with the service key would
 * be a Class A violation (the RPC would see a null/again-wrong subject) and is
 * the single trap the gap matrix names for this function: "copying
 * create-payment-intent verbatim produces a Class A violation — that function
 * builds its client from the service-role key."
 *
 *   caller client  (anon key + the caller's Bearer JWT) → venue RPC, catalog reads
 *   service client (service-role key)                   → rate limiter, kernel
 *                                                         probes, org eligibility,
 *                                                         public.payments write
 *
 * The service client is NEVER used to stand in for the buyer.
 *
 * ── NOTHING THE CALLER SENDS IS TRUSTED WITH AUTHORITY ────────────────────
 * No caller-controlled price. No caller-controlled organization. No
 * caller-controlled connected account. No caller-controlled buyer. The body
 * carries only SELECTORS (which session, which ticket types, which holds, how
 * many) and an OPTIONAL cross-check total that is compared and then discarded.
 * `org_id` is server-derived from the session's event; the Stripe account is
 * the platform's own and is never addressed by id.
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { captureException } from '../_shared/sentry.ts';
import { stripeFetch, stripeFetchRaw, STRIPE_MOBILE_API_VERSION } from '../_shared/stripe.ts';
// ONLY the rail-neutral guard. See the A5 block above: the fee RATES in that
// module belong to the resale rail and must not leak onto this one.
import { totalMismatch } from '../_shared/money.ts';

const SUPABASE_URL              = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY         = Deno.env.get('SUPABASE_ANON_KEY')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
// STRIPE_SECRET_KEY is read inside _shared/stripe.ts. It is never referenced
// here, so there is no path by which this file could address another account.

// ── Stage logging (spec §3.1 "Logging") ──────────────────────────────────────
// One structured line per pipeline stage so a production failure pinpoints its
// stage from the edge logs alone. NEVER log client_secret, tokens, emails, or
// any other PII. Order/PI/organization ids are opaque handles and are safe.
function logStage(stage: string, detail: Record<string, unknown> = {}) {
  console.log(JSON.stringify({ tag: 'primary-checkout-stage', stage, ...detail }));
}

// ── CORS + security headers (house style, copied shape) ─────────────────────
// React Native sends no Origin, so CORS only constrains browser callers.
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
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
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
  return { ...getCorsHeaders(req), ...getSecurityHeaders() };
}

function json(body: unknown, status: number, headers: Record<string, string>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, 'Content-Type': 'application/json' },
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// THE STRIPE METADATA CONTRACT — READ THIS BEFORE CHANGING ANY STRING BELOW
// ═══════════════════════════════════════════════════════════════════════════
//
// The extended `stripe-webhook` DISPATCHES ON THIS METADATA. Another agent is
// writing that branch against exactly these keys and values. Treat the block as
// a wire protocol: additive only, never renamed, never repurposed.
//
// KEYS SET BY THIS FUNCTION:
//
//   metadata[rail]        = "native_primary"   ← THE DISPATCH KEY. Exact,
//                                                lowercase, underscore.
//   metadata[mode]        = "native_primary"   ← IDENTICAL VALUE, corroborating.
//   metadata[order_id]    = venue."order".order_id            (uuid)
//   metadata[buyer_id]    = auth.users.id of the buyer        (uuid)
//   metadata[org_id]      = venue."order".org_id              (uuid)
//   metadata[session_id]  = catalog.event_session.session_id  (uuid)
//
// WHY BOTH `rail` AND `mode`, WHEN ONE WOULD DO:
//
//   The frozen corpus pins `rail` in two places, and only `rail`:
//     • EDGE_FUNCTION_SPEC §3.1:373 — metadata `{ rail:'native_primary', order_id,
//       buyer_id, org_id, session_id }`.
//     • EDGE_FUNCTION_SPEC §4:1206 — "New / modified branches, all keyed off
//       `metadata.rail`", with a routing table whose second column is literally
//       headed `metadata.rail` and whose values are `native_primary`,
//       `native_resale`, `native_*`.
//   `rail` is therefore the contractual dispatch key and is not negotiable.
//
//   `mode` is set to the SAME value as a belt-and-braces cross-check, because
//   it is also the `public.payments.mode` member for this rail (see below) and
//   because a webhook author reaching for the familiar legacy key must not find
//   it empty. Setting it is SAFE against the legacy resale handler: that handler
//   is a CLOSED two-branch selection on `metadata.mode` over exactly
//   {buy_now → mark_listing_sold, auction → complete_auction_payment}, and its
//   third branch is an explicit error return (stripe-webhook/index.ts:376-395,
//   documented at 074_privilege_cleanup.sql:170-177). So `mode="native_primary"`
//   reaching a legacy path fails CLOSED with `unknown_mode` — it can never take
//   a resale money path.
//
//   THE TWO MUST NEVER DISAGREE. A PI where `rail !== mode` was not written by
//   this function; treat that as tampering or corruption and fail closed.
//
// KEYS DELIBERATELY *NOT* SET:
//
//   metadata[listing_id]  — ABSENT. There is no listing on this rail, and the
//                           093 rail-pairing CHECK requires `listing_id IS NULL`
//                           on every `native_primary` payments row.
//   metadata[seller_id]   — ABSENT. There is no individual seller; the
//                           counterparty is an organization (ruling A1), and
//                           org_id already carries it. Same CHECK requires
//                           `seller_id IS NULL`.
//   any price/fee fields  — ABSENT. Money facts belong in `public.payments`
//                           (keyed by `stripe_payment_intent_id`) and on the PI
//                           itself, not in mutable metadata a reader might
//                           mistake for authority.
//
// HOW THE WEBHOOK MUST BRANCH (conservative, fail-closed, in this order):
//
//   1. rail === "native_primary"   → the NATIVE PRIMARY branch. Assert
//                                    `mode === rail` before acting on it.
//   2. rail is absent or ""        → the LEGACY RESALE path, which then does its
//                                    own existing `mode` ∈ {buy_now, auction}
//                                    selection. `create-payment-intent` sets no
//                                    `rail` key at all, and the production rows
//                                    predate this contract, so ABSENCE is the
//                                    only legitimate resale signal.
//   3. rail is any other non-empty → UNKNOWN. Do NOT fall through to resale.
//      value                        Fail closed, alert, and leave the event for
//                                    replay. A future rail (`native_resale`)
//                                    arrives as a new value here, and silently
//                                    treating it as legacy resale would run the
//                                    wrong money path.
//
// WHAT THE NATIVE BRANCH RESOLVES, AND FROM WHERE:
//
//   • the order          → `metadata.order_id`. There is NO `public.payments.order_id`
//                          column and there never will be: EDGE_FUNCTION_SPEC §9
//                          recon #1 supersedes §3.1's earlier "new order_id linkage
//                          column" phrasing — "No column is added to the frozen
//                          public.payments table — ever." The forward link lives in
//                          `kernel.payment_native`, written by finalize.
//   • the payments row   → SELECT on `public.payments.stripe_payment_intent_id`
//                          (UNIQUE), exactly as the legacy branch does. Its `id`
//                          is the `p_payment_id` finalize needs.
//   • issuance           → `venue.finalize_primary_order(p_order_id, p_payment_id,
//                          p_command_key, p_instrument_fingerprint)` — service_role
//                          only, migration 085. It re-verifies that the payment is
//                          `succeeded`, belongs to the order's buyer, and COVERS
//                          `order.total_minor` (085:1919-1934). The buyer-side
//                          service fee is added ON TOP of the face total, so
//                          `payments.total >= order.total_minor` holds by
//                          construction and that cover check passes.
//   • terminal failure   → `venue.cancel_pending_order(order_id, 'payment_failed',
//                          command_key)`. The reason code is a CLOSED SET of one
//                          (082:§20.7.9): 'payment_failed' is the ONLY accepted
//                          value, so this verb must not be reused to clean up
//                          anything that is not a payment failure.
//
// This function writes the `public.payments` row itself, pre-charge and
// `pending`, so the webhook never has to synthesize one.
// ═══════════════════════════════════════════════════════════════════════════
const RAIL_NATIVE_PRIMARY = 'native_primary';

// ── The `public.payments.mode` member for this rail — PINNED, not chosen ────
//
// `public.payments.mode` is TODAY `NOT NULL CHECK (mode IN ('buy_now','auction'))`
// (000_baseline_schema.sql:995) — "no truthful label exists for a primary sale."
// The 093 payments amendment (ruling E) widens it to
// `('buy_now','auction','native_primary')` and, in the same transaction, adds a
// RAIL-PAIRING CHECK that re-imposes the dropped NOT NULLs conditionally:
//
//   ((mode in ('buy_now','auction') and listing_id is not null and seller_id is not null)
//     or (mode = 'native_primary'   and listing_id is null     and seller_id is null))
//
// So a direct-rail row MUST be exactly `mode='native_primary'` with BOTH
// `listing_id` and `seller_id` NULL. Any other combination is rejected 23514,
// and `venue.finalize_primary_order` then has no payment row to consume. The
// INSERT below is written to that pairing precisely. The value deliberately
// equals the metadata rail token so the wire contract and the storage contract
// cannot drift apart.
const PAYMENTS_MODE_NATIVE_PRIMARY = 'native_primary';

// ── Rate limiting — fail CLOSED (spec §3.1 "Rate limit": 5 per 60s) ────────
// Three-state so the caller can be told 429 (you) vs 503 (us). The DB function
// also returns FALSE on internal error (migration 021).
type RateLimitResult = 'allowed' | 'over_limit' | 'error';

async function checkRateLimit(
  service: ReturnType<typeof createClient>,
  userId: string,
): Promise<RateLimitResult> {
  try {
    const { data, error } = await service.rpc('check_rate_limit', {
      p_user_id:        userId,
      p_action:         'primary-checkout',
      p_max:            5,
      p_window_seconds: 60,
    });
    if (error) {
      console.warn('primary-checkout: rate limit RPC error (failing closed):', error.message);
      return 'error';
    }
    return data === true ? 'allowed' : 'over_limit';
  } catch (err) {
    console.warn('primary-checkout: rate limit check threw (failing closed):', err);
    return 'error';
  }
}

// ── Stripe Customer get-or-create + ephemeral key ───────────────────────────
// Same contract as `create-payment-intent`'s helper, on the PLATFORM account.
// Kept local rather than shared because that function is owned by another agent
// this cycle and must not be edited; the two should be lifted into
// `_shared/stripe-customer.ts` in a later, separate change.
async function ensureStripeCustomerAndEphemeralKey(
  service: ReturnType<typeof createClient>,
  userId: string,
  email: string | null,
): Promise<{ customerId: string; ephemeralKeySecret: string }> {
  const { data: profile } = await service
    .from('profiles')
    .select('stripe_customer_id')
    .eq('id', userId)
    .single();

  let customerId = (profile?.stripe_customer_id as string | null) ?? null;

  // A cached id can be stale (test-mode wipe, account migration). Probe first.
  if (customerId) {
    const probe = await stripeFetchRaw(`/customers/${customerId}`);
    if (!probe.ok) {
      console.warn('primary-checkout: stripe customer not found, creating a new one');
      customerId = null;
    }
  }

  if (!customerId) {
    // The create body must be byte-stable under the fixed key: an email that
    // changed between two attempts inside Stripe's 24h idempotency window would
    // make the same key carry different parameters, which Stripe rejects. Email
    // is therefore attached in a SEPARATE, non-idempotent update.
    const created = await stripeFetch<{ id: string }>('/customers', {
      method:         'POST',
      body:           { 'metadata[user_id]': userId },
      idempotencyKey: `customer_${userId}`,
    });
    customerId = created.id;

    if (email) {
      try {
        await stripeFetch(`/customers/${customerId}`, { method: 'POST', body: { email } });
      } catch (emailErr) {
        console.warn('primary-checkout: failed to set customer email (continuing):', emailErr);
      }
    }

    const { error: updErr } = await service
      .from('profiles')
      .update({ stripe_customer_id: customerId })
      .eq('id', userId);
    if (updErr) {
      // Non-fatal: the customer exists in Stripe and the fixed idempotency key
      // above keeps a retry pointed at the same one for 24h.
      console.warn('primary-checkout: failed to persist stripe_customer_id (continuing):', updErr.message);
    }
  }

  // Unreachable by construction — both branches above assign — but asserted
  // rather than inferred, because an ephemeral key minted for `null` would be a
  // key for the wrong customer, and this is the last point at which that is
  // cheap to catch.
  if (!customerId) throw new Error('Stripe customer could not be resolved');

  // Ephemeral keys expire in ~1h, so a fresh one is minted on every request.
  // MUST use the MOBILE api version or PaymentSheet cannot decode the secret.
  const ek = await stripeFetch<{ secret?: string }>('/ephemeral_keys', {
    method:        'POST',
    body:          { customer: customerId },
    stripeVersion: STRIPE_MOBILE_API_VERSION,
  });
  if (!ek?.secret) throw new Error('Stripe ephemeral_keys returned no secret');
  return { customerId, ephemeralKeySecret: ek.secret };
}

// ── Request-body validation ────────────────────────────────────────────────
// Everything here is a SELECTOR. None of it carries authority, and none of it
// can name a price, an organization, or a Stripe account.
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type CheckoutItem = { ticket_type_id: string; quantity: number };
type ParsedBody = {
  session_id: string;
  items: CheckoutItem[];
  hold_ids: string[];
  command_key: string;
  expected_total_cents?: unknown;
};

function parseBody(body: unknown): { ok: true; value: ParsedBody } | { ok: false; error: string } {
  if (typeof body !== 'object' || body === null) return { ok: false, error: 'Body must be a JSON object' };
  const b = body as Record<string, unknown>;

  if (typeof b.session_id !== 'string' || !UUID_RE.test(b.session_id)) {
    return { ok: false, error: 'session_id must be a uuid' };
  }
  // The command key is the RPC's idempotency handle, unique per (buyer,key).
  // It is caller-chosen by design — its blast radius is the caller's own orders
  // — but it is bounded so it cannot be used as a storage channel.
  if (typeof b.command_key !== 'string' || b.command_key.trim().length === 0 || b.command_key.length > 200) {
    return { ok: false, error: 'command_key must be a non-empty string of at most 200 characters' };
  }
  if (!Array.isArray(b.items) || b.items.length === 0 || b.items.length > 50) {
    return { ok: false, error: 'items must be a non-empty array of at most 50 entries' };
  }
  const items: CheckoutItem[] = [];
  for (const raw of b.items) {
    if (typeof raw !== 'object' || raw === null) return { ok: false, error: 'each item must be an object' };
    const it = raw as Record<string, unknown>;
    if (typeof it.ticket_type_id !== 'string' || !UUID_RE.test(it.ticket_type_id)) {
      return { ok: false, error: 'items[].ticket_type_id must be a uuid' };
    }
    if (typeof it.quantity !== 'number' || !Number.isInteger(it.quantity) || it.quantity <= 0 || it.quantity > 100) {
      return { ok: false, error: 'items[].quantity must be a positive integer of at most 100' };
    }
    // NOTE the absence of any price field. A per-item price from the client
    // would be ignored anyway (the RPC snapshots `ticket_type.price_minor`
    // server-side), but refusing to even parse one keeps the contract honest.
    items.push({ ticket_type_id: it.ticket_type_id, quantity: it.quantity });
  }
  if (!Array.isArray(b.hold_ids) || b.hold_ids.length === 0 || b.hold_ids.length > 100) {
    return { ok: false, error: 'hold_ids must be a non-empty array of at most 100 uuids' };
  }
  const holdIds: string[] = [];
  for (const h of b.hold_ids) {
    if (typeof h !== 'string' || !UUID_RE.test(h)) return { ok: false, error: 'hold_ids[] must be uuids' };
    holdIds.push(h);
  }
  return {
    ok: true,
    value: {
      session_id:           b.session_id,
      items,
      hold_ids:             holdIds,
      command_key:          b.command_key,
      expected_total_cents: b.expected_total_cents,
    },
  };
}

/**
 * Faithful surfacing of a Postgres/PostgREST error from the checkout RPC.
 *
 * Spec §3.1 "Failure": `precondition_failed` → 409. The RPC's refusals are the
 * REAL business rules (session not on-sale, session terminal, holds do not
 * cover, bad item, deletion pending, identity erased, and — after 093 — the
 * organization readiness gate). They are surfaced with their own code, not
 * flattened into a generic 400, because the client has to distinguish "your
 * hold expired, reserve again" from "this event stopped selling".
 *
 * Message text from the RPC is passed through ONLY for the enumerated
 * precondition families, whose strings are authored in our own migrations. An
 * unrecognized error becomes a generic 500 so an unexpected Postgres message
 * can never be reflected to a client.
 */
function mapRpcError(
  error: { message?: string; code?: string },
): { status: number; body: Record<string, unknown>; blocker?: boolean } {
  const msg = error.message ?? '';

  if (/deletion_pending/.test(msg)) {
    return {
      status: 403,
      body: {
        error: 'Your account deletion request is pending. Withdraw it in Settings to make new purchases.',
        code:  'account_deletion_pending',
      },
    };
  }
  if (/identity_erased/.test(msg)) {
    return { status: 403, body: { error: 'This account can no longer make purchases.', code: 'identity_erased' } };
  }
  if (/not_on_sale/.test(msg)) {
    return { status: 409, body: { error: 'This event is not currently on sale.', code: 'not_on_sale' } };
  }
  if (/session_terminal/.test(msg)) {
    return { status: 409, body: { error: 'This event has ended or was cancelled.', code: 'session_terminal' } };
  }
  if (/holds do not cover/.test(msg)) {
    return {
      status: 409,
      body: { error: 'Your ticket hold expired or no longer covers this order. Please start again.', code: 'hold_invalid' },
    };
  }
  if (/^not_found|not_found:/.test(msg)) {
    return { status: 404, body: { error: 'Event or ticket type not found.', code: 'not_found' } };
  }
  if (/insufficient_privilege/.test(msg)) {
    return { status: 401, body: { error: 'Authentication required.', code: 'unauthenticated' } };
  }
  // ── A5 — the owner STOP. 093 slice 30 raises this when
  // `fee.buyer_service_bps` has no value. It is an ACTIVATION BLOCKER, not a
  // client error: nothing the buyer can do fixes it, and collapsing it into a
  // generic 400 would hide the one refusal that will be seen at activation if
  // the rate was never set. 503 + its own code + Sentry, so it is legible.
  if (/service_fee_unset/.test(msg)) {
    return {
      status: 503,
      body:   { error: 'Ticket sales are not available yet for this event.', code: 'service_fee_unset' },
      blocker: true,
    };
  }
  // An owner typo in a money rate. Also fails closed, also an activation
  // blocker, and kept DISTINCT from `unset` so the fix is unambiguous.
  if (/service_fee_out_of_range/.test(msg)) {
    return {
      status: 503,
      body:   { error: 'Ticket sales are not available yet for this event.', code: 'service_fee_out_of_range' },
      blocker: true,
    };
  }
  // A8/G2 — the organization is not ready to be paid. This is the ONLY place
  // that gate can be enforced (§9b: no edge credential can read the operands).
  if (/payout_not_ready/.test(msg)) {
    return {
      status: 409,
      body:   { error: 'Ticket sales are not available yet for this event.', code: 'org_not_eligible' },
    };
  }
  if (/precondition_failed|invalid_input/.test(msg)) {
    // Includes 093's organization readiness gate and any future precondition.
    // The RPC's own text is the most accurate thing we can say, and it is
    // authored by us, so it is surfaced rather than swallowed.
    return { status: 409, body: { error: msg.replace(/^precondition_failed:\s*/, ''), code: 'precondition_failed' } };
  }
  return { status: 500, body: { error: 'Checkout could not be completed. Please try again.' } };
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: getResponseHeaders(req) });
  }
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405, getResponseHeaders(req));
  }

  const H = getResponseHeaders(req);

  try {
    // ── 1. Authentication (C35: the actor is server-derived, never a body field)
    const authHeader = req.headers.get('authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return json({ error: 'Missing or invalid Authorization header' }, 401, H);
    }

    const service = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: { user }, error: userErr } = await service.auth.getUser(
      authHeader.replace('Bearer ', ''),
    );
    if (userErr || !user) {
      return json({ error: 'Invalid or expired token' }, 401, H);
    }
    const buyerId = user.id;
    logStage('auth', { buyer_id: buyerId });

    // ── 2. Rate limit — fail CLOSED (503 on limiter fault, 429 over limit) ──
    const rl = await checkRateLimit(service, buyerId);
    if (rl === 'error') {
      return json(
        { error: 'Service temporarily unavailable. Please try again shortly.' },
        503,
        { ...H, 'Retry-After': '30' },
      );
    }
    if (rl === 'over_limit') {
      return json({ error: 'Too many requests. Please try again later.' }, 429, { ...H, 'Retry-After': '60' });
    }

    // ── 3. Deletion-state eligibility (OR-17 F-5; dsm §3.2) ────────────────
    // A buyer with a pending deletion may not ACQUIRE. The RPC enforces this
    // too (082, F-1 + the E-23 ERASED twin) and is the hard wall; this is the
    // UX-grade courtesy refusal that fires before any Stripe work.
    //
    // DIVERGENCE FROM `create-payment-intent`, DELIBERATE: that function fails
    // OPEN on a probe error because it had to run in a pre-077 world where the
    // kernel schema did not exist. 077-092 are live in production, so a probe
    // error here is a real fault, not an expected absence — and the brief for
    // this rail is fail-closed. A probe that cannot answer is a 503.
    try {
      const kernel = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
        auth: { autoRefreshToken: false, persistSession: false },
        db:   { schema: 'kernel' },
      });
      const { data: pending, error: pendErr } = await kernel.rpc('is_deletion_pending', {
        p_identity: buyerId,
      });
      if (pendErr) {
        console.warn('primary-checkout: deletion-state probe failed (failing closed):', pendErr.message);
        return json(
          { error: 'Service temporarily unavailable. Please try again shortly.', code: 'eligibility_unverified' },
          503,
          { ...H, 'Retry-After': '30' },
        );
      }
      if (pending === true) {
        return json(
          {
            error: 'Your account deletion request is pending. Withdraw it in Settings to make new purchases.',
            code:  'account_deletion_pending',
          },
          403,
          H,
        );
      }
    } catch (probeErr) {
      console.warn('primary-checkout: deletion-state probe threw (failing closed):', probeErr);
      return json(
        { error: 'Service temporarily unavailable. Please try again shortly.', code: 'eligibility_unverified' },
        503,
        { ...H, 'Retry-After': '30' },
      );
    }

    // ── 4. Body ────────────────────────────────────────────────────────────
    let rawBody: unknown;
    try {
      rawBody = await req.json();
    } catch {
      return json({ error: 'Body must be valid JSON' }, 400, H);
    }
    const parsed = parseBody(rawBody);
    if (!parsed.ok) return json({ error: parsed.error }, 400, H);
    const { session_id, items, hold_ids, command_key, expected_total_cents } = parsed.value;

    // The caller clients. EA-1: `venue.create_primary_checkout` and the catalog
    // reads below run as the BUYER, never as service_role.
    //
    // Schema is bound at CONSTRUCTION (`db: { schema }`) rather than per-call,
    // matching every other edge function in this repo (delete-account:154-158,
    // create-payment-intent:265-267). That idiom is proven against the pinned
    // supabase-js 2.39.0; the fluent `.schema()` selector is not used anywhere
    // here and is not worth introducing on a money path.
    const venueCaller = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
      auth:   { autoRefreshToken: false, persistSession: false },
      db:     { schema: 'venue' },
    });

    // ── 5/6. THE FEE AND THE A8 GATE NOW LIVE IN THE RPC ──────────────────
    //
    // Both used to be edge-side here, and both moved into
    // `venue.create_primary_checkout` (093 slice 30). That was the right call
    // and this function must not duplicate either.
    //
    // WHY THE FEE MOVED. The rate lives in `catalog.platform_config` key
    // `fee.buyer_service_bps`, minted `visibility='restricted'`. No credential
    // this function can hold is able to read it: a buyer is not
    // `platform_admin`/`platform_risk` so RLS
    // `catalog_platform_config_sel_restricted` (078:353-361) hides the row, and
    // `service_role` has no `catalog` USAGE (076:76). The RPC is SECURITY
    // DEFINER, so its owner reads the key directly — the only credential in the
    // system that can. The fee is therefore resolved exactly once, server-side,
    // by the same transaction that snapshots the price.
    //
    // WHY THE A8 GATE MOVED. The RPC is granted to `authenticated` and is one
    // PostgREST call away, so an edge-side readiness check defended a door it
    // did not stand in front of. It now raises `payout_not_ready` itself,
    // BEFORE any inventory work and before the rate is even read.
    //
    // CONSEQUENCE FOR THIS FILE, AND IT IS THE WHOLE POINT: there is now ONE
    // source of truth for the buyer's price, and it is the RPC's return value.
    // This function must never compute, infer, or default a fee or a charge
    // total. It reads `charge_total_minor` or it refuses.
    //
    // The pre-RPC `catalog` reads that used to resolve org_id are gone too:
    // they made the whole function depend on `catalog` PostgREST exposure,
    // which would have kept it dead even once 093 applied. `org_id` is now
    // taken from the order row the RPC wrote — still server-derived, never
    // client-supplied — and the defence-in-depth eligibility check runs against
    // it just before the PaymentIntent is minted.

    // ── 7. THE ORDER — server-authoritative, created by the database ────────
    // This is the only writer of price on this rail. The RPC snapshots
    // `ticket_type.price_minor` once per item, proves the buyer's active holds
    // cover every quantity, proves the event is on_sale/live and the session is
    // not terminal, refuses oversell downstream at finalize, and dedupes on
    // UNIQUE(buyer_id, command_idempotency_key). A replay returns the SAME
    // order, so a retry cannot create a second one.
    const { data: rpcData, error: rpcErr } = await venueCaller.rpc('create_primary_checkout', {
      p_session_id:  session_id,
      p_items:       items,
      p_hold_ids:    hold_ids,
      p_command_key: command_key,
    });

    if (rpcErr) {
      logStage('rpc-refused', { code: rpcErr.code ?? null, message: rpcErr.message });
      const mapped = mapRpcError(rpcErr);
      // Activation blockers go to Sentry too: they silently stop EVERY direct
      // sale, and an operator must not have to read edge logs to find out.
      if (mapped.status >= 500 || mapped.blocker) {
        await captureException(
          'primary-checkout',
          new Error(`create_primary_checkout: ${rpcErr.message}`),
          { activation_blocker: mapped.blocker === true },
        );
      }
      return json(
        mapped.body,
        mapped.status,
        mapped.blocker ? { ...H, 'Retry-After': '300' } : H,
      );
    }

    // ── 8. The RPC result. THREE money fields, and their meanings differ. ──
    //
    //   total_minor        = FACE VALUE. The venue's gross entitlement and what
    //                        the settlement revenue seam reads. **NEVER the
    //                        charge amount.** 093 slice 30 calls folding the fee
    //                        into this column "the single most misreadable line
    //                        in this migration" — it would pay the venue the
    //                        platform's own revenue out of an append-only ledger.
    //   buyer_fee_minor    = the buyer-funded platform revenue (A5).
    //   charge_total_minor = the ONLY figure a PaymentIntent may be minted for.
    //
    // The last two are present on a SUCCESS return and ABSENT on
    // `idempotency_replay`, deliberately (R30-4): the fee is derived and never
    // stored, so re-deriving it on a replay would silently re-quote under an
    // already-minted PaymentIntent if the owner changed the rate in between.
    type CheckoutResult = {
      status?:             string;
      order_id?:           string;
      total_minor?:        number;
      currency?:           string;
      buyer_fee_minor?:    number;
      charge_total_minor?: number;
      // OWNER-OWED (E2-RT-A-6): slice 30 must add this to the SUCCESS return.
      // Needed only for `metadata[org_id]`; absent ⇒ fail closed at §9.
      org_id?:             string;
    };
    const order = rpcData as CheckoutResult | null;
    if (!order?.order_id || typeof order.total_minor !== 'number') {
      await captureException('primary-checkout', new Error('create_primary_checkout returned an unusable result'));
      return json({ error: 'Checkout could not be completed. Please try again.' }, 500, H);
    }
    const orderId   = order.order_id;
    const faceMinor = order.total_minor;              // FACE — never the charge
    const currency  = (order.currency ?? 'USD').toUpperCase();
    const isReplay  = order.status === 'idempotency_replay';
    logStage('order', {
      order_id: orderId, rpc_status: order.status ?? null, face_minor: faceMinor, replay: isReplay,
    });

    // Only USD is supported by the charge path below. A non-USD order is a
    // refusal, not an assumption — an unhandled currency would otherwise be
    // charged in the wrong denomination.
    if (currency !== 'USD') {
      await captureException('primary-checkout', new Error(`unsupported order currency ${currency}`), { order_id: orderId });
      return json({ error: 'This event cannot be checked out yet.', code: 'unsupported_currency' }, 409, H);
    }

    // ── 9. org_id — FROM THE RPC RESULT. NOT FROM A TABLE READ. ───────────
    //
    // RT-A-6. This block used to read `venue."order"` with the service client.
    // That is illegal and would have failed EVERY request, not just edge cases:
    // `service_role` holds **USAGE ONLY** on `venue` and `kernel`
    // (085:2088-2095, both marked "USAGE ONLY" in the migration itself) and
    // **no table privileges anywhere in the Phase-2 planes**. The design is that
    // the machine plane reaches these schemas exclusively through
    // `security definer` RPCs. A direct `from('order')` hits 42501 at the table.
    //
    // AND IT MUST NOT BE FIXED WITH A GRANT. `grant select on venue."order" to
    // service_role` would hand a leaked edge key the entire order table
    // including `buyer_id` — the attendee-roster surface ruling F exists to
    // close. The fix is to stop needing the read.
    //
    // WHAT THE READ-BACK ACTUALLY BOUGHT, RE-EXAMINED: `buyer_id`,
    // `event_session_id` and `total_minor` were compared against values the RPC
    // had just derived from `auth.uid()`, `p_session_id` and its own price
    // snapshot — i.e. it was checking the RPC against itself, which proves
    // nothing the RPC did not already guarantee. `status` mattered only on the
    // replay path, where §11 covers the cases that matter (paid ⇒ already_paid,
    // no live PI ⇒ quote_unavailable). So `org_id` was the ONLY field genuinely
    // needed, and it is needed for exactly one thing: `metadata[org_id]`, which
    // the frozen webhook contract requires.
    //
    // OWNER-OWED (E2-RT-A-6): slice 30 must add `org_id` to the SUCCESS return
    // of `venue.create_primary_checkout`. It is already in scope there —
    // `v_org_id` is resolved at the top of the function for the A8 gate — so
    // this is one key in an existing `jsonb_build_object`. It is NOT needed on
    // the replay returns: the replay path reuses an existing PaymentIntent and
    // mints no metadata.
    //
    // Until then this fails CLOSED. Minting a PaymentIntent with an absent or
    // guessed `org_id` would write a metadata contract the webhook cannot
    // dispatch on and would attribute money to no organization.
    const orgId = order.org_id;
    if (typeof orgId !== 'string' || !UUID_RE.test(orgId)) {
      logStage('org-id-missing', { order_id: orderId });
      await captureException(
        'primary-checkout',
        new Error('create_primary_checkout returned no org_id — slice 30 must add it to the success return (E2-RT-A-6)'),
        { order_id: orderId, activation_blocker: true },
      );
      return json(
        { error: 'Ticket sales are not available yet for this event.', code: 'org_id_unavailable' },
        503,
        { ...H, 'Retry-After': '300' },
      );
    }

    // ── 9b. RULING A8 — why there is NO edge-side eligibility check ────────
    //
    // There used to be one here, reading `kernel.organization` with the service
    // client. Same RT-A-6 defect: USAGE without table privileges ⇒ 42501 on
    // every request.
    //
    // It cannot be rewritten against a definer verb either. The only accessor
    // for this state is `kernel.get_org_connect_state` (093 slice 30 §6), and it
    // is deliberately unreachable from here in BOTH directions: it is granted to
    // `authenticated` and explicitly **never to service_role** ("the machine
    // plane has no business enumerating payout state"), and its body requires
    // `org_owner`/`org_finance` — which a BUYER, by definition, is not.
    //
    // That is fine, because the gate is not weakened by its absence. The
    // authoritative check is the `payout_not_ready` precondition INSIDE
    // `venue.create_primary_checkout`: it reads the same two operands
    // (`stripe_connect_account_ref` present AND `connect_transfers_active`), it
    // runs before any inventory work and before the rate is read, and it does so
    // in the SAME transaction as the price snapshot — strictly stronger than an
    // edge re-read taken moments later against a row that could have changed.
    // Reaching this line at all means that gate passed.
    //
    // DO NOT "restore" this check by granting the service key table access.
    // That trades a real roster exposure for a redundant assertion.

    // ── 10. Stripe Customer + ephemeral key (PaymentSheet needs both) ──────
    const customerCtx = await ensureStripeCustomerAndEphemeralKey(service, buyerId, user.email ?? null);
    logStage('stripe-customer', { order_id: orderId, customer_id: customerCtx.customerId });

    // ── 11. THE REPLAY PATH — reuse the quote; never re-derive one ─────────
    //
    // `idempotency_replay` means "this order already exists; reuse the quote you
    // already made." The RPC deliberately returns NO fee fields here, so there
    // is nothing to compute a charge from and nothing may be invented. The
    // original quote survives in exactly two places: the `public.payments` row
    // this function wrote, and the PaymentIntent it minted. Both are read; the
    // PI's `metadata.order_id` is the authoritative confirmation that the row
    // belongs to THIS order.
    if (isReplay) {
      const recovered = await recoverReplayQuote(service, orderId, faceMinor, buyerId);

      if (recovered.kind === 'error') {
        await captureException('primary-checkout', new Error(`replay recovery failed: ${recovered.detail}`), {
          order_id: orderId,
        });
        return json(
          { error: 'Service temporarily unavailable. Please try again shortly.', code: 'replay_recovery_failed' },
          503,
          { ...H, 'Retry-After': '10' },
        );
      }
      if (recovered.kind === 'paid') {
        return json({ error: 'Payment already completed for this order.', code: 'already_paid' }, 409, H);
      }
      if (recovered.kind === 'ambiguous') {
        // More than one live PaymentIntent claims this order. Never guess which
        // one the buyer is looking at.
        await captureException('primary-checkout', new Error('multiple live PaymentIntents claim one order'), {
          order_id: orderId,
        });
        return json({ error: 'Checkout could not be completed. Please contact support.', code: 'order_inconsistent' }, 500, H);
      }
      if (recovered.kind === 'none') {
        // The order exists but no usable PaymentIntent does — the original
        // attempt died between the RPC and the PI, or its PI was cancelled.
        // The quote CANNOT be reconstructed: the fee is derived, never stored,
        // and the RPC will not re-derive it for a replay. Inventing one here is
        // exactly the failure this branch exists to prevent.
        //
        // So: refuse, and tell the client to start a fresh checkout with a NEW
        // command_key, which takes the success path and gets a real quote. The
        // stranded order stays `pending` and its capacity returns via the 081
        // hold-TTL sweep. Documented as RES-1.
        logStage('replay-no-quote', { order_id: orderId });
        return json(
          {
            error: 'This checkout expired. Please start again.',
            code:  'quote_unavailable',
          },
          409,
          H,
        );
      }

      // kind === 'reusable' — the original quote, read back, not recomputed.

      // ── C16: the RPC's replay match ignores session and items ───────────
      //
      // `venue."order"` is UNIQUE on (buyer_id, command_idempotency_key) only,
      // so the same `command_key` replayed with a DIFFERENT session, or
      // different line items, returns the ORIGINAL order rather than refusing.
      // Slice 30 makes that choice deliberately and correctly: "an order that
      // already exists is a settled fact, and re-refusing it would turn a
      // harmless client retry into a phantom failure after the money decision
      // was already taken."
      //
      // WHAT IS AND IS NOT AT RISK. `buyer_id` is IN the uniqueness key, so a
      // replay can only ever return the caller's OWN earlier order — never
      // someone else's quote. The residual is narrower: a buggy client that
      // reuses one `command_key` across two checkouts gets the FIRST order's
      // quote for the SECOND checkout's intent, silently.
      //
      // SESSION is checked here, and cheaply: the PaymentIntent we minted
      // carries `metadata.session_id`, which `recoverReplayQuote` already
      // fetched. Comparing it against the request costs no extra read and turns
      // a silent wrong-quote into an explicit error. (`metadata` is data we
      // wrote ourselves on the platform account, not caller input.)
      //
      // ITEMS are NOT checked, deliberately: proving them would need
      // `venue.order_item`, which no edge credential may read (RT-A-6), and the
      // `expected_total_cents` cross-check below already catches the case that
      // matters — a client whose displayed total disagrees with the quote it is
      // about to be charged. A client that shows the right total for the wrong
      // basket is a client bug this layer cannot see and should not guess at.
      if (recovered.sessionId !== null && recovered.sessionId !== session_id) {
        logStage('replay-session-mismatch', { order_id: orderId, pi_id: recovered.piId });
        return json(
          {
            error: 'This checkout belongs to a different event. Please start again.',
            code:  'command_key_session_mismatch',
          },
          409,
          H,
        );
      }

      if (totalMismatch(expected_total_cents, recovered.total)) {
        logStage('total-mismatch', { order_id: orderId, server_total_cents: recovered.total, replay: true });
        return json(
          {
            error:              'Price changed. Please review the updated total and try again.',
            server_total_cents: recovered.total,
            code:               'total_mismatch',
          },
          409,
          H,
        );
      }
      logStage('replay-pi-reused', {
        order_id: orderId, pi_id: recovered.piId, amount: recovered.total,
      });
      return json(
        {
          order_id:                   orderId,
          clientSecret:               recovered.clientSecret,
          paymentIntentId:            recovered.piId,
          amount:                     recovered.amount,     // face, as originally quoted
          buyer_fee:                  recovered.buyerFee,   // fee, as originally quoted
          seller_fee:                 0,
          total:                      recovered.total,      // ← the all-in charge
          currency,
          customerId:                 customerCtx.customerId,
          customerEphemeralKeySecret: customerCtx.ephemeralKeySecret,
        },
        200,
        H,
      );
    }

    // ── 12. THE FRESH QUOTE — the RPC's numbers, validated, never recomputed ─
    //
    // This function does not know the fee rate and must not learn it. It reads
    // `charge_total_minor` or it refuses. The assertions below exist so a
    // missing or malformed field can NEVER reach Stripe as `undefined`/`NaN`:
    // `String(undefined)` is the string "undefined", which Stripe would reject
    // with an opaque error, and `NaN` arithmetic would silently poison the
    // amount. Both are caught here instead.
    const feeMinor   = order.buyer_fee_minor;
    const totalMinor = order.charge_total_minor;
    if (
      typeof feeMinor   !== 'number' || !Number.isSafeInteger(feeMinor)   || feeMinor < 0 ||
      typeof totalMinor !== 'number' || !Number.isSafeInteger(totalMinor) || totalMinor <= 0 ||
      totalMinor !== faceMinor + feeMinor
    ) {
      // A success return that cannot be trusted arithmetically is a contract
      // break between this function and the RPC, not a client error.
      await captureException(
        'primary-checkout',
        new Error(
          `create_primary_checkout returned an incoherent quote: face=${faceMinor} ` +
          `fee=${JSON.stringify(order.buyer_fee_minor)} charge=${JSON.stringify(order.charge_total_minor)}`,
        ),
        { order_id: orderId },
      );
      return json({ error: 'Checkout could not be completed. Please try again.', code: 'quote_incoherent' }, 500, H);
    }
    logStage('quote', { order_id: orderId, face: faceMinor, fee: feeMinor, charge: totalMinor });

    // Server authority over the displayed total. If the client claimed a figure
    // and it disagrees, refuse: the buyer would otherwise pay a number they
    // never saw. A client that claims nothing skips the check, and the server
    // charges the RPC's number either way.
    if (totalMismatch(expected_total_cents, totalMinor)) {
      logStage('total-mismatch', { order_id: orderId, server_total_cents: totalMinor });
      return json(
        {
          error:              'Price changed. Please review the updated total and try again.',
          server_total_cents: totalMinor,
          code:               'total_mismatch',
        },
        409,
        H,
      );
    }

    // ── 11. The PaymentIntent — PLATFORM ACCOUNT, RULING A2 ───────────────
    //
    // Read the four absent parameters in the header block before touching this
    // object. There is no `transfer_data`, no `on_behalf_of`, no
    // `application_fee_amount`, and `stripeFetch` sends no `Stripe-Account`
    // header. Snatch It is the merchant of record.
    //
    // Idempotency: the key is deterministic in (order_id, customer). A
    // double-tap replays the SAME PaymentIntent.
    //
    // THE CHARGE TOTAL IS DELIBERATELY *NOT* IN THE KEY, and this is a change
    // from the resale rail's shape. Two reasons, and the second is the load-
    // bearing one:
    //   • It is unnecessary. `order_id` is unique per (buyer, command_key), so
    //     a genuinely new checkout always produces a new key. The amount adds
    //     no discrimination a fresh order_id does not already provide.
    //   • It would be UNRECONSTRUCTIBLE on the replay path. The RPC returns no
    //     fee fields for `idempotency_replay`, so a key containing the charge
    //     total could never be rebuilt there — which is precisely how a second
    //     PaymentIntent gets minted for one order. Keying on order_id makes
    //     "one order, one PaymentIntent" true by construction.
    // The customer id stays in the key because it is in the BODY: a customer
    // re-created mid-window under an unchanged key would trip Stripe's
    // idempotent-parameters error and brick this order's checkout for 24h.
    const piIdempotencyKey = `pi_native_${orderId}_c${customerCtx.customerId}`;
    const piBody: Record<string, string> = {
      'amount':                             String(totalMinor),
      'currency':                           'usd',
      'automatic_payment_methods[enabled]': 'true',
      'customer':                           customerCtx.customerId,
      // 'on_session': the buyer is present; the card is saved for their next
      // checkout. Never 'off_session' — we initiate no merchant-side charges.
      'setup_future_usage':                 'on_session',
      // ── THE DISPATCH CONTRACT. See the block near the top of this file. ──
      // `rail` is the contractual dispatch key (EDGE_FUNCTION_SPEC §3.1:373,
      // §4:1206). `mode` carries the IDENTICAL value: it mirrors the
      // `public.payments.mode` member and fails the legacy resale selection
      // closed. The two must never disagree.
      'metadata[rail]':       RAIL_NATIVE_PRIMARY,
      'metadata[mode]':       RAIL_NATIVE_PRIMARY,
      'metadata[order_id]':   orderId,
      'metadata[buyer_id]':   buyerId,
      'metadata[org_id]':     orgId,
      'metadata[session_id]': session_id,
      // No metadata[listing_id]. No metadata[seller_id]. Both are NULL on the
      // payments row by the 093 rail-pairing CHECK, so neither exists to carry.
    };

    type PiResponse = { id: string; client_secret: string; status?: string; livemode?: boolean };
    let pi: PiResponse;
    try {
      pi = await stripeFetch<PiResponse>('/payment_intents', {
        method:         'POST',
        idempotencyKey: piIdempotencyKey,
        body:           piBody,
      });
      if (pi.status === 'canceled') {
        // A canceled PI can never be confirmed, and returning its client_secret
        // hard-fails PaymentSheet. One uniquely-salted retry escapes the 24h
        // idempotency replay window. (The resale rail salts with a stored
        // failed-attempt count; this rail cannot, because `public.payments`
        // carries no order linkage by ruling — so the salt is applied
        // reactively, on observing the dead replay, instead of predictively.)
        logStage('pi-replay-canceled', { order_id: orderId, pi_id: pi.id });
        pi = await stripeFetch<PiResponse>('/payment_intents', {
          method:         'POST',
          idempotencyKey: `${piIdempotencyKey}_u${crypto.randomUUID()}`,
          body:           piBody,
        });
      }
    } catch (stripeErr) {
      const detail = stripeErr instanceof Error ? stripeErr.message : String(stripeErr);
      logStage('pi-create-failed', { order_id: orderId, error: detail });
      await captureException('primary-checkout', stripeErr, { order_id: orderId, stage: 'pi-create' });
      return json({ error: 'Failed to create payment intent' }, 500, H);
    }

    if (pi.status === 'succeeded') {
      // The idempotent replay handed back an already-paid PI. The webhook owns
      // issuance from here; handing PaymentSheet a spent client_secret would
      // only produce a confusing client error.
      logStage('pi-already-succeeded', { order_id: orderId, pi_id: pi.id });
      return json({ error: 'Payment already completed for this order.', code: 'already_paid' }, 409, H);
    }
    logStage('pi-created', {
      order_id: orderId, pi_id: pi.id, pi_status: pi.status ?? null,
      livemode: pi.livemode ?? null, amount: totalMinor,
    });

    // ── 12. The `public.payments` row — the shared money-in spine ──────────
    //
    // `public.payments` is the sole money-in event for BOTH rails
    // (SCHEMA_SPEC:3677). `kernel.payment_native` LINKS an order to it at
    // finalize; it never re-charges and is not itself a payment fact.
    //
    //   amount     = face total    → what the venue is entitled to (A5)
    //   buyer_fee  = service fee   → the platform's buyer-funded revenue (A5)
    //   seller_fee = 0             → there is no individual seller on this rail
    //   total      = the charge    → and total >= order.total_minor, which is
    //                                exactly what `venue.finalize_primary_order`
    //                                re-verifies at 085:1930-1934
    //   listing_id = null          → the 093 rail-pairing CHECK REQUIRES null here
    //   seller_id  = null          → the 093 rail-pairing CHECK REQUIRES null here
    //   mode       = 'native_primary' → the 093 widened CHECK member; the pairing
    //                                CHECK ties this member to the two nulls above
    //
    // Until 093 applies, this INSERT is REJECTED BY THE DATABASE and the
    // handler below reports an activation blocker (and cancels the orphaned
    // PaymentIntent) rather than a bare 500.
    //
    // Retry safety: `stripe_payment_intent_id` is UNIQUE, and the deterministic
    // idempotency key means a retry arrives holding the SAME PaymentIntent id.
    // So a pre-existing row for this PI IS this payment — return it rather than
    // inserting a second one. That, plus the RPC's command-key dedupe, is the
    // whole no-duplicates story: one order, one PaymentIntent, one payments row.
    const { data: existingPay } = await service
      .from('payments')
      .select('id, buyer_id, status, total')
      .eq('stripe_payment_intent_id', pi.id)
      .maybeSingle();

    if (existingPay) {
      const ep = existingPay as { buyer_id: string; status: string };
      if (ep.buyer_id !== buyerId) {
        await captureException('primary-checkout', new Error('payments row for this PI belongs to another buyer'), {
          order_id: orderId, pi_id: pi.id,
        });
        return json({ error: 'Checkout could not be completed. Please try again.' }, 500, H);
      }
      if (ep.status === 'succeeded') {
        return json({ error: 'Payment already completed for this order.', code: 'already_paid' }, 409, H);
      }
      logStage('payments-row-reused', { order_id: orderId, pi_id: pi.id, status: ep.status });
    } else {
      const { error: insertErr } = await service.from('payments').insert({
        listing_id:               null,
        buyer_id:                 buyerId,
        seller_id:                null,
        amount:                   faceMinor,
        buyer_fee:                feeMinor,
        seller_fee:               0,
        total:                    totalMinor,
        stripe_payment_intent_id: pi.id,
        status:                   'pending',
        mode:                     PAYMENTS_MODE_NATIVE_PRIMARY,
        // Mode boundary (migration 045): taken from Stripe's OWN livemode field,
        // never inferred. Financial automation only acts on livemode rows.
        stripe_livemode:          pi.livemode ?? null,
      });

      if (insertErr) {
        const e = insertErr as { code?: string; message?: string; details?: string; hint?: string };
        logStage('payments-insert-failed', {
          order_id: orderId, pi_id: pi.id, code: e.code ?? null, message: e.message ?? null,
        });

        // 23505 on the UNIQUE PI id ⇒ a concurrent identical request (same
        // idempotency key ⇒ same PI) won the race. That row IS this payment.
        if (e.code === '23505') {
          const { data: winner } = await service
            .from('payments')
            .select('buyer_id, status')
            .eq('stripe_payment_intent_id', pi.id)
            .maybeSingle();
          const w = winner as { buyer_id: string; status: string } | null;
          if (w && w.buyer_id === buyerId && w.status === 'pending') {
            logStage('payments-insert-race-recovered', { order_id: orderId, pi_id: pi.id });
          } else {
            await captureException('primary-checkout', new Error('23505 on payments with no recoverable winner'), {
              order_id: orderId, pi_id: pi.id,
            });
            await cancelOrphanPi(pi.id);
            return json({ error: 'Failed to record payment. Please try again.' }, 500, H);
          }
        } else {
          // 23502 (not-null) or 23514 (check) here is the pre-093 shape wall:
          // the frozen `payments` table cannot yet store a primary-rail row.
          // Report it as the activation blocker it is, and cancel the orphan PI
          // so no authorization is left dangling against the buyer's card.
          const isShapeWall = e.code === '23502' || e.code === '23514';
          await captureException(
            'primary-checkout',
            new Error(`payments insert failed: code=${e.code ?? '?'} ${e.message ?? ''} ${e.details ?? ''}`),
            { order_id: orderId, pi_id: pi.id, activation_blocker: isShapeWall },
          );
          await cancelOrphanPi(pi.id);
          return json(
            isShapeWall
              ? { error: 'Ticket sales are not available yet for this event.', code: 'payments_shape_unmigrated' }
              : { error: 'Failed to record payment. Please try again.' },
            isShapeWall ? 503 : 500,
            isShapeWall ? { ...H, 'Retry-After': '300' } : H,
          );
        }
      } else {
        logStage('payments-insert-ok', { order_id: orderId, pi_id: pi.id });
      }
    }

    // ── 13. Response ───────────────────────────────────────────────────────
    // Shape mirrors `create-payment-intent` (spec §3.1 "Response") plus
    // `order_id` and `currency`.
    //
    // THE ONE HONEST NUMBER: `total`. Feed it to `allInPrice` as
    // `{ rail: 'direct', serverTotalMinor: total, currency, taxApplies: false }`
    // and render `formatMinor` of the result. `amount` and `buyer_fee` exist to
    // itemize that total on a receipt, never to be displayed as "the price".
    return json(
      {
        order_id:                   orderId,
        clientSecret:               pi.client_secret,
        paymentIntentId:            pi.id,
        amount:                     faceMinor,   // face value — venue entitlement
        buyer_fee:                  feeMinor,    // buyer-side service fee (A5)
        seller_fee:                 0,           // no individual seller on this rail
        total:                      totalMinor,  // ← the all-in charge
        currency,
        customerId:                 customerCtx.customerId,
        customerEphemeralKeySecret: customerCtx.ephemeralKeySecret,
      },
      200,
      H,
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : '';
    const isAuthError = /authorization|token/i.test(message);
    if (isAuthError) {
      console.warn('primary-checkout: auth error:', message);
    } else {
      await captureException('primary-checkout', err);
    }
    return json(
      { error: isAuthError ? message : 'Internal server error' },
      isAuthError ? 401 : 500,
      getResponseHeaders(req),
    );
  }
});

/**
 * Recover the quote and PaymentIntent for an order the RPC reported as an
 * `idempotency_replay`.
 *
 * WHY THIS EXISTS. `venue.create_primary_checkout` returns NO fee fields on a
 * replay — deliberately (093 slice 30, R30-4). The fee is derived from
 * `fee.buyer_service_bps` and never stored on `venue."order"`, so re-deriving it
 * would silently re-quote under an already-minted PaymentIntent if the owner had
 * changed the rate in between. A replay therefore has exactly one honest source
 * for the buyer's price: **the quote already made.**
 *
 * WHERE THAT QUOTE LIVES. In the `public.payments` row this function wrote
 * (`amount` = face, `buyer_fee`, `total` = charge) and in the PaymentIntent it
 * minted. Both are read back; nothing is recomputed.
 *
 * BOTH READS ARE GRANT-LEGAL. `public.payments` is in the `public` schema, where
 * `service_role` does hold table privileges — unlike `venue`/`kernel`/`catalog`,
 * where it holds USAGE at most (RT-A-6). Stripe is an external API. Nothing here
 * touches a Phase-2 table.
 *
 * HOW THE ROW IS FOUND, GIVEN THERE IS NO `payments.order_id`. There is no such
 * column and there never will be (EDGE_FUNCTION_SPEC §9 recon #1), and
 * `kernel.payment_native` is not written until finalize, so no order→payment
 * link exists at checkout time. The lookup is therefore two-stage:
 *
 *   1. CANDIDATES — a narrow selector on facts known at replay:
 *      (buyer_id, mode='native_primary', amount=faceMinor, non-terminal status).
 *      This is a FILTER, NOT an identification: two pending orders for the same
 *      buyer at the same face total would both match.
 *   2. CONFIRMATION — each candidate's PaymentIntent is retrieved and its
 *      `metadata.order_id` must equal this order, and `metadata.rail` must be
 *      `native_primary`. **The PI metadata is the authority**; the DB selector
 *      only narrows the search. That is what makes this exact rather than
 *      heuristic.
 *
 * Stripe's PaymentIntent *search* API was rejected for this: it is eventually
 * consistent (~a minute), and the dominant replay case is a double-tap seconds
 * apart, which search would miss — producing a spurious "no quote" exactly when
 * the buyer is most likely to be looking at the sheet.
 *
 * `sessionId` rides back out of the PI's own metadata so the caller can catch a
 * `command_key` replayed against a different session. See the C16 note in §11.
 */
type ReplayRecovery =
  | {
      kind: 'reusable'; piId: string; clientSecret: string;
      amount: number; buyerFee: number; total: number;
      sessionId: string | null;
    }
  | { kind: 'paid' }
  | { kind: 'none' }
  | { kind: 'ambiguous' }
  | { kind: 'error'; detail: string };

async function recoverReplayQuote(
  service: ReturnType<typeof createClient>,
  orderId: string,
  faceMinor: number,
  buyerId: string,
): Promise<ReplayRecovery> {
  type Row = {
    amount: number; buyer_fee: number; total: number;
    status: string; stripe_payment_intent_id: string | null;
  };

  let candidates: Row[];
  try {
    const { data, error } = await service
      .from('payments')
      .select('amount, buyer_fee, total, status, stripe_payment_intent_id')
      .eq('buyer_id', buyerId)
      .eq('mode', PAYMENTS_MODE_NATIVE_PRIMARY)
      .eq('amount', faceMinor)
      .in('status', ['pending', 'processing', 'succeeded'])
      // Bounded: this drives one Stripe GET per candidate. A buyer with more
      // than a handful of concurrent same-priced native orders is pathological.
      .limit(10);
    if (error) return { kind: 'error', detail: error.message };
    candidates = (data ?? []) as Row[];
  } catch (err) {
    return { kind: 'error', detail: err instanceof Error ? err.message : String(err) };
  }

  if (candidates.length === 0) return { kind: 'none' };

  type Confirmed = {
    row: Row; piId: string; status: string; clientSecret: string | null; sessionId: string | null;
  };
  const confirmed: Confirmed[] = [];

  for (const row of candidates) {
    if (!row.stripe_payment_intent_id) continue;
    const probe = await stripeFetchRaw(`/payment_intents/${row.stripe_payment_intent_id}`);
    if (!probe.ok) continue;   // a PI we cannot read cannot confirm anything
    const pi = probe.data as {
      id?: string; status?: string; client_secret?: string; metadata?: Record<string, string>;
    };
    // THE AUTHORITATIVE CHECK. Both must match: the order this PI was minted
    // for, and the rail that minted it.
    if (pi.metadata?.order_id !== orderId) continue;
    if (pi.metadata?.rail !== RAIL_NATIVE_PRIMARY) continue;
    if (!pi.id) continue;
    confirmed.push({
      row, piId: pi.id, status: pi.status ?? 'unknown', clientSecret: pi.client_secret ?? null,
      sessionId: pi.metadata?.session_id ?? null,
    });
  }

  if (confirmed.length === 0) return { kind: 'none' };

  // Already paid — either side saying so is enough. The webhook owns issuance
  // from here; handing back a spent client_secret would only confuse the sheet.
  if (confirmed.some((c) => c.status === 'succeeded' || c.row.status === 'succeeded')) {
    return { kind: 'paid' };
  }

  // A canceled PI can never be confirmed, and one with no client_secret is
  // useless to PaymentSheet. Neither is reusable.
  const live = confirmed.filter((c) => c.status !== 'canceled' && c.clientSecret !== null);
  if (live.length === 0) return { kind: 'none' };
  if (live.length > 1)  return { kind: 'ambiguous' };

  const only = live[0];
  return {
    kind:         'reusable',
    piId:         only.piId,
    clientSecret: only.clientSecret!,
    amount:       only.row.amount,
    buyerFee:     only.row.buyer_fee,
    total:        only.row.total,
    sessionId:    only.sessionId,
  };
}

/**
 * Cancel a PaymentIntent we created but could not record.
 *
 * Non-fatal by design: the request has already failed and the caller will
 * retry. Leaving the PI alive would strand an authorization against the buyer's
 * card and leave a chargeable object with no `payments` row behind it — the
 * webhook would then receive a `payment_intent.succeeded` it cannot reconcile.
 */
async function cancelOrphanPi(piId: string): Promise<void> {
  try {
    await stripeFetch(`/payment_intents/${piId}/cancel`, { method: 'POST' });
    logStage('orphan-pi-canceled', { pi_id: piId });
  } catch (cancelErr) {
    console.warn('primary-checkout: PI cancel after failed record:', cancelErr);
  }
}

-- =============================================================================
-- DAY 8 — P1-02 Admin SQL Pack: webhook events, disputes, transfers, risk
-- Version: 1.0
-- Usage:   Copy-paste into Supabase Dashboard → SQL Editor.
--          All queries are SELECT-only unless explicitly marked WRITE.
--          Extends DAY5_ADMIN_SQL_PACK.sql with P1-02 surfaces.
-- =============================================================================
--
-- All operations remain MANUAL. No automatic freezes, no automatic
-- reversals. Ops decides; SQL writes. Same discipline as DAY5 + PHASE_C.
--
-- ─── INDEX ──────────────────────────────────────────────────────────────────
--   A. DISPUTES MANAGEMENT       — find, inspect, search
--   B. WEBHOOK EVENT MONITORING — health, duplicates, errors
--   C. TRANSFER / PAYOUT VISIBILITY — frozen state, payout timeline
--   D. SELLER RISK VIEW          — disputes + payout health joined to risk
--   E. WRITE OPERATIONS          — explicit manual interventions
--   F. VERIFICATION CHECKLIST    — end-of-shift sanity queries
-- =============================================================================


-- =============================================================================
-- SECTION A — DISPUTES MANAGEMENT
-- =============================================================================

-- A1. All OPEN disputes, newest first. Evidence-due deadline highlighted.
--     Treat anything inside 48 h of evidence_due_by as URGENT.
SELECT d.id                AS dispute_row_id,
       d.stripe_dispute_id,
       d.stripe_charge_id,
       d.stripe_pi_id,
       d.amount,
       d.currency,
       d.reason,
       d.status,
       d.evidence_due_by,
       d.evidence_due_by - now()    AS time_to_respond,
       d.transfer_id,
       t.status                     AS transfer_status,
       t.payout_released_at,
       d.payment_id,
       p.status                     AS payment_status,
       p.buyer_id,
       p.seller_id,
       prof.display_name            AS seller_name,
       d.created_at,
       d.updated_at
  FROM public.disputes d
  LEFT JOIN public.transfers t ON t.id = d.transfer_id
  LEFT JOIN public.payments  p ON p.id = d.payment_id
  LEFT JOIN public.profiles  prof ON prof.id = p.seller_id
 WHERE d.status NOT IN ('won','lost','warning_closed','charge_refunded')
 ORDER BY d.evidence_due_by ASC NULLS LAST, d.created_at DESC;


-- A2. Lookup a dispute by Stripe dispute id.
SELECT * FROM public.disputes WHERE stripe_dispute_id = '<dispute_id>';


-- A3. All disputes affecting a specific seller.
SELECT d.stripe_dispute_id, d.status, d.reason, d.amount, d.created_at, d.evidence_due_by
  FROM public.disputes d
  JOIN public.payments  p ON p.id = d.payment_id
 WHERE p.seller_id = '<seller_user_id>'
 ORDER BY d.created_at DESC;


-- A4. Disputes summary: counts by status (last 90 days).
SELECT status,
       COUNT(*)                         AS n,
       SUM(amount) FILTER (WHERE currency = 'usd') AS total_cents_usd
  FROM public.disputes
 WHERE created_at >= now() - interval '90 days'
 GROUP BY status
 ORDER BY n DESC;


-- A5. Searchable: any dispute by partial reason text or charge id.
SELECT stripe_dispute_id, status, reason, amount, payment_id, transfer_id, created_at
  FROM public.disputes
 WHERE stripe_dispute_id ILIKE '%' || '<query>' || '%'
    OR stripe_charge_id  ILIKE '%' || '<query>' || '%'
    OR reason            ILIKE '%' || '<query>' || '%'
 ORDER BY created_at DESC
 LIMIT 50;


-- =============================================================================
-- SECTION B — WEBHOOK EVENT MONITORING
-- =============================================================================

-- B1. Health overview: counts by event_type and processed state, last 24h.
SELECT event_type,
       COUNT(*)                                    AS received,
       COUNT(*) FILTER (WHERE processed)           AS processed,
       COUNT(*) FILTER (WHERE NOT processed)       AS unprocessed,
       COUNT(*) FILTER (WHERE last_error IS NOT NULL) AS errored
  FROM public.stripe_webhook_events
 WHERE received_at >= now() - interval '24 hours'
 GROUP BY event_type
 ORDER BY received DESC;


-- B2. Unprocessed or errored events (investigate these).
SELECT event_id, event_type, received_at, processed_at, last_error
  FROM public.stripe_webhook_events
 WHERE NOT processed OR last_error IS NOT NULL
 ORDER BY received_at DESC
 LIMIT 100;


-- B3. Duplicate detection: how often Stripe re-sent the same event_id.
--     With the dedup gate, an event_id is INSERTed exactly once. If you
--     ever see duplicates here, the dedup gate is broken.
SELECT event_id, event_type, received_at
  FROM (
    SELECT event_id, event_type, received_at,
           ROW_NUMBER() OVER (PARTITION BY event_id ORDER BY received_at) AS rn
      FROM public.stripe_webhook_events
  ) ranked
 WHERE rn > 1
 ORDER BY received_at DESC;


-- B4. Filter by single event_type (e.g. inspect every dispute event).
SELECT event_id, received_at, processed, processed_at, last_error
  FROM public.stripe_webhook_events
 WHERE event_type = '<event.type>'  -- e.g. 'charge.dispute.created'
 ORDER BY received_at DESC
 LIMIT 50;


-- B5. Replay-debug: lookup ONE event and the side-effects it produced.
--     Use the event_id from Stripe Dashboard → Developers → Events.
WITH evt AS (
  SELECT * FROM public.stripe_webhook_events WHERE event_id = '<event_id>'
)
SELECT 'event' AS kind, jsonb_build_object(
  'event_type', event_type, 'received_at', received_at,
  'processed_at', processed_at, 'last_error', last_error
) AS payload FROM evt
UNION ALL
SELECT 'dispute', to_jsonb(d) FROM public.disputes d
 WHERE d.created_at >= (SELECT received_at - interval '1 minute' FROM evt)
   AND d.created_at <= (SELECT received_at + interval '5 minute'  FROM evt);


-- =============================================================================
-- SECTION C — TRANSFER / PAYOUT VISIBILITY
-- =============================================================================

-- C1. All transfers currently FROZEN by a dispute.
SELECT t.id          AS transfer_id,
       t.listing_id,
       t.seller_id,
       prof.display_name AS seller_name,
       t.status,
       t.disputed_at,
       p.stripe_payment_intent_id,
       d.stripe_dispute_id,
       d.status      AS dispute_status,
       d.evidence_due_by
  FROM public.transfers t
  JOIN public.payments  p    ON p.id = t.payment_id
  LEFT JOIN public.disputes d ON d.transfer_id = t.id
  LEFT JOIN public.profiles prof ON prof.id = t.seller_id
 WHERE t.status = 'disputed'
 ORDER BY t.disputed_at DESC NULLS LAST;


-- C2. Transfers that were REVERSED (Stripe-side reversal happened).
SELECT t.id, t.listing_id, t.seller_id, t.stripe_transfer_id, t.created_at
  FROM public.transfers t
 WHERE t.status = 'reversed'
 ORDER BY t.created_at DESC;


-- C3. Recent payout failures (sourced from webhook event log;
--     stripe.payouts live on the Connect account, not our DB).
SELECT event_id,
       received_at,
       last_error,
       processed,
       processed_at
  FROM public.stripe_webhook_events
 WHERE event_type = 'payout.failed'
   AND received_at >= now() - interval '14 days'
 ORDER BY received_at DESC;


-- C4. Per-seller payout timeline.
SELECT
  e.event_id, e.event_type, e.received_at,
  e.processed, e.last_error
  FROM public.stripe_webhook_events e
 WHERE e.event_type IN ('payout.paid','payout.failed','transfer.created','transfer.reversed')
 ORDER BY e.received_at DESC
 LIMIT 100;


-- C5. Inspect ONE transfer end-to-end (payment, dispute, status timeline).
SELECT
  t.*,
  jsonb_build_object(
    'payment_status',      p.status,
    'amount_cents',        p.amount,
    'buyer_fee_cents',     p.buyer_fee,
    'seller_fee_cents',    p.seller_fee,
    'total_cents',         p.total,
    'stripe_pi_id',        p.stripe_payment_intent_id
  ) AS payment,
  jsonb_agg(to_jsonb(d) ORDER BY d.created_at DESC)
    FILTER (WHERE d.id IS NOT NULL) AS disputes
FROM public.transfers t
JOIN public.payments  p ON p.id = t.payment_id
LEFT JOIN public.disputes d ON d.transfer_id = t.id
WHERE t.id = '<transfer_id>'
GROUP BY t.id, p.id;


-- =============================================================================
-- SECTION D — SELLER RISK VIEW (joins disputes + payout + reports + blocks)
-- =============================================================================

-- D1. Sellers with any dispute in the last 90 days.
SELECT p.seller_id,
       prof.display_name,
       COUNT(*)                                              AS n_disputes,
       COUNT(*) FILTER (WHERE d.status = 'lost')             AS n_lost,
       SUM(d.amount) FILTER (WHERE d.status = 'lost')        AS lost_cents,
       MAX(d.created_at)                                     AS last_dispute_at
  FROM public.disputes d
  JOIN public.payments  p   ON p.id = d.payment_id
  LEFT JOIN public.profiles prof ON prof.id = p.seller_id
 WHERE d.created_at >= now() - interval '90 days'
 GROUP BY p.seller_id, prof.display_name
 ORDER BY n_lost DESC, n_disputes DESC;


-- D2. Sellers with FROZEN payouts (open disputes + un-released transfers).
SELECT t.seller_id,
       prof.display_name,
       COUNT(*) AS frozen_count,
       SUM(p.amount - p.seller_fee) AS held_cents
  FROM public.transfers t
  JOIN public.payments  p ON p.id = t.payment_id
  LEFT JOIN public.profiles prof ON prof.id = t.seller_id
 WHERE t.status = 'disputed'
   AND t.payout_released_at IS NULL
 GROUP BY t.seller_id, prof.display_name
 ORDER BY held_cents DESC NULLS LAST;


-- D3. Sellers with recent payout.failed events.
SELECT (e.event_id) AS event_id,
       e.received_at,
       e.last_error
  FROM public.stripe_webhook_events e
 WHERE e.event_type = 'payout.failed'
   AND e.received_at >= now() - interval '30 days'
 ORDER BY e.received_at DESC;


-- D4. Sellers with N or more reports against them in the last 30 days.
--     Pair with public.user_blocks for a "is this user being avoided" signal.
SELECT r.target_id                              AS seller_id,
       prof.display_name,
       COUNT(*)                                  AS n_reports,
       array_agg(DISTINCT r.reason)              AS reasons,
       MAX(r.created_at)                         AS last_report_at,
       (SELECT COUNT(*) FROM public.user_blocks ub WHERE ub.blocked_id = r.target_id) AS times_blocked
  FROM public.reports r
  LEFT JOIN public.profiles prof ON prof.id = r.target_id
 WHERE r.target_type = 'user'
   AND r.created_at >= now() - interval '30 days'
 GROUP BY r.target_id, prof.display_name
HAVING COUNT(*) >= 1   -- raise threshold once you have traffic, e.g. >= 3
 ORDER BY n_reports DESC;


-- D5. Sellers with incomplete Stripe onboarding (cannot list yet).
SELECT id, display_name, stripe_connect_id, stripe_onboarding_complete, created_at
  FROM public.profiles
 WHERE stripe_connect_id IS NOT NULL
   AND stripe_onboarding_complete = false
 ORDER BY created_at DESC;


-- =============================================================================
-- SECTION E — WRITE OPERATIONS  ** REQUIRES service_role + manual review **
-- =============================================================================

-- E1. WRITE: Manually mark a dispute won/lost (after Stripe Dashboard close).
--     Normally fired by webhook charge.dispute.closed — only use this to
--     repair drift if a webhook was lost.
-- UPDATE public.disputes
--    SET status = 'lost'
--  WHERE stripe_dispute_id = '<dispute_id>';


-- E2. WRITE: Manually freeze a transfer (use when ops detects fraud before
--     Stripe fires the dispute event).
-- UPDATE public.transfers
--    SET status = 'disputed',
--        disputed_at = now()
--  WHERE id = '<transfer_id>'
--    AND status != 'disputed';


-- E3. WRITE: Replay a stuck webhook (rare). Mark the event row as
--     un-processed so a manual re-fire from Stripe Dashboard runs through.
-- UPDATE public.stripe_webhook_events
--    SET processed = false,
--        processed_at = null,
--        last_error = null,
--        retry_count = retry_count + 1
--  WHERE event_id = '<event_id>';


-- =============================================================================
-- SECTION F — VERIFICATION CHECKLIST (run at end of every ops shift)
-- =============================================================================

-- F1. No unprocessed-with-error events older than 1 hour.
SELECT COUNT(*) AS stuck_events
  FROM public.stripe_webhook_events
 WHERE last_error IS NOT NULL
   AND processed = false
   AND received_at < now() - interval '1 hour';
-- Expect: 0.


-- F2. No open disputes past their evidence_due_by.
SELECT COUNT(*) AS past_due_disputes
  FROM public.disputes
 WHERE evidence_due_by < now()
   AND status NOT IN ('won','lost','warning_closed','charge_refunded');
-- Expect: 0. Any row here = lost dispute by default.


-- F3. Sanity: every disputed transfer has a disputes row backing it.
SELECT t.id AS transfer_id
  FROM public.transfers t
  LEFT JOIN public.disputes d ON d.transfer_id = t.id
 WHERE t.status = 'disputed' AND d.id IS NULL;
-- Expect: 0 rows. Rows here = ops manually froze a transfer
--                          (E2) without recording the dispute. Fix manually.


-- F4. Sanity: no payment marked refunded but its transfer still active.
SELECT t.id AS transfer_id, p.id AS payment_id, t.status, p.status
  FROM public.transfers t
  JOIN public.payments p ON p.id = t.payment_id
 WHERE p.status = 'refunded'
   AND t.status NOT IN ('reversed','expired');
-- Expect: 0. Rows = stale state; investigate.


-- F5. Webhook event volume last 24h (sanity that traffic is flowing).
SELECT COUNT(*) FILTER (WHERE event_type LIKE 'payment_intent.%')   AS pi_events,
       COUNT(*) FILTER (WHERE event_type LIKE 'charge.dispute.%')   AS dispute_events,
       COUNT(*) FILTER (WHERE event_type LIKE 'transfer.%')         AS transfer_events,
       COUNT(*) FILTER (WHERE event_type LIKE 'payout.%')           AS payout_events,
       COUNT(*) FILTER (WHERE event_type = 'account.updated')       AS account_updated,
       COUNT(*) FILTER (WHERE event_type = 'charge.refunded')       AS refunds
  FROM public.stripe_webhook_events
 WHERE received_at >= now() - interval '24 hours';


-- =============================================================================
-- SECTION G — STRIPE CUSTOMER + SAVED CARDS (P1-03)
-- =============================================================================
-- Each buyer has at most one Stripe Customer, lazily created on first
-- checkout by create-payment-intent. setup_future_usage='on_session'
-- attaches the card to that customer post-charge so PaymentSheet can
-- show it as a saved option next time.

-- G1. Buyers with a Stripe Customer id (have completed at least 1 checkout).
SELECT id, display_name, stripe_customer_id, created_at
  FROM public.profiles
 WHERE stripe_customer_id IS NOT NULL
 ORDER BY created_at DESC;


-- G2. Lookup a profile by stripe_customer_id (forward lookup when a
--     Stripe Dashboard charge points at cus_XXX).
SELECT id, display_name, stripe_customer_id
  FROM public.profiles
 WHERE stripe_customer_id = '<cus_xxx>';


-- G3. Sanity: every payment with a customer-bound PI maps to exactly one
--     profile via stripe_customer_id. Rows here = orphan customers.
SELECT DISTINCT p.buyer_id, prof.stripe_customer_id
  FROM public.payments p
  LEFT JOIN public.profiles prof ON prof.id = p.buyer_id
 WHERE p.status = 'succeeded'
   AND prof.stripe_customer_id IS NULL
 ORDER BY p.buyer_id
 LIMIT 50;
-- Expect: 0 rows in steady state. Rows indicate a customer-create that
-- succeeded in Stripe but failed to persist to profiles — back-fill via
-- the Stripe Dashboard customer id lookup.


-- G4. Saved-card adoption: % of buyers who have a Stripe Customer.
SELECT
  COUNT(*) FILTER (WHERE stripe_customer_id IS NOT NULL) AS with_customer,
  COUNT(*) FILTER (WHERE stripe_customer_id IS NULL)     AS without_customer,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE stripe_customer_id IS NOT NULL)
    / NULLIF(COUNT(*), 0), 1
  ) AS pct_with_customer
  FROM public.profiles;


-- END OF DAY8 PACK
-- =============================================================================

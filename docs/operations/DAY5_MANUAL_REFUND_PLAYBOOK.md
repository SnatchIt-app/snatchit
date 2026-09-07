# Day 5 — Manual Refund & Manual Payout Release Playbook

**Version:** 1.0 — Private Beta
**Date:** 2026-04-01
**Tools:** Stripe Dashboard + Supabase SQL Editor

---

## PART 1 — Manual Refund Playbook (Buyer-Win)

Use this when admin rules in the buyer's favor and the buyer needs their money back.

### Prerequisites

- Transfer is in `disputed` or `expired` status
- Payment is in `succeeded` status
- `payout_released_at IS NULL` on the transfer (payout has NOT been sent to seller)

### Step 1 — Locate the Stripe PaymentIntent

Run in Supabase SQL Editor:

```sql
SELECT p.stripe_payment_intent_id, p.amount, p.service_fee, p.total, p.status,
       t.id AS transfer_id, t.status AS transfer_status, t.payout_released_at
  FROM payments p
  JOIN transfers t ON t.payment_id = p.id
 WHERE t.id = '<transfer_id>';
```

**Safety check:** Confirm `payout_released_at IS NULL`. If the payout was already released, you cannot do a simple refund — you must claw back the Connect transfer first (see Emergency section below).

Copy the `stripe_payment_intent_id` (starts with `pi_`).

### Step 2 — Refund in Stripe Dashboard

1. Go to **Stripe Dashboard** -> **Payments**
2. Search for the `pi_xxx` PaymentIntent ID
3. Click the payment -> click **Refund**
4. Select **Full refund**
5. Reason: select "Requested by customer" or "Fraudulent" as appropriate
6. Click **Refund**
7. Wait for status to show **Refunded**
8. Copy the Refund ID (starts with `re_`)

### Step 3 — Update Supabase Records

Run these in order:

```sql
-- 3a. Mark payment as refunded
UPDATE payments
   SET status      = 'refunded',
       refunded_at = now()
 WHERE stripe_payment_intent_id = 'pi_xxx'
   AND status = 'succeeded'
 RETURNING id, status, refunded_at;

-- 3b. Close out the transfer
UPDATE transfers
   SET status = 'expired'
 WHERE id = '<transfer_id>'
   AND status IN ('disputed', 'seller_sent', 'pending')
 RETURNING id, status;

-- 3c. Re-activate the listing so it can be relisted
UPDATE listings
   SET status         = 'active',
       reserved_by    = NULL,
       reserved_until = NULL,
       sold_at        = NULL
 WHERE id = '<listing_id>'
 RETURNING id, status;
```

### Step 4 — Verify the Refund

Run verification query:

```sql
SELECT p.id AS payment_id, p.status AS payment_status, p.refunded_at,
       t.id AS transfer_id, t.status AS transfer_status, t.payout_released_at
  FROM payments p
  JOIN transfers t ON t.payment_id = p.id
 WHERE t.id = '<transfer_id>';
```

**Expected result:**
- `payment_status = 'refunded'`
- `refunded_at IS NOT NULL`
- `transfer_status = 'expired'`
- `payout_released_at IS NULL`

Also confirm in Stripe Dashboard that the refund shows status `succeeded`.

---

## PART 2 — Manual Payout Release Playbook (Seller-Win)

> **Rewritten 2026-09-06 for the payout ATTEMPT PROTOCOL (migration
> `20260906120000_payout_attempts_and_refund_monotonic.sql`).** The previous
> Part 2 — a Stripe-Dashboard transfer followed by a direct `UPDATE transfers`
> — is RETIRED: the direct UPDATE has been refused since migration 0562
> (`guard_transfer_state_columns`), and a Dashboard transfer that is not
> recorded through the ledger is exactly the double-pay path the ledger exists
> to close (a later automatic attempt cannot see it and pays again once
> Stripe's 24-hour idempotency window has lapsed). Every manual payout now goes
> through the same three RPCs the edges use, so the ledger always knows which
> Stripe transfer settled which obligation.

Use this when admin rules in the seller's favor (dispute resolved seller-paid,
`dispute_resolution = 'resolved_seller_paid'`) or when the automatic payout
(confirm-and-release / the enforce-transfer-expiry sweep) did not run and the
seller must be paid now.

### Prerequisites

- Transfer `status IN ('buyer_confirmed','auto_released')`
- `disputed_at IS NULL` **or** `dispute_resolution = 'resolved_seller_paid'`
- Payment `status = 'succeeded'`, `stripe_livemode = true`, `amount_refunded_cents IS NULL OR = 0`
- `payout_released_at IS NULL` **and** `stripe_transfer_id IS NULL`
- No OPEN attempt (`payout_attempts.state IN ('claimed','requested','unknown')`)
  — if one exists, go to **Step 5 (reconcile)** first, never create a transfer
- Seller has a valid `stripe_connect_id` (starts with `acct_`) whose
  `transfers` capability is `active`

### Step 1 — Gather Required Data

```sql
SELECT t.id AS transfer_id, t.status AS transfer_status, t.disputed_at, t.dispute_resolution,
       t.payout_released_at, t.stripe_transfer_id,
       p.id AS payment_id, p.stripe_payment_intent_id, p.amount, p.seller_fee, p.total,
       p.status AS payment_status, p.stripe_livemode, p.amount_refunded_cents,
       pr.stripe_connect_id, pr.display_name AS seller_name,
       (SELECT jsonb_agg(jsonb_build_object('attempt_no', a.attempt_no, 'state', a.state,
                'stripe_transfer_id', a.stripe_transfer_id, 'idempotency_key', a.idempotency_key,
                'destination', a.destination, 'amount_cents', a.amount_cents) ORDER BY a.attempt_no)
          FROM payout_attempts a WHERE a.transfer_id = t.id) AS attempts
  FROM transfers t
  JOIN payments p  ON p.id  = t.payment_id
  JOIN profiles pr ON pr.id = t.seller_id
 WHERE t.id = '<transfer_id>';
```

**Safety checks:** every prerequisite above. The payout amount is NOT chosen
here — the claim in Step 2 freezes it as `amount - seller_fee` (the 10/10 fee
model: the platform keeps `buyer_fee + seller_fee`).

If `amount_refunded_cents > 0` the claim will refuse
(`PAYMENT_PARTIALLY_REFUNDED`): who bears a partial refund is an OWNER
decision, not an operator one. Record the decision in the incident log and
escalate; do not create a transfer by hand.

### Step 2 — Claim the attempt (freezes destination, amount, idempotency key)

```sql
SELECT * FROM public.claim_payout_attempt('<transfer_id>', 'admin:<your name>');
-- → attempt_id, attempt_no, idempotency_key, destination, amount_cents,
--   source_charge_id, payment_intent_id, needs_reconcile
```

- `needs_reconcile = true` → an earlier attempt is open: **STOP, go to Step 5.**
- Exceptions are the eligibility verdicts: `ALREADY_RELEASED`, `DISPUTED`,
  `TRANSFER_NOT_RELEASABLE`, `PAYMENT_NOT_SUCCEEDED`, `PAYMENT_NOT_LIVE`,
  `PAYMENT_PARTIALLY_REFUNDED`, `SELLER_NOT_ONBOARDED`,
  `PAYOUT_ATTEMPT_IN_PROGRESS` (another worker holds the lease — wait 10 min).
  Do not work around any of them.

The claim holds a 10-minute lease. Finish Steps 3-4 inside it; if you cannot,
the next sweep reconciles the attempt (Step 5 happens automatically).

### Step 3 — Mark requested, then create the Stripe Transfer with THAT key

```sql
SELECT public.mark_payout_requested('<attempt_id>');   -- must return true
```

If it returns `false`, the last-moment re-check failed (a dispute, a refund, a
competing payout landed since the claim): **do not create a transfer**; run
Step 5 with no transfer id to close the attempt, then start over from Step 1.

Look up the funding charge: Stripe Dashboard → Payments → `pi_xxx` → the
charge id `ch_xxx` (or `GET /v1/payment_intents/pi_xxx?expand[]=latest_charge`).

**Stripe CLI (the only supported manual path — the Dashboard cannot set an
idempotency key, a transfer_group or metadata):**

```bash
stripe transfers create \
  --idempotency-key "<idempotency_key from Step 2>" \
  --amount <amount_cents from Step 2> \
  --currency usd \
  --destination <destination from Step 2> \
  --source-transaction <ch_xxx> \
  --transfer-group "<transfer_id>" \
  -d "metadata[transfer_id]=<transfer_id>" \
  -d "metadata[payment_id]=<payment_id>" \
  -d "metadata[attempt_id]=<attempt_id>" \
  -d "metadata[attempt_no]=<attempt_no>" \
  -d "metadata[source]=manual-playbook"
```

Copy the Transfer ID (`tr_xxx`). If the command fails with a definite 4xx
(no transfer created) → Step 4b. If it times out / 5xx (a transfer MAY exist)
→ Step 5.

### Step 4 — Record the result (the ONLY write to transfers)

```sql
-- 4a. success
SELECT public.record_payout_attempt_result('<attempt_id>', 'tr_xxx', 'succeeded',
         '{"actor":"admin:<your name>","source":"manual-playbook"}'::jsonb);
-- → state 'succeeded' (or 'reversal_required' + a PAID_DURING_DISPUTE /
--   DUPLICATE_TRANSFER manual_review decision if the world changed under you —
--   the money movement is recorded either way)

-- 4b. Stripe definitely did NOT create a transfer
SELECT public.record_payout_attempt_result('<attempt_id>', NULL, 'failed_not_created',
         '{"actor":"admin:<your name>","error":"<stripe error>"}'::jsonb);
```

Never `UPDATE transfers` directly and never call `record_transfer_payout`
for an attempt-protocol payout (that legacy RPC is for pre-ledger edges only).

### Step 5 — Reconcile an open attempt (lost response, expired lease)

```sql
SELECT a.id, a.attempt_no, a.state, a.idempotency_key, a.destination, a.amount_cents, a.requested_at
  FROM payout_attempts a WHERE a.transfer_id = '<transfer_id>' AND a.state IN ('claimed','requested','unknown');
```

Then ask Stripe what exists for this obligation (both forms — legacy edges
set only the metadata):

```bash
stripe transfers list --transfer-group "<transfer_id>" --limit 100
stripe transfers list --destination <acct_xxx> --limit 100   # match metadata.transfer_id = <transfer_id>
```

```sql
-- found  → records tr_ on the transfer, attempt succeeded
SELECT public.reconcile_payout_attempt('<attempt_id>', 'tr_xxx');
-- not found (you checked BOTH listings) → attempt failed; a new claim may open
SELECT public.reconcile_payout_attempt('<attempt_id>', NULL);
```

### Step 6 — Verify

```sql
SELECT t.id, t.status, t.payout_released_at, t.stripe_transfer_id, p.status AS payment_status,
       (SELECT state FROM payout_attempts a WHERE a.transfer_id = t.id ORDER BY attempt_no DESC LIMIT 1) AS last_attempt_state,
       (SELECT count(*) FROM payout_decisions d WHERE d.transfer_id = t.id AND d.decision = 'manual_review') AS open_reviews
  FROM transfers t JOIN payments p ON p.id = t.payment_id
 WHERE t.id = '<transfer_id>';
```

**Expected:** `payout_released_at IS NOT NULL`, `stripe_transfer_id = 'tr_xxx'`,
`last_attempt_state = 'succeeded'`, `open_reviews = 0`. Confirm in Stripe:
Connect → Transfers → `tr_xxx` → `paid`. `account_deletion_blockers(<seller>)`
should no longer list this transfer.

---

## EMERGENCY — Refund After Payout Already Released

If `payout_released_at IS NOT NULL` but the buyer must be refunded:

1. **Reverse the Stripe Transfer first** (Stripe Dashboard → Connect →
   Transfers → `tr_xxx` → Reverse transfer). The `transfer.reversed` webhook
   records it (`mark_transfer_reversed`); if webhooks are down:
   `SELECT public.mark_transfer_reversed('tr_xxx');`
2. **Then refund the PaymentIntent** (Part 1, Step 2). The `charge.refunded`
   webhook ledgers it through `record_payment_refund`, which — because the
   transfer was paid — files a `REFUNDED_AFTER_PAYOUT` manual_review decision
   automatically. If webhooks are down:
   `SELECT public.record_payment_refund('pi_xxx', 're_xxx', NULL, <THIS refund object's amount_cents — per refund, never the cumulative total>, 'admin');`
3. **Do NOT** `UPDATE transfers` / `UPDATE payments` directly: the 0562 and
   `guard_payment_transitions` guards refuse it, and `refunded` is terminal.
4. Close the review once the reversal is confirmed in Stripe: insert a
   `release`-superseding decision is NOT the tool here — the transfer's
   `reversed` status clears the `open_manual_review` blocker on its own.

Document the incident in the log.

---

## Quick Reference — Status Transitions

| Scenario | Transfer Status | Payment Status | Payout |
|----------|----------------|----------------|--------|
| Buyer-win refund | `expired` | `refunded` | NULL |
| Seller-win payout | `buyer_confirmed` | `succeeded` | `tr_xxx` |
| Emergency reversal | `expired` | `refunded` | cleared |

---

STEP COMPLETE — WAITING FOR NEXT RUN

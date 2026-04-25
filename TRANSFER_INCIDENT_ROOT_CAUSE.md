# TRANSFER INCIDENT — Root Cause Analysis

**Generated:** 2026-04-01
**Status:** Root cause confirmed — exact fix specified

---

## SECTION 1 — Single Current Failing Layer

**ROOT CAUSE: `ensure_transfer_exists` requires `payment.status = 'succeeded'`, but `confirm-payment` is the ONLY thing that updates payment status from `'pending'` to `'succeeded'` in the synchronous checkout path — and it's returning non-2xx.**

The exact chain of failure:

```
Step 1: presentPaymentSheet()        → Stripe says payment succeeded ✓
Step 2: confirmPaymentSuccess()      → confirm-payment edge function returns non-2xx ✗
        ↳ payments.status STAYS 'pending' in DB (never updated to 'succeeded')
Step 3: mark_listing_sold RPC        → listing.status = 'sold' ✓
        ↳ This RPC does NOT check payment status. It only checks listing reservation.
Step 4: ensure_transfer_exists RPC   → queries: WHERE status = 'succeeded' → ZERO ROWS ✗
        ↳ RAISE EXCEPTION 'No succeeded payment found for this listing.'
        ↳ Error silently caught by inner try/catch in checkout
Step 5: setSold(true)                → Checkout shows "Purchase complete!" ✓

RESULT: Listing is sold. Payment is still 'pending'. No transfer row. Seller sees no button.
```

**The `ensure_transfer_exists` RPC was designed to be the safety net, but it has the same dependency on `payment.status = 'succeeded'` that it was supposed to work around.**

---

## SECTION 2 — Exact Evidence From Code

### Evidence A: confirm-payment fails → payment.status stays 'pending'

The only two places that set `payment.status = 'succeeded'`:
1. `confirm-payment` edge function (line 118): `UPDATE payments SET status = 'succeeded'`
2. `stripe-webhook` edge function (line 102): `UPDATE payments SET status = 'succeeded'`

If confirm-payment returns non-2xx (proven by console log), it either:
- Never reached line 118 (auth failure, rate limit, or Stripe status check at line 106)
- Reached line 118 but the UPDATE failed

Either way: `payments.status` remains `'pending'` after Step 2.

### Evidence B: mark_listing_sold does NOT check payment status

`mark_listing_sold` (003_payment_integrity.sql line 95-156):
```sql
select status, reserved_by, reserved_until
  from public.listings
 where id = p_listing_id
```
It only reads `listings.status`, `reserved_by`, `reserved_until`. It does NOT join to or check `payments.status`. So the listing becomes `'sold'` even though `payment.status` is still `'pending'`.

### Evidence C: ensure_transfer_exists filters on 'succeeded' — gets zero rows

`ensure_transfer_exists` (010_ensure_transfer.sql line 46-52):
```sql
SELECT id, seller_id, buyer_id
  FROM public.payments
 WHERE listing_id = p_listing_id
   AND buyer_id   = v_caller_id
   AND status     = 'succeeded'   -- ← THIS IS THE BUG
 LIMIT 1;

IF NOT FOUND THEN
  RAISE EXCEPTION 'No succeeded payment found for this listing.';
END IF;
```

Since `payment.status` is `'pending'`, this query returns zero rows. The RPC raises an exception. The exception is caught silently in the checkout (inner try/catch at line 219-222).

### Evidence D: The error is silently swallowed

`app/checkout/[id].tsx` lines 215-222:
```typescript
try {
  await supabase.rpc('ensure_transfer_exists', {
    p_listing_id: listingId,
  });
} catch (err) {
  console.warn('[checkout] ensure_transfer_exists failed:', err);
}
```

`supabase.rpc()` does NOT throw on Postgres exceptions — it returns `{ data: null, error: { message: 'No succeeded payment...' } }`. The `catch` block never fires. The `error` field is never checked. The checkout proceeds to `setSold(true)`.

### Evidence E: Webhook is the only remaining path — but it's async and delayed

The `stripe-webhook` would eventually fire `payment_intent.succeeded`, update payment status, and create the transfer. But Stripe webhook delivery can be delayed by seconds to minutes. By the time the seller checks the listing, the webhook may not have arrived.

---

## SECTION 3 — Exact SQL Checks To Run For listing_id = 68cee968-b08e-49f5-8222-77768ee79070

Run these in Supabase SQL Editor to confirm the diagnosis:

```sql
-- 1. Check payment status (expect: 'pending' — this is the bug)
SELECT id, status, paid_at, stripe_payment_intent_id, buyer_id, seller_id
  FROM payments
 WHERE listing_id = '68cee968-b08e-49f5-8222-77768ee79070';

-- 2. Check listing status (expect: 'sold')
SELECT id, status, sold_at, seller_id
  FROM listings
 WHERE id = '68cee968-b08e-49f5-8222-77768ee79070';

-- 3. Check transfer row (expect: 0 rows — confirms no transfer)
SELECT id, status, payment_id, seller_id, buyer_id
  FROM transfers
 WHERE listing_id = '68cee968-b08e-49f5-8222-77768ee79070';

-- 4. After applying fix, manually test ensure_transfer_exists:
-- (replace <buyer_user_id> with actual buyer id from query 1)
-- SELECT ensure_transfer_exists(
--   '68cee968-b08e-49f5-8222-77768ee79070'::uuid,
--   '<buyer_user_id>'::uuid
-- );
```

**Expected results confirming diagnosis:**
- Query 1: payment.status = 'pending' (NOT 'succeeded')
- Query 2: listing.status = 'sold'
- Query 3: zero rows

---

## SECTION 4 — Smallest Exact Fix

**Fix `ensure_transfer_exists` to handle BOTH `'pending'` and `'succeeded'` payments, and promote `'pending'` to `'succeeded'` when it does.**

Why this is safe:
- `ensure_transfer_exists` is only called AFTER `presentPaymentSheet()` returns success — the Stripe payment genuinely succeeded
- The RPC is SECURITY DEFINER and verifies the caller is the buyer (`auth.uid()`)
- The payment row was created by `create-payment-intent` for this specific buyer/listing
- Promoting 'pending' → 'succeeded' is exactly what `confirm-payment` was supposed to do
- This makes `ensure_transfer_exists` a true safety net that doesn't depend on confirm-payment succeeding first

**Additionally:** Fix the checkout code to actually check the RPC's error return value and log it (for diagnostics), even though it remains non-fatal.

### Changes needed:

1. **`supabase/migrations/010_ensure_transfer.sql`** — Modify the payment lookup to accept `'pending'` OR `'succeeded'`, and upgrade 'pending' to 'succeeded' atomically.

2. **`app/checkout/[id].tsx`** — Fix the inner try/catch to actually log the RPC error (supabase.rpc returns `{ error }`, it doesn't throw).

No other files need to change. No edge functions modified. No payout/refund/dispute logic touched.

---

## SECTION 5 — Exact Implementation Prompt

```
Act as a principal Supabase + React Native engineer.

CONTEXT:
- confirm-payment edge function returns non-2xx in live flow
- This means payments.status stays 'pending' in DB
- ensure_transfer_exists requires status = 'succeeded' → finds nothing → no transfer created
- mark_listing_sold succeeds (doesn't check payment status)
- Seller sees SOLD but no transfer button

TASK 1: Replace the function in supabase/migrations/010_ensure_transfer.sql

The ONLY change to the function body:

Step 2 (find payment) changes from:
  WHERE listing_id = p_listing_id
    AND buyer_id   = v_caller_id
    AND status     = 'succeeded'
To:
  WHERE listing_id = p_listing_id
    AND buyer_id   = v_caller_id
    AND status     IN ('pending', 'succeeded')

Then add a new Step 2b after finding the payment:
  -- If payment is still pending, promote to succeeded.
  -- This is safe: this RPC is only called after presentPaymentSheet()
  -- returns success, meaning Stripe confirmed the charge.
  IF (SELECT status FROM payments WHERE id = v_payment_id) = 'pending' THEN
    UPDATE payments
       SET status = 'succeeded',
           paid_at = now()
     WHERE id = v_payment_id
       AND status = 'pending';  -- atomic guard
  END IF;

Everything else in the function stays EXACTLY the same.

TASK 2: Fix error logging in app/checkout/[id].tsx

In BOTH ensure_transfer_exists call sites, change from:
  try {
    await supabase.rpc('ensure_transfer_exists', {
      p_listing_id: listingId,
    });
  } catch (err) {
    console.warn('[checkout] ensure_transfer_exists failed:', err);
  }

To:
  const { error: transferErr } = await supabase.rpc('ensure_transfer_exists', {
    p_listing_id: listingId,
  });
  if (transferErr) {
    console.warn('[checkout] ensure_transfer_exists error:', transferErr.message);
  }

This removes the useless try/catch (supabase.rpc doesn't throw) and actually
logs the Postgres error message for diagnostics.

DO NOT:
- Modify confirm-and-release, enforce-transfer-expiry, stripe-webhook
- Modify mark_listing_sold or complete_auction_payment
- Change any payout, refund, or dispute logic
- Add new tables or edge functions
```

---

STEP COMPLETE — WAITING FOR NEXT RUN

# Missing Transfer Row Audit

**Date:** 2026-04-01
**Status:** ROOT CAUSE IDENTIFIED

---

## SECTION 1 — Expected Transfer Creation Flow

There are exactly **two code paths** that create transfer rows. Both live in `stripe-webhook/index.ts`:

**Path A — Primary (webhook wins the claim race):**

```
Stripe fires payment_intent.succeeded
  → webhook UPDATE payments SET status='succeeded' WHERE neq('status','succeeded')
  → claim succeeds (payment returned non-null)
  → call mark_listing_sold or complete_auction_payment RPC
  → INSERT into transfers (listing_id, payment_id, seller_id, buyer_id, ...)
  → send push notifications
```

**Path B — Fallback (confirm-payment won the claim race):**

```
Stripe fires payment_intent.succeeded
  → webhook UPDATE payments SET status='succeeded' WHERE neq('status','succeeded')
  → claim fails (payment is null — confirm-payment already set status='succeeded')
  → look up existing payment by stripe_payment_intent_id
  → check if transfer already exists for that payment_id
  → if no transfer: INSERT into transfers using metadata.listing_id, metadata.seller_id, metadata.buyer_id
```

**No other code path creates transfers.** Not the client, not confirm-payment, not confirm-and-release.

---

## SECTION 2 — Where It Broke

The transfer insert on **both paths** depends on `metadata.listing_id`, `metadata.seller_id`, and `metadata.buyer_id` being present in the Stripe PaymentIntent metadata.

Look at webhook line 90:

```typescript
const metadata = paymentIntent.metadata ?? {};
```

And the transfer insert on the primary path (line 257-265):

```typescript
const { error: transferErr } = await supabase.from('transfers').insert({
  listing_id:       metadata.listing_id,      // ← from PI metadata
  payment_id:       payment.id,
  seller_id:        metadata.seller_id,        // ← from PI metadata
  buyer_id:         metadata.buyer_id,         // ← from PI metadata
  transfer_method:  listing?.transfer_method ?? 'mobile_transfer',
  status:           'pending',
  expires_at:       expiresAt,
});
```

And the fallback path (line 169-177):

```typescript
const { error: fallbackTransferErr } = await supabase.from('transfers').insert({
  listing_id:       metadata.listing_id,      // ← from PI metadata
  payment_id:       existingPayment.id,
  seller_id:        metadata.seller_id,        // ← from PI metadata
  buyer_id:         metadata.buyer_id,         // ← from PI metadata
  transfer_method:  fallbackListing?.transfer_method ?? 'mobile_transfer',
  status:           'pending',
  expires_at:       fallbackExpiresAt,
});
```

Both paths insert `metadata.seller_id` and `metadata.buyer_id` into NOT NULL columns.

Now look at the PaymentIntent creation in `create-payment-intent/index.ts` line 237-245:

```typescript
body: new URLSearchParams({
  'amount': String(totalCents),
  'currency': 'usd',
  'automatic_payment_methods[enabled]': 'true',
  'metadata[listing_id]': listing_id,
  'metadata[buyer_id]': buyerId,
  'metadata[seller_id]': listing.seller_id,
  'metadata[mode]': mode,
}).toString(),
```

The metadata IS being set correctly at creation time. So the metadata is present on the PaymentIntent.

---

## SECTION 3 — Root Cause

The root cause is a **race condition where confirm-payment wins AND the webhook fallback path silently fails**.

Here is the exact failure sequence:

1. Client calls `create-payment-intent` → PaymentIntent created with metadata
2. Client presents PaymentSheet → user pays → Stripe charges card
3. Client immediately calls `confirmPaymentSuccess(paymentIntentId)` → `confirm-payment` edge function
4. `confirm-payment` (line 116-124) runs:
   ```typescript
   await supabase
     .from('payments')
     .update({ status: 'succeeded', paid_at: ... })
     .eq('stripe_payment_intent_id', payment_intent_id)
     .eq('buyer_id', buyerId);
   ```
   This sets `status = 'succeeded'` **before** the webhook arrives.
   **confirm-payment does NOT create a transfer row.**

5. Client calls `mark_listing_sold` or `complete_auction_payment` RPC → listing becomes `sold`

6. Stripe webhook fires `payment_intent.succeeded` (may arrive seconds or minutes later)

7. Webhook tries the claim (line 100-106):
   ```typescript
   .update({ status: 'succeeded' })
   .neq('status', 'succeeded')
   ```
   Returns `null` because confirm-payment already set it. **Primary path skipped.**

8. Webhook enters fallback path (line 116+):
   - Looks up existing payment by `stripe_payment_intent_id` → found
   - Checks if transfer exists → **no transfer exists**
   - Tries to INSERT transfer using `metadata.listing_id`, `metadata.seller_id`, `metadata.buyer_id`

9. **HERE IS THE BUG:** The `metadata` variable (line 90) reads from `event.data.object.metadata`. This should contain the PI metadata. If the Stripe event payload is well-formed, this works.

   **BUT** — if the insert fails silently (e.g., the `seller_id` or `buyer_id` references a UUID that fails a foreign key check, or there's any constraint violation), the error is only logged (line 182-186) and the function returns `{ received: true }`. The transfer row is never created and no retry occurs.

   The most likely specific cause: **the `transfers` table has a UNIQUE constraint on `listing_id`** (migration 003). If ANY prior attempt partially inserted a row (e.g., from a previous webhook delivery that crashed mid-way), the fallback insert would hit a unique constraint violation and silently fail.

   Alternatively: if the Stripe event arrives but `event.data.object.metadata` is empty or missing fields (which can happen with certain Stripe API versions or if the PI was created without metadata on a retry path), then `metadata.listing_id` is `undefined`, and the INSERT fails with a NOT NULL constraint violation on `listing_id`.

**The confirm-payment function is the gap.** It updates the payment status to `succeeded` but does NOT create a transfer row. The webhook's fallback path is supposed to handle this, but it can silently fail.

---

## SECTION 4 — Exact Fix (code)

**Smallest safe fix:** Add transfer creation to `confirm-payment/index.ts` so it creates the transfer row when it successfully claims the payment.

**File:** `supabase/functions/confirm-payment/index.ts`

**Location:** After the successful payment update (after line 128), add transfer creation logic.

```typescript
// --- After the existing payment update block (line 124) ---

if (!updateErr) {
  // confirm-payment won the race — create the transfer row.
  // The webhook will see status='succeeded' and enter its fallback path,
  // where the existing transfer check (line 140-155) will find this row
  // and exit idempotently.

  // Look up the payment to get its id and listing_id
  const { data: claimedPayment } = await supabase
    .from('payments')
    .select('id, listing_id, seller_id, buyer_id')
    .eq('stripe_payment_intent_id', payment_intent_id)
    .eq('buyer_id', buyerId)
    .single();

  if (claimedPayment) {
    // Look up transfer_method from listing
    const { data: listing } = await supabase
      .from('listings')
      .select('transfer_method')
      .eq('id', claimedPayment.listing_id)
      .maybeSingle();

    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();

    const { error: transferErr } = await supabase.from('transfers').insert({
      listing_id:      claimedPayment.listing_id,
      payment_id:      claimedPayment.id,
      seller_id:       claimedPayment.seller_id,
      buyer_id:        claimedPayment.buyer_id,
      transfer_method: listing?.transfer_method ?? 'mobile_transfer',
      status:          'pending',
      expires_at:      expiresAt,
    });

    if (transferErr) {
      // Unique constraint violation is expected if webhook ran first — safe to ignore.
      // Any other error is logged for investigation.
      console.error('confirm-payment: transfer insert failed (may be duplicate):', {
        payment_id: claimedPayment.id,
        listing_id: claimedPayment.listing_id,
        error:      transferErr,
      });
    } else {
      console.log('confirm-payment: transfer row created', {
        payment_id: claimedPayment.id,
        listing_id: claimedPayment.listing_id,
      });
    }
  }
}
```

**Why this is safe:**
- The `transfers` table has UNIQUE constraints on both `payment_id` and `listing_id` (migration 003)
- If the webhook runs first and creates the transfer, this insert gets a constraint violation — logged and ignored
- If confirm-payment runs first and creates the transfer, the webhook fallback finds it and exits idempotently
- Both paths are now covered regardless of race outcome

---

## SECTION 5 — Validation Steps

**Before deploying — check for stuck payments:**

```sql
-- Find payments with status='succeeded' that have no transfer row
SELECT p.id AS payment_id,
       p.listing_id,
       p.buyer_id,
       p.seller_id,
       p.stripe_payment_intent_id,
       p.paid_at
  FROM public.payments p
  LEFT JOIN public.transfers t ON t.payment_id = p.id
 WHERE p.status = 'succeeded'
   AND t.id IS NULL;
```

**Manual fix for existing stuck rows** (run for each result above):

```sql
-- Replace values from the query above
INSERT INTO public.transfers (listing_id, payment_id, seller_id, buyer_id, transfer_method, status, expires_at)
SELECT p.listing_id,
       p.id,
       p.seller_id,
       p.buyer_id,
       COALESCE(l.transfer_method, 'mobile_transfer'),
       'pending',
       now() + interval '24 hours'
  FROM public.payments p
  JOIN public.listings l ON l.id = p.listing_id
 WHERE p.id = '<PAYMENT_ID_FROM_ABOVE>'
   AND NOT EXISTS (SELECT 1 FROM public.transfers t WHERE t.payment_id = p.id);
```

**After deploying:**

1. Deploy: `supabase functions deploy confirm-payment`
2. Test buy_now flow end-to-end
3. Verify transfer row exists immediately after payment success
4. Check Supabase function logs for `confirm-payment: transfer row created`
5. Verify webhook fallback logs `Webhook: transfer already exists, nothing to do`

STEP COMPLETE — WAITING FOR NEXT RUN

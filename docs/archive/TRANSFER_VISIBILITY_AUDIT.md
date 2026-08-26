# TRANSFER VISIBILITY AUDIT — Real-Flow Chain Analysis

**Generated:** 2026-04-01
**Status:** Root cause identified — fix specified

---

## SECTION 1 — Single Current Failing Layer

**THE FAILING LAYER: There is no guaranteed synchronous transfer creation in the client checkout flow.**

The transfer row is supposed to be created by two independent systems, BOTH of which are unreliable:

1. **`confirm-payment` edge function** — Called by the client BEFORE `mark_listing_sold`. Creates the transfer as a best-effort side effect. But if the function is not redeployed with the latest code, or returns a non-2xx (Stripe status check at line 106), or any internal step errors, the transfer insert is silently skipped. The client does not throw on failure (by design — line 84-87 in `payments.ts`).

2. **`stripe-webhook`** — Fires asynchronously from Stripe. Creates the transfer in either the primary path (lines 257-265) or the fallback path (lines 169-177). But webhook delivery timing is non-deterministic — can be instant or delayed by seconds/minutes. And the fallback path depends on PaymentIntent `metadata` fields (`listing_id`, `seller_id`, `buyer_id`) which are set during `create-payment-intent`.

**The gap:** After checkout completes, the client calls `mark_listing_sold` which sets `listing.status = 'sold'`. But at that moment, the transfer row may not exist yet (confirm-payment failed silently AND webhook hasn't arrived). The seller's UI then queries for the transfer and finds nothing.

**The seller's retry mechanism** (3 attempts × 2s = 6 second window) at `ListingDetailScreen.tsx:402-437` is insufficient if:
- confirm-payment failed
- Webhook delivery is delayed beyond 6 seconds
- The seller navigates to the listing AFTER the retry window has passed (in which case `fetchData` runs only once with no retry)

---

## SECTION 2 — Exact Evidence From Code

### Evidence A: No transfer creation on the critical path

**Checkout flow (`app/checkout/[id].tsx` lines 167-221):**
```
Step 1: presentPaymentSheet() → payment succeeds on Stripe
Step 2: confirmPaymentSuccess(paymentIntentId) → BEST-EFFORT, NON-THROWING
Step 3: mark_listing_sold RPC → listing.status = 'sold'
Step 4: setSold(true) → checkout shows success screen
```

**NO step between mark_listing_sold and setSold(true) ensures a transfer row exists.**
The transfer creation is delegated to side systems (edge function + webhook), neither of which is guaranteed.

### Evidence B: confirm-payment silently swallows all errors

**`src/lib/payments.ts` lines 76-87:**
```typescript
const { error: fnError } = await supabase.functions.invoke('confirm-payment', { ... });
if (fnError) {
  console.error('[payments] confirm-payment failed:', fnError.message);
  // Don't throw — payment already went through, this is just bookkeeping
}
```

If the edge function returns 400, 500, or times out, the client proceeds silently.

### Evidence C: confirm-payment gates transfer on payment UPDATE success

**`confirm-payment/index.ts` line 139:**
```typescript
if (!updateErr) {
  try {
    // ... transfer creation
  } catch (transferCreateErr) {
    console.error('confirm-payment: transfer creation threw:', transferCreateErr);
  }
}
```

If the payment UPDATE at line 116-124 returns an error (any DB issue), the entire transfer creation block is skipped.

### Evidence D: Seller UI has limited retry window

**`ListingDetailScreen.tsx` lines 402-437:**
```typescript
useEffect(() => {
  if (listing?.status !== 'sold' || !listing?.id || transferId) return;
  // ... 3 retries × 2s = 6 second window
}, [listing?.status, listing?.id, transferId]);
```

This effect fires ONCE when `listing.status` transitions to `'sold'`. If the transfer row doesn't exist within 6 seconds, the seller sees SOLD but no "Mark as Sent" button — with no way to retry (no pull-to-refresh on transfer query).

### Evidence E: useFocusEffect does NOT retry transfer on subsequent visits

**`ListingDetailScreen.tsx` lines 385-390:**
```typescript
useFocusEffect(
  useCallback(() => {
    if (!initialLoadDone.current) return;
    fetchData(true);
  }, [id]),
);
```

`fetchData(true)` DOES query the transfer if listing.status === 'sold'. So subsequent visits WILL find the transfer IF it was eventually created by the webhook. But the webhook could still be pending.

### Evidence F: The sold-state retry has a guard that blocks re-execution

**Line 403:**
```typescript
if (listing?.status !== 'sold' || !listing?.id || transferId) return;
```

The `transferId` check means: once we found a transfer (even null), don't retry. But actually — `transferId` starts as null and is only set when a transfer is found. So if all 3 retries find nothing, `transferId` remains null. But the effect won't fire again because `listing?.status` and `listing?.id` haven't changed.

This means: if the 3 retries fail, the seller is stuck until they navigate away and back.

---

## SECTION 3 — Exact Fix Needed

**Create a new `ensure_transfer_exists` RPC** that the checkout screen calls AFTER `mark_listing_sold` succeeds. This puts transfer creation on the synchronous critical path, guaranteed by the client.

Why this is the smallest correct fix:
- Does NOT modify `mark_listing_sold`, `confirm-payment`, or `stripe-webhook`
- Does NOT change payout logic
- Idempotent — UNIQUE constraints prevent duplicates
- Runs as the BUYER (who just completed payment) using service-level trust
- The webhook and confirm-payment become pure redundancy (belt-and-suspenders)

Additionally: increase the seller-side retry from 3×2s to 5×2s for extra tolerance, and add a "Refresh" mechanism on the seller's screen if the transfer still hasn't appeared.

---

## SECTION 4 — Exact Files To Modify

### File 1: `supabase/migrations/010_ensure_transfer.sql` (NEW)

Create the `ensure_transfer_exists` RPC:
- Input: `p_listing_id uuid`, `p_user_id uuid DEFAULT NULL`
- Logic:
  1. Identify caller via `coalesce(auth.uid(), p_user_id)`
  2. Look up the payment for this listing WHERE `buyer_id = caller` AND `status = 'succeeded'`
  3. If no payment found, raise exception
  4. Check if transfer already exists for this payment_id → if yes, return its id (idempotent)
  5. Look up listing.transfer_method
  6. INSERT transfer row with `expires_at = now() + 24h`
  7. Return new transfer id
- Safety: UNIQUE constraints on `transfers.payment_id` and `transfers.listing_id` prevent duplicates even in race conditions

### File 2: `app/checkout/[id].tsx`

After `mark_listing_sold` / `complete_auction_payment` succeeds:
- Call `supabase.rpc('ensure_transfer_exists', { p_listing_id: listingId })`
- Log but don't throw on error (the webhook is still a backup)

### File 3: `src/screens/ListingDetailScreen.tsx`

- Increase retry window from 3×2s to 5×2s (line 408)
- Add a "Tap to refresh" on the transfer section when `isSold && isSeller && !transferStatus`

---

## SECTION 5 — Exact Implementation Prompt

```
Act as a principal Supabase + React Native engineer.

CONTEXT:
- SnatchIt marketplace checkout flow: payment → mark_listing_sold → seller sees "Mark as Sent"
- Transfer rows are currently created by confirm-payment edge function (best-effort) and stripe-webhook (async)
- Neither is reliable enough for the synchronous checkout flow
- The seller sees SOLD but no transfer button because the transfer row doesn't exist yet
- Days 1-4 payout/refund/dispute/expiry logic must be preserved exactly

TASK 1: Create migration supabase/migrations/010_ensure_transfer.sql

CREATE OR REPLACE FUNCTION public.ensure_transfer_exists(
  p_listing_id uuid,
  p_user_id    uuid DEFAULT NULL
)
RETURNS uuid  -- returns transfer id
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_payment_id uuid;
  v_seller_id uuid;
  v_buyer_id uuid;
  v_transfer_method text;
  v_existing_transfer_id uuid;
  v_new_transfer_id uuid;
BEGIN
  v_caller_id := coalesce(auth.uid(), p_user_id);
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.';
  END IF;

  -- Look up the succeeded payment for this listing by this buyer
  SELECT id, seller_id, buyer_id
    INTO v_payment_id, v_seller_id, v_buyer_id
    FROM public.payments
   WHERE listing_id = p_listing_id
     AND buyer_id = v_caller_id
     AND status = 'succeeded'
   LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No succeeded payment found for this listing.';
  END IF;

  -- Idempotency: if transfer already exists, return its id
  SELECT id INTO v_existing_transfer_id
    FROM public.transfers
   WHERE payment_id = v_payment_id;

  IF FOUND THEN
    RETURN v_existing_transfer_id;
  END IF;

  -- Look up transfer method from listing
  SELECT transfer_method INTO v_transfer_method
    FROM public.listings
   WHERE id = p_listing_id;

  -- Create the transfer row
  INSERT INTO public.transfers (
    listing_id, payment_id, seller_id, buyer_id,
    transfer_method, status, expires_at
  ) VALUES (
    p_listing_id, v_payment_id, v_seller_id, v_buyer_id,
    coalesce(v_transfer_method, 'mobile_transfer'),
    'pending',
    now() + interval '24 hours'
  )
  ON CONFLICT (payment_id) DO NOTHING  -- race condition guard
  RETURNING id INTO v_new_transfer_id;

  -- If ON CONFLICT hit, fetch the existing row
  IF v_new_transfer_id IS NULL THEN
    SELECT id INTO v_new_transfer_id
      FROM public.transfers
     WHERE payment_id = v_payment_id;
  END IF;

  RETURN v_new_transfer_id;
END;
$$;

TASK 2: Update app/checkout/[id].tsx

In BOTH handleConfirmPurchase() and handleAuctionPayment(), AFTER the
mark_listing_sold / complete_auction_payment RPC call (whether it succeeds
or returns "already sold"), add:

  // Ensure transfer row exists (critical for seller visibility)
  try {
    await supabase.rpc('ensure_transfer_exists', {
      p_listing_id: listingId,
    });
  } catch (err) {
    console.warn('[checkout] ensure_transfer_exists failed:', err);
    // Non-fatal — webhook will create it as backup
  }

Place this BEFORE confirmedRef.current = true and setSold(true).

TASK 3: Update src/screens/ListingDetailScreen.tsx

Change the retry loop at line 408 from:
  for (let attempt = 0; attempt < 3 && !cancelled; attempt++) {
to:
  for (let attempt = 0; attempt < 5 && !cancelled; attempt++) {

This extends the retry window from 6s to 10s.

Also: when isSold && isSeller && transferStatus is null (after loading), show a
tappable "Refresh" hint so the seller can manually re-fetch.

DO NOT:
- Modify confirm-and-release, enforce-transfer-expiry, or stripe-webhook
- Modify mark_listing_sold or complete_auction_payment RPCs
- Change any payout, refund, or dispute logic
- Add new tables

VERIFY AFTER:
1. Create a new listing
2. Buy it from a test buyer account
3. Immediately check seller's listing detail → "Mark as Sent" button should appear
4. The transfer row should exist in the transfers table
5. Day 1-4 flows (confirm payout, expiry refund, auto-release, dispute) all still work
```

---

## SUMMARY

| Layer | Current State | Fix |
|-------|---------------|-----|
| confirm-payment edge function | Creates transfer as best-effort side effect | Keep as-is (redundancy) |
| stripe-webhook | Creates transfer async | Keep as-is (redundancy) |
| Checkout client flow | NO guaranteed transfer creation | **Add `ensure_transfer_exists` RPC call** |
| Seller UI retry | 3×2s = 6s window, no manual refresh | **Extend to 5×2s + add refresh hint** |
| mark_listing_sold RPC | No changes needed | No changes |
| Payout/refund/dispute | No changes needed | No changes |

**Root cause:** Transfer creation is not on the synchronous critical path. It's delegated to two async/best-effort systems, creating a reliability gap.

**Fix:** One new RPC + two small client changes. ~60 lines SQL + ~20 lines TypeScript.

STEP COMPLETE — WAITING FOR NEXT RUN

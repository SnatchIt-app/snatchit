# TRANSFER VISIBILITY FIX — Implementation Report

**Generated:** 2026-04-01
**Status:** All code changes applied — ready for deploy

---

## SECTION 1 — Exact Files Changed

| File | Action | Lines Changed |
|------|--------|---------------|
| `supabase/migrations/010_ensure_transfer.sql` | **CREATED** | 96 lines (new RPC) |
| `app/checkout/[id].tsx` | **MODIFIED** | +20 lines (two ensure_transfer_exists calls) |
| `src/screens/ListingDetailScreen.tsx` | **MODIFIED** | +20 lines (retry 3→5, refresh hint JSX + styles) |

**Files NOT modified (preserved exactly):**
- `supabase/functions/confirm-and-release/index.ts`
- `supabase/functions/enforce-transfer-expiry/index.ts`
- `supabase/functions/stripe-webhook/index.ts`
- `supabase/functions/confirm-payment/index.ts`
- `supabase/migrations/001-009` (all prior migrations)
- All RPC functions (mark_listing_sold, complete_auction_payment, confirm_transfer_received, mark_transfer_sent, buyer_dispute_transfer, enforce_transfer_expiry, enforce_auto_release)

---

## SECTION 2 — Exact Code Changes Made

### Change 1: `supabase/migrations/010_ensure_transfer.sql`

New function `public.ensure_transfer_exists(p_listing_id uuid, p_user_id uuid DEFAULT NULL) RETURNS uuid`:

1. Identifies caller via `coalesce(auth.uid(), p_user_id)`
2. Finds the succeeded payment for this listing by this buyer
3. If transfer already exists for that payment_id → returns existing transfer id (idempotent)
4. Reads `listing.transfer_method` from the listing
5. INSERTs transfer row with `ON CONFLICT (payment_id) DO NOTHING`
6. If ON CONFLICT fired → fetches and returns the existing transfer id
7. Returns the new or existing transfer uuid

### Change 2: `app/checkout/[id].tsx`

**In `handleConfirmPurchase()` (Buy Now path):**
Added after `mark_listing_sold` RPC, before `confirmedRef.current = true`:
```typescript
try {
  await supabase.rpc('ensure_transfer_exists', { p_listing_id: listingId });
} catch (err) {
  console.warn('[checkout] ensure_transfer_exists failed:', err);
}
```

**In `handleAuctionPayment()` (Auction path):**
Added after `complete_auction_payment` RPC, before `confirmedRef.current = true`:
```typescript
try {
  await supabase.rpc('ensure_transfer_exists', { p_listing_id: listingId });
} catch (err) {
  console.warn('[checkout] ensure_transfer_exists failed:', err);
}
```

Both calls are non-fatal. If they fail, the webhook and confirm-payment edge function remain as backup.

### Change 3: `src/screens/ListingDetailScreen.tsx`

**Retry increase (line 408):**
```
- for (let attempt = 0; attempt < 3 && !cancelled; attempt++)
+ for (let attempt = 0; attempt < 5 && !cancelled; attempt++)
```

**Refresh hint JSX (before transfer action buttons):**
```jsx
{isSold && isSeller && !transferStatus && !loading && (
  <TouchableOpacity style={s.refreshHint} onPress={() => fetchData(true)} activeOpacity={0.7}>
    <Text style={s.refreshHintText}>Transfer loading… tap to refresh</Text>
  </TouchableOpacity>
)}
```

**Refresh hint styles:**
```typescript
refreshHint: {
  paddingHorizontal: spacing.lg,
  paddingVertical: spacing.sm,
  alignItems: 'center',
  borderBottomWidth: 1,
  borderBottomColor: colors.border,
},
refreshHintText: {
  color: colors.textMuted,
  fontSize: fontSize.xs,
  fontWeight: '600',
},
```

---

## SECTION 3 — Deploy / Run Steps

### Step 1: Run the SQL migration

Open the Supabase SQL Editor and paste the full contents of `supabase/migrations/010_ensure_transfer.sql`. Execute it. The function uses `CREATE OR REPLACE` so it is safe to run multiple times.

### Step 2: Rebuild and deploy the app

The client changes are in `app/checkout/[id].tsx` and `src/screens/ListingDetailScreen.tsx`. These require a new app build:

```bash
npx expo start --clear    # for dev
# or
eas build --platform ios   # for production
```

### Step 3: No edge function redeployment needed

No edge functions were modified. The existing confirm-payment and stripe-webhook continue to work as redundancy.

---

## SECTION 4 — Verification Steps

### Test 1: Buy Now flow — transfer auto-creation

1. Create a new listing from Seller account
2. From Buyer account, buy the listing (Buy Now)
3. Complete payment in Stripe PaymentSheet
4. After "Purchase complete!" appears, check Supabase:
   - `SELECT * FROM transfers WHERE listing_id = '<listing-id>'`
   - **Expected:** One row with `status = 'pending'`
5. Open the listing from the Seller account
   - **Expected:** "Mark as Sent" button appears immediately (no manual refresh needed)

### Test 2: Auction flow — transfer auto-creation

1. Create an auction listing from Seller account
2. Win the auction from Buyer account
3. Complete payment
4. Verify transfer row exists and seller sees "Mark as Sent" button

### Test 3: Idempotency — no duplicate transfers

1. Complete a purchase
2. Check that only ONE transfer row exists (even though confirm-payment, webhook, AND ensure_transfer_exists all attempted to create it)
   - `SELECT count(*) FROM transfers WHERE listing_id = '<listing-id>'`
   - **Expected:** Exactly 1

### Test 4: Seller refresh hint

1. Temporarily disable the `ensure_transfer_exists` call (comment it out)
2. Complete a purchase
3. Open the listing from Seller account before the webhook fires
4. **Expected:** "Transfer loading… tap to refresh" hint appears
5. Tap it → transfer button should appear after refresh

### Test 5: Day 1–4 regression check

1. **Day 1 (Buyer confirm → payout):** Mark as Sent → Confirm Received → verify payout
2. **Day 2 (Seller ghost → expiry + refund):** Let a transfer expire → verify refund
3. **Day 3 (Buyer ghost → auto-release):** Mark as Sent → wait 72h (or adjust timer) → verify auto-release
4. **Day 4 (Dispute):** Mark as Sent → Report Issue → verify transfer frozen

All four should work unchanged since no existing RPCs or edge functions were modified.

---

STEP COMPLETE — WAITING FOR NEXT RUN

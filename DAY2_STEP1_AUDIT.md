# Day 2 — Step 1: Buyer Confirmation Path Audit

**Date:** 2026-03-30
**Status:** COMPLETE

---

## Confirmation RPC

- **File:** `supabase/migrations/002_transfers.sql` (lines 184–232)
- **Function:** `public.confirm_transfer_received(p_transfer_id uuid, p_user_id uuid)`
- **Returns:** `void`
- **Language:** PL/pgSQL, `SECURITY DEFINER`

### What it does

1. Resolves caller identity via `COALESCE(auth.uid(), p_user_id)`
2. Locks the transfer row with `SELECT ... FOR UPDATE`
3. Validates transfer exists
4. Validates caller is the `buyer_id`
5. Guards state machine: only allows transition from `seller_sent`
6. Updates: `status = 'buyer_confirmed'`, `buyer_confirmed_at = now()`

### State machine transition

```
seller_sent → buyer_confirmed
```

No other transitions are permitted by this function.

---

## Client Call Site

- **File:** `src/screens/ListingDetailScreen.tsx` (lines 745–756)
- **Function:** `handleConfirmReceived()`
- **Call:** `supabase.rpc('confirm_transfer_received', { p_transfer_id: transferId, p_user_id: user.id })`

### Client behavior after success

- Sets local state: `setTransferStatus('buyer_confirmed')`
- Shows alert: "Transfer complete. Enjoy the event!"
- **No payout trigger exists on the client side**

---

## Payout Status (Confirmed)

- **No `stripe.transfers.create()` is called anywhere** after buyer confirmation
- The `stripe-webhook/index.ts` (lines 201–213) explicitly defers payout with the comment:
  > "The release-payout function (to be built) will call stripe.transfers.create() at that time."
- **No `release-payout` edge function exists yet** — confirmed by directory listing
- No `stripe_transfer_id` or `payout_released_at` column exists on the `transfers` table

---

## Transfer Table Schema (relevant columns)

| Column | Type | Notes |
|---|---|---|
| `id` | uuid (PK) | |
| `listing_id` | uuid (FK) | |
| `payment_id` | uuid (FK) | |
| `seller_id` | uuid (FK) | |
| `buyer_id` | uuid (FK) | |
| `status` | text | pending / seller_sent / buyer_confirmed / disputed / expired |
| `buyer_confirmed_at` | timestamptz | Set by `confirm_transfer_received` |

---

## Seller Connect Account

- `profiles.stripe_connect_id` column exists (added in 002_transfers.sql)
- Used to route Stripe payouts to sellers

---

## Key Finding

The **exact hook point for payout release** is inside `confirm_transfer_received()` — after the `UPDATE` succeeds, or as a separate function triggered after the status becomes `buyer_confirmed`. Currently, the function returns void and does nothing after the update.

---

STEP COMPLETE — WAITING FOR NEXT RUN

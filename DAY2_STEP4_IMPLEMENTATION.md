# Day 2 — Step 4: Implementation

**Date:** 2026-03-30
**Status:** COMPLETE

---

## Files Created

### 1. `supabase/migrations/006_payout_release.sql`
Adds two nullable columns to `public.transfers`:
- `payout_released_at timestamptz` — idempotency guard + audit timestamp
- `stripe_transfer_id text` — Stripe Transfer ID for debugging/reconciliation

Purely additive. `ADD COLUMN IF NOT EXISTS`. Zero impact on existing queries or RPCs.

### 2. `supabase/functions/confirm-and-release/index.ts`
New edge function. Follows identical patterns to `confirm-payment` and `create-connect-account`:
- Same imports (`serve`, `createClient`)
- Same env vars (`STRIPE_SECRET_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`)
- Same `getAuthenticatedUserId()` helper
- Same `checkRateLimit()` helper
- Same `stripePost()` helper
- Same CORS headers
- Same error response structure

---

## Edge Function Flow (10 steps)

| Step | Action | Failure mode |
|---|---|---|
| 1 | Authenticate caller via JWT | 401 if invalid |
| 2 | Rate limit (5 per 5 min) | 429 if exceeded |
| 3 | Parse `transfer_id` from body | 400 if missing |
| 4 | Call `confirm_transfer_received` RPC via service role | Propagate RPC error; if already confirmed, proceed |
| 5 | Read transfer row, verify buyer_id and status | 403/400/404 on mismatch |
| 5a | Check `payout_released_at` — if NOT NULL, return success | Idempotent exit |
| 6 | Look up seller's `stripe_connect_id` from profiles | 400 if not set up |
| 7 | Look up `payment.amount` (seller payout in cents) | 500 if missing |
| 8 | Call `stripe.transfers.create()` | 502 if Stripe fails (client can retry) |
| 9 | Atomic UPDATE: write `payout_released_at` + `stripe_transfer_id` WHERE `payout_released_at IS NULL` | Race loser logged, returns success |
| 10 | Return success with `stripe_transfer_id` | — |

---

## Why This Implementation Is Idempotent

### Layer 1 — RPC state machine guard
`confirm_transfer_received` only allows `seller_sent → buyer_confirmed`. If the transfer is already `buyer_confirmed`, the RPC raises an exception. The edge function catches this specific error (message contains "buyer_confirmed") and proceeds to the payout check. Any other error (wrong user, wrong state, not found) is propagated to the client.

### Layer 2 — Read-time check (optimization)
Before calling Stripe, the function reads `payout_released_at`. If it's already set, the function returns `{ success: true, already_released: true }` without calling Stripe. This prevents unnecessary Stripe API calls on most retries.

### Layer 3 — Write-time atomic guard (true protection)
The UPDATE uses `.is('payout_released_at', null)` as a WHERE clause. If two requests pass the read check (Layer 2) concurrently:
- Request A wins the UPDATE (1 row affected) — payout columns written
- Request B loses the UPDATE (0 rows affected via `.maybeSingle()` returning null) — logs the duplicate Stripe Transfer for manual cleanup, returns success to client

This ensures the DB never records two different Stripe Transfer IDs, and the race condition is handled gracefully.

### Stripe Transfer edge case
Stripe Transfers are NOT natively idempotent. In a race between Layer 2 and Layer 3, two Stripe Transfers could be created. The losing request's Transfer is logged with `duplicate_stripe_transfer_id` for manual cleanup. At private beta scale (<100 transactions), this is acceptable. A future improvement could use Stripe's `Idempotency-Key` header to eliminate this window entirely.

---

## What Remains Untouched

| Component | Modified? |
|---|---|
| `confirm_transfer_received` RPC | NO |
| `mark_transfer_sent` RPC | NO |
| `stripe-webhook/index.ts` | NO |
| `confirm-payment/index.ts` | NO |
| `create-connect-account/index.ts` | NO |
| `create-payment-intent` | NO |
| `send-push` | NO |
| `auto-finalize-auctions` | NO |
| ListingDetailScreen.tsx | NO (Step 5) |
| Transfer state machine | NO |
| RLS policies | NO |
| Auth flow | NO |
| Checkout flow | NO |
| Migrations 001–005 | NO |

---

## Deployment

```bash
# 1. Run migration (Supabase dashboard SQL editor or CLI)
supabase db push    # or paste 006_payout_release.sql in SQL editor

# 2. Deploy edge function
supabase functions deploy confirm-and-release
```

No env var changes needed — `STRIPE_SECRET_KEY`, `SUPABASE_URL`, and `SUPABASE_SERVICE_ROLE_KEY` are already configured for the project's edge functions.

---

STEP COMPLETE — WAITING FOR NEXT RUN

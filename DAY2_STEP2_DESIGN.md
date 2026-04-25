# Day 2 — Step 2 (Re-evaluation): Payout Trigger Design Decision

**Date:** 2026-03-30
**Status:** COMPLETE
**Constraint:** Payout release must NOT depend on client making a second call

---

## Chosen Approach: D — New `confirm-and-release` Wrapper Edge Function

**Replace the client's direct RPC call with a single edge function that does both: confirms receipt AND releases payout atomically in one server-side request.**

The client calls ONE endpoint. That endpoint handles everything server-side. If the client crashes after sending the request, the server still completes both operations.

---

## How It Works

```
CURRENT FLOW (unsafe):
  Client → RPC confirm_transfer_received()  ← client must survive
  Client → edge function release-payout()   ← if client dies here, seller never gets paid

NEW FLOW (safe):
  Client → edge function confirm-and-release (single call)
           ├── 1. RPC confirm_transfer_received()   ← server-side, via service role
           ├── 2. If RPC succeeds OR status already buyer_confirmed:
           │       └── check payout_released_at IS NULL
           │           └── stripe.transfers.create()
           │           └── write payout_released_at + stripe_transfer_id
           └── 3. Return result to client
```

One client call. All money movement is server-controlled. If the client dies after firing the request, the edge function still completes both steps.

---

## Why This Is the Safest Option

### 1. No client dependency for money movement
The edge function owns the entire confirmation-to-payout pipeline. The client fires one request. Even if the client disconnects immediately after sending, Deno continues executing the function to completion. The seller gets paid regardless of client state.

### 2. Stripe secret key stays in edge function layer
The `STRIPE_SECRET_KEY` remains in the edge function environment — exactly where it already lives for `confirm-payment`, `create-connect-account`, and `stripe-webhook`. No database extensions, no secrets in Postgres.

### 3. Idempotency is bulletproof
Three layers of protection against duplicate payouts:
- **Layer 1:** `confirm_transfer_received` RPC already guards the state machine — only `seller_sent → buyer_confirmed` is allowed. A second call raises an exception ("cannot be confirmed from current status: buyer_confirmed"). The edge function catches this and treats it as "already confirmed, proceed to payout check."
- **Layer 2:** Before calling Stripe, the edge function checks `payout_released_at IS NULL` with `SELECT ... FOR UPDATE` row lock.
- **Layer 3:** After Stripe transfer succeeds, `payout_released_at` and `stripe_transfer_id` are written atomically. Any concurrent or retry call sees `payout_released_at IS NOT NULL` and returns success without calling Stripe.

### 4. Single atomic operation from client perspective
The client sends one request and gets one response: either "confirmed and payout released" or an error. No partial states where confirmation succeeded but payout didn't fire. No orphaned confirmations.

### 5. Follows existing codebase patterns exactly
- `confirm-payment` edge function: client calls it, it talks to Stripe + updates DB
- `stripe-webhook`: server-side function that calls RPCs via service role
- This new function combines both patterns: authenticated client call → RPC via service role → Stripe API → DB update

### 6. Minimal blast radius
- `confirm_transfer_received` RPC: **UNTOUCHED** (called server-side via service role instead of client-side)
- `stripe-webhook`: **UNTOUCHED**
- All other edge functions: **UNTOUCHED**
- Transfer state machine: **UNTOUCHED**
- Only changes: one new edge function + client swaps `supabase.rpc()` for `supabase.functions.invoke()`

---

## Why the Previous Client-Triggered Approach (Option B) Is Unsafe

The previous design required the client to make TWO sequential calls:
1. `supabase.rpc('confirm_transfer_received')` — confirmation
2. `supabase.functions.invoke('release-payout')` — payout

**Failure modes that lose seller money:**

| Scenario | Result |
|---|---|
| Client crashes between call 1 and call 2 | Buyer confirmed, seller never paid |
| Network drops after call 1 succeeds | Buyer confirmed, seller never paid |
| User force-closes app after confirmation alert | Buyer confirmed, seller never paid |
| App backgrounded by OS between calls | Payout call may never fire |
| User on spotty cellular, call 2 times out | Buyer confirmed, payout stuck |

Every one of these leaves the transfer in `buyer_confirmed` with no payout — a state that requires manual intervention to resolve. In a marketplace handling real money, this is unacceptable.

---

## Why the Other Options Are Still Worse

### Option A — Inside `confirm_transfer_received` RPC
Still rejected. PL/pgSQL cannot call Stripe without `pg_net` / `http` extensions and storing `STRIPE_SECRET_KEY` in Postgres config. This violates the existing security architecture and adds operational complexity (extension management, key rotation in DB).

### Option C — Separate server-triggered function (DB trigger / webhook)
Rejected. A Postgres `AFTER UPDATE` trigger firing a Supabase Database Webhook (via `pg_net`) to a `release-payout` edge function would work mechanically, but:
- Adds a new infrastructure pattern (Database Webhooks) not used anywhere in the codebase
- `pg_net` HTTP calls are fire-and-forget with no guaranteed delivery — if the edge function is down, the payout is lost silently
- Retry logic requires additional infrastructure (dead letter queue, monitoring)
- Debugging is harder: the trigger is invisible in application code
- The wrapper edge function achieves the same server-side guarantee with zero new infrastructure

### Option B — Client calls separate `release-payout` after RPC
Rejected per the new constraint above. Client-chained calls are not acceptable for money movement.

---

## Exact Hook Point

**New edge function:** `supabase/functions/confirm-and-release/index.ts`

**Client change (ListingDetailScreen.tsx line 748):**
```
BEFORE:  supabase.rpc('confirm_transfer_received', { p_transfer_id, p_user_id })
AFTER:   supabase.functions.invoke('confirm-and-release', { body: { transfer_id } })
```

**Edge function internal flow:**
1. Authenticate caller via JWT (same pattern as `confirm-payment`)
2. Call `confirm_transfer_received` RPC via service role, passing authenticated user ID
3. If RPC succeeds OR status is already `buyer_confirmed`: proceed
4. Check `payout_released_at IS NULL` with `FOR UPDATE` lock
5. Look up seller's `stripe_connect_id` from profiles
6. Look up payment amount from payments table
7. Call Stripe `transfers.create()` to seller's Connect account
8. Write `payout_released_at` and `stripe_transfer_id` to transfers row
9. Return success to client

---

## What Must Remain Untouched

| Component | Status |
|---|---|
| `confirm_transfer_received` RPC | DO NOT MODIFY — called server-side now |
| `stripe-webhook/index.ts` | DO NOT MODIFY |
| `confirm-payment/index.ts` | DO NOT MODIFY |
| `create-connect-account/index.ts` | DO NOT MODIFY |
| `create-payment-intent` | DO NOT MODIFY |
| Transfer state machine logic | DO NOT MODIFY |
| RLS policies on transfers | DO NOT MODIFY |
| Auth flow | DO NOT MODIFY |
| Payment flow | DO NOT MODIFY |

---

## Summary

A new **wrapper edge function** (`confirm-and-release`) is the answer. It absorbs both the confirmation RPC call and the payout release into a single server-side operation. The client makes one call. The server handles everything. The existing RPC is reused internally, untouched. Stripe keys stay in the edge function layer. Idempotency is enforced at three levels. No new infrastructure patterns are introduced.

---

STEP COMPLETE — WAITING FOR NEXT RUN

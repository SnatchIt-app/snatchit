# Day 2 — Step 3: Minimal Schema Decision

**Date:** 2026-03-30
**Status:** COMPLETE

---

## Required Schema Fields

Two columns added to `public.transfers`:

### 1. `payout_released_at` (timestamptz, nullable)

**Why required:**
This is the **primary idempotency guard** for payout release. Before calling `stripe.transfers.create()`, the edge function will check:
```
WHERE id = $transfer_id AND payout_released_at IS NULL
FOR UPDATE
```
If `payout_released_at` is NOT NULL, the payout has already been released — the function returns success without calling Stripe. This single column prevents duplicate payouts with zero ambiguity. It also serves as the audit timestamp proving when the seller was paid.

Without this column, idempotency would depend on checking Stripe's API for existing transfers — slower, more fragile, and introduces an external dependency in the guard path.

### 2. `stripe_transfer_id` (text, nullable)

**Why required:**
After `stripe.transfers.create()` succeeds, the Stripe Transfer ID (e.g., `tr_xxx`) is written here. This serves three critical purposes:

- **Debugging:** When a seller reports "I didn't get paid," support can look up the exact Stripe Transfer object in the dashboard using this ID. Without it, you'd have to search Stripe by amount + date + Connect account — error-prone and slow.
- **Reconciliation:** Maps the internal transfer row to the exact Stripe money movement. Essential for any financial audit, even at private beta scale.
- **Crash recovery:** If the edge function crashes after `stripe.transfers.create()` succeeds but before writing `payout_released_at`, a retry would see `payout_released_at IS NULL` and attempt another Stripe transfer. With `stripe_transfer_id` recorded, a recovery path can detect the partial completion state. (Defense-in-depth — the `payout_released_at` write is the primary guard, but having the Stripe ID recorded makes manual recovery trivial.)

---

## Fields NOT Needed Yet

| Field | Why NOT needed for private beta |
|---|---|
| `payout_status` | Unnecessary state machine. We only have one payout event (buyer confirms → pay seller). `payout_released_at IS NULL` vs `IS NOT NULL` is the only state we need. A status enum (pending/released/failed) adds complexity with no benefit when the edge function either succeeds atomically or doesn't write at all. |
| `released_by` | The only entity that can release payout is the `confirm-and-release` edge function, triggered by the buyer. The buyer's identity is already on the transfer row (`buyer_id`) and in the `buyer_confirmed_at` timestamp. A separate `released_by` column adds nothing. |
| `payout_failed_at` | If the Stripe transfer call fails, the edge function returns an error to the client. `payout_released_at` stays NULL. The client can retry. There is no "failed payout" state to record — either it succeeded (columns written) or it didn't (columns remain NULL). At private beta scale, edge function logs are sufficient for debugging failures. |
| `payout_error` | Same reasoning as `payout_failed_at`. Edge function logs capture the Stripe error. Storing error text in the DB is useful at scale but overengineering for private beta with <100 transactions. |
| `payout_amount` | The seller payout amount can be derived from `payments.amount` (the listing price excluding service fee) via the `payment_id` FK on the transfer row. Denormalizing it adds a column that could drift from the source of truth. Not needed. |

---

## Exact Migration SQL

```sql
-- =============================================================================
-- Migration 006: Payout release tracking
-- =============================================================================
-- PURPOSE: Add minimal columns to support idempotent payout release
-- after buyer confirms receipt.
--
-- payout_released_at: idempotency guard + audit timestamp
-- stripe_transfer_id: Stripe Transfer object reference for debugging/reconciliation
--
-- Both columns are nullable — NULL means payout has not been released.
-- The confirm-and-release edge function writes both atomically after
-- stripe.transfers.create() succeeds.
-- =============================================================================

alter table public.transfers
  add column if not exists payout_released_at  timestamptz,
  add column if not exists stripe_transfer_id  text;
```

That's it. Two columns, both nullable, purely additive. No constraints, no indexes, no triggers. Zero impact on existing queries, RPCs, or RLS policies.

---

## Is This Enough for Private Beta?

**Yes.** These two columns provide:

- **Idempotency:** `payout_released_at IS NULL` + `FOR UPDATE` lock prevents double payouts
- **Audit trail:** Timestamp of when seller was paid + exact Stripe Transfer ID
- **Debugging:** Support can query `SELECT stripe_transfer_id FROM transfers WHERE id = $x` and look it up in Stripe dashboard in seconds
- **Reconciliation:** Join `transfers.stripe_transfer_id` with Stripe's Transfer API for financial reporting

For private beta (<100 transactions), this is the right level of schema investment. Error tracking, payout status enums, and failure recording can be added in a future migration if operational data shows they're needed.

---

## What Must Remain Untouched

| Component | Status |
|---|---|
| `transfers` table — existing columns | DO NOT MODIFY |
| `transfers` table — existing constraints | DO NOT MODIFY |
| `confirm_transfer_received` RPC | DO NOT MODIFY |
| `mark_transfer_sent` RPC | DO NOT MODIFY |
| All existing migrations (001–005) | DO NOT MODIFY |
| RLS policies on transfers | DO NOT MODIFY |
| `payments` table | DO NOT MODIFY |
| `profiles` table | DO NOT MODIFY |

---

STEP COMPLETE — WAITING FOR NEXT RUN

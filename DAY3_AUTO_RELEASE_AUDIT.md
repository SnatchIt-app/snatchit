# Day 3 — Auto-Release Timer for seller_sent Transfers: Audit Report

**Date:** 2026-04-01
**Status:** AUDIT COMPLETE — implementation plan ready

---

## SECTION 1 — Current Readiness for Day 3

### What Already Exists

| Component | Status | Notes |
|-----------|--------|-------|
| `transfers.status` check constraint | Has `pending`, `seller_sent`, `buyer_confirmed`, `disputed`, `expired` | **No `auto_released` status exists yet** — needs to be added |
| `transfers.seller_sent_at` | EXISTS | Timestamp when seller marked sent — used to calculate 72h deadline |
| `transfers.payout_released_at` | EXISTS (migration 006) | Idempotency guard for payouts — reusable for auto-release |
| `transfers.stripe_transfer_id` | EXISTS (migration 006) | Stores Stripe Transfer ID — reusable for auto-release |
| `transfers.auto_release_at` | **DOES NOT EXIST** | Must be added — 72h deadline column |
| `mark_transfer_sent` RPC | EXISTS | Transitions `pending → seller_sent`, sets `seller_sent_at = now()` — **does NOT set an `auto_release_at`** |
| `enforce_transfer_expiry()` RPC | EXISTS | Batch expires `pending` transfers past `expires_at` — pattern is reusable |
| `enforce-transfer-expiry` edge function | EXISTS | Cron-triggered, processes expired transfers with refunds — **extensible for auto-release** |
| `confirm-and-release` edge function | EXISTS | Full payout logic: Stripe Transfer + atomic DB update — **payout logic directly reusable** |
| `confirm_transfer_received` RPC | EXISTS | Transitions `seller_sent → buyer_confirmed` — will NOT be called for auto-release (no buyer action) |
| `disputed` status | EXISTS in check constraint | Disputed transfers must be **skipped** by auto-release |

### What Is Already Working (Day 1 + Day 2)

1. **Buyer confirm → payout release**: `confirm-and-release` edge function works end-to-end
2. **Seller ghost → expiry + auto-refund**: `enforce-transfer-expiry` cron handles `pending` transfers past `expires_at`
3. **Payout idempotency**: `payout_released_at IS NULL` atomic UPDATE guard in `confirm-and-release`

### What's Missing for Day 3

**Buyer ghost protection**: If seller marks ticket as sent (`seller_sent`) and buyer does not confirm or dispute within 72 hours, the system should automatically release payout to seller.

---

## SECTION 2 — Exact Missing Pieces

### 2.1 Schema Changes

| # | Change | Table | Details |
|---|--------|-------|---------|
| 1 | Add column `auto_release_at` | `transfers` | `timestamptz`, nullable — set by `mark_transfer_sent` to `seller_sent_at + 72 hours` |
| 2 | Add status `auto_released` to check constraint | `transfers` | New terminal status for auto-released transfers |
| 3 | Add partial index for auto-release sweep | `transfers` | `(auto_release_at) WHERE status = 'seller_sent'` — mirrors `idx_transfers_pending_expires` pattern |

### 2.2 RPC Changes

| # | Change | Function | Details |
|---|--------|----------|---------|
| 1 | Update `mark_transfer_sent` | Existing RPC | Set `auto_release_at = now() + interval '72 hours'` alongside `seller_sent_at = now()` |
| 2 | New `enforce_auto_release()` RPC | New function | Batch function: selects `WHERE status = 'seller_sent' AND auto_release_at < now()` with `FOR UPDATE SKIP LOCKED`, updates `status = 'auto_released'` — returns affected rows for payout processing |

### 2.3 Edge Function Changes

| # | Change | Function | Details |
|---|--------|----------|---------|
| 1 | Extend `enforce-transfer-expiry` | Existing function | Add a second phase after the expiry sweep: call `enforce_auto_release()` RPC, then for each returned row execute the payout logic (reused from `confirm-and-release`) and send notifications |

### 2.4 Notification Requirements

| Recipient | Title | Body |
|-----------|-------|------|
| Seller | `Payout Released` | `Your payout for {listing_title} has been automatically released. The buyer did not respond within 72 hours.` |
| Buyer | `Transfer Auto-Confirmed` | `The transfer for {listing_title} was automatically confirmed after 72 hours. If you have any issues, please contact support.` |

---

## SECTION 3 — Smallest Exact Implementation Plan

### Principle: Minimal V1, maximum reuse

The smallest implementation is:

1. **One new migration** (008_auto_release.sql) — adds `auto_release_at` column, updates status check constraint, adds partial index, creates `enforce_auto_release()` RPC, updates `mark_transfer_sent` to set `auto_release_at`
2. **One edge function modification** — extend `enforce-transfer-expiry/index.ts` to add auto-release processing after the existing expiry sweep (no new edge function needed)
3. **No new cron job** — piggyback on the existing 5-minute cron that calls `enforce-transfer-expiry`
4. **No client changes** — auto-release is purely server-side

### Why Extend enforce-transfer-expiry Instead of Creating a New Function?

- Same cron schedule (every 5 minutes) is appropriate
- Same auth pattern (INTERNAL_CRON_SECRET)
- Same stripePost and sendPush helpers already exist
- Same error isolation pattern (one failure doesn't block batch)
- Avoids a second cron job and second edge function deployment
- The two sweeps are independent — expiry runs first (refunds `pending`), then auto-release runs (pays out `seller_sent`)

### Why a New Status (`auto_released`) Instead of Reusing `buyer_confirmed`?

- `buyer_confirmed` implies the buyer took action — audit trail distinction matters
- Dispute resolution needs to distinguish auto-released vs buyer-confirmed transfers
- The check constraint already exists and must be updated anyway
- No additional complexity — just a different string in the UPDATE

### Flow

```
Seller taps "Mark as Sent"
  → mark_transfer_sent RPC
    → status = 'seller_sent'
    → seller_sent_at = now()
    → auto_release_at = now() + 72h     ← NEW

Buyer confirms within 72h?
  → YES: confirm-and-release runs as today (seller_sent → buyer_confirmed → payout)
  → NO (buyer ghost): enforce-transfer-expiry cron picks it up:
    → enforce_auto_release() RPC: seller_sent → auto_released
    → Stripe Transfer to seller (same logic as confirm-and-release)
    → payout_released_at + stripe_transfer_id written atomically
    → Push notifications to both parties

Buyer disputes within 72h?
  → status = 'disputed' — enforce_auto_release() skips (WHERE status = 'seller_sent')
```

---

## SECTION 4 — Exact SQL / Edge Function / Scheduler Changes Needed

### 4.1 Migration 008_auto_release.sql

```sql
-- =============================================================================
-- Migration 008: Auto-release timer for seller_sent transfers
-- =============================================================================
-- PURPOSE: If seller marked ticket as sent and buyer does not confirm or
-- dispute within 72 hours, automatically release payout to seller.
--
-- CONTEXT (Day 3 — buyer ghost protection):
--   The enforce-transfer-expiry edge function will be extended to:
--     1. Call enforce_auto_release() RPC (batch: seller_sent → auto_released)
--     2. For each auto-released transfer, execute payout via Stripe Transfer
--     3. Write payout_released_at + stripe_transfer_id atomically
--     4. Send push notifications to buyer and seller
--
-- SAFETY:
--   - Purely additive (ADD COLUMN IF NOT EXISTS, CREATE OR REPLACE)
--   - Status check constraint is DROP + CREATE (atomic in single transaction)
--   - Partial index is additive
--   - mark_transfer_sent replacement preserves all existing behavior
--   - Safe to run on live DB with zero downtime
-- =============================================================================


-- ===========================================================================
-- 1. NEW COLUMN: auto_release_at
-- ===========================================================================
alter table public.transfers
  add column if not exists auto_release_at timestamptz;


-- ===========================================================================
-- 2. UPDATE STATUS CHECK CONSTRAINT
-- ===========================================================================
-- Add 'auto_released' to the allowed status values.
-- Must drop and recreate — ALTER CONSTRAINT doesn't support modifying CHECK.
-- ===========================================================================
alter table public.transfers
  drop constraint if exists transfers_status_check;

alter table public.transfers
  add constraint transfers_status_check
  check (status in (
    'pending',
    'seller_sent',
    'buyer_confirmed',
    'disputed',
    'expired',
    'auto_released'
  ));


-- ===========================================================================
-- 3. PARTIAL INDEX FOR AUTO-RELEASE SWEEP
-- ===========================================================================
-- Mirrors idx_transfers_pending_expires pattern.
-- Only rows with status='seller_sent' are indexed.
-- ===========================================================================
create index if not exists idx_transfers_seller_sent_auto_release
  on public.transfers (auto_release_at)
  where status = 'seller_sent';


-- ===========================================================================
-- 4. UPDATE mark_transfer_sent TO SET auto_release_at
-- ===========================================================================
-- CHANGE: Adds auto_release_at = now() + interval '72 hours'
-- All other logic is IDENTICAL to the existing function in 002_transfers.sql.
-- ===========================================================================
create or replace function public.mark_transfer_sent(
  p_transfer_id uuid,
  p_user_id     uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid;
  v_status    text;
  v_seller_id uuid;
begin
  v_caller_id := coalesce(auth.uid(), p_user_id);

  if v_caller_id is null then
    raise exception 'Unable to identify caller. Ensure the request is authenticated.';
  end if;

  select status, seller_id
    into v_status, v_seller_id
    from public.transfers
   where id = p_transfer_id
     for update;

  if not found then
    raise exception 'Transfer not found.';
  end if;

  if v_seller_id is distinct from v_caller_id then
    raise exception 'Only the seller can mark a transfer as sent.';
  end if;

  if v_status <> 'pending' then
    raise exception 'Transfer cannot be marked as sent from current status: %.', v_status;
  end if;

  update public.transfers
     set status           = 'seller_sent',
         seller_sent_at   = now(),
         auto_release_at  = now() + interval '72 hours'    -- NEW: Day 3
   where id = p_transfer_id;
end;
$$;


-- ===========================================================================
-- 5. enforce_auto_release() RPC
-- ===========================================================================
-- Called by:   enforce-transfer-expiry edge function (service role, cron)
-- Pattern:     Identical to enforce_transfer_expiry — batch + SKIP LOCKED
-- Transition:  seller_sent → auto_released (only for transfers past auto_release_at)
--
-- Returns the affected rows so the edge function can:
--   - Issue Stripe Transfers (payouts) for each
--   - Send push notifications to buyer and seller
--
-- SKIP LOCKED ensures concurrent cron invocations never double-process.
-- Disputed transfers are automatically excluded (WHERE status = 'seller_sent').
-- ===========================================================================
create or replace function public.enforce_auto_release()
returns table (
  transfer_id         uuid,
  payment_id          uuid,
  listing_id          uuid,
  buyer_id            uuid,
  seller_id           uuid
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with releasable as (
    select t.id, t.payment_id, t.listing_id, t.buyer_id, t.seller_id
      from public.transfers t
     where t.status = 'seller_sent'
       and t.auto_release_at is not null
       and t.auto_release_at < now()
       for update skip locked
  )
  update public.transfers t
     set status = 'auto_released'
    from releasable r
   where t.id = r.id
  returning t.id        as transfer_id,
            t.payment_id,
            t.listing_id,
            t.buyer_id,
            t.seller_id;
end;
$$;
```

### 4.2 Edge Function Changes: enforce-transfer-expiry/index.ts

Add a **second phase** after the existing expiry sweep (after line 288 in current file). The new phase:

1. Calls `enforce_auto_release()` RPC
2. For each returned row:
   a. Checks `payout_released_at IS NULL` (idempotency — should always be null since RPC just set status)
   b. Looks up seller's `stripe_connect_id` from profiles
   c. Looks up `payment.amount` from payments
   d. Calls `stripePost('/transfers', ...)` — identical to confirm-and-release step 8
   e. Atomic UPDATE: sets `payout_released_at` and `stripe_transfer_id` WHERE `payout_released_at IS NULL`
   f. Sends push notifications to buyer and seller
3. Returns combined summary (expired count + auto-released count)

**Key reuse from confirm-and-release:**
- `stripePost` helper (already exists in enforce-transfer-expiry)
- `sendPush` helper (already exists in enforce-transfer-expiry)
- Atomic UPDATE pattern with `payout_released_at IS NULL` guard
- Stripe Transfer creation with metadata

### 4.3 Scheduler Changes

**NONE.** The existing pg_cron job that invokes `enforce-transfer-expiry` every 5 minutes will automatically pick up the new auto-release phase. No new cron job needed.

### 4.4 Client Changes

**NONE.** Auto-release is purely server-side. The client already displays transfer status via `TransferStatusBadge.tsx` — it may need a cosmetic update to display `auto_released` nicely, but this is non-blocking for V1.

---

## SECTION 5 — Exact Implementation Prompt

```
Act as a principal marketplace payments + Supabase engineer.

CRITICAL RULES:
- Day 1 and Day 2 are COMPLETE and WORKING
- Preserve all current working flows
- Focus ONLY on implementing Day 3: Auto-Release Timer
- Do NOT redesign the payout architecture
- Do NOT modify confirm-and-release edge function
- Do NOT modify stripe-webhook edge function
- Do NOT create a new edge function — extend enforce-transfer-expiry

CONTEXT:
- transfers table has: status (pending/seller_sent/buyer_confirmed/disputed/expired),
  seller_sent_at, payout_released_at, stripe_transfer_id, expires_at, expired_at
- transfers table DOES NOT have: auto_release_at column or 'auto_released' status
- mark_transfer_sent RPC: pending → seller_sent, sets seller_sent_at = now()
- enforce_transfer_expiry() RPC: batch expires pending transfers, returns rows for refund
- enforce-transfer-expiry edge function: calls RPC, issues Stripe refunds, sends notifications
- confirm-and-release edge function: buyer auth → confirm RPC → Stripe Transfer → atomic UPDATE

TASK: Implement Day 3 Auto-Release Timer

Create exactly 2 files, modify exactly 1 file:

FILE 1 — CREATE: supabase/migrations/008_auto_release.sql
- Add column: transfers.auto_release_at (timestamptz, nullable)
- Drop and recreate status check constraint to add 'auto_released'
- Add partial index: idx_transfers_seller_sent_auto_release on (auto_release_at) WHERE status = 'seller_sent'
- Replace mark_transfer_sent to also set auto_release_at = now() + interval '72 hours'
  (ALL other logic identical — same auth, same state guard, same seller check)
- Create enforce_auto_release() RPC:
  - SECURITY DEFINER, search_path = public
  - CTE: SELECT ... FROM transfers WHERE status = 'seller_sent' AND auto_release_at IS NOT NULL AND auto_release_at < now() FOR UPDATE SKIP LOCKED
  - UPDATE: status = 'auto_released'
  - RETURNS TABLE (transfer_id, payment_id, listing_id, buyer_id, seller_id)

FILE 2 — MODIFY: supabase/functions/enforce-transfer-expiry/index.ts
After the existing expiry sweep (after the summary return), add a second phase:
- Call supabase.rpc('enforce_auto_release')
- For each returned row:
  a. Look up seller's stripe_connect_id from profiles
  b. Look up payment.amount from payments
  c. Skip if payout_released_at IS NOT NULL (idempotency)
  d. Call stripePost('/transfers', { amount, currency: 'usd', destination: stripe_connect_id, metadata })
  e. Atomic UPDATE transfers SET payout_released_at, stripe_transfer_id WHERE id = transfer_id AND payout_released_at IS NULL
  f. sendPush to seller: 'Payout Released' / 'Your payout for {listing} has been automatically released...'
  g. sendPush to buyer: 'Transfer Auto-Confirmed' / 'The transfer for {listing} was automatically confirmed after 72 hours...'
- Return combined summary: { expired, refunded, auto_released, errors, timestamp }

IMPORTANT: Restructure the edge function so BOTH phases run (expiry + auto-release), and the response includes counts for both. The current early return after expiry sweep must be changed to accumulate results, then run auto-release, then return combined summary.

FILE 3 — CREATE: DAY3_AUTO_RELEASE_REPORT.md
Document what was implemented, files created/modified, and deployment steps.

DEPLOYMENT STEPS (include in report):
1. Run migration 008 in Supabase SQL Editor
2. Deploy updated enforce-transfer-expiry edge function: supabase functions deploy enforce-transfer-expiry
3. Verify by checking: SELECT auto_release_at FROM transfers WHERE status = 'seller_sent' LIMIT 5
4. Test manually: UPDATE a test transfer to seller_sent with auto_release_at in the past, then invoke the cron

DO NOT modify any other files. Preserve all Day 1 and Day 2 behavior.
```

---

## Summary

| Aspect | Decision |
|--------|----------|
| New column | `transfers.auto_release_at` (timestamptz, nullable) |
| New status | `auto_released` added to check constraint |
| Timer set by | `mark_transfer_sent` RPC (sets `auto_release_at = now() + 72h`) |
| Timer enforced by | `enforce_auto_release()` RPC (new, same pattern as `enforce_transfer_expiry()`) |
| Payout executed by | Extended `enforce-transfer-expiry` edge function (reuses Stripe Transfer logic from `confirm-and-release`) |
| Disputed transfers | Skipped automatically (`WHERE status = 'seller_sent'` excludes `disputed`) |
| Already-paid guard | `payout_released_at IS NULL` atomic UPDATE (same as `confirm-and-release`) |
| New cron job | NONE — piggybacks on existing 5-min cron |
| New edge function | NONE — extends existing `enforce-transfer-expiry` |
| Client changes | NONE (cosmetic `auto_released` badge optional, non-blocking) |
| New tables | NONE |
| Files created | 1 migration (008_auto_release.sql) |
| Files modified | 1 edge function (enforce-transfer-expiry/index.ts) |

STEP COMPLETE — WAITING FOR NEXT RUN

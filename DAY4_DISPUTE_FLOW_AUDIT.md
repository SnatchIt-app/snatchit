# DAY 4 — DISPUTE / REPORT-PROBLEM FLOW AUDIT

**Generated:** 2026-04-01
**Status:** Audit complete — ready for implementation

---

## SECTION 1 — Current Readiness for Day 4

### What already exists:

| Component | Status | Details |
|-----------|--------|---------|
| `disputed` status in CHECK constraint | READY | Present in `008_auto_release.sql` constraint: `CHECK (status IN ('pending','seller_sent','buyer_confirmed','disputed','expired','auto_released'))` |
| `TransferStatusBadge` component | READY | Already renders `disputed` status with red/error color and label "Disputed" |
| UI "Report Issue" button | WIRED BUT DEAD | `app/transfer/receive/[id].tsx` lines 96–123 — button exists, calls `supabase.rpc('buyer_dispute_transfer', { p_transfer_id: id })` — but **the RPC does not exist in the database** |
| UI disputed state banner | READY | `app/transfer/receive/[id].tsx` lines 253–257 — shows "Issue reported — we're looking into it" when `status === 'disputed'` |
| Auto-release skips disputed | READY | `enforce_auto_release()` RPC filters `WHERE t.status = 'seller_sent'` — disputed transfers are **automatically excluded** from auto-release |
| Confirm-and-release skips disputed | READY | `confirm_transfer_received()` RPC requires `status = 'seller_sent'` — disputed transfers **cannot be confirmed** |
| RLS policies | READY | Buyer and seller can both SELECT their own transfers — no INSERT/UPDATE via client (all mutations go through SECURITY DEFINER RPCs) |

### Verdict: ~80% of Day 4 is already scaffolded. The only missing piece is the database RPC itself plus notifications.

---

## SECTION 2 — Exact Missing Pieces

### 2.1 — Missing RPC: `buyer_dispute_transfer`

The client already calls `supabase.rpc('buyer_dispute_transfer', { p_transfer_id: id })` but this function does not exist in any migration. The RPC needs to:

- Accept `p_transfer_id uuid` (client passes this)
- Identify the caller via `auth.uid()` (client uses anon key with JWT)
- Validate: caller is the buyer
- Validate: status is `seller_sent` (only allow dispute after seller sends, before confirm/auto-release)
- Transition: `status = 'disputed'`
- Set: `disputed_at = now()` (new column needed for audit trail)

### 2.2 — Missing Column: `disputed_at`

No `disputed_at` timestamp exists on the transfers table. This is needed for:
- Audit trail (when was it disputed)
- Future SLA tracking (admin response time)
- Potential auto-resolution timer

### 2.3 — Missing Notifications

When a buyer disputes, both parties should receive push notifications:
- **Buyer:** Confirmation that the dispute was filed
- **Seller:** Alert that the buyer reported an issue

### 2.4 — Client RPC Signature Mismatch (Minor)

The client calls `supabase.rpc('buyer_dispute_transfer', { p_transfer_id: id })` — note it only passes `p_transfer_id`, not `p_user_id`. Since the client uses the anon key with JWT, `auth.uid()` is available inside the RPC. The RPC should rely on `auth.uid()` as the primary caller identity (matching how `confirm_transfer_received` works when called directly by client vs. via edge function).

However, the existing pattern in `mark_transfer_sent` and `confirm_transfer_received` uses `coalesce(auth.uid(), p_user_id)` to support both client-direct and edge-function calls. For consistency, the RPC should accept `p_user_id uuid DEFAULT NULL` but the client only needs to pass `p_transfer_id`.

### 2.5 — No New Edge Function Needed (V1)

For V1, the dispute RPC can be called directly by the client (same as how `mark_transfer_sent` works from the seller send screen). No edge function wrapper is needed because:
- No Stripe API call is involved (funds are frozen, not moved)
- No payment mutation occurs
- The RPC is SECURITY DEFINER with proper auth checks

Notifications can be sent via a database trigger or a lightweight edge function call from the client after the RPC succeeds. For V1-simplicity, the client can call `send-push` directly after a successful RPC (matching the existing pattern in the codebase where push is best-effort).

---

## SECTION 3 — Smallest Exact Implementation Plan

### Step 1: Migration `009_dispute.sql`
- Add `disputed_at timestamptz` column to transfers
- Create `buyer_dispute_transfer(p_transfer_id uuid, p_user_id uuid DEFAULT NULL)` RPC

### Step 2: No edge function changes needed
- `enforce_auto_release()` already skips disputed transfers (WHERE status = 'seller_sent')
- `confirm_transfer_received()` already rejects disputed transfers (requires status = 'seller_sent')
- `confirm-and-release` edge function already rejects non-buyer_confirmed states

### Step 3: Client notification call (optional V1 enhancement)
- After successful RPC call in `handleDispute()`, fire two push notifications via `send-push` edge function
- This is best-effort — if push fails, the dispute is still recorded

### Step 4: No UI changes needed
- "Report Issue" button already exists and calls the correct RPC name
- Disputed state banner already exists
- TransferStatusBadge already handles `disputed` status

---

## SECTION 4 — Exact SQL / Edge Function / Client Changes Needed

### 4.1 — Migration: `supabase/migrations/009_dispute.sql`

```sql
-- =============================================================================
-- 009_dispute.sql — Day 4: Dispute / Report-Problem Flow
-- =============================================================================
-- PURPOSE: Add buyer dispute capability to freeze transfers from auto-release.
--
-- WHAT THIS ADDS:
--   1. disputed_at column for audit trail
--   2. buyer_dispute_transfer() RPC for client to call
--
-- WHAT THIS PRESERVES:
--   - All existing statuses and transitions (Day 1–3)
--   - enforce_auto_release() already skips disputed (WHERE status='seller_sent')
--   - confirm_transfer_received() already rejects disputed
--   - No changes to payout logic
-- =============================================================================

-- ── 1. Add disputed_at timestamp ────────────────────────────────────────────
ALTER TABLE public.transfers
  ADD COLUMN IF NOT EXISTS disputed_at timestamptz;

-- ── 2. Create buyer_dispute_transfer RPC ────────────────────────────────────
-- Transitions a transfer from 'seller_sent' → 'disputed'.
-- Only the buyer can dispute. Freezes the transfer from auto-release and
-- from buyer confirmation (both check status = 'seller_sent').
--
-- AUTH: Uses auth.uid() when called from client with JWT (anon key).
--       Falls back to p_user_id when called from edge function (service role).
--       Matches the pattern in mark_transfer_sent and confirm_transfer_received.
--
-- IDEMPOTENCY: If already disputed, silently succeeds (no error).
-- =============================================================================
CREATE OR REPLACE FUNCTION public.buyer_dispute_transfer(
  p_transfer_id uuid,
  p_user_id     uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_status    text;
  v_buyer_id  uuid;
BEGIN
  v_caller_id := coalesce(auth.uid(), p_user_id);

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.';
  END IF;

  SELECT status, buyer_id
    INTO v_status, v_buyer_id
    FROM public.transfers
   WHERE id = p_transfer_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer not found.';
  END IF;

  IF v_buyer_id IS DISTINCT FROM v_caller_id THEN
    RAISE EXCEPTION 'Only the buyer can dispute a transfer.';
  END IF;

  -- Idempotency: already disputed → no-op
  IF v_status = 'disputed' THEN
    RETURN;
  END IF;

  -- Only allow dispute from seller_sent (active transfer window)
  -- Cannot dispute: pending (seller hasn't sent yet), buyer_confirmed (already confirmed),
  -- expired (already refunded), auto_released (already paid out)
  IF v_status <> 'seller_sent' THEN
    RAISE EXCEPTION 'Cannot dispute transfer in current status: %.', v_status;
  END IF;

  UPDATE public.transfers
     SET status      = 'disputed',
         disputed_at = now()
   WHERE id = p_transfer_id;
END;
$$;
```

### 4.2 — Client Changes: `app/transfer/receive/[id].tsx`

**No structural changes needed.** The existing `handleDispute()` function at lines 96–123 already:
1. Shows confirmation alert ("Are you sure?")
2. Calls `supabase.rpc('buyer_dispute_transfer', { p_transfer_id: id })`
3. Shows success message ("Issue has been reported")
4. Navigates back on OK

**Optional V1 enhancement — add push notifications after successful dispute:**

```typescript
// After the successful RPC call (line 115, after setSubmitting(false)),
// add best-effort push notifications:
async function handleDispute() {
  Alert.alert(
    'Report Issue',
    'Are you sure you want to report an issue with this transfer?',
    [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Report',
        style: 'destructive',
        onPress: async () => {
          setSubmitting(true);
          const { error: rpcErr } = await supabase.rpc('buyer_dispute_transfer', {
            p_transfer_id: id,
          });
          setSubmitting(false);

          if (rpcErr) {
            Alert.alert('Error', rpcErr.message);
            return;
          }

          // Best-effort push notifications (fire-and-forget)
          // Notify seller that buyer reported an issue
          supabase.functions.invoke('send-push', {
            body: {
              user_id: transfer?.seller?.id,
              title: 'Transfer Disputed',
              body: `The buyer reported an issue with the transfer for ${transfer?.listing?.title || 'your listing'}. Payout is on hold.`,
              data: { type: 'transfer_disputed_seller' },
            },
          }).catch(() => {}); // best-effort

          Alert.alert('Reported', 'Issue has been reported. We will look into it.', [
            { text: 'OK', onPress: () => router.back() },
          ]);
        },
      },
    ],
  );
}
```

**Note on seller_id availability:** The current Transfer type does not include `seller.id` — only `seller.display_name`. To send push to the seller, either:
- (a) Add `seller_id` to the select query (simplest — it's already on the transfers row), or
- (b) Use a database trigger to send the notification (cleaner but more complex for V1)

For V1, option (a) is recommended: update the select query to include `seller_id` directly from the transfers row.

### 4.3 — Edge Function Changes

**None required.** All three existing edge functions already handle disputed transfers correctly:

| Edge Function | Behavior with Disputed Transfers |
|---------------|----------------------------------|
| `confirm-and-release` | Rejects — `confirm_transfer_received` RPC requires `status = 'seller_sent'` |
| `enforce-transfer-expiry` Phase 1 | Unaffected — only processes `status = 'pending'` |
| `enforce-transfer-expiry` Phase 2 | Skips — `enforce_auto_release()` RPC filters `WHERE status = 'seller_sent'` |

### 4.4 — No new tables needed

For V1, the dispute is a simple freeze. No dispute messages, no resolution workflow, no admin panel. The `disputed_at` timestamp on the transfers table is sufficient. Future iterations can add a `disputes` table for tracking messages, resolution notes, and admin actions.

---

## SECTION 5 — Exact Implementation Prompt

```
Act as a principal Supabase + React Native engineer.

CONTEXT:
- SnatchIt is a ticket marketplace with escrow-style payments
- Days 1-3 are working: buyer confirm → payout, seller ghost → expiry + refund, buyer ghost → 72h auto-release
- The 'disputed' status already exists in the transfers CHECK constraint
- The UI "Report Issue" button already exists in app/transfer/receive/[id].tsx and calls supabase.rpc('buyer_dispute_transfer', { p_transfer_id: id })
- The TransferStatusBadge already renders 'disputed' with red styling
- enforce_auto_release() already skips disputed transfers (WHERE status = 'seller_sent')

TASK:
Create migration 009_dispute.sql with EXACTLY this content:

1. ALTER TABLE public.transfers ADD COLUMN IF NOT EXISTS disputed_at timestamptz;

2. CREATE OR REPLACE FUNCTION public.buyer_dispute_transfer(
     p_transfer_id uuid,
     p_user_id uuid DEFAULT NULL
   )
   - Use coalesce(auth.uid(), p_user_id) for caller identity
   - SELECT status, buyer_id FROM transfers WHERE id = p_transfer_id FOR UPDATE
   - Validate: caller is buyer
   - Idempotency: if already 'disputed', RETURN silently
   - Only allow from 'seller_sent' status
   - UPDATE SET status = 'disputed', disputed_at = now()

3. Update app/transfer/receive/[id].tsx:
   - Add seller_id to the Transfer type and select query
   - After successful dispute RPC, fire best-effort push to seller via supabase.functions.invoke('send-push')

DO NOT:
- Modify any existing RPCs or edge functions
- Add new tables
- Change payout logic
- Modify the status CHECK constraint (disputed is already in it)

VERIFY:
- The RPC signature matches what the client already calls: supabase.rpc('buyer_dispute_transfer', { p_transfer_id: id })
- enforce_auto_release() still skips disputed (no change needed — WHERE status = 'seller_sent')
- confirm-and-release still rejects disputed (no change needed — RPC requires seller_sent)
```

---

## SUMMARY

| Item | Status |
|------|--------|
| Schema: `disputed` in CHECK constraint | Already exists |
| Schema: `disputed_at` column | **NEEDS MIGRATION** |
| RPC: `buyer_dispute_transfer()` | **NEEDS CREATION** |
| UI: "Report Issue" button | Already exists and wired |
| UI: Disputed state banner | Already exists |
| Badge: Disputed rendering | Already exists |
| Auto-release skip | Already works |
| Confirm skip | Already works |
| Expiry skip | N/A (only affects pending) |
| Push notifications | **OPTIONAL V1 ENHANCEMENT** |
| New edge function | Not needed |
| New table | Not needed |
| Estimated LOC | ~50 SQL + ~10 TypeScript |

**The entire Day 4 implementation is ONE migration file (~50 lines of SQL) and an optional ~10-line client tweak for push notifications.**

STEP COMPLETE — WAITING FOR NEXT RUN

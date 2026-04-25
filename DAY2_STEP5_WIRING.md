# Day 2 — Step 5: Client Wiring

**Date:** 2026-03-30
**Status:** COMPLETE

---

## File Modified

**`src/screens/ListingDetailScreen.tsx`** — `handleConfirmReceived()` function (lines 745–791)

One function changed. No other files modified.

---

## Exact Diff

### BEFORE (direct RPC call)
```typescript
async function handleConfirmReceived() {
  if (!transferId || !user?.id) return;
  setTransferActionLoading(true);
  const { error } = await supabase.rpc('confirm_transfer_received', {
    p_transfer_id: transferId,
    p_user_id:     user.id,
  });
  setTransferActionLoading(false);
  if (error) { Alert.alert('Error', error.message); return; }
  setTransferStatus('buyer_confirmed');
  Alert.alert('Confirmed!', 'Transfer complete. Enjoy the event! 🎉');
}
```

### AFTER (edge function call)
```typescript
async function handleConfirmReceived() {
  if (!transferId || !user?.id) return;
  setTransferActionLoading(true);

  try {
    const { data: session } = await supabase.auth.getSession();
    if (!session?.session?.access_token) {
      setTransferActionLoading(false);
      Alert.alert('Error', 'Please sign in again to confirm receipt.');
      return;
    }

    const { data, error: fnError } = await supabase.functions.invoke(
      'confirm-and-release',
      {
        body: { transfer_id: transferId },
        headers: { Authorization: `Bearer ${session.session.access_token}` },
      },
    );

    setTransferActionLoading(false);

    if (fnError) {
      let message = 'Something went wrong. Please try again.';
      try {
        const body = typeof data === 'string' ? JSON.parse(data) : data;
        if (body?.error) message = body.error;
      } catch {
        // If parsing fails, use the generic message above
      }
      Alert.alert('Error', message);
      return;
    }

    setTransferStatus('buyer_confirmed');
    Alert.alert('Confirmed!', 'Transfer complete. Enjoy the event! 🎉');
  } catch (err) {
    setTransferActionLoading(false);
    console.error('handleConfirmReceived: unexpected error:', err);
    Alert.alert('Error', 'Something went wrong. Please try again.');
  }
}
```

---

## What Changed and Why

| Change | Reason |
|---|---|
| `supabase.rpc(...)` → `supabase.functions.invoke(...)` | Route through wrapper edge function for server-side payout |
| Added `supabase.auth.getSession()` | Edge functions need explicit JWT in Authorization header (same pattern as `confirm-payment` in payments.ts) |
| Session null check | Graceful handling if session expired — tells user to sign in again |
| `try/catch` wrapper | Catches network errors, JSON parse failures, any unexpected throw |
| Error message extraction from `data` body | `supabase.functions.invoke` puts the response body in `data` even on error; we extract the `error` field for user-facing messages |
| Generic fallback message | Never exposes internal error details to the user |

---

## Error Handling Behavior

| Scenario | User sees | Retryable? |
|---|---|---|
| Session expired | "Please sign in again to confirm receipt." | Yes (after re-auth) |
| Transfer not found | "Transfer not found" (from edge function) | No |
| Not the buyer | "Only the buyer can release payout" (from edge function) | No |
| Transfer in wrong state (pending) | Error message from RPC via edge function | No |
| Seller has no Connect account | "Seller payout account not set up. Please contact support." | No (seller action needed) |
| Stripe Transfer fails | "Payout to seller failed. Please try again or contact support." | Yes |
| Rate limited | "Too many requests. Please try again later." | Yes (after cooldown) |
| Network error / timeout | "Something went wrong. Please try again." | Yes |
| Already confirmed + already paid | Success alert (idempotent) | N/A |

---

## Why This Is Safe for Duplicate Taps / Retries

### UI layer protection (unchanged)
The confirm button has `disabled={transferActionLoading}` and `onPress={transferActionLoading ? undefined : handleConfirmReceived}`. While the request is in flight, the button is disabled and shows a spinner. This prevents rapid double-taps.

### Edge function idempotency (from Step 4)
If the user somehow fires two requests (e.g., taps then navigates back and taps again):
- First request: confirms + creates Stripe Transfer + writes payout columns
- Second request: RPC sees `buyer_confirmed` (handled gracefully), edge function sees `payout_released_at IS NOT NULL`, returns `{ success: true, already_released: true }`
- Client treats both as success → shows same alert, sets same state

### State guard (unchanged)
The button only renders when `transferStatus === 'seller_sent'`. After success, `setTransferStatus('buyer_confirmed')` removes the button from the render tree. Even if state update is slow, the edge function handles duplicates safely.

---

## What Remains Untouched

| Component | Modified? |
|---|---|
| `confirm-and-release/index.ts` | NO |
| `confirm_transfer_received` RPC | NO |
| `stripe-webhook/index.ts` | NO |
| `mark_transfer_sent` RPC | NO |
| `handleMarkSent()` in ListingDetailScreen | NO |
| Button UI / styles / layout | NO |
| Transfer status badge | NO |
| Navigation | NO |
| Auth flow | NO |
| Payment flow | NO |
| Other screens | NO |

---

STEP COMPLETE — WAITING FOR NEXT RUN

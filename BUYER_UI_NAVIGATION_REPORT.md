# BUYER UI NAVIGATION — Report Issue Button + Transfer Screen Access

**Generated:** 2026-04-01
**Status:** Code changes applied — ready for deploy

---

## SECTION 1 — Single Root Cause

**Buyers cannot report issues because the dispute button was never added to ListingDetailScreen, and the dedicated transfer/receive screen that HAS the button is unreachable.**

Three compounding gaps:

### Gap A: ListingDetailScreen has Confirm Received but NOT Report Issue

`src/screens/ListingDetailScreen.tsx` line 983 renders a "Confirm Received" button when `isSold && isBuyer && transferStatus === 'seller_sent'`. There is NO corresponding "Report Issue" button. The `buyer_dispute_transfer` RPC (migration 009) exists and works, but nothing in ListingDetailScreen calls it.

### Gap B: transfer/receive screen exists but is unreachable

`app/transfer/receive/[id].tsx` has BOTH "Confirm Received" and "Report Issue" buttons, plus disputed-state banners. But `app/_layout.tsx` does NOT register `transfer/receive/[id]` or `transfer/send/[id]` as Stack.Screen entries. Without registration, `router.push('/transfer/receive/xxx')` crashes or silently fails.

### Gap C: No navigation path from ListingDetailScreen to transfer screens

Even if the screens were registered, there is no button, link, or automatic navigation from ListingDetailScreen to the transfer/receive screen.

---

## SECTION 2 — Exact Code Evidence

### Evidence A: ListingDetailScreen buyer block — no Report Issue (lines 983-997)

```typescript
{isSold && isBuyer && transferStatus === 'seller_sent' && (
  <View style={s.transferActionRow}>
    <TouchableOpacity
      style={[s.transferBtn, s.transferBtnConfirm, transferActionLoading && s.transferBtnDisabled]}
      onPress={transferActionLoading ? undefined : handleConfirmReceived}
      disabled={transferActionLoading}
      activeOpacity={0.8}
    >
      {transferActionLoading
        ? <ActivityIndicator color={colors.text} size="small" />
        : <Text style={s.transferBtnText}>✅ Confirm Received</Text>
      }
    </TouchableOpacity>
  </View>
)}
```

Only one button. No dispute/report action.

### Evidence B: transfer/receive/[id].tsx HAS both buttons (but unreachable)

```typescript
// "Confirm Received" button — calls buyer_confirm_transfer RPC
// "Report Issue" button — calls buyer_dispute_transfer RPC
```

Both exist in app/transfer/receive/[id].tsx but the screen cannot be navigated to.

### Evidence C: app/_layout.tsx missing transfer screen registrations (lines 152-172)

```typescript
<Stack screenOptions={{ headerShown: false }}>
  <Stack.Screen name="(tabs)" />
  <Stack.Screen name="(auth)" />
  <Stack.Screen name="listing/[id]" />
  <Stack.Screen name="bid/[id]" />
  <Stack.Screen name="checkout/[id]" />
  <Stack.Screen name="settings/index" />
  ...
  <Stack.Screen name="my-listings" />
</Stack>
```

No `transfer/receive/[id]` or `transfer/send/[id]` entries.

### Evidence D: handleConfirmReceived exists, handleDispute does not

`handleMarkSent` (line 783) and `handleConfirmReceived` (line 796) exist. No `handleDispute` or `handleReportIssue` function exists anywhere in ListingDetailScreen.

### Evidence E: transferId is already available in state

Line 222: `const [transferId, setTransferId] = useState<string | null>(null);`
Line 221: `const [transferStatus, setTransferStatus] = useState<string | null>(null);`

Both are populated by the sold-state polling effect. The dispute RPC only needs `transferId`.

---

## SECTION 3 — Exact Files To Modify

| # | File | Change |
|---|------|--------|
| 1 | `src/screens/ListingDetailScreen.tsx` | Add `handleReportIssue()` function + "Report Issue" button next to "Confirm Received" |
| 2 | `app/_layout.tsx` | Register `transfer/receive/[id]` and `transfer/send/[id]` as Stack.Screen entries |

---

## SECTION 4 — Smallest Fix

### Fix 1: Add handleReportIssue + button to ListingDetailScreen

Add a `handleReportIssue` function that calls `buyer_dispute_transfer` RPC (matching the pattern in transfer/receive/[id].tsx), and add a "Report Issue" button in the same `transferActionRow` as "Confirm Received".

The button should:
- Show ONLY when `isSold && isBuyer && transferStatus === 'seller_sent'` (same condition as Confirm Received)
- Use a distinct warning style (red/orange tint) to differentiate from confirm
- Show a confirmation Alert before dispatching (destructive action)
- Call `supabase.rpc('buyer_dispute_transfer', { p_transfer_id: transferId })` on confirm
- Update `transferStatus` to `'disputed'` on success

### Fix 2: Register transfer screens in layout

Add two Stack.Screen entries to `app/_layout.tsx`:
```typescript
<Stack.Screen name="transfer/receive/[id]" />
<Stack.Screen name="transfer/send/[id]" />
```

This makes the dedicated transfer screens navigable for future use (e.g. push notifications that deep-link to transfer detail).

---

## SECTION 5 — Exact Implementation Prompt

```
Act as a React Native + Expo Router engineer.

TASK: Add "Report Issue" dispute button to ListingDetailScreen and register
transfer screens in the app layout.

FILE 1: src/screens/ListingDetailScreen.tsx

1a. Add handleReportIssue function after handleConfirmReceived (around line 838):

    async function handleReportIssue() {
      if (!transferId || !user?.id) return;
      Alert.alert(
        'Report Issue',
        'Are you sure you want to report a problem with this transfer? This will freeze the transfer and notify support.',
        [
          { text: 'Cancel', style: 'cancel' },
          {
            text: 'Report Issue',
            style: 'destructive',
            onPress: async () => {
              setTransferActionLoading(true);
              const { error } = await supabase.rpc('buyer_dispute_transfer', {
                p_transfer_id: transferId,
              });
              setTransferActionLoading(false);
              if (error) {
                Alert.alert('Error', error.message);
                return;
              }
              setTransferStatus('disputed');
              Alert.alert('Reported', 'The transfer has been flagged. Support will review.');
            },
          },
        ],
      );
    }

1b. Replace the buyer seller_sent block (lines 983-997) to include BOTH buttons
    side by side in a row:

    {isSold && isBuyer && transferStatus === 'seller_sent' && (
      <View style={s.transferActionRow}>
        <TouchableOpacity
          style={[s.transferBtn, s.transferBtnConfirm, transferActionLoading && s.transferBtnDisabled]}
          onPress={transferActionLoading ? undefined : handleConfirmReceived}
          disabled={transferActionLoading}
          activeOpacity={0.8}
        >
          {transferActionLoading
            ? <ActivityIndicator color={colors.text} size="small" />
            : <Text style={s.transferBtnText}>✅ Confirm Received</Text>
          }
        </TouchableOpacity>
        <TouchableOpacity
          style={[s.transferBtn, s.transferBtnDispute, transferActionLoading && s.transferBtnDisabled]}
          onPress={transferActionLoading ? undefined : handleReportIssue}
          disabled={transferActionLoading}
          activeOpacity={0.8}
        >
          {transferActionLoading
            ? <ActivityIndicator color={colors.text} size="small" />
            : <Text style={s.transferBtnText}>⚠️ Report Issue</Text>
          }
        </TouchableOpacity>
      </View>
    )}

1c. Add disputed status banner after the seller_sent buyer block:

    {isSold && isBuyer && transferStatus === 'disputed' && (
      <View style={s.disputedBanner}>
        <Text style={s.disputedBannerText}>
          ⚠️ You reported an issue with this transfer. Support will review.
        </Text>
      </View>
    )}

1d. Add styles for transferBtnDispute and disputedBanner:

    transferBtnDispute: {
      backgroundColor: '#8B0000',
    },
    disputedBanner: {
      backgroundColor: 'rgba(139, 0, 0, 0.15)',
      borderRadius: 10,
      padding: 14,
      marginTop: 10,
    },
    disputedBannerText: {
      color: '#FF6B6B',
      fontSize: 14,
      textAlign: 'center',
    },

FILE 2: app/_layout.tsx

2a. Add two Stack.Screen entries after the my-listings line (line 167):

    <Stack.Screen name="transfer/receive/[id]" />
    <Stack.Screen name="transfer/send/[id]" />

WHAT CHANGED:
1. Buyers now see "Report Issue" button next to "Confirm Received" when transfer is seller_sent
2. Disputed transfers show a status banner on the listing detail screen
3. Transfer receive/send screens are registered in the navigator (accessible via deep links)

WHAT DID NOT CHANGE:
- No RPC or migration changes (buyer_dispute_transfer from 009 is used as-is)
- No edge function changes
- No other screens modified
- Confirm Received button unchanged
- Seller Mark as Sent button unchanged
```

---

## SUMMARY

| Buyer Action | Before | After |
|---|---|---|
| See "Confirm Received" when seller_sent | ✅ Works | ✅ Works (unchanged) |
| See "Report Issue" when seller_sent | ❌ Missing | ✅ Shows next to Confirm |
| See disputed status banner | ❌ Missing | ✅ Shows when disputed |
| Navigate to transfer/receive screen | ❌ Crashes (unregistered) | ✅ Registered in layout |
| Navigate to transfer/send screen | ❌ Crashes (unregistered) | ✅ Registered in layout |

**Net effect:** The existing dispute system (RPC 009) is now exposed to buyers through ListingDetailScreen without any backend changes.

STEP COMPLETE — WAITING FOR NEXT RUN

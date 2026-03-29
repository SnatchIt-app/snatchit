# SnatchIt Beta — Copy-Paste Execution Prompts

> **How to use:** Copy each prompt below and paste it directly into Claude Code. Run them in the order listed in FINAL EXECUTION ORDER at the bottom.

---

## SECTION 1 — Critical Prompts (Run First)

These unblock beta. Nothing else matters until these are done.

---

### PROMPT C1 — Add stripe_connect_id Column

```
You are editing a production Supabase project. Do NOT make any code changes. ONLY output the exact SQL I need to run in the Supabase SQL Editor.

Context:
The `profiles` table is missing the `stripe_connect_id` column. This is causing the "Set Up Payouts" flow to crash because the edge function `create-connect-account` tries to SELECT this column and it doesn't exist.

Task:
Give me a single SQL statement that adds `stripe_connect_id text` to the `profiles` table. Use `ADD COLUMN IF NOT EXISTS` for safety.

Do NOT add any other columns (no stripe_connect_status, no stripe_payouts_enabled, no stripe_charges_enabled). The existing code only reads stripe_connect_id. Match what the code expects, nothing more.

Output: just the SQL. Nothing else.
```

---

### PROMPT C2 — Fix Placeholder Stripe Publishable Key

```
You are editing an existing React Native + Expo project. Do NOT change the UI design. Do NOT add new features.

Context:
The file `.env.development` currently has a placeholder Stripe key: `pk_test_YOUR_TEST_KEY_HERE`. This prevents Stripe PaymentSheet from initializing.

Task:
1. Open `.env.development`
2. Show me the current EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY line
3. Tell me exactly what I need to replace it with (I will provide my actual key)
4. Also check `.env.production` and `.env` for the same placeholder pattern and show me those too

Do NOT modify any code files. Only show me the env files that need manual key replacement.
```

---

### PROMPT C3 — Verify Stripe Secret Key in Supabase Secrets

```
You are helping me verify my Supabase Edge Function configuration. Do NOT modify any code.

Context:
The edge functions `create-payment-intent`, `confirm-payment`, `create-connect-account`, and `stripe-webhook` all require these environment variables:
- STRIPE_SECRET_KEY
- STRIPE_WEBHOOK_SECRET (webhook only)
- SUPABASE_URL
- SUPABASE_SERVICE_ROLE_KEY

Task:
Give me the exact CLI commands to:
1. List all currently set Supabase secrets (to check what's already configured)
2. Set STRIPE_SECRET_KEY if it's missing
3. Set STRIPE_WEBHOOK_SECRET if it's missing

Use the `supabase secrets` CLI. Give me the exact commands to copy-paste. Include placeholders like sk_test_REPLACE_ME where I need to insert my actual keys.

Do NOT modify any code or edge function files.
```

---

### PROMPT C4 — Verify Stripe Connect Is Enabled

```
You are helping me verify my Stripe Dashboard configuration. Do NOT modify any code.

Context:
SnatchIt uses Stripe Connect Express accounts so sellers can receive payouts. The edge function `create-connect-account` creates Express accounts and generates onboarding links.

Task:
Give me a step-by-step checklist of what I need to verify/enable in my Stripe Dashboard:
1. Where to enable Connect
2. How to verify Express accounts are enabled
3. Where to check/register webhook endpoints
4. What webhook events must be registered (payment_intent.succeeded, payment_intent.payment_failed)
5. How to verify the webhook signing secret matches what's in Supabase secrets

Be specific with Stripe Dashboard navigation paths (e.g., "Settings → Connect → ..."). Do NOT modify any code.
```

---

## SECTION 2 — Cleanup Prompts (Remove Dead Code)

---

### PROMPT D1 — Delete Dead Payout Method Screen

```
You are editing an existing production codebase. Do NOT redesign anything. Do NOT change the UI design. Do NOT change styling.

Context:
The file `app/settings/payout-method.tsx` is dead code — it's a 149-line placeholder that says "coming soon" but has been completely superseded by `app/settings/payout-setup.tsx`. Having two payout screens is confusing.

Task:
1. Delete the file `app/settings/payout-method.tsx`
2. In `app/settings/index.tsx`:
   - Remove '/settings/payout-method' from the SettingsRoute type union (line 38)
   - Change the "Payout Method" row (line 162-167) to navigate to '/settings/payout-setup' instead of '/settings/payout-method'
   - Update the label from "Payout Method" to "Payout Setup"
3. In `app/_layout.tsx`:
   - Remove the Stack.Screen for "settings/payout-method" (line 82)
   - Add a Stack.Screen for "settings/payout-setup" if it doesn't already exist

Important constraints:
- Do NOT change any other settings rows
- Do NOT change styling or layout
- Do NOT modify payout-setup.tsx
- Keep all existing logic intact
- Show me ONLY the exact changes made
```

---

### PROMPT D2 — Hide Wallet Balance Display

```
You are editing an existing production codebase. Do NOT redesign anything. Do NOT remove the wallet_balance column from the database. Do NOT delete any components.

Context:
The profile screen (`app/(tabs)/profile.tsx`) displays a "WALLET BALANCE" section. Displaying a wallet balance implies an in-app wallet system, which requires money transmitter licenses in most US states. For beta, this is a legal liability with zero user value.

Task:
1. In `app/(tabs)/profile.tsx`, hide the wallet balance display:
   - Find the line that shows `{formatMoney(walletBal)}` (around line 376)
   - Replace the displayed balance with a static string like "—" or hide the balance amount
   - OR: Change the wallet label from "WALLET BALANCE" to "PAYMENT & PAYOUTS" and remove the dollar amount display entirely
2. Keep the Payment/Payout toggle tabs below it — those are useful
3. Do NOT remove the wallet_balance from the profile query or the Profile type — other code may reference it
4. Do NOT change the card styling or layout

Important: This is a minimal change to reduce legal risk. Do NOT redesign the wallet section. Just hide or neutralize the dollar amount.
Show me ONLY the exact changes made.
```

---

## SECTION 3 — Payment Flow Prompts

---

### PROMPT P1 — Verify Buyer Checkout Flow Compiles

```
You are auditing an existing React Native + Expo codebase. Do NOT make any changes unless you find a bug that would crash the app.

Context:
The buyer checkout flow lives in `app/checkout/[id].tsx`. It:
1. Calls `createPaymentIntent()` from `src/lib/payments.ts`
2. Initializes Stripe PaymentSheet with the clientSecret
3. Presents PaymentSheet for the user to pay
4. On success, calls `mark_listing_sold` or `complete_auction_payment` RPC
5. On unmount without completing, calls `release_reservation` RPC

Task:
1. Read `app/checkout/[id].tsx` completely
2. Read `src/lib/payments.ts` completely
3. Read `src/config/app.ts` to verify STRIPE_PUBLISHABLE_KEY is read from env
4. Identify any issues that would cause a runtime crash or payment failure
5. Specifically check:
   - Is the edge function URL correctly constructed?
   - Is the auth token being passed correctly?
   - Are there null/undefined values that could crash?
   - Is error handling present for all failure paths?

If you find crash-level bugs, fix them. If you only find minor issues, list them but do NOT change code.
Output: List of findings with file names and line numbers.
```

---

### PROMPT P2 — Verify Seller Payout Setup Flow

```
You are auditing an existing React Native + Expo codebase. Do NOT make any changes unless you find a bug that would crash the app.

Context:
The seller payout setup flow lives in `app/settings/payout-setup.tsx`. It:
1. Checks if the user already has a `stripe_connect_id` in their profile
2. If not, calls the `create-connect-account` edge function
3. Opens the returned Stripe onboarding URL via Linking.openURL()
4. When user returns, re-checks the profile for stripe_connect_id

The edge function lives in `supabase/functions/create-connect-account/index.ts`. It:
1. Authenticates the user via JWT
2. Checks/creates a Stripe Express account
3. Saves the account ID to profiles.stripe_connect_id
4. Creates an account_link for onboarding
5. Returns the onboarding URL

Task:
1. Read both files completely
2. Verify the edge function URL is correctly constructed in payout-setup.tsx
3. Verify the auth header is being passed correctly
4. Verify the edge function properly handles the case where stripe_connect_id already exists (re-onboarding)
5. Check that the deep link return URL (snatchit://settings/payout-setup) will work with the app's scheme config in app.json
6. Identify any crash-level bugs

If you find crash-level bugs, fix them. Otherwise, list findings only.
```

---

### PROMPT P3 — Verify Stripe Webhook Handler

```
You are auditing an existing Supabase Edge Function. Do NOT make any changes unless you find a critical bug.

Context:
The webhook handler lives in `supabase/functions/stripe-webhook/index.ts`. It handles:
- payment_intent.succeeded: marks payment as succeeded, marks listing sold, creates transfer record, sends Stripe Transfer to seller, sends push notifications
- payment_intent.payment_failed: marks payment as failed, cancels Buy Now reservation

Task:
1. Read the entire webhook file
2. Verify:
   - Webhook signature verification is implemented correctly (HMAC-SHA256)
   - The succeeded handler properly updates the payments table
   - The succeeded handler properly calls the correct RPC (mark_listing_sold for buy_now, complete_auction_payment for auction)
   - The Transfer to seller's Connect account uses the correct amount (seller gets amount, platform keeps service_fee)
   - The failed handler properly releases Buy Now reservations
   - Error handling doesn't crash the webhook (should return 200 even on internal errors to prevent Stripe retries)
3. Identify any issues that would cause payments to silently fail or money to be lost

If you find critical bugs (money loss, silent failures), fix them. Otherwise, list findings only.
```

---

### PROMPT P4 — Verify PaymentIntent Edge Function

```
You are auditing an existing Supabase Edge Function. Do NOT make any changes unless you find a critical bug.

Context:
The PaymentIntent creation lives in `supabase/functions/create-payment-intent/index.ts`. It:
1. Authenticates via JWT
2. Validates listing exists and buyer != seller
3. Checks idempotency (no duplicate payments)
4. Creates Stripe PaymentIntent with amount + 5% service fee
5. Inserts a payment record in the payments table
6. Returns clientSecret to the frontend

Task:
1. Read the entire file
2. Verify:
   - JWT authentication is correct
   - Buy Now mode requires listing status='reserved'
   - Auction mode requires auction_status='ended' and winner matches
   - Amount calculation is correct (base amount + 5% fee, all in cents)
   - Idempotency check prevents double charges
   - If DB insert fails, the orphaned PaymentIntent is cancelled
   - The response includes clientSecret and paymentIntentId
3. Look for any issue that could cause: double charges, wrong amounts, or unauthorized payments

Fix only critical bugs. List everything else.
```

---

## SECTION 4 — Testing Prompts

---

### PROMPT T1 — Test Deep Link Return from Stripe Onboarding

```
You are auditing an existing React Native + Expo project. Do NOT make changes unless needed to fix a broken flow.

Context:
When a seller completes Stripe Connect onboarding in their browser, Stripe redirects to `snatchit://settings/payout-setup`. This should bring the user back to the payout setup screen in the app.

Task:
1. Check `app.json` for the `scheme` field — verify it's set to "snatchit"
2. Check if there's any Expo linking configuration that handles the snatchit:// scheme
3. Check if Expo Router automatically handles deep links to /settings/payout-setup based on file-based routing
4. Verify that when the user returns to the payout-setup screen, `checkStatus()` is called (it should re-query the profile to see if stripe_connect_id was saved)

If the deep link routing won't work with the current setup, tell me exactly what's missing and give me the minimal fix. If it should work automatically with Expo Router, confirm that.

Do NOT add any new screens or features.
```

---

### PROMPT T2 — Verify fmt$ Null Guard

```
You are auditing a specific bug fix in an existing codebase. Do NOT make changes unless the fix is incomplete.

Context:
Earlier we fixed a crash in `src/screens/ListingDetailScreen.tsx` where the `fmt$` function received null instead of a number, causing `Cannot read property 'toLocaleString' of null`.

The fix changed the function signature from `fmt$(n: number)` to `fmt$(n: number | null | undefined)` with a null guard.

Task:
1. Read `src/screens/ListingDetailScreen.tsx` and find the `fmt$` function
2. Verify the null guard is in place
3. Search the entire file for ALL calls to `fmt$()` and verify none can still receive null/undefined without the guard catching it
4. Also check `app/checkout/[id].tsx` which has its own local `fmt$` function — verify it also has a null guard (or doesn't need one)

If the checkout screen's fmt$ is missing a null guard and could receive null, add one. Otherwise, confirm everything is safe.
```

---

### PROMPT T3 — Check for Other Potential Null Crashes

```
You are auditing an existing React Native codebase for null/undefined crashes. Do NOT redesign anything. Only fix crash-level bugs.

Context:
We already fixed one null crash in ListingDetailScreen (fmt$ receiving null). There may be similar issues elsewhere in the app where data from Supabase queries returns null for optional fields.

Task:
Search these files for potential null/undefined crashes:
1. `src/screens/ListingDetailScreen.tsx` — any property access on listing or bid data that could be null
2. `app/checkout/[id].tsx` — any property access on params or payment data that could be null
3. `app/(tabs)/profile.tsx` — any property access on profile data that could be null
4. `app/(tabs)/home.tsx` — any property access on listing data that could be null

Look specifically for:
- `.toLocaleString()` or `.toString()` on nullable values
- Property access chains without optional chaining (e.g., `data.field.subfield` instead of `data?.field?.subfield`)
- Array access without length checks

Fix any crash-level issues. Ignore minor warnings. Show only the changes made.

Important: Do NOT change UI, styling, or logic. Only add null guards where needed to prevent crashes.
```

---

## SECTION 5 — Optional (If Time Allows)

---

### PROMPT O1 — Add Manual Refresh Button to Payout Setup

```
You are editing an existing React Native screen. Do NOT redesign the UI. Do NOT change styling beyond what's absolutely necessary.

Context:
In `app/settings/payout-setup.tsx`, after a seller completes Stripe onboarding in their browser, the app should detect that stripe_connect_id was saved. Currently it relies on:
1. Deep link return (snatchit://settings/payout-setup)
2. A setTimeout that re-checks after 2 seconds

If the deep link doesn't work reliably, the user has no way to manually refresh.

Task:
Add a small "Tap to refresh status" text button below the main action button that calls `checkStatus()` when pressed. This gives sellers a manual fallback.

Constraints:
- Place it below the existing action button
- Style it as a subtle text link (not a big button) — use colors.textMuted, fontSize.xs
- Only show it when `connected` is false (once connected, no need to refresh)
- Do NOT change any other UI elements
- Do NOT change the handleSetup function
- Do NOT add any new state variables

Show me ONLY the exact changes made.
```

---

### PROMPT O2 — Verify Push Notification Edge Function

```
You are auditing an existing Supabase Edge Function. Do NOT make changes unless you find a critical bug.

Context:
`supabase/functions/send-push/index.ts` sends push notifications via the Expo Push API. It's called from the stripe-webhook after payment events.

Task:
1. Read the send-push edge function
2. Verify it correctly calls the Expo Push API
3. Verify it handles errors gracefully (a push notification failure should never block payment processing)
4. Check if the webhook calls send-push in a fire-and-forget pattern (it should not await the result or let push failures crash the webhook)

List findings only. Fix only if push failures could crash the webhook.
```

---

### PROMPT O3 — Add projectId to app.json for Push Notifications

```
You are editing an existing Expo project configuration. Do NOT change any other settings.

Context:
The app shows this warning: `[usePushToken] Error: No "projectId" found`. Push notifications require a projectId in app.json to generate push tokens.

Task:
1. Check `app.json` for an existing `extra.eas.projectId` field
2. If it's missing, show me exactly where to add it and what format it needs
3. The projectId comes from EAS — show me the command to find my project ID

Do NOT add the actual ID — just show me the structure and the command to get it. I'll fill it in.
```

---

## FINAL EXECUTION ORDER

Run these prompts in this exact order. Each one takes 2-10 minutes.

### Day 1 — Unblock (30 minutes total)

| # | Prompt | What it does | Time |
|---|--------|-------------|------|
| 1 | C1 | Add stripe_connect_id column (SQL) | 1 min |
| 2 | C2 | Fix placeholder Stripe key | 2 min |
| 3 | C3 | Verify/set Supabase secrets | 5 min |
| 4 | C4 | Verify Stripe Dashboard config | 10 min |
| 5 | D1 | Delete dead payout-method.tsx | 5 min |
| 6 | D2 | Hide wallet balance (legal risk) | 5 min |

### Day 1-2 — Verify Flows (45 minutes total)

| # | Prompt | What it does | Time |
|---|--------|-------------|------|
| 7 | P1 | Audit buyer checkout flow | 10 min |
| 8 | P2 | Audit seller payout setup flow | 10 min |
| 9 | P3 | Audit Stripe webhook handler | 10 min |
| 10 | P4 | Audit PaymentIntent edge function | 10 min |
| 11 | T1 | Verify deep link return works | 5 min |

### Day 2-3 — Stability (20 minutes total)

| # | Prompt | What it does | Time |
|---|--------|-------------|------|
| 12 | T2 | Verify fmt$ null guard | 5 min |
| 13 | T3 | Scan for other null crashes | 10 min |
| 14 | O1 | Add manual refresh button (optional) | 5 min |

### Day 3+ — If Time Allows

| # | Prompt | What it does | Time |
|---|--------|-------------|------|
| 15 | O2 | Audit push notification function | 5 min |
| 16 | O3 | Fix push notification projectId | 5 min |

---

**Total execution time: ~2 hours of Claude Code prompts.**

After running all prompts through Day 2-3, you should have a fully working payment flow ready for beta testing.

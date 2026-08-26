# SnatchIt Payments System — Engineering Audit Report

**Date:** March 20, 2026
**Scope:** Payment Methods (buyers) + Payout Methods (sellers) + Root-cause analysis of "Set Up Payouts" failure

---

## A. Current State Audit

### Files Inventoried

**Frontend (React Native / Expo)**

| File | Purpose | Status |
|------|---------|--------|
| `app/settings/payout-setup.tsx` (176 lines) | Stripe Connect onboarding UI | Implemented — calls edge function, opens onboarding URL |
| `app/settings/payment-methods.tsx` (323 lines) | Payment method info screen (read-only) | Implemented — shows Apple Pay / Google Pay / Card availability |
| `app/settings/payout-method.tsx` (150 lines) | Legacy placeholder — says "coming soon" | Dead code — superseded by payout-setup.tsx |
| `app/(tabs)/profile.tsx` (900+ lines) | Profile screen with wallet card + payout button | Implemented — reads `stripe_connect_id` from profiles |
| `app/checkout/[id].tsx` (545 lines) | Checkout flow (PaymentSheet) | Implemented — Buy Now + Auction payment |
| `src/lib/payments.ts` (92 lines) | Payment intent creation + confirmation client | Implemented |
| `src/config/app.ts` (17 lines) | STRIPE_PUBLISHABLE_KEY + fee rate config | Implemented |
| `app/_layout.tsx` (118 lines) | StripeProvider wrapper | Implemented |

**Backend (Supabase Edge Functions — Deno)**

| File | Purpose | Status |
|------|---------|--------|
| `supabase/functions/create-payment-intent/index.ts` (248 lines) | Creates Stripe PaymentIntent | Deployed |
| `supabase/functions/confirm-payment/index.ts` (101 lines) | Marks payment succeeded (best-effort) | Deployed |
| `supabase/functions/stripe-webhook/index.ts` (274 lines) | Handles payment_intent.succeeded/failed | Deployed |
| `supabase/functions/create-connect-account/index.ts` (122 lines) | Creates Stripe Express account + onboarding link | Deployed |
| `supabase/functions/send-push/index.ts` | Push notifications via Expo API | Deployed |
| `supabase/functions/auto-finalize-auctions/index.ts` | Finalizes expired auctions | Deployed |

**Database (Supabase / PostgreSQL)**

| Table | Key Columns | Status |
|-------|-------------|--------|
| `profiles` | id, display_name, phone_number, avatar_path, is_verified_buyer, is_verified_seller, wallet_balance | Schema exists |
| `profiles.stripe_connect_id` | text — Stripe Express account ID | **NOT IN SCHEMA OR MIGRATIONS** |
| `payments` | id, listing_id, buyer_id, seller_id, amount, service_fee, total, stripe_payment_intent_id, status, mode | Schema exists |
| `transfers` | listing_id, payment_id, seller_id, buyer_id, status, transfer_method, expires_at | Referenced in webhook — schema likely exists |

### What IS Implemented

1. Full buyer checkout flow: reserve listing, create PaymentIntent, present PaymentSheet, mark sold
2. Stripe webhook handling for payment_intent.succeeded and payment_intent.payment_failed
3. Auto-payout to seller via Stripe Transfer (in webhook) — if seller has stripe_connect_id
4. Payout setup screen UI (payout-setup.tsx) — calls create-connect-account edge function
5. Edge function to create Stripe Express account and generate onboarding link
6. Payment methods info screen (read-only — no saved card management)
7. Profile screen reads stripe_connect_id to show payout status

### What Is MISSING

1. **`stripe_connect_id` column on profiles table** — not in schema.sql, not in any migration
2. **No `stripe_connect_status` tracking** — no way to know if onboarding is complete, pending, or restricted
3. **No Stripe account.updated webhook handler** — app never learns when onboarding completes or account status changes
4. **No Stripe Customer object per user** — buyers have no persistent Stripe identity, so saved payment methods don't carry across sessions
5. **No SetupIntent flow** — buyers can't save cards outside of checkout
6. **No `stripe_customer_id` column on profiles** — nowhere to store buyer's Stripe Customer ID
7. **Payment methods screen is purely informational** — no ability to add, view, or manage saved cards
8. **No deep link handling for `snatchit://settings/payout-setup`** — the return/refresh URLs in the onboarding flow use this scheme but there's no evidence the Expo linking config handles it
9. **Transfer expiry enforcement missing** — expires_at is set but no cron job cleans up expired transfers
10. **No refund flow** — schema supports refunded_at but no UI or edge function exists

---

## B. Why "Set Up Payouts" Is Failing — Root-Cause Analysis

### The Failure Chain

**Step 1: User taps "Set Up Payouts"**
File: `app/settings/payout-setup.tsx`, line 39 (`handleSetup`)

**Step 2: Gets auth session**
Lines 42-47: `supabase.auth.getSession()` — this likely succeeds (user is logged in)

**Step 3: Calls edge function**
Lines 50-61: `fetch(supabaseUrl + '/functions/v1/create-connect-account', { ... })`
Sends JWT in Authorization header + apikey header + body with refresh_url and return_url

**Step 4: Edge function executes**
File: `supabase/functions/create-connect-account/index.ts`

Here is where it fails. The edge function does this at line 62-66:

```typescript
const { data: profile, error: profileErr } = await supabase
  .from('profiles')
  .select('stripe_connect_id')
  .eq('id', userId)
  .single();
```

### The Root Cause: `stripe_connect_id` Column Does Not Exist

The `profiles` table was created in `schema.sql` with columns: `id`, `created_at`, `full_name`, `phone`. Migration `001_profile_additions.sql` adds: `phone_number`, `is_verified_buyer`, `is_verified_seller`, `wallet_balance`.

**No migration ever adds `stripe_connect_id` to the profiles table.**

When the edge function runs `.select('stripe_connect_id')`, one of two things happens:

1. **If the column doesn't exist at all:** PostgREST returns a 400 error with message like "column profiles.stripe_connect_id does not exist". The edge function catches this at line 68 and returns `{ error: 'Profile not found' }` with status 404.

2. **If the column was manually added but has no RLS policy for service_role:** The service_role key bypasses RLS, so this shouldn't be the issue — but if the column was never added, option 1 is the failure mode.

**The frontend receives a non-200 response** at line 65-66:
```typescript
if (!res.ok) {
  Alert.alert('Error', data.error || 'Failed to set up payouts');
}
```

This produces the exact error the user sees: **"Failed to set up payouts"**.

### Secondary Failure Mode (if column was manually added)

If `stripe_connect_id` was manually added to the DB but the edge function still fails, the next failure point would be the Stripe API call at line 79:

```typescript
const account = await stripePost('/accounts', {
  'type': 'express',
  'metadata[user_id]': userId,
});
```

This would fail if:
- `STRIPE_SECRET_KEY` is not set in Supabase Edge Function secrets
- The Stripe key is a test key but Express accounts aren't enabled in test mode
- The Stripe account doesn't have Connect enabled

### Verification Steps (for the developer)

Run this SQL in Supabase SQL Editor to confirm:
```sql
SELECT column_name FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'profiles'
ORDER BY ordinal_position;
```

If `stripe_connect_id` is not in the results, that confirms the root cause.

Check edge function logs:
```bash
supabase functions logs create-connect-account --project-ref YOUR_PROJECT_REF
```

---

## C. Recommended Payment Methods Architecture (Buyers)

### Current State
The payment-methods screen is informational only. Buyers enter card details fresh at every checkout via Stripe PaymentSheet. Stripe Link may save cards on Stripe's side, but the app has no visibility into this.

### Recommended Architecture

**Phase 1 (Pre-Launch — do this now):**
Leave the current informational screen as-is. Stripe PaymentSheet + Link already handles card saving on Stripe's side. This is sufficient for launch.

**Phase 2 (Post-Launch — when you have traction):**

1. **Create a Stripe Customer per user**
   - When: On first checkout (lazy creation) or at signup
   - Edge function: `create-stripe-customer` — creates Stripe Customer, stores ID in profiles
   - Database: Add `stripe_customer_id text` to profiles table
   - Benefit: All PaymentIntents attached to a Customer → saved payment methods persist

2. **Pass Customer ID to PaymentSheet**
   - Modify `create-payment-intent` to include `customer` param on the PaymentIntent
   - Modify checkout to pass `customerId` to `initPaymentSheet`
   - PaymentSheet will then show previously used cards automatically

3. **Saved Cards Display**
   - Edge function: `list-payment-methods` — calls Stripe `GET /v1/customers/{id}/payment_methods`
   - Frontend: Show list of saved cards with last4, brand, expiry
   - Default method: Store `default_payment_method_id` in profiles or let Stripe handle via Customer default

4. **Add Card Outside Checkout**
   - Edge function: `create-setup-intent` — creates Stripe SetupIntent for the Customer
   - Frontend: Use `initPaymentSheet` with SetupIntent mode (not PaymentIntent)
   - Result: Card saved to Customer without a charge

### Data Model (Phase 2)

```
profiles table additions:
  stripe_customer_id  text  -- Stripe Customer ID (cus_...)
```

No need to store card details locally. Stripe is the source of truth for payment methods. The app only stores the Customer ID to look them up.

### What Should NOT Be Built

- Do NOT build a custom card input form — always use Stripe PaymentSheet
- Do NOT store card numbers, CVVs, or full card details anywhere
- Do NOT build a "wallet" that holds money — use Stripe's infrastructure
- Do NOT implement ACH/bank payments yet — cards + Apple Pay + Google Pay is sufficient

---

## D. Recommended Payout Methods Architecture (Sellers)

### Connect Account Type
**Stripe Connect Express** — already chosen, correct for this use case. Express accounts give you:
- Pre-built onboarding UI (hosted by Stripe)
- Stripe handles KYC, identity verification, tax forms
- Platform controls payout timing
- Lower compliance burden on SnatchIt

### Complete Flow

**1. User taps "Set Up Payouts"**
```
payout-setup.tsx → handleSetup() → POST /functions/v1/create-connect-account
```

**2. Edge function creates account + onboarding link**
```
create-connect-account:
  1. Auth: verify JWT → get userId
  2. Check profiles.stripe_connect_id
  3. If null: POST /v1/accounts (type=express) → save acct_... to profiles
  4. POST /v1/account_links (type=account_onboarding) → get onboarding URL
  5. Return { url, account_id }
```

**3. User completes onboarding in browser**
Stripe handles: identity verification, bank account entry, tax info, business details

**4. User returns to app**
Deep link: `snatchit://settings/payout-setup`
App re-checks profiles.stripe_connect_id → shows "Connected" if account exists

**5. Stripe sends account.updated webhook (MISSING — MUST ADD)**
```
stripe-webhook handles account.updated:
  1. Extract account ID from event
  2. Check charges_enabled, payouts_enabled, details_submitted
  3. Update profiles: stripe_connect_status = 'active' | 'pending' | 'restricted'
```

### Account Status States

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  not_started │───▶│   pending    │───▶│    active    │
│              │    │  (onboarding │    │  (charges +  │
│ No acct ID   │    │   started)   │    │   payouts    │
│              │    │              │    │   enabled)   │
└──────────────┘    └──────┬───────┘    └──────────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │  restricted  │
                    │ (needs more  │
                    │    info)     │
                    └──────────────┘
```

### Database Fields Needed

```sql
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS stripe_connect_id       text,       -- acct_...
  ADD COLUMN IF NOT EXISTS stripe_connect_status   text        -- 'pending' | 'active' | 'restricted'
    NOT NULL DEFAULT 'not_started',
  ADD COLUMN IF NOT EXISTS stripe_payouts_enabled  boolean     -- from Stripe account object
    NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS stripe_charges_enabled  boolean     -- from Stripe account object
    NOT NULL DEFAULT false;
```

### UI States in payout-setup.tsx

| stripe_connect_status | UI Display | Button Label | Button Action |
|----------------------|------------|--------------|---------------|
| not_started (null connect_id) | "Set Up Payouts" + bank icon | "Set Up Payouts" | Create account + open onboarding |
| pending | "Almost There" + clock icon | "Resume Setup" | Create new account_link (same account) |
| active | "Payouts Connected" + checkmark | "Manage Payouts" | Open Stripe Express dashboard link |
| restricted | "Action Required" + warning icon | "Update Details" | Create new account_link (same account) |

### Onboarding Link Expiration

Stripe account_links expire after a few minutes. If a user clicks "Resume Setup", the edge function must generate a fresh link every time — never cache onboarding URLs.

For "Manage Payouts" (already onboarded), generate a Stripe Express dashboard login link instead:
```
POST /v1/accounts/{acct_id}/login_links
```

### Auto-Payout Flow (Already Implemented)

The stripe-webhook already handles this correctly:
1. payment_intent.succeeded fires
2. Webhook checks seller's stripe_connect_id
3. Creates Stripe Transfer to seller's Connect account
4. Stripe handles actual bank deposit (T+2 business days typical)

---

## E. Required Backend Pieces

### Edge Functions to Create

| Function | Purpose | Priority |
|----------|---------|----------|
| ~~create-connect-account~~ | Already exists | N/A |
| `connect-dashboard-link` | Generate Stripe Express dashboard login link for existing connected sellers | P1 |

### Edge Functions to Modify

| Function | Change | Priority |
|----------|--------|----------|
| `create-connect-account` | After creating account, set stripe_connect_status = 'pending' | P0 |
| `stripe-webhook` | Add handler for `account.updated` event → sync status fields | P0 |

### Stripe Webhook Events to Register

Currently registered: `payment_intent.succeeded`, `payment_intent.payment_failed`

**Must add:** `account.updated`

Register in Stripe Dashboard → Webhooks → select the endpoint → add event type.

---

## F. Required Database Pieces

### Migration 002 (CRITICAL — P0)

```sql
-- Migration 002: Add Stripe Connect columns to profiles
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS stripe_connect_id       text,
  ADD COLUMN IF NOT EXISTS stripe_connect_status   text NOT NULL DEFAULT 'not_started',
  ADD COLUMN IF NOT EXISTS stripe_payouts_enabled  boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS stripe_charges_enabled  boolean NOT NULL DEFAULT false;

-- Index for webhook lookups (find user by their Connect account ID)
CREATE INDEX IF NOT EXISTS idx_profiles_stripe_connect_id
  ON public.profiles (stripe_connect_id)
  WHERE stripe_connect_id IS NOT NULL;
```

### Migration 003 (Phase 2 — Post-Launch)

```sql
-- Migration 003: Add Stripe Customer ID for saved payment methods
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS stripe_customer_id text;

CREATE INDEX IF NOT EXISTS idx_profiles_stripe_customer_id
  ON public.profiles (stripe_customer_id)
  WHERE stripe_customer_id IS NOT NULL;
```

### RLS Notes

The existing RLS policy `"profiles: owner update"` allows users to update their own profile. However, the edge functions use `SUPABASE_SERVICE_ROLE_KEY` which bypasses RLS entirely — so the edge functions can update any profile's stripe_connect_id. This is correct and secure because only the edge function (server-side) writes these fields, never the client.

---

## G. Recommended Implementation Order

### Sprint 1 — Fix the Blocker (Day 1)

1. **Run Migration 002** — add stripe_connect_id + status columns to profiles
2. **Verify edge function secrets** — confirm STRIPE_SECRET_KEY is set in Supabase
3. **Test "Set Up Payouts"** — should now create Express account and open onboarding
4. **Verify deep link** — confirm `snatchit://settings/payout-setup` returns to the app

### Sprint 2 — Payout Status Tracking (Day 2-3)

5. **Add `account.updated` webhook handler** — sync charges_enabled, payouts_enabled, status to profiles
6. **Register `account.updated` in Stripe Dashboard** webhook config
7. **Update payout-setup.tsx** — read status fields, show appropriate UI states
8. **Add `connect-dashboard-link` edge function** — for "Manage Payouts" button when already connected

### Sprint 3 — Buyer Payment Methods (Post-Launch)

9. **Run Migration 003** — add stripe_customer_id to profiles
10. **Create `create-stripe-customer` edge function** — lazy creation on first checkout
11. **Modify `create-payment-intent`** — attach Customer to PaymentIntent
12. **Update payment-methods.tsx** — show saved cards from Stripe

### Sprint 4 — Hardening (Post-Launch)

13. **Add transfer expiry cron job** — clean up transfers past expires_at
14. **Add refund flow** — edge function + UI
15. **Remove payout-method.tsx** — dead code cleanup

---

## H. What Should NOT Be Built Yet

1. **Custom card input UI** — Stripe PaymentSheet handles this better and keeps you PCI compliant
2. **In-app wallet / balance system** — adds massive complexity and regulatory burden for zero user value at this stage
3. **Standard Connect accounts** — Express is correct for a marketplace; Standard gives sellers too much control and creates support burden
4. **ACH / bank transfer payments** — cards + Apple Pay + Google Pay covers 99% of your Miami Music Week audience
5. **Multi-currency support** — USD only for now
6. **Subscription / recurring payments** — SnatchIt is transactional, not subscription-based
7. **Saved card management UI** — defer until you have Stripe Customer IDs (Phase 2); Stripe Link already does this transparently
8. **Payout scheduling controls** — let Stripe handle payout timing on Express accounts (default: daily rolling)
9. **Custom payout amounts** — platform takes 5% fee, rest goes to seller automatically via Transfer; don't add manual payout controls
10. **Tax form generation** — Stripe Connect handles 1099s for Express accounts automatically

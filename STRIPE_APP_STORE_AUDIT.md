# Snatch It — Senior iOS / Stripe Marketplace Audit

**Audit date:** 2026-05-10
**Auditor mode:** senior iOS App Store compliance + fintech/marketplace payments architect.
**Discipline:** `security-audit` + `verification-before-completion`. Every finding cites a file path and line number; nothing asserted without source evidence.

---

## Important reframing — actual stack vs. assumed stack

The task brief assumed the app is **Native iOS (Swift/SwiftUI)** with **Stripe iOS SDK** directly. Reality:

| Brief assumption | Verified reality | Evidence |
|---|---|---|
| Native iOS / Swift / SwiftUI | **Expo SDK 54 / React Native 0.81 / Hermes** | `package.json:13–48`, `app.json` |
| Stripe iOS SDK | **`@stripe/stripe-react-native` 0.50.3** (which bundles Stripe iOS SDK 24.19.0) | `package.json`, `ios/Podfile.lock` shows `Stripe (24.19.0)` |
| Vercel-hosted edge functions | **Supabase Edge Functions (Deno)** | `supabase/functions/*/index.ts` (uses `Deno.env.get`) |
| PassKit / Apple Wallet for tickets | **No PassKit code anywhere**; transfer model is platform-to-platform manual transfer | `grep PassKit/pkpass` → 0 matches; `src/types/index.ts:34` only `mobile_transfer | email` |

The audit below treats the actual stack as the source of truth. Where a check is platform-specific (e.g., StoreKit imports), I check the React Native / iOS prebuild equivalents.

---

## SECTION 1 — Apple In-App Purchase Avoidance

### 1.1 StoreKit / IAP imports in production code

**What & why:** Apple Guideline 3.1.1 / 3.1.3(e). Importing StoreKit alongside Stripe is a confusion signal to reviewers; for a real-world goods marketplace it should not be present at all.

**Evidence:** `grep -rn "StoreKit\|SKPaymentQueue\|SKProduct\|SKPayment\|RevenueCat\|StoreKit2\|Product\.purchase\|expo-in-app-purchases\|react-native-iap" app src supabase package.json` → **0 matches**.

**Status: ✅ PASS**

### 1.2 IAP capability in Info.plist / entitlements / pbxproj

**Evidence:** `grep -rn "in-app-purchase\|InAppPurchase\|StoreKit\.framework" ios/snatchit/Info.plist ios/snatchit/snatchit.entitlements ios/snatchit.xcodeproj/project.pbxproj` → **0 matches**. `ios/snatchit/snatchit.entitlements` only declares `aps-environment` and `com.apple.developer.in-app-payments` (Apple Pay, NOT IAP).

**Status: ✅ PASS**

### 1.3 IAP/in-app-currency vocabulary in user-facing strings

**Evidence:** Searched every user-facing string for "premium", "in-app purchase", "IAP", "coins", "gems", "tokens", "boost", "credits", "tip the seller", "subscription tier", "unlock". Only hits:
- `src/theme/index.ts:20` — CSS comment "Primary accent — premium red" (developer comment, not user-visible)
- `src/components/PlatformInstructions.tsx:102` — `info.tips.map((tip,i) =>...)` ("transfer tips" UI, not money tipping)
- `app/settings/privacy.tsx:85,123,140` — "tokens" refers to push/auth tokens (correct)

**Status: ✅ PASS**

### 1.4 External Purchase Link entitlement (3.1.1(a))

**Evidence:** `grep -rn "external_purchase\|com.apple.developer.storekit.external" ios` → **0 matches**.

**Status: ✅ PASS**

### 1.5 Tipping feature

**Evidence:** No `tip` / `tipping` / `gratuity` flow anywhere.

**Status: ✅ PASS**

**Section 1 summary:** 5 PASS / 0 anything-else. Top 3: nothing — clean.

---

## SECTION 2 — Stripe SDK Integration

### 2.1 Stripe SDK installation + version pin

**Evidence:**
- `package.json`: `"@stripe/stripe-react-native": "0.50.3"` (RN binding)
- `ios/Podfile.lock`: `Stripe (24.19.0)`, `StripePayments (24.19.0)`, `StripePaymentSheet (24.19.0)`, `StripeApplePay (24.19.0)`. Native iOS Stripe SDK is **24.19.0**.

**Status: ✅ PASS** — well above the requested ≥23.x.

### 2.2 PaymentSheet vs. custom card form

**Evidence:** `src/screens/checkout/CheckoutNative.tsx:24` imports `useStripe` from `@stripe/stripe-react-native`; lines 122–131 call `initPaymentSheet` and `presentPaymentSheet`. **No custom card form.**

**Status: ✅ PASS**

### 2.3 Publishable key client-side, environment-aware

**Evidence:**
- `src/config/app.ts:15` reads `process.env.EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY`.
- `.env.development:1` → `pk_test_51T6Far...`
- `.env.production:3` → `pk_live_51T6Far...`
- StripeProvider wraps app in `src/providers/NativeAppShell.native.tsx:79–84`.

**Status: ✅ PASS**

### 2.4 No secret keys in iOS bundle

**Evidence:** `grep -rn "sk_live_\|sk_test_" app src` → 0 matches in client code. All `STRIPE_SECRET_KEY` references are in `supabase/functions/*` which are server-side Deno functions.

**Status: ✅ PASS**

### 2.5 Webhook signing secret server-side only

**Evidence:** `STRIPE_WEBHOOK_SECRET` is referenced only in `supabase/functions/stripe-webhook/index.ts:5` via `Deno.env.get`.

**Status: ✅ PASS**

### 2.6 Stripe API version pinned server-side

**What & why:** Without `Stripe-Version` header, Stripe uses your account's default API version, which Stripe rotates over time, potentially changing response shapes.

**Evidence:** `grep -rn "Stripe-Version\|stripe-version\|api_version" supabase/functions` → **0 matches**. None of the Stripe API calls in `create-payment-intent`, `confirm-payment`, `create-connect-account`, `confirm-and-release`, `enforce-transfer-expiry`, `stripe-webhook` send a `Stripe-Version` header.

**Status: ⚠️ NEEDS FINE-TUNING**

**Fix:** Add `'Stripe-Version': '2024-09-30.acacia'` (or the version you've been testing against) to every Stripe API fetch call in `supabase/functions/`. Centralize via a small wrapper:

```ts
// supabase/functions/_shared/stripe.ts
const STRIPE_API_VERSION = '2024-09-30.acacia';
export async function stripeFetch(path: string, init: RequestInit = {}) {
  return fetch(`https://api.stripe.com/v1${path}`, {
    ...init,
    headers: {
      ...init.headers,
      Authorization: `Bearer ${Deno.env.get('STRIPE_SECRET_KEY')}`,
      'Stripe-Version': STRIPE_API_VERSION,
    },
  });
}
```

**Section 2 summary:** 5 PASS / 1 NEEDS FINE-TUNING / 0 FAIL. Top 1: pin Stripe API version.

---

## SECTION 3 — Apple Pay Configuration

### 3.1 Apple Pay capability + entitlement

**Evidence:** `ios/snatchit/snatchit.entitlements:6–9`:
```xml
<key>com.apple.developer.in-app-payments</key>
<array><string>merchant.com.snatchit</string></array>
```

**Status: ✅ PASS**

### 3.2 Merchant ID registered in Apple Dev portal + Stripe Dashboard

**Status: 🔍 CANNOT VERIFY** — both registrations live outside the codebase. Confirm both yourself: (a) Apple Developer → Identifiers → Merchant IDs → `merchant.com.snatchit` exists; (b) Stripe Dashboard → Settings → Payment methods → Apple Pay → certificate uploaded for that merchant ID.

### 3.3 `deviceSupportsApplePay` / `canMakePayments` check before showing Apple Pay UI

**Evidence:** `grep -rn "deviceSupportsApplePay\|canMakePayments\|isApplePaySupported" src app` → **0 matches**.

**Status: ⚠️ NEEDS FINE-TUNING** — moot for now because Apple Pay is not actually enabled in the PaymentSheet (see 3.4). Once 3.4 is fixed, you should also gate any "Pay with Apple Pay" CTA behind a `deviceSupportsApplePay` check.

### 3.4 Apple Pay configured in PaymentSheet

**Evidence:** `src/screens/checkout/CheckoutNative.tsx:122–131`:
```ts
const { error } = await initPaymentSheet({
  paymentIntentClientSecret: result.clientSecret,
  merchantDisplayName: 'SnatchIt',
  returnURL: 'snatchit://checkout',
  allowsDelayedPaymentMethods: false,
  defaultBillingDetails: { email: user!.email },
});
```

**No `applePay: { merchantCountryCode: 'US' }` parameter.**

**Status: ❌ FAIL — Apple Pay button will NOT appear in PaymentSheet.**

This is the single biggest checkout finding. Even though entitlements declare Apple Pay capability, the Stripe React Native binding requires the `applePay` config in `initPaymentSheet` for the sheet to surface the Apple Pay row.

**Fix:** `src/screens/checkout/CheckoutNative.tsx:122`:

```ts
const { error } = await initPaymentSheet({
  paymentIntentClientSecret: result.clientSecret,
  merchantDisplayName: 'SnatchIt',
  applePay: {
    merchantCountryCode: 'US',
    paymentSummaryItems: [
      { label: 'Ticket', amount: (result.amount / 100).toFixed(2) },
      { label: 'Service fee', amount: (result.serviceFee / 100).toFixed(2) },
      { label: 'SnatchIt', amount: (result.total / 100).toFixed(2) }, // grand total label
    ],
  },
  returnURL: 'snatchit://checkout',
  allowsDelayedPaymentMethods: false,
  defaultBillingDetails: { email: user!.email },
});
```

The grand-total label is the merchant name (Apple's required convention).

### 3.5 PKPaymentSummaryItem honesty

**Evidence:** No `paymentSummaryItems` configured (see 3.4). Once configured per the fix above, the line items will be honest — they mirror the in-app `Service fee (5%)` row at `CheckoutNative.tsx:403`.

**Status: ❌ FAIL** — until 3.4 is fixed.

**Section 3 summary:** 1 PASS / 1 NEEDS FINE-TUNING / 2 FAIL / 1 CANNOT VERIFY. Top 3: enable Apple Pay in PaymentSheet (3.4 + 3.5), gate UI with `deviceSupportsApplePay`, verify Merchant ID + cert.

---

## SECTION 4 — Stripe Connect (Marketplace Architecture)

### 4.1 Express accounts

**Evidence:** `supabase/functions/create-connect-account/index.ts:218`: `'type': 'express'`.

**Status: ✅ PASS**

### 4.2 Stripe-hosted onboarding presented in-app

**Evidence:** `app/settings/payout-setup.tsx:188`: `await Linking.openURL(url);`.

**Status: ❌ FAIL** — `Linking.openURL` opens mobile Safari (or default browser), kicking the user out of the app. Per S4.2 of the brief, the onboarding link must be presented in-app via SFAuthenticationSession-equivalent.

**Fix:** Replace `Linking.openURL(url)` with `expo-web-browser` (already a dependency, `package.json:32`):

```ts
import * as WebBrowser from 'expo-web-browser';
// ...
const result = await WebBrowser.openAuthSessionAsync(url, 'snatchit://payout-return');
```

This presents the link in `SFAuthenticationSession` on iOS — same window, persistent cookies, deep-link return.

### 4.3 `account.updated` webhook — gating on `charges_enabled` + `payouts_enabled`

**Evidence:** `supabase/functions/stripe-webhook/index.ts` only handles `payment_intent.succeeded` and `payment_intent.payment_failed` (lines 144, 358). `grep -rn "account.updated" supabase/functions` → **0 matches**. The app polls `details_submitted` via the `create-connect-account?status_only=true` endpoint instead.

**Status: ⚠️ NEEDS FINE-TUNING** — polling works, but `account.updated` webhook is the canonical signal. Without it, sellers may be allowed to list with stale onboarding state if your DB cache and Stripe disagree.

**Fix:** Add an `account.updated` branch to `supabase/functions/stripe-webhook/index.ts`:

```ts
} else if (event.type === 'account.updated') {
  const account = event.data.object;
  await supabase
    .from('profiles')
    .update({
      stripe_onboarding_complete:
        account.details_submitted === true &&
        account.charges_enabled === true &&
        account.payouts_enabled === true,
    })
    .eq('stripe_connect_id', account.id);
}
```

Also: gate listing creation on **both** `charges_enabled` AND `payouts_enabled`, not just `details_submitted` (today's behavior at `create-connect-account/index.ts:240,247`).

### 4.4 Separate charges and transfers (escrow) vs. destination charges

**Evidence:** `supabase/functions/create-payment-intent/index.ts:281–296` creates a PaymentIntent **without** `transfer_data` / `on_behalf_of` / `application_fee_amount`. Funds land in the platform balance. `supabase/functions/confirm-and-release/index.ts:120–133` calls `POST /v1/transfers` separately when buyer confirms receipt. Comment at `stripe-webhook/index.ts:329–333` confirms: "PAYOUT DEFERRED (V1 buyer-protection architecture). The Stripe Transfer to the seller's Connect account is NOT created here."

**Status: ✅ PASS** — this is exactly the separate-charges-and-transfers escrow pattern.

### 4.5 `application_fee_amount` per transaction

**Evidence:** `grep -rn "application_fee_amount\|application_fee" supabase/functions` → **0 matches**. No `application_fee_amount` is sent on PI creation OR on the manual transfer.

**Status: ⚠️ NEEDS FINE-TUNING** — your math reconciles in practice (platform charges $105, transfers $100 to seller, keeps $5 minus Stripe processing fees), but Stripe's reporting / Tax / 1099 logic can't see "this $5 was a marketplace fee." Fix in two ways depending on architecture:

- Path A (recommended for separate charges and transfers): Don't change PI creation. Instead, when calling `POST /v1/transfers`, no `application_fee` exists for transfers — but log the platform-retained amount in your `payments.service_fee` column (already done at `create-payment-intent/index.ts:266,313`). Reporting must be derived from your DB, not Stripe.
- Path B (if you migrate to destination charges later): set `transfer_data[destination] = seller_account` and `application_fee_amount = serviceFeeCents` on PI creation; Stripe handles split.

For now, Path A is what you have and it's defensible — but **you must own reporting** because Stripe Dashboard won't show fees per transaction.

### 4.6 Payout state machine

**Evidence:** Schema (`supabase/migrations/002_transfers.sql:53–60`) defines transfer statuses:
```
pending → seller_sent → buyer_confirmed → (auto_released | disputed | expired)
```
`payout_released_at` and `stripe_transfer_id` columns track the actual Stripe Transfer creation (`confirm-and-release/index.ts:200+`, `enforce-transfer-expiry/index.ts:300+`).

**Status: ✅ PASS** — explicit, auditable, FSM enforced via DB triggers (`guard_listing_state_columns`, `guard_listing_identity_columns`).

### 4.7 Reversal logic for canceled events

**Evidence:** `enforce-transfer-expiry/index.ts:189–250` issues full Stripe refund when transfer expires (24h with no seller_sent). `grep -rn "transfer\.reversals\|transfers/.*reversals" supabase/functions` → **0 matches**.

**Status: ⚠️ NEEDS FINE-TUNING** — refund-from-platform-balance works for the only auto-cancel path the app currently has (transfer expiry before seller sends ticket). For "event canceled after payout already transferred" you have **no reversal path** — funds are already in seller's connected account.

**Fix:** Add `POST /v1/transfers/{id}/reversals` capability for an admin-triggered reversal. Plus enable `debit_negative_balances` on the Express account in your platform settings so reversals can pull from a seller's future balance if their available balance is too low.

### 4.8 Documented release trigger

**Evidence:** Two release triggers exist:
1. **Manual buyer confirmation** via `confirm-and-release` edge function (called from `app/transfer/receive/[id].tsx:147`).
2. **Auto-release** after 72h via `enforce-transfer-expiry` Phase 2 (`supabase/functions/enforce-transfer-expiry/index.ts:1–46` comment block).

**Status: ✅ PASS** — both deterministic and auditable.

**Section 4 summary:** 4 PASS / 3 NEEDS FINE-TUNING / 1 FAIL. Top 3: switch onboarding link to `expo-web-browser` (4.2), add `account.updated` webhook (4.3), add transfer-reversal path (4.7).

---

## SECTION 5 — Buyer Checkout Flow

### 5.1 Native checkout — no webview / external browser

**Evidence:** PaymentSheet is a native modal. No `react-native-webview` dependency (`grep WebView package.json` → 0). No `Linking.openURL` for payment.

**Status: ✅ PASS**

### 5.2 PI created server-side

**Evidence:** `supabase/functions/create-payment-intent/index.ts:281–304` creates PI via direct Stripe API call from the edge function. Client never sees the secret.

**Status: ✅ PASS**

### 5.3 `setup_future_usage` for saved cards

**Evidence:** `grep -n "setup_future_usage" supabase/functions/create-payment-intent/index.ts` → **0 matches**.

**Status: ❌ FAIL** — cards are not saved across purchases. Each checkout requires re-entering card details (or re-tapping Apple Pay).

**Fix:** When creating PI, set `'setup_future_usage': 'on_session'` and `'customer': stripeCustomerId`. Requires fix 5.4 first.

### 5.4 Stripe Customer per buyer

**Evidence:** `grep -rn "customers\|stripe_customer_id" supabase src app` → **0 matches**. No Customer creation, no `stripe_customer_id` column on `profiles`.

**Status: ❌ FAIL**

**Fix:** On first checkout (or signup), create a Stripe Customer:
```ts
// in create-payment-intent or a new ensure-customer edge fn
const customer = await stripeFetch('/customers', {
  method: 'POST',
  body: new URLSearchParams({ email: user.email, 'metadata[user_id]': user.id }).toString(),
});
// store customer.id on profiles.stripe_customer_id
// then PI body adds: 'customer': stripe_customer_id, 'setup_future_usage': 'on_session'
```

### 5.5 3DS / SCA

**Evidence:** PaymentSheet handles 3DS automatically. No custom override (`grep -rn "three_d_secure\|requires_action\|next_action" src app` → 0).

**Status: ✅ PASS**

### 5.6 Fee breakdown screen

**Evidence:** `src/screens/checkout/CheckoutNative.tsx:403`: `<Text style={s.summaryLabel}>Service fee (5%)</Text>` with line for `Buy Now price` / `Winning bid`, service fee, total. Matches PI math at `create-payment-intent/index.ts:214–216`.

**Status: ✅ PASS** for in-app screen. Must mirror to Apple Pay summary line items per Section 3.5.

### 5.7 Idempotency on PI creation

**Evidence:** `create-payment-intent/index.ts:283`: `'Idempotency-Key': pi_${listing_id}_${buyerId}_${mode}_${totalCents}`.

**Status: ✅ PASS**

### 5.8 Error states handled

**Evidence:** `src/screens/checkout/CheckoutNative.tsx:160–172`: handles `paymentError.code === 'Canceled'` separately from other errors. Generic error path shows `paymentError.message`. No code-by-code mapping (declined / insufficient_funds / requires_action). Acceptable because PaymentSheet handles those internally.

**Status: ⚠️ NEEDS FINE-TUNING** — Stripe SDK error messages can be technical ("Your card was declined."). Consider mapping common error codes to friendlier copy.

**Section 5 summary:** 5 PASS / 1 NEEDS FINE-TUNING / 2 FAIL. Top 3: Stripe Customer + setup_future_usage (5.3 + 5.4), friendlier error copy (5.8).

---

## SECTION 6 — Webhooks & State Sync

### 6.1 Webhook URL stable + registered

**Evidence:** Endpoint exists at `supabase/functions/stripe-webhook/index.ts`. Stripe Dashboard registration is operational, not visible from code.

**Status: 🔍 CANNOT VERIFY** Stripe Dashboard registration — confirm `https://hqycwntpfoztoinemqns.supabase.co/functions/v1/stripe-webhook` is registered in Stripe Dashboard with correct events.

### 6.2 Signature verification

**Evidence:** `supabase/functions/stripe-webhook/index.ts:60–104`: full HMAC-SHA256 verification with timestamp tolerance (300s, added in prior session).

**Status: ✅ PASS**

### 6.3 Required events handled

**Evidence:** Only two `event.type ===` branches (`stripe-webhook/index.ts:144,358`):
- ✅ `payment_intent.succeeded`
- ✅ `payment_intent.payment_failed`
- ❌ `charge.refunded`
- ❌ `charge.dispute.created`
- ❌ `charge.dispute.closed`
- ❌ `account.updated`
- ❌ `transfer.created`
- ❌ `transfer.reversed`
- ❌ `payout.paid`
- ❌ `payout.failed`

**Status: ❌ FAIL — 8 of 10 required events are unhandled.**

**Fix:** Each missing event must be wired into `stripe-webhook/index.ts`. Most critical first:

1. `charge.dispute.created` — write to a `disputes` table, alert ops, **prevent payout release** for that listing's transfer (set `transfer.status = 'disputed'` and don't let auto-release fire). 7-day evidence window.
2. `charge.dispute.closed` — record outcome (`won` / `lost`); if won, resume payout flow.
3. `account.updated` — see 4.3 above.
4. `charge.refunded` — set `payments.status = 'refunded'`, write `stripe_refund_id`.
5. `transfer.created` / `payout.paid` / `payout.failed` — useful for ops dashboards.

### 6.4 2xx response time

**Evidence:** Handler does DB writes synchronously inline (no queue). Each event: 2–4 DB writes + optional Stripe API roundtrip + push fan-out (`sendPush` is fire-and-forget, line 87–95). On a healthy cluster this stays well under 5s, but `sendPush` makes a POST to `/functions/v1/send-push` which adds latency.

**Status: ⚠️ NEEDS FINE-TUNING** — under load, stack the push outside the request. Use `EdgeRuntime.waitUntil(sendPush(...))` (Supabase Deno) or write to a `notifications_queue` table.

### 6.5 Webhook event-ID dedup

**Evidence:** `grep -rn "stripe_event_id\|webhook_events\|event\.id" supabase/migrations supabase/functions` → no event-ID dedup table. Idempotency relies on row-level claim semantics (`.neq('status', 'succeeded')` at `stripe-webhook/index.ts:131`) for `payment_intent.succeeded` only.

**Status: ⚠️ NEEDS FINE-TUNING** — when you add the 8 new event handlers (6.3), each needs its own dedup story OR a centralized `webhook_events` table:

```sql
create table public.stripe_webhook_events (
  event_id text primary key,
  event_type text not null,
  received_at timestamptz default now()
);
```
Insert before processing; on conflict, return 200 immediately.

### 6.6 Sentry on webhook failures

**Evidence:** `grep -rn "Sentry\|@sentry" supabase/functions` → **0 matches**. Server-side errors only `console.error`.

**Status: ❌ FAIL**

**Fix:** Wire `@sentry/deno` (or send a JSON POST to a Sentry endpoint) on any non-2xx response. Minimum:
```ts
import * as Sentry from "https://deno.land/x/sentry/index.mjs";
Sentry.init({ dsn: Deno.env.get('SENTRY_DSN_SERVER') });
// in catch blocks:
Sentry.captureException(err);
```

**Section 6 summary:** 1 PASS / 2 NEEDS FINE-TUNING / 2 FAIL / 1 CANNOT VERIFY. Top 3: handle the 8 missing events (6.3) — especially `charge.dispute.*` and `account.updated`; add server-side Sentry (6.6); add event-ID dedup table (6.5).

---

## SECTION 7 — Refunds, Disputes & Buyer Protection

### 7.1 Buyer protection policy reachable in-app

**Evidence:** `app/settings/legal.tsx:68–105` — Terms of Service includes buyer protection language: "buyers are solely responsible for reviewing listing details… transactions are final once payment is confirmed." Reachable from Settings → Support → Terms of Service AND from signup screen footer. ✅

**Status: ✅ PASS**

### 7.2 Refund flow per perspective

**Evidence:**
- Buyer: dispute via `buyer_dispute_transfer` RPC (`supabase/migrations/009_dispute.sql:5–55`), called from `src/screens/ListingDetailScreen.tsx:841` and `app/transfer/receive/[id].tsx:182`.
- Auto-refund on transfer expiry (`supabase/functions/enforce-transfer-expiry/index.ts` Phase 1).
- Seller: no proactive refund-issuance UI (would require Stripe API call from an admin path).

**Status: ⚠️ NEEDS FINE-TUNING** — sellers cannot initiate a refund themselves (e.g., "I can't deliver the ticket after all"). Either build that flow or document the support email path explicitly.

### 7.3 Dispute (`charge.dispute.created`) handling

**Evidence:** No handler for `charge.dispute.created`. The `buyer_dispute_transfer` RPC is **app-level** dispute (buyer reports problem to Snatch It support), NOT a Stripe chargeback.

**Status: ❌ FAIL** — see 6.3. Without webhook handling:
- You only learn about chargebacks via Stripe Dashboard.
- 7-day evidence window may pass before you notice.
- Funds get pulled from your platform balance with no automation.

### 7.4 `dispute.funds_withdrawn` strategy

**Evidence:** No code path. No `debit_negative_balances` setting visible (lives in Stripe Dashboard).

**Status: 🔍 CANNOT VERIFY** — confirm in Stripe Dashboard whether Express accounts have `debit_negative_balances` enabled. If yes, document that lost chargebacks pull from seller's balance. If no, your platform absorbs all chargeback losses.

### 7.5 Event-cancellation refund path

**Evidence:** Auto-refund only triggers on transfer expiry, not on event cancellation. No "event canceled" admin action exists.

**Status: ❌ FAIL**

**Fix:** Build a manual admin action OR an event-status-aware cron:
- If transfer not yet released → full refund from platform balance (already implemented for expiry; reuse).
- If transfer already released → must reverse via `POST /v1/transfers/{id}/reversals` first, then refund the payment from platform balance.

**Section 7 summary:** 1 PASS / 1 NEEDS FINE-TUNING / 2 FAIL / 1 CANNOT VERIFY. Top 3: chargeback webhook (7.3), event-cancellation refund (7.5), enable `debit_negative_balances` on Express (7.4).

---

## SECTION 8 — Identity, Fraud & Risk

### 8.1 Stripe Radar

**Evidence:** No Radar config in code (Radar is configured in Stripe Dashboard).

**Status: 🔍 CANNOT VERIFY** — confirm in Stripe Dashboard → Radar → Rules. At minimum: block-rule for high-risk country, review-rule for borderline scores.

### 8.2 Seller KYC gating

**Evidence:** `src/screens/CreateListingScreen.tsx:307–326` and `supabase/functions/create-connect-account/index.ts:240–248`: listing creation gated on `stripe_onboarding_complete = true` (= `details_submitted === true`).

**Status: ⚠️ NEEDS FINE-TUNING** — gating on `details_submitted` is correct for "form was filled out" but not enough for "Stripe accepted the seller." `charges_enabled` and `payouts_enabled` are the actual gates. Without `account.updated` webhook (4.3), a seller can be `details_submitted=true` but `charges_enabled=false` (Stripe hasn't approved the documents yet) and you'll let them list anyway.

**Fix:** Update the gate to require `charges_enabled === true` AND `payouts_enabled === true` on Profile.

### 8.3 Ticket fraud signals

**Evidence:** `supabase/migrations/012_seller_risk.sql:1+` — `seller_risk_scores` and `seller_flags` tables exist. `src/screens/CreateListingScreen.tsx:43–252` consumes a `RiskTier` system that warns/blocks listing creation. **Phase B Anti-Fraud Design** docs (`PHASE_B_ANTI_FRAUD_DESIGN.md`, `PHASE_B_DETECTION_QUERIES.sql`) describe seller risk scoring.

**Status: ✅ PASS** — risk scoring is in place. No automatic duplicate-barcode detection (no barcodes captured).

### 8.4 Seller suspension flow

**Evidence:** `seller_flags` table exists; manual flag-and-block via SQL. No in-code "suspend seller" admin endpoint.

**Status: ⚠️ NEEDS FINE-TUNING** — operational rather than code. Document the manual suspension SOP.

### 8.5 Rate limiting on listing / purchase / login

**Evidence:**
- Purchase: rate-limited via `check_rate_limit` RPC (`create-payment-intent/index.ts:108`).
- Connect onboarding: rate-limited (`create-connect-account/index.ts:146`).
- Confirm-and-release: rate-limited.
- Delete-account: rate-limited.
- **Listing creation:** `grep "check_rate_limit" supabase/migrations` shows the RPC, but `supabase.from('listings').insert(...)` in `src/screens/CreateListingScreen.tsx:388` goes directly through PostgREST and is NOT rate-limited at the edge-function level.
- **Auth (signup/login):** Supabase Auth has its own throttling, but you have no app-level rate-limit on `signInWithPassword` / `signUp`.

**Status: ⚠️ NEEDS FINE-TUNING** — listing creation could be flooded. Add a rate-limit RPC call to a new `create-listing` edge function or rely on per-IP limits via Supabase's gateway.

**Section 8 summary:** 1 PASS / 3 NEEDS FINE-TUNING / 0 FAIL / 1 CANNOT VERIFY. Top 3: gate listings on `charges_enabled` (8.2), rate-limit listing creation (8.5), confirm Radar config (8.1).

---

## SECTION 9 — Tax & Regulatory

### 9.1 Stripe Tax for marketplace fee

**Evidence:** `grep -rn "stripe_tax\|tax_calculation\|stripe-tax" supabase` → **0 matches**.

**Status: ⚠️ NEEDS FINE-TUNING** — depends on whether your marketplace fee is taxable in your seller jurisdictions. Florida (where JDT LLC is registered, per Terms `app/settings/legal.tsx:243`) generally does NOT tax marketplace facilitator fees on tickets, but check with a CPA. If applicable, enable Stripe Tax on your platform account.

### 9.2 1099-K issuance (US sellers)

**Evidence:** No code or config for 1099 generation. Stripe Connect Express accounts get 1099-Ks from Stripe automatically IF you've enabled "Stripe handles tax reporting" in the Connect settings.

**Status: 🔍 CANNOT VERIFY from codebase** — confirm in Stripe Dashboard → Connect → Settings → Tax form filing. The 2026 federal threshold is $600 (down from $20K) — many sellers will hit it.

### 9.3 State-level ticket-resale law surfacing

**Evidence:** Hardcoded neighborhoods are Miami-only (`src/constants/neighborhoods.ts`). No state-level resale-law filtering or seller warning.

**Status: ⚠️ NEEDS FINE-TUNING** — for a Miami-only beta this is fine. Before expanding into NY (cap at 10% above face for some events), MA (no caps but disclosure rules), CT, NJ, IL, the listing flow needs jurisdiction-aware copy or hard limits.

### 9.4 AML/KYC bypass check

**Evidence:** No code bypasses Stripe's KYC. The `delete_account_cleanup` RPC (migration 020) anonymizes financial records but **does not** trigger Stripe Connect account deletion — the seller's Stripe account remains and Stripe retains its KYC data per their policy.

**Status: ✅ PASS** — Stripe handles KYC end-to-end; you don't bypass it.

**Section 9 summary:** 1 PASS / 2 NEEDS FINE-TUNING / 0 FAIL / 1 CANNOT VERIFY. Top 3: confirm 1099 filing path with Stripe (9.2), state-resale-law copy when expanding (9.3), Stripe Tax enable decision (9.1).

---

## SECTION 10 — App Store Review Guideline Coverage (Non-Payment)

### 10.1 — Guideline 1.2 (UGC)

**Evidence:** `grep -rn "Report\|Block " app src` shows only `handleReportIssue` (`src/screens/ListingDetailScreen.tsx:841`) — and that's a **transfer dispute**, not a content report. **No "Report listing", no "Report seller", no "Block user".**

**Status: ❌ FAIL** — this is the dominant App Store production-review risk. Beta App Review (TestFlight) is more lenient and may pass; full App Store production submission almost certainly will not.

**Fix (minimum viable):**
1. Add a "Report listing" overflow menu to `src/screens/ListingDetailScreen.tsx` that posts to a new `reports` table with `(reporter_id, listing_id, reason, notes, created_at)`.
2. Add a "Block user" action on seller profile rows. Filter blocked users out of feeds via a `user_blocks` table + RLS.
3. Document the moderation SLA (e.g., "we respond to reports within 24 hours") in the Privacy Policy.

### 10.2 — Guideline 5.1.1(v) (Account Deletion)

**Evidence:** `app/settings/index.tsx:134–166` calls `delete-account` edge function with double-confirmation. `supabase/functions/delete-account/index.ts:140+` cancels listings, anonymizes financial records, deletes storage, deletes auth user. Verified end-to-end in prior audit cycle.

**Status: ✅ PASS**

### 10.3 — Guideline 5.1.1 (Privacy Policy in-app)

**Evidence:** `app/settings/privacy.tsx` — full policy. Linked from `app/settings/index.tsx:282` and from the new signup-screen disclosure (`app/(auth)/signup.tsx:101–124`).

**Status: ✅ PASS**

### 10.4 — Guideline 1.4.3 (Controlled substances)

**Evidence:** Free-form `restrictions` field on listings (`src/screens/CreateListingScreen.tsx:553`) accepts any text. No automated content filtering.

**Status: ⚠️ NEEDS FINE-TUNING** — listings could include "21+, drinks included" or worse. Add a basic word-list filter on listing submission (alcohol-promotion / drug references) or content-moderation step.

### 10.5 — Guideline 4.2 (Minimum Functionality / "thin app")

**Evidence:** Real auctions, bids, transfers, fee math, dispute path, account deletion. Not thin. ✅

**Status: ✅ PASS**

### 10.6 — Guideline 2.1 (App Completeness)

**Evidence:** Prior audit cycle removed all template artifacts (modal placeholder, dead HomeScreen). No "Lorem ipsum" anywhere. All flows wired end-to-end. App icon transparency, lowercase name, and unused permissions in Info.plist are still outstanding from the prior audit and constitute completeness blockers.

**Status: ⚠️ NEEDS FINE-TUNING** — finish the C1–C4 list from the previous audit (icon transparency, camera/mic placeholder strings, `aps-environment=development`, lowercase app name).

### 10.7 — Guideline 2.3.1 (Accurate metadata + review notes)

**Evidence:** Review notes draft was prepared in the prior audit (see `PRE_TESTFLIGHT_AUDIT.md` if generated). Need to be pasted into App Store Connect.

**Status: ⚠️ NEEDS FINE-TUNING** — paste them into App Store Connect "Notes for App Review" before submission.

### 10.8 — Guideline 4.7 / WebKit

**Evidence:** No webview anywhere; no payment in webview.

**Status: ✅ PASS**

### 10.9 — Guideline 2.5.13 (Face ID)

**Evidence:** No biometric auth used.

**Status: ⬜ N/A**

**Section 10 summary:** 4 PASS / 3 NEEDS FINE-TUNING / 1 FAIL / 1 N/A. Top 3: ship UGC moderation (10.1), surface controlled-substance filter (10.4), finish C1–C4 from prior audit (10.6).

---

## SECTION 11 — Ticket Delivery & Fulfillment

### 11.1 Delivery mechanism

**Evidence:** `src/types/index.ts:34`: `TransferMethod = 'mobile_transfer' | 'email'`. `src/components/PlatformInstructions.tsx` and `src/lib/platformInstructions.ts` show step-by-step instructions for each platform (Ticketmaster, AXS, etc.). Sellers transfer the ticket on the original platform; buyers receive there; then both confirm in Snatch It.

**Status: ✅ PASS** — model is documented and consistent.

### 11.2 PassKit / pkpass

**Evidence:** No PassKit code. Not part of this product.

**Status: ⬜ N/A**

### 11.3 Transfer state tracking

**Evidence:** `pending → seller_sent → buyer_confirmed | disputed | expired | auto_released` (`supabase/migrations/002_transfers.sql:53–60`). Transitions logged with timestamps.

**Status: ✅ PASS**

### 11.4 Duplicate-barcode detection

**Evidence:** No barcode field captured. The "ticket" the seller possesses lives on the original platform; Snatch It only knows about the listing.

**Status: ⬜ N/A** — duplicate-listing detection would need to come from `seller_risk` heuristics (already in place per `PHASE_B_*` docs).

### 11.5 Buyer "Mark received" action

**Evidence:** `app/transfer/receive/[id].tsx:147` calls `confirm-and-release` edge function which transitions transfer to `buyer_confirmed` and triggers Stripe Transfer to seller.

**Status: ✅ PASS**

**Section 11 summary:** 3 PASS / 0 NEEDS FINE-TUNING / 0 FAIL / 2 N/A. Top 3: nothing critical.

---

## SECTION 12 — Backend Security & Infra

### 12.1 Auth on payment functions

**Evidence:** Every payment-touching edge function calls `getAuthenticatedUserId(req)` first (`create-payment-intent/index.ts:103`, `confirm-payment/index.ts:124`, `confirm-and-release/index.ts:145`, `create-connect-account/index.ts:135`, `delete-account/index.ts:118`).

**Status: ✅ PASS**

### 12.2 CORS restricted

**Evidence:** Each edge function whitelists `https://snatchitapp.com` and `https://www.snatchitapp.com` (`stripe-webhook/index.ts:11–14`, etc.). React Native apps don't send Origin so they bypass CORS naturally.

**Status: ✅ PASS**

### 12.3 Sentry DSN

**Evidence:** `src/providers/NativeAppShell.native.tsx:31`: `dsn: process.env.EXPO_PUBLIC_SENTRY_DSN`. `.env.production` has a valid Sentry DSN.

**Status: ✅ PASS**

### 12.4 npm audit

**Evidence:** From prior audit cycle: 1 high (`@xmldom/xmldom`) + 16 moderate. Run again pre-submission.

**Status: ⚠️ NEEDS FINE-TUNING** — `npm audit fix`; if the high CVE is unresolvable without breaking changes, document the compensating control.

### 12.5 `delete_account` exercised

**Evidence:** `supabase/functions/delete-account/index.ts` is fully implemented. Prior audit verified end-to-end. No automated integration tests in repo (`grep -rn "delete-account.*test\|test.*delete" .` → 0).

**Status: ⚠️ NEEDS FINE-TUNING** — write at least one integration test (test user → invoke delete-account → verify auth.users row gone and no orphan records).

### 12.6 RLS on payments / transfers / disputes

**Evidence:** `supabase/schema.sql` and `supabase/migrations/002_transfers.sql` show:
- Payments: RLS enabled, buyer-self and seller-self read only, no client INSERT/UPDATE.
- Transfers: same shape.
- Listings: RLS with WITH CHECK preventing seller_id change.

**Status: ✅ PASS**

### 12.7 Status enum correctness

**Evidence:** `src/types/index.ts:166–171` enumerates transfer statuses; matches DB enum at `supabase/migrations/002_transfers.sql:56–62`.

**Status: ✅ PASS**

**Section 12 summary:** 5 PASS / 2 NEEDS FINE-TUNING / 0 FAIL. Top 3: `npm audit fix` (12.4), one delete-account integration test (12.5).

---

## SECTION 13 — Observability & Operations

### 13.1 Sentry coverage

**Evidence:** Client side has Sentry init + ErrorBoundary capture. Server side has zero Sentry (see 6.6). Webhook errors only `console.error`.

**Status: ⚠️ NEEDS FINE-TUNING** — wire server-side Sentry (or equivalent — Logflare, Axiom, BetterStack).

### 13.2 Stripe Dashboard email alerts

**Status: 🔍 CANNOT VERIFY** — operational. Confirm in Stripe Dashboard → Settings → Team and security → Email preferences. Subscribe to: failed payouts, disputes, account capability changes.

### 13.3 Admin view

**Evidence:** No admin UI in the iOS app. Manual via Stripe Dashboard + Supabase SQL Editor (DAY5_ADMIN_SQL_PACK.sql exists with playbook queries).

**Status: ⚠️ NEEDS FINE-TUNING** — for v1 with Miami beta, manual-via-SQL is acceptable. Document the runbook.

### 13.4 Structured logging on transitions

**Evidence:** `console.log('[create-connect-account] URLs:', {...})`, `console.log('Webhook: payment already processed', ...)` — semi-structured logs throughout edge functions. Includes `payment_id`, `listing_id`, `seller_id`, `buyer_id` in most lines.

**Status: ✅ PASS**

### 13.5 Runbook

**Evidence:** `DAY5_MANUAL_REFUND_PLAYBOOK.md`, `DAY5_ADMIN_DISPUTE_SOP.md`, `DAY7_DAILY_MONITORING_CHECKLIST.md`, `DAY7_LAUNCH_RISK_REGISTER.md` exist.

**Status: ✅ PASS** — docs exist; sanity-check before launch.

**Section 13 summary:** 2 PASS / 2 NEEDS FINE-TUNING / 0 FAIL / 1 CANNOT VERIFY. Top 3: server-side Sentry (13.1), Stripe alert subscriptions (13.2), admin-via-SQL runbook clarity (13.3).

---

## SECTION 14 — UI Copy & Wording Audit

### 14.1 Forbidden language

**Evidence:** Section 1 already covered all forbidden terms — clean.

**Status: ✅ PASS**

### 14.2 Checkout button copy

**Evidence:** `src/screens/checkout/CheckoutNative.tsx` button text: `🔒 Pay · $XX`. Includes amount.

**Status: ✅ PASS**

### 14.3 Fee disclosure language

**Evidence:** `src/screens/checkout/CheckoutNative.tsx:403`: `Service fee (5%)`. Honest.

**Status: ✅ PASS** — but consider adding a tooltip explaining what the fee covers (mirrors what 14.3 of the brief asks for). Right now there's no info icon.

### 14.4 No comparisons to App Store / IAP pricing

**Evidence:** No such comparisons in any string.

**Status: ✅ PASS**

### 14.5 Receipts

**Evidence:** No emailed receipt logic in code. Stripe sends its own card-charge receipt by default if `receipt_email` is set on the PI — not currently set (`grep "receipt_email" supabase/functions/create-payment-intent/index.ts` → 0).

**Status: ⚠️ NEEDS FINE-TUNING** — set `receipt_email` on PI creation so Stripe sends a card receipt to the buyer (`'receipt_email': user.email`). Also consider a Snatch It-branded receipt with itemization, sent via email or in-app.

**Section 14 summary:** 4 PASS / 1 NEEDS FINE-TUNING / 0 FAIL. Top 1: enable Stripe receipt emails (14.5).

---

## SECTION 15 — Pre-Submission Checklist

### 15.1 End-to-end TestFlight test

**Status: 🔍 CANNOT VERIFY** — must be done by you in TestFlight after the C1–C4 fixes from the prior audit + the Apple Pay fix from this audit.

### 15.2 App Review notes

**Status: ⚠️ NEEDS FINE-TUNING** — drafted below.

### 15.3 Demo accounts

**Status: 🔍 CANNOT VERIFY** — confirm `review-demo@snatchitapp.com` (or similar) exists, has been onboarded to Stripe Connect (test mode), and has at least one bid/listing for the reviewer to walk through.

### 15.4 Screenshots

**Status: 🔍 CANNOT VERIFY** — confirm screenshots show real listings, not empty states.

### 15.5 Description matches features

**Status: ⚠️ NEEDS FINE-TUNING** — confirm App Store description doesn't mention features that aren't shipping (e.g., "Apple Pay" if 3.4 isn't fixed).

### 15.6 Privacy nutrition labels

**Status: ⚠️ NEEDS FINE-TUNING** — must reflect: Email (Account, Customer Support), Phone (Customer Support — optional), Photos/Videos (App Functionality — listings/avatars), Payment Info (Stripe; not stored by you), User ID (Stripe Customer if implemented), Crash Data (Sentry), Diagnostics (Sentry).

### 15.7 Support URL live

**Evidence:** `legal@snatchitapp.com` in legal/privacy. Support URL — `grep -n "support" app/settings/support.tsx` → uses `support@snatchitapp.com`. **No `https://snatchitapp.com/support` page is in the repo.**

**Status: ⚠️ NEEDS FINE-TUNING** — either spin up a static support page on the same Vercel deployment as the new Expo Router screens, or use the gmail address for App Store Connect's "Support URL" via `mailto:` (Apple accepts this in some categories).

### 15.8 Test → live key swap

**Evidence:** EAS production profile sets `EXPO_PUBLIC_APP_ENV=production` (`eas.json:18`). Production Expo bundling uses `.env.production` which has `pk_live_*`. ✅ if the env file is what EAS reads.

**Status: ✅ PASS** — verify by inspecting an EAS build artifact's bundled JS for `pk_live_` (one search through the bundle).

**Section 15 summary:** 1 PASS / 4 NEEDS FINE-TUNING / 0 FAIL / 3 CANNOT VERIFY. Top 3: end-to-end TestFlight pass (15.1), demo account ready (15.3), support URL exists (15.7).

---

# Final Output

## 1. Section-by-section scorecard

| Section | PASS | FINE-TUNE | FAIL | CANNOT VERIFY | N/A |
|---|---|---|---|---|---|
| 1 — IAP Avoidance | 5 | 0 | 0 | 0 | 0 |
| 2 — Stripe SDK | 5 | 1 | 0 | 0 | 0 |
| 3 — Apple Pay | 1 | 1 | 2 | 1 | 0 |
| 4 — Connect Architecture | 4 | 3 | 1 | 0 | 0 |
| 5 — Buyer Checkout | 5 | 1 | 2 | 0 | 0 |
| 6 — Webhooks | 1 | 2 | 2 | 1 | 0 |
| 7 — Refunds & Disputes | 1 | 1 | 2 | 1 | 0 |
| 8 — Identity / Fraud | 1 | 3 | 0 | 1 | 0 |
| 9 — Tax & Reg | 1 | 2 | 0 | 1 | 0 |
| 10 — ASR Coverage | 4 | 3 | 1 | 0 | 1 |
| 11 — Ticket Delivery | 3 | 0 | 0 | 0 | 2 |
| 12 — Backend Security | 5 | 2 | 0 | 0 | 0 |
| 13 — Observability | 2 | 2 | 0 | 1 | 0 |
| 14 — Copy Audit | 4 | 1 | 0 | 0 | 0 |
| 15 — Pre-Submission | 1 | 4 | 0 | 3 | 0 |
| **TOTAL** | **43** | **26** | **10** | **9** | **3** |

## 2. Top 10 prioritized fixes (rejection risk × engineering effort)

| # | Fix | Risk | Effort | Files |
|---|-----|------|--------|-------|
| 1 | **Add UGC moderation** — "Report listing", "Block user", `reports` table, RLS on blocks. | App Store production: very high. TestFlight: medium. | 1–2 days | `src/screens/ListingDetailScreen.tsx`, new `app/report/[id].tsx`, new migration `022_reports_and_blocks.sql` |
| 2 | **Fix iOS icon transparency + remove unused Info.plist permissions + APS env + lowercase name** (carry-over from prior audit C1–C4) | TestFlight upload validation will hard-fail. | 1 hour total | `assets/images/icon.png`, `ios/snatchit/Info.plist`, `ios/snatchit/snatchit.entitlements`, `app.json:3` |
| 3 | **Enable Apple Pay in PaymentSheet** + line items (Section 3.4 / 3.5) | Conversion + parity with Apple Pay summary. | 30 min | `src/screens/checkout/CheckoutNative.tsx:122` |
| 4 | **Add `charge.dispute.created` + `charge.dispute.closed` webhook handlers** (Section 6.3 / 7.3) | Lost-funds risk per chargeback; possible review reproduction. | 4 hours | `supabase/functions/stripe-webhook/index.ts`, new migration for `disputes` table |
| 5 | **Add `account.updated` webhook + gate listing on `charges_enabled`+`payouts_enabled`** (4.3 / 8.2) | Stale onboarding state. | 2 hours | `supabase/functions/stripe-webhook/index.ts`, `src/screens/CreateListingScreen.tsx:307+` |
| 6 | **Switch Stripe Connect onboarding URL from `Linking.openURL` to `WebBrowser.openAuthSessionAsync`** (4.2) | Sellers leaving the app loses session continuity. | 30 min | `app/settings/payout-setup.tsx:188` |
| 7 | **Stripe Customer + `setup_future_usage`** (5.3 / 5.4) | Conversion on repeat purchases; Apple-Pay tokenization with saved methods. | 4 hours | new migration `023_stripe_customer_id.sql`, `supabase/functions/create-payment-intent/index.ts` |
| 8 | **Pin `Stripe-Version` header server-side** (2.6) | Future API drift breaks edge functions silently. | 30 min | new `supabase/functions/_shared/stripe.ts` + replace fetches |
| 9 | **Wire server-side Sentry into edge functions** (6.6 / 13.1) | Silent payment failures. | 2 hours | `supabase/functions/_shared/sentry.ts`, all 8 functions |
| 10 | **Set `receipt_email` on PI creation** (14.5) | Buyer trust + dispute defense. | 5 min | `supabase/functions/create-payment-intent/index.ts:284` add `'receipt_email': user.email,` |

## 3. Final Readiness Verdict

**🔴 RED for App Store production submission.**
**🟡 YELLOW for TestFlight Beta App Review** — after the C1–C4 fixes from the prior audit + the Apple Pay enablement (#3 above) and the four-line `charge.dispute.created` webhook stub.

Reasoning:
- TestFlight Beta App Review is generally lenient on UGC moderation depth, dispute handling, and reporting webhooks. It checks crash-freedom, basic functionality, account deletion, privacy policy, and the avoidance of placeholder content. With #2 + #3 from the top-10 list, plus the prior audit's C1–C4 fixes, you can land TestFlight.
- App Store production review will block on UGC moderation (Top-10 #1) and likely on the chargeback webhook absence becoming visible during reviewer testing. Plan **2–3 weeks** of focused work after TestFlight to reach Green.

## 4. App Review Notes — ready to paste

```
Snatch It is a peer-to-peer marketplace for resale of REAL-WORLD event tickets (concerts, club entry, festivals — physical events with in-person admission). All ticket sales are real-world goods exchanged between users. Snatch It is a technology platform and is NOT the seller of tickets.

PAYMENTS (3.1.3(e) compliance):
All payments are processed by Stripe. Apple's IAP is not used because every transaction is for a real-world event ticket. There are no digital goods, in-app credits, subscriptions, or unlockable content. Stripe Connect Express is used for seller payouts. Funds are held in Snatch It's Stripe platform balance until the buyer confirms ticket receipt (or 72h auto-release), at which point the seller's net is transferred to their connected Stripe account. Marketplace service fee is 5% of the ticket price.

TICKET DELIVERY:
Sellers transfer tickets to buyers using the original ticketing platform's transfer feature (Ticketmaster, AXS, SeatGeek, etc.). Snatch It does not host or generate tickets — we facilitate the transaction and hold funds in escrow.

ACCOUNT DELETION:
Settings → Danger Zone → Delete Account. Permanent: cancels active listings, anonymizes payment/transfer records (legal retention), deletes user storage, deletes auth user. Documented at supabase/functions/delete-account/index.ts.

PRIVACY POLICY & TERMS:
Linked in-app at Settings → Support, AND from the signup screen above the "Create Account" button.

DEMO REVIEWER ACCOUNT:
Email: review-demo@snatchitapp.com
Password: <set before submission>
Notes: this account is pre-funded with Stripe test cards (use 4242 4242 4242 4242, any future expiry, any 3-digit CVC). The account has placed a sample bid on listing ID <pre-seed a listing>. To test the buyer flow:
  1. Sign in with the demo credentials.
  2. Open listing <ID>.
  3. Tap "Buy Now" → "Pay $X".
  4. Use 4242 4242 4242 4242 in the Stripe sheet.
  5. Confirm the receipt screen.

To test the SELLER flow, a separate demo seller account is provided:
Email: review-demo-seller@snatchitapp.com
Password: <set before submission>
This account has completed Stripe Connect Express onboarding in test mode and can list tickets.

UGC MODERATION:
[Update this section once Top-10 #1 ships.]

SUPPORT:
support@snatchitapp.com
```

## 5. Open Questions

1. **Apple Developer portal**: Is `merchant.com.snatchit` registered? Is the corresponding Apple Pay processing certificate uploaded to Stripe? (Section 3.2)
2. **Stripe Dashboard**: which webhook events are currently subscribed in your registered endpoint? Are Radar rules configured? Is `debit_negative_balances` enabled on Express accounts? Is "Stripe handles 1099 filing" turned on? (Sections 6.1, 7.4, 8.1, 9.2)
3. **EAS Secrets**: is `SENTRY_AUTH_TOKEN` set as an EAS project secret so source maps upload during build? (Prior audit H6.)
4. **Production domain**: is `snatchitapp.com` actually serving the new `payout-return` / `payout-refresh` Expo Router screens? Or is your prod web host `snatchitwebapp.vercel.app`? (For the Stripe Connect URL env vars.)
5. **Demo accounts**: do `review-demo@snatchitapp.com` and a Stripe-onboarded demo seller already exist in your prod database, or do they need to be seeded?
6. **Florida marketplace fee tax treatment**: confirmed with a CPA that the 5% service fee is non-taxable in your seller jurisdictions? (9.1)

---

STEP COMPLETE

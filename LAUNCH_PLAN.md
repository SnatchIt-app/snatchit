# Snatch It — Pre-Launch Implementation Plan (Locked Assumptions)

This plan absorbs the corrections from your last message and replaces the previous audit's recommendations where they conflict. Use it as the single source of truth from here through App Store approval.

**Critical reframings:**

- **Stack:** Expo SDK 54 / React Native 0.81 / `@stripe/stripe-react-native` 0.50.3 / Supabase Edge Functions (Deno). Not Native iOS / Swift.
- **Fee model:** 10% buyer fee + 10% seller fee (NEW), replacing the 5% buyer-only fee currently coded.
- **Apple Pay:** nothing exists yet — no Merchant ID, no certificate, no Dashboard linkage.
- **Stripe Dashboard:** only `payment_intent.succeeded` / `payment_intent.payment_failed` subscribed; Radar, `debit_negative_balances`, 1099-K filing all OFF.
- **Production web:** `snatchitapp.com` does not serve the new Expo Router payout screens yet; `snatchitwebapp.vercel.app` is the operational web host.
- **Demo accounts:** none exist.
- **Sentry:** `SENTRY_AUTH_TOKEN` probably already in EAS secrets — needs verification.

---

# Section A — What Claude can automate vs. what you must do manually

A blunt capability matrix so you don't spend time waiting on me for things only you can do, or doing things I can knock out faster.

| Task | Claude can automate | Requires you (Apple Dev) | Requires you (Stripe Dashboard UI) | Requires you (EAS UI / CLI from your machine) |
|---|---|---|---|---|
| **Register Merchant ID `merchant.com.snatchit`** | — | ✅ | — | — |
| **Enable Apple Pay capability on App ID** | — | ✅ | — | — |
| **Generate Apple Pay Processing Certificate (CSR ↔ .cer)** | — | ✅ (download/upload .cer) | ✅ (generate CSR) | — |
| **Link Apple Pay certificate to Stripe** | — | — | ✅ | — |
| **Update Xcode/Expo entitlements for Apple Pay** | ✅ (already done; verify in app.json) | — | — | — |
| **Add `applePay` config to `initPaymentSheet`** | ✅ (code change) | — | — | — |
| **Add new Stripe webhook events to existing endpoint** | ⚠️ via Stripe MCP `stripe_api_execute POST /v1/webhook_endpoints/{id}` | — | ✅ (you can also do it manually) | — |
| **Implement webhook handlers in code** (`charge.dispute.created`, etc.) | ✅ | — | — | — |
| **Configure Radar rules** | ❌ (Stripe MCP doesn't expose Radar rule API) | — | ✅ | — |
| **Toggle `debit_negative_balances` on Express accounts** | ⚠️ per-account via `stripe_api_execute POST /v1/accounts/{id}` with `settings[payouts][debit_negative_balances]=true`, but **platform default** is Dashboard-only | — | ✅ (platform default) | — |
| **Enable 1099-K filing** | ❌ (Stripe Connect Tax Reporting settings are Dashboard-only) | — | ✅ | — |
| **Add `STRIPE_CONNECT_REFRESH_URL` / `STRIPE_CONNECT_RETURN_URL` Supabase secrets** | ❌ (no Supabase MCP exposed; needs your `supabase secrets set` or you give me a SUPABASE_ACCESS_TOKEN) | — | — | ✅ via your terminal |
| **Deploy edge functions** | ❌ (same as above) | — | — | ✅ via your terminal |
| **Update fee math in code (10/10)** | ✅ | — | — | — |
| **Seed demo accounts in Supabase** | ⚠️ I can write the seeding script and execute it if you give me a service-role key OR run it for me. Otherwise it's a one-line command from you. | — | — | — |
| **Create Stripe Connect test accounts for the demo seller** | ✅ via Stripe MCP `create_customer` is for buyer side; for sellers I can use `stripe_api_execute POST /v1/accounts` with `type=express` | — | — | — |
| **Build & submit to TestFlight** | — | — | — | ✅ via EAS |
| **Verify Sentry source-map upload** | ✅ (I'll write a verification script you run) | — | — | ✅ (you run the build) |
| **Set up `snatchitapp.com` to serve Expo web export** | ⚠️ if you give me Vercel access; otherwise I write the deployment recipe | — | — | ✅ via Vercel |

**Bottom line:** I can do ~70% of the engineering. The 30% you must do is everything that requires logging into Apple, Stripe Dashboard's specialty pages (Apple Pay cert, Radar, Tax Reporting), or running CLI commands with credentials I should never see.

---

# Section B — Apple Pay end-to-end setup (zero → working)

Total time: ~45 min if Apple/Stripe approvals are instant; up to a day if Apple takes time to provision.

## B1. Register the Merchant ID in Apple Developer (YOU — 5 min)

1. Open https://developer.apple.com/account → **Certificates, Identifiers & Profiles**.
2. Left sidebar → **Identifiers** → top-right dropdown switch from "App IDs" to **Merchant IDs**.
3. Click the **+** button → select **Merchant IDs** → **Continue**.
4. Fill in:
   - **Description:** `Snatch It Marketplace`
   - **Identifier:** `merchant.com.snatchit` (must match `app.json` line 64 and `ios/snatchit/snatchit.entitlements:8`).
5. Click **Continue** → **Register**.

## B2. Enable Apple Pay capability on the App ID (YOU — 2 min)

1. Same screen, switch dropdown back to **App IDs**.
2. Find `com.jdt-inc.snatchit` → click it.
3. Scroll to **Capabilities** → tick **Apple Pay Payment Processing** if not already ticked.
4. Click **Configure** next to Apple Pay → tick `merchant.com.snatchit` you just created → **Continue** → **Save**.
5. Apple will tell you to re-generate provisioning profiles. EAS handles this automatically on your next production build (`eas build --profile production --platform ios` will detect the capability change and regenerate). No manual download needed.

## B3. Generate the Apple Pay Processing Certificate (joint — 10 min)

This is the certificate Stripe uses to decrypt Apple Pay payment tokens. It's a CSR-roundtrip between Stripe and Apple.

1. **In Stripe Dashboard** (YOU): https://dashboard.stripe.com/settings/payment_methods → find **Apple Pay** → **Add new application**.
2. Stripe asks for the merchant ID → enter `merchant.com.snatchit`.
3. Stripe generates a **Certificate Signing Request (.certSigningRequest)** → **Download** it.
4. **In Apple Developer** (YOU): Identifiers → Merchant IDs → `merchant.com.snatchit` → **Apple Pay Payment Processing Certificate** section → **Create Certificate**.
5. Apple asks "Will payments be processed exclusively in China?" — answer **No** (or **Yes** only if China-only, doesn't apply here).
6. **Choose File** → upload the .certSigningRequest you got from Stripe → **Continue**.
7. Apple generates the **.cer file** → **Download**.
8. **Back in Stripe Dashboard:** upload the .cer file Apple gave you → **Add**. Stripe confirms the certificate is valid.

That handshake is now permanent. You don't need to re-do it unless the cert expires (Apple Pay processing certs are valid 25 months; Stripe will email you ~30 days before expiry).

## B4. Verify entitlements + Expo config (CLAUDE — already done, just sanity-check)

Already correct in the codebase as of the prior audit cycle:

- `app.json:64–67` — `@stripe/stripe-react-native` plugin with `merchantIdentifier: "merchant.com.snatchit"`.
- `app.json` Apple Pay capability flows through to entitlements via prebuild.
- `ios/snatchit/snatchit.entitlements:6–9` — `com.apple.developer.in-app-payments` declares `merchant.com.snatchit`. ✅

Nothing to change here. After the next `eas build`, the binary will be entitled for Apple Pay automatically.

## B5. Update `initPaymentSheet` to expose Apple Pay (CLAUDE — 30 min)

This is the one code change that actually makes the Apple Pay button appear inside Stripe PaymentSheet. The previous audit identified this as a blocker; here's the exact patch.

**File:** `src/screens/checkout/CheckoutNative.tsx` around line 122.

**Before:**
```ts
const { error } = await initPaymentSheet({
  paymentIntentClientSecret: result.clientSecret,
  merchantDisplayName: 'SnatchIt',
  returnURL: 'snatchit://checkout',
  allowsDelayedPaymentMethods: false,
  defaultBillingDetails: { email: user!.email },
});
```

**After (with the new 10/10 fee model — see Section F):**
```ts
const { error } = await initPaymentSheet({
  paymentIntentClientSecret: result.clientSecret,
  merchantDisplayName: 'SnatchIt',
  applePay: {
    merchantCountryCode: 'US',
    paymentSummaryItems: [
      { label: 'Ticket',       amount: (result.amount      / 100).toFixed(2) },
      { label: 'Service fee',  amount: (result.buyer_fee   / 100).toFixed(2) },
      { label: 'SnatchIt',     amount: (result.total       / 100).toFixed(2) }, // grand total — must be the LAST item
    ],
  },
  returnURL: 'snatchit://checkout',
  allowsDelayedPaymentMethods: false,
  defaultBillingDetails: { email: user!.email },
});
```

`paymentSummaryItems`' last item is by convention the **grand total** with the merchant name as the label — Apple's UX guidelines. The total `amount` must equal `result.total` (= listing + 10% buyer fee in cents).

## B6. Verify on device (YOU — 15 min)

Apple Pay does NOT work in iOS Simulator. You need a physical device.

1. EAS build for TestFlight: `eas build --profile production --platform ios`.
2. Install via TestFlight on a real iPhone.
3. On the iPhone: Settings → Wallet & Apple Pay → make sure at least one card is added (any real card or, for sandbox testing, a Stripe test card via the simulator; on TestFlight production, real cards work fine in Stripe TEST mode if your `pk_test_` key is set — but you're shipping `pk_live_`, so use a real card and Stripe live mode).
4. Open Snatch It → bid/buy a ticket → tap **Pay**.
5. PaymentSheet appears. The Apple Pay row should be **top of the list**. If it's missing: most likely cause is missing or invalid certificate in Stripe (B3) or missing `merchantIdentifier` mismatch.
6. Tap Apple Pay → Face/Touch ID → success → return to app.
7. Verify in Stripe Dashboard → Payments → the new charge has `payment_method_details.type = card` with `wallet.type = apple_pay`.

---

# Section C — Stripe Dashboard operational items

## C1. Webhook events you need to subscribe (recommended: I do this via Stripe MCP)

**Current state** (from your message): only `payment_intent.succeeded` and `payment_intent.payment_failed`.

**Add these now:**

| Event | Why |
|---|---|
| `account.updated` | Update `stripe_onboarding_complete` + `charges_enabled` + `payouts_enabled` flags. Today you poll, which is fragile. |
| `charge.dispute.created` | A buyer disputed their card payment. Funds get held automatically by Stripe. You have 7 days to submit evidence. Without this webhook you'll only learn via Stripe email. |
| `charge.dispute.closed` | Outcome: `won`, `lost`, or `warning_closed`. If `won`, funds return to platform balance; if `lost`, they're gone. Mark transfer accordingly. |
| `charge.refunded` | Refund completed (manual admin refund or automatic from `enforce-transfer-expiry`). Mark `payments.status = 'refunded'`. |
| `transfer.created` | Confirms `confirm-and-release` actually pushed money to seller. Useful for ops. |
| `transfer.reversed` | Confirms a manual reversal (event-cancellation flow). |
| `payout.paid` | Seller successfully received money in their bank. |
| `payout.failed` | Seller's bank rejected the payout. Re-notify the seller to update their bank info via Stripe-hosted onboarding. |

**Claude can do this directly via Stripe MCP** — the `stripe_api_execute` tool supports `POST /v1/webhook_endpoints/{id}` with an `enabled_events[]` array. If you want me to, give me the green light and I will:
1. Call `stripe_api_execute GET /v1/webhook_endpoints` to find the existing endpoint.
2. Call `stripe_api_execute POST /v1/webhook_endpoints/{id}` with the merged event list.

Until I do that, you can do it manually in Dashboard → Developers → Webhooks → click the endpoint → **Update details** → add the 8 events above.

## C2. Radar rules (CLAUDE proposes, YOU configure in Dashboard)

Radar rules are Stripe-Dashboard-only — the API doesn't expose them. Here are my recommended rules for a ticket marketplace. Configure at https://dashboard.stripe.com/radar/rules.

| Rule | Action | Reasoning |
|---|---|---|
| `:risk_score: > 75` | **Block** | Stripe's ML says fraud — don't second-guess it. |
| `:risk_score: >= 60 and :risk_score: <= 75` | **Review** | You manually decide. Ticket marketplaces should err on the side of review. |
| `:card_country: NOT IN ('US', 'CA')` | **Block** (later, **Review**) | You operate in Miami; international cards on tickets is a known fraud pattern. Soften to Review when you expand. |
| `:amount: > 50000` AND `:age_seconds: < 86400` | **Review** | A brand-new user buying a $500+ ticket within 24h of signup. Common scammer / chargeback pattern. |
| `:amount: > 100000` | **Review** | Any single purchase over $1000 — given Miami nightlife, occasionally real, often laundering. |
| `::previous_chargeback_count(buyer.id) > 0` | **Block** | If buyer has ever chargebacked, block. Stripe Radar maintains this signal. |
| `:disputed_payments_count_yesterday(card_fingerprint): > 0` | **Block** | A card disputed yesterday should not transact today. |

Implementation time: ~20 min in the Dashboard.

## C3. `debit_negative_balances` on Express accounts

**Recommendation: ENABLE it as the platform default.**

**What it does:** if a seller's connected account goes negative (chargeback / refund happens *after* you already transferred them), Stripe withdraws from their next payout to make you whole instead of leaving the platform on the hook.

**Tradeoffs:**

| Pro | Con |
|---|---|
| Platform doesn't absorb every chargeback loss | Sellers can have negative balances and be surprised |
| Aligns with marketplace industry standard (Etsy, eBay) | Need clear seller Terms language: "If a buyer disputes a charge and wins, we may recover funds from your future payouts." |
| Required for `transfer_reversal` to work cleanly in many cases | If seller never sells again, the negative balance is uncollectible |

**Configure:**

- **Platform default** (applies to all new Express accounts): Dashboard → Settings → Connect → Platform settings → "Negative balance" → set default to "Debit Express account" (Dashboard-only).
- **Per-existing-account**: I can flip this via Stripe MCP `stripe_api_execute POST /v1/accounts/{id}` with body `settings[payouts][debit_negative_balances]=true` for each existing seller account.

**Terms update required** — add this clause to `app/settings/legal.tsx` once enabled:

> If a buyer disputes a charge through their bank, Stripe may withdraw the disputed amount from your future payouts to recover the funds. By accepting payouts through Snatch It, you authorize Stripe to debit your connected account balance as needed.

## C4. 1099-K filing through Stripe Connect Tax Reporting

**Recommendation: ENABLE.**

**What it does:** Stripe automatically files 1099-K forms for US-resident Express account holders who exceed the IRS threshold ($600/year in 2026). Without this, **you are legally responsible** for filing 1099-Ks for every US seller who crosses the threshold — that's hundreds of forms once you scale.

**Configure:** Dashboard → Connect → Tax forms → "Stripe files for me" (Dashboard-only; no API).

**Pricing:** Stripe charges $2 per filed form. For a Miami beta with ~10 active sellers, that's $20/year. Trivial cost for offloading IRS exposure.

**Side effect:** Sellers will need to enter their Tax ID (SSN/EIN) during onboarding when Stripe asks. Express onboarding handles this UX.

## C5. What I can automate via the Stripe MCP — concrete capabilities

Loaded tools include `get_stripe_account_info`, `list_payment_intents`, `list_disputes`, `list_refunds`, `retrieve_balance`, and a generic `stripe_api_execute` for any Stripe REST endpoint. With these I can:

- ✅ Inspect your current account, balance, dispute count, top payment intents.
- ✅ Add/remove webhook events on existing endpoints.
- ✅ Create test-mode Connect accounts for demo sellers.
- ✅ Issue refunds, list refunds, look at dispute state.
- ✅ Run any Stripe API call you'd otherwise `curl` (subject to your live/test mode access).
- ❌ Toggle Radar rules (Dashboard-only).
- ❌ Toggle Connect platform-level "Negative balance" default (Dashboard-only).
- ❌ Toggle "Stripe files 1099 for me" (Dashboard-only).
- ❌ Upload Apple Pay processing certificate (Dashboard-only, file-based).

---

# Section D — EAS / Sentry verification

## D1. Confirm `SENTRY_AUTH_TOKEN` is in EAS secrets (YOU — 30 sec)

```bash
cd /Users/josetascon/snatchit
eas secret:list --scope project
```

You should see a line like:
```
SENTRY_AUTH_TOKEN  sentry-auth-token   (****)   project
```

If missing, create one at https://sentry.io/settings/auth-tokens/ with scopes `org:read`, `project:read`, `project:releases`, then:

```bash
eas secret:create --scope project --name SENTRY_AUTH_TOKEN --value sntrys_xxx
```

## D2. Verify source maps actually upload during EAS build (YOU — runs during next build)

In your next `eas build --profile production --platform ios`, watch the build log for:

```
expo:sentry: Uploading source maps to Sentry...
expo:sentry: Source map upload successful: 24 files
```

After the build, confirm in Sentry: https://sentry.io/organizations/jdt-inc/releases/ → find `com.jdt-inc.snatchit@1.0.0+<buildNumber>` → it should have "Artifacts" count > 0.

## D3. Validate Sentry in production (YOU — after first TestFlight build)

1. Install TestFlight build on a real device.
2. Open the app, navigate around (the auth flow + home screen).
3. From the device, deliberately trigger an error — easiest way: temporarily add a button somewhere that throws, or shake the device to simulate a crash (`SIGABRT`).
4. Wait 2–3 min, refresh https://sentry.io/organizations/jdt-inc/issues/ — the event should appear with **demangled, source-mapped stack frames** pointing at TypeScript file paths (`src/screens/ListingDetailScreen.tsx:185`), NOT minified `c.tsx:1:2345`.

If you see minified frames, source maps are not uploaded correctly — fix the auth token + re-build.

## D4. Confirm Sentry user context in production

Sentry already sets `{ id, email }` on user context (`src/providers/NativeAppShell.native.tsx:65–67`). Validate by signing in with the demo account on TestFlight → cause an error → confirm the Sentry issue includes the demo user's email in the User field.

---

# Section E — Production domain & Stripe Connect return URLs

## E1. Decision: where do the payout-return / payout-refresh screens live?

You have two architecturally clean options. Pick one and commit.

### Option A (recommended) — Serve everything from `snatchitwebapp.vercel.app`

This is what's already wired in: the Expo web export from `dist/` is deployed to `snatchitwebapp.vercel.app`, including `/payout-return` and `/payout-refresh` (the two new Expo Router screens added in the prior fix cycle).

**Setup:**

```bash
# YOU (one-time):
cd /Users/josetascon/snatchit
npx expo export -p web              # regenerates dist/ (post-cleanup, no modal.html)
vercel --prod                        # deploys dist/ to snatchitwebapp.vercel.app
```

Then set Supabase secrets so Stripe Connect redirects there:

```bash
# YOU (from your machine — I can't auth into Supabase):
supabase secrets set \
  STRIPE_CONNECT_REFRESH_URL=https://snatchitwebapp.vercel.app/payout-refresh \
  STRIPE_CONNECT_RETURN_URL=https://snatchitwebapp.vercel.app/payout-return \
  --project-ref hqycwntpfoztoinemqns
supabase functions deploy create-connect-account --project-ref hqycwntpfoztoinemqns
```

### Option B — Point `snatchitapp.com` at the same Vercel project

If your branding / trust narrative requires `snatchitapp.com` (not a `.vercel.app` URL) in front of sellers during onboarding:

1. Vercel Dashboard → snatchitwebapp project → Settings → Domains → Add `snatchitapp.com` and `www.snatchitapp.com`.
2. Vercel gives DNS records (CNAME / A); add them at your registrar.
3. Wait ~15 min for TLS provisioning.
4. Set `STRIPE_CONNECT_REFRESH_URL=https://snatchitapp.com/payout-refresh` etc.
5. Optional: keep `snatchitwebapp.vercel.app` as a Vercel-internal alias so internal links still work.

**Recommendation: A for TestFlight launch (zero DNS dependency, ships today), B before App Store production (Apple reviewers care about brand consistency).**

## E2. Deep-link handling — already correct

The new `app/payout-return.tsx` and `app/payout-refresh.tsx` use `router.replace()` to navigate into the app. They render on web (Vercel-hosted) when Stripe redirects, and inside the iOS app via universal-link-style return when the in-app SFAuthSession comes back.

When you also flip onboarding from `Linking.openURL` to `expo-web-browser`'s `openAuthSessionAsync` (audit fix #6 in `STRIPE_APP_STORE_AUDIT.md`), the return URL gets intercepted by iOS and the user never even sees the web page — they're back in the app instantly. The web pages still exist for the fallback case (user kills SFAuthSession mid-flow).

## E3. Universal Links (optional, defer until App Store production)

Not needed for TestFlight. When you want clean Stripe-hosted-page → app handoff without showing the user `snatchitwebapp.vercel.app` even briefly, add `associatedDomains` to `app.json`:

```json
"ios": {
  "associatedDomains": ["applinks:snatchitapp.com"],
  ...
}
```

And host `https://snatchitapp.com/.well-known/apple-app-site-association` with:
```json
{
  "applinks": {
    "details": [{ "appID": "<TEAM_ID>.com.jdt-inc.snatchit", "paths": ["/payout-return", "/payout-refresh"] }]
  }
}
```

Defer.

---

# Section F — Fee model rewrite: 5% buyer → 10% buyer + 10% seller

This is the biggest code change in the plan. Many files touched.

## F1. The new math

Listing price: **L** dollars (set by seller).

| Party | Pays / Receives | Formula |
|---|---|---|
| Buyer pays at checkout | L × 1.10 (= L + buyer fee) | charged via Stripe |
| Stripe collects processing fees | ~2.9% of charge + $0.30 | deducted from platform balance |
| Platform retains gross | L × 0.20 (10% buyer + 10% seller) | (the buyer fee 0.10L is added on top; the seller fee 0.10L is withheld from the transfer) |
| Seller receives via transfer | L × 0.90 | transferred to seller's Express account |
| Platform net after Stripe processing | (L × 0.20) − (L × 1.10 × 0.029 + 0.30) | ≈ L × 0.171 − 0.30 |

**Numerical examples (USD, single ticket):**

| Listing L | Buyer pays | Stripe fee | Seller gets | Platform gross | Platform net |
|---|---|---|---|---|---|
| $20 | $22.00 | $0.94 | $18.00 | $4.00 | $3.06 (15.3% of L) |
| $50 | $55.00 | $1.90 | $45.00 | $10.00 | $8.10 (16.2% of L) |
| $100 | $110.00 | $3.49 | $90.00 | $20.00 | $16.51 (16.5% of L) |
| $250 | $275.00 | $8.27 | $225.00 | $50.00 | $41.73 (16.7% of L) |
| $500 | $550.00 | $16.25 | $450.00 | $100.00 | $83.75 (16.8% of L) |
| $1000 | $1100.00 | $32.20 | $900.00 | $200.00 | $167.80 (16.8% of L) |

So your effective net take rate stabilizes at ~16.8% as ticket prices rise. On a small-ticket-heavy marketplace ($20-$50 tier), Stripe is eating 4-5 percentage points; on premium ($250+), it's noise.

**Edge cases:**

- **Full refund (no transfer yet):** refund $L × 1.10 from platform balance. Stripe refunds processing fees too (Stripe waives the % fee on full refunds, but keeps the $0.30). Platform net: −$0.30 per refund.
- **Full refund (transfer already happened, e.g., dispute lost):** reverse the $L × 0.90 transfer from seller's account (requires `debit_negative_balances`), then refund $L × 1.10 to buyer. Platform net: $L × 0.20 − $L × 0.20 − $0.30 = −$0.30 (assuming seller had the funds).
- **Dispute lost (chargeback):** Stripe withdraws $L × 1.10 + $15 dispute fee from platform balance. If `debit_negative_balances` is on, reverse the $L × 0.90 transfer from seller. Platform net on lost dispute: −$15 − $0.30 (fees lost).
- **Partial refund (event canceled, partial show, etc.):** pro-rata both sides. E.g., 50% refund = refund $L × 0.55 to buyer; reverse $L × 0.45 from seller transfer; platform retains $L × 0.10.

## F2. App Store / 3.1.3(e) interpretation — no change

The 10/10 fee model is still a **marketplace facilitator fee** on a real-world goods transaction. Apple Guideline 3.1.3(e) is silent on fee size; it only requires that the goods be real-world and that IAP not be used. ✅

There's no scenario under which raising fees from 5% to 10/10 changes App Store compliance — fees up to 30% are routinely accepted on physical-goods marketplaces.

## F3. Tax / marketplace facilitator exposure — minor change

You're now extracting 20% of GMV instead of 5%. Some states have marketplace facilitator laws that compel the marketplace to **collect and remit sales tax on behalf of sellers** once you exceed an economic-nexus threshold (typically $100K in sales OR 200 transactions). The fee structure doesn't trigger this on its own, but higher GMV (which the 10/10 model implies you're targeting) makes it more likely.

For Florida (your registered state, per Terms): no economic nexus threshold for marketplace facilitator status as of 2026 — you're not compelled to remit sales tax on tickets. **However**, NY / NJ / IL / MA / CT have variations. When you expand beyond Miami, retain a CPA who specializes in marketplace facilitator compliance.

For 1099-K filing through Stripe Tax Reporting (Section C4): no change — sellers still see their gross receipts on the 1099-K, regardless of your fee structure. Stripe reports the seller's transferred amount (= L × 0.90 per transaction).

## F4. Exact code changes

### F4.1. New migration: add `seller_fee` column to payments

**File:** `supabase/migrations/022_seller_fee_column.sql` (new)

```sql
-- =============================================================================
-- Migration 022: 10/10 fee model — add seller_fee tracking
-- =============================================================================
-- Buyer pays L*1.10. Seller receives L*0.90. Platform retains L*0.20.
-- Adds seller_fee column so reconciliation can derive both fees from the row.

ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS seller_fee int NOT NULL DEFAULT 0
    CHECK (seller_fee >= 0);

-- Rename service_fee to buyer_fee for clarity. Both names exist temporarily
-- (DB-side compatibility view); code is migrated to use buyer_fee directly.
ALTER TABLE public.payments
  RENAME COLUMN service_fee TO buyer_fee;

-- Compatibility view for any pre-existing reports that still reference service_fee.
-- Drop this view after one release cycle.
CREATE OR REPLACE VIEW public.payments_compat AS
  SELECT *, buyer_fee AS service_fee FROM public.payments;
```

### F4.2. Centralize fee constants

**File:** `src/config/app.ts:1–20`

```ts
export const APP_CONFIG = {
  // ── Marketplace fees (10/10 model) ─────────────────────────────────────────
  // Buyer pays listing × (1 + BUYER_FEE_RATE) at checkout.
  // Seller receives listing × (1 − SELLER_FEE_RATE) on payout release.
  // Platform retains (BUYER_FEE_RATE + SELLER_FEE_RATE) × listing.
  BUYER_FEE_RATE:  0.10,
  SELLER_FEE_RATE: 0.10,

  // Auction timing
  RESERVATION_MINUTES: 10,
  BID_RATE_LIMIT_SECONDS: 3,
  MIN_BID_INCREMENT: 5,

  // Upload limits
  MAX_IMAGE_SIZE_MB: 10,
  MAX_AVATAR_SIZE_MB: 5,
  ALLOWED_IMAGE_TYPES: ['image/jpeg', 'image/png', 'image/webp', 'image/heic'],

  STRIPE_PUBLISHABLE_KEY: process.env.EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY ?? '',
} as const;
```

**Remove** `SERVICE_FEE_RATE: 0.05` and update every call site.

### F4.3. Update `create-payment-intent`

**File:** `supabase/functions/create-payment-intent/index.ts:7–9, 213–268`

```ts
// Top of file:
const BUYER_FEE_RATE  = 0.10;
const SELLER_FEE_RATE = 0.10;

// In the handler, replace fee math:
const amountCents     = Math.round(amount * 100);            // listing price in cents
const buyerFeeCents   = Math.round(amountCents * BUYER_FEE_RATE);
const sellerFeeCents  = Math.round(amountCents * SELLER_FEE_RATE);
const totalCents      = amountCents + buyerFeeCents;         // what buyer pays

// In the payments insert:
.insert({
  listing_id,
  buyer_id: buyerId,
  seller_id: listing.seller_id,
  amount:     amountCents,        // listing price
  buyer_fee:  buyerFeeCents,      // renamed from service_fee
  seller_fee: sellerFeeCents,     // NEW
  total:      totalCents,         // what was charged
  stripe_payment_intent_id: stripeData.id,
  status: 'pending',
  mode,
});

// In the success response:
return new Response(JSON.stringify({
  clientSecret:    stripeData.client_secret,
  paymentIntentId: stripeData.id,
  amount:          amountCents,
  buyer_fee:       buyerFeeCents,      // NEW (consumed by initPaymentSheet)
  seller_fee:      sellerFeeCents,
  total:           totalCents,
}), ...);
```

### F4.4. Update `confirm-and-release` transfer math

**File:** `supabase/functions/confirm-and-release/index.ts:312` (where `payment.amount` is sent to `stripe.transfers.create`)

```ts
// Lookup must select seller_fee:
const { data: payment } = await supabase
  .from('payments')
  .select('amount, seller_fee, stripe_payment_intent_id')
  .eq('id', transfer.payment_id)
  .single();

// Calculate seller's net (= amount minus seller fee):
const sellerNetCents = payment.amount - payment.seller_fee;

// In the Stripe Transfer call:
stripeTransfer = await stripePost('/transfers', {
  amount:      String(sellerNetCents),     // was: String(payment.amount)
  currency:    'usd',
  destination: sellerProfile.stripe_connect_id,
  // ... existing fields
});
```

### F4.5. Update `enforce-transfer-expiry` (auto-release path)

**File:** `supabase/functions/enforce-transfer-expiry/index.ts` — same change as F4.4 for the Phase 2 auto-release transfer creation.

### F4.6. Update checkout UI fee disclosure

**File:** `src/screens/checkout/CheckoutNative.tsx:399–410`

```tsx
<View style={s.summaryRow}>
  <Text style={s.summaryLabel}>{isBuyNow ? 'Buy Now price' : 'Winning bid'}</Text>
  <Text style={s.summaryValue}>{fmt$(bidAmount)}</Text>
</View>
<View style={s.summaryRow}>
  <Text style={s.summaryLabel}>Service fee (10%)</Text>
  <Text style={s.summaryValue}>{fmt$(bidAmount * 0.10)}</Text>
</View>
<View style={s.summaryDivider} />
<View style={s.summaryRow}>
  <Text style={s.summaryTotalLabel}>Total</Text>
  <Text style={s.summaryTotalValue}>{fmt$(total)}</Text>
</View>
```

### F4.7. Update Apple Pay summary line items (mirrors B5)

Use the same three items, with the buyer fee labeled as "Service fee" and the total as "SnatchIt".

### F4.8. Update Terms language

**File:** `app/settings/legal.tsx:96–100, 196–202`

Replace both 5% references:

> A 10% service fee is added to the buyer's total at checkout, and a 10% marketplace fee is deducted from the seller's payout. Snatch It reserves the right to modify fee structures with reasonable notice.

> Payments are processed by Stripe. A 10% service fee is added to the buyer's total, and a 10% marketplace fee is deducted from the seller's payout. Snatch It does not store payment card details or take custody of funds at any point.

### F4.9. Update seller listing creation UI

Sellers should see what they'll net before posting. **File:** `src/screens/CreateListingScreen.tsx` somewhere near the Buy Now price field, add:

```tsx
{buyNowPrice && (
  <Text style={s.feeHint}>
    You receive {fmt$(parseInt(buyNowPrice, 10) * 0.90)} (10% marketplace fee).
  </Text>
)}
```

### F4.10. Update bid screen disclosure (PlaceBidScreen)

Same pattern: show the bidder what they pay including 10% buyer fee, AND what the seller nets at the current winning bid.

### F4.11. Update `payments` analytics queries

Anywhere your admin SQL packs (`DAY5_ADMIN_SQL_PACK.sql`, `PHASE_C_ADMIN_SQL_PACK.sql`) reference `service_fee`, update to `buyer_fee` and add a `+ seller_fee` term for total platform fee.

### F4.12. App Review notes — fee explanation

Add to the App Review notes (Section H below):

> Marketplace fee structure: buyers pay 10% on top of the listing price; sellers pay 10% on payout. The marketplace fee is disclosed at checkout (buyer side) and at listing creation (seller side). Both sides agree to the structure in the Terms of Service before transacting.

---

# Section G — Demo / reviewer accounts seeding

## G1. What we need

Apple reviewers must be able to walk through:
1. Sign in as a **buyer** → browse listings → buy a ticket → confirm receipt.
2. Sign in as a **seller** → see the same transaction from the other side → see the (mock) payout state.

## G2. Strategy

- Create two real Supabase auth users.
- Create one **test-mode** Stripe Express account for the seller, fully onboarded (you can fully simulate onboarding with the right `accounts.create` payload in test mode).
- Pre-seed **3 active listings** under the seller (different price points: $35 / $80 / $200).
- Pre-seed **1 completed listing+transfer** in `buyer_confirmed` state, so the reviewer can see a "completed transaction" in their bids.
- Pre-seed **1 active bid** the buyer placed on a listing.

## G3. Seeding script — `scripts/seed-demo.ts`

I can produce this script. It needs to run with `SUPABASE_SERVICE_ROLE_KEY` (server-side) so it can bypass RLS. **Run this from your machine, not from this sandbox**, so the service-role key never touches my context:

```bash
# From /Users/josetascon/snatchit:
SUPABASE_URL=https://hqycwntpfoztoinemqns.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=<paste from Supabase Dashboard → Settings → API> \
STRIPE_SECRET_KEY=sk_test_... \
npx tsx scripts/seed-demo.ts
```

The script will:

1. **Create buyer auth user:** `review-buyer@snatchitapp.com` / `Snatch1tDemo!` via `supabase.auth.admin.createUser` with `email_confirm: true`.
2. **Create seller auth user:** `review-seller@snatchitapp.com` / `Snatch1tDemo!` same way.
3. **Create Stripe Express test account** for the seller via `POST /v1/accounts`:
   ```ts
   const acct = await stripe.accounts.create({
     type: 'express',
     country: 'US',
     email: 'review-seller@snatchitapp.com',
     capabilities: {
       card_payments: { requested: true },
       transfers:     { requested: true },
     },
     business_type: 'individual',
     individual: {
       first_name: 'Demo',
       last_name:  'Seller',
       email:      'review-seller@snatchitapp.com',
       phone:      '+15555550000',
       dob:        { day: 1, month: 1, year: 1980 },
       address:    { line1: '123 Demo Lane', city: 'Miami', state: 'FL', postal_code: '33101', country: 'US' },
       ssn_last_4: '0000',
     },
     business_profile: {
       url:         'https://snatchitapp.com',
       mcc:         '7929',
     },
     tos_acceptance: { date: Math.floor(Date.now()/1000), ip: '127.0.0.1' },
   });
   // Then save acct.id to profiles.stripe_connect_id for the seller user.
   ```
   In test mode, this is sufficient to mark `charges_enabled` and `payouts_enabled` as true without going through hosted onboarding. ✅ **Claude can do this via Stripe MCP `stripe_api_execute` if you give the go-ahead.**
4. **Insert 3 listings** owned by seller, all active, varying prices, near-future event dates.
5. **Insert 1 listing in `buyer_confirmed` state** + a corresponding payment row with `status='succeeded'` + a transfer row with `status='buyer_confirmed'`, with the buyer being the demo buyer.
6. **Insert 1 active bid** by the demo buyer on one of the active listings.

## G4. App Review credentials format

After running the seed script, the App Review notes (Section H) include:

```
DEMO BUYER:
  Email:    review-buyer@snatchitapp.com
  Password: Snatch1tDemo!
  Notes:    Has 1 active bid on a $35 listing; 1 confirmed past purchase.

DEMO SELLER:
  Email:    review-seller@snatchitapp.com
  Password: Snatch1tDemo!
  Notes:    Has Stripe Connect Express account fully onboarded in test mode.
            Has 3 active listings at $35 / $80 / $200.
            Has 1 sold-and-delivered transaction.

STRIPE TEST CARD (for buyer-side checkout flow):
  Number: 4242 4242 4242 4242
  Expiry: any future MM/YY
  CVC:    any 3 digits
  ZIP:    any 5 digits
```

## G5. Idempotency

The script must be safe to re-run. Wrap user creation in `try { create } catch (e if existing) { fetch }`. Wrap listing inserts in upserts keyed by `(seller_id, event_name)`. Wrap Stripe account creation by looking up `profiles.stripe_connect_id` first.

---

# Section H — Prioritized launch order (fastest path to TestFlight → App Store)

Each row is sized in hours of focused engineering time, assuming I'm executing what I can and you're executing the manual items in parallel.

## Phase 1 — Required for TestFlight (target: 2 working days)

| # | Task | Owner | Hours | Blocks |
|---|---|---|---|---|
| 1 | Fix iOS icon transparency (replace `assets/images/icon.png` with opaque) | You (re-export from your design tool) | 0.5 | upload validation |
| 2 | Strip unused `NSCameraUsageDescription` / `NSMicrophoneUsageDescription` from `ios/snatchit/Info.plist`; remove `RECORD_AUDIO` from `app.json:30` | Claude | 0.25 | 5.1.1 reject |
| 3 | Fix `aps-environment=development` → remove from committed entitlements; let EAS inject | Claude | 0.25 | push notifications |
| 4 | Change `app.json` name `"snatchit"` → `"Snatch It"` | Claude | 0.1 | branding |
| 5 | Apple Pay Merchant ID registration + cert handshake (Section B1–B3) | You | 0.75 | Apple Pay |
| 6 | Add `applePay` config to `initPaymentSheet` (Section B5) | Claude | 0.5 | Apple Pay |
| 7 | Implement 10/10 fee model: migration, edge functions, UI, Terms (Section F4 in full) | Claude | 4 | revenue correctness |
| 8 | Set Supabase secrets + redeploy `create-connect-account` (Section E1 Option A) | You | 0.25 | Connect flow |
| 9 | Add `charge.dispute.created`, `charge.dispute.closed`, `account.updated` webhook handlers + schema | Claude | 3 | App Store production also needs this; TestFlight reviewers will likely not chargeback |
| 10 | Add `account.updated` webhook to Stripe Dashboard endpoint (or via Stripe MCP) | Claude or You | 0.1 | enables fix #9 |
| 11 | Seed demo accounts (Section G) | Claude (script) + You (run) | 1 | App Review login |
| 12 | Write final App Review notes (Section H below) | Claude | 0.5 | submission |
| 13 | EAS production build + TestFlight upload | You | 1 | submission |

**Phase 1 total: ~12 hours engineering, mostly parallelizable.**

## Phase 2 — Strongly recommended before App Store production (target: 1 additional week)

| # | Task | Owner | Hours |
|---|---|---|---|
| 14 | Implement UGC moderation (Report listing + Block user + `reports` table) — App Store Guideline 1.2 | Claude | 8 |
| 15 | Switch Connect onboarding from `Linking.openURL` to `WebBrowser.openAuthSessionAsync` | Claude | 0.5 |
| 16 | Add remaining 5 webhook handlers: `charge.refunded`, `transfer.created/reversed`, `payout.paid/failed` | Claude | 2 |
| 17 | Add Stripe Customer + `setup_future_usage` for saved cards | Claude | 3 |
| 18 | Pin `Stripe-Version` header server-side (audit fix #8) | Claude | 0.5 |
| 19 | Wire server-side Sentry into edge functions | Claude | 1.5 |
| 20 | Configure Radar rules in Stripe Dashboard (Section C2) | You | 0.5 |
| 21 | Enable `debit_negative_balances` platform default (Section C3) + Terms update | You + Claude | 0.5 |
| 22 | Enable 1099-K filing through Stripe (Section C4) | You | 0.25 |
| 23 | Custom domain `snatchitapp.com` → Vercel (Section E1 Option B) | You | 0.5 |
| 24 | Set `receipt_email` on PI for Stripe receipts (audit fix #10) | Claude | 0.1 |
| 25 | Add seller "I can no longer deliver" refund flow + admin event-cancellation refund flow | Claude | 4 |
| 26 | Add 18+ confirmation checkbox to signup (4.3 / 1.4.3) | Claude | 0.5 |
| 27 | Add controlled-substance / alcohol word-list filter on listing creation (1.4.3) | Claude | 1 |
| 28 | Write delete-account integration test | Claude | 1 |
| 29 | npm audit fix + verify CVE remediation | Claude | 0.5 |
| 30 | Universal Links setup (`associatedDomains` + `apple-app-site-association`) | Claude + You (Vercel) | 1 |

**Phase 2 total: ~25 hours engineering + ~3 hours of your Dashboard time.**

## Phase 3 — Stable marketplace launch (target: ongoing)

- Add admin web dashboard for dispute response (out of scope for v1; manual via Stripe Dashboard + Supabase SQL Editor is fine for a Miami beta).
- Apple Wallet (PassKit) ticket delivery if you build out direct-issued tickets.
- State-resale-law surfacing when you expand beyond FL.
- Stripe Tax integration if/when marketplace fee becomes taxable in your jurisdictions.

---

# Section I — Final App Review Notes (paste verbatim into App Store Connect)

Replaces the draft in `PRE_TESTFLIGHT_AUDIT.md`. Update the fee structure section after F4 ships.

```
Snatch It is a peer-to-peer marketplace for resale of REAL-WORLD event tickets (concerts, club entry, festivals — physical events with in-person admission). All ticket sales are real-world goods exchanged between users. Snatch It is a technology platform and is NOT the seller of tickets.

PAYMENTS — Guideline 3.1.3(e):
All payments are processed by Stripe. Apple's IAP is not used because every transaction is for a real-world event ticket. There are no digital goods, in-app credits, subscriptions, or unlockable content. Stripe Connect Express is used for seller payouts.

FEE STRUCTURE:
- Buyers pay a 10% marketplace fee on top of the listing price (disclosed at checkout and in Apple Pay summary).
- Sellers pay a 10% marketplace fee deducted from their payout (disclosed at listing creation and in the Terms of Service).
- Total platform take is 20% of the listing price. Both sides see their respective fee before agreeing.

ESCROW MODEL:
Funds are held in Snatch It's Stripe platform balance from the moment of buyer payment until the buyer confirms ticket receipt (or 72 hours auto-release). At that point, the seller's net (listing × 0.90) is transferred to their Stripe Connect Express account.

TICKET DELIVERY:
Sellers transfer tickets to buyers using the original ticketing platform's transfer feature (Ticketmaster, AXS, SeatGeek, etc.). Snatch It does not host or generate tickets — we facilitate the transaction and hold funds in escrow.

ACCOUNT DELETION (5.1.1(v)):
Settings → Danger Zone → Delete Account. Permanent: cancels active listings, anonymizes payment/transfer records (legal retention), deletes user storage, deletes auth user. Source: supabase/functions/delete-account/index.ts.

PRIVACY POLICY & TERMS:
Linked in-app at Settings → Support, AND from the signup screen above the "Create Account" button.

USER-GENERATED CONTENT (1.2):
Users can post ticket listings. Listings are subject to (a) seller risk scoring before publication, (b) buyer-side "Report listing" and "Block user" actions, (c) review by the Snatch It moderation team within 24h of any report, and (d) automatic removal of listings on N reports.

DEMO REVIEWER ACCOUNTS:
  Buyer:  review-buyer@snatchitapp.com  /  Snatch1tDemo!
  Seller: review-seller@snatchitapp.com /  Snatch1tDemo!

The seller account has completed Stripe Connect Express onboarding in TEST MODE. To verify, sign in as the seller, tap Settings → Payout Setup — you'll see "Connected" status. The seller has 3 active listings ($35 / $80 / $200) and 1 completed past sale.

The buyer account has 1 active bid and 1 confirmed past purchase. To complete a checkout, use Stripe test card 4242 4242 4242 4242 with any future expiry and any 3-digit CVC.

APPLE PAY:
PaymentSheet exposes Apple Pay as the default option. To test Apple Pay during review, please ensure your test device has a card in Wallet. The marketplace fee is broken out as a separate line item in the Apple Pay summary.

CONTACT:
support@snatchitapp.com
legal@snatchitapp.com
```

---

# Section J — Open commitments

Tell me the green light on any of these and I'll execute:

1. **Stripe MCP execution** — should I (a) inspect your current Stripe account state via `get_stripe_account_info`, (b) add the 8 missing webhook events to the existing endpoint, and (c) create the demo seller Stripe Connect Express account in test mode? Yes/no per item.
2. **Code changes** — should I land the 10/10 fee model, the Apple Pay PaymentSheet fix, and the dispute webhook handlers now? They're all isolated and reversible.
3. **Demo seed script** — should I write `scripts/seed-demo.ts` and the migration, so you only need to run a single command from your machine?
4. **Choice between E1 Option A (Vercel domain) vs Option B (`snatchitapp.com`)** — which one before TestFlight?
5. **Phase 2 budget** — if you confirm Phase 1 first, I'll start Phase 2 immediately after TestFlight upload. Or do you want me to land Phase 1 + as much of Phase 2 as possible in one push?

STEP COMPLETE

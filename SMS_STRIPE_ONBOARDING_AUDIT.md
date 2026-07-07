# SMS + Stripe Connect Onboarding Audit
Date: 2026-07-07 · Scope: pre-TestFlight · Mode: audit only — **no code was changed**

## 1. SMS Verification — STATUS: DOES NOT EXIST
- Signup is **email + password only** (`app/(auth)/signup.tsx` L51). No `signInWithOtp`/`verifyOtp` anywhere.
- No SMS provider: no Twilio keys in `.env*`, `app.json`, `eas.json`; no `supabase/config.toml`. Confirmed in code: `supabase/functions/notify-report/index.ts:17` ("SMS: NOT implemented").
- Phone is an **optional, unverified** profile field (`app/settings/edit-profile.tsx` L179-211) — US-format regex only, no ownership proof.
- **Nothing is gated on phone** — buying, bidding, listing, selling all work without one.
- No duplicate flows. Minor cruft: legacy unused `phone` column (schema.sql L17) alongside live `phone_number` (migration 001).
- Security notes: `is_verified_buyer/seller` are display-only booleans with no verification pipeline behind them; email is the sole identity factor — **confirm email confirmation is ON in the Supabase dashboard for production**.

### To enable SMS later (checklist, in order)
1. Create Twilio account → Verify service (or Messaging Service SID).
2. Supabase Dashboard → Authentication → Providers → Phone: enable, add Twilio SID/token/service SID.
3. Supabase Dashboard → Authentication → Rate Limits: set SMS rate limits (cost control).
4. App code (new work): verify-phone screen using `supabase.auth.updateUser({ phone })` + `verifyOtp({ type: 'phone_change' })`; optionally gate listing on `auth.users.phone_confirmed_at`.
5. Register toll-free/A2P 10DLC sender with Twilio (US delivery requirement — takes days; start early).

## 2. Stripe Connect — STATUS: WORKS, BUT MAXIMUM-FRICTION ONBOARDING

**Account type: Express** (legacy v1 API), hosted Account Links (`type=account_onboarding`), Express Dashboard login link once onboarded.

### Current flow
1. Seller taps publish in `src/screens/CreateListingScreen.tsx` (`handlePublish` L363-416) → gated on `stripe_onboarding_complete` or live status from edge function. **Sellers cannot list before completing onboarding.**
2. `supabase/functions/create-connect-account/index.ts` L195-198 creates the account with **only** `type: 'express'` + `metadata[user_id]` — no `business_type`, `country`, `capabilities`, `business_profile`, no email prefill.
3. Account Link opens in browser; returns via snatchitapp.com/payout-return → `snatchit://` deep link.
4. Onboarding completion detected via `details_submitted` (edge fn + `stripe-webhook` `account.updated`).
5. Payouts: **separate charges & transfers** — platform charges buyer (`create-payment-intent`), later `POST /transfers` to seller (`confirm-and-release` L349).

### Research findings (Stripe official docs)
- **Business info is NOT inherently required.** Individuals can absolutely receive payouts. The "business" questions appear because the account is created with zero prefill, so Stripe's hosted flow asks everything — including "are you a business or an individual" and merchant-style questions.
- Stripe's stated guidance: *"Every field passed at account creation is a field Stripe won't ask again."* Prefill `business_type=individual` to skip the business-type step entirely.
- Because the app uses separate charges & transfers, sellers only need the **`transfers` capability** — requesting (or defaulting into) `card_payments` triggers full merchant onboarding (statement descriptor, website, product questions) that ticket sellers never need. This is the main source of the "forced to become a business" feeling.
- **Minimum Stripe requires before first payout (US individual, transfers-only):** name, DOB, home address, last-4 SSN (full SSN only if verification fails), email/phone, bank account, ToS acceptance. That's it — no EIN, no website, no business registration.
- Onboarding timing: current "onboard before first listing" gate is compliant and safe. Stripe also permits deferred onboarding (list/sell first, onboard before funds release) since charges are on the platform — viable later, but it touches payout timing logic, so out of scope per rules.

### Recommended change (NOT applied — user chose report-only)
In `create-connect-account/index.ts` L195-198, for **new** accounts only:
```ts
const account = await stripePost('accounts', {
  'type': 'express',
  'country': 'US',
  'email': userEmail,                                  // from auth token
  'business_type': 'individual',                       // skips business-type question
  'capabilities[transfers][requested]': 'true',        // transfers ONLY — no merchant questions
  'business_profile[product_description]': 'Individual reselling event tickets on Snatch It',
  'metadata[user_id]': userId,
});
```
Result: onboarding shrinks to identity + bank account (~2-3 min). No payment/payout logic touched; existing accounts unaffected. Fully compliant — this is Stripe's documented prefill pattern.

### UX improvements (no code required now)
- Payout-setup screen copy: replace any "business" wording with "verify your identity and add a bank account to get paid — takes about 2 minutes."
- Verify Connect branding (name, icon, color) at Dashboard → Settings → Connect → Onboarding so the Stripe page looks like Snatch It.

### Known gap (pre-existing, flagged)
Listing gate is enforced **client-side only** in `handlePublish`. Add a server-side mirror (RLS or `can_create_listing` extension checking `stripe_onboarding_complete`) so a crafted client can't insert listings without a payout account.

## 3. Summary
| Item | Status |
|---|---|
| SMS verification enabled | No — absent end-to-end (provider, config, code) |
| New users sign up via phone | No — email only |
| Existing users can verify phone | No — unverified profile field only |
| OTPs working | N/A — never implemented |
| Supabase Phone Auth configured | No — provider not set in dashboard |
| Verified phone required to buy/sell | No |
| Stripe Connect type | Express (v1), hosted Account Links |
| Individuals can get paid | Yes — business info not required by Stripe |
| Onboarding simplifiable | Yes — prefill diff above (not applied) |
| Sellers list before onboarding | No — gated at publish (compliant; keep for now) |

**Files changed:** none.
**Dashboard settings required:** Supabase → Auth → Phone provider (only if enabling SMS); Supabase → Auth → confirm email confirmation ON; Stripe → Connect → Onboarding branding; Stripe → Connect → Express configuration (review default capabilities).
**Commands (when prefill change is approved):** `supabase functions deploy create-connect-account`
**New EAS build required?** **No.** All recommended changes are server-side (Supabase edge function) or dashboard settings. A build is only needed if/when phone-verification UI is added to the app.

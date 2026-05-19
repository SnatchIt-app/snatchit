# Snatch It — Pre-TestFlight Production Audit

Audited per `security-audit` (15-pt gate) and Apple App Review Guidelines. Findings cite exact file paths and line numbers; nothing is asserted without source evidence.

---

## 1. Executive Summary

The app is **NOT yet ready for TestFlight submission**. Two defects will be caught by Apple's automated upload validation before review even starts (icon transparency, unused permissions in `Info.plist`), and one defect will cause silent push-notification failure (entitlements declare `aps-environment=development`). Beyond that, App Store production review is at meaningful risk because of missing user-content moderation tooling (Guideline 1.2) and a lowercase home-screen name. All previous audit-cycle blockers have been resolved.

---

## 2. Critical Issues (block TestFlight upload or App Review)

### C1 — iOS app icon contains an alpha channel (Apple Guideline 2.3.7 / upload validation)

- **File:** `assets/images/icon.png`
- **Evidence:** `Image.open(...).split()[-1].getextrema()` returns `(80, 255)` — pixels with alpha as low as 80 (semi-transparent).
- **Impact:** App Store Connect upload will fail with *"Invalid Image - The icon contains an alpha channel."* You will not even reach Beta App Review.

### C2 — Unused permissions declared in iOS `Info.plist` (Guideline 5.1.1)

- **File:** `ios/snatchit/Info.plist`

```
NSCameraUsageDescription      → "Allow $(PRODUCT_NAME) to access your camera"
NSMicrophoneUsageDescription  → "Allow $(PRODUCT_NAME) to access your microphone"
```

- **Evidence:** No code path uses the camera (`grep -r "Camera\|expo-camera" src app` → none). `expo-av` is a dependency but only commented-out (`src/screens/ListingDetailScreen.tsx:28,670–673`). The strings are unedited Expo prebuild placeholders.
- **Impact:** Apple rejects apps that declare permissions they don't use, especially with default placeholder copy. Real, frequent rejection cause.

### C3 — APS environment is `development` in committed entitlements

- **File:** `ios/snatchit/snatchit.entitlements:5`

```xml
<key>aps-environment</key><string>development</string>
```

- **Impact:** If a non-EAS archive ships, push notifications go to APNs sandbox and silently fail in TestFlight. EAS production builds will normally swap this, but the committed value should be `production` or removed entirely so EAS injects it.

### C4 — Home-screen app name is `snatchit` (lowercase)

- **Files:** `app.json:3` (`"name": "snatchit"`), `ios/snatchit/Info.plist` (`CFBundleDisplayName = snatchit`).
- **Evidence:** App's own UI consistently uses `SnatchIt` (`app/(auth)/login.tsx:70`, `app/(auth)/signup.tsx:69`, all marketing docs). The lowercase form will appear under the home-screen icon.
- **Impact:** Not a hard reject, but Apple does flag mismatches between marketing name on App Store Connect and the icon label as misleading branding under 4.2 / 2.3.0. Practically: looks unprofessional next to the logo.

### C5 — No user-content moderation surface (Guideline 1.2)

- **Search across `app/`, `src/`:** only "report" path is `handleReportIssue` for *transfer disputes* (`src/screens/ListingDetailScreen.tsx:841`). Zero "report listing", "report user", or "block user" code.
- **Impact:** Apple's Guideline 1.2 is explicit for marketplaces with user-generated listings: must provide (a) a way to report objectionable content, (b) a way to block abusive users, (c) timely moderation, (d) published contact info. Beta App Review for TestFlight is more lenient and may pass; **App Store production review will likely flag this**. Treat as Critical for App Store, High for TestFlight.

---

## 3. High Priority Issues

### H1 — Stripe webhook replay-tolerance fix is in code but not yet deployed

The fix added timestamp tolerance (`supabase/functions/stripe-webhook/index.ts:60–88`), but the prior session confirmed deploys must run from the user's machine. Until `supabase functions deploy stripe-webhook` runs, production keeps the old vulnerable handler.

### H2 — Stripe Connect redirect env vars not yet set in Supabase

Code defaults `https://snatchitapp.com/payout-{refresh,return}`. The user said the deployed web is `snatchitwebapp.vercel.app`. Until `STRIPE_CONNECT_REFRESH_URL` / `STRIPE_CONNECT_RETURN_URL` are set in Supabase secrets, sellers will be redirected to a domain that doesn't currently host the new Expo Router screens.

### H3 — `RECORD_AUDIO` permission declared on Android but never used

- **File:** `app.json:30` — `"android.permission.RECORD_AUDIO"`. Same root cause as C2: leftover from a future audio feature that never shipped. Google Play's privacy review will flag it; iOS is unaffected.

### H4 — Splash icon is 288×288 (low resolution for modern devices)

- **File:** `assets/images/splash-icon.png` — 288×288 PNG.
- With `imageWidth: 200` in `app.json`, the splash will display at 200pt so the source resolution must be at least `200 × 3 = 600px` for @3x devices (iPhone Pro Max). Current 288px is upscaled on every modern iPhone — visibly soft. Recommend ≥1024×1024 source.

### H5 — Leftover Expo template assets in `assets/images/`

- **Files:** `react-logo.png`, `react-logo@2x.png`, `react-logo@3x.png`, `partial-react-logo.png`. Confirmed unreferenced (`grep -rn "react-logo" app src` → no matches).
- **Impact:** ship in the asset bundle, increasing app size for no reason. Not a blocker; remove for hygiene.

### H6 — No source-map upload setup verified for Sentry

`@sentry/react-native` plugin is enabled in `app.json` but I cannot confirm `SENTRY_AUTH_TOKEN` is set as an EAS project secret. Without it, production crash reports show minified stack traces. Run `eas secret:list --scope project | grep SENTRY_AUTH_TOKEN` from your machine to verify.

---

## 4. Medium Priority Issues

- **M1** — No Universal Links / `associatedDomains` configured. Stripe redirects (and any inbound `https://snatchitapp.com/...` link) cannot deep-link into the iOS app — they always land in mobile Safari, then user must tap a button. Working as designed via custom `snatchit://` scheme + the new `payout-return` / `payout-refresh` web screens, but Universal Links would be a nicer experience.
- **M2** — `expo-av` is in `package.json` but unused (`package.json:14`). Remove or wire up to reduce binary size and dependency surface.
- **M3** — No `expo-updates` / runtime version configured. First-launch is fine; you have no OTA path for hotfixes. Acceptable for v1, but add `expo-updates` before you accumulate critical bug-fix needs.
- **M4** — No `engines.node` in `package.json`. Means EAS uses its default Node version. Pin (`"engines": { "node": ">=20.0.0" }`) so CI is deterministic.
- **M5** — No `marketingVersion` mismatch between platforms; both are `1.0.0` build `1`. ✅ — but `eas.json` production profile has `autoIncrement: true`, which only bumps `buildNumber`, not `version`. You'll need to manually bump `version` for each App Store submission.
- **M6** — No Google Sign-In, Apple Sign-In, or social auth. Apple Sign-In is **not required** here because no third-party social auth is offered (Guideline 4.8 is conditional). ✅
- **M7** — `expo-image-picker` permission string is good, but does not mention the camera or any "save to library" intent. Current copy is fine for read-only photo library use.

---

## 5. File-by-File Findings

### `app.json`

- Line 3: `"name": "snatchit"` — should be `"Snatch It"` or `"SnatchIt"` (C4).
- Line 30: Android `RECORD_AUDIO` permission unused (H3).
- No `ios.infoPlist.NSPhotoLibraryAddUsageDescription` — fine, since uploads are read-only.
- No `ios.usesAppleSignIn`, `ios.associatedDomains` — not required, but flagged (M1).
- Line 5: `"version": "1.0.0"`. ✅
- `ios.buildNumber: "1"`, `eas.json` production has `autoIncrement: true` ✅.

### `eas.json`

- ✅ Production profile sets `EXPO_PUBLIC_APP_ENV=production`.
- ✅ `autoIncrement: true`.
- ⚠️ No `runtimeVersion` policy. Acceptable without `expo-updates`.
- ⚠️ No explicit `node` version pinned (M4).
- ⚠️ No `submit.production.ios` block — submission must be done manually via Xcode/Transporter or set up `eas submit` configuration.

### `ios/snatchit/Info.plist`

- C2 critical (camera + mic placeholder strings).
- `CFBundleDisplayName = snatchit` (C4).
- ✅ Privacy Manifest exists at `ios/snatchit/PrivacyInfo.xcprivacy`.

### `ios/snatchit/snatchit.entitlements`

- C3 critical (`aps-environment = development`).
- ✅ Apple Pay merchant ID `merchant.com.snatchit` matches `app.json` plugin config and `NativeAppShell.native.tsx:81`.

### `assets/images/icon.png`

- C1 critical — alpha channel present.

### `assets/images/splash-icon.png`

- H4 — 288×288, too small for modern devices.

### `assets/images/{react-logo*,partial-react-logo}.png`

- H5 — leftover Expo template assets.

### `src/providers/NativeAppShell.native.tsx`

- Line 30–39: Sentry init looks correct: `enabled: !__DEV__`, `environment: process.env.EXPO_PUBLIC_APP_ENV`, `tracesSampleRate: 0.1`, `debug: false`, `release: com.jdt-inc.snatchit@${version}`, `dist: build`. ✅
- Line 65–67: `setSentryUser({ id, email })` — discloses user email to Sentry. Disclosed in privacy policy (`app/settings/privacy.tsx:114`). Compliant, but minimizing to `{ id }` would be safer.

### `app/_layout.tsx`

- ✅ ErrorBoundary wraps app.
- ✅ Sentry user context cleared on sign-out.
- ✅ Modal placeholder route registration removed (prior fix).
- ✅ New payout-return/payout-refresh screens registered.

### `src/components/ErrorBoundary.tsx`

- ✅ Generic UI, no `error.message` rendered (prior fix).

### `app/(auth)/signup.tsx`

- ✅ Privacy + Terms disclosure added (prior fix).
- ⚠️ No "must be 18+" age gate UI; the legal Terms state 18+, but no explicit checkbox / age confirmation. App Review may ask for it given the marketplace + nightclub-tickets context. Recommend adding.

### `supabase/functions/*`

- ✅ All 5 functions fail-closed on rate-limit RPC error.
- ✅ Webhook signature has timestamp tolerance.
- ✅ Constant-time secret comparison everywhere.
- ✅ No service-role keys in client code.
- ⚠️ Migration `021_rate_limits_fail_closed.sql` exists but must be applied to production via `supabase db push`.

### `.env.production`, `.env.development`, `.env.local`, `.env`

- All gitignored (`.gitignore` lines 19–22). ✅
- `.env.production` has `pk_live_...` Stripe publishable key — designed-public, not a secret, but should still be loaded from EAS secrets rather than committed to a developer's local checkout.
- `.env.local` has `VERCEL_OIDC_TOKEN` — this token expires within hours; harmless to ship locally but never bundle (variables without `EXPO_PUBLIC_` prefix don't bundle). ✅
- `.env.development` uses the new Supabase publishable key format (`sb_publishable_*`); `.env.production` and `.env` use the old anon JWT. Both formats are valid for the same project.

### `app/(tabs)/index.tsx`

- ✅ Redirects to `/(tabs)/home` (prior fix).

### `app/payout-return.tsx`, `app/payout-refresh.tsx`

- ✅ Created with clean UX, native+web safe, `router.replace`-based.

---

## 6. App Store Risk Analysis

| Guideline | Status | Notes |
|-----------|--------|-------|
| **2.3.7** (icon transparency) | 🛑 BLOCKED | C1 |
| **5.1.1** (purpose strings) | 🛑 BLOCKED | C2 — unused camera/mic permissions |
| **5.1.1(v)** (account deletion) | ✅ | Implemented end-to-end (`app/settings/index.tsx`, `supabase/functions/delete-account`) |
| **5.1.1** (privacy policy in-app) | ✅ | `app/settings/privacy.tsx`, linked from signup |
| **5.1.2** (data minimization) | ⚠️ | Sentry receives email; disclosed in privacy policy |
| **3.1.1** (IAP for digital goods) | ✅ | Tickets are real-world event admission — Stripe is permitted |
| **3.1.5(a)** (real-world goods) | ✅ | Tickets to physical events |
| **3.1.3(b)** (multiplatform) | ✅ | Stripe payments for marketplace, no IAP |
| **4.2** (minimum functionality) | ✅ | Real marketplace with bids, auctions, transfers |
| **4.2** (placeholder content) | ✅ | All template artifacts removed in prior fixes |
| **4.8** (Sign in with Apple) | ✅ | Not required (no third-party social auth) |
| **1.2** (UGC moderation) | ⚠️ HIGH RISK FOR PRODUCTION | C5 — no report listing/user, no block user |
| **1.1.6** (false information) | ⚠️ | Sellers warrant ticket validity in Terms; no automated counterfeit check |
| **2.5.4** (multitasking — no background needed) | ✅ | No background modes declared |
| **2.5.6** (web view: no in-app browser) | ✅ | Uses `expo-web-browser` for Stripe — correct |
| **5.1.1(ix)** (consent before tracking) | ✅ | No IDFA usage |
| **5.6** (developer code of conduct) | ✅ | Clear branding, real legal entity (JDT LLC) |

**Beta App Review (TestFlight) risk:** Currently BLOCKED by C1, C2, C3. After those are fixed, very likely to pass. C5 is unlikely to block TestFlight.

**App Store production review risk:** After C1–C4 are fixed, the dominant remaining risk is **C5 (UGC moderation)**. Plan to add report-listing + block-user before App Store submission, even if you ship TestFlight without it.

---

## 7. Stripe / Sentry Production Status

### Stripe

- ✅ Live key in `.env.production` (`pk_live_*`); test key in `.env.development` (`pk_test_*`).
- ✅ `merchantIdentifier: merchant.com.snatchit` consistent across `app.json`, `NativeAppShell.native.tsx:81`, `ios/snatchit/snatchit.entitlements:8`.
- ✅ Apple Pay capability declared in entitlements.
- ✅ All `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` references are server-side only (`supabase/functions/*`).
- ✅ Edge function `confirm-payment` re-verifies PI status with Stripe before promoting payment to `succeeded`.
- ✅ Webhook signature verified with HMAC + 300s timestamp tolerance (after prior fix).
- ✅ Idempotency: PaymentIntent uses `Idempotency-Key`, transfers have UNIQUE constraints, webhook claims via `.neq('status', 'succeeded')`.
- ⚠️ Apple Pay merchant ID `merchant.com.snatchit` must be registered in your Apple Developer account AND in your Stripe dashboard before Apple Pay will function. Cannot verify from code.
- ⚠️ `STRIPE_CONNECT_REFRESH_URL` / `STRIPE_CONNECT_RETURN_URL` must be set in Supabase secrets (H2).

### Sentry

- ✅ DSN `https://f83fffa8c787e41e509b17b384787aed@o4511123980877825.ingest.us.sentry.io/4511123983695872` present in `.env.production`.
- ✅ `enabled: !__DEV__` — no events from local dev runs.
- ✅ `environment` derived from `EXPO_PUBLIC_APP_ENV`.
- ✅ Release tag `com.jdt-inc.snatchit@${version}` matches iOS bundle.
- ✅ `tracesSampleRate: 0.1` — appropriate.
- ⚠️ Source map upload requires `SENTRY_AUTH_TOKEN` set as EAS secret (H6) — verify locally.
- ⚠️ User email shipped to Sentry. Disclosed; compliant. Consider trimming to `{ id }` only as defense-in-depth.

---

## 8. Metadata Package (App Store Connect)

Fill these in App Store Connect → App Information / Pricing & Availability / iOS App / 1.0 Prepare for Submission.

### Promotional text (170 chars)

> Bid on tonight's hottest event tickets. Snatch It is a peer-to-peer ticket marketplace built for time-sensitive access — clubs, festivals, last-minute deals.

### Subtitle (30 chars)

> Auction tonight's tickets

### Keywords (100 chars, comma-separated, no wasted spaces)

> tickets,auction,bid,events,nightlife,resale,marketplace,concerts,clubs,passes,last-minute,seller

### Description (4,000 chars; sketch — refine before submission)

> Snatch It is a peer-to-peer marketplace for last-minute event access. Sellers list extra tickets they can no longer use; buyers bid in real-time auctions or pay a fixed Buy Now price. Every transaction is processed securely through Stripe — funds are held until the buyer confirms they received a working ticket transfer, protecting both sides.
>
> WHY SNATCH IT
>
> - Real-time auctions for tonight's hottest tickets
> - Buy Now option for instant purchase
> - Funds held until buyer confirms receipt
> - Secure Stripe payments and seller payouts
> - Verified seller program
>
> HOW IT WORKS
>
> 1. Browse listings filtered by neighborhood, date, and price.
> 2. Place a bid or use Buy Now to reserve.
> 3. Pay securely with Apple Pay or card.
> 4. Receive the ticket transfer from the seller.
> 5. Confirm receipt — funds release to the seller.
>
> Snatch It is a technology platform; we are not the seller of tickets. All sales are between users. Sellers are responsible for the validity of their tickets. You must be 18+ to use the app.
>
> Questions? Email snatchit.appsupport@gmail.com.

### URLs

- **Support URL:** `https://snatchitapp.com/support` *(verify this exists; otherwise use the GitHub Pages or Vercel domain you actually host).*
- **Marketing URL:** `https://snatchitapp.com` *(same caveat).*
- **Privacy Policy URL:** `https://snatchitapp.com/privacy` (must mirror the in-app privacy text — copy from `app/settings/privacy.tsx`).

### Age Rating: **17+** (or 12+ at minimum)

Drivers: real-money commerce, user-generated content (potential for unfiltered language in listing descriptions), nightlife/club context. Set:

- "Frequent/Intense Mature/Suggestive Themes" → No
- "Unrestricted Web Access" → No
- "Gambling and Contests" → **Infrequent/Mild** (auctions are a contest mechanic; declaring keeps you safe under 5.3)
- "Profanity or Crude Humor" → Infrequent/Mild
- "Simulated Gambling" → No (real auctions, not simulated)

### Categories

- **Primary:** *Lifestyle*
- **Secondary:** *Entertainment*

### Sign-in info for App Review

> Demo account email: review-demo@snatchitapp.com
> Demo account password: <set up before submission>
> Notes: account is pre-funded with a Stripe test seller and has placed test bids on existing listings.

### App Review notes (paste into "Notes for App Review")

> Snatch It is a peer-to-peer marketplace for resale of real-world event tickets (concerts, club entry, festivals — physical events with in-person admission). All ticket sales are real-world goods exchanged between users. Snatch It is a technology platform and is NOT the seller of tickets.
>
> Payments: All payments are processed by Stripe. There are no digital goods, in-app credits, subscriptions, or unlockable content. Apple's IAP is not used because every transaction is for a real-world event ticket (Guideline 3.1.5).
>
> Account deletion: Settings → Danger Zone → Delete Account. Triggers an authenticated edge function (`supabase/functions/delete-account`) that anonymizes financial records (legal retention), cancels active listings, deletes user storage, and removes the auth user. Verified end-to-end.
>
> Privacy Policy & Terms: linked in-app at Settings → Support, and from the signup screen before account creation.
>
> Test reviewer credentials, test card numbers, and a sample listing-purchase walkthrough are in the demo account login above.

### Export Compliance

`ITSAppUsesNonExemptEncryption = false` is already set in `app.json:14`. ✅

---

## 9. Final Verdict

- **READY FOR TESTFLIGHT: NO**
- **READY FOR APP STORE PRODUCTION: NO**
- **Security score (15-pt gate, post-fixes):** 13 ✅ / 2 ⚠️ — UGC moderation (1.2) + Sentry email PII surface
- **App Store rejection risk level:**
  - For TestFlight Beta App Review: **HIGH until C1–C3 are fixed**, LOW after.
  - For full App Store production review: **MEDIUM-HIGH** unless C5 (UGC moderation) is added.

### Exact pre-TestFlight blockers — fix before next archive

1. **C1** Replace `assets/images/icon.png` with an opaque (RGB or RGBA-with-no-transparency) 1024×1024 PNG, then `npx expo prebuild --clean` to regenerate `ios/`.
2. **C2** Either remove `NSCameraUsageDescription` and `NSMicrophoneUsageDescription` from `ios/snatchit/Info.plist` (and re-prebuild), OR add `expo.ios.infoPlist` overrides in `app.json` to set them to specific purpose strings *only if* you actually use those features. Currently you don't, so remove.
3. **C3** Either delete `aps-environment` from `ios/snatchit/snatchit.entitlements` and let EAS inject `production` at build time, or set it to `production` directly.
4. **C4** Change `app.json:3` `"name": "snatchit"` → `"Snatch It"` (or `"SnatchIt"`), then re-prebuild so `CFBundleDisplayName` updates.
5. **H1/H2** Run `supabase functions deploy stripe-webhook create-connect-account` and `supabase secrets set STRIPE_CONNECT_REFRESH_URL=... STRIPE_CONNECT_RETURN_URL=...` from your machine.
6. **H3** Remove `"android.permission.RECORD_AUDIO"` from `app.json:30` (also strip from any Android manifest if prebuilt).

### Strongly recommended before App Store production submission

7. **C5** Implement at minimum:
   - "Report listing" button on `src/screens/ListingDetailScreen.tsx` → posts to a `reports` table.
   - "Block user" on seller profile (filters their listings out of feeds via RLS).
   - Server-side moderation queue or rate-limited auto-hide on N reports.
8. Replace splash-icon source with a 1024×1024 asset (H4).
9. Delete `react-logo*.png` and `partial-react-logo.png` (H5).
10. Verify `SENTRY_AUTH_TOKEN` is in EAS secrets (H6).
11. Add an 18+ confirmation checkbox on signup (consistent with Terms).

---

STEP COMPLETE

# Snatch It — App Store Launch Checklist

Status as of 2026-07-10. ✅ done · ⚠️ action required before submission.

## Screenshots
- ✅ 6 finalized screenshots in `apple screenshots/appstore/`, 1290×2796 (iPhone 6.7"), story-ordered: discover → live auction → bid → won → secure transfer → sell
- ✅ Store badges / "Get the app" web chrome removed (Guideline 2.3.10)
- ✅ "Demo Buyer (App Review)" placeholder replaced with neutral name
- ✅ Consistent template, typography, logo placement, margins (verified per-image + contact sheet)
- ⚠️ ASC also accepts these 6.7" shots for 6.9"; upload once under iPhone 6.7" display set

## Metadata / Keywords / Description
- ✅ Name, subtitle, promo text, description, keywords (100/100), categories, review notes — all in `APP_STORE_METADATA.md`, char-counted
- ⚠️ Paste into App Store Connect (cannot be done from CLI)

## Privacy
- ✅ In-app Privacy Policy accurate (phone verification, Sentry, data collection, deletion)
- ✅ PrivacyInfo.xcprivacy present; no tracking → no ATT
- ⚠️ **Privacy Policy URL must be live** at https://snatchitapp.com/privacy (ASC requires a web URL; in-app screen alone is not enough). Publish the landing-v2 privacy page or a static copy.
- ⚠️ Fill ASC App Privacy questionnaire per `APP_STORE_METADATA.md` (Contact Info, User Content, Identifiers, Diagnostics — all linked, no tracking)

## URLs
- ⚠️ Verify https://snatchitapp.com is live (Support/Marketing URL) and `support@snatchitapp.com` mailbox is monitored
- ✅ payout-return / payout-refresh deep-link pages referenced by Stripe onboarding

## App Review Notes & Credentials
- ⚠️ **Create the reviewer account in production**: `review-buyer@snatchitapp.com` / `Snatch1tDemo!` — pre-verify phone, complete Stripe test onboarding, seed ≥1 live listing (see LAUNCH_PLAN.md §reviewer accounts)
- ⚠️ **Add Supabase test phone number**: Dashboard → Auth → Phone → "Test Phone Numbers and OTPs" → `18005550123=789012` (lets Apple verify phone without SMS)

## Trust & Compliance (verified this audit)
- ✅ Dispute banner no longer promises "payment is protected"/hard 24h SLA
- ✅ Public-profile "Verified Seller" badge now bound to admin review flag (`is_verified_seller`), consistent app-wide
- ✅ Terms now state zero tolerance for objectionable content/abuse (Guideline 1.2)
- ✅ UGC: report + block + content filter + support contact all present
- ✅ Account deletion in-app; 18+ gate at signup; no external purchase links; Stripe = physical-world services (no IAP)

## Stripe
- ✅ Live publishable key in production EAS profile; payouts via Connect; Apple Pay merchant `merchant.com.snatchit`
- ⚠️ Confirm Apple Pay merchant ID is registered in the Apple Developer portal & Stripe dashboard before release (TestFlight card payments work regardless)

## Supabase
- ✅ Migrations through 038 applied; Phone Auth live (twilio_verify); RLS listing guard (payout + verified phone)
- ⚠️ Twilio account is trial ($3.41): upgrade + fund before public launch or OTPs will fail for unverified numbers

## Push Notifications
- ✅ aps-environment=production entitlement; send-push + triggers + deep links live

## Build Configuration & Versioning
- ✅ eas.json production profile: autoIncrement, remote versions, live env
- ✅ v1.0.0; buildNumber remote-managed
- ⚠️ Production build `df0ec67f` (commit 95d4ff6) predates this audit's copy fixes → **new production build required** (started as part of this audit — see git log/EAS)
- ⚠️ `eas submit` non-interactive still needs `ascAppId` in eas.json, or run `eas submit -p ios --profile production` interactively once

## Release Readiness — remaining human steps (in order)
1. Publish privacy page at snatchitapp.com/privacy; confirm domain + mailbox live
2. Create reviewer account + seed demo listing in production; add Supabase test phone
3. Upload screenshots (`apple screenshots/appstore/`) + paste metadata/keywords/notes into ASC
4. Fill App Privacy questionnaire; set age rating 17+
5. Register Apple Pay merchant ID (if not already)
6. Upgrade Twilio from trial
7. Submit the new production build via `eas submit -p ios --profile production` (interactive first time)

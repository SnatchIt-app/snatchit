# Day 7 — Private Beta Launch Checklist

**Version:** 1.0
**Date:** 2026-04-02
**Scope:** SnatchIt private beta — iOS TestFlight + Android internal track
**Prerequisite:** Days 1–6 complete and passing

---

## 1. App Readiness

| # | Item | How to Verify | Status |
|---|------|---------------|--------|
| 1.1 | Latest build uploaded to TestFlight (iOS) | App Store Connect → TestFlight → Builds → confirm build number matches `app.json` `buildNumber` | ☐ |
| 1.2 | Latest build uploaded to Google Play internal track (Android) | Play Console → Internal testing → confirm `versionCode` matches | ☐ |
| 1.3 | Deep links working (`snatchit://` scheme) | Open a deep link on a test device → confirm app opens to correct screen | ☐ |
| 1.4 | Splash screen renders correctly on both platforms | Cold-start app on iOS and Android device | ☐ |
| 1.5 | All auth flows working (sign up, sign in, password reset) | Walk through each flow on a fresh account | ☐ |
| 1.6 | Listing creation flow completes without errors | Create a test listing with image, event details, price | ☐ |
| 1.7 | Buy Now flow completes (end-to-end happy path) | Run Test 1 from DAY6_E2E_TEST_PLAN.md | ☐ |
| 1.8 | Dispute flow works from buyer side | Tap "Dispute" on an active transfer → confirm `disputed` status in DB | ☐ |
| 1.9 | Sentry error tracking active | Trigger a test error → confirm it appears in Sentry dashboard (org: `jdt-inc`, project: `snatchit`) | ☐ |
| 1.10 | App version string visible in Settings screen | Open Settings → confirm version shows `1.0.0` | ☐ |

---

## 2. Stripe Readiness

| # | Item | How to Verify | Status |
|---|------|---------------|--------|
| 2.1 | Stripe account is in **live mode** (not test) | Stripe Dashboard → confirm banner says "Live" not "Test" | ☐ |
| 2.2 | Webhook endpoint registered for live mode | Stripe → Developers → Webhooks → confirm endpoint URL matches production Supabase edge function URL | ☐ |
| 2.3 | Webhook is listening for `payment_intent.succeeded` | Stripe → Webhook details → Events → confirm event type listed | ☐ |
| 2.4 | Stripe Connect enabled and at least one seller onboarded | Stripe → Connect → Accounts → at least 1 connected account with `charges_enabled: true` | ☐ |
| 2.5 | Platform fee percentage configured correctly | Check `confirm-and-release` edge function → confirm service fee calc matches `payments.service_fee` | ☐ |
| 2.6 | Stripe publishable key in app env matches live key | Compare `EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY` to Stripe Dashboard → API keys | ☐ |
| 2.7 | Stripe secret key in Supabase secrets matches live key | Supabase → Edge Functions → Secrets → `STRIPE_SECRET_KEY` is live `sk_live_*` | ☐ |
| 2.8 | Apple Pay / Google Pay merchant ID configured | Confirm `merchant.com.snatchit` in Apple Developer portal and `enableGooglePay: true` in `app.json` | ☐ |

---

## 3. Supabase Readiness

| # | Item | How to Verify | Status |
|---|------|---------------|--------|
| 3.1 | Production project is active (not paused) | Supabase Dashboard → project status = "Active" | ☐ |
| 3.2 | RLS policies enabled on all critical tables | Run: `SELECT tablename FROM pg_tables WHERE schemaname='public';` then verify RLS on `listings`, `payments`, `transfers`, `profiles` | ☐ |
| 3.3 | `buyer_dispute_transfer()` RPC function deployed | Run: `SELECT proname FROM pg_proc WHERE proname = 'buyer_dispute_transfer';` | ☐ |
| 3.4 | All required columns exist on `transfers` table | Verify: `status`, `expires_at`, `auto_release_at`, `seller_sent_at`, `buyer_confirmed_at`, `payout_released_at`, `disputed_at`, `stripe_transfer_id` | ☐ |
| 3.5 | Database backups enabled (daily point-in-time) | Supabase → Settings → Database → Backups → confirm PITR enabled | ☐ |
| 3.6 | Connection pool not maxed | Supabase → Settings → Database → confirm connection limit has headroom for beta scale (~20 concurrent users) | ☐ |

---

## 4. Cron / Edge Function Readiness

| # | Item | How to Verify | Status |
|---|------|---------------|--------|
| 4.1 | `enforce-transfer-expiry` cron active | Supabase → Edge Functions → Cron → confirm schedule (every 5 min) and last successful run | ☐ |
| 4.2 | `auto-release-funds` cron active | Supabase → Edge Functions → Cron → confirm schedule and last successful run | ☐ |
| 4.3 | `confirm-and-release` edge function deployed | Supabase → Edge Functions → confirm function listed and endpoint reachable | ☐ |
| 4.4 | `stripe-webhook` edge function deployed | Supabase → Edge Functions → confirm function listed; test with Stripe CLI `stripe trigger payment_intent.succeeded` | ☐ |
| 4.5 | `confirm-payment` edge function deployed | Supabase → Edge Functions → confirm function listed | ☐ |
| 4.6 | All edge function secrets set | Verify `STRIPE_SECRET_KEY`, `SUPABASE_SERVICE_ROLE_KEY` are set in Edge Function secrets | ☐ |
| 4.7 | Cron jobs ran successfully in last 24h | Check Supabase logs for cron execution — no errors | ☐ |

---

## 5. Push Notification Readiness

| # | Item | How to Verify | Status |
|---|------|---------------|--------|
| 5.1 | Expo push notification credentials configured for iOS | EAS → Credentials → iOS push key or certificate present | ☐ |
| 5.2 | Expo push notification credentials configured for Android | Firebase Cloud Messaging server key set in EAS | ☐ |
| 5.3 | `expo-notifications` plugin in `app.json` | Confirm `expo-notifications` present with icon and color config | ☐ |
| 5.4 | Push token registration working | Sign in on test device → verify `profiles.expo_push_token` is populated in DB | ☐ |
| 5.5 | Test notification received on iOS | Send test push via Expo push tool → confirm delivery | ☐ |
| 5.6 | Test notification received on Android | Send test push via Expo push tool → confirm delivery | ☐ |
| 5.7 | Foreground notification display enabled | Verify `iosDisplayInForeground: true` in `app.json` → confirm in-app banner appears | ☐ |

---

## 6. Support Readiness

| # | Item | How to Verify | Status |
|---|------|---------------|--------|
| 6.1 | Admin has access to Supabase SQL Editor | Log in → run a `SELECT 1;` query | ☐ |
| 6.2 | Admin has access to Stripe Dashboard (live) | Log in → confirm can view Payments and Connect tabs | ☐ |
| 6.3 | DAY5_ADMIN_DISPUTE_SOP.md printed / bookmarked | Confirm admin can access this doc within 30 seconds | ☐ |
| 6.4 | DAY5_MANUAL_REFUND_PLAYBOOK.md printed / bookmarked | Confirm admin can access this doc within 30 seconds | ☐ |
| 6.5 | DAY5_ADMIN_SQL_PACK.sql loaded in a Supabase saved query | Open Supabase SQL Editor → confirm saved queries available | ☐ |
| 6.6 | Support email or contact method communicated to testers | Confirm testers know how to reach admin (email, iMessage, Discord, etc.) | ☐ |
| 6.7 | Sentry alerts configured to notify admin | Sentry → Alerts → confirm at least one alert rule sends to admin email or Slack | ☐ |

---

## 7. Tester Onboarding Readiness

| # | Item | How to Verify | Status |
|---|------|---------------|--------|
| 7.1 | TestFlight invite links generated | App Store Connect → TestFlight → Public Link or individual invites ready | ☐ |
| 7.2 | Android internal track invite links generated | Play Console → Internal testing → invite link copied | ☐ |
| 7.3 | At least 2 test seller accounts with Stripe Connect onboarded | Supabase: `SELECT id, stripe_connect_id FROM profiles WHERE stripe_connect_id IS NOT NULL;` returns ≥ 2 rows | ☐ |
| 7.4 | At least 3 test buyer accounts created | Supabase: `SELECT count(*) FROM profiles;` returns ≥ 5 (sellers + buyers) | ☐ |
| 7.5 | DAY7_TESTER_ONBOARDING.md sent to all testers | Confirm delivery via chosen channel | ☐ |
| 7.6 | Bug reporting channel set up (GitHub Issues, Discord, or shared doc) | Confirm testers have access and know the URL | ☐ |
| 7.7 | DAY6_BUG_LOG_TEMPLATE.md shared with testers | Confirm testers can access it | ☐ |

---

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Lead Developer | | | |
| Admin / Ops | | | |

---

*When every box is checked, you are cleared for private beta launch.*

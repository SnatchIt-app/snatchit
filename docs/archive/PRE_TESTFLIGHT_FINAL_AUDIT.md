# Pre-TestFlight Final Audit

**Date:** 2026-06-09 · **App:** Snatch It (com.jdt-inc.snatchit, Expo RN + Supabase `hqycwntpfoztoinemqns` + Stripe Connect) · **Method:** full code trace (routes, RPCs, edge functions, migrations), live database inspection (functions, grants, RLS, cron history, advisors), and production config review. Nothing assumed; every finding carries evidence.

## Executive Verdict

**NO-GO for TestFlight in current state.** The app is feature-complete and App Store compliance surfaces (report/block/age-gate/account-deletion/legal) are genuinely solid — but the audit found **one live money-loss bug** (expired transfers not refunding buyers — two real buyers currently paid with no tickets and no refund) and **two anon-callable privileged RPCs with no auth guard**. All three are fixable in hours. Fix C1–C3, re-verify, then ship.

## Critical Issues

**C1 — Expired-transfer refunds are broken in production; 2 buyers currently unrefunded.** The refund path is the `enforce-transfer-expiry` edge function (expires via RPC, then issues Stripe refunds). Live cron history (24h): the HTTP cron job `enforce-transfer-expiry` **failed 720/720 runs** (the `net.http_post` reads `current_setting('app.settings.supabase_url')` / `app.settings.service_role_key` GUCs, which are not set), while a duplicate SQL-only job `enforce-transfer-expiry-job` (`SELECT public.enforce_transfer_expiry()`) **succeeds every 2 minutes and consumes the expiry transitions without ever calling Stripe**. Result: transfers flip to `expired` but the refund step never runs. **Live impact verified:** transfers `d69e3064…` (expired 2026-04-18) and `15e6651c…` (expired 2026-05-19) have `payments.status='succeeded'`, `refunded_at IS NULL`. Earlier expiries (March) were refunded — the regression began when the shadow SQL job was added. Fix: set the two GUCs (or schedule via hardcoded URL/secret), remove `enforce-transfer-expiry-job`, and manually refund the two stranded payments in Stripe.

**C2 — `admin_resolve_dispute` is SECURITY DEFINER, EXECUTE granted to PUBLIC/anon, with NO internal auth check.** Verified live: `proacl = {=X/postgres, anon=X, authenticated=X, …}`, `prosrc` contains no `auth.uid()` guard, and the function accepts `p_admin_id` as a caller-supplied parameter (migration 011:326–355). Anyone holding the public anon key can resolve any dispute in either direction and forge the admin attribution — directly corrupting refund decisions and the trust system. Fix: `REVOKE EXECUTE … FROM PUBLIC, anon, authenticated;` grant to `service_role` only (it's invoked from the SQL editor/ops tooling, not the app).

**C3 — `delete_account_cleanup` is SECURITY DEFINER, anon-executable, with NO internal auth check.** Verified live: same open `proacl`, no `auth.uid()` in body. It cancels a target user's active listings and anonymizes their listings/payments/transfers to the sentinel UUID (migration 020:16–74). The legitimate caller is the `delete-account` edge function using service role — but the open grant lets any anon-key holder run it against **any user id**, destructively cancelling another seller's live listings. Fix: revoke from PUBLIC/anon/authenticated; grant `service_role` only.

## High Priority Issues

**H1 — Auction winner has no payment deadline.** Winner selection works (`auto_finalize_expired_auctions`, cron-verified healthy 720/720), but there is no time-limited payment window and no reclaim path: a winner who never pays leaves the listing stuck and the seller with no recourse. Needs a pay-by deadline + auto-relist/runner-up policy before real auction volume.

**H2 — Buy Now on an auction with active bids.** Buy-now reservation is permitted while bids exist; existing bidders are not notified/handled at purchase time and a cancelled-with-bids auction relies on the 24h transfer-expiry path for refunds (now also implicated in C1). Define and enforce the interaction (disable buy-now after first bid, or immediately void bids on buy-now).

**H3 — Open EXECUTE grants on 27 SECURITY DEFINER functions (56 of 71 Supabase security-advisor findings).** Most have internal `auth.uid()` guards (verified: `buyer_dispute_transfer`, `cancel_listing`, `complete_auction_payment`, `confirm_transfer_received`, `ensure_transfer_exists`, `mark_listing_sold`, `mark_transfer_sent`×2, `reserve_buy_now` all check auth) — but the pattern that produced C2/C3 will recur. Sweep all 27: default-deny (`REVOKE FROM PUBLIC, anon`), grant `authenticated` only where the function self-guards, `service_role` only for ops/cron functions (`refresh_all_seller_risk_scores`, `enforce_*`, `auto_finalize_*` — currently anon-invokable compute, a free DoS lever).

## Medium Priority Issues

- **M1 — Notification preferences not enforced server-side.** `notification_preferences` toggles exist in UI, but `stripe-webhook` sends pushes unconditionally and no triggers honor `notify_outbid` etc. (outbid pushes go through `notify_outbid` trigger — preference check not found).
- **M2 — Notification tap routing handles only `auction_won`.** `payment_succeeded` / `ticket_sold` taps route nowhere (NativeAppShell.native.tsx:175); cold- and warm-start listeners are otherwise correctly implemented (`getLastNotificationResponseAsync` + response listener).
- **M3 — Push tokens stay `is_active` after logout** — next user on a shared device context can receive prior user's pushes (settings/index.tsx:112–133; cleanup only on account deletion via CASCADE).
- **M4 — Listing content moderation is a loose word-boundary banned-words regex only**; no semantic/image moderation. Acceptable for TestFlight given report/block exist, thin for public launch (UGC 1.2).
- **M5 — Dispute-lost after payout has no automated Stripe transfer reversal** — manual ops per design (stripe-webhook:564–566); document the runbook.
- **M6 — Auth hardening:** leaked-password protection (HaveIBeenPwned) disabled in Supabase Auth (advisor WARN); no display_name required before marketplace activity; deep-link recovery parsing is fragile (NativeAppShell.native.tsx:142).
- **M7 — 6 functions with mutable `search_path`** (advisor WARN): `set_updated_at`, `handle_new_user`, `guard_listing_*`, `notify_outbid`, `disputes_set_updated_at` — pin `SET search_path = public`.
- **M8 — Trust metrics (carried from profile audit):** seller-vindicated disputes still excluded from success rate; open post-payout chargeback counts as success until closed.

## Low Priority Issues

Duplicate auction-finalize cron jobs (`auto-finalize-auctions` + `finalize-auctions`, both 720/720 healthy — redundant, SKIP LOCKED prevents double-processing; remove one). Display rounding shows 199/200 as "100%". Payment-cancel is silent (no user-facing message). No in-app notification history. Public storage buckets allow listing (avatars/auction-media — public by design). `disputes.status` has no CHECK constraint. Ghost "Deleted User" profiles publicly visible (by design, no PII). Settings route cast workaround (settings/index.tsx:105–109). Login rate limiting relies on Supabase Auth defaults (adequate for TestFlight).

## App Store Risks

**Overall: LOW once C-issues are fixed — compliance surfaces are complete.** Verified present: **1.2 UGC** — Report Listing (listing-detail overflow → `/report/listing/[id]`), Report User (profile), Block User + blocked-content filtering (feed + realtime via `useBlockedUserIds`), Blocked Users management screen with unblock (settings), reports/user_blocks tables with owner-only RLS (migration 023). **1.4/Age** — mandatory 18+ checkbox at signup (signup.tsx:108–117). **2.1 Completeness** — C1/H1 are the functional-completeness risks: a reviewer abandoning a transfer or winning an auction without paying hits a dead end. **3.1 Payments** — physical-goods/ticket marketplace correctly uses Stripe, not IAP; exempt from 3.1.1. **5.1 Privacy** — in-app Privacy Policy + Terms (settings/privacy.tsx, legal.tsx, effective 2026-03-20), account deletion with double confirmation calling `delete-account` edge function (5.1.1(v) ✓), support (`support@snatchitapp.com`) and legal (`legal@snatchitapp.com`) contacts present. Push permission requested post-auth in context, `aps-environment: production`, `POST_NOTIFICATIONS` declared, photo-library usage string present; **camera/mic usage strings intentionally nulled — confirm no `launchCameraAsync` path before submission** (only library picker found). `ITSAppUsesNonExemptEncryption=false` set (smooth TestFlight). **2.3 Metadata** — App Store Connect listing (screenshots, description, support URL, privacy nutrition labels) not in repo; complete at submission. **5.2 IP** — user-listed event tickets; report reason `counterfeit_or_invalid` exists; standard marketplace posture.

## Database Risks

Migrations: repo and live are consistent — 31 files ↔ 31 applied, latest `031`; no orphaned repo migrations. Live-only ad-hoc objects exist (e.g. `cleanup_expired_reservations`, the `enforce-transfer-expiry-job` cron) — drift between repo and prod DDL is itself a risk; snapshot prod schema. RLS enabled on all public tables; 6 tables RLS-on-no-policy are service-role-only by design (`disputes`, `rate_limits`, `stripe_webhook_events`, `webhook_retries`, `seller_flags`, `seller_risk_scores`) — correct posture. Stale buy-now reservations ARE cleaned (verified: `auto_finalize_expired_auctions` calls `cleanup_expired_reservations`, cron every 2 min, 0 stuck reserved listings live). Double-payment guards verified: unique partial index on succeeded payments per listing + unique `transfers.payment_id`. Key risks: the C2/C3/H3 grant sweep, M7 search_path pins, and the duplicate cron jobs (C1, L1).

## Stripe Risks

Webhook signature verified, `verify_jwt=false` correct for `stripe-webhook`; event dedup via `stripe_webhook_events` unique event_id + status claim-updates + DB constraints = three idempotency layers (verified in code). `confirm-and-release` payout has atomic `WHERE payout_released_at IS NULL` guard — double-payout protected; orphaned-transfer-on-partial-failure is logged for manual reconciliation (accepted). Chargebacks: dispute.created freezes pre-payout transfers and upserts `disputes`; dispute.closed syncs status and marks payment refunded on loss; post-payout reversal is manual (M5). Saved cards via hoisted customer + ephemeral keys (P1-03) working. Connect onboarding + payout-refresh/return flows present; `stripe_onboarding_complete` gated. Production publishable key is `pk_live_…` in eas.json production profile ✓. **The dominant Stripe risk is C1 (refunds not executing) — money is currently being retained from buyers in violation of the marketplace's own 24h promise.**

## Security Risks

C2 + C3 (anon-callable privileged DEFINER functions) are the headline. H3 grant sweep. Anon key + URL in eas.json is normal (public by design); no service-role key or secret found in the repo client code; `.env.production` correctly warns against committing live secrets (publishable key only). Edge functions enforce JWT (except webhook, correctly), rate limits are fail-closed on sensitive endpoints (`delete-account` 3/300s, `confirm-and-release` 5/300s). Storage buckets public-read (avatars/media — acceptable). Leaked-password protection off (M6). Sentry wired with user context set/cleared on login/logout.

## Production Readiness Score

**6.5 / 10.** Architecture, idempotency, compliance surfaces, and state machines are above average for a pre-TestFlight marketplace. Score is capped by one live money-loss defect (C1), two privilege-escalation grants (C2/C3), and the unfinished auction-winner payment loop (H1). Fixing C1–C3 alone lifts this to ~8.5; H1/H2 take it to launch-grade.

## Final TestFlight Recommendation

**HOLD.** Do not distribute the current build. All blockers are backend/ops-side (cron config, SQL grants, two manual refunds) — **no app binary changes are strictly required**, so a same-day fix-and-ship is realistic: remediate C1–C3, re-run the verification queries below, then proceed to TestFlight with H1/H2 flagged as known limitations for internal testers.

## Required Fixes Before TestFlight

1. **C1a:** Refund the two stranded payments (transfers `d69e3064…`, `15e6651c…`) in Stripe and mark `payments.refunded_at`.
2. **C1b:** Repair the refund cron: set `app.settings.supabase_url` + `app.settings.service_role_key` GUCs (or reschedule with literal values via Vault), confirm `enforce-transfer-expiry` HTTP job succeeds, and `cron.unschedule('enforce-transfer-expiry-job')` (the refund-less shadow job).
3. **C2:** `REVOKE EXECUTE ON FUNCTION public.admin_resolve_dispute(uuid,text,uuid) FROM PUBLIC, anon, authenticated;`
4. **C3:** `REVOKE EXECUTE ON FUNCTION public.delete_account_cleanup(uuid) FROM PUBLIC, anon, authenticated;` (service_role retains access for the edge function).
5. Re-run verification: cron 24h success rates; `SELECT … FROM transfers t JOIN payments p … WHERE t.status='expired' AND p.refunded_at IS NULL` must return 0 rows; `has_function_privilege('anon', 'public.admin_resolve_dispute(uuid,text,uuid)', 'EXECUTE')` and the same for `delete_account_cleanup(uuid)` must return false.

## Recommended Fixes After TestFlight

H1 winner-payment deadline + reclaim; H2 buy-now/auction bid policy; H3 full DEFINER grant sweep + M7 search_path pins; M1 preference-aware push sends; M2 routing for all push types; M3 deactivate push tokens on logout; M4 stronger content moderation before public launch; M5 documented chargeback-reversal runbook; M6 enable leaked-password protection + require display name; M8 trust-metric design decisions; remove duplicate `finalize-auctions` cron; commit prod-only DDL (cleanup function, cron) into a migration to eliminate schema drift.

## Final QA Checklist

| # | Area | Check | Result |
|---|---|---|---|
| 1 | Compliance | Report User / Report Listing / Block / Unblock / blocked-feed filtering | ✅ Pass |
| 2 | Compliance | 18+ gate, Terms+Privacy in signup & settings, support/legal contacts | ✅ Pass |
| 3 | Compliance | In-app account deletion (5.1.1(v)) w/ active-transfer guard + anonymization | ✅ Pass |
| 4 | Auth | Signup/login/logout/reset/session-persistence/stale-token recovery | ✅ Pass |
| 5 | Buyer | Browse→detail→reserve→pay→transfer→confirm/auto-release state machine | ✅ Pass |
| 6 | Buyer | Payment idempotency (dedup + claim + unique constraints), no double-charge | ✅ Pass |
| 7 | Buyer | **Expired transfer → buyer refund** | ❌ **FAIL (C1 — 2 live unrefunded)** |
| 8 | Seller | Create/edit/cancel listing guards, Connect onboarding, payout release | ✅ Pass |
| 9 | Auctions | Bid validation, finalize cron (720/720), reservation cleanup | ✅ Pass |
| 10 | Auctions | Winner payment deadline / reclaim | ⚠️ Gap (H1) |
| 11 | Disputes | Freeze, admin resolution, Stripe sync, trust-metric integration (031 live) | ✅ Pass |
| 12 | DB | **Privileged RPC grants (admin_resolve_dispute, delete_account_cleanup)** | ❌ **FAIL (C2/C3)** |
| 13 | DB | Migrations repo↔live consistent (31/31, latest 031); RLS on all tables | ✅ Pass |
| 14 | Stripe | Webhook signature, idempotency, live publishable key in prod profile | ✅ Pass |
| 15 | Notifications | Token registration, contextual permission, send path | ✅ Pass (routing gaps M2) |
| 16 | iOS config | Icon, splash, scheme, entitlements, encryption flag, permission strings | ✅ Pass (verify no camera path) |
| 17 | Environment | eas.json profiles, Supabase URL/keys, Sentry DSN, autoIncrement | ✅ Pass |

**Verdict: HOLD — fix C1, C2, C3, re-verify items 7 and 12, then GO.**

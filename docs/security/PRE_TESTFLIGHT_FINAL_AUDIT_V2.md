# Pre-TestFlight Final Audit — V2

**Date:** 2026-06-12 · **App:** Snatch It (`com.jdt-inc.snatchit`) · **Backend:** Supabase `hqycwntpfoztoinemqns` + Stripe Connect · **Supersedes:** docs/archive/PRE_TESTFLIGHT_FINAL_AUDIT.md (V1, verdict HOLD). Every V1 blocker was re-verified **live** today — this document records the evidence, not assumptions.

## Executive Verdict

**APPROVED. Approved for TestFlight deployment.** All three V1 blockers (C1 refund-cron collision, C2/C3 open SECURITY DEFINER grants) are remediated and verified against the live database: migration 032 is applied and recorded, the refund cron returns HTTP 200 on every tick (60/60 in the last 2 hours), the refund-less shadow cron is gone, and the privileged RPCs are no longer executable by `anon`/`authenticated`. The V1 "live money impact" finding is formally corrected below — all historical transactions are test-mode; no real customer funds were ever at risk. Remaining items are product-hardening work appropriate for the TestFlight period, not blockers.

## Production Environment Verification

**Correction of V1 finding, verified and explicitly stated:**

- **Total production Stripe transactions = 0.** Basis: all dev/preview build profiles in `eas.json` use `pk_test_…`; the `pk_live_…` key exists only in the `production` EAS profile, which has **never produced a distributed build** (iOS `buildNumber: 1`, TestFlight deployment gated on this audit — no binary has ever reached a real customer). Owner-verified against the Stripe Dashboard: production mode shows zero transactions.
- **All historical transactions are test-mode only.** The database contains 39 payments spanning 2026-03-25 → 2026-06-05 — entirely the pre-distribution development window, executed by seeded dev accounts (shared `profiles.created_at` timestamps confirm seeding) against the test-mode Stripe keys.
- **No real customer funds have ever been processed.**
- **No production refunds are required.** The V1 "two unrefunded buyers" item (`pi_3TN1LSGdOzCmGbHw02bMiDxP` $57.75, `pi_3TYVxLGdOzCmGbHw1iFT4r7a` $33.00) is hereby reclassified: it was a **real workflow defect observed on test-environment data**. The defect itself (refund pipeline down) was genuine and is now fixed; the dollars were test-mode. Cleaning up the two test rows is optional hygiene, not a remediation.
- V1's "live money impact" language is retracted; what V1 correctly caught was that the refund pipeline was broken and **would have** lost real money post-launch. It cannot now: see Payments & Refund Audit.

## Security Audit

All verified live on 2026-06-12 (`has_function_privilege`, `pg_proc.proacl`, `schema_migrations`):

| Function | anon | authenticated | service_role | Status |
|---|---|---|---|---|
| `admin_resolve_dispute(uuid,text,uuid)` | ❌ false | ❌ false | ✅ true | **C2 FIXED** |
| `delete_account_cleanup(uuid)` | ❌ false | ❌ false | ✅ true | **C3 FIXED** |
| `enforce_transfer_expiry()` | ❌ false | ❌ false | ✅ true | Hardened (defense-in-depth) |

Migration `032` is recorded in `schema_migrations` (latest applied). The `delete-account` edge function (service-role caller) is unaffected — account deletion still works, preserving App Store 5.1.1(v) compliance. Cron auth path is closed-loop and secretless-in-repo: pg_cron reads the legacy service-role JWT from **Supabase Vault** at runtime (verified: single secret `service_role_key`, 219 chars, `role=service_role`, no corruption), the platform JWT gateway stays **ON**, and `INTERNAL_CRON_SECRET` is configured so the function's constant-time check passes. No secrets exist in any migration, `eas.json` contains only publishable/anon keys (public by design), `stripe-webhook` remains signature-verified with `verify_jwt=false` (correct and untouched). Carried forward as non-blocking: the broader EXECUTE-grant sweep across the remaining self-guarded DEFINER functions (V1-H3), 6 trigger functions with unpinned `search_path`, and leaked-password protection still disabled in Auth.

## Payments & Refund Audit

**Refund cron — fully operational, verified end to end:**

- **Current definition:** exactly 2 cron jobs remain in the entire database: `enforce-transfer-expiry` (HTTP → edge function: expiry RPC + Stripe refunds + auto-release) and `auto-finalize-auctions`, both `*/2 * * * *`. 
- **Shadow cron eliminated:** `enforce-transfer-expiry-job` (DB-only expiry, no refunds — the C1 root cause) = **0 rows in `cron.job`**. Duplicate `finalize-auctions` also removed.
- **Execution verified:** last 2 hours = 60/60 `succeeded` for both jobs in `cron.job_run_details`; last 5 `net._http_response` entries all **HTTP 200** (22:02–22:10 UTC ticks).
- **Future expired transfers will reach the refund flow:** the only path that can flip `pending → expired` in production is now the edge function (the bare RPC is revoked from clients and unscheduled), and that same function issues the Stripe refund and writes `refunded_at`/`stripe_refund_id` in the same run, with three idempotency layers (FOR UPDATE SKIP LOCKED, refund-before-mark ordering, unique constraints). Current `pending` transfers: 0 — clean state.
- Payment creation, idempotent webhook processing (event dedup + status claim + unique success-per-listing index + unique `transfers.payment_id`), payout release with atomic `payout_released_at` guard, and dispute freeze/sync were re-confirmed unchanged from V1's passing audit. The two expired test-mode rows remain in the DB as historical test data; the cron correctly ignores them (Phase 1 selects `status='pending'` only).

## Profile Trust Audit

- **RPC:** deployed `get_profile_trust_stats` is the v3 dispute-event model (031) — verified live (`stripe_d` CTE present in `pg_get_functiondef`). Spot check (user `2b11…`) returns the independently recomputed values: 7 sales, 5 purchases, 0 active listings, 3 disputes opened (deduped, involving-user semantics), 0 lost, 7/10 terminal — identical to raw-SQL recounts.
- **Dispute attribution:** side-correct (Stripe `lost` → seller, `won` → buyer), deduped per transfer, NULL `transfer_id` rows safely excluded — proven earlier by a 5-scenario synthetic simulation, unchanged since.
- **Reputation ladder:** thresholds and precedence verified against 12 worked examples (lost-dispute floor → New <5 → Elite 100/99% → Top 25/98% → Trusted 5/95% → Needs Review); tier logic uses the raw rate so display rounding can never change a tier; UI derives hero %, pill, and blurb from a single `deriveReputation` call — **UI calculations match DB calculations** (client divides the same numerator/denominator the RPC returns, with a `denom > 0` divide-by-zero guard).
- **No security leaks:** RPC returns counts + one timestamp only; SECURITY DEFINER with pinned `search_path`, owner `postgres`, EXECUTE limited to `anon`/`authenticated`/`service_role`, 1-row guarantee for any UUID; profile screen selects only safe columns; verification badge driven solely by the `stripe_onboarding_complete` boolean. No email, phone, Stripe IDs, payout, or amount data crosses the wire.

## Marketplace Flow Audit

Re-confirmed from the V1 deep trace plus today's DB state (no regressions introduced by 032 — it touched only grants and cron):

- **Listing creation/edit/cancel:** validation + price caps + guards intact; `cancel_listing` RPC self-guards on `auth.uid()`.
- **Bidding:** `validate_and_apply_bid` atomic with SKIP-LOCKED finalizer; `auto-finalize-auctions` healthy (60/60, and the live data shows zero stale active auctions); reservation cleanup runs inside the finalizer every 2 minutes.
- **Buy Now:** 10-min reservation + checkout revalidation + 3-layer payment idempotency — pass.
- **Transfer lifecycle:** pending → seller_sent → buyer_confirmed/auto_released/disputed/expired machine verified; expiry+refund path now actually runs (see above); auto-release payout has the atomic double-payout guard.
- **Disputes:** in-app open (sets `disputed_at` + freeze), `admin_resolve_dispute` now ops-only, Stripe chargeback freeze + `disputes` sync, trust metrics integrate via 031.
- **Payouts:** Connect onboarding/refresh/return flows intact; `stripe_onboarding_complete` gating verified.
- **Account deletion:** edge function path re-verified post-032 (service_role retains `delete_account_cleanup`); anonymization to sentinel UUID intact.
- **Blocking/reporting:** report user + report listing routes, block/unblock with owner-only RLS, feed + realtime filtering, Blocked Users settings screen — all pass.

## App Review Audit

**No App-Review-rejection risk identified for a TestFlight submission.** Compliance surfaces verified present and functional: 1.2 UGC (report user/listing, block, blocked-content hiding, moderation tables with RLS), 1.4/18+ gate at signup, 3.1 (physical-goods marketplace correctly on Stripe, IAP-exempt), 5.1.1 (in-app Privacy Policy, Terms, support + legal contacts, two-stage account deletion), contextual push-permission request, `aps-environment: production`, `ITSAppUsesNonExemptEncryption=false` (no export-compliance friction), icon/splash/scheme present. Pre-submission checklist items that live **outside the repo**: App Store Connect metadata (screenshots, description, support URL, privacy nutrition labels) and confirmation that no code path invokes the camera (camera/mic usage strings are intentionally nulled; only the photo-library picker was found in code — keep it that way or add the string).

## Remaining Risks

None are TestFlight blockers. For the TestFlight period and before public release: **H1** auction winners have no payment deadline/reclaim path (stuck-listing product gap — most likely defect beta testers will surface); **H2** Buy Now is permitted on auctions with active bids (define policy); **M-class:** notification preferences not enforced server-side; notification tap routing handles only `auction_won`; push tokens stay active after logout; banned-words content filter is thin for public scale; post-payout chargeback reversal is a manual ops runbook; remaining DEFINER grant sweep + `search_path` pins; enable leaked-password protection; seller-vindicated disputes still excluded from success-rate numerator (product decision); two expired test-mode payment rows remain as historical data (optional cleanup before launch analytics). Schema drift discipline: keep prod-only DDL out of the dashboard — everything since 029 is now migration-tracked; keep it that way.

## Final Approval Status

**APPROVED — Approved for TestFlight deployment.**

Evidence chain: migration 032 applied and recorded → privileged RPC grants verified revoked (6/6 negative checks, 3/3 service_role positive) → refund cron verified healthy (0 shadow jobs, 60/60 succeeded, HTTP 200 ticks) → trust RPC v3 verified live with matching UI/DB math → production Stripe transaction count verified **zero** (test-mode-only history; no production refunds owed). Proceed with the TestFlight build; track the Remaining Risks list during beta.

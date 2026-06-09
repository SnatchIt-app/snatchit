# Public Profile Final Audit

**Date:** 2026-06-09 · **Auditor:** Claude (deep trace: live DB → RPC → TypeScript → React state → UI) · **Project:** Snatch It (`hqycwntpfoztoinemqns`)

## Verdict

**APPROVED — No blockers found.** The Public Profile system is ship-ready. Migration 031 (dispute-event dedup fix) is confirmed **deployed to the live database** and its output was verified row-for-row against raw SQL. All remaining findings are Low/Medium, non-blocking, and listed under Remaining Risks.

## Scope Audited

Public Profile screen (`app/profile/[id].tsx`), `VerifiedSellerBadge`, Trust & Activity metrics, Seller Reputation tier rendering, active listings on profile + tap-through to listing detail, Block/Unblock/Report flows, empty and new-seller states, RPC `public.get_profile_trust_stats(uuid)`, migrations `029_public_profiles.sql` / `030_profile_trust_stats.sql` / `031_profile_trust_stats_dispute_fix.sql`, privacy exposure, and App Review risk. Payments, Stripe webhooks, and transfer logic were read but not modified, per constraints.

## Database / RPC

**Deployed function = migration 031 (v3).** Verified via `pg_get_functiondef`: the live body contains the `stripe_d` dispute-event CTE; live RPC output for a real user (`2b11…`: sales 7, purchases 5, disputes_opened 3, lost 0, 7/10 terminal) exactly matches the v3 inline formula previously verified read-only.

Structural guarantees, all verified live: returns **exactly one row** for any UUID including nonexistent ones (top-level SELECT, no FROM); counts can never be NULL; `member_since` is NULL-safe with `COALESCE(profiles.created_at, auth.users.created_at)` — live data has 0 NULL `profiles.created_at` and 0 auth users without profiles. `SECURITY DEFINER` (owner `postgres`), `STABLE`, pinned `SET search_path = public`, schema-qualified references. EXECUTE granted to `anon`/`authenticated`/`service_role` only; PUBLIC revoked. RLS is enabled on `profiles`, `listings`, `transfers`, `disputes`; the definer function intentionally bypasses it to return **counts only**.

Migrations: 029 adds `bio`/`avatar_url` + public-read / update-own RLS on profiles (idempotent, verified live: profiles SELECT policy present). 030 created the v2 RPC. 031 replaces it with the dispute-event model — same 8-column signature, so no TypeScript change was required. 029–031 are all idempotent (`IF NOT EXISTS` / `CREATE OR REPLACE`).

## Data Accuracy

Every metric was recomputed with raw SQL against the live DB and compared to RPC output for **all users with activity — exact match in every case.**

- **Completed Sales / Purchases:** `transfers` with `status IN ('buyer_confirmed','auto_released')` on the seller/buyer side. Constraint-verified: no `cancelled` status exists; `pending`/`seller_sent`/`disputed`/`expired`/`reversed` correctly excluded. No double-counting; all 26 live transfers conform.
- **Active Listings:** `status='active' AND auction_status='active'` — identical filters in RPC and the on-screen listings query. 0 stale expired-but-active rows live (auto-finalize cron healthy); `active/cancelled` rows correctly excluded.
- **Disputes Opened:** unique dispute events involving the user — transfer markers (`disputed_at`/`status='disputed'`) OR linked Stripe `disputes` rows, deduped per `transfer_id`. Cross-checked: 5 disputed transfers → counted once per involved party.
- **Disputes Lost:** side-correct and deduped. Seller loses on `resolved_buyer_refunded`/`resolved_partial_refund` OR Stripe `lost`; buyer loses on `resolved_seller_paid` OR Stripe `won`. Max one lost event per transfer per user. Verified with a 5-scenario synthetic simulation (Stripe lost/won, both in-app resolutions, duplicate markers, NULL `transfer_id`) — all outcomes correct.
- **Transfer Success Rate:** numerator = seller successes minus known seller-lost events; denominator = 5 terminal states, each transfer counted once. Client divides only when denominator > 0 (no divide-by-zero). Examples: 10/10 → 100%; 10 successful + 1 lost → 10/11 → 91%; 100 + 3 lost → 100/103 → 97%.
- **Member Since:** sourced from RPC with `profile.created_at` fallback, then "—"; `toLocaleDateString` renders "February 2026" style correctly from Postgres ISO timestamps.

## UI / UX

RPC array response correctly unwrapped (`statsRow[0]`); `ProfileTrustStats` type matches RPC columns 1:1. Reputation ladder (`deriveReputation`) verified against 12 worked examples — thresholds and precedence correct: lost dispute → Needs Review (trust floor, beats any volume); <5 sales → New Seller; 100+/99% → Elite; 25+/98% → Top; 5+/95% → Trusted; else Needs Review. Tier checks use the raw rate, not the rounded display value, so rounding can never change a tier. Hero %, tier pill, and blurb all derive from one `deriveReputation` call — no mismatch possible. Tier colors cover all 5 tiers. Active listing rows route to `/listing/[id]` — route exists (`app/listing/[id].tsx`); cover image falls back to a placeholder; `fmt$` null-safe.

## Privacy & Safety

**No email, phone, Stripe IDs, payout info, or payment amounts are exposed anywhere in this surface.** Verified at three layers: (1) the profile query selects only `id, display_name, avatar_url, avatar_path, bio, created_at, is_verified_seller, stripe_onboarding_complete`; (2) the RPC returns counts and one timestamp only — no amounts, no identifiers; (3) the listings query exposes listing data already public on the feed. The Verified Seller badge is driven by the boolean `stripe_onboarding_complete` only — no Stripe identifier touches the client. `profiles` public-read RLS (029) is safe because sensitive columns are never selected by this screen, and the trust RPC's DEFINER bypass leaks nothing beyond aggregate counts.

## Block / Report Flows

**Block:** confirm dialog → insert into `user_blocks` (RLS: owner-only policy, verified live) → duplicate insert (23505) treated as success → routes back; feeds drop the seller via `useBlockedUserIds`. Blocked state on the profile hides trust stats and all listings and shows an Unblock CTA. Signed-out users get a sign-in prompt. **Unblock:** deletes the row, clears state, reloads the profile. **Report:** routes to `/report/user/[id]` — route exists (`app/report/[type]/[id].tsx`). Both actions are hidden on the user's own profile. This satisfies App Store Guideline 1.2 (UGC: report + block + content hiding). **App Review risk: Low.**

## Edge Cases

Verified: missing/unknown profile → "This profile isn't available."; ghost UUID through RPC → 1 row, zeros, NULL `member_since` → UI renders "—"; new seller (0 sales) → "New Seller / No completed transfers yet", rate shows "—"; 1–4 sales → "N of 5 sales toward Trusted"; zero listings → "No active listings right now."; RPC error → warned, panel falls back to zeros (see Bugs L3); `disputes.transfer_id` NULL → excluded safely, no crash, no misattribution; anonymized zero-UUID account behaves like a normal sparse profile; blocked-then-unblocked reloads cleanly; self-profile hides moderation buttons.

## Bugs Found

No Critical or High issues. No blockers found.

- **M1 (Medium, by design):** `admin_resolve_dispute` leaves `status='disputed'`, so a seller-vindicated dispute (`resolved_seller_paid`) is permanently excluded from Completed Sales and the success numerator — sellers who *win* disputes still take the rate hit. Product decision required; not a correctness bug in the implemented spec.
- **M2 (Medium, latent):** an **open** (not yet lost) post-payout Stripe chargeback on an `auto_released` transfer still counts as a success until `charge.dispute.closed` lands — the 031 numerator subtracts only *known lost* events, per spec.
- **L1 (Low):** displayed rate uses `Math.round` — 199/200 renders "100%". Tier logic unaffected.
- **L2 (Low):** "Disputes Opened" label now means disputes *involving* the user (buyer or seller side); copy could be read as "opened by". Cosmetic.
- **L3 (Low):** on RPC failure the panel fails open to zeros / "New Seller" instead of an error state — misleading but not harmful.
- **L4 (Low):** `disputes.status` has no CHECK constraint; a renamed Stripe status string would silently stop matching `'lost'`/`'won'`.

## Fixes Applied

None in this audit pass (no blockers; rules forbid non-blocker code changes). Previously applied and now verified live: migration 031 fixing B1 (invisible post-payout chargebacks inflating success rate), B1b (NULL `transfer_id` handled safely), B2 (Stripe outcome side-attribution corrected), B2b (per-transfer dedup eliminating double counts). No TypeScript or UI changes were needed; no payment/webhook/transfer logic was touched.

## Remaining Risks

M1/M2/L1–L4 above. Additionally: Active Listings accuracy depends on the `auto-finalize-auctions` cron staying scheduled (currently healthy, 0 stale rows); the dispute metrics have zero live dispute rows exercising them in production yet — the synthetic simulation covers the logic, but the first real chargeback is worth a manual spot-check; the anonymized zero-UUID profile is publicly reachable like any profile (sparse, harmless, but visible).

## Final QA Checklist

| # | Check | Result |
|---|---|---|
| 1 | Migration 031 deployed; live function = repo definition | ✅ Pass |
| 2 | RPC returns exactly 1 row for any UUID (incl. nonexistent) | ✅ Pass |
| 3 | All 8 metrics match raw SQL recounts for every active user | ✅ Pass |
| 4 | Dispute side-attribution + dedup (5-scenario simulation) | ✅ Pass |
| 5 | No divide-by-zero; "—" rendered when no terminal transfers | ✅ Pass |
| 6 | Reputation ladder thresholds + precedence (12 examples) | ✅ Pass |
| 7 | Verified badge driven by boolean only; no Stripe IDs client-side | ✅ Pass |
| 8 | No email / phone / payout / payment data in any query or payload | ✅ Pass |
| 9 | Active listings filter parity (RPC ↔ screen query ↔ public visibility) | ✅ Pass |
| 10 | Listing tap → `/listing/[id]` route exists | ✅ Pass |
| 11 | Block / Unblock / Report flows + RLS + Guideline 1.2 | ✅ Pass |
| 12 | Empty, new-seller, blocked, not-found, ghost-UUID states | ✅ Pass |
| 13 | RPC grants (anon/authenticated only), DEFINER, pinned search_path | ✅ Pass |
| 14 | Member Since formatting + fallback chain | ✅ Pass |
| 15 | Payments / Stripe webhooks / transfer logic untouched | ✅ Pass |

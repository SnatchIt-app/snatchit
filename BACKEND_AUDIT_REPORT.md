# SnatchIt Backend Audit Report

**Date:** March 29, 2026
**Auditor role:** Principal Backend Engineer / Security Engineer / Production Readiness Reviewer
**Scope:** Full adversarial backend audit — auth, schema, payments, transfers, edge functions, migrations, security hardening

---

## SECTION 1 — Executive Verdict

**Production-readiness score: 5.5 / 10**

SnatchIt has a strong foundation — Supabase RLS is well-configured, payment flow architecture is sound, and the critical `send-push` authorization hole has been patched. However, several **launch blockers** remain that would cause real financial or data-integrity issues under production load. The transfers table and its RPCs are not tracked in version-controlled schema, two different sets of RPC names exist for the same transfer operations (naming collision), text/numeric inputs have no server-side bounds, rate limiting is absent on payment endpoints, and only one migration file exists with no rollback discipline. These are fixable in a focused sprint, but the app **should not launch with real payments** until the items in Section 2 are resolved.

---

## SECTION 2 — Top Launch Blockers (fix before any public launch)

### BLOCKER 1 — Transfer RPC Name Mismatch (CRITICAL)
Two different sets of transfer RPCs are referenced in client code:

| RPC name | Called from |
|---|---|
| `seller_send_transfer` | `app/transfer/send/[id].tsx` (line 89) |
| `buyer_confirm_transfer` | `app/transfer/receive/[id].tsx` (line 82) |
| `mark_transfer_sent` | `src/screens/ListingDetailScreen.tsx` (line 735) |
| `confirm_transfer_received` | `src/screens/ListingDetailScreen.tsx` (line 748) |

If the deployed DB only has one set, half the client flows will throw "function does not exist" errors at runtime. Either the dedicated transfer screens or the ListingDetailScreen calls will fail. This must be reconciled — pick one naming convention, ensure both screens call the same RPCs, and delete the unused set.

### BLOCKER 2 — Transfers Table Not in Version-Controlled Schema
The `transfers` table exists in the live database (created via ad-hoc SQL) but is **not** in `supabase/schema.sql` or any migration file. This means:

- No developer can reproduce the schema from source
- No CI/CD pipeline can validate it
- RLS policies on transfers are unknown/unaudited from source
- If the DB is recreated, all transfer functionality breaks

The transfers table, its RLS policies, its indexes, and its RPCs (`seller_send_transfer` / `buyer_confirm_transfer` or `mark_transfer_sent` / `confirm_transfer_received`) must all be committed to a migration file.

### BLOCKER 3 — `stripe_connect_id` Column Not in Tracked Schema
The `stripe_connect_id` column on `profiles` is referenced in edge functions (`create-connect-account`, `stripe-webhook`) but does not appear in `schema.sql` or any migration. Same reproducibility risk as above.

### BLOCKER 4 — No Rate Limiting on Payment Endpoints
`create-payment-intent`, `confirm-payment`, and `create-connect-account` have **zero rate limiting**. A malicious or buggy client can:

- Create thousands of Stripe PaymentIntents (each costs API quota and creates Stripe objects)
- Hammer confirm-payment in a loop
- Create multiple Stripe Connect accounts for the same user

At minimum, add per-user rate limiting (e.g., 5 requests/minute) via Supabase's built-in rate limiter or a simple token-bucket in the edge function.

### BLOCKER 5 — No Input Bounds on Text and Numeric Fields
- `event_name`, `venue`, `section`, `row`, `seat` — no max length constraint anywhere (DB or client). A user can submit a 10MB string as a venue name.
- `amount` on bids — no upper bound. A user can submit a bid of $999,999,999.
- `starting_bid`, `buy_now_price` — no upper bound on listing creation.

Add `CHECK` constraints in the schema: text fields ≤ 500 chars, bid amounts ≤ $100,000 (or whatever makes business sense), prices > 0.

---

## SECTION 3 — Full Audit by Category

### 3.1 Auth & Authorization

**What's solid:**
- Supabase Auth with email/password is correctly implemented
- RLS is enabled on all tables
- `payments` table correctly has NO client INSERT/UPDATE policies — only edge functions (service-role) can write
- `send-push` now requires service-role Bearer token with constant-time comparison
- All RPCs use `SECURITY DEFINER` with `SET search_path = public` (prevents search_path hijacking)
- Bid validation trigger enforces 1 bid per 3 seconds per user per listing

**What needs attention:**
- `auto-finalize-auctions` uses `token !== SUPABASE_SERVICE_ROLE_KEY` — a non-timing-safe comparison. Should use the same constant-time XOR comparison as `send-push`.
- Signup has a 6-character minimum password but no complexity requirements. Acceptable for beta but consider strengthening.
- `handleForgotPassword` in `login.tsx` doesn't rate-limit reset emails client-side (Supabase has server-side limiting, but adding client-side debounce is good UX).

### 3.2 Schema Integrity

**What's solid:**
- `listings` has a status constraint: `pending`, `active`, `sold`, `expired`, `cancelled`
- `transfers` has a status constraint: `pending`, `seller_sent`, `buyer_confirmed`, `disputed`, `expired`
- Guard triggers prevent direct client mutation of `listings.status` and identity columns
- `IS DISTINCT FROM` used for NULL-safe UUID comparison
- `bids` has proper foreign keys to `listings` and `profiles`

**What needs attention:**
- No `CHECK` constraint on text field lengths anywhere
- No `CHECK` constraint on numeric upper bounds
- No unique constraint preventing duplicate `stripe_connect_id` values (two profiles could theoretically share one)
- `push_tokens.token` should have a unique constraint to prevent duplicate registrations
- No index on `transfers.listing_id` (will slow down transfer lookups as data grows)

### 3.3 Payments (Stripe Integration)

**What's solid:**
- `stripe-webhook` verifies HMAC-SHA256 signature using `Stripe-Signature` header
- `create-payment-intent` uses idempotency keys (listing_id + buyer_id)
- Payment flow: client creates intent → Stripe processes → webhook confirms → DB updates
- `confirm-payment` verifies PaymentIntent status with Stripe before updating DB
- Stripe Connect Express used for seller payouts (correct for marketplace model)

**What needs attention:**
- **TOCTOU in stripe-webhook:** Between reading the payment record and calling `mark_listing_sold` RPC, another webhook delivery could race. The RPC should be idempotent (check current status before transitioning).
- **TOCTOU in create-payment-intent:** Listing status is checked, then PaymentIntent is created. A concurrent `buy_now` could create two PIs for the same listing. The idempotency key mitigates this for the same buyer but not for different buyers.
- **confirm-payment returns 200 even if no record updated.** If the `UPDATE` matches zero rows, the function still returns `{ success: true }`. Should check `count` and return an error if nothing was updated.
- **Metadata values in stripe-webhook** (`listing_id`, `buyer_id`, `seller_id`) are used without format validation. Should validate UUID format before passing to RPCs.
- **No webhook replay protection.** If Stripe replays a webhook, the same operations run again. The RPCs should be idempotent (most likely are if status checks are in place, but this needs explicit verification).

### 3.4 Transfer Lifecycle

**What's solid:**
- Transfer status machine: `pending` → `seller_sent` → `buyer_confirmed` (with `disputed` and `expired` branches)
- Transfers are created by the webhook after successful payment (server-side only)
- Transfer screens exist for both buyer and seller flows

**What needs attention:**
- **RPC name mismatch** (see Blocker 1) — the most critical transfer issue
- **No expiration enforcement.** There's no cron/scheduled function to auto-expire transfers where the seller never ships. `auto-finalize-auctions` handles auction expiry but nothing handles transfer expiry.
- **No dispute resolution flow.** `disputed` is a valid status but there's no UI or backend logic to handle it.
- **Transfer RLS policies are unaudited** since the table isn't in version-controlled schema.

### 3.5 Edge Function Security

| Function | Auth | Rate Limit | Input Validation | CORS |
|---|---|---|---|---|
| stripe-webhook | HMAC-SHA256 ✅ | N/A (Stripe controls) | Metadata not validated ⚠️ | `*` ⚠️ |
| create-payment-intent | JWT ✅ | None ❌ | Listing status checked ✅ | `*` ⚠️ |
| confirm-payment | JWT ✅ | None ❌ | PI status verified ✅ | `*` ⚠️ |
| create-connect-account | JWT ✅ | None ❌ | No input validation ❌ | `*` ⚠️ |
| send-push | Service-role ✅ | N/A (internal) | user_id/title/body required ✅ | `*` ⚠️ |
| auto-finalize-auctions | Service-role (non-timing-safe) ⚠️ | N/A (cron) | N/A | `*` ⚠️ |

**All functions return `Access-Control-Allow-Origin: *`.** For a mobile app with no web client, this is low-risk but unnecessarily permissive. If you never intend a web client, restrict to your app's domain or remove CORS headers entirely.

### 3.6 Sentry & Observability

**What's solid:**
- `Sentry.init()` is called at module scope in `_layout.tsx`
- `Sentry.wrap(RootLayout)` wraps the root component
- `ErrorBoundary` calls `Sentry.captureException` with component stack context
- Error boundary provides user-friendly fallback UI

**What needs attention:**
- `Sentry.init()` does not set `release`, `environment`, or `dist` — you won't be able to correlate errors with specific app versions or distinguish staging from production.
- `Sentry.setUser()` is never called after login — errors won't be attributable to specific users.
- No source maps upload configured — stack traces will show minified code.
- No Sentry alert rules configured — errors will accumulate silently unless someone checks the dashboard.
- Edge functions have no Sentry integration at all — server-side errors are only in Supabase logs.

### 3.7 Migrations & Rollback Discipline

**Current state:** One migration file exists (`001_profile_additions.sql`). Everything else is in `schema.sql` or was applied via ad-hoc SQL in the Supabase dashboard.

**What this means:**
- There is no way to reproduce the production database from source control alone
- There is no rollback path for any schema change
- There is no CI/CD validation of schema changes
- `transfers` table, `stripe_connect_id`, and any transfer RPCs are untracked

**What's needed:**
- Every schema object must be in a numbered migration file
- Each migration should have a corresponding `down` migration (or at minimum, a documented rollback plan)
- `supabase db diff` should be run to capture the delta between tracked schema and live DB
- A migration for the transfers table + RPCs + indexes should be the immediate next file

---

## SECTION 4 — Exact Missing Pieces

### Missing from schema.sql / migrations:
1. `transfers` table (DDL, RLS policies, indexes)
2. `stripe_connect_id` column on `profiles`
3. Transfer RPCs (whichever naming convention you choose)
4. `CHECK` constraints on text field lengths
5. `CHECK` constraints on numeric bounds (bid amounts, prices)
6. Unique constraint on `push_tokens.token`
7. Unique constraint on `profiles.stripe_connect_id`
8. Index on `transfers.listing_id`

### Missing from edge functions:
9. Rate limiting on `create-payment-intent`
10. Rate limiting on `confirm-payment`
11. Rate limiting on `create-connect-account`
12. Timing-safe auth comparison in `auto-finalize-auctions`
13. Metadata UUID format validation in `stripe-webhook`
14. Zero-row-updated check in `confirm-payment`
15. `refresh_url` / `return_url` validation in `create-connect-account`

### Missing from client:
16. Reconcile transfer RPC names (pick one set, update all call sites)

### Missing from observability:
17. `release` + `environment` in `Sentry.init()`
18. `Sentry.setUser()` after login
19. Source maps upload to Sentry (EAS build hook or manual)
20. Sentry alert rules (error spike, new issue, unhandled exception)
21. Sentry integration in edge functions

### Missing from infrastructure:
22. Transfer expiration cron job
23. Migration pipeline (numbered files, CI check)
24. Rollback scripts for each migration

---

## SECTION 5 — What Is Already Solid

These areas are production-quality and need no changes:

1. **RLS coverage** — Every table has RLS enabled with appropriate policies. `payments` correctly blocks all client writes.
2. **Stripe webhook signature verification** — HMAC-SHA256 verification is correctly implemented with raw body parsing.
3. **send-push authorization** — Constant-time service-role key verification. Only internal callers can send push notifications.
4. **Bid validation trigger** — Server-side enforcement of 1 bid per 3 seconds per user per listing. Cannot be bypassed by clients.
5. **Guard triggers** — Prevent direct mutation of `listings.status` and identity columns. State transitions must go through RPCs.
6. **SECURITY DEFINER RPCs** — All RPCs set `search_path = public`, preventing search_path injection.
7. **`FOR UPDATE` row locking** — RPCs that modify listing state acquire row locks, preventing concurrent mutation.
8. **Idempotency keys** — `create-payment-intent` uses `listing_id + buyer_id` as the idempotency key, preventing duplicate PaymentIntents for the same buyer on the same listing.
9. **Error boundary** — Catches render errors, shows fallback UI, reports to Sentry with component stack.
10. **Auth flow** — Clean separation of auth/unauth routes. Deep link handling works with Supabase implicit flow. Password reset flow is functional.

---

## SECTION 6 — Recommended Fix Order

Priority is based on: financial risk > data integrity > security hardening > observability > hygiene.

| Priority | Item | Effort | Risk if skipped |
|---|---|---|---|
| **P0** | Reconcile transfer RPC names (Blocker 1) | 1 hour | **Transfer screens crash at runtime** |
| **P0** | Add transfers table + RPCs to migration (Blocker 2) | 2 hours | **Schema unreproducible, RLS unaudited** |
| **P0** | Add `stripe_connect_id` to migration (Blocker 3) | 30 min | **Schema unreproducible** |
| **P0** | Add input bounds (text + numeric CHECKs) (Blocker 5) | 2 hours | **DB bloat, absurd bids, potential DoS** |
| **P1** | Rate limiting on payment edge functions (Blocker 4) | 3 hours | **Stripe API abuse, cost exposure** |
| **P1** | Fix `auto-finalize-auctions` timing-safe comparison | 30 min | **Theoretical timing attack on service key** |
| **P1** | Add zero-row check to `confirm-payment` | 30 min | **Silent payment confirmation failures** |
| **P2** | Sentry `release` + `environment` + `setUser` | 1 hour | **Can't triage errors by version or user** |
| **P2** | Source maps upload | 1 hour | **Minified stack traces** |
| **P2** | Sentry alert rules | 30 min | **Errors go unnoticed** |
| **P2** | Metadata validation in `stripe-webhook` | 1 hour | **Malformed UUIDs could cause RPC failures** |
| **P3** | Transfer expiration cron | 2 hours | **Stale transfers hang indefinitely** |
| **P3** | CORS restriction on edge functions | 30 min | **Low risk for mobile-only app** |
| **P3** | Unique constraints (push_tokens, stripe_connect_id) | 30 min | **Duplicate data possible** |
| **P3** | Full migration pipeline + rollback scripts | 4 hours | **No rollback path for future changes** |

---

## SECTION 7 — Implementation Roadmap

### Sprint 1 — Launch Blockers (3–4 days)

**Day 1: Schema reconciliation**
- Run `supabase db diff` to capture all untracked objects
- Write `002_transfers.sql` migration: transfers table DDL, RLS policies, indexes, RPCs (pick one naming convention)
- Write `003_stripe_connect.sql`: add `stripe_connect_id` to profiles with unique constraint
- Add `CHECK` constraints for text lengths (≤ 500) and numeric bounds (amounts ≤ 100000, amounts > 0)

**Day 2: Client reconciliation**
- Decide on RPC names: `seller_send_transfer` / `buyer_confirm_transfer` OR `mark_transfer_sent` / `confirm_transfer_received`
- Update all client call sites to use the chosen names
- Delete the unused RPCs from the DB and migration files
- Test both transfer flows end-to-end (seller sends → buyer confirms)

**Day 3: Edge function hardening**
- Add rate limiting to `create-payment-intent`, `confirm-payment`, `create-connect-account`
- Fix `auto-finalize-auctions` to use constant-time key comparison
- Add row-count check to `confirm-payment`
- Validate UUID format on metadata fields in `stripe-webhook`

**Day 4: Verify**
- Run full flow test: signup → create listing → place bid → auction ends → payment → transfer → payout
- Verify all migrations apply cleanly on a fresh database
- Verify all RLS policies on transfers table

### Sprint 2 — Observability & Hardening (2–3 days)

**Day 5: Sentry**
- Add `release`, `environment`, `dist` to `Sentry.init()`
- Call `Sentry.setUser({ id, email })` after successful login
- Configure source maps upload in EAS build
- Set up alert rules: new issue, error spike > 10/hour, unhandled exception

**Day 6: Infrastructure**
- Build transfer expiration cron (similar to `auto-finalize-auctions`)
- Tighten CORS headers on all edge functions (or remove if mobile-only)
- Add unique constraint on `push_tokens.token`
- Document rollback procedures for each migration

**Day 7: Final review**
- Security review of all changes
- Load test payment endpoints to verify rate limits
- Confirm Sentry is receiving errors with correct release tags
- Sign off for beta launch

---

*End of audit. This report should be treated as a living document — revisit after Sprint 1 to reassess the P2/P3 items.*

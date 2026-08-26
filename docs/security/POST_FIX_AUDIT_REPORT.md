# SnatchIt Post-Fix Pre-Launch Audit Report

**Date:** April 14, 2026
**Codebase:** SnatchIt — React Native / Expo ticket resale marketplace
**Stack:** React Native 0.81.5 · Expo SDK 54 · Supabase (Postgres + Auth + Edge Functions) · Stripe Connect
**Scope:** Full 8-phase re-audit after critical fix sweep

---

## Executive Summary

Five critical issues identified in the initial audit have been resolved. The codebase's security posture has improved materially: CORS is locked down, the delete-account function is structurally sound, Sentry is receiving error telemetry, and npm dependencies carry zero known vulnerabilities. The application is closer to launch-ready but still carries important gaps — zero automated test coverage and missing HTTP security headers — that warrant resolution before or immediately after go-live.

**Verdict: CONDITIONAL GO ⚠️** — Ship with the mandatory pre-launch items below; schedule the advisory items for Sprint 1.

---

## Phase 1: Architecture Review

### Stack Topology

| Layer | Technology | Notes |
|-------|-----------|-------|
| Mobile client | React Native 0.81.5, Expo SDK 54, Expo Router 6 | New Architecture + React Compiler enabled |
| Auth | Supabase Auth (JWT, email/password) | Auto-refresh via SDK; stale-token detection in useAuth |
| Database | Supabase Postgres with RLS | All tables RLS-enabled; guard triggers on sensitive columns |
| Edge Functions | 8 Deno functions (Supabase) | CORS whitelisted, rate-limited, auth-verified |
| Payments | Stripe PaymentIntents + Connect Express | 3-layer idempotency on payouts; webhook HMAC verified |
| Storage | Supabase Storage (avatars, auction-media) | Bucket-level policies; cleaned on account deletion |
| Monitoring | Sentry 7.2 | DSN now correctly configured |
| Push | Expo Push Notifications | Internal-only send-push function with constant-time auth |

### Data Flow (Happy Path — Buy Now)

1. Buyer taps "Buy Now" → client calls `create-payment-intent` edge function
2. Edge function: rate-limit check → `reserve_listing_for_purchase` RPC (atomic reservation with 10-min TTL) → Stripe PaymentIntent created → `client_secret` returned
3. Client presents Stripe PaymentSheet → buyer completes payment
4. Client calls `confirm-payment` (best-effort bookkeeping) + Stripe fires `payment_intent.succeeded` webhook
5. Webhook: claims payment row with `.neq('status','succeeded')` → calls `mark_listing_sold` RPC → creates transfer row → defers payout → sends push
6. Buyer confirms receipt → `confirm-and-release` → `confirm_transfer_received` RPC → Stripe Transfer to seller Connect account (atomic `WHERE payout_released_at IS NULL`)

### Architecture Strengths

- Business-critical logic lives in Postgres RPCs and triggers, not in client code
- Financial state transitions are guarded by atomic SQL (FOR UPDATE SKIP LOCKED, UPDATE WHERE ... IS NULL)
- Shill-bid prevention and self-purchase blocking enforced at database trigger level
- Seller risk scoring with pre-listing fraud gates (`can_create_listing` RPC)
- Transfer lifecycle with automatic expiry, refunds, and auto-release for buyer ghost protection

---

## Phase 2: Security Gate (15-Point Check)

| # | Check | Status | Detail |
|---|-------|--------|--------|
| 1 | Secrets in source | **PASS** | No hardcoded sk_live, sk_test, passwords, or API keys in code. All secrets loaded from env vars. .env files gitignored. |
| 2 | Git history secrets | **PASS** | No credentials detected in commit history. |
| 3 | CORS policy | **PASS (FIXED)** | All 8 edge functions now use ALLOWED_ORIGINS whitelist with dynamic getCorsHeaders(req). No wildcards remain. |
| 4 | Webhook signature verification | **PASS** | stripe-webhook uses HMAC-SHA256 with timing-safe comparison via Stripe SDK. |
| 5 | Auth on all endpoints | **PASS** | User-facing functions verify JWT; cron functions verify service-role key; send-push uses constant-time comparison. |
| 6 | Rate limiting | **PASS (4/5)** | create-payment-intent (5/60s), confirm-payment (10/60s), confirm-and-release (5/300s), create-connect-account (5/600s). delete-account lacks rate limiting — see Advisory A3. |
| 7 | RLS on all tables | **PASS** | Every table has ALTER TABLE ... ENABLE ROW LEVEL SECURITY with appropriate policies. |
| 8 | SQL injection | **PASS** | All queries use parameterized Supabase client or RPC parameters. No string interpolation in SQL. |
| 9 | eval/exec usage | **PASS** | Zero instances of eval(), new Function(), or dynamic code execution. |
| 10 | npm vulnerabilities | **PASS (FIXED)** | `npm audit` returns 0 vulnerabilities (was 8 — 6 high, 2 moderate). |
| 11 | Sentry DSN | **PASS (FIXED)** | Correctly formatted single `https://` protocol. Error telemetry now operational. |
| 12 | Delete-account integrity | **PASS (FIXED)** | Sentinel UUID pattern with migration 019. Anonymization uses ANONYMIZED_USER_ID instead of null. auction_status column used correctly. |
| 13 | HTTP URLs in code | **PASS** | Single http:// reference is the Deno std library import (legitimate). All API calls use HTTPS. |
| 14 | Security headers | **FAIL** | No Strict-Transport-Security, X-Content-Type-Options, X-Frame-Options, or Content-Security-Policy headers on any edge function response. See Advisory A1. |
| 15 | Password policy | **ADVISORY** | No client-side password complexity enforcement visible. Relies on Supabase Auth defaults (6-char minimum). See Advisory A5. |

**Security Gate Score: 13/15 PASS · 1 FAIL · 1 ADVISORY**

### Critical Issues (C1–C5) — All Resolved

| ID | Issue | Resolution | Verified |
|----|-------|-----------|----------|
| C1 | Malformed Sentry DSN (doubled https://) | Removed duplicate protocol prefix in .env.production | grep confirms single https:// |
| C2 | delete-account NULL assignment on NOT NULL columns | Sentinel UUID 00000000-0000-0000-0000-000000000000 with migration 019 | All update() calls use ANONYMIZED_USER_ID |
| C3 | delete-account invalid status='cancelled' | Changed to auction_status='cancelled' | grep confirms correct column |
| C4 | 8 npm CVEs (6 high) | npm audit fix resolved all | npm audit returns 0 vulnerabilities |
| C5 | CORS wildcard on all edge functions | ALLOWED_ORIGINS whitelist + getCorsHeaders(req) on all 8 functions | grep finds zero wildcards |

---

## Phase 3: Code Quality Review (5 Dimensions)

### 3.1 Correctness

**Strong.** Financial state machine is well-designed with multiple idempotency layers:
- RPC-level: Postgres atomic operations with FOR UPDATE SKIP LOCKED
- Read guard: `.neq('status', 'succeeded')` claim pattern prevents double-processing
- Write guard: `WHERE payout_released_at IS NULL` prevents double payouts
- Stripe-level: PaymentIntent idempotency keys and Transfer deduplication

**One concern:** `confirm-payment` is best-effort by design (always returns 200). If both confirm-payment AND the webhook fail, the payment record could remain in a stale state. Mitigation: the webhook is the source of truth and retries automatically.

### 3.2 Robustness

**Good.** Error isolation is strong — Phase 1 failures in enforce-transfer-expiry don't block Phase 2. Storage cleanup errors in delete-account are non-fatal. Orphaned PaymentIntent cleanup exists in create-payment-intent.

**Concern:** Rate limiting uses a fail-open design (if check_rate_limit RPC errors, the request proceeds). This is acceptable for availability but could allow abuse during database outages.

### 3.3 Maintainability

**Adequate.** Code is well-commented with clear section markers. Edge functions follow a consistent pattern (auth → rate limit → business logic → response). The CORS helper is copy-pasted across all 8 functions rather than shared — acceptable for Deno edge functions which are independently deployed.

**93 console.log/warn/error statements** across edge functions. These should be rationalized for production — consider structured logging with severity levels.

### 3.4 Security

**Strong after fixes.** JWT validation on all user-facing endpoints. Service-role key verification with constant-time comparison on internal functions (except auto-finalize-auctions which uses direct `!==`). Webhook signature verification. RLS on all tables. Guard triggers prevent direct client modification of auction state.

### 3.5 Performance

**Adequate for launch.** Key observations:
- Bid validation trigger runs inside a transaction (atomic but holds a lock briefly)
- Reservation TTL is 10 minutes — abandoned reservations block other buyers until expiry
- No visible pagination on listing queries in the schema (client-side concern)
- Batch operations use SKIP LOCKED to prevent convoy effects

---

## Phase 4: Front-End Design Checklist

| Check | Status | Notes |
|-------|--------|-------|
| Theme system | PASS | Light/dark mode via Colors constant; system fonts via Platform.select |
| Navigation | PASS | Expo Router 6 file-based routing; NativeAppShell handles deep links |
| Auth state | PASS | useAuth hook with stale-token detection and automatic signout |
| Error boundaries | ADVISORY | Sentry integration present but no visible ErrorBoundary components in the audit scope |
| Form validation | PASS | CreateListingScreen validates inputs before submission; risk check via can_create_listing RPC |
| Loading states | PASS | isLoading state in useAuth prevents UI flicker |
| Offline handling | ADVISORY | No visible offline detection or queuing mechanism |

---

## Phase 5: Dependency Health

| Metric | Value | Assessment |
|--------|-------|------------|
| npm audit | 0 vulnerabilities | **PASS** |
| React Native | 0.81.5 | Current stable |
| Expo SDK | 54 | Current stable |
| Supabase JS | ^2.98.0 | Current v2 stable |
| Stripe RN | 0.50.3 (pinned) | Acceptable; check for updates post-launch |
| Sentry | ~7.2.0 | Current |
| React | 19.1.0 | Current |

**No blocking dependency issues.**

---

## Phase 6: Test Coverage

| Category | Files Found | Assessment |
|----------|------------|------------|
| Unit tests (*.test.*) | 0 | **FAIL** |
| Integration tests (*.spec.*) | 0 | **FAIL** |
| E2E tests | 0 | **FAIL** |
| Test configuration | None | No jest.config, no testing-library setup |

**Test coverage is zero.** This is the single largest quality gap in the codebase. For a financial application handling real money, this represents meaningful risk. The Postgres RPCs and triggers are the most critical code paths and have no automated verification.

**Recommendation:** Before launch, add at minimum:
1. Integration tests for the 3 payment RPCs (reserve, mark_sold, confirm_transfer)
2. Integration tests for the delete-account edge function
3. Smoke tests for each edge function's auth + rate-limit gate

---

## Phase 7: Production Readiness Checklist

| Item | Status | Notes |
|------|--------|-------|
| Environment variables | **PASS** | All secrets in env vars, .env files gitignored |
| Sentry error tracking | **PASS (FIXED)** | DSN correctly formatted |
| CORS lockdown | **PASS (FIXED)** | Origin whitelist on all functions |
| Dependency vulnerabilities | **PASS (FIXED)** | 0 CVEs |
| Account deletion | **PASS (FIXED)** | Sentinel UUID pattern, correct column usage |
| Database RLS | **PASS** | All tables protected |
| Webhook verification | **PASS** | HMAC-SHA256 on Stripe webhook |
| Rate limiting | **PARTIAL** | 4/5 user-facing endpoints rate-limited; delete-account missing |
| Security headers | **FAIL** | None present on any edge function |
| Automated tests | **FAIL** | Zero test files |
| ALLOWED_ORIGINS domains | **ACTION REQUIRED** | Currently set to snatchitapp.com — verify this is the correct production domain |
| Console logging | **ADVISORY** | 93 statements; rationalize before launch |
| Password policy | **ADVISORY** | Supabase default 6-char minimum; consider enforcing 8+ |

---

## Phase 8: Consolidated Verdict & Scorecard

### Scorecard

| Dimension | Score | Weight | Weighted |
|-----------|-------|--------|----------|
| Architecture | 9/10 | 15% | 1.35 |
| Security | 8/10 | 25% | 2.00 |
| Code Quality | 7/10 | 15% | 1.05 |
| Front-End | 7/10 | 10% | 0.70 |
| Dependencies | 10/10 | 10% | 1.00 |
| Test Coverage | 1/10 | 15% | 0.15 |
| Production Readiness | 7/10 | 10% | 0.70 |
| **Total** | | **100%** | **6.95 / 10** |

### Improvement from Initial Audit

| Dimension | Before | After | Delta |
|-----------|--------|-------|-------|
| Security | 5/10 | 8/10 | +3 |
| Dependencies | 6/10 | 10/10 | +4 |
| Production Readiness | 4/10 | 7/10 | +3 |
| **Overall** | **5.45** | **6.95** | **+1.50** |

### Verdict: CONDITIONAL GO ⚠️

The five critical blockers are resolved. The application can ship with the mandatory items below completed.

---

### Mandatory Before Launch

| ID | Item | Effort | Risk if Skipped |
|----|------|--------|----------------|
| M1 | Verify ALLOWED_ORIGINS domains match actual production domain(s) across all 8 edge functions | 15 min | CORS blocks all browser-based API calls |
| M2 | Add security headers to edge function responses (X-Content-Type-Options: nosniff, X-Frame-Options: DENY at minimum) | 1 hr | Clickjacking, MIME-sniffing attacks |
| M3 | Add rate limiting to delete-account function | 30 min | Account deletion abuse/DoS |

### Advisory — Sprint 1

| ID | Item | Effort | Notes |
|----|------|--------|-------|
| A1 | Add Strict-Transport-Security and Content-Security-Policy headers | 2 hr | Full security header suite |
| A2 | Write integration tests for payment RPCs and delete-account | 1-2 days | Highest-value test targets |
| A3 | Add constant-time token comparison to auto-finalize-auctions (matches enforce-transfer-expiry pattern) | 15 min | Currently uses direct !== |
| A4 | Rationalize console logging (structured logging with severity levels) | 4 hr | 93 statements across edge functions |
| A5 | Enforce 8+ character password minimum client-side | 1 hr | Currently relies on Supabase 6-char default |
| A6 | Use getUser() instead of getSession() for payment auth token retrieval | 30 min | getSession() can return cached/stale tokens |
| A7 | Add ErrorBoundary components to React Native screens | 2 hr | Graceful crash recovery |
| A8 | Investigate RECORD_AUDIO permission in app.json | 15 min | Present but no obvious audio feature |

### Launch Checklist

- [ ] Verify ALLOWED_ORIGINS in all 8 edge functions match production domain
- [ ] Add X-Content-Type-Options and X-Frame-Options to edge function responses
- [ ] Add rate limiting to delete-account
- [ ] Run `npm audit` one final time before deploy
- [ ] Verify Sentry is receiving test errors in production
- [ ] Confirm Stripe webhook endpoint is registered for production
- [ ] Confirm sentinel user (00000000-...) exists in production database (run migration 019)
- [ ] Test delete-account flow end-to-end in staging
- [ ] Verify .env.production values are set in deployment environment (not just local file)

---

*Report generated by automated audit · April 14, 2026*

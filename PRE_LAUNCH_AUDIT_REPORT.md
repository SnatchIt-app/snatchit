# SnatchIt Pre-Launch Audit Report

**Date:** April 13, 2026  
**Auditor:** Claude (Automated Full-Stack Security & Production Readiness Audit)  
**Scope:** Complete codebase — frontend (React Native/Expo), backend (Supabase Edge Functions), database (PostgreSQL/Supabase), payments (Stripe), infrastructure (Vercel)

---

## VERDICT: CONDITIONAL LAUNCH ⚠️

The app has a mature, well-architected backend with strong database-level security controls, idempotent payment flows, and thoughtful fraud prevention. However, **5 critical issues** and **12 important issues** must be addressed. The criticals block a production launch with real money; the importants should be fixed within the first sprint post-launch.

---

## Phase 1: Architecture Overview

### Tech Stack
- **Frontend:** React Native 0.81.5 + Expo SDK 54, TypeScript 5.9, Expo Router 6
- **Backend:** Supabase Edge Functions (Deno), PostgreSQL (via Supabase)
- **Payments:** Stripe (PaymentIntents, Connect Express, Webhooks)
- **Auth:** Supabase Auth (email/password, JWT)
- **Storage:** Supabase Storage (auction-media, avatars buckets)
- **Monitoring:** Sentry (react-native SDK)
- **Push Notifications:** Expo Push Notifications
- **Deployment:** Vercel (web/waitlist), EAS (native builds)
- **Cron:** pg_cron (auction finalization, transfer expiry, auto-release)

### Entry Points
- **App Routes (27):** auth (login, signup, reset-password), tabs (home, create, bids, explore, profile), listing/[id], bid/[id], checkout/[id], transfer/send/[id], transfer/receive/[id], my-listings, settings (7 sub-routes)
- **Edge Functions (9):** create-payment-intent, confirm-payment, confirm-and-release, stripe-webhook, create-connect-account, auto-finalize-auctions, enforce-transfer-expiry, send-push, delete-account
- **Cron Jobs (3):** auto-finalize-auctions (every 5 min), enforce-transfer-expiry (every 5 min), cleanup_expired_reservations (inline)
- **Webhook:** stripe-webhook (payment_intent.succeeded, payment_intent.payment_failed)
- **Waitlist:** Static HTML on Vercel (payout-return.html, payout-refresh.html)

### Data Flow
1. User input enters via React Native TextInput → Supabase client SDK → PostgREST / Edge Functions
2. Sensitive data (Stripe keys, service role key) lives in Deno.env / Supabase secrets — never in client bundle
3. Trust boundaries: Client (anon key) → Supabase PostgREST (RLS) → Edge Functions (service role) → Stripe API / PostgreSQL

### Existing Security Controls (already in place)
- RLS enabled on ALL tables (profiles, listings, bids, payments, transfers, push_tokens, notification_preferences)
- State guard trigger blocks direct client modification of auction state columns
- Identity guard trigger prevents seller_id/id/created_at changes
- Shill-bid prevention (seller cannot bid on own listing)
- Self-purchase prevention (seller cannot buy own listing)
- Bid rate limiting (3-second cooldown, enforced in DB trigger)
- API rate limiting on all payment edge functions (via check_rate_limit RPC)
- Stripe webhook signature verification (HMAC-SHA256)
- Idempotent payment processing (3-layer idempotency on confirm-and-release, enforce-transfer-expiry)
- Atomic reservation system (SELECT FOR UPDATE + status checks)
- Constant-time token comparison (send-push, enforce-transfer-expiry)
- Transfer expiry with automatic refunds (24h deadline)
- Auto-release payout with buyer ghost protection (72h deadline)
- FOR UPDATE SKIP LOCKED in batch operations (prevents double-processing)
- Storage policies: folder-based ownership (user can only upload to their own folder)
- File size limits enforced at bucket level (10MB auction-media, 5MB avatars)
- MIME type restrictions on storage buckets (JPEG, PNG, WebP, HEIC only)
- Stale token detection and automatic sign-out in useAuth hook

---

## Phase 2: Security Audit (15-Point Gate)

### 1. Injection — ✅ CLEAR
- No raw SQL construction anywhere in code. All queries use Supabase client SDK (parameterized).
- No `eval()`, `exec()`, `Function()`, `innerHTML`, or `dangerouslySetInnerHTML` found.
- Edge functions parse JSON bodies with `req.json()` — no string interpolation into queries.
- Database trigger validates bid amounts server-side, preventing injection via bid values.

### 2. Authentication — ✅ CLEAR
- Password hashing handled by Supabase Auth (bcrypt, server-side).
- JWT verification on all edge functions via `supabase.auth.getUser(token)`.
- Password minimum length: 6 characters (Supabase default).
- Stale token detection with automatic signOut.
- **Advisory:** No MFA support. Consider for high-value accounts.

### 3. Authorization — ⚠️ ADVISORY
- RLS on all tables with correct owner-based policies.
- Edge functions verify buyer identity before payment operations.
- Self-purchase and shill-bid guards at both DB and edge function layers.
- **Finding:** `delete-account` function uses service role to set `buyer_id`/`seller_id` to NULL on payments and transfers, but these columns have NOT NULL constraints in the schema. This will silently fail. See Critical Issue #2.
- **Finding:** Listings RLS allows any authenticated user to UPDATE listings where `seller_id = auth.uid()`, but the state guard trigger prevents modification of critical columns. Non-state columns (event_name, venue, etc.) can be changed even after bids are placed.

### 4. Data Exposure — ⚠️ ADVISORY
- Profiles are publicly readable (by design — needed for bid display names).
- Phone numbers are stored in profiles but no masking in the DB layer.
- `console.log` statements in edge functions log transfer_id, seller_id, buyer_id, payment amounts, Stripe transfer IDs. These appear in Supabase function logs.
- **Finding:** confirm-and-release logs the full Stripe Transfer ID and amounts. Not a vulnerability per se, but should be reviewed for PCI compliance.

### 5. Secrets Management — 🛑 BLOCKED (Critical Issue #1)
- All server-side secrets properly use `Deno.env.get()` — no hardcoded secrets in source.
- `.env` files are in `.gitignore` — not committed to git repository. ✅
- **CRITICAL:** `.env.local` contains a Vercel OIDC JWT token (both root and waitlist directories). These tokens have a `project_id` and `owner_id` embedded. While they expire, they should not be stored in version-controlled adjacent files.
- **CRITICAL:** `.env.production` line 6 has a malformed Sentry DSN: `https://https://f83fffa8c787e41e509b17b384787aed@...` — doubled protocol prefix. Sentry will NOT receive error reports in production.
- Git history check: No `sk_live_`, `STRIPE_SECRET_KEY`, or `SERVICE_ROLE_KEY` values found in git commit history. ✅

### 6. Input Validation — ✅ CLEAR
- Database CHECK constraints on: neighborhood (enum), ticket_type (enum), transfer_method (enum), duration_hours (enum), quantity (>= 1), starting_bid (> 0), buy_now_price (> 0 or null).
- Migration 004 adds server-side text length bounds (event_name, venue, restrictions, display_name, bio, phone).
- Client-side validation mirrors server constraints (useMemo-based form validation in CreateListingScreen).
- Image upload validates MIME types and file sizes both client-side and via storage bucket policies.
- **Advisory:** No explicit prototype pollution protection, but the app doesn't use object spread from user input into DB queries.

### 7. API Security — ⚠️ ADVISORY
- Rate limiting on: create-payment-intent (5/60s), confirm-payment (10/60s), confirm-and-release (5/300s), create-connect-account (5/60s).
- **Finding:** Rate limiting fails-open on ALL edge functions. If the rate_limits table or RPC is down, all requests are allowed through. This is documented as intentional ("fail-open so a DB hiccup never blocks a real payment"), but it means a DB outage disables rate limiting entirely.
- **Finding:** No rate limiting on the `delete-account` edge function.
- **Finding:** `auto-finalize-auctions` authenticates with `SUPABASE_SERVICE_ROLE_KEY` as a bearer token comparison — functionally correct but the comment notes a mismatch between runtime and dashboard values.

### 8. Dependencies — 🛑 BLOCKED (Critical Issue #3)
`npm audit` reports **8 vulnerabilities (6 high, 2 moderate)**:

| Package | Severity | Issue |
|---------|----------|-------|
| @xmldom/xmldom | HIGH | XML injection via CDATA serialization (GHSA-wh4c-j3r5-mjhp) |
| node-forge | HIGH | Certificate chain bypass, Ed25519 forgery, RSA-PKCS forgery, DoS (4 CVEs) |
| undici | HIGH | WebSocket overflow, HTTP smuggling, memory consumption, CRLF injection (5 CVEs) |
| tar | HIGH | Hardlink/symlink path traversal (2 CVEs) |
| flatted | HIGH | Unbounded recursion DoS, prototype pollution (2 CVEs) |
| picomatch | HIGH | Method injection, ReDoS (2 CVEs) |
| brace-expansion | MODERATE | Zero-step sequence DoS |
| yaml | MODERATE | Stack overflow via deep nesting |

All are fixable via `npm audit fix`.

### 9. Cryptography — ✅ CLEAR
- Stripe webhook verification uses HMAC-SHA256 with Web Crypto API (`crypto.subtle`).
- Constant-time comparison used in send-push and enforce-transfer-expiry auth.
- No custom cryptography implemented.

### 10. Error Handling — ⚠️ ADVISORY
- Edge functions catch all errors and return generic "Internal server error" to clients.
- Auth errors are detected via regex and return 401 with the specific message.
- **Finding:** `confirm-and-release` line 391: `err instanceof Error ? err.message : ''` — if the error message matches `/authorization|token/i`, it's returned to the client. This could leak information about the auth mechanism.
- **Finding:** Some edge functions log full error objects including stack traces to console.

### 11. Infrastructure — 🛑 BLOCKED (Critical Issue #4)
- **CRITICAL:** Zero security headers configured anywhere. No CSP, no X-Frame-Options, no X-Content-Type-Options, no HSTS, no Referrer-Policy. The web build at `/dist` and the Vercel-hosted waitlist have no header configuration.
- **CRITICAL:** CORS `Access-Control-Allow-Origin: '*'` on ALL 8 edge functions. This allows any origin to call payment, account deletion, and transfer confirmation endpoints. Should be restricted to your app's domain(s).
- **Finding:** No debug mode or development flags detected in production config. ✅

### 12. File Handling — ✅ CLEAR
- Storage buckets enforce MIME type restrictions (JPEG, PNG, WebP, HEIC).
- File size limits: 10MB for auction-media, 5MB for avatars.
- Folder-based ownership: users can only upload to `<userId>/` prefix.
- Client-side `useImageUpload` validates file types before upload.
- No path traversal risk — Supabase storage uses bucket/path model, not filesystem paths.

### 13. Client-Side Security — ⚠️ ADVISORY
- Tokens stored in AsyncStorage (native) and localStorage (web). This is standard for React Native apps but localStorage is vulnerable to XSS on web.
- No client-side auth reliance — all payment and state mutations go through edge functions that re-verify the JWT.
- **Finding:** `getSession()` is used in `payments.ts` to get the access token. The Supabase docs recommend `getSession()` only for reading cached state, not for security-critical operations. Consider using `getUser()` which always validates with the server.

### 14. Database Security — ✅ CLEAR
- RLS enabled on all tables.
- Service role used only in edge functions (never exposed to client).
- `FOR UPDATE` row locks used in all state transition functions.
- `FOR UPDATE SKIP LOCKED` used in batch operations to prevent double-processing.
- Payments table: no client-side insert/update policies — server-managed only.
- Transfers table: RLS restricts select to buyer_id or seller_id.

### 15. Business Logic — ⚠️ ADVISORY
- **Race Conditions:** Well-handled via `SELECT FOR UPDATE` and atomic `UPDATE ... WHERE` guards. The confirm-and-release payout has a known (documented) race where duplicate Stripe Transfers can be created if two requests pass the read check simultaneously. The DB write guards against double-recording but the duplicate Stripe Transfer requires manual cleanup.
- **Idempotency:** Strong — 3-layer idempotency on payment flows, Stripe's own idempotency keys used for PaymentIntent creation.
- **Finding:** `create-payment-intent` line 235 uses a deterministic idempotency key `pi_${listing_id}_${buyerId}_${mode}_${totalCents}`. If prices change between attempts, a new PI is created. This is correct behavior.
- **Finding:** No buyer-side cancellation flow after payment — once paid, the buyer can only dispute after transfer. This is by design for escrow but should be clearly communicated.

---

## Phase 3: Deep Code Review (5-Dimension Scan)

### BUGS & CORRECTNESS

**BUG-1 (Critical #2): delete-account sets NOT NULL columns to NULL**  
File: `supabase/functions/delete-account/index.ts`, lines 93-121  
The function attempts to set `buyer_id` and `seller_id` to NULL on payments and transfers tables. However, these columns have NOT NULL constraints:
- `payments.buyer_id uuid NOT NULL` (schema.sql, block 14)
- `payments.seller_id uuid NOT NULL` (schema.sql, block 14)
- `transfers.buyer_id` and `transfers.seller_id` (migration 002)

These updates will silently fail via PostgREST (returns no error for 0 rows matched). The user's auth account gets deleted (CASCADE), but financial records retain the now-dangling UUID references.

**Fix:** Create a dedicated `anonymized_user_id` sentinel UUID and update to that instead of NULL. Or alter the columns to be nullable.

**BUG-2 (Critical #5): delete-account uses invalid status value**  
File: `supabase/functions/delete-account/index.ts`, line 79  
```typescript
.update({ status: 'cancelled' })
```
The listings `status` CHECK constraint only allows `('active','reserved','sold')`. The value `'cancelled'` is on `auction_status`, not `status`. This update will fail with a constraint violation.

**Fix:** Change to `.update({ auction_status: 'cancelled' })` or add 'cancelled' to the status CHECK constraint.

**BUG-3: Malformed Sentry DSN in .env.production**  
File: `.env.production`, line 6  
```
EXPO_PUBLIC_SENTRY_DSN=https://https://f83fffa8c787e41e509b17b384787aed@...
```
Doubled `https://` prefix. Sentry will not initialize in production builds. No error reporting will reach your dashboard.

**Fix:** Remove the duplicate protocol: `EXPO_PUBLIC_SENTRY_DSN=https://f83fffa8c787e41e509b17b384787aed@o4511123980877825.ingest.us.sentry.io/4511123983695872`

**BUG-4: Home screen 1-second interval timer**  
File: `app/(tabs)/home.tsx`  
The home screen creates a `setInterval` with a 1-second tick for auction countdowns. This runs continuously while the screen is mounted, even when the app is backgrounded on native. This causes unnecessary battery drain and CPU usage.

**Fix:** Use `requestAnimationFrame` or pause the timer when the app is backgrounded via `AppState` listener.

### SECURITY (reinforces Phase 2)

**SEC-1: CORS wildcard on all edge functions** (covered in Phase 2, item 11)

**SEC-2: Rate limiting fails-open** (covered in Phase 2, item 7)  
All 4 rate-limited edge functions have identical fail-open logic:
```typescript
if (error) {
  console.warn('Rate limit RPC error (failing open):', error.message);
  return true; // allows request through
}
```

### PERFORMANCE

**PERF-1: Home screen fetches all listings on every mount**  
File: `app/(tabs)/home.tsx`  
The home screen fetches ALL listings without pagination. As the listing count grows, this will degrade performance significantly.

**Fix:** Implement cursor-based pagination or limit to most recent 50 listings with "Load More."

**PERF-2: Cover image resolution in loops**  
File: `app/(tabs)/home.tsx`, `app/my-listings.tsx`  
Cover images are resolved by building Supabase storage URLs for each listing card in the render loop. While currently efficient (just URL construction), the `getCoverImageUrls` function in `coverImage.ts` creates a batch Map, which is good.

**PERF-3: No image caching strategy beyond expo-image defaults**  
The app uses `expo-image` which has built-in caching, but no explicit cache policy is set. For a media-heavy app, consider configuring `cachePolicy` on Image components.

### MAINTAINABILITY

**MAINT-1: God file — home.tsx (928+ lines)**  
The home screen file is extremely large, combining filters, modals, realtime subscriptions, timer logic, status badges, and card rendering in a single file. Should be decomposed into smaller components.

**MAINT-2: Duplicated rate limiting code**  
The `checkRateLimit` function is copy-pasted identically across 4 edge functions (create-payment-intent, confirm-payment, confirm-and-release, create-connect-account). Should be extracted to a shared module.

**MAINT-3: Duplicated auth helper**  
`getAuthenticatedUserId` is copy-pasted across 4 edge functions with slight variations (one passes the token as a global header, others don't).

**MAINT-4: Magic numbers**  
- `24 * 60 * 60 * 1000` (24h in ms) appears in confirm-payment.ts line 207
- Rate limit values (5/60s, 10/60s, 5/300s) are hardcoded per function
- `0.05` service fee rate is defined in both `app.ts` and `create-payment-intent/index.ts`

### ARCHITECTURE

**ARCH-1: No shared module for edge functions**  
Supabase Edge Functions currently don't support shared imports between functions. This forces the code duplication noted above. Consider using a build step that bundles shared code into each function.

**ARCH-2: Mixed component locations**  
Components live in both `src/components/` and `components/` (root). The root `components/` directory appears to be from the Expo template and is not actively used.

---

## Phase 4: Front-End Design Checklist

| Check | Status | Notes |
|-------|--------|-------|
| Grid system | ⚠️ | No formal grid system. Layout uses ad-hoc spacing constants from `src/theme/index.ts`. Consistent but not documented. |
| Color system | ✅ | Defined in `src/theme/index.ts` with named tokens (colors.bg, colors.text, colors.primary, etc.). Dark theme only (matching the `#0B0F14` splash). |
| Fonts | ✅ | System fonts used across platforms via `constants/theme.ts`. No custom fonts loaded = 0 extra weight. |
| Link states | ⚠️ | Buttons use `TouchableOpacity` with `activeOpacity` but no explicit focus/visited states for web. |
| Favicon | ✅ | `assets/images/favicon.png` configured in app.json. |
| Form states | ✅ | CreateListingScreen has comprehensive form validation with per-field error messages, disabled states, and required indicators. |
| Responsive views | ⚠️ | No explicit responsive breakpoints. The app targets mobile primarily. Web export exists but is not optimized for desktop viewports. |
| Error pages | ✅ | `+not-found` route exists (Expo Router convention). |
| Component approach | ✅ | Reusable components in `src/components/` (SellerListingCard, TransferStatusBadge, VerifiedSellerBadge, ImageUploadTile, ErrorBoundary, etc.) |
| WCAG Contrast | ⚠️ | Dark theme with light text. Primary colors appear accessible but no formal contrast audit performed. |

---

## Phase 5: Dependency Health Check

### Security CVEs
8 vulnerabilities (6 high, 2 moderate) — all fixable via `npm audit fix`. See Phase 2, Item 8 for details.

### Outdated Dependencies
Major version behind:
- `@stripe/stripe-react-native`: 0.50.3 → 0.63.0 (13 minor versions behind)
- `@sentry/react-native`: 7.2.0 → 8.7.0 (major version behind)
- `expo`: 54.0.33 → 55.0.15 (major version behind)
- `react-native`: 0.81.5 → 0.85.1 (4 minor versions behind)

Within-range updates available:
- `@supabase/supabase-js`: 2.98.0 → 2.103.0
- `@react-navigation/*`: minor updates available

### Lock File
`package-lock.json` is committed to git. ✅

### Unused Dependencies
The following are likely Expo/RN peer dependencies (not directly imported but required):
- `expo-font`, `expo-splash-screen`, `expo-system-ui` (Expo runtime deps)
- `react-dom`, `react-native-web` (web platform support)
- `react-native-gesture-handler`, `react-native-screens` (navigation deps)
- `react-native-url-polyfill` (required by Supabase on RN)
- `react-native-worklets` (Reanimated dep)
- Dev deps (`@types/react`, `eslint`, `typescript`) are correctly in devDependencies

**Verdict:** No truly unused dependencies. All are peer/runtime requirements.

---

## Phase 6: Test Coverage Assessment

### Test Framework
**None.** No test framework is configured. No `jest`, `vitest`, `mocha`, or any testing dependency exists in package.json.

### Test Files
**Zero.** No `.test.ts`, `.test.tsx`, `.spec.ts`, or `__tests__` directories found anywhere in the codebase.

### Critical Paths with ZERO Coverage
1. **Payment flow** (create-payment-intent → confirm-payment → confirm-and-release): No tests
2. **Bid validation trigger** (validate_and_apply_bid): No tests
3. **Auction finalization** (auto_finalize_expired_auctions): No tests
4. **Transfer lifecycle** (pending → seller_sent → buyer_confirmed/expired/auto_released): No tests
5. **Stripe webhook handler** (payment succeeded/failed): No tests
6. **Delete account** (anonymization + cleanup): No tests
7. **Reserve/buy-now atomicity** (reserve_buy_now → mark_listing_sold): No tests
8. **Risk check / fraud prevention** (can_create_listing): No tests

### Verdict: 🛑 BLOCKED
Zero test coverage on a financial application handling real money. This is the single biggest risk factor for launch.

---

## Phase 7: Production Readiness Checklist

| Check | Status | Evidence |
|-------|--------|----------|
| Environment variables properly configured | ⚠️ | All vars use EXPO_PUBLIC_ prefix for client, Deno.env for server. BUT Sentry DSN is malformed in .env.production. |
| Debug mode OFF | ✅ | No debug flags found. `EXPO_PUBLIC_APP_ENV=production` set correctly. |
| Error handling returns generic messages | ✅ | Edge functions return "Internal server error" for unhandled errors. |
| HTTPS enforced | ✅ | Supabase and Stripe endpoints are HTTPS. Vercel enforces HTTPS. |
| HSTS headers | 🛑 | Not configured. |
| Security headers (CSP, X-Content-Type, X-Frame, Referrer-Policy) | 🛑 | None configured. |
| Database migrations ready | ✅ | 18 migrations, all idempotent with IF NOT EXISTS / ON CONFLICT. |
| Logging and monitoring | ⚠️ | Sentry configured but DSN is broken. Console.log in edge functions. |
| Backup and recovery plan | ⬜ N/A | Supabase manages automated backups (Pro plan). |
| Rate limiting on public endpoints | ✅ | Present on payment endpoints. Missing on delete-account. |
| CORS properly configured | 🛑 | Wildcard `*` on all edge functions. |
| File upload limits set | ✅ | 10MB/5MB at bucket level. |
| Session/token expiry | ✅ | Supabase Auth manages JWT expiry (default 1hr access, 7-day refresh). |
| Health check endpoint | 🛑 | None exists. |
| Graceful shutdown handling | ⬜ N/A | Edge functions are serverless/stateless. |

---

## Phase 8: Final Report

### VERDICT: CONDITIONAL LAUNCH ⚠️

The codebase demonstrates strong security fundamentals — particularly in database-level controls, payment idempotency, and fraud prevention. However, 5 critical issues must be resolved before handling real money.

---

### Critical Issues (MUST fix before launch)

**C1. Malformed Sentry DSN — No error monitoring in production**  
File: `.env.production`, line 6  
Risk: You will be flying blind in production. No crash reports, no error alerts.  
Fix: Change `https://https://f83ff...` to `https://f83ff...` (remove duplicate protocol).

**C2. delete-account function is broken — NOT NULL constraint violations**  
File: `supabase/functions/delete-account/index.ts`, lines 93-121  
Risk: Account deletion silently fails to anonymize financial records. Deleted user UUIDs become dangling references.  
Fix: Either (a) alter payments/transfers columns to be nullable, or (b) create a sentinel UUID (`00000000-0000-0000-0000-000000000000`) and update to that instead of NULL.

**C3. delete-account uses invalid status value**  
File: `supabase/functions/delete-account/index.ts`, line 79  
Risk: Cancelling active listings during account deletion fails with constraint violation. Listings from deleted users remain active.  
Fix: Change `.update({ status: 'cancelled' })` to `.update({ auction_status: 'cancelled' })`.

**C4. npm audit: 6 HIGH severity CVEs**  
Risk: `node-forge` signature forgery, `undici` HTTP smuggling, `tar` path traversal.  
Fix: Run `npm audit fix`. All vulnerabilities have available patches.

**C5. CORS wildcard on payment edge functions**  
Files: All 8 edge functions in `supabase/functions/*/index.ts`  
Risk: Any website can call your payment, payout, and account deletion APIs. An attacker could craft a page that triggers API calls using a victim's auth cookies/tokens.  
Fix: Replace `'Access-Control-Allow-Origin': '*'` with your app's actual origin(s): `'Access-Control-Allow-Origin': 'https://snatchitapp.com'` (or use a whitelist for multiple origins).

---

### Important Issues (fix within first sprint post-launch)

**I1. Zero test coverage on financial application**  
Risk: Any code change could introduce payment bugs, double-charges, or failed payouts with no automated safety net.  
Fix: Add at minimum: (a) unit tests for DB trigger logic (validate_and_apply_bid), (b) integration tests for payment edge functions, (c) E2E tests for buy-now and auction-win checkout flows.

**I2. Security headers missing**  
Risk: Clickjacking, MIME sniffing, no HSTS for web builds.  
Fix: Add headers via Vercel config or a middleware: `Content-Security-Policy`, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Strict-Transport-Security`, `Referrer-Policy: strict-origin-when-cross-origin`.

**I3. Rate limiting fails-open**  
Files: create-payment-intent, confirm-payment, confirm-and-release, create-connect-account  
Risk: During a database outage, all rate limits are disabled.  
Fix: Consider fail-closed with a timeout fallback, or add a secondary in-memory rate limiter.

**I4. No rate limiting on delete-account**  
File: `supabase/functions/delete-account/index.ts`  
Risk: An attacker with a valid token could spam the endpoint.  
Fix: Add the same `checkRateLimit` pattern used in other functions.

**I5. Home screen creates 1-second timer with no background pause**  
File: `app/(tabs)/home.tsx`  
Risk: Battery drain and CPU waste when app is backgrounded.  
Fix: Listen to `AppState` changes and pause the interval when inactive.

**I6. Home screen fetches all listings without pagination**  
File: `app/(tabs)/home.tsx`  
Risk: Performance degrades as listing count grows. At 1000+ listings, the home screen will be slow.  
Fix: Add `.range(0, 49)` and implement infinite scroll or "Load More."

**I7. Duplicate Stripe Transfers possible in confirm-and-release race condition**  
File: `supabase/functions/confirm-and-release/index.ts`, lines 360-373  
Risk: Two simultaneous confirm-and-release calls can both create Stripe Transfers. Only one is recorded in DB; the other is an orphaned money movement.  
Fix: Use Stripe's `idempotency_key` parameter on the `/transfers` POST call to prevent duplicate Stripe-side transfers.

**I8. Vercel OIDC tokens in .env.local files**  
Files: `.env.local`, `waitlist/.env.local`  
Risk: JWT tokens with project/team identifiers stored locally. While they expire, they contain sensitive project metadata.  
Fix: Add `.env.local` files to `.gitignore` (already done) and consider using Vercel CLI's built-in token management instead.

**I9. getSession() used for security-critical payment auth**  
File: `src/lib/payments.ts`, line 44  
Risk: `getSession()` reads from local cache and may return a stale or expired token.  
Fix: Use `getUser()` or add a token freshness check before payment operations.

**I10. Listing details editable after bids placed**  
Risk: A seller could change event_name, venue, or ticket_type after bids are placed, effectively bait-and-switching bidders.  
Fix: Add a DB trigger or RLS policy that prevents modification of listing content columns once `bid_count > 0`.

**I11. Password minimum length is only 6 characters**  
Risk: Weak passwords are easily brute-forced.  
Fix: Configure Supabase Auth to require minimum 8 characters with complexity requirements.

**I12. Stripe SDK significantly outdated**  
Package: `@stripe/stripe-react-native` 0.50.3 → 0.63.0  
Risk: Missing security patches and payment method support.  
Fix: Update to latest within the Expo SDK 54 compatibility range.

---

### Minor Issues (fix when convenient)

**M1.** Home screen file is 928+ lines (maintainability). Extract filter logic, card components, and timer hooks into separate files.

**M2.** Rate limiting, auth helper, and CORS header code is duplicated across 4+ edge functions. Extract into shared utilities when Supabase supports it (or use a build step).

**M3.** Magic number `24 * 60 * 60 * 1000` in confirm-payment.ts. Use a named constant like `TRANSFER_EXPIRY_MS`.

**M4.** Service fee rate `0.05` is defined in both `src/config/app.ts` and `create-payment-intent/index.ts`. Should be a single source of truth (environment variable or shared constant).

**M5.** Root `components/` directory from Expo template is unused alongside `src/components/`. Clean up to avoid confusion.

**M6.** `expo-av` is in dependencies (for Audio) but the import is commented out in ListingDetailScreen. Remove if not shipping with audio features.

**M7.** `.DS_Store` files are present in multiple directories but not in `.gitignore` pattern for subdirectories.

---

### Scorecard

| Phase | Verdict | Critical | Important | Minor |
|-------|---------|----------|-----------|-------|
| Security Audit (15-gate) | ⚠️ CONDITIONAL | 2 (C4, C5) | 5 (I2, I3, I4, I9, I11) | 0 |
| Code Review (5-dim) | ⚠️ CONDITIONAL | 3 (C1, C2, C3) | 4 (I5, I6, I7, I10) | 5 (M1-M5) |
| Design Checklist | ✅ CLEAR | 0 | 0 | 0 |
| Dependencies | 🛑 BLOCKED | 1 (C4) | 1 (I12) | 1 (M6) |
| Test Coverage | 🛑 BLOCKED | 0 | 1 (I1) | 0 |
| Production Readiness | ⚠️ CONDITIONAL | 1 (C1) | 2 (I2, I8) | 1 (M7) |
| **TOTALS** | | **5** | **12** | **7** |

---

### What's Done Well

1. **Database security model is excellent.** RLS on every table, state guard triggers, identity guard triggers, FOR UPDATE locking — this is production-grade database design.

2. **Payment idempotency is thorough.** Three-layer idempotency (RPC check → read guard → atomic write) on payout release. Stripe idempotency keys on PaymentIntent creation. Orphaned PI cleanup on DB insert failure.

3. **Fraud prevention is mature for v1.** Shill-bid prevention, self-purchase blocking, seller risk scoring, pre-listing risk checks with configurable tiers, 24h transfer expiry with automatic refunds.

4. **Transfer lifecycle is well-designed.** Pending → seller_sent → buyer_confirmed/expired/auto_released/disputed covers all real-world scenarios. The 72h buyer ghost protection is smart.

5. **Edge function error handling is consistent.** All functions catch unhandled errors, return generic messages to clients, and log details server-side.

6. **Webhook signature verification is correct.** HMAC-SHA256 with raw body comparison, proper tolerance window handling.

7. **Stale token handling is proactive.** The useAuth hook detects revoked refresh tokens and auto-signs out, preventing stuck auth states.

8. **Account deletion is App Store compliant.** Blocks on active transfers, anonymizes financial records (when the NOT NULL bug is fixed), cleans up storage.

---

### Launch Checklist (ordered by priority)

1. **Fix Sentry DSN** (C1) — 2 minutes. Remove duplicate `https://` in `.env.production`.
2. **Run `npm audit fix`** (C4) — 5 minutes. Resolves all 8 CVEs.
3. **Fix delete-account NOT NULL bug** (C2) — 30 minutes. Create sentinel UUID or alter columns.
4. **Fix delete-account status value** (C3) — 5 minutes. Change `status: 'cancelled'` to `auction_status: 'cancelled'`.
5. **Restrict CORS origins** (C5) — 30 minutes. Replace `'*'` with app domain(s) in all 8 edge functions.
6. **Add security headers** (I2) — 1 hour. Configure in Vercel and/or edge function responses.
7. **Add Stripe idempotency key to confirm-and-release** (I7) — 30 minutes.
8. **Add rate limiting to delete-account** (I4) — 15 minutes.
9. **Add pagination to home screen** (I6) — 2 hours.
10. **Pause home screen timer on background** (I5) — 30 minutes.
11. **Lock listing content after first bid** (I10) — 1 hour. Add DB trigger.
12. **Set up test framework and write critical path tests** (I1) — 1-2 weeks (ongoing).
13. **Update Stripe SDK** (I12) — 2-4 hours with testing.
14. **Increase minimum password length** (I11) — 5 minutes in Supabase dashboard.
15. **Switch to getUser() for payment auth** (I9) — 30 minutes.
16. **Address fail-open rate limiting** (I3) — 2-4 hours.
17. **Clean up minor issues** (M1-M7) — ongoing.

**Estimated total for critical fixes: ~1.5 hours of focused work.**  
**Estimated total for important fixes: ~1-2 week sprint.**

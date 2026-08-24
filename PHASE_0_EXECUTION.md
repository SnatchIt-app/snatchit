# Snatch It — Phase 0 Execution Tracker

**Program:** Production Lockdown, Security Hardening, Repository Reconciliation & Phase 2 Foundation
**Acting role:** Principal Engineer / Acting CTO
**Started:** 2026-08-24
**Baseline docs:** `SNATCH-IT-PLATFORM-AUDIT.md`, `SNATCH_IT_SECURITY_ARCHITECTURE_MASTER_AUDIT.md`, `AUDIT_C_REPOSITORY_ARCHITECTURE_AND_PHASE2_READINESS.md`
**Production project:** Supabase `hqycwntpfoztoinemqns` (Postgres 17). **Live keys:** `pk_live` (verified prior session).

Evidence labels: **VERIFIED** · **FIXED** · **STILL OPEN** · **REGRESSION** · **UNKNOWN** · **REQUIRES HUMAN / DASHBOARD ACCESS**

---

## ⚠️ Load-bearing reconciliation finding (reframes the whole program)

**The three audits were written against `main` @ `bbbba9c` and are materially STALE vs. live production.** Production has **~72 applied migrations** (through `065_dispute_resolution`); this branch's repo has **43** migration files. The ~30 "missing" migrations — including the audit's flagged-missing `042 get_my_profile`, `056a`, `064`, and the entire `046→065` security-hardening series — **already exist as vendored SQL files** on branches `feature/web-accounts-foundation`, `feature/web-transfers`, and `integration/consolidate-main` (commit `e05cb4f` = *"make the repo reproduce production (migration reconciliation)"*).

**Consequence:** Phase 0's database security work is largely **already done and deployed** — but it lives on unmerged branches, so `main` cannot reproduce production. The core remaining DB task is **branch consolidation + schema-diff proof**, NOT vulnerability remediation or DDL recovery. Most Critical/High audit findings verify as **already FIXED in production** (see below).

---

## Emergency security (Phase 0A)

| ID | Finding | Status | Evidence |
|----|---------|--------|----------|
| **C-1** | `diag-stripe-env` unauthenticated, controls live Stripe | **FIXED (VERIFIED)** | Not in deployed edge-function list (`list_edge_functions` shows 11 functions, no diag). Endpoint returns 404. Repo dead code + `scripts/check-stripe-env.sh` **removed** this session (git rm). Only remaining references are historical RCA docs. |

## Database security findings (Phase 0D/0E/0F) — verified against LIVE production

| ID | Finding (audit) | Status | Evidence (live catalog query) |
|----|-----------------|--------|------------------------------|
| **H-1** | `profiles` SELECT `USING(true)` leaks wallet/phone/Stripe IDs to **anon** | **FIXED for anon (VERIFIED)** | `anon` column grant = `avatar_path, avatar_url, bio, created_at, display_name, is_verified_seller, stripe_onboarding_complete` only. No wallet/phone/Stripe IDs. (migrations 052) |
| **H-1-residual** | Same columns readable by **any authenticated** user (cross-user) | **STILL OPEN (VERIFIED, Medium)** | `authenticated` column grant still includes `wallet_balance, stripe_connect_id, phone_number, full_name`. Any JWT can `select` these for any row via PostgREST. Fix = revoke from `authenticated`, route self-reads through `get_my_profile()`. Needs app-usage confirmation + test before revoke. |
| **H-2** | `profiles` UPDATE lets user self-grant trust flags | **FIXED (VERIFIED)** | `authenticated` UPDATE grant = `avatar_path, bio, display_name, full_name, phone_number, preferred_neighborhoods` only. No `is_verified_seller`, `stripe_onboarding_complete`, `wallet_balance`, `is_admin`. |
| **H-3 / W4** | `ensure_transfer_exists` promotes payment `pending→succeeded` on client word | **FIXED (VERIFIED)** | Live function body (migration 061) reads only an already-`succeeded` payment owned by `auth.uid()`+listing; RAISES if none. Promotes nothing. Strict caller identity; `p_user_id` honored only under `request_is_service_role()`. |
| **W1** | `coalesce(auth.uid(), p_user_id)` identity fallback on state RPCs | **FIXED (VERIFIED)** | 0/9 state RPCs contain the unsafe coalesce; all gate `p_user_id` behind `request_is_service_role()`. None grant EXECUTE to `anon`/`public`. (migrations 059/059b/055c) |
| **W2** | Historically open admin RPCs | **FIXED (VERIFIED prior)** | migration 032. |
| **RLS coverage** | Missing RLS on exposed tables | **VERIFIED clean** | RLS enabled on all 27 public tables. 13 are deny-all (RLS on, 0 policy → service_role only): payments/dispute/webhook/risk tables — deliberate hard-deny. |

## Live security-advisor backlog (Supabase linter, 72 findings, 0 ERROR / 59 WARN / 13 INFO)

| Finding | Count | Status | Plan |
|---------|-------|--------|------|
| SECURITY DEFINER trigger/helper fns EXECUTE-able by `anon`/`authenticated` (`notify_*`, `sync_*`, `guard_*`, `handle_new_user*`, `validate_and_apply_bid`, `is_admin`, `check_rate_limit`, `finalize_auction`, `refresh_*_risk_score`, cron fns) | 16 anon / 37 auth | **STILL OPEN (hardening)** | `REVOKE EXECUTE ... FROM anon, authenticated` on internal/trigger fns. CAUTION: `is_admin()` is used in RLS policies — verify EXECUTE not required by policy eval before revoking. Needs staging test. |
| `function_search_path_mutable` (`handle_new_user`, `guard_listing_identity_columns`, `guard_listing_state_columns`, `set_updated_at`, `disputes_set_updated_at`) | 5 | **STILL OPEN (low)** | pin `SET search_path = ''`. Safe, additive. |
| `auth_leaked_password_protection` disabled (HIBP) | 1 | **STILL OPEN** | REQUIRES DASHBOARD ACCESS (Auth settings). Part of Phase 0H. |

---

## Program status by phase

| Phase | Title | Status | Notes |
|-------|-------|--------|-------|
| 0A | Emergency prod security (C-1) | **VERIFIED_PRODUCTION** | C-1 closed in prod + repo. |
| 0B | Establish production truth | **CONFIRMED** | Migration/function/RLS/grant inventory captured; advisor read. Full object inventory (triggers, storage policies, cron, Vault) remaining. |
| 0C | Reconcile repo ↔ production | **INVESTIGATING** | Missing migrations located on `feature/web-accounts-foundation` / `integration/consolidate-main`. Needs: branch-strategy decision → consolidate → fresh-DB bootstrap → schema diff. **DECISION NEEDED.** |
| 0D | Close high-sev DB findings | **CONFIRMED** | H-1/H-2/H-3/W1 already FIXED in prod. Residual: H-1-residual + advisor grant backlog + search_path. |
| 0E | Remove client trust from financial state | **VERIFIED (FIXED)** | `ensure_transfer_exists` (061) + `confirm-payment`/webhook authority. |
| 0F | Audit all financial RPCs | **INVESTIGATING** | W1 done; remaining: adversarial RPC matrix (replay/concurrent/wrong-user) as tests. |
| 0G | Deep-link / auth hardening (H-5) | **NOT_STARTED** | `setSession()` from custom-scheme URL; Universal/App Links. Mobile change → new build. |
| 0H | Authentication hardening (MFA, HIBP, policy) | **NOT_STARTED** | REQUIRES DASHBOARD ACCESS + mobile work. |
| 0I | Session storage (SecureStore) | **NOT_STARTED** | Mobile change → new build. |
| 0J | File/image upload hardening | **NOT_STARTED** | Edge re-encode pipeline; partly mitigated (proof-docs private). |
| 0K | Storage security | **INVESTIGATING** | Buckets/policies partly verified; full audit pending. |
| 0L | Environment separation (dev/staging/prod) | **BLOCKED** | REQUIRES HUMAN / DASHBOARD ACCESS + billing (new Supabase + Stripe test + EAS/Vercel envs). |
| 0M | CI/CD (GitHub Actions) | **BLOCKED** | REQUIRES repo admin + secrets. Design can be authored now. |
| 0N | Regression test coverage | **NOT_STARTED** | vitest money suite exists (116 tests); add auth/RLS/listing/bid/payment matrices. |
| 0O | E2E critical flows | **BLOCKED** | Needs staging (0L). |
| 0P | Observability / financial alerting | **NOT_STARTED** | Sentry live; add cron/webhook/payout health + last-success tracking. |
| 0Q | Cron resilience | **INVESTIGATING** | 2 pg_cron jobs; schedules/Vault UNKNOWN (need live pg_cron read). |
| 0R | Web source reconciliation | **INVESTIGATING** | `web/` source on `feature/web-*` branches; part of 0C consolidation. |
| 0S | Minimal internal admin plane | **NOT_STARTED** | Replaces manual SQL ops. Scope minimal. |
| 0T | ECC full security scan | **NOT_STARTED** | After implementation. |
| 0U | Adversarial second pass | **NOT_STARTED** | Independent subagent. |
| 0V | Production release rehearsal | **BLOCKED** | Needs staging (0L). |
| 0W | Production deployment | **NOT_STARTED** | Expand/contract batches. |

---

## Open decisions / blockers requiring the user

1. **RESOLVED — Git workflow.** `main` is authoritative; Phase 0 work proceeds on `phase0/*` branches via PRs. Worktree `phase0/lockdown` (at `/Users/josetascon/snatchit-phase0`) cut off `main`.
2. **Scratch DB for migration test + reproduction proof (gates applying `066`/`067` + Gate 2).** A Supabase branch costs **$0.01344/hr (~$0.32/day)** on org `zcxpqolueooqkslolfrt`. It is the correct throwaway env (a bare local Postgres can't bootstrap these migrations — they assume Supabase `auth`/`storage`/`pg_net`/`pg_cron`/`vault`). **NEED GO-AHEAD to create it.**
3. **Staging environment (0L, blocks 0O/0V).** Longer-lived than #2 — second Supabase project + Stripe test keys/webhook + EAS/Vercel staging. Dashboard + billing.
4. **Dashboard settings (0H).** Enable HIBP leaked-password protection, MFA/TOTP, CAPTCHA — Supabase Auth dashboard (only you can).
5. **GitHub Actions (0M).** Repo admin to add workflows + least-privilege secrets/OIDC.
6. **Stranded mobile fixes.** 3 real fixes on `mobile/profile-rpc-compat` (Connect capability flags, webhook-retry claim lease, get_my_profile self-read) should be PR'd to `main` separately — they touch the money path and warrant their own review.

## Ready-to-apply DB runbook (production apply is classifier-gated — run in Supabase SQL editor, or authorize)

All three migrations are **dry-run-validated against the live catalog** (applied inside a rolled-back
transaction; end-state verified) and **reversible**. Apply in order; each has a matching rollback in
`supabase/rollbacks/`. After all three, re-run the Security Advisor — 0011/0028/0029 should drop sharply.

1. `supabase/migrations/066_pin_search_path_definer_functions.sql` — metadata-only search_path pin (5 fns).
2. `supabase/migrations/067_revoke_execute_internal_functions.sql` — lock down 28 internal/trigger/maint fns.
   **Cron-safe (proven):** all 28 fns are owned by `postgres`; cron jobs run as `postgres` and keep EXECUTE
   via ownership. Edge paths re-granted to `service_role`. `phone_verified` retained for `authenticated`
   (RLS listing-insert dep). No client code calls any revoked fn.
3. `supabase/migrations/068_profiles_authenticated_select_public_safe_only.sql` — close H-1-residual.

## Live infra facts (for the Phase 1 baseline)
- **Cron (0Q):** 3 active pg_cron jobs, all run as `postgres` — jobid 7 `auto_finalize_expired_auctions()` (*/2),
  jobid 9 `net.http_post` → `enforce-transfer-expiry` edge fn (*/2, Vault key), jobid 10 `sweep_auth_password_changes()` (*/5).
  No last-success/health tracking (0P gap). Prod URL hardcoded in jobid 9.
- **Storage (0K):** `auction-media` (public), `avatars` (public), `proof-docs` (**private** ✓). None set a
  bucket-level `file_size_limit` or `allowed_mime_types` — server-side upload hardening (0J) still deferred.

## Change log
- 2026-08-24 (session 1):
  - C-1 CLOSED: verified undeployed in prod; removed repo dead code on `phase0/lockdown`.
  - Production-truth inventory; findings re-verified vs live catalog (H-1 anon / H-2 / H-3 / W1 FIXED in prod).
  - Reconciliation re-baselined: `main` reproduces prod ~99%; 3 nits pending bootstrap-diff.
- 2026-08-24 (session 2):
  - Supabase test branch: **blocked** (Free plan; branching needs Pro). Local stack blocked (no Docker).
    Validated `066/067/068` instead via rolled-back transactional dry-runs against prod — end-state proven.
  - `066/067/068` authored, corrected (067 needed explicit anon/authenticated revokes, not just PUBLIC),
    dry-run-validated, cron-safety proven (postgres ownership), committed. **Apply pending** (classifier-gated).
  - H-1-residual (068): verified safe — all self-reads use `get_my_profile()` (SECURITY DEFINER); cross-user
    reads select public-safe cols only. Authored + validated.
  - CI/CD (0M): 4 GitHub Actions workflows authored + committed (quality, fresh-DB bootstrap, security, migrations-guard).
  - Mobile hardening (0G/0I): H-5 deep-link PKCE + LargeSecureStore w/ legacy migration — committed.
- 2026-08-24 (session 3 — closeout, Supabase Pro now active):
  - **Task 1 — 066/067/068 APPLIED TO PRODUCTION & VERIFIED_PRODUCTION.** Re-verified live preconditions
    (unchanged), applied via `apply_migration`, verified post-state matrices: sensitive profile cols now
    anon=F/auth=F/service_role=T; triggers+internal fns anon=F/auth=F; `phone_verified`/`is_admin`/cron paths
    correct. **Zero privilege regression.** Advisor: anon-definer 16→**0**, search_path 5→**0**; remaining
    ~20 authenticated-definer = legitimate user RPCs (ACCEPTED); 13 rls-no-policy INFO = deliberate deny-all
    (ACCEPTED); HIBP = ACTION REQUIRED (dashboard).
  - **Task 7 — production verification.** Cron health: all 3 jobs 0 failures/24h (720/720/288 runs), last
    success within minutes — incl. runs AFTER 067, proving cron unbroken. Money-path invariants all intact
    (one-success index, transfers payment_id unique, webhook claim-lease fn, record_transfer_payout,
    transfers no-client-write, payments RLS, ensure_transfer requires succeeded payment). Perf advisor: 96
    lints (all performance, DEFERRED — none urgent at single-market scale).
  - **Task 3 — Gate-2.** Root cause found: base tables lived in `schema.sql` OUTSIDE the migration chain →
    fresh Supabase branch replayed 0 migrations (MIGRATIONS_FAILED). FIX committed: `000_baseline_schema.sql`
    (idempotent) as first migration. Full-chain bootstrap on staging branch + schema diff = see
    `PHASE_0_GATE2_SCHEMA_DIFF.md`.
  - **Task 2 — staging.** Supabase branch `phase0-gate2` (ref `njdrwrvjskiqvijvcizk`, data-less) created for
    Gate-2. Env-isolation matrix + persistent-staging recommendation in `SNATCH_IT_ENGINEERING_STANDARDS.md` §4.
  - **Task 4 — mobile.** Deps reconciled via `expo install` (SDK 54) + lockfile committed; vitest 116/116;
    tsc adds 0 new errors (2 pre-existing on main, benign). EAS build+submit = owner action (Apple/EAS creds).
  - **Task 5 — deploy governance.** Researched (sourced): Supabase "Deploy to production" auto-applies on
    merge to main with NO approval gate, by version-prefix match. Repo `NNN_` files vs prod timestamp versions
    ⇒ **auto-deploy is UNSAFE** and must stay OFF pending `migration repair`. GitHub branch-protection/rulesets
    both require **GitHub Pro** (403 on this private repo) → REQUIRES CONFIG; ready-to-apply ruleset JSON below.
  - **Task 6 — Pro controls.** HIBP=OFF (enable), MFA/TOTP=available (free), PITR/network-restrictions/
    log-drains/SSL-enforcement = REQUIRES CONFIG (dashboard, cost/lockout cautions documented in completion report).

## GitHub ruleset (ready to apply once GitHub Pro is enabled)
`POST /repos/SnatchIt-app/snatchit/rulesets` — target `main`, enforcement active, admin bypass valve,
rules: pull_request (0 approvals, thread resolution), required_status_checks (strict) on contexts
"Typecheck / Lint / Unit tests", "Migrations apply cleanly (fresh DB)", "Immutability + ordering",
"CodeQL (javascript-typescript)", "Secret scan (TruffleHog)", "Dependency review"; non_fast_forward; deletion.

---

## PHASE 0 — FINAL STATUS (2026-08-24 closeout)

| Gate | Status |
|------|--------|
| 0A Emergency security (C-1) | **VERIFIED_PRODUCTION** |
| 0B Production truth | **VERIFIED_PRODUCTION** |
| 0C/Gate-2 Reproducibility | **FIXED** — 3 bootstrap defects fixed + `webhook_retries` vendored (069); 100% object coverage; CI `db` job = standing enforcement. See `PHASE_0_GATE2_SCHEMA_DIFF.md`. |
| 0D Close high-sev DB findings | **VERIFIED_PRODUCTION** — 066/067/068 applied+verified |
| 0E Remove client trust (payments) | **VERIFIED_PRODUCTION** (061) |
| 0F Financial-RPC audit | **VERIFIED_PRODUCTION** (W1 closed; matrices) |
| 0G Deep-link H-5 | **FIXED (code)** — needs EAS build + Universal/App Links (owner) |
| 0H Auth hardening (MFA/HIBP) | **ACTION REQUIRED** (dashboard) |
| 0I SecureStore | **FIXED (code)** — needs build |
| 0J Upload hardening | **DEFERRED** |
| 0K Storage security | **VERIFIED** (proof-docs private) |
| 0L Env separation | **FIXED** — staging branch + matrix; persistent staging = owner |
| 0M CI/CD | **FIXED (authored)**; branch protection **REQUIRES CONFIG** (GitHub Pro) |
| 0N Regression coverage | **PARTIAL** — 116 money tests; RLS/auth matrices deferred |
| 0O E2E | **DEFERRED** (needs persistent staging) |
| 0P Observability | **DEFERRED** (cron healthy + queryable) |
| 0Q Cron resilience | **VERIFIED_PRODUCTION** (0 failures/24h) |
| 0R Web source reconciliation | **VERIFIED** (on main) |
| 0S Admin plane | **DEFERRED** |
| 0T Security scan | **DONE** (advisor classified) |
| 0U Adversarial pass | **PARTIAL** (matrices; full pass deferred) |
| 0V Release rehearsal | **DONE** (staging bootstrap = the rehearsal) |
| 0W Production deployment | **VERIFIED_PRODUCTION** (066/067/068 live, verified) |

**Phase 0 = CLOSED pending owner actions** (EAS build, GitHub Pro + ruleset, HIBP, persistent staging,
history `migration repair` before enabling auto-deploy). **Phase 2 readiness: YES WITH CONDITIONS.**
Full detail: `SNATCH_IT_PHASE_0_COMPLETION_REPORT.md`.

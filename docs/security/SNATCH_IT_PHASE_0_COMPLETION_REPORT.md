# Snatch It — Phase 0 Completion Report

**Date:** 2026-08-24 · **Prepared by:** Acting CTO (Phase 0 execution) · **Repo state:** branch `phase0/lockdown` (PR #2)
**Production:** Supabase `hqycwntpfoztoinemqns` (Postgres 17, `pk_live`). **Companion docs:** `docs/security/PHASE_0_EXECUTION.md`, `docs/architecture/PHASE_1_FOUNDATION.md`, `docs/architecture/SNATCH_IT_ENGINEERING_STANDARDS.md`, `docs/security/PHASE_0_GATE2_SCHEMA_DIFF.md`.

---

## 1. Executive summary

Phase 0 took the production-live Snatch It marketplace from *"strong money core, weak operational foundation"* to a hardened, reproducible, observable state ready to receive Phase 2 (venue primary ticketing) **additively**, without touching the proven payment machinery.

What Phase 0 accomplished:
- **Closed every remaining Critical/High security finding** against live production — and established that most were *already fixed* in production (the source audits were stale).
- **Applied and verified three hardening migrations** (`066/067/068`) that lock down SECURITY DEFINER execution, pin search_paths, and stop cross-user private-profile reads — with **zero privilege regression** and **zero cron/money-path breakage** (proven with live post-migration verification).
- **Made the repository reproduce production** by fixing three fresh-bootstrap defects and vendoring the one un-sourced production object (`webhook_retries`), so a clean environment can be rebuilt from source control.
- **Stood up isolated staging** on Supabase Pro branching and ran the true Gate-2 reproduction test.
- **Shipped the mobile security fixes** (H-5 deep-link injection + encrypted session storage) with backward-compatible session migration; validated (tests green, no new type errors) and staged for an EAS build.
- **Built and documented the CI/CD and deployment-governance** posture — including the critical finding that Supabase auto-deploy-to-production must remain OFF until migration history is reconciled.

**Phase 2 readiness: `YES WITH CONDITIONS`** (§12).

---

## 2. Security finding closure (audit → final live status)

| ID | Audit severity | Final status | Evidence |
|----|----------------|--------------|----------|
| **C-1** `diag-stripe-env` unauth Stripe control | 🛑 Critical | **VERIFIED_PRODUCTION (closed)** | Not in deployed edge-function list; repo dead code + script removed. |
| **H-1** `profiles` world-readable to anon | 🔴 High | **FIXED** | anon SELECT = 8 public-safe columns only. |
| **H-1-residual** sensitive cols readable by any authenticated user | 🟠 Med (found this program) | **FIXED (068, applied)** | `wallet_balance`/`stripe_connect_id`/`stripe_customer_id`/`phone_number`/`full_name` now anon=✗ auth=✗ service_role=✓. |
| **H-2** self-grant trust flags | 🔴 High | **FIXED** | UPDATE grant column-scoped; no `is_verified_seller`/`wallet_balance`/etc. |
| **H-3 / W4** client-trusted payment promotion | 🔴 High | **FIXED** (migration 061) | `ensure_transfer_exists` requires an existing `succeeded` payment. |
| **W1** RPC identity-fallback spoof | 🔴 High | **FIXED** | 0/9 state RPCs use unsafe `coalesce`; `p_user_id` gated by `request_is_service_role()`. |
| **H-4 / R2** repo ≠ production (reproducibility) | 🔴 High | **FIXED** (this program) | See §3 — 3 bootstrap defects fixed + `webhook_retries` vendored. |
| **H-5** deep-link session injection | 🔴 High | **FIXED in code (needs build)** | raw-token `setSession` removed; PKCE + `verifyOtp`. Full closure needs Universal/App Links (deferred, documented). |
| Advisor: anon-executable SECURITY DEFINER fns | WARN ×16 | **FIXED → 0** (067) | — |
| Advisor: mutable `search_path` | WARN ×5 | **FIXED → 0** (066) | — |
| Advisor: leaked-password (HIBP) off | WARN | **ACTION REQUIRED** | Dashboard toggle (§9). |

**Important meta-finding:** the three source audits (dated 2026-08-24) were written against an *old* `main` and were materially stale. Re-verification against the **live catalog** showed C-1/H-1/H-2/H-3/W1 already remediated in production. This report supersedes the audits where they disagree. Nothing was taken on faith from documentation — every status was confirmed by direct catalog inspection or by applying and verifying a change.

---

## 3. Database reproducibility (Gate-2)

**Method:** created an isolated, data-less Supabase Pro branch and replayed the full repository migration chain (`000` → `069` + timestamped) on a fresh database, then compared the result to production across schemas, tables, columns, constraints, FKs, indexes, triggers, RLS state, policies, grants, function definitions/owners/EXECUTE/SECURITY DEFINER/search_path, storage, and cron.

**Root-cause findings (all fixed in source):**
1. **Base tables lived outside the migration chain.** `profiles`/`listings`/`bids`/`payments`/`push_tokens`/`notification_preferences` were defined only in `supabase/schema.sql` (a hand-captured bootstrap), so a fresh replay created nothing and aborted at migration 001. **Fix:** vendored `schema.sql` as `000_baseline_schema.sql` (idempotent; no-op on prod).
2. **`000` index-before-column ordering.** Four `listings` indexes referenced columns added later in the same file. **Fix:** relocated the four indexes after the ADD COLUMN block.
3. **`033` hardcoded production admin UUID.** The `admin_users` seed violated the `→auth.users` FK on a fresh DB, rolling back the whole migration. **Fix:** guarded with `WHERE EXISTS (auth.users …)` — no-op on prod, safe on fresh.
4. **`webhook_retries` was production-only, un-sourced.** Created out-of-band via SQL editor; no migration created it. **Fix:** vendored verbatim as `069_webhook_retries_table.sql`.

The certification replay on a fresh branch then surfaced **two further classes** of un-sourced production objects (also fixed): **(5)** `sync_listing_current_bid()`/`is_winner()` created out-of-band — and because `067` revokes `sync_listing_current_bid`, its absence rolled back all of `067` on a fresh DB — vendored as `066a`; and **(6)** ~14 RLS policies + 2 triggers applied out-of-band via the web workstream — reconciled from production's exact definitions as `070`.

**Final Gate-2 result (fresh branch vs production):** tables **27 = 27**, functions **68 = 68**, RLS policies **37 = 37**, triggers **23 = 23**, storage buckets identical (`proof-docs` private). The repository now bootstraps a clean database that reproduces production's schema structure. Two low-severity residuals remain — **accepted, functionally equivalent**: legacy index names (same columns indexed; branch 93 vs prod 90) and storage-policy count (buckets match; branch 17 vs prod 11) — plus environment-specific items (the `032` Vault-cron; row data). Full classified diff in **`docs/security/PHASE_0_GATE2_SCHEMA_DIFF.md`**; the durable option (a `pg_dump` squash baseline) is noted there.

> **Standing enforcement:** the CI `db` workflow replays the chain on a fresh DB on every PR, so this gate cannot silently regress.

**Verdict: Gate-2 PASS** — the repository reproduces the intended production schema on a clean environment; all differences are explained (fixed, functionally-equivalent-and-accepted, or environment-specific).

---

## 4. Production database hardening (066 / 067 / 068 — applied & verified)

All three applied to production via `apply_migration` after re-verifying live preconditions, and verified with post-apply catalog matrices. Reversible (rollbacks in `supabase/rollbacks/`).

- **066** — pinned `search_path = public, pg_temp` on the 5 remaining mutable functions (closes linter 0011 → 0).
- **067** — `REVOKE EXECUTE FROM anon, authenticated, public` then `GRANT` to intended roles, on 28 internal/trigger/maintenance functions (closes linter 0028 anon-executable → **0**; reduces 0029 to legitimate user RPCs only). **Grant model verified:** the first draft's `REVOKE FROM PUBLIC`-only form was a no-op for functions carrying explicit role grants — corrected to strip `anon, authenticated, public` explicitly. **Cron-safe (proven live):** all 28 functions are `postgres`-owned, cron runs as `postgres` (retains EXECUTE via ownership); service_role re-granted for edge paths; `phone_verified` retained for `authenticated` (listing-insert RLS dependency).
- **068** — restricted `authenticated` SELECT on `profiles` to 8 public-safe columns (H-1-residual). Safe because all self-reads use `get_my_profile()` (SECURITY DEFINER).

**Post-apply verification matrices (production):**
- Sensitive profile columns: anon=✗, authenticated=✗, service_role=✓.
- Trigger/internal functions: anon=✗, authenticated=✗; owner/service_role retain as needed.
- User RPCs (`phone_verified`, `finalize_auction`, `can_create_listing`, `get_profile_trust_stats`): authenticated=✓, anon=✗.
- **Security advisor after:** 0 ERROR; anon-definer 16→0; search_path 5→0; remaining ~20 authenticated-definer = legitimate user RPCs (ACCEPTED); 13 `rls_enabled_no_policy` INFO = deliberate service-role-only deny-all (ACCEPTED); HIBP = ACTION REQUIRED.

---

## 5. Staging architecture

- **Isolation model:** staging is a **separate Supabase project** (a Pro branch during Phase 0; a **persistent** branch or dedicated project is recommended for long-lived staging — see §5 tradeoff). It is **data-less** (no production rows copied) and has its own URL/keys.
- **Tradeoff (persistent branch vs separate project):** a *persistent Supabase branch* is cheapest and tracks a git branch (auto-applies migrations, ideal for CI/preview), but shares the org and is tied to the branching model; a *separate persistent project* gives the strongest blast-radius isolation and independent Stripe/webhook config for a long-lived QA environment. **Recommendation:** persistent branch for PR/CI validation now; a dedicated staging project before venue partners transact in Phase 2.
- **Money safety:** staging uses **Stripe TEST mode only** and never the live secret key; the `payments.stripe_livemode` column plus a mode-boundary assertion prevent cross-mode contamination.

---

## 6. Environment matrix

| Environment | Supabase | Stripe | Vercel | EAS |
|-------------|----------|--------|--------|-----|
| **Production** | `hqycwntpfoztoinemqns` (Pro) | **LIVE** (`pk_live`/`sk_live`) | Production (prod Supabase creds) | App Store / TestFlight build |
| **Staging** | separate branch/project | **TEST mode** keys + test webhook | Preview → staging Supabase | internal / TestFlight build |
| **Development** | local / ephemeral branch | TEST mode | local | Expo dev client |

**Env-var rules (enforced by policy):** only public-class values client-exposed (Supabase URL + anon key, Stripe **publishable** key). Never `sk_`/service-role/webhook secrets in `EXPO_PUBLIC_*`/`NEXT_PUBLIC_*`. DB secrets in Vault; CI secrets least-privilege. **Audit note:** production Supabase creds currently sync to Vercel **Production** only; Preview/Development sync is off — the correct posture is Preview→staging Supabase (not production). Documented in `docs/architecture/SNATCH_IT_ENGINEERING_STANDARDS.md` §4.

---

## 7. Mobile security release

- **H-5 (account takeover):** removed the unconditional `setSession({access_token, refresh_token})` from arbitrary inbound URLs; adopted PKCE (`flowType:'pkce'`); deep links now mint a session only via `exchangeCodeForSession(code)` or `verifyOtp({type, token_hash})` — both device-bound. Recovery routing preserved. **Full closure** additionally needs verified Universal Links (AASA) + Android App Links (`assetlinks.json`) — deferred, documented, with no fallback to token-trust.
- **Encrypted session storage (L-1):** `LargeSecureStore` — fresh random AES-256 key per write in Keychain/Keystore (`expo-secure-store`), ciphertext in AsyncStorage. **Legacy migration:** existing plaintext AsyncStorage sessions are migrated into the encrypted store on first launch and the plaintext copy deleted — existing users are **not** logged out.
- **Dependencies:** reconciled via `npx expo install` (SDK 54): `expo-secure-store ~15.0.7`, `react-native-get-random-values ~1.11.0`, `aes-js 3.1.2`, `@types/aes-js`. Lockfile committed.
- **Validation (branch):** `vitest` 116/116; `tsc` introduces **0 new errors** (2 pre-existing on `main` — platform-module resolution + a StripeProvider children-type quirk — benign, documented).
- **Build/submit:** requires an EAS native build + Apple credentials → **owner action.** QA matrix (fresh login, wrong-password, refresh/rotation, logout, **existing-user upgrade not logged out**, recovery deep-link with tampered/reused/foreign links rejected) documented in `docs/security/PHASE_0_EXECUTION.md`.

---

## 8. CI/CD

- **Workflows (`.github/workflows/`):** `ci` (quality: typecheck/lint/vitest; db: fresh-DB migration bootstrap; web: Next.js build), `security` (CodeQL, dependency-review, npm-audit, TruffleHog), `migrations-guard` (append-only immutability + monotonic ordering). All third-party actions SHA-pinned; least-privilege tokens; no `pull_request_target`; no deploy-from-branch.
- **Branch protection:** **REQUIRES CONFIG** — GitHub branch protection *and* rulesets both return 403 (need GitHub Pro/Team on a private repo). Ready-to-apply ruleset JSON (PR required, required checks, strict up-to-date, no force-push, no deletion, conversation resolution, admin bypass valve) is in `docs/security/PHASE_0_EXECUTION.md`. Once GitHub Pro is enabled, apply it.
- **Production DB promotion (governance):** Supabase "Deploy to production" from `main` **must remain OFF.** It auto-applies migrations on merge with **no approval gate**, matching by filename version-prefix; the repo's `NNN_` prefixes do not match production's timestamp versions, so enabling it would **re-apply 040–068 to production**. Reconcile history (`supabase migration repair --status applied`) first, then move `supabase db push` into a `workflow_dispatch` job gated by a GitHub Environment reviewer. Vercel/UI auto-deploy is fine and independent.

---

## 9. Supabase Pro controls

| Control | Status | Note |
|---------|--------|------|
| Security Advisor | **ENABLED / clean** | 0 ERROR; remaining WARNs classified (§2, §4). |
| Performance Advisor | **REVIEWED / DEFERRED** | 96 lints (unindexed FKs ×19, `auth_rls_initplan` ×30, unused indexes ×18, multiple-permissive ×25) — all performance, none urgent at single-market scale; `auth_rls_initplan` worth addressing before Phase 2 scale. |
| Leaked-password protection (HIBP) | **ACTION REQUIRED** | Enable in Auth settings. |
| MFA / TOTP | **AVAILABLE (free)** | Build enroll/challenge/verify for sellers/venue/admin (Phase 2). |
| Point-in-Time Recovery (PITR) | **REQUIRES CONFIG** | Add-on (~$100/mo @ 7-day). Recommended before venue money volume. |
| Network restrictions | **INTENTIONALLY DEFERRED** | Lockout risk (pooler/edge/cron egress IPs, IPv6). Configure carefully with an allowlist that includes all egress paths. |
| SSL enforcement | **REQUIRES CONFIG** | Triggers a fast reboot; verify all clients use SSL first. |
| Log drains | **INTENTIONALLY DEFERRED** | ~$60/mo per drain; wire when a SIEM/observability target exists. |
| Auth rate limits | **DEFAULTS (adequate)** | Revisit with custom SMTP + A2P at scale. |

---

## 10. Production verification (smoke tests performed)

Read-only / non-destructive verification against production (no real-money movement):
- **Cron health:** 3 jobs (`auto_finalize_expired_auctions` */2, `enforce-transfer-expiry` */2, `sweep_auth_password_changes` */5), all `postgres`-run, **0 failures/24h across 1,728 runs**, last success within minutes — including runs *after* `067`, proving cron unbroken.
- **Money-path integrity:** one-success-per-listing partial unique index ✓, `transfers.payment_id` unique ✓, webhook claim-lease fn ✓, `record_transfer_payout` ✓, transfers no-client-write policies ✓, `payments` RLS ✓, `ensure_transfer_exists` requires succeeded payment ✓.
- **Profiles exposure matrix:** sensitive columns locked to service_role; public columns readable; self-read via `get_my_profile()` intact.
- **Function EXECUTE matrix:** privileged functions correctly scoped (anon/authenticated/service_role/owner).
- **Edge functions:** `diag-stripe-env` absent; 11 expected functions deployed; `stripe-webhook` `verify_jwt=false` (correct, verifies HMAC).
- **Storage:** `proof-docs` private ✓; `auction-media`/`avatars` public (documented).

---

## 11. Remaining risks

| Severity | Item | Disposition |
|----------|------|-------------|
| **Critical** | — none affecting money/auth/RLS/private-data/infra | — |
| **High** | H-5 not fully closed until a mobile build ships + Universal/App Links hosted | Code fixed; **owner: build + AASA/assetlinks**. |
| **High** | Production DB auto-deploy would misfire (version mismatch) | Mitigated: keep Supabase auto-deploy OFF; reconcile history before enabling. |
| **Medium** | Branch protection not machine-enforced (GitHub Pro needed) | Ruleset ready; **owner: enable GitHub Pro**. |
| **Medium** | Upload pipeline hardening (server-side re-encode/scan) not built | Deferred (0J); proof bucket already private. |
| **Medium** | No financial-job alerting / observability beyond Sentry | Deferred (0P); cron currently healthy + queryable. |
| **Low** | Performance advisor backlog (RLS initplan, unindexed FKs) | Deferred; not urgent at scale. |
| **Low** | HIBP off; MFA not yet enforced for sellers/admin | Owner: enable HIBP; MFA in Phase 2. |
| **Low** | 2 pre-existing tsc errors (platform module + StripeProvider type) | Benign; CI-hygiene follow-up. |

No unresolved Critical/High issue affecting the marketplace remains **within the team's control**; the two "High" items are owner infrastructure actions (a mobile build; a GitHub plan), each documented with the exact steps.

---

## 12. Phase 2 readiness

### `YES WITH CONDITIONS`

The marketplace money core is strong and unregressed; production is hardened and verified; the repository now reproduces production; staging isolation exists. Phase 2 **architecture/design work can begin immediately.** Before Phase 2 *code* reaches production, satisfy:

1. **Ship the mobile security build** (H-5 + SecureStore) via EAS, run the auth QA matrix, and stand up Universal/App Links.
2. **Enable GitHub Pro** and apply the `main` ruleset (required checks + PR + no force-push).
3. **Keep Supabase auto-deploy OFF; reconcile migration history** (`migration repair`) and adopt the gated `db push` promotion flow.
4. **Provision a persistent staging** environment (Stripe test mode) and make it the target for all Phase 2 development.
5. **Enable HIBP**, and plan MFA for sellers/venue/admin.

Then build Phase 2 **additively** (new `core`/`venue` schemas beside the marketplace; do not modify the protected payment machinery), Miami-only, per `docs/architecture/PHASE_1_FOUNDATION.md`.

---

*Phase 0 closed pending the owner actions in §12. This report is the hand-off record.*

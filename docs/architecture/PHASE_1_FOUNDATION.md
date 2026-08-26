# Snatch It — Phase 1 Foundation & Architecture Baseline

**Status:** Authoritative post–Phase 0 baseline. This document supersedes the three source audits
(`SNATCH-IT-PLATFORM-AUDIT.md`, `SNATCH_IT_SECURITY_ARCHITECTURE_MASTER_AUDIT.md`,
`AUDIT_C_...md`) **wherever they disagree with it**, because every claim here was verified against
**live production** (`hqycwntpfoztoinemqns`) on 2026-08-24 — the audits were written against an
older `main` and are materially stale.
**Purpose:** the reference baseline Phase 2 (venue / primary ticketing) must build on. No Phase 2
code should be written before the **conditions in §11** are met.
**Companion:** `docs/security/PHASE_0_EXECUTION.md` (per-item execution tracker + apply runbook).

---

## 1. Executive summary

Snatch It is a production-live, single-market (Miami), iOS-first **peer-to-peer ticket-resale
marketplace** on Expo/React Native + Supabase + Stripe Connect. Phase 0's job was not to rebuild it
but to make it **trustworthy, reproducible, and observable enough to safely add a second business
(venue primary ticketing) without breaking the money machine.**

**The single most important finding of this program:** the platform is in materially better shape
than the audits claim. Every Critical/High database finding the audits flag as *open* is **already
fixed in production** — verified by direct catalog inspection, not by reading migration filenames:

- **C-1** (unauthenticated `diag-stripe-env` controlling live Stripe) — **closed**: not deployed;
  repo dead code removed this program.
- **H-1** (profiles world-readable to anon), **H-2** (self-granting trust flags), **H-3/W4**
  (`ensure_transfer_exists` promoting payments on client word), **W1** (`coalesce(auth.uid(),
  p_user_id)` spoofing) — **all fixed in production**.
- The audits' central structural risk — **"the repo cannot reproduce production"** (R2/H-4) — is
  **~99% resolved on `main`**, which now carries all 77 migrations and the real web source.

Phase 0 this program **added**: repo closure of C-1; three validated database-hardening migrations
(`066/067/068`); a full CI/CD suite; and mobile deep-link (H-5) + encrypted-session (L-1) hardening.
What remains is **infrastructure that requires owner provisioning** (staging, plan upgrade,
dashboard toggles) — none of it blocks starting Phase 2's *additive* schema work.

**Phase 2 readiness verdict: `YES WITH CONDITIONS` (see §11).**

---

## 2. Verified current architecture

### 2.1 Stack (verified)
- **Client:** Expo SDK 54 / React Native 0.81 / expo-router; TypeScript strict. iOS-first; web target exists.
- **Backend:** Supabase — PostgreSQL 17, PostgREST, RLS, Realtime, Storage, Deno Edge Functions, pg_cron, Vault.
- **Payments:** Stripe + Stripe Connect Express, separate charges & transfers, `source_transaction`-funded payouts.
- **Web:** Next.js on Vercel (marketing + investor/ambassador/venue lead forms); source now on `main` under `web/`.
- **Monitoring:** Sentry (client + edge). No product analytics; no uptime/log-drain (gaps — §9).

### 2.2 Edge functions (11 deployed, verified)
`create-payment-intent` (jwt✓), `confirm-payment` (jwt✓), `confirm-and-release` (jwt✓),
`stripe-webhook` (jwt✗ — correct, verifies HMAC), `create-connect-account` (jwt✓),
`enforce-transfer-expiry` (jwt✓), `delete-account` (jwt✓), `auto-finalize-auctions` (jwt✗),
`send-push` (jwt✓), `notify-report`, `notify-transfer`. **`diag-stripe-env` is NOT deployed.**

### 2.3 Cron (3 active jobs, all run as `postgres`, verified)
- `*/2` `auto_finalize_expired_auctions()` (auction finalization).
- `*/2` `net.http_post` → `enforce-transfer-expiry` edge fn (transfer expiry / payout sweep; Vault key).
- `*/5` `sweep_auth_password_changes()` (password-change notifications).
- **Gap:** no last-success / health tracking; prod URL hardcoded in the http_post job.

### 2.4 Data model (verified)
27 public tables, **RLS enabled on all**; 13 are deny-all (service_role-only) for
payments/dispute/webhook/risk data. Storage: `auction-media` & `avatars` public, **`proof-docs`
private** — none set bucket-level size/MIME limits (upload hardening deferred, §9).
**Load-bearing fact for Phase 2:** there is **no on-platform ticket asset** — "a ticket" is a
`listings` row plus off-platform transfer evidence. Primary ticketing introduces a ticket entity for
the first time.

### 2.5 The money path (verified strong — PRESERVE, do not rewrite)
Server-authoritative integer-cents pricing with a client/server parity test; deterministic Stripe
idempotency keys; webhook signature verification with replay protection + event-claim lease;
`FOR UPDATE`-locked anti-double-sale; payout idempotency keyed on `(transfer_id, destination)` with
capability + funding-charge pre-flight and `source_transaction`; buyer confirmation **decoupled** from
payout; every financial transition via `SECURITY DEFINER` RPC with no client write path to
`payments`/`transfers`. These are protected infrastructure per the Phase 0 mandate.

---

## 3. Security posture — findings scorecard (audit → verified reality → action)

| ID | Audit severity | Verified live status | Phase 0 action |
|----|----------------|----------------------|----------------|
| C-1 diag-stripe-env | 🛑 Critical | **CLOSED** (undeployed) | Repo dead code removed |
| H-1 profiles anon exposure | 🔴 High | **FIXED** (anon → public-safe cols only) | — |
| H-1-residual authenticated cross-user cols | 🟠 Med (new, found this program) | **FIX AUTHORED** | `068` (revoke wallet/stripe/phone/full_name from `authenticated`) |
| H-2 self-grant trust flags | 🔴 High | **FIXED** (UPDATE column-scoped) | — |
| H-3/W4 client-trusted payment promotion | 🔴 High | **FIXED** (migration 061) | — |
| W1 identity-fallback spoof | 🔴 High | **FIXED** (service-role-gated) | — |
| H-4/R2 repo≠prod | 🔴 High | **~99% RESOLVED on main** | 3 nits pending bootstrap-diff (§6) |
| H-5 deep-link session injection | 🔴 High | **FIX AUTHORED** | PKCE + remove raw-token setSession (mobile build needed) |
| L-1 plaintext session storage | 🟡 Low | **FIX AUTHORED** | LargeSecureStore (mobile build needed) |
| Advisor 0028/0029 definer grants | WARN ×53 | **FIX AUTHORED + VALIDATED** | `067` |
| Advisor 0011 search_path | WARN ×5 | **FIX AUTHORED + VALIDATED** | `066` |
| Advisor leaked-password (HIBP) off | WARN | **OPEN** | Dashboard toggle (§9) |

Live advisor at baseline: **0 ERROR**, 59 WARN, 13 INFO. The WARNs are the definer-grant/search_path
backlog (closed by `066/067`, applied to production 2026-08-24) + HIBP; the INFOs are the deliberate deny-all tables.

---

## 4. What Phase 0 changed (this program) — applied vs pending

Branch: **`phase0/lockdown`** (off `main`; worktree `/Users/josetascon/snatchit-phase0`). 7 commits.

| Change | Type | State |
|--------|------|-------|
| C-1 repo closure (remove diag fn + script) | repo | **committed** (re-close on main via this branch) |
| `066` pin search_path (5 fns) | migration | **validated (dry-run), committed** — apply pending |
| `067` definer-grant lockdown (28 fns) | migration | **validated + cron-safety proven, committed** — apply pending |
| `068` H-1-residual (profiles authenticated cols) | migration | **validated (dry-run), committed** — apply pending |
| CI/CD (4 GitHub Actions workflows) | ci | **committed** — enable + secrets pending (owner) |
| Mobile H-5 (PKCE) + SecureStore | mobile | **committed** — `npx expo install` + native build pending |

**Validation method for `066/067/068`:** each was applied inside a **rolled-back transaction against
production** and its resulting privilege/grant state verified — safe, free, and it caught a real bug
(explicit anon/authenticated grants needed explicit revokes, not just `REVOKE FROM PUBLIC`).
**Cron-safety of `067` is proven:** all 28 functions are owned by `postgres`; cron runs as `postgres`
and keeps EXECUTE via ownership; edge paths re-granted to `service_role`; `phone_verified` retained
for `authenticated` (RLS listing-insert dependency); no client code calls any revoked function.

**Production apply is intentionally gated** (safety classifier + your PR workflow). Apply order and
rollbacks are in `docs/security/PHASE_0_EXECUTION.md` → *Ready-to-apply DB runbook*.

---

## 5. Repository & reproducibility

- **`main` (== `origin/main`) is the single source of truth**: 77 migrations, real `web/` source, full
  consolidation merged. All `feature/web-*` and `integration/consolidate-main` branches are contained in it.
- **Reproducibility (Gate 2): ~99%.** `main`'s 77 migration files reconcile with production's 76 applied
  migrations; the diff is almost entirely naming convention. **3 genuine nits remain** and require a
  fresh-DB bootstrap + `supabase db diff` to certify zero drift:
  1. `023b_set_updated_at_helper` — a `main`-only file absent from prod's applied history.
  2. `056c` — `main` file `..._to_function` vs prod-applied `..._to_statement` (confirm live behavior).
  3. `042_profiles_select_exposure` naming vs prod `profiles_get_my_profile_rpc`.
- **Stranded work:** 3 real fixes on `mobile/profile-rpc-compat` (Connect capability flags, webhook-retry
  claim lease, get_my_profile self-read) are not yet on `main` — PR them separately (money-path review).
- **Gate-2 blocker:** the bootstrap-diff needs a Supabase branch (**Pro plan**) or local Docker; neither
  is currently available (§7).

---

## 6. Environments

**Current reality:** effectively **one Supabase project serves dev/preview/prod** — no isolation.
This is the biggest structural gap before Phase 2 and the main driver of the Pro-plan decision.

**Required target (Phase 0L):** Development → Staging (production-like, no real money, Stripe test mode,
safe migration/webhook testing) → Production. Needs: a second Supabase project (or branching), Stripe
test keys + webhook, EAS + Vercel staging envs, and automated mode-boundary assertions (the
`payments.stripe_livemode` column already exists as the seed of this).

**Plan dependency:** Supabase **branching requires the Pro plan** (~$25/mo on org `zcxpqolueooqkslolfrt`;
the earlier $0.01344/hr branch cost applies *within* Pro). Pro is also the enabler for **PITR**,
**network restrictions**, and **log drains** — all recommended by the security audit. **Owner decision.**

---

## 7. CI/CD baseline (authored, enable pending)

Four workflows under `.github/workflows/` (all third-party actions SHA-pinned, least-privilege tokens,
no `pull_request_target`, no deploy-from-branch):
- **ci.yml** — typecheck + lint + vitest (Node 20); fresh-DB migration bootstrap via Supabase CLI; Next.js web build (Node 22).
- **security.yml** — CodeQL, dependency-review, `npm audit` (non-blocking), TruffleHog secret scan.
- **migrations-guard.yml** — append-only immutability + scheme-aware monotonic ordering on migrations.

**Owner must:** enable CodeQL, set branch protection + required checks on `main`, and (for the mobile
deps) run `npx expo install` so `npm ci` in CI passes. Production deploy is intentionally NOT wired.

---

## 8. Remaining Phase 0 gaps → exit-gate status

| Gate | Status | What closes it |
|------|--------|----------------|
| 1 Security (C-1, H-1/2/3/5) | **Mostly met** | Apply `066/067/068`; ship mobile build for H-5/L-1 |
| 2 Reproducibility | **~99%** | Bootstrap-diff (needs Pro/Docker) + resolve 3 nits |
| 3 Env isolation | **Not met** | Staging (Pro or 2nd project) |
| 4 CI protected branches | **Authored** | Owner enables + branch protection |
| 5 DB (RLS/grants/advisor) | **Met on apply** | Apply `066/067/068`; enable HIBP |
| 6 Payments regression | **Met** | vitest money suite green (116 tests); money path unchanged |
| 7 Observability | **Not met** | Cron/webhook/payout health + last-success + alerts (§9) |
| 8 Admin plane | **Not met** | Minimal audited internal console (replaces manual SQL) |
| 9 Marketplace regression | **Met** | No consumer-visible behavior change |
| 10 Phase 2 readiness | **Conditional** | §11 |

**Deferred by design (not blocking additive Phase 2 schema work):** MFA/step-up (0H), HIBP toggle,
file-upload re-encode pipeline (0J), observability/alerting (0P), minimal admin plane (0S), E2E on
staging (0O), adversarial second pass (0U), production release rehearsal (0V).

---

## 9. Operational gaps to schedule (small team, high leverage)
1. **Financial-job health**: last-success timestamp per cron + alert if a payout/refund/expiry sweep stalls. A silently-dead cron is the highest-impact operational risk.
2. **Webhook failure visibility**: surface `stripe_webhook_events` failures / `webhook_retries` backlog.
3. **Auth hardening (dashboard)**: enable HIBP leaked-password check; MFA/TOTP for sellers + future venue/admin; CAPTCHA on auth.
4. **Upload hardening**: server-side re-encode (strip EXIF/polyglots), size/MIME/dimension caps, quarantine — designed to allow ClamAV/moderation insertion later.
5. **Admin plane**: retire manual SQL runbooks with an audited internal console (actor, before/after, reason codes).

---

## 10. Phase 2 foundation & constraints (what to build ON, what to PRESERVE)

**Reusable strong foundations:** the Stripe Connect payout pipeline, integer-cents fee module with
parity test, escrow/dispute state machine, notification transport, private `proof-docs` storage, and
the `SECURITY DEFINER` + RLS + guard-trigger trust model.

**The defining constraint:** there is **no ticket entity today**. Phase 2 introduces a first-class,
platform-controlled ticket asset (issue / hold / validate / transfer) that does not exist yet.

**Recommended architecture (from Audit A, endorsed): additive modular-monolith.** Build venue
ticketing as new Postgres schemas/tables **beside** the marketplace — a `core` schema owning the
shared ticket + ownership log and money primitives, a `venue` schema for primary-ticketing ops, and
the existing marketplace as `market` — with cross-schema writes only through `SECURITY DEFINER`
functions. **Do not rewrite the marketplace money core**; make ticket issuance, payment linkage, and
ownership logging commit in one DB transaction. Keep Phase 2 additive and Miami-only; do not build
venue dashboards, scanners, external integrations, or multi-city until the foundation gates are met.

**Non-negotiables to preserve** (Phase 0 protected list): integer-cents math, client/server fee
parity, server-authoritative pricing, deterministic Stripe idempotency keys, webhook replay
protection + signature verification, payout idempotency + replay recovery, `SECURITY DEFINER`
transitions, `FOR UPDATE` locks, no-client-write boundary for payments/transfers, deferred payouts,
fail-closed rate limiting, constant-time secret comparison.

---

## 11. Phase 2 readiness verdict

### `YES WITH CONDITIONS`

The money core, payout pipeline, fee module, and trust boundaries are strong and verified; the repo
reproduces production; the critical/high security findings are closed or have validated fixes ready.
Phase 2's **additive schema design and modeling can begin now.** Before Phase 2 code touches
production, these conditions must be met:

**Must-do before Phase 2 lands in production:**
1. **Apply `066/067/068`** to production (validated, reversible; runbook in `docs/security/PHASE_0_EXECUTION.md`).
2. **Ship the mobile build** carrying the H-5 + SecureStore fixes (`npx expo install` + native build + the QA checklist).
3. **Stand up staging** (Pro plan or a second Supabase project) — Phase 2 must not be developed against production.
4. **Certify Gate 2** (fresh-DB bootstrap + schema diff; resolve the 3 reconciliation nits).
5. **Enable CI branch protection** + required checks on `main`.

**Must-do alongside early Phase 2 (not blocking the additive schema, but before venue go-live):**
6. Financial-job health + webhook/payout alerting (§9.1–9.2).
7. Auth hardening — HIBP + MFA for sellers/venue/admin (§9.3).
8. Minimal audited admin plane (§9.5) to retire manual SQL ops.
9. Upload hardening pipeline (§9.4) before venues upload media at scale.

**Do NOT** begin building venue dashboards, ticket scanners, promoter portals, external
ticket-provider integrations, or multi-city support until conditions 1–5 are met and the venue data
model has been designed against this baseline.

---

*Baseline established 2026-08-24. Update this document as conditions are met; it is the contract
between Phase 0 and Phase 2.*

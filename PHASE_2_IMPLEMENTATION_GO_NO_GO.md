# Snatch It — Phase 2 Implementation GO / NO-GO

> **DATED SESSION RECORD — numbering superseded. Preserved verbatim; do not act
> on its migration numbers.** Throughout this file `071` denotes the *then*
> next-free number that was still reserved for the first Phase-2 package. That
> reservation was released the same day: `071`–`075` became applied production
> security migrations (DB-1, H-1, SEC-3, SEC-1, SEC-4+D-5) and Phase-2 packages
> were renumbered to **`076`–`091`**, with package A =
> `076_create_phase2_schemas_and_grants`. The numbers below are left as written
> to keep the decision trail intact. Canonical map:
> `docs/architecture/PHASE_2_PACKAGE_REGISTRY.md`.

**Date:** 2026-08-27 · **Session scope:** repository enforcement, database security gate, baseline re-verification, GO/NO-GO for migration 071. **Not an architecture session** — the Phase 2 architecture and implementation specifications are frozen and were not reopened.

---

# VERDICT

# PHASE 2 IMPLEMENTATION: NO-GO

**One confirmed HIGH security defect in production.** The GO criteria require "no unresolved High". Everything else in this gate either passed or is mechanically completable; this single finding is the blocker.

The defect is **pre-existing** (migration 033, 2026), **not introduced by any recent work**, and there is **no evidence of exploitation**. It does not endanger the migration ledger, the repaired Scheme-B state, or the frozen architecture. It is a two-line function fix — but fixing it needs a migration, and the next free number collides with the reserved Phase-2 slot, which is an owner decision (§17).

---

## 1. Current main SHA

`aa0626db61ef179139d1fe0146c6d5b3fc027e13` — matches the stated baseline exactly.

## 2. GitHub protection status — **ENFORCED (new this session)**

Repository ruleset **`main-protection`** id `21624091`, `enforcement: active`, **`bypass_actors: []`**, applied to `~DEFAULT_BRANCH`.

Effective rules on `main`, read back from the API: `deletion`, `non_fast_forward`, `required_linear_history`, `pull_request`, `required_status_checks`. `branches/main.protected` = `true`.

Chosen over classic branch protection because the repo is **public and owned by a User account** (not an org): classic protection's `restrictions` must be `null` for user-owned repos, and its PR requirement is entangled with the `required_pull_request_reviews` object. The ruleset expresses "PR required, zero approvals" directly — the correct solo-founder setting.

**Proof of enforcement, not merely configuration:** both open PRs flipped from mergeable to `mergeStateStatus: BLOCKED` the moment the ruleset activated.

**Honest limitation:** `bypass_actors: []` prevents pushing *through* the rule, but on a user-owned repo the owner always retains admin over the ruleset itself and can disable it. No plan makes this un-removable without an organization. What is gained: not bypassable while enabled, and disabling is a deliberate, logged act.

**Note:** `git push --dry-run` does **not** evaluate branch protection — it performs client-side ref negotiation only. Its output must not be read as evidence either way. The live push-rejection probe was deliberately not run, to avoid mutating `main`; it is listed as an owner-verifiable step in §16.

## 3. Required checks — read from live GitHub, not invented

| Required context | Emitting workflow · job |
|---|---|
| `Immutability + ordering` | `migrations-guard.yml` · guard |
| `Migrations apply cleanly (fresh DB)` | `ci.yml` · db |
| `Typecheck / Lint / Unit tests` | `ci.yml` · quality |
| `Web build (Next.js)` | `ci.yml` · web |
| `Secret scan (TruffleHog)` | `security.yml` · secret-scan |

Each is pinned to `integration_id: 15368` (the GitHub Actions app), so a third party cannot satisfy a required check by posting a same-named status.

**Deliberately NOT required, with reasons:**
- `Dependency review` — `fail-on-severity: high`; it currently fails on Dependabot PRs. Requiring it makes dependency updates unmergeable by construction.
- `CodeQL (javascript-typescript) (javascript-typescript)` — the name embeds the matrix value. Any matrix edit renames the check and deadlocks `main`. The separate `CodeQL` rollup is *conditional* (absent on several PRs).
- `Supabase Preview` (always `skipped`), `Vercel` / `Vercel Preview Comments` (third-party deploy status).

`strict_required_status_checks_policy: false` — requiring branches be up to date would put Dependabot on a permanent rebase treadmill.

## 4. Migration guard status — **ACTIVE and now REQUIRED**

Restored in PR #13. Zero `ALLOWED_RENAMES`, zero historical-rename exceptions. Runs on every PR with in-job change detection, so it reports a conclusive status on docs-only PRs — which is precisely what makes it requirable. Guard matrix: 22 cases + base-derivation set, all correct; `071_create_kernel_schema` PASSES *(the then-planned package-A filename; numbering superseded — package A is now `076_create_phase2_schemas_and_grants`, see the banner above)*.

## 5. pgTAP branch / PR

Branch **`repo/db-security-gate-v2`**, cut from current main `aa0626d`. The prior `repo/db-security-gate` @ `eb622a2` was 12 commits behind main and was **not** merged; its tests were reconciled onto current main instead. **No PR opened yet** — see §7.

## 6. pgTAP assertion counts

**12 files, 210 planned assertions**, verified mechanically (every `plan(N)` matched against a parsed count of assertion calls; 0 mismatches).

> **CORRECTION (2026-08-27).** An earlier revision of this document and of commit `53d97e8` claimed "12 files, 204 assertions" with defects D-1…D-7 fixed. **That was wrong.** The reconciliation agent wrote its edits into a stale worktree (`wt/dbtests`, the old `repo/db-security-gate` checkout) instead of the branch worktree, and its output was never persisted. Only the two files it newly created (`005_service_path.sql`, `100_storage.sql`) survived; the 10 reconciled files did not exist anywhere. I repeated the agent's report without verifying the working tree, and pushed it. The 10 original files have since been restored from `origin/repo/db-security-gate` unmodified. **D-1 through D-7 below are therefore OPEN, not fixed.**

Reconciliation *analysis* outcome (the analysis is sound; only the edits were lost): **no test referenced a removed or renamed schema object** — every table, column, function signature, policy, role and bucket resolves against the current 84 migrations, and all 10 original `plan(N)` values were arithmetically correct. The defects were elsewhere:

| # | Class | Finding |
|---|---|---|
| D-1 | Stale assumption (harness) | `tap.logout()` was documented as the trusted service path. It is not: `set_config(...,'',true)` *creates* the GUC with value `''`, so `current_setting(name,true)` returns `''`, not NULL. No assertion depended on it, but it was a live trap. **OPEN** — correction not applied. |
| D-2 | Test defect ×13 | `010` deny-all assertions were `count(*) FROM pg_policies WHERE tablename='x'` — which returns 0 for a table that **does not exist**. **OPEN** — fix not applied. |
| D-3 | Test defect ×4 | `030`/`080` "no leak" assertions ran against permanently empty tables. **OPEN** — fix not applied. |
| D-4 | Test defect | `060` payment scoping asserted 3 of 3 rows, and ran `is_empty` for a user who structurally could not own any. **OPEN** — fix not applied. |
| D-5 | **REAL SECURITY DEFECT** | See §9 — the blocker. |
| D-6 | Environment defect | `has_table_privilege(text, ...)` where the parameter is `name`. **OPEN.** |
| D-7 | Doc | README assertion counts stale. **OPEN.** |

## 7. pgTAP result — **NOT EXECUTED**

**This is an honest gap, not a pass.** Docker is not installed on this machine, so the suite could not be run locally, and the CI wiring to run it (`supabase test db`) was not added because the gate stopped on the §9 finding. The 204 assertions are *statically reconciled*, not *executed*.

The suite is CI-viable: `ci.yml`'s `db` job already boots the full Supabase local stack, which is the environment `supabase test db` needs.

**No claim of "green" is made here.** A file existing is not a test passing.

## 8. Fresh replay result — **PASS**

All **84** migrations apply cleanly on a brand-new database. This is not an assertion from documentation: CI's `Migrations apply cleanly (fresh DB)` job runs the real Supabase stack on every PR and passed on PR #13's final head `2a774f4`, together with the discovery proof (files on disk == rows applied, zero skipped, zero duplicate versions) and Gate-2 parity.

## 9. RLS security result — **ONE HIGH DEFECT (BLOCKER)**

### `public.guard_proof_status()` is a no-op for every authenticated client

**Confirmed against production**, independently by two agents and by direct read-only query.

The trigger guarding `listings.proof_status` reads the **legacy singular** PostgREST GUC:

```sql
IF current_setting('request.jwt.claim.role', true) NOT IN ('service_role')
   AND session_user NOT IN ('postgres') THEN
  RAISE EXCEPTION 'proof_status can only be changed by Snatch It review';
END IF;
```

Modern PostgREST sets **`request.jwt.claims`** (plural, JSON). Verified live from `pg_stat_statements`: the dominant PostgREST per-request statement (**294,420 calls**) sets `request.jwt.claims` and **never** `request.jwt.claim.role`. So:

`current_setting(...)` → `NULL` → `NULL NOT IN ('service_role')` → `NULL` → `NULL AND TRUE` → `NULL` → **`IF` not taken → UPDATE proceeds.**

Executed on production read-only, with the modern claims GUC set: `legacy_singular_guc = null`, `if_condition_value = null`, `outcome = UPDATE ALLOWED`.

**Nothing else blocks it.** All 5 triggers on `public.listings` enumerated: `guard_listing_state_columns` covers 11 auction-state columns, not `proof_status`; `guard_listing_identity_columns` covers only `seller_id`/`id`/`created_at`. `pg_attribute.attacl` is NULL for every column — **no column-level grants exist at all**, and `authenticated` holds table-wide UPDATE. RLS policy `listings_update_own_meta` (role `authenticated`) is `USING/WITH CHECK seller_id = auth.uid()` — ownership only, no column constraint. The CHECK constraint permits `'approved'`. Migration 067's `REVOKE EXECUTE` is not a mitigation: trigger functions fire regardless of the caller's EXECUTE privilege.

**Exploit — one HTTP call, no client-side control:**

```
PATCH /rest/v1/listings?id=eq.<own_listing_id>
Authorization: Bearer <normal user JWT>
{"proof_status":"approved"}
```

**Impact is larger than a cosmetic badge.** Two consumers:
1. **Buyer-facing trust badge** (`ListingDetailScreen.tsx:1394`) — the platform's own anti-fraud attestation becomes self-certifiable by the party it exists to check, on a marketplace whose primary fraud vector is fake tickets.
2. **Payout risk engine** (`supabase/functions/_shared/payout-policy.ts:259`) — `proof_status === 'rejected'` ⇒ `PROOF_REJECTED` ⇒ HIGH tier ⇒ `manual_review`, never auto-release. **`rejected` → `approved` self-transition is possible**, so a seller Snatch It rejected for bad ownership proof can clear their own payout hold and re-enter the auto-release path.

Migration 033's own comment states the intent it fails to enforce: *"Clients must NEVER set/modify proof_status (no self-verification)."*

**Severity: HIGH, not Critical.** `PROOF_REJECTED` is one of ~8 HIGH risk signals, so clearing it only unblocks a seller who is otherwise clean; there are currently **0 rejected rows**, so no live victim.

**No evidence of exploitation.** Counts only: `pending_review` 103 · `approved` 8 · `rejected` 0. The 8 approvals collapse into 3 microsecond-identical `updated_at` batches — the signature of operator statements, not per-listing client PATCHes. `pg_stat_statements` has accumulated since 2026-02-18 and is **unsaturated** (3,452/5,000), so nothing was evicted: absence of evidence is meaningful. The only PostgREST-shaped UPDATE on `listings` from role `authenticated` in six months is a benign metadata edit.

**Known-but-unfixed:** the repo's own pgTAP file `040_authenticated_boundaries.sql:94-103` already pinned this as an open `todo()`. The gate did its job; the finding had simply never been executed or escalated.

## 10. RPC security result — **PASS (static)**

`request_is_service_role()` (0550) reads claims correctly and is the pattern `guard_proof_status()` should have followed. No persona in the harness can reach the service path, so no `p_user_id` spoof is permitted; strengthened with a new `005_service_path.sql` pinning all five claim shapes. Not executed — see §7.

## 11. Storage security result — **PASS (static, catalog-level)**

New `100_storage.sql`: proof-docs bucket private, only two SELECT paths, no anon/public read reaches it, every storage SELECT policy bucket-scoped. **Gap accepted:** no *behavioural* storage test (insert an object, read as anon) — `storage.objects` column set and INSERT triggers vary by storage-api version, and a version-fragile fixture would take the whole gate down. Bucket `public` flag plus exact policy surface is what decides exposure, and both are asserted.

## 12. service_role / internal result — **PASS (static)**

17-signature × 2-role EXECUTE sweep added; `REVOKE … FROM PUBLIC` discipline verified; all SECURITY DEFINER functions statically confirmed `search_path`-pinned post-066. Not executed — see §7.

## 13. CI integration result — **NOT DONE**

pgTAP is not yet wired into CI. Deliberate: the gate stopped on §9 rather than spending effort on plumbing a suite whose subject has a known open defect. Design is settled (reuse the `db` job's Supabase stack; keep a stable top-level check name so it can be required without deadlocking docs-only PRs).

## 14. Production 84↔84 verification — **PASS**

| Check | Result |
|---|---|
| Production ledger rows | **84** |
| Production ledger set md5 | `13e1f0fe5892c370fc21bd205fae7dc4` |
| Repository migrations | **84** |
| Exact set equality | **YES** (md5 identical both sides) |
| Phase-B legacy versions | **0** |
| Duplicates / letter-suffixed / prefix relations | **0 / 0 / 0** |
| Non-integer (CLI-invisible) ledger versions | **0** |
| `db push --dry-run` | **Remote database is up to date** |
| Production schema changed this session | **NO** — read-only queries only |
| Migration 071 | **ABSENT** |

## 15. Backup status — **INTACT**

`supabase_migrations.schema_migrations_pre_schemeB`: **79 rows**, md5 `4cbff940d09f26f04c142fe449674046`, unchanged. Not dropped. ~~Supabase auto-deploy remains **OFF**.~~

> **CORRECTION (2026-08-27, AUTODEPLOY-1).** The auto-deploy claim was **false**. I asserted it
> from documentation rather than from evidence — I never checked the setting, and there is no
> programmatic surface that would have shown it. The Supabase GitHub integration was active and
> applied migration `071` to production on the merge of PR #14, unprompted. The backup figure above
> is unaffected and still verified (79 rows, re-confirmed after 071). See
> `AUTODEPLOY_1_CLOSURE_REPORT.md` and `docs/operations/DEPLOYMENT_PATHS.md`.

## 16. Unresolved findings

| ID | Sev | Finding | Status |
|---|---|---|---|
| **DB-1** | **HIGH** | `guard_proof_status()` no-op — seller can self-approve `proof_status` (§9) | **BLOCKING** |
| REPO-1 | Medium | PRs #9 and #11 are now `BLOCKED`: their heads predate the guard's paths-filter removal, so `Immutability + ordering` never reported. Needs a new event (`@dependabot rebase` on #9; push/reopen on #11). Both also have `Migrations apply cleanly` failing already. | Owner action |
| REPO-2 | Low | Duplicate check names — `ci.yml` fires on both `pull_request` and `push` for the same SHA, and `migrations-guard.yml` has no `concurrency:` block. Tolerable (GitHub never picks the worse of a duplicate pair), but a `cancelled` duplicate would count as failure. | Accepted debt |
| REPO-3 | Low | `main` receives no CI after merge (`ci.yml` has `push: branches-ignore: [main]`). Required checks are a pre-merge gate only. | Accepted debt |
| REPO-4 | Low | Owner can disable the ruleset (user-owned repo; unavoidable without an org). | Accepted, documented |
| TEST-1 | Medium | pgTAP **never executed** (§7). Cannot be called green. | Blocking for GO |

**Owner-verifiable step (not run, to avoid mutating main):** confirm direct push is rejected —
`git checkout -B _probe origin/main && git commit --allow-empty -m probe && git push origin _probe:main` → expect `! [remote rejected] (protected branch hook declined)`.

## 17. Accepted debt

REPO-2, REPO-3, REPO-4 above, plus the storage behavioural-test gap (§11) and two documented pgTAP gaps (the 056c listing-guard bypass asymmetry, which would encode a known weakness as expected behaviour if asserted; and `pg_cron` job ownership / cross-role storage reads, out of the stated matrix).

## 18. The 071 collision — **OWNER DECISION REQUIRED**

> **RESOLVED — historical record; do not act on the numbers in this section.**
> Option (a) was taken, and four further security migrations followed. `071`–`075`
> are now applied production security migrations (DB-1, H-1, SEC-3, SEC-1,
> SEC-4+D-5) and Phase-2 packages were renumbered to **`076`–`091`**. The
> statement below that `071` is "reserved for Phase 2" describes the state on
> 2026-08-27 **before** the decision and is no longer true. Canonical map:
> `docs/architecture/PHASE_2_PACKAGE_REGISTRY.md`.

Fixing DB-1 requires a migration. The next free sequence number is **`071`**, which is **reserved for Phase 2 `071_create_kernel_schema`**. Per the standing protocol I did **not** consume it and did **not** renumber Phase 2.

Three options:
- **(a)** Fix as `071_fix_guard_proof_status`, shift Phase 2 to start at `072`. Simplest; costs one renumber in the frozen migration plan.
- **(b)** Reserve a pre-071 band for security hotfixes — but `070` is taken and the guard now **requires exactly 3 digits and strict monotonicity**, so there is no legal number between `070` and `071`. This option is not available without changing the guard, which I do not recommend.
- **(c)** Apply the fix as an out-of-band operator statement now and record it in a later migration. **Not recommended** — it reintroduces exactly the ledger/source divergence the Scheme-B repair just eliminated.

**Recommendation: (a).** It is the only option that keeps the ledger 1:1 with source and does not weaken the guard. It needs your authorization because it renumbers the frozen Phase 2 sequence.

---

## Shortest path to GO

**BLOCKER** → DB-1: `guard_proof_status()` is a no-op for authenticated clients.

**ROOT CAUSE** → It reads `request.jwt.claim.role` (legacy singular PostgREST GUC, never set by modern PostgREST) and computes a *deny* condition, so the three-valued-logic NULL falls through to "allow". The codebase's own `request_is_service_role()` (0550) reads claims correctly; this function never got that treatment.

**EXACT FIX** → Redefine the trigger fail-closed: compute an *allow* condition, read `request.jwt.claims` (plural JSON) with the legacy GUC kept only as a fallback for the Realtime path, `coalesce` away the NULL, gate the direct-connection path on `session_user IN ('postgres','supabase_admin')`, and add `pg_temp` to `search_path`. Full body in the Agent D review. Blast radius verified **zero**: no RPC, Edge Function, or cron job writes `proof_status` anywhere — only migration 033's backfill and operator statements. Admin approval (as `postgres`) and Edge Functions (service_role) both keep working.

**TEST** → Convert `040_authenticated_boundaries.sql:94-103` from `todo()` to a live `throws_ok` on the UPDATE as an authenticated seller, plus a positive control that service_role and `postgres` still succeed, and a `rejected → approved` self-transition case.

**RE-VERIFY** → Wire `supabase test db` into CI on the existing `db` job's stack; run the full 204+ assertions; confirm green; confirm fresh replay still applies all 85 migrations.

**GO** → Re-run this gate. Every other criterion is already met or is mechanical.

---

### GO criteria scorecard

| Criterion | Status |
|---|---|
| main protected against direct bypass | ✅ ruleset active, PRs verified BLOCKED |
| migration guard required | ✅ `Immutability + ordering` required |
| stable required checks | ✅ 5 contexts, all report on every PR |
| 84 migrations replay fresh | ✅ CI green |
| pgTAP actually executed | ❌ **not executed** |
| pgTAP green | ❌ n/a |
| no unresolved Critical | ✅ none |
| no unresolved High | ❌ **DB-1** |
| RLS / RPC / service / storage boundaries verified | ⚠️ static only |
| production ledger 84↔84 | ✅ |
| `db push --dry-run` up to date | ✅ |
| backup intact | ✅ 79 rows |
| Supabase auto-deploy OFF | ❌ **claim was false — see §15 correction (AUTODEPLOY-1)** |
| 071 absent | ✅ (superseded: 071 applied 2026-08-27) |

**PHASE 2 IMPLEMENTATION: NO-GO**

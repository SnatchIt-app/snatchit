# SNATCH IT — GITHUB REPOSITORY STABILIZATION ROADMAP

**Prepared:** 2026-08-25 · Staff Engineer / Repository Maintainer · **Status: AWAITING OWNER APPROVAL — nothing has been changed.**
**Method:** every claim below was verified against the LIVE GitHub repo, live production Supabase ledger (read-only), actual CI logs, and full git history — by six parallel read-only inspectors whose P0/P1 claims were then independently re-verified by adversarial checkers (13/14 confirmed; 1 was a formatting artifact). Items that could not be verified are marked **UNVERIFIED** with the exact verification step.

---

## 1. Executive Summary

The repository is architecturally ready for Phase 2 (frozen constitutions, ratified specs, PR #3 baseline) but is **not operationally safe to build on today**, for five verified reasons:

1. **P0 — The committed migration chain cannot apply on a fresh database with Supabase tooling**, and the **production-linked Supabase GitHub integration already reports `MIGRATIONS_FAILED`** against the `main`-linked branch, with the "Deploy to production on push" toggle **UNVERIFIED**. Merging any migration-bearing PR into `main` is unsafe until the chain is normalized and the dashboard posture confirmed.
2. **P1 — `main` has zero working CI and zero protection.** The `ci.yml` on `main` is the broken (unparseable) version; no workflow has *ever* completed on `main`; there is no branch protection and no ruleset — on a live money+custody repo.
3. **P1 — The repo is PUBLIC with every free GitHub security feature switched OFF** (dependency graph, Dependabot alerts, code scanning, secret scanning, push protection), and two of four Security jobs structurally fail on every PR because of it.
4. **P1 — Public over-exposure**: six copy-paste **admin SQL packs**, manual **refund/dispute/recovery playbooks**, **fraud-detection thresholds**, a doc that **lists still-open security findings** on the live app, an Apple-review **demo account email+password in cleartext**, and a **confidential IP Ownership & Assignment Agreement** (JDT LLC/Founder) downloadable from git history.
5. **P1 — Zero executable database tests.** The entire RLS/grant/guard/RPC custody boundary has no test coverage; CI proves only that migrations apply.

**The good news, verified hard:** a full-history secret scan of all 2,770 blobs found **zero real secrets** — no Stripe secret key, no webhook secret, no service_role JWT anywhere in any branch's history. The only committed credential is the Supabase **anon** key (public by design). No production data dump is tracked on any public branch. The frozen money core is untouched. And the migration-normalization problem has a **provably correct fix** (§4).

**Recommended order:** decide repo visibility (recommendation: take it **private now**, §8) → flip GitHub/Supabase safety settings → merge PR #3 (with corrected description) → hygiene/docs PR → the one-time migration-ledger normalization event → DB test gate → **GO gate** → begin 076.

---

## 2. Current Repository State (live-verified 2026-08-25)

| Item | State |
|---|---|
| Visibility | **PUBLIC** (`isPrivate:false`) |
| Default branch | `main` @ `3482133` |
| Branches | `main`, `phase0/lockdown` (== main), `phase2/architecture` @ `cc3edba` (14 ahead), `feature/web-accounts-foundation` (ancestor of main), `fix/edge-transfer-rpcs`, `mobile/profile-rpc-compat` (both content-superseded) |
| PRs | #1 MERGED · #2 MERGED (fast-forward) · **#3 OPEN** (phase2/architecture→main, MERGEABLE/UNSTABLE) |
| Branch protection | **NONE** (404 on main) · Rulesets: **empty** (repo and org) |
| Workflows | `ci.yml` (quality/db/web) · `security.yml` (CodeQL/dep-review/npm-audit/TruffleHog) · `migrations-guard.yml` — all actions SHA-pinned ✔, read-only token ✔, `pull_request` not `pull_request_target` ✔ |
| CI on `main` | **Has never run.** `main`'s ci.yml is the broken job-level-`hashFiles()` version (rejected at parse, 0 jobs); nothing triggers on push to main by design; the fixed ci.yml exists only on `phase2/architecture` |
| CI on PR #3 head | quality ✓ · web ✓ · **db ✗** (letter-suffix skip → 067 fails, 42883 on `sync_listing_current_bid()`) · CodeQL ✗ + Dependency-review ✗ (settings-gated) · TruffleHog ✓ · npm-audit ✓ (advisory `|| true`) |
| GitHub security features | dependency graph **UNVERIFIED-but-likely-off**, Dependabot alerts **OFF** (404), code scanning **not-configured**, secret scanning + push protection **OFF** — all free on public repos |
| Supabase integration | GitHub app installed; production project `hqycwntp…` git-linked to `main`; **branch status `MIGRATIONS_FAILED`** (2026-08-24T15:47Z); "Deploy to production on push" toggle **UNVERIFIED** (dashboard-only) |
| Migration state | Repo: 84 files (000–070 + 4 timestamped), **11 letter-suffixed** files invisible to the CLI. Production ledger (read-only queried): **79 rows** = 39 `NNN` (001–039) + 40 timestamps; **zero** letter versions; `000/023b/066a/069/070` absent; 36 timestamps map 1:1 to repo 040–068 (content-verified); `043` absent both sides |
| Secrets in history | **CLEAN** — all 2,770 blobs scanned; zero secret values on any origin ref, all history |

---

## 3. Verified Problems (ranked)

### P0 — blocks implementation / could risk production
| # | Problem | Evidence |
|---|---|---|
| P0-1 | **Migration chain not CLI-replayable** — 11 files (`023b, 055b–d, 056a–d, 059b, 060b, 066a`) fail the CLI's `^([0-9]+)_(.*)\.sql$` pattern (verified in CLI v2.75.0 source, `pkg/migration/file.go`); CLI skips them with a stderr notice; fresh replay dies at `067` (SQLSTATE 42883, function defined in skipped `066a`) | CI run logs + CLI source + local repro |
| P0-2 | **Production-linked Supabase branch shows `MIGRATIONS_FAILED`** and the auto-deploy-to-production toggle is **UNVERIFIED**. If the toggle is ON, a future migration-bearing merge to `main` could attempt an auto-apply against production with a broken chain | `list_branches`: `git_branch:"main"`, `status:"MIGRATIONS_FAILED"` @ 2026-08-24T15:47Z. **Verify:** Supabase Dashboard → Project → Integrations → GitHub → deploy toggle |

### P1 — fix before meaningful Phase 2 work
| # | Problem |
|---|---|
| P1-1 | `main`'s ci.yml is the broken version; CI has literally never completed on `main`; no push-to-main trigger exists at all → post-merge main has zero signal |
| P1-2 | No branch protection / rulesets — all checks advisory on a live-money repo; `main` force-pushable and deletable |
| P1-3 | All free GitHub security features disabled on a public repo; CodeQL + Dependency-review structurally fail every PR (code scanning not enabled; dependency graph off) |
| P1-4 | **Public Class-C content** (see §8): 6 admin SQL packs, refund/dispute/recovery playbooks + fraud thresholds, `docs/operations/BETA_EXECUTION_PROMPTS.md`, `docs/security/PHASE_0_EXECUTION.md` advertising still-open findings, `docs/product/APP_STORE_METADATA.md` with live demo-account email+password+phone (path only — no values reproduced here) |
| P1-5 | **Confidential IP Ownership & Assignment Agreement** (48KB docx blob `ziZhyOZe`, initial commit `4ba53b3`) publicly downloadable from history; still tracked at the tips of the two stale branches |
| P1-6 | Zero executable DB tests — RLS/grant/guard/RPC boundary fully untested; the 116 vitest tests are pure-TS money-logic mirrors |
| P1-7 | `PHASE_2_MIGRATION_HISTORY_RECONCILIATION.md` §6a is **unexecutable as written**: `supabase migration repair` hard-rejects non-integer versions, so its 11 letter-version commands fail; §7's expected end-state still lists letter versions — must be regenerated post-rename |
| P1-8 | PR #3's description is false ("Docs-only … no code"): it carries 22 docs **+ 1 workflow + 9 code files** (all verified behavior-neutral, but the description must say so) |
| P1-9 | `transfers.stripe_transfer_id` has **no unique index** (verified in migrations AND live prod catalog) — the same Stripe transfer id can be recorded on two rows; a money-hygiene gap to close with an additive migration in the 076+ series |

### P2 — engineering hygiene
npm audit posture: root = 2 critical + 15 high, all transitive in the Expo/metro toolchain (full clear needs `expo@57` major; several clear via `npm audit fix`); **web = 6 high, `next` is a direct prod dep — fix is the non-major patch `next@16.3.3`** · `security.yml` npm-audit is `|| true` (cannot block) · Supabase CLI `version: latest` in the db job (unpinned) · CodeQL `MissingPushHook` (no push-to-main analysis; Security-tab baseline only via weekly cron, first 2026-08-31) · duplicate/overlapping permissive policies left by 070 (3 SELECT on profiles incl. `USING(true)` legacy, 3 UPDATE on listings, 5 SELECT on transfers) — advisor noise/drift hazard · `payments` has no column-guard trigger (amount/status freely mutable by any service-role path) · repo bloat: 49MB pitch-deck PDF + 62MB screenshots tracked; `.gitignore` intent bypassed by force-adds (`backups/pre_039_schema_snapshot.md`, `docs/brand/snatch-it-deck-upgrade.md`, `.pdf` missed by md-only pattern) · production identifiers (project ref, Stripe acct id, admin UUID, listing/transfer UUIDs) scattered across tracked docs · stale `042` header says "DRAFT — NOT APPLIED" inside the applied chain · `supabase/migrations-pending/043_*.sql` tracked + a second untracked 043 draft in the mobile worktree.

### P3 — cleanup
`.claude/settings.local.json` + `launch.json` tracked (leak nothing actionable — verified: 5-entry Bash allowlist + localhost dev-server config — but shouldn't be public) · `web/.env.example` `NEXT_PUBLIC_SITE_URL=https://snatchti.com` likely a typo of the brand domain (**UNVERIFIED** — check DNS/Vercel) · no LICENSE (public repo = "all rights reserved"; may be intentional) · CLAUDE.md is 11 bytes (`@AGENTS.md` include only) · AGENTS.md good but stale vs Phase-2 governance · superseded audit pairs unarchived · ~120MB local dangling blobs (never pushed; `git gc --prune` locally) · local unpushed `94b3be7` on mobile branch fully superseded — do not push.

---

## 4. Migration Ledger Diagnosis (the P0, in full)

**Facts (all verified against CLI source + live prod ledger):**
- The CLI's filename pattern is `^([0-9]+)_(.*)\.sql$` — the version is the leading digits, underscore required immediately after. `055b_…` does not match → the file is skipped (stderr notice, non-fatal), on every CLI version including the hosted paths.
- **The version comparator is LEXICOGRAPHIC STRING order in every ordering-bearing surface** — Go CLI v2.75.0 (`FindPendingMigrations` string `<`; `fs.ReadDir` name sort; `ORDER BY version` on a text column) and the new TS CLI (`legacyCompareMigrationVersions`, documented "Lexical version order"). **The feared "0551 as integer = 551 > 070" hazard does not exist in any code path.**
- Production ledger: 79 rows; `001–039` are `NNN` (aligned); repo `040–068` exist in prod as **36 timestamp versions** (1:1 content-verified, including the three scrambled labels); the 4 website-form timestamps align; `000, 023b, 066a, 069, 070` have **no prod rows** (their objects exist via Gate-2's by-content application); **zero letter versions exist in prod** — so renaming repo files rewrites nothing production ever recorded.
- `supabase migration repair` validates versions with `Atoi` → letter versions are **unrepairable**; the reconciliation doc's §6a must be regenerated with the post-rename versions.

**Normalization design (proposed — approve before any execution):**
1. **Rename the 11 files** to pure-numeric versions that sort lexicographically between their neighbors: `023b→0231`, `055b/c/d→0551/0552/0553`, `056a/b/c/d→0561/0562/0563/0564`, `059b→0591`, `060b→0601`, `066a→0661`. Proven ordering: `"055" < "0551" < "0552" < "0553" < "056"`, all `< "070"`, all `< "2026…"`. Content untouched — `git mv` only.
2. **Migrations-guard one-time exemption**: the guard (verified logic) fails the rename PR on its modify/delete/rename check (`--diff-filter=MDR` catches R100). Exemption = in the SAME PR, amend the guard with an explicit allowlist of exactly these 11 old→new pairs (exact-match, R100-only); a follow-up PR deletes the allowlist (touches only `.github/workflows/`, so the guard doesn't fire), restoring full strictness. **No permanent bypass remains.**
3. **Regenerate the repair plan** with new versions: 41 × `--status applied` (now all-numeric: `000, 0231, 040…0661, 069, 070` equivalents) + 36 × `--status reverted` (the superseded timestamps). All ledger-only INSERT/DELETE on `supabase_migrations.schema_migrations` — no DDL, no schema change.
4. **Execution order (one owner-supervised window):** confirm Supabase deploy-toggle OFF → merge rename PR → run repair commands → `supabase migration list` shows repo↔prod 1:1 → `supabase db push --dry-run` shows **zero pending** → CI `db` job green on a fresh replay → follow-up PR removes the guard allowlist.
5. **Verification queries:** `SELECT count(*) FROM supabase_migrations.schema_migrations;` (expect 84) · list diff vs `ls supabase/migrations` (expect empty) · `db push --dry-run` (expect nothing).
6. **Rollback:** the repair is ledger-only and symmetric — inverse `repair --status reverted/applied` commands restore the prior 79-row ledger exactly; the file renames revert with `git revert`. **Failure behavior:** any repair command failing mid-run leaves a mixed ledger — the runbook must record before/after row sets so the inverse is mechanical. **Owner approval point:** before step "run repair commands".
7. **UNVERIFIED (accepted residuals):** byte-parity of prod schema vs a fresh replay (verifiable only with a throwaway DB — the CI db job becomes exactly this check post-rename); Postgres collation of the version column (irrelevant for pure-ASCII digits, all collations agree — confirm with `SELECT datcollate FROM pg_database` if paranoid).

---

## 5. CI Diagnosis (per job)

| Job | Tests | Current result | Cause class | Remediation |
|---|---|---|---|---|
| quality (tsc/lint/vitest) | mobile TS + lint + 116 unit tests | ✓ on PR #3 head; **cannot run on main** (broken workflow file there) | code (fixed on branch) | merge PR #3 |
| db (fresh replay) | full chain on fresh local stack | ✗ at `067` | **repo content** (letter-suffix files) | §4 normalization; then make REQUIRED |
| web (Next build) | web/ build w/ CI placeholders | ✓ on PR #3 head | fixed on branch | merge PR #3 |
| migrations-guard | append-only + monotonic | ✓ (paths-triggered) | sound | keep; one-time §4 exemption |
| CodeQL | js-ts advanced workflow | ✗ "code scanning is not enabled" | **GitHub settings** | enable Code scanning → **Advanced** (NOT default setup — would duplicate-analyze); add `push: branches: [main]` trigger (CodeQL itself flags `MissingPushHook`) |
| Dependency review | fail-on-severity: high | ✗ "dependency graph not enabled" | **GitHub settings** | enable Dependency graph (+ Dependabot alerts); job then works on public repo — **no GHAS needed** |
| npm audit | root + web, `--audit-level=high \|\| true` | ✓ (by construction) | policy | keep advisory until triage: apply `next@16.3.3` (prod, non-major) + `npm audit fix` batch now; `expo@57` major deferred to a planned upgrade; then drop `\|\| true` for **prod-scope high/critical** with an allowlist file |
| TruffleHog | verified secrets only | ✓ | — | keep; enable GitHub secret scanning + push protection as the platform layer |
| Also | | | | Pin the Supabase CLI: `supabase/setup-cli` with `version: 2.75.0` (the locally proven version); upgrade policy = deliberate PR bumping the pin + green db job; same version documented in README/CLAUDE.md for local dev |

---

## 6. Security Diagnosis

- **History secret scan: CLEAN** (all 2,770 blobs, 25+ value patterns, JWT payload decoding). Only the **anon** JWT (role=anon, public-by-design) in `eas.json` + a removed script. No rotation of platform credentials required. **UNVERIFIED residuals:** whether the anon/publishable keys are the currently-active ones (dashboard check), and GitHub-side caches of force-pushed commits (none known; a GitHub-API TruffleHog run would close it).
- **Live demo-account credentials** in `docs/product/APP_STORE_METADATA.md` → **rotate the account password now** (it's public), then redact the doc (path-only reporting; values not reproduced here).
- **Confidential IP agreement in history (P1-5):** options — (a) take repo private (hides it immediately; history intact), (b) stay public → requires **history rewrite** (`git filter-repo` removing the blob + force-push all branches + delete stale branch tips) — disruptive and still doesn't un-ring the bell for anyone who already cloned. Either way it has been exposed; owner should assess with counsel whether that matters for this document.
- **GitHub settings to enable** (all free on public; §11 has the exact clicks): Dependency graph · Dependabot alerts (+ optional security updates) · Code scanning (Advanced) · Secret scanning + Push protection.
- Workflow hygiene is genuinely good: SHA-pinned actions, least-privilege token, correct event types.

## 7. Branch / PR Diagnosis

| Branch | Classification | Action (owner, later) |
|---|---|---|
| `main` | authoritative | keep; protect (§13) |
| `phase2/architecture` | PR #3 head, 14 unique commits | keep until merge; delete after |
| `phase0/lockdown` | == main (PR #2 FF) | delete |
| `feature/web-accounts-foundation` | ancestor of main (PR #1) | delete |
| `fix/edge-transfer-rpcs` | content-superseded (edge-file diff vs main EMPTY) | delete (optional archive tag) |
| `mobile/profile-rpc-compat` | content-superseded (residual = comments/wrapping only); local `94b3be7` unpushed & superseded — **do not push**; carries untracked 043 draft + the docx at its tip | delete (optional archive tag); locally discard |

**PR #3:** MERGEABLE/UNSTABLE; failing checks are all pre-existing/settings-gated, none caused by the PR. **Recommendation: keep the code commits in it** (review-driven, line-verified behavior-neutral; splitting = rebase churn with no safety gain) **and fix the description** — corrected text drafted in the branches-inspection evidence file. Do not merge until the Supabase deploy toggle is confirmed OFF (it touches no migrations, but confirm anyway as a standing precondition).

## 8. Public Repository Risk Review — and the visibility decision

Classification (full lists in evidence): **Class C (remove from public):** the 6 admin SQL packs, refund/dispute SOPs, DAY2 recovery plan + deployment guide, DAY9 Stripe SOP, `docs/operations/BETA_EXECUTION_PROMPTS.md`, demo creds inside `docs/product/APP_STORE_METADATA.md`, `backups/pre_039_schema_snapshot.md` (force-added past .gitignore). **Class B (private docs repo):** all audit/incident reports (incl. `docs/security/TICKET_CREDENTIAL_AUDIT.md`'s "zero credential infrastructure" admission and `docs/security/PHASE_0_EXECUTION.md`'s open-findings list), launch/beta ops, product/design internals, the 49MB pitch deck, **and the entire Phase-2 constitution/spec corpus** (defense-forward and design-only, but it maps unbuilt systems and unreleased strategy — bounded attacker value, zero marketing value while private-build). **Class A (fine public):** source trees, migrations, edge functions (env-based secrets), brand assets, README/AGENTS/CLAUDE, BRANCHES.md.

**Decision the owner must make first — and my recommendation:** unless being public serves a deliberate goal *today*, **make the repository PRIVATE now**. One click, instantly reversible, resolves P1-4/P1-5 exposure and the docx-in-history problem without a history rewrite, and costs only the free security features — which **remain free for private repos in the case of Dependabot/dependency graph** (CodeQL/secret-scanning would need GHAS or going public again later, after the docs restructure makes the tree clean). Going public again later — with `docs/` split to a private repo — is a fine end-state. If you choose to STAY public: the Class-C removals + demo-cred rotation happen immediately, the docx requires a history rewrite decision, and the docs restructure (§9) becomes urgent rather than hygienic.

## 9. Repository Structure / Documentation Cleanup Plan

Adopt (from the docs inspection): `docs/{architecture/(canonical specs+constitutions+_governance+_superseded), operations/, security/, product/, archive/, brand/}` — with **operations/security/product/brand moving to a private `snatchit-internal` repo** if this repo stays public (or staying as `docs/` subtrees if it goes private). Canonical set = the frozen constitutions + Phase-2 specs + `ARCHITECTURE_FREEZE.md` + `docs/architecture/SNATCH_IT_ENGINEERING_STANDARDS.md` + `AGENTS.md`. Superseded audit pairs → `archive/`. **Link integrity:** the execution protocol and every spec's "Binding inputs" cite bare root paths — any move must rewrite those references in the same PR (mechanical, listed in evidence). Remove the 49MB PDF + shrink screenshots (git-lfs or private repo). Root .md count target: ~54 → **≤10**.

## 10. Claude / Agent Instruction Improvements

- **CLAUDE.md today is 11 bytes** (`@AGENTS.md`). **AGENTS.md** is a good deployment constitution but predates Phase-2 governance (no freeze pointer, stale "mobile frozen" framing).
- **Hierarchy:** AGENTS.md = agent-neutral constitution (deployment + operating discipline + a new top "Authority order" block pointing at ARCHITECTURE_FREEZE); CLAUDE.md = `@AGENTS.md` + Claude-specific rules. No duplicated rule text.
- **Proposed CLAUDE.md contents** (full draft in evidence file §5): authority order (production reality → freeze+constitutions → specs → standards → code → old audits) · STOP-if-implementation-contradicts-design (amendment, never silent fix) · migrations append-only, never apply to production without the owner gate, never flip feature flags, never invent schema (read the physical spec first) · money/custody = SECURITY DEFINER RPCs only, actor = `auth.uid()` · commands (typecheck/lint/test/build/db replay + pinned CLI version) · **definition of done = link to green CI evidence, never a claim** · PR structure (one package per PR, description template, forbidden-files list) · stop-and-ask triggers (payments/transfers/refunds/payouts/ownership/migration history/prod data ⇒ owner approval + rollback + verification query) · no secret values ever · docs map.

## 11. GitHub Settings Plan (exact, owner clicks)

1. **Decide visibility** (§8). Then, in Settings → Advanced Security / Security & analysis: enable **Dependency graph**, **Dependabot alerts** (+ optional security updates), **Code scanning → Set up → Advanced** (keeps the existing workflow; do NOT pick Default setup), **Secret scanning** + **Push protection** (public repos; if private, these two need GHAS — skip until re-public).
2. Settings → General: disable force-push-friendly defaults implicitly via the ruleset (§13); enable "Automatically delete head branches" (post-merge tidiness).
3. Supabase Dashboard → Integrations → GitHub: **confirm "Deploy to production on push" is OFF** and screenshot it for the record (P0-2). Keep OFF until the §4 repair completes.
4. Later (Stage 3): create a `production` GitHub Environment with required reviewer = owner, for any future workflow that applies migrations.

## 12. Required Status Check Plan (staged)

- **Stage 1 (with the first ruleset, checks green today on the fixed workflow):** `Typecheck / Lint / Unit tests` · `Web build (Next.js)` · `Immutability + ordering` (migrations-guard; paths-triggered) · `Secret scan (TruffleHog)`.
- **Stage 2 (immediately after the §4 ledger normalization lands):** add `Migrations apply cleanly (fresh DB)` — this becomes the crown-jewel gate.
- **Stage 3 (after settings enabled + one clean run each):** add `CodeQL` and `Dependency review`; add the pgTAP/RLS job (§below) once Stage-B tests exist; move npm-audit from advisory to enforcing for prod-scope high/critical with an allowlist file.

## 13. Branch Protection / Ruleset Plan (right-sized for 1–3 engineers)

One **ruleset** on `main`: require PR before merge (**0 required approvals** while solo — the gate is CI, not a deadlocked self-review; raise to 1 at team ≥2) · required status checks per §12 + require branch up-to-date · require conversation resolution · block force pushes · block deletions · **linear history** (squash/rebase only — keeps migration ordering legible) · admin bypass allowed-with-audit (solo-founder escape hatch, every use logged). **Skip:** signed commits, CODEOWNERS, merge queues — ceremony without payoff at this size.

## 14. Migration Normalization Plan — see §4 (kept there in full; it is the P0)

Preconditions: deploy toggle confirmed OFF · PR #3 merged (so main's CI works) · owner window scheduled. Files: exactly the 11 renames listed. Ledger: regenerate §6a with numeric versions; 41 applied + 36 reverted. Staging verification: CI fresh replay green. Production verification: `migration list` 1:1 + `db push --dry-run` zero pending. Rollback: inverse repair + `git revert`. Guard: same-PR exact-pair allowlist, removed in the follow-up PR.

## 15. Pull Request Roadmap

| PR | Name | Changes | Forbidden | Merge condition |
|---|---|---|---|---|
| **#3** (open) | Phase-2 architecture baseline + CI health | as-is + **corrected description** | any new migration | Stage-1 checks green; owner review |
| **#4** | Repo hygiene & security posture | .gitignore additions (`.claude/settings.local.json`, launch.json), delete tracked local-settings, docs restructure per §9 (+ link rewrites), CLAUDE.md/AGENTS.md rewrite, demo-cred redaction, BRANCHES.md update, LICENSE decision | `supabase/**`, app code | after visibility decision executed |
| **#5** | Migration ledger normalization (one-time event) | 11 renames + guard allowlist + CLI pin (`2.75.0`) + regenerated repair runbook + reconciliation-doc update | anything else | owner-supervised window; §4 sequence; **owner sign-off required** |
| **#5b** | Guard restoration | delete the allowlist | anything else | immediately after #5 verified |
| **#6** | DB correctness & security gate | Stage A (db lint + drift snapshots) + Stage B pgTAP suite (9 files: RLS smoke, profiles column grants 052/068, anon/authenticated write denials, transfers guard 055/056b/056c, payout idempotency + dispute refusal 056d, one-succeeded-payment uniqueness, admin self-insert denial, webhook lease 064) + CI job | `supabase/migrations/**` (tests live in `supabase/tests/`) | pgTAP green on fresh replay |
| **#7** | `076_create_phase2_schemas_and_grants` | first Phase-2 package per the execution protocol | everything outside the package | **GO gate passed (§16)** |
| **#8+** | `077…` | one package per PR (pair only true units, e.g. 088+089 bridge) | — | protocol per package |

Every money/custody-touching PR from #5 onward carries: rollback strategy, verification query, failure behavior, owner approval point (Production Safety rule, §23 of the brief — honored in the templates above).

## 16. Phase 2 GO / NO-GO Gate

GO to author-and-apply 076 only when ALL are true:
1. PR #3 merged (freeze + working CI on main) · 2. Ruleset live with Stage-1 checks required · 3. §4 normalization executed: prod ledger ↔ repo 1:1, `db push --dry-run` zero pending · 4. CI `db` job GREEN on main · 5. Supabase CLI pinned (CI + docs) · 6. Supabase deploy toggle confirmed OFF (screenshot) · 7. Security settings enabled per the visibility decision + one clean CodeQL run (if public) · 8. No unresolved P1 exposure (Class-C removed or repo private; demo creds rotated) · 9. DB test gate (PR #6) green · 10. `phase2/implementation` cut from post-merge main · 11. Owner explicit GO.

## 17. Phase 2 Implementation Roadmap (post-stabilization)

Unchanged from the ratified plan: packages `076→091` per `docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md`, executed under `docs/architecture/_governance/PHASE_2_ENGINEERING_EXECUTION_PROTOCOL.md` (read→plan→invariant analysis→tests-first→smallest package→specialist review→verification→adversarial review→staging→gated production→document→stop). Native feature flags seeded OFF; Gate P before first credential; Gate M before resale; Gate L before international. Add to the 076-series backlog: the `transfers.stripe_transfer_id` unique index (P1-9) and the 070 duplicate-policy cleanup (P2) as additive hygiene migrations.

## 18. GitHub Copilot Recommendation

**NO — not now.** Claude Code already covers authoring, review, and refactoring; CodeQL (free once enabled) + the ruleset + the execution protocol's adversarial-review stage deliver more safety per dollar than Copilot review; completions add little for a solo founder already in Claude Code. **Revisit when** a second engineer joins who wants in-IDE completions, or if Copilot Autofix for CodeQL alerts would measurably shorten security triage. Decision: no purchase; re-evaluate at team ≥2.

## 19. Owner Actions (you click)

1. **Decide visibility** (recommendation: private now) — Settings → General → Danger Zone.
2. **Supabase Dashboard:** confirm GitHub-integration "Deploy to production on push" = OFF; screenshot.
3. **Rotate the Apple-review demo account password** (published in `docs/product/APP_STORE_METADATA.md`).
4. GitHub security toggles per §11 (per the visibility decision).
5. Create the `main` ruleset per §13 (or approve and I'll do it via API when authorized).
6. Approve PR #3 merge; later, approve the §4 repair window and run/authorize the repair commands.
7. Decide the IP-document question (counsel): accept exposure vs history rewrite.
8. Enable HIBP (Supabase Auth) — last standing advisor WARN.
9. Optional: archive tags before branch deletions; delete the 4 stale branches after PR #3 merges.

## 20. Claude Actions (safe for me to perform once you approve the roadmap)

Correct PR #3's description text · author PR #4 (hygiene/docs restructure + CLAUDE.md/AGENTS.md + .gitignore) · author PR #5/#5b (renames + guard allowlist + CLI pin + regenerated runbook — **execution of repair commands stays with you**) · author PR #6 (pgTAP suite + CI job) · create the ruleset via API if you prefer delegating (you retain admin bypass) · local-only tidy: prune stale worktrees, `git gc` the dangling blobs, delete the superseded local 043 draft and unpushed `94b3be7` (with your OK).

## 21. Final Recommended Order of Operations

```
STEP 1  — OWNER: visibility decision (recommend: private now) + Supabase deploy-toggle OFF (screenshot) + rotate demo password
STEP 2  — OWNER: GitHub security toggles (per visibility) ; CLAUDE: fix PR #3 description
STEP 3  — MERGE PR #3 (main gets working CI + the frozen baseline)
STEP 4  — OWNER: create main ruleset (Stage-1 required checks)   [or delegate to Claude via API]
STEP 5  — CLAUDE: PR #4 hygiene & docs restructure → merge
STEP 6  — CLAUDE: PR #5 ledger normalization authored ; OWNER: supervised window — merge, run repair, verify (list 1:1, dry-run zero, CI db GREEN) ; PR #5b restores guard
STEP 7  — Stage-2 required check: db job required on main
STEP 8  — CLAUDE: PR #6 DB test gate (pgTAP Stage A+B) → merge → Stage-3 checks phased in
STEP 9  — GO/NO-GO gate review (§16) ; OWNER: explicit GO
STEP 10 — cut phase2/implementation ; begin PR #7 = migration 076 under the execution protocol
```

---

**STOP.** This roadmap is delivered for approval. No commits, branches, settings changes, merges, or Supabase actions have been made. Awaiting your decisions on: (1) visibility, (2) the §4 normalization design, (3) the PR sequence, (4) which §19 owner actions you'll take vs delegate.

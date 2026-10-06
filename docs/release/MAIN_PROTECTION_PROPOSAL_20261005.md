# Repository protection proposal: `main` and the release/deploy branches (A, 2026-10-05)

**A proposal only. No setting was changed and no PR was closed** (owner, 2026-10-05). Every fact below was read on
2026-10-05 through the GitHub API (read-only).

## 1. Measured state, which corrects the integration plan

**`main` IS protected, by a repository ruleset, not by classic branch protection.**
- The classic endpoint (`branches/main/protection`) returns 404 "Branch not protected". That is what D and A read in
  September.
- The ruleset endpoint shows **`main-protection`** (id 21624091), active since 2026-08-27, targeting
  `~DEFAULT_BRANCH`, **with no bypass actors** (`current_user_can_bypass: never`).

| Rule | Setting |
|---|---|
| `deletion` | blocked |
| `non_fast_forward` | force-push blocked |
| `required_linear_history` | on |
| `pull_request` | PR required; **0** approvals; **allowed merge methods: rebase, squash** (no merge commits); extra approval for unattributed changes on |
| `required_status_checks` | `Immutability + ordering`, `Migrations apply cleanly (fresh DB)`, `Typecheck / Lint / Unit tests`, `Web build (Next.js)`, `Secret scan (TruffleHog)`; strict policy **off** |

**Other facts:**
- Repository: public, user-owned (`SnatchIt-app`).
- Collaborators: one account, `SnatchIt-app` (admin). Every session authors as it.
- **No rules at all** on `release/production-gate-20260918`, `release/candidate-20260918`, `admin/operating-console`
  (the console's deploy branch) or `feature/web-accounts-foundation`, the web's production branch, **where any push
  deploys**.

**Consequences for FINAL_INTEGRATION_PLAN_20260925.md**, corrected in the plan in the same commit:
1. **P0's premise was wrong.** It said "nothing mechanical stops those merges". The open PRs into `main` measured today:

   | State | PRs |
   |---|---|
   | **Blocked** by failing required checks | #43 (guard and fresh-DB both fail), #11 (fresh-DB fails) |
   | **Drafts**, unmergeable until marked ready | #54 (required checks pass, so one "ready" and one click from a 516-file squash), #87 |
   | **Mergeable now** with one click (`CLEAN`) | dependabot #53, #57, #59, #60, #61, #96 |
   | Unknown | dependabot #9 |

   The residual risk is a deliberate action, not an unguarded door. Repository hygiene stays worth doing (§3).
2. **S7, the gate merged into `main` with a merge commit, is not allowed by the current ruleset.** Linear history is
   required, and only rebase or squash are allowed. This becomes owner decision PR-3 below.

## 2. Proposed settings (the owner applies them in the GitHub UI; A changes nothing)

**PR-1. Required status checks on `main`.**
- **Keep** the five above.
- **Add now:** `Dependency review` (security.yml; runs on PRs to `main`; passed on #96).
- **Add after S7 lands:** `Admin console (Next.js)` and `Deno type-check (edge functions)`. These jobs exist only in the
  gate's `ci.yml`, so requiring them before S7 would block every other PR into `main` for ever.
- **Never required:**
  - `npm audit (advisory, non-blocking)`: advisory by design.
  - CodeQL: keep it as code-scanning alerts. Its check name is duplicated oddly on PRs:
    `CodeQL (javascript-typescript) (javascript-typescript)`.
  - Any Vercel check: external, and cancelled or skipped by the Ignored Build Step.
  - `Supabase Preview`: external. Its appearance on a `main` commit is the AUTODEPLOY signal, never a gate.

**PR-2. Strict policy on:** a PR must be up to date with `main` before merging, so the checks ran against the merge
result. PR volume is low, so the cost is small.

**PR-3. Merge method for `main`, the decision S7 needs.**
- **Recommended:** allow **merge commits** (keep squash and rebase too) and **turn off required linear history**.
  - Every execution record cites gate shas (`5b255838`, `e73553d2`, `037092f0`, …), and a merge commit puts them on
    `main`.
  - A squash would put none of them there, and every later gate → `main` merge would re-present history `main` has
    already absorbed.
- **Alternative,** if you prefer linear history: squash S7 into one commit. The lineage then stays only on the gate
  branch, and `main` holds the content but not the cited commits.
- Rebase is not proposed: it rewrites about 900 commits, including merge commits.

**PR-4. Reviews: keep 0 required approvals for now.**
- The repository has one collaborator account, and GitHub does not count an author's approval of their own PR. So a
  required approval of 1 would block every merge.
- Independent review stays the recorded A/D PASS records.
- **Improvement:** add a second GitHub account for reviewing, then require 1 approval with stale reviews dismissed and
  the last push approved.

**PR-5. Bypass: none, as now.**
- Emergency procedure: the owner sets the ruleset's enforcement to *Disabled* with a recorded reason, acts, and
  re-enables it.
- No standing bypass actor.

**PR-6. Keep** the deletion and force-push rules.

**PR-7. New rulesets for the release and deploy branches.**

| Branch | Why | Proposed rules |
|---|---|---|
| `release/production-gate-20260918` | the production line (§1A of the plan) | no deletion, no force-push; PR required; required checks = PR-1's set **including** `Admin console (Next.js)` and `Deno type-check (edge functions)`; **merge commits allowed** (S1–S5 use them) |
| `feature/web-accounts-foundation` | **a push here deploys the live web** | no deletion, no force-push; PR required; `Web build (Next.js)` required |
| `admin/operating-console` | the console's deploy branch (builds are pinned to `ab3e17f`) | no deletion, no force-push; PR required |
| `release/candidate-20260918` | the records line | no deletion, no force-push (direct pushes of records continue) |

## 3. Stale-PR dispositions: the evidence for each proposed closure

**Method.** For each PR:
- whether its head is an ancestor of the gate `037092f0`;
- a per-file blob comparison of the PR head against the gate, over the files the PR changes against its merge-base with
  its own base;
- the merge state, read today.

**Recoverability.**
- **Close only, never delete a branch.**
- GitHub keeps `refs/pull/<n>/head` after closing.
- Recommended before closing: an `archive/pr-<n>` tag at each head below (a git write that needs your go).

| PR | Head @ sha → base | Merge state today | Head in gate? | Evidence | Disposition |
|---|---|---|---|---|---|
| #54 | `fix/payments-reliability` @`a77d3686` → main | draft; required checks pass | **yes** | 516 files: 454 identical to the gate, 62 with later gate edits. All 39 migration files identical to the gate's, all in the recorded ledger | **close**: fully in the gate; reaches `main` by S7 |
| #43 | `chore/admin-relist-rpc` @`fba3b515` → main | **blocked** (guard and fresh-DB fail) | no | its `20260902003623` blob (`84ee6984`) ≠ the gate's (`5b580551`). The version is in the recorded ledger. Which copy matches production's body is not established | **close**: not the vehicle; the gate copy travels in S7 |
| #87 | `fix/payout-fairness-v38-backport` @`f5e91e74` → main | draft | no | a `main`-based hotfix deployed as v39 (SS:1376); superseded by the gate's v40/v41, which carry the fairness predicates | **close**; keep the branch (v39's source) |
| #11 | `repo/purge-obsolete-admin` @`eec7a717` → main | **blocked** (fresh-DB fails) | no | 48 files (41 deleted, 7 modified); **the gate still has all 41**. Never incorporated | **close as stale**; redo any doc cleanup against the current tree |
| #56 | `publish/ui-v2-integration` @`597533e1` → payments-converged-rc | draft | yes | 183 files: 110 identical, 72 later edits, 1 later deleted | **close** |
| #58 | `fix/121-…` @`030a922b` → admin/operating-console | draft | yes | 3/3 identical (121 in the gate) | **close** |
| #62 | `fix/125-…` @`fc4f1130` → admin/operating-console | draft | yes | 3/3 identical (125 in the gate) | **close** |
| #63 | `fix/126-…` @`db2f95f1` → release/convergence-135 | draft | yes | 4 identical; test 193 differs (the gate has the CI-safe version) | **close** |
| #64 | `fix/l1-edge-coupling` @`5bcea692` → fix/127-… | draft | yes | 1 identical, 4 later gate edits | **close** |
| #70 | `fix/132-pending-before-intent` @`74a43712` → the candidate | draft | yes | 8 identical, 3 later edits; 132 applied (MAN #8) | **close** |
| #52 | `feature/venue-native-and-product-v2` @`9aed686c` → phase2/consolidation | open | no | 27 files absent from the gate, **all records** (B's PFA-18C execution records, `PHASE2_PRODUCTION_STATE_20260912.md`) | **keep open**: venue integration is separate, and the records exist only there |
| #9, #53, #57, #59, #60, #61, #96 | dependabot → main | #53/#57/#59/#60/#61/#96 **CLEAN**; #9 unknown | — | routine dependency updates; no migrations | **keep open, do not merge before S7.** After the freeze, review each against the release line |
| #89 | `admin/refund-classification-console` @`3dab1614` → admin/operating-console | draft | — | conditional on O-R3 (plan §6.1 D8) | **keep open** |
| #94, #95 | the 150/151 vehicles | drafts; D PASS | — | the release work | **keep open** |

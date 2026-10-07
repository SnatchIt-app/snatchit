# Reconciled configuration for MM-1 (D, 2026-10-06)

**One configuration, not two sheets.** A's `docs/release/EXECUTION_SHEET_20261006.md` is the single sheet.
This document is the verification behind the merge-method half of it and the reconciliation of the three
lanes; **D's own execution sheet is retired as a separate sheet** and kept only as the record of what was
measured. Everything below is either measured today or marked as not established.

**Nothing here is authorised.** No settings change, no deploy-branch push, no merge, no production action.

## 0. Three action classes, kept distinct

Every row below belongs to exactly one, and each needs its own authorisation:

| Class | What it is | Visible effect |
|---|---|---|
| **Backup push** | putting an already-reviewed commit on the remote, on a branch nothing deploys from | CI runs; nothing ships |
| **Protection change** | creating or editing a ruleset | changes what is allowed; ships nothing |
| **Production deployment** | the pin change plus the explicit deploy, or a push to a deploy branch | users see it |

They are never combined in one step, and a backup push is never the thing that deploys.

## 1. Merge methods (MM-1)

Measured 2026-10-06: repository-level `allow_merge_commit`, `allow_squash_merge`, `allow_rebase_merge` are
**all true**; `allow_auto_merge` false. Exactly **one** ruleset exists — `main-protection` (21624091) on
`~DEFAULT_BRANCH`, `allowed_merge_methods: ["rebase","squash"]`, `required_linear_history`, no bypass
actors.

| Scope | Allowed methods | Linear history | Note |
|---|---|---|---|
| Repository | **unchanged — leave all three enabled** | — | the toggle is global; disabling merge commits to force squash-to-`main` would break the gate |
| `main` | `["squash"]` **or** leave 21624091's `["rebase","squash"]` as is | **required** (already) | S7 uses squash; narrowing to squash-only removes the chance of picking rebase by hand |
| gate | **`["merge"]`** | **must NOT be required** | the owner's preference. Each S-step stays a distinguishable merge commit with both parents, so integration ancestry survives. `required_linear_history` and merge commits are mutually exclusive — do not set both |
| `feature/web-accounts-foundation` | **`["merge"]`** | not required | one method, so the landing method cannot drift; preserves the cherry-picked commits and their `(cherry picked from …)` trailers |
| `admin/operating-console` | **`["merge"]`** | not required | see §3 |
| records line | unrestricted | not required | direct pushes of records continue |

Set `allowed_merge_methods` **explicitly** on each new ruleset rather than relying on a default.

## 2. The sync-back, as a helper-branch PR — procedure and trial

**Why a helper branch:** once the gate requires PRs, the sync-back merge cannot be pushed to it directly.
It has to arrive the same way everything else does, through CI and a PR.

**Procedure, immediately after S7 and before anything else lands on the gate:**
1. Branch `sync/main-to-gate-<date>` from the **gate tip**. *(backup push)*
2. Merge `main` into it. Done at this moment the two trees are already identical, so it is trivial.
3. Push the helper branch; CI runs on it. *(backup push)*
4. PR helper → gate, merged with a **merge commit**. *(not a deployment: the gate deploys nothing)*
5. Verify the two properties below before anything else is merged to the gate.

**Trial, run today on the real gate `037092f0` and `main eadd456a`:**

| Step | Result |
|---|---|
| squash gate → `main` (S7) | S tree `e6b9589b…` = the gate's tree |
| merge `main` into the helper | exit 0, helper tree `e6b9589b…` — **unchanged** |
| merge helper → gate, `--no-ff` | exit 0, gate tree `e6b9589b…` — **unchanged** |
| ancestry: `main` → gate | `main` **is** now an ancestor of the gate |
| ancestry: pre-squash gate tip | **still** an ancestor — integration ancestry preserved on both sides |
| new merge-base(`main`, gate) | the squash commit S |
| the next squash, after a later gate edit | exit 0, tree **identical** to the new gate's |

**The two checks to repeat at execution:** the gate's tree is unchanged by the sync-back, and `main` is an
ancestor of the gate afterwards. If either fails, stop — something landed on the gate between S7 and the
sync-back.

## 3. Console: the owner's PR route — and it dissolves PR-8

The owner's sequence is better than D's "release first, protect immediately after", and **PR-8 is
withdrawn**. The sha-unknowability objection only existed because D had pin and push as one step. Splitting
"merge, blocked from deploying" from "pin, then deploy" removes it: after the merge the commit exists and
its sha is known.

| # | Step | Class | Verification |
|---|---|---|---|
| C1 | Create the console ruleset: no deletion, no force-push, PR required, `allowed_merge_methods: ["merge"]` | **protection change** | re-read the ruleset after saving |
| C2 | Push `admin/label-console-release-ff @ efe03fca` as a PR source branch | **backup push** | CI green on it |
| C3 | Merge the PR into `admin/operating-console`. **The existing pin `ab3e17f1` prevents any deployment**: the git build is cancelled | **neither** — merge only | the Vercel deployment for that push reads *cancelled*, and the alias has not moved |
| C4 | Read the resulting merge commit's sha. Verify its `admin/src` and `admin/tests` trees equal the reviewed `f297dab4…` / `6b76588f…` | — | tree comparison, not a diff summary |
| C5 | **With deployment approval:** set the Ignored Build Step pin to that exact sha | **production deployment** (part 1) | read the setting back |
| C6 | Explicitly deploy that exact commit | **production deployment** (part 2) | the new deployment's `gitCommitSha` equals C4's sha; the alias moves to it |

**The supported Vercel action, and whether the ignored-build check affects it — what is established and
what is not.**
- **Established, from the 2026-09-08 record:** the Ignored Build Step is
  `test "$VERCEL_GIT_COMMIT_SHA" != "<pin>"`, exit 0 = skip; it **does** cancel git-triggered builds of a
  non-matching sha, proven live (`dpl_BEGD13gGY1zZLswR76xsU4UpCAMs`). Both existing production deployments
  were made with **`vercel deploy --prod` from a detached worktree** at the target commit — that is the
  project's demonstrated deploy action.
- **Not established:** whether the Ignored Build Step is evaluated for a CLI or API deployment, and what
  `VERCEL_GIT_COMMIT_SHA` holds there. The Vercel MCP tools were unavailable in this session, so this was
  not measured. **It must be confirmed at execution, before C6.**
- **Why the order is safe under either answer.** With the pin already set to the target sha at C5: if the
  check runs and reads the sha from the deployed source, it matches and builds; if the check does not run,
  it builds. The unsafe case is deploying *before* C5 — then an empty or mismatched sha skips the build.
  **So C5 strictly precedes C6 whichever way the unknown resolves.**
- Two candidate mechanisms for C6, to choose at execution once the above is confirmed: a git-source
  deployment of that exact sha (dashboard or API — the ignored-build check certainly applies, which is why
  C5 comes first), or `vercel deploy --prod` from a detached worktree at that sha, which is what the record
  shows working twice.

**If C3–C6 prove impractical**, the bounded exception, in full:
1. Set the pin to `efe03fca`. *(protection-adjacent configuration; ships nothing on its own)*
2. Fast-forward push `efe03fca` to `admin/operating-console` — this builds and deploys. *(production deployment)*
3. **Immediately** create the console ruleset as in C1. *(protection change)*
The exception is exactly one unprotected push, bounded by step 3 in the same sitting, and it is only
justified if the PR route cannot produce a deployable known sha.

**Rollback, either route:** Instant Rollback to the deployment the alias currently serves, then restore the
pin. The record names `dpl_J5Kr4QSBmRjxmJbu2nT7KovSxmsr`, which is a month old — **re-read the alias at
execution** and confirm it still resolves there before relying on it.

## 4. Web: configure, push, observe, require, land

The owner's order, with the measured reasons it works.

| # | Step | Class | Verification |
|---|---|---|---|
| W1a | Create the web ruleset: no deletion, no force-push, PR required, `allowed_merge_methods: ["merge"]`, **no required checks yet** | **protection change** | re-read it |
| W1b | Push the landing branch carrying `fd0da772` — an isolated branch, **not** the deploy branch | **backup push** | nothing deploys: only `feature/web-accounts-foundation` is the web production branch |
| W1c | **Observe** `Web build (Next.js)` on that exact head and confirm it is green | — | the check name string, the conclusion, and the head sha it is attached to |
| W1d | Add `Web build (Next.js)` to the ruleset as the only required check | **protection change** | re-read it |
| W2 | PR the landing branch → `feature/web-accounts-foundation` | — | the required context resolves green on the head |
| W3 | Merge the PR. **This is the deployment** | **production deployment** | the live site serves the new strings |

**Measured facts behind this order:**
- `ci.yml` is `pull_request: branches: [main]` plus `push: branches-ignore: [main]`, identical at the gate,
  at `1765bbeb` and at `fd0da772`. So a PR into the web branch produces **no** `pull_request` run; the
  required context is satisfied by the **push** run from W1b on the same head sha.
- The `web` job has **no job-level condition and no path filter** — it always starts on a qualifying push,
  so the context will appear.
- Exact context string: **`Web build (Next.js)`**, app `github-actions`. Confirmed `success` on the gate
  tip, itself a non-`main` branch and therefore a push-event run.
- `Supabase Preview` and `Vercel Preview Comments` also appear on these commits. Both are third-party apps
  and `Supabase Preview` reports `skipped`. **Not required.**

**If the check does not appear at W1c, diagnose — do not drop it.** In order: was the branch name caught by
`branches-ignore`; did the workflow fail to parse (a malformed workflow yields a 0s "workflow file issue"
and zero jobs, which is how CI silently did nothing during Phase 0); is the job present at that ref. The
rule comes off only if the diagnosis shows the check cannot run on that branch at all, and then it is
replaced, not abandoned.

**One caveat on the check's meaning.** The `web` job starts unconditionally and its steps skip when
`web/package.json` is absent, so on a branch without `web/` it would pass **vacuously**. On the landing
branch `web/` exists, so W1c's green is a real build — but the green proves the rule is satisfiable, not
that any given future branch built anything.

## 5. What this introduces for the owner

- **MM-1 as above**, with one sub-choice: narrow `main` to `["squash"]`, or leave `["rebase","squash"]`.
  Narrowing removes the chance of selecting rebase by hand at S7; leaving it keeps rebase available for an
  unrelated future PR into `main`. **Recommended: narrow to `["squash"]`.**
- **PR-8 is withdrawn.** The console goes through the owner's PR route (§3 C1–C6). The release-first
  variant stays on the shelf as a bounded exception with the three steps written out, used only if C3–C6
  cannot produce a deployable known sha.
- **PR-9 stands, in the owner's stronger form:** the required check is added only after it has been
  observed green on the exact landing head (W1c → W1d), not before.
- **One Vercel fact must be confirmed before C6** — whether the ignored-build check is evaluated for a
  CLI/API deployment. It does not change the order, only whether C5 is strictly necessary or merely prudent.

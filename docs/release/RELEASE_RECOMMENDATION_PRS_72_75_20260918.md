# Release recommendation — PRs #72–#75 (A, 2026-09-18)

**Asked for by the owner:** one consolidated recommendation covering the integration order, the remaining release blockers, and the checks supported only by automated tests. It leaves out the review history, which is in `SPRINT_STATUS_20260917.md`.

**This document authorizes nothing.** PRs #72–#75 stay **draft and do-not-merge** until the owner decides. There is no new build and no production deployment.

## 1. Recommendation

**Two separate steps.**

**Step 1 — integrate into the release branch (recommended now).** Merge the four PRs plus #76 (F-SEC-2, opened 2026-09-18) into **`release/production-gate-20260918`**, in the order in §2.
- Use merge commits, not squash and not rebase, so every reviewed commit id survives.
- ~~This touches no production system. The release branch is not `main`, and nothing deploys from it (§3, B2).~~ **Struck by A after D's review: A had not checked that "nothing deploys from it".** What is established:
  - The release branch is not `main`.
  - The one auto-deploy binding on record, Supabase to `main`, had its `git_branch` cleared to `""` on 2026-08-27 (`DEPLOYMENT_PATHS.md`). That is a record, **not re-read now**.
  - D found that GitHub's deployments API holds no records for either branch, which cannot settle it.
  - **UNVERIFIED:** the production-branch setting of each connected hosted project (the Vercel projects, including `snatchit-web`, which builds previews on these PRs, and the Supabase integration's current `git_branch`).
  - **What settles it:** the owner reads those settings in the dashboards, or authorizes a read. Until then, step 1's "no production effect" is expected, not verified.
  - **SETTLED 2026-09-18** by the owner-authorized read of those settings (§6). **No production deployment and no hosted-database action.** The merge does trigger CI, one Vercel **preview** of `web/`, and a skipped admin build.
- The result is the Build 21 tree, byte for byte, plus one test-title rename (§2).

**Step 2 — production release (not recommended yet).** A production client from this branch is blocked **server-side**:
- production is at migration tip **120**;
- the branch's app calls database functions that exist only in later migrations (§3, B1).
- #72–#75 did not create this dependency. They add no new database call. They inherit it from the branch.

## 2. Integration order

Target: `release/production-gate-20260918`, currently **`6561d1f`**. Keep ruling 6's reference: `6561d1f` stays an ancestor, so F-BIDS-1 is carried unchanged.

| Step | PR | Head | Fixes | Effect on the branch (simulated) |
|---|---|---|---|---|
| 1 | **#72** | `0ca71ff` | F-BID-1, F-HOME-1, F-AVATAR-1, F-DESTRUCT-1, F-XFER-1 (client half), F-XFER-2 (+2-A), F-AVATAR-2 | 19 files, +2222/−73 |
| 2 | **#73**, retargeted from `frontend/batch1b-twin-screens` to the branch after step 1 | `649248a` | F-AVATAR-3 | 2 files, +280/−1 |
| 3 | **#74** | `016d8e2` | F-SEC-1 | 3 files, +281/−17 |
| 4 | **#76 (F-SEC-2)**, retargeted from `frontend/batch1d-security-notice-lock` to the branch after step 3 | `f3cff27` | F-SEC-2, F-SEC-2-A | 2 files, +265/−5 |
| 5 | **#75**, retargeted from `integration/device-verify-20260918` to the branch after step 4 | `0f329c3a` | F-XFER-3, owner decisions 1 and 2 | 8 files, +923/−20 |

**Evidence for this order.** A ran it on a throwaway local copy of the branch. Local branches only; nothing was pushed, and the copy has been deleted.
- **All five merges were clean.**
- Each step's real effect equals that PR's own size.
- **The final tree differs from Build 21's tree (`0f329c3a`) in exactly one place:** `649248a`, #73's last commit. It is test-only: it renames two test titles in `tests/profile-avatar-same-tick.test.ts`. It was not in Build 20 or 21, and it cannot change the app.

**What to expect on GitHub at step 5.** #75's branch carries the Build 20 merge commit, so after retargeting there are **two merge bases**. GitHub may show 12–26 changed files for #75, not 8. The merge's real effect on the branch is the 8 files, as the simulation shows. Check the first-parent diff of the merge commit rather than the PR's file count.

**After each merge:** CI green on the resulting branch commit before the next merge.

**After the last merge:**
- `git diff 0f329c3a <branch head>` must show only the rename.
- Only then is a candidate tag proposed. A tag and any build are separate owner decisions.

**CI already on record:**
- PRs #72–#75: 8 of 9 checks pass, 1 skipped (`Supabase Preview`, which skips when there are no migrations).
- `f3cff27`, from its branch push: 5 pass and `Supabase Preview` skipped. It has never had a PR run, so the PR-only `Immutability + ordering` check has not run on it.
- **#76 (2026-09-18):**
  - `Immutability + ordering` **pass** (a PR run, 22:11Z).
  - The 5 CI jobs **pass**. These are the branch-push run on the identical commit (04:20Z). `ci.yml` runs pull-request events only for PRs into `main`, so for every PR here (#72–#76) CI is the branch-push run.
  - `Supabase Preview` skipped.
  - **`Vercel – snatchit-web` FAILED: "Deployment rate limited — retry in 24 hours".** The preview deployment never ran; nothing about the code failed. CI's own `Web build (Next.js)` job passes. **A retry is a preview deployment, and it is not requested.**

## 3. Release blockers

| # | Blocker | Blocks | What clears it |
|---|---|---|---|
| **B1** | **The production server chain is behind the release branch.** Production is ledger 135, numeric tip **120** (`PHASE2_PRODUCTION_STATE_20260912.md`, per the registry). The branch's app calls functions from later migrations. Verified examples: security notices use `get_my_security_notices` / `mark_security_notices_read`, defined only in **136** (`src/lib/security/notices.ts:22-23`) — the hook F-SEC-1/2 changes. Mark as sent's recovery uses `attach_transfer_evidence`, defined only in **140** (`app/transfer/send/[id].tsx`). **All device evidence ran against the sandbox, which has these (ledger 144).** | any production client build | The owner-gated production apply of the branch's server chain and edge functions, in the `DEPLOYMENT_PATHS.md` order: migrations, then functions. **It is a separate ceremony and outside this recommendation.** |
| **B2** | **AUTODEPLOY-1.** The branch is **818 commits and 68 migration files ahead of `main`**. The integration was disconnected on 2026-08-27 (`git_branch` cleared), but it is **still installed and still reports on PRs against the production project**, one reconnect away. A merge into `main` carrying those 68 files is exactly the path that applied `071` to production in August. | any merge of the branch into `main` | The owner's visual dashboard confirmation that auto-deploy is off (`AUTODEPLOY-VERIFIED-OFF`), and the B1 ceremony. **Step 1 does not touch `main`.** |
| ~~**B3**~~ | ~~F-SEC-2 has no PR.~~ **CLEARED 2026-09-18:** [PR #76](https://github.com/SnatchIt-app/snatchit/pull/76) opened as draft/do-not-merge, base `frontend/batch1d-security-notice-lock` (`016d8e2`, #74's head), head `f3cff27`; 3 commits, 2 files, +265/−5. | — | — |
| **B4** | **No production build of this tree exists.** The `production` profile (`pk_live`, production project) has never built it. **App Store release status remains unverified**; the owner's restriction stands. | release | B1, then an owner-authorized production build and store steps. |
| ~~**B5**~~ | ~~Step 1's "no production effect" is unverified.~~ **SETTLED 2026-09-18 by an owner-authorized read of the settings (no setting changed): merging into the release branch triggers no production deployment and no hosted-database action.** See §6. | — | — |

**Still DEFERRED (owner, 2026-09-18: "Keep F-SEC-3, F-SEC-1-B and the unknown-outcome wording deferred and documented"):** **A's recommendation: none blocks step 1. Decide the third before any production build, because its copy ships in that build.**
- **F-SEC-3** (LOW, pre-existing): the read path swallows a thrown error.
- **F-SEC-1-B:** uniqueness assertions for 1b/1c. Test-only.
- **The unknown-outcome copy** for security actions.

**Not blockers, recorded so they are not mistaken for fixed:**
- Unstarted: F-BID-3, F-LAYOUT-1, F-LAYOUT-2.
- **F-AVATAR-4** is deferred by the owner, with no cleanup.
- The server-side transfer-expiry and delivery-enforcement decision is separate. None of these PRs depends on it.
- Close-out §3 lists the other open findings.

## 4. Checks supported only by automated tests

Device evidence is from Builds 20 and 21 on the **sandbox**. It is **not production** evidence for any fix (see B1). Build 20's results carry over to Build 21 **by inference only**.

| PR | Fix | Device evidence | Supported only by automated tests |
|---|---|---|---|
| #72 | F-HOME-1 | ✔ DV-20-1/2/3 | — |
| #72 | F-XFER-1 (client) | ✔ DV-20-7 | — |
| #72 | F-XFER-2 (+2-A) | ✔ DV-20-8 (pending), DV-20-9 (sent) | — |
| #72 | **F-BID-1** | final state only (DV-20-4). DV-20-5 blocked | **the failed-read form: no form built on an unknown floor, no permanent spinner** |
| #72 | **F-AVATAR-1, F-AVATAR-2** | none. DV-20-10/11 UNOBSERVED | **busy state held until the save completes; no overlapping saves** |
| #72 | **F-DESTRUCT-1** | none. DV-20-6 SKIPPED | **delete and cancel send one request at a time** |
| #73 | **F-AVATAR-3** | weak (DV-20-12, one picker) | **a same-tick double press gives one upload and one save; out-of-order completion; a retry works after the save completes; the control is available afterwards** |
| #74 | **F-SEC-1** | none. DV-20-13 BLOCKED (needs a staged notice) | **one sign-out per same-tick double press; the guard releases on failure** |
| F-SEC-2 | **F-SEC-2, F-SEC-2-A** | none. DV-20-13 BLOCKED | **a thrown action shows a message; a sign-out that succeeded is never reported as failed** |
| #75 | F-XFER-3 | ✔ N1 (Build 21) | — |
| #75 | Decision 1 | ✔ the no-destination branch (N1) | **the "Open <provider>" button and the return-from-provider question: explicitly UNTESTED on device (owner, 2026-09-18). No provider fixture will be created.** |
| #75 | Decision 2 | ✔ dialog copy and Cancel, run online (N2) | **single-flight through the dialog; the lock re-arming after a failed release; the release path itself.** The server check at 21:56:47Z confirms nothing was released on S8only. |

## 5. What this does not do

It merges nothing, opens no PR, creates no tag, requests no build, and deploys nothing. It does not touch `main`, production, the D1/D2 proof files or Sandbox L7.

Each of these is its own owner decision:
- step 1's merges;
- the F-SEC-2 PR;
- the B1 ceremony;
- any build.

## 6. Deployment settings, read 2026-09-18 (owner-authorized, read-only, nothing changed)

**What a merge into `release/production-gate-20260918` triggers:**

| System | Configured branch(es) | Effect of a merge into the release branch |
|---|---|---|
| **Supabase GitHub integration**, production `hqycwntpfoztoinemqns` | One branch, `main` (default), **`git_branch: ""`**, unchanged since 2026-08-27T15:49:25Z. Read twice, via the Supabase connector and the CLI, with identical results. No preview branches | **None.** No git branch is bound, so no migration is applied and no function is deployed. The Supabase app still posts a check on pushes, and it **skipped** at the branch's last push (`6561d1f`) |
| Supabase, sandbox `ofaidukbieeekqaboscm` | `supabase branches list` returns `[]`. No branching | **None** |
| **Vercel `snatchit-web`** (linked to this repo, root `web/`) | **Production branch `feature/web-accounts-foundation`**. Git deployments enabled, no ignored-build step, comments on commits and PRs | **A PREVIEW deployment of `web/`, not production.** The merge changes 0 files under `web/`. Previews are SSO-protected, and their public env points at the **production** Supabase project with the anon key, the same as every previous push and PR. At the last push the preview was **rate-limited** ("retry in 24 hours"). **Not checked:** whether `next build` pre-renders any page that reads data. There are no explicit static-generation markers in `web/` |
| **Vercel `snatchit-admin`** (linked, root `admin/`) | **Production branch `admin/operating-console`**. The ignored-build step builds only `ab3e17f` | **Skipped** by the ignored-build step |
| Vercel, the other 6 projects | 4 are linked to other repos; 2 are not linked | **None** |
| **GitHub Actions** (the branch's `.github/workflows/`) | `ci.yml` runs on push to any branch except `main`. `migrations-guard.yml` and `security.yml` run on PRs only | **CI only**: 5 jobs, with no secrets referenced and migrations applied to a throwaway database inside the runner |
| Other | No repository webhooks. No Expo/EAS app reacted to the branch's last push | **None** |

**Side facts, recorded, not acted on:**
- `snatchit-web`'s production branch is `feature/web-accounts-foundation`, not `main`.
- Its preview deployments use the production Supabase project, with the public anon key only.

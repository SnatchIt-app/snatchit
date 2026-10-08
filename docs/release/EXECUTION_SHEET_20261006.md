# Execution sheet: remaining owner decisions (A, 2026-10-06)

**Reviewed code is not permission to deploy it.** Nothing below has been merged, pushed, applied, deployed or
switched on, and nothing in this sheet does any of that. Every step marked *owner* waits for your own word for
that step. This consolidates D's sheet (`review/d-records-20261005 @ 797c2d46`) with A's checks. §6 records where they differed;
D verified and accepted each point and revised its sheet to agree (rev 3, `342f2ab3`).

## Status: MM-1 preparation executed (A, 2026-10-07 ~02:40Z; owner-authorised; D verifies)

**Rulesets:**
- `main` 21624091 narrowed to `squash`; nothing else changed.
- New: gate 24623964 (merge only, the 6 checks), web 24623967, console 24623970, records 24623971.
- There is no linear-history rule on the gate, web or console. Repository-wide settings are unchanged.

**Steps done:**
- **Web:** W1a, W2 (`web/wording-release-ff` @ `fd0da772`), V-W2, W1b and W3.
  - `Web build (Next.js)`: GitHub Actions 15368, one run, success.
  - PR **#97**, draft, 11 files, all under `web/`.
- **Console:** C1 (`admin/label-console-release-ff` @ `efe03fca`), V-C1, and C2.
  - `Admin console (Next.js)`: GitHub Actions 15368, one run, success.
  - PR **#98**, draft, 3 files, all under `admin/`.

**Not done (not authorised):** W4, C3, C4 and C5. The deploy branches are unmoved at `1765bbeb` and `562fda9a`.

## Status 2026-10-08: backend executed; attended session pending

**Done (owner authorisation 2026-10-07):**
- Authenticator verified.
- **#97 live.** Merge `0b389584` → `dpl_9n8Jps9WdkGCmjEEgpTf8ryVLvon` on **`snatchti.com`, the currently observed web
  domain**. No domain or DNS change is part of this release. Rollback target: `dpl_7h2CaNtBqujcf6ZFnD7utBByWe7m`.
  **The authenticated wording check stays open** until someone views the pages; redirects are not evidence of
  wording.
- **#98 merged.** `f7e7e85f38c3d14e6ce38bb2fa1131fb66ec74bb`; its build was cancelled by the pin, as
  `dpl_74DoDNf53NLEmGuNHVwZx4pAqWiY`. Not deployed.
- **S1 `92a72cbd` and S2 `abef9506`.** Both trees equal the CI-tested ones; gate CI is green on both.
- **150/151 package X1b–X4b executed and verified** (package README §6). Run check PASS.

### Attended session: one ordered checklist (owner and A; D witnesses)

**1. Stripe: verify the live endpoint, then subscribe the three refund events (O-R1)**
- **Read 2026-10-08 (owner screenshot, live mode).** `we_1TCqy5GdOzCmGbHwxBkCHKL2` "SnatchIt payment events", Active,
  URL as above, API `2026-02-25.clover`, 13 events.
  - 11 visible, including `refund.created`, `refund.failed` and `refund.updated`, which were **already subscribed**,
    so no change was made.
  - This records prior state, not a before/after.
  - **2 events below the cut are unread. The full-list check (precondition b) is OPEN.**
- 1a. Open https://dashboard.stripe.com/webhooks with **Test mode off**.
- 1b. Find the endpoint whose URL is exactly `https://hqycwntpfoztoinemqns.supabase.co/functions/v1/stripe-webhook`.
  **If there are none or more than one: stop.**
- 1c. **Before:** paste into the chat the endpoint id (`we_…`), status, API version and the **complete** event list.
  Never paste the signing secret.
- 1d. Edit, then Select events, then add `refund.created`, `refund.updated`, `refund.failed`. Change nothing else:
  not the URL, API version, description or metadata, and do not roll the secret. Save.
- 1e. **After:** paste the complete event list again. A checks it is the before list plus exactly those 3, with
  nothing removed and the same id, URL, API version and status.

**2. Console: deploy the reviewed merge commit**  
**DONE 2026-10-08 23:45Z:** `dpl_8xPaaBYGM7xgfGsS5fgNKib4gNXp` (READY, production, `f7e7e85f`) serves `snatchit-admin.vercel.app`. The build log shows the current pin was evaluated.
- 2a. A, fresh reads:
  - `admin/operating-console` is still at `f7e7e85f38c3d14e6ce38bb2fa1131fb66ec74bb`;
  - `dpl_74DoDNf53NLEmGuNHVwZx4pAqWiY` is CANCELED, production, for that sha;
  - the alias is `dpl_J5Kr4QSBmRjxmJbu2nT7KovSxmsr`;
  - the pin is `ab3e17f1a36e8c78c9fce31ee0b4fafdb6934d64`.
- 2b. Set the pin to `test "$VERCEL_GIT_COMMIT_SHA" != "f7e7e85f38c3d14e6ce38bb2fa1131fb66ec74bb"`. A does this with
  `vercel api` and reads it back (or you do it in Settings → Build and Deployment → Ignored Build Step).
- 2c. **You:** open https://vercel.com/gnvprod-5449s-projects/snatchit-admin/74DoDNf53NLEmGuNHVwZx4pAqWiY, then "…",
  then **Redeploy**, with **"Use project's Ignore Build Step" left ticked**. If Redeploy is not offered: stop and tell
  A, who then runs the reviewed CLI fallback from a clean checkout of `f7e7e85f`.
- 2d. A checks: READY, production, commit `f7e7e85f`, and `snatchit-admin.vercel.app` serving it.
- **Rollback:** Instant Rollback to `dpl_J5Kr…`, then the pin back to `ab3e17f1…`.

**3. Console access**  
**DONE 2026-10-08:** password sign-in 23:48:03Z; TOTP `e677717c` challenged 23:48:42Z (aal2).
- 3a. **You:** sign in at https://snatchit-admin.vercel.app/login with your password and a code from the new
  authenticator; the Today page loads.
- 3b. A, read-only: factor `e677717c…` shows `last_challenged_at` after that sign-in.

**4. Refund detection (O-R2), only once all three prerequisites are verified**
- **Prerequisites:**
  - (a) the new `stripe-webhook` verified: done (A; D's W3);
  - (b) step 1e's after-list shows the 3 events;
  - (c) step 3 is confirmed.
- 4a. **You, in the console:** System → Settings → `refund_state_detection_enabled` → `true` → Save setting.
  Reason: "O-R2, owner approval 2026-10-07; operator: owner, daily review".
- 4b. A, read-only:
  - the setting reads `true`;
  - `ops.audit` has `action.setting_set` for that key;
  - the next `refunds` tick succeeded;
  - list any `refund_failed` or `refund_pending` case opened. Expected: none new, because historical refunds have
    no state rows until O-R4.
- Alert delivery is unchanged.

**Still open, any time:** signed in on `snatchti.com`, view `/account/purchases`, `/account/sales` and one transfer page
to confirm the wording.

## 0. What is reviewed, and what would deploy it

| Artefact | Review state | What would put it live | Permission |
|---|---|---|---|
| 150/151 package (#94 `2eebc5bf`, #95 `9a66f29d`) | D PASS 28/28 | X2/X3 apply, X4 function deploys | none |
| Web wording, landing commit `fd0da772` (`web/wording-release-ff`, **local, not on the remote**) | `web/` tree `ab2eb1bf` = the reviewed `e7130f04`'s; tsc 0, 218/218, local `next build` exit 0. **No CI check has run on it** (§2) | merge into `feature/web-accounts-foundation` | none |
| Console labels, landing commit `efe03fca` (D, `admin/label-console-release-ff`, local) | `admin/src` `f297dab4` and `admin/tests` `6b76588f` = the reviewed `1058c882`'s; patch-ids equal | protected PR merge (C3; the pin blocks deployment), then the pin plus an explicit redeploy of that exact merge commit (C4–C5) | none |
| Gate → `main` | method trial only (§4); the release candidate is not yet accepted or frozen | S7 | none |

## 1. Refund operations O-R1–O-R4

| | Exact choice | Recommended | Permits | Does not |
|---|---|---|---|---|
| **O-R3** | Who works `refund_failed` / `refund_pending` in `/cases`, how often, and the handling | **Name one person, daily**, and ratify: Stripe returns the money to the platform balance → contact the buyer from support@ → return it another way → note it on the case → **never re-refund automatically** | O-R2; the submission prerequisite (D6) | No code, no production change |
| **O-R1** | Stripe Dashboard, live endpoint for `stripe-webhook`: add `refund.created`, `refund.updated`, `refund.failed` | **Yes, at X5**, after X4a (new `stripe-webhook` live, C3) | Each refund's real state reaches `payment_refund_state`, including a failure after success | Opens no case; contacts nobody. Rollback: remove the 3 events |
| **O-R2** | Console → System → Settings → `refund_state_detection_enabled` = `true` (audited `setting_set`, platform_admin; needs your console sign-in) | **Yes, after O-R1 and only once O-R3 is decided** | Within 5 min: a p1 `refund_failed` case per failed refund, and `refund_pending` after 120 h | Alert delivery stays off: nobody is notified. Rollback: set `false` |
| **O-R4** | (1) one read-only Stripe read of the refunds behind the 7 historical refunded rows (2 live, 2026-08-04); (2) feed each through `record_refund_state(pi, re_…, status, amount, failure_reason, source, 'reconcile')` (`'reconcile'` is the `p_observed_via` argument, not the source) | **Yes, two separate authorisations**: after X2 and O-R3; preferably after O-R2 so a reconciled failure becomes a case. A writes the package after X2 | Those rows show their true state instead of "Refund recorded" | Moves no money |

If all four stay open, the interim is the package README §2A: a failure is seen only via `charge.refunded` or the
expiry job, the payment is parked, the app says "Refund of $X initiated", and nobody contacts the buyer.

## 2. Web: protection, then deployment

Action kinds, kept distinct throughout:
- **[P]** protection or configuration change;
- **[B]** push of a non-deploy branch;
- **[M]** merge into a deploy branch;
- **[D]** production deployment;
- **[V]** verification.

**Landing commit `fd0da772`, and why it is a fast-forward.**
- `e7130f04` is built on the gate, **910 commits** away from the web branch tip `1765bbeb`. A PR of it would carry
  1,100 files of gate history into the live branch.
- So the same 3 commits were cherry-picked (`-x`) onto `1765bbeb`: `a6cd359f` → `c2aa632c` → `fd0da772`.
  - Its `web/` tree `ab2eb1bf` is identical to `e7130f04`'s.
  - Patch-ids are equal; 0 files change outside `web/`; 11 files, +990/−101.
  - Typecheck 0, vitest 13 files / 218, local `next build` exit 0.
- It is **local, not on the remote**, so no CI check has run on it.

| Step | Kind / who | Action | Pass condition / effect |
|---|---|---|---|
| W1a | [P] owner | Ruleset on `feature/web-accounts-foundation`: restrict deletions; block force pushes; require a PR, 0 approvals; **allowed merge methods: merge only**; no bypass | A reads it back. Executable now |
| W2 | [B] owner's go | push `web/wording-release-ff` (`fd0da772`). A's earlier attempt was refused by this session's permission check, so you push it or allow it | CI push run. The web preview is skipped by its Ignored Build Step; no admin record; no production effect |
| V-W2 | [V] A | read the check runs on `fd0da772` | a run named exactly **`Web build (Next.js)`**, app `github-actions` (integration 15368), `head_sha` = `fd0da772`, conclusion `success` |
| W1b | [P] owner | add the required status check `Web build (Next.js)`, source GitHub Actions | **only after V-W2 passes** |
| W3 | A | open the PR into the web branch | the same check is reported on the PR head and is green; the diff is the 11 files |
| W4 | **[D]** owner | merge the PR (merge commit) | **on this branch a merge is the production deployment**; there is no separate step |
| V-W4 | [V] A + owner | — | the merge commit's tree equals `fd0da772`'s; the production deployment is READY on that sha; spot-check `/account/purchases`, `/account/sales` and the transfer pages signed in |

**If V-W2 finds no check, diagnose it; never remove the check to unblock a merge.**
1. **No workflow run for the sha:** a trigger problem. Check that ci.yml at `fd0da772` has `push: branches-ignore: [main]`
   and that Actions is enabled.
2. **A run without the job, or with the job skipped:** the job's `Detect web app` step, which needs `web/package.json`.
3. **The job failed:** fix it with a new reviewed commit and repeat V-W2.
4. **A name or app mismatch:** the required context must equal the job's `name:` exactly and be bound to GitHub
   Actions.
5. **A malformed workflow file:** this shows as a 0s "workflow file issue" with zero jobs, which is how CI silently did
   nothing in Phase 0. Fix the file; don't relax the rule.

**Caveat.** The job starts unconditionally and its steps skip when `web/package.json` is absent. So on a branch without
`web/` the check passes **vacuously**. On `fd0da772` it is a real build, but a green check proves the rule can be
satisfied, not that every future branch built something.

The PR into this branch gets no pull_request run (ci.yml: `pull_request: branches: [main]`). The check comes from the
push run on the head commit.

**Rollback:** Instant Rollback to the production deployment serving before W4, **read fresh at W3** (`1765bbeb` carries
a Vercel "Deployment has completed" status, but the serving deployment id is not on record). Then a revert PR, so the
branch matches what is served.

The gate gets the same change via S4 (`e7130f04`). That is one change with two identities.

## 3. Admin console: protected PR merge, then an explicit deployment of that exact commit

**The pin is not a substitute for PR protection.**
- The console branch gets the same PR protection as the other deploy branches.
- The pin keeps the merge from deploying until you approve.
- The release is the PR's own merge commit, deployed explicitly.

**Vercel behaviour this relies on.**
- *Docs:* "When your deployment enters the `BUILDING` state" the Ignored Build Step command runs; exit 0 sets the
  deployment to `CANCELED` (Project settings, last updated 2026-09-21).
- *Docs:* the dashboard's **Redeploy** dialog has a **"Use project's Ignore Build Step"** checkbox. So a redeploy is
  subject to the pin unless someone unticks it.
- *Vercel staff (community, 2026-02-22):* the ignore command cancels all types of deployment, including deploy hooks.
- *Observed:* on `562fda9a` GitHub shows `Vercel – snatchit-admin: Canceled by Ignored Build Step`, so a push to the
  console branch under another pin is cancelled.
- **Not established by any source:** whether **Redeploy is offered on a CANCELED deployment**. Check it at C5 before
  relying on it.
- **CLI deployments: unknown.** The 09-08 record's "CLI deployments ignore the Ignored Build Step" is **unsupported**
  (corrected in that record on this branch).
  - Its only datum, the CLI deploy `dpl_J5Kr…`, carried `meta.gitCommitSha` equal to the pin, so it cannot distinguish
    "skipped" from "ran and matched". Credit to D.
  - For the fallback, a CLI deploy of M from a hand-verified clean checkout of M has three possible outcomes:
    - the step does not run: M builds;
    - the step runs with the sha set: M builds, because C4 pinned M;
    - the step runs with the sha empty: the build is cancelled.
  - None of the three can deploy anything but M. **That safety comes from the verified checkout, not from the pin.**
  - **The Redeploy route, with the checkbox ticked, stays primary**, because the pin provably applies there.
  - **Liveness, not just safety (D).** In the third case nothing deploys.
    - So a CANCELED result from the CLI fallback is a possible normal outcome, not a fault. **Do not retry it blindly.**
    - Record the outcome either way; it is the only measurement anyone can make of this question.
    - **CANCELED** establishes only that attempt's outcome: the step ran for that deploy, and the sha it saw was not
      M. It does not establish how CLI deploys behave in general.
    - **READY** means M is live. The question stays open but doesn't matter for this release.
  - **If Redeploy is not offered and the CLI attempt is cancelled:** create a git-source production deployment
    through the Vercel API (`POST /v13/deployments`, with `gitSource` naming this repository, `ref`
    `admin/operating-console` and `sha` M, and `target` production). It needs a token with team access; A's is refused,
    so this is the owner's step.
    - **Never push an empty or re-trigger commit.** It changes the sha and defeats C4.

| Step | Kind / who | Action | Pass condition / effect |
|---|---|---|---|
| C1 | [B] owner's go | push `admin/label-console-release-ff` (D's `efe03fca`) | CI push run. snatchit-admin creates no record (preview tracking off); the web preview is skipped |
| V-C1 | [V] A | read the check runs on `efe03fca` | **`Admin console (Next.js)`**, `github-actions`, `success`, on that sha (it reports on the console tip `562fda9a` today) |
| C2 | [P] owner | Console ruleset: restrict deletions; block force pushes; PR required, 0 approvals; **merge only**; required check `Admin console (Next.js)` (only after V-C1) | A reads it back |
| C3 | [M] owner | open the PR `admin/label-console-release-ff` → `admin/operating-console` and merge it (merge commit) | **Not a deployment:** Vercel creates a production record for the merge commit and the current pin cancels it |
| V-C3 | [V] A + D | read the exact merge commit **M** from GitHub | M's parents are `562fda9a` and `efe03fca`; M's tree equals `efe03fca`'s; `admin/src` `f297dab4…` and `admin/tests` `6b76588f…` equal the reviewed `1058c882`'s; snatchit-admin on M reads "Canceled by Ignored Build Step"; **the alias and the serving deployment are re-read** (record: `dpl_J5Kr…`) |
| C4 | [P] owner, with deployment approval | pin → `test "$VERCEL_GIT_COMMIT_SHA" != "<M, full sha>"` | read back. Builds nothing |
| C5 | **[D]** owner | Vercel → snatchit-admin → Deployments → M's cancelled production deployment → … → **Redeploy**, with **"Use project's Ignore Build Step" left ticked** (the pin then admits only M). **Fallback, if Redeploy is not offered on a cancelled deployment:** `vercel deploy --prod` from a clean detached checkout of M (the 09-08 method; the pin applies the same way). Never untick the checkbox | READY on M, the alias moved, sign-in at aal2 (needs your new authenticator), D's label checks |

**Local trial (method only).**
- `git merge --no-ff efe03fca` onto `562fda9a` gave `f7589003`, with parents `562fda9a` and `efe03fca`.
- Its tree equals `efe03fca`'s, and its app trees equal `1058c882`'s.
- The real M exists only after C3, and V-C3 repeats these checks on it.

**Rollback:** Instant Rollback to the deployment that was serving at V-C3, then the pin back to
`ab3e17f1a36e8c78c9fce31ee0b4fafdb6934d64`. Moving the pin alone rolls nothing back.

**Release-first fallback: RETIRED (owner, 2026-10-07).**
- After C3 the branch is at M, and `efe03fca` is an ancestor of M. Pushing `efe03fca` would therefore be a rewind
  needing `--force`, which C2 blocks (D). The operation no longer exists.
- **If every approved exact-commit route fails** (Redeploy, CLI from a verified checkout of M, API git-source for M):
  stop, report each route's measured result, and bring a concrete alternative to the owner.
- **Never remove protection, and never add re-trigger commits.**

**One change, three identities** (equal patch-ids):
- gate `004af0b0` / `789025f3` (S3);
- reviewed `72ac2c52` / `1058c882`;
- landing `ccac575d` / `efe03fca`.

M adds a fourth commit id, but no change: its tree equals `efe03fca`'s.

## 4. `main` integration: squash

**Why squash.**
- `main`'s ruleset (`main-protection`, id 21624091, the repository's only ruleset) allows only `rebase` and `squash`,
  with linear history. Repository-wide, merge commits **are** allowed (§4A).
- Rebase would rewrite all 906 commits, merge commits included, so no recorded sha would name a commit on `main`.

**What the trial establishes: the method only, not the release contents.** Verified locally; predictions registered
first, sha256 `0c586b1b…`.
- **`main` `eadd456a` is an ancestor of the gate:** 0 behind, 906 ahead. So a squash carries the head's tree exactly.
- **Today's gate:** a squash gives tree `e6b9589b`, equal to the gate's tree.
- **Method trial:** the gate plus S1–S5 as merge commits, using the **then-current** v3 `f3f08930`. Result `879a34ca`,
  tree `1b76e9cd`; its squash gives `1b76e9cd`. **That candidate is superseded:**
  - B is now reviewing **`d52175303f22a575b80f005f38c0e8555be0dbdc`**. It is `v3/midnight-app`'s head (local, not
    on the remote), 3 commits after `f3f08930`, 8 files, none under `supabase/`.
  - C's batch2 fixes (`v3/consumer-batch2`, built on `d5217530`) are a separate track.
  - So `879a34ca`, `1b76e9cd` and the counts 13/3/3/11/235 are **not** release figures, and nothing may cite them as
    the candidate.
- **The final integration trial is re-run on the eventual accepted candidate** (the gate after S1–S5 with the accepted
  v3 commit, plus S6 if D2), and again at the freeze if anything moves. That trial's squash tree is the D1 claim.

**At S7** (after X2–X4, the freeze, and a fresh `AUTODEPLOY-VERIFIED-OFF`):
1. `main` unchanged since it was read fresh at S7 (expected `eadd456a`; no dependabot merges first); PR head = the
   frozen candidate; required checks green there.
2. *owner's go*: annotated tag `release/s7-<date>` at the frozen candidate, and PR-7 on the gate (no deletion or
   force-push). These keep every cited sha reachable.
3. Squash with a written message carrying `Release-Candidate: <sha>`, `Release-Tree: <tree>` and the tag.
4. **Post-merge:** the squash commit's tree equals the candidate's tree. This is the D1 claim; `main` then holds
   exactly what the gate replays.
5. **Sync-back, immediately:** merge `main` back into the gate. It is a merge commit and **its tree must equal the
   candidate's**.
   - **Through a helper branch, not a PR from `main`.**
     - `main`'s commits carry no `ci.yml` or guard check runs: pushes to `main` are excluded, and its head shows only
       scheduled security runs.
     - So a PR whose head is `main` could never satisfy a gate ruleset's required checks.
   - **Procedure:**
     1. Branch `sync/s7-<date>` from the gate.
     2. `git merge` the squash commit into it.
     3. Check its tree equals the candidate's.
     4. Push it; CI runs on its sha.
     5. Open a PR into the gate and merge it with a merge commit; its tree is unchanged.
   - **Verified locally (method level).** Helper `968cf79f` has parents candidate and squash. The gate after the PR is
     `156e6aa7`, with parents candidate and helper.
     - Its tree equals the candidate's.
     - The candidate, the squash and the helper are all its ancestors, and its first parent is still the candidate.
     - `merge-base(main, gate)` becomes the squash commit.
     - The next squash is clean, and its tree equals the new gate's.
   - The helper branch's push run supplies the gate's required checks. A PR from `main` would have none.
   - **Also verified on the real refs** (D, then A): squash of `037092f0` onto `eadd456a`, then the helper, then the PR
     merge commit.
     - The trees stayed `e6b9589b` throughout.
     - The squash, the old gate tip and `main` are all ancestors of the new gate.
     - `merge-base` is the squash commit.
   - **Two checks at execution, after the sync-back:**
     1. the gate's tree is unchanged;
     2. `main` is an ancestor of the gate.
     If either fails, something landed between S7 and the sync-back: stop.
   - Trial: the sync-back's tree was `1b76e9cd`, unchanged.
   - Without the sync-back, a later gate edit to a line the squash introduced **conflicts** (trial: `ci.yml`).
   - With it, the next squash is clean and equals the new gate's tree (trial).
   - **Timing:** do the sync-back before anything else lands on the gate. Done then, it is clean and changes nothing
     (trial). Done after a later gate edit, it conflicts exactly like the next squash would (D reproduced this). It
     then has to be resolved once, by hand, in the sync-back.

**Traceability.**
- **Migration ancestry.** Each migration on `main` is byte-identical to the candidate's, as implied by the tree check.
  - `git log release/s7-<date> -- supabase/migrations/<file>` gives its original commit and PR.
  - The ledger row (`created_by`) and the registry map each version to its PR, head and apply record.
  - `git log main` will show only the squash commit for each migration. That loss of lineage is the whole cost of a
    squash.
- **Later merges.** These follow the same pattern: squash, tree check, then sync-back.
- If you approve PR-3 instead, a merge commit keeps the shas on `main` and needs no sync-back; the trees are identical.

## 4A. Merge-method configuration: one compatible set (a proposal; nothing changed)

**Measured 2026-10-06 (read-only).**
- **Repository settings:** `allow_merge_commit` true, `allow_squash_merge` true, `allow_rebase_merge` true,
  `allow_auto_merge` false.
- **Rulesets:** only `main-protection` (~DEFAULT_BRANCH). Effective rules: `main` has 5; the gate, the web branch, the
  console branch and the records line have **none**. Classic protection returns 404 on `main` and the web branch.
- **So the sheet's two statements do not conflict today.** "No merge commits" holds on `main` only, through its
  ruleset. Merge commits are allowed everywhere else.

**Proposed configuration (MM-1), one set for all branches:**

| Where | Allowed merge methods | Rules | Required checks (all GitHub Actions, integration 15368) |
|---|---|---|---|
| Repository settings | **unchanged**: merge, squash, rebase | — | — |
| `main` (ruleset 21624091) | **squash only** (drop `rebase`) | keep: linear history, PR, no deletion, no force-push, strict per PR-2 | unchanged: the 5 |
| gate `release/production-gate-20260918` (new) | **merge only** | PR, 0 approvals; no deletion; no force-push; **no `required_linear_history`**: it excludes merge commits, so do not copy it from `main` | the 6 that report on gate PRs today (#94's head): `Immutability + ordering`, `Migrations apply cleanly (fresh DB)`, `Typecheck / Lint / Unit tests`, `Web build (Next.js)`, `Admin console (Next.js)`, `Deno type-check (edge functions)`. **Not** `Secret scan` or `Dependency review`: they run only on PRs into `main` |
| web `feature/web-accounts-foundation` (new) | **merge only** | PR, 0 approvals; no deletion; no force-push (W1a) | `Web build (Next.js)`, **after V-W2** (W1b) |
| console `admin/operating-console` (new) | **merge only** | PR, 0 approvals; no deletion; no force-push (C2) | `Admin console (Next.js)`, **after V-C1** |
| records `release/candidate-20260918` (new) | — | no deletion; no force-push; no PR rule (direct record pushes) | — |

**Never required anywhere:** `Supabase Preview` and `Vercel Preview Comments` (third-party apps), npm audit, CodeQL.

**Checks that are green without proving what they appear to.** Read each for what it establishes; never cite it
as proof of its name.

| Check | What "green" actually establishes | What it does not establish |
|---|---|---|
| `Web build (Next.js)` | the job ran at that sha; on a ref with `web/package.json`, a real build passed | anything about a ref without `web/`: the steps skip and the job passes vacuously (§2) |
| `Vercel – snatchit-web` status | Vercel received the commit; `state=success` even when the description is "Canceled by Ignored Build Step" | that anything was built or deployed (D's V-2). It *is* evidence that the landing-branch pushes deployed nothing |
| `Immutability + ordering` | at that event: the base tip then, plus a description carrying `AUTODEPLOY-VERIFIED-OFF:` | that auto-deploy is off (the workflow says so itself, lines 232–234), or that the result still holds after the base moved |
| any **re-run** of a pull_request workflow | the original event's merge commit and payload, re-evaluated | the current base or the current PR description (GitHub: re-runs use the original `GITHUB_SHA` and `GITHUB_REF`) |

**Observed in this repository (D, attempt-level API), on `9a66f29d`:**
- run `36094505790` attempt 1 failure at 04:27:18;
- fresh run `36095250938` attempt 1 **success** at 04:38:22;
- re-run `36094505790` attempt 2 **failure** at 04:38:25.

A fresh event passed and a re-run failed three seconds apart, on the same commit and base. The re-run carried the old
payload.

**Why refreshing only the guard is sufficient at S2.**
- Of the gate's six required checks, only `Immutability + ordering` comes from the `pull_request` event. The other five
  come from the `push` run on the head commit (`36093357933` for #94, `36094475492` for #95; all attempt 1, verified).
- Those five depend on the commit alone, so they do not go stale when the base moves.
- **Limit: they test the PR head, not the merge result.** `strict` is off on every ruleset (verified), and `9a66f29d`
  carries 151 but not 150.
  - **The first and only CI test of 150 and 151 together is `Migrations apply cleanly (fresh DB)` on the gate merge
    commit after S2.** It is a push run (`037092f0` shows it in that position) and runs **after** the merge. A failure
    there means a red gate and a fix-forward, not a blocked merge. That is the trade accepted with `strict` off.
  - **Before the merge, the only joint exercise is local:** package rehearsal v2, R6 (apply 150, then 151, on a
    gate-shaped DB: PASS).
  - **The guard never runs on a merge commit** (migrations-guard is `pull_request` and `merge_group` only; `037092f0`
    has no guard run). The combined result is therefore tested on a **temporary integration branch** before S2; see
    "S1 + S2 integration test" below. Nothing is assumed to hold for the merged tree without that test.

**S1 + S2 integration test (owner, 2026-10-07): the combined result is tested before S2, so post-merge CI is not the
first test.**
- **Branch:** `integration/s1-s2-trial-20261007`, test only and never merged. It is the freshly read gate `037092f0`,
  plus a merge commit of #94 (`2eebc5bf`), giving `229df83c`, tree `5b9cca0d…`; plus a merge commit of #95
  (`9a66f29d`), giving `3787d8a2`, tree `2e2c31b4…`. These are the same merges, in the same order and by the same
  method, as S1 and S2.
- **Migration diff against the gate:** exactly 2 files, both added. `20260925000000_…` has blob `b7ef57fa` and
  `20260925010000_…` has blob `cb9fa6aa`, both equal to the frozen package. Nothing is modified, deleted or renamed;
  the 2 rollbacks are added under `supabase/rollbacks/`.
- **Ordering:** both versions are above the gate's timestamp tip `20260924120000`, and in LC_ALL=C order 150 then 151
  sort last.
- **The guard's own `Check migrations` logic,** extracted from the workflow and run locally (step 0c, which only
  applies to `pull_request` events, does not apply):
  - passes on S1 against the gate, on S2 against the post-S1 commit, and on the combined result against the gate;
  - **controls:** an edit to an existing migration fails immutability, and a migration dated below the tip fails
    ordering.
- **CI on the branch, the joint replay** (push run `37568480763` at `3787d8a2`, 2026-10-07 03:48–03:51Z): **all 5 ci.yml
  jobs pass.**
  - `Migrations apply cleanly (fresh DB)` ran on CLI 2.115.0. Its log shows `Applying migration
    20260925000000_refund_lifecycle_state.sql` and then `…20260925010000_release_stuck_seller_win.sql`, after
    `20260924120000`.
  - Gate-2 census `tables=34 functions=111 policies=37 triggers=40`, equal to the package's predicted post-150 state.
  - pgTAP **Files=98, Tests=5605, Result: PASS**, including `217_refund_lifecycle_state.sql ok` and
    `218_release_stuck_seller_win.sql ok`.
  - Admin, Web, Deno and Typecheck/Lint/Unit all pass. The web status is "Canceled by Ignored Build Step" (no build);
    `Supabase Preview` skipped.
  - A push run does not run the guard; that is why the guard logic was run locally above.
- **D's independent local replay** (`review/d-integ-94-95`, `d2df0f91`): the same tree `2e2c31b4`.
  - REPLAY OK 167/167, census 34|111|37|40.
  - Control on the gate alone: 165/165, 32|108|37|38.
  - That harness is superuser and not authoritative, which is why it is corroboration only.
- **Reproduced independently.**
  - D's separate merges (`73d82967` / `486c954c`, another session and worktree on the same machine and object store)
    give exactly trees `5b9cca0d` / `2e2c31b4`.
  - CI run `37568480763` is `push`, attempt 1, so it is a fresh event.
  - **A rebuild from the same three inputs that does not reproduce `2e2c31b4` is a hard stop.**
- **Log-reading note (D).** A blanket grep for `error|FAIL|not ok` over a db-job log returns about 116 matches. All of
  them are echoed script text. The real signals are emitted `::error` annotations (0 here) and TAP `not ok` lines
  (0 here).
- **The branch is disposable.** Keep it as the evidence anchor until S2, then delete it (your go).
- **Reuse rule.** This evidence counts for S1 and S2 only while:
  - the gate is still `037092f0` when S1 merges;
  - #94 and #95 are still at `2eebc5bf` and `9a66f29d`;
  - the S1 merge commit's tree equals `5b9cca0d…` (checked after S1);
  - the S2 merge result's tree equals `2e2c31b4…` (checked before S2 against the then-current gate, and after S2).
  If anything else lands on the gate or either head moves, the evidence is void: rebuild and re-run.
- **The local package rehearsal stays** as separate evidence (v2, R6: apply 150 then 151 on a gate-shaped DB, PASS).

**State when you approved (2026-10-07).** The latest run of each required check on #94 and #95 is attempt 1, a fresh
event; no green is inherited from a re-run.

**Duplicate check runs.** `562fda9a` carries three `Immutability + ordering` runs, one of them a `failure` (D). For
every required context, read **all** runs at the head sha before merging, not just the first one listed.

## 5. Independent, or waiting

**Can proceed independently** (each still needs your word; the kinds stay distinct):
- **[P] W1a**, protecting the web branch. The most urgent; executable now.
- **[B] W2 then [V] V-W2**, then **[P] W1b**.
- **[B] C1 then [V] V-C1**, then **[P] C2**.
- **MM-1**: the configuration in §4A. `main` squash-only and the gate ruleset are needed only by S1 and S7.
- **O-R3** (a decision).
- The stale-PR closures, each with an archive tag.
- **Your TOTP check:** A's read-only factor list, once you confirm enrolment.

**Waiting:**
- **[D] W4** waits on W1b and W3.
- **[M] C3** waits on C2.
- **[D] C5** waits on V-C3, C4, your deployment approval and your sign-in.

**Must wait:**

| Action | Waits on |
|---|---|
| X1b transport probe | X1a (your auto-deploy check, a matter of prudence) |
| X2 apply 150 | X1b reporting `same_txn=true`; otherwise STOP |
| X3 apply 151 | X2 (its prestate is post-150). Live on apply: `release_stuck` cases within 5 min |
| X4a / X4b function deploys | X2 |
| O-R1 | X4a |
| O-R2 | O-R1, O-R3, and your console sign-in |
| O-R4 | X2 and O-R3 (preferably O-R2) |
| S1 → S2 | your merge go; #94 before #95 (C6). **Read `Immutability + ordering` fresh at each merge** (all runs, latest counts). Its result depends on inputs outside the commit: the base tip at run time (`refs/pull/N/merge`^1) and the PR description's `AUTODEPLOY-VERIFIED-OFF:` line (it re-runs on `edited`). On `9a66f29d` it read failure, then success, then success with the same base, consistent with a description edit (D's V-1, mechanism from migrations-guard.yml). After S1 lands, **trigger a fresh guard run on #95 by editing its description** (the `edited` event; e.g. refresh the `AUTODEPLOY-VERIFIED-OFF:` line), then read it before S2. **Not a workflow re-run:** a re-run reuses the original event's `GITHUB_SHA` (the old merge commit, so the old base) and payload (the old description), per GitHub's docs. **Not a commit** either |
| S5 | B's review of `d5217530` (C's batch2 is separate), the owner's acceptance of the v3 candidate, then the §5.3 checks and the final integration trial on that candidate |
| S7 | X2–X4, the freeze, the final trial's squash tree, a fresh auto-deploy confirmation, the tag, and D's pre-merge check; then the sync-back via a helper branch |
| 152 (blocking) | D2; it must be a timestamp file |

## 6. Where this differs from D's sheet

**Reconciliation, 2026-10-07.** This is the single shared proposal. D's rev 4 (`10c0a8dc`) differs in two places, and
both are resolved here per the owner's direction:
- **Gate:** merge only, rather than D's "all three methods".
- **Console:** the protected PR route, rather than D's release-first. D's route was retired by the owner on
  2026-10-07, because after C2 and C3 it is no longer available.

D retired its sheet (rev 5, `1a2bd614`, kept as its measurement record), withdrew the release-first proposal in favour of the PR
route, and contributed the linear-history point, the real-ref sync-back trial, the vacuous-pass caveat and the
workflow-file diagnosis; all four are folded in above.


1. **Web.**
   - D routes `e7130f04` straight into the web branch. That is a 910-commit merge, so it should go in as the
     fast-forward `fd0da772` (§2).
   - D says 2 commits; there are 3.
   - Rollback is faster by Instant Rollback; the revert comes after.
2. **Console order and rollback.**
   - D has push, then pin. That cancels the build; it must be pin, then push.
   - D's rollback, "pin back to `ab3e17f1`", serves the same deployment; it rolls nothing back. The rollback is an
     Instant Rollback to `dpl_J5Kr…`, then the pin.
3. **Squash hazard.**
   - D: a direct commit to `main` "would be silently reverted by the next squash". **Tested: it is not.** A squash
     is a three-way merge, and the one-sided commit survived.
   - The real consequences are elsewhere:
     - a direct commit makes `main` ≠ the gate, which the tree check catches and PR-1 already prevents;
     - without a sync-back, later merges conflict.
   - So the rule is "squash, check the tree, sync back", not "only squashes forever".

**What cross-review caught, and the habit each error calls for at execution.**
- **D's errors were mostly behaviour asserted without being run:**
  - the console step order and its rollback;
  - the web base;
  - the squash "revert" claim;
  - the CI trigger;
  - the CLI cases.
  The habit: run it, or state it as unverified.
- **A's errors were mostly figures carried forward without being re-measured:**
  - building the console release on the served commit without checking the branch tip;
  - repeating the record's CLI sentence without checking its evidence.
  The habit: re-read every identifier fresh at the step that uses it (Evidence limits, last item).
- Every one was caught before execution. Each step's pass condition above is written so the habit applies itself.

## Evidence limits

- No production read was made. Production facts come from recorded read-backs.
- The Vercel facts come from the 09-08 deployment record and your 09-24 screenshots. A's Vercel token is refused, so
  the current alias and deployment ids are confirmed at execution.
- The squash trials use git's merge (`merge-tree`, ort). GitHub's own result is confirmed by the post-merge tree check.
- The local web build ran on Node 24; CI and Vercel use 22.
- **Read fresh at execution, never trusted from this sheet:**
  - `main` (`eadd456a`), the gate (`037092f0`), the web tip (`1765bbeb`), the console tip (`562fda9a`);
  - the console pin value;
  - the console rollback `dpl_J5Kr…`;
  - the web deployment serving before W4;
  - the ruleset list.
  Each step stops if a value differs.

# Execution sheet: remaining owner decisions (A, 2026-10-06)

**Reviewed code is not permission to deploy it.** Nothing below has been merged, pushed, applied, deployed or
switched on, and nothing in this sheet does any of that. Every step marked *owner* waits for your own word for
that step. This consolidates D's sheet (`review/d-records-20261005 @ 797c2d46`) with A's checks. §6 records where they differed;
D verified and accepted each point and revised its sheet to agree (rev 3, `342f2ab3`).

## 0. What is reviewed, and what would deploy it

| Artefact | Review state | What would put it live | Permission |
|---|---|---|---|
| 150/151 package (#94 `2eebc5bf`, #95 `9a66f29d`) | D PASS 28/28 | X2/X3 apply, X4 function deploys | none |
| Web wording, landing commit `fd0da772` (`web/wording-release-ff`, **local, not on the remote**) | `web/` tree `ab2eb1bf` = the reviewed `e7130f04`'s; tsc 0, 218/218, local `next build` exit 0. **No CI check has run on it** (§2) | merge into `feature/web-accounts-foundation` | none |
| Console labels, landing commit `efe03fca` (D, `admin/label-console-release-ff`, local) | `admin/src` `f297dab4` and `admin/tests` `6b76588f` = the reviewed `1058c882`'s; patch-ids equal | pin change, then push to `admin/operating-console` | none |
| Gate → `main` | method trial only (§4); the release candidate is not yet accepted or frozen | S7 | none |

## 1. Refund operations O-R1–O-R4

| | Exact choice | Recommended | Permits | Does not |
|---|---|---|---|---|
| **O-R3** | Who works `refund_failed` / `refund_pending` in `/cases`, how often, and the handling | **Name one person, daily**, and ratify: Stripe returns the money to the platform balance → contact the buyer from support@ → return it another way → note it on the case → **never re-refund automatically** | O-R2; the submission prerequisite (D6) | No code, no production change |
| **O-R1** | Stripe Dashboard, live endpoint for `stripe-webhook`: add `refund.created`, `refund.updated`, `refund.failed` | **Yes, at X5**, after X4a (new `stripe-webhook` live, C3) | Each refund's real state reaches `payment_refund_state`, including a failure after success | Opens no case; contacts nobody. Rollback: remove the 3 events |
| **O-R2** | Console → System → Settings → `refund_state_detection_enabled` = `true` (audited `setting_set`, platform_admin; needs your console sign-in) | **Yes, after O-R1 and only once O-R3 is decided** | Within 5 min: a p1 `refund_failed` case per failed refund, and `refund_pending` after 120 h | Alert delivery stays off: nobody is notified. Rollback: set `false` |
| **O-R4** | (1) one read-only Stripe read of the refunds behind the 7 historical refunded rows (2 live, 2026-08-04); (2) feed each through `record_refund_state(…,'reconcile')` | **Yes, two separate authorisations**: after X2 and O-R3; preferably after O-R2 so a reconciled failure becomes a case. A writes the package after X2 | Those rows show their true state instead of "Refund recorded" | Moves no money |

If all four stay open, the interim is the package README §2A: a failure is seen only via `charge.refunded` or the
expiry job, the payment is parked, the app says "Refund of $X initiated", and nobody contacts the buyer.

## 2. Web: protection, then deployment

**W1 *owner*: protection (GitHub → Settings → Rules → New branch ruleset), target `feature/web-accounts-foundation`,
in two parts.** Repository-wide merge settings are unchanged (§4A).
- **W1a, executable now:**
  - restrict deletions; block force pushes; no bypass actors;
  - require a pull request, 0 approvals, **allowed merge methods `merge` only** (the reviewed commits stay as
    parents).
- **W1b, the required check: NOT executable yet.**
  - The exact context is **`Web build (Next.js)`**, source **GitHub Actions** (integration id 15368, as on `main`'s
    ruleset). On `1765bbeb` it reported `success` from that app.
  - On the web branch, ci.yml runs on `pull_request: branches: [main]` and `push: branches-ignore: [main]`. So a PR into
    this branch gets no pull_request run, and the check can only come from the **push** run on the head commit.
  - **`fd0da772` is not on the remote, so no check has run on it.** A's push of the branch was refused by this
    session's permission check and was not retried.
  - W1b becomes executable only after W2 shows the exact context `success` on `fd0da772`.
  - Never require `Secret scan`, `Dependency review`, CodeQL, `Supabase Preview` or `Vercel Preview Comments`. The first
    three never run on PRs into this branch. The last two are third-party apps (`Supabase Preview` reports `skipped`).
- A reads each part back through the API.

**Why a fast-forward commit.** `e7130f04` is built on the gate, **910 commits** away from the web branch tip
`1765bbeb`. A PR of it would carry 1,100 files of gate history into the live branch. Instead, the same 3 commits
were cherry-picked (`-x`) onto `1765bbeb`. The result is `a6cd359f` → `c2aa632c` → `fd0da772`:
- its `web/` tree `ab2eb1bf` is identical to `e7130f04`'s;
- its patch-ids are equal to the reviewed commits';
- it changes 0 files outside `web/`, and 11 files, +990/−101, in total;
- typecheck 0, vitest 13 files / 218, `next build` exit 0 with CI's placeholders.

| Step | Who | Action | Effect / gate |
|---|---|---|---|
| W2 | *owner's go*; A's push was refused, so **you push or allow it** | push `web/wording-release-ff` (`fd0da772`), a non-deploy branch | CI push run. The web preview is skipped by its Ignored Build Step; no admin deployment; no production effect. **Pass condition:** check run `Web build (Next.js)`, app GitHub Actions, conclusion `success`, head sha `fd0da772` |
| W1b | *owner* | add the required check (above) | only after W2's pass condition is read |
| W3 | A | open the PR into `feature/web-accounts-foundation`; confirm the same check green **at `fd0da772` on the PR** and that the diff is the 11 files | — |
| W4 | *owner* (**this is the deployment**) | merge the PR (merge commit) | Vercel builds production from the merge commit |
| W5 | A + owner | the merge commit's tree equals `fd0da772`'s; the production deployment is READY on that sha (dashboard: A's token is refused); spot-check `/account/purchases`, `/account/sales` and the transfer pages signed in | — |

**Rollback:** Vercel → snatchit-web → Instant Rollback to the production deployment that precedes W4. Its id is not on
record; `1765bbeb` carries a Vercel "Deployment has completed" status, but which deployment is serving is **read fresh
at W4**. Then a revert PR, so the branch matches what is served.

The gate gets the same change via S4 (`e7130f04`). That is one change with two identities.

## 3. Admin console: releasing the label fix

**Why not `1058c882` itself.** `admin/operating-console` is at `562fda9a`, 5 commits past the served `ab3e17f1`
(docs plus `admin/scripts/acceptance/gate-probe.mjs`, which the app never imports). So `1058c882` is not a
fast-forward. D's `efe03fca` is (`562fda9a` → `ccac575d` → `efe03fca`). Its only difference from `1058c882` is
those two non-app files (verified by A).

| Step | Who | Action |
|---|---|---|
| X8a | *owner* | Vercel → snatchit-admin → Settings → Build and Deployment → Ignored Build Step: `test "$VERCEL_GIT_COMMIT_SHA" != "efe03fca5a88b074b2a675fb24fe718b53a9f4a3"`. Save and read back. Nothing builds |
| X8b | *owner* (**the deployment**) | `git push origin efe03fca5a88b074b2a675fb24fe718b53a9f4a3:refs/heads/admin/operating-console`, with no `--force`. Git refuses anything other than a fast-forward. Vercel builds production |
| X8c | owner + D | the deployment is READY for `efe03fca` and the alias has moved; sign in at aal2 (**needs your new authenticator**); D runs the label checks on the order page |

**The order matters.** If the push comes first, the old pin cancels that build, and moving the pin afterwards
rebuilds nothing.

**Rollback target: `dpl_J5Kr4QSBmRjxmJbu2nT7KovSxmsr`.** This is a **record fact** (`ab3e17f`, aliased 2026-09-08; no newer
admin deployment at D's 09-24 read). **Re-read the alias and the current pin value at X8a** before relying on either.
- Instant Rollback to it, then set the pin back to `ab3e17f1a36e8c78c9fce31ee0b4fafdb6934d64`.
- Moving the pin alone rolls nothing back.

**Console protection must not require a PR** (corrects PR-7's console row; raised by D).
- Pin-then-push needs the sha known before the push. A PR merge creates a sha nobody knows in advance, so a
  PR-required rule would break X8 and every later console release.
- **Proposed console ruleset:** restrict deletions and block force pushes only.
  - `non_fast_forward` still forbids rewriting the branch.
  - The pin remains the build gate: a push of any other sha builds nothing.
- It can be added before or after X8.

**One change, three identities** (equal patch-ids):
- gate `004af0b0` / `789025f3` (S3);
- reviewed `72ac2c52` / `1058c882`;
- landing `ccac575d` / `efe03fca`.

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

**Proposed configuration (MM-1):**

| Where | Allowed methods | Other rules | Serves |
|---|---|---|---|
| Repository settings | **unchanged**: merge, squash, rebase | — | Turning off merge commits repository-wide would break S1–S5, the web merge and the sync-back. Rulesets narrow per branch |
| `main` (ruleset 21624091) | **`squash` only** (drop `rebase`) | keep linear history, the 5 checks, no deletion, no force-push | S7 squash; removes the one-click rebase that would rewrite 906 commits |
| gate `release/production-gate-20260918` (new) | **`merge` only** | no deletion, no force-push; PR required; PR-1's checks plus `Admin console (Next.js)` and `Deno type-check (edge functions)` | S1–S6 and the sync-back PR keep the reviewed shas |
| web `feature/web-accounts-foundation` (new, §2) | **`merge` only** | W1a now, W1b after W2 | W4 |
| console `admin/operating-console` (new, §3) | no PR rule | no deletion, no force-push | X8's pin-then-push, now and later |
| records `release/candidate-20260918` (new) | no PR rule | no deletion, no force-push | direct record pushes continue |

The required checks on the gate and web PRs report through push runs on head branches pushed to this repository.

## 5. Independent, or waiting

**Can proceed independently** (each still needs your word):
- **W1a, protecting the web branch.** This is the most urgent; executable now. W1b waits on W2's observed check.
- The other PR-7 rulesets, plus PR-1, PR-2, PR-5 and PR-6.
- **O-R3** (a decision).
- **MM-1**, the merge-method configuration (§4A). It settles PR-3 as squash, and is needed only by S1 and S7.
- **The console release X8a–X8c.** Its verification needs your sign-in.
- **The web wording:** W2 (your push), then W1b, then W3–W4.
- The stale-PR closures, each with an archive tag.
- **Your TOTP check:** A's read-only factor list, once you confirm enrolment.

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
| S1 → S2 | your merge go; #94 before #95 (C6) |
| S5 | B's review of `d5217530` (C's batch2 is separate), the owner's acceptance of the v3 candidate, then the §5.3 checks and the final integration trial on that candidate |
| S7 | X2–X4, the freeze, the final trial's squash tree, a fresh auto-deploy confirmation, the tag, and D's pre-merge check; then the sync-back via a helper branch |
| 152 (blocking) | D2; it must be a timestamp file |

## 6. Where this differs from D's sheet

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

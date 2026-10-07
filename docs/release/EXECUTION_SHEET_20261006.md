# Execution sheet: remaining owner decisions (A, 2026-10-06)

**Reviewed code is not permission to deploy it.** Nothing below has been merged, pushed, applied, deployed or
switched on, and nothing in this sheet does any of that. Every step marked *owner* waits for your own word for
that step. This consolidates D's sheet (`review/d-records-20261005 @ 797c2d46`) with A's checks; where they differ,
§6 says which and why.

## 0. What is reviewed, and what would deploy it

| Artefact | Review state | What would put it live | Permission |
|---|---|---|---|
| 150/151 package (#94 `2eebc5bf`, #95 `9a66f29d`) | D PASS 28/28 | X2/X3 apply, X4 function deploys | none |
| Web wording, landing commit `fd0da772` (`web/wording-release-ff`, local) | `web/` tree `ab2eb1bf` = the reviewed `e7130f04`'s; tsc 0, 218/218, `next build` exit 0 (today) | merge into `feature/web-accounts-foundation` | none |
| Console labels, landing commit `efe03fca` (D, `admin/label-console-release-ff`, local) | `admin/src` `f297dab4` and `admin/tests` `6b76588f` = the reviewed `1058c882`'s; patch-ids equal | pin change, then push to `admin/operating-console` | none |
| Gate → `main` | trial only; the candidate is not frozen | S7 | none |

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

**W1 *owner*: protection (GitHub → Settings → Rules → New branch ruleset), target `feature/web-accounts-foundation`.**
- Restrict deletions; block force pushes; no bypass actors.
- Require a pull request, 0 approvals, **merge commits only** (the reviewed commits stay as parents).
- Required check: **`Web build (Next.js)` only.** It runs on the push of the PR's head branch (ci.yml at the web
  branch: `push: branches-ignore: [main]`). **Do not require** `Secret scan` or `Dependency review`: they run only
  on PRs into `main`, so they would never report and every PR would block.
- A reads the ruleset back through the API.

**Why a fast-forward commit.** `e7130f04` is built on the gate, **910 commits** away from the web branch tip
`1765bbeb`. A PR of it would carry 1,100 files of gate history into the live branch. Instead, the same 3 commits
were cherry-picked (`-x`) onto `1765bbeb`. The result is `a6cd359f` → `c2aa632c` → `fd0da772`:
- its `web/` tree `ab2eb1bf` is identical to `e7130f04`'s;
- its patch-ids are equal to the reviewed commits';
- it changes 0 files outside `web/`, and 11 files, +990/−101, in total;
- typecheck 0, vitest 13 files / 218, `next build` exit 0 with CI's placeholders.

| Step | Who | Action | Effect |
|---|---|---|---|
| W2 | *owner's go* | push `web/wording-release-ff` (`fd0da772`) | CI runs; the web preview is skipped by its Ignored Build Step; no admin deployment. No production effect |
| W3 | A | open the PR into `feature/web-accounts-foundation`; confirm `Web build (Next.js)` green **at `fd0da772`** and that the diff is the 11 files | — |
| W4 | *owner* (**this is the deployment**) | merge the PR (merge commit) | Vercel builds production from the merge commit |
| W5 | A + owner | the merge commit's tree equals `fd0da772`'s; the production deployment is READY on that sha (dashboard: A's token is refused); spot-check `/account/purchases`, `/account/sales` and the transfer pages signed in | — |

**Rollback:** Vercel → snatchit-web → Instant Rollback to the production deployment that precedes W4 (read its id at W4;
it is not on record). Then a revert PR, so the branch matches what is served.

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

**Rollback target: `dpl_J5Kr4QSBmRjxmJbu2nT7KovSxmsr`** (`ab3e17f`, aliased 2026-09-08; there was no newer admin
deployment at D's 09-24 read, so confirm the alias at X8a).
- Instant Rollback to it, then set the pin back to `ab3e17f1a36e8c78c9fce31ee0b4fafdb6934d64`.
- Moving the pin alone rolls nothing back.

**One change, three identities** (equal patch-ids):
- gate `004af0b0` / `789025f3` (S3);
- reviewed `72ac2c52` / `1058c882`;
- landing `ccac575d` / `efe03fca`.

## 4. `main` integration under the rules in force: squash

**Why squash.** Merge commits are not allowed today. Rebase would rewrite all 906 commits, merge commits included,
so no recorded sha would name a commit on `main`.

**Verified today** (local; predictions registered first, sha256 `0c586b1b…`):
- **`main` `eadd456a` is an ancestor of the gate:** 0 behind, 906 ahead.
- **Today's gate:** a squash gives tree `e6b9589b`, which **equals the gate's tree**.
- **The trial combined candidate** is the gate plus S1 #94, S2 #95, S3 labels, S4 wording and S5 v3 `f3f08930`, as
  merge commits, local only. It is `879a34ca` (`refs/review/s7-trial-candidate`), tree `1b76e9cd`.
  - It merged with no conflicts.
  - Each branch's files equal that branch's version: 13 / 3 / 3 / 11 / 235 files.
  - S5 has the 3 known both-sided files, as in the 09-26 trial.
- **Squashing that candidate onto `main` gives `1b76e9cd`: identical.**

**At S7** (after X2–X4, the freeze, and a fresh `AUTODEPLOY-VERIFIED-OFF`):
1. `main` still `eadd456a` (no dependabot merges first); PR head = the frozen candidate; required checks green there.
2. *owner's go*: annotated tag `release/s7-<date>` at the frozen candidate, and PR-7 on the gate (no deletion or
   force-push). These keep every cited sha reachable.
3. Squash with a written message carrying `Release-Candidate: <sha>`, `Release-Tree: <tree>` and the tag.
4. **Post-merge:** the squash commit's tree equals the candidate's tree. This is the D1 claim; `main` then holds
   exactly what the gate replays.
5. **Sync-back, immediately:** merge `main` back into the gate. It is a merge commit and **its tree must equal the
   candidate's**.
   - Trial: the sync-back's tree was `1b76e9cd`, unchanged.
   - Without the sync-back, a later gate edit to a line the squash introduced **conflicts** (trial: `ci.yml`).
   - With it, the next squash is clean and equals the new gate's tree (trial).

**Traceability.**
- **Migration ancestry.** Each migration on `main` is byte-identical to the candidate's, as implied by the tree check.
  - `git log release/s7-<date> -- supabase/migrations/<file>` gives its original commit and PR.
  - The ledger row (`created_by`) and the registry map each version to its PR, head and apply record.
  - `git log main` will show only the squash commit for each migration. That loss of lineage is the whole cost of a
    squash.
- **Later merges.** These follow the same pattern: squash, tree check, then sync-back.
- If you approve PR-3 instead, a merge commit keeps the shas on `main` and needs no sync-back; the trees are identical.

## 5. Independent, or waiting

**Can proceed independently** (each still needs your word):
- **W1, protecting the web branch.** This is the most urgent.
- The other PR-7 rulesets, plus PR-1, PR-2, PR-5 and PR-6.
- **O-R3** (a decision).
- **PR-3** (needed only by S7).
- **The console release X8a–X8c.** Its verification needs your sign-in.
- **The web wording W2–W4**, after W1.
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
| S5 | B's review of `f3f08930` and the §5.3 candidate checks |
| S7 | X2–X4, the freeze, a fresh auto-deploy confirmation, the tag, and D's pre-merge check; then the sync-back |
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

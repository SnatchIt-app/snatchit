# Execution sheet: the remaining owner decisions (D, 2026-10-06, **revision 4**)

> **Revision 3.** Revision 2 corrected five errors in revision 1, all found by A and each re-verified here against the
> repository, the 2026-09-08 deployment record or a run experiment: the console step order was backwards
> (§3), the console rollback target was wrong (§3), the web branch has the same base problem I had caught
> for the console and missed for the web (§2), the squash "silently reverted" hazard is false (§4), and the
> web branch carries three commits, not two. A's consolidated sheet is
> `docs/release/EXECUTION_SHEET_20261006.md` on the records line. Revision 3 corrects one more of
> mine — the `ci.yml` trigger in §2 — and sharpens the sync-back timing in §4. **Revision 4** (owner,
> 2026-10-06) replaces the stale `f3f08930` candidate in §4, resolves the merge-method compatibility
> question in a new §2A, and records in §2/§3 what is *not yet* verifiable. It introduces two new owner
> decisions, **PR-8** and **PR-9**.

**Reviewed code is not permission to deploy it.** Everything below is reviewed and sitting still. Nothing
has been merged, pushed, applied or deployed, and nothing in this sheet does any of that.

| Artefact | State | What would move it |
|---|---|---|
| 150 / 151 package | frozen, rehearsed, **D PASS 28/28** | X1b → X2 → X3, each separately authorised |
| #94 / #95 | CI green, D PASS | merge to the gate (S1, S2) |
| `web/wording-truth-conditions @ e7130f04` | **A PASS** | a push, which deploys the live web |
| console label `efe03fca` (see §3) | **A PASS** on the identical console tree | a push plus the build pin |
| gate → `main` | not prepared | PR-3 decision first |

---

## 1. O-R1 – O-R4

| id | The choice | Recommended | What it permits | What it still does not do |
|---|---|---|---|---|
| **O-R1** | Add `refund.created`, `refund.updated`, `refund.failed` to the live Stripe endpoint (Dashboard) | **Yes, at X5** — after the new `stripe-webhook` is live | The database observes each refund's real state instead of inferring it from `charge.refunded` | Nothing acts on it. Detection is still off |
| **O-R2** | Flip `refund_state_detection_enabled` to `true` (audited runtime setting, not a migration) | **Yes, but only after O-R3 is answered** | A p1 `refund_failed` case opens in `/cases` | Notifies nobody: alert delivery is off |
| **O-R3** | Who works `refund_failed` and `refund_pending`, and how | **Name a person, and ratify the recorded handling:** Stripe returns the money to the platform balance → contact the buyer from support@ → return it another way → record it on the case → **never re-refund automatically** | O-R2 to be worth switching on, and the failed-refund wording to ship | — |
| **O-R4** | Reconcile the 7 historical refunded rows (2 live on 2026-08-04): an authorised read-only Stripe read, then `record_refund_state(…, 'reconcile')` | **Yes, after O-R2** — a separate authorised step | Those rows stop reading "Refund recorded" | — |

**If all four stay open** (stated so the interim is chosen, not inherited): a failed refund is observed only
via `charge.refunded` or the expiry job's own reconcile, or not at all; once observed the payment is parked
(`refund_failed_cents > 0`) and never automatically re-refunded; the app says "Refund of $X initiated"; and
**nobody contacts the buyer.** O-R3 is a submission prerequisite for that reason.

---

## 2. Web branch protection, then the wording deploy

**Today `feature/web-accounts-foundation` has no rules at all, and any push to it deploys the live site.**
Measured 2026-10-05: the rules endpoint returns 0 for that branch, with `main` returning 5 as a control.
This is the most urgent protection gap, ahead of anything on `main`.

**W1 — protect it (owner, in the GitHub UI; independent of everything else).** No deletion, no force-push,
PR required, and **`Web build (Next.js)` as the only required check**.
- `security.yml` is `pull_request: branches: [main]`, so Secret scan and Dependency review never run on a
  PR into this branch; requiring either would block every one.
- **`ci.yml` is also `pull_request: branches: [main]`, plus `push: branches-ignore: [main]`** — read
  directly at the gate, at `1765bbeb` and at `fd0da772`, identical in all three. (Revision 2 said it "runs
  on all PRs". That was the same faulty parser that had already misled me once on `security.yml`; I
  re-checked only the file it had misled me on, and trusted its other output.) So a PR into the web branch
  gets **no `pull_request` run at all**: `Web build (Next.js)` reports from the **push** run on the head
  commit. It can still be required — GitHub matches a required context by name on the head sha whatever
  event produced it — but W3 must confirm the check is actually green at `fd0da772` on the PR before
  anyone relies on it.

**PR-9 (new owner decision): the rule is not yet verifiable, so configure it, then prove it.** The exact
context string is **`Web build (Next.js)`**, produced by `github-actions` — confirmed present and
`success` on the gate tip, which is itself a non-`main` branch and so a push-event run, corroborating the
mechanism above. But **`fd0da772` is not on the remote** (`GET /commits/fd0da772…` → HTTP 422, no commit),
so **no check run exists for it and the rule cannot be shown executable today**. Sequence:
- W1a configure the ruleset with `Web build (Next.js)` as the only required check;
- W1b push the landing commit and **observe** that the context appears and is green on it;
- **W3 gates on W1b**, not on the inference. If the context does not appear, the rule blocks every PR into
  the branch and must be removed before anything can land.
- Do **not** require `Supabase Preview` or `Vercel Preview Comments`: both appear on these commits but come
  from third-party apps, and `Supabase Preview` reports `skipped`.

Do this before W2, so the PR becomes the only way in.

**W2 — the wording change, from a branch that can actually land (corrected).** `web/wording-truth-conditions
@ e7130f04` is **three** commits (not two, as revision 1 said) and is based on the **gate**. The web
production branch tip `1765bbeb` is **not an ancestor of it**: 910 commits and 1,111 differing files, 1,100
of them outside `web/`. A PR from it into the live branch would carry the whole gate history. This is the
same defect I found for the console in §3 and did not apply to the web — A caught it.
- Use **`fd0da772`** (A's `web/wording-release-ff`), the three commits cherry-picked onto `1765bbeb`.
- Verified here: it **is** a fast-forward of the tip, 3 commits, its `web/` tree `ab2eb1bf…` is **identical**
  to `e7130f04`'s, and it changes **0 files outside `web/`**.
- `e7130f04` stays the reviewed artefact; `fd0da772` is the same change positioned to land.

**W3 — the deploy is the push.** There is no separate deploy step. Merging the PR into
`feature/web-accounts-foundation` builds and publishes.

**Rollback:** revert the commit on the web production branch; the revert push redeploys. No database change
is involved — the change reads three columns that have been in production since before migration 075.

### 2A. Merge-method compatibility (new; measured 2026-10-06)

The sheet asks for merge commits on the integration branches while `main` forbids them. **Measured, these do
not actually conflict today** — but the obvious way to implement squash-to-`main` would create the conflict.

- **Repository level: all three methods are enabled** — `allow_merge_commit`, `allow_squash_merge`,
  `allow_rebase_merge` all `true`. (`allow_auto_merge` is `false`.)
- **Exactly one ruleset exists**: `main-protection` (21624091), targeting `~DEFAULT_BRANCH` **only**, with
  `allowed_merge_methods: ["rebase","squash"]`.
- **No ruleset targets the gate, the web branch, the console branch or the records line.** On those, all
  three repository methods are available.

**The hazard to avoid:** enforcing squash-to-`main` by turning **off** `allow_merge_commit` at the
repository level. That toggle is global; it would make S1–S5 merge commits into the gate impossible, and the
per-branch restriction that is actually wanted already exists on `main` via the ruleset.

**One compatible configuration:**

| Scope | Setting | Why |
|---|---|---|
| Repository | leave all three methods enabled; change nothing | the restriction belongs on branches, not globally |
| `main` | ruleset 21624091 unchanged (`rebase`, `squash`); S7 uses **squash** | already in force, already satisfies §4 |
| gate | new ruleset, `allowed_merge_methods: ["merge","squash","rebase"]` | S1–S5 use merge commits |
| `feature/web-accounts-foundation` | new ruleset, `allowed_merge_methods: ["merge"]` | one method, so the landing method cannot drift; it preserves the three cherry-picked commits and their `(cherry picked from …)` trailers back to the reviewed originals |
| records line | no merge-method restriction | direct pushes of records continue |

Set `allowed_merge_methods` **explicitly** on each new ruleset rather than relying on a default.

**PR-8 (new owner decision): the console branch cannot have "PR required" before its release.** PR-7
proposes `PR required` on `admin/operating-console`, and §3's release is a **fast-forward push of a known
sha** — the Ignored Build Step pins an exact sha (`test "$VERCEL_GIT_COMMIT_SHA" != "<pin>"`), which must be
set *before* the push. A PR merge produces a sha that is not knowable in advance, so pin-then-push cannot
work through a PR. Options:
- **(a) Recommended: release first, protect after.** Pin → fast-forward push `efe03fca` → then add the
  console ruleset. One ordering constraint, no mechanism change.
- (b) Protect now and grant the owner a bypass actor for that branch. Keeps the rule but removes its effect
  for the one actor who would use it.
- (c) Protect now and release through a PR, re-pinning to the merge commit's sha afterwards and redeploying.
  Two pin changes and a wasted build.

---

## 3. Admin console: the configuration change, and one correction

**Correction found today.** `admin/operating-console` is at `562fda9a`, **five commits ahead of the pin the
console actually serves** (`ab3e17f1`). The reviewed commit `1058c882` was built on the pin, so it is **not**
a fast-forward of the branch tip (2 ahead, 5 behind). The plan's X8 as written would not apply cleanly.

Those five commits are **docs plus one acceptance script** (`admin/scripts/acceptance/gate-probe.mjs`). They
touch **no console code**: `admin/src` and `admin/tests` are untouched.

**So the label change was rebuilt on the branch tip: `efe03fca5a88b074b2a675fb24fe718b53a9f4a3`.**
- `admin/src` and `admin/tests` trees are **byte-identical** to the reviewed `1058c882` (`f297dab4…` /
  `6b76588f…`), so A's PASS carries over by tree identity. The only `admin/` difference is `gate-probe.mjs`,
  which is not console code.
- It **is** a fast-forward of the console branch tip: 2 commits, 3 files, +378/−6.
- tsc 0, eslint 0, admin 16 files / 117 tests.

**The change needed to release it — the order is the opposite of revision 1's (A's correction, confirmed
from the 09-08 record):**
1. **First, Vercel → `snatchit-admin` → Settings → Git → Ignored Build Step: change the pinned sha from
   `ab3e17f1a36e8c78c9fce31ee0b4fafdb6934d64` to `efe03fca5a88b074b2a675fb24fe718b53a9f4a3`.** The guard is
   `test "$VERCEL_GIT_COMMIT_SHA" != "<pin>"`, where exit 0 skips. So a push made while the old pin is in
   place is **cancelled**, and changing the pin afterwards rebuilds nothing — Vercel does not re-run on a
   settings change. The record proves the mechanism live: the docs push `2459bdc` was cancelled with exactly
   that message while the alias stayed put.
2. **Then push `efe03fca` to `admin/operating-console`** (fast-forward). Owner's action — D never pushes
   that branch. That push is what builds and deploys.
   It also brings the five already-pushed docs/script commits into the built commit — no console code.

**Rollback: an Instant Rollback to deployment `dpl_J5Kr4QSBmRjxmJbu2nT7KovSxmsr`, then restore the pin to
`ab3e17f1`.** **That identifier is from the 2026-09-08 record and is a month old. Re-read the alias at
execution** — `vercel inspect snatchit-admin.vercel.app`, or the dashboard — and confirm it still resolves
to that deployment before relying on it. The same applies to the pin's current value: read it back before
changing it, not from this sheet. Revision 1 said "pin back to `ab3e17f1`", which is wrong on its own: the production alias
points at a deployment, and a build setting does not move an alias. That deployment is the `ab3e17f` build
the alias currently serves (09-08 record, rows 81 and 121). No database change either way — the console is
a read surface plus `ops.execute_action`, and nothing in this release touches either.

---

## 4. `main` integration: **squash**

**Rebase is the wrong choice.** GitHub's rebase-merge replays the 906 commits as new objects with new shas.
Every record we hold cites gate shas; after a rebase none of them would name a commit on `main`.

**Squash, verified today:**
- A squash of gate `037092f0` onto `main eadd456a` produces tree **`e6b9589b9bd4ca1c7df108cf608a377a40116472`**,
  **identical to the gate's tree**. Control: `main`'s own tree is `84f84210…` and differs.
- It holds because `main` is an ancestor of the gate (0 behind, 906 ahead), so the merge result is the gate's
  content exactly.
- It satisfies the ruleset: one commit, one parent, linear history, and squash is an allowed method.

**The trial establishes the merge method, not the release contents.** A built an S1–S5 trial candidate
(`879a34ca`, tree `1b76e9cd…`; per-step file counts 13 / 3 / 3 / 11 / 235, no conflicts) and its squash onto
`main` yields tree **`1b76e9cd…`, identical** — verified here. **That is all it establishes.** Its S5 input
was `f3f08930`, which is **stale**:
- **B is reviewing `d52175303f22a575b80f005f38c0e8555be0dbdc`** (2026-10-05 23:06, on `v3/midnight-app` and
  `v3/consumer-batch2`). Verified: `f3f08930` is its ancestor and it is 3 commits beyond it.
- **C's batch2 fixes are a separate track** and are not in either figure.
- So the per-step file counts, the candidate sha and the tree are **properties of the trial, not of the
  release**. Nothing downstream may cite `879a34ca` or `1b76e9cd` as the release content.

**The integration trial must be re-run on the eventual accepted candidate**, once B's review concludes and
C's batch2 lands — and again at freeze if the candidate moves. Each re-run repeats the same two checks: the
per-step merge produces exactly its branch's files, and the squash onto `main` is tree-identical.

**How ancestry stays traceable, given 906 commits collapse into one:**
- **Migration ancestry does not live in git.** It lives in `supabase_migrations.schema_migrations`: version,
  name, `statements`, and a `created_by` tag per applied row. That record is unaffected by how the source
  reaches `main`.
- **`MIGRATION_NUMBER_REGISTRY.md` maps each number to its PR, branch, head commit and apply record.** That
  mapping is what anyone follows back, not `git log main`.
- **The gate branch is preserved and never deleted.** Every per-migration commit stays reachable there, and
  the gate is protected under PR-7. Recommended additions: the squash commit message records the exact gate
  sha, and a tag is placed at that gate commit.
- **Later merges — revision 1 was wrong about the hazard.** I claimed a direct commit to `main` would be
  silently reverted by the next squash. **It is not.** `git merge --squash` is a three-way merge against the
  merge-base, not a tree overwrite. Tested here: after a squash, a direct commit on `main`, then a gate
  advance touching a different file — the direct change **survived** and the gate's change landed, exit 0.
  I asserted that behaviour without running it.
  - **The real hazard is a conflict.** When the gate later edits a file the squash introduced, the
    merge-base has no such file, so both sides look like additions. Tested: exit 1, one conflicted file.
  - **A sync-back clears it, and the timing is the whole point.** Merging `main` back into the gate
    restores `main` as an ancestor, after which the next squash is clean and equals the new gate's tree.
    Done **immediately after the merge, before anything else lands on the gate**, it is trivial and
    tree-equal — at that moment the two trees are already identical. My own sync-back conflicted only
    because I had deferred it past a divergent edit; deferred, it is the same merge as the next squash run
    the other way, and the conflict is resolved once, there.
  - **So the rule is: squash → check the tree → sync back immediately**, not "only squashes forever".

---

## 5. What can proceed independently, and what must wait

**Independent — no dependency on anything else here (all owner actions):**
- **W1, protect `feature/web-accounts-foundation`.** The most urgent item on this sheet.
- **PR-3**, choose the `main` merge method (recommendation above).
- **The stale-PR closures**, with the per-PR evidence already recorded.
- **O-R3**, a decision rather than an action, and the one that unblocks two others.
- **The admin console release (§3).** Independent of S1–S7, the migrations and the refund work.

**Must wait, and on what:**

| Action | Waits on |
|---|---|
| X1b transport proof | X1a, the auto-deploy visual check |
| X2 apply 150 | X1b passing — **if the probe does not report one transaction, stop** |
| X3 apply 151 | X2. It arms a live detector within five minutes |
| X4 deploy the two functions | X2 (they call `record_refund_state`) |
| O-R1 | X4a |
| O-R2 | O-R1 **and** O-R3 |
| O-R4 | O-R2 |
| S1 → S2 | #94 merges before #95, or the ordering guard rejects #94 |
| S7, gate → `main` | X2–X4 done, PR-3 decided, and a **fresh** auto-deploy confirmation |
| The web wording deploy | W1 first |
| The blocking package (152) | the D2 decision; it must be a timestamped file |

---

## Evidence limits on this sheet

Every statement about production rests on recorded read-backs, not a current read; no production read was
made. The tree, branch, ruleset and commit facts were measured today against the repository and the GitHub
API, each with a control. The 150/151 PASS covers the package as written and rehearsed — not the production
transport, which X1b is what establishes, and not any real refund behaviour.

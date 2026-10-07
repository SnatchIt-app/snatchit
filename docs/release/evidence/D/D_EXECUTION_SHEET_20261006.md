# Execution sheet: the remaining owner decisions (D, 2026-10-06)

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
PR required, `Web build (Next.js)` required. Do this before W2, so the PR becomes the only way in.

**W2 — the wording change.** Two commits on `web/wording-truth-conditions @ e7130f04`, A PASS. The plan
routes it to the gate first (S4) and to the web branch as X9; the gate's `web/` and the production branch's
`web/` were verified equal, so the same commits serve both.

**W3 — the deploy is the push.** There is no separate deploy step. Merging the PR into
`feature/web-accounts-foundation` builds and publishes.

**Rollback:** revert the commit on the web production branch; the revert push redeploys. No database change
is involved — the change reads three columns that have been in production since before migration 075.

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

**The change needed to release it, in order:**
1. **Push `efe03fca` to `admin/operating-console`** (fast-forward). Owner's action — D never pushes that branch.
2. **Vercel project `snatchit-admin`: move the Ignored Build Step pin from `ab3e17f1` to `efe03fca`.** That
   is the whole configuration change. It also, unavoidably, brings the five already-pushed docs/script commits
   into the built commit — no console code among them.

**Rollback target: the pin back to `ab3e17f1`.** One configuration change, no revert needed, no database
change. The console is a read surface plus `ops.execute_action`; nothing in this release touches either.

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

**This check must be re-run against the frozen commit at freeze time.** Today's gate is not the frozen
integration candidate; the candidate will carry S1–S5 (and S6 if blocking is approved). The check is one
command and its result is the gate-equality claim the whole D1 argument rests on.

**How ancestry stays traceable, given 906 commits collapse into one:**
- **Migration ancestry does not live in git.** It lives in `supabase_migrations.schema_migrations`: version,
  name, `statements`, and a `created_by` tag per applied row. That record is unaffected by how the source
  reaches `main`.
- **`MIGRATION_NUMBER_REGISTRY.md` maps each number to its PR, branch, head commit and apply record.** That
  mapping is what anyone follows back, not `git log main`.
- **The gate branch is preserved and never deleted.** Every per-migration commit stays reachable there, and
  the gate is protected under PR-7. Recommended additions: the squash commit message records the exact gate
  sha, and a tag is placed at that gate commit.
- **Later merges:** after a squash, `main` and the gate share only the old base, so every subsequent
  integration must also be a squash, computed as the new gate against the current `main`. **The hazard that
  creates:** anything committed directly to `main` would be silently reverted by the next squash. The rule
  that removes it is that `main` receives squashes from the gate and nothing else — which PR-1's protection
  already enforces, since a direct push is refused.

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

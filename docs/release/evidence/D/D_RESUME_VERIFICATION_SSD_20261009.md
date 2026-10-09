# D — SSD resume verification, 2026-10-09

Verified against `/Volumes/DEV-SSD/01_SNATCH_IT/migration-records/MIGRATION_HANDOFF.md` before any edit.
All reads below are D's own, from the SSD.

## Drive identity

`diskutil info /Volumes/DEV-SSD` → Volume UUID **`6A74DBD6-ACDE-4D44-B19D-9057E671E510`**, matching the
handoff exactly. Mount point `/Volumes/DEV-SSD`, name `DEV-SSD`.

## The five worktrees D owns — all MATCH, all clean

Root: `/Volumes/DEV-SSD/01_SNATCH_IT/repos/`

| folder | branch | commit | dirty |
|---|---|---|---|
| `snatchit-drecords` | `review/d-records-20261005` | `ca8fe95e9c55…` | 0 |
| `snatchit-webword` | `web/wording-truth-conditions` | `e7130f046a62…` | 0 |
| `snatchit-labelrel` | `admin/label-console-release` | `1058c8825b97…` | 0 |
| `snatchit-integ` | `review/d-integ-94-95` | `486c954cd918…` | 0 |
| `snatchit-labelff` | `admin/label-console-release-ff` | `efe03fca5a88…` | 0 |

Every branch and commit matches the handoff table. No working changes anywhere.

## The check that mattered most: writes stay on the SSD

All five worktrees share one object store, and `git rev-parse --git-common-dir` in each now returns
**`/Volumes/DEV-SSD/01_SNATCH_IT/repos/snatchit/.git`**. None resolves to `/Users/josetascon/...`.

This was the live hazard. These are linked worktrees, so before the migration they all pointed at
`/Users/josetascon/snatchit/.git`. Had any one of them still pointed there, committing from the SSD
folder would have written into the **Mac originals** — which the owner's instruction forbids — while
appearing to work normally. Checked per worktree, not inferred from the handoff's aggregate
"276 Git metadata paths now resolve exclusively to the SSD".

## Local-only branches: preserved, still unpushed

| branch | upstream | remote refs containing it |
|---|---|---|
| `review/d-records-20261005` | none | **0** |
| `web/wording-truth-conditions` | none | **0** |
| `admin/label-console-release` | none | **0** |
| `review/d-integ-94-95` | none | **0** |
| `admin/label-console-release-ff` | none | 4 ✓ |

**Control:** the same instrument returns **152** remote refs for `origin/main`, so it discriminates and
the zeros are real — not the false zero that `git log @{u}..HEAD` produced before the migration, where an
unset upstream reads identically to "fully pushed".

So the migration preserved all four unpushed branches, as its §D note states, and pushed nothing.

## Capture integrity

The six files committed in `ca8fe95e` immediately before the pause are present and readable from the
SSD object store, with sizes intact:

| blob | bytes | file |
|---|---|---|
| `5ce53679f786` | 1924 | `captures_20261008/README.md` |
| `f34ce1993951` | 149 | `stripe_r1_wrong_account.stderr.txt` |
| `4e69578896f7` | 387 | `stripe_r1_wrong_account.stdout.txt` |
| `be2f60ce5f3c` | 1012 | `vercel_project_T1.json` (pre-deployment, irreplaceable) |
| `644adbb5735d` | 996 | `vercel_project_T2.json` |
| `562b5ce08847` | 992 | `vercel_project_T3.json` |

All eleven `D_*` record files are on disk alongside them.

## Standing risk, restated now that it has changed shape

Before the migration the four unpushed branches existed in exactly one place. They now exist in **two**:
this SSD working copy and the retained Mac recovery copy. That is a genuine improvement, with two
qualifications from the handoff itself: development must not continue in both locations (§70), and there
is **no ongoing backup system configured yet** (§76). So the only *working* copy of D's evidence is on a
single external drive, and none of it is on the remote.

Pushing these branches would remove that exposure, and it remains **unauthorised** — the owner has only
ever authorised pushing `web/wording-release-ff` and `admin/label-console-release-ff`. Not done, raised.

## Method note

A first pass reported all five folders `ABSENT ON SSD`. That was a bug in D's own script, not a migration
failure: zsh does not word-split unquoted `$line`, so `set -- $line` left `$1` holding the entire
expectation string and every path malformed. Caught by listing the directories plainly before trusting
the loop. This is the **same zsh word-splitting trap already recorded** from the patch-id comparison that
printed a vacuous "IDENTICAL"; the recorded lesson did not prevent the repeat. Pattern to retire: shell
word-splitting for structured per-item data — pass values as explicit function arguments, as the
corrected run did.

## Not D's lane, noted and not acted on

The owner's message also directed B and C to coordinate simulator ownership, and F to take the updated
dashboard brief before continuing design. D has done nothing about either.

## Scope on resume

Unchanged from the pre-pause handoff. Awaiting the owner on: the five test-mode refund records, the live
Stripe read on the two real ones, and the `source` value per reconciled row. `F-CONSOLE-SETTING-STALE-1`
is queued in D's lane, untouched.

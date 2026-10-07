# D's pre-state baseline for the MM-1 preparation

Captured **2026-10-07T02:30:36Z**, before A executes. Committed first so the "afterwards" comparison is
against a recorded "before", not a remembered one. Every line below was read from the GitHub API.

## Rulesets
- Exactly **one**: `21624091 main-protection`, enforcement `active`, target `branch`, `~DEFAULT_BRANCH`.
- `main`'s rule types: `deletion`, `non_fast_forward`, `pull_request`, `required_linear_history`,
  `required_status_checks`.
- `main`'s `allowed_merge_methods`: **`rebase, squash`** (to be narrowed to `squash`).

## Repository-wide merge settings — must be unchanged afterwards
`allow_merge_commit=true` · `allow_squash_merge=true` · `allow_rebase_merge=true` · `allow_auto_merge=false`

## Branches with no rules today (0 each)
`release/production-gate-20260918` · `feature/web-accounts-foundation` · `admin/operating-console` ·
`release/candidate-20260918`

## Destination heads
| Branch | Head |
|---|---|
| `feature/web-accounts-foundation` | `1765bbebfa4f52a4aa4835d795d449458205fdc8` |
| `admin/operating-console` | `562fda9aba261d7929ee772a4fd1ce50485c4294` |
| `release/production-gate-20260918` | `037092f00cd46c0062c30b4a9dc70dd6928e998b` |
| `release/candidate-20260918` | `d218b71311b0d3968851e3fc1a55e278756d1be1` |

## Landing branches
- On the remote: **both absent** (`Branch not found`).
- Local: `web/wording-release-ff` = `fd0da772b1e9680de0e73b09ad0c045d890bc6d5` (A, converge);
  `admin/label-console-release-ff` = `efe03fca5a88b074b2a675fb24fe718b53a9f4a3` (D, labelff).

## Heads against destinations, re-verified at capture time
| Landing branch | Destination | Fast-forward | Commits | Files | Outside its directory |
|---|---|---|---|---|---|
| `fd0da772` | `feature/web-accounts-foundation @ 1765bbeb` | yes | 3 | 11 | **0** |
| `efe03fca` | `admin/operating-console @ 562fda9a` | yes | 2 | 3 | **0** |

## Known condition to carry into verification
`562fda9a` already carries **three** `Immutability + ordering` check runs, one of them `failure`. So
verification reads **every** run of each required context at a head sha, not the first one returned.

## Division
A executes the preparation. D verifies settings, remote heads and PR checks from the API, not from A's
report. Neither merges anything.

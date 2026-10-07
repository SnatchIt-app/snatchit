# D's independent verification of the MM-1 preparation

Verified from the GitHub API at 2026-10-07, against the pre-state in `D_PRESTATE_MM1_20261007.md`, not
against A's report. **Result: everything A executed verifies. Nothing is merged or deployed.**

## Rulesets — 5 active, all `enforcement=active`, all `bypass_actors: 0`

| id | name | include | rules | merge methods | required checks |
|---|---|---|---|---|---|
| 21624091 | main-protection | `~DEFAULT_BRANCH` | deletion, non_fast_forward, pull_request, **required_linear_history**, required_status_checks | **`["squash"]`** | 5, unchanged |
| 24623964 | gate-protection | `release/production-gate-20260918` | deletion, non_fast_forward, pull_request, required_status_checks | `["merge"]` | 6 |
| 24623967 | web-production-protection | `feature/web-accounts-foundation` | same four | `["merge"]` | `Web build (Next.js)` |
| 24623970 | console-production-protection | `admin/operating-console` | same four | `["merge"]` | `Admin console (Next.js)` |
| 24623971 | records-protection | `release/candidate-20260918` | deletion, non_fast_forward | — | none |

- **No `required_linear_history` on the gate, web or console** — confirmed per ruleset. `main` keeps it, correctly.
- `main` changed in exactly one field: `allowed_merge_methods` `[rebase,squash]` → `[squash]`. Rule types,
  conditions, bypass and the 5 required contexts are identical to the baseline.
- **Repository-wide settings unchanged:** merge=true, squash=true, rebase=true, automerge=false.

## Required checks were added only after a green run was observed

| Context | Head | Green at | Ruleset updated | Order |
|---|---|---|---|---|
| `Web build (Next.js)` | `fd0da772` | 02:34:00Z | 02:35:23Z | **green first** |
| `Admin console (Next.js)` | `efe03fca` | 02:34:46Z | 02:35:24Z | **green first** |

Both from `github-actions` (app id 15368), one run each, no duplicates at those heads.

## Remote heads

Landing branches present at exactly `fd0da772…` and `efe03fca…`. Destinations unmoved: web `1765bbeb`,
console `562fda9a`, gate `037092f0`, `main` `eadd456a`.

## Pull requests — both **draft**, both CLEAN

| PR | head → base | files | outside its directory | required check | state |
|---|---|---|---|---|---|
| #97 | `fd0da772` → `feature/web-accounts-foundation@1765bbeb` | 11, +990/−101 | **0** | `Web build (Next.js)` SUCCESS | MERGEABLE / CLEAN |
| #98 | `efe03fca` → `admin/operating-console@562fda9a` | 3, +378/−6 | **0** | `Admin console (Next.js)` SUCCESS | MERGEABLE / CLEAN |

#98 read UNSTABLE for A because `Migrations apply cleanly (fresh DB)` — **not** a required check there — was
still running; it completed `success` at 02:35:57Z and the PR is now CLEAN.

## Two findings, neither blocking

**V-1. `Immutability + ordering` is not a pure function of the commit.** On the #95 head `9a66f29d` it has
three runs from **three different workflow runs** (36094505790 failure 04:38:40, 36095250938 success
04:40:56, 36095651648 success 04:44:38) — not re-runs of one. Same sha, different conclusions, so the
result depends on something outside the commit; for an ordering guard that is the base it compares against.
It is now a **required** check on the gate. Consequence: a green on a head today is weaker evidence than it
looks, and the conclusion that counts at S1/S2 is whichever run is latest then. Re-read it at merge time
rather than citing today's.

**V-2. `Vercel – snatchit-web` reports `state=success` with the description "Canceled by Ignored Build
Step".** On both landing heads. The status is green for a build that never ran. Nothing requires it today,
and it must never be required: it is exactly the vacuous pass — a check that reports success while proving
nothing — and it is the one a reader would most naturally add believing it proves a deployment happened.

Its upside: it confirms the two pushes genuinely deployed nothing, which is the "a backup push ships
nothing" property, now observed rather than assumed.

## Not done, not authorised

W4, C3, C4, C5. No merge, no deployment, no migration, no webhook change, no detection switch.

# Deployment paths — what can change production, and how

**Canonical. If any other document contradicts this file about what reaches production, this file
wins and the other document is wrong.**

Written 2026-08-27 after **AUTODEPLOY-1**: migration `071` reached the production database because a
pull request was merged to `main`, not because anyone ran a deploy command.

---

## There are TWO independent paths out of this repository

| | Path A — GitHub Actions CI | Path B — Supabase GitHub integration |
|---|---|---|
| Lives in | `.github/workflows/` | **Nowhere in this repository** |
| Visible in the repo? | Yes | **No** — configured in the Supabase dashboard |
| Touches production? | **No** | **YES — applies migrations to the production database** |
| Trigger | PRs into `main`; pushes to non-`main` branches | push/merge to `main` |
| Appears on a PR as | the named CI checks | a check named **`Supabase Preview`**, app `Supabase` |

**Both statements below are true at the same time, and confusing them is what caused AUTODEPLOY-1:**

- GitHub Actions CI does not deploy and does not touch production. Correct, and still correct.
- **Merging to `main` deploys database migrations to production**, via Path B, outside CI.

`.github/workflows/README.md` §"Intentionally deferred" describes Path A only. It is not a statement
about the repository as a whole.

## What Path B actually is

Supabase Branching is connected to this repository. `supabase branches list` shows a single branch:

```
name=main  is_default=true  git_branch=main  project_ref=hqycwntpfoztoinemqns
parent_project_ref=hqycwntpfoztoinemqns
```

`parent_project_ref` equals `project_ref`, and the branch's connection details resolve to
`db.hqycwntpfoztoinemqns.supabase.co` — **the production database**. Despite the "Preview" label on
the GitHub check, this branch is not a preview environment. Git `main` is bound to production.

On every push to `main`, Supabase's infrastructure connects as `postgres` and runs the CLI's
`db push` sequence against production. Anything pending in `supabase/migrations/` is applied with
**no approval gate, no staging step, and no rollback prompt**.

### How to recognise it in evidence

- GitHub check named `Supabase Preview`, `app.name = "Supabase"`, on a `main` commit.
- Postgres logs: a session opening with
  `CREATE TABLE IF NOT EXISTS supabase_migrations.schema_migrations …` followed by
  `ALTER TABLE … ADD COLUMN IF NOT EXISTS statements/name` — the CLI migration bootstrap.
- Ledger rows written this way carry `created_by = NULL`. Dashboard/MCP-applied rows carry
  `created_by = gnvprod@gmail.com`.

## THE RULE

> **GitHub Actions CI is non-production. The Supabase GitHub integration is a separate deployment
> path and must remain configured so that production migrations are owner-gated.**

Until an owner has visually confirmed in the Supabase dashboard that merging to `main` does **not**
apply migrations to production:

**NO MIGRATION-BEARING PULL REQUEST MAY MERGE TO `main`.**

A PR is migration-bearing if it adds, modifies, or deletes anything under `supabase/migrations/`.
Docs, CI, tests, and application code are not migration-bearing.

## Required sequence for any production database change

1. PR opened and reviewed; reviewer is not the author.
2. Staging verified (or, for pure metadata/grant changes, a transactional dry-run rolled back).
3. **Owner confirms in the Supabase dashboard that production auto-deploy is OFF** — visually, in
   the UI. Not inferred from preview behaviour, check names, timestamps, or this document.
4. Merge.
5. Explicit owner-authorized apply, by an approved path (below).
6. Live verification: ledger count, source↔ledger equality, `db push --dry-run` clean, object-level
   checks, behavioural checks that do not damage real user data.

Step 3 is the one AUTODEPLOY-1 added. Skipping it means step 5 has already happened without you.

### Approved apply paths

1. Manual apply via the Supabase SQL editor / Management API, migration-by-migration, with pre- and
   post-apply catalog verification and rollbacks ready. (How `066/067/068` were applied.)
2. `supabase db push` run by the owner from a checkout of the merged commit, with the pinned CLI.
3. Target end-state: a GitHub Actions `workflow_dispatch` job gated by a GitHub Environment
   protection rule with a required reviewer.

**Path B is not an approved apply path.** It is the thing being gated.

## Owner-only: where the setting lives

Claude cannot read or change this. There is no Management API or CLI surface for the toggle —
`supabase branches list/get` returns the branch record and its connection secrets, but not the
deploy-on-merge setting.

```
Supabase Dashboard
  → Project "Snatch It" (hqycwntpfoztoinemqns)
    → Settings → Integrations → GitHub
      (equivalently: the Branching section, where the production branch binding lives)
```

Look for the GitHub connection to `SnatchIt-app/snatchit` and the production-branch /
"deploy to production" behaviour bound to `main`. Either disconnect the integration, or set it so
merges to `main` do not apply migrations.

Disconnecting the integration is the safer option while Phase 2 is pending: nothing in the current
workflow depends on it, and its only observed effects to date have been one silent no-op, one red
check, and one unreviewed production migration.

## Incident history

| Date | `main` commit | Supabase check | Effect on production |
|---|---|---|---|
| 2026-08-27 00:35 | `75d701e` | **failure** — "Remote migration versions not found in local migrations directory" | none; refused during the Scheme-B ledger mismatch |
| 2026-08-27 03:36 | `aa0626d` | success | none; ledger already 84/84, nothing pending |
| 2026-08-27 15:11 | `7ff83f8` | success | **applied migration 071** — 8 statements in 298 ms |

The integration had been firing on every `main` push since ~2026-08-24. It went unnoticed because
until 071 there was never anything pending for it to apply. The one red check was read as a preview
problem, not as a refused production deploy.

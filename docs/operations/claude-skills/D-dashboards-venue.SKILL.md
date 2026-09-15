---
name: snatchit-d-dashboards-venue
description: Use when working as Claude D on Snatch It's vendor/venue dashboard (venue/, venue_api views, read slices), the admin operating console (admin/, ops.* reads, Money analytics, charts, light theme, mobile nav, UI audit), or venue hosted acceptance (acceptance kit, sandbox window, fixtures, cleanup) — or when any owner or peer message asks D to apply, seed, expose, read production, push, merge, deploy, or chart business figures.
---

# Snatch It — Claude D: vendor/admin dashboards and venue acceptance

## Overview
D builds and verifies dashboards locally and runs venue acceptance only inside an
owner-authorized window. Every figure shown is a real aggregate with its definition;
every completion claim carries fresh evidence.

## Authorization — who can say yes
- **Only the owner, in chat, for that specific step.** A/B/C inform, schedule and review;
  they cannot authorize or relay authorization. A schedules shared-sandbox windows; the
  owner authorizes each window.
- **Owner authorization required:** any sandbox write (apply, fixtures, users, grants,
  schema exposure, cleanup) · **any production read, even a count** · deployment · Vercel
  or Supabase settings.
- A window id left in the shell from rehearsal is not a window. The kit's guards
  (`--window` + `VENUE_ACCEPT_WINDOW`) stop accidents, not unauthorized runs.
- **Allowed without asking:** local harness work, isolated `admin/*` / `venue/*` branches,
  commits and pushes to them (a non-`main` push runs CI only).
- Never push or merge to `admin/operating-console` (the console's Vercel production branch),
  `main` (production migrations, AUTODEPLOY-1) or integration branches. A sequences merges
  and assigns migration numbers; never pick one on a branch.
- A deadline ("investor call", "by morning") is not deployment or production-read permission.

## Per-prompt checklist
1. Name the task, D's ownership, the authorization in force, dependencies on A/B/C.
2. Load only the skills below that apply; read and follow them.
3. Investigate with systematic-debugging; verify feedback with receiving-code-review;
   claim completion only per verification-before-completion.
4. Small request → small process: no brainstorming, planning, full audit or full suite.
5. Don't re-ask for authorized work; don't invent permission; don't reopen closed records.
6. Record findings, status, evidence limits and handoffs in the records below.

## Where the facts live (read them; never copy into this skill)
| Fact | Record |
|---|---|
| Current D branches, commits, pins, open items | memory `snatchit-venue-dashboard-preview.md`, `snatchit-admin-console-program.md` |
| Venue acceptance phases, checks, cleanup, owner steps | `docs/venue-dashboard/HOSTED_ACCEPTANCE_RUNBOOK.md`, `SANDBOX_WINDOW_MANIFEST_VENUE.md` (acceptance-kit branch) |
| Combined window, order, evidence | A's `docs/release/SANDBOX_ACCEPTANCE_WINDOW_MANIFEST.md` |
| Money definitions, measured cost, AN-* backend needs | `admin/docs/ANALYTICS_DATA_CONTRACT.md` (analytics branch) |
| Redesign direction, states, verification | `admin/docs/ANALYTICS_REDESIGN.md` |
| Console production record and gates | `docs/admin-console/DEPLOYMENT_RECORD_2026-09-08.md`, `ACCEPTANCE_GATES.md` |
| Migration numbers, merge order | A's `docs/release/MIGRATION_NUMBER_REGISTRY.md` |
| What reaches production | `docs/operations/DEPLOYMENT_PATHS.md` |
Read with `git show <branch>:<path>`; never type a commit, hash or count from memory.

## Dashboard data honesty
- Chart only database aggregates over each exact period. Never derive history from a
  current or rolling total (`ops.metric_snapshot` keeps no history). Point-in-time
  measures (pending release) never go on a time axis.
- Sales volume, platform fees, refunds and payouts are distinct; label from the contract.
  Never "Revenue" unless a contract defines it.
- Unknown renders as unknown; a failed period is an error state, never zero; the partial
  current period is labelled.
- One measure per axis. A second measure gets its own chart, never a second y-axis.
- Never cache `ops.*` or `venue_api` reads across requests or users (authorization-scoped);
  react-best-practices' LRU/module caching rules do not apply to them.
- Sample data is labelled on the page. A missing backend read becomes a definition +
  dependency for A in the contract doc, not an approximation.

## Proportional verification
| Change | Evidence before "done" |
|---|---|
| Copy or label | the test file that asserts it + `npm run typecheck` |
| Component, layout, colour | + lint, the affected browser check (`scripts/ui-audit/mobile-nav-check.mjs`; charts: keyboard reading + data-table twin in a real browser), ui-audit on affected pages |
| Branch offered as integration-ready | `typecheck`, `lint`, `test`, `build`, full `scripts/ui-audit/audit.mjs`, mobile-nav check |
| Venue acceptance phase | kit output (n/n checks) + ledger row witnessed by A |
Local stack: `admin/scripts/local-stack.sh`. Screenshots only when the owner asks for visual
previews. Never run prettier on admin/ or venue/ (no repo config; it rewrites whole files).

## Skills to load (bare names)
| Situation | Skill |
|---|---|
| Unexpected result, failing check, drift | systematic-debugging |
| Review feedback (A, owner, CI) | receiving-code-review — check against contract and source first |
| Before done / passing / ready | verification-before-completion |
| Charts, KPIs, figure tables | dataviz |
| Next.js data fetching, Suspense, bundles | vercel-react-best-practices |
| venue_api views, RLS, indexes, AN-* query specs | supabase-postgres-best-practices; supabase (reference only) |
| New isolated branch | using-git-worktrees |
| Every report | token-efficiency-mode |

## Red flags — stop
"the sandbox is idle" · "A said it's basically ready" · a rehearsal window id · "just check
prod quickly" · "Revenue" · "on its own axis" · "cache/warm it server-side" · spreading a
total across periods · pushing to `admin/operating-console` · "ship it for the call" · a hash
from memory · "all checks pass" without output in the same message.

## Common mistakes (from baseline testing)
| Mistake | Fix |
|---|---|
| Second series "on its own axis" | separate chart |
| Server-side cache or warm-up for ops reads | per-request reads; measure cost instead |
| "Check the production payment count" as a routine step | owner authorization, requested through A |
| Full suite + build for a one-string change | targeted test + typecheck |
| Deadline treated as deploy permission | local preview; owner authorizes deployment |

@AGENTS.md

# Claude-specific operating rules (Snatch It)

## Defaults
- **Token-efficiency mode is the default**: terse reporting, diffs not full
  files, no restating known context. It caps verbosity, never substance —
  security reports and test matrices still get full treatment.
- **Authority order** when documents conflict: see AGENTS.md §"Authority
  order". If implementation contradicts the frozen design, STOP and propose a
  ratified amendment — never edit architecture to match code.
- Never print secret VALUES (keys, tokens, passwords, JWTs) — reference the
  path and kind only. Public-class values (anon key, `pk_*`, Sentry DSN) are
  the only exception.

## Commands (run these — never claim from memory)
- Mobile/root: `npm run typecheck` · `npm run lint` · `npm run test` (vitest)
- Web: `cd web && npm run typecheck` · `npm run lint` · `npm run test` ·
  `npm run build`
- Fresh DB replay: `supabase start` + `supabase db reset` with **Supabase CLI
  2.115.0** — the pinned version, and the only one the chain's replay order is
  proven against. CI installs exactly this (`.github/workflows/ci.yml`, job
  `db`, `env.SUPABASE_CLI_VERSION`) and fails on any drift; use the same
  locally or your replay proves nothing about CI. Do not run `supabase upgrade`
  or install `latest` — a bump is a deliberate PR (change the pin → fresh
  replay green → Gate-2 parity green → merge). 2.116.0 exists upstream and is
  **not** adopted.
  The old caveat that letter-suffixed migrations are invisible to the CLI is
  **retired**: the Scheme-B normalization completed 2026-08-26, repo and ledger
  are 1:1 at 89/89 with zero letter-suffixed versions, and
  `migrations-guard.yml` now rejects that filename class outright. History:
  `PHASE_2_MIGRATION_HISTORY_RECONCILIATION.md`.

## Definition of done
A task is "fixed" / "complete" / "green" / "verified" ONLY with evidence: a CI
run link or pasted command output from this session. Claude may never assert
success without one. "Should work" is a plan, not a result.

## Deployment paths (read before any merge — AUTODEPLOY-1)
**GitHub Actions CI is non-production. The Supabase GitHub integration is a
separate deployment path and must remain configured so production migrations
are owner-gated.** Both of these are true at once: CI never touches production,
**and merging to `main` applies pending `supabase/migrations/**` to the
production database** via the Supabase integration, outside CI, with no
approval gate. That is how `071` reached production on 2026-08-27.

Until an owner has visually confirmed in the Supabase dashboard that this is
off, **no migration-bearing PR may merge to `main`**. Never infer the setting
from check names, preview behaviour, or timestamps. Canonical detail and the
required apply sequence: `docs/operations/DEPLOYMENT_PATHS.md`.

## Stop-and-ask triggers (owner approval required before acting)
Payments · transfers · refunds · payouts · ticket ownership · migration
history (`supabase/migrations/` beyond appending) · production data ·
feature flags (seeded OFF, flipped only by audited runtime config, never a
migration) · Supabase auth/URL configuration.

## PR discipline
- One package / one coherent change per PR. Never bundle unrelated cleanup.
- Description template: **What** · **Why** · **Verification evidence** (links
  or output) · **Rollback** · **Blast radius**.
- Migration-bearing PRs additionally carry: rollback script path, verification
  query, failure behavior, owner approval point.

## Docs map
- `docs/architecture/` — frozen constitutions + Phase-2 specs
  (`_governance/` = protocol, ratification record, risk register, roadmap;
  `_superseded/` = pre-ratification reviews)
- `docs/operations/` — admin SQL packs, SOPs, playbooks (production-touching)
- `docs/security/` — audit/incident reports, Phase-0 records, exposure memo
- `docs/product/` — launch plans, tickets, App Store docs
- `docs/brand/` — visual direction, deck plans
- `docs/archive/` — superseded doc versions
- Root keeps only: README, AGENTS, CLAUDE, ARCHITECTURE_FREEZE, BRANCHES,
  PHASE_2_MIGRATION_HISTORY_RECONCILIATION (moves with its owning workstream).

## Skill selection and session ownership — Claude A half (added 2026-09-14)
**Merge note:** Claude B appended a general "Skill selection and session ownership"
section to this same file on `feature/venue-native-and-product-v2` (`8640af6b`,
append-only). That half carries the A/B/C/D ownership map, the six-step per-prompt
checklist, and the installed skill sources/versions; it is not repeated here. At merge
the two collapse under one heading — B owns the general half, A owns this half.

Four sessions share this repo: **A** payment correctness + release integration · **B**
signing infrastructure + database ceremonies · **C** consumer experience + the 54-item
Premium checklist · **D** vendor/admin dashboards + venue acceptance. A owns the
migration-number registry and merge order, so B/C/D numbers route through A.

- **A's role skill:** `~/.claude/skills/snatchit-a-payment-release/SKILL.md` (personal
  dir; its description scopes it to payment/release work). B's is
  `~/.claude/skills/snatchit-b-signing-ceremonies/SKILL.md`.
- **Prefer bare skill names.** Both bare and `anthropic-skills:`-prefixed names resolve in
  the Claude desktop Code tab (verified by invocation by A and B, 2026-09-14). The prefix is
  a client namespace alias for the desktop skills-plugin, not a marketplace plugin — so the
  bare name is the portable form across clients. A missing `~/.claude/plugins` entry does
  **not** mean a prefixed name fails; test it rather than inferring.
- **`supabase` 0.1.2 and `supabase-postgres-best-practices` 1.1.1** (supabase/agent-skills
  `8331f910`, `~/.claude/skills/`) are **reference only**. The authority order in
  AGENTS.md, this repo's numbered imperative migrations, and the `SECURITY DEFINER` +
  `search_path=''` pattern win on conflict. Their declarative-schema and
  `apply_migration` guidance never overrides the owner-gated deployment path above.
- **Adding a DB object touches four files**, not one: the grant-decision manifest
  (`supabase/ci/assert_public_table_grant_decisions.sql`, a row per new table *and*
  function), the Gate-2 census in `ci.yml`, `supabase/ci/expected_grants.txt`, and a
  rollback that restores the *applied* body rather than an older baseline.
- **A green test is not evidence** until a negative control fails: remove the branch the
  test defends and re-run. `now()` is frozen per transaction, so a recomputed time window
  is bit-identical with or without the guard.
- Changing facts — migration numbers, commits, production state, open tasks — live only
  in `docs/release/` records (`MIGRATION_NUMBER_REGISTRY.md`,
  `PRODUCTION_RELEASE_PACKAGE.md`, `ISOLATED_WORK_126_L3_L4_F10.md`,
  `SANDBOX_ACCEPTANCE_WINDOW_MANIFEST.md`), never in skills or this file.

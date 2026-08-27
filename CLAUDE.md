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
  2.75.0** (the pinned version the chain is proven against; the letter-suffixed
  migrations are invisible to the CLI until the normalization event lands —
  see `PHASE_2_MIGRATION_HISTORY_RECONCILIATION.md`).

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

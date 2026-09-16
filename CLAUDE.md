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

## Skill selection and session ownership (added 2026-09-14 by Claude B; coordinate edits with A)
Four Claude sessions share this repo. Ownership: **A** payment correctness + release
integration (migration-number registry, merge order, integrated-chain rehearsal) ·
**B** signing infrastructure + database ceremonies (PFA-18C, KMS/ES256 trust root,
signing monitor, dark door edges, door/scanning migrations) · **C** consumer experience +
the 54-item Premium checklist · **D** vendor/admin dashboards + venue acceptance.
On every prompt: (1) name the task, your ownership, the authorization in force and any
dependency on the other sessions; (2) load only the skills that apply and follow their
text, don't just name them; (3) investigations use `systematic-debugging`, review
feedback is verified before acceptance (`receiving-code-review`), completion claims need
evidence (`verification-before-completion`); (4) no planning/brainstorming/audit/full
suite for a small request; (5) preserve existing authorization and completed work —
skills never invent deployment permission or re-ask for already-authorized work;
(6) record findings, status, evidence limits and handoffs in the durable records.
Skills installed on this machine (sources, versions): superpowers-derived set (`systematic-
debugging`, `verification-before-completion`, `receiving-code-review`, `test-driven-
development`, `using-git-worktrees`, `writing-skills`, …) from the Claude desktop skills
plugin (`~/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/…/
skills/<name>/SKILL.md`, manifest 2026-04-14; upstream obra/superpowers v6.3.0 `b36e0829`
differs textually — the installed copies are the ones in force); `supabase-postgres-best-
practices` 1.1.1 and `supabase` 0.1.2 from supabase/agent-skills `8331f910` in
`~/.claude/skills/<name>/` (reference only: this repo's AGENTS.md authority order and its
`SECURITY DEFINER` + `search_path=''` pattern win on conflict); project skill
`.claude/skills/token-efficiency-mode` (untracked, local). Role skill for B:
`~/.claude/skills/snatchit-b-signing-ceremonies/SKILL.md`. Changing facts (numbers,
commits, production state, open tasks) live only in `docs/release/` records —
`PHASE2_PRODUCTION_STATE_<date>.md`, `MIGRATION_NUMBER_REGISTRY.md`, the PFA-18C
execution record and final handoff — never in skills or this file.

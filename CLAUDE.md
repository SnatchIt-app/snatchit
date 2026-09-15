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

## Skill selection and session ownership — Claude C half (added 2026-09-14)
**Merge note:** B's general half (ownership map, the six per-prompt rules, hosted-skill
inventory) is on `feature/venue-native-and-product-v2` (`8640af6`) and A's half on the
converge branch (`d28e277`); this half adds only what is C-specific. At merge the three
collapse under one heading, append-only. Coordinate edits with A.

- **C's role skill:** `~/.claude/skills/snatchit-consumer-experience/SKILL.md` (tracked
  copy `docs/operations/claude-skills/C-consumer-experience.SKILL.md`). Consolidated
  registry of every skill across the four sessions, with source, commit, date and real
  path: `docs/operations/CLAUDE_SKILLS_REGISTRY.md`.
- **C's records of truth:** the Premium backlog, rulings A-01…A-17, findings F1…F10 and
  the 54-item coverage — `docs/product-v2/PREMIUM_EXPERIENCE_BACKLOG.md` on
  `frontend/premium-experience-backlog` (worktree `snatchit-premium`); the next
  candidate's device checklist `docs/product-v2/DEVICE_VERIFICATION_CHECKLIST.md`; the
  closed Build 16 matrix under `docs/security/PAYMENTS_RELIABILITY_2026-09/`.
- **Gated client surface — every change goes to A before merge:** `src/lib/payments.ts`,
  `src/lib/checkout/{setupDecision,payControl,holdState}.ts`, `src/lib/auth/signOut.ts`,
  and any authoritative-state read. Prove the surface with
  `git diff --stat <batch-base>..HEAD -- <those files>`.
- **Product truths C enforces:** no success shown before authoritative confirmation
  (leading bid, reservation, payment, receipt, payout); cached data never authorises a
  transaction; returning from another app never confirms or releases anything; "Payment
  refunded" only for a confirmed refund; the device clock is not an authority on whether
  an auction closed; a server reply asserts only what it says.
- **C-installed skills** (`~/.claude/skills/`, each with `INSTALL_SOURCE.txt`; MIT;
  inspected before install): `expo-router`, `expo-animation`, `expo-data-fetching` from
  expo/skills `c180b05` (2026-09-14) and `vercel-react-native-skills` from
  vercel-labs/agent-skills `063bee9` (2026-08-28). Reused, not duplicated: B's `supabase`
  and D's `vercel-react-best-practices`. Not installed: expo `eas-simulator` (paid EAS
  cloud simulators — a preview option only the owner can authorise) and the ship/release
  skills (A's lane). Static previews are supporting evidence; native acceptance needs an
  authorised candidate build.

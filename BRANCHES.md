# Branch topology

Updated 2026-08-25 (repository-stabilization program). Previous consolidation
record: tag `consolidated/pre-cleanup-2026-08-06`.

## Authoritative

### `main` — the single source of truth
Everything: `app/` + `src/` (Expo mobile), `web/` (Next.js), `packages/`
(shared, vendored into web as tarballs), `supabase/` (migrations, rollbacks,
edge functions), and `docs/` (constitutions, specs, governance, ops, security,
product — see the docs map in `CLAUDE.md`).

PR #3 (`phase2/architecture` → `main`) was **rebase-merged** 2026-08-25: `main`
carries byte-identical rebased equivalents of the frozen Phase-2 baseline
(`cf7d6b9` → `e24989c` → `f66bf1d`), while tag **`phase2-architecture-v1`**
anchors the original freeze SHAs (`51cce52`/`dd960c4` chain) — see
`ARCHITECTURE_FREEZE.md` Amendment A-2.

Kept as one repo on purpose. Migrations and edge functions are consumed by
**both** clients; splitting web into its own repo would fracture them.

## Stale — pending deletion per the stabilization roadmap §7 (owner action)

| Branch | State | Note |
|---|---|---|
| `phase2/architecture` | merged via PR #3 | delete after tagging; `phase2-architecture-v1` preserves the SHAs |
| `phase0/lockdown` | == pre-merge `main` (PR #2 fast-forward) | delete |
| `feature/web-accounts-foundation` | ancestor of `main` (PR #1) | **repoint Vercel's Production Branch to `main` first** — the dashboard still deploys snatchti.com from this branch; never let it lead or lag `main` until repointed |
| `fix/edge-transfer-rpcs` | content-superseded (edge-file diff vs `main` empty) | delete; optional archive tag |
| `mobile/profile-rpc-compat` | content-superseded (residual = comments/wrapping only) | delete; its local unpushed `94b3be7` is superseded — do not push |

## Releases

- **Web** — push to the Vercel production branch (see table above until
  repointed to `main`). See `web/DEPLOYMENT.md`.
- **Mobile** — cut from a tag, built via EAS (`eas.json` uses
  `appVersionSource: remote`, so the real build number lives on EAS, not
  `app.json`). Tag pattern `mobile/v<version>-build<n>-<purpose>`.
  Latest: `mobile/v1.0-build9-apple-review` (the repo tag lags; App Store
  metadata records Build 13 as the current binary).

## Rules

- Never force-push `main` or the production branch.
- Migrations are append-only (`AGENTS.md` §"Phase-2 governance rules"; the
  sole authorized exception is the one-time normalization event in
  `PHASE_2_MIGRATION_HISTORY_RECONCILIATION.md`).
- `supabase/migrations-pending/` and `supabase/one-off/` sit outside every
  replay path on purpose — read their READMEs before moving anything into
  `supabase/migrations/`.

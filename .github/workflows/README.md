# CI/CD workflows — Snatch It

Phase 0 lockdown pipeline for a live-money marketplace. Every workflow is
least-privilege (read-only token by default, widened per-job only where
required) and every third-party action is pinned to a full commit SHA.

## Workflows

### `ci.yml` — build & test gate
Triggers: PRs into `main`, and pushes to any non-`main` branch.

| Job | What it does |
| --- | --- |
| `quality` | `npm ci` → `npm run typecheck` (`tsc --noEmit -p .`) → `npm run lint` (`expo lint`) → `npm run test` (`vitest run`). Node 20, npm cache keyed on root `package-lock.json`. |
| `db` | Installs the Supabase CLI and brings up the local stack, which applies **every** file in `supabase/migrations/` in version order on a fresh database. Any failing migration fails the job. Placeholders (commented) for pgTAP RLS tests and schema advisors/lint. |
| `web` | Builds the Next.js app in `web/` (`npm ci` → `npm run build`). Node **22** to satisfy `web/package.json` `engines` (`>=22 <25`). Runs only if `web/package.json` exists. |

Why the `db` job uses the Supabase CLI and not a plain `postgres:17` container:
the migrations are Supabase-flavoured — they reference the `auth`/`storage`
schemas, `auth.users`, and the `anon`/`authenticated`/`service_role` roles,
none of which exist on vanilla Postgres. The CLI local stack reproduces them.

### `security.yml` — supply-chain & code scanning
Triggers: PRs into `main`, weekly cron (Mon 06:00 UTC), and manual dispatch.

| Job | What it does |
| --- | --- |
| `codeql` | CodeQL static analysis for `javascript-typescript`. Uploads SARIF to the Security tab (`security-events: write`). |
| `dependency-review` | Fails a PR that adds a dependency with a **high+** advisory or a disallowed license. PR-only. |
| `npm-audit` | `npm audit --audit-level=high` on root **and** `web/`. **Non-blocking** (`|| true`) for now — see TODO below. |
| `secret-scan` | TruffleHog filesystem scan, `--only-verified`. Chosen over gitleaks-action because it needs no paid license on private/org repos. |

Uses `pull_request` (never `pull_request_target`) — untrusted PR code is never
run with access to repository secrets.

### `migrations-guard.yml` — append-only ledger
Triggers: PRs that touch `supabase/migrations/**`.

Enforces two invariants against the PR base:
1. **Immutability** — no existing migration may be modified, deleted, or
   renamed (a changed line in an applied migration fails the check).
2. **Monotonic + unique ordering** — new migrations must sort after the latest
   existing migration *of the same naming scheme*, and version prefixes must be
   unique. The repo mixes two schemes (zero-padded `NNN_` and 14-digit
   timestamp `YYYYMMDDHHMMSS_`); the check is scheme-aware so a new `068_`
   compares against the max `NNN_` and a new timestamp against the max
   timestamp.

## Repo-owner setup required

**Branch protection (`main`):** require these status checks before merge —
`Typecheck / Lint / Unit tests`, `Migrations apply cleanly (fresh DB)`,
`Web build (Next.js)`, `CodeQL (javascript-typescript)`, `Dependency review`,
and (once wired) `Immutability + ordering` from the migrations guard. Require
branches up to date, and require PR review.

**CodeQL:** enable Code Scanning for the repo (Settings → Code security →
Code scanning). No default-setup config is needed since this workflow provides
CodeQL explicitly; if GitHub "default setup" is enabled, disable it to avoid a
duplicate analysis conflict.

**Secrets:** none are required by these workflows today — there are no deploy
steps. All `${{ secrets.* }}` usage is intentionally absent. When staging/prod
deploy jobs are added later they will need (at minimum): `SUPABASE_ACCESS_TOKEN`,
`SUPABASE_DB_PASSWORD`, the target `SUPABASE_PROJECT_REF`, and Stripe/Vercel
credentials — to be added by the owner in repo/environment secrets and gated on
protected environments, not on arbitrary branches.

**Permissions:** default workflow token is read-only; the only elevated scopes
are `security-events: write` (CodeQL) and `pull-requests: write`
(dependency-review PR comment). Confirm "Read and write permissions" is NOT the
org default — these workflows do not rely on it.

## Pinned third-party actions

| Action | Version | Commit SHA |
| --- | --- | --- |
| `actions/checkout` | v5.0.0 | `08c6903cd8c0fde910a37f88322edcfb5dd907a8` |
| `actions/setup-node` | v4.4.0 | `49933ea5288caeca8642d1e84afbd3f7d6820020` |
| `actions/dependency-review-action` | v4.7.1 | `da24556b548a50705dd671f47852072ea4c105d9` |
| `github/codeql-action` (init+analyze) | v3.29.0 | `ce28f5bb42b7a9f2c824e633a3f6ee835bab6858` |
| `supabase/setup-cli` | v3.0.0 | `46f7f98c7f948ad727d22c1e67fab04c223a0520` |
| `trufflesecurity/trufflehog` | v3.97.0 | `bcfcf73aaf4759d4dadc2783177c245a02792318` |

All SHAs resolved from the upstream tags via the GitHub API. Bump with a tool
like Dependabot or `pinact`; keep the trailing `# vX.Y.Z` comment in sync.

## Intentionally deferred

- **Production & staging deploys.** Not included. Prod deploys must never run
  from arbitrary branches — add them later on protected GitHub Environments
  with required reviewers, triggered by tags/releases, not by CI here.
- **pgTAP RLS tests.** Placeholder in the `db` job; wire `supabase test db`
  once `supabase/tests/*.sql` exist. Critical for an RLS-enforced money app.
- **Schema advisors / `supabase db lint`.** Placeholder in the `db` job.
- **`npm audit` blocking.** Currently advisory (`|| true`); tighten to blocking
  once the existing advisory backlog is triaged.
- **Expo/EAS build & OTA.** Mobile binary builds and store submission are out
  of scope for Phase 0.

## Known assumptions / caveats for the owner

- **Supabase CLI + migration filenames.** The `db` job pins `supabase/setup-cli`
  to v3.0.0 but installs the `latest` CLI at runtime (`version: latest`). If a
  future CLI rejects the legacy `NNN_` (non-timestamp) filenames, pin `version:`
  to a known-good CLI release, or rename going forward. Verify this job passes
  on its first real run.
- **`supabase/config.toml` is not committed.** The `db` job runs `supabase init`
  to generate it in-runner. If you later commit a `config.toml`, confirm
  `[db].major_version = 17` to match production Postgres 17.
- **Node split is intentional:** mobile (root) on Node 20, `web/` on Node 22
  (its `engines` require it). Keep the two `cache-dependency-path`s distinct.
- **TruffleHog `--only-verified`** minimises false positives but can miss
  unverifiable secrets; broaden `extra_args` if you want a stricter gate.

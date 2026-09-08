# CI/CD workflows — Snatch It

Phase 0 lockdown pipeline for a live-money marketplace. Every workflow is
least-privilege (read-only token by default, widened per-job only where
required) and every third-party action is pinned to a full commit SHA.

## Workflows

### `ci.yml` — build & test gate
Triggers: PRs into `main`, and pushes to any non-`main` branch.

| Job | What it does |
| --- | --- |
| `quality` | **OFFLINE-VERIFY-v1 spec byte-identity gate** (docs-only, see below) → `npm ci` → `npm run typecheck` (`tsc --noEmit -p .`) → `npm run lint` (`expo lint`) → `npm run test` (`vitest run`). Node 20, npm cache keyed on root `package-lock.json`. |
| `db` | Installs the Supabase CLI and brings up the local stack, which applies **every** file in `supabase/migrations/` in version order on a fresh database. Any failing migration fails the job. Placeholders (commented) for pgTAP RLS tests and schema advisors/lint. |
| `web` | Builds the Next.js app in `web/` (`npm ci` → `npm run build`). Node **22** to satisfy `web/package.json` `engines` (`>=22 <25`). Runs only if `web/package.json` exists. |

#### The `OFFLINE-VERIFY-v1` gate (first step of `quality`)

`docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md` §5.4.3 states the **offline
door admission predicate** once, tagged `OFFLINE-VERIFY-v1`, and permits
sanctioned mirrors elsewhere under `docs/architecture/**` on condition that they
are reproduced byte-for-byte. Clause 3 of that rule promises "a docs job … fails
the build unless every one is byte-identical". **This step is that job.** Until
it existed the property held by inspection rather than by construction.

Why the predicate is worth a gate: ratification record **C53**. Four documents
each held an editable copy of the offline door check; one was corrected and the
others were not, and the copy that stayed wrong was the one a scanner SDK
implements. It carried **two** conjuncts at 3b where **five** are required, which
made the OFFLINE door strictly *more permissive* than the ONLINE one — it
admitted `paid_pending_transfer` and `refund_hold` atoms the online door refuses.

**It asserts more than byte-identity, because byte-identity alone fails open in
three separate ways.** The step scans every markdown file under
`docs/architecture/`, extracts each fenced block whose first body line carries the
tag, and enforces seven guards:

| # | Guard | What it catches |
| --- | --- | --- |
| 1 | **No unterminated code fence** under the scan root | One unclosed fence makes every block after it invisible to the scan. |
| 2 | **No tag at column 1 outside a fence** | An unfenced copy is an ungated copy — exactly the fourth editable copy C53 was raised about. |
| 3 | **Block-count floor** (`OFFLINE_VERIFY_MIN_BLOCKS`, currently **4**) | *Non-vacuity.* A scan over zero blocks passes silently, forever. This repo has already shipped that failure shape: a bare `UPDATE` reported success against zero rows and every audit that read the migration source concluded the limits were in place. They were not. A floor, not a comparison against whatever happens to be there. The 4 is counted, not assumed — edge §5.4.3 (normative) + door §9.2 + Wallet §2.3 + Wallet §11.9; the Wallet spec carries **two**, which is why "three mirrors" and "three documents" are different numbers. |
| 4 | **The normative home still contributes a block** (`OFFLINE_VERIFY_NORMATIVE_FILE` = the edge spec) | Delete §5.4.3's own block and the surviving mirrors would happily agree with each other — and with nothing authoritative. |
| 5 | **Byte-identity** — exactly **one** distinct body SHA-256 across all blocks (and guard 4 guarantees the normative one is among them, so that single hash *is* §5.4.3's) | The property §5.4.3 clause 3 actually promises. On failure the step prints each divergent body's `diff -u` against the normative block. A mirror that differs is a defect in that mirror, never a change to the predicate. |
| 6 | **Minimum body size** (`OFFLINE_VERIFY_MIN_BODY_BYTES`, currently **1900**; the canonical body is 2017 bytes / 34 lines) | *Anti-emptying.* Four blocks truncated or emptied **together** are byte-identical and still four in number. Deliberately well under the real length so it catches a wholesale gutting rather than acting as a second copy of the length. |
| 7 | **Clause anchors** — a fixed list of load-bearing substrings must all be present in the canonical body | *Anti-coordinated-weakening, and the guard that would have caught C53 itself.* Byte-identity says the four copies agree; it says nothing about **what** they agree on. Four copies that all drop conjunct 3b.v are byte-identical, four in number, and full length — and the offline door is once again more permissive than the online one. The anchors assert the predicate's **strength**, not merely its uniformity: the five 3b conjuncts individually (`i` atom ∈ M2 … `v` `resale_state == 'none'`), the applied-set rule, the 3c key binding, and the `MUST NOT admit` clause. The anchor list is itself length-checked, so a truncated heredoc cannot make guard 7 vacuous. |

**Why it lives in `quality` and not in a new workflow.** The check name
`Typecheck / Lint / Unit tests` is already a required status check in branch
protection (see below). A gate added as a step inside it blocks merge **today**,
with no branch-protection change and no rename. A new workflow file would have
produced a brand-new check that nobody requires — advisory, ignorable, and
exactly the "control described as structural that is actually prose" shape the
C53 correction was raised against. It also runs **before `npm ci`**, so a broken
lockfile cannot take the gate offline.

**Ratchets — one-way.** Raise `OFFLINE_VERIFY_MIN_BLOCKS` when a sanctioned
mirror is added. **Never lower it to make a red build pass.** Removing a mirror
is a reviewed decision that lowers it deliberately, in the same commit that
removes the mirror and amends §5.4.3's list of sanctioned mirrors. Editing the
anchor list is a reviewed change to the ratified predicate, made in §5.4.3 first.
The step also writes a metrics table (blocks found, distinct bodies, body bytes,
canonical SHA-256) to the job summary.

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
Triggers: **every** pull request.

It used to trigger only on `paths: supabase/migrations/**`. That made the check
*absent* rather than *passing* on unrelated PRs, so it could never be a required
status check without deadlocking every PR that touches no migration. Change
detection now happens inside the job: if nothing under `supabase/migrations/**`
changed it logs `nothing to guard` and exits 0. The check is therefore always
present and always conclusive — safe to mark required.

Enforces, against the PR base:
1. **Base resolvable and correct** — when HEAD is a two-parent merge (the normal
   `pull_request` checkout of `refs/pull/N/merge`) the base is `HEAD^1`, the
   merge's base parent. It is deliberately *not*
   `github.event.pull_request.base.sha`, which is pinned at PR creation and goes
   stale as `main` advances; diffing against the stale value reports every
   migration merged upstream since as though this PR deleted it. When HEAD is
   **not** a two-parent merge the job falls back to the event base
   (`pull_request.base.sha`, or `merge_group.base_sha` for queued PRs) — that
   path still carries the staleness risk, and exists so the job stays conclusive
   rather than silently skipping. An unresolvable base, a base that is not an
   ancestor of HEAD, or a derived base that *contains the PR head* (merge parents
   swapped — the diff would compare the branch against itself) all fail the job.
2. **Immutability** — no existing migration may be modified, deleted, renamed,
   or have its object **type** changed. Rename detection is disabled, so a
   rename is reported as delete + add and caught by the deletion check. The
   modification check uses `--diff-filter=MT`: the `T` matters, because
   replacing a `.sql` file with a **symlink** is invisible to a plain `M` filter
   and would let SQL be sourced from outside the guarded directory while the
   guard reported "no existing migration was modified". A **newly added**
   migration must also be a regular file: an added symlink reviews as a one-line
   "add migration" diff, but its SQL lives outside the directory, so a later PR
   editing only the target would change an *applied* migration while change
   detection reported "nothing to guard".
3. **Well-formed names** — a new migration must match exactly `NNN_name.sql`
   (three digits) or `YYYYMMDDHHMMSS_name.sql` (fourteen), with the name in
   `[A-Za-z0-9_]`. This rejects letter-suffixed versions (`071a_`, which the
   Supabase CLI cannot parse), non-padded ones (`71_`, which would become the
   lexicographic maximum and permanently block every later `NNN_`), four-digit
   additions like `0999_` (same wedge), stray non-`.sql` files, and any name
   that git would C-quote or that would misbehave under shell word-splitting.
4. **Unique + prefix-free versions** — no two migrations may share a version,
   and no version may be a *prefix of* another (`070` vs `0700`). Prefix
   relationships make replay order depend on tool internals — CLI 2.75.0 (Go)
   sorted by raw filename, 2.115.0 (TS) re-sorts by parsed version, and the two
   disagree. Removing them is the entire point of the Scheme-B normalization.
5. **Monotonic ordering** — new migrations must sort after the latest existing
   migration *of the same naming scheme*. The repo mixes two schemes
   (zero-padded `NNN_` and 14-digit timestamp `YYYYMMDDHHMMSS_`); the check is
   scheme-aware so a new `076_` compares against the max `NNN_` (`075`) and a
   new timestamp against the max timestamp.

**Historical note.** Between the Scheme-B normalization PR and the production
ledger repair (completed 2026-08-26), this workflow carried a one-time
`ALLOWED_RENAMES` allowlist permitting exactly 16 content-identical renames.
**That exception has been removed.** Historical renames are forbidden again with
no standing exception; a future normalization requires its own reviewed,
time-boxed change rather than a reinstated allowlist.

## Repo-owner setup required

**Branch protection (`main`):** require these status checks before merge —
`Typecheck / Lint / Unit tests`, `Migrations apply cleanly (fresh DB)`,
`Web build (Next.js)`, `CodeQL (javascript-typescript)`, `Dependency review`,
and `Immutability + ordering` from the migrations guard. Require branches up to
date, and require PR review.

**These check names are load-bearing — do not rename a job without updating
branch protection in the same change.** `Typecheck / Lint / Unit tests` in
particular now also carries the `OFFLINE-VERIFY-v1` gate; renaming that job
would silently drop both it and the unit tests from the required set.

`Immutability + ordering` is now safe to require: since it runs on every PR and
exits 0 when no migration changed, it always reports a conclusive status. (Under
the old `paths:` filter it would simply not report on unrelated PRs, which
branch protection treats as *pending* — every such PR would have blocked
forever.)

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

- **Production & staging deploys.** Not included **in these workflows**. Prod
  deploys must never run from arbitrary branches — add them later on protected
  GitHub Environments with required reviewers, triggered by tags/releases, not
  by CI here.

  > **This section describes GitHub Actions only, and says nothing about the
  > repository as a whole.** A second, independent deployment path exists: the
  > **Supabase GitHub integration**, configured in the Supabase dashboard and
  > invisible here, **applies pending database migrations to production on every
  > merge to `main`**. It surfaces as a check named `Supabase Preview` (app
  > `Supabase`) — the "Preview" label is misleading; it targets production.
  > Migration `071` reached production this way on 2026-08-27 (AUTODEPLOY-1).
  > Canonical: `docs/operations/DEPLOYMENT_PATHS.md`.
- **pgTAP RLS tests.** Placeholder in the `db` job; wire `supabase test db`
  once `supabase/tests/*.sql` exist. Critical for an RLS-enforced money app.
- **Schema advisors / `supabase db lint`.** Placeholder in the `db` job.
- **`npm audit` blocking.** Currently advisory (`|| true`); tighten to blocking
  once the existing advisory backlog is triaged.
- **Expo/EAS build & OTA.** Mobile binary builds and store submission are out
  of scope for Phase 0.

## Known assumptions / caveats for the owner

- **Supabase CLI is pinned twice over — action *and* binary.** The `db` job
  pins the action `supabase/setup-cli` to v3.0.0 by SHA **and** pins the CLI
  binary it installs to an exact version. Both matter: the SHA stops the
  installer from changing, the `version:` input stops the *installed tool* from
  floating. It used to pass `version: latest`; that caveat is resolved.
  - The expected version lives in **one** place — the job-level
    `env.SUPABASE_CLI_VERSION` in `ci.yml` (currently **2.115.0**). The
    installer input and the assertion both read it; never repeat the literal.
  - A step named **"Assert pinned Supabase CLI (toolchain drift gate)"** runs
    immediately after install and before anything migration-sensitive. It
    prints the resolved binary path and version and fails the job on an exact
    mismatch. This catches a bad input, an action behaviour change, and a
    preinstalled/cached `supabase` earlier on `PATH`. `supabase --version`
    prints the bare version on stdout; the "new version available" notice goes
    to stderr and is discarded.
  - **Why 2.115.0:** it is the version the normalized (Scheme B) chain's replay
    order was verified against, and the client the production ledger repair was
    executed with (2026-08-26). **2.116.0 exists upstream and is deliberately
    not adopted.** Bumping the pin is its own PR: change the env value → fresh
    replay green → Gate-2 parity green → merge. Local development must use the
    same version, per `CLAUDE.md` §Commands.
  - **Only the `db` job installs a CLI.** `migrations-guard` and `security`
    intentionally do not: the guard is pure git/filename analysis over
    `supabase/migrations/**` (shell + `git diff`, no database and no tool whose
    version could change the verdict), and `security` runs CodeQL /
    dependency-review / TruffleHog. Neither is migration-*replay*-sensitive, so
    there is nothing to pin. The `2.75.0` / `2.115.0` versions named in
    `migrations-guard.yml` comments and in §4 above are **historical**, part of
    the explanation of why prefix-related version pairs are banned — not a
    statement about what any job installs.
- **`supabase/config.toml` is not committed.** The `db` job runs `supabase init`
  to generate it in-runner. If you later commit a `config.toml`, confirm
  `[db].major_version = 17` to match production Postgres 17.
- **Node split is intentional:** mobile (root) on Node 20, `web/` on Node 22
  (its `engines` require it). Keep the two `cache-dependency-path`s distinct.
- **TruffleHog `--only-verified`** minimises false positives but can miss
  unverifiable secrets; broaden `extra_args` if you want a stricter gate.

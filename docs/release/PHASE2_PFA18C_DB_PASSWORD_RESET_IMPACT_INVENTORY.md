# PFA-18C — PRODUCTION DATABASE PASSWORD RESET — READ-ONLY IMPACT INVENTORY (NOT A RESET · C3 PAUSED)

**Date:** 2026-09-10 · **Coordinator:** Claude B · **Project:** `hqycwntpfoztoinemqns` ("Snatch It", us-west-2, PG 17.6, ACTIVE_HEALTHY).
**Purpose:** the owner cannot locate the production database password (only the Supabase **Dashboard** login exists); the C3 bootstrap needs a working `psql` connection. This is a read-only inventory of what a Dashboard **Database → Settings** password reset would and would not affect. **Nothing was reset. No connection setting was changed. C3 is paused.** This document is not an authorization to reset.

Evidence: CLAUDE-OBSERVED (local repo/CLI reads, read-only MCP, AWS reads) and OFFICIAL-DOC (Supabase docs).

---

## 1. What the "database password" is (scope of the reset)

The Dashboard **Database → Settings → Reset database password** rotates the credential for the user-facing **`postgres`** role — the one used by direct connections, the connection pooler, `psql "$PROD_DB_URL"`, and the auto-populated `SUPABASE_DB_URL`. It does **not** rotate the separately platform-managed credentials of the internal roles (`authenticator` for PostgREST, `supabase_auth_admin`, `supabase_storage_admin`, `supabase_admin`, `supabase_replication_admin`, etc. — all present, CLAUDE-OBSERVED). OFFICIAL-DOC: "You can reset your database password from the Database > Settings section of the Dashboard."

## 2. Every documented consumer of the DB password (CLAUDE-OBSERVED)

| Consumer | Uses the `postgres` DB password? | Effect of a reset | Post-reset action |
|---|---|---|---|
| **Owner `psql "$PROD_DB_URL"`** (the C3 bootstrap; runbook §A "postgres role, owner's shell only") | **Yes** — this is the whole point | old password stops working; the new one is needed | set `PROD_DB_URL` with the new password (§4) |
| Local shell / dotfiles (`~/.zshrc`, `~/.zprofile`, `~/.pgpass`, `~/.pg_service.conf`) | **No** — none store it (searched; none found) | none | none |
| `supabase/.temp/pooler-url` (both worktrees) | **No** — passwordless session-pooler URL | none | none |
| **CLI migrations** `supabase db push --linked` (C4 precedent) | **No** — authenticates via the CLI **login role** / access token (`Initialising login role…`) | none | none |
| **CI** `.github/workflows/migrations-guard.yml` | **No** — dry-run/guard only; the real apply is the Supabase **GitHub integration** (project link/OAuth), not a GH secret; `gh secret list` shows no DB secret | none | none |
| **Read-only MCP connector** (this session) | **No** — Supabase access token (Management API) | none | none |
| **Mac 2 Supabase Dashboard** (Option A read-backs) | **No** — Dashboard account login + its MFA | none | none |
| **Rehearsal scripts** `scripts/rehearsal_reset.sh` / `rehearsal_test.sh` | **No** — target a **local** Postgres (`REHEARSAL_PGHOST:-127.0.0.1`, `PGPASSWORD` for localhost), never production | none | none |
| **Monitoring** `postgres_exporter` (metrics) | **No** — connects as `supabase_admin` (platform-managed) | none | none |
| **In-DB cron** (`pg_cron`, 24 jobs incl. `monitor-signing-key-invariants`, payout/refund/sweep ticks) | **No** — runs inside the database; `pg_net` calls edges with the service-role JWT | none | none |

## 3. Deployed Edge Functions — connection model (CLAUDE-OBSERVED)

11 functions are **ACTIVE** (`create-payment-intent`, `confirm-payment`, `send-push`, `stripe-webhook`, `auto-finalize-auctions`, `create-connect-account`, `confirm-and-release`, `enforce-transfer-expiry`, `delete-account`, `notify-report`, `notify-transfer`). The native door/credential edges are **not deployed** (darkness intact). **No edge-function source in either worktree references `SUPABASE_DB_URL`, `DATABASE_URL`, `postgres://`, `npm:pg`, `new Pool(`, or `new Client(`** — every function uses `supabase-js createClient` over PostgREST with the **service-role key** (a JWT), which is unaffected by a DB password reset. The default secret `SUPABASE_DB_URL` exists (platform auto-populated) but is used by **zero** deployed functions. **Conclusion: a reset does not affect any deployed Edge Function.** (Validation item V5 re-confirms this.)

## 4. What the reset will NOT alter (confirmed)

| Asset | Why unaffected |
|---|---|
| **Schema** | a password reset is a role-credential change; no DDL. Ledger 135, tip 120, 32 kernel tables — unchanged |
| **Data** (incl. `kernel.signing_key` = 0, `kernel.tickets` = 0) | no DML; the reset touches only the role password |
| **KMS** | AWS, a different account (`652872010073`); no Supabase linkage. Key `45907419…` untouched |
| **Stripe** | edge secrets (`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, Connect URLs) are independent of the DB password |
| **Feature flags** | `catalog.platform_config` rows (`native_issuance_enabled` etc.) are data — unchanged, still false |
| **Supabase Auth users** | 18 `auth.users` rows are data owned by `supabase_auth_admin` (its own credential); the user-facing password reset does not touch them, RLS, or sessions |
| **PostgREST / Realtime / Storage / Auth availability** | those connect via platform-managed internal roles, not the `postgres` password — they keep serving during and after the reset |

**Residual/known caveat:** any *future* edge function that reads `SUPABASE_DB_URL` would need a redeploy so the platform re-injects the refreshed value; none exists today, so nothing to redeploy now (tracked as V5).

## 5. Post-reset update list and validation

**Update (exactly one place):** set `PROD_DB_URL` in the owner's Mac 1 shell to the session-pooler URL with the **new** password (never printed/committed) — the §4 step-0a′ silent-entry flow from the C3 package. Nothing else needs updating.

**Validation checks (read-only):**

| # | Check | Expected |
|---|---|---|
| V1 | connection validator (C3 §2 snippet) | `project_match=True mode=session PASS` |
| V2 | `psql -X "$PROD_DB_URL" -tAc "select 1"` | `1` (auth succeeds with the new password) |
| V3 | C3 step-0 precondition read | `0\|135\|tg_signing_key_immutable=O,tg_signing_key_insert_guard=O,tg_signing_key_updated_at=O\|0\|false` |
| V4 | read-only MCP baseline (coordinator) | signing_key 0, ledger 135, flags false — unchanged from 18:11:56Z |
| V5 | `list_edge_functions` + deployed-source grep for `SUPABASE_DB_URL` | 11 ACTIVE, unchanged; 0 use `SUPABASE_DB_URL` (no redeploy needed) |
| V6 | app smoke (PostgREST path): a normal authenticated read via the app/API | succeeds (proves PostgREST/`authenticator` unaffected) |
| V7 | `auth.users` count; a test sign-in | 18; sign-in works (Auth unaffected) |
| V8 | AWS `kms describe-key` D4; flags | Enabled/v2 unchanged; flags false (reset touched nothing outside Postgres) |

Any V-check failing other than V2/V1 (which prove the new password works) is unexpected — stop and report before C3.

## 6. Short reset plan (owner executes; coordinator reads back; C3 stays paused until this completes)

1. **Snapshot (coordinator, read-only):** record the §4 baseline (done: signing_key 0, ledger 135, flags false, 11 edges, key v2).
2. **Reset (owner, Dashboard):** Database → Settings → Reset database password; save the new password directly into the owner's password manager (a new item named for the project). Never typed into chat.
3. **Update (owner):** set `PROD_DB_URL` with the new password via the silent-entry flow (C3 §step-0a′).
4. **Validate (owner + coordinator):** V1–V8. 
5. **Resume C3** only after V1–V3 pass: re-run the C3 preflight (already green except the connection) and proceed with the guarded bootstrap under the existing authorization. The reset does **not** re-authorize C3 or change its scope.

## 7. What this does NOT authorize
Resetting the password does not authorize C3, C5, C6, secrets, deploy, issuance/scanning, or any AWS change. It is solely to restore the owner's `psql` access.

## 8. Exact owner authorization phrase required before any reset
**`AUTHORIZE PFA-18C DB PASSWORD RESET`** — scoped to a single Dashboard reset of project `hqycwntpfoztoinemqns`'s database password, updating only `PROD_DB_URL` in the owner's shell, followed by V1–V8. (The reset is an owner Dashboard action; the coordinator runs only the read-only validations. Prohibited-action note: the coordinator never sets or enters the password.)

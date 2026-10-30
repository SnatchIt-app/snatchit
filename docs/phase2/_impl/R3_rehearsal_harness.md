# R3 — Local PostgreSQL migration-rehearsal harness

**Repo** `/Users/josetascon/snatchit-consol` · branch `feature/venue-native-and-product-v2`
**Date** 2026-09-02 · **Server** Homebrew PostgreSQL 17.11 (`/opt/homebrew/opt/postgresql@17`), pgTAP 1.3.5
**Status** **The full 107-file chain applies cleanly on vanilla local PostgreSQL, and the
pgTAP suite runs: 34 files, 2921 assertions planned, 2921 run, 2917 pass, 4 fail — all four documented.**

Nothing in this work touched the remote Supabase project. No `supabase` CLI command was run.
No file under `supabase/migrations/` was modified. Nothing was committed.

---

## 1. Exact commands

```sh
# once per machine — the server
brew services start postgresql@17          # this is what was used (pg_ctl not needed)
export PATH=/opt/homebrew/opt/postgresql@17/bin:$PATH

# fresh DB + full chain (idempotent; ~5.5 s)
cd /Users/josetascon/snatchit-consol
./scripts/rehearsal_reset.sh               # default DB: snatchit_rehearsal

# pgTAP suite (~5.5 s)
./scripts/rehearsal_test.sh                # same default DB

# a single test file
./scripts/rehearsal_test.sh snatchit_rehearsal supabase/tests/132_replay_parity.sql

# partial replay (stop after a given migration) — see §7
REHEARSAL_UPTO=092_notify_reduced.sql ./scripts/rehearsal_reset.sh snatchit_rehearsal_pre093
```

Env knobs: `REHEARSAL_PGHOST` (default `127.0.0.1`), `REHEARSAL_PGPORT` (`5432`),
`REHEARSAL_PGUSER` (`postgres`), `REHEARSAL_UPTO`, `REHEARSAL_ERR`.

Files added (the only repo additions):

| Path | Role |
|---|---|
| `scripts/rehearsal_bootstrap.sql` | Supabase-shaped bootstrap; carries the full fidelity ledger in its header |
| `scripts/rehearsal_reset.sh` | drop + recreate + replay chain, stop at first error |
| `scripts/rehearsal_test.sh` | pgTAP runner + known-delta classifier |
| `docs/phase2/_impl/R3_rehearsal_harness.md` | this report |

Pre-existing and **reused, not duplicated**: `scripts/local/replay_shim.sql` (the validated
492-line scaffolding dump) and `scripts/local/runtests.sh` (the TAP parser).
`scripts/local/replay.sh` is the earlier, guard-less version of the same idea; the new
scripts supersede it and neither modifies it.

### Safety properties of the two scripts

* Both `unset` `SUPABASE_DB_URL`, `SUPABASE_DB_PASSWORD`, `SUPABASE_ACCESS_TOKEN`,
  `SUPABASE_PROJECT_ID/REF`, `SUPABASE_URL`, `DATABASE_URL`, `POSTGRES_URL*`,
  `PGSERVICE`, `PGSERVICEFILE`, `PGPASSFILE`, `PGPASSWORD`, `PGSSLMODE`, `PGDATABASE`
  **before the first `psql` invocation**. A remote connection string cannot steer them.
* `PGHOST` must be `127.0.0.1`, `::1`, `localhost`, or a Unix socket path.
* Server-side proof after connecting: `host(inet_server_addr())` must be loopback (or a
  socket), `pg_is_in_recovery()` must be false, and the cluster must have **zero**
  `supabase_admin` / `supabase_replication_admin` roles — a real Supabase server is refused
  outright.
* The database name must contain `rehears`, must be `[a-z0-9_]` only, and can never be
  `postgres` / `template0` / `template1`.

Verified refusals (all abort before any write):

```
$ ./scripts/rehearsal_reset.sh production_db
[rehearsal] ABORT: database name 'production_db' must contain 'rehears' — this script DROPs it.
$ REHEARSAL_PGHOST=db.abc.supabase.co ./scripts/rehearsal_reset.sh snatchit_rehearsal
[rehearsal] ABORT: PGHOST='db.abc.supabase.co' is not loopback. …
$ ./scripts/rehearsal_reset.sh postgres
[rehearsal] ABORT: refusing to drop the 'postgres' database.
```
A decoy `SUPABASE_DB_URL=postgresql://postgres:BAD@db.example.supabase.co:5432/postgres`
was exported for every verification run in this session and was ignored.

---

## 2. The canonical order

CI (`.github/workflows/ci.yml`, job `db`, "Migrations apply cleanly (fresh DB)", ~line 448)
does **not** order the files itself. It runs

```yaml
supabase start -x studio,inbucket,imgproxy,edge-runtime,logflare,vector
```

with the Supabase CLI **pinned to 2.115.0** (a hard drift gate fails the job if the resolved
binary differs), and lets the CLI apply everything in `supabase/migrations/`. The CLI
enumerates that directory with a read that returns entries **sorted by filename, byte-wise**,
and applies them in that sequence. So:

> **Canonical order = `ls supabase/migrations/*.sql | LC_ALL=C sort` on the basenames.**
> Byte-wise on the whole filename — *not* a numeric sort of the version prefix.

That is the entire point of the normalized "Scheme B" sub-numbering. Byte-wise:

```
022_seller_fee_column.sql
0230_user_reports_and_blocks.sql      <-- 022 < 0230 < 0231 < 024 because '3' < '4'
0231_set_updated_at_helper.sql
024_disputes.sql
…
054_fix_notify_outbid_aborts_bids.sql
0550_transfer_state_guard.sql         <-- the 055x/056x/059x/060x families slot in
0551_… 0552_… 0553_… 0561_… 0562_… 0563_… 0564_…       between 054 and 057
057_notifications_dedupe_and_enqueue_helper.sql
058_notification_producers.sql
0590_… 0591_… 0600_… 0601_…
061_… → 092_notify_reduced.sql
20260714190445_investor_leads_website_form.sql          <-- the 5 timestamped files
20260730212326_ambassador_applications_website_form.sql     sort LAST, after 092,
20260730212406_ambassador_applications_fix_search_path.sql  because '0' < '2'
20260731224653_venue_partnership_inquiries_website_form.sql
20260902003623_admin_relist_listing_rpc.sql
```

107 files total, zero duplicate version prefixes (CI asserts both).

**This was verified empirically, not assumed.** A counter-experiment replaying the same 107
files in *numeric-prefix* order (which would put `024` before `0230`) fails hard:

```
NUMERIC-ORDER FAILED AT: 033_marketplace_expansion.sql
  ERROR:  relation "public.reports" does not exist        (public.reports is created by 0230)
32 of 107 applied
```

Byte-wise order applies all 107 and reproduces CI's certified Gate-2 baseline exactly
(§4). Numeric order dies a third of the way in. The ordering claim is therefore load-bearing
and settled.

---

## 3. Shim inventory and fidelity risk

Everything below is scaffolding that Supabase's platform provides *before migration 000
runs* and that a vanilla cluster does not have. The authoritative, commented ledger lives in
the header of `scripts/rehearsal_bootstrap.sql`; this is the summary.

### 3a. Inherited from `scripts/local/replay_shim.sql` (pre-existing, catalog-diff validated)

| Object | Shim form | Fidelity risk |
|---|---|---|
| roles `anon`, `authenticated`, `service_role` | `NOLOGIN`; `service_role` has `BYPASSRLS` | **Low.** Matches Supabase for grant/RLS purposes. |
| publication `supabase_realtime` | created empty | **Low.** Migrations add tables to it; `wal_level` is not `logical` locally, so a WARNING is emitted and no replication happens. Nothing tests delivery. |
| schemas `auth`, `storage`, `cron`, `net`, `vault`, `extensions` | bare `CREATE SCHEMA` | Low. |
| `auth.uid()`, `auth.role()`, `auth.jwt()` | read `request.jwt.claims` / `request.jwt.claim.*` GUCs | **Low.** Same mechanism PostgREST uses; the pgTAP personas drive them identically. |
| `auth.users`, `auth.audit_log_entries` | column subsets, no GoTrue triggers | **Medium.** Columns the chain touches are present; GoTrue-side behaviour (email confirmation, identities, MFA) does not exist. Anything asserting on GoTrue internals would be vacuous here. |
| `storage.buckets`, `storage.objects`, `storage.foldername()` | column subsets | **Medium.** RLS policies on `storage.objects` replay and are testable; the Storage API's own ownership bookkeeping, `storage.search()`, multipart tables etc. do not exist. |
| `vault.decrypted_secrets` | **empty plain TABLE** (production: a decrypting VIEW) | **HIGH — read this.** Every secret read returns NULL locally, so every secret-gated code path (e.g. the 087 CRM-export `net.http_post`) is inert *by construction*. A rehearsal can never exercise the secret-present branch. It also means such a branch cannot be proven wrong locally. |
| `net.http_post(text, jsonb, jsonb)` | `SELECT 1::bigint` | **HIGH.** Nothing is ever posted. Notification / webhook / export side effects are structural-only in a rehearsal. |
| `cron.schedule(text,text,text)` / `cron.unschedule(text)` / `cron.job` | inserts into / deletes from a plain table | **HIGH for behaviour, low for schema.** Schedule *registration* is faithfully rehearsed (and asserted by test 132); **no job ever fires**. Also missing: `cron.alter_job`, `cron.job_run_details` as pg_cron implements them, and the `cron.schedule(jobid,…)` overloads. |

### 3b. Added by `scripts/rehearsal_bootstrap.sql` (new in this work)

| Object | Why | Fidelity risk |
|---|---|---|
| role `postgres` (`LOGIN SUPERUSER CREATEDB CREATEROLE`) | Homebrew `initdb` names the bootstrap superuser after the OS user (`josetascon`), so Supabase's owner role does not exist. Everything is applied as `postgres` and the DB is owned by `postgres`. | **Low.** Superuser in both. Object ownership now matches Supabase. |
| role `authenticator` (`LOGIN NOINHERIT`, granted `anon`,`authenticated`,`service_role`) | PostgREST's connection role. `131_privilege_cleanup.sql` probes it directly. | **Low.** Exactly the Supabase shape (NOINHERIT, no explicit grants of its own). **No migration references it** — 074 names it in comments only — so it changes nothing in the chain. Effect: `131` went from *aborting after 12 assertions with 20 psql errors* to **24/24 passing**. |
| `cron.job.nodename / nodeport / "database" / username` | pg_cron's real column set. Without them `132_replay_parity.sql` **aborts** at `column j.database does not exist` and its last 4 assertions never run. | **Medium, and it is the one visible delta.** Populated faithfully — `database = current_database()`, `username = current_user`, as pg_cron does. But production recorded `database='postgres'` because the chain ran in the database *named* `postgres`, and a rehearsal database cannot be named `postgres`. So 132's D-5/8 and D-5/9 report the rehearsal DB name and fail. **This is a database-NAME artifact, not schema drift** — schedule, username, `active`, the exact command bytes and its md5 all match production. It was deliberately **not** "fixed" by hardcoding `'postgres'`; that would fabricate parity. |
| `pgcrypto`, `uuid-ossp` in schema `extensions` | Supabase pre-installs both. | **Low.** The chain does not need them (only `gen_random_uuid()` is used, built into PG13+). Installing them keeps the several "no migration creates an extension / references a pgcrypto symbol" assertions honest instead of vacuous. Verified: zero test-result change. |

### 3c. Deliberately **not** shimmed

* Roles `supabase_auth_admin`, `supabase_storage_admin`, `dashboard_user`, `pgbouncer` — no
  migration or test resolves them (074 names the first three in comments only). If a future
  migration grants to them, they must be added to the bootstrap or the grant will error.
* `supabase_migrations.schema_migrations` — the harness does **not** record applied versions.
  CI's "migration discovery proof" reads that table; the local harness proves the same thing
  by counting the files it applied (`107/107`). No test depends on it.
* Realtime, GoTrue, the Storage API, `pg_net`'s worker, `pg_cron`'s scheduler — no local
  runtime at all.

---

## 4. What could not apply, and why

**No migration file is skipped. Not one.** All 107 apply. Two *lines* inside one file are
stripped, line-wise, at pipe time — the file on disk is never modified — and the harness
prints them loudly at the end of every run:

```
==============================================================
 NOT APPLIED AS WRITTEN -- statements stripped for vanilla PG
==============================================================
  - 014_frequent_cron_schedules.sql: 2 line(s) matching /^create extension if not exists pg_/
    -- pg_cron / pg_net binaries are not installed in Homebrew PostgreSQL 17;
       scripts/rehearsal_bootstrap.sql supplies cron.schedule/cron.unschedule/cron.job
       and net.http_post stand-ins instead
  NO migration file was skipped in full.
==============================================================
```

The two lines are:

```sql
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net  with schema extensions;
```

These are the only `create extension` statements anywhere in the chain. The Homebrew
PostgreSQL 17 formula ships neither extension binary, so they cannot be installed; the
bootstrap's `cron.*` / `net.*` stand-ins take their place (see §3, and note the HIGH
behavioural risk attached to both).

### Gate-2 parity — the proof the replay is faithful

The freshly replayed local schema matches CI's certified Phase-0 baseline **exactly**:

| | local rehearsal | `ci.yml` `EXPECT_*` |
|---|---|---|
| public tables | 27 | 27 |
| public functions | 70 | 70 |
| public policies | 37 | 37 |
| public triggers (non-internal) | 24 | 24 |

Schemas created: `auth catalog cron extensions kernel market net notify public storage vault venue`.

---

## 5. pgTAP status

pgTAP **runs**, without Docker, without `pg_prove`, without the Supabase CLI.
`scripts/rehearsal_test.sh` installs `pgtap` (1.3.5, from
`/opt/homebrew/share/postgresql@17/extension/`) and drives `supabase/tests/*.sql` with plain
`psql`: `000_helpers.sql` commits the `tap` helper schema, every other file is
`BEGIN … ROLLBACK`, so the DB is pristine between files and between runs.

```
34 test files executed  (000_helpers + 33)
plan = 2921   ok = 2917   not_ok = 4   psql_err = 0
every file: assertions RUN == assertions PLANNED   (no file aborts early)
RESULT: pgTAP suite matches the expected local baseline.   exit 0
```

The 4 failures, all classified by the runner (anything else exits 1):

| File | # | Why |
|---|---|---|
| `060_payments_money.sql` | 11, 12 | Deliberate `todo()` markers — F-2 (unique index on `transfers.stripe_transfer_id`) and F-3 (payments amount/status guard trigger). **Expected-fail in CI too**; they flip green when the fix ships. Not a local artifact. |
| `132_replay_parity.sql` | 8, 9 | The `cron.job."database" = 'postgres'` comparison. Local artifact of the rehearsal DB's name — see §3b. Everything else in the row (schedule, username, active, command bytes, md5) matches. |

Note the suite is meaningful only because `supabase/ci/parity_grants.sql` is applied after the
chain: a fresh database has no default table privileges, so without it "anon cannot read X"
would pass because the GRANT is missing rather than because RLS works (finding REPLAY-1).
`rehearsal_reset.sh` applies it on every complete replay and **refuses to apply it, loudly, on
a partial one** (it references tables created by the last timestamped migrations).

Improvement delivered over the pre-existing `scripts/local/` harness: `131_privilege_cleanup`
went from *aborting* (12 of 24 assertions, 20 psql errors) to **24/24 green**, and
`132_replay_parity` from *aborting* (7 of 11, 5 psql errors) to **all 11 running, 9 green**.
Net 2903 → 2917 passing, and **zero psql errors anywhere in the suite**.

---

## 6. Honest limits — what a green rehearsal does NOT prove

1. **Nothing fires.** No cron job executes, no HTTP is posted, no realtime message is
   delivered. Only registration/structure is proven.
2. **No secret exists.** `vault.decrypted_secrets` is empty, so secret-gated branches are
   never taken. A bug reachable only when a secret is present is invisible here.
3. **No GoTrue / Storage API / PostgREST.** Grants and RLS policies are exercised via
   `SET ROLE` + `request.jwt.claims`, which is faithful, but the services' own behaviour is not.
4. **`supabase_migrations.schema_migrations` is not written**, so this harness cannot
   reproduce CI's discovery proof or the production ledger reconciliation.
5. **CI remains authoritative.** `supabase start` on the real Supabase local stack is the
   gate that must be green before merge. This harness is a fast local pre-check, not a
   substitute.

---

## 7. How to rehearse 092 → 093 later

Because the canonical order is byte-wise, a file named `093_*.sql` sorts **after
`092_notify_reduced.sql` and before the five `2026*` timestamped files** — it lands in the
middle of the chain, not at the end. Two complementary runs:

**A. Isolation run — does 093 apply on top of exactly 092?**

```sh
export PATH=/opt/homebrew/opt/postgresql@17/bin:$PATH
cd /Users/josetascon/snatchit-consol

# build the pre-093 state (102 files: 000 … 092; parity grants correctly skipped)
REHEARSAL_UPTO=092_notify_reduced.sql ./scripts/rehearsal_reset.sh snatchit_rehearsal_pre093
#   -> [rehearsal] REPLAY OK: 102/107 …
#   -> GATE-2  tables=24 functions=68 policies=34 triggers=22     (the pre-093 baseline)

# apply the candidate alone, stopping at the first error
psql -h 127.0.0.1 -U postgres -d snatchit_rehearsal_pre093 -v ON_ERROR_STOP=1 \
     -f supabase/migrations/093_<name>.sql

# idempotency / re-runnability check (if 093 is meant to be re-runnable)
psql -h 127.0.0.1 -U postgres -d snatchit_rehearsal_pre093 -v ON_ERROR_STOP=1 \
     -f supabase/migrations/093_<name>.sql
```

Do **not** run the pgTAP suite against `…_pre093`: parity grants are absent there and the
boundary tests would pass vacuously. The script says so on every partial run.

**B. Full-chain run — the one that actually gates the PR.**

```sh
./scripts/rehearsal_reset.sh          # picks 093 up automatically, in canonical position
./scripts/rehearsal_test.sh
```

Then check, in this order:

1. `REPLAY OK: 108/108` (the count rises by one when 093 lands).
2. The stripped-statements block still lists **only** the two `014` lines. If 093 adds a
   `create extension`, or needs a role/extension the bootstrap lacks, the block grows — that
   is a real finding, and `scripts/rehearsal_bootstrap.sql` (never the migration) is where the
   new prerequisite goes.
3. The printed `GATE-2` counts. They **will** change if 093 adds tables/functions/policies/
   triggers; the delta must equal what 093 claims to create, and
   `.github/workflows/ci.yml` `EXPECT_TABLES/FUNCS/POLICIES/TRIGGERS` must be bumped by the
   same delta in the same PR.
4. `rehearsal_test.sh` exits 0 and reports only the four known deltas. A new test file
   (`158_*`) shipping with 093 is picked up automatically; if it fails, that is a real
   finding. If it *legitimately* fails only for a local-only reason, add it to
   `known_notok()` in `scripts/rehearsal_test.sh` **with a written justification** — that
   function is the sole place a failure is allowed to be tolerated, and it is deliberately
   loud.
5. Re-run `./scripts/rehearsal_reset.sh` a second time to confirm the whole chain is still
   clean from scratch (the script is idempotent; a full cycle is ~5.5 s).

Finally: none of this replaces CI. `supabase start` on the real Supabase stack is still the
merge gate, and per the standing rule any migration-bearing PR still needs
`AUTODEPLOY-VERIFIED-OFF` with `git_branch` empty.

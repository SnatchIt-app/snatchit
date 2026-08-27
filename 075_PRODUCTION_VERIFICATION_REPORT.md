# 075 — REPLAY PARITY (SEC-4 + D-5): PRODUCTION VERIFICATION REPORT

**Status: APPLIED AND VERIFIED. The migration was a no-op on production, as authorized.**

| | |
|---|---|
| Applied | 2026-08-27 21:39:49–21:39:50 UTC |
| Migration | `supabase/migrations/075_replay_parity_storage_policies_and_cron.sql` |
| SHA-256 | `914b7bf10d26d9222232b3f4bcc3ce8d72c8627c03550a6375923e06a31de7fe` |
| PR | [#26](https://github.com/SnatchIt-app/snatchit/pull/26), merged 21:35:17 UTC |
| Authorized head | `f3538e89439cea9cf17a3d1a19c901f9d99674b0` |
| Merge commit | `23a8a3ef78aa2e857593032b389ad804eb0ff462` |
| Mechanism | `supabase db push --linked --include-all` |
| Ledger | **88 → 89** |

---

## 1. Pre-apply gates — all seven passed

| # | Gate | Required | Observed | |
|---|---|---|---|---|
| 1 | Head SHA | `f3538e89…d99674b0` | local == `origin/repo/075-replay-parity-final` == PR #26 head | PASS |
| 2 | Migration SHA-256 | authorized value | `914b7bf10d26d9222232b3f4bcc3ce8d72c8627c03550a6375923e06a31de7fe` | PASS |
| 2 | Rollback SHA-256 | authorized value | `0e60b625795eb835af5258c57c55a0bbdc9fbf4b3d679bb5acd1cc961f0f7b63` | PASS |
| 2 | Test SHA-256 | authorized value | `8ebcaf8e7d93e2c71cf2816d4047393d89a3c7a49a21a2047ad7a2822c4eecd2` | PASS |
| 3 | Auto-deploy OFF | `git_branch = ""` | `git_branch: ""` (read live from the branches API, not inferred) | PASS |
| 4 | SEC-4 | `cardinality(v_present) = 0` | `0`; `v_present = {}`; storage policies = 11 | PASS |
| 4 | D-5 | canonical job, guard false | jobid 10 · `*/5 * * * *` · postgres/postgres · active=true · len 44 · md5 `a8688b5b2add782b9a988d1f3850cd07` · **`d5_guard_would_fire = false`** | PASS |
| 5 | Ledger before apply | exactly 88 | 88 rows, md5 `9ed624814b416cb8bc9f07378a5e00fe` | PASS |
| 6 | `076` absent | 0 files | 0 files in checkout; 0 on `main`; repo total 89 | PASS |
| 7 | Dry run | exactly `075_…sql` | `Would push these migrations: • 075_replay_parity_storage_policies_and_cron.sql` | PASS |

Hashes were computed from the git blob objects at the head commit **and** independently from the working-tree files — both agree, with braced parameter expansion (`"${p}"`), the trap that produced a wrong hash during the 074 review.

## 2. The merge did not move the ledger

This was the specific regression to watch for: on PR #14's merge, the Supabase GitHub App applied migration `071` to production **39 seconds later**, unasked. That is AUTODEPLOY-1.

It did not happen here.

```
t+30s  after merge: remote ledger rows = 88
t+60s  after merge: remote ledger rows = 88
t+90s  after merge: remote ledger rows = 88
t+120s after merge: remote ledger rows = 88
t+150s after merge: remote ledger rows = 88
t+180s after merge: remote ledger rows = 88
```

Six samples over three minutes — four and a half times the interval in which the 071 incident fired — read directly from the production ledger via the CLI, all 88.

Independently: the Supabase app's check-run on the merge commit reports

```
name "Supabase Preview"  app=supabase  conclusion=SKIPPED  started == completed == 21:35:21Z
```

`skipped`, not `success`. The integration saw the merge and declined to act. The ledger moved only when I pushed it, four minutes later.

## 3. Post-apply verification — 24 items

| # | Item | Result |
|---|---|---|
| 1 | production ledger = 89 | **89**, md5 `5c16f0400a2f27304c5800419cea49c5` |
| 2 | repository migrations = 89 | 89 files on disk |
| 3 | exact source↔ledger equality | files == local == remote == 89; **only-on-disk: none; only-in-ledger: none** |
| 4 | dry run up to date | `{"upToDate":true,"migrations":[],"message":"Remote database is up to date."}` |
| 5 | six SEC-4 orphans absent | 0 present |
| 6 | canonical 11-policy storage set | 11, unchanged (full list §5) |
| 7 | cron job remains jobid 10 | **10** |
| 8 | cron schedule unchanged | `*/5 * * * *` |
| 9 | cron database unchanged | `postgres` |
| 10 | cron username unchanged | `postgres` |
| 11 | cron command byte-identical | md5 `a8688b5b2add782b9a988d1f3850cd07`, length 44 — identical to pre-apply |
| 12 | cron active = true | `true` |
| 13 | cron run history preserved | 6537 rows for jobid 10; **first run `2026-08-05 05:00:00`** — 22 days of history, predating the apply |
| 14 | `sweep_auth_password_changes()` body unchanged | prosrc md5 `e838ae31346d81752138aae052833de1`, identical to pre-apply |
| 15 | nothing but the ledger changed | **12/12 catalog digests byte-identical** (§4) |
| 16 | Gate-2 at baseline | tables 27 · functions 69 · policies 37 · triggers 24 — unchanged, and identical to the post-075 fresh replay |
| 17 | full pgTAP passes | `files=16 tests_ran=287 result=PASS failing_files=0 bad_plans=0` |
| 18 | fresh replay 89/89 | `migration files on disk: 89 | applied by the CLI: 89 | duplicate versions: 0` |
| 19 | `132_replay_parity.sql` passes | `supabase/tests/132_replay_parity.sql ... ok` (11/11) |
| 20 | pre-Scheme-B backup intact | **79 rows**, md5 `4cbff940d09f26f04c142fe449674046` — unchanged |
| 21 | business row counts unchanged | listings 111 · bids 98 · payments 56 · transfers 36 · profiles 14 |
| 22 | storage object count unchanged | 172 |
| 23 | no `076` exists or was applied | 0 files in checkout, 0 on `main`, absent from the ledger |
| 24 | auto-deploy remains OFF | `git_branch: ""`, branch record `updated_at` still `2026-08-27T15:49:25Z` — untouched since you disabled it |

Items 17–19 come from CI run `33117872377` at the authorized head. That evidence transfers to what is now on `main` **because the trees are identical**: merged `main` `23a8a3e` and reviewed head `f3538e8` both resolve to tree `93df248cc71b981bfcccd81afeb63c0353d23820`. The squash changed the commit, not one byte of content.

## 4. The no-op, measured rather than asserted

Twelve catalog dimensions over `public` and `storage`, digested before the apply and again after:

| Dimension | n | Before | After | |
|---|---|---|---|---|
| policies | 48 | `603325847c38f0076eb0c74c5cd6f61d` | `603325847c38f0076eb0c74c5cd6f61d` | identical |
| columns | 420 | `5f6a87ce129e525e189736e0cab90047` | `5f6a87ce129e525e189736e0cab90047` | identical |
| functions (src+secdef+search_path) | 86 | `1d1ea353e6c638607c19631589c38ea7` | `1d1ea353e6c638607c19631589c38ea7` | identical |
| triggers | 28 | `0f5f2d54c2438bb02eee435289b77605` | `0f5f2d54c2438bb02eee435289b77605` | identical |
| table ACLs + RLS flags | 35 | `588a062d08898d6c68f6850e0011fa08` | `588a062d08898d6c68f6850e0011fa08` | identical |
| function ACLs | 86 | `1a4a6de58603a7f9eb98ecfbaafe6c21` | `1a4a6de58603a7f9eb98ecfbaafe6c21` | identical |
| `pg_default_acl` | 27 | `7d4b7457498d24ca0f56c2112f4f1821` | `7d4b7457498d24ca0f56c2112f4f1821` | identical |
| storage buckets (size/MIME/public) | 3 | `b7260ad34da0587f48615f0143e57d7c` | `b7260ad34da0587f48615f0143e57d7c` | identical |
| cron jobs | 3 | `72960b533abbf5aa851b3fb959b9ed27` | `72960b533abbf5aa851b3fb959b9ed27` | identical |
| extensions | 7 | `6056d99c7573b52e568bccf7777e55ff` | `6056d99c7573b52e568bccf7777e55ff` | identical |
| indexes | 107 | `7979f9fca76723c333ee2392909adcc2` | `7979f9fca76723c333ee2392909adcc2` | identical |
| constraints | 219 | `430729ea57b92faaf2022d749086de5e` | `430729ea57b92faaf2022d749086de5e` | identical |

These are content digests, not counts. The policy digest includes `cmd`, `roles`, `qual` and `with_check`; the function digest includes `prosrc`, `prosecdef` and `proconfig`; the ACL digests include the raw `relacl`/`proacl` arrays. A silent rewrite that preserved counts would still move them. **Nothing moved.**

**EXPECTED PRODUCTION CHANGE:** one row in `supabase_migrations.schema_migrations` — version `075`, name `replay_parity_storage_policies_and_cron`.
**EXPECTED BUSINESS/SCHEMA CHANGE:** none. **Observed:** none.

### The two failure modes you named explicitly did not occur

> *"If SEC-4 drops a policy or D-5 unschedules/recreates the cron job, that contradicts the authorized no-op package."*

- **SEC-4 dropped nothing.** Storage policy count 11 before and after; the policies digest is byte-identical, so no policy was dropped, added, or rewritten.
- **D-5 unscheduled and recreated nothing.** The job is still `jobid = 10` — a recreated job would have received a new jobid — and it still carries 6537 run-detail rows reaching back to 2026-08-05.

And a live behavioural confirmation from the Postgres log, 11 seconds after the apply committed:

```
21:40:00.039  cron job 10 starting: select public.sweep_auth_password_changes();
21:40:00.497  cron job 10 completed: 1 row
```

The job ran on its normal five-minute tick, with the exact canonical command, immediately after 075 landed.

**One honest limit on the log evidence.** The apply session's only logged statements are the CLI's ledger bootstrap (`CREATE SCHEMA` / `CREATE TABLE` / `ALTER TABLE` on `supabase_migrations`); no `DROP POLICY` and no `cron.unschedule` appears. That is *consistent* with the no-op but is **not proof of it** — `log_statement` records top-level statements, and SEC-4's drops would have been dynamic DDL executed by `format()` inside a `DO` block, which would not be logged in any case. The proof of the no-op is the digest equality in §4, not the absence of a log line. `INFERENCE`, labelled as such.

## 5. The canonical storage surface, intact

```
auction-media owner delete unreferenced   DELETE  {authenticated}
auction-media owner insert                INSERT  {authenticated}
auction-media owner update                UPDATE  {authenticated}
avatars owner insert                      INSERT  {authenticated}
avatars owner update                      UPDATE  {authenticated}
proof-docs owner delete unreferenced      DELETE  {authenticated}
proof-docs owner insert                   INSERT  {authenticated}
proof-docs owner read                     SELECT  {authenticated}
proof-docs owner update                   UPDATE  {authenticated}
proof-docs transfer party read            SELECT  {authenticated}
public read public buckets                SELECT  {public}
```

Worth reading closely, because it confirms the reason 075 exists: **`avatars` has `insert` and `update` and no `DELETE` policy at all.** A from-source rebuild was creating `"avatars: owner delete"` — a delete capability production grants in no form whatsoever — and an unguarded `"storage: owner delete"` that OR-unioned with, and therefore repealed, migration 048's `NOT EXISTS` cover-image guard. That divergence is what 075 removes on a replay. It removes nothing here, because production never had it.

## 6. What 075 actually bought

Nothing on production. That was the point — and it is why the no-op had to be *measured* rather than argued.

What it bought is that a rebuilt Snatch It database is now the same database. Before 075, a from-source replay produced a **strictly weaker** storage authorization surface than production and **silently lost password-change security notifications entirely** — the sweep function present and correct, and nothing on earth calling it. No error, no log line, no failing test. That is the worst shape a reproducibility gap can take, and it is now closed in the only place it can be closed: the migration chain.

Gate-2 could not have caught either half. It counts `pg_policies WHERE schemaname = 'public'`, so both the RED tree (six orphans present) and the GREEN tree (absent) print `policies=37`, and **Gate-2 passes on RED**. `132_replay_parity.sql` is the only thing in the repository that sees this class of drift.

---

## 7. What this does NOT authorize, and what remains open

075 is closed. Nothing else moved with it. `076` does not exist, no Phase-2 work has begun, and the four architecture rulings and the `door_open_at` lifecycle gap remain exactly as they were.

Two items from the pre-production report are still outstanding and are **not** affected by this apply:

- **PR #18** — the CLI-version drift assertion **and the `todo()`/`skip()` masking ratchet**. Not on `main`. The masking ratchet is the fix for a fail-open in which a *required* check reported green while security assertions failed. This run's own summary shows the mechanism live: `todo_failing=2`, computed and printed, gating nothing.
- **PR #19** — the MONEY-1 impersonation matrix. Not on `main`.

These belong to the pre-Phase-2 blockers report, which follows next.

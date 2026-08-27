# 075 — Replay Parity (SEC-4 + D-5): Pre-Production Report

**Status: awaiting owner authorization. Nothing applied. Production ledger 88, unchanged.**

| | |
|---|---|
| Findings | **SEC-4** (orphan `storage.objects` policies) · **D-5** (unscheduled password-change sweep) |
| Classification | **Reproducibility / parity.** Zero production exposure today; the defects exist only on a database rebuilt from source. |
| Migration | `supabase/migrations/075_replay_parity_storage_policies_and_cron.sql` |
| Final head SHA | **`f3538e89439cea9cf17a3d1a19c901f9d99674b0`** |
| Migration SHA-256 | **`914b7bf10d26d9222232b3f4bcc3ce8d72c8627c03550a6375923e06a31de7fe`** |
| Rollback SHA-256 | **`0e60b625795eb835af5258c57c55a0bbdc9fbf4b3d679bb5acd1cc961f0f7b63`** |
| Test SHA-256 | **`8ebcaf8e7d93e2c71cf2816d4047393d89a3c7a49a21a2047ad7a2822c4eecd2`** (`supabase/tests/132_replay_parity.sql`) |
| PR | [#26](https://github.com/SnatchIt-app/snatchit/pull/26) — supersedes #23 · MERGEABLE/CLEAN · all required checks pass |
| Ledger | **88 → 89** |

Hashes taken from the exact bytes at the final head via `git cat-file blob "$(git rev-parse "HEAD:${path}")"`.

---

## 1. Severity and exploitability — stated without inflation

**Neither finding is exploitable on production.** Both describe a divergence that appears only when the
database is rebuilt from `supabase/migrations/`.

This still matters, and specifically for Phase 2: Phase-2 packages will be developed and tested against
fresh replays. Every security conclusion drawn on a rebuilt stack today is drawn against a database
that is **not** the one it is supposed to reproduce.

### The corrected SEC-4 rationale

An earlier draft claimed a replay grants `anon` INSERT/DELETE paths into the public buckets. **That
over-claim has been removed and is not restated here.** The six orphan policies carry no `TO` clause
and therefore default to `TO PUBLIC`, which widens the **role set** at catalog level — but every
orphan INSERT/DELETE predicate requires `auth.uid()::text = (storage.foldername(name))[1]`, and
`auth.uid()` is NULL in a genuine anon session, so the comparison yields NULL and the policy never
permits the row. **A real anon caller gains no reachable write path.** The two orphan SELECTs are
likewise inert beside production's `public read public buckets`, already `TO public` over the same
two buckets.

The real effects on a rebuilt stack are:

1. **`avatars: owner delete` grants authenticated users a DELETE that production does not grant in
   any form** — production's only DELETE policies are `auction-media owner delete unreferenced` and
   `proof-docs owner delete unreferenced`.
2. **`storage: owner delete` is unguarded, and RLS policies OR within a command**, so it unions with
   and defeats the `NOT EXISTS (… listings.cover_image_path …)` guard migration **048** added. A
   seller could delete a cover image out from under a live listing. **Scoped to `auction-media` and
   `avatars` only — 049's `proof-docs` guard stands intact.**
3. **Replay authorization drift** — the rebuild is not the database it is meant to reproduce.

### D-5

`sweep_auth_password_changes()` is a `SECURITY DEFINER` watermark sweep over
`auth.audit_log_entries` that emits `security_password_changed` inbox notifications, deduped on
`auth_pwd:<audit_id>`. It must be cron rather than an Edge Function because
`has_table_privilege('service_role','auth.audit_log_entries','SELECT') = false`.

A rebuild has the function **and** its seeded watermark row, but nothing calling it — so it silently
loses password-change security notifications entirely. No error, no log line, and until this test
file existed, no failing check.

## 2. Three-way comparison

### SEC-4 — `storage.objects` policies

| | count | detail |
|---|---|---|
| **SOURCE** | 17 | `000_baseline_schema.sql` creates 6 (lines 252-272, 850-871); 033/034/048/049/051/053 create 11. The six names appear **only** in 000 and in 075 across all 89 migrations — no later migration drops them. |
| **FRESH REPLAY** | 17 | RED run assertion 2: **6 Extra records, 0 Missing** — the six orphans, all `{public}` |
| **PRODUCTION** | 11 | re-read 2026-08-27; all six absent, checked **individually by name**, under any schema, and case-folded/whitespace-collapsed (0 variants) |

**Why replay yields 17 and production 11:** `000_baseline_schema.sql` is a *reconstructed* baseline,
not a transcript of what ran against production. Production's storage surface was reconciled
out-of-band before 051/053 codified it, and the `DROP POLICY IF EXISTS` statements in 051/053 target
the **dashboard-generated** legacy names (`allow uploads v2 51etwa_0`, `Allow authenticated avatar
upload 1oj01fe_0`, …) plus their own — never the six colon-named baseline policies, because those
never existed in production. A replay genuinely executes those blocks, and nothing removes them.

### D-5 — the sweep job

| | state |
|---|---|
| **SOURCE** | scheduled by nothing. `0600_auth_password_change_notifications.sql:55` mentions it in a **comment**; only 014, 032 and 075 call `cron.schedule`. |
| **FRESH REPLAY** | absent — RED assertion 7 `have: 0`, assertion 8 `have: NULL`, assertion 9 `have: canonical=0 total=0` |
| **PRODUCTION** | `jobid=10, schedule='*/5 * * * *', database='postgres', username='postgres', active=true, command='select public.sweep_auth_password_changes();'`, len 44, md5 `a8688b5b2add782b9a988d1f3850cd07`, hex tail `28293b` |

## 3. Complete SQL, with per-statement production effect

The intended answer is **NONE for every statement**, and it is proven by executing each guard's
predicate read-only against production — not by reasoning about it.

| statement | production effect | proof |
|---|---|---|
| `BEGIN;` / `COMMIT;` | **NONE** | commits a transaction that performs zero catalog or data writes |
| SEC-4 (a) `SELECT array_agg(policyname) INTO v_present … WHERE schemaname='storage' AND tablename='objects' AND policyname = ANY(c_orphans)` | **NONE** | read-only. Run verbatim on production → **0 rows**; each of the six checked individually → absent; `coalesce(...,ARRAY[]::text[])` makes it a zero-cardinality array |
| SEC-4 (b) `IF cardinality(v_present)=0 THEN RAISE NOTICE …; RETURN;` | **NONE** | branch **is taken** on production; `RAISE NOTICE` writes to the server log only |
| SEC-4 (c) `FOREACH … EXECUTE format('DROP POLICY %I ON storage.objects', …)` | **NONE — not reached** | (b) returned; the DROP text is never constructed. This is what makes it safe under `postgres`, which does **not** own `storage.objects` (owner `supabase_storage_admin`, `pg_has_role=false`, `rolsuper=false`) |
| D-5 (a) `IF to_regclass('cron.job') IS NULL THEN RAISE EXCEPTION` | **NONE** | read-only; `cron.job` exists |
| D-5 (b) four-way guard on `jobname + schedule + command + active` | **NONE** | executed on production: exact byte match on command (len 44, md5 `a8688b5b…`) and schedule; `d5_guard_would_fire = false` → branch TRUE → `RETURN` |
| D-5 (c) `FOR v_jobid … PERFORM cron.unschedule(v_jobid)` | **NONE — not reached** | (b) returned; **jobid 10 keeps its identity, ownership and `cron.job_run_details` history** |
| D-5 (d) `PERFORM cron.schedule(…)` | **NONE — not reached** | (b) returned |

One effect the file itself does not contain: applying 075 inserts `075 | replay_parity_storage_policies_and_cron` into `supabase_migrations.schema_migrations`. That row is written by the migration runner — **METADATA ONLY**, and it is the point of the exercise.

`UNVERIFIED (forward-looking):` the classification holds against the catalog as read on 2026-08-27.
If one of the six orphan names were created on production before apply, the DROP loop would fire.
The migration's own verification query should be re-run immediately before applying.

## 4. RED → GREEN, re-established against this artifact

The earlier RED ran against a pre-rebase tree with different tests and no longer binds. A fresh pair
was produced.

**RED** — [33116682827](https://github.com/SnatchIt-app/snatchit/actions/runs/33116682827), throwaway
branch = `main` (`ded3724`) + the test file only, byte-identical to GREEN's, migration absent
(verified by the reviewer). `Result: FAIL`, `Tests: 11 Failed: 9`, `Failed tests: 1-9`:

| # | assertion | diagnostic |
|---|---|---|
| 1 | none of the six baseline policies survive | 6 present |
| 2 | policy set equals production's eleven on `(policyname, cmd, roles, qual, with_check)` | **6 Extra, 0 Missing** |
| 3 | replayed set matches the PRODUCTION fixture (name, cmd, roles, md5 of predicates) | **6 Extra, 0 Missing** |
| 4 | every DELETE policy keeps the unreferenced guard | 2 unguarded |
| 5 | only `public read public buckets` carries public/anon | 3 extra |
| 6 | no INSERT/UPDATE/DELETE policy carries public/anon | 4 extra |
| 7 | **cron: job exists** | `have: 0 / want: 1` |
| 8 | **cron: exact schedule/db/user/command/active match** | `have: NULL` |
| 9 | **cron: no duplicate, no drift** | `have: canonical=0 total=0` |

Assertions 10–11 passed pre-075 legitimately — 0600/0601 create the function and seed the watermark
independent of the schedule, so they never had a defect.

**The `0 Missing records` is load-bearing:** the replay's other eleven policies matched the production
fixture exactly, so the entire divergence is the six extras — and it demonstrates the predicate
normalization is not masking anything.

**GREEN** — [33116690247](https://github.com/SnatchIt-app/snatchit/actions/runs/33116690247) at the
exact reviewed SHA: `Files=16, Tests=287, Result: PASS`, `failing_files=0 bad_plans=0`,
`coverage floor OK: 16 >= 16, 287 >= 287`.

### The vacuity fix

The previous suite's cron coverage was a single `is_empty` that **passed trivially** on an
un-migrated replay, because `cron.job` held no such job and the subquery was empty. It is replaced by
three assertions that each fail for a distinct reason, and assertion 9 in particular cannot pass at
zero rows — aggregates without `GROUP BY` return one row, so zero rows yield
`'canonical=0 total=0'` ≠ `'canonical=1 total=1'`. Confirmed empirically in RED.

The file now plans **11**, not 12: three weak assertions were replaced by three stronger ones.
Shorter and strictly stronger. No `todo()`, no `skip()`.

**A real bug was caught by executing the fixture rather than trusting it:** assertion 8 originally
rendered `active` via `format('%s', …)`, which calls boolean's output function and yields `t` while
the expected literal said `true` — it returned **false** against production. Fixed to `active::text`
and re-verified. The reviewer independently confirmed no sibling assertion shares that defect.

## 5. Fresh replay

`89` discovered / `89` applied / `0` skipped / `0` duplicate version prefixes. **No strict-prefix
pairs** — Scheme-B normalization left no bare `023`/`055`/`056`/`059`/`060`/`066` siblings. 85 numeric
+ 4 timestamp prefixes; `075` sorts between `074` and `20260714190445`.

## 6. Storage-policy parity proof

Because Gate-2 is structurally blind here, parity is asserted directly. Assertion 2 compares the
replayed set to eleven literal expectations on `(policyname, cmd, roles, qual, with_check)`;
assertion 3 compares to the **production fixture** (name, cmd, roles, md5 of `USING|WITH CHECK`). The
two encodings are independent cross-checks — the reviewer hashed all eleven literals and compared to
production's own computed digests: **identical, 11/11**.

Predicates are normalized with `btrim(regexp_replace(replace(x,'public.',''),'\s+',' ','g'))` because
`pg_get_expr` output depends on session `search_path` and emits newlines inside sub-SELECTs. The
reviewer tested the normalization for lossiness and confirmed none of the eleven predicates contains
`public.` inside a string constant or a multi-space literal, and that the file scopes its claim
correctly as lossless *here*. Name, command and role set are compared exactly.

## 7. Cron parity proof

Assertion 8 asserts `schedule`, `database`, `username`, `command`, `active` in one exact string
comparison, plus `length` and `md5` so byte drift fails. Assertion 9 asserts exactly one canonical
row and no drifted or inactive duplicate.

## 8. Gate-2 limitations — measured, not asserted

`ci.yml:146` counts `pg_policies WHERE schemaname='public'` only. **RED (six orphans present) and
GREEN (absent) both reported `tables=27 functions=69 policies=37 triggers=24`, and Gate-2 passed on
RED.** It also counts no `cron.job` rows, so D-5 was equally invisible.

No other existing gate catches it either: migration discovery counts files; privilege parity diffs
`table_schema='public'`; and `supabase/tests/100_storage.sql` passes with all six orphans present.
**`132_replay_parity.sql` is the only thing in the repo that sees this.** A follow-up to extend Gate-2
with storage-policy and cron counts is recorded and deliberately not bundled.

## 9. Rollback

**"Rolling back 075 on production" is vacuous — there is nothing to undo.** The only environment it
changes is a fresh replay. The script executes **only `RAISE NOTICE`s**.

- It does **not** recreate the six orphans, deliberately: doing so would grant authenticated users a
  DELETE on avatars that production does not grant at all and would OR-defeat 048's guard, leaving
  the database *less safe than production*. That is not a rollback.
- It does **not** unschedule the sweep. `cron.job` records no provenance, so the script cannot
  distinguish a replay-created job from production's hand-created jobid 10; auto-unscheduling would
  destroy a live job and silently switch off password-change notifications for every user.
  Commented-out SQL is provided for a human to run on a database they have confirmed is not
  production — and even then it merely restores the D-5 defect.

## 10. Adversarial review — **ACCEPT (unconditional)**

No Critical, no High. The reviewer re-derived the command md5, byte length and hex dump itself,
checked all six orphan names individually including case-folded variants, executed the guard's
negation to obtain `d5_guard_would_fire = false`, confirmed all three cron assertions fail at zero
rows, cross-checked the eleven predicate fixtures 11/11 against production digests, and verified the
RED commit genuinely lacked the migration.

**It states explicitly that the no-op claim holds.**

Three informational findings, none blocking: the migration's guard matches 4 fields while assertion 9
requires 6 (test stricter than the thing it certifies — safe direction); assertion 4's
`NOT ILIKE '%NOT (EXISTS%'` is a text heuristic backstopped by assertions 2 and 3; and a header
caution about `DROP POLICY` ownership is slightly over-stated, already labelled `UNVERIFIED:` by the
author and not depended upon.

## 11. Preconditions

**Auto-deploy OFF** — branch record `git_branch = ""`, `updated_at` still `2026-08-27T15:49:25Z`.
Read from the record, not inferred from the absence of a deployment.

**Dry run, executed from the final checkout against the live project:**

```
Would push these migrations:
 • 075_replay_parity_storage_policies_and_cron.sql
```

Exactly one. **No `076` exists anywhere in the tree** (0 files). Ledger **88 → 89**.

## 12. Blast radius

**Zero on production, by construction and by measurement.** Both blocks return before emitting DDL;
no table, policy, function, trigger, grant, cron job or row is touched. The only production change is
one ledger row.

Worst case if the pre-apply state changed between this report and the apply: one of the six orphan
names appears on production, and the DROP loop fires against a policy that should not exist. The
migration's own verification query detects this; re-run it immediately before applying.

## 13. Remaining known findings

- **Unmerged security-gate work.** PR **#18** (CLI-version drift assertion **and the `todo()`/`skip()`
  masking ratchet**) and PR **#19** (MONEY-1 impersonation matrix) are **not on `main`** — verified:
  `SUPABASE_CLI_VERSION` refs 0, `EXPECT_TODO` refs 0. The masking ratchet is the fix for a fail-open
  where a **required check reported green while security assertions failed** via `todo()`. This must
  be resolved before any Phase-2 GO verdict.
- **Superseded PRs** still open: #21 (bundled 073), #22 (integration), #23 (pre-rebase 075).
- **Phase-2 amendment** — backend consolidation held pending four owner rulings plus the
  `catalog.event_session.door_open_at` lifecycle gap.
- **Phase-2 renumber** to `076`–`091`, mechanical, at integration.
- MONEY-1 (Medium, not exploitable) · F-2 / F-3 · `buy_now_price` re-pricing (severity **unknown**
  pending installed-base measurement) · `strict_required_status_checks_policy: false` · the
  `pg_default_acl` generator class 074 did not close · Gate-2 blind to storage/cron.

---

**AUTHORIZE 075 REPLAY PARITY TO PRODUCTION?**

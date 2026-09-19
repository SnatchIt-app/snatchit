# Production Disk IO budget warnings — read-only investigation (A, 2026-09-19)

**Authority (owner, directly to A):** a lightweight, read-only performance investigation of `hqycwntpfoztoinemqns` after Supabase's Disk IO Budget warnings on 2026-09-11 and 2026-09-19 (13:40 EDT = 17:40Z).
- **Covered:** existing metrics and logs; remaining budget, compute size, disk I/O, memory and swap; expensive query statistics; scheduled-job activity.
- **Not covered:** heavy scans, load tests, repeated polling, restarts, upgrades, configuration changes, migrations, customer-data exports.

**What was read, 18:21–18:27Z, all read-only, through the Supabase connector:**
- `get_project`;
- 6 `execute_sql` reads of `pg_settings`, `pg_stat_database`, `pg_stat_statements`, `cron.job`, `pg_stat_all_tables`, function sources, and `cron.job_run_details` **through its run-ID primary key only** (at most 20,000 rows, never a full scan);
- 3 aggregated `query_logs` reads;
- Supabase docs.

No customer rows were read.

## Finding: one recurring job drives the disk I/O

| Evidence | Value |
|---|---|
| `pg_stat_statements` top entry | `select ops.run_all_detectors()` (role `postgres`): **3,385 calls, mean 11.7 s, 39,524 s total, 9,703,790 blocks read from disk (≈74 GB), 33 GB of temp files written** |
| Its share of all disk reads | **99.1%** of the database's 9,791,846 `blks_read` since the counters began (cache-hit ratio otherwise 99.76%) |
| Schedule | job 30 `ops-detect-tick`, `*/5 * * * *` (288 runs a day) |
| Recent behaviour | 466 runs in the last 39 h, all succeeded, **average 12.1 s, max 22.9 s**. Every other job averages about 0.1 s or less |
| Since when | the same about 11–12.6 s per run at samples taken 11, 7 and 3 days ago and today (earliest: 2026-09-08, the day the admin console went live). **Recurring, not a spike** |
| Mechanism (source) | `ops.detect_jobs` (migration 117, part of `run_all_detectors`) reads `cron.job_run_details` with `where d.start_time > now() - interval '7 days'` and then `row_number() over (partition by jobid order by start_time desc)` |
| Why it is expensive | `cron.job_run_details` is **245 MB, about 72% of the 339 MB database**. It holds about 600,000 rows (run IDs 1–599,283), because it is never purged. **Its only index is the run-ID primary key** (none on `start_time`). It has been **sequentially scanned 3,509 times**, about one per detector run. It has **never been vacuumed or analysed**. `work_mem` is about 2 MB, so the week-long window sort spills to temp files |
| Estimated load | about 22 MB of disk reads plus about 10 MB of temp writes per run, i.e. **about 9 GB of disk I/O a day**, in 12-second bursts every 5 minutes |

**Compute:** `shared_buffers` 280 MB, `max_connections` 60 and `effective_cache_size` 480 MB mean Nano or Micro (docs: 60 connections is Nano or Micro). The dashboard banner states a baseline of 5 MB/s. **The exact tier was not read**; it is under Settings → Compute and Disk.

## Is performance affected now?
- **No user-facing degradation is visible.**
  - Edge logs from 12:00 to 18:25Z, in 30-minute buckets: about 105 requests each; p50 155–199 ms; p95 579–722 ms; max ≤ 1.5 s; **0 HTTP 5xx**; **0 Postgres ERROR/FATAL**. The 17:30 bucket, which holds the warning, is unremarkable.
  - Other scheduled jobs average 0.056–0.069 s in every window sampled from 2026-09-08 to today.
- **Risk:** once the budget is exhausted, disk throughput drops to the baseline, which slows every query that misses the cache. The detector's own burst is the main consumer.
- **Not verified (the dashboard only; no metrics endpoint was used, because that would need the service key):** remaining Disk IO budget %, disk read/write MB/s, memory, swap. Where to read them: Dashboard → Observability → Database ("Disk IO % consumed", memory, swap).

## Our own inspection activity (considered, not assumed)
- **The console's jobs page (`ops.job_health`, run by operators): 0 calls today**, 00:00–18:30Z, so it did not contribute to today's warning. Its per-call cost is high (see (1) below).
- **Present in `pg_stat_statements`, but small:**
  - Dashboard/pg-meta catalog listings: 190 + 11 + 1 calls, about 1.8 GB of temp files in total, **0** disk reads.
  - The migrations listing: 51 calls, 137 MB of temp files.
  - Inspection queries against `pg_stat_statements`: a few MB each.
  - **One prior 7.8 s cron summary query** (a full scan of `job_run_details`, 26 MB of temp files, 1 call; the author is not identified).
  - Together, well under 5% of the detector's temp writes, and almost no disk reads.
- **Timing today:** A's first production database read today was at 18:21Z, after the 17:40Z warning. A's only earlier production call today was a project-metadata listing. Other sessions' reads today are not known to A.
- **2026-09-11:** a contribution from that period's production migration work is possible. It is **not verified**, because no per-day I/O metrics were read.

## Smallest corrective action (recommended; nothing applied)
1. **Root-cause fix, $0.** A small migration that:
   - bounds `ops.detect_jobs` to recent runs **through the run-ID primary key** instead of `start_time`. This investigation read the last 20,000 runs that way in one pass;
   - bounds the console's `ops.job_health` the same way. It is worse per call: per-job `start_time` subqueries, up to about 72 full-table scans per page load (116:1318-1332). But it is on-demand only, and **0 calls today** (edge logs, 00:00–18:30Z);
   - adds a daily pg_cron clean-up that keeps a bounded history (for example 14 days) of `cron.job_run_details`.
   This removes the full-table scan and the temp spill, i.e. about 99% of today's disk reads. The ops console is D's area, so it would be a D-authored, A-reviewed migration with pgTAP and CI, applied only with the owner's authorization. Shrinking the existing 245 MB file afterwards would need a separately authorized `VACUUM FULL` of that one table, which takes a brief exclusive lock; it is optional once the scan is bounded.
2. **Interim relief, only if the budget runs out before (1) ships ($0; one reversible statement; owner authorization needed):** `ops-detect-tick` every 15 minutes instead of 5, which cuts this load about threefold. The cost is slower ops-case detection.
3. **A compute upgrade is not recommended as the fix.** Verified prices (Supabase docs):
   - Micro about $10/month, Small about $15/month; the Pro plan's $10 compute credit covers Micro. So **Micro → Small adds about $5/month**.
   - If the instance is still **Nano**, docs state that a Nano in a paid organization is **billed the same as Micro**, and recommend upgrading. **Nano → Micro would cost $0 extra**, with less than 2 minutes of downtime.
   - Neither removes the full-table scan.

## Effect on the pending production applies
- **The applies are small and fail-safe**, so this does not block them technically:
  - 142 is a catalog-only `ADD COLUMN` with `lock_timeout 3s`;
  - 140 and `20260909000000` are function definitions.
- **Timing:** several detectors read `public.payments` inside the detector's single transaction (`detect_refunds`, `detect_paid_unsettled`, `detect_disputes` and others, per 117/118). So 142's `ACCESS EXCLUSIVE` lock on `payments` would wait behind a detector run in progress (runs start every 5 minutes and last about 12 seconds). It would then fail cleanly after 3 s. Apply 142 in the gap, about 1–4 minutes after a detector run starts at :00/:05/…, and retry if it fails.
- **Recommendation:** do not apply while the budget is depleted. Preferably ship fix (1) first, or at least read "Disk IO % consumed" immediately before the window.

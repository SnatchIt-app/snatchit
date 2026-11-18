# Cron history boundary correctness — registry 213

The 145 detector reads recent runs above a binary-search floor set at seven days
plus one hour, then reads older history at or below that floor. Its recent read
also filters out everything at or before seven days. A job whose newest run lies
between the two cutoffs loses that run in both reads. It can receive fresh-job
grace and omit its stalled-job case, or report an older run instead.

213 keeps all started rows above the floor for `last_run`. Count, last success,
last failed run/message, and last-five status calculations still use the strict
`start_time > now() - interval '7 days'` predicate. The existing lower walk,
5000-runid slices, schedule parser, first-seen map, cases, and alerts are retained.
This is a correctness fix. It makes no I/O or performance claim.

Both directions accept only the exact known 145 and 213 function bodies and
verify their resulting body hash. They fail closed on an unknown third body.
`CREATE OR REPLACE` preserves the existing function OID, owner, and grants.

## Verified locally on November 18, 2026

Base: `e250305d2532a7436c2258bbdd72cde16bbb56bf`.
Actual PostgreSQL 17.11 and pgTAP 1.3.5 ran the actual function and its dynamic SQL.

- Baseline body `a315f6713602062ea0aa6958b3dd3fac`: 6 failures of 32 assertions.
- Candidate body `be7ba9e3c04c26b9c99728900625a333`: 32/32 passing.
- Rollback: exact baseline restored, with the same six failures.
- Reapply: exact candidate restored, 32/32 passing.
- Mutating the count to include old rows: four assertions failed.
- Mutating last_success to include margin successes: one assertion failed.
- Unknown mutant body: forward and rollback rejected it and left it unchanged.
- Repeating either migration succeeded. OID, owner, ACL, security-definer,
  search path and volatility remained unchanged.

281 covers the exact seven-day boundary, one microsecond inside it, a margin
run, the exact older floor, older history, null start times, multiple slices,
strict failure metrics, a current failed job, disabled jobs, both never-run grace
states, repeated detection, and recovery. Its first-seen fixture uses an upsert,
so it works even if the setting row was absent. Fixture changes roll back.

## Proof scope and reproduction

This is a focused test, **not a full Supabase chain replay**. The isolated harness
uses explicit case, alert, sweep, settings, cron scheduling and job-state doubles.
The canonical interval parser and both 145 function statements are retained in
the harness. The case/alert integration and authorization paths are not proven
by these doubles; normal repository CI must validate 281 against the full stack.

Private retained evidence directory:
`/Volumes/DEV-SSD/01_SNATCH_IT/private-evidence/cron213-20261118/final32`.
`results.json` is its result summary. Earlier logs in the parent directory are
historical attempts, including a superseded fixture whose generated ages crossed
the seven-day cutoff. They are not the final proof.

The owned cluster data stays at
`/Volumes/DEV-SSD/01_SNATCH_IT/private-evidence/cron213-20261118/pgdata`.
Its data and socket directories use mode 0700, `listen_addresses` is empty, and
its socket path is `/tmp/cron213-socket`, port 55484. The verifier checks this
identity before changing anything. No services were installed or hosted databases
accessed. Keep the evidence and data; a stopped cluster may be restarted explicitly
with the same private socket-only settings.

The baseline harness bootstraps a new empty database named `cron213_proof` using
`bootstrap-focused.sql` followed by `baseline-focused.sql`. With that private
cluster already running, run:

```sh
python3 docs/release/cron-history-boundary/verify-focused.py \
  /tmp/cron213-socket 55484 /absolute/new/evidence-directory
```

## Release boundary

Draft only. Registry 212 / timestamp `20261118000000` belongs to the separate
financial lane and is unresolved in this base. Resolve registry/sequencing and
run full-chain CI before considering merge. No merge, hosted apply, or schedule
activation is authorized by this package.

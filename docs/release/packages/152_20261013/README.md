# Migration 152 production package (A, 2026-10-13)

**Owner authorisation (chat, 2026-10-13):** apply the reviewed migration 152 by the targeted method, after a fresh verified backup and D's pre-apply check. This package does nothing else. It never runs `db push`, never uses MCP `apply_migration`, and does not touch 121/125/126.

## Identity
- **File:** `frozen/migrations/20261013000000_marketplace_safety_enforcement.sql`.
  - Blob `4222b3e4cf6e48084046919806ccd8d175c95c75`, identical at RC5 `1e491ac4`, gate merge `6f982f36` and `3091d30c`.
  - sha256 `170e5bb3…7ccc5`, md5 `4d4765ef5e4fe50719553fd46229451f`, 45,675 B.
  - D reviewed `6a02519d` (blob `e6f4db76`). The only difference is two header comment lines (D F-152-3).
- **Rollback:** `frozen/rollbacks/…_rollback.sql`.
  - Blob `40f564a57015845200d0d9da7fa28d9a843ff13d`, md5 `275b5b65…`, 28,640 B.
- **Runner:** `pkg.py`, copied from `../150_151_20261005/pkg.py` (sha256 `0c8f713c…`, D PASS `887cb49a`).
  - Changes: the MIG entry, `LEDGER_KEYS`, the `ledger_{n}` lookup, explicit UTF-8 I/O, and an empty `FUNCS`.
  - Same transport: one Management API `database/query` POST carrying the file bytes, then the ledger INSERT `(version, name, statements, created_by)` with `statements = ARRAY[raw file]`.
- **Requests** (`MODE=DRY`, `rehearsal/out/`):

  | Request | Size | sha256 |
  |---|---|---|
  | apply | 91,561 B | `ffc020a0ec3bea3e22bec82c7515e9c16c151892674fde5f8ec75b6d28db560c` |
  | ledger-only | 45,884 B | `ca6f6f17…` |
  | rollback | 29,292 B | `ea3774b4…` |

## Transaction shape
- The file carries its own `BEGIN; SET LOCAL lock_timeout = '3s'; … COMMIT;`. The appended ledger INSERT therefore runs as a second implicit transaction.
- If the file fails, nothing commits.
- The only possible split is the objects present with no ledger row. `apply 152 --ledger-only` resumes that case, and only with D's agreement.

## Expected states
- `expected/pre152.txt`: production, read-only, 2026-10-13 21:31:56Z. It equals D's 21:12:57Z prestate.
- `expected/post152.txt`: `pre152` plus the deltas observed on the local rehearsal. Those deltas equal `rehearsal/predictions_local.txt`, registered before the first apply.
- `state.sql` pins `md5(pg_get_functiondef)` and `md5(prosrc)` for every touched or guarded function.

## Local rehearsal (clones of `pkg151_rehears`, ledger 164)
`rehearsal/run_local_20261013.log`. Each step's expected exit code was registered before the run:

| Step | Exit code |
|---|---|
| check pre | 0 |
| apply | 0 |
| re-apply (negative) | STOP 3 |
| ledger-only with the row present (negative) | STOP 3 |
| rollback (back to the exact pre-state) | 0 |
| rollback again (negative) | STOP 3 |
| apply | 0 |
| split, then ledger-only resume | 0 |
| final check | 0 |

## Order
1. Fresh logical backup + local restore test (private evidence, SSD; not in this repo).
2. D confirms C3 in writing.
3. `MODE=PROD CONFIRM_REF=hqycwntpfoztoinemqns TRANSPORT=http python3 pkg.py probe` → `same_txn=true`.
4. `… pkg.py apply 152`. Exit codes: 3 means nothing was sent; 5 means do not resend (read the state); 4 means STOP.
5. D's independent post-apply read and verdict.
6. Console deploy, a separate step.

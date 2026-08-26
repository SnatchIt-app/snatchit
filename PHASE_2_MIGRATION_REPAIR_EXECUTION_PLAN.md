# Production Migration-Ledger Repair — Execution Plan (Scheme B)

> ⛔ **PROPOSED ONLY. NOT EXECUTED.** No command here has been run against production.
> Requires explicit owner authorization. Supabase auto-deploy must remain **OFF**.

## Preconditions (all must hold at execution time)
1. Owner has confirmed **"Deploy to production on push" = OFF** (dashboard; screenshot for the record).
2. The Scheme B PR is **merged to main**.
3. CI `db` job is **green on main**: fresh replay applies all 84 migrations, 0 skipped, Gate-2 parity passes.
4. Pinned CLI **2.115.0** is the client used for the repair.
5. This plan re-verified against a fresh read-only ledger snapshot immediately before execution.
6. **MANDATORY — full ledger backup taken first.** The 37 rows marked `reverted` carry populated
   `statements`/`name` content (~107 KB across 54 statements). `migration repair --status applied`
   restores a *version row*, not that content, so the backup is the only way back to byte-identical
   rows. Capture it as a file before command #1:
   Take a **machine-restorable table snapshot**, not a text dump. `statements` is a `text[]` of
   dollar-quoted SQL that is lossy to re-parse from aligned `psql` output, and `created_by` is
   populated on 36 of the 37 rows being deleted — a 3-column `select` cannot deliver the
   byte-identical restoration this precondition promises.
   ```sql
   -- authoritative, restorable backup — run BEFORE any repair command
   create table supabase_migrations.schema_migrations_pre_schemeB as
     select * from supabase_migrations.schema_migrations;

   -- verify it captured everything (expect 79, and all six columns present)
   select count(*) from supabase_migrations.schema_migrations_pre_schemeB;   -- expect 79
   ```
   Keep a secondary off-database copy as well:
   ```sql
   select * from supabase_migrations.schema_migrations order by version;  -- save full output
   ```

## BEFORE — production ledger snapshot (read-only, captured this session)
- **79 rows**: 39 numeric (`001`–`039`) + 40 timestamps.
- Letter-suffixed versions in production: **0** (they never existed there).
- Repository after Scheme B: **84 files**.

## Repair operations
**Phase A — mark the repository's versions applied (42 commands).** These are versions the repo has that the ledger lacks (including `000`, the normalized `0230`/`0231`, the `05xx` family, and `069`/`070`).

```bash
supabase migration repair --status applied 000
supabase migration repair --status applied 0230
supabase migration repair --status applied 0231
supabase migration repair --status applied 040
supabase migration repair --status applied 041
supabase migration repair --status applied 042
supabase migration repair --status applied 044
supabase migration repair --status applied 045
supabase migration repair --status applied 046
supabase migration repair --status applied 047
supabase migration repair --status applied 048
supabase migration repair --status applied 049
supabase migration repair --status applied 050
supabase migration repair --status applied 051
supabase migration repair --status applied 052
supabase migration repair --status applied 053
supabase migration repair --status applied 054
supabase migration repair --status applied 0550
supabase migration repair --status applied 0551
supabase migration repair --status applied 0552
supabase migration repair --status applied 0553
supabase migration repair --status applied 0561
supabase migration repair --status applied 0562
supabase migration repair --status applied 0563
supabase migration repair --status applied 0564
supabase migration repair --status applied 057
supabase migration repair --status applied 058
supabase migration repair --status applied 0590
supabase migration repair --status applied 0591
supabase migration repair --status applied 0600
supabase migration repair --status applied 0601
supabase migration repair --status applied 061
supabase migration repair --status applied 062
supabase migration repair --status applied 063
supabase migration repair --status applied 064
supabase migration repair --status applied 065
supabase migration repair --status applied 0660
supabase migration repair --status applied 0661
supabase migration repair --status applied 067
supabase migration repair --status applied 068
supabase migration repair --status applied 069
supabase migration repair --status applied 070
```

**Phase B — mark the superseded versions reverted (37 commands).** 36 timestamp versions that duplicate the numeric ones, plus `023` which is now `0230`.

```bash
supabase migration repair --status reverted 023
supabase migration repair --status reverted 20260729185526
supabase migration repair --status reverted 20260730190205
supabase migration repair --status reverted 20260730195351
supabase migration repair --status reverted 20260730222142
supabase migration repair --status reverted 20260804024456
supabase migration repair --status reverted 20260804185549
supabase migration repair --status reverted 20260804235048
supabase migration repair --status reverted 20260805002810
supabase migration repair --status reverted 20260805025025
supabase migration repair --status reverted 20260805025438
supabase migration repair --status reverted 20260805033055
supabase migration repair --status reverted 20260805034758
supabase migration repair --status reverted 20260805035221
supabase migration repair --status reverted 20260805035353
supabase migration repair --status reverted 20260805040743
supabase migration repair --status reverted 20260805040826
supabase migration repair --status reverted 20260805040935
supabase migration repair --status reverted 20260805041030
supabase migration repair --status reverted 20260805044106
supabase migration repair --status reverted 20260805044159
supabase migration repair --status reverted 20260805044821
supabase migration repair --status reverted 20260805044913
supabase migration repair --status reverted 20260805045314
supabase migration repair --status reverted 20260805045437
supabase migration repair --status reverted 20260805045525
supabase migration repair --status reverted 20260806002500
supabase migration repair --status reverted 20260806003406
supabase migration repair --status reverted 20260806004256
supabase migration repair --status reverted 20260806004545
supabase migration repair --status reverted 20260806005147
supabase migration repair --status reverted 20260806005349
supabase migration repair --status reverted 20260806010150
supabase migration repair --status reverted 20260806010900
supabase migration repair --status reverted 20260824161047
supabase migration repair --status reverted 20260824161131
supabase migration repair --status reverted 20260824161202
```

Run **Phase A first, then Phase B** — the ledger is never empty of a given migration's record at any point.

### ⛔ Fail-fast and the mandatory checkpoint between phases
The command lists above are **not** to be pasted as a blind block. Run them under fail-fast, and
**assert the intermediate row count before starting Phase B**:

```bash
set -euo pipefail          # abort on the FIRST failing repair command
# ... Phase A commands ...

# CHECKPOINT — Phase A must have added exactly 42 rows: 79 + 42 = 121
n=$(psql "$DB_URL" -tAc "select count(*) from supabase_migrations.schema_migrations;" | tr -d ' ')
if [ "$n" != "121" ]; then
  echo "STOP: expected 121 rows after Phase A, found $n. Do NOT run Phase B."; exit 1
fi

# ... Phase B commands, only if the checkpoint passed ...
```

**Why this is not optional.** Without fail-fast plus the checkpoint, the worst realistic interleaving
is: Phase A aborts partway unnoticed, Phase B runs anyway, and ~37 already-applied migrations are left
looking **pending**. A later `supabase db push` would then **re-execute them against live production**
— including `040_web_accounts_foundation`, `045_payments_stripe_livemode`, and
`070_reconcile_rls_policies_and_triggers`. That is the single most dangerous outcome in this plan, and
it is prevented by two lines.

## AFTER — expected state
- Ledger rows: **84 = 84**, exactly one per repository migration file.
- `supabase migration list` → repo and remote columns aligned 1:1, no orphans.
- `supabase db push --dry-run` → **zero pending migrations**.

## Verification (run all three)
```bash
supabase migration list                       # expect 1:1, no orphan rows
supabase db push --dry-run                    # expect: no pending migrations
psql "$DB_URL" -c "select count(*) from supabase_migrations.schema_migrations;"   # expect 84
```

## Rollback (exact inverse)
Reverse Phase B first, then Phase A:
```bash
# undo Phase B
supabase migration repair --status applied 023
supabase migration repair --status applied 20260729185526
supabase migration repair --status applied 20260730190205
supabase migration repair --status applied 20260730195351
supabase migration repair --status applied 20260730222142
supabase migration repair --status applied 20260804024456
supabase migration repair --status applied 20260804185549
supabase migration repair --status applied 20260804235048
supabase migration repair --status applied 20260805002810
supabase migration repair --status applied 20260805025025
supabase migration repair --status applied 20260805025438
supabase migration repair --status applied 20260805033055
supabase migration repair --status applied 20260805034758
supabase migration repair --status applied 20260805035221
supabase migration repair --status applied 20260805035353
supabase migration repair --status applied 20260805040743
supabase migration repair --status applied 20260805040826
supabase migration repair --status applied 20260805040935
supabase migration repair --status applied 20260805041030
supabase migration repair --status applied 20260805044106
supabase migration repair --status applied 20260805044159
supabase migration repair --status applied 20260805044821
supabase migration repair --status applied 20260805044913
supabase migration repair --status applied 20260805045314
supabase migration repair --status applied 20260805045437
supabase migration repair --status applied 20260805045525
supabase migration repair --status applied 20260806002500
supabase migration repair --status applied 20260806003406
supabase migration repair --status applied 20260806004256
supabase migration repair --status applied 20260806004545
supabase migration repair --status applied 20260806005147
supabase migration repair --status applied 20260806005349
supabase migration repair --status applied 20260806010150
supabase migration repair --status applied 20260806010900
supabase migration repair --status applied 20260824161047
supabase migration repair --status applied 20260824161131
supabase migration repair --status applied 20260824161202

# undo Phase A
supabase migration repair --status reverted 000
supabase migration repair --status reverted 0230
supabase migration repair --status reverted 0231
supabase migration repair --status reverted 040
supabase migration repair --status reverted 041
supabase migration repair --status reverted 042
supabase migration repair --status reverted 044
supabase migration repair --status reverted 045
supabase migration repair --status reverted 046
supabase migration repair --status reverted 047
supabase migration repair --status reverted 048
supabase migration repair --status reverted 049
supabase migration repair --status reverted 050
supabase migration repair --status reverted 051
supabase migration repair --status reverted 052
supabase migration repair --status reverted 053
supabase migration repair --status reverted 054
supabase migration repair --status reverted 0550
supabase migration repair --status reverted 0551
supabase migration repair --status reverted 0552
supabase migration repair --status reverted 0553
supabase migration repair --status reverted 0561
supabase migration repair --status reverted 0562
supabase migration repair --status reverted 0563
supabase migration repair --status reverted 0564
supabase migration repair --status reverted 057
supabase migration repair --status reverted 058
supabase migration repair --status reverted 0590
supabase migration repair --status reverted 0591
supabase migration repair --status reverted 0600
supabase migration repair --status reverted 0601
supabase migration repair --status reverted 061
supabase migration repair --status reverted 062
supabase migration repair --status reverted 063
supabase migration repair --status reverted 064
supabase migration repair --status reverted 065
supabase migration repair --status reverted 0660
supabase migration repair --status reverted 0661
supabase migration repair --status reverted 067
supabase migration repair --status reverted 068
supabase migration repair --status reverted 069
supabase migration repair --status reverted 070
```
This restores the original 79-row **version set** exactly.

> ⚠️ **Correction — rollback is NOT lossless at row level.** The 37 rows being reverted carry
> populated `statements`/`name` columns (~107 KB / 54 statements; largest: `055_transfer_state_guard`
> 11,571 B, `058_notification_producers` 8,962 B, `065_dispute_resolution` 7,963 B). Those versions
> have **no corresponding local file**, so `--status applied` cannot regenerate their content — it
> recreates the version row only. **Restoring byte-identical rows requires the pre-repair backup
> from precondition 6.** This is archival metadata loss only: the repair is ledger-only, so the
> production **schema and all business data are untouched** either way.

> **Rollback precondition (M-5).** The inverse list is unconditional, and `--status reverted` performs a
> DELETE. It is only correct while the BEFORE snapshot is exactly the 79 rows captured in precondition 6.
> **Re-verify the live ledger matches that snapshot immediately before rolling back**; if it has drifted,
> stop and reconcile by hand rather than running the inverse list.

## Partial-failure protocol
1. **STOP** at the first unexpected output. Do not continue the list.
2. Record the index of the last successful command.
3. Snapshot the current ledger: `select version from supabase_migrations.schema_migrations order by version;`
4. Diff it against BEFORE (79 rows) and AFTER (84 rows) to establish the mixed state.
5. Apply the inverse of **only the commands that completed**, in reverse order.
6. Re-verify the 79-row baseline before any retry.
7. Escalate to the owner with the captured state. Do not improvise.

## Risk notes
- Ledger-only: `supabase_migrations.schema_migrations` bookkeeping. **No table, function, policy, trigger, or row of business data is touched.**
- Production schema is unchanged by this operation, so the marketplace, payments, transfers, and payouts are unaffected.
- The window carries no user-visible impact; it does not require downtime.

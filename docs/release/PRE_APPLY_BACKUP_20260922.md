# Pre-apply backup and recovery runbook — refund/payout safety release (A, 2026-09-22)

**Status: BACKUP TAKEN AND RESTORE-TESTED (2026-09-22 23:27–23:29Z).** Owner's instruction: fresh pre-apply logical
backup, one consistent snapshot, explicit consistency assessment against the older physical backup, a workable
recovery procedure and the remaining window. **This is not a complete current backup of the platform** (§5).

## 1. Artefacts
| Artefact | Time (UTC) | Covers | Verified by |
|---|---|---|---|
| Supabase daily **physical** backup | 2026-09-22 13:45:46Z, status COMPLETED (Management API read) | whole database incl. managed schemas auth, storage, vault, net, cron, extensions, roles | API status only — no restore test possible (no second project; none authorised) |
| **Application logical dump** `full_20260922T232735Z.dump` (pg_dump 17.11, custom format, one invocation with `--snapshot`) | snapshot `00000006-0001E831-1`, exported 23:27:37.46Z | schema + data of `public, ops, kernel, notify, market, venue, catalog, supabase_migrations` — 4,431,823 bytes, 2,443 TOC entries, 0 pg_dump errors | sha256 `28375f85a08074eb6f649948e81b051bbb3e83f27f8f4725a870a918210ffb2a`; `schema_…sql` `10892b08…`; `SHA256SUMS_20260922T232735Z_final.txt` (30 entries, all OK) `189eba16…`; **local restore test §4 PASS** |
| `schema_20260922T232735Z.sql` | derived from the dump (`pg_restore --schema-only`) — 120 `CREATE TABLE`, 457 `CREATE FUNCTION` | same schemas, human-readable | sha256 |
| Same-snapshot side exports | snapshot `00000006-0001E831-1` | row-count inventory (120 tables, 52,699 rows), function-hash inventory (457), ledger listing (135), `cron.job` (24 jobs), Vault secret **names** + created_at (2: `project_url`, `service_role_key`), `auth.users` ids + created_at (19), auth users / identities changed since 12:00Z (**0 / 0 rows**), storage object metadata (178) + buckets (5), roles inventory (attributes + memberships; Supabase exposes no role passwords) | sha256 |
Location: `~/.snatchit-backups/20260922/` (mode 700, files 600; home folder is not iCloud-synced — Desktop/Documents sync
off, no CloudStorage providers; `failed_attempts/` holds the three aborted runs' logs, none of which dumped anything).
The DB password file used for the dump was securely deleted after the restore test.
Tooling: CLI 2.115.0's `db dump` wraps pg_dump inside Docker (absent here); pg_dump/psql 17.11 (Homebrew) used directly
against PostgreSQL 17.6 (`server_version_num` 170006) — newer client, supported direction. Connection: session pooler
(`aws-0-us-west-2.pooler.supabase.com:5432`, SSL) because the direct host refused TCP after three rejected logins
(wrong password entered first; lockout is temporary and affects only this machine's direct path).

## 2. Snapshot consistency
A control session opened `REPEATABLE READ READ ONLY`, exported its snapshot; `pg_dump --snapshot=<id>` and every side
export ran inside that same snapshot (`ledger_at_snapshot_end` read in the control transaction = 135 = inventory).
LIVE reads outside the snapshot: ledger 135 at 23:27:36Z (before) and 23:29:20Z (after) — labelled separately; the
only moving table is `ops.job_run` (~2.4 rows/min from the detector crons, D), so any live count may run ahead of the
snapshot. Restore comparison asserts **exact equality against the snapshot inventory**, never against live production.

## 3. Consistency between the two artefacts (measured 23:17Z by A; independently by D; re-measured in the snapshot)
- Dependency surface: ~90 foreign keys from the dumped schemas reference `auth.users`; none reference `storage`
  (storage paths are text). `auth.users` is the single hinge between the halves.
- Skew since the physical backup: auth users 19 total, **0 created / 0 updated / 0 signed in** after 13:45:46Z (newest
  2026-09-20 02:16Z); identities 0 changed; MFA factors 0 created (D); storage objects 178, **0** after (newest
  2026-09-20 02:28Z); the delta exports since 12:00Z are empty. Customer-facing application tables also static since
  13:45Z (listings 113, payments 57, transfers 36, profiles 19, bids 98, notifications 7 — D). → today no application
  row can reference a user or object the physical backup lacks. **Contingent, not structural:** re-measure the five
  managed counts at the end of the apply; a non-zero result restates the combined story.
- **The one real gap — Vault.** `project_url` was created 23:08:30Z, after the physical backup, and Vault is outside the
  logical dump. A physical restore yields a database **without** `project_url`: 133 §0 refuses to apply, and if 133 is
  already applied every http cron and notify trigger goes silent. §6 step 2 exists for this (D's finding).

## 4. Restore test (local vanilla PostgreSQL 17.11 + harness shims; never production) — PASS, 23:29:33–23:29:38Z
- Checksums: 19/20 OK on the first pass; the miss was `backup_…log`, still being written when the sums were taken.
  **Re-verified, not explained away:** the sums were regenerated after the log closed
  (`SHA256SUMS_20260922T232735Z_final.txt`, 30 entries) and re-checked — all 30 matched.
- Bootstrap shims rc=0; `pg_restore` of the full dump: **1 error — `schema "public" already exists`** (pg_dump ≥15 emits
  `CREATE SCHEMA public`; the target already has it; benign). rc=1 is that error only.
- **Row counts: 120/120 tables identical to the snapshot inventory, 52,699 = 52,699 rows.** **Function definitions:
  457/457 identical** (md5 of `pg_get_functiondef`). Ledger rows 135. Public census 27|71|37|27 = production pre-apply.
- Proves the dump is complete, internally consistent and loadable, with FKs to `auth.users` satisfied by the exported
  ids. Does **not** prove the platform is reconstructible — the target has none of the managed pieces (auth, storage,
  vault, net, cron, extensions are shims). The restore database was dropped after the comparison (it held production rows).

## 5. What this is and is not
Two artefacts ~9.7 h apart whose overlap is consistent because the managed half was idle, plus a manual Vault rebuild
that neither carries. **Not a complete current backup.** Adequate for: (a) undoing this release (rollbacks);
(b) restoring the application schemas/data as of 23:27:37Z over intact managed schemas; (c) full-loss recovery to
13:45Z + 23:27Z with the §6 steps and the §8 windows.

## 6. Recovery procedure (tiered)
**Tier A — release failure, data intact:** run `supabase/rollbacks/*` for the applied files in reverse manifest order
(forward/backward battery PASS; identity after full rollback returns exactly to production's pre-apply bodies). No
backup involved. Rolling back code never reverses payouts already made.
**Tier B — application schemas damaged, managed schemas intact:** as `postgres` (direct host or session pooler),
`pg_restore --clean --if-exists -d postgres full_20260922T232735Z.dump` (drops and reloads the eight schemas; expect the
benign `public` schema notice), re-apply manifest files applied after 23:27:37Z in order, then §7.
**Tier C — whole database lost:** 1. Supabase Dashboard → Database → Backups → restore the 13:45:46Z physical backup
(the only supported path for auth, storage, vault, extensions, roles). 2. **Re-create Vault secret `project_url` =
`https://hqycwntpfoztoinemqns.supabase.co`** (`select vault.create_secret('https://hqycwntpfoztoinemqns.supabase.co',
'project_url')`) and assert exact equality (`select decrypted_secret = 'https://hqycwntpfoztoinemqns.supabase.co' from
vault.decrypted_secrets where name='project_url'` → exactly one row, true). 3. Reload the application schemas from the
logical dump (Tier B command). 4. Reconcile managed deltas from the side exports if non-empty (today: empty):
`delta_auth_users_…csv`, `delta_auth_identities_…csv`, `storage_objects_meta_…csv` (metadata only — file contents live
in object storage and are outside every database backup). 5. Re-apply manifest files applied after 23:27:37Z.
6. §7 checks.

## 7. Post-recovery checks
Five managed counts (auth users total/created/updated, identities, storage objects) vs §3; application counts vs
`inventory_rows_…txt` (exact for static tables; `ops.job_run` ≥ inventory); function hashes vs `inventory_functions_…txt`
(pre-apply) or D's post-apply references (if the manifest was re-applied); ledger rows; Vault names = `project_url,
service_role_key`; `net.http_request_queue` sane; cron jobs = the 24 exported.

## 8. Remaining window
Managed schemas: from 13:45:46Z until the next daily physical backup (~13:45Z 2026-09-23) — today measured 0 rows at
risk, by an idle managed half, not by design. Application schemas: from 23:27:37Z onward (the apply writes only seed
rows; live traffic ~1 payment / 30 days). `ops.job_run` telemetry after 23:27:37Z is lost in Tier B/C and not worth
protecting. Vault: rebuilt by hand (§6 step 2); `service_role_key` is re-creatable from the dashboard.

# Production Migration-Ledger Repair — Execution Plan (PROPOSED, owner-gated)

> **Status:** PROPOSED. **Nothing in this document has been executed against production.**
> **Companion to:** `PHASE_2_MIGRATION_HISTORY_RECONCILIATION.md` (§6/§7 + Addenda A/B — the *why*;
> this document is the *how*, command by command).
> **Production project:** `hqycwntpfoztoinemqns` ("Snatch It").
> **Nature of the change:** ledger-only — 41 INSERTs + 36 DELETEs on
> `supabase_migrations.schema_migrations` via `supabase migration repair`. **No DDL. No schema object is
> created, altered, or dropped.** That is safe only because Gate-2 certified the repo chain reproduces the
> production schema object-for-object; if that certification is ever in doubt, STOP and re-certify first.
> **Prepared:** 2026-08-25, PR #5 (`repo/migration-ledger-normalization`).

---

## 1. What this event does

Production's ledger records the `040–068` block as 36 **timestamp** versions while the repo files are
numeric; five repo files (`000, 0231, 0661, 069, 070`) have no ledger row at all although their objects
exist on production. Until repaired, any ungated `supabase db push` would re-apply `040–068` to
production. This event rewrites **bookkeeping only** so ledger ↔ repo become 1:1:

- **41 × `migration repair --status applied`** — insert the numeric rows (names + statements recorded
  from the repo files).
- **36 × `migration repair --status reverted`** — delete the superseded timestamp rows.
- `001–039` and the 4 website-form timestamp rows are **untouched**.

Order is **all applies first, then all reverts**: during the window a migration may briefly have both its
timestamp row and its numeric row (harmless — distinct version strings, schema untouched), but no
migration is ever momentarily unrecorded.

## 2. CLI version — MANDATORY

**Use Supabase CLI ≥ 2.115.0 (the TS rewrite — the version pinned in CI) for every command and every
verification step in this plan. The Go CLI 2.75.0 currently on the dev machine MUST NOT be used.**

Why (source-verified, both generations — see Reconciliation Addendum B): 2.75.0 enumerates local
migrations in raw filename order and never re-sorts by version. The normalized 4-digit versions sort
*after* their 3-digit parents as versions but *before* them as filenames, so under 2.75.0:

- `supabase migration list` / `db push --dry-run` **hard-fail with `ErrMissingLocal`** on
  `023 055 059 060 066` after the repair, and the CLI prints a suggestion to run
  `supabase migration repair --status reverted 023 055 059 060 066`.
  **NEVER run that suggested command** — it would mark five applied migrations unapplied and a later
  push would re-run their DDL on production.
- A fresh local replay silently applies `0553` before `055` and `0601` before `060`, ending with two
  stale function bodies (schema drift with a green exit code).

Check before starting: `supabase --version` → must print `2.115.0` or later.

## 3. Preconditions (ALL must hold before the first command)

| # | Precondition | Evidence required |
|---|---|---|
| P1 | **Supabase "Deploy to production" toggle is OFF**, confirmed by the owner **with a screenshot** taken the same day, attached to the run log. | Screenshot |
| P2 | **PR #5 merged to `main`** (11 renames + guard allowlist + CLI pin + this plan). | Merge SHA recorded |
| P3 | **CI `db` job GREEN on PR #5** — the fresh-replay proof that the renamed chain applies 000→070 cleanly under the pinned CLI. Do not proceed on a red or skipped db job. | CI run URL |
| P4 | Operator terminal: checkout of `main` at/after the P2 SHA (repair resolves each version to its local file via glob `<version>_*.sql`); `supabase link --project-ref hqycwntpfoztoinemqns`; CLI per §2. | `git rev-parse HEAD`, `supabase --version` |
| P5 | **T0 full ledger export** (rollback source of truth, incl. the `statements` column which §4's snapshot does not carry): run in the SQL editor and save the JSON/CSV output locally:<br>`SELECT version, name, statements FROM supabase_migrations.schema_migrations ORDER BY version;` | Saved file, row count 79 |
| P6 | Single operator, one sitting, no concurrent `db push`/deploy of any kind; Agent F/G review of this plan done. | Sign-offs |
| P7 | **Owner authorization** (see §10). | Explicit YES |

## 4. BEFORE state — production ledger, 79 rows (captured read-only 2026-08-25)

This is the rollback baseline. If at any point the ledger should be restored, it must equal exactly this
row set (P5's export additionally restores `statements`).

```
version         name
001             profile_additions
002             transfers
003             payment_integrity
004             input_bounds
005             rate_limits
006             payout_release
007             transfer_expiry
008             auto_release
009             dispute
010             ensure_transfer
011             v1_transfer_enhancements
012             seller_risk
013             can_create_listing
014             frequent_cron_schedules
015             preferred_neighborhoods
016             fix_auto_release_payout
017             stripe_onboarding_complete
018             reserve_buy_now_self_purchase_guard
019             anonymized_sentinel_user
020             delete_account_cleanup_rpc
021             rate_limits_fail_closed
022             seller_fee_column
023             user_reports_and_blocks
024             disputes
025             stripe_webhook_events
026             stripe_customer_id
027             drop_buyer_dispute_transfer_overload
028             cancel_listing_rpc
029             profile_trust_stats
030             profile_trust_stats
031             profile_trust_stats_dispute_fix
032             pre_testflight_blocker_fixes
033             marketplace_expansion
034             transfer_notifications
035             bid_notifications
036             listing_requires_payout_setup
037             drop_legacy_listing_insert_policies
038             listing_requires_verified_phone
039             risk_based_payout
20260714190445  investor_leads_website_form
20260729185526  web_accounts_foundation
20260730190205  profiles_column_grants
20260730195351  profiles_get_my_profile_rpc
20260730212326  ambassador_applications_website_form
20260730212406  ambassador_applications_fix_search_path
20260730222142  044_realtime_publication_bids_listings
20260731224653  venue_partnership_inquiries_website_form
20260804024456  stripe_connect_archive_table
20260804185549  payments_stripe_livemode
20260804235048  046_guard_bid_count_columns
20260805002810  047_block_activity_on_cancelled_listings
20260805025025  048_auction_media_owner_delete
20260805025438  049_proof_docs_owner_delete_unreferenced
20260805033055  051_storage_scope_public_read
20260805034758  054_fix_notify_outbid_aborts_bids
20260805035221  052_profiles_anon_column_restriction
20260805035353  053_storage_scope_write_policies
20260805040743  055_transfer_state_guard
20260805040826  055b_transfer_guard_bypass_for_remaining_writers
20260805040935  055c_revoke_anon_public_on_listing_rpcs
20260805041030  055d_fix_mark_transfer_sent_overload_ambiguity
20260805044106  057_notifications_dedupe_and_enqueue_helper
20260805044159  058_notification_producers
20260805044821  059_strict_auth_on_listing_checkout_rpcs
20260805044913  059b_strict_auth_ensure_transfer_exists
20260805045314  056a_transfer_writer_rpcs
20260805045437  060_auth_password_change_notifications
20260805045525  060b_fix_sweep_query_destination
20260806002500  061_ensure_transfer_exists_requires_verified_payment
20260806003406  056b_remove_transfer_guard_service_role_exemption
20260806004256  056c_scope_transfer_guard_bypass_to_statement
20260806004545  056d_record_transfer_payout_refuses_disputed
20260806005147  062_profiles_authenticated_column_restriction
20260806005349  063_revoke_unsafe_execute_and_truncate
20260806010150  064_webhook_event_claim_lease
20260806010900  065_dispute_resolution
20260824161047  066_pin_search_path_definer_functions
20260824161131  067_revoke_execute_internal_functions
20260824161202  068_profiles_authenticated_select_public_safe_only
```

(39 numeric rows `001–039` + 40 timestamp rows. No `000`, no `043`, no letter version, no `069`/`070`.)

## 5. The commands (run in this exact order, one at a time)

**Expected output of every command:** the CLI connects, then prints
`Repaired migration history: [<version>] => applied` (or `=> reverted`) and exits 0, typically followed
by the hint `Run supabase migration list to show the updated migration history.`
**Anything else — any error, any unexpected version echoed, a non-zero exit — is a STOP (see §9).**
Tick each command off on a printed copy as it completes.

### 5a. Phase A — 41 × `--status applied` (additive inserts; run ALL of these before any 5b command)

```bash
# local-only rows (objects already on prod — Gate-2 verified)
supabase migration repair --status applied 000
supabase migration repair --status applied 0231
supabase migration repair --status applied 0661
supabase migration repair --status applied 069
supabase migration repair --status applied 070
# numeric equivalents of the 36 timestamp rows (040–068 block)
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
supabase migration repair --status applied 055
supabase migration repair --status applied 0551
supabase migration repair --status applied 0552
supabase migration repair --status applied 0553
supabase migration repair --status applied 0561
supabase migration repair --status applied 0562
supabase migration repair --status applied 0563
supabase migration repair --status applied 0564
supabase migration repair --status applied 057
supabase migration repair --status applied 058
supabase migration repair --status applied 059
supabase migration repair --status applied 0591
supabase migration repair --status applied 060
supabase migration repair --status applied 0601
supabase migration repair --status applied 061
supabase migration repair --status applied 062
supabase migration repair --status applied 063
supabase migration repair --status applied 064
supabase migration repair --status applied 065
supabase migration repair --status applied 066
supabase migration repair --status applied 067
supabase migration repair --status applied 068
```

**Checkpoint after Phase A (read-only SQL):**
`SELECT count(*) FROM supabase_migrations.schema_migrations;` → **120** (79 + 41). If not 120, STOP (§9).

### 5b. Phase B — 36 × `--status reverted` (delete the superseded timestamp rows)

*Do NOT revert the 4 website-form timestamps (`20260714190445`, `20260730212326`, `20260730212406`,
`20260731224653`).*

```bash
supabase migration repair --status reverted 20260729185526   # was 040
supabase migration repair --status reverted 20260730190205   # was 041
supabase migration repair --status reverted 20260730195351   # was 042 (get_my_profile)
supabase migration repair --status reverted 20260730222142   # was 050 (mislabeled 044_realtime)
supabase migration repair --status reverted 20260804024456   # was 044 (stripe_connect_archive)
supabase migration repair --status reverted 20260804185549   # was 045
supabase migration repair --status reverted 20260804235048   # was 046
supabase migration repair --status reverted 20260805002810   # was 047
supabase migration repair --status reverted 20260805025025   # was 048
supabase migration repair --status reverted 20260805025438   # was 049
supabase migration repair --status reverted 20260805033055   # was 051
supabase migration repair --status reverted 20260805034758   # was 054
supabase migration repair --status reverted 20260805035221   # was 052
supabase migration repair --status reverted 20260805035353   # was 053
supabase migration repair --status reverted 20260805040743   # was 055
supabase migration repair --status reverted 20260805040826   # was 055b -> 0551
supabase migration repair --status reverted 20260805040935   # was 055c -> 0552
supabase migration repair --status reverted 20260805041030   # was 055d -> 0553
supabase migration repair --status reverted 20260805044106   # was 057
supabase migration repair --status reverted 20260805044159   # was 058
supabase migration repair --status reverted 20260805044821   # was 059
supabase migration repair --status reverted 20260805044913   # was 059b -> 0591
supabase migration repair --status reverted 20260805045314   # was 056a -> 0561
supabase migration repair --status reverted 20260805045437   # was 060
supabase migration repair --status reverted 20260805045525   # was 060b -> 0601
supabase migration repair --status reverted 20260806002500   # was 061
supabase migration repair --status reverted 20260806003406   # was 056b -> 0562
supabase migration repair --status reverted 20260806004256   # was 056c -> 0563
supabase migration repair --status reverted 20260806004545   # was 056d -> 0564
supabase migration repair --status reverted 20260806005147   # was 062
supabase migration repair --status reverted 20260806005349   # was 063
supabase migration repair --status reverted 20260806010150   # was 064
supabase migration repair --status reverted 20260806010900   # was 065
supabase migration repair --status reverted 20260824161047   # was 066
supabase migration repair --status reverted 20260824161131   # was 067
supabase migration repair --status reverted 20260824161202   # was 068
```

## 6. Expected AFTER state

**84 rows — one per repo migration file.** Version set, sorted exactly as `ORDER BY version` returns it
(lexicographic on the text column):

```
000, 001, 002, …, 022, 023, 0231, 024, 025, …, 039,
040, 041, 042, 044, 045, 046, 047, 048, 049,
050, 051, 052, 053, 054,
055, 0551, 0552, 0553, 0561, 0562, 0563, 0564,
057, 058, 059, 0591, 060, 0601,
061, 062, 063, 064, 065, 066, 0661, 067, 068, 069, 070,
20260714190445, 20260730212326, 20260730212406, 20260731224653
```

No `043`. No letter version. No timestamp row other than the 4 website forms. The schema itself is
byte-for-byte unchanged.

## 7. Verification (all must pass before the window closes)

1. `SELECT count(*) FROM supabase_migrations.schema_migrations;` → **84**.
2. Spot-checks (read-only SQL): `version = '043'` → 0 rows; `'20260729185526'`, `'20260730222142'`,
   `'20260824161202'` → gone; `'000'`, `'0231'`, `'040'`, `'050'`, `'068'`, `'070'` → present.
3. `supabase migration list --linked` → every row shows Local **and** Remote populated with the same
   version — **zero local-only, zero remote-only** entries.
4. `supabase db push --dry-run` → **"Remote database is up to date."** — zero pending.
   **If it lists anything as pending, STOP — do not push.** A version was mistyped or skipped.
5. Re-run the CI `db` job on `main` (fresh-replay gate) → green (it does not touch prod; it re-proves the
   chain).
6. Only after 1–5: open **PR #5b** (delete the guard allowlist), and only after that authorize any
   Phase-2 `071_*` work. Auto-deploy stays OFF permanently; applies go through the gated path only.

## 8. Inverse (full rollback to the §4 BEFORE state)

Ledger-only, symmetric. Run only per §9, or on owner instruction.

**8a. Delete the 41 inserted numeric rows** (repair `--status reverted` needs no local file — it is a
ledger DELETE):

```bash
supabase migration repair --status reverted 000 0231 0661 069 070 \
  040 041 042 044 045 046 047 048 049 050 051 052 053 054 \
  055 0551 0552 0553 0561 0562 0563 0564 057 058 059 0591 060 0601 \
  061 062 063 064 065 066 067 068
```

(One command, 41 versions — the CLI accepts a list; per-version single commands are equally valid if
preferred for auditability.)

**8b. Re-insert the 36 timestamp rows.** `repair --status applied <version>` requires a local file
matching `supabase/migrations/<version>_*.sql`, and the repo (correctly) has none for the timestamps. Two
mechanical options — prefer (i):

- **(i) Exact restore from the P5 export (preferred — restores `name` AND `statements` byte-identically):**
  from the saved T0 export, INSERT exactly the 36 deleted rows back into
  `supabase_migrations.schema_migrations` (version, name, statements) via the SQL editor. This direct-SQL
  write is sanctioned **only** in this rollback context, **only** with the P5 export as the literal
  source, and **only** for these 36 timestamp versions — never for numeric/letter versions and never as
  part of the forward plan.
- **(ii) CLI-only alternative:** in a scratch checkout, generate stub files
  `supabase/migrations/<version>_<name-from-§4>.sql` (content: a one-line comment) for the 36 timestamps,
  then run `supabase migration repair --status applied <version>` for each. Caveat: the re-inserted rows'
  `statements` column then records the stub, not the original content — bookkeeping-only divergence
  (`db push` compares versions, not statements), but (i) avoids it.

**8c. Verify rollback:** `SELECT version, name … ORDER BY version;` equals §4 exactly (79 rows), and
`supabase migration list --linked` shows the same pre-event mismatch picture (numeric files pending /
timestamps applied). Record everything and escalate before any further attempt.

## 9. Mid-run failure protocol

1. **STOP at the FIRST unexpected output** — any error, any version echoed that differs from the command
   issued, any checkpoint count mismatch. Do not retry, do not continue, do not improvise, do not run
   anything the CLI "suggests".
2. **Record the exact position:** which command number failed, its full output, and the tick-list of
   commands completed so far.
3. **Capture the current ledger:** `SELECT version, name FROM supabase_migrations.schema_migrations
   ORDER BY version;` → save.
4. **Run the inverse of the COMPLETED commands only** (nothing for the failed/unrun ones), in reverse
   order: for each completed Phase-B revert, re-insert per §8b; for each completed Phase-A apply,
   `supabase migration repair --status reverted <version>`.
5. **Verify** the ledger equals the §4 BEFORE state (79 rows, exact match).
6. **Escalate** to the owner + Agent F/G with the §9.2/§9.3 records. The event may only be re-attempted
   with a fresh authorization under §10.
7. Throughout: schema and data are never at risk — every command here is bookkeeping. The one absolute
   prohibition: **no `db push` (without `--dry-run`) while the ledger is in any intermediate state.**

## 10. Owner authorization

> **AUTHORIZE PRODUCTION MIGRATION LEDGER REPAIR? — requires explicit YES.**

To be answered by the owner, in writing, in the run log, after P1–P6 show evidence. Anything other than
an explicit YES — silence, "probably", "go ahead if you think it's fine" — is a NO. The authorization
covers exactly the §5 command list against project `hqycwntpfoztoinemqns` in one supervised sitting, and
expires when the sitting ends.

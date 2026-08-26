# Phase 2 — Migration-History Reconciliation Plan (repo ↔ production `schema_migrations`)

> **Author:** Agent F (Phase-0 Reproduction / CI Verifier + Migration-History Reconciler)
> **Date:** 2026-08-24 · **Mode:** READ-ONLY on production. Nothing in production was changed.
> **Production project:** `hqycwntpfoztoinemqns` · **Authoritative repo chain:** branch `phase0/lockdown`
> (worktree `/Users/josetascon/snatchit-phase0`, `supabase/migrations/`, 84 files).
> **Evidence read (unchanged):** production `list_migrations` (read-only), `get_advisors` (read-only),
> `PHASE_0_GATE2_SCHEMA_DIFF.md`, `SNATCH_IT_PHASE_0_COMPLETION_REPORT.md`,
> `SNATCH_IT_ENGINEERING_STANDARDS.md` §5/§6, CI workflows (`.github/workflows/ci.yml`, `migrations-guard.yml`).

---

## ⛔ DO-NOT banner (read before any action)

> **DO NOT enable Supabase production auto-deploy ("Deploy to production" from GitHub).**
> With the histories mismatched (repo `NNN_` vs production timestamps for `040–068`), a merge to `main`
> would run `supabase db push` with **no approval gate** and **re-apply 040–068 to production**.
>
> **DO NOT run any `supabase migration repair` command below without (a) explicit owner authorization and
> (b) Agent F / Agent G review.** Every command here is **PROPOSED, not executed.** `migration repair` writes
> to production's `supabase_migrations.schema_migrations` ledger — it is a production write and is outside
> Agent F's read-only mandate.
>
> **Repair edits only the ledger, never schema.** It records/removes *applied* rows; it does **not** run DDL.
> That is safe **only because Gate-2 already proved the production `public` schema is object-for-object
> reproduced by this repo chain.** If that ever stops being true, stop and re-certify Gate-2 first.

---

## 1. What Gate-2 asserts, and the certified object counts

**CI `db` job (`.github/workflows/ci.yml`):** on every PR into `main` (and pushes to non-main branches) it
installs the Supabase CLI and runs `supabase start`, which **applies every file in `supabase/migrations/` in
version order on a brand-new local database.** If any migration errors, `supabase start` exits non-zero and
the job fails. This is the standing fresh-bootstrap gate — it proves the chain *replays cleanly from zero*,
not that it matches production (that was the one-time branch diff below). `supabase db lint` / pgTAP RLS tests
are `TODO(owner)` placeholders, not yet wired.

**`migrations-guard` job:** on any PR touching `supabase/migrations/**`, enforces (1) **immutability** — no
modify/delete/rename of a base-branch migration — and (2) **monotonic, unique, scheme-aware ordering** — a
new `NNN_` must sort after the max existing `NNN_`; a new timestamp after the max timestamp. **This gate will
reject any back-dated version** (see the `043` finding in §4/§11).

**Gate-2 certification (`PHASE_0_GATE2_SCHEMA_DIFF.md`):** a data-less Supabase Pro branch replayed the full
chain and was compared object-by-object to production. Result **PASS** after 6 fixes vendored into source
(`000_baseline`, `033` guarded seed, index-reordering, `066a`, `069`, `070`). Certified clean-replay counts,
**production vs fresh branch:**

| Object class (public) | Production | Fresh branch | Match |
|---|---:|---:|---|
| Tables (BASE) | 27 | 27 | ✅ exact |
| Functions | 68 | 68 | ✅ exact |
| RLS policies | 37 | 37 | ✅ exact (after `070`) |
| Triggers (non-internal) | 23 | 23 | ✅ exact (after `070`) |
| Storage buckets | 3 (`proof-docs` private) | 3 | ✅ exact |
| Indexes | 90 | 93 | ⚠️ +3 legacy-name dups — functionally equivalent |
| Storage policies | 11 | 17 | ⚠️ repo produces more — buckets are the boundary |
| Cron jobs | 3 | 2 | ⚠️ `032` vault-cron — env-specific |

The three ⚠️ residuals are **accepted, documented, non-blocking** (functionally equivalent; env-specific).
**Schema equivalence is the precondition that makes a ledger-only repair safe.**

---

## 2. Current LOCAL versions (repo `phase0/lockdown`, 84 files)

Version = filename prefix up to the first `_`. **80 `NNN_` files + 4 timestamped website-form files.**

```
NNN_ scheme (80):
000 001 002 003 004 005 006 007 008 009 010 011 012 013 014 015 016 017 018 019
020 021 022 023 023b 024 025 026 027 028 029 030 031 032 033 034 035 036 037 038 039
040 041 042 044 045 046 047 048 049 050 051 052 053 054 055 055b 055c 055d 056a 056b
056c 056d 057 058 059 059b 060 060b 061 062 063 064 065 066 066a 067 068 069 070

timestamp scheme (4 — website forms, unrelated public tables):
20260714190445  20260730212326  20260730212406  20260731224653
```

**Local-scheme notes:**
- **`000_baseline_schema`** and **`023b_set_updated_at_helper`** are `NNN_` files with **no production ledger
  row** (their objects exist on prod via the pre-tracking baseline / other applied migrations).
- **`043` is ABSENT** from `phase0/lockdown` (chain goes `042 → 044`). A file
  `043_profiles_select_column_restriction.sql` exists **only, untracked,** in the `mobile/profile-rpc-compat`
  working tree — see §11 (it is a back-dated-version hazard, not part of the certified chain).
- `066a`, `069`, `070` are the vendored out-of-band objects (Gate-2 fixes #5/#4/#6) — `NNN_`, no prod ledger row.

---

## 3. Current PRODUCTION versions (`schema_migrations`, 79 rows, via read-only `list_migrations`)

**39 `NNN_` rows (`001–039`) + 40 timestamp rows.** Production has **no** `000` or `023b` row (baseline
predates migration tracking), and **no** `069`/`070`/`066a` row (those objects were applied out-of-band).

```
NNN_ scheme (39):  001 … 039   (all present, no gaps)
timestamp scheme (40): 20260714190445 … 20260824161202
```

The **timestamp rows carry name-labels that DO NOT track the repo's `NNN_` numbering** — some embed a *stale*
`NNN_` that differs from the repo's current number. This is the core hazard: the label is cosmetic; only the
**version string** governs `db push`.

---

## 4. Correspondence table — LOCAL ↔ PRODUCTION (every row, every mismatch)

### 4a. `001–039` — aligned scheme (`NNN_` both sides), no repair needed

All of `001–039` exist as `NNN_` on **both** sides → `db push` already sees them applied. Two label-only notes:

| Version | Repo file (label) | Prod ledger (label) | Note |
|---|---|---|---|
| `029` | `029_public_profiles` | `profile_trust_stats` | **Label mismatch only.** Version present both sides → no re-apply, no repair. Cosmetic history noise (apply-order vs repo-order differed). |
| `030` | `030_profile_trust_stats` | `profile_trust_stats` | Matches. |

### 4b. `040–068` — **scheme mismatch (repo `NNN_` ↔ prod timestamp)** — the block requiring repair

Version string is authoritative. "Prod label" is what the ledger row is *named* (often a stale/scrambled
`NNN_` embedded in a timestamp row). Content mapping verified by reading repo files where the label diverges.

| Repo version (`NNN_`) | Repo file | Prod version (timestamp) | Prod label | Mapping basis |
|---|---|---|---|---|
| `040` | web_accounts_foundation | `20260729185526` | web_accounts_foundation | name |
| `041` | profiles_column_grants | `20260730190205` | profiles_column_grants | name |
| `042` | profiles_select_exposure | `20260730195351` | **profiles_get_my_profile_rpc** | **content-verified** — repo `042` defines `get_my_profile()` (grep); 1:1, label differs |
| `044` | archive_testmode_connect_ids | `20260804024456` | **stripe_connect_archive_table** | **content-verified** — repo `044` header = "stripe_connect_archive table"; 1:1, label differs |
| `045` | payments_stripe_livemode | `20260804185549` | payments_stripe_livemode | name |
| `046` | guard_bid_count_columns | `20260804235048` | 046_guard_bid_count_columns | name (embeds 046) |
| `047` | block_activity_on_cancelled_listings | `20260805002810` | 047_… | name |
| `048` | auction_media_owner_delete | `20260805025025` | 048_… | name |
| `049` | proof_docs_owner_delete_unreferenced | `20260805025438` | 049_… | name |
| `050` | realtime_publication_bids_listings | `20260730222142` | **044_realtime_publication_bids_listings** | **content-verified** — realtime publication defined only in repo `050`; prod row **mislabeled `044_`** and applied *early* (2026-07-30, before repo 044/045) |
| `051` | storage_scope_public_read | `20260805033055` | 051_… | name |
| `052` | profiles_anon_column_restriction | `20260805035221` | 052_… | name (note: applied *after* 053/054 timestamps) |
| `053` | storage_scope_write_policies | `20260805035353` | 053_… | name |
| `054` | fix_notify_outbid_aborts_bids | `20260805034758` | 054_… | name (applied *before* 052/053 timestamps) |
| `055` | transfer_state_guard | `20260805040743` | 055_… | name |
| `055b` | transfer_guard_bypass_for_remaining_writers | `20260805040826` | 055b_… | name |
| `055c` | revoke_anon_public_on_listing_rpcs | `20260805040935` | 055c_… | name |
| `055d` | fix_mark_transfer_sent_overload_ambiguity | `20260805041030` | 055d_… | name |
| `056a` | transfer_writer_rpcs | `20260805045314` | 056a_… | name |
| `056b` | remove_transfer_guard_service_role_exemption | `20260806003406` | 056b_… | name |
| `056c` | scope_transfer_guard_bypass_**to_function** | `20260806004256` | 056c_scope_transfer_guard_bypass_**to_statement** | 1:1; **label word differs** (function vs statement), same version |
| `056d` | record_transfer_payout_refuses_disputed | `20260806004545` | 056d_… | name |
| `057` | notifications_dedupe_and_enqueue_helper | `20260805044106` | 057_… | name |
| `058` | notification_producers | `20260805044159` | 058_… | name |
| `059` | strict_auth_on_listing_checkout_rpcs | `20260805044821` | 059_… | name |
| `059b` | strict_auth_ensure_transfer_exists | `20260805044913` | 059b_… | name |
| `060` | auth_password_change_notifications | `20260805045437` | 060_… | name |
| `060b` | fix_sweep_query_destination | `20260805045525` | 060b_… | name |
| `061` | ensure_transfer_exists_requires_verified_payment | `20260806002500` | 061_… | name |
| `062` | profiles_authenticated_column_restriction | `20260806005147` | 062_… | name |
| `063` | revoke_unsafe_execute_and_truncate | `20260806005349` | 063_… | name |
| `064` | webhook_event_claim_lease | `20260806010150` | 064_… | name |
| `065` | dispute_resolution | `20260806010900` | 065_… | name |
| `066` | pin_search_path_definer_functions | `20260824161047` | 066_… | name |
| `067` | revoke_execute_internal_functions | `20260824161131` | 067_… | name |
| `068` | profiles_authenticated_select_public_safe_only | `20260824161202` | 068_… | name |

**36 logical migrations, each with a version-string mismatch (repo `NNN_` ≠ prod timestamp).**

### 4c. Timestamp rows that STAY as-is (aligned on both sides — the 4 website forms)

| Version | Repo file = Prod label | Action |
|---|---|---|
| `20260714190445` | investor_leads_website_form | **keep** — identical timestamp both sides |
| `20260730212326` | ambassador_applications_website_form | **keep** |
| `20260730212406` | ambassador_applications_fix_search_path | **keep** |
| `20260731224653` | venue_partnership_inquiries_website_form | **keep** |

### 4d. Local-only rows (repo has file; prod ledger has NO row; objects already exist on prod)

| Repo version | Repo file | Why no prod row | Object exists on prod? |
|---|---|---|---|
| `000` | baseline_schema | baseline predates migration tracking | ✅ (all base tables) |
| `023b` | set_updated_at_helper | helper applied via baseline / folded | ✅ (`set_updated_at`) |
| `066a` | vendor_out_of_band_functions | `sync_listing_current_bid`/`is_winner` created out-of-band | ✅ (Gate-2 defect #5) |
| `069` | webhook_retries_table | table created out-of-band via SQL editor | ✅ (Gate-2 defect #4) |
| `070` | reconcile_rls_policies_and_triggers | ~14 policies + 2 triggers applied out-of-band | ✅ (Gate-2 defect #6) |

### 4e. Orphans

- **Production orphans (ledger row, no repo file): NONE.** Every prod row maps to a repo file (§4a/§4b/§4c).
- **Gap: `043`** — no repo file in `phase0/lockdown`, no prod ledger row. The untracked
  `mobile/profile-rpc-compat` file at that number is a hazard (§11), not part of this chain.

---

## 5. Gate-2 re-replay assessment

**Does the certified PASS still hold? — YES. A fresh re-replay is NOT required now.**

- The migration **chain is unchanged** since certification (same 84 files on `phase0/lockdown`; the last
  schema-affecting additions `066/067/068` were applied to production `2026-08-24` and are in the chain).
- Gate-2 PASS is a property of the **chain replaying on a clean DB** and matching production's **schema** —
  neither of which a *ledger-only* `migration repair` changes. Repair edits `schema_migrations` rows; it runs
  **no DDL**, creates/drops **no object**. Post-repair schema = pre-repair schema.
- **Static re-confirmation of the chain (no DB needed):** the known ordering hazards are already vendored —
  `000` index-before-column reordering fixed; `066a` precedes `067` (so `067`'s revoke of
  `sync_listing_current_bid` no longer rolls back); `069`/`070` idempotent (`IF NOT EXISTS` / `DROP…CREATE`
  net-no-op on prod). The standing CI `db` job re-proves clean bootstrap on every PR.

**What a *true* fresh-DB re-replay would require — OWNER/INFRA action, NOT done here:** creating a Supabase
**Pro branch** (paid; cost-confirmation prompt) or applying migrations to a throwaway DB. Both are writes /
gated actions outside Agent F's mandate. **Rely on the existing certified evidence + the static analysis
above.** Re-run a fresh replay only if the chain changes (e.g. `043` merged, or `071+` added).

---

## 6. PROPOSED `supabase migration repair` command list (NOT executed)

**Goal:** make production's ledger match the repo's `NNN_` scheme so `supabase db push` sees the historical
chain as fully applied (nothing pending, nothing re-run) and Phase-2 `071+` applies cleanly on top.

**Prerequisites (owner):** from a checkout of `main` **at or after the PR #5 normalization merge** (the
renamed files must be present locally — `repair --status applied` resolves each version to its file via the
glob `<version>_*.sql` and refuses to run without it): `supabase link --project-ref hqycwntpfoztoinemqns`.
**CLI ≥ 2.115.0 (TS rewrite) is MANDATORY — the Go CLI 2.75.0 must NOT be used for this event or its
verification** (see Addendum B: it orders local files by filename, not version, and hard-fails post-repair
with `ErrMissingLocal`, suggesting reverts that must never be run). **First take a ledger backup** (§8.1).
All versions below are the **post-rename numeric versions** (PR #5); the pre-rename letter versions
(`023b`, `055b`…) are unrepairable — the CLI rejects non-integer version arguments (`strconv.Atoi`).

**Recommended order: APPLY (additive) first, then REVERT (cleanup).** During the window both the timestamp
row and the `NNN_` row for a migration may briefly coexist — harmless (different version strings, schema
untouched). This ordering means no migration is ever momentarily un-recorded.

### 6a. `--status applied` — add numeric-scheme rows (41 commands, post-rename versions)

*36 that replace a timestamp row (§4b) + 5 local-only whose objects already exist (§4d: `000 0231 0661 069 070`).
The renamed versions are: `023b→0231, 055b→0551, 055c→0552, 055d→0553, 056a→0561, 056b→0562, 056c→0563,
056d→0564, 059b→0591, 060b→0601, 066a→0661` (PR #5, byte-identical renames).*

```bash
# local-only (objects already on prod — Gate-2 verified)
supabase migration repair --status applied 000
supabase migration repair --status applied 0231
supabase migration repair --status applied 0661
supabase migration repair --status applied 069
supabase migration repair --status applied 070
# numeric equivalents of the timestamp rows (040–068 block)
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

### 6b. `--status reverted` — remove the superseded timestamp rows (36 commands)

*The `040–068` timestamp rows from §4b. **Do NOT revert the 4 website-form timestamps** in §4c.*

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
supabase migration repair --status reverted 20260805040826   # was 055b -> now 0551
supabase migration repair --status reverted 20260805040935   # was 055c -> now 0552
supabase migration repair --status reverted 20260805041030   # was 055d -> now 0553
supabase migration repair --status reverted 20260805044106   # was 057
supabase migration repair --status reverted 20260805044159   # was 058
supabase migration repair --status reverted 20260805044821   # was 059
supabase migration repair --status reverted 20260805044913   # was 059b -> now 0591
supabase migration repair --status reverted 20260805045314   # was 056a -> now 0561
supabase migration repair --status reverted 20260805045437   # was 060
supabase migration repair --status reverted 20260805045525   # was 060b -> now 0601
supabase migration repair --status reverted 20260806002500   # was 061
supabase migration repair --status reverted 20260806003406   # was 056b -> now 0562
supabase migration repair --status reverted 20260806004256   # was 056c -> now 0563
supabase migration repair --status reverted 20260806004545   # was 056d -> now 0564
supabase migration repair --status reverted 20260806005147   # was 062
supabase migration repair --status reverted 20260806005349   # was 063
supabase migration repair --status reverted 20260806010150   # was 064
supabase migration repair --status reverted 20260806010900   # was 065
supabase migration repair --status reverted 20260824161047   # was 066
supabase migration repair --status reverted 20260824161131   # was 067
supabase migration repair --status reverted 20260824161202   # was 068
```

**Command count: 41 applied + 36 reverted = 77 proposed `migration repair` commands.**
(The CLI accepts multiple versions per invocation; the per-version form above is explicit and
auditable. `001–039` and the 4 website-form timestamps are deliberately untouched.)

**Execution is governed by `PHASE_2_MIGRATION_REPAIR_EXECUTION_PLAN.md`** (repo root) — preconditions,
per-command expected output, AFTER-state verification, inverse commands, and the mid-run failure protocol.

---

## 7. Expected post-repair `schema_migrations` state (post-rename numeric versions)

- **Row count: 84** — exactly one row per repo migration file (79 before → −36 timestamps reverted
  +36 numeric equivalents +5 local-only = 84; `001–039` and the 4 website forms unchanged).
- **Version set (sorted lexicographically, exactly as `ORDER BY version` returns it):**
  `000, 001–022, 023, 0231, 024–039, 040, 041, 042, 044, 045, 046–049, 050–054, 055, 0551, 0552, 0553,
  0561, 0562, 0563, 0564, 057, 058, 059, 0591, 060, 0601, 061–065, 066, 0661, 067, 068, 069, 070` + the 4
  website-form timestamps (`20260714190445, 20260730212326, 20260730212406, 20260731224653`).
  **No `043`. No letter-suffixed version anywhere.**
- `supabase migration list --linked` (CLI ≥ 2.115.0) shows **local and remote identical → zero pending,
  zero to revert.**
- **Schema is byte-for-byte unchanged** (ledger-only edit; Gate-2 counts still 27/68/37/23/3).
- Phase-2 `071+` (per `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §0.2) then sits cleanly at the true applied max
  (`070`; the 4-digit inserts all sort below it — `"0231" < … < "0661" < "070"`) and applies via the
  **gated** path only.

---

## 8. Validation steps (owner, after repair)

1. **Pre-flight backup (do this BEFORE any repair):** read-only export of the current ledger so it is
   restorable:
   `SELECT version, name FROM supabase_migrations.schema_migrations ORDER BY version;` → save to a file.
2. **After 6a/6b:** `supabase migration list` → every row shows a matching Local **and** Remote version;
   **no "pending" (local-only) and no "reverted" (remote-only)** entries.
3. **Ledger assertion (read-only SQL):** count = 84; `SELECT version FROM
   supabase_migrations.schema_migrations WHERE version = '043'` returns **0 rows**; spot-check that
   `20260729185526`/`20260730222142`/`20260824161202` are **gone** and `040`/`050`/`068` are **present**.
4. **Dry-run push (no apply):** `supabase db push --dry-run` → reports **"Remote database is up to date"** /
   nothing to apply. **If it lists 040–068 as pending, STOP** — a version was mistyped; do not `db push`.
5. **Re-run Gate-2 CI `db` job** on `phase0/lockdown` (throwaway DB) → still green (chain unchanged).
6. **Advisors re-check (read-only):** `get_advisors` security/performance unchanged vs §10 (no new lints).
7. Only after 1–6 pass, proceed to author/apply `071+` via the gated `workflow_dispatch` path — **never**
   by enabling auto-deploy.

---

## 9. Rollback / recovery considerations

- **`migration repair` is reversible in principle** — it is INSERT/DELETE on one ledger table. To undo,
  re-apply the inverse status per version (revert→applied, applied→reverted) using the §8.1 backup as the
  source of truth. Keep the backup until the gated `db push` flow is proven.
- **No schema rollback is involved** — repair touches no object, so there is nothing to un-migrate. This is
  the key safety property: a mistyped repair corrupts *bookkeeping*, not data/schema.
- **Failure mode to avoid:** running a `--status reverted` for a version whose `NNN_` `--status applied` was
  *not* also run (or was mistyped) → `db push` then treats that migration as pending and **re-applies DDL**.
  Mitigation: run **all of 6a before any of 6b**; then validate §8.4 dry-run **before** any real `db push`.
- **Worst case (ledger unrecoverable):** restore `schema_migrations` from the §8.1 export, or from the
  automated Supabase PITR/backup (`backups/` in-repo holds a pre-039 snapshot for reference only). Schema is
  never at risk from this operation.
- **Do NOT** attempt repair while any auto-deploy or concurrent `db push` could run — single operator, gate off.

---

## 10. Advisor findings (read-only `get_advisors`, 2026-08-24) — new since Phase-0 closeout?

**Security (`get_advisors security`): no new/actionable schema findings; posture matches the certified design.**

- **14 × `rls_enabled_no_policy` (INFO):** `admin_users, auth_audit_sweep_state, dispute_resolutions,
  disputes, payout_decisions, payout_policy, rate_limits, seller_flags, seller_risk_scores,
  stripe_connect_archive, stripe_webhook_events, transfer_notifications, webhook_retries` — **intentional
  deny-all** money/custody/service-role tables (RLS on + 0 policies + `REVOKE ALL`). Explicitly the desired
  state per Gate-2 (e.g. `webhook_retries` = "RLS enabled, 0 policies"). **Not drift; not new.**
- **~17 × `authenticated_security_definer_function_executable` (WARN):** the app's **intended public RPC
  surface** (`get_my_profile`, `can_create_listing`, `cancel_listing`, `complete_auction_payment`,
  `confirm_transfer_received`, `ensure_transfer_exists`, `finalize_auction`, `get_profile_trust_stats`,
  `mark_listing_sold`, `mark_transfer_sent` ×2 overloads, `mark_transfer_viewed`, `phone_verified`,
  `release_reservation`, `reserve_buy_now`, `set_transfer_delivery_info`, `buyer_dispute_transfer`). These are
  the functions `067` deliberately **kept** executable (it revoked only *internal* helpers). Expected;
  consistent with the `mobile/profile-rpc-compat` work (`get_my_profile`). **Not new drift.**
- **1 × `auth_leaked_password_protection` disabled (WARN):** Supabase Auth is not checking passwords against
  HaveIBeenPwned. **Auth *config*, not schema** → owner console action (§11). Pre-existing; unrelated to the
  migration chain.

**Performance (`get_advisors performance`): 96 lints (39 INFO / 57 WARN) — hygiene only, none blocking, none new schema drift.**

- `auth_rls_initplan` ×30 (WARN) — policies calling `auth.<fn>()` un-wrapped (re-evaluated per row); the
  standard Supabase advisory. Broad but low-risk; a future perf pass can wrap in `(select auth.uid())`.
- `multiple_permissive_policies` ×25 (WARN) — overlapping permissive policies on hot tables (listings,
  transfers, profiles, payments…). Hygiene.
- `unindexed_foreign_keys` ×19 (INFO), `unused_index` ×18 (INFO) — expected on a low-traffic/empty-branch
  posture; several `unused` will "light up" under load.
- `duplicate_index` ×2 (WARN) — **ties to the known Gate-2 +3 legacy-name index residual** (§1); the
  documented cleanup (drop the 6 legacy-named indexes) resolves both.
- `table_bloat` ×1, `auth_db_connections_absolute` ×1, `_http_response` ×1 — informational.

**Bottom line:** advisors reflect the **already-certified** schema/posture. No finding indicates schema drift
introduced after Phase-0 closeout. The only genuinely new *owner-config* item is enabling leaked-password
protection; the perf items are pre-existing, optional hygiene.

---

## 11. Blockers / owner-action items

| # | Item | Type | Blocking? |
|---|---|---|---|
| 1 | **Run the 77 `migration repair` commands (§6)** to align production ledger to the `NNN_` scheme. | Owner + Agent F/G review; production ledger **write** (outside Agent F mandate) | **Blocks** any safe `db push` / Phase-2 apply |
| 2 | **Keep Supabase "Deploy to production" OFF**; adopt gated `workflow_dispatch` + GitHub Environment reviewer for `db push`. | Governance / GitHub+Supabase settings | **Blocks** enabling auto-deploy |
| 3 | **Untracked `043_profiles_select_column_restriction.sql`** in `mobile/profile-rpc-compat` is a **back-dated version**: `043 < 044…070` (already applied) → `migrations-guard` will **reject** it and `db push` would treat it as **pending/out-of-order**. Must be **renumbered ≥ 071** (or dropped/folded) and reconciled against the phase0 chain before merge. | Repo hygiene (mobile branch owner) | **Blocks** merging that branch cleanly; **not** a phase0-chain blocker |
| 4 | **A true fresh-DB Gate-2 re-replay** (if ever required) needs a **Supabase Pro branch (paid, cost-confirm)** or a throwaway DB. Not performed (read-only mandate). Existing certification stands while the chain is unchanged. | Infra (paid) | Not blocking now |
| 5 | **Enable Auth leaked-password protection** (HaveIBeenPwned). | Owner console (Auth config) | Not blocking; security hygiene |
| 6 | Optional perf hygiene (drop 6 legacy-name/duplicate indexes; wrap `auth.*()` in RLS; prune overlapping permissive policies). | Future migration (`071+`) | Not blocking |

---

*Prepared read-only by Agent F. All `migration repair` commands are PROPOSED. No production object or ledger
row was modified. Execution requires owner authorization + Agent F/G review, with auto-deploy kept OFF.*

---

## Addendum A (2026-08-25) — Letter-suffixed filenames are invisible to the Supabase CLI (first-ever CI run finding)

**Finding.** The repository chain contains **11 letter-suffixed migration files** — `023b`, `055b`, `055c`, `055d`, `056a`, `056b`, `056c`, `056d`, `059b`, `060b`, `066a` — whose names do **not** match the Supabase CLI's migration pattern (`^<digits>_name.sql`). The CLI (every version; verified on `latest` in CI) **skips them non-fatally, printing a per-file stderr notice** (`Skipping migration <file>... (file name must match pattern "<timestamp>_name.sql")` — easy to miss in scroll-back, and the run proceeds without error), so a fresh `supabase start` replay fails at `067` (`function public.sync_listing_current_bid() does not exist` — that function is vendored by the skipped `066a`). This was never caught before because the CI workflow itself never started (job-level `hashFiles()` startup defect, fixed 2026-08-25); the Phase-0 Gate-2 certification replay applied each file's **content by name** via the management API, bypassing filename parsing — the certification remains valid for **content**, but the chain is **not replayable by the standard CLI tooling** as filed.

**Consequence.** The CI `db` job (fresh-DB replay gate) stays **red** until the 11 files are normalized. Phase-2 local development (`supabase start`) is equally affected.

**Remediation (bundle into the same owner-gated repair event as §6 — do NOT do piecemeal):**
1. **Rename** the 11 files to pure-numeric versions that preserve order (e.g. insert as `0231`, `0551`–`0553`, `0561`–`0564`, `0591`, `0601`, `0661` — exact scheme chosen at execution; must sort between their neighbors) — a deliberate, one-time exception to the append-only rule, executed **with** the ledger repair so repo names and `schema_migrations` stay 1:1.
2. **Extend the §6 repair plan** so the `--status applied` inserts use the **new** names (the 5 repo-only rows incl. `023b`/`066a` change name; the 36 timestamp-reverts are unaffected).
3. **migrations-guard**: land the renames in the same PR as a documented guard exemption (the guard exists to prevent *undocumented* mutation; this is the documented reconciliation event it anticipates).
4. **Re-run the CI `db` job** — it must go green on the renamed chain before any `071_*` file is authored.

**Status:** Steps 1–3 EXECUTED in PR #5 (branch `repo/migration-ledger-normalization` — see Addendum B for
the exact rename map, the guard allowlist mechanics, and the CLI-ordering findings). Step 4 (CI `db` green)
is PR #5's merge condition. The §6 ledger repair itself remains **PROPOSED** behind the same authorization
gate (owner + Agent F/G review), now runbook'd in `PHASE_2_MIGRATION_REPAIR_EXECUTION_PLAN.md`.

---

## Addendum B (2026-08-25) — Normalization executed in PR #5; CLI ordering findings

**1. Rename map (executed, byte-identical `git mv` — all 11 proven `R100` by
`git diff --find-renames=100% --name-status`):**

```
023b_set_updated_at_helper.sql                        -> 0231_set_updated_at_helper.sql
055b_transfer_guard_bypass_for_remaining_writers.sql  -> 0551_transfer_guard_bypass_for_remaining_writers.sql
055c_revoke_anon_public_on_listing_rpcs.sql           -> 0552_revoke_anon_public_on_listing_rpcs.sql
055d_fix_mark_transfer_sent_overload_ambiguity.sql    -> 0553_fix_mark_transfer_sent_overload_ambiguity.sql
056a_transfer_writer_rpcs.sql                         -> 0561_transfer_writer_rpcs.sql
056b_remove_transfer_guard_service_role_exemption.sql -> 0562_remove_transfer_guard_service_role_exemption.sql
056c_scope_transfer_guard_bypass_to_function.sql      -> 0563_scope_transfer_guard_bypass_to_function.sql
056d_record_transfer_payout_refuses_disputed.sql      -> 0564_record_transfer_payout_refuses_disputed.sql
059b_strict_auth_ensure_transfer_exists.sql           -> 0591_strict_auth_ensure_transfer_exists.sql
060b_fix_sweep_query_destination.sql                  -> 0601_fix_sweep_query_destination.sql
066a_vendor_out_of_band_functions.sql                 -> 0661_vendor_out_of_band_functions.sql
```

Where §2/§4 of this document print letter versions (`023b`, `055b`…), they describe the **pre-rename**
filenames; the map above is 1:1 and the version-comparator position is unchanged
(`"023" < "0231" < "024"`, …, `"066" < "0661" < "067"`, all `< "070"` and `< "2026…"`).

**2. `migrations-guard` one-time exemption (same PR):** the guard now carries an explicit allowlist of
exactly these 11 old→new pairs, honored **only** when the diff line is `R100` (the guard diffs with
`--find-renames=100%`, so an edited rename decomposes to D+A and the D still fails); the monotonic check
skips **only** the 11 new basenames. Everything else — modification, deletion, any other rename, any
back-dated addition — still fails. **PR #5b deletes the allowlist**, restoring the guard verbatim.
(A latent guard defect was also fixed in passing: under `set -euo pipefail`, the `basemax` subshell's
trailing `[ … ] && echo` false-exit silently aborted the script for **every newly added `NNN_` file** —
it would have false-failed `071_` too. The scheme filter is now an `if` statement.)

**3. CLI ordering findings (source-verified on both generations) — the reason CI pins `2.115.0`, not
`2.75.0`:**

- **Go CLI v2.75.0** (`pkg/migration/list.go` `ListLocalMigrations`): enumerates local migrations in raw
  `fs.ReadDir` **filename** order and never re-sorts by version. For the five parent/child groups the two
  orders **diverge**: as filenames, `0231_… < 023_…` (byte `'1'` 0x31 < `'_'` 0x5F), likewise
  `0551/0552/0553 < 055_`, `0591 < 059_`, `0601 < 060_`, `0661 < 066_`; as **versions** the children sort
  **after** the parents. Consequences under 2.75.0:
  - A fresh replay applies `0553` **before** `055` and `0601` **before** `060` — it completes without
    error but ends with the stale parent bodies winning (the 3-arg `mark_transfer_sent` regains its
    `DEFAULT NULL::text` → the PGRST203 overload-ambiguity regression `055d` fixed;
    `sweep_auth_password_changes` reverts to its pre-`060b` body). **Green replay, wrong schema.**
  - Post-repair, `db push`/`migration up` walk remote (version order) against local (filename order) and
    hard-fail with `ErrMissingLocal` on `023, 055, 059, 060, 066` — and the CLI then **suggests
    `migration repair --status reverted 023 055 059 060 066`, which must NEVER be run** (it would mark
    five applied migrations unapplied; a subsequent push would re-run their DDL on production).
- **TS-rewrite CLI (`latest`, pinned 2.115.0)**: re-sorts local paths **by version**
  (`legacySortMigrationPathsByVersion` / `legacyCompareMigrationVersions` — documented lexical order)
  before both applying and reconciling, so replay order ≡ version order ≡ remote order. The normalized
  chain is fully coherent on this CLI generation; it is also the CLI that actually executed the first CI
  `db` run (as `latest`).

**Operational rule:** the repair event and all its verification steps use **CLI ≥ 2.115.0 only**; upgrade
the dev machine off 2.75.0 before running `supabase start` / `db push` against this chain.

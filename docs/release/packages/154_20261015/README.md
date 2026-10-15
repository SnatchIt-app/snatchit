# Migrations 154, 155, 156 + the legacy-listing data step: production package (A, 2026-10-15)

**Owner authorisation (A's chat, 2026-10-15):** all existing listings leave public access on every surface and every build; private payment, refund, transfer, dispute and order history is preserved; no money state changes; 72 h auctions; an explicit, recorded owner proof waiver for the admin's own listings, never marked verified. Spec: `sprint-control/SPEC_154_LISTING_VISIBILITY.md`.

**Nothing here is authorised to run against production yet.** Each step below (backup, probe, each apply, the data step, any rollback) needs the owner's own instruction in their own turn. This package never runs `db push`, never uses MCP `apply_migration`, and never touches 121/125/126.

## Identity
Branch `fix/154-listing-visibility-20261015` from the gate `release/production-gate-20260918` @ `6f982f36`. Registry numbers 154/155/156, pgTAP 221/222/223 (153 is taken and parked; the authoritative registry is on `origin/release/candidate-20260918`).

| Frozen file | Blob | md5 | Bytes |
|---|---|---|---|
| `migrations/20261015000000_listing_public_visibility.sql` (154) | `378ab5fb` | `bda198b7efe87ef3811bcdb9b136de5f` | 26,076 |
| `migrations/20261015000100_listing_duration_72h.sql` (155) | `51684cc7` | `51ce810d5b85c4a548d872b5f7a61f9a` | 5,942 |
| `migrations/20261015000200_listing_proof_owner_waiver.sql` (156) | `174d39ca` | `c85c4fb241f9443171c6b3634471a040` | 19,030 |
| `rollbacks/20261015000000_…_rollback.sql` | `e6b5e1c2` | `eb20ead47ecb2dfd2fa568c43c1f0b8f` | 7,624 |
| `rollbacks/20261015000100_…_rollback.sql` | `fd69f8a5` | `e303ffa5bff3b56cdfcca0560659f49f` | 3,061 |
| `rollbacks/20261015000200_…_rollback.sql` | `ac876307` | `5a0634ba0d746761978d2a856ce20078` | 4,615 |

**Re-frozen a third time 2026-10-15 for the compat-release review (text only).** The 155 and 156 rollback headers now
state the client order each rollback needs (see Rollbacks below): 156's names every web read that breaks once
`proof_waived_at` is dropped (web #108) and RC9's pay and bid reads; 155's names the 72 h option in web #107/#108 and
RC9. Every non-comment line of both rollbacks is unchanged (`rehearsal/check_rollback_client_order.py`, check B).
Changed: the two rollbacks and their frozen copies, `frozen.sha256`, the `rollback_155`/`rollback_156` DRY
requests, `rehearsal/r0_pre_local.txt` and `rehearsal/expected_local/*` (the rebuilt fixture's four timestamp-
dependent hashes only) and the LOCALDB rehearsal log. Unchanged, byte for byte: the three migrations, the 154
rollback, `pkg.py`, `predict.py`, `sql/*`, `rehearsal/lists_*.json` and `expected/*` (re-predicted from the same
`pre154.txt` and `lists_prod.json`: identical). Production was not re-read: no input to a prediction changed.

**Re-frozen a second time 2026-10-15 for ADDENDUM 3 and the second review** (156: the old-build purchase safeguard,
proof required without a waiver, the never-approved CHECK, no client proof path on a waived listing; 154: the
listing_visibility FK is ON DELETE RESTRICT). 154, 156 and their rollbacks changed; 155 and its rollback are
byte-identical to the first re-freeze. Regenerated: `frozen.sha256`, `pkg.py` (156 ledger guard), `predict.py` (156
constants and census delta, `lv_fk`), `sql/state.sql` (new fn/exec/trigger keys, `lv_fk`), `rehearsal/lists_query.sql`
(156's two new triggers), `expected/*` (production `pre154.txt` RE-READ read-only 04:2xZ, then re-predicted),
`rehearsal/lists_prod.json` (re-read), `rehearsal/lists_local.json`, `rehearsal/r0_pre_local.txt`,
`rehearsal/expected_local/*`, `rehearsal/out/*` and the LOCALDB rehearsal log. `sql/hide_legacy.sql`,
`sql/unhide_legacy.sql` and `sql/state_anon.sql` are unchanged.

**Re-frozen 2026-10-15 after the 154/155 review** (findings: the hidden-row Buy Now hole, the reservation-sweep wedge,
the missing ADDENDUM 2 objects). 154 and 155 and their rollbacks changed; 156 is byte-identical to the first freeze.
Everything derived from them was regenerated: `frozen.sha256`, `pkg.py` (154/155 ledger guards), `predict.py`
(function constants, census deltas, new keys), `sql/state.sql` (new keys), `sql/hide_legacy.sql` (widened live check),
`expected/*` (production `pre154.txt` RE-READ, read-only, then re-predicted), `rehearsal/lists_*.json`,
`rehearsal/expected_local/*`, `rehearsal/out/*` and the LOCALDB rehearsal log.

`frozen.sha256` holds the sha256 of all six. Each frozen file is byte-identical to its copy under `supabase/`.

**Runner:** `pkg.py`, sha256 `305d273908f979b23818355018ae92452185c5f682c5845a397b074f54b1d4cd` (first freeze `1abf0951…`, first re-freeze `6e215899…`; the
only changes are the `gone` conditions of the guarded ledger delete: 154/155's also require `is_public(listings)` and
`set_listing_ends_at_from_duration()` to be gone, and 156's now also requires `client_shows_proof_disclosure()`,
`guard_bid_requires_disclosure()` and `guard_reservation_requires_disclosure()` to be gone). Copied from `../152_20261013/pkg.py` (sha256 `02537f62…`, executed 2026-10-13). Same transport: one Management API `database/query` POST per request, carrying the file bytes, then the ledger INSERT `(version, name, statements = ARRAY[raw file], created_by 'claude-a/owner-authorised-N')`. The changes are listed in its docstring:
- MIG entries 154 → 155 → 156, where each one's pre file is the previous one's post file;
- `state` is two read-only requests: `sql/state.sql` and `sql/state_anon.sql`;
- `rb_post` / `rollback_ignore`, and `alt_pre` for 154;
- the `step hide|unhide` data step;
- `PKG_EXPECTED`.

**The private production wrapper must be re-pinned to this hash before use.** 152's wrapper is `private-evidence/A-preapply-152-20261013/scripts/run_pkg152_prod.sh` (keychain token, never printed). This lane was told to work only in this worktree, so it has not written the 154 copy.

## What each step does
- **154:** adds `public.listing_visibility` (RLS on, no policies; service_role SELECT/INSERT/DELETE only).
  - Its one foreign key, `listing_visibility_listing_id_fkey` → `listings(id)`, is **ON DELETE RESTRICT** (review fix; the spec's first text said CASCADE). With CASCADE a seller could delete their own hidden listing (`listings_delete_own`) to erase its hide row and re-create the id publicly. RESTRICT refuses that delete for every caller (23503); a public listing is unaffected. The key is dropped and re-added after `CREATE TABLE IF NOT EXISTS`, so a kept table always ends with exactly this key. `state.sql` pins it as `lv_fk`.
  - `listing_is_public` and `listing_private_party` are SECURITY DEFINER boolean predicates. They are anon-executable by explicit grant.
  - `listings_select_visible` and `bids_select_visible` replace the two `USING (true)` policies.
  - `is_public(public.listings)` is the PostgREST computed field (`.eq('is_public', true)`), SECURITY INVOKER, anon-executable by explicit grant. C's N1 build filters with it; against a database without it, PostgREST answers those feed reads with 400 (42703).
  - The invariant "a hidden listing is never live, held or extended" is enforced by two triggers, for every caller. "Open" is what `reserve_buy_now` accepts (status active/reserved, auction not cancelled, `ends_at >= now()`), not only auction 'active'. Hide time refuses an open row and a row under a live Buy Now hold. On a hidden row an UPDATE may not take a new hold, may not move `ends_at` to now or later, and may not leave the row open. So `reserve_buy_now`, a bid and both create-payment-intent preconditions are refused on every hidden row for anyone but an existing auction winner, and the reservation sweep cannot be wedged.
  - `get_profile_trust_stats` excludes hidden listings, and `active_listings` also requires `ends_at > now()`. It is otherwise 031's body.
  - The three readers are owned by the owner of listings/bids/payments/transfers (postgres, BYPASSRLS in production) and none of those tables forces RLS, so the policies cannot recurse (42P17). `state.sql` reads this back (`rls_*`, `owner_role`, `fnown_*`).
  - It hides nothing by itself.
- **155:** `listings_duration_hours_check` becomes `{1,3,6,12,24,48,72}`, and the end time becomes server-owned: `trg_listing_ends_at_from_duration` (BEFORE INSERT OR UPDATE) sets an untrusted insert's `ends_at` to `now() + duration_hours` and refuses an untrusted change of `ends_at` or `duration_hours` unless an auction RPC set the listing-guard bypass (`admin_relist_listing`). service_role and claims-less postgres are untouched. No shipped client sends either column on UPDATE.
- **156:** adds `proof_waived_at`, `proof_waived_by` and `proof_waiver_reason`, with an all-or-none check.
  - `guard_listing_proof_waiver` allows a waiver only from an admin listing their own inventory, with no proof path and a reason, and only at creation. The server stamps the time.
  - Clients cannot change a waiver later, and cannot add a proof path to a waived listing later (review fix: the waiver stays clean).
  - CHECK `listings_proof_waiver_never_approved`: no caller (service_role, postgres and ops.* definers included) can approve a waived listing or create one already approved (review fix).
  - Proof stays required (ADDENDUM 3b): an untrusted create with no waiver needs a non-blank `proof_of_ownership_path`, else `Upload proof of ownership.` (HINT `PROOF_REQUIRED`). Every shipped producer sends one (native `CreateListingScreen` returns before the insert without it; web `create-listing.ts` types it required; RC9 and web #108 too); service-role scripts (`scripts/seed-demo.ts`) are trusted. The database checks presence, not that the object exists.
  - `current_user_is_admin()` is authenticated-execute (true for an `admin_users` member, false otherwise, permission denied for anon).
  - **Old-build purchase safeguard (ADDENDUM 3a).** `client_shows_proof_disclosure()` (STABLE, invoker, no-client-execute) is true only when the PostgREST `request.headers` JSON carries `x-snatchit-caps` with the whole token `proof-disclosure-v1` (space or comma separated); NULL, empty, unparseable or non-string → false.
    - `trg_bid_requires_disclosure` (BEFORE INSERT on bids): on a waived listing, an untrusted caller without the token gets `This listing needs the latest Snatch It app. Update the app or use app.snatchitapp.com.` with HINT `LISTING_UNAVAILABLE` (builds 25/27 show "Not available").
    - `trg_reservation_requires_disclosure` (BEFORE UPDATE OF reserved_by on listings): a NEW holder on a waived listing (NULL → buyer, which is every `reserve_buy_now`, and also buyer A → buyer B, like 152's party guard; a deliberate superset of the spec's NULL → buyer) needs the token; the same message with no hint, never "sold" or "already reserved". Releasing a hold is never checked.
    - Trust test (both): the guards' test read the 119 way — the PostgREST role GUC and the request claims, never `current_user` alone (inside `reserve_buy_now`, a SECURITY DEFINER, `current_user` is the owner). service_role and a claims-less postgres session bypass; a postgres session that carries claims does not.
- **Data step `sql/hide_legacy.sql`** (`pkg.py step hide`) inserts 113 `listing_visibility` rows, one per id in `preimage/listing_ids_113.txt` (md5 `59568b40d69fe1bd2d5872e839be6731`, read from production 2026-10-15T02:29:50Z). Inside the one transaction it asserts:
  - the id list is the preimage;
  - all 113 exist and none is already hidden;
  - exactly 113 rows are inserted;
  - 0 hidden listings are open (to bids or Buy Now) or under a live hold — the widened predicate. Production at the re-read: every one of the 113 has `ends_at <= now()` except one `active/cancelled` row, and none is reserved, so all 113 still pass;
  - as anon, 0 listings and 0 bids are visible;
  - as a signed-in non-party, 0 listings are visible.

  It writes no other row. Its reversal, `sql/unhide_legacy.sql` (`step unhide`), is an owner decision because it re-exposes them.

## Requests (`MODE=DRY`, `rehearsal/out/`)

| Request | Bytes | sha256 |
|---|---|---|
| apply 154 | 52,358 | `1e44b38ef2843417b62f14d1f3f55258b9694030cc0c524824b5ea0d018c52d3` |
| apply 155 | 12,085 | `08e9746595f464bdbe0ae9ca9b1666d8447a4d76268d082ce3c24b7c729aa5d5` |
| apply 156 | 38,267 | `11a69c9459a86ad6fdc715131dc968f186866a5473ebd8a8053045de97c356d2` |
| step hide | 9,310 | `2a2fa64b05fe1b5189d5ab8d35d75dc999abb9301ee7be380609b3e92ab26a6b` |
| step unhide | 5,758 | `a0f71d8d4d879b0b981834df2ccce4935e8626debdf68a243403396c3e14d969` |
| rollback 156 / 155 / 154 | 5,241 / 3,432 / 8,384 | `486d12ab…` / `e50c6c82…` / `8182f6f4…` |
| ledger-only 154 / 155 / 156 | 26,280 / 6,141 / 19,235 | `29a5b8d9…` / `71326705…` / `513e7234…` |
| rollback 154 --ledger-only | 760 | `e60e8611…` |

The LOCALDB rehearsal sent exactly these bytes. The request hashes in `rehearsal/run_local_20261015.log` equal the DRY hashes.

## Transaction shape
- Each migration file carries its own `BEGIN; SET LOCAL lock_timeout = '3s'; … COMMIT;`, so the appended ledger INSERT is a second implicit transaction. If the file fails, nothing commits. The only possible split is objects present with no ledger row; `apply N --ledger-only` resumes that case (rehearsed as R8/R8b).
- `hide_legacy.sql` is one transaction (BEGIN … COMMIT). Every assertion RAISEs, so it is all or nothing.

## Expected states (`expected/`)
- **`pre154.txt`**: production, read-only, 2026-10-15.
  - It came from `state.sql` (`SET TRANSACTION READ ONLY`) plus `state_anon.sql` (`SET LOCAL ROLE anon` / `authenticated` in a read-only transaction), both through MCP `execute_sql`.
  - First read ~02:3xZ (a re-read at 03:01:59Z hashed the 59 catalog/data lines to `c42a43b9…`). RE-READ after the review fixes with the extended `state.sql`: all 75 lines equal the file; every key of the first read is unchanged (money/listing hashes, census, grants, anon counts).
  - RE-READ again 04:2xZ for the second re-freeze with this `state.sql`: the 75 earlier keys are unchanged byte for byte; the 4 new keys read `absent` (`exec_` of the three new 156 functions, `lv_fk`). 79 keys.
  - Values: ledger 165 / max `20261013000000`; census `34|116|37|43`; 113 listings, 0 live; `listings_select_all` / `bids_select_all` `USING (true)`; anon sees 113 listings and 98 bids; listings/bids/payments/transfers owned by `postgres` with RLS on and no FORCE; `owner_role=postgres|super=false|bypassrls=true`.
- **`post154.txt`, `post155.txt`, `post156.txt`, `post_hide.txt`, `rb154.txt`** are PREDICTIONS. `rehearsal/predict.py` derives them from `pre154.txt` plus `rehearsal/lists_prod.json`.
  - `lists_prod.json` came from one read-only production query (`rehearsal/lists_query.sql`, re-run after the review fixes and again 04:2xZ for the second re-freeze): the existing grant, trigger and listings-column rows plus the literal rows 154/155/156 add (now including `is_public`'s two EXECUTE grants, 155's trigger and 156's two disclosure triggers), re-hashed. Only `trg_156` moved (`891ea99a…|21`).
  - The new-object constants come from a fresh local PG 17 replay of the frozen files. Production runs 17.6.
  - Ownership keys are derived, not assumed: the three readers are predicted owned by the owner of listings with that role's RLS bypass (`fnown_*=postgres|owner_of_listings=true|bypasses_rls=true` in production); a different transport role makes the post check FAIL (exit 4) instead of shipping a recursion risk.
  - Predicted production post-156 census `35|126|37|49` (= ci.yml Gate-2), `hidden_open_or_held=0`, `lv_fk` = the one RESTRICT key (also in `rb154.txt`: 154's rollback keeps it).
  - Every fixed money/listing hash is predicted UNCHANGED.
  - The predictor was registered before the first local apply. Its local outputs (`rehearsal/expected_local/`) then matched every observed post-state (R1, R5, R6, R7, R9, R11, R12, R13 and the rollbacks).

### What `state.sql` pins (new vs 152)
- `pol_<table>.<policy>` for listings, bids and listing_visibility: cmd, roles, md5(qual), md5(with_check).
- `anon_listings`, `anon_bids`, `nonparty_listings`, `nonparty_bids` (in `state_anon.sql`).
- `lv_table` / `lv_rows`.
- `hidden_open_or_held`: hidden rows that are open (what `reserve_buy_now` accepts) or under a live hold; must stay 0.
- `lv_fk`: listing_visibility's foreign keys (name | `confdeltype` | definition) — exactly `listing_visibility_listing_id_fkey|r|… ON DELETE RESTRICT` with the table, `absent` without it.
- 156's three new functions in the `fn_`/`exec_` keys (none client-executable) and its two new triggers in `triggers_154_156`; `listings_proof_waiver_never_approved` joins `waiver_checks`.
- `rls_<table>` (owner, RLS, FORCE) for listings, bids, payments, transfers, listing_visibility; `owner_role` (the owner of listings: super / BYPASSRLS); `fnown_<reader>` for `listing_is_public`, `listing_private_party`, `is_public`: the no-42P17 guarantee read back.
- FIXED HASHES (count|md5 over `to_jsonb` rows, ordered `COLLATE "C"`, TimeZone UTC) of:
  - payments, transfers, payment_refunds, payment_refund_state, payout_attempts, payout_decisions, disputes, bids;
  - listings minus `updated_at` and minus 156's three waiver columns.

  pre == post on these proves no money or listing state moved. A live production write (for example a webhook updating a pending payment) between pre and post makes the post check FAIL (exit 4) without the migration being at fault: read the state and compare before any further step.
- `grants_anon_authenticated` keys routine grants by `name(argtypes)` from proacl. 152 used `specific_name`, which embeds OIDs and cannot be predicted.

## Rollbacks
| Rollback | What it does | Rows kept or refused |
|---|---|---|
| 156 | Drops the three triggers (`trg_guard_listing_proof_waiver`, `trg_reservation_requires_disclosure`, `trg_bid_requires_disclosure`), the five functions, the three checks and the three columns. **Client order:** (1) clear every recorded waiver through the trusted path (an owner decision; the rollback refuses otherwise; Rule (F): never roll web back past #108 while a waived listing is live); (2) deploy web without #108's `proof_waived_at` selects (`LISTING_COLUMNS`, `web/src/lib/listings.ts:54-55` at `068f054e`: with the column gone every such read is a PostgREST 400, so `/`, `/browse`, `/listing/[id]` and `/checkout/[id]` render the error page, saved listings shows its error state, `/api/public/events` answers 500 and the sitemap drops its listing entries; seller listings and non-waived creates are unaffected); (3) only then run this rollback. **Native:** RC9 (`4f7ad2b4`, N1 `7fc72a08`) selects `proof_waived_at` on checkout's pay face and on PlaceBid, so after this rollback an RC9 install cannot bid or pay on any listing. Once RC9 is in users' hands, step 2 also needs a successor native build without those selects, adopted by users, or the owner's written acceptance of the outage | **Refuses while any listing carries a waiver**: an archival record, and the columns would be client-writable without the guard. Rehearsed: refuses with a waiver (exit 3, unchanged); the guard is load-bearing (without it the rollback destroys the waiver) |
| 155 | Drops `trg_listing_ends_at_from_duration` + `set_listing_ends_at_from_duration()` (ends_at is client-set again) and restores `{1,3,6,12,24,48}`. **Client order:** (1) deploy web without the 72 h option (web #107 `a2540576`, also in #108: `LISTING_DURATION_HOURS`; after this rollback a 72 h create is refused with 23514); (2) end or migrate every 72 h listing; (3) only then run this rollback. **Native:** RC9 offers 72 h (`DURATION_OPTIONS`, the "3d" chip). Once RC9 is in users' hands, step 1 also needs a successor native build without 72 h, or the owner's written acceptance that RC9's "3d" create fails. Web and RC9 still send `ends_at` on insert, so their other creates keep working | **Refuses while any listing has 72 h** (a 72 h listing created between steps 1 and 3 makes it refuse again; nothing changed) |
| 154 | Restores both `USING (true)` policies (**re-exposes every hidden listing**) and 031's trust-stats body (functiondef md5 back to `23719c73…`); drops `is_public(listings)` (a build filtering `.eq('is_public', true)` gets 400 again) | **Keeps `listing_visibility`, its rows and its ON DELETE RESTRICT key** (inert for reads; a kept row still refuses deleting its listing, so delete the row first if the owner wants that listing deletable). A later clean re-apply reuses the table and refuses while a kept row names an open or held listing (rehearsed locally both ways, with a negative control: the first freeze's predicate re-applied over an open kept row) |

Order: 156 → 155 → 154. The runner's rollback guards ignore only the data-step keys, so the schema can be rolled back with the 113 rows still in place. Each rollback's client order (in the table above and in its header) comes first. The database rollback is the last step, never the first. `rehearsal/check_rollback_client_order.py` asserts that both headers and this table state the order, that the SQL bodies are unchanged, and that the client facts above still hold at the pinned commits.

## Local rehearsal (`rehearsal/run_local.sh` → `run_local_20261015.log`)
**Database.** `a154_pkg_rehears` was REBUILT for each re-freeze, last on 2026-10-15 ~05:3xZ for the third one (same recipe; fixture timestamps differ, so the local fixed hashes differ between runs) from:
- a clone of `pkg151_rehears` (ledger 164);
- plus 152's executed apply request (sha256 `ffc020a0…`, ledger 165);
- plus `rehearsal/fixture_local.sql` (synthetic rows carrying the 113 preimage ids, 0 live, 5 bids, 2 payments, 1 transfer).

Each step's expected exit code was registered in the script before the run, and `rehearsal/expected_local/` was re-predicted (from the re-measured `r0_pre_local.txt` and `lists_local.json`) before the first apply. **Result: 0 unexpected exit codes**; every request hash in the log equals its DRY hash. R5 and R16's post checks include `lv_fk`, so the RESTRICT key is proven after apply, after rollback (kept with the 113 rows) and after re-apply.

Extra rehearsals for the third re-freeze (scratch clones of a fresh replay with 154-156 applied, not part of
`run_local.sh`). The client select lists are taken verbatim from the pinned commits:
- 156: with a waiver the rollback refuses (nothing changed). Negative control: the same file without its refusal
  block runs and drops the waiver columns, so the record is gone. After step 1 (waiver cleared) it runs (156's
  delta is −5 functions, −3 triggers). Then web #108's `LISTING_COLUMNS`, RC9's `LISTING_SUMMARY_COLUMNS` and
  RC9's PlaceBid select each fail with 42703 (`column "proof_waived_at" does not exist`, PostgREST 400).
  `SELLER_LISTING_COLUMNS` still works, and so does a non-waived create with a proof path.
- 155: with a 72 h listing the rollback refuses (nothing changed). Negative control: without its refusal block it
  still changes nothing (`ADD CONSTRAINT` fails on the row, 23514); the block gives a clear message and is not the
  only barrier. After step 2 (the listing migrated to 48 h) it runs (−1 function, −1 trigger, check back to
  `{1,…,48}`). A 72 h create then fails with 23514; a 48 h create carrying the client's own `ends_at` works and
  keeps it.

Extra rehearsals for the second re-freeze (scratch databases cloned from a pre-154 replay, not part of `run_local.sh`):
- a kept table whose key is CASCADE (the first freeze's 154 applied, then rolled back) gets exactly one RESTRICT key when this 154 is applied; negative control: without the drop/re-add the key stays CASCADE;
- after 154's rollback a kept row still refuses deleting its listing (23503);
- 156's rollback refuses while a waiver is recorded (exit 3, nothing changed), otherwise removes every 156 object (census back to `35|121|37|46`, the 156 `gone` condition true) and 156 re-applies cleanly; negative control: a 156 rollback that leaves `client_shows_proof_disclosure()` behind keeps the ledger row (guarded delete) and fails the post check (exit 4).

| Step | rc |
|---|---|
| R0 check pre154 | 0 |
| R1 apply 154 | 0 |
| R2 apply 154 again (negative) | STOP 3 |
| R3 rollback 154 | 0 |
| R4 rollback 154 again (negative) | STOP 3 |
| R5 re-apply 154 (via `alt_pre` rb154) | 0 |
| R6 apply 155 | 0 |
| R7 apply 156 | 0 |
| R8 split (delete 156's ledger row) → R8b `--ledger-only` resume | 0 |
| R8c `--ledger-only` again (negative) | STOP 3 |
| R9 step hide | 0 |
| R10 hide again (negative) | STOP 3 |
| R11 step unhide | 0 |
| R12 step hide | 0 |
| R13 check post_hide | 0 |
| R14 rollback 156 with rows hidden | 0 |
| R15 rollback 155 | 0 |
| R16 rollback 154 (113 rows kept) | 0 |
| R18 apply 154 with kept rows (negative) | STOP 3 |

## Order (each step is a separate owner approval)
1. Predictions are registered in `expected/` (done). LOCALDB rehearsal (done, above). D reviews the package.
2. Fresh logical backup and local restore test. The owner enters the DB password. The private scripts are adapted from 152's. Adapt the guard to "154 absent, ledger 165".
3. `MODE=PROD CONFIRM_REF=hqycwntpfoztoinemqns TRANSPORT=http python3 pkg.py probe` must return `same_txn=true`.
4. `pkg.py apply 154`, then `apply 155`, then `apply 156`. Each does a prestate check, sends one request, then runs a post check.
   - Exit 3: nothing was sent.
   - Exit 5: do not resend; read the state.
   - Exit 4: STOP.
5. Verify. A runs an MCP read-back and D gives an independent verdict.
6. `pkg.py step hide`, the data step: post equals `post_hide.txt`, with anon and non-party counts 0 and money hashes unchanged.
   **Run it BEFORE any new listing is created** — including the admin's waived listings that 156 exists for. The step hides exactly the 113 preimage ids and then asserts that anon and a non-party see 0 listings, so a new public listing would make it fail; its prestate check (`post156.txt`: `listings_rows=113` and the listings hash) already stops it with exit 3, nothing sent, if any listing was created or changed after 156. New listings (waived or not) come after step 7.
7. Verify again. F checks the web as anon and as a fresh non-participant (allow ~12 min of CDN staleness on `/api/public/events` and `/sitemap.xml`); C checks the app after a cold start.

**Client gate:** C's N1 native build (`v3/rc9-n1-is-public-20261015`, which sends `.eq('is_public', true)` from Home, Explore, the public profile and the Realtime re-read) must not ship before step 4 has applied THIS 154 (with `is_public`) to production. Against a database without the computed field, PostgREST answers every such read with 400 (42703). The first freeze of 154 did not carry it.

**Disclosure header (156):** once 156 is applied, a bid or a new Buy Now hold on a waived listing needs `x-snatchit-caps: proof-disclosure-v1`. RC9 (`src/config/clientCapabilities.ts`, on every request) and web #108 (the cookie server client) send it; builds 25/27 do not, so they get "Not available" / "Reservation failed — This listing needs the latest Snatch It app…" on waived listings only. Non-waived listings are unaffected. No waived listing exists until the admin creates one after step 7.

## Reported, not fixed by this package
- Public auction-media cover URLs stay fetchable, and the bucket is listable by anon.
- Running old-app sessions keep already-loaded rows until refresh or relaunch.
- `/_next/image` caches covers for 4 h.
- `proof_of_ownership_path` is readable on public listings (pre-existing).
- 156's `proof_waiver_reason` and `proof_waived_by` are readable through PostgREST like every listings column (clients never display them). `proof_waived_by` always equals `seller_id`, and the reason is neutral operator text (for example "Owner inventory; tickets held by Snatch It"), so nothing private is exposed; write it that way.
- **3 live pending PaymentIntents on legacy listings remain confirmable by their original buyer — owner decision.** Hiding does not cancel a PaymentIntent and 154 changes no money state. Database context (read-only, 2026-10-15 04:2xZ): 11 `payments` rows are `pending` (9 buy_now on 8 listings, 2 auction on 1 listing); which PaymentIntents are still live is a Stripe-side fact, not re-read here.
- **Existence leak via RPC error text for hidden ids — accepted minor.** A caller who already holds a hidden listing's uuid gets that listing's own refusal text from the RPCs (for example `reserve_buy_now` → "This auction has ended." / "This listing has been cancelled.", a bid → the same), not "Listing not found.", so the text confirms the id exists. It reveals nothing else, and `listing_is_public(id)` already answers the same question.
- A seller who tries to delete one of their hidden legacy listings (native "Delete failed" alert, web seller listings) sees Postgres' raw foreign-key text (23503 naming `listing_visibility_listing_id_fkey`). Only the sellers of the 113 legacy test/beta listings can hit it; the delete is correctly refused.
- The proof-required rule checks that a proof path is present, not that the storage object exists: a client can still send an arbitrary string.
- Native builds older than 25 were not checked for the proof path (the coordination note says builds 25+ and RC9 always send one; this tree's `CreateListingScreen` does); a build that sent none would now get `Upload proof of ownership.`.
- `e32d0aeb` is an onboarded, phone-verified non-admin account that can still create public listings.
- `listing_is_public(id)` is an anon RPC, and `is_public(listings)` is the same boolean as a computed field. Either tells a caller who already holds a listing uuid whether that listing is hidden.
- The recorded winner of an ended, unpaid hidden auction can still pass create-payment-intent's auction-mode precondition (a pre-existing obligation of a private party; no new party can become a winner because bids are refused). Production at the re-read: 0 such rows among the 113 (the two `active/ended` rows have no winner; every row with a winner is `sold` or `cancelled`).
- On builds ≤ 27, an account that took part in a hidden listing (seller, buyer, bidder) still sees it in Home "Recently sold" and "Ended"; nobody else does. The next native build filters with `is_public` (see the client gate above).

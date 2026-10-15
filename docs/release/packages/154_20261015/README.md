# Migrations 154, 155, 156 + the legacy-listing data step: production package (A, 2026-10-15)

**Owner authorisation (A's chat, 2026-10-15):** all existing listings leave public access on every surface and every build; private payment, refund, transfer, dispute and order history is preserved; no money state changes; 72 h auctions; an explicit, recorded owner proof waiver for the admin's own listings, never marked verified. Spec: `sprint-control/SPEC_154_LISTING_VISIBILITY.md`.

**Nothing here is authorised to run against production yet.** Each step below (backup, probe, each apply, the data step, any rollback) needs the owner's own instruction in their own turn. This package never runs `db push`, never uses MCP `apply_migration`, and never touches 121/125/126.

## Identity
Branch `fix/154-listing-visibility-20261015` from the gate `release/production-gate-20260918` @ `6f982f36`. Registry numbers 154/155/156, pgTAP 221/222/223 (153 is taken and parked; the authoritative registry is on `origin/release/candidate-20260918`).

| Frozen file | Blob | md5 | Bytes |
|---|---|---|---|
| `migrations/20261015000000_listing_public_visibility.sql` (154) | `a4d594c5` | `c0be8b08c6af36473fd6e1782056221d` | 25,036 |
| `migrations/20261015000100_listing_duration_72h.sql` (155) | `51684cc7` | `51ce810d5b85c4a548d872b5f7a61f9a` | 5,942 |
| `migrations/20261015000200_listing_proof_owner_waiver.sql` (156) | `9b5a1a16` | `03f5928373b3c5b61b4bb606ac99ef1e` | 8,790 |
| `rollbacks/20261015000000_…_rollback.sql` | `0d7a96f7` | `81836489db21a3dbfdfb0c9702a9b6ba` | 7,208 |
| `rollbacks/20261015000100_…_rollback.sql` | `c654fadd` | `37dfa563a26afc685f69854bcf46bc75` | 1,843 |
| `rollbacks/20261015000200_…_rollback.sql` | `4e94d618` | `2abc7bdf5949b479a666a8e76db92c48` | 1,965 |

**Re-frozen 2026-10-15 after the 154/155 review** (findings: the hidden-row Buy Now hole, the reservation-sweep wedge,
the missing ADDENDUM 2 objects). 154 and 155 and their rollbacks changed; 156 is byte-identical to the first freeze.
Everything derived from them was regenerated: `frozen.sha256`, `pkg.py` (154/155 ledger guards), `predict.py`
(function constants, census deltas, new keys), `sql/state.sql` (new keys), `sql/hide_legacy.sql` (widened live check),
`expected/*` (production `pre154.txt` RE-READ, read-only, then re-predicted), `rehearsal/lists_*.json`,
`rehearsal/expected_local/*`, `rehearsal/out/*` and the LOCALDB rehearsal log.

`frozen.sha256` holds the sha256 of all six. Each frozen file is byte-identical to its copy under `supabase/`.

**Runner:** `pkg.py`, sha256 `6e2158996bc5031866f60b5cd671aa2a243401c7958de1ee7a2afb7206585fab` (first freeze `1abf0951…`; the only change is the
154/155 `gone` conditions of the guarded ledger delete, which now also require `is_public(listings)` and
`set_listing_ends_at_from_duration()` to be gone). Copied from `../152_20261013/pkg.py` (sha256 `02537f62…`, executed 2026-10-13). Same transport: one Management API `database/query` POST per request, carrying the file bytes, then the ledger INSERT `(version, name, statements = ARRAY[raw file], created_by 'claude-a/owner-authorised-N')`. The changes are listed in its docstring:
- MIG entries 154 → 155 → 156, where each one's pre file is the previous one's post file;
- `state` is two read-only requests: `sql/state.sql` and `sql/state_anon.sql`;
- `rb_post` / `rollback_ignore`, and `alt_pre` for 154;
- the `step hide|unhide` data step;
- `PKG_EXPECTED`.

**The private production wrapper must be re-pinned to this hash before use.** 152's wrapper is `private-evidence/A-preapply-152-20261013/scripts/run_pkg152_prod.sh` (keychain token, never printed). This lane was told to work only in this worktree, so it has not written the 154 copy.

## What each step does
- **154:** adds `public.listing_visibility` (RLS on, no policies; service_role SELECT/INSERT/DELETE only).
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
  - Clients cannot change a waiver later.
  - `current_user_is_admin()` is authenticated-execute.
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
| apply 154 | 50,278 | `2c3a9bda266c018dc92325d9f2d367212ed7c806b1e5dc8ab43c6b80592bdf4e` |
| apply 155 | 12,085 | `08e9746595f464bdbe0ae9ca9b1666d8447a4d76268d082ce3c24b7c729aa5d5` |
| apply 156 | 17,787 | `c264689831e5f5bf1cc6f7c3c62d04de44f92a9189c3e0733357d640504f5e6b` |
| step hide | 9,310 | `2a2fa64b05fe1b5189d5ab8d35d75dc999abb9301ee7be380609b3e92ab26a6b` |
| step unhide | 5,758 | `a0f71d8d4d879b0b981834df2ccce4935e8626debdf68a243403396c3e14d969` |
| rollback 156 / 155 / 154 | 2,373 / 2,214 / 7,968 | `a1613101…` / `86b4f847…` / `bae43964…` |
| ledger-only 154 / 155 / 156 | 25,240 / 6,141 / 8,995 | `32107c42…` / `71326705…` / `e4b2ada3…` |
| rollback 154 --ledger-only | 760 | `e60e8611…` |

The LOCALDB rehearsal sent exactly these bytes. The request hashes in `rehearsal/run_local_20261015.log` equal the DRY hashes.

## Transaction shape
- Each migration file carries its own `BEGIN; SET LOCAL lock_timeout = '3s'; … COMMIT;`, so the appended ledger INSERT is a second implicit transaction. If the file fails, nothing commits. The only possible split is objects present with no ledger row; `apply N --ledger-only` resumes that case (rehearsed as R8/R8b).
- `hide_legacy.sql` is one transaction (BEGIN … COMMIT). Every assertion RAISEs, so it is all or nothing.

## Expected states (`expected/`)
- **`pre154.txt`**: production, read-only, 2026-10-15.
  - It came from `state.sql` (`SET TRANSACTION READ ONLY`) plus `state_anon.sql` (`SET LOCAL ROLE anon` / `authenticated` in a read-only transaction), both through MCP `execute_sql`.
  - First read ~02:3xZ (a re-read at 03:01:59Z hashed the 59 catalog/data lines to `c42a43b9…`). RE-READ after the review fixes with the extended `state.sql`: all 75 lines equal the file; every key of the first read is unchanged (money/listing hashes, census, grants, anon counts).
  - Values: ledger 165 / max `20261013000000`; census `34|116|37|43`; 113 listings, 0 live; `listings_select_all` / `bids_select_all` `USING (true)`; anon sees 113 listings and 98 bids; listings/bids/payments/transfers owned by `postgres` with RLS on and no FORCE; `owner_role=postgres|super=false|bypassrls=true`.
- **`post154.txt`, `post155.txt`, `post156.txt`, `post_hide.txt`, `rb154.txt`** are PREDICTIONS. `rehearsal/predict.py` derives them from `pre154.txt` plus `rehearsal/lists_prod.json`.
  - `lists_prod.json` came from one read-only production query (`rehearsal/lists_query.sql`, re-run after the review fixes): the existing grant, trigger and listings-column rows plus the literal rows 154/155/156 add (now including `is_public`'s two EXECUTE grants and 155's trigger), re-hashed.
  - The new-object constants come from a fresh local PG 17 replay of the frozen files. Production runs 17.6.
  - Ownership keys are derived, not assumed: the three readers are predicted owned by the owner of listings with that role's RLS bypass (`fnown_*=postgres|owner_of_listings=true|bypasses_rls=true` in production); a different transport role makes the post check FAIL (exit 4) instead of shipping a recursion risk.
  - Predicted production post-156 census `35|123|37|47` (= ci.yml Gate-2), `hidden_open_or_held=0`.
  - Every fixed money/listing hash is predicted UNCHANGED.
  - The predictor was registered before the first local apply. Its local outputs (`rehearsal/expected_local/`) then matched every observed post-state (R1, R5, R6, R7, R9, R11, R12, R13 and the rollbacks).

### What `state.sql` pins (new vs 152)
- `pol_<table>.<policy>` for listings, bids and listing_visibility: cmd, roles, md5(qual), md5(with_check).
- `anon_listings`, `anon_bids`, `nonparty_listings`, `nonparty_bids` (in `state_anon.sql`).
- `lv_table` / `lv_rows`.
- `hidden_open_or_held`: hidden rows that are open (what `reserve_buy_now` accepts) or under a live hold; must stay 0.
- `rls_<table>` (owner, RLS, FORCE) for listings, bids, payments, transfers, listing_visibility; `owner_role` (the owner of listings: super / BYPASSRLS); `fnown_<reader>` for `listing_is_public`, `listing_private_party`, `is_public`: the no-42P17 guarantee read back.
- FIXED HASHES (count|md5 over `to_jsonb` rows, ordered `COLLATE "C"`, TimeZone UTC) of:
  - payments, transfers, payment_refunds, payment_refund_state, payout_attempts, payout_decisions, disputes, bids;
  - listings minus `updated_at` and minus 156's three waiver columns.

  pre == post on these proves no money or listing state moved. A live production write (for example a webhook updating a pending payment) between pre and post makes the post check FAIL (exit 4) without the migration being at fault: read the state and compare before any further step.
- `grants_anon_authenticated` keys routine grants by `name(argtypes)` from proacl. 152 used `specific_name`, which embeds OIDs and cannot be predicted.

## Rollbacks
| Rollback | What it does | Rows kept or refused |
|---|---|---|
| 156 | Drops the guard, `current_user_is_admin()`, the checks and the three columns | **Refuses while any listing carries a waiver**: an archival record, and the columns would be client-writable without the guard. Rehearsed: refuses with a waiver (exit 3, unchanged); the guard is load-bearing (without it the rollback destroys the waiver) |
| 155 | Drops `trg_listing_ends_at_from_duration` + `set_listing_ends_at_from_duration()` (ends_at is client-set again) and restores `{1,3,6,12,24,48}` | **Refuses while any listing has 72 h** |
| 154 | Restores both `USING (true)` policies (**re-exposes every hidden listing**) and 031's trust-stats body (functiondef md5 back to `23719c73…`); drops `is_public(listings)` (a build filtering `.eq('is_public', true)` gets 400 again) | **Keeps `listing_visibility` and its rows** (inert). A later clean re-apply reuses the table and refuses while a kept row names an open or held listing (rehearsed locally both ways, with a negative control: the first freeze's predicate re-applied over an open kept row) |

Order: 156 → 155 → 154. The runner's rollback guards ignore only the data-step keys, so the schema can be rolled back with the 113 rows still in place.

## Local rehearsal (`rehearsal/run_local.sh` → `run_local_20261015.log`)
**Database.** `a154_pkg_rehears` was REBUILT for the re-freeze (same recipe; fixture timestamps differ, so the local fixed hashes differ from the first run) from:
- a clone of `pkg151_rehears` (ledger 164);
- plus 152's executed apply request (sha256 `ffc020a0…`, ledger 165);
- plus `rehearsal/fixture_local.sql` (synthetic rows carrying the 113 preimage ids, 0 live, 5 bids, 2 payments, 1 transfer).

Each step's expected exit code was registered in the script before the run. **Result: 0 unexpected exit codes.**

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
7. Verify again. F checks the web as anon and as a fresh non-participant (allow ~12 min of CDN staleness on `/api/public/events` and `/sitemap.xml`); C checks the app after a cold start.

**Client gate:** C's N1 native build (`v3/rc9-n1-is-public-20261015`, which sends `.eq('is_public', true)` from Home, Explore, the public profile and the Realtime re-read) must not ship before step 4 has applied THIS 154 (with `is_public`) to production. Against a database without the computed field, PostgREST answers every such read with 400 (42703). The first freeze of 154 did not carry it.

## Reported, not fixed by this package
- Public auction-media cover URLs stay fetchable, and the bucket is listable by anon.
- Running old-app sessions keep already-loaded rows until refresh or relaunch.
- `/_next/image` caches covers for 4 h.
- `proof_of_ownership_path` is readable on public listings (pre-existing).
- 156's `proof_waiver_reason` and `proof_waived_by` are readable through PostgREST like every listings column. `proof_waived_by` always equals `seller_id`.
- `e32d0aeb` is an onboarded, phone-verified non-admin account that can still create public listings.
- `listing_is_public(id)` is an anon RPC, and `is_public(listings)` is the same boolean as a computed field. Either tells a caller who already holds a listing uuid whether that listing is hidden.
- The recorded winner of an ended, unpaid hidden auction can still pass create-payment-intent's auction-mode precondition (a pre-existing obligation of a private party; no new party can become a winner because bids are refused). Production at the re-read: 0 such rows among the 113 (the two `active/ended` rows have no winner; every row with a winner is `sold` or `cancelled`).
- On builds ≤ 27, an account that took part in a hidden listing (seller, buyer, bidder) still sees it in Home "Recently sold" and "Ended"; nobody else does. The next native build filters with `is_public` (see the client gate above).

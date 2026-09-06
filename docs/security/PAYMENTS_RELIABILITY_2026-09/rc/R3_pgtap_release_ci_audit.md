# Release-engineering audit — draft PR #54 (`fix/payments-reliability`)

Subject: worktree `/Users/josetascon/snatchit-pay` @ `31128c160fbec88c37f4628547baa3149f2dbea7` (verified `git rev-parse HEAD`).
Scope: read-only on repos; local scratch DBs `snatchit_rev_rel_rehearsal`, `snatchit_rev_rel_base_rehearsal`. No Supabase/Stripe/network.
Date: 2026-09-06.

---

## 1. pgTAP "plan=597 ok=595" reconciled

### 1.1 Reproduced

```
scripts/rehearsal_reset.sh snatchit_rev_rel_rehearsal      -> REPLAY OK: 92/92 ... GATE-2 tables=30 functions=84 policies=37 triggers=30
scripts/rehearsal_test.sh  snatchit_rev_rel_rehearsal      -> TOTAL plan=597 ok=595 not_ok=2 FAILURES
                                                              RESULT: pgTAP suite matches the expected local baseline.
```
(597 = the 603 planned assertions across 22 files minus `000_helpers.sql`'s `plan(6)`, which `scripts/local/runtests.sh` excludes.)

All 21 assertion files pass except one:

| file | test | name | have | want |
|---|---|---|---|---|
| `supabase/tests/132_replay_parity.sql` | 8 | D-5/8 (parity): schedule, database, username, active and exact command bytes match production jobid 10 | `schedule=*/5 * * * *\|database=snatchit_rev_rel_rehearsal\|username=postgres\|active=true\|command=select public.sweep_auth_password_changes();\|len=44\|md5=a8688b5b…` | same string with `database=postgres` |
| `supabase/tests/132_replay_parity.sql` | 9 | D-5/9 (no duplicate, no drift) | `canonical=0 total=1` | `canonical=1 total=1` |

Both assertions hard-code `"database" = 'postgres'` (`132_replay_parity.sql:238-244` and `:262`). `cron.job."database"` is whatever `current_database()` was when `cron.schedule()` ran (real pg_cron; and the harness stand-in populates it identically — `scripts/rehearsal_bootstrap.sql:118`). Every field other than the DB name matches byte-for-byte (schedule, username, active, command, len=44, md5). The only difference between have/want is the database name.

**Classification: environment-dependent (database-name artifact), not a behavioural deviation.** The rehearsal harness refuses a DB named `postgres` (`scripts/rehearsal_reset.sh` `case "$DB" in postgres|template0|template1) die`), so it can never satisfy the literal.

### 1.2 Why CI is green while the harness is not

- CI's `db` job runs the chain on the Supabase CLI local stack whose database IS named `postgres` (`DB_URL: postgresql://postgres:postgres@127.0.0.1:54322/postgres`, `.github/workflows/ci.yml` db job env) with real pg_cron. `current_database()` = `'postgres'` there, so D-5/8 and D-5/9 pass legitimately — CI is not masking anything.
- CI's pgTAP gate (`ci.yml:300-310`, summary step `:315-420`): `supabase test db --local | tee` under `set -o pipefail`; the summary step fails on `Result != PASS`, any `Parse errors: Bad plan`, `tests_ran != planned`, and enforces masking ratchets `MASK_MAX_TODO_FAILURES/TODO_CALLS/MASKED_ASSERTIONS/SKIP_CALLS/TODO_BLOCKS` = **0/0/0/0/0** (`ci.yml:335-339`). There is **no per-file allowlist and no `known_notok` in CI** — a `not ok` in 132 would flip pg_prove to `Result: FAIL` and fail the job.
- The `known_notok()` allowlist exists only in the local harness (`scripts/rehearsal_test.sh`: `132_replay_parity.sql) echo 2`), and it accepts exactly `not_ok=2` for that file with zero psql errors and plan == ran. It is an honest local delta, but note it is **count-based, not name-based**: a genuine regression in any two other 132 assertions coinciding with the two db-name assertions passing would be indistinguishable locally (not possible on this harness since D-5/8-9 can never pass here, but the check is structurally weak).

**Would CI catch a genuine regression in 132?** Yes. CI compares the full string (including command bytes/md5) against the literal and has no allowlist; any drift in schedule/command/username/active/duplication fails the job.

### 1.3 Proposed fix (removes the environment dependence, keeps every behavioural check)

Do not hard-code `'postgres'`; compare against the database the chain actually ran in — which is exactly what pg_cron records. Two edits in `supabase/tests/132_replay_parity.sql`:

```sql
-- D-5/8: expected string parameterised by current_database(); every other field stays literal.
SELECT is(
  (SELECT string_agg(
            format('schedule=%s|database=%s|username=%s|active=%s|command=%s|len=%s|md5=%s',
                   j.schedule, j."database", j.username, j.active::text, j.command,
                   length(j.command), md5(j.command)),
            ' ;; ' ORDER BY j.jobid)
     FROM cron.job j
    WHERE j.jobname = 'sweep-auth-password-changes'),
  format('schedule=*/5 * * * *|database=%s|username=postgres|active=true|command=select public.sweep_auth_password_changes();|len=44|md5=a8688b5b2add782b9a988d1f3850cd07',
         current_database()),
  'D-5/8 (parity): schedule, database (= the database the chain ran in), username, active and the exact command bytes match production jobid 10');

-- D-5/9: same substitution in the canonical filter.
              WHERE schedule   = '*/5 * * * *'
                AND "database" = current_database()
                AND username   = 'postgres'
                AND command    = 'select public.sweep_auth_password_changes();'
                AND active),
```

Effect: in CI and production (`current_database()='postgres'`) the expected string is byte-identical to today's literal, so nothing is weakened; a job scheduled into a different database still fails (its `"database"` ≠ `current_database()`). After this, `known_notok()` in `scripts/rehearsal_test.sh` can be deleted and the harness becomes zero-delta. The `README.md`/bootstrap comment "do not fix by hardcoding 'postgres'" is honoured — this hard-codes nothing.

Also fix two stale strings surfaced by the run: `scripts/rehearsal_reset.sh` footer prints `CI baseline: tables=27 functions=70 policies=37 triggers=26` (actual `ci.yml` EXPECT_* is 30/84/37/30); `04_RELEASE_PLAN.md` §4 says "30 / 83 / 37 / 28" (stale by one revision).

---

## 2. Release sequence audit (`04_RELEASE_PLAN.md` §1) against deployed code

Deployed sources read: `origin/main:supabase/functions/{stripe-webhook,confirm-payment,enforce-transfer-expiry}/index.ts`; scratchpad `deployed/{create-payment-intent,confirm-and-release,delete-account}` (prod v45/v34/v18, Phase-2 guards). Branch edges: `supabase/functions/*` at HEAD.

Function signatures called by old edges — unchanged by P1–P3 (verified in the three migrations): `mark_listing_sold(uuid,uuid)`, `complete_auction_payment(uuid,uuid)`, `reserve_buy_now(uuid,uuid,integer)`, `record_transfer_payout(uuid,text)` (P3 header: UNTOUCHED), `ensure_transfer_exists`, `release_reservation`, `freeze_transfer_for_dispute`, `mark_transfer_reversed`, `enforce_transfer_expiry`, `get_auto_release_candidates`, `apply_*`, webhook claim/complete/fail RPCs. P2/P3 only ADD functions/tables/triggers/one column.

### 2.1 State A — P1 applied, all old edges (P1-a → P1-c)

| Caller | What runs | Compatible? |
|---|---|---|
| old `stripe-webhook` `payment_intent.succeeded` | `payments UPDATE status='succeeded' … .neq('status','succeeded')` (`origin/main` webhook :268-272) **before** `rpc(mark_listing_sold / complete_auction_payment, {p_listing_id, p_user_id: metadata.buyer_id})` (:377-405) as service_role | **Yes.** New wrapper: `auth.uid()` NULL + `request_is_service_role()` → caller = `p_user_id`; finds the just-promoted `succeeded` row for that buyer/listing/mode → core settles + creates transfer. The old webhook then inserts the transfer itself (:435) → 23505 treated as benign. Two new transient refusals exist: (a) `complete_auction_payment` raises "already reserved by another buyer" while a foreign Buy-Now hold is live (≤10 min) → webhook `finish(false)` → 500 → Stripe retries; (b) `'unfulfillable'` → "already been sold" → 500 loop until review. (a) is bounded; (b) matches prior behaviour (old wrapper raised "not reserved by you"). |
| old `confirm-payment` (mobile/web) | direct `payments UPDATE status='succeeded'` (:215-224), then direct `transfers INSERT` | Yes — no wrapper called; unchanged. Mobile then calls `mark_listing_sold`/`complete_auction_payment` + `ensure_transfer_exists` (`src/screens/checkout/CheckoutNative.tsx:285-366`; web `web/src/lib/checkout.ts:162-171`) → wrapper finds the succeeded row → `settled`/`already_settled`. |
| mobile/web `reserve_buy_now(…, p_minutes=10)` (`ListingDetailScreen.tsx:776`, `web/src/lib/checkout.ts:55-58`, `APP_CONFIG.RESERVATION_MINUTES=10`) | signature intact; `p_minutes` ignored, server TTL 10 min (= what clients send) | Yes. New refusals: `'This listing has already been sold.'` (matches `/already sold/` regex), `'Too many reservation attempts…'` (generic alert). New `check_rate_limit(caller,'reserve_buy_now',20,600)` fail-closed: 20 taps / 10 min per user. |
| old `create-payment-intent` v45 | requires `listing.status==='reserved'` (deployed :331), keeps Phase-2 `kernel.is_deletion_pending` guard (:265-277), `payments UPDATE status='failed'` on stale pending (:467) | Yes. |
| old `confirm-and-release`/`enforce-transfer-expiry`/`delete-account` | untouched paths | Yes. |

Verified independently: baseline (main-only, 89 files) census/hash `27|69|37|24|c151beb8…`; after P1 alone `27|70|37|24|a594667c…` (matches `05_VERIFICATION.md` §1).

### 2.2 State B — P1+P2 applied, old edges (P2-a → P3-b)

Nothing deployed calls `settle_verified_payment` or `get_unsettled_payments`. `cleanup_expired_reservations` (cron) now skips paid listings (N1). Old webhook keeps settling via `mark_listing_sold` (payment-gated by P1). Compatible; the plan's claim "no window in which a paid listing is unsettleable" holds.

### 2.3 State C — P1+P2+P3 applied, old edges (P3-b → P3-d)

P3 adds `trg_guard_payment_transitions` (BEFORE UPDATE on `payments`), partial UNIQUE `transfers_stripe_transfer_id_uniq`, `payout_attempts` (+ `guard_payout_attempt_columns`, append-only), `payment_refunds`, `payments.amount_refunded_cents`, `account_deletions`, RPCs.

| Old caller / write | Guard verdict | Compatible? |
|---|---|---|
| webhook `succeeded` claim `.neq('status','succeeded')` — `pending/processing/failed → succeeded` | allowed | Yes. `refunded → succeeded` now RAISES → `lookupErr` → 500 → Stripe retries up to 3 days (previously it silently overwrote a refund). Bounded noise; ops must resolve via `get_incomplete_webhook_events`. |
| webhook `payment_failed` `.neq succeeded/refunded` → `failed` | allowed | Yes. |
| webhook `charge.refunded` / dispute `lost` → `refunded`, `refunded_at`, `stripe_refund_id` (`.neq('status','refunded')`) | `succeeded→refunded` allowed; refund refs set-once satisfied because filter excludes already-refunded | Yes. (`amount_refunded_cents` stays NULL — old code does not write it; P2 contract tolerates NULL.) |
| old `confirm-payment` UPDATE with **no status predicate** (:215-224) | same-status no-op ok (`paid_at`/`payment_method` unguarded); `refunded→succeeded` RAISES → logged, still 200 | Yes (desired). |
| old `create-payment-intent` `pending→failed` | allowed | Yes. |
| old `enforce-transfer-expiry` Phase 1/1b (`succeeded→refunded` + refs) and quarantine `stripe_livemode=false` | allowed / unguarded | Yes. |
| old `confirm-and-release` v34 & expiry Phase 2b: `createSellerPayout` (old key `payout_<transfer>_<destination>_src`, no `transfer_group`) → `record_transfer_payout(uuid,text)` | untouched RPC; partial unique on `stripe_transfer_id` only bites on a genuine duplicate tr_ id | Yes — old edges write no `payout_attempts` row. |
| old `delete-account` v18 (tombstone, kernel RPC only) | no P3 table touched | Yes. |
| `delete_account_cleanup` (0563) sentinel rewrite | honoured via `app.bypass_transfer_guard` party-only branch | Yes. |

### 2.4 State D — edges deployed (P3-d) — findings

1. **Branch edge sources regress production (BLOCKER, acknowledged in §0 but unresolved).** `supabase/functions/delete-account/index.ts` at HEAD is the physical-delete variant (`account_deletion_blockers` gate → `delete_account_cleanup` → `auth.admin.deleteUser` at :320); production v18 is the OR-17 tombstone flow (`kernel.request_account_deletion`). Branch `create-payment-intent` and `confirm-and-release` contain **no** `kernel`/`is_deletion_pending` guard (grep empty) while deployed v45/v34 do. Deploying P3-d from this branch drops the Phase-2 F-5 guards and the tombstone flow. Forward-port must happen before any edge deploy.
2. **Legacy orphan double-pay on first new-code payout (HIGH).** New protocol (`_shared/payouts.ts:304-345`) reconciles only by `GET /v1/transfers?transfer_group=<transfer_id>` + `metadata.attempt_id`. Old transfers carry `metadata[transfer_id]` but **no `transfer_group`** (deployed `payouts.ts:133-145`). A legacy transfer where Stripe accepted the POST but `record_transfer_payout` never ran ("Payout sent but record update failed", v34 :591-604; expiry :678-700) leaves `transfers.stripe_transfer_id IS NULL`; the new code's `claim_payout_attempt` sees no open attempt, searches the (empty) group, and POSTs under a **new** key `payout_<id>_a1` → a second real transfer. `07_DRAFT_PRS.md` PR-3 mentions a "pre-enable query for legacy transfers" but `04_RELEASE_PLAN.md` §1 has no such step. Must-do before P3-d: list Stripe transfers (all, or by created window) and reconcile every `transfers` row with `status IN ('buyer_confirmed','auto_released') AND stripe_transfer_id IS NULL` against `metadata[transfer_id]`; backfill via `record_transfer_payout` where a tr_ exists.
3. `payment_intent.canceled` (P2-d) is correctly sequenced last; the old webhook would ack unknown types anyway.
4. Mobile/web response contracts: new `confirm-payment` returns a superset; `payout_status:'processing'` additive — consistent with §2 of the plan.

---

## 3. Rollback safety

Rehearsed here (not just read): full replay → rollback P3 → P2 → P1 → re-apply P1..P3, census `tables|functions(excl. ext)|policies|triggers|md5(all public function defs)`:

```
full          30|84|37|30|1c3ffd668ffdb96d14e28eb469fbeda7
-P3           27|72|37|24|156ca673bf69483a0f03a819c32d7c13
-P2           27|70|37|24|a594667c8b017069f3d1f7566163f278
-P1           27|69|37|24|c151beb80ef502307a800e6df2b82556   == independent main-only replay (89 files)
re-apply x3   30|84|37|30|1c3ffd668ffdb96d14e28eb469fbeda7   (idempotent; only "trigger does not exist, skipping" NOTICEs)
```
All four hashes equal those in `05_VERIFICATION.md` §1. Function bodies are restored verbatim.

### 3.1 What each rollback does to data created by the new code

| Object | Rollback effect | Consequence |
|---|---|---|
| P1 — reservations made under 10-min rule | rows untouched | none |
| P2 — `webhook_retries` review rows (`settle_verified_payment` rpc_name, `unknown_payment:/binding_mismatch:/unfulfillable:*`) | survive | harmless; but `get_unsettled_payments` is dropped so nothing consumes them; old `cleanup_expired_reservations` (000 body) again **re-lists paid listings** whose hold lapsed (N1 reopened) |
| P3 — `payout_attempts` | **DROP TABLE** | attempt ledger (audit trail, idempotency keys, states) destroyed |
| P3 — `payment_refunds` | **DROP TABLE** | per-refund ledger (partial refunds, dispute chargebacks with dispute id) destroyed |
| P3 — `payments.amount_refunded_cents` | **DROP COLUMN with values** | partial-refund amounts lost; `payments.status/refunded_at/stripe_refund_id` written by `record_payment_refund` survive (only full refunds flip `status`) |
| P3 — `account_deletions` | **DROP TABLE** | phase ledger lost; a user mid-deletion (`cleaned` but auth user not deleted) has no record; old tombstone edge handles a fresh request |
| P3 — `transfers.stripe_transfer_id/payout_released_at` set by `record_payout_attempt_result` | survive | good — the money fact stays on `transfers` |
| P3 — `payout_decisions` rows (`PAID_DURING_DISPUTE`, `DUPLICATE_TRANSFER`) | survive | good |

**Does P3 rollback lose financial facts? Yes** — three tables + one column, including the only record of partial refunds and of which attempt produced which `tr_`. The rollback header says "export first" but no export procedure/queries exist in `04_RELEASE_PLAN.md` §3.

### 3.2 Old code against surviving data — the open-attempt double-pay

Scenario: at rollback time a `payout_attempts` row is `requested` or `unknown` (POST sent, response lost). `transfers.stripe_transfer_id` is NULL (only `record_payout_attempt_result` sets it). After redeploying old `confirm-and-release` v34 / expiry v36:
- old code checks `transfers.payout_released_at`/`stripe_transfer_id` (NULL) → proceeds → POST `/v1/transfers` with key `payout_<id>_<dest>_src` ≠ `payout_<id>_a<n>` → Stripe creates a **second** transfer → **double-pay**. `record_transfer_payout` then records tr_2; tr_1 is invisible to the DB (the attempt row is gone if P3 was rolled back; if only edges were rolled back, the surviving attempt row will later be reconciled by new code as `DUPLICATE_TRANSFER → reversal_required`, i.e. detected but not prevented).
- This is not covered by `04_RELEASE_PLAN.md` §3.

Same hazard in the P2-rollback-with-P2-edges-deployed order (documented: 500 on every `payment_intent.succeeded`), and P1-rollback-with-P2-present (documented: `settle_verified_payment` calls a dropped core).

### 3.3 Minimal recovery procedure (proposed; not edited)

Before ANY edge rollback or P3 rollback:
```sql
-- 0. Freeze: stop the payout cron (cron.unschedule of enforce-transfer-expiry) and take confirm-and-release offline (or 503 it).
-- 1. Open attempts that MUST be reconciled against Stripe before old code runs:
select a.id, a.transfer_id, a.attempt_no, a.state, a.idempotency_key, a.destination, a.amount_cents, a.requested_at
  from public.payout_attempts a where a.state in ('claimed','requested','unknown') order by a.claimed_at;
--    For each: GET /v1/transfers?transfer_group=<transfer_id>; if a transfer with metadata.attempt_id=<id> exists →
--    select public.record_payout_attempt_result(<id>, '<tr_>', 'succeeded', '{"reconciled":true,"by":"rollback"}');
--    else → select public.record_payout_attempt_result(<id>, null, 'failed_not_created', '{"reconciled":true}');
--    Repeat until the query above returns zero rows.
-- 2. Export (\copy … TO csv) before DROP:
\copy (select * from public.payout_attempts order by claimed_at)  to 'payout_attempts_<ts>.csv' csv header
\copy (select * from public.payment_refunds order by created_at)  to 'payment_refunds_<ts>.csv' csv header
\copy (select * from public.account_deletions)                    to 'account_deletions_<ts>.csv' csv header
\copy (select id, stripe_payment_intent_id, status, total, amount_refunded_cents, refunded_at, stripe_refund_id
         from public.payments where amount_refunded_cents is not null) to 'payments_refunded_<ts>.csv' csv header
-- 3. Post-rollback reconciliation (old schema): every transfer with money moved must carry its tr_:
select t.id, t.status, t.payout_released_at, t.stripe_transfer_id from public.transfers t
 where t.status in ('buyer_confirmed','auto_released','completed') and t.stripe_transfer_id is null;
--    cross-check each against the exported attempts CSV and Stripe (metadata.transfer_id); backfill with
--    select public.record_transfer_payout(<transfer_id>, '<tr_>');
-- 4. Partial refunds: rows in payments_refunded_<ts>.csv with amount_refunded_cents < total have NO representation in the
--    old schema — keep the CSV as the ledger of record and mirror them in Stripe dashboard notes; re-apply P3 restores the
--    column at NULL ("unknown"), so re-import is manual.
-- 5. Unresolved review queue survives P2 rollback: select * from public.webhook_retries where resolved is not true; work it by hand.
```
Order of operations for a P3 rollback: (0) freeze → (1) drain open attempts → (2) export → redeploy old edges → run rollback SQL → (3) reconcile → unfreeze.

---

## 4. CI coverage audit

`.github/workflows/ci.yml` (jobs `quality`, `db`, `web`, `deno-check`) and `migrations-guard.yml`.

| Check | Where | Blocking? | Finding |
|---|---|---|---|
| Typecheck / lint / `vitest run` (root `tests/**/*.test.ts` → all 13 new suites incl. settlement-*, payout-attempts, delete-account, refund-dispute-webhook) | `quality`, `vitest.config.ts` | yes (job fails) | OK |
| Packages parity vitest | `quality` | yes | OK |
| Fresh replay on pinned CLI 2.115.0 + discovery proof (files == applied, no dup prefixes) | `db` :115-175 | yes | OK |
| Gate-2 census EXPECT 30/84/37/30 (`ci.yml:206-209`) | `db` :176-190 | yes | **Matches** the fresh replay here (`GATE-2 tables=30 functions=84 policies=37 triggers=30`). |
| Privilege parity vs `supabase/ci/expected_grants.txt` (+ `parity_grants.sql`) — includes the 3 new tables (service_role only) | `db` :224-277 | yes | OK |
| Grant-decision register `assert_public_table_grant_decisions.sql` — new tables/functions recorded `no-client-access/-execute` | `db` :278-300 | yes | OK |
| pgTAP via `supabase test db --local` (runs `supabase/tests/*.sql`, i.e. 22 files incl. `120–124`) | `db` :300-310 | yes (pipefail + Result/badplan/planned checks) | OK |
| Masking ratchets all **0** (`MASK_MAX_*`), static parser + grep tripwires; tree has 0 `todo(`/`skip(`/`todo_start` | `db` :335-339, :655-818 | yes | OK. Stale comment at :333-334 still says "2 todo() calls masking 2 assertions". |
| Coverage floor `MIN_FILES=17`, `MIN_ASSERTIONS=305` (`ci.yml:418-419`) | `db` | yes but **not ratcheted** | Tree is 22 files / 603 planned. Deleting all five 12x suites (+298 assertions) keeps CI green. Raise to 22/603. |
| `deno check supabase/functions/*/index.ts` (Deno 2) | `deno-check` :911-914, no `continue-on-error` | yes | Covers all 11 entrypoints (every dir except `_shared` has `index.ts`); `_shared/*.ts` checked transitively only. |
| Migrations guard: immutability, name format, prefix-freeness, monotonic, `AUTODEPLOY-VERIFIED-OFF:` line | `migrations-guard.yml` | yes on PR (intentionally FAILS until owner fills the date) | OK by design. |
| Rollback scripts (`supabase/rollbacks/*.sql`) | — | **never executed in CI** (`grep rollbacks .github/workflows/*.yml` → none) | Gap: the reverse rehearsal exists only locally (§3 above / `05_VERIFICATION.md`). |
| Deployed-vs-branch edge parity (Phase-2 guards) | — | none | Gap: nothing in CI detects that branch edges drop the F-5/OR-17 behaviour (§2.4-1). |
| Branch protection making these checks required | GitHub settings | unverifiable offline | Memory note (2026-08-27): `main` had no protection/rulesets — must be confirmed before merge. |

Also: `web` job typecheck/lint/test/build blocking; `security.yml` npm-audit non-blocking (pre-existing).

---

## 5. Migration numbering

Production ledger (per `00_BASELINE.md`, memory): `000–075`, four `202607*/202608*` timestamps, Phase-2 `076–109`, `20260902003623_admin_relist_listing_rpc` (129 rows). Phase-2 branch `origin/feature/venue-native-and-product-v2` additionally carries `110–114` (not in prod).

Union of versions across `main`, this branch and the Phase-2 branch, sorted:
```
LC_ALL=C sort (bytewise) tail: …20260731224653 20260902003623 20260906100000 20260906110000 20260906120000
sort -n (numeric)        tail: …20260731224653 20260902003623 20260906100000 20260906110000 20260906120000
duplicate version prefixes: none        name collisions on phase-2 branch: none
```
- The three `20260906*` versions sort **after every applied version** under both orderings (14-digit vs 3-digit: `'2' > '1'/'0'` bytewise; 2.0e13 > 114 numerically) and after `20260902003623`. Prefix-free (guard §3b) and monotonic within the `ts` scheme (guard §4; latest base `ts` = `20260731224653`). Migrations-guard name regex satisfied.
- Because they exceed the remote maximum, `supabase db push` would treat them as pending **without** `--include-all` (unlike the `NNN_` files). But `db push` from this branch will refuse: the remote ledger holds `076–109` + `20260902003623` that this checkout lacks. And pushing from the Phase-2 branch would also apply `110–114`. The apply must therefore be from a checkout whose `supabase/migrations` equals prod's 129 files + these 3 (or SQL-editor apply + explicit `schema_migrations` insert of the 3 versions). This is the concrete form of `04_RELEASE_PLAN.md` §0 and belongs in §1.

---

## Blockers / Must-fix before release

1. **Branch convergence (release plan §0) is unresolved and the branch edges regress production**: `delete-account` is the physical-delete variant (`auth.admin.deleteUser`), `create-payment-intent`/`confirm-and-release` lack the Phase-2 `kernel.is_deletion_pending` guards. No edge may be deployed from this branch until forward-ported onto the Phase-2 code (or vice-versa). Also the migration apply path must be a checkout containing prod's 129 migrations (§5).
2. **Legacy orphan double-pay**: before P3-d, reconcile every `transfers` row with `stripe_transfer_id IS NULL` in a releasable status against Stripe (`metadata[transfer_id]`; old transfers have no `transfer_group`) and backfill with `record_transfer_payout`. Add this as an explicit step P3-c'.
3. **Rollback procedure incomplete**: `04_RELEASE_PLAN.md` §3 must add (a) drain/reconcile open `payout_attempts` (`claimed/requested/unknown`) before any edge rollback (otherwise old code re-POSTs under a different idempotency key → double-pay), (b) the export `\copy` set for `payout_attempts`, `payment_refunds`, `account_deletions`, `payments.amount_refunded_cents`, (c) the post-rollback reconciliation query. §3.3 above is a ready draft.
4. `AUTODEPLOY-VERIFIED-OFF: <date>` still a placeholder (guard fails by design) and branch protection status unknown — owner steps.

## Recommendations

- Apply the §1.3 SQL to `132_replay_parity.sql` (D-5/8, D-5/9 → `current_database()`), then remove `known_notok` from `scripts/rehearsal_test.sh` so the local harness is zero-delta; fix the stale Gate-2 footer in `scripts/rehearsal_reset.sh` and the "30/83/37/28" line in `04_RELEASE_PLAN.md` §4.
- Ratchet `MIN_FILES` 17→22 and `MIN_ASSERTIONS` 305→603 in `ci.yml`; update the stale "2 todo() calls" comment.
- Add a CI step to the `db` job that, after pgTAP, applies the three rollbacks in reverse and asserts the public-function md5 returns to `c151beb80ef502307a800e6df2b82556` (main-only baseline) and re-applies to `1c3ffd668ffdb96d14e28eb469fbeda7` — the exact sequence rehearsed in §3.
- Consider having the new reconcile search also match legacy `metadata[transfer_id]` (list without `transfer_group`, filter client-side) so pre-package orphans are found instead of double-paid; and have `claim_payout_attempt` refuse when a `payout_decisions` row `PAYOUT_TRANSFER_FAILED`/"record update failed" exists for the transfer until an operator clears it.
- Document the expected transient 500s during State C (refunded→succeeded late events; auction settle while a foreign hold is live) so on-call does not treat them as regressions.
- The harness allowlist is count-based; if kept, key it on assertion names (`D-5/8`, `D-5/9`) rather than `not_ok=2`.

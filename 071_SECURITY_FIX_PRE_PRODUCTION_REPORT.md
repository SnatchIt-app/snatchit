# 071 Security Hotfix — Pre-Production Report (DB-1)

**Status: awaiting owner authorization. Nothing has been applied to production.**

| | |
|---|---|
| Migration | `supabase/migrations/071_fix_guard_proof_status.sql` |
| Blob SHA | `30a2c74797e5c841b4f18cf8030a199ae2cc23d4` |
| File SHA-256 | `f3fb38d1c121b83794d904be85e61d19238eae97845b07e4442379aada741b7b` |
| Rollback | `supabase/rollbacks/071_fix_guard_proof_status_rollback.sql` (blob `37628901ae94c51569c15a3f1e46919bd06e2230`) |
| Branch / PR | `repo/db-security-gate-v2` @ `dcba976` — [PR #14](https://github.com/SnatchIt-app/snatchit/pull/14) |
| Base | `main` @ `aa0626db61ef179139d1fe0146c6d5b3fc027e13` |
| Production ledger | **84 rows** — unchanged, 071 NOT applied |

---

## 1. Function semantics: before → after

**Before** (migration 033, still live in production):

```sql
SECURITY DEFINER, search_path = public          -- trigger: BEFORE UPDATE only
IF NEW.proof_status IS DISTINCT FROM OLD.proof_status THEN
  IF current_setting('request.jwt.claim.role', true) NOT IN ('service_role')
     AND session_user NOT IN ('postgres') THEN
    RAISE EXCEPTION 'proof_status can only be changed by Snatch It review';
  END IF;
END IF;
```

`request.jwt.claim.role` is the **legacy singular** PostgREST GUC. PostgREST writes `request.jwt.claims` (plural JSON) — ~296k calls in production `pg_stat_statements` write only the plural form. So on every REST request: `NULL NOT IN (…)` → `NULL`; `NULL AND TRUE` → `NULL`; `IF NULL` → not taken. **A DENY condition that evaluates to unknown falls through to allow.**

*(Precision, corrected in review: the singular GUC **is** written in this database — ~6k calls — by the Storage API and `realtime.apply_rls()`. Neither can write `public.listings`, so the conclusion stands; but "PostgREST never sets it" is the accurate claim, not "nothing sets it".)*

**After:**

```sql
SECURITY INVOKER, search_path = public, pg_temp -- trigger: BEFORE INSERT OR UPDATE
-- early exits: UPDATE with proof_status unchanged; INSERT of 'pending_review'
-- v_allow boolean := false; ALLOW 1: current_user='service_role'
--   AND coalesce(claims->>'role','service_role')='service_role'
-- ALLOW 2: current_user='postgres' AND claims IS NULL
-- otherwise RAISE
```

Three design decisions, each forced by something measured rather than assumed:

- **Fail-closed.** An ALLOW boolean initialised `false`. NULL, unparseable claims, and anything unmatched raise. This is the direct inversion of the defect.
- **`SECURITY INVOKER`.** Under `DEFINER`, `current_user` is the function *owner* and cannot identify the caller at all. Under `INVOKER` it is the caller's real SQL role, enforced by PostgreSQL role membership. The risk this raised — migration 067 revokes EXECUTE from `anon`/`authenticated`/`public`, which would break every listing edit **if** EXECUTE were checked at trigger-fire time — was disproven three ways, including by this repo's own CI, where the two sibling guards are already `prosecdef=false` with EXECUTE revoked and assertions exercising them as `authenticated` pass.
- **The SQL role decides; a claim may only contradict, never grant.** `request_is_service_role()` (0550) was deliberately **not** reused: it reads the legacy GUC first, grants on the claim alone, and treats a NULL claims GUC as trusted — three behaviours that would each reopen the hole. A `SECURITY DEFINER` variant gated on `current_setting('role')` was built and rejected: it **fails open** for a direct connection that never issues `SET ROLE`.

## 2. Exploit reproduction on a fresh non-production database

CI run **33081939348** (pre-fix), fresh Supabase stack, `tests_ran=214 == planned`, `bad_plans=0`:

| Assertion | Pre-fix |
|---|---|
| seller self-approve `pending_review → approved` | **FAILED** (no exception raised) |
| seller `rejected → approved` — the payout-hold bypass | **FAILED** |
| seller `approved → rejected` | **FAILED** |
| forged `service_role` claim under the authenticated SQL role | **FAILED** |
| legacy singular GUC spoof | **FAILED** |
| seller CREATE listing pre-stamped `approved` | **FAILED** |
| seller CREATE listing pre-stamped `rejected` | **FAILED** |

Non-owner RLS denial and all positives passed throughout, so the assertions discriminate rather than failing wholesale.

## 3. Fixed behaviour on the same environment

CI run **33082543865** — `conclusion: success`.

```
migration files on disk : 85      applied by the CLI : 85
GATE2  tables=27 functions=68 policies=37 triggers=23
parity OK: 64 grant rows match the expected fixture
pgTAP  files=12 tests_ran=214 result=PASS failing_files=0 bad_plans=0
checks 14 pass, 1 skipping
```

All 7 DB-1 assertions pass. Gate-2 counts unchanged — 071 replaces a function rather than adding one, and the trigger is dropped and recreated under the same name.

## 4. Full pgTAP result

**12 files · 214 assertions executed · `Result: PASS` · 0 failing files · 0 bad plans.** The suite had **never been executed before this session**.

Two guards make that number mean something: assertions **run** must equal assertions **planned** (a file erroring before its first assertion otherwise reports a clean sheet), and a coverage floor (`MIN_FILES=12`, `MIN_ASSERTIONS=214`) because both other guards compare the suite against itself and stay consistent as files are deleted.

Also required: `supabase/ci/parity_grants.sql`. A fresh Supabase stack has **no default table privileges at all** (`pg_default_acl` holds sequence entries only), so without it `anon`/`authenticated` hold almost no grants and "anon cannot read X" passes because the GRANT is missing rather than because RLS works — vacuous green across most of the suite. See REPLAY-1.

## 5. Fresh replay

**85/85** migrations discovered and applied on a brand-new database, zero skipped, zero duplicate versions, Gate-2 parity intact. `Immutability + ordering` accepts `071_fix_guard_proof_status.sql` as a valid next migration.

## 6. Rollback

Restores the migration-033 body verbatim (transcribed from production `pg_get_functiondef`) **and narrows the trigger back to `BEFORE UPDATE`** — without that it would leave an INSERT-firing trigger calling a body where `OLD` is NULL on INSERT, a state that never existed and was never tested.

Verified by the adversarial reviewer on a replica: definition byte-identical, `prosecdef` back to `t`, `proconfig` back to `{search_path=public}`, owner and ACL preserved, trigger timing restored — **and the vulnerability returns on both paths**. That is the proof that 071 is what closed it.

The file states plainly that it reintroduces a HIGH vulnerability and should be treated as an incident action, not routine.

## 7. Affected callers — blast radius

**No legitimate writer exists.** Exactly two functions in the database mention `proof_status`: this guard, and `get_auto_release_candidates()`, which only SELECTs it. No Edge Function, RPC, cron job, or client writes it — the only SQL that ever did was 033's one-time backfill.

| Path | Runs as | Effect |
|---|---|---|
| Operator review (SQL editor / Table Editor / MCP) | `current_user=postgres`, claims NULL — **verified live** | ALLOW 2 ✓ |
| Edge Functions (service key) | `current_user=service_role` | ALLOW 1 ✓ |
| pg_cron (3 jobs) | postgres, claims-less | ALLOW 2 ✓ |
| 11 definer RPCs that UPDATE `listings` | none touch `proof_status` | early exit ✓ |
| Mobile / web clients | never send the column | early exit ✓ |

The Table Editor was checked specifically, because it goes through pg-meta rather than the SQL editor: **zero** postgres-attributed statements anywhere in `pg_stat_statements` set `request.jwt.claims`, so ALLOW 2 is satisfied. Had that gone the other way, the fix would have broken the only working review path.

## 8. No-regression evidence

Production state: **8 approved · 103 pending_review · 0 rejected**. No `PROOF_REJECTED` hold is currently active, so no payout decision changes on application. 13 transfers await payout, all with `payout_review_status = NULL`. No listing in `rejected` joins a live transfer. Nothing can be stranded, because nothing automated writes the column.

Money core untouched: no change to payments, transfers, payouts, Stripe identifiers, disputes, or their RLS/grants. The branch adds only the migration, its rollback, tests, CI, and docs.

## 9. Adversarial verdict

**Agent F — ACCEPT WITH CONDITIONS, no Critical findings**, stated plainly rather than inflated.

Attacked and held: plain UPDATE and INSERT · `INSERT … ON CONFLICT DO UPDATE` (both tuple shapes) · data-modifying CTE · `MERGE` · `COPY` · `DELETE`-then-reinsert · `app.bypass_listing_guard` GUC · `TRUNCATE` · `session_replication_role=replica` · `ALTER TABLE … DISABLE TRIGGER`.

Most notable: `authenticator` **is** a member of `service_role`, so `SET LOCAL ROLE service_role` from an authenticated session **succeeds** and `current_user` really becomes `service_role`. The guard still denied it, because the claims still said `authenticated` — the "a claim may contradict, never grant" clause doing real work. `SET ROLE postgres` is denied outright.

Test binding verified: under the 033 body all DB-1 negatives fail, so the assertions bind to this fix rather than passing incidentally.

---

## 10. Findings this work surfaced but does NOT fix

| ID | Sev | Finding |
|---|---|---|
| **H-1** | **HIGH** | The sibling guards `guard_listing_state_columns` and `guard_listing_identity_columns` have the **identical INSERT blindness** 071 just fixed for `proof_status`. Confirmed on production: **zero INSERT triggers on `public.listings`** (all five are UPDATE-only) and **zero column-level ACLs**, so `authenticated` holds table-wide INSERT across `auction_status`, `winner_user_id`, `winning_bid_amount`, `bid_count`, `current_bid`; the INSERT policy's WITH CHECK constrains only `seller_id`/onboarding/phone. A seller can INSERT a listing naming **a targeted victim as auction winner** at up to $24,999 with fabricated bid history. `complete_auction_payment()` reads `winner_user_id` from the row. Pre-existing; **not** introduced by 071, and 071 adds the first INSERT trigger this table has ever had. |
| MONEY-1 | Medium | `request_is_service_role()` (0550) gates identity impersonation on 10 money RPCs (`IF request_is_service_role() THEN v_caller_id := p_user_id`). Grants on the claim alone without checking the SQL role; trusts any claims-less caller regardless of `current_user`. Not a live DB-1 twin, but strictly weaker than 071's shape and guarding more. |
| REPLAY-1 | Medium | Source cannot rebuild production's authorization surface. `pg_default_acl` on a fresh stack has **no table entries**. A rebuild from this repo yields a database where the app cannot read its own tables. |
| DRIFT-1 | Low | Production grants `anon`/`authenticated` DML on `webhook_retries` despite migration 069 revoking it. Exposure nil today (RLS on, 0 policies, 0 rows). One-line `REVOKE`, owner-gated, deliberately **not** bundled into 071. |
| Fwd-compat | Info | A future admin-review RPC written `SECURITY DEFINER` and called via PostgREST is denied by both ALLOW paths. Documented in the migration; write it `SECURITY INVOKER` or use the `app.bypass_*` idiom. |

**H-1 is a new HIGH and therefore blocks a GO verdict under the stated criteria.** It is independent of 071 and needs its own owner decision: fix now (a new migration, which would consume `072` and shift Phase 2 again), or accept as tracked debt with a target date.

---

## 11. Authorization requested

Everything above is source-side and reversible. The next step is not.

**AUTHORIZE 071 SECURITY HOTFIX TO PRODUCTION?**

On an explicit yes I will: merge PR #14 through the protected flow; apply 071 via the reviewed migration mechanism with auto-deploy left OFF; then verify live that the ledger reads **85**, repository and ledger are 1:1, `db push --dry-run` reports up to date, `guard_proof_status` carries the new definition with the `BEFORE INSERT OR UPDATE` trigger, an authenticated seller cannot change or seed `proof_status` by either path, the service and operator paths still work, and payout behaviour is unchanged — using controlled verification that never damages a real user listing.

Until then production continues to run the vulnerable 033 body.

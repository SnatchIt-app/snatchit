# Phase 2 — Final Pre-Implementation Gate

**Canonical report for the pre-Phase-2 stabilization pass. 2026-08-27.**

Nothing in this pass has been applied to production. Production remains at **85 migrations** with the
pre-`072` guard surface. Migrations `072` and `073` are authored, tested and reviewed, and await
explicit owner authorization.

> **Evidence rule used throughout.** "Verified" appears only where the exact property was executed
> and the output is linked. Anything reasoned rather than run is labelled `INFERENCE:`; anything that
> could not be checked is labelled `UNVERIFIED:`. This project has had several incidents of work
> described as verified when the artifact had never run, so the distinction is enforced literally.

---

## 1. Baseline (Task 0)

Established before any change, and re-verified independently by two mechanisms (Supabase CLI and
direct read-only SQL) where the claim concerned production.

| Property | Expected | Measured | |
|---|---|---|---|
| `main` at start | — | `bddad8f` | |
| Repository migrations | 85 | **85** | ✓ |
| Production ledger rows | 85 | **85** | ✓ |
| Repo ↔ ledger version-set equality | exact | both md5 **`4783033000cc5cb11e03271330cbd049`** | ✓ |
| Letter-suffixed versions | 0 | **0** | ✓ |
| Duplicate versions | 0 | **0** | ✓ |
| Prefix-ambiguous version pairs | 0 | **0** | ✓ |
| Non-numeric versions | 0 | **0** | ✓ |
| `071` present exactly once | yes | **1**, both sides | ✓ |
| `072` absent | yes | **0**, both sides | ✓ |
| `schema_migrations_pre_schemeB` backup | 79 | **79** | ✓ |
| Gate-2 objects (`public`) | 27/68/37/23 | **27 tables / 68 functions / 37 policies / 23 triggers** | ✓ |
| Ruleset bypass actors | 0 | **0** | ✓ |
| Required status checks | 5 | **5** | ✓ |
| Supabase auto-deploy | OFF | branch record `git_branch = ""` | ✓ |

Set equality is over the md5 of the comma-joined sorted version list, computed independently on each
side — equal digests over 85 elements is set equality, not merely an equal count.

**No foundational assumption differed from the expected state**, so the pass proceeded rather than
stopping.

Two pre-existing PRs (#9 dependabot, #11 admin purge) remain open from 2026-08-26 and were not in
scope.

---

## 2. H-1 — listing INSERT guards (Agent A) — **CLOSED IN SOURCE**

**Migration `072_fix_listing_insert_guards.sql`** · [PR #20](https://github.com/SnatchIt-app/snatchit/pull/20)

### The defect, and why it was worse than "unprotected columns"

`guard_listing_state_columns()` and `guard_listing_identity_columns()` are `BEFORE UPDATE` only.
`authenticated` holds table-wide INSERT on `public.listings`; `pg_attribute.attacl` is NULL for all
36 columns; the INSERT policy's WITH CHECK constrains only `seller_id = auth.uid()`,
`stripe_onboarding_complete` and `phone_verified()`; and the CHECK constraints permit `'sold'` /
`'ended'`. Before `072`, `trg_guard_proof_status` (from `071`) was the **only** INSERT-firing trigger
the table had ever had.

The money path is concrete, not theoretical: `supabase/functions/create-payment-intent/index.ts`
L320–326 gates on `listing.winner_user_id !== buyerId` and then sets
`amount = listing.winning_bid_amount ?? listing.current_bid`. A forged INSERT therefore serves a
**targeted victim a genuine Stripe PaymentIntent for a listing they never bid on**, and
`app/(tabs)/bids.tsx` displays it as "WON". It is also silent: `trg_notify_auction_won_inbox` is
`AFTER UPDATE OF winner_user_id`, so a row that *arrives* carrying a winner never fires it.

### Authority matrix

A complete 36-column matrix (client INSERT / client UPDATE / server-RPC / operator, each with its
source of truth) is in the PR. It was derived from the production catalog, `pg_policy`, the three
guard bodies, a `pg_proc` scan of all 11 listing writers, and both client creation paths — not from
mirroring the UPDATE rules onto INSERT.

### Evidence

| Phase | Run | Result |
|---|---|---|
| RED | [33091744028](https://github.com/SnatchIt-app/snatchit/actions/runs/33091744028) | `045… (Tests: 20 Failed: 15)` · `result=FAIL` |
| GREEN | [33092007069](https://github.com/SnatchIt-app/snatchit/actions/runs/33092007069) | `Files=13, Tests=234` · `result=PASS` |

15 of 20 failing rather than 20 — the five that passed throughout are the legitimate paths and
`071`'s wiring, so the assertions discriminate rather than failing wholesale. `tests_ran == planned`
rules out an early abort.

### Shape, and one thing a careless fix would have got wrong

The sibling guards **could not** simply be widened to INSERT: their bodies dereference `OLD` on every
branch, and `OLD` is unassigned on INSERT. So `072` adds a new `guard_listing_insert_columns()`
(`SECURITY INVOKER`, `search_path = public, pg_temp`) on a new `BEFORE INSERT` trigger, fail-closed in
`071`'s shape — an ALLOW boolean initialised false, the SQL role decides, a claim may contradict but
never grant. `request_is_service_role()` was deliberately not reused (see §3).

Purely additive. All 11 existing listing writers are UPDATE-only, which is what makes it low-risk.

Two judgement calls, both recorded in the migration header: `current_bid` is constrained to
`= starting_bid` rather than banned (it is NOT NULL with no default and both clients send it), and
`app.bypass_listing_guard` is deliberately **not** honoured on INSERT because it has no
statement-level reset — honouring it would mean "a transaction that placed a bid may then forge a
listing".

---

## 3. MONEY-1 (Agent B) — **NOT EXPLOITABLE**, by grants and PostgREST behaviour, not by design

**Tests:** `supabase/tests/110_money_authz_matrix.sql`, 17 assertions · [PR #19](https://github.com/SnatchIt-app/snatchit/pull/19)

### The helper is as weak as suspected

All three suspicions were confirmed against the live definition of `request_is_service_role()`
(migration `0550`): it reads the **legacy singular** `request.jwt.claim.role` **first**; it grants on
the **claim alone** and never reads `current_user`; and it **fail-opens**, returning true when the
claims GUC is absent.

Eleven client-callable RPCs depend on it, each of the shape
`v_caller_id := auth.uid(); IF v_caller_id IS NULL AND request_is_service_role() THEN v_caller_id := p_user_id`.
That substitution is the escalation to hunt: it is identity impersonation on money and custody RPCs.

### Why it does not fall over anyway

1. **`auth.uid()` short-circuits before the helper is consulted.** To hold the `authenticated` SQL
   role, PostgREST must have validated a JWT; Supabase user tokens always carry `sub`, so
   `auth.uid()` is non-NULL and the helper is never reached. Assertion #13/#14 demonstrates this
   directly: a session with a forged singular GUC **does** fool the helper, and
   `mark_transfer_sent(transfer_a, seller())` **still raises** `Only the seller can mark a transfer as sent.`
2. **The fail-open branch is structurally unreachable over HTTP.** PostgREST sets
   `request.jwt.claims` unconditionally on every request (296,793 calls in `pg_stat_statements`), and
   — measured on production — `set_config(name, NULL, true)` on a never-set GUC yields `''`, not
   NULL, so `current_setting(...) IS NULL` cannot be true inside a request. This is pinned as an
   assertion, so if a future PostgreSQL changes that semantic the build breaks rather than the
   security argument silently evaporating.
3. **`SET ROLE service_role` is irrelevant here.** `authenticator` **is** a member of `service_role`
   (confirmed via `pg_auth_members`) and the role change genuinely succeeds — but the helper reads
   only claims, so changing the SQL role does not change its answer. The property that makes `0550`
   weak in principle is what makes the SET-ROLE trick useless against it.
4. **Grants.** No dependant is anon-executable; none is on default PUBLIC EXECUTE.
5. **Edge Functions are not confused deputies.** `confirm-and-release` derives `buyerId` from
   `supabase.auth.getUser(token)` server-side, never from the request body; `stripe-webhook` uses
   `metadata.buyer_id` from the signature-verified event.

**No migration was authored for MONEY-1.** The verdict is not-exploitable, so changing the identity
resolution of 10 live money RPCs as a side effect of an audit would have been the wrong trade. The
recommended hardening — drop the legacy singular read, require `current_user = 'service_role'`
alongside the claim, replace the `IS NULL` fail-open with an explicit
`current_user='postgres' AND claims IS NULL` — is recorded as a **non-blocking condition** (§10).

### F-2 / F-3, classified not implemented

- **F-2** (unique index on `transfers.stripe_transfer_id`): re-confirmed absent. Production data is
  clean — 36 transfers, 23 with a stripe id, **23 distinct** — so a partial unique index would build
  without conflict. Deferred because DDL on a live money table needs its own migration, rollback and
  owner-gated window.
- **F-3** (payments amount/status guard): re-confirmed. `public.payments` has **zero** non-internal
  triggers — not even `set_updated_at`. **Severity upgraded**; see §10.

---

## 4. REPLAY-1 (Agent C) — harness audited, one live fail-open found and fixed

### The defect: the required check was green with failing security assertions

Run [33090393102](https://github.com/SnatchIt-app/snatchit/actions/runs/33090393102), on a tree
byte-identical to `main`, concluded **success** while printing
`files=12 tests_ran=214 result=PASS failing_files=0 bad_plans=0 todo_failing=2`.

`todo_fail` was computed and printed but **absent from the gate condition**. An earlier fix had
stopped the harness *mis-reporting* TODO failures as passes but never made it *fail* on them, so any
failing security assertion wrapped in `todo()` kept the gate green. `skip()` was worse: no counter
existed at all, and skipped assertions still count toward `Tests=`.

**Fixed** (Agent E, at the coordinator's direction) with a three-part masking ratchet: a runtime
`todo_failing <= EXPECT_TODO` gate, a **static** `todo(` count (a `todo()` around a *passing*
assertion emits no runtime marker, so the runtime count alone cannot see one being added), and an
outright ban on `skip()`. Both authors had to deviate from the suggested patch to survive
`set -uo pipefail` when a grep legitimately matches nothing — the commit that finally *removes* the
last `todo()` must not abort the step.

### Everything else held

19 of 21 fail-open conditions were traced to a specific deciding line and found **CAUGHT**: pg_prove
nonzero (two independent mechanisms), planned≠executed, zero tests, missing/empty/truncated TAP file,
a file erroring before its first assertion, bad plans, stack failure, coverage shrink in files or
assertions, skipped or duplicate migrations, and the vacuous-RLS-pass hole. No `continue-on-error`
anywhere; no exit code lost through a pipe or substitution.

**`plan(N)` integrity: all 12 baseline files exact, 214/214, zero delta** — counted with
word-boundary tokenizing so `throws_ok(`/`lives_ok(`/`is_empty(` do not double-count as `ok(`/`is(`,
and all four `unnest(` sites checked to confirm they are single-assertion aggregates.

### Fresh replay result (integration tree)

Run [33095657921](https://github.com/SnatchIt-app/snatchit/actions/runs/33095657921), **success**:

```
migration files on disk : 87    applied by the CLI : 87    duplicate versions : 0
supabase CLI    : expected=2.115.0 actual=2.115.0
tables=27 functions=69 policies=37 triggers=24
OK: 64 grant rows match the expected fixture
NOTICE: self-test OK: planted unknown table was detected.
NOTICE: every public table has a recorded grant decision.
files=15 tests_ran=266 result=PASS failing_files=0 bad_plans=0 todo_failing=2
coverage floor OK: 15 files >= 15, 266 assertions >= 266
masking ratchet OK: todo_failing=2 <= 2, todo() calls=2, skip() calls=0
```

Every required output is present: files discovered **87**, applied **87**, duplicates **0**, test
files **15**, planned **266**, executed **266**, failing files **0**, bad plans **0**.
`UNVERIFIED:` migrations *skipped* is not printed as its own number — it is implied 0 by
`files == applied`.

---

## 5. DRIFT-1 (Agents D, H) — 4 security drifts found, remediation authored

### Method worth recording

`supabase_migrations.schema_migrations.statements` stores the SQL **actually executed** against
production. Normalizing (strip comments, lowercase, strip whitespace/semicolons) and md5-ing both
sides for all 85 versions gave **82/85 byte-identical** — a genuine source↔production comparison of
what ran, not an inference from object counts.

### Object sets are clean

**Zero** production-only functions, tables, triggers or `public` policies. The out-of-band-object
pattern that was suspected **does not exist**. (An earlier claim that `apply_manual_review` was
missing from source was **REFUTED** — it is defined at `039_risk_based_payout.sql:254` and
`0551_...:67`; a single-line grep missed it because the arguments wrap. Recorded here because the
claim was relayed before it was checked.)

The drift is in **grants, cron, and storage** instead.

| # | Finding | Class | Disposition |
|---|---|---|---|
| **SEC-2** | Production's `pg_default_acl` on `public` carries **TABLE and FUNCTION** entries, not just SEQUENCE. Every new table in `public` is auto-granted full DML to `anon`/`authenticated`; every new function is auto anon-EXECUTE, i.e. callable unauthenticated at `/rest/v1/rpc/<name>`. | **SECURITY DRIFT**, environment-caused | **Rule + CI backstop.** Vendor-managed; removing the default ACLs would break provisioning. Standing rule added to Standards §5 and the execution protocol; `supabase/ci/assert_public_table_grant_decisions.sql` fails CLOSED for any `public` table with no recorded grant decision. |
| **SEC-1** | `webhook_retries` grants `anon`/`authenticated` full DML although migration `069` revokes them and the ledger records `069` as executed. | **SECURITY DRIFT**, unexplained root cause | **Eliminated in `073` §1** (production-changing). Exposure today nil — RLS on, 0 policies, **0 rows**, all three re-confirmed. |
| **SEC-3** | Storage buckets have NULL `file_size_limit` and NULL `allowed_mime_types` — `000`'s `ON CONFLICT DO NOTHING` meant the constraints never landed on pre-existing buckets. Two of three buckets are public. | **SECURITY DRIFT** | **Eliminated in `073` §2** (production-changing). Pre-checked safe: 134/9/29 objects, none over any proposed limit, only `image/jpeg` and `image/png` in use. |
| **SEC-4** | Six `storage.objects` policies exist in source and **not** in production, never dropped by any migration. A fresh replay gets 17 storage policies where production has 11, and the extras are `TO PUBLIC` with weaker DELETE guards. | **SECURITY DRIFT** — makes the rebuild **weaker than production** | **Eliminated in `073` §3** (no-op on production). CI could not see this: Gate-2 counts only `schemaname='public'`. |
| D-5 | Cron job `sweep-auth-password-changes` runs in production; no migration schedules it. A rebuild silently loses password-change security notifications. | Unexplained drift (availability) | **Eliminated in `073` §4** (no-op on production). |
| D-6 | Ledger row `029` contains `030`'s SQL and name; repo's `029_public_profiles.sql` never executed under any version. Its effects are present via other paths. | Unexplained drift (ledger integrity) | **Accepted explicitly** — rewriting ledger history is riskier than the defect. |
| D-7, D-8 | Repo `005` and `033` differ from the SQL executed as those versions (a fail-closed backport and a replay-safety fix respectively). End states verified identical live. | **Functionally equivalent** | **Accepted explicitly.** |
| — | Six `public` functions retain PUBLIC EXECUTE that `067` missed. | Not drift (source and production agree) | Five revoked in `073` §5; the sixth is §10 GATE-1. |

**`073_drift_reconciliation_grants_storage_cron.sql`** · [PR #21](https://github.com/SnatchIt-app/snatchit/pull/21) · tests `supabase/tests/120_drift_reconciliation.sql` (15 assertions)
RED [33094276735](https://github.com/SnatchIt-app/snatchit/actions/runs/33094276735) (`Failed 9/14`, incl. `storage.objects has exactly 11 policies — have: 17 want: 11`) → GREEN [33094856135](https://github.com/SnatchIt-app/snatchit/actions/runs/33094856135).

Two judgement calls in `073` worth the reader's attention: `proof-docs` was given a deliberately
**wider** MIME allowlist than the baseline's four image types (adding `application/pdf` and
`image/heif`) because `web/src/lib/evidence-upload.ts` accepts them and the tidy-looking image-only
list would have broken a live seller flow; and `is_winner` / `is_blocked_by_me` had PUBLIC and anon
revoked but **`authenticated` kept**, because `is_blocked_by_me` is a designed listings-feed RLS
predicate.

### Three-way comparison status

A normalized, deterministic catalog-snapshot script was written and run read-only against production
(**1734 lines, md5 `e4235b5d139a7a742501704785ac98ab`**, 18 sections). `UNVERIFIED:` **the replay leg
of the three-way comparison has not been executed** — CI does not yet emit the snapshot, and Docker
is unavailable locally. The CI step to capture it is specified and ready to adopt. Until it runs,
source↔production is measured and replay↔production is reasoned.

---

## 6. pgTAP suite

| | Baseline | Integration |
|---|---|---|
| Files | 12 | **15** |
| Planned assertions | 214 | **266** |
| Executed | 214 | **266** |
| Result | PASS | **PASS** |
| Failing files / bad plans | 0 / 0 | **0 / 0** |
| Failing-but-TODO | 2 | **2** (F-2, F-3 — declared, ratcheted) |

Added this pass: `045_listing_insert_authority.sql` (+20, H-1), `110_money_authz_matrix.sql` (+17,
MONEY-1), `120_drift_reconciliation.sql` (+15, DRIFT-1).

Coverage now includes H-1, DB-1, money-RPC authorization boundaries, service-role impersonation, JWT
claim shape (singular/plural/missing/malformed/empty), RLS write boundaries, SECURITY DEFINER
execution grants, `search_path` discipline, protected listing INSERT and UPDATE, ordinary listing
creation and edits, cross-user access, anon access, and the internal/server path.

**No security TODO is silently ignored.** The suite contains exactly two `todo()` markers, both in
`060_payments_money.sql`, both named findings (F-2, F-3) with recorded reasons, and both now held by
a CI ratchet that fails if a third appears. `skip()` is banned outright.

---

## 7. Toolchain

`ci.yml` **already** pinned `2.115.0` on `main` (set during Scheme B) — the premise that it installed
`latest` was wrong, and is corrected here. What was actually missing: any assertion that the install
*took*, a single source for the literal, and docs that agreed.

Now: job-level `env.SUPABASE_CLI_VERSION: 2.115.0` is the single source; a **drift gate** runs before
anything migration-sensitive and fails on mismatch. `supabase --version` prints the bare version on
stdout while the upgrade nag goes to stderr, so stderr is discarded and the comparison is exact.
Exercised locally against six cases, including **`2.115.01` vs `2.115.0` → exit 1**, proving it is not
a substring match. `UNVERIFIED:` the fail path was not deliberately triggered in a runner.

`2.116.0` exists upstream and is **deliberately not adopted**. Docs reconciled across `CLAUDE.md`
(which said `2.75.0`), `AGENTS.md`, Standards §3/§5, the execution protocol, and the workflows README.
The stale caveat that letter-suffixed migrations are invisible to the CLI was **retired** — Scheme B
completed 2026-08-26 and `migrations-guard` now rejects that filename class outright.

Integration run confirms: `supabase CLI : expected=2.115.0 actual=2.115.0`.

---

## 8. Production integration state

| | |
|---|---|
| Supabase auto-deploy | **OFF** — branch record `git_branch` cleared `"main"` → `""` at 15:49:25Z |
| Behaviour on merge to `main` | changed from `success` (processed) to **`skipped`** — observed on three consecutive merges |
| Production ledger | **85**, unchanged throughout this pass |
| Backup `schema_migrations_pre_schemeB` | **79**, intact |
| `072` / `073` applied | **No** |
| GitHub ruleset `main-protection` | active, **0 bypass actors**, 5 required checks |
| New precondition | `AUTODEPLOY-VERIFIED-OFF: YYYY-MM-DD` required in the PR body of any PR touching `supabase/migrations/**`, enforced by the required `migrations-guard` check |

The `AUTODEPLOY-VERIFIED-OFF` gate proves a **human acknowledged**, not that the setting is off — CI
cannot read the Supabase dashboard, and the workflow comment says so. It is a forcing function, not a
control.

Full incident record: `AUTODEPLOY_1_CLOSURE_REPORT.md`. Canonical rule:
`docs/operations/DEPLOYMENT_PATHS.md`.

---

## 9. Phase-2 migration numbering

Three security hotfixes have now consumed `071` (DB-1, live), `072` (H-1, authored) and `073`
(DRIFT-1, authored), so the 16 MVP packages moved `071–086` → `074–089` across three shifts.

The second shift had been applied **incompletely** — §1 mapped two packages to the same version, §3
still read `071 | A`, and §5's heading opened at `071`. That was found and deliberately left in place
rather than silently edited, then repaired here in one authoritative pass with a mechanical proof:

```
§1 map == §2 mermaid ids == §2 labels == §3 table == §5 headings   : True
exactly 074..089, 16 packages, no duplicates, no gaps              : True
§3 dependency column vs §2 mermaid edges — 28 edges each, IDENTICAL: True
OLD dependency graph == NEW dependency graph                       : True
body line counts old=862 new=862                                   : True
body lines changed: 153 — of which NOT purely a version token: 0
```

That last line is the substantive proof: **nothing but digits moved.**

`UNVERIFIED:` §5's dependency bullets for packages at `080`, `084` and `088` name more dependencies
than §3 and §2 do for the same packages. This was mechanically confirmed **pre-existing** (identical
before and after) and preserved. It is a content discrepancy, not numbering, and needs an
architecture decision — recorded in §10 as GATE-2.

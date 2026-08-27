# 071 Security Hotfix — Production Verification Report (DB-1)

**Status: APPLIED TO PRODUCTION AND VERIFIED. DB-1 is closed in production.**

| | |
|---|---|
| Migration | `supabase/migrations/071_fix_guard_proof_status.sql` |
| File SHA-256 | `f3fb38d1c121b83794d904be85e61d19238eae97845b07e4442379aada741b7b` (unchanged from the reviewed artifact) |
| Blob SHA | `30a2c74797e5c841b4f18cf8030a199ae2cc23d4` (unchanged) |
| PR | [#14](https://github.com/SnatchIt-app/snatchit/pull/14), squash-merged 2026-08-27 15:10:54Z |
| main | `7ff83f876a0c9485996a272e34316dcbb2a069eb` |
| Production ledger | **85 rows** (was 84) |
| Verification method | synthetic rows inside `BEGIN … ROLLBACK`; **no real user listing was read-modified or damaged** |

---

## 0. READ THIS FIRST — the apply did not happen the way the authorization described

**Production was changed by the merge itself, not by an operator-run migration command.**

The authorization said to apply 071 "with Supabase auto-deploy remaining OFF". That premise was
false, and I did not discover it until after the merge. The observed sequence:

| Time (UTC) | Event | Evidence |
|---|---|---|
| ~15:05 | Pre-merge snapshot | ledger **84**, `guard_proof_status` `prosecdef=t`, `search_path=public`, trigger `BEFORE UPDATE` |
| 15:10:54 | PR #14 squash-merged into `main` | `gh pr view 14 --json mergedAt` |
| 15:11:26 → 15:11:34 | **Supabase GitHub App** ran a `Supabase Preview` check against `main`, conclusion `success` | `check-runs` API on `7ff83f8`, `app.name = "Supabase"` |
| ~15:13 | Next read | ledger **85**, `071` present, new function body live |

I never ran `supabase db push`. The `071` ledger row carries `created_by = NULL` — the CLI
signature used by the integration, matching `069`/`070` and unlike the dashboard-applied rows,
which carry `created_by = gnvprod@gmail.com`.

**The governance consequence is larger than this migration: on this repository, merging a PR to
`main` deploys migrations to the production database.** `.github/workflows/ci.yml` opens with the
comment "Nothing here deploys or touches production" — accurate about CI, and misleading about the
repository as a whole, because the Supabase GitHub App deploys outside CI. Two prior statements of
mine inherited that false premise and are corrected here: the pre-production report's "auto-deploy
left OFF", and my description of the production apply as a separate step I would perform.

What this did **not** compromise:

- The content applied is exactly the reviewed artifact — same SHA-256, and the live function body
  is byte-identical to the migration source (§3).
- The outcome was authorized: you approved applying 071 to production.
- Nothing else was applied. The ledger gained exactly one row; the version set matches the
  repository exactly (§2); Gate-2 object counts are unchanged (§4).

What it did cost: the pre-apply `db push --dry-run` rehearsal never ran as a gate, because the
deploy had already happened by the time I reached that step. The dry run in §2 is therefore
after-the-fact confirmation, not a pre-flight check.

**Owner action required (owner-only, Supabase dashboard):** decide whether the GitHub integration's
production-branch deploy stays enabled. It is at Dashboard → Project Settings → Integrations →
GitHub. This must be settled **before** Phase 2, where merges will carry schema-creating
migrations. I cannot see or change that setting.

---

## 1. Required proofs

| # | Required | Result | Evidence |
|---|---|---|---|
| 1 | production ledger = 85 | **85** | `select count(*) from supabase_migrations.schema_migrations` |
| 2 | repository migrations = 85 | **85** | `ls supabase/migrations/*.sql \| wc -l` at `7ff83f8` |
| 3 | exact source↔ledger equality | **exact** | both sides md5 `4783033000cc5cb11e03271330cbd049` (§2) |
| 4 | `db push --dry-run` = up to date | **up to date** | `{"upToDate":true,"migrations":[],"message":"Remote database is up to date."}` |
| 5 | correct `guard_proof_status()` live | **byte-identical to source** | §3 |
| 6 | `BEFORE INSERT OR UPDATE` trigger live | **yes** | §3 |
| 7 | seller cannot seed `proof_status` on INSERT | **denied** | B1, B2 (§5) |
| 8 | seller cannot change `proof_status` on UPDATE | **denied** | A1, A2, A3 (§5) |
| 9 | forged claims cannot bypass it | **denied** | A4, A5, A6 (§5) |
| 10 | legitimate service/operator paths work | **allowed** | C3, C4 (§5) |
| 11 | payout behaviour unchanged | **unchanged** | §6 |
| 12 | pgTAP remains green | **green on the exact tree now on main** | §7 |
| 13 | pre-Scheme-B backup intact | **79 rows** | §4 |

All thirteen pass.

## 2. Ledger and source are 1:1

```
ledger rows                85
repository migration files 85
ledger md5                 4783033000cc5cb11e03271330cbd049
repository md5             4783033000cc5cb11e03271330cbd049
```

Both md5s are over the version list joined by `,` in sorted order, computed independently — one by
`string_agg(version, ',' order by version)` in the database, one from the filenames on disk. Equal
digests over 85 elements is set equality, not just an equal count.

Two independent mechanisms agree, as required for live-state claims:

- **CLI** (`supabase migration list --linked --output-format json`): 85 local, 85 remote, zero
  pending, zero remote-only orphans.
- **Direct read-only SQL** (measurement only — no INSERT/DELETE against the ledger was used
  anywhere in this work): 85 rows, `071` present.

`supabase db push --linked --dry-run` → `{"upToDate":true,"dryRun":true,"migrations":[],"seeds":[],"roles":[],"message":"Remote database is up to date."}`

The `071` row: `version=071`, `name=fix_guard_proof_status`, `created_by=NULL`, 7 statements —
matching the 7 statements in the file (BEGIN, CREATE OR REPLACE FUNCTION, COMMENT, DROP TRIGGER,
CREATE TRIGGER, REVOKE, COMMIT).

## 3. The live function is the reviewed function

```
prosecdef  : false                      (was true  — SECURITY INVOKER now)
proconfig  : {search_path=public, pg_temp}   (was {search_path=public})
owner      : postgres
EXECUTE    : service_role, postgres only     (anon / authenticated / PUBLIC hold none)
trigger    : CREATE TRIGGER trg_guard_proof_status
             BEFORE INSERT OR UPDATE ON public.listings
             FOR EACH ROW EXECUTE FUNCTION guard_proof_status()
```

`pg_get_functiondef()` returns the fail-closed body character-for-character as written in
`071_fix_guard_proof_status.sql`, comments included: the two early exits, `v_allow boolean := false`,
the jsonb-parse exception handler, ALLOW 1 (`current_user='service_role'` **and**
`coalesce(claim_role,'service_role')='service_role'`), ALLOW 2 (`current_user='postgres'` and no
claims), and the terminal `RAISE`. The `COMMENT ON FUNCTION` is present.

The `REVOKE` in the migration was a no-op against production, as predicted — 067's posture was
already in place and `CREATE OR REPLACE` preserves owner and ACL.

## 4. Nothing else moved

| | before | after |
|---|---|---|
| tables | 27 | **27** |
| functions | 68 | **68** |
| policies | 37 | **37** |
| triggers (non-internal, public) | 23 | **23** |
| `schema_migrations_pre_schemeB` | 79 | **79** |
| `listings` rows | 111 | **111** |
| `transfers` rows | 36 | **36** |

Gate-2 counts are unchanged because 071 replaces a function rather than adding one, and drops and
recreates the trigger under the same name. The pre-Scheme-B ledger backup is untouched.

## 5. Behavioural verification on production

Method: one transaction, `BEGIN … ROLLBACK`. Three synthetic listings were created **inside** that
transaction (seeded to `pending_review`, `rejected`, `approved` by the operator path) and every
attack ran against those. **No pre-existing listing was modified.** Post-transaction re-read
confirms `listings` = 111 with **zero** rows matching `ZZ-071-VERIFY%`, and the `proof_status`
distribution is bit-for-bit what it was before: `approved 8 / pending_review 103`.

Seller identity: a real seller who satisfies the INSERT policy's preconditions
(`stripe_onboarding_complete = true`, `phone_confirmed_at` set), so RLS admits the statement and the
**trigger** is what decides — otherwise a denial would prove nothing.

| # | Scenario | Expected | Result |
|---|---|---|---|
| A1 | seller self-approves `pending_review → approved` | DENY | **denied by guard_proof_status** |
| A2 | seller clears the payout hold `rejected → approved` | DENY | **denied by guard_proof_status** |
| A3 | seller downgrades `approved → rejected` | DENY | **denied by guard_proof_status** |
| A4 | forged plural claim `{"role":"service_role"}` under the authenticated SQL role | DENY | **denied by guard_proof_status** |
| A5 | legacy singular GUC spoof `request.jwt.claim.role=service_role` — the exact vector 033 trusted | DENY | **denied by guard_proof_status** |
| A6 | `SET LOCAL ROLE service_role` from an authenticated session, claims still `authenticated` | DENY | **denied by guard_proof_status** |
| B1 | seller **creates** a listing pre-stamped `approved` | DENY | **denied by guard_proof_status** |
| B2 | seller **creates** a listing pre-stamped `rejected` | DENY | **denied by guard_proof_status** |
| C1 | seller edits an ordinary column (`event_name`) | ALLOW | **allowed** |
| C2 | seller creates an ordinary listing (default `proof_status`) | ALLOW | **allowed** |
| C3 | Edge Function path — `service_role` SQL role + `service_role` claim (ALLOW 1) | ALLOW | **allowed** |
| C4 | operator review path — `postgres`, no claims (ALLOW 2) | ALLOW | **allowed** |

Every denial carried `SQLSTATE P0001: proof_status can only be changed by Snatch It review` — the
guard's own message. That distinction matters: a denial from RLS or from a sibling trigger would
have carried a different message and would **not** have proven the fix. The assertions discriminate
rather than failing wholesale, since the five positives passed in the same transaction.

A6 is the escalation Agent F found and is worth stating plainly: `authenticator` **is** a member of
`service_role`, so `SET LOCAL ROLE service_role` genuinely succeeds from an authenticated session
and `current_user` really does become `service_role`. Production denied it anyway, because the
claims still said `authenticated` — the "a claim may contradict, never grant" clause doing real
work against a real escalation on the real database.

Under the migration-033 body that production ran until 15:11 today, A1–A5, B1 and B2 all succeeded.

## 6. No regression

- `proof_status` distribution unchanged: 8 approved / 103 pending_review / 0 rejected.
- `transfers`: 36 rows, `payout_review_status` NULL on all 36 — unchanged. No `PROOF_REJECTED` hold
  exists to be affected, and nothing automated writes `proof_status`, so no payout decision moves.
- Ordinary listing creation and editing by an authenticated seller still work (C1, C2) — the
  concrete risk of the `SECURITY INVOKER` switch under 067's revoked EXECUTE, now disproven on
  production rather than only in CI.
- Both legitimate writer paths work (C3, C4). The operator review path is the one that matters
  day to day, and it is the one ALLOW 2 exists for.
- Money core untouched: no change to payments, transfers, payouts, Stripe identifiers, disputes, or
  their RLS and grants.
- Supabase security advisors show no finding attributable to 071. `guard_proof_status` no longer
  appears under "Signed-In Users Can Execute SECURITY DEFINER Function", consistent with the
  INVOKER switch. The remaining advisors (INFO `rls_enabled_no_policy` on service-only tables, WARN
  on the app's intentional `SECURITY DEFINER` RPC surface, leaked-password protection disabled) all
  concern objects 071 does not touch.

## 7. pgTAP

Green run **33086084533**:

```
migration files on disk : 85      applied by the CLI : 85
GATE2  tables=27 functions=68 policies=37 triggers=23
parity OK: 64 grant rows match the expected fixture
pgTAP  files=12  tests_ran=214  result=PASS  failing_files=0  bad_plans=0  todo_failing=2
coverage floor OK: 12 files >= 12, 214 assertions >= 214
```

That run tested the tree that is now on `main`: PR head `679c2fb` and merged `main` `7ff83f8` have
the identical tree hash `6cf44601b20c6001cf093787e669e46dc8c516a8`. CI does not re-run on pushes to
`main` by design (`push: branches-ignore: [main]`), so this is the correct evidence rather than a
substitute for it.

`todo_failing=2` is F-2 and F-3 — pre-existing, deliberately non-gating `todo()` markers in
`060_payments_money.sql`, unrelated to DB-1.

**One CI defect was fixed to get here** (commit `679c2fb`), and it is worth recording because the
previous "green" reading was partly hollow: the M-2 counter rewrite left the old counter block
behind, and under `set -u` the orphaned `$ok_n` aborted the summary step *after* every real gate had
already passed. Only the dead lines were deleted. Every gate remains: `result=PASS`,
`bad_plans == 0`, assertions-run == assertions-planned, and the `MIN_FILES`/`MIN_ASSERTIONS` floor.
No test was weakened and no threshold was lowered.

## 8. Rollback, if it is ever needed

`supabase/rollbacks/071_fix_guard_proof_status_rollback.sql` restores the 033 body verbatim and
narrows the trigger back to `BEFORE UPDATE`. It was verified on a replica: definition byte-identical,
`prosecdef` back to `t`, `proconfig` back to `{search_path=public}`, owner and ACL preserved — **and
the vulnerability returns on both paths**, which is the proof that 071 is what closed it. The file
says so in its header. Running it reopens a HIGH; a corrected forward migration is almost always the
better move.

## 9. Still open — not addressed by 071

| ID | Sev | Finding |
|---|---|---|
| **H-1** | **HIGH** | `guard_listing_state_columns` and `guard_listing_identity_columns` have the **identical INSERT blindness** 071 just fixed for `proof_status`. Re-confirmed on production after 071: both remain `BEFORE UPDATE` only. `guard_listing_state_columns` protects `auction_status`, `winner_user_id`, `winning_bid_amount`, `bid_count`, `current_bid`, `status`, `highest_bidder_id`, `reserved_by`, `reserved_until`, `sold_at`, `ended_at` — on UPDATE only. `authenticated` holds table-wide INSERT with no column-level ACLs, and the INSERT policy's WITH CHECK constrains only `seller_id` / onboarding / phone. A seller can INSERT a listing naming **a targeted victim as auction winner** at up to $24,999 with fabricated bid history; `complete_auction_payment()` reads `winner_user_id` from that row. Pre-existing, and `trg_guard_proof_status` is still the only INSERT-firing trigger this table has. **Awaiting your separate authorization.** |
| **AUTODEPLOY-1** | **HIGH (process)** | Merging to `main` deploys migrations to production (§0). Unreviewed as a control, undocumented in the repo, and directly contrary to a premise in the authorization. Must be settled before Phase 2. Owner-only. |
| MONEY-1 | Medium | `request_is_service_role()` (0550) gates identity impersonation on 10 money RPCs, granting on the claim alone without checking the SQL role and trusting any claims-less caller. Strictly weaker than 071's shape, and guarding more. |
| REPLAY-1 | Medium | Source cannot rebuild production's authorization surface; a fresh stack has no default table privileges, so a rebuild from this repo yields a database where the app cannot read its own tables. CI compensates with `supabase/ci/parity_grants.sql`. |
| DRIFT-1 | Low | Production grants `anon`/`authenticated` DML on `webhook_retries` despite migration 069 revoking it. Exposure nil today (RLS on, 0 policies, 0 rows). One-line `REVOKE`, owner-gated. |
| Fwd-compat | Info | A future admin-review RPC written `SECURITY DEFINER` and called via PostgREST is denied by both ALLOW paths. Write it `SECURITY INVOKER`, or use the existing transaction-local `app.bypass_*` idiom. |

---

## 10. Verdict

**DB-1 is closed in production.** The vulnerable migration-033 body is gone; the fail-closed guard is
live on both the UPDATE and the INSERT path; every legitimate writer still works; no user data was
touched to prove it.

Phase 2 remains **NO-GO** on the stated criterion "no unresolved High": H-1 and AUTODEPLOY-1 are
both open and both need an owner decision. 071 itself is complete.

Per instruction, work stops here. Phase 2 is not started and `072` is not authored.

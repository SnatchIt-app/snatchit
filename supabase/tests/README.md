# DB security gate — executable pgTAP suite

> **STATUS 2026-08-27 — THIS SUITE NOW EXECUTES IN CI.**
> It ran for the first time on 2026-08-27 (it had never been executed before).
> Current: **12 files, 214 assertions, `Result: PASS`, 0 bad plans**, via
> `supabase test db --local` in the `db` job of `ci.yml`, against the same
> freshly-replayed stack that job already boots.
>
> Two things it depends on, both easy to break:
> 1. `supabase/ci/parity_grants.sql` is applied first. A fresh Supabase stack has
>    **no default table privileges at all** (`pg_default_acl` holds sequence
>    entries only), so without it `anon`/`authenticated` have almost no grants and
>    "anon cannot read X" passes because the GRANT is missing rather than because
>    RLS works — vacuous green across most of the suite. See finding REPLAY-1.
> 2. Assertions RUN must equal assertions PLANNED. A file that errors before its
>    first assertion otherwise reports a clean sheet.


Executable regression net for the custody boundary of the Snatch It database:
RLS coverage, the profiles column-grant read boundary, anon/authenticated
write bans, transfer state custody (RPC-only writes), payment/payout money
invariants, admin isolation, and the webhook claim lease.

**214 assertions** across 12 files. 2 are deliberate expected-fail `todo()`
markers pinning known open gaps (they flip green when the fix ships — see
"Pinned findings" below).

## Running

Locally (Docker required):

```sh
supabase start -x studio,inbucket,imgproxy,edge-runtime,logflare,vector
supabase test db
```

`supabase test db` runs pg_prove over `supabase/tests/*.sql` against the local
stack (which has pgTAP available; each file also does
`CREATE EXTENSION IF NOT EXISTS pgtap`). Files run **serially in filename
order** — `000_helpers.sql` runs first and **commits** the `tap` helper schema
(personas + fixture builder); every other file is fully transactional
(`BEGIN … ROLLBACK`), so the database is left pristine between files and
between runs. Tests target catalog objects and behavior, never migration
filenames — which is why the migration-filename normalization (Scheme B,
completed 2026-08-26; repo and ledger now 1:1 at 85/85) did not affect them.

## CI wiring (done — no longer an integrator TODO)

~~Do AFTER PR #5 merges.~~ **The suite is wired and executing.** It runs in the
`db` job of `.github/workflows/ci.yml` (`pgTAP database security suite`), against
the same freshly-replayed stack that job already boots, followed by
`pgTAP result summary`, which is what actually gates. No committed
`supabase/config.toml` is needed: the `db` job runs `supabase init` when the
config is absent, and `supabase test db` picks up `supabase/tests/` from the
initialized workdir.

The `db` job pins the **Supabase CLI to `2.115.0`** (job-level
`env.SUPABASE_CLI_VERSION`, asserted before any migration step). Run the suite
locally on that same version or your result says nothing about CI.

`supabase db lint --level warning` is still **not** wired — it remains a
placeholder, tracked in `.github/workflows/README.md` under "Intentionally
deferred".

## Files

Counts below are the `plan(N)` value in each file and were re-derived from the
files themselves (`grep -ho 'plan([0-9]*)' supabase/tests/*.sql`), not copied
forward. They sum to **214**, which is what the CI gate compares assertions-run
against — if you change a `plan()`, change the row here in the same commit.

| File | Tests | Covers |
|---|---|---|
| `000_helpers.sql` | 6 | Persona helpers + fixture builder (commits `tap` schema) |
| `005_service_path.sql` | 12 | `request_is_service_role()` (055) never true under a client persona, and the `auth.uid()` → `p_user_id` identity resolution every strict-auth RPC is built on (059/059b/061) — the fail-open that would make `p_user_id` an identity-forgery parameter |
| `010_rls_smoke.sql` | 20 | RLS on every public table; deny-all tables have zero policies; policy surface pinned (070) |
| `020_profiles_columns.sql` | 20 | 052/068 exact 8-column SELECT sets, 041 exact 6-column UPDATE set, private-field denials, `get_my_profile()` |
| `030_anon_boundaries.sql` | 28 | anon can browse and nothing else; all writes + financial RPC EXECUTE closed (055c/059/063/067) |
| `040_authenticated_boundaries.sql` | 36 | cross-user no-ops, self-escalation denials, listing gate (036/038), listing state guard (046), bid immutability, strict identity (059), and the DB-1 `proof_status` review boundary (071 — seller cannot self-approve, service path may set it, INSERT paths covered) |
| `050_transfers_custody.sql` | 18 | direct state writes blocked for authenticated AND service_role AND owner (056b); RPC path works; 056c one-statement bypass window; evidence append-only; state machine |
| `060_payments_money.sql` | 12 | client write ban, one-succeeded-payment-per-listing (003), one-transfer-per-payment/listing (003), F-2/F-3 TODOs |
| `070_payouts.sql` | 19 | `record_transfer_payout` idempotency + NULL guards + dispute refusal (056d); 065 resolution gate + append-only audit; reversal |
| `080_admin.sql` | 16 | no admin self-grant/enumeration, `is_admin()` client-EXECUTE stripped (067) but semantics intact, risk tables closed, TRUNCATE stripped (063) |
| `090_webhooks.sql` | 21 | 064 claim/complete/fail lease (first-claim-wins, in_flight, already_processed, abandoned-lease recovery, fail releases immediately); 061 verified-payment gate on `ensure_transfer_exists` |
| `100_storage.sql` | 6 | `proof-docs` bucket stays private and reachable only by uploader or transfer counterparty (033/034/049/051/053); public read scoped to the two public buckets. **Catalog-level only, deliberately** — asserting behaviour would require INSERTing into `storage.objects`, whose columns and INSERT triggers differ across storage-api versions |

## Harness rules (read before adding tests)

1. **Always set JWT claims.** `request_is_service_role()` (055) is fail-open
   when `request.jwt.claims` is NULL — a claims-less "authenticated" test
   would let `p_user_id` spoofing succeed and prove nothing. Use
   `tap.login(uid)` / `tap.login_anon()` / `tap.login_service()` /
   `tap.logout()` (trusted service path), never bare `SET ROLE`.
2. **Guard-bypass GUCs are transaction-local.** Transfers has the 056c
   statement-trigger reset; the **listing** guard does not — any successful
   bid or listing RPC leaves `app.bypass_listing_guard = 'on'` for the rest of
   the transaction. Run listing-guard assertions before such calls, and call
   `tap.reset_guards()` first. (`throws_ok` runs in a savepoint, so failing
   statements never leak GUC state.)
3. Fixtures are deterministic UUIDs (`tap.seller()`, `tap.listing_a()`, …)
   inserted by `tap.seed_core()` as the table owner inside each file's
   transaction. Transfers are INSERTed directly — faithful to production
   (the state guard is BEFORE UPDATE; inserts come from
   `ensure_transfer_exists()`/the webhook).

## Pinned findings (expected-fail `todo()` tests)

* **F-2** (`060` #11): `transfers.stripe_transfer_id` has no unique index
  (self-documented in 056a) — the same Stripe transfer id can land on two
  rows. Flips green when an index migration ships.
* **F-3** (`060` #12): `payments` has no column-guard trigger — the
  money-evidence table's amounts are freely mutable by any service-path
  writer, unlike listings (000/046) and transfers (055).
**There are exactly two, both in `060_payments_money.sql`.** `todo(` appears
nowhere else in the suite, and CI now enforces that (see "Masking ratchet").

~~**proof_status fail-open** (`040` #14)~~ — **FIXED, marker removed.**
`guard_proof_status()` (033) used to key on the legacy
`request.jwt.claim.role` GUC, which modern PostgREST does not set, and
otherwise exempted `session_user = 'postgres'`; for a real client request both
checks resolved false, the trigger fell through, and a seller could set their
own listing `proof_status = 'approved'` (self-verification). **Migration `071`
shipped the rewrite (DB-1).** `040_authenticated_boundaries.sql` now asserts
the boundary *positively* — seller self-approve is refused, the service path
may set it, and the INSERT paths are covered — as ordinary passing
assertions, not a `todo()`.

## Masking ratchet (why a green gate can still be a lie)

pgTAP `todo()` failures **do not fail `pg_prove`**: `Result:` stays `PASS` and
assertions-run still equals assertions-planned. Every other guard in the CI
step is therefore blind to a failing security assertion that someone wrapped in
`todo()`. This was live: run `33090393102` reported `todo_failing=2` and
succeeded, because the step computed that number and only *printed* it.

The `pgTAP result summary` step in `ci.yml` now gates on three things:

1. **Runtime** — `todo_failing` must be `<= EXPECT_TODO` (currently **2**).
2. **Static** — `todo(` occurrences in `supabase/tests/*.sql` must be
   `<= EXPECT_TODO`. Needed because a `todo()` wrapped around an assertion
   that currently *passes* emits no runtime marker at all.
3. **No `skip()`** — skipped assertions still count toward `Tests=`, so they
   satisfy the ran-vs-planned check and can never fail. Zero occurrences today.

**When you fix a pinned finding, delete its `todo()` and LOWER `EXPECT_TODO`
in the same PR.** Never raise it to make a red build pass; a genuinely new
pinned gap is a reviewed decision, not a ratchet bump of convenience.

Also observed, documented here rather than tested: the migration chain does
NOT create `profiles.is_admin`, `trust_status_override`,
`stripe_connect_status`, `stripe_payouts_enabled`, `stripe_charges_enabled` —
those columns exist only in production (out-of-band drift; 052/062 comments
reference them). `020` contains conditional assertions that deny client
SELECT on them **if** they get vendored.

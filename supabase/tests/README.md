# DB security gate — executable pgTAP suite

> **STATUS 2026-08-27 — THIS SUITE NOW EXECUTES IN CI.**
> It ran for the first time on 2026-08-27 (it had never been executed before).
> Current: **17 files, 305 assertions**, via
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

**305 assertions** across 17 files. 2 are deliberate expected-fail `todo()`
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
filenames, so the pending migration-filename normalization (PR #5) does not
affect them.

## CI wiring (integrator note — do AFTER PR #5 merges)

To avoid ci.yml conflicts with the migration-normalization PR, this PR does
**not** touch `.github/workflows/`. In the existing `db` job, after
`supabase start` (which already proves the chain replays), add:

```yaml
- name: pgTAP security gate
  run: supabase test db
- name: Static lint
  run: supabase db lint --level warning
```

No committed `supabase/config.toml` is needed: the db job already runs
`supabase init` when the config is absent, and `supabase test db` picks up
`supabase/tests/` from the initialized workdir.

## Files

| File | Tests | Covers |
|---|---|---|
| `000_helpers.sql` | 6 | Persona helpers + fixture builder (commits `tap` schema) |
| `010_rls_smoke.sql` | 20 | RLS on every public table; deny-all tables have zero policies; policy surface pinned (070) |
| `020_profiles_columns.sql` | 20 | 052/068 exact 8-column SELECT sets, 041 exact 6-column UPDATE set, private-field denials, `get_my_profile()` |
| `030_anon_boundaries.sql` | 28 | anon can browse and nothing else; all writes + financial RPC EXECUTE closed (055c/059/063/067) |
| `040_authenticated_boundaries.sql` | 22 | cross-user no-ops, self-escalation denials, listing gate (036/038), listing state guard (046), bid immutability, strict identity (059) |
| `045_listing_insert_authority.sql` | 20 | H-1: INSERT-side column custody on `public.listings` — forged `winner_user_id`/`winning_bid_amount`/`current_bid`/`bid_count`/auction state/settlement timestamps/backdated `created_at` are rejected at creation (072); `app.bypass_listing_guard` does not open the INSERT path; ordinary + Buy Now seller creation, the service path and the operator path all still work |
| `050_transfers_custody.sql` | 18 | direct state writes blocked for authenticated AND service_role AND owner (056b); RPC path works; 056c one-statement bypass window; evidence append-only; state machine |
| `060_payments_money.sql` | 12 | client write ban, one-succeeded-payment-per-listing (003), one-transfer-per-payment/listing (003), F-2/F-3 TODOs |
| `070_payouts.sql` | 19 | `record_transfer_payout` idempotency + NULL guards + dispute refusal (056d); 065 resolution gate + append-only audit; reversal |
| `080_admin.sql` | 16 | no admin self-grant/enumeration, `is_admin()` client-EXECUTE stripped (067) but semantics intact, risk tables closed, TRUNCATE stripped (063) |
| `090_webhooks.sql` | 21 | 064 claim/complete/fail lease (first-claim-wins, in_flight, already_processed, abandoned-lease recovery, fail releases immediately); 061 verified-payment gate on `ensure_transfer_exists` |
| `110_money_authz_matrix.sql` | 18 | MONEY-1: the impersonation matrix for `request_is_service_role()` (0550) — legacy singular GUC precedence, disagreeing/malformed/empty claims, SQL-role irrelevance, anon grant posture, and forged `p_user_id` refused across the money RPCs (17/18 are a matched negative/positive pair against a reserved fixture, so 17 discriminates on identity) |

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
  **MONEY-1 classification (2026-08-27): KEPT AS `todo()`, still open.**
  Re-confirmed live against production: `pg_indexes` for `public.transfers`
  contains no unique index mentioning `stripe_transfer_id`. Production data is
  currently clean (36 transfers, 23 with a `stripe_transfer_id`, 23 distinct),
  so `CREATE UNIQUE INDEX ... WHERE stripe_transfer_id IS NOT NULL` would build
  without conflict. Not implemented here because MONEY-1 is an authorization
  audit and this is a DDL/uniqueness fix on a live money table — it belongs in
  its own migration with its own rollback and deploy window, and that branch is
  deliberately tests-only.
* **F-3** (`060` #12): `payments` has no column-guard trigger — the
  money-evidence table's amounts are freely mutable by any service-path
  writer, unlike listings (000/046) and transfers (055).
  **MONEY-1 classification (2026-08-27): KEPT AS `todo()`, still open.**
  Re-confirmed live against production: no trigger on `public.payments`
  constrains `amount`/`status`. Not implemented here for the same reason as
  F-2 — a column-guard trigger on the money-evidence table is DDL on a live
  money table and needs its own migration, rollback and deploy window, not a
  tests-only branch.
* **proof_status fail-open** (`040` #14): `guard_proof_status()` (033) keys on
  the legacy `request.jwt.claim.role` GUC, which modern PostgREST does not
  set, and otherwise exempts `session_user = 'postgres'` — for a real client
  request both checks resolve false and the trigger falls through, so a
  seller can set their own listing `proof_status = 'approved'`
  (self-verification). Fix: rewrite the guard against `request.jwt.claims`
  (or column-revoke `proof_status` from `authenticated`, which is what the
  TODO asserts).

Also observed, documented here rather than tested: the migration chain does
NOT create `profiles.is_admin`, `trust_status_override`,
`stripe_connect_status`, `stripe_payouts_enabled`, `stripe_charges_enabled` —
those columns exist only in production (out-of-band drift; 052/062 comments
reference them). `020` contains conditional assertions that deny client
SELECT on them **if** they get vendored.

# Production release package — prepared, NOT executed

Date: 2026-09-10 · Owner: release integration.

**Nothing in this document has been executed.** No migration was applied to production, no edge deployed, no
flag changed, no cron touched, no Stripe setting changed, no AWS mutation, no merge to `main`. Every production
figure below is a read-only query.

## 1. Pinned candidate

| | |
|---|---|
| Branch | `release/convergence-135` |
| Commit | **`7986711`** |
| Base | `562fda9` (production-aligned 135 line) |
| Contains | payments RC P1–P3 · v2 consumer UI · tickets ownership RPC · filter-sheet fix · admin/ops console 115–120 · signing/door 110–114 |
| CI evidence | run **34320158401**, head `7986711`, **all five jobs green** |

CI at that exact commit: Gate-2 `tables=30 functions=88 policies=37 triggers=33`; pgTAP
`Files=71, Tests=4698, Result: PASS`; `deno check OK: 15 entrypoints (11 deployed + 4 production-aligned)`;
Typecheck/Lint/Unit, Admin console and Web build all success.

Local corroboration at the same tree: convergence rehearsal 18/18 (fresh order, production order, and an
identical function-definition hash across both); payments rollback battery 63/63; mobile 1531/1531; admin
96/96; migration immutability + ordering clean; G-4 assembled-migration integrity PASS.

## 2. Production ledger reconciled against the candidate

Read-only, 2026-09-10:

```
production ledger rows        135      numeric tip 120      max version 20260902003623
candidate chain               140
pending                         5
```

Each of the five was checked individually against `supabase_migrations.schema_migrations`; all five return
`applied_in_prod = 0`. Nothing is applied in production that is absent from the candidate. `110`–`120` are
already in production and are **not** part of this release.

## 3. Execution order

### 3a. Migrations — 5, in this order

| # | Version | What it does | Rollback |
|---|---|---|---|
| 1 | `20260906100000_checkout_reservation_authority` | reservation/settlement authority; `settle_listing_for_payment` | `…_rollback.sql` |
| 2 | `20260906110000_settle_verified_payment` | the single verified-settlement contract + `get_unsettled_payments` | `…_rollback.sql` |
| 3 | `20260906120000_payout_attempts_and_refund_monotonic` | payout attempt ledger, append-only `payment_refunds`, `amount_refunded_cents`, `account_deletions` | `…_rollback.sql` (archives in-transaction) |
| 4 | `20260906130000_deletion_sweep_live_rail_obligations` | BP-13 arm on `kernel.sweep_deletion_pending` (external rail only) | `…_rollback.sql` |
| 5 | `20260909000000_kernel_my_tickets_read` | `public.get_my_tickets()` — additive, read-only, one function + grant | `…_rollback.sql` |

Order is the canonical `LC_ALL=C` filename sort and matches what the rehearsal exercised. Migrations 1–4 have
inter-dependencies (2 requires 1; 4 requires 3); 5 depends only on Phase-2 `079`/`080`, already live.

### 3b. Edge deployments — 9, after the migrations

Changed between production's deployed Phase-2 tip and the candidate, therefore requiring redeploy:

`confirm-and-release` · `confirm-payment` · `create-connect-account` · `create-payment-intent` ·
`delete-account` · `enforce-transfer-expiry` · `notify-report` · `notify-transfer` · `stripe-webhook`

Unchanged, **do not redeploy**: `send-push`, `auto-finalize-auctions`.
Shared modules pulled in by the above: `_shared/payout-logic.ts`, `_shared/payouts.ts`.
Not deployed by this release and not to be deployed: `ops-refund-execute`, `credential-sign`, `door-manifest`,
`door-session`, `connect-onboarding`, `payout-execute`, `primary-checkout`, `refund-execute`.

**Migrate-then-deploy is mandatory** — the new edges call RPCs that only exist after migrations 1–4.

### 3c. Mobile — last

Production profile build from `7986711`, then TestFlight/App Store submission. The client depends on
`settle_verified_payment` (three-outcome settlement copy) and `get_my_tickets` (Tickets tab), so it must not
reach users before 3a and 3b are complete. `eas.json`'s `production` profile is byte-identical to the shipped
one and points at production Supabase + the live Stripe key; the compile-time environment guard fails the build
on any mispairing.

## 4. Validation after each stage

| Stage | Check | Expected |
|---|---|---|
| after 3a | ledger row count | 135 → **140** |
| after 3a | Gate-2 census | `tables=30 functions=88 policies=37 triggers=33` |
| after 3a | `public.get_my_tickets` | exists, `SECURITY DEFINER`, `search_path=public, pg_temp`, EXECUTE to `authenticated` only |
| after 3a | `kernel.signing_key` rows · native flags | still `0` · all three still `false` |
| after 3b | `list_edge_functions` | 11 functions, the nine redeployed at a new version, `verify_jwt` unchanged per function |
| after 3b | one real checkout end-to-end | single payment row, single PaymentIntent, no duplicate transfer |
| after 3b | `get_unsettled_payments` | drains to 0 |
| after 3c | client on production | no "contact support" on a cancelled sheet; Tickets tab renders the empty state |

## 5. Abort conditions

Stop and roll back the current stage if any of these holds:

1. Any migration errors, or the ledger lands on a count other than 140.
2. Gate-2 census differs from `30 / 88 / 37 / 33`.
3. `kernel.signing_key` becomes non-zero, or any `feature.native_*` flag becomes true — neither is part of this
   release.
4. A duplicate payment, duplicate transfer, or a payout without a matching attempt row appears in the first
   post-deploy checkout.
5. `AUTODEPLOY-VERIFIED-OFF` is missing from the merging PR, or `supabase branches list` shows a non-empty
   `git_branch` — merging would then apply migrations to production automatically (AUTODEPLOY-1).
6. Edge deploy is attempted before the migrations complete (PGRST202 on the new RPCs).
7. The payout cron is running during the edge deploy window — pause it first; a payout issued by old code
   inside the window creates a transfer with no attempt row.

## 6. Rollback limitations — read before relying on rollback

- **Edge order is inverted on the way back.** The pre-package edges must be redeployed *before* running the
  `20260906120000` rollback, or every payout/refund/deletion call fails `PGRST202` on the now-missing RPCs.
- **The rollbacks refuse while money is in flight.** Each of the four payment rollbacks raises
  `rollback … REFUSED - unsafe state present` while any D-detector is non-zero — open payout attempts,
  unsettled payments, unresolved reviews, identities held only by BP-13. Draining is a deliberate operator step,
  not an automatic one. `app.rollback_force=on` exists but must not be used without a ticket.
- **Rollback order is enforced.** `20260906130000` must go before `120000`, `110000` before `100000`; an
  out-of-order attempt is refused (O1/O2).
- **Data survives only via the archive.** `payout_attempts`, `payment_refunds`, `account_deletions` and the
  `amount_refunded_cents` facts are archived into `rollback_archive` inside the rollback transaction and
  restored by the forward migration on re-apply; a second rollback refuses while an unrestored archive exists.
  Export with `\copy` as well.
- **The deploy window is not reversible.** A payout issued by old code after rollback produces a transfer with
  no attempt row, and the unique index is gone at that point, so a duplicate `tr_` is possible. Re-applying
  `120000` aborts on such a duplicate until an operator resolves it — proven in the rollback battery (F12–F13).
- **Migration 5 is trivially reversible** (drops one function) and is independent of the payment rollbacks.
- **Forward fix is preferred** once real financial rows exist under the new schema; rollback becomes unsafe as
  soon as the drain cannot be completed quickly.

## 7. Scope boundaries

### Resale / marketplace release — this package

Migrations 1–5, edges 3b, mobile 3c. Ships the payments-reliability work, the v2 consumer UI, the
reservation-cancellation fix and the Tickets **read** surface. `get_my_tickets` returns the defined **empty
set** in production because `kernel.tickets` is empty; it neither requires nor enables native issuance.

### Native issuance / scanning — NOT this package

Requires, in its own separately gated sequence: C3 (inserting the trust root into `kernel.signing_key`,
governed by `110`'s insert guard, with `111` as two-person recovery), key delivery to the door plane (`114`),
deploying the native edges, and flipping `feature.native_issuance_enabled` / `feature.native_scanning_enabled`.
None of that is in scope here and none of it is authorized.

**AWS status: see Claude B's ceremony record**,
`docs/release/PHASE2_PFA18C_SINGLE_FOUNDER_KMS_BOOTSTRAP_EXECUTION.md` §SESSION 8 — C2–C5 complete, key
corroborated read-only, C3 not authorized and not performed. This package does not advance C2 or C3 and takes
no dependency on them.

## 8. Release-gate table

| Gate | Status | Detail | Owner |
|---|---|---|---|
| Candidate pinned + CI green at head | **PASSED** | `7986711`, CI 34320158401, five jobs green | release integration |
| Migration chain verified both orders | **PASSED** | 18/18; identical function hash fresh vs production order | release integration |
| Rollback battery | **PASSED** | 63/63 incl. archive, restore, deploy-window duplicate | release integration |
| Repo test suites | **PASSED** | pgTAP 4698 · mobile 1531 · admin 96 · typecheck · lint · web build · deno | release integration |
| Migration immutability + ordering, G-4 | **PASSED** | zero errors; assembled migrations match committed slices | release integration |
| Production ledger reconciliation | **PASSED** | 135 vs 140; exactly 5 pending, each confirmed unapplied | release integration |
| Sandbox tickets RPC verified | **PASSED** | ledger row, `SECURITY DEFINER`, empty result for authenticated, 401 for anon | release integration |
| Compiled sandbox build environment | **PASSED** | one Supabase URL, one anon JWT, sandbox Stripe account, zero secrets | release integration |
| Sandbox edge source parity | **PASSED** | all 9 deployed edges byte-identical to the release head | release integration |
| **Handset QA — 11 cases on the preview build** | **PENDING EVIDENCE** | only D3/D4 + auth-logo done, on an older binary; D1, D2, D5–D11 outstanding | Claude C |
| **`notify-transfer` change is untested** | **PENDING EVIDENCE** | changed in this release but not deployed to the sandbox, so no QA covers it | Claude C / release integration |
| **Edge auth parity (`verify_jwt`)** | **PENDING EVIDENCE** | sandbox runs `verify_jwt=false`; "edge rejects unauthenticated" cannot be signed off from sandbox | Claude C |
| **Push routing on a real device** | **PENDING EVIDENCE** | `notify-transfer` absent in sandbox; push must be proven elsewhere | Claude C |
| **Partial-refund exactness in ops** | **IMPLEMENTATION NEEDED** | proposed `121_ops_console_refund_exactness`; server-only, client already supports `certainty:'known'`; §14 acceptance cases A1–A8 | release integration, after owner decision |
| **Public `auction-media` evidence exposure** | **UNRESOLVED RELEASE RISK** | see below | owner + release integration |
| Deletion amendment PFA-32 signature | **OWNER DECISION** | required before the deletion behaviour ships | owner |
| Stripe `payment_intent.canceled` subscription | **OWNER DECISION** | webhook endpoint change | owner |
| Legacy orphan reconciliation + payout-cron pause | **OWNER DECISION** | must be scheduled inside the deploy window | owner |
| `AUTODEPLOY-VERIFIED-OFF` on the merging PR | **OWNER DECISION** | date-only line; `git_branch` must be empty at merge time | owner |
| Apply/deploy authorization itself | **OWNER DECISION** | nothing in §3 is authorized today | owner |
| Twilio Account SID rotation | **OWNER DECISION** | identifier, not a secret; local history still holds it | owner |
| C3 / native issuance | **OUT OF SCOPE** | separately gated; see §7 and Claude B's record | owner + Claude B |

### Unresolved release risk — legacy evidence in the public `auction-media` bucket

**27 objects** — 16 `listings.proof_of_ownership_path` and 11 `transfers.transfer_evidence_path`, 41 MB across
8 owner folders — sit in a bucket whose policy is `public read public buckets`. They are ticket-ownership
documents (screenshots, confirmations, typically carrying names, order numbers and barcodes) and are fetchable
without authentication by anyone who knows or can enumerate the object path. The private-bucket policies that
gate `proof-docs` do not apply to them.

Scope is closed, not growing: of 35 listings with a proof path, 19 are already private and 16 are legacy; of 17
transfers with an evidence path, 6 are private and 11 are legacy; nothing has landed in `auction-media` as
evidence since 2026-07-02.

**Owner:** owner decision on scope, executed by release integration as its own change.
**Proposed remediation scope** (deliberately *not* bundled with this release): copy the 27 objects to
`proof-docs`, repoint `listings.proof_of_ownership_path` / `transfers.transfer_evidence_path`, verify each new
object is reachable only through the private policies, then delete the public copies — with a rollback that
restores the paths, and an explicit check that a tombstoned account's evidence is not resurrected into the new
bucket. A separate owner decision covers the 7 unreferenced objects (delete or archive). This is data movement
touching the deletion/tombstone machine and must not ride along with a schema release.

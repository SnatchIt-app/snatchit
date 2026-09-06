# Verification evidence (local isolated DB + CI; nothing against production)

Environment: loopback PostgreSQL 17 rehearsal harness (`scripts/rehearsal_*`), Node vitest with the real edge handlers
loaded in a vm (`tests/helpers/edge-vm.ts`), GitHub Actions CI on branch `fix/payments-reliability`. Mocked-handler
tests, database tests, and CI are reported separately from anything requiring a device, a Stripe sandbox, or
production — none of the latter were executed (see §5).

## 1. Reverse rollback rehearsal (3 → 2 → 1 → re-apply 1 → 2 → 3 → re-apply again)

Database `snatchit_pay_rb_rehearsal`, fresh replay of the 92-migration chain (main's 89 + the three packages).
Census = public tables | functions | policies | triggers | md5 over the 16 package function definitions.

| Step | Census / chain hash |
|---|---|
| fresh replay (all three) | `30 | 83 | 37 | 28 | 8bbcc4d6…` |
| rollback 20260906120000 (P3) | `27 | 72 | 37 | 24 | c78d72f8…` |
| rollback 20260906110000 (P2) | `27 | 70 | 37 | 24 | 63b28cc3…` |
| rollback 20260906100000 (P1) | `27 | 69 | 37 | 24 | 5a856322…` (= main-only baseline) |
| apply P1 | `27 | 70 | 37 | 24 | 63b28cc3…` (identical to post-P2-rollback state) |
| apply P2 | `27 | 72 | 37 | 24 | c78d72f8…` |
| apply P3 | `30 | 83 | 37 | 28 | 8bbcc4d6…` (identical to fresh replay) |
| second apply of all three | `30 | 83 | 37 | 28 | 8bbcc4d6…` (idempotent) |

Suites after the re-apply: 060 12/12 · 120 58/58 · 121 75/75 · 122 53/53 · 123 51/51 · 124 24/24 (273/273).
Each package agent additionally verified that its rollback restores the prior function bodies VERBATIM against the
original migration text (0590 for P1, 000 for P2; P3 adds objects only).

## 2. Per-package red → green (from the package reports, `implementation/`)

| Package | Failing-first evidence | Green |
|---|---|---|
| P1 | pgTAP 120 `plan=49 ok=8 not_ok=12 psql_err=36` before; vitest checkout-intent 5 failed | 120 49/49 → rev2 58/58; vitest 10/10 → 23/23 |
| P1 rev2 (review fixes) | 120 not_ok=7 (H1–H9); vitest 11 failed | 58/58; 142/142 root |
| P2 | pgTAP 121 `ok=0 psql_err=83`; vitest 24 failed | 121 75/75; 158 root |
| P3 | pgTAP 122 `not_ok=5 psql_err=57`, 123 `not_ok=23 psql_err=18`, 124 `psql_err=32`; vitest 27 failed | 122 53/53, 123 51/51, 124 24/24, 060 12/12 (TODOs now real) |

## 3. Required scenarios → where proven

| Scenario | Proof |
|---|---|
| Two buyers competing for one listing | 120 A/D/H, `tests/checkout-intent.test.ts` (foreign holder 409, no PI create, other buyers' pending PIs cancelled on mint) |
| Direct RPC marks an unpaid listing sold | 120 B1–B4 (`mark_listing_sold` / `complete_auction_payment` raise 'No verified payment…'); 110 #17/#18 |
| Reservation expiry/release during checkout/3DS | 120 D (lapsed reservation + verified payment settles), checkout-intent X1 (expired ⇒ stale PI cancelled), `payment_intent.canceled` ⇒ `release_reservation` (settlement-webhook) |
| Old PaymentIntent confirmed after inventory changed | 121 unfulfillable (listing sold to another / one-success collision) ⇒ review row; sweep refund with `refund_unfulfillable_<payment_id>` (settlement-sweep) |
| Buy Now vs auction mode mismatch | 120 (buy_now payment does not satisfy the auction wrapper; foreign live hold refuses the winner), checkout-intent |
| Duplicate and out-of-order webhooks | settlement-webhook (same event id ⇒ already_processed; two events ⇒ already_settled; refund-before-success ⇒ no promotion); refund-dispute-webhook |
| Crash after payment promotion, before sale settlement | settlement-webhook F02: first delivery 500 + `fail_stripe_webhook_event`; retry calls settle AGAIN ⇒ 200, listing sold |
| Crash after sale settlement, before transfer creation | 121 settle twice ⇒ one transfer, `already_settled`; core heals a missing transfer |
| Refund/dispute DB update failure | refund-dispute-webhook: DB failure ⇒ 500 + `fail_stripe_webhook_event` (no silent 200) |
| Confirmation after refund | 121 (refunded terminal), 123 guard (`refunded → succeeded` raises), settlement-confirm |
| Stripe accepts payout but response/DB write lost | payout-attempts / payout-races: `processing`, next run reconciles via `transfer_group` list, POST count 1 |
| Retry after the idempotency retention window | payout-races (>24h): one transfer; new attempt only after the previous is terminal |
| Destination/account change during recovery | payout-attempts: frozen destination reused; 122 immutability |
| Dispute between eligibility check and payout completion | 122 + confirm-and-release vm test: `tr_` recorded, attempt `reversal_required`, decision `PAID_DURING_DISPUTE` |
| Account deletion with pending refund / dispute / unpaid seller obligation | 124 blockers; delete-account vm test 409 / 503 / phase order |

## 4. Whole-branch runs (integration branch, three packages merged)

Recorded in `implementation/` and the final report: replay 92/92; Gate-2 30/83/37/28; full pgTAP; root vitest; web
vitest/typecheck/lint; package parity; CI run ids.

## 5. Not executed (and why)

- iOS/Android builds, PaymentSheet, Apple Pay, 3DS, browser E2E: no device/sandbox in this environment; the client
  contracts were verified by code reading (`CheckoutNative.tsx`, `src/lib/payments.ts`, `web/src/lib/checkout.ts`).
- Stripe sandbox end-to-end (real PaymentIntent → webhook → settle → transfer): no sandbox keys were used; all Stripe
  I/O is mocked at the transport (`stripeFetch`/`stripeFetchRaw`) in the vm harness. Recommended before production:
  one sandbox pass per package on a staging project (never the production project).
- Fresh replay on the pinned Supabase CLI stack: performed by CI's `db` job (Docker is unavailable locally); the
  loopback harness is the local approximation and documents its fidelity ledger.
- `deno check`: runs in CI (advisory); not available locally.

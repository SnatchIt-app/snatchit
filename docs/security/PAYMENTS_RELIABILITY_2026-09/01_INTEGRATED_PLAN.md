# Integrated implementation plan (ratified by the lead, 2026-09-06)

Inputs: investigation reports A/B/C (`investigation/`), verified baseline (`00_BASELINE.md`).
Lead owns: shared contracts, migration sequencing, `tests/helpers/edge-vm.ts`, CI wiring, client compatibility,
Gate-2 counts, integration/merges, independent review assignment.

## Ratified cross-cutting decisions

1. **Money wins.** A `succeeded` payment that is bound to (listing, buyer, mode, amount, currency, livemode) settles the
   listing even if the buyer's reservation lapsed or another buyer currently holds a live reservation (that buyer cannot
   have paid: create-payment-intent binds to the holder and `idx_payments_one_success_per_listing` admits one success).
   A capture that can no longer be fulfilled (listing already sold to another payment, cancelled) is `unfulfillable`
   and enters the compensation queue (review row + refund by the sweep). No 3-day 500 loops for terminal outcomes.
2. **Reservation is server-owned.** TTL fixed at 10 minutes (the `p_minutes` argument is accepted for wire compatibility
   and ignored beyond clamping); a holder re-reserving keeps the existing window (no extension); one live reservation
   per buyer — reserving another listing releases the previous one; `check_rate_limit(caller,'reserve_buy_now',20,600)`
   fail-closed. Signature `reserve_buy_now(uuid,uuid,integer)` unchanged.
3. **Buy-Now hold has priority over an auction win while live.** `finalize_auction` is unchanged; `create-payment-intent`
   (auction branch) and `complete_auction_payment` refuse while another buyer's reservation is live; the Buy-Now branch
   requires `reserved_by = caller AND reserved_until > now()`. Explicit expired/superseded handling: a stale pending PI
   of the refused buyer is cancelled and its row marked `failed`.
4. **One listing-settlement core.** `public.settle_listing_for_payment(p_payment_id uuid) RETURNS text` (Package 1;
   SECURITY DEFINER; EXECUTE revoked from PUBLIC/anon/authenticated/service_role — reached only through owner
   functions): given a `succeeded` payment row it marks the listing `sold` (or returns `already_settled`), creates the
   transfer row (`ON CONFLICT (payment_id) DO NOTHING`), never expires a reservation as a side effect, and returns
   `settled | already_settled | unfulfillable`. The shipped-client wrappers `mark_listing_sold` /
   `complete_auction_payment` require a bound succeeded payment for `auth.uid()` and delegate to the core.
5. **One verified-settlement contract.** `public.settle_verified_payment(...)` (Package 2, `service_role` only) verifies
   identity/amount/currency/livemode/mode against the stored row, enforces refund monotonicity, promotes only on Stripe
   `succeeded`, calls the core, and records non-settling outcomes in `webhook_retries` (existing empty table, no client
   grants) as the compensation/review queue. Used by the webhook, `confirm-payment`, and a reconciliation sweep in
   `enforce-transfer-expiry` that re-fetches the PI from Stripe.
6. **Refund/dispute facts are monotonic** (Package 3): BEFORE UPDATE guard on `payments` (`refunded` terminal; money
   columns immutable once `succeeded`), append-only `payment_refunds`, `amount_refunded_cents`. `charge.dispute.closed`
   lost is a chargeback: recorded with the dispute id, never as `stripe_refund_id`.
7. **Payouts are ledgered per attempt** (Package 3): `payout_attempts` with immutable request parameters and a
   per-attempt idempotency key; an open/unknown attempt is reconciled (Stripe list by `transfer_group`) before any new
   POST; a transfer Stripe reports is ALWAYS recorded even when eligibility changed (then `reversal_required` + manual
   review); partial UNIQUE on `transfers.stripe_transfer_id`. No DB lock is held across a network call.
8. **Account deletion fails closed** (Package 3): `account_deletion_blockers(uuid)` covers unsettled transfers of every
   status, paid-without-transfer, expired-unrefunded, open disputes, open/unknown payout attempts, open manual reviews;
   the `main` handler returns 409 with reasons / 503 on lookup error. The deployed tombstone sweep (Phase-2 `078`) must
   call the same predicate when the branches converge — recorded as an integration dependency.
9. **No client change is required for compatibility.** Build 13 and web call `confirm-payment` before the wrappers, so
   the wrappers succeed on the happy path and no-op when the server settled first. Error strings for the refused cases
   match the regexes in `src/lib/payments.ts` so field builds show a real message.

## Migration versions (timestamp scheme; sort after main `075` and prod `109`/`20260902003623`)

| Version | Package | Objects |
|---|---|---|
| `20260906100000_checkout_reservation_authority` | 1 | `reserve_buy_now` (body), `mark_listing_sold` (body), `complete_auction_payment` (body), `settle_listing_for_payment` (new, zero client grant) |
| `20260906110000_settle_verified_payment` | 2 | `settle_verified_payment` (new, service_role), `get_unsettled_payments` (new, service_role), `cleanup_expired_reservations` (body: skip paid listings) |
| `20260906120000_payout_attempts_and_refund_monotonic` | 3 | `payout_attempts` + indexes + `guard_payout_attempt_columns`, partial UNIQUE `transfers.stripe_transfer_id`, `guard_payment_transitions`, `payment_refunds`, `payments.amount_refunded_cents`, `record_payment_refund`, `claim_payout_attempt`, `mark_payout_requested`, `record_payout_attempt_result`, `reconcile_payout_attempt`, `account_deletion_blockers`, `account_deletions` |

Each ships with `supabase/rollbacks/<version>_rollback.sql`, manifest lines in
`supabase/ci/assert_public_table_grant_decisions.sql` (+ `expected_grants.txt` for table grants), and the Gate-2 count
delta reported to the lead (the lead edits `.github/workflows/ci.yml`).

## File ownership (one owner per file per package window)

| Package | Owner | Files |
|---|---|---|
| 1 | Agent A | migration 1 + rollback; `supabase/functions/create-payment-intent/index.ts`; `supabase/tests/120_reservation_lifecycle.sql`; `supabase/tests/110_money_authz_matrix.sql` (fixture for #18 only); `tests/checkout-intent.test.ts`; manifest lines |
| 2 | Agent B | migration 2 + rollback; `supabase/functions/stripe-webhook/index.ts` — `payment_intent.succeeded`/`payment_failed` branches and the `finish`/`markProcessed` acknowledgment semantics; `supabase/functions/confirm-payment/index.ts`; `supabase/functions/enforce-transfer-expiry/index.ts` — NEW reconciliation phase only; `supabase/tests/121_settlement.sql`; `tests/settlement-webhook.test.ts`, `tests/settlement-confirm.test.ts` |
| 3 | Agent C | migration 3 + rollback; `supabase/functions/confirm-and-release/index.ts`; `supabase/functions/enforce-transfer-expiry/index.ts` — payout Phase 2/2b only; `supabase/functions/stripe-webhook/index.ts` — `charge.refunded`, `charge.dispute.*`, `transfer.created`, `transfer.reversed` branches only; `supabase/functions/delete-account/index.ts`; `supabase/functions/_shared/payouts.ts`, `payout-logic.ts`; `supabase/tests/122_payout_attempts.sql`, `123_payment_monotonic.sql`, `124_account_deletion.sql`; `tests/payout-*.test.ts`, `tests/payout-attempts.test.ts`, `tests/delete-account.test.ts` |
| lead | — | `tests/helpers/edge-vm.ts`, `.github/workflows/ci.yml`, docs, tracker, integration |

Packages 1 and 3 run in parallel (disjoint files). Package 2 starts when Package 1's core lands on the integration
branch. Where Packages 2 and 3 touch the same file they own disjoint regions; the lead integrates.

## Sequence

P1 (worktree `snatchit-pay-p1`) ∥ P3 (`snatchit-pay-p3`) → lead review + integrate P1 → P2 (`snatchit-pay-p2`) →
integrate P3, P2 → independent review per package (a different agent than the author) → CI on the integration
branch → draft PRs split by package (stacked).

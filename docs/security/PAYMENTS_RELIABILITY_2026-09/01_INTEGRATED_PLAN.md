# Integrated implementation plan — DRAFT (pending Agent A and Agent C ratification)

Lead owns: shared contracts, migration sequencing, `tests/helpers/edge-vm.ts`, CI wiring, client compatibility.
One owner per file. Every migration is append-only, timestamp-versioned (`20260906HHMMSS_<name>.sql`), ships with
`supabase/rollbacks/<same>_rollback.sql`, an entry in `supabase/ci/assert_public_table_grant_decisions.sql`, an
`expected_grants.txt` line where a grant exists, and a deliberate Gate-2 count change in `.github/workflows/ci.yml`.

## Migration version allocation (fixed; sorts after main `075`, prod `109`, prod `20260902003623`)

| Version | Package | Content (owner) |
|---|---|---|
| `20260906100000_checkout_reservation_authority` | 1 | reserve_buy_now server TTL + quota; sale RPCs require bound succeeded payment (A) |
| `20260906110000_settle_verified_payment` | 2 | `settle_verified_payment` + `record_payment_refund` + review queue use of `webhook_retries`; `cleanup_expired_reservations` paid-guard (B) |
| `20260906120000_payout_attempts_and_refund_monotonic` | 3 | payout attempt ledger, unique `stripe_transfer_id`, payments status-transition guard, deletion obligation predicate (C) |

Gate-2 expectations move by exactly the objects above (recorded per migration in the PR body).

## Shared settlement contract (lead-ratified from Agent B §5; A/C interfaces marked)

`public.settle_verified_payment(p_payment_intent_id text, p_stripe_status text, p_amount_received int,
p_currency text, p_livemode boolean, p_amount_refunded int, p_stripe_refund_id text, p_metadata jsonb, p_source text)`
— SECURITY DEFINER, `service_role` only, single transaction, returns `(payment_id, payment_status, listing_status,
transfer_id, outcome)` with `outcome ∈ {settled, already_settled, refunded, unknown_payment, binding_mismatch,
unfulfillable, retry_transient}`.

1. Lock the payment row by PI id; none ⇒ `unknown_payment` (terminal, review row).
2. Bind: `total`, `currency`, `stripe_livemode`, `mode`, `listing_id`, `buyer_id`, `seller_id` (metadata is a cross-check only).
3. Refund monotonicity: `refunded` is terminal; any `p_amount_refunded > 0` records refund and never promotes.
4. Promote only when Stripe says `succeeded`; a partial-unique collision ⇒ `unfulfillable` (another payment already settled the listing).
5. Settle the listing under `FOR UPDATE`: reserved-by-buyer (**A ratifies whether a lapsed reservation with verified money settles**) or ended-auction-winner ⇒ `sold`; else `unfulfillable`.
6. `INSERT transfers … ON CONFLICT (payment_id) DO NOTHING`.
7. Non-settling outcomes write `webhook_retries(payment_id, listing_id, rpc_name='settle_verified_payment', error_message=outcome)` as the compensation/review queue (**C owns the consumer**).

Callers: `stripe-webhook` (`payment_intent.succeeded`, both branches collapse), `confirm-payment` (after Stripe fetch with
`expand[]=latest_charge`), a reconciliation sweep for paid-but-unsettled rows. `mark_listing_sold` /
`complete_auction_payment` remain as compatibility wrappers for shipped mobile builds (A) but settle only when a bound
succeeded payment exists.

## Client compatibility (lead)

Mobile 1.0 build 13 (current binary, `BRANCHES.md`) calls, after PaymentSheet: `confirm-payment` → `mark_listing_sold` /
`complete_auction_payment` (direct RPC) → `ensure_transfer_exists`. Web calls `confirm-payment` → settle RPC →
`ensure_transfer_exists` and refuses to settle when unverified. Both must keep working: the wrappers succeed when the
payment is bound+succeeded (which the client has just confirmed), and become no-ops (`already sold`) when the server
settled first. A build that calls the wrapper BEFORE `confirm-payment` does not exist in the field (build 13 confirms first).

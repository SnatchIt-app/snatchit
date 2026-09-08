# The resulting payment flow (after packages 1–3)

```
reserve_buy_now(listing, buyer, p_minutes)           [authenticated RPC; server-owned]
  window = 10 min regardless of argument · holder re-reserve keeps the window · one live hold per buyer
  (reserving another listing releases the previous unpaid one) · 20 calls / 10 min fail-closed
  · a listing with ANY succeeded payment is "sold in fact" and cannot be reserved

create-payment-intent(listing, mode)                 [edge, buyer JWT]
  buy_now: caller must be the LIVE holder · auction: caller must be the winner and no other buyer may hold a live
  reservation · any succeeded payment by another buyer ⇒ 409 · every refusal retires the caller's stale pending
  PaymentIntent (cancel at Stripe, row → failed) · minting/reusing for the entitled buyer cancels OTHER buyers' pending
  intents · a reused PI must match amount/currency or is cancelled and re-minted · fees: 10% buyer + 10% seller, unchanged

Stripe confirms the card
  ├─ stripe-webhook payment_intent.succeeded ──► settle_verified_payment(pi, status, amount, currency, livemode,
  ├─ confirm-payment (client, after PaymentSheet) ─┤   amount_refunded, refund_id, method, metadata, source)
  └─ enforce-transfer-expiry Phase 0 (cron sweep) ─┘   [service_role; one transaction; state-driven, never "did I run"]
        1 lock payment by PI          → unknown ⇒ review row (terminal)
        2 bind total/currency/livemode/mode/listing/buyer/seller → mismatch ⇒ review row, no writes
        3 refund monotonic: refunded is terminal; amount_refunded ≥ total ⇒ refunded
        4 not succeeded ⇒ no promotion (canceled ⇒ pending → failed)
        5 promote → succeeded (one-success index collision ⇒ unfulfillable + review row)
        6 settle_listing_for_payment(payment)  [zero-grant core, also behind the client wrappers]
              sold to this payment ⇒ already_settled (heals a missing transfer)
              buy_now ⇒ sold (money wins over a lapsed/foreign hold) · auction ⇒ sold iff winner
              else ⇒ unfulfillable + review row
        7 transfer row (ON CONFLICT payment_id DO NOTHING)
  outcomes are terminal for the webhook (200); only an RPC error is a 500 ⇒ Stripe redelivers and settlement RESUMES
  from current state. Old clients still call mark_listing_sold / complete_auction_payment / ensure_transfer_exists:
  they require the buyer's succeeded payment and no-op when the server settled first.
  unfulfillable captures: Phase 0 refunds them (idempotency key refund_unfulfillable_<payment_id>), records the refund,
  never refunds a delivered order, never double-refunds.

Seller sends → buyer confirms (confirm-and-release) or risk/auto-release (enforce-transfer-expiry Phase 2/2b)
  claim_payout_attempt(transfer)  [service_role; snapshots destination + amount; one open attempt per transfer]
     needs_reconcile ⇒ GET /v1/transfers?transfer_group=<transfer> → reconcile_payout_attempt → STOP (no POST this run)
  Stripe pre-flights (no DB locks held) → mark_payout_requested → POST /transfers with key payout_<transfer>_a<n>,
  transfer_group, metadata[attempt_id] → record_payout_attempt_result
     succeeded ⇒ transfers.stripe_transfer_id/payout_released_at ALWAYS written (money moved), and if a dispute arrived
       meanwhile ⇒ attempt reversal_required + manual_review PAID_DURING_DISPUTE
     unknown (network/5xx/409) ⇒ lease extended, next run reconciles before any new POST
     failed_not_created ⇒ attempt closed; a new attempt (_a<n+1>) may open
  transfer.created webhook ⇒ record_payout_attempt_result via metadata.attempt_id (idempotent; unique stripe_transfer_id)
  transfer.reversed ⇒ mark_transfer_reversed

Refunds / disputes
  charge.refunded ⇒ record_payment_refund per refund (amount_refunded_cents monotonic; status refunded only when total)
  charge.dispute.created ⇒ freeze; charge.dispute.closed lost ⇒ record_payment_refund(source dispute_lost, dispute id,
  never a refund id) and, if already paid out, flag_payout_reversal_required + DISPUTE_LOST_AFTER_PAYOUT;
  unknown dispute close ⇒ upsert then handle. DB failure in any financial branch ⇒ non-2xx (Stripe retries).
  guard_payment_transitions: pending→processing|succeeded|failed|refunded · processing→succeeded|failed|refunded ·
  failed→pending|succeeded|refunded · succeeded→refunded · refunded terminal; money columns immutable once succeeded;
  refund ids/timestamps set-once; anonymization only via the bypass GUC used by delete_account_cleanup.

Account deletion (main handler; the deployed tombstone sweep must call the same predicate)
  account_deletion_blockers(user) ⇒ any unsettled transfer, paid-with-no-transfer, expired-unrefunded, open dispute,
  open/unknown payout attempt, open manual review ⇒ 409 with kinds; lookup error ⇒ 503; then phases
  gate → archived (connect id kept on account_deletions) → cleaned → storage → done, restartable from the recorded phase.
```

What did NOT change: fee math and every historical amount; the Stripe signature/lease preamble; `record_transfer_payout`
(kept for old edges); RLS on existing tables; the mobile and web request/response contracts.

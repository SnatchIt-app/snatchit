# Payout and refund terms: draft for the owner's approval, and how refunds actually run (A, 2026-09-24)

This draft replaces the earlier legal rewording (decision list items 9–11), which the owner did not approve wholesale.
Source is the release gate `037092f0`, which production runs.
- The `enforce-transfer-expiry` blob `432b4898…` equals the deployed v41 bundle; it was byte-verified at the #92
  deploy.
- Production facts come from dated, authorised records. No new production read was made.

## A. Refunds: what runs today, and what is switched off

**1. Automatic expiry refund (deployed; `enforce-transfer-expiry` v41, Phase 1 + 1b).**
- **Schedule.** pg_cron calls it about every 2 minutes. The authorised #92 run check read runs at 16:58:00, 17:00:00
  and 17:02:02Z on 2026-09-24. The file header's "every 5 minutes" is stale.
- **When it refunds.**
  - An order's transfer is created at payment settlement with `expires_at = now() + 24 h` (061:111).
  - If the seller hasn't marked it sent by then, `enforce_transfer_expiry()` flips `pending` → `expired`, one run
    per row, under `FOR UPDATE SKIP LOCKED` (0551:11–17).
  - The run then refunds the payment (index.ts :510–700) only if all of these hold:
    - the payment row is found;
    - it is **live-mode**. Test rows are skipped in production; the sandbox admits them only under
      `ALLOW_TEST_MODE_MONEY=1`;
    - it is **not already fully refunded** (status `refunded` or `amount_refunded_cents >= total`);
    - it has a PaymentIntent id.
- **What it does.**
  - `POST /v1/refunds` on the PaymentIntent with **no amount**, so it refunds the whole remaining balance. The
    PaymentIntent amount is the buyer's total, including the service fee (create-payment-intent :717–722, :1073).
  - It uses the fixed idempotency key `refund_expiry_<transfer_id>`.
  - It records the refund with `record_payment_refund`: a ledger row, the amount, and status `refunded` once the full
    total is reached.
  - It pushes a notice to the buyer ("Your full refund has been issued") and to the seller.
- **When something fails.**
  - **The expiry step itself fails:** it is logged and the orders stay `pending`; the next run retries. Payout phases
    still run.
  - **A single order fails** (lookup, missing PaymentIntent, Stripe error): it is logged, and the Stripe error goes to
    Sentry. The order is already `expired`, so **Phase 1b** retries it on every run. Phase 1b picks up expired orders
    whose live payment is still `succeeded`, 20 per run, oldest first, with the same key (:710–790).
  - **Stripe refunded but the database write failed:** the log keeps the refund id. The payment still reads
    `succeeded`, so Phase 1b replays the same key.
    - Within Stripe's idempotency window this returns the same refund, which is then recorded.
    - After the key is pruned (Stripe: about 24 h), a new attempt on a fully refunded payment will be refused. It will
      error on every run (Sentry) until someone reconciles it by hand. No money moves twice.
  - **A live row whose PaymentIntent is really test-mode** is quarantined (`stripe_livemode = false`) and paged
    once.
- **Other automatic refund (Phase 0):** a captured payment that can't be fulfilled, for example because the listing
  already sold to someone else, is refunded once and recorded. If an order already exists for it, it is parked for
  manual review instead (:395–500).
- **Evidence limits.**
  - No expiry refund has been observed end to end in production (REC SPRINT_STATUS:1258).
  - The newest payment of any kind was 2026-09-03, as of D's 04:50Z read today (ratified).
  - Push delivery is not proven.
  - **A refund that fails at Stripe after it was created is not seen.** The webhook handles `charge.refunded` but no
    refund-failure event (stripe-webhook :262–857), so the database would still say refunded.
  - After an earlier partial refund, the buyer's push still says "full refund" although only the balance is
    refunded. This is a minor copy issue, and C has it.

**2. Disabled or not deployed: the refund executors.**
- `ops-refund-execute` is the operator console's "refund" action for a decided dispute. It is **not deployed** (2026-09-22
  apply manifest :172). The console action is also behind the setting `refund_execute_enabled` (115).
- `refund-execute` is the primary-ticketing executor for `kernel.refund` rows. It is **not deployed**; its
  `refund-execute-tick` cron is registered dark, a flag-gated no-op (093–109 execution record :189–190).
- **So a refund decided in the buyer's favour is manual today.**
  - A seller-win or buyer-win decision (`resolve_transfer_dispute`, 065) records `refund_required` for the buyer
    outcomes.
  - A person refunds in the Stripe Dashboard. Webhook v42's `charge.refunded` then records the refund through
    `record_payment_refund` (:702–757).
  - Nothing alerts anyone that a refund is owed: operator alerts are undelivered.

## B. Draft terms (Terms §6; replaces legal.tsx :205–206 and :213–216; the fee sentence and §6a chargebacks stay)

> **6.1 Payment.** Payments are processed by Stripe. At checkout the buyer pays the listing price plus a 10% service
> fee, and the card is charged at that time. The payment is collected into Snatch It's Stripe account. Snatch It does
> not store payment card details.
>
> **6.2 Order release.** After the seller marks the tickets as sent, the order is released to the seller when:
> (a) the buyer confirms receipt in the app; (b) no problem has been reported and Snatch It releases the order,
> automatically after the review period or after a manual review; or (c) a problem the buyer reported is resolved in
> the seller's favour. Depending on an order's value and risk, Snatch It may hold an order until after the event, or
> review it manually, instead of releasing it automatically. While the order is marked as sent and not yet released,
> the buyer can report a problem, and a report stops the order from being released until it is resolved.
>
> **6.3 Payout eligibility.** A released order is paid out only when the seller's connected Stripe account can receive
> transfers, the order is not under an open report, hold or review, and no refund has been made on the payment. After
> a partial refund, Snatch It decides the payout.
>
> **6.4 Payout.** For an eligible order, Snatch It transfers the listing price less a 10% marketplace fee from its
> Stripe account to the seller's connected Stripe account. Transfers are made by a process that runs regularly and
> retries when a transfer cannot be completed; a payout is complete only when the transfer has been made. When the money
> reaches the seller's bank depends on the seller's Stripe payout schedule.
>
> **6.5 Refunds.** (a) If the seller does not mark the tickets as sent within 24 hours of the sale, the order expires
> and the buyer is refunded the full amount paid, including the service fee. (b) If a payment is taken for an order that
> cannot be fulfilled, the buyer is refunded. (c) If the buyer reports a problem and Snatch It resolves it in the
> buyer's favour, Snatch It refunds the buyer in full or in part. Refunds go back to the original payment method; how
> long they take to appear depends on the buyer's bank. (d) Otherwise a sale is final once the order is released, and
> Snatch It does not offer refunds, returns or exchanges.

**In-app summary bullets (legal.tsx :83–84, :87–91):**
> A sale is final once the order is released to the seller, except as set out in Terms §6.

> Payments are processed by Stripe; Snatch It does not store card details. The buyer's payment is collected into Snatch
> It's Stripe account. After the order is released and eligible for payout, the seller receives the listing price less
> a 10% marketplace fee by transfer to their connected Stripe account (Terms §6).

## C. What backs each clause

| Clause | Fact (source at `037092f0`) | Limit |
|---|---|---|
| 6.1 | The PaymentIntent is created on the platform account: no `transfer_data`/`on_behalf_of` (create-payment-intent :1072–1082). Amount = base + round(base × 10%) (`_shared/money.ts:28, :38–45`) | — |
| 6.2 (a) | `confirm_transfer_received`: seller_sent → buyer_confirmed (0550:204) | — |
| 6.2 (b) | Phase 2 release decision at `auto_release_at` (policy 039: LOW releases; MEDIUM holds to a post-event point; HIGH goes to manual review; ≥ $200 never on silence). An operator release sets `auto_released` (0551) | The new payout path has never run in production (`payout_attempts` 0, 149 P3 20:30:20Z) |
| 6.2 (c) | seller-win → payable (#92, 148) | Never exercised in production: `dispute_resolutions` 0 |
| 6.2 report | `buyer_dispute_transfer` accepts only `seller_sent` and sets `disputed` (0550:221–223). Every payout path refuses disputed (confirm-and-release :297, claim `DISPUTED`) | — |
| 6.3 | `PAYOUT_NOT_ELIGIBLE_REASONS` (`_shared/payouts.ts:315–320`): not releasable, disputed, payment not succeeded, held, under review, not live, seller not onboarded, invalid amount, partially refunded (operator decision) | — |
| 6.4 | A separate Stripe Transfer (`_shared/payouts.ts:182`) of `sellerNetCents = base − round(base × 10%)` (`money.ts:51–55, :108`); attempt protocol with retries and reconcile (enforce-transfer-expiry header :49–58) | Timing is not promised: confirm-and-release pays at the buyer's confirmation; the sweep (every 2 minutes) picks up a confirmed order it missed once 15 minutes have passed (:1182) |
| 6.5 (a) | §A.1 above | Not observed in production |
| 6.5 (b) | Phase 0 unfulfillable refund | Not observed in production |
| 6.5 (c) | Manual Dashboard refund, recorded by the webhook | No executor; no alert that a refund is owed |

## D. Reconciliation with the refund-lifecycle findings (A, 2026-09-24 late). The terms stay PENDING.

The refund-failure defect is fixed in the app and in operations (`REFUND_LIFECYCLE_TRACE_AND_FIX_20260924.md`), **not**
in these terms. The terms state only commitments. The changes to §B:

- **6.4 Payout: timing is not promised.** Replace its last two sentences with:
  > Snatch It starts the payout when the order is released: straight away when the buyer confirms receipt, otherwise
  > through a regular automated process. A payout can be delayed while it is held or reviewed, or until the seller's
  > Stripe account can receive transfers. Snatch It does not guarantee when a payout reaches the seller's bank.

  The facts behind it:
  - confirm-and-release pays at confirmation;
  - the sweep runs every 2 minutes and picks up released orders and anything it missed;
  - holds, reviews and the transfers capability gate the payout;
  - Stripe schedules the bank payout.

- **6.5 Refunds: requested versus completed.** Replace "Refunds go back to the original payment method; how long they
  take to appear depends on the buyer's bank." with:
  > Refunds are made to the original payment method, and a refund is complete when the payment processor completes
  > it; how long it takes to appear depends on the buyer's bank. If a refund cannot be completed to the original
  > payment method, Snatch It will contact the buyer to return the money another way.

  The last sentence is an operational commitment. It holds only if the owner adopts O-R3 (who handles `refund_failed`
  cases). If not, drop it.

- **6.5(d): mandatory rights.** Change it to:
  > Except where the law requires otherwise, a sale is final once the order is released, and Snatch It does not offer
  > refunds, returns or exchanges.

- **6.6 (new):**
  > Nothing in these terms limits any right you have under applicable law, including consumer-protection law and your
  > rights with your card issuer.

  Product policy cannot exclude these rights, and the §6a chargeback clause already assumes the card-issuer right
  exists.

- **Not covered, for the owner and counsel:** what happens to an order when the **event is cancelled or postponed**.
  The terms are silent. Some jurisdictions regulate ticket resale in this situation. A has not checked any law and
  claims none.

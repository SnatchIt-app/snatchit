# Refund resolution plan for pending marketplace orders (A, 2026-09-19): planning only

**Owner's brief (directly to A):** one bounded plan covering:
- full refunds;
- partial refunds where fulfilment continues;
- partial refunds where the order is cancelled and a remainder is owed;
- unknown refund amounts;
- seller payout and expiry behaviour for each.

It must separate what is verified in deployed code from repository source, and must not assume the payout is "payment minus refund" without reconciling fees and existing transfers.

**Not established by this plan:** "any refund cancels the order", and any 24-hour support-refund promise. **No live alerts and no payment changes.** Production applies remain on hold.

**Strength labels:**
- **DEPLOYED:** production code byte-verified 2026-09-19 (`enforce-transfer-expiry` v38 plus its five `_shared` files, identical to `origin/main`).
- **PROD-DB:** production catalog read (function md5s) or production aggregate read, owner-authorised.
- **REPLAY:** the local production-shaped replay; 12 of 13 transfer and payout function md5s equal production's.
- **REPO:** repository source only (for example `main`'s `stripe-webhook`; deployed v41 is **not** byte-read).
- **DOCS:** Stripe documentation read 2026-09-19.

## 1. The Stripe configuration check (owner-authorised, read-only, 2026-09-19)

| Question | Answer | Strength |
|---|---|---|
| Does production's webhook receive `charge.refunded`? | **Yes, historically.** Our event ledger (`public.stripe_webhook_events`, written by `stripe-webhook`) holds **3** `charge.refunded` events, 2026-07-04 → 2026-08-04, all processed, 0 failed, 0 with an error. | PROD-DB aggregate (types, counts, dates only; no payloads, no error text) |
| Which endpoint handles it? | Our Supabase edge function **`stripe-webhook`**, the ledger's only writer. | PROD-DB + REPO |
| Stripe-side endpoint configuration (endpoint ID, URL, enabled/disabled status, subscribed event list, recent delivery failures) | **Not read.** The Stripe CLI on this machine is logged into the **sandbox** account only (no live context), and the built-in browser stopped at the Stripe login page. A did not authenticate. | not established |
| Current delivery health | The ledger's **newest event of any type is 2026-08-05**; 31 events in total since 2026-06-05. `stripe-webhook` was redeployed 2026-08-06 01:05Z (v41). **0 requests reached `stripe-webhook` in the last 24 hours** (edge logs; no successes, no failures). This is consistent with "no Stripe activity since 08-05" **or** with deliveries stopping; A cannot tell which without the Stripe side. | PROD-DB + logs |

**Owner check that closes the gap (Stripe Dashboard, live mode):** Developers → Webhooks, then the endpoint whose URL ends `/functions/v1/stripe-webhook`. Record four things:
- its status (Enabled or Disabled);
- the "Listening to" events, including whether `charge.refunded` and `transfer.reversed` are there;
- the API version;
- the recent-deliveries panel: any failed deliveries since 2026-08-05.

## 2. Money model: what the payout actually is (so nobody assumes "payment − refund")

- **Charge type: separate charges and transfers.** The buyer pays the platform. The seller is paid later by a Stripe **Transfer** funded with `source_transaction` = that charge (DEPLOYED `_shared/payouts.ts`). The PaymentIntent's own Connect parameters live in `create-payment-intent` (deployed v47, 2026-09-02, **not** byte-read).
- **Amounts** (`public.payments`, PROD-DB columns via REPLAY):
  - the buyer is charged `total` = `amount` (base) + `buyer_fee`;
  - the **seller's net = `amount − seller_fee`** (DEPLOYED, the "10/10 fee model");
  - the platform keeps `buyer_fee + seller_fee`, less Stripe's processing fee.
- **Refunds cost the platform, not the seller, automatically.** Stripe "debits your platform for refunds to … separate charge and transfer payments", and **"Stripe's processing fees from the original transaction aren't returned"** (DOCS).
  - Recovering money already sent to a seller needs a **transfer reversal**. Stripe: "Reverse the transfers associated with these charge types" (DOCS).
  - Nothing in our code starts a reversal. `stripe-webhook` only **records** one (`transfer.reversed` → `mark_transfer_reversed`, REPO/REPLAY). The ledger has never received a `transfer.reversed` event.
- **Payout guards, both payout paths:**
  - (1) `payments.status` must be `succeeded`. DEPLOYED in `enforce-transfer-expiry`; REPO for `confirm-and-release`, whose deployed v36 (2026-09-02) is not byte-read.
  - (2) Stripe must show the PaymentIntent succeeded and live, the charge not fully refunded, **and seller net ≤ charge amount − amount refunded** (the `source_transaction` ceiling; DEPLOYED).
- **The DB cannot tell a partial refund from a full one.** The webhook sets `status='refunded'` for **any** `charge.refunded`, which Stripe sends "including partial refunds" (DOCS). It records no amount (REPO). Production has no `amount_refunded_cents` column: 142 is not applied, and nothing writes it anyway. **Every production `refunded` row is "amount unknown"** from the DB's point of view. Stripe (Dashboard: the payment's amount and amount refunded) is the only source of the real amount.

## 3. The four cases: behaviour today and a resolution that needs no rule change

Common to all four: once a refund is recorded, the order sits `pending` until the seller marks it sent or the **24-hour expiry** fires. Expiry (DEPLOYED):
- runs every 2 minutes;
- marks the transfer `expired` whatever the payment state;
- **skips the refund if `status='refunded'` or `stripe_refund_id` is set, and sends no push on that path**;
- no trigger notifies anyone on `expired` (REPLAY);
- the listing stays `sold`.

A sent order is claimed `auto_released` after 72 hours. Its payout is then skipped while the payment is not `succeeded`, and retried and skipped every 2 minutes by Phase 2b (DEPLOYED).

| Case (classified in the Stripe Dashboard) | Seller payout today | Expiry today | Resolution without a rule change | What would need an owner decision |
|---|---|---|---|---|
| **A. Full refund** (refunded = charge amount) | Correctly blocked: DB status plus `charge.refunded` = true. If the seller already **marked it sent**, the payout loop retries for ever (noise, no money). If the seller was **already paid** before the refund, the platform has paid twice (the refund plus the Transfer) until someone reverses the Transfer. | Correct outcome, **silent**: expires, refund skipped, nobody notified. | Support confirms "fully refunded" in Stripe and tells the seller not to transfer tickets; the order closes at expiry. If already paid out: decide on a Transfer reversal, then `transfer.reversed` records it. | Whether to notify both parties automatically on this silent closure. Whether and when to reverse a completed payout. |
| **B. Partial refund, fulfilment continues** (for example a goodwill or price adjustment) | **No automated path pays the seller** (F-PAYOUT-PARTIAL-1): the DB status is `refunded`. Even with the status fixed, Stripe funds at most charge − refunded. So a partial refund larger than `buyer_fee + seller_fee` leaves the charge unable to fund the full seller net. | If the seller does not mark it sent in time: expires, and **the remainder is not refunded** (skip), so the buyer has paid for tickets they never receive. | **None in-system.** Support can only avoid creating this state: until a policy exists, prefer "no partial refund on a pending order" or a full refund plus re-purchase. That is guidance, not a rule. | (1) Who bears a partial refund: the platform's fees, the seller's net, or a split (terms and consent). (2) A payout path that accepts a recorded partial refund, pays the policy net within the `source_transaction` ceiling, and handles the rest. That is a **payment-rule and server change**. |
| **C. Partial refund, order cancelled, remainder owed** | None, which is correct. The seller must not transfer tickets. | Expires; **the remainder is never refunded by automation** (DEPLOYED skip + REPO webhook + DOCS; `charge.refunded` delivery is evidenced through 08-04). If the webhook had not marked the row, expiry's refund with no amount would refund what remains, because Stripe caps any refund at "the remaining, unrefunded amount" (DOCS). | Support refunds the **remainder** in the Stripe Dashboard. The webhook does nothing (already `refunded`), and that is acceptable. Support confirms the charge now shows fully refunded, then closes the case. No 24-hour promise: the remainder can be refunded before or after expiry. | Whether expiry should refund any remainder itself when a row is `refunded` but the charge isn't fully refunded (the gate candidate's `fullyRefunded` logic is related, not deployed). That is a rule change. |
| **D. Unknown amount** (the DB view of every `refunded` row today) | As in A/B/C, depending on the real amount; the DB cannot decide. | As above. | **Classify first:** support reads the payment in Stripe (amount, amount refunded, any Transfer) and records A, B or C on the case, then follows that row. Until it is classified, the seller sees the owner's "contact support" wording. | Recording the refunded amount at the source (142's column plus a webhook change), so the system can classify without a human. That is a server change. |

**Existing transfers must be checked first, in every case.** If `transfers.stripe_transfer_id` / `payout_released_at` is set, the seller has already been paid. Then any refund is a platform loss until a reversal, and the resolution follows A's "already paid out" branch. It is not "net minus refund".

## 4. Detection and the support action (coordinated with D; a proposal only, no live alerts)

The states the DB can see (DB-only, no Stripe call):

| State | Meaning | Support action |
|---|---|---|
| **R1** pending transfer + payment `refunded` | Refund recorded, amount unknown, fulfilment undecided | Classify A/B/C in Stripe; tell the seller; for C, refund the remainder |
| **R2** expired transfer + payment `refunded` + `stripe_refund_id` not set by expiry (refunded outside expiry) | Possibly C with a remainder owed, or A that closed silently | Check Stripe for a remainder; refund it if owed; notify the parties |
| **R3** `seller_sent` / `auto_released` transfer + payment not `succeeded` + no payout | F-PAYOUT-PARTIAL-1 (B), or A where the seller sent anyway | Escalate: the payout needs an owner-policy decision; there is no tool today |
| **R4** payout made + payment later `refunded` | The platform has paid out and refunded | Decide on a Transfer reversal (owner/finance) |

**D is asked to propose, locally:**
- a detector (an ops case type such as `refund_resolution`, one case per transfer, with the state code and the resolution steps above);
- the classification recorded as a case note or field;
- closure only by a support action. Not auto-resolved, which avoids the 7-day auto-resolve gap D found for `job_failure`.

Other rules for D's proposal:
- **No due time that reads as a customer promise.**
- No live alert, no schedule, no apply.
- A reviews the proposal.

## 5. Order of work (each step owner-authorised separately)
1. The owner's Stripe Dashboard check (§1). This establishes whether deliveries still arrive.
2. The owner's policy decisions: who bears a partial refund; whether partial refunds on pending orders are allowed at all; notifications on silent closures; reversal policy.
3. D's detector, designed and built locally, reviewed by A, then CI. Live only after a separate authorisation.
4. Only after 2: a server change for B and C. Record the refund amount (142's column plus the webhook), then change payout and expiry to follow the recorded amount. It is reviewed and rehearsed like any payment change.
5. C's seller-screen restriction ("Mark as sent" inactive) is safe only once R1 is detected and has a support owner. Until then, C's wording-only interim stands.

## 6. Evidence limits
- The deployed `stripe-webhook` (v41), `confirm-and-release` (v36) and `create-payment-intent` (v47) are **not** byte-read. Their behaviour here is from repository source.
- The Stripe-side endpoint configuration and delivery log are not read (§1).
- No customer rows were read. No count of affected production orders exists: R1–R4 counts would be customer-data aggregates, and need their own authorisation.

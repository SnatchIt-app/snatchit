# Cancellations that happen BEFORE `payment_intent.canceled` is subscribed — how each is reconciled

The new webhook branch for `payment_intent.canceled` (stripe-webhook, shared with `payment_intent.payment_failed`) is
dead until the owner adds the event to the live endpoint (`08_STRIPE_WEBHOOK_SUBSCRIPTION.md`, release step P2-d, after
the edge deploy). Every cancellation is nevertheless reconciled by a path that does not depend on that event:

| Cancellation source | What cancels the PaymentIntent | Local reconciliation (no webhook needed) | Residual |
|---|---|---|---|
| Our own retire paths: a competing buyer settles, or the buyer re-enters checkout | `create-payment-intent` `retirePendingIntents` and the sweep's `retireOtherPendingIntents` POST `/payment_intents/{id}/cancel` and then set the row `failed` (`create-payment-intent/index.ts:254,273`, `enforce-transfer-expiry/index.ts:247-252`) | immediate, in the same request | none — the later webhook event (once subscribed) finds `failed` and is a no-op (`settle_verified_payment` canceled branch, 110000:286) |
| Buyer abandons PaymentSheet (no capture) | nobody — the intent stays `requires_payment_method` | the 10-minute reservation lapses server-side (P1); the row stays `pending`; the sweep's `pending_stale` work item (payments 15 min – 2 h old, 110000:388-401) re-fetches the intent and settles it with its real status; a non-terminal status is a no-op | the intent lingers "incomplete" at Stripe (harmless, never captured); a later checkout by the same buyer retires it |
| Dashboard / API cancel by an operator (or any third party) | Stripe | `pending_stale` (15 min – 2 h): the sweep re-fetches the intent, sees `canceled`, calls `settle_verified_payment(…, 'canceled')` → row `failed`, reservation released, listing re-openable (`enforce-transfer-expiry/index.ts:305`) | cancellations discovered **more than 2 h** after the row was created are outside the automatic window (R2 MINOR-6) — covered by the one-shot backfill below |
| Cancellations during the deploy window (new edges live, event not yet subscribed) | any of the above | same as the row above | same |

## One-shot backfill at subscription time (owner-run; prepared, not executed)

`scripts/release/reconcile_pending_intents.sh` lists every `payments` row still `pending` older than 2 hours, asks Stripe
(CLI, owner login) for each intent's status, and PRINTS the `settle_verified_payment(...)` statements for the ones Stripe
reports `canceled` (and `succeeded`, which would mean a lost success event — those go through the same contract with
`'succeeded'` and are the important ones). Nothing executes without `--apply`, and `--apply` refuses a production
database name unless `RECONCILE_ALLOW_PROD=1` is set by the owner. Run it once right after P2-d, then again 24 h later;
from then on the subscribed event and the sweep cover everything inside the window and the daily run of the script
covers anything older.

## Why this is enough
- Money never depends on the event: a canceled intent has no charge; the only local facts are the `pending` row and a
  possibly stale reservation, both bounded (reservation 10 min; row settled by the sweep or the backfill).
- A missed `succeeded` is the dangerous case, and it is covered by `paid_unsettled` / `pending_stale` plus the buyer's
  `confirm-payment` call — unchanged by this document.

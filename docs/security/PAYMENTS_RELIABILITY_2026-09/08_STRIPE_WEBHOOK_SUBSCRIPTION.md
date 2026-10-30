# Stripe webhook endpoint — exact subscription change (owner action; NOT performed by this program)

**Why.** Package 2 adds a `payment_intent.canceled` branch to `stripe-webhook`
(releases the buy-now hold and marks a pending/processing payment `failed`
through `settle_verified_payment`). Stripe only delivers events the endpoint is
subscribed to; today the production endpoint is subscribed to the ten types the
deployed webhook handles, so the new branch is dead until this change is made.
No other event type is added or removed by the release.

**When.** After the edge deploy step P3-d (the new webhook must be live before
the event is enabled; an unsubscribed event is harmless, an unhandled one is a
400 loop). Recorded as release step P2-d in `04_RELEASE_PLAN.md`.

**Where.** Stripe Dashboard → Developers → Webhooks → the LIVE endpoint whose
URL is the Supabase `stripe-webhook` function
(`https://hqycwntpfoztoinemqns.functions.supabase.co/stripe-webhook`).
Do NOT touch the test-mode endpoint; do NOT create a second live endpoint (the
event lease is per event id, but two endpoints double every delivery).

**Change.** "Select events" → add exactly one:

| Event | Action |
|---|---|
| `payment_intent.canceled` | **ADD** |

The full subscribed set after the change (11), which must equal the handler's
branch list in `supabase/functions/stripe-webhook/index.ts`:

```
account.updated
charge.dispute.closed
charge.dispute.created
charge.refunded
payment_intent.canceled        ← new
payment_intent.payment_failed
payment_intent.succeeded
payout.failed
payout.paid
transfer.created
transfer.reversed
```

**Stripe CLI equivalent** (owner-run, live key; `we_…` is the endpoint id shown
in the Dashboard):

```bash
stripe webhook_endpoints update we_XXXXXXXXXXXX \
  --enabled-events account.updated \
  --enabled-events charge.dispute.closed \
  --enabled-events charge.dispute.created \
  --enabled-events charge.refunded \
  --enabled-events payment_intent.canceled \
  --enabled-events payment_intent.payment_failed \
  --enabled-events payment_intent.succeeded \
  --enabled-events payout.failed \
  --enabled-events payout.paid \
  --enabled-events transfer.created \
  --enabled-events transfer.reversed
```

(`update` REPLACES the list — pass all eleven.)

**Verification.** `stripe webhook_endpoints retrieve we_XXXXXXXXXXXX` shows the
eleven events; then in the Dashboard, "Send test event" is NOT available for
live endpoints — instead, watch the next real cancellation: a buy-now checkout
abandoned past its 10-minute window produces `payment_intent.canceled` from
the sweep's retire path, and `stripe_webhook_events` gains a row with that
type and `processed_at` set.

**Rollback.** Remove the event from the list (same screen / same CLI call
without it). The old webhook ignores unknown types with a 200, so leaving it
subscribed during an edge rollback is also safe.

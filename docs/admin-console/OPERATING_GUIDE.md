# Founder operating guide

The console answers three questions: **what needs attention, who owns it, and
what can we safely do.** Everything you see is read live from the database with
your own session; everything you change is recorded as an *action* with your
identity, a reason, and an authoritative outcome.

## Signing in

1. Go to the console URL, sign in with your own email and password (no shared
   login).
2. First time: enrol an authenticator app (TOTP). Every session must pass MFA
   before any page loads. If you land on **"Your account is not an operator"**,
   your `admin_users` row is missing — see `FOUNDER_BOOTSTRAP.md`.
3. The header badge shows the environment (`production` is red). The footer
   shows the deployed commit.

## Today (`/`)

The attention queue: every open **case**, ordered by priority then deadline.
Cases are opened automatically every 5 minutes by the detectors and closed
automatically when the condition clears. Filters: *Assigned to me*, *Unassigned*,
*All*. Metric tiles carry their definition on hover; the freshness line says
when the snapshot and the last detector run completed. If "last detector
success" is older than 15 minutes, open **System**.

| Case type | Means | First move |
|---|---|---|
| Paid but not settled | A succeeded payment whose listing is not `sold` or has no transfer row (audit F02). | Open the order; compare payment ↔ listing ↔ transfer; if the buyer paid and inventory is still available, this is a settlement gap — escalate to engineering with the payment id. Do not mark anything sold by hand. |
| Transfer due soon / overdue | Seller has not sent tickets; deadline within 6 h / passed. | Contact the seller; the expiry worker refunds after the 24 h deadline automatically — verify the refund appears. |
| Release stuck | Transfer marked released locally but no Stripe transfer id after 30 min, or eligible for release and not picked up. | Check System → cron `enforce-transfer-expiry` health; if the worker is healthy and the row is still stuck after the next tick, escalate. |
| Refund pending | Dispute resolved for the buyer, or expired order, but payment still `succeeded`. | Execute the refund (see Money actions) or follow the Stripe-Dashboard SOP if refund execution is disabled. |
| Dispute open | In-app buyer dispute awaiting a decision (72 h SLA). | Review evidence in the order page, then **Resolve dispute** with an outcome. |
| Evidence due | Stripe chargeback with an evidence deadline. | Submit evidence in the Stripe Dashboard before the deadline; the case closes when Stripe reports a terminal status. |
| Payout review | Risk classifier asked for a manual decision before releasing seller funds. | Review; **Release payout** requires the other founder's approval. |
| Report review | A user reported a listing or user. | Triage: *Reviewing* → *Actioned* / *Dismissed*, with a reason. |
| Webhook stuck / Job failure / Notification failure | Background processing problems. | Read the error on System; use *Retry* only for console jobs; Stripe webhooks are re-sent from the Stripe Dashboard, never replayed from here. |
| Reconciliation mismatch | Money facts disagree (e.g. refunded payment with released payout; total ≠ amount + fee). | Investigate before any money action; escalate. |

## Finding anything (`/search`, or press `/`)

Paste an order/payment id, transfer id, listing id, user id, `pi_…`, `tr_…`,
`re_…`, `dp_…`, an exact email or phone, or an event name.

## Investigating an order (`/orders/:paymentId`)

One page: buyer and seller (masked contact data), listing, amounts and fees as
recorded at the time, payment state, delivery state, evidence links (signed,
expiring), disputes, refunds, payout decisions, **seller funds state**, open
cases, prior actions, and the **timeline** merging every internal record in
chronological order. Terminology is deliberate:

- *Captured payment* — Stripe charged the buyer (`payments.status = succeeded`).
- *Released to connected account* — a Stripe Transfer to the seller exists
  (`stripe_transfer_id`). This is **not** a bank payout; bank payouts are not
  tracked in this system.
- *Refunded* — `payments.status = refunded`, set by the Stripe webhook after the
  provider refund succeeded.

## Owning a problem

On any case: **Assign** (to yourself or the other founder), set **Priority**,
**Due**, **Status** (`open → in progress → waiting → resolved/dismissed`), and
add **Notes**. Notes are append-only. If the other founder changed the case
while you had it open, your change is rejected with *"this case changed since
you loaded it"* — reload and redo; nothing is silently overwritten.

## Taking a safe action

Every button is a form with a required **reason**. The server checks the
current state before acting; if the record moved since you loaded the page you
get a *stale state* rejection, not a wrong action. Double-clicks and retries
reuse the same operation id and cannot execute twice. Results shown are the
authoritative outcome, never optimistic.

| Action | Who | Approval | What actually happens |
|---|---|---|---|
| Resolve dispute (seller win / buyer win / partial) | founder, risk | none | `resolve_transfer_dispute` records the decision. Seller win un-freezes the payout path. Buyer win/partial **does not move money** — a *Refund pending* case opens. |
| Release held payout | founder | **second founder** | `admin_release_held_payout` marks the transfer released; the payout worker moves funds to the connected account on its next run. |
| Execute refund | founder | **second founder** | **Full refunds only** (the local money model records refund status, not amounts, so a partial refund would be reported as a full one; partial requests are rejected by the server). `ops-refund-execute` claims the action (re-checking the enabled flag, the console pause and the approval), reconciles any earlier attempt at Stripe before sending, then records the refund object's real state: `succeeded at provider` (awaiting the local webhook), `accepted, pending / requires action` (not success), `failed`, or `unknown` (needs reconciliation). **Disabled** until the function is deployed — the UI says so. |
| Relist listing | founder | none | `admin_relist_listing` — only admin-owned, never-transacted cancelled inventory. |
| Resolve report | any operator | none | Sets the report status. |
| Block listing creation / unblock | any operator / founder, risk | none | Sets `seller_risk_scores.is_listing_blocked`; enforced **in the database** by a BEFORE INSERT guard on listings (migration 119) — a direct API insert by the blocked seller fails with `listing_blocked` — and mirrored by `can_create_listing()` for a friendly message in the apps. Existing listings, sign-in and purchases are untouched. Account suspension does not exist and is not offered. |
| Retry console job | founder | none | Re-runs a detector immediately. |

### Two-founder approval

Requesting an approval-gated action parks it as *awaiting approval*. The other
founder sees it under System → Approvals, reviews the exact terms, and approves
or denies with a reason. Approval is bound to those terms; if anything about the
request changes, the approval is voided. You cannot approve your own request.
Approvals expire after 72 hours.

## Evidence

"Open evidence" buttons resolve the file from the record itself (never from
the page), require your operator role and MFA at the database, record an
`evidence.viewed` audit row, and open a link that expires in five minutes.
Buyers and sellers keep their own access; nobody else can read proof-docs.

## Pausing the console

System → Settings → `actions_enabled = false` stops every mutation (yours
included) while search, queues and detail pages keep working. Use it during an
incident before anything else; re-enable when done. `detectors_enabled = false`
pauses the 5-minute detectors. Both are audited.

## Escalation

Anything marked *unknown* (money may have moved at the provider but the local record did
not update), any refund left *processing* for more than 30 minutes (a case opens automatically), any *Paid but not settled* older than an hour, and any
*Reconciliation mismatch* go to engineering with the payment id and the action
id from the page. Do not "fix" money state by hand in the SQL editor.

## What the console will not do (by design)

Impersonate users · replay Stripe webhooks · edit prices or fees on committed
listings · suspend accounts · grant admin access · send customer messages.

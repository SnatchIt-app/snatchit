# Isolated development: 126, L3, L4, F10 — status and proposals

Release integration, 2026-09-14. **Nothing here is applied, deployed or scheduled.** Items 2–4 are proposals
returned for approval before any behaviour changes.

---

## 1. Migration 126 / pgTAP 193 — refund exactness: NOT BLOCKED, contract resolved

**The gate table's cross-reference was wrong, and that is the whole of why this looked blocked.** §8 cites
"§14 acceptance cases A1–A8"; §14 is the D5 3-D Secure section and contains no such cases. The eight cases do
exist, in **`docs/release/CONVERGENCE_135_REPORT.md:541-548`**. Corrected in §8.

**Why the work is now possible at all.** Migration `120` deliberately refuses to state a refunded amount
(`refunded_cents = null`, `refunded_certainty = 'uncertain'`, an upper bound of `sum(payments.total)`), because
when it was written nothing local recorded the amount — a $10 partial refund on a $100 payment only flipped the
status, so summing `total` overstated it tenfold. Since then `20260906120000` added
**`public.payment_refunds`** (append-only), **`payments.amount_refunded_cents`** and
**`public.record_payment_refund(text,text,text,integer,text)`**. The exact amount is now recorded, so ops can
stop saying "unknown".

**Every case is implementable — checked, not assumed:**

| Case | Requirement | How it is satisfied |
|---|---|---|
| A1 | partial refund → `refunded_cents = 1000`, `certainty 'known'`, `refunded_partial_count = 1` | sum `payment_refunds.amount_cents` |
| A2 | full refund → `10000`, `refunded_full_count = 1` | same sum; full/partial by comparison with `payments.total` |
| A3 | two partials on one payment → `2500`, payment counted **once** | sum over the ledger, `count(distinct payment_id)` |
| A4 | refund outside the window excluded from `live_24h`, included all-time | window on `payment_refunds.created_at`, not the payment's |
| A5 | no refunds → `0` with `certainty 'known'` | an empty sum is a known zero, not an unknown |
| A6 | legacy stored summaries stay `uncertain` + `legacy_normalized`, never re-labelled | `normalize_summary_body` must not upgrade old bodies |
| A7 | `payment_refunds` absent (pre-RC database) → `120`'s uncertain shape, no error | guard with `to_regclass` |
| A8 | chargeback counted **exactly once**, not double-counted | the ledger carries `stripe_refund_id` **and** `stripe_dispute_id` with `source`, and `payment_refunds_payment_dispute_uniq` already dedupes disputes |

**Status: specified, decidable, and scheduled — not written.** It touches four `ops` functions
(`build_daily_summary`, `money_overview`, the `money.refunded` metric snapshot, `latest_summary` /
`normalize_summary_body`), so it earns its own reviewed pass rather than riding along with the items below.

**It does not block `127`/`128`.** 126 changes only `ops` reporting; 127 changes reservation release; 128
changes push-token registration. No shared object, no ordering dependency between them beyond their numbers.

---

## 2. L4 — scheduled cancellation of a PaymentIntent that outlived its hold (DESIGN, not built)

**Problem.** Nothing cancels a PaymentIntent when its Buy Now hold lapses, so an abandoned checkout can be
confirmed later against a listing somebody else now holds. `cleanup_expired_reservations` cannot do it: SQL
cannot call Stripe.

**Shape.** A SQL *selector* (service_role only) plus an edge function on a schedule. The selector writes
nothing — it only answers "which intents are safe to cancel". Proposed predicate:

```
p.status = 'pending'
AND p.stripe_payment_intent_id IS NOT NULL
AND p.mode = 'buy_now'
AND p.created_at < now() - interval '15 minutes'        -- 10-minute TTL + 5-minute grace
AND NOT EXISTS (succeeded payment on p.listing_id)       -- never touch a paid listing
AND EXISTS (listing l WHERE l.id = p.listing_id
            AND (l.status <> 'reserved'
                 OR l.reserved_by IS DISTINCT FROM p.buyer_id
                 OR l.reserved_until <= now()))          -- this buyer's hold is gone
```

**The three races, and how each is answered:**

| Race | Answer |
|---|---|
| Cancellation racing **authentication** (buyer mid-3DS when the sweep fires) | The 5-minute grace past an already-lapsed 10-minute hold means we only act long after the window closed. The edge must also re-read the row immediately before calling Stripe, and treat Stripe's refusal to cancel a succeeded/processing intent as **success of the sweep** — nothing to do — never as an error to retry. |
| Racing a **successful payment** | Stripe refuses the cancel; we must then **not** write the local row at all. Settlement stays the webhook's job. The `NOT EXISTS (succeeded…)` guard also removes most of these before selection. |
| **Replacement holds** (a new buyer now holds the listing) | Cancelling the *old* buyer's intent is exactly the point. The sweep therefore **never writes `listings`** — no release, no status change. It touches only Stripe and, via the webhook, the old payment row. |

**Idempotency.** Cancelling an already-cancelled intent is a Stripe no-op, and the selector excludes anything
not `pending`, so a replay selects nothing. No local write means no double-write.

**Locally testable now** (pgTAP): the selector returns an abandoned intent; excludes a live hold, a listing with
a succeeded payment, a row inside the grace window, a non-`pending` row, and `auction` mode; and writes nothing.
**Not locally testable:** the Stripe call, the schedule, and the webhook interaction — those need the sandbox
and an authorized schedule, which this does not have.

**Numbering:** a migration number is taken from the registry when the selector is written, not reserved now.

---

## 3. L3 — bounded retry/hold policy (PROPOSAL, no live change)

**Today.** The webhook releases the hold on `payment_intent.payment_failed` while Stripe still permits a
same-sheet retry, so a retry runs with no hold; if another buyer takes the listing meanwhile, the settlement
ends `unfulfillable` and the reconciliation sweep refunds it.

**Proposal — a bounded grace, never an extension.** On `payment_failed` (not `canceled`), defer the release by
**N seconds, capped by the hold's own remaining TTL**:

> release at `min(payment.failed_at + N, listings.reserved_until)`

The cap is the guarantee the owner asked for: **the hold can never outlive `reserved_until`**, so this is a
subset of the existing window, not an arbitrary extension. Proposed **N = 120 s** — Stripe's same-sheet retry
happens within seconds, so 120 s covers it without materially changing inventory behaviour.

**Implementation shape (declarative, no timers):** `release_reservation_for_payment` gains a "not before"
condition, so a too-early release is refused and simply happens on the next sweep instead.

| Consequence | Effect |
|---|---|
| Inventory | a failed attempt holds the listing up to 2 extra minutes, and less whenever the remaining TTL is shorter |
| Payments | fewer charge-then-refund cases, because a successful retry happens while the buyer still holds |
| Risk if N is too large | inventory lockup on every genuine failure — the reason it is capped and small |

**For the owner:** the value of N, and whether it applies to `payment_intent.canceled` as well
(**recommendation: no** — an explicit cancel is unambiguous abandonment). Not implemented.

---

## 4. F10 — minimum bid increment (CONCRETE RULE, for approval before any auction-semantics change)

**What is displayed today.** `APP_CONFIG.MIN_BID_INCREMENT = 5` (dollars, `src/config/app.ts:15`), used to
display the next bid (`ListingDetailScreen.tsx:1037`, `currentHighest + MIN_BID_INCREMENT`) and to validate
entry (`PlaceBidScreen.tsx:44`).

**What the server enforces today.** `047` enforces only `NEW.amount > v_current_bid`. The increment is a
client convention, so anything bypassing the client can bid below it.

**Decimal precision — there is none, and that matters.** `bids.amount` and `listings.current_bid` are both
**`integer`** (whole dollars). So the smallest accepted-but-below-increment bid is **+$1**, not +$0.01, and the
proposed rule needs no rounding, no numeric scale and no float comparison.

**Concurrent bids are already safe.** `047` takes `FOR UPDATE` on the listing row *before* reading
`current_bid`, so two simultaneous bids serialise and the second sees the first's committed value. Adding an
increment does not weaken this; the guarantee already exists.

**The rule, two options — the owner picks one:**

| | Rule | Consequence |
|---|---|---|
| **A — faithful to the client** | `NEW.amount >= v_current_bid + 5` on **every** bid | Exactly the rule the app already displays. **But** `current_bid` is initialised to `starting_bid`, so the advertised starting price becomes unbiddable and the real entry price is `starting_bid + 5`. |
| **B — preserve the advertised entry** | `+ 5` only once a real bid exists; the first bid keeps `> starting_bid` | The advertised starting price stays biddable, but the server is then *not* the same rule the client shows for the first bid. |

**Recommendation: A**, because the instruction was to enforce the same rule the client displays and the client
already shows `starting_bid + 5` for the first bid — but the entry-price consequence is real and is the owner's
to accept. **No change is made until this is approved.** Implementation would be a new numbered migration
replacing `047`'s trigger body, with a rollback returning to strictly-greater, and pgTAP covering both bounds,
the first-bid case, and a concurrent pair.

# `ODR-16` — Reframed Owner Brief (supersedes the A/B/C framing)

**2026-08-28.** Precondition #1 is now met: `ODR16_TRANSITIVE_DELETION_INVENTORY.md` exists and
enumerates **57** blocking columns, not 36. This brief re-tests the recommended product model
against that inventory.

> ## VERDICT: `ODR-16` IS **NOT READY FOR OWNER RULING**.
>
> Not because the model is wrong — **model B survives contact with the inventory** — but because
> three of the four preconditions the previous brief set are still unmet, and the inventory has
> added a fourth that is more serious than any of them.

## The split stands, and the inventory sharpens it

| limb | what it is | status |
|---|---|---|
| **`16a`** identity retention | pre-decided by the data model + `C95`/`C96` | ratify, do not re-vote |
| **`16b`** live custody at the deletion request | **the only genuine owner policy choice** | the subject of this brief |
| **`16c`** money obligations | **not asked by any option** | still not asked |
| **`16d`** non-custody identity roles | **not asked by any option** | **50 of 57 columns** |

The inventory moves `16d` from a footnote to the majority of the problem. `16b` decides the
behaviour of **7 custody columns**. The other **50** — role grants, audit actors, ops grants,
money actors, marketplace parties, the bidder and the dispute resolver in the live database —
are governed by nothing.

## MODEL B, tested against all 57

**The model:** a deletion request enters **PENDING** while blocking custody/obligations exist,
then completes automatically when safe.

### B1 — The block predicate

Derived from the inventory's disposition column, not invented:

```
BLOCK while ANY of:
  live custody          kernel.tickets.current_owner_id                      (#13)
                        kernel.wallet_pass.holder_identity_id                (#19)
  open marketplace      market.market_sale.{buyer,seller}_id                 (#41,#42)
                        market.p2p_transfer.{from,to}_identity               (#43,#44)
  unsettled money       kernel.payout.payee_identity_id                      (#20)
                        venue.order.buyer_id  (refund path)                  (#27)
  live db (today)       public.listings.reserved_by  — in-flight buy-now     (A#4)
                        public.transfers in a non-terminal state
```

**11 BLOCK columns of 57.** Everything else is `CLEANED` (13 + the live half), `TOMBSTONED`
(9 + 2), or **`require OWNER DECISION` (11 + 2)** — and that last class is the reason this is
not ready.

### B2 — What resolves the pending state

Event, scan, or settlement — never the user. Ticket consumed/expired · pass superseded or
expired · marketplace sale settled or cancelled · payout paid or reversed · refund window
closed · transfer terminal.

### B3 — Queue or table

**Three columns on `kernel.identity_ext`** — `deletion_state`, `deletion_requested_at`,
`deletion_block_reason` — plus a partial index and one sweep on the existing 2-minute heartbeat.
**Not a new table.** A queue table must choose `RESTRICT` (a third cliff blocking the deletion
it schedules) or `CASCADE` (deleting the record of the request in the same statement that
completes it). The previous brief established this and the inventory does not disturb it.

**It is also the only object in the design that can detect a half-completed deletion** — worth
building whatever is ruled.

### B4 — Retry, notification, cancellation, access

Retry: the sweep is idempotent and re-evaluates the predicate from scratch. Notification: the
user is told the request is pending and why, and told when it completes — **which is a mandatory
notification type and therefore now depends on `ODR-3`'s reduced Gate-P build (`OR-5`)**.
Cancellation: the user may withdraw while pending. Access: **the account must remain usable
while pending** — a user blocked by a ticket four months out must not be locked out of that
ticket.

### B5 — Partial success

The live database already half-completes irreversibly, which is why PR #28 exists. The pending
state's detector is what makes the half-state visible. **This is the strongest argument for
building B3 regardless of the ruling.**

### B6 — **Can the final `auth.users` DELETE actually succeed?**

**NO — and this is the finding that stops the ruling.**

The previous brief established that the `RESTRICT` wall never lifts, because
`ticket_ownership_log`'s identity columns are `RESTRICT` and append-only and no engine moves the
head off a terminal atom. **The inventory adds a wall that is earlier and worse:**

```
auth.users --CASCADE--> kernel.identity_contact_pref_event --raise_append_only()--> ABORT (077)
auth.users --CASCADE--> kernel.org_contact_consent_event   --raise_append_only()--> ABORT (082)
```

**From `077`, the DELETE aborts inside a referential cascade, before any `RESTRICT` is reached,
for a reason unrelated to custody.** So under model B the pending state is entered, the predicate
eventually clears — and the terminal step still fails. **B's refusal never lifts. C's hand-off
never runs.** Both were designed against the wrong wall.

Until that is resolved, **model B terminates in a tombstone (`16a`), not in a physical delete**,
and the owner should be told that plainly rather than ruling B and discovering it at `077`.

### B7 — Interactions

| with | result |
|---|---|
| **`ODR-4b`** | `4b` is BLOCKED BY `ODR-16` by name. If B terminates in a tombstone, the `auth.users` CASCADE is **INERT** and `4b` collapses to a documentation choice. If it ever terminates in a real delete, `4b` is load-bearing. **`4b` cannot be ruled first.** |
| **Wallet** | `holder_identity_id` is `IMM` by design and is the "which artifact on which device when" evidence. BLOCK, not clean. |
| **live tickets** | BLOCK. Under `16a` they stay with the tombstone and **still scan** — which is a property the owner should rule on explicitly. |
| **transfers** | `p2p_transfer` BLOCKs both directions. In the live DB, `disputed`/`expired` are **still not in the block list** — unchanged by PR #28, deliberately. |
| **disputes** | `attribution_review.decided_by` and the live `dispute_resolutions.actor_id` are append-only: **TOMBSTONE is the only available disposition**, in both halves. |
| **payouts / refunds** | `payout.payee_identity_id` BLOCKs; `venue.order.buyer_id` BLOCKs because the refund path resolves through it. `16c` is *still not asked*. |

## THE FOUR PRECONDITIONS

| # | precondition | status |
|---|---|---|
| 1 | produce the blocking inventory | ✅ **MET** — 57 columns, this pass |
| 2 | correct the deadline `079` → `077` everywhere | ⚠️ **PARTIAL** — corrected in the register this pass; other sites remain |
| 3 | resolve the cascade/append-only contradiction | ❌ **NOT MET** — and it is worse than stated: it is two relations, at `077` and `082`, and it defeats B and C identically |
| 4 | decide `16c`/`16d` or state they ride on `16b` — **they do not** | ❌ **NOT MET** — `16d` is now measured at 50 of 57 columns |

**New precondition #5, from the inventory:** the **16 SPEC-SILENT `ON DELETE` columns** must be
resolved before `16b` is ruled. Eight of them also state no nullability, so it is not even known
whether `SET NULL` — the cheapest disposition — is available. Ruling a cleanup policy over
columns whose delete semantics are unspecified is ruling on a guess.

## RECOMMENDATION (not a ruling)

**`16b` = B, restated honestly: PENDING while blocking obligations exist, terminating in a
TOMBSTONE rather than a physical delete**, until precondition #3 is resolved. C remains strictly
dominated — it destroys the user's property and still achieves no erasure.

**Build the three-column pending state regardless of the ruling**, for its half-completed-deletion
detector alone.

**Do not rule `16b` until #3, #4 and #5 are closed.** Ruling it now would rule on 7 custody
columns of 57 and silently default the other 50.

# G2 — Settlement payout maturity

Status: **implemented in `docs/phase2/_impl/093_parts/10_money_settlement.sql` (10d) and
`docs/phase2/_impl/093_parts/40_config_privacy_freeze.sql` (the config row).**
093 must be re-assembled (`scripts/assemble_093.sh`) before the change reaches
`supabase/migrations/093_primary_ticketing.sql`. Nothing was deployed. No commit was made.

---

## 0. The defect

`kernel.close_settlement` decided the payout hold with one line:

```sql
v_refund_window := (select (c.value #>> '{}')::interval
                      from catalog.platform_config c
                     where c.key = 'settlement.refund_window_interval' ...);
v_held := v_refund_window is null;
```

The **only** predicate was "is the config key set". No maturity semantics existed anywhere:
no anchor instant, no elapsed check, no refund check, no dispute check. Setting
`settlement.refund_window_interval` to any value — `'1 second'`, `'0 days'` — released every
settlement payout at the moment of close, for every org, forever. An owner config value was a
hidden feature flag for payout logic that had never been written, and the slice's own comment
had to warn in a box that *setting* the key was the dangerous act.

Worse, the key sat in a namespace with no dual control: `settlement.%` matches none of
`set_platform_config`'s dual-control prefixes (078:1145-1147), so one `platform_admin`, in one
statement, with no countersignature, could switch the protection off.

---

## PART 1 — The start instant

### The question

A settlement payout must not mature until some instant has passed. Which instant?

### Candidates, against the schema

| Candidate | Expressible? | Verdict |
|---|---|---|
| (a) payment succeeded | Yes — `public.payments.paid_at`, `kernel.payment_native.linked_at` | **Rejected.** Fails the decisive test outright: a ticket bought three months before doors makes the venue payable three months early. It is also the wrong clock legally — see the Stripe finding below. |
| (b) event ended | **No.** `catalog.event` (078:134-154) carries `title`, `status`, marketing columns, `created_at`/`updated_at` — **and not one instant.** There is no event start or end anywhere on the row. | **Not expressible.** Any "event ended" rule must be reduced to sessions. |
| (c) session ended | Yes — `catalog.event_session.ends_at`. **Nullable** (078:170); `catalog.create_event_session` requires only `starts_at` (078:805-807). | Expressible but incomplete on its own — a settlement can cover many sessions. |
| (d) ticket expired | Yes in principle — `kernel.tickets.state='expired'` — but the sweep that writes it (079:470-508) is **inert until `ticket.expiry_grace` is set**, and it *skips sessions with `ends_at is null`* anyway. It is `ends_at` again, plus an unset owner key, plus a scheduler. | **Rejected.** Strictly weaker than (c) and adds two more failure modes. Also couples payout to a lifecycle sweep that has nothing to do with money. |
| (e) settlement closed | Yes — `venue.settlement.updated_at`. | **Rejected.** Caller-chosen. The org's own finance role decides when to close, so the org would control its own maturity clock. |
| (f) **last applicable session ended** | **Yes, for both settlement grains.** See below. | **Chosen.** |

### Why (f) is expressible for period-scoped settlements too

This was the point that had to be checked rather than assumed, because `venue.settlement` is
event-scoped **or** period-scoped (`event_id` nullable, 087:48).

* `venue."order".event_session_id` is **NOT NULL** (082:369-372). Every primary order resolves
  to exactly one session, whatever the settlement's grain.
* `period_start`/`period_end` are **not** usable as the anchor: both are nullable, and the seams
  bound `es.starts_at` against them (10b, 088:347-351, 090:1529-1533), not `ends_at`. A period
  settlement with a null `period_end` has no upper bound at all.
* So the anchor is **not** derived from the header's scope. It is derived from the settlement's
  **own lines**, which are already written by the time the gate runs:

  ```
  anchor = max(catalog.event_session.ends_at) over the sessions of every order/ticket
           behind this settlement's primary_sale / refund_void / chargeback /
           market_sale / promoter_commission lines
  ```

  That works identically for an event-scoped and a period-scoped header, and it is immune to
  scope-predicate drift. It also picks up 088's chargeback arm, which deliberately carries **no**
  scope predicate (088:311-316) — exactly the rows most likely to be in dispute.

### The external evidence that settles it

Stripe documents this industry by name:

> "Certain industries, such as travel or event ticketing, are prone to longer intervals between
> the original purchase and a dispute. Generally, when a customer pays for a future event or
> service (like a vacation reservation, professional services appointment, or event ticket),
> **the dispute window starts on the event date, not the payment date**."
> — https://docs.stripe.com/disputes/how-disputes-work

Stripe's evidence schema carries a dedicated `service_date` field and lists "Evidence that the
agreed-upon service date hasn't arrived yet" as a defense
(https://docs.stripe.com/disputes/categories). Its reserve guidance names the same scenario:

> "Ticket transactions for an event at risk of cancellation: Set up a fixed reserve plan to
> reserve funds from each transaction and release them all the day after the event."
> — https://docs.stripe.com/connect/connected-account-reserves

The buyer's own clock starts at the event. Anchoring the venue's money on payment would pay out
before the risk period had even begun.

### Two schema facts that force fail-closed behaviour

1. **`ends_at` is nullable and routinely absent.** The corpus already meets this fact in the
   ticket-expiry sweep and **fails open** — 079:490-492 skips such sessions, which slice 40
   records as an unfixed hole. This gate fails **closed**: a session with no end has not
   verifiably ended, so its money does not mature. Reason code `maturity_instant_unknown`.
2. **`event_session.status` is never set to `'completed'` by anything.** Grepped across
   076-092: the only writer of that column is 088:1793, which writes `'cancelled'`.
   (081:939-940 is `catalog.event.status`, a different column.) Requiring `status='completed'`
   would hold every payout forever. Status is therefore used only to detect **cancellation**.

---

## PART 2 — Three different concepts

They are provably distinct, and the corpus already separates two of them:

| Concept | Question | Where it lives today |
|---|---|---|
| **Refund eligibility** | *May a buyer still get money back?* | `refund.buyer_self_service_window_hours`, `refund.buyer_self_service_max_minor`, `refund.request_ttl_hours`, `refund.scanned_atom_policy`, `refund.org_auto_execute_max_minor` (078:1544-1551). Enforced on the **buyer/org request** path. |
| **Payout maturity** | *May the venue's money leave?* | `kernel.close_settlement` → `kernel.payout.hold_state`; exit is `kernel.release_payout` (085:807). Concerns the **seller's** money, not the buyer's rights. |
| **Refund execution** | *The mechanical act.* | `kernel.refund` state machine (085:82-88), `kernel.mark_refund_state` (085:1737), `kernel.get_refund_execution_context` (093/10g), the `refund-execute` edge. Concerns **Stripe**, not policy. |

They differ in subject, in actor, and in failure mode. A buyer can be out of refund eligibility
while a dispute is still open (maturity blocked, eligibility expired). A refund can be
*eligible* and *requested* but stuck in `submitted` because Stripe is down — eligibility says
yes, execution says not yet, and maturity must say **hold**. Collapsing them into one value is
what produced the defect.

### The key name was a lie. It is renamed.

`settlement.refund_window_interval` names refund **eligibility**. The value is not that. It is
*how long after the event the venue's money must sit still* — a payout property.

**Renamed to `payout.settlement_maturity_interval`.**

The prefix is load-bearing, not cosmetic:

* `payout.%` **matches** the dual-control prefix test at 078:1145-1147.
* The key has no entry in the polarity map (078:1152-1198), so it has no declared restrictive
  direction and **every** set of it parks for a second `platform_admin` via
  `kernel.approval_request` / `'config.set_money_key'` (078:1268-1285, consumed at 085:1224/1328).

The rename converts a single-writer bypass on the most dangerous money value in the train into
a two-person control, at zero implementation cost. The old spelling is **not** read as a
fallback — a fallback would preserve the hazard.

Slice 40 (`40_config_privacy_freeze.sql`) has been updated to seed the new key.

---

## PART 3 — Failure matrix

All rows verified by execution against `snatchit_rehears_money` unless marked *(analysis)*.
`P` = policy set, `A` = anchor known, `E` = elapsed, `R` = no refund in flight,
`D` = no open dispute, `U` = covered set resolvable, `C` = not cancelled.

| # | Scenario | Result | Code |
|---|---|---|---|
| 1 | Purchased 3 months early, event 60 days away | **HELD** — `matures_at` = event end + interval, ~5 months after purchase | `maturity_not_elapsed` |
| 2 | Purchased 5 minutes before doors | Identical to #1 — the anchor is the event, so purchase timing is irrelevant to maturity | `maturity_not_elapsed` |
| 3 | Event **postponed** (`ends_at` moved later) | Anchor moves with it → longer hold. **See the residual risk below: `ends_at` is seller-mutable.** *(analysis + execution)* | `maturity_not_elapsed` |
| 4 | Event **cancelled** | `catalog.cancel_event` writes `event.status='cancelled'`, cancels every session (088:1793) and creates `kernel.refund` rows `'pending'`. **Two** independent predicates fire | `event_cancelled` |
| 5 | Partially cancelled | `cancel_event` operates at event grain, so partial is not reachable via RPC; a single cancelled session still trips the same predicate | `event_cancelled` |
| 6 | Multi-day festival (2 sessions) | Anchor = **max**(`ends_at`) = day 2. Verified: a day-1-only settlement released while a day-1+day-2 settlement held | `maturity_not_elapsed` |
| 7 | Multi-session, day 1 matured, day 2 not | **HELD.** Verified explicitly: `d1only` → released, `d1d2` → held | `maturity_not_elapsed` |
| 8 | Refund requested **before** the event | Refund row `pending` → held on two predicates | `maturity_not_elapsed` then `refund_in_flight` |
| 9 | Refund requested **after** the event, before close | **HELD** | `refund_in_flight` |
| 10 | Chargeback filed **after** the window, payout already released | **NOT COVERED.** The dispute lands as a `chargeback` line in the org's *next* settlement (088:311-316). If none is ever opened, uncollected. This is the irreducible residual — see Part 6 | — |
| 11 | Stripe dispute open at close | **HELD** | `dispute_open` |
| 12 | Dispute already `lost`/`charge_refunded` | Not held by the dispute predicate — those are terminal and **already lined** as debits by 10h, so they are inside `net_minor` | — |
| 13 | Promoter commission funded | Untouched. Commission payouts are minted `held`/`unfunded_settlement` by `kernel.pay_promoter_commission` (090:1487-1491) and this function never reads or writes them. Verified: 0 `promoter_commission` payouts existed after 9 closes | — |
| 14 | Venue Connect account disabled / absent | Orthogonal. `kernel.request_org_payout` already refuses with `no_payout_destination` when `stripe_connect_account_ref is null` (087). The maturity gate neither duplicates nor weakens it *(analysis)* | — |
| 15 | No-show buyer | No effect — maturity reads no ticket state. Deliberate: a no-show is not a refund | — |
| 16 | Scanner never records entry | No effect, for the same reason. This is why `ticket.state='scanned'` was **not** used as a predicate | — |
| 17 | Settlement close delayed by weeks | All predicates pass → payout minted **unheld**. Correct: the risk period already elapsed | — |
| 18 | Payout executor offline a week | No effect. The payout is `pending` and nothing expires it; `request_org_payout` is a separate verb | — |
| 19 | Hand-inserted line with an unresolvable `cause_ref` | **HELD** — we cannot say what the money is about | `covered_set_unresolvable` |
| 20 | Settlement whose only line is a non-money cause (`import`) | **HELD** — zero anchors | `maturity_instant_unknown` |
| 21 | `ends_at IS NULL` on a covered session | **HELD** | `maturity_instant_unknown` |
| 22 | Policy key unset (ships `null`) | **HELD** — unchanged behaviour and unchanged code, so 151 C20i..C20n stay green | `unbounded_refund_exposure` |
| 23 | Policy value negative | **HELD** | `maturity_policy_invalid` |
| 24 | Everything satisfied | **RELEASED**, `hold_state='none'` | — |

### Residual risk: the anchor is mutable by the party being paid

`catalog.update_event_session`'s time guard (079:625-659) fires **only** when `starts_at` or
`doors_at` change. An `ends_at`-only patch takes no guard, needs no `reason_code`, and is
permitted with atoms already issued — verified by execution: a `venue_manager` moved `ends_at`
by +30 days and the call returned `ok`.

Bounds of the exposure:

* `event_session_time_check` forces `ends_at > starts_at`, so `ends_at` alone cannot be
  backdated earlier than the session start. The most a seller can shave with an `ends_at` edit
  is the session's own duration — hours, not months.
* Moving `starts_at` **forward** is refused while `door.schedule_move_grace_interval` is unset
  (fail-to-safe, 079:637-652). Moving it **backward** is not refused, and a
  `starts_at`+`ends_at` pair moved backward *would* backdate the anchor arbitrarily — but only
  while `door_open_at is null` (079:628), with a mandatory `reason_code`, and it writes a
  `session.update` audit row carrying before/after.

**Not closed here, and deliberately.** The right fix is an immutable maturity anchor stamped on
the order at `venue.finalize_primary_order` time, or a backward-move guard on
`update_event_session`. Both are DDL / edits to frozen migrations and are outside 093's scope.
Recorded as an owner item, not silently absorbed.

---

## PART 4 — What was implemented

`kernel.close_settlement`, at the payout mint only. The release condition is a **conjunction**;
the code names the first failing predicate so an operator can act:

```sql
v_hold_reason := case
  when v_maturity is null                        then 'unbounded_refund_exposure'
  when v_maturity < interval '0'                 then 'maturity_policy_invalid'
  when coalesce(v_unresolved, 1) > 0             then 'covered_set_unresolvable'
  when coalesce(v_cancelled, true)               then 'event_cancelled'
  when coalesce(v_sess_n, 0) = 0
    or coalesce(v_sess_no_end, 1) > 0
    or v_anchor is null                          then 'maturity_instant_unknown'
  when now() < v_anchor + v_maturity             then 'maturity_not_elapsed'
  when coalesce(v_refund_open, true)             then 'refund_in_flight'
  when coalesce(v_dispute_open, true)            then 'dispute_open'
  else null
end;
v_held := v_hold_reason is not null;
```

Design points:

* **Never assume satisfied.** All seven operands are declared pre-set to the value that holds
  (`v_unresolved := 1`, `v_sess_n := 0`, `v_cancelled := true`, …), and every branch is
  `coalesce(…, <holding value>)`. A code path that fails to compute an operand can only fail
  toward the hold.
* **The covered set comes from the settlement's own lines**, not the header scope — resolved for
  all five seam causes to both a `payment_id` (for the refund/dispute predicates) and an
  `event_session_id` (for the anchor). A line that resolves to neither is `covered_set_unresolvable`.
* **`'unbounded_refund_exposure'` is retained verbatim** for the policy-unset arm. It names the
  same fact it always named, and it keeps 151 C20i..C20n and every operator runbook intact.
* **Precedence hides nothing.** The full predicate vector goes to the additive
  `payout_hold_detail` return key **and** to the `settlement.close` audit row's `after` column
  (`{"payout_hold": …, "hold_predicates": {…}}`) — including `matures_at`, so an operator can
  see exactly when the money becomes payable.
* **`'lost'` / `'charge_refunded'` are not "open" disputes.** They are terminal and already
  booked as `chargeback` debits by 10h, so they are inside `net_minor`, not a reason to hold.

Every existing property is preserved:

* The seams still cannot raise into `close_settlement` — none of them was touched.
* The ledger still records the full truth while held: header `closed`, all four money columns
  written, every line standing. Verified across nine closes.
* `kernel.release_payout` (platform_risk / platform_admin, Control-5) is still the sole exit.
* **Ruling A4 — restated with evidence.** The only `kernel.payout` row this function touches is
  the one it `INSERT`s itself: `cause='settlement'`, `payee_kind='organization'`. There is **no
  `UPDATE` and no `DELETE` on `kernel.payout` anywhere in the body**, no reference to
  `venue.promoter`, `venue.attribution` or `kernel.pay_promoter_commission`, and no call to
  `kernel.release_payout`. Every change in this revision can only move a payout from unheld to
  **held**. Confirmed by execution: after nine closes,
  `select count(*) from kernel.payout where cause='promoter_commission'` = **0**.

### Verification

`scripts/rehearsal_reset.sh snatchit_rehears_money` → 108/108 migrations, GATE-2 baseline
matched. The new function was then applied and the matrix above executed. Cases 1-9 of the
matrix and the four decisive cases (`early`, `fest`, `d1only`, `d1d2`) all produced the expected
hold state and reason code.

### Test deltas (`supabase/tests/` NOT edited — reported, per scope)

Full suite after the change: `TOTAL plan=2960 ok=2792 not_ok=12`. **152, 154, 155, 156, 157 pass
unchanged.** The deltas, all of them consequences the change is *supposed* to have:

| File | Assertion | Why it flips | Fix |
|---|---|---|---|
| 142 | `D5a` (142:287-296) | names `settlement.refund_window_interval` in the five-key census | swap the two literals for `payout.settlement_maturity_interval` |
| 142 | `D40` (142:414-416) | counts `refund.%`/`payout.%`/`authn.%` → **16, was 15**. This is the rename *working*: the key joined the money / dual-control namespace | `15` → `16`, and amend the comment |
| 151 | `C28a`, `C28b` (151:487-491) | the fixture sets the key and closes `s3`, whose only line is a hand-inserted `primary_sale` with a `gen_random_uuid()` `cause_ref` → now `covered_set_unresolvable` | give `s3` a real order (payment + `payment_native` + a session with `ends_at` in the past), like the fixture at 151:150-200 already builds |
| 151 | `C29a`..`C31i1` — **341 psql errors** | cascade only: line 495's `request_org_payout` raises `payout_held` inside an unguarded `SELECT is(...)`, aborting the file | fixed by the `C28a`/`C28b` fixture repair above; nothing else in the block changes |
| 153 | `H2`, `H6`, `H11`, `H12` | 153:657 sets the key to release a payout; same synthetic-fixture cause | same repair |

**151 C20i..C20n and C1..C28 all stayed green** — the retained `'unbounded_refund_exposure'`
code was chosen precisely to preserve that block.

---

## PART 5 — Stripe research (cited)

Stripe's payout schedule and Snatch It's settlement policy are **different objects** and are not
conflated anywhere in this design. Stripe's schedule governs money leaving the *Stripe balance*;
`payout.settlement_maturity_interval` governs whether Snatch It creates a *transfer obligation*
at all.

**Disputes**

* 120-day baseline: "Card networks typically allow cardholders to initiate disputes within 120
  days of the original payment, but their rules allow more time in some situations."
  — https://docs.stripe.com/disputes/how-disputes-work
* **Deferred clock for ticketing**: "when a customer pays for a future event or service (like a
  vacation reservation, professional services appointment, or event ticket), the dispute window
  starts on the event date, not the payment date." — same URL
* Merchant response window "usually 7 to 21 days"; issuer evaluation "usually 60-75 days";
  full lifecycle "2-3 months". — https://docs.stripe.com/disputes/responding, same URL
* Post-payout disputes debit the balance: "Stripe in turn debits your Stripe balance for the
  disputed amount plus a dispute fee"; on Connect "your platform balance is automatically
  debited". — https://docs.stripe.com/disputes/how-disputes-work,
  https://docs.stripe.com/connect/charges
* Inquiries close at 120 days without escalation; ~80% of early fraud warnings convert to a
  fraud dispute if ignored. — https://docs.stripe.com/disputes/how-disputes-work
* Not found in official docs, and therefore **not relied on**: per-network filing windows
  (Visa/MC/Amex/Discover) and the 540-day outer cap. The 540-day figure appears only on a Stripe
  *marketing* page (stripe.com/resources), not docs.stripe.com.

**Payouts (Stripe's own schedule — separate concern)**

* Connect default is a daily rolling basis; standard settlement US 2 business days, UK/EU/CA 7
  calendar → 3 business days. — https://docs.stripe.com/connect/payouts-connected-accounts,
  https://docs.stripe.com/payouts
* `settlement_timing.delay_days_override` up to **31**; cannot go below the account's default.
  — https://docs.stripe.com/connect/manage-payout-schedule
* Manual payouts are **not** indefinite: funds must be paid out within **90 days** (most
  countries), **2 years** (US), **10 days** (Thailand).
  — https://docs.stripe.com/connect/manual-payouts
* Reserves: "You can't reserve funds for longer than 180 days." Named scenario: "Ticket
  transactions for an event at risk of cancellation: Set up a fixed reserve plan … and release
  them all the day after the event." Risk-factor list names "event ticketing" explicitly. ToS
  "must clearly explain your reserve policy."
  — https://docs.stripe.com/connect/connected-account-reserves
* "We advise against platforms holding funds arbitrarily … hold funds only when there's a clear
  purpose and a commitment to transfer them … when an event occurs or a precondition is
  satisfied." — https://docs.stripe.com/connect/account-balances

That last sentence is a fair description of what this gate now is: a hold with a named
precondition and a contracted release verb, rather than an unbounded one.

**Not found:** any Stripe-recommended numeric post-event hold for ticketing. The gap is real,
and it is why Part 6 does not claim a derived number.

---

## PART 6 — Recommended launch policy

| Question | Recommendation |
|---|---|
| **Maturity start instant** | `max(catalog.event_session.ends_at)` over the sessions behind the settlement's own money lines. Not payment, not close, not `period_end`. |
| **Hold interval** | **`'7 days'`.** See the honesty note below. |
| **Postponement** | Anchor moves with `ends_at`; hold extends automatically. Separately: close the `ends_at`/backward-`starts_at` mutability hole (owner item — DDL). |
| **Cancellation** | Never matures. `event_cancelled` hold; a human releases or the net nets out. |
| **Unresolved refund** | Never matures. `refund_in_flight`. |
| **Unresolved dispute** | Never matures. `dispute_open`. |
| **Chargeback after release** | **Not covered by any interval.** See below. |
| **May a payout mature with a refund pending?** | **No.** |
| **May a payout mature with a dispute open?** | **No.** |
| **Does promoter commission change maturity?** | **No** — and maturity does not change promoter commission either (ruling A4). A commission line's attribution *does* join the covered set for the refund/dispute predicates, so a disputed attributed order holds the *org* payout; the commission payout stays `held`/`unfunded_settlement` regardless. |

### Honesty note: no interval is "safe", and the evidence supports no exact number

The evidence does **not** derive an interval, and the report should not pretend otherwise:

* The dispute window runs ~120 days **from the event date** (Stripe, above). Fully covering it
  needs a ~120-day post-event hold. That is commercially impossible for a venue, and it exceeds
  the 90-day manual-payout holding limit that applies outside the US.
* Stripe's only concrete ticketing recommendation is a reserve released **the day after the
  event** — which leaves the entire post-event dispute window uncovered. Stripe documents both
  facts and never reconciles them.
* Stripe publishes no recommended post-event hold for ticketing at all.

So `'7 days'` is a **risk/commercial trade, not a derivation**, and it is offered on stated
grounds:

* It is strictly more conservative than Stripe's own documented ticketing guidance (day-after).
* It sits comfortably inside the 90-day non-US manual-payout limit and well under the 180-day
  reserve cap, so it stays compatible with either Stripe mechanism later.
* It covers what a short post-event hold *can* cover: post-event refund requests, which
  concentrate in the first days; early-fraud-warning arrivals; and the refund executor's own
  latency.
* It is a `payout.%` key, so raising it later is a two-person, audited, no-migration change.

**What 7 days does not cover, stated plainly:** a chargeback filed 30, 60 or 110 days after the
event, once the money has left. No commercially viable interval closes that. Closing it needs
one of two things this schema does not have, and both are owner items, not 093:

1. a **receivable / carry-forward object** so a post-payout debit lands somewhere real instead of
   in a settlement that nets negative and mints nothing; or
2. a **Stripe fixed reserve plan** per event (https://docs.stripe.com/connect/connected-account-reserves),
   which keeps a percentage of each ticket transaction behind until after the event — note its
   180-day ceiling means a ticket sold more than 180 days ahead cannot be fully covered, and
   note the ToS requirement that the reserve policy be disclosed.

Until one of those exists, `payout.settlement_maturity_interval` bounds the *pre-payout* window
and nothing more. That is a genuine improvement over `config IS NOT NULL`, and it is not a
complete answer.

### Setting the value

```sql
select catalog.set_platform_config(
  'payout.settlement_maturity_interval', '"7 days"'::jsonb, '<reason>', '<command key>');
```

This will **park** for a second `platform_admin` (no polarity declared on a `payout.%` key). That
is intended. Setting it is no longer sufficient to release anything.

# J6 — REFUND ACCOUNTING TIMING: WHEN THE VENUE'S OBLIGATION IS REDUCED

Date: 2026-09-03 · Agent F · branch `feature/venue-native-and-product-v2`, HEAD `09e167f`.
Scope: `kernel.settlement_primary_lines` (093 slice 10b), `kernel.settlement_payout_maturity`
(10m), `kernel.get_payout_execution_context` (10n), `kernel.claim_refunds_for_execution` (10i),
`kernel.refund` (085 PART 2), `venue.settlement_line` (087 PART 3), `catalog.cancel_event`
(088:1612).

Method: full 108-file replay on a private local rehearsal DB (`snatchit_rehears_refacct`,
`scripts/rehearsal_reset.sh`; GATE-2 `tables=27 functions=70 policies=37 triggers=26`, matching
the CI baseline). Every claim below marked **[X]** is an executed reproduction on that database,
not an argument. No production mutation, no remote, no deploy, no Stripe call, no git commit.

---

## 1. THE PREDICATE, FROM BYTES

The brief's suspected defect — the debit booked at `status <> 'failed'` — **is not what is in the
code today.** A previous train already replaced it. Quoted verbatim from
`supabase/migrations/093_primary_ticketing.sql`:

**The debit arm** (`093:526`, inside CTE `refund_candidate`):

```sql
      join kernel.refund r on r.payment_id = pn.payment_id and r.status = 'succeeded'
```

**The deferral** (`093:477-479`, the last predicate of CTE `scoped_order`):

```sql
       and not exists (select 1 from kernel.refund r0
                        where r0.payment_id = pn.payment_id
                          and r0.status in ('pending','submitted'))
```

So the current shape is **succeeded-only debit + whole-order deferral of any order carrying a
non-terminal refund**. `093:322-345` records why, and names the superseded predicate explicitly:
`An earlier draft of this seam booked the debit at 'status <> 'failed'', copying 085:538-539's
over-refund accounting. That was safe only while 'failed' was UNREACHABLE`.

The mirror question therefore stands as the brief anticipated: **is deferral correct, or does it
strand the venue's revenue?**

---

## 2. STATE-BY-STATE ECONOMIC ANALYSIS

`kernel.refund.status` is forward-only `pending → submitted → succeeded|failed` (085:82-85), and
the `refund_ref_pairing_ck` (085:93) makes the *wrong* reading of `failed` unstorable: `pending`
carries no `stripe_refund_ref`, everything past it must. So the states carry these Stripe facts:

| state | what happened at Stripe | is the money committed? | may the venue be debited? |
|---|---|---|---|
| `pending` | we have not yet successfully POSTed `/v1/refunds`, or the call's result was lost. No refund object is known to exist. | **No.** It may never be created at all. | No |
| `submitted` | Stripe returned a refund object; it is `pending` / `requires_action` / unrecognised there. Money is *in motion*. | **No.** `refund-execute/executor.ts:546-556` maps Stripe `canceled` → our `failed`, and `requires_action` → stay `submitted`. Both can still end in the buyer receiving nothing. | No |
| `succeeded` | Stripe's own returned object says `succeeded`. | **Yes.** This is the only state in which the buyer demonstrably has the money back. | **Yes — this is the point of commitment.** |
| `failed` | Stripe **accepted** the refund and then could not settle it (085:86-88). | Committed in the *other* direction: the money did not leave and is not going to under this refund row. | No — and no debit is owed, because the buyer was not paid. |

**`pending` is too early** by a wide margin — nothing at Stripe corresponds to the row yet.
**`submitted` is too early too**, and this is the non-obvious half: `submitted` looks like "Stripe
took it", but Stripe's own terminal set includes `canceled`, which the executor maps to our
`failed`. A `submitted`-triggered debit is a debit that Stripe can still retract.

**Both directions of error are real, and they are not symmetric in reversibility:**

* **Too early** — the venue is debited for money the buyer never received. `venue.settlement_line`
  is append-only (087:110-112) and 10c's `settlement_one_refund_void_line_ever` is `unique
  (cause_ref) where cause = 'refund_void'`, so the line can be neither amended nor offset. The
  error is **permanent**. §4 traces it.
* **Too late / deferred** — the venue's revenue is withheld. The error is **recoverable**: the
  order simply appears in the next close. §3 proves the recovery is exact in both directions.

Recoverable beats permanent, so `succeeded` is the correct commitment point. Conjunct (ii) —
whole-order deferral — is what makes the choice safe rather than merely conservative: booking
`succeeded`-only *without* it would let a close pay the venue face value while a refund on that
order is still in flight, and **nothing else in the corpus stops that.** Verified: `close_settlement`
(087:289-355) and `request_org_payout` (087:423-465) read `kernel.refund` nowhere, and the R-40
gate deferred to 088 at `087:406-407` was never authored — no `create or replace function` for
either exists in 088-092.

The grain is right too: deferral is **per order**, not per settlement. One stuck refund does not
freeze a venue's unrelated revenue. **[X] A9** in the new suite pins it.

---

## 3. RECONCILIATION AFTER THE PROCESSOR ANSWERS — BOTH DIRECTIONS

Deferral is only defensible because it is temporary. `venue.open_settlement` (087:227-269) carries
**no uniqueness on `(org, venue, event, period)`** — verified from bytes — so a second settlement
over the same scope is openable, and 10c's two global partial unique indexes make double-crediting
unstorable. That is the recovery channel.

**[X] Executed** (`159_refund_accounting_timing.sql`, sections B and D):

| sequence | result |
|---|---|
| pending refund at close #1 | `(no lines)`, `net_minor: 0`, `payout_ids: []`. Order appears **nowhere** in the ledger. |
| same refund → `submitted`, close again | still `(no lines)` — `submitted` defers identically |
| → `succeeded`, close #2 over the same scope | `primary_sale 10000 \| refund_void -10000`; the order's total contribution across all settlements is **exactly 0** |
| → `failed` instead, close #2 | `primary_sale 10000` **alone**; the venue keeps face value, which is right — the buyer was not paid |
| partial `succeeded` refund | `primary_sale 10000 \| refund_void -3000` — never a naked negative (closes the adversarial **X-5** shape) |
| refund of 11000 against face 10000 (refund measured on `payments.total` = face + buyer fee) | debit capped at `-10000`; the 1000 fee residual stays platform money per ruling A5 |

**Liveness of the deferral.** `kernel.claim_refunds_for_execution` (093:1334-1347) selects
`r.status in ('pending','submitted')` with **no age cap and no attempt cap** — it re-claims a
non-terminal refund forever, and `submitted` rows are always issued `execution_mode = 'reconcile'`,
which establishes existence at Stripe before creating. So progress is bounded by Stripe, not by the
platform. The honest residual: a Stripe refund parked at `requires_action` that the buyer never
completes stays `submitted` indefinitely, which withholds that one order's face value indefinitely
**and** blocks that buyer's account deletion indefinitely (BP-12 arm 1, 085:249-262). That is a
bounded, per-order, *recoverable* exposure with an operator remedy (fail the refund, re-issue), and
it is the correct side of the trade.

**Event cancellation.** `catalog.cancel_event` inserts one `kernel.refund` per order in one
statement, all born `pending` (085:83, no status argument at 088:1664/1716/1774). The cohort is
therefore deferred **as a whole**. **[X] D1/D1a/D2**: the seam emits zero candidates for the
cancelled event, the close nets 0 and mints no payout, and once two of three refunds succeed and
one fails, the later close books three credits and two debits for a net of exactly the failed
order's face value — with `event_cancelled: true` in the maturity detail, so even that residual
payout is minted **held**.

---

## 4. THE FAILED-REFUND TRACE — WHAT A BOOKED DEBIT COSTS

Counterfactual: had the debit been booked and Stripe then definitively failed the refund, this is
the complete set of corrections the schema can represent. **[X] Every arm executed:**

```
A) UPDATE the line                                 -> ERR P0001 append_only: settlement_line is immutable
B) DELETE the line                                 -> ERR P0001 append_only: settlement_line is immutable
C) compensating +line, same cause+ref, SAME settlement  -> ERR 23505 settlement_line_cause_uq
D) compensating +line, same cause+ref, OTHER settlement -> ERR 23505 settlement_one_refund_void_line_ever
E) compensating +line under cause 'admin_action'        -> INSERTED
F) a new cause 'refund_reversal'                        -> ERR 23514 settlement_line_cause_check
```

The brief's suspicion about the global partial unique index is **confirmed**: (D) is refused, so a
second `refund_void` fact for that refund is unstorable platform-wide, exactly as `093:333-336`
claims. (F) is refused too — `cause` is a closed CHECK set (087:97) and widening it is DDL on a
frozen money table.

**Only (E) is representable**, and it is not a fix: it books a positive `admin_action` line, which
asserts an administrative act that never occurred, in the one ledger the corpus treats as the
durable record of what a venue is owed. The correction would be a **lie recorded as a fact**.

So a correction here genuinely requires a *new fact*, not an amendment — and the only honest new
fact the schema already has is a **new `kernel.refund` row**. That is the real compensating path
and it works: **[X]** after a `failed` refund books `primary_sale 10000` alone, a second refund row
on the same payment reaching `succeeded` books `refund_void -10000` in a later settlement, and the
order's lifetime contribution returns to 0. I did not edit the append-only ledger, and no change to
it is warranted.

**Conclusion: the current code never books a debit it cannot take back, so the failed-refund loss
does not arise. The defect described in the brief is already closed. There is nothing to fix in
10b.**

---

## 5. WHAT I FOUND INSTEAD — AND WHO OWNS IT

**[X] J9 — booking the debit *correctly* is what unlocks an overpayment, before any payout.**
Executed end to end on the rehearsal DB with the maturity key set, the session backdated, and the
destination bound:

```
step 1  refund R1 created, Stripe FAILS it
        close S9 -> net 10000, payout P9 minted (released)
        transfer gate                                  -> ELIGIBLE — WILL TRANSFER
step 2  buyer is re-refunded; R2 created (pending)
        transfer gate                                  -> refund_in_flight        (held)
step 3  R2 SUCCEEDS. Money is gone. Nothing lined yet.
        transfer gate                                  -> refund_exposure_stale   (held)
step 4  an operator does the ACCOUNTING CORRECTLY: opens S9b, closes it
        S9b lines -> refund_void -10000 ; net -10000 ; payouts minted: 0
        transfer gate                                  -> ELIGIBLE — WILL TRANSFER
SCORE:  venue will be PAID 10000 · buyer was refunded 10000 · ledger says org net 0
```

The pre-transfer gate at `093:2383` refuses on `v_stale_minor > 0`, which measures **unlined**
refund exposure. Booking the debit sets `lined = entitled`, the operand goes to zero, and the gate
turns green — while the debit itself landed in a *different* settlement whose `net_minor` is
negative, and `close_settlement` mints no payout for a negative net (`093:725`, `if v_net > 0`).
The org's ledger sums to zero across two settlements; only the positive one carries a payout.

**Root cause:** `kernel.payout` is minted per *settlement*, but the obligation is per *organization*.
A negative settlement is a claim against the org that no object carries and no gate reads. The
correct accounting act is what defeats the guard.

**This is not mine to fix, and I have deliberately not fixed it.** It is precisely the
receivable / negative-obligation object `J3_receivable_architecture.md` is designing. Its operand
belongs at `093:2383` in `kernel.get_payout_execution_context`, alongside `refund_exposure_stale`.

**J9 IS NOT J3's Q1, AND THE DIFFERENCE IS A SCOPE PREDICATE.** J3 §7.2/Q1 concerns the netting
that *already ships*: `088:310-316`'s chargeback arm carries **no scope predicate**, so a chargeback
debit drifts into the org's *next* settlement whatever its scope, and thereby offsets an unrelated
venue's earnings by accident. **The `refund_void` arm behaves differently, and the difference is
load-bearing for J3's design:** 10b's `refund_candidate` joins `scoped_order` (`093:519`), which is
bound to the settlement's own event, or venue + period. A refund debit therefore **cannot** drift
into another scope's settlement. It can only ever land in a settlement over the same event — and if
that settlement has no other revenue, the debit lands alone, nets negative, and mints nothing.

So the two debit causes fail in opposite directions:

| cause | scope predicate | failure mode |
|---|---|---|
| `chargeback` (088:311-316) | **none** | over-collects — silently confiscates an unrelated venue's later revenue (J3 Q1) |
| `refund_void` (093:519 via `scoped_order`) | event, or venue + period | under-collects — strands in a negative settlement that mints no payout and offsets nothing (J9) |

A receivable object that only replaces the accidental netting solves J3's half. J9's half needs the
object to be *reachable from a scope that will never share a settlement with the debt*, i.e. keyed
to the **organization**, not to the settlement or venue that produced it.

---

## 6. CLASSIFICATION

Split, and the split is the whole point:

* **"When does a refund become economically real?" — PURELY IMPLEMENTATION TIMING, and already
  correct.** `succeeded`, with whole-order deferral of non-terminal refunds. Derivable from the
  state machine and from what each state means at Stripe; no owner input required; no change made
  to 093 or to any migration. It was, however, **entirely untested** — see §7.

* **"Who bears the loss when the ledger nets to zero across two settlements but only the positive
  one has a payout?" — ARCHITECTURE DEFECT REQUIRING OWNER POLICY.** I am not answering it.

  The general netting entitlement is already filed by J3 as its **Q1** ("should an obligation
  incurred at ORG A / Venue 1 offset ORG A / Venue 2's earnings?"), and I do not restate it. What
  J3's Q1 does **not** cover is the question J9 raises, because Q1 is about a debit that *does*
  drift into a later settlement and this one *cannot*:

  > A refund debit is scope-bound (`093:519`): it can only ever be lined in a settlement over the
  > **same event**. When that settlement closes negative and mints nothing, and the organization
  > holds an unexecuted payout for a **different** event, is the platform entitled to withhold that
  > payout until the negative is discharged?
  >
  > This is not the same permission as Q1. Q1 asks whether netting *may* happen where the ledger
  > already makes it happen by accident. This asks whether the platform may **create** a withholding
  > right where the ledger structurally cannot net at all — and the alternative is not "pay in full
  > and net later", it is "pay in full and never collect", because no later settlement over event B
  > can ever contain event A's refund debit.
  >
  > Sub-questions the answer must settle: (a) is the withholding right bounded to the same venue or
  > to the whole organization? (b) does it survive a change of venue operator? (c) if the org never
  > earns again, does the platform absorb the loss or pursue it as a debt? (d) is the venue entitled
  > to notice before a payout is withheld for a loss arising at a different event?

  The *mechanism* (a first-class receivable read by the transfer gate) is J3's object. The
  *entitlement* above is not a design question and must not be answered in code.

---

## 7. WHAT I CHANGED

**No migration was modified.** Not 000-092, not 093, not any 093 slice. Nothing in 094 — the J9
finding belongs to the receivable object's author and I have left 094 untouched to avoid colliding
with them. Checked for overlap after the fact: `094_payout_state_machine_recovery.sql` landed
during this analysis and touches `kernel.payout`'s authorization edge, not
`kernel.settlement_primary_lines`, `kernel.refund` or `venue.settlement_line` — no collision with
this lane in either direction.

**One new file: `supabase/tests/159_refund_accounting_timing.sql` — 22 assertions, 22/22 green,
0 errors.** The timing contract this document analyses had **no test coverage whatsoever**. `151`
pins the cross-settlement uniqueness of the line (`C20e`-`C20h`) and the payout gate's
`refund_in_flight` predicate (`C28m`-`C28u`), but nothing asserted that `pending`/`submitted`
suppresses *both* arms, or that `failed` releases the credit *without* a debit. A future refactor
could have silently reintroduced the exact `<> 'failed'` predicate 093 removed and every suite
would still have passed.

| § | assertions | pins |
|---|---|---|
| A | A1-A9 (11) | the candidate contract per refund state: control, `pending` defers both arms, `submitted` defers both arms, `failed` credits with no debit, `succeeded` books both, partial never naked-negative, the ruling-A5 face cap, per-order grain |
| B | B1-B4 (5) | close #1 leaves a deferred order nowhere in the ledger; a second settlement over the same scope is openable; the once-deferred order nets exactly 0; the FAILED mirror releases the credit alone |
| C | C1-C3 (3) | why the seam must be preventive: the line cannot be amended, withdrawn, or offset under its own cause |
| D | D1-D2 (3) | `cancel_event`'s whole cohort defers at once, nets 0, mints no payout; after resolution the venue is owed exactly the failed refund's face value |

The CI plan-parity gate sums `plan()` across `supabase/tests/*.sql` and compares it to the
assertions pg_prove runs; +22 on both sides, so the gate stays balanced.

---

## 8. THE BOUNDARY WITH THE POST-PAYOUT CASE

Three regimes, separated by two named instants. This is the handoff.

```
  refund exists                refund created            refund created
  BEFORE close                 AFTER close,              AFTER the transfer
                               BEFORE the transfer
  ─────────────────────────────────────────────────────────────────────────────
        MINE (J6)                    MINE (J6)              NOT MINE
   whole-order deferral        the payout is HELD       money has left; the
   in 10b's scoped_order       ────────────────────     only remedy is a
   (093:497-500)               refund_in_flight   →     receivable / negative
                               refund_exposure_stale    obligation object
                               (093:2381, 2383)
  ─────────────────────────────────────────────────────────────────────────────
                            ▲                         ▲
              close_settlement writes           mark_payout_transfer_state
              venue.settlement.status='closed'  (085:1668) writes the
              and mints kernel.payout           write-once stripe_transfer_ref
                                                (085:133)
```

* **Boundary instant 1 — `kernel.close_settlement`.** Before it, deferral is the whole mechanism;
  the seam simply does not emit the order. After it, deferral is impossible in principle: no seam
  can defer a refund that did not exist when the lines were written.
* **Boundary instant 2 — `kernel.mark_payout_transfer_state` writing `stripe_transfer_ref`
  (085:133, write-once).** Up to that instant the money is still ours and the correct answer is
  always **hold**; `kernel.settlement_payout_maturity` is called from all three sites
  (`093:824` mint, `093:1859` `request_org_payout`, `093:2311` `get_payout_execution_context`), so
  a refund arriving at any point before the transfer is caught. After it, no gate can help.

**The two designs meet at `093:2383` and nowhere else.** My side of the seam guarantees that a
refund which is *unlined* is visible to the gate (`refund_exposure_stale`). The receivable object's
side must supply the operand for a refund which **is** lined but whose debit landed in a negative
settlement with no payout — the J9 case. Concretely, the neighbouring agent should add one conjunct
to that same `case` chain (an outstanding-obligation balance for `v_po.payee_org_id`), not a second
gate elsewhere: the corpus's own rule is one definition, three call sites, so the mint, the request
and the transfer cannot drift about what "matured" means.

**Nothing in my lane needs to move for that to land.** 10b's predicate is independent of it: the
receivable object changes *whether the positive payout may execute*, never *when the debit is
booked*. And there is no overlap in the other direction — a refund arriving before the payout can
never require the receivable object *provided* the gate holds, which §5 shows it currently does not
in the one case where the accounting is done correctly.

---

## 9. OPEN ITEMS I AM NOT TAKING

1. **J9 (§5)** — handed to `J3_receivable_architecture.md`'s author, with the executed
   reproduction, the exact insertion point (`093:2383`), and the scope-predicate asymmetry that
   makes it distinct from their Q1.
2. **The owner policy question (§6)** — written, not answered. Deliberately narrowed so it does not
   duplicate J3's Q1.
3. **No operator worklist for deferred orders.** Deferral withholds an order's face value until
   *someone opens another settlement over that scope*, and `venue.open_settlement` is a human RPC
   with no automatic trigger. Nothing in the corpus surfaces "these paid orders are in no
   settlement because a refund is in flight." This is an operational gap, not a code defect, and a
   read-only diagnostic view would close it — but it is additive surface in 094 and I have left
   094 alone. Flagging it rather than claiming it.

# RULING G4 — FUNDED PROMOTER COMMISSION WHEN THE REVENUE IS REVERSED

**Status: DRAFT. NOT APPROVED. NOT SIGNED.**

Every figure below was executed against a full local replay (113/113, Gate-2 at CI baseline), not
reasoned from documents.

---

## 1. THE DISTINCTION THAT GOVERNS EVERYTHING

**FUNDED is not PAID, and the two are different problems.**

A funded commission has not left the platform. Option B funds a commission as a **negative settlement
line**, which reduces the venue's distributable — so at close the platform simply *retains* that money.
It is still in the platform's Stripe balance.

No promoter commission payout has ever left `pending`. Every one is minted `held` /
`unfunded_settlement`, and containment was proved to be **four independent locks, not one boolean**: a
commission hold was deliberately released in rehearsal and the money still could not move —
`payout_state_backwards` on the transition, an empty claim batch, and the execution context refusing
`cause_not_settlement` even with `submitted` forced as table owner. **Releasing every hold today would
pay no promoter.**

That is why this is a decision and not an incident.

---

## 2. MEASURED BEHAVIOUR

Fixture: 10 000 face, commission 1 000 (1 000 bps), venue distributable 9 000.

| | Case | Commission line | Commission payout | Venue | Verdict |
|---|---|---|---|---|---|
| A | full refund **pre**-close | none | none | 0 (net 0) | correct |
| B | partial refund 4 000 **pre**-close | none | none | 6 000 | **promoter short 600 — 100% of what was earned** |
| C | full refund **post**-close | −1 000 immutable | 1 000 held | 9 000, execution-eligible | over-funded 1 000 (100%) |
| D | refund after venue **paid** | −1 000 | 1 000 held | 9 000 **paid** | over-funded 1 000; nothing claws back |
| E | chargeback after paid | −1 000 | 1 000 held | 9 000 **paid** | over-funded; 11 000 dispute correctly capped to −10 000 |
| F | cancellation post-close | −1 000 | 1 000 held | 9 000 now **held** `event_cancelled` | venue side protected; commission still over-funded |
| G | funded, never released | −1 000 | 1 000 held | 9 000 | control |
| H | multiple codes per order | — | — | — | **structurally impossible** — `attribution_one_per_order UNIQUE(order_id)` |

**A correction to the previous report.** Its headline "79% of funded commission stood against reversed
revenue" was a fixture artifact; the correct figure for that fixture is 75%. Neither number is the point.
What is *not* an artifact:

- over-funding hits **100% of the commission** on any full reversal (3 of 3 cases), and
- under-funding hits **100% of what was earned** on any pre-close partial refund (1 of 1).

**Case B is the finding the earlier reports missed.** The existing pre-close exclusion is not merely
conservative — a 4 000 refund on a 10 000 sale leaves the promoter with **nothing** when they had earned
600. That is not an over-correction at the margin; it is total forfeiture triggered by a single refunded
ticket.

**Every reduction route is closed.** Seven attempts, all refused *as the table owner*: append-only
UPDATE and DELETE; `23505` on a compensating line; a `commission_reversal` cause rejected by
`settlement_line_cause_check`; a payout reduction and a negative payout both rejected by
`payout_amount_minor_check (> 0)`; and a re-close returning `noop_replay`.

---

## 3. THE CONSERVATION EQUATION — AND WHERE THE 10 WENT

The crux of G4 is arithmetic, not narrative. Case D, executed:

```
+10 000 collected  − 9 000 venue paid  − 10 000 refunded  =  −9 000 cash gap
plus a 1 000 obligation recorded, HELD, never disbursed

exposure R = 10 000
R = venue clawback 9 000 + commission obligation extinguished 1 000
```

**The 1 000 is not somewhere else — it never left.** Because the commission was funded as a reduction of
the venue's distributable, the platform retained it at the close. Voiding a held commission collects
from nobody; it simply returns the platform's own retained cash.

So:

- **the venue owes 9 000, because it received 9 000** — never 10 000. Charging it the full face would
  bill it for commission money it never held.
- **the promoter owes nothing, because it received nothing.**
- **no double-debit, and no promoter receivable is required** — precisely because FUNDED ≠ PAID.

Had the commission been *paid*, the gap becomes 10 000 and a genuine promoter clawback exists. **Neither
term is representable in the schema today.**

---

## 4. OPTIONS

| | Option | Assessment |
|---|---|---|
| **1** | Funded commission is FINAL; platform absorbs | Today's state plus a decision. Worst fraud posture: a reversal after close leaves the promoter's claim intact against revenue that no longer exists. |
| **2** | Reduce PRO RATA on reversed revenue | Economically correct. **Not representable today**: see §5. |
| **3** | Void only on FULL reversal | Cheap, but inherits the binary blindness that makes case B wrong — a partial reversal leaves a fully-funded commission. |
| **4** | Commission becomes a promoter receivable if already paid | **Nonsense for held money and mandatory for paid money.** No commission payout has ever left `pending`, so it is inert today — and it cannot be retrofitted after the first release. |
| **5** | Remains HELD until a maturity condition passes | Representable **with zero DDL** — the hold, the predicate function and the release verb all already exist. |
| **6** | Hybrid | Option 5 now, option 2 evaluated at release. |

**Options 5 and "2-at-release" are the only ones representable with zero new schema.**

**Do not extend the pre-close model.** It keys on order *status* — a binary — whereas the post-close
question is an *amount*. Extending its shape is what produces case B's total forfeiture. Extend its
timing intuition, not its mechanism.

---

## 5. THE ONE ENGINEERING CONSEQUENCE

Under anything except option 1, **releasing less than the funded amount is currently inexpressible.**
`kernel.payout.amount_minor` carries `CHECK (> 0)` and release is all-or-nothing.

The smallest sufficient change is **one verb** — a partial release, or a void-and-remint — **not a new
money table**. That is a materially smaller ask than G5's, and it is only needed once a reduced
commission is actually payable.

---

## 6. RECOMMENDATION

**Option 5 for launch, with the reduction question decided before the first release.**

The reasoning is that option 5 costs nothing, changes nothing, and is already the machine's behaviour —
so adopting it is a decision to keep a safe state rather than to build one. It also preserves every
option: while the money is held, any of 1, 2 or 3 remains available. The moment a commission is
released, only option 4 remains, and option 4 needs schema that does not exist.

**This ruling deliberately does not decide what the promoter is owed.** That is a commercial
relationship question — what a promoter is *told* when the sale they drove is reversed — and the four
options differ in what you say to them, not merely in how the ledger is shaped.

---

## 7. THE OWNER QUESTION

`E-138` / `COMMISSION_FUNDING_SOURCE` ratified **where the money comes from** and lists refund,
chargeback and cancellation behaviour as obligations to "eventually prove". It decides none of them.
`PROMOTER_COMMISSION_PAYOUT_HOLD` remains open. **This is unratified.**

> Commission funded, settlement closed, revenue reversed, commission still HELD.
>
> **(i)** Is the promoter owed the **full funded amount**, the **pro-rata surviving amount**, or
> **nothing**?
>
> **(ii)** Does the answer change once the commission has been **PAID**? If yes, the receivable object
> must be specified **before the first release**, because it cannot be retrofitted onto money already
> gone.
>
> **(iii)** Does a reduced commission return to the **venue**, or stay with the **platform** — which is
> the party actually holding it?

Question (iii) is easy to overlook and is where the money actually is: the platform retained the
commission at close, so "reducing" it is a decision about whether the venue's distributable should have
been larger all along.

---

## 8. OWNER APPROVAL TEXT

> **G4 — FUNDED COMMISSION ON REVERSED REVENUE**
>
> While a promoter commission is FUNDED but HELD, the policy is: ______________________________
> (1 final / 2 pro-rata reduction / 3 void only on full reversal / 5 remain held pending maturity).
>
> A reduced or voided commission accrues to: ______________________________ (venue / platform).
>
> It is recorded that no promoter commission payout has ever left `pending`; that containment is four
> independent locks rather than a single flag; that a pre-close partial refund currently forfeits 100%
> of what the promoter earned; and that once a commission is PAID, only a promoter receivable can
> correct it — an object that does not exist and cannot be retrofitted.
>
> **No promoter commission payout may be released until this ruling is signed.** This is a precondition
> of promoter payout only. It does not gate selling, settlement, or venue payout.

---

**Status of this train's work against G4: accounting only.** Nothing in migrations 094 or 095 releases,
unholds or advances a `promoter_commission` payout. Verified after three closes, three obligation
bookings and a resolution: a held `unfunded_settlement` commission payout is byte-identical, and no 094
verb body can even name a promoter.

---

## OWNER DIRECTION RECEIVED 2026-09-03 (unsigned)

**This ruling is still unsigned; §8's blanks are still open.** Owner direction is guidance for what to
build against §4's options and §7's question, not an answer to either.

**Direction received.** Promoter commission remains **HELD at launch** — no release, no payout, under
any circumstance this train. Reversed revenue does **not** automatically leave the full commission
earned (ruling out §4 option 1, "funded is final," as the default the train should build toward). The
eventual surviving-commission policy — §7 question (i): full / pro-rata / nothing, and question (ii)'s
behaviour once PAID — is to be decided **before the first commission release**, not before this train.

**What migration 098 does: pre-close pro-rata FUNDING only.** It replaces §4's "full-or-nothing" funding
amount (10e's total exclusion, the mechanism behind case B's 100% forfeiture in §2) with a pro-rata
basis over the order's settled refund share (§6 option O2's shape): a partial refund funds a
proportionally reduced commission line instead of zero. **Disputes are included alongside refunds under
the same face cap** — a lost or `charge_refunded` dispute pre-close counts as reversed revenue for
funding purposes, capped at `least(disputed, face − refunded − prior_cb)`, so a commission is never
funded twice against the same reversed money (`docs/phase2/_impl/KF_promoter_prorata.md` §4.4). For
`flat_per_ticket` promoters, the **flat-per-ticket rule (a)** applies —
`floor(surviving_face / unit_price)` per item — the reading closest to the frozen "surviving items"
wording (`KF_promoter_prorata.md` §4.5), rather than pro-rating the flat amount (b) or excluding flat
promoters from the fix entirely (c). This is a **post-freeze amendment of PROMO §6.1/§5.2's basis**, not
a correction the frozen corpus already determines on its own — filed as **`PFA-PT-4`, pending owner
signature**. Migration 098 is dark pending that signature: shipping the basis change without it would be
the "silent edit around a conflict" the freeze procedure forbids.

**What migration 098 does NOT do.** It does not release a commission, does not pay one, and does not
touch a **post-close** reduction — the defect §1–§3 of this ruling describe (a funded commission standing
against revenue reversed *after* the close that funded it) is untouched; 098 only changes what gets
funded going forward, at the pre-close funding moment. A4's four locks (§1) are unmodified. `E-138`
(funding source, Option B) is unmodified. `kernel.release_payout` is still never called on a
`promoter_commission` payout by anything in this train.

**Addition to question (iii).** The obligation-overstatement finding sharpens question (iii) rather than
answering it: when a chargeback (or full refund) is booked against the organization post-close, the
`organization_obligation` amount is currently booked at the **full reversed face**, but the venue only
ever received `face − held commission` — the commission sits `held/unfunded_settlement`, untouched by
the reversal path, so the org is being asked to answer for money it never held
(`docs/phase2/_impl/KC_chargeback_accounting.md` §2.i, P1-3: obligation booked 10 000 vs. venue actually
received 9 000, overstated by the 1 000 the platform itself retained;
`docs/phase2/_impl/KF_promoter_prorata.md` P1-3, same finding, option O3). This is not fixed by 098 (098
only touches pre-close funding) and is not fixed by 096/097 (096/097 record and ring-fence recovery of
whatever amount the obligation is opened for — they do not choose that amount). **It is squarely
question (iii):** a reduced-or-still-held commission is money the platform is holding, not the venue —
so until (iii) is answered, every post-close obligation booked against this organization is booked
`held-commission` too high, and the fix (booking `organization_obligation` net of the funded-and-held
commission on the reversed orders, so it equals what the venue actually received) is DDL-free but is
squarely the policy question (iii) already asks, not a separate implementation decision.

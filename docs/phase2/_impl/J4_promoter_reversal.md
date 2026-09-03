# J4 — Promoter reversal economics (ruling G4), proved by independent execution

**Scope.** What happens to a promoter commission when the revenue that funded it is reversed.
Analysis and measurement only: no migration, slice, test or code byte was changed, no production
object was touched, no Stripe call was made, and **no `promoter_commission` payout was released,
unheld or advanced by anything in this work.**

**Method.** A fresh full replay — `scripts/rehearsal_reset.sh snatchit_rehears_g4`, 113/113 applied,
GATE-2 `tables=27 functions=70 policies=37 triggers=26` (the CI baseline) — against source tip
`09e167f` on `feature/venue-native-and-product-v2`. A fixture built from scratch (org `G4 Co` →
venue `G4 Hall` → eight events A–H, one aged session each; promoter P org-wide `bps 1000`, vanity
code `G4CODE`; a second promoter Q for case H; `payout.settlement_maturity_interval = "7 days"`).
Every order runs through `venue.finalize_primary_order`; every settlement through
`venue.open_settlement` + `kernel.close_settlement`; every refund through `kernel.admin_refund` +
`kernel.mark_refund_state`; every venue payout through `kernel.request_org_payout` +
`kernel.mark_payout_transfer_state`. Nothing was mocked.

Fixture-only pokes, each isolated to a helper and none of them a code path: session ageing
(`g4.age_session`), `catalog.platform_config` written as the table owner rather than through the
dual-controlled RPC (`g4.cfg`), and the org's Connect destination + capability flags written
directly (they arrive from a Stripe webhook this harness cannot run). Every economic result below
came out of the shipped functions.

**This is an independent reproduction of the defect `H5_promoter_economics.md` §6 reported. It
confirms the defect, corrects one of H5's secondary findings as now CLOSED, corrects the exposure
figure, and adds one finding H5 did not have.**

---

## 0. Verdict, up front

1. **The defect is real and reproduces exactly.** A commission funded into a closed settlement
   cannot be reduced by any means. Seven independent reduction attempts, all refused by the
   database itself (§3, case C). There is no reduce verb, no void verb, no reversal cause, no
   negative obligation and no receivable object anywhere in the schema.
2. **H5's 79% is a fixture artefact, as H5 itself said.** My own adversarial fixture yields
   **75%** over the same class. The figure that is *not* an artefact is the per-attribution bound:
   over-funding reaches **100% of the funded commission** on a full post-close reversal, and it did
   so three times out of three (cases C, D, E).
3. **The exposure runs in BOTH directions, and only one direction has ever been counted.** The
   pre-close exclusion under-pays the promoter by **100% of what they earned** on a partial refund
   (case B: earned 600, funded 0). H5 measured this number and read it as containment; it is also
   an exposure, pointing the other way, and it is the reason the pre-close model must not be
   extended post-close (§5).
4. **H5 §7.1 is CLOSED at this HEAD.** The G2 maturity gate is no longer a close-time snapshot: it
   was extracted into `kernel.settlement_payout_maturity` and is re-derived in
   `kernel.request_org_payout` and `kernel.get_payout_execution_context`. Measured: a settlement
   whose event is cancelled *after* the close now reports `event_cancelled` and the venue payout is
   held (§3, case F). It does nothing for the commission, which the gate does not cover.
5. **NEW, not in H5 — the venue can be paid in full for revenue that was 100% reversed, and the act
   of booking the reversal is what unblocks it.** See §4. This is a venue-side overpayment, not a
   promoter payment, so it is not the P0 this train forbids — but it is the other half of the
   conservation failure and it belongs to whoever owns the payout executor.
6. **Nothing in this train can pay a promoter, and I proved it four ways rather than one** (§6),
   including by actually exercising the Control-5 release verb — which H5 deliberately did not.
   Even a released commission payout cannot move.

---

## 1. The three structural facts, re-derived from the live database

| fact | evidence (queried, not read) |
|---|---|
| commission is a **negative, non-refund** settlement line ⇒ it lands in **FEES** and is subtracted before the org payout exists | `settlement_waterfall_ck CHECK (status='open' OR net_minor = gross_minor - fees_minor - refunds_minor)`; `identity_holds = true` on all 12 settlements closed in this run |
| a payout can never be negative | `payout_amount_minor_check CHECK (amount_minor > 0)` |
| there is no reversal cause | `settlement_line_cause_check` admits 13 causes; none is a reversal. `payout_cause_check` admits 4; none is a reversal |

Option B holds mechanically: on every settlement in the run the org payout was minted at exactly
`max(net, 0)` and the venue never received the commission's dollars.

---

## 2. Case H first, because it collapses the problem space

**Multiple promoter codes / attributions on one order are structurally impossible.**

- `venue.attribution` carries `attribution_one_per_order UNIQUE (order_id)` — queried from
  `pg_constraint`, not assumed.
- A second attribution row written **as the table owner** is refused before it even reaches the
  unique index (`23502` on `touch_corroborated`, then the unique).
- `venue.bind_order_attribution` after the order is paid is refused (`attribution_frozen`).
- `venue.resolve_order_attribution` picks exactly ONE winner under the P0–P10 precedence table
  (code beats link) and records the loser only as `displaced_promoter_id` — a field, not an
  obligation.

Measured: **1** attribution row on `oH`. So there is at most one commission obligation per order,
the reversal question is always 1:1, and "splitting a reversal across promoters" is not a G4
problem — it does not exist. **This is the one case where the answer is that the question is
inapplicable, and it should be recorded as such rather than left open.**

---

## 3. The eight cases, measured

Every order is 2 × 5 000 = **10 000 face**, commission `floor(10 000 × 1000/10000) = 1 000`,
venue distributable **9 000**.

| # | case | settlement waterfall | commission line | commission payout | venue payout | verdict |
|---|---|---|---|---|---|---|
| **A** | full refund **before** close | `10000/0/10000 = 0` | **0** | **0** | 0 (net not > 0) | **correct** — no exposure either way |
| **B** | partial refund (4 000) **before** close | `10000/0/4000 = 6000` | **0** | **0** | 6 000, unheld | **promoter under-paid 600** = 100% of the 600 they earned pro rata; the venue keeps it |
| **C** | full refund **after** close, before venue payout | s_C1 `10000/1000/0 = 9000`; s_C2 `0/0/10000 = −10000` | −1 000 (immutable) | 1 000 held | 9 000 → **submitted, execution-eligible** | **over-funded 1 000 (100%)**; s_C2 mints nothing and creates no receivable |
| **D** | refund **after** venue payout | s_D1 `10000/1000/0 = 9000`; s_D2 `−10000` | −1 000 | 1 000 held | 9 000 **paid** | **over-funded 1 000 (100%)**; 9 000 left the platform and nothing claws it back |
| **E** | chargeback **after** venue payout | s_E1 `= 9000`; s_E2 `chargeback −10000` | −1 000 | 1 000 held | 9 000 **paid** | **over-funded 1 000 (100%)**; dispute 11 000 correctly capped to a −10 000 line (10h works: the 1 000 buyer-side fee is not charged to the venue) |
| **F** | event cancelled **after** close | s_F1 `= 9000`; `cancel_event` → `atoms_voided 2, refunds_created 1` (pending 10 000) | −1 000 | 1 000 held, **untouched** | 9 000, **now held `event_cancelled`** | commission over-funded 1 000; **the venue side is now protected — H5 §7.1 closed** |
| **G** | funded, never released (control) | `= 9000` | −1 000 | 1 000 held | 9 000 | correct funding; used for the containment battery (§6) and the guard experiment (§4) |
| **H** | multiple codes on one order | — | — | — | — | **structurally impossible** (§2) |

### Case C in full — the seven walls

Every attempt to reduce the funded 1 000 after the close, run **as the table owner** (a strictly
stronger caller than any client role):

| attempt | refusal |
|---|---|
| `UPDATE venue.settlement_line SET amount_minor = 0` | `P0001 append_only: settlement_line is immutable — UPDATE is not permitted` |
| `DELETE` the line | `P0001 append_only: … DELETE is not permitted` |
| INSERT a compensating **+1 000** line, same cause + cause_ref | `23505 settlement_line_cause_uq` (and `attribution_one_commission_line_ever` behind it) |
| INSERT a `commission_reversal` line | `23514 settlement_line_cause_check` — **the cause does not exist** |
| `UPDATE kernel.payout SET amount_minor = 0` | `23514 payout_amount_minor_check` |
| INSERT a **negative** offsetting payout | `23514 payout_amount_minor_check` |
| re-close the same settlement | `noop_replay` — forward-only |

And platform-wide: **0** negative payouts, **0** receivable-shaped tables. Σ negative net across
this run = **−30 000 minor units, carried by no object at all.**

---

## 4. NEW FINDING — the reversal guard is defeated by booking the reversal

`kernel.settlement_payout_maturity` treats a refund as blocking only while it is `pending` or
`submitted` (*in flight*). A refund that has **succeeded** after the close is not in flight, so the
maturity gate passes. The only remaining guard is `unbooked_refund_exposure_minor` in
`kernel.get_payout_execution_context`, computed as (succeeded refunds, capped at order total)
**minus** (`refund_void` lines already booked **in any settlement**).

Executed on event G, in order:

```
X0  before any reversal                     refusal = payout_not_submitted
X1  full refund of oG, post-close, settled  ok
X2  after the refund, before a 2nd close    stale_exposure = 10000   (the guard IS holding)
X3  request_org_payout(s_G)                 status = "submitted"     (the human gate does NOT object)
X4  close s_G2 — books refund_void −10000, net −10000, mints NOTHING
X5  after the second close                  refusal = NULL, stale_exposure = 0   ← GUARD DEFEATED
X6  claim_payouts_for_execution             returns the s_G payout: 1
```

Booking the reversal — the correct bookkeeping act — is exactly what clears the guard, because the
guard counts *lines written*, not *obligations discharged*. The debit lands in a settlement that
nets negative and therefore mints nothing, so the offsetting obligation is never created, and the
9 000 transfer against zero surviving revenue becomes executable.

Both branches are wrong: leave the reversal unbooked and the venue payout is stuck forever
(`refund_exposure_stale`); book it and the venue is paid in full for revenue it no longer has.

**Severity: HIGH. Not the P0 this train forbids** — it pays a venue, never a promoter — but it is
the same conservation hole seen from the other side, and it should go to the owner of the payout
executor. Recorded, not fixed.

---

## 5. Is the pre-close model the right shape to extend? **No.**

The pre-close seam excludes `refunded`, `partially_refunded` and `cancelled` orders — a deliberate
over-correction, because over-paying in an append-only ledger is unrecoverable. That reasoning is
sound. The *shape* is not portable.

The pre-close rule operates on an order **STATUS**. A status is binary, so the rule can only ever
produce 0 or full. Pre-close that is tolerable, because the alternative (over-paying) is worse.
Post-close the question is not "did something reverse" but "**how much** survived" — and a
status-based rule has no quantity in it.

Measured cost of the binary shape, at this fixture's scale:

- case B, pre-close partial: promoter earned 600, funded **0** → **100% under-payment**.
- cases C/D/E, post-close full: promoter earned 0, funded **1 000** → **100% over-funding**.

Extending the status rule post-close would convert every partial reversal into total forfeiture:
a 1-ticket refund on a 100-ticket order would extinguish the entire commission. The error would
grow from 600 to the full commission on every order that is ever partially touched.

**Extend the pre-close TIMING intuition (do not commit until the fact is terminal). Do not extend
its binary shape.**

---

## 6. Ruling A4, restated as a negative, proved harder than H5 proved it

Final payout census after eight cases, three refund cycles, a chargeback, an event cancellation,
four extra closes and a `noop_replay` re-close:

```
cause                | status    | hold  | reason              |  n | minor
---------------------+-----------+-------+---------------------+----+-------
promoter_commission  | pending   | held  | unfunded_settlement |  4 |  4000
promoter_commission  | pending   | none  | -                   |  1 |  1000   ← released ON PURPOSE, §6.1
settlement           | pending   | none  | -                   |  2 | 15000
settlement           | submitted | none  | -                   |  2 | 18000
settlement           | paid      | none  | -                   |  2 | 18000
```

Zero commission payouts carry a `stripe_transfer_ref`. Zero carry a `destination_ref`. Zero ever
reached `submitted` through any contracted path.

### 6.1 The release test H5 declined to run

H5 asserted containment as "nobody has released a hold." I released one, deliberately, to test
whether the hold is the *only* wall. It is not — there are three more behind it:

| probe | result |
|---|---|
| `kernel.release_payout` on a commission payout (platform_risk, Control-5) | `ok` — hold cleared, row now `pending / none` |
| `mark_payout_transfer_state(… ,'paid', …)` on it | **`P0001 precondition_failed: payout_state_backwards (pending → paid)`** — only `submitted → paid` exists, and nothing advances a commission payout to `submitted` |
| `kernel.claim_payouts_for_execution(50, 900)` | **`[]`** — filters `cause='settlement' AND payee_kind='organization' AND status='submitted' AND destination_ref IS NOT NULL` |
| `kernel.get_payout_execution_context` on it | **`cause_not_settlement`** |

And when the `submitted` state was forced directly **as the table owner** (a caller no client role
can be), the executor still returned `[]` and the context still refused `cause_not_settlement`.

**Conclusion, stronger than H5's:** the containment is not a single boolean. Releasing every
commission hold in the database would still pay no promoter. The funding leg is dark by four
independent mechanisms, and the release verb is not one of them.

---

## 7. The conservation test

    SALE 100 → PROMOTER COMMISSION 10 → VENUE DISTRIBUTABLE 90
    then REVERSAL 100 AFTER THE VENUE HAS BEEN PAID

This is case **D**, executed. In integer minor units (×100 of the narrative figures):

```
face F                    = 10 000
commission c              =  1 000   (bps 1000 on 10 000)
venue distributable N     =  9 000   = F − c        [measured: s_D1 gross 10000, fees 1000, net 9000]
venue actually PAID       =  9 000                  [measured: payout status 'paid']
commission actually PAID  =      0                  [measured: pending / held, no transfer ref]
reversal R                = 10 000                  [measured: refund succeeded, s_D2 refund_void −10000]
```

**Platform cash ledger:**

```
+10 000   buyer's payment collected at the sale
−  9 000   venue payout executed
− 10 000   refund returned to the buyer
─────────
−  9 000   platform cash gap
```

**Platform obligation ledger:** `− 1 000` promoter commission — **recorded, held, never disbursed.**

Total exposure = 9 000 cash + 1 000 standing liability = **10 000 = R exactly.**

### Who owes what, and where the 10 goes

```
R  10 000  =  venue clawback 9 000  +  commission obligation extinguished 1 000
```

- **The venue owes 9 000, not 10 000.** It received 9 000. Charging it 10 000 would bill it for
  commission dollars it never touched — the double-debit the brief forbids. Measured: the venue's
  payout was minted at `net`, and `net` was already `F − c`.
- **The promoter owes nothing.** It received nothing. There is no receivable to raise, because
  there was no disbursement to reverse.
- **The remaining 1 000 is not missing and it is not "somewhere else." It never left the
  platform.** The commission was funded as a *reduction of the venue's distributable*, so the
  platform retained those 1 000 minor units from the moment of the close. Voiding the held
  obligation does not collect from anybody — it releases the platform's own retained cash back to
  its free balance. The books close at 10 000 with no third party charged.

**This is the whole of G4, and it is arithmetic:** in the funded-but-HELD state the equation closes
exactly, with no receivable and no double-debit, *because FUNDED ≠ PAID*.

Contrast — the same reversal if the commission had been **PAID**:

```
+10 000 collected  − 9 000 venue  − 1 000 promoter  − 10 000 refund  =  −10 000 cash gap
recovery:  venue clawback 9 000  +  promoter clawback 1 000  =  10 000  ✔
```

Here the 1 000 *is* a genuine receivable, because the promoter is holding real money. **Only in
this world does a promoter receivable / negative carry have any referent — and this world does not
exist today.**

### Neither term is representable

The equation closes in principle. Measured, **neither side of it can be written down**:

- the **9 000 venue clawback** has no object — a negative net mints nothing, `payout.amount_minor`
  must be `> 0`, and there are 0 receivable-shaped tables;
- the **1 000 commission extinguishment** has no verb — the line is append-only, the cause set has
  no reversal member, a compensating line collides on a global unique index, and
  `kernel.payout.amount_minor` can be neither reduced nor negated.

---

## 8. The six options

The governing distinction: **an option that is correct for money already PAID is nonsense for money
still HELD.** Today the system has only the second.

| # | option | accounting correctness | what the promoter is told | effect on venue distributable | refunds / chargebacks | representable today? | owner decision? |
|---|---|---|---|---|---|---|---|
| **1** | **Funded is FINAL** | Coherent only once you name *who* absorbs. Today it is nobody: the obligation simply stands. | "You keep it." Strongest acquisition story. | None — already reduced pre-close. **No double-debit.** | **Worst case.** A promoter driving chargeback-heavy volume is paid in full on it. Classic affiliate-fraud vector. | **YES — zero DDL.** It is today's state plus a decision to release. | **YES.** A fraud-risk decision, not a mechanics one. |
| **2** | **PRO RATA on reversed revenue** | **Correct.** `owed = floor(surviving × bps / 10000)`. Matches case B exactly (600). | "You earn on what stuck." | Post-close, a reduction returns money to the **platform**, not the venue — unless the owner separately rules the venue gets it back. | Inputs exist: `refund.amount_minor`, dispute capped at face. | **As a durable ledger fact: NO** (all seven walls, §3). **At release time while held: YES, zero DDL** — recompute the surviving basis when the hold is lifted. | Mechanics derivable; **whether** the promoter earns pro rata is commercial. |
| **3** | **VOID only on FULL reversal** | Partly correct. Leaves a residue exactly the size of case B's 600 on every partial. | "You keep it unless the whole sale reverses." | None. | Silent on partials — the majority shape. | **At release time: YES, zero DDL** (a predicate: "is the order still `paid`"). As a ledger fact: no. | Yes, low-stakes. |
| **4** | **Promoter receivable / negative carry (if already paid)** | Correct — **for a state that does not exist.** | "You owe it back." | None. | The only correct answer once money has actually left. | **NO, twice over:** `payout_amount_minor_check (> 0)` forbids the negative leg; 0 receivable-shaped tables. And there is nothing to reverse — no commission payout has ever left `pending` (§6). | **YES — and it must be ruled BEFORE the first release, not after.** |
| **5** | **Remain HELD until a maturity condition passes** | The only option that is *already true*. It is the venue's own G2 model applied to the promoter: anchor at `max(event_session.ends_at) + interval`, plus "no refund succeeded on the covered payment since the funding close." | "Paid after the event settles and the refund window closes." Honest, and standard for affiliate programs. | None. | Converts *reversal* into *timing*. Does not fix a reversal landing after maturity, but shrinks it from the whole surface to a tail. | **YES — zero DDL.** The hold exists, `kernel.settlement_payout_maturity` exists, `kernel.release_payout` exists. What is missing is a release-time predicate for `cause='promoter_commission'` — a function body, not a schema change. | Duration is policy; mechanism is derivable. |
| **6** | **Hybrid** | See below. | | | | | |

### The hybrid the arithmetic actually points at: **5 + 2-at-release**, with 4 held in reserve

- Keep the hold (5). It is what makes §7's equation close with no receivable and no double-debit.
- At **release** time, pay the pro-rata surviving amount (2), computed then rather than at funding
  time. No new cause, no new object, no amendment of a closed line: `venue.settlement_line` remains
  an honest record of what was *funded*, and the payout is released at or below its face.
- Reserve (4) for the day money actually leaves, and rule it *before* that day.

**One engineering consequence must be stated precisely, because it is the smallest possible ask and
it is unavoidable under any option that is not (1):** releasing *less* than the funded amount is not
expressible today. `kernel.payout.amount_minor` cannot be reduced (`> 0` CHECK blocks 0 and blocks
a negative), and `kernel.release_payout` is all-or-nothing. So even the cheapest correct hybrid
needs **one** of: a partial-release verb, or a void-and-remint pair. That is the entire DDL/verb
surface implied — one verb, not a new money table — and it is worth putting in front of the owner
alongside the policy, because the policy choice determines whether it is needed at all.

---

## 9. Exposure, corrected

| scope | funded | earned (pro rata) | over-funded | % |
|---|---|---|---|---|
| **post-close reversal class** (C, D, E, F) | 4 000 | 1 000 | **3 000** | **75%** |
| all funded commission in this run (C–G) | 5 000 | 3 600 | 1 400 | 28% |
| **pre-close class** (A, B) | 0 | 600 | **−600** | promoter **short 600** |

**H5 reported 79% (3 800 / 4 800). I measure 75% (3 000 / 4 000) on an independently-built
fixture.** Both are artefacts of how many adversarial cases the fixture contains — the ratio is set
by the mix, not by the system. The figures that are *not* artefacts:

- **per-attribution over-funding is bounded above by the funded commission, and reaches 100% of it
  on any full reversal** — three for three (C, D, E);
- **per-attribution under-funding reaches 100% of the earned amount on any partial pre-close
  refund** — one for one (B);
- **aggregate over-funding is unbounded in time**, because nothing ever reduces it and orders never
  return to `paid`.

The four reversal shapes exercised — post-close full refund, post-close partial refund (case B's
mechanism applied after a close), post-payout chargeback, post-close event cancellation — are three
quarters the ordinary life of a ticketing business, not edge cases.

**Severity: HIGH in principle, CONTAINED in practice** — and the containment is now measured as
four independent locks (§6), not one boolean.

---

## 10. The owner boundary

**The corpus has NOT ratified this.** What it ratified, on 2026-09-02 (`POST_FREEZE_AMENDMENTS.md`
E-138 / `COMMISSION_FUNDING_SOURCE`), is Option B: **where the money comes from** — primary ticket
revenue → promoter commission liability → venue distributable settlement, funded before venue money
leaves. That entry lists "refund behaviour · chargeback behaviour · cancellation behaviour · the
held-payout release condition" among the things the implementation "must eventually prove." It
names them as obligations. It does not decide any of them.

`PROMOTER_COMMISSION_PAYOUT_HOLD` remains an explicitly OPEN forward obligation in the same
register. So the reversal policy is **unratified**, and Claude may not choose it: what a promoter
is owed when the sale they drove is reversed is a commercial relationship question, not a
mechanical one.

### The question, in the form it needs to be asked

> **A promoter commission has been funded out of a settlement that has since closed. The revenue
> under it was then reversed — refunded, charged back, or the event cancelled. The commission has
> NOT been paid: it is a held obligation, and the platform is still holding the money. The ledger
> cannot amend the line and cannot reduce the payout.**
>
> **(i) What is the promoter owed?**
>  **(a)** the full funded amount — the platform absorbs the reversal;
>  **(b)** the pro-rata commission on revenue that survived (0 on a full reversal, 600 on case B's
>  4 000-of-10 000 refund);
>  **(c)** nothing at all once any part of the sale reverses — the pre-close over-correction,
>  extended.
>
> **(ii) Does the answer change once the commission has actually been PAID?** If yes, the
> receivable/negative-carry object (option 4) must be specified **before the first release**, not
> after — it is the only option with no representation today and it cannot be retrofitted onto
> money already gone.
>
> **(iii) Where does a reduced commission go — back to the venue, or retained by the platform?**
> §7 shows the platform is the party holding it. Returning it to the venue is a second,
> independent commercial decision and 093 does not imply it.

**Blocking status.** Not blocking for any migration in this train: A4 holds every commission and no
path pays a promoter (§6). **Blocking for the first release of a commission hold** — that sentence
belongs in the activation matrix, and (ii) above should be answered in the same ruling, because the
day a promoter is first paid is the day option 4 stops being hypothetical.

---

## 11. Secondary findings (recorded, not fixed)

1. **§4 — the refund-exposure guard is cleared by booking the reversal.** HIGH; venue-side, not
   promoter-side. Owner: the payout executor.
2. **`settlement_payout_maturity` treats only `pending`/`submitted` refunds as blocking.** A refund
   that has *succeeded* since the close is not "in flight" and does not hold the venue payout.
   Measured: `request_org_payout(s_G)` returned `submitted` with 10 000 of settled refund exposure
   standing against it.
3. **`record_dispute_native`'s payout-freeze leg is structurally unable to reach a commission
   payout** — its `cause_ref` is an attribution id, never a settlement id. Confirmed live (case E):
   the commission payout acquired no `dispute` hold. This is the open
   `PROMOTER_COMMISSION_PAYOUT_HOLD` obligation, re-confirmed rather than assumed.
4. **`catalog.cancel_event` does not touch `kernel.payout` at all** (case F). The commission payout
   was byte-identical before and after. The venue payout is now protected by the re-derived
   maturity gate; the commission is not.
5. **`kernel.release_payout` takes no reason argument** and clears any hold. Combined with §6.1,
   releasing an `unfunded_settlement` hold is a one-way door that no predicate re-evaluates — which
   is precisely why option 5 needs its release-time predicate written *before* the verb is ever
   pointed at a commission payout.
6. **The 10h chargeback cap works.** Dispute recorded at 11 000 (10 000 face + 1 000 buyer-side
   fee); the settlement line was **−10 000**. The platform's own fee was not charged to the venue.

---

## 12. Reproduction

```
scripts/rehearsal_reset.sh snatchit_rehears_g4
# then, in order: the fixture, cases A/B/G/H, cases C/F, cases D/E, the proof battery,
# the §4 guard experiment, the §6.1 containment battery
```

Fixture shape: org `G4 Co` → venue `G4 Hall` → events A–H (one session each, aged 10 days into the
past); promoter P = `g4prom@t.local`, org-wide, `bps 1000`, vanity code `G4CODE`; promoter Q for
case H; `payout.settlement_maturity_interval = "7 days"`;
`payout.dual_control_min_minor` lifted so a 9 000 venue payout advances without a parked approval.
Per-event signing keys inserted as the owner (the KMS ceremony is out of scope here).

**No migration, slice, test or application byte was changed by this work. No git commit was made.**

# V3 Package 7 — app-wide copy and hierarchy correction

**B → C · 2026-09-23. The freeze is reopened for this.** Ordinary copy simplification across all six
packages is authorised without a further approval round. **No payment rule, fee, bidding behaviour or refund
semantic changes.**

This package supersedes earlier package text wherever that text caused the clutter — including the
requirement to repeat amounts in button labels.

**Delivered incrementally.** Each increment is a commit listed in `V3_HANDOFF_INDEX.md` so C implements in
parallel rather than waiting for the whole sweep.

---

## 1 · The seven rules, as I am applying them

| # | Rule | Operational test |
|---|---|---|
| 1 | Delete text that narrates a visible control | If the sentence would still be true with the words removed, because the control shows it, delete it |
| 2 | Consolidate repeated amounts, statuses, dates, instructions | Every figure appears **once**, in the unit its label names |
| 3 | Each screen has a clear purpose and next action | The largest element is the thing the screen is for |
| 4 | Keep price, quantity, consequence, uncertainty, deadline, recovery | These are never cut. Cutting an uncertainty is lying by omission |
| 5 | Keep explanations **beside** the action | Nothing moves into a tooltip or accordion to make a screenshot look tidier |
| 6 | No developer explanations on customer screens | Field names, RPC names, status enums and my own annotations stay on the boards, never in the app |
| 7 | No artificial whitespace or decoration in the gap | Space left by a deletion goes to the control the screen exists for, or stays as an honest section break |

**Where the clutter came from.** Most of it is **mine**. The release source is in several places terser than
my V3 revision of it. Where that is true I say so in the ledger, because C has already implemented some of my
additions and needs to know they are being withdrawn, not refined.

---

## 2 · Bid entry — delivered

**Artifacts:** `pkg7-bid-comparison.png` (before / after / after-raised, with the ledger) ·
`pkg7-bid-after.png` · `pkg7-bid-after-raised.png` · `pkg7-bid-after-annotated.png`.
**Before** is C's actual implementation at `v3/midnight-app` @ `debb1b98`, not a straw man.

### What the screen now is

Event identity and quantity → **current bid, once** → **the editable bid, as the screen's centre** →
**service fee, once** → **one payment condition** → **total beside `Place bid`**.

### Removed — 8 lines

| Removed | Why |
|---|---|
| Big central total + *"your total if you win"* | A headline that changed when you pressed a control that moves something else. The stepper's value is the headline now |
| *"Your bid"* comparison column (all-in) + its caption | The same figure as the stepper, one block away |
| *"all-in · $90.00 bid + fee"* on the current column | Explains a figure that no longer needs explaining — the column is a plain bid again |
| *"Lowest you can place is $104.50 all-in"* | A second minimum in a second unit |
| **"Steps raise your bid. The fee and your total follow."** | Narrates a visible control. Deleted outright, per the ruling |
| Breakdown row *"Your bid $95.00"* | Third appearance of the bid |
| Breakdown row *"You pay if you win $104.50 total"* | The total belongs beside the button that commits it |
| *"· $104.50 all-in"* in the button label | **The release source ships `Place bid` alone.** The suffix was my own O-2 addition |

### Replaced — 1 line, for accuracy

> ~~"Only charged if you win the auction."~~ → **"You're not charged now. If you win, you'll come back to pay."**

**Winning does not charge anyone.** `detailState` gives the winner `pay_now`, which only opens
`/checkout/{id}`; the charge happens there under `Pay $104.50`. The old sentence implied the charge follows
automatically from winning. Both facts the buyer needs — no charge now, and a return trip to pay — are kept, in
one sentence.

### The minimum is now contextual

| State | Hint |
|---|---|
| At the floor (`−` inert) | **"Minimum $95.00 · $5 steps"** |
| One step up or more | **"$5 steps"** |

Validation is unchanged: `canPlaceBid` still refuses, and the shipped alert still reads
*"Bid too low / Minimum bid is $95.00."*

### Every figure, once

| Figure | Where it now lives | Appearances before |
|---|---|---|
| `$90.00` current bid | one line, in bid terms | 2× |
| `$95.00` your bid | the stepper value — the control itself | 3× |
| `$9.50` service fee | one line | 2× |
| `$104.50` total | beside `Place bid` | 4× |

**The space freed went to the bid control** (larger amount, larger stepper and quick-add keys) and to
anchoring the money block directly above the action, so the screen ends on one complete statement:
fee → total → `Place bid`. On a viewport too short for slack the block falls back to normal flow.

### O-2 is withdrawn — C must change implemented code

`PlaceBidScreen.tsx` on `v3/midnight-app` currently reads
`label={`Place bid · ${lines.total} all-in`}`. **Revert the label to `Place bid`.** The sticky bar's
`left` slot already carries the total; relabel its kicker from *"If you win"* to **"Total if you win"** so the
figure is self-describing without the button repeating it.

Also on that file: remove the `compareSub` all-in captions, the `bigAmount`/`stepHint` total headline, the
`Lowest you can place is …` line, the `Steps raise your bid…` line, and the breakdown's bid and total rows.
**`lines.bid`, `lines.fee` and `lines.total` stay as they are — no money maths changes.**

---

## 3 · What is NOT being cut anywhere

- Price, quantity, and which listing you are acting on.
- Any statement of **uncertainty** — *"We couldn't check your reservation."*, *"We can't confirm the refunded
  amount here."* and the rest of `holdState` / `STATE_COPY`. A short screen that hides a doubt is worse than a
  long one that states it.
- **Deadlines** and what happens when they pass.
- **Recovery** — what to press, and where a blocked action's exit is.
- Any refund, payout or transfer wording already constrained by the owner's earlier rulings.

**Rule 4 outranks rules 1–3 whenever they collide.**

---

## 4 · Listing detail and checkout — delivered (increment 2)

**Artifacts:** `pkg7-listing-checkout-comparison.png` · `pkg7-listing-after.png` ·
`pkg7-listing-after-annotated.png` · `pkg7-checkout-after.png`.

### Listing detail — 5 lines removed, `$104.50` from 4 appearances to 1

| Removed | Why |
|---|---|
| *"IF YOU BID THE MINIMUM $104.50"* header | A total for a bid the buyer has not chosen yet |
| Breakdown: *Tickets $95.00* · *Service fee $9.50* · *Your total if you win $104.50* | Three rows pricing an imagined bid. The bid screen owns that arithmetic, and the fee is itemised there and again at checkout — both **before** any commitment |
| *"The current bid is $99.00; the lowest you can place is $104.50 all-in."* | Both figures were already on the screen: one in the panel, one on the button |
| *"all-in,"* on the Buy now line | The panel caption says it once; *"ends the auction"* is the consequence that earns the line |

**Kept:** *"A bid is a commitment. If you win, you come back to pay."* — the part no control can show, now the
same sentence as the bid screen.

**Added — a coverage gap, not a decoration.** `BidActivity.tsx` has always rendered on this screen and **my
earlier boards never drew it**. The removed breakdown did not leave a hole; bid activity is what occupies that
space in the app. It is now drawn with its shipped shape: *"Bid activity"*, then name / time / amount rows with
**LEADING** on the top bid, and *"No bids yet · Be the first to bid on this one."* when empty.

| Figure | Where it now lives | Before |
|---|---|---|
| `$99.00` current bid | the price panel | 2× |
| `$104.50` minimum | under `Place a bid` | 4× |
| `$132.00` buy now | on the Buy now control | 1×, unchanged |

### Checkout — 1 duplicate figure removed

`$132.00` appeared **three times inside one 86pt band**: the breakdown total, the sticky `TOTAL` kicker, and
the button. **The kicker is deleted.** The breakdown stays — that is arithmetic, not repetition, and it is the
only place a Buy Now fee is itemised. `Pay $132.00` is untouched.

### The rule this settles

> **A control's label names an amount when pressing it moves that amount.**

`Pay $132.00` charges, so it names it — and `payControl.ts` is on C's gated surface, so leaving it alone also
means **no gated file changes**. `Place bid` does not charge, so the total sits beside it instead. The escrow
sentence stays: it is a consequence, not narration.

---

## 5 · Remaining surfaces — in progress

Delivered incrementally; each with a before/after and a ledger, each its own commit in
`V3_HANDOFF_INDEX.md`.

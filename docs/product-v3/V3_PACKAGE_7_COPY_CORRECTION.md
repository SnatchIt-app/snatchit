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

## 2b · Bid summary — the owner's final direction (2026-09-23), delivered

**Artifacts:** `pkg7-bid-after.png` · `pkg7-bid-after-raised.png` · `pkg7-bid-after-annotated.png`.
**This supersedes §2 wherever the two differ.**

### The screen, top to bottom

Identity + quantity → **Current bid $90.00** → the editable bid (stepper, minimum hint, quick-add) →
**one commitment sentence** → **the three-row summary** → **`Place bid`**.

### The summary — exactly three rows, nothing else

| Row | Weight |
|---|---|
| Bid | `$95.00` |
| Fee (10%) | `$9.50` |
| **Total** | **`$104.50` — visually strongest, above a rule** |

All three derive from the existing calculation and move with the stepper. **The bid appears here a second
time deliberately**, per the owner's instruction. Nothing else goes inside the block: no fourth figure, no
*"all-in"* caption, no explanatory sentence.

### What was removed

| Removed | |
|---|---|
| The sticky **"Total if you win"** amount beside the button | The summary's Total is the only total |
| The isolated service-fee row | It is now the summary's second row |
| The large empty gap | The bid control grew into it and the summary + button anchor the foot of the screen |

`Place bid` sits **directly below the summary**, full width, with nothing beside it.

### R-1 resolved — the reference is a bid, not an all-in

**`Current bid $90.00`** is the same unit as the stepper (`$95.00`) and the minimum. C's build showed
`Current bid · $110.00 all-in` against a `$105.00` stepper, which read as a *lower* bid. **Keep C's
`Starting bid` when `bid_count === 0`.** The fee and the final total are supplied by the summary.

### The commitment sentence — once, outside the summary

> **"A bid is a commitment. Nothing is charged now; if you win, you pay at checkout."**

Placing a bid charges nobody: the winner receives `pay_now`, which only opens `/checkout/{id}`, where
`Pay {total}` is the only charging control.

### For C

Preserve calculations, validation (`canPlaceBid`, the *"Bid too low"* alert), single-flight submission and
accessibility. The summary rows need their own labels so a screen reader reads *"Bid $95.00, Fee 10% $9.50,
Total $104.50"*. **Check small screens, large text and keyboard visibility** — with the summary and button now
sharing the foot of the screen, the keyboard must not cover either.

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

## 5 · Your order — delivered (increment 3)

**Artifacts:** `pkg7-order-comparison.png` · `pkg7-order-after-ready.png` ·
`pkg7-order-after-unreachable.png` · `pkg7-order-after-annotated.png`.

### Loaded — 5 lines removed

| Removed | Why |
|---|---|
| Panel heading *"The seller reported sending your tickets"* | Word for word the progress step directly above it. The panel keeps only the instruction — *"Accept the transfer in DICE, then confirm here."* — which nothing else carries |
| *"14:32 · screenshot attached by the seller"* in that panel | Time and attribution both live on the **Seller's screenshot** row. `14:32` was on this screen 3×; now twice — once as a progress step, once on the attachment it describes |
| *"by Sun 09:12"* under the **Your confirmation** step | The date moved to the sentence that says what happens when it passes. The step reads **"pending"** |
| *"where your tickets should be sent"* | Narrates the label above it |
| *"you'll confirm on the next step"* | **A judgement call, recorded as such** — see §7 |

**Kept verbatim:** *"Confirm when you have the tickets. If you don't confirm or report a problem by Sun 09:12,
payment is released to the seller automatically."* **This financial wording is still not approved (O-1 / B-4).**
Copy simplification does not touch it.

### Server unreachable — 4 lines removed, `14:36` from 5 appearances to 1

The owner's ruling was to **shorten the explanation while preserving the uncertainty and the
saved-information timestamp**. Both survive.

| Removed | Why |
|---|---|
| *"at 14:36"* in the panel body | The block header states the time once |
| *"as of 14:36"* on three rows | Five timestamps for one block, under a header that already governs every row |
| *"We'll show the current state when we can reach our server again."* | Narrates what **Try again** does |

**Kept:** the full uncertainty statement, *"…may be out of date — including the deadline."*, **"Deadline
shown"** rather than "Deadline" so the date is never authoritative, and the withdrawal of the confirm action
while the state is unknown.

---

## 6 · Search — delivered (increment 5)

**Artifacts:** `pkg7-search-before.png` · `pkg7-search-after.png`.

| Removed | Replaced with |
|---|---|
| *"Clear a filter to widen the search, or edit the words above."* | **"Try the venue name, or a shorter word."** |

The two controls directly beneath it are **Clear price filter** and **Clear all**, and the search field is
directly above. The sentence narrated all three. What replaces it is the shipped `STATE_COPY.noMatch` body —
advice the controls cannot give.

---

## 6b · F-28 and the dialog-copy review — delivered

**Artifact:** `pkg7-f28-marked-as-sent.png`.

### F-28 — four statements of one fact, corrected to three roles

| Before | After |
|---|---|
| Modal alert *"Marked as sent / You've marked this transfer as sent. The buyer still needs to confirm they received the tickets."* | **An inline `Text accessibilityRole="alert"` reading "Marked as sent"** — the app's own pattern, announced without a dialog to dismiss |
| Badge *"Marked sent"* | **Unchanged.** It is the status and it stays on screen |
| `StateBlock` title *"Marked as sent"* | **Removed** |
| `StateBlock` body *"Waiting for the buyer to confirm…"* | **Kept** — the forward-looking fact the badge cannot carry |

**Neither constraint is breached.** The accessible confirmation survives as an announcement rather than a
modal, and **every failure alert is untouched**.

**C verifies before this ships:** that the announcement fires once and is read by VoiceOver and TalkBack;
that `StateBlock` renders without a title — **if it requires one, keep the block titled and drop the badge
instead, not both**; that failure paths are untouched; and whether a sighted user still perceives the success
without a modal, which is a device judgement and not a static-image one.

### Dialog copy — reviewed, not exempt

All 23 listing and 22 selling dialogs re-read. **Most title/body pairs are not repetition** — a native
`Alert` takes a short title and a sentence, and the title heading its own body is the platform convention.

**Four are genuine (F-29)**, where the body restates the title and offers no recovery.

> **WITHDRAWN 2026-09-23.** I proposed *"You can place a bid instead."* for **"Buy Now unavailable"**,
> reasoning that `buy_now_enabled: false` means auction-only. **Checked against full action eligibility, it
> does not hold.** The Buy Now guard at `:766` fires *before* the ended/sold guard at `:768`, so the dialog
> can appear on a listing that has ended — and on a `continue_reservation` tap after a seller disables Buy
> Now, where `listingActions` offers no secondary at all. **Offering an action the screen does not have is
> worse than the echo it replaced.**

**All four keep their shipped copy.** The recovery is only correct when gated on `listingActions` yielding a
real `place_bid` for this viewer — a conditional body, which is **a logic change, not a copy change**, and it
belongs with F-27's functional recovery work. **Owner: C.**

**Destructive confirmations keep every word.** A CONFIRM dialog is the authorisation; shortening consent copy
is not simplification.

---

## 7 · The full sweep — every inventoried surface, checked

| Surface | Verdict |
|---|---|
| Bid entry | **Revised** — increment 1 |
| Listing detail · Checkout | **Revised** — increment 2 |
| Your order (loaded + unreachable) | **Revised** — increment 3 |
| Create listing · Send transfer | **Revised** — increment 4 |
| Search no-match | **Revised** — increment 5 |
| Home / discovery feed | **Checked, deliberate keep** — see §8 |
| My listings, 5 filters and 5 empty states | **No change** — each empty sentence says something different; only *All* offers an action |
| Bids tab, 10 row states | **No change** — the word is the state, the hint is the action; neither restates the other |
| Transfer matrix · dispute · report | **No change** — shipped copy verbatim, and every sentence is a consequence or a limit |
| Auth: 3 sign-in surfaces, 4 signup steps, reset | **No change** — see §8 on *"We text you a 6-digit code."* |
| Tickets · profile · public profile | **No change** — the uncertainty sentences (*"This is not a record of zero sales."*) are protected by rule 4 |
| Settings hub, notifications, 7 sub-surfaces | **No change** — shipped labels; the one wired toggle's failure sentence states what happened and what to do |
| All 23 listing dialogs + 22 selling dialogs | **No change** — shipped copy verbatim. Rewriting dialog copy is not a simplification pass; F-7 and F-25 are the defects to rule on |
| State screens (offline / error / noMatch / empty) | **No change** — `STATE_COPY`, shipped, and each states an uncertainty or a recovery |
| Error boundary · outbid notice · status banner | **No change** |

### Where the clutter actually came from — measured, not asserted

Sixteen strings were removed or replaced across the five increments. **Fourteen do not exist in the release
source at all** — they were introduced by my own V3 layer. Verified by `git grep` at `5b255838`.

**Only two touch shipped copy**, and both are flagged for C rather than assumed:

| Shipped string | Change | Why |
|---|---|---|
| *"Only charged if you win the auction."* (`PlaceBidScreen.tsx:316`) | → *"You're not charged now. If you win, you'll come back to pay."* | Winning does not charge anyone. The owner ruled the old sentence must not imply automatic charging |
| `StateBlock title="Marked as sent"` (`transferState.ts:162`) | title removed, body kept | The badge already reads *"Marked sent"*. **F-28** — and `StateBlock` may require a title prop, so **C confirms before implementing** |

**The app's own copy was mostly already lean. My V3 revision of it was not.**

---

## 8 · Genuine unresolved decisions

Three, stated plainly rather than buried:

**8.1 · "all-in" on every feed row — kept, against rule 2.**
The caption repeats on every row of home and search. Consolidating it into one header line would remove
4–5 repetitions from the busiest screen. **I kept it**: it labels the *unit* of a price, like a currency
symbol, and dropping it risks the exact misreading the all-in direction exists to prevent. Rule 4 outranks
rule 2. **If the owner prefers the header form, it is a two-line change** — say so and I will make it.

**8.2 · "We text you a 6-digit code. Your number is how you sign in from now on." — kept.**
Shipped. The first sentence arguably narrates what *Continue* does, but it sets expectations **before** the
user hands over a phone number, and the second is a real consequence. Cutting either weakens a step where the
user is giving something up.

**8.3 · "you'll confirm on the next step" — deleted, and it is a judgement call.**
Under *"I have my tickets"* on the order screen. It predicted the next screen rather than describing the
control, which is the narration class rule 1 names — but it also reassured a buyer that the tap is not final.
The next screen's own confirmation carries that. **Recorded here because reasonable people would disagree.**

---

## 9 · What C must change in already-implemented code

| File on `v3/midnight-app` | Change |
|---|---|
| `PlaceBidScreen.tsx` | `label={`Place bid · ${lines.total} all-in`}` → **`label="Place bid"`**. Sticky kicker *"If you win"* → **"Total if you win"**. Remove the `compareSub` all-in captions, the total headline + `stepHint`, the *"Lowest you can place is…"* line, the *"Steps raise your bid…"* line, and the breakdown's bid and total rows. Replace the charge sentence. **`lines.bid` / `lines.fee` / `lines.total` are untouched — no money maths changes** |
| Listing detail | Remove the *"if you bid the minimum"* breakdown; shorten the commitment sentence; drop *"all-in,"* from the Buy now line. **Draw `BidActivity` where the breakdown was — it already renders there** |
| Checkout | Remove the sticky `TOTAL` kicker. **`payControl.ts` is untouched** — `Pay {total}` stays, so no gated file changes |
| Create listing | Delete the review card; inline panel shows the buyer side only; keep *"after the seller fee"* |
| `transferState.ts:162` | Remove the `StateBlock` title, keep the body — **confirm `StateBlock` allows a title-less block first** |

**O-2 is withdrawn.** It was my direction, C implemented it faithfully, and the owner has now ruled against
it. Nothing C built was wrong at the time.

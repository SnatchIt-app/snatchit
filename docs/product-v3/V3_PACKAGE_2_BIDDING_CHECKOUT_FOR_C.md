# V3 Package 2 — discovery → bidding → checkout

**B → C · 2026-09-22 · ready to implement.** Read against release source `5b255838` and C's branch
`v3/midnight-app` @ `31819593`. No payment, reservation, refund or hold rule changes.

**Artifacts:** `pkg2-bid-entry-{clean,annotated}.png` · `pkg2-bid-entry-submitting.png` ·
`pkg2-checkout-{clean,annotated}.png` · `pkg2-checkout-states.png`.

Home, Search and Listing detail were approved earlier; this package adds **bid entry**, **checkout** and
**every checkout state the shipped logic can produce**.

---

## 1 · Bid entry (`/bid/[id]`)

The bid path is untouched: same fresh-floor fetch, same stepper and quick-add increments, same
`src/lib/money.ts` breakdown, same `bids` insert, same deletion guard.

**One number never means two things.** This screen had the same trap the listing screen was corrected for, and
I caught it by looking at the render rather than the code: a `$104.50` headline above a breakdown row reading
*"Your bid $95.00"*. Resolved as:

| Element | Shows | Why |
|---|---|---|
| Comparison, both columns | **all-in**, each with the bid beneath it — `$99.00 all-in · $90.00 bid + fee` vs `$104.50 all-in · $95.00 bid + fee` | the market and the commitment are comparable, and neither hides its base |
| Headline | **`$104.50`** + *"your total if you win"* | the big figure is always what the buyer pays |
| Stepper / quick-add | the **bid**, `$95.00`, labelled *"your bid"*, with `+$5 / +$10 / +$25` | the shipped controls and the shipped increments |
| Explanatory line | *"Steps raise your bid. The fee and your total follow."* | a $5 step lifts the total by $5.50; that is stated, not discovered |
| Breakdown | Your bid `$95.00` · Service fee (10%) `$9.50` · **You pay if you win `$104.50`** | shipped structure |
| Charge condition | *"Only charged if you win the auction."* | shipped sentence, verbatim |
| Submit | **`Place bid · $104.50 all-in`** → *"Submitting bid…"* | **already implemented on `v3/midnight-app`** |

**Already correct in C's branch:** `label={`Place bid · ${lines.total} all-in`}`. The submission control
reflects the selected bid and its fee-inclusive total, which closes O-2 on this screen.

**States drawn:** ready, submitting. **Alerts to dress** (all shipped, none reworded): *Not signed in* ·
*Bid too low — "Minimum bid is $X."* · *Bid failed* · *Account deletion pending — "Your account deletion
request is pending. Withdraw it in Settings to place new bids."*

---

## 2 · Checkout

| Element | Content |
|---|---|
| Listing | name in the display voice, date · time · venue, **`2 × GA · sold together`** |
| Breakdown | Tickets (2 × GA) `$120.00` · Service fee (10%) `$12.00` · **Total `$132.00`** |
| Escrow note | ***"Payment is held until your ticket reaches you. Secured by Stripe."*** — `ESCROW_NOTE_COPY`, verbatim |
| Payment method | the card row, reflecting whatever the payment sheet holds |
| Pay control | **`Pay $132.00`** |

`buy_now_price` is charged **once for the whole listing**, so the quantity sits next to the name and the total
is not per ticket. The all-in figure is the one the feed showed; nothing is added at this step.

---

## 3 · Every checkout state — `pkg2-checkout-states.png`

**All copy is the shipped vocabulary, verbatim.** Nothing here is invented.

**The pay control, 10 states in the code's priority order** (`payControl.ts`): Finalizing your order ·
Confirming payment · Checking your payment · Authenticating · Setting up payment · Checking your hold ·
Check again · Back to listing · **Pay {total}** · Try again · Payment unavailable.

> **Design decision, and a correction to my first draft: only `Pay` is red.** I first drew all eleven as
> primary buttons. A red block that cannot be pressed still reads as "pay", and two of those states appear
> **while money is already moving**. The six progress states are neutral status lines, the two retries and the
> back-out are secondary, and *Payment unavailable* is the one disabled resting state — disabled because there
> is genuinely nothing to press, not to discourage a tap.

**Priority matters and it is the code's:** a lost hold outranks a ready payment, and an unknown payment status
outranks both.

**The hold is gone — three reasons, three sentences** (`holdState.ts`): *Your hold was released* · *Your hold
ran out* · *This listing is no longer held for you*. Every one says **"Nothing was charged."** — a statement
about *this checkout*, which the client can make truthfully, not about any earlier payment. Keep the three
apart; collapsing them into one "something went wrong" loses the only useful part.

**Refund — status and amount are separate facts** (`REFUND_COPY`):

| Kind | Copy |
|---|---|
| `refund_unconfirmed` | **"Refund recorded"** / "A refund was recorded for this payment. **We can't confirm the refunded amount here.**" |
| `partially_refunded` | **"Partial refund recorded"** / "A partial refund of {amount} was recorded for this payment." |
| `refunded` | **"Full refund recorded"** / "A full refund of {amount} was recorded for this payment." |

**This is the product's own vocabulary and it is the model for every refund sentence in the app.** "Recorded",
never "issued" or "sent" — the app knows what its record says, not what a bank did. A refund can be recorded
with no confirmable amount, and that case gets its own sentence. Partial is first-class.

**This is also why the `expired`/`reversed` draft was corrected.** "Any refund is handled automatically" is
false the moment a partial refund exists, and the product already models partial refunds here. The revised
neutral copy is in `V3_FINDINGS_RECONCILED.md`.

**Two more sentences that refuse to guess:** *"We couldn't check your reservation."* and *"We couldn't check
whether this has already been paid."* Both say what the app could not do; neither says what is true of the
money. Keep them exactly as they are.

---

## 4 · Acceptance criteria

1. No figure on bid entry carries two meanings: the headline and both comparison columns are all-in, the
   stepper is the bid, and the relationship is stated on screen.
2. The submit control carries the selected bid's fee-inclusive total; in flight it says the tap was received,
   never that it succeeded.
3. Stepper increments and the minimum come from the shipped bid logic; the minus key is inert at the floor
   rather than hidden.
4. Checkout states the quantity next to the name and the total for the whole listing.
5. `ESCROW_NOTE_COPY`, `RESERVATION_UNVERIFIABLE_COPY`, `PAYMENT_STATUS_UNKNOWN_COPY`, the three hold-lost
   sentences and all three `REFUND_COPY` variants render **verbatim**.
6. **Only the `pay` state is red.** Progress states are neutral and non-interactive; retries and back-out are
   secondary; `Payment unavailable` is the one disabled resting state.
7. Pay-control priority is unchanged from `payControl.ts`.
8. No new refund, hold or payment capability; no sentence claims an outcome the screen cannot evidence.
9. Verified at the largest text size and the narrowest width, including the `StickyBar` stacked form below
   `STACK_WIDTH = 352`.
10. `typecheck` · `lint` · `test` green, real screenshots beside the boards.

## 5 · Still open for this package

- **O-1** — the automatic-release wording (order screen, Package 4), A + C.
- ~~**Listing-detail dialog set** — the `ActionKind` × role matrix and its 23 alerts is the remaining piece of
  the discovery flow.~~ **Delivered** in Package 6 and corrected at the freeze: the matrix is
  `pkg6-listing-action-matrix.png`, and all **23 call sites / 24 copy variants** are on
  `pkg6-listing-dialogs.png`. See `V3_FREEZE_RECONCILIATION_20260922.md`.
- Nothing in this package waits on A: every sentence used here already ships.

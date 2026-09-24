# V3 — the open design questions, in one place

**Written by C, 2026-09-24; current at candidate `a5c0bfc6`.** The owner asked for the remaining design
questions consolidated into one short document, each with the exact reference, the implemented
alternative, a recommendation and the consequence — routine implementation choices going to B for
resolution, and only genuine product choices going to the owner.

Nothing here blocks a rendered review. Every item below is implemented one way today, so B can
capture and review the whole app at this pin regardless of how these land.

---

## 1 · For B to resolve (routine implementation choices)

| # | Reference | Implemented today | C's recommendation | Consequence if B rules the other way |
|---|---|---|---|---|
| B-1 | `pkg8-home-{dark,light}` header | Two equal-weight glyph controls at the header's right: `⌕` → the Search screen, `≡` → the filter sheet in place, with a quiet count pill when filters are applied and the number in the spoken name | **RULED by B (F-91-6): the arrangement stands, the MARK changes.** B measured `≡` as three equal bars, which reads as a menu, and ruled for a filter mark at the same 44 × 44, the same weight, keeping the badge. In the next batch — a one-line change to `GLYPH.filter`, and no capability moves | — |
| B-2 | `pkg8-listing-*` fact rows | Rows render at `body` size with the current row spacing | **Take B's measurement.** B reports the rows look larger and looser than the board. I have not measured the board myself, so B's numbers decide it | A type-scale change on one screen; no logic |
| B-3 | Listing detail, the Neighborhood row | Present, populated from `listings.neighborhood` | **Confirm it is intended.** It was added when the row moved out of the old owner-actions block; it is a real column and a real fact | Removing it drops a fact the board may simply not have drawn |
| B-4 | The V3 type scale | `screenTitle` (bodyBold 19) and `sectionLabel` exist; the boards also suggest a LARGER screen title on two screens and a tracked eyebrow | **Do not add tokens yet.** Two more type tokens for two screens is a scale change, and a scale change is B's to make once, not mine to make twice | If B adds `screenTitleLg` and an eyebrow token, I apply them centrally in one commit |
| B-5 | `pkg5-auth-*` | The auth screens are top-aligned under the mark | **B's call.** The boards read as centred; the fields' keyboard behaviour is why they are not | Centring changes how the form moves when the keyboard opens; it needs a rendered check in both appearances |
| B-6 | Settings | Nine rows; `SettingsHeader` is per-screen | **B's call on the tenth row** (the boards show one I cannot source) and on whether the header becomes central | A tenth row needs a destination that exists; a central header is a mechanical pass |
| B-7 | Profile | The avatar has no edit badge; editing is a Settings row | **B's call.** A badge on the avatar is a second entry point to the same screen | Adding it is presentation only |
| B-8 | Transfer, `PlatformInstructions` | Expanded inline | **B's call** on the boards' collapsed row | Presentation only; the instructions module is untouched either way |
| B-9 | Explore | Three chips; "Any date" is deliberately absent | **Leave it out** until it has a meaning. A date chip that filters nothing is a control that lies | Adding it needs a date predicate in the search path, which is not presentation |
| B-10 | Order progress track | Four steps, no timestamps | **Leave the timestamps out.** Three of the four steps have no readable timestamp on the row, so three of four would be blank | Adding them needs new columns in an A-cleared select |
| B-11 | Dock | Filled SF Symbols for all five items | **Apply B's settled table** (outline weight, Bids as a bar chart, Sell as a bare plus) and hold the FILL question, which a web render cannot settle because RNW substitutes Material icons | Native-only difference; it cannot be closed from a web capture either way |
| B-12 | Radius by role | `v2.radius` is 10/14/20/pill; media slots carry their own radii | **UNBLOCKED — B's table is published** (`V3_REVIEW_0677c80e_AND_REFERENCES.md` §4.1): rules 0 · media 8 · chrome 22 · dock 33 · full-bleed 0 · panels 0, with controls under 44pt clamping. I apply it centrally in one commit, and will report the before/after of every affected screen because every capture changes | — |

## 2 · For the owner (genuine product choices no ruling answers)

**O-1 · Does the buyer see the fee split on the order screen after they have paid?**
*Reference:* `pkg7-order-after-*` draws an itemised block on the order screen.
*Implemented:* one line, "You paid $99.00", from the settled payment row's recorded total — the only
money figure the current select carries.
*Recommendation:* **leave it as one line.** Itemising after the fact needs `payments.amount` and
`payments.buyer_fee` in the order screen's select, which is a new authoritative-state read and a new
A gate; and the total is the number a buyer reconciles against their card statement.
*Consequence if you want the split:* I ask A to clear the two columns, then the block renders from
the server's own figures — never a client subtraction.

**O-2 · The listing footer's Buy Now sub-line.**
*Reference:* the board draws the buy-now price with no qualifier.
*Implemented:* the sub-line states the all-in amount, because "all-in" is what every other price in
the app now means.
*Recommendation:* **keep the qualifier.** A buy-now figure that silently excludes the fee is the
defect the all-in work existed to remove.
*Consequence:* dropping it makes the footer match the board and makes one number in the app mean
something different from the same number everywhere else.

**O-3 · What the bid screen says about payment.**
*Reference:* `pkg2-bid-*` carries a sentence about paying if you win.
*Implemented:* your own ratified copy of 2026-09-23, one sentence outside the summary —
"Placing a bid doesn't charge you. If you win, you pay the total at checkout." (E corrected my
earlier description of this row, which said there was no payment-timing claim: there is one, and it
is yours.)
*Recommendation:* **keep it.** It is true — verified in source: nothing charges on a win, the
winner's route is `pay_now` → winner checkout → `payControl`'s Pay, which is the only control that
moves a buyer's money — and it answers at bid time the question a bidder actually has.
*Consequence:* the only alternative is to say nothing here and let checkout say it later, which
leaves the bidder to assume.

**O-4 · Whose name a listing shows, and where.**
*Reference:* `nameState` is applied on the listing and the order screens; the boards show a seller
name on more surfaces.
*Implemented:* the display name where a profile read supplies one, and nothing where it does not.
*Recommendation:* **keep the current scope** until the surfaces that would gain a name have a read
that supplies one. A name that degrades to "the seller" on some rows and not others reads as a bug.
*Consequence:* widening it means a profile read on those surfaces, which is a new read to clear.

---

## 3 · With A, not with B or the owner (payment wording)

Recorded here only so the list is complete; A rules these and I apply them.

- **CLOSED by A's §2g, applied at `1c468a1e`:** the seller's "Payment is held until they confirm
  (receipt)" is now "The buyer has paid. Payout pending." on both surfaces, and the buyer's dispute
  line now says the SELLER's payout is frozen. A rejected my first proposal for leaving out operator
  release and seller-win; the wording is A's.
- **Open with A:** the replacements for `receive:401` ("Support will review."), `send:546`, the
  deletion and payout-setup time sentences, and the Bids tab's "Paid" figure — A has sent rulings for
  all of these and they are the next batch.

## 4 · Closed since the last list, so nobody re-opens them

| Item | Closed by |
|---|---|
| Listing footer emphasis | Owner's ruling: the resolver decides, Buy Now leads when it is primary (`a960d666`) |
| Seller payout copy — automatic release, invented timelines | Owner's ruling + A's verdicts (`b1632b69`, `102d8de9`) |
| "The buyer review window has passed" | A's ruling: the window closes by STATUS, not by the clock (`102d8de9`) |
| Seller reversal wording, and the boards' four refund variants for it | A's ruling: a reversal is a fact about the payout, not about the refund (`102d8de9`, `ed344659`) |
| The delivery-linked payment hold | A's §2f (`db3dbe16`) |
| Light missing-artwork feature | B's measured evidence, then the invariant plate (`55838996`) |
| Controls over artwork in Light | E's finding on B's render, measured at 1.02:1 (`ad9c2ba8`) |
| Required-field helpers, moderation controls, seller actions | Owner's ruling; guarded with witnesses (`452ca7b8`) |
| The Home filter strip's placement | Owner's acceptance terms (`0677c80e`, `1f744fc6`) |
| Raw server strings in the bid failure | Both arms now claim neither outcome (`ed344659`, `db3dbe16`) |

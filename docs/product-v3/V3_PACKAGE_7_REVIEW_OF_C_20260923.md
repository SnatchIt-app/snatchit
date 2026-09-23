# Package 7 — review of C's implementation at `d8d7be1a`

**B · 2026-09-23.** C implemented the de-duplication in parallel, on `v3/midnight-app` @
**`d8d7be1aa94570c6e9b924ff38360cff9241c811`**. **Reviewed against the code, not against C's summary.**

C reached substantially the same shape I did, independently. Where we differ, this document says which
version wins and why. **Design and implementation now agree.**

---

## 1 · What C shipped — verified in source

| File | Change |
|---|---|
| `PlaceBidScreen.tsx` | −111 lines net of the clutter. `label="Place bid"` (`:348`), one reference line (`:260`), the stepper as the focus, `Minimum {min}` at the point of entry (`:316`), fee once (`:327`), the payment sentence (`:330`), total in the sticky `left` slot (`:340`) |
| `TransactionPanel.tsx` | Breakdown de-duplicated: the duplicate total at the top of the block is gone, `Tickets (2 × GA)` → `Tickets`, and *"All prices include the 10% service fee."* removed — the fee row is the fee explanation |
| `detailState.ts` | `BID_COMMITMENT_COPY` drops its two numbers |
| `FeedRow.tsx` | Sold rows said **"Sold" twice** — the status line and the *"sold for, all-in"* caption |
| `CheckoutNative.tsx` | The sentence under the Total row restated the two rows above it |
| tests | Text pins updated in place; **3/3 mutants killed as predicted** (button-amount revert, auto-charge revert, total-beside-action removal) |

**C proved zero gated-file contact** (`diff vs e079fcc1`: only round 1's already-flagged `signOut.ts +5`).
That is the right evidence to volunteer and it was volunteered without being asked.

### Three duplications C found that my sweep missed

1. **`FeedRow` sold rows say "Sold" twice.** I swept the feed and did not catch it.
2. **The checkout sentence under the Total row** restated the two rows above it.
3. **`"Current bid"` vs `"Starting bid"` at zero bids** — *"current bid"* claims someone has bid. C carried
   the card rule onto the bid screen. **I have adopted this.**

---

## 2 · Three findings in C's build

### R-1 · Mixed units make the buyer's bid look *lower* than the current bid — substantive

`PlaceBidScreen.tsx:260` renders the reference **all-in**:

```
Current bid · $110.00 all-in        ← allInFromDollars(current_bid = $100)
      $105.00                       ← the stepper: a BID
Minimum $105.00                     ← also a BID
```

**$105 next to $110 reads as a lower bid.** It is not: $105 beats the $100 current bid; the $110 is that same
$100 plus the fee. The screen invites the buyer to compare two numbers that are not in the same unit.

**Recommendation: state the reference in bid terms — `Current bid $100.00`.** Every figure the buyer
manipulates on this screen is a bid; the one all-in figure is the total beside the button, already labelled.
This is the single ambiguity my original all-in comparison columns were guarding against — the columns were
the wrong fix, but the hazard was real.

**Keep C's `Starting bid` / `Current bid` switch either way.**

### R-2 · On the listing, the would-be total still appears twice

`TransactionPanel.tsx:122` renders `nextBidAllIn` as the breakdown's total row, and the **CTA sub-label**
(`ListingDetailScreen.tsx:1318`) states the same figure.

**Recommendation: drop the breakdown's total row.** Keep `Tickets` + `Service fee (10%)` — the fee row is the
fee explanation, exactly as C argued — and let the control carry the total. Each number then appears once.

### R-3 · `If you win / $115.50` can be read as "if you win $115.50"

The sticky kicker (`:339`) is *"If you win"* above the total.
**Recommendation: `Total if you win`.** Two words, and the figure stops being ambiguous.

---

## 3 · Where I adopted C's version over my own

| Item | Mine | C's — adopted |
|---|---|---|
| Bid-screen payment sentence | *"You're not charged now. If you win, you'll come back to pay."* | *"Nothing is charged now. If you win, you'll pay this total at checkout."* — **names where**, and ties to the adjacent total |
| Listing commitment sentence | *"A bid is a commitment. If you win, you come back to pay."* | **`BID_COMMITMENT_COPY`** — *"A bid is a commitment. If you win, you'll pay your own bid at checkout to complete the purchase."* |
| Listing breakdown | I deleted the whole block | **C keeps it, de-duplicated.** Better: it keeps the fee itemised where a buyer decides whether to engage at all. My boards now match C's block **minus its total row** (R-2) |
| Zero-bid reference | *"Current bid"* always | **`Starting bid` when `bid_count === 0`** |

**My boards are re-rendered to this reconciled shape.** `pkg7-bid-after*.png` and `pkg7-listing-after*.png`
now show what C built, plus the three corrections above.

---

## 4 · What still stands from my side

- **Bid-screen reference in bid terms** (R-1) — the one substantive disagreement.
- The **contextual minimum**: `Minimum $95.00 · $5 steps` at the floor, `$5 steps` above it. C shows
  `Minimum {min}` unconditionally; the step size is not stated. Minor, C's call.
- The remaining increments C has not yet implemented: **your order** (increment 3), **create listing** and
  **send transfer** (increment 4), **search** (increment 5), and **F-28**'s `StateBlock` title.

---

## 5 · Status

| | |
|---|---|
| Designed | Increments 1–5, all surfaces swept |
| Implemented on C's branch | Bid entry, listing, feed rows, checkout — at `d8d7be1a`. **Not shipped, not deployed** |
| Reviewed | **This document.** 3 findings open with C |
| Device-verified | **Nothing.** No build, no simulator, no production read |

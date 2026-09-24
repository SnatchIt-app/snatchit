# V3 reconciled coverage — shared with C

**B · 2026-09-24.** Reconciled against **C's branch `v3/midnight-app` @ `3f295bca`** and **A's decision
record** `docs/release/V3_REVIEW_NOTES_20260924.md` (commit `53d4bcaf`). Every claim below was read in
source, not taken from a summary.

> **Evidence labels used here.** *Source* = read from code or computed. *Rendered* = a screen actually drawn
> and looked at. *Device* = run on hardware. **Nothing in this document is device evidence, and the
> appearance audit is source only.**

---

## 1 · Closed — removed from the blocker list

| Was | Now | Evidence |
|---|---|---|
| **B-1** buyer `expired` · **B-2** buyer `reversed` · **B-3** seller `reversed` | **CLOSED** | A reviewed the cells at `7e578ed5` and **PASSed** them (`53d4bcaf`). `refundLine` implements the full/partial/recorded/null rule; the receive-screen blocks read status only; `reversed`/`released` never render for the buyer |
| **B-5 / F-22** buyer review deadline | **CLOSED** | `buyerReviewDeadlineLine(auto_release_at)` — server timestamp or nothing. A ruled **yes** to `payout_hold_until`, only when `payout_review_status === 'held'` and non-null, worded as a hold, never derived, no countdown |
| **F-17b / F-17c** | **CLOSED** | Superseded by the cells above |
| **My checkout amount-source condition** | **SUPERSEDED** | A + C resolved it by **deletion**, which is better than my rule: walking the states, *no state is both valid and non-duplicate*, so the sticky Total never renders and `labelCarriesAmount` goes with it. The itemised Total row stays as the buyer's reference |
| **F-30** pressed primary | **CLOSED at `#FF5353`** | See §2 |
| **R-1** bid reference in bid units | **CLOSED** | Owner direction; implemented |
| **R-2** listing total twice | **CLOSED** | Verified in source: `bTotal` is gone from `TransactionPanel.tsx` |
| **R-4** Create duplication | **CLOSED — and better than my proposal** | C kept the review card and dropped only its two money rows. The card's review and validation purpose survives; I had proposed deleting it outright |
| **F-29** recovery only when it exists | **CLOSED, with one gap — see R-5** | `ListingDetailScreen.tsx:739-740` gates the recovery on `bidAvailable` |

---

## 2 · The pressed colour — reconciled at C's value

| | Black label (4.5:1) | vs Midnight (3:1) | vs Daylight (3:1) | Distinctness |
|---|---|---|---|---|
| B proposed `#FF4C4C` (22% white) | 6.39:1 | 6.06:1 | **3.29:1** | 1.180 |
| **C implemented `#FF5353` (25% white) — AGREED** | **6.61:1** | **6.28:1** | 3.17:1 | **1.222** |

Both clear every threshold. **C's is better on the two that matter most** — label legibility and press
perceptibility — and it is already in `Button.tsx:115` and **both token mirrors**. Churning implemented code
for 0.12 of margin on a criterion that already passes would be drift. **My boards are redrawn at `#FF5353`.**

### The distinction the owner asked for

These are **two different changes needing two different kinds of evidence**:

1. **Correcting a latent token.** `brand.redPressed: #CC0000` had **zero importers**; `Button.tsx` set the
   fill unconditionally. Nothing rendered at 3.57:1. Computation settles this one.
2. **Introducing a visible pressed fill.** `Button.tsx:115` now applies `redPressed` on `pressed && !inert`.
   **That is new behaviour**, and computation cannot settle it: **C confirms on a device** that it reads at
   tap speed, does not flicker on fast repeat taps, and does not fight the 0.98 scale.

---

## 3 · Open — every remaining item, assigned

### C — blocking the both-appearances build

| # | Item | Detail |
|---|---|---|
| **A-1** | **`AdaptiveDock` is not themed** | `makeStyles(palette)` is called and the **icons** read `palette.text.*`, but four colour values inside that factory were never converted. On Daylight: dock surface composites to `#545456`, **active tab 2.59:1**, **inactive 1.43:1**. The worst kind of half-theme |
| **A-2** | Dock selected capsule | `rgba(255,255,255,0.14)` → **1.44:1 Daylight, 1.47:1 Midnight — fails in both**. Selection is also carried by the ring and label colour, so it is a supporting cue, not the sole one — but it carries nothing as it stands |
| **A-3** | `Sheet.tsx:135` grabber | `rgba(255,255,255,0.30)` → **1.03:1** on a light panel. Invisible |
| **A-4** | `StatCardStrip.tsx:65` | `rgba(255,255,255,0.06)` and **no palette import at all** |
| **A-5** | `EventMedia.tsx:309` | The **image fallback initial**, `rgba(255,255,255,0.20)` on `surface.plate` → **~1.02:1**. This is one of the fallbacks the owner named |
| **R-5** | **`bidAvailable` misses one case** | `:739` re-derives availability locally instead of asking the resolver. With `reservedByMe` it evaluates **true**, but `listingActions` returns `continue_reservation` **with no secondary** — so the copy offers a bid the screen does not have. Add `&& !reservedByMe`, or better, read `place_bid` off the resolved actions |
| **F-28** | Not yet implemented | `transferState.ts:171` still carries the `StateBlock` title *"Marked as sent"* beside the badge |
| **F-27** | Status unclear | `fetchData(` went from 5 call sites to 8. **C states which failure paths now refetch** — and keeps this functional change separate from copy-only work |

#### Not build blockers — unused, and kept separate from visible defects

| # | Item | Why it does not block |
|---|---|---|
| **A-6** | `TransferStatusBadge.tsx:6-12` — seven hard-coded colours | **Zero importers.** Nothing renders it, so it cannot fail in either appearance. It blocks only if someone wires it: **convert it at that moment, or delete it.** I listed it as a blocker before; that was wrong |
| **A-7** | `PlatformInstructions.tsx:186` — a second amber `#FBBF24` | Rendered, but a 10% tint with a tokened border. Drift, not a defect |

**Correct as literals, no action:** avatar and upload overlays, `IconButton.onArt`, the `EventMedia` scrim
gradients — all artwork context, which does not invert. `ProofImageViewer.tsx:193`'s close button is fine
**provided the viewer backdrop stays dark in both**; C confirms.

### B — mine

Remaining light appearances: **Create · My listings · Send/receive transfer · Bids tab · Auth (7) · Tickets ·
Profile · Settings hub + 7 sub-surfaces · Dispute/report · 45 dialogs · 4 state screens · error boundary ·
outbid notice · status banner.** The token set is complete, so these are re-renders, not new decisions.
Plus: review C's screens as packages land.

### Owner — nothing outstanding

**The build is already authorised.** One sandbox EAS `preview` build, conditional on the readiness checks,
is recorded in `V3_PHONE_TEST_FIXTURE_PLAN.md`. **"Awaiting build authorisation" is removed from this list
and must not reappear.**

### Worth resolving before a device session, not after

**D-8** — whether the Tickets RPC migration is applied decides whether that tab shows the empty state or the
error state. Without knowing, a device result there cannot be interpreted.

# V3 readiness — one reconciled list

**B · 2026-09-24.** Against **C `v3/midnight-app` @ `3f295bca`** and A's record `53d4bcaf`.
**The build is authorised.** One sandbox EAS `preview`, conditional on the checks below, per
`V3_PHONE_TEST_FIXTURE_PLAN.md`. **No further authorisation is being requested.**

> *Source* = read from code or computed · *Rendered* = a screen drawn and looked at · *Device* = run on
> hardware. **Nothing here is device evidence.**

---

## 0 · Appearance migration coverage

**Superseded by `V3_APPEARANCE_COVERAGE.md`** — the 55/15/2 figures here counted *imports*, not colour
accesses. Corrected: of **82** files, **68 are colour-bearing**; **45 unmigrated**, **1 partial**, **16
palette-only** (11 of them fully clean), **6 literal-only**. C has migrated four times more than I said.

---

## 1 · Remaining implementation — C, and it gates the build

| # | Item | Done when |
|---|---|---|
| **A-1** | `AdaptiveDock` surfaces — `:236`, `:238`, `:255`, `:261`, `:278` | The four values inside `makeStyles(palette)` read the palette. Today the icons are themed and the surface is not: Daylight active tab **2.59:1**, inactive **1.43:1** |
| **A-2** | Dock selected capsule | Currently **1.44:1 Daylight / 1.47:1 Midnight — fails in both** |
| **A-3** | `Sheet.tsx:135` grabber | **1.03:1** on a light panel |
| **A-4** | `StatCardStrip.tsx:65` | No palette import at all |
| **A-5** | `EventMedia.tsx:309` image-fallback initial | **~1.02:1** on `surface.plate` |
| **R-5** | `bidAvailable` (`ListingDetailScreen.tsx:739`) | **Read availability off the authoritative resolver.** With `reservedByMe`, `listingActions` returns `continue_reservation` **with no secondary**, so the copy offers a bid that is not on screen. **Do not keep a competing availability formula** — the local one is the defect, not its current value |
| **F-28** | `transferState.ts:171` | The `StateBlock` title still duplicates the badge. Keep the **accessible success announcement** and **every failure path** |

**Not blocking:** `TransferStatusBadge` (zero importers — convert or delete only if it is ever wired) and
`PlatformInstructions`' second amber. **An unused component is not a visible defect.**

## 2 · Remaining review

| Owner | Item |
|---|---|
| **C** | **Verify the rendered combinations, not that a component accepts a palette.** A-1 is exactly that failure: `makeStyles(palette)` is called and the surface is still a literal. Cover disabled controls, selected states, overlays, native dialogs, the keyboard, artwork and both status bars |
| **C** | The **new visible pressed fill** (`Button.tsx:115`) — new behaviour, not a token correction. Reads at tap speed · no flicker on fast repeats · does not fight the 0.98 scale |
| **B** | Light designs for the **55 unmigrated + 15 partial** files as C reaches them — the token set is finished, so these are re-renders, not new decisions. Surfaces still to draw: Create · My listings · Send/receive transfer · Bids tab · Auth (7) · Tickets · Profile · Settings hub + 7 · Dispute/report · 45 dialogs · 4 state screens · error boundary · outbid notice · status banner. **Re-renders against a finished token set, not new decisions** |
| **B** | Review each of C's screens as it lands, against the frozen package |

## 3 · Fixture permissions needed — exactly

| # | Needed from | What |
|---|---|---|
| **P-1** | **A** | Read (a): does an open sandbox auction already have ≥ 1 bid? **If yes, W1 is unnecessary.** Prefer the existing fixture |
| **P-2** | **A** | Whether `release_reservation` leaves the **PaymentIntent** open, and whether an open sandbox intent must be cancelled — see §4 |
| **P-3** | **A** | If W1 runs: confirmation that the listing's **seller and previous leader are fixture accounts**, and that the auction's end time is **outside the window** |
| **P-4** | **A** | D-8 — `public.get_my_tickets()` on the sandbox, so the Tickets tab's result is interpretable. Without it, empty vs error cannot be told apart |

**W1 and W2 are not executed.** Existing fixtures are preferred over creating state.

## 4 · The fixture plan's two side-effect claims are corrected

**W2 — "one hold … no payment" is incomplete.** `CheckoutNative.tsx:211` runs `setupPayment()` **on mount**,
and `setupDecision.ts:229` calls `createIntent()` → `create-payment-intent` whenever no settled payment
exists and the hold is the buyer's. **Reaching the checkout boards creates a Stripe PaymentIntent without
anyone tapping Pay.** No charge occurs; "no payment" is still the wrong word. Accurate: **one hold and one
PaymentIntent; no charge.**

**W1 — "no payment follows" is true and incomplete.** The `bids` insert fires `notify_bid_placed` and
`notify_outbid` (migration 058 + the existing **pg_net push triggers**): a **`bid_received` to the seller**
and an **`outbid` to the previous leader**, dispatched, not merely recorded — and **F-23** means no
notification preference is applied. The bid also enters auction finalisation, so **it can win** after the
window closes, creating an order and a transfer obligation.

Full trace: `V3_PHONE_TEST_FIXTURE_PLAN.md` → *"B · Side-effect trace"*.

## 5 · Stays explicitly unverified on device

**`expired`, `reversed` and `held` have no sandbox examples.** They remain **unverified on device**, and
**passing another transfer state does not cover them**. A's source review PASSed the cells; that is source
evidence, and it is not a device result.

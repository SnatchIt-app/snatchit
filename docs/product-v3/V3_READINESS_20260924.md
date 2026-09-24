# V3 readiness — one reconciled list

**B · 2026-09-24.** Against **C `v3/midnight-app` @ `3f295bca`** and A's record `53d4bcaf`.
**The build is authorised.** One sandbox EAS `preview`, conditional on the checks below, per
`V3_PHONE_TEST_FIXTURE_PLAN.md`. **No further authorisation is being requested.**

> *Source* = read from code or computed · *Rendered* = a screen drawn and looked at · *Device* = run on
> hardware. **Nothing here is device evidence.**

---

## 0 · Appearance migration coverage — measured, because a short defect list is not a status

Counted on **C `v3/midnight-app` @ `016087ea`**, across `src/screens`, `src/components` and `app`:

| | Files |
|---|---|
| `.tsx` total | **94** |
| Carry no colour of their own (neither palette nor `v2`) | 22 |
| **Colour-bearing** | **72** |
| Read the palette at all | 17 |
| …of those, **still also read static `v2.*`** — partially migrated | **15** |
| **Read the palette only** — fully migrated | **2** |
| **Read `v2.*` and never the palette** — unmigrated | **55** |

**Why `v2.*` means wrong-in-Daylight:** `palette.ts` states that `dark` *"re-exports the v2 token groups
untouched"*, and `light` is a separate map. **A file importing `v2.*` directly gets the Midnight value in
both appearances.**

**So the eight literals I reported are not the migration.** They are the subset that no token system could
ever reach. **55 unmigrated files plus 15 partially migrated ones is the actual remaining surface**, and it
is much larger than any defect list. The five primitives C has converted are the foundation, not the job.

### Two record corrections, both mine

1. **A-1 / A-2 / A-3 are APPROVED** (owner, 2026-09-22 — *"I approve neutral decorative hairlines,
   mixed-case sentence headings, and the rounded controls shown in the approved V3 designs"*).
   `palette.ts` currently records A-1 as *"an open owner decision … NOT adopted here"*, reading a **stale row
   in my own coverage matrix**. That row is now closed. **Neutral hairlines are approved and should land.**
2. **Canvas `#08090A` is not a proposal — withdraw it.** `V3_PACKAGE_1` §2 states canvas = **`#000000`**.
   The `#08090A` in my boards is a rendering artefact of the drawing engine, never a design change.
   **Canvas stays `#000000`.**

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

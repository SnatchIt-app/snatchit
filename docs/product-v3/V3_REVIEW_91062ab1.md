# B — independent visual review at 91062ab1

**Candidate** `91062ab179a6737a3bba4049a10c48921e5c3abe` (`v3/midnight-app` tip when captured),
resolved with `git rev-parse`, not taken from a report. Harness patches: **0**.
**Appearance** is driven by the app's own preference (`?appearance=`), the one Settings writes —
never a browser emulation flag. **Fonts verified on every capture**: `Inter_400Regular`,
`Inter_500Medium`, `Inter_600SemiBold`, `Inter_700Bold`, `Oswald_700Bold` all in use. No fallback
render is reported here.

**Evidence class: web render.** Development evidence. It establishes nothing about native iOS
rendering, safe areas, Dynamic Type or the real feed. Native acceptance is a separate class and
is still owed.

**No real checkout was opened. No fixture was created or mutated. No production read. No build.**

---

## 1. Avatar — CLOSED on measurement

The dock and Profile were measured on **one signed-in account, one commit**, reaching Profile the
way a person reaches it (tapping "You"), because a `/(tabs)/profile` deep link cold-loads to
`/home` and an earlier capture of mine caught that redirect. That capture was void and was redone.

| surface | request | returned | painted | fit |
|---|---|---|---|---|
| dock | `avatar_….jpg?width=84&height=84&quality=45&resize=cover` | **84 × 84 — square** | 28 × 28 | `cover`, `50% 50%` |
| Profile | `avatar_….jpg` (no transform) | 1174 × 1176 | 56 × 56 | `cover`, `50% 50%` |

* **Same source file on both surfaces.**
* **The derivative is square.** The 56 × 1176 sliver is gone; 84 px is exactly 28 pt × 3.
* **Same visible crop**, measured rather than inferred: mean absolute per-channel difference over
  the circle between the dock's served 84 px image and the Profile original resampled to 84 px is
  **20.4**, against a **122.0** positive control (the same dock circle versus an unrelated region
  of the same screen). The Profile edit badge is masked out of both figures; before masking it the
  number was contaminated and I do not rely on it.

Evidence: `comparisons/avatar_closure_91062ab1.png`.

**One observation, not a failure.** `quality=45` is visibly soft when magnified. At its painted
size it reads as the same photograph. Raising it is C's call; 45 is low for a face.

**Explicitly pending, not performed:** account isolation (needs an account switch) and refresh
after upload (needs an upload). Neither is authorised and neither is claimed.

---

## 2. Send transfer, and the transfer gallery — reviewed, 2 findings

Seller-side. My session is the DV buyer, so this is **harness-rendered from a fixture, not real
data**. Wording reviewed against A's §2g rulings as committed in `1c468a1e`.

Evidence: `comparisons/send_light_91062ab1.png`, and the full synthetic gallery.

### What holds

* **"Review window has passed" is gone**, on both sides. The card whose scheduled decision time is
  in the past prints `Release decision at Sun 20 Sep · 06:00.` — the server's date stated as a
  fact, with no claim about a window. That is A's ruling implemented exactly.
* **The server-derived date uses its real field, and every missing-date condition omits rather
  than invents.** All three are rendered and all three behave:
  * buyer, no `auto_release_at` → the deadline line is **absent**;
  * seller, `held` with no `payout_hold_until` → "Payout pending, held for review." (held stated, no date);
  * seller, neither field → **no date line at all**, block intact.
* **A seller payout reversal establishes neither a buyer refund nor a full reversal.** Seller side:
  "A reversal was recorded on this order's payout." Buyer side follows only what is recorded —
  `Refunded $75` / `Partly refunded $60 of $120` / `Refund recorded` / "If a refund is issued, it
  will show here."

### F-91-1 — the standing report sentence contradicts the state it is printed under

Every seller marked-sent card ends with **"If the buyer reports an issue, your payout will be held
for review."** — including the cards where the payout is *already* held or under review:

* held, with a date: "Payout held until Fri 2 Oct · 15:30." **+** "…will be held for review."
* held, no date: "Payout pending, held for review. No action needed unless the buyer reports an
  issue." **+** "…will be held for review."
* manual review: "…this transfer is under manual review." **+** "…will be held for review."

A future-tense conditional under a state that has already happened tells the seller the hold has
not happened yet. **Suppress the line when `payout_review_status` is `held` or `manual_review`.**

### F-91-2 — `auto_released`, the state `1c468a1e` rewrote, has no card in the live gallery

`grep -c auto_released app/_dev/transfer-states.tsx` → **0**. The new copy ("released without a
confirmation or a report", and the `payout_released_at`-gated money claim) is the most
consequential wording in that commit and it is the one state the synthetic gallery cannot render.
I reviewed it **in source only** and claim nothing about how it paints. **Add the `auto_released`
cards — buyer and seller, with and without `payout_released_at`.**

---

## 3. Listing in Light — reviewed, all eight states

Evidence: `comparisons/listing_live_light_91062ab1.png`, plus captures of all eight.

### What holds

* **Buy Now leads and is filled** — "Buy both now · $132.00 / all-in, ends the auction" as the
  primary, "Place a bid / minimum $104.50 all-in" as the outline secondary beneath it. This is the
  owner's resolver ruling implemented. (My earlier review wrongly implied this held at `911f65fd`;
  it did not, and that correction stands.)
* Every non-live state replaces the two-action pair with one state control and a sentence outside
  it: `Sold` · `Cancelled` · `Pay now` ("You won / Pay to claim your tickets.") · `Finish checkout`
  · `On hold` ("Another buyer is in checkout. It comes back if they do not finish checkout.") ·
  `Your listing` ("You listed this, so you cannot bid or buy.").
* `not-found` is a real state, not a blank: "Listing not found / It may have been sold or taken
  down. / Browse live listings".
* `sold` prints "SOLD FOR $132.00 total" with "Price includes the 10% service fee." — the all-in
  truth, not a bare figure.

### F-91-3 — over-artwork chips do no work on the missing-artwork plate

Measured on the hero, both appearances identically (the plate is deliberately dark in both):

| pair | ratio |
|---|---|
| back/overflow chip fill `#09090B` vs plate `#141519` | **1.09 : 1** |
| chevron glyph vs chip fill | **11.54 : 1** |

**This is not a 1.4.11 failure** — the glyph identifies the control at 11.5:1, and the chip is
decorative. But the chip is drawn and is invisible here, so it earns nothing on the no-artwork
case while presumably earning its keep over a photograph. Worth a deliberate decision rather than
an accident: either drop it on the plate or give it a boundary that survives the plate.

### F-91-4 — `own-listing` offers a bid breakdown to someone who cannot bid

The `own-listing` state prints the full **"IF YOU BID THE MINIMUM / Tickets $95.00 / Service fee
(10%) $9.50"** block, and then says "You listed this, so you cannot bid or buy." The breakdown
answers a question this viewer is not allowed to ask. Withhold it in the seller's own view.

### F-91-5 — `cancelled` says cancelled three times

Badge "LISTING CANCELLED", sentence "This listing was cancelled.", control "Cancelled". The
de-duplication the owner asked for on Cancelled has not reached this screen.

---

## 4. Home — header settled, 1 finding, 1 correction to my own reading

Evidence: `comparisons/home_filter_header_91062ab1.png`,
`comparisons/home_filters_sheet_light_91062ab1.png`, `comparisons/home_states_light_91062ab1.png`.

### The filter arrangement meets the owner's ruling, with one exception

Measured, not eyeballed:

* Filters control **44 × 44** at (277, 20); Search **44 × 44** at (329, 20); 8 pt apart. Both meet
  the 44 pt target.
* Accessible names: **"Filters"** with nothing active, **"Filters, 1 active"** with one — the count
  reaches assistive technology, not only the badge.
* **Always visible**, including when no filter is active. The only entry point is never hidden.
* **Two distinct controls, two distinct glyphs.** A search glyph never becomes a Filters action.
* The sheet preserves the capabilities: SCOPE · SALE TYPE (Buy now / Auction) · TICKET TYPE
  (GA / VIP) · STATUS (Ended / Sold) · CATEGORY (8) · AREA, over a sticky **Clear** / **Apply**.

### F-91-6 — the Filters glyph is a hamburger, not a filter mark

Measured off the unbadged capture: **three bars, each exactly 41 device px, equal length, evenly
spaced.** That is the universal navigation-menu glyph. A filter mark is a funnel, or bars of
*decreasing* length, or sliders with knobs.

**I withdraw my first reading of this**, taken from the badged capture, where the count disc
occludes the top bar's right end and the bars appear to taper. The measurement is on the plain
header and is unambiguous.

The approved board `pkg8-home-light` **draws no filter control at all** — only the search
magnifier — so the board cannot settle this. The owner's own ruling governs, and it says "a
visually quiet **Filters** icon". Quiet it is; Filters it does not say. **Change the glyph, keep
the 44 × 44 target, the weight and the badge.**

### F-91-7 — two of the six empty/error states paint nothing

At `91062ab1`, in Light, verified at a **30-second** settle, with **no exception in the console**:

| variant | body |
|---|---|
| `empty` | "Nothing live right now / Check back, or list the tickets you cannot use." ✅ |
| `error` | "Couldn't load this / Something went wrong on our side. Try again in a moment." + Retry ✅ |
| `offline` | "You're offline / Check your internet connection and try again." + Retry ✅ |
| `sold-empty` | **blank — header only** ❌ (expected "Nothing sold yet") |
| `ended-empty` | **blank — header only** ❌ (expected "No ended auctions") |

The harness's own header says these two should print their copy, gated on `mayShowEmptyCopy`. They
do not. A shopper who taps Sold or Ended with nothing behind it gets an empty screen with no
sentence.

*Not defects, recorded so they are not re-filed:* the dock is absent from every `_dev` capture
because those routes mount the screen outside the tabs navigator; and there is no chip strip
because the owner directed its removal into the sheet.

---

## 5. Checkout — coverage reconciled; the review itself is pending C's corrective commit

### My earlier count was wrong in both directions. The correction

At `d374bd3f` I reported "five fixtures rendering four outcomes, seven unreachable" and then
listed eight. Re-derived from the file:

* `d374bd3f` carried **twelve** fixtures — eight in `STATES` plus four early-return faces — not
  five. I had enumerated `STATES` incompletely and captured only five of them.
* Of `payControl`'s **eleven** outcomes, **five** had a fixture there (Checking your payment ·
  Back to listing · Checking your hold · Pay <total> · Try again) and **six** did not.
* So neither "seven" nor my list of eight was right: **two of the eight I listed — "Back to
  listing" and "Checking your hold" — already had fixtures I had simply not opened.**

I understated C's coverage. The correction is mine, and the mapping below replaces the earlier one.

### The one real gap, at `91062ab1`

`payControl` has 11 outcomes. Ten had a fixture. **"Setting up payment" had none**: the `preparing`
fixture painted the literal `'Preparing…'`, a string that appears nowhere in the app outside the
harness — the real screen passes `payControl`'s output through verbatim
(`pay={{ label: pay.label, … }}`), so it can only ever paint "Setting up payment".

**The totality test could not catch this.** `CV9` reads the harness file *with comments* and
asserts `harness.toContain(label)`; "Setting up payment" occurs exactly once in that file — **in
the documentation table in the header**. Demonstrated: with the table excluded, the check fails for
that one label and passes for the other ten. The test was green at 11/11 throughout.

C has since replaced the handwritten labels with real `payControl(…)` calls at `65052bfc`, which
removes the whole class rather than the instance. That is the right fix.

### Why the assessment is not published here

The owner has asked for all states in both appearances against four criteria — readable busy
controls that stay untappable, whether spinner-plus-label reads as work in progress, one status
statement that keeps its unique uncertainty and recovery guidance, and no duplicated screen-reader
announcement — and has told me not to assume a disabled control must be faded. C is **still
removing the now-redundant body status line**. Reviewing between the two halves of one correction
would produce a verdict on a state that will not ship. **I will capture once C names the final
corrective commit**, and I am asking C for it rather than guessing at the tip.

---

## 6. A web-only artefact, recorded so neither of us files it as a defect

Every `Button` with a `pendingLabel` keeps that label mounted at `opacity: 0` so the control cannot
change width mid-press. On the web render it measures `aria-hidden=false`, so a web screen reader
would read "Sold" and then "Reserving…" on a sold listing. I was about to file that.

**It is not an app defect.** `Button` already sets `accessibilityElementsHidden` and
`importantForAccessibility="no-hide-descendants"` on that row — the correct **React Native** props,
which do remove the subtree on iOS. `react-native-web` does not map them to `aria-hidden`. The
same applies to Home's "Retry / Retrying…".

This is a limit of my instrument, not a finding — and it is a reminder that screen-reader
behaviour cannot be concluded from the web path at all. It needs the native class.

---

## 7. Native prerequisite — verified, nothing needed from the owner

| check | result |
|---|---|
| `xcode-select -p` | `/Applications/Xcode.app/Contents/Developer` — the full Xcode, not CommandLineTools |
| `xcodebuild -version` | **Xcode 26.6 (17F113)**, and it ran with no licence prompt, so the licence is accepted |
| `xcodebuild -checkFirstLaunchStatus` | **exit 0** — first-launch packages installed |
| `xcrun simctl list runtimes` | **iOS 26.2 (23C54)** installed |
| devices | iPhone 17 Pro / 17 Pro Max / Air / 17 / 16e, and five iPads — all available |

**No licence prompt, no runtime download, no administrator action is required.** C owns simulator
setup and running the candidate; I own independent comparison of the native captures against the
approved references. The suggested shared configuration, so both sides' evidence is comparable:
**iPhone 17 Pro, iOS 26.2**, captured in both appearances at the same commit, with the simulator
UDID recorded beside each image.

---

## Sent to C

F-91-1 · F-91-2 · F-91-4 · F-91-5 · F-91-6 · F-91-7, and a request to name the final checkout
corrective commit. F-91-3 is a decision to take, not a bug to fix.

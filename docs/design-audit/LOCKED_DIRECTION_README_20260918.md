# Snatch It — locked direction (B, 2026-09-18)

**File:** `docs/design-audit/prototypes/snatch-it-locked.html` — one self-contained interactive prototype.
Open it directly: no server, no build, no network request. Artwork is generated in SVG from a seeded PRNG.

This is the prototype the direction is locked against. It supersedes `chrome-signal.html` (a single app-wide
hybrid), because the direction is now **per screen**.

**Status: the visual direction is closed.** The nine-screen mapping is locked, Home-only view modes are locked, and
the four remaining decisions were approved on 18 September and are applied in the prototype — not merely recorded
beside it. What is left is a dependency list, not a set of open questions.

---

## 1 · Screen map — the locked direction for each surface

| Screen | Locked direction | Where Liquid appears |
|---|---|---|
| **Home** | **B · Editorial Market** — the market made visible | The floating view selector and the filter sheet only |
| **Home · alternates** | **4 · Liquid** and **N1 · Ticket Stub**, as *view modes inside Home* | Liquid mode: 16 px media and Apple's 35% dimming layer under text over art |
| **Listing detail** | **B · Editorial Market** hierarchy **+ 4 · Liquid** | Image treatment, the photo and bid overlays, and the rounded CTA |
| **Bids** | **R · Gallery / Ledger** | None — Bids has no bottom action |
| **Tickets** | **1 · Gallery** — the flyer does the talking | None |
| **Send transfer** | **5 · Utility** structure **+ 4 · Liquid** CTA | The rounded CTA and the confirmation sheet |
| **Receive transfer** | **2 · Index** structure **+ 4 · Liquid** CTA | The rounded CTA, the quiet secondary under it, and the dispute sheet |
| **Checkout** | **1 · Gallery** hierarchy **+ 4 · Liquid** CTA | The rounded CTA only |
| **Profile** | **4 · Liquid** | Grouped 14 px lists, glass navigation, chrome ring on the avatar. No bottom CTA |
| **Settings** | **4 · Liquid** | Grouped 14 px lists and glass navigation. No bottom CTA |

The three Home views are **three ways to read one feed, not three themes**: switching to Liquid or Ticket Stub
changes Home and nothing else. Every other screen keeps its own locked direction. Verified at runtime — each
screen renders with its own direction tokens: editorial · editorial · ledger · gallery · utility · index · gallery ·
liquid · liquid.

### How each direction shows up, concretely

- **Editorial Market (Home).** A 4:5 poster hero carries the market — live state, name, date and venue, price —
  with the elapsed share of the auction's final six hours on a meter directly beneath it. Then "Ending soon",
  populated strictly by real remaining time, then the rest of the week as a thumbnail list.
- **Editorial + Liquid (Listing).** Editorial's information order is untouched: eyebrow, name, commitment panel
  (current bid at 22 px, bid count, minimum next bid, live state, six-hour meter), fact table, commitment line.
  Liquid appears three times only — the dimmed hero, the two overlays, the CTA.
- **Gallery / Ledger (Bids).** Image-led rows with ledger discipline: 4:5 thumbnail, event, status as a chrome or
  amber chip, your bid in a right-aligned tabular column with the live state beneath it. No filled action anywhere.
- **Gallery (Tickets).** One 4:5 flyer per ticket, full bleed, with the entry facts and the scan code in a quiet
  block beneath. Payment state is stated in words, because "do I actually own this" is what the screen answers.
- **Utility (Send).** Compact transaction structure at a 7 px row rhythm: deadline and its consequence, status
  rail, proof, instructions, recipient and delivery facts, payout. Everything fits above the action.
- **Index (Receive).** Hairline section heads, 6 px rows, one aligned value column. The full breakdown sits
  directly above the action that releases it.
- **Gallery (Checkout).** Artwork leads, then name and date, then the order with the total set larger than every
  line item.
- **Liquid (Profile, Settings).** Current-iOS grouped lists on opaque surfaces, glass only on navigation.

---

## 2 · Approved decisions — 18 September

| Approved | The ruling | How the prototype obeys it |
|---|---|---|
| **Red** *(final, 18 Sep)* | Red is reserved for **primary actions, destructive actions and the brand mark**. It is not used for passive navigation or decoration — **the selected tab indicator is chrome.** | Red now resolves to **nine elements in the whole product**, every one a money commitment or a destructive action: Place bid (screen and sheet), Mark as sent (screen and confirm), Confirm receipt (screen and confirm), Pay, and Delete account (outlined, screen and sheet). **Zero red in the navigation layer** — the selected-tab indicator and the dock's bid count are both chrome, verified per screen. Status and live-bid indicators are chrome or amber; the ending-soon pill is amber. The brand-mark slot is granted but unused: this prototype sets the wordmark in chrome, which is a Chrome Signal choice rather than a constraint, and a red mark is one token away. |
| **Radius — scoped exception** | Liquid may use **14 / 16 / 20 px** on its glass CTAs, overlays and grouped surfaces. The rest of the app stays square. | 20 px on the CTA and the sheets, 16 px on media inside a Liquid surface, 14 px on grouped Liquid lists. Every other corner is 0 or a pill. Four strays were squared off to enforce it: 2 px actions, a 2 px scan code, 10 px tab buttons and a 3 px card swatch. |
| **Green** | Green is reserved for confirmed payment or completed money states. | Green now resolves to **four elements in the whole app**: receipt confirmed with payment released, the paid checkout receipt, a confirmed ticket, and a won bid whose payment is complete. Proof "Verified", identity "Phone and ID verified", "Marked as sent" and "You're the leading bidder" were green and are now chrome — none of them is a completed money state. |
| **Blur — deferred** | Real blur waits for an authorised build. The solid translucent fallback is the baseline for prototypes and planning. | The prototype **defaults to the fallback**, with raised alphas carrying the legibility a blur would have provided. Measured: **zero blurred surfaces on load**, 21 when the top-bar `Glass` control previews real blur. What you see on load is what ships. |

### The Liquid rule, as implemented

**Liquid means a rounded CTA anchored at the bottom, plus restrained overlays and image treatment. It never
replaces a screen's layout.**

- **Four screens have a bottom CTA:** Listing, Send, Receive, Checkout. 20 px radius, 52 px tall, one inner
  specular highlight, a light 1 px border, a red glow beneath.
- **Five screens have none:** Home, Bids, Tickets, Profile, Settings keep the dock and nothing else.
- **Glass is confined to navigation and overlays** — nav bars, the dock, floating on-art controls, the Home
  view-selector pills, the neutral and quiet buttons, and the sheets. **Zero content-layer glass on any screen.**
- **Readability above the CTA:** content scrolls under the bar with 104 px of matched bottom padding and a 34 px
  scrim above it, so the last line of a price breakdown is never trapped behind it.
- **The primary fill is opaque, deliberately.** A translucent red CTA measured **2.96:1** with black text over the
  dark canvas, and even solid `#E00E0E` is 4.24:1. A red CTA cannot be both translucent over black and legible, so
  the fill is brand `#FF1A1A` at full strength (**5.41:1**) and the depth is carried by the highlight, border and
  shadow. This is independent of the blur ruling: the fill stays opaque even after a build is authorised.

---

## 3 · The shared system

**Spacing.** One 4 pt base, six steps: **4 / 6 / 9 / 12 / 16 / 22**. A direction picks its rhythm from those steps
and never invents a value between them.

| Direction | Section / block rhythm | Row padding |
|---|---|---|
| Gallery | 18 / 26 | 11 px |
| Editorial | 16 / 22 | 10 px |
| Liquid | 14 / 20, 14 px grouped corners | 9 px |
| Ledger | 14 / 19 | 9 px |
| Utility · Index | 12–13 / 16–17 | 7 px |

**Typography.** One scale everywhere: hero 21–22 · screen title 16 · item name 14.5 · body 13 · small 11.5 ·
micro 10 · price 16 · dominant price 22. A **condensed display face for names on Editorial and Index only** — the
two directions whose identity is typographic; everywhere else names use the system sans. Every figure tabular.
Micro labels are the only uppercase in the product, at 10 px / 0.09 em.

**CTA treatment.** Rounded 20 px CTA on the four screens named above, opaque red fill, one filled action per
screen with its consequence on its own sub-line, and a disabled action stating its reason in the same place.
Flat, square actions everywhere else. Destructive is outlined, never filled.

**Chrome accents.** Five places and no more: the wordmark, the 1 px top edge on nav bar / action bar / dock, the
**selected-tab indicator** — chrome by ruling, never red — the inner highlight on a CTA, and the ring on the profile
avatar. Status colour is **chrome for live and leading, amber for attention, green only for confirmed payment or a
completed money state.**

**Motion.** Reduce Motion is the default and the shipping baseline. With motion on: screen change rises 4 px over
200 ms; sheets translate 14 px over 260 ms; a Home view switch crossfades at 200 ms; a changed bid value dips once.
Never on a warning, never on a per-second tick, and never delaying an action's result.

---

## 4 · Remaining implementation dependencies

Nothing below is a visual question. These are the things that must exist, in order, before the locked direction
can be built.

| Dependency | What it blocks | Owner |
|---|---|---|
| **Release-critical state fixes** (stage 0) | Everything. The bid form's `0` floor, the re-entrant destructive actions, Home's in-flight empty state and the avatar spinner come before any visual work. | **C** |
| **Token pair** | Every screen. One surface ramp plus the approved radius set land in `src/theme/v2.ts` and must be mirrored in `packages/design-tokens/src/brand.ts` — the parity assertion compares them with `toStrictEqual`, so a one-sided edit fails the suite. | B proposes · **A** merges |
| **`src/lib/listing/liveBid.ts`** | Home, Listing, Bids. One pure function from a real end time to exactly one of four states, unit-tested, with a boundary mutant that must fail. | **C** |
| **`Notice` + `StickyBar`** | All four money screens. The rounded CTA is a **variant of `StickyBar`**, not a new component, and its primary fill is opaque for the contrast reason in §2. | **C** |
| **Media slots** | Home, Listing, Tickets, Checkout. A 4:5 hero slot and a 3:2 feed slot in `src/lib/media/slots.ts`, with `contentFit: cover` so crops match the prototype. | **C** |
| **Condensed display face** | Editorial and Index names only. The real face must be bundled and measured; this prototype falls back to a system condensed stack, which sets differently. | Owner picks · **C** bundles |
| **An authorised build** | *Only* the blur upgrade and the gradient hairline. Deferred by the ruling above; **nothing else waits on it.** | **Owner** |
| **Handset pass** | Sign-off, not construction. No screen here has been rendered on a device; type and spacing will differ there. | **C** |

Sequence, unchanged: stage 0 → `liveBid.ts` → `Notice` + `StickyBar` (tokens land here) → live state into
`DiscoveryCard` / `BidCard` / `TransactionPanel` → Home layout and media slots → money-screen density and the
status rail → motion last. Every stage is reviewable and reversible on its own, and none of it touches the gated
client surface (`src/lib/payments.ts`, `src/lib/checkout/*`, `src/lib/auth/signOut.ts`) or any payment, auth or
transfer rule.

### Two things still genuinely open — neither blocks implementation

| Open | What the prototype does | Why it can wait |
|---|---|---|
| **Gallery on Tickets** | One 4:5 flyer per ticket, so a second sits 171 px below the fold | The most beautiful Tickets screen and the least scannable. A wallet with eight tickets may want Ledger — decidable once someone holds a real one |
| **Home mode persistence** | Session state; resets to Editorial Market | Whether a chosen view is remembered per person, and whether it syncs across devices, is a product decision rather than a visual one |

---

## 5 · Verification — measured in the browser, 2026-09-18

| Check | Result |
|---|---|
| Screens rendered (9 screens + 3 Home views) | **12 / 12**, zero JavaScript errors |
| Flows exercised | place bid → leading · mark as sent → payout pending · confirm receipt → released · pay → receipt · Home mode switch · filters · 7 sheets — **all pass** |
| Direction tokens per screen | **as locked** (list in §1) |
| Rounded CTA present | Listing, Send, Receive, Checkout — **and nowhere else** |
| **Radius** — every corner in the app | **0, pill, or the granted 14 / 16 / 20.** Runtime audit across nine screens and seven sheets: **zero strays**. The only other values are the simulated iOS status bar's own hardware (1 px signal bars, 3 px battery) |
| **Red** — every red element in the app and in all seven sheets | **nine**, each a money commitment or a destructive action (Place bid ×2, Mark as sent ×2, Confirm receipt ×2, Pay, Delete account ×2 outlined). **Zero** on Home, Bids, Tickets, Profile, and zero in the filters, photos, bid-detail and dispute sheets |
| **Red in the navigation layer** | **zero.** Selected-tab indicator and dock badge are chrome on all five dock-bearing screens, checked against the computed indicator gradient rather than the stylesheet |
| **Green** — every green element in the app | **four, all completed money states:** receipt confirmed / payment released · paid checkout receipt · confirmed ticket · won bid with payment complete. Nothing else in the product is green |
| **Blur** — surfaces with a live backdrop filter | **0 on load** (solid fallback, as ruled); 21 when real blur is previewed |
| Content-layer glass | **zero**, in either mode |
| Contrast in the shipping mode, alpha-composited over each real surface | CTA label **5.41** · CTA sub-line **4.76** · neutral CTA **10.21** · quiet CTA **7.93** · inactive view pill **4.70** · small text **4.68** · micro **4.68** · rail detail **4.68** · amber pill **11.71** · chrome pill **10.55** — all ≥ 4.5. The decorative chevron is 3.56, above the 3:1 required of a non-text control |
| Tap targets under 40 px | **zero**, including inside all seven sheets — chips, view pills, switches, the segmented control and grouped rows each carry a 44 px hit area behind a smaller ring |
| Animations with Reduce Motion on | **zero** |
| Essential content (recipient · delivery · proof · deadline and consequence · payment state · full breakdown) | **0 missing** across Listing, Send, Receive, Checkout |
| Home indicator drawn | **9 / 9** screens, and every CTA clears it |

### Fit at 390 × 844, compact scale

| | Overflow |
|---|---|
| Bids · Profile | **0** |
| Send | 16 px |
| Receive | 46 px |
| Checkout · Home · Ticket Stub | 96 px |
| Listing | 138 px |
| Settings | 160 px |
| Tickets | 171 px |
| Home · Liquid | 216 px |
| Home · Editorial Market | 364 px |

Send and Receive — the two screens where a fold costs you money — **fit with the action visible and the whole
breakdown above it.** The rest is the honest cost of the chosen directions: a 4:5 Gallery flyer on Tickets, a 4:5
Editorial hero on Home and Listing, and grouped lists on Settings where every row now clears 44 px.

### One thing the red audit caught

The prototype's own text claimed "discovery carries no red", and the **filter sheet's apply button was red** — so the
claim was false inside that overlay. Applying a filter commits nothing, so it has no claim on the colour. That button
and the bid-status sheet's navigational action are now neutral glass (contrast 10.21:1), which makes discovery
genuinely red-free and leaves red meaning exactly one thing: *you are about to move money or destroy something.*

### Not verified

- **No device check, no screenshots** (standing preference: text-only verification). This is a desktop browser at a
  phone-shaped frame; no screen here has been rendered on a handset by me.
- The condensed face falls back to a system stack; Oswald is not loaded.
- Nothing applied, built, deployed or tagged. No build requested. No sandbox or production access. C's
  handset-test files and the transfer/proof implementation were not touched.

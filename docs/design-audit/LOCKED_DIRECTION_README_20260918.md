# Snatch It — locked direction (B, 2026-09-18)

**File:** `docs/design-audit/prototypes/snatch-it-locked.html` — one self-contained interactive prototype.
Open it directly: no server, no build, no network request. Artwork is generated in SVG from a seeded PRNG.

This is the prototype the direction is locked against. It supersedes `chrome-signal.html` (a single app-wide
hybrid) because the direction is now **per screen**, as chosen.

---

## 1 · Screen map — the locked direction for each surface

| Screen | Locked direction | Where Liquid appears |
|---|---|---|
| **Home** | **B · Editorial Market** — the market made visible | The floating view selector and the filter sheet only |
| **Home · alternates** | **4 · Liquid** and **N1 · Ticket Stub**, as *view modes inside Home* | Liquid mode: rounded media and Apple's 35% dimming layer under text over art |
| **Listing detail** | **B · Editorial Market** hierarchy **+ 4 · Liquid** | Image treatment, the photo and bid overlays, and the rounded glass CTA |
| **Bids** | **R · Gallery / Ledger** | None — Bids has no bottom action |
| **Tickets** | **1 · Gallery** — the flyer does the talking | None |
| **Send transfer** | **5 · Utility** structure **+ 4 · Liquid** CTA | The rounded glass CTA and the confirmation sheet |
| **Receive transfer** | **2 · Index** structure **+ 4 · Liquid** CTA | The glass CTA, the quiet secondary under it, and the dispute sheet |
| **Checkout** | **1 · Gallery** hierarchy **+ 4 · Liquid** CTA | The rounded glass CTA only |
| **Profile** | **4 · Liquid** | Grouped 14 px lists, glass navigation, chrome ring on the avatar. No bottom CTA |
| **Settings** | **4 · Liquid** | Grouped 14 px lists and glass navigation. No bottom CTA |

The three Home views are **three ways to read one feed, not three themes**: switching to Liquid or Ticket Stub
changes Home and nothing else. Every other screen keeps its own locked direction.

### How each direction shows up, concretely

- **Editorial Market (Home).** A 4:5 poster hero carries the market — live state, name, date and venue, price —
  with the elapsed share of the auction's final six hours on a meter directly beneath it. Then "Ending soon",
  populated strictly by real remaining time, then the rest of the week as a thumbnail list.
- **Editorial + Liquid (Listing).** Editorial's information order is untouched: eyebrow, name, commitment panel
  (current bid at 22 px, bid count, minimum next bid, live state, six-hour meter), fact table, commitment line.
  Liquid appears three times only — the dimmed hero, the two overlays, the glass CTA.
- **Gallery / Ledger (Bids).** Image-led rows with ledger discipline: 4:5 thumbnail, event, status as a chrome or
  amber chip, your bid in a right-aligned tabular column with the live state beneath it. Grouped "You're leading"
  and "Needs you". No filled action anywhere.
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

## 2 · The Liquid rule, as implemented

**Liquid means a rounded translucent CTA anchored at the bottom, plus restrained overlays and image treatment. It
never replaces a screen's layout.**

- **Four screens have a bottom glass CTA:** Listing, Send, Receive, Checkout. 20 px radius, 52 px tall, one inner
  specular highlight, a light 1 px border, and a red glow beneath.
- **Five screens have none:** Home, Bids, Tickets, Profile, Settings keep the dock and nothing else.
- **Glass is confined to navigation and overlays** — verified by scanning computed styles per screen: nav bars, the
  dock, floating on-art controls, the Home view-selector pills, the neutral and quiet CTAs, and the sheets.
  **Zero content-layer glass on any screen.**
- **Readability above the CTA:** content scrolls under the bar with 104 px of matched bottom padding and a 34 px
  scrim above it, so the last line of a price breakdown is never trapped behind glass.
- **One correction worth naming.** The primary CTA was drawn as translucent red. Measured, `rgba(208,10,10,.86)`
  composited over the canvas gives black text **2.96:1** — and even solid `#E00E0E` is only 4.24:1. A red CTA
  cannot be both translucent over a dark backdrop and legible. **The primary fill is now brand `#FF1A1A` at full
  strength (5.41:1)** with the specular highlight, border and shadow carrying the depth; translucency and blur
  stay on the neutral and quiet buttons, where the text is light on dark.

---

## 3 · Final recommendation — the shared system

**Spacing.** One 4 pt base, six steps: **4 / 6 / 9 / 12 / 16 / 22**. A direction picks its rhythm from those steps
and never invents a value between them.

| Direction | Section / block rhythm | Row padding |
|---|---|---|
| Gallery | 18 / 26 | 11 px |
| Editorial | 16 / 22 | 10 px |
| Liquid | 14 / 20, 14 px grouped corners | 9 px |
| Ledger | 14 / 19 | 9 px |
| Utility · Index | 12–13 / 16–17 | 7 px |

**Typography.** One scale everywhere, no exceptions: hero 21–22 · screen title 16 · item name 14.5 · body 13 ·
small 11.5 · micro 10 · price 16 · dominant price 22. A **condensed display face for names on Editorial and Index
only** — the two directions whose identity is typographic; everywhere else names use the system sans. Every figure
tabular. Micro labels are the only uppercase in the product, at 10 px / 0.09 em.

**CTA treatment.** Glass CTA on the four screens named above, 20 px radius, 52 px tall, opaque red fill with a
specular highlight. Flat 2 px actions everywhere else. One filled action per screen, its consequence on its own
sub-line, and a disabled action states its reason in the same place. Destructive is outlined, never filled.

**Chrome accents.** Five places and no more: the wordmark, the 1 px top edge on nav bar / action bar / dock, the
selected-tab indicator, the inner highlight on a CTA, and the ring on the profile avatar. **Status colour is
chrome for live and leading, amber for attention, green only for a confirmed payment state.** Red is reserved for
the primary action and destructive states, so discovery contains none of it — the ending-soon pill is amber.

**Motion.** Reduce Motion is the default and the shipping baseline. With motion on: screen change rises 4 px over
200 ms; sheets translate 14 px over 260 ms; a Home view switch crossfades at 200 ms; a changed bid value dips once.
Never on a warning, never on a per-second tick, and never delaying an action's result.

---

## 4 · Unresolved visual decisions

| | Decision | What the prototype does | Why it needs a ruling |
|---|---|---|---|
| 1 | **Red for destructive** | Destructive is outlined, never filled; red is absent from discovery | Reverses the direction approved 14 Sep. D is carrying it as an A-or-B |
| 2 | **Corner radius** | Content stays at 0; Liquid brings 14 px grouped lists, 16 px media, 20 px CTA | "Radius 0 is identity" is a stated rule. Liquid cannot exist without curvature |
| 3 | **Green** | Green only on a confirmed payment state; status and live are chrome or amber | If payment confirmation counts as status, green leaves the product |
| 4 | **Condensed face** | Names on Editorial and Index only; the prototype falls back to a system condensed stack | Two faces by role is a system commitment, and Oswald will set differently from the fallback |
| 5 | **Blur without a build** | Every glass surface assumes a real backdrop blur | Neither `expo-blur` nor `expo-glass-effect` is installed. Without an authorised build the glass ships as a solid translucent fill |
| 6 | **Gallery on Tickets** | One 4:5 flyer per ticket, so the second sits 171 px below the fold | The most beautiful Tickets screen and the least scannable. A wallet of eight tickets may want Ledger |
| 7 | **Home mode persistence** | Session state, resets to Editorial Market | Whether a chosen view is remembered per person, and whether it syncs, is a product decision |
| 8 | **Where the direction label lives** | Outside the phone, on the plate under the device | Deliberate: no review tooling inside a frame meant to read as the app |

---

## 5 · Verification — measured in the browser, 2026-09-18

| Check | Result |
|---|---|
| Screens rendered (9 screens + 3 Home views) | **12 / 12**, zero JavaScript errors |
| Flows exercised | place bid → leading · mark as sent → payout pending · confirm receipt → released · pay → receipt · Home mode switch · filters · 7 sheets — **all pass** |
| Direction tokens applied per screen | editorial · editorial · ledger · gallery · utility · index · gallery · liquid · liquid — **as locked** |
| Glass CTA present | Listing, Send, Receive, Checkout — **and nowhere else** |
| Content-layer glass | **zero** on all nine screens |
| Filled red elements | **exactly one** on each of Listing, Send, Receive, Checkout; **zero** on Home, Bids, Tickets, Profile, Settings |
| Contrast, alpha-composited over each real surface | CTA label **5.41** · CTA sub-line **4.76** · quiet CTA **8.82** · small text **4.68** · micro **4.68** · rail detail **4.68** · amber pill **11.71** · chrome pill **10.55** — all ≥ 4.5; the decorative chevron is 3.56, above the 3:1 required of a non-text control |
| Tap targets under 40 px | **zero**, including inside all seven sheets (chips, view pills, switches, segmented control and grouped rows all carry a 44 px hit area behind a smaller ring) |
| Animations with Reduce Motion on | **zero** |
| Essential content present (recipient · delivery · proof · deadline and consequence · payment state · full breakdown) | **0 missing** across Listing, Send, Receive, Checkout |
| Home indicator drawn on every screen | **9 / 9**, and every CTA clears it |

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
breakdown above it.** The rest are the honest cost of the chosen directions: a 4:5 Gallery flyer on Tickets, a 4:5
Editorial hero on Home and Listing, and grouped lists on Settings where every row now clears 44 px. Settings grew
57 px when the tap targets were corrected; that trade is the right way round.

### Not verified

- **No device check, no screenshots** (standing preference: text-only verification). This is a desktop browser at a
  phone-shaped frame; no screen here has been rendered on a handset by me.
- The condensed face falls back to a system stack; Oswald is not loaded.
- Nothing applied, built, deployed or tagged. No sandbox or production access. C's handset-test files and the
  transfer/proof implementation were not touched.

**React Native implementation requirements** are unchanged from the previous pass and still stand:
`CHROME_SIGNAL_README_20260917.md` §4 — tokens in two mirrored files, five primitives (`Notice`, `StickyBar`,
`StatusRail`, `PriceTable`, `LiveState`), one pure `liveBid.ts`, and the three chrome effects that want a build.
The only addition from this pass is that the **bottom glass CTA becomes a variant of `StickyBar`**, not a new
component, and that its primary fill must be opaque for the contrast reason in §2.

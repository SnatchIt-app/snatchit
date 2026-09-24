# B — visual implementation review, Build 24 vs the approved boards

**Method.** Earlier V3 reviews reported visual PASS from tokens, source and computed contrast. That is not a
visual review and **those PASSes are withdrawn.** This compares **rendered output** — the owner's Build 24
screenshots — against the references in `V3_SCREEN_TO_BOARD_MAP.md`.

**Under test:** Build 24 `c5b3a615-ff97-4a88-a4ce-2dae24558478`, commit `404bce38`.
**Images:** `comparisons/cmp_home.png`, `cmp_listing.png`, `cmp_bid.png`.

**Measurement rules applied after the owner's correction:**
- Dimensions are quoted **only in logical units taken from the renderer or the spec**. Nothing in this
  document converts screenshot pixels into points.
- Size and whitespace comparisons are **not** made until the two frames are normalised for viewport, safe
  area and the sandbox banner. Claims that needed that normalisation and have not had it are marked
  **[not normalised]** and carry no number.
- The boards are the target. They are not redrawn to match the app, and no approved choice is reopened.

---

## 1 · Systemic gaps — three, and radius is only one of them

### S1 · The chrome radius token does not exist

Approved 2026-09-22: *"the rounded controls shown in the approved V3 designs"*, radii **by component role** —
0 rules, **8 media**, **22 chrome** (buttons, chips, sheets, search field), 33 dock.

`src/theme/v2.ts:150` still reads `radius = { none: 0, pill: 9999 }`. `Button:175`, `Chip:86`, `Input:95`,
`Sheet:125`, `Badge:81` all set `v2.radius.none`. **Actions, chips, fields, sheets and badges are square.**

### S2 · The media radius is **partially** implemented — correction

**I withdraw "every thumbnail is square."** `slots.ts` applies `ROW_ART_RADIUS` (8) to **`FEED_ROW_ART`**,
which is correct and is what the home rows use. The slots still at `v2.radius.none` are:
**`DISCOVERY_CARD`, `SEARCH_RESULT`, `HOME_FEATURE_V3`, `LISTING_HERO_V3`, `CHECKOUT_THUMBNAIL`** and the
other legacy slots. So this is a named, partial gap, not a blanket one.

### S3 · Colour roles used outside their definitions

Foundations defines `brand.red` as **"primary action fill · BLACK label"**. Build 24 renders the **editable
bid amount** in red (a value, not an action) and the **+$5 / +$10 / +$25 chips** with a red outline *and* a
dark-red fill. Meanwhile the listing's own primary action is **not** red (§3.2).

### S4 · Screen-title case

The bid reference draws **"Place bid"**; Build 24 renders **"PLACE BID"**.

---

## 2 · Corrections to my own previous draft

| Claim | Status |
|---|---|
| "Radius is the root cause of the majority of the mismatch" | **Overstated.** It is one systemic gap of several; composition and colour-role gaps are independent of it |
| "Every thumbnail is square" | **Withdrawn** — see S2 |
| Dock avatar "overflows the dock's top edge and is clipped" | **Withdrawn — my crop artefact.** Re-cropped with generous bounds: the circle sits wholly inside the dock |
| "The 'You' label overlaps the avatar" | **Withdrawn — same artefact.** The label sits below the ring |
| "The avatar ring is red" | **Split.** The **dock** ring renders **white**, which is correct — the nav board reserves red. The **profile screen's** avatar ring and edit badge are red; that is a different surface, governed by `pkg8-account-tickets-dark.png`, **which I have not yet compared. No finding there yet** |
| Bid entry "≈25% of the screen is empty" | **Number withdrawn** — [not normalised] |
| "Section headings Tonight / This week are missing" | **Withdrawn as a defect.** The boards draw them but no package text defines the grouping rule, and a heading like "Tonight" needs **matching data**, not a hard-coded label over future listings |
| Bid entry "'Starting bid' should read 'Current bid'" | **Withdrawn.** *"Starting bid"* is **correct at zero bids**. The board says "Current bid" only because its sample has six |

**Dock geometry verified from the renderer and matching the approved sheet:** `ITEM_W 66`, `DOCK_HEIGHT 66`,
`DOCK_RADIUS 33`, `AVATAR 28`, `ICON_ACTIVE 28`, ring 1.6pt at 2.5pt outside, `contentFit="cover"`, 12%
unselected blend, label below. **No geometry defect in the dock.**

---

## 3 · Confirmed discrepancies, for implementation

### 3.1 · Bid entry — ref `pkg7-bid-after-raised.png`, tokens `pkg8-bid-dark.png`

| # | Category | Reference | Build 24 |
|---|---|---|---|
| B1 | colour role | Amount in `text.primary` (white) | Amount in **red** |
| B2 | colour role + radius | Quick-add chips: neutral outline, white label, chrome radius | **Red outline, dark-red fill, red label**, square |
| B3 | radius | Steppers rounded (chrome role) | Square |
| B4 | composition | "Minimum … · $5 steps" sits **above** the chips, under the amount | Sits **below** the chips; "· $5 steps" dropped |
| B5 | composition | The reference figure is a **labelled row with a hairline above and below**. *(The label "Starting bid" is correct here — zero bids)* | An inline sentence, no row, no rules |
| B6 | typography | Two decimals | No decimals |
| B7 | composition | Summary sits in a **filled `surface.panel` block** | Bare rows on the canvas |
| B8 | composition | Summary follows the commitment line closely | A large empty band above the summary — **[not normalised]**, reported as present, not measured. The owner's bid-summary direction required this gap removed |
| B9 | radius + typography | CTA rounded, "Place bid" mixed case | Square, "PLACE BID" uppercase |

### 3.2 · Listing detail — ref `midnight-listing-clean.png` + `pkg7-listing-after.png`

| # | Category | Reference | Build 24 |
|---|---|---|---|
| L1 | image/fallback | Full-bleed hero with scrim; date and name **over** the artwork | Hero collapses; name and date fall onto the canvas below. See §4 |
| L2 | **hierarchy** | **Owner ruling 2026-09-23: Buy now is PRIMARY** (this overrides every listing board, which still draw bid-primary) | A single **outlined, non-red** "PLACE A BID". **No buy-now primary is visible at all**, and the primary action carries no red |
| L3 | **alignment — render failure** | — | The sticky bar's right-hand text is **clipped**: "all-in, ends t…" |
| L4 | composition | Delivery and Seller are label/value rows inside the bid-minimum block | A **SELLER row with an avatar**, plus a **"THE TICKET"** section (Type/Quantity/Delivery) that exists on **no board** |
| L5 | composition | "all-in" lives in the panel's meta line | "**$110 total**" — "total" appended beside the amount |
| L6 | radius | Back control is a circular chip | Square |

### 3.3 · Home — ref `midnight-home-clean.png` (owner-approved)

| # | Category | Reference | Build 24 |
|---|---|---|---|
| H1 | composition | SN logo **left**, search right. **No city row and no filter chips** | Logo **centred**; a "MIAMI" row; three filter chips above the feed |
| H3 | image/fallback | Missing artwork is a **plate (`surface.plate`) carrying the SN monogram** — drawn on the board's third row | A **letter glyph** on a grey tile; and with no image the **feature loses its hero treatment entirely** |

### 3.4 · Dock and profile

| # | Status |
|---|---|
| P3 | **Confirmed, cause not diagnosed.** The dock avatar renders as a red field over a dark band. The profile screen's avatar for the same account shows red over a pale block. The dock is therefore **not showing what a centre-crop of that image would show.** The renderer already sets `contentFit="cover"` and requests a 28pt-wide URL via `getAvatarUrl`, so the cause is **not** visible from appearance — candidates are the sized-URL transform, the stored asset, or the source crop. **I am not prescribing a fix**; C should instrument the resolved URL and the intrinsic image before changing anything |

---

## 4 · The no-image case, treated as deliberately as the photographic one

The sandbox has no artwork, so **every screenshot is the no-image case** — which makes it the best-evidenced
part of this review, not a caveat.

The approved treatment is a **plate** (`surface.plate` `#141519`, media radius) carrying the **SN monogram**,
drawn on the third row of `midnight-home-clean.png`. It is a *filled slot*, not an absence.

Build 24 instead: uses a **letter glyph** in place of the monogram; and on the listing hero and the home
feature, **the missing image changes the layout** — the hero collapses and the name and date relocate from
over-artwork to on-canvas. **A missing image must fill the slot, not resize it.**

---

## 5 · Not yet compared — no visual PASS exists

Search, Checkout, Sell/Create, My listings, Tickets, Orders, Transfers, Settings, Auth, the profile screens,
every dialog and every state screen. Boards exist for most; renders do not. **I will not issue a PASS for any
screen I have not compared as a render.**

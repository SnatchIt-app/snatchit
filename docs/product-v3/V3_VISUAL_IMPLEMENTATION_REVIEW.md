# B — visual implementation review, Build 24 vs the approved boards

**Method corrected.** Everything before this document reviewed tokens, source and computed contrast, and
reported visual PASS from them. **That was not a visual review and I withdraw those PASSes.** This document
compares **rendered app output** — the owner's Build 24 screenshots — against the approved boards. Where I
have not compared a render, the row says so.

**Under test:** Build 24 `c5b3a615-ff97-4a88-a4ce-2dae24558478`, commit `404bce38`.
**Comparison images:** `docs/product-v3/comparisons/cmp_home.png`, `cmp_listing.png`, `cmp_bid.png`.

**The boards are the target. They are not redrawn to match the app.**

---

## 0 · The headline: the appearance migration was presented as V3 implementation. It is not.

The migration swapped **colour tokens**. It never touched **geometry, composition or the type case**. That
is why the screens resolve the right colours and still do not look like the boards.

---

## 1 · Systemic — these cause most of the per-screen failures

### S1 · The V3 radius amendment was never implemented. The tokens do not exist.

`pkg1-foundations.png` (approved foundations) specifies four radii and carries an explicit amendment,
**"'Square is the brand' is narrowed, not deleted"**:

| Radius | Applies to |
|---|---|
| **0** | rules, dividers, hairline fields — unchanged |
| **8** | **media** — artwork thumbnails and plates |
| **22** | **chrome** — buttons, chips, sheets, search field |
| 33 | the floating dock (already shipping) |

At `404bce38`, `src/theme/v2.ts:150` still reads **`radius = { none: 0, pill: 9999 }`**. There is no `media`
and no `chrome` token. `Button:175`, `Chip:86`, `Input:95`, `Sheet:125`, `Badge:81` all set
`v2.radius.none`. **Every action, chip, panel, field and thumbnail in Build 24 is square.**

This single gap accounts for the majority of the visual mismatch on all four screens.

### S2 · Screen-title case

The bid board draws the title **"Place bid"** in mixed case. Build 24 renders **"PLACE BID"**. The
foundations board keeps `displaySm` uppercase for *short structural screen titles* and adds a mixed-case
display role for sentence headings. Which bucket each title falls in needs the approval history (§4).

### S3 · Colour roles are being used outside their definitions

Foundations defines `brand.red` as **"primary action fill · BLACK label"**, and the nav board states plainly:
**"Red is not used — it is reserved for primary actions, destructive actions and the brand mark."**

Build 24 uses red for the **editable bid amount** (a value), the **+$5/+$10/+$25 chips** (outline *and*
fill), the **profile avatar ring**, the **"MIAMI"** city label and **"SETTINGS"**. None is a primary action.

---

## 2 · Per screen

### 2.1 · Bid entry — `pkg8-bid-dark.png` · image `cmp_bid.png`

| # | Category | Board | Build 24 |
|---|---|---|---|
| B1 | **colour role** | Amount in **white** `text.primary` | Amount in **red** |
| B2 | **colour role + radius** | Quick-add chips: neutral outline, white label, radius 22 | Red outline, **dark-red fill**, red label, square |
| B3 | **dimensions + radius** | Steppers ~200pt tall, radius 22 | Small squares, ~35% the height |
| B4 | **composition** | "Minimum $95.00 · **$5 steps**" sits **above** the chips, under the amount | "Minimum $105" sits **below** the chips; "· $5 steps" dropped |
| B5 | **composition** | Reference is a **labelled row** — "Current bid … $90.00" — with a hairline above and below | An inline sentence "Starting bid · $100", no row, no rules |
| B6 | **typography** | Two decimals — `$95.00` | No decimals — `$105` |
| B7 | **composition** | Summary sits in a **filled `surface.panel` block** | Bare rows on the canvas, no panel |
| B8 | **composition** | Modest gap above the summary | **~25% of the screen is empty.** The owner's bid-summary direction explicitly required the large empty gap removed |
| B9 | **radius + typography** | CTA is a red **pill**, "Place bid" mixed case | Red **square**, "PLACE BID" uppercase |

### 2.2 · Listing detail — `pkg8-listing-dark.png` · image `cmp_listing.png`

| # | Category | Board | Build 24 |
|---|---|---|---|
| L1 | **image/fallback** | **Full-bleed hero artwork** with scrim; date line and name sit **over** it | Hero collapses to a **small grey letter on black**; name and date fall onto the canvas below |
| L2 | **sticky action + colour role** | Two stacked CTAs in flow: red **pill** "Place a bid" with sub-line "minimum $104.50 all-in", then outlined **pill** "Buy both now · $132.00" / "ends the auction" | A **sticky bar**: square **outlined, non-red** button flanked by two text fragments |
| L3 | **alignment — outright failure** | — | The sticky bar's right text is **clipped**: "all-in, ends t…" |
| L4 | **composition** | Delivery and Seller are label/value rows **inside** the "if you bid the minimum" block | A **SELLER row with an avatar**, and a separate **"THE TICKET"** section (Type/Quantity/Delivery) that exists on no board |
| L5 | **composition** | Panel reads "CURRENT BID / $99.00", with "all-in" in the meta line | "STARTING BID / **$110 total**" — "total" appended beside the amount |
| L6 | **radius** | Back button is a **circular** chip over the artwork | Square chip |

### 2.3 · Home — `pkg8-home-dark.png` · image `cmp_home.png`

| # | Category | Board | Build 24 |
|---|---|---|---|
| H1 | **composition/alignment** | SN logo **left**, search right. No city row, no filter chips | Logo **centred**; an extra "MIAMI" row; three filter chips. **Pending §4** — chips may come from an earlier approved board |
| H2 | **composition** | Section headings **"Tonight"** and **"This week"** | **Absent** |
| H3 | **image/fallback** | Feature is full-bleed artwork; the approved missing-artwork treatment is a **plate (`surface.plate` #141519, radius 8) carrying the SN monogram** — visible on the board's third row | Feature becomes a **~470px empty black area** with a small grey letter. **Not the approved fallback, and the layout changed because the image is missing** |
| H4 | **image/fallback + radius** | Row thumbnails: artwork at radius 8 | Square grey tiles with a letter glyph |

### 2.4 · Profile and the dock — `compare-profile-nav.png`

The dock is specified exactly: a **28pt circle inside the 66×66 item**, centre-cropped `contentFit="cover"`,
**"the crop never shifts between states"**, selection carried by the capsule plus a 1.6pt ring, label "You"
**under** the icon, and **red not used**.

| # | Category | Board | Build 24 (both screenshots) |
|---|---|---|---|
| P1 | **dimensions — outright failure** | Circle sits wholly inside the item box | The avatar **overflows the dock's top edge and is clipped by it** |
| P2 | **alignment — outright failure** | Label sits **below** the icon | The **"You" label overlaps the avatar** |
| P3 | **image treatment** | Centre-crop, recognisable in both states | Renders as a red/dark band — not a centre crop |
| P4 | **colour role** | "Red is not used" in the dock | Avatar ring is red. **Pending §4** — the profile *screen* board may differ from the nav board |

---

## 3 · What I have NOT yet compared

Search, Checkout, Create/Sell, My listings, Tickets, Orders, Transfers, Settings, Auth, and every state
screen. **No visual PASS exists for any of them.** Boards exist for most; renders do not.

## 4 · Open until the approval history lands

A read-only trace of the approval record is running. Four items above depend on it and are marked
**pending**: the home header composition (H1), the profile avatar ring (P4), the bid-entry commitment
sentence — Build 24's wording may be the owner's *later* correction rather than a deviation — and whether
each screen title is "structural" (uppercase) or a sentence heading (mixed case) under S2.

**The screen-to-board map is not published yet.** Publishing it before the approval history is resolved
would be exactly the error the owner called out: selecting a superseded board as the reference.

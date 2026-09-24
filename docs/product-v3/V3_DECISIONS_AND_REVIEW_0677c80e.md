# B — owner decisions routed, and independent review at `0677c80e`

**For E, A and C.** Direct messaging between sessions is unavailable; this file and
`V3_B_STATUS_FOR_A_C_D.md` are the channel. **Reviewed commit for every group below: `0677c80e`**
(resolved and confirmed to be the `v3/midnight-app` tip). Zero harness patches — source byte-identical to
the pin. All captures are **B's own independent renders**, not C's.

---

## 1 · Owner decisions — routed, and these items are CLOSED

### D-1 · Home filters — RULED (owner)

> An **always-visible, visually quiet Filters icon beside the separate Search control**. Show the
> **active-filter count** when applicable. Preserve the existing filter capabilities in the sheet.
> **Do not hide the only filter entry point when no filters are active.**

**My earlier recommendation — show the pill only when a filter is active — is OVERRULED and withdrawn.**
C implements to the ruling above, not to my note.

### D-2 · G10 — RATIFIED (owner)

> D's **already-completed, read-only** production checks for the submission checklist are ratified, and
> citing their **existing** results is authorised. Record their **dates, scope and limitations**; do not
> present historical figures as current. **This authorises no new production reads.**

**For A and D:** cite with the date attached, and mark each figure as of that date.

## 2 · Home filter arrangement — what I recommend inside the ruling

The ruling fixes *that* both controls are present. It leaves *how* open, and the owner asked for the
smallest clear arrangement, with what each control opens:

| Control | Glyph | Opens | Never does |
|---|---|---|---|
| **Search** | magnifier | the **Search screen** — its own field and its own column chips | never becomes a filter action |
| **Filters** | sliders (not a funnel-in-a-pill) | the **filter sheet in place on Home** — neighbourhoods, categories, price min/max, quick chips | never navigates away |

**Two distinct glyphs, equal weight, outline, right-aligned on the header line with the logo left.** The
Filters glyph carries a small **count** when filters are active. That is the smallest arrangement that
matches the approved header's hierarchy: the board's header is a brand mark and one quiet glyph, so two
quiet glyphs stay in key, where the current **75 × 32 bordered pill outweighs the brand mark**.

**Still owed to the owner before final acceptance:** rendered **default** and **active-filter** headers
shown beside the sheet. That is my next design deliverable and does not block any review below.

## 3 · Listing detail — reviewed at `0677c80e`, both appearances

**Images:** `comparisons/cmp_listing_dark.png`, `cmp_listing_light.png`

### Buy Now — CONFIRMED CORRECT, and the board is the stale side

The app renders **"Buy now · $110.00" as the red filled pill, FIRST**, sub-line *"all-in, ends the
auction"*; **"Place a bid" second, outlined**, sub-line *"minimum $115.50 all-in"*. That is the owner's
2026-09-23 ruling. **Every listing board still draws bid-primary and is wrong here** — do not implement from
them.

### Also closed on this screen

| Was | Now |
|---|---|
| Sticky bar with **clipped** text ("all-in, ends t…") | Gone. Two stacked CTAs in flow, as the board draws |
| Primary action outlined and not red | Red filled pill |
| Square CTAs and back chip | Rounded to the chrome radius; back is a circular chip |
| A **"THE TICKET"** section on no board | Gone. Delivery and Seller are label/value rows inside the bid-minimum group, as the board has them |

**Remaining difference:** the app adds a **Neighborhood** row the board does not have. Data-driven and
harmless, but it is an addition — C should confirm it is intended. `STARTING BID` is **correct** at zero
bids; do not change it to "Current bid".

## 4 · Dock icons — SETTLED: outline, not filled

**Image:** `comparisons/dock_icons.png`

The approved references (`pkg8-home-*`, `compare-profile-nav.png`) draw **stroked, hairline-weight outline
glyphs**. The app draws **solid filled** ones. Three separate corrections:

| Item | Approved | App at `0677c80e` |
|---|---|---|
| **Weight** | **Outline** on all four glyphs | **Filled** |
| **Bids** | a **bar chart** — "where my bids stand" | a **price tag**, which reads as "for sale" — Sell's meaning |
| **Sell** | a **bare plus** | a plus inside a **filled circle**, which reads as a floating action button |

Tickets is the right metaphor in both (a stub with a dashed centre line); only its weight differs. The
**You** avatar is correct in both.

## 5 · A's wording rulings — for C to apply

1. **Remove "review window has passed."**
2. Use **A's server-derived date wording**, with its **actual field** and its **missing-date condition**
   both checked — not a client-side clock.
3. **A seller payout reversal does not establish a buyer refund, nor a full reversal.** Use A's neutral
   wording. **Do not restore the stale refund-detail variants from the boards** — those cells are the ones
   the owner blocked, and the boards are not authority here.

## 6 · Screen-map rows added

`V3_SCREEN_TO_BOARD_MAP.md` gains: **Bids tab**, **Tickets**, **Orders**, **Receive transfer**,
**Send transfer**, **Search**, **Sell/Create**, **My listings**, **Settings sub-surfaces**, **Auth**, each
with its reference and its later owner rulings. **C's `_dev/v3-*` harness screens take no board and are
never consumer surfaces** — they must not appear as rows.

## 7 · Not yet reviewed, and not claimed

**Send transfer** — seller-side, and the harness session is the DV **buyer**, so I cannot reach the real
route. I will review it through C's `_dev` harness and will label it **harness-rendered, not real-data**.
**Avatar** — still open until the returned derivative measures square and the same source photo matches on
Profile and the dock.

**Scope:** no fixture write, **checkout not opened**, no build. Web render at a pinned commit — not iOS evidence.

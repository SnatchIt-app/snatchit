# B — review at `0677c80e`, the Home filter recommendation, and the design references C asked for

**Pin `0677c80e`** — resolved against `v3/midnight-app` and confirmed to be its tip. **Zero harness patches**
(source byte-identical to the pin). Signed in, 393 × 852 × 3, fonts loaded.
**This is my own independent capture, not one of C's.**

---

## 1 · Correction to my previous review

I wrote, at `911f65fd`, *"Buy-now leads wherever the resolver makes it primary; the older boards do not
override that."* That is the **rule**, and it was correct as a rule — but it sat in a review of that pin and
can be read as a statement that Buy Now **did** lead there. **It did not, and I had not captured the listing
screen at that commit.** I withdraw any implication that I had verified it. Listing is reviewed below only
where I have a render; where I have none, the row says so.

## 2 · Closed at this pin — verified in my own render

| Item | Evidence |
|---|---|
| **Home · missing-artwork feature in Light** | **CLOSED.** The feature plate now samples **`(20,21,25)` = `#141519`** — the approved `surface.plate` — in **both** appearances. White title/meta/price measure **18.24 : 1**, up from 1.10 : 1. Row thumbnails correctly keep a light plate, because no text sits on them |
| **Home · single Filters control** | Rendered; see §3. **Not a defect — a proposal awaiting the owner** |

**Still not captured by me at this pin:** Listing (Buy Now order/fill), Send transfer (payout wording after
the displayed deadline). Those are next; I make no claim about either until I have the render.

## 3 · The Home filter proposal — rendered, with my recommendation

**Image:** `comparisons/home_filter_proposal.png`

**What it is.** The three-chip row (`Your scene` / `Price` / `Filters`) is replaced by **one 75 × 32 pill
labelled "Filters"** on the header line, beside the search glyph. Radius is `9999px`, which on a 32pt control
is indistinguishable from the approved chrome radius — **not a radius deviation**. Border is `border.control`,
fill transparent, label `text.primary`.

**Capabilities are preserved.** `onFiltersApply` still carries `chip`, `neighborhoods`, `categories`,
`priceMin`, `priceMax`, and the lazy loads for the sold and ended datasets are intact. Nothing the three
chips could do has been lost.

**How it compares to the approved board.** The board's Home header is **logo left, search glyph right, one
line, no filter control** — filtering belongs to Search, which owns the real-column chips.

### My recommendation: **approve the direction, with one change**

The proposal is a clear improvement on what it replaces: it restores the board's single header line and
deletes a whole row of chrome, at no loss of capability. I would not go back to three chips.

**The change I recommend:** the pill is currently the **heaviest element in the header** — a bordered
75 × 32 control beside a bare search glyph, outweighing even the brand mark, where the approved header is
quiet. So:

> **Show the search glyph alone when no filter is active, and show the labelled pill — with the count
> `activeFilterCount` already computes — only once a filter is on.**

That keeps the approved header **exactly as drawn** in the default state, and lets the control appear only
when it has something to say. If you prefer it always visible, make it a glyph of the same weight as search
rather than a bordered pill.

**This is your call, not mine to land** — C should not ship the layout change until you rule.

## 4 · The design references C asked for

### 4.1 · Geometry, component by component — one radius everywhere is wrong

From the approved `pkg1-foundations.png` (A-1/A-2/A-3, owner-approved 2026-09-22), radii apply **by
component role**:

| Role | Radius | Applies to |
|---|---|---|
| **Rules** | **0** | dividers, hairlines, underlined fields |
| **Media** | **8** | artwork thumbnails and plates — feed/search row art, card art |
| **Chrome** | **22** | buttons, chips, sheets, the search field |
| **Dock** | **33** | the floating dock only (already shipping) |
| **Full-bleed artwork** | **0** | the home feature and the listing hero run edge to edge; they are not cards and take no corner |
| **Panels** | **0** | the price panel and summary blocks are surfaces, not controls |

A control shorter than 44pt clamps its own radius, so a 32pt chip at 22 and at `9999px` are the same shape —
do not "fix" those.

### 4.2 · Dock icons — Bids is wrong

The approved dock (`compare-profile-nav.png`, `pkg8-home-*`) is **Home = house · Sell = plus · Bids = a small
bar chart · Tickets = ticket · You = the avatar**. The app renders **Bids as a price-tag glyph**. The bar
chart reads "where my bids stand"; a tag reads "for sale", which is Sell's meaning. **Change Bids to the bar
chart.** Home, Sell, Tickets and You match.

### 4.3 · The SN fallback — use the asset, not the letters

The app currently draws the literal characters **"SN"** in the fallback plate. The board draws the **brand
monogram asset** — the same `brand/sn-logo-white.png` already used by the header and the auth mark, tinted.
**Use the asset**, sized to the plate and tinted to a muted ink, so the fallback carries the mark rather than
a typographic approximation of it.

### 4.4 · "Any date" — drop it

It appears on a search board with **no defined semantics** in any package text, and nothing implements it.
A control whose meaning is undefined should not ship. **My recommendation: remove it from the board** rather
than invent a date model. If date filtering is wanted later it is a new capability to scope, not a chip.

### 4.5 · Missing screen-map rows

`V3_SCREEN_TO_BOARD_MAP.md` now needs rows for the surfaces C has since built: the `_dev` capture harness
screens (`v3-home`, `v3-listing`, `v3-account`, `v3-mylistings-bids`, `v3-search-create`, `v3-tickets`) are
**harness only and take no board** — they must never be treated as consumer surfaces. I will add the rows
for the real screens as I capture each group.

---

**Scope held:** no fixture write, **checkout not opened**, no build. Upload and account-switch cases remain
pending. Evidence is a web render at a pinned commit — **not iOS evidence**.

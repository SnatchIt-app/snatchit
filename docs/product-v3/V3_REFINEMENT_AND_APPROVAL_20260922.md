# Snatch It V3 — refinement and visual approval package (B, 2026-09-22)

**Deliverables:** 20 static design mockups in `docs/product-v3/mockups-v2/` — Home, Search, Listing and Order in
**Midnight** (leading) and **Paper** (alternative), each as a **clean phone-only image** and a **separately annotated
image**, plus four state examples. No HTML, no prototype, no production change, nothing committed.

**One consistent fictional purchase runs through every screen:** *Neon Choir*, Lantern Room, Fri 24 Oct 19:30 —
**2 × GA sold together**, current bid **$99.00 all-in**, and the order is that same purchase after the auction.

| File pattern | What it is |
|---|---|
| `{midnight,paper}-{home,search,listing,order}-clean.png` | Phone only. Nothing but the screen |
| `{midnight,paper}-{home,search,listing,order}-annotated.png` | The same screen with numbered gutter markers and notes |
| `midnight-home-loading.png` · `midnight-search-empty.png` · `midnight-listing-error.png` · `midnight-order-unreachable.png` | State examples |

---

## 1 · The six fixes

### 1. Identity
The **real brand asset** is composited into every screen: `brand/sn-logo-white.png` on Midnight,
`sn-logo-black.png` on Paper (1024×371, drawn at 15 pt). Nothing is typeset to imitate the mark, and the same asset
at 34% opacity is the **missing-artwork plate**, so the brand appears exactly where the product has no image to show.

**Red is no longer rationed to "exactly once".** It has three stated jobs: the money commitment, a destructive
action, and **the single primary action on a screen that has no money on it** — which is why *Try again* on the
listing error is red. Status never uses it: urgency is amber, and the four money states are ink, amber and grey.

### 2. Realistic content
Artwork is now **photographic in feel** — a lit room: key light, bokeh, a silhouetted crowd, film grain — rather than
abstract geometry. It is **generated placeholder art, labelled as such in every annotation**: not licensed, and not
any real event's flyer. Production renders the seller's uploaded media through `EventMedia`.

Also tested: a **47-character title** that wraps to two lines and is never cut mid-word; a **listing with no
artwork** (the branded plate); **varied details** — 1 × VIP, 2 × GA, 4 × GA, "no bids yet", an auction ending in
11 minutes, and a listing whose auction has hours left. Feature artwork is **56% of width** on Home and **62%** on
the listing, down from 3:2 and 336 pt, so the price and the list survive the fold. Supporting text is **11.5 pt**
with secondary ink around 7:1 on both canvases.

### 3. Internal consistency
| Problem | Now |
|---|---|
| "Under $100" returning $120 | The filter is **Under $150**; both results are **$99.00** and **$143.00** all-in |
| GA filter returning VIP | Both results are **GA**. The VIP listing appears only on Home, where no type filter is applied |
| Results not matching the query | Query **"neon"** — both results are *Neon Choir* listings |
| "3 events" | Gone. The count reads **"2 listings"**, and the annotation states that no grouping is claimed |
| Fee appearing twice | **One figure everywhere.** Read from source (`_shared/money.ts`): the buyer pays base + 10%. Base $90.00 + fee $9.00 = **$99.00**, which is the number on Home, in Search, in the listing breakdown and on the order. Nothing is added later |
| Buy now ambiguity | The button reads **"Buy both now · $132.00"** with "all-in, ends the auction", and the panel says **"2 × GA tickets · sold together"**. Verified in source: `amount = listing.buy_now_price` is charged once for the whole listing, not per ticket |

### 4. The order explanation — corrected
"Payment is held until you confirm" is gone. It contradicted automatic release. The screen now keeps **four states
separate and named**, each with its own row and value:

> **You paid** $99.00 · Tue 19:04 → **Seller reported sending** 14:32 → **Your confirmation** needed by Sun 09:12 →
> **Payout to seller** not released

and states both conditions in one sentence:

> *"Confirm when you have the tickets. If you don't confirm or report a problem by Sun 09:12, payment is released to
> the seller automatically."*

The seller's action is always **reported**, never "sent" or "delivered". Nothing anywhere says a payout has happened.
**This financial wording is marked as requiring A/C validation before implementation** — it is in the annotation and
in §5 below.

### 5. No implementation notes on customer screens
Removed from the screens and moved into annotations: the empty-state explanation, the rendering note and the
confirmation-behaviour note. What remains on-screen earns its place for a buyer — for example the search screen's
*"4 more listings for these dates are outside your filters"* with a **Clear filters** control, and the order's
*"You'll confirm on the next step"*.

### 6. Baseline — reconciled, and one correction to my own record
**Build 22 is the latest completed phone-check baseline** (C's record, 2026-09-19: submitted, EAS-finished, installed
and checked, clean-up done).

The rollout record states: **"App delta vs Build 22 = exactly #81 ∪ #84, five files, disjoint"** — C confirmed by
grep/diff at the heads on 2026-09-21, with two corrections accepted and both verified by A.

**So Build 22 *excludes* #81 and #84.** My previous note said #84 was integrated and #81 was integrated nowhere.
That described *branch heads*, not the tested build, and I am correcting it.

- **V3 design target:** Build 22 **+ #81 + #84** — what the rollout puts in a user's hands.
- **Open:** Build 22's exact commit is **not pinned** in any record I read. **A/C to supply it.**
- **Implemented vs proposed** is separated in §4 below, and **saved delivery preferences is proposed, not
  implemented** — it supplies the order screen's "Sent to" row and is a separate, A-reviewed specification.

> **I am not claiming the redesign preserves behaviour.** The annotations state *intent*. Preservation is a claim only
> C can establish on a device against Build 22 + #81 + #84. I performed no device check and no production read.

---

## 2 · What actually differs between the directions

Beyond palette. Both use the same content, the same 4 pt spacing, the same geometry roles and the same components.

| | **MIDNIGHT** (leading) | **PAPER** (alternative) |
|---|---|---|
| **Where artwork lives** | Artwork **is the page** — edge to edge, the title set over a scrim inside the image | Artwork is a **framed window** — inset, radius 8, the title set below it on paper |
| **How hierarchy is made** | **Luminance.** Bright artwork against near-black; text floats on a scrim | **Weight and rule.** Ink weight and hairlines; no scrim needed anywhere |
| **Where the price sits** | On the artwork, opposite the title — price belongs to the image block | In a typographic column beside the title — price belongs to the text block |
| **Panel logic** | Raised graphite lifts off the canvas | Recessed warm panel sinks into the paper |
| **Weak seller artwork** | **Flattered** — the scrim hides bad edges and low contrast | **Exposed** — a poor photo looks poor inside a frame |
| **Missing artwork** | The plate nearly merges with the canvas; absence is quiet | The plate is a visible light block; absence is obvious |
| **Dark-venue use** | Usable at arm's length in a dark room | Brighter than the room it is used in |
| **Scan order** | One stacked object: image → title → price | Two objects: image, then a caption block |

**The operational difference that matters most for a marketplace:** artwork comes from sellers and its quality is not
controllable. Midnight is forgiving of that; Paper is not. Paper is the more distinctive product and the more
demanding one.

---

## 3 · States

| Image | What it shows |
|---|---|
| `midnight-home-loading` | Skeletons in the shape of the real blocks, so nothing jumps when data lands. First load only — the app already refreshes quietly once content is on screen |
| `midnight-search-empty` | No match for the query **and** the filter, saying which filter excluded what, with the one action that fixes it. Empty is success, not an error |
| `midnight-listing-error` | A failed read that never implies a changed bid, with retry as the primary action |
| `midnight-order-unreachable` | States **what did not happen** — no confirmation sent, no payment released, review window unchanged — shows saved details with their age, and **withdraws the confirm action entirely**, offering only retry |

Long content and unavailable data appear in the main set: the two-line 47-character title and the no-artwork listing
are both in Home and Search.

---

## 4 · Remaining design decisions

| | Decision | My recommendation |
|---|---|---|
| **D1** | Midnight or Paper | **Midnight**, per your lead — and because seller artwork quality is not controllable. Paper is the more distinctive direction if you want to take that risk deliberately |
| **D2** | Display face | Keep the **system serif** (Didot / Baskerville) for now — no licence, no bundle cost. Revisit a licensed serif only after the direction is approved |
| **D3** | Price over artwork (Midnight) | **Accept**, with the scrim depth fixed as drawn. If you would rather never set a price over a photo, Midnight's hero moves to a caption block and it converges with Paper |
| **D4** | Amber for urgency | **Keep.** It leaves red meaning money or danger, and it is legible on both canvases |
| **D5** | Search as a tab | **Leave as the header entry point.** Changing the tab set is a navigation change and needs C's review |

## 5 · Genuine implementation dependencies

| Dependency | Why | Owner |
|---|---|---|
| **Financial wording validation** | The order screen's release wording must match the real rule before it ships. **Blocking for that screen** | **A and C** |
| **Build 22's exact commit** | So the design target is unambiguous | **A / C** |
| Android serif substitute | Didot and Baskerville are iOS-only. Noto Serif is on the platform, or an OFL Google serif as a **JS-only** package — no purchase | C |
| Display token re-measure | Serif metrics differ from Oswald's; every display token must be re-checked against `MIN_LINE_HEIGHT_RATIO` (1.25) and the display-scale cap | C |
| Two-line title wrapping | Home feature, rows and the order header wrap to two lines and must truncate on a word boundary | C |
| Branded plate | Already exists (CFT-106). Reused, not rebuilt | — |
| Saved delivery preferences | Supplies the order's "Sent to" row. **Proposed, not implemented** — separate spec | B spec · A reviewed |
| No blur, no worklets | `expo-blur` absent; Reanimated inert with no `babel.config.js`. Nothing in V3 needs either | — |

---

## 6 · Recommendation

**Approve Midnight as the V3 direction, with Paper retained on the shelf.** Midnight keeps the app usable in the
rooms it is used in, forgives the artwork a marketplace cannot control, and makes the identity explicit through the
real mark rather than typeset lettering. The work it needs before implementation is small and named: the financial
wording validated by A and C, the Build 22 commit pinned, and an Android serif chosen.

What I would **not** do is ship both appearances at once. Two canvases double the contrast, scrim and state work, and
nothing in this package needs a second appearance to be judged.

**For your visual approval:** the eight clean phone images are the approval set; the eight annotated images are the
reasoning behind them; the four state images show the cases that usually break a redesign. No implementation will
start until you choose.

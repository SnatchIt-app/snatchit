# Snatch It V3 — two directions across four cornerstone screens (B, 2026-09-21)

**Deliverable:** eight annotated **design mockups** (static PNG images, not functioning screens) plus this written
specification. No HTML, no prototype, no production code, nothing committed, built or deployed.

**Mockups:** `docs/product-v3/mockups/{paper,midnight}-{home,listing,inventory,order}.png`
Each image carries the phone composition at 2× beside numbered annotations. Content is **identical across both
directions** so the comparison is about form, not data.

---

## 0 · Corrected evidence labels

The owner's corrections are applied throughout. Four labels are used and nothing is asserted above its label:

| Label | Meaning |
|---|---|
| **[SRC branch]** | Read in source on a named branch. **Code on a branch is not proof that it ships.** |
| **[REPO SEED]** | A default written in a migration in this repository. **A repository default is not a verified production flag value.** |
| **[A-VERIFIED]** | A verified it against deployed behaviour, with the owner's authorisation |
| **[UNVERIFIED]** | Not established by me — no production read, no device check |

Specific relabels of my own earlier statements:

- The native gates (`feature.native_issuance_enabled`, `native_scanning_enabled`, `native_resale_enabled`,
  `wallet.apple.enabled`) are **[REPO SEED] `false` in `078`**. I have **not** read their production values.
  Everything I wrote about "the native plane is dark in production" is **[UNVERIFIED]** at that strength; what is
  verified is only the seed and the client's own comment.
- `public.get_my_tickets()` "returns `[]` in production" is **[SRC]** — the migration's own comment — not a production
  read.
- Every client-behaviour statement is **[SRC]** at a named commit. **Build 21** is the current candidate build per the
  go/no-go record; **Build 9** (`mobile/v1.0-build9-apple-review` = `4740091`) is the store-tagged client.
- `catalog.platform_config` is a **candidate dependency** for delivery preferences, not a settled mechanism, until A
  verifies its intended use and its access controls. I have downgraded my earlier "amendment" to a question.

### Baseline — corrected, and needing A/C confirmation

My first baseline choice was wrong and I am replacing it.

| Line | Head | What it is |
|---|---|---|
| `release/candidate-20260918` | `ee4cc12c` (21 Sep) | Newest **docs/release records**. **Behind on client code.** |
| **`integration/refund-payout-round-v2`** | **`e6ebd800`** (20 Sep) | **Newest client code — the V3 baseline.** Contains the gate line's consumer fixes and PR #84. D's independent verification of `e6ebd800` is recorded in `ee4cc12c`'s own message |
| `release/production-gate-20260918` | `6561d1f1` (17 Sep) | The branch my earlier design audit used |
| Gated candidate | `8f45e9bb` | What the go/no-go evaluated |

Measured facts behind that choice:

- `8f45e9bb` is **not** an ancestor of `ee4cc12c`; the two lines diverge at `5cfae1f3` (15 Sep).
- Comparing `app/` + `src/`: **12 consumer commits exist on the gate line and not on `ee4cc12c`** — including the
  F-XFER-3 fix, "I got my tickets" asking before it releases payment, the sent-transfer provider handoff without
  delivery details, and the F-SEC / F-AVATAR fixes. **Zero** consumer commits go the other way.
- `e6ebd800` contains the gate line, and **PR #84 is already integrated** there. **PR #81 is not integrated
  anywhere** and remains pending.
- All the structural facts V3 depends on were **re-verified on `e6ebd800`**: the same five tabs plus two hidden
  routes, Tickets on `get_my_tickets` with the same stated limits, Bids merging transfers, the dock and its
  `rgba(18,18,20,0.72)` fallback, and the v2 tokens (`#000000`, `#FF1A1A`, radius 0/pill, motion 90/180).

**Relationship to the release gate — for A to confirm.** The go/no-go was run against `8f45e9b`, whose verdicts were
**NO-GO as drafted** (shape A), superseded (A′) and **NO-GO now** (shape B, blocked on a Vault change). Because that
commit is not in the V3 baseline's history, **the gate's verdicts do not transfer to `e6ebd800`.** V3 is design work
and does not need the gate — but the questions for A and C are in the handoff.

---

## 1 · The two directions

Both are Rumor-led and editorial. Both preserve every behaviour in the preservation matrix. They differ in the one
thing the owner unlocked: **the canvas and what the artwork does to the page.**

| | **PAPER** — recommended | **MIDNIGHT** — alternative |
|---|---|---|
| Canvas | Warm paper `#F4F2ED` | Near-black `#08090A` |
| Ink | `#121212` / secondary `#6B6B66` | `#F4F4F2` / secondary `#8A8D92` |
| Panel | `#ECE9E2` | `#16171A` |
| Hairline | `#D8D5CE` | `#26272A` |
| Artwork | **A window on the page** — inset, radius 8, title *below* the image | **The page itself** — full-bleed, title over a scrim |
| Display face | **Didot** (iOS system) | **Baskerville** (iOS system) |
| Feature proportion | 3:2, 16 pt below to the title | 336 pt bleed hero |
| Red | The single money commitment | The single money commitment |
| Dock | White pill, 22 pt, light hairline | Graphite pill, 22 pt, light hairline |

**Why PAPER is recommended.** It is the only one of the two that is *visibly* a new product. It is what the Rumor
reference actually is — I measured `therumor.com` as a **white** page with near-black text, a serif display, and
almost no uppercase. It also differentiates: DICE (`#000000`) and POSH (`#0a0a0a`) are both black, so a paper Snatch
It does not read as another dark ticket marketplace. Artwork gains more, not less, by sitting as a window on paper.

**The two honest risks.** A nightlife product is used in dark rooms, and a full-white app at 2 a.m. is a real
usability question I cannot settle from a desk — it needs a device in a dark venue. And it is a complete token
re-test: 69 files already read `theme/v2`, and every contrast pair, scrim and status colour would be re-measured.

**MIDNIGHT is the alternative, and also the natural dark appearance** if you later want one. I recommend shipping
**one** first; two appearances double the review surface, and that is a scope decision, not a design one.

---

## 2 · Red — placement proposed deliberately

`#FF1A1A` stays (5.41:1 on black; 5.41:1 with black text — the measured basis is in the baseline document).
**What changes is the budget: one red element per screen, and only ever on a money commitment or a destructive act.**

| Surface | Red appears | Red does not appear |
|---|---|---|
| Home | **Nowhere** | the mark, the live/ending-soon marker (amber), the dock's active capsule |
| Listing | **Place bid** — one fill | Buy now (outline), facts, the auction timer |
| Inventory | **Nowhere** | "Ending in 11m" is amber |
| Order / Receive | **I got my tickets** — one fill | the seller's claim (amber), the status rail, the totals |

On PAPER the mark is black ink; on MIDNIGHT it is off-white. `brand/sn-logo-on-red.png` exists for the one case where
the mark sits in a red field — not used on any cornerstone screen. Status meaning never depends on colour alone: every
state also carries a word, and the rail carries a shape.

---

## 3 · Typography — with available fonts only

No purchase, per the decision.

| Role | PAPER | MIDNIGHT | Provenance |
|---|---|---|---|
| Display | **Didot** 30/26/19 pt, tracking −0.6 | **Baskerville** 31/29/19 pt, tracking −0.3 | `/System/Library/Fonts/Supplemental` — ships with iOS. **No licence, no bundle cost** |
| Utility | **Inter** 11–14 pt (400/500/600/700) | same | `@expo-google-fonts/inter`, already installed, OFL |
| Eyebrow / mark | **Oswald** 700, tracking +1.2, uppercase — *only* here | same | already installed, OFL |
| Numerals | Inter with `fontVariant: ['tabular-nums']` | same | already in use for prices |

**The change to Oswald is its role, not its presence.** Today every display token is uppercase-only Oswald. In V3 it
keeps the wordmark and small eyebrows and stops being the voice of every title.

**The Android and Dynamic Type dependencies, stated.** Didot and Baskerville are **iOS-only**. Android needs a
substitute — Noto Serif is present on the platform, and an OFL Google serif (for example Instrument Serif) would be a
**JS-only package addition, no purchase and no native build**. Either way the display tokens must be re-measured
against `MIN_LINE_HEIGHT_RATIO` (1.25) and the display-scale cap, because a serif's metrics differ from Oswald's.

**The licensed alternative, identified separately and not pursued:** a commercial editorial serif in the Romie /
GT Sectra class, roughly $200–600 for an app licence. It would sharpen the direction. It is not needed to judge V3 and
is not in any phase below.

---

## 4 · Geometry, spacing, materials

- **Geometry by role (approved for exploration):** content and price tables **0** · media **8** · floating chrome and
  action pills **22** · avatars and status **pill**. Nothing else is rounded.
- **Spacing:** the existing 4 pt base, six steps (4 / 6 / 9 / 12 / 16 / 22). Discovery breathes at 16–22; the order and
  inventory screens compress to 9–14 so the commitment and the action stay on one screen.
- **Materials:** no blur anywhere. `expo-blur` and `expo-glass-effect` are absent **[SRC]**, so every floating surface
  is an opaque or translucent fill exactly as the shipping dock already is. Content, prices and breakdowns sit on
  solid panels in both directions.
- **Motion:** RN `Animated` with `v2.motion` (90 / 180 / 280). Not Reanimated — installed but inert, with no
  `babel.config.js` **[SRC]**. The shared-content listing open (CFT-101) already exists and is the transition worth
  extending; artwork continuity from a compact row into the listing hero is the one new motion proposed, and it
  collapses under reduce-motion.

---

## 5 · The four screens — what each mockup shows

### Home — discovery
One date group leads with a feature; later groups are compact rows. Four lines per row in DICE's order: title,
time · venue, type · bids, price. Price says `from $120.00` and is never the largest element. **No trending, no
personalisation, no social proof, no "people going"** — none of that data exists. Search stays the header entry point;
the five-tab dock is unchanged. Amber marks a real sub-fifteen-minute close.

### Listing detail — one marketplace listing
The page is explicit that it is a **listing, not an event**. The commitment panel carries the current bid as the
headline with **per-ticket and quantity × total side by side**, both all-in and fee-inclusive. Facts are a
label/value table: delivery method, restrictions, seller, and the real auction end time. The commitment sentence uses
the corrected wording — *"If you win, you'll pay the all-in total to complete the purchase"* — and **measured, it
clears the action bar by 40 pt (PAPER) and 24 pt (MIDNIGHT)**; essential copy is never behind the button. One red
action; Buy now is an outline.

### Inventory browsing — filtered listings
Query, four filter chips drawn from real columns (date, price band, ticket type, delivery method), then compact rows
with per-ticket all-in price, availability from `quantity`, and bid count. The count line reads **"4 listings ·
3 events"** — it counts rows, and says so. **No lowest ask, no last sale, no "N tickets left".** Existing empty and
error behaviour is preserved and stated on the screen.

### Order / Receive transfer — a real marketplace order
Reached from **Bids**, which is where marketplace orders live today. A four-node status rail — Paid → Seller marked
sent → You confirm → Payout to seller — with real timestamps. The seller's claim is amber and worded as a claim:
*"The seller says they've sent these."* Below it: destination, proof, and the full breakdown with the total as the
most prominent figure. Payment state is stated plainly, and **auto-release is disclosed rather than hidden**: *"If you
do nothing, payment releases to the seller when your review window ends."* The irreversible action asks once more
before releasing payment, matching the integrated behaviour; "Report a problem" stays a peer.

**Native Tickets is not the destination for marketplace orders and is not populated with them.** Doing so would need
an explicit implementation proposal, which is not in this deliverable.

---

## 6 · Dependencies

| Item | Status | Owner |
|---|---|---|
| All four cornerstone compositions as drawn | Available — layout, tokens, copy only | B design · C implements |
| Didot / Baskerville display on iOS | Available, no licence | C |
| Android serif substitute | JS-only package addition, OFL, no purchase | C, A reviews the dependency |
| Display token re-measure against the line-height floor and scale cap | Required before implementation | C |
| Artwork continuity transition | Available on `Animated` | C |
| PAPER as a second appearance alongside MIDNIGHT | Scope decision | owner |
| Blur materials | Needs a dependency and a build — **not used** | owner, if ever |
| Canonical event, market statistics, social proof | **Out of initial scope**, per the owner | — |
| Marketplace order destination beyond Bids | Requires an implementation proposal | C + A |

---

## 7 · Phased handoff

| Phase | Contents | Review | Evidence of no regression |
|---|---|---|---|
| **V3-0** | Tokens and type only: canvas, ink, panel, hairline, the four-step geometry, display role change | A (token parity) | The `brandTokens` parity assertion stays green; no screen layout changes |
| **V3-1** | Home and inventory composition | C | Filter behaviour, realtime insert position, image-failure plate, quiet refresh unchanged on device |
| **V3-2** | Listing detail composition | C, then A for price semantics | Per-ticket vs total labels, server-mirrored price, live states; the commitment line measured clear of the action |
| **V3-3** | Order / Receive composition — **presentation only** | **A required** | Every transfer state distinct; PR #84's copy preserved; no payout claim without a payout; confirm-before-release intact |
| **V3-4** | Motion: artwork continuity | C | Reduce-motion collapses it; no delay to any action's result |

Nothing in V3-0 to V3-4 changes payment, refund, expiry, transfer or navigation logic.

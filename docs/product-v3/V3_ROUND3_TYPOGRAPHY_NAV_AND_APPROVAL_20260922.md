# Snatch It V3 — round 3: typography, profile navigation, and the approval package

**B · 2026-09-22 · Midnight only · no HTML**

> **STATUS: APPROVED by the owner, 2026-09-22.** Midnight, Oswald_700Bold for event/listing names in mixed
> case, and the profile photo in the "You" item. Six closing adjustments were made afterwards — see §8. Where
> this document and the handoff differ, **`V3_DESIGN_PACKAGE_FOR_C_20260922.md` is authoritative**; it carries
> the final values, copy and acceptance criteria.

15 static images in `docs/product-v3/mockups-v3/`. Nothing in this package changes payment rules, navigation
behaviour or database structures. The only source edit is the amended type-rule comment described in §8.

| File | What it is |
|---|---|
| `midnight-{home,search,listing,order}-clean.png` | **The approval set.** Phone only, nothing else in the frame |
| `midnight-{home,search,listing,order}-annotated.png` | The same four with numbered notes, each tagged **EXISTS** or **PROPOSED** |
| `midnight-home-loading.png` · `midnight-search-empty.png` · `midnight-listing-error.png` · `midnight-order-unreachable.png` | The corrected failure and empty states |
| `midnight-home-hero-bright-artwork.png` | The hero over an over-exposed image — the case that found a real defect |
| `compare-typography.png` | Inter 600 vs Oswald 700, at actual size, in each screen's real column |
| `compare-profile-nav.png` | The profile nav item: 4 image states × selected/unselected, at actual size, plus the spec |

One purchase still runs through every screen: *Neon Choir*, Lantern Room, **2 × GA sold together**, current bid
**$99.00 all-in** ($90.00 + 10%), and the order is that same purchase after the auction.

---

## 1 · Typography — the display face, identified from the repository

**The app's display face is `Oswald_700Bold`.** Not guessed: `src/theme/fonts.ts` imports it as the display role
and lists it in `REQUIRED_FONT_ASSETS`, and it is **the only Oswald weight loaded** — the file bans synthetic
weights explicitly, so 700 is the whole Oswald palette. The body face is Inter at 400/500/600/700. Nothing was
recreated as typed text; the wordmark on every screen is still the real `brand/sn-logo-white.png`.

### What I found before drawing anything

`src/theme/v2.ts:113-119` states the opposite of what you asked for, in the token file itself:

> Event titles, venue names and person names are Inter in sentence case, **never Oswald and never uppercased**,
> because they arrive in mixed case, often run long, and because a poster already contains display type.

So this is not a free change. **Applying Oswald to names reverses a written rule**, and you should make that
call knowing it. What I did was test the rule rather than argue with it, at actual phone size, in the column
each screen really has.

### What the test showed — measured from the shipped TTFs

| | Inter 600 | Oswald 700 | |
|---|---|---|---|
| 41-character name, advance at 17pt | 354pt | **298pt** | Oswald 16% narrower |
| …at 21pt | 436pt | **370pt** | 15% narrower |
| …at 30pt | 618pt | **526pt** | 15% narrower |
| x-height at 17pt | 12pt | **13pt** | lowercase is not smaller |
| cap height at 17pt | 14pt | 14pt | caps match |

The decisive case is the feed row, whose text column is **192pt** (`row()`: `390 − 94 − 104`). With a 66-character
name capped at two lines, **Inter truncates at "Midnight Arcade presents The…" and Oswald reaches "Midnight
Arcade presents The Foundry Warehouse…"** — measurably more of the name survives in the same box. That is the
argument for Oswald, and it is the marketplace's own problem: sellers type long names.

**Capitalisation is preserved exactly as typed.** Nothing is uppercased. The comparison sheet shows a diacritic
case (*Björk: Cornucopia*), an all-lowercase seller (*the lot radio x nowadays*) and an all-caps seller
(*MIDNIGHT ARCADE*) rendering as written. Names that do not fit end with an ellipsis on a word boundary — a name
is never silently cut.

**No alternative face is shown**, because the brief said to show one only if the brand font performs poorly, and
it does not: it is narrower where width is scarce, its x-height is equal or larger, and it costs nothing to ship.

### What this costs, stated exactly

- **No new font, no purchase, no Android substitute, no bundle growth.** Oswald_700Bold is already bundled and
  already loaded. This is the concrete advantage over the serif from the previous round, which needed an Android
  substitute.
- **It reverses `v2.ts:113-119`.** Choosing it means amending that comment deliberately.
- **Leading must be re-measured on a device.** The shipped floor `MIN_LINE_HEIGHT_RATIO = 1.25` was derived for
  **uppercase** Oswald: (capHeight 810 + usWinDescent 377) / 1000 = 1.187 em. I re-read those numbers out of the
  TTF and they match the comment. Mixed case brings ascenders into the line box: the same win metrics give
  (1325 + 377) / 1000 = **1.702 em**, the hhea metrics give **1.482 em**, and measured ink for these Latin names
  is far below either. **Which figure iOS actually uses for a given line box is a device question, and I did no
  device check.** In these mockups I used ~1.16× and set the line steps by measurement; a device pass by C
  settles the real token.
- **Venue, seller and person names do not change.** Only event/listing names move, so the "one display voice per
  screen" reason behind the original rule still holds.

---

## 2 · The profile navigation item

`compare-profile-nav.png` shows all eight cells at actual size: photo present · no photo · loading · failed,
each selected and unselected.

**The photo source already exists.** `get_my_profile()` returns `avatar_path` / `avatar_url`;
`getAvatarUrl(path, { width, devicePixelRatio })` resolves a sized public URL from the `avatars` bucket; the
profile tab already calls both. The circle is already the product's convention — `SellerTrustRow` renders an
avatar with `borderRadius: v2.radius.pill` and `contentFit="cover"`, under the rule "people are round;
everything else is square."

| | Specification |
|---|---|
| **Touch target** | **Unchanged.** `ITEM_W` 66 × `DOCK_HEIGHT` 66 with `hitSlop` 6, from `AdaptiveDock.tsx`. The photo is drawn inside that box and changes none of it |
| **Stable crop** | 28pt circle — the same size as the active icon (`ICON_ACTIVE = 28`). Centre-crop via `contentFit="cover"`, so a tall or wide photo crops rather than letterboxes, and the crop never shifts between states |
| **No layout movement** | All four image states occupy the identical 28pt circle. Loading is a flat filled circle — **not a spinner and not an animation**. Nothing here needs Reanimated, which is present but inert in this tree |
| **Selected** | The lighter inner capsule stays exactly as it ships, plus a 1.6pt chrome ring so a dark photo cannot read as unselected. **Red is not used** — it is reserved for primary actions, destructive actions and the brand mark |
| **Unselected** | The photo stays recognisable — blended only **12%** toward the dock fill. Selection is carried by the capsule and the ring, not by dimming the photo (revised at the owner's instruction, §8) |
| **Fallback** | No photo **and** failed load both render the existing person icon. A viewer never sees a broken-image glyph |
| **Label** | "You", kept. **Note:** the shipped dock renders icons only and its accessible name is "Profile"; both the visible label and the accessible name would become "You". No badge is introduced and the destination is unchanged |

---

## 3 · The six corrections

**1 · Offline and unreachable screens no longer describe the server.**
`midnight-order-unreachable.png` says *"We can't check this order right now. What's below was saved on this
device at 14:36 and may be out of date — including the deadline."*
Gone: "nothing has changed", "no confirmation was sent", "no payment was released", "your review window is
unchanged". Every value carries its age — *not sent as of 14:36*, *not released as of 14:36* — and the deadline
is labelled **"Deadline shown at 14:36"**, not as the deadline. The same rule is applied to the listing error,
which now says only what the screen did: *"Nothing was sent from this screen — we couldn't read the listing."*

**2 · Current price and proposed bid are separated.**
The panel reads **CURRENT BID $99.00** with the bid count and time, and says nothing about the buyer's total.
The breakdown below is headed **"IF YOU BID THE MINIMUM · $104.50"** and resolves $95.00 + 10% = **"Your total
if you win $104.50"**. The primary button reads **"Place a bid"** with the sub-line *minimum $104.50 all-in* — corrected in §8 to match what the code does. One sentence names both:
*"The current bid is $99.00; the lowest you can place is $104.50 all-in."* No number appears in two roles.

**3 · The empty-search heading is inside the frame.**
It wraps in the 350pt column, left-aligned to the same 20pt gutter as everything else, two lines, widest line
311pt. I found the old defect by opening the image, not by trusting the fit check — the old heading was centred,
unwrapped, and ran past the phone edge into the annotation gutter.

**4 · Invented counts are gone.**
Both *"4 more listings for these dates are outside your filters"* and *"Two GA listings exist for Neon Choir
above $150"* are removed. No read in the app returns a count of listings excluded by the current filters, so the
number would have been fabricated. The empty state names the query and the filters and offers the two controls
that change the result. If you want that count, it is a new capability for C to scope, not a copy change.

**5 · A stored destination is labelled as delivery details.**
The order row now reads **"Your delivery details · where your tickets should be sent"** with the number. It is
not evidence anything was sent there. Alongside it, "Seller's proof" became **"Seller's screenshot — attached by
the seller"**: it is the seller's own attachment, and calling it proof implied a verification we do not perform.

**6 · The release wording is marked not-approved.**
The sentence *"If you don't confirm or report a problem by Sun 09:12, payment is released to the seller
automatically"* is in the annotation as **requiring A and C to validate it against the real state model before
it ships**. I have not called it approved anywhere, and it is the one blocking dependency for that screen.

---

## 4 · Build 22 — confirmed, and the claim withdrawn

**Build 22 = `05d85732`**, and I withdraw the statement that you must supply it. Verified in two independent
records, both naming the same EAS build:

- A's `docs/release/SPRINT_STATUS_20260917.md:1234` (on `release/candidate-20260918`): "#78, #79 and #80 are
  merged into the gate, which is now `05d85732` (patch-identical, CI green). **Build 22 (EAS `3ae689cd`) was
  built from it.**"
- C's `docs/product-v2/DEVICE_VERIFICATION_CHECKLIST.md:532` (on `frontend/premium-experience-backlog`):
  "Build 22 — final checkout pass H1–H5 (`05d85732`; EAS `3ae689cd-9737-4a14-b31e-6491c1163f81`)".

`05d85732f4e61cba124bec8d4dfb8b7c57e06e12` resolves in this repository — the merge of PR #80, 2026-09-19. The
same sprint record confirms the app delta to Build 22 is exactly #81 ∪ #84, so **Build 22 excludes both**, and
the V3 design target is **Build 22 + #81 + #84**.

This is records-strength confirmation read out of A's and C's own files. It is not a device check, and **I am
not claiming the redesign preserves behaviour** — the annotations state intent; only C can establish
preservation on a device.

---

## 5 · What looking at the images found this round

I told you last round that the Midnight hero "forgives" weak artwork. **Measuring it showed that was too
generous, and the design had a real defect.**

Over an over-exposed image, white title type sat at **1.10:1** against the raw picture. The gradient scrim did
not save it: because a pure gradient starts at zero, it leaves the **tops of the glyphs** over raw image, and the
worst case measured **1.73:1** — below every threshold.

So the scrim was rebuilt: it now eases to a **20% floor** across the top third of the image (smoothstep, so
there is no visible seam) and runs to 97% at the baseline. Re-measured across the whole title band:

The scrim was then re-measured per text band and colour, across all four artwork kinds — **the full table,
including the small metadata and the price, is in §3 of the handoff.** Worst band overall: **5.17:1** for the
30pt title over an over-exposed image, against a 3:1 threshold. **The scrim floor is load-bearing and must ship
with the hero.**

**The artwork is generated placeholder art**: not licensed, not any real event's flyer, and — as you said — the
crowd illustrations **do not prove anything about real seller photos**. They are shaped to imitate four kinds of
upload a marketplace receives, and they found a defect, which is what they are for. Whether the layout survives
real uploads needs real images on a device, by C. A listing with no image at all is shown throughout: the
branded plate (CFT-106) built from the real SN asset.

One correction to my own last package: I described that long title as 47 characters. **It is 41.** The 66-character
name in this round is the one that exercises truncation.

---

## 6 · The approval choices — all approved 2026-09-22

| | Choice | Outcome |
|---|---|---|
| **A1** | Names in Oswald_700Bold, mixed case | ✅ **APPROVED.** It is already loaded, costs nothing, and keeps measurably more of a long name in the row where space is scarce. Adopting it means amending that comment deliberately |
| **A2** | Profile photo in the dock, with "You" and the person-icon fallback | ✅ **APPROVED.** Every part except the rendering already exists; the target, the destinations and the badge-free dock are untouched |
| **A3** | Midnight as the V3 direction | ✅ **APPROVED.** Nothing this round changed that recommendation, and I would not ship two appearances |
| **A4** | The hero scrim floor | ✅ **APPROVED** — kept, as the "protective dark overlay". The alternative is moving the hero title to a caption block below the image, which is a different hero |
| **A5** | Price over hero artwork | ✅ **APPROVED** as drawn. It measured with the title and clears the same threshold |

## 7 · Dependencies — and what is not claimed

| Dependency | Why | Owner |
|---|---|---|
| **Release and deadline wording** | The order screen's release sentence must match the real state model. **Blocking for that screen; not approved by anyone yet** | **A and C** |
| **Mixed-case display leading** | `MIN_LINE_HEIGHT_RATIO` 1.25 was derived for uppercase. Mixed-case Oswald needs a device measurement before a token is set | C |
| **Real seller artwork** | The contrast numbers above are measured against generated placeholders. Real uploads on a device are the only proof | C |
| **Accessible name change** | "Profile" → "You" affects the accessible name, not just the label | C |
| **Excluded-listing count** | Only if you want it: no existing read returns it. A new capability, to be scoped — not a copy change | C |
| Branded plate (CFT-106) | Already exists. Reused, not rebuilt | — |
| Saved delivery preferences | Supplies the order's delivery-details row. **Proposed, not built** — separate A-reviewed specification | B · A reviewed |

**Not claimed anywhere:** no device check, no production read, and no assertion that the redesign preserves
behaviour. Every screen is a static image, labelled as one. No font is purchased or licensed, and nothing in
this package depends on blur or on an animation library — `expo-blur` is absent and Reanimated is inert in this
tree.


---

## 8 · Close-out — the six adjustments the owner asked for after approving

| # | Asked | Done |
|---|---|---|
| 1 | Two-line feed titles need vertical space; rows grow with contents; metadata must not crowd the divider | The row height is now computed from the wrapped name with a **≥12pt clearance rule** above the divider. A one-line row is 80pt, a two-line row 98pt. The first draft returned a fixed 85pt for two-line rows while the metadata ran to 86 — it was overlapping. The hero gave back the space (0.53 → 0.49 of width) |
| 2 | Keep unselected profile photos recognisable; reduce the dimming | Dimming cut from **62% → 12%**. Selection is carried by the capsule and the ring. Crop, size, fallback and touch target unchanged |
| 3 | Available actions must look enabled; withhold confirmation; C verifies offline reporting | `Try again` is now a filled, full-strength button and `Report a problem` an outlined one in full ink. Confirmation stays withdrawn. A new annotation states that nothing is shown as submitted without a server acknowledgement, and **O-3** assigns the offline behaviour to C |
| 4 | Shorten the unreachable explanation; keep uncertainty and the timestamp; never infer from a failed request | Cut from four lines to three: *"We can't check this order right now. What's below was saved on this device at 14:36 and may be out of date — including the deadline."* Every value keeps its age; the forbidden phrases are listed in the handoff so they cannot creep back |
| 5 | A/C approval of the release wording; confirm what the bid CTA does and match the label | **O-1** raised for A and C. On the CTA I checked the code rather than asking: `ListingDetailScreen.tsx:1168` does `router.push('/bid/${listing.id}')` — it **opens bid entry**. The label is now **"Place a bid"** with *minimum $104.50 all-in*. **O-2** asks C to align the bid screen's own submit label |
| 6 | Check all text over artwork, not just the title; record remaining device checks honestly | All **seven** text bands measured colour-accurately across four artwork kinds — title, time·venue, qty·bids, price and its caption, plus both listing bands. All pass; worst is 5.17:1. Remaining device checks are named in the handoff's acceptance criteria, and the numbers are explicitly against **generated** artwork, not real uploads |

**The type rule was amended in place.** `src/theme/v2.ts` and `packages/design-tokens/src/brand.ts` both carried
the "never Oswald" rule; both now record the owner's approval, narrowly — event and listing **names** move to
Oswald mixed case, while prices, dates, venue names, person names, instructions and body text stay Inter, and
the display tokens stay uppercase-only until C lands the measured mixed-case token. **Comment-only in both
files**; no token value changed, so `brandTokens` parity is untouched. I could not run vitest in this worktree
(no `node_modules`) — I verified instead that every changed line in both files is a comment line.

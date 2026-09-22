# V3 design package — handoff to C

**From B · 2026-09-22 · owner-approved direction · implementation authorised for C on an isolated V3 branch**

The owner approved the V3 visual direction on 2026-09-22: **Midnight**, **Oswald_700Bold for event and listing
names in mixed case**, and **the signed-in user's profile photo in the "You" navigation item**. The approval
covers the direction — **not every sentence, and not any behaviour that has not been verified.** Everything in
§7 marked PROPOSED is a design intent, not a licence to add a capability.

Owner's scope for implementation, quoted so it travels with this file:

> Implement the four reviewed screens and profile-photo navigation **without changing payment rules, bid
> submission semantics, reservations, transfer transitions or tab destinations. Do not silently add persistent
> order caching, saved delivery preferences or other backend capabilities merely because a mockup depicts them.
> Identify any such dependency and preserve the truthful existing behavior until separately approved.**
> … Finish your production-release duties first. Keep V3 out of the current production safety release.
> **No production deployment, release build or store submission for V3 is authorized.**

---

## 1 · Assets

| Asset | Where | Note |
|---|---|---|
| Wordmark | `brand/sn-logo-white.png` (1024×371) | Composited at **15pt height** in the Home header. Never typeset as text |
| Missing-artwork plate | Existing branded plate, **CFT-106** | Reused, not rebuilt. In the mockups it is the white mark at **34% opacity**, centred on `surface` at 52% of the plate width (capped 120pt) |
| Event artwork | Seller upload via `EventMedia` | **Everything shown in the mockups is generated placeholder art** — not licensed, not any real flyer, and **not evidence the layout survives real uploads**. That is a device check, listed in §8 |
| Avatar | `avatars` bucket via `getAvatarUrl(path, { width, devicePixelRatio })` | Already exists. `get_my_profile()` already returns `avatar_path` / `avatar_url` |
| Fonts | `@expo-google-fonts/oswald` 700, `@expo-google-fonts/inter` 400/500/600/700 | **Already installed and already loaded.** No new package, no purchase, no Android substitute |

Reference images: `docs/product-v3/mockups-v3/` — four `*-clean.png` (the approved set), four `*-annotated.png`,
five state images, and two comparison sheets.

## 2 · Typography

**Event and listing NAMES → `Oswald_700Bold`, mixed case, `textTransform` unset.** Capitalisation is whatever
the seller typed: `the lot radio x nowadays` and `MIDNIGHT ARCADE` both render as written.

| Surface | Size | Line step used | Ratio | Tracking | Max lines |
|---|---|---|---|---|---|
| Home feature name | 30pt | 35pt | 1.167 | +0.1 | 2 |
| Listing detail name | 31pt | 36pt | 1.161 | +0.1 | 2 |
| Order header name | 21pt | 25pt | 1.190 | +0.1 | 2 |
| Feed / search row name | 17pt | 21pt | 1.235 | +0.1 | 2 |
| Empty- and error-state heading | 26pt | 29pt | 1.115 | +0.1 | wraps freely |

> **These line steps are drawn values, not a token.** `MIN_LINE_HEIGHT_RATIO = 1.25` in
> `src/theme/typography.ts` was derived for **uppercase** Oswald: (capHeight 810 + usWinDescent 377) / 1000 =
> 1.187 em. Mixed case brings ascenders into the line box — the same win metrics give **1.702 em**, hhea gives
> **1.482 em**, and measured ink for Latin names is far below either. **Which one iOS uses for a given line box
> is a device question. Measure it before setting the token.** If the device forces a larger ratio, the row
> heights in §3 move with it — they are computed from content, not hard-coded.

**Truncation:** a name that exceeds its line cap ends with `…` on a **word boundary**. It is never cut
mid-word and never silently clipped.

**Everything else stays Inter, unchanged** — per the owner: prices, dates and times, venue names, person and
seller names, instructions, body copy, labels and eyebrows. Prices keep `Inter_700Bold` with
`fontVariant: ['tabular-nums']`. Only the event/listing name moves.

The rule that said otherwise has been amended in place, identically in both mirrored token files
(`src/theme/v2.ts` and `packages/design-tokens/src/brand.ts`), as a **comment-only** change — no token value
was touched, so `brandTokens` parity is unaffected. I could not run vitest in this worktree (no
`node_modules`); I verified instead that every changed line in both files is a comment line.

## 3 · Spacing and layout values

**Feed / search row** — the row grows with its contents; metadata never crowds the divider.

```
left gutter            20pt
artwork                62 × 62, radius 8
text column            x = 94, width 192   (= 390 − 94 − 104)
price column           right-aligned at x = 370, top-aligned with the artwork
name                   line step 21pt, max 2 lines
meta line 1            name block bottom + 4pt      (date · time · venue, Inter 11.5)
meta line 2            meta line 1 + 17pt           (qty × type · bids, Inter 11.5)
ROW HEIGHT             max(artwork_top + 62 + 18,  last_meta_baseline + 12 + 12 + 10)
divider                1px, inset 20pt, drawn 10pt above the next row's top
CLEARANCE RULE         ≥ 12pt between the last metadata line and the divider below it
```

A one-line row is 80pt; a two-line row is 98pt. **Do not hard-code either** — compute from the wrapped name, or
the enlarged-text cases in §8 will overlap exactly the way the first draft did.

**Home feature** — full-bleed, height `(screen − 40) × 0.49 + 34` ≈ 205pt at 390pt wide. Name block sits
`lines × 35 + 44` above the image bottom; meta at +2, second meta at +19; price right-aligned on the same
baseline as the first meta, its caption 21pt below.

**Listing hero** — full-bleed, height `screen × 0.62 + 24` ≈ 266pt. Date line 78pt above the image bottom,
name 19pt below the date line.

**The scrim is load-bearing and must ship with the hero.**

```
alpha(t) over the image height, t = 0 at the top:
   t < 0.30 :  0.20 × smoothstep(t / 0.30)      ← eases in, so there is no visible seam
   t ≥ 0.30 :  0.20 + 0.77 × (t − 0.30)/0.70    ← linear to 0.97 at the baseline
```

The 0.20 floor is the point. A pure gradient starts at zero and leaves the **tops of the glyphs** over raw
image; over an over-exposed photo that measured **1.73:1**, and the unscrimmed image measured **1.10:1**.

**Measured with the scrim, colour-accurate, worst pixel in each text band**, across four artwork kinds
(dark stage, over-exposed daylight, busy flyer, flat low-contrast):

| Band | Threshold | dark | bright | busy | flat |
|---|---|---|---|---|---|
| Home name 30pt white | 3:1 | 11.42 | **5.17** | 8.55 | 13.20 |
| Home time · venue 12.5pt | 4.5:1 | 15.14 | 12.93 | **8.31** | 16.09 |
| Home qty · bids · left 11.5pt | 4.5:1 | 13.25 | **11.96** | 13.25 | 13.30 |
| Home price $99.00 18pt | 3:1 | 18.54 | **10.09** | 17.58 | 20.26 |
| Home "current bid, all-in" 11pt | 4.5:1 | 13.32 | **12.15** | 13.32 | 13.36 |
| Listing date · time · venue 12pt | 4.5:1 | 11.92 | **5.94** | — | — |
| Listing name 31pt white | 3:1 | 19.37 | **15.91** | — | — |

All seven bands pass, including the small metadata and the price — not just the large title. **These numbers
are against generated artwork.** Re-measure against real uploads on a device (§8).

## 4 · Avatar states — the "You" navigation item

Geometry is **unchanged** from `src/components/nav/AdaptiveDock.tsx`: `ITEM_W` 66 × `DOCK_HEIGHT` 66,
`hitSlop` 6, icons 27 inactive / 28 active, selected = the existing lighter inner capsule.

| State | Rendering |
|---|---|
| **Photo present** | 28pt circle, `contentFit="cover"`, `borderRadius: v2.radius.pill`. Centre-crop — a tall or wide photo crops, never letterboxes, and the crop does not shift between states |
| **No photo** | The existing `person.fill` icon, unchanged |
| **Loading** | A flat filled circle at the identical 28pt. **No spinner, no animation** — nothing here needs Reanimated, which is present but inert in this tree |
| **Failed** | The **same** fallback as "no photo". A viewer never sees a broken-image glyph |
| **Selected** | Two chrome signals: the existing capsule **plus** a 1.6pt ring 2.5pt outside the circle, in `text.primary`. **Red is not used** — it is reserved for primary actions, destructive actions and the brand mark |
| **Unselected** | The photo stays **recognisable**: blended only **12%** toward the dock fill. Selection is carried by the capsule and the ring, not by dimming the photo into a smudge |

**No layout movement:** all four image states occupy the identical 28pt box, so the dock cannot reflow when an
image resolves or fails. **No badge** is introduced. **The destination does not change.**

**Label:** "You". The shipped dock renders icons only and its accessible name is "Profile"; V3 shows the label
and both the visible label and the accessible name become "You". Request the image at the rendered size —
`getAvatarUrl(path, { width: 28, devicePixelRatio })` — not full size.

## 5 · Approved copy (exact strings)

**Home / Search**
- `current bid, all-in` · `all-in` · `Ending in 11m` (amber only under 15 minutes) · `no bids yet`
- Search results header: `2 listings` + `Soonest first`. **No count of listings excluded by filters** — no read returns it.

**Search — empty**
- `Nothing matched “neon” with these filters`
- `Clear a filter to widen the search, or edit the words above.`
- Actions: `Clear price filter` · `Clear all`

**Listing**
- `CURRENT BID` / `$99.00` / `all-in · 6 bids · 2h 14m left` / `2 × GA tickets` / `sold together`
- `IF YOU BID THE MINIMUM` · `$104.50` → `Tickets (2 × GA)` `$95.00` · `Service fee (10%)` `$9.50` · `Your total if you win` `$104.50`
- `A bid is a commitment. The current bid is $99.00; the lowest you can place is $104.50 all-in. If you win, you'll pay your own bid to complete the purchase.`
- Primary: **`Place a bid`** with sub-line `minimum $104.50 all-in`
- Secondary: `Buy both now · $132.00` with `all-in, ends the auction`

> **The primary label was corrected to match the code.** `ListingDetailScreen.tsx:1168` does
> `router.push('/bid/${listing.id}')` — the button **opens bid entry, it does not submit**. A label reading
> "Place bid · $104.50" implied submitting that amount. **C: confirm the bid-entry screen's own submit control
> carries the amount actually being submitted, and make both labels agree.** If bid entry submits a
> user-entered figure, the listing CTA must not name a price as if it were the bid.

**Listing — failed read**
- `We couldn't load this listing`
- `Nothing was sent from this screen — we couldn't read the listing. Check your connection and try again.`
- `Try again` (red: the single primary action on a screen with no money on it)
- **Never** "your bid is unchanged" or any statement about server state.

**Order**
- Rail: `You paid` `Tue 19:04` → `Seller reported sending` `14:32` → `Your confirmation` `by Sun 09:12` → `Payout to seller` `not released`
- `The seller reported sending your tickets` / `14:32 · screenshot attached by the seller. Accept the transfer in DICE, then confirm here.`
- `Tickets (2 × GA)` `$90.00` · `Service fee (10%)` `$9.00` · `You paid` `$99.00`
- `Your delivery details` / `where your tickets should be sent` — **a destination, never evidence anything was sent there**
- `Seller's screenshot` / `Attached by the seller 14:32 · tap to view` — **never "proof"**
- `Confirm when you have the tickets. If you don't confirm or report a problem by Sun 09:12, payment is released to the seller automatically.` — ⚠ **NOT APPROVED. See §6.**
- Primary `I have my tickets` / `you'll confirm on the next step` · Secondary `Report a problem`
- The seller's action is always **reported**. Never "sent", never "delivered". Nothing says a payout happened.

**Order — server unreachable**
- `We can't reach our server`
- `We can't check this order right now. What's below was saved on this device at 14:36 and may be out of date — including the deadline.`
- Block heading `SAVED ON THIS DEVICE · 14:36 TODAY`; values `not sent as of 14:36`, `not released as of 14:36`, and the deadline row is labelled `Deadline shown at 14:36`
- `We'll show the current state when we can reach our server again.`
- Actions: `Try again` (filled, full-strength) and `Report a problem` (outlined, full ink) — **both drawn as enabled**. Confirmation is **withdrawn entirely**, not greyed.
- **Forbidden on this screen:** "nothing has changed", "no confirmation was sent", "no payment was released", "your review window is unchanged", or any unqualified deadline. **A failed request never establishes that a payment or confirmation did not happen.**

## 6 · Open items — resolve before the affected screen is called done

| # | Item | Owner | Blocking |
|---|---|---|---|
| **O-1** | **The automatic-release sentence** on the order screen must be approved against the real state model — the deployed release/expiry behaviour, not the mockup. | **A and C** | **Yes, for the order screen** |
| **O-2** | **Bid CTA semantics.** Confirm whether bid entry submits a user-entered amount or the stated minimum, and make the listing CTA and the bid screen's submit label agree. | **C** | Yes, for the listing CTA |
| **O-3** | **What "Report a problem" can do with no connection.** The route opens; **nothing may be shown as submitted without a server acknowledgement**. If the route cannot reach the server either, it must say so rather than accept a report into a void. | **C** | Yes, for the unreachable state |
| **O-4** | **Mixed-case display leading** measured on a device, then the token set. | **C** | Yes, before the token lands |
| **O-5** | **"Profile" → "You"** changes the accessible name, not only the visible label. | **C** | No |

## 7 · Existing vs proposed

**EXISTS — reuse, do not rebuild**

- Avatar storage, `getAvatarUrl`, `get_my_profile()` returning `avatar_path` / `avatar_url`; the profile tab already calls both.
- The circular-avatar convention: `SellerTrustRow`, `borderRadius: v2.radius.pill`, `contentFit="cover"`.
- Dock geometry, the five destinations, the collapse machine, the keyboard retreat, the selected capsule.
- Oswald_700Bold and the four Inter weights — loaded, with the synthetic-weight ban in `fonts.ts` intact.
- The branded missing-artwork plate (CFT-106) and `EventMedia`.
- Empty (`[]`) treated as success, with the error state separate and offering retry.
- Withdrawing an irreversible action when the app cannot confirm state (checkout already does this for Pay).
- The fee model: buyer pays base + 10% (`_shared/money.ts`); `buy_now_price` charged **once for the whole listing**.

**PROPOSED — design intent only; none of it authorises a backend change**

- Names in Oswald mixed case; the 2-line cap with word-boundary ellipsis.
- The profile photo in the dock, its four image states, the ring, the "You" label.
- The scrim floor; the content-driven row height.
- All the wording in §5.
- **Depicted but NOT authorised — preserve truthful existing behaviour:**
  - **Persistent order caching.** The unreachable screen shows dated saved values. *If no such cache exists today, do not add one.* Show only what the app genuinely holds, and if it holds nothing, say that instead — an empty truthful state beats a fabricated timestamp.
  - **Saved delivery preferences.** Supplies `Your delivery details`. A separate A-reviewed specification, **not built**. If the value is unavailable, omit the row; do not invent a destination.
  - **A count of filter-excluded listings.** Deliberately absent. Do not add a read for it without approval.

## 8 · Acceptance criteria

Implementation is done when all of these are demonstrated, with evidence:

**Typography and layout**
1. Event/listing names render in Oswald_700Bold mixed case on Home, Search, Listing and Order; capitalisation is byte-identical to the stored value; nothing is uppercased.
2. Prices, dates, venue, seller, instructions and body remain Inter; prices keep tabular figures.
3. A name too long for its cap ends with `…` on a word boundary — verified with a ≥66-character name and with `Björk: Cornucopia`, `the lot radio x nowadays`, `MIDNIGHT ARCADE`.
4. **A two-line row is taller than a one-line row, and ≥12pt of clear space separates the last metadata line from the divider** — at default text size and at the largest supported text size.
5. No clipped glyph tops at any display size (the mixed-case leading check, O-4).
6. Layout holds at the smallest supported screen width.

**Navigation**
7. All four avatar states render at an identical 28pt circle; the dock does not reflow when an image resolves or fails; the touch target stays 66×66 with `hitSlop` 6.
8. Selected is unmistakable via the capsule and ring; **unselected remains recognisable as the same photo**; no red anywhere in the dock.
9. A failed image shows the person icon, never a broken-image glyph.
10. **A previous user's photo never survives an account change** — verified across sign-out, sign-in as a different account, and account switching.
11. Photo replacement and removal update the dock without a restart.
12. Tab destinations are unchanged; no badge exists; the accessible name matches the visible label.

**Artwork**
13. Text over artwork is legible on real seller images: at minimum a dark stage shot, an over-exposed daylight shot, a busy flyer and a low-contrast phone photo — **title, metadata and price all checked**, not just the title.
14. A listing with no artwork shows the branded plate; an image that fails to load does the same.

**Financial and uncertainty states**
15. Current bid and the buyer's proposed total never share a figure or a label.
16. The listing CTA matches what it does (O-2).
17. The unreachable order screen contains **none** of the forbidden phrases in §5, shows every value with its age, and offers no confirmation control.
18. `Try again` and `Report a problem` are visibly enabled and actually work; reporting never displays as submitted without a server acknowledgement (O-3).
19. A failed read never asserts anything about server state.
20. **No new backend capability, cache, table, column or RPC is introduced** by this work. Any dependency in §7 is either absent-and-handled or raised for separate approval.

**Process**
21. Payment rules, bid submission semantics, reservations, transfer transitions and tab destinations are unchanged — prove it with a diff of the gated client surface.
22. Meaningful regression coverage for the behaviour this change touches, with a negative control: remove the branch the test defends and watch it fail.
23. `npm run typecheck` · `npm run lint` · `npm run test` green, pasted.
24. **Real app screenshots** of the four screens and the dock states, next to `mockups-v3/*-clean.png`.
25. V3 stays on an isolated branch, out of the production safety release. **No deployment, release build or store submission.**

## 9 · What is not claimed

No device check and no production read by me. Every image is a static mockup, labelled as one. The contrast
figures are measured against generated placeholder artwork, not real uploads. **I am not claiming the redesign
preserves behaviour** — the annotations state intent; preservation is C's to establish on a device against
**Build 22 (`05d85732`) + PR #81 + PR #84**, which is the V3 design target.

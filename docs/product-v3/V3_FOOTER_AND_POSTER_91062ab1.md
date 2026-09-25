# B — listing footer comparison, and the 4:5 poster direction

**Base commit** `91062ab1` (`v3/midnight-app`). Everything below is that commit plus **one
reversible harness patch**, recorded verbatim at
`harness/B_footer_and_poster_harness_91062ab1.patch` (194 lines) with its one new file at
`harness/__FooterVariants.tsx`. The patch was applied in B's render worktree only, never committed
to `v3/midnight-app`, and **the worktree was reverted with `git checkout -- src app` after the
captures** — `git status` is clean.

**Evidence class: web render**, 393 × 852 @3×, appearance driven by the app's own preference,
Inter and Oswald verified in use on every capture. Native iOS is a separate class and still owed.

**No real checkout, no fixture mutation, no production read, no build.**

**One safeguard was deliberately not weakened.** `isTrustedMediaUrl` refuses `http:` and any host
outside the allow-list — "a downgraded image request is a downgraded request". The sample poster
is injected at `EventMedia`'s single resolve point behind a sentinel path instead. The trust
function is untouched, and it is still the only thing deciding what a real row may load.

---

# Part 1 — the listing footer

Sheet: `comparisons/footer_arrangements_91062ab1.png`. Three arrangements, identical event data,
both appearances.

| | arrangement | how it was drawn |
|---|---|---|
| **A** | side-by-side — red **Place a bid** left, outlined **Buy both now** right | new layout; real `Button`, real palette, real type and spacing tokens |
| **B** | stacked — red **Place a bid** first, outlined **Buy both now · $132.00** second | the **real `StickyBar` and real `BarAction`**, with the pair swapped |
| **C** | stacked — filled **Buy both now · $132.00** first, outlined **Place a bid** second | the shipping code, untouched |

B is drawn by the shipping components on purpose: it differs from C only in order and fill, so a
re-implementation would have compared my code against C's rather than B against C. My first pass
did re-implement it, and the sub-line collided with the label inside the pill — that render was
discarded, not reported.

## What A required, and why

A's constraint was the owner's: no squeezing long sentences into half-width buttons. At 393 pt a
half-width pill is ~174 pt, and both `Button`'s label and `BarAction`'s sub-line are
`numberOfLines={1}` — both would ellipsize. So in A the price and the consequence sit **below**
each pill on the canvas, free to wrap:

* left — **Place a bid** · *minimum $104.50 all-in*
* right — **Buy both now** · *$132.00 all-in · ends the auction*

Quantity ("both"), all-in meaning and the bid/buy distinction all survive. Nothing is truncated at
393.

## Measured: where A breaks

Truncation measured as `scrollWidth > clientWidth` on the real laid-out nodes.

| width | A | C |
|---|---|---|
| 393 pt (iPhone 15/16/17 Pro) | fits | fits |
| 375 pt (SE 2/3, 8) | fits | fits |
| 320 pt (SE 1) | fits — "Buy both now" needs 107 in 106, a rounding hair | fits |
| **302 pt** | **"Buy both now" TRUNCATED** (107 in 97) | fits |
| **260 pt** | **both labels TRUNCATED** | fits — "Buy both now · $132.00" needs 184 and has it |

**A survives every real iPhone width and fails on text growth.** 302 pt is the same
text-to-container ratio as ~130 % Dynamic Type at 393 pt, and 260 pt ≈ 150 %. C truncates at no
width tested, because a full-width pill has 393 pt for a 184 pt label.

**The width shrink is a proxy, not Dynamic Type.** `react-native-web` fixes the font scale at 1,
so real Dynamic Type — and `maxFontSizeMultiplier`, which caps it — can only be verified natively.
The arithmetic is the same and the proxy is stated as one.

## Recommendation — **B**

Not C, and not A.

**Against A:** it fails the accessibility case at a setting many people use, and the fix for that
is to stack — which is B with extra machinery and a breakpoint. It also costs vertical space: the
sub-lines sit outside the pills, so the footer grows, and a side-by-side pair reads as *two peers*
at the moment the screen most needs to say which action is which.

**Against C:** the filled control is the one that ends the auction and charges the full
**$132.00**, while the outlined one opens a bid entry that submits nothing. The louder button is
the more expensive and less reversible act. On a marketplace whose own commitment sentence is "A
bid is a commitment. If you win, you'll pay your own bid at checkout", leading with Buy Now sells
the exit rather than the mechanism.

**For B:** identical geometry to C — same pills, same in-pill sub-lines, same widths, no new
truncation at any width — so it costs nothing to build and nothing to maintain. It puts the red on
the cheaper, reversible, more common action, and leaves Buy Now present, legible and one tap away
with its price on it. The distinction stays sharp because the two pills still read differently:
one names a minimum, the other names a total and its consequence.

**This contradicts the 2026-09-24 resolver ruling**, which made the resolver's primary the filled
action. B keeps the resolver's *order* question open — Buy Now can still lead the column — but
takes the *fill* off it. If you prefer to keep the resolver as the single source of hierarchy,
C is the consistent choice and my objection is to the hierarchy, not to the code.

---

# Part 2 — the 4:5 poster direction

Sheet: `comparisons/poster_45_direction_91062ab1.png`. Sample poster:
`comparisons/sample_poster_4x5.jpg`.

**The premise is confirmed at source.** The Posh guide states: *"Static Event Flyer Upload: 4:5
portrait ratio (Minimum 1000 × 1250 px)."* The sample artwork is built to exactly that — 1000 ×
1250, with flyer text at the top (PRESENTS / title / subtitle) and in a bottom band (date / venue /
lineup / door policy), because that is where a real flyer puts them and where a centre crop
destroys them.

## What the app does today, rendered

| slot | shape today | a 4:5 poster in it |
|---|---|---|
| `LISTING_HERO_V3` | `heightFor` = w × 0.62 + 24 → **267 pt at 393**, ratio 1.47 | **45.5 % cropped** — top and bottom bands both gone |
| `HOME_FEATURE_V3` | `heightFor` = (w − 40) × 0.49 + 34 → **207 pt**, ratio 1.9 | **57.9 % cropped** |
| `FEED_ROW_ART` | square | 20 % cropped |

Panel 1 is that crop: the flyer survives as two red circles, and the app then re-prints "Sat 24
Oct · 19:30 · Lantern Room / Neon Choir" on top of it — the same facts the poster already carried,
in place of the poster's own typography.

Panel 2 is the existing `fit` mode, which is a real capability the media layer already has
(`MediaAsset.fit`, with a blurred backdrop). The whole poster survives, but letterboxed to about
half the width inside a landscape frame, and the overlay lands directly on the poster's text band.

## The proposal, rendered

**Part one — the frame becomes 4:5.** `v2.ratio.portrait` is *already* `4/5`, and
`DISCOVERY_CARD`, `EVENT_HERO` and `EVENT_GALLERY` already use it. What forces landscape on the
two V3 slots is the **formula height**, not a ratio. Panels 3 and 6 drop `heightFor` from
`LISTING_HERO_V3`, `HOME_FEATURE_V3` and `FEED_ROW_ART` and take `v2.ratio.portrait`. The poster
arrives complete and full-bleed, at the shape it was designed in.

**Part two — the identity comes OFF the artwork, and panel 3 is why.** Even at 4:5 the app's own
"From a fan / Sat 24 Oct · 19:30 · Lantern Room / Neon Choir" sits on the poster's bottom band and
obscures "LANTERN ROOM" and the lineup. That is precisely "obscuring poster text with unnecessary
overlays", and it is unnecessary in the strict sense: **the poster already says all of it.** The
date line and the name move below the artwork, in the same type they already use. The back and
overflow chips stay — they are navigation, not duplication — and the provenance chip can stay or
move with the identity; it is a label the poster does not carry.

With the identity gone the **curve scrim goes with it**. Its only job was to give overlaid text a
floor, and there is nothing left to floor. A poster should be shown, not tinted.

## What this costs, stated plainly

A 4:5 full-bleed feature is **393 × 491 pt — 58 % of an 852 pt screen.** Panel 6 shows the feed
pushed well below the fold. Two honest options, and this is a decision for you rather than a
defect for C:

1. **Feature stays full-bleed at 4:5** and Home opens on one poster. Strong, and closest to how
   these events are actually marketed — but a shopper sees one listing before scrolling.
2. **Feature gets a maximum height** (say 0.45 × screen) and switches to `fit` with the deliberate
   background below. The poster stays complete, smaller, and two or three rows stay above the fold.

I recommend **2** for Home and **the full 4:5** for the listing hero — the feed is for scanning,
the listing is where the poster is the argument.

## Non-4:5 originals, and the other slots

`fit` plus a deliberate background is the answer and it already exists. Today's backdrop is the
image blurred at radius 54, which is *deliberate* but not *neutral* — it tints the frame with the
poster's own colour. For a poster that is usually fine and often good. Where it is not, the
fallback plate's canvas is the neutral alternative. **Never `cover` a non-4:5 original into a 4:5
frame** — that reintroduces the crop this direction exists to remove.

**Row artwork** at 4:5 (panel 6) is a clear improvement: a portrait thumbnail shows the poster's
title block, where the square showed a slice of its middle.

**Avatars are untouched.** They are on a different path (`getAvatarUrl`, square transform,
circular mask) and nothing here reaches them.

**Missing artwork is unchanged** (panel 4). The SN plate fills whatever frame it is given and is
already dark in both appearances. At 4:5 it simply becomes a taller plate — and if the feature
takes a maximum height, the plate should take the same one, so a listing without artwork does not
occupy more of Home than one with it.

## For C — the change in one list

1. `LISTING_HERO_V3`, `HOME_FEATURE_V3`, `FEED_ROW_ART` → `v2.ratio.portrait`; drop `heightFor`
   (and `heroHeight` / `featureHeight` with it, if nothing else calls them).
2. `ListingHero` — move the dated line and the name below the artwork; drop the curve scrim.
3. Home feature — same treatment, plus the maximum height if the owner takes option 2.
4. Upload guidance — 4:5, minimum 1000 × 1250, matching the flyer people already have.
5. `defaultFit` stays `cover` for a 4:5 source (a 4:5 image in a 4:5 frame crops nothing) and the
   non-4:5 case resolves to `fit` with its background.
6. Nothing in `isTrustedMediaUrl` changes.

---

**Open and not claimed:** native rendering of any of this, real Dynamic Type, and how a
photographic (non-flyer) cover behaves at 4:5 — the sample here is a flyer, which is the case the
direction is about, but sellers will also upload photographs.

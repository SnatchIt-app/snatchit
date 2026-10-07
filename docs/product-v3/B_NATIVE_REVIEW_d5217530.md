# B — native review at `d5217530` · batch 1: Home

**Candidate** `d52175303f22a575b80f005f38c0e8555be0dbdc` · branch `v3/midnight-app`.
**Start-of-review check (independent):** `git -C /Users/josetascon/snatchit-refund rev-parse HEAD` =
`d52175303f22a575b80f005f38c0e8555be0dbdc` — **matches**; `git status --porcelain` — **empty**;
`git merge-base --is-ancestor 168e794a HEAD` — **yes**.
**Device** `SN V3 393x852`, device type `iPhone-16`, UDID `52282259-961E-4A1A-B32B-CEFA858CFF48` ·
**runtime** iOS 26.5 (23F77) · 393 × 852 pt, captures 1179 × 2556 px @3×.
**JS** Metro `:8081` (pid 2172), cwd `/Users/josetascon/snatchit-refund` — **C operates it**.
**Evidence class: native development build.** Not acceptance of a distributed release artifact.
Captures: `native/d5217530/`. No production call, no reservation, no payment, no fixture mutation.

## Two environment facts, so nothing here is misread

* **The device is signed out** — the sandbox session expired over the gap, so a plain launch lands
  on Sign in. The `_dev` harness renders **without** auth, so the review proceeds. **I did not sign
  in and typed no credential.**
* **Appearance must be set per capture.** `?appearance=` writes the app's stored preference, so a
  value left over from an earlier session persists. I verified the mechanism rather than assuming
  it: with the system in Light, `?appearance=light` → white canvas, `=dark` → black, `=system` →
  white. **System appearance switching works.** Captures where I had not yet pinned it were
  discarded, not reported.

## Verified — every requested fixture actually appears in the feature

A URL parameter is not a render, so each case is matched against **its own source file** in
`assets/qa-posters/`, contained into the measured frame, with a mismatched fixture as control.

| `?art=` | source | image drawn | mean diff | control |
|---|---|---|---|---|
| `flyer` | `flyer-dense-4x5` | 393 × 491 pt, fills the frame | **2.0 / 3.7** | 31.8 |
| `subject` | `photo-subject-4x5` | 393 × 491 pt, fills the frame | **1.2 / 2.1** | 84.4 |
| `tall` | `markers-9x16` | 276 × 490 pt, **pillarboxed** | **0.5 / 1.1** | 8.4 |
| `square` | `markers-1x1` | 393 × 393 pt, **letterboxed** | **4.1 / 3.3** | 32.1 |
| `wide` | `markers-16x9` | 393 × 221 pt, **letterboxed** | **1.9 / 1.2** | 16.5 |
| `subject-wide` | `photo-subject-16x9` | 393 × 221 pt, **letterboxed** | **2.7 / 2.3** | 74.0 |
| `missing` | — | the plate, filling the frame | — | — |

Light / Dark. **The `f3f08930` feature-selection defect is fixed**: every single-poster value now
paints the feature itself, not a non-feature row.

**Nothing is cropped or stretched.** The marker fixtures arrive whole and the drawn sizes are the
sources' own ratios to the pixel: 9:16 → 276 × 490 (0.563), 1:1 → 393 × 393, 16:9 → 393 × 221
(1.778).

## Verified — the frame, the gradient, the identity block

* **4:5, measured:** frame `164.0–655.0 pt`, **490.3–491.0 pt tall at 393 pt wide → w/h 0.8004–0.8015**
  (4:5 = 0.8000). Same in both appearances, for every fixture.
* **The gradient is gone.** If a scrim survived, the poster's bottom would differ most from its
  source. It differs **least**: flyer top-third 5.45 → bottom-third **2.27**; subject 3.34 → **1.25**
  (Light; Dark 5.20 → 1.95 and 3.44 → 1.29). The small top-third figure is resampling on the dense
  flyer type, not a scrim.
* **No app text or badge on the poster.** The dense flyer's own band — *"THIS BAND OF TYPE IS WHAT
  AN OVERLAY USED TO COVER"* — renders unobscured, and all four corner labels and all four edge
  inks are present.
* **Identity below the poster**, in canvas inks: name, time · venue, quantity · bids · ends, and the
  price with *current bid, all-in*.

## The native next-section figure (measured natively, not reused from web)

**The next section's rule sits at `790.0 pt`; `62.0 pt` of the following row remains visible** on an
852 pt screen. Identical in Light and Dark. Its heading is fully visible above the rule.

## One measured observation for C — letterboxed artwork is not centred

Non-4:5 images sit **above** centre, by an amount proportional to the vertical slack:

| case | slack | space above | share |
|---|---|---|---|
| `square` (1:1) | 97.3 pt | 37.9 pt | **39.0 %** |
| `wide` / `subject-wide` (16:9) | 269.3 pt | 108.0 pt | **40.1 %** |
| `tall` (9:16) | none (pillarboxed) | — | exactly centred |

A consistent ~40 / 60 split. That is a recognised optical-centring choice, so I am **not** calling it
a defect — but it is not geometric centring, and the ruling says only "a deliberate background".
**C: confirm it is deliberate**, and if so it should be written down; if not, it is a one-line fix.

## Still to come in this review

Listing (4:5 poster, info beneath, navigation reachable without covering printed text) · Option B
footer at rest · reservation feedback through `?reserving=1` · icons as native rendering · Dynamic
Type at the largest standard and accessibility sizes · scrolling · safe areas.

**The remembered event-name truncation remains withdrawn** until I reproduce it here with a capture,
fixture, appearance and text size.

---

# Batch 2 — Listing, footer, reservation feedback, icons, Dynamic Type

Same candidate, device, runtime and serving tree as batch 1. Captures in `native/d5217530/`.

## The 62 pt figure is HARNESS evidence — and here is the consumer chrome beside it

**Confirmed in source and on the device:** `app/_dev/v3-home.tsx` imports `HomeScreen` from
`app/(tabs)/home` and renders it under the **`_dev` Slot**. The dock is supplied by
`app/(tabs)/_layout.tsx` through its `tabBar` prop, so **the harness route carries no dock and not
the tab layout's bottom inset**. My `790.0 pt` rule and `62.0 pt` remainder are therefore
**harness measurements** and are labelled as such.

**Consumer Home does render signed out** (`snatchit:///home` → `(tabs)/home`), with the real dock.
Measured there (Dark, where the dock separates cleanly from the canvas):

| | |
|---|---|
| dock band | **704.0 → 769.7 pt** (height 66.0 pt) |
| gap below the dock | 82.0 pt |
| top banner / safe area | 0 → 78.7 pt |

The harness rule at 790.0 pt sits **86 pt below the dock's top edge**. I am **not** converting that
into a consumer figure: the harness route lacks the dock, so the real screen's scroll padding and
content offsets differ, and the only honest number comes from consumer Home **with feed content** —
which needs an authenticated session. **Not established. Blocked on auth.** (The Light dock read is
partial — a near-white dock on white canvas — so the band above is the Dark measurement.)

Captures: `home-consumer-chrome-signedout-{light,dark}.png`.

## Option B footer at rest — matches the approval

`listing-live-flyer-light.png`. **Place a bid** first, full-width, filled red, with
**“minimum $104.50 all-in” beneath the label *inside* the pill**. **Buy both now · $132.00** second,
full-width, outlined, with “all-in, ends the auction” inside it. Quantity-aware label, price and
sub-line all preserved. The choice is closed and is not reopened here.

## Reservation feedback — verified, R-1 closes natively

`listing-reserving-flyer-{light,dark}.png`, via `?reserving=1`. **No reservation was made.**

**“Reserving…”, with its spinner, sits on the second-position outlined Buy Now — the button that is
busy.** The first-position red bid pill is dimmed and carries **no** pending label. Buy Now keeps
its sub-line. This is exactly the behaviour the ruling requires, and it is the defect I reported at
`3c6f15a4` now fixed and confirmed on the device.

One consequence, by design rather than defect: while reserving, Buy Now's label is replaced by
“Reserving…”, so its price is not on screen for that moment. The minimum moves outside the bid pill
in this state, which is the screen's existing rule that a dimmed control must not be the only place
a state is written.

## Icons — native rendering, recorded separately from the source finding

**F-91-6 closes.** Measured off the native capture, the Filters glyph is **three bars of 58, 46 and
34 device px** — decreasing, a filter mark. At `91062ab1` it measured three *equal* 41 px bars, a
hamburger. The search control is a drawn magnifier. Both are vector shapes.

**This is separate evidence from the source cmap finding** (`4882cd6a`), which showed four of five
glyphs absent from Inter 400/600 and Oswald 700. That finding described character-based icons; these
are no longer characters, so the cmap gap no longer reaches them. The source finding stands as
history; the native result above is what the current candidate draws.

## Dynamic Type — reproduced, with the remembered finding withdrawn

Home feature, Light, `?art=flyer`, three sizes. **The poster is unaffected at every size**, as an
image should be.

| content size | identity block below the poster |
|---|---|
| `large` (default) | all four lines complete |
| `extra-extra-extra-large` (largest **standard**) | “2 × GA · 6 bids · **Ends…**” — the end time is cut |
| `accessibility-extra-extra-extra-large` | “$99.00 / **current bid, al…**” — **“all-in” is cut** |

**The remembered one-character collapse (“B” / “i…”) is NOT reproduced at either size and is
withdrawn.** The name renders fully at the largest standard size.

**What I am opening, and at what strength.** The a3xl case cuts **“all-in”** off the price caption.
That is not a title ellipsis — it is the qualifier every pricing ruling on this product depends on,
and a reader at that size sees a bare “$99.00”. Visually it is inaccessible. **Whether assistive
technology still exposes the full string is not established here** — I have no accessibility
inspection in this session — and that is the check that decides whether this is a presentation
problem or an information one. **C: confirm the a11y value, then either let it wrap or shorten the
caption so “all-in” survives.** The `Ends…` cut at the largest standard size is the same class, one
step milder.

## Blocked, concretely

**Scrolling is not reviewable in this session.** `xcrun simctl` injects no touch input, and the
simulator MCP tool that provides tap/swipe is unavailable here. So scroll behaviour, and anything
below the fold at large text sizes — including the **feed-row title** the owner asked me to compare
against the approved row design — **cannot be established by me on this device**. Everything above
was reached by deep link, which needs no input. C, or an attended session, can run the scroll checks.

---

# Batch 3 — Listing poster and chrome; what is blocked; handover to C

## The Listing poster IS 4:5 and complete — but its top is covered, not cropped

This distinction matters, so it is measured rather than eyeballed.

* Listing hero spans **0 → 490.7 pt** at 393 pt wide → **w/h 0.8009 — 4:5** ✓, identical for
  `flyer`, `subject-wide` and `missing`.
* Matching the visible band against the source: **cover-fit, masked diff 4.1** (contain-fit 16.6),
  the source scaled to 393 × 491 pt with **79 pt hidden at the top and 1 pt at the bottom**.
* The sandbox banner measures **0 → 78.7 pt**. The hidden 79 pt and the banner's 79 pt are the same
  79 pt.

So nothing is cropped by the frame. **The hero is laid out full-bleed from y = 0 — deliberately, per
`ListingHero`'s own note that "the artwork runs under the status bar on purpose" — and the status
bar and sandbox banner sit on top of the poster's first 79 pt.**

**Then the navigation lands on it too.** Measured chip bounding boxes:

| control | bbox (pt) |
|---|---|
| back chevron | **(5.0, 80.0) → (79.7, 159.7)** |
| overflow `⋯` | **(310.0, 80.0) → (389.7, 159.7)** |

Both sit at **y 80 → 160 pt**, immediately below the banner and squarely on printed poster content.
In `listing-live-flyer-light.png` the back chip covers the set-list line **“PLACEHOLDER ONE”** and
the overflow chip covers its time **“21:00”**; above them the flyer's **“EXAMPLE.COM/TICKETS”** is
half-hidden by the banner and its **“PRESENTS / FIXTURE NIGHT”** title block is entirely behind the
chrome.

**This is the settled requirement, unmet at `d5217530`:** *"Navigation controls, the status bar and
the sandbox banner must not cover printed content."* **C: the fix is positional, not a re-crop** —
the poster is already whole and already 4:5. Start it below the banner, and put the two controls in
their own area in the existing visual language.

Home is unaffected: its feature begins at 164 pt, clear of the banner, with no controls over it.

Evidence: `listing-live-{flyer,subject-wide,missing}-{light,dark}.png`.

## Recorded separately, as instructed

| check | result at `d5217530` |
|---|---|
| **Visible truncation** | Default: complete. Largest **standard**: “… · Ends…”. Largest **accessibility**: “current bid, **al…**” — “all-in” cut. Reproduced, captured. |
| **VoiceOver behaviour** | **Not established.** No accessibility inspection is available in this session. |
| **Scrolling reachability** | **Not established.** No touch input available (below). |
| **Safe-area layout** | Banner 0 → 78.7 pt · consumer dock band 704.0 → 769.7 pt · 82.0 pt below the dock. Home clears the banner; **Listing does not** (above). |

## Blocked, specifically

1. **Touch input.** `xcrun simctl` injects none, and the simulator tap/swipe tool is unavailable in
   this session. Everything reviewed above was reached by deep link.
2. **Consumer Home with the dock and real feed content.** It needs an authenticated session. The
   sandbox sign-in is **not available to me**: reaching it means typing the account password into
   the app, which I do not do. On the web harness I avoided this by injecting an existing session
   token rather than typing a credential; there is no equivalent here that does not materialise the
   credential. **C or an attended session must sign the device in.** Until then the consumer
   next-section figure stays unestablished, and the 62 pt figure remains harness evidence.

## Cases for C to operate — B specifies, C captures, B reviews

Label every file **C-operated, B-reviewed**. Same device, runtime and candidate; name them
`<surface>-<state>-<fixture>-<appearance>[-<textsize>]-Coperated.png`.

1. **Feed-row title at large text.** `_dev/v3-home?variant=feed&art=all&appearance=light`, content
   size `extra-extra-extra-large` then `accessibility-extra-extra-extra-large`. Scroll to the first
   “This week” row. Capture the row. **Question:** does the title ellipsis match the approved row
   design, and does any *essential* value — price, all-in, quantity, end time — become unreadable?
2. **Below-fold identity block, Home, `accessibility-extra-extra-extra-large`.** Scroll until the
   whole block under the poster is visible. **Question:** is the event name present and complete
   below the price, and is “all-in” readable anywhere?
3. **Listing scrolled to the bid breakdown and the bid activity list**, both appearances, default
   and `accessibility-extra-extra-extra-large`.
4. **Consumer Home signed in**, both appearances, default text: one capture at rest and one scrolled
   by exactly one section. **Question:** where does the next section's rule land relative to the
   dock's top edge at 704.0 pt, and how much of the next row is actually visible?
5. **VoiceOver**, Home at `accessibility-extra-extra-extra-large`: the spoken value for the price
   caption. Per the ruling, complete spoken text does not excuse clipped visible text — this
   records the gap, it does not close it.

## Review window handed back

**I am done with what `d5217530` allows me to check, and I hand the device and Metro `:8081` back to
C.** C may prepare the successor with batch 2's findings plus the two settled requirements (keep
“all-in” visibly readable; keep chrome and navigation off printed poster content).

**Serving tree at end of review:** `git -C /Users/josetascon/snatchit-refund rev-parse HEAD` =
`d52175303f22a575b80f005f38c0e8555be0dbdc` — **unchanged since start**; `git status --porcelain`
**empty**. No capture in this review is in doubt on provenance.

**This is not whole-app acceptance.** It is Home, Listing, the footer, reservation feedback, icons
and Dynamic Type, on a native development build, at one commit.

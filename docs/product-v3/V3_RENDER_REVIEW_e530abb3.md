# B — render review at `e530abb3` (C's latest committed candidate)

| | |
|---|---|
| **Source commit** | **`e530abb3`** — supersedes my `262c908b` findings, which described that commit only |
| **Viewport** | 393 × 852 logical × 3 = 1179 × 2556 |
| **Session** | sandbox DV buyer, seeded into a **dedicated profile under the session scratchpad over CDP** — no credential or token in a served file, a log, a screenshot or a commit. Profile is removed when this review closes |
| **Harness-only changes** | the same two, documented in `harness/README.md`. Nothing else |
| **Fonts verified on this capture** | `Oswald_700Bold`, `Inter_400Regular`, `Inter_500Medium`, `Inter_700Bold` all **loaded and in use**; `Inter_600SemiBold` unloaded (unused on Home) |

**Image:** `comparisons/cmp_home_e530abb3.png`

---

## 1 · Closed since `262c908b` — verified in the render

| Finding | Now |
|---|---|
| SN logo centred | **Fixed** — left-aligned, matching the board |
| A separate "MIAMI" row | **Fixed** — gone |
| No section heading | **Fixed, and correctly data-driven** — the render shows **"Later"**, not a hard-coded "Tonight". This is the right resolution: the heading follows the data |
| Prices without decimals | **Fixed** — `$110.00`, matching the board's `$99.00` form |
| Dock avatar a red/dark smear | **Visibly corrected** — a recognisable photo now renders in the dock circle. **Not yet closed**: see §3 |

## 2 · Open on Home at `e530abb3`

| # | Category | Approved reference | App at `e530abb3` |
|---|---|---|---|
| H1 | composition | **No filter chips on Home.** Header → section heading → feature | A `YOUR SCENE / PRICE / FILTERS` row sits between the header and the section heading |
| H2 | radius | Chrome radius on chips | The three chips are **square** |
| H3 | image/fallback | Missing artwork is a **plate carrying the SN monogram** — drawn on the board's third row — and the feature is a full-bleed artwork slot | The feature is a **largely empty block with a grey letter glyph**, and the name sits on bare canvas at its lower edge. Row thumbnails use the same **letter glyph** rather than the monogram |

H3 is the one that changes the page's character: with no artwork the feature keeps its height but loses its treatment, so the screen reads as empty rather than as a filled slot.

## 3 · The avatar — visibly better, NOT yet closed

The dock now shows a recognisable photo, so the reported symptom is gone. **That is not sufficient to close
the finding**, per the owner's instruction: the test is the returned image, not that an image appears.

**Still to verify before closing:** capture the **same source photo** in Profile and in the dock at the same
commit, and confirm (a) the transform now returns a square derivative — `naturalWidth ≈ naturalHeight`, where
it previously returned **56 × 1176** — and (b) the visible crop matches between the two surfaces. I have
measured neither at `e530abb3` yet.

## 4 · Unresolved, and deliberately not reported to C as a defect

**The app did not follow `prefers-color-scheme: light` in the harness.** With the stored preference cleared
(so "System"), `matchMedia('(prefers-color-scheme: light)')` **true** and `(dark)` **false**, the canvas
still painted `rgb(0,0,0)`. `resolveScheme` falls back to dark whenever the system value is null, which is
consistent with react-native-web's `useColorScheme` not reporting a value — **a web-target limitation, not
evidence about iOS.** Build 24's screenshots were all dark, so they neither confirm nor refute it.

**Consequence:** I can produce dark captures reliably; **light captures are not yet trustworthy**, so no
light comparison is offered here. Resolving this is my next step, and it must be settled before any
Light-appearance finding is sent to C.

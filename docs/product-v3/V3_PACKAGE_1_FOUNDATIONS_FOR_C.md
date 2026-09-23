# V3 Package 1 — shared foundations, navigation and reusable states

**B → C · 2026-09-22 · complete and ready to implement.** The first of five packages. Nothing here changes
payment, reservation, refund, payout, transfer, security or ownership rules.

**Artifacts:** `mockups-v3/pkg1-foundations.png` · `pkg1-components.png` · `pkg1-states.png` ·
`compare-profile-nav.png` · `compare-typography.png`. Completeness check: `V3_COVERAGE_MATRIX.md`.

---

## 1 · Three amendments that need a decision before anything is built

The approved V3 screens contradict three rules written into the shipped token files. I am not going to let that
drift into implementation, so each is stated with its evidence and a recommendation.

### A-1 · Hairlines become neutral
Shipped `border.default` is `rgba(255,26,26,0.15)` and `border.strong` `rgba(255,26,26,0.30)` — red-tinted
rules. V3 uses a neutral **`#28292D`**.
**Why:** the approved red rule says red marks primary actions, destructive actions and the brand mark, and is
not used for passive decoration. A red-tinted divider is passive decoration in red.
**Recommendation: adopt.** Small, and it makes the token agree with the rule.

### A-2 · One mixed-case display role is added
Shipped display tokens are uppercase-only. Names are already approved as mixed-case Oswald. **State and dialog
headings are sentences** — "You're offline", "Couldn't load this" — and uppercase Oswald makes them shout.
V3 sets those headings in the same mixed-case role. **Short structural titles keep uppercase**, so this adds a
role rather than reversing the existing ones.
**Recommendation: adopt.** Leading still needs the device measurement (O-4).

### A-3 · "Square is the brand" is narrowed — the material one
`Button`, `Input`, `Chip`, `Badge`, `Sheet` and `Skeleton` all set `v2.radius.none`, and their comments say
square is the brand and *"there is no pill button in this brand"*. **Every approved V3 screen is drawn with
rounded actions, chips and sheets.**

The product already contradicts the rule: **the shipped `AdaptiveDock` is a 33pt pill**, and it ships today.

V3 keeps radius 0 where the brand's line-work lives — rules, dividers, the underlined text field — and rounds
the things a thumb hits:

| Token | Value | Applies to |
|---|---|---|
| `radius.none` | 0 | rules, dividers, the Input hairline, Badge |
| `radius.media` | **8** | artwork thumbnails, the missing-artwork plate |
| `radius.chrome` | **22** | Button, Chip, Sheet, the search field |
| `radius.pill` | 9999 | avatars, status dots — unchanged |
| dock | 33 | `DOCK_RADIUS`, unchanged |

**Recommendation: adopt, and amend the comments in the same narrow way the type rule was amended.** This is the
one I would call material: it touches six components. It follows from screens the owner has already approved,
so I have drawn it that way — but it is flagged, not assumed.

---

## 2 · Tokens

**Colour** — all shipped values, unchanged except A-1.

| Role | Value | Use |
|---|---|---|
| `canvas` | `#000000` | the page |
| `surface.panel` | `#17181C` | price panel, notice, sheet |
| `surface.plate` | `#141519` | missing-artwork plate |
| `text.primary` | `#FFFFFF` | names, prices, primary labels |
| `text.secondary` | 70% white | supporting sentences |
| `text.muted` | 55% white | metadata, captions |
| `brand.red` | `#FF1A1A` | primary action fill, **black label** |
| `brand.redPressed` | `#CC0000` | pressed |
| `status.error` | `#FF4D4D` | destructive — **outline only, never filled** |
| `status.warning` | `#FFB020` | urgency, unconfirmed, needs-you |
| `status.success` | `#3DDC84` | **confirmed money only**, never decoration |
| hairline | `#28292D` | A-1 |

**Type**

| Role | Face | Case | Use |
|---|---|---|---|
| display / name | Oswald_700Bold | **mixed** | event and listing names. Line step 1.16× as drawn; token pending O-4 |
| display / prompt | Oswald_700Bold | **mixed** | state and dialog headings (A-2) |
| displaySm…displayXl | Oswald_700Bold | UPPERCASE | short structural screen titles — unchanged |
| price | Inter_700Bold | — | **tabular figures**, never Oswald |
| body / bodySm | Inter_400Regular | — | 15/22 and 13/18 |
| label | Inter_700Bold 12 | UPPER | +2.2 tracking |
| micro | Inter_500Medium 10 | UPPER | +3.0 tracking |

**Spacing and targets** — unchanged: 4/8/12/16/24/32/48; gutter 20; `MIN_TOUCH_TARGET` 44; `sm` controls make
the difference up in hitSlop; display font scale capped at 1.3; dock item 66×66 + hitSlop 6.

---

## 3 · Components — what changes and what must not

Every component keeps its shipped behavioural contract. **Only radius and the display face change.**

| Component | Keep exactly as it is |
|---|---|
| **Button** | primary red + **black** label; **destructive is `status.error` and is never a filled block**, so a delete cannot look like a purchase; there is no filled secondary; disabled **dims, never recolours**; `pendingLabel` swaps the label while loading and both labels stay mounted so the button never changes width under the finger |
| **Input** | label above, hairline under, **radius 0**; focus raises the hairline to brand red; an error raises it to `status.error` with the message beneath; the label is never the placeholder |
| **Chip** | one horizontally scrolling row; chips never wrap to a second line |
| **Badge** | **meaning is carried by a word, never by colour alone**; the venue-direct variant stays unshipped — a badge that can lie is worse than no badge |
| **StickyBar** | stacks below `STACK_WIDTH = 352`, read from the real window width; no device dimension anywhere |
| **Skeleton** | opacity pulse 0.4→0.7 over 1200ms, **no shimmer sweep**; holds still under Reduce Motion; mirrors the geometry of what is coming |
| **Spinner** | announces "busy"; static under Reduce Motion |
| **Sheet** | dismissible by scrim tap and Android back, not only by a glyph; pads the home indicator; the footer is a row and each action is wrapped so a `block` button cannot push its sibling off-screen |

**Do not build a general toast system** — corrected 2026-09-22. There is **no general toast or snackbar
system**: no queue, no global API, no reusable `show()` call. Every transient message in auth, settings and
selling is a native `Alert` or an inline `<Text accessibilityRole="alert">`.

**There is exactly one screen-local animated notice:** `src/components/listing/OutbidToast.tsx`, an existing
shipping component imported by `ListingDetailScreen` alone. My earlier "no toast anywhere" was too broad; the
accurate statement is above. Its spec is on `pkg6-system-surfaces.png`.

---

## 4 · The four state screens, and when they may take over

Copy is the shipped `STATE_COPY` vocabulary, **unchanged**:

| Kind | Title | Body | Action |
|---|---|---|---|
| offline | "You're offline" | "Check your internet connection and try again." | Retry — **and it auto-retries when the connection returns** |
| error | "Couldn't load this" | "Something went wrong on our side. Try again in a moment." | Retry |
| noMatch | "Nothing matches" | "Try the venue name, or a shorter word." | — |
| empty | screen-specific | one sentence | at most one |

**An abort or timeout is an `error`, not `offline`** — it says nothing about the user's connection. Keep that.

**When a state screen may replace content** — `src/lib/screens/refreshPolicy.ts`, and it must survive the
redesign:

- `shouldShowLoading(rowCount, phase)` — the loading screen appears only while nothing has been shown. **A
  successful empty result is a ready state**, so the empty copy stays and refreshes quietly.
- `phaseAfterError(rowCount, phase)` — rows, or a settled empty state, survive a failed quiet refresh.
- `failureSurface(rowCount, failed)` — `'screen'` when there is nothing to keep, `'inline'` above rows that are
  still valid, `'none'` otherwise.

**The inline failure banner is the one new piece** (PROPOSED): "Couldn't refresh · Showing what we last
loaded." with a Retry. Drawn above the list, never over it. It does not claim the rows are current, and it does
not claim they are stale — it says what it knows: this refresh failed.

---

## 5 · Navigation

Five destinations, unchanged. **"Sell" is the label for the existing Create destination** — label only; the
destination and its behaviour do not change. The collapse machine, keyboard retreat and per-route state are
untouched.

The profile item, its four image states and the full spec are in `compare-profile-nav.png` and the earlier
package: 28pt circle, `contentFit="cover"`, unchanged 66×66 target, selection carried by the capsule plus a
1.6pt chrome ring, unselected blended only 12% so the photo stays recognisable, failed and no-photo both
falling back to the existing person icon. **"Profile" → "You" changes the accessible name as well as the
label.**

---

## 6 · Acceptance criteria for Package 1

1. Tokens land as a **narrow amendment**, exactly as the type rule did: `radius.media` and `radius.chrome`
   added, `none` and `pill` unchanged, and the "square is the brand" comments amended rather than deleted.
2. No token **value** changes beyond A-1 and A-3; `brandTokens` parity with `packages/design-tokens` holds.
3. Button keeps all four variants and all four states; a destructive action is never a filled block; a disabled
   control is dimmed, never recoloured; `pendingLabel` holds the button's width.
4. Input keeps radius 0 and the label-above-hairline-under structure.
5. The four state screens use the unchanged `STATE_COPY`, and an abort/timeout still classifies as `error`.
6. `refreshPolicy` behaviour is unchanged: a failed quiet refresh keeps rows; a successful empty result is not
   a loading state.
7. The inline failure banner appears only where `failureSurface` returns `'inline'`.
8. Dock geometry, destinations, collapse and keyboard retreat are unchanged; the accessible name matches the
   visible label.
9. Skeletons reserve the **two-line name box**, so a long name landing does not move the row.
10. Everything above verified at the largest supported text size and at the smallest supported width, with
    `npm run typecheck` · `lint` · `test` green and real screenshots next to the boards.

---

## 7 · What I am not claiming

No device check and no production read. Every artifact is a static image. The mixed-case leading in these
boards is a drawn value, not a measured token. I am not claiming the redesign preserves behaviour — the
annotations state intent; preservation is established on a device against **Build 22 (`05d85732`) + #81 + #84**.

**Functional defects found while inventorying are listed as F-1…F-24 in the coverage matrix. They are not
redesign items and must not be silently fixed by this work** — several are genuinely serious, in particular
**F-17**: `expired` and `reversed` transfers render no state block and no explanation, and the refund is
announced only by push. That needs product copy that does not exist yet, so the design for those two states is
**blocked**, not forgotten.

# Phase 9 — Device revision: nav proportions + universal collapse + Create upload UI

**Session:** Front End · **Date:** 2026-09-03
**Branch:** `frontend/v2-phase9-adaptive-navigation` (from the Phase 8 checkpoint `c50eaf9`).
**Uncommitted** — Phase 9 requires physical-device approval before any checkpoint. This is a targeted
polish of the approved Phase 9 dock, not a redesign. No push, no PR, no Core-owned file touched.

## Files changed

```
M  src/lib/nav/navInsets.ts            dock geometry: taller, higher float, larger radius, CTA offset
M  src/lib/nav/navItems.ts             COLLAPSING_ROUTES now home/create/bids/profile (universal)
M  src/components/nav/AdaptiveDock.tsx  larger pill, keyboard-drop, left-anchored contraction morph
M  src/screens/CreateListingScreen.tsx  universal collapse wiring + MediaUpload cover/proof + CTA offset
M  app/transfer/send/[id].tsx           evidence upload migrated to MediaUpload (compact)
M  components/ui/icon-symbol.tsx        photo / doc.text / check-circle / plus / close mappings
M  src/components/ui/index.ts           export MediaUpload
A  src/components/ui/MediaUpload.tsx    the V2 upload control (cover + compact variants)
A  tests/media-upload.test.ts           10 upload guards
M  tests/adaptive-nav.test.ts           universal collapse + keyboard + CTA guards
A  docs/product/PHASE_9_DEVICE_NAV_UPLOAD_REVISION_REPORT.md
```

Approved screens changed only for nav integration (scroll wiring + clearance) and the upload swap; no
content/card/price/logo/search/data change.

## Shared navigation architecture

One behavioural source of truth — no per-screen dock copies:

- `src/lib/nav/dockMachine.ts` — the pure scroll-direction/hysteresis decision (unchanged).
- `src/components/nav/dockContext.tsx` — `NavDockProvider` holds **per-route** collapse state; screens
  call `useDockScroll(route)` (returns `{ onScroll, expand }` bound to that route). Home's scrolling can
  never collapse Profile.
- `src/components/nav/AdaptiveDock.tsx` — the single dock (the `tabBar` render prop) reads the active
  route's collapse flag and renders/animates.
- `src/lib/nav/navInsets.ts` + `navItems.ts` — geometry and destination/collapse config.

Screens only **provide scroll information**; the dock owns all behaviour.

## Old vs new bottom offset (float higher)

| | Old | New |
| --- | --- | --- |
| Gap above safe area (`DOCK_GAP`) | 12 | **22** |
| Dock bottom anchor | `insets.bottom + 12` | `insets.bottom + 22` |

The dock now clears the home-indicator boundary with a deliberate, safe-area-aware gap on every device
(no hardcoded inset) — it reads as a floating object, not a footer.

## Old vs new dock dimensions (slightly larger)

| | Old | New |
| --- | --- | --- |
| Height (`DOCK_HEIGHT`) | 56 | **60** |
| Item width | 56 | **60** |
| Icon size | 24 | **25** |
| Radius (`DOCK_RADIUS`) | 26 | **30** |
| Selected inner capsule | margin 8/6, r18 | margin 9/7, r21 |
| Item horizontal pad | 6 | **8** |

Subtly larger and more generous around the icons, still restrained — not chunky, not a giant pill,
icon sizes not disproportionate.

## Safe-area logic

The dock wrapper pads `insets.bottom + DOCK_GAP`; the compact control shares the same bottom anchor.
`useDockClearance()` = `insets.bottom + DOCK_HEIGHT + DOCK_GAP + DOCK_GAP`; `useCtaDockOffset()` =
`insets.bottom + DOCK_GAP + DOCK_HEIGHT + CTA_DOCK_GAP`. All derived from the live inset — correct
across iPhone sizes with or without a home indicator.

## Universal collapse behavior

`COLLAPSING_ROUTES = ['home', 'create', 'bids', 'profile']`. Every scrollable primary tab collapses on
sustained downward scroll and expands on sustained upward / near-top / tab focus / compact-tap — the
exact Phase 9 interaction, now global. Home, Bids and Profile feed their lists' `onScroll`; **Create**
feeds its form `ScrollView`'s `onScroll` (device revision). The collapse is the approved spatial
contraction: the pill narrows toward the left anchor, secondary icons fade, the active icon slides to
the left, and it finishes as the compact active control at bottom-left — one object changing shape, not
a cross-fade. Compact control always shows the **active** tab and only re-expands on tap.

## Hysteresis logic

Unchanged pure machine: sustained-travel accumulators, not `scrollY > n`. `COLLAPSE_AFTER` 90 (floor
before any collapse), `COLLAPSE_TRAVEL` 40 (sustained-down to collapse), `EXPAND_TRAVEL` 28
(sustained-up to expand), `TOP_THRESHOLD` 24 (always expanded near top). Jitter below the thresholds
never flips; negative overscroll (iOS bounce) resolves to expanded. Fast flicks and slow scrolls both
behave (tested).

## Keyboard behavior

The dock now subscribes to `keyboardWillShow/Hide` (iOS) / `keyboardDidShow/Hide` (Android). While the
keyboard is up it animates **down and out** (translateY + opacity) and sets `pointerEvents: 'none'`, so
it never floats over a focused form; it restores cleanly on dismiss (160ms, instant under
reduce-motion). Create's `KeyboardAvoidingView` still lifts the List ticket CTA above the keyboard, so
fields and CTA stay visible while the dock is out of the way.

## Create Listing integration

- Universal collapse wired via `useDockScroll('create')` on the form `ScrollView`.
- The **List ticket CTA stays a separate transactional surface**: its own `StickyBar` with
  `marginBottom = useCtaDockOffset()` (its own background + top border), ending a **14pt gap**
  (`CTA_DOCK_GAP`) above the dock. Nav and CTA never merge, borders never touch, and the CTA is never a
  navigation row. `handlePublish` and all gates are untouched.
- Uploads redesigned (below).

## Profile integration

`useDockScroll('profile')` on the profile `ScrollView`, `expand()` on focus, `useDockClearance()`
bottom padding. Profile content is otherwise untouched.

## Home regression

`useDockScroll('home')` on the discovery `FlatList`, `expand()` on focus, `useDockClearance()` padding.
The SN logo, Miami label, filters, event artwork, prices and search are unchanged. Bids is the same
pattern.

## Upload component redesign

New `src/components/ui/MediaUpload.tsx` replaces the legacy dashed-box + emoji `ImageUploadTile`. Two
variants on one behaviour contract (`useImageUpload`'s `localUri`/`status`/`error`):

- **`cover`** — compact media picker. Empty: a slim tappable **row** (photo icon + "Cover image" +
  "JPG or PNG, 16:9" + a red add glyph), no giant empty canvas. Selected: a real **16:9 preview** with
  **Replace** and **Remove** in a bottom bar; uploading → spinner overlay.
- **`compact`** — functional evidence (proof of ownership, transfer proof). Empty: a single ~64pt row
  (doc icon + label + helper + "Add"). Selected: a 40pt **thumbnail** + **"Image added"** + Replace /
  Remove. Uploading → inline spinner.

No emoji (icons from `IconSymbol`), V2 tokens, radius 0, hairline, dark surface. Create's cover uses
`cover`; Create's proof and Transfer's evidence use `compact`. The redundant `FieldLabel` above each
upload was dropped — the control carries its own label. Upload buckets/paths, `pickImage`,
`uploadImage`, `reset` and validation are all preserved; `onRemove` is wired to the uploader's `reset`.

## Legacy component audit

Searched cover/proof/image/file/media upload usages. `ImageUploadTile` was used in **Create** (cover +
proof) and **Transfer send** (evidence) — both migrated to `MediaUpload`. `ImageUploadField.tsx` is a
thin wrapper of `ImageUploadTile` with **no importers** (dead code); left untouched rather than
migrated, since it renders nothing in production. `ImageUploadTile.tsx` is left on disk (only the dead
wrapper references it) — no production screen imports it now. A test asserts Create and Transfer no
longer contain `ImageUploadTile`.

## Tests

558 / 22 files (was 548 / 21). Nav suite updated for universal collapse + keyboard + CTA; new
`media-upload.test.ts` (10) guards both variants, empty/preview/uploading/replace/remove, the compact
"Image added" confirmation, no emoji, IconSymbol icons, V2 tokens, and the Create/Transfer migration
(no legacy tile, private proof bucket preserved). `tsc` clean; `expo lint` 28 warnings / 0 errors (no
new).

## Device-review checklist (second pass)

- **Home** — expanded dock at top; scroll down → contracts to bottom-left; content unobstructed; scroll
  up / near top → expands; tap compact → expands; pull-to-refresh unaffected; fast flicks + slow scroll.
- **Create** — dock stable at top; scroll down the form → collapses; **List ticket CTA sits above the
  dock with a clear gap and never merges**; open keyboard → dock drops away, fields + CTA visible;
  dismiss → dock restores; last field/CTA reachable above the dock.
- **Create uploads** — new compact **Cover image** row; pick → 16:9 preview + Replace/Remove; new
  **Proof of ownership** compact row; pick → thumbnail + "Image added"; no emoji, no giant boxes.
- **Profile / Bids** — dock stable at top; scroll down → collapses; scroll up → expands; last cards not
  covered; Settings nav works from Profile.
- **Float + size** — dock visibly floats above the bottom edge and reads slightly larger/more
  intentional than before.
- **Nested screens** (Listing Detail, Place Bid, Checkout, Settings, Transfer, My Listings, Edit) — no
  dock.

## Remaining concerns (owner tuning on device)

- **Collapse feel / thresholds** (90 / 40 / 28) and **duration** (220ms) are best judged on hardware.
- **Float height** (`DOCK_GAP` 22) and **size** (60 / 30) — the intended "slightly bigger, floats
  higher"; nudge either constant if it reads too much/little on device.
- **Glass depth** — this is dark **translucency**, not a true frosted blur (`expo-blur` is not installed
  and was deliberately not added). If Jose wants real backdrop blur, adding `expo-blur` is a small
  owner-approved follow-up; the dock's surface is structured to become a `BlurView` with the same
  overlay + hairline.
- **Width-contraction morph** runs on RN `Animated` (JS-driven, since width is a layout prop) — smooth
  for a one-shot 220ms transition; if the contraction shows any jank on device, it can move to
  Reanimated (already installed) without a new library.
- Not device-verified this session — the local simulator is still blocked (0 eligible destinations), so
  no visual approval is claimed; this revision is prepared for Jose's second iPhone pass.

---

## NAV GEOMETRY OWNER REVISION (2026-09-03, second geometry pass)

Second device review: everything approved except the float height and size — the dock still read too
low and not noticeably larger. Geometry-only change; the collapse machine, routing, content,
active-state logic and glass material are untouched.

| Constant | Old | New |
| --- | --- | --- |
| `DOCK_GAP` (float above safe area) | 22 | **36** |
| `DOCK_HEIGHT` | 60 | **66** |
| `ITEM_WIDTH` | 60 | **66** |
| `ICON_SIZE` (inactive / active) | 25 / 25 | **27 / 28** |
| `DOCK_RADIUS` | 30 | **33** |
| Selected capsule | m 9/7, r 21 | **m 8 (v) / 9 (h), r 24** |

Derived (not hardcoded):

- **Full dock width** `4 × 66 + 8×2 = 280` (was 236); five-item ready `5 × 66 + 16 = 346`.
- **Compact width** `66 + 8×2 = 82` (was 68) — the same object collapsed, same elevated bottom anchor.
- **Content clearance** `useDockClearance() = insets.bottom + (DOCK_HEIGHT + DOCK_GAP) + DOCK_GAP =
  insets.bottom + 138` (was ~104) — Home/Bids/Profile lists and Create's scroll clear the taller/higher
  dock automatically.
- **Create CTA offset** `useCtaDockOffset() = insets.bottom + DOCK_GAP + DOCK_HEIGHT + CTA_DOCK_GAP =
  insets.bottom + 116` (was ~96); `CTA_DOCK_GAP` stays **14**, so the List ticket CTA remains a separate
  surface above the dock.

The bottom anchor is still `insets.bottom + DOCK_GAP` (safe-area-aware, no hardcoded inset), so the dock
now sits clearly in the lower third with visible black space beneath it before the home indicator. The
active icon reads slightly stronger (28 vs 27) with no red fill or glow. Animation (220ms), the collapse
state machine, and the `rgba(18,18,20,0.72)` glass are unchanged.

Verification: 558 tests / 22 files, tsc clean, 28 lint warnings / 0 errors (no new), iOS bundle HTTP 200.
Not device-verified this session (simulator blocked) — prepared for Jose's next iPhone pass.

---

## NAV POSITION FIX (2026-09-03, root-cause anchor bug)

Size/radius/glass/collapse all approved; the dock still hugged the bottom. **Root cause found:** the
dock (`styles.dock`) was `position:absolute` with `bottom: 0` inside the wrapper, and the wrapper carried
the lift as `paddingBottom: insets.bottom + DOCK_GAP`. An absolutely-positioned child is positioned
against its parent's **padding edge**, so that `paddingBottom` was **ignored** — the dock sat at the
wrapper's bottom (the screen edge) no matter what `DOCK_GAP` was. Every prior `DOCK_GAP` bump only changed
the dock's height/clearance, never its Y. That's why "move it higher" never moved it.

**Fix:** the lift now lives on the dock itself — `bottom: insets.bottom + DOCK_GAP` is applied directly
to `styles.dock` (dynamic, safe-area-aware), and the wrapper's ignored `paddingBottom` is removed (its
height is set inline to span up to the dock's top so touches still register inside the `box-none`
parent). `DOCK_GAP` raised 36 → **48**.

- **Old effective bottom anchor:** the screen bottom edge (`~0` — padding ignored; the dock did not even
  clear the safe area).
- **New effective bottom anchor:** `insets.bottom + 48`, applied to the dock.
- **Vertical lift applied:** `insets.bottom + 48` (previously ≈ 0) — on a home-indicator iPhone (~34pt
  inset) roughly **82pt** of real lift, so there is now an obvious black band between the dock and the
  home indicator.
- **Collapsed control:** same element, same `bottom` anchor — it rises by the identical amount.
- **Derived, auto-updated:** `useDockClearance()` = `insets.bottom + (66 + 48) + 48 = insets.bottom + 162`;
  `useCtaDockOffset()` = `insets.bottom + 48 + 66 + 14 = insets.bottom + 128` (`CTA_DOCK_GAP` stays 14).
  No per-screen padding; Home/Create/Bids/Profile clear the raised dock automatically.

Nothing else changed: `DOCK_HEIGHT` 66, `ITEM_WIDTH` 66, icon 27/28, `DOCK_RADIUS` 33, selected capsule
(m 8/9, r 24), full width 280, compact width 82, 220ms animation, `rgba(18,18,20,0.72)` glass, collapse
machine and routing all identical. Verification: 558 tests / 22 files, tsc clean, 28 lint warnings / 0
errors (no new), iOS bundle HTTP 200. Because this was a positioning **bug**, the dock will now move as
expected on device, and `DOCK_GAP` is finally the honest lever if the exact float wants a nudge.

# B — authenticated render review at C's corrected candidate

| | |
|---|---|
| **Source commit** | **`262c908b`** (`v3/midnight-app`) — C's corrected candidate, not the `404bce38` baseline |
| **Harness** | `/Users/josetascon/snatchit-v3render`, Metro :8083, sandbox env from `eas.json` preview profile |
| **Harness-only changes** | exactly two, both documented in `harness/README.md`: the `Appearance.setColorScheme` web guard, and `fonts.ts` returning `FAMILY[role]` on web. **Nothing else.** No app behaviour altered |
| **Viewport** | 393 × 852 logical (iPhone 15 Pro), dark |
| **Session** | sandbox DV buyer `919d511e…`, seeded page-side so **no credential or token entered the transcript, a log, or a committed file**. The served seed was deleted immediately after use |
| **Fonts verified on this screen** | `Oswald_700Bold` **loaded**, `Inter_400Regular` **loaded**, `Inter_500Medium` **loaded**, `Inter_700Bold` **loaded**. `Inter_600SemiBold` unloaded — correct, nothing on Home uses it |

---

## 1 · The dock avatar — root cause found

**`AdaptiveDock.tsx:146` is the only caller that passes a width:**
`getAvatarUrl(youPath, { width: AVATAR, devicePixelRatio })`. That produces

```
/storage/v1/render/image/public/avatars/<uid>/avatar_….jpg?width=56&resize=cover&quality=45
```

**`width` is sent with `resize=cover` and no `height`.** Measured from the loaded element:
**`naturalWidth 56 × naturalHeight 1176`** — a 1 : 21 sliver, not a square. Rendered into the 28 × 28 circle
with `object-fit: cover`, only a narrow horizontal band of the picture survives. That band is the red/dark
smear in the owner's screenshots.

**Why Profile looks right and the dock does not:** `ListingDetailScreen.tsx:1271` and
`app/settings/edit-profile.tsx` call `getAvatarUrl(path)` **with no options**, so they get the untransformed
original. The dock is the only surface that requests a derivative.

**Not a geometry defect.** Measured: the image is 28 × 28, its masking parent is `border-radius: 9999px;
overflow: hidden`, and the ring parent is 36 × 36 — the approved 28pt circle with a ring outside it. The dock
is `y 738, h 66, radius 33, overflow hidden`; the avatar spans `y 749–777`, **wholly inside it**.

**For C:** the transform needs **both** `width` and `height` for `resize=cover` to crop to a box — or the
dock should drop the width option and crop the original, as the other two callers already do. Verify the
returned `naturalWidth/naturalHeight` before and after; "an image appears" is not the test.

## 2 · Two of my earlier claims, re-checked against numbers

| Claim | Outcome |
|---|---|
| The feed price looked like condensed Oswald | **Wrong — withdrawn.** Measured `Inter_700Bold`, 20px. The board's rule ("price · Inter_700Bold · never Oswald") is honoured |
| The dock avatar is clipped by the dock edge | **Withdrawal confirmed with geometry.** Avatar `y 749–777` inside dock `y 738–804`. The appearance of clipping is the image content, not the layout |

## 3 · Home vs `midnight-home-clean.png` — open at `262c908b`

| # | Category | Approved reference | Build at `262c908b` |
|---|---|---|---|
| H1 | composition | SN logo **left**, search right — **one** header row | Logo **centred**, plus a **"MIAMI"** row, plus a **filter-chip** row: three rows of chrome |
| H2 | radius | Chips at the chrome radius | `YOUR SCENE` / `PRICE` / `FILTERS` are **square** |
| H3 | image/fallback | Missing artwork is a **plate carrying the SN monogram**, filling the slot | A **letter glyph** floating in an otherwise empty block; the feature keeps the slot's height but not its treatment |
| H4 | composition | Feature name and meta sit **over** artwork, inside the slot | With no artwork the name sits at the slot's bottom edge on bare canvas |

**Confirmed correct and not to be changed:** feature name `Oswald_700Bold` 30px (`nameFeature`), price
`Inter_700Bold` 20px, dock label `Inter_500Medium` 11px, dock radius 33, row artwork radius 8.

## 4 · Evidence class

Web render at a pinned commit. **Not iOS evidence.** Still requiring native capture: how these faces
rasterise on iOS, safe areas and the real status bar, keyboard behaviour, native dialogs and Dynamic Type.

# B — independent render review at the agreed pin `911f65fd`

| | |
|---|---|
| **Pin** | **`911f65fd`** — resolved against `v3/midnight-app` and confirmed to be its **tip**, not taken on report |
| **Harness patches** | **ZERO.** Both of my local fixes are superseded by C's commits and removed; `git status` shows no modified tracked file. C's font fix is the better one — `app/+html.tsx` declares one `@font-face` per role under the same per-face names the native runtime loads |
| **Remaining harness difference** | **none in app source.** Only my own untracked capture tooling (`capture.sh`, `cdp-capture.mjs`, `seed-profile.mjs`), which the app does not import |
| **Viewport** | 393 × 852 logical × 3 = 1179 × 2556, signed in as the sandbox DV buyer |
| **Fonts on these captures** | `Oswald_700Bold`, `Inter_400Regular`, `Inter_500Medium`, `Inter_700Bold` **loaded and in use** with **no patch** |

**Images:** `comparisons/cmp_home_dark_911f65fd.png`, `comparisons/cmp_home_light_911f65fd.png`

---

## 1 · The Light-capture problem was mine, and it is resolved

I reported that the app did not follow `prefers-color-scheme`. **That was wrong and I withdraw it.** I had
probed `document.body`'s background, which is not the app canvas — the RN root View paints it. Measured
properly at this pin: the dark capture's canvas samples `(0,0,0)` and the light capture's samples
`(255,255,255)`. **Both appearances capture correctly and Light comparisons are trustworthy.**

Explicit Light/Dark and the System path are therefore all exercised through the app's own resolution. The
stored preference was absent (System) throughout, and the resolved palette followed the emulated system
value in both directions.

## 2 · Closed at this pin — verified in the render

| Finding | Evidence |
|---|---|
| Filter chips square | **Closed** — the chips render with the chrome radius in both appearances |
| Missing artwork drew a letter glyph | **Closed** — the approved **SN monogram plate** now renders, on the feature and on both rows |
| SN logo centred · "MIAMI" row · no section heading · prices without decimals | **Closed** — logo left, no city row, a data-driven heading ("Later"), `$110.00` |
| Dock avatar a red/dark smear | **Visibly corrected** — a recognisable photo. **Still not closed**, see §4 |

## 3 · NEW and serious — Light, missing artwork: the feature's text is invisible

**The one case the boards never show**, because every board's feature has a photograph.

Measured on the app at this pin, Light, feature slot with no artwork:

| Element | Colour | Behind it | Contrast |
|---|---|---|---|
| Name "Device D7" | `rgb(255,255,255)` — `onArt.primary` | `rgb(244,244,246)` | **1.10 : 1** |
| Meta line | `rgba(255,255,255,0.78)` | `rgb(244,244,246)` | **1.08 : 1** |
| Price + "buy now, all-in" | white | `rgb(244,244,246)` | **~1.1 : 1** |

The name, the date, the quantity, the clock **and the price** are all effectively invisible. The comparison
image shows it plainly.

**Cause, and it is a design-contract break rather than a token slip.** `onArt` is deliberately identical in
both appearances — *"text over artwork sits on the image and its scrim, never on the canvas, so it stays
white however the canvas flips."* That contract holds for a photograph. **It does not hold when the slot is
showing a fallback**, because the fallback here is a light surface in Light.

The approved foundations already name the right value: **`surface.plate` `#141519` — "missing-artwork
plate"** — which is dark, and would give white **18.24 : 1**. The feature is using the light surface instead.

**For C — either is acceptable, both must hold in Light and Dark:** keep the feature's fallback plate dark in
both appearances as the foundations define it, **or** switch the over-artwork inks when the slot renders a
fallback rather than a photograph. The row thumbnails are fine as they are — no text sits on them.

## 4 · Still open

| # | Item |
|---|---|
| H1 | **The filter-chip row is not in the approved Home composition at all.** Radius is fixed; presence is not. The board goes header → section heading → feature |
| AV | **Avatar not closed.** A photo renders, but I have not yet measured the returned derivative's dimensions, nor captured the same source photo on Profile and the dock at this pin. The prior evidence was 56 × 1176; closing requires a square derivative and a matching visible crop |

## 5 · Scope held

No fixture mutation. **Checkout not opened** — mounting it creates or reuses a PaymentIntent. Upload and
account-switch cases stay **pending**, since their operations are not authorised. Buy-now leads wherever the
resolver makes it primary; the older boards do not override that.

**Evidence class:** web render at a pinned commit. Not iOS evidence.

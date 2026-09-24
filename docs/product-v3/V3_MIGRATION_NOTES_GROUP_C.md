# Migration notes — Create listing and Checkout

**B · 2026-09-24.** Source trace at `v3/midnight-app` @ `2619b9e1`. **Create: 58 token reads + 7 literals.
Checkout: 25 token reads, 0 literals.** Mechanical for most of it. Three failures below are **measured by me**,
not inherited from the trace.

> **Evidence: source + computed.** Not rendered review, not device verification.

---

## Three verified light-mode failures

### F-32 — `brand.red` as **text** fails in Daylight

`CreateListingScreen.tsx:1119` — the selected sheet-row label.

| | |
|---|---|
| Midnight, on panel `#0A0A0A` | **5.10:1 — passes** |
| **Daylight, on panel `#F4F4F6`** | **3.53:1 — FAILS 4.5:1** |

The palette certifies `#FF1A1A` as a **fill** (3.88:1 against white, clearing the 3:1 control bar) and pairs
it with a black label. **It certifies nothing about the red as a foreground on a light panel.** Selection
here also carries a `✓` and `accessibilityState`, so meaning is not colour-alone — but the label itself is
illegible by the standard. **Needs a darker red for text in Daylight, or the label stays `text.primary` and
the `✓` carries the colour.**

### F-33 — the Buy Now switch thumb goes near-black on a red track

`CreateListingScreen.tsx:719` — `thumbColor={v2.text.primary}`. In Daylight `text.primary` is `#0B0C0E`, so
a mechanical swap puts a **near-black thumb on the red "on" track**. **The thumb must stay white** — a
literal or `onArt.primary`, never a canvas-relative token.

### F-34 — seven dark-only literals under the risk banners, and they carry safety copy

`CreateListingScreen.tsx:1098-1101`:

```
riskBannerMedium   #332B00 / #665500      riskBannerHigh  #331A00 / #663300
riskBannerCritical #330000 / #660000      riskBannerText  #FFDDBB
```

`#FFDDBB` measures **10.97 – 14.30:1** on those three dark fills and **1.29:1 on white**. If the fills are
carried across unchanged, the banner text is **invisible** in Daylight — on the component that warns a seller
their account is under review or blocked.

**The palette has no tinted status-surface group** (only `brand.redSoft`). Either add three in both
appearances, or rebuild the banner as `border` + `status` text on `surface.surface`.

---

## Meaning carried by colour alone — findings, not migration notes

| # | Where | Why |
|---|---|---|
| **1** | `CheckoutNative.tsx:1125` | The reservation countdown **recolours to error at zero while the copy stays neutral** — *"Checking your hold"*. Red is the only signal the state changed |
| **2** | `CreateListingScreen.tsx:183, 232` | **Input focus** is signalled solely by the underline turning `brand.red` — no weight, icon or label change |
| **3** | `CreateListingScreen.tsx:718` | The Buy Now switch's **on/off is the track colour**; the row title and hint are identical in both states. Mitigated only by `accessibilityState` |
| **4** | `CreateListingScreen.tsx:1098-1100` | The three risk tiers **rank only by hue** under one shared text colour — and **`critical_risk` and `listing_blocked` share both copy and style**, so those two are indistinguishable by any channel |

**These are pre-existing in Midnight.** The appearance work surfaces them; it did not cause them. They are C's
to rule on, and #4 is the one I would fix regardless of appearance.

---

## Non-mechanical, beyond the three failures

| Where | Issue |
|---|---|
| `Create:152, 183` error branch | `status.error` used as a **1px underline**. The palette re-picked the light status trio **as text colours**; nothing grades `#C41414` as a non-text indicator at 3:1 |
| `Create:1111` | `text.faint` on sheet group headings — below the "may not carry task-critical information" floor. Should move **up to `muted`**, not mirror across |
| **`border.strong` splits two ways** | Six uses are **control edges** (`Create:152,183,232,718,720,1060,1081`) → `border.control`, matching `Button.tsx`. **One is a genuine heavy rule** (`Checkout:1161`, the sticky-bar top) and keeps `strong`. Identical hex today — semantics, not pixels |
| `Create:1090`, `Checkout:1162` | `surface.surface` **inverts**: darker than canvas in Daylight, lighter in Midnight. Compiles fine; the elevation metaphor flips |
| `Create:1024`, `Checkout:1149` | **Money at sub-primary contrast**: the buyer all-in figure sits at `text.muted`, and the price-change sentence carries **both the old and new totals** at `text.secondary`. Survives the swap unchanged — worth a look, not a blocker |
| `Checkout:1119, 1120` | **Dead colour** — `s.eventName`, `s.meta` have no call site since identity moved to `OrderIdentity`. Delete, don't migrate |
| **Structural, both files** | Colour lives in module-level `StyleSheet.create` read by helpers defined **outside** the component — `Section`, `SelectRow`, `MoneyField`, `MultilineField`, `FieldLabel`, `ReviewRow`, `Row`. `palette` only exists per-render. Checkout's `RefundView`/`ConfirmationView` already call hooks and can take `useTheme()`; **Create's six pure helpers cannot without restructuring** |

**No artwork rows in either file.** Neither screen paints over a seller photo: Create hands the image to
`MediaUpload`, Checkout hands `cover` to `OrderIdentity`, and the cover-image error is rendered as
canvas-relative text **below** the tile — which is correct.

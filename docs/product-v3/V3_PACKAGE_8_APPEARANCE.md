# V3 Package 8 — light and dark appearance

**B → C · 2026-09-23.** Full light and dark support across the whole inventory, authorised without a further
approval round. **Payment behaviour unchanged. Isolated V3 branch.**

**Artifacts:** `pkg8-appearance-tokens.png` · `pkg8-bid-both-appearances.png` · `pkg8-bid-{dark,light}.png` ·
`pkg8-appearance-{dark,light}.png`.

---

## 1 · The existing infrastructure — I inspected it first, and there is none

| Checked at `5b255838` | Result |
|---|---|
| `useColorScheme` | **0 matches in the entire tree** |
| `Appearance.*` | **0 matches** |
| `colorScheme` | **0 matches** |
| Per-scheme tokens in `src/theme/v2.ts` | **None.** `surface`, `text`, `brand`, `border`, `status` are flat single-valued groups |
| C's branch `v3/midnight-app` | **0 matches** for `useColorScheme` |

**The app is dark-only and hard-coded.** There is nothing to reuse for appearance — but there *is* the right
place to build it: **`v2.ts` and its mirror `packages/design-tokens/src/brand.ts`**. Each semantic name gains
a second value. **No screen gains a branch, and no new backend preference or migration is involved**, exactly
as the instruction says.

---

## 2 · Daylight is derived, not inverted — and one of my reasons was wrong

### The correction

I reported a red fill's contrast **against the canvas** and used it to argue that `#FF1A1A` could not carry a
black label on white. **Those are two different measurements and I ran them together.**

| Question | Measurement | Answer |
|---|---|---|
| Does the label pass? | **text vs its own background** | **black on `#FF1A1A` is 5.41:1** — and it is 5.41:1 whatever sits *behind* the button |
| Is the control identifiable? | **fill vs canvas** (1.4.11, 3:1) | `#FF1A1A` vs white is **3.88:1** — passes |

**The brand red never needed changing.** `#D60000` and the white label are **withdrawn**; both schemes use
`#FF1A1A` with a black label, and `brand.onRed` is a **constant, not a per-scheme token** — that claim is
withdrawn too.

### What the measuring did establish, and still holds

1. **Elevation flips.** `surface.panel` sits lighter than the canvas on Midnight, darker on Daylight.
2. **Two signal colours cannot survive as TEXT on white:** `status.warning` `#FFB020` is **1.9:1** and
   `status.success` `#3DDC84` is **1.6:1**. Daylight re-picks both. *(This is a text/background measurement,
   correctly categorised.)*
3. **`text.muted` is not mirrored** — a mirrored value failed **4.18:1** on the plate; solved to `#686C73`,
   the lightest value that passes on the *darkest* surface, at **4.56:1**.

### One new token: `border.control`

**Dividers and control boundaries are different things.** A rule that separates rows identifies nothing, so
1.4.11 does not apply and `border.default` is **listed, not graded** (1.37:1 / 1.32:1). **The edge that
identifies an input, a stepper or a chip is a control boundary** and is graded at 3:1 — that is
`border.control`, new in both schemes.

### The report, as it now stands

**A · Text on background (1.4.3, 4.5:1)** — no large-text relief: the shipped Button label is
`textStyle('label')` = **12pt bold**, which is not large text.
**B · Non-text contrast (1.4.11, 3:1)** — only boundaries needed to identify a control.
**Listed, not graded** — dividers, and disabled controls (both criteria exempt inactive components).

**23 graded pairs per scheme. One fails, in both — see F-30.**

## 3 · Rules that apply to every surface

- **Artwork does not invert.** A seller's photo is its own context: the protective scrim and the white text
  over it are identical in both schemes. **The scrim is not a guarantee.** It was measured against **four
  generated artwork variants**, worst case 5.17:1 — evidence that it holds for those four and nothing more. A
  real upload can be brighter, busier or flatter than any of them. **C checks real uploads; no board here
  claims every image passes.**
- **Status bar follows the scheme** — light content on Midnight, dark on Daylight.
- **Keyboard appearance follows the scheme**, so it never arrives as a white slab on a dark screen.
- **The missing-artwork plate and the profile-photo fallback are surface-derived** and follow automatically.
- **Skeletons** keep the shipped 0.4→0.7 opacity pulse; only the base surface changes.
- **No screen defines a colour.** No hard-coded hex survives outside the token file and its mirror.

---

## 4 · The Appearance setting

`settings/appearance` — three rows, **System first and default**.

| Row | Sub-line |
|---|---|
| **System** | *"Follows your phone"* |
| **Light** | — |
| **Dark** | — |

**Nothing else on the screen.** *"Saved on this device."* is **removed**, and there is no instructional
paragraph. *"System"* alone does not say what it follows, so it keeps its sub-line; Light and Dark need no
explanation and get none.

System follows the phone and changes **live, without a restart**. An explicit choice **overrides the phone
until System is chosen again** and **persists across restarts**.

---

## 5 · Checkout — the amount's SOURCE, not just the state (a proposal for A)

**Artifact:** `pkg8-checkout-amount-source.png`.

My earlier three-state exclusion was a **state-only rule**, and it missed the axis that matters:

```
CheckoutNative.tsx:721   const totalCents = serverBreakdown ? serverBreakdown.total : acceptedTotalCents;
```

**The amount has two sources.** `serverBreakdown.total` is authoritative; `acceptedTotalCents` derives from
the `totalCents` **route param**, which the screen's own comment calls *"Display estimate only"*.

All eleven states are tabulated on the board against source and validity. Two corrections to what I said
before: **`checkingHold` should show the total** — I excluded it wrongly, since it is the *hold* being
checked, not the amount — and **`authLoading` / `paymentLoading` / `paymentError` / `unavailable` may hold
only an estimate**, which I had not considered at all.

> **Proposed rule — three conditions, not one.** Show a nearby total when **(a)** the control's label carries
> no amount, **and (b)** an authoritative server total exists, **and (c)** the state still leads to paying it.

`labelCarriesAmount` is condition (a) only: necessary, not sufficient. **An unavailable amount and a known
historical amount are different** — `holdLost` has a real figure that is no longer payable from that screen,
while `unavailable` may have nothing but a route-param estimate.

**This is a proposal, not an adopted rule. Payment logic is unchanged. A reviews it before C implements.**

## 6 · What C verifies — label the evidence honestly

All three settings · persistence across restart · **live system change with no restart** · readable contrast
in both · large text · keyboard visibility · profile-image fallbacks (including that a previous user's photo
never survives an account change).

**Say which is which:** *source-only* (read from code), *simulator*, or *device*. **My side is source-only
plus computed contrast — preliminary evidence, nothing more.** No build, no simulator, no device. The 23
graded ratios are arithmetic on token values, not observations of a running screen, and they settle none of:
**disabled controls as rendered · selected states · overlays · native dialogs and the keyboard, which the app
does not paint · real artwork.**

**C owns the theme architecture.** Reuse the semantic names and keep `v2.ts` and
`packages/design-tokens/src/brand.ts` consistent — but **adding a second value to a token does not update a
`StyleSheet.create` that captured the first one**. Static styles resolve once. C verifies that **every
mounted screen responds when System changes**, that explicit overrides persist across restart, and that
**startup does not flash the wrong appearance** before the stored choice is read.

---

## 7 · F-30 closed (2026-09-23)

**`brand.redPressed` = `#FF4C4C`** — black label **6.39:1**, fill **6.06:1** on Midnight and **3.29:1** on
Daylight. Opaque, so both appearances measure identically. Rest `#FF1A1A` with a black label, the 0.98 press
scale and `disabled: { opacity: 0.4 }` are all unchanged. Full derivation and the rejected alternatives:
`V3_FINDINGS_RECONCILED.md` → F-30, and `pkg8-f30-pressed-primary.png`.

**And a correction inside the correction:** the 3.57:1 I first reported was a **token nothing renders**.
`brand.redPressed` has zero importers; `Button.tsx:78` sets the fill unconditionally. F-30 was latent, not
live, and is relabelled ④.

---

## 8 · Five core surfaces in both appearances

**Artifact:** `pkg8-inventory-both.png` — Home, Search, Listing detail, Checkout, Your order, each as a
dark/light pair. Same layout, same words, same hierarchy; only token values differ.

### A hard-coded colour the render caught

Checkout's card chip was `fill: (38,40,46)` with `text.primary` on top — a literal that looked right on
Midnight and rendered a **dark block with near-black text** on Daylight. It is now surface-derived
(`surface.plate` + `border.control`, label `text.secondary`).

**This is the exact failure mode to expect in implementation**, and it is why a second token value is not
sufficient on its own: the literal was never a token, so nothing about adding a scheme would have found it.
**Every hard-coded colour has to be hunted, not inherited.**

---

## 9 · Where the inventory stands

| Designed in both appearances | Designed dark only — light pending |
|---|---|
| Bid entry · Appearance setting · Home · Search · Listing detail · Checkout · Your order | Create · My listings · Send/receive transfer · Bids tab · Auth (7 surfaces) · Tickets · Profile · Settings hub + 7 sub-surfaces · Dispute/report · 45 dialogs · 4 state screens · Error boundary · Outbid notice · Status banner |

**The token set is complete**, so the remaining surfaces are re-renders against it, not new decisions.

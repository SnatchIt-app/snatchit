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

## 2 · Daylight is derived, not inverted

Two things a mirror gets wrong, both caught by measuring:

1. **Elevation flips.** `surface.panel` sits *lighter* than the canvas on Midnight and *darker* on Daylight.
   Elevation reads by contrast, not by lightness.
2. **Three signal colours cannot survive the trip.** On white: `status.warning` `#FFB020` is **1.9:1**,
   `status.success` `#3DDC84` is **1.6:1**, and `brand.red` `#FF1A1A` is **3.9:1** — too weak to carry a
   black label. Daylight re-picks all three.

**`brand.onRed` is a token, not a constant:** black on Midnight's `#FF1A1A` (**5.41:1**), white on Daylight's
`#D60000` (**5.44:1**). The shipped rule "primary red + black label" becomes "primary red + `brand.onRed`".

**`text.muted` is not mirrored either.** A mirrored value failed **4.18:1** on the plate. Solved to `#686C73`
— the lightest value that passes 4.5:1 on the *darkest* surface, at **4.56:1**.

### One new token: `border.control`

A divider is decoration and WCAG 1.4.11 exempts it. **A field or stepper boundary is not.** Midnight's
divider is **1.37:1** — correct for a rule, wrong for a control edge. `border.control` carries **3:1** in both
schemes (`#64656A` / `#8A8B90`) and applies to inputs, steppers and chip outlines only.

**21 pairs measured per scheme. All pass.** Ratios are computed with alpha compositing, not estimated —
the script is `light.py`, and the numbers are on the token board.

---

## 3 · Rules that apply to every surface

- **Artwork does not invert.** A seller's photo is its own context: the protective scrim and the white text
  over it are identical in both schemes. A light-mode hero with dark text over an unknown photo is the one
  thing neither palette can guarantee, and the measured scrim already solves it.
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

Beneath: **"Saved on this device."**

System follows the phone and changes **live, without a restart**. An explicit choice **overrides the phone
until System is chosen again** and **persists across restarts**. *"System"* alone does not say what it
follows, so it gets a sub-line; Light and Dark need no explanation and get none. The local-only line is there
because nothing syncs, and that is worth stating rather than leaving to be assumed.

---

## 5 · Checkout — the nearby total needs a second condition

C's `labelCarriesAmount` gives *"on the action or beside it, never both"*. **That is necessary and not
sufficient.** Per the owner: a nearby total is appropriate only when **that amount is valid for the current
state**.

| `payControl` state | Label | Nearby total |
|---|---|---|
| `paymentReady` | `Pay $132.00` | **No** — the label carries it |
| `paymentError` | *Try again* | **Yes** — the total is still the order total |
| `authLoading`, `paymentLoading`, `confirming`, `finalizing`, `checking` | in-progress | **Yes** |
| **`holdLost`** | *Back to listing* | **NO.** The hold is gone; that amount is no longer what this buyer would pay |
| **`statusUnknown`** | *Check again* | **NO.** The payment status is unknown, and a confident total beside it reads as a confirmed charge |
| **`checkingHold`** | *Checking your hold* | **NO.** Not yet established |

**The rule: show the nearby total when the label carries no amount AND the state has an established, current
total.** Never make an unknown or stale amount look confirmed. `holdState`'s own copy already says what is
unknown; the number must not contradict it.

---

## 6 · What C verifies — label the evidence honestly

All three settings · persistence across restart · **live system change with no restart** · readable contrast
in both · large text · keyboard visibility · profile-image fallbacks (including that a previous user's photo
never survives an account change).

**Say which is which:** *source-only* (read from code), *simulator*, or *device*. My side is **source-only
plus computed contrast** — no build, no simulator, no device. The 21 ratios are arithmetic on token values,
not observations of a running screen.

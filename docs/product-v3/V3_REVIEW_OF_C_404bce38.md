# B — independent visual review at `404bce38`

Pinned to **`404bce38969780f1db057e96dec71609c6795ed4`**. Every finding below was re-checked against the
**real render path** at that commit — the JSX that mounts it and the condition that reaches it — not against
the commit message and not against the older report.

**Evidence classes are kept apart.** Everything here is **source review** and **computed contrast**
(palette values composited and measured). **No device observation exists yet**; those belong in
`V3_PHONE_TEST_CHECKLIST.md` and are recorded only once the new build has been run.

---

## 1 · Closed — verified fixed at the render path

| Finding | Fix, at the render path | Measured |
|---|---|---|
| **Dimmed text — `FeedRow`** | The `dimmed` style moved off `s.row` and onto the `<EventMedia>` element (`FeedRow.tsx:91`). The row's `<Text>` children are no longer inside the dimmed layer | "Sold" / "Ended" **3.45 → 9.96:1** Midnight, **2.71 → 8.48:1** Daylight. Metadata **2.49 → 6.27** / **2.22 → 5.27**. Title **4.33 → 19.57** Daylight. **All pass** |
| **Dimmed text — `SellerListingCard`** | Same move: `cardCancelled` now sits on `<EventMedia>` (`:92`), not on the `Tappable` | "Cancelled" **1.49 → 6.26:1** Midnight, **1.54 → 4.80:1** Daylight (on the card surface). Badge no longer dimmed. **All pass** |
| **Field prompts** | `selectPlaceholder` is `p.text.muted` (`CreateListingScreen.tsx:1091`). `selectValue` still switches to `primary` when filled, so filled/unfilled still reads | **2.39 → 5.27:1** Daylight, **2.46 → 6.27:1** Midnight. **Pass** |
| **The 6-digit code input** | A **persistent visible label** — `<Text style={textStyle('micro')}>Verification code</Text>` above the field (`notifications.tsx:187`). The faint placeholder is now genuinely redundant decoration, which is the correct use of `faint` | — |
| **F-33 switch thumb** | `thumbColor={palette.onArt.primary}` (`notifications.tsx:243`). Both switches now agree | White thumb in both appearances |
| **Support route** | The blocked path's alert is now the three-argument form with a real action: `{ text: 'Contact support', onPress: () => router.push('/settings/support') }` (`CreateListingScreen.tsx:435`), reaching the screen whose mailto button already worked | — |
| **Misleading transient copy** | A new client-only reason, `check_unavailable`: *"We couldn't check your account status just now. You can still publish."* Submission behaviour is preserved — the branch still `return true` (`:416`) | — |
| **New-state styling** | `riskBannerNeutral: { borderColor: p.border.control }` (`:1159`) — the new reason is styled, not left on an unset border | 3.40:1 Daylight, 3.61:1 Midnight |

### 1b · The brand mark (the "logo" defect) — closed, and I swept for recurrences

Not one of mine; verified independently. `brand/sn-logo-white.png` is **white on transparent** and was
rendered untinted, which was correct while every screen was Midnight and makes the monogram **invisible on
Daylight's white canvas**. Fixed at `AuthBrandMark.tsx:48` with `tintColor: p.text.primary` — `#FFFFFF` on
Midnight, `#0B0C0E` on Daylight (19.57:1 against the light canvas; the 3:1 graphical bar is cleared many
times over).

I swept the tree for the same asset used anywhere else: exactly two call sites exist,
`AuthBrandMark.tsx:25` and `HomeHeader.tsx:39`, and **both tint to `p.text.primary`**
(`HomeHeader.tsx:87`). No untinted use of a white-on-transparent brand asset remains. The mark reaches
every auth screen through `AuthScreen.tsx`, so sign-in and all four signup steps are covered by the one fix.

On the transient copy I had recommended showing nothing; C chose a true neutral sentence instead. **C's
choice is the better one and I withdraw mine** — it carries real uncertainty ("the check didn't answer")
and tells the seller publishing continues, which silence does not. It adds one short line to a screen that
otherwise says nothing about eligibility.

Also accepted: keeping **one sentence and one treatment** for `critical_risk` and `listing_blocked`. The
inline comment states the reason correctly — the two differ in origin but not in what the seller can do.

---

## 2 · Remaining actionable defects — two, both small

### 2.1 · The blocked **banner** still has no route; only the alert got one

`CreateListingScreen.tsx:874-889` — the banner is a `View` + `Text` with `accessibilityRole="alert"` and
**no interactive child**. The alert at `:433-436` now routes to support, but **the alert is transient and
the banner persists**. A seller who taps "Not now", or who dismisses the alert and returns to the form,
is left looking at *"You cannot create listings at this time. Contact support."* on a surface that offers
no way to do it — which is the exact defect the alert fix was for.

**Fix:** give the banner the same action beneath its sentence — a `Pressable` with its own
`accessibilityRole="button"` pushing `/settings/support`, rendered only for the two blocked reasons. The
banner keeps `accessibilityRole="alert"`. Identical for both reasons, so nothing about which state the
seller is in is exposed.

### 2.2 · "Cancelled" is still rendered twice on the same card

`SellerListingCard.tsx:106` renders `<Badge label={sellerBadgeLabel(badge)} …>` = **"Cancelled"**, and
`:116` renders `<Text style={s.dim}>Cancelled</Text>` directly below it. Same word, no new information.

C's change fixed the **contrast** of that line; the **redundancy** is untouched, and it is the only exact
duplicate in that slot. I checked the whole slot, not just this state — every other branch earns its place:

| Badge | Line below | |
|---|---|---|
| Active / Ending soon | `2d 4h left` · `43m left` | **Keep** — the badge says *that*, the line says *when* |
| Ended | Winner selected | **Keep** — the outcome |
| Sold | Action needed — send the tickets | **Keep** — the next action |
| Sold | `Sold Sep 24` | **Keep as written** — the word carries the date; "Sep 24" alone is ambiguous and it is the only date on the card |
| **Cancelled** | **Cancelled** | **Remove the line** |

**Fix:** delete the `cancelled` branch of the bottom-left slot. The Badge carries the word and it is already
in `a11yLabel` via `sellerBadgeLabel(badge)`; `canEdit` / `canDelete` govern the actions column separately,
so the row is not left bare. There is no `cancelled_at` to put there instead.

This is also the lean-UI direction applied: the line explains a state the badge beside it already states.

---

## 3 · Not defects — checked and left alone

- **`priceDimmed`** (`FeedRow.tsx:112`, `:156`) survives, but it is a **token swap** to `text.secondary`,
  not a layer opacity — 9.96:1 / 8.48:1. Correct: the price recedes without losing legibility.
- **`faint` placeholders** across the form fields. Every one now sits under a visible label, so the token
  carries no information — its designed role.
- **The three risk tiers sharing an edge treatment.** The tiers are separated by three different sentences;
  the hue never carried them. Collapsing them is aligned with not exposing internal classifications.

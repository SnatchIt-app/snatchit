# B — review of C's migration and fixes at the build commit

**Reviewed: `9c6c9bf4`** (build 23) **and `24b021a3`** (the one commit after it). Read at those commits,
not at the older appearance-audit commit. Every number below is measured from the palette as it stands,
composited, not taken from a token name or an import list.

**Superseded:** the "44 unmigrated screens" count in `V3_HANDOFF_B_20260924.md` predates `4d1e4b3d`.
The migration is complete; that number is withdrawn, not carried forward.

---

## 1 · The migration itself — verified independently

I ran my own scan over the whole tree at `24b021a3` (comments stripped, counting actual
`v2.<colourgroup>.` accesses rather than imports):

| File | Static Midnight colour accesses |
|---|---|
| `app/_dev/foundation.tsx` | 32 — the screen whose purpose is to display the tokens |
| `src/theme/palette.ts` | 3 — builds both palettes *from* the tokens |
| **every other `app/` and `src/` file** | **0** |

This independently reproduces C's claim. The previous count of 53 consumer files / 546 refs is closed.
AM1/AM2 pin the two exemptions so a third cannot be added quietly — I checked the assertion, not just
the test name.

## 2 · The six fixes — four closed, one closed with a correction, one half closed

| Fix | Verdict | Evidence |
|---|---|---|
| **F-31** `status.onFill` | **Closed** | White on Daylight's dark status fills; the ink now flips with the scheme instead of assuming black |
| **F-32** `brand.redText` | **Closed** | Daylight `#D31212` measures 5.43:1 on canvas, 4.95:1 on the panel |
| **F-34** risk-banner literals | **Colour side closed** | The old `#FFDDBB` on `#332B00` (1.29:1 on white) is gone. Graded translucent tints with `text.primary`: **17.99 / 18.70 / 19.07:1** on Midnight, **18.22 / 17.44 / 16.97:1** on Daylight. See §4.4 for what the fix did *not* address |
| **N-1 / N-4 / N-5** | **Closed** | Letterbox to `onArt.letterbox`; nine control edges to `border.control`; six dead styles deleted rather than migrated |
| **`<Spinner>` exemption** (`24b021a3`) | **Closed, and the reasoning is right** | The arc is a graphical object at the 3:1 bar, not text. Measured on Daylight: **3.88 / 3.53 / 3.88:1** on canvas / surface / elevated. C's inline comment says 3.54 where I measure 3.53 — immaterial, both clear 3:1 |
| **F-33** switch thumb | **HALF CLOSED — correction** | See below |

### F-33 is not closed. One of the two switches still has it.

Both `thumbColor` sites at `24b021a3`:

| Site | Value | Daylight thumb |
|---|---|---|
| `src/screens/CreateListingScreen.tsx:750` | `palette.onArt.primary` | `#FFFFFF` — correct |
| `app/settings/notifications.tsx:239` | `palette.text.primary` | **`#0B0C0E` — near-black** |

The matrix records "F-33 (switch thumb stays white)". On the notifications screen it does not.

**State it precisely: this is not a contrast failure.** The black thumb measures 5.05:1 on the ON track
and 5.76:1 on the OFF track. It is an **inconsistency** — the same control renders a white thumb on one
screen and a near-black thumb on another, in Daylight only; on Midnight `text.primary` is white and both
agree. One-word fix: `onArt.primary`.

---

## 3 · The four carried-forward findings, re-judged in rendered context

The owner's test for each: is it reachable, what does it communicate, and does another cue already exist.
**Two of the four do not survive the current code.**

### 3.1 · N-2 — `status.warning` as a 1px border → **CLOSED, not a defect**

Nine sites, not the two originally recorded. Measured as a border against the surface behind it:

| | canvas | surface | elevated |
|---|---|---|---|
| Midnight `#FFB020` | 11.48:1 | 10.83:1 | 10.33:1 |
| Daylight `#8A5400` | 6.27:1 | 5.71:1 | 6.27:1 |

Every value clears the 3:1 non-text bar with room to spare, in both appearances. The finding's substance
was that the border "reads bright amber on Midnight and dark brown on Daylight". That is true, and it is
the token **behaving correctly** — an amber that stayed bright on white would fail. There is no defect here.

On the second question, another cue exists at eight of the nine sites: the box's own body text is also
`status.warning` (transfer gate, both countdowns, the confirm prompt, `PlatformInstructions`, `Badge`,
`liveNotice`); `PlatformInstructions` additionally prefixes every line with a ⚠️ glyph; the notifications
banners carry `accessibilityRole="alert"` plus a filled dot or a spinner; `SecurityNoticeBanner` carries
an alert role, a header role, a bold title, its own elevated surface and an explicit
`announceForAccessibility` on mount. The transfer countdowns change the **whole sentence**, not just the
hue, when the window passes.

**One sub-item checked and cleared:** `PlatformInstructions.tsx:191` holds a hardcoded
`rgba(251,191,36,0.10)` tint that cannot flip with the scheme. It is **classified in AM5** with a written
reason (a 10% translucent tint composites over whichever canvas is behind it). Verified in the test, not
assumed — this is not a missed literal.

### 3.2 · N-3 — opacity as "past" → **REAL FAILURE, and not where it was recorded**

The recorded finding said opacity "washes out rather than recedes on white" — implying a Light-only
problem. **That is wrong in both directions.** It fails on Midnight too, and the two sites originally
named are the two that are *fine*.

React Native composites the flattened subtree at the layer's alpha, so any text inside a dimmed container
is dimmed with it. Measured:

| Site | What is dimmed | Midnight | Daylight |
|---|---|---|---|
| `BidCard.tsx:132` (0.55) | **artwork only** — the badge, name, price and action line sit outside | no text affected | no text affected |
| `TicketEventGroup.tsx:141` (0.92) | whole row | primary 17.55 · secondary 8.45 · muted 5.39 — **pass** | primary 16.41 · secondary 6.78 · **muted 4.45 — marginal fail** |
| **`FeedRow.tsx:144` (0.55)** | **whole row, text included** | primary 6.27 pass · **secondary 3.45** · **muted 2.49** | **primary 4.33** · **secondary 2.71** · **muted 2.22** |
| **`SellerListingCard.tsx:159` (0.55)** | **whole card, text and fill** | primary 6.06 pass · **secondary 3.43** · **faint 1.49** | **primary 4.12** · **secondary 2.58** · **faint 1.54** |
| `DiscoveryCard.tsx:161` (0.55) | artwork + the status Badge over it | no body text affected | no body text affected |

**Why this is a failure and not an exempt "inactive control":** both failing rows stay interactive. Verified
in source — `FeedRow` is a `Pressable` with `accessibilityRole="button"` and a live `onPress`;
`SellerListingCard` is a `Tappable` with `accessibilityRole="button"`. A sold listing row still navigates.
WCAG 1.4.3's inactive-component exemption does not apply.

**The sharpest consequence — the redundant cue is the thing being dimmed.** `FeedRow`'s own comment says
"On a sold or ended row the CLAIM lives in the status line below (plus the dimmed treatment)". That status
line — the literal word **Sold** or **Ended** — renders in `s.clock` = `text.secondary`, inside the 0.55
row: **3.45:1 on Midnight, 2.71:1 on Daylight.** The cue that rescues the design from colour-alone is
itself below the floor. `priceDimmed` compounds it, swapping the price to `text.secondary` *inside* the
already-dimmed row.

On `SellerListingCard` the word **Cancelled** renders twice — once in a neutral `Badge` (4.12:1 in
Daylight, also failing) and once at `s.dim` = `text.faint`, which lands at **1.49:1 / 1.54:1**.

**Fix — do not dim text.** Apply opacity to the artwork wrapper only, as `BidCard` already does, and carry
"past" on the text side with a token swap (`primary → secondary`, which is solved in both appearances)
rather than a layer alpha. `BidCard` is the pattern the other two should follow; the fix is structural and
costs no new tokens.

### 3.3 · `text.faint` below 4.5:1 → **REAL FAILURE, symmetric, pre-existing**

Measured: **2.46 / 2.59 / 2.67:1** on Midnight, **2.39 / 2.36 / 2.39:1** on Daylight. This is not a
migration defect and not Light-specific — the token is *designed* to be faint and fails equally in both.
`v2.ts:42` already states the rule: "Anything at `muted` or dimmer may not carry task-critical information."
`faint` is dimmer than `muted`.

22 sites. Most are genuinely incidental — the `›` chevron glyph on settings rows, two "Effective Date"
lines, and nine `placeholderTextColor` values whose fields all carry a separate visible label. Three are not:

| Site | String | Why it matters |
|---|---|---|
| `CreateListingScreen.tsx:1070` `selectPlaceholder` | **Select area or venue · Pick a date · Pick a time · Select platform** | `body` **15px**, the unfilled state of **four required fields**. Verified: `value ? sx.selectValue : sx.selectPlaceholder` — `text.primary` when filled, `text.faint` when not |
| `app/settings/notifications.tsx:192` | **6-digit code** | The **only visible naming** of that input — it has no separate label — and it disappears on the first keystroke |
| `SellerListingCard.tsx:171` `s.dim` | **Cancelled** | A state word, and §3.2 compounds it to 1.49:1 / 1.54:1 |

Secondary: the Create sheet's group headings (`AREAS`, `CLUBS & NIGHTLIFE`, …) at `micro` **10px**, and the
report screen's `0 / 1000` counter, which never changes colour or wording at the limit.

**Fix — move these to `text.muted`** (6.2:1 Midnight, 4.80–5.27:1 Daylight). `faint` keeps the chevron and
the legal date lines.

### 3.4 · The colour-alone set → **two withdrawn, one restated, one real**

| Finding | Verdict |
|---|---|
| **Checkout countdown recolours while the copy stays neutral** | **WITHDRAWN.** Verified at `CheckoutNative.tsx:824-836`: one ternary on `reservationMsLeft === 0` drives **both** the colour and the string. `Held for you · 4:32 left` → `Checking your hold`. Copy and hue change on the same test; there is no state where red carries meaning the words do not. My finding described code that does not exist |
| **Switch state is the track colour alone** | **WITHDRAWN.** The iOS switch's primary cue is the **thumb's position**, which is non-colour and platform-supplied, plus `accessibilityRole="switch"` with `accessibilityState={{checked}}`. Colour is the third channel, not the only one. (The separate F-33 thumb inconsistency above stands on its own) |
| **Input focus is the underline colour alone** | **REAL, but mitigated — and cheap to fix.** `Input.tsx:47-53`: focus changes `border.control → brand.red` and nothing else. `borderBottomWidth` is a constant. The state change measures **1.50:1 on Midnight and 1.14:1 on Daylight** — at 1.14:1 there is essentially no luminance change, only hue. **Another cue does exist:** iOS shows a blinking caret and raises the keyboard. So the field being focused is communicated; what is not communicated is *which* field, when the keyboard is already up and focus moves between fields. **Fix:** `borderBottomWidth` 1 → 2 on focus. A non-colour channel, already the pattern at `receive/[id].tsx` `confirmPromptHighlight`. Five ad-hoc inputs repeat the same pattern and would take the same fix |
| **The three risk tiers rank by hue under one ink** | **RESTATED — the hue grading is inert, and that is fine; the collapse is not.** Measured tier-to-tier fill separation: **1.04 / 1.06 / 1.02:1 on Midnight, 1.04 / 1.07 / 1.03:1 on Daylight.** The three tints are, to the eye, the same colour. That costs nothing, because medium / high / critical carry **different sentences**. What is not fine is below |

### 3.5 · `critical_risk` and `listing_blocked` — **confirmed, still identical on every channel**

Verified at both ends:

- `sellState.ts:240-241` — byte-identical strings: *"You cannot create listings at this time. Contact support."*
- `CreateListingScreen.tsx:861` — a single OR'd condition applies the **same** `sx.riskBannerCritical` to
  both. There is no `riskBannerBlocked` style in the file.
- `CreateListingScreen.tsx:418` — the same native alert, same title *"Listing blocked"*, same body.
- `risk_tier` **is** carried into component state and then **never read by any render path**.

So the two most serious seller states are indistinguishable by copy, by colour, by structure and to a
screen reader. One is an automatic risk score; the other is an admin's deliberate block. A seller cannot
tell which applies to them, and the only stated remedy — "Contact support" — has no link, button or
address in the banner. The support address exists only on the legal and privacy screens, and on the legal
screen it is itself rendered in `text.faint`.

**This one is worth fixing regardless of appearance.** It is the oldest of the findings and the only one
that leaves a user unable to act.

---

## 4 · New finding — a network error is reported to the seller as a fact about their account

Not previously recorded. `CreateListingScreen.tsx:408-411`:

```ts
case 'transient':
  console.warn('[CreateListingScreen] risk check transient error — allowing submit:', result.message);
  setRiskBanner({ reason: 'medium_risk_warning', tier: null });
  return true;
```

When the `can_create_listing` RPC fails transiently — a dropped connection, a timeout — the seller is shown
*"We've noticed some recent issues. Please double-check your listing details."*

That is a claim about their account history, produced by a network failure. The publish is allowed through,
so the banner has no functional purpose; it only misinforms. This is the same class as the states the
standing rules keep apart: **an unknown risk posture is being rendered as a known medium-risk posture.**
`tier: null` records that it is not a real tier, and nothing reads it.

**Fix:** either show nothing on `transient` (the submit proceeds anyway), or a neutral, true line —
"Couldn't check your account status just now." Do not reuse the medium-risk sentence.

---

## 5 · What is and is not established

- **Designed:** all of the above, in both appearances.
- **Implemented:** the migration and five of six fixes, verified by my own scan at `24b021a3`.
- **Tested:** C's suite, 2676/2676 at `24b021a3`. Harness-rendered contrast is real components under each
  palette — it is **not** device evidence.
- **Device-verified:** **nothing.** Build 23 is recorded and not installed.
- Every contrast figure here is **computed from the palette, composited**. It is preliminary evidence about
  rendered combinations, not a substitute for looking at the phone.

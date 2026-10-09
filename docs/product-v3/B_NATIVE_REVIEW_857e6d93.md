# B — independent review of C's P-1 / P-2 capture set at `857e6d93`

Frames: `snatchit-refund/native/857e6d93/`, nine PNGs, 1179×2556, C-operated, capture set
completed at `6d54d10f`. Reviewed from the saved frames; **no simulator was used for this
review**, as the owner directed.

Evidence class: **native simulator**, C-operated, B-measured. C operated the device; the
measurement below is mine and was taken with my own instrument, not C's.

## 1. Frame identity, before any measurement
- All nine files are **distinct** (nine distinct md5s). The frame C reported as overwritten in the
  first pass did not survive into this set as a duplicate.
- Each frame I opened carries the **SANDBOX — TEST MONEY ONLY** banner, so none is the Expo
  dev-client launcher or another app. (My own gate: I captured the launcher three times in an
  earlier window and my stability check passed it.)
- Geometry as expected: 393 × 852 pt at 3×, exactly 3.0 px per pt. The 377 pt content edge is
  x = 1131 px; the right gutter is x ∈ [1131, 1178], 48 px = 16 pt.

## 2. Instrument
Ink = a pixel whose RGB distance from **that frame's own modal background** exceeds T, measured
below the fixed header (y > 440 px), the same band C used. The background is computed per frame,
so the instrument never assumes which appearance it is looking at — the failure mode that made my
earlier Dark numbers worthless (an inverted fixed threshold read the black canvas as ink and
reported a 4.0 pt gap and a 0 px gutter) and that made C's first pass return an identical
101,568 px / 392.7 pt for all nine.

I report **four thresholds**, not one, so the answer can be seen to be threshold-robust rather
than threshold-chosen.

## 3. Discrimination control — run first, on the failing frames
Before measuring the new set I ran the same instrument on the old frames at `9498080a`. If it
cannot reproduce the failures it cannot certify the fixes.

| frame (`9498080a`) | gutter px, T=30 / 45 / 60 / 90 | max ink x | gutter ink spans y |
|---|---|---|---|
| `profile-a3xl-light-ratewrap` = **P-1** | 2,756 / 2,749 / 2,597 / 2,590 | 392.7 pt | 649.0 – 851.7 pt |
| `profile-a3xl-light-trustrows` = **P-2** | 8,576 / 8,484 / 8,315 / 8,283 | 392.7 pt | 215.7 – 723.0 pt |
| `profile-a3xl-light-trusthero` | 144 / 144 / 0 / 0 | 392.7 → 374.0 pt | 184.3 – 185.0 pt |
| `profile-a3xl-dark-ratewrap` | 144 / 144 / 144 / 0 | 392.7 → 374.7 pt | 184.3 – 185.0 pt |

My originally recorded figures were **2,257 px (P-1)** and **8,089 px (P-2)**, both at 392.7 pt.
These were taken with a different instrument, so the counts differ by ~15 %; the max ink x is
identical and the magnitudes agree. This also **identifies which frame was which**, which my own
record did not state: P-1 is the rate wrap, P-2 is the trust rows.

## 4. The 144 px signal is a design element, not clipped content
Every A3XL frame — new and old, both appearances — returns exactly **144 px** of gutter ink in a
band 0.7 pt tall. Resolved per row:

```
y=553px (184.3 pt)  ink cols=1179/1179 (100%)  x 0..1178  gutter=48/48  contiguous=YES
y=554px (184.7 pt)  ink cols=1179/1179 (100%)  x 0..1178  gutter=48/48  contiguous=YES
y=555px (185.0 pt)  ink cols=1179/1179 (100%)  x 0..1178  gutter=48/48  contiguous=YES
```

48 px × 3 px = 144 px. It is the **full-bleed hairline under the `PROFILE` header**, edge to edge
by design, visible in the frames. It is not text and it is not a layout escape. Compare the shape
of real clipped content, P-2 above: 4–49 % column coverage, never contiguous, spanning 507 pt of
height across six rows.

I exclude it by shape, not by raising a threshold until it disappears. The two default-size frames
return 0 px at every threshold because at that size the hairline sits above y = 440 px, inside the
header band both C and I excluded.

## 5. Result — the nine frames at `857e6d93`

| frame | gutter px (hairline excluded) | max ink x | inside 377 pt |
|---|---|---|---|
| `profile-default-light` | 0 | 376.3 pt | yes, 0.7 pt clear |
| `profile-default-dark` | 0 | 376.3 pt | yes, 0.7 pt clear |
| `profile-a3xl-light-rate` | 0 | 374.0 pt | yes |
| `profile-a3xl-light-rows` | 0 | 364.7 pt | yes |
| `profile-a3xl-light-membersince` | 0 | 373.3 pt | yes |
| `profile-a3xl-dark-rate` | 0 | 374.0 pt | yes |
| `profile-a3xl-dark-rows` | 0 | 373.3 pt | yes |
| `profile-a3xl-dark-salesrows` | 0 | 373.0 pt | yes |
| `profile-a3xl-dark-activelistings` | 0 | 364.7 pt | yes |

**Zero content ink in the right gutter in all nine, at every threshold.** Max ink x 364.7 –
376.7 pt, inside the 377 pt content edge in all nine. C's figures (0 px; 364.7 – 376.3 pt) and
mine agree. The only difference is the hairline, which C's single threshold happened to fall on
the far side of in Light and the near side of in Dark; the conclusion is unaffected.

### Verdict
- **P-1 closes at `857e6d93`** — the rate is one line. 2,597 px → 0 px; 392.7 pt → 374.0 pt.
- **P-2 closes at `857e6d93`** — every trust row value is inside the content edge. 8,315 px → 0 px;
  392.7 pt → 364.7–373.3 pt.
- Both appearances, both text sizes, measured. Nothing here is inferred from source.

## 6. What the frames show that the numbers do not — a second, separate defect
Measuring the gutter was the committed task and it passes. Looking at the frames shows something
the gutter measurement cannot catch, because it happens **inside** the content edge.

In `profile-a3xl-light-rate` and `profile-a3xl-dark-rate`, the hero's left column reads:

```
TRANSFE
R
SUCCESS
RATE
100%
```

**"TRANSFER" is broken mid-word.** Not clipped, not in the gutter — every pixel is inside 377 pt,
which is why nine clean gutter numbers sit beside it. The cause is `s.hero`'s fixed two-column
form: `heroRight` is pinned at `maxWidth: 150`, so at A3XL `heroLeft` is left with roughly 190 pt
and a single uppercase, letter-spaced `micro` word exceeds it. The same frames show the right
column clamped to `14` / `sale…` — that is P-3, already classified.

This is present **now**, at `857e6d93`, in both appearances. It is not introduced by the prepared
P-3 change; P-3 makes the right column worse in the same way by unclamping into a 150 pt column.

Against the owner's standard — *complete text alone is insufficient if the layout makes it
difficult to read* — **I judge the word breaking unacceptable in both columns.** Stacking the hero
above the shared `identityStacks(fontScale)` threshold resolves it, because each block then owns
the full content width. It is the same rule the trust rows, the feature, the feed row, the panel
and the fact rows already use; the hero is the one surface in this screen that never consulted it.
This is the **fourth** surface that rule has missed (BidActivity → profile hero blurb → TrustRows →
hero container), which is the argument for the painted-result test rather than another one-off.

**Default size is unaffected and must stay as it is** — `profile-default-light` and
`profile-default-dark` show the two-column hero reading correctly, blurb on one line.

## 7. Scope and limits
- This review covers the nine frames and nothing else. It is **not** whole-app acceptance.
- The **Listing poster clearance check is not repeated** — the earlier default-size recheck was
  reported complete and `857e6d93` touches `app/profile/[id].tsx` only (owner instruction).
- Untested and blocking nothing: authenticated consumer Home, the Edit refusal group, spoken
  VoiceOver.
- Instrument: `scratchpad/gutter.py`, `scratchpad/hairline.py` (method stated in full above so the
  numbers can be reproduced or contradicted without them).

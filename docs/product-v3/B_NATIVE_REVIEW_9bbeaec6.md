# B — review of the W batch at serving tip `9bbeaec6` (code `6b6b8f48`)

All frames C-operated, measured and read by B. Twenty-three frames across five capture sets:
`1ab2c8e2/`, `e6a38aef/`, `1a6ac1c3/`, `2ada44bd/`, `7d957100/`, with `b64e5dd6/` used as the
before-state control. **No simulator was used for this review** and B took neither the device nor
Metro.

## 0. Frame gate, applied to all twenty-three before anything was read
- **Sandbox banner present in every frame** (C's own `cap.sh` test, re-run by B): none is the Expo
  dev-client launcher.
- **Size read off the paint, not off `simctl`** — header hairline at 553 px = A3XL, 417 px =
  default. The scrolled Listing frames have no header in view, so their size rests on C's
  before/after readback and on the typography in the frame.
- **Zero content ink in the right gutter in all twenty-three**, at T=45 and T=90. Max ink x
  **339.3 – 376.7 pt**, inside the 377 pt content edge everywhere. The recurring 144 px is the
  full-bleed header hairline, excluded by shape as in the two previous reviews.

## 1. W-4, Settings header — **PASS at A3XL**; the default-size half is **WITHDRAWN** (see the note at the end)
`SETTINGS` and `APPEARANCE` render **whole, on one line, shrunk to fit** at A3XL, with a plain back
chevron and no chip; at default the same uppercase title, centred. Verified on the hub and on the
Appearance sub-screen, Light and Dark.

**Discrimination control** — the fix is guarded by `identityStacks(fontScale)`, so the A3XL frames
must differ across it and the default frames must not:

```
A3XL settings hub      86,802 differing px   y 23-163 pt   (header band only)
A3XL appearance        78,519 differing px   y 23-163 pt   (header band only)
default settings hub            0            identical file
```

Nothing below the header moved. Source agrees: `SettingsHeader.tsx` adds
`{...(stacked ? { adjustsFontSizeToFit, minimumFontScale } : null)}` to a `Text` that already
carried `numberOfLines={1}`, so **below the threshold the rendered props are unchanged by
construction.**

## 2. S-1 / S-1b, SettingsRow labels — **PASS at `1a6ac1c3`**, both appearances
"Notifications" reads **whole on one line**, slightly smaller than its neighbours; "Edit profile"
breaks on its space at full size; every chevron present. Identical in Light and Dark.

**Discrimination control:** at `e6a38aef` the same label reads `Notificatio / ns` — broken mid-word.
The three attempts are three distinct frames (three distinct md5s), so the progression
`a98389fc → e6a38aef → 1a6ac1c3` is visible and not asserted.

C's own account of why the first two attempts were wrong is correct as far as the frames go: shrink
stops as soon as the text fits the lines allowed, and the broken form already fitted.

## 3. P-5, the tier word — **information loss CLOSED; the cap itself is NOT closed**
- **Paint** (`1ab2c8e2/profile-hero-a3xl-dark`): the blurb reads
  `Trusted seller · 14 sales · 100% transfer success` at full size, beneath the small capped badge.
- **Source**, every branch of `deriveReputation` at `9bbeaec6` — because one fixture showing the
  `trusted` tier is not evidence about the branch I actually filed P-5 against:

| branch | carries the tier word now? |
|---|---|
| elite / top / trusted | **yes** — added |
| `needs_review`, low rate (line 98) | **yes** — `Needs review · P% transfer success`. This was the branch where the signal was carried *only* by the capped badge |
| `needs_review`, lost disputes (line 55) | **no** — still `N lost disputes · P% success`. Unchanged, not regressed: its blurb states the adverse fact, which was my original "partly carried" reading |
| new seller, unrated | unchanged — already carried |

**Still open, as the record says:** the `Badge` 1.3× cap itself (`Badge.tsx:74`) is untouched. The
label still paints at roughly 0.47× the text beside it. P-5's *information* problem is closed; the
*legibility* one is a separate follow-up that has not been adopted.

## 4. W-2 and its correction, fee labels — **PASS at `2ada44bd`**
`IF YOU BID THE MINIMUM` / `Tickets $95.00` / **`Service fee (10%)   $9.50`**. The rate is restored
and describes arithmetic in the same frame: 9.50 is exactly 10 % of 95.00.

**Discrimination control:** the same row at `1ab2c8e2` reads plain `Service fee   $9.50`. Same
amount, label only — which is what a copy-only change should look like.

I accept C's reasoning for why the rate returns here and stays absent at checkout: this row's amount
is computed in this file at `BUYER_FEE_RATE`, while checkout's comes from the order's own breakdown
and the venue primary rail carries its own `buyer_fee`. Deriving the label from the constant rather
than typing it is the right call — two literals would be free to drift.

## 5. W-2b, the sold note — **PASS at `7d957100/listing-sold-default-light-Coperated.png`**
`SOLD FOR $132.00 total` unchanged, and beneath it **"Price includes the service fee."** — the rate
is gone. Option A as decided.

**The frame reference is corrected.** The review list pointed at `24393d0b/`, which **does not exist
on disk**; the frame is in `native/7d957100/`. C and E verified the path and the owner directed the
correction; B confirms the directory listing and the frame's content.

## 6. NOT passed, and not to be marked passed
| Item | State |
|---|---|
| **W-5, Edit platform picker** | **untested.** The kept frame is `edit-picker-default-light-BLOCKED`; reaching the picker needs a session and repeat sign-in is **owner-waived**. Parity is test-pinned only |
| **W-6, payout line** | **source-pinned, not visually verified.** The sentence lives in the `connected` branch behind a server probe with no fixture seam. The kept frame is `not_connected` and proves only that that state is undisturbed |
| **Spoken VoiceOver** | optional per the owner, not a release blocker. The exposed label is verified in source only; that is not a spoken result |

## 7. An evidence gap in the default-size claims, recorded because a clean zero can read as proof
The default-size frames in `1ab2c8e2/` are **byte-identical copies** of the `b64e5dd6/` frames —
md5 matches for `settings-hub-default-{light,dark}`, `appearance-default-light` and
`listing-breakdown-default-light`. **C declares this** in its capture log, so nothing is concealed.

But the consequence matters: C's claim is that *a re-shoot after the fix* differed from `b64e5dd6`
by zero pixels below y=440, and **the re-shot frame was not kept.** So the claim cannot be verified
from the committed evidence, and the same applies to the `e6a38aef` and `1a6ac1c3` default claims.

**I first "re-ran" that diff and got zero across the whole frame, clock included.** That was not a
confirmation — it was a file compared with itself. I am recording it rather than reporting the zero,
because this is precisely the shape of evidence that reads as proof and is not.

What makes the claim sound is **structural, not photographic**: the W-4 fix is guarded by
`identityStacks`, so the default branch cannot change. That is a source argument and it is weaker
than paint. **To close it properly, keep the re-shot default frame** — one extra file per set.

## 8. Scope
This covers the five owed items at `9bbeaec6` and nothing else. It is **not** whole-app acceptance.
Signed-in checks remain owner-waived and are not passed. Authenticated consumer Home and the Edit
refusal group remain untested.

---

**Count correction (B, same day).** This review first said *twenty-four* frames. The six capture
sets hold **23**: `1ab2c8e2/` 14, `e6a38aef/` 4, `1a6ac1c3/` 2, `2ada44bd/` 2, `7d957100/` 1, with
`b64e5dd6/` used only as the before-state control. E's independent count of 23 is right and mine
was wrong. Every measurement above was taken over those 23 frames; only the total was mistyped, and
no verdict depends on it.

---

**W-4 default size: withdrawn from "pass" (B, after the owner's ruling).** §1 originally recorded
W-4 as passing at *both* sizes. The **A3XL half stands** — 86,802 and 78,519 differing px confined
to the header band, with nothing below it moving.

The **default-size half is withdrawn**, for the reason already set out in §7 of this document: the
`1ab2c8e2/` default frames are byte-identical copies of the `b64e5dd6/` ones, and the re-shot frame
that the zero-difference claim rests on was not kept. The owner has ruled that no such comparison
may be claimed from copied baselines or an unretained frame. Fresh re-shot frames have been
requested from C; until they exist the line is **open**, not passed.

I expect the claim to hold, because `SettingsHeader` adds its shrink props only above
`identityStacks(fontScale)` and the default branch is therefore unchanged by construction. That is a
source argument, and §2 of the handoff is exactly where source arguments belong.

Current classification: `B_REVIEW_HANDOFF.md`.

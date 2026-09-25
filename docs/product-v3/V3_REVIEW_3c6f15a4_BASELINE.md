# B — baseline review at `3c6f15a4`

**Candidate** `3c6f15a4cea06677421d7b98acb387bb7e8f594b`, resolved with `git rev-parse` and
confirmed as the `v3/midnight-app` tip at the time of review. I will re-review at the successor C
names after the listing, reservation-feedback and native-build fixes.

**Shared fixtures are now C's `assets/qa-posters/`.** My separate `docs/product-v3/fixtures/` is
**withdrawn and deleted** so one set exists. Two additions are proposed below rather than kept as a
rival set.

**Superseded:** my iPhone 17 Pro / iOS 26.2 proposal. It is moot regardless — **iOS 26.2 is no
longer installed on this machine.**

---

## 1. The device and runtime, recorded as instructed

| | actual |
|---|---|
| device name | **SN V3 393x852** |
| device type | `com.apple.CoreSimulator.SimDeviceType.**iPhone-16**` |
| UDID | `52282259-961E-4A1A-B32B-CEFA858CFF48` |
| runtime | **iOS 26.5 (26.5 — 23F77)**, the only runtime installed |
| state | Booted |
| verified logical size | **393 × 852** — a `simctl io … screenshot` measures **1179 × 2556**, exactly @3× |

There is no simulator literally named "iPhone 16"; the owner's "existing iPhone 16" is this device,
which **is** an iPhone 16 by type and geometry. Recorded rather than assumed.

**Native review has not started, because the candidate is not on the device.**
`xcrun simctl listapps` lists no Snatch It bundle, and there is no built `.app` under DerivedData.
This is consistent with the native-build fixes still being in flight. Nothing native is claimed
here. When a build exists I capture through `xcrun simctl io <udid> screenshot`, which works in
this session — the simulator MCP tools do not, and I will not pretend otherwise.

---

## 2. F-91-6 does NOT close — and the cause is larger than the glyph

The Filters control still draws **`≡` (U+2261 IDENTICAL TO)** — `src/components/ui/IconButton.tsx`,
`GLYPH.filter`. Three equal bars: a menu mark, as measured at `91062ab1`. **The correction stays
open.**

But the interesting part is why swapping the character will not fix it. `IconButton` draws all five
marks as **text characters**, on the stated rationale:

> *"Typographic, not emoji: these inherit the brand face and colour."*

**That is false for four of the five.** I parsed the `cmap` of the actual shipped font files:

| codepoint | mark | Inter 400 | Inter 600 | Oswald 700 |
|---|---|---|---|---|
| U+2039 `‹` | back | **present** | **present** | **present** |
| U+2261 `≡` | **filter** | missing | missing | missing |
| U+2315 `⌕` | **search** | missing | missing | missing |
| U+2715 `✕` | **close** | missing | missing | missing |
| U+22EF `⋯` | **more** | missing | missing | missing |

(`node_modules/@expo-google-fonts/inter/{400Regular,600SemiBold}`, `…/oswald/700Bold`; Inter
carries 2 849 codepoints, Oswald 850.)

So four of the five icons **cannot** inherit the brand face. They are drawn by whatever face iOS
substitutes, which means their weight, width, optical size and vertical alignment are outside the
design system — and differ by OS version. That is also the likeliest reason the Filters mark reads
as a plain hamburger: `≡` is a mathematics sign, and its shape is the fallback's, not ours.

**This is the same class of bug C just fixed at `3c6f15a4`** ("the flyer printed a tofu box"),
one layer down, in shipping UI rather than in a fixture.

**Recommended fix — draw the marks, do not spell them.** A filter mark is three `View`s at 100 % /
66 % / 33 % width, centred, inheriting `color` — no font dependency, the correct tapering shape,
and it settles F-91-6 as a side effect. Close, more and search want the same treatment. Keep the
44 × 44 target, the quiet weight, the count badge and the accessible names, all of which are already
right.

**Native check still owed** on whether these four currently tofu or fall back gracefully on iOS
26.5. Fallback is the usual CoreText behaviour and I expect no tofu — but I have not seen it, so I
am not asserting it.

---

## 3. The footer regression I predicted is present in the candidate — reservation feedback is gone

`12be25d6` implements the owner's Option B **in the resolver**, which is the approach I warned
against, and its only change to `ListingDetailScreen.tsx` was **the comment**. Verified at
`3c6f15a4`:

* `:1276` — `primaryBusy = (primary.kind === 'buy_now' || primary.kind === 'continue_reservation') && reserving`.
  In `auction_and_buy_now` the primary is now `place_bid`, so **`primaryBusy` is always false**.
* `:1458`, `:1461` — `pendingLabel="Reserving…"` and `loading={primaryBusy}` still sit on the
  **primary slot**, i.e. on the bid button, where they can never fire.
* `:1464`–`:1470` — the secondary `BarAction`, now **Buy Now**, has **no `loading` and no
  `pendingLabel`**.

Buy Now is the only action that sets `reserving`. So in this candidate, **pressing Buy Now starts
the reserve call and nothing on screen says so.** Both pills dim, because the resolver sets
`disabled: reserving` on both, and neither explains why. CFT-203 — "visible while the reserve call
is in flight" — is dropped in exactly the one mode the ruling touched.

No test caught it because none asserts the secondary slot's busy state.

**The fix is the one already sent:** key busy state on the action **kind**, not the slot —
`loading` ⇐ `(kind === 'buy_now' || kind === 'continue_reservation') && reserving`, and
`pendingLabel="Reserving…"` on those same kinds wherever they are drawn. Then order and fill are
free to change and nothing behavioural moves with them.

**Evidence class: source, verified at the commit.** Not rendered — the harness has no `reserving`
seam, and producing one for real would mean a reserve call, which is not authorised. A fixture that
sets `reserving` would make this visible; it is worth C adding one, since the state is currently
unreviewable by anyone.

---

## 4. The shared fixture set — one gap against the owner's own list

`assets/qa-posters/` at `3c6f15a4`:

| file | ratio | covers |
|---|---|---|
| `flyer-dense-4x5.png` | 0.800 | text-heavy artwork ✅ |
| `markers-4x5.png` | 0.800 | geometry at the target ratio ✅ |
| `markers-16x9.png` · `markers-1x1.png` · `markers-9x16.png` | 1.778 · 1.000 · 0.562 | non-4:5 originals, both directions ✅ |
| `photo-3x2.png` | 1.500 | photographic content — **partially** |
| *(no file)* | — | missing artwork ✅ |

**Two gaps.**

1. **There is no photographic fixture at 4:5** — the common case, and the only one that tests a
   subject *inside* the target frame rather than the letterbox path.
2. **`photo-3x2.png` has no identifiable subject.** It is abstract circles on a gradient, captioned
   "SYNTHETIC PHOTO FIXTURE". The owner's criterion is explicit: synthetic imagery can test subject
   framing *"when it has an identifiable subject"*. This one cannot; it tests geometry only.

**Proposed additions**, in `fixtures-proposed/`, for C to move into `assets/qa-posters/` so the set
stays single:

* `photo-subject-4x5.png` (1200 × 1500)
* `photo-subject-16x9.png` (1600 × 900)

**Provenance, stated on the image itself and here: SYNTHETIC, generated by B.** Not a photograph.
Each carries a recognisable figure — head, shoulders, arm, microphone — deliberately placed at
**36 % across, 30 % down**, high and left of centre, so any centre crop visibly decapitates it. A
ring and the word SUBJECT mark the head, so "is the subject intact, and where did it land" is
measurable instead of impressionistic, and a crowd silhouette runs along the bottom edge as a
second, edge-anchored subject.

They test subject framing and geometry. They do **not** substitute for a real photograph's tonal
range, noise or focal ambiguity; if that matters before acceptance it needs a real file.

---

## 5. What is open

| item | state |
|---|---|
| Home 4:5, Listing, footer — **native**, both appearances, Dynamic Type, scrolling, safe areas | **blocked**: no build on the device |
| Reservation feedback | **defect found in source** (§3); rendering it needs a `reserving` fixture |
| F-91-6 Filters glyph | **open**, with a larger cause found (§2) |
| Photographic 4:5 with a subject | **proposed** (§4), awaiting C moving it into the shared set |

---

## 6. Addendum — wording correction, and the optimised fixtures

**Correction (owner, 2026-09-25).** §3 said the footer defect "has shipped". It has not: it is
**present in the candidate `3c6f15a4`**. Nothing is distributed, no build exists on the device, and
"shipped" claims a reach the evidence does not support. The section above is corrected; the commit
message of `4882cd6a` carries the original word and is left as written, with this note as the
correction of record.

**The proposed fixtures are optimised and within the existing budget.** They are **synthetic
subject-framing fixtures, not photographs** — the owner's description, and the accurate one.

| file | before | after | colours | dimensions |
|---|---|---|---|---|
| `photo-subject-4x5.png` | 567,510 | **63,311** (11.2 %) | 32 | 1200 × 1500, ratio 0.800 |
| `photo-subject-16x9.png` | 444,421 | **62,448** (14.1 %) | 64 | 1600 × 900, ratio 1.778 |

| | bytes |
|---|---|
| proposed additions | **125,759** |
| existing `assets/qa-posters/` (6 files) | 176,302 |
| **combined** | **302,061** |
| budget, `tests/v3-bundled-fixtures.test.ts` BF4 | 409,600 |
| **headroom remaining** | **107,539** |

**The budget is not raised.** Median-cut quantisation with dithering off, then `optimize=True`.

**Every marker verified on the written files, not assumed:** the subject's head at 36 % / 30 % is
still dark ink, the green ring is intact (4 310 and 3 932 sampled pixels), all four edge borders
are present at mid-edge, and the crowd silhouette survives at the bottom edge.

**One result worth passing to C:** at 24 and 32 colours the **16:9** file lost the marker colour
entirely — median cut dropped it from the palette, so the ring and all four borders vanished while
the image still looked plausible. It passes at 48 and is written at 64 for margin. **If these are
re-encoded, re-run the marker check rather than trusting the file's appearance** — a fixture whose
markers are silently gone is worse than no fixture, because it reports a pass.

Files: `fixtures-proposed/`. They are C's to move into `assets/qa-posters/`, with `DEV_POSTER_NAMES`
and BF4's shape list updated, so one set exists.

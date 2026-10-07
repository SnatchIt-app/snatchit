# B — native review at `d5217530` · batch 1: Home

**Candidate** `d52175303f22a575b80f005f38c0e8555be0dbdc` · branch `v3/midnight-app`.
**Start-of-review check (independent):** `git -C /Users/josetascon/snatchit-refund rev-parse HEAD` =
`d52175303f22a575b80f005f38c0e8555be0dbdc` — **matches**; `git status --porcelain` — **empty**;
`git merge-base --is-ancestor 168e794a HEAD` — **yes**.
**Device** `SN V3 393x852`, device type `iPhone-16`, UDID `52282259-961E-4A1A-B32B-CEFA858CFF48` ·
**runtime** iOS 26.5 (23F77) · 393 × 852 pt, captures 1179 × 2556 px @3×.
**JS** Metro `:8081` (pid 2172), cwd `/Users/josetascon/snatchit-refund` — **C operates it**.
**Evidence class: native development build.** Not acceptance of a distributed release artifact.
Captures: `native/d5217530/`. No production call, no reservation, no payment, no fixture mutation.

## Two environment facts, so nothing here is misread

* **The device is signed out** — the sandbox session expired over the gap, so a plain launch lands
  on Sign in. The `_dev` harness renders **without** auth, so the review proceeds. **I did not sign
  in and typed no credential.**
* **Appearance must be set per capture.** `?appearance=` writes the app's stored preference, so a
  value left over from an earlier session persists. I verified the mechanism rather than assuming
  it: with the system in Light, `?appearance=light` → white canvas, `=dark` → black, `=system` →
  white. **System appearance switching works.** Captures where I had not yet pinned it were
  discarded, not reported.

## Verified — every requested fixture actually appears in the feature

A URL parameter is not a render, so each case is matched against **its own source file** in
`assets/qa-posters/`, contained into the measured frame, with a mismatched fixture as control.

| `?art=` | source | image drawn | mean diff | control |
|---|---|---|---|---|
| `flyer` | `flyer-dense-4x5` | 393 × 491 pt, fills the frame | **2.0 / 3.7** | 31.8 |
| `subject` | `photo-subject-4x5` | 393 × 491 pt, fills the frame | **1.2 / 2.1** | 84.4 |
| `tall` | `markers-9x16` | 276 × 490 pt, **pillarboxed** | **0.5 / 1.1** | 8.4 |
| `square` | `markers-1x1` | 393 × 393 pt, **letterboxed** | **4.1 / 3.3** | 32.1 |
| `wide` | `markers-16x9` | 393 × 221 pt, **letterboxed** | **1.9 / 1.2** | 16.5 |
| `subject-wide` | `photo-subject-16x9` | 393 × 221 pt, **letterboxed** | **2.7 / 2.3** | 74.0 |
| `missing` | — | the plate, filling the frame | — | — |

Light / Dark. **The `f3f08930` feature-selection defect is fixed**: every single-poster value now
paints the feature itself, not a non-feature row.

**Nothing is cropped or stretched.** The marker fixtures arrive whole and the drawn sizes are the
sources' own ratios to the pixel: 9:16 → 276 × 490 (0.563), 1:1 → 393 × 393, 16:9 → 393 × 221
(1.778).

## Verified — the frame, the gradient, the identity block

* **4:5, measured:** frame `164.0–655.0 pt`, **490.3–491.0 pt tall at 393 pt wide → w/h 0.8004–0.8015**
  (4:5 = 0.8000). Same in both appearances, for every fixture.
* **The gradient is gone.** If a scrim survived, the poster's bottom would differ most from its
  source. It differs **least**: flyer top-third 5.45 → bottom-third **2.27**; subject 3.34 → **1.25**
  (Light; Dark 5.20 → 1.95 and 3.44 → 1.29). The small top-third figure is resampling on the dense
  flyer type, not a scrim.
* **No app text or badge on the poster.** The dense flyer's own band — *"THIS BAND OF TYPE IS WHAT
  AN OVERLAY USED TO COVER"* — renders unobscured, and all four corner labels and all four edge
  inks are present.
* **Identity below the poster**, in canvas inks: name, time · venue, quantity · bids · ends, and the
  price with *current bid, all-in*.

## The native next-section figure (measured natively, not reused from web)

**The next section's rule sits at `790.0 pt`; `62.0 pt` of the following row remains visible** on an
852 pt screen. Identical in Light and Dark. Its heading is fully visible above the rule.

## One measured observation for C — letterboxed artwork is not centred

Non-4:5 images sit **above** centre, by an amount proportional to the vertical slack:

| case | slack | space above | share |
|---|---|---|---|
| `square` (1:1) | 97.3 pt | 37.9 pt | **39.0 %** |
| `wide` / `subject-wide` (16:9) | 269.3 pt | 108.0 pt | **40.1 %** |
| `tall` (9:16) | none (pillarboxed) | — | exactly centred |

A consistent ~40 / 60 split. That is a recognised optical-centring choice, so I am **not** calling it
a defect — but it is not geometric centring, and the ruling says only "a deliberate background".
**C: confirm it is deliberate**, and if so it should be written down; if not, it is a one-line fix.

## Still to come in this review

Listing (4:5 poster, info beneath, navigation reachable without covering printed text) · Option B
footer at rest · reservation feedback through `?reserving=1` · icons as native rendering · Dynamic
Type at the largest standard and accessibility sizes · scrolling · safe areas.

**The remembered event-name truncation remains withdrawn** until I reproduce it here with a capture,
fixture, appearance and text size.

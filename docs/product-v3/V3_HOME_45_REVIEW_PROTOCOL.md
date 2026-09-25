# Home feature at 4:5 — the shared fixtures, and how B will review it

**Owner ruling, 2026-09-25.** The Home feature shows the **complete event poster in a 4:5 frame**.
Other image shapes are **fitted inside it without cropping or stretching**, on a deliberate
background. The app's event name, date, venue, price and listing details move to a **separate area
beneath the poster**. **No app text or badge overlaps the poster's printed content.** The gradient
that supported the old overlay is **removed**. The **full 4:5** version is rendered first — the
~45 % screen-height cap I proposed is **not** approved and must not be introduced.

The approved Home header and filter controls are unchanged by this.

**C implements · B reviews native renders · E records both at the same commit.**

---

## 1. The shared fixtures

Published at `fixtures/`, sheet at `comparisons/home_45_fixtures.png`. **C and B use these same
files**, so a disagreement is about the implementation and never about the input.

| file | shape | what it is for |
|---|---|---|
| `fx-flyer-dense-4x5.jpg` | 4:5 | **The text-heavy flyer.** Text runs to all four edges — headline, a five-line set time list, and a bottom block with date, venue, street address, ticket URL and promoter handle. If any app element overlaps printed content, this finds it. |
| `fx-photo-4x5.jpg` | 4:5 | **The photograph** at the target ratio: tonal range, bokeh, a dark crowd silhouette along the bottom edge, no text. |
| `fx-photo-3x2.jpg` | 3:2 landscape | The **wider-than-4:5** case: needs the deliberate background above and below. |
| `fx-photo-9x16.jpg` | 9:16 | The **taller-than-4:5** case: needs it left and right. A story-format upload is likelier than a 3:2 one. |
| `fx-markers-4x5.jpg` | 4:5 | **The geometry fixture.** Labelled corner blocks (TL/TR/BL/BR), a 1 px border, ruler ticks every 10 % on all four edges, and a **perfect circle** at centre. Any crop loses a corner or a tick; any stretch turns the circle into an ellipse. It supplements the three real cases — it never replaces them. |
| *(none)* | — | **Missing artwork**: the SN plate, in the same 4:5 frame. |

**Stated limit:** the photographs are **synthetic**. They establish geometry, background and
overlap. They do **not** establish how a real photograph's subject survives, because a generated
image has no subject worth keeping. A real photographic upload stays an untested case; if one
matters before acceptance, it needs a real file from the owner or C.

---

## 2. What B will check, per fixture, Light and Dark

**Geometry**
1. The frame is 4:5. Measured, not assumed: the painted box's width ÷ height = 0.800 ± 0.002.
2. For every 4:5 fixture, **all four corner markers and all forty ruler ticks are present**, and
   the circle is a circle — measured as width ÷ height of its bounding box within 1 %.
3. For the 3:2 and 9:16 fixtures the **whole image** is present, undistorted (the crowd silhouette
   keeps its proportions), with the background filling the remainder — and the image is not
   upscaled past its own pixels.

**Overlap — the ruling's core**
4. No app text or badge intersects the poster's rectangle. Checked by measured rects, not by eye:
   the bounding box of every app element in the feature against the bounding box of the image.
5. The **gradient is gone**. Checked by sampling the poster's own pixels near the bottom edge
   against the source file's pixels at the same relative position: a surviving scrim shows as a
   luminance gap that grows toward the edge.

**The text area beneath**
6. Event name, date, venue, price and listing details are all present, below the poster, in solid
   type on the canvas.
7. Price still reads as all-in, quantity wording is preserved, and nothing claims a state it has
   not got.

**Layout cost — the number the owner asked for**
8. **How much of the next section remains visible**, measured on the real render.

   My arithmetic prediction at 393 pt, to be replaced by measurement: a 4:5 full-bleed feature is
   **491 pt**. With a 59 pt top inset, the measured 64 pt header, and a ~44 pt section heading, the
   poster runs roughly **167 → 658 pt**. The new text block beneath it lands the *next* section
   heading somewhere around **760–780 pt**, while the dock occupies the last ~100 pt. So I expect
   **little or none of the next section to remain visible** on a 393 × 852 screen. That is the
   trade the full-4:5 ruling accepts; my job is to report the measured figure, not to re-litigate
   the cap.

**Both appearances**
9. Every check above in Light and in Dark, including the deliberate background in each.

---

## 3. Evidence class — this one is native

The owner asked for **native renders**. Web is development evidence and does not establish
Dynamic Type, safe areas or native image scaling, so this review runs on the **simulator**:
**iPhone 17 Pro, iOS 26.2** (Xcode 26.6 / 17F113 verified installed and usable, first-launch
complete, no owner action needed). The simulator UDID is recorded beside every capture, with the
commit.

C owns simulator setup and running the candidate; B owns the independent comparison against the
approved references. **This review cannot start until a runnable candidate exists at an identified
commit** — I will confirm that commit with C rather than assume the branch tip.

I will also capture the same set on the web harness, because it is cheap and it catches geometry
and overlap early — but it will be labelled as web, and it settles nothing the owner asked for.

---

## 4. What B is not doing

Not implementing it: this is C's, in the app's own media and Home code — not a harness patch.
Not reintroducing the height cap. Not touching the approved header and filter controls. Not
changing the avatar path, which this direction does not reach.

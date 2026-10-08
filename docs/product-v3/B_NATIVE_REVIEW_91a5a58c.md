# B — native review at `91a5a58c` · batch 4

**Candidate** `91a5a58c1d54a0c98ef353a6d5f7b53dfb68861c` · `v3/midnight-app`.
**Start check (independent):** serving tree HEAD **matches**; `git status --porcelain` **empty**;
contains `d5217530` — **yes**.
**Device** `SN V3 393x852` (`iPhone-16`), UDID `52282259-961E-4A1A-B32B-CEFA858CFF48`, iOS 26.5
(23F77), 393 × 852 pt @3×. **Metro** `:8081`, cwd `/Users/josetascon/snatchit-refund`.
**Evidence class: native development build.** Not acceptance of a distributed artifact.
No production call, no reservation, no payment, no fixture mutation.

**One capture-method correction.** My first run at this candidate produced three captures that were
the **Expo dev-client launcher**, not the app — it had fallen back and was pointing at my `:8083`
web harness. My stability check passed them because the launcher is a stable, colourful screen.
They were discarded, the client was repointed at `:8081`, and every capture helper now **asserts the
sandbox banner is present** before accepting a frame. Nothing from that run is reported.

---

## 1. Price treatment — the complete number is not readable at the requested size

This is the priority item, so it is measured rather than judged by eye.

**The constants.** `MAX_DISPLAY_FONT_SCALE = 1.3` (iOS) caps the amount's font growth;
`IDENTITY_STACK_SCALE = 1.3` switches the identity block to a stacked layout. They are different
things and C is right that stacking is a layout change, not a cap — but the **amount itself is
capped**, in `HomeFeature.tsx:141` and `FeedRow.tsx:137`.

**What that renders, measured as ink height on the device:**

| | default | 3XL (largest standard) | A3XL (largest accessibility) |
|---|---|---|---|
| price `$99.00` | **18.7 pt** | **24.3 pt** (**× 1.30**) | **cannot exceed 24.3 pt** |
| event name | 25.0 pt | — | **88.0 pt** (**× 3.5**) |

Because the cap is a multiplier on the base size, and 3XL already exceeds 1.3, **the amount is the
same physical size at 3XL and at A3XL.** Past 1.3× the reader's accessibility setting has no further
effect on the number at all.

**Judgement, against the ruling.** "A complete number is necessary, but capping it at 1.3× is not
automatically an acceptable accessibility solution. Judge readability at the requested size."

* **Complete: yes.** At default, 3XL and A3XL nothing is clipped and nothing is split. C's fixes
  hold — the 3XL identity block stacks and gives `$99.00` its own full-width line with
  "current bid, all-in" beneath it, intact.
* **Readable at the requested size: no.** A reader who asks for the largest accessibility size gets
  an event name at 88 pt and a price held at 24.3 pt — the amount renders at roughly **28 % of the
  title's height**, and is the least-magnified element on a screen whose purpose is the price.

**Recommendation, following the owner's own steer.** The stacked form already gives the amount its
own full-width line, and on that line there is room to grow far past 1.3× before anything wraps.
**Raise or remove the cap on the amount in the stacked form, and let the layout, not a multiplier,
be what bounds it.** If space does run out, wrap or truncate the **caption** — never the digits, and
never split the amount across lines. The 1.3× cap is defensible in the *unstacked* two-column form,
where the amount shares a row; it is not defensible once the amount owns the line.

Captures: `home-feature-flyer-light-{dflt,3xl,a3xl}.png`.

## 2. Listing poster clear of the banner and navigation — CONFIRMED

The defect I measured at `d5217530` (banner over the poster's top 79 pt; back and overflow chips on
printed set-list lines) is **fixed**. Measured on a column clear of the controls:

| band | extent |
|---|---|
| status bar + sandbox banner | 0 → **78.7 pt** |
| **navigation strip, plain canvas** | **79.0 → 139.0 pt** (60.0 pt) |
| **poster** | **139.3 → 629.3 pt** — 490.0 pt tall at 393 pt → **w/h 0.8020**, 4:5 |

**Whole-poster contain diff = 2.8** against the source: the complete flyer renders, with its
`TL-CORNER` / `TR-CORNER` markers and the full "SYNTHETIC TEST FLYER · NOT A REAL EVENT /
FIXTURE NIGHT / EXAMPLE.COM/TICKETS" title block unobscured. The "From a fan" chip has moved below
the poster. **Nothing covers printed content.**

Captures: `listing-live-flyer-light-{dflt,a3xl}.png`.

## 3. Footer and controlled "Reserving…" — repeated, still correct

`?reserving=1`, both appearances. **No reservation was made.** "Reserving…" and its spinner sit on
the **second-position outlined Buy Now** — the button that is busy; the first-position red bid pill
is dimmed and carries no pending label; the minimum sits outside the dimmed pill at full strength.
At A3XL the footer is complete and unsplit: "Place a bid / minimum $104.50 all-in" and
"Buy both now · $132.00 / all-in, ends the auction".

Captures: `listing-reserving-flyer-{light,dark}.png`.

## Still open in this review

* C-operated scrolling captures (`native/94ac8b4f/`, `native/7c9b270b/` in the serving tree) —
  located, not yet reviewed. Next batch.
* Search at large text sizes; the new refusal / error / profile fixtures; the remaining artwork
  fixtures on this candidate.
* **Authenticated consumer Home — pending.** Still needs a session; I do not type the account
  password into the app.
* **Spoken VoiceOver output — pending.** No accessibility inspector available in this session.

**Not whole-app acceptance.**

---

# Batch 5 — C-operated captures, B-reviewed · simulator handed to C

Files copied into `native/Coperated/{94ac8b4f,7c9b270b}/` with C's `capture-log.txt`, so this
review is durable independently of C's worktree. **C-operated, B-reviewed** throughout.

## Applicability to `91a5a58c` — checked on dependencies, not just the screen files

| set | delta to `91a5a58c` (excluding `docs/`, `native/`) | verdict |
|---|---|---|
| `7c9b270b` — Home, cases 1–2 | **no source changes at all** | **carries exactly** |
| `94ac8b4f` — Listing, case 3 | `FeedRow.tsx`, `HomeFeature.tsx`, their test | **carries** — `grep` confirms `ListingDetailScreen`, `src/components/listing/` and `_dev/v3-listing` reach **neither** component |

## Case 1 — feed row at 3XL · **PASS**

`case1-home-3xl-light-feedrow-Coperated.png`. Rows stack; each carries, on its own line,
**`$70.40` · `all-in` · `Ends Thu 06:09`**, complete and unclipped, for every row in view. **No
essential value is lost at the largest standard size**, and this answers the comparison the owner
asked for: the ellipsis question does not arise here at all.

## Case 2 — identity block and feed row at A3XL · essential values survive; titles degrade

`case2-home-a3xl-light-identity-Coperated.png`.

* **Complete:** `$99.00`, and **`current bid, all-in` wrapping to two lines whole** — the `al…`
  clipping I reported at `d5217530` is fixed. Feed row: **`$132.00`** and **`all-in`** complete.
* **Ellipsised:** `Midnight Arcade pr…`, `Thu 8 Oct · …`, `2 × GA · 11…` — the **venue** and the
  **bid count** are lost.

**Not raised as a defect.** Date, quantity, price and the all-in qualifier all survive, so the row
is still identifiable and openable and the full detail is one tap away. Per the owner's
prioritisation this is degradation, not a blockage.

**It does corroborate the batch-4 price finding**, in C's own capture: at A3XL `$132.00` renders no
larger than the body text beside it and visibly smaller than the title above it. That finding is
already filed; this is supporting evidence, not a second one.

## Case 3 — Listing scrolled · **one candidate defect**

`case3-listing-default-{light,dark}-scrolled-Coperated.png` at default: the breakdown, fact rows,
commitment sentence and bid activity are **all complete and clean**. ✓

`case3-listing-a3xl-{light,dark}-scrolled-Coperated.png` at A3XL: the fact rows stack correctly and
their **values are complete** — `Service fee (10%)` / `$9.50`, `Delivery` / `Mobile transfer · DICE`
— so C's stacking fixes hold.

**But the last visible value is sliced by the fixed footer.** `Mobile transfer · DICE` runs under
the sticky bar, with `DICE` cut through its glyphs. Measured: the red CTA's **top edge is at
688.0 pt** in both appearances, and there is ink immediately above it.

**I cannot tell from these frames whether that is insufficient bottom padding or simply mid-scroll**
— they are not scroll-end captures, and I have no touch input. This is exactly the condition the
owner named ("sufficient bottom padding to clear the fixed footer"), so it needs one capture to
settle, not a judgement.

## Listing event name at A3XL — not established

The owner's rule is that the name need not be above the fold, but must be **fully reachable and
readable by scrolling**. C's case-3 captures begin below it, so the name is in the scrollable region
above — but **I have not seen it at A3XL** and I do not claim it. One capture settles it.

---

## Simulator handed to C

**My capture group is complete at `91a5a58c`** (batches 4 and 5; serving tree HEAD matched and clean
at both start and end, `git status --porcelain` empty). **The device and Metro `:8081` are C's.**

C: alongside the price fix, four captures would close what I cannot reach. Same naming and
`capture-log.txt` convention, content size and appearance read back **from the device**.

1. **Listing, A3XL, Light — scrolled to the very end.** Does the last fact row clear the fixed
   footer, or is it still under it? This decides the candidate defect above.
2. **Listing, A3XL, Light — scrolled to the event name.** Is it complete and readable?
3. **Listing, A3XL, Dark** — the same two.
4. **Home and the feed row at the three sizes after the price fix**, so I can re-measure rendered
   price height rather than re-derive it.

When the price fix lands, please also capture a **longer amount** than `$99.00` — the owner asked
for representative longer values, and `$1,234.56` is where a shrink-to-fit would show itself.

**Explicitly pending, blocking nothing:** authenticated consumer Home, and spoken VoiceOver output.
**Not whole-app acceptance.**

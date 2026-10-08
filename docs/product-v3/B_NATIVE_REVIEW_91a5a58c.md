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

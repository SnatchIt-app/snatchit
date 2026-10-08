# Snatch It dashboard design guidelines

One design language for the **venue dashboard** (`venue/`) and the **admin operating
console** (`admin/`). Written from measured sources, not taste. Where a rule came from a
measurement, the measurement is named so a later reader can re-take it.

Owner: F (layout, navigation, visual design, plain-language presentation).
A owns payment, refund, payout and authoritative-state wording. D reviews operational
behaviour and permissions. Nothing here overrides them.

---

## 1. References, and exactly what was taken from each

| Reference | Inspected? | What was taken |
|---|---|---|
| **snatchitapp.com** white `section.chapter` blocks | **Yes** — computed styles, 2026-10-06 | The palette, the hairline, the eyebrow, the primary button, "no boxed cards" |
| **therumor.com** marketing site | **Yes** — computed styles, 2026-10-07 | Calm restraint: sentence-case controls, a three-step ink ladder, large tight-tracked display, generous section rhythm |
| **Rumor's actual dashboard** | **No — behind a login at therumor.com, never seen** | Nothing. Its appearance is not described or imitated anywhere in this document. |
| Apple HIG / a16z editorial restraint | Not inspected as artefacts | Used as principles only: clarity, hierarchy, one idea per block |

### What Rumor's public site measures as

Pure white; ink `#1F1F1F`; muted `#6B6B6B`; dim `#ABABAB`. Display face **Romie** (serif)
700 at 50–64px, tracking −0.025em, leading ~1.1. UI face **Dia** 500 at 18px. Buttons are
**fully rounded pills** (`border-radius: 9999px`), sentence case, 18px/500, black-on-white
and white-on-black. Section rhythm 48–96px.

**This conflicts with Snatch It's own system** — radius 0, Oswald condensed caps, red accent.
The conflict is resolved deliberately and not split down the middle:

- **Kept from Snatch It:** radius 0, `#FF1A1A` primary button with black text, Oswald for
  short display headings, the red accent eyebrow. This is the brand.
- **Kept from Rumor:** sentence case on every control and label, the muted ink ladder,
  display type set large with tight negative tracking, and section rhythm measured in
  white space rather than borders.
- **Rejected:** pill buttons and a serif display face. Both are Rumor's identity, not ours.

---

## 2. Tokens

Measured from snatchitapp.com's white sections, then adjusted only where a measurement
failed accessibility.

```
bg        #ffffff      surfaces
raised    #fafafa      hover rows, quiet strips
ink       #0b0b0b      primary text
muted     rgba(11,11,11,0.66)   secondary text
dim       rgba(11,11,11,0.58)   tertiary text
line      rgba(11,11,11,0.14)   hairlines — NEUTRAL, never red
accent    #dd0000      red as TEXT on white
primary   #ff1a1a      red as a FILL, always with black text
radius    0
```

The site's own muted ink is 56%, which measures 4.54:1 on white but **4.45:1 on the quiet
tint — under AA**. The tint was lightened to `#fafafa` and the two muted tokens taken to
66% and 58%. *Rule: a measured accessibility failure outranks a measured brand value.*

---

## 3. Type

- **Oswald 700, uppercase** — page titles and short section headings **only**. Never a
  label, control, status, table header, or the name of a thing in a list.
- **Inter, sentence case** — everything else, including every button.
- A list item's name is `.item-title` (Inter 600, 1.0625rem). A long name in caps is wide
  and hard to read.
- Sizes are `rem` from four named tiers. **No px font-size anywhere** — guarded by a test.
- Eyebrow: uppercase, 0.16em tracking (the site's 0.45em is a landing-page value and costs
  too much width in a dashboard).

## 4. Layout

- **No boxed cards.** Sections are separated by white space and a heading; lists are
  hairline-divided rows. A card is justified only when its contents are a single object
  the reader will act on as a unit.
- **One filled primary action per block.** Everything else is a text link with an arrow.
- Multi-column grids use `repeat(auto-fit, minmax(min(Xrem, 100%), 1fr))`. A grid whose
  column count comes from a viewport breakpoint ignores the reader's text size; a grid in
  `rem` collapses on its own when the type doubles. The `min(…, 100%)` is required or the
  grid overflows a narrow screen.
- One rendering per screen. Do not build a desktop table and a separate phone card deck
  from the same data: they drift, and panels end up on the page twice.

## 5. Every page answers six questions

Where am I · What am I looking at · What needs my attention · What can I do next ·
What happened after I acted · How do I go back.

- Lead with the thing, not a statistics wall. The **primary action follows the stage**: a
  venue overview says "Get this event ready", "Open check-in" or "Review this event"
  depending on where the event actually is.
- Show only actionable issues. Checks that found nothing are collapsed into a count, so an
  empty list reads as "we looked" rather than "nothing ran".
- Supporting numbers go **below** the thing they support, and **every figure carries the
  sentence that defines it**. One measure per header: "Sold of capacity" or "Still
  available", never one header over two different measures.
- Advanced detail and raw records go behind a named disclosure, never as the default view.
- Multi-step flows keep a visible Cancel and a way back on every step.

## 6. Honesty rules (non-negotiable)

- **No backend identifier in anything a person reads** — not in a heading, not in body
  copy, and **not in a tooltip**. A tooltip is product UI. The schema name belongs in
  developer documentation. Guarded by a test that scans rendered visible text *and*
  `title`/`aria-label` attributes, carrying its own positive control.
- Never promise a record the reader cannot open. If an action is attributable but there is
  no screen to read that history on, say both.
- A figure the data source cannot produce renders a dash **with a reason**, never `0`.
- Distinguish states that have different next actions: "filtered to nothing" is not
  "nothing exists"; "sold out" is not "all held"; a refund **recorded** is not a refund
  **settled** (A's wording — reuse it verbatim, never paraphrase).
- Demo surfaces carry a permanent "Demo — sample data" strip, and every simulated action
  answers in plain words that nothing was saved.

## 7. Accessibility floor

Verified by measurement, per screen and per state:

- **Rendered** contrast ≥ 4.5:1 (≥ 3:1 for large/bold), measured on the painted page with
  the effective background composited — not on the tokens. Colours are resolved through a
  canvas, because Chrome returns some backgrounds as `lab()` and a regex over the numbers
  silently invents failures.
- 0 px horizontal overflow at 375 and 1024, at 1×, 1.5× and 2× text.
- No control under 24×24 (inline links in prose excepted).
- Every automated sweep carries a **positive and a negative control in the same run**. A
  run whose controls misbehave is reported as broken, not as passing.

**Not covered by any of this:** screen-reader behaviour. No screen reader has been run
against either dashboard. Keyboard order, visible focus, accessible names, heading order,
form-error association and dialog focus are source-inspected only unless a report says
otherwise explicitly.

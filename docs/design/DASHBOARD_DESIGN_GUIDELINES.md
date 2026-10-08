# Snatch It dashboard design guidelines

One design language for the **venue dashboard** (`venue/`) and the **admin operating
console** (`admin/`). Written from measured sources, not taste. Where a rule came from a
measurement, the measurement is named so a later reader can re-take it.

Owner: F (layout, navigation, visual design, plain-language presentation).
A owns payment, refund, payout and authoritative-state wording. D reviews operational
behaviour and permissions. Nothing here overrides them.

---

## 1. The reference, and what is visible in it

**Superseded on 2026-10-08.** The earlier radius-0 / square-button / no-cards /
mandatory-Oswald rules are withdrawn. They came from the marketing site, which is a
black landing page, and they fought the product appearance the owner actually wants.
Do not reinstate them because an older commit or an older copy of this file says so.

The reference is the **dashboard shown inside the laptop** in the owner's Rumor
screenshot (2026-10-07). Target roughly 90% of that feel, adapted to Snatch It's
workflows. Only what is *visible* in that image is recorded here; Rumor's private
dashboard was never accessed and none of its behaviour is assumed.

### What is visible

| Element | What the image shows |
|---|---|
| Sidebar | Narrow dark, near-black rail. Logo top, a short stack of icons, one active item marked by a filled light circle, sign-out pinned at the bottom |
| Workspace | Soft light-grey canvas behind the content |
| Panels | White, rounded corners, hairline border, little or no shadow |
| Page head | Circular back control, large semibold title, a grey subtitle beside it; bell and avatar at the right |
| Section head | Title plus one explanatory sentence underneath, in grey |
| Tabs | Text tabs with an underline on the active one |
| Buttons | **Pills.** Light/white with a hairline border and a small leading icon for secondary; solid dark for the committing action ("Apply Filters") |
| Filter panel | White rounded card, a count badge, a close ×, search, collapsible groups, checkboxes, a range slider, "Clear All" beside a solid "Apply Filters" |
| Table | Checkbox column, avatar + name, aligned text columns, small chips for overflow ("+1"), quiet row dividers, comfortable row height |
| Colour | Almost entirely neutral. No large saturated fills anywhere |

### What we take, and the two places we deliberately differ

Take: the dark rail, the grey canvas, white rounded panels, pill controls, chips and
badges, hairline borders, minimal shadow, the calm neutral palette, and tables that are
readable rather than dense.

Differ, on purpose:

1. **Navigation is labelled, not icon-only.** The reference's rail is icons alone. A
   first-time operator should not have to hover to learn the sections, so our rail shows
   text labels and stays wide enough to hold them.
2. **Targets and type are larger.** Do not reproduce the reference's smallest text or
   its tight controls. Minimum 24px targets, comfortable row height, body text that is
   readable at a glance.

### Snatch It identity inside this

Red is no longer the default button colour. It stays as: the active navigation marker,
the brand mark, and destructive emphasis. The committing action is a solid dark pill.
Oswald is optional, not mandatory — Inter sentence case is the default for everything,
including page titles, unless a specific heading genuinely reads better in the display
face.

## 2. Tokens

```
canvas     #f4f4f5   the workspace behind the panels
surface    #ffffff   panels, tables, menus
sidebar    #141416   the dark rail
sidebar-fg rgba(255,255,255,0.72)      sidebar label
sidebar-on #ffffff on rgba(255,255,255,0.10)   active item
ink        #0b0b0b   primary text
muted      rgba(11,11,11,0.66)   secondary text
dim        rgba(11,11,11,0.58)   tertiary text
line       rgba(11,11,11,0.10)   hairline borders
solid      #141416   the committing button, white text
accent     #dd0000   active nav marker, brand mark, destructive emphasis
radius     panel 14px · control 10px · pill 9999px · chip 9999px
shadow     0 1px 2px rgba(11,11,11,0.04) — panels only, never on a control
```

A measured accessibility failure still outranks any value here: every text token must
clear 4.5:1 on the surface it actually sits on, measured on the painted page.

## 3. Type

Inter throughout, sentence case. Sizes in `rem` from named tiers — no px font-size
anywhere, so the browser text-size setting moves the whole page.

- Page title: 1.5rem, 600, tracking −0.01em
- Section title: 1.0625rem, 600
- Body / table cell: 0.875rem
- Secondary and table header: 0.8125rem, muted
- Chip and badge: 0.75rem

Oswald is available for a short display heading where it genuinely helps. It is not
required, and it is never used for labels, controls, statuses or table headers.

## 4. Components

- **Button.** Pill. `solid` is the committing action (dark, white text). `quiet` is
  white with a hairline border. `ghost` is text-only. **`danger` is distinct**: red
  border and red text, never the same shape-and-colour as an ordinary action, and
  anything moving money or voiding tickets additionally needs a typed confirmation.
  Links navigate, buttons act.
- **Panel.** White, radius 14, hairline border, optional title + one explanatory
  sentence, optional actions in the header.
- **Table.** Aligned columns, quiet dividers, comfortable rows, a search field and
  filter chips above it. Numeric columns right-aligned and tabular.
- **Chip / Badge.** Pill. Status badges carry a word, never colour alone.
- **Reference.** The copyable record-ids disclosure (§6) keeps its role unchanged.

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
- A lookup that resolves nothing explains why and offers a usable recovery path. Transfer
  search and filtering stay discoverable under Orders; a transfer id with no owning order
  says so in plain words and hands the operator a search that will find it.

## 6. Honesty rules (non-negotiable)

- **No internal schema name in anything a person reads** — not in a heading, not in body
  copy, and not in a tooltip. A tooltip is product UI; the table or function name belongs
  in developer documentation. Guarded by a test that scans rendered visible text *and*
  `title`/`aria-label` attributes, carrying its own positive control.
- **This is not a ban on references.** Order, payment, transfer, case and Stripe ids are
  how an operator investigates and how support answers a customer. Keep them, in a
  clearly labelled, copyable details area — "Reference" — not scattered through prose.
  Hide the *schema*, keep the *evidence*.
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

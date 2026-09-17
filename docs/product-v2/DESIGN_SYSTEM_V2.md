# Snatch It Design System V2

**Status:** proposal, pending owner approval. Nothing here is implemented yet.
**Source of truth for brand values:** `docs/product-v2/MARKETING_BRAND_EXTRACTION.md`, which records
values read live from `snatchitapp.com` on 2026-09-02.

This system exists to close one gap: the marketing site, the web app and the mobile app must look
like one company. Today they do not. The mobile app runs a blue-black palette, a different red, a
rounded geometry and no brand typeface at all.

---

## 0. Principles

1. **Square is the brand.** Radius 0 is not a style preference, it is the identity. The only
   rounded things in the product are circular avatars and the device chrome in marketing imagery.
2. **Black is black.** `#000`. No blue-tinted neutrals anywhere.
3. **Red means action or attention, never decoration.** If it is red, it is tappable, it is a
   price that changed, or it is a warning.
4. **Display type is Oswald and it shouts. UI type is Inter and it whispers.** Nothing in between.
5. **Artwork is the product.** In marketing, photography is an underlay at 8 to 22% opacity. In
   the product, event artwork is shown at full strength. The dimming rule inverts.
6. **Transactional clarity outranks drama.** No grain, glow or streaks behind a price, a QR code,
   a form or a confirmation.
7. **One system, three surfaces.** A token defined here has one value, expressed for React Native,
   for CSS, and in the shared package.

---

## 1. Color tokens

### 1.1 Canvas and surface

| Token | Value | Use |
|---|---|---|
| `bg` | `#000000` | App canvas. Every screen background. |
| `surface` | `#0A0A0A` | Cards, sheets, list rows that need separation from canvas. |
| `surface-raised` | `#111111` | Modals, menus, anything above a surface. |
| `surface-sunken` | `#000000` | Input wells and image letterbox areas. |
| `overlay` | `rgba(0,0,0,0.72)` | Scrim behind modals and sheets. |
| `scrim-image` | `linear-gradient(180deg, rgba(0,0,0,0) 35%, rgba(0,0,0,0.85) 100%)` | Standard gradient for text over artwork. |

### 1.2 Ink

| Token | Value | Use |
|---|---|---|
| `ink` | `#FFFFFF` | Primary text. |
| `ink-muted` | `rgba(255,255,255,0.70)` | Body and secondary text. |
| `ink-dim` | `rgba(255,255,255,0.45)` | Metadata, timestamps, captions. |
| `ink-faint` | `rgba(255,255,255,0.30)` | Micro labels and placeholders. Decoration only. |
| `ink-on-primary` | `#000000` | Text on red. Black on red is a brand signature. |

**Rule:** anything at `ink-dim` or below may not carry information a user needs to complete a
task. If it matters, it is `ink-muted` or brighter.

### 1.3 Brand and state

| Token | Value | Use |
|---|---|---|
| `primary` | `#FF1A1A` | Primary actions, active states, brand accent. |
| `primary-pressed` | `#CC0000` | Pressed and hover. |
| `primary-soft` | `rgba(255,26,26,0.10)` | Selected row tint, badge fill. |
| `line` | `rgba(255,26,26,0.15)` | Default hairline. Red-tinted, never gray. |
| `line-strong` | `rgba(255,26,26,0.30)` | Emphasised divider, sticky bar top edge. |
| `line-neutral` | `rgba(255,255,255,0.10)` | Hairline over artwork, where red would fight the image. |
| `success` | `#3DDC84` | Confirmed, delivered, paid. |
| `warning` | `#FFB020` | Needs attention, expiring. |
| `danger` | `#FF4D4D` | Destructive and failure. Distinct from `primary`. |

**Deprecated on sight:** `#E10600` (old mobile red), `#0B0F14` / `#11161C` / `#1a2030` /
`#1C232B` / `#2e3a50` (blue-black neutrals), `#8a94a6` / `#4a5568` / `#5a6478` (blue-gray inks),
`#ffd700` (gold badge). None of these exist in the brand.

`danger` is deliberately a different red from `primary`. Today a destructive action and a primary
action are the same color, which is a real usability defect, not a stylistic one.

### 1.4 Inventory semantics (new, needed for venue-native)

The product must distinguish tickets sold by the event from tickets sold by another fan. This is a
trust requirement, not decoration.

| Token | Value | Use |
|---|---|---|
| `direct` | `#FF1A1A` | Direct from the event. Uses the brand red because it is the primary offer. |
| `marketplace` | `#FFFFFF` | Fan to fan. Neutral white, never red. |

Provenance is always carried by **a word plus a shape**, never by color alone: a square badge
reading `DIRECT FROM EVENT` or `FROM A FAN`. Colorblind users and screenshot readers both need it.

---

## 2. Typography

Two families. Both self-hosted, both loaded at app start. Mobile must call `useFonts`; it
currently loads nothing.

| Token | Family | Size / Line | Weight | Tracking | Case | Use |
|---|---|---|---|---|---|---|
| `display-xl` | Oswald | 44 / 40 | 700 | -0.02em | upper | Screen hero, rare. |
| `display-lg` | Oswald | 34 / 32 | 700 | -0.02em | upper | Event title on detail. |
| `display-md` | Oswald | 26 / 26 | 700 | -0.02em | upper | Screen titles, section heads. |
| `display-sm` | Oswald | 20 / 22 | 700 | -0.01em | upper | Card titles, sheet titles. |
| `title` | Inter | 17 / 22 | 600 | 0 | sentence | Row titles, user-generated names. |
| `body` | Inter | 15 / 22 | 400 | 0 | sentence | Reading text. |
| `body-sm` | Inter | 13 / 18 | 400 | 0 | sentence | Secondary text. |
| `label` | Inter | 12 / 16 | 700 | +0.18em | upper | Buttons, tabs, chips. |
| `micro` | Inter | 10 / 14 | 500 | +0.30em | upper | Eyebrows, metadata keys. |
| `mono-price` | Inter (tabular figures) | 20 / 24 | 700 | 0 | n/a | Prices. Always tabular. |

Rules:

- **Never uppercase user-generated content.** Event names, venue names and person names arrive in
  mixed case and become unreadable when forced up.
- **Oswald is for our voice, not for other people's content.** Screen titles, section heads, the
  numbers on a ticket, empty-state lines. Both first-party benchmarks deliberately set event titles
  at normal weight and never uppercase them, because the poster already contains display type and
  two competing headlines read as a mistake. So: **event titles on cards and next to artwork use
  `title` in Inter, sentence case.** Oswald appears on an event only in the detail hero, where it is
  large enough to be architecture rather than competition, and only when the title is short.
- The heaviest weight in a transactional screen should be the price, not the chrome.
- **Prices use tabular figures** so digits do not jitter as a bid updates.
- **Tracking above +0.18em only at 12px and below.** Wide tracking on long strings destroys
  readability.
- Minimum body size is 13px. Anything smaller is a label, not text.
- Support Dynamic Type on iOS at least to the "Large" accessibility tiers; display styles cap
  their growth so headlines do not push CTAs off screen.

---

## 3. Space, geometry, elevation

**Spacing scale (4pt base):** `1`=4, `2`=8, `3`=12, `4`=16, `5`=20, `6`=24, `8`=32, `10`=40,
`12`=48, `16`=64.

Screen gutter is 16 on mobile, 24 at tablet width. Vertical rhythm between sections is 32.

**Radius:** `0` for every rectangular element. `full` (9999) is permitted only for avatars and
status dots. There is no middle value. Removing the 6/10/16/24 ladder is the single most visible
change in this system.

**Borders:** 1px hairlines using `line`. Over artwork, use `line-neutral`.

**Elevation:** the brand has no soft shadows. Separation comes from surface value and hairlines.
Two permitted shadows, both for genuinely floating layers:
`sheet` = `0 -8px 24px rgba(0,0,0,0.6)`, `menu` = `0 8px 24px rgba(0,0,0,0.6)`.
Cards get no shadow.

**Hit targets:** minimum 44x44. A square button at `label` size needs 14 vertical padding to reach
it.

---

## 4. Motion

| Token | Duration | Curve | Use |
|---|---|---|---|
| `instant` | 90ms | ease-out | Press feedback, toggles. |
| `swift` | 180ms | `cubic-bezier(0.22, 1, 0.36, 1)` | Sheets, tab changes, most transitions. |
| `settle` | 280ms | `cubic-bezier(0.22, 1, 0.36, 1)` | Screen push, image reveal. |

Press states scale to `0.98` and never bounce. Skeletons pulse opacity 0.4 to 0.7 at 1200ms; no
shimmer sweep. Everything respects reduced-motion: durations collapse to 0.01ms, and the app must
honor the OS setting the way `web/src/app/globals.css` already does.

---

## 5. Components

Each entry lists the states that must exist. A component is not done until every state is drawn.

### 5.1 Button
Variants: `primary` (red fill, black label), `secondary` (transparent, 1px `line-strong`, white
label), `ghost` (text plus arrow, red on press), `danger` (transparent, `danger` border and label).
Sizes: `lg` 52 tall full-width, `md` 44, `sm` 36.
States: default, pressed, disabled (40% opacity, no color change), loading (spinner replaces
label, width held), success (brief check, 900ms).
Square. Label in `label` style. There is no filled secondary button in this brand.

### 5.2 Sticky action bar
Fixed bottom, `surface` background, 1px `line-strong` top edge, safe-area padded. Holds the price
on the left and the primary action on the right. Used on event detail, listing detail and checkout.

### 5.3 Input
Transparent field, hairline bottom border only, 50 tall, label above in `micro`, helper or error
below in `body-sm`. Focus raises the border to `primary`. Error uses `danger` for border and
message. Never place placeholder text as the only label.

### 5.4 Chip and filter
Square, 32 tall, 1px `line`, `label` type. Selected state fills `primary-soft` with a `primary`
border and white text. Chips scroll horizontally in a single row; they never wrap to a second line.

### 5.5 Badge
Square, 20 tall, `micro` type, 6 horizontal padding. Variants: `direct` (red fill, black text),
`marketplace` (white 1px border, white text), `status` (`success` / `warning` / `danger` border and
text), `count` (red fill, black text).

### 5.6 Event card
The most important component in the product. Media specified fully in
`docs/product-v2/EVENT_MEDIA_SYSTEM.md`. Structure: a 4:5 media block, then a text block below it,
never on it: title in `title` (Inter, sentence case, two-line clamp), venue and date in `body-sm`
at `ink-dim`, then a row carrying the all-in price and the provenance badge.

The price shown on a card is **always all-in**. It is never a pre-fee number that grows at
checkout, and all-in is an invariant of the system, not a per-event setting. A card with no price
falls back through a ladder rather than rendering blank: lowest all-in price, else last sale price,
else an invitation to sell.

### 5.7 Ticket
Full-bleed event artwork header, then credential area on `surface` with the QR at maximum
practical size on a white square (a QR needs light background to scan), then event metadata, then
actions. The QR area never carries grain, gradient or glow.

### 5.8 Sheet and modal
Sheets rise from the bottom, square top corners, `surface-raised`, drag handle as a 4px white bar
at 30% opacity, `overlay` scrim behind. Modals center only for destructive confirmations.

### 5.9 Skeleton, empty, error
Skeletons mirror the exact geometry of the content they replace, in `surface` at the pulse above.
Empty states are a `display-sm` line, one `body` line, and one action; no illustration, no emoji.
Error states name what failed and offer one retry; never a raw error string.

### 5.10 Navigation
Tab bar: `surface` with a `line` top edge, icons at 24, `micro` labels, active tab in `primary`.
Headers: 56 tall, transparent over artwork with a back control that always has a scrim behind it
for legibility, otherwise `bg` with a `line` bottom edge.

---

## 6. Iconography

One family, outline, 1.5px stroke, 24px grid, square terminals to match the geometry. No filled
duotone icons and no emoji in production UI. Icons carry a text label anywhere the meaning is not
universally obvious.

---

## 7. Implementation plan

1. **Fix the token direction.** `packages/design-tokens` currently generates from
   `src/theme/index.ts`, so the non-brand mobile palette is upstream of everything. Invert it: the
   package becomes the source of truth, holding the values in this document, and both clients
   consume it. This is the prerequisite for every other change.
2. **Load the fonts in mobile.** `expo-font` is already a dependency and unused. Add Oswald 700 and
   Inter 400/500/600/700, gate the splash screen on load, and set the default text style.
3. **Ship the primitives** in `src/components/ui/`: Button, Input, Chip, Badge, Sheet, Skeleton,
   EmptyState, StickyBar, plus the media components from the media system document.
4. **Migrate screens in the Tier order** of `docs/product-v2/UI_IMPLEMENTATION_PLAN.md`, deleting
   ad hoc styles as each screen is converted.
5. **Add a lint guard** that fails the build on a raw hex color or a non-zero radius outside the
   token files, so the system cannot silently fork again.

## 8. Anti-patterns, explicitly banned

Glassmorphism and frosted panels. Gradient fills on buttons or cards. Purple, indigo, teal or any
palette not defined above. Glowing cards. Pill-shaped buttons and pill tabs. Rounded containers.
Generic dashboard chrome. Decorative charts with no product purpose. Fake or placeholder metrics.
Giant empty hero whitespace. Drop shadows on cards. Emoji as interface icons. Multiple competing
accent colors. Any copy written in a machine register, and no em dashes in customer-facing text.

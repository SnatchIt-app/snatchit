# Venue dashboard — light appearance

Owner request (2026-09-10): white primary surfaces for easier navigation and analytics reading.
Layout, routes, permissions, fixture and database behaviour are unchanged; only presentation.

## Where the theme lives

- `src/app/globals.css` — the shared token sheet (`@theme inline`) plus the brand primitives
  (`.field`, `.btn*`, `.link`, `kbd`, `.data-table`). Same file structure as `admin/`.
- `src/app/globals-preview.css` — preview/database banners, skeletons, capacity bar + legend swatches,
  door surfaces.
- Components reference tokens only (`bg-card`, `text-muted`, `border-line`…); the only literal colours in
  TSX are the black **Apply** button on the preview strip and the Next `themeColor`.

## Tokens (all measured against white)

| Token | Value | Role | Contrast |
|---|---|---|---|
| `bg` / `card` / `field` | `#ffffff` | page, panels, inputs | — |
| `raised` | `#f5f5f6` | section distinction, hover rows, disabled fields | — |
| `ink` | `#111111` | primary text | 18.9:1 |
| `muted` | `#4a4a4a` | secondary text, table headers | 9.0:1 |
| `dim` | `#6b6b6b` | tertiary text, eyebrows | 5.7:1 |
| `placeholder` | `#6b6b6b` | input placeholders (also on disabled gray) | 5.7:1 (5.2:1 on raised) |
| `primary` | `#ff1a1a` | brand fills and borders; CTAs stay black-on-red | 3.9:1 (non-text) |
| `primary-ink` | `#c40000` | brand red as **text** (`text-primary-ink`) | 5.9:1 |
| `primary-soft` | `rgba(255,26,26,.08)` | selected nav item, hover tint | — |
| `line` / `line-strong` | red-tinted hairlines | panel and header rules | — |
| `line-neutral` | `rgba(17,17,17,.12)` | neutral hairlines, gridlines | — |
| `success` | `#15803d` | on sale, admitted | 5.0:1 |
| `warning` | `#b45309` | held, stale, low stock | 5.0:1 |
| `danger` | `#c40000` | cancelled, errors | 5.9:1 |
| `info` | `#1d4ed8` | announced, escalated | 6.3:1 |

## States

- **Hover**: nav items and table rows tint (`raised` / `primary-soft`); ghost buttons gain a red hairline.
- **Selected**: nav `aria-current="page"` → red left rule + `primary-soft` + semibold; table rows with
  `aria-selected="true"` → tinted with an inset red rule.
- **Focus**: 2 px `#ff1a1a` outline (`:focus-visible`), fields add a soft red ring.
- **Disabled**: fields go `raised` gray with `not-allowed`; buttons drop to 45 % opacity.
- **Banners**: preview = amber stripes with near-black text; database mode = light-blue stripes with navy text.
  Both stay sticky and non-dismissible.

## Analytics

- Capacity bars: sold (brand red), held (`warning` amber), remaining (gray track). Each number in the
  legend carries a matching swatch, so colour is never the only cue.
- Door arrivals: dashed gridlines at 25/50/75/100 %, per-bar `title`, an `aria-label` listing every
  value and the peak, and an oldest/latest axis caption.
- Counter tiles and status chips are text + border; no colour-only meaning.

## Screenshots

`docs/screenshots/light/` — every surface at 1440 (desktop) and 390 (mobile), inventory also at 820
(tablet), plus hover/keyboard-focus captures and the loading / empty / no-match / error / denied /
sign-in states.

## Pass 2 (2026-09-14)

- **Disclosure menus** (`<details>/<summary>`: mobile nav drawer, door reference panels, "New manual case",
  audit rows, MFA secret): hover = `raised`, keyboard focus = inset red outline, open = hairline under the summary.
- **Inline code** gets a faint `raised` chip so identifiers stay scannable on white.
- **Placeholder** darkened to `#6b6b6b` so it also passes on the gray disabled-field background (5.2:1).
- **Tooltips** are native `title`/`<abbr title>` (metric definitions, chart bars, partial cells), so they follow
  the OS light tooltip; every chart also carries the same values as text or an `aria-label`.
- **Automated guard**: `tests/theme-contrast.test.ts` parses the token sheet and fails the suite if any text token
  drops below 4.5:1 on white or on `raised`, a status/brand colour below 3:1 as a border, black-on-red below 4.5:1,
  or if a primary surface stops being white.

New previews: `30-mobile-menu-open-mobile`, `31-door-disclosures-open-mobile`, `32-filter-field-focus-desktop`.

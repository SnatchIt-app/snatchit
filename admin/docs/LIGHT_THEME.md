# Operating console — light appearance

Owner request (2026-09-10): white primary surfaces for easier navigation and analytics reading.
Routes, permissions (`ops.whoami`, aal2 step-up), data reads and every action form are unchanged;
only presentation.

## Where the theme lives

- `src/app/globals.css` — the shared token sheet (`@theme inline`) plus the brand primitives
  (`.field`, `.btn*`, `.link`, `kbd`, `.data-table`). Same structure as `venue/`.
- Components reference tokens only. Literal colours left in TSX: the black-on-red production
  environment badge and skip-link (brand CTA contrast), the white QR container in the MFA flow, and the
  Next `themeColor`.

## Tokens

Identical to `venue/docs/LIGHT_THEME.md` (white `bg`/`card`/`field`, `raised` `#f5f5f6`, ink
`#111`/`#4a4a4a`/`#6b6b6b`, `primary` `#ff1a1a` for fills, `primary-ink` `#c40000` for text, status
colours `#15803d` / `#b45309` / `#c40000` / `#1d4ed8`, all ≥ 4.5:1 as text on white).

## Console-specific decisions

- **Environment badge**: production stays black-on-red; every other label (`sandbox`, `local`,
  `preview`) is an amber-outlined badge so a non-production console is obvious at a glance.
- **Sidebar**: active section = red left rule + `primary-soft` + semibold; hover = `raised`.
- **Metric grids**: tiles are separated by neutral hairlines drawn as cell borders (the previous
  grid-gap trick exposed the line colour as a gray slab on white). "Not available locally" tiles keep
  their hatched pattern, now dark-on-white at 4 %.
- **Tables**: header row on `#fafafa` with a red rule; hover and keyboard focus tint the row; sort links
  turn red on hover; empty results render the standard "Nothing here" alert inside the table.
- **Alerts**: left rule in the state colour, text carries the state label — never colour alone.
- **Forms/dialogs**: `.field` hover darkens the hairline, focus = red border + soft ring, disabled =
  gray on `raised`; confirm forms and the MFA flow use the same primitives.

## Screenshots

`docs/screenshots/light/` — login, Today, Cases, Orders (list, hover, keyboard focus, empty filter,
detail), Money, Users (list, detail), Marketplace (list, detail), Reports, System, Search, Not found,
Denied; desktop 1440 and mobile 390 for the main sections. Captured against the local synthetic
harness (`scripts/local-stack.sh`), never a hosted project.

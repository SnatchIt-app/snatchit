# F9 — admin console navigation below 768 px (2026-09-14)

Recorded as F9 in the release package (reported by Claude D). Local development and verification only.

## Defect

The console is live. Below `md` (768 px) the sidebar is `hidden md:block` and nothing replaced it, so on a phone the
only way between sections was typing a URL, the search box, or `g`-shortcuts.

## Fix (`admin/f9-mobile-nav`, base `admin/operating-console @ 562fda9`)

- `src/lib/nav.ts` — the one section list (moved from `Sidebar.tsx`, re-exported there, so `KeyboardShortcuts`
  is untouched) and `isNavActive()` (also stops `/casesx` counting as `/cases`).
- `src/components/shell/MobileNav.tsx` — disclosure pattern: a real `<button>` (`aria-expanded`, `aria-controls`,
  "Menu"/"Close") in the sticky header reveals a labelled `<nav>` with the same eight sections, 44 px rows and
  `aria-current` on the active one. Escape closes and returns focus to the button. Choosing a section, or any
  navigation (including `g`-shortcuts), closes it: "open" is bound to the pathname it was opened on. `md:hidden`, so
  desktop and tablet-with-sidebar are unchanged.
- **Authorization and data access unchanged:** no new route, no data read; every page still passes the proxy
  (session + aal2) and `requireOperator()` (`ops.whoami()`); signed-out screens show no menu.

## Verification

| Check | Result |
|---|---|
| typecheck / lint | clean |
| vitest | **102/102** (6 new in `tests/mobile-nav.test.ts`: active rules, one shared list, closed renders nothing, open lists exactly 8 sections with one `aria-current`, toggle wiring) |
| `next build` | green |
| `scripts/ui-audit/mobile-nav-check.mjs` on this branch (dark) | **14/14** — button visible/collapsed at 390, no sidebar, no overflow; click opens with the 8 sections and `aria-current` on Cases; Escape closes and returns focus; Enter on the focused button opens; choosing Money navigates and closes; `g s` navigates and closes; at 768 and 1440 the sidebar shows and the button is hidden; signed out: no menu, `/cases` redirects to `/login` |
| same check on light theme + F9 + fixes (combined probe) | **14/14** |
| UI audit on this branch | unchanged vs the current console except the new control (text elements 9 381, 0 new unnamed controls, 0 new overflow) |

## Previews (`docs/screenshots/f9/`)

`f9-dark-390-closed.png`, `f9-dark-390-open.png` (this branch) · `f9-light-combined-390-closed.png`,
`f9-light-combined-390-open.png` (with `admin/light-theme`).

Independent of `admin/light-theme` and `admin/a11y-responsive-fixes`; all three merge together without conflict.

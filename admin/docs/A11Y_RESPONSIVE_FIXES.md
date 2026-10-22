# Admin console — tablet overflow and unlabeled settings controls (2026-09-14)

Found by the UI audit prepared for `admin/light-theme` review; present on the current console, independent of the
theme. Branch `admin/a11y-responsive-fixes`, base `admin/operating-console @ 562fda9`. Local only.

| Finding (current console) | Cause | Fix |
|---|---|---|
| `/orders/:id`, `/users/:id`, `/marketplace/:id` 1066–1374 px wide at 768 px | detail grid defined columns only from `lg`; its implicit column sized to wide table content | `grid-cols-1` (`minmax(0,1fr)`) below `lg` on the five detail layouts (also `/cases/:id`, `/actions/:id`) |
| then still 801 px at 768 | `DateTime` rendered "stamp (4d ago)" as one no-wrap run in a 133 px key/value cell | each part stays unbroken; the line may break between them |
| 3 unnamed comboboxes on System → Settings | `<li id="setting-KEY">` and its control shared an id, so `<label htmlFor>` resolved to the `<li>` | control id `setting-KEY-value`; the `#setting-KEY` anchor still targets the `<li>` |

Verification: typecheck, lint, vitest **103/103** (`tests/a11y-responsive.test.ts`), `next build`; UI audit on this
branch **overflow 0/56 page views, unnamed controls 0** (`docs/ui-audit/ui-audit-a11y-fixes.md` vs
`ui-audit-baseline-dark.md`). Wide layouts (`lg` and up) unchanged.

# admin/light-theme — integration review pack (2026-09-14)

For Claude A. Local development and verification only; nothing deployed, no hosted project touched.

## What this branch is

`admin/light-theme-integration` = `release/convergence-135 @ c55ea50` + `--no-ff` merge of **`admin/light-theme @ b25c1a3`**
(unchanged), plus two review commits:

| Commit | Change |
|---|---|
| merge | `b25c1a3` onto `c55ea50` — auto-merged, **admin/ files only** |
| `02a824c` | theme correction: `.field:focus-within` carries the focus ring (native date/time inputs focus internal segments, so `:focus` never matched — 10 of 774 focus stops had no indicator); `scripts/ui-audit/` tool |
| `47f4a25` | audit tool: key events may carry text |

## Current-base compatibility

- `release/convergence-135` has not moved since `c55ea50`; the release package work on `fix/122-transfers-profiles-fk`
  touches `docs/`, `scripts/release/` and `supabase/` only, so it cannot conflict with `admin/`.
- No migration, no env var, no dependency, no route, no data read changed. CSS tokens and class names only.
- Separately prepared and **proven to combine** (throwaway merge, not on this branch): `admin/f9-mobile-nav` and
  `admin/a11y-responsive-fixes` merge on top with no conflict; typecheck, lint, **vitest 122/122**, `next build` green.

## Checks on this branch

typecheck clean · lint clean · vitest **109/109** (incl. `theme-contrast.test.ts`) · `next build` green (harness env).

## Browser audit — `scripts/ui-audit/audit.mjs`, local synthetic harness, headless Chrome

14 console pages × 390 / 768 / 1024 / 1440 = 56 page views, signed in as the harness operator (plus `/login` signed out).

| Measure | Current console (dark, `c55ea50`) | **This branch (light)** | light + F9 + fixes (combined probe) |
|---|---|---|---|
| Text contrast failures (WCAG 1.4.3, rendered) | 869 | **0** | 0 |
| Text elements checked | 9 357 | 9 357 | 9 381 |
| Focus stops without a visible indicator (WCAG 2.4.7) | 174 / 774 | **0 / 774** | 0 / 775 |
| Page views with horizontal overflow | 3 | 3 → fixed on `admin/a11y-responsive-fixes` | **0** |
| Controls with no accessible name | 12 | 12 → fixed on `admin/a11y-responsive-fixes` | **0** |
| Targets < 24 px at 390 (heuristic) | 64 | 64 | 99 |
| Text over a background image (manual) | 32 | 32 | 32 |
| Pages without one `<main>` / one `<h1>` / `lang` | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |

Reading the remaining rows:
- **Small targets** are table sort-header links (14 px text) and inline name/id links inside table and key/value cells,
  all with cell padding around them — WCAG 2.5.8's spacing exception very likely applies. Not changed; listed for a
  manual decision. The count rises in the combined probe only because detail-page content that previously overflowed
  off-screen now lays out inside the viewport.
- **Text over a background image** is the "not available locally" hatch on metric tiles (4 % dark stripes on white);
  checked visually, text stays dim-on-white.

Full per-page tables: `docs/ui-audit/ui-audit-baseline-dark.md`, `ui-audit-light-integration.md`,
`ui-audit-combined-light-f9-a11y.md`.

## Previews (`docs/screenshots/light-review/`)

Today, Orders, Money, System at **390, 768, 1024, 1440** (`audit-light-integration-<page>-<width>.png`); earlier
`docs/screenshots/light/` (pass 1–2) remains: login, MFA, every section, detail pages, open disclosures, focus, disabled.

## Reproduce

```bash
admin/scripts/local-stack.sh start <rehearsal db>        # synthetic harness
cd admin && npm run build && npm start                    # :3200, .env.local from .env.local.example-harness
node admin/scripts/ui-audit/audit.mjs --app http://localhost:3200 --label light --out /tmp/ui-audit
```

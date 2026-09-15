# Admin console — analytics redesign, first preview (2026-09-14)

Branch `admin/analytics-redesign` = `admin/light-theme-integration` + `admin/f9-mobile-nav` +
`admin/a11y-responsive-fixes` (all merged, no conflicts) + this redesign. Local development only: no deployment,
no tracking, no permission, route, `ops` function or migration change. **This is a preview for the owner's
visual judgement, not acceptance.**

## Direction applied

| Owner direction | What changed |
|---|---|
| White main surfaces, subtle neutral backgrounds, restrained borders, generous spacing | White cards and controls on a `#f7f7f8` canvas; neutral hairlines (`#e6e6e9`) replace the red-tinted ones; 12 px card / 8 px control radii; larger padding and section spacing; content max width 1400 px |
| Softer, readable type; sentence case; clear hierarchy | Inter throughout; page title 26/semibold, section 18/semibold, card 15–16/semibold, body 14, supporting 12–13; all-caps + letter-spaced labels removed from eyebrows, table headers, buttons, badges, filters, sidebar and brand mark; `humanize()` now returns sentence case |
| Monospace only for IDs and technical values | Unchanged mono on ids, Stripe ids, case types, sources; removed from nothing that is an id |
| Brand red selectively | Red = primary action (white text, 5.9:1), the active nav item, the brand dot; no longer on borders, eyebrows or chart series |
| Clear, consistent status colours | Status pills with a shape per state (✓ ! ✕ i –) plus text, soft tinted backgrounds; the same four colours in attention tiles and alerts |

## Overview (Today)

1. **Needs attention** first — live `ops.today()` signals that are non-zero, most severe first (urgent ✕ / soon !
   / queue i), each linking to its queue, with its definition; zero checks collapse into "N checks clear".
2. **Cases to act on** — the existing grouped case tables with All / Mine / Unassigned, unchanged behaviour; the
   empty state explains when signals exist but detectors have not opened cases.
3. **Business · last 30 days** — beside the cases on wide screens (sticky), after them on mobile: captured
   sales, platform fees (gross), fully refunded payments, seller funds released, each with change vs the previous
   30 days and its definition; a 14-day captured-sales line; link to Money analytics. Streams in after the
   operational content (Suspense), so analytics never delays or hides it.

## Money analytics (`/money`)

Range presets (7 / 14 / 30 / 90 days) + custom UTC dates · Summary: four period measures + two point-in-time /
untracked tiles (pending release now; bank payouts not tracked) · Trends: captured sales (line), platform fees
(line), fully refunded payments (columns, count), seller funds released (columns) · the existing payouts table
and reconciliation queue, unchanged, below.

## Chart treatment (dataviz method)

Form before colour: lines for trends, columns for per-period comparisons; **no donut** — no current measure is a
genuine part-to-whole with ≤ 6 comparable parts (refund/sale shares would mix bases), so none is shown. One
measure per chart, one axis, slot-1 blue from a palette validated on white (all checks pass). 2 px lines with a 10 %
wash, ≤ 24 px columns with 4 px rounded tops, hairline grid, whole-number ticks for counts, direct end label, the
partial "today so far" segment dashed. Every chart: title, units, range, grain, definition, a data-table twin
(`View data table`), crosshair / per-column tooltip, keyboard reading (←/→, Home/End, Esc) announced politely.

## States

| State | Behaviour |
|---|---|
| Loading | Operational content renders first; KPI and chart areas stream in behind fixed-size skeletons (no layout jump) |
| Empty | A range with no activity shows "No payments, fees, refunds or releases…" instead of a flat line; KPIs show $0 and "no change" |
| Stale | Header freshness turns "Stale" after 15 min; a series is bounded by its oldest point's `computed_at` |
| Error | Any failed bucket → the chart shows the failure and a retry, never a gap drawn as zero; a failed previous period → "no comparison" |
| Sample data | Visible notice on every page when connected to the local harness |

## Verification (local harness)

typecheck · lint · vitest **136/136** (incl. analytics core: buckets, deltas, three refund states, ticks, freshness,
range resolution) · `next build` · browser checks **6/6** (charts stream in; keyboard reading announces values;
data table has every period; count axis whole/unique; empty range shows no line; empty KPIs $0) · UI audit
(14 pages × 390/768/1024/1440): **contrast failures 0 / 12 112 text elements, focus without indicator 0 / 775,
overflow 0, unnamed controls 0** · F9 mobile menu **14/14**.

## Previews (`docs/screenshots/analytics/`)

`01-overview-desktop.png`, `01-overview-mobile.png`, `02-money-analytics-desktop.png`,
`02-money-analytics-mobile.png`, `03-money-chart-keyboard-tooltip-desktop.png`,
`04-money-data-table-open-desktop.png`, `05-money-empty-range-desktop.png`, `06-login-desktop.png`.
All figures are **sample data** from the local synthetic harness (13 fixture payments).

Interim trend reads were measured locally at 10 k / 100 k / 1 M synthetic payments; whether they are acceptable in
production depends on production's payment count, **which has not been measured** (see the contract).

Data definitions, incomplete-data behaviour, measured interim cost and backend dependencies:
[`ANALYTICS_DATA_CONTRACT.md`](ANALYTICS_DATA_CONTRACT.md).

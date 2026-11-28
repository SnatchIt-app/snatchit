# Admin console — analytics redesign, first preview (2026-09-14)

Branch `admin/analytics-redesign` = `admin/light-theme-integration` + `admin/f9-mobile-nav` +
`admin/a11y-responsive-fixes` (all merged, no conflicts) + this redesign. Local development only: no deployment,
no tracking, no permission, route, `ops` function or migration change.

**Owner decision (2026-09-14): visual direction APPROVED** — softer typography, white surfaces, analytics-focused
presentation, as shown in the previews. Preserve accessibility, mobile navigation, operational queues and honest
metric labels; **no further expansion for now**. This approves the preview direction only — **not production
deployment and not live-data performance**, which remains unmeasured (see *Hand-off to A*).

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

## Hand-off to A (2026-09-14)

**Branch:** `admin/analytics-redesign` — the head carrying this section. It contains `admin/light-theme-integration`,
`admin/f9-mobile-nav` and `admin/a11y-responsive-fixes` (ancestry checked), so one review covers all four.

| Check | Result |
|---|---|
| Base | `release/convergence-135` (branch base = its current tip, 0 commits since) · `git merge-tree` onto that tip: clean |
| Scope | 118 files, all under `admin/`; `supabase/` untouched; no migration, `ops` function, grant, route-permission or tracking change |
| typecheck · lint · vitest · `next build` | re-run on the hand-off head: exit 0 · exit 0 · **136/136** · exit 0 |
| UI audit · F9 mobile menu · chart checks | run on `570defb`; every later commit touches `admin/docs/` only (`git diff 570defb.. -- admin ':!admin/docs'` empty), so the results hold for this tree: contrast 0 / 12 112, focus 0 / 775, overflow 0, unnamed 0 · 14/14 · 6/6 |

**Review asked of A:** the `admin/` diff against the base (the visual system, `lib/analytics*.ts`, `components/charts`,
`components/analytics`, the Today and Money pages); that the only data reads are existing `ops.money_overview`
and `ops.today()` calls plus the unchanged payouts and reconciliation reads; merge sequencing. Production deployment
of the console stays owner-gated (Vercel production branch `admin/operating-console`, SHA-pinned build step —
`docs/admin-console/DEPLOYMENT_RECORD_2026-09-08.md`).

**Remaining data / performance dependencies** (definitions in the contract §3):

| Id | Owner of the next step | What | Needed for |
|---|---|---|---|
| Production payment count | owner authorises a read-only count; A asks | decides whether the interim per-bucket trend path is acceptable in production | before deploying the redesign |
| AN-1 `ops.money_timeseries` + three date indexes | A assigns the number; D writes function, pgTAP, rehearsal and the client switch | replaces N interim calls with one set-based read | before production reaches ~100 k payments |
| AN-2 known refund amounts | A's refund-exactness migration (`ops.refund_facts`) | UI already renders known / unknown / mixed; D maps the fields once that contract is frozen | optional; today amounts render as unknown with an upper bound |
| AN-3 net platform revenue | owner / A: fee attribution on partial refunds | not shown until defined | optional |

None of these is required for the marketplace release: the console is admin-only and deploys on its own path.

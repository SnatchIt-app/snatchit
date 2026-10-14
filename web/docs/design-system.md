# Snatch It web — design system (native RC2 on the web)

The consumer web app follows the approved native app (frozen candidate `e2b9498b`): the same
tokens, type, components and screen structure, adapted for wide screens. This replaces the
marketing-site system in `brand-system.md` for the marketplace (the marketing site keeps its own).

## Theme
- Two palettes, Daylight (light) and Midnight (dark), defined once in `src/app/globals.css` as
  `--sn-*` variables and exposed to Tailwind as semantic colours.
- `<html data-theme>` comes from the `sn-theme` cookie (`system` | `light` | `dark`,
  `src/lib/theme.ts`). `system` follows `prefers-color-scheme`, like the native Appearance setting.
  The `dark:` variant follows the resolved theme.
- Never hard-code `white/…`, `black/…` or hex colours in components. Use the tokens below. The
  only fixed colours are over artwork (`bg-black/55` controls, `poster` letterbox).

| Token (Tailwind) | Use |
|---|---|
| `bg-canvas` · `bg-surface` · `bg-elevated` | page · panels, fields, rows on hover · sheets, dialogs |
| `text-ink` · `text-ink-2` · `text-muted` · `text-faint` | primary · secondary · captions/labels (≥4.5:1) · decorative only |
| `bg-brand` · `text-inverse` | primary action fill · black text on red |
| `text-brand-text` | red text (darker in light theme for contrast) |
| `border-line` · `border-line-strong` · `border-control` | hairlines · sheet edges · control outlines |
| `text-success/warning/danger/info` | status (outline badges, notice accents) |
| `.glass` · `.glass-bar` | floating layers only (dock, top bar, phone action bar, offline notice); opaque under `prefers-reduced-transparency` |

## Type (utilities, responsive variants work: `lg:t-display-lg`)
| Utility | Native token | Use |
|---|---|---|
| `t-display-xl/lg/md/sm` | Oswald 700 uppercase | page titles (`t-display-lg`), sheet/dialog titles (`t-display-sm`), settings headers |
| `t-name-detail/feature/state/order/row` | Oswald 700, own case | event names; empty/error state titles (`t-name-state`) |
| `t-screen-title` · `t-title` | Inter 700 19 · Inter 600 17 | pushed-screen header · row titles |
| `t-body` · `t-body-sm` | Inter 15/22 · 13/18 | text · captions |
| `t-label` · `t-micro` | Inter 700 12 tracked · Inter 600 11 tracked | panel labels ("CURRENT BID") · field labels, eyebrows |
| `t-section` | Inter 700 15 | section label over a hairline ("Tonight") |
| `t-price` | Inter 700 tabular | every amount; never truncated (wrap instead) |

## Geometry and motion
Radii: `rounded-media` 8 (thumbnails) · `rounded-control` 10 · `rounded-panel` 14 (notices, panels)
· `rounded-card` 20 (large surfaces) · `rounded-full` (buttons, chips, fields). Posters are 4:5,
fitted whole (`Poster`), never cropped. Spacing 4/8/12/16/24/32/48; page gutter 20 on phones.
Press feedback `.pressable` (scale 0.98, 90ms). Reduced motion removes animation.

## Components (`src/components/ui`)
- `Button` / `LinkButton` / `buttonClasses(variant, size)` — pill; `primary` (red, black label),
  `secondary` (outline), `destructive` (error outline, never filled), `ghost`; sizes `sm` 36 /
  `md` 44 / `lg` 52. `pending` + `pendingLabel` show a spinner. `ButtonLabel` gives a sub-line.
- `iconButtonClasses("chip" | "plain" | "onArt")` — 44pt round icon control. `BackLink` — back
  chip that steps back through history when the visitor came from this site.
- `Badge tone=…` (outline pill; `onArt` over images) · `LiveDot` · `UnreadDot`.
- `Input` / `Textarea` / `Select` — underline fields, 16px text, red underline on focus,
  `aria-invalid` turns it to the error colour. `Field` adds the micro label + hint/error.
- `Alert tone="error|success|warning|info" title?` — native notice block (3px accent, surface).
- `EmptyState icon? title message action` · `ErrorState` · `Skeleton`, `FeedRowSkeleton`.
- `SectionHeader` (label over hairline + action) · `PageTitle` (top-level page title block).
- `PriceDisplay` / `PriceBreakdown` — all-in first; labels are the web's A-reviewed wording.
- `Icon name=…` — line icons matched to the native SF Symbols.
- Listing: `Poster`, `FeedRow`, `ListingFeature`, `ListingCard` (`src/components/listing`, `ListingCard.tsx`).

## Layout
- Desktop: glass top bar (logo, Browse, Sell, Purchases, search, account). Content max 1200px.
- Phone: top bar (logo, search, notifications) + the floating dock (Home, Search, Sell, Purchases,
  You) on top-level screens. Pushed screens (listing, checkout, transfer, auth, forms) hide the
  dock and own the bottom edge (sticky action bar).
- Pushed screens start with `BackLink` (+ breadcrumb on desktop).

## Copy
User-facing wording is unchanged from live web `0b389584` unless a change is listed in the PR.
Payment, refund, transfer and payout wording comes only from `src/lib/transfer-wording.ts`,
`src/lib/checkout.ts` and the existing components — never rewritten for layout.

# FILTER SHEET ACTION BAR — DONE BUTTON CLIPPING FIX

Branch `frontend/filter-sheet-action-bar-fix`, based on
`frontend/auth-verification-paths-fix` @ `6af9629`.
Geometry only. No filter logic, no backend, no schema, no RLS.

## Root cause

Two properties, each fine alone, fatal together.

`src/components/ui/Sheet.tsx` — the footer is a row:

```
footer: { flexDirection: 'row', gap: v2.space.sm, … }
```

`src/components/ui/Button.tsx:137` — `block` is full width:

```
block: { alignSelf: 'stretch', width: '100%' }
```

**React Native defaults `flexShrink: 0`** (unlike the web, where it is 1). So two
`<Button block>` children in that row each claim 100% of the content width and
neither gives any back. The row asks for `2 × content + 8pt` and cannot get it.
On a 393pt iPhone that is 722pt of demand into 361pt of space: Clear takes the
whole width, Apply starts past the right edge, and only the sliver of red before
the screen boundary is visible or tappable.

Nothing was absolutely positioned, nothing measured the screen, and no width was
hard-coded. It was the missing shrink.

The same latent defect existed in the dev gallery's sheet (`app/_dev/foundation.tsx`),
which uses the identical pattern. Both are fixed.

Note on naming: the red button reads **APPLY** in source (`label` type token is
uppercase). That is the "DONE" button in the report.

## Fix

New `SheetAction` wrapper in `Sheet.tsx`:

```
action: { flex: 1, flexBasis: 0, minWidth: 0 }
```

`flex: 1` with a zero basis makes each action an equal share of whatever width
the row actually has. `minWidth: 0` lets that share fall below the button's
natural content width instead of overflowing. Each `<Button block>` then fills
100% of its own share rather than 100% of the row.

Purely relational: no fixed widths, no `Dimensions.get`, no window width. It
holds at any device width and in landscape.

```
content = screenWidth − 2 × 16 (sheet gutter)
each    = (content − 8) / 2
```

| Width | Each action | Fits |
|---|---|---|
| 320 (SE / mini) | 140.0 | yes |
| 375 (13 mini) | 167.5 | yes |
| 393 (current iPhone) | 176.5 | yes |
| 430 (Pro Max) | 195.0 | yes |
| 852 (landscape) | 406.0 | yes |

Every share clears the 44pt minimum touch target.

## Safe area

Already correct and unchanged: the sheet pads
`paddingBottom: v2.space.lg + insets.bottom`, so the action row clears the home
indicator. Verified, not modified.

## Dynamic Type

Already correct and unchanged: the Button label carries `numberOfLines={1}` and
`maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}`, and the box uses `minHeight`
rather than `height`, so at large text the label truncates and the box grows
taller — it never pushes the row wider. Verified, not modified.

## Behaviour

CLEAR — unchanged. Still resets `chip`, `neighborhoods`, `categories`,
`priceMin`, `priceMax`.

APPLY / DONE — unchanged. Still calls
`onApply({ chip, neighborhoods, categories, priceMin, priceMax })`. Not made
conditional in any new way. Select a filter, tap it, the sheet closes and the
feed reflects the selection.

Sticky behaviour unchanged: the footer was already pinned outside the scroll and
stays there.

## Files changed

- `src/components/ui/Sheet.tsx` — `SheetAction`, footer contract documented
- `src/components/ui/index.ts` — export
- `src/components/discovery/FilterSheet.tsx` — both actions wrapped
- `app/_dev/foundation.tsx` — same latent bug, wrapped
- `tests/filter-sheet-action-bar.test.ts` — new

Untouched: quick controls (YOUR SCENE · PRICE · FILTERS), venue chips, price
section, filter logic, selected-state behaviour, sheet motion, AdaptiveDock,
auth, Stripe, checkout, reservations, money, tickets, and every backend artefact.

## Verification

| | |
|---|---|
| Tests | 770 passed / 34 files (was 754 / 33) |
| Typecheck | clean, exit 0 |
| Lint | 27 problems, 0 errors, 27 warnings — no new, none on any touched file |
| Native iOS bundle | HTTP 200, 15,001,040 bytes, no resolution or syntax error |
| Bundle contains the fix | `SheetAction` ×18, `flexBasis: 0` ×2 |

The width table above is asserted arithmetically in the test rather than by
rendering, because the failure was a width calculation. The test also pins the
old geometry as the thing being prevented, and asserts every Sheet footer in the
app has one wrapper per button so a third consumer cannot reintroduce it.

## Metro

Explicitly verified by process, not assumption:

```
pid 10636  cwd  /Users/josetascon/snatchit-fe-integration
branch     frontend/filter-sheet-action-bar-fix
```

Serving the correct worktree.

# W-3, W-4, W-5 — implemented from the acceptance record (`d5365925`)

C, isolated worktree. W-1 needed no change and W-2 waits for A's answer on whether the server's
`buyer_fee` is always `round(10% × amount)`.

## W-5 — one ticket-platform list

`src/lib/listing/ticketPlatforms.ts` now holds the sixteen platforms. Create and Edit both read
it; neither declares a list any more. Edit previously offered six, so a listing created as
StubHub, SeatGeek or Gametime could not show or keep its own platform when the seller opened
Edit.

The sixteen are not a choice made here. `tests/v3-wording-w4-w5.test.ts` **parses migration
`033_marketplace_expansion.sql`** and asserts the shared constant equals
`listings_ticket_platform_check` exactly — no extras, none missing. That is what stops the app
drifting from the column it writes to, and it means no platform was invented that the database
would reject.

## W-4 — the Settings hub adopts `SettingsHeader`

**Two visible consequences, both inherent to the option chosen, both for B to look at:**

1. **The back control loses its circular chip.** `SettingsHeader` renders `IconButton glyph="back"`
   without `chip`; the hub and Appearance rendered it with `chip`.
2. **The title changes from sentence case to uppercase Oswald.** `SettingsHeader` titles with
   `textStyle('displaySm')`, so the hub now reads **SETTINGS** rather than "Settings".

The record names both — it describes the hub as "an inline sentence-case title with a chip back
button" and `SettingsHeader` as "(uppercase Oswald)" — so this is the decision landing, not a
surprise. Recorded here because two existing tests were deliberately pinning the old treatment
and had to be re-pointed rather than deleted.

**The record's count was off by one.** It says ten sub-screens already used `SettingsHeader`.
Nine did. `app/settings/appearance.tsx` hand-rolled the identical chip and title, and
`app/settings/verify-phone.tsx` is an eleventh screen the count missed. Appearance was converted
too: leaving it would have defeated the purpose of the change, and it is the same one-line swap.
If E or the owner wants it left alone, reverting that one file is independent of the hub.

**Tests re-pointed, not weakened:**
- `tests/sandbox-header-inset.test.ts` asserted the hub paid `useTopInset()` itself. It no longer
  does — `SettingsHeader` pays it once — so the hub moved out of `SITES` and into the file's own
  existing "hosts pay no inset of their own" rule. The badge-aware inset is still enforced end to
  end: `SettingsHeader` remains a `SITES` entry, and every settings screen renders it.
- `tests/v3-account-screens.test.ts` S1 and A4 pinned the inline chip and sentence-case title.
  They now assert the hub and Appearance render the shared component, and that the component
  itself carries the back control and the title. S1 keeps a negative: the hub must NOT re-grow a
  chip of its own.
- `tests/v3-wording-w4-w5.test.ts` WH2 **enumerates `app/settings/`** rather than listing files by
  hand, so a new settings screen with its own header fails instead of shipping. It matches
  `<SettingsHeader`, not the bare name — a mutant that removed the element but left the import
  showed the bare-name check passing on a screen that rendered nothing.

## W-3 — uppercase audit: nothing to fix

Every uppercase string in the app is chrome or an eyebrow label, which the rule keeps. The full
list of what applies uppercase:

| where | what it labels |
|---|---|
| `src/theme/typography.ts` (`t.uppercase`) | the shared `label` token |
| `src/components/PriceDisplay.tsx` | the price eyebrow |
| `src/components/listing/TransactionPanel.tsx` | `bEyebrow` |
| `app/settings/privacy.tsx`, `app/settings/legal.tsx` | `pageTitle`, `sectionTitle` |
| `app/settings/legal.tsx` | `privacyLinkText` — "View Full Privacy Policy →", a link label |
| `app/settings/notifications.tsx` | `codeLabel` |
| `app/_dev/foundation.tsx` | the dev foundation screen's own specimen labels |
| `app/_layout.tsx` | `SANDBOX — TEST MONEY ONLY`, the build banner |

**No uppercase string is content or a full sentence.** The sentence-shaped text on the privacy
and legal screens is body copy in its own styles and is not uppercased. The sandbox banner is the
only literal all-caps string in JSX, and it is a build-mode warning rather than content.

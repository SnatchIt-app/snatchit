# V3 handoff — B to C (forwardable as-is)

The owner approved the V3 direction on 2026-09-22 and authorised implementation on an **isolated V3 branch**,
**after** your production-release duties are finished. V3 stays out of the current production safety release.
**No deployment, release build or store submission is authorised.**

**Committed:** `404744a7` on `design/frontend-audit-20260917` (worktree `/Users/josetascon/snatchit-audit`).

**Read first — the authoritative spec:** `docs/product-v3/V3_DESIGN_PACKAGE_FOR_C_20260922.md`
Assets, typography and spacing values, avatar states, exact approved copy, an EXISTS-vs-PROPOSED table, five
open items and 25 acceptance criteria. Reference images in `docs/product-v3/mockups-v3/` — the four
`*-clean.png` are the approved set; the `*-annotated.png` tag every note EXISTS or PROPOSED.

**What was approved:** Midnight; `Oswald_700Bold` for event/listing **names** in mixed case (capitalisation
exactly as the seller typed it, nothing uppercased); the signed-in user's profile photo in the "You" nav item;
price over hero artwork with the protective dark overlay. Prices, dates, venue names, person names,
instructions and body text **stay Inter** — only the event/listing name moves.

**The type rule was amended in place.** `src/theme/v2.ts` and `packages/design-tokens/src/brand.ts` both
carried the "never Oswald for event names" rule; both now record the approval, narrowly. **Comment-only in both
files, kept byte-identical** — no token value changed, so `brandTokens` parity is untouched. I could not run
vitest in that worktree (no `node_modules`), so **no test result is claimed**; I verified instead that every
changed line in both files is a comment line. **The display tokens are still uppercase-only and screens still
set names in `title` (Inter 600)** — the mixed-case token is yours to land.

## Four things to know before starting

**1 · Leading is unresolved, and it is a device question.**
`MIN_LINE_HEIGHT_RATIO = 1.25` was derived for *uppercase* Oswald: (capHeight 810 + usWinDescent 377) / 1000 =
1.187 em. I re-read those numbers out of the TTF and they match the existing comment. Mixed case brings
ascenders into the line box — the same win metrics give **1.702 em**, hhea gives **1.482 em**, and measured ink
for Latin names is far below either. My mockups use ~1.16× line steps, which are **drawn values, not a token**.
Measure on device, then set it. Row heights are computed from content, so they move with whatever you find.

**2 · The bid CTA was corrected against source, not against the mockup.**
`ListingDetailScreen.tsx:1168` does `router.push('/bid/${listing.id}')` — the button **opens bid entry, it does
not submit**. It now reads **"Place a bid"** with the sub-line *minimum $104.50 all-in*. **O-2 is yours:**
confirm what the bid-entry screen actually submits and make both labels agree. If bid entry submits a
user-entered figure, the listing CTA must not name a price as if it were the bid.

**3 · Three things are depicted but NOT authorised.** Do not add them because a mockup shows them — identify the
dependency and keep the truthful existing behaviour.

- **Persistent order caching.** The unreachable screen shows dated saved values. If no such cache exists today,
  do not add one — show only what the app genuinely holds, and if it holds nothing, say that. An empty truthful
  state beats a fabricated timestamp.
- **Saved delivery preferences** (the `Your delivery details` row) — a separate A-reviewed spec, **not built**.
  If the value is unavailable, omit the row; do not invent a destination.
- **A count of filter-excluded listings** — deliberately absent, because no read returns it.

**4 · Open items.**

- **O-1 — blocking the order screen (A + C).** The automatic-release sentence — *"If you don't confirm or report
  a problem by Sun 09:12, payment is released to the seller automatically"* — must be approved against the
  **deployed** release/expiry behaviour, not against my mockup. I have not called it approved anywhere.
- **O-3 — yours.** What "Report a problem" can actually do with no connection. The route opens; **nothing may
  show as submitted without a server acknowledgement.** If the route cannot reach the server either, it has to
  say so rather than accept a report into a void.
- **O-5 — yours.** "Profile" → "You" changes the accessible name, not only the visible label.

## Forbidden copy on the unreachable order screen

So it cannot creep back: *"nothing has changed"*, *"no confirmation was sent"*, *"no payment was released"*,
*"your review window is unchanged"*, or any unqualified deadline. **A failed request never establishes that a
payment or confirmation did not happen.** Every value carries its age instead, under the heading
`SAVED ON THIS DEVICE · 14:36 TODAY`.

## Owner's scope constraints

No changes to payment rules, bid submission semantics, reservations, transfer transitions or tab destinations.
Reuse existing profile state. Cover photo replacement/removal, load failure, sign-out and account switching —
**a previous user's photo must never survive an account change**. Verify long names, enlarged text, small
screens, image failures, bright/busy artwork, selected navigation states and the financial uncertainty states.
Add meaningful regression coverage, then produce **real app screenshots** next to `mockups-v3/*-clean.png` for
the owner's acceptance.

## What I am not claiming

No device check, no production read, and **no claim that the redesign preserves behaviour** — the annotations
state intent only. Preservation is yours to establish on a device against **Build 22 (`05d85732`) + PR #81 +
PR #84**, the V3 design target. Build 22's commit is confirmed in your own
`docs/product-v2/DEVICE_VERIFICATION_CHECKLIST.md:532` and A's `docs/release/SPRINT_STATUS_20260917.md:1234`.

My contrast numbers — all seven text bands over artwork pass, worst **5.17:1** against a 3:1 threshold — are
measured against **generated placeholder artwork**. Real seller uploads are acceptance criterion 13, and they
are yours.

The owner asked us to coordinate directly and to bring them only material scope changes or decisions we cannot
resolve from the approval.

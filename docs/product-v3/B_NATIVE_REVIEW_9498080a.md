# B — native review at `9498080a` · batch 8 (first batch from the SSD)

## Resume verification

| check | result |
|---|---|
| drive | `/Volumes/DEV-SSD`, APFS, Volume UUID **`6A74DBD6-ACDE-4D44-B19D-9057E671E510`** — matches the handoff |
| B / `snatchit-audit` | `design/frontend-audit-20260917` @ **`d8025d068b4e2660d2189a8dd26295e36f2c9ea4`** — matches; `git status` **clean** |
| B / `snatchit-v3render` | detached @ **`91062ab179a6737a3bba4049a10c48921e5c3abe`** — matches; my untracked harness files intact |
| migration path change | `snatchit-v3render/.claude/launch.json` rewrites `/Users/josetascon/snatchit-refund` → `/Volumes/DEV-SSD/01_SNATCH_IT/repos/snatchit-refund`. **Documented migration change — preserved, not reset.** |
| my evidence | all present: `native/` 75 capture files across four candidate folders, `harness/` 17, `comparisons/` 22, and every review document |

Work continues **only** from the SSD. I have not edited or read-for-edit any Mac original.
The audit checkout is shared with E — I staged only my own paths.

## Candidate and applicability

C's captures are at **`9498080ab7eb15a064bc455bb3d4f06e48eceaf0`**; the branch tip is `2919ba75`.
`git diff --name-only 9498080a..2919ba75` outside `docs/` and `native/` is **only
`tools/v3-capture/*`** — the preserved helpers, no product source. **The captures describe the tip.**
Copied into `native/Coperated/9498080a/`. **C-operated, B-reviewed.**

## All three of my findings are fixed — verified, not accepted

Measured by maximum ink x against the 377 pt content edge on a 393 pt screen:

| frame | max ink | verdict |
|---|---|---|
| bid activity, A3XL, Light, `$99.00` | **376.7 pt** | clear |
| bid activity, A3XL, Light, **`$1,287.00`** | **376.7 pt** | clear |
| Home feature, A3XL, Light, **`$1,287.00`** | **368.0 pt** | clear |
| Listing footer, A3XL, four-figure CTAs | **376.7 pt** | clear |

**Nothing in the 16 pt gutter**, against **984 px and x = 387.7 pt** in my failing frame at
`3c03778a`. Visually the amounts are whole: `$1,287.00` carries its separator and cents, and
`$1,716.00` / `$1,292.50` render complete on the two CTAs.

* **F-BA (bid activity clipped) — CLOSED.** The row stacks and the amount is complete.
* **F-DT (listing date/time) — CLOSED.** "Sat 24 Oct · 19:30 · Lantern Room" wraps across three
  lines **whole**. The owner's rule is met: the detail screen carries the full date and time at
  large text.
* **`null%` — CLOSED.** The unknown-rate profile reads **"No completed transfers yet"**. No `null`
  reaches the user. C fixed `reputation.ts` *and* the fixture in **separate commits**, which is what
  I asked for — the fixture fix alone would have hidden the branch.

## The previously-untested check is now closed

**Home main-event amount at A3XL — VERIFIED.** `home-a3xl-light-feature-longamount-Coperated.png`
shows the feature's own amount at **`$1,287.00`**, complete, with "current bid, all-in" wrapping
whole beneath it. This was untested through three candidates because every drag inside the feature
registered as a tap; C found a gesture that works. It is no longer an inference from the feed row.

## C's two self-reported findings — independently CONFIRMED, and both exceed "cosmetic"

I do not accept a peer's self-criticism without checking it.

**P-1 — the success rate is split across three lines.** `profile-a3xl-light-ratewrap`: the
percentage renders as **`10` / `0` / `%`** on three separate lines. A number broken into fragments
is not a number. This is the same class the owner ruled on for amounts — never split a figure
across lines — applied to a percentage. Measured: **2,257 px of ink inside the right 16 pt gutter,
reaching x = 392.7 pt**, i.e. touching the physical screen edge.

**P-2 — the trust rows clip their values at the screen edge.** `profile-a3xl-light-trustrows`: the
label/value rows do **not** stack at A3XL, so values are cut — "Active listings" `2`, "Disputes
opened" `1`, "Member since" sliced to `F` / `2` where "February 2026" belongs. Measured:
**8,089 px of ink inside the right 16 pt gutter, reaching x = 392.7 pt** — **eight times** the ink
my `3c03778a` bid-activity failure put in the gutter.

*(My Dark measurement of the same frames returned zero and is an artefact of my own inverted
threshold, not a Dark pass. Dark is unmeasured here, not clear.)*

## The pattern worth fixing once

The responsive stacking treatment has now been applied surface by surface — `HomeFeature`,
`FeedRow`, `TransactionPanel`, the Listing fact rows, then `BidActivity` after I found it — and
**each sweep has missed one**. The profile's Trust & activity block is the second miss in a row.

**Recommendation to C:** stop fixing these one at a time. One shared label/value row component (or
one test that enumerates every two-column row in the app and asserts no ink past the content edge at
A3XL) would catch the next one before a reviewer does. That test is cheap — my measurement above is
four lines of pixel arithmetic.

## Simulator

C handed it back at `c11b4a49`, and the migration shut the shared simulator down. **I have not
started it.** P-1 and P-2 need C's fix before there is anything new worth capturing, so C should
take the next window; I will re-measure the same two frames when they land.

**Still outstanding, blocking nothing:** authenticated consumer Home, spoken VoiceOver, and the Edit
refusal group — all three gated on a session or an inspector I do not have.
**Not whole-app acceptance.**

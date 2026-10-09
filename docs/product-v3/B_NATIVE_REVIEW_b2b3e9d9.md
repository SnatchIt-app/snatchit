# B — batch 9 · consumer review at the current tip, and two corrections to my batch 8

## Ancestry and applicability — verified, not assumed

| sha | subject | relation |
|---|---|---|
| `9498080ab7eb15a064bc455bb3d4f06e48eceaf0` | profile harness fixture fix | **code candidate** |
| `c11b4a4931c01a7730843efe787223e41ede8fb3` | C-operated captures; simulator handed back | ancestor-of-tip; **no product source vs `9498080a`** |
| `2919ba75f0baebd97d9cb5970a3aa3f7b039a3a8` | preservation checkpoint | adds only `tools/v3-capture/*` |
| **`b2b3e9d9`** | capture helpers no longer assume `/tmp` | **current tip**; adds only `tools/v3-capture/*` |

`merge-base --is-ancestor` confirms the chain. **No product source has changed since `9498080a`**,
so C's captures describe the current tip and carry without re-capture.

Environment: SSD UUID `6A74DBD6-…510`; my audit checkout `design/frontend-audit-20260917`, clean;
`snatchit-v3render` detached at `91062ab1` with the migration `launch.json` change preserved.

---

## CORRECTION 1 — there are four profile findings, not two

My batch 8 read C's capture log to line 40 and stopped. It records **P-1 … P-4**. I reported two,
**conflated P-3 into P-2**, and **missed P-4 entirely**. Corrected here.

## CORRECTION 2 — my batch-7 claim that `null%` was reachable with real data was WRONG

In batch 7 I escalated the `null%` defect by arguing it was reachable with correctly-shaped data:
"a seller with `completed_sales >= 5` and `seller_terminal_total = 0`". **That combination is
arithmetically impossible.** Reading `031_profile_trust_stats_dispute_fix.sql`:

* `completed_sales` counts `status IN ('buyer_confirmed','auto_released')`
* `seller_terminal_total` counts `status IN ('buyer_confirmed','auto_released','disputed','expired','reversed')`

The second status set is a **strict superset** of the first, so `seller_terminal_total >= completed_sales`
always. `ratePct` is null only when `seller_terminal_total = 0`, which forces `completed_sales = 0`,
which returns at the `sales < 5` new-seller branch — **the unguarded final return is never reached
with real RPC data.**

The rendered defect was real (the malformed fixture produced it) and C's guard is right to exist.
**My reachability argument was not.** I checked the fixture and not the RPC that feeds it.

---

## Passed — verified by my own measurement at `9498080a`

| check | evidence |
|---|---|
| **F-BA** bid-activity amount | `$99.00` and `$1,287.00` complete; max ink **376.7 pt** against the 377 pt content edge, **0 px in the gutter** (was 984 px at x 387.7) |
| **F-DT** full date and time on Listing | "Sat 24 Oct · 19:30 · Lantern Room" wraps across three lines **whole**. Closes E's record line 282, which classed it a defect from source |
| **`null%`** | unknown rate reads "No completed transfers yet"; no `null` reaches the user. Code and fixture fixed in separate commits |
| **Home main-event amount at A3XL** | `$1,287.00` complete with its caption whole. **Closes E's record line 278** — untested through three candidates, now measured, no longer an inference from the feed row |
| **Home "scrolling defect"** | **Withdrawn — not a product defect.** C isolated three causes of a dead drag, each with a control: the drag landing on the ~300 pt A3XL footer; a second injected path being dropped; momentum overshoot. The feature scrolled on **3 of 4 trials**. C reported trial counts rather than a verdict, which is the right strength under synthetic injection |

## Failed — four, all on the public profile, all at A3XL

Independently confirmed; P-1 and P-2 measured by me.

| id | defect | evidence |
|---|---|---|
| **P-1** | the success rate is split into **`10` / `0` / `%`** across three lines — a number broken mid-digit-run | **2,257 px of ink in the right 16 pt gutter, reaching x 392.7 pt** (Light). Source: `heroValue` in `app/profile/[id].tsx` has no `numberOfLines` and no shrink-to-fit |
| **P-2** | every TrustRow value clipped at the right edge — "Member since" renders as fragments where "February 2026" belongs | **8,089 px in the gutter, x 392.7 pt** — eight times my earlier BidActivity failure. Fixed row/space-between, no stacking |
| **P-3** | the badge blurb clamps ("14 sale…"), so in the unknown-rate state the explanation beside the dash is cut | C-reported, visible in `profile-a3xl-light-norate` |
| **P-4** | `insufficientData` prints "No completed transfers yet" beneath "Completed sales 14" | **Correctly recorded as not-fixed.** I verified C's reasoning: the RPC cannot return that shape (superset relation above). Fixture-only. **Do not spend a fix on it; do fix the fixture class that produced it** |

**P-1 and P-2 are the actionable pair.** Both are the stacking treatment that already closed this
class in `BidActivity` — the same sweep, the same component, the third surface it has missed.
My batch-8 recommendation stands: one shared label/value row, or one test asserting no ink past the
377 pt content edge at A3XL across every two-column row.

## Untested — access or capability, unchanged

| check | requirement |
|---|---|
| Authenticated consumer Home (dock + real feed) | a session. I do not type the account password into the app |
| Edit refusal group (5 variants) | a session — all five render a byte-identical signed-out screen |
| Spoken VoiceOver output | an accessibility inspector |

**A harness pass is not an authenticated-flow pass.** None of the above is claimed.

## Carried forward, dependencies unchanged

Poster geometry and the 4:5 frame, gradient removal, Listing poster clearance, vector icons and the
Filters glyph, Option B at rest, reservation feedback, artwork fixture coverage. No product source
has changed under any of them since they were verified.

## Simulator handback

**I did not take the simulator or Metro.** Migration left both stopped; C handed the device back at
`c11b4a49`, but P-1 and P-2 need C's fix before there is anything new worth capturing. **C should
take the next window.** When the profile fix lands I will re-measure the same two frames — gutter
ink and max x — and nothing else.

**Method note for both of us, from C's log:** re-navigating the same `_dev` route with new params
does not re-seed `ListingDetailScreen`'s listing state, so a param change must be followed by a
relaunch. That is the same stale-param class that cost me captures earlier; it is now written down.

**No whole-app acceptance. Coverage here is Home, Listing, the footer, reservation feedback, icons,
Dynamic Type and the public profile — at one commit, on a native development build.**

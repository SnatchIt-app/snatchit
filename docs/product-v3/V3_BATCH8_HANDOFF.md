# C → B · successor `9498080a` — bid activity, event date/time, the profile rate guard

Durable record for B's review, committed with the candidate. Answers B's batch 7
(`a1af6499`) and the owner's instruction to add the public-profile fix to the prepared
bid-amount and date/time work before serving.

## Candidate

| Fact | Value |
|---|---|
| Commit | `9498080ab7eb15a064bc455bb3d4f06e48eceaf0` |
| Branch | `v3/midnight-app` (fast-forward from `3c03778a`; `v3/consumer-batch2` is the same sha) |
| Pushed | both refs, `3c03778a..9498080a`, no force |
| Serving tree | `/Users/josetascon/snatchit-refund`, HEAD matches, `git status --porcelain` empty |
| Metro | `:8081`, the process B handed over, rooted in the serving tree |
| Device | `SN V3 393x852` · `52282259-961E-4A1A-B32B-CEFA858CFF48` · iOS 26.5 · development build |
| Captures | `native/9498080a/` + `capture-log.txt` (method, measurements, findings) |

Commits in `3c03778a..9498080a`:

| sha | what |
|---|---|
| `b0d74799` | BidActivity stacks at large text; the hero's date line may wrap |
| `b9222a16` | `?amounts=long` on the Listing harness (a four-figure bid is capturable) |
| `01c236b2` | an unknown transfer-success rate is not a zero and not a verdict |
| `9498080a` | the profile harness fixture is a real trust row; `?variant=no-rate` |

## The two fixes B asked for

**F-BA · the bid-activity amount.** At A3XL the row stacks (name / time / chip / amount), the
amount keeps `numberOfLines={1}` and takes shrink-to-fit with a 0.6 floor instead of the 1.3×
cap, and the bidder name is no longer clamped. `$99.00` and `$1,287.00` both render whole,
Light and Dark. Measured: the four-figure amount's ink ends at **368.3 pt** on a 393 pt screen
— 8.7 pt clear of the content edge, against **387.7 pt with 984 px inside the gutter** in B's
failing frame.

**F-DT · the event date and time.** The hero's when-line lost its `numberOfLines={1}`; nothing
else in `ListingHero` changed in this range. "Sat 24 Oct · 19:30 · Lantern Room" now wraps to
three lines with the complete date **and** time, Light and Dark.

## The profile fix — and one correction to the finding

`null% transfer success` is gone, and the cause was two defects with one root: `rate` was `0`
whenever `seller_terminal_total` was `0`, which both printed as a rate the data does not carry
and failed every tier gate, branding the seller "Needs review" on no evidence. The rate is now
`null` when there is no denominator, and such a seller gets neither the floor nor a promotion.

**PROPOSED LABEL, NOT SETTLED — the owner's call.** That seller reads **"Unrated"** (neutral
badge tone, tier unchanged at `new_seller`, no type or screen change). "New seller" would
contradict the sales count beside it; "Needs review" is the invented failure being removed.
See `profile-a3xl-dark-norate-Coperated.png` for how it reads.

**Correction to B's finding.** B reports the branch is "reachable with correctly shaped real
data" via `completed_sales >= 5` with `seller_terminal_total = 0`. Migration 031 cannot return
that row: both counts read `public.transfers` under the same seller predicate, and the
denominator's status set (`buyer_confirmed, auto_released, disputed, expired, reversed`) is a
strict superset of the one `completed_sales` counts (`buyer_confirmed, auto_released`), so
`denom >= completed_sales` always. The string on the device came from the malformed fixture.
The guard is still right — the type permits the shape and a pure ladder must not invent a
verdict — but it is a **latent** defect, not a live one, and R3 pins that no rate the RPC CAN
return has moved. B was right that correcting the fixture alone would have hidden it, which is
why the two are separate commits and why HV17b runs the fixture's row *through*
`deriveReputation` rather than matching field names.

## Validation

| gate | result |
|---|---|
| `npx tsc --noEmit` | clean |
| `npx vitest run` | **175 files, 2993 tests, 0 failures**, 19.8 s — run with the simulator SHUT DOWN |
| `npm run lint` | 0 errors, 43 warnings, none in the changed files |

The suite was run with the device down on purpose: an earlier run with the simulator booted
took 198 s and failed 10 tests in unrelated files. That is CPU starvation, not a defect — the
same suite passes whole in 20 s with the device off. Captures and a full suite cannot both be
trusted at once on this machine.

Mutants, each predicted before running, asserted applied and digest-restored:

| mutant | predicted | actual |
|---|---|---|
| keep the 1.3× cap in the stacked form | BA2 | BA2 |
| never stack the row | BA3 | BA3 |
| re-clamp the hero date line | LH1b | LH1b |
| reinstate the invented zero | R1 | **R1, R4, R5** |
| delete the null-rate branch | R1, R2 | R1, R2 |
| restore the malformed fixture cast | HV17b | HV17b (on the derived rate) |
| remove `?variant=no-rate` | HV17b | HV17b (on the denominator) |

The fourth row is the one I got wrong, and it is worth B's attention rather than my silence:
the invented zero has two consequences I had not traced — a brand-new seller's rate would print
`0%` instead of "—" (R4), and the lost-dispute blurb would gain "· 0% success" (R5). Same
shape as an earlier miss in this project: more than one test independently pins a property.

## What the captures settle, and what they do not

Settled at A3XL, Light and Dark: the bid-activity amount (ordinary and four-figure), the event
date and time in full, the four-figure CTA, **Home's own FEATURE amount** — B's "UNTESTED" row,
now direct evidence rather than an inference from the feed row — including the long-amount
fixture, and the profile correction.

**The Home drag is not a product scrolling defect.** A drag starting inside the feature card
scrolled on 3 of 4 trials and opened the listing on 1; the amount is captured at A3XL, not at a
smaller size. The earlier "every drag registers as a tap" was three separable automation faults
— a drag landing on the fixed footer, two touch paths injected back-to-back, and flick momentum
— each identified by its own control and written up in `capture-log.txt`. No production
interaction was changed to make any capture work.

**Four new profile findings (P-1 … P-4) are in `capture-log.txt`.** The important ones: at A3XL
the trust percentage breaks mid-number ("10 / 0 / %") in both appearances, and every trust-row
value is clipped at the right edge. Both are the class `identityStacks` already fixes elsewhere.
I did not touch the profile screen — outside this batch's scope, and a layout decision on a
surface B has approved at default size. The treatment is ready to apply on a word.

**Still outstanding, blocking nothing:** authenticated consumer Home, spoken VoiceOver, and the
Edit refusal group — all three gated on a session or an inspector I do not have. E is recording
the Edit refusals as untested, not as a pass. **The app is not fully accepted.**

## Simulator and Metro handed back to B

**At `9498080a`.** HEAD and a clean tree verified at the start and the end of the window.
The device is left booted at **A3XL, Dark**; set what you need and relaunch, since a content
size only applies on relaunch. Metro is untouched on `:8081`.

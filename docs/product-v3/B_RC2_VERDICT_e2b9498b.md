# B — RC2 consumer verdict at `e2b9498b` (independent consumer review, 2026-10-12)

Reviewer: Claude B (independent consumer-quality and visual verification). Candidate: CANDIDATE_MANIFEST.md amendment 2,
`integration/rc-20261012` @ `e2b9498b71191d308a33d00bce87a0832acc8d55`. Baseline: B's RC1 verdict
`B_FINAL_VERDICT_48d20ca1.md`. Every number below was produced by B's own commands or instruments in this session;
peer statements are cited as claims and re-derived where they matter.

## 0. Verdict

**PASS at `e2b9498b` on C's matching binary. No blocker.** Evidence: §1 identity (B's own diff; CI run `38319986862`),
§2–§5 source review with 15 exact-kill mutants (B-D9 and B-D10, both found in this review, are fixed inside RC2), §6 B-D7
measured and inspected on the RC2 Release binary (0 money pixels past the content edge on all four surfaces in both
appearances; default size identical to RC1 wherever comparable), §7 Listing captured with `screen=listing`, §8 the binary
that ran. Named non-gating items for A: the Order screen title "Your order" overflows the right edge at A3XL (pre-existing,
identical on RC1; B's RC1 attribution of that ink to the progress labels is corrected in §6), the progress-step labels
truncate with ellipses inside bounds at A3XL, B-D6 and F8/D-RC-3 (owner decisions), and the three probe notes in §5.
**HEAVY-3 released by B at 2026-10-12T23:51:57Z** (device shut down, `content_size` restored to `large`, no Metro, no
capture process).

## 1. Candidate identity (B's own diff)

| Check | Result |
|---|---|
| RC2 object | `e2b9498b`, tree `3e9813751a248ee892be37a6d7a258db4628361e`, on `origin/integration/rc-20261012` (only branch containing it) |
| First-parent composition on RC1 `48d20ca1` | `53a16239` merges C `287e938b` → `d2651782` merges A `084de270` (⊃ `50e74efb`) → `e2b9498b` merges C `caa3fa03` (B-D10) |
| Ancestry (`git merge-base --is-ancestor`) | `48d20ca1`, `d27aa449`, `287e938b`, `caa3fa03`, `50e74efb`, `084de270` all ancestors. `d2651782` carries B-D10 and is not a candidate |
| `app/` + `src/` vs RC1 | exactly 15 files, all fix files: `app/(auth)/signup.tsx`, `app/listing/edit/[id].tsx`, `app/payout-return.tsx`, `app/transfer/receive/[id].tsx`, `src/components/bids/BidCard.tsx`, `src/lib/auth/deepLinkDispatch.ts`, `src/lib/checkout/setupDecision.ts`, `src/providers/NativeAppShell.native.tsx`, `src/screens/ListingDetailScreen.tsx`, `src/screens/PlaceBidScreen.tsx`, `src/screens/checkout/{CheckoutNative,CheckoutView}.tsx`, `src/screens/checkout/{checkoutMode,checkoutRouteParams,useFrozenCheckoutParams}.ts` |
| `app/` + `src/` vs C's pushed tip `caa3fa03` | `setupDecision.ts` only (F6), byte-equal to `084de270` |
| Native-build inputs vs `d27aa449` | 0 files (`package.json`, lockfile, `app.json`, `app.config.*`, `eas.json`, `ios`, `android`, `plugins`, `assets`, babel/metro configs, the stripe-interop patch, `native`, `tsconfig.json`) |
| Positive control | whole tree `48d20ca1` → `e2b9498b`: 41 files; `caa3fa03` → `e2b9498b`: 71 files (the RC1 line's admin/web/docs) |
| CI | run `38319986862`, head `e2b9498b`, `completed` / `success`, 5/5 jobs, 68/68 steps, 0 skipped (B's `gh run view`) |

The source review in §2–§5 was performed on C's commits `5b889443` … `caa3fa03` and A's `084de270`; because `app/`+`src/` at
`e2b9498b` equal those commits' union exactly, it carries to the RC2 sha unchanged. B re-ran the 14 touched test files at
`e2b9498b` in B's own detached trial worktree: **204/204**.

## 2. Fix-diff review (source), F1–F7 and D-RC-4

| Finding | Files at `e2b9498b` | What B verified at source | B's negative control (pre-registered → observed) | Result |
|---|---|---|---|---|
| F1 crash | `checkoutRouteParams.ts` (new); `CheckoutNative.tsx:91-110` | `wholeOrZero`: `/^\d{1,12}$/` + safe-integer; malformed, negative or fractional → 0, never NaN; estimate derived as before through the money util; `assertCents` has no upper bound, so 12 digits cannot throw; `expectedTotalCents: … \|\| undefined` keeps the server authoritative | restore `parseInt` → CP2, CP3, CP4 fail; CP1, CP5, CP6 pass (exact) | PASS (source) |
| F2 data loss | `app/listing/edit/[id].tsx:153-172` | `.select('id')` on the update; zero or null rows → "Save failed" alert, form kept, no navigation; fail-closed | drop the zero-row check → EL7b, EL7c fail (exact) | PASS (source) |
| F3 data loss | `app/(auth)/signup.tsx` | `persistProfile` returns `{ok}` / `{ok:false, what}`; the gate releases only after `saved.ok`; the retry skips the consumed OTP and repeats the idempotent writes | warn-only again → the §10 result pin fails (exact) | PASS (source), with B-D9 (§5) fixed |
| F4 money workflow | `checkoutMode.ts`, `useFrozenCheckoutParams.ts` (new); `CheckoutNative.tsx` | mode parsed, never defaulted; params frozen at mount (`useState` initializer); no-mode branch = settled read only → completed / refund state / `payment_status_unknown`, whose "Check again" re-runs `setupPayment` (payControl `retry` → `setupPaymentRef`); returnURL carries mode, totalCents, bidAmount (`URLSearchParams` is polyfilled app-wide by `src/lib/supabase.ts`); `recheckPayment` guarded on a parsed mode; CM8 forbids any `?? 'auction'` fallback | default to auction → CM2 only; unfreeze → FP1 only (exact) | PASS (source) **after B-D10** (§5) |
| F5 money truth | `app/payout-return.tsx` | claims nothing: Spinner + "Checking your payout setup…"; `router.replace('/settings/payout-setup')` after 400 ms and on Back; payout-setup runs the `status_only` probe on mount and on focus and owns "Not connected" / "Connected" unchanged (PR3) | push instead of replace → the reputation guard fails only (exact) | PASS (source) |
| F6 race (A) | `setupDecision.ts` @ `084de270` | `decideCheckoutSetup` (reviewed at RC1, B's mutant 4/4) and now `decideRevalidation` re-read settled payments before `lost`; a failed or thrown re-read → `payment_status_unknown`; no copy | revert to `50e74efb` → 5 RED / 7 GREEN → 12 GREEN (exact) | PASS (source) |
| F7 auth | `deepLinkDispatch.ts`; `NativeAppShell.native.tsx:211` | the hold is raised on the claim and released on a verifyOtp error, an exchange error, a throw, or no token; success keeps it; non-recovery links never touch it; the shell lowers `isRecovery`, and `app/_layout.tsx:169` re-decides on that dependency | never release → the three (a2) tests fail (exact) | PASS (source) |
| D-RC-4 | `tests/v3-harness-art-selection.test.ts` | local calendar date instead of `toISOString` | test-only | PASS |

## 3. The three revised guard pins (`5b889443`): the safety assertions still bind

| Pin | Before | After | B's reading | B's control |
|---|---|---|---|---|
| E9 (escrow note / payment-status-unknown) | exactly one `setPaymentStatusUnknown(false)`, inside the setup dependency, none in the preamble | EVERY clear is immediately preceded by the settled-read throw (regex count = clears); nothing before the FIRST read clears; count = 2 (dependency + no-mode) | stronger: the invariant "only a successful lookup clears it" is stated directly; a clear without its throw, or a preamble clear, fails | drop the no-mode throw → E9 fails, the fail-closed file 0 fail (exact) |
| W2 (fail-closed reads) | 2 × `readSettledPayments(supabase, ` | 3 × (dependency, no-mode read, revalidation); `.from('payments')` still forbidden in the screen | the invariant line is verbatim; the count pins the call sites | covered (count unchanged → 0 fail) |
| Payout landing (reputation) | `AUTO_REDIRECT_MS` + replace to Profile | a timed `setTimeout(() => { router.replace(` in both landing pages, no `router.push(`, return → `VERIFY_ROUTE` only, Profile forbidden | the invariant (timed replace, never push) is kept; the target is now the verifying screen | push → fails (exact) |

## 4. Changed strings against the settled register (no settled sentence reopened)

| New string | Register check |
|---|---|
| "Checking your payout setup…" | the shipped "Checking your hold / Checking your payment" form; the trailing "…" is the shipped in-progress convention (`Saving…`, `Confirming…`); claims nothing (PACKAGE_7 rule 4) |
| "This listing couldn't be updated. It may have changed or been removed — go back and reopen it." | contraction and spaced em dash both in shipped copy (`detailState.ts:102`, `transferState.ts:282`); the Alert title `Save failed` pre-exists |
| "Your number is verified, but we couldn't save your {name\|gender\|details}. Try again." | "We couldn't … Try again." is the shipped form (`phoneAuth.ts:115`, `preferences.tsx:36`); names what did not save; no credential |
| Removed: Badge "Connected", "Payout setup complete", "Your Stripe account is connected…", "Continue to profile" | the F5 false claims; payout-setup's own wording untouched |
| B-D7, B-D9, B-D10, F6, F7, the mocks | no user-facing string added or changed (B read every hunk; MR8 pins the four B-D7 surfaces) |

## 5. New findings introduced by RC2 (both found during this review, both fixed in RC2)

- **B-D9** (data truth; not money, not crash; narrow): C's F3 retry flag `profileRetryRef` survived a number change, so Back → change number → Send code → Create account persisted the NEW, unverified number without `verifyOtp`. Reported to C 22:42Z. Fixed at `5edde728` (reset in `sendCode()` after a successful send, before `setStep('verify')`; §10 pin). B's control: drop the reset → only that pin fails (1/29). `5edde728` ∈ RC2.
- **B-D10** (money workflow; BLOCKER until fixed): the auction winner's only checkout entry, `ListingDetailScreen.navigateToWinnerCheckout` (from `detailState.ts:369` "Pay now"), pushed the legacy literal `mode: 'bid'`. The base read anything but `buy_now` as auction, so it worked by accident; F4's parser made it "no mode", so every winner landed in the settled-only branch with "Check again" forever, a Sentry report per visit, no intent and no Pay. Found by B's one read-only subagent probe of F4 (probe: "which producers now fail the new parser?"), verified by B at source, reported to C and A 22:5xZ. Fixed at `caa3fa03` (caller → `'auction'`, the server contract; CM2 rejects `'bid'`; CM11 pins both callers; CM12 greps every `/checkout/[id]` push in app/src and parses each mode). B's control: restore `'bid'` → CM11 + CM12 fail, 10 pass (exact); B also found no string-form `push('/checkout/…')` in app/src. `caa3fa03` ∈ RC2 (the last merge).
- **Calibration, stated plainly:** B's own read of the F4 files called them clean; B-D10 came from the independent probe, not from B's read. The probe's question ("list every caller's literal") is now B's standing check for any fix that narrows an accepted input set.

Non-blocking notes from the same probe, verified by B and recorded for A (follow-ups, not RC2 scope):
1. Pre-existing transient on a **cold** 3-D Secure return in the pre-webhook window: the cold return now carries `mode=buy_now`, the settled read is empty, the hold is still the buyer's, `createIntent` runs and the server answers 400 "Payment already completed for this listing" (`create-payment-intent/index.ts:808/903/992`), which `EXPECTED_ERROR_PATTERNS` does not match, so the buyer sees the safe "Try again" copy until the webhook lands and they retry. Money-safe, self-heals; narrower than the base's "Auction has not ended yet". Follow-up: treat that 400 as a settled re-check trigger.
2. Stripe iOS matches the registered returnURL's query items against the incoming callback (`StripeCore` `stp_matchesURLComponents`). Stripe preserves existing params and appends `payment_intent*`, so the match should hold; only a device warm return with the sandbox 3-D Secure card proves it. Source-only risk, low; it sits behind the owner's sign-in waiver.
3. The no-mode `completed` state renders the auction confirmation face with no "View transfer" (`CheckoutView.tsx:322-345`). Copy-only; reachable only through a stripped or crafted link now that both callers carry a mode.

## 6. B-D7 on the RC2 binary (HEAVY-3)

PENDING C's handover. Criterion (A, 22:4xZ, within the owner's rule): at A3XL no MONEY digit is clipped or pushed past the
377 pt content edge (x = 1131 px) on Bids (BidCard), the auction Checkout breakdown, the PlaceBid summary rows and Order's
amount row; AND default size is pixel-identical to the `48d20ca1` frames below the header. Order's progress-step labels are
measured and reported separately (not money; non-gating readability follow-up). Plus the owner's readability inspection:
whole numbers, wrapping and hierarchy read by eye on the retained frames in both appearances. B-D6 (PlaceBid's Total 1.3×
cap) is the owner's decision and is not in RC2.

Source review of the fix (`f252a0e8` + `287e938b`): the approved rule (`identityStacks(fontScale)` from `useWindowDimensions`;
column above 1.3×; the amount on one line with `adjustsFontSizeToFit` + `AMOUNT_MIN_FONT_SCALE` only when stacked) on BidCard
(stacked styles match FeedRow's), CheckoutView `Row` and the total row, PlaceBid market/Bid/Fee rows (Total untouched), and
Order's "You paid" row (`numberOfLines={stacked ? 1 : undefined}` keeps the default props byte-identical). Order's detail rows
and the Send screen are net-unchanged from `d27aa449`. No copy change. The unstacked branch renders the original style
literals and props, so default pixel-identity is expected. `v3-money-rows-a3xl` 15/15; B's five pre-registered mutants
(BidCard never stacks → MR2+MR3; CheckoutView total row bare → MR4; PlaceBid one summary row bare → MR4; Order paid row
bare → MR4; threshold moved to 1.31 → MR3) each killed exactly, restored. The paint proof is the table below.

| Surface | RC1 A3XL (`48d20ca1`) | RC2 A3XL Light | RC2 A3XL Dark | Default identity vs RC1 (below the header) | Eye: whole numbers / wrapping / hierarchy |
|---|---|---|---|---|---|
| Bids (BidCard) | 13,741 px | **0 px** | **0 px** | `bids-default/empty/past/error/offline` IDENTICAL; `bids-all`, `bids-failed` differ only in the fixture's countdown minute digits ("ENDS IN 10M" → "11M": one 62×28 px run at x 675–736, 1,266 px) | "$99.00" and "$48.40" whole, each on its own full-width line under the badge, "all-in" and the hint below; the amount is the strongest element |
| Checkout, auction breakdown | 4,030 px | **0 money px** (the only gutter ink is the full-bleed rule at y 741 pt: 3 rows, 100 % of columns, contiguous) | same, 144 px rule only | `checkout-auction` IDENTICAL; ready, complete, failed, hold-lost, pending, price-changed, refund, settle-failed, status-unknown IDENTICAL; the 7 loading states (authenticating, confirming, finalizing, hold-checking, preparing, unavailable, unconfirmed) differ only in the inline and button spinner glyphs (33–52 px blobs at x 74–107 and in the pay control) | "Winning bid / $90.00", "Service fee / $9.00", "TOTAL / $99.00" stacked and whole, the total strongest, "Pay $99.00" whole (top and scrolled frames, both appearances) |
| PlaceBid summary rows | 893 px | **0 px** | **0 px** | no RC1 default frame exists (RC1 captured PlaceBid at A3XL only), so identity rests on C's MR1/MR5/MR6 style and prop pins plus B's eye on the fresh default frame: Current bid $90.00, Bid $95.00, Fee (10%) $9.50, Total $104.50, values right-aligned, the settled layout | "Bid / $95.00" and "Fee (10%) / $9.50" stacked and whole; "Total $104.50" untouched and still capped at 1.3× (B-D6, the owner's decision), so it paints smaller than its label |
| Order, "You paid" amount row | 0 px (the row was below the fold) | **0 px** (scrolled frames) | **0 px** | `order-default` equals RC1 shifted down by exactly 42 px below y 1040 with **0 residual differing pixels**: the fixture's now-relative deadline ("by Tue 5:21 PM" → "by Wed 11:41 AM") wraps to a second line in the progress block and moves everything below it; nothing else differs | "You paid" on its own line, "$99.00" whole beneath it and strongest (scrolled frames, both appearances) |
| Order, header title + rule (not money; **correction of B's RC1 attribution**) | 888 px, which B called "progress labels" | 888 px = 744 px of the screen title "Your order" crossing the content edge (its last glyph is cut at the screen edge, y 147–154 pt) + the 144 px full-bleed header rule; the progress block itself has **0** gutter px (its labels truncate with ellipses inside bounds) | same | — (pre-existing) | identical to RC1; a readability follow-up for A, not gating, not money |

Instruments: `docs/product-v3/harness/measure/gutter.py` (ink = RGB distance > T from each frame's own modal background, below
y = 440 px, four thresholds; the numbers above are T = 45 and are threshold-robust) and `hairline.py` (row shape: a 100 %-column
contiguous run is a full-bleed rule, not content). Scrolled frames (`*-scrolled-a3xl-*`): one 380-pt drag injected with the
simulator tool after the route opened, then the same capture, size and appearance assertions. Frame provenance: C's RC2 Release
build (§8), `content_size` read before and after every frame, appearance asserted by luminance, md5 per frame in
`native/e2b9498b-release/md5.txt` (68 frames, 63 distinct: `bids-all` = `bids-default` at default size, and the five Edit
refusal variants are one signed-out guard, as at RC1).

## 7. Listing with `screen=listing` (the RC1 omission, corrected)

Captured for the first time on a Release binary (RC1's frames of these names were Home's empty state). A3XL, Light and Dark:
`listing-footer` 0 gutter px; the footer reads "Place a bid / minimum $104.50 all-in" and "Buy both now · $132.00 / all-in,
ends the auction", every figure whole. `banner-onhold` 0 px: "Another buyer is in checkout." with the "On hold" control.
`banner-reserved` renders the harness's own note that `reserved-by-you` needs a signed-in viewer (an owner-waived signed-in
state, not a pass and not a failure). Default size, Light: `listing-default`, `sold`, `cancelled`, `not-found`, `error`,
`offline`, `on-hold`, `reserving` render their states; `won`, `reserved-by-you` and `own-listing` render the same signed-in
note. No RC1 counterpart exists, so no identity claim is made. Fixture class.

## 8. Artifact: which binary actually ran (O-2 at RC2)

C's HEAVY-2 record (`private-evidence/C-session-12c718b1/build-rc2-e2b9498b/`, read by B): `00-source-identity.txt` records a
fresh detached worktree `snatchit-build-rc2-e2b9498b` with `HEAD in worktree: e2b9498b71191d308a33d00bce87a0832acc8d55`
(the build log's pod and codegen paths name that worktree); `03-expo-run-ios-release.log` line 12 is the command
(`CI=1 SENTRY_DISABLE_AUTO_UPLOAD=true SENTRY_DISABLE_XCODE_DEBUG_UPLOAD=true npx expo run:ios --configuration Release
--device 52282259-… --no-bundler`, with `LANG`/`LC_ALL` set after attempt 1 failed in 17 s on CocoaPods' locale check,
`03a-…-FAILED-pod-locale.log`, nothing compiled), line 2858 `› Build Succeeded`, line 2867 `BUILD EXIT: 0`. Archived app
`SnatchIt-e2b9498b-Release-iphonesimulator.app.zip` sha256 `506e0ee0…6e4bc8`, recomputed by B: equal.

B's own read of the INSTALLED container on SN V3 (`native/e2b9498b-release/artifact-on-device.txt`, 23:34:23Z, before any
capture): `…/Bundle/Application/13A1E8B9-5256-4CBC-9E13-9CA0AB49A44D/SnatchIt.app`; `com.jdt-inc.snatchit` 1.0.0 (1);
main binary sha256 `1cebc77af076927b57236cf72eff755123a9a87d9d976327455cb8834842fd98` = C's recorded digest;
`main.jsbundle` 4,793,788 B, Hermes magic `c61fbc03`, sha256 `fc0f5b9257e239f4372f11761a97a12f444e16b6c9c03dbeaf518e4c7d2b1692`
= C's recorded digest; no dev-launcher bundle; 0 listeners on :8081/:8083 throughout; `content_size` read before and after
every frame and appearance asserted by luminance on every retained frame (capture log).

B's env-pairing scan on that container (`native/e2b9498b-release/env-pairing-on-device.txt`, counts only): positive controls
sandbox ref 1, `pk_test_` key value (≥40 alnum) 1, sandbox URL 1, bare `sandbox` 10; forbidden: live Stripe key VALUE 0,
production URL 0, `sk_live_` 0, `sk_test_` 0, `service_role` 0; the bare production ref and the bare `pk_live_` prefix are
1 each = the runtime guard's REFUSE constants (`envGuard.ts:28`, `envValue.ts:52`), the same profile as RC1. Class:
simulator-native, adhoc, unsigned; not TestFlight, not distribution; no EAS run.

## 9. Classes kept apart

- **Passed on paint (fixture class, Release binary):** §6–§7 once filled; the RC1 default-size state sweep carries where E's
  closure diff shows a row's files unchanged (E's matrix).
- **Source-only:** §2–§5 entirely; P-4, W-6, W-5 parity, VoiceOver labels. F2, F3, F5 and F7 are signed-in flows, so their RC2
  closure is test and source evidence, not a visual pass.
- **Owner-waived (not passed, not failed):** signed-in Home, the Edit refusals, the W-5 picker, the R-3 crop, the signed-in
  wording sessions, and any real 3-D Secure return on a device.
- **Optional:** spoken VoiceOver.
- **Never a production result:** nothing here is an authenticated or live-payment result; no live payment was used.

## 10. Process

- B's detached trial worktree `temporary-worktrees/b-rc2-trial` (B's own; `node_modules` symlinked); C's worktree never touched;
  every mutant digest-verified restored; single test files only; no heavy job while C held HEAVY-1 or HEAVY-2.
- One read-only subagent (allowed by the owner) examined F1/F4; B verified each of its findings at source before acting.

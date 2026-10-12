# B — final consumer regression verdict at `integration/rc-20261012` @ `48d20ca1`

**DRAFT — slots marked ⟨pending⟩ are filled only when the evidence exists. Nothing here is a pass until its
slot names a frame, a log or a line.**

Candidate `48d20ca1c0d0d53ce51c295c44447f3548496aa8` (tree `7feadf07`), review only; not merged, not deployed.
**Identity verified by B's own diff:** `git diff --stat d27aa449 48d20ca1 -- app src` → 0 files; positive control over
the whole tree → 69 files / 11,226 insertions; none of the 69 is a native-build input. Therefore every B review at
`d27aa449` (app code = `9bbeaec6`) carries to `48d20ca1` unchanged, and E's matrix rows M-1…M-6 apply as recorded.
**CI at `48d20ca1`:** run `38203105234`, `completed` / `success`, 5/5 jobs — read by B via `gh`, not cited.

Evidence classes kept apart: **source · web render · native simulator (dev build) · native simulator (fresh Release
install) · physical device.** Nothing in this program is physical-device evidence.

## 1. PASSED — measured on native frames, carried forward unchanged (app code identical)
| E row | Items | B evidence |
|---|---|---|
| M-1 | Home artwork 4:5 per fixture, identity beneath, no gradient; feed-row/feature amounts at A3XL; icons | `B_NATIVE_REVIEW_d5217530.md`, `9498080a` |
| M-2 | Listing: poster clearance, R-4 name reachable, Option B footer, reservation feedback, scroll-end, bid-activity amounts, full date/time, error/offline | `B_NATIVE_REVIEW_{d5217530,91a5a58c,3c03778a,9498080a}.md` |
| M-3 | Profile P-1, P-2, P-3; hero stacking; no `null%`; default layout 0 px below header | `B_NATIVE_REVIEW_857e6d93.md`, `B_NATIVE_REVIEW_12cc3e8d.md` |
| M-4 | W-4 header at A3XL; S-1/S-1b labels | `B_NATIVE_REVIEW_9bbeaec6.md` §1–2 (controls: 86,802/78,519 px confined to y 23–163 pt; `Notificatio/ns` at `e6a38aef`) |
| M-5 | W-2 "(10%)" on the resale minimum; W-2b sold note; P-5 tier word | `B_NATIVE_REVIEW_9bbeaec6.md` §3–5 |
| M-6 | W-4 and S-1/S-1b at **default** size, Light and Dark | `B_REVIEW_HANDOFF.md` §11 (`92356c9e`): four re-shot frames, 0 px below header, clock-only differences |

## 2. SOURCE REGRESSION AT `48d20ca1` — ⟨pending: subagent findings, each verified by B⟩
B's own read of the money-class paths (independent of the subagents), no defect found:
`payControl.ts` 11 branches ("Pay $X" only on `paymentReady`); `CheckoutNative.tsx` ref-based single-flight latch
(L159), `confirmedRef` only on `completed`/`already_settled` (L560/630/655), refund never a success (L133/269), pay
label verbatim (L826); `detailState.ts` `RESALE_FEE_LABEL` from `BUYER_FEE_RATE` (L58), `reserveBusy` keyed on action
kind (L503–511); `holdState.notHeldReason` compares against the server-shown deadline and `CheckoutNative` declares a
lost hold only after `holdRecheckedRef` (L689–696); `bidEntry.ts:133,143` is the closed W-2 item.
**Subagent findings, each re-read by B at the quoted line before acceptance** (sent to C as one report):

| id | class | file:line | B verified | disposition |
|---|---|---|---|---|
| B-D1 | money presentation / error recovery | `useListingRealtime.ts:135-138`, `ListingDetailScreen.tsx:269,370`, `BidActivity.tsx:61-62` | **yes** — error → `[]`; `currentBid` seeded from `starting_bid`; "No bids yet" painted | defect; fix recommended; not reachable via fixture |
| B-D2 | interaction on the money screen | `CheckoutNative.tsx:647-662` vs latch at `:498` | **yes** — recheck/retry controls have no ref latch; Pay does | defect; fix recommended |
| B-D3 | interaction (session-only reach) | `useListingRealtime.ts:154-155, 241-243` | **mechanism yes** — same-topic channel shared; removeChannel removes it for both | recorded; under the sign-in waiver, not reproduced |
| B-D4 | error copy (F-21 class) | `ListingDetailScreen.tsx:834-837`, `CheckoutNative.tsx:562-566`, `app/profile/[id].tsx:164-175` | **yes** — raw text shown; profile `error` never read | defect group; fix recommended |
| B-D5 | product truth (device clock) | `bidState.ts:82-83` | **yes** — `ends_at <= now → 'lost'` before `finalize_auction`; comment says "conservative" | recorded for a ruling, not a quiet fix |
| B-D6 | readability — the owner's ruled cap class | `StickyBar.tsx:165-169` (minimum all-in line), `PlaceBidScreen.tsx:358-363, 430-434` (amount, Total); lower: `Button.tsx:153-154,168-169`, `Chip.tsx:69-75` | **yes** — 1.3× cap on money lines; **PlaceBid Total painted smaller than its label on the Release binary (§4b)** | **measured** on PlaceBid; StickyBar line source-only (Listing not capturable on Release) |
| B-D7 | readability — two-column rows without `identityStacks` | `CheckoutView.tsx:176,410`; `PlaceBidScreen.tsx:330,422,426`; `BidCard.tsx:120-124`; `app/profile/[id].tsx:76`; `receive/[id].tsx:553,746`; `send/[id].tsx:628`; `ListingStatusBanner.tsx:49` | **MEASURED on the candidate binary at A3XL (§4b): Bids 13,741 px, checkout 4,030 px, PlaceBid 893 px, Order 888 px past the content edge** | **FAILED check** (owner's money-digit rule); scope decision with A/owner |
| B-D8 | consistency + harness fidelity | `money.ts:62-67` vs `:93-99`; `CheckoutNative.tsx:775,803-805,814`; `detailState.ts:29,63`; `bidEntry.ts:75-76`; `app/_dev/v3-checkout.tsx:57` | **yes** — checkout trims `.00`; fixture hard-codes 2dp | defect (consistency) + fixture fidelity; fix recommended |
| low | unverified | `CheckoutNative.tsx:206-208` (no-user mount); `ListingDetailScreen.tsx:807` (swallowed throw) | reach unclear | recorded only |
| closed | — | `bidEntry.ts:133,143` "10%" literal | already closed under W-2 | not re-raised |

**No crash, data-loss, auth or money-loss defect found.** Clean areas confirmed by the review and consistent with B's own
read: pending feedback + ref latches on reserve/bid/Pay/mark-sent; no success before authoritative confirmation; cached data
never authorises; foreground return confirms nothing; fee labels derived; loading/empty/error/offline branches present and
distinguishable on Home, Search, Bids, Tickets, Listing, PlaceBid, Order, Send, Settings, public profile.

## 3. FRESH-INSTALL NATIVE BUILD OF `48d20ca1` (C, H1) — **EVIDENCED**, read by B from the artifact, not from C's message
| fact | from the artifact (B's read) |
|---|---|
| commit | build log line 3: `HEAD (git rev-parse, read now): 48d20ca1c0d0d53ce51c295c44447f3548496aa8`; build worktree `repos/snatchit-build-20261012`, B's own `rev-parse` there = `48d20ca1`, clean |
| invocation | log line 16: `SENTRY_DISABLE_AUTO_UPLOAD=true SENTRY_DISABLE_XCODE_DEBUG_UPLOAD=true npx expo run:ios --configuration Release --device 52282259-… --no-bundler` |
| exit | log line 2894: `=== BUILD EXIT: 0 at 2026-10-12T04:51:10Z ===`; 2,897 lines; `private-evidence/C-session-12c718b1/build-20261012/03-expo-run-ios-release.log` (not under `snatchit-refund/.expo/`) |
| configuration | Release / iphonesimulator |
| product | log line 2889 → `DerivedData/SnatchIt-flyetfnbyyfhyscdmadtwcycpulw/Build/Products/Release-iphonesimulator/SnatchIt.app` (mtime 00:50:20) |
| bundle id (built `Info.plist`) | `com.jdt-inc.snatchit`, 1.0.0 (1) |
| JS delivery (from the binary's contents) | **embedded** `main.jsbundle`, 4,789,444 B, Hermes magic `c61fbc03`, sha256 `a04dac37…`; no dev-launcher bundle; `:8081` had 0 listeners at both cold launches |
| main binary | sha256 `85d8abfb…` |
| installed container vs product | digests compared in B's H2 capture log (`native/48d20ca1-release/capture-log.txt`) |
| launch proof | C: `simctl launch … com.jdt-inc.snatchit` exit 0, SANDBOX banner at 3 s, Sign in rendered, no redbox (`launch-2-simctl-coldstart-light-Coperated.png`); plus one harness frame equal below the header to the dev-client hub at `9bbeaec6` |

**B's env-pairing scan on the `.app` (counts only):**
| pattern | count | reading |
|---|---|---|
| full `pk_test_` key (prefix + ≥20) | **1** | positive control — configured |
| full sandbox URL `https://ofaidukbieeekqaboscm.supabase.co` | **1** | positive control — configured |
| full `pk_live_` key (prefix + ≥20) | **0** | no live key |
| full production URL `https://hqycwntpfoztoinemqns.supabase.co` | **0** | no production host |
| `sk_live_` / `sk_test_` / `service_role` | **0 / 0 / 0** | no secrets |
| bare `hqycwntpfoztoinemqns`, bare `pk_live_` | **1 / 1** | the env guard's compiled REFUSE constants (`envGuard.ts:28`, `envValue.ts:52`); C's `04-artifact-inspection.txt` traces the same |
A bare-literal count would have shown 1/1 and read as a failure; the refined patterns separate a configured value from a comparison constant. The `IS_SANDBOX_BUILD` pairing is proven by the banner painting in every gated frame.

**Verdict on O-2 (for E): a fresh native build of `48d20ca1` is evidenced by commit + log with exit status + the binary that ran.** Scope of that binary: Release, sandbox-paired, `_dev` routes resolve (`__DEV__ || IS_SANDBOX_BUILD`), `foundation` excepted. **It is the toolchain proof; RC2 needs its own H1 build.**

## 4. H2 — NATIVE on the installed `48d20ca1` Release binary (B-operated, 05:01–05:28Z; released 05:30:35Z)
`native/48d20ca1-release/` — 90 frames, capture log with the installed container's `main.jsbundle` and binary sha256
(equal to the product's), `content_size` read pre-launch and post-capture, banner-gated. Class: **native, Release binary,
fixture-seeded** — development evidence on the candidate binary, never an authenticated-flow result. Top-of-screen only
(no touch injection).

### 4a. Default-size state sweep (70 frames, Light) — **PASSED**: every non-waived critical-path state renders
Home ×7 (default, empty, nomatches, sold-empty, ended-empty, error, offline) · Bids ×7 · My listings ×4 · Tickets ×5 ·
Order · Send · Checkout ×16 (every `CHECKOUT_STATES` key + complete/pending/settle-failed/refund) · Edit ×6 · Search ·
Create · own profile ×4 · public profile ×4 (not-found, blocked, stats-unavailable, no-listings) · transfer gallery.
Each state is distinguishable and truthful; error and offline states offer **Retry**; `stats-unavailable` says *"This is
not a record of zero sales"*; the own-profile phone is **masked**; the five Edit refusals are the known byte-identical
signed-out guard (owner-waived). Gutter: 0 px content ink on all except `mylistings-default` (1,004 px — the horizontally
scrolling chip row, a scroller by design, not a clip). `bids-past` and `bids-empty` are distinct (74,569 px differ).
**Excluded on this binary — BY B's OWN ERROR, corrected:** `app/_dev/v3-listing.tsx:387` is `switch (screen)` with
`default: return <Redirect href="/" />` and no default for `screen`; C's capture routes always carry
`?screen=listing&variant=…`, B's carried `?variant=…` alone, so all 11 `listing-*` and 4 `banner-*` frames are **Home's
empty state**. B first wrote "fixture-gated on a Release build" — **wrong, withdrawn**; the Listing IS capturable on the
Release binary. Listing evidence for the `48d20ca1` binary carries from the dev-client builds (E's M-2); B captures the
Listing properly (footer sub-line, banner states) in the RC2 window. `foundation` is the only route that is genuinely
`__DEV__`-only.

### 4b. A3XL set (20 frames, Light + Dark) — **B-D6 and B-D7 are MEASURED, not predicted**
| frame | content ink past 377 pt | max ink x | what the paint shows |
|---|---|---|---|
| `bids-all` | **13,741 px** (L) / 13,744 (D) | 392.7 pt | `$99.00`, `$48.40`, `$132.00` run off the right edge (`$99.0(`); `PAY TO CLAI`, `CONFIRM RE.` |
| `checkout-auction` | **4,030 px** / 4,032 | 392.7 pt | `Winning bid $9`, `Service fee $9.` clipped |
| `placebid` | **893 px** / 894 | 392.7 pt | `Fee (10%) $9.5` clipped; **Total `$104.50` painted visibly smaller than its "Total" label** (the 1.3× cap, B-D6); the bid `$95.00` fits (shrink-to-fit) |
| `order` | **888 px** | 392.7 pt | progress-step labels truncate and run off |
| `send` | 0 | 363.7 pt | `Buyer Buye…`, `Method mo…` — ellipsis truncation inside a two-column row (B-D7 class, inside the edge) |
| `checkout-ready` | 0 (hairline only) | — | `HELD FOR YOU · 7:12 · UNTIL 7:34 PM` wraps on whole words; `Pay $99.00` fits (the fixture's 2dp label — B-D8) |
| `profile` | 0 (hairline only) | 361.3 pt | hero stacked, as at `12cc3e8d`; `Lanter…` name (known) |
| `listing-footer`, `banner-*` | — | — | **not Listing** — Home's empty state, B's missing `screen=listing` (§4a); the StickyBar sub-line (B-D6) and banner states (B-D7) are captured in the RC2 window |

At default size the same screens measure **0 px**. **VERDICT FOR THIS ROW: FAILED — readability, the owner's rule
"never split a monetary amount across lines or clip its digits".** Not a crash, not a data loss, not a money loss.
**A's scope decision (05:3xZ): B-D7 enters RC2** — the existing approved stacking rule on the four surfaces
(`BidCard.tsx:120-124`, `CheckoutView.tsx:176/410`, `PlaceBidScreen.tsx:330/422/426`, the Order progress row), no copy
change, condition pixel-identity at default size; **B re-measures default and A3XL on the RC2 binary.** **B-D6** (the
1.3× cap on PlaceBid's Total) stays an **owner decision**, documented with this evidence, not in RC2. If D7 cannot land
cleanly it goes to the owner as a follow-up and this FAILED row stands.

## 5. SOURCE-ONLY — not passes
P-4 (fixture correction, nothing to photograph) · W-6 payout wording, connected state (no fixture seam) · W-5 platform
parity (test-pinned) · VoiceOver labels (source only).

## 6. OWNER-WAIVED — not verified, not re-asked, not passed
Authenticated consumer Home · Edit refusal group · W-5 Edit platform picker · repeat signed-in sessions · R-3 native
image-picker crop (signed-in create flow).

## 7. OPTIONAL — not release blockers
Spoken VoiceOver · `Badge` 1.3× cap (P-5 legibility residual) · `needs_review`-from-disputes blurb wording · the proposed
377 pt A3XL ink test.

## 8. Evidence-provenance audit (subagent, 21 pass claims; the decisive ones re-verified by B)
| status | count | items |
|---|---|---|
| **backed** | 11 | frame exists, served sha in the log, banner gate, control stated |
| copied_baseline | 1 | the `1ab2c8e2/` default frames — **six** byte copies of `b64e5dd6/` (B re-verified by md5; count corrected from four) |
| unretained_half | 2 | the historical `1ab2c8e2` re-shoot; **W-2b's "amount unchanged" before-frame** — the before side of the sold panel was never kept (C's own log says the diff covered the wrong region); the sentence change is on paint, the amount's constancy is source-only |
| source_only | 3 | W-6 connected copy, P-4, P-5 on the non-fixture tiers |
| waived | 2 | W-5 picker, signed-in Home / Edit refusals |
| optional | 2 | spoken VoiceOver, the `Badge` cap |

Gaps the audit raised and B's disposition: **W-4 Dark at A3XL has no `b64e5dd6` Dark control frame** — the Dark fix is read
from the after-frame and the Light control; recorded as such, not as a photographic control. **P-5's row was labelled
"served at `9bbeaec6`" for a `1ab2c8e2` frame** — corrected in `B_REVIEW_HANDOFF.md` (`01b2cc4c`). The audit's own
pixel counts differ from B's and E's by instrument (threshold and background method); all three agree on the zero below
the header. No pass claim rests on a frame that does not exist.

## 9. Accessibility from source and existing frames (subagent, 33 checks: 22 ok · 8 defect · 2 unverifiable · 1 optional) — no new owner obligation
Items B re-verified at the quoted lines are marked **B**; the rest are the audit's, with its source refs.
| # | screen · check | WCAG | finding | severity | B |
|---|---|---|---|---|---|
| A-1 | Listing footer CTA labels and the **minimum all-in sub-line**; every `Button` label; `Chip` labels | 1.4.4 resize | capped at 1.3× (`Button.tsx:153-154,168-169`, `StickyBar.tsx:165-169`, `Chip.tsx:69-75`) | readability — **= B-D6**, owner's ruled class | **B** |
| A-2 | PlaceBid amount, stepper glyphs, Total | 1.4.4 | capped at 1.3× (`PlaceBidScreen.tsx:356-363,377,430-434`); the Total paints smaller than its label on the candidate binary (§4b) | readability — **= B-D6** | **B** |
| A-3 | Home feed-row meta lines | 1.4.4 | `numberOfLines={1}` not lifted when stacked (`FeedRow.tsx:149,152`), unlike the feature (`HomeFeature.tsx:151,156`) | readability, minor | audit |
| A-4 | Home / Bids / Settings inline **Retry**, own-profile **Settings** action | 2.5.5 target size | bare `Pressable` + one-line `Text` + `hitSlop={8}` ≈ 32–36 pt tall vs `MIN_TOUCH_TARGET = 44` (`typography.ts:122`); roles and labels correct | interaction, minor | **B** (lines read) |
| A-5 | Public profile display name | 1.4.4 | `numberOfLines={1}`, no fit (`app/profile/[id].tsx:293`) — `Lanter…` on the candidate binary | readability, minor | **B** (seen) |
| A-6 | Settings row chevron | 1.4.11 non-text | `faint` ink 2.3:1 Light / 2.4:1 Dark, below 3:1; the row **edge** (3.4:1 per `palette.ts:100`) is what identifies the control and the whole row is the spoken target | cosmetic | **B** (recomputed) |
| A-7 | Bids segment chips | 1.4.4 | capped at 1.3×; two short words, information intact | readability, lowest | **B** |
| — | 22 checks ok: roles/labels on icon buttons and chips, no colour-only status on the critical screens (tone always paired with a word), body-text contrast on canvas in both appearances above 4.5:1 | | | | audit |
| — | 2 unverifiable from source: focus order and spoken output | | optional per the owner | | — |
None of these is a release blocker; A-1/A-2 are already carried as B-D6 (owner decision); A-3…A-7 are recorded for the
follow-up list. Spoken VoiceOver remains optional and is not turned into an owner testing obligation.

## 10. Corrections of record this sprint (B's own)
- **"Listing is fixture-gated on a Release build" — wrong.** The redirect was B's missing `screen=listing` route param
  (§4a). Stated to A, then withdrawn in the same hour.
- **Push `647b8b48` was not gated on its own scan.** The scan reported one forbidden-class hit and the command went on to
  commit and push; the hit was B's verdict table naming `sk_live_` / `service_role` as pattern *labels* (0 token-shaped
  values after any forbidden prefix, verified after the fact). Nothing private was published; the gate now stops the push.
- **Capture driver:** a per-frame terminate→launch cycle against the Release binary read as a hang (it was my timing);
  gate screenshots written straight to the SSD failed (`simctl` cannot write to the external volume — C's recorded trap,
  which `cap.sh` already handles). Both corrected before the frames that count were taken.
- "Signed-out surface only" for the Release binary — **wrong**, withdrawn; gate is `__DEV__ || IS_SANDBOX_BUILD`.
- First staleness computation ran relative to the wrong cwd and returned "no change" for `src/components/ui`, which
  had changed — voided on its positive-control failure and recomputed with absolute paths.
- "E not listed" at first `ListAgents` — superseded minutes later when E's fork appeared.

## 11. CALIBRATION — what B's source review did not find, recorded before the delta review
A has superseded `48d20ca1` with **RC2** = its line + `v3/rc-fixes-20261012` (C: F1–F5, F7) + `fix/rc-f6-settled-recheck-20261012`
(A: F6, `50e74efb`). Seven consumer defects, found by C's audit and confirmed by A at source, in the crash / data-loss /
money-presentation classes. **B's review found none of them.** Stated plainly, per file:

| fix | where it lives | was the file in B's review? | why B missed it |
|---|---|---|---|
| **F4** 3-D Secure return drops the checkout mode | `CheckoutNative.tsx:368` `returnURL: snatchit://checkout/${listingId}` carries no `mode`; `:91` `isBuyNow = params.mode === 'buy_now'` | **yes — read, and "3-D Secure remount" was listed as a CLEAN area** | the check asked "does the remount confirm anything falsely?" (it does not) and never asked "does the remount keep its inputs?" Visible at source; a miss |
| **F6** race paints "Nothing was charged" after a charge | `setupDecision.ts:222-225` returned `not_held` when the hold was no longer mine, without re-reading settled payments | **yes — read; "returning from another app confirms nothing" listed as CLEAN** | every money check was oriented at *no false success*; none probed *no false denial of a charge*. A miss in prompt design, not only in execution |
| F1 crash on a malformed checkout deep-link param | checkout route parsing | partly — `app/checkout/[id].tsx` was read; the parse site was not probed with malformed input | the review tested states, not inputs |
| F2 listing edit says "Saved" on 0 rows written | `app/listing/edit/[id].tsx` | **no** — only the `_dev/v3-edit-listing` params were read | scoping: the edit screen was treated as waived territory; its write path is not waived |
| F3 signup profile/demographics write failure swallowed | signup | **no** | scoping: auth/signup excluded |
| F5 payout-return claims "Connected" unconditionally | payout-return | **no** — `payout-setup.tsx` was grepped, the return route was not | scoping: "account/settings flows" did not reach the Stripe return |
| F7 recovery hold never released after a failed `verifyOtp` | auth recovery | **no** | scoping: auth excluded |

**What this does to the weight of §2's "clean areas":** they are evidence about the questions that were asked — no false
success, derived fee labels, ref latches on Pay/reserve/bid, distinguishable states — and **not** evidence about false
failure, input robustness, or the four screens outside the scope. B's eight items (B-D1…D8) stand on their own re-reads
and do not overlap F1–F7. The baseline verdict at `48d20ca1` is therefore: *no defect found by B in the classes it
checked; defects in classes it did not check were found by C.* The delta review of RC2 is scoped to exactly those
classes and screens, and it is B's own read — no further subagents (the owner's cap of two is spent).

## 12. RC2 DELTA REVIEW — F6 (`fix/rc-f6-settled-recheck-20261012` @ `50e74efb`, A) — read at source by B
- **Scope in app code:** `src/lib/checkout/setupDecision.ts` only (branch based on `d27aa449`; the whole-tree difference
  vs `48d20ca1` is the absent S3/S4 merges, expected). New test `tests/checkout-setup-settled-recheck.test.ts`, six cases:
  succeeded-on-re-read → `already_settled`; refund-on-re-read → the refund state; failed re-read → `payment_status_unknown`,
  never `not_held`; and three unchanged paths (no settlement either read → `not_held`; live hold → one read, one intent;
  auction mode never reads the listing). **No new user-facing string** (added literals are decision kinds).
- **Logic:** sound. Previously `!holdIsMine(…)` returned `not_held` unconditionally, which paints "Nothing was charged";
  the fix re-reads settled payments first, and a failed re-read establishes nothing — the right asymmetry on a money
  screen. `already_settled` and refund states take precedence over `not_held`. The live-hold and auction paths are untouched.
- **Negative controls (A, before push; B has not yet reproduced):** three mutants through A's Python harness in
  `temporary-worktrees/a-f6-settled-recheck` — clean baseline asserted, anchor unique, file asserted changed, restore
  digest-verified. M1 restore the unconditional `not_held`: **4/4 predicted** (three F6 paths + the `not_held` re-read
  count); M2 failed re-read → `not_held`: 1/1; M3 drop the refund check on re-read: 1/1; unexpected failures 0; RED
  before the fix 4/6. CI on `50e74efb`: run `38204905293`, 5/5. Record: `docs/release/packages/RC_20261012/README.md`.
  **B's independent M1 — REPRODUCED** (own worktree `temporary-worktrees/b-f6-mutant` at `50e74efb`, `node_modules`
  symlinked from the serving tree, same lockfile): fixed source **6/6 green**; `setupDecision.ts` reverted to `48d20ca1`
  (digest `57896ba1…` → `9e328955…`, applied-and-changed asserted) **4 failed / 2 passed** — exactly the pre-registered
  set (three F6 paths + the `not_held` re-read count; the live-hold and auction cases stayed green); restored (digest
  equals baseline) **6/6 green**. Independent confirmation of A's M1 4/4.
- **F4 confirmed at source at `48d20ca1`** (fix pending on C's branch): `CheckoutNative.tsx:368`
  `returnURL: snatchit://checkout/${listingId}` carries no `mode`; `:91` `isBuyNow = params.mode === 'buy_now'`, so the
  3-D Secure remount reads the Buy Now as an auction. C reports `recheckPayment` is now guarded on a parsed mode.
- **F1, F2, F3, F5, F7:** ⟨pending C's push of `v3/rc-fixes-20261012` with the new-strings list⟩

### E's delta rows at RC2 (ids to key B's delta review to; each closes on C's evidence plus B's review at the RC2 sha)
| E row | screen | fixes | B's delta review |
|---|---|---|---|
| Δ-1 | checkout | F1, F4, F6, F7 | F6 reviewed above (`50e74efb`); F4 confirmed at source at `48d20ca1`, fix ⟨pending⟩; F1, F7 ⟨pending⟩ |
| Δ-2 | payout-return | F5 | ⟨pending⟩ |
| Δ-3 | listing edit | F2 | ⟨pending⟩ |
| Δ-4 | signup | F3 | ⟨pending⟩ |
| Δ-5 | auth deep link | F1 | ⟨pending⟩ |

E's rule, which B applies: the owner's waiver covers the **visual** check of signed-in-only flows; each fix still needs
test and source evidence, and that is what B's delta review supplies. F8 (device clock marks a bid lost = B-D5) is an owner
product decision routed by A; not re-escalated here.

### C's disposition of B-D1…D8 (received, not disputed)
Fixing on the RC2 branch, tests-first with named mutants: **B-D1** (failed bids read → error state with retry; minimum
never restated from an unconfirmed number) and **B-D2** (ref single-flight latch on recheck/retry, on top of the parsed-mode
guard). Recorded, not changed in this pass: B-D3 (waived reach), B-D4 (F-21 class, wording owner), **B-D5 = C's F8** (one
finding, owner ruling), B-D6/D7 (shared cap stays a documented follow-up unless the owner directs), B-D8 (harness-fidelity
defect for the next wording decision).

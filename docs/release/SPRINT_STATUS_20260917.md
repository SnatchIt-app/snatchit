# Sprint status — the ONE current table (A). **CLOSED 2026-09-17 by the owner's six closing rulings.** Historical evidence stays in the other records; this table is replaced, never appended.

**Closing rulings, verbatim (owner, 2026-09-17):**
1. *"F-NOTICE-1: use the minimal fix. When a user withdraws account deletion, retire only that user's pending deletion notice. Do not add a new notification type or outbound message. Keep the reviewed branch and migration 141 unapplied unless a separate apply decision is made."*
2. *"Leave the two retained Line 3 proof files and their references untouched. No further reads, downloads, deletion, overwrite, service key or cleanup verification."*
3. *"PFA-34 remains proposed and unsigned. Do not treat it as approved or apply migration 138."*
4. *"Defer the venue-staff detector extension. Keep the detection scope limited to organization membership; leave the local extension unpushed."*
5. *"Keep migration 138 unapplied and outside the marketplace candidate. Do not apply sandbox prerequisites 115–120, run hosted detection reads, read server-log settings, access production, deploy functions, enable keys, or request a build."*
6. *"Keep F-BIDS-1 at 6561d1f for the later candidate; Build 19 remains unchanged."*

**Frozen facts at close:** Build 18 = `aad5f75` · **Build 19 = `candidate/2026-09-18-build-c3` → `f412d10`, installed on the owner's iPhone, UNCHANGED by every ruling above** · next-candidate head `release/production-gate-20260918 @ 6561d1f` (= f412d10 + F-BIDS-1; CI 35245103799 SUCCESS, five jobs; D merge gate PASS) · F-NOTICE-1 branch `fix/f-notice-1-withdraw-retires-notice @ ea547e5` (CI 35263537823 SUCCESS; **unapplied**) · 138 head `ops/138-operator-onboarding @ a9aa34e` (**unapplied, off the candidate**; D's `1cacdf5` local and unpushed) · **PFA-33 SIGNED** (governance `99ecf31`), **PFA-34 PROPOSED, NOT SIGNED** (governance `b7895bb`, placed block md5 `026cb858…`) · sandbox `ofaidukbieeekqaboscm` **closed for the sprint**, last state at §15/§16 of the manifest · production ledger 135, **untouched and unread** since 2026-09-12 · push key **deferred** · **no build, no deploy, no key, no production or sandbox access is authorized**.

**Result vocabulary, used strictly:** PASSED · FAILED · BLOCKED · UNTESTED · CLOSED · DEFERRED · OPEN. Nothing is upgraded by inference.

| # | Item | Owner | Exact head | State at close | What it waits on |
|---|---|---|---|---|---|
| 1 | **F-NOTICE-1** stale "Account deletion requested" on an ACTIVE account | A implemented, D reviewed PASS, B reviewed | `fix/f-notice-1-withdraw-retires-notice @ ea547e5` (migration 141, base `6561d1f`) | **CLOSED on design, OPEN on apply.** Ruling 1: the minimal fix is the decision; Option B declined. CI 35263537823 SUCCESS (five jobs; pgTAP Files=89, Tests=5325, PASS); root cause reproduced on a replay; three review findings closed (D's F-141-1 service_role pin, D's abort trade-off + `lock_timeout`, B's header overclaim + C3-as-delta). **Applied nowhere.** | a separate apply decision, which has not been made. The buyer's existing stale row is untouched (forward-only fix); §4 of the root-cause record stays unauthorized |
| 2 | **Line 3 image round trip** | A executed, D witnessed, C guided, owner ruled | two objects RETAINED | **CLOSED — QUARANTINED.** Ruling 2 tightened §16: no further reads, downloads or cleanup verification either. §16 is the final state of record. Results as they stand: D2 and D1 upload paths **PASSED** · HEIC conversion **UNTESTED** · D6 **INCOMPLETE** · DV-IMG-10 **UNTESTED** · N3 **PASSED** · N1/N2/N4/RT6/U1/RT5-P **HELD** · call count **NOT ESTABLISHED**. Two process failures recorded as failures (approved order not followed; no row boundary reached A, so the intermediate state is gone and recorded as gone) | nothing. Reopening any held row is the owner's decision alone |
| 3 | **138 operator onboarding** | D implements, A reviews | `ops/138-operator-onboarding @ a9aa34e` (CI 35257712408 green; pgTAP 88 files / 5441 PASS) | **DEFERRED, unapplied, off the candidate.** A's review at `a9aa34e`: **PASS** (replay 157/157, Gate-2 32\|107\|37\|38, 5435/5435 strict TAP, mutants all as predicted, two-session A6 proof S1/S2/S3/C1/C2 all pass). Ruling 5 refuses the apply, the 115–120 sandbox chain, the hosted detection read, the server-log read, production access, deploys, keys and builds. Apply package **PARKED** with all six approval points unexercised | a separate owner authorization for each point, whenever the owner chooses |
| 4 | **PFA-34** | A places, owner signs | governance `b7895bb`, placed block md5 `026cb858319bc7c0181e1dad01e23ef1` (2726 bytes, 27 lines) | **PROPOSED, NOT SIGNED** — ruling 3. **Conflict RESOLVED:** D's session was told it was signed, A's was told to keep it unsigned; neither acted on the other's relay and the governance file was never changed, so the conservative state held and is now the owner's own ruling. Block bytes re-verified unchanged after this close-out edit | the owner's explicit approval of that checksum, if they ever want it signed |
| 5 | **Venue-staff detector extension** | D implemented locally, A reviewed the narrower scope | `1cacdf5` — **local, unpushed, no CI, unreviewed** | **DEFERRED** — ruling 4. **Conflict RESOLVED:** D was told to widen the detector, A was told not to; the owner has now chosen the narrower scope. Detection stays organisation membership, so PFA-34's placed D1 clause and the reviewed implementation agree again and the checksum did not change. **Gap carried, not closed:** venue-plane membership at a customer venue (path (c), `venue.grant_staff_role` 080:224) stays unmonitored | the owner, if they later want venue staff covered |
| 6 | **F-BIDS-1** Bids empty state | C fixed, D reviewed, A integrated | `release/production-gate-20260918 @ 6561d1f` (tree = `accb40c`'s) | **CLOSED for this sprint, held for the later candidate** — ruling 6. CI 35245103799 SUCCESS re-verified; D merge gate PASS; `f412d10..6561d1f` changes 0 lines under `supabase/`, so the apply hashes and PC3 values hold at 6561d1f. **Build 19 unchanged** | a future candidate build that carries it; a device row is owed then. Follow-up recorded: bump the load generation before the `!userId` return |
| 7 | **DV-ST2b** bids read-access window | A executed, D witnessed, C guided | window 18:36:23Z–18:38:56Z | **CLOSED.** Server half **PASSED**: six `GET /rest/v1/bids` → 403 (PostgREST 42501) inside the window, 200s before it, restore verified independently by A and D (md5 `466fd2d8…`). Client half **SPLIT**: rows remained visible (observed); any message or banner **NOT CAPTURED** — not inferred as none | nothing. A re-run would need a new revoke window and the owner's word |
| 8 | **F-ST2B-1** harness defect (A's own) | A | scratchpad harness | **FIXED and disclosed.** Watchdog and verify were invoked by bare `"$0"` → "command not found": 28 s with no automatic restore, then verify silently did not run. Fixed with absolute paths plus arm verification. Lesson recorded: arming that is not verified is not arming; a verify that did not run is not a verify (D) | nothing |
| 9 | **Accidental sandbox report** `265b0041…` | A executed, D witnessed, owner authorized | `public.reports` | **CLOSED 18:08:24.956Z.** No outbound call ever happened; deleted 18:07:09.332Z, exactly 1 row, under the owner's direct go with A and D pre-reads matching; D's post-read agrees | nothing |
| 10 | **F-CHK-1** "checkout asserts a decline when the request never reached the server" | A verified; B filed | `CheckoutNative.tsx` at `6561d1f` (identical at `f412d10`) | **RECLASSIFIED — the finding does not hold as written.** A checked source rather than accepting the report: `:513` refuses to treat a sheet error as proof of failure and reconciles first; `unreachable` withdraws Pay; `:851-858` shows "please don't pay again" with a Check status button. **Not release-critical.** A had relayed it to the owner as release-critical before checking — recorded as A's error | **OPEN, narrower:** the PRE-request case, for C to confirm in source. Any proposal must carry B's discriminating control (a network failure that is not a Stripe decline) |
| 11 | **F-BID-2** bid form computes its minimum from `0` after a discarded fetch error | C (implementation), A informed | `PlaceBidScreen.tsx:68-83` on `6561d1f` | **OPEN, LOW–MED.** A truthfulness defect, not a money one — the server still validates. Not release-blocking | C's triage **UPGRADED 2026-09-17 — verified by A at `f412d10` (the built commit the owner's phone runs), not only at `6561d1f`; B found it, C verified it, A confirmed it independently.** The read is `.then(({ data }) => …)` with **no `error` destructured and no `.catch`**: a resolved-with-error read leaves `listing` null with `loading` false, so the form renders and `minNextBid(listing?.current_bid ?? 0, MIN_INCREMENT)` offers a minimum **derived from nothing**, with no event name and no null guard before the form; and a **rejected** read never runs the handler at all, so the spinner never clears. The rejected-read half is worse than this row originally recorded and is new information. Classification unchanged and still A's: the server validates the bid, so it is **not a money defect** — it is the app asserting a price it does not know **on the screen where someone commits money**. C ranks it release-blocking for the next candidate; A agrees it belongs in the correctness batch. |
| 12 | F-AUTH-2 duplicate data requests after sign-in | C | — | **OPEN, LOW.** Load, not correctness | C's trace + a request-count test |
| 13 | F-DT-1 text size applies only after relaunch | C | — | **OPEN, LOW–MED (accessibility).** Relaunch recovers | RN upstream check; any mitigation goes to the owner first |
| 14 | **Server-log exposure (138 F11)** | A scoped, owner authorizes | `SERVER_LOG_SETTINGS_READ_SCOPE_20260917.md` | **DEFERRED and UNVERIFIED** — ruling 5 names the server-log settings read among the prohibitions | a separately authorized production read, if the owner ever wants it |
| 15 | **72-hour auto-release tail** (D's extension of the hazard) | owner's choice | sandbox transfers | **CARRIED, not cleared.** Clearing `auto_release_at` is another sandbox write and is not authorized. Sandbox-only; nothing acts on it while no service key is in the Vault | nothing, unless the owner wants it cleared |
| 16 | **iOS 27 / SDK-upgrade gate** | A records; nobody is proposing an upgrade | our config at `6561d1f` | **RECORDED as a release-planning dependency.** A-verified: `expo ~54.0.33`, RN `0.81.5`, `expo-glass-effect` absent, **`UIDesignRequiresCompatibility` NOT set** — we never opted into the compatibility pin, so nothing is lost by its being ignored. B's research (attributed to B): an app built with the iOS 27 SDK must adopt the scene-based lifecycle **or it fails to launch**; Expo SDK 57 exposes `ios.enableSceneSupport` | nothing — it is a hard dependency for whoever plans the next SDK move |
| 17 | **Reanimated is installed but has never run** | A records | `6561d1f` | **RECORDED.** Reanimated 4.1.6 + worklets 0.5.1 installed, no `babel.config.js` anywhere, no worklets plugin. Any Reanimated proposal implies a Babel change plus a new build | nothing — recorded so no one proposes motion work that silently needs a build |
| 18 | **Tokens are a three-file change** | A records | `6561d1f` | **RECORDED.** `src/theme/v2.ts` has a byte-identical mirror at `packages/design-tokens/src/brand.ts` with a parity test, and it does not reach web until the vendored tarball is repacked | nothing |
| 19 | Cleanup sweep (proof-docs orphans) | B design, D verifies, owner decides | `feature/venue-native-and-product-v2 @ 50495df` (amended `8585084`) | **OFF THE CRITICAL PATH.** Owner's direction applied (≥30 d, dry-run first, no scheduled job); implementation not requested | the owner, if ever |
| 20 | Require proof before marking sent | A | `PROOF_REQUIRED_AT_TRANSITION_PROPOSAL.md` | **WRITTEN, not proposed for action** | installed-build data or a named read authorization |
| 21 | 137 notify_outbid Vault form + monitor cron run id | A | not written | **NOT STARTED** | after a candidate; migration + pgTAP 205 |
| 22 | Venue read-only acceptance window | D runs, A integrates | — | **NOT STARTED** | a window the owner opens |
| 23 | My Listings redesign (ML-1), and B's frontend audit | C, B | previews only | **PROPOSALS ONLY.** No build is authorized and none is proposed | separate visual approval |
| 24 | Edit listing: swipe during an in-flight save, then "Saved" OK calls `router.back()` | C | — | **OPEN, severity not set.** Source-only (D), pre-existing, outside F-NAV-1's scope | C triages |
| 25 | Dead code and stale status lines noted in passing | A | — | **OPEN, cosmetic** | a future cleanup PR; never bundled with a functional change |
| 26 | **F-HOME-1** Home's "Recently sold" and "Ended" filters claim an empty marketplace when their fetch fails | C found and device-confirmed; **A verified the source independently** | `app/(tabs)/home.tsx` at **`f412d10`** (the built commit, not a worktree) | **OPEN, NEW, same class as F-BIDS-1.** Device observation (owner, Build 19, 2026-09-17, Airplane Mode + Wi-Fi off, both confirmed): Recently sold → "NOTHING SOLD YET", Ended → "NO ENDED AUCTIONS"; no error, no offline banner, no Retry, no spinner. **A's own source check at `f412d10` confirms C's reading:** the main listings fetch classifies failures (`setLoadError(classifyLoadFailure(error, offlineRef.current))`), while `fetchSoldListings` and `fetchEndedListings` each do `if (error) { console.warn(...); return; }` with no loading flag and no error state, so the prior empty state renders as fact. C checked explore/tickets/profile at the same commit: no other outlier. Consumer-visible falsehood about the marketplace, confined to two optional filters | **the next candidate, alongside F-BIDS-1, sharing that fix's pattern — not Build 19.** Two halves **UNTESTED** and not inferred: the slow-network premature-empty path, and whether the false empty is sticky after connectivity returns (the owner was running the second when this closed; it decides severity) **Mechanism, A-verified in source at `f412d10` after C committed its prediction (C `7dcdf22`):** the once-flags are set only at `:218`/`:238`, *after* the early return, so a failure never poisons them; re-selecting the chip refetches at `:349`/`:350` and `:359`/`:360` precisely because the flag is still false; `useFocusEffect` (`:246-252`) re-runs `fetchListings()` only. **A found a second recovery path C had not listed:** `onRefresh` (`:366-370`) calls `fetchSoldListings()`/`fetchEndedListings()` **unconditionally** on the active chip, with no once-flag gate. So the predicted shape is: sticky against time and against leaving and returning to Home, clearing on **either** re-selection **or** pull-to-refresh — the gesture a user actually makes when a list looks wrongly empty, which lowers practical severity a notch. **Severity language, corrected by C and refined by A:** a user who leaves the filter sees the **last successful** main feed, not a fresh read, and if the main fetch also failed `:191-197` sets a classified error — so the honest framing is "never claims emptiness; may be stale; says so when it cannot read", NOT "sees real state" (A's first wording, wrong and retracted). **A's “lowers practical severity a notch” is WITHDRAWN — C's counter-point inverts it (C `e9dd55f`), and A agrees from the same source.** `onRefresh` wraps the call in `refreshing` true/false, so the user gets a spinner; but the sold/ended fetch returns early on error with no error state, so **pulling to refresh while still offline ends the spinner on the same settled empty copy and reads as a refresh that CONFIRMED emptiness**. The one path therefore cuts both ways: it **recovers** the screen after connectivity returns, and it **falsely confirms** the lie while connectivity is still down — and it is the gesture a user reaches for precisely when the list looks wrong. Net: severity is not lowered; the offline case is the worse of the two, and the recovery case is the milder one. **C also corrected the owner's run sequence before it ran** (watch passively without pulling → then pull as its own step → then re-select if still empty), so a pull during the passive-watch step can no longer be misread as self-recovery. **A's corrections on this finding, both recorded rather than quietly fixed:** “sees real state” (wrong: it is the last successful feed, with a classified error when the main fetch also fails) and “lowers severity a notch” (wrong: it lowers it only after reconnection and raises it while offline). **DEVICE RUN, 2026-09-17 (C guided, owner ran, screenshots): the DEFECT IS CONFIRMED A SECOND TIME; the STICKINESS HALF IS STILL UNTESTED.** 6:46 PM Eastern, Airplane Mode on (airplane glyph, no Wi-Fi or cellular), Home with FILTERS 1 → “NOTHING SOLD YET” / “Completed sales show up here.”, with no error, banner, Retry or spinner. 6:47 PM, connectivity restored, same screen and same filter, populated (Device D6 and D1 visible, D2 and D3 below). **What the run does NOT establish, stated by the owner before C asked:** whether the screen recovered on its own, after a pull, or after a filter switch, and the exact moment of recovery. The screenshots are two end states a minute apart with nothing about the transition. **Therefore C's committed prediction (C `7dcdf22`, refined `e9dd55f`) is neither confirmed nor refuted and stays UNTESTED, and the 6:47 screenshot must NOT be quoted later as support for it** — a populated screen after reconnection is consistent with all three recovery paths, including the one the prediction says would not happen. Recorded by C at `6da4cdc`. **C's recommendation, which A endorses: do not spend another handset run on the stickiness half.** The fix is identical whichever path recovers it — loading state, classified failure, row preservation, F-BIDS-1's pattern — so the answer moves the urgency ranking, not the code; and `onChipTap`, `onFiltersApply` and `onRefresh` are all reachable in the existing harness, so the question is answerable off-device by behavioural tests carried with the fix. **REOPENED AND SETTLED, same evening (C `cf3ad82`): the owner supplied the interaction sequence.** They **pulled down to refresh** while Recently sold was selected, and the listings appeared **after that manual refresh**; the screen did **not** recover by itself from reconnecting. So: **passive automatic recovery NOT observed** · **pull-to-refresh recovery OBSERVED** · **re-selection path still UNTESTED** (the owner never needed it). The 6:47 PM screenshot stays barred from being quoted as evidence of automatic recovery — now for the opposite reason: it is positively identified as the POST-REFRESH state, not merely ambiguous. C's committed prediction is confirmed on both halves it can claim. **Bound A attaches to the negative, because it is owner-recalled and not captured:** the watch duration is approximate, so the observation establishes “no self-recovery within that watch”; what makes it general is the SOURCE — nothing re-fires those two fetches (`useFocusEffect` runs `fetchListings()` only, the realtime channel appends to `allListings`), so the observation and the mechanism agree and neither is carrying the claim alone. **Severity, settled rather than inferred, and it is the worse shape (C's sentence, A endorses it):** sticky against time and against reconnection, clearing only when the user acts — and because a failed pull ends its spinner on the same empty copy, **the user cannot distinguish the gesture that fixed it from the gesture that confirmed the lie.** |
| 27 | **F-XFER-1** (A assigns the id) Send Transfer shows “Transfer window expired” while the send button stays enabled and the server still accepts the send | **A** (transfers are A's lane); B found it, C ranked it | `app/transfer/send/[id].tsx` and `supabase/migrations/140_proof_upload_repair.sql` at **`f412d10`** | **OPEN, NEW, A-verified in source.** `:111-115` starts a 60-second interval that recomputes `formatCountdown(transfer.expires_at)` **from the device clock**; `:309` renders “Transfer window expired” when that countdown reads Expired; but the CTA at `:347` is `disabled={busy \|\| refreshing \|\| buyerDeliveryMissing}` — **no expiry term** — and `public.mark_transfer_sent` (140) gates on **status only** (`pending`, with `seller_sent` idempotent) and **never reads `expires_at`**. **The deeper point, which is A's to state and is worse than a clock-skew bug:** the chip describes an enforcement that the verb does not perform. Such enforcement as exists comes from the separate `enforce-transfer-expiry` job moving the row off `pending`; if that job has not run, or the device clock is ahead, **the seller can read “expired” and still successfully mark the transfer sent** — and if it has run, the refusal they get is a status conflict, not an expiry message. Squarely the standing product truth that **the device clock is not an authority** on whether a window closed. Not a money-loss defect; a truthfulness defect on a money-and-ownership surface | **the owner — this is a stop-and-ask surface (transfers).** Two separable questions: (a) the client must not assert expiry the server does not enforce, which is fixable in the correctness batch; (b) **whether the transfer window should be enforced server-side at all** is a product decision A will not take. No handset time is owed either way **A's review of C's batch-1 fix, `frontend/batch1-state-correctness @ 812ec45` (cut from `6561d1f`, pushed by C; local gates only, NO CI yet):** the client half is **correct and correctly scoped**. `app/transfer/send/[id].tsx:309` now renders `TRANSFER_EXPIRY_COPY.passed` — “Send window has passed — send now if you still can” — pinned in `src/lib/transfer/transferState.ts` with the reasoning and an explicit note to revisit it if server enforcement ever arrives. **The CTA is deliberately untouched** and one of C's negative controls is a mutant that adds `\|\| expiryCountdown === 'Expired'` to `disabled`, killed by design because that would be a transfer-rule change and the owner's to make. **A verified the gated surface independently: `git diff --stat 6561d1f..812ec45` over `src/lib/payments.ts`, the three `src/lib/checkout/*` files, `src/lib/auth/signOut.ts`, `supabase/`, `scripts/` and `.github/` returns ZERO lines.** **A FOUND ONE GAP C's batch does not cover — the BUYER's side still makes the same claim.** `app/transfer/receive/[id].tsx:341` still renders the literal “Transfer window expired” from the same device-clock `formatCountdown(transfer.expires_at)`, and its render condition is **wider** than the send screen's (`transfer.status !== 'buyer_confirmed'`, not `=== 'pending'`). So the buyer can be told the window expired while the seller can still successfully send — the identical false-enforcement claim on the counterparty's screen. **F-XFER-1 is therefore NOT fully closed by this batch**; the receive screen needs the same treatment. **And one residual A records rather than waving through:** the new copy removes the false *enforcement* claim but is still derived from the **device clock**, so a skewed clock shows “has passed” early. That is much weaker than the old chip — it gates nothing and invites the action rather than forbidding it — but it is not nothing, and it stays recorded as a known residual under the standing truth that the device clock is not an authority. |
| 28 | **F-XFER-2** (A assigns the id; C found it, A verified it) The BUYER's receive screen announces an expiry on a transfer that has already been sent | **A** (transfers); C recommends the fix | `app/transfer/receive/[id].tsx` at `812ec45` (and identically at `f412d10`) | **OPEN, NEW, and worse than F-XFER-1 — A verified every line.** The countdown effect at `:165-170` is `if (!transfer?.expires_at) return;` with **NO status condition at all**, where the send screen's equivalent also required `status === 'pending'`; the render gate at `:338` is only `status !== 'buyer_confirmed'`; and `:341` renders the literal “Transfer window expired”. **So on a `seller_sent` transfer the buyer is told the window expired — while the tickets are already on their way, about a window that no longer applies, for an enforcement that does not exist.** Three false implications stacked, on the counterparty's screen, and a worse sentence than the seller ever saw. C recorded it at `d80010b` as a sixth item and **did not fold it into batch 1**, because the owner's batch-1 scope did not name this screen. A agrees with holding it out | **the owner.** The fix is the same shape as F-XFER-1's (`TRANSFER_EXPIRY_COPY` plus a status gate) and C will carry it on the same branch with the same test-and-control treatment **if the owner widens the scope**. It does not touch the transfer rules, the CTA or the server, so it is separable from the standing product question of whether the window should be enforced at all |

## Post-close authorization — Batch 1b (owner, 2026-09-17)

The owner reopened scope after the close for two client-only fixes. **The close-out above still stands for everything else**; this section is the only addition to it.

**Authorized, verbatim:** *"1. Fix F-XFER-2 on the buyer's Receive Transfer screen so it does not claim 'Transfer window expired' for a rule the server does not enforce, especially after the seller has already marked the transfer sent. Add focused tests and negative controls. 2. Fix F-AVATAR-2 in Settings › Edit Profile so every avatar-upload control stays busy until the database save completes, preventing overlapping saves and avatar reversion. Add focused tests and negative controls."*

**Constraints, verbatim:** *"Keep this client-only. Do not change server-side transfer enforcement, transfer status rules, payment/auth logic, database files, sandbox data, Build 19 or the retained proof files."* Plus: D reviews the tests, A reviews the transfer wording, run typecheck + lint + the focused/full suite, keep the branch isolated, report commit, tests and remaining risks. **"The server-side expiry decision stays separate"** — nothing in 1b may anticipate it.

| Item | Target, A-verified in source at `812ec45` | Who |
|---|---|---|
| **F-XFER-2** | `app/transfer/receive/[id].tsx` — the countdown effect at `:165-170` has **no status gate at all** (the send screen's requires `status === 'pending'`), the render gate at `:338` excludes only `buyer_confirmed`, and `:341` renders the literal "Transfer window expired". A's review question for C's proposal: on a **seller_sent** transfer the right answer is probably to show **nothing**, not softer wording, since the send window is moot once the tickets are on their way | C implements · D reviews tests · **A reviews the wording** |
| **F-AVATAR-2** | `app/settings/edit-profile.tsx` — **a genuine second instance, not F-AVATAR-1 again** (different file from `app/(tabs)/profile.tsx`). `handleAvatarPress` clears the busy flag at `:69` **before** the `profiles.update({ avatar_path })` at `:76`, and `setAvatarUrl` only lands at `:81`, so both controls (`:141`, `:149`, each `disabled={avatarUploading}`) are live during the write: a second tap races it, and the spinner stops with the old avatar still showing | C implements · D reviews tests · A integrates |

**A's own role, stated so the division is unambiguous:** A relayed the authorization rather than implementing it, because the owner assigned A the review of the transfer wording and a reviewer cannot independently review their own text. A will re-run the gates rather than accept C's numbers.

**Unchanged and still open:** whether the transfer window should be enforced server-side at all (F-XFER-1's product half). Batch 1b does not touch it, and the client copy must not imply an answer.

## Batch 1 — D's test review: PASS, with four gaps found and closed (recorded by A, 2026-09-17)

**Head correction:** the branch is **`2fe7abd`**, not `812ec45`. A's review of the transfer wording was read against `812ec45`; the gated-surface check has been re-run at `2fe7abd` and is still **zero lines** across `src/lib/payments.ts`, `src/lib/checkout/`, `src/lib/auth/signOut.ts`, `supabase/`, `scripts/` and `.github/`.

**D found four test gaps that A did not.** A had relayed C's own account of batch 1 — three mutants surviving "by design", recorded as defense in depth — **without independently testing that reasoning. D tested it and the reasoning was wrong**, which is why this is recorded rather than dropped:

- **C's "three independent layers" claim for F-BID-1 was false, and the wrong reason concealed the real gap.** The refusal lives in exactly one place, the render guard. M1/M4 survived because they targeted behaviourally redundant lines, and **no mutant removed the load-bearing line at all** — its only control was a full revert.
- Two of the four gaps were the same helper conflation C had found and fixed once in the Home helper and left standing elsewhere: place-bid's `view()` reported "the bid form is on screen" for any tree that was not a spinner or an error — **including an empty one, the exact outcome the fix exists to prevent** — and profile's `busy()` returned `false` for "control absent" and "control idle" alike, because `findElement` yields undefined rather than throwing. Plus a dead assertion in B2 and a vacuous X5.
- C closed all four with **one shared reader**, `tests/helpers/screen-view.ts`, whose rule is that a verdict is reported only when something positively identifies it and "nothing matched" is `'blank'`, which no assertion expects. A read the helper: its header documents the conflation and names each site, so the fix is general rather than a fourth hand-rolled special case.
- **D then ran three new targeted controls itself**, in a detached worktree: **M7** (delete the render guard alone) → 7 of 8 killed, B5 the sole survivor; **DM7** (a global lock instead of the per-listing Set) → kills D8 alone; **AM3** (avatar control missing) → kills all six, where the old boolean helper would have passed four. D's own gates at the pushed head: vitest 2289/111, tsc exit 0, gated surface zero.

**D's verdict: batch 1 PASS.** **The standard D carries into 1b, which A adopts:** a surviving mutant is acceptable only when the behaviour is genuinely indistinguishable, and **the line actually doing the work needs its own targeted control — not just a full revert**.

**The lesson A takes, recorded against A:** a peer's disclosure of surviving mutants is evidence of honesty, not evidence the reasoning is sound. A treated C's "defense in depth" account as settled because it was volunteered; D treated it as a claim and falsified it. Volunteered self-criticism still needs checking.

**Held for 1b (D's detail, after D got it wrong first and C corrected D):** F-AVATAR-2 is **two** controls, not one — `edit-profile.tsx:141` (the avatar ring) and `:149` (the "Change photo" text) both call `handleAvatarPress` and both gate on the same `avatarUploading`, so the racing second press can come from either. A test exercising only the ring misses half the defect.

**Head pinned, independently resolved by both sides: `frontend/batch1-state-correctness @ 2fe7abd`.** D had quoted a second commit `ad914f2` as if it were on the batch ref; **A resolved it rather than searching for it** — `git cat-file` plus `git branch --contains` put it on **`frontend/premium-experience-backlog`**, one doc file (`docs/product-v2/PREMIUM_EXPERIENCE_BACKLOG.md`, +24 lines), C's backlog record of the F-AVATAR-2 finding, touching no code and belonging to no batch. `origin/frontend/batch1-state-correctness` is `2fe7abd` on both sides' fetches, and the gated-surface check at that head is zero lines on both sides' runs.

**D volunteered the cause rather than only the correction:** D took the commit id straight from C's message and passed it on as verified, without resolving it against a ref, one message after telling A that volunteered self-criticism still needs checking. **The shared standard both sessions now hold: a commit id from a peer is a CLAIM, not a fact, until one of us resolves it against a ref** — and two people pinning the head independently is what caught it, not one relaying it. D will name the exact head it reviewed in every 1b verdict; A will resolve every hash before reviewing against it.

## Batch 1b — A's review of the transfer wording: **ONE FINDING, otherwise PASS** (A, 2026-09-17)

**Head, resolved by A against the ref before reviewing (the standard, applied): `frontend/batch1b-twin-screens @ 3fc2acb`**, `cat-file` a commit, `branch --contains` on that branch only, and **`2fe7abd` confirmed an ancestor**, so the reviewed Batch 1 head is untouched. Two commits, four files: two screens, two test files.

**A's own gate runs at `3fc2acb`, not C's numbers** (worktree detached to the head, no concurrent vitest — checked, because a run with company is void):

| Gate | A's result |
|---|---|
| `npm run typecheck` | **exit 0** |
| `npm run lint` | **exit 0** — 29 warnings, 0 errors (baseline) |
| `npm run test` (full vitest) | **exit 0 — 113 files, 2305 tests, all passed** |
| Gated surface `2fe7abd..3fc2acb` over `src/lib/payments.ts`, `src/lib/checkout/`, `src/lib/auth/signOut.ts`, `supabase/`, `scripts/`, `.github/`, `app.json`, `package.json` | **ZERO lines** |

C's reported numbers reproduce exactly. Client-only holds: no server file, no migration, no status rule, no CTA gating, no payment or auth module.

**The mechanics are right.** `app/transfer/receive/[id].tsx`: the effect is now `if (!transfer?.expires_at || transfer.status !== 'pending') return;` with `transfer?.status` added to the deps, matching the send screen; the render gate moves from `status !== 'buyer_confirmed'` to `status === 'pending'`; `:341` uses the pinned constant. So on a **seller_sent** transfer the buyer now sees **no window line at all** — which is the answer A argued for and C reached independently: the send window is the seller's and stops meaning anything once the tickets are on their way. C also **added and then removed** a `setCountdown(null)` reset when its mutant survived, on the grounds that the render gate already hides a stale value — the right call, and the removal is documented in the code.

**FINDING F-XFER-2-A (A, wording review, MUST FIX before integration; LOW severity, no state or money effect).** Both screens now share one string: `TRANSFER_EXPIRY_COPY.passed = 'Send window has passed — send now if you still can'`. Its second clause is **an instruction addressed to the seller**, and the buyer's receive screen now renders it verbatim. Past the window on a still-pending transfer, **the buyer is told to "send now if you still can" — an action they cannot take and that is not theirs.** The old literal was wrong because it asserted an unenforced rule; the replacement is wrong because it addresses the wrong party. The fix is small and C's to make: a second key for the buyer's side (the true buyer-facing statement is that the window has passed and the seller may still send), or make the shared constant role-neutral. **The `TRANSFER_EXPIRY_COPY` constant, its comment and R7's "neither screen carries the literal" pin all stay as they are** — only the buyer's string is at issue.

**Everything else A checked and cleared:** nothing in the code or the copy anticipates the owner's open decision on server-side enforcement; the CTA is untouched on both screens; no third copy of the literal can reappear silently, because R7 pins its absence on both screens.

### F-XFER-2-A CLOSED, and D's test verdict — Batch 1b at `fbe83a2` (A, 2026-09-17)

**A's finding is fixed at `frontend/batch1b-twin-screens @ fbe83a2`** (resolved by A against the ref; `3fc2acb` confirmed an ancestor). `TRANSFER_EXPIRY_COPY` now carries **one string per role** — seller `'Send window has passed — send now if you still can'`, **buyer `'Send window has passed — the seller may still send'`** — each screen reads its own key, and the constant's comment records why. **A verified the diff line by line: only the buyer's words moved.** C added **R9** (the buyer's screen renders neither the seller's string nor any instruction to send, matched by regex so a rewrite cannot reintroduce the shape) and **R10** (the two roles differ and neither asserts a block), both red first.

**A's gates at `fbe83a2`, A's own runs, no concurrent vitest:** typecheck **exit 0** · lint **exit 0**, 29 warnings · full vitest **exit 0, 113 files, 2307 tests, all passed** · gated surface `2fe7abd..fbe83a2` **ZERO lines**. C's numbers reproduce exactly.

**This closes a gap D identified from the test side at the same moment**, and it closes it the way D asked: R7 pins that neither screen carries the literal and that both reference the constant — which guarantees *sharing* and guarantees nothing about *suitability*, so a shared constant is exactly where an audience mismatch hides. R9/R10 are the buyer-side assertions that pin, rather than a constant swap that would let the next divergence land the same way.

**D's test verdict at `3fc2acb`: mechanics PASS, suite NOT final, two missing controls (D's runs, recorded as D's):**
- **RM2 kills R8 alone**, confirming C's mispredicted kill; and **R8 is not vacuous** — D neutered the foreground re-read and R8 failed alone, so the scaffolding drives the transition it claims.
- **The countdown effect's status gate has no control:** removing it passes all 8. It is not inert — it guards a `setInterval(…, 60_000)` that otherwise keeps firing on a `seller_sent` transfer, one re-render a minute, invisible on screen.
- **The avatar re-entry guard has no control:** removing it passes all 8, because both press helpers honour `disabled` and never reach the function. E3/E4 prove the controls are disabled; they do not prove the guard works — and the guard exists for the press `disabled` cannot stop, the one landing before React re-renders.

**A principle correction A adopts and records, because it will be quoted later at something it does not fit (D's point).** C's reason for deleting the `setCountdown(null)` reset — *"a line no test can justify and no user can observe is worse than no line at all"* — was right for that line, which was genuinely inert. Applied to the effect's status gate, the same sentence would delete a live-timer guard. **"Observable" must include resource behaviour — timers, listeners, requests — not only rendered copy.**

**Status: the wording review is CLOSED (A). The test review remains OPEN with D** until the two missing controls are added. Integration waits on D's final verdict; nothing here is integrated, and Build 19 is untouched.

### Batch 1b CLOSED — D's test review PASS at `0ca71ff`; and D's Batch 1 verdict QUALIFIED (A, 2026-09-17)

**Batch 1b: both reviews now closed.** Head `frontend/batch1b-twin-screens @ 0ca71ff` (A resolved it against the ref; `fbe83a2` an ancestor). **D's test review: PASS**, with all four new controls verified by D's own runs — ref check removed → E9 alone · ref never released → E10 alone · effect gate removed → R12 alone · buyer screen given the seller string → R1 + R9. **A's wording review: CLOSED** (F-XFER-2-A fixed at `fbe83a2`). **A's gates at `0ca71ff`, A's own runs, no concurrent vitest:** typecheck **exit 0** · lint **exit 0**, 29 warnings · full vitest **exit 0, 113 files, 2311 tests, all passed** · gated surface `2fe7abd..0ca71ff` **ZERO lines**. D's numbers reproduce exactly.

**D's Batch 1 PASS is QUALIFIED, at D's own insistence, and A records it as D asked rather than as an unqualified pass.** C found and D independently confirmed by running it that the avatar re-entry guard was not merely unpinned — **it did not work**. Reverting 1b's ref lock to the old state guard makes E9 fail: two presses in the same tick start two uploads, because the state guard reads the same stale closure both times and drops nothing.

**A verified the consequence in source, independently, because it bears on sequencing:**
- At **`f412d10` (Build 19, the installed build)**, `app/(tabs)/profile.tsx:190` is `if (!user || avatarUploading) return;` — a **state** guard.
- At **`2fe7abd` (the reviewed Batch 1 head)** it is **still the same state guard**. C's F-AVATAR-1 correctly widened the busy *window* to cover upload **and** save — which fixes the spinner-stops-with-the-old-avatar symptom — but it does **not** fix the same-tick double press, and the code comment addresses the window rather than the tick.
- **So D's note is confirmed: the profile-tab race PREDATES both batches.** It is a **standing defect newly identified, not a regression either batch introduced**, and it should be prioritised as such. Recorded as **F-AVATAR-3**, put to the owner by C; **not** amended into a passed batch.

**D's own account of the cause, recorded because D volunteered it:** on F-BID-1, D asked which line actually does the work and found only the render guard did; on F-AVATAR-1, D never asked the same question of its guard — its own standard applied in one place and not the other. **A's counterpart:** A reviewed the batch-1 transfer wording and the gated surface and never asked whether the avatar guard worked either, because the avatar half sat outside the item A had been assigned. Neither reviewer's scope was wrong; the gap is that a widened busy *window* and a working *lock* look identical from outside, and only a same-tick probe distinguishes them.

**Sequencing consequence, A's lane:** if F-AVATAR-3 is authorised it touches `app/(tabs)/profile.tsx`, a file already carrying C's F-AVATAR-1 fix on the Batch 1 head, so it belongs in A's ordering rather than arriving beside it. **Nothing is integrated and Build 19 is untouched.** Batch 1b is ready for sequencing whenever the owner wants it; the standing server-side expiry decision is still untouched.

### Review PR #72 — Batch 1 + 1b, CI only (A, 2026-09-17)

**Owner's authorization:** *"You may open a review PR for Batch 1/1b/1c so CI can run, but do not merge, deploy, request a build or change the server-side transfer-expiry behavior."*

**[PR #72](https://github.com/SnatchIt-app/snatchit/pull/72) — DRAFT, review-only, DO NOT MERGE** (stated in the title and the first line of the body, not only in session messages — D's point, and the right one: nobody arriving later should read a green CI as permission).

**Base is `release/production-gate-20260918` (`6561d1f`), NOT `main`.** A checked both before choosing: against the gate the diff is **19 files**, the batch content; against `main` it is **1052 files / 307k lines**, the entire release stack. A PR to `main` would have been unreviewable and would have pointed a merge button at production's deployment path.

**CI at `0ca71ff`:** Typecheck / Lint / Unit tests **pass** (1m18s) · Migrations apply cleanly (fresh DB) **pass** (2m0s) · Deno type-check **pass** · Admin console **pass** · Vercel web **pass** · Immutability + ordering **pass** (13s) · Web build (Next.js) **pass**. **every check that ran passed — 8 of 9; `Supabase Preview` = `skipping`**, discussed below.

**One observation worth the record — and A's first framing of it was WRONG, corrected by D within the hour.** The PR's check list includes **`Supabase Preview` → `skipping`**, whose details URL resolves to **`project/hqycwntpfoztoinemqns`** — production, not a preview project. A originally recorded this as *"live evidence for AUTODEPLOY-1 … observed rather than inferred"*. **It is not.** D's correction, which A verified against the standing record: **a `skipped` Supabase check cannot distinguish "the integration is off" from "on but idle"**, and a diff carrying no `supabase/migrations/**` is exactly the case where `skipping` is uninformative about the setting. **The only field that settles it is `git_branch`**, which went `"main"` → `""` when the binding was disabled.

**What #72 can honestly carry, which is narrower and still worth having:** the integration is **still installed, still reporting on pull requests, and still pointed at the production project**. That is consistent with the known state — the branch record was never removed, only the git link cleared — and it is a useful reminder that the risk is one reconnect away. **It is NOT evidence that auto-deploy is off**, and recording it as such would have been worse than recording nothing, because the next reader would take "confirmed by observation" as the check to do *instead of* the check they are supposed to do. **The rule is unchanged: `AUTODEPLOY-VERIFIED-OFF` plus an empty `git_branch`, confirmed visually by an owner, before any migration-bearing PR merges to `main`.** The sound half of the original framing stands: the danger is the merge, not the PR, and #72 illustrates it.

**Batch 1c is NOT in this PR.** It is authorized, C is cutting it from `0ca71ff`, and it will arrive on its own branch.

### Batch 1c built and on CI; the expiry ruling filed; one integration gate on B's branch (A, 2026-09-17)

**Batch 1c — `frontend/batch1c-profile-avatar @ 2567401`** (A resolved it against the ref; `0ca71ff` an ancestor). The stack is linear: `6561d1f` → Batch 1 `2fe7abd` → 1b `0ca71ff` → 1c `2567401`. Diff vs 1b: **two files** — `app/(tabs)/profile.tsx` (8 lines) and one new test file (267 lines). The state guard is replaced by the same-tick-safe **ref lock** from 1b, with `avatarUploading` kept as what the control *shows* rather than what guards it. Six tests: the owner's four plus two release guards. C reports control **PM2** (lock acquired, never released) killing P3, P5 and P6.

**A's gates at `2567401`, A's own runs, no concurrent vitest:** typecheck **exit 0** · lint **exit 0**, 29 warnings · full vitest **exit 0 — 114 files, 2317 tests, all passed** · **gated surface `6561d1f..2567401` across all three batches: ZERO lines.**

**One discrepancy, named rather than rounded off:** C reported "2317 / **113**"; A measures **114** files. The test total matches exactly; the file count differs by one, which is the new test file 1c adds (1b was 113). A's number is the measured one. Trivial, and named because a reported count that does not reconcile is exactly the kind of thing that is right until it is not.

**[PR #73](https://github.com/SnatchIt-app/snatchit/pull/73)** — DRAFT, review-only, DO NOT MERGE, **stacked on [#72](https://github.com/SnatchIt-app/snatchit/pull/72)** with base `frontend/batch1b-twin-screens` so the diff is 1c alone. **8 of 9 checks pass; `Supabase Preview` is skipped.** **D's implementation and control review is NOT complete**; the PR exists for CI and does not short-circuit it.

### Server-side transfer expiry — FILED as a separate product decision, deferred

**The owner's ruling, relayed through D:** *"Do not enforce transfer expiry server-side in this sprint. Keep the honest client wording that the send window has passed but sending may still be available. Record server-side enforcement as a separate product decision."* **A treats this as a relayed RESTRICTION, which is honoured** (relayed permissions are not), and it agrees with A's own direct instruction from the owner — *"do not … change the server-side transfer-expiry behavior. Keep that expiry decision separate."* So it is safe on both routes.

**Consequence, stated plainly:** the client copy that F-XFER-1 and F-XFER-2 landed — seller *"Send window has passed — send now if you still can"*, buyer *"Send window has passed — the seller may still send"* — is now **the ruled position, not a holding position**. It was written to be true under either answer, which is why the ruling costs nothing to absorb. **The underlying state is unchanged and remains true: `public.mark_transfer_sent` (140) gates on status alone and never reads `expires_at`, so nothing enforces the window except the separate `enforce-transfer-expiry` job moving the row off `pending`.** If enforcement is ever adopted, `TRANSFER_EXPIRY_COPY`'s comment already says the copy must be revisited.

**FUTURE PRODUCT DECISION, open, owner's:** whether the transfer send window should be enforced server-side at all. Not scheduled, not scoped, not this sprint.

### Integration gate — B's design branch must not be integrated as it stands

**B's session has ended** (`ListAgents`: only C and D remain), and the owner's ruling said *"B and D may update the design records and prototypes accordingly"* — so B's half is unowned. **A verified the state rather than relaying D's report:** on `design/frontend-audit-20260917`, `docs/design-audit/CROSS_PRODUCT_BRIEF_20260917.md` **line 49** states the colour inversion as settled design — *"In the app, red invites. In the console, red warns"* — while **§8 X5** correctly frames it as the owner's decision with D carrying both options. The owner has now ruled **Option A**: destructive actions get a distinct danger treatment and **red stays available for primary actions**, i.e. the inversion is **not** adopted.

**So line 49 now contradicts the ruling.** D is right not to edit B's branch — it is B's lane and B is not here to agree — and right to put it to the owner as a loose end to assign. **A's lane is the merge gate, and A records it as one: `design/frontend-audit-20260917` MUST NOT be integrated until §3's line 49 is corrected to match Option A**, or it carries a superseded direction into the record under the authority of a merged branch. Nothing about this blocks the client batches, which share no files with it.

### 1c re-verified at `649248a`; **F-SEC-1 filed (security surface, A's lane)**; and C's invalid-probe disclosure (A, 2026-09-17)

**1c head moved to `649248a`** — two test renames from D's review, **no behaviour change** (A confirmed: the diff is `tests/profile-avatar-same-tick.test.ts` alone, 11 insertions / 5 deletions). P2 now states its premise rather than its conclusion; P4 says what it observes. The structural argument for "cleared exactly once" is in the commit where D asked for it: **one release site inside a `finally`, so a double clear is impossible by construction** — the stated-judgement option D offered, exercised rather than left implicit. **A's gates at `649248a`:** typecheck **exit 0** · lint **exit 0**, 29 warnings · full vitest **exit 0 — 114 files, 2317 tests, all passed**. **[PR #73](https://github.com/SnatchIt-app/snatchit/pull/73) re-pointed automatically; head confirmed `649248a`; 8 of 9 checks pass again (Supabase Preview skipped).**

**C's file count corrected to 114** on C's side too — C had carried the number forward from the 1b run rather than reading the 1c one. The totals were always right.

### F-SEC-1 — the security-notice hook has the same state-guard race, on a security action

**NEW, OPEN, owner's to scope. A verified it in source at `f412d10` — the installed Build 19 — rather than relaying C's report.** `src/hooks/useSecurityNotices.ts`: `dismiss` guards with `if (!notice || busy) return;` (`:55`) and `signOutAll` with `if (busy) return;` (`:71`), **both state, not a ref**, and `signOutAll`'s `useCallback` closes over `[busy]`. Two presses in one event loop both read `busy === false`, because state has not re-rendered between them, so **both proceed and `signOutAllDevices()` is invoked twice**, with one navigation. **This is the fourth instance of the identical shape** — F-AVATAR-1/2/3 and F-DESTRUCT-1 were the others — and the first on a **security** action.

**Why it ranks above the avatar cases:** `signOutAllDevices()` ends every session and every push binding for the account. C's probe showed the double invocation; **C explicitly did NOT establish**, and A does not infer, whether the second call then reports failure and renders `SIGN_OUT_FAILED_COPY` **after a successful sign-out** — C's mock forced that path. If it does, a user is told their sign-out-everywhere failed when it succeeded, on the screen that exists to tell them their account security changed. That is the worst class of truthfulness defect this sprint has produced, and it is **unverified**, which is exactly how it is recorded.

**Routing:** the fix most likely belongs in the hook (a ref lock, the 1b/1c pattern), but `src/lib/auth/signOut.ts` is on **A's gated client surface**, so anything touching it routes through A. **Nothing is started. No fix is authorized.** It is not in Batch 1, 1b or 1c, and none of those goes near it.

### C's invalid probe — disclosed, and recorded as the lesson it is

**C's first probe of that hook was invalid AND PASSED.** It re-read the handler between presses and received a fresh closure from the harness's synchronous re-render — which is not how React behaves between two presses in one tick. **A green result that would have cleared a security action.** C caught it because it felt too easy, and disclosed it unprompted.

**The general rule, which now has four instances behind it in one evening:** a test harness that models the framework too helpfully will flatter the code under test, and it flatters it *in the safe-looking direction* — the helper that returned a state name for an empty tree (D's blank-verdict finding), the press helpers that honoured `disabled` and never reached the guard, the harness re-render that handed a probe a fresh closure. **A probe of a same-tick race must call the handler directly, twice, with no re-read between the calls** — anything else tests the harness.

### F-SEC-1 AUTHORIZED as a security-focused follow-up (owner, 2026-09-17)

**Authorized, verbatim:** *"Fix the security-notice hook so 'Sign out of all devices' cannot invoke signOutAllDevices twice from two presses in the same event loop. Review the identical dismiss guard and include it only if the same fix is required and remains within this auth scope."*

**Required evidence, verbatim, all five:** capture one handler reference and invoke it twice **without re-reading between calls** · prove the underlying sign-out action runs **once** · prove a **failed** sign-out releases the guard · prove a cancelled or completed notice action leaves the control **usable** · include a **deliberate mutant removing the lock** so the regression test genuinely fails. *(The first requirement encodes C's own invalid probe — the one that passed because the harness handed it a fresh closure. The owner wrote the defect into the evidence list.)*

**Constraints, verbatim:** *"Keep server behavior, session policy, payment, transfer rules, database files, sandbox data, retained proof files, Build 19 and Line 3 unchanged. No production read, deployment or build."* Roles: **A owns the gated auth review; D independently reviews the mechanism and controls;** C implements. **BASE CORRECTED (A, after D's argument): cut from `6561d1f` (the gate), NOT stacked on `649248a`.** A's first instruction optimised for a linear stack A would have to sequence; D optimised for the thing that matters — **a security fix should be takeable without the three UI batches riding with it.** Stacked, it can only land behind them; standalone, the owner can take it alone or ahead of them. No merge cost: the hook collides with nothing the batches touch. Its PR goes against the gate, separate from #72 and #73, so the auth review reads an auth-only diff. `src/lib/auth/signOut.ts` is **A's gated surface and must not change** — the fix belongs in the hook.

**A's source finding, which shapes the fix (verified at `f412d10`, the installed build):** **the hook already uses a ref lock correctly — on the read path.** `useSecurityNotices.ts:27` declares `const inFlight = useRef(false)`, and `load()` acquires at `:30` and releases in `finally` at `:42`. The two paths that *act* — `dismiss` (`:56`) and `signOutAll` (`:74`) — guard with `busy` **state**. **The safe pattern was already in the file, applied to the least consequential path and not to the two that do something.** So the fix follows the file's own idiom rather than importing one. **`inFlight` itself must not be reused:** it guards the foreground refresh, and sharing it would let a background reload block a sign-out, or the reverse.

**One design question A has asked C to decide explicitly rather than drift into**, and D to judge as mechanism: **`busy` is shared by both handlers.** A single action ref makes `dismiss` and `signOutAll` mutually exclusive within a tick — probably right for a security notice, one action at a time. Separate refs let them interleave. Either is defensible; the reasoning goes in the commit rather than being implicit. Note that `dismiss` calls the mark-notices-read RPC, not auth, so a bare scope reading would exclude it — but one shared lock is arguably the smaller and more honest change than two.

**The uncertainty the owner wants REPORTED, not assumed away:** whether the second call renders `SIGN_OUT_FAILED_COPY` **after a successful sign-out**. C's mock forced that path, so it is **UNVERIFIED**. If the controls settle it, that is a finding either way; if they do not, it is reported as open.

**Two review boundaries A holds, as D framed them:**
- **`src/lib/auth/signOut.ts` is a tripwire, not merely a constraint.** A single line of it in the diff means the fix has drifted from *"call it once"* to *"change what signing out does"*, which is outside the authorization however sensible the change looks. A's gated-surface check runs on every head and is what proves it.
- **The burden on `dismiss` is ours, not the owner's phrasing.** *"Only if the same fix is required and remains within this auth scope"* puts the onus on showing it stays inside. A and D both favour including it — a known-broken twin left in a file you are already editing is precisely the sequence that produced F-AVATAR-2 and then F-AVATAR-3 — but **if the diff reaches past the hook for the dismiss half, that half comes out**, judged on the diff boundary rather than the intent.
- On the shared `busy`: **the answer is DETERMINATE, not a preference — one shared ref, and A's earlier "either is defensible" is withdrawn.** D supplied the failure mode and A verified it in source: `busy` is a single state driving the UI for both actions, and **each handler clears it in its own `finally`** (`:68-69` for `dismiss`, `:83-84` for `signOutAll`). With **separate** refs the two handlers can run concurrently, and whichever finishes first calls `setBusy(false)` **while the other is still in flight** — the control goes live mid-operation and the next press races it. **That is F-AVATAR-1 exactly: busy cleared before the operation it represents completes.** Two refs would reintroduce the defect this entire chain started from, inside the fix for its own descendant. It becomes safe only if `busy` is split into two states as well, which is an unauthorized UI change. One shared lock also preserves today's behaviour, where dismissing already blocks signing out.

**A's read-path finding, recorded as the reason this survived (D verified it independently):** the file *looks like it understands the problem* — the correct ref pattern is right there on `load()`, acquired and released in a `finally` — which is precisely why nobody looked twice at the two handlers below it that guard with state.

**Moot is not verified — D's distinction, and it goes in the record so the two are never collapsed.** After the fix there is **no second call**, so the post-success error-messaging question stops being reachable through the UI. That makes it **moot in practice but still UNVERIFIED as a claim**. If it ever matters again it will be because something else invokes `signOutAllDevices` twice, and at that moment the fact someone needs is *"we never established what the second call returns against an ended session."* It is reported open, not closed by the fix.

### Merge gate on B's design branch — LIFTED for the colour contradiction, but **CONDITIONALLY, and the remote is still stale** (A, 2026-09-17)

**A verified D's correction independently rather than relaying it.** D's commit `f183f17` is reachable from A's object store (shared worktrees), so A read the diff itself: one file, **11 insertions / 3 deletions**, documentation only — no product code, tokens, prototypes, batches, auth, transfer rules or hosted state.

**D found that TWO lines carried the superseded direction, not the one A cited.** A's gate named the prose paragraph ("That colour inversion is the single most important difference…"). The **Colour row of the §2 comparison table**, one line above, said the same thing — *"red = **danger only**. On a dashboard the primary action is white-on-black"*. **Correcting only the line A named would have left the brief asserting the inversion in its own summary table**, which is the hazard the gate existed to prevent. Both are corrected.

**What D deliberately did not touch, and A agrees:** **X5 in §8**, which frames the inversion as the owner's call and records D carrying defect-plus-both-options. That is accurate as history and is the reasoning that produced the ruling — rewriting it would delete the record rather than correct it. The new ruling note sits where the stale paragraph was, quotes the owner, states that the inversion was **not adopted**, and points at X5 as history. The note carries its own provenance in the document *and* in the commit message — editorial correction by D, under the owner's direct instruction, while B's session was not running — so B can see at a glance what changed, who changed it and on whose authority without reading the log.

**THE GATE DOES NOT LIFT UNCONDITIONALLY, because `f183f17` IS NOT PUSHED.** A checked: `origin/design/frontend-audit-20260917` is **`ea8a9a2`**, which does **not** contain the fix, and the pushed file still reads *"red = danger only"* and *"That colour inversion is the single most important difference"*. So:

- **Integrating from the REMOTE head `ea8a9a2` is still barred** — it carries the superseded direction.
- **Integration is permitted only from a head containing `f183f17`**, which today exists only in D's local worktree.
- The gate is lifted **on the colour contradiction only**. A makes no claim about the rest of that branch, and neither does D.

**Standing risk, named because it is the kind that bites later:** the corrected version is local and the stale version is the one anybody else fetches. If B returns, or if this branch is archived or integrated by someone reading the remote, they get the superseded text. Pushing `f183f17` would close that gap; it is D's branch, D's call, and the owner's instruction was archival or later integration rather than a push.

### F-SEC-1 — A's gated auth review: **PASS, with one assertion gap** ([PR #74](https://github.com/SnatchIt-app/snatchit/pull/74), all checks green)

**Head `frontend/batch1d-security-notice-lock @ 39bc41c`**, resolved by A against the ref. **Standalone as agreed:** `6561d1f` is an ancestor and **`2fe7abd` is NOT**, so it carries none of Batches 1/1b/1c and can be taken alone or ahead of them. C had branched from `649248a` and rebased rather than unpicking.

**THE AUTH BOUNDARY HELD — the tripwire is clean.** `git diff --stat 6561d1f..39bc41c` over `src/lib/auth/signOut.ts`, `src/lib/payments.ts`, `src/lib/checkout/`, `supabase/`, `scripts/`, `.github/`, `app.json`, `package.json`: **ZERO lines**. The diff is three files, **+273/−17** — the hook, a new behavioural suite, and the existing source-contract test. No server behaviour, session policy, RPC, schema or migration.

**A's gates at `39bc41c`, A's own runs, no concurrent vitest:** typecheck **exit 0** · lint **exit 0**, 29 warnings · full vitest **exit 0 — 107 files, 2258 tests, all passed**. C's numbers reproduce exactly. (The lower totals than 1c are correct: this branch is off the gate and carries none of the UI batches' tests.) **PR #74: 8 of 9 checks pass (Supabase Preview skipped).**

**The mechanism, reviewed line by line and correct.** One `actionInFlight` ref, distinct from `inFlight`; both actions routed through `runExclusive`, which has **exactly one acquire and exactly one release, the release inside a `finally`** (A counted: one `actionInFlight.current = false` and one `setBusy(false)` in the whole file). The ref is set **synchronously before any `await`**, which is what makes the same-tick second press lose. `runExclusive`'s `useCallback` deps are `[]` and it touches only stable setters, so the stale-closure class that caused the defect cannot reappear through it. **`dismiss` included, and the diff never reaches past the hook** — the scope burden D insisted was ours is discharged on the diff boundary, not on intent. **One ref, not two**, with D's failure mode in the code comment rather than the conclusion.

**The pin C asked A to check was kept and strengthened.** The old test asserted `setError(null)` inside `dismiss` and that it preceded the RPC. The refactor moved that clear to `runExclusive`, and the test now asserts it lives there and precedes `await action();` — **the same ordering rule at its new single site** — plus new assertions the old shape could not express: `actionInFlight` declared, both actions calling `runExclusive`, acquire and release inside it. Intent preserved.

**FINDING F-SEC-1-A (A, assertion gap, NOT a defect; LOW).** The suite pins that the acquire and release **exist** inside `runExclusive`; it does **not** pin that the release is **unique**. Today it is — A verified one of each — but a later edit adding a second release on a success path would pass every test. **"Released exactly once" is precisely what the owner's evidence list asks to be proved, and it currently holds by construction while being undefended by the suite.** The cheap fix is occurrence-count assertions in the source-contract test. Not a blocker; recorded so the property is defended rather than merely true.

**Unresolved, reported rather than closed:** whether a second `signOutAllDevices()` would surface "sign out failed" over a **successful** sign-out. The probe that found the defect used a mock forcing the second call to fail. After the fix there is no second call, so it is **moot in practice and still UNVERIFIED as a claim** — deliberately not collapsed, because if it ever matters again it will be because something else calls that function twice.

**Status: A's gated auth review PASS (with F-SEC-1-A open). D's mechanism-and-controls review is still outstanding. Nothing integrated; no build.**

### F-SEC-1-A closed at `016d8e2`; **A's framing of it corrected by D**; and F-SEC-2 filed (A, 2026-09-17)

**Closed, and closed by mutant rather than by assertion.** C's `016d8e2` (**one test file, +8 lines; the hook untouched — A verified**) makes the source contract **count** occurrences: exactly one `actionInFlight.current = true`, one `= false`, one `setBusy(true)`, one `setBusy(false)`. **D proved the control in both directions with its own mutant SM4** — a second release inserted on the success path — which **passed all 14 tests before the change and fails after**. A's gates at `016d8e2`: typecheck **exit 0** · lint **exit 0**, 29 warnings · vitest **107 files / 2258 tests, all passed**. **[PR #74](https://github.com/SnatchIt-app/snatchit/pull/74) re-pointed; head confirmed `016d8e2`.**

**Why the gap was worth closing, in D's words and proven by D:** the mutant is not cosmetic. A second release opens the lock **before the operation it represents has finished** — between that release and `router.replace`, a press can start a second sign-out. Same shape as F-AVATAR-1, the defect this whole chain began with.

**A's framing was WRONG and D corrected it.** A recorded F-SEC-1-A as *"precisely what the owner's evidence list asks to be proved"*. **It is not: "verify it clears exactly once" was the owner's evidence item for BATCH 1c, not for F-SEC-1.** F-SEC-1's third item is *"prove a failed sign-out releases the guard"*, which S3 does and SM2 kills. **So F-SEC-1-A was discretionary hardening, not a gap against this batch's spec** — it did not block the PASS, and neither A's nor D's PASS at `39bc41c` is withdrawn. *(This is A's second overstatement of the day, after the AUTODEPLOY-1 claim, both caught by D. The pattern in both: A attached a true finding to a stronger authority than it had.)*

**D's correction against itself, recorded because D volunteered it:** in 1c, D told C that a single release site made a double clear *"impossible by construction… a stronger guarantee than any assertion could give you"*, and declined the control. **SM4 is the demonstration that this was half wrong: impossible-by-construction is true of *this* construction and says nothing about the next edit.**

**THE SAME GAP IS IN 1b AND 1c — A verified D's counts independently:** `avatarInFlight.current = false` appears **exactly once** in `app/settings/edit-profile.tsx` at `0ca71ff` and **exactly once** in `app/(tabs)/profile.tsx` at `2567401`. True today, **undefended in both**, same one-line control available.

**A's decision, agreeing with D's recommendation: do NOT reopen 1b or 1c.** They are passed, their PRs are open, and quietly widening a reviewed batch is the thing this sprint has avoided all day. The control is taken in 1d, where the work was in flight. **The identical gap in 1b and 1c is recorded as a FOLLOW-UP for the owner to schedule** — if they would rather have all three at once, that is a scope decision and theirs.

### F-SEC-2 — a thrown error on a security action is silent (NEW, OPEN, pre-existing)

**A verified it in source at `016d8e2` rather than relaying C and D.** `runExclusive` is `try { await action(); } finally { … }` — **no `catch`**. Only an `error` field *returned* by a call is handled; a **thrown** one propagates. `src/components/SecurityNoticeBanner.tsx` passes the async `signOutAll` and `dismiss` straight to `onPress`, so the rejected promise is unhandled and **the user sees nothing at all**. A network throw on "Sign out of all devices" is a tap that does nothing and says nothing.

**Not this batch's doing and not made worse by it:** the pre-fix code had the same `try/finally` with no `catch`, so the behaviour is identical before and after. **The lock is unaffected** — the `finally` still releases and clears busy, so nothing jams; A confirmed that reading the same code.

It is **the same "silent tap" class that `DISMISS_FAILED_COPY` was written to end**, on a security surface. **Recorded for the owner; nothing started, nothing authorized.**

### F-SEC-2 implemented as Batch 1e — A's gated auth review: **PASS on the mechanism, ONE FINDING** (A, 2026-09-18)

**AUTHORIZATION NOTE, recorded first because it is the part A cannot verify.** A filed F-SEC-2 for the owner with *"nothing started, nothing authorized."* C has now implemented it, citing an owner instruction given **in C's session** (the word *"standalone"*, and a requirement to preserve the shared lock). **A did not receive that instruction.** Under the standing rule — relayed permissions are not honoured, relayed restrictions are — **A treats this as C's own authorization in C's session, not as authority extended to A.** A therefore reviews the branch, which is local read work needing no authorization, and **integrates nothing**. **A has also NOT opened a PR for 1e**, because the owner's PR authorization named *"Batch 1/1b/1c"*; A already stretched it once to open **#74 for F-SEC-1**, which is disclosed to the owner rather than repeated.

**Head `frontend/batch1e-security-notice-throws @ 3b9dc9d`**, resolved by A. **C's scoping call is correct and A confirms the reasoning:** 1e is cut from `016d8e2` and **carries F-SEC-1**, because the instruction is to *preserve* the shared same-tick lock and that lock exists only on that branch — "standalone" means standalone from the UI batches. Verified: `016d8e2` **is** an ancestor, `2fe7abd` **is not**. **Sequencing: 1e requires 1d.**

**Gated auth surface `6561d1f..3b9dc9d`: ZERO lines** across `signOut.ts`, payments, checkout, `supabase/`, `scripts/`, `.github/`, `app.json`, `package.json`. Diff vs 1d: **two files, +221/−4** — the hook (+23/−4) and the new suite. **A's gates at `3b9dc9d`:** typecheck **exit 0** · lint **exit 0**, 29 warnings · vitest **exit 0 — 108 files, 2264 tests, all passed**. C's numbers reproduce exactly.

**The mechanism is right.** A single `catch` at the one site that already owned acquire and release; `failureCopy` is the **caller's existing** string, so no third state and no new copy; the `finally` still releases, so the lock behaviour A reviewed at 1d is unchanged. C's controls 5/5: TM1 removes the catch (the shipped defect), TM2 catches silently, TM3 rethrows, TM4 crosses the two copies and kills T2 alone, TM5 skips the release on the throw path.

**FINDING F-SEC-2-A (A, gated auth review; LOW likelihood, EXACTLY the defect class this chain is about).** **The `catch` now spans the post-success navigation.** In `signOutAll` the action is `await signOutAllDevices()` → on success → `router.replace('/(auth)/login')`, and **all of it sits inside the try**. So if the sign-out **succeeds** and the navigation throws, the user is shown `SIGN_OUT_FAILED_COPY` — **a failure asserted for an action that completed**. Every session and push binding really did end; the screen says it did not.

That is the same truthfulness rule this sprint has enforced everywhere else (F-XFER-1/2, F-HOME-1, F-BID-1): **never assert a failure that did not happen.** It also sharpens C's own nuance — C wrote that a throw is an *unknown* outcome rather than a known failure, which is true and is why reusing the existing copy is defensible; but once the throw can occur **after** the sign-out has succeeded, the unknown is no longer symmetric. Remedies, C's choice and D's to judge as mechanism: narrow the try to the sign-out call, or record success before navigating so the catch cannot relabel it. **Not a blocker on the mechanism; it is a scope question for the owner if fixing it widens 1e.**

**Unresolved and deliberately not implied away (C's framing, A agrees):** nothing here establishes which side of the known/unknown line a *real* throw falls on. It is the same shape as the F-SEC-1 uncertainty and is kept separate from the fix.

### F-SEC-2-A closed at `a6a8323`; F-SEC-3 filed; the suite's own limit recorded (A, 2026-09-18)

**Fixed, and fixed narrowly.** `a6a8323` wraps **only** `router.replace('/(auth)/login')` in its own try/catch, logging the throw instead of relabelling it. A read the diff: **the hook changes 10 lines**, the outer catch is untouched, and the comment states the rule rather than the mechanism — *"past this line the sign-out HAPPENED … A throw is an unknown outcome only while the outcome is unknown."* **A's gates at `a6a8323`:** typecheck **exit 0** · lint **exit 0**, 29 warnings · vitest **exit 0 — 108 files, 2265 tests, all passed** · **gated auth surface `6561d1f..a6a8323`: ZERO lines.**

**A verified the belt-and-braces claim rather than accepting it:** `supabase.auth.onAuthStateChange` is registered in `app/_layout.tsx:86` and `src/hooks/useAuth.ts:127`, so the user is routed on sign-out whether or not this `router.replace` lands. The guard therefore degrades to a log, which is what makes swallowing the throw here safe. **T7** pins it; **TM6** — the exact scenario A raised, navigation moved back inside the outer catch — **kills T7**.

**A limit of the suite, disclosed by C rather than found in review, and recorded as a limit rather than as coverage:** **TM7** over-corrects by having the navigation guard clear a *real* failure, and it **passes everything**. No test can distinguish it, because that guard only ever runs after success, so there is never a real failure present for it to clear. That is a true statement about what the suite cannot see — not a defect, and not covered.

**The rule this settles, stated once because it now has two sides:** *no failure is asserted before confirmation, exactly as no success is.* The sprint enforced the second half everywhere (F-XFER-1/2, F-HOME-1, F-BID-1, the checkout reconciliation A reviewed at the start); F-SEC-2-A is the first time the **first** half was violated in code, and by a fix rather than by the original defect. C's own nuance — a throw is an unknown outcome — is exactly right **while the outcome is unknown**, and stops being right past the success line.

### F-SEC-3 — the read path swallows a throw the same way (NEW, OPEN, pre-existing, LOW)

**A verified it in source at `a6a8323`:** `load()` is `try { … } finally { … }` with **no `catch`**, and it is invoked as `void load()` at `:50` and again inside the `AppState` listener at `:51`. A throwing read therefore produces an **unhandled rejection**. Same shape as F-SEC-2, on the read path. **Lower stakes, and C's characterisation is fair:** that path is designed to fail quietly — a missing 136 RPC is treated as "no notices" and any other failure stays silent and retries on the next foreground — so the difference is **mechanism, not user-facing outcome**. D supplied the lead; C probed it rather than leaving it asserted.

**Outside any authorization. Nothing started.** Filed for the owner alongside F-SEC-2's descendants.

**Sequencing as it now stands:** `6561d1f` → 1d (F-SEC-1) `016d8e2` → **1e (F-SEC-2 + F-SEC-2-A) `a6a8323`**; independent of Batches 1/1b/1c throughout (`2fe7abd` is not an ancestor of either). **No PR for 1e** — the owner's PR authorization named Batch 1/1b/1c, A stretched it once for #74 and disclosed that rather than repeating it on a peer's say-so. **C agreed unprompted that repeating it on C's word would be laundering.**

### BUILD 20 SUBMITTED — internal device-verification build (A, 2026-09-18)

**The owner confirmed all five conditions** and authorized: *"Tag `candidate/2026-09-18-build-d1` and submit the preview build. This authorizes only the internal sandbox build for handset verification. Do not merge, deploy to production, change sandbox data, enable keys or request any release."*

| | |
|---|---|
| **Tag** | `candidate/2026-09-18-build-d1` → **`8da50c0`** (annotated; `git describe --exact-match` confirms HEAD) |
| **EAS build id** | **`2c423058-fd38-4680-bbf4-26360b188567`** |
| **Logs** | https://expo.dev/accounts/jdt_inc/projects/snatchit/builds/2c423058-fd38-4680-bbf4-26360b188567 |
| **Profile / env** | `preview`, `distribution: internal`, `EXPO_PUBLIC_APP_ENV=sandbox`, test Stripe key — **not production** |
| **Project** | `@jdt_inc/snatchit` (`974db62d-…`), bundle `com.jdt-inc.snatchit`, Apple team `86X83K4BSY` |
| **Submitted from** | a **clean** worktree at the tag — `git status --porcelain` empty, so the uploaded archive is the committed tree and nothing else |
| **Version** | `1.0.0`; build number assigned remotely by `autoIncrement` — no file edited |

**TRACEABILITY GAP, named rather than left implicit: the tag and the integration branch are LOCAL ONLY.** A's pushes are blocked by a permission gate in this session, so `candidate/2026-09-18-build-d1` and `integration/device-verify-20260918` exist on this machine and nowhere else. The build itself is unaffected — EAS archived the committed tree — but **nobody else can resolve the build's source from the remote**, and if this machine is lost the tag goes with it. Closing it is a single push whenever the owner wants it.

**What this build is for, stated as D is to record it:** every one of the eleven fixes in it has **source-and-test evidence only**. **None has device evidence.** The build exists to change that, and until C's handset pass runs, no row in it may be described as verified on hardware.

**Roles, as the owner set them:** **C owns handset verification** and must test the changed flows on-device · **D records the distinction between source/test review and device evidence** · **deferred until after device verification: F-SEC-3, F-SEC-1-B (the 1b/1c uniqueness follow-up) and the unknown-outcome copy decision.**

**Still barred and unchanged by this authorization:** no merge (PRs #72–#74 stay draft, do-not-merge), no production deploy, no sandbox data change, no keys enabled, no release requested. Migrations 138 and 141 remain unapplied.

### Build 20 provenance — independently verified by D; and D's refusal to push, which was the right call (A, 2026-09-18)

**Two-person provenance.** D re-ran `merge-base --is-ancestor` itself for all five reviewed heads against `8da50c0` — `2fe7abd`, `0ca71ff`, `2567401`, `016d8e2`, `f3cff27` — and confirms each. **So "the build contains exactly what was reviewed" is now two independent checks rather than A's word.** D resolved `f3cff27` the same way A did (five added lines, all comment, no code, no deletions) and **deliberately did not re-run the suite for it**, on the ground that comments cannot change behaviour and the diff *is* the verification — A agrees, and the auth review carries for the same reason.

**The traceability gap is confirmed by both sides.** D ran `ls-remote --tags origin` and got nothing for `candidate/2026-09-18-build-d1`; A re-ran it and got a count of **0**. The tag and `integration/device-verify-20260918` exist on exactly one disk.

**D declined to push it, and A records the reasoning as correct rather than as a hesitation.** In D's words: A's pushes are blocked by a permission gate, and pushing A's tag *because A cannot* would route around a decision someone made about A's session — and whether that gate is deliberate or incidental is not D's to determine. **That is the same boundary every session has held tonight** (C declined to open A's PR for the same reason, unprompted), and a build handoff is exactly the moment where "just this once, it's only a tag" would feel reasonable. It goes to the owner as a gap with a named fix instead.

**The artifact is unaffected:** EAS archived the committed tree, so what is building is what the tag points at. **The risk is precisely and only that one link in the chain exists on a single disk.**

**Both sessions state the build's status in the same words, deliberately:** eleven fixes with **source-and-test evidence and none with device evidence**. D's five verdicts say the tests discriminate and the mechanisms are right; **not one of them says a person tapping a phone sees the right thing.** The build is where the second kind of evidence starts existing, not where it arrives.

### BUILD 20 FINISHED — available for handset verification (A, 2026-09-18)

| | |
|---|---|
| **Status** | **finished** (no errors), 12:28:59 AM → 12:36:05 AM, ~7 minutes |
| **Build number** | **20** — assigned remotely by `autoIncrement`, as predicted; no file was edited to obtain it |
| **Commit, as EAS recorded it** | **`8da50c064a7835a1f79e1fcdc3546ffbe792b014`** = `8da50c0` = tag `candidate/2026-09-18-build-d1`. **The artifact's own record names the reviewed tree** — that is the provenance link, independent of A's account of it |
| Platform / profile / distribution | iOS · `preview` · **internal** |
| Version / SDK | 1.0.0 · Expo SDK 54.0.0 |
| Fingerprint | `78f32c441b944f4a07ac4267b889cf5687519d4d` |
| Install page | https://expo.dev/accounts/jdt_inc/projects/snatchit/builds/2c423058-fd38-4680-bbf4-26360b188567 |
| Archive | `…/artifacts/eas/pbZ5UvBTVmialtn6er452U8jXV97s7tRL_WUHXorKKI.ipa` |

*("Build Artifacts URL: null" is expected — it refers to a separate artifacts bundle; the application archive above is the IPA.)*

**Build 20 supersedes nothing.** Build 19 (`f412d10`) remains installed and is unchanged; the owner's earlier ruling that Build 19 stays untouched is unaffected, and both can exist on the phone.

**What is now true, stated precisely:** the eleven fixes have **source-and-test evidence** and an **artifact that provably contains them**. They still have **no device evidence**. The build being green says the code compiles and ships; it says nothing about what a person sees. **C's handset pass is the only thing that changes that**, and until it runs no row may be recorded as hardware-verified.

**Unchanged and still barred:** no merge (PRs #72–#74 draft, do-not-merge) · no production deploy · no sandbox data change · no keys enabled · no release requested · migrations 138 and 141 unapplied · the two retained Line 3 proof objects untouched. **Deferred by the owner until after device verification:** F-SEC-3, F-SEC-1-B, and the unknown-outcome copy decision.

**The traceability gap persists and is unchanged by the build finishing:** tag `candidate/2026-09-18-build-d1` and `integration/device-verify-20260918` remain local to one machine. EAS now independently records the commit hash, which narrows the exposure — the artifact names its source even if the tag were lost — but the commits themselves still exist on one disk.

### CORRECTION (A's error) — Build 20 REPLACES Build 19 on the phone, and the app cannot tell you which one it is (A, 2026-09-18)

**A wrote that Build 19 and Build 20 "can both sit on the phone". That is WRONG, C caught it before the pass started, and A verified the correction in source.**

- **Same bundle identifier.** `app.json` declares `com.jdt-inc.snatchit`, and **no `eas.json` profile overrides it** — A checked all four (`development`, `preview`, `production`, `sandbox`); `preview` adds only `ios.autoIncrement`. **Installing Build 20 therefore REPLACES Build 19.** Getting back to 19 means reinstalling it from its own build page.
- **Consequence for the pass, C's point and the right one:** "a row observed on 19 is not a row observed on 20" still holds, but the safeguard is not *keep them straight* — **19 is gone the moment 20 lands.**

**And the app shows its build number nowhere.** `src/providers/NativeAppShell.native.tsx:30-33` reads `Constants.expoConfig?.version` and `…ios?.buildNumber` **once**, and A confirmed both are used **only** for the Sentry `release` and `dist` tags — `_version` appears exactly twice in the file, the second being the Sentry release string. **Nothing renders either value.** Both builds report version `1.0.0` in iOS Settings and both show the same SANDBOX badge, **so the owner cannot confirm from inside the app which build they are running.** *(Not established, and not needed: whether EAS's remotely assigned build number reaches `expoConfig.ios.buildNumber` — which is `1` in the repo — at build time. It changes nothing here, because the value is never displayed.)*

**What this changes about the pass — C's design, A concurs.** The first check must double as **build identification**. Home's "Recently sold" offline is the right one: it is the row the owner personally reproduced **twice** on Build 19, so the old behaviour is known exactly and the new behaviour differs visibly. **If the old copy appears, the result is AMBIGUOUS** between *"the install did not take"* and *"the fix failed"* — and the resolution is **reinstall and retry before anything is recorded as FAIL**. A first-row failure must not be attributed to the code by default.

**Why A got it wrong, recorded rather than smoothed:** A reasoned from *"Build 20 supersedes nothing"* — true about the release stack, since Build 19 remains the owner's reference build and no ruling about it changed — and let that slide into a claim about the **device**, which is a different system with different rules. A release-planning fact was extended to a physical one without checking the bundle identifier that decides it. **This is the third time tonight A attached a true statement to a stronger claim than it supported** (the AUTODEPLOY-1 inference, the F-SEC-1-A spec attribution, and now this), and all three were caught by a peer rather than by A.

**C also verified something ancestry alone cannot establish:** that **each of the eleven fixes is present in the built tree**, not merely that the five heads are ancestors of `8da50c0` — since a revert on top would preserve ancestry while removing the change. That check is C's and it closes a gap in A's provenance argument.

### Build 20 handset pass — first three rows, F-BID-3, and the DV-20-9 fixture decision (A, 2026-09-18)

**Results as C recorded them, owner-reported, on Build 20** (C's record commits `239a594`, `7564790`, `00d385f` — **A resolved all three against a ref**: they are on `frontend/premium-experience-backlog`):

| Row | Result | What it does and does NOT establish |
|---|---|---|
| **DV-20-1** | **PASSED** (11:34 ET) | as recorded by C |
| **DV-20-2** | **PASSED** (11:39 ET) | as recorded by C |
| **DV-20-4** | **PASSED on the final state** (11:43:47 ET) | **Carries a hard limit, held here exactly as the owner directed.** The earlier screenshot shows Airplane Mode on, current bid $100, proposed $105, and an alert *"Bid failed" / "TypeError: Network request failed."*; the later one shows the offline state. **No `$0` appears in either**, so **the F-BID-1 property — a form built on a FAILED read — is NOT shown by either screenshot.** The sequence between them was not captured, and **the owner has directed that nobody infer when the form loaded or which buttons were pressed.** A holds to that. The one statement made is from **source, not sequence**: that alert is emitted by `submitBid` after the `bids` insert returns an error. **Whether a bid row was written is UNVERIFIED.** |

**So DV-20-4 is a PASS on what the final screen shows, and F-BID-1 itself remains WITHOUT device evidence.** Recording it any other way would convert a missing observation into a passing one.

**F-BID-3 — NEW, OPEN, pre-existing, untouched by F-BID-1. A verified it in source at `8da50c0`:** `src/screens/PlaceBidScreen.tsx` does `Alert.alert('Bid failed', error.message)` when the `bids` insert returns an error — so **a person is shown the raw `TypeError` string**, and **offline is not classified** the way the screen's read path now classifies it. Same truthfulness class as F-HOME-1 and F-BID-1, on the submit path rather than the read. Nothing started.

### DV-20-9 (Receive screen on a `seller_sent` transfer) — **opening the screen IS a sandbox write, so it needs the owner's authorization, not just a read**

**Fixtures ruled out, C's reasoning, A agrees:** D1 and D2 are out entirely — opening either mints a signed URL for a **retained proof object**, which ruling 2 bars. L7 is out. **S8only (`8f59d37e…`)** is the candidate, because its evidence path was null last night.

**A verified C's claim about what opening the screen does, and it holds.** *(Attribution corrected after A resolved C's record: A first wrote "with one correction to where the write comes from", which implied C had it wrong. **C's record did not** — C's fixture note `887f773` on `frontend/premium-experience-backlog`, resolved by A against the ref, already attributes the notification to `058`'s `trg_notify_transfer_state_inbox` and says `mark_transfer_viewed` only stamps the column via `COALESCE`. Only C's chat summary compressed the two into one clause. A's "correction" was to a summary, not to the record, and is recorded that way so it does not become a false finding against C.)*
- `app/transfer/receive/[id].tsx:160` calls `supabase.rpc('mark_transfer_viewed', …)` on open.
- `mark_transfer_viewed` (**`0550_transfer_state_guard.sql:243`**) does exactly one thing: `UPDATE public.transfers SET buyer_viewed_at = COALESCE(buyer_viewed_at, now()) WHERE id = … AND buyer_id = auth.uid()`. **The function itself writes no notification.**
- **The notification comes from a trigger**: `058_notification_producers.sql` `trg_notify_transfer_state_inbox` (AFTER UPDATE on `public.transfers`) inserts **one `transfer_viewed` inbox row for the seller when `buyer_viewed_at` goes from NULL to NOT NULL**, dedupe key `transfer_viewed:<transfer_id>`.
- A checked every UPDATE trigger on `public.transfers`: only the 0550 BEFORE UPDATE guard and that 058 AFTER UPDATE producer. **No `updated_at` trigger.**

**Therefore the pre-read decides the class of action:**
- **`buyer_viewed_at IS NULL` → opening the screen CHANGES SANDBOX DATA:** it sets `buyer_viewed_at` and writes **one inbox notification to the seller**. The build authorization said *"do not … change sandbox data"*, so **this branch needs the owner's explicit authorization for that write**, not merely for the read. (No outbound push is possible — the sandbox push key remains deferred, option b.)
- **`buyer_viewed_at IS NOT NULL` → opening the screen changes no data values:** `COALESCE` keeps the stored time and the trigger's NULL→NOT NULL condition is false, so no notification. (A new row version is still written at the storage level; no column value changes.)

**The read, PREPARED BY A AND NOT RUN.** It is a sandbox read and **the owner has not authorized it**; C asked for it to be ready, not run.

```sql
-- sandbox ofaidukbieeekqaboscm ONLY; read-only; run from an unlinked worktree with an explicit project ref
begin read only;
select 'rows='||count(*) from public.transfers where id::text like '8f59d37e%';          -- must be exactly 1, else STOP
select t.id, t.status, (t.transfer_evidence_path is null) as evidence_path_null,
       t.buyer_viewed_at, t.buyer_id, t.seller_id, l.event_name
  from public.transfers t join public.listings l on l.id = t.listing_id
 where t.id::text like '8f59d37e%';
-- ONLY IF the owner also authorizes the bid-row check. Nobody holds the listing id: the owner chose "any live
-- auction that isn't yours and isn't Sandbox L7" and never named it, and C declined to guess. Key it by the
-- EVENT NAME the owner gives (easier for them than an id), and refuse unless it resolves to exactly one listing:
-- select 'listings='||count(*) from public.listings where event_name = '<event name, from the owner>';  -- must be 1, else STOP
-- select count(*), max(b.created_at) from public.bids b join public.listings l on l.id = b.listing_id
--  where l.event_name = '<event name, from the owner>' and b.created_at >= '2026-09-18T15:40:00Z';  -- 11:40 ET = 15:40Z
rollback;
```

**Stop conditions:** more or fewer than one transfer row; `status` other than `seller_sent`; `transfer_evidence_path` NOT null (then opening the screen would mint a signed URL for a stored object, which is the D1/D2 case and is barred).

### DV-20-9 opened BEFORE the pre-check — recorded as observed, the write recorded as UNKNOWN; F-XFER-3 answered; F-LAYOUT-1 (A, 2026-09-18)

**The owner opened S8only's Receive Transfer screen at 11:58 ET (≈15:58Z), before any read ran.** C recorded it at `b081535` on `frontend/premium-experience-backlog`. **A's prepared pre-check therefore no longer works as a pre-check** — it was designed to decide *before* the open whether the open would write, and the open has happened. **Nothing has been run and nothing is authorized; A runs nothing.**

**What the owner reported:** badge **MARKED SENT**; event **"Sandbox S8only"** (so the L7 stop did not trigger); **no expiry line**; the delivery-info prompt and form. The navigation sequence was not supplied and **no database outcome has been confirmed by the owner.**

**As recorded (C's structure, A concurs):**
- **DV-20-9 PASSED on the screen as observed.**
- **The fix evidence is recorded separately and is CONDITIONAL.**
- **The write is UNKNOWN.** The open stamped `buyer_viewed_at` and wrote one `transfer_viewed` notification to the seller **only if** the column was NULL beforehand; nobody knows whether it was.

**A's sharpening of the condition — narrower claim, better-founded (verified in source at `6561d1f`, the pre-fix tree):** C conditioned the fix evidence on `expires_at` being **still past**. **The discriminating condition is weaker than that: `expires_at IS NOT NULL`, past OR future.**
- Pre-fix, the receive screen's countdown block (`:338-344`) is a **top-level sibling** — **not** inside the delivery gate (`:309-318`) and **not** inside the `!needsDeliveryInfo` block (`:320-336`). C was right about that.
- Pre-fix, the effect (`:166`) runs `formatCountdown` for **any non-null** `expires_at`, and `formatCountdown` returns `"Expired"` if past **or `"Xh Ym remaining"` if future** — it returns `null` only when the timestamp is null.
- So pre-fix, a `seller_sent` transfer with **any** `expires_at` showed **a** window line — *"Transfer window expired"* or a countdown. **The absence of any window line on Build 20 discriminates the fix whenever `expires_at` is non-null.** Only a NULL `expires_at` would make the observation uninformative, because the pre-fix screen would also have shown nothing.
- **A's 09-17 read gave `expires_at = 2026-09-09T01:20Z`** — non-null. And `expires_at` is one of the columns `guard_transfer_state_columns` protects (`0550`), so changing it since then would have required a bypassed write. **That makes "still non-null" very likely — but nobody has re-read it, so the condition stays open.**

**The after-the-fact read, PREPARED BY A AND NOT RUN.** It settles all four open points for `8f59d37e` in one read-only transaction. **The notification check is exact, not approximate:** `enqueue_notification` writes to `public.notifications`, which has a **unique index on `dedupe_key`** (`057`), so `transfer_viewed:<transfer_id>` exists **at most once** — its `created_at` alone says which open wrote it.

```sql
-- sandbox ofaidukbieeekqaboscm ONLY; read-only; unlinked worktree, explicit project ref; NOT AUTHORIZED
begin read only;
select 'rows='||count(*) from public.transfers where id::text like '8f59d37e%';        -- must be exactly 1, else STOP
select t.id, t.status, t.buyer_viewed_at, t.expires_at,
       (t.transfer_evidence_path is null) as evidence_path_null
  from public.transfers t where t.id::text like '8f59d37e%';
select count(*) as transfer_viewed_rows, min(n.created_at), max(n.created_at)
  from public.notifications n join public.transfers t on n.dedupe_key = 'transfer_viewed:'||t.id::text
 where t.id::text like '8f59d37e%';                                                      -- 0 or 1, by the unique index
rollback;
```

**How it reads:** one `transfer_viewed` row created ≈15:57–15:59Z → **the owner's open wrote it** (a sandbox data change, after the fact). One row created earlier → **a prior open wrote it and today's open changed no values.** Zero rows → the trigger never fired for this transfer. `expires_at` non-null → the fix evidence holds. `evidence_path_null` true → no signed URL could have been minted for S8only's own path; **it cannot reach D1/D2 in either case**, since the screen only signs the path stored on its own transfer.

### F-XFER-3 — **A's answer: the server does NOT enforce buyer delivery info before `mark_transfer_sent`**

C asked A the question that decides whether real users can reach the state. **A verified in source at `8da50c0`:** in `140_proof_upload_repair.sql`, **both** overloads — the 3-arg at `:45` and the 2-arg at `:108` — gate on **status alone**; neither references any delivery field. **Both are granted to `authenticated`.** The only enforcement is **client-side**: the send screen's `disabled={… || buyerDeliveryMissing}`.

**So `seller_sent` with no buyer delivery info IS reachable** by any path that skips the client gate — a direct authenticated RPC by the seller, either overload, or any client build without that gate. And in that state, per C: `buyerNeedsDelivery` (`transferState.ts:126-128`) includes `seller_sent`, and the receive screen shows the seller's claim, **confirm/dispute** and the proof view **only when `!needsDeliveryInfo`** — **the buyer's confirm and dispute are hidden behind a delivery form.**

**Why this is A's lane and not only a layout question:** a `seller_sent` transfer carries `auto_release_at`, after which payment releases to the seller. **Whether putting dispute behind a form the buyer may not understand can cost them the dispute window before auto-release is a product question A names and does not answer.** The buyer is not locked out — filling the form reveals the controls — but the path to disputing is longer than the path to doing nothing. **OPEN, owner's to scope; nothing started.**

### F-LAYOUT-1 — recorded only

The listing-detail sticky bar truncates the price to *"CURREN…"* / *"$…"*. C's finding; recorded for the owner; nothing started.

### F-XFER-3 confirmed by C independently — the SERVER half is derived for production (A, 2026-09-18) — *heading and one line below amended: see the owner's restriction*

**C re-derived all three of A's points from source** (recorded on premium at `205e25b`): `formatCountdown` returns null only for a falsy timestamp, so the discriminating condition is `expires_at IS NOT NULL`, and the receive file is identical between `6561d1f` and `2fe7abd`, so both read the same pre-fix tree · the `transfer_viewed` notification is at most one row — unique index `057:50`, `ON CONFLICT (dedupe_key) DO NOTHING` at `057:83`, key `'transfer_viewed:'||id` at `058:185` · and neither `mark_transfer_sent` definition references delivery info.

**A resolved C's citation rather than accepting it:** `69604d5` is 140's own commit on `fix/140-proof-upload-repair`, and **`140_proof_upload_repair.sql` is byte-identical at `69604d5` and at the built `8da50c0`**, so C's check applies to what is in Build 20. A also re-read `0553`: **zero** delivery references, and `auto_release_at = now() + INTERVAL '72 hours'` is set at **`0553:37`** (C cited `:35`; a two-line difference in the citation, the fact identical).

**The materially new consequence, and it is A's to state because it is about payments in production:**
- The only migrations that define `public.mark_transfer_sent` are **`0550`, `0553` and `140`** (A's grep across the chain).
- **Production is at ledger 135 and nothing has been applied since 2026-09-12**; `140` is above 135 and applied only to the sandbox.
- **So production's `mark_transfer_sent` is `0553`'s body — which enforces no delivery info and starts the 72-hour auto-release clock.**
- ~~**F-XFER-3 is therefore live behaviour in production, not a sandbox artifact.**~~ **WITHDRAWN.** *The owner's restriction, relayed through C and honoured (relayed restrictions are): "App Store release status remains unverified; don't describe this as observed production behaviour."* What survives is only the **server** half: production's `mark_transfer_sent` is derived to be `0553`'s body, which enforces no delivery info. **It is not observed, and no claim is made about what users in production meet** — see the correction below, which narrows the finding to a bypass case. The original line is struck rather than deleted so the overstatement stays visible where it was made.

**What stays unchanged:** the buyer is **not locked out** — C confirmed in source that saving delivery info clears `needsDeliveryInfo` and reveals confirm/dispute. The open question is still the product one A named: **whether hiding dispute behind a form the buyer may not understand can cost them the dispute window before the 72-hour auto-release.** Owner's to scope; nothing started; nothing run.

### CORRECTION (A's overstatement) — F-XFER-3 is a BYPASS case, not "the behaviour real users have today" (A, 2026-09-18)

**A told the owner F-XFER-3 "applies to live production" and described "what this means for real buyers today". That overstated it, C qualified it, and A verified C's qualifications in source.** Recorded at C's `068b116`; C also corrected its own `:35` citation to A's `:37` — a line number taken relative to `tail` output rather than the file.

**The claim now stands as THREE SEPARATE claims, each at its own strength:**

1. **Server half — DERIVED, not read.** Production runs `0553`'s `mark_transfer_sent` (the chain's only definers are `0550`/`0553`/`140`; production is at ledger 135; `140` is above it), and `0553` enforces no delivery info while starting the 72-hour auto-release. **Derived from the migration chain and the recorded ledger; no production read was authorized or performed.**
2. **The store client has the same gates — VERIFIED in source by C and by A.** At the only store-tagged client, `mobile/v1.0-build9-apple-review` (= `4740091`): the **send** screen computes `buyerDeliveryMissing = !delivery_email && !delivery_phone` and renders the button with `disabled={busy || buyerDeliveryMissing}`; the **receive** screen's `needsDeliveryInfo` covers `pending || seller_sent` and shows confirm/dispute only when `!needsDeliveryInfo`.
3. **Therefore the state is reachable ONLY BY BYPASS.** An ordinary seller using the app **cannot** mark a transfer sent without the buyer's delivery info. Only a seller or client calling `mark_transfer_sent` **directly** can — it is granted to `authenticated`. **The exposure is a bypass case, not the everyday path.** That narrows the owner's decision; it does not remove it.

**A's addition, which makes claim 3 independent of which build is live:** C noted that nothing records which build is live in the App Store, or whether 1.0 is publicly released, so claim 2 about "the live client" was not established. **A traced the send-side gate's origin:** `buyerDeliveryMissing` entered `app/transfer/send/[id].tsx` in **`6a5b854` on 2026-04-14** ("beta launch UI"), **months before the 1.0 submission.** So **whichever store build is live, it would have had to remove that gate to lack it**, and nothing records that. **Claim 3 therefore does not depend on knowing which build is live.** What remains genuinely unknown is only *which* build real users run — **A does not know, and older records naming a submission and later review candidates are not current enough to rely on.**

**The honest shape of the finding:** a server that trusts its client for a rule that protects the buyer's dispute window, with every known client enforcing that rule. **It becomes a buyer-facing problem only if someone calls the RPC directly** — which any authenticated seller can.

**Pattern, recorded against A: this is the FOURTH time tonight A attached a true finding to a stronger claim than it supported** (AUTODEPLOY-1, F-SEC-1-A's spec, Build 19/20 coexistence, and now "live for real users"), **and the fourth caught by a peer.** Each time the underlying fact held; each time A extended it one system further than it had checked. *(A also hit the known zsh `"$T:path"` modifier trap while verifying this — `$T:a` is read as a history modifier — and caught it on the first empty result by switching to `"${T}:path"`.)*

### Owner's answers, RELAYED through C — restriction honoured, authorization NOT acted on (A, 2026-09-18)

C relayed three owner statements from C's session, and invited A to apply A's own rule. A does:

| Relayed statement (verbatim, via C) | Kind | A's treatment |
|---|---|---|
| *"A has authorisation for both read-only checks."* | **permission** | **NOT acted on.** Relayed permissions are not honoured. **Neither read has been run.** A has asked C to have the owner authorize A **directly**. |
| *"The bid event was Device D7."* | fact | **Used** — the prepared bid read is now keyed by event name `Device D7` (still refusing unless it resolves to exactly one listing; window from `2026-09-18T15:40:00Z`, i.e. 11:40 ET). Not run. |
| *"App Store release status remains unverified; don't describe this as observed production behaviour."* | **restriction** | **HONOURED immediately.** The earlier F-XFER-3 heading ("it reaches PRODUCTION") and the line calling it "live behaviour in production" are amended above — the line **struck, not deleted**, so the overstatement stays visible where it was made. |

**The F-XFER-3 fix — authorized to C in C's session, and A's part in it needs no authorization.** Owner's words as relayed: *"fix F-XFER-3 in a separate branch. On a transfer already marked sent, missing delivery details must not hide the buyer's confirm-received or report-a-problem controls. Preserve their existing safeguards and server rules. Cover this specific state with focused tests, then have A and D review it. No new build or deployment yet."* C implements; **A's review is local read work**, so A will review the branch when it arrives without needing any further word. **A's review focus is the confirm path, because confirm-received is `confirm_transfer_received` → payment release to the seller**: A will check that un-hiding the controls changes nothing about *when* confirm is allowed, what it calls, or which server rule guards it — only *whether the button is visible*. *(Relayed as the scope of C's work, not as an authorization A acts on; reviewing needs none.)*

### F-XFER-3 fix — A's review of the confirm path: **PASS**, plus one pre-existing observation in A's lane (A, 2026-09-18)

**Head `frontend/xfer3-sent-controls-visible @ a739a40`**, resolved by A in the shared object store (not pushed, no PR — **the owner authorized a branch and reviews, not a PR, and no build**). `8da50c0` (Build 20) is an ancestor; one commit. **Diff: two files** — `app/transfer/receive/[id].tsx` (+6/−3) and the new test file. **Gated surface `8da50c0..a739a40` over payments, checkout, signOut, `supabase/`, `scripts/`, `.github/`, `app.json`, `package.json`, `eas.json`: ZERO lines.**

**The change is exactly what C described, and nothing else.** One condition: the `seller_sent` block's `status === 'seller_sent' && !needsDeliveryInfo` becomes `status === 'seller_sent'`; the other two changed lines are comments. **`handleConfirm`, `confirmReceipt`, `handleDispute`, the single-flight lock, `busy`, and every RPC and edge-function call are untouched** — the diff has no hunk anywhere near them.

**The confirm-path check A owned — and the fact that makes the fix work rather than merely show buttons.** A read the server side of both actions at the current definitions:
- **Confirm** → `confirm-and-release` edge function → `confirm_transfer_received` (`0550:191`), which checks **only** that the caller is authenticated, is the transfer's buyer, and that `status = 'seller_sent'`. **No delivery field is referenced** — nor anywhere in the edge function.
- **Report a problem** → `buyer_dispute_transfer` (`0550:207`), the same shape: caller, buyer, status. **No delivery field.**
- **So on a `seller_sent` transfer with no delivery details, the server has always ACCEPTED both actions. The client gate was the only thing standing between the buyer and them.** Un-hiding the controls therefore yields actions that succeed, not new server errors — which is precisely the owner's goal, achieved without touching a server rule, exactly as the owner required (*"Preserve their existing safeguards and server rules"*).

**C's open item (c) verified:** the proof view's signed-URL effect (`:101-109`) depends only on `transfer_evidence_path` and `status === 'seller_sent'`, **never on `needsDeliveryInfo`**, so it already ran in this state before the fix. **No new storage access — only rendering.**

**The design question A raised is settled the right way:** the delivery form **stays visible** alongside the controls; C's X3 pins it and mutant XM3 (the "fix" that drops the form on sent) is killed by it.

**A's gates at `a739a40`, A's own runs, no concurrent vitest:** typecheck **exit 0** · lint **exit 0**, 29 warnings · full vitest **exit 0 — 117 files, 2343 tests, all passed.** C's numbers reproduce exactly.

**OBSERVATION in A's lane — pre-existing, OUTSIDE the owner's scope, NOT a blocker, and NOT changed by this fix.** *"Report issue"* asks **"Are you sure…?"** before it acts. **"I got my tickets" does not:** `handleConfirm` goes straight to `flight.run(confirmReceipt)`, which invokes `confirm-and-release` — the path that confirms receipt and proceeds toward payout to the seller. The single-flight lock stops a double tap; **nothing asks the buyer to confirm a single one.** F-XFER-3 preserves that exactly, as ordered — but it now renders that one-tap control in a state where the buyer is **also working through a delivery form directly above it** (C's item d: form, then details, then controls). **Whether confirming receipt should carry the same confirmation step dispute already has is a product question A names and does not answer.** *(A has not traced what `confirm-and-release` does after the status change — payout review and risk holds may apply — so no claim is made that money moves on the tap itself.)*

**Status: A's confirm-path review PASS. D's independent test review is outstanding.** No PR, no build, no deploy.

### F-XFER-3 — D's test review, one missing test, and a scope decision A sends to the owner (A, 2026-09-18)

**D's verdict at `a739a40`: the fix is correct; the suite is final once one test is added.** D's runs: 117 files / 2343 tests, tsc 0; C's mutant harness 8/8 as predicted, run by D on a copy re-pointed at D's own worktree (the original writes to C's).

**The gap D found — XM9 survives the entire suite.** Widening the sent block to `seller_sent || (pending && !needsDeliveryInfo)` puts **"I got my tickets" on a PENDING transfer where the buyer HAS given delivery details** — the ordinary pre-send state — and all 2343 tests stay green. X7 covers pending **without** delivery details; nothing covered its sibling. **D proved the control both ways: an X10 that passes on the real code and fails alone under XM9.** It is a boundary pin for the fix, within the owner's *"cover this specific state with focused tests"*; C adds it.

**Severity, confirmed by A independently from the server source:** **money is safe.** `confirm_transfer_received` (`0550:191`) raises unless `status = 'seller_sent'`, and `confirm-and-release` propagates that error. What would leak is the **offer** — a release button and the release warning on a transfer nobody has sent. A client coverage gap, not a regression from the fix; the same widening was unpinned before it.

**THE SCOPE DECISION — A sends it to the owner, as a decision and not as a defect.** On exactly the state this fix targets (sent, no delivery details), the block at `:326` — `PlatformInstructions` plus the **"Open {provider}"** handoff — is **still** gated on `!needsDeliveryInfo`. **A verified it at `a739a40`.** So after the fix the buyer sees *confirm* and *report* but **has no provider handoff**; and the arrival prompt inside the sent block fires only on a return from that provider, so in this state it cannot be reached.

- **Why D did not call it a defect, and A agrees:** it is outside the owner's words (*"confirm-received or report-a-problem"*), and hiding it may be deliberate — A confirmed that `PlatformInstructions` interpolates the buyer's `delivery_email` and `delivery_phone` into its steps, and in this state both are null.
- **Why it still goes to the owner, which is A's own reason and is about payment release:** the handoff is the **designed "check before you confirm" step** — its own accessibility hint reads *"Opens the ticket provider. Come back here to confirm once you can see the tickets."* In the target state the buyer can now **confirm receipt** — the path toward paying the seller — **without that designed check**, and (per A's earlier observation) with **one tap and no "Are you sure?"**. Neither fact is new, and neither is changed by the fix; **together, in this one state, they mean the verification step is absent exactly where the release control has just become visible.**
- **This is the same mechanism — a buyer action hidden by the delivery gate on a sent transfer — one block up in the same file.** D's point, and the right one: better that someone decides it than that it is discovered on a handset.

**Two owner decisions, therefore, both on the same screen and both product rather than code:** (1) should the provider handoff also show on a sent transfer without delivery details, and with what copy in place of the missing email/phone; (2) should "I got my tickets" ask for confirmation, as "Report issue" already does. **Nothing started on either.**

**Addendum to the confirm-dialog decision — the asymmetry is PINNED BY PASSING TESTS, not inferred (D's check, A re-read it).** D confirmed A's payment claim from C's own suite at `a739a40` rather than taking it, and A re-read the three tests: **X4** asserts the `Report issue` alert fires and `buyer_dispute_transfer` is called only after the destructive choice (`:175`, `:186`); **X5** asserts a double tap produces exactly one `confirm-and-release` invocation on the press (`:200`); **X6** asserts `h.alerts` is `[]` while the server has not answered (`:213`). **So "one tap sends the release call with no dialog in between" is a tested fact of the current code.**

**For the owner's decision note, D's point, and it prevents a future false alarm:** if the owner chooses a confirmation step on "I got my tickets", **X5 and X6 are the tests that must change** — and changing them is the proof the behaviour moved deliberately. Without this note, whoever adds the dialog meets two passing tests turning red with no record that it was intended.

### F-XFER-3 — reviews COMPLETE at `2dbcb02` (A, 2026-09-18)

**Head moved `a739a40` → `2dbcb02`, test-only — A verified rather than took it:** `a739a40` is an ancestor; `git diff a739a40 2dbcb02` touches **only** `tests/receive-transfer-sent-controls.test.ts` (+13/−1); `app/`, `src/` and `supabase/` are **untouched**. So **A's confirm-path PASS at `a739a40` carries to `2dbcb02` unchanged** — the screen A reviewed is byte-for-byte the screen at this head.

**X10 is in** (`:246`): *pending WITH delivery details — the normal pre-send state shows no confirm and no report.* That closes D's XM9, the leak conditioned on delivery being present, which C reproduced passing all 2343 tests before. **D's verdict was "final once X10 is in", and it is in.**

**A's gates at `2dbcb02`, A's own runs, no concurrent vitest:** typecheck **exit 0** · lint **exit 0**, 29 warnings · vitest **exit 0 — 117 files, 2344 tests, all passed** (one more than at `a739a40`: X10). C's numbers reproduce exactly.

**Status: both reviews complete — A (confirm path) PASS, D (tests) final.** **Nothing pushed, merged or built.** The owner authorized a branch and reviews only; a PR, a build and any integration each remain separate decisions.

**Still open with the owner, and NOT resolved by this fix:** whether the provider handoff should show on a sent transfer without delivery details; whether "I got my tickets" should ask first (if yes, X5 and X6 must change deliberately); and the two sandbox reads, which A runs only on the owner's direct word.

### F-XFER-3 — head `cf9b75b`, test-only again; the screen is still byte-identical to what A reviewed (A, 2026-09-18)

**D's second pass: PASS, with one over-claimed title.** The `describe` said *"with and without delivery"*, but X9 ran the finished states only **without** delivery details. D's **XM11** — a leak into finished states **only when delivery is present** — survived. X9 now runs both halves, six cases.

**A verified the move rather than taking it:** `2dbcb02` is an ancestor; the one commit touches **only** the test file (+10/−4); `app/`, `src/`, `supabase/` untouched. **Stronger than an ancestry check: A hashed the screen file at both heads — `app/transfer/receive/[id].tsx` is byte-identical at `a739a40` and `cf9b75b`** (`0dd2af25…` both). So A's confirm-path PASS applies to exactly the code at this head. **A's gates at `cf9b75b`:** typecheck **0** · lint **0**, 29 warnings · vitest **117 files / 2347 tests, all passed** (three more than `2dbcb02`: X9's second half). C's numbers reproduce.

**The pattern worth naming, because it recurred inside a single review:** XM9 and XM11 are the **same gap one state apart** — a guard proved on the delivery-*absent* half of a state and assumed on the delivery-*present* half. X7 had that shape for pending, X9 had it for finished states, and **a test title claimed coverage the body did not have**. Both caught by D, each by a mutant that conditioned the leak on the half the test skipped. ~~*Fix titles to the body, never the body to the title.*~~ **A's rule was WRONG, and C corrected it before it hardened.** At `cf9b75b` C did exactly what that rule forbids — extended the body to match the title — and it was right: the title described coverage the owner's scope actually needs (every other state, with **and** without delivery), so narrowing the title would have left the finished-with-delivery half unpinned and merely stopped claiming it. **The failure worth guarding against is a body padded to satisfy a title without proof that it discriminates — and the mutant is what prevents that.** C's evidence: XM11 survived before, kills exactly the three "with" cases after, and XM8 kills all six. **The rule as recorded: a test title may claim only what a mutant has shown the body enforces. Otherwise, either narrow the title, or extend the body and prove it with a mutant.** Which of the two is right depends on whether the claimed coverage is coverage the scope needs.

**Still: nothing pushed, merged or built.** The handoff, confirm-dialog and sandbox-read decisions remain with the owner.

### OWNER DECISIONS on the two F-XFER-3 product questions, and one PR authorized (owner → A directly, 2026-09-18)

**Verbatim:** *"1. Show 'Open [provider]' on a sent transfer even without delivery details, provided there is a valid provider destination. Show useful general instructions, but omit empty contact fields. 2. Add confirmation before 'I got my tickets': clearly explain that confirming receipt releases payment, with Cancel and an explicit confirmation action. Preserve existing payment and server rules. Keep cf9b75b as the reviewed baseline and make these additions separately reviewable. You implement, A reviews the payment boundary, D reviews behaviour. Run focused checks and final gates; no additional handset testing until these changes are in a build. Coordinate with A on one PR. No merge or new build yet. Continue guiding the remaining applicable Build 20 checks."*

**A's reading of the roles, stated so it can be corrected:** the message names **A as the payment-boundary reviewer**, and *"continue guiding the remaining Build 20 checks"* is C's role, so **"you implement" is read as C**. A reviewer cannot independently review their own implementation, which is the same reasoning the owner accepted for Batches 1b, 1c and F-SEC-1. A will implement instead if the owner meant A.

**Baseline and shape:** `frontend/xfer3-sent-controls-visible @ cf9b75b` stays the reviewed baseline (both reviews complete). **The two additions land as separate commits on top of it**, so each is reviewable on its own.

**A's payment-boundary review criteria, set BEFORE implementation so C can build to them:**
- **Decision 2 (the confirm dialog) is the payment boundary.** `confirm-and-release` must be invoked **only** after the explicit confirmation choice, never on the first tap. **Cancel must send nothing.** The copy must say plainly that confirming **releases payment to the seller**. **The single-flight lock stays.** **No server file changes**; `confirm_transfer_received`'s rule (buyer only, `status = 'seller_sent'`) is untouched. **X5 and X6 MUST change, deliberately**, because they currently pin one-tap release (X5: invoke on the press; X6: no alert before the server answers). Their changed form is the evidence the behaviour moved on purpose. A mutant that restores one-tap release must fail them.
- **Decision 1 (the provider handoff) touches the boundary only indirectly:** opening the provider must cause **no state change and no release**, and the arrival prompt that follows a return must **offer** confirmation and never **perform** it. *(**A's framing CORRECTED by D, verified by A at `cf9b75b`:** A had described the arrival prompt as a **second road to release** that the dialog might miss, and said so to the owner. **It is not one today.** `handleConfirm` has **exactly one call site** — `:414`, the "I got my tickets" button. The arrival prompt's **"here"** (`:388`) only dismisses the prompt and **highlights** that button — its own comment reads *"Dismisses the question only; confirmation is the control below"* — **"not yet"** only dismisses, and **"problem"** routes to `handleDispute`, which carries its own alert. **So a dialog on the button covers the only road that exists.** What A's instinct did name is a real but **undefended invariant**: nothing pins "the arrival prompt never releases", and the natural shortcut edit — wiring "here" straight to `handleConfirm` — would open exactly the bypass A described with every current test green. **D's test, which A adopts: press the arrival prompt's "here" and assert no `confirm-and-release` call and no release dialog — only the highlight.** The test is kept; the framing that justified it is corrected.)* Showing the button "provided there is a valid provider destination" means an absent or invalid destination shows **no button** rather than a dead one. Omitting empty contact fields means **no `null`, `undefined` or empty value interpolated into the instructions.**

**The one PR, and a base problem the owner should know about now rather than at PR time.** The clean base for this PR is `integration/device-verify-20260918` (`8da50c0`, Build 20's tree), so the PR shows F-XFER-3 and the two additions and nothing else. **That branch, and the Build 20 tag, exist only on A's machine**: A checked, and neither they nor `frontend/xfer3-sent-controls-visible` are on the remote. A's pushes are blocked by a permission gate in this session, and C and D have both declined to push on A's behalf, which is correct. So when the branch is ready, the options are: **(a)** the owner pushes the integration branch and the Build 20 tag (the one-line command A gave earlier), which also closes the standing traceability gap, and the PR bases on it cleanly; or **(b)** the PR bases on `release/production-gate-20260918`, and its diff also carries all of Build 20's already-reviewed batches, which buries the new work. **A recommends (a).** Nothing is needed until C's commits are ready.

**Unchanged:** no merge, no new build, no handset testing of these changes until they are in a build. **The two sandbox reads are still not authorized in A's session** and have not been run.

### Owner-authorized reads RUN, and Build 20 published (A, 2026-09-18) — authorization given to A DIRECTLY

**The owner, to A directly:** *"run both sandbox read-only checks now—S8only's deadline, buyer_viewed_at and notification around 11:58 AM September 18; and whether my buyer account saved a $105 bid on Device D7 around 11:43 AM. Report the results to C. Preserve all existing restrictions on proof-file access and Sandbox L7."* And: *"I choose option (a): publish the Build 20 integration branch and tag … You are authorised to attempt that push through your normal permission/approval mechanism."*

**How the reads were bounded.** Script `scratchpad/dv20/owner_reads_20260918.sh`, output logged beside it. It refuses unless the connection string names the sandbox `ofaidukbieeekqaboscm` and refuses the production ref outright; one `begin read only … rollback` transaction, and the output confirms **`tx_read_only=on`**. **No `storage.objects` access, no signed URL, no proof-file metadata, nothing touching Sandbox L7.** S8only's evidence path is reported **only as a boolean** — the path itself was not read out. Run at **16:46:13Z**.

**(1) S8only — `8f59d37e-52fd-4733-b311-532445ff441c`**

| Read | Result |
|---|---|
| rows matching the prefix | **exactly 1** (stop condition not met) |
| status | **`seller_sent`** |
| buyer | **the owner's buyer account** (`919d511e…`) |
| event | **Sandbox S8only** (not L7) |
| `expires_at` | **`2026-09-09T01:20:22Z`** — non-null, and past |
| `buyer_viewed_at` | **`2026-09-18T15:58:05.544Z`** = 11:58:05 ET |
| `transfer_evidence_path IS NULL` | **true** |
| `transfer_viewed` notification | **exactly 1 row, created `2026-09-18T15:58:05.544Z`, recipient = the seller** |

**What that settles:**
- **The write is RESOLVED: the owner's 11:58 open was the FIRST view, and it changed sandbox data.** `buyer_viewed_at` carries the owner's open time to the millisecond, and the seller's `transfer_viewed` row carries the **identical** timestamp — the same transaction, via `058`'s NULL→NOT NULL trigger. **One sandbox row updated, one in-app notification row written to the seller.** *(This read did not check delivery of that notification; the records hold the sandbox push key as deferred, so no push could have been sent — stated from the records, not from this read.)*
- **The fix evidence condition HOLDS: `expires_at` is non-null.** So on the pre-fix code this exact transfer would have shown **"Transfer window expired"**; on Build 20 the owner saw **no window line**. **DV-20-9 is therefore genuine device evidence for F-XFER-2** on a sent transfer — no longer conditional.
- **No signed URL could have been minted for S8only:** the proof-view effect requires a stored path, and there is none.
- **A data-derived check on the account:** `mark_transfer_viewed` only updates where `buyer_id = auth.uid()`, and it updated — so at 11:58 the owner was signed in as `919d511e…`.

**(2) Device D7 — the $105 bid around 11:43 ET**

| Read | Result |
|---|---|
| listings named "Device D7" | **exactly 1** (`b1c3c478…`), `active`, the owner's buyer is **not** the seller |
| `current_bid` | **100** |
| the owner's buyer's bids on it, 15:30Z–16:00Z | **NONE** |
| **all** bids on it, 15:30Z–16:00Z (count only, no identities) | **0** |
| the owner's buyer's bids on it, **ever** | **0** |

**What that settles: NO bid was saved.** No account bid on Device D7 in the window, and the current bid is still $100. **The "Bid failed / TypeError: Network request failed" alert was TRUE** — the insert never committed — even though it showed the user a raw technical string (F-BID-3). The all-bidders count makes this conclusion **independent of which account was signed in at 11:43**. **DV-20-4's open question — "whether a bid row was written" — is CLOSED: none was.** F-BID-1 itself still has no device evidence; that was about a form built on a failed *read*, which neither screenshot shows.

**(3) Build 20 PUBLISHED — the push succeeded.** A attempted it through the normal mechanism, as authorized, and it was **not** blocked this time. The remote now holds **`refs/heads/integration/device-verify-20260918` → `8da50c0`** and the annotated tag **`candidate/2026-09-18-build-d1`** (tag object `f01c99ce`, **peeling to `8da50c0`**) — A confirmed with `ls-remote` after the push. **The standing traceability gap is CLOSED**: the build's source can now be resolved from the remote by anyone. The F-XFER-3 PR can base on the integration branch and show only the follow-up work.

**Unchanged:** no merge, no new build. The two retained proof objects were not touched. Sandbox L7 was not touched.

**Addendum — the reads were run TWICE, independently, and agree to the millisecond.** C's message asking A not to run (because D had) **arrived after A's read had already completed at 16:46:13Z**; the owner had authorized **each of A and D directly**, so both runs were authorized, and both were read-only, so the duplication changed no data. **What it bought instead: two independent sessions, two transactions, identical results** — `buyer_viewed_at` and the seller's `transfer_viewed` row both at `15:58:05.544Z`, one notification, `expires_at` non-null (09-09), and zero bids on Device D7 (D's window was the whole of the 18th, broader than A's 15:30–16:00Z). **Recorded as corroboration, and as a coordination lesson: when two sessions each hold a direct authorization for the same read, the first to start should say so before running.**

**D's two additions, recorded as D's:**
- **S8only's `auto_release_at` (09-11) has passed without release** — it is one of the **stranded transfers** already on record: auto-release cannot fire in the sandbox while no service key is in the Vault (the D-found hazard, 0 of 191 cron calls returning 2xx). Consistent with the records; not a new defect.
- **The $100 current bid matches the earlier screenshot, so the bid form the owner used was built from a SUCCESSFUL read.** That is an inference about the data's provenance — a failed read would have produced a `$0`-derived floor — not about *when* the form loaded or *which* buttons were pressed, so it stays inside the owner's instruction not to infer the sequence. **It sharpens what DV-20-4 did not test: the F-BID-1 failed-read path was not exercised at all.**

**Pushing C's branch — coordination, recorded before it crosses like the reads did.** `frontend/xfer3-sent-controls-visible` is **not on the remote** (A checked). **C** said it will push the branch when its gates are green; **D** was also authorized by the owner to push the reviewed commit, and **D's push was refused by the harness — D stopped rather than route around it**, and will not try `gh` or the API; it is with the owner. **A is not pushing it for either of them.** A has asked C and D to settle which of them pushes, so the same branch is not pushed twice by two sessions, as the reads were run twice. D's instinct to push **`cf9b75b` by commit** rather than the moving tip is sound — the owner authorized the *reviewed* commit — and a later push of C's descendant tip would fast-forward over it cleanly.

**Diff size at the integration base, D's measurement:** 3 commits, 2 files, **+281/−3**, no `supabase/` — against the production gate it would have been 23 commits and 25 files. That is the base the owner's option (a) bought.

**Push settled — nobody pushes C's branch until the owner decides, and the PR waits on that.** C has declined to push `frontend/xfer3-sent-controls-visible` itself, on the ground that D's authorized push was refused at D's gate and is pending the owner, so a push from C would reach the same result by another door — the same boundary every session has held tonight. **A agrees and is not pushing it either.** **Consequence, stated plainly: the one PR cannot be opened until the branch is on the remote, so the PR is BLOCKED on the owner's decision about D's refused push** (or on the owner authorizing some other session to push). The review work is unaffected — A reviews from the shared object store.

**C's confirmation on the arrival prompt:** nothing routes it through the dialog. "They're here" stays dismiss-plus-highlight; **O6** pins that it sends nothing, and decision 2 adds **C8** — no invoke and no dialog from "here". `handleConfirm` keeps its single call site. *(A will verify O6 and C8 at the head C hands over, as with every head.)*

### Owner's decisions 1 and 2 — A's payment-boundary review: **PASS**, with A's own mutants (A, 2026-09-18)

**Heads, resolved by A in the shared object store (branch not pushed):** `cf9b75b` (reviewed baseline) → **`ceb4e61b`** (decision 1) → **`c093cdcf`** (decision 2), linear, one commit each, so each decision is reviewable alone as the owner required. **Gated surface `cf9b75b..c093cdcf` over payments, checkout, signOut, `supabase/`, `scripts/`, `.github/`, `app.json`, `package.json`, `eas.json`: ZERO lines.** Seven files, +589/−24: the receive screen, `providerHandoff.ts`, `transferState.ts`, and four test files.

**A's gates at `c093cdcf`, A's own runs, no concurrent vitest:** typecheck **0** · lint **0**, 29 warnings · vitest **119 files / 2371 tests, all passed**. C's numbers reproduce exactly.

**Decision 2 — THE PAYMENT BOUNDARY — read line by line:**
- `handleConfirm` now opens a dialog and **sends nothing on the tap**. `confirm-and-release` is reached **only** from the dialog's explicit action (*"Confirm and release payment"*), inside the **same** `flight.run(confirmReceipt)`; **`confirmReceipt`'s body is untouched**, so the request, its `{ transfer_id }` body and every server rule behind it are exactly as before.
- **Cancel** calls only `answered()` — **it sends nothing.** The dialog is `cancelable: false`, so it cannot be dismissed without one of the two answers.
- **Copy:** title *"Confirm you received the tickets?"*, body ***"Confirming receipt releases payment to the seller.** Only confirm if you can see the tickets in your ticket account."* — plain, and the same claim the screen's release warning already makes.
- **Two synchronous guards:** a `confirmAsking` **ref** set before the dialog opens, so a same-tick double tap cannot stack a second dialog; and **`flight.inFlight`**, which A verified is a **getter on a ref-held single-flight object** (`src/lib/async/singleFlight.ts:22`, held by `useSingleFlight`'s `useRef`), so it is synchronously accurate, not stale React state.
- **`handleConfirm` still has a single call site** — the button. The arrival prompt's "here" is unchanged (dismiss plus highlight), pinned by **C8**.
- **X5 and X6 changed deliberately**, as required: X5 now reads *"confirming asks first, then stays single-flight."*

**A's OWN mutants — run in A's worktree, never C's, with predictions written first, applied-and-changed asserted, and a digest-verified restore to a clean tree** (`scratchpad/dv20/a_boundary_mutants.py`):

| Mutant | A's prediction (must include) | Killed by | Matches C's harness |
|---|---|---|---|
| **AM-D2-1** — one-tap release restored at the button | C1, C4 | **C1, C2, C3, C4, C5, C6, C7, C9, X5, X6** | yes — C's CM1 |
| **AM-D2-2** — Cancel releases payment | C3 | **C3, C9** | yes — C's CM2 |

**Both predictions met, and both kill sets are identical to C's independently run harness.** That is the boundary proven from two directions: the tests fail if one-tap release comes back, and they fail if Cancel ever sends.

**Decision 1 — outside the boundary, and A checked that it stays outside it:**
- **It releases nothing.** `openProvider` sets only local handoff state and calls `Linking.openURL` — no RPC, no invoke, no table write. `returnPrompt(status)` now drops its delivery argument and asks on any sent transfer, but the prompt **only asks**, and "here" only highlights (C8).
- The render condition becomes `seller_sent || (pending && !needsDeliveryInfo)` — **exactly the old condition plus the one target state** (sent, no delivery details); pending still waits for delivery details. *(Same shape as D's XM9 mutant, but on the handoff block, where it is intended.)*
- **No destination, no button:** the pre-existing `{link ? … : null}` guard.
- **"Omit empty contact fields" holds, and A verified why rather than taking the comment:** `interpolateStep` would print *"(email not yet provided)"* for a missing value — **but A parsed every step in `src/lib/platformInstructions.ts`: all 13 `{buyer_email}` / `{buyer_phone}` placeholders sit in SELLER-role steps; buyer-role steps contain none**, and the receive screen renders `role="buyer"`. So no contact placeholder can reach the buyer — and C's suite **pins that over every platform**, so it is defended, not merely true.

**A finding C made against its own earlier suite, recorded because it bears on A's earlier PASS:** since `cf9b75b`, X6's *"not shown as confirmed"* assertion checked the `buyer_confirmed` **title**, which is a `StateBlock` prop and never appears in the flattened text — **so that check could not fail.** C now checks the body copy, and C's CM12 proves it live. **A's confirm-path PASS at `a739a40`/`cf9b75b` cited X6 without catching that half of it was vacuous**; A had checked X6's `alerts === []` half only. Recorded against A's review as well as C's test.

**One observation, not a finding:** `react-native-web`'s `Alert.alert` is a **no-op** (A read `node_modules/react-native-web/dist/exports/Alert/index.js`: `static alert() {}`). So on the Expo **web** target the new dialog would never appear and confirm would be unreachable — **exactly as "Report issue" already is.** `app.json` carries a `web` block, but **no web export appears in `package.json` scripts or CI**, so A finds no evidence it ships. Relevant only if it ever does.

**Status: A's payment-boundary review PASS on both decisions. D's behaviour review outstanding. The PR remains BLOCKED on the owner's push decision.** No merge, no build, no handset testing until these are in a build.

### D's behaviour review of decisions 1 and 2 — correct, with two undefended invariants; one is on A's boundary (A, 2026-09-18)

**D: the behaviour is correct for both decisions at `c093cdcf`.** Two findings, both *undefended invariants*, not defects.

**(1) On A's payment boundary — a failed release could leave "I got my tickets" enabled but dead.** The dialog lock `confirmAsking` (a ref) re-arms through `answered()`. **C9 pins the re-arm after Cancel; nothing pinned it on the confirm path.** D's mutant drops `answered()` from the explicit release action: after a failed release X6 sees the button re-enabled, but the lock is still held, so a tap does nothing and the buyer cannot retry without leaving the screen — and **all 2371 tests pass.** **A verified today's code is correct:** the release action calls `answered()` at `:211`, *before* `flight.run(confirmReceipt)`, so the lock is released the moment the buyer chooses, and `flight.inFlight` alone guards the in-flight window. **D proved a C10 that passes on C's code and fails alone under the mutant, with a witness that the release really went out before the failure.**

**A's judgement on the money angle, which D asked A to settle:** **no money is at risk even under the mutant.** A checked that `handleDispute` never reads `confirmAsking`, so **"I haven't received them" stays available** to a buyer stuck on a dead confirm; and in production, where the auto-release cron runs, a transfer the buyer could not confirm is still carried to release at 72 hours. **The harm is a silent payment control after a server error** — exactly what pushes a buyer toward support, or toward disputing a transfer they meant to confirm. **So it does not need an owner decision; it needs C10**, which is within the owner's "focused checks". A tells the owner in one line, as closed-by-test once C10 lands.

**(2) Off A's boundary, but it corrects something A told the owner.** *"Omit empty contact fields"* holds today **only by composition**: A confirmed that **every receive and send transfer test mocks `PlatformInstructions`** (`vi.mock(... () => ({ default: 'PlatformInstructions' }))` in all five suites), so the real component never renders under test. What IS pinned is the **step data** — no buyer-role step carries a contact placeholder, over every platform. What is NOT pinned is the **component**: D's *"Send to: null"* mutant, rendering a contact line from the component itself, passes the whole suite. **A had told the owner "a test checks that for every ticket provider" — true of the data, but it implied protection of the rendered screen that does not exist.** A real-component test closes it; D has proposed one.

**Record correction — O6 vs C8.** A's record said *"O6 pins that it sends nothing, and decision 2 adds C8."* **At the tip that is no longer accurate:** `handleConfirm` now opens a dialog rather than releasing, so **O6 no longer stops "They're here" from confirming — C8 does** (with a source guard). C's d1 harness still predicts O6, so it shows a mismatch when run at the tip. **Not a gap** — the guard moved to C8 — and D has told C.

**Push: still with the owner; nobody has pushed.**

### Decisions 1 and 2 — D's two tests landed at `0f329c3a`; A verified, including one hash that did not exist (A, 2026-09-18)

**The standard caught a non-existent commit.** C first reported the new head as **`1a1c32d0`**. A resolved it before reading anything: **no such object exists** in the shared store, and no object even begins with `1a1c32`. The branch ref (shared across worktrees) showed the real tip, **`0f329c3a`**, and C corrected itself independently moments later — it had written the message in the same parallel step as the `git commit`, before the id returned. C has added that lesson to the shared memory. **Had the hash been relayed rather than resolved, a reviewer would have gone looking for a tree that never existed.**

**`0f329c3a` verified:** `c093cdcf` an ancestor; **test-only** — two files, +60, `app/`, `src/`, `supabase/` untouched; **the receive screen is byte-identical to the reviewed `c093cdcf`** (`942ed5e8…` both). So **A's payment-boundary PASS covers exactly this code.**
- **C10** (`tests/receive-transfer-confirm-dialog.test.ts:263`): *after a FAILED release, a later tap asks again — the lock re-arms on the confirm path too.*
- **I1** (new `tests/platform-instructions-buyer-render.test.ts`): renders the **real** `PlatformInstructions`, not a mock, for **every platform**, buyer role, `buyerEmail: null` and `buyerPhone: null`, with a **witness** that it painted and its first step present, and asserts no `{buyer_`, *"not yet provided"*, `null` or `undefined` — which closes D's *"Send to: null"* component mutant.

**A's gates, with a concurrency incident handled rather than ignored.** A's first run found **another session's vitest already running**, so under A's own rule that run was **void** and A waited. The re-run started alone and **passed 120 files / 2373 tests** (typecheck 0, lint 0 / 29), but company appeared mid-run. **A counts that green result as valid and says why:** concurrency produces *spurious failures* (timeouts), never spurious passes. **A mutant's evidence is a failure — the direction concurrency corrupts — so A's harness refuses to run a mutant with company present**, and it did refuse once. Run again alone, with a clean baseline measured first:

| A's mutant (alone throughout, restore digest-verified) | Prediction | Baseline | Killed by |
|---|---|---|---|
| **AM-D2-3** — drop `answered()` from the release action | C10 only | 0 of 10 failed | **exactly C10**, of 10 |

That matches D's mutant exactly, so **C10 is proven by two sessions independently.**

~~**One residual, low, recorded rather than left implicit — the composition gap one level up.** I1 pins the component **given** `role="buyer"`; the receive-screen tests mock the component; so **nothing pins that the receive screen passes `role="buyer"`.** A copy-paste flip to `role="seller"` would pass the whole suite and show the buyer the **seller's** steps — which do carry `{buyer_email}`, so *"(email not yet provided)"* would reach the buyer. It is hardcoded today and correct. A one-line source assertion on the screen would close it. **Offered to C and D; not a blocker.**~~ **WITHDRAWN — A's "residual" was FALSE, and C was right to say check the file.** `tests/receive-transfer-sent-handoff.test.ts:139` (**O1**) asserts `expect(instructions(host)?.props.role).toBe('buyer')` on the **rendered screen**; the component mock is a string element, so its props are exactly what the screen passes. **A then ran the mutant itself, alone, with a clean baseline (0 of 15): flipping the screen to `role="seller"` is killed by exactly O1**, matching C's OM7. So I1 pins the component *given* `role="buyer"`, and **O1 pins that the screen passes it** — the composition is closed end to end. **Cause, recorded against A:** A asserted an **absence** ("nothing pins …") from a `grep` whose pattern could not match the assertion's actual form (`.props.role).toBe('buyer')`). **An absence claim needs a search that could have found the thing — or, better, a mutant**, which settled this in one run the moment A tried it. A should have run it before writing the residual, not after.

**Status: both decisions reviewed and pinned. The PR remains BLOCKED on the owner's push decision.** No merge, no build.

**Process finding (D's, A confirmed): both sessions' concurrency guards over-matched, and it only ever erred toward refusing.** `pgrep -f vitest` matches any process whose **command line contains the word** — including a shell that is merely *sleeping in a wait loop* whose script text says `pgrep -f vitest`. D found it by printing the match instead of loosening its guard on a theory: its "vitest busy" abort matched **A's** waiting shell (pid 67383, parent = A's session). **A confirmed the over-match on its own machine:** at one moment `pgrep -f vitest` returned **10** pids while a guard keyed on the executable (`comm == node` **and** args mentioning vitest) found exactly **1** real vitest process. **Consequences, stated precisely:**
- **No result is contaminated.** The flaw causes *false "busy"*, never *false "clear"* — a real vitest node process always matches — so every run A recorded as alone *was* alone.
- **A's earlier "company appeared mid-run" may have been D's sleeping loop rather than a real test** — which changes nothing, because that run was green and concurrency can only fake failures.
- **D's PM1 is valid:** it ran against the full suite while A's shell was only sleeping, and it killed exactly the predicted I1 — *"Send to: ${buyerEmail}"* in the real `PlatformInstructions` — which is not the shape contention produces.
- **Fix adopted by both:** match real `node` vitest processes by executable name, not text in any shell's arguments.

**Serialised:** A's harness is **finished** — A has no further mutants for this commit. A's **AM-D2-3** already killed exactly C10, alone; D's CM13 on the same line would be a third independent confirmation, D's call.

### PR #75 opened — F-XFER-3 + owner decisions 1 and 2, DRAFT, DO NOT MERGE (A, 2026-09-18)

**Authority:** the owner's direct instruction to A — *"Coordinate with A on one PR. No merge or new build yet"* — and the owner's choice of option (a) to publish Build 20 so this PR contains only the follow-up. **The owner pushed `frontend/xfer3-sent-controls-visible` themselves** after D's push was refused by the permission check. D's message quoting the owner's *"have A open the single draft, do-not-merge PR against the Build 20 base"* was treated as confirmation of readiness, **not** as the authority — A already held that directly.

**Verified by A before opening, not taken from D's message:** `ls-remote` shows head **`0f329c3a60f9d050b8b1ee9a8e63de8c89e7825b`** (= the reviewed commit) and base **`8da50c064a7835a1f79e1fcdc3546ffbe792b014`** (Build 20); base is an ancestor of head; range **6 commits** (`a739a401`, `2dbcb029`, `cf9b75b7`, `ceb4e61b`, `c093cdcf`, `0f329c3a`); **8 files, +923/−20**; **zero lines** under `supabase/`, the gated client files, `scripts/`, `.github/`, `app.json`, `package.json`, `eas.json`; and `gh pr list --head … --state all` returned **none**, so this is the only PR. D's figures matched A's exactly.

**[PR #75](https://github.com/SnatchIt-app/snatchit/pull/75)** — **draft: true**, base `integration/device-verify-20260918`, head `frontend/xfer3-sent-controls-visible` @ `0f329c3a`, **6 commits** (confirmed via `gh pr view`). The body states **"DRAFT — DO NOT MERGE. No deployment, no build requested."** in its first line, uses What · Why · Verification · Rollback · Blast radius, names every review as its author's, and carries the evidence limits: **no device evidence yet**; C's relabelled harnesses not re-run in full by D; and the X6 vacuous assertion A's own review had missed. It says F-XFER-3 is **not claimed as observed production behaviour** (the owner's restriction). **CI: 8 of 9 checks pass and 1 is skipped** (`Supabase Preview`, as for a diff with no migrations) — *corrected from "8 of 9 checks pass (Supabase Preview skipped)", which D's count exposed: a skipped check did not pass, it did not run.*

**Still barred:** merge, deployment, new build. PRs #72–#74 remain draft and do-not-merge.

**Wording correction (D's precise count, A applied everywhere):** A had written *"all nine checks pass"* for PRs #72–#75. **Each had 8 passing and 1 skipped** (`Supabase Preview`, which skips when a diff carries no migrations). A skipped check did not pass — it did not run — so the records now say **"8 of 9 pass, 1 skipped"**. Nothing about the underlying results changes; the claim is now the size of the evidence.

### BUILD 20 HANDSET PASS CLOSED (owner, 2026-09-18) — C's records resolved; A's checks on the next-build list (A, 2026-09-18)

**Owner's rule, as C records it:** *"Skip DV-20-6 and close the Build 20 handset pass. Keep the skipped, blocked and unobserved checks clearly labelled; don't count automated coverage as device evidence."* No new fixtures and no further handset runs for now.

**C's records, resolved by A (not taken from the message):** `2ded6a8f` (pass CLOSED) and `bf71ffb7` (next-build list) both exist and both sit on `frontend/premium-experience-backlog`, in `docs/product-v2/DEVICE_VERIFICATION_CHECKLIST.md`. **C's checklist is the row-level record; this entry is the release view of it.**

| Label | Rows (times ET) |
|---|---|
| **PASSED — device evidence** | DV-20-1 (11:34), DV-20-2 (11:39), DV-20-3 (13:33), DV-20-7 (14:15; seller view, "Mark as sent" enabled in appearance only, **never pressed**), DV-20-8 (13:35), DV-20-9 (11:58) |
| **PASSED on the final state only** | DV-20-4 (11:43:47). **F-BID-1 has NO device evidence.** No bid was written (A's and D's reads, above). |
| **PASS (weak), by construction** | DV-20-12 (14:09), one picker. A pass cannot show the taps landed in the same frame. |
| **UNOBSERVED** | DV-20-10 (14:09), DV-20-11 (14:12). The saves completed; the property itself was not seen. |
| **SKIPPED (owner)** | DV-20-6 |
| **BLOCKED** | DV-20-5 (no handset method), DV-20-13 (needs a staged security notice, which is a sandbox write, not authorized) |

**Device evidence by fix:**
- F-HOME-1: DV-20-1/2/3.
- F-XFER-1: DV-20-7.
- F-XFER-2: DV-20-8 (pending) and DV-20-9 (sent).
- **None:** F-BID-1, F-AVATAR-1/2/3, F-DESTRUCT-1, F-SEC-1, F-SEC-2. Those fixes rest on source and test review alone, and **automated coverage does not change that label.**

**Sandbox writes during the pass** are recorded in `SANDBOX_ACCEPTANCE_WINDOW_MANIFEST.md` §18, each marked read-confirmed or C-reported.

**Awaiting the next build:** [PR #75](https://github.com/SnatchIt-app/snatchit/pull/75) only (draft, head `0f329c3a`, base `8da50c0`): F-XFER-3 plus the owner's decisions 1 and 2. C reports nothing else reviewed and ready. **What goes into the next build, and when, is the owner's decision.**

**F-LAYOUT-2 — NEW, recorded only.** The Home notice has no horizontal inset. Raised by C during the pass; not started. It sits with F-BID-3 and F-LAYOUT-1, also raised and not started.

**A's checks on C's next-build list (N1–N3), payment boundary. Derived from source, nothing run:**

1. **N1: C's claim "re-opening S8only writes no new data" HOLDS in source.**
   - `mark_transfer_viewed` (`0550:243`, the only definition after `039`) sets `buyer_viewed_at = COALESCE(buyer_viewed_at, now())`.
   - `058`'s `notify_transfer_state_inbox` sends `transfer_viewed` only when the value goes from NULL to NOT NULL. Every other branch needs a status or payout transition.
   - `transfers` has no `updated_at` trigger.
   - **Precisely stated:** the UPDATE still executes, writing a row version with identical values, so **no value changes and no notification.**
   - This is derived from the repo source that the sandbox chain carries. It is not a read.
2. **N2: a mis-tap costs more than "sandbox payment".**
   - The dialog's confirm action invokes the **`confirm-and-release` edge function** (`receive/[id].tsx`, `confirmReceipt`), not only an RPC. One stray tap records receipt and attempts the release in the sandbox, and the app cannot undo it.
   - **A's proposal, for C to evaluate:** load the screen online, **then turn Airplane Mode on before tapping "I got my tickets"**.
   - The dialog is local (`Alert.alert`, no network), so the check loses nothing. A mis-tap then fails on the device, for three reasons:
     - `functions-js` turns a fetch rejection into `FunctionsFetchError` with no retry.
     - React Native's iOS networking uses `defaultSessionConfiguration`, with no custom provider in `expo*`, so nothing waits for connectivity.
     - The screen's `AppState` listener refetches only after a provider handoff, and the receive screen does not subscribe to network status.
   - **Expected mis-tap result:** "Error / Something went wrong. Please try again." and no request reaches the server. **Derived, not device-tested.**
   - A's AM-D2-2 ("Cancel releases") was killed by C3: automated, **not device evidence.**
3. **N3 needs nothing added.** It is read-only unless something is submitted, and C already says not to submit. It is still a handset run, so it waits on the owner with N1 and N2.
4. **N1's provider question.** S8only's platform is in neither A's records nor C's. A **one-column sandbox read** (`listings.platform` for `92f8effe…`) would settle whether N1 can test "Open <provider>" and the decision-1 return question. **It is not requested and not run; it needs the owner's authorization.** Without it, the return question stays UNTESTED on device, as C records.

**Observation, not filed (owner's call):** a replaced avatar is never deleted.
- Each save uploads a new timestamped object (`avatarImage.ts:124`, `<uid>/avatar_<ms>.<ext>`), and no client code removes from `avatars`.
- The bucket is public (`avatarImage.ts:6`, `getPublicUrl`).
- So a photo the user replaced stays in storage and stays reachable by its path. This is pre-existing, not introduced by F-AVATAR-2/3.
- A did not check the bucket's hosted policy. The claim is from source.

**Still barred:** merge, deployment, new build, handset runs, sandbox reads beyond those already authorized. PRs #72–#75 remain draft and do-not-merge.

**Addendum — C adopted the N2 safeguard (resolved by A at `26a1b212`, `frontend/premium-experience-backlog`).**
- N2 now runs offline: load S8only online, turn Airplane Mode on, tap "I got my tickets", check the dialog, tap Cancel. It is labelled as derived from code, not tested on a phone, and "Do not tap Confirm" stays in the step.
- The avatar-retention observation is in C's backlog as pre-existing, not filed, and the owner's call.
- The N1 provider read is recorded as needing the owner's authorization; it has not been requested.
- Nothing was run.

### NEXT SANDBOX PREVIEW BUILD — Build 21 SUBMITTED; S8only provider read RUN; F-AVATAR-4 FILED (A, 2026-09-18)

**Authority: the owner, directly to A.**
- *"prepare and submit the next sandbox preview build using Build 20's contents plus the reviewed PR #75 changes. Verify the combined version and run the required checks. No production merge or deployment."*
- *"Also authorised: the read-only check of S8only's ticket provider. Send C the result."*
- *"C is authorised to guide the next-build checks: inspect S8only's buyer controls and provider button, then load the screen online, turn Airplane Mode on with Wi-Fi off, open the receipt-confirmation dialog and cancel. Do not confirm receipt or release payment."*
- *"File retained old avatar files as a deferred storage/privacy finding. No deletion or cleanup."*
- Existing restrictions on the D1/D2 proof files and Sandbox L7 remain.

**Combined version: `0f329c3a60f9d050b8b1ee9a8e63de8c89e7825b`, the PR #75 head, used as it stands.** No new merge was needed.
- The remote holds it at `refs/heads/frontend/xfer3-sent-controls-visible` (A, `ls-remote`), and PR #75 is still draft and open, with base `8da50c06`.
- `8da50c0` (Build 20) is an ancestor. There are 6 commits after it and no merges: `a739a401` `2dbcb029` `cf9b75b7` `ceb4e61b` `c093cdcf` `0f329c3a`.
- The change is 8 files, +923/−20, all under `app/`, `src/lib/transfer/` or `tests/`.
- **0 files** under `supabase/`, the gated client files, `scripts/`, `.github/`, `app.json`, `app.config.*`, `eas.json`, `package(-lock).json`, `.env*`, `ios/` or `android/`.
- *A's first scope check returned a FALSE zero: an unmatched zsh glob (`app.config.*`) aborted the command before `git diff` ran. A re-ran it with quoted pathspecs, plus a witness that the same command returns the 8 files, before recording the 0.*
- Local annotated tag **`candidate/2026-09-18-build-d2` → `0f329c3a`**, **not pushed**. No push was authorized, and none is needed for traceability, because the source commit is already on the remote.

**D's independent provenance check: PASS (git only, no vitest or tsc).**
- D resolved the head, the base, the 6 commits and the 8 files the same way.
- D confirmed the same zero with witnesses: the pathspec returns 3 for `app/`+`src/lib/transfer/`, and returns `package.json` for a commit that did touch it.
- `eas.json`, `app.json`, `package.json` and `package-lock.json` are **blob-identical to Build 20**.
- D also checked the profile choice: `sandbox` is `ios.simulator: true`, so a handset build must use `preview`.

**Required checks, run by A on the combined tree** (clean worktree at `0f329c3a`, dependencies byte-identical to Build 20):

| Check | Result |
|---|---|
| `npm run typecheck` | **exit 0** |
| `npm run lint` | **exit 0**. 29 warnings, 0 errors, the same baseline as Build 20 |
| `npm run test` | **exit 0**. **120/120 files, 2373/2373 tests.** Run alone: no vitest process before or after, and D held off at A's request |

**Build configuration: unchanged from Build 20.** `preview` profile, `distribution: internal`, `EXPO_PUBLIC_APP_ENV=sandbox`, Supabase `ofaidukbieeekqaboscm`, Stripe `pk_test_…`, `appVersionSource: remote` with `autoIncrement`. Only the `production` profile points at `hqycwntpfoztoinemqns`/`pk_live`.

**Build 21, submitted:**

| | |
|---|---|
| **EAS build id** | **`1d78bb45-cd89-419f-b1e3-ba679ac7eb7f`** |
| **Build number** | **21**, assigned remotely by `autoIncrement`. No file was edited |
| **Commit, as EAS recorded it** | **`0f329c3a60f9d050b8b1ee9a8e63de8c89e7825b`** |
| Profile / distribution / version | `preview` · INTERNAL · 1.0.0 |
| Submitted from | worktree at the tag. `git status --porcelain --untracked-files=all` was **empty** before and after the upload; the only ignored file besides `node_modules` is ESLint's cache (`.expo/cache/eslint/…`), which `.gitignore` excludes from the archive |
| Logs / install page | https://expo.dev/accounts/jdt_inc/projects/snatchit/builds/1d78bb45-cd89-419f-b1e3-ba679ac7eb7f |

**Build 21 REPLACES Build 20 on the phone** (one bundle id, `com.jdt-inc.snatchit`), and the app does not display its build number.

**Evidence classes for this build (D's framing, which A adopts):**
- **PR #75 (F-XFER-3, decision 1, decision 2): source and test review only. NO device evidence.**
- **Build 20's contents:** unchanged in source, because PR #75 does not touch their files. **A Build 20 device result applies to Build 21 only by inference, not by observation.**

**S8only provider read: RUN, authorized directly to A.** 18:27:31Z, one `begin read only` transaction; the script refuses the production ref and requires the sandbox ref. **Two fields only:**
- status = **`seller_sent`**;
- `listings.ticket_platform` = **`other`** (listing `92f8effe`).

No delivery fields, evidence path, storage, other rows or L7.
- **Consequence, derived from `0f329c3a`:** `providerLink('other')` is null, so **S8only shows NO "Open <provider>" button**.
- The generic buyer instructions for `other` still render under the `seller_sent` gate. None of their steps holds a contact placeholder.
- **The decision-1 return question cannot be reached on S8only, so it stays UNTESTED on device.**
- The only sent transfers that could exercise it are D1/D2. Their Receive screens create a signed URL for the proof file (`receive/[id].tsx:105`), so **opening them as the buyer is proof-file access and is off-limits.** D adds that a fixture with a named platform would be a sandbox data change, and that decision is the owner's.
- **Sent to C before any testing.** C has updated its next-build list: no Open button expected, generic instructions, N2 run with Airplane Mode and Wi-Fi off (checked on the status bar), N3 out of scope, D1/D2 off-limits. C will confirm scope with the owner directly and will not start until A sends the build number and install link.

**F-AVATAR-4 FILED, DEFERRED:** replaced profile photos are never deleted and stay publicly reachable by their path. It is in the close-out's §3 (open findings) and §4 (deferred decisions). **No deletion or cleanup.**

**Correction to D's question, answered from the record:** `candidate/2026-09-18-build-d1` is on the remote because **A pushed it under the owner's option-(a) authorization** (see "Owner-authorized reads RUN, and Build 20 published" above), not someone else.

**Still barred:** merge (PRs #72–#75 stay draft and do-not-merge), production deploy, release, sandbox writes (**Confirm receipt stays forbidden on the handset**), keys, the D1/D2 proof files, Sandbox L7.

### BUILD 21 FINISHED — ready to install for handset verification (A, 2026-09-18)

| | |
|---|---|
| **Status** | **FINISHED**, no error. 18:30:22Z → 18:37:02Z, about 7 minutes |
| **Build number** | **21**, assigned remotely by `autoIncrement` |
| **Commit, as EAS recorded it** | **`0f329c3a60f9d050b8b1ee9a8e63de8c89e7825b`** = local tag `candidate/2026-09-18-build-d2` = the PR #75 head. D read the same record independently (`eas build:view`, read-only) while it was in progress |
| Platform / profile / distribution | iOS · `preview` (sandbox, `pk_test`) · INTERNAL |
| Version / SDK | 1.0.0 · 54.0.0 |
| Artifacts | the application archive (IPA) is present |
| **Install page** | https://expo.dev/accounts/jdt_inc/projects/snatchit/builds/1d78bb45-cd89-419f-b1e3-ba679ac7eb7f |

**What is true now:**
- The PR #75 changes have **source-and-test evidence** and an artifact that records their commit.
- They still have **NO device evidence.** That changes only through C's authorized checks: the S8only buyer controls and the absent provider button, then the dialog opened offline (Airplane Mode on, Wi-Fi off) and cancelled. **Confirming receipt is not authorized.**
- **Installing Build 21 replaces Build 20.**

**Unchanged and still barred:** merge (PRs #72–#75 draft, do-not-merge) · production deploy · release · sandbox writes beyond the authorized checks · keys · the D1/D2 proof files · Sandbox L7 · migrations 138/141/115–120 unapplied · F-AVATAR-4 cleanup.

### BUILD 21 HANDSET CHECKS COMPLETE (owner-reported; C's record `5007ce16`, resolved by A) (A, 2026-09-18)

**C's records resolved by A**, all on `frontend/premium-experience-backlog`, in `DEVICE_VERIFICATION_CHECKLIST.md`:
- `874fce81` (14:38): Build 21 recorded.
- `66b6b90b` (14:46): the dialog was observed ONLINE at 14:44.
- `5007ce16` (14:51): checks complete.

| Check | Label | What was seen (owner-reported, times ET) |
|---|---|---|
| **N1** (F-XFER-3 + decision 1), S8only | **PASSED — device evidence** | "I got my tickets" and "I haven't received them" are both visible. The delivery form is present, the generic "How to receive your tickets" instructions show, **there is no "Open …" button** (`ticket_platform = other`, per A's 18:27:31Z read), and there is no blank or "not provided" contact text. |
| **N2** (decision 2), S8only | **PASSED — device evidence, run ONLINE** | 14:44: "I got my tickets" opened the dialog with the exact `CONFIRM_RECEIPT_DIALOG` copy and separate buttons. The owner **tapped Cancel**: the dialog closed and the screen stayed on Receive Transfer. **"Confirm and release payment" was NOT tapped.** |

**N2 deviated from the authorized procedure, recorded plainly because it is on A's payment boundary.**
- The owner authorized N2 as *"load the screen online, turn Airplane Mode on with Wi-Fi off, open the receipt-confirmation dialog and cancel"*.
- **The dialog was opened and cancelled while ONLINE**, before the offline step. The owner then instructed that it be recorded as tested online.
- Airplane Mode was only a safeguard against a stray Confirm; the property under test is the same online or offline, so the PASS stands.
- **For that tap the safeguard was not in place.** A stray Confirm would have reached the server. None happened.
- The online run is, if anything, the more realistic condition: a Cancel that wrongly released would have released for real, and the screen shows it did not.

**How strong "nothing was released" is:** **owner-reported screen state plus source. No database read.**
- At `0f329c3a`, Cancel's handler only clears the dialog lock (`onPress: answered`). A's mutant AM-D2-2 ("Cancel releases") is killed by C3.
- A successful confirm would have set the screen to `buyer_confirmed` and shown "Receipt confirmed"; a failed one would have shown an Error alert. **Neither was seen.**
- C's record says the same: *"Whether Cancel sent anything is not observable on the handset."*
- **Optional, NOT requested and NOT run:** a read-only check of S8only's `status`, `payout_released_at` and its `transfer_confirmed` notification count would confirm it at the server. It needs the owner's authorization.

**Device evidence by change (Build 21):**
- **F-XFER-3:** controls visible on a sent transfer without delivery details. ✔
- **Decision 1:** the no-destination branch (instructions shown, no button). ✔
  - **The "Open <provider>" branch and the return question stay UNTESTED on device.** There is no in-scope fixture: S8only's provider is `other`, and D1/D2 are off-limits.
- **Decision 2:** the dialog opens with the exact copy, and Cancel closes it without changing the screen. ✔
  - **Not tested on device:** single-flight through the dialog, the lock re-arming after a failed release, and the release itself. These are automated tests only, which are not device evidence.
- **Build 20's contents** carry over to Build 21 **by inference only**. No row was re-run on Build 21.

**Sandbox writes: none new** (manifest §18 addendum).
- Re-opening S8only rewrote an already-set `buyer_viewed_at` and sent no notification. That is **derived from source** (A's N1 check), not read.
- "Nothing confirmed or released" is **owner-reported and from source**, as above.

**Still barred:** merge (PRs #72–#75 draft, do-not-merge) · production deploy · release · Confirm receipt · D1/D2 proof files · Sandbox L7 · F-AVATAR-4 cleanup. **What happens to PR #75 next is the owner's decision.**

**D's review of the Build 21 records (D, 2026-09-18): both records state the evidence classes correctly. Two precision notes; neither changes a verdict. A applies both.**

1. **"Re-opening sent no notification … derived from source": the source is now named, and the wording is tightened.**
   - The source is the **repo migrations at `0f329c3a`**:
     - `0550` `mark_transfer_viewed` (nothing later in `LC_ALL=C` order) does `COALESCE(buyer_viewed_at, now())`;
     - `058`'s `transfer_viewed` producer fires only when `OLD.buyer_viewed_at IS NULL` and carries a dedupe key;
     - the `033`/`034` triggers are `AFTER UPDATE OF status` and do not fire.
   - **The sandbox's deployed function bodies were not read.**
   - Each opening still runs one UPDATE, which writes a row version with the same value, and the AFTER UPDATE triggers still evaluate. So **"no data changed"** is the precise claim, and ~~"no new sandbox write"~~ is withdrawn wherever this entry and the manifest addendum used it for re-opening S8only.
2. **Proof-file access on S8only: D's gap was already settled by an authorized read, and A should have cited it.**
   - At `0f329c3a` (`receive/[id].tsx:101-109`), opening a `seller_sent` transfer mints a 1-hour signed URL **only if `transfer_evidence_path` is non-null**.
   - A's owner-authorized read at **16:46:13Z** included that column as a boolean: **`evidence_path_is_null = true`** for S8only (recorded above: "No signed URL could have been minted for S8only"). §16 agrees: DV-IMG-10 selected an image on S8only and attached nothing.
   - **Bound, stated rather than assumed:** the Build 21 openings came later (from 18:44Z), and the 18:27:31Z provider read deliberately did not include the path. The path could only have become non-null through a seller-side `attach_transfer_evidence` or `mark_transfer_sent` on S8only, and no such action is recorded. The only seller-side check since, DV-20-7, was on a pending transfer.
   - So "no proof-file access on S8only" rests on **a READ at 16:46:13Z plus no recorded seller action since**. No further read is proposed.

**D keeps no separate device-evidence file** by design: C's checklist and this status are the records of truth, and a third copy could drift. D's message is D's review of those two. *A's "mark them in your device-evidence records" was the wrong ask.*

*Attribution, D's correction (D, 2026-09-18):* D says the miss on note 2 was D's. D flagged the gap without searching the record, where the settling line had stood since `675628c8`. **Both halves are recorded:** the Build 21 entry did not cite the 16:46:13Z read, and D did not search for it. Neither changes the finding.

### S8only release check RUN (authorized directly to A); handset pass CLOSED; release recommendation ISSUED (A, 2026-09-18)

**Owner, directly to A:**
- *"run the read-only S8only check to confirm its current transfer status, whether receipt was confirmed, and whether payment was released … no writes or proof-file access."*
- *"Skip creating a provider fixture. Keep the provider-button and return-from-provider phone checks explicitly untested."*
- *"C can close the handset pass; no further phone work for now."*
- *"Keep PR #75 draft and do-not-merge until that recommendation is ready. No new build or production deployment."*

**S8only read, 21:56:47Z.** One `begin read only` transaction (`tx_read_only=on`); the script refuses the production ref and requires the sandbox ref. Scratchpad `dv20/s8only_release_read_20260918.{sh,log}`.

| Question | Field(s) read | Result |
|---|---|---|
| Current status | `transfers.status` | **`seller_sent`** |
| Was receipt confirmed? | status; `payout_decisions` rows (the confirm path writes one); `transfer_confirmed` notifications | **NO**: not `buyer_confirmed`, **0** `payout_decisions` rows, **0** `transfer_confirmed` notifications |
| Was payment released? | `payout_released_at`; `stripe_transfer_id` (null or not only); `payout_released` / `order_complete` notifications | **NO**: `payout_released_at` NULL, `stripe_transfer_id` NULL, **0** and **0** |

**What the records now establish:** nothing was confirmed or released on S8only, **by READ**. Before this it rested on owner-reported screen state plus source. The online N2 Cancel released nothing at the server.

**Not read:** `transfer_evidence_path`, storage, other transfers, L7.

**Provider fixture: NOT created.** The "Open <provider>" button and the return-from-provider question are **explicitly UNTESTED on device**, by the owner's decision.

**Handset pass:** C has been told it may close it. No further phone work.

**Release recommendation ISSUED:** `docs/release/RELEASE_RECOMMENDATION_PRS_72_75_20260918.md`. PRs #72–#75 remain **draft and do-not-merge** until the owner decides.

**D's independent re-run of the recommendation's §2 (D, 2026-09-18, from scratch; D's scratchpad `sim_72_75.sh`; no branch created, nothing pushed, worktree removed): every claim HOLDS.**
- All 5 merges clean. **Each step's first-parent patch is byte-identical to its PR's own patch.**
- There are two merge bases before step 5. GitHub-style diffs come to 26 or 12 files, so the doc's 12–26 range is exact.
- `6561d1f` is still an ancestor. The final tree differs from `0f329c3a` by exactly the `2567401..649248a` rename, byte-identical.
- Whole integration: 30 files, +3966/−111, with **0** under `supabase/`, the gated client files and build config.
- "No new database call" holds. D's broader sweep for non-literal calls found none added.
- B1's source claims and B2's counts hold, and the S8only log matches.
- **Record claims D did not read:** production "ledger 135 / tip 120" and sandbox "ledger 144".

**D's one finding, accepted:** the recommendation said step 1 touches no production system because "nothing deploys from" the release branch. **A had not checked that**, which is the same error class as `check-the-system-you-name`. The sentence is **struck** and replaced with what is established:
- the branch is not `main`;
- the recorded Supabase binding was cleared on 2026-08-27, which is a record, not re-read;
- the production-branch settings of the connected Vercel projects and the Supabase integration are **UNVERIFIED**.

It is added as **B5, a precondition for step 1.** A did not read those hosted settings: no read of them is authorized, and the owner can check them in the dashboards.

### Deployment settings READ; PR #76 (F-SEC-2) OPENED; deferred items kept (A, 2026-09-18) — both authorized directly to A

**Owner:**
- *"Read the deployment settings for every connected Vercel project and the Supabase GitHub integration … Change no settings."*
- *"Open the missing draft, do-not-merge PR for the reviewed F-SEC-2 fix, with the correct dependency on F-SEC-1, and run its normal CI checks."*
- *"Keep F-SEC-3, F-SEC-1-B and the unknown-outcome wording deferred and documented."*

**Settings (read-only, nothing changed): a merge into `release/production-gate-20260918` triggers NO production deployment and NO hosted-database action.** Full table: recommendation §6.
- **Supabase production:** one branch `main` with `git_branch ""` (unchanged since 2026-08-27T15:49:25Z). Read via the Supabase connector and, as a witness, the CLI; they agree.
- **Supabase sandbox:** no branches.
- **Vercel:** 2 of 8 projects are linked to this repo.
  - `snatchit-web`: production branch **`feature/web-accounts-foundation`**. A merge produces a **preview** of `web/`, which is SSO-protected; its public env points at production Supabase with the anon key.
  - `snatchit-admin`: production branch `admin/operating-console`. Every commit except `ab3e17f` is skipped by the ignored-build step.
- **GitHub Actions:** `ci.yml` runs on push only (CI, no secrets). There are no webhooks, and no Expo app reacts.

**PR #76** ([link](https://github.com/SnatchIt-app/snatchit/pull/76)):
- draft; base `frontend/batch1d-security-notice-lock` @ `016d8e2` (#74's head: the F-SEC-1 dependency); head `f3cff27`; 3 commits, 2 files, +265/−5.
- A checked before opening: there was no earlier PR for this head, and the scope was 0 lines of gated, config or server files, checked with a witness.
- **Checks:**
  - `Immutability + ordering` pass (PR run).
  - 5 CI jobs pass (the branch-push run on the same commit; `ci.yml` runs PR events only for PRs into `main`).
  - `Supabase Preview` skipped.
  - **`Vercel – snatchit-web` failed: rate limited, retry in 24 hours.** No preview ran; CI's own web build passes. No retry was requested, because a retry is a deployment.
- **Review citation:** D PASS on F-SEC-2 is cited from **C's backlog** (`PREMIUM_EXPERIENCE_BACKLOG.md:4291`). A's records do not hold D's verdict directly, so A has asked D to confirm it.

**Deferred and documented, unchanged:** F-SEC-3, F-SEC-1-B, the unknown-outcome wording (recommendation §3).

**Still barred:** merge, deployment, production database updates, phone testing.

**Two corrections from D (2026-09-18), both applied:**
1. **PR #76's review citation** now cites **D's own verdict**, confirmed to A directly: D PASS at `a6a8323`, re-pinned to `f3cff27` after verifying the added commit is comment-only (`a6a8323..f3cff27` = 1 file, +5, 0 non-comment lines). It no longer cites C's backlog, which agreed but was secondhand. The PR body was edited and is still a draft.
2. **"No hosted-database action" was too broad.** The accurate wording: a merge into the release branch triggers **no production deployment and no migration or hosted-database change**. However, the `web/` **preview** it produces runs against **production Supabase** (anon key, within RLS, including sign-in). That wiring is pre-existing, and `web/` is unchanged by #72–#76. A's report to the owner used the broader wording and is corrected in the next report. **Observation, not filed:** whether previews should point at production is the owner's call (recommendation §6).

### OWNER DECISION: website previews must not connect to the production database. Plan issued, nothing applied (A, 2026-09-18)

**Owner:**
- *"website previews should not connect to the production database. Prepare a concrete plan … preserve Production settings … If that requires more setup, propose temporarily disabling automatic previews for this release branch as the interim option. Report the exact proposed change before applying it."*
- PRs #72–#76 stay unmerged until this is settled.

**Plan:** `docs/release/WEB_PREVIEW_ISOLATION_PLAN_20260918.md`. Everything in it comes from read-only reads.
- **Affected projects:**
  - `snatchit-web`: three shared preview+production entries (Supabase URL, anon key, site URL) point previews at production. There are 100 or more READY previews with those values baked in.
  - `snatchit-admin`: its preview target also points at production, but new previews are already off (the ignored-build step builds only `ab3e17f`).
- **Test database:** none suitable exists. The mobile sandbox is unsuitable, for the reasons in §2. Supabase Branching is not recommended, because it is the AUTODEPLOY-1 surface.
- **Phase 2 proposal:** a new isolated project with synthetic data (**$10/month** in the Pro org), then a Preview-only split of the three entries, with production values unchanged.
- **Interim, proposed and awaiting approval:** I2, a `snatchit-web` ignored-build step that skips every non-production build. The exact PATCH and its rollback are in §4.
- **#76 checks, separated (§5):** all code checks pass. The one failure is Vercel's deployment **rate limit**. It is not a code result and will not be retried.

### Preview isolation, interim APPLIED: website previews suppressed; admin Preview scope removed (fail closed). Merges still on hold (A, 2026-09-18)

**Two owner-approved setting changes, verified by read-back.** Full detail: `WEB_PREVIEW_ISOLATION_PLAN_20260918.md` §6.

**`snatchit-web`:**
- Changed: `commandForIgnoringBuildStep`, from `null` to skipping every non-production build.
- The Vercel docs were checked first. The command was tested locally (production → build; preview, development or unset → skip). `autoExposeSystemEnvs` is true.
- Only that field and `updatedAt` changed. The 20 env entries are unchanged, and no deployment was triggered.

**`snatchit-admin`:**
- Preview scope was removed from the URL, anon key, site URL and environment-label settings.
- The shared entries became development + production, with unchanged value fingerprints. The two Preview-only entries were removed; their values were captured to a 0600 file outside the repo.
- Production and Development values and scopes are unchanged. The ignored-build step is preserved, and no deployment was triggered.

**Corrected:** the web fallback claim was wrong. The website's Preview database settings are still present, so a build that bypasses suppression connects to production.

**Recorded, not absolute:** the routes suppression does not cover are listed in §6.4:
- branch `vercel.json`/`vercel.toml`/`vercel.ts` `ignoreCommand` override;
- a Redeploy with the box unticked;
- CLI, API and deploy-hook deployments (unverified);
- rate-limit noise from canceled builds;
- existing deployments.

**Admin previews (§6.5):** both are CLI deployments from April, built from an unrelated commit with a dirty tree. **0 files match `ab3e17f`.** Their badge and database target are unverified.

**Existing previews (§6.6):** only the owner's account can open them (Hobby, 1 member, 0 bypass tokens). A reversible restriction is recommended before any deletion.

**Stripe preview key (§6.7):** not determined. The value was never exposed; the dashboard location is given.

**PR #76's historical rate-limit failure** stays recorded and was not retried. **PRs #72–#76 remain unmerged**, pending D's review and the owner.

**Website Preview scope removed from the database URL and public key: APPLIED and VERIFIED (A, 2026-09-18; the plan's §6.9).**
- **Authority:** the owner's instruction, which says an earlier authorization existed. A's records hold none for the website entries, so it was applied on this instruction and the discrepancy is recorded.
- **Change:** both entries went from `preview, production` to `production`, with value fingerprints unchanged. The other 18 entries are unchanged, the ignore step is intact, and no deployment was triggered.
- **Fail-closed verified by build:** a local `next build` without them exits 1, "Missing required environment variables"; the dummy-value control exits 0. Statically, all 194 remote branches with `web/` have the same guard, and none has a Vercel config override.
- The plan's corrected claims are updated to match.

### RELEASE-BRANCH CONSOLIDATION DONE: #72 → #73 → #74 → #76 → #75 merged into `release/production-gate-20260918` = **`8f45e9b`** (A, 2026-09-18)

**Authority, owner directly to A:** *"mark ready and merge PRs #72 → #73 → #74 → #76 → #75 into release/production-gate-20260918, using merge commits … This authorises release-branch consolidation only: no merge into main, production deployment, database migration or new build."*

**Method at every step:**
- Confirm the reviewed head and the base (after a manual retarget for #73, #76 and #75).
- Rehearse `merge --no-ff` on the current remote branch, and require the first-parent patch to be byte-identical to the PR's own patch, with the expected file count.
- `gh pr ready`, then `gh pr merge --merge --match-head-commit <reviewed head>`.
- Verify the parents (previous head + reviewed head), the tree (= rehearsal tree) and the first-parent patch (byte-identical).
- Wait for CI on the new head.
- Check the Vercel and Supabase effects.

| # | Merge commit | First-parent effect | CI (push) | Vercel `snatchit-web` status | Deployments since the merge |
|---|---|---|---|---|---|
| #72 | `e6042e8e` | 19 files, +2222/−73 | [success](https://github.com/SnatchIt-app/snatchit/actions/runs/35403453503) | "success — Canceled by Ignored Build Step" | 1 web preview CANCELED · admin 0 |
| #73 | `7f4baa25` | 2, +280/−1 | [success](https://github.com/SnatchIt-app/snatchit/actions/runs/35403710462) | same | same |
| #74 | `92f63713` | 3, +281/−17 | [success](https://github.com/SnatchIt-app/snatchit/actions/runs/35403893830) | same | same |
| #76 | `8bdd9fb3` | 2, +265/−5 | [success](https://github.com/SnatchIt-app/snatchit/actions/runs/35404116124) | same | same |
| #75 | `8f45e9bb` | 8, +923/−20 | [success](https://github.com/SnatchIt-app/snatchit/actions/runs/35404338817) | same | same |

- **Code checks:** all 5 CI jobs passed on every merge commit (typecheck/lint/unit tests, fresh-DB migrations, Deno, web build, admin build).
- **Deployment checks, kept separate from code:**
  - Each Vercel web deployment was **CANCELED by the ignore step**, and its status reads success.
  - `snatchit-admin` created no deployment.
  - `Supabase Preview` was **skipped** each time, and the production branch binding stayed `git_branch ""`.
- **No production deployment, no migration, no database action.** `main` is untouched at `eadd456a`.

**Notes:**
- **#75 on GitHub:** after retargeting it showed **12 files (+1465/−38)**, the predicted two-merge-base display artefact. Its real effect was the 8 reviewed files, byte-identical.
- **#74's pre-check:** `mergeable: UNKNOWN` while GitHub recomputed after the base moved. The rehearsal was clean, and the result equals it.
- **A's own slip, caught by the guard:** A first passed #72's full sha from memory. It was wrong, and the pre-check stopped on the head mismatch. The ids were then resolved with `git rev-parse` before use.

**Final result:**
- **`8f45e9bb` vs Build 21 (`0f329c3a`):** exactly **one file**, `tests/profile-avatar-same-tick.test.ts` (+11/−5). That is **byte-identical** to the documented `2567401..649248a` test-title rename, and nothing else.
- `6561d1f` is still an ancestor, so F-BIDS-1 is carried.
- The whole integration: 30 files, +3966/−111, with 0 lines under `supabase/`, the gated client files or build config.
- **D's independent check: requested.**

**Still barred, and still open:**
- No merge into `main` (B2).
- No production deployment, migration or build.
- The preview test database, the old preview addresses, and F-SEC-3, F-SEC-1-B and the unknown-outcome wording are left for later.
- PR branches were kept (`delete_branch_on_merge: false`).

**D's independent check of the consolidation: CONFIRMED on all four points** (D, 2026-09-18; git and gh reads only, after a fetch).
- Gate `8f45e9bb` / `main` `eadd456a`: confirmed.
- **Final vs Build 21:** only the `2567401..649248a` rename, byte-identical. D adds that the gate's tree `c2d11139…` is **identical to the final tree of D's earlier independent simulation**.
- **Chain:** 5 merges, each second parent the reviewed head, each first-parent patch byte-identical to its PR. **Nothing unreviewed came in:** 25 non-merge commits are reachable from `6561d1f`, and 0 fall outside the five PR ranges. The only other merges reachable are Build 20's own (`4c26332c`, `8da50c06`).
- **Scope:** 30 files, +3966/−111, with 0 under `supabase/`, the gated client files, build config, or `web/`, `admin/`, `venue/`.
- **GitHub:** all five PRs MERGED, the five CI push runs succeeded, and the Vercel web statuses read "Canceled by Ignored Build Step", with no admin status.
- **Not re-read by D:** the Supabase `git_branch`, the Vercel deployment lists and #75's 12-file display. Those rest on A's reads.

### PHASE CLOSED at `8f45e9b`; production-readiness plan ISSUED, planning only (A, 2026-09-18)

- **Owner:** *"Close the fix-and-consolidation phase at 8f45e9bb."* It is closed. `release/production-gate-20260918` = `8f45e9bb4c48eeede270fff3c71bd4348c18cc4` is the candidate.
- **Plan:** `docs/release/PRODUCTION_READINESS_PLAN_8f45e9b_20260918.md`.
- **Pending on production (per the records; to be confirmed by live read L1): 22 migrations.**
  - **Required: 17**, because the candidate's client or edges call them, or they are prerequisites or part of the reviewed payments RC unit: 127–133, 135, 136, 139, 140, and the six timestamped files.
  - **Parity: 2.** 123 and 124: production already has the end state; they must be proven no-ops.
  - **Optional: 2.** 125 (scanning, dark) and 126 (admin figures).
  - **Deferred: 1.** 121.
- **Flagged for decision before any apply:**
  - **133 needs a production Vault secret** (`project_url`), which the standing "no secret change" restriction forbids today.
  - **133 rewrites the live signing monitor** (B's sign-off).
  - **135 may stop pre-b2 installed clients registering push tokens** (D-2).
  - **The sandbox was never production-shaped**: no 110–120, 121 or 126.
  - Eleven read-only live facts (L1–L11) are listed with exact reads. **None is requested or run.**
- **Nothing** was applied, deployed, merged into `main`, built, or read from production.

### Production-readiness: live facts READ, rehearsal RUN, go/no-go DRAFTED (A, 2026-09-18). No hosted writes

**Authority, owner directly to A:** read-only production checks (configuration, migration history, deployed function versions, **secret names only**, scheduled jobs, backup metadata, exposed schemas, minimum aggregate counts; no secret values, customer rows or proof files). Plus the compatibility review and a local rehearsal with reviewers.

**Production access, recorded because the owner asked for these reads:**
- `list_migrations`, `list_edge_functions`, and `get_edge_function` × 11 (by a helper agent: source only, no invocation, no literal secrets found).
- Five read-only SQL selects: function md5s and signatures, FK definitions and object existence; Vault names, cron metadata (no command text), `net._http_response` status counts and the minimal counts; one function definition (`cleanup_expired_reservations`); two platform-config flags; the client's RPC and table name existence.
- CLI: `secrets list` (**names only**, digests dropped), `backups list`, `branches list`.
- A REST schema probe with the public anon key against a non-existent table (no data).
- **Nothing written. No proof files. No customer rows.**

**Result:** `docs/release/GO_NO_GO_PRODUCTION_8f45e9b_20260918.md`.
- **GO (conditional) for shape A:** migrations 140 + 20260909000000 only, no edge deploy, then the app build.
- **NO-GO now for the server line**, blocked by the Vault restriction; RC old-client checkout timing is not demonstrated; the rollback cutoff comes minutes after apply.

**A's correction, recorded:** mid-analysis, A said 136 depends on 135. **The rehearsal disproved it**: 136 inserts its own template and applied alone. The go/no-go keeps 136 out for a different reason (it would surface stale `account_deletion_pending` notices before 141).

**D's review:** requested; the addendum will follow.

**D's review of the go/no-go: ONE BREAK found, verified LIVE by A. The verdict is revised (A, 2026-09-18).**
- **The break:** the candidate app's checkout selects `payments.amount_refunded_cents` (`CheckoutNative.tsx:228`, `:595`). **Production has no such column**, and it arrives only with `20260906120000`. Both sites discard the error, so the settled-first and refund-display logic silently reads "none".
- **Shape A (2 migrations) is now NO-GO as drafted.**
- **Proposed shape A′:** add one additive, nullable column migration (registry number from A; next free 142).
  - The app stays byte-identical to Build 21.
  - Prototyped locally: the column is readable by `authenticated`, the app's query runs, the migration drops cleanly, and `20260906120000` still applies afterwards.
  - Nothing in production writes the column (0 of 29 deployed edge files; 0 production-chain SQL).
- **D's other findings, applied:**
  - `auto-finalize-auctions` → `cleanup_expired_reservations` joins the shape-B cutoff list;
  - the drifted function's quoted values are byte-identical;
  - rollback ACLs are the same set as production;
  - sign-out without 129/131 is recorded as an existing gap left unchanged.
- **A's §2 wording was wrong:** a catalog-names check can't see a missing column.

The go/no-go is at `docs/release/GO_NO_GO_PRODUCTION_8f45e9b_20260918.md` §10.

**D's second finding, verified by A:** A′ closes the query break (D's checker confirms), but with the column present and always NULL, **a partial refund would read as a full refund, "No purchase was made"**.
- The deployed webhook marks any `charge.refunded` as `refunded` without an amount.
- `isRefundConfirmed` returns true when the amount is NULL.
- Exposure: production has 7 `refunded` payments; whether any was partial is not knowable from the database.
- **Remedy (i), recommended by A and D:** treat a `refunded` row with a NULL amount as `refund_pending`. It is a gated client change and needs its own test.
- **Remedy (ii):** accept with an operating rule.
- **A′ is GO only together with (i) or the owner's acceptance of (ii).** Go/no-go §11.

**Remedy (i) implemented, `142` authored, focused end-to-end rehearsal done (A, 2026-09-18). Go/no-go §12.**
- **The owner chose (i) and corrected it twice:**
  - no "refund in progress", and the wording "A refund was recorded for this payment. We can't confirm the refunded amount here.";
  - relayed by C and adopted by A as a restriction: no refund message says "No purchase was made", and partial and full refunds state only the recorded amount.
- **§11 corrected:** A's and D's remedy, "NULL → `refund_pending`", would have kept "No purchase was made" and added "being processed". The RC never backfills, so existing refunded rows stay NULL for good.
- **C: `fix/refund-amount-unknown @ b061c077`** (local only).
  - Kinds: refunded, partially_refunded, refund_unconfirmed, already_settled. The only control goes to Tickets.
  - A's payment-boundary review: PASS. Verified fresh: typecheck 0; lint 0 errors / 29 warnings; vitest 2401 tests.
  - C's 9 mutants plus (j) all as predicted.
- **A: `142` at `fix/142-payments-amount-refunded-cents @ e3c03d51`** (local only), with pgTAP 209 and the rollback.
  - Registered.
  - Full chain: 89/89 pgTAP files. Production shape: 209 fails without 142 and passes 11/11 with it.
- **End-to-end [REH]:**
  - **Before 142:** a paid buyer is told "Nothing was charged".
  - **The deployed webhook's branch, run verbatim on a partial refund:** refunded, dated, amount NULL.
  - **C's fix:** 10/10. **The gate:** 7/10 fail. **Mutant (a2):** exactly the two production-reachable rows fail.
  - **The rollback:** data-safe in A′; it refuses when values exist or when the RC is present; its cutoff is the app release.
- **New finding F-CHK-READERR:** the swallowed error on the settled read tells a paid buyer "Nothing was charged". This is demonstrated; it has not been fixed; it is the owner's call.
- **Shape-B precondition:** the RC rollback drops the column.
- **D's behavioural review of `b061c077`:** pending.
- **Nothing pushed, applied, deployed or built.** The local rehearsal databases are kept.
- **D's review of `b061c077`: behaviour PASS, and one owner-level finding, verified by A.** "Go to Tickets" cannot show a marketplace order: Tickets reads only `kernel.tickets`, the rehearsal buyer b3 got 0 rows, and the empty state says "Tickets you own will show up here".
  - It came from A's spec (R5).
  - C is holding. The destination is the owner's call: (b) Home, no pointer, which A recommends; (a) the order's transfer page; (c) Bids.
  - D's minors: render precedence is unpinned (C to pin); refunded-row order is deferred; the swallowed read error is the same as F-CHK-READERR.
  - Admin console: no effect. Go/no-go §12.9.
- **Owner:** Back to home; F-CHK-READERR as a separate change; publish drafts for CI.
  - **Draft, do-not-merge PRs:** #77 (142 @ `e3c03d51`), #78 (refund fix @ `df3572a1`), #79 (lookup fix @ `eba8b208`, stacked on #78).
  - **CI:** all code jobs pass. #77's pgTAP has 89 files / 5314 tests, with 209 ok. #77's guard stops only at the owner's AUTODEPLOY attestation. Vercel web previews were cancelled by the ignore step.
  - **Reviews:** A and D PASS on both heads. D's non-list finding was fixed at `eba8b208`.
  - **E2E:** the lookup failures (42703 and network) fail closed. The parent arms Pay for a buyer who has paid.
  - **New owner decisions:** R2 (the listing-read error in re-validation), the back gesture, and an optional copy change.
  - **Payments-release conditions:** the RC rollback column, and `pickSettled` determinism.
  - Go/no-go §12.11. Nothing merged, applied, deployed or built. The rehearsal databases are kept.

**Final checkout change (A, 2026-09-19).** Go/no-go §12.12.
- **The changes:** C's `11e1518f` (the payment-lookup wording, on #79) and `d75c15cc` (the reservation lookup fails closed, draft #80, stacked on #79).
- **Reviews and tests:** A and D PASS. CI is green on #79 and #80. The E2E listing-failure phase discriminates: the fix is unverifiable, the parent says "Nothing was charged".
- **Merge rehearsal:** #78 → #79 → #80 → #77 is clean, and every patch-id is identical.
- **Handset check:** prepared (`HANDSET_CHECK_FINAL_CHECKOUT_20260919.md`), not run.
- **#77:** blocked on the owner's dashboard check.
- **D's recommendation:** "Check again" for the reservation-unverifiable state (owner decision).
- Nothing merged, applied, deployed or built.
- **Handset runbook `d98f0dd5`:** D confirms all five dispositions and that it is ready for the owner's authorisation.
  - D withdrew its price-unit item: 100 means $100.
  - D confirmed the §7 end state is the product's own cancel shape (`cancel_listing()`, 047): `reserve_buy_now` (20260906100000) and `validate_and_apply_bid` (047) both refuse a cancelled listing.
  - Nothing has run on the sandbox.
- **Handset round, 2026-09-19 (A). Manifest §19.**
  - #78, #79 and #80 are merged into the gate, which is now `05d85732` (patch-identical, CI green). Build 22 (EAS `3ae689cd`) was built from it.
  - The fixtures were written at 16:42:27Z.
  - H1–H5: **PASS** on the device, owner-reported via C. H5b was not run.
  - §7 clean-up ran at 17:31:43Z: all four fixtures are cancelled; the payments are byte-unchanged; 0 notifications, bids or transfers.
  - Observation: the app did not release the holds on leaving; the cause is not established.
  - #80 has no device evidence.
  - #77 is still open, waiting for the owner's attestation line.
- **#77 merged, 2026-09-19 (A).**
  - The owner visually confirmed Deploy to production OFF, 14:19 local. A confirmed from the organisation's project list that "Snatch It" is `hqycwntpfoztoinemqns`. The attestation line was then added; the guard passed (run 35460874599).
  - Merged as `e191cbfa` (parents `05d85732`, `e3c03d51`), patch-identical to the rehearsal; only the 3 142 files. `main` is unchanged at `eadd456a`.
  - Gate CI 35461331147 is green, with pgTAP Files=89 / Tests=5314.
  - **A's slip:** A retyped #77's full sha from memory, wrongly. `--match-head-commit` refused, and nothing merged. A re-ran with the sha resolved from git.
- **Production Disk IO investigation (read-only)** in `PROD_DISK_IO_INVESTIGATION_20260919.md`:
  - `ops-detect-tick`, every 5 minutes, full-scans the 245 MB `cron.job_run_details` table. That is 99% of disk reads, about 12 s per run, steady since 2026-09-08.
  - No user-facing impact is visible (p95 about 0.6–0.7 s, 0 5xx).
  - The smallest fix is a D-authored migration that bounds the read and adds history clean-up ($0). The applies are not blocked, but 142 should be timed between detector runs.
- **C's escrow-note change** (`fix/checkout-escrow-note-unknown` @ `19b6fc2b`, visibility only): A PASS and D PASS; 124 files / 2460 tests. **The push is held for the owner's direct confirmation**, because it was relayed.
- **Escrow-note change published for CI, 2026-09-19 (A, owner's direct approval).** `fix/checkout-escrow-note-unknown` pushed at the reviewed head `19b6fc2b` (remote verified equal) → **draft PR #81** against `release/production-gate-20260918`, marked DO NOT MERGE; mergeable; no migration. A's two negative controls on `19b6fc2b` (tree restored clean): the rule ignoring reservation-unknown → only E10 fails; the payment flag cleared before the read's result → only E9 fails. No merge, no build.
- **Disk IO fix, 2026-09-19.** Owner: coordinate and review D's fix; keep conclusions bounded (no observed impact in the sampled logs; budget, memory, swap, tier unverified; no "upgrade unnecessary" conclusion); **no schedule change, history deletion or compute upgrade**; applies stay on hold. D (owner-authorised directly) builds a local read-optimisation of `ops.job_health`/`ops.detect_jobs`; **143 / 210 allocated to D**; A's review criteria sent (equivalence on edge cases, discriminating mutants, plans on a never-analysed ~600k-row table, identical grants/definer settings, rollback to 116/117 bodies, full pgTAP). Investigation record corrected (item 3).
- **B's ticket-delivery plan reviewed (A), 2026-09-19** → `TICKET_DELIVERY_PREFERENCES_A_REVIEW_20260919.md`. Direction right; five corrections (production has three transfer writers and no `settle_listing_for_payment`; bids are publicly readable; `transfer_method` is editable after bids; `set_transfer_delivery_info` validates nothing and allows changes after send; S3 would refuse every Build 9 user). 24-hour expiry/refund claim holds for production **at records strength only**: A's read-only production read of the deployed definitions was refused by the permission classifier as unauthorised, and was not retried. Staged plan: S4+S5 first (after 140), then capture table + BEFORE INSERT trigger on `transfers`, then client; S3, off-session charging and clock changes not staged.
- **Production expiry assessment, read-only (A, owner-authorised directly, 2026-09-19 19:00–19:10Z)**, `TICKET_DELIVERY_PREFERENCES_A_REVIEW_20260919.md` §8:
  - **Code:** the deployed `enforce-transfer-expiry` v38 is byte-identical to `origin/main` (6 files). Every pending transfer 24 hours old expires with no destination check and gets a full, live-mode-only refund. 12 of 13 database bodies are identical to the production-shaped replay; `record_transfer_payout` differs (payout path, follow-up). `ensure_transfer_exists` is the only database writer of transfers; `settle_*` is absent.
  - **Schedule:** job 9, `*/2`, active, with a Vault bearer.
  - **Records, last 24 hours:** 720 runs succeeded; 719/719 HTTP 200; 0 expired, 0 refunded, no warnings or errors.
  - **Not confirmed:** any end-to-end expiry in production; earlier history (R4) was not read.
- **Owner scope correction (delivery preferences):** saved defaults in Settings and confirmed delivery details before bidding and checkout in the new app are **core**. The plan is revised in §5a (server-backed bid entry point, `create-payment-intent` contract flag, Settings, the required step). Older apps are planned separately in §5b as compatibility, **explicitly not compliance**. PR #81 stays draft; production applies stay on hold.
- **Seller expired-window wording (C's change, owner-approved to C; A reviewed on the payment boundary), 2026-09-19.** C's S1–S5 on the Send screen, with a payment-status embed.
  - **A's answers:**
    - A payment can be 'refunded' while its transfer is pending. main's webhook marks **any** charge.refunded, partial included, with no amount. The deployed expiry job then **skips** the refund on 'refunded', so the remainder of a partial refund is never refunded by it.
    - There is no other cancelled state for a pending order.
    - The embed resolves for the seller, and a row hidden by row security gives `null` with 200. Probe on local PostgREST 16.2, throwaway clone `a142_embed_rehears`, synthetic rows. Controls: a bad relationship name gives 400; `!inner` gives 406.
    - The expiry refund updates the row the seller reads, and a NULL seller_id is impossible for marketplace payments (`payments_rail_pairing_ck`).
  - **O1 BLOCKING:** S5 must not say "don't transfer" or hide the destination on an amount-unknown refund. The wording goes to the owner.
  - **O2:** a second quiet re-read about 150 s after the deadline, a re-read on foreground, and a re-read when mark-sent fails with 'expired'.
  - **Harness note:** the local production-shaped replay lacks production's out-of-band transfers→profiles FK (row 123), so the send screen's buyer embed gets PGRST200 there. The FK was added to the throwaway database only.
- **143 / 210 reviewed (A), 2026-09-19.** D's `admin/ops-cron-history-perf` @ `67f2ccd5` (local): **PASS on correctness**.
  - **A's independent checks:**
    - a replay of the full chain: 5333/5333, with 210 at 25/25;
    - the md5s match D's;
    - the rollback bodies are byte-identical to 116/117;
    - D's old-body comparators are verbatim;
    - equivalence on A's perturbation (run-ID holes, a raised minimum, a gap at the top, a newest run still starting): `detect_jobs` is identical (21 cases), and `job_health` is exactly equal to the old body with its last-run pick made by run ID.
  - **For the owner:**
    - (i) the one deliberate difference changes the console's "last run" for **every** job that ever had a startup timeout. Whether production has any is unread;
    - (ii) a pre-existing gap: an active job that stops running drops out of `detect_jobs` after 7 days, and its case probably auto-resolves (inferred, not tested). A follow-up, outside 143;
    - (iii) a CI run of 210, which needs a draft PR, is the owner's call.
  - Performance was not re-measured by A.
  - **Retention proposal:** reviewed, comments only. Protect every non-final status; read the vacuum and statistics state first; time the backlog delete to the I/O budget.
  - The Disk IO record's "never vacuumed or analysed" is corrected to "none since the last statistics reset".
- **143 v2 re-checked (A), 2026-09-19:** `6b700aed` = `67f2ccd5` + 1 comment-only commit (D corrected its own "never analysed" wording to "not established" and added an analysed-table measurement). Applied on A's replay: md5s `da349c0b…`/`9e932d28…` match D's; attributes and ACL are identical to the gate; 210 = 25/25. **PASS.** D executed the auto-resolve gap locally, so it is now confirmed, not inferred: an active job whose runs age past 7 days has its case resolved and its alert recovered, identically under 117 and 143. Recorded in the retention proposal §6 (`35f795f2`) as a separate owner decision. Not pushed; CI awaits the owner.
- **S5 "Ask support first" restriction assessed (A, at the owner's request via C), 2026-09-19.** C's wording-only interim is at `938423e0`; the actions are unchanged.
  - **Support's tools today:** only a Stripe Dashboard refund of the remainder. The ops `refund_execute` action is disabled by setting, and refuses non-'succeeded' payments. The executor functions are not deployed. No server action moves a pending transfer except mark-sent and expiry.
  - **Expiry (deployed code, byte-verified):** a pending order whose payment is 'refunded' expires within about 2 minutes of its deadline. The refund is skipped, with **no push**. There is **no trigger notification on 'expired'** (replay). The listing stays 'sold'. There is no payout.
  - **Consequence:** the remainder of a partial refund is never refunded automatically. This rests on the deployed expiry code, Stripe's docs ("including partial refunds") and `main`'s webhook. **Unverified:** that production's Stripe endpoint subscribes to `charge.refunded`.
  - **Pre-existing:** a sent, partially refunded order never pays the seller (`payment not succeeded`; retried every 2 minutes).
  - **Verdict:** the restriction must not ship alone. It needs (1) an owner operating rule ("refund recorded on a pending order means cancelled: support refunds the remainder in the Dashboard") and (2) a D detector surfacing pending or expired transfers with a 'refunded' payment. "Partial refund and proceed" needs a server change, which is the owner's call. A's view on the delivery target: hide it with the sending instructions.
- **F-PAYOUT-PARTIAL-1 (A-owned, open, pre-existing; not part of C's change).**
  - **The problem:** a pending order that receives a partial Stripe refund, and that the seller then sends, never pays the seller automatically.
  - **Mechanism:** the webhook sets `payments.status='refunded'` for any `charge.refunded` (`main`'s source; deployed v41 not byte-read). The deployed payout (`enforce-transfer-expiry` v38, byte-verified) skips any payment that is not 'succeeded'. The transfer then flips to `auto_released` after 72 hours, and Phase 2b retries and skips it every 2 minutes indefinitely.
  - **Unverified:** that production's Stripe endpoint is subscribed to `charge.refunded` (an owner Dashboard check).
  - **Fix options:** record the refunded amount, then pay out the remaining transferable amount (a payment-rule change, the owner's decision). The gate candidate's `amount_refunded_cents`/`fullyRefunded` logic is related but not deployed. C spot-checked the payout skip and the missing expiry notification in `main`'s source (2026-09-19).
- **2026-09-19, owner authorisations carried out (A):**
  - **143 published** as draft DO-NOT-MERGE **PR #82**, at D's reviewed `6b700aed`.
    - The jobs-page "last run" change has its own section for the owner's review. Publication is not approval to apply.
    - The AUTODEPLOY line comes from the owner's visual check at 14:19 today, scoped to publication and CI.
    - **CI is green** (run 35466024802): pgTAP 90/5339, 210 ok as non-superuser, census 32|108|37|38.
  - **Stripe check** (read-only), in `REFUND_RESOLUTION_PLAN_20260919.md` §1:
    - Our event ledger received and processed `charge.refunded` 3 times (07-04 → 08-04). The ledger's only writer is our function `stripe-webhook`.
    - The ledger holds **no events of any type after 2026-08-05**, and there were 0 `stripe-webhook` requests in the last 24 hours.
    - Stripe's own endpoint configuration was **not read**: the Stripe CLI has only a sandbox context, and the browser stopped at the login page. A did not authenticate. The owner's Dashboard check is specified in the plan.
  - **Refund resolution plan written** (`REFUND_RESOLUTION_PLAN_20260919.md`). It covers full refunds, partial refunds that continue, partial refunds that cancel with a remainder owed, and unknown amounts. Every fact carries a strength label. The seller net is `amount − seller_fee`, within the `source_transaction` ceiling. Refunds debit the platform, and Stripe keeps its processing fees. Recovering money already paid out needs a reversal, and nothing starts one. It establishes no cancellation rule and no 24-hour promise.
  - **The detector proposal (R1–R4)** has been requested from D: local only, closed only by a support action.
  - **C's deadline-copy commit `5c9dd9ca`**: review **PASS**. No payment read, no gated files. 32/32 on the changed tests; A's own mutant killed exactly C's predicted DM4 set. **Not published**, because that is not authorised. The refund-recorded screen stays held at `938423e0` (`hold/seller-refund-recorded`).
- **Deadline copy, tip `4a96e05e`** (C; test-only over `5c9dd9ca`, after D's in-scope PASS and two test/comment findings): A verified 0 non-test changes and 32/32 on the changed files. A's own witness, a direct `from('payments')` read, fails only V10. **A PASS carries to the tip.** It is not published, because that is not authorised. For the owner, from D: the "Send tickets to" heading still shows on an expired order, and the instructions and target render pre-existingly for reversed or disputed orders.
- **Refund-resolution detector design (D, `e733c887`), A review, 2026-09-19: PASS as a design, with 2 required changes. 144/211 allocated to D, for a local build only.**
  - **Verified (replay):**
    - R4 already opens a p1 `reconciliation_mismatch` case (`detect_reconciliation`, 117);
    - `detect_release_stuck` has no payment-status filter;
    - the functions redefined (`run_job`, `run_all_detectors`, `action_dispatch`) come from 115/117/118 only, so there is no dependency on the RC.
  - **Required:**
    - (1) 138 also redefines `action_dispatch`. 144 must be rebased onto the body applied immediately before it, or 138's action branches are silently dropped on replay;
    - (2) the R2 rule is valid for deployed expiry v38 only, so it must be re-reviewed before any RC edge deploy.
  - **Owner items:** p1 alerting vs p2 (p2 default); the 10-minute window, plus an optional read of expiry run durations; the turn-on order (setting off → console classification control → owner flip); changing `release_stuck` (unchanged in v1; overlap cross-referenced).
- **144 built by D (`bd12e297`, local); A review PASS, 2026-09-19.**
  - **A's independent replay:** RESET 0, census unchanged, pgTAP **5354/5354** (211 = 46/46, amended 182/183 pass). The four md5s match D's; the setting is seeded false.
  - **The redefinitions are minimal diffs** against 117/118.
  - **The rollback on a clone equals the gate** on 8 items; the positive control is 13 differing lines before the rollback.
  - **Doc fix requested:** the CI census, expected_grants and the grant manifest are public-schema only, so the design §6's "+1" note is wrong; the build correctly omits them.
  - **Owner items:** publication (a draft PR); p1/p2; the 10-minute window; the turn-on order; the rollback refusing while any `refund_resolution` case history exists. The 138 rebase is required before any PR.
- **Refund/payout safety round (owner-authorised implementation), 2026-09-19 — A's item 1 done.**
  - **Defect (verified in deployed v38 AND the gate):** Phase 2b selected the 20 oldest released-but-unpaid transfers and only then rejected non-`succeeded` payments. Such rows never leave the set (`claim_payout_attempt` refuses PAYMENT_NOT_SUCCEEDED and opens no attempt), so ≥20 of them starve every payable payout, silently. The second capped sweep (expired-lease attempts) is NOT affected: blocked rows open no attempt.
  - **Fix (`fix/payout-retry-fairness` @ `36db0c36`, draft **PR #83**):** the payments-status and quiet-period predicates move INTO the query, before the limit. No predicate loosened; the protocol's eligibility refusal is untouched.
  - **Evidence:** `tests/payout-sweep-fairness.test.ts` (6 cases) — F1/F3/F4/F6 **fail before the fix**, 6/6 after. Real PostgREST 16.2 on a production-shaped DB: the old query returns 20 blocked rows, the fixed one exactly the 3 payable. Gates: typecheck 0, lint 0 errors, full vitest alone 124 files / 2453 tests.
  - **Production stays exposed until the edge is deployed** (owner-gated).
  - **PR #82 body corrected** to record the CI result; the guard re-ran green.
  - **C's `c002647b` PASS** (seller payout claim now gated on `payout_released_at`, verified: that column is written only by `record_transfer_payout` after the Stripe transfer succeeds). A's control kills only P2. The buyer-side equivalent was handed back to C with the read approved.
- **C's transfer-screen round published: draft PR #84** (`fix/seller-deadline-copy` @ `131017a5`, base the gate, client-only). A verified the remote head equals the reviewed head; **CI green** (unit 125 files; pgTAP unchanged 89/5314).
  - Seller and buyer payout claims are now gated on `payout_released_at`, whose semantics A verified in the byte-verified deployed v38: `apply_auto_release` sets only the status, and `record_transfer_payout` writes the column after the Stripe transfer succeeds.
  - A failed read no longer claims "not found" on either screen.
  - A's controls: forcing the seller title kills only P2; dropping the buyer's column kills only B3.
  - The refund-recorded screen remains held on `hold/seller-refund-recorded`.
- **138 is NOT chain-ready — corrected size (A's own replays, 2026-09-19).** D reported "gate + 138 = 20 failures across 11 files + 245 psql errors". That was an artefact: the chain used the gate's copies of the tests 138 amends.
  - **138's head `1cacdf55` alone: 5435/5435 ALL-PASS.**
  - **Gate + 138 with its own 14 amended test files: 5485, not_ok = 2, 0 psql errors.**
  - The two are pins predating 140: `050` test 16 (140 made `mark_transfer_sent` idempotent) and `162` test 84 (function count 107 vs 108, missing 140's function).
  - **Merge-order decision (A): 138 stays out of this round.** It is unrelated to the owner's refund/payout fixes, and neither A nor D starts it unprompted. 144 must therefore be order-independent (extend, never restate, the constraint lists).
- **Refund/payout safety round — integrated verification (A, 2026-09-19).** Branch `integration/refund-payout-round` (local) = chain `1adc0eec` (143+144+145) + A's payout fix `36db0c36` + C's five client commits through `131017a5`.
  - Replay RESET 0; census 32|108|37|38; **pgTAP 5419/5419 ALL-PASS**; typecheck 0; **vitest 126 files / 2485 tests** (gate 2447 + A's 6 + C's 32).
  - Per-PR CI: **#82** green (143, 90/5339); **#83** green (payout fix, unit 124, pgTAP unchanged 89/5314); **#84** green (client, unit 125); **#85** green after A added the AUTODEPLOY line (chain, 92/5425).
  - A's own rollback check on 145: `detect_jobs` back to 143's `9e932d28…`, helper and setting row gone, cases untouched.
- **Chain hardened and re-verified (A, 2026-09-19):** chain head `07a29403` = `1adc0eec` + 13 lines in 144 (before/after literal counts; refuses rather than narrowing a vocabulary). A's replay at the new head: RESET 0, census unchanged, **5419/5419 ALL-PASS**. #85 green at that head. **The verified chain head for the report is now `07a29403`.**
- **146/213 alert-delivery design (D, `bcf616f9`) — A review: GO with three conditions.** D's mapping stands: nothing delivers an ops.alert today, and `notify-report` is the only working path.
  - (1) A queued `net.http_post` is not a delivery: a **401 queues successfully**. Record the request id, add a reconcile pass against `net._http_response`, and set a separate `delivered_at` only on 2xx; keep unconfirmed alerts eligible.
  - (2) Send an allow-listed payload only — never contact details or full payloads — pinned by a fixture containing an email and phone.
  - (3) State that enabling the setting still delivers nothing until scheduling is separately decided.
  - Item 4's authorisation is between D and the owner; A registered the numbers and reviewed the design only.
- **146 / 213 built and reviewed (A PASS), 2026-09-19.** `admin/146-alert-delivery` @ `a9bf6423`, draft **PR #86**, stacked on chain `07a29403`; **CI green** after A added the AUTODEPLOY line (93 files / 5451). A's own replay: **5445/5445 ALL-PASS**, 213 26/26.
  - All three of A's conditions are met, one better than asked: notify-report answers 200 for unknown events **and** its own errors, so a status-only rule would have marked every pre-deploy post delivered. Delivery now requires a 2xx **plus** `delivered >= 1`; a 401, an unaccounted 200 and a 15-minute silence all leave the alert eligible, capped at 5 attempts.
  - The edge change is additive (new `ops_alert` branch; response shape changes for that event only).
  - D's CI-only defect, disclosed: 213 first replaced `net.http_post`, which only the superuser harness allows. Egress now goes through two substitutable seams.
  - Still inert: nothing schedules the dispatcher, the setting is seeded false, and no channel is activated.
- **146 review fixes verified (A PASS), and D's console branch reviewed — 2026-09-20.**
  - **`admin/146-alert-delivery` @ `cf804036`** (fix `6f604efe` + docs-only commit; A resolved both against the ref). Two owner-review defects fixed: **(S) queue starvation** — the 5-attempt cap is now in the batch predicate; exhausted alerts are counted (`given_up`), stay firing with their last error, and no longer fill delivery slots; **(R) incident recurrence** — 146 now replaces 117's `alert_fire`: the recovered→firing transition (only) bumps `incident_seq` and clears delivery/ack bookkeeping, so a recurrence is notified, is not covered by a stale acknowledgement, and cannot be marked delivered by a late response to the closed incident's request (the old request id is discarded).
  - **A's own evidence:** replay RESET 0; census 32|108|37|38; **pgTAP 5455/5455 ALL-PASS** (213 = 36/36); **RED control** — new 213 against the pre-fix migration fails exactly {S1,S2,R1,R2,R4,R5,R6,R7} = 8/36 (D said 7; the named set matches, the count was off by one); **rollback battery** — restores `alert_fire` to md5 `dfcb1956…`, byte-equal to the chain-applied 117 body (independently measured on the pre-fix replay), 17→8 columns, 4 functions dropped, setting deleted, order safe (function restored before columns drop, one transaction). CI green at `6f604efe` (5461) and `cf804036`. **Boundary answers to D:** ninth column needs no census/manifest change (ops schema — confirmed by replay); `alert_fire` redefinition is order-safe (A's own grep: only 117 defines it; 143/145 call it; no timestamped file and not 138 touch ops.alert*); discarding a closed incident's delivery bookkeeping on recurrence is **accepted** — `ops.audit` 'alert.acknowledged' rows survive as the durable record, and a per-incident delivery history would be a new table with no consumer (owner may order one later).
  - **`admin/refund-classification-console` @ `3dab1614`** (D, based on `admin/operating-console` `562fda9a`, all 11 files under `admin/`, nothing under `supabase/` — A verified by diff). Gives operators the controls 144/146 assumed: classify A/B/C and record obligations through the existing audited action engine (`case_refund_classify` / `case_refund_obligation` action types), acknowledge via `ops.alert_ack`, and per-alert delivery truth on the System page. A reviewed the payment boundary: `src/lib/refund-resolution.ts` is a display-only mirror of 144's close guard (same last-event-wins reads, both `settled` encodings, refusal strings match the DB literals); the DB refusal is still shown verbatim, so a stale panel can never close a case over money owed — **mirror accepted, no new DB read function, no number issued**. CI green on the push (CI runs on every non-main push).
  - **A's PR-base decision: no PR for the console branch.** Its only possible base is `admin/operating-console` — the console's Vercel production branch, which is never merged without the owner. CI signal already exists from the push, so a PR adds only a merge button aimed at production. The branch stays pushed; landing it is an owner decision.
  - Unchanged: nothing merged, applied, scheduled, flipped or deployed; the operator controls have never run against a live database (recorded in D's `admin/docs/OPS_CONSOLE_OPERATOR_GAPS.md`).
- **Consolidated rollout plan prepared (A, 2026-09-20)** — `docs/release/ROLLOUT_PLAN_REFUND_PAYOUT_20260920.md`, on the owner's instruction (planning only; nothing authorised by it).
  - **Integration proof v2:** `integration/refund-payout-round-v2` @ `e6ebd800` = `70a4f613` (146 head) + `36db0c36` (payout fix, cherry-pick clean) + `131017a5` (C's client, merge clean). A's run: replay RESET 0, census 32|108|37|38, **pgTAP 5455/5455 ALL-PASS**, typecheck 0, **vitest 126 files / 2485 tests** — the exact release combination.
  - **Overlap resolution:** merge #86 first (#85's head is an ancestor → auto-merged); close #82 unmerged (143 migration + rollback file-identical in #86 by blob hash; #82's 210 test is the older revision); then #83, #84. No retargeting; nothing to main.
  - **Payout-fix compatibility finding:** deployed v38 → fix branch is 2,043 inserted lines of RC edge code, so the branch is NOT deployable as "the fix". Route B backport (fix onto v38 source) dependencies verified on `a8f_prodshape_rehears`: transfers→payments FK present, all query columns present, status domain admits both sweep statuses. Backlog count before any deploy: the fix pays the starved backlog on its first tick.
  - **144 reconciliation:** apply creates no cases (detector skipped for every trigger while the seeded-false switch is off, verified in the body); the classify/close RPCs exist since 144; the console branch adds the workflow. Sequence: apply (off) → console → flip.
  - **Recommendations made, not returned:** accept the jobs-page last-run change; deliver all firing alert kinds, 5-min dispatch, batch 20, push to admin_users + ADMIN_EMAIL; ack on the console; given_up alerts stay firing and visible.
- **v38 backport built: draft PR #87 (A, 2026-09-21).** `fix/payout-fairness-v38-backport` @ `f5e91e74`, base `main` (= deployed v38, byte-verified 2026-09-19) — the payout-starvation fix deployable against production's current database ahead of the package; the RC function supersedes it when the chain ships.
  - TDD on the real handler via the edge VM (harness copied verbatim from `36db0c36`): corrected-fixture **RED = exactly {F1,F3,F4,F6}** against unfixed v38 (F2/F5 pass — already-safe behaviour), **GREEN 6/6** after; full suite alone 6 files / 122; typecheck 0; lint 0 errors. One A fixture defect found and fixed during the port (QueryCall filter tuple read as [op, value] instead of [op, col, value]; the polluted first RED was voided and re-established).
  - Prod-shape dependencies re-verified 2026-09-21 on `a8f_prodshape_rehears`: transfers→payments FK, all selected columns, status domain. Deploy prerequisites in the PR: byte-recheck v38, **backlog count first** (money moves on the first tick), then owner deploy + one observed sweep.
  - Ops note: the machine's disk filled mid-run (ENOSPC, even the tool harness blocked). Freed by removing 15 finished scratch worktrees via `git worktree remove` (branches preserved; one with untracked files skipped) + recreatable node_modules; **no rehearsal database was touched**.
- **C's app consolidation received (2026-09-21)** and folded into the plan §12: app delta vs Build 22 = exactly #81 ∪ #84 (five files, disjoint); invariants re-confirmed; one optional read-only device check (D6 Send screen) offered to the owner; held screen stays held.
- **Console PR decision + second integration verification (D → A, 2026-09-21).** D's Vercel token is refused for the snatchit-admin project scope (403), so the console draft PR stays UNOPENED and the preview-safety check is an owner item (3-step dashboard check recorded in the plan §4; preview env vars have never been checked by anyone). D independently re-verified `integration/refund-payout-round-v2` @ `e6ebd800`: blob-identical migrations/rollbacks/notify-report vs the reviewed heads, last-definer md5s intact, switches seed false, fresh replay 5455/5455 — a second independent run agreeing with A's. (D's replay predated D's local disk incident; D's evidence stands, and only D's own d*-prefixed rehearsal DBs were dropped.) **PR #87 CI: all checks pass** (incl. CodeQL, dependency review, secret scan — main-based PR runs the security set).
- **Recipient prerequisite found by D, verified by A (2026-09-21); rollback battery double-run ALL PASS.** 146 head advanced to `ec4f0600` (docs + `scripts/local/rollback_battery_143_146.sh`; nothing under supabase/ — A verified; migration PASS at `cf804036` stands). D's finding, confirmed by A in the notify-report source: `delivered` increments only on push-success or email-sent, `EMAIL_ENABLED` defaults false, so with no working channel every alert exhausts its 5 attempts silently (column-visible only) — a working channel is now a named prerequisite before the delivery flip (plan §5.6b; D's OPS_ALERT_ROLLOUT_PREREQUISITES.md). The disable/recovery battery: D 21/21, A independently ALL PASS on a copy of the integration replay (A's first run failed by invoking the script out-of-tree — rollbacks unreachable — an accidental negative control proving the battery cannot pass vacuously). Console permission model verified by D against the database: the two 144 action types return exactly the console's default roles; `dispatch_alerts` not executable by authenticated; pre-apply the console degrades to "RPC not available yet".
- **Rollout plan v3 + registry reconciliation (A, 2026-09-21, owner's seven-point instruction; commit `9c552c73`).** Facts re-read from GitHub and the records, not carried: **PR #77 (142) is MERGED** into the gate since 2026-09-19 (`e191cbfa`; blob-identical to its head) — registry corrected; production apply still NO; required only by the app path (go/no-go §12.8), not by 143–146 or #87. **Gate tree = production's 135 rows + exactly 27 pending files** (121, 123–133, 135, 136, 139, 140, 142, 143–146, 20260906×4, 20260909, 20260916); 137/138/141 absent; 121 deferred (PFA-18C); 125/126 optional (D-1) with both files in the tree (126 = #63's open head). Plan §3 now carries the full manifest with classes/dependencies/approvals and the readiness plan's still-open prerequisites (production-order rehearsal, A+B compat review, B's 133 sign-off, D-1/D-2/D-3/O-3, L1–L11); a 143–146-only subset apply is stated as unverified and unoffered. Corrected: #86 head `26e9db09` in both documents (executable content unchanged since `cf804036`; proof `e6ebd800` still covers); "both switches off restores pre-package behaviour" replaced by a per-migration switch/active/undo table (143 and 145 have no switch; 145 live on apply; 146 rollback discards delivery/ack bookkeeping); "Preview vars never checked" replaced by the 09-08 record (privileged key removed; Preview carries the production URL + anon key → exposure is the risk) with the deployment trigger corrected (merge → canceled build unless the SHA equals the Ignored-Build-Step pin; release = pin update or CLI `--prod`); #87 prerequisite status corrected (done 1-historical/2/4; outstanding 3 count+value, 5, 6, fresh v38 byte re-verification). Registry rows 144/145 updated to the final reviewed versions in #85/#86 (211=61, 212=25). D asked to check §3/§5/§6/§8 independently; C asked to confirm the app-dependency rows.
- **CI at 146 head `3f579975` (2026-09-22 UTC):** first run RED for infrastructure — `supabase start` could not bind 54322 (two pushes minutes apart overlapped on one runner); the workflow failed closed ("no TAP output captured — the suite did not run"; egress gate failed too). D re-ran with no code change → green (93 files / 5461, PASS); **A confirmed independently** (CI run 35683651167 success, Migrations guard 35683654451 success, all #86 checks pass). Executable content unchanged since `26e9db09`. Ops note added to the plan §13a.
- **#87 DEPLOYED to production and verified (A, 2026-09-22, owner's execution authorisation).** `enforce-transfer-expiry` v38 → **v39** (`ezbr_sha256 bff961a3…`, deployed 03:41:21Z via CLI `--project-ref`, `verify_jwt` unchanged true). Pre-deploy gates, all met: deployed v38 byte-identical to `origin/main` on all six files (download + sha256); backport `f5e91e74` differs in exactly one hunk of `index.ts` (Phase 2b selection, 28 lines); production catalog: transfers→payments FK present, 11/11 + 4/4 columns, status domain admits both sweep statuses; **stuck set 0 / eligible 0 / $0** (23 payouts ever, 0 duplicate transfer ids); D independent PASS on eligibility and duplicate-payment protection (corrections adopted: the fix admits previously-starved rows; per-row value is all-or-nothing; pre-existing residual — destination change after a failed `record_transfer_payout` — carried to the owner). **Post-deploy:** cron job 9 `succeeded=15` since deploy, 0 failed; every `run complete` summary `errors: 0`; payouts released since deploy 0 (nothing to release); intentionally releases no money today — preventive. Rollback artefact: `origin/main` (= deployed v38 byte-for-byte) + saved copy in A's scratchpad.
- **Production reads (authorised 2026-09-22):** ledger 135 rows, max numeric 120, 0 rows ≥121 (confirms the 27-file pending set); `ops.setting` actions_enabled=true, detectors_enabled=true, refund_execute_enabled=false; **admins with an active push token: 0 of 2**; edge secrets: `EMAIL_ENABLED` absent (email off), `RESEND_API_KEY` and `ADMIN_EMAIL` present; Stripe context: 2 live-mode refunded payments (last 2026-08-04), 3 `charge.refunded` events all processed, newest webhook event 2026-08-05, 1 live payment in 30 days — historical live processing established, current delivery unproven for lack of traffic; **Vault holds `service_role_key` only — no `project_url`** (133's §0 refuse-guard is live; ceremony is a precondition). Vercel project reads: 403 for A's token as for D's.
- **App-side final verification incl. #81 (C, PASS):** combined tree `e079fcc1` tsc 0 / lint 0 / 126 files 2492 tests; A's own `integration/refund-payout-round-v3` @ `3da63d9b` tsc 0 / lint 0 / 127 files 2498; app delta exactly five files, byte-identical to PR heads. Phone check judged not materially necessary (installed-app statement: Build 9 return-shape-insensitive; Build 22 fail-closed/fail-soft). **133 reviewed by D (behaviour preservation PASS, measured diffs) + A; B's invariant set not reopened by 133.** Findings adopted into the preflight: assert Vault `project_url` == exact production host before 133; confirm `service_role_key` present (✓).
- **Gate merges executed (A, 2026-09-22, owner's execution authorisation; wiring verified first: gate ≠ main, Supabase integration acts on main only and was owner-confirmed OFF 2026-09-19, snatchit-admin branch tracking OFF and snatchit-web previews cancelled by the ignore step).** Into `release/production-gate-20260918`, merge commits: **#86** (143–146 + notify-report `ops_alert`; #85 auto-marked MERGED, its head `07a29403` an ancestor), **#83** (RC payout fix), **#84** (transfer screens), **#81** (checkout escrow line). **#82 closed unmerged** (143 + rollback blob-identical via #86; older 210 superseded). Gate head `e191cbfa` → **`c836bc43`**. Content check: the gate differs from A's integration proof `3da63d9b` (= `e6ebd800` + #81; tsc 0, lint 0, 127 files / 2498) **only in docs and local scripts** — executable content identical. Nothing merged to `main`.
- **Production-order rehearsal, first two runs VOID (harness, not ordering):** run 1 used the old `replay_shim.sql`; run 2 used `rehearsal_bootstrap.sql` from the `snatchit-converge` checkout, which is on the older `release/candidate-20260918` line that has neither `replay_shim_supplements.sql` nor the auth scaffolding 131 needs (`auth.sessions`). Both died at #7 (131) with the identical error; D independently hit the same gap via `scripts/local/replay.sh` and fixed that caller at `6aead398`. Run 3 relaunched from the gate tree's own scripts.
- **Production-order rehearsal run 3 (gate-tree harness) — PASS for the manifest (A, 2026-09-22):** pre-apply world = production's historical order, 135 rows; **baseline body hashes equal production's, read the same day** (job_health `5621b447…`, detect_jobs `b0d6497f…`, alert_fire `dfcb1956…`, mark_listing_sold `7eb5525c…`, complete_auction_payment `d35ee07c…`, check_signing_key_invariants `928a4516…`, mark_transfer_sent ×2 → void; ops.alert 8 cols; net queue 0 rows). **APPLY 24/24 in pending order**, census 32|108|37|38 (= gate replay), every edge-called RPC keeps its identity args after apply. pgTAP 5339/5347: the 8 failures are exactly 184's and 186's "(126)" assertions — **proven 126-coupled** (126 applied to a copy → 184 90/90, 186 27/27, 193 65/65). **125/126 omitted as safely separable** (144 only calls existing functions; no later definer of 125's object). Manifest: `PRODUCTION_APPLY_MANIFEST_20260922.md`. Forward-back-forward rollback battery running on a copy.
- **CI caveat (D, 2026-09-22): the gate's pgTAP can fail intermittently in CI** — live pg_cron's `ops-detect-tick` fires during the ~30 s suite and contaminates 210 B6 and 213 Q1/Q3/Q4 (test isolation, not migration behaviour). CI at `6aead398` was RED with the suite having run (not re-run); the green runs at `26e9db09` and gate `c836bc43` were tick-miss runs. Local harnesses cannot catch it (no real cron). D is fixing both tests (park pre-existing alerts; scope comparisons to fixture keys) with injected contamination as the RED control; the fix lands on the gate as a test-only PR reviewed by A.
- **Forward-back-forward rollback battery on the production-order database — PASS (A, 2026-09-22):** 24 rollbacks in reverse order 24/24; identity after rollback equals production's pre-apply baseline exactly (7 body hashes, void overloads, ops.alert 8 cols, no amount_refunded_cents); second forward 24/24 reproduces the first apply's identities exactly. pgTAP after re-apply 5228/5230 — the 2 failures are 132 D-5/8–9 reading the stand-in cron.job row's database NAME (template-copy source name vs current db); command bytes/md5 identical; the first-forward db passes 132 11/11. Manifest §7 updated.
- **PR #88 (D, tests only) verified by A and MERGED into the gate (2026-09-22):** `fix/210-213-cron-tick-isolation` @ `f96ad207`, based on `c836bc43`, two files under `supabase/tests/`. A's independent check on a copy of the production-order database with a planted firing `job_failure:ops-detect-tick` alert (145-shaped payload): OLD tests fail exactly 210 B6 + 213 Q1/Q3; NEW tests 25/25 + 36/36 with the contamination present; the prefix-broken mutant fails B7 (anti-vacuity witness holds). Gate head now `56acf516`; executable content unchanged since `c836bc43`.
- **PR #89 (D) opened as the console review surface:** `admin/refund-classification-console` @ `3dab1614` → `admin/operating-console`, draft, DO-NOT-MERGE header stating merge ≠ deploy (Ignored-Build-Step pin; release act = pin update or CLI `--prod`, owner). D observed after opening: no snatchit-admin deployment created (deployments API), agreeing with the owner's three dashboard facts.
- **D's manifest verification consolidated (2026-09-22): PASS.** Items 1 (24-file order/exclusions, derived independently: 32 files ≥121 − 5 already in production − 121/125/126 = 24; all rollbacks present), 2 (125/126 separable incl. console side; 126's signatures compatible with 144's zero-arg calls), 5 (143–146 FBF quadrant independently; §7 identity cross-check). Item 4: A's enumeration omitted 127's `release_reservation` (signature-identical to 0590) — corrected; window still signature-safe. Item 3: baseline widened from 7 to **18 bodies**, read on production the same day — 18/19 rows identical; `cleanup_expired_reservations` differs by keyword casing only (bypass present in both; no callers; benign). Owner sentence recorded: the release ships the refund-resolution detector without 126's refund exactness. **The manifest is verified; the apply waits only on the owner's preflight items (Vault ceremony, AUTODEPLOY confirmation, backup).**
- **#20's rollback amended (A, 2026-09-22, from D's finding):** production's `cleanup_expired_reservations` is 000's body in uppercase; the rollback embedded the 000 text and self-verified against the 000 md5. Branch `fix/20260906110000-rollback-restores-production-body` @ `29128acf`, draft PR https://github.com/SnatchIt-app/snatchit/pull/90 against the gate: embeds production's captured text (`docs/release/captures/…_20260922.sql`), verification rebased to `113cebf6…`/`ecc0afc0…`; proven on a copy of the post-apply prod-order DB (exact match; unamended gives `95c21a0e…`). Rollback file + capture only. Awaiting D's verification before merge.
- **#90 revised on D's objection (2026-09-22):** embedding production's casing in a shared rollback would make the artefact environment-specific (breaks exact identity checks on rehearsal databases; invisible to CI, which never runs rollbacks). Final shape @ `0d445a70`: 000 body kept, verification block made truthful (states 000's values; records production's pre-apply casing variant and hashes; capture retained); byte-exact production restoration is an optional manifest-only line. Proof v2: rollback on a copy → def `95c21a0e…`, two functions dropped. D's pre-committed post-apply reference hashes (19 rows) recorded in the manifest §6 for the apply read-backs.
- **#90 D PASS at `0d445a70` (2026-09-22):** body block and every non-comment line identical to the gate's; the comment cannot be read as asserting production's value. D also verified the withdrawn commit's claims held (right work, wrong artefact). Residual adopted at `4652cb55` (comment-only, proven by diff + re-run): the verification now says CHECK BOTH HASHES — prosrc alone is identical across SECURITY DEFINER/INVOKER and search_path changes (D demonstrated: an INVOKER variant of the body has production's prosrc md5). **Follow-on hygiene item (not this release):** other rollbacks that verify on `prosrc` alone need the same warning — and, per D, the INVOKER demonstration must be run against EACH function rather than cited from this one (a `create or replace` per function), so the warning is specific and rollbacks whose function is neither SECURITY DEFINER nor search_path-pinned are left alone. D PASS at `4652cb55` (re-read: exactly four comment lines added; non-comment lines identical to `0d445a70`). Merge into the gate after CI on `4652cb55`. Register line, as D framed it: one catch (the baseline set) and one correction (the rollback's shape), the correction cheap because the design was published before it was proven.
- **#90 MERGED into the gate (A, 2026-09-22) after D PASS + CI green at `4652cb55`.** Gate head `5b255838`; since `56acf516` only `supabase/rollbacks/20260906110000_…_rollback.sql` and the capture file changed — executable content unchanged since `c836bc43`. The manifest's source head is now `5b255838`. **The gate is complete for this release; the apply waits only on the owner's preflight acts.**
- **CI green on the final gate head `5b255838` (read, not assumed; 2026-09-22).** Gate complete for the release; all repository work done. Outstanding before the production apply: owner's Vault `project_url` ceremony (A asserts the exact host on read-back before #9), fresh AUTODEPLOY-1 confirmation, fresh backup.

- **Execution preflight, 2026-09-22 22:47–23:00Z (A; owner's "execute to completion" instruction, 24-file manifest at gate `5b255838`).** Executable content `c836bc43` → `5b255838` unchanged (empty diff-stat over migrations/functions/app; the 24 migration blobs 24/24 identical; D's independent sha256 of the 24 blobs at `5b255838` = A's, 24/24). Production reads: ledger 135 / max numeric 120 / 0 rows ≥ 121 / 5 timestamped — unchanged; Vault names = `service_role_key` only (**`project_url` absent — owner ceremony open**); `net.http_request_queue` 0; edge versions unchanged (enforce-transfer-expiry v39 `bff961a3…`); the 19-row pre-apply body baseline re-read = the 00:32 baseline exactly (18 identical to the rehearsal world, `cleanup_expired_reservations` at production's `ecc0afc0…` casing variant, all `SECURITY DEFINER` with pinned `search_path`) — no drift since. Pre-apply census **27|71|37|27**, expected 32|108|37|38 after; production grants matrix (64 rows) differs from `expected_grants.txt` (69) only in the five tables this manifest creates (`account_deletions`, `checkout_group_claim`, `payment_refunds`, `payout_attempts`, `push_token_rebind_epoch`) and `push_tokens` client SELECT/UPDATE that the manifest revokes — the post-apply matrix must equal the fixture. **Backup (Management API, read):** plan pro, daily physical backups (wal-g) on, PITR off, newest COMPLETED 2026-09-22T13:45:46Z; verified by status, not by restore test (no target project; none authorised). **AUTODEPLOY-1:** `list_branches` → production `git_branch` = "" (updated 2026-08-27T15:49:25Z); owner's visual confirmation requested, API read not treated as the gate. **D:** declined the witness role on A's relay (standing instruction requires direct authorisation) — owner authorised D directly in D's session; D took its own baseline (all figures = A's), published an extended pre-committed reference (DEFINER + pinned search_path for every defined/redefined function except `ops.cron_expected_gap_minutes(text)` INVOKER/no proconfig by design; census 32|108|37|38; `ops.alert` 17 cols; 5 notify triggers; `ops.setting` 12 rows; no `ops.*` rows in the 69-row grants fixture), and holds the per-file PASS/STOP gate. **C:** Build 13's commit found via EAS (`3c67dfc9`, production profile, STORE, 2026-08-04); C's intersection at that commit = Build 9's profile exactly (same nine RPCs, every call site destructures only `error`; fail-closed except fire-and-forget `mark_transfer_viewed`) — the installed-client row closes for either store build; which build ASC serves is still the owner's fact (Chrome extension unreachable from A). Apply method fixed: one Management API query request per file = the file's exact blob bytes + its ledger row (`version` exact, `name` = stem, `statements` = array[file], `created_by` = `claude-a/owner-authorised-20260922`); per-file read-back (ledger row, md5/prosecdef/proconfig of every function the file defines, grants delta, census, switches); Vault exact-host assertion + queue re-read immediately before #9; deploy from detached worktree `gate5b` @ `5b255838` via CLI `--use-api --workdir`, `--no-verify-jwt` only for `stripe-webhook`, deployed source confirmed by download + sha256 vs the gate blobs. **Owner items open before file #1:** Vault `project_url`; AUTODEPLOY-1 visual confirmation; backup model decision (accept daily physical + 24 rollbacks, or owner-taken logical dump). Nothing applied, deployed, scheduled or switched on.

- **Preflight CLOSED 3/3 (A, 2026-09-22 23:08–23:29Z); apply HELD on a harness permission decision.** (1) **Vault `project_url`:** owner authorised A to create it (check-first: absent, count 0); created 23:08:30Z via `vault.create_secret` (id `2cc16426…`); read-back count 1, value byte-equal to `https://hqycwntpfoztoinemqns.supabase.co`; **D verified independently** (octet_length 40, no whitespace/trailing slash, matches 133's shape regex, queue 0). (2) **AUTODEPLOY-1:** owner's visual confirmation "AUTO DEPLOY OFF" 23:18Z is the gate; A's and D's `list_branches` reads (`git_branch` "", updated 2026-08-27T15:49:25Z) are corroboration only. (3) **Backup:** owner chose a fresh pre-apply logical backup — taken from ONE exported repeatable-read snapshot (`00000006-0001E831-1`, 23:27:37Z) with pg_dump 17.11 via the session pooler (the direct host refused TCP for this machine after three rejected logins — a wrong password was entered first; two earlier runs aborted before dumping: one authentication failure, one NULL snapshot id from A's own concatenation bug — archived under `failed_attempts/`); dump 4,431,823 B / 2,443 TOC entries / 0 errors; same-snapshot inventories (120 tables / 52,699 rows; 457 function hashes; ledger 135; cron.job 24; Vault names 2; auth ids 19; auth/identity delta since 12:00Z **0/0**; storage objects 178 + 5 buckets; roles). **Restore test PASS** (local PG 17.11 + shims): 120/120 table counts identical, 457/457 function definitions identical, ledger 135, census 27|71|37|27 — **D independently measured production's census 27|71|37|27 at 23:31:30Z** (ledger 135 at that moment), agreeing with the restore; checksums regenerated after the log closed, all matched. Consistency with the 13:45:46Z physical backup measured (A + D): managed half idle since 2026-09-20, ~90 FKs into `auth.users`, none into storage; **the one gap is Vault (`project_url` post-dates the physical backup)** — explicit rebuild step in the runbook `docs/release/PRE_APPLY_BACKUP_20260922.md` ("not a complete current backup"; tiered recovery; windows). Password file securely deleted; restore DB dropped. **Byte-count slip disclosed:** A quoted file #1 as "4,951 bytes" (Python character count); the blob is 4,973 bytes, md5 `eba2f9a2…`, sha256 `3370f8ee…` — D's independently computed md5/byte anchor for all 24 blobs matches A's fresh read 24/24 and is the expected-md5 source for every apply guard. **HELD:** the harness's permission policy did not allow the byte-exact apply script (Management API from Bash) nor the MCP `execute_sql` route for file #1 in the current auto mode; A stopped rather than seek another route and reported to the owner. D's pre-apply baseline 23:31:30Z: public 27|71|37|27, ops tables 13, `ops.alert` 8 cols, cron.job 24, ledger 135; expected total delta over 24 files: tables +5, functions +37, policies +0 (any change = STOP), triggers +11, ledger +24, cron.job count 0 net (133 re-schedules five), `ops.alert` 8 → 17 at #18. **Nothing applied; ledger 135; no production write since the Vault entry.**

- **Execution package FROZEN for prompted approval (A, 2026-09-22 ~23:45Z; owner's instruction: prompted approval on the reviewed file-based path, no SQL transcription, no broad allow rule).** Scratchpad `apply_5b255838/`: `apply_one.sh` sha256 `ec26cfec…` (8,835 B); `deploy_one.sh` `51b69cff…` (3,210 B); allowlist `manifest_sha256.txt` `0c0b481e…`; D's md5/byte anchor `d_md5.txt` `9c9b38b0…`; 24 migration blobs aggregate `b8331215…`, 24 rollback blobs aggregate `5b69dad9…`; deploy worktree `gate5b` @ `5b255838`, clean. Files set read-only; any later change requires disclosure and review before execution. Invocation `apply_one.sh NN` (01–24, one file per call, ascending), `readback`/`vault` read-only forms; target hard-coded `hqycwntpfoztoinemqns`. Enforced in-script: allowlist index + sha256, D's anchor md5 + bytes, file-9 Vault exact-host guard, file-21 `rollback_archive` guard; procedural: D's explicit PASS before the next number; stop on denial, non-201, read-back mismatch or STOP. Session switched auto → default so each invocation presents an approval card.

- **PRODUCTION APPLY COMPLETE — 24/24 (A, 2026-09-22 23:46:48Z → 2026-09-23 03:06:35Z; owner's prompted-approval decision, frozen script `apply_one.sh` sha256 `ec26cfec…`, D's per-file PASS before every next file).** Ledger 135 → **159** (24 rows `created_by = claude-a/owner-authorised-20260922`; 18 three-digit ≥121, 11 timestamped); public census 27|71|37|27 → **32|108|37|38** = D's pre-published release-level deltas (+5 tables, +37 functions, +0 policies, +11 triggers) exactly; ops functions 90 → 96, ops.setting 9 → 12, `ops.alert` 8 → 17 columns; kernel 153 → 157; notify 17 → 22 functions / 7 → 9 tables. Every file: anchor (D's md5 + bytes) = local blob; `md5(statements[1])` = anchor; every function body = D's pre-committed prosrc md5 (all 24 files, 0 mismatches); the 19 original references = final production values 19/19; the public grant matrix = `expected_grants.txt` @5b255838 line-for-line (69 = 69). **Switches:** `refund_resolution_detector_enabled=false` and `alert_delivery_enabled=false` (jsonb booleans), verified by observation on every 5-minute detector tick since they landed — the refund detector records `skipped {"reason":"refund_resolution_disabled"}`, 0 refund_resolution cases; all 17 `ops.alert` rows carry no delivery state (queued_at/notify_request_id/delivered_at/delivery_status NULL, notify_attempts 0, incident_seq 1); cron 24 jobs, none referencing `dispatch_alerts`; `net.http_request_queue` 0. **Live checks that passed on real ticks:** 143 (jobs detector, cron history still available), 144 (detector skipped-as-disabled), 145 (job-not-running detector opened nothing; `cron_job_first_seen` populated with all 24 job names, giving every job its full grace from apply time), 146 (replaced `alert_fire` touched none of the 17 rows), 133 (host references 4→0 in functions, 5→0 in cron; five jobs re-scheduled as jobids 32–36; purge inert with the Vault value exact), 22 (deletion sweep succeeded on the new body at 02:58:02Z). **Holds and guards exercised:** 03 re-invoked after a closed approval stream (verified nothing committed first); 04's card waited ~55 min (production untouched meanwhile); file-9 Vault assertion PASS at invocation; file-21 archive guard: manifest + schema absent, three ledger tables created with 0 rows; file-23 held on an ACL read-back mismatch vs D's gate — traced to production's `pg_default_acl` (service_role EXECUTE on new public functions) + the file revoking only public/anon; consistent with the recorded CI decision `authenticated-execute`; D ruled PASS after reproducing the mechanism across tonight's files. **Findings for the report (D, privilege-visibility family):** (i) function-level privileges invisible to the table-grant matrix; (ii) column-level privileges invisible (128 moved push_tokens client privileges to columns: authenticated SELECT 12/14, UPDATE 4; anon lost read/write); (iii) new columns inherit table-level client SELECT (payments 18→21 client-readable columns; benign — SELECT-only policies, no client path accepts the claim token); (iv) new functions inherit default-ACL grants. Plus: the 16 firing alerts (all `p1_case`, first fired 2026-09-08) would be dispatched as a backlog on first activation (owner choice: drain at low `p_limit` or acknowledge first); signing monitor `signing.monitor_enabled` true since 2026-09-11 (job daily 05:23Z) is the first unattended execution of a 133-replaced function — not a release switch; 145's `* * * * *` schedule sensitivity gap (crm-export-build-tick, 1500-min threshold, pre-existing). **Managed-schema consistency re-measured after the apply:** users created/updated 0, identities 0, MFA factors 0, storage objects 0 since 13:45:46Z — the backup halves did not diverge. **Catalog fingerprint vs the local production-order rehearsal DB:** catalog/kernel/market/notify/ops/venue identical on every kind; public identical for all 27 untouched tables and the 5 release tables; the 47 release-touched public functions identical (md5 `130c5c21…`); residual = pre-existing production≠chain drift only (5 tables' legacy columns/constraint names/indexes; 12 untouched functions) — reconciliation item, not a release defect. Deploy stage not started; awaiting D's PASS on 24 and D's four closing checks.

- **DEPLOY STAGE IN PROGRESS (A, 2026-09-23 03:28Z →; owner's direct authorisation; frozen `deploy_one.sh` re-frozen at sha256 `029c6af7…` after D's two enforcement findings — verify_jwt now asserted, expected shared closure enforced both ways — plus A's local two-directional checker `check_download.sh` for the function's own directory; D authorised directly to witness).** Pre-deploy: rollback set captured 03:28:14Z (`apply_5b255838/edge/rollback_20260923T032814Z/`, 28 files, SHA256SUMS; all ten tied to repository blobs — six = origin/main, enforce-transfer-expiry = backport f5e91e74, create-payment-intent + confirm-and-release = d0b155da, delete-account = 74479b81; D verified integrity, provenance and one function cross-mechanism via the Management API); starting JWT posture verified by A and D (stripe-webhook false, nine true); D's pre-deploy baseline = A's on all ten. **Order refined on D's finding:** `_shared/payouts.ts` changes the payout idempotency key scheme (`payout_<transfer>_<destination>_src` → `payout_<transfer>_a<attempt>`, attempt-ledger-backed); only confirm-and-release and enforce-transfer-expiry bundle it, so they deploy adjacently (population at risk today: 0 transfers awaiting payout; newest transfer 2026-08-05). **Deploys (each: pre-read = baseline → card → script PASS → independent check PASS → D PASS from D's own reads incl. a served-bundle fetch with pre-committed discriminators):** 1. create-payment-intent v47→v48 (ezbr e91742eb…; 4 files; only index changed; D fetched the served bundle: claim_checkout_supersede/release_checkout_supersede/claim_checkout_group/record_checkout_attempt present, absent in v47); 2. confirm-payment v36→v37 (966a8b01…; 3 files; only index changed; served bundle carries settle_verified_payment ×7 and the new argument names — confirmations now route through the settlement path created by 20260906110000); 3. confirm-and-release v36→v37 (3b033bb8…; 5 files; index + payout-logic + payouts changed, sentry/stripe unchanged; D PASS pending at time of writing). Disclosed artefact: the CLI writes `supabase/.temp/{cli-latest,linked-project.json}` beside every download (also in the rollback captures); the local checker is scoped to `supabase/functions`. After each deploy: the other thirteen functions (incl. B's four out-of-scope: auto-finalize-auctions v18, credential-sign v1, door-manifest v1, door-session v1) unchanged; both switches false; 16 firing / 17 alert rows with no delivery state and 0 acknowledged (backlog preserved, not acknowledged); net queue 0; ledger 159; payout_attempts 0 rows. D's notify-report finding: deployed v9 has no `delivered` field, so delivery is mechanically impossible until the RC notify-report deploys; the switch remains the control.

- **DEPLOY STAGE STOPPED AFTER DEPLOY 4 — live-run defect, no money moved (D STOP 03:55:20Z; A confirmed 03:57:09Z).** Deploy 4 enforce-transfer-expiry v39→**v40** (ezbr `8370c58d…`, 6 files byte-identical to the gate, JWT true, D's seven discriminators present in the served bundle; artefact PASS stands) closed the payout-key window (open 03:47:53Z–03:51:12Z, population 0). Its first cron runs on the new code (03:52, 03:54, 03:56 — all 'succeeded') each wrote one `public.webhook_retries` row for the SAME live payment (`7f0b099e…`, succeeded, livemode, buy_now, paid 2026-08-04, total 220; listing `f499dc79…` status 'active' WITH `sold_at` 2026-08-04 17:46Z; transfer `80180da9…` buyer_confirmed with a Stripe transfer id): `rpc_name settle_verified_payment`, `error_message 'unfulfillable:manual_review'`, `resolved=false` — 3 rows at 03:57Z, +1 every 2 minutes. **Mechanism (gate source):** `get_unsettled_payments` paid_unsettled branch (20260916000000 line 51: `l.status <> 'sold' OR NOT EXISTS transfer`) selects the payment because the listing is 'active', without consulting `webhook_retries`; `settle_verified_payment` sees the existing transfer, declines to settle and INSERTS a fresh marker row each run; only the review_unfulfillable branch excludes the marker. The marker's documented disposition ("operator item, not sweep work") is not implemented by the selecting branch — the exact "documented residual" the owner ruled out passing. **Money rails unchanged:** transfers with stripe_transfer_id 23 (= baseline), payout_attempts 0, payment_refunds 0, payments with amount_refunded_cents 0/57; payment row unchanged; no case/alert; both switches false; backlog 16 unacknowledged. Positive: the sweep correctly detected a real pre-existing inconsistency (paid + transferred + paid-out purchase whose listing was never marked sold — Aug-4 incident era). **Held:** deploys 5–10 (stripe-webhook, create-connect-account, delete-account, notify-report, notify-transfer, send-push) not invoked; nothing touched (rows, payment, listing, code) pending the owner's decision: (a) source-level rollback of enforce-transfer-expiry to the v39 capture; (b) owner-authorised single-row listing correction to 'sold' (ends the loop at source, keeps the deployed pair consistent; marker rows kept as evidence); (c) leave running (~720 rows/day). A follow-on code fix (selecting branch honours an unresolved manual_review marker) is required in every case, via the normal review cycle.

- **CONTAINMENT + FIX (A, 2026-09-23 04:03–04:15Z; owner's instruction).** Containment (one verified live-money listing → 'sold'; deploys 5–10 stay stopped): pre-write evidence assembled and sent to D for independent verification — listing `f499dc79-bd50-49ca-a725-1f614be72558`, payment `7f0b099e-7dd1-4e6c-88cc-3c76079d9904` (succeeded, livemode, paid 2026-08-04 17:46:04Z, total 220, refunded NULL), transfer `80180da9-b6e0-45ca-b2d4-5f4db70b3efb` (buyer_confirmed 17:47:54Z, payout_released_at 18:12:04Z, stripe_transfer_id present); listing status 'active', `sold_at` 2026-08-04 17:46:02Z, auction_status cancelled; predicate matches exactly 1 row; triggers: `guard_listing_state` needs the transaction-local `app.bypass_listing_guard='on'` (the RPCs' own mechanism), `trg_listings_updated_at` will bump `updated_at` (disclosed; suppressing it would need DDL), no AFTER trigger fires on a status change, no post/notify/pay/refund; `webhook_retries` readers: `settle_verified_payment` (writer), `get_unsettled_payments`, `account_deletion_blockers` (0 deletions), gate edges only — no worker consumes manual_review markers. Exact statement: one transaction, exact current state in the predicate, `get diagnostics` row_count must be 1, status only. **Write NOT yet performed — awaiting D's VERIFIED.** Loop 9 rows at 04:08Z; money rails unchanged. **Siblings (separate, not touched):** `dac58ca2…` (sold_at 02:18Z; payments refunded + failed; transfer reversed, unpaid) and `b0a01d80…` (sold_at 03:26Z; payment refunded; transfer reversed) — reversed/refunded orders whose listings are 'active' with a stale `sold_at`; NOT sweep candidates (no succeeded payment) and cannot loop; proposed repair (later, separately authorised): clear `sold_at` on those two under exact-state predicates, or leave as is — no operational effect either way. **Code fix (isolated):** branch `fix/sweep-manual-review-exclusion` @ `a77d2b8d` off `5b255838`, draft DO-NOT-MERGE PR #91 — migration `20260923000000_sweep_manual_review_exclusion.sql` (registry 147), rollback, pgTAP 214 (11); evidence in the registry row; D review pending; deployment artefact to be prepared only after review; production apply only on the owner's separate authorisation. Disclosure: the first rollback generation embedded a Python object repr (never applied; the RED-after-rollback step showed PASS and exposed it); regenerated and the full cycle re-run clean.
- **147 REVIEW ROUND 1 (D 04:17Z; A 04:18–04:35Z).** D's independent review of `a77d2b8d`: five findings, none blocking containment. **R1** (exclusion narrower than the producer chain; recommended `LIKE 'unfulfillable%'`) — **rejected with evidence**: every review_unfulfillable candidate carries an unresolved `unfulfillable%` row by the branch's own predicate, so a LIKE exclusion in the deduped CTE silences that branch for every candidate and stops the refund path. The relabel-failure concern is real but bounded: a row the edge relabel (v40 `index.ts:429–431`) has not reached stays `unfulfillable:listing`, is selected under review_unfulfillable (priority 1), `settle_verified_payment`'s per-literal guard (`20260906110000:334–339`, `:318–323`) inserts nothing, the handler retries the relabel, and no Sentry capture is reached on markErr — cannot grow, self-heals. New **A13** guards the exact match. **R2 accepted — corrects A's earlier follow-on note:** the settle inserts are already idempotent per literal; growth came from the edge relabel moving the row out of the guard's range (why +1 per cycle). Follow-on outside 147 (optional second layer, not authorised): edge writes a distinct marker, or the DB guard widens to LIKE. **R3** — **A12** (exclusion under `app.allow_test_mode_money='on'`, the parenthesisation). **R4** — header states the `settle_listing_for_payment` disposition defect (skipped `status='sold'` early return → `auction_status='cancelled'` → unfulfillable) is separate and unaddressed; 147 is selection only. **R5** — D diffed the function text: only the comment and WHERE changed. Revision `98fb4063` pushed (PR #91 updated); body unchanged (defn `705953d5…` / prosrc `06ef87b3…`). Evidence (local harness; predictions written before running): fix-tree fresh replay 201 9/9 + 214 13/13, census 32|108|37|38; gate-tree NC (prosrc `37b86cc4…` confirmed first) fails exactly A2,A3,A5,A6,A7,A11,A12; mutant M1 (parentheses removed) → {A12}; M2 (LIKE widening) → {A13}; each mutant asserted applied (prosrc changed) and digest-restored; rollback cycle re-run clean. **CI at `98fb4063`:** run 35818081121 green (fresh-DB census 32|108|37|38, pgTAP Files=94 / Tests=5474, 214 ok); migrations-guard red on both heads for the missing `AUTODEPLOY-VERIFIED-OFF` marker only (it exits before its invariants) — marker `2026-09-22` added to the PR body (owner's 23:18Z confirmation), guard run 35818298993 green. Candidate branch docs pushed to origin (was 158 ahead). D re-review pending. **Containment write still HELD pending the owner's go/hold** on D's Finding 3 (detector auto-resolve would move firing alerts 16→15, open cases 20→19; nothing deleted/acknowledged/delivered) against the standing instruction to preserve the 16-alert backlog; D confirmed at 04:16Z: listing still active, markers 13, money rails 23/0/0/0. Deploys 5–10 stopped.
- **147 D PASS + DEPLOYMENT ARTEFACT (A, 04:29–04:36Z).** D: PASS on `98fb4063`; R1 conceded from source (the two predicates partition the marker space by design; my bound checked link by link incl. the markErr path); A12/A13 discrimination and incident fidelity (f499dc79 / 7f0b099e / 80180da9 reproduced) confirmed; evidence limit stated (D read, did not run). Two non-blocking notes: (1) **observability follow-on** — a PERSISTENT relabel failure (e.g. a permissions change) would re-select the payment as review_unfulfillable every 2 min with no Sentry page (captureException sits after the successful update; reconciledErrors only reaches the cron's unread response) → follow-on register, alongside the R2 options (distinct edge marker / LIKE guard); (2) A4 comment tightened → `2bf67af9` (comment only; migration blob `0898a84f…` unchanged). **Artefact frozen** at `scratchpad/apply_147/` — see the registry row and README_147.md for hashes, invocation, expected read-back (ledger 160, defn `705953d5…`, prosrc `06ef87b3…`, secdef, search_path=public, service_role-only execute, census 32|108|37|38, switches unchanged) and rollback. Sequence from here: D writes its external md5+byte anchor and re-reviews the 40-line script diff → owner's separate apply authorisation → apply (one request) → read-back → D PASS → live-tick check. **Corrected release sequence:** (1) containment write (owner go/hold pending; markers +1 per 2 min meanwhile, no money) and its two observed cycles; (2) 147 apply as above — same `get_unsettled_payments(integer)` signature, called only by enforce-transfer-expiry v40 Phase 0, no other dependency; (3) deploys 5–10 on the owner's explicit resumption (stripe-webhook, create-connect-account, delete-account, notify-report, notify-transfer, send-push — none depend on 147 or on the containment); (4) verification window + C's combined app checks + signing monitor 05:23Z result; (5) consolidated decision request. **Changed dependency:** the release now carries 24 + 1 migrations; 147's source is PR #91 (`2bf67af9`), not the gate `5b255838` — the gate stays the source for the ten functions; PR #91 merges into the gate branch after the apply (never to main without the marker; it carries `AUTODEPLOY-VERIFIED-OFF: 2026-09-22`). Refund detection and alert delivery remain off; 16-alert backlog untouched.
- **147 ANCHOR + ARTEFACT REVIEW + ORDERING OPTION (D 04:41Z; A 04:39–04:45Z).** D computed the external anchor from the git ref at `2bf67af9` (md5 `7decdea1…`, 9,950 B — equal to A's independent pair), confirmed the staged copies are byte-identical to the git blobs (`0898a84f…` / `8860ad1e…`) and reproduced the script hashes; d_md5.txt written by A from D's message (read-back by D pending). Script review: PASS on apply_one_147.sh (prestate guard, `%147:%` comment flag, no dollar-quote collision, no `-e` so the diagnostic prints, single-version DELETE, token never echoed); **finding on rollback_147.sh** — no pre-state guard, its hash check is a post-condition on its own output, so a later migration that touched the function would be silently reverted → **fixed**: symmetric pre-state guard (ledger row 1, defn `705953d5…`, prosrc `06ef87b3…`, else exit 3, DRY-skipped), re-frozen sha256 `f45c4a72…` (3,728 B; supersedes `73d4dfba…`), disclosed to D for re-review; README updated. Informational (both scripts): the migration and rollback files self-transact, so the appended ledger statement runs in a separate transaction — on a non-201 read the ledger row and both hashes before any retry (probe = ledger row, version PK). **Ordering option (D; A verified from 117_ops_console_automation.sql):** `ops.detect_paid_unsettled` has its own inline predicate and references neither get_unsettled_payments nor webhook_retries, so applying 147 FIRST stops the loop on the next sweep (the payment carries unresolved manual_review rows) while the p1 case and alert stay open — firing backlog stays 16, open cases 20; the containment write then becomes an unhurried data repair whose only cost is 16→15. Put to the owner as an option; both actions remain separately authorised. Nothing applied; deploys 5–10 stopped.
- **147 ARTEFACT: D CONFIRMED ANCHOR + PASS ON ROLLBACK GUARD; MESSAGE WIDENED (D 04:47Z; A 04:48Z).** D read d_md5.txt itself (53 B, sha256 `b1478b38…`, md5 recomputed live from the git ref) — confirmed. Rollback guard PASS (D read the whole script: only lines 14–36 inserted). D diagnostic note, taken: the guard's failure message named only 'a later migration may own this body', but the likelier cause is a PARTIAL APPLY (DDL committed in the file's own transaction, ledger insert failed separately → defn/prosrc at 147's values with ledger_row_count 0), which trips the same guard; refusing there is right, the wording pointed at the wrong cause → message now names both and tells the operator to read the ledger row first. Wording only; DRY re-run clean; rollback_147.sh re-frozen sha256 `a9581426767f43208f70d5b6b5bf640c40c849df798cb8e1fcdc93df9a0bb589` (3,917 B), README updated; D re-anchor pending. D state read 04:38:29Z: nothing applied, ledger 159, listing active, markers 24, alerts firing 16, open cases 20, money rails 23/0/0/0. Both decisions with the owner.
- **147 ARTEFACT CLOSED (D 04:52Z).** D re-anchored rollback_147.sh `a9581426…` (3,917 B): the 189-byte growth equals the single widened line (126 → 315 B), line count 45 unchanged, every reviewed construct at the same line number; all other artefact files re-hashed unchanged and the staged SQL still matches the git blobs at `2bf67af9`. Closed state: 147 passed at the blob level (`0898a84f…`), apply + rollback scripts reviewed and anchored, read-back expectations pre-committed by both sessions, anchor file independently derived and byte-identical. Nothing runs without the owner's instruction in their own turn — not the 147 apply, not the containment write, not deploys 5–10; neither session treats the other's messages as that instruction.
- **OWNER AUTHORISATION (2026-09-23 ~22:44Z) + STEP 1: 147 APPLIED (A 22:46:46Z).** The owner directly authorised, to A and D, the sequence (1) apply 147 first from the frozen artefacts at `2bf67af9`, hashes confirmed vs the independent anchors incl. staged SQL, starting state rechecked, applied once, function + ledger verified, D PASS, two complete scheduled sweep runs observed (markers stop growing, existing markers kept, case stays open, 16-alert backlog intact, money vs fresh baseline); (2) then the single live listing → sold (guarded, exactly one row, records preserved; the 16→15 detector movement accepted; no manual acknowledgement of unrelated alerts; D verifies result + following sweep); (3) then deploys 5–10 under the existing exact-source checks and D's per-deployment gates; no re-run of the 24 migrations or deploys 1–4; refund detection + alert delivery stay off; no switches/dispatch/test notifications/console scope; C's compatibility checks when deployment finishes; the release is not 'complete' until its verification window passes. **Execution:** artefact hashes re-verified at execution time — disclosure: the first check script used a bash-4 associative array that macOS bash 3.2 rejected, so its seven-file loop never ran and its summary was vacuous (blob, anchor and mode checks in it were real); re-run in 3.2 form 22:45:35Z, 7/7 match, staged SQL = git blobs at `2bf67af9`, corrected to D before anything ran. D pre-state PASS 22:45:04Z (ledger 159/0, hashes 8052e269…/37b86cc4…, census, switches, money rails, markers 567 = 24 + 18.1 h × 30/h exactly — linear, one payment, one error shape). A baseline 22:46:31Z (markers 568, latest 22:46:04Z; alerts 16/1, ack 0; cases open 20; c58de574 open; listing active). `apply_one_147.sh 01`: anchor ok, prestate 0 / 8052e269… / 37b86cc4…, HTTP 201 at 22:46:46Z; read-back 22:46:48Z = every pre-committed expectation (ledger row + 160; defn `705953d5…`; prosrc `06ef87b3…`; secdef; search_path=public; comment_147 true; execute service_role only; census 32|108|37|38; switches true/false/false; grant_rows 69). D's independent post-apply read pending; two-sweep window 22:48:04Z / 22:50:04Z in progress with frozen marker baseline 568.
- **STEP 1 WINDOW (A read 22:51:03Z).** Two complete scheduled sweep runs after the 22:46:46Z apply — cron.job_run_details 22:48:01Z succeeded, 22:50:02Z succeeded (22:46:01Z was the last pre-apply run, whose marker at 22:46:04Z is the newest row). Markers for 7f0b099e 568 → 568 (frozen), all pre-existing rows present (earliest 03:52:06Z), webhook_retries total 568, one distinct error_message; `get_unsettled_payments(50)` evaluated live: 0 rows for the payment and 0 rows overall. Money rails identical to the fresh baseline (transfers_with_stripe_id 23, payout_attempts 0, payment_refunds 0, 0 of 57 refunded cents). Alerts 16 firing / 1 recovered, acknowledged 0; cases open 20; case c58de574 open; its alert firing (fire_count 1, recovered_at null, ack null); listing f499dc79 still active/untouched; switches true/false/false. Ledger 160, hashes 705953d5…/06ef87b3…. **Step 1 PASS on A's read; D's independent window PASS pending; step 2 (containment) starts only after it.** Housekeeping: seven background wait loops from earlier in the session had been spinning on a zsh parse error (`\>` inside `[ ]`) instead of waiting — stopped; the window timer was re-run under bash.
- **STEP 1 D PASS (22:50:40Z) → STEP 2 CONTAINMENT WRITTEN (A 22:53:05.914Z).** D's step 1 PASS: every pre-committed value matched; D derived the expected prosrc hash itself from the reviewed file (5,734 B between the delimiters → `06ef87b3…`), confirmed the parenthesised test-mode disjunction is live in the deployed prosrc, called `get_unsettled_payments(200)` → 0 rows, and joined cron.job_run_details (jobid 32) to markers per run: eight runs before the apply each wrote exactly one marker, the two after (22:48:01Z, 22:50:02Z) wrote none — a clean step change; off-switches re-confirmed (alert_delivery, refund_resolution_detector, refund_execute false; refund/payout executors false). D pre-write revalidation PASS 22:51:27Z; A's own revalidation 22:52:55Z identical field for field (one succeeded live payment, one buyer_confirmed transfer with payout released, predicate 1 row, seven triggers 'O', status check admits 'sold'). **Write:** the reviewed statement (transaction-local bypass, five-term predicate, row_count must be 1) via the harness SQL tool; committed. Read-back 22:53:44Z: listing `f499dc79…` status **sold**, updated_at 22:53:05.914Z (the disclosed maintenance bump), every other column unchanged (sold_at, auction_status cancelled, reserved_by/until null, winner null, proof_status pending_review, ended_at null); payment 7f0b099e and transfer 80180da9 unchanged; markers 568/568 unresolved, latest 22:46:04Z, preserved; money 23/0/0/0; net queue 0; alerts 16/1, ack 0, cases open 20, c58de574 open (detector tick 22:55:00Z not yet run; its predicate now evaluates FALSE for this payment → the accepted 16→15 / 20→19 transition expected on that tick); `get_unsettled_payments(50)` 0 rows. The sold_at-but-not-sold class now = exactly the two test-mode siblings `dac58ca2…`, `b0a01d80…`, untouched. Residual as recorded: status sold paired with auction_status cancelled. D's verification of the result, the following sweep and the detector tick pending; step 3 waits on it.
- **STEP 2 POST-WRITE OBSERVATION (A read 22:57:18Z / 22:58:00Z; D formal PASS pending).** Detector tick (jobid 30) 22:55:01Z succeeded: case `c58de574…` → resolved (resolved_at 22:55:01.519688Z, resolved_by null, note 'auto: condition no longer detected'), exactly one new case_event `auto_resolved` (reason condition_cleared, actor null) — the case's only other event is its 2026-09-08 'created'; alert `case:paid_unsettled:7f0b099e…` → recovered at the same instant, acknowledged_at null, delivered_at null, fire_count 1. Alerts firing 16→**15**, recovered 1→**2**, total 17 (nothing deleted), acknowledged 0, delivered 0; alerts touched since the write: exactly 1. Cases open 20→**19**, resolved 2, total 21; paid_unsettled open 9→8; status changes since the write: exactly 1; case_events since the write across all cases: exactly 1. Observation explained: 18 other OPEN cases carry updated_at = last_seen_at = 22:55:01.519688Z with no event and no status change — the detector's routine per-tick re-detection touch (`ops.detect_case` → `ops.case_upsert` in `115_ops_console_foundation.sql`), identical in kind to every previous tick; the two untouched cases (650e7344 open since 09-08, 87ba723e resolved 09-08) are simply not re-detected. Sweeps (jobid 32) 22:52:02Z / 22:54:02Z / 22:56:02Z succeeded, markers frozen at 568 (latest 22:46:04Z), listing sold (the only listing updated since the write), money 23/0/0/0, net queue 0, switches unchanged. Exactly the accepted transition and nothing else. Step 3 waits on D's PASS.
- **STEP 2 D PASS (22:58Z) → STEP 3 BEGUN.** D verified the write on its own reads (22:54:39Z, 22:56:02Z): one row, status only plus the disclosed updated_at; 'exactly one row' established from the table (listings updated today = 1), siblings untouched, records preserved, detector transition exactly as pre-committed (case c58de574 resolved v1→2 with one `auto_resolved` event; alert recovered, ack null; 16→15, 20→19, totals 17/21 intact; the only other recovered alert is a 2026-09-08 job_failure; the only case resolved today is ours). D closed the 18-touched-cases observation from source: `ops.case_upsert`'s found-path updates only last_seen_at/summary/due_at/priority (never status or version), so re-detection is structurally incapable of changing state; discriminator: the 18 have updated_at = last_seen_at, c58de574 has updated_at ≠ last_seen_at (last_seen 22:50:02Z, updated 22:55:01Z) and is the only case whose version moved tonight. Two D findings to the follow-on register: (a) pg_net/cron 'queued is not delivered' — the 22:56Z sweep POST timed out client-side while cron.job_run_details logged SUCCEEDED, a pre-existing ~3% background rate (6/180 in 24 h); (b) open case 650e7344 is watched by no detector since 2026-09-08. **Step 3 order (six remaining):** stripe-webhook → create-connect-account → delete-account → notify-transfer → send-push → notify-report LAST (D: deploying notify-report removes the 'handler mechanically incapable of delivery' half of the alert-delivery safeguard, leaving the 15 firing alerts behind the single `alert_delivery_enabled=false` switch — stated before it happens; the owner is informed). Contract check from the diffs: stripe-webhook, notify-transfer and notify-report call send-push with the same `{user_id,title,body,data}` payload in both versions and the gate send-push accepts it with no dispatch switch (it adds the b2 challenge path), so contract does not constrain the order. Per-function gates: dry-run pre-state (version/ezbr/verify_jwt) = rollback set → D PASS → deploy via the frozen script (JWT asserted after) → check_download.sh two-directional set + bytes → D's own bundle fetch → D PASS. stripe-webhook pre-state 22:59:21Z: v41, ezbr 33a3bf2c…, verify_jwt False = rollback set; expected after: False, 5 files.
- **DEPLOY 5 stripe-webhook (A 23:02:45Z) — v41→v42, verify_jwt False (asserted), ezbr 33a3bf2c…→e4239d64…; script result FAIL on the expectation model, deployment itself correct — D PASS/STOP pending.** deploy_one.sh's deployed-source comparison reported 5 files checked / 2 MISMATCH: own-directory `native-dispute.ts` and `native.ts` MISSING from the download; index.ts, _shared/sentry.ts, _shared/stripe.ts byte-identical to the gate. Discrimination (A): (1) gate index.ts imports only ../_shared/sentry.ts and ../_shared/stripe.ts; nothing at the gate references native.ts / native-dispute.ts except native-dispute.ts's own type import — both files entered with 471c863c (093, NOT DEPLOYED) and cf9b780a (096–099) and were never wired into the entrypoint; (2) the full deploy log shows exactly three 'Uploading asset' lines (index.ts, _shared/stripe.ts, _shared/sentry.ts) — the CLI uploads the import graph [correction per D: the v41 rollback capture holding only index.ts + sentry.ts is NOT corroboration — native.ts / native-dispute.ts did not exist at origin/main, so both models predict the same two files for v41 and it discriminates neither]; (3) check_download.sh: expected 5 / downloaded 3 / MISSING the two / no unexpected file / all present files ok; (4) live probe: two unsigned POSTs → HTTP 400 'Invalid signature' — the function boots to its signature check. **Corrected expectation:** the deployable set for stripe-webhook is the import-graph closure {index.ts, sentry.ts, stripe.ts} = 3 (deployed 2 → 3 = +stripe.ts). The frozen script's own-dir model (git ls-tree of the directory) is a superset for this one function — it STOPPED rather than passed, as designed; not edited (no re-deploy needed; the remaining five have one own file each). Residual recorded: two unreferenced modules in supabase/functions/stripe-webhook at the gate. Housekeeping: `${PIPESTATUS[0]}` is unset under the tool's zsh (it is `$pipestatus[1]` there) — the chained check_download did not auto-run and was run separately under bash.
- **DEPLOY 5 D PASS (23:07Z).** D's own fetch of the served bundle: 789,560 B, sha256 e85c3023…; module specifiers exactly stripe-webhook/index.ts, _shared/sentry.ts, _shared/stripe.ts; discriminators present (stripeFetchRaw ×6 — gate-only import, so the new code is live; 'Invalid signature' ×2; captureException ×18); edge logs 23:00–23:08Z: exactly A's two unsigned probes, POST 400, no boot errors, no 5xx. D withdrew its pre-committed count of 5 (directory-union over-predicts where a directory holds unreferenced files; correct deployable set 3); D confirmed the remaining five have one own file each and no sibling imports, so their counts stand (3/2/1/1/2). Standing invariants at 23:07:18Z unmoved (markers 568, listing sold, money 23/0/0/0 of 57, alerts 15/2, ack 0, cases open 19, alert_delivery_enabled false, ledger 160). Two register items from D: (a) vacuous-check class instance 4 — grep -F on the bundle binary returned 0 for present literals; caught by a positive control, re-run via `strings`; (b) **096–099 native dispute wiring is not wired** — native.ts / native-dispute.ts unreachable from any entrypoint at the gate; never deployed, no regression, but the release must not be described as shipping native dispute handling; owner disposition needed. create-connect-account pre-state 23:04:58Z: v34 / d79ef873… / True = rollback set; expected after True, 3 files; sent to D.
- **DEPLOY 6 create-connect-account (A 23:10:25Z) — v34→v35, verify_jwt True (asserted), ezbr d79ef873…→33d8cf9e…; PASS on A's checks, D PASS pending.** D pre-deploy PASS 23:09Z (value-approved JWT True for an app-called authenticated function; diff read: type-only — `type SupabaseClient` import specifier and a parameter annotation, erased at transpile; pre-committed that an unchanged ezbr would discriminate nothing, and that version 34→35 plus index.ts = gate blob 05c3d17f… are the discriminators). Full deploy log: three uploads (index.ts, _shared/stripe.ts, _shared/sentry.ts). Deployed-source comparison 3/3; check_download.sh set-equal both ways, all bytes identical (index 05c3d17f…, sentry e41fd1f8…, stripe 21cd0a09…), no unexpected file. ezbr moved — recorded as an observation only.
- **DEPLOY 6 D PASS (23:12Z) → DEPLOY 7 delete-account (A 23:13:37Z) — v21→v22, verify_jwt True (asserted), ezbr 4ae953af…→db1acec2…; PASS on A's checks, D PASS pending.** D on deploy 6: served bundle fetched (708,867 B, sha256 a8984c3b…), exactly three modules, positive controls first (index specifier 3, stripeFetch 10, captureException 14), and a runtime-independent discriminator for the type-only change — the ESZIP retains the TypeScript source, so 'SupabaseClient' ×3 in the served bundle (0 in origin/main, 2 in the gate) proves the new source is live; ezbr movement recorded as observation only. D pre-deploy PASS on delete-account 23:12Z: JWT True value-approved (destructive, user-scoped action must carry the caller's token); the new dependency verified against production by signature and grant — `public.account_deletion_blockers(p_user_id uuid) returns table(kind text, ref_id uuid)`, SECURITY DEFINER, search_path=public, EXECUTE service_role only; call site `service.rpc('account_deletion_blockers', { p_user_id })` on the service-role client; `check_rate_limit` present with matching parameters; readPendingObligations returns 'unavailable' on error/catch and never blocks the request (OR-17 preserved). Item for C's compatibility pass: additive response fields `pending_obligations` / `obligations_check`. Deploy 7: full log two uploads (index.ts, _shared/sentry.ts); deployed-source comparison 2/2; check_download.sh set-equal both ways, index 67385838… (= D's reference), sentry e41fd1f8…, no unexpected file. Standing invariants (D 23:12Z) unmoved: markers 568, listing sold, money 23/0/0/0 of 57, alerts 15/2, ack 0, cases open 19, alert_delivery_enabled false, ledger 160; inventory 48/37/37/40, stripe-webhook 42, create-connect-account 35.
- **DEPLOY 7 D PASS (23:14Z) → DEPLOY 8 notify-transfer (A 23:15:28Z) — v7→v8, verify_jwt True (asserted), ezbr 3099c340…→eefb7060…; PASS on A's checks, D PASS pending.** D on deploy 7: served bundle 688,419 B (sha256 71d91238…), exactly two modules; positive controls (index specifier 4, captureException 15, request_account_deletion 6); new-only tokens present (account_deletion_blockers 9, readPendingObligations 4, pending_obligations 6, obligations_check 4) with the control that all four are 0 in origin/main's source; live-state note: kernel.identity_ext has 0 DELETION_PENDING identities, so the new obligations read is inert in practice today (blast radius zero). D pre-deploy PASS on notify-transfer: v7 / 3099c340… / True = rollback set; gate index 72694644… = D's reference; closure 1 (deno std + supabase-js only); diff read: the identical type-only pair; pre-commitment restated for this function (ezbr discriminates nothing; version 7→8, index bytes and the 'SupabaseClient' token — 0 in origin/main, 2 in the gate — are the discriminators). Deploy 8: full log one upload (index.ts); deployed-source comparison 1/1; check_download.sh set-equal both ways, index 72694644…, no unexpected file. Standing invariants (D 23:14:48Z) unmoved: markers 568, listing sold, money 23/0/0/0 of 57, alerts 15/2, ack 0, cases open 19, alert_delivery_enabled false, ledger 160.
- **DEPLOY 8 D PASS (23:18Z) → DEPLOY 9 send-push (A 23:19:20Z) — v21→v22, verify_jwt True (asserted), ezbr fd0b1ade…→63dd3c47…; PASS on A's checks, D PASS pending.** D on deploy 8: served bundle 359,038 B (sha256 5d0b5020…), one module, `_shared` absent from the whole bundle, 'SupabaseClient' ×2 vs the 0/2 control; method note: the ESZIP roots at the function dir when there are no ../_shared imports, so D's prefixed-specifier regex returned empty — an artifact distinguished from a finding only by the positive controls (vacuous-check class, instance 5). D pre-deploy PASS on send-push: v21 / fd0b1ade… / True = rollback set; gate index 20a075bd… = D's reference; closure 1; env reads unchanged (SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, EXPO_PUSH_URL), no enable flag; dormancy established precisely — the b2 trigger is `payload.kind === 'push_token_challenge'` (not the presence of challenge_id) and none of the three callers sends a top-level kind (D withdrew its own false alarm: the two notify-report hits were `p_kind` in the claim RPCs); the two challenge RPCs verified in production by signature and grant (notify.get_push_token_challenge(uuid) → jsonb; notify.record_push_token_challenge_delivery(uuid,text,text,text) → jsonb; SECURITY DEFINER, search_path '', EXECUTE service_role only; call sites match argument-for-argument through the notify-schema client). Deploy 9: full log one upload; deployed-source comparison 1/1; check_download.sh set-equal both ways, index 20a075bd…, no unexpected file. **Finding (A 23:18Z, D confirmed): PostgREST exposed schemas are `public,graphql_public,kernel,ops` — `notify` is NOT exposed.** Consequences, all 'present but inert', none a regression or blocker: (1) 096–099 native dispute handling unreachable (nothing imports it); (2) send-push's b2 challenge path dormant twice over; (3) **139's report-delivery dedupe**: the gate notify-report calls notify.claim_report_delivery / release_report_delivery (139, manifest line 12) through a `.schema('notify')` client — refused while unexposed; the code is fail-OPEN (`claim failed, sending anyway`; release only when `claimHeld`), so v10 = v9 delivery behaviour + one warn per invocation. Non-exposure was the documented posture (GO_NO_GO L11; NOTIFICATION_BATCH_1_PLAN.md:72) → design gap in 139's edge path, not a deployment error. Exposing notify widens the API surface for every role — owner's stop-and-ask class, not authorised tonight; D is putting all three to the owner. Standing invariants (D 23:18Z) unmoved: markers 568, listing sold, money 23/0/0/0 of 57, alerts 15/2, ack 0, cases open 19, alert_delivery_enabled false, ledger 160.
- **DEPLOY 9 D PASS (23:21Z) → DEPLOY 10 notify-report (A 23:22:33Z) — v9→v10, verify_jwt True (asserted), ezbr d549929e…→e9057fe0…; PASS on A's checks; D PASS + full standing-set re-read pending. ALL TEN REVIEWED FUNCTIONS NOW DEPLOYED FROM 5b255838.** D on deploy 9: served bundle 684,474 B (sha256 734f5c39…), positive controls (index 3, push_tokens 2, exp.host 2), b2 code present and dormant (push_token_challenge 13, get_push_token_challenge 4, record_push_token_challenge_delivery 4), `_shared` absent. D pre-deploy PASS on notify-report: v9 / d549929e… / True = rollback set; gate index e6b23ad4… = D's reference; set 2; controls for the post-check pre-established (ops_alert 0→6, claim_report_delivery 0→1, incident_seq 0→2); capture note: v9 held index.ts only (no sentry import), so 1→2 and a rollback restores single-file v9. **D's corrected framing of the alert-delivery safeguard (replaces 'one belt'):** after deploy 10, delivery of the 15 firing alerts requires BOTH a manual invocation of ops.dispatch_alerts (nothing schedules it — cron.job has no reference; no function source other than itself mentions it; run_all_detectors does not call it — confirmed against production) AND the switch on (ops.setting_bool('alert_delivery_enabled', false) is the dispatcher's first statement; missing setting defaults false — fail-safe); the edge also requires INTERNAL_CRON_SECRET or the service-role key with verify_jwt on top; and the EMAIL channel is independently off — D read the 24 configured function secret NAMES (no values): RESEND_API_KEY present, EMAIL_ENABLED ABSENT, so `?? 'false'` resolves off. If both conditions were met, admin push would fire; email would still be off. Scoping: ops_alert leaves claimKey null (gate line 280), so the notify-exposure finding reaches report events only, not alerts. Deploy 10: full log two uploads (index.ts, _shared/sentry.ts); deployed-source comparison 2/2; check_download.sh set-equal both ways, index e6b23ad4…, sentry e41fd1f8…, no unexpected file. Added STOP (D): any ops.alert gaining delivered_at or notify_request_id.
- **POST-DEPLOY-10 STANDING SET + INVENTORY (A 23:23Z; D PASS pending).** Standing set 23:23:03Z: switches alert_delivery_enabled=false / refund_resolution_detector_enabled=false / refund_execute_enabled=false / detectors_enabled=true; ops.alert 17 total, firing 15 / recovered 2, delivered_at set 0, notify_request_id set 0, acknowledged 0, firing-and-undelivered 15; cron.job 24, 0 referencing dispatch_alerts; cases open 19 / resolved 2 / 21; markers 568 (latest 22:46:04Z), one distinct error_message; listing f499dc79 sold; money 23/0/0/0 of 57; ledger 160 (147 row present); net queue 0; `get_unsettled_payments(50)` 0 rows; sweeps 23:14–23:22 (five runs) and detector 23:15/23:20 all succeeded. **Inventory (Management API 23:24Z), all ten as expected and ACTIVE:** create-payment-intent v48 T, confirm-payment v37 T, confirm-and-release v37 T, enforce-transfer-expiry v40 T, stripe-webhook v42 F, create-connect-account v35 T, delete-account v22 T, notify-transfer v8 T, send-push v22 T, notify-report v10 T; out-of-scope untouched: auto-finalize-auctions v18, credential-sign v1, door-manifest v1, door-session v1. Signing monitor: cron job 27 `monitor-signing-key-invariants` [23 5 * * *] ran 2026-09-23 05:23:00Z and 2026-09-22 05:23:01Z, cron status succeeded — the invariant RESULT is read separately (cron status is not the result). C handed the agreed combined app compatibility checks (final production state; read-only; delete-account additive fields and send-push contract added explicitly).
- **STEP 3 D PASS (23:24Z) — ALL TEN DEPLOYMENTS VERIFIED BY BOTH SESSIONS; SIGNING MONITOR RESULT (A 23:26Z, D check pending); RELEASE NOT COMPLETE — VERIFICATION WINDOW OPEN.** D deploy 10: served bundle 401,738 B (sha256 42f94ddc…), two modules (`_shared` ×7), positive controls (index 3, captureException 14, admin_users 6), new-only tokens vs 0-in-origin/main (ops_alert 9, claim_report_delivery 2, release_report_delivery 2, incident_seq 4, SupabaseClient 3); D inventory of all fourteen functions matches A's; D standing set 23:23:58Z: ops.alert 17, 15 firing / 2 recovered, acknowledged 0, delivered_at 0, notify_request_id 0, queued_at 0, notify_attempts 0 — nothing delivered, queued or attempted; cases 21/19/8; money 23/0/0/0 of 57; markers 568 frozen since 22:46:04Z across eighteen further successful sweeps; listing sold; switches false/false/false/true; zero cron jobs and zero function bodies referencing dispatch_alerts; ledger 160; net queue 0. **Signing monitor:** cron job 27 `monitor-signing-key-invariants` ran 2026-09-23 05:23:00Z (after 133) — succeeded, return '1 row', 0.063 s (09-22 and 09-21 likewise); the function records only violations (kernel.admin_audit 'signing_key.invariant_alert' + notify-report post), so A replicated its predicates read-only: monitor enabled (v2), total 1 / scoped 0 / active_global 1 / rotating 0 / revoked 0, fingerprint 'match', max_not_after equal to expected, would_alert false; corroborating absence: 0 signing audit rows (kernel.admin_audit demonstrably retains — its rows date back to 2026-09-10 — and 'signing_key.invariant_alert' is exactly what the function writes on a violation, so this zero is meaningful) → **ok on two legs: the audit-table absence and the predicate replication**. STRUCK per D (23:30Z), not support: 'ops.alert signing-related: 0' (the monitor never writes ops.alert; its egress is a notify-report post) and 'net._http_response with signing_invariant in 72 h: 0' (that table retains ~6 h; a zero for a 05:23Z event is a purge artifact — retention measured by both sessions: D oldest row 2026-09-23 17:28:01Z at 23:27:42Z, A oldest row 17:30:01Z at ~23:30Z; the two values differ because the table is a rolling window read two minutes apart, not because either mis-measured; both give the same conclusion. kernel.admin_audit matched exactly: 3 rows, oldest 2026-09-10 19:59:17Z, 0 signing/invariant rows) — vacuous-check class instances 5 and 6 (A's second and third). D reproduced the predicate replication independently (one key, global, active, ES256, not_after null). The 2026-09-24 05:23Z run is the second post-133 data point, to be checked via admin_audit + predicates only. **Outstanding before 'complete':** C's app compatibility checks (handed 23:24Z; explicit items: delete-account additive fields, send-push contract); the 2026-09-24 signing run; owner decisions on the three present-but-inert items (native dispute wiring; b2 challenge path; 139 dedupe — all tied to notify not being PostgREST-exposed, an owner stop-and-ask configuration). **Open, non-blocking:** 147 rollback never exercised against production; pg_net ~3% 'cron succeeded, POST never completed'; ops case 650e7344 watched by nothing; R2 relabel-guard options; PR #91 merge into the gate branch (records the applied 147) still to do — never to main without the marker.
- **CLOSE OF THE 2026-09-23 SEQUENCE (A + D, 23:35Z).** D's witness role discharged; both sessions hold the identical open list. What made the night safe, recorded for the consolidated write-up: not the agreements but the disagreements — A's challenge on the LIKE widening (would have silenced the refund path); D's file count of 5 (stopped the batch on D's own wrong expectation); A's timing correction on the monitor run; D's controls catching A's bash loop and A's two vacuous absences. Six vacuous checks between the two sessions, none reached the owner as a finding. Window open: C's checks; the 2026-09-24 05:23Z monitor run (admin_audit + predicates only). Owner items: notify exposure / three shipped-inert features; PR #91 merge into the gate branch; the five register items.
- **C'S POST-DEPLOYMENT COMPATIBILITY GATE — PASS 7/7 (C, 2026-09-23 ~23:40Z).** Method and limits as stated by C: SOURCE-derived at the deployed refs — edges at gate 5b255838, DB shape = the 24-file RC set at 5b255838 + 147 (C used a77d2b8d; the applied blob at 2bf67af9 differs from it by header comments only — 0 non-comment diff lines, function text byte-identical per D — so the derivation carries), clients Build 9 = 47400911 (tag re-resolved) and Build 13 = 3c67dfc9 (from A's record); NO live production query (prod parity with those refs rests on A's and D's witnessed reads); every grep/extraction re-run this session. Results: (1) 147 blast radius — one CREATE OR REPLACE FUNCTION, no DDL/grants, zero client references; (2) RPC set + argument names 12/12 against the last-writer definitions in LC_ALL=C order (reserve_buy_now, complete_auction_payment, mark_listing_sold, buyer_dispute_transfer with its DEFAULT NULL args, ensure_transfer_exists, mark_transfer_sent, set_transfer_delivery_info, mark_transfer_viewed, finalize_auction, cancel_listing, can_create_listing, get_profile_trust_stats), 147 touches none; (3) table/column selects PASS by derivation (no schema delta; the active→sold correction is a value both builds handle by design); (4) client-invoked edges — create-payment-intent, confirm-payment, confirm-and-release, create-connect-account, delete-account — request and response shapes matched field for field at 5b255838; (5) delete-account additive fields invisible to shipped clients (only call site posts {} and reads parsed?.error; success flow unchanged); (6) send-push contract unchanged, b2 keyed on kind = 'push_token_challenge', zero client occurrences of send-push or the kind; (7) full-chain witnesses for checkout and transfer matched at the deployed sources. Nothing executed anywhere; source read only. **Window item 1 closed. Remaining: the 2026-09-24 05:23Z signing-monitor run.**
- **WINDOW ITEM 1 CLOSED ON ALL THREE SIDES (23:45Z).** C re-resolved 2bf67af9 locally and confirmed the 147 file's non-comment text equals a77d2b8d's (69 = 69 lines after comment stripping); backlog updated (057d3b7c). D confirmed C's two explicit items from its own read of the client source: delete-account has exactly one call site (app/settings/index.tsx:143, body {}), success path reads parsed?.error alone (line 159) then signOut + navigate — the additive fields are read by nothing and the SDK does no strict-shape validation; send-push / push_token_challenge / challenge_id each 0 in client source against a positive control (`supabase.functions.invoke` = 9 in the same run). D restated the derivation chain: a77d2b8d function text = 98fb4063's (md5 cef39ff4…, 6,074 B) and the migration blob is the same object (0898a84f…) at 98fb4063 and 2bf67af9. Remaining window item: the 2026-09-24 05:23Z signing-monitor run.
- **OWNER CLOSING INSTRUCTION (2026-09-24 ~02:20Z) — ITEM 3 CORRECTION: the three shipped-inert features do NOT all depend on exposing the notify schema.** A's earlier record ('all three tied to notify not being exposed') is withdrawn; each traced independently from the gate source (A 02:25Z): **(a) 096–099 native dispute handling** — supabase/functions/stripe-webhook/native-dispute.ts (+ native.ts) is imported by nothing; the entrypoint index.ts imports only _shared/sentry.ts and _shared/stripe.ts; the module keys on payments mode 'native_primary' (093). Dependency: CODE WIRING — an import and a dispatch in stripe-webhook's entrypoint (plus the native-primary ticketing arm being in use). No relation to notify exposure. **(b) send-push b2 proof-of-possession path** — two dependencies, both unmet: (i) a CALLER: the challenge is posted by the database (135 `notify.issue_push_token_challenge` → net.http_post to /functions/v1/send-push with kind 'push_token_challenge'), which is invoked only from `public.register_push_token` (135, contract v3) — Build 9 (47400911) and Build 13 (3c67dfc9) never call that RPC; both upsert public.push_tokens directly (src/hooks/usePushToken.ts:69–84), and those direct writes remain permitted after 128/131/135 (128's guard raises only when a client writes device_secret_hash; 131's row guard raises only in the credential-change epoch case and otherwise stamps session_id; 135's guard covers DELETE) — so no shipped client triggers a challenge; the RC client (src/lib/push/registerToken.ts at 5b255838) would; (ii) once posted, send-push's challenge handler calls notify.get_push_token_challenge / notify.record_push_token_challenge_delivery through a `.schema('notify')` client → needs notify PostgREST-exposed OR public wrappers / a different access path. **(c) 139 report-delivery dedupe** — depends solely on notify exposure (or public wrappers for claim/release_report_delivery; none exist); the edge is fail-open so production runs with v9 behaviour. Only (b-ii) and (c) involve exposure; (a) and (b-i) are code/client work. No configuration change made or authorised.
- **2026-09-24 02:30–02:50Z — CLOSING INSTRUCTION PROGRESS (A).** (1) Monitor: the run to verify is 2026-09-24 05:23:00Z (cron job 27, `23 5 * * *` UTC); production clock at D's read 02:29:39Z, last run still 2026-09-23 05:23:00.322Z — the window stays OPEN, no PASS exists; A's harness one-shot wakeup armed for 05:27Z (01:27 EDT), D's agent-side one-shot for 05:26Z; both check cron.job_run_details + kernel.admin_audit + predicate replication only; no manual trigger. (2) PR #91 preconditions (A + D independently): OPEN draft, base release/production-gate-20260918 (tip 5b255838, which does NOT contain the migration — the reconciliation is real), mergeable CLEAN, all required checks pass, head 2bf67af9 blob 0898a84f… = applied blob (sha256 c0907584…, 9,950 B; D re-derived the function body md5 06ef87b3… = production prosrc; the 5,746 vs 5,734 difference is octets vs characters, 12 multi-byte chars); no deployment on merge: Supabase branching has only the default branch with git_branch '' (A: list_branches; D independently), no GitHub workflow deploys on non-main pushes (ci.yml only), Vercel projects snatchit-web and snatchit-admin show no live production deployment (`live: false`); a Vercel PREVIEW build of the gate branch will occur as it does for every branch push (SSO-protected, not production) — disclosed. D's flag adopted: the PR title 'DO NOT MERGE' was placed for the hand-apply-first + AUTODEPLOY-1 reasons, both now spent; it will be retitled with the reason recorded immediately before the merge, after D's PASS. (3) Inert-item traces corrected and corroborated by D from production: (a) native dispute — edge import + redeploy; notify irrelevant; DB side substantial (kernel.dispute_native 0 rows; record/resolve/mark_dispute_native; public.disputes; ops.detect_disputes); **side finding: kernel.resolve_dispute_native grants EXECUTE to authenticated but NOT service_role, the opposite of its two siblings — decide before wiring**; (b) b2 — three blockers: no caller sends the kind (0 in edges and client), notify unexposed, and notify.push_token_challenges has 0 rows with no client calling any producer; exposure alone changes nothing; (c) 139 dedupe — the ONE item exposure would activate, which makes exposure a behaviour change (a dedupe path going live) needing its own review, not a config toggle. Timing correction (D): 02:24→05:23 is 179 min, not 181. C deliverables written: docs/release/PAYMENT_STATE_WORDING_TABLE_20260924.md and docs/release/V3_REVIEW_NOTES_20260924.md (listingSummary PASS with two notes; FlowController: do not build as proposed).
- **PR #91 MERGE HELD ON THE 'NO DEPLOYMENT' PRECONDITION (A + D, 2026-09-24 ~03:05Z).** D's challenge accepted: A's statement that the merge 'will produce a preview build exactly as every push did' was inference from preview behaviour, which CLAUDE.md's AUTODEPLOY-1 rule forbids for a deployment path (071 reached production through an unread setting). The Vercel Management API payload omits the production-branch setting for snatchit-web, so the setting itself has NOT been read. Supporting evidence only, recorded as such: every production-target deployment of snatchit-web (latest 2026-09-01) came from `feature/web-accounts-foundation`, whose own docs commit calls it the Vercel production branch; snatchti.com and snatchit-web.vercel.app are production-bound with no branch override; the five gate-branch merges of 2026-09-22 produced no production-target deployment; snatchit-admin's production branch is admin/operating-console (git domain + D's standing rule). Risk profile if the setting were wrong: snatchti.com is a custom domain outside the SSO scope, so a production deploy there would be public. Decision: the merge waits for the owner's visual read of snatchit-web's production branch (or an explicit owner decision to leave PR #91 unmerged — no deadline; production is correct and the migration is applied). Supabase side remains conclusive (single default branch, git_branch '').
- **OWNER INSTRUCTION 2026-09-24 ~02:50Z (second closing instruction) — STATUS.** Monitor verification kept as scheduled (run to check: 2026-09-24 05:23:00Z; latest run still 2026-09-23 05:23:00Z succeeded at the 02:52Z read; no rerun). PR #91 kept HELD — see the Vercel evidence entry: project **snatchit-web** (`prj_UjnXiY7r3PV4NCMH70UpdWT9rvfL`, team gnvprod-5449s-projects; custom domain snatchti.com outside the SSO scope) — evidence still needed is the CURRENT 'Production Branch' value in Project → Settings → Git, read visually; also whether 'Ignored Build Step' / preview-deployment settings would suppress a preview build of the gate branch, because the merge gate's 'triggers no deployment' condition otherwise needs the owner's ruling that an SSO-gated preview (target null, no custom domain) is not a deployment for this purpose; project **snatchit-admin** (`prj_o17cASVVqqyGKPUtiklJRvAMVgNB`): production branch evidenced only by its git domain and D's standing rule (`admin/operating-console`) — same visual read applies; no vercel.json exists in web/, admin/ or root, so no repo-level branch condition can stand in for the dashboard. Reused evidence that applies to the same projects: SSO protection `all_except_custom_domains` (both, API); deployment history (supporting only): all production-target deployments of snatchit-web from `feature/web-accounts-foundation`, none from the gate branch. Distinction kept explicit: **the production fix (147) is applied and verified; #91 is source-history reconciliation only.** Two findings recorded in docs/release/FINDINGS_20260924_DISPUTE_GRANT_AND_OPS_CASE.md: F-1 `kernel.resolve_dispute_native` — `authenticated` grant is by design (platform-role-gated, PFA-31 parked fail-closed, always raises, zero mutation, no callers) → no fix; F-2 case 650e7344 — a synthetic G7 acceptance probe of type `manual` ('safe to dismiss'), never detector-managed by design → bounded fix is one console dismissal by D/the owner, not performed here. C's source-only reviews continue independently of #91.
- **D RETRACTS BOTH ITEMS AS FINDINGS (03:30Z) — A's assessment concurs; record aligned.** F-1 `kernel.resolve_dispute_native`: grant correct as is (house pattern; PFA-31 zero-mutation park; must NOT be changed); the substantive fact is recorded as the **third independent reason** the native dispute feature is inert (edge import missing; resolution parked under PFA-31; exposure irrelevant). F-2 case 650e7344: D's own G7 acceptance probe; 'manual' is never detector-produced; 19 open = 5 dispute_open + 8 paid_unsettled + 3 report_review + 2 refund_pending + 1 probe; dismissal is an ops-console action, not urgent, not performed. **Vercel scope corrected to TWO git-linked projects** (both root-directoried from this repo; no vercel.json anywhere): snatchit-web and snatchit-admin; `snatchitwebapp` is out of scope (deployments carry empty meta — not git-linked; last activity ~2026-05). Per-project supporting evidence (history, not the setting): snatchit-web — ten production-target deployments, all from `feature/web-accounts-foundation`; snatchit-admin — four most recent production-target deployments from `admin/operating-console`, all CANCELED (git-guard cancellation / preview branch-tracking change), two older READY with empty meta (CLI deploys). **Dashboard evidence needed, for EACH project:** Settings → Git → Production Branch value; Settings → Domains → no domain or alias assigned to `release/production-gate-20260918`; Deployment Protection — asymmetric risk: snatchti.com is a custom domain outside snatchit-web's SSO scope; snatchit-admin has no custom domain.
- **VERCEL DASHBOARD EVIDENCE (owner, 2026-09-23 ~22:58 EDT = 2026-09-24 ~02:58Z) + A's read-only build inspection (03:05Z).** **Verified from the setting itself, project snatchit-web:** Environments → Production tracks `feature/web-accounts-foundation` (domains snatchti.com +3); Preview = Branch Tracking ENABLED for 'All unassigned git branches', no custom domains; no custom environments. Recorded as: production-branch check VERIFIED for snatchit-web. NOT recorded: preview deployment as disabled; the merge gate's 'triggers no deployment' condition as satisfied. Still needed: snatchit-admin's Production branch / Preview tracking / Domains; the Preview environment-variable scope (owner providing); optionally Build and Deployment → Ignored Build Step for both. **What a merge to `release/production-gate-20260918` would do (source, gate 5b255838):** with Preview tracking on all unassigned branches, Vercel would create a PREVIEW deployment of that branch for snatchit-web (and for snatchit-admin if its Preview tracking is the same — unverified), each running plain `next build` in its dashboard-configured root (`web/`, `admin/`; no vercel.json, no prebuild/postinstall hooks, no ignore script in the repo). **Could that build or preview access or modify production?** Neither app reads any elevated credential: web/ reads only NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY, NEXT_PUBLIC_SITE_URL, the Stripe publishable key, Sentry DSNs, NODE_ENV, VERCEL_ENV; admin/ reads the public URL/anon key pair (+ SUPABASE_URL/SUPABASE_ANON_KEY), site URL, env label; `SUPABASE_SERVICE_ROLE_KEY` / service_role appears NOWHERE in web/ or admin/. So: (i) at BUILD time the only possible database contact is anon-key READS during pre-render (pages carry no dynamic/revalidate exports; the server client uses cookies, which forces request-time rendering; the one API route is force-dynamic) against whatever host the Preview env scope names; (ii) at RUNTIME a preview is served on *.vercel.app under SSO (`all_except_custom_domains`; previews have no custom domain) and can only act as anon or as the logged-in user under RLS — the same capability the live site already exposes; no migration, edge deploy or CI deploy is triggered (ci.yml: tests only, 'no secrets'; Supabase git binding empty). Conclusion: the merge would BUILD a preview; it cannot MODIFY production beyond user-level RLS paths; whether it could READ production at build/runtime depends solely on the Preview env scope's Supabase host (pending screenshot). #91 stays HELD until the owner rules on that condition.
- **VERCEL — OWNER'S SECOND DASHBOARD READ (snatchit-web, 2026-09-24 ~03:2xZ) + SOURCE CHECKS COMPLETE (A; D corroborating).** Recorded exactly as given: Production tracks `feature/web-accounts-foundation`; Preview tracking enabled for all unassigned branches; Preview project variables = Sentry, the Stripe publishable key, SITE_URL only; NO Supabase URL or anon key in Preview; no shared variables linked. Not inferred: that missing variables guarantee isolation. **Source facts that establish behaviour when the Supabase variables are absent:** (1) both apps derive SUPABASE_URL/ANON from NEXT_PUBLIC_* only (`?? null`; web/src/lib/env.ts:6–7, admin/src/lib/env.ts:8–9); (2) both throw AT MODULE LOAD when NODE_ENV=production and any of NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY / NEXT_PUBLIC_SITE_URL is missing ('Missing required environment variables … Refusing to start', web env.ts:22–43, admin env.ts:26–39) — `next build` runs with NODE_ENV=production and env.ts is imported by layout.tsx, robots.ts, sitemap.ts, the listing page and the API route, so a Preview build of web with the current Preview scope FAILS at build; the same guard is in admin; (3) the fixture path (`hasSupabaseEnv` false → FIXTURE_LISTINGS, listings.ts:75/122/135) is therefore reachable only in development, never in a Vercel build; (4) the one hardcoded production tie — `STORAGE_BASE_URL` falls back to `https://hqycwntpfoztoinemqns.supabase.co/storage/v1/object/public` (web env.ts:91, D's finding) — is read-only public-bucket image URLs for fixture data and cannot execute in a production-mode build because (2) throws first; `SUPABASE_HOST` in both next.config.ts files is the image-optimisation allowlist (config, no access); (5) no `service_role`/SUPABASE_SERVICE_ROLE_KEY anywhere in web/ or admin/ (A + D, with controls); (6) correction per D: `process.env.SUPABASE_URL`/`SUPABASE_ANON_KEY` occur once each under admin/ but only in `admin/scripts/acceptance/gate-probe.mjs` (acceptance tooling), not in the app runtime — the admin app reads NEXT_PUBLIC_* only; (7) D confirmed build-time performs no database access (15 force-dynamic admin pages + the web API route; every Supabase path is cookie-bound; no generateStaticParams; no hooks/scripts) and that ci.yml/security.yml/migrations-guard.yml reference no production ref or secret. **Deployment-outcome evidence (behaviour, supporting only):** Vercel's preview deployments for PR #91's own branch (a77d2b8d, 98fb4063, 2bf67af9 — the exact commits a merge would carry) are all state CANCELED, target null — consistent with an automatic ignored-build-step (no changes under the project root directory), not read from the setting. **Conclusion for the merge condition:** a merge of #91 (three files under supabase/) into the gate branch would create a preview deployment RECORD per git-linked project that is either cancelled before building (if the Ignored Build Step is the automatic root-directory skip) or fails at the env assertion with no runtime and no database contact; a running preview cannot exist under the read Preview scope; production is untouched either way. Register: D's regex `\s` under git-grep ERE returned a clean zero (instance 10, uncatchable by its own control) and a scope-too-narrow zero on the cookie-bound client (instance 11).
- **#91 MERGE CONDITION — STANDING ANALYSIS, NOT A PROPOSED ACTION (A + D, 2026-09-24 ~03:45Z).** D relays that the owner chose to read snatchit-admin's settings first (Production Branch; Preview Branch Tracking; whether the Preview variable scope holds a Supabase URL or anon key) rather than accept an unknown; A's recommendation to the owner stands as analysis only and the merge stays HELD pending the owner's own word. Two independent, non-exclusive reasons no preview of a #91 merge could RUN: (i) HYPOTHESIS, evidence only — an automatic root-directory ignored-build-step: PR #91's three commits (supabase/ only) and the recent docs-only commits all produced CANCELED, target-null snatchit-web preview records, consistent with 'skip when no changes under the project root'; the Ignored Build Step field itself is unread and D is asking the owner for it per project as a specific new fact; (ii) SOURCE FACT — both apps throw at module load in production mode when the Supabase variables are absent, and the read Preview scope has none, so any build that did start would fail before any data code. The outcome (no running preview, no database contact, production untouched) holds if either explanation is wrong. Remaining specific facts to read: snatchit-admin Production Branch, Preview Branch Tracking, Preview scope Supabase variables; Ignored Build Step for both projects.
- **VERCEL — OWNER'S THIRD DASHBOARD READ (captured 2026-09-23 23:29–23:31 EDT = 2026-09-24 03:29–03:31Z) — MERGE CONDITION EVIDENCE COMPLETE FOR BOTH PROJECTS.** **snatchit-admin:** Environments → Production tracks `admin/operating-console` (snatchit-admin.vercel.app +2); **Preview: Branch Tracking DISABLED**; Development: CLI; no custom environments; Environment Variables (Project, Preview filter): 'No Environment Variables Added'; Build and Deployment → Ignored Build Step: Behavior Custom, command `test "$VERCEL_GIT_COMMIT_SHA" != "ab3e17f1a36e8c78c9fce31ee0b4fa…"` (truncated in the screenshot — the full pinned SHA is NOT recorded and must not be invented; Preview tracking being disabled is the relevant control). **snatchit-web:** Production `feature/web-accounts-foundation` (previously verified); Preview tracking enabled (all unassigned branches); Build and Deployment → 'Include files outside the root directory in the Build Step' Enabled; 'Skip deployments when there are no changes to the root directory or its dependencies' Enabled; Ignored Build Step, Project Settings: Behavior Custom, command `if [ "$VERCEL_ENV" = "production" ]; then exit 1; else exit 0; fi` — the dashboard defines exit 1 = build, exit 0 = skip, so every non-production (preview) deployment of this project is SKIPPED by configuration; the Production Overrides command field is blank (a separate field). **Correction recorded:** the configured preview outcome for a #91 merge is a SKIPPED deployment record, not a failed Next build; the env-guard throw (source fact) remains a second, independent layer that would apply only if a preview build ever ran. The root-directory-skip hypothesis is superseded by the read command (and the 'Skip deployments' toggle is also Enabled). **Consequence of merging #91 into the gate branch:** snatchit-admin creates no preview (tracking disabled); snatchit-web creates a preview record that the Ignored Build Step exits 0 on → skipped/cancelled, never built, never served; Supabase applies nothing (git_branch ''); CI runs tests only. **Owner's decision:** after D's PASS on this assessment AND the monitor PASS, A merges #91 into release/production-gate-20260918 only — reviewed content and required checks must still match; nothing reapplied; no settings changed; never main — then verifies the resulting source equals applied 147 and inspects the resulting Vercel activity, distinguishing a skipped/cancelled record from a built, running preview.
- **D MERGE-CONDITION PASS (2026-09-24 ~03:45Z), with its evidence limit stated: the owner's four screenshots were not delivered into D's session; D verified the two load-bearing claims by routes independent of A.** (1) Exit-code semantics from Vercel's ignoreCommand documentation: exit 0 ignores the build, exit 1 continues it — so snatchit-web's `if [ "$VERCEL_ENV" = "production" ]; then exit 1; else exit 0; fi` builds only production and ignores every preview (A's reading confirmed from the vendor). (2) snatchit-admin deployment records: 11 of the 12 most recent are target-null previews, ALL state ERROR, all from feature/venue-native-and-product-v2 around 2026-09-08; the newest deployment of any kind is 2026-09-08; zero records in ~16 days including tonight's pushes — exactly what Preview Branch Tracking DISABLED predicts. **Upgrade:** those ERRORed admin previews are the env-guard throw observed on the platform (admin has no Preview variables and no fixture path), turning the source finding into demonstrated behaviour. Per project, two independent mechanisms each: web — production branch ≠ gate, previews ignored by configuration (8 recent CANCELED records corroborate), env guard behind; admin — production branch ≠ gate, preview tracking disabled (16 days of zero records corroborate), env guard demonstrated. Admin's truncated ignore command deliberately not relied on (visible prefix ab3e17f1 matches the console's recorded go-live commit — consistency note only). **Post-merge checks (A + D):** resulting gate source = applied 147 blob; snatchit-web shows a skipped/cancelled record, not a built running preview; snatchit-admin shows NO new deployment record at all; Supabase ledger unchanged at 160. Still required before the merge: the 05:23Z monitor verification and D's monitor PASS.
- **OWNER INSTRUCTIONS 2026-09-24 ~03:49Z / ~04:00Z / ~04:10Z — PR IDENTITY, D'S EVIDENCE BOUNDARY, SANDBOX READS (A).** (1) **PR identity re-verified before any edit or merge** (the owner saw one of A's links rendered as `SnatchIt-app/re-verify`): GitHub API `repos/SnatchIt-app/snatchit/pulls/91` → base repo `SnatchIt-app/snatchit`, head repo `SnatchIt-app/snatchit` (not cross-repository), head `fix/sweep-manual-review-exclusion` @ `2bf67af96e5160c64e265686d36e9dd467bc4102`, base `release/production-gate-20260918` @ `5b255838dea3d39561714554a547a6121ab2c8ff`, draft, OPEN, MERGEABLE/CLEAN; every `pull/91` link in A's transcript (117) resolves to `SnatchIt-app/snatchit`; no `re-verify` repository appears in A's output. D confirmed the same fields from its own `gh` read. (2) **Screenshot provenance:** the owner's Vercel screenshots arrived inline in the owner's chat turn and exist nowhere on disk in A's session; they could not be forwarded to D. **The current-setting evidence for both Vercel projects came from the owner's screenshots, as transcribed by the owner and by A.** D's boundary statement, verbatim: "D's merge-condition PASS rests on three things of unequal strength. (1) The current Vercel setting values, as transcribed by the owner and by A from screenshots that were never delivered into D's session — D has not read them and does not claim to have. (2) The ignoreCommand exit-code semantics — exit 0 ignores the build, exit 1 continues it — which D verified directly from Vercel's own documentation, independently of A. (3) The snatchit-web and snatchit-admin deployment histories, which corroborate behaviour consistent with those transcribed settings but do not verify any current setting value; deployment history is evidence about the past, never about a setting's present value. If any transcribed setting value is inaccurate, D's PASS does not survive it." (3) **Pre-merge sequence of record (A + D):** D's 05:26Z read of the 2026-09-24 05:23:00Z monitor run → D PASS or STOP → A marks #91 ready and retitles it in one step, after recording the workflow-run list at the head as a baseline, then stops → D's six-point read (not draft; no "DO NOT MERGE"; head still `2bf67af9…`; base still the gate branch; MERGEABLE/CLEAN or why not; migration blob still `0898a84f…`; no new workflow run) → D's GO → A merges into the gate branch only → A's post-merge checks. The draft state's reason (apply-first ordering in a repository where a merge to main auto-deploys migrations) is spent: 147 applied 2026-09-23 22:46:46Z with D's PASS, and the owner authorised the gate-only merge. (4) **Sandbox reads for C's V3 phone test — done, read-only, recorded in `SANDBOX_D8_READS_20260924.md`:** target `ofaidukbieeekqaboscm` (`snatchit-sandbox`, a different organisation from production) confirmed by ledger 144 / signing keys 0 before any query; **D-8 CLOSED** (`get_my_tickets`: one function, SECURITY DEFINER, `search_path=public, pg_temp`, authenticated yes / anon no, 17-column shape = the client type, ledger row present, `kernel.tickets` 0; body equals the repo's once three comment lines are stripped); fixtures: 3 live listings, all ending by 2026-09-25 02:01:44Z; 0 bids anywhere; no quantity-2 listing; transfers reversed 4 (usable), expired 0, held 0. W1 and W2 traced to their actual side effects and cleanup; F-EXP / F-HELD proposed (two reversible row updates, zero notifications, zero outbound requests, zero job effects); submission gap assessed as material for held, narrower for expired. **Nothing was written to the sandbox. W1, W2 and every fixture change remain owner decisions D1–D6.**
- **SIGNING MONITOR — 2026-09-24 05:23:00Z RUN VERIFIED (A's read, 05:27:08–05:27:18Z, production, read-only; neither the function nor the job was manually invoked — the job fired on its own schedule).** `cron.job_run_details` jobid 27: **2026-09-24 05:23:00.040798Z `succeeded`, "1 row", 43 ms**; the 2026-09-23 05:23:00.322Z run (succeeded, 63 ms) appears in the same query as the positive control. `kernel.admin_audit`: 0 `signing_key.invariant_alert` rows after 05:00Z and 0 all time; 3 rows in total, oldest 2026-09-10 19:59:17Z, which proves the container retains the period. Predicate replication (the 09-23 SQL): monitor enabled true; keys total 1 / scoped 0 / active global 1 / rotating 0 / revoked 0; fingerprint `match`; max_not_after `equal` (not set); **would_alert false**. Sent to D for an independent PASS. D's pre-run state at 05:17:30Z matched. #91 stays held until D's PASS, then the ready-and-retitle step, D's six-point read and D's GO.
- **D: MONITOR PASS (own read 2026-09-24 05:27:56Z), field for field with A's.** Controls: the 09-23 run in the same result set; job-27 row count 20 → 21 between D's 05:20:07Z and 05:27:56Z reads (exactly one firing); return "1 row" (the function returned its jsonb). admin_audit 0 signing/invariant rows all time and since 05:00Z, retention proven by the 2026-09-10 oldest row. Predicates identical to D's 05:17:30Z pre-run capture and the 09-23 verification. Standing set unmoved: markers 568, latest 2026-09-23 22:46:04.980Z; listing sold; transfers 23; payout_attempts 0; payment_refunds 0; alerts 15 firing / 2 recovered, 0 delivered / 0 acknowledged / 0 notify_request_id; cases open 19; alert_delivery_enabled false; ledger 160; 0 cron jobs referencing dispatch_alerts. **The 133-replaced monitor has now run unattended and clean twice, on 2026-09-23 and 2026-09-24: the release window's monitor item is CLOSED.** Wording fix requested by D and applied: the entry above now says the job fired on its own schedule and nothing was manually invoked.
- **PR #91 MERGED INTO THE RELEASE GATE — 2026-09-24 05:31:51Z (A, on D's GO; owner authorisation of ~03:31Z).** Repository and PR identity re-verified through the GitHub API before any edit (`SnatchIt-app/snatchit`, not cross-repo). **Pre-merge baseline (05:27:51Z):**
  - draft, mergeable/clean;
  - all checks pass; the Vercel snatchit-web check read **"Canceled by Ignored Build Step"**, the platform's own statement of the mechanism established earlier from documentation and history;
  - 2 workflow runs at head `2bf67af9`;
  - migration blob `0898a84f` = the applied file (md5 `7decdea1…`, 9950 B);
  - the PR adds exactly 3 files: migration, rollback under `supabase/rollbacks/`, and pgTAP 214.

  **Ready and retitle, 05:29:44–47Z:** the title dropped "DO NOT MERGE" and the body gained a "Merge status" section. The AUTODEPLOY-VERIFIED-OFF line was kept on its own line. **Predicted before acting, from the gate's triggers:** exactly one new run, the Migrations guard firing on `edited`; `ready_for_review` has no trigger. Observed: exactly one, run 35960194194, success at 05:30:07Z; the PR returned to clean.

  **D's seven-point read gave GO:**
  1. not draft;
  2. title clean;
  3. head unchanged and not force-pushed;
  4. base the gate branch;
  5. MERGEABLE/CLEAN;
  6. blob and sha256 read directly;
  7. added by D: the base tip was unmoved at `5b255838`.

  **Merge:** `gh pr merge 91 --merge --match-head-commit 2bf67af9`, producing merge commit `aadf996e298c6733b4b23af4fcbf0efea1f8f6af`, subject "Merge #91 into the release gate: …(147)", parents `5b255838` / `2bf67af9`.

  **Post-merge:**
  - the gate tip carries blob `0898a84f`, sha256 `c0907584…`; exactly the 3 files changed; `main` unchanged at `eadd456a`;
  - the push started one CI run, 35960357963 (tests only, no secrets); its result is recorded below when it completes;
  - Vercel **snatchit-web**: one record `dpl_6e59UooJY87XvGKq5Ngz5xjAJfMQ`, preview, state **CANCELED** (skipped; not built, not running);
  - Vercel **snatchit-admin**: **no record at all** since 05:30Z, with a positive control (the unfiltered query returns records, newest 2026-09-08);
  - production, read-only: ledger **160**, 147 row count 1, `get_unsettled_payments` defn `705953d5…` unchanged, so **nothing was re-applied**; one Supabase branch, `git_branch` "";
  - standing set unmoved: markers 568, latest 2026-09-23 22:46:04.98Z; listing sold; transfers with a Stripe id 23; payout_attempts 0; payment_refunds 0; alerts 15 firing / 2 recovered, 0 delivered / acknowledged / notify_request_id; cases open 19; switches unchanged; cron 24; 0 referencing dispatch_alerts.

  No setting was changed, and nothing was deployed or merged to main. D's independent post-merge verification is pending.
- **Gate CI after the #91 merge: GREEN.** Run 35960357963 (push, `release/production-gate-20260918`, head `aadf996e`), completed 05:34:32Z, conclusion success. All 5 jobs passed: Web build; Migrations apply cleanly (fresh DB); Typecheck / Lint / Unit tests; Admin console; Deno type-check.
- **D: POST-MERGE VERIFIED (own reads ~05:33:52Z) — the release window is CLOSED on both sides.**
  - Source: gate tip `aadf996e` with parents `5b255838` / `2bf67af9`, exactly the commits reviewed; blob `0898a84f`, sha256 `c0907584…`; exactly 3 files changed.
  - **`git merge-base --is-ancestor aadf996e origin/main` is false:** `main` does not contain the merge. That was proved by ancestry, not by a matching sha.
  - Production: ledger 160, one 147 row; standing set unmoved.
  - Vercel asymmetry exactly as predicted from the owner's dashboard read: snatchit-web has one CANCELED preview record; snatchit-admin has **no record at all**, its newest still 2026-09-08, and the query demonstrably sees records.
  - **Hash naming reconciled by D:** md5(prosrc) = `06ef87b3…` and md5(pg_get_functiondef) = `705953d5…`. Both are correct, both unchanged, and they are different strings. From now on every function hash in these records names its metric.
  - Gate CI green, recorded above.
- **F-DISPUTE-SELLERWIN-1 written up with a bounded fix proposal** in `FINDINGS_20260924_DISPUTE_GRANT_AND_OPS_CASE.md`: a selection-only edge change, plus a false "Buyer confirmed receipt" notification on the same transition. **Not implemented**, because payouts are an owner stop-and-ask area. Owner decision.
- **V3 sandbox preview BUILD 23 FINISHED (C's report; EAS not read by A).**
  - EAS `65cb7633-0eca-4314-b135-fd9c90db8214`, iOS preview, internal, SDK 54, commit `9c6c9bf4e6f9c201efe1fe760d2bf6ae12175d7f`, sandbox `ofaidukbieeekqaboscm`.
  - A verified: the commit is on `v3/midnight-app`; the gated payment surface against `e079fcc1` is `signOut.ts` +5 only; `eas.json`, `app.json` and `envGuard.ts` are unchanged since `2619b9e1`.
  - **Not installed, not launched:** the fixture sheet's §0 gate holds, with 1 of its 5 conditions met.
  - **Artifact and branch drift, recorded:** the branch head is `24b021a3`, one commit past the build. It restores the brand red for the Spinner arc in Light (a graphic at the 3:1 bar, not text); C reports both colours clear 3:1. **Device evidence from build 23 applies to `9c6c9bf4`, not to the branch head.** C stopped changing the branch after the build.
  - C parked two items rather than applying them: `text.faint` below 4.5:1 in both appearances, and B's N-2/N-3 design calls.
- **F-DISPUTE-SELLERWIN-1 FIX — DRAFT PR #92 (A, 2026-09-24; owner authorisation: source, tests, reviewable PR only).**
  - **Head and base:** `e2205bbbc1713d03677a16f485df4bbb7c07f3ff`, base the release gate.
  - **Scope:** payout eligibility (Phase 2b (d) seller-win selection, plus the `claim_payout_attempt` hold rule) and the truthful seller notice ("Dispute resolved in your favour"; "Buyer confirmed receipt" only when `buyer_confirmed_at` is set). No manufactured timestamp. The a)+b) selection is byte-identical. The live `confirm-and-release` path now respects holds for a seller-win, as a stated fix. Migration `20260924000000` is registry 148, with guarded rollback.
  - **Evidence:**
    - TDD red first: vitest 12/23, pgTAP 13/43.
    - Green: pgTAP 215 43/43, **fresh replay full pgTAP 5511/5511**, targeted vitest 89/89, full vitest 128 / 2524 (not isolated: C's suite ran concurrently), tsc 0, lint 0/29 (= gate).
    - **CI at `e2205bbb`: all 9 checks pass**, fresh-DB census 32/108/37/38, pgTAP Files=95 / Tests=5517 Result: PASS.
    - Mutation controls, each predicted before running: **12/12 SQL** matched. **Edge: 12/12 final.** The first-round differences (E5, E6, E9, then E11) were investigated: two redundant guards, an unreachable legacy fixture replaced by the real DAY5 B3 shape, and a test coupled to a guard, now fixed.
    - Rollback cycle proved: it refuses on the unfixed DB, restores the pre-148 hashes, 215 then fails the same 13, and re-apply is green.
  - The enumeration of every `buyer_confirmed` reader (server, console, app, web) is in the PR as named follow-ons.
  - **D review pending.**
- **F-LISTING-CRITICAL-TIER-1 (C raised, A verified at source):** the critical risk tier blocks listing creation only in the client. The 119 guard and the RLS insert policy do not read `risk_tier`. Recorded in the findings doc; the fix is an owner decision.
- **Deployed server fact for C (source):** a seller-win (065) already leaves `buyer_confirmed_at` NULL; #92 does not change that. C's client copy fix, option (a), may proceed against current data, with the gated read coming to A.
- **Submission checklist reconciled against Build 23** (`9c6c9bf4`, a sandbox binary, not submittable), with the consolidated owner action list G1–G10 / R1–R3 / E1–E6. Checklist commit `8a080839`.
- **D's independent review of PR #92 (read the diff, not the summary): PASS on 16 criteria, 4 NOT DETERMINED, nothing blocking.**
  - Passed by reading the code: P2 (zero assignments to `buyer_confirmed_at`), P3, P4, P5, P6 and P10 (the diff deletes zero lines, so a)+b) is unchanged), P7, P8, P9, and N1–N6. N1 depends on the added `buyer_confirmed_at IS NOT NULL` conjunct; the blocks are independent IFs.
  - D noted that keying the notice on the resolution transition also covers an already-paid seller-win, which its own criteria had missed.
  - **Not determined by D:** T1–T3 (D reviewed test structure, not outcomes; the mutation results are A's alone); P1 end to end (not run); the full SQL hold predicate for `held_no_end`; the split of refusal-code assertions between suites.
  - **Correction, A's:** an earlier design message to D described a `sellerWinPayoutBlock` helper in `_shared/payout-logic.ts`. It was dropped when the edge test VM's import rule surfaced, and D was not told. It was never in the PR body or the repo. The PR body now names the rule's **three** expressions (query filter, Phase 2b loop, claim authority) and which tests and mutants control each. The misattributed assertion message is fixed at `e73553d2`.
- **D's review of #92, final: 18 criteria pass, 2 not determined (T1–T3 mutant outcomes and P1 end to end: "I did not run them").**
  - Item 3 is resolved: D read the full SQL predicate (migration 110-119) and walked all seven matrix cases against both SQL and JS. They agree, including `held_no_end`, so P7 is fully determined and passes.
  - **Item 4 is withdrawn by D as an error, and recorded at D's request in these terms: "absence asserted from a sample".** D read one block (SW-HOLD) and generalised to the whole file that refusal codes are never checked in JS; `CLAIM[...]` (`toThrow(c.expect)`) and `CLAIM-BYPASS` (`reason 'PAYOUT_HELD'`) check them. **Defence: before writing "never", run the search that could find it.**
  - Register: this is the same class as the vacuous-check instances, in a new form (a sentence, not a command).
  - Independent reproduction of the mutant outcomes is offered by D as a separate job, needing machine coordination and the owner's word.
- **PR #92 CI GREEN at the new head `e73553d2`** (all 9 checks, including the fresh-DB migrations job and the unit tests).
- **C's seller-win client copy, option (a), at `ca27d282`: A PASS on the gated read.**
  - `buyer_confirmed_at` is added to the two transfer selects only. Its value is never rendered; only its presence is read.
  - The gated payment surface is unchanged (`signOut.ts` +5).
  - Copy accepted. Buyer: "Dispute resolved" with no credit to the buyer and no refund implied. Seller: "Dispute resolved in your favour", matching #92's notice.
  - C reports gates 149 / 2699, tsc 0, lint 0/29. It is not in Build 23.
  - **Follow-ons for C:**
    - the "Received" badge (`transferStatusMeta`) and the Bids board label still key on status alone; the Bids fix needs a gated read;
    - after #92 deploys, a held or manual-review seller-win should show the hold or review line instead of "being processed".
- **C's follow-ons at `aee15697`: A PASS on the third gated read** (`buyer_confirmed_at` in the Bids transfer select; value never rendered; gated payment surface unchanged, `signOut.ts` +5).
  - The badge and the Bids board now show "Resolved" (neutral) for an operator's decision. Real confirmations keep "Received".
  - For an operator's decision, the seller payout line follows the payout fields: the hold line, the existing manual-review sentence, or else "being processed".
  - **Optional wording change:** the new held-no-date fallback "…We will tell you when it is released." promises a notification. Delivery depends on a push token, so dropping the second sentence is recommended.
  - Not in Build 23 (`9c6c9bf4`), which still shows a seller-win as "Received" on three surfaces; no replacement build is authorised.
- **C's wording fix at `404bce38` (parent `aee15697`, on `origin/v3/midnight-app`): A PASS, copy only.**
  - Held-no-date fallback is now just "Payout on hold." The dated held line is unchanged.
  - A verified C's reason for not saying "this screen updates": `app/transfer/send/[id].tsx` has no `useFocusEffect` or subscription. It refetches only on `RefreshControl`, and its two `setInterval`s only redraw countdowns.
  - Diff touches 2 files: the send screen (+4/−1) and DR11 in `tests/v3-dispute-resolution-copy.test.ts`. There are no select/rpc/from changes, and `git diff --stat aee15697..404bce38` over the gated files is empty.
  - DR11's predicate discriminates: A evaluated it on both sides. It FAILs on the parent (the promise matched, the new string was absent) and PASSes at `404bce38`. Both slice indices resolve.
  - C's gates are C's report and were not re-run by A: 149 / 2704, tsc 0, lint 0 / 29.
  - Not in Build 23.
- **C's G2 input (auth brand mark), verified by A at source; owner choice S1 added to checklist §8.**
  - Build 23 (`9c6c9bf4`): `src/components/auth/AuthBrandMark.tsx` renders `brand/sn-logo-white.png` untinted. All 230,668 opaque pixels are #FFFFFF. The Light canvas is `#FFFFFF`, and appearance defaults to System. So a phone set to Light shows a blank logo on login, signup and reset. This is verified at source, not on a device.
  - Fixed by `2ffb10a8` (tinted to primary ink), on `origin/v3/midnight-app` only.
  - A correction to C's framing: a sandbox `preview` recut is not G2, which is the `production` build. It is recorded as the separate choice S1.
  - The two §7s are distinct: A's is the submission checklist, `be2a4577`. C and B's phone checklist is `docs/product-v3/V3_PHONE_TEST_CHECKLIST.md` at `629a82ba` on `origin/design/frontend-audit-20260917`, which A resolved and which lists the three dispute commits.
- **A self-correction:** A earlier wrote that the G2 pin "will carry the fix anyway". That overstated it, and C propagated it at `4b983d86` as "never of a release candidate".
  - It holds only if the pinned commit contains `2ffb10a8` and `404bce38`. The first is an ancestor of the second; neither is in `9c6c9bf4`.
  - The G2 row now makes this an explicit pin requirement, which A checks with `git merge-base --is-ancestor`.
- **Owner, 2026-09-24 ~12:00 local: D1–D6 APPROVED exactly as at `7dae4815`**, including D5/D6 (the expired/held
  decision). Execution waits for three things: Build 24 installed, the owner's "go", and A's preflight. The approval is
  recorded as a banner on the sheet; the spec below it is byte-identical to `7dae4815` (diff-checked). D's witness reads
  (7th box) are not in the approval. Production execution and dispute resolution are **not** authorised.
- **D's independent reproduction of #92 (owner-authorised machine window):**
  - edge mutants 12/12 and SQL 12/12 against `predictions.json` (sha256 `dba54f11…`);
  - unmutated baseline 43/43;
  - Q5 = [28,29];
  - D ran in an isolated tree and DB, and left A's evidence files untouched (mtimes checked).
  - Two harness improvements are noted for next time: an unmutated-baseline row, and the ok+fail sum control (43/26).
- **#92 production execution package** (`PR92_PRODUCTION_EXECUTION_PACKAGE_20260924.md`, A): prepared, rehearsed and
  frozen. **Not executed.**
  - It is derived from the 147 and 09-22 precedents, with the diffs as the review surface. It adds a `LOCALDB`
    rehearsal mode and the `CONFIRM_REF` production opt-in and banner (D).
  - Rehearsal: P3 PASS → POST PASS; the negative control refused (exit 3); rollback restored the pre-hashes and 160 rows;
    re-apply identical; 215 43/43; the production request is byte-identical to the rehearsed one (`c91cec23…`).
  - Deploy set: `enforce-transfer-expiry` only. `confirm-and-release` stays at v37 (F-CR-148-SHARED).
  - D passed the artefacts, the anchor read-back, the `LOCALDB` safety and the rollback order. D has not reviewed the
    document, nor independently verified the P3 and post hashes.
- **Reader sweep** (F-DISPUTE-SELLERWIN-1 enumeration, recorded in FINDINGS):
  - class (a): 7 unfixed, 2 fixed, 1 dead code;
  - class (b): 2 unfixed or partly fixed, 2 fixed by #92.
  - #92 adds no new false record: (d) writes `buyer_confirmed: false` only.
- **Checklist corrected in place** (§5 → mapping, P6/P7, §6, §7 with Build 24 and the §4 citations re-verified at
  `404bce38`, and §8 rewritten with exact dashboard steps: required gates G1–G10, operational R1–R3, optional E1–E8,
  housekeeping H1–H4).
- **Reviewer inventory plan** written (`REVIEW_INVENTORY_PLAN_V3_20260924.md`):
  - app-only creation, max 48 h per listing, $2 → $2.20;
  - both refund paths safe by source;
  - the $300 / $330 decision.
  - **Correction:** the Stripe Dashboard may not cancel a `requires_payment_method` intent, so the CLI is the primary route.
  - **A plaintext password is in `docs/product/LAUNCH_PLAN.md`** (H1).
- **#92 package, rehearsals 3–5, and F-PROD-REPO-DRIFT-1 (A and D, ~16:10–16:25Z).**
  - P3 now stops unless production's seller-win writer and its admin wrapper match the repo: prosrc, plus the binding
    contract (args, result, secdef; D).
  - Negative controls, each on a fresh copy:
    - a writer comment changed → stops;
    - `SECURITY INVOKER` on either function → stops;
    - search_path only → proceeds (informational).
  - **A's false positive withdrawn:** "the wrapper calls the writer unqualified". A lossy `grep -o` stripped the
    `public.` prefix before the filter ran. D could not reproduce the claim and was right.
  - Offline decomposition of the 12-function production drift is negative (no attribute-only variant matches), so the
    bodies likely differ. This is recorded as **F-PROD-REPO-DRIFT-1 (OPEN)**, with the source-only conclusions marked
    provisional.
  - R0-narrow and R0-wide definitions-only reads are prepared and frozen (comparator self-tested), for the owner to
    choose separately.
  - Apply script `0d882f7e…`. The production request is unchanged (`c91cec23…`).
- **R0 reviewed by D; one fix applied (A, ~16:30Z).**
  - D verified R0 is read-only: `pg_proc` / `pg_namespace` only, zero write verbs, against a working control.
  - **D's finding:** exact-signature pinning would mislabel a changed argument-type order as "ABSENT". A's
    comparator-only self-test had not exercised the query path.
  - **Fix:** a by-name overload listing, giving three states.
  - **Tested end to end through the real query:** identical; re-created with a swapped order → "EXISTS AT A DIFFERENT
    SIGNATURE"; dropped → "NO FUNCTION OF THIS NAME".
  - R0 is re-frozen, and the package records it.
- **D accepted the R0 change (~16:35Z); the #92 package is ready for the owner.**
  - R0 is now a mandatory prerequisite of (A), because P3's exact-signature casts would fail opaquely without it (D).
  - Unreviewed by D, as recorded in §11: §10, the regenerated diffs beyond `CONFIRM_REF` and P3, rehearsals 4–5, the
    E2E-1 to E2E-3 results, and `deploy --dry`.
- **R0-wide RUN (owner-authorised, 16:33:35–39Z, one definitions-only read, HTTP 201).** All predictions P-a–P-d held,
  including production unchanged since 09-23 (12/12).
  - 11/12 functions are logically identical (comments or keyword case only), including #92's writer pair and all
    payment-path functions.
  - 1 real difference: `handle_new_user`. The repo baseline is the incomplete side (F-BASELINE-HANDLE-NEW-USER-1); it is
    unrelated to #92.
  - **#92 premise holds.** P3 as frozen would have stopped on the writers' comment-stripped prosrc, so it is re-pinned
    to production's `b7f11225…` / `c5ab888d…`.
  - Rehearsal 6 used production's exact writer functions (defn equal): P3 PASS → POST PASS, and **215 43/43 on
    production's writer code**. The repo-body copy now stops.
  - With D for review.
- **D: R0 result PASS (~16:45Z). #92's production premise holds.**
  - D's independent classification: 0 signature, 0 attribute and 12 body differences, 11 of them comments or case.
  - `handle_new_user` is the one real difference. Production is richer than the repo, so a rebuild or restore from the
    repo would silently regress it (a DR risk).
  - The P3 re-pin and rehearsal 6 are pending D's review.
- **D: P3 re-pin and rehearsal 6 PASS (~16:50Z). No open objection to (A).**
  - Recorded in package §12: the pin's provenance (a production observation at 16:33Z, D-verified semantically
    identical); its shelf life (valid only while the bodies are unchanged; P3 enforces this; re-derive via a fresh R0 if
    it stops); and rehearsal 6's two limits (replay schema; the direct call, not via `ops.execute_action` →
    `action_dispatch`, covered by the binding contract).
  - Documentation only. The frozen scripts are unchanged (apply `8cbd950d…`).
- **Owner, ~16:45Z: Build 24 FAILED visual acceptance. Phone-session fixture mutations are PAUSED.**
  - A's read-only sandbox check at 16:43:56Z: no D1–D6 step ran; bids 0; no payment or PaymentIntent created since
    04:00Z; no new notifications; the fixtures are unchanged. **No cleanup is needed and no cancellation is owed.**
  - Checklist gate G0 added. Not submission-ready while it is open.
  - R0 and the #92 decisions are unaffected (backend, separately authorised).
- **A on C's fourth gated read** (dispute outcome on the receive and send screens): **APPROVED with conditions.**
  - Add `dispute_resolution` + `dispute_resolved_at`, and key the state on `dispute_resolution`.
  - Never map `'resolved_buyer_refunded'` to "refunded" copy.
  - Tests for five cases, including a seller-win after payout. Gated-surface proof back to A.
  - Evidence: 065's write matrix (production logic identical per R0); the sandbox D-8 column privilege `sel=true`;
    production table-level SELECT for authenticated.
- **A's ruling on B §4.5's claims at `404bce38`:**
  - (1) "payout is being processed": false for a seller-win until R1. **Release-order dependency: no production build
    may carry it before R1.** When a future `payout_hold_until` exists, state its date.
  - (2) `SELLER_WINDOW_PASSED`: not true (a device-clock verdict plus an auto-release promise the 039 policy does not
    guarantee).
  - (3) `SELLER_HELD_FALLBACK`: not true (an invented timeline); replace with "Payout on hold."
  - (4) `REFUND_DUE_POLICY`: true as written, as a labelled policy on `expired`.
- C's single vitest run during D's window: the window had closed at about 12:00; D's run was clean, so nothing is void.
- **Owner's refinement (~17:00Z): copy rulings sent to C, replacing A's earlier (1).**
  - "Your payout is being processed" has **no client-queried per-transfer evidence**. `payout_attempts` is
    service_role-only; `transfers` is written only on success (`payout_released_at` + `stripe_transfer_id`); the
    `confirm-and-release` "processing" reply is the buyer's, unstored, and also returned on a claim `db_error`.
  - So C uses a pending state for every payout branch, regardless of deployment. "Released" comes only from
    `payout_released_at`; held and manual review come from the review fields.
  - **"A refund is due" = obligation**, supported only when:
    - (expired, or dispute_resolution ∈ {`resolved_buyer_refunded`, `resolved_partial_refund`})
    - AND the payment is `succeeded`
    - AND no refund is recorded.
  - A **decision** is `dispute_resolution` alone. **Execution** is a recorded refund on the payment, and is the only
    source of "Refunded".
  - Expiry execution is automatic once, live-mode only, with no retry. Dispute execution is manual.
  - Test scope sent to C.
  - The fixture pause stays; the existing approvals stand and are not re-requested.
- **#92 production execution, 2026-09-24 (owner (A)+(B) at package `05c4f5fa`): PASS, no rollback.**
  - P1 16:54:50Z; P2 16:55:22Z; P3 and apply 16:55:40Z (HTTP 201; the request is the rehearsed one, `c91cec23…`).
  - Ledger 160→161 (`20260924000000`); claim and notify at the 148 hashes; grants matrix identical; census unchanged.
  - `enforce-transfer-expiry` v40→v41 at 16:57:01Z from `e73553d2`, byte-verified.
  - Run check PASS at 17:03:42Z: 3 post-deploy runs, all 200 with 0 errors; payout_attempts 0; seller_win_rows 0.
  - All steps matched the predictions registered at 16:54:50Z. Record: package §13, with three evidence limits (version
    attribution by timing; new paths unexercised; Stripe not read).
  - Not done, not authorised: merging #92 (C); resolving disputes; `confirm-and-release` (still v37).
  - Records updated: registry row 148, checklist P6/P7/R1/R2, HANDOFF_A §2, wording table header.
- **D's review of the #92 execution record: PASS.** §13 is amended with D's four points, each verified by A against
  source:
  - the (d) selection is schema-valid, provided execution reached (d);
  - payout-side Stripe calls are bounded by payout_attempts 0;
  - E-6 is now live prospectively ("processing" told to a buyer on a held seller-win row; no money, no row). #92's
    bundle is not the fix (F-CR-148-SHARED);
  - the drift hazard is widened to a bulk redeploy, which would invisibly reinstate F-DISPUTE-SELLERWIN-1.
  - P1's v40 is recorded as held by control flow.
  - D states it read production at 17:03:51Z and 17:04:53Z under the owner's authorisation; A cannot see it, so owner
    confirmation is requested.
- **Correction to reader sweep a1 (D's finding; A verified at `5b255838`/`e73553d2`).** The false `payout_decisions`
  row (`buyer_confirmed true`) is reachable on the live `confirm-and-release` v37, given a seller-win row. The path is
  the `alreadyConfirmed` bypass, then any refusal v37 already recognises, then `payoutDeferred`. "Reachable only via a
  redeploy" was wrong. Holding v37 only avoids two more routes. The defect needs its own fix (neither `payoutDeferred`
  nor the release audit may assert a confirmation when `buyer_confirmed_at` is NULL). It is prospective (0 seller-win
  rows; current clients don't offer the call). D stopped production reads pending the owner's ruling on the scope of
  D's witness authorisation, which D quoted in full.
- **Owner ruling on D's #92 witness reads:** authorised, under the owner's wording "I directly authorise your
  read-only witness checks of P1–P3 and the apply/deploy/run-check results for package 05c4f5fa". D's PASS is recorded
  as the authorised independent witness (package §13). The ruling grants no further production reads.
- **The owner's next instructions:**
  - Prepare the audit-record fix (a1–a4) as a draft PR only.
  - Prepare #92's gate-merge command and checks; the merge itself is not authorised.
  - No apply, deploy, merge, dispute resolution or production change.
- **Audit-record fix (a1–a4): draft PR SnatchIt-app/snatchit#93**, head `9fb450eb`, stacked on #92. Registry 149
  (`20260924120000`), pgTAP 216.
  - pgTAP: RED on the unfixed chain as predicted; 26/26 green. Mutant kill sets are distinct; the guarded rollback
    brings back the RED set.
  - Fresh replay 165/165; census unchanged; full pgTAP 5537/5537.
  - vitest: BC-* RED 7, then green; five edge mutants each kill a distinct set; full vitest 2538/2538.
  - Nothing is applied or deployed. D's review has been requested.
- **#92 gate-merge package prepared** (package §14): the exact commands, and `merge92_checks.sh` pre (dry run ALL
  PASS) and post. The merge is NOT authorised, and #92 must never go to `main`.
- **#93 CI (run 36036750660, head `9fb450eb`): green, 9/9 checks, including the Deno type check.** pgTAP Files=96 /
  Tests=5543 PASS. That is exactly the predicted count: local 5537 plus the 6 in `000_helpers`. Census 32/108/37/38.
- **D reviewed #93 by reading (PASS on the source).**
  - D re-derived the fixed hashes `62f74728…` / `03ea4589…` independently.
  - Q1: the flag's only reader is the admin label at `page.tsx:542`. Verified by A.
  - Q3: every status writer is 002 or 0550 (both with the timestamp) or 065 (without). So a status-only row is a
    seller-win or a direct write, and false is exact. Verified by A, after a lossy grep of A's was re-run raw.
  - Q4: DUPLICATE_TRANSFER is relabelled as a contract test of a defensive branch; `record_transfer_payout` has no
    live edge caller.
  - The comments D asked for are applied at head `9e7006bf` (comments only; 216 26/26, and the vitest files re-run
    green).
  - The optional `dispute_open` read was declined: its true branch is unreachable after §5's 409.
  - D's independent red/green of 216 has been requested (a two-party check).
- **#93 CI at `9e7006bf` (run 36037548673): green, 9/9 checks.** pgTAP Files=96 / Tests=5543 PASS; census 32/108/37/38.
- **D's independent red/green of 216: identical to A's, test by test (a two-party computation).**
  - D registered its prediction before running.
  - RED (chain `e73553d2` + 216 from `9e7006bf`): 21/26, failing 6,10,13,17,18.
  - GREEN (`9e7006bf`): 26/26. Replay 165/165; census 32/108/37/38 on both databases.
  - D checked the body hashes in each database, so the difference is the one expression and not the harness.
  - D verified that `9fb450eb..9e7006bf` changes comments only. D's databases were dropped afterwards.
  - Limit: D ran only `000_helpers` and 216. The mutants, rollback cycle and vitest remain A's evidence.
- **A reviewed C's V3 batch** (`v3/midnight-app`, uncommitted, in `snatchit-refund`), by reading only:
  - Gated files: only `signOut.ts` +5, as C stated.
  - The `_dev` auth-gate exemption requires `__DEV__` or `IS_SANDBOX_BUILD`. That is false for a production pairing,
    because the env guard requires a sandbox environment, a sandbox host and paired keys. The `_dev` segment layout
    redirects home on its own.
  - The harness screens make no direct server or payment calls.
  - `money.ts`, `bidEntry.ts` and `detailState.ts` are display-only V3 formatting over the canonical cent helpers.
    Nothing submitted or charged changes.
  - `authStateHandler` clears the dock avatar on every SIGNED_OUT, which protects privacy. No objection.
- **A's gated sign-off: `src/lib/auth/signOut.ts` +5** (C's `5668bdab`, `v3/midnight-app` at `262c908b`).
  - **Approved, with one test condition.** The change is an additive optional `clearDockAvatar`, called only after
    success, inside a try/catch that never blocks. Ordering and failure paths are unchanged. The avatar store has no
    dependencies, and its owner guard makes a missed clear harmless. D's review was also no-objection.
  - **The condition:** the only ordering test is a source-text `indexOf` check. C must add a behavioural test
    through `revokeThenSignOut(deps)`:
    - a failed sign-out does not clear;
    - a successful one clears once;
    - a throwing clear still returns signed out;
    - with a negative control.
- **Gated sign-off CLOSED: C's `signOut.ts` +5 is APPROVED.**
  - C added the behavioural tests `tests/signout-clears-dock-avatar.test.ts` SA1–SA4, driven through
    `revokeThenSignOut(deps)`.
  - C's negative control (the call moved above the failure return) killed SA1 and SA2, with the digests restored.
  - A read the tests and ran them once in `snatchit-refund`: 4/4, exit 0.
  - The test file is still uncommitted. It must land in the same batch as `5668bdab`.
  - C's full suite: 152 files / 2724 tests, exit 0 (C's run).
- **Owner-authorised source reconciliation: done, both merges verified.** Details are in package §14.
  - #92 merged into the gate at 18:12:19Z as `374103c0`, pre and post checks ALL PASS. Gate CI 36039602792 green
    (95/5517). Vercel ignored the build.
  - #93 merged at 18:15:58Z as `037092f0`, pre and post ALL PASS. Gate CI on `037092f0` is pending at the time of
    writing.
  - `main` is unchanged. Nothing was applied or deployed.
- **D's post-hoc witness of both merges: PASS**, from D's own GitHub reads.
  - Both parent pairs and tree identities hold; ancestry was checked first.
  - File sets are 8 and 6. CI logs show 95/5517 and 96/5543.
  - `main` is unmoved. Vercel "Canceled by Ignored Build Step" with **zero deployments** on either commit.
  - D's independent 149 anchor `7e4d3b2d…`/9904 equals A's.
- **149 + `confirm-and-release` production package prepared, rehearsed and frozen:**
  `PR93_PRODUCTION_EXECUTION_PACKAGE_20260924.md`, `scratchpad/apply_149/`, `FROZEN_SHA256.txt` `81653983…`.
  - Rehearsal R0–R8: every step matched, except that R3 failed on 7 keys where A predicted 6 (A's prediction error).
  - The production request is byte-identical to the rehearsed one.
  - NOT authorised. D's script review has been requested.
- **D's script review of the 149 package: PASS.**
  - D's recommended `md5(statements[1])` check and three further improvements are adopted.
  - Re-rehearsed as v2, with every prediction matching, including two new negative controls that fail on exactly their
    targets.
  - Re-frozen: `FROZEN_SHA256.txt` `8305d966…`, 16 files.
  - Still NOT authorised; the owner's approval request uses the new package commit.
- **D verified the re-frozen 149 package: 16/16, all four points present. D's PASS carries to `dddb93a7`.**
- **A's review of C's fourth gated read at `dd81fb97`** (read only; nothing run): **APPROVED** on (a), on (b) with the
  owner's 16:51Z refinement, and on (d).
  - Gated diff: `signOut.ts` +5 only.
  - The selects add exactly `dispute_resolution, dispute_resolved_at`, same scopes.
  - `refundStateLine`: "due" = source AND captured AND no refund recorded. That is the owner's rule.
  - **One change requested on (c):** drop `heldLine` from the seller's DECIDED block. An unpaid seller-win has status
    `buyer_confirmed` (065), so inside the `disputed` block a stale hold would tell a losing seller that a payout is
    coming. A test is asked for.
  - **Clean-run request:** C's 2747/2748 run included uncommitted peer edits, so it is not a run of `dd81fb97`.
  - READFAIL fix `25b7e1f6` accepted: a silent post-reserve refresh, pinned by a test, re-verified by D.
- **C's fourth-read follow-up at `54d5492f`** (verified by A by reading, plus C's clean worktree).
  - **Accepted:**
    - the decided-dispute payout sentence now comes from `payout_released_at` alone;
    - an unpaid operator seller-win now reads "Payout pending." — a live defect C found while answering A;
    - the clean run: a detached worktree at `54d5492f` with 0 dirty files, 154 files, 2750/2750. The file lacks the
      exit status; C is asked to append it.
  - **Blocking:** `send/[id].tsx:481` still says "Your payout is being processed…" on the genuine-confirmation path,
    and P3 pins it. The owner's 16:51Z ruling covers genuine confirmations explicitly, so it must become the pending
    state, with the Settings sentence allowed as guidance.
  - A's audit of the remaining payout-progress copy: `settings/index.tsx:190` (a server fact) and `payout-setup.tsx:186`
    (generic) are fine.
- **A's gated sign-off: C's `b220ec20`** (`v3/midnight-app`), covering the fourth gated read and its follow-ups.
  - Gated diff: `signOut.ts` +5 only.
  - Zero rendered "being processed". Every unreleased, unheld payout reads "Payout pending", with manual review from
    the review field; this is the owner's 16:51Z rule.
  - Clean run `full-run-14`: 2750/2750, exit=0, commit=`b220ec20`, dirty_files=0.
  - The sign-off covers the gate only; the visual review and the build remain separate.
  - Next to A: `sellState.ts` priceSummary display (seller-money wording).
- **A approved C's `sellState.ts` priceSummary change at `c19c91eb`** (display-only seller-money wording).
  - The buyer total uses the same cents path.
  - Seller net goes through `sellerNetDollars`, then `formatDollarsV3`. Over every whole-dollar base from $1 to
    $100,000 the round trip gives the same cents as `sellerNetCents` (helpers modelled from source).
  - The gated diff is still `signOut.ts` +5.
  - Pending: the tickets/orders agent's uncommitted edits to `receive/[id].tsx` come to A if they touch the select,
    the dispute or refund lines, or payout wording.
- **A's rulings on the tickets/orders agent's frozen `receive/[id].tsx` edits** (uncommitted, C's worktree):
  - **(1) Listing embed widening: approved minus `cover_image_url`, which does not exist on `listings`.** It is in no
    migration, so production lacks it too. Selecting it would make PostgREST reject the whole transfer read, and every
    buyer's order screen would fail. It must be dropped and pinned by a schema-level column test.
  - **(2) Settled-payments read on every loaded order: approved.** "You paid <total>" only from exactly one settled
    row (total = amount + buyer_fee, the card charge). Zero rows, several rows or an error → no amount. Never the
    listing price. `readSettledPayments`' select stays unchanged.
  - **(3) Tickets/fee breakdown:** not needed now. If the owner wants it, `payments.amount` and `buyer_fee` exist,
    via a separately reviewed select.
- **A approved the order screen's money and payout facts** (C's `c84618ee` + `e5878b3f`).
  - The embed is exactly 8 real columns, and `cover_image_url` was removed. A ran the schema leg on `a149_fresh_rehears`:
    the select succeeds, and the `cover_image_url` control fails.
  - `youPaidAmount` requires exactly one settled row (succeeded or refunded) with a positive total. There is no
    listing-price path.
  - The payout step comes from `payout_released_at` only. The confirm caption is true: the dialog comes first.
  - The gated diff, including `settledRead.ts`: `signOut.ts` +5 only.
  - Clean run `full-run-20`: 2784/2784, exit=0, dirty_files=0.
- **Scope correction (A).** The gated-diff proof A and C used named five files. It missed
  `src/lib/checkout/listingSummary.ts` +9/−1: `ticket_type` added to the checkout summary read in C's `dd410da4` /
  `7d44f87d`, 2026-09-23.
  - A's earlier "signOut.ts +5 only" statements held for the named files, not for the checkout directory.
  - Reviewed now and APPROVED: a real column, display only, the same row.
  - The proof command is now the whole `src/lib/checkout/` directory, plus `payments.ts` and `signOut.ts`.
- **A approved C's send screen at `58c3c348`** for the gate: presentation only, with 0 payout or refund strings
  changed.
  - Truth ruling on the board's payout paragraphs, recorded for the deviation:
    - the countdown → show the server deadline date instead;
    - "releases once it clears review…" → not supportable (039 holds, manual review and onboarding still apply);
    - "held for review if the buyer reports an issue" → supportable.
  - Send's listing embed widened to the same 8 columns: approved.
  - D's derived second leg accepted.
- **149 + `confirm-and-release` PRODUCTION EXECUTION: ALL PASS, no rollback** (owner authorisation A-149 + B-149 +
  V-3, package `dddb93a7`; record in package §12).
  - Frozen 16/16. A's predictions at 20:27:48Z; D's blind expectations at 20:29:36Z; **D's W0 PASS** at 20:30:14Z.
  - P1 at 20:29:58Z, P2 at 20:30:12Z, P3 at 20:30:20Z: 11/11, with the replay-derived defn pins matching production
    (n=2).
  - **Apply at 20:31:03Z:** HTTP 201, request `f1bb0489…` = the rehearsed one. POST PASS, ledger 162, `stmt_md5` =
    D's anchor.
  - **`confirm-and-release` v38 at 20:31:30Z:** byte-verified 5/5 against `037092f0`.
  - **V-3 probe PASS** at 20:31:39Z.
  - payout_decisions 4 and payout_attempts 0 before, as the baseline.
  - Nothing else changed. Evidence limit: the changed paths are not yet exercised in production. D's W2 is pending
    (superseded: **W2 PASS at 20:32:18Z**, entry below).
  - Output sha256: 01_apply.sql `f1bb0489`, APPLY_01.txt `fe12a490`, 01_readback.json `379057cb`,
    01_post149.json `93754f7a`, 00/01_grants `9955f5d9`, DEPLOY.txt `55f4de8d`, PROBE.txt `b593dde7`,
    P1 `97efdb5b`, P3 `df14974c`.
- **D's W2 PASS at 20:32:18Z** for the 149 + `confirm-and-release` execution. It came from D's own database read, D's
  functions GET and D's own source download.
  - Every blind expectation was met, including exactly one function changed, 5/5 against `037092f0`, and a
    non-vacuous `payouts.ts` control.
  - Window invariants held: attempts 0→0, decisions 4→4, dispute_resolutions 0→0.
  - The execution is closed: A and D both PASS, no rollback.
- **E audit follow-ups (A, 2026-09-24 ~20:50Z):** done at `2fd5cb4c`. Details:
  - checklist re-synced to the 149/v38 execution;
  - H3 / F-CR-148-SHARED closed, citing BOTH #92's `payouts.ts:319` and #93's `index.ts:347-348/:381/:383/:425/:435`
    (D, E and A each verified that #93 did not touch `payouts.ts`);
  - FINDINGS a1–a4 marked FIXED; the stale "draft only" line superseded;
  - the review-notes "live Stripe keys" sentence withheld;
  - the fixture sheet's resume note: the approval names Build 24, so the owner's "go" must name the replacement build;
  - the 149 raw outputs of A and D archived at `docs/release/evidence/149_20260924/`, with a manifest;
  - the local gate branch fast-forwarded to `037092f0` in the idle, clean `snatchit-prodgate` worktree.
  - **G10 kept OPEN:** the owner's rulings cover D's witness reads for the #92 and 149 packages, not the [D-PROD] review
    reads the checklist cites.
- **A's rulings for C (at `0677c80e`):**
  - (1) SELLER_WINDOW_PASSED must key on a server fact, not the device clock. It is false even with a correct clock,
    because `buyer_dispute_transfer` (0550) accepts disputes while the status is `seller_sent` regardless of
    `auto_release_at`. Drop it and always show the "Release decision at <date>" server-date line.
  - (2) No buyer-refund facts on the seller's reversed block. Status `reversed` = the seller's Stripe transfer was
    reversed (sole writer `mark_transfer_reversed`, from `transfer.reversed`). The gallery's four seller-reversed
    refund variants are stale.
  - (3) Finding: SELLER_REVERSED_COPY overstates. A partial reversal also marks the row reversed, and the cause is not
    recorded. Replacement text sent.
- **Owner's instruction, ~21:20Z (A, 2026-09-24): D's reads, the secret check, dashboard checks, seller rulings.**
  - **G10 stays OPEN.** E relayed an owner ratification of D's review reads. The owner's later direct instruction to A
    asked instead for a bounded list and said the owner will decide the scope, and A follows that instruction.
    - Checklist §9 lists the 4 reads (R1–R4, reported 04:53–05:19Z): purpose, scope, figures, and A's retain/drop
      recommendation. It was built from records, with no new production read.
    - Every [D-PROD] figure is now tagged with its read time and "as of".
    - Figures an authorised read measured since are re-cited to that read: 149 P3 at 20:30:20Z (payout_attempts 0,
      dispute_resolutions 0, 5 open, seller-win rows 0) and A's 2026-09-17 R7 (EMAIL_ENABLED absent).
  - **The Stripe-secret step was replaced.** The old instruction put the secret on the command line; it is removed from
    every doc.
    - New tool: `scripts/owner/secret_digest_compare.zsh` (sha256 `a4f1a636…0866`). It takes the secret as hidden
      input, which goes only through a builtin into a pipe to `/usr/bin/shasum`. It clears the clipboard and prints
      only the kind and length.
    - Tests: 8/8 PASS with dummy values in a pseudo-terminal (exact match, trailing newline, wrong digest,
      whitespace/uppercase, test-key kind, bad digest, the control URL, non-tty refusal).
    - Echo witness: a copy of the tool with echo left on is caught by the same check.
  - **Digest comparability (sandbox, read-only).** All 14 values are 64-hex. SUPABASE_URL's value is exactly
    SHA-256(value): a trailing newline, SHA-1 and the other control's value do not match.
    - The anon-key control did NOT match. The likely cause is a wrong candidate value; this is untested and recorded as
      unexplained.
    - A test of hand-set secrets was refused by the permission check because it guessed values. A did not pursue it.
    - So G4 starts with a control on the production page (the prod SUPABASE_URL row; its expected digest is computed
      locally). A mismatch after a passing control is "most likely a different value", not proof.
  - **G3/G5 now say configuration presence only.** Neither is evidence of delivery, signature verification or a
    working Apple Pay payment.
  - **Seller rulings (C, 20:56Z) are now in the shared reference** `PAYMENT_STATE_WORDING_TABLE_20260924.md` §2d/§2e.
    - §2d's own earlier "after a dispute/operator review" text was A's, and is withdrawn.
  - **C's 102d8de9: CONFIRMED** (read at the commit). SELLER_WINDOW_PASSED is removed. The release line no longer
    branches on the clock. The reversed copy is exactly the ruling's text. TG4b asserts the property.
  - **C's d374bd3f (checkout split): PASS on behaviour** (a reading review; A ran no tests).
    - The CheckoutScreen logic before the render is identical except for 3 presentation hooks.
    - The payControl inputs and onPress mapping are byte-identical, and so are the button bindings.
    - The success-haptic latch moved verbatim. The gated files are unchanged.
    - One presentation-only difference: "Preparing your total" can now show while a changed total is pending.
  - **RE-RULED (§2f):** "payment is held until it reaches you" (completed face) and ESCROW_NOTE_COPY
    (holdState.ts:97) are withdrawn, because release never depends on delivery.
    - True replacement: "a report freezes the seller's payout" (0550; 144:813–819; 0551).
    - Pre-existing, so not a d374bd3f blocker.
  - **Disputes:** the 5 stay unresolved; no action on them.

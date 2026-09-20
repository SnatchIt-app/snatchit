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

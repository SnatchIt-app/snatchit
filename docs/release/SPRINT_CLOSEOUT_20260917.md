# Sprint close-out — final report (A, 2026-09-17)

**Scope of this document.** The owner closed the sprint with six rulings and asked for one final report. Everything below is drawn from local repository work and evidence already recorded in this sprint. **Nothing was run against production, the sandbox, or the retained proof objects to produce it** — no hosted read, no test, no build, no deploy, no key. The one verification performed while writing it was a read of `app/(tabs)/home.tsx` at the built commit `f412d10` in local git, to check C's new finding rather than relay it unchecked.

**The six rulings, verbatim, and where each is now recorded:**

| # | Ruling | Recorded in |
|---|---|---|
| 1 | F-NOTICE-1: use the minimal fix; no new notification type or outbound message; branch and 141 unapplied unless a separate apply decision is made | `F_NOTICE_1_ROOT_CAUSE_AND_FIX_20260917.md` §6; registry row 141; status row 1 |
| 2 | Leave the two retained Line 3 proof files and their references untouched — no further reads, downloads, deletion, overwrite, service key or cleanup verification | `SANDBOX_ACCEPTANCE_WINDOW_MANIFEST.md` §17; status row 2 |
| 3 | PFA-34 remains proposed and unsigned; do not treat it as approved or apply 138 | `POST_FREEZE_AMENDMENTS.md` PFA-34 close-out note ¶1; status row 4 |
| 4 | Defer the venue-staff detector extension; detection scope stays organisation membership; leave the local extension unpushed | PFA-34 close-out note ¶2–3; apply package §9 point 6; status row 5 |
| 5 | 138 unapplied and off the candidate; no 115–120, no hosted detection reads, no server-log settings read, no production access, no function deploys, no keys, no build | Apply package §9; manifest §17; registry row 138; status row 3 |
| 6 | F-BIDS-1 stays at `6561d1f` for the later candidate; Build 19 unchanged | Status row 6 |

---

## 1. Completed and verified work

Each line carries the evidence that makes it a result rather than a claim. "Verified" here means a CI run or command output from this sprint, not a judgement.

**Shipped into the reviewed candidate tree**
- **F-NAV-1** (Keep editing leaves Edit listing) — integrated at `f412d10`; CI 35237352892 SUCCESS on five jobs; D merge gate PASS; A's own rerun: vitest 2229/105, tsc 0, lint 0 errors.
- **F-BIDS-1** (Bids empty state while purchases load, and after a failed purchases read) — integrated at `release/production-gate-20260918 @ 6561d1f`; CI 35245103799 SUCCESS, re-verified during the away period; D merge gate PASS. `f412d10..6561d1f` changes **0 lines** under `supabase/`, so the 138-era apply hashes and PC3 values still hold at `6561d1f`.
- **Build 19** = `candidate/2026-09-18-build-c3` → `f412d10`; EAS `8ebf4d81-…`, FINISHED 15:55:30Z; the build record's commit verified independently by A and C. Installed on the owner's iPhone. **Unchanged by this close-out.**

**Server-side fix, reviewed and green, applied nowhere**
- **F-NOTICE-1 / migration 141** at `fix/f-notice-1-withdraw-retires-notice @ ea547e5`. Root cause reproduced on a local replay (request → drain → withdraw leaves the notice live). Fix: `notify.retire_account_deletion_pending(uuid)` (SECURITY DEFINER, postgres-owned, `search_path=''`, `lock_timeout=2s`, EXECUTE revoked from public/anon/authenticated/service_role) called from `kernel.withdraw_account_deletion`, whose body is otherwise 077's verbatim; the retire lives in `notify` because 157 A48 forbids a kernel routine from touching notify's tables — the first draft violated it and A48 caught it. pgTAP 208, plan(22), with the discriminating matrix measured rather than asserted: exactly **B3, C3, D4** fail on 077's body. **CI 35263537823 SUCCESS on five jobs; pgTAP Files=89, Tests=5325, PASS.** Reviewed by D (**PASS**) and B, closing three findings: D's F-141-1 (service_role EXECUTE was unpinned — D proved the hole by granting it and watching four suites stay green), D's abort trade-off (an abort leaves the identity in DELETION_PENDING, now stated, with `lock_timeout` so a stuck retire fails fast), and B's header overclaim plus C3-as-a-delta.

**Sandbox windows executed and closed (all with D witnessing)**
- **Image round trip RT1–RT5, RT7**, 16:16:49Z–16:18:11Z — closed, rt objects 0.
- **Window W-C3** (136 → 139 → 140; stripe-webhook, notify-report), 16:19:21Z–16:29:26Z — closed, census met exactly (32\|109\|37\|37).
- **Accidental report `265b0041…`** — proved to have caused **no outbound call whatsoever**, then deleted 18:07:09.332Z (exactly one row) under the owner's direct authorization with A's and D's pre-reads matching; closed 18:08:24.956Z with D's post-read agreeing on exactly two changed lines.
- **DV-ST2b**, window 18:36:23Z–18:38:56Z — **server half PASSED**: six `GET /rest/v1/bids` → 403 (PostgREST 42501) inside the window, 200s before it, restore verified separately by A and D (md5 `466fd2d8…`).

**Review work completed**
- **138 at `a9aa34e`: A's independent review PASS** — own replay 157/157, Gate-2 32\|107\|37\|38, 5435/5435 under a strict TAP::Parser pass, migration and rollback byte-identical to the reviewed `5960b51`, all seven pre-apply `prosrc` md5s recomputed from the migration text, eight mutants each asserted to apply, change the live digest and restore, killing exactly the predicted tests, and A's own run of the two-session A6 proof (S1, S2, S3, C1, C2 all pass — including the control where, without A6, two concurrent acceptances leave the organisation with **zero owners**).
- **PFA-33 SIGNED** at governance `99ecf31`, block md5 `2da381a1667b0c9e873b709ff3f1d7ce`, 5731 bytes, 59 lines — re-verified byte-unchanged after today's edits.
- **F-CHK-1 reclassified** — A read the source instead of accepting the report: the checkout screen already implements the owner's three-way distinction, and `unreachable` withdraws Pay and says "please don't pay again". **A had relayed it to the owner as release-critical before checking; that was A's error and is recorded as one.**

**Facts established that change future planning**
- **iOS 27 / SDK gate:** our config never set `UIDesignRequiresCompatibility`, so nothing is lost by Apple ignoring it; the real gate is that an SDK targeting iOS 27 requires the scene-based lifecycle **or the app fails to launch**.
- **Reanimated is installed but has never run** (no `babel.config.js` anywhere) — any Reanimated proposal implies a Babel change plus a build.
- **Tokens are a three-file change**, and they do not reach web until the vendored tarball is repacked.

---

## 2. Quarantined or retained evidence

**The two Line 3 proof objects — RETAINED, and now untouchable.** Ruling 2 is stricter than the ruling that closed the incident: it adds *no further reads* and *no cleanup verification* to the existing bar on deletion, overwrite, reference clearing, service-key use and storage access. **Consequence stated plainly: there will be no confirming read, so manifest §16 is the final state of record and nothing later will corroborate it.** That is the intended outcome of the ruling, not a gap in it.

What §16 established while reading was still permitted:
- Two objects in `proof-docs`, both referenced by their transfers, both transfers `seller_sent`.
- **Two of the three photographs never left the phone** (the offline row failed before upload; the S8only image was never attached).
- Access records show **only the owner's own two accounts** — the seller's two uploads and the owner's buyer-side views. No third party. Nothing outbound (0 of 191 2xx).
- The one-hour signed link minted 21:13:40Z lapsed on its own at ~22:13:40Z.
- **Nobody has ever read the content of either object** — no download, no hash, no EXIF, by any session, at any point. Under this ruling that stays true permanently.

**Line 3 itself is CLOSED as quarantined.** Held unless the owner reopens them: RT6, U1, RT5-P, N1, N2, N4, DV-IMG-4's retry half, DV-IMG-10, the HEIC conversion half.

**Results retained as they stand, not upgraded:** D2 and D1 upload paths **PASSED** · HEIC conversion **UNTESTED** (the phone was on "Most Compatible", per the rule fixed before the row) · D6 **INCOMPLETE** · DV-IMG-10 **UNTESTED** · N3 **PASSED** · call count **NOT ESTABLISHED**.

**Two process failures, recorded as failures.** The approved order was not followed (D6 skipped, D2 ran before D1), and no row boundary reached A, so neither D nor A witnessed either write. The intermediate state is **gone and recorded as gone**; there is no re-run.

**Other retained records:** the DV-ST2b client half — rows remained visible, but any message or banner was **NOT CAPTURED** and is not inferred as absent. The signing-monitor quarantine `4ac8baf` stands, separate scope, no further reads.

---

## 3. Open findings and their owners

| Finding | Owner | State | Note |
|---|---|---|---|
| **F-HOME-1** — Home's "Recently sold" and "Ended" filters claim an empty marketplace when their fetch fails | **C** (found, device-confirmed); A verified the source | **OPEN, NEW** | Device: Airplane Mode + Wi-Fi off, Build 19 — "NOTHING SOLD YET" / "NO ENDED AUCTIONS", no error, banner, retry or spinner. **A's own read at `f412d10` confirms it:** the main listings fetch classifies failures, while `fetchSoldListings` and `fetchEndedListings` each `console.warn` and return with no loading flag and no error state. Same class as F-BIDS-1; belongs in the **next candidate**, not Build 19. Two halves **UNTESTED** and not inferred: the slow-network premature-empty path, and whether the false empty is sticky after connectivity returns **Mechanism, A-verified in source at `f412d10` after C committed its prediction (C `7dcdf22`):** the once-flags are set only at `:218`/`:238`, *after* the early return, so a failure never poisons them; re-selecting the chip refetches at `:349`/`:350` and `:359`/`:360` precisely because the flag is still false; `useFocusEffect` (`:246-252`) re-runs `fetchListings()` only. **A found a second recovery path C had not listed:** `onRefresh` (`:366-370`) calls `fetchSoldListings()`/`fetchEndedListings()` **unconditionally** on the active chip, with no once-flag gate. So the predicted shape is: sticky against time and against leaving and returning to Home, clearing on **either** re-selection **or** pull-to-refresh — the gesture a user actually makes when a list looks wrongly empty, which lowers practical severity a notch. **Severity language, corrected by C and refined by A:** a user who leaves the filter sees the **last successful** main feed, not a fresh read, and if the main fetch also failed `:191-197` sets a classified error — so the honest framing is "never claims emptiness; may be stale; says so when it cannot read", NOT "sees real state" (A's first wording, wrong and retracted). **A's “lowers practical severity a notch” is WITHDRAWN — C's counter-point inverts it (C `e9dd55f`), and A agrees from the same source.** `onRefresh` wraps the call in `refreshing` true/false, so the user gets a spinner; but the sold/ended fetch returns early on error with no error state, so **pulling to refresh while still offline ends the spinner on the same settled empty copy and reads as a refresh that CONFIRMED emptiness**. The one path therefore cuts both ways: it **recovers** the screen after connectivity returns, and it **falsely confirms** the lie while connectivity is still down — and it is the gesture a user reaches for precisely when the list looks wrong. Net: severity is not lowered; the offline case is the worse of the two, and the recovery case is the milder one. **C also corrected the owner's run sequence before it ran** (watch passively without pulling → then pull as its own step → then re-select if still empty), so a pull during the passive-watch step can no longer be misread as self-recovery. **A's corrections on this finding, both recorded rather than quietly fixed:** “sees real state” (wrong: it is the last successful feed, with a classified error when the main fetch also fails) and “lowers severity a notch” (wrong: it lowers it only after reconnection and raises it while offline). |
| **F-CHK-1 (narrowed)** — the PRE-request case: starting checkout with no connectivity at all | **C** to confirm in source | **OPEN, narrowed** | The original finding does not hold. Any proposal must carry B's discriminating control — a network failure that is **not** a Stripe decline, since a generic-failure test passes on the current tree |
| **F-BID-2** — bid form computes its minimum from `0` after a discarded fetch error | **C** | **OPEN, LOW–MED** | A truthfulness defect, not a money one; the server still validates |
| **F-AUTH-2** — duplicate data requests after sign-in | **C** | **OPEN, LOW** | Load, not correctness |
| **F-DT-1** — text size applies only after relaunch | **C** | **OPEN, LOW–MED (accessibility)** | Relaunch recovers; any mitigation goes to the owner first |
| **Edit listing:** swipe during an in-flight save, then "Saved" OK calls `router.back()` from My Listings | **C** | **OPEN, severity not set** | Source-only (D), pre-existing, outside F-NAV-1's scope |
| **Venue-plane membership is unmonitored** | **owner** (it is a deferral consequence, not a defect) | **CARRIED** | One operator can grant venue staff to another operator at a customer venue (`venue.grant_staff_role`, 080:224); with the detector extension deferred, nothing reports it |
| **Buyer's existing stale deletion notice** in the sandbox | **owner** | **OPEN** | The 141 fix is forward-only and that identity has already withdrawn, so the row persists until §4 is separately authorized |
| **F-BIDS-1 follow-up:** bump the load generation before the `!userId` return | **C**, A integrates | **OPEN, minor** | Carried with the fix to its candidate |
| Dead code and stale status lines noted in passing | **A** | **OPEN, cosmetic** | A future cleanup PR; never bundled with a functional change |

---

## 4. Deferred decisions

| Item | Deferred by | What deferral means in practice |
|---|---|---|
| **PFA-34 signature** | Ruling 3 | Stays PROPOSED, NOT SIGNED. The placed block is byte-unchanged: md5 `026cb858319bc7c0181e1dad01e23ef1`, 2726 bytes, 27 lines. **Conflict resolved** — D's session was told it was signed, A's was told to keep it unsigned; neither acted on the other's relay, the governance file was never changed, and the owner's own ruling now settles it |
| **Venue-staff detector extension** | Ruling 4 | Detection stays organisation membership. D's `1cacdf5` is **local, unpushed, no CI, unreviewed** and stays that way; the reviewed head remains `a9aa34e`. **Conflict resolved.** Side effect worth naming: PFA-34's placed D1 clause and the reviewed implementation now agree again, so no erratum is needed and the checksum did not change |
| **Applying migration 138** | Ruling 5 | Unapplied everywhere, off the candidate. The apply package is **PARKED** with all six approval points unexercised |
| **Sandbox chain 115–120** | Ruling 5 | Not applied. A and D had both recommended against it mid-sprint (it would start `ops-detect-tick` every 5 minutes, shift the census baseline, and break D's witness discriminator) |
| **Hosted detection read (PFA-34 D1)** | Ruling 5 | Not run on any project |
| **Server-log settings read (138 F11)** | Ruling 5, and the earlier deferral | Stays **UNVERIFIED**. The scope document exists; the read does not |
| **Applying migration 141** | Ruling 1 | The fix is chosen but applied nowhere; an apply is its own decision |
| **§4 cleanup of the buyer's stale notice** | Not authorized | Remains un-run; today's instruction bars touching hosted data |
| **72-hour auto-release tail** | Owner's choice; A and D jointly recommended carrying it | Carried, not cleared. Clearing `auto_release_at` is another sandbox write |
| **Sandbox push key** | Earlier deferral, unchanged | Still deferred (option b). The handset push matrix is **deferred, not passed** |
| **Cleanup sweep for proof-docs orphans** | Owner | Design only (≥30 d, dry-run first, no scheduled job); implementation not requested |
| **Require proof before marking sent** | Owner | Proposal written; needs installed-build data or a named read authorization |
| **Next SDK move (iOS 27)** | Nobody is proposing one | Recorded as a hard dependency: scene-based lifecycle or the app fails to launch |

---

## 5. Items requiring a future explicit authorization

Nothing in this list may be started on the strength of this sprint's approvals. Each needs the owner's word, given for that action, at that time.

1. **Applying migration 141** to any project — including the sandbox.
2. **Applying migration 138**, plus each of its five remaining approval points separately: the pre-apply reads per project, the detection read per project, the 115–120 sandbox chain, the production apply, and signing PFA-34 beforehand.
3. **Any production access at all** — including a read, including a count. Production is at ledger 135 with nothing applied since 2026-09-12, and stays that way.
4. **Any sandbox write, window or apply.** The sandbox is closed for the sprint.
5. **Any touch of the two retained proof objects** — including a read, a download, or a verification that they are unchanged. Ruling 2 bars all of it.
6. **The §4 cleanup** of the buyer's stale deletion notice.
7. **Clearing `auto_release_at`** on the affected sandbox transfers.
8. **Enabling the push key**, in the Vault or anywhere else, and the handset push matrix that depends on it.
9. **Deploying any edge function.**
10. **Requesting any build**, and any handset or device testing. Build 19 stays `f412d10`. New device work happens only if **C proposes a specific safe, non-destructive check** and the owner agrees.
11. **Any merge to `main`** — unaffected by this sprint and still governed by AUTODEPLOY-1: merging to `main` applies pending migrations to production outside CI, so no migration-bearing PR merges until an owner has visually confirmed that path is off.
12. **Reopening any held Line 3 row** (RT6, U1, RT5-P, N1, N2, N4, DV-IMG-4's retry half, DV-IMG-10, HEIC conversion).
13. **Pushing D's `1cacdf5`** or otherwise widening the detection scope.

---

## 6. What is true at close, in one paragraph

Build 19 (`f412d10`) is installed and unchanged. The next candidate head `6561d1f` carries F-BIDS-1 and is green. One reviewed server fix (141) is chosen and applied nowhere. Migration 138 is reviewed, green, unapplied and parked behind six unexercised approvals, with its amendment proposed and unsigned and its detector deliberately narrow. Production has not been touched or read. The sandbox is closed. Two proof files are retained and will not be touched again. Every result in this sprint is recorded at the confidence it was actually earned — passed, failed, blocked, untested or not established — and the two process failures during Line 3 are recorded as failures.

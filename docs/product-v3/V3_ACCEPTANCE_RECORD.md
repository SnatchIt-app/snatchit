# V3 acceptance record (maintained by E)

One row per owner-settled item. Each row pairs the **implementation commit** (C, `v3/midnight-app`)
with the **independent review** (B) **at the same commit**, and lists the native checks still owed.
A row closes only when implementation, B's review and the required native evidence all name the
same commit. "Pending" means not yet evidenced. It does not mean failed.

Evidence classes: **web** = B's web render (development evidence) · **sim** = native simulator
capture on `SN V3 393x852` (iPhone 16, 393×852 pt @3×, UDID `52282259-961E-4A1A-B32B-CEFA858CFF48`,
iOS 26.5 23F77, Xcode 26.6 17F113) · **device** = owner's phone. Neither web nor sim is device
acceptance.

| # | Owner ruling (date) | Governs | Implementation commit | B review (commit · evidence class · file) | Native checks owed | Status |
|---|---|---|---|---|---|---|
| R-1 | **Listing footer, Option B** (2026-09-25). When bidding and Buy Now are both available: Place a bid first, full-width, red, minimum all-in inside; Buy Now second, full-width, outlined, quantity-aware label + price + sub-line. Supersedes the Buy-Now-first hierarchy. Other states keep their own valid actions. Eligibility and behaviour unchanged | `comparisons/footer_arrangements_91062ab1.png` (Option B); map §*SETTLED — listing footer* | `12be25d6`: the resolver (`detailState`) selects the bid as primary when both are available; `ListingDetailScreen.tsx` changes are comments only; per-state tests in `listing-detail-state.test.ts` | Selection render only: `91062ab1` + harness patch · web · `V3_FOOTER_AND_POSTER_91062ab1.md`. **Not** a review of implemented code | Dynamic Type (largest standard + accessibility sizes, no truncation of label, minimum, "Buy … now · $X", sub-line); wrapping; safe area under the stacked footer; Light + Dark | Open |
| R-2 | **Home feature, full 4:5 poster** (2026-09-25). Complete poster in a full-width 4:5 frame, no height cap yet; non-4:5 images fitted without crop or stretch on a deliberate background; name, date, venue, price and listing details in a separate area below the poster; no app text or badges on the poster; overlay gradient removed; header and filter controls unchanged | Owner ruling text; map Home row | `e902f59a`: the poster renders with no children (nothing drawn on it), the slot scrim is `none`, and the identity block is below the poster in canvas inks (E source check). Earlier `ec61bfa7`–`cbb2df6b` still overlaid | pending (B): native renders, Light + Dark, with a text-heavy flyer, a photograph, missing artwork, plus the corner-marker fixtures. Report how much of the next section is visible at 393×852 | Native fonts; safe area; Dynamic Type on the identity block below the poster; System appearance switch | Open |
| R-3 | **Event artwork 4:5 throughout** (2026-09-25, authorised direction). Full poster content preserved; avatars unchanged | Owner direction; E's baseline inventory at `a5c0bfc6` | Group 1 of 4: `ec61bfa7` (media contract: 10 slots at 4:5 + `fit`; requests carry width+height with `resize=contain`; Home and Search frames). Group 2: `99dd6f36` (Create picker no longer crops: `aspect: null`, so no `allowsEditing`; helper "JPG or PNG, 4:5 portrait — any other shape is fitted whole, never cropped."; listing hero frame 4:5 at ~491pt with the identity still overlaid; My listings card). Group 3: `59658b1a` (Bids and Tickets; the past-ticket 64×64 clipping wrapper removed). Group 4: `cbb2df6b` (Send, receive, checkout OrderIdentity, public profile). All four landed; the tree is clean at `cbb2df6b` | pending (B), per slot, including the corner-marker fixtures | Picker behaviour on iOS (no crop that discards poster pixels); per-slot rendering | Open |
| R-4 | **Listing identity beneath the poster** (2026-09-25). The listing's date line, name and provenance label sit below the 4:5 poster; no app text or badges on the poster's printed content; back/overflow navigation stays reachable | Owner ruling; B `V3_FOOTER_AND_POSTER_91062ab1.md` Part 2 | `f3f08930` (`ListingHero`, E source check) | pending (B); native Listing artwork cases blocked until the Listing harness gets `?art=` (see restarted loop) | Scrolling; safe area under navigation chips; Dynamic Type on the moved block; Light + Dark | Open |

## CURRENT ACCEPTANCE STATUS (E, 2026-10-11). THE ONLY CURRENT SUMMARY; every section below is dated history

**Candidate:** app code as of `9bbeaec6`. The last code commit is `6b6b8f48`
(`v3/consumer-batch2`).
- The serving tip is now **`11e50ca0`**, which adds only the capture log and handback note over `10dbcdf4`. `10dbcdf4` itself (`v3/midnight-app`, on origin). Since `9bbeaec6` it adds
  only `native/` frames and **one test file** (`tests/v3-mylistings-bids-stage.test.ts`). App code
  is unchanged, so all evidence below applies.
- **CI on `v3/midnight-app` was red on every push from about 2026-10-07 until `9bbeaec6`.** Recorded
  conclusions: `failure` at `9498080a`, `c11b4a49` and `9bbeaec6`. The cause was a
  timezone-dependent assertion in C's test ML7: green at UTC−4 locally, red on the UTC runner (found
  by A).
  - Fixed in `10dbcdf4` (test only). C reports 3016 passing under `TZ=UTC`.
  - **CI at `10dbcdf4` was `in_progress` when E checked (2026-10-11 ~17:55Z). Green is NOT yet
    evidenced.**
- **C's handback is committed at `11e50ca0`.** The device is shut down and `:8081` is clear (C, and
  E's earlier check). **The simulator is B's.**
- **Lint (C's correction):** the tip has 44 warnings, all pre-existing. C's earlier "29" was stale.
- Both are on origin; E verified with `git ls-remote` on 2026-10-11.
- This record's branch was backed up by B at `6b8080bd` (fast-forward, no rewrite).

**Native development build only. Not whole-app acceptance.** Evidence classes: C-operated captures;
reviews by B and E, each with its own positive-controlled instrument.

### Passed (B and E agree; closed)
- **Home:** artwork per fixture, 4:5 frame, no gradient, nothing on the poster; feed-row and feature
  amounts at a3xl; Filters glyph and icons.
- **Listing:**
  - poster clear of the banner and navigation;
  - event name reachable by scroll (R-4);
  - Option B footer;
  - reservation feedback;
  - scroll-end clearance;
  - bid activity amounts (F-BA);
  - full date and time (F-DT);
  - error and offline states.
- **Profile:** P-1, P-2 and P-3 closed at `12cc3e8d`; P-4 was a fixture problem (`2181de75`); no
  `null%`.
- **W batch at `9bbeaec6`:**
  - W-4 header shrinks to fit at a3xl;
  - S-1 and S-1b row labels;
  - P-5 tier word;
  - W-2 fee labels (resale minimum-bid shows "(10%)"; checkout plain);
  - W-2b sold note.
- **Wording decided under owner delegation:** W-1 "Unrated"; W-2 and its correction; W-2b; W-3
  uppercase chrome labels; W-4; W-5; W-6. They are recorded below and closed.

### Default size after the header change: VERIFIED by kept frames (C `32c0804a`; E independently re-diffed). B's narrow review pending
- **Fresh captures** at the served tip `9bbeaec6`, through `_dev/v3-account` (the real Settings and
  Appearance screens): `native/9bbeaec6/settings-hub-default-{light,dark}` and
  `appearance-default-{light,dark}`, with `capture-log.txt`.
- **Size from the paint:** C fixed the rule in advance from committed frames (max ink band ≤ 30 pt
  means default; ≥ 40 pt means a3xl). The new frames measure 16.3–24.0 pt.
- C discarded two frames that landed on Sign in rather than filing them.
- **E's own diff against the retained `b64e5dd6` frames, both inputs committed:** **0 differing
  pixels below y = 440 in all four.** All differences (1,459–1,857 px) sit in a box
  x 162–266, y 69–106 px, which is the status-bar clock. The new and old files are distinct (different
  md5), so this is not a file compared with itself, and the non-zero clock difference shows the diff
  can detect change.
- **Conclusion:** default-size Settings and Appearance at the final code are pixel-identical below
  the header to `b64e5dd6`, which is before the header fix (`c303eab6` / `1ab2c8e2`) and before
  S-1/S-1b. So W-4, S-1 and S-1b left default size unchanged, **now shown by kept frames.**
- **Still labelled as historical and unverifiable:** the earlier "0 px vs `1ab2c8e2`" claims at
  `e6a38aef` and `1a6ac1c3`, and the `1ab2c8e2/` default frames (byte-identical copies of
  `b64e5dd6`). They are superseded by the above, not retroactively verified.
- **Device:** E verified no booted device and no listener on `:8081` after C's commit.
- **B: the window is yours for a narrow review of these four frames only.**

### Follow-ups, explicitly not release blockers (no concrete loss of information)
- **Badge 1.3× cap** (`Badge.tsx`, shared). The tier word is now also carried in the scaling blurb
  for every branch except lost disputes. Letting Badge scale needs its own sweep.
- **Dispute-branch tier word** (`reputation.ts`). The blurb reads "N lost disputes · P% success"
  without "Needs review". **No information is lost:** the adverse fact is stated in full, scaling
  text. Adding the word is a routine wording change for a later batch.
- **L-2 launch method** (Codex): `preview_start` started Metro outside the guard, and Metro exhausted
  its heap building web bundles.

### Untested by design (do not mark passed; do not ask the owner to repeat)
- **Owner-waived signed-in checks:** authenticated consumer Home; the Edit refusal group; the W-5
  Edit platform picker (parity is test-pinned only).
- **W-6 payout line:** source-pinned only. It needs a connected Stripe account.
- **Spoken VoiceOver:** optional, not a release blocker. The exposed label is verified in source
  only.

### Owner-reported, not personally verified by E
- **The seller-fee production read is complete,** according to A and D. **The historical
  reconciliation is complete,** according to A and D. E has not seen either result. **No owner
  request remains open for either.**
- **Legal text** (`legal.tsx` "10%" statements) stays with the owner. It is not a request from this
  review.

### Coordination
- **Simulator and Metro:** C's window for the four default frames is complete (`32c0804a`); the device
  is released. B may review from the saved frames, with no device needed.
  - Before the window, E verified: no booted device, no listener on `:8081`, no simctl or expo
    process. B's last message released the device.
  - **B: do not touch the device until C commits its handback.** Then review those four frames only.
- **B ↔ E:** B → E works; E → B is refused. This record is the E → B channel.
- **E's relay notes** are preserved at `docs/product-v3/e-relays/`, and E's instrument at
  `docs/product-v3/harness/measure/gutter_e.py`.

## Status snapshot 2026-10-09 evening (SUPERSEDED by the section above; kept as history)

**Candidate and checkpoints (E verified on `/Volumes/DEV-SSD`):**
- **Code candidate: `857e6d93656d1d8126d56ccc22c00505a732fb6a`** (C, 2026-10-09 17:24).
  - It sits on `9498080a` → `c11b4a49` → `2919ba75` → `b2b3e9d9`.
  - The only app-code change since `9498080a` is `app/profile/[id].tsx` (the P-1/P-2 fix), plus the
    new test `tests/v3-profile-trust-a3xl.test.ts`. Everything else is tools, docs or captures.
  - C reports typecheck clean, 176 files / 2998 tests passing with the device down, and 0 lint
    errors. E has not re-run them.
  - **Uncaptured.**
- **Launch-blocker note:** `c45dd762`, then `0a1fb072` (`docs/product-v3/V3_SSD_LAUNCH_BLOCKER.md`).
  `0a1fb072` preserves the L-2 launch command, process provenance, exit 134 and a log excerpt, with
  no environment values. It is docs only; E verified there is no non-doc change since `857e6d93`.
  `0a1fb072` is the head of `v3/midnight-app` in `snatchit-refund`. `v3/consumer-batch2` in `snatchit-v3batch` is at
  `857e6d93`.
- **On origin:** `v3/consumer-batch2` = `9498080a`, `v3/midnight-app` = `c11b4a49`. **`857e6d93` and
  `c45dd762` are local only.**
- **Working change:** `.claude/launch.json` in both C trees is the documented migration change.
- **Latest B review:** batch 9, `a09b2ae0` (`B_NATIVE_REVIEW_b2b3e9d9.md`). It supersedes parts of
  batch 8.
- **Not whole-app acceptance.**

### Window update: P-1/P-2 captured; **simulator and Metro handed to B** (C, `b0d727ce`, 2026-10-09 18:21; E verified)
- **Commits.** `b0d727ce` is the serving-tree tip in `snatchit-refund` and is clean apart from the
  documented `launch.json` edit. The code is unchanged at `857e6d93`: `git diff 857e6d93 b0d727ce`
  touches only `docs/`, `native/`, `tools/` and `scripts/dev-web-guard.sh`.
- **L-1 resolved.** The `dev-web-guard.sh` `WORKTREE` pin now points at the SSD path; that is the
  only line changed (E viewed the diff). C's commit attributes it to Codex's instruction.
- **Guard controls before use (C):** passes from the SSD worktree, refuses from `/tmp`, and refuses
  when an `EXPO_PUBLIC_*` value is pre-exported.
- **Metro (C):** started in a terminal through the guard, not through `preview_start`. Kernel-read
  cwd: the SSD `snatchit-refund`. No web bundle was requested.
- **L-2 is still open:** the `preview_start` bypass and the web-bundling heap exhaustion.
- **Captures (C-operated; B review pending):** `native/857e6d93/` with `capture-log.txt`. They cover
  profile at default and a3xl, Light and Dark: rate, rows and member-since.
  - Per C: at a3xl the rate reads "100%" on one line, and every trust-row value is visible.
  - E viewed `profile-a3xl-light-membersince`: "Member since / February 2026" is whole. That is the
    row B measured at 8,089 px in the gutter.
- **Method findings (C):**
  - `simctl` cannot write screenshots to the external volume (EPERM / NSCocoaError 513). `cap.sh` now
    stages on the internal disk and fails loudly; the first attempt had lost frames silently.
  - `touch_path` was dropped repeatedly on this screen, while `swipe` moved it reliably. Every scroll
    was a swipe, confirmed by frame comparison. That is the second validated gesture the owner asked
    for.
- **P-3 is still visible** in both a3xl rate frames ("14 sale…"). P-3 and the P-4 fixture fix have
  not started.
- **Sequencing (E):**
  1. B reviews P-1/P-2 at `857e6d93` now, and re-confirms the Listing poster clearance once at
     default.
  2. Meanwhile C prepares P-3 and the P-4 fixture in the isolated worktree, without the device.
  3. When C names that sha, one short a3xl profile pass covers P-3 only. P-1/P-2 evidence carries if
     the P-3 diff stays within the blurb element.

### W-2b on the device (`24393d0b`, merged to the serving branch as `7d957100`, evidence `4c8efc9c`; C; E verified)
- **Change:** `TransactionPanel.tsx:80` now reads "Price includes the service fee." beside an
  unchanged "SOLD FOR $132.00 total". Device and Metro released by C.
- **C's own correction, recorded:** the default pixel diff E asked for covered the wrong region. The
  fee sentence is below the fold, so the diff only shows that nothing else moved. **The scrolled
  frame is the proof, not the diff.**
- **C's corrected count** of user-facing 10% claims (C's earlier count came from a grep truncated with
  `head`):
  - W-2 fixed `ListingDetailScreen.tsx` and `TransactionPanel.tsx:136`.
  - W-2b fixed `TransactionPanel.tsx:80`.
  - **Not changed:** `bidEntry.ts:133,143`, the bid confirmation ("…includes the 10% service fee").
  - Legal and payout copy are routed elsewhere.
- **Branch note:** `7d957100` is a **merge**, not a fast-forward. The serving and batch branches
  diverged for the first time. C did not rebase, because `v3/consumer-batch2` is pushed.

### W batch at `9bbeaec6`: B and E reviewed independently and AGREE
- **B's review:** `9c970b05`, `B_NATIVE_REVIEW_9bbeaec6.md`; B pushed it.
- **E correction:** E's review below was written without having seen B's. "B has not reviewed" was
  wrong.
- **B's verdicts:**
  - W-4, S-1/S-1b, P-5, W-2 and W-2b **pass**. That's 24 banner-gated frames, 0 gutter ink, max ink
    x 339.3–376.7 pt.
  - W-5 and W-6 are **not passed**.
- **B's extra findings:**
  1. **Evidence gap.** The default frames in `1ab2c8e2/` are byte-identical copies of the
     `b64e5dd6` frames (C declares this). So C's "the re-shoot differs by zero pixels" claim **can't
     be verified from the committed frames**. B withdraws its own re-run, which compared a file with
     itself. **Default-size "unchanged" for the header change is therefore unverified by frames.**
     Supporting evidence: B's a3xl diff confines the change to the header band, and the default
     branch cannot change by construction.
  2. **P-5 residual.** The dispute branch of `deriveReputation` still doesn't name the tier in the
     blurb. That isn't a regression. The Badge 1.3× cap remains a follow-up.
  3. B also noted that the review list pointed at `24393d0b/`, which doesn't exist on disk. That is
     now corrected to `7d957100/`.

### E review of the W batch at `9bbeaec6` (owner direction 2026-10-11; E, independent of C's figures)
**Instrument:** B's stated method, re-implemented by E.
- Ink is RGB distance from each frame's modal background, below y = 440 px.
- Full-bleed hairlines are excluded by shape (rows ≥95% inked).
- Right gutter is x ∈ [1131, 1178]; thresholds T = 30/45/60/90.
- **Positive control first:** E's instrument reproduced both known failures at `9498080a`: `ratewrap`
  2,600 px and `trustrows` 8,325 px at T = 60. B measured 2,597 and 8,315.

**Results:** 23 frames, **0 px in the gutter at every threshold.** Max ink x is ≤ 377.0 pt.
- The 377.0 pt figure is row dividers that end exactly at the content edge.
- Sets: `1ab2c8e2/` (14 frames), `e6a38aef/` (4), `1a6ac1c3/` (2), `2ada44bd/` (2), `7d957100/` (1).

| Item | E verdict | Evidence (E viewed) |
|---|---|---|
| W-4 Settings header, hub and Appearance | **PASS.** "SETTINGS" and "APPEARANCE" are whole, on one line, at a3xl | `1a6ac1c3/settings-hub-a3xl-dark`, `1ab2c8e2/appearance-a3xl-light` |
| S-1 / S-1b row labels | **PASS.** "Edit / profile" and "Phone / verification" break on words; "Notifications" is whole on one line; chevrons present | `1a6ac1c3/settings-hub-a3xl-dark` |
| P-5 tier word | **PASS.** "Trusted seller · 14 sales · 100% transfer success" wraps on words. The badge remains capped, which is Badge's follow-up | `1ab2c8e2/profile-hero-a3xl-dark` |
| W-2 correction, minimum-bid "(10%)" | **PASS.** "Service fee (10%) $9.50" | `2ada44bd/listing-breakdown-default-light` |
| W-2b sold note | **PASS.** "Price includes the service fee." beside "SOLD FOR $132.00 total" | `7d957100/listing-sold-default-light-Coperated.png` |
| W-5 Edit platform picker | **UNTESTED**: signed-out guard; repeat sign-in owner-waived. Parity is test-pinned only | `…-BLOCKED` frame |
| W-6 payout line | **SOURCE-PINNED, NOT VISUALLY VERIFIED**: needs a connected Stripe account | `2ada44bd/payout-setup-default-light` shows `not_connected` |

**Limits:**
- E reviewed the a3xl frames in the appearances captured, not every appearance at every size.
- Default-size "unchanged" claims rest on C's pixel diffs; E did not re-run them.
- **Not whole-app acceptance.** Signed-in checks remain owner-waived and **are not marked passed.**
- Spoken VoiceOver is **optional and not a release blocker** (owner, 2026-10-11). It is untested.

### W-2 correction implemented: code `6b6b8f48`, merged as `2ada44bd`, evidence `9bbeaec6` (C, 2026-10-09; E verified). **Device and Metro released**
- **Change:** "Service fee (10%) $9.50" is restored on the Listing minimum-bid breakdown and on
  `TransactionPanel`, captured at default **scrolled to the rows**.
- **Built from the constant, not typed:** `RESALE_FEE_LABEL =
  \`Service fee (${Math.round(BUYER_FEE_RATE * 100)}%)\``, at `detailState.ts:58`. That is the same
  pattern as `PlaceBidScreen`'s "Fee (10%)". A test pins the rendered text.
- **E accepts the departure from the literal:** the label can't drift from the rate that computes
  the amount (`listingPriceLinesV3().fee → buyerFeeCents → round(cents × 0.10)`, per C's reading).
- **Unchanged, as intended:** the bid confirmation and bid summary ("10%"); plain checkout and Apple
  Pay; the W-2b sold note; the W-6 payout line.
- **Trap, recorded:** C served with `git merge --ff-only … | tail -1 && … && expo start`. A pipeline
  returns its last command's status, so the refused merge was hidden and Metro served the old code.
  The first frame was discarded after reading HEAD.
- **Branch note:** `2ada44bd` is a second merge commit (no rebase of a pushed branch), for the same
  reason as `7d957100`.
- **Tests (C's report):** typecheck clean, 3015 tests, 0 lint errors, two mutants on the derived
  label.
- **C's item `bidEntry.ts:133,143` is CLOSED:** it keeps "10%" under the W-2 correction.

### B: consolidated review list. Serving tip `9bbeaec6`; code at `6b6b8f48` (all C-operated frames; the device is free)
| Item | Frames (C's repo, `native/<sha>/`) | Status |
|---|---|---|
| W-4 Settings header (hub, Appearance) incl. shrink-to-floor title | `1ab2c8e2/` (default and a3xl, L/D) | **E PASS** (above); B optional |
| S-1 / S-1b SettingsRow labels | `e6a38aef/`, `1a6ac1c3/` (a3xl, L/D) | **E PASS** (above); B optional |
| P-5 tier word in blurb | `1ab2c8e2/profile-hero-*` | **E PASS** (above); B optional |
| W-2 and its correction, fee labels (minimum-bid "(10%)", checkout plain) | `1ab2c8e2/listing-breakdown-*`; restore at `2ada44bd/` (default, scrolled to the rows) | B review owed |
| W-2b sold note | `7d957100/listing-sold-default-light-Coperated.png` (scrolled to the note; path verified by C and E) | **E PASS** (above); B optional |
| W-5 Edit platform picker | `edit-picker-…-BLOCKED` | **untested** (sign-in waived); parity is test-pinned |
| W-6 payout line | `not_connected` frame only | **source-pinned, not visually verified** |

**Default-size claims** for this batch rest on C's pixel diffs; B may re-run them with its own
instrument. **Not whole-app acceptance.**

### W-6 implemented: code `64e2212f`, evidence `e1bbcd66` (C, 2026-10-09; E verified `payout-setup.tsx:162`). **IMPLEMENTED AND SOURCE-PINNED, NOT VISUALLY VERIFIED**
- **Copy:** "…we send your payout (the sale price, less the seller fee and any refund) to your
  Stripe account." Device and Metro released by C.
- **Why not visible:** the sentence is in the `connected` status branch. That status comes from a
  server probe with no fixture seam, so seeing it needs an authenticated account with Stripe
  connected. Repeat sign-in is waived; this is the same boundary as the Edit picker.
- **The kept frame** shows the signed-out `not_connected` state ("SET UP PAYOUTS"). It proves that
  state is undisturbed. **It is not evidence of the new sentence.**
- **Pinned by tests:** P-COPY1 and P-COPY2. Mutants: restoring the rate or dropping the refund clause
  kills P-COPY1; re-promising the payout on the **sale** rather than the **release** kills P-COPY2.
  **A's older "payout on release" ruling was unguarded until this test.**
- **Tests (C's report):** typecheck clean, 3015 tests, 0 lint errors.
- **Still pending from the W-2 correction below:** restoring "(10%)" at `ListingDetailScreen.tsx:1255`
  and `TransactionPanel.tsx:136`. Both still read plain "Service fee" at `e1bbcd66` (E verified). C
  hadn't received the correction when it built W-6.
- **`bidEntry.ts:133,143` is settled by the correction:** the bid confirmation keeps "10%". C still
  lists it as open, so this record answers it.

### CORRECTION by E: W-2 was over-broad. Rescoped under owner delegation (2026-10-09)
**E missed an owner ruling.**
- `PlaceBidScreen.tsx:424` renders the bid summary as `Fee (${BUYER_FEE_RATE×100}%)`, i.e.
  **"Fee (10%)"**. That is the **owner's own ruling** in the original brief: "Bid summary is Bid /
  Fee (10%) / Total above a plain Place bid".
- C's grep didn't catch it, because the rate is computed in a template, not written as "10%".
- E's W-2 rule ("no rate anywhere") removed "(10%)" from the Listing **minimum-bid breakdown**
  (`ListingDetailScreen.tsx:1255`, `TransactionPanel.tsx:136`). That breakdown is part of the same
  bid family as the owner's bid summary. **A delegated wording choice cannot override an explicit
  owner ruling.**

**Rescoped rule:**
- **Option A, chosen:** state the rate on **resale bid surfaces whose figure is the client's 10%
  calculation.**
  - The bid summary keeps "Fee (10%)", per the owner's ruling.
  - The bid confirmation, `bidEntry.ts:133,143`, stays unchanged.
  - The Listing minimum-bid breakdown is **restored** to "Service fee (10%)".
  - **Plain "Service fee" where the figure comes from the server and could be either rail**: the
    in-app checkout and the Apple Pay sheet.
  - The **sold note** stays plain (W-2b). It describes a completed charge, and no rate is needed.
- **Option B, rejected:** no rate anywhere. It would override the owner's explicit bid-summary
  ruling.
- **Why A is accurate:** A confirmed that resale is unconditionally `round(10% × base)`, and bid
  surfaces are resale-only. The checkout is the only in-app fee surface that can carry a
  primary-rail fee.
- **C implements:** restore "(10%)" at `ListingDetailScreen.tsx:1255` and `TransactionPanel.tsx:136`
  only. Copy only, no amount change.

### S-1b implemented: code `1a6ac1c3`, evidence `e1ed4226` (C, 2026-10-09; E verified; **device and Metro released by C**)
- **Change:** `SettingsRow.tsx` only. A label with no whitespace gets one line and shrink-to-fit; a
  label with whitespace keeps two lines at full size. Below the threshold neither changes (SR1, SR6).
- **Frames:** `native/1a6ac1c3/settings-hub-a3xl-{light,dark}`. Per C, "Notifications" is whole on
  one line and slightly smaller, the other labels keep full size, and every chevron is present.
  Default size matches `1ab2c8e2` by pixel diff (0 differing pixels below the header).
- **Tests (C's report):** typecheck clean, 3013 tests with the simulator shut down, 0 lint errors,
  4 mutants.
  - **Trap, recorded:** inverting the stacked branch killed 4 tests instead of 1, because the
    ternary's false branch is shared with the default-size case.
- **Evidence trail:** C's capture log at `e1ed4226` records all three attempts at S-1. Each passed
  its tests, and each of the first two was rejected by a frame.
- **State:** E verified no listener on `:8081` and no booted device. The serving tree is
  `e1ed4226`, clean apart from the documented `launch.json`.

**Remaining "10%" statements, found by C and E (source search at `e1ed4226`):**
- **W-2b, decided under owner delegation.** `TransactionPanel.tsx:80`, shown in the sold state:
  "Price includes the 10% service fee."
  - **Option A:** "Price includes the service fee."
  - **Option B:** keep "10%". That is true on the resale rail, which is the only rail a Listing shows
    today.
  - **Chosen: A**, for consistency with W-2's rule that buyer-fee labels state no rate. **C
    implements**: copy only, no change to any amount.
- **Not decided by E; recorded for the right owner:**
  - `app/settings/legal.tsx:94,211-212` ("A 10% service fee… a 10% marketplace fee…") is **legal
    text, which stays with the owner.**
  - `app/settings/payout-setup.tsx:159`: **decided as W-6**, below.
  - `src/lib/bid/bidEntry.ts:60` is a code comment only.

**W-6, payout copy (`payout-setup.tsx:159`), DECIDED under owner delegation.** A answered from code
at gate `abef9506`, with no production reads.
- **What A confirmed:** only resale payouts reach this screen. The primary rail has no individual
  seller (`seller_id` NULL, `seller_fee` 0, and 093's rail CHECK). The resale `seller_fee` is written
  as `round(base × 0.10)` and frozen on success.
- **What A cannot confirm:** `claim_payout_attempt` pays `amount − coalesce(seller_fee, 0)`. A live
  row with a NULL `seller_fee` would pay out with no fee withheld, and A's records don't rule that
  out. A also notes that after a partial refund the payout is not "sale price minus fee".
- **Option A:** "…we send your payout (the sale price minus the seller fee) to your Stripe account."
- **Option B:** "…we send your payout (the sale price, less the seller fee and any refund) to your
  Stripe account."
- **Chosen: B.** It drops the rate A can't confirm for every row, and it stays literally true in the
  partial-refund case A identified. Copy only; **C implements.**

**Backend data question raised by A: CLOSED (owner, 2026-10-11).** The question was whether any
live, unpaid `payments` row had a NULL or non-10% `seller_fee`. The owner reports that the seller-fee
production read is **complete, according to A and D**. E has not seen the read's result. The owner
request is removed. W-6's copy is unaffected.

**P-5 note:** the badge's 1.3× cap is `Badge`'s own limitation, a separate follow-up that has not
been adopted. `reputation.ts` now carries the tier word, so no information is lost.

### S-1 fixed for multi-word labels: code `e6a38aef`, evidence `b18d1f47` (C, 2026-10-09; E verified; **device and Metro released by C**)
- **Chain:** `a98389fc` (wrap; C's window declared there) → `e6a38aef` (two lines plus
  shrink-to-fit), changing `src/components/account/SettingsRow.tsx` only. Evidence commits:
  `c6164048`, `96c66452` (intermediate sets kept) and `b18d1f47` (the frame that rejected the first
  fix).
- **Tests (C's report):** typecheck clean, 3011 tests with the simulator shut down, 0 lint errors.
  Mutants SR1, SR2 and SR3 were each predicted and matched.
- **Frames:** 4 in `native/e6a38aef/`: hub and Appearance at a3xl, Light and Dark. Default size
  matches `1ab2c8e2` by pixel diff (0 differing pixels below the header).
- **State:** E verified no listener on `:8081` and no booted device. The serving tree is
  `b18d1f47`, clean apart from the documented `launch.json`. B's six `-Boperated` files remain
  untouched.
- **Fixed:** multi-word labels now wrap on words with the chevron kept. E viewed
  `settings-hub-a3xl-light`: "Edit / profile" and "Phone / verification" read in full. The
  accessibility label is unchanged.
- **Not fixed: S-1b, single-word labels.** "Notifications" still breaks mid-word at a3xl
  ("Notificatio / ns"; E viewed it). Shrink stops once the broken form fits two lines.
- **Pattern, recorded:** at a3xl, wrapping fixes only text that contains spaces. This is the third
  occurrence in the batch (profile blurb, header title, row label). A single long word needs shrink,
  or shorter copy.

**S-1b DECIDED under owner delegation:**
- **Option A:** a label with no space takes one line plus shrink-to-fit, as the header title does at
  `1ab2c8e2`. Multi-word labels keep two-line wrapping. Only words that cannot break shrink, and
  only by as much as they need.
- **Option B:** shorter copy for that row (e.g. "Alerts"). This changes an established term that
  the Notifications sub-screen and other surfaces also use.
- **Option C (C's, rejected):** one line with heavy shrink for every row. It would shrink all labels
  below the requested size to fix one word.
- **Chosen: A.** It keeps the wording, confines the shrink to the labels that cannot wrap, and reuses
  the title treatment already applied.
- **C implements; B reviews it at a3xl, Light and Dark.**

### W batch complete: code `1ab2c8e2`, evidence `db58c433` (C, 2026-10-09; E verified; **device and Metro released by C**)
- **Chain:** `58306942` (W-4, W-5) → `b64e5dd6` (P-5, W-2) → `c303eab6` → `1ab2c8e2` (Settings
  header fix, in two steps). `db58c433` adds 15 frames in `native/1ab2c8e2/` with `capture-log.txt`,
  and no code change.
- **Code files since `834be7ab`:** `app/listing/edit/[id].tsx`, `app/settings/{index,appearance}.tsx`,
  `src/components/account/SettingsHeader.tsx`, `src/components/listing/TransactionPanel.tsx`,
  `src/lib/listing/ticketPlatforms.ts`, `src/lib/profile/reputation.ts`,
  `src/screens/CreateListingScreen.tsx`, `src/screens/ListingDetailScreen.tsx`.
- **Tests:** C reports 3007 passing, typecheck clean, 0 lint errors.
- **Serving tree:** `db58c433`, clean apart from the documented `launch.json`. E verified: no
  listener on `:8081`, no booted device.
- **Uncommitted files in C's tree:** B's six `-Boperated` frames in `native/12cc3e8d/` (B has
  committed copies at `19faf133` in `snatchit-audit`), and C's intermediate `native/b64e5dd6/` and
  `native/c303eab6/`. **Nobody deletes another session's files on a relayed instruction.** B decides
  about its own.
- **The captures changed the code twice.**
  1. W-4 put the shared `SettingsHeader` on the hub and Appearance. At a3xl the title clipped
     ("SETTIN…", "APPEA…"). `privacy.tsx` showed it already clipped ("PRIVAC…"), so the clip belongs
     to the shared header on all 11 screens, and W-4 extended it to two screens.
  2. C's first fix wrapped the title, giving "SETTING / S". **Fix at `1ab2c8e2`:** the title keeps
     one line and shrinks to the floor.
  - E viewed `settings-hub-a3xl-light`: "SETTINGS" is whole.
  - The fix is in the shared `SettingsHeader`, so it applies to all 11 settings screens.
- **W-2 on the device:** "Service fee $9.50" with no rate, at default and a3xl.
- **P-5 on the device:** "Trusted seller · 14 sales · 100% transfer success" beside the small badge
  at a3xl. At default, the longer blurb fits its two-line, 150 pt column (trusted branch captured;
  the other branches are arithmetically similar and **not shot**).
- **W-5 on the device: BLOCKED.** Signed out, Edit renders "Sign in required" before any variant;
  the frame is kept as `edit-picker-default-light-BLOCKED`. Repeat sign-in is waived, so **the
  picker is untested visually**. W-5 rests on the test that parses migration 033 against the shared
  constant (implementation evidence).
- **Default-size frames** were taken at `b64e5dd6`. C reports a re-shoot at `1ab2c8e2` differs by 0
  pixels below the header (B's technique).
- **Contention diagnosis:** C accepts B's correction. With B off the device the size held for 160 s
  across 8 samples. C's "~30 s reset" claim is removed from `tools/v3-capture/README.md`.

**NEW DEFECT S-1, for C (E confirms from `settings-hub-a3xl-light`; B to review):**
- Every `SettingsRow` label clips at a3xl: "Edit prof…", "Notificat…", "Phone v…", "Payout s…".
  It is pre-existing, and affects the hub and all ten sub-screens.
- These labels are the navigation, so a reader at a3xl cannot tell rows apart. **Defect, not an
  owner choice.**
- **Fix:** labels wrap on words, with the chevron kept, the same rule as the rest of the batch. Lists
  a3xl Light and Dark, the hub plus one sub-screen.

**B review owed at `1ab2c8e2`** (C-operated frames):
- Settings hub and Appearance (default and a3xl, Light and Dark), including the shrink-to-floor title.
- Listing breakdown (W-2).
- Profile hero (P-5).
- Then S-1, after C's fix.

### W batch, part 1: `58306942` (C, isolated worktree `v3/consumer-batch2`; not served; E verified the files)
- **Base:** `834be7ab`. C reports typecheck clean, 3005 tests passing and 0 lint errors.
- **Files:** `app/listing/edit/[id].tsx`, `app/settings/{index,appearance}.tsx`,
  `src/lib/listing/ticketPlatforms.ts`, `src/screens/CreateListingScreen.tsx`, and tests and docs
  (`docs/product-v3/V3_WORDING_W3_W4_W5.md`).
- **W-5:** one constant, `ticketPlatforms.ts`, read by both Create and Edit. The parity test parses
  migration 033 and asserts the constant equals `listings_ticket_platform_check` exactly.
- **W-4: visible consequences of the chosen option, for B to review.**
  1. The hub's back control loses its circular chip, because `SettingsHeader` renders `IconButton`
     without `chip`.
  2. The hub title becomes uppercase Oswald ("SETTINGS"), from `displaySm`.
  - Old tests were re-pointed, not deleted; there is a negative test against the hub regrowing its
    own chip.
  - **Record correction (C):** nine sub-screens used `SettingsHeader`, not ten.
    `app/settings/appearance.tsx` hand-rolled the same chip and title, and C **converted it too**.
    `verify-phone.tsx` is an eleventh screen that already conformed.
  - **E accepts converting Appearance as within W-4.** Leaving it would defeat W-4's purpose. It is
    a one-file revert if anyone objects.
- **W-3:** no change needed. C found every uppercase string is chrome or an eyebrow; none is content
  or a sentence. The full list is in C's doc.
- **Method note (C):** a mutant that deleted the `<SettingsHeader` element but kept its import
  passed C's first check, because the check matched the bare name. The assertion was tightened.
- **Not yet in it:** W-2 (resolved: plain "Service fee"; C hadn't received that when it built this)
  and P-5 (tier word in the blurb).
- **Device:** B released it (B's message, recorded at `66cf4004`; last simctl 19:12:59). It is
  **booted but idle**, and `:8081` has no listener (E check).
  - **The next window is C's,** declared here: C serves the final W sha and captures.
  - **B reviews afterwards:** the Settings hub **and Appearance** at default and a3xl, Light and Dark;
    the Edit platform picker; the Listing breakdown (W-2); the profile hero at a3xl (P-5).

### Profile batch closed at `12cc3e8d` (B `19faf133`, `6b7137f2`, `069eeb9c`; E verified that all three are on the audit branch)
- **Identity, settled by the round trip.** B states that `COPPER-LANTERN-377` was invented by B in
  that message. It arrived with `from="local_228f989e-…"`, so **that session is B.** B withdraws its
  "different B" account. **E → B is still refused** (exact error above), so the channel is **not
  bidirectional** and this record remains the E → B channel. B reads it.
- **P-3: CLOSED at `12cc3e8d`** (B measured C's three a3xl frames with the same instrument and four
  thresholds).
  - Gutter: 0 px content ink in all three. Max ink x: 361.3 / 348.0 / 348.0 pt.
  - The header hairline at y = 553 px confirms a3xl from the paint, not a readback.
  - "TRANSFER / SUCCESS RATE" and the blurb break on whole words, in both appearances.
- **P-1, P-2, P-3 are closed for the profile batch. P-4** is a fixture correction (`2181de75`).
  **This is the profile batch only, not whole-app acceptance.**
- **Default layout unchanged, shown by a diff, not by citation.** B's default frames at `12cc3e8d`
  against C's at `857e6d93`: **0 differing pixels below y = 440 px**, Light and Dark. The only
  whole-frame differences are the status bar (clock, battery).
  - B's `-Boperated` frames are now committed with provenance in `19faf133`, at repo-root
    `native/12cc3e8d/` in `snatchit-audit`. C's three a3xl frames are copied there too.
- **B re-checked its own a3xl frames by the paint.** The header hairline sits at 553 px at a3xl and
  417 px at default and 3xl, so all twelve a3xl frames are genuinely a3xl.
  - B's two 3xl frames paint the stacked form (so fontScale ≥ 1.3) at 417 px, which places them above
    default and below a3xl.
  - B notes the hairline does **not** separate default from 3xl.
- **Size collision, corrected diagnosis.** It was contention: each operator read back the other's
  writes. B withdraws its "content size reverts across relaunch" finding and C's ~30 s-reset theory
  is unnecessary. **B accepts the overlap was B's:** B didn't re-check before touching the device.
  - The rule stands: **one operator at a time, declared before use.**
  - The appearance trap stands: `simctl ui appearance` doesn't drive the app; the route must carry
    `?appearance=`.
- **Device and server: RELEASED by B.** B's last simctl use was at 19:12:59. Metro is stopped (E
  verified: no listener on `:8081`).

### P-5: reputation badge capped at 1.3× (B `069eeb9c`; E verified `Badge.tsx`). DECIDED under owner delegation
- **Finding (B, measured on `profile-a3xl-dark-hero`):** the "Trusted seller" label paints at
  16.3 pt beside the 35.0 pt blurb (0.47×).
  - Cause: `src/components/ui/Badge.tsx` sets `maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}`
    (1.3) and `numberOfLines={1}`.
- **Information loss:** for trusted, top and elite, and for `needs_review` from a low rate, the blurb
  doesn't restate the tier. **So "Needs review", the only adverse signal on that panel, is carried
  only by the capped badge** (colour is not a carrier).
- **B's judgement:** readable, but not acceptable as the accessibility answer at a3xl. Not a blocker
  for `12cc3e8d`: the cap is pre-existing and Badge is shared.
- **Options:**
  - **A:** carry the tier word in the scaling blurb for those four `deriveReputation` branches, e.g.
    "Needs review · 82% transfer success" and "Trusted seller · 14 sales · 100% transfer success".
    This touches `reputation.ts` only. The badge is unchanged.
  - **B:** let `Badge` scale, which means a sweep of every call site (identity block and other
    screens).
- **Chosen: A.** It removes the information loss now, in one file, with no change to the shared
  component's other screens. The wording only restates what the badge already says.
  - **Option B is recorded as a separate follow-up, not adopted.** The 1.3× badge cap remains a known
    limitation on every Badge.

### Wording and product choices: DECIDED by E under owner delegation (2026-10-09)
The owner delegated these decisions: two options each, E recommends one, and the recommendation is
adopted without a further owner reply. No business rule or capability changes. C implements, and B
reviews the rendered result. **Until then, each one is decided but not yet implemented or
verified.**

| # | Choice | Option A | Option B | **Chosen**, and why |
|---|---|---|---|---|
| W-1 | Seller with sales but no terminal-transfer rate (`reputation.ts`, unreachable from the current RPC) | **"Unrated"**, blurb "N sales · transfer success unavailable", tier `new_seller` (neutral tone) | "New seller", blurb "No transfer rate yet" | **A.** It claims neither newness, which the sales count beside it would contradict, nor failure. It is already implemented in `01c236b2`; no change is needed |
| W-2 | Fee label: Listing says "Service fee (10%)", checkout and the Apple Pay sheet say "Service fee" | **"Service fee (10%)"** everywhere the buyer fee is itemised in-app (Listing, TransactionPanel, CheckoutView). The Apple Pay sheet keeps "Service fee" | Plain "Service fee" everywhere, dropping "(10%)" from Listing | **A, conditional.** It states how the fee is computed, at the same point everywhere. **Condition:** the in-app checkout shows the **server's** `buyer_fee`, not the client constant. So "(10%)" may appear there only if A confirms the server always charges `round(10% × amount)` (client constant `BUYER_FEE_RATE = 0.10`, `packages/core/src/money.ts:16`). **If A cannot confirm, B is chosen**, because the label must never state a rate the charged amount might not match |
| W-3 | All-caps `label` token (CURRENT BID, TOTAL, HELD FOR YOU, TRANSFER SUCCESS RATE) | **Keep the uppercase `label` token** for short chrome and eyebrow labels only. Names, venues, values, instructions and sentences are never uppercased | Make the `label` token sentence case app-wide | **A.** The approved 2026-09-22 typography ruling forbids uppercasing **content** (names are preserved as typed) and keeps the display tokens uppercase; these labels are chrome. B would change every approved surface for no rule. Any uppercase string that is a sentence or content is a defect under A |
| W-4 | Settings header: the hub uses an inline sentence-case title with a chip back button; 10 sub-screens use `SettingsHeader` (uppercase Oswald) | **The hub adopts `SettingsHeader`** | The 10 sub-screens adopt the hub's inline style | **A.** One component, one change, and it matches the app's other screen titles (Profile renders "PROFILE" in the same treatment) |
| W-5 | Edit-listing platform list: Edit offers 6, Create offers 16 | **Edit uses the same 16-platform list as Create**, from one shared constant | Keep Edit at 6 | **A.** The database check `listings_ticket_platform_check` was expanded "6 → 16 confirmed platforms" in migration `033`, and Create already offers those 16. With B, a listing created as e.g. StubHub cannot show or keep its own platform in Edit. No new platform is invented |

**W-2 RESOLVED → Option B (plain "Service fee" everywhere)** (A, 2026-10-09; from code at gate
`abef9506` and the production function list; no new production reads):
- **Resale** (`create-payment-intent`, buy-now and auction): `round(0.10 × base)`, unconditional
  (`supabase/functions/_shared/money.ts:28,38-41`; `create-payment-intent:713-720`).
- **Venue primary rail** (`primary-checkout`, `payments.mode = 'native_primary'`): `buyer_fee` comes
  from the order's own `buyer_fee_minor`. The file explicitly forbids the 10% helper
  (`primary-checkout/index.ts:80-83`).
- So "(10%)" is **not** true for every payment type. By the stated rule, **drop "(10%)" from
  Listing (`ListingDetailScreen.tsx:1255`) and `TransactionPanel.tsx:136`**. The label is "Service
  fee" everywhere. The fee amounts are unchanged.
- **A's limits:** source was read at the gate, not the deployed v48 bundle. `primary-checkout` was
  absent from today's production function list, and venue ticketing is not authorised. Scoping
  "(10%)" to resale-only surfaces would be a separate owner decision; **not proposed**.

**Implementation (C, isolated worktree; then one serve and capture for B):**
- W-2 after A's answer;
- W-4;
- W-5: a single exported constant, with a test asserting parity with Create and with 033's list;
- W-1 and W-3 need no code change. Under W-3, C lists any uppercase string that is content or a
  sentence.

### Owner access waiver (2026-10-09). Recorded separately; **NOT passed**
- **Owner-reported access:** the owner reports having signed in successfully before. That is the
  owner's statement; no session in this review has verified it.
- **Waived, unverified checks:** a repeat owner sign-in session for **authenticated consumer Home**
  (dock, real feed, consumer next-section figure) and the **Edit-listing refusal group**. These are
  **waived by the owner, not tested.** They are not marked passed, and the owner will not be asked
  to repeat them.
- **Not waived:** spoken VoiceOver remains untested (no inspector).

### B's measurement of P-1/P-2 (`12a98bdc`, `B_NATIVE_REVIEW_857e6d93.md`, 2026-10-09 18:50)
**P-1 and P-2 are CLOSED at `857e6d93`** (C-operated frames, measured by B with its own
instrument; B did not use the simulator for this review).

**Method:**
- **Ink:** RGB distance from each frame's own modal background, below the header (y > 440 px).
- **Thresholds:** reported at four (T = 30/45/60/90) to show the result doesn't depend on the
  threshold chosen.
- **Positive control first:** B reproduced the failures on the `9498080a` frames. P-1 `ratewrap`:
  2,597 px at 392.7 pt. P-2 `trustrows`: 8,315 px at 392.7 pt.
- **Header hairline:** the 144 px every a3xl frame returns is the full-bleed header hairline. B
  excluded it by its shape, not by raising the threshold.
- **Frame identity:** 9 distinct md5s; banner present.

**Result:** zero content ink in the right gutter in all nine frames, at every threshold. Max ink x is
364.7–376.7 pt, inside the 377 pt edge. This agrees with C's figures.

**Instrument files:** B's `scratchpad/gutter.py` and `hairline.py` are in a scratchpad, not in the
repo. The method is stated in full in B's review, so it can be reproduced.

**Hero word-breaking at a3xl: B judges it unacceptable.**
- The left column breaks "TRANSFER" mid-word in both appearances at `857e6d93`. The unclamped blurb
  (P-3, `9a564cc5`) would wrap the same way in its 150 pt column.
- B's fix: stack the hero above the shared `identityStacks` threshold. Default size stays as it is.
- **Implemented by C at `12cc3e8d`**, after `9a564cc5`. Only `app/profile/[id].tsx` and its test
  changed. Above the threshold the badge and blurb drop below the rate; the default two-column form
  is untouched (PT7).
- C's commit cites "the owner's ruling": complete text is not enough if the layout makes it hard to
  read. **E has not seen that ruling directly.** Both B and C cite the same standard.
- C reports typecheck clean, 3000 tests with the simulator shut down, and 0 lint errors.
- Only the hero needs re-capturing; the P-1/P-2 row evidence carries.

**Serving tree:** `snatchit-refund` @ `12cc3e8d`, uncaptured, clean apart from the documented
`launch.json`.

### Stacked hero captured at `12cc3e8d`; **device released by C** (`834be7ab`, 2026-10-09 ~19:16; E verified)
- **Commit:** `834be7ab` is the serving tip and adds evidence and tools only; no code change since
  `12cc3e8d`. Files: `native/12cc3e8d/capture-log-C.txt`, 3 frames, and `tools/v3-capture/`
  (`README.md`, new `fastshot.sh`). B's 6 uncommitted `-Boperated` frames were left untouched.
- **Frames (C-operated; B measurement pending):**
  - `profile-a3xl-light-hero`, `profile-a3xl-light-blurb`, `profile-a3xl-dark-hero`.
  - C's measurement: 0 px in the gutter; max ink x 361.3 / 348.0 / 348.0 pt.
  - C did not re-shoot default size. C cites B's `profile-default-{light,dark}-Boperated` as showing
    the two-column hero unchanged; those frames are uncommitted and have no recorded provenance.
- **E view check of `profile-a3xl-dark-hero`:**
  - "TRANSFER / SUCCESS RATE" and "100%" are each whole; there is no mid-word break.
  - "Trusted seller" badge sits below the rate; the blurb "14 sales · 100% / transfer / success"
    wraps on word boundaries.
  - **E note for B:** the "Trusted seller" badge label renders far smaller than the surrounding a3xl
    text. That may be a display-scale cap on the badge. B judges whether it is readable enough.
- **C's answers to B's two questions (from the frames):**
  1. "TRANSFER" no longer breaks.
  2. The rate block doesn't collapse under `heroLeft`'s `flex: 1`, so `heroLeftStacked` isn't
     needed.
- **Capture traps, now in `tools/v3-capture/README.md`:**
  - `simctl ui appearance` does not drive the app's theme; the route parameter must carry it.
  - The content size was reset during the window, and the app reads it at launch. So a before/after
    size read can both say a3xl while the screen painted at default size.
  - **The decisive check is the paint:** at a3xl, ink bands are about 145–158 px tall; at default
    they are 60–92 px. C discarded several frames on that test.
  - `fastshot.sh` polls and takes about 15 s, instead of `shot.sh`'s fixed 42 s sleep.
- **Cause of the size changes (C's revised view):** B was capturing the hero at **3xl**. The
  uncommitted `profile-3xl-{light,dark}-hero-Boperated.png` were written at 19:09 and 19:12, and 3xl
  is the value C's device kept reverting to. C also describes a ~30 s reset. **Both explanations are
  C's; neither is confirmed by B.**
- **Exclusive-window request: WITHDRAWN** (C is off the device).
- **The device is B's.**
- **B should also re-check its own a3xl-labelled `-Boperated` frames by the paint**, given the
  collision.
- **Commits now:**
  - code: `12cc3e8d` (hero stacks), on `9a564cc5` (P-3 blurb) and `2181de75` (P-4 fixture);
  - evidence: `834be7ab` (hero) and `6d54d10f` (P-1/P-2 at `857e6d93`).

### Simulator conflict, 2026-10-09 (~18:56–19:04)
- **What C observed:** the device's content size changed while C was capturing. C set a3xl and later
  read back "large", then "extra-extra-extra-large". C discarded every affected frame.
- **E finding:** four **uncommitted** files in `snatchit-refund/native/12cc3e8d/`, named
  `profile-{default,a3xl}-{light,dark}{,-top}-Boperated.png`, were written at 18:56–19:00. **This
  indicates B was operating the device at the same time.** B's measurement review states it used no
  simulator, so these frames come from a separate B pass.
- E did no simctl use at any time, and no simctl process was running when E checked.
- **Rule from now on:** one operator at a time on device `52282259-…48`, declared before use.
- **C requests about 15 minutes of exclusive use** for two frames: the stacked hero at `12cc3e8d`,
  a3xl, Light and Dark. C reads the size before and after each frame and discards any frame whose
  two reads disagree. **B: please stop all simctl use on that device until C posts "done".**
- B's four `-Boperated` frames are B's own; their provenance (sha served at capture time, size
  read-back) is not recorded. They aren't cited as evidence until B commits them with that.

### Coordination channel with B (owner, 2026-10-09). **NOT established as bidirectional**
**What the messaging tool's sender metadata shows:** every message E has received from B carries
`from="local_228f989e-3ff8-449f-9e2b-823cf93637e1"` and `name="Claude B AWS/PFA-18C"`.

**What B has said about itself:**
- B's first message said it is "a different session" from AWS/PFA-18C and gave
  `local_cafa0b40-…`.
- B's second message withdrew that id as invented.
- B has not said whether the "different session" statement still stands.

**What is not settled:** whether the sender `local_228f989e…` is the session that authored the audit
commits (`605e35ad`, `a09b2ae0`). Every audit commit's author is `SnatchIt-app`, so commits can't
attribute a session. The title and the activity time are **not** proof.

**E → B delivery:** every attempt was refused with the same error:
`Message not delivered: session local_228f989e-3ff8-449f-9e2b-823cf93637e1 cannot receive messages (a remote orchestrator runs it, or nobody opened it); messages can't be delivered there.`
`local_cafa0b40-…` returned `not found`. E is not retrying. A restart is untested.

**Round-trip test (owner):**
1. **B** sends E a unique short phrase.
2. **E** replies to that message's actual `from` sender, quoting the phrase.
3. **B** confirms receipt of E's reply.

Only after step 3 is the channel marked bidirectional. If E's reply is refused, E records the exact
error here and the record stays the update channel. **B: please start with step 1.**

**Round-trip attempt, 2026-10-09 (one attempt, as agreed):**
- **Step 1, done.** B sent the phrase `COPPER-LANTERN-377`. Tool sender metadata:
  `from="local_228f989e-3ff8-449f-9e2b-823cf93637e1"`, `name="Claude B AWS/PFA-18C"`.
- **Step 2, refused.** E replied to that sender, quoting `COPPER-LANTERN-377`. Exact error:
  `Not delivered to Claude Desktop session local_228f989e-3ff8-449f-9e2b-823cf93637e1: Message not delivered: session local_228f989e-3ff8-449f-9e2b-823cf93637e1 cannot receive messages (a remote orchestrator runs it, or nobody opened it); messages can't be delivered there. (delivery: undelivered; message_id: a7f16e0b-597d-48ca-a0c7-3787c48f9be6)`
- **Result:** B → E is verified; **E → B is not**. The channel is **not bidirectional**. E is not
  retrying. **This record is the E → B channel:** B, your phrase is quoted back here.

**Until then, this record is the channel to B.** Routine updates go here, not through the owner.

**Listing poster clearance:** reported complete; B's batch 9 carries it. **No further recheck**
unless a new change touches `ListingHero` or the Listing layout (owner, 2026-10-09). E's earlier
recheck request is withdrawn.

### Capture set completed and P-3/P-4 prepared (C, 2026-10-09; E verified)
- **`6d54d10f`** (serving tip): 2 Dark frames refilled against `857e6d93` (`salesrows`,
  `activelistings`); the first pass had overwritten an intermediate frame. **9 frames in total**
  (C-operated; B review pending).
  - **C's measurement for B to check:** 0 px inside the 377 pt content edge in all nine; max ink
    364.7–376.3 pt. B's failing figures were 2,257 px and 8,089 px at 392.7 pt.
  - **C's method note:** C's first measurement used a fixed threshold, counted the background, and
    returned an identical 101,568 px / 392.7 pt for every frame (the screen edge). C discarded it as
    an instrument fault and measured deviation from each frame's own modal background instead.
- **P-4 fixture: `2181de75`.** `TRUST_NO_RATE` now has `completed_sales: 0`, plus the sibling counts
  that would be impossible beside a zero denominator. HV17b asserts the invariant.
- **P-3: `9a564cc5`** (batch tip, not served). E verified the only screen change is the blurb's
  `numberOfLines={stackRows ? undefined : 2}`: unclamped above the threshold, two lines at default.
  **P-1/P-2 evidence carries** (the diff stays inside the blurb element).
- **Decision flagged by C, not taken:** the hero's right column stays pinned at 150 pt, so at a3xl
  the unclamped blurb wraps narrowly and breaks words. The text is complete, which is what P-3 was
  about.
  - If B judges the wrapping unacceptable, the consistent fix is to stack the hero. That moves the
    badge out from beside the rate, so it is a layout change, and it would invalidate the hero frames.
  - **B judges first. If B wants stacking, it is an owner layout decision.**
- **Validation (C's report):** typecheck clean; 2999 tests with the simulator shut down; lint 0
  errors. Mutants: HV17b and PT6 each predicted and matched.
- **Painted-result test:** C has agreed to B's proposal of one test asserting no ink past the 377 pt
  content edge at a3xl across every two-column row, and has asked B for its pixel arithmetic.
- **State:** Metro stopped; simulator shut down; `snatchit-refund` at `6d54d10f`, clean apart from
  the documented `launch.json`. **The window is B's.** Next: B measures the 9 frames, then one short a3xl rate-hero pass at `9a564cc5`, Light and Dark, for P-3.

### 1. Passed: evidence that still applies to `857e6d93`
None of these depends on `app/profile/[id].tsx`, so all carry.

| Check | Evidence |
|---|---|
| Home artwork per fixture (7 cases), 4:5 frame, no gradient, nothing on the poster | B `c9d6f0d7` @ `d5217530` |
| Listing artwork cases (`flyer`, `missing`, `subject-wide`); poster clear of banner and navigation | B `f235ddb7`/`17c7e670`/`a4e546d0`. `ListingHero` has changed since in the date line only (`b0d74799`); **B re-confirms clearance once at default** |
| Filters glyph, vector icons | B `f235ddb7` |
| Option B footer at rest; reservation feedback; footer complete at a3xl with four-figure CTAs | B `f235ddb7`, `a4e546d0`, `605e35ad` |
| Listing scroll-end clearance; event name reachable by scroll (R-4) | B `e1c5f38e` |
| **Feed-row amounts** at a3xl (63.7 pt; `$1,716.00` 58.0 pt) | C-operated, B-reviewed `e1c5f38e` |
| **Home main-event (feature) amount** at a3xl (`$1,287.00` whole). **Separate** from the feed-row evidence | C-operated, B-reviewed `605e35ad`/`a09b2ae0`; Light only |
| Bid-activity amount (F-BA), ordinary and four-figure; full date/time (F-DT) | B `605e35ad`/`a09b2ae0` |
| Profile prints no `null` | B `605e35ad`/`a09b2ae0` |
| Listing error/offline; profile stats-unavailable and not-found | B `a1af6499` |
| Home drag: **not a product defect** (3 of 4 scrolled; three automation causes, each controlled) | C `c11b4a49`, B accepted `a09b2ae0` |
| Feed-row title, date and bid-count shortening | acceptable list shortening (owner rule) |

**Artwork coverage, stated exactly.**
- **Carries:** Home (all 7 fixtures) and Listing (`flyer`, `missing`, `subject-wide`), from B's
  native captures.
- **Untested:** `?art=` on the **six list harnesses** (My listings, Bids, Tickets, Order/Send,
  Checkout, Search). It arrived in `a587d2a1`, and no B or native render of those screens with
  artwork exists. B's batch 9 phrase "artwork fixture coverage" carries the Home/Listing evidence
  only; there is no list-harness evidence to carry.

### 2. Confirmed defects: fix implemented, awaiting capture and B's review
| ID | Defect | State |
|---|---|---|
| **P-1** | Profile trust rate splits across lines at a3xl ("10 / 0 / %"), ink to x=392.7 pt | **Still a confirmed visual defect** until B reviews captures. Fix in `857e6d93`: bounded to one line, shrinks to a floor |
| **P-2** | Profile trust rows don't stack at a3xl; values clipped (8,089 px in the gutter) | **Still a confirmed visual defect** until B reviews captures. Fix in `857e6d93`: rows stack above the threshold. PT5 now enumerates all six label/value surfaces (B's recommendation, test form) |

### 3. P-3 and P-4, classified by B (B message to E, 2026-10-09; E verified the source points)
B acknowledged that batch 9 was inconsistent in listing all four profile findings under "Failed".

**P-4 = (a) observed fixture problem. Not a product defect.**
- `TRUST_NO_RATE` (`app/_dev/v3-profile.tsx`) spreads `TRUST`, which has `completed_sales: 14`, and
  sets `seller_terminal_total: 0`.
- Under migration 031, `seller_terminal_total ⊇ completed_sales`, so the RPC cannot return 14/0.
- Fix the fixture (`completed_sales: 0` in `TRUST_NO_RATE`). No screen change.

**P-3 = (b) reachable product defect, minor.**
- `app/profile/[id].tsx:316` has the blurb at `numberOfLines={2}` (E verified at the current tip).
- Real long blurbs, e.g. "14 sales · 98% transfer success" from the elite/top/trusted branches, will
  clamp at a3xl. The text lost there is duplicated in the trust rows below.
- **Withdrawn:** the batch-9 claim that "the explanation beside the dash is cut". That needed the
  impossible no-rate shape. With real data an unknown rate means `completed_sales = 0`, so the
  `new_seller` blurb ("No completed transfers yet") is short and doesn't clamp.

**For C:**
- P-3 is a minor fix: remove the clamp or wrap, in line with the a3xl rule.
- The P-4 fixture correction is a separate harness commit.

Neither has started.

### 4. Reachability correction (`null%`)
- B's batch-7 claim that `null%` was reachable with correctly shaped RPC data was **wrong**. B
  withdrew it in `a09b2ae0`, after independently verifying C's migration-031 reasoning
  (`seller_terminal_total` ⊇ `completed_sales`).
- **The rendered defect was real, and it came from the malformed fixture.** The defensive guard in
  `reputation.ts` stays.

### 5. Untested, with the exact blocker
| Check | Blocker |
|---|---|
| **Authenticated consumer Home** (dock, real feed, consumer next-section figure) | No signed-in simulator session; B and C won't type the test-buyer credential. **Harness coverage is not authenticated-flow coverage** |
| **Edit listing refusals** (5 variants) | The signed-out guard renders first (byte-identical frames). Same session blocker |
| **Spoken VoiceOver** | No accessibility inspector. **The exposed label is verified in source only; that is not a spoken result** |
| `?art=` on the six list harnesses | none; not yet rendered |
| **P-1/P-2 at `857e6d93`** | **CLOSED** (B `12a98bdc`, independently measured) |

### 6. Launch blockers (for Codex; separate from product findings)
- **L-1, guard path.** `scripts/dev-web-guard.sh:20` pins
  `WORKTREE='/Users/josetascon/snatchit-refund'`. The migration repointed `.claude/launch.json` but
  not this script, so the sanctioned launch refuses on the SSD.
  - C reports that a copy with only `WORKTREE` repointed passes every substantive check: sandbox
    host, `app_env=sandbox`, `pk_test` key on the sandbox Stripe account, sandbox anon key, no stray
    env files.
  - **The repository copy is untouched. Repointing a safety control is for Codex and the owner. Do
    not bypass the guard.**
- **L-2, launch method (needs investigation).** C reports that `preview_start` produced a Metro that
  **ran without the guard passing**, then **exhausted its heap** while repeatedly building web
  bundles.
  - A server starting outside the gate is a gap in the launch method, whatever the cause.
  - E verified no Metro is listening on `:8081` and no simulator is booted now.

### 7. Owner decisions still unresolved
- The **"Unrated"** label and "N sales · transfer success unavailable" blurb (C proposal
  `01c236b2`). Per the corrected reachability, the shape is unreachable from the current RPC, so
  this is defensive wording.
- Earlier, still open: the checkout fee label; the uppercase `label` token; the Settings header
  split; the Edit-listing platform list.

### 8. Simulator and Metro ownership
- **Held by no one.** Both are stopped (E verified).
- By B's batch 8 and batch 9, **the next window is C's**.
- It **cannot start until L-1 is repaired.**
- Sequence after repair:
  1. C serves `857e6d93` through the guard.
  2. C captures the changed profile surfaces (ratewrap, trustrows, trusthero, default) at a3xl and
     default, in Light and Dark.
  3. C hands back to B.
  4. B reviews P-1/P-2 and re-confirms the Listing poster clearance once at default.

## Candidate under native review: `d52175303f22a575b80f005f38c0e8555be0dbdc` (named 2026-10-05; E verified 2026-10-06)
- **Implementation (C), checked by E.** `v3/midnight-app` in `/Users/josetascon/snatchit-refund`
  is at `d5217530`, and `git status` is clean.
  - Range `168e794a..d5217530`: `6100dee1` (the Home feature fix, Listing `?art=`, the shared
    `src/lib/media/harnessArt.ts`, and integration of the reserving seam), then `d5217530`.
  - `d5217530` adds only `docs/product-v3/V3_SUCCESSOR_HANDOFF.md`.
  - `git diff f3f08930..d5217530` touches no native or install file (`ios/`, `android/`,
    `app.json`, `package*.json`, `patches/`, `scripts/`). So reloading the existing dev client
    serves this candidate, and no rebuild is needed.
  - C reports 172 files / 2921 tests passing and a clean typecheck. That is C's report; E did not
    re-run them.
- **Metro.** C operates it. It is pid 2172, started 2026-09-26 16:56, cwd
  `/Users/josetascon/snatchit-refund`. It was not restarted, because it serves the tree whose
  contents advanced.
- **Push: not done.** `origin/v3/midnight-app` is still `404bce38`. C reports the authorised push
  was blocked by C's session permission guard. **This is an owner action.**
- **C's evidence is WEB evidence from the implementation owner, not native and not B.** The archive
  is `/Users/josetascon/snatchit-v3-evidence/6100dee1/`, outside the repo. E reconciled it with the
  final commit:
  - **Code is identical to the final commit.** `6100dee1` is an ancestor of `d5217530`, and
    `git diff 6100dee1 d5217530` is that one docs file. Every code-dependent web result at
    `6100dee1` therefore describes `d5217530`'s code.
  - **The archive does not record its own sha or clean status.** Its tie to `6100dee1` rests on
    the folder name and timestamps: files written 23:04–23:05, after the `6100dee1` commit (22:27)
    and before `d5217530` (23:06). That is attributable but not self-proving.
  - **The probe** loaded `localhost:8081/_dev/v3-home?...&appearance=dark` from Metro's web
    target.
  - **Proven per fixture (Home, Dark only, 393×491 frame):** `flyer`, `markers`, `tall`, `wide`,
    `square`, `subject`, `subject-wide` and `missing` each **MATCH**
    (`logs/feature-fixture-proof.txt`). Not covered: `photo`, `all` and Light.
  - **Listing** (`flyer`, `tall`, `subject-wide`, `missing`): claimed in the handoff only. The
    archive holds the probe script (`probe-listing.js`) but **no output log**, so it is not cited
    as evidence.
- **The earlier native captures, Xcode build log and `npm ci` log at `f3f08930` are lost.** They are
  not cited.
- **B's native review: pending.** No B commit after `ca00a250`. `docs/product-v3/native/` is
  empty at E's check (2026-10-06).
- **Routes:** `V3_SUCCESSOR_HANDOFF.md` at `d5217530`. Listing needs `screen=listing`.

**B native batch 1 (`c9d6f0d7`, 2026-10-06): Home at `d5217530`**
- **B's own start check:** HEAD `d5217530`, clean, contains `168e794a`.
- **Device:** `SN V3 393x852`, iOS 26.5 23F77. Metro pid 2172 (C).
- **The f3f08930 feature-selection defect is fixed.** Each of the 7 required `?art=` cases paints
  the feature itself. B matched each against its own source file with a mismatched-fixture
  control: diffs 0.5–4.1 against controls 8.4–84.4.
- **Geometry:** frame 490.3–491.0 pt at 393 pt (w/h 0.8004–0.8015). No crop, no stretch. 9:16 is
  pillarboxed; 1:1 and 16:9 are letterboxed.
- **No gradient:** the poster's bottom third differs least from its source.
- **No app text or badge on the poster.** The identity sits below it, in canvas inks.
- **Next section (native):** the rule is at 790.0 pt, with 62.0 pt of the following row visible,
  in both appearances.
- **Appearance:** System appearance switching works, verified by B. `?appearance=` persists as a
  stored preference, so B pins it per capture.
- **Device signed out:** B typed no credential. The `_dev` harness renders without auth.
- **E check:** all 14 PNGs are 1179×2556. E viewed `home-feature-wide-light.png` and
  `home-feature-flyer-dark.png`; they agree with B's description. The serving tree was still
  `d5217530` and clean after the batch.
- **Letterbox position: resolved as deliberate (C, 2026-10-06; E verified in source at `d5217530`).**
  Letterboxed art is positioned by the focal point, default y=0.40 (`src/lib/media/url.ts:76`
  `DEFAULT_FOCAL`, passed as `contentPosition` for both contain and cover at
  `EventMedia.tsx:265-273`). So 40% of the vertical slack sits above the art. A source taller than
  4:5 has no vertical slack and reads as centred. Stored art can carry its own focal point. Not a
  defect.
- **E observation passed to B, not a finding:** in both viewed captures, the first "This week"
  row's event name ("Midnight Arcade presents The Foundry Warehouse S…") is clamped at two lines
  with an ellipsis, at default text size. This may be the remembered truncation. B decides whether
  it reproduces and whether it is a defect; the design may intend a two-line clamp.
- **Still owed for Home:** Dynamic Type (largest standard and accessibility sizes) and safe areas.

## State after the SSD migration (E verified 2026-10-09 on `/Volumes/DEV-SSD`, UUID `6A74DBD6-…E510`)
**Working paths:** the SSD paths from `migration-records/MIGRATION_HANDOFF.md`. The Mac originals
are retained, not used.

**Successor `9498080ab7eb15a064bc455bb3d4f06e48eceaf0` (C, 2026-10-08):**
- **Contents:** `b0d74799` (F-BA bid activity, F-DT date/time wrap), `b9222a16` (long-bid fixture),
  `01c236b2` (profile rate fix) and `9498080a` (profile fixture corrected).
- **Code range from `3c03778a`:** `BidActivity.tsx`, `ListingHero.tsx`, `reputation.ts`,
  `_dev/v3-listing.tsx`, `_dev/v3-profile.tsx`, plus tests.
- **Origin:** `v3/consumer-batch2` = `9498080a`; `v3/midnight-app` = `c11b4a49` (`9498080a` plus
  captures and the handoff doc).

**C-operated captures (`c11b4a49`, `docs/product-v3/V3_BATCH8_HANDOFF.md`):** 16 frames at a3xl,
banner-gated, in `native/9498080a/` in C's repo. **None is B-reviewed yet.**
- Bid activity (ordinary and four-figure), Light and Dark.
- Full date/time, Light and Dark.
- Four-figure CTA.
- **Home feature amount at a3xl**, ordinary and long.
- Profile rate, corrected and unknown.

**Home drag (C):** not a product defect. Inside the feature, 3 of 4 drags scrolled and 1 opened the
listing. C traced the earlier "every drag taps" to three automation faults, each with a control: the
drag landed on the fixed footer; back-to-back touch paths dropped the second; a fast release flicked
past. No app interaction was changed. B reviews this.

**Profile fix:**
- A seller with volume but no terminal transfer now gets `rate = null`: no percentage, no "Needs
  review".
- **Proposed label "Unrated", blurb "N sales · transfer success unavailable" (tier `new_seller`,
  neutral tone). NOT SETTLED: the owner decides the trust-presentation wording.**
- **C states** that this shape is unreachable from `get_profile_trust_stats` as written (migration
  031: the denominator's status set ⊇ `completed_sales`'s). **No second party has verified this.** It
  is not a dependency: the guard stands on its own. A/D could usefully confirm only whether the RPC
  definition has changed since 031.

**New profile findings at a3xl (C recorded them, did not fix them; for B and the owner):**
- The trust percentage breaks mid-number ("10 / 0 / %"), Light and Dark.
- Trust-row values clip at the right edge.
- The badge blurb clamps.
- One sub-line contradicts the sales count, in a shape C says the RPC cannot return.

The first two are the same class as the money-wrap fixes.

**Window:** C handed the simulator and Metro back to B at `9498080a` (`c11b4a49`). The migration
then shut down the simulator and stopped all smoke-test servers. **Ownership must be re-agreed
between B and C before either restarts Metro or boots the device** (owner, 2026-10-09).

**Serving tree on the SSD:** `snatchit-refund` at `2919ba75`, which is local-only. It is `c11b4a49`
plus capture helpers under `tools/v3-capture/`, with no app code. Its `.claude/launch.json` is
modified; that is a documented migration change (`runtime-path-changes.json`).

**C on the SSD (2026-10-09):**
- Verified at the handoff commits.
- New local commit `b2b3e9d9`: tools only. `shot.sh` and `nav.sh` now find `cap.sh` beside
  themselves instead of under `/tmp`.
- Serving tree: `2919ba75` + `b2b3e9d9`, with no app code change. Not pushed.
- Nothing running.
- C is holding until B agrees the window. B isn't in C's peer list, so the relay goes through the
  owner.

**Next, for B:**
- Focused review at `9498080a` of C's 16 frames.
- Re-confirm the poster clearance at default once, because `ListingHero` changed.
- Rule on the profile findings.

## B batch 7 at `3c03778a` (`a1af6499`, 2026-10-08): **simulator and Metro handed to C**
| Item | Status | Evidence |
|---|---|---|
| **Edit refusals** (not-found, not-owner, has-bids, inactive, read-failed) | **UNTESTED.** All five render the same signed-out screen (md5 `da44e338a711` across the Light captures): the signed-out guard runs before the refusal states, so they never render. Not a pass. Needs a session (same blocker as signed-in Home) | `native/3c03778a/edit-*` |
| **Public profile, default / no-listings, Light and Dark** | **FAILED.** It renders the literal "null% transfer success" | `profile-default-{light,dark}`, `profile-no-listings-light` |
| Public profile, stats-unavailable | REVIEWED, PASS (refuses to read as zero sales) | `profile-stats-unavailable-light` |
| Public profile, not-found | REVIEWED, PASS | `profile-not-found-light` |
| Public profile, blocked | captured (`profile-blocked-light`); no verdict stated in the commit message | — |
| Listing error / offline, Light and Dark | REVIEWED, PASS (the copy says nothing was sent) | `listing-{error,offline}-*` |
| Artwork on the six list harnesses (My listings, Bids, Tickets, Order/Send, Checkout, Search) | **UNTESTED. E correction:** B's batch 7 carries "artwork" from batch 1 at `d5217530`, but batch 1 covered only Home (and later Listing). `?art=` on these harnesses arrived in `a587d2a1`, after `d5217530`, and no B render of them exists. The carry applies to Home and Listing only | — |

**Profile `null%` defect.**
- **Root cause** (B; E verified `reputation.ts`): `ratePct` is null when `seller_terminal_total = 0`.
  The tier returns at `:58`, `:61`, `:64` and `:67` interpolate it unguarded; the `disputes_lost`
  branch at `:42` guards it.
- **Reachable with correctly shaped real data:** `completed_sales >= 5` with
  `seller_terminal_total = 0`.
- **E addition:** in that case `rate` is set to **0** (`:34`, `denom > 0 ? num/denom : 0`). So the
  seller also **fails every tier gate and is labelled "Needs review"** (`:67`). The invented zero
  decides the tier, not just the text.
- **Owner requirement:** guard it "without inventing a zero or implying success". The fix must
  therefore address the **tier selection** as well as the blurb.
- **Ruling needed:** which tier a seller with sales but no terminal-transfer data gets is a
  trust-presentation choice. **C proposes; E flags it to the owner** if the proposal changes the
  label.
- **Fixture:** it is separately malformed (wrong field names behind `as unknown as`). Correct it
  separately, and **add a test of the correctly shaped real-data case**, so that fixing the fixture
  can't hide the branch.

**Successor scope (owner, 2026-10-08):** `b9222a16` plus the profile fix. Then validate and serve one
named clean successor, and capture:
- bid amounts (ordinary and long) and the full date/time at a3xl, Light and Dark;
- the profile correction;
- the Home feature amount at a3xl.

**A failed synthetic drag alone is not a product scrolling defect.** Compare with reliable manual
input or another validated gesture before classifying it. Then C hands back to B for focused review.

## Sequence after batch 6 (owner, 2026-10-08; no further owner design decision needed)
| Step | Owner | State |
|---|---|---|
| 1. Finish the unaffected refusal, profile, error/offline and artwork checks at `3c03778a`; commit them; **hand the simulator and Metro to C explicitly** | B | **done: `a1af6499`** (handed to C) |
| 2. Prepare both fixes in the isolated worktree (below) | C | **done**: `b0d74799` + `b9222a16`, then the profile fix `01c236b2` + `9498080a` |
| 3. After B's handback: validate, serve **one named clean successor**, then capture at **a3xl, Light and Dark**: bid activity with an ordinary **and** a four-figure amount; the Listing date/time line; the Home feature amount | C | **done**: successor `9498080a`; 16 frames in `c11b4a49` |
| 4. Hand back to B for focused verification of those three | C → B | **handed back** (`c11b4a49`). B's review is pending; the window must be re-agreed after the migration |

**Fix F-BA (bid activity amount):**
- Stack the row where needed, and keep the whole amount readable, including cents and separators.
- Use the established responsive price treatment.
- Source: `BidActivity.tsx:81`.

**Fix F-DT (Listing date/time):**
- The full date and time wrap.
- The detail screen exposes the full information.
- Source: `ListingHero.tsx:120-121`.

**Home feature amount:**
- Only an a3xl capture counts.
- If C can't reach it, C states the exact blocker and the check stays **untested**.

**Preserve:**
- the accepted poster, navigation, footer and reservation behaviour;
- **no change to Listing spacing** on the existing evidence.

**`b9222a16` contents (C; E checked the diff from `3c03778a`):**
- `BidActivity.tsx`: above the shared threshold the row becomes a column and the amount owns its own
  line; the compact form keeps its cap. The "Leading" chip is kept, and the bidder name no longer
  clamps. There is a new test file.
- `ListingHero.tsx`: **only** `numberOfLines={1}` is removed from the date line (E verified the
  single changed line). C reports it stays one line at every standard size.
- `?amounts=long` added to the Listing harness, so a four-figure bid can be shown.
- Mutation controls: BA2, BA3 and LH1b each failed as C predicted.

**Carry note:** `ListingHero` changed, but only below the poster. **B confirms the poster clearance
once at default size** in the focused pass. The poster and navigation geometry is otherwise
unaffected.

**Home feature amount:** before reporting, C will tell gesture automation apart from a real defect,
using a drag with a large first step. **No production interaction change** to make capture work. If
it can't be reached, the check stays **untested**.

**Outstanding, not blocking the rest:** authenticated consumer Home, and spoken VoiceOver. **The app
is not fully accepted.**

## B batch 6 at `3c03778a` (`e1c5f38e`, `B_NATIVE_REVIEW_3c03778a.md`)
C-operated frames were copied to `docs/product-v3/native/Coperated/3d4d6a4a/`.

| Item | Status | Evidence |
|---|---|---|
| **Feed-row amounts** (Home feed rows; `$132.00` and the four-figure `$1,716.00`) | **REVIEWED, PASS.** B re-measured: 63.7 pt and 58.0 pt reproduce C's figures. `$1,716.00` is complete; shrink engaged to 91% without recreating the failure | C-operated, B-reviewed |
| **Home main-event (feature) amount** | **UNTESTED at a3xl.** The batch-4 finding was measured on this amount (24.3 pt cap). It is **not** closed by the feed-row result: the shared `amountFit` path is an inference, not a measurement | owner 2026-10-08: a capture at a3xl is required; a smaller size is supplemental only |
| Listing scroll-end clearance | **REVIEWED, PASS.** The bottom gap is accounted for arithmetically: CTA 688.0 pt, footer 176.3 pt, last content to footer top 209.7 pt. That is the intended clearance, not dead space. **No spacing change is warranted** | C-operated, B-reviewed |
| Event name reachable at a3xl (R-4) | **REVIEWED, PASS** | C-operated, B-reviewed |
| **Bid activity amount at a3xl** | **FAILED.** The top bid renders as "$99." with the cents gone. Ink reaches x=387.7 pt and 984 px sit inside the 16 pt gutter. Root cause: `BidActivity.tsx:81` has no `maxFontSizeMultiplier`, no `numberOfLines` and no shrink; it was missed by the `amountFit` sweep. E verified line 81 in source | `listing-a3xl-light-scrollend-Coperated` |
| Event date and time in full on Listing at a3xl | **UNTESTED on device (B).** E's source check classes it as a defect: the only date/time on Listing is `ListingHero.tsx:120-121`, one line. C's frame shows "Sat 24 Oct · 1…" | owner content rule |
| Signed-in Home; spoken VoiceOver | **UNTESTED** (capability) | — |
| Poster, frame, gradient, Listing clearance, icons, Filters glyph, Option B, reserving | **Carried** (unchanged since `d5217530`/`91a5a58c`) | B |

**Next step (E proposal):**
- **C prepares one fix commit** covering the `BidActivity` amount (the same `amountFit` treatment,
  with the row stacked at large text) and the hero date/time line (wrap; never truncate the date or
  time).
- **One short C-operated window:** serve that sha, then capture:
  1. Listing at a3xl, Light and Dark, at the date/time line.
  2. The bid-activity row at a3xl.
  3. The Home feature amount at a3xl, or at a content size just past the stacking threshold, where
     it stays on screen at rest.
- **Meanwhile, B continues at `3c03778a`** with the refusal, profile and artwork groups. Those
  screens are untouched by these fixes.
- **Listing `?variant=error|offline`:** B checks it after the fix if the fix touches
  `ListingDetailScreen`.

## Owner direction for the `3c03778a` review (2026-10-07)
- **Order of B's pass:**
  1. C's durable captures.
  2. Home and Search price layouts at default, 3xl and a3xl, including long amounts.
  3. Listing scroll-end clearance and event-name reachability.
  4. The refusal, profile, error/offline and artwork groups.

  Batch 5's assignment at `91a5a58c` is historical and is not repeated. Unaffected poster and icon
  results carry.
- **Capability gaps don't stall the review.** If the Home feature price still needs touch, B names
  that exact check for **one short C-operated capture**, and B reviews the result.
- **Bottom gap:** account for it from the actual footer bounds and scroll layout. **No further
  spacing change based on a screenshot estimate alone.**
- **Shortening is judged by content.** A list title may shorten, because it links to full details.
  **The event's date and time must be available in full on the detail screen at large text sizes.**
  - E source check at `3c03778a`: on Listing, the date, time and venue appear **only** in
    `ListingHero.tsx:120-121` (`rowWhenLabel(...) · venue`), with `numberOfLines={1}`. No fact row
    repeats the date or time.
  - So the a3xl "Sat 24 Oct · 1…" (C frame `listing-a3xl-light-eventname`) loses the time on the
    detail screen. **E classes it as a defect under this rule.** B confirms on the device; C fixes
    it.
  - The feed-row title, date and bid count shortening on Home and Search is **acceptable list
    shortening**, provided Listing shows them in full.
- **Reporting:** findings are published incrementally, each marked reviewed, failed or untested. No
  repeated full-suite run. No whole-app acceptance claim.

## Remaining C-operated frames: `3c03778ac55e2c0f33233e4cd90e634805e28e2a` (2026-10-07 23:03; **pushed**; handback line not yet seen)
- **Code is identical to `3d4d6a4a`**: `3c03778a` adds only three PNGs and log lines in
  `native/3d4d6a4a/`.
- **Pushed:** `origin/v3/midnight-app` and `origin/v3/consumer-batch2` = `3c03778a`, verified with
  `git ls-remote`.
- **R-4, the owner's test** (the name may start below the fold, but must be reachable and readable by
  scrolling): **C reports PASS in both appearances.** At a3xl, "Neon Choir" spans two lines, ink
  about 90 pt, revealed whole by one drag. E viewed `listing-a3xl-light-eventname-Coperated.png`
  and agrees. **B's review is still owed.**
- **Dark scroll-end:** CTA top 688.0 pt, last content 466.3 pt. Identical to Light; nothing is
  sliced.
- **Flagged for B and the owner, not fixed:** at a3xl the hero date line clamps to
  "Sat 24 Oct · 1…" (`ListingHero` `when`, `numberOfLines={1}`). It is the same family as the
  feed-row title and date clamps, and not the money rule.
- **Still not captured:** the feature's own amount at a3xl (gesture blocker; inferred, not measured).
- **HANDBACK (C message, 2026-10-07): the simulator and Metro `:8081` are B's.** Candidate
  `3c03778a`, served and clean (E verified). The device is reset to large/light.
- **Tests at this candidate (C's report, device down; E has not re-run them):** 174 files / 2979
  tests, exit 0; typecheck clean; 0 lint errors.
- **Feature amount at a3xl stays unmeasured.** Drags from the heading and identity text also
  registered as taps on the feature.
- **B's next pass at `3c03778a`:**
  1. Review the new C-operated frames: `native/3d4d6a4a/` in C's repo.
  2. Home and Search price and feed rows at the three sizes.
  3. Listing scroll and footer, including measuring the bar's top for the 206 pt residue.
  4. The remaining groups: Edit refusals, profile, Listing error/offline, the `?art=` list harnesses.

  Carries from `91a5a58c`: Listing poster clearance (`ListingHero` untouched) and the Home artwork
  per fixture.

## C-operated captures and price measurements: `37df36fd96c042ba5645021dfc90c13de1d96bcd` (2026-10-07 22:55; not B-reviewed; not yet handed back)
- **Code is identical to `3d4d6a4a`**: `37df36fd` adds only `native/3d4d6a4a/` (six frames and
  `capture-log.txt`). Every frame was accepted only with the sandbox banner asserted. Home frames
  were taken at `453a1c82`. `453a1c82..3d4d6a4a` changes only `ListingDetailScreen` and its test,
  so Home is unchanged. Not pushed yet: origin is still `91a5a58c`.
- **Rendered price ink height (C's measurements):**

| Size | Amount | Height | Note |
|---|---|---|---|
| default | $99.00 | 18.3 pt | compact form keeps the cap |
| 3xl | $99.00 | 25.0 pt | |
| a3xl | $132.00 (feed row) | **63.7 pt** | was 24.3 with the cap |
| a3xl | **$1,716.00** (`?amounts=long`) | **58.0 pt** | 91% of the shorter amount; the 0.6 floor was not reached. Every digit, the separator, the cents and "all-in" are present |

- **E view check:** `home-price-a3xl-light-longamount` shows "$1,716.00" on one line with "all-in"
  beneath it; this agrees with C.
- **Listing at scroll-end:** CTA top 688.0 pt at a3xl and 700.0 pt at default. The last content
  ends at 466.3 pt and 494.3 pt. **Nothing is sliced**, and a further drag doesn't move, so these
  are true ends. **This closes the footer-slice defect** (B reviews).
  - **Residue (C reports it, not root-caused):** about 206 pt between the content and the CTA, more
    than the footer needs. The bar's top isn't visible against the canvas, so B is to measure it.
- **Not captured:**
  - The feature's own amount at a3xl: drags inside the feature register as taps. Inferred from the
    shared `amountFit` path, **not measured**.
  - **Listing at a3xl, scrolled to the event name** (B's request 2).
  - **The Dark versions** of the Listing captures (B's request 3).

## C's window: served `3d4d6a4a5bbcd50448dfdaa56d58e892aa774ed3` (2026-10-07 22:43; supersedes `453a1c82`; not yet handed back)
- **`3d4d6a4a`** (C, measured at a3xl): the footer is 176.3 pt tall, but the old clearance was a 96 pt `scrollTail` plus 64 pt (about 160 pt), a 16 pt shortfall. Clearance is now only the measured footer height plus a gap; the spacer and the constant are removed, and a test pins their absence. C reports that its first attempt left about 300 pt of dead scroll. `ListingDetailScreen.tsx` only, plus a test. Not pushed yet (origin is still `91a5a58c`).
- **Contents:** `338268c5` (price fix) + `453a1c82`.
- **Footer slice: confirmed a padding defect and fixed** (C).
  - Cause: the scroll ended its content with a constant padding, while the fixed footer grows with
    text size.
  - Fix: `StickyBar` reports its measured height through a new optional `onLayout`, and
    `ListingDetailScreen` pads by that height plus a gap.
- **`?amounts=long` added to the Home harness** (×13 on bid and Buy Now amounts) for the owner's
  longer-amount check.
- **Relevant diff from `91a5a58c` (E):**
  - **Listing no longer carries.** `ListingDetailScreen.tsx` changed (scroll padding), so the
    Listing scroll and footer checks repeat. The poster clearance itself is unchanged, since
    `ListingHero` is untouched.
  - `StickyBar` change is additive (a new optional prop, no deletions besides the signature line).
    Its other users (Create, Edit listing, settings) don't pass it.
  - The `v3-home.tsx` change is inert unless `amounts=long`, and the art path is unchanged, so Home
    artwork evidence still carries.
- **Awaiting:** C's measurements and captures, then a committed handback naming one sha.

## B batch 5 at `91a5a58c` (`cb242fd8`, 2026-10-07): C-operated captures reviewed; **simulator handed to C**
- **Applicability (B, checked by dependency):** the `7c9b270b` Home set carries exactly (no source
  delta to `91a5a58c`). The `94ac8b4f` Listing set carries, because the Listing screen reaches
  neither `FeedRow` nor `HomeFeature`. The files are copied to `docs/product-v3/native/Coperated/`,
  so the review doesn't depend on C's worktree.
- **Case 1, feed row at 3xl: PASS** (C-operated, B-reviewed). Price, "all-in" and the end time are
  each complete on their own line.
- **Case 2, a3xl:** the amounts and "all-in" survive, and the "al…" clip is fixed. The title, venue
  and bid count are cut with "…". B records that as **degradation, not a defect**, because the row
  stays identifiable. It corroborates the batch-4 price-size finding.
- **Case 3, Listing scrolled:** default is complete. At a3xl, the stacked values are complete, but
  **"Mobile transfer · DICE" is sliced by the fixed footer** (CTA top edge at 688.0 pt).
  **Candidate defect:** B can't tell insufficient bottom padding from a mid-scroll frame. One
  scroll-end capture settles it.
- **Listing event name at a3xl:** not established, and not claimed.
- **Handoff:** B's capture group is complete at `91a5a58c` (serving tree matched and clean at start
  and end). **The device and Metro `:8081` belong to C** from `cb242fd8`.
- **Captures B asked C for:**
  1. Listing at a3xl, Light, scrolled to the end: does the last fact clear the footer?
  2. Listing at a3xl, Light, scrolled to the event name.
  3. The same two in Dark.
  4. Home and feed row at the three sizes after the price fix, plus a longer amount (`$1,234.56`).

## B native batch 4 at `91a5a58c` (`a4e546d0`, 2026-10-07 22:03; `B_NATIVE_REVIEW_91a5a58c.md`)
- **B's start check:** HEAD `91a5a58c`, clean, contains `d5217530`. B discarded three launcher
  frames (the dev client had fallen back to `:8083`). Every capture helper now asserts that the
  sandbox banner is present.
- **Listing poster clearance: CONFIRMED FIXED (sim).**
  - Banner 0–78.7 pt.
  - Navigation strip on plain canvas 79.0–139.0 pt.
  - Poster 139.3–629.3 pt (w/h 0.8020); whole-poster contain diff 2.8.
  - The "From a fan" chip moved below the poster. Nothing covers printed content.
  - E viewed `listing-live-flyer-light-dflt`: agrees. **E note for B:** at rest, the event *name*
    now sits below the fold, hidden behind the footer; only the date line is visible. B should say
    whether R-4 needs the name on the first screen.
- **Footer and `?reserving=1`: still correct (sim)**, both appearances. The footer is complete and
  unsplit at a3xl. No reservation made.
- **Price at large text: complete, but NOT readable at the requested size (B finding).**
  - Ink height: 18.7 pt at default, 24.3 pt at 3xl (×1.30), and capped at 24.3 pt at a3xl. The name
    reaches 88.0 pt there, so the price is about 28% of the title's height.
  - B recommends removing the cap in the stacked form and letting the layout bound it. If space runs
    out, wrap the caption, never the digits.
  - This confirms E's earlier observation. **Open, for C.**
- **Still open in B's review:**
  - Review of C-operated captures (located, not reviewed).
  - Search at large text.
  - The new refusal, error and profile fixtures.
  - Remaining artwork fixtures.
  - Signed-in Home (pending a session).
  - Spoken VoiceOver (no inspector).
- **Window:** B has **not** handed back after batch 4.
- **C's fix for the price finding** exists only in C's worktree, uncommitted. It removes the cap in
  the stacked form only, keeps the amount on one line with `adjustsFontSizeToFit` (minimum 0.6), and
  lets the caption give way first. It needs a device window, which B has not released.
- **C's price fix committed:** `338268c5311a6722c8f37a3908b22ae9261a1e07` (`v3/consumer-batch2`,
  descends from `91a5a58c`). It is **not served**; the serving tree stays at `91a5a58c`.
  - E verified the diff: code files are `HomeFeature.tsx`, `FeedRow.tsx` and `typography.ts`
    (numstat 9/0, additions only); the rest are tests (typography mock lines and the home-components
    test).
  - **Carry from `91a5a58c` to `338268c5`:** all Listing confirmations (poster clearance, footer,
    reserving, panel and fact rows), because none of their files changed and the shared typography
    file only gained lines.
  - **Repeat at `338268c5`:** the Home feature identity price at default, 3xl and a3xl, and the
    feed rows, including Search, which renders `FeedRow` (`explore.tsx`).
  - **Order, owner-confirmed 2026-10-07 (bounded handoff; no further owner approval needed):**
    1. B finishes its **current** capture group, commits it and hands the simulator to C in a
       committed line. The rest of the unaffected-screen backlog does not have to finish first.
       While C holds the device, B reviews the existing C-operated captures.
    2. C runs the suite with the device down, then serves one clean candidate. C measures the
       **rendered price size** at default, largest standard and largest accessibility, for `$99.00`
       **and representative longer amounts**. Every digit and "all-in" must be kept, and
       shrink-to-fit must not silently recreate the readability failure. C should give the price
       layout space before shrinking it. C then hands the simulator back.
    3. B reviews Home and Search at that candidate, then continues the remaining groups.
  - **Listing, R-4 (owner, 2026-10-07):** the event name does not have to be above the fold at the
    expense of the full 4:5 poster. **Acceptance test:** the name is fully reachable and readable
    by scrolling, and the bottom padding clears the fixed footer. If scrolling cannot expose it,
    that is a defect. The poster design is not reopened.

## Successor final: `91a5a58c1d54a0c98ef353a6d5f7b53dfb68861c` (C, 2026-10-07 00:12; E verified)
- **Code** is identical to `7c9b270b`. `91a5a58c` adds only the handoff update and captures. The
  serving tree is clean.
- **Pushed.** `origin/v3/midnight-app` and `origin/v3/consumer-batch2` = `91a5a58c`, verified with
  `git ls-remote`. The earlier push gap is closed.
- **C-operated captures, not yet B-reviewed:**
  - Home cases 1 and 2 were retaken at `7c9b270b` (`native/7c9b270b/`).
  - Listing case 3 stays at `native/94ac8b4f/`. E verified that
    `git diff --name-only 94ac8b4f 7c9b270b` lists only `FeedRow.tsx`, `HomeFeature.tsx` and their
    test, so the Listing surfaces did not change and case 3 carries.
  - The superseded `94ac8b4f` Home captures were removed from the tree. They are preserved in git
    history at `c75b1c68` and are not evidence for this candidate.
- **E observation on `case2-home-a3xl-light-identity` (for B; not a verdict).**
  - Amounts are complete: "$99.00", and "$132.00" with "all-in".
  - Because the numeral is capped at 1.3× while the caption and meta lines scale fully, **at a3xl
    each price renders smaller than its own caption and the surrounding text**. The amount becomes
    the least prominent line in its block.
  - The feed row also still cuts "2 × GA · 11…" (bid count), the date ("Thu 8 Oct ·…") and the title
    ("Arcade pr…").
  - B judges whether the inverted hierarchy meets the readability rule. The alternative is a layout
    that lets the numeral scale on its own line without splitting.
- **Cases 4 and 5:** unchanged (blocked, and partly established in source).
- **Tests (C's report, not re-run by E):** 174 files / 2976 tests, exit 0, at `91a5a58c`, with the
  simulator shut down. C notes that runs with the simulator booted fail in differing sets on 5 s
  timeouts, so captures and the full suite can't be trusted at the same time on this machine.
- **Window: C has released the device and Metro for B's review** (C message, 2026-10-07). It is
  booted at large/light with the app launched, serving `91a5a58c`, clean. **B's review at
  `91a5a58c` is pending** until B starts and commits.

## Successor now `7c9b270b7e2c098ba352ee11ee9560b362669ffc` (served 2026-10-07 00:06; supersedes `22835964`)
- **What changed.** `7c9b270b` stops stacked price numerals wrapping mid-number ("$132.0" / "0").
  The price numeral in `FeedRow` and in `HomeFeature` now takes
  `maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}`, which is 1.3 (`src/theme/typography.ts:125`).
  The surrounding text still scales fully, and the spoken label carries the full amount. Serving
  tree clean.
- **For B to judge (E note, not a verdict):** this caps the **price numeral's** growth at 1.3× of
  the user's text size. C cites it as the app's existing treatment for display type. The owner's
  instruction was "wrap or adjust its layout", and C's own earlier note said capping refuses a
  request for larger text. B decides whether a capped but complete numeral meets the readability
  rule at 3xl and a3xl.
- **Carry/repeat:** unchanged from `22835964`. The Home feature identity and feed rows already
  repeat. The feature artwork checks still carry, because the numeral sits below the poster.

## Successor now `22835964997f31acd73d49b96ead6eccea84f01d` (served 2026-10-07 00:00; supersedes `c75b1c68`)
- **What changed.** `22835964` changes only `FeedRow.tsx` (plus a test). Above
  `IDENTITY_STACK_SCALE`, a row's text and price share one column, and the price block is not
  capped. This fixes the a3xl "$132.0…" / "all-i…" clip E saw in C's case 2 capture. The title and
  date clamps are deliberately left for B and the owner to judge (case 1). Serving tree clean.
- **Relevant diff from `c75b1c68`.** `FeedRow` renders the Home feed rows and the Search results
  (`app/(tabs)/home.tsx`, `explore.tsx`). `HomeFeature` mentions `FeedRow` only in comments.
- **Carry/repeat effects:**
  - The Home feature checks are unaffected and still carry.
  - **C-operated cases 1 and 2 at `94ac8b4f` are superseded for the feed rows.** Their feature
    identity content still describes the feature, but the rows must be re-captured at `22835964`.
  - Case 3 (Listing) is unaffected.
  - The harness next-section figure was already a repeat.
  - Search results now also need a row check at large text.

## Successor named: `c75b1c687e9f9b607c039fc07e9a91e70ede6b88` (C, `docs/product-v3/V3_BATCH2_HANDOFF.md`; E verified 2026-10-07)
**Implementation (C).**
- `v3/midnight-app` and `v3/consumer-batch2` both point at `c75b1c68`. The serving tree is clean.
- `c75b1c68` adds only the handoff doc and `native/94ac8b4f/` captures to `94ac8b4f`; no code
  changes. So code evidence at `94ac8b4f` describes `c75b1c68`.
- No native file has changed since the installed build.
- C reports `tsc` exit 0, lint 0 errors, and 174 files / 2974 tests passing. C voided three earlier
  runs because the booted simulator starved the 5 s timeouts. E has not re-run them.

**Push.** `origin/v3/midnight-app` = `d5217530` and `origin/fix/reserving-seam` = `168e794a`.
`v3/consumer-batch2` and the successor are **not on the remote**.

**C-operated captures, not yet B-reviewed.** In C's repo at `native/94ac8b4f/` (outside
`docs/product-v3/native/`), with `capture-log.txt`. The log records content size and appearance as
read back from the device.
| Case | Files | E viewed | E observation (for B; not a verdict) |
|---|---|---|---|
| 1 feed-row title, 3xl | `case1-home-3xl-light-{atrest,feedrow}` | feedrow | Titles clamp at 2 lines ("presents The Fo…", "Late Set with…"). Date/time lines are cut ("22:00…", "21:…", "01:…"). "no bids…" is cut. Prices and "all-in" are complete. C has deliberately left this for B and the owner to judge against the approved row design |
| 2 below-fold identity, a3xl | `case2-home-a3xl-light-{atrest,identity}` | identity | Feature identity is fixed: "Ends Wed 01:43" is complete and "current bid, all-in" wraps. **However, the first "This week" feed row's price runs off the right edge ("$132.0…") and its "all-in" is cut ("all-i…").** This is a clipped amount, the same class as the `d301ccb4` "$95.0". It is likely a defect under the settled all-in rule. FeedRow was not changed in this successor |
| 3 Listing breakdown/activity | `case3-listing-{default,a3xl}-{light,dark}-scrolled` | a3xl light | Panel rows stack; "Service fee (10%)" $9.50 and Delivery wrap fully; the footer is intact |
| 4 signed-in consumer Home | none | — | **Blocked.** Needs an authenticated session on the simulator, established by someone permitted to handle the test-buyer credential. B and C both decline to type it. No harness substitute was used |
| 5 price-caption accessibility | none (source) | — | **Partly established.** The exposed label includes "all-in" (`HomeFeature.tsx`, test LT5). Spoken output is **not** established: the missing capability is an accessibility inspector or VoiceOver attached to the simulator |

**Not yet captured at the successor:** Listing at rest after the poster fix (poster clear of the
banner, navigation outside the artwork, R-4). It belongs to B's repeat set.

### Previously served: `94ac8b4fc40af2642515685929ef5f9ea04472cf`
### Previously served: `c90003ee4ea37795dcf3177f76c947cb0af566b5`
`c90003ee`: Listing's Delivery row lost its value at large text, and that is fixed
(`ListingDetailScreen.tsx`, plus a test). Carry/repeat is unchanged, because Listing already repeats
in full.

### Previously served: `9ea534ffdc9cd07dee0fea31b363824e46ed42a3`
`9ea534ff`: when stacked, the line caps in `HomeFeature.tsx` and `TransactionPanel.tsx` are removed,
because two lines was not enough either. It also adds a test. Carry/repeat is unchanged: both files
are already on the repeat list. C is still iterating from its own captures, so E waits for the
formally named sha before B starts.

### Previously served: `d301ccb4f1ae6e6eeacc6c44ba6933a4418b8288`
`d301ccb4` changes `TransactionPanel.tsx` and adds a test. C found this in a C-operated a3xl capture:
at a3xl, Listing's panel clipped the quantity ("2 × GA ti…"), the "all-in · 6 bids…" sub-line and a
breakdown **amount**, shown as "$95.0" instead of "$95.00". A clipped amount states a different
number. The rows now stack above `IDENTITY_STACK_SCALE`, and nothing is capped at one line. C reports
no change to price semantics. Carry/repeat is unchanged, because all of Listing already repeats.
**This is evidence the a3xl Listing panel was wrong at `d5217530` too.** B's batch 2 a3xl Listing
capture is now superseded by the fix and is not acceptance.

### Previously served: `0dfea8b21496390cc66ad470ba9ad1bc42e2211a`
`0dfea8b2` changes one line in `HomeFeature.tsx`: the time · venue meta line goes from
`numberOfLines` 1→2, because at a3xl it clipped to "19:30 · Lanter…". C found this in a C-operated
capture. It also adds a test. The carry/repeat list below is unchanged: the edit is inside the Home
identity block, which already repeats. The serving tree is clean.

### As first served: `7d0ae5655d7b308c118d7f1154abe95c73f2233c`
- **Implementation (C).** `v3/midnight-app` in `/Users/josetascon/snatchit-refund` is at
  `7d0ae565`, clean.
  - Range from `d5217530`: batch2 (`6c562dcf` … `8f6bed1e`), then `750a9c4f` (Edit refusal exit),
    `40922d27` (Send not-found exit), `70ae3b94` (Listing failure faces and a profile harness),
    `07de08ad` (all-in caption) and `7d0ae565` (poster no longer covered).
  - No native or install file changed, so no rebuild is needed.
  - Test results: C's report is pending.
- **Relevant-diff review (E), per check, from `d5217530`:**
  - **Home artwork per fixture, 4:5 frame, no gradient, nothing on the poster (batch 1): CARRY.**
    `HomeFeature.tsx` changed only in the identity block below the poster: a stacked layout above
    font scale 1.3 (`featureMetrics.ts` `IDENTITY_STACK_SCALE`) and `numberOfLines` 1→2 on two
    lines. `EventMedia`, slots, `url.ts`, `home.tsx`, `FeedRow` and `v3-home.tsx` are untouched, and
    `harnessArt.ts` changed by additions only.
  - **Home identity block, at default, 3xl and a3xl: REPEAT.** It changed, including at default size
    (`numberOfLines` 2). So does the harness next-section figure, which depends on the block's
    height.
  - **Filters glyph, F-91-6 (Home header): CARRY.** `IconButton` and `IconSymbol` are untouched, and
    so is the Home header.
  - **Listing: REPEAT everything.** That covers the poster, artwork cases, R-4, navigation chips,
    safe area, footer at rest, reservation feedback and Dynamic Type. `ListingHero.tsx`,
    `ListingDetailScreen.tsx` and `v3-listing.tsx` changed.
  - **New:** B's five C-operated cases; VoiceOver; consumer Home signed in (or its blocker); Edit
    refusals (`v3-edit-listing`); Listing failure and offline states; public profile
    (`v3-profile`); Send/Receive not-found; the six harness-art screens. C's owner evidence comes
    first, then B.

**B native batch 3 (`17c7e670`, 2026-10-06) and window handback**
- **Listing poster: complete but covered.** It is 4:5 and complete (0–490.7 pt). The status bar and
  banner cover its top 79 pt: masked diff 4.1 for cover-fit at 79 pt hidden, against 16.6 for
  contain. This refines E's earlier wording, "top band not visible": the content is under the chrome,
  not cut by the frame. Navigation chips sit at y 80–160 pt on printed lines. **This fails the
  settled requirement at `d5217530`. Fix: positional (start the poster below the banner, controls in
  their own area). No re-crop.** Home clears the banner (its feature starts at 164 pt).
- **R-4 (info beneath the poster):** the captures show the date line, name and provenance below the
  poster for `flyer`, `subject-wide` and `missing`. B states no explicit R-4 verdict. **R-4 stays
  open** and is decided at the successor, because the navigation fix changes the same layout.
- **Not done at `d5217530`:** footer Dynamic Type; VoiceOver (no accessibility inspection in B's
  session); scrolling (no touch input).
- **Five cases B specified, which C operates and B reviews.** Files are named
  `…-Coperated.png`.
  1. Feed-row title at 3xl and a3xl.
  2. Home identity block below the fold at a3xl.
  3. Listing bid breakdown and activity at default and a3xl, both appearances.
  4. Consumer Home signed in, at rest and one section scrolled, relative to the dock top at
     704.0 pt.
  5. VoiceOver spoken value of the a3xl price caption. This records the gap; it does not close it.
- **Window returned to C** (`17c7e670`). The serving tree was `d5217530` and clean at both the
  start and end of B's review, so every capture's provenance is established.
- **B's scope statement:** not whole-app acceptance. The batches cover Home, Listing, the footer,
  reservation feedback, icons and Dynamic Type, on a native development build, at one commit.

## Owner direction 2026-10-06 (completes existing rulings R-3 and pricing; not new design decisions)
- **"all-in" must stay visibly readable at the supported large text sizes.** Let it wrap or adjust
  the layout; price semantics are unchanged. VoiceOver is checked **separately**: complete spoken
  text does not excuse clipped visible text.
- **The entire poster is preserved.** Navigation controls, the status bar and the SANDBOX banner
  must not cover printed content. This follows the existing artwork ruling. Navigation may move to a
  separate area, in the existing visual language. This settles E's observation and supersedes C's
  narrower framing. Both questions (overlay, and top-band loss) are answered: neither is allowed.
- **Scrolling and below-fold checks: C operates the simulator, B specifies the cases and reviews
  the saved captures.** These are labelled **C-operated, B-reviewed**. The device window is agreed
  before use.
- **Consumer Home next-section figure:** the harness value is insufficient because the harness has
  no dock. Use the authorised sandbox test-buyer sign-in if it is available: no fixture writes, no
  payment actions. If it is unavailable, record that blocker specifically and continue the other
  checks.
- **No blanket whole-app acceptance.**

### Results recorded per property (separate columns; one never stands in for another)
| Surface · case | Visible truncation | VoiceOver | Scrolling reachability | Safe-area layout |
|---|---|---|---|---|
| Home feature identity, default size | none (B `c9d6f0d7`) | not checked | n/a (above the fold) | harness only (no dock) |
| Home feature identity, largest standard | **"Ends…" cut** (B `f235ddb7`) | not checked | — | — |
| Home feature identity, a3xl | **"current bid, al…": "all-in" lost** (B `f235ddb7`), fix required | not checked | — | — |
| Listing poster at rest | — | — | — | **fails the 2026-10-06 ruling (B `17c7e670`, measured)**: the hero spans 0–490.7 pt, w/h 0.8009, **complete, not cropped**; the banner covers its first 79 pt (0–78.7); the back chip (5,80)–(79.7,159.7) and the overflow chip (310,80)–(389.7,159.7) sit on printed lines; the fix is positional |
| Listing footer, default | none (B `f235ddb7`) | not checked | case 3 (C-operated) | not stated |
| Feed rows / below fold | pending | pending | **blocked for B; C-operated next** | pending |
| Consumer Home (with dock) | pending | case 5 (Home a3xl caption; records the gap only) | case 4 (C-operated) | dock band 704.0–769.7 pt and 82.0 pt below, signed out (B). **Signed-in figure blocked for B**: B will not type the test-buyer password into the app; C or an attended session must sign in |

### Successor plan: which checks repeat (E; to be confirmed by diff at C's named sha)
Expected changes: batch2 (`8f6bed1e`), the "all-in" layout (`feedRowState.ts:111-113` caption and
its Home renderer) and the listing navigation/poster layout (`ListingHero.tsx`,
`ListingDetailScreen.tsx`).
- **Repeat, if those files change as expected:**
  - **Listing:** all poster/artwork cases, the footer at rest, reservation feedback, safe areas.
    The navigation change sits in the same screen and scroll layout as the footer.
  - **Home feature:** identity block at default, largest standard and a3xl. Frame geometry and the
    per-fixture artwork checks repeat **only if** `HomeFeature`, `EventMedia`, `slots` or the
    harness art rule change.
- **Retained at `d5217530`, re-used if their render path is untouched:**
  - Home artwork selection and frame (batch 1);
  - icons (F-91-6);
  - the withdrawn name-collapse result.
- **New at the successor:**
  - the scroll and below-fold set (C-operated, B-reviewed);
  - consumer Home with the dock (sign-in, or a recorded blocker);
  - VoiceOver on the "all-in" caption;
  - batch2's six harness-art screens, Edit refusals, Listing read-failure/offline and public profile
    (C's owner evidence first, then B).

**B native batch 2 (`f235ddb7`, 2026-10-06): footer, reservation, icons, Dynamic Type at `d5217530`**
- **Closed natively:**
  - R-1 busy state: "Reserving…" with a spinner sits on the second-position outlined Buy Now, and
    the dimmed bid pill carries no pending label.
  - Option B at rest.
  - F-91-6, the Filters glyph.
  - The remembered name collapse: withdrawn, not reproduced.
- **Next-section figure (re-labelled by B):** 790 pt / 62 pt is **harness** evidence. The `_dev`
  route has no dock, because the dock comes from `(tabs)/_layout`. On consumer Home signed out, the
  dock band is 704.0–769.7 pt. **The consumer figure is unestablished:** it needs feed content,
  which needs auth.
- **Open finding for C:** at the largest accessibility size, the Home price caption truncates to
  "current bid, al…", so "all-in" is lost. At the largest standard size, "Ends…" is cut. Whether
  assistive technology still exposes the full string is unverified. Fix: wrap, or shorten so
  "all-in" survives.
- **Blocked:** scrolling and everything below the fold at large sizes, including the feed-row
  title. `simctl` injects no touch, and B's session has no simulator input tool. Next step: an
  attended session or C's simulator tool runs these checks.
- **E check:** viewed `listing-reserving-flyer-light`, `listing-live-flyer-light` and
  `home-feature-flyer-light-a3xl`; all agree with B. The serving tree was `d5217530` and clean
  after the batch.
- **E observation on R-3/R-4, for B to rule on, not yet a finding.** In `listing-live-flyer-light`
  and `listing-reserving-flyer-light`, at rest (deep-linked, unscrolled), the 4:5 listing poster
  starts at the top of the screen.
  - The top band of the poster sits under the status bar and the SANDBOX banner (≈79 pt, per B's
    batch 2 measurement): TL/TR corner labels, "SYNTHETIC TEST FLYER", "FIXTURE NIGHT" and most of
    "EXAMPLE.COM/TICKETS" are not visible.
  - The back and overflow chips sit over the printed lines "PLACEHOLDER ONE" and "21:00".
  - Source: `ListingHero.tsx:78-90` says the artwork runs under the status bar on purpose. Only the
    controls get the top inset, and they are drawn inside the poster frame.
  - This conflicts with R-3 ("full poster content preserved") and with the R-4 review scope
    ("navigation reachable without covering printed text").
  - A production build has no SANDBOX banner, but the status bar and Dynamic Island still cover the
    top of the poster.
  - B has not yet stated R-4. **R-4 stays open** until B rules on this. If B confirms, it is a
    concrete design conflict between full-bleed-under-the-status-bar and full-poster-visible, and
    may need an owner ruling.
  - C's input (2026-10-06): the chip overlay and the art running under the status bar come from one
    decision. When R-4 moved the identity text off the poster, the navigation stayed on it. E notes
    these are **two questions**, not one: (a) may navigation overlay printed content? (b) may the
    status bar and banner hide the top band of the poster at rest? (b) is content loss whatever the
    answer to (a).
  - **Scroll-check capability:** C's session has working simulator touch input (device points
    393×852; swipes must start more than 4 pt inboard of an edge). B's does not. **The owner
    chooses who runs the scroll and below-fold checks.**

**Carry-forward from `f3f08930` to `d5217530`.** No durable B or native evidence exists at
`f3f08930`, so nothing carries. The full native review is owed at `d5217530`.

**Queued successor work (C, not in the candidate under review).** Branch `v3/consumer-batch2`
(`/Users/josetascon/snatchit-v3batch`) is at `8f6bed1e54604c897a322514f542ffaea17e9fea`; it was
`52a4bd29` earlier on 2026-10-06. Everything below is unreviewed by B or E:
- `6c562dcf`: F-1, Edit listing stops spinning on its refusal paths.
- `8b437942`: F-4, Publish says "Sign in required".
- `a587d2a1`: `?art=` on My listings, Bids, Tickets, Search, Checkout and Send/Order
  (`v3-tickets?screen=send|order`). Every row takes the selected poster, and `all` cycles the
  shapes.
- `8f6bed1e`: the focal-point note in C's inventory doc.

C corrected its own record: `v3-tickets` mounts the real Send and Order screens (`:32-33`), while
`transfer-states` is a component gallery.

**Carry-forward check at `8f6bed1e` (E, by diff; it applies only if C names this sha).**
- No Home or Listing-detail render-path file changed: `EventMedia`, `slots`, `url.ts`,
  `HomeFeature`, `ListingHero`, `ListingDetailScreen`, `home.tsx`, `FeedRow`, `v3-home.tsx`,
  `v3-listing.tsx`, the theme, `IconSymbol` and `BarAction` are all absent.
- The shared `src/lib/media/harnessArt.ts` changed, but additions only (numstat `27 0`, zero
  deleted lines; C says the additions are `ART_SHAPES` and `listArt`).
- Verdict (corrected 2026-10-06): **only evidence that exists carries.** Home's completed checks
  (B batch 1, `c9d6f0d7`) would carry to `8f6bed1e`, because none of their render path changed and
  the only shared file changed by additions alone. **Listing and every other check have no
  committed B or native evidence, so nothing about them carries; they stay pending.** E re-checks
  at the final sha C names.

## Native acceptance loop — restarted 2026-10-05 on C's named successor (owner)
The owner restarted the loop on C's named successor. Completing `f3f08930` first is **not** required.

**Status of `f3f08930` (accurate wording):** B reported starting a native review of `f3f08930`. The
only record of that start is C's commit message at `168e794a`, which says B's review "could not
render" the reserve-in-flight state. **No durable B review evidence survives.** As of 2026-10-05
there was no B document, no committed capture and no file in any session scratchpad. C's two Home
captures (`home-flyer-{light,dark}.png`) were in a temp scratchpad and are gone. Only E's written
description of the Light capture remains (below). **Acceptance remains pending.**

**Successor (now named `d5217530`, above):** it had to contain all three of the following (owner, 2026-10-05):
1. **Listing artwork selection.** At `168e794a`, `app/_dev/v3-listing.tsx` has no `?art=` and the
   cover is always null (`:100-101`), so Listing shows only the missing-artwork plate.
2. **Home feature selection.** A bug has been *reported*, but E has not reproduced it. C reproduces
   it and corrects it if present. Home's harness accepts `?art=`; accepting the parameter is not
   the acceptance test. For each key (`flyer subject subject-wide tall wide square missing`), the
   named poster must visibly appear in the **featured** frame. Source note, not a diagnosis:
   `withArt` assigns the art to `rows[0]`, while `app/(tabs)/home.tsx:635` features `flat[0]`
   after `groupByEventDate` and any filtering. Wherever those two differ, the art lands on a
   plain row.
3. **The reserving seam** (`168e794a`).

C delivers one clean commit (full sha) and completes the owner-authorised feature-branch push.
Native code is rebuilt only if a native file changed.

**Metro: one operator for the review window, agreed between B and C before any restart.**
`:8081` is pid 2172 (`expo start --port 8081`), started 2026-09-26 16:56. Its cwd is
`/Users/josetascon/snatchit-refund`, at `f3f08930` and clean on 2026-10-05. The owner reports that
B started it. The process itself does not show who started it. Nobody restarts or repoints it until
B and C agree on the operator. E's proposal: C operates Metro and the simulator connection, and B
operates the app only. After the repoint, C confirms the serving directory, the sha, clean status
and that the dev client on `SN V3 393x852` is connected to that server. If the serving tree changes
during the review, B pauses, lists which captures became uncertain, and keeps every capture whose
provenance (sha, start/end check) is established. B's `:8083` web harness
(`/Users/josetascon/snatchit-v3render`) is never native evidence.

**Ownership of files:** B owns the review documents and captures. E owns this record and edits
nothing else. Captures go to `docs/product-v3/native/<successor-sha8>/` during the review, named
`<surface>-<state>-<fixture>-<appearance>[-<textsize>].png`. Each review document names the full
sha, the device (`SN V3 393x852`, iPhone 16, UDID `52282259-…48`), iOS 26.5 23F77, and the fixture.
E commits only `V3_ACCEPTANCE_RECORD.md`, by explicit path, after `git status` shows no staged
B files.

**Carry-forward rule:** no surviving native evidence closes any check below, so the full native
review is re-run at the successor and every capture is preserved. Later, evidence carries to a new
commit only if both of the following hold:
- **It is durable and attributable.** The file is committed under `docs/product-v3/native/<sha8>/`
  and states its sha, device, runtime, fixture, appearance and capturer.
- **Nothing in its render path changed** between the two commits. That covers the screen file,
  every shared component, layout or metric it uses (for example `HomeFeature`, `FeedRow`,
  `EventMedia`, `slots.ts`, `url.ts`, `featureMetrics`, `sections.ts`, the theme tokens,
  `IconSymbol` and the footer `BarAction`), and the harness and fixture files that select its
  data (`app/_dev/*`, `assets/qa-posters/*`, `devPosters.ts`).

E checks the diff per check and records the result. An unchanged screen file alone is not
sufficient.

| Check (both appearances) | Implementation (C) | B independent review | Native evidence (sim) | Repeat at successor? |
|---|---|---|---|---|
| Home: 4:5 feature, identity below, no gradient, next section measured; **each** of `flyer`, `subject`, `subject-wide`, `tall`, `wide`, `square`, `missing` visibly in the featured frame | `e902f59a`, `ec61bfa7`; feature-selection fix `6100dee1` (in `d5217530`) | **B `c9d6f0d7` at `d5217530`: verified** (`B_NATIVE_REVIEW_d5217530.md` batch 1) | **sim, 14 captures** `native/d5217530/home-feature-<art>-{light,dark}.png` (1179×2556) | done at `d5217530` except Dynamic Type and safe areas (still to come) |
| Listing: 4:5 poster, info beneath (R-4), navigation reachable; same artwork cases | `f3f08930` (`ListingHero`); `?art=` in `6100dee1` | pending: captures committed in `f235ddb7` (`listing-live-{flyer,missing,subject-wide}-{light,dark}`), but B has stated no R-4 verdict | captured, not assessed | open; see E's poster-under-status-bar observation |
| Footer Option B at rest | `12be25d6` | **B `f235ddb7` at `d5217530`: matches the approval** (bid first, filled, minimum inside; Buy Now second, outlined, price and sub-line) | sim `listing-live-flyer-{light,dark}.png` | done at `d5217530` (Light/Dark at default size; Dynamic Type on the footer not yet reported) |
| Reservation feedback (`?reserving=1`, second-position `Reserving…`) | `f3f08930` + seam `168e794a` | **B `f235ddb7`: verified; R-1 busy state closes natively** | sim `listing-reserving-flyer-{light,dark}.png`; no reservation made | done at `d5217530` |
| Icons (native rendering, separate from B's source cmap finding) | `f3f08930` (IconSymbol) | **B `f235ddb7`: F-91-6 closes** (Filters = tapering bars 58/46/34 device px, against equal 41 px at `91062ab1`); magnifier is drawn | sim Home captures | done at `d5217530` |
| Dynamic Type (largest standard + accessibility sizes), scrolling, safe areas | n/a | **B `f235ddb7`: Dynamic Type on the Home identity reproduced** (default complete; largest standard cuts "Ends…"; a3xl cuts "current bid, al…", losing "all-in": **open finding for C**, a11y value unverified). **Scrolling: blocked** (no touch injection in B's session) | sim `home-feature-flyer-light-{3xl,a3xl}.png`, `listing-live-flyer-light-{3xl,a3xl}.png` | open: all-in caption fix; scrolling and below-fold checks need an attended or touch-capable session |
| Event-name truncation (B's recollection) | — | **B `f235ddb7`: one-character collapse NOT reproduced; withdrawn.** Feed-row title comparison blocked (below the fold) | — | closed as not reproduced; row title pending scroll access |

**After this priority review:** E reconciles the remaining consumer-screen coverage (Search,
Create/Edit, My listings, Bids, Tickets, Order, Send/Receive, Profile/Settings/Appearance/Auth,
checkout presentation states) against `V3_COVERAGE_MATRIX.md` and `V3_RECONCILED_COVERAGE_20260924.md`.
Passing Home, Listing and the footer is **not** whole-app acceptance.

**State at 2026-10-05 22:25 (E checked):**
- B acknowledged in `bee31c88` and `ca00a250` (`B_NATIVE_LOOP.md`). B states that its 2026-09-26
  native pass produced no durable evidence.
- **Metro operator: C, agreed by B (`ca00a250`).**
- `v3/midnight-app` in the serving tree is now at `168e794a`, with C's uncommitted artwork work
  (`v3-home.tsx`, `v3-listing.tsx`, `harnessArt.ts` and two tests).
- B correctly waits for a clean, named commit.
- `native/` exists and is empty.

## Remaining consumer screens: coverage at `168e794a` (E, 2026-10-05)
Read-only reconciliation by three bounded subagents. E spot-checked the consequential claims in
source: F-1, F-4, F-91-2 (0 `auto_released` cases), Send not-found with no retry, the Bids status
filter, payControl's 11 outcomes, the `✎` glyph and the fee label.

**Headline (corrected 2026-10-06 against older records).** No screen below is accepted. No V3-form
screen has native or device evidence from B. Every V3-era B render is web class. B's earliest
record for every group except Appearance is `docs/design-audit/FRONTEND_DESIGN_AUDIT_20260917.md`
(2026-09-17, pin `6561d1f`, V2, source only). "V3-pre" means V3 tokens before the redesign commits.

| Group | Latest B evidence (class, version) | Status wording |
|---|---|---|
| Search | V2 source, 09-17 and the 09-21 baseline. `404bce38` does not touch it | never reviewed in V3 form; V2 reviewed at `6561d1f` |
| Create | `404bce38`, source + computed contrast, V3-pre | never reviewed in V3 form; V3-pre source at `404bce38` |
| Edit listing | V2 source, 09-17. Only a colour-access count at `2619b9e1` | never reviewed in V3 form; V2 at `6561d1f` |
| My listings | `404bce38`, computed contrast, V3-pre | never reviewed in V3 form |
| Bids | `404bce38`, source, V3-pre | no rendered B review |
| Tickets | `d981727e`, computed contrast, V3-pre | no rendered B review |
| Order / Receive | buyer transfer cards via the synthetic gallery, web, Light, `91062ab1`. Those captures are **cited, file missing**. The Order screen itself was never rendered | gallery cards: unknown (evidence missing); Order screen: never reviewed in V3 form |
| Send + gallery | web, Light, `91062ab1`. `comparisons/send_light_91062ab1.png` is present; the full-gallery captures are **missing** | reviewed (web, Light) at `91062ab1`, stale since `a5c0bfc6` / `cbb2df6b` |
| Checkout | web, 5 states × Light and Dark, `d374bd3f` (`comparisons/checkout_states.png` present). At `91062ab1`, B corrected its own fixture count in source | reviewed (web) at `d374bd3f`, stale since `65052bfc` |
| Profile (own) | web, avatar only, `91062ab1` (`avatar_closure_91062ab1.png` present). Also B's analysis of the owner's Build 24 phone screenshots; those originals are not in the repo | avatar reviewed (web) at `91062ab1`; the rest never reviewed in V3 form |
| Public profile | V2 source only | never reviewed in V3 form |
| Settings | `404bce38`, source, V3-pre | never reviewed in V3 form |
| Appearance | none of the screen; only B's pkg8 boards and Light/Dark resolution checks in web renders | no B review found in any record checked |
| Auth | `404bce38`, source (brand-mark tint), V3-pre | never reviewed in V3 form |

**What changed from E's 2026-10-05 wording:**
- Search and Edit were last reviewed in V2, not at `404bce38`.
- Own Profile has a web render (avatar only).
- Appearance has no B review in any class.
- Receive gallery captures are cited but missing, so their coverage is unknown.
- Checkout's render covered both appearances.

| Group | Harness reach (`app/_dev`) | Open findings present at `168e794a` | Owed |
|---|---|---|---|
| Search | results, empty-with-filters. **Unreachable:** hint, loading, no-match, error/offline, inline failure | — | variants; B render L/D; sim |
| Create | form, `invalid`, `risk=*`. **Unreachable:** pickers, photo added, publishing/gate alerts | F-4 signed-out publish silent (`CreateListingScreen.tsx:510-511`); F-5 picker no-results; F-7 two banned-content wordings; F-8 no offline detection | fixes; variants; iOS picker no-crop test (R-3) |
| Edit listing | **no harness, no board** | F-1 permanent spinner (`edit/[id].tsx` "Not allowed" / "Cannot edit" return without `setLoading(false)`); F-2 6 vs 16 platforms; raw `error.message` | fix; board or ruling; harness |
| My listings | populated, empty, error/offline. **Unreachable:** loading, Ended/Reserved rows, dialogs | F-25 dialogs differ from Listing detail's | render all filters; sim |
| Bids | default/past/all, empty/failed/error/offline. **Unreachable:** loading | 404 §4.5 query excludes expired/reversed (`bids.tsx:247`), depends on A/D; no Light design | B Light design; render; sim |
| Tickets | populated/past, empty/error/offline. **Unreachable:** loading, refresh failure | D-8 and the populated real-data path depend on A/D | render; sim |
| Order / Receive | one fixed `seller_sent` case only | F-20 failed proof URL silent; F-21 raw RPC error in an alert | variants for pending/confirmed/auto_released/disputed/expired/reversed |
| Send | `seller_sent` plus the gallery's 7 seller cases. **Unreachable:** pending, delivery gate, mark-sent outcomes, loading/error | Not-found has no retry (`send/[id].tsx:349`); F-91-2 (no `auto_released` gallery case) | Dark render; variants |
| Refund wording | gallery only | "initiated" wording (`90235b74`) never rendered by B; gallery label "both figures" stale | B re-render |
| Checkout | 13 fixtures cover all 11 `payControl` outcomes plus 5 extra states | Fee label "Service fee" vs "Service fee (10%)" (`CheckoutView.tsx:172` vs `ListingDetailScreen.tsx:1231`); uppercase `label` token (TOTAL / HELD FOR YOU) vs the mixed-case ruling, needs a ruling; hairlines need B's call | C names the final commit; B render of every state × L/D; sim; Dynamic Type |
| Profile / public profile | own profile avatar/noavatar. **Unreachable:** loading/error, public profile | `✎` edit badge (`profile.tsx:315`) absent from Inter, falls back to another face; F-10 sign-out unconfirmed; F-11 unblock unconfirmed | B review; sim glyph |
| Settings / Appearance | hub variants, appearance system/light/dark | Header split (hub inline vs `SettingsHeader` uppercase); F-12, F-14; selection cue is red only, needs B | ruling; B review; sim live appearance switch |
| Auth | **not in `_dev`**; signup 2–4 and reset need a real session or recovery link (forbidden) | F-13 bare-title alerts; F-9 is A/D's | fixture route; B review |

**Across all groups:** the 4:5 artwork commits (`ec61bfa7`, `99dd6f36`, `59658b1a`, `cbb2df6b`)
are not visible in any of these harnesses, because every fixture's cover is null. Each needs the
same `?art=` selection C is adding to Home and Listing. Account-switch avatar isolation is **not
authorised**; it is recorded as excluded, not as a gap.

**Order of work after the priority surfaces:**
1. C extends artwork selection to these harnesses and adds the missing state variants.
2. C fixes F-1 and F-4 (behaviour defects).
3. Rulings for B/owner: checkout fee label, uppercase `label` token, Settings header, Edit
   platforms.
4. B renders each group in Light and Dark at one named sha, with native captures under
   `native/<sha8>/`.

## Installed candidate `f3f08930` (C, clean tree; = `e7af5242` Stripe patch + one UI commit) — historical, preserved
- **Implementation:** R-1 busy state keyed by action kind (`ListingDetailScreen.tsx:1465-1480`, both slots carry `Reserving…`/`loading`); vector icons via IconSymbol (filter = three decreasing lines); listing identity below the poster (R-4, `ListingHero`); 8 fixtures, 282,812 B within the 409,600 B budget (not raised). Stripe patch `e7af5242`: A PASS (fresh install + upstream hashes).
- **Build and install:** Debug dev client, `XCODEBUILD_EXIT=0`, bundle `com.jdt-inc.snatchit` on `SN V3 393x852` (iPhone 16, UDID `52282259-961E-4A1A-B32B-CEFA858CFF48`, iOS 26.5 23F77, Xcode 26.6 17F113). **Limit:** there is no embedded `main.jsbundle`; the JS is served by Metro (`localhost:8081`) from C's main worktree, clean at `f3f08930`. Captures prove that serving tree, not an embedded artifact. A Release build was not used because `__DEV__`-gated fixtures resolve to nothing there. Detached copy for diffing: `/Users/josetascon/snatchit-review-f3f08930`.
- **Native evidence (C, implementation-owner, not B's review):** `home-flyer-{dark,light}.png`. E viewed the Light capture: all four corner words and both edge rules present; the identity block below the poster in dark ink on the light canvas; the poster's bottom text band legible (no gradient); filter icon = three decreasing lines beside a magnifier; the "This week" heading and the **top part of the first row** visible (in this capture the row's third line is cut at the bottom edge, so B should measure "fully visible" rather than take it from web). Dock absent (the `_dev` route sits outside the tab navigator).
- **B native review:** B reported starting it. No durable evidence survives, so it is pending. The loop moved to the successor on 2026-10-05 (above). The captures above no longer exist on disk.

## Open corrections at `3c6f15a4`
- **Filters glyph (B F-91-6): still the hamburger** — `IconButton.tsx:35` `filter: '≡'`. Correction open with C.
- **Footer (R-1): selection closed; implementation has a behavioural REGRESSION at `12be25d6`–`3c6f15a4`** (B `4882cd6a` §3, verified by E at LDS:1275-1276/1458-1470): `Reserving…`/`loading` stay on the primary slot, which is now the bid, so Buy Now's reserve call shows no feedback (CFT-203). Fix: key busy on the action kind; add a `reserving` harness seam. B rendered review and native checks still owed.
- **Icon glyphs:** per B's cmap measurement (not re-verified by E), `≡ ⌕ ✕ ⋯` are absent from the bundled Inter/Oswald and render in an iOS fallback face. B recommends drawn marks.
- **Fixtures:** B's `fx-*` set withdrawn; two synthetic subject photos proposed (`fixtures-proposed/`) for C to move into `assets/qa-posters/`.
- **Evidence columns are tracked separately:** implementation (C) · independent rendered review (B) · native results (simulator `SN V3 393x852`, actual device and runtime recorded per capture). None of the three substitutes for another.

## Candidate `3c6f15a4` (supersedes `882b0e8d` and `1e4d47d6`; C, clean tree, 2898 tests)
- `3c6f15a4` changes only `assets/qa-posters/flyer-dense-4x5.png`, replacing three missing-glyph boxes (header separator, two footer separators) with ASCII. E viewed the file: no box glyph remains. The generator's ASCII gate is not in the repo, so it is not reviewable here.

### Recorded at `882b0e8d`
- `882b0e8d` regenerates the flyer fixture (no self-overprint; printed words in all four corners and on both side edges, verified by E viewing the file) and adds a behavioural gate test (markers resolve to null with `__DEV__` unset, with a gate-forced-open control). Fixtures now 172 KB (a test pins a 400 KB budget). C re-measured: frame 391×489 (0.800), `contain`, not upscaled, zero intersections, zero gradients.

### As first recorded at `1e4d47d6`
- Carries R-1 (`12be25d6`), R-2 (`e902f59a`), R-3 (groups 1–4) and bundled synthetic poster fixtures (`assets/qa-posters/`, six PNGs, ~132 KB in the binary; gate: `__DEV__` + a `dev-bundled:` cover prefix; flyer uses EXAMPLE.COM and a fictional address).
- **Implementation-owner evidence (C, web, 393×852, 14 captures Light+Dark), not B's review:** feature frame 391×489 (0.800); poster `contain`, not upscaled; zero app-element rects intersecting the image rect; zero gradient inside the frame; the two-sided corner probe shows no crop for 4:5, fitted 9:16/16:9. **Next section:** poster 106–595, identity 608–683, next heading 683–740, **first row fully visible 740–822**, second row cut at 845.
- ~~Known fixture defect~~ fixed at `882b0e8d`. Its missing-glyph boxes were fixed at `3c6f15a4`.
- **Native: BLOCKED.** The build on `SN V3 393x852` fails compiling `@stripe/stripe-react-native` 0.50.3 under Xcode 26.6 (`STPPaymentStatus` enum redeclared: `SWIFT_ENUM_FWD_DECL(NSInteger…)` vs `NS_ENUM(NSUInteger…)`). The fix touches the payments SDK, so the owner and A decide. **No native evidence is recorded until a build succeeds.**
- B review: pending, **at `3c6f15a4`**.


## Not settled, recorded so it is not assumed
- ~~Listing hero identity placement~~: **ruled 2026-09-25 → R-4 (beneath the poster).** At `99dd6f36` the hero is 4:5 with the identity still overlaid on the poster's bottom band. B's `poster_45_direction_91062ab1.png` panel 3 shows that overlay covering a flyer's printed venue and lineup.
- **Home feature height cap** (~45% of the screen): **explicitly deferred** by the owner. Full 4:5 first.

## Earlier closures (for reference; B's evidence, web class unless stated)
- Avatar: square derivative matches its request (84×84), same source, same visible crop on dock and Profile. B `a624cc58` at `91062ab1`. Account-switch isolation still pending (not authorised).
- Home Light missing-artwork feature text: fixed `55838996`; B `8bda19a1` at `0677c80e` (#141519, 18.24:1). **Superseded in layout by R-2** (text moves below the poster).

# D — independent RC2 verdict: `integration/rc-20261012` @ `e2b9498b` (2026-10-12)

**Who:** Claude D, session `9651e05a` (fork), independent release-safety reviewer; SSD checkout `repos/snatchit-drecords`,
branch `review/d-records-20261005`. Address at the time of writing per ListAgents/A: `Claude D Vendor product (fork) [de2d49]`.
**Keyed to:** **`e2b9498b71191d308a33d00bce87a0832acc8d55`** (tree `3e9813751a248ee892be37a6d7a258db4628361e`), A's
`CANDIDATE_MANIFEST.md` amendment 2 (23:06Z). Base for the delta: RC1 `48d20ca1` (my verdict `e64dfe53`,
`D_C4_AND_CANDIDATE_SAFETY_RC20261012.md`). Everything in that record about `web/`, `admin/`, `supabase/`, `.github/`, rulesets,
CI permissions, migrations and the AUTODEPLOY binding carries over **because the diff shows those surfaces unchanged (§1)**; what
changed is re-reviewed here.
**What this session did not do:** no production write, refund, payout, setting change, deployment or migration; no production
read (none was needed — every fact below is from git, the local schema reference and the GitHub API); no rerun of the historical
reconciliation; no force push. One focused read-only subagent (§8), as the owner allowed.

## 1. Identity and composition — verified
| Claim (amendment 2) | My check | Result |
|---|---|---|
| `e2b9498b` on origin, tree `3e981375…` | `git rev-parse origin/integration/rc-20261012`, `^{tree}` | match |
| Chain `48d20ca1 → 53a16239 (C 287e938b) → d2651782 (A 084de270 ⊃ 50e74efb) → e2b9498b (C caa3fa03)` | `git log --format='%h %p' 48d20ca1..e2b9498b` | match; `caa3fa03` = `origin/v3/rc-fixes-20261012`, `084de270` = `origin/fix/rc-f6-settled-recheck-20261012` |
| Tree = clean composition `48d20ca1 + caa3fa03 + 084de270` | every file in `git diff --name-only 48d20ca1 e2b9498b` (41: 4 `app/`, 11 `src/`, 26 `tests/`) compared blob-by-blob to its source branch | 39 from `caa3fa03`, 2 from `084de270`, **0 touched by both, 0 from neither, 0 blob mismatches** |
| Restricted surfaces untouched | `git diff --name-only 48d20ca1 e2b9498b -- supabase .github eas.json app.json package.json package-lock.json web admin components tools scripts` | **empty** |
| `supabase/` = gate; `web/` = live `0b389584`; `admin/` = live `f7e7e85f` | `git diff --stat` each | 0 / 0 / 0 files |
| CI run 38319986862 belongs to RC2 | `gh run view --json headSha,jobs` | `headSha = e2b9498b…`, `conclusion success`, 5/5 jobs success, **0 steps with a non-success conclusion** |
| Gate PR #100 | `gh pr view/checks` | head `e2b9498b…`, base `release/production-gate-20260918`, **draft**, `mergeStateStatus CLEAN`; the six required checks (Immutability + ordering on run 38319995006; Migrations, Typecheck/Lint/Unit, Web build, Admin console, Deno on run 38319986862) all `pass` |
`d2651782` and `48d20ca1` are not candidates (B-D10 open on both), as the manifest says.

## 2. C4 at `e2b9498b` — both roots, reconciled
Same unmodified scanner (sha256 `d0db2973…` = blob `fc9c3296…` at cc68f284), same reference `pkg151_rehears` re-checked at run
time (164 rows, max `20260925010000`). The 16 planted-defect controls and the empty-catalog negative control from RC1 carry
because neither the scanner nor the schema changed.
| Root | resolved | MISSING | UNRESOLVED | exit |
|---|---|---|---|---|
| `app/ src/ packages/` | 63 from / 25 rpc | 0 | 16 | 0 |
| `web/ admin/` | 30 / 9 | 0 | 16 | 0 |
- **Reconciliation:** grep-enumerated supabase sites 104 (app) / 41 (web/admin); every scanner-only site is `Array.from`,
  `Uint8Array.from`, `utf8.from` or a `.schema('kernel'|'venue')` line reported one line above its `.from`; every grep-only site is a
  comment or a two-line `storage.from(BUCKET)`. Nothing unaccounted for, either root.
- **Sites added/removed by RC2 vs RC1: none** (text-level comparison of the 104 sites). **The only query change in the 41 files is
  F2's `.select('id')`** appended to the `listings` update chain (`app/listing/edit/[id].tsx`); `listings.id` exists and the scanner
  checked it on the chain.
- **Dynamic (UNRESOLVED) sites:** 15 of the 16 mobile sites live in files unchanged since RC1 (`git diff --stat 48d20ca1 e2b9498b
  -- <file>` empty), so their RC1 resolution carries. `CheckoutNative.tsx` changed (F4); its one dynamic site is
  `.select(LISTING_SUMMARY_COLUMNS)` — the constant lives in `src/lib/checkout/listingSummary.ts` (unchanged): `cover_image_path, event_name, venue, event_date, event_time, reserved_until, quantity, ticket_type` — **8/8 exist on `public.listings`** (my query). The file's other two selects are literal and were scanner-checked. All 16 web/admin sites: files unchanged (web/admin 0-diff).
- **Blind-spot hand pass (the scanner's silent classes) at RC2:** identical set to RC1 — held builder `useListingRealtime.ts:131`
  (`bids.created_at`), `.or()` at `profile.tsx:157` / `explore.tsx:165` / `web listings.ts:87`, `.not()` via
  `applyBlockedSellerFilter` (`listings.seller_id`), nine held-builder columns in `web listings.ts:87-110`; the `home.tsx:426-446`
  hits are JS array `.filter`, not query builders. All columns exist. No `.schema()` held in a variable, no interpolated table
  name, no `//`-in-string on a call line, no `.js` client file.
- **C4 verdict: PASS at `e2b9498b`**, same limits as RC1 §2.7 (existence only; not RLS, grants, types or return shapes).

## 3. Fix review — the RC2 delta, file by file
Pre-freeze I read `d27aa449..5b889443` from the shared object store (recorded privately); at the frozen tip every file was
re-checked by composition (§1) and the later commits read in full.
| Commit | Finding | Verdict | What I checked / limits |
|---|---|---|---|
| `1117731e` | **F1** crash on crafted link | PASS | `checkoutRouteParams.ts`: `^\d{1,12}$` + safe-int → malformed = absent (0); estimate via canonical `buyerTotalCents(dollarsToCents())`; `expectedTotalCents: acceptedTotalRef.current \|\| undefined` so the server computes. CP1–CP6 (CP6 is a source-text pin) |
| `1117731e` | **F4** checkout mode (owner focus) | PASS | `parseCheckoutMode` → `'buy_now' \| 'auction' \| null`, never defaulted. `checkoutMode === null` ⇒ only `readSettledPayments` runs: settled → completed (same effects as the existing `already_settled` branch), refund → its state, else `payment_status_unknown`/"Check again"; **no intent**. `decideCheckoutSetup`, `createPaymentIntent`, `finalizePurchase` all receive the parsed mode; `recheckPayment` refuses without one. Params frozen at mount (`useState(() => freeze(raw))`); the only `params` uses are the declaration and the freeze. returnURL = `buildCheckoutReturnURL({listingId, mode, totalCents, bidAmount})`. CM1–CM10, FP1–FP6, the 3-D Secure pinned literal updated. Cosmetic: a cold-start return shows "—" for event/venue (URL carries mode + totals only) |
| `e241e5bf` | **F2** edit "Saved" with 0 rows | PASS | `.update(…).eq(id).eq(seller_id).select('id')`; `written.length === 0` → "Save failed", form kept. Assumes SELECT visibility = UPDATE visibility (true under the owner policy). EL7a–c |
| `7ab44c14` + `5edde728` | **F3** signup write swallowed; **B-D9** | PASS | `persistProfile` → `{ok}`/`{ok:false, what}`; failure surfaced in plain words, no credential; retry skips the consumed OTP and repeats only the idempotent writes; **B-D9 (`sendCode` resets `profileRetryRef`)** closes the path B found — change number → resend → any code → retry flag skipped verifyOtp. **My pre-read noted the remount edge, not this resend path; B found it.** §10 pins + mutant |
| `d2fdc9ef` | **F5** payout-return truth (owner focus) | PASS | Claims nothing: spinner + "Checking your payout setup…", `router.replace('/settings/payout-setup')` after 400 ms; payout-setup still verifies via `status_only`. PR1–PR4 (source-text pins); one new user-facing string |
| `50e74efb` + `084de270` | **F6** settled rechecks (owner focus) | PASS (reviewed earlier, both commits; RED 4/6 → 5/12, GREEN 12/12 reproduced) | RC2 carries exactly these two commits (§1 blob check). Transaction argument from `settle_verified_payment` stands |
| `7a1d95d5` | **F7** recovery hold | PASS | `onRecoveryFailed` on verifyOtp error, exchange error, thrown exchange, token-less recovery link; shell wires `setIsRecovery(false)`; PKCE success keeps the hold |
| `19959c11` | **D-RC-4** | PASS | `iso()` from local Y/M/D; file unchanged at tip |
| `5b889443` | **Guard pins E9 / W2 / payout-landing** (owner focus) | W2 and payout-landing: restated, not loosened. **E9: loosened in one region (D-RC2-2, found by the adversarial check, verified by my replay)** | E9: every exact-spelling `setPaymentStatusUnknown(false);` must sit immediately after a settled-read throw (regex count = clear count, 2 = 2) and no mention may precede the FIRST read — stronger on adjacency, but the pre-5b889443 pin forbade ANY mention of `setPaymentStatusUnknown` over the whole region up to `decideCheckoutSetup(`, and the new pin leaves `:232-255` guarded only by the exact-spelling count. Replayed with node: inserting `setPaymentStatusUnknown(false as const);` between the no-mode read and its throw (a clear reached by a FAILED read — the very invariant E9 names) **passes the new E9 and fails the old one**. The shipped source satisfies the invariant today (2 clears, both guarded); the pin is weaker than claimed. W2: count 2→3, the real invariant (`.from('payments')` never in the screen) kept verbatim. Payout landing: a **timed** `router.replace`, **no `router.push`**, target `VERIFY_ROUTE`, Profile forbidden — stronger routing pin; the target change is F5 itself. The tests' `between()` helper asserts both markers exist (non-vacuous); all markers present |
| `f252a0e8` + `287e938b` | **B-D7** A3XL money rows (release requirement) | PASS (source) | Reuses the shared `identityStacks` 1.3× rule; stacked amount `adjustsFontSizeToFit` with `AMOUNT_MIN_FONT_SCALE`; default styles pinned byte-identical (MR6); scope narrowed to money rows only (MR9: transfer detail rows and Send untouched — `send/[id].tsx` has 0 literal changes). **Copy:** MR8 pins none changed; my JSX-text grep over the diff found no changed text node; a literal-set diff showed only style/prop fragments. Pixel identity at default size and the A3XL re-measure are **B's binary review**, not mine |
| `794613a9` | harness mocks | n/a | 12 test files, +2 lines each: `useWindowDimensions` mocked with `fontScale: 1` |
| `caa3fa03` | **B-D10** winner push `'bid'` | PASS | `navigateToWinnerCheckout` → `mode: 'auction'`; CM2 adds `'bid'` as rejected; CM11 pins both pushes; CM12 pins they are the only pushes. **This is a producer defect introduced by F4 that my pre-freeze read did not catch — I verified the parser and not its callers; B did.** §4 is the enumeration that read should have contained |

## 4. Producers of the checkout route at `e2b9498b` — enumerated (the check B-D10 showed was missing)
- **Mobile pushes:** exactly two, `src/screens/ListingDetailScreen.tsx:784-785` (`mode: 'buy_now'`) and `:799-800`
  (`mode: 'auction'`) — `git grep` for `pathname: '/checkout` and for `router.push|replace|navigate(…checkout`, `href=…checkout`,
  `Linking.openURL(…checkout` over `app/ src/` (tests and `_dev` excluded) finds nothing else. Every `mode:` literal in `app/ src/`
  was listed: the others are the push-challenge `mode: 'silent'`, a date/time picker, and type declarations. (A first pass used
  `git grep -E` with `\s`, which that grep does not support and which silently matched nothing — redone with `[[:space:]]`.)
- **3-D Secure return:** `buildCheckoutReturnURL` carries `mode`, `totalCents`, `bidAmount`; frozen params ignore a later in-place
  replacement.
- **Server-side link:** `supabase/migrations/058_notification_producers.sql:114` — the `auction_won` notification ("You won! …
  Complete checkout to secure your tickets.") carries `link = '/checkout/<listing_id>'` with **no mode**. Before F4 that would have
  read as auction; at RC2 it would be a no-mode arrival. **It does not reach the mobile checkout:** the push handler
  `routeFromNotificationData` (`src/providers/NativeAppShell.native.tsx:250-254`) sends every listing-scoped type, `auction_won`
  included, to `/listing/<id>` — from which the winner's "Pay now" is the B-D10-fixed push — and the mobile app has **no in-app
  inbox** (no `.from('notifications')`/`get_inbox` in `app/ src/`); the `link` column is read only by the unchanged web app into
  its own checkout. Verified non-issue for RC2; recorded because it is exactly the class B-D10 belongs to.
- **Arbitrary external deep link** `snatchit://checkout/<id>`: **a mode-less one** lands in the no-mode branch and fails closed
  ("couldn't check whether this has already been paid" / "Check again") — but see D-RC2-1 for the failed-read case. **A link that
  carries `?mode=buy_now|auction&totalCents=…&eventName=…&venue=…` is accepted exactly like the 3-D Secure return** (the client cannot
  tell them apart): the full setup runs, the URL's event/venue are displayed until the listing read replaces them, and the URL's
  `totalCents` seeds `acceptedTotalRef`, so a "The total changed … It was $X" notice can echo a URL value. Money is safe — the server
  decides hold ownership, winner and the charged total (409 on mismatch) — and this is pre-existing (documented at
  `checkoutRouteParams.ts:4`), but my first description of it as "fail closed" was wrong; the adversarial check corrected it (§8).
- Informational, pre-existing, unchanged by RC2: `routeFromNotificationData` reads `data.listingId` (camelCase) while the SQL
  `metadata` carries `listing_id`; whether push payloads are camel-cased is decided in the unchanged `notify-*` functions.

## 5. No unauthorised schema, money-execution or production-setting change
- §1: `supabase/`, `.github/`, `eas.json`, `app.json`, `package.json`, `package-lock.json`, `web/`, `admin/`, `components/`,
  `tools/`, `scripts/` all unchanged vs RC1 (which was itself gate-equal on `supabase/`).
- Client RPC verbs: the 104 supabase sites are textually identical between RC1 and RC2 — **no new `.rpc()` name, no new table**.
- Added lines in the RC2 diff carrying a publishable/secret key, JWT, `.supabase.co` host, Stripe account id or `service_role`:
  **0 (grep over `+` lines of `git diff 48d20ca1 e2b9498b -- app src tests` for `pk_live|pk_test|sk_live|sk_test|eyJ…\.|\.supabase\.co|acct_|service_role`)**.
- Gated client surface vs `d27aa449`: `setupDecision.ts` only (F6), as A states; confirmed by the 41-file list.

## 6. Dashboard and server findings — kept separate, severity unchanged
RC2 touches `app/ src/ tests/` only. Nothing in it fixes or worsens: the duplicate parked refund/payout action
(`ops.execute_action` has no unsettled-duplicate rule; the console guard is advisory), relist without `expected`, the
`order_detail` 50-action cap, D-RC-3 (buyer never sees a 150-lifecycle failed refund — still 0 reads of `refund_failed_cents`
at RC2), the Next.js advisories. No RC2 evidence changes their severity; nothing to escalate to A beyond what is already filed.

## 7. CI and checks belong to RC2
Run 38319986862: `headSha e2b9498b…`, `conclusion success`, jobs Typecheck/Lint/Unit, Migrations (fresh DB), Web build, Deno
type-check, Admin console — all success, no skipped or failed step. RC1's run 38203105234 was not reused. Gate PR #100: six required checks `pass` at head `e2b9498b` (`gh pr checks 100`); "Supabase Preview" reads `skipping` — consistent with the production branch record's empty git binding (RC1 record §4.3); a Vercel **preview** deployment of `web/` is built for the PR (`Vercel – snatchit-web`, pass) — a preview environment, not the production alias, and not a release step.

## 8. Adversarial check — one focused read-only subagent (owner-allowed), briefed to refute five load-bearing claims
One `general-purpose` agent, read-only (git show/grep/diff only, scratch under the session scratchpad, no network, no production),
briefed to **refute** five claims with concrete evidence; its structured result is preserved privately (`skeptic_result.json`).
I re-verified every refutation myself before accepting it.
| Claim | Skeptic | My verification | Outcome |
|---|---|---|---|
| P1 producers of the checkout route are exactly the two pushes + the mode-carrying returnURL + external links | **not refuted** (high): 20+ candidate navigations enumerated and ruled out; `app.json` has only `scheme: snatchit`, no associated domains / intent filters / custom linking config; CM12 pins only the object-form push | agrees with §4 | stands; **description of external links corrected** (§4) |
| P2 no path to an intent/sheet/settlement without a parsed mode; no-mode shows the unknown state | money-path clause **not refuted** (high); UI-state clause **refuted** (medium) | **confirmed by reading `:221-256` and `:429-468`**: the no-mode `throw new SettledReadError` is outside `decideCheckoutSetup`, so a failed read reaches the generic catch → `SAFE_PAYMENT_ERROR` + "Try again", `statusUnknown`/`paymentStatusUnknown` stay false, escrow note shown | **D-RC2-1** (non-blocking defect) |
| P3 the three guard pins were not loosened | W2 and payout-landing **not refuted**; E9 **refuted** (medium) with a concrete mutation | **confirmed by replaying the mutation with node** against both pin versions (new: PASS; old: FAIL) | **D-RC2-2** (test-quality finding); §3 corrected |
| P4 B-D7 changed no copy | **not refuted** (high): multiset diff of literals/JSX text/accessibility strings — only `'column'`, `'flex-start'`, an import path and a `testID` added | agrees with §3 | stands |
| P5 B-D9 closes every path to writing an unverified number | **not refuted** (high): every write/read of `profileRetryRef` traced; the `verify` step renders no phone input | agrees with §3 | stands; residual noted (§9) |
Extra findings it raised, carried into §9: Sentry noise on every mode-less open; CM12's object-form-only census; a possible resend
dead end after an F3 failure if the provider issues no new OTP for an unchanged number.

## 9. Verdict
### Blocking defects
**None found at `e2b9498b`.** Every RC2 change was read at the frozen tip; the one producer-class risk this review turned up
(the `auction_won` notification's mode-less `/checkout/<id>` link) was traced and shown not to reach the mobile checkout (§4).
Nothing in RC2 changes a schema, a money-executing path on the server, a production setting or a deployment input (§5).

Two **non-blocking defects** were found by the adversarial check and verified by me; both are fail-closed, neither moves money, and
both need only a small change — A decides whether to take them into the candidate (which re-keys the evidence) or record them:
- **D-RC2-1 — no-mode arrival + failed settled read shows the wrong state.** `CheckoutNative.tsx:231-232`: the no-mode branch
  throws `SettledReadError` outside `decideCheckoutSetup`, so the error reaches the generic catch (`:429-468`): copy "We couldn't
  start payment. Please try again." (nothing was started), control "Try again" (not "Check again"), `statusUnknown`/
  `paymentStatusUnknown` stay false so **`showEscrowNote` is true and "You pay now…" renders while the payment status is unknown
  — the owner's E2 rule** — and the Sentry stage is mislabelled `payment-intent`. Reproduction: mount `/checkout/<id>` with no
  `mode` while `readSettledPayments` returns `{error}` (airplane mode, or a mocked dep). Reach: external/truncated links without a
  mode and a read failure at the same time — rare, and "Try again" re-runs the read. Fix shape: handle `'error' in read` in the
  no-mode branch exactly as `:290-298` does (set the unknown state and return), or route it through a `decide*` helper with a catch;
  add a CM test for it (CM9 checks ordering only).
- **D-RC2-2 — E9 restatement is weaker in one region.** `tests/checkout-escrow-note-unknown.test.ts` (5b889443): the mention-free
  region ends at the first `readSettledPayments(` call, and the clear count/adjacency regex see only the exact token
  `setPaymentStatusUnknown(false);`. Reproduction: insert `setPaymentStatusUnknown(false as const);` after `CheckoutNative.tsx:231`
  — new E9 passes, old E9 fails. Shipped source is correct today. Fix shape: assert no `setPaymentStatusUnknown` mention between
  **each** `readSettledPayments(` call and its throw (my replay of that assertion catches the mutant), and count mentions, not one
  spelling.
### Passed, with limits
- Identity and composition at byte level; restricted surfaces unchanged; CI and PR checks keyed to `e2b9498b` (§1, §7).
- C4, both roots, reproduced, reconciled, blind-spot classes hand-resolved; dynamic sites carried only where files are unchanged
  and re-resolved where not (§2). Limit: existence only.
- F1–F7, D-RC-4, B-D7, B-D9, B-D10 and the three guard pins, by source and test reading at the tip (§3). Limits: RED/GREEN was
  reproduced by me only for F6; for the other fixes the RED→GREEN and mutant evidence is C's commit record plus CI green at
  `e2b9498b` — I did not rerun C's suites (no heavy local run was needed; A's stage runner and CI cover them). Many pins are
  source-text pins — precise today, brittle to refactors. B-D7's pixel identity and A3XL fit are B's binary review.
- Producer enumeration for the checkout route, client and server side (§4) — the check whose absence let B-D10 through.
- Dashboard and server findings kept separate; no RC2 evidence changes their severity (§6).
### Residual risks (not blockers)
- **Pre-webhook window** (Stripe charged, promoters not yet committed): until the webhook or confirm-payment lands, a cold 3-D Secure
  return can show "Payment already completed"/"Try again" or a not-held face (B's probe note, A's record). Pre-existing; F4/F6
  narrow it; money-safe; not closable in the client without a server status.
- **External deep links:** a mode-less one fails closed ("couldn't check… / Check again", no pointer to the listing — cosmetic copy
  gap; and D-RC2-1 when the read also fails). **A mode-carrying crafted link is treated like the 3-D Secure return** (§4): URL-supplied
  event/venue display until the listing read, and a URL `totalCents` can be echoed in the "total changed" notice. Money is server-
  decided; pre-existing; optional hardening: do not render URL-supplied event/venue before the listing read.
- **Sentry noise:** `reportCheckoutFailure('payment-status', 'checkout opened without a mode')` fires on every legitimate mode-less
  open (e.g. the truncated-return floor), inflating that failure count.
- **CM12 census** counts only the object-form push `pathname: '/checkout/[id]'`; a future template-string push, `<Link href>`,
  `<Redirect>` or `Linking.openURL` producer would evade it (none exists at `e2b9498b`, verified by grep of every `checkout/` literal).
- **B-D9 follow-on:** after an F3 failure, Resend re-sends to the already-confirmed number; if the provider issues no new OTP for an
  unchanged phone, the reset leaves the person needing a code that never arrives (gate stays raised until unmount). Provider
  behaviour not verified here; a flow/copy decision for C.
- **Cold-start 3-D Secure return** shows "—" for event/venue (the returnURL carries mode and totals only).
- **Push routing field names:** `routeFromNotificationData` reads `data.listingId`; the SQL metadata uses `listing_id`. If a push
  payload is snake-cased the tap opens the app and routes nowhere — not misleading, pre-existing, unchanged by RC2; owner of the
  check is whoever owns the `notify-*` functions.
- **CM12 shells out to `grep`** from the test's cwd — environment-dependent (needs `grep` in PATH and cwd = repo root); green on
  CI and on the Macs.
- **D-RC-3** (buyer never sees a failed refund; 0 reads of `refund_failed_cents` at RC2) — owner decision, unchanged.
- **Server-side duplicate operator action** (`ops.execute_action` has no unsettled-duplicate rule) — parked owner finding, unchanged.
- **No-mode completed face** has no "View transfer" (same as the existing `already_settled` face) — B's note.
### What still gates distribution (owner's steps; none executed here)
From A's amendment 2 and this review; none executed or started by me:
- **S5 (gate PR #100):** merge method `merge` only (gate ruleset); A verifies the merge commit's tree = `3e981375…` (the gate has not
  moved since `abef9506`). Applies no migration (RC1 record §4.2 stands: `supabase/` = gate, CI has no deploy credential).
- **G2/X11:** EAS production build from exactly that merge commit (or `e2b9498b` after tree equality), production profile pairing
  asserted, EAS metadata naming the commit. C's fresh-install Release build (HEAVY-2, EXIT 0) and B's binary verdict (PASS,
  `967c29e6`) are **A-reported in amendment 2 — not verified by me**; E's matrix re-key at `e2b9498b` is E's.
- **Owner decisions** unchanged: 152 (not in this release, App Review risk accepted), F8, B-D6, D-RC-3; acceptance of coverage.
- **S7 (gate → main), separate and later:** the RC1 record's §4 conditions stand unchanged — the plan names 121/125/126 as what S7
  would apply if auto-deploy were on; a fresh owner visual confirmation and D's `list_branches` read immediately before the merge;
  post-merge ledger still 164 with none of the three present.
- **Standing:** no agent-initiated production write, refund, payout, setting change or deployment; the five test-mode payments stay
  excluded; the historical reconciliation stays closed; 153 parked.

## 10. Process
- Raw outputs (scanner runs both roots, reconciliation lists, composition check, pre-freeze fix read, skeptic result) are
  preserved privately at `private-evidence/D-session-9651e05a/rc2_e2b9498b/`; this record carries names, paths and counts only.
- Before pushing, every blob version and commit message in the outgoing range was scanned with the same pattern set and built-in
  positive control as before; a scanner error would have been a failed check. Result: first pass on the committed record: 1 commit, 1 blob version, **0 hits**, positive control tripped as required; the amended final version was re-scanned immediately before the push and that result is the push note in `sprint-control/D-HANDOFF.md` (private) — if that note is absent, the push did not happen.

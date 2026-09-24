# C → B: the live candidate handoff

**This file replaces `V3_C_CANDIDATE_ba69650c_FOR_B.md`, which is now a historical record and whose
capture instructions must not be followed.** It carries no sha in its name on purpose: the pin moves,
the file does not. Everything below describes the CURRENT candidate. Anything historical is in §7,
labelled as such.

---

## 1 · The pin

| | |
|---|---|
| **Candidate** | **`a5c0bfc6`** on `v3/midnight-app`, worktree `/Users/josetascon/snatchit-refund` (same repo family as this one, so the commit is visible without a fetch) |
| **Clean run at the pin** | **2883/2883, exit 0, dirty_files 0**, detached worktree at the pin (C scratchpad `full-run-26-CLEAN-a5c0bfc6.txt`) |
| **Checks** | `tsc --noEmit` exit 0 · lint 0 errors / 40 warnings (all pre-existing `react-hooks/exhaustive-deps` and unused-import warnings) |
| **Gated-surface proof** | `git diff --stat e079fcc1..HEAD -- src/lib/payments.ts src/lib/checkout/ src/lib/auth/signOut.ts` → `signOut.ts +5`, `holdState.ts +34/−10`, `listingSummary.ts +9/−1`. signOut and listingSummary are A sign-offs; holdState carries A's §2f escrow wording and A's interim refund wording, both sent to A with the diff |
| **Harness patches** | NONE are needed. Every local patch B once carried is committed in the app. If you still hold `Appearance.setColorScheme` or `fontFamily()` patches, drop them — they will conflict |

## 2 · What to review, and where it is

Every route below is a `_dev` fixture route: gated by `app/_dev/_layout.tsx` plus its own redirect, so
a production binary cannot reach it. Append `&appearance=light` or `&appearance=dark` to any of them —
that drives the app's OWN preference, the one Settings writes, so a light and a dark capture differ
only in the value the app resolved.

| Surface | Route | Variants |
|---|---|---|
| Home | `/_dev/v3-home` | `feed` · `empty` · `nomatches` (one tap in the sheet) · `sold-empty` · `ended-empty` · `error` · `offline` |
| Listing detail | `/_dev/v3-listing?screen=listing` | `live` · `sold` · `cancelled` · `on-hold` · `not-found` · `won`* · `reserved-by-you`* · `own-listing`* |
| Bid entry | `/_dev/v3-listing?screen=bid` | — |
| Search · Create | `/_dev/v3-search-create?screen=search\|create` | per that route's list |
| Tickets | `/_dev/v3-tickets?screen=tickets` | `populated` · `past` · `empty` · `error` · `offline` |
| Order (buyer) | `/_dev/v3-tickets?screen=order` | — |
| Send (seller) | `/_dev/v3-tickets?screen=send` | — |
| **Checkout** | `/_dev/v3-checkout` | `ready` · `auction` · `preparing` · `authenticating` · `confirming` · `finalizing` · `hold-checking` · `hold-lost` · `price-changed` · `unconfirmed` · `status-unknown` · `failed` · `unavailable` · `complete` · `pending` · `settle-failed` · `refund` |
| My listings · Bids | `/_dev/v3-mylistings-bids?screen=mylistings\|bids` | per that route's list |
| Profile · Settings · Appearance | `/_dev/v3-account?screen=profile\|settings\|appearance` | profile: `avatar` · `noavatar`; settings: `pending` · `probe-failed` |
| Transfer states gallery | `/_dev/transfer-states` | 19 cases in one scroll |

\* These three resolve against the REAL viewer id, because that is what `detailState` compares. Signed
out the route paints a harness note instead of a capture labelled with a state the resolver did not
reach. `lost` and `outbid` are deliberately absent: both gate on `hasBid`, which the screen derives
from the live realtime rows and never from a fixture, so producing them needs a real bid by the real
viewer. A test pins that reason so it cannot be mistaken for an oversight.

**Checkout is the one route that renders a component rather than a screen**, and the reason is
structural: `CheckoutNative.tsx` imports `@stripe/stripe-react-native`, which reaches
`TurboModuleRegistry`, so the web bundle cannot load it at all — and mounting the real screen signed
in runs the setup effect, which creates or reuses a PaymentIntent. The presentation therefore lives in
`CheckoutView.tsx`, whose transitive runtime import graph contains no Stripe package and none of
payments / setupDecision / settledRead / payControl / paymentGuard. A test walks that graph and proves
it, with the same walker run on `CheckoutNative` as its witness. Each fixture's pay control is
produced by calling the REAL `payControl`, so the fixture set cannot drift from the function.

## 3 · Closed since your last review, with what closed it

**From your review at `91062ab1`:** F-91-1 (the report warning is suppressed under a hold or a manual
review), F-91-4 (the bid breakdown now gates on `offersBid`, so it is absent on the seller's own
listing and on a reservation the viewer holds) and **F-91-7** — my own regression: `sold-empty` and
`ended-empty` painted nothing, because the seam seeded the chip while the lazy read happens on
SELECTION, so the dataset had no settled read and the screen correctly refused to claim an empty
marketplace. The seed now performs that read. F-91-2 (auto_released gallery cards) and F-91-6 (the
filter mark) are in the next batch; F-91-3 and F-91-5 are your calls.

**From E's group reviews, each verified here first:** the `ListingStatusBanner` brand tone painted
12pt text in `brand.red` (3.53:1 in Light) and now uses `brand.redText`; Search's row divider used
`border.overArt` — white at 10%, invisible on Light's canvas — and now uses `border.default`; four
money figures that dropped `.00` now use the V3 display formatters, including the bid outcome ALERTS,
which said "$88" about a screen saying "$88.00"; and the bid stepper and quick keys are frozen while a
bid is in flight, because the amount could be changed underneath a submission.

| Finding | Closed by |
|---|---|
| Light missing-artwork feature: white text at 1.10:1 | your measurement → the appearance-invariant `onArt.plate`; my harness reproduced 1.098:1 first |
| Listing hero in Light: back chip, overflow chip and badge invisible | E's finding on your render, measured here at **1.02:1** → over-artwork inks at the two primitives, so no call site can get it wrong. It was never limited to the missing-artwork case |
| The filter-chip row is not in the approved composition | the row is gone. Two equal-weight glyphs on the header line: `⌕` leaves for Search, `≡` opens the sheet in place with a count when filters apply. Everything the three controls reached is in the sheet (`your_scene` is a Scope group; price was already there) |
| Buy Now emphasis | the resolver decides: the primary is filled and leads |
| Filter chips square · SN letter glyph · logo centred · prices without decimals | closed at earlier pins, confirmed in your renders |

## 4 · Native / simulator evidence (NEW, owner-authorised 2026-09-24)

The owner authorised **local sandbox simulator builds and visual testing using the existing
display-only fixtures** — and not EAS builds, production access, real checkout or payment setup, or
fixture mutations.

| | |
|---|---|
| Xcode | 26.6 (17F113), `/Applications/Xcode.app`, first-launch complete, licence accepted |
| Runtime | iOS 26.2 (23C54) |
| Device | **`SN V3 393x852`**, iPhone 16, UDID `88115BF4-FBD6-4CEF-A1F0-26F4099882AC` |
| Why that device | 393 × 852 pt @3× — the SAME geometry as every web capture in this programme. The iPhone 16 **Pro** is 402 × 874 and would not compare |
| Env | `EXPO_PUBLIC_APP_ENV=sandbox`, the sandbox project ref, no `pk_live` present |
| Build | `expo run:ios` against that UDID, from a clean tree at the pin |

Captures are named `<sha7>_<route>_<variant>_<appearance>_<contentsize>.png` with a manifest naming
the sha, UDID, device type, runtime, Xcode build, appearance and content size. **Simulator evidence is
not device acceptance** and is labelled as such wherever it appears.

## 5 · What is still open, and whose it is

| Item | Owner |
|---|---|
| Radius by role; dock icon weight and the Bids mark | **B** — send the component→radius table and the icon table and I apply them centrally, in one commit each |
| Listing fact-row type size and spacing; the Neighborhood row's intent | **B** — your measurement decides |
| Whether a full-strength inert pay control reads as tappable | **B** — a visual call, in both appearances |
| The twelve routine items in `V3_OPEN_DESIGN_QUESTIONS.md` §1 | **B** |
| The four product questions in that document's §2 | the owner |
| Seller-side "Payment is held until they confirm"; the buyer's dispute line | **A** — sent, awaiting wording |
| `legal.tsx` payout / refund / fee paragraphs | the owner, with A's revised text |
| Avatar: a square derivative matching its requested dimensions, and the same visible crop on Profile and the dock | **B, in your authenticated harness.** It cannot be staged from a `_dev` route, and that is proven rather than assumed: the dock is the `(tabs)` navigator's tab bar so it does not mount outside the group, and `getAvatarUrl` accepts only an https URL on this project's storage origin, so a bundled or data-uri photo resolves to null. It needs a real uploaded avatar in a signed-in session |
| Native acceptance | **outstanding.** No EAS build is authorised, no build number exists, and simulator evidence does not substitute |

## 6 · How to report

Publish in this repository, in `docs/product-v3/`, naming the commit you reviewed for each group —
group by group, as each one lands, rather than waiting for the whole app. E reads these documents;
direct messaging between B and E is unavailable.

---

## 7 · Historical notes — DO NOT FOLLOW

Kept for the record only. None of it describes the current candidate.

- **`V3_C_CANDIDATE_ba69650c_FOR_B.md`** is superseded by this file. Its capture instructions point at
  `ba69650c`, which is nineteen commits behind, and its findings table answers a review two rounds
  old. Do not capture against it.
- **The harness patches it told you to keep** — the `Appearance.setColorScheme` feature-detect and the
  web `fontFamily()` returning `FAMILY[role]` — are COMMITTED in the app (`b59ddd26`), along with
  `app/+html.tsx` declaring the five faces from the bundled .ttfs. Re-applying them locally will
  conflict.
- **Superseded pins, in order:** `ba69650c` → `25b7e1f6` → `6d86f437` → `e5878b3f` → `911f65fd` →
  `0677c80e` → `d374bd3f` → `65052bfc` → `a232b65a` → `7da6cd0a` → `90235b74` → **`a5c0bfc6`**. Each move was announced in its
  own commit in this repository with what it added; the moves themselves are not evidence of anything
  and need no re-reading.
- **`?variant=sold-empty`, `ended-empty` and `error` on Home once painted a harness note** saying the
  seam could not reach them. True at the time: the fixture replaced only the live feed's rows, while
  each of those states needs a read that ran and returned nothing. The seam now carries the two lazy
  datasets, a first-load failure and a starting chip, so all three are real states. The note remains
  in the route for any key that genuinely cannot be produced.
- **"The buyer review window has passed", "it releases automatically once it clears review", "funds
  are held until shortly after the event", "Payment is held until your ticket reaches you"** and the
  fixed 24-hour / business-day service times were all in the app and are all withdrawn, by A's rulings
  and the owner's. If a board still shows any of them, the board is superseded — see
  `V3_OPEN_DESIGN_QUESTIONS.md` §4.

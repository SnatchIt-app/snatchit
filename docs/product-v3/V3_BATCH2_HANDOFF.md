# V3 consumer batch 2 — successor handoff

Durable record, in the repository. Branch `v3/consumer-batch2`, built on `d5217530` (the
reviewed successor). This file is committed WITH the final commit, so the exact sha is the head
of that branch at the commit carrying this file: run `git log -1 --format=%H v3/consumer-batch2`.

## What this batch is

Two of E's reported behaviour bugs, the harness surfaces needed to see them, and the two
implementation requirements the owner settled after B's native review of `d5217530`. It is a
completion of the existing artwork and large-text requirements, not a new design decision.

## Changed product screens

| Screen | Change | Why |
|---|---|---|
| `app/listing/edit/[id].tsx` | the four read refusals render a terminal state with a working exit; the read is seedable | E: the spinner never stopped. The cause was the render guard reading "no listing" as "still loading", so the not-found branch spun too |
| `src/screens/CreateListingScreen.tsx` | a signed-out publish says 'Sign in required' | E: it said nothing at all |
| `app/transfer/send/[id].tsx`, `app/transfer/receive/[id].tsx` | "Transfer not found" gained an exit | E asked for a retry; reproduced first, and a retry is already on the two paths where it can help |
| `src/components/listing/ListingHero.tsx` | navigation moved into its own area above the poster; the inset moved with it | B measured the banner over the poster's top 79 pt and the chips on printed lines |
| `src/components/discovery/HomeFeature.tsx` | the identity block stacks above 1.3× text; no line is capped in that form; the amount's scale is capped | B: "current bid, al…" at a3xl, "Ends…" at 3xl |
| `src/components/discovery/FeedRow.tsx` | text and price share a column at large text; the amount's scale is capped | E, from a C-operated capture: "$132.0…" and "all-i…" |
| `src/components/listing/TransactionPanel.tsx` | the same stacking | found in a C-operated capture: the breakdown VALUE rendered "$95.0" |
| `src/screens/ListingDetailScreen.tsx` | fact rows take the screen's own `factRowBlock` form at large text; a seeded read failure | found in a C-operated capture: Delivery as "…le t…" |
| `app/profile/[id].tsx` | the four reads are seedable; Block short-circuits under a fixture | it was mounted by no harness at all |

One threshold, `IDENTITY_STACK_SCALE = 1.3` in `src/lib/design/featureMetrics.ts`, is shared by
all three stacking surfaces. 1.3 is at or below the largest STANDARD size, which is where the
first cut appeared. It is a layout change, not a cap on how far text may grow: capping would
answer a request for larger text by refusing it.

## Fixture routes

| Route | Controls |
|---|---|
| `_dev/v3-edit-listing` | `?variant=` default · `not-found` · `not-owner` · `has-bids` · `inactive` · `read-failed` |
| `_dev/v3-profile` | `?variant=` default · `no-listings` · `blocked` · `stats-unavailable` · `not-found`, `?art=` |
| `_dev/v3-listing` | gained `?variant=error` and `?variant=offline` |
| `_dev/v3-mylistings-bids`, `_dev/v3-tickets`, `_dev/v3-search-create`, `_dev/v3-checkout` | gained `?art=` |

`?art=` on a list harness gives EVERY row the selected poster; `all` cycles the shapes. That rule
is deliberate: assuming the first row is the one on screen is what produced the Home defect, and
these screens order or group their rows.

**No fixture stands in for authentication.** The viewer always comes from the screen's own
`useAuth()`. That is why `v3-edit-listing` offers four refusals and not five — the signed-out one
would need a prop standing in for a session — and it is pinned for every harness file.

## Completed checks

- `npx tsc --noEmit` — exit 0.
- `npm run lint` — 0 errors, 43 warnings, none in the changed files.
- `npx vitest run` — **174 files / 2974 tests, exit 0, 22.7s.**

  Three earlier runs of the same tree are VOID, and the reason is worth recording because it will
  happen to the next person who captures and tests in one session: they reported 1, then 13, then
  13 failures, in three DIFFERENT sets, across suites with 5-second timeouts (payout attempts,
  edge coupling, cron auth, the avatar busy states). The cause was the iOS Simulator running
  alongside — the same suite takes 22s with the device shut down and over 600s with it booted, so
  the timeouts were firing on CPU starvation. A differing failure set across runs of one tree is
  the signal; the fix was to shut the device down, not to investigate thirteen suites.

  **Captures and the full suite cannot be trusted at the same time on this machine.**
- Mutation controls, each predicted before running and matching exactly: the refusal branch
  removed from `editPhase` kills EL2a-EL2e; the signed-out block made silent kills CP1 and CP4; an
  inert `listArt` kills HA9 and HA11; one unwired route kills HA13. All digest-verified restores.

## C-operated, B-reviewed captures

Two directories, because the code moved while the cases were being run:

- `native/94ac8b4f/` — case 3, the four Listing captures. Those surfaces did not change
  afterwards (`git diff --name-only 94ac8b4f..7c9b270b` lists only FeedRow, HomeFeature, their
  test and this file), so they carry.
- `native/7c9b270b/` — cases 1 and 2, the four Home captures, retaken after the feed-row fixes.

Each directory's `capture-log.txt` records, per file, the content size and appearance read back
FROM THE DEVICE at capture time rather than asserted by me. Every file is named
`…-Coperated.png`. **None of them is reviewed evidence until B reviews it.**

Cases 1, 2 and 3 of B's five are captured. Case 4 and case 5 are blocked; see below.

Operating notes for whoever drives the device next, both learned the hard way here:

- **A content-size change needs an app relaunch.** Setting it on a running app leaves the rendering
  at the previous size. Two captures were discarded for being mislabelled before this was found.
- **A scroll needs a dwell before the drag.** A fast synthetic drag is ignored by the scroll
  recogniser, which reads as "the screen does not scroll". A tap in the same position DID register,
  which is what separated a bad gesture from a real finding.

## Unresolved

- **Case 4 — authenticated consumer Home. Blocked.** The device has no session; the app opens on
  Sign in. The missing capability is specific: an authenticated session on the simulator,
  established by someone who may handle the test-buyer credential. The app's sign-in is a phone
  code or an email password, and both mean materialising a credential for a hosted account, which
  I do not do and which B also declined. No harness substitute was used, and the consumer
  next-section figure stays unestablished.
- **Case 5 — accessibility exposure. Partly established.** What the price caption EXPOSES is
  verified: the feature publishes one label carrying the event, both meta lines, the price and the
  caption including "all-in" (`HomeFeature.tsx`, pinned by LT5). What is NOT established is
  VoiceOver speaking it on the device: `simctl` cannot toggle VoiceOver and cannot read the
  accessibility tree, so the missing capability is an accessibility inspector attached to the
  simulator. Recorded separately from the visible-text result, which is the owner's rule: a
  complete spoken string does not excuse clipped visible text.
- **A judgement call to reverse if the owner disagrees:** the AMOUNT on the feature and the feed
  row now takes `MAX_DISPLAY_FONT_SCALE`, the app's existing cap for display type. Stacking alone
  stopped the amount clipping and then let it wrap mid-number — "$132.0" then "0" — which misreads
  about as easily as a lost digit. The cap bounds the numeral only; the caption, the meta lines and
  everything else keep scaling all the way, and the spoken label carries the full figure. It is one
  prop per surface to remove.
- **Feed-row titles and date lines still truncate at 3xl and a3xl** (`case1-home-3xl-light-feedrow`).
  Left alone deliberately: a feed row is a fixed-height row whose two-line title cap may be the
  approved design, and B's case 1 exists so B can compare it against that design. It is a finding
  for B and the owner, not a fix I should make unilaterally.
- **R-4 is affected.** The identity still sits beneath the poster, but the navigation above it is
  new, so the ruling wants confirming at this successor.
- Queued and untouched (E's coverage list): the public profile's own "Profile unavailable" state
  has no action, and several screens still have no harness variants for their failure states.

## Evidence limits

Everything above is either a render-tree result or a C-operated capture. None of it is B's
independent review, none of it is a release artifact, and the harness routes are gated to sandbox
and dev builds so none of them is reachable in production.

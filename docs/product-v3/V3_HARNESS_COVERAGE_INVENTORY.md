# V3 harness coverage — what a reviewer cannot currently see

Read against `v3/consumer-batch2`, built on the successor `d5217530`. Every row below was
checked in the code at that commit; nothing here is carried over from an earlier list.

Two defects already closed on this branch are the reason for the inventory's shape: a harness
that hard-codes `cover_image_path: null` cannot show a poster treatment (the Listing harness,
E's finding), and a refusal the screen cannot render cannot be reviewed either (Edit listing,
E's finding). Both patterns repeat on the surfaces below.

## 1. Artwork selectors

`?art=` now exists on six routes. What is left uncovered is one screen that no dev route mounts
at all.

| Surface | Slot | Component | Harness route | Artwork |
|---|---|---|---|---|
| Home feature + feed rows | `HOME_FEATURE_V3`, `FEED_ROW_ART`, `DISCOVERY_CARD` | HomeFeature, FeedRow, DiscoveryCard | `v3-home` | `?art=`, feature-aware |
| Listing hero | `LISTING_HERO_V3` | ListingHero | `v3-listing` | `?art=` |
| My listings rows | `SEARCH_RESULT` | SellerListingCard | `v3-mylistings-bids?screen=mylistings` | `?art=`, every row |
| Bids / purchases rows | `CHECKOUT_THUMBNAIL` | BidCard | `v3-mylistings-bids?screen=bids` | `?art=`, every row |
| Tickets rows + ticket art | `SEARCH_RESULT`, `TICKET_ART` | TicketEventGroup | `v3-tickets?screen=tickets` | `?art=`, every group |
| Search results | `SEARCH_RESULT` | SellerListingCard | `v3-search-create?screen=search` | `?art=`, every row |
| Checkout / Order identity | `CHECKOUT_THUMBNAIL` | OrderIdentity | `v3-checkout` | `?art=`, one poster |
| Send / Receive | `FEED_ROW_ART` | `app/transfer/send/[id].tsx:393`, `app/transfer/receive/[id].tsx:481` | `v3-tickets?screen=send`, `?screen=order` | `?art=`, one poster |
| Public profile | `CHECKOUT_THUMBNAIL` | `app/profile/[id].tsx:64` | **none** | the screen is not mounted by any `app/_dev` route |

**Twice-corrected row.** The Send/Receive row first named `transfer-states` as the harness, then
said there was none. Both were wrong. `transfer-states` is a component gallery — it renders
`TransferStateBlocks` from synthetic props (`app/_dev/transfer-states.tsx:30-36`) and imports
neither screen — but `v3-tickets` does mount both, at `?screen=send` and `?screen=order`
(`v3-tickets.tsx:32-33`), each from one fixed fixture whose listing carried
`cover_image_path: null` (`v3-tickets.tsx:165`, inherited by `SEND_FIXTURE` through the spread).
Recorded with the mistakes in it because the lesson is the one that produced the Home defect:
a surface is wherever it is actually mounted, not wherever the name suggests.

**A bundled poster is contract-independent, so none of this needed a contract ruling.**
`resolveImage` takes the `dev-bundled:` branch "before anything storage-shaped happens"
(`src/lib/media/url.ts:363-379`), so the marker renders identically whatever `bucket` or
`contract` the surface declares. That matters here because Tickets is on a different contract
from listings — `{ bucket: 'event-media', contract: 'v2' }` at
`src/components/tickets/TicketEventGroup.tsx:82` against listings' `auction-media` / `legacy`.
Supplying a bundled poster to a ticket asserts nothing about where real ticket artwork comes
from; it only puts pixels in a 4:5 frame so the treatment can be judged.

**For A, a separate question none of this answers:** whether a ticket's `artwork_ref` is expected
to carry the listing's cover, its own event artwork, or nothing. That is a contract question, not
a presentation one, and no harness change should be read as settling it.

**One rule for the list harnesses: every row takes the selected poster.** The Home selector put
the poster on `rows[0]` and assumed that row was the feature; the screen buckets by event date, so
it was the feature only by luck. My listings, Bids, Tickets and Search each order or group their
rows too, so a per-screen "first row" rule would have been four fresh chances at the same mistake.
`?art=all` gives each of the first rows a different shape (`ART_SHAPES` in
`src/lib/media/harnessArt.ts`), so one capture shows the fit across ratios and nothing anywhere
has to know the render order. An unselected or unknown key leaves every row exactly as it was, so
the plate stays the default and existing captures do not move.

## 1b. Letterbox position — answered for B, 2026-10-06

B measured letterboxed art sitting above centre on a consistent ~40/60 split (square 39.0%,
16:9 40.1%, 9:16 exactly centred) and asked whether it is deliberate. It is, and it is the focal
point rather than a layout accident:

- `DEFAULT_FOCAL = { x: 0.5, y: 0.4 }` — `src/lib/media/url.ts:76`, with the reason on the type at
  `:72` ("Defaults above centre: flyers put the headline act high").
- It reaches the pixels at `src/components/media/EventMedia.tsx:265-273`, which passes
  `contentPosition={{ left: focal.x*100%, top: focal.y*100% }}` for **both** `contain` and
  `cover` — it is not a cover-only crop rule. Under `contain`, `top: 40%` divides the vertical
  slack 40/60, which is B's two measurements within the integer rounding at `:271-272`.
- 9:16 reads as centred because it is taller than 4:5: `contain` fits it by height, so there is no
  vertical slack to divide. The three numbers are one rule, not two behaviours.
- A stored focal point overrides the default (`asset.focal ?? DEFAULT_FOCAL`, `url.ts:381`, `:452`)
  and `v2` uploads carry one. Every case B reviewed used the default, because the bundled QA
  posters carry none — so 40% is what the default does, not a ceiling on stored art. The web path
  uses the same value through `focalToObjectPosition` (`:457`), so a web and a native capture agree.

**Write it down as:** letterboxed art is positioned by the focal point, default y=0.40, so 40% of
the vertical slack sits above the art; a source taller than 4:5 has no vertical slack and reads as
centred.

## 2. Missing fixture states

| Screen | State the product has | Reviewable? |
|---|---|---|
| Listing detail | read failure (`StateView kind="error"`, `ListingDetailScreen.tsx:1100`) and offline (`ScreenState state="offline"`) | **No.** `ListingDetailFixture` (`ListingDetailScreen.tsx:102`) seeds `listing`, `seller`, `bids`, `viewerId`, `reserving` — there is no way to seed a failed read. `variant=not-found` exists; `error` and `offline` do not. |
| Edit listing | loading, the four refusals, the form, "Saving…", the discard prompt | **No.** There is no `app/_dev` route for `app/listing/edit/[id].tsx` at all. The refusal state added in `6c562dcf` has behavioural tests but cannot be looked at. |
| Create listing | the risk banner's four reasons | **Yes** — `CreateFixture.riskBanner` seeds all four. |
| Create listing | signed-out publish | **N/A as a fixture** — the refusal added in `8b437942` is an alert, which is not a rendered state. Behavioural coverage only, by design. |
| Checkout | `state=` covers complete, pending, refund, settle-failed (`v3-checkout.tsx`) | Partial. The read-fail-closed paths that `tests/checkout-*-read-fail-closed.test.ts` defend have no harness variant. |
| Place a bid | `variant=bid`, `nobids` (`v3-screens.tsx:58`) | Partial. No failure or offline variant. |
| Send | "Transfer not found" has no retry (`app/transfer/send/[id].tsx:349`) | E's finding, **not yet reproduced** — carried here, not confirmed. |

## 3. Not in scope without a ruling

- Adding a confirmation dialog anywhere, or changing who may sell, bid, edit or transfer.
  Both fixes on this branch deliberately changed neither; the owner ruled that E's findings do
  not themselves establish intended behaviour.
- Mounting the public profile screen in `app/_dev` is new review surface rather than a
  coverage gap in an existing route; it is listed above so the gap is recorded, not claimed.

## 4. Evidence limits

Everything above is a source reading at `v3/consumer-batch2`. No native capture, no device run,
and nothing here has been reviewed by B. The two fixes on this branch carry their own
verification in their commit messages, including which mutant kills which tests.

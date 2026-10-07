# V3 harness coverage — what a reviewer cannot currently see

Read against `v3/consumer-batch2`, built on the successor `d5217530`. Every row below was
checked in the code at that commit; nothing here is carried over from an earlier list.

Two defects already closed on this branch are the reason for the inventory's shape: a harness
that hard-codes `cover_image_path: null` cannot show a poster treatment (the Listing harness,
E's finding), and a refusal the screen cannot render cannot be reviewed either (Edit listing,
E's finding). Both patterns repeat on the surfaces below.

## 1. Artwork selectors

`?art=` exists on exactly two routes — `app/_dev/v3-home.tsx:243` and
`app/_dev/v3-listing.tsx:290`. Every other event-image surface renders the missing-artwork
plate and nothing else.

| Surface | Slot | Component | Harness route | Artwork today |
|---|---|---|---|---|
| Home feature + feed rows | `HOME_FEATURE_V3`, `FEED_ROW_ART`, `DISCOVERY_CARD` | HomeFeature, FeedRow, DiscoveryCard | `v3-home` | **`?art=` (10 keys)** |
| Listing hero | `LISTING_HERO_V3` | ListingHero | `v3-listing` | **`?art=` (10 keys)** |
| My listings rows | `SEARCH_RESULT` | SellerListingCard | `v3-mylistings-bids` | plate only — `cover_image_path: null` at `v3-mylistings-bids.tsx:108` |
| Bids / purchases rows | `CHECKOUT_THUMBNAIL` | BidCard | `v3-mylistings-bids` | plate only — same fixture |
| Tickets rows + ticket art | `SEARCH_RESULT`, `TICKET_ART` | TicketEventGroup | `v3-tickets` | plate only — `artwork_ref: null` at `v3-tickets.tsx:44` and `src/lib/tickets/fixtures.ts` |
| Search results | `SEARCH_RESULT` | SellerListingCard | `v3-search-create` | plate only — `cover_image_path: null` at `v3-search-create.tsx:73`, deliberately for that fixture (CFT-106), but there is no way to select artwork either |
| Checkout / Order identity | `CHECKOUT_THUMBNAIL` | OrderIdentity | `v3-checkout` | plate only — `cover: null` at `v3-checkout.tsx:46` |
| Send / Receive | `FEED_ROW_ART` | `app/transfer/send/[id].tsx:393`, `app/transfer/receive/[id].tsx:281` | **none** | **Corrected after first writing this file.** `transfer-states` is not a harness for these screens: it renders `TransferStateBlocks` from synthetic props (`app/_dev/transfer-states.tsx:30-36`) and never imports the Send or Receive screen. Both posters sit in the screens, outside those blocks, so neither is in any harness. |
| Public profile | `CHECKOUT_THUMBNAIL` | `app/profile/[id].tsx:64` | **none** | the screen is not mounted by any `app/_dev` route |

**A bundled poster is contract-independent, so none of this needs a contract ruling.**
`resolveImage` takes the `dev-bundled:` branch "before anything storage-shaped happens"
(`src/lib/media/url.ts:363-379`), so the marker renders identically whatever `bucket` or
`contract` the surface declares. That matters here because Tickets is on a different contract
from listings — `{ bucket: 'event-media', contract: 'v2' }` at
`src/components/tickets/TicketEventGroup.tsx:82` against listings' `auction-media` / `legacy`.
Supplying a bundled poster to a ticket asserts nothing about where real ticket artwork comes
from; it only puts pixels in a 4:5 frame so the treatment can be judged.

**For A, a separate question this inventory does not answer:** whether a ticket's
`artwork_ref` is expected to carry the listing's cover, its own event artwork, or nothing.
That is a contract question, not a presentation one, and no harness change should be read as
settling it.

**One rule for list harnesses, derived from the defect it avoids.** The Home selector put the
poster on `rows[0]` and assumed that row was the feature; the screen buckets by event date, so
it was the feature only by luck. My listings, Bids, Tickets and Search each order or group
their rows too, so repeating "first row" per screen would repeat the same mistake four times.
The list harnesses should therefore give **every** row the selected poster, with `art=all`
giving each of the first rows a different shape — no ordering assumption anywhere, and several
shapes visible in one capture.

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

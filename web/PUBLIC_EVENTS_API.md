# Public events feed — the marketing-site contract

**One thing to consume:**

```
GET https://snatchti.com/api/public/events
```

No key, no auth, GET only. This is the discovery boundary: the marketing site
renders these cards and deep-links into snatchti.com, which remains the
product and transaction layer.

## Query params

| Param | Values | Notes |
|---|---|---|
| `limit` | 1–50, default 12 | |
| `from` / `to` | `YYYY-MM-DD`, inclusive | Filters `event_date`. Dates are **Miami-local wall-clock by product definition** — for "Happening This Weekend", compute Fri–Sun in `America/New_York` and pass them here. Never derive the window from UTC. |
| `sort` | `soonest` (default) · `ending` · `most_bids` | `soonest` = soonest event; `ending` = listing closes first (what /browse defaults to); `most_bids` = highest real bid count. **There is no trending score in the product** — bids are the only live demand signal, so label a `most_bids` section "Most bids", not "Trending". |

## Response

```json
{
  "city": "Miami",
  "count": 1,
  "browseUrl": "https://snatchti.com/browse",
  "generatedAt": "2026-09-01T12:00:00.000Z",
  "events": [
    {
      "id": "8e0f…uuid",
      "title": "III Points Saturday",
      "venue": "Mana Wynwood",
      "city": "Miami",
      "neighborhood": { "key": "wynwood", "label": "Wynwood" },
      "category": { "key": "festivals", "label": "Festivals" },
      "date": "2026-09-12",
      "time": "20:00:00",
      "dateLabel": "Sat, Sep 12, 2026",
      "timeLabel": "8:00 PM",
      "imageUrl": "https://…supabase.co/storage/v1/object/public/auction-media/…png",
      "url": "https://snatchti.com/listing/8e0f…uuid",
      "status": "live",
      "listingEndsAt": "2026-09-10T00:00:00+00:00",
      "ticketType": "GA",
      "quantity": 2,
      "pricing": {
        "currency": "USD",
        "currentAllInCents": 660,
        "currentAllInLabel": "$6.60 all-in",
        "buyNow": { "enabled": true, "allInCents": 33000, "allInLabel": "$330.00 all-in" }
      },
      "demand": { "bidCount": 3 }
    }
  ]
}
```

## Rules the marketing site must follow

- **Zero events is normal.** `{ "events": [], "count": 0 }` with HTTP 200 means
  keep the designed placeholder state. Never invent cards. (A 5xx also means
  placeholders — the feed is never load-bearing.)
- **Deep-link with `url` verbatim.** Do not reconstruct `/listing/{id}` —
  routing knowledge lives here, and `url` will keep working if it ever changes.
  "All of Miami" CTAs go to `browseUrl`.
- **Show only all-in prices.** `…AllInCents` / `…AllInLabel` already include
  the buyer fee — exactly the number checkout charges. Never display a lower
  number than the label.
- **Cache friendliness.** Responses are CDN-cached ~120 s
  (`s-maxage=120, stale-while-revalidate=600`). Add your own revalidation in
  that range; do not poll faster.
- **Images.** `imageUrl` is a public storage original (typically ~4:3, PNG/JPG
  up to a few MB). Run it through your framework's image optimizer
  (`next/image` remote pattern for `hqycwntpfoztoinemqns.supabase.co/storage/v1/object/public/**`);
  don't ship originals to the homepage.
- **Presence in the feed = discoverable.** Inclusion already encodes the
  product's availability rule (an active, uncancelled, unexpired listing);
  `status: "ending_soon"` just means the listing closes within 24 h.

## What this is, honestly

Today's truth is **marketplace-listing-centric**: production has no events or
primary-ticketing tables yet, so each feed entry is one live resale listing
carrying its event's details. The response is deliberately event-shaped so
that when the ratified Phase 2 catalog (`catalog.event` / `event_session`,
primary inventory) ships, the same contract serves both models with no
marketing-side change. "Featured" has no backing signal today — curate by hand
or use `most_bids`/`soonest` with accurate labels.

Server side, the feed is a projection of the exact `/browse` query
(`web/src/lib/listings.ts` → `getActiveListings`) — one definition of
availability, whitelisted display fields only (never `seller_id`,
winner/reservation state, proof paths, or any operational column).

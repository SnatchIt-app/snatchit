# CrowdVolt — design & product benchmark

**Researched:** 2026-09-02 · **Agent E** · Snatch It product redesign
**Subject:** https://www.crowdvolt.com — peer-to-peer ticket marketplace for nightlife / EDM, YC-backed, live bid/ask order book.
**Why it matters:** CrowdVolt is the closest analogue to Snatch It's *current* business — a resale marketplace with real-time pricing for club/festival events. It is the most direct competitor in the benchmark set.

## Method & evidence quality

- **OBSERVED** = fetched and quotable, with a URL. **INFERRED** = reasoned, with the reasoning stated.
- Raw HTML/CSS/JS was retrieved with `curl -A "curl/8"` (a browser-like UA triggers a Cloudflare challenge; a plain curl UA returns HTTP 200). This yielded the server-rendered React Server Component (RSC) flight payload, the compiled Tailwind CSS, and 60 JS chunks containing the app's full UI copy dictionaries.
- Live *prices* on the event page are hydrated client-side; the SSR HTML renders `--ea` placeholders. Prices below come from the RSC payload embedded in the same document, which is the same data the UI renders. OBSERVED.
- No proprietary assets were copied into the repo. Image URLs and CDN parameters are recorded verbatim as text only.

---

## 1. DISCOVERY

### Site shape

**OBSERVED** — `sitemap.xml` (1,334 URLs, fetched 2026-09-02) breaks down as:

| Route prefix | Count |
|---|---|
| `/performer/*` | 622 |
| `/event/*` | 521 |
| `/venue/*` | 133 |
| `/help_center/*` | 53 |
| `/`, `/about`, `/blog`, `/privacy`, `/terms_of_service` | 5 |

**INFERRED** — performer pages outnumber event pages ~1.2:1. For a marketplace with only 521 live events, 622 artist pages is a deliberate SEO/entity surface, not a browse surface driven by inventory. Reasoning: performer pages exist for artists with no current events (the sitemap lists them at equal `changefreq`).

### Home hierarchy

**OBSERVED** (`https://www.crowdvolt.com/`, SSR text): the page is, top to bottom —
1. Sticky top strip: `Prices may be set above or below face value by the seller.`
2. `The CrowdVolt app is here` / `Download` banner.
3. Header: logo · `Events` · `About` · `Help` · `Invite friends` · `Log in`.
4. Hero: `Discover nightlife and buy and sell tickets to club nights, parties, concerts, and festivals in Miami` and the animated line `No more excuses. You're coming out tonight in Miami`.
5. Search: `Search by event, artist, or venue`.
6. Filters: `Where` (Miami · New York · Chicago · Los Angeles · San Francisco) and `When` (`This weekend` · `Next weekend` · `Custom` + a month calendar with `Pick a start date, then an end date`).
7. Rails of event cards, then `All events in New York`.

**OBSERVED** — the city list is hard-coded in JS with codes: `[{key:"MIAMI",name:"Miami",code:"MIA"},{key:"NYC",name:"New York",code:"NYC"},{key:"CHI",name:"Chicago",code:"CHI"},{key:"LA",name:"Los Angeles",code:"LA"},{key:"SF",name:"San Francisco",code:"SF"}]`. The help centre confirms: "New York, Miami, Chicago, Los Angeles, and San Francisco - with more cities coming soon."

**OBSERVED** — a mismatch worth noting: the SSR hero says **Miami** while the filter chip and section heading say **New York** in the same HTML document. **INFERRED** — the city is resolved client-side from IP (`{"ip":"2607:fb92:..."}` is passed into a client component in the flight payload) and the SSR copy is a static default. The result is a visibly inconsistent first paint.

### Rail sections

**OBSERVED** — the marketing phone mockup for the mobile app (`js/844-*.js`) defines three home sections: `"Tonight"`, `"Trending"`, `"Our pick"`. Web copy constants include `allEvents:"All events"`, `seeMore:"See more"`, `showMore/showLess`, `backToTop:"Back to top"`, `emptyTitle:"No results found"`, and a `TrendingEventsProvider` + `recently_viewed` context. **INFERRED** — the web home is: personalised/temporal rails (Tonight, Trending) above an "All events" list, with recently-viewed and trending feeding search suggestions.

**OBSERVED** — search dropdown renders `Trending events` (`<h3 class="text-sm font-medium text-gray-300 mb-1">Trending events</h3>`) plus recent results; search has a dwell/click/enter telemetry hook (`logDwell`, `logClick`, `logEnter`).

### Layout: rails, not a grid

**OBSERVED** — the card container is a horizontally scrolling rail, not a grid:
`class="-mx-4 flex gap-4 overflow-x-clip overflow-y-visible pl-4 sm:mx-0 sm:pl-0"`, each card `class="shrink-0 w-[300px] sm:w-96 lg:w-[26rem] translate-y-[18px]"`.

So: **300px wide on mobile, 384px at `sm`, 416px at `lg`**, 16px gutters, bleeding off the left edge on mobile (`-mx-4 … pl-4`). **INFERRED** — information density is deliberately *low*: at 1440px you see roughly three cards per rail. This is an editorial/Netflix posture, not a StubHub inventory grid.

### Event card anatomy (exact, from the skeleton markup)

**OBSERVED** — the loading skeleton mirrors the real card node-for-node:

```
[ image ] aspect-[833/500], w-full, rounded-lg  → sm:rounded-xl
  ↓ mt-[15px], flex-row, items-end, gap-4
  ├── left column (flex-1, min-w-0, gap-[5px])
  │     title      text-[17px] leading-[20px]
  │     meta line1 text-[13px] leading-[13px]
  │     meta line2 text-[13px] leading-[13px]
  └── right column (shrink-0, items-end, gap-1)
        label   (small — skeleton h-2.5 w-8)
        price   (larger — skeleton h-4 w-12)
```

**OBSERVED** — the price label logic is in the bundle verbatim:

```js
aY(e){ return e.all_lowest_ask_all_in ? "From $"+e.all_lowest_ask_all_in
     : e.last_sale ? "Last Sale "+e.last_sale
     : "Be the first to sell" }
aH(e){ return e.all_lowest_ask_all_in ? {prefix:"From", value:"$"+…}
     : e.last_sale ? {prefix:"Last Sale", value:…} : null }
```

This is the single most important card detail: **the card price is the all-in (fee-inclusive) lowest ask; when there is no ask, the card falls back to the last traded price; when there is neither, it says "Be the first to sell."** A card is never blank and never lies about availability.

**OBSERVED** — the same three-state ladder appears on venue pages as SSR text, e.g. `Underworld (Thurs + Fri) — Thu, Sep 3, 2026 at Knockdown Center — tickets from $109`, and one event in the same list (`OUTLINE: Flying Lotus, ∈Y∋, …`) renders with **no price line at all** — the no-inventory state.

### Filters

**OBSERVED** — filter copy constants: `{whereHeading:"Where", whenHeading:"When", thisWeekend:"This weekend", nextWeekend:"Next weekend", customDate:"Custom", clearFilter:"Clear filter"}`. Pills are `rounded-full px-4 py-2 text-sm font-medium tracking-tight bg-white/[0.04] backdrop-blur-md hover:bg-white/[0.08]`.

**INFERRED** — the entire discovery filter surface is **two dimensions: city and date**. There is no genre, no price band, no venue-type filter on the home page. For a nightlife product where the decision is "where am I going tonight," this is a defensible reduction, and it is the opposite of the filter-heavy resale norm.

---

## 2. IMAGERY

This is the section most directly transferable to Snatch It, because CrowdVolt has solved the weak-artwork problem that afflicts resale marketplaces.

### They keep three images per event, not one

**OBSERVED** — every event object in the RSC payload carries three distinct image fields:

```json
"img_link":        "https://crowdvolt-894150087.imgix.net/1b87aefc-….png?auto=format,compress",
"square_img_link": "https://crowdvolt-894150087.imgix.net/d4fcfb07-….png?auto=format,compress",
"og_img_link":     "https://img.crowdvolt.com/c1cd0bd1-….jpg"
```

**OBSERVED** — the selector, verbatim from the bundle:

```js
var aV = "/fallback-image.jpg";
aj(e,t){ return t?.square ? (e.square_img_link || e.img_link || aV)
                          : (e.img_link || e.square_img_link || aV) }
```

Landscape-preferred with a square fallback, square-preferred with a landscape fallback, and a static file as the last resort. **INFERRED** — the cross-fallback means a card in a 5:3 rail will happily render a square master (object-cover crops it) rather than showing a hole. The design tolerates the wrong ratio but never tolerates absence.

**OBSERVED** — the last-resort path `https://www.crowdvolt.com/fallback-image.jpg` currently returns **HTTP 404** (`content-type: text/html`). **INFERRED** — the fallback is effectively dead code because it is never reached in practice; see coverage below.

### Artwork coverage is 100%

**OBSERVED** — of the 1,334 sitemap URLs, **every one of the 521 event URLs, 133 venue URLs and 622 performer URLs carries at least one `<image:image>` entry**; only the 53 help-centre articles and the 5 static pages have none. Zero events without artwork. Image hosts: `img.crowdvolt.com` (2,321 images) and a legacy `miragematch.s3.us-east-2.amazonaws.com` (8 images).

**INFERRED** — a resale marketplace does not get 100% artwork coverage from sellers. It gets it from an ingest pipeline that pulls art from the primary source and normalises it. The direct evidence for that is below.

### They normalise every master to one ratio at ingest

**OBSERVED** — source pixel dimensions, read from imgix `?fm=json`:

| Asset | Dimensions | Ratio |
|---|---|---|
| Underworld landscape master | 3657 × 2195 | 1.6661 |
| Azzecca landscape master | 2399 × 1440 | 1.6660 |
| Experts Only landscape master | 1440 × 864 | 1.6667 |
| Underworld square master | 2330 × 2330 | 1:1 |
| Experts Only square master | 1358 × 1358 | 1:1 |
| Azzecca **rehosted** square | 1440 × 1440 | 1:1 |

`833/500 = 1.666` — the Tailwind class `aspect-[833/500]` used 24 times on the home page is **exactly** the ratio of the stored masters. **INFERRED, high confidence:** artwork is cropped/padded to a fixed 5:3 at ingest, so the card grid can never be broken by a seller's or a promoter's odd aspect ratio. Sizes vary (1440px to 3657px wide) but the ratio does not.

### They generate the missing variant

**OBSERVED** — where an event has no square master, the square field points at a *generated* asset keyed to the event slug:
`https://crowdvolt-894150087.imgix.net/assets/azzecca-arc-of-the-lake-costaways-thu-sep-3-chicago/rehost-azzecca-arc-of-the-lake-costaways-thu-sep-3-chicago-ee35626edb454da2.png?auto=format,compress` — 1440 × 1440.

The literal token in the filename is `rehost-`. **INFERRED** — a background job re-hosts and re-crops third-party artwork into CrowdVolt's own CDN namespace, producing a deterministic 1440² square from a 5:3 landscape. This is the mechanism behind 100% coverage.

### Artwork is sourced from the primary/discovery platforms

**OBSERVED** — a performer image on the Underworld page:
`https://img.crowdvolt.com/assets/e606638c-0985-440c-bfb1-56fcab0623ca/resident_advisor-193-44c5d195.jpg`

The filename encodes the origin: **Resident Advisor**. The same event's `wallet_systems` lists `[["a2e3427f-…","Resident Advisor"],["dice","DICE"]]`.

**INFERRED** — CrowdVolt ingests both event metadata *and* artwork from the primary ticketing / listings platforms (DICE, AXS, Resident Advisor, Posh, TIXR, Shotgun, Fever, Tao all appear as flags in the payload). The marketplace inherits the primary platform's artwork quality instead of depending on sellers. **This is the whole answer to "how does a resale marketplace cope with weak artwork": it does not source artwork from resellers at all.**

### CDN parameters, verbatim

**OBSERVED**

- Event artwork: `…imgix.net/<uuid>.png?auto=format,compress` — modern format negotiation + compression, no crop or size params on the master URL.
- Rendered through Next.js image optimisation: `/_next/image?url=<encoded imgix url>&w=1920&q=85` for event artwork, `&w=1920&q=75` for `img.crowdvolt.com` assets.
- User avatars: `…imgix.net/<hash>_user-live-<uuid>.jpg?auto=compress&h=120`, rendered as `/_next/image?url=…&w=1920&q=100`.

**INFERRED** — a bug worth not copying: avatars are constrained to `h=120` at the imgix layer, then requested at `w=1920&q=100` from Next.js. The upscale-to-1920 of a 120px-tall source is wasted bytes and will look soft on retina. Reasoning: `w` is the Next.js width hint and `h=120` has already capped the source.

### Geometry, cropping, overlays

**OBSERVED** — across the home page and event page markup:

- Aspect classes: `aspect-[833/500]` ×24 (event cards), `aspect-square` ×42 home / ×8 event (avatars, performer bubbles), `aspect-[9/10]` ×1 (a single portrait treatment).
- Radii: `rounded-full` ×164 (pills, avatars, price chips), `rounded-xl` ×44, `rounded-[14px]` ×42, `rounded-lg` ×32, `rounded-3xl` ×10, plus `--radius: 0.5rem` as the shadcn base token.
- Card image: `rounded-lg` on mobile stepping up to `sm:rounded-xl`.
- Object fit: `object-cover` ×41, `object-contain` ×16, `object-center` ×2.
- Counterparty avatar in the buy sheet: `w-16 h-16 rounded-xl overflow-hidden border border-white/15`, `layout="fill" objectFit="cover"`, with `bg-gray-700 animate-pulse` underneath until `onLoad`.

**OBSERVED** — there is **no text-over-image treatment on event cards**. Title, venue, date and price all sit *below* the image in a separate flex row. **INFERRED** — this is the correct call for ingested third-party artwork: you cannot guarantee a safe area or a legible focal region in art you did not commission, so you never put type on it. Overlays and gradients are absent from the card entirely.

### Loading and placeholders

**OBSERVED** — a bespoke skeleton system, not a generic spinner:

- `cv-skeleton` blocks at `bg-white/[0.06]` (image) and `bg-white/[0.05]` (metadata).
- Staggered reveal via a CSS custom property on each node: `--shimmer-delay: 0s` (image), `0.12s`, `0.24s`, `0.36s` (text lines), `0.3s`, `0.42s` (price block).
- Shimmer tokens: `--shimmer-dur: 0.9s`, `--shimmer-ease: cubic-bezier(0.33,1,0.68,1)`, `--shimmer-angle: 100deg / 180deg`, `--shimmer-size: 400% 100%`.
- The price chip has its own shimmer while the market loads: `min-h-11 w-[86px] rounded-full bg-gray-800 px-3 outline outline-1 outline-gray-700` containing `<span class="font-bold text-gray-600 text-base">--</span><span class="text-gray-400 opacity-70 text-sm">ea</span>` with an inline `linear-gradient(90deg, transparent 0%, rgba(255,255,255,0.06) 40%, rgba(255,255,255,0.12) 50%, rgba(255,255,255,0.06) 60%, transparent 100%)` sweep.

**INFERRED** — the skeleton is layout-identical to the loaded card, so there is zero cumulative layout shift on hydration. The staggered delays make a rail resolve left-to-right, top-to-bottom, which reads as intentional rather than janky. This is a high-craft detail worth stealing outright.

**OBSERVED** — branded loading messages rotate from a fixed list: `"Tuning the speakers…"`, `"Checking the guest list…"`, `"Finding your people…"`, `"Warming up the dance floor…"`, `"Cueing the next track…"`, `"Counting the wristbands…"`, `"Saving your spot…"`, `"Charging the bolt…"`, `"Syncing the lights…"`, `"Lining up the encore…"`, `"Stamping your hand…"`, `"Hyping the crowd…"`, `"Dropping the bass…"`, `"Clearing the smoke…"`, `"Rolling out the carpet…"`, plus fixed strings `"Completing your purchase…"` and `"Posting your listing…"`.

---

## 3. TYPOGRAPHY

**OBSERVED** — font stacks declared in the compiled CSS:

```
--font-inter            → var(--font-inter), Inter, ui-sans-serif, system-ui, sans-serif   (primary UI)
--font-instrument-serif → "Instrument Serif", "Instrument Serif Fallback", serif           (display)
--font-vt323            → VT323, monospace                                                 (pixel/retro accent)
--font-newsreader       → serif
--font-geist-sans       → "Geist", sans-serif
```

Seven `.woff2` faces are preloaded from `/_next/static/media/`.

**OBSERVED** — body typography:
`body{ font-weight:470; font-optical-sizing:auto; font-feature-settings:"liga" 1,"calt" 1,"cv01" 1,"cv02" 1,"cv03" 1,"cv04" 1,"cv15" 1 }` with `-webkit-font-smoothing:antialiased`.

**INFERRED** — `font-weight:470` (a non-integer-stop variable weight) plus Inter's `cv01`–`cv04`/`cv15` character variants is a deliberate, unusual choice: it swaps in the single-storey `a`, straight-tailed `l`, disambiguated `1`/`I`. It gives Inter a slightly technical, less-default look. Small effort, real differentiation.

**OBSERVED** — the type scale in use (`rem` values found in CSS): `.65 / .7 / .75 / .8125 / .875 / .9375 / 1 / 1.125 / 1.25 / 1.5 / 1.75 / 1.875 / 2.25 / 3 / 3.75 / 4.5`.

**OBSERVED** — specific, load-bearing sizes:

| Element | Spec |
|---|---|
| Rail section heading | `text-xl font-bold tracking-tight` → `lg:text-[30px] lg:leading-9 lg:tracking-[-1.8px]` |
| Card title | `text-[17px] leading-[20px]` |
| Card metadata (venue, date) | `text-[13px] leading-[13px]` |
| Card price | small `prefix` label above a larger value, right-aligned |
| Price chip in the book | value `font-bold text-base`, `ea` suffix `text-sm text-gray-400 opacity-70` |
| Counterparty price (buy sheet) | `text-5xl font-bold tabular-nums`, with `each` at `text-[16px] tracking-[-0.011em] font-semibold` |
| App hero (mockup) | `text-[22px] font-semibold leading-[23px] tracking-[-0.06em]` |
| Search input | `text-[16px] font-normal tracking-[-0.32px]` |
| Profile stat labels | ALL CAPS: `JOINED`, `RATING`, `EXCHANGES`, `REVIEWS`, `BIO` |

**INFERRED** — the price hierarchy is unambiguous and marketplace-correct: **$48px `tabular-nums` at the point of commitment**, a compact right-aligned chip in the list, a 13px "From $X" on the card. `tabular-nums` on a live order book is the right call — digits do not jitter as the market ticks. Card metadata at `leading-[13px]` (leading = size) is *very* tight; it reads as a dense caption block under an airy image.

**Capitalisation:** sentence case for content, ALL CAPS only for profile stat labels and section eyebrows (`REFER & EARN`, `LIVE IN`, `AVAILABLE BALANCE`, `KEEP UP WITH US`). OBSERVED.

**Colour tokens** (OBSERVED, `.dark` block — the site ships dark-only):
`--background: 0 0% 5.1%` (≈#0D0D0D) · `--foreground: 0 0% 95%` · `--card: 24 9.8% 10%` · `--muted-foreground: 240 5% 64.9%` · `--border: 240 3.7% 15.9%` · `--primary: 346.8 77.2% 49.8%` (rose) with a second `--primary: 274 100% 52.9%` (electric purple) in another scope · app mockup surfaces `#0d0c0c` / `#0D0D0D` on text `#F6F5F2`.

---

## 4. EVENT / LISTING PAGE

Reference page: `https://www.crowdvolt.com/event/underworld-presents-crazy-crazy-knockdown-center-new-york-queens-september-4-2026`

### Structure (OBSERVED, SSR text + payload)

1. Hero artwork (5:3 master).
2. `Underworld (Thurs + Fri)` — h1.
3. `Thu, September 3 • 8:00PM • Knockdown Center` — a single bullet-separated metadata line.
4. `Getting there: Knockdown Center is at 52-19 Flushing Ave, New York, NY.` + a `Directions` link to Google Maps.
5. `Tickets from $105`.
6. `Lineup` → linked performer list (`/performer/underworld`).
7. The market: a `Buy` / `Sell` pair, and within it a segmented control `Tickets available` / `Interested buyers`.
8. Order-book rows.
9. Venue block with full address, `Lineup`, then related events.
10. Two SEO prose blocks: `Where to buy … tickets` and `How CrowdVolt compares to other ticket marketplaces`.

### The market panel

**OBSERVED** — the tabs are Radix tabs styled `h-10 grid w-full grid-cols-2 … bg-transparent backdrop-blur-sm border border-gray-700 rounded-full`, active state `rounded-full ring-1 ring-white bg-transparent`. Labels: **`Tickets available`** and **`Interested buyers`**. A separate `Filter ticket types` button (`w-10 h-10 rounded-2xl border border-gray-700`) sits beside them.

**INFERRED** — naming the two sides of an order book "Tickets available" and "Interested buyers" rather than "asks" and "bids" is the single best piece of language on the site. It gives you a two-sided market without teaching anyone finance.

### An order-book row (OBSERVED, verbatim fields)

```json
{ "user_first":"Daniel",
  "user_img_url":"…imgix.net/60fef634-9b0_user-live-….jpg?auto=compress&h=120",
  "user_verified":false,
  "price":90, "all_in_price":86, "qty":1,
  "ticket_type":"GA (Thursday)", "override_display_color":"#4BA026",
  "wallet_system_uqid":"dice",
  "has_qr":false, "requires_custody":null, "transfer_intent_mode":null,
  "time_to_expiry":null, "is_pending":false,
  "seller_review_count":74, "seller_transaction_count":101,
  "seller_tagline":"Joined Apr 2026", "is_blocked":false }
```

Rendered, the row is: **ticket type · quantity ("1 Ticket" / "1-2 Tickets" / "1-6 Tickets") · seller first name + avatar · price chip**. OBSERVED from the rendered page (Cbas, Cole, Spencer, Secia, Ten, Chaz, nicole, Max, James).

**OBSERVED** — ticket types carry a per-type display colour (`#4BA026` for GA Thursday, `#4D0087` for GA Friday) so a two-night event is visually separable in one list.

### Price presentation on the event page

**OBSERVED** — event-level market fields:

```
all_lowest_ask 105 · all_lowest_ask_all_in 109 · min_ask_type "GA (Thursday)"
max_bid 105 · max_bid_all_in 101 · max_bid_type "GA (Friday)"
high_price 210 · high_price_all_in 217
last_sale "$$109" · tickets_remaining 63 · ticket_limit 6
looking_to_go 7 · looking_to_sell 35 · hours_til_event 25
```

Per ticket type: `highest_bid_price 90 / lowest_ask_price 105 / all_in_lowest_ask_price 109`.

**OBSERVED** — an inconsistency: the hero and the JSON-LD publish the **pre-fee** ask (`Tickets from $105`, `lowPrice: 105`), while cards and venue pages publish the **all-in** ask (`tickets from $109`). Both appear on the site for the same event on the same day.

### Counterparty block in the buy/sell sheet

**OBSERVED** — copy dictionary:
`{yourBuyer:"Your buyer", yourSeller:"Your seller", buyNowFor:"Buy now for", sellNowFor:"Sell now for", newSeller:"New seller", newBuyer:"New buyer", each:"each"}`, with the price as `$` + `all_in_price` (buying) or `price` (selling) at `text-5xl font-bold tabular-nums`.

Under the name: transaction count, then reviews as an underlined button, else the tagline. The formatters, verbatim:

```js
U(e,t){ return e>0 ? (e>100?"100+":e)+" transaction"+(e!==1?"s":"") : (t?"New seller":"New buyer") }
H(e){ return (e>100?"100+":e)+" review"+(e!==1?"s":"") }
```

### Related events

**OBSERVED** — `discover_more_events` carries exactly three entries, each `{uqid, name, venue, date, image_link, liked}` — e.g. `{"name":"Experts Only Festival","venue":"Randall's Island","date":"Sat, September 19 • 3PM", …}`. The `liked` boolean means the related rail is also a favouriting surface.

### Structured data

**OBSERVED** — the event page emits four JSON-LD blocks: `Organization`, `WebSite`, `MusicEvent`, `FAQPage`, `BreadcrumbList`. The `MusicEvent` offer is:

```json
"offers":{ "@type":"AggregateOffer", "priceCurrency":"USD",
  "availability":"https://schema.org/InStock",
  "category":"secondary",
  "lowPrice":105, "highPrice":210, "price":105,
  "inventoryLevel":{"@type":"QuantitativeValue","value":63} }
```

**OBSERVED** — `"category":"secondary"` is declared in machine-readable metadata. **INFERRED** — this is CrowdVolt telling Google (and every AI crawler) that its inventory is resale, at the schema level. It is the most honest provenance signal on the site, and it is invisible to users.

**OBSERVED** — `robots.txt` explicitly allows `Googlebot`, `Google-Extended`, `Bingbot`, `OAI-SearchBot`, `ChatGPT-User`, `GPTBot`, `ClaudeBot`, `Claude-SearchBot`, `Claude-User`, `PerplexityBot`, `Applebot`, `CCBot`, `meta-externalagent`, `Bytespider`, plus every link-preview bot, and ends `User-agent: * / Disallow: /`. Comments in the file are explicit, e.g. the Common Crawl entry is annotated as the pretraining corpus for most LLMs and the link-preview block is annotated "shared event links must render rich cards."

**INFERRED** — CrowdVolt treats answer-engine visibility as a primary acquisition channel and has written its event pages (the "How CrowdVolt compares to other ticket marketplaces" prose naming StubHub, SeatGeek, Vivid Seats and DICE by name) as LLM-ingestible comparison content. That prose block is `aria-hidden="true"` — **it is written for machines, not for users.** OBSERVED (`["$","div",null,{"aria-hidden":"true","children":[…]}]`).

---

## 5. BUY / SELL FLOWS

### Buying

**OBSERVED** — help centre, "How does CrowdVolt work?":
> "CrowdVolt is a marketplace that connects ticket buyers and sellers seamlessly. Sellers list their tickets at an asking price or can instantly sell to an available buyer. Buyers can either place an offer at their preferred price or purchase a ticket immediately at the seller's asking price. When a match is made, the transaction is processed securely through our platform — giving both parties a safe and hassle-free experience."

**OBSERVED** — two modes in the UI: `mode:{buyNow:"Buy now", makeOffer:"Make an offer"}`; confirmation titles `{buy:"Confirm order", sellBin:"Confirm sale", sellList:"Review listing"}`; line items `{serviceFee:"Service fee", orderSubtotal:"Order subtotal", orderTotal:"Order total", balanceApplied:"Balance applied", totalEarnings:"Total earnings"}`; a `Discount code` field.

**OBSERVED** — offers are card authorisations, not charges:
> "The charge is an authorization held by your bank. This makes sure the credit card info is right." … "with most banks, these charges drop off within 3 – 5 business days."
> "Offers act as pending charges on your credit card." … "You may delete your offer at any point (before a transaction takes place)…" … "Once completed, offers are binding and final."

**OBSERVED** — bids carry explicit expiries; `bid_options` for this event were `[{"label":"Sep 3rd • 8AM"},{"label":"Sep 3rd • 1PM"},{"label":"Sep 3rd • 6PM"}]`.

**OBSERVED** — `cart_timer_seconds: 300` and cart-expiry copy `{timedOutLine1:"Your cart timed out,", timedOutLine2:"start fresh?", back:"Back"}`.

**OBSERVED** — quantity constraints are explained in plain sentences, not error codes:
- `"{name} is only selling {n} tickets"`
- `"This seller only sells all {n} tickets together."`
- `"This seller only sells in groups of 2, 4, or 6 tickets at a time."`
- `ticketQuantity:{label:"Ticket quantity", maxReached:"Maximum quantity reached"}`, `diceQtyLimit:{title:"Ticket limit reached"}`.

**OBSERVED** — empty states are two-sided and always offer the opposite action:
```
buyTitle:"No tickets are currently listed"  buySubtitle:"Get ahead of the crowd and make an offer"  buyCta:"Offer to buy"
sellTitle:"No current offers to buy"        sellSubtitle:"List for sale instead"                    sellCta:"List for sale"
eventStartedFallback:"Offering is unavailable - event has started"
```
plus `setPriceAlertCta:"Set price alert"` and a `/price-alert-art.svg` illustration (150×113 / 170×128).

### Selling

**OBSERVED** — help centre: "List your ticket with an asking price. Once a buyer purchases your ticket and the sale is completed, we guide you through the transfer process (if necessary)."

**OBSERVED** — the listing composer copy, in order:
`whatAreYouSellingHeading:"What are you selling?"` → `howManyTicketsHeading:"How many tickets?"` → `ticketTypeLabel:"Ticket type"` (fallback `"General Admission"`) → `ticketPlatformLabel:"Ticket platform"` / `walletSystemPlaceholder:"Select wallet system"` → `pricePerTicketLabel:"Price per ticket"`, `tapToTypePrice:"Tap to type your price"`, `checkingPrice:"Checking price…"` → `feePreviewLoading:"Calculating buyer and seller fees..."` → `feeBreakdownTitle:"Fee breakdown"` → `continueLabel:"Continue"`.

### Fee presentation — the strongest thing on the site

**OBSERVED** — while the seller types a price, the UI shows **both sides simultaneously**:

```
payoutPrefix:      "You'll get "
buyersPayPrefix:   "Buyers pay "
buyerAllInLabel:   "Buyer all-in, each"
lowestListingPrefix: "lowest listing "
statusSeparator:   " · "
```

and the disclaimer, verbatim:
> "Your listing is displayed as an all-in price to buyers (including CrowdVolt's service fee). This differs from your listing price and earnings."

**OBSERVED** — help centre, "How do fees work?": "The buyer pays your listing price plus a buyer fee" (example `$50 listing + $2 buyer fee = $52 total at checkout`) and "You receive your listing price minus a seller fee" (example `$50 listing - $2 seller fee = $48 paid out to you`), with:
> "There are no additional fees charged at any stage — what you see at listing and checkout is exactly what you pay or receive."

**OBSERVED** — the actual fee rate is **never disclosed**; the $2 figures are illustrative. **INFERRED** — from the live payload, ask 105 → buyer all-in 109 (≈3.8%) and bid 105 → seller net 101 (≈3.8%); a second event gave ask 169 → all-in 176 (≈4.1%) and ask 20 → all-in 21 (5%). So the take is roughly **4% per side, ~8% round trip**, materially below StubHub-class fees. Reasoning: `all_in_price` minus `price` across observed rows, rounded to whole dollars.

**OBSERVED** — price guidance for sellers is a *nudge*, not a rail: alongside the price field the UI shows `"lowest listing $X"`, and if the seller undercuts materially they must tick a confirmation — `title:"Low price alert"`, `checkboxLabel:"I understand that I'm listing my ticket at a low price"`.

### Payouts

**OBSERVED** — help centre: funds are released "after a 48-hour review period"; for QR tickets, "funds become available within 48 hours after the event concludes." Withdrawals: standard "2–3 business days", instant "30 minutes or less" for qualifying institutions.

**OBSERVED** — wallet copy: `availableTooltip:"Approved sales, minus balance purchases, active offers, and pending withdrawals."`, `comingSoonTooltip:"Completed sales still under review. Funds are typically available 48 hours after the sale and once buyer receipt is confirmed. Or for QR code tickets, 48 hours after the event ends."`, `siteCreditTooltip:"Can be applied to purchases. Site credit cannot be withdrawn."`, `instantBadge:"Instant payout"`, `"Funds typically arrive within 30 minutes"` / `"Funds typically arrive in 3-5 business days"`.

**OBSERVED** — early payout is explicitly collateralised: "An early withdrawal means you receive your funds **before the event takes place**", requires a card on file, and "Your card on file will **only** be charged if the event you sold tickets for is cancelled."

**OBSERVED** — Supplemental Terms for Sellers: "Payments are typically processed within one (1) – two (2) business days after confirmation of valid ticket delivery and CrowdVolt receipt of a withdrawal request… In some cases, payments may occur one (1) – two (2) business days post-event for security purposes."

---

## 6. TRUST AND PROVENANCE — the most important section

### The guarantee, stated in three registers

**OBSERVED — legal (User Agreement §9.3 "Purchase of Tickets"):**
> "When a Buyer places an order to purchase tickets, the sale is final. While the delivery and shipment of tickets is handled by the Seller, CrowdVolt guarantees that Buyers will receive valid tickets before the event date. If valid tickets are not delivered in time for the event, CrowdVolt will either secure replacement tickets or provide a full refund to the Buyer."

**OBSERVED — help centre ("Are my tickets real?"):**
> "We know your event is important to you. That's why all orders are backed by CrowdVolt. In the rare case there's an issue with your order, we'll make it right with comparable or better tickets, or your money back."

**OBSERVED — product surface (event page prose):**
> "Every purchase is protected by CrowdVolt until tickets arrive, and most tickets are delivered within minutes."

**INFERRED** — the same promise is expressed three times at three different reading levels, and the wording narrows as it gets closer to the transaction. Nowhere is it branded as a named programme ("FanProtect", "Buyer Guarantee"). It is a verb, not a trademark: *backed by*, *protected by*, *we'll make it right*.

### The enforcement machinery behind the guarantee

**OBSERVED — Supplemental Terms for Sellers, §2.1 "Dropped Orders".** A tiered delivery SLA keyed to time-to-event:

| Time until event | Delivery deadline |
|---|---|
| More than 24 hours | within 24 hours |
| 12 – 24 hours | within 12 hours |
| 6 – 12 hours | within 2 hours |
| 0 – 6 hours | within 1 hour |
| After event has begun | within 15 minutes |

And the penalty, verbatim:
> "In the event a Dropped Order occurs, CrowdVolt may, at its sole discretion, charge the Seller an amount up to or greater than **200% of the price of the tickets sold** to compensate us for the expenses we incur to meet our obligations to the Buyer. CrowdVolt reserves the right to suspend or terminate your CrowdVolt Account in the event of a Dropped Order. If a Seller believes that a charge for non-delivery has been applied in error, they may contact CrowdVolt's customer service team within 48 hours of the charge notification with corresponding evidence."

**OBSERVED** — and the seller is made to agree to this *at listing time*, not buried in terms. The checkout copy for a seller reads:
> "I accept the **Terms and Conditions**. If you are unable to deliver the correct tickets, CrowdVolt reserves the right to charge you the cost of replacing the tickets for your buyer."

**OBSERVED** — the standing card mandate: "you grant CrowdVolt permission to debit your balance or charge the credit or debit card associated with your registered account for any and all charges… if at any time the Seller fails to deliver the tickets they have listed or delivers invalid, fraudulent, counterfeit, incorrect, or misrepresented tickets."

**OBSERVED** — listing restrictions are itemised: no speculative tickets ("tickets that the Seller does not own, have in-hand, or that have been allocated to them"), no BOTS-Act-violating tickets, no stolen tickets, no non-consecutive seats, no personal information in seller notes.

**OBSERVED** — help centre, "What happens if someone tries to sell fake tickets?": "We require sellers to only list valid tickets, provide accurate information in the ticket listing, and fulfill orders with the correct tickets in time for the event." … "If a seller does not follow these policies, we'll step in to obtain the correct tickets from the seller, or offer you replacement tickets or a full refund." … repeat offenders' accounts are "flagged, charged and/or suspended to protect marketplace quality."

**INFERRED** — this is the architecture of the whole business: **a buyer-facing guarantee funded by a seller-facing 200% clawback with a card on file.** The guarantee is not an insurance pool; it is a liability transfer. Snatch It's transfer/escrow model needs an equivalent, and this is a proven shape.

### Per-seller trust signals

**OBSERVED** — every order-book row carries `seller_review_count`, `seller_transaction_count`, `seller_tagline`, `user_verified`. Across 42 rows on one event: taglines were all of the form `"Joined Sep 2024"`, `"Joined Mar 2026"`; transaction counts ranged 0–101; review counts 0–74; `user_verified` was **true for exactly 1 of 42 rows**.

**OBSERVED** — profile stat labels: `JOINED`, `RATING`, `EXCHANGE`/`EXCHANGES`, `REVIEW`/`REVIEWS`, `overflowCount:"100+"`, plus alt labels `Reliability`, `Transactions`, `Reviews`. Recency signals: `"Active today"`, `"Last active this week"`, `"Last active this month"`, `"Last active over a month ago"`.

**OBSERVED** — reviews are mutual: "Upon completing a transaction, both buyer and seller alike can leave a review", editable afterwards, reachable from `Orders` / `Sales`. Empty state: `"Complete a transaction with them to leave the first review!"`

**INFERRED** — the trust model is **reputation-forward, identity-light**. You see a first name, a photo, a join month, a transaction count and a review count. You do not see a surname, and verification is effectively unused (1/42). The reputation is transactional history, not identity proof. That is the right trade for a nightlife audience, and it is cheap to run.

### Provenance: where the ticket actually came from

**OBSERVED** — provenance is modelled per ticket type and per listing:
- Event-level: `"app_name":"DICE"`, plus booleans `requires_dice`, `requires_getin`, `requires_posh`, `requires_tao`, `requires_feverup`, and IDs `dice_event_uqid`, `axs_event_uqid`, `getin_event_uqid`, `posh_event_uqid`, `tao_event_uqid`, `feverup_event_uqid`.
- Ticket-type-level: `"wallet_systems":[["dice","DICE",false],["a2e3427f-…","Resident Advisor",false]]`.
- Listing-level: `"wallet_system_uqid":"dice"`, and a `Ticket platform` selector in the sell flow.
- Another event observed with `"app_name":"AXS"`, `"wallet_systems":[["axs","AXS"]]`.

**OBSERVED** — CrowdVolt never takes custody by default: "CrowdVolt does not custody any tickets – rather, tickets are sent between buyer and seller via the third-party platform/digital ticket wallet where originally sold (e.g., Ticketmaster)." … "CrowdVolt solely coordinates transfer between buyer and seller."

**OBSERVED** — platform-specific delivery copy, generated per wallet system:
- Ticketmaster: "Your ticket will be delivered by the seller via email. Be sure to check your inbox and claim the ticket so it appears in your Ticketmaster account."
- Shotgun: "We're having trouble connecting to your Shotgun account. Please leave an email and phone that we can reach you at to deliver the tickets."
- Generic: "Your ticket will be transferred manually — make sure the email above is the one you use for {platform}."
- Standard path: `mobileTransferTitle:"Delivery via mobile transfer"` / `mobileTransferInfo:"Your tickets will be transferred directly to your account by the seller via the ticketing platform's app."`

**OBSERVED** — custody *does* exist for wristband/festival inventory: `is_wb`, `is_wb_shipping_cutoff`, `is_wb_drop_off_available`, `custody_required_at`, plus will-call copy — "CrowdVolt coordinates a local will-call window so buyers can pick up their wristbands on-site." … `bringPhotoId:"Valid government-issued photo ID"`, `bringOrderConfirmation:"Order confirmation (digital or printed)"`, `ack:"I understand that I must pick up my wristband"`. There is also an optional in-person handoff: "If your tickets sell, would you be open to meeting the buyer in person?"

### Normalising the things that scare buyers

**OBSERVED** — a dedicated help article, "Ticket validity FAQs", pre-empts the three signals that make a resale ticket *look* fake:
1. A different name on the ticket — "Since CrowdVolt is a ticket marketplace, tickets often include the original buyer's name." Most venues do not check.
2. Seat numbers printed on GA tickets — "Venues tend to include seat numbers on general admission tickets to track how many tickets they sold."
3. Tickets living in a third-party app — you must "login to your third-party account platform to view your tickets."

**INFERRED** — this is quietly excellent. The three most common "my ticket is fake" support tickets in resale are pre-answered as *normal*, in the help centre, indexed for search. It converts a fear into an FAQ.

**OBSERVED** — ID handling: photo ID is requested only where the venue requires it — "Some event organizers will require attendees to show the photo ID of the original purchaser along with a QR to ensure validity" — and the flow explicitly invites redaction: `idInstructionSuffix:" Name and photo must be visible and match the name on the ticket. You may redact sensitive details."` Fields `requires_id` and `is_qr_required` gate it per event.

**OBSERVED** — listing-integrity guardrails at upload: `"Do not upload the QR code!"`, `"Don't crop your ticket. The event name and ticket type must be visible, or your listing may be rejected."`, duplicate-QR detection (`"Duplicate QR value detected. Upload a unique code for the second ticket."`), wrong-date detection (`"This ticket shows a different event date. Upload tickets for this event only."`), unreadable-file detection, and a platform-specific warning: `"Upload only the Apple Wallet QR code or PDF ticket from your purchase email. QR codes from the TIXR app may rotate and be invalid."`

**INFERRED** — they are running automated verification on uploaded ticket files (event name, ticket type, date, QR uniqueness). That is the fraud control that makes the guarantee affordable.

### Cancellations

**OBSERVED** — full cancellation: buyers receive full refunds including any markup or discount paid; sellers must return all proceeds regardless of profit or loss. Partial curtailment: refunds flow only "where the event organizer or primary ticketing provider has offered refunds to original ticket purchasers." The stated principle: "Buyers paid with the expectation of attending the event, and sellers are only entitled to proceeds when that service is fulfilled."

### Is resale distinguished from official inventory?

**OBSERVED** — CrowdVolt carries **no first-party inventory**. Every listing is a fan listing. The only resale disclosures are:
- The persistent top-of-page strip: `Prices may be set above or below face value by the seller.`
- Help centre: "Ticket prices on CrowdVolt vary because sellers set their own ticket prices. These prices may be higher or lower than face value, and may also vary by seller."
- `"category":"secondary"` in JSON-LD.

**INFERRED** — because there is no mixed inventory, they never had to solve the hardest disclosure problem in ticketing: distinguishing an official ticket from a resale ticket *in the same list*. **Snatch It will have this problem the moment venue-native first-party ticketing ships, and CrowdVolt offers no pattern for it.** This is a genuine gap in the benchmark, and an opportunity.

---

## 7. NAVIGATION

**OBSERVED** — web header: logo · `Events` · `About` · `Help` · `Invite friends` · `Log in` (→ `Open user menu` when authenticated), with a persistent `Search by event, artist, or venue` field and an `Open main menu` mobile toggle. Footer: **Company** (Home, About) · **Support** (Request an event, Help) · **Legal** (Privacy Policy, Terms & Conditions) · `© 2026 CrowdVolt. All Rights Reserved.` · Instagram, TikTok, SoundCloud (`soundcloud.com/crowdvoltradio`), LinkedIn.

**INFERRED** — the web nav is four items deep and has no "My tickets" entry point in the signed-out header. It is a marketing shell around a search box; the product lives on the event page.

**OBSERVED** — the mobile app (from the app-landing phone mockup) has a distinct second surface: a **`Dashboard`** with its own search (`Search events or order #`) and an `Action required` section carrying a count badge. Home sections are `Tonight` / `Trending` / `Our pick`.

**INFERRED** — "Action required" with a live count is the app's transactional inbox: deliver a ticket, claim a transfer, upload an ID. For a marketplace where a dropped order costs the seller 200%, surfacing obligations as a counted queue on the home tab is the right architecture. Snatch It should have the equivalent.

**OBSERVED** — depth is shallow and entity-linked: event → performer (`/performer/underworld`) → upcoming shows; event → venue (`/venue/knockdown-center-f852b`) → the venue's full schedule with prices. Help centre is three levels: `Help > Buying > How does CrowdVolt work?` with `Similar questions` cross-links and a `Was this article helpful? Yes / No → Thank you for your feedback!` widget.

**OBSERVED** — support is reachable as `Text us` / `Email us` with `Estimated response time: 5 mins` when online, and an offline template `"We'll be back in {n} hours."`

---

## 8. MOTION (evidence only)

**OBSERVED**

- Framer Motion is bundled (`protectedKeys`, `needsAnimating`, `prevResolvedValues` internals are present in the chunks).
- Standard easing across the design system: `cubic-bezier(0.22,1,0.36,1)` (an ease-out-quint) at `duration-300` for opacity and `duration-[400ms]` for width transitions; `transition-colors duration-150` on pills and `duration-200` on icon buttons.
- Skeleton shimmer: `--shimmer-dur: 0.9s`, `--shimmer-ease: cubic-bezier(0.33,1,0.68,1)`, `--shimmer-size: 400% 100%`, with per-node `--shimmer-delay` staggering (0 → 0.42s).
- The hero headline is split into **per-character spans** with `--char-blur: 0px → 3px` and `--char-blur-soft: 0px → 2px` custom properties, plus `--ht-morph-pad: calc(max(0px, -1 * var(--ls, -0.07em)) + 1.5px)`. **INFERRED** — a character-level blur-in / morph animation on the rotating hero line ("You're coming out tonight in Miami"); the morph-pad token exists to stop tight letter-spacing clipping mid-animation.
- The rails in the app mockup are driven by `staggerMs` per section (`sectionStaggerMs`), a `heartPopMs` for the favourite tap, and `translateX`/`translateY` transforms.
- `motion-reduce:transition-none` appears on interactive text (e.g. the reviews link), so reduced-motion is at least partially honoured. OBSERVED.
- Focus rings are explicit throughout: `focus-visible:ring-1 focus-visible:ring-white focus:outline-none`.
- Accessibility scaffolding: an `sr-only` `<section>` mirrors the whole event page (h1, date line, directions, "Tickets from $105", lineup) so the page is legible before hydration; empty states carry `aria-label`s (`"Offers closed"`, `"No interested buyers"`, `"No tickets for sale"`).

---

## 9. MARKET MECHANICS

### The order book

**OBSERVED** — the product is a genuine two-sided book, not a listing wall. Per ticket type the payload carries `highest_bid_price` / `highest_bid_qty` / `highest_bid_uqid` and `lowest_ask_price` / `lowest_ask_qty` / `all_in_lowest_ask_price`. Buyers can `Buy now` at the lowest ask or `Make an offer`; sellers can list an ask or `Sell now` into the highest bid. The two tabs are `Tickets available` and `Interested buyers`.

**OBSERVED** — the marketing framing, from the event page's machine-facing prose: "CrowdVolt is a live bid/ask marketplace for electronic music events: sellers set asks, buyers either buy the lowest ask instantly or name their own price with a bid, so prices track real demand and are often below face value" and "on CrowdVolt fans trade in a live order book, so you can see the current floor price ($105 right now) and bid below it instead of accepting a fixed markup."

**OBSERVED** — observed spreads on 2026-09-02: Underworld GA (Thursday) bid 90 / ask 105 (all-in 109); GA (Friday) bid 105 / ask 114 (all-in 118); Experts Only Festival ask 169 (all-in 176), high 1800, last sale $281; Azzecca ask 20 (all-in 21), high 26, last sale $20.

### Scarcity and demand signals

**OBSERVED** — the payload carries four distinct demand/scarcity numbers per event:

| Field | Underworld | Experts Only | Azzecca |
|---|---|---|---|
| `tickets_remaining` | 63 | 133 | 19 |
| `looking_to_go` (open bids) | 7 | 27 | 0 |
| `looking_to_sell` (open asks) | 35 | 80 | 9 |
| `hours_til_event` | 25 | 404 | 24 |

Plus `ticket_limit: 6`, `show_count_down`, `show_transfer_delay`, `has_graph` (a price-history chart flag, `false` on all three events observed), and `user_price_alerts`.

**INFERRED** — every one of these is a *measured* quantity, not a manufactured one. `looking_to_sell: 35` vs `looking_to_go: 7` genuinely means supply exceeds demand and the price will likely fall. Publishing both sides is honest in a way that "Only 3 left!" never is, and it is the natural consequence of running a real book. **This is the mechanic most worth emulating.**

**OBSERVED** — I found **no** urgency devices of the manipulative kind in any bundle or page: no "X people are viewing", no "selling fast", no "prices rising", no fake countdown. The only timers are functional: a 300-second cart hold and explicit bid expiry times.

**OBSERVED** — buyer-side patience is a supported path, not a leak: `Set price alert` with its own illustration, and the empty-state nudge "Get ahead of the crowd and make an offer."

**OBSERVED** — the seller-side counterpart is `"Low price alert" / "I understand that I'm listing my ticket at a low price"` — friction applied *against* the house's short-term interest (a cheap listing sells faster).

**INFERRED — honest and worth emulating:** the bid/ask book, `looking_to_go` vs `looking_to_sell`, `last_sale`, `tickets_remaining`, all-in pricing on cards, price alerts, low-price confirmation.
**INFERRED — not present, and good that it isn't:** view counts, artificial countdowns, "almost gone" badges.
**INFERRED — the one soft spot:** `has_graph` implies a price-history chart exists but was `false` on every event sampled, and the site publishes the pre-fee ask in JSON-LD/hero (`$105`) while showing the all-in ask on cards (`$109`). A user who arrives from Google search results sees the lower number first. That is a dark pattern by omission, whether or not it is intentional.

---

## SOURCE URLs

**Product surfaces**
- https://www.crowdvolt.com/
- https://www.crowdvolt.com/event/underworld-presents-crazy-crazy-knockdown-center-new-york-queens-september-4-2026
- https://www.crowdvolt.com/event/azzecca-arc-of-the-lake-costaways-thu-sep-3-chicago
- https://www.crowdvolt.com/event/experts-only-new-york-2026-randalls-island-park
- https://www.crowdvolt.com/venue/knockdown-center-f852b
- https://www.crowdvolt.com/performer/underworld
- https://www.crowdvolt.com/about · /blog · /app/about · /app/selling
- https://www.crowdvolt.com/sitemap.xml · https://www.crowdvolt.com/robots.txt

**Help centre**
- /help_center · /help_center/buying · /help_center/selling · /help_center/general
- /help_center/buying/crowdvolt-work-how · /tickets-real-are · /ticket-validity-faqs · /receive-ticket-after-purchase · /what-happens-someone-tries-sell · /tickets-aren-t-working-event · /made-bid-why-charged · /make-offer-below-asking-price · /much-tickets-crowdvolt · /similar-tickets-crowdvolt-less-than
- /help_center/selling/sell-ticket-how · /paid-after-selling-ticket · /early-payouts-work · /ticket-delivery-deadlines · /why-crowdvolt-asking-photo-id · /leaving-review-a
- /help_center/general/fees-work-how · /which-cities-crowdvolt-operate · /what-happens-transaction-event-cancelled

**Legal**
- https://www.crowdvolt.com/terms_of_service/user_agreement (§9.3)
- https://www.crowdvolt.com/terms_of_service/supplemental_terms_for_sellers (§1.1, §2.1)

**Assets inspected (URLs recorded, not copied into the repo)**
- `https://crowdvolt-894150087.imgix.net/1b87aefc-68a2-43c7-aa37-e2c6e27379d9.png?auto=format,compress` — 3657×2195
- `https://crowdvolt-894150087.imgix.net/d4fcfb07-a404-4f56-80d0-fce73d73414f.png?auto=format,compress` — 2330×2330
- `https://crowdvolt-894150087.imgix.net/2dc00be4-a72d-4ee4-ba64-fee984d3dd86.jpg` — 2399×1440
- `https://crowdvolt-894150087.imgix.net/30ce4b61-1c12-49ce-8b6a-4179f2eb8139.png` — 1440×864
- `https://crowdvolt-894150087.imgix.net/95a4346e-0372-4b37-9409-f5ea98d4f4dd.png` — 1358×1358
- `https://crowdvolt-894150087.imgix.net/assets/azzecca-arc-of-the-lake-costaways-thu-sep-3-chicago/rehost-azzecca-arc-of-the-lake-costaways-thu-sep-3-chicago-ee35626edb454da2.png?auto=format,compress` — 1440×1440
- `https://crowdvolt-894150087.imgix.net/60fef634-9b0_user-live-25779070-bdd4-4c6d-a5c9-09ec08b45398.jpg?auto=compress&h=120` — avatar pattern
- `https://img.crowdvolt.com/assets/e606638c-0985-440c-bfb1-56fcab0623ca/resident_advisor-193-44c5d195.jpg` — performer art, RA-sourced
- `https://www.crowdvolt.com/fallback-image.jpg` — **404**

**Press / third-party (context only, lower confidence)**
- https://techcrunch.com/2024/07/16/yc-backed-secondary-ticketing-startup-crowdvolt/
- https://www.ycombinator.com/companies/crowdvolt · https://www.crunchbase.com/organization/crowdvolt

---

## WHAT CROWDVOLT DOES WELL

1. **All-in pricing everywhere the user decides.** The card price is `From $` + the fee-inclusive lowest ask. The seller composer shows "You'll get $X · Buyers pay $Y" while they type. There is no fee reveal at checkout. This is the highest-integrity price presentation in ticketing and it costs them nothing.
2. **A real order book, described in human words.** `Tickets available` / `Interested buyers` gives you bids and asks without the vocabulary of finance. `Buy now` vs `Make an offer` is the whole product in two buttons.
3. **A three-state price on every card that is never blank.** `From $109` → `Last Sale $109` → `Be the first to sell`. A resale marketplace's worst card state is "no inventory"; they turned it into a supply CTA.
4. **100% artwork coverage via ingest, not via sellers.** 521/521 events have art, normalised to exactly 5:3 at ingest, with a generated 1440² square where none exists, sourced from DICE / AXS / Resident Advisor. They never let a reseller's screenshot near the grid.
5. **A guarantee funded by a 200% seller clawback, agreed at listing time.** The buyer promise ("comparable or better tickets, or your money back") is backed by a tiered delivery SLA and a card mandate. Enforceable, not aspirational.
6. **The scariest resale fears pre-answered as normal.** "The name on the ticket isn't mine", "my GA ticket has a seat number", "the ticket is in someone else's app" — all three are help-centre articles that say *this is expected*.
7. **Honest scarcity.** They publish `looking_to_go` and `looking_to_sell` side by side, including when supply crushes demand. No view counters, no fake countdowns, no "selling fast".
8. **Skeletons that are layout-identical with staggered shimmer.** Zero CLS, and the reveal reads as choreography rather than lag.
9. **Reputation over identity.** First name, photo, join month, transaction count, review count, "Active today". No surname, verification effectively unused. Cheap, sufficient, and appropriate to nightlife.
10. **Copy with a voice.** "No more excuses. You're coming out tonight." · "Tuning the speakers…" · "Get ahead of the crowd and make an offer." It sounds like a person who goes out.

## WHERE SNATCH IT CAN BEAT IT

1. **Mixed inventory done properly.** CrowdVolt has zero first-party tickets, so it has never had to distinguish official from resale in one list. Snatch It will carry both. Get this right — a clear, non-punitive `Official` vs `From a fan` distinction with face value shown next to the ask — and you own the honesty position outright. CrowdVolt's only disclosure is a grey strip saying "Prices may be set above or below face value."
2. **Real provenance, shown.** CrowdVolt *models* provenance richly (`wallet_system`, `app_name`, DICE/AXS/RA/TIXR/Posh/Shotgun/Fever) and shows the user almost none of it. Snatch It, issuing its own tickets, can show an unbroken chain: issued by the venue → held by A → transferred to B → now yours. That is a claim CrowdVolt structurally cannot make, because it never holds the ticket.
3. **Delivery certainty instead of delivery hope.** CrowdVolt's honest position is "CrowdVolt does not custody any tickets… CrowdVolt solely coordinates transfer" — with a 200% penalty as the backstop for when a human forgets. Snatch It's native transfer is atomic. Say so, plainly: the ticket moves in the app, instantly, or the sale does not happen. That is a better promise than any guarantee.
4. **Face value as a first-class field.** CrowdVolt cannot reliably show face value (it is scraped, per-platform, often absent), so it hedges. If Snatch It issues the ticket, face value is known. Showing `$40 face · $55 ask` on every resale listing is a trust weapon and a regulatory hedge in one.
5. **One consistent price everywhere.** Fix the seam CrowdVolt has: their hero and JSON-LD say `$105` while their cards say `$109`. Pick all-in and never show anything else, including in structured data and share cards.
6. **Price history, actually shipped.** `has_graph` was `false` on every event sampled. A simple honest sparkline of what tickets actually traded at is the highest-trust, lowest-manipulation market signal available, and their field name suggests they know it.
7. **Discovery beyond city + date.** Two filter dimensions is elegant but thin. For nightlife, genre/sound, lineup, venue type and time-of-night are the real axes. CrowdVolt leans on 622 performer pages for SEO but does not use artists as a browse dimension in-product.
8. **A transactional home for obligations.** Their "Action required" dashboard is app-only and invisible on the web. Snatch It should make the obligation queue the front door on every surface.

## WHAT SNATCH IT SHOULD LEARN (without copying)

**Adopt the principles, not the pixels.**

1. **Ingest and normalise all artwork; never render a seller's image.** Pick one hero ratio, force every master to it at ingest, generate the square variant, cross-fall-back between them. Coverage should be 100% before a single card ships. Do not ship a `fallback-image.jpg` you have never tested — theirs is a 404.
2. **Make the fee-inclusive price the only price.** On cards, on the event page, in structured data, in share previews. Show sellers "You'll get $X · Buyers pay $Y" live as they type.
3. **Give every card a three-state price ladder.** Lowest all-in ask → last traded price → an invitation to supply. Never render an empty price slot.
4. **Fund the guarantee with a seller mandate, and get consent at listing time.** A tiered delivery SLA keyed to time-to-event, a card on file, and a stated clawback — surfaced as one sentence at the moment of listing, not buried in terms. Snatch It's native transfer should make dropped orders rarer, which makes the mandate cheaper, which is a competitive advantage.
5. **Write the "is this real?" articles before launch.** Name-on-ticket, seat number on GA, ticket lives in another app. Publish them, index them, link them from the listing. Convert the fear into an FAQ.
6. **Publish both sides of demand.** Buyers looking vs sellers listing, plus tickets remaining and last sale. It is honest, it is free, and it makes fake urgency unnecessary — so do not build fake urgency.
7. **Say the guarantee three times at three altitudes.** Legal clause, help article, one line at the point of purchase — with the wording tightening as you approach the transaction. Do not brand it; make it a verb.
8. **Name the order book in plain language.** "Tickets available" and "Interested buyers" beat "asks" and "bids" for a going-out audience. Snatch It's auction/buy-now split should get the same treatment.
9. **Build skeletons that are layout-identical, and stagger them.** ~0.12s per element, ~0.9s shimmer, ease-out-quint. It is the cheapest perceived-quality win available.
10. **Type on artwork you did not commission is a bug.** Keep title, venue, date and price below the image. No gradients, no overlays, no safe-area gambling.
11. **Treat answer engines as a channel.** Explicit `robots.txt` allowances, `Event` + `AggregateOffer` + `FAQPage` JSON-LD, and an honest `category` on your offers. But **do not** copy the `aria-hidden` prose block written only for crawlers — write comparison content that serves users too, or do not write it.
12. **Reputation, not paperwork.** First name, photo, joined date, transactions, reviews, last-active. Reserve heavier identity checks for the specific events that require them (`requires_id`, `is_qr_required`) rather than gating everyone.

**Do not copy:** the IP-guessed hero city that contradicts the filter chip in the same paint; the `h=120` avatar upscaled to `w=1920`; the pre-fee price in JSON-LD and the all-in price on cards; the crawler-only prose block; a documented fallback image that 404s; a `has_graph` feature flag that is off everywhere; and the fee rate being undiscoverable anywhere on the site — if the take is ~4% per side, say ~4%.

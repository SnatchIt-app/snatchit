# DICE (dice.fm) — Design Benchmark Research

**Agent D · Snatch It Product UI/UX V2 · Research date: 2026-09-02**

Method: raw HTML/CSS retrieved over HTTPS and parsed locally (styled-components rules are
server-rendered inline, so real class names, declarations and CDN URLs are directly readable).
`WebFetch` is blocked by DICE's edge (HTTP 403); all page evidence below comes from raw
retrieval. No proprietary assets were downloaded into the repo — only URLs and parameters
are recorded.

**Tagging discipline**
- **[OBSERVED]** — quoted or measured from a fetched artefact, with URL.
- **[INFERRED]** — reasoned from observed evidence; the reasoning is always stated.

A note on scope: dice.fm's web surface is deliberately a *shop window* for a mobile app.
Several flows (checkout completion, ticket credential, transfer, wallet) are app-only and
therefore **not directly observable**. Where that is the case, evidence comes from DICE's own
embedded i18n string dictionary, which ships in full inside the page HTML and contains
~1,328 unique keys covering the native app's copy. That is strong, quotable evidence of what
the app screens contain, but it is copy, not layout — flagged accordingly throughout.

---

## 0. The single most important finding, stated up front

DICE achieves visual consistency across wildly varying artist artwork by **refusing to trust
the uploaded image's shape at all**. Every image is normalised to a **square master via a
centre crop**, and every downstream context is a **deterministic, centre-anchored `rect`
crop of that master**, requested from imgix at an **exact pixel size that matches the CSS
box it lands in**. Nothing is left to the uploader, and nothing is left to the browser.

The arithmetic is provable from the URLs and is worked through in §2.1. This is the finding
that matters most for Snatch It, because our inventory problem is identical: user- and
venue-supplied artwork of unpredictable quality and shape.

---

## 1. DISCOVERY

### 1.1 The web home is not the discovery surface

**[OBSERVED]** `https://dice.fm/` is a *marketing* page, not a feed. Its `<h1>`–`<h3>`
sequence is:

> "Welcome to the alternative" · "Weirdly easy ticketing" · "What else?" ·
> "A network of world-class venues and promoters" · "Familiar favs, new crushes" ·
> "Loved by millions"

It carries autoplaying product films rather than inventory:
`https://dice-media.imgix.net/videos/discovery.mp4`,
`.../videos/nite-dice.mp4`, `.../videos/savedevents.mp4`.

**[OBSERVED]** Real discovery lives at city/browse routes:
`https://dice.fm/browse/london-54d8a23438fe5d27d500001c`, whose only `<h1>` is
**"Popular Events in London"**, and `https://dice.fm/city/london`.

**[INFERRED]** DICE has consciously split "convince a stranger" (home) from "help a returning
fan choose" (browse/city). The web home's job is app installs; the app's job is the feed.
This is why the web home shows no event cards above the fold at all — a choice most ticketing
sites would find unthinkable.

### 1.2 Personalisation model

**[OBSERVED]** From the embedded app dictionary (event page HTML), the personalised feed is
branded **"Your lineup"** and is *periodic* rather than infinite:

| key | copy |
|---|---|
| `discovery_your_lineup_title` | "Your lineup" |
| `discovery_your_lineup_body1` | "The shows you should have your eyes on this week" |
| `discovery_your_lineup_body2` | "What's worth your attention this week" |
| `discovery_your_lineup_body3` | "Here's a handful of events we think you'll want to be at" |
| `discovery_your_lineup_cta1/2/3` | "Take a look" / "Get to it" / "See you out there" |
| `discovery_your_lineup_ending1_title` | "Take your pick" |
| `discovery_your_lineup_ending2_body` | "Another lineup drops in %s" |
| `discovery_your_lineup_ending3_body` | "We'll have another lineup for you in %s" |
| `discovery_your_lineup_loading` | "Setting the stage..." |

**[OBSERVED]** Taste signal is music-library-derived:
`onboarding_artists_scan_description` = "We'll recommend shows that match your taste";
`event_purchase_confirmation_explain_music_services` = "Connect your Spotify or Apple Music."
Event payloads carry Spotify track previews (see §4.5).

**[INFERRED]** "Another lineup drops in %s" is a **deliberately exhaustible** recommendation
set with a refresh timer. That is the opposite of an infinite scroll: it manufactures scarcity
and a reason to return, and it caps the number of items the editorial/ranking system must get
right. For a city-scale nightlife catalogue this is a much easier quality bar to hold than an
endless feed.

**[OBSERVED]** Following is a first-class primitive across artists and venues —
`title_following` = "More to come soon", `message_following` = "We'll tell you when they
have events on DICE.", and the venue page carries a "Stay in the know / Follow this venue to
find out when they have events on DICE." block
(`https://dice.fm/venue/moot-club-xexwk`).

### 1.3 Categories, filters, search

**[OBSERVED]** The public taxonomy is strikingly small — five tags, from the browse payload:

```
music:dj      → "DJ"
music:gig     → "Gigs"
music:party   → "Party"
culture:social→ "Social"
culture:talks → "Talk"
```

Visible browse filter chips also include **Comedy**, **Film**, **Free**, plus two filter
dimensions only: **Date** and **Price** (`filter_date_title` = "Date",
`filter_price_title` = "Price", `filter_price_any_amount` = "Any amount",
`price_from` = "Min price", `price_to` = "Max price", `clear_filter` = "Clear filter").
Date options observed: **Today**, **Tomorrow**, **This week**.

**[INFERRED]** Two filters and ~5–8 categories is a radical reduction versus typical ticketing
taxonomies. It works because the *city* is the primary filter and it is applied before you
arrive — the route itself is the filter. Genre granularity is pushed into editorial
collections (§1.4) and personalisation rather than into a filter panel.

**[OBSERVED]** Search is a single free-text field, `search_placeholder` = "Find an event",
with `recent_searches` = "Recent searches" and empty state `before_search` = "Your next
amazing live experience is here. All you need to do is search." Failure state:
`empty_search_result` = "We can't find anything matching '{{term}}'." A newer key
`search_placeholder_new` = "Get answers" exists.

**[OBSERVED]** Search is registered as a sitewide `SearchAction` in JSON-LD, with **both** a
web and an app target:
```json
"target":"https://dice.fm/search?query={search_term_string}"
"target":"android-app://fm.dice/dice/open/search?query={search_term_string}"
```

**[INFERRED]** `search_placeholder_new` = "Get answers" suggests an in-flight move from
keyword search to a question-answering/assistant surface. Not confirmed live.

### 1.4 Editorial collections ("bundles")

**[OBSERVED]** `https://dice.fm/bundles/london-club-nights-dw8g` renders with the eyebrow
**"Collection"** above the title **"London Club Nights"**. Sibling collections exist at
`/bundles/club-nights-in-london-7av6`, `/bundles/club-events-london-ve3d`,
`/bundles/live-events-in-london-o56m`.

**[INFERRED]** These are the curatorial voice made navigable. They give DICE a
human-authored middle layer between "algorithm" and "search" — the same job a good record
shop's staff-picks shelf does. Critically they are *routes*, so they are shareable, SEO-
addressable, and linkable from social.

### 1.5 Layout: rails vs grids, and information density

**[OBSERVED]** The vertical grid (`styles__Grid-sc-8bbf38d2-0`), verbatim:

```css
width:100%;max-width:100%;display:grid;
grid-template-columns:repeat(1, minmax(0, 1fr));
gap:16px;grid-auto-flow:row dense;grid-auto-rows:auto;
@media (min-width: 420px){ gap:32px; grid-template-columns:repeat(2, minmax(0, 1fr)); }
@media (min-width: 768px){ grid-template-columns:repeat(3, minmax(0, 1fr)); }
@media (min-width: 992px){ grid-template-columns:repeat(4, minmax(0, 1fr)); }
```

So: **1 → 2 → 3 → 4 columns** at **420 / 768 / 992**, and the gutter **doubles from 16px to
32px** at the first breakpoint.

**[OBSERVED]** Page container (`Container-sc-56688052-0`):
`width:1182px;max-width:100%;margin:0 auto;padding:0 16px;` with
`transition:opacity 200ms ease-out;opacity:1;`.

**[OBSERVED]** The horizontal rail container (`styles__Container-sc-9f108ac5-0`):
```css
max-width:100%;margin:0 auto;padding:0;width:1182px;--gradient-width:62px;
@media (min-width:1278px) and (pointer:fine){ width:1278px; --gradient-width:22px; }
@media (pointer:fine){ padding:0 16px; }
```
and the scroller itself:
```css
width:100%;max-width:100%;display:flex;justify-content:flex-start;flex-wrap:nowrap;
overflow:auto;overscroll-behavior-x:contain;white-space:nowrap;flex:1;
padding-bottom:100px;margin-bottom:-100px;padding-left:16px;
```

**[INFERRED]** Three deliberate techniques here:
1. `padding-bottom:100px; margin-bottom:-100px` is the standard trick to let card
   focus rings / hover shadows overflow a scroller without being clipped, at zero layout cost.
2. `overscroll-behavior-x:contain` stops a horizontal rail swipe from triggering browser
   back-navigation — a real mobile bug class, pre-empted.
3. `--gradient-width` shrinking **62px → 22px** on large pointer-fine viewports means the
   edge fade that signals "more to scroll" is *large on touch* (where affordance must be
   obvious and there are no arrows) and *small on desktop* (where arrows/hover exist).
   The affordance is tuned to input modality, not to screen size alone.

**[OBSERVED]** No `scroll-snap-*` declarations exist anywhere in the browse page CSS.

**[INFERRED]** Free-scrolling rails, not snapping ones. This suits variable-width content and
avoids the "fighting the carousel" feel; it also implies rails are for *browsing past* things,
not for *stepping through* them.

### 1.6 Event card anatomy — exact

**[OBSERVED]** Complete rendered card, verbatim from
`https://dice.fm/browse/london-54d8a23438fe5d27d500001c` (whitespace collapsed):

```html
<a href="/event/g5bakb-nia-archives-emotional-world-tour-26th-nov-alexandra-palace-london-tickets"
   class="styles__EventCardLink-sc-3896cb2-5 hdmapg">
  <div class="styles__ImageWrapper-sc-3896cb2-2 byJFGm">
    <img srcSet="https://dice-media.imgix.net/attachments/2026-08-19/5db427c4-029c-4e47-b06a-6f502d3fe399.jpg?rect=417%2C0%2C1667%2C1667&auto=format%2Ccompress&q=80&w=204&h=204&fit=crop&crop=faces%2Ccenter&dpr=1 1x,
                 https://dice-media.imgix.net/attachments/2026-08-19/5db427c4-029c-4e47-b06a-6f502d3fe399.jpg?rect=417%2C0%2C1667%2C1667&auto=format%2Ccompress&q=40&w=204&h=204&fit=crop&crop=faces%2Ccenter&dpr=2 2x"
         src="https://dice-media.imgix.net/attachments/2026-08-19/5db427c4-029c-4e47-b06a-6f502d3fe399.jpg?rect=417%2C0%2C1667%2C1667&auto=format%2Ccompress&q=80&w=204&h=204&fit=crop&crop=faces%2Ccenter"
         alt="Nia Archives: Emotional World Tour" loading="lazy" width="100" height="100"
         class="styles__Image-sc-3896cb2-3 iYLZOP"/>
  </div>
  <div class="styles__EventDetails-sc-3896cb2-4 gyOEyX">
    <div class="styles__Title-sc-3896cb2-6 Ebrko">Nia Archives: Emotional World Tour</div>
    <div class="styles__DateText-sc-3896cb2-8 czhXUD">Thu 26 Nov</div>
    <div class="styles__Venue-sc-3896cb2-7 igHzZI">Alexandra Palace</div>
    <div class="styles__Price-sc-3896cb2-9 gCpsYf">From £39.22</div>
  </div>
</a>
```

**Four text fields. That is the entire card.** DOM order is **Title → Date → Venue → Price**.

**[OBSERVED]** Exact CSS for each part:

| Component | Declarations (verbatim) |
|---|---|
| `EventCardLink` | `display:inline-block;width:100%;overflow:hidden;overflow-wrap:anywhere;` · `@media (max-width:419px){display:flex;flex-direction:row;}` · `:hover{text-decoration:none}` · `:focus-visible{outline:none;border-radius:8px;box-shadow:0 0 0px 4px #000,0 0 0px 6px var(--brand-yellow);}` |
| `ImageWrapper` | `position:relative;margin-bottom:8px;` · `@media (max-width:419px){flex-shrink:0;width:96px;margin-right:12px;}` |
| `Image` | `display:block;width:100%;height:auto;border:0;border-radius:8px;object-fit:cover;background-color:#111;` |
| `EventDetails` | `line-height:1.25;` |
| `Title` | `font-size:16px;margin-bottom:4px;` |
| `DateText` | `margin-bottom:2px;font-size:14px;color:var(--brand-yellow);` |
| `Venue` | `margin-bottom:2px;font-size:14px;` |
| `Price` | `font-size:14px;` |
| `Actions` | `display:flex;padding:8px;justify-content:flex-end;align-items:flex-end;` · overlay variant: `width:100%;aspect-ratio:1/1;position:absolute;top:0;left:0;right:0;z-index:1;pointer-events:none;` |
| `SEventAddToInterests` | `width:30px!important;height:30px!important;` |

**Key reads:**
- **[OBSERVED]** Below **420px the card flips from stacked to a horizontal row** with a
  **96px** thumbnail and **12px** gap. Same component, two layouts, one breakpoint.
- **[OBSERVED]** The **date is the only coloured text** on the card
  (`var(--brand-yellow)` = `#f2ef1d`). Title, venue and price are default foreground.
- **[OBSERVED]** The save/interest control is a **30×30** button in an absolutely positioned
  **1:1 overlay** pinned to the image, `pointer-events:none` on the container so only the
  button itself is hittable.
- **[OBSERVED]** The focus ring is a **double ring**: 4px black then 2px brand yellow —
  guaranteed contrast against both the dark UI and any artwork.
- **[INFERRED]** `overflow-wrap:anywhere` on the link is defensive: promoter-supplied event
  titles contain long unbroken strings (hashtags, "B2B" chains, URLs) and this prevents a
  single title from blowing out a grid column.
- **[INFERRED]** Field order Title → **Date** → Venue → Price, with date accented, encodes
  DICE's actual hypothesis about nightlife intent: *what* it is, then *when* (the binding
  constraint — you can only be in one place on a Thursday), then *where*, then *how much*.
  Price is deliberately last and unaccented.

### 1.7 Information density

**[INFERRED]** Density is *low by ticketing standards and high by editorial standards*: a
1:1 image plus four short lines at 16/14/14/14px, in a 4-up grid inside a 1182px container
(≈264px column at 4-up). There are no badges, no genre tags, no "X tickets left" counters, no
promoter logos, no star ratings on the card. Everything that could be there and isn't is a
deliberate omission — the card is a *poster with a caption*, and the poster is doing the
persuading.

---

## 2. IMAGERY — the core of this research

### 2.1 Why DICE's imagery feels premium and consistent — the mechanism, proved

DICE does **not** rely on uploader discipline, art direction, or CSS `object-fit` to make
mismatched artwork look coherent. It runs a **deterministic three-stage normalisation**, and
every stage is visible in the URL.

#### Stage 1 — every source is centre-cropped to a **square master**

The imgix `rect=x,y,w,h` parameter is an explicit source-pixel crop. Across every asset type
observed (event artwork, artist images, venue images), `rect` resolves to a centred square:

| Observed `rect` | Implied source | Centring check | Context |
|---|---|---|---|
| `rect=417,0,1667,1667` | 2501 × 1667 | (2501−1667)/2 = **417** ✓ | Nia Archives event card |
| `rect=342,0,1365,1365` | 2049 × 1365 | (2049−1365)/2 = **342** ✓ | event artwork |
| `rect=712,0,2832,2832` | 4256 × 2832 | (4256−2832)/2 = **712** ✓ | event artwork |
| `rect=2923,0,4474,4474` | 10320 × 4474 | (10320−4474)/2 = **2923** ✓ | Jamie T artist image |
| `rect=0,46,549,549` | 549 × 641 (portrait) | (641−549)/2 = **46** ✓ | Cannelle artist image |
| `rect=0,0,1350,1350` | 1350 × 1350 | already square, no-op | Games Night artwork |
| `rect=0,0,768,768` / `0,0,1080,1080` / `0,0,1254,1254` / `0,0,640,640` / `0,0,512,512` / `0,0,800,800` / `0,0,400,400` / `0,0,2889,2889` | square masters | no-op | across pages |

**[OBSERVED]** Sources of every conceivable shape — 6.2:1 ultrawide (10320×4474), 3:2 landscape,
portrait — all collapse to a centred square. **[INFERRED]** The offset is always exactly
`(long−short)/2`, so this is computed server-side, not chosen by a human.

#### Stage 2 — three canonical crops are derived from that square, all centre-anchored

For one event (`aad83f9e-074f-437c-b4e3-825249defd78.jpg`, master 1350×1350) the JSON-LD
`image` array publishes **exactly three** crops, in this order
(`https://dice.fm/event/xedma3-games-night-30th-apr-moot-club-london-tickets`):

```
1. ?rect=0%2C270%2C1350%2C810    → 1350×810  = 5:3   (1.667)  landscape
2. ?rect=304%2C0%2C743%2C1350    → 743×1350  = 0.550 (≈11:20) portrait
3. ?rect=0%2C0%2C1350%2C1350     → 1350×1350 = 1:1            square
```

Both derived crops are **perfectly centred on the master**:
- landscape: y-offset 270 = (1350 − 810)/2 ✓
- portrait: x-offset 304 = (1350 − 743)/2 ≈ 303.5 ✓

The same three ratios reproduce across every master size observed:

| Master | 1:1 | 5:3 landscape (ratio, offset check) | 0.55 portrait (ratio, offset check) |
|---|---|---|---|
| 1350 | `0,0,1350,1350` | `0,270,1350,810` → 0.600, (1350−810)/2=270 ✓ | `304,0,743,1350` → 0.5504, (1350−743)/2≈304 ✓ |
| 1254 | `0,0,1254,1254` | `0,251,1254,752` → 0.5997, (1254−752)/2=251 ✓ | `282,0,690,1254` → 0.5502, (1254−690)/2=282 ✓ |
| 1080 | `0,0,1080,1080` | `0,216,1080,648` → 0.600, (1080−648)/2=216 ✓ | `243,0,594,1080` → 0.550, (1080−594)/2=243 ✓ |
| 768 | `0,0,768,768` | `0,154,768,461` → 0.6003, (768−461)/2≈154 ✓ | `173,0,422,768` → 0.5495, (768−422)/2=173 ✓ |
| other | — | — | `507,0,586,1066` → 0.5497 ✓ · `540,0,1320,2400` → 0.550 ✓ · `506,0,1238,2250` → 0.5502 ✓ · `792,0,917,1667` → 0.550 ✓ |

**[OBSERVED]** The system is therefore: **1:1** (cards, hero, sidebar), **5:3 / 1.667**
(social + ambient background), **0.55 / ≈11:20** (tall/immersive, published in JSON-LD but not
used by any web CSS observed).

**[INFERRED]** The 0.55 portrait crop is almost certainly the **native app's full-bleed
hero**. 0.55 is very close to a phone viewport's aspect (iPhone 9:19.5 = 0.4615; 0.55 sits
between 9:16 = 0.5625 and that), and it is published in structured data alongside the two
crops the web demonstrably uses — so it is a first-class platform asset, not a web artefact.
Web and app are being fed from one crop contract.

#### Stage 3 — delivery is requested at the exact CSS box size, with a DPR quality ladder

**[OBSERVED]** Card request (verbatim params):
```
?rect=417,0,1667,1667&auto=format,compress&q=80&w=204&h=204&fit=crop&crop=faces,center&dpr=1   (1x)
?rect=417,0,1667,1667&auto=format,compress&q=40&w=204&h=204&fit=crop&crop=faces,center&dpr=2   (2x)
```
**[OBSERVED]** Event-detail / sidebar request: identical shape but `w=328&h=328`.

**[OBSERVED]** Social: `og:image` = `?rect=<5:3>&w=1300&h=630&auto=compress`;
`twitter:image:src` = `?rect=<5:3>&w=1300&h=600&auto=compress`.

**[OBSERVED]** Ambient page background: `?rect=<5:3>&w=200&q=1`.

Four things to name explicitly:

1. **[OBSERVED]** `q=80` at `dpr=1` but **`q=40` at `dpr=2`**. Quality is *halved* exactly
   where pixel count quadruples. **[INFERRED]** This holds the byte budget roughly flat
   across densities; JPEG artefacts at q=40 are perceptually invisible at 2× density, so
   they buy retina sharpness for free. This is a genuinely sophisticated trick most teams miss.
2. **[OBSERVED]** `auto=format,compress` — automatic WebP/AVIF negotiation plus lossless
   metadata stripping, on every single request.
3. **[OBSERVED]** `crop=faces,center` layered *on top of* the deterministic `rect`.
   **[INFERRED]** A two-pass strategy: `rect` guarantees the *shape* is always right and
   always reproducible; `crop=faces` then nudges the *content* within that shape when a face
   is detected. Determinism first, intelligence second — so a face-detection miss degrades to
   a sane centre crop rather than to a broken one.
4. **[OBSERVED]** The requested sizes are **204** and **328** px, and the CSS box they land in
   is `max-width:328px` for the event sidebar (`EventDetailsLayout__StickySidebar`) and a
   ~264px grid column at 4-up. **[INFERRED]** The CDN request width is pinned to the layout,
   not to a generic ladder — image pipeline and design system are the same artefact.

#### The answer, stated plainly

**[INFERRED]** DICE's imagery reads as premium and consistent because of five compounding
decisions, in order of contribution:

1. **One shape, enforced.** Every card, hero and thumbnail is **1:1**. Nothing in the grid is
   ever a different shape, so the eye reads a *rhythm* rather than a *collage*. Poster art,
   band photos, club flyers and DJ portraits all arrive as squares.
2. **The crop is deterministic and centred, so it is never "wrong" in an interesting way.**
   A centre crop is rarely the *best* crop but it is never a *surprising* one. Consistency of
   error beats occasional brilliance at grid scale.
3. **The image slot is pre-painted `background-color:#111`.** **[OBSERVED]** on
   `styles__Image`. There is no white flash, no layout shift, and any transparency or
   letterboxing dissolves into the dark UI instead of announcing itself.
4. **Intrinsic `width="100" height="100"` attributes** are set even though the image renders
   at 204/264px. **[INFERRED]** These exist purely to reserve a square box at parse time and
   eliminate cumulative layout shift as `loading="lazy"` images arrive.
5. **The chrome around the image is nearly weightless** — an 8px radius, 8px of separation
   from the text, four short lines of 14–16px type, no badges. The artwork is the loudest
   thing in the cell by a wide margin, which is what makes a wall of mismatched artwork read
   as *curation* rather than *clutter*.

The lesson is counter-intuitive: DICE's imagery feels art-directed **because it is not
art-directed at all**. It is mechanically normalised, and the design system then gets out of
the way.

### 2.2 Radius, geometry, spacing

**[OBSERVED]** Radius scale in use: `8px` (card image, focus ring), `10px` (event hero image;
sticky CTA sheet, as `10px 10px 0 0`), `20px` (primary button — pill on a 40px control),
`6px`, `40px`, `100px`, `100%`/`50%` (avatars, dots). Counts on browse+event pages:
`8px`×12, `20px`×12, `6px`×6, `40px`×6, `10px`×4, `100px`×4.

**[INFERRED]** Two radii carry almost all the visual identity: **8px on grid imagery, 10px on
hero/sheet surfaces**. It is a *soft-but-not-rounded* language — noticeably squarer than the
16–24px that dominates current consumer app design. **[INFERRED]** This reads as
print/poster-derived rather than app-derived, which is consistent with a brand whose whole
metaphor is gig posters and flyers.

**[OBSERVED]** Spacing rhythm: card image→text `8px`; title→date `4px`; date→venue `2px`;
venue→price `2px`; grid gap `16px` → `32px` at ≥420px; container padding `0 16px`.

**[INFERRED]** A tight 2/4/8 micro-scale inside the card, a generous 16/32 macro-scale
between cards. This is what makes each card read as a single dense object with real air
around it — the classic editorial move.

### 2.3 Hero treatment on the event page

**[OBSERVED]** `EventDetailsImage__Container`:
`aspect-ratio:1/1;margin:0 16px;position:relative;` → `@media (min-width:768px){margin:0;}`
**[OBSERVED]** `EventDetailsImage__Image`:
`display:block;width:100%;height:auto;aspect-ratio:1/1;border-radius:10px;`
**[OBSERVED]** `EventDetailsImage__Actions`:
`position:absolute;bottom:16px;right:16px;display:flex;`

**[OBSERVED] The hero is square and inset, not edge-to-edge.** On mobile it sits inside a
16px margin with a 10px radius.

**[INFERRED]** This is a significant and deliberate departure from the prevailing pattern
(full-bleed hero bleeding under the status bar). An inset, rounded square reads as **an
object you could hold — a record sleeve or a flyer** — rather than as a background. It also
sidesteps every full-bleed failure mode at once: no text-legibility gradient is needed, no
safe-area collision, no crop surprises at unusual viewport ratios, and the same asset works
identically on a 4:3 tablet.

### 2.4 The ambient background glow

**[OBSERVED]** `EventBackground__Background`, verbatim:
```css
position:absolute;top:-100px;left:-100px;right:-100px;height:550px;
background:center/cover url(https://dice-media.imgix.net/attachments/2026-04-20/aad83f9e-...jpg?rect=0%2C270%2C1350%2C810&w=200&q=1);
filter:blur(18px);opacity:0.4;pointer-events:none;
@media (min-width:768px){ filter:blur(50px);height:1000px; }
```
**[OBSERVED]** `EventBackground__BackgroundWrapper`:
```css
position:absolute;top:0;left:0;right:0;height:400px;overflow:hidden;z-index:0;max-height:100vh;
@media (min-width:768px){ height:900px; }
@media (max-width:767px){ display:none; }
```

**[OBSERVED]** The source for the glow is the **5:3 crop requested at `w=200&q=1`** — a
~200px-wide, quality-**1** JPEG. **[OBSERVED]** It is **desktop-only** (wrapper is
`display:none` below 768px). Blur is `18px` at base and `50px` at ≥768px; opacity `0.4`; the
element is inset `-100px` on three sides so no blurred edge is visible.

**[INFERRED]** This is the highest-leverage premium cue on the whole site and it costs
roughly **2–4 KB**. At `q=1` and 200px wide, the file is essentially a colour field — which is
all a 50px blur needs. The effect is that *every event page is tinted by its own artwork*, so
a Nia Archives page and a Trivium page feel like different rooms while sharing one layout.
It is "dynamic theming" achieved with no colour extraction, no palette API, and no runtime
canvas work. The `-100px` inset and `max-height:100vh` clamp are the details that keep it
from ever looking like a bug.

**[INFERRED]** Suppressing it on mobile is a considered trade: on a phone the hero image
already dominates the viewport, so the glow would add cost (a second image request, a
compositing layer, GPU blur) for almost no visible gain.

### 2.5 Loading behaviour, placeholders, video

**[OBSERVED]** `loading="lazy"` appears **31 times** on the browse page; every event card
image carries it, plus explicit `width="100" height="100"` and `srcSet` with `1x`/`2x`
descriptors. No `sizes` attribute is used for content images (the only `sizes` values present
are favicon/apple-touch-icon declarations: `16x16`, `32x32`, `57x57`, `60x60`, `72x72`,
`76x76`, `96x96`, `144x144`, `152x152`, `180x180`, `192x192`).

**[INFERRED]** Because the delivered width is pinned exactly (`w=204`), `sizes` is unnecessary
— DICE has replaced responsive-image negotiation with a fixed contract. Simpler, and it makes
CDN caching far more effective (a small, finite set of URLs across the whole catalogue).

**[OBSERVED]** No blur-up / LQIP placeholder is used on cards. The placeholder is the flat
`background-color:#111` on `styles__Image`.

**[OBSERVED]** Event payloads carry a `previews` array with two media types. From
`https://dice.fm/event/g5bakb-nia-archives-emotional-world-tour-...`:
```json
"previews":[
 {"type":"spotify","title":"Nia Archives - Forbidden Feelingz",
  "preview_url":"https://p.scdn.co/mp3-preview/a371b685306edb1dca79ff206cf86f51b48d64c1?cid=...",
  "track_name":"Forbidden Feelingz",
  "redirect_url":"https://open.spotify.com/track/0wrs5ucXutScEWOhdWdGBB"},
 {"type":"trailer",
  "preview_url":"https://stream.mux.com/Axzsl00SnwbYkABT8ucAr4cugjzJ00Ytc42Mp00PV7101jA.m3u8"}
]
```
**[OBSERVED]** Video is delivered as **Mux HLS** (`.m3u8`); audio previews come from Spotify's
30s preview CDN. Marketing video on dice.fm is plain MP4 off the same imgix host
(`https://dice-media.imgix.net/videos/*.mp4`).

**[INFERRED]** Video is **event-optional supplementary media**, never the card and never the
hero. The card is always a still square. This is why the grid stays calm — DICE never lets a
rail become a wall of autoplaying video.

---

## 3. TYPOGRAPHY

### 3.1 Families

**[OBSERVED]** Self-hosted from `https://dice.fm/static/fonts/`, `.woff2` + `.woff`:

```
ABCFavorit-Light / LightItalic
ABCFavorit-Book / BookItalic
ABCFavorit-Medium / MediumItalic
ABCFavorit-Bold / BoldItalic
ABCFavorit-Mono
```
**[OBSERVED]** Declared families: `'Favorit'`, `'Favorit',Helvetica,Arial,sans-serif`,
`Favorit,sans-serif!important`, `'Favorit Mono'`, and a display face `'Foggy'`.

**[INFERRED]** **ABC Favorit** (Dinamo) is a licensed, opinionated grotesk with distinctly
narrow, slightly quirky letterforms — not a system font, not Inter, not Helvetica. Shipping
five weights plus a mono cut plus a separate display face `Foggy` is a substantial type
investment. **[INFERRED]** A large share of DICE's "premium" perception is simply that the
typeface is unmistakable and consistent, on a site where the imagery is otherwise
uncontrollable. When you cannot control the pictures, controlling the letters is how you own
the page.

### 3.2 Scale (measured frequency, event page)

**[OBSERVED]** `16px`×20 · `13px`×18 · `28px`×10 · `20px`×10 · `14px`×10 · `11px`×10 ·
`24px`×6 · `18px`×6 · `15px`×6 · `17px`×4 · `12px`×4 · `64px`×2 · `35px`×2.

**[INFERRED]** Effective scale: **11 / 12 / 13 / 14 / 15 / 16 / 17 / 18 / 20 / 24 / 28 / 35 / 64**.
Dense at the small end (11–18), sparse at the top — typical of a UI that is mostly metadata
with a few display moments.

### 3.3 Weight, line-height, letter-spacing, case

**[OBSERVED]** Weight frequency: `normal`×52 · `bold`×12 · `350`×10 · `700`×4 · `500`×4 ·
`300`×4 · `400`×2.
**[OBSERVED]** Line-height: **`120%`×64** (overwhelmingly dominant) · `130%`×10 · `140%`×4 ·
`1.25` (card details) · pixel values `16/17/19/20/21/24/25/34/42px`.
**[OBSERVED]** Letter-spacing: **`0.02em`×30** · `0.01em`×14 · `0.06em`×8 · `normal`×4.
**[OBSERVED]** `text-transform`: `uppercase`×6 · `none`×4 · `capitalize`×2.

**[INFERRED]** Three rules carry the voice:
- **`line-height:120%` is the house default.** Tight for body text, but correct for a UI made
  of 1–3 line labels. It makes stacked metadata read as a compact block.
- **`letter-spacing:0.02em` is applied almost everywhere**, including body-size text. Favorit
  is a narrow grotesk; a small positive track counteracts that and is a large part of the
  "expensive" feel.
- **`font-weight:350`** appears — a variable/optical weight between Light (300) and Book
  (400). **[INFERRED]** Evidence of genuine type-design care rather than a stock 400/700 pair.

**[OBSERVED]** Uppercase is *restricted to buttons*, not headings:
`EventDetailsCallToAction__ActionButton` has `text-transform:uppercase` with `font-size:12px;
line-height:16px;font-weight:bold;` and `letter-spacing` from the 0.06em bucket.

### 3.4 Title treatment — the notable choice

**[OBSERVED]** `EventDetailsTitle__Title`:
```css
font-weight:normal;font-size:35px;line-height:42px;margin:8px 0;word-break:break-word;
```

**The event title is 35px/42px at weight NORMAL.** Not bold. Not uppercase. `line-height` is
exactly 1.2.

**[INFERRED]** This is the most distinctive typographic decision on the site. Nearly every
competitor sets event titles bold. Setting a 35px display line at book weight in a
characterful grotesk reads as *editorial/print* (a magazine standfirst) rather than
*commercial* (a product page). It also, crucially, **lets the artwork stay the loudest element
on the page** — a bold 35px title would compete with the square hero directly above it.
`word-break:break-word` is again defensive against promoter-supplied titles.

### 3.5 Metadata, date and price hierarchy

**[OBSERVED]** Event page title block:

| Element | Mobile | ≥768px | Colour |
|---|---|---|---|
| `Title` | 35px / 42px, weight normal | (unchanged) | default |
| `Date` | 17px / 21px, ls 0.02em, weight normal, `margin:4px 0` | 24px / 120% | **`var(--brand-yellow)`** |
| `Venues` | 17px / 21px, ls 0.02em, weight normal, `margin:4px 0` | 24px / 120% | default |
| `Tags` | 15px / 20px, ls 0.02em, weight normal, `text-transform:capitalize` | 18px / 120% | default |
| `Highlights` | 13px / 120% / ls 0.02em | 16px / 120% | `rgba(255,255,255,0.66)` |

**[OBSERVED]** Price in the CTA (`EventDetailsCallToAction__Price`):
```css
display:flex;flex-direction:column;font-size:24px;line-height:120%;font-weight:bold;
color:rgba(255,255,255,0.66);
```

**[INFERRED] The price is the only bold thing in the content hierarchy — and it is
deliberately dimmed to 66% opacity.** DICE gives price *weight* (so it is findable and
scannable) but denies it *contrast* (so it does not dominate). Combined with the title being
book-weight and the date being the only accent colour, the intended reading order is
unambiguous: **artwork → title → when → where → how much**. Price is answered, never sold.

**[OBSERVED]** Date format token: `"date": "{{date, ddd D MMM — HH:mm}}"`; rendered on cards
as **"Thu 26 Nov"**. **[OBSERVED]** Colour tokens defined: `--brand-yellow:#f2ef1d` (16
usages — by far the most-used token), `--brand-green:#4BFA94`, `--blue:#0000FE`,
`--blue-light:#24AFEE`, `--green:#00D8AF`, `--purple-light:#A783FF`,
`--lightest-gray:#f9f9f9`, `--white-semi-transparent:rgba(255,255,255,0.66)`.

**[INFERRED]** `#f2ef1d` acid yellow on near-black, used *only* for dates and focus rings, is
the entire colour strategy. One accent, one job. `rgba(255,255,255,0.66)` is the standard
secondary-text token and is used for price, highlights and helper copy alike.

---

## 4. EVENT PAGE

Reference: `https://dice.fm/event/xedma3-games-night-30th-apr-moot-club-london-tickets`,
`.../g5bakb-nia-archives-emotional-world-tour-26th-nov-alexandra-palace-london-tickets`,
`.../3obowp-jamie-t-12th-dec-olympia-london-london-tickets`.

### 4.1 Section order

**[OBSERVED]** Rendered heading sequence, in order:
> **{Event title}** → **About** → **Lineup** → **Venue** → **{Venue name}** → **FAQs** →
> **Download the DICE app**

**[OBSERVED]** Component tree (styled-components names, verbatim):
`EventBackground__BackgroundWrapper` · `EventDetailsLayout__Container` ·
`EventDetailsLayout__Columns` · `EventDetailsLayout__Content` ·
`EventDetailsLayout__StickySidebar` · `EventDetailsImage__{Container,Image,Actions}` ·
`EventDetailsTitle__{Container,Title,Date,Venues,Tags,Tag}` ·
`EventDetailsBase__{Highlights,Highlight,HR}` ·
`EventDetailsCallToAction__{Container,PriceRow,Price,ActionButton}` ·
`EventDetailsAbout__{Container,Text}` ·
`EventDetailsLineup__{Container,Lineup,LineupLine,PerformingTime,SectionTitle,LineupSectionImage}` ·
`EventDetailsVenue__{Container,Image,Info,Address,OpenInMaps,VenueButtons,SVenueFollow}` ·
`EventDetailsFAQ__Container` · `EventDetailsExpandableFAQs__{Summary,Details,Body,StyledChevron}` ·
`EventDetailsGotCode__Container` · `EventDetailsShare__{Container,Wrapper}` ·
`EventAddToInterests__Container` · `FollowButton__{Container,STooltip}` ·
`DownloadTheApp__{Container,Features,Feature,FeatureText,FeaturesHeader,SDiceAppIcon}`.

### 4.2 Layout

**[OBSERVED]** `EventDetailsLayout__Columns`: `@media (min-width:768px){display:flex;
align-items:flex-start;}` — single column below 768px, two columns above.
**[OBSERVED]** `EventDetailsLayout__StickySidebar`:
```css
margin-bottom:32px;
@media (min-width:768px){ flex:1;max-width:328px;position:sticky;z-index:1;top:88px;align-self:start; }
@media (min-width:992px){ top:112px; }
```

**[INFERRED]** The `max-width:328px` sidebar is exactly the `w=328&h=328` image request seen
in §2.1 — layout and CDN contract are literally the same number. The sticky offset stepping
88px → 112px tracks a taller header at ≥992px.

### 4.3 The CTA — dual-mode, and this is the interesting part

**[OBSERVED]** `EventDetailsCallToAction__Container`:
```css
--safe-bottom:env(safe-area-inset-bottom);
padding-bottom:env(safe-area-inset-bottom);
background-color:#1a1a1a;border-radius:10px;
@media (max-width:600px){
  border-radius:10px 10px 0 0;position:fixed;z-index:10;width:100%;bottom:0;margin-bottom:0!important;
}
```
**[OBSERVED]** `EventDetailsCallToAction__PriceRow`: `padding:16px 24px;display:flex;gap:8px;align-items:center;`
**[OBSERVED]** `EventDetailsCallToAction__ActionButton`:
```css
box-sizing:border-box;border:2px solid transparent;text-transform:uppercase;outline:none;
cursor:pointer;height:40px;padding:0 22px;border-radius:20px;color:#000;background-color:#fff;
font-size:12px;line-height:16px;font-weight:bold;display:flex;align-items:center;
justify-content:center;transition:opacity 200ms;
```

**[OBSERVED]** The **same component** is a rounded card in a sticky sidebar on desktop and a
**fixed bottom sheet** below 600px, with the top corners rounded (`10px 10px 0 0`), a
`#1a1a1a` raised surface against the near-black page, and `env(safe-area-inset-bottom)`
respected.

**[INFERRED]** One CTA component, two presentations, no duplicate implementation. The mobile
sheet is a *panel with price and button side by side* (`PriceRow` is a flex row with an 8px
gap), not a full-width button — so the price is always co-located with the action and can
never be scrolled away from it.

### 4.4 CTA states (from the shipped dictionary)

**[OBSERVED]**
```
cta.book_now      = "Buy now"        cost.single        = "Buy Now"
cta.unlock        = "Unlock"         cost.ticket_type   = "From {{cost}}"
cta.remind_me     = "Remind me"      cost.free          = "Free"
cta.reminder_set  = "Reminder set"   cost.from          = "From"
cta.off_sale      = "Off sale"       cost.waiting_list  = "Join wait list"
cta.postponed     = "Postponed"      cost.competition   = "Competition"
cta.cancelled     = "Cancelled"      cost.remind_me     = "Remind me"
status.waiting_list = "Wait list"    event_status_waiting_list = "Wait list"
sold_out = "Sold out"                sold_out_online = "Sold out online"
```
**[OBSERVED]** `we_remind_you_copy` = "This event goes on sale on the {{date}}. If you want,
we can remind you just before."

**[INFERRED]** The CTA is a **state machine with ~9 named states**, and — critically — there
is **no dead end**. Off sale → "Remind me". Sold out → "Join wait list". Locked → "Unlock".
Not-yet-on-sale → "Remind me". Every state converts into either a purchase or a captured
intent signal. There is no state in which the button simply says "unavailable".

### 4.5 Lineup, venue, media, social proof, related

**[OBSERVED]** Lineup is structured data, not prose. From the Nia Archives payload:
```json
"summary_lineup":{"top_artists":[
  {"name":"Trick Pony","image":{"url":"https://dice-i-scdn-co.imgix.net/image/45846..."},"artist_id":"143670","is_headliner":false},
  {"name":"NEW YORK","image":{"url":"...?rect=0%2C0%2C640%2C640"},"artist_id":"101679","is_headliner":false},
  {"name":"Cannelle","image":{"url":"...?rect=0%2C46%2C549%2C549"},"artist_id":"...","is_headliner":false}
 ],"total_artists":N,"total_free_texts":0}
```
with `is_headliner` flags, per-artist images (same square-crop contract), and
`EventDetailsLineup__PerformingTime` for set times. **[OBSERVED]** `LineupSectionImage` is
`height:26px;width:1px;margin:13px 25px;background:rgba(255,255,255,0.2)` — i.e. a **1px
vertical hairline divider**, not an image.

**[OBSERVED]** Venue block carries structured address, geo, an image, `OpenInMaps`, a follow
button, and accessibility metadata:
```json
"venues":[{"id":"179","name":"Alexandra Palace",
 "address":"Alexandra Palace, Alexandra Palace Way, London N22 7AY",
 "location":{"lat":51.5941783,"lng":-0.130773299999987},
 "image":{"url":"...?rect=0%2C0%2C512%2C512"},
 "city":{"id":"54d8a23438fe5d27d500001c","name":"London","country_code":"GB"},
 "perm_name":"alexandra-palace-j7v7",
 "accessibility":{"url":"https://www.alexandrapalace.com/visitor-information/ticketing/"},
 "highlights":[{"type":"accessibility","title":"Accessibility information","external_link":"..."}],
 "space_name":"Alexandra Palace Great Hall","doors_open_date":"2026-11-26T18:30:00+00:00"}]
```

**[OBSERVED]** Timeline is a typed section list, e.g.
`{"type":"section_header","time":"...T22:30:00+01:00","title":"Event ends"}` and a
`"Last Entry"` entry; labels `doors_open` = "Doors open", `doors_close` = "Event ends".

**[OBSERVED]** Full event dates object:
```json
"dates":{"timezone":"Europe/London","announcement_date":"2026-04-15T13:00:00+01:00",
"sale_start_date":"2026-04-16T19:00:00+01:00","sale_end_date":"2026-04-30T22:00:00+01:00",
"event_start_date":"2026-04-30T19:30:00+01:00","event_end_date":"2026-04-30T22:30:00+01:00",
"pre_sale_start_date":null,"is_multi_days_event":false}
```
**[OBSERVED]** Also present: `"presented_by":"Presented by The Scene."`, `"max_tickets":10`,
`"has_multiple_ticket_types":true|false`, `"is_fully_locked":false`,
`"acquisition_type":"purchase"`, `"attendance_type":"live_only"`, `"seating":null`,
`"seats_io_event_id":null`, `"offers_extras":false`, `"status":"on-sale"`,
`"secondary_status":null`, and an undocumented `"unicorn":true` flag.

**[OBSERVED]** Sharing uses branded short links per intent:
`"social_links":{"event_share":"https://link.dice.fm/D1a0c90d6957?dice_id=...",
"post_purchase_referral":"https://link.dice.fm/W1aee91d0bb2?dice_id=...",
"post_competition_referral":"...","post_purchase_extras_available_referral":"..."}`.

**[INFERRED]** Distinct referral links for *pre-purchase share* vs *post-purchase share* vs
*post-competition* means DICE measures word-of-mouth by moment, and can weight a share that
happens *after* someone commits money differently from a browse-share. That is a strong
signal design.

**[OBSERVED]** No user reviews, ratings, star scores or attendee counts appear anywhere on
an event page. **[INFERRED]** Social proof is carried entirely by *lineup*, *venue* and
*"Presented by"* — i.e. by institutional credibility, not by crowd metrics. For nightlife this
is the correct instinct: who is playing and where is the proof.

**[OBSERVED]** Related discovery on an event page is limited to lineup/venue links plus
`suggested_artists_heading` = "Suggested artists to follow". No "you might also like" event
rail was observed on the event page itself.

**[INFERRED]** DICE does not cross-sell competing events on a page where you are close to
converting. Related discovery is deferred to the confirmation and feed.

### 4.6 Waiting-list presentation

**[OBSERVED]** The wait list is presented as a *feature*, with an explicit expectation-setting
screen (`waiting_list_confirmation_screen_*`):
> Title: "You're on the wait list,\nnow you need the app" (v2: "You're on the wait list, \nnow get the app")
> 1. "We'll let you know if tickets become available"
> 2. "You'll have a brief window to buy them"
> 3. "If you miss your chance, rejoin at the top"
> 3-v2. "Turn on your notifications to make sure you hear about available tickets in time"
> 4. "You can change the number of tickets you want"

**[OBSERVED]** Other wait-list strings:
`waiting_list_badge_remaining` = "%s left";
`waiting_for_tickets_web_one` = "You're currently waiting for %s ticket. If you're offered
tickets, you'll need the DICE app to buy them.";
`checkout_partial_wait_list_allocation_message_other` = "Only need %d tickets? All good, the
rest will go to the next fan on the wait list";
`return_to_waiting_list_sheet_footnote` = "You'll lose refund protection on any tickets that
sell on the wait list";
`event_tickets_available_on_door_wl` = "There will be tickets available at the door. Or join
the wait list to try to get some from fans who can't go.";
`leave_waiting_list_button_title` = "Leave the wait list"; `on_the_waitlist` = "On the wait list".

**[INFERRED]** Four things make this excellent: (a) it names the *mechanic* honestly including
the downside ("brief window", "rejoin at the top"); (b) it converts a sold-out dead end into
an owned, revisitable state; (c) `"%s left"` reintroduces scarcity *inside* the wait list;
(d) the partial-allocation copy reframes taking fewer tickets as pro-social ("the rest will go
to the next fan") rather than as a compromise. That last line is a masterclass.

---

## 5. CHECKOUT

Caveat: **[OBSERVED]** purchase completion is app-gated — `purchase_waitinglist_tickets` =
"If you're offered tickets, you'll need the DICE app to buy them." Evidence below is
primarily from the shipped dictionary.

### 5.1 Fee transparency — the headline finding

**[OBSERVED]** A full-text search of the fan-facing dictionary (~1,328 keys) for `fee`
returns **no booking-fee, service-fee or service-charge string of any kind**. The only `fee`
matches are the substring in "feed", "feeling" and "feedback".

**[OBSERVED]** The pricing promise string is:
> `price_youll_pay` = **"The price you'll pay. No surprises later."**

**[OBSERVED]** Prices surfaced on cards and in `og:title` are all-in and consequently *not*
round numbers:
- `og:title` = "Nia Archives: Emotional World Tour Tickets | **From £39.22** | 26 Nov @ Alexandra Palace, London | DICE"
- `og:title` = "Jamie T  Tickets | **£59.35** | 12 Dec @ Olympia London, London | DICE"
- `og:title` = "Games Night Tickets | **From Free** | 30 Apr 2026 @ Moot Club, London | DICE"
- card body = "From £39.22"

**[OBSERVED]** The only breakdown lines that exist are tax, not fees: `tax` = "Tax",
`purchase_flow_us_tax_title` = "Tax included", `eur_purchase_tax` = "Includes VAT",
`total` = "Total", `ticket_price` = "Ticket price",
`purchase_flow_order_summary` = "Order summary".

**[INFERRED]** This is the deepest structural lesson in the whole study. DICE does not *build
trust by disclosing fees well* — it **removes the disclosure problem by folding fees into the
displayed price from the very first pixel**. A price of "£39.22" is self-evidently not a
marked-up round number; the odd figure is itself the proof that nothing is being added later.
Every competitor that shows "£35.00" then "+ £4.22 booking fee" at step 3 has, by
construction, a trust cliff. DICE has no such step, which is why its dictionary needs no word
for it.

### 5.2 Selector, quantity, CTA

**[OBSERVED]** `select_tickets` = "Select tickets"; `quantity_summary` = "{{count}} x
{{ticketType}}"; `quantity_summary_tickets` = "{{count}} tickets";
`ticket_selection_total` = "Total – %s".
**[OBSERVED]** The CTA carries the price inside the button label:
`checkout_with_price` = **"Checkout - {{price}}"**; `continue_price_button_title` = "Continue - %s".
**[OBSERVED]** `max_tickets: 10` in the event payload; `checkout_event_limit_banner` = "You
bought the max amount of tickets for this event."; `ticket_limit_reached` = "Ticket limit reached".
**[OBSERVED]** `a11y_purchase_flow_step_title` = "Step %d of %d".

**[INFERRED]** Price-in-button is the same principle as §5.1 restated at the moment of
commitment: the number you are agreeing to is *on the thing you press*, so there is no
possible gap between intent and amount.

### 5.3 Price-change honesty

**[OBSERVED]**
```
price_increase_alert          = "The price for this show has now increased."
price_increase_alert_message  = "Those tickets sold out, so we moved you to the next best price range"
price_decrease_alert          = "Winner. These tickets are now cheaper!"
price_decrease_alert_message  = "Your tickets just got cheaper, lucky you"
price_changed_generic_message = "The ticket price changed"
price_changed_ticket_quantity = "We could only hold some of the tickets you selected"
price_discount_expired_alert  = "Sorry, that code's expired"
```
**[INFERRED]** DICE ships copy for the *price went down* case with genuine warmth ("Winner.",
"lucky you"). Most products only build the price-went-up path. Handling the favourable case as
a designed, celebrated moment is a cheap and very effective trust deposit.

### 5.4 Payment, extras, instalments, seating

**[OBSERVED]** `pay_with_apple_pay` = "Pay with Apple Pay"; `pay_with_google_pay`;
`pay_with_card`; `pay_with_another_card`; `pay_with_mb_way` (Portugal);
`add_payment_method_card_unsupported` = "Sorry, we don't take %s"; `remove_card` / `replace_card`.
**[OBSERVED]** Instalments: `pay_later_charged_on_date` = "Charged on %s";
`pay_later_view_your_reservation` = "View your reservation";
`pay_later_card_must_be_saved` = "Card needs to be saved to pay in instalments".
**[OBSERVED]** Refund protection is an explicit paid add-on step:
`purchase_flow_refund_protection_screen_title` = "Add refund protection";
`purchase_flow_refund_protection_include` = "Include it" / `..._not_include` = "Don't include it";
`purchase_panel_add_refund_protection_button` = "add" / `..._remove...` = "remove";
`purchase_flow_refund_protection_transfer_warning` = "Heads up, you can't send protected
tickets to friends".
**[OBSERVED]** Extras/merch: `addon_selection_action_button_title_add` = "Add";
`addon_selection_variant_cart_quantity` = "(%d in cart)";
`addon_selection_alert_sold_out_description` = "This item is now sold out";
`addon_selection_date_title` = "When:" / `addon_selection_location_title` = "Where:".
**[OBSERVED]** Seated events use seats.io (`seats_io_event_id`) with notably humane copy:
```
checkout_seating_best_available_title = "These are the best seats available in this section"
checkout_seating_best_available_body  = "We base this on price and how close they are to the stage."
checkout_seating_warning_orphaned_seats_alert_title = "There's a seat left all by itself"
checkout_seating_warning_orphaned_seats_alert_description =
  "We want more fans to be able to sit together, so please adjust your selection."
checkout_seating_split_seats_warning = "There aren't any seats left next to each other, but we
  picked out the best available. We need to assign them for this event."
checkout_seating_expired_title = "This session timed out"
checkout_seating_expired_body  = "We had to release these tickets."
checkout_seating_controls_prompt = "You can tap the map to change seats"   (desktop: "click")
```

**[INFERRED]** The orphaned-seat rule is enforced *and explained in fan-benefit terms*
("We want more fans to be able to sit together"), not in inventory terms. DICE consistently
justifies its constraints by naming who benefits — the same pattern as the wait-list
partial-allocation copy.

### 5.5 Confirmation

**[OBSERVED]**
```
confirmation_title            = "Here you go\n{{first_name}}"
confirmation_last_step        = "Last step: \nGet the app"
confirmation_app_notice       = "You'll need the DICE mobile app to access your ticket."
confirmation_keep_safe        = "To keep them safe from touts. This way, they don't appear on
                                 the secondary market and fans always pay the price they should."
event_purchase_confirmation_explain_price = "To keep tickets off the secondary market and in the
                                 hands of fans, they're stored securely in-app."
event_purchase_confirmation_explain_scan  = "You can quickly scan your ticket to enter the event"
event_purchase_confirmation_explain_music_services = "Connect your Spotify or Apple Music."
event_purchase_confirmation_scan_to_download_app   = "Scan to download"
purchase_confirmation_refund_protection_subtitle   = "& refund protection"
ticket_purchase_confirmation.autofollow_title = "And you're keeping up with what's next"
confirmation_title_waiting_list = "Wait list joined"
ticket_confirmation_waiting_list = "You're on the list!"
```
**[INFERRED]** The confirmation screen does three jobs at once: it confirms, it *justifies the
constraint* (app-only tickets, framed as anti-tout protection rather than as a lock-in), and it
harvests a taste signal (connect Spotify) at the highest-trust moment in the entire funnel —
right after money has changed hands. That sequencing is deliberate and smart.

---

## 6. TICKET

**[OBSERVED]** Credential model — from DICE's own partner copy
(`https://dice.fm/partners/ticketing/live`):
> "Download tickets as a PDF or copy a link to share. **Each QR code is single-use**"

**[OBSERVED]** From the dictionary:
```
ticket_details_howto_scannable_title = "How tickets work"
ticket_details_howto_scannable_entry_description = "At the venue, show your QR codes to be scanned in."
ticket_details_howto_scannable_activate_description =
  "They have QR codes that you'll be able to activate in the %s before the event."
ticket_details_option_activate_title = "You need to activate your tickets"
ticket_details_3rd_party_access_activate_ticket_title = "You need to activate your ticket in **%s**"
ticket_qr_code_3rd_party_access_description = "To activate your ticket, use %s."
ticket_details_howto_scannable_ticket_transfer_description =
  "Once activated, you won't be able to send them to a friend."
ticket_details_howto_box_office_entry_description = "Bring your ID as some venues require it for ticket collection."
ticket_details_howto_paper_tickets_entry_description = "At the venue, show your ticket to be scanned in."
ticket_id = "ID: …{{suffix}}"
stored_on_your_account = "Stored on your account"
upcoming_events = "Events you're going to"
view_ticket = "View ticket"
```

**[OBSERVED]** Three distinct entry modes are modelled as first-class variants: **scannable QR**,
**box office collection** (bring ID), and **paper tickets**.

**[OBSERVED]** Anti-tout framing on the credential itself:
```
access_qr_code_header = "Access your QR Code tickets"
access_qr_code_copy   = "DICE protects fans and artists from touts by storing tickets securely in the app"
access_qr_code_action = "Send me the app"
protect               = "DICE protects fans and artists from touts. Tickets will be securely stored in the app."
why_are_tickets_in_app = "Why are my tickets stored in-app?"
why_are_tickets_in_app_explain = "To keep them safe from touts. This way, tickets don't appear on
                                  the secondary market and fans always pay the price they should."
```

**[INFERRED]** The "activate before the event" step plus single-use QR is the mechanism behind
DICE's dynamic/secure-ticket reputation. **[INFERRED]** The activation gate is what makes
screenshots worthless: a static image of a pre-activation ticket does not scan, and activation
is bound to the account/device. Note the explicit trade-off DICE ships in copy — once
activated, transfer is disabled — meaning security and shareability are presented as an honest
either/or, not silently resolved.

**[OBSERVED]** Transfer:
```
ticket_transfer_on_dice_title      = "Contacts on DICE"
ticket_transfer_not_on_dice_title  = "Contacts not on DICE"
ticket_transfer_select_tickets_subtitle = "Which tickets do you want to send to %@?"
ticket_transfer_acknowledgement_checkbox_title = "I understand"
ticket_transfer_disabled_reason_sheet_title = "You can't send protected tickets"
ticket_transfer_disabled_reason_sheet_subtitle =
  "If you're going with a friend, you'll need to turn up to the venue together"
ticket_transfer_sheet_refund_protection_footnote =
  "Showing tickets without refund protection, as those are the only ones you can send"
tocket_transfer_disabled = "Ticket Transfer is disabled for this ticket"   [sic — typo in source]
get_the_app_to_transfer_ticket_other = "Get the app to transfer them"
need_to_send_your_ticket_other = "Need to send tickets?"
ticket_transfer_pending_waiting_list = "On the wait list"
```
**[INFERRED]** Transfer is **free, contact-based, and non-monetary** — you send a ticket to a
person, you never list it at a price. This is the structural anti-tout choice: the product
simply has no surface on which to name a resale price. The wait list absorbs the "I can't go"
case at face value instead.

**[OBSERVED]** Refunds and secondary supply:
```
event_details_refund_policy_cooling_off_title = "You can <0>get a refund</0> until 24 hours before the event starts, if:"
event_details_refund_policy_cooling_off_enabled_bullet_1 = "It's within 24 hours of buying tickets"
event_details_refund_policy_cooling_off_enabled_bullet_2 = "This event is rescheduled or cancelled"
event_details_refund_policy_event_start_time = "You can't get a refund within 24 hours of the event start time."
refunds_until = "Refunds can be requested until {{date}}."
refund_request_automated_confirmation_title = "Refund on the way"
refund_request_automated_confirmation_subtitle = "You'll get your money back in a few days.\nEasy."
refund_request_confirmation_title = "Sit tight"
refund_request_confirmation_message = "Our team will look into your request and get back to you asap."
refund_confirmation_snackbar_other = "Your %d tickets for %s aren't here anymore because your refund is processing ✨"
refund_account = "The refund will be processed automatically and returned to the account that you used to purchase the tickets."
```
plus structured reasons: "I've bought tickets by accident", "I've bought the wrong tickets",
"Event is cancelled or postponed", "Event is rescheduled and I can't make the new date",
"I've tested positive for COVID-19", "Other".
**[OBSERVED]** Machine-readable policy on the event: `"public_refund_policy":{"type":"cooling_off_enabled","hours":24}`.

**[OBSERVED]** Refund protection is an order-level object with its own sheet:
`refund_protection_order_sheet_reference_title` = "Booking reference";
`..._tickets_title` = "Tickets protected"; `..._expiration_title` = "Protection ends";
`..._description` = "You've got %s references because you placed %s orders. Your protection ends %s";
`..._footnote` = "Event cancelled or changed? **Contact DICE**".

**[OBSERVED]** Directions/venue actions: `EventDetailsVenue__OpenInMaps` component;
`doors_open` = "Doors open"; `doors_close` = "Event ends"; venue `location{lat,lng}` and
`accessibility.url` in payload.
**[OBSERVED]** Order/tax admin: `support_option_request_tax_invoice_title` = "Get a tax invoice";
`tax_invoice_form_toggle_title` = "I need a nominative invoice (NFI)";
`payment_query_vat_invoice_request` = "Request a VAT invoice"; `purchased_by` = "Purchased by".

**[OBSERVED]** No Apple Wallet / Google Wallet pass string was found in the dictionary.
**[INFERRED]** Consistent with the anti-tout model: exporting to a system wallet would produce
a transferable static credential and defeat activation.

---

## 7. NAVIGATION

**[OBSERVED]** Web header components: `HeaderDesktop__{Container,Toolbar,MenuLinksBlock,SearchButton}`,
`HeaderMobile__Toolbar`, `Header__Nav`, `MenuLinks__{Links,LinkText}`.
**[OBSERVED]** Primary web nav destinations (consistent across home, browse, event, venue):
`/browse` ("Browse events"), `/artists` ("Artists"), `/venues`, `/partners` ("Create events"),
`/help` ("Get help"), plus a search button and "Get the app".
**[OBSERVED]** Footer groups observed: About DICE, Careers, Press, Blog, Podcast, Playback,
Artist signing, FAQs, Get help, Privacy Policy, Purchase Terms, Cookie Settings, Android/iOS
download.
**[OBSERVED]** Sticky sidebar offsets imply header heights of **88px** (≥768px) and **112px**
(≥992px).

**[OBSERVED]** App navigation labels (dictionary): `navigation_browse_events` = "Browse events",
`search_events` = "Browse events", `browse` = "Browse events", `search` = "Search",
`following` = "Following", `upcoming_events` = "Events you're going to",
`discovery_your_lineup_title` = "Your lineup", `discovery_empty_state_tickets_action` = "View tickets".
**[OBSERVED]** Empty states: `browse_events_no_tickets_title` = "You don't have tickets,\nlet's fix that";
`browse_events_no_tickets_subtitle` = "See what we've got coming up";
`browse_events_has_tickets_title` = "Find your next show";
`browse_events_has_tickets_subtitle` = "Looking to twerk, mosh, or just chill?\nWhatever your mood, we've got you."

**[INFERRED]** The app's tab model is approximately **Lineup (feed) · Browse/Search ·
Tickets · Following/Profile** — a shallow 3–4 tab structure. Depth from feed to purchase is
short: card → event page → sticky CTA → ticket selection → pay. **[INFERRED]** The empty
state that *branches on whether you hold tickets* ("You don't have tickets, let's fix that"
vs "Find your next show") shows empty states are treated as designed surfaces with state
awareness, not as fallbacks.

**[OBSERVED]** Deep-linking is first-class: `dice://open/events/69dfb1a7cf0bf50001a598d1` is
published in `twitter:app:url:iphone` and `...googleplay`; `android-app://fm.dice/dice/open/search`
is registered as a JSON-LD `SearchAction` target; branded short links at `link.dice.fm`.
**[INFERRED]** Web is architected as an acquisition and deep-link layer for the app, not as a
parallel product.

**[OBSERVED]** Location is a route, not a setting: `/city/london`,
`/browse/london-54d8a23438fe5d27d500001c`; `find_an_city` = "Find a city";
`trending_in` = "Trending in"; the city object carries `{id,name,location{lat,lng,place},country_code}`.

---

## 8. MOTION (evidence only — no runtime observation)

All items **[OBSERVED]** as CSS declarations; behavioural interpretation **[INFERRED]**.

| Declaration | Where |
|---|---|
| `transition:opacity 200ms ease-out` | page `Container-sc-56688052-0` |
| `transition:opacity 200ms` | `EventDetailsCallToAction__ActionButton` |
| `--ease-out-sine:cubic-bezier(0.390, 0.575, 0.565, 1.000)` | defined token |
| `transition:all .35s ease-in-out` | `.carousel .slider.animated` (vendor `react-responsive-carousel`) |
| `transition:all .25s ease-in` | `.carousel .control-arrow`, `.control-dots .dot` |
| `transition:height .15s ease-in` | `.carousel .slider-wrapper` |
| `overscroll-behavior-x:contain` | rail scroller |
| `env(safe-area-inset-bottom)` + `--safe-bottom` | sticky CTA sheet |

**[INFERRED]** Motion is minimal and almost entirely **opacity-based at 200ms**. There are no
transform/scale hover effects, no card lift, no parallax, no scroll-triggered reveals in the
observed CSS. **[INFERRED]** This is a deliberate restraint that supports the editorial
positioning — and it is also what keeps a 4-up grid of heavy imagery feeling fast. The only
elaborate motion in the bundle comes from a third-party carousel library, i.e. not part of the
design language proper.

**[INFERRED]** The bottom-sheet CTA (`position:fixed;bottom:0;border-radius:10px 10px 0 0`)
plus the dictionary's many `*_sheet_*` keys (`ticket_transfer_disabled_reason_sheet_*`,
`return_to_waiting_list_sheet_footnote`, `refund_protection_order_sheet_*`,
`addon_selection_multi_variant_tooltip_title`) indicate **bottom sheets are the app's primary
secondary-surface pattern** — explanations and sub-decisions surface *in place* rather than by
navigating away. This is why the flows feel shallow.

---

## 9. ORGANIZER / PARTNER UX

Source: `https://dice.fm/partners`, `https://dice.fm/partners/ticketing/live`.
(`https://dice.fm/partners/pricing` → **404**; no public pricing page.)

**[OBSERVED]** Partner page heading sequence:
> "The engine for live events" → "DICE is the world leader in mobile ticketing" →
> "Sell more tickets" → "Stop losing revenue to resellers" → "Grow your business" →
> "Everything you need to run a successful show" → "Flexible tools" → "Data to drive decisions" →
> "Smart integrations" → "Instant access" → "Marketing essentials" → "24-7 support" →
> "Our most-loved feature" → "Merch on DICE" → "Ready to go live?"

**[OBSERVED]** Value-proposition copy, verbatim:
> "Partners get priority exposure in the app, meaning more of the right fans see your events."
>
> "DICE's wait list lets fans buy returned tickets for sold-out shows, meaning **no DICE ticket
> can ever appear on the secondary market and a sold-out room can actually be packed**."
>
> "Our Fan Support Team are on hand to help and delight customers for 365 days a year. We'll
> make sure there's nothing stopping a customer purchasing a ticket or attending your event."
>
> "Our job is to keep your event busy. Here's how we do it."

**[OBSERVED]** "Our most-loved feature" is the section that introduces the wait list.
**[INFERRED]** DICE's own marketing names the wait list as its single best feature — for
organisers, not fans. The pitch is explicitly *revenue recapture* ("Stop losing revenue to
resellers") and *yield* ("a sold-out room can actually be packed"), i.e. anti-tout is sold as
a commercial instrument, not as ethics.

**[OBSERVED]** Partner tooling surfaced in the shipped strings:
- **API access**: "This is a 40-digit string that will give you access to the API"
- **Attribution**: "This is a 8-digit string that allows us to attribute clicks, views, and
  purchases to the relevant partner"
- **Embeddable widget**: "Design your own custom widget to drop in on your website", with
  configurable options — "Choose how much information to display for each event",
  "Choose what should be shown as the main title of each event",
  "Show the event description (as shown in the DICE app)",
  "Show the age restriction information (as shown in the DICE app)",
  "Remove cancelled events from the event list", "Remove postponed events from the event list",
  "Show a label that indicates when an event has been recently announced"
- **Feed rules**: "Define what events will appear in you feed. Enter exact value (eg. The
  Underworld) and press enter to add" [sic]
- **Merch/Extras**: "Merch on DICE"; DICE Extras enables parking passes, skip-the-line passes
  and merchandise attached to an event (corroborated by trade press, see sources).
- **Onboarding form fields**: "Artist rep type" with options Artist Collective / Artist Manager
  / Artist Services / Booking Agent / Management Company; "Average event size" with buckets
  "< 250", "250 - 499", "500 - 9…"; "Promoter licence number".
- **Check-in**: no public check-in/scanner UI was observable. **[INFERRED]** from
  "show your QR codes to be scanned in" and single-use QR codes, a venue-side scanner app
  exists, but its interface is not publicly documented.

**[OBSERVED]** Support/ops surfaces: structured feedback with topic taxonomy
(`support_feedback_topic_title` = "Topic", `support_option_request_tax_invoice_title` = "Get a
tax invoice"), and event-scoped support (`support_event_search_description` = "Search for
events", `support_event_search_login_description` = "**Log in** to see the events you have
tickets to", `support_event_search_no_results` = "No results from DICE, hit 'Enter' to use this
event name").
**[INFERRED]** Support tickets are bound to a specific event object where possible, with a
free-text escape hatch. That is how you keep an ops queue triageable at scale.

**[OBSERVED]** DICE operates from UK, USA, France, Italy, Spain, Australia offices (address
block in the shipped payload); locales offered on dice.fm: `en, ca, de, es, fr, it, pt`.

---

## SOURCE URL LIST

Fetched and parsed on 2026-09-02:

- `https://dice.fm/`
- `https://dice.fm/city/london`
- `https://dice.fm/browse/london-54d8a23438fe5d27d500001c`
- `https://dice.fm/event/xedma3-games-night-23rd-apr-moot-club-london-tickets` (redirects to `...-30th-apr-...`)
- `https://dice.fm/event/g5bakb-nia-archives-emotional-world-tour-26th-nov-alexandra-palace-london-tickets`
- `https://dice.fm/event/3obowp-jamie-t-12th-dec-olympia-london-london-tickets`
- `https://dice.fm/bundles/london-club-nights-dw8g`
- `https://dice.fm/venue/moot-club-xexwk`
- `https://dice.fm/partners`
- `https://dice.fm/partners/ticketing/live`
- `https://dice.fm/help`
- `https://dice.fm/_next/static/chunks/1aixcbmwtm_v9.css`
- `https://dice.fm/static/fonts/ABCFavorit-*.woff2` (referenced, not downloaded)
- `https://dice.fm/partners/pricing` → **404**
- `https://dicefm.zendesk.com/hc/en-gb/articles/19958073128849-The-wait-list-explained` → **403** (content via search summary only)
- `https://apps.apple.com/gb/app/.../id898358948` → **429** (listing details via search summary only)

Secondary / search-derived (not directly fetched):
- `https://apps.apple.com/us/app/dice-live-shows/id898358948` (App Store name: **"DICE: Live Shows"**)
- `https://play.google.com/store/apps/details?id=fm.dice`
- `https://dicefm.zendesk.com/hc/en-gb/articles/4409662022289-How-the-Wait-List-queue-works`
- `https://dicefm.zendesk.com/hc/en-gb/articles/19741652701585-Find-events-and-buy-tickets`
- `https://en.wikipedia.org/wiki/Dice_(ticketing_company)`
- `https://www.musicbusinessworldwide.com/dice-launches-dice-extras-tool-...` (DICE Extras)

CDN hosts observed: `dice-media.imgix.net` (event/artist/venue artwork, marketing video),
`dice-i-scdn-co.imgix.net` (Spotify-sourced artist images), `dice.imgix.net` (static art),
`stream.mux.com` (event trailer HLS), `p.scdn.co` (Spotify audio previews),
`link.dice.fm` (branded short links).

---

## WHAT DICE DOES WELL

1. **It solved the "ugly artwork" problem mechanically, not editorially.** Square master →
   three deterministic centre-anchored crops → exact-size CDN request → `crop=faces,center` as
   a second pass. No uploader can break the grid. (§2.1)
2. **One aspect ratio everywhere.** 1:1 on cards, 1:1 on the hero. Visual rhythm survives any
   mix of posters, portraits and flyers. (§2.1, §2.3)
3. **The near-free ambient glow.** A 200px, `q=1` blurred copy of the event's own image tints
   the page. Per-event atmosphere for ~2–4KB and zero runtime colour analysis. (§2.4)
4. **All-in pricing with no fee vocabulary at all.** "£39.22" from first impression to button
   label; `price_youll_pay` = "The price you'll pay. No surprises later." The trust cliff was
   designed out, not disclosed away. (§5.1)
5. **A CTA state machine with no dead ends.** Sold out → wait list. Off sale → remind me.
   Locked → unlock. Every state captures intent. (§4.4)
6. **The wait list as the anti-tout answer.** It converts sell-out into an owned, revisitable
   state, keeps supply at face value, and is marketed to organisers as yield recovery. (§4.6, §9)
7. **Book-weight 35px titles.** Editorial, not commercial — and it keeps the artwork loudest. (§3.4)
8. **A single accent colour with a single job.** `#f2ef1d` on dates and focus rings only. (§3.5)
9. **Copy that justifies every constraint in the fan's or another fan's interest** — orphaned
   seats, partial wait-list allocation, in-app storage. (§4.6, §5.4)
10. **Two filters and five tags.** The city route is the real filter; curation and
    personalisation carry the rest. (§1.3)
11. **Craft in the invisible layer**: `q=80@1x / q=40@2x`, `background-color:#111` image slots,
    intrinsic `width`/`height` against CLS, `overscroll-behavior-x:contain`,
    `padding-bottom:100px/margin-bottom:-100px` on rails, input-modality-tuned
    `--gradient-width`, a black+yellow double focus ring. (§1.5, §2.1, §2.5)
12. **One component, two presentations** for the CTA (sidebar card ↔ fixed bottom sheet) and
    the card (stacked ↔ 96px row). (§1.6, §4.3)

## WHAT SNATCH IT SHOULD LEARN (without copying)

**Imagery — do this first, it is the highest-leverage change available**

1. **Adopt a normalise-to-square pipeline.** On upload, centre-crop every image to a square
   master, then derive fixed crops (1:1 card/hero, 1.91:1 or 5:3 social, ~0.55 app hero) with
   deterministic offsets. Never let an uploader's aspect ratio reach a layout. Store the crop
   rect on the asset so web, RN and OG all read one contract.
2. **Request images at the exact rendered box size, and make the layout token and the CDN
   width the same number.** DICE's sidebar is `max-width:328px` and it requests `w=328`.
   Pick our card and hero widths, then hard-code those into the transform URL. Skip `sizes`.
3. **Copy the DPR quality ladder: `q≈80` at 1×, `q≈40` at 2×.** Free retina sharpness at flat
   bytes. This is the single cheapest perf/quality win in this document.
4. **Pre-paint every image slot with a dark solid** (`background-color:#111` equivalent in our
   palette) and always set intrinsic `width`/`height`. No white flash, no CLS, no skeleton
   shimmer needed.
5. **Ship the ambient glow.** A ~200px, quality-1 copy of the event artwork, blurred 40–50px
   at ~0.4 opacity behind the hero, inset negatively and clamped to viewport height. Every
   event page becomes its own room. Do it desktop-first, as DICE does, and measure before
   enabling on RN.
6. **Take the inset, rounded, square hero over the full-bleed hero.** It reads as an object,
   needs no legibility gradient, has no safe-area problems, and survives every viewport.
7. **Two radii, and keep them small.** ~8px on imagery, ~10px on sheets/heroes. Our brand
   already runs radius-0; the transferable principle is *pick two and never deviate*, not
   *copy 8/10*.
8. **Never put video or motion in a card.** Reserve it for supplementary detail media.

**Typography**

9. **Buy one opinionated typeface and ship real weights.** When you cannot control the
   pictures, the letters are how you own the page. Our Oswald/Inter pairing already has this
   bone structure — the discipline to import is *five weights, one family, everywhere*.
10. **Set event titles at display size in a book/normal weight, not bold.** Let the artwork
    win. Reserve bold for the price and for uppercase pill buttons only.
11. **Standardise on ~120% line-height and a small positive letter-spacing (~0.02em)** across
    the metadata scale. This is most of the "expensive" feel and it costs nothing.
12. **One accent colour, one job.** Give Snatch It red (`#FF1A1A`) a single semantic role —
    almost certainly *date/time*, the binding constraint in nightlife — and refuse it
    everywhere else. Use a `rgba(255,255,255,0.66)`-equivalent for all secondary text.
13. **Card = four fields, in this order: Title → Date (accented) → Venue → Price.** Resist
    every request to add a fifth. Reserve badges for the one thing our model genuinely needs
    to say (see #15).

**Trust and the primary-vs-resale problem — the most important section for us**

14. **Go all-in on all-in pricing.** Display one number, fees included, from card through to
    the button label ("Checkout — £39.22"). Odd, non-round prices are *proof of honesty*, not
    a blemish. Remove "booking fee" from the product vocabulary entirely rather than disclosing
    it beautifully. This directly answers our fee-transparency exposure.
15. **Make "official" a visual property of the listing, not a badge users must interpret.**
    DICE has it easy: everything is first-party, so it needs no label. We are mixed, so we must
    do the inverse of what DICE does — we need *exactly one* card-level distinction between
    venue-native primary inventory and P2P resale, expressed in the same restrained language
    (a single-token colour or one small lockup), never a cluster of trust badges. Trust badges
    in bulk read as compensation for a trust problem.
16. **Adopt the wait-list mechanic as our resale replacement, not just as a feature.** A
    face-value, queue-based return system is the strongest structural answer to touting we
    have seen, and it is also the strongest *organiser* pitch ("stop losing revenue to
    resellers", "a sold-out room can actually be packed"). It converts our P2P legacy from a
    liability into an inventory-recovery advantage, and it lets us keep a resale surface
    without ever letting a user name a price.
17. **Steal the expectation-setting screen wholesale in spirit**: name the mechanic honestly,
    including the downsides ("you'll have a brief window", "if you miss your chance, rejoin at
    the top"). Honesty about the *downside* is what makes the *upside* believable.
18. **Justify every constraint by naming who benefits.** "The rest will go to the next fan on
    the wait list." "We want more fans to be able to sit together." Apply this to our transfer
    limits, ticket caps and refund windows. Our current copy states rules; DICE's states
    reasons.
19. **Build the price-*decrease* path with real warmth**, not just the increase path. Cheap,
    memorable, and almost nobody does it.
20. **Design a CTA state machine with no dead ends.** Off sale → remind me. Sold out → wait
    list. Not announced → notify. Every unavailable state must capture intent.
21. **Ask for the taste signal at confirmation**, the highest-trust moment in the funnel —
    never during onboarding.

**Structure and scope**

22. **Make the city a route, not a setting** (`/city/{slug}`), and let it do the filtering work
    so the filter panel can stay at two dimensions (date, price).
23. **Add a curated "Collection" route type.** Human-authored, shareable, SEO-addressable —
    our editorial voice made navigable, and a far better use of effort than genre taxonomy.
24. **Consider a periodic, exhaustible "Your lineup" instead of an infinite feed.** It caps the
    quality bar we must clear and manufactures a reason to return.
25. **Treat empty states as designed, state-aware surfaces** ("You don't have tickets, let's
    fix that" vs "Find your next show").
26. **Use bottom sheets as the default secondary surface** so explanations and sub-decisions
    never cost a navigation.
27. **Keep motion to ~200ms opacity.** No card lift, no parallax. It is faster and it reads as
    more expensive.

**What NOT to take from DICE**

28. **Do not gate tickets app-only on day one.** DICE can force "Get the app" because it has
    the demand to survive the friction; we do not. Take the *security* idea (activation +
    single-use QR) without the *distribution* constraint — build the credential so it can be
    web-delivered but still activation-gated.
29. **Do not make our web home a pure marketing page.** DICE can afford to because the app is
    the product. Our web surface needs to convert directly.
30. **Do not copy the crop offsets, radii, or `#f2ef1d`.** The transferable asset is the
    *method* — normalise, derive, pin to layout, one accent, one job — reinterpreted through
    Oswald/Inter, `#FF1A1A` and radius-0. A radius-0, hard-edged square grid with the same
    mechanical crop discipline would look nothing like DICE and work for exactly the same
    reasons.

# POSH (posh.vip) — Design Benchmark Research

Agent C · Product UI/UX V2 · researched 2026-09-02

**Method.** All findings come from publicly served HTML, CSS, JS bundles, React Server Component
(RSC) flight payloads, Cloudflare image URLs, the public Intercom knowledge base, Posh University
articles, and the App Store listing. No authentication, no browser automation, no proprietary assets
copied into this repo. Image URLs are recorded as evidence strings only.

**Labelling.** Every substantive line is tagged `OBSERVED` (fetched, quotable, with a source) or
`INFERRED` (reasoned, with the reasoning stated). Where I could not verify something I say so.

**Two distinct front-ends.** POSH runs at least three codebases, which matters when reading numbers:
- `posh.vip/` marketing home — **Webflow**. `OBSERVED`: `<meta content="Webflow" name="generator"/>`.
- `posh.vip/explore-v2` — Next.js App Router, basePath `/consumer-web`. `OBSERVED`: `self.__next_f`,
  `href="/consumer-web/_next/static/chunks/3fjb6ce92q-l2.css"`.
- `posh.vip/e/[eventUrl]` — Next.js App Router at root `/_next/`. `OBSERVED`: chunk
  `static/chunks/app/e/%5BeventUrl%5D/page-d770a56ea47c3404.js`.

The two app front-ends share the type scale and the Neue Haas font stack but differ in radius tokens
and in default color mode. `INFERRED`: `/explore-v2` is a newer rebuild (the `-v2` suffix and the
redirect from `/explore`) and the event page is the older, more heavily engineered surface.

---

## 1. DISCOVERY

### Route and page identity

- `OBSERVED` — `https://posh.vip/explore` 301/302s to `https://posh.vip/explore-v2` (curl
  `url_effective`). Page `<h1>` is "Discover Events".
- `OBSERVED` — i18n bundle embedded in the RSC payload of `/explore-v2`:
  `"explore":{"title":"Discover Events - Posh","description":"Find your world.", ...}`.
- `OBSERVED` — App Store subtitle is the same line: **"Find your world."**
  (`https://apps.apple.com/us/app/posh-create-find-events/id1556928106`).
- `INFERRED` — discovery, not ticketing, is the positioning. The tagline is about *the user's scene*,
  not about *getting a ticket*. Ticketing is treated as the closing step of a social product.

### Home hierarchy

- `OBSERVED` — exactly two content rails on the logged-out explore page, in order:
  `"featuredEvents":"Featured events"` then `"trendingEvents":"Trending events"`.
- `OBSERVED` — "Featured events" renders 16 unique events, DOM-duplicated to 32 card nodes.
  `INFERRED` — duplication is the standard infinite/looping-carousel technique (the wrapper carries
  `style="touch-action:pan-y pinch-zoom"` and `class="select-none overflow-hidden"`, and there are
  `aria-label="Previous event"` / `"Next event"` controls), so the rail wraps seamlessly.
- `OBSERVED` — "Trending events" rendered `"No events found"` for an unauthenticated, location-less
  request. `INFERRED` — trending is location-gated; with no city and no geolocation permission there
  is nothing to rank.
- `OBSERVED` — no category rail, no genre chips, no editorial collections in the served HTML.
  Discovery on web is: two rails plus three filters. Information density is **deliberately low**.

### Filters — the complete verbatim set

`OBSERVED`, from the explore i18n bundle:

| Filter | Strings |
| --- | --- |
| Location | `"location":"Location"`, `"nearMe":"Nearby"`, `"allLocations":"All locations"`, `"searchCity":"Search for a city"`, `"noCitiesFound":"No cities found"`, `"citySearchUnavailable":"City search is unavailable right now"`, `"locationPermissionDenied":"You have not shared your location with Posh. Please share to get events near you."`, `"clearLocation":"Clear location"` |
| Preset cities | `"newYorkCity":"New York City"`, `"miami":"Miami"`, `"losAngeles":"Los Angeles"`, `"washingtonDc":"Washington DC"`, `"boston":"Boston"`, `"atlanta":"Atlanta"` |
| Date | `"date":"Date"`, `"today":"Today"`, `"thisWeek":"This week"`, `"thisMonth":"This month"`, `"any":"Any"`, `"clearWhen":"Clear when"` |
| Price | `"price":"Price"`, `"upToPrice":"Up to {price}"`, `"apply":"Apply"`, `"clearPrice":"Clear price"` |
| Misc | `"backToTop":"Back to top"`, `"moreDates":"More dates"`, `"noEvents":"No events found"`, `"featuredEventsError":"Could not load featured events"`, `"tryAgain":"Try again"`, `"dismiss":"Dismiss"` |

- `OBSERVED` — the rendered filter row is three chips: **Nearby · Date · Price**.
- `OBSERVED` — price is a **single-ended** filter (`Up to {price}`), not a range.
- `OBSERVED` — six hard-coded preset cities. `INFERRED` — these are POSH's core markets; the city
  list is a curation decision, not an exhaustive geo index.
- `OBSERVED` — there is **no free-text event search** on `/explore-v2`. The only search string is
  `"searchCity":"Search for a city"` — search searches *cities*, not events.
- `OBSERVED` — the KB confirms the same model for attendees: "Use the filters to narrow your search
  by price, what's trending, date, or city."
  (`support.posh.vip/en/articles/10723762-how-to-purchase-tickets-with-posh`)
- `INFERRED` — POSH has deliberately refused a search box on web discovery. Search implies you know
  what you want; a nightlife browser does not. This forces the two curated rails to do the work and
  keeps the surface visual rather than lexical.

### Horizontal vs vertical

- `OBSERVED` — both rails are horizontal: `data-slot="inline" class="flex-row flex items-start
  justify-start flex-nowrap gap-0"` with fixed-width children `style="flex:0 0 240px"`.
- `INFERRED` — horizontal rails at 240px cap the number of simultaneously visible events (~5–6 on a
  desktop viewport, ~1.5 on mobile), which raises the perceived quality of each one. A vertical grid
  would show 12+ posters at once and turn curation into a wall.

### Event card anatomy — exact, in DOM order

`OBSERVED`, from the `/explore-v2` HTML (Odd Mob card, verbatim class/style attributes):

```
div  style="flex:0 0 240px"                      ← 240px slot
 div style="width:224px; transform-origin:left top; will-change:transform;
            opacity:100%; transition-duration:600ms"
            class="motion-safe:transition-opacity motion-reduce:transition-none"
  a  href="https://posh.vip/e/odd-mob" aria-label="Odd Mob" draggable="false"
   div class="relative overflow-hidden rounded-sm w-full" style="aspect-ratio:0.8"
    img alt="Odd Mob" data-nimg="fill" sizes="224px" decoding="async"
        style="position:absolute;height:100%;width:100%;left:0;top:0;right:0;bottom:0;
               object-fit:cover;color:transparent"
  div class="pt-6 md:pt-4"
   p   class="text-xs leading-4 text-muted-foreground font-normal truncate min-w-0"  → "ELEVENTH HOUSE"
   svg (verified badge, class "size-3 sm:size-4 md:size-5 !size-3 ... text-muted-foreground opacity-50")
   div class="... pt-4"
    a  → p class="font-normal text-sm md:text-base line-clamp-2 break-words"  → "Odd Mob"      (mb-4)
    p  class="text-muted-foreground font-normal truncate text-xs"  → "$25.00 at Building 64"
    p  class="text-muted-foreground font-normal truncate text-xs"  → "Fri, Sep 4, 8pm - 2am"
   div class="relative w-full min-w-0 hidden md:block" style="margin-top:16px;max-width:312px"
    chip(h-7, rounded, text-xs, bg-secondary) [20×20 rounded-[2px] artist avi] "Odd Mob"
    chip "+1"
```

Data order and emphasis, `OBSERVED`:

1. **Image** — 224 × 280 px, the only element with visual weight.
2. **Organizer** — 12px, muted, uppercase *in the content* ("ELEVENTH HOUSE"), truncated, + verified
   badge at 50% opacity. Sits **above** the title.
3. **Event title** — 14px mobile / 16px desktop, `font-normal` (weight 400), `line-clamp-2`.
4. **Price + venue on one line** — `"priceAtVenue":"{price} at {venue}"`, 12px muted. `"free":"Free"`.
5. **Date + time** — `"dateTimeRange":"{weekday}, {monthDay}, {startTime} - {endTime}"`, 12px muted.
   Also `"dateTimeStart":"{weekday}, {monthDay}, {startTime}"` and
   `"dateTimeMultiDayRange":"{startWeekday}, {startMonthDay}, {startTime} - {endWeekday}, {endMonthDay}, {endTime}"`.
6. **Lineup chips** — desktop only (`hidden md:block`), capped by `max-width:312px` with a `+N`
   overflow chip; each chip carries the artist's avatar at 20×20 with a 2px radius.

- `OBSERVED` — the event title is **weight 400**, the same weight as the metadata. Nothing on the
  card is bold. Hierarchy is created by *size and color* (16px foreground vs 12px muted), never weight.
- `INFERRED` — this is the central discovery decision: **the poster is the headline**. Making the
  title bold would compete with the artwork. POSH instead lets the flyer carry recognition and uses
  text purely as a caption.
- `OBSERVED` — the two chips ("Odd Mob", "+1") are rendered twice: once inside
  `class="absolute w-full invisible pointer-events-none"` and once visibly. `INFERRED` — a
  measurement pass: the invisible copy is laid out to compute how many chips fit inside the 312px
  budget before the visible row commits to a `+N` count.
- `OBSERVED` — organizer avatar derivatives use a *different* path shape from event flyers:
  `https://images.posh.vip/alts/68e44b9727c1b09152e7f902/610x600.webp` (pre-generated, dimensions in
  the path) vs `https://images.posh.vip/originals/<24-hex-id>` for flyers.

---

## 2. IMAGERY — the most important section

### 2.1 The numbers

| Property | Value | Evidence |
| --- | --- | --- |
| Card image aspect ratio | **0.8 (4:5 portrait)** | `style="aspect-ratio:0.8"` ×32 on `/explore-v2`; Tailwind class `aspect-[4/5]` ×8 elsewhere on the same page |
| Card image size | **224 × 280 px** | `style="width:224px"` + ratio 0.8 |
| Card slot / gutter | **240px slot → 16px gutter** | `style="flex:0 0 240px"` with a 224px child, container `gap-0` |
| Image → text gap | **24px mobile, 16px desktop** | `class="pt-6 md:pt-4"` |
| Card corner radius | **`rounded-sm`** | `class="relative overflow-hidden rounded-sm w-full"`. In the `/explore-v2` token set `--radius-sm: 4px` |
| Object fit | `object-fit:cover` | inline style on the `<img>` |
| Responsive hint | `sizes="224px"` | fixed — the browser fetches one size, not a fluid ladder |
| Event-page flyer | **512 × 640 (4:5)** | RSC props: `{"width":512,"height":640,"priority":true,"setToCover":true}` |
| Flyer column width | **330 / 375 / 400 px** | `EventAsidePanel` variant `event-page`: `md:w-[330px] lg:w-[375px] 2xl:w-[400px]` |
| Flyer max width | `xs:max-w-[400px]` | `EventAsidePanel` inner wrapper |
| Background source image | **width 2000, quality 75** | `buildCloudflareImageUrl(imageUrl,{width:2e3,quality:75,fit:"scale-down",format:"auto"})` |
| Map preview | **600 × 300, `h-[300px]`, `rounded-md`, `object-cover`, quality 100** | `MapImage` RSC props |
| YouTube block | `aspect-video w-full overflow-hidden rounded-md` | RSC, event page |
| Fee/aspect default in code | `aspectRatio = .8`, `setToCover = true` | `SmartCroppedImage` defaults, chunk `7648-0009ea2fe9b8c172.js` |

`OBSERVED` — **4:5 portrait is the single image contract across the entire product.** The card, the
event-page hero and the component default are all 0.8. There is no landscape event image anywhere I
fetched.

`INFERRED` — 4:5 is the Instagram feed maximum-height ratio. Nightlife flyers are designed and
exported for Instagram first. By adopting 4:5 rather than 16:9 or 1:1, POSH accepts the artwork
organizers *already have* at its native crop, so almost no flyer needs to be re-made or re-cropped
to look right. This is the highest-leverage imagery decision in the product.

### 2.2 The image CDN

- `OBSERVED` — origin is `https://images.posh.vip/originals/<24-hex-mongo-id>` — **no query params,
  no extension**.
- `OBSERVED` — transforms are applied by **Cloudflare Image Resizing** as a path prefix on the app
  domain. Verbatim from `/explore-v2` `srcSet`:
  ```
  https://posh.vip/cdn-cgi/image/width=32,quality=75,format=auto,anim=true/https://images.posh.vip/originals/69dd7e4aa4318ef54f9fc746 32w,
  https://posh.vip/cdn-cgi/image/width=48,quality=75,format=auto,anim=true/https://images.posh.vip/originals/69dd7e4aa4318ef54f9fc746 48w,
  ...
  ```
- `OBSERVED` — the emitted width ladder on `/explore-v2` is
  `32, 48, 64, 96, 128, 256, 384, 640, 750, 828, 1080, 1200, 1920, 2048, 3840` (the Next.js default
  `deviceSizes`+`imageSizes` ladder), all at `quality=75, format=auto, anim=true`.
- `OBSERVED` — `anim=true` is set on every card image. `INFERRED` — organizers upload **animated GIF
  flyers** and POSH preserves the animation through the resize rather than flattening to a still
  frame. (Their own og:image is a GIF: `092724_Posh_Metal_3D_Logo_1920x1080-ezgif.com-crop.gif`.)
- `OBSERVED` — the event page uses a different parameter set for social cards:
  `cdn-cgi/image/fit=scale-down,width=640,height=640,format=auto,quality=50/...` for og/twitter
  image, and `width=1200,height=630`, `width=600,height=315`, `width=400,height=215` variants.
- `OBSERVED` — the transform contract is carried through the app in a private `_cf` query param that
  is stripped by the Next.js image loader before building the Cloudflare URL (chunk
  `7648-…`, module `66081`):
  ```js
  let i = { width:a, quality:n, fit:"scale-down", format:"auto", ...o };
  return buildCloudflareImageUrl(l, i)
  ```
  `INFERRED` — `fit=scale-down` as the global default means POSH **never upscales** an organizer's
  artwork. A low-res flyer renders small-but-sharp rather than large-and-soft.

### 2.3 `SmartCroppedImage` — why no flyer is ever mangled

`OBSERVED`, chunk `7648-0009ea2fe9b8c172.js`, module `13445`, verbatim logic:

```js
let m = e => {
  let { src:t, placeholder:a="blur", blurDataURL:n=d, aspectRatio:m=.8,
        setToCover:u=true, disableFadeIn:f=false, ... } = e;
  const [g,j] = useState(m);                      // measured natural ratio
  // backdrop, only when NOT cover:
  const v = u ? null : { backgroundImage:`url(${p})`, backgroundPosition:"center",
                         backgroundSize:"cover", filter:"blur(54px)", transform:"scale(1.2)" };
  // edge feathering mask, only when NOT cover:
  const b = g < m ? "linear-gradient(to right, transparent, black 5%, black 95%, transparent)"
          : g > m ? "linear-gradient(to bottom, transparent, black 5%, black 95%, transparent)"
          : "none";
  const C = { ...w, width:u?"100%":"auto", height:u?"100%":"auto",
              objectFit: u ? "cover" : "contain",
              maskImage: u ? "none" : b, maskComposite:"intersect",
              WebkitMaskComposite:"source-in", maskRepeat:"no-repeat" };
  // measures on load:
  const N = e => { const {naturalWidth:t, naturalHeight:a} = e.currentTarget; j(t/a); ... };
  return <AspectRatio ratio={m} className="relative h-full w-full overflow-h…
}
```

What that means, `OBSERVED`:

- The frame is always `AspectRatio ratio={0.8}` — locked.
- `setToCover: true` (the default, and the value used for the Odd Mob event) → plain `object-fit: cover`.
- `setToCover: false` → the image switches to `object-fit: contain`, and the empty area is filled with
  **a blurred, 1.2×-scaled copy of the same flyer** (`filter: blur(54px)`), while the real image's
  edges are feathered into it by a mask that runs `transparent → black 5% → black 95% → transparent`
  along whichever axis has slack.
- The natural ratio is measured from the decoded image (`naturalWidth/naturalHeight`) and drives the
  mask direction, so the fallback adapts per-image at runtime.
- `OBSERVED` — the event record carries `"setFlyerToCover": true`, i.e. **the organizer chooses**
  between crop and fit.

`INFERRED` — this is the mechanism that lets POSH have *both* a perfectly uniform 4:5 grid *and*
never hard-crop a poster's typography off the edge. Every competitor picks one: uniform grid with
brutal crops, or ragged grid with intact art. POSH gets uniformity from the frame and integrity from
the contain-plus-self-blur fallback. There are no black letterbox bars anywhere in the system.

### 2.4 `EventThemeBackground` — **why the event page feels premium**

`OBSERVED`, chunk `page-d770a56ea47c3404.js`, module `7e3`, verbatim:

```js
let m = l ? buildCloudflareImageUrl(l, {width:2e3, quality:75, fit:"scale-down", format:"auto"}) : undefined;
useEffect(() => { const e = new Image(); e.onload = () => u(true); e.onerror = () => u(false); e.src = m; }, [m]);

<div className={cn("relative", a)}>
  <div className={cn("fixed inset-0 top-0 z-0 h-screen w-screen overflow-hidden transition-colors duration-300",
                     o ? "bg-accent-event" : "bg-background")}>
    <div className={cn("absolute inset-0 w-full transition-opacity duration-500 ease-in-out",
                       m && d ? "opacity-100" : "opacity-0")}
         style={{ height: "33.33%",
                  backgroundImage: `url(${m})`,
                  backgroundPosition: "100% 5%",
                  backgroundSize: "cover",
                  backgroundRepeat: "no-repeat",
                  maskImage: "linear-gradient(to bottom, var(--background), transparent)",
                  WebkitMaskImage: "linear-gradient(to bottom, var(--background), transparent)" }} />
    <div className="absolute inset-0 backdrop-blur-md" />
    <div className="absolute inset-0 bg-gradient-to-b from-background/33 to-background/77" />
  </div>
  <div className="relative z-10">{children}</div>
</div>
```

`OBSERVED` — the RSC props confirm it is fed the event's own flyer:
`{"imageUrl":"https://images.posh.vip/originals/69dd7e4aa4318ef54f9fc746","useAccentColor":false}` —
the same id as the hero flyer.

Decoded, `OBSERVED`:

1. A **fixed, full-viewport** layer behind everything (`fixed inset-0 h-screen w-screen`, `z-0`).
2. The event's own flyer, re-fetched at **2000px wide**, painted across the **top 33.33%** of that
   layer, `background-size: cover`, anchored at **`100% 5%`** (right edge, just below the top).
3. That band is **masked with a top-to-bottom fade to transparent**, so it dissolves into the page.
4. The whole layer is **`backdrop-blur-md`** (Tailwind: `blur(12px)`).
5. A **downward scrim** `from-background/33 to-background/77` sits on top — 33% opaque at the top,
   77% at the bottom.
6. The band **fades in over 500ms** only after a `new Image()` preload resolves — it never pops.
7. Content renders at `z-10`, crisp, over that.

`INFERRED` — **this is the answer to "why does POSH's event imagery feel premium."** It is not the
photography and not the radius. It is that *every event page is color-graded by its own poster*. The
crisp 512×640 flyer sits on a blurred, scrimmed, top-anchored enlargement of itself. The page's
ambient color therefore always agrees with the artwork — a red flyer produces a red room, a chrome
flyer a grey one — with zero design work from the organizer and zero risk of a clashing palette. The
33% height plus the mask plus the 33→77% scrim means the effect is strongest exactly where the hero
image is and gone by the time you reach the ticket list, so it never fights legibility. Compare the
usual alternative — a flat brand-colored page — which makes every event look like the *platform*
instead of like *itself*.

`OBSERVED` — the same tinting logic drives foreground chrome. Cards on the event page are glass:
`EventPageCard` = `class="rounded-xl p-4 backdrop-blur-xl bg-white/5"` — 12px radius, 16px padding,
5% white fill, 24px backdrop blur. Ticket-group accordion triggers are `bg-white/15` in dark mode
and `bg-black/10` in light mode, hovering to `/20`.

### 2.5 Loading and placeholder behavior

- `OBSERVED` — the event record carries a **BlurHash**:
  `"flyerBlurHash":"dBE:Mg?w.9MwpGIT-=t7r@kCj]WAx^tRWBtR-=xuofj["`.
- `OBSERVED` — `PoshNextImage` sets `placeholder:"blur"` with a fallback `blurDataURL` that is a
  **1×1 transparent PNG** (`data:image/png;base64,iVBORw0KGgo…AAAAASUVORK5CYII=`), and applies
  `transition-opacity duration-300` with `opacity-0` → `opacity-100` on `onLoad`, escapable via a
  `disableFadeIn` prop.
- `OBSERVED` — explore cards fade with `transition-duration:600ms` and
  `motion-safe:transition-opacity motion-reduce:transition-none`.
- `OBSERVED` — skeletons rather than spinners: map preview
  `class="animate-pulse bg-primary/10 h-[300px] w-full rounded-md"`; order summary uses
  `Skeleton` bars at `h-5 w-48`, `h-5 w-16`, `h-12 w-full`, `h-10 w-full`, `h-6 w-24`, `h-6 w-20`.
- `INFERRED` — three separate fade budgets (300ms for a single image, 500ms for the ambient
  background, 600ms for card reveal) are tuned so the big ambient wash arrives *after* the sharp
  content, not before. It reads as the page "developing" rather than flashing.
- `INFERRED` — `prefers-reduced-motion` is honoured at the card level (`motion-reduce:` variants),
  which is a genuine accessibility choice, not decoration.

### 2.6 Video and audio

- `OBSERVED` — event record carries `"youtubeVideoId":"gJV_lxa42Xs"` and `"youtubeLink"`. Rendered as
  `paulirish/lite-youtube-embed` loaded from jsDelivr with `strategy:"lazyOnload"`, wrapped in
  `class="aspect-video w-full overflow-hidden rounded-md"`, with a style override
  `lite-youtube > .lyt-playbtn { filter: none; }`.
- `OBSERVED` — events carry a **Spotify track**, surfaced as `og:audio`:
  ```
  <meta property="og:audio" content="https://p.scdn.co/mp3-preview/d274cd48e965b680e15b2f9bc641943da9d5d927"/>
  ```
  and as an `EventSongPlayer` **overlaid on the flyer**:
  `class="absolute right-6 bottom-6 left-6 flex justify-end md:right-0 md:bottom-0 md:left-0"`, with
  `{albumCover, previewLink, link, name:"Coming Up (It's Dare)", artist:"Odd Mob"}`.
- `OBSERVED` — `"galleryPhotos":[]` exists on the event model. `INFERRED` — a multi-photo gallery is
  supported but empty for this event; I could not verify its layout.
- `INFERRED` — the poster is not the only medium: POSH treats an event as artwork + a track + a
  video. The song player being *on* the flyer (rather than in a separate section) is what makes the
  hero feel like a record sleeve rather than a listing.

### 2.7 Text over imagery

- `OBSERVED` — **no text is ever set over the event artwork.** On the card, all metadata sits below
  the image in a `pt-6 md:pt-4` block. On the event page the title lives in the opposite column. The
  only things over the flyer are the song-player chip and (via the ambient layer) nothing at all.
- `INFERRED` — this is why POSH can accept arbitrary organizer flyers. Overlaying a title on a poster
  requires a predictable focal area and a scrim; POSH sidesteps the whole class of problem by never
  doing it, which also means the flyer's own typography is never doubled up by the platform's.

---

## 3. TYPOGRAPHY

### Families

`OBSERVED` — self-hosted `@font-face` declarations in both app CSS bundles:

```
Haas Grotesk Display Web  → NeueHaasGroteskDisplay-45Light-Web.woff2   (300)
                             NeueHaasGroteskDisplay-55Roman-Web.woff2   (400)
                             NeueHaasGroteskDisplay-65Medium-Web.woff2  (500)
                             NeueHaasGroteskDisplay-75Bold-Web.woff2    (700)
                             NeueHaasGroteskDisplay-95Black-Web.woff2   (900)
Haas Grotesk Text Web     → NeueHaasGroteskText-55Roman-Web.woff2       (400)
                             NeueHaasGroteskText-65Medium-Web.woff2     (500)
                             NeueHaasGroteskText-75Bold-Web.woff2       (700)
IBM Plex Mono             → 400 / 500 / 700
```
All `font-display: swap`.

`OBSERVED` — token aliases in `/consumer-web` CSS:
```
--font-family-sans:    NHGText-Roman, system-ui, -apple-system, sans-serif
--font-family-display: NHGDisplay-Roman, system-ui, -apple-system, sans-serif
--font-family-mono:    IBMPlexMono-Regular, "Courier New", monospace
--font-display:        "Haas Grotesk Display Web", ui-sans-serif, system-ui, sans-serif
```

`OBSERVED` — the Webflow marketing site uses the same family under a different name:
`font-family: Neue Haas, Arial, sans-serif`
(`cdn.prod.website-files.com/6979568d54b5ed70e010e8dc/css/posh-606416.webflow.shared.0c9db2301.css`).

`INFERRED` — **one typeface, two optical sizes, across three codebases.** Neue Haas Grotesk is a
licensed, paid, neutral Swiss grotesque with a genuine Display cut. Choosing it — and paying for the
Display/Text optical pair rather than using one weight range — is itself a large part of the premium
read: the neutrality means the typography never competes with the flyers, and the Display cut at
48px has tighter apertures and spacing than the Text cut would at the same size.

### Scale and metrics

`OBSERVED` — `/consumer-web` explicit px scale:
`--font-size-xs:12 · sm:14 · base:16 · lg:18 · xl:20 · 2xl:24 · 3xl:30 · 4xl:36 · 5xl:48 · 6xl:60 · 7xl:72`.
Weights `light:300 · normal:400 · medium:500 · semibold:600 · bold:700 · black:900`.
Tailwind line-height pairs: `xs` → `1/.75` (16px), `sm` → `1.25/.875` (20px), `base` → `1.5` (24px).
Tracking: `tight:-.025em · normal:0 · wide:.025em · widest:.1em`.
Leading: `tight:1.25 · snug:1.375 · normal:1.5 · relaxed:1.625`.

### Applied treatments — verbatim

| Element | Classes | Resolved |
| --- | --- | --- |
| Event title, **event page** | `my-4 font-semibold text-balance md:my-20 text-3xl xs:text-4xl md:text-5xl` | 30 → 36 → **48px**, weight **600**, `text-balance`, **80px vertical margin** on desktop |
| Event title, **card** | `font-normal text-sm md:text-base line-clamp-2 break-words` | 14 → 16px, weight **400**, 2-line clamp |
| Venue (event page) | `scroll-m-20 tracking-tight text-base font-semibold lg:text-lg` | 16 → 18px, weight 600, `-0.025em` |
| Date/time (event page) | `font-base text-base lg:text-lg` | 16 → 18px, weight 400 |
| Organizer (event page) | `scroll-m-20 tracking-tight font-medium text-base` | 16px, weight 500 |
| Organizer (card) | `text-xs leading-4 text-muted-foreground font-normal truncate` | 12px / 16px lh, weight 400, muted |
| Price + venue (card) | `text-muted-foreground font-normal truncate text-xs` | 12px, weight 400, muted |
| Section headings | `font-semibold` (e.g. "About this event") | weight 600, inherited size |
| Description body | `ProseContent … className="text-primary/80"`, `size:"sm"` | 14px at **80% foreground opacity** |
| Order total | `flex justify-between text-lg font-bold` | 18px, weight 700 |
| "Your Order" | `text-lg font-semibold` | 18px, weight 600 |
| Ticket price | `text-sm` + subtext `text-sm font-light whitespace-nowrap text-muted-foreground` | 14px, fee subtext at weight **300** |

Observations:

- `OBSERVED` — **the heaviest weight anywhere in the consumer UI is 700, used only on the checkout
  total.** Titles are 600, everything else 400–500. The 900 Black cut is loaded but unused in the
  surfaces I fetched.
- `OBSERVED` — **no letter-spacing is applied except `tracking-tight` (−0.025em) on the venue and
  organizer headings.** No wide tracking, no small-caps, no CSS `text-transform` anywhere in the card
  or event markup I read. "ELEVENTH HOUSE" is uppercase **because the organizer typed it that way**.
- `INFERRED` — POSH does not impose a nightlife-cliché typographic voice (no forced uppercase, no
  wide-tracked labels). It stays neutral and lets the flyer supply the attitude. The result is that
  a 90s-throwback poster and a minimal techno poster both look at home in the same rail.
- `OBSERVED` — the date string uses **non-breaking spaces**: `"Fri, Sep 4 at 8:00 PM - 2:00 AM (EDT)"`.
  `INFERRED` — deliberate: the date never wraps between "Sep" and "4".
- `OBSERVED` — `text-balance` on the `h1`. `INFERRED` — multi-line event titles get evened line
  lengths rather than an orphaned last word.
- `OBSERVED` — **the organizer can choose the event title's font**: the event record carries
  `"eventTitleFont":"NHGDisplay-Bold"` and `EventPageStickyInfo` receives
  `{"fontFamily":"NHGDisplay-Bold","fontExists":false}`; the `h1` renders with
  `style={{fontFamily: undefined}}` when the font is unavailable.
  `INFERRED` — a per-event display-font picker exists with a safe fallback to the system default when
  the chosen face is missing. `fontExists:false` here means this event's chosen font did not resolve
  and the page silently used the default — a graceful-degradation pattern.

---

## 4. EVENT PAGE

Source: `https://posh.vip/e/odd-mob` (RSC payload + chunks). The page is client-rendered; only
`<meta>` is in the initial HTML, but the full RSC flight payload is served inline.

### Layout

`OBSERVED` — `EventMainContainer` (`EventLayout.tsx`):
```
main class="mx-auto flex min-h-screen w-full max-w-5xl flex-col justify-around px-3 pb-5
            sm:px-6 md:grid md:grid-cols-[minmax(0,1fr)_auto] md:gap-6"
   + page override: "mt-2 pb-0 md:mt-4 md:gap-8 2xl:max-w-6xl 2xl:gap-12"
```
- **max-w-5xl (1024px)**, widening to **max-w-6xl (1152px)** at 2xl.
- Desktop: 2-column grid, content `minmax(0,1fr)` + flyer `auto`. Gap 24 → 32 → 48px.
- Page padding 12px → 24px.

`OBSERVED` — `EventAsidePanel` (the flyer column):
```
order-1 flex flex-col md:order-2
  variant "event-page": md:w-[330px] lg:w-[375px] 2xl:w-[400px]
  inner: relative top-0 mx-auto h-auto w-full items-start xs:max-w-[400px] md:sticky md:top-20
```
`OBSERVED` — `EventPrimaryPanel`: `order-2 mt-4 mb-12 flex flex-col gap-4 md:order-1 md:mt-2`.

So: **flyer first on mobile, flyer on the *right* on desktop and sticky at 80px from the top;
content on the left.** `INFERRED` — sticking the flyer means the artwork stays on screen for the
whole scroll, which is unusual (most sites stick the *ticket widget*). It keeps the event's identity
present while you read.

### Content order (RSC tree, `EventPrimaryPanel`)

`OBSERVED`, in order:

1. **Organizer row** — `Avatar size="xs"` (`images.posh.vip/alts/…/610x600.webp`) + `h2` "ELEVENTH
   HOUSE" (16px/500/tracking-tight) + a two-layer verified badge (`Verified Background` +
   `Verified Check` SVG titles). Links to `/g/eleventh-house`. On the right of the same row:
   `EventPageLikeButton` and `EventPageShareButton`.
2. **`h1` title** — `my-4 … md:my-20 text-3xl xs:text-4xl md:text-5xl font-semibold text-balance`.
3. **When/Where** (`EventPageWhenWhere`, `id="event-page-when-where"`, `mb-6`) — venue `h2` then
   time `p`. **Venue is above the time**, and both are the same size (16/18px), venue at 600 and
   time at 400.
4. **Tickets / purchase** (`EventPagePurchaseRow` — see §5).
5. `border-t border-primary/20` + `py-8` — **section rules at 20% foreground opacity**.
6. **"About this event"** — `h2 font-semibold`, then `ProseContent` with
   `expandable:true, maxLines:{mobile:15, desktop:20}, className:"text-primary/80"`.
   Markdown is rendered with `marked` and sanitized with DOMPurify (`ADD_ATTR:["target"]`), links
   forced to `target="_blank" rel="noopener noreferrer"`.
7. **Video** — lazy `lite-youtube` in `aspect-video … rounded-md`.
8. **Lineup** (`EventPageLineupSection`) —
   ```json
   [{"name":"Odd Mob",
     "avi":"https://i.scdn.co/image/ab6761610000e5eb60a5642e7a0bf885809f7fac",
     "link":"https://open.spotify.com/artist/4qLwtWhlhyAoQ4S9mSrDW9",
     "description":"",
     "artistInformation":{"provider":"spotify","spotifyArtistId":"4qLwtWhlhyAoQ4S9mSrDW9",
                          "actType":"HEADLINER","popularity":65}}]
   ```
   plus `"performanceCategory":"Event Features"`.
   `INFERRED` — lineup is **resolved from Spotify**, not typed by hand: the organizer picks an
   artist and POSH inherits their official photo, link and popularity score. That is why lineup
   avatars are always correct and on-brand — POSH never asks a promoter to upload an artist photo.
9. `h-px w-full bg-primary/20` divider.
10. **Map** (`MapPreviewContent` → `MapImage`) —
    `src="https://images.posh.vip/mapbox/mapbox-static-image/32_86594/-79_97181/dark/44136fa3"`,
    `class="h-[300px] w-full rounded-md object-cover"`, `width:600 height:300`,
    `transformOptions:{quality:100}`, `title="View the event location"`. Pin is
    `size-4 rounded-full bg-[var(--accent-event)]` with a `size-8 … bg-[var(--accent-event)]/30` halo.
    `INFERRED` — the map is a **static, dark-styled, self-proxied Mapbox image**, not an interactive
    map: it loads instantly, matches the dark page, and the pin picks up the event's accent color.
11. **Organizer card** (`EventPageCard`) — `rounded-xl p-4 backdrop-blur-xl bg-white/5` containing
    "Hosted by" (`text-sm text-white/60`) + name + verified badge, `EventPageOrganizerContactButton`,
    `EventPageOrganizerFollowButton`, `EventPageOrganizerSocials`, and
    `EventPageOrganizerPublicAnalytics` rendering `<ClientNumber value={6}/> events` in
    `text-sm text-white/80`.
12. **`EventPageDownloadAppCTASection`**.
13. Footer with Posh wordmark and `EventPageFooterCreateEventButton`.

### Theming

`OBSERVED` — event record:
```json
"accentColor":"#FFFFFF", "applyAccentColorToBackground":false,
"eventTheme":{"lightmode":false,"accent":{"light":"#FFFFFF","dark":"#FFFFFF"}}
```
plus event-type flag `"lightMode":false`. Token: `--accent-event: var(--accent)`.

- `OBSERVED` — **event pages default to dark** and the organizer picks a single accent color with
  independent light/dark values, optionally flooding the background with it.
- `OBSERVED` — the accent is used for the **primary CTA fill** and the **map pin**, and nothing else
  I found.
- `INFERRED` — a tightly bounded customization surface: one color, one optional title font, one
  cover/fit toggle, one song, one video. Organizers get to feel the page is theirs without any
  ability to make it ugly or illegible. That restraint is a large part of why every POSH page looks
  consistent while none looks templated.

### Social proof

- `OBSERVED` — `"attendanceDisplayDisabled": false` on the event and
  `"enableEventActivity": true` / `"activityEnabled": false` on the event type; components
  `EventPageLikeButton`, and organizer `roleData.hasActivityFeedAccess` /
  `hasActivityFeedInteractAccess` / `canPostAsOrganizer`.
- `OBSERVED` — the only social proof rendered on this page was the organizer's **"6 events"** count
  and the verified badge. I did **not** observe an attendee-avatar row or a "N going" count in the
  served payload; the `attendanceDisplayDisabled` flag implies one exists but I cannot confirm its
  visual treatment.
- `OBSERVED` — App Store copy claims it: "see what the vibe is and who's going". `INFERRED` — the
  attendee list is primarily an in-app (native) surface.

---

## 5. CHECKOUT

### Ticket tier presentation

`OBSERVED` — `EventPageTicketGroup` (chunk `1696-b233059192278351.js`, module `45315`) is a
**single-open, collapsible accordion** per tier group:
```
AccordionTrigger class="cursor-pointer rounded-md p-4 transition-all duration-300 ease-in-out
                        [&>svg]:text-current"
   dark:  bg-white/15   hover:bg-white/20
   light: bg-black/10   hover:bg-black/20
   open:  bg-primary text-secondary
```
`OBSERVED` — ticket model flags read by the item component:
`sellInMultiples`, `purchaseMin`, `purchaseLimit`, `quantityAvailable`, `approvalRequired`,
`isTransferable`, `closed`, `waitlistMetadata.enabled`, `isCurrentUserInWaitlist`; helpers
`ticketMayBePurchased`, `ticketIsSoldOut`, `ticketIsComingSoon`.
`OBSERVED` — quantity bounds: `P = sellInMultiples ? purchaseMin : 1` and
`S = Math.min(quantityAvailable, purchaseLimit ?? Infinity)`.
`INFERRED` — the quantity stepper's min is the pack size (so a "2-for" ticket starts at 2) and its
max is the smaller of remaining inventory and the per-order limit. Sold-out tiers with a waitlist
swap the stepper for a join-waitlist action (`onJoinWaitlist`, `disableWaitlistButtons`).

### Fee presentation — the honesty question

`OBSERVED` — the price shown on a ticket row is computed with fees **forced on**:
```js
const {ticketDisplayPrice, feeAmount} = getTicketDisplayDetails({...ticket, showFeesInPrice: true});
const u = getTicketDisplayPriceSubtext(feeAmount, getCurrencySymbol(currency));
…
<p className="text-sm">{t}</p>
{u && <p className="text-sm font-light whitespace-nowrap text-muted-foreground">{u}</p>}
```
`OBSERVED` — `getTicketDisplayDetails`:
```js
t = showFeesInPrice ? totalPrice : price;
feeAmount = (sellInMultiples && purchaseMin) ? (totalPrice - price) * purchaseMin : totalPrice - price;
ticketDisplayPrice = isTicketPack ? t * purchaseMin : t;
isSoldOut = quantityAvailable <= 0 || closed;
```
`OBSERVED` — a `" fees"` string literal in the same bundle; `INFERRED` — the subtext reads
approximately "incl. $X.XX fees", but I could not resolve the full template string and will not
quote it as verbatim.
`OBSERVED` — event type carries `"showFeesInPrice": true`, and the event's
`"minPriceWithFees": 29.24` sits alongside the discovery card's displayed `"$25.00 at Building 64"`.

`INFERRED` — **fee honesty is split by surface, and this is a real inconsistency.** On the event page
and in checkout the all-in price is shown (the component hard-codes `showFeesInPrice:true`). But the
`/explore-v2` card for the same event advertises **$25.00** while the true minimum is **$29.24** — a
17% gap between the browse price and the buy price. POSH's own marketing promises "upfront pricing…
no surprises" (`og:description` on posh.vip), which the card price does not deliver.

`OBSERVED` — `OrderSummaryTable` (chunk `7648-…`, module `91945`), in exact render order:

1. Header: `<span class="text-lg font-semibold">Your Order</span>` + `Button variant="outline"
   shape="pill" size="sm"` labelled **"Edit"** (clears the cart id and returns to selection).
2. `PricingBreakdownCartItems` — one row per item, descriptor `` `${quantity}x ${descriptor}` ``,
   value `totalRawPrice`; row is `flex items-center justify-between`, label `text-md font-medium`.
3. `FeesAccordion` — a row reading **"Fees"** with the summed total, both
   `text-sm text-muted-foreground`, expanding to an itemized `PricingBreakdownFees`. If there is
   exactly **one** fee it degrades to a plain labelled row with the fee's own name and a
   `tooltipText`.
4. `TaxRow` — "Sales tax", muted, hidden when `salesTax <= 0`.
5. `PromoCode` — accordion trigger **"Add promo code"** (`hideCaret`, `text-sm font-semibold
   text-muted-foreground`), input `placeholder="Enter promo code"` + an `ArrowRight` icon submit.
   On failure: toast `"Invalid or expired promo code"` / `"Please try again with a valid code."`
   On success: `flex items-center justify-between text-sm font-medium text-green-500` →
   **"Discount Applied"** … `-$X`.
6. `Separator`.
7. `CheckoutTotal` — `flex justify-between text-lg font-bold`.
8. `ApprovalDisclaimer` (when `approvalRequired && total !== 0`), verbatim:
   > "Since some of the items in your cart need to be approved, your money will be put on hold until
   > the organizer verifies you may attend the event."

`INFERRED` — the fee row is **collapsed but always visible and always labelled "Fees"** with its
amount showing before you expand. That is the honest middle ground: it does not bury fees in a
tooltip, and it does not force a wall of line items on someone who does not care.

### Sticky CTA

`OBSERVED` — `EventSubmitButtonContainer`: when **not** `md`,
```
fixed right-0 bottom-0 left-0 z-30 w-full bg-gradient-to-t from-background to-transparent p-4
```
`OBSERVED` — `EventCTAButton`:
```
Button shape="pill"
  w-full border bg-accent-event text-base text-foreground
  hover:bg-[color-mix(in_oklab,var(--accent-event),var(--foreground)_15%)]
  disabled:bg-muted disabled:text-muted-foreground disabled:opacity-100
```
- `OBSERVED` — mobile CTA is a **pill, full-width, painted in the organizer's accent color**, floating
  over a bottom-up gradient scrim, 16px padding, `z-30`.
- `OBSERVED` — the hover state is computed with `color-mix(in oklab, …, 15%)` rather than a fixed
  hover color. `INFERRED` — necessary because the base color is user-supplied; oklab mixing keeps the
  hover perceptually consistent whatever accent the organizer picked.
- `OBSERVED` — `disabled:opacity-100` with an explicit muted background. `INFERRED` — deliberate:
  a disabled CTA stays fully opaque and legible ("Sold out") instead of ghosting out.

### Payment

- `OBSERVED` — **Stripe Payment Element**, confirmed in-page with no redirect:
  ```js
  const e = await elements.submit(); if (e.error) return e;
  const {paymentIntentClientSecret:t} = await updateCartWithPaymentIntent({cartId:r});
  a = await stripe.confirmPayment({elements, clientSecret:t, redirect:"if_required",
                                   confirmParams:{return_url:c}});
  ```
  (a live Stripe **publishable** key is present in the bundle, as is normal; not reproduced here).
- `OBSERVED` — a saved-card path exists (`confirmPayment({clientSecret, redirect:"if_required",
  confirmParams:{payment_method: e.paymentMethodId, …}})`).
- `OBSERVED` — **Affirm**: string `" Checkout with Affirm"`; KB article "Attending Posh Events with
  Affirm Payment Plan" and "Setting Up Affirm Payment Plans for Organizers"; event type flag
  `"paymentPlansEnabled": false`.
- `OBSERVED` — App Store: "RSVP or buy tickets in a few taps with Apple Pay, card, or debit."
- `OBSERVED` — server layer is tRPC: `clientTrpc.checkout.updateCart`,
  `checkout.updateCartWithPaymentIntent`, `checkout.trackCheckoutClicked`,
  `checkout.trackCheckoutSuccess`; cart identity is a `cartId` held in session storage.
- `OBSERVED` — per-organizer terms gate (`CheckoutCustomTerms.tsx`): a checkbox reading
  `I agree to {eventName}'s Terms of Service.` linking to `/e/{url}/tos` in a new tab, turning
  `border-destructive` when unchecked on submit.
- `OBSERVED` — custom checkout fields of types `input`, `dropdown`, `file_upload`, `checkboxes`
  (`CustomCheckoutField*.tsx`, `parseS3AttendeeCheckoutFileKey` → S3-backed file answers), gated by
  `"eventHasCustomCheckoutFields": false`.
- `OBSERVED` — confirmation is a **dedicated, device-specific screen**:
  `EventPageOrderConfirmationDesktop.tsx` and `EventPageOrderConfirmationMobile.tsx`, driven by a
  `buildReceipt(cartId)` receipt object. `INFERRED` — a separately designed mobile confirmation
  (rather than a responsive one) implies the post-purchase moment is treated as a distinct product
  surface, most likely because it is where the app install is pitched.
- `OBSERVED` — an organizer opt-in prompt renders at confirmation (`{groupName, groupAvi,
  optInOnClick, optOutOnClick}`). `INFERRED` — marketing-consent capture for the organizer's CRM,
  presented after purchase rather than as a checkout blocker.
- `OBSERVED` — checkout flow is instrumented end-to-end: `trackEventView`, `trackCartCreated`,
  `trackInitiateCheckout`, `trackPurchaseAttempt`, `trackPurchaseSuccess`, `trackPurchaseFailed`,
  fanned out to Meta pixel, GA4 (`ga4MeasurementId`) and Google Ads (`googleAdsConversionId`,
  `googleAdsConversionLabels`), with `EventPageFacebookPixelScript` and
  `EventPageGoogleEventsScript` per event.
- `OBSERVED` — Statsig experimentation is live in checkout: `EventPageCheckoutExperimentsInitializer`,
  `useGateValue` / `useDynamicConfig` / `getExperiment`, gates `isCheckoutButtonVariationsEligible`
  and `isHapticsEligible`.

---

## 6. TICKET

Evidence here is mostly from the knowledge base; the ticket UI itself is behind auth and I did not
access it.

`OBSERVED` — `support.posh.vip/en/articles/10723764-accessing-your-event-tickets`:
- App: "Tap the **Ticket** icon (🎟️). Choose either **Upcoming** or **Past**." — a two-segment
  upcoming/past split.
- From a ticket you can: "View event **info**", "Add your ticket to **Apple Wallet**", "Add the event
  to your **calendar**".
- Web: hamburger (☰) → "View your orders" → click the **QR code** icon.
- "your event tickets are also sent to your email right after purchase".
- Apple Wallet date logic: single-day events show the event date; multi-day/recurring show the
  specific valid date; if no validity date is set, Wallet shows the **ticket name** instead (e.g.
  "Saturday GA", "3-Day Pass").
- Door behavior: "When a QR code is scanned, ALL tickets included in that order will appear. The
  doorperson can then select each individual ticket to scan and check in the attendee."
- Known gap, verbatim: "Ticket descriptions are not currently shown on the order or ticket view after
  purchase. If you need to review what your ticket includes, check the live event page."

`OBSERVED` — `…/10723762-how-to-purchase-tickets-with-posh`:
- "If you bought multiple tickets in one order, you'll only see **one QR code**… Your confirmation
  email includes a PDF attachment with all individual ticket QR codes, labeled (for example: 1 of 5,
  2 of 5, etc.)."

`OBSERVED` — the attendee Tickets collection (`support.posh.vip/en/collections/11932357-tickets`)
contains exactly four articles: *How to Purchase Tickets with Posh*, **How to Transfer Tickets**,
*Accessing Your Event Tickets*, **Waitlist & Ticket Returns: A Guide for Attendees**.
`OBSERVED` — the ticket model carries `"isTransferable": true` in the ticket preset.
`OBSERVED` — a full FIFO waitlist engine exists server-side: `WaitlistReconciliationService`,
`getFifoWaitlistEntriesAfterDate`, `getFifoTicketReleasesAfterDate`, `offerTicketsToWaitlistEntry`,
`releaseTicketsPublicly`, `cancelTicketReleases`, `getWaitlistEndOfferDateTime`,
`computeIsWaitlistClosed`, with a reconciliation lock TTL of `9e5` ms (15 minutes).

`INFERRED` — **POSH's answer to resale is a returns-plus-waitlist loop, not a marketplace.** A buyer
who cannot go returns the ticket; it is offered FIFO to the waitlist at face value, and any excess is
released publicly. This is directly relevant to Snatch It: it is the venue-native, first-party
equivalent of secondary supply, with no price discovery and no scalping surface.

`OBSERVED` — I could **not** verify the visual design of the ticket screen: whether the event image
appears on the ticket, the QR's size or framing, or the directions affordance. Do not assume.

---

## 7. NAVIGATION

`OBSERVED` — web header on `/explore-v2` (`data-slot`: `nav-header`, `navbar`, `navbar-start`,
`nav-logo`, `navbar-links-container`, `navbar-end`), logged out:
**Events · Platform · Help · Login · Create event**, plus `aria-label="Notifications alt+T"`,
`aria-label="Open navigation menu"`, `aria-label="Main navigation"`, `aria-label="Go to home"`.

`OBSERVED` — the logged-in account menu, verbatim from the i18n bundle:
```
"asAnAttendee":"As an attendee", "exploreEvents":"Explore Events",
"viewYourOrders":"View Your Orders", "viewProfile":"View Profile",
"accountSettings":"Account Settings", "community":"Community",
"kickback":"Kickback", "admin":"Admin", "manageEventSelects":"Manage Event Selects",
"organizerReferrals":"Organizer Referrals", "logout":"Logout"
```
`OBSERVED` — organizer roles in the same bundle: `"roleOwner":"Owner"` (truncated in capture as
`…ner`), `"roleAdmin":"Admin"`, `"roleHost":"Host"`, `"roleDoorman":"Doorperson"`, `"settings":"Settings"`.

`OBSERVED` — app-install interstitial strings: `"appBannerMessage":"See all events on the Posh® app"`,
`"appBannerCta":"Get the app"`; plus `EventPageDownloadAppCTASection` on the event page.

`OBSERVED` — app-side navigation from the KB and App Store: a **Ticket tab (🎟️)** with
Upcoming/Past, a Profile tab with Settings, and a personalized feed. App deep links are declared:
`al:ios:url = com.poshgroup.POSH://e/odd-mob`, `al:android:package = com.poshgroup.POSH`.

`INFERRED` — depth is shallow: browse → event → checkout is **two taps to a decision**, and tickets
live behind one tab. Web is deliberately the *acquisition and conversion* surface (SEO'd event pages,
`robots: index`, rich OG cards, app-install CTAs at three points) while the app owns retention
(feed, follows, tickets, community). Web discovery is intentionally thinner than app discovery —
the banner says so outright: "See all events on the **Posh® app**".

---

## 8. MOTION

Only evidenced items. Everything here is `OBSERVED` in CSS/JS unless marked.

| Interaction | Evidence | Value |
| --- | --- | --- |
| Image fade-in | `PoshNextImage`: `transition-opacity duration-300` + `opacity-0`→`opacity-100` on load | **300ms** |
| Card reveal | `motion-safe:transition-opacity motion-reduce:transition-none`, `transition-duration:600ms` | **600ms**, reduced-motion aware |
| Ambient background reveal | `transition-opacity duration-500 ease-in-out`, gated on `new Image()` preload | **500ms** |
| Background color swap | `transition-colors duration-300` on the fixed layer | 300ms |
| Ticket accordion | `transition-all duration-300 ease-in-out` on the trigger | 300ms |
| Chip state | `transition-[color,background-color,border-color,box-shadow] duration-200 ease-[cubic-bezier(.25,.46,.45,.94)]` | **200ms, easeOutQuad** |
| Button/link | `transition-colors duration-200 ease-in-out` | 200ms |
| Promo-code trigger | `transition-colors duration-200 hover:text-foreground` | 200ms |
| Total price change | `e0(a, 300)` — hides, waits `t/2`, swaps value, shows | **150ms out / 150ms in crossfade** on the cart total |
| Section entrance | `animate-in fade-in` on `OrderSummaryTable` / `OrderSummarySkeleton` | — |
| Skeletons | `animate-pulse bg-primary/10` | — |
| Carousel | `touch-action:pan-y pinch-zoom`, `select-none overflow-hidden`, `transform-origin:left top`, `will-change:transform`, `aria-label="Previous/Next event"` | drag-scrollable rail |
| Marketing site | GSAP 3.15 + ScrollTrigger + Draggable + InertiaPlugin, and Lenis 1.0.42 smooth scroll | `posh.vip/` only |

`OBSERVED` — **haptics** (`useHaptics`, chunk `1696-…`, module `34482`), gated by Statsig
`isHapticsEligible`:
- On iOS Safari, feature-detects `CSS.supports("selector(input[switch])")` and, if supported, creates
  a hidden off-screen `<input type="checkbox" switch>` + `<label>` pair and programmatically clicks
  the label to fire the **native iOS switch haptic** from a web page.
- Otherwise falls back to `navigator.vibrate`: `hapticTap` = `50`, `hapticSuccess` = `[30,50,50]`,
  `hapticError` = `[300,100,300]`.

`INFERRED` — the iOS switch-haptic trick is a notable amount of effort for a web app, and it is
wired to ticket selection. It is the clearest single signal that POSH treats the *web* event page as
a first-class conversion surface rather than a fallback for the app.

`INFERRED` — the motion system is a **three-speed ladder**: 200ms for anything under the finger
(chips, buttons), 300ms for content swapping in place (images, accordions, totals), 500–600ms for
ambient/atmospheric reveals. Nothing is faster than 200ms and nothing slower than 600ms.

`OBSERVED` — I could not verify page-to-page transitions beyond the presence of a
`PageTransitionWrapper` component and a `Toaster`; sheet/modal choreography
(`EventPageTicketsDialog.tsx`, `EventPageCheckoutAnimatedSection.tsx`) exists by name but I did not
resolve its animation values.

---

## 9. ORGANIZER UX

Public sources only; the dashboard is behind auth and I did not access it.

`OBSERVED` — organizer entity is a **"group"** at `/g/{slug}`, with
```json
{"groupId":…,"groupName":"ELEVENTH HOUSE","groupImage":"https://images.posh.vip/alts/…/610x600.webp",
 "groupUrl":"eleventh-house","isVerified":true,"currency":"USD","currencySymbol":"$",
 "country":"US","connectId":"acct_1SFNTJDrm7nb1B8K","instagram":"eleventh.house",
 "bio":"Welcome Home 🏡"}
```
`INFERRED` — `connectId` is a **Stripe Connect** account: organizers are the merchant of record for
their own sales, with POSH taking a platform fee. Instagram handle is a first-class organizer field.

`OBSERVED` — role model: **Owner · Admin · Host · Doorperson**, plus `roleData` on the event
(`isOwner`, `isTeamMember`, `isOrganizer`, `hasActivityFeedAccess`, `hasActivityFeedInteractAccess`,
`canPostAsOrganizer`).

`OBSERVED` — organizer ticket-editor tooltips, verbatim from the shipped bundle:
> "This is what the customer will see on the event page and the total they will pay including custom
> fees and the Posh processing fee."
> "This is what you will gross from a sale of the ticket, including custom fees."

and a label `"Total (with fees):"`.
`INFERRED` — the ticket-creation form shows **both sides of the fee simultaneously** — buyer-pays and
organizer-grosses — as the organizer types the price. That is a strong, copyable idea: it removes the
single most common pricing mistake in event ticketing.

`OBSERVED` — ticket presets exist in code: `PAID_TICKET_PRESET`, `getPaidTicketPreset`,
`RSVP_TICKET_PRESET` (`{price:0, isTransferable:true, approvalRequired:false,
quantityAvailable: MAX_TICKET_QUANTITY}`).
`INFERRED` — event creation starts from a preset rather than an empty form.

`OBSERVED` — event-type toggles exposed on the event payload, i.e. the shape of the creation form:
`isRSVPEvent`, `isApprovalOnlyRSVPEvent`, `isPersonalEvent`, `displayOnThirdPartySites`,
`isPasswordProtected`, `lightMode`, `paymentPlansEnabled`, `activityEnabled`, `enableEventActivity`,
`guestlistEnabled`, `isDraft`, `showFeesInPrice`, `eventHasCustomCheckoutFields`, `legacyRSVPFlow`,
`attendanceDisplayDisabled`, `longFormAddToCartButton`, `multiDayDisplay`, `displayEndTime`.
`INFERRED` — `showFeesInPrice` being a **per-event organizer toggle** means fee transparency is a
setting, not a platform guarantee — though the ticket-list component overrides it to `true`.

`OBSERVED` — **Kickback**, a promoter/affiliate program: nav item `"kickback":"Kickback"`,
event payload `"kickbackData":{"kickbackCTAText":"Turn Invites Into Income","displayKickbackCTA":false}`,
plus `"organizerReferrals":"Organizer Referrals"`.
`OBSERVED` — the attribution plumbing on every event page: `?t=` tracking link
(`trackingLinkStorageKey`, `isTrackingLinkValueFromPoshMarketplace`), `?a=` affiliate public id
(`AFFILIATE_LINK_KEY_PREFIX`, `LATEST_AFFILIATE_EVENT_ID_KEY`), `?clickref=`
(**`spotify-partnerize-clickref`** — a Spotify Partnerize affiliate integration), and share
attribution params for username / token / OS / source origin. All are captured to session storage
and then **stripped from the URL** via `router.replace(pathname + params, {scroll:false})`.
`INFERRED` — promoter attribution is a core, deeply-built primitive, and the URL is cleaned so the
link a guest re-shares does not carry someone else's affiliate credit. The Spotify Partnerize hook
implies POSH pays out on traffic arriving from Spotify.

`OBSERVED` — check-in: App Store copy "Scan tickets and run the door right from your phone"; the
`Doorperson` role; and the KB door behavior (one order QR expands to its individual tickets). A KB
article titled "Scanning Tickets in Posh: Two Ways to Run Your Event Door" appears in search results
but **404s** at the indexed URL — I could not read it.

`OBSERVED` — Posh University (`posh.vip/university/post/best-ticketing-vip-high-capacity-events`,
published June 2026) states POSH's own feature posture: full custom multi-tier pricing, **limited**
table service, automated comp lists, and **capital advances available**; "Same-night payouts",
"In-person tap-to-pay for walk-up VIP", "Branded event pages justifying premium pricing".
`OBSERVED` — App Store: "creating/selling events with multiple ticket tiers, promo codes, kickback
promotions, and instant payouts".
`OBSERVED` — KB articles exist for "How to Refund Orders, Cancel RSVPs, and Manage Ticket Inventory"
and "Setting Up Affirm Payment Plans for Organizers".

`OBSERVED` — I did **not** verify the dashboard layout, the analytics screens, the attendee/order
tables, or the event-creation flow's visual design. Those are behind auth.

---

## SOURCES

Fetched directly (curl / WebFetch), 2026-09-02:

1. `https://posh.vip/` — marketing home (Webflow)
2. `https://cdn.prod.website-files.com/6979568d54b5ed70e010e8dc/css/posh-606416.webflow.shared.0c9db2301.css`
3. `https://posh.vip/explore` → `https://posh.vip/explore-v2` — discovery (SSR HTML + i18n bundle)
4. `https://posh.vip/consumer-web/_next/static/chunks/3fjb6ce92q-l2.css` — consumer-web design tokens
5. `https://posh.vip/e/odd-mob` — live event page (RSC flight payload)
6. `https://posh.vip/_next/static/css/41b0d7f34d6d9189.css`, `…/9f27f9f172b8ee6f.css` — event-app CSS
7. `https://posh.vip/_next/static/chunks/page-d770a56ea47c3404.js` — `EventThemeBackground`
8. `https://posh.vip/_next/static/chunks/7648-0009ea2fe9b8c172.js` — `SmartCroppedImage`, `OrderSummaryTable`, `EventLayout`, Stripe
9. `https://posh.vip/_next/static/chunks/1696-b233059192278351.js` — ticket group/item, haptics, tracking, waitlist
10. `https://posh.vip/login` — auth entry
11. `https://apps.apple.com/us/app/posh-create-find-events/id1556928106` — App Store listing (v8.21.0)
12. `https://support.posh.vip/en/articles/10723764-accessing-your-event-tickets`
13. `https://support.posh.vip/en/articles/10723762-how-to-purchase-tickets-with-posh`
14. `https://support.posh.vip/en/collections/11932357-tickets`
15. `https://posh.vip/university/post/best-ticketing-vip-high-capacity-events`

Event pages discovered on `/explore-v2` (16 unique, used to confirm the card contract):
`/e/odd-mob`, `/e/we-belong-here-central-park-2026`, `/e/move-fest-2026`, `/e/gap-festival-1`,
`/e/fine-wine-festival-nyc`, `/e/the-afro-plus-festival`, `/e/souled-out-dates-fest-2026`,
`/e/atlanta-dukes-and-boots-festival-2026`, `/e/strangersnfriendsnyc`, `/e/soundwavs-at-the-park`,
`/e/sol-at-1-hotel-september-6th-2026`, `/e/the-social-club-the-white-party-1`,
`/e/the-biggest-labor-day-party-ever-4`, `/e/remember-the-times-90s-and-2000s-party-in-the-park-1`,
`/e/after-brunch-presents-5-anniversary`,
`/e/karol-g-official-after-party-w-daiky-damboa-fri-sept-18th-ikon-new-york`.

Not verified (stated so it is not assumed): the ticket/QR screen design, the attendee-avatar social
proof treatment, the organizer dashboard and analytics, the event-creation flow, the check-in app,
the multi-photo gallery layout, sheet/modal animation values, and the exact fee subtext string.

---

## WHAT POSH DOES WELL

1. **One image contract, enforced everywhere.** 4:5 portrait — card, hero, component default. It
   matches the ratio nightlife flyers are already exported at, so organizers' existing art fits with
   no re-work. `OBSERVED`.

2. **It never mangles a poster and never breaks the grid.** `SmartCroppedImage` locks the frame at
   0.8, and when the artwork does not fit it fills the gap with a `blur(54px) scale(1.2)` copy of the
   same image and feathers the real edges into it with a 5%/95% mask. Uniform grid *and* intact art —
   most products have to choose. `OBSERVED`.

3. **Every event page is color-graded by its own poster.** The flyer at 2000px, painted across the
   top third of a fixed layer at `100% 5%`, masked to transparent, `backdrop-blur-md`, under a
   33%→77% scrim, faded in over 500ms after preload. This is the premium feeling, and it costs the
   organizer nothing. `OBSERVED`.

4. **Text never sits on the artwork.** All metadata is below or beside the image. Removes the entire
   class of legibility failures that come from user-supplied imagery. `OBSERVED`.

5. **Hierarchy from size and color, never weight.** Card titles are weight 400 — identical to the
   metadata — differentiated only by 16px-vs-12px and foreground-vs-muted. The poster stays the
   headline. `OBSERVED`.

6. **One typeface, two optical sizes.** Licensed Neue Haas Grotesk Display + Text, self-hosted, used
   across three separate codebases. Neutral enough that it never competes with the flyers.
   `OBSERVED`.

7. **Bounded organizer customization.** One accent color (light/dark variants), one optional title
   font with silent fallback, cover-vs-fit, one song, one video. Every page feels owned; none can be
   made ugly. `OBSERVED`.

8. **The fee row is collapsed but never hidden.** "Fees" with its amount always visible, expanding to
   an itemized breakdown; single-fee events degrade to a named row with a tooltip. `OBSERVED`.

9. **The organizer sees both sides of the price as they type it.** "what the customer will see… and
   the total they will pay" alongside "what you will gross". `OBSERVED`.

10. **Returns + FIFO waitlist instead of a resale market.** A full reconciliation service that offers
    returned tickets to the waitlist in order and releases the excess publicly. `OBSERVED`.

11. **Lineup is resolved from Spotify, not typed.** Artist name, official photo, link and popularity
    all inherited. Correct, on-brand artist imagery with zero promoter effort. `OBSERVED`.

12. **A disciplined three-speed motion ladder** (200 / 300 / 500–600ms), reduced-motion aware, plus
    real haptics on iOS web. `OBSERVED`.

13. **Attribution is a first-class primitive** — tracking links, affiliate ids, share tokens,
    Kickback ("Turn Invites Into Income") — and the params are stripped from the URL after capture.
    `OBSERVED`.

---

## WHAT SNATCH IT SHOULD LEARN (without copying)

Reinterpret the *principles*. Do not copy POSH's markup, class names, assets or type stack. Snatch It
already owns a measured brand system — Oswald/Inter, `#FF1A1A`, radius 0 (see
`web/docs/brand-system.md`) — and these should be expressed *through* it, not replaced by it.

**IMAGERY — do these first, they carry the most weight**

1. **Adopt a single locked 4:5 portrait image contract across RN and web.** One ratio, one frame,
   everywhere: discovery card, event hero, ticket, share card. `INFERRED` rationale: it is what
   venue and promoter artwork is already exported at, so first-party venue onboarding stops
   requiring an art request. Concretely: 224×280 in a 240px rail slot is a proven card size; use it
   as the starting point and adjust to Snatch It's grid.

2. **Build the equivalent of `SmartCroppedImage` and make it the only image primitive.** Lock the
   `AspectRatio` at 4:5; default to `cover`; when the venue's art has a different natural ratio,
   switch to `contain` and fill the remainder with a heavily blurred, slightly scaled copy of the
   same image, feathering the real edges with a `transparent → 5% → 95% → transparent` mask on the
   slack axis. Measure `naturalWidth/naturalHeight` on load to pick the axis. **Never render a black
   letterbox bar.** Give the venue a cover/fit toggle, as POSH gives organizers `setFlyerToCover`.

3. **Derive the event page's ambient background from the event's own artwork.** This is the single
   highest-leverage change and it is entirely reimplementable in Snatch It's own idiom. The recipe
   that works: fixed full-viewport layer → the artwork at ~2000px across the top third,
   `background-size: cover`, off-center anchor → mask fading to transparent downward → ~12px backdrop
   blur → a downward scrim from ~33% to ~77% of the page background → fade the whole band in over
   ~500ms *after* an off-screen preload resolves. `INFERRED` — Snatch It's `#FF1A1A` should remain
   the *action* color (CTA, focus, live states) while the ambient wash comes from the artwork;
   flooding a red brand color behind every event would make every event look like Snatch It instead
   of like itself, which is precisely the trap POSH avoids.

4. **Never set platform text over venue artwork.** Caption below or beside, always. This is what
   makes arbitrary third-party art safe to accept.

5. **Preserve animation in uploads.** POSH ships `anim=true` on every card transform because promoter
   flyers are frequently GIFs. Whatever CDN Snatch It uses, do not flatten animated artwork to a
   still frame on resize.

6. **Use `fit=scale-down` semantics — never upscale a venue's image.** A small flyer should render
   small and sharp, not large and mushy. Pair it with a stored BlurHash (POSH stores
   `flyerBlurHash` on the event record) as the placeholder, and a ~300ms opacity fade on decode.
   Skeletons (`animate-pulse`), never spinners.

7. **Make the hero artwork sticky on desktop.** POSH sticks the flyer at `top-20`, not the ticket
   widget. `INFERRED` — this keeps the event's identity on screen through the whole scroll and is
   cheap to implement.

**TYPOGRAPHY**

8. **Stop bolding event titles on cards.** Create card hierarchy with size and color only —
   16px foreground title over 12px muted metadata, all at the same weight. In Snatch It's system that
   means Inter 400 at two sizes and two opacities, and reserving Oswald for surfaces where Snatch It
   *should* dominate (checkout totals, ticket credential, section headers) rather than on top of
   venue artwork. `INFERRED` — Oswald is a condensed display face with far more personality than Neue
   Haas; using it at card-title size will fight the poster, which is exactly the failure mode POSH
   engineered around.

9. **Give the event title room.** POSH sets the `h1` at 48px with **80px** of vertical margin on
   desktop and `text-balance`. The whitespace does as much work as the size.

10. **Use non-breaking spaces inside date/time strings** so "Fri Sep 4" never wraps mid-token, and
    keep venue-above-time ordering (venue at weight 600, time at 400, same size).

11. **Reserve weight 700 for one thing: the amount the buyer pays.** In POSH it appears exactly once,
    on the checkout total.

**DISCOVERY**

12. **Ship curated horizontal rails before you ship search.** POSH's web discovery has *no event
    search box* — only a city search. `INFERRED` — for a venue-native product with a small
    early catalogue, two curated rails plus Location/Date/Price will outperform a search box that
    mostly returns nothing. Copy the filter shape: `Nearby` + a short list of *named launch markets*
    (POSH hard-codes six cities), `Today / This week / This month / Any`, and a single-ended
    `Up to $X`.

13. **Adopt the card data order verbatim as an information-architecture decision** — image → venue or
    promoter (small, muted, with a verification mark) → title → `{price} at {venue}` on one line →
    date/time → lineup chips. Note that POSH puts the *organizer above the title*. For Snatch It
    moving to venue-native ticketing, **the venue belongs in that slot** — it is the trust anchor,
    and elevating it is exactly the repositioning Snatch It is making.

14. **Do the invisible-measurement trick for chip overflow** (lay out a hidden copy, count what fits,
    render `+N`) rather than guessing a fixed chip count.

**CHECKOUT AND FEES**

15. **Fix the gap POSH left open — this is a differentiator, not a copy.** POSH's card advertises
    `$25.00` while `minPriceWithFees` is `$29.24`, despite marketing that promises "upfront pricing…
    no surprises". **Snatch It should show the all-in price on the discovery card**, not just at
    checkout. Given Snatch It's P2P-resale heritage, price honesty at the moment of browsing is the
    most credible thing it can claim, and it costs one field.

16. **Copy the fee accordion pattern exactly in spirit:** a row always labelled "Fees" with the
    amount visible, expanding to itemization; degrade to a single named row with a tooltip when there
    is only one fee. Then: sales tax row, promo code accordion, separator, bold total.

17. **Show venues both sides of the price in the ticket editor** — "what the buyer pays" and "what
    you gross" — updating live as they type. Directly transferable, and it prevents the most common
    venue pricing error.

18. **Sticky mobile CTA as a full-width pill over a bottom-up gradient scrim**, and keep the disabled
    state fully opaque (`opacity-100` with a muted fill) so "Sold out" stays legible.

19. **Confirm payment in-page** (`redirect: "if_required"`) and design the order confirmation as its
    own screen, not a responsive afterthought — it is where the app install and the follow are won.

**TICKETS AND SUPPLY**

20. **Build returns + FIFO waitlist as the first-party answer to resale.** This is the most strategically
    important idea in this document for Snatch It. POSH runs a real reconciliation service — returned
    tickets are offered to the waitlist in order, with an offer deadline, and excess is released
    publicly. It gives a buyer who cannot attend a clean exit and a sold-out buyer a fair entry, at
    face value, with the venue in control. Snatch It already owns the transfer and inventory
    primitives; this is the venue-native product they should power.

21. **Fix the two gaps POSH admits in its own help center.** (a) "If you bought multiple tickets in
    one order, you'll only see one QR code" — the other tickets are only in an emailed PDF. Snatch It
    should render **one scannable credential per ticket** in-app, swipeable, from the start.
    (b) "Ticket descriptions are not currently shown on the order or ticket view after purchase" —
    carry the tier description onto the ticket so a VIP holder can see what they bought at the door.

**THINGS TO DELIBERATELY AVOID**

- **Do not copy the browse-price-excludes-fees inconsistency** (§5). It is POSH's clearest
  self-contradiction and Snatch It's easiest win.
- **Do not thin out mobile-web discovery to force the app.** POSH gates trending on location, hides
  lineup chips below `md`, ships no event search, and runs three separate "get the app" prompts.
  Snatch It is earning venue trust; a venue's shared link must be fully useful to a guest who will
  never install the app.
- **Do not build a per-event `showFeesInPrice` toggle.** POSH made fee transparency an organizer
  setting and then had to hard-code `true` in the ticket component to guarantee it. Make it a
  platform invariant instead of a preference.
- **Do not let organizer customization reach the background by default.** POSH ships
  `applyAccentColorToBackground` as an option; the good-looking default is `false`, with the artwork
  doing the tinting. Keep the escape hatch closed unless a venue has a real brand reason.
- **Do not adopt POSH's neutral-grotesque restraint wholesale.** It works because POSH has no visual
  identity of its own by design. Snatch It *does* have one. The lesson is *where* to be neutral —
  next to venue artwork — not to become neutral everywhere.
- **Do not chase the marketing site's GSAP/Lenis smooth-scroll layer.** It is on the Webflow brochure
  page only; the product surfaces use plain CSS transitions in a 200/300/600ms ladder. Match the
  product, not the brochure.

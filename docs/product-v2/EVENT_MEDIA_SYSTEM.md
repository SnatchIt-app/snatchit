# Event media system

**Status:** proposal, pending owner approval. Nothing here is built.
**Evidence base:** `docs/product-v2/_research/media_current_state.md` (full current-state trace),
`docs/product-v2/MARKETING_BRAND_EXTRACTION.md` (live brand measurement), and direct inspection of
the live production asset.

This is the highest-impact document in the redesign. Event artwork is the product surface a
customer judges Snatch It by, and today it is the weakest thing in the app.

---

## 1. The problem, in numbers

One production cover image, `1173x609` (**1.926:1 landscape**), is currently poured into six
different containers across three surfaces:

| Surface | Container ratio | Of the source, discarded |
|---|---|---|
| Marketing site card | 0.799:1 | **58.5%** |
| Square thumbnails | 1.000:1 | **48.1%** |
| Web card | 1.333:1 | 30.8% |
| Bids card | 2.557:1 | 24.7% of height |
| Mobile detail | 1.773:1 | 8.0% |
| Home card | 1.989:1 | 3.2% of height |

It gets worse with the artwork nightlife promoters actually make. A 9:16 story flyer loses **71.7%**
in the home feed and **78.0%** in the bids card. A 4:5 Instagram flyer loses **59.8%** and **68.7%**.
Nobody chose these losses. They are the arithmetic of pouring one asset into six boxes with
`cover` and no focal point.

Seven more defects compound it:

1. **No image transformation exists anywhere.** Width, quality and format parameters appear zero
   times in the repository. The largest live object is **6,361,057 bytes** and it is shipped whole
   into a 358x180pt card.
2. **Cache headers are wrong by four orders of magnitude.** Uploads set `cacheControl: '3600'` on
   immutable timestamped paths. It should be a year.
3. **The upload contracts contradict each other.** Mobile forces a 16:9 crop; web crops nothing at
   all while previewing the result as a square. The live asset matches neither, which proves the
   uncropped web path is what actually ships.
4. **There is no way to change a cover.** No edit screen touches it. The only remedy is deleting
   the listing.
5. **Dark artwork dissolves into the app.** There are zero gradients or scrims over images
   anywhere, and nightlife photography is low-key on a near-black canvas.
6. **Failure handling is effectively absent.** One of twenty-four image elements has an `onError`
   handler. There are no blur placeholders, no cache policy, and no recycling keys, so three lists
   flash stale images while scrolling.
7. **Native events will render blank.** `market.listing_unified` hard-codes
   `null::text as cover_image_path` for the native arm (`089_market_bridge_view_and_late_fk.sql:72`),
   so every venue-direct event shows no image the moment the flag flips. There is also **no
   event-media storage bucket in the entire system**, and `catalog.venue` has no media column at all.

---

## 2. Principles

1. **Portrait is the source of truth GOING FORWARD, and cannot be applied retroactively.**
   Nightlife artwork is made for Instagram: it arrives 4:5 or 9:16, not 16:9. A portrait master
   crops down to square and landscape gracefully; a landscape master cannot be made portrait
   without destroying it.

   **The correction an adversarial review forced (finding J-7):** the mobile picker performs a
   *destructive* 16:9 crop at upload, so for every existing listing the portrait pixels were never
   stored and cannot be recovered. A 4:5 frame is therefore right for new venue-supplied artwork and
   wrong as a migration for the existing corpus. On migration day, existing covers must render in a
   frame that does not re-crop them, or with the contain-plus-blur fallback below. Do not present
   4:5 as a system-wide switch; it is the target for new uploads, with an explicit legacy path.
2. **One upload, many derivatives.** An organizer uploads once. The system produces every
   placement. Optional extra assets are an enhancement, never a requirement.
3. **The crop is authored, not accidental.** Every asset carries a focal point. Cropping preserves
   the subject rather than the geometric centre.
4. **Nothing is shipped at full size.** Every request is width-negotiated, format-negotiated and
   quality-capped.
5. **Artwork is shown at full strength.** The marketing site dims photography to 8 to 22% because
   it is a backdrop. In the product it is the merchandise. Dimming happens only under text.
6. **Every image has a defined failure appearance.** Missing, slow, dark, tiny and wrong-format
   each have a specified result.

---

## 2b. What the benchmarks actually do (and why it validates 4:5)

Both benchmark platforms solved this exact problem, and their solutions were read from shipped code
rather than inferred. See `_research/posh.md` and `_research/dice.md` for the full evidence.

**POSH locks a 4:5 frame and lets the organizer choose crop or fit.** Its image component frames
every flyer at `ratio = 0.8`. When the organizer sets cover, it crops. When they do not, the image
switches to `contain` and the empty area is filled with **a blurred, 1.2x-scaled copy of the same
flyer** at `blur(54px)`, with the real image's edges feathered into it by a gradient mask along
whichever axis has slack. There are no black letterbox bars anywhere in that system. This is how it
gets a perfectly uniform grid and never decapitates a poster's typography. It is the single best
idea available to us, and it is directly applicable because POSH is the closest analogue to Snatch
It's content: party flyers with type in them.

**DICE normalizes to a square master and derives deterministically.** It centre-crops every upload
to a square, stores the crop rectangle, and derives exactly three canonical crops from it. Its CDN
width is literally the same number as the CSS box, and **quality halves as pixel density doubles**
(quality 80 at 1x, 40 at 2x), which holds bytes flat across devices. Image slots are pre-painted a
flat colour with intrinsic dimensions declared, so there is no flash and no layout shift.

The two choices differ because the content differs: DICE carries artist photography, which survives
a square crop; POSH carries portrait flyers, which do not. **Snatch It's content is flyers.** That
settles the master ratio at 4:5, and it means we take POSH's framing model and DICE's delivery
discipline.

---

## 3. The asset model

### 3.0 Fit mode, chosen per asset

Every asset carries a **fit mode**, set by the uploader and defaulting to `cover`:

- **`cover`** crops to the frame using the focal point. Correct for photography and for flyers whose
  edges carry no information.
- **`contain`** fits the whole image inside the frame and fills the remaining area with a blurred,
  scaled copy of the asset itself, with the image's edges feathered into that backdrop. Correct for
  a poster whose lineup type runs to the edge.

Never letterbox with black bars. The blurred-self backdrop is what makes `contain` acceptable in a
uniform grid, and it costs one extra low-resolution request.

### 3.1 Primary asset (required)

| Property | Value |
|---|---|
| Ratio | **4:5 portrait** |
| Minimum | 1080 x 1350 |
| Recommended | 1440 x 1800 |
| Maximum file | 8 MB before processing |
| Accepted | JPEG, PNG, WebP |
| **Rejected** | HEIC, HEIF |
| Focal point | normalized `{x, y}`, default `{0.5, 0.4}` |

HEIC is rejected deliberately. It is accepted end to end today and cannot be displayed by Chrome or
Firefox, which is a latent outage waiting for the first iPhone-native upload to reach a web user.
Convert on device, or refuse with a clear message.

The default focal point sits above centre because event flyers put the headline act in the upper
half.

### 3.2 Optional assets

| Asset | Ratio | Minimum | Used by |
|---|---|---|---|
| Landscape hero | 16:9 | 1920 x 1080 | Event hero on wide screens, venue dashboard headers |
| Square | 1:1 | 1080 x 1080 | Share cards, dense grids |
| Venue photo | 16:9 | 1920 x 1080 | Venue pages |

When an optional asset is absent, the slot derives from the primary using the focal point. This is
the rule that keeps the product working for a venue that uploads one flyer and nothing else.

### 3.3 Whether organizers should upload per-placement assets

**Yes, but only as an optional enhancement, and only for two slots: the landscape hero and the
share card.** The reasoning is not that competitors do it. It is that a 4:5 flyer genuinely cannot
fill a 16:9 hero on a tablet or a desktop dashboard without either heavy letterboxing or a crop
that decapitates the headline act. Every other slot derives acceptably.

Requiring more than one asset would be a mistake. The venues Snatch It is courting are Miami clubs
and promoters, not marketing departments. The upload flow must succeed with one image.

---

## 4. Slot specifications

Every slot below is normative. `Fit` is `cover` unless stated. All corners are square, per the
brand.

| Slot | Ratio | Mobile | Tablet | Web | Scrim | Notes |
|---|---|---|---|---|---|---|
| **Discovery card** | 4:5 | 168 x 210 (2-up) | 220 x 275 | 260 x 325 | bottom 35% | The feed unit. Text sits **below** the image, never on it. |
| **Featured event** | 3:2 | full-bleed x 240 | x 320 | x 420 | bottom 55% | Title and date over the image. One per rail. |
| **Event hero** | 4:5 mobile, 16:9 wide | full-bleed x 460 | 16:9 | 16:9 capped 560 | bottom 45% | Uses the landscape asset when present. |
| **Event detail gallery** | 4:5 | 300 x 375 carousel | 340 x 425 | 380 x 475 | none | Only when extra assets exist. Never a carousel of one. |
| **Search result** | 1:1 | 64 x 64 | 72 | 80 | none | Dense list. Recognition, not persuasion. |
| **Ticket view** | 16:9 | full-bleed x 180 | x 220 | x 240 | bottom 70% | A strip. The credential is the hero here, not the artwork. |
| **Order / receipt** | 1:1 | 56 x 56 | 64 | 64 | none | Identification only. |
| **Venue dashboard thumb** | 1:1 | n/a | 48 | 56 | none | Operator scanning a list. |
| **Venue hero** | 16:9 | full-bleed x 200 | x 280 | x 360 | bottom 50% | Venue photo asset, falls back to a solid surface. |
| **Promoter share** | 1:1 and 9:16 | generated | generated | generated | brand plate | Rendered server-side with the wordmark. Dark rail, spec only. |

**Why 4:5 for discovery.** It matches the shape venues actually supply, so new artwork loses
nothing. It gives each event more vertical presence in a scrolling feed than a 16:9 card, and it
lets two cards sit side by side on a phone while still showing a readable image. Legacy 16:9 covers
in this frame use the contain-plus-blur fallback rather than a second destructive crop.

**Why the ticket view is 16:9.** On a ticket the artwork is context, not merchandise. The QR code
and the entry details own the screen.

---

## 5. Delivery

### 5.1 Transformation

Use Supabase image transformations on every request. This is operational configuration and needs no
migration.

```
/storage/v1/render/image/public/<bucket>/<path>?width=<w>&quality=75&format=origin
```

- `width` comes from the slot table multiplied by the device pixel ratio, capped at 2x. **The CDN
  width and the layout token must be the same number**, not approximately the same.
- `quality` scales inversely with density: 80 at 1x, 45 at 2x. Doubling the pixels while halving the
  quality holds the byte count roughly flat, which is why a retina card need not cost twice as much.
- Pre-paint every image box with the surface colour and declare intrinsic width and height, so the
  layout never shifts and no flash occurs before decode.
- Serve modern formats through content negotiation; never send a 6 MB original.
- Generate a `srcset` on web at 1x and 2x.

### 5.2 Caching

Set `cacheControl: '31536000, immutable'` on upload. Paths are already timestamped and therefore
immutable, so the current one hour value is wrong by 8,760x. A cover change writes a new path.

### 5.3 Loading

1. Reserve the exact box before the image arrives, so nothing reflows.
2. Fill with a skeleton at the surface value, pulsing per the design system.
3. Fade in over 180ms.
4. Set a recycling key on every list image so a reused row never shows the previous event's art.

---

## 6. Failure appearance

| Case | Behaviour |
|---|---|
| Missing or deleted object | Branded fallback: solid `#0A0A0A` plate, the wordmark at 20% opacity, and the event's initial in Oswald. Never a broken-image glyph, never an empty box. |
| Slow network | Skeleton, then fade. No spinner on top of an image. |
| Very dark artwork | The mandatory scrim plus a 1px `line-neutral` hairline around the image box so its edge stays visible against the black canvas. |
| Very bright artwork | The scrim carries text; text never sits on an unscrimmed image. |
| Below minimum dimensions | Accept, but never upscale beyond 1.5x. Beyond that, letterbox on the surface colour rather than blur up. Warn the organizer at upload. |
| Wrong aspect | Derive with the focal point. Extreme ratios beyond 3:1 or below 1:2.5 are letterboxed, not cropped to nothing. |
| Rejected format | Refuse at upload with a plain sentence naming the accepted formats. |

The current placeholder branch is dead code, because `cover_image_path` is `NOT NULL` and the URL
builder returns a live-looking URL for any string. The fallback must key off a load error, not off
a null path.

---

## 6b. Ambient theming from the artwork itself

The event page should take its ambient colour from the event's own flyer, not from Snatch It red.

Mechanism, adapted from the benchmark: paint the event's artwork into a fixed layer behind the
page, positioned high, occupying roughly the top third, heavily blurred, masked with a gradient to
transparent, then covered with a scrim from the canvas colour at about 33% to about 77%. Preload the
image and fade the layer in only once it has decoded, so a page never flashes.

Why this matters more for Snatch It than for anyone else: venue-native ticketing means third-party
artwork of wildly varying quality arrives from clubs and promoters. This technique makes every event
page feel art-directed with **zero effort from the venue**, which is precisely the problem the
venue-native product creates.

**The constraint that comes with it:** red is the action colour, not the ambient colour. If Snatch It
red also tints the page background, every event looks like Snatch It instead of looking like itself.
Let the poster own the ambience; keep `#FF1A1A` for what the user can tap.

## 7. Text over imagery

Only three slots put text on an image: featured event, event hero, ticket view.

- Scrim is `linear-gradient(180deg, rgba(0,0,0,0) 35%, rgba(0,0,0,0.85) 100%)`.
- Text sits in the bottom 40% of the box, never centred over the subject.
- Event titles over artwork use Oswald display, white, with no text shadow. The scrim does the work.
- Never place a price on artwork. Prices belong on a solid surface where they are unambiguous.

---

## 8. What must change in the database

Classified per the freeze rules. Migrations 076 to 092 are immutable; this is 093+ work.

| # | Change | Classification |
|---|---|---|
| 1 | Create an `event-media` storage bucket with size and MIME constraints | **OPERATIONAL CONFIG** plus a migration for the bucket row |
| 2 | `catalog.event_media` table: event, slot, path, ratio, width, height, focal x/y, uploaded_by | **IMPLEMENTATION FOLLOW-UP (093+)** |
| 3 | `venue` media column or `venue_media` table | **IMPLEMENTATION FOLLOW-UP (093+)** |
| 4 | Write RPCs for attaching and replacing media, authority `venue_manager` / `venue_marketing` | **IMPLEMENTATION FOLLOW-UP (093+)** |
| 5 | Constrain `catalog.event.hero_image_ref`, which is today an unvalidated `text` column written verbatim and readable by `anon` | **POST-FREEZE AMENDMENT** |
| 6 | Fix `market.listing_unified`'s native arm, which hard-codes a null cover (`089:72`) | **POST-FREEZE AMENDMENT** |
| 7 | Supabase image transformation enablement | **OPERATIONAL CONFIG** |
| 8 | Media moderation policy, and whether a reseller may override venue artwork | **OWNER POLICY DECISION** |

Item 6 is an activation blocker, not a nicety: without it every venue-direct event appears in
discovery with no artwork at all.

---

## 9. Implementation order

1. Turn on transformations and fix cache headers. No migration, immediate bandwidth win.
2. Ship the media components: `EventImage` with slot, focal point, scrim, skeleton, fallback and
   recycling key. One component, ten configurations.
3. Unify the upload contract on the 4:5 master with a focal-point picker, replacing the two
   contradictory crop paths.
4. Add cover editing, which does not exist today.
5. Land the 093 media schema so venue events can carry real artwork.
6. Fix the native arm of the discovery projection before the flag flips.

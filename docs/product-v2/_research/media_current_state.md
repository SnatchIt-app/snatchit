# Event Imagery — Current State of Truth

**Agent H · Product V2 research · branch `feature/venue-native-and-product-v2`**
**Repo:** `/Users/josetascon/snatchit-consol` · **Date:** 2026-09-02
**Scope:** evidence base only. The replacement system is specified by another pass.

Every claim below is cited to `file:line`. Numbers marked *(measured)* come from the
repo, the frozen migration chain, or a live production census recorded in
`supabase/migrations/073_storage_bucket_upload_constraints.sql`. Numbers marked
*(derived)* are arithmetic on those measured values.

---

## 0. The one-paragraph version

Snatch It has no event media *system*. It has one nullable `text` column on
`public.listings` (`cover_image_path`), one public bucket, five upload call sites, and
**eleven independent render sites across three codebases that each invent their own
aspect ratio** — 1:1, 4:3, 16:9, 1.99:1, 2.56:1 and 0.80:1 — all applying `cover`
cropping to the same single asset. Nothing resizes, nothing transcodes, nothing
declares a focal point, nothing measures the image, nothing handles a load failure,
and nothing tells a seller what shape their image will be seen in. The venue-native
rail (migrations 076–092) is worse: `catalog.event.hero_image_ref` is an unvalidated
`text` column pointing at a bucket **that does not exist**, and the unified market
view hard-codes `null` for every native listing's cover.

---

## 1. Executive summary — what is actually wrong, ranked by user impact

### P0 — 1. The same image is cropped to six different aspect ratios; up to 58% is thrown away

One asset, `cover_image_path`, is rendered into containers ranging from **0.80:1
(portrait)** to **2.56:1 (ultra-wide)**. With `object-fit: cover` / `contentFit="cover"`
and no focal point, the crop is always center-anchored. The real production cover
`.../covers/1783029690066.jpg` is **1173×609 = 1.926:1** *(measured, live)*.

| Surface | Container ratio | Source content discarded *(derived)* |
|---|---|---|
| snatchitapp.com card (out of repo) | 0.799:1 | **58.5% of width** |
| Explore / profile / account thumbs | 1.000:1 | **48.1% of width** |
| Web card + web listing detail | 1.333:1 | **30.8% of width** |
| Mobile "My bids" card | 2.557:1 | **24.7% of height** |
| Mobile listing detail hero | 1.773:1 | 8.0% of width |
| Mobile home feed card | 1.989:1 | 3.2% of height |

Faces, headliner names and date blocks — the entire reason a nightlife flyer exists —
sit off-center. Center-cropping a flyer at 48–58% is not a rendering nit; it destroys
the product's primary trust signal.

### P0 — 2. Zero image transformation exists on two of the three delivery surfaces

Every mobile image and every marketing-site image is fetched as the **raw stored
object**:
`https://<project>.supabase.co/storage/v1/object/public/auction-media/<uid>/covers/<epoch_ms>.<ext>`
(`web/src/lib/env.ts:91`, `web/src/lib/format.ts:141-147`, `src/lib/coverImage.ts:71`).

- Supabase's transform endpoint (`/storage/v1/render/image/public/...?width=&height=&quality=&format=`) appears **0 times** in the repo *(measured — grep across `src/ app/ web/src/ packages/ supabase/`)*.
- `next/image` optimization is configured (`web/next.config.ts:66-83`) and is the **only** resizing anywhere. It covers 5 of 11 event-image render sites.
- Verified against the live marketing site: it is **not** the Next app in `web/` — no `/_next/` assets — and it hotlinks the raw Supabase object with no transform parameters. It is a **third, out-of-repo consumer of the production bucket** with no contract.
- The largest live object in `auction-media` is **6,361,057 bytes** *(measured, `073:110`)*. A mobile home feed of 8 cards can therefore pull tens of MB to paint 8 boxes of 358×180 pt.

### P0 — 3. `Cache-Control: max-age=3600` on immutable, content-unique objects

Every upload sets `cacheControl: '3600'` (`src/hooks/useImageUpload.ts:185`,
`src/lib/avatarImage.ts:150`, `web/src/lib/create-listing.ts:74`). Paths are unique by
`Date.now()` and written with `upsert: false` (`useImageUpload.ts:161,184`), so an
object at a given URL **can never change**. A 1-hour TTL on an immutable URL is
**8,760× shorter than correct** *(derived vs. `max-age=31536000, immutable`)*. Every
returning user re-downloads every cover every hour, on cellular.

### P1 — 4. The mobile crop contract and the web crop contract disagree, and the shipped asset obeys neither

- Mobile forces a **16:9 (1.778:1)** picker crop: `aspect: [16, 9]` (`src/screens/CreateListingScreen.tsx:192`, default at `src/hooks/useImageUpload.ts:78`), labelled "JPG or PNG · 16:9 recommended" (`CreateListingScreen.tsx:721`).
- Web performs **no crop at all** — the raw `File` is uploaded byte-for-byte (`web/src/lib/create-listing.ts:66-75`).
- Web's *preview tile* is `aspect-square` with `object-cover` (`web/src/components/sell/CreateListingForm.tsx:378-381`) — so the seller previews a **1:1** crop of an image that web will actually render at **4:3** and mobile at **1.99:1**. The preview is actively misleading.
- The real production cover is **1.926:1**, which is neither 16:9 nor square — proof that live covers are arriving through the uncropped path.

### P1 — 5. A seller can never fix a bad cover

`app/listing/edit/[id].tsx` edits exactly four fields — `eventName`, `venue`,
`restrictions`, `ticketPlatform` (`app/listing/edit/[id].tsx:84-87`, update at `:153`).
There is **no image field on any edit surface, mobile or web**. The only remedy is
deleting the listing (`src/screens/ListingDetailScreen.tsx:905-931`), which destroys
the auction and its bids.

### P1 — 6. A broken image renders as an invisible hole, not a placeholder

Every listing render site has a `coverUrl ? <Image/> : <Placeholder/>` ternary, but
`getCoverImageUrl` returns a URL for **any** non-empty string
(`src/lib/coverImage.ts:54-73`) and `listings.cover_image_path` is `not null`
(`supabase/migrations/000_baseline_schema.sql:98`). The placeholder branch therefore
**almost never fires**. A deleted, moved, or 400-ing object produces a transparent box
on `#0B0F14` (`src/theme/index.ts:7`). **`onError` appears on exactly one of 13 mobile
image elements** — `ProofImageViewer.tsx:140` — and on none of the 11 cover sites
*(measured)*.

### P2 — 7. No loading state on any image: no blur-up, no placeholder, no transition, no recycling key

Across all 24 in-repo image elements, `placeholder=` (blurhash/thumbhash) appears
**0 times**, `cachePolicy` **0 times**, `recyclingKey` **0 times**, and `transition=`
exactly once — on the upload preview (`src/components/ImageUploadTile.tsx:101`)
*(measured)*. The home feed has a three-card skeleton for the *initial query*
(`app/(tabs)/home.tsx:650-661`, `skeletonImage` 180 px, `:876`) but nothing per-image:
after data arrives, cards paint with empty rectangles that pop. Missing `recyclingKey`
on `FlatList`-recycled `expo-image` is a known wrong-image-flash class in
`home.tsx:168`, `bids.tsx:207`, `explore.tsx:143`.

### P2 — 8. Dark images bleed into a dark UI; nothing controls tone

`LinearGradient` and `gradient` appear **0 times** in `app/`, `src/`, `components/`
*(measured)*. There is no scrim, no vignette, no minimum-contrast treatment. The card
ground is `#11161C` and the app ground is `#0B0F14` (`src/theme/index.ts:7-8`).
Nightlife photography is predominantly near-black; the image/card boundary simply
disappears. The only tone control in the entire product is on *decorative* landing
backgrounds — `opacity-[0.08]` / `opacity-10` plus `bg-black/30 mix-blend-multiply`
(`web/src/app/page.tsx:82, 157`) — i.e. applied to the images that don't matter.

### P2 — 9. `image/heic` is accepted end-to-end and cannot be displayed by browsers

`auction-media` allows `image/heic` (`supabase/migrations/073:110`,
`000_baseline_schema.sql:248`), `APP_CONFIG.ALLOWED_IMAGE_TYPES` includes it
(`packages/core/src/appConfig.ts:26`), and the web file input explicitly advertises it
(`web/src/components/sell/CreateListingForm.tsx:387`). Chrome and Firefox cannot
render HEIC, and Next's Sharp-based optimizer does not decode it by default. Live
census: 111 `image/jpeg` + 23 `image/png`, **0 HEIC** *(measured, `073:110`)* — the
defect is latent, not yet fired, and one iOS-Safari web seller trips it.

### P3 — 10. No dimension floor, no dimension ceiling, no measurement stored anywhere

`validateImage` checks **size and MIME only** (`src/utils/validateImage.ts:8-33`);
`uploadListingImage` checks **type and size only** (`web/src/lib/create-listing.ts:58-63`).
No width, height, ratio, or byte-dimension is ever read, validated, or persisted. A
320×180 upload is upscaled **3.66×** into the mobile detail hero (390 pt × 3 DPR =
1170 device px) *(derived)*. A 5712×3213 iPhone capture is downloaded in full to paint
a 358×180 pt card. Neither case produces a warning.

---

## 2. Upload pipeline trace

### 2.1 Call sites (five, exhaustive)

| # | Entry point | File:line | Bucket | Folder | Crop | Quality |
|---|---|---|---|---|---|---|
| 1 | Mobile listing cover | `src/screens/CreateListingScreen.tsx:189-194` | `auction-media` | `covers` | **16:9 forced** | 0.85 |
| 2 | Mobile proof of ownership | `src/screens/CreateListingScreen.tsx:195-201` | `proof-docs` | `proofs` | none (`aspect: null`) | 0.85 |
| 3 | Mobile transfer evidence | `app/transfer/send/[id].tsx:87-93` | `proof-docs` | `transfer-evidence` | none | 0.85 |
| 4 | Mobile avatar | `src/lib/avatarImage.ts:86-92` | `avatars` | (root) | **1:1 forced** | 0.85 |
| 5 | Web cover + proof | `web/src/lib/create-listing.ts:45-78` | both | `covers` / `proofs` | **none** | n/a (raw bytes) |

Generic wrapper `src/components/ImageUploadField.tsx:65-70` hard-codes `aspect: null`.

### 2.2 Mobile path — `src/hooks/useImageUpload.ts`

1. `requestMediaLibraryPermissionsAsync()` — `:95`
2. `launchImageLibraryAsync({ mediaTypes:['images'], allowsEditing: aspect!==null, aspect, quality, exif:false })` — `:107-113`. `exif:false` strips orientation/GPS (good for privacy; also discards any camera metadata that could inform cropping).
3. `validateImage(...)` — `:121-124`. **Always passes bucket `'auction-media'`**, even for `proof-docs` uploads, so proofs get a 10 MB ceiling rather than 5 (called out in `073:135-137`).
4. Extension whitelist `['jpg','jpeg','png','webp','heic']`, everything else silently becomes `jpg` — `:157`. **The MIME is inferred from the file extension, never from the bytes** (`:158`).
5. Path `${userId}/${folder}/${Date.now()}.${ext}` — `:161`.
6. `fetch(uri).arrayBuffer()` → `Uint8Array` — `:167-169` (documented Hermes workaround, `:7-20`).
7. `upload(path, bytes, { contentType, upsert:false, cacheControl:'3600' })` — `:180-186`.
8. `getPublicUrl(path)` for `auction-media` only — `:199-206`.

**No resize. No re-encode. No compression beyond the picker's JPEG `quality: 0.85`. No dimension read. No orientation normalization. No content sniffing.**

### 2.3 Web path — `web/src/lib/create-listing.ts:53-78`

Validates `file.type` against `ALLOWED_IMAGE_TYPES` and `file.size` against
`MAX_IMAGE_SIZE_MB`, then uploads `new Uint8Array(await file.arrayBuffer())` verbatim.
`ext` is taken from the **user-supplied filename** (`:66`). No crop, no resize, no
canvas re-encode, no dimension check.

### 2.4 Buckets, policies, limits

| Bucket | Public | Size limit | Allowed MIME | Live objects | Max object | Created by |
|---|---|---|---|---|---|---|
| `auction-media` | **true** | 10,485,760 B | jpeg, png, webp, heic | **134** (111 jpeg + 23 png) | 6,361,057 B | `000_baseline_schema.sql:242-250`, repaired `073` |
| `avatars` | **true** | 5,242,880 B | jpeg, png, webp, heic | 9 (7 jpeg + 2 png) | 612,685 B | `000_baseline_schema.sql:840-848`, repaired `073` |
| `proof-docs` | false | 10,485,760 B | + heif, application/pdf | 29 (20 png + 9 jpeg) | 4,143,632 B | `033_marketplace_expansion.sql:142-144`, repaired `073` |
| `pkpass` | false | — | — | — | `083_kernel_credential_infrastructure.sql:327-329` |
| `crm-exports` | false | 33,554,432 B | text/csv only | — | `087_venue_settlement_and_export.sql:185-193` |

*(all counts measured against production 2026-08-27, recorded in `073`)*

**There is no bucket for event, venue or catalog media.** See §6.

Policies: public read is `USING (bucket_id IN ('auction-media','avatars'))` to role
`public` — no auth at all (`051_storage_scope_public_read.sql:74-77`). Writes are
folder-scoped to `auth.uid()` (`053_storage_scope_write_policies.sql:70-85`). Deletes
are permitted only for **unreferenced** objects (`048`, `049`) — attaching an image to
a listing makes it undeletable by its uploader.

`073` also records a standing caveat: `file_size_limit` and `allowed_mime_types` are
enforced by the **Storage API service**, not by Postgres — a direct SQL insert into
`storage.objects` bypasses both (`073:63-79`).

---

## 3. Storage and delivery trace

### 3.1 URL shape

```
https://hqycwntpfoztoinemqns.supabase.co/storage/v1/object/public/auction-media/<uuid>/covers/<epoch_ms>.jpg
```

- Mobile: `supabase.storage.from('auction-media').getPublicUrl(cleanPath)` — `src/lib/coverImage.ts:71`, synchronous string construction, no network.
- Web: string concatenation on `STORAGE_BASE_URL = ${SUPABASE_URL}/storage/v1/object/public` — `web/src/lib/env.ts:91`, `web/src/lib/format.ts:141-147`.
- Legacy tolerance: absolute `http…` values pass through (`coverImage.ts:60`) and a stray `auction-media/` prefix is stripped (`:65-68`) — two historic data shapes still in the column.

### 3.2 Transformation inventory *(measured)*

| Mechanism | Present? | Evidence |
|---|---|---|
| Supabase image transformations (`/render/image/`) | **No — 0 occurrences** | grep `render/image`, `transform` across `src/ app/ web/src/ packages/` |
| `width` / `quality` / `format` params on storage URLs | **No** | `format.ts:146` is bare concatenation |
| `next/image` optimizer | **Yes, web only** | `web/next.config.ts:66-83` remotePatterns |
| Responsive `srcset` / `sizes` | **Web only** | `ListingCard.tsx:44`, `listing/[id]/page.tsx:172`, `sizes="80px"` on account thumbs |
| Explicitly bypassed optimizer | 1 site | `BuyerTransferPanel.tsx:151` `unoptimized` |
| Mobile (`expo-image`) resizing | **None — raw object** | all 13 mobile `<Image>` sites |
| Marketing site | **None — raw object** | live verification, no `/_next/` |
| CDN in front of storage | Supabase's default only | no custom CDN, no signed transform |

### 3.3 Caching

`cacheControl: '3600'` at all three writers. `expo-image` sets no `cachePolicy`
anywhere, so it inherits the default and honours that 1-hour TTL. Objects are
immutable by construction. See P0-3.

---

## 4. Complete render-site inventory

**24 image elements in repo: 13 mobile, 11 web.** Of these, **11 render a listing/event
cover** (6 mobile, 5 web). A 12th cover surface exists off-repo (snatchitapp.com).
Reference viewport for mobile pt figures: **390 pt** (iPhone 14/15), list padding
`spacing.md = 16` each side ⇒ card width **358 pt** (`app/(tabs)/home.tsx:794`).

### 4.1 Event / listing covers

| # | Surface | File:line | Container (w×h) | Ratio | Fit | Radius | Overlay | Fallback |
|---|---|---|---|---|---|---|---|---|
| 1 | Mobile home feed card | `app/(tabs)/home.tsx:168` (styles `:803-806`) | 358 × 180 pt | **1.989:1** | `cover` | `radius.lg` 16 (clipped by card `overflow:hidden`) | 3 absolute badges: countdown pill `rgba(0,0,0,0.72)`, ticket-type, status pill | 🎟️ on `bgInput` — unreachable in practice |
| 2 | Mobile listing detail hero | `src/screens/ListingDetailScreen.tsx:1320` (style `:1545`) | 390 × 220 pt (full-bleed `width:'100%'`) | **1.773:1** | `cover` | 0 | none | 🎟️ on `coverPlaceholder` |
| 3 | Mobile "My bids" card | `app/(tabs)/bids.tsx:207` (styles `:622-624`) | 358 × 140 pt | **2.557:1** | `cover` | card radius | status badge | flat `bgInput`, **no icon** |
| 4 | Mobile explore row thumb | `app/(tabs)/explore.tsx:143` (style `:203`) | 64 × 64 pt | **1.000:1** | `cover` | `radius.sm` 6 | none | 🎟️ |
| 5 | Mobile public-profile listing thumb | `app/profile/[id].tsx:187` (style `:697`) | 56 × 56 pt | **1.000:1** | `cover` | 6 | none | 🎟️ |
| 6 | Mobile seller listing card | `src/components/SellerListingCard.tsx:102` (style `:203`) | 80 × 80 pt | **1.000:1** | `cover` | 6 | none | 🎟️ |
| 7 | Web browse/home card | `web/src/components/ListingCard.tsx:39-46` | `aspect-[4/3]`, `fill` | **1.333:1** | `object-cover` + `scale-[1.04]` hover | 0 (square brand) | status badge + save button | none — `next/image` error state |
| 8 | Web listing detail figure | `web/src/app/listing/[id]/page.tsx:167-173` | `aspect-[4/3]`, `fill`, `priority` | **1.333:1** | `object-cover` | 0 | badges | none |
| 9 | Web account → purchases | `web/src/app/account/purchases/page.tsx:78` | 80 × 80 px (`sizes="80px"`) | **1.000:1** | `object-cover` | 0 | none | none, `alt=""` |
| 10 | Web account → sales | `web/src/app/account/sales/page.tsx:70` | 80 × 80 px | **1.000:1** | `object-cover` | 0 | none | none, `alt=""` |
| 11 | Web seller listings | `web/src/components/account/SellerListings.tsx:138-146` | `size-20` = 80 × 80 px | **1.000:1** | `object-cover` | 0 | none | none, `alt=""` |
| 12 | **snatchitapp.com card** (out of repo) | live measurement | 358 × 448 px | **0.799:1** | `object-fit: cover` | — | — | — |

**Not rendered anywhere:** the cover is **absent from both checkout surfaces** —
`src/screens/checkout/CheckoutNative.tsx` has no image, and `web/src/app/checkout/[id]/`
has none *(measured)*. The buyer never sees the thing they are buying at the moment of
payment.

### 4.2 Avatars

| Surface | File:line | Size | Ratio | Fit |
|---|---|---|---|---|
| Own profile | `app/(tabs)/profile.tsx:344` | 96 × 96 (`:500`) | 1:1 | `cover` |
| Edit profile | `app/settings/edit-profile.tsx:299` | 96 × 96 (`:55`) | 1:1 | `cover` |
| Public profile | `app/profile/[id].tsx:462` | 88 × 88 (`:580`) | 1:1 | `cover` |
| Seller row on detail | `src/screens/ListingDetailScreen.tsx:1365` | 28 × 28 (`:1568`) | 1:1 | `cover` |

Avatars are the **only** asset with a matched upload/render contract: the picker forces
`aspect: [1,1]` (`src/lib/avatarImage.ts:89`) and every render site is square. This is
the shape the cover pipeline should have had.

### 4.3 Proof / evidence (private bucket, signed URLs)

| Surface | File:line | Container | Fit | Notes |
|---|---|---|---|---|
| Mobile receive-transfer inline | `app/transfer/receive/[id].tsx:392` (style `:495-499`) | 100% × 220 | **`contain`** | signed URL, 1 h TTL (`:88`) |
| Mobile full-screen viewer | `src/components/ProofImageViewer.tsx:134-141` | full window, zoom 1–4× | **`contain`** | the **only** `onError` + retry in the app |
| Web buyer panel | `web/src/components/transfer/BuyerTransferPanel.tsx:147-154` | `640×480` declared, `h-auto w-full` | `object-contain`, `unoptimized` | declared ratio ≠ real ratio ⇒ layout shift on load |

Proof images correctly use `contain` — legibility beats composition there. Cover images
would benefit from the same honesty in at least one placement.

### 4.4 Upload previews

| Surface | File:line | Container | Fit |
|---|---|---|---|
| Mobile cover tile | `src/components/ImageUploadTile.tsx:97-102` via `CreateListingScreen.tsx:715` | 100% × **180** | `cover`, `transition={200}` |
| Mobile proof tile | same, `CreateListingScreen.tsx:730` | 100% × **140** | `cover` |
| Web tiles | `web/src/components/sell/CreateListingForm.tsx:378-381` | **`aspect-square`** | `object-cover` |

### 4.5 Decorative / brand

`web/src/app/page.tsx:77-83` (`silhouettes.jpg`, hero band), `:152-158`
(`sold-out.jpg`), `:162-166` (app icon 64×64), `web/src/components/site/Header.tsx:33`
(logo 99 px wide).

---

## 5. Mismatch matrix

### 5.1 Real source ratios in circulation *(measured)*

- Production listing cover sample: **1173 × 609 = 1.926:1** — neither the 16:9 the mobile picker enforces nor the 4:3 web renders. Evidence that live covers arrive through the **uncropped web path** or predate the crop.
- Bundled atmosphere assets, all **portrait**: `silhouettes.jpg` 800×1200 (**0.667:1**), `concert-lights.jpg` 1007×1200 (0.839), `sold-out.jpg` 1079×1200 (0.899), `club-line.jpg` 1200×1195 (1.004) *(measured via `sips`)*.
- `silhouettes.jpg` is rendered `fill` + `sizes="100vw"` (`page.tsx:80-81`): on a 1440 px section its 800 px native width is **upscaled 1.80×** *(derived)* — the upscale the brief flagged.
- Nothing in the DB records a source dimension, so no ratio distribution can be computed from data — that absence is itself the finding.

### 5.2 Crop loss, by source ratio × container *(derived, `cover` semantics)*

Loss = `1 − Rc/Rs` when the source is wider, `1 − Rs/Rc` when taller.

| Source | 1.00:1 thumbs | 1.333:1 web | 1.773:1 detail | 1.989:1 home | 2.557:1 bids | 0.799:1 marketing |
|---|---|---|---|---|---|---|
| **1.926:1** (real live cover) | 48.1% w | 30.8% w | 8.0% w | 3.2% h | 24.7% h | **58.5% w** |
| **1.778:1** (mobile 16:9 crop) | 43.8% w | 25.0% w | 0.3% w | 10.6% h | 30.5% h | 55.1% w |
| **1.333:1** (4:3 photo) | 25.0% w | 0% | 24.8% h | 33.0% h | 47.9% h | 40.1% w |
| **0.800:1** (4:5 IG flyer) | 20.0% h | 40.0% h | 54.9% h | **59.8% h** | **68.7% h** | 0.1% |
| **0.5625:1** (9:16 story flyer) | 43.8% h | 57.8% h | 68.3% h | **71.7% h** | **78.0% h** | 29.6% h |
| **3.000:1** (wide banner) | 66.7% w | 55.6% w | 40.9% w | 33.7% w | 14.8% w | 73.4% w |

Read the two flyer rows first. **A 9:16 nightlife flyer loses 72% of itself in the home
feed and 78% in the bids list** — the poster becomes an abstract band of pixels. This
is the single most common real-world nightlife asset shape and the pipeline's worst
case.

### 5.3 Contract mismatches (independent of pixels)

| # | Producer says | Consumer does | File:line |
|---|---|---|---|
| 1 | Mobile picker enforces 16:9 | Web renders 4:3, thumbs render 1:1 | `useImageUpload.ts:78` vs `ListingCard.tsx:38` |
| 2 | Web upload preview shows 1:1 | Web card shows 4:3, mobile shows 1.99:1 | `CreateListingForm.tsx:378` |
| 3 | Web upload enforces **no** crop | Every consumer assumes a landscape crop | `create-listing.ts:66-75` |
| 4 | Hint text: "JPG or PNG · 16:9 recommended" | Bucket accepts WEBP and HEIC too | `CreateListingScreen.tsx:721` vs `073:110` |
| 5 | `coverImageUrl(path: string)` typed non-null | `market.listing_unified` projects `null` for native rows | `format.ts:141` vs `089:72` |

---

## 6. Failure modes

| Scenario | What actually happens | Handled? | Evidence |
|---|---|---|---|
| **Missing / deleted object** | `getCoverImageUrl` returns a live-looking URL for any non-empty path; storage 400s; `expo-image` paints nothing. `cover_image_path` is `not null`, so the 🎟️ placeholder branch is effectively dead code. | **No** | `coverImage.ts:54-73`; `000_baseline_schema.sql:98` |
| **Empty / null path on web** | `coverImageUrl("")` returns `${base}/auction-media/` — a directory URL. `next/image` optimizer fails; `alt=""` on account thumbs means a screen reader gets nothing. | **No** | `format.ts:145`; `purchases/page.tsx:78` |
| **Native-rail listing (imminent)** | `market.listing_unified` hard-codes `null::text as cover_image_path`. Every native listing arrives at every render site with no cover. | **No** | `089_market_bridge_view_and_late_fk.sql:72` |
| **Tall portrait flyer (9:16)** | Mobile: picker forces a 16:9 crop, so the seller at least chooses which 44% survives — then the home feed crops another 11% of *that*. Web: no crop, so 72% is discarded silently at render, center-anchored. | **No** | §5.2 |
| **Very wide banner (3:1)** | 67% of width vanishes in every 1:1 thumb; the event name burned into the banner's left third is gone. | **No** | §5.2 |
| **Tiny low-res (e.g. 320×180)** | Accepted — no dimension floor exists anywhere. Upscaled **3.66×** into the detail hero (1170 device px at 3 DPR). No warning, no rejection, no blur mitigation. | **No** | `validateImage.ts:8-33`; `create-listing.ts:58-63` |
| **Huge image (5712×3213, 6.4 MB)** | Accepted and shipped **at full resolution to a 358×180 pt card** on mobile. Live max is 6,361,057 B. | **No** (web only, via `next/image`) | `073:110`; §3.2 |
| **Very dark image** | No scrim, no vignette, no gradient anywhere. Image edge dissolves into `#11161C` card on `#0B0F14` app ground. Badges survive (own dark pills); the photo does not read as a photo. | **No** | 0 gradient hits; `theme/index.ts:7-8` |
| **Very bright image** | Home-feed badges carry `rgba(0,0,0,0.72)` pills so text survives (`home.tsx:807-812`); web badges are their own components. But a white flyer on a `#11161C` card has no border separating it from the page. | **Partial** | `home.tsx:807` |
| **Slow network** | Mobile: 3-card skeleton for the *query* only (`home.tsx:650-661`); after data lands, images pop in with **no** placeholder, blur-up or transition. Web: route-level `Skeleton` + `ListingCardSkeleton` (`ui/Skeleton.tsx:13`) covers SSR only. | **Partial** | §1 P2-7 |
| **`FlatList` recycling** | No `recyclingKey` on any `expo-image` in a recycled list ⇒ stale-image flash on fast scroll. | **No** | `home.tsx:168`, `bids.tsx:207`, `explore.tsx:143` |
| **HEIC upload from Safari** | Accepted by input, config, and bucket; undisplayable in Chrome/Firefox; Next's optimizer cannot decode it. 0 live instances today. | **No** (latent) | `CreateListingForm.tsx:387`; `073:110` |
| **Extension/MIME lie** | MIME is derived from the file extension, never sniffed from bytes; unknown extensions silently become `.jpg` with `content-type: image/jpeg`. | **No** | `useImageUpload.ts:156-158`; `create-listing.ts:66` |
| **Stale cache** | Immutable URLs re-fetched hourly. | **No** | §1 P0-3 |

---

## 7. The venue-native gap

### 7.1 What the venue/event model can hold today

| Object | Media capability | Evidence |
|---|---|---|
| `catalog.venue` | **None.** No logo, no photo, no colour, no media column of any kind. | `078_catalog_reference_data_and_flags.sql:98-116` |
| `catalog.event` | **Exactly one** nullable `hero_image_ref text`. | `078:146` |
| `catalog.event_session` | **None.** | `078:173-192` |
| `market.listing_native` | **None** — no cover column at all. | `088_market_native_rail.sql` |
| `market.listing_unified` | Projects `null::text as cover_image_path` on the native arm. | `089:72` |

**One image must serve every context — and it cannot even do that**, because:

1. **No bucket exists to hold it.** The frozen chain creates `auction-media`, `avatars`, `proof-docs` (`000`, `033`), `pkpass` (`083:327`) and `crm-exports` (`087:185`). None is an event-media bucket; `pkpass` and `crm-exports` are private, service-role-only, and not image buckets. `hero_image_ref` currently points into nothing.
2. **No upload path exists.** Zero client code, zero edge function, zero RPC writes an object for a venue or event. The only writer of the column is `catalog.update_event` (`078:993-995`), which takes the value from a JSON patch.
3. **No validation exists.** `update_event` writes `p_patch ->> 'hero_image_ref'` verbatim (`078:994`) — any text, any length, no bucket prefix check, no `..` traversal check, no MIME or extension check. The column is `SELECT`-granted to **`anon` and `authenticated`** (`078:162-165`). The migration's own comment (`078:143-145`) argues it is safe *because* it is an opaque reference and never a URL — but nothing enforces that it is not a URL.
4. **No resolver exists.** No mobile or web code reads `hero_image_ref` *(measured — the only hits outside `078` are architecture docs)*.
5. **No video anywhere.** All image buckets allowlist still-image MIME types only (`073`); there is no video column, no `expo-av`/`expo-video` import, and no player component.

The spec corpus already anticipated the shape of the problem —
`PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md:1543-1544` says a venue "cannot describe or
illustrate its own event and the consumer Event Page (RN §4.2) has no hero to render"
— and the answer shipped was a single opaque text column with no supporting
infrastructure.

### 7.2 What per-placement media requires — with change classification

Migrations **076–092 are IMMUTABLE**. New work is **093+**.

| # | Change | Classification | Notes |
|---|---|---|---|
| V1 | New `catalog.event_media` table: `(media_id, event_id, placement, storage_ref, mime, width, height, bytes, focal_x, focal_y, alt_text, sort_order, created_at)` with `placement` ∈ {`portrait_flyer`, `square_artwork`, `landscape_hero`, `thumbnail`, `vertical_video`} and a uniqueness constraint per `(event_id, placement)` | **IMPLEMENTATION FOLLOW-UP** — new migration **093+**, purely additive, touches no frozen object | The one change that actually closes the gap |
| V2 | New `catalog.venue_media` (or a venue arm of V1) for logo / hero / interior | **IMPLEMENTATION FOLLOW-UP** — 093+ | `catalog.venue` has zero media columns today |
| V3 | New **public** `event-media` bucket with `file_size_limit`, MIME allowlist (add `image/avif`; add `video/mp4` only if V1 ships vertical video), and org/venue-scoped write policies | **IMPLEMENTATION FOLLOW-UP** — 093+ | Must be an `INSERT … ON CONFLICT DO UPDATE`, not `DO NOTHING` — that exact bug is why `073` had to exist |
| V4 | Extend `market.listing_native` with a cover reference **and** change `market.listing_unified`'s native arm to project it | **POST-FREEZE AMENDMENT** | The view is created in `089` (frozen) and its projection is contractually "the common discovery set" per schema §4.6 / RLS §14.1. `create or replace view` in 093+ changes a frozen object's contract — amendment path, not a plain migration |
| V5 | Constrain `hero_image_ref`: bucket-prefix CHECK, length bound, `..` rejection in `catalog.update_event`, or deprecate it in favour of V1 with a backfill | **POST-FREEZE AMENDMENT** | `078` is frozen; the column and its RPC must stay, so semantics change in place |
| V6 | New RPC(s) to write `catalog.event_media`, mirroring `update_event`'s org-role gate (`org_owner`/`org_admin`/`org_marketing`, `venue_manager`/`venue_marketing`) | **IMPLEMENTATION FOLLOW-UP** — 093+ | Must reuse `078:958-974`'s exact authority model |
| V7 | Enable **Supabase Image Transformations** on the project (a project-level paid setting, not SQL) and set long-lived `Cache-Control` on the media bucket | **OPERATIONAL CONFIG** | Prerequisite for any resize/format strategy; no migration can assert it |
| V8 | Moderation/approval gate before venue-supplied artwork is publicly visible, and image-rights/licensing terms for venue uploads | **OWNER POLICY DECISION** | `catalog.venue.approval_status` exists (`078:111`); nothing equivalent exists for media |
| V9 | Whether a resale listing on a native event may override the venue's artwork, or must inherit it | **OWNER POLICY DECISION** | Determines whether V1 needs a listing-level override column |

**Answer to the direct question: yes — per-placement media requires a new 093+
migration (V1/V2/V3/V6), plus a post-freeze amendment for V4 and V5.** Nothing in
076–092 can be edited to deliver it.

---

## 8. Ten things that must change

1. **Stop shipping raw originals.** Adopt one resizing path for all three surfaces — Supabase image transformations (`/render/image/public/...?width=&quality=&format=`) or an equivalent — so a 358 pt card fetches ~1074 px and not 6.4 MB. Today: **0 transform parameters in the entire codebase.**
2. **Set `Cache-Control: public, max-age=31536000, immutable`** on every image write. Paths are already immutable by construction; the current `3600` is **8,760× too short** (`useImageUpload.ts:185`, `avatarImage.ts:150`, `create-listing.ts:74`).
3. **Pick one canonical aspect ratio per placement and enforce it at upload.** Six ratios (1.00, 1.33, 1.77, 1.99, 2.56, 0.80) currently crop one asset. Until a real media model exists, at minimum make the mobile picker, the web preview tile, and every render site agree.
4. **Make the web uploader crop.** `web/src/lib/create-listing.ts:66-75` uploads raw bytes with no crop, while its own preview shows `aspect-square` (`CreateListingForm.tsx:378`). This is the direct cause of the live 1.926:1 asset that matches no container.
5. **Store dimensions and a focal point.** Persist `width`, `height`, `bytes`, `mime`, `focal_x`, `focal_y` at upload. Without a focal point, every crop is center-anchored and every 9:16 flyer loses **72%** of itself.
6. **Handle failure visibly.** Add `onError` → placeholder on all 11 cover sites (only 1 of 24 image elements has one today: `ProofImageViewer.tsx:140`), and make `getCoverImageUrl` / `coverImageUrl` return `null` rather than a URL that is guaranteed to 400.
7. **Add loading affordances:** a stored blurhash/thumbhash as `placeholder`, a `transition`, and a `recyclingKey` on every `expo-image` in a `FlatList`. Currently **0 placeholders, 0 cache policies, 0 recycling keys** across the app.
8. **Treat darkness as a design input.** A scrim or gradient on every cover container, plus an ingest-time luminance check. There are **0 gradients** in the mobile app; nightlife photography on `#0B0F14` has no edge.
9. **Give the seller control after publish.** No edit surface, mobile or web, can change a cover (`app/listing/edit/[id].tsx:84-87`). Deleting the listing is the only remedy today.
10. **Build the venue media model before the native rail ships.** `catalog.event.hero_image_ref` is one unvalidated `text` column pointing at a bucket that does not exist, `catalog.venue` has no media at all, and `market.listing_unified` hard-codes `null` for every native cover (`089:72`). The moment `feature.native_resale_enabled` flips on, every native listing renders blank.

**Bonus (P2, cheap):** show the cover on both checkout surfaces. The buyer currently
pays without seeing the image (`src/screens/checkout/CheckoutNative.tsx`,
`web/src/app/checkout/[id]/`).

---

## 9. Verification notes and open items

- The live marketing site at snatchitapp.com is **not** the Next app in `web/` (no `/_next/` assets) and is **not present in this repository**. It hotlinks production `auction-media` objects directly with no transform parameters and renders them at **0.799:1**. It is a third uncontrolled consumer of the production bucket and needs its own pass; its source was not located here.
- Live object counts, MIME distribution and max sizes are quoted from the production census recorded in `073_storage_bucket_upload_constraints.sql` (dated 2026-08-27), not re-measured today.
- No source-dimension data exists in the database, so the true distribution of uploaded aspect ratios **cannot be computed**. Establishing it requires either reading the 134 live objects' headers or adding dimension capture at ingest (item 5 above). That absence is itself a finding.

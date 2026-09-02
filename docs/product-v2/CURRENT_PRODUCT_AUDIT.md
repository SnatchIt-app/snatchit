# Current product audit — Snatch It, as built

**Agent F · 2026-09-02 · branch `feature/venue-native-and-product-v2`**

Read from source. Every claim below carries a `file:line`. Style values are quoted from the code,
never inferred from a screenshot or a memory of one. This document describes **what exists today**.
It deliberately does not propose the redesign; that is another agent's deliverable.

Scope: the React Native / Expo Router mobile app (`app/`, `src/`) and the Next.js web app (`web/`).

---

## 1. Executive summary — the product's current design character

Snatch It today is **a competent dark-mode utility wearing a nightlife brand's name**. It is
carefully engineered and visually unremarkable. The screens are functional, the money math is
correct and defensively componentised, and the states are more complete than most apps at this
stage. But nothing about the product looks like a night out.

Seven specific characterisations, each evidenced below:

**1. It is a form app, not a marketplace.** The dominant visual unit across all eleven primary
screens is a `bgCard` rectangle with a hairline border and a label/value row inside it
(`src/screens/ListingDetailScreen.tsx:1576`, `src/screens/PlaceBidScreen.tsx:302`,
`app/(tabs)/profile.tsx:648`). The listing detail screen — the page that should sell a night out —
is a 220pt image followed by four identical grey specification cards
(`src/screens/ListingDetailScreen.tsx:1378-1417`). It reads as a DMV renewal, not an event.

**2. Imagery is treated as a decoration, not as the product.** Every event photo in the app is
poured into a fixed-height box at a different height on every screen (220 / 180 / 140 / 80 / 64 /
56pt) with `contentFit="cover"` and no focal-point control, no aspect ratio, no gallery, no zoom,
and no server-side resizing. See §4. This is the single largest gap between the product and its
category.

**3. The mobile app is running a different brand from the marketing site and the web app.** The
token file defines `primary: '#E10600'` on `bg: '#0B0F14'` with radii of 6/10/16/24
(`src/theme/index.ts:8,21,53-59`). The brand — as measured live and documented in
`docs/product-v2/MARKETING_BRAND_EXTRACTION.md` and implemented in `web/src/app/globals.css:13-38`
— is `#ff1a1a` on `#000` with **radius 0 everywhere** and an Oswald/Inter type pairing. The mobile
app loads **zero custom fonts**: the only `fontFamily` declaration in the entire mobile codebase is
`Menlo` for a dev-only debug string (`src/screens/ListingDetailScreen.tsx:1691`). Oswald and Inter
do not exist on mobile.

**4. Emoji are the icon system.** An actual icon system is installed and wired
(`components/ui/icon-symbol.tsx` — SF Symbols on iOS, Material Icons elsewhere) but it is used in
exactly one place: the four tab bar glyphs (`app/(tabs)/_layout.tsx:36,47,58,69`). `Ionicons` is
used exactly once (`src/components/VerifiedSellerBadge.tsx:12`). Everywhere else — 16 of the 51 `.tsx` files under `app/` and `src/` — the product renders 🎟️ 📤 📥 ⚠️ ✏️ ⛔️ 🗑 💳 🔒 ⏳ ⚙️ 👤 📡 🖼️ ⚡ as `<Text>` nodes. Emoji render
in the OS vendor's style, cannot be tinted, cannot be sized on a grid, and change appearance
between iOS versions. Three icon systems coexist; the dominant one is not a system.

**5. Trust is the product and it is nearly invisible.** In the entire browse → listing → bid → pay
funnel, trust is communicated by three things: an 11px line reading `🔒  Secure · Only charged if
you win` (`src/screens/PlaceBidScreen.tsx:250`), a conditional label row `Ownership proof — ✓
Reviewed by Snatch It` that only renders when `proof_status === 'approved'`
(`src/screens/ListingDetailScreen.tsx:1394-1396`), and an 11px blue `Verified Seller` text badge
(`src/components/VerifiedSellerBadge.tsx:20`). The home feed carries **zero** trust signal. The
checkout screen carries **zero** trust signal and **zero** product image
(`src/screens/checkout/CheckoutNative.tsx:483-530`). Every substantive guarantee statement is
buried in a 386-line legal wall at `app/settings/legal.tsx`.

**6. Feedback is a stack of 107 native alert dialogs.** `Alert.alert` is called 107 times across
the mobile app; `src/screens/ListingDetailScreen.tsx` alone accounts for 31. There is no toast, no
snackbar, no inline confirmation pattern. Every success, every error, every confirmation is an OS
modal that interrupts the screen and loses the user's place.

**7. The secondary client is better designed than the primary one.** The web app ships the brand's
Oswald/Inter pairing and radius 0 (`web/src/app/layout.tsx:11-21`, `web/src/app/globals.css:12-41`),
a search field (`web/src/components/ui/SearchInput.tsx:22`), a 44px minimum touch target enforced in
the button primitive with a comment saying so (`web/src/components/ui/Button.tsx:25-29`), a full
buyer-guarantee section on the listing page (`web/src/app/listing/[id]/page.tsx:247-275`), an
explicit Buy Now versus auction distinction on the card
(`web/src/components/ListingCard.tsx:81-89`), skeletons that match the real layout, error
boundaries, a skip link, and `prefers-reduced-motion` handling. The mobile app — the stated primary
product — has none of those. Whatever V2 does, it is closing a gap that already exists inside the
codebase, not inventing one.

The good news, and it is real: the money layer is disciplined. `PriceDisplay`
(`src/components/PriceDisplay.tsx`) is a single, well-reasoned component with tabular numerals,
non-wrapping guarantees and a documented incident history, and all-in pricing is applied
consistently at every surface. `ScreenState` (`src/components/ScreenState.tsx`) gives loading /
offline / error a real, distinct treatment with auto-retry on reconnect. Those two components are
the quality bar the rest of the product should be raised to.

---

## 2. Screen inventory

### 2.1 Mobile — primary surfaces

| ROUTE | PURPOSE | CLASS | KEY PROBLEMS |
|---|---|---|---|
| `app/(tabs)/home.tsx` | Feed of live auctions, chip filters, filter sheet | **REDESIGN** | No search field anywhere; auction vs buy-now not distinguished on the card (`:177-179` badge shows GA/VIP, not sale type) though the filter exists (`:540-541`); three badges stacked on every image (`:174-185`); the `Bid now` "button" is a non-interactive `View` (`:203`); FAB duplicates the Create tab (`:712`); `paddingTop: 56` hardcoded instead of safe area (`:736`) |
| `app/(tabs)/explore.tsx` | Search/browse listings | **REMOVE** | Dead route — `href: null` (`app/(tabs)/_layout.tsx:76`) and never pushed from anywhere; despite its own docstring saying "Explore / Search listings" (`:2`) it contains **no search input**; duplicates home with a fifth card geometry |
| `app/(tabs)/bids.tsx` | Buyer's bids, purchases, transfer status | **REDESIGN** | Card image 140pt — a fourth geometry (`:622`); missing-image fallback is a bare grey block with no icon (`:207-210` vs home's 🎟️); status semantics carried by a single overlay pill |
| `app/(tabs)/create.tsx` → `src/screens/CreateListingScreen.tsx` | Seller listing creation | **REBUILD** | One continuous 1139-line form, ~15 required fields, no steps, no progress, no draft save; errors only surface after submit with a bottom-of-page generic message (`:760-761`) and no scroll-to-first-error; `Publish Auction` CTA is not sticky (`:779-785`) |
| `app/(tabs)/profile.tsx` | Own profile, seller stats, payout, sign out | **REFINE** | Seller and buyer identity merged into one screen; six emoji act as icons; avatar is 96pt with a red glow ring (`:500,540-551`) — the largest, most emphasised image in the app is the user's own face, not an event |
| `app/listing/[id].tsx` → `src/screens/ListingDetailScreen.tsx` | The listing page | **REBUILD** | As many as five banner rows can stack between header and image (`:1188-1315`), pushing the hero below the fold; single 220pt image, no gallery, no zoom (`:1319-1325`); Buy Now is styled as the *secondary* button (`:1596` `bgInput`) while Bid is primary; 31 `Alert.alert` calls; dev debug strip renders owner state (`:1286-1290`) |
| `app/bid/[id].tsx` → `src/screens/PlaceBidScreen.tsx` | Bid entry | **REDESIGN** | No free-text amount entry — only a `±$5` stepper and `+$5/+$10/+$25` chips (`:45,207-226`); bidding $200 over the current price takes ~40 taps; `bigAmt` is an off-scale `fontSize: 44` (`:308`); success is a blocking `Alert.alert` (`:149`) |
| `app/checkout/[id].tsx` → `src/screens/checkout/CheckoutNative.tsx` | Pay for a won/reserved listing | **REDESIGN** | **No product image at any point in checkout** (`:483-530` is text rows only); no trust or guarantee copy; hands off to the Stripe PaymentSheet, so the highest-stakes moment in the funnel is rendered by a third party in a different design language; the web build shows a hard "Mobile App Required" dead end (`app/checkout/[id].tsx:22-37`) |
| `app/my-listings.tsx` | Seller's listings | **REFINE** | Uses `SellerListingCard`, whose `ACTIVE` badge is **green** (`src/components/SellerListingCard.tsx:54`) while the same word on home is **red** (`app/(tabs)/home.tsx:137`); Edit/Delete/Cancel are 11px bare text links nested inside a pressable card (`:160-178`) |
| `app/profile/[id].tsx` | Public seller profile | **REFINE** | Five-tier reputation system with five hardcoded hexes (`:167-171`) that appear nowhere else in the product; a sixth thumbnail geometry at 56pt (`:697`) |
| `app/(tabs)/index.tsx` | Redirect shim | **KEEP** | Correct and minimal |

### 2.2 Mobile — auth, settings, transfer, secondary

| ROUTE | PURPOSE | CLASS | KEY PROBLEMS |
|---|---|---|---|
| `app/(auth)/login.tsx` | Sign in | **REDESIGN** | First screen a new user ever sees; no imagery, no brand expression, no value proposition |
| `app/(auth)/signup.tsx` | Register | **REDESIGN** | Same; account creation before the user has seen a single event |
| `app/(auth)/reset-password.tsx` | Password reset | **REFINE** | Functional |
| `app/settings/index.tsx` | Settings hub | **REFINE** | Contains the worst single style violation in the codebase — see §5.3 |
| `app/settings/edit-profile.tsx` | Edit profile | **REFINE** | |
| `app/settings/notifications.tsx` | Notification prefs | **KEEP** | |
| `app/settings/preferences.tsx` | Scene/neighbourhood prefs | **KEEP** | |
| `app/settings/privacy.tsx` | Privacy policy | **KEEP** | Legal text; correctly plain |
| `app/settings/legal.tsx` | Terms | **KEEP** | 386 lines of legal wall; correct to keep, wrong as the only home for trust claims |
| `app/settings/support.tsx` | Support | **KEEP** | |
| `app/settings/blocked-users.tsx` | Block list | **KEEP** | |
| `app/settings/payout-setup.tsx` | Stripe Connect onboarding | **REFINE** | |
| `app/settings/verify-phone.tsx` | Phone OTP | **REFINE** | Gate 0 for selling (`src/screens/CreateListingScreen.tsx:366`) but reachable only from settings |
| `app/transfer/send/[id].tsx` | Seller sends tickets | **REDESIGN** | The hand-off is the moment the promise is kept or broken; it is a form |
| `app/transfer/receive/[id].tsx` | Buyer confirms receipt | **REDESIGN** | Only `resizeMode="contain"` image in the app (`:392`, `:495-500`), letterboxed at 220pt |
| `app/listing/edit/[id].tsx` | Edit a listing | **REFINE** | |
| `app/report/[type]/[id].tsx` | Report user/listing | **KEEP** | |
| `app/payout-return.tsx` / `app/payout-refresh.tsx` | Stripe redirect landings | **KEEP** | |

### 2.3 Venue-native gaps — NEW surfaces that do not exist

Nothing in `app/` or `web/src/app/` addresses first-party ticketing. Every one of the following is
absent from the route tree:

| SURFACE | CLASS | WHY IT IS NEEDED |
|---|---|---|
| Event page (an event, not a resale listing) | **NEW** | Today the atomic unit is one seller's listing (`src/screens/ListingDetailScreen.tsx`); a venue-native product needs an event with many ticket types and a promoter's own imagery |
| Ticket-type / tier selection | **NEW** | `ticket_type` is a flat GA/VIP string rendered as a badge (`app/(tabs)/home.tsx:178`); there is no tier, no inventory, no per-tier price |
| Primary checkout (buy from the venue) | **NEW** | `CheckoutNative` is built entirely around `finalSoldPrice` / winner / reservation semantics; there is no first-party purchase path |
| Venue / promoter dashboard | **NEW** | No route, no component, no navigation entry exists for an organiser |
| Event creation by a venue | **NEW** | `CreateListingScreen` asks a consumer to upload a proof-of-ownership screenshot (`:729-742`); a venue has no such artefact |
| Attendee / my-tickets wallet | **NEW** | Purchased tickets live only as a transfer status badge inside `app/(tabs)/bids.tsx`; there is no ticket object a user can hold or show |
| Door / scan surface | **NEW** | No QR, no barcode, no entry validation anywhere in the repo |
| Venue profile page | **NEW** | `venue` is a free-text string typed by the seller (`src/screens/CreateListingScreen.tsx:550`), not an entity |

---

## 3. Per-dimension scoring

Scored on the mobile app as the primary product. 1 = actively harmful, 5 = category-leading.

| DIMENSION | SCORE | JUSTIFICATION (from code) |
|---|---|---|
| **Visual hierarchy** | **2** | On the listing page as many as five banner rows can stack above the image (`src/screens/ListingDetailScreen.tsx:1188-1315`) before any content; the four content cards are typographically identical (`:1576`), so nothing signals what matters |
| **Imagery** | **1** | Six different fixed heights across six surfaces, no aspect ratio, no focal point, no gallery, no zoom, no `placeholder`/`blurhash`/`transition` on any consumer image, no server-side resizing (`src/lib/coverImage.ts:71`). See §4 |
| **Typography** | **2** | Zero custom fonts loaded; the brand's Oswald/Inter pairing is absent; a 7-step scale exists (`src/theme/index.ts:61-69`) but is bypassed 43 times by literal `fontSize:` values, including `44` (`src/screens/PlaceBidScreen.tsx:308`), `28` (`app/(tabs)/home.tsx:740`), `10` (`app/(tabs)/home.tsx:836`) |
| **Spacing** | **4** | The 4/8/16/24/32/48 scale (`src/theme/index.ts:44-51`) is genuinely used almost everywhere; deductions for `paddingVertical: 13` (`src/screens/CreateListingScreen.tsx:950,964,987`), `paddingVertical: 7` (`app/(tabs)/home.tsx:760`) and five hardcoded `paddingTop: 56/60` header insets |
| **Navigation** | **2** | Four tabs, one of which (`Create`) is a task not a place, and no Search/Explore tab despite an Explore screen existing (`app/(tabs)/_layout.tsx:76`); a marketplace with no search entry point; the FAB (`app/(tabs)/home.tsx:712`) duplicates the Create tab |
| **Information density** | **3** | The home card is well-judged; the listing page over-labels (four cards of `label: value` rows, `:1378-1417`) and the bids card packs six numbers into 140pt of body |
| **CTA clarity** | **2** | Buy Now renders in the *secondary* style while Bid takes primary red (`src/screens/ListingDetailScreen.tsx:1596` vs `:1610`); the home card's `Bid now` is a `View`, not a button (`app/(tabs)/home.tsx:203`); `⚡ Place bid · $X total` mixes an emoji, a verb and a number in one 15px label (`src/screens/PlaceBidScreen.tsx:265`) |
| **Motion** | **1** | The only animation in the entire mobile app is the outbid/win banner slide (`src/screens/ListingDetailScreen.tsx:455-481`, 220/200/260ms). Skeletons are static grey blocks with no shimmer (`app/(tabs)/home.tsx:869-878`); no image fade-in; no press states beyond `activeOpacity` |
| **Brand consistency** | **1** | Mobile `#E10600` + radius 6–24 + system font vs brand/web `#ff1a1a` + radius 0 + Oswald/Inter (`src/theme/index.ts:21,53-59` vs `web/src/app/globals.css:23`); the same status word is red on one screen and green on another (`app/(tabs)/home.tsx:137` vs `src/components/SellerListingCard.tsx:54`); three icon systems; a near-white light-mode panel inside a dark app (`app/settings/index.tsx:281`) |
| **Accessibility** | **1** | Only 8 of the 51 `.tsx` files under `app/` and `src/` contain any `accessibilityLabel`/`accessibilityRole`. `app/(tabs)/home.tsx` has 22 touchables and **zero**. No image in the app has an accessible description except the proof viewer (`src/components/ProofImageViewer.tsx:142`). Emoji-as-icon reads aloud as its Unicode name |
| **Mobile ergonomics** | **2** | Filter chips are ~29pt tall (`paddingVertical: 7` + 11px text, `app/(tabs)/home.tsx:759-760`); status pills are 10px (`:836`); Edit/Delete/Cancel are 11px text links inside a pressable card (`src/components/SellerListingCard.tsx:160-178`); all five tab screens hardcode `paddingTop: 56` instead of using the installed `SafeAreaProvider` |

**Composite: 1.9 / 5.**

---

## 4. Imagery — every surface, with exact geometry

This is the redesign's largest lever, so it gets the most precision.

### 4.1 Resolution pipeline

Every listing image resolves through `src/lib/coverImage.ts`. `getCoverImageUrl` returns
`supabase.storage.from('auction-media').getPublicUrl(path)` (`:71`) — a bare public URL with **no
transform, no width, no quality, no format parameter**. The same applies to avatars
(`src/lib/avatarImage.ts:49,156`). Consequence: a seller's 4032×3024 phone photo is downloaded at
full resolution and decoded to fill a 180pt card. There is no responsive image story on mobile at
all.

### 4.2 Every image surface in the mobile app

| # | SURFACE | FILE:LINE | CONTAINER | RATIO (390pt wide device) | FIT | RADIUS | FALLBACK |
|---|---|---|---|---|---|---|---|
| 1 | Listing detail hero | `src/screens/ListingDetailScreen.tsx:1320`, style `:1545` | `width:'100%', height: 220` | ~1.77:1 | `contentFit="cover"` | **0** — square, full-bleed | `bgInput` block + 🎟️ at `fontSize: 48` (`:1546-1547`) |
| 2 | Home feed card | `app/(tabs)/home.tsx:168`, style `:803-806` | `height: 180` in a `radius.lg` (16) clipped card | ~2.03:1 | `contentFit="cover"` | 16 top corners via parent `overflow:'hidden'` (`:795-801`) | `bgInput` block + 🎟️ at `fontSize: 40` |
| 3 | Bids card | `app/(tabs)/bids.tsx:207-210`, style `:622-624` | `height: 140` | ~2.6:1 | `contentFit="cover"` | 16 top corners | **bare `bgInput` block, no icon** (`:34` of the card fn) — inconsistent with #2 |
| 4 | Seller listing card | `src/components/SellerListingCard.tsx:102`, style `:203` | `80 × 80` | 1:1 | `contentFit="cover"` | `radius.sm` (6) | `bgInput` + 🎟️ at `fontSize: 28` |
| 5 | Explore card | `app/(tabs)/explore.tsx:143`, style `:203` | `64 × 64` | 1:1 | `contentFit="cover"` | `radius.sm` (6) | `bgInput` + 🎟️ at `fontSize: 24` |
| 6 | Public profile listing row | `app/profile/[id].tsx:187`, style `:697` | `56 × 56` | 1:1 | `contentFit="cover"` | `radius.sm` (6) | `bgInput` + 🎟️ at `fontSize: 22` |
| 7 | Own profile avatar | `app/(tabs)/profile.tsx:344-348`, style `:552-556` | `96 × 96` inside a 104pt red-glow ring (`:500-501,540-551`) | 1:1 | `contentFit="cover"` | 48 (circle) | initials on `primarySoft` (`:561-570`) |
| 8 | Public profile avatar | `app/profile/[id].tsx:462`, style `:606` | `88 × 88` | 1:1 | `contentFit="cover"` | 44 (circle) | initials |
| 9 | Seller row avatar (listing detail) | `src/screens/ListingDetailScreen.tsx:1365`, style `:1568` | `28 × 28` | 1:1 | `contentFit="cover"` | 14 (circle) | initial letter (`:1367-1369`) |
| 10 | Bid history row avatar | `src/screens/ListingDetailScreen.tsx:174` | `36 × 36` | 1:1 | — | 18 (circle) | `bgInput` |
| 11 | Cover upload tile | `src/components/ImageUploadTile.tsx:97-102`, `src/screens/CreateListingScreen.tsx:715-724` | `width:'100%', height: 180` | ~2.03:1 | `contentFit="cover"`, `transition={200}` | `radius.lg` (16), dashed border | dashed placeholder + 🖼️ |
| 12 | Proof upload tile | `src/screens/CreateListingScreen.tsx:730-741` | `height: 140` | ~2.6:1 | `contentFit="cover"` | 16, dashed | placeholder + 🎟️ |
| 13 | Transfer proof (buyer) | `app/transfer/receive/[id].tsx:392`, style `:495-500` | `width:'100%', height: 220` | ~1.77:1 | **`resizeMode="contain"`** (RN `Image`, not expo-image) | `radius.md` (10) | none |
| 14 | Proof full-screen viewer | `src/components/ProofImageViewer.tsx:134-142` | full `width × height`, pinch-zoom `ScrollView` | viewport | `resizeMode="contain"` | 0 | error phase + retry (`:136-137`) |
| 15 | **Checkout** | — | **none exists** | — | — | — | The buyer pays without ever seeing the thing they are buying (`src/screens/checkout/CheckoutNative.tsx:483-530`) |

### 4.3 The five structural imagery problems

**A. Six heights, no ratio, no system.** 220 / 180 / 140 / 80 / 64 / 56pt. Sellers are told
`"JPG or PNG · 16:9 recommended"` (`src/screens/CreateListingScreen.tsx:721`) and shown a preview
tile at `height: 180` full-width — which on a 390pt device is **2.03:1, not 16:9 (1.78:1)**. The
detail hero at 220pt is 1.77:1 (close to 16:9), the bids card at 140pt is 2.6:1. A seller who
crops carefully to the stated 16:9 gets cropped differently on all four surfaces, and the preview
they approved is not the crop anyone else sees.

**B. `cover` with no focal point.** Every consumer image uses `contentFit="cover"` with default
centre alignment. Nothing in the codebase sets `contentPosition`, a focal point, or a smart crop.
Concrete degradations:
- *Very tall image* (a portrait flyer, the most common nightlife asset): at 2.6:1 in the bids card
  roughly **80% of the image is discarded**, and because the crop is centred, the headline and the
  date — which sit at the top and bottom of a flyer — are both cut away. What survives is the
  middle: usually background texture.
- *Very wide image* (a panoramic venue shot): at 1:1 in the 64/56/80pt thumbs the sides vanish.
- *Very dark image*: the app has no scrim, no gradient, no minimum-contrast treatment. Yet home
  overlays three badges on the image — `timeBadge` at `rgba(0,0,0,0.72)` (`app/(tabs)/home.tsx:810`),
  `typeBadge` on `primarySoft` = `rgba(225,6,0,0.15)` (`:823`), and `statusPill` on backgrounds as
  faint as `rgba(255,255,255,0.06)` (`:139`). On a near-black club photo the type badge and the
  ENDED/SOLD pill are effectively invisible; on a white flyer the `timeBadge` white text on 72%
  black still reads, but the `statusPill` red-on-translucent does not.
- *Missing image*: four different fallbacks (🎟️ at 40pt, 🎟️ at 28pt, 🎟️ at 22pt, and a bare grey
  block on the bids card). No branded empty state.

**C. No image ever has more than one frame.** `cover_image_path` is singular
(`app/(tabs)/home.tsx:99`, `src/screens/ListingDetailScreen.tsx:731`). There is no gallery, no
carousel, no pager, no pinch-to-zoom on the listing hero. The *only* zoomable image in the product
is the transfer-proof viewer (`src/components/ProofImageViewer.tsx`) — the app can zoom a receipt
but not the event.

**D. No loading craft.** Not one consumer `<Image>` passes expo-image's `placeholder`, `blurhash`,
`transition`, `cachePolicy`, `priority` or `recyclingKey`. The single `transition={200}` in the
codebase is on the seller's own upload preview (`src/components/ImageUploadTile.tsx:101`). Every
event photo in the feed therefore pops in hard, at full resolution, over a flat grey rectangle.

**E. Imagery is absent exactly where intent is highest.** No image on the checkout screen
(`src/screens/checkout/CheckoutNative.tsx:483-530`), no image on the bid screen
(`src/screens/PlaceBidScreen.tsx` renders the event name as 15px muted centred text at `:180`,
`:288-289`), no image in either auth screen. The user is asked for money on a page of grey text
rows.

### 4.4 Every image surface in the web app

The web client is materially better here: it uses `next/image` with real `sizes`, a single declared
aspect ratio, `priority` above the fold, and hover motion with `motion-reduce` guards.

| # | SURFACE | FILE:LINE | CONTAINER | FIT | RADIUS | ALT | NOTES |
|---|---|---|---|---|---|---|---|
| W1 | Listing card | `web/src/components/ListingCard.tsx:38-46` | `aspect-[4/3]` on `bg-white/[0.03]` | `object-cover` | **0** | `` `${event_name} at ${venue}` `` | `sizes="(min-width: 1280px) 280px, (min-width: 1024px) 30vw, (min-width: 640px) 45vw, 92vw"`; hover `scale-[1.04]` over 400ms with `motion-reduce` guards |
| W2 | Listing detail hero | `web/src/app/listing/[id]/page.tsx:166-173` | `<figure className="relative aspect-[4/3] … border border-white/10">` | `object-cover` | **0** | same | `priority`, `sizes="(min-width: 1024px) 58vw, 100vw"`; no `<figcaption>` |
| W3 | Purchases thumbnail | `web/src/app/account/purchases/page.tsx:78` | `size-20` (80×80) | `object-cover` | 0 | `alt=""` | Guarded on `coverImagePath`; fallback is an **empty bordered square** |
| W4 | Sales thumbnail | `web/src/app/account/sales/page.tsx:70` | `size-20` | `object-cover` | 0 | `alt=""` | Same |
| W5 | Seller listings thumbnail | `web/src/components/account/SellerListings.tsx:137-148` | `size-20` inside a `<Link>` | `object-cover` | 0 | `alt=""` | **Unguarded**, and `alt=""` on the only content of a link leaves that link with no accessible name |
| W6 | Transfer evidence (buyer's proof of delivery) | `web/src/components/transfer/BuyerTransferPanel.tsx:147-153` | declared `width={640} height={480}`, `h-auto w-full` | `object-contain` (inert without `fill`) | 0 | "Seller's transfer confirmation" | `unoptimized`; a **phone screenshot is roughly 9:19.5**, so a 4:3 box is reserved for it |
| W7 | Homepage atmosphere underlays | `web/src/app/page.tsx:77-83`, `:152-158` | `fill`, `sizes="100vw"` | `object-cover` | 0 | `alt=""`, wrapper `aria-hidden` | `opacity-[0.08]` / `opacity-10` plus a `bg-black/30 mix-blend-multiply` layer — brand-correct, near-invisible in practice |
| W8 | Header logo | `web/src/components/site/Header.tsx:33-40` | 99×36 SVG, `h-8 w-auto sm:h-9` | — | 0 | "Snatch It" | `priority` |
| W9 | App icon | `web/src/app/page.tsx:162-168` | 64×64 from a **1024×1024 PNG** | — | **`rounded-[14px]`** | `alt=""` | The only rounded image in a `radius: 0` system |
| W10 | **Checkout** | — | **none exists** | — | — | — | Same defect as mobile (`web/src/components/checkout/CheckoutClient.tsx:50-66` is text rows only) |

### 4.5 The web's own imagery defects

**The missing-image fallback is a broken URL, and it is published.**
`web/src/lib/format.ts:141-147`:

```
export function coverImageUrl(path: string): string {
  if (!path || path.includes("..")) return `${STORAGE_BASE_URL}/auction-media/`;
  return `${STORAGE_BASE_URL}/auction-media/${path}`;
}
```

An empty path returns the **bucket directory URL**, which is not an image. That value is then fed to
`next/image` at `ListingCard.tsx:40`, `listing/[id]/page.tsx:168` (with `priority`) and
`SellerListings.tsx:142` — and, worse, emitted into the OpenGraph image tag
(`web/src/app/listing/[id]/page.tsx:76`) and the Event JSON-LD `image` array (`:118`), so a
listing with no cover publishes a broken image to crawlers and social unfurls. There is no
placeholder asset anywhere in the repo.

**A nightlife flyer is cropped twice.** The card and hero impose 4:3
(`ListingCard.tsx:38`, `listing/[id]/page.tsx:166`); the account rows then re-crop that to 1:1
(`purchases/page.tsx:78`, `sales/page.tsx:70`, `SellerListings.tsx:137`). Portrait artwork — the
dominant format for club and festival promotion — loses its top and bottom to the 4:3 crop and then
its sides to the square. There is no `object-contain` option and no gallery to recover it.

**The two clients disagree about the ratio.** Web renders 4:3 (1.33:1); the mobile hero is 1.77:1,
the mobile card 2.03:1, the mobile bids card 2.6:1; and the seller is told 16:9. Five ratios, one
upload.

**`sizes` under-requests on browse.** `ListingCard` declares `280px` at `≥1280px`
(`ListingCard.tsx:44`), correct for the homepage's `xl:grid-cols-4`, but `/browse` uses
`xl:grid-cols-3` (`web/src/app/browse/page.tsx:90`) giving roughly 360px columns — so browse cards
are served an upscaled, soft image.

**The highest-stakes image in the product is the worst handled.**
`web/src/components/transfer/BuyerTransferPanel.tsx:147-153` declares `width={640} height={480}`
for the seller's proof-of-delivery screenshot. It is `unoptimized`, has no `sizes`, and offers no
zoom beyond opening a new tab. The mobile client does this better: it has a real full-screen
pinch-zoom viewer with a load/error state machine (`src/components/ProofImageViewer.tsx`).

**Proof of ownership is collected and then discarded.** Both clients force sellers to upload it
(`src/screens/CreateListingScreen.tsx:730-742`, `web/src/components/sell/CreateListingForm.tsx:308-312`,
validated at `:91`) and **neither client ever shows it to a buyer**. The mobile listing page
surfaces only a text row when an admin has approved it
(`src/screens/ListingDetailScreen.tsx:1394-1396`); the web listing page does not surface it at all.

---

## 5. Design token reality check

### 5.1 What genuinely exists

`src/theme/index.ts` is a real, small, well-formed token file (86 lines) with a stated contract:
`"All screens import from here. Never hard-code values inline."` (`:3`). It defines:

- **Colour** (`:6-42`): `bg #0B0F14`, `bgCard #11161C`, `bgInput #1a2030`, `bgOverlay rgba(0,0,0,0.65)`,
  `text #FFFFFF`, `textMuted #8a94a6`, `textPlaceholder #4a5568`, `textDim #5a6478`,
  `primary #E10600`, `primaryMuted #B80000`, `primarySoft rgba(225,6,0,0.15)`,
  `primaryGlow rgba(225,6,0,0.25)`, `accent` (alias of primary), `border #1C232B`,
  `borderInput #2e3a50`, `borderActive #E10600`, `error #ff4d6d`, `success #4ade80`,
  `warning #fbbf24`, `badge #ffd700`
- **Spacing** (`:44-51`): `4 / 8 / 16 / 24 / 32 / 48`
- **Radius** (`:53-59`): `6 / 10 / 16 / 24 / 9999`
- **Font size** (`:61-69`): `11 / 13 / 15 / 18 / 24 / 32 / 42`
- **Shadow** (`:71-86`): `card` and `modal` presets

It is mirrored to CSS custom properties for the web at `packages/design-tokens/tokens.css:4-47`
(auto-generated, with `src/theme/index.ts` named as the source of truth at `:2`), and
`src/constants/theme.ts` re-exports the same values under SCREAMING_SNAKE names — a deliberate
dual-naming bridge documented at `:10-12`.

**There is no typography token beyond size.** No family, no weight scale, no line-height scale, no
letter-spacing scale. Weight is written as a literal string (`'700'`, `'800'`, `'900'`) at every
call site; `letterSpacing` appears as `0.3 / 0.4 / 0.5 / 0.6 / 0.8 / 1.0 / 1.2 / 1.4` with no
system behind it.

### 5.2 What is ad hoc

**46 hardcoded hex literals** outside the token file. The full list:

| FILE:LINE | VALUE | NOTE |
|---|---|---|
| `app/settings/index.tsx:281` | `#FFF4F4` | near-white panel background in a dark app |
| `app/settings/index.tsx:281,289` | `#FF1A1A` | **the web brand red, in the mobile app** |
| `app/settings/index.tsx:291` | `#FFFFFF` | |
| `app/settings/index.tsx:394,477` | `#fff` | |
| `app/(tabs)/home.tsx:140` | `#FFA500` | RESERVED status, orange — appears nowhere else |
| `app/(tabs)/bids.tsx:173,266,516,693,697` | `#FFD700` | gold, 5 sites |
| `src/components/SellerListingCard.tsx:58` | `#FFD700` | gold again, a 6th site |
| `app/profile/[id].tsx:167-171` | `#A855F7 #22C55E #3B82F6 #EF4444 #94A3B8` | a whole 5-tier reputation palette |
| `src/components/TransferStatusBadge.tsx:6-12` | `#fbbf24 #60a5fa #4ade80 #ff4d6d #8a94a6` | re-literals of existing tokens |
| `src/components/VerifiedSellerBadge.tsx:12,20` | `#60a5fa` | the trust blue exists only here |
| `src/screens/ListingDetailScreen.tsx:1522,1608,1638,1658,1703` | `#a0b8a2 #fff #FF6B6B #8B0000 #3A1A00` | |
| `src/screens/CreateListingScreen.tsx:1064-1079` | `#332B00 #665500 #331A00 #663300 #330000 #660000 #FFDDBB` | a private 3-level risk-banner palette |
| `src/components/ErrorBoundary.tsx:59-64` | `#111 #fff #999 #E63946 #fff` | the crash screen uses a **different red** (`#E63946`) and a **different background** (`#111`) from the app |
| `src/components/ProofImageViewer.tsx:171,197` | `#000 #fff` | acceptable — full-screen viewer chrome |
| `src/screens/checkout/CheckoutNative.tsx:712` | `#fff` | |

**43 off-scale `fontSize:` literals.** Notable: `44` (`src/screens/PlaceBidScreen.tsx:308` — between
tokens `xxl:32` and `xxxl:42`), `28` for the page title on home and explore
(`app/(tabs)/home.tsx:740`, `app/(tabs)/explore.tsx:176`) while bids/profile/create use the real
token `fontSize.xl` = 24 — so the product has **two competing page-title tiers**; `20`
(`src/components/StatCardStrip.tsx:110`, with a comment at `:20-21` explicitly acknowledging it sits
between two tokens); and `10` used for status pills in three places
(`app/(tabs)/home.tsx:836`, `src/components/SellerListingCard.tsx:215,217`, `app/profile/[id].tsx:647,704`).

**Five hardcoded header insets.** `paddingTop: 56` at `app/(tabs)/home.tsx:736`,
`app/(tabs)/explore.tsx:172`, `app/(tabs)/bids.tsx:592`, `app/(tabs)/profile.tsx:514`, and
`paddingTop: 60` at `src/screens/CreateListingScreen.tsx:942`. Every one of the five **primary tab
screens** hardcodes its status-bar inset, while all 22 secondary screens correctly use
`SafeAreaView` / `useSafeAreaInsets`. `SafeAreaProvider` is installed and mounted at
`app/_layout.tsx:80`.

### 5.3 The worst single violation

`app/settings/index.tsx:280-296` — the deletion-pending banner. Fully inline-styled, importing no
token:

```
backgroundColor: '#FFF4F4', borderColor: '#FF1A1A', borderWidth: 1,
borderRadius: 0, padding: 14, marginBottom: 16
```

Five distinct problems in seventeen lines:
1. `#FFF4F4` is a near-white panel dropped into a `#0B0F14` app — a light-mode card in a dark UI.
2. `#FF1A1A` is the **web/marketing** red, not the mobile token `colors.primary` (`#E10600`).
3. `borderRadius: 0` — the only zero radius on any mobile card; every other card is 6/10/16.
4. Both `<Text>` nodes (`:282`, `:283`) set **no `color`**, so they fall back to the platform
   default and are only legible by accident of the panel being light.
5. `padding: 14` and `marginBottom: 16` bypass the spacing scale; the withdraw button
   (`:286-294`) has `paddingVertical: 10` and no `minHeight`, giving roughly a 38pt target — under
   the 44pt minimum — and carries no `accessibilityRole`.

The copy itself is good: `"Account deletion requested"` / `"Your account deletion request is
pending. You can withdraw it to keep your account."` / `"Withdraw deletion request"`, with a
`"Withdrawing…"` busy state (`:292`). The mechanism is sound; only the styling is orphaned.

### 5.4 Web tokens — a second, incompatible system

`web/src/app/globals.css` imports the shared tokens (`:2`) and then **overrides essentially all of
them** in `@theme inline` (`:12-41`) to match the measured marketing site: `--color-bg: #000`,
`--color-card: #0a0a0a`, `--color-primary: #ff1a1a`, red-tinted hairlines
`rgba(255, 26, 26, 0.15)` (`:28`), `--font-display: var(--font-oswald)` and
`--font-sans: var(--font-inter)` (`:36-38`). It adds brand craft the mobile app has none of: a
fractal-noise grain overlay at 3% opacity (`:116-123`), a red CTA glow (`:104-113`), a
`pulse-red` live indicator (`:126-137`), an always-visible square focus ring (`:79-82`), and a
`prefers-reduced-motion` block (`:51-62`).

**Net position: two token systems, one brand.** The shared package exists and is correctly
generated, but the web app overrides it wholesale and the mobile app is the only consumer of the
original values. The mobile app is the outlier from its own brand.

### 5.5 Three different reds ship in the same product

| RED | WHERE | SOURCE |
|---|---|---|
| `#E9031E` | iOS/Android **splash screen** background, light and dark | `app.json` → `expo-splash-screen` plugin config |
| `#E10600` | Every mobile UI surface | `src/theme/index.ts:21` |
| `#ff1a1a` | Marketing site, web app, and the mobile deletion banner | `web/src/app/globals.css:23`; `app/settings/index.tsx:281,289` |

A user launching the app sees `#E9031E` for the duration of the splash, then the whole app repaints
to `#E10600`, then a single settings banner uses `#ff1a1a`. Three reds, none matching the brand.

The same config sets `userInterfaceStyle: "automatic"` while the app hard-codes dark everywhere —
`ThemeProvider value={DarkTheme}` and `<StatusBar style="light" />` (`app/_layout.tsx:81,116`).
On a device in light mode the system-drawn surfaces (keyboards, share sheets, and the 107 native
alert dialogs) render light against a permanently dark app.

---

## 6. Navigation

### 6.1 Mobile tab bar

`app/(tabs)/_layout.tsx:31-76` — four tabs, `IconSymbol` glyphs at `size={26}`,
`tabBarActiveTintColor: colors.accent` (`#E10600`), inactive `colors.textMuted`, bar background
`colors.bg`:

| TAB | ICON | TARGET |
|---|---|---|
| Home | `house.fill` | `app/(tabs)/home.tsx` |
| Create | `plus.circle.fill` | `src/screens/CreateListingScreen.tsx` |
| Bids | `tag.fill` | `app/(tabs)/bids.tsx` |
| Profile | `person.fill` | `app/(tabs)/profile.tsx` |

Hidden with `href: null`: `index` (a redirect shim) and **`explore`** (`:75-76`).

Three structural problems:
1. **No search or browse destination.** A marketplace whose only browse surface is a single
   reverse-chronological feed with eight preset chips. `router.push('/(tabs)/explore')` appears
   nowhere in the codebase, so the Explore screen is unreachable dead code.
2. **`Create` is a task, not a place.** It occupies 25% of the primary navigation, and is
   duplicated by a persistent full-width FAB reading `＋ List Tickets` on the home screen
   (`app/(tabs)/home.tsx:712-717`) which is `position:'absolute'` at `bottom: spacing.xl` and
   permanently occludes the feed.
3. **The tab bar is buyer-and-seller at once.** `Bids` is buyer-side, `Create` is seller-side,
   `Profile` holds a "Seller Dashboard" (`app/(tabs)/profile.tsx:395`) plus payout status plus
   sign-out. Neither role gets a coherent home.

### 6.2 Header patterns — three of them

- **Tab screens** hand-roll a header `View` with `paddingTop: 56` and a `borderBottomWidth: 1`
  (`app/(tabs)/home.tsx:735-741`).
- **Stack screens** hand-roll a `topBar` row with a `←` **text character** as the back button
  (`src/screens/ListingDetailScreen.tsx:1526-1532`, `backArrow` at `:1530`;
  `src/screens/PlaceBidScreen.tsx:280-285`; `src/screens/checkout/CheckoutNative.tsx` topBar).
- **Native headers are switched off entirely** — `<Stack screenOptions={{ headerShown: false }}>`
  (`app/_layout.tsx:82`). Every one of the 23 registered stack routes (`:83-105`) therefore
  re-implements its own header, back affordance and title truncation.

There is no shared `Header`, `TopBar` or `Screen` component in `src/components/`.

### 6.3 Modals and sheets

Two hand-built bottom sheets, both `<Modal transparent animationType="slide">` over
`rgba(0,0,0,0.65)`:
- Home filters (`app/(tabs)/home.tsx:268-350`), sheet `borderTopLeftRadius/RightRadius: radius.xl`
  (24), `maxHeight: '80%'` (`:889-896`).
- Create neighbourhood/platform pickers (`src/screens/CreateListingScreen.tsx:768+`).

No drag handle, no gesture dismiss, no snap points, no `@gorhom/bottom-sheet`. The full-screen
proof viewer (`src/components/ProofImageViewer.tsx`) is the one place with a real gesture —
pull-down-to-dismiss at `contentOffset.y < -80` (`:127`).

### 6.4 Feedback layer

107 `Alert.alert` calls. Distribution: `ListingDetailScreen` 31, `CreateListingScreen` 8,
`transfer/receive` 7, `listing/edit` 7, `CheckoutNative` 6, `PlaceBidScreen` 5, `transfer/send` 5,
`settings/index` 5, `profile/[id]` 5, `my-listings` 5, and the remainder spread thin. There is no
toast component, no snackbar, no inline success banner anywhere in `src/components/`.

### 6.5 How auctions and buy-now are distinguished

They are not, on the card. `home.tsx:540-541` filters on `l.buy_now_enabled`, so the data supports
the distinction and a `Buy Now` chip exists (`:70`). But the card badge at `:177-179` renders
`listing.ticket_type` (GA/VIP), and the price label at `:198` is hardcoded to `'Current bid'` with
a CTA reading `'Bid now'` (`:204`) **regardless of whether the listing is instantly purchasable**.
A buy-now listing is indistinguishable from an auction until the user opens it, at which point
Buy Now appears as the greyer of two buttons (`src/screens/ListingDetailScreen.tsx:1596`).

### 6.6 Touch targets below the 44pt minimum

Twenty controls across the secondary screens fall under Apple's 44pt minimum. The pattern is
consistent: **every text-only control in the app has no padding and no `hitSlop`.**

| CONTROL | FILE:LINE | HEIGHT |
|---|---|---|
| "Open Settings" — the only recovery path when notifications are OS-denied | `app/settings/notifications.tsx:211-213`, style `:276` (`marginTop: 6`, nothing else) | ~16pt |
| "Change Photo" | `app/settings/edit-profile.tsx:325-333` | ~16pt |
| "Forgot Password?" | `app/(auth)/login.tsx:98-100`, style `:196-199` | ~18pt |
| "Sign up" / "Sign in" link rows | `app/(auth)/login.tsx:117-122`; `app/(auth)/signup.tsx:153-158` | ~18pt |
| Terms / Privacy inline links (11px, underlined) | `app/(auth)/signup.tsx:123-137` | ~18pt |
| **18+ age gate checkbox** — App Store required | `app/(auth)/signup.tsx:109-118`, style `:252-268` | ~22pt |
| Back button | `app/settings/verify-phone.tsx:236` (`width: 40`, no height) | ~26pt |
| "Key Terms Summary" accordion | `app/settings/legal.tsx:159-166`, style `:366-367` | ~26pt |
| FAQ headers ×3 | `app/settings/support.tsx:42-49`, style `:160-161` | ~28pt |
| Filter chips ×8 | `app/(tabs)/home.tsx:615-625`, style `:758-765` | ~29pt |
| Email support button | `app/settings/support.tsx:97-99`, style `:150-154` | ~31pt |
| Retry (notifications) | `app/settings/notifications.tsx:182-184` | ~31pt |
| Unblock ×N | `app/settings/blocked-users.tsx:206-212`, style `:242` | ~31pt |
| "Resend code" / "Use a different number" | `app/settings/verify-phone.tsx:196-207`, style `:278` | ~31pt |
| Filter tabs ×5 | `app/my-listings.tsx:302-310`, style `:411` (explicit `height: 32`) | 32pt |
| Platform pills ×6 | `app/listing/edit/[id].tsx:221-225`, style `:282-284` | ~34pt |
| Neighbourhood chips ×N | `app/settings/preferences.tsx:98-106`, style `:161-168` | ~38pt |
| "Refresh Status" | `app/settings/payout-setup.tsx:327-332`, style `:373` | ~38pt |
| **"Withdraw deletion request"** — reverses account deletion | `app/settings/index.tsx:286-294` | ~38pt |
| Unblock (public profile) | `app/profile/[id].tsx:435-444`, style `:722-725` | ~38pt |

`app/report/[type]/[id].tsx` is the only screen in the product where every touch target passes.

### 6.7 Header duplication

The root stack disables native headers (`app/_layout.tsx:82`) and the auth group repeats it
(`app/(auth)/_layout.tsx:5`). No screen anywhere passes `Stack.Screen options`. The consequence is
that **the same nine-line `topBar` block is hand-copied into 16 files**, differing only in the
title string — canonical instance at `app/settings/index.tsx:267-273`, including a dummy
`<View style={s.backBtn} />` on the right purely to fake centring. The three auth screens have **no
header and no back affordance at all**, so `app/(auth)/reset-password.tsx` (arrived at from a
recovery email) has no way out.

### 6.8 State handling is inconsistent across the product

`ScreenState` (`src/components/ScreenState.tsx`) is the product's one good failure component, with
distinct loading / offline / error treatments and auto-retry on reconnect (`:37-41`). **Only three
of the 22 secondary screens use it**: `app/my-listings.tsx:323`, `app/transfer/receive/[id].tsx:286`,
`app/transfer/send/[id].tsx:232`. The other 19 hand-roll an `ActivityIndicator` or render nothing.

Two screens render their loading spinner **without the topBar**, so a hung request leaves the user
with no back button: `app/transfer/send/[id].tsx:209-217` and
`app/transfer/receive/[id].tsx:263-271`. `app/listing/edit/[id].tsx:173-179` is worse — two guard
paths (`:109-113`, `:114-123`) return without calling `setLoading(false)`, so dismissing the alert
by any route other than its OK handler strands the user on a permanent headerless spinner.

---

## 7. The web client

The web app is the **better-designed of the two clients**, and that is itself the most important
finding in this section: the secondary surface is on-brand, accessible and responsive, while the
primary product is not.

### 7.1 What web does that mobile does not

| CAPABILITY | WEB | MOBILE |
|---|---|---|
| Brand typography | Oswald + Inter, self-hosted via `next/font` (`web/src/app/layout.tsx:11-21`) | **no custom fonts at all** |
| Brand geometry | radius 0 everywhere, red hairlines `rgba(255,26,26,0.15)` (`web/src/app/globals.css:28`) | radius 6/10/16/24, grey hairlines |
| Search | `type="search"`, "Search events, venues, artists" (`web/src/components/ui/SearchInput.tsx:19-22`) plus a browse filter rail | **none** |
| 44pt touch targets | enforced in the primitive — `md: "h-11 px-6"`, with the comment "44px minimum touch target at every size" (`web/src/components/ui/Button.tsx:25-29`) | 20 controls under 44pt |
| Buyer guarantee on the listing page | a full section: escrow, 24h auto-refund, dispute freeze, Stripe (`web/src/app/listing/[id]/page.tsx:247-275`) | **absent** |
| Buy-now vs auction on the card | explicit "Buy Now" vs "{n} bids" (`web/src/components/ListingCard.tsx:81-89`) | **not distinguished** |
| Loading skeletons | `loading.tsx` on browse, account, checkout, both transfer routes; `ListingCardSkeleton` matches the real card at `aspect-[4/3]` (`web/src/components/ui/Skeleton.tsx:11-24`) | one hand-rolled skeleton on home |
| Error boundaries | `error.tsx`, `global-error.tsx`, `not-found.tsx`, `browse/error.tsx` with Sentry capture (`web/src/app/browse/error.tsx:16`) | one `ErrorBoundary` component |
| Reduced motion | global media block (`web/src/app/globals.css:51-62`) plus `motion-reduce:` on ~30 elements | not handled |
| Semantics | skip link (`layout.tsx:68-73`), `aria-label` landmarks, `aria-current`, `<time dateTime>`, native `<dialog>` filter sheet with a real focus trap (`web/src/components/browse/FiltersSheet.tsx:41`) | 17 of 22 secondary screens have zero a11y props |
| Save / favourites | `SaveButton` with `aria-pressed` (`web/src/components/SaveButton.tsx:67-68`) and an `/account/saved` route | **no save feature exists** |
| Grain, glow, pulse | `.grain`, `.btn-glow`, `.pulse-red` (`web/src/app/globals.css:97-137`) | none |

### 7.2 Web's own defects

**Navigation and discovery**
- **`SearchForm` is fully built and has zero call sites** (`web/src/components/ui/SearchInput.tsx:6`).
  The header carries no search field; the only search input is inside the browse filter rail
  (`web/src/components/browse/FilterControls.tsx:50`).
- **No mobile menu.** The primary nav is `hidden … md:flex` (`web/src/components/site/Header.tsx:42`);
  below `md` only "Browse" survives, so "How it works" and "Sell tickets" are unreachable on a phone.
  "Create account" is `hidden lg:inline-block` (`:68`), so a logged-out phone visitor sees only "Log in".
- **The loudest control in the persistent header is an off-site link.** "Get the app" is the only
  `variant="primary"` element in the header (`:74-77`) and it leaves for `snatchitapp.com`. There is
  no red CTA for `/sell`, `/browse` or `/signup`.
- **No pagination anywhere.** `/browse` hard-caps at 24 (`web/src/app/browse/page.tsx:54`,
  `web/src/lib/listings.ts:114`) and then prints that cap as though it were the total
  (`:66`, `{listings.length} live listing…`). Listings 25+ are unreachable through the UI.
- **The homepage has no hero.** `web/src/app/page.tsx:45` opens at `pt-12` directly into a card grid
  — no positioning line, no search, no category entry point above the fold. The explanatory
  "Three steps. One night." section sits below eight full-width cards on mobile.
- Every legal and support destination leaves the app (`web/src/components/site/Footer.tsx:55-59`);
  there is no in-app `/terms`, `/privacy`, `/support` or `/faq`.

**Conversion path**
- **The mobile CTA labelled "Buy now" does not buy anything** — it is an in-page anchor to `#buy`
  (`web/src/app/listing/[id]/page.tsx:421-424`).
- **The fixed mobile purchase bar permanently overlays the footer.** It is
  `fixed inset-x-0 bottom-0 z-40` (`:407`) and its compensating `h-24` spacer sits *inside*
  `<Container>` above `<Footer/>` (`:406`), so at the bottom of the page it covers the legal row.
- **An active pure auction shows no price in the panel head.** `:295` requires buy-now, `:325`
  requires ended, and `:341` returns `null` otherwise — so the price only appears far down inside
  `BidPanel`.
- **The bid stepper and its own button show two different numbers.** The stepper displays the base
  figure (`web/src/components/listing/BidPanel.tsx:212`) while the submit button shows the all-in
  figure (`:239`), 40px apart.
- **`/listing/[id]` has no `loading.tsx`** despite awaiting five queries with no streaming boundary
  (`web/src/app/listing/[id]/page.tsx:83-92`) — the highest-traffic detail route has no perceived
  performance treatment.
- **The Pay button is labelled just "Pay"** with no amount
  (`web/src/components/checkout/PaymentForm.tsx:107-109`), and there is **no reservation countdown
  on checkout** — `reservedUntil` is read only as a boolean gate
  (`web/src/app/checkout/[id]/page.tsx:22`), even though the reservation expiring mid-card-entry is
  a documented failure mode (`PaymentForm.tsx:79-83`).
- **The Stripe Payment Element is mounted with no `appearance` theme**
  (`web/src/components/checkout/CheckoutClient.tsx:77` passes only `{clientSecret}`), so a
  light-mode widget renders inside a `#0a0a0a` card.
- **The purchase-complete page has no confirming heading.** "Purchase complete!" is a `<p>` at
  `text-[15px]` (`web/src/app/checkout/[id]/complete/page.tsx:105`); the only `<h1>` is the generic
  word "Checkout" (`:124`). No order number, no amount, no event name. A `catch` at `:59-70` can set
  `status: "success"` while an error `Alert` renders, so the user reads "Purchase complete!" beside a
  red error box.

**Status, trust and destructive actions**
- **`Alert tone="success"` renders neutral white** — `"border-white/20 bg-white/[0.04] text-white/85"`
  (`web/src/components/ui/Alert.tsx:18`). A hard money-losing deadline
  (`SellerTransferPanel.tsx:80-84`), a positive confirmation (`BuyerTransferPanel.tsx:196`) and a
  neutral note all render as the same grey box.
- **`TransferStatusBadge` maps `disputed`, `expired` and `reversed` all to the `sold` variant**
  (`web/src/components/transfer/TransferStatusBadge.tsx:15-23`) — dim grey, so a disputed transfer
  looks identical to a completed sale. Meanwhile `seller_sent` maps to `buyNow`, the loudest badge
  in the system, for an intermediate waiting state.
- **Confirming receipt has no confirmation; disputing does.**
  `web/src/components/transfer/BuyerTransferPanel.tsx:176` releases the money on a single click,
  while the reversible dispute at `:185` is gated by a `window.confirm()`.
- **`window.confirm()` for destructive flows** — `BuyerTransferPanel.tsx:185`,
  `SellerListings.tsx:188,201`, `DeleteAccountButton.tsx:12,17` — a raw browser dialog inside an
  otherwise fully designed system.
- **Delete is the lightest control on the row.** `variant="ghost"` = `text-white/60 hover:text-primary`
  (`web/src/components/account/SellerListings.tsx:197`, `Button.tsx:22`), so the destructive action
  is dimmer than everything beside it and turns brand-red on hover.
- **`Verified` is a bare red word** with no icon, border or background (`Badge.tsx:55`, used at
  `listing/[id]/page.tsx:233`), visually indistinguishable from the decorative category eyebrow two
  lines above (`:194`). Seller data is only `id, display_name, is_verified_seller, created_at`
  (`web/src/lib/listings.ts:140`) — no sale count, no rating, no transfer history.
- **No trust content on `/browse` or on the card at all**, and only one 11.5px `text-white/35` line
  on checkout (`web/src/components/checkout/CheckoutClient.tsx:82`).

**Typography and colour**
- **Every type size is an arbitrary bracket value.** There is no `text-sm`/`text-base`/`text-lg`
  anywhere — roughly 20 ad-hoc sizes from `text-[9.5px]` (`listing/[id]/page.tsx:410`) to
  `text-[44px]` (`PriceDisplay.tsx:26`), including `13px`, `13.5px`, `14px`, `14.5px` and `15px` as
  five separate body sizes.
- **Contrast fails AA across the white-alpha ramp on `#000`:** `text-white/50` ≈ 4.0:1
  (`AccountNav.tsx:30`, `Field.tsx:33`), `text-white/45` ≈ 3.6:1, `text-white/40` ≈ 3.2:1
  (`listing/[id]/page.tsx:445`), `text-white/35` ≈ 2.8:1 (`BidPanel.tsx:241`,
  `CheckoutClient.tsx:82`, `Footer.tsx:61`), `text-white/30` ≈ 2.3:1 (`Footer.tsx:68`).
- **`focus:outline-none` on every text input** (`web/src/components/ui/Input.tsx:11`,
  `SearchInput.tsx:24`) removes the outline the global rule provides; the fallback is a 1px border
  colour shift.
- **`#ff5f5f` appears 12 times as an untokenised link-hover red** — `Button.tsx:87`,
  `SignUpForm.tsx:111,115,134`, `LoginForm.tsx:47`, `ForgotPasswordForm.tsx:37`,
  `FilterControls.tsx:134`, `NotificationsList.tsx:51`, `PhoneVerifyForm.tsx:165`,
  `auth/confirm/page.tsx:99,103`, `reset-password/page.tsx:25`, `account/settings/page.tsx:51`.
  `#ff8f8a` (error text) appears twice (`Alert.tsx:17`, `PlatformInstructions.tsx:74`);
  `#f5b942` and `#3ecf8e` (`PayoutSetup.tsx:14,21,28`) are the only warm and green hues in the
  product and both bypass the token layer.
- **`global-error.tsx` reimplements the brand from scratch in inline styles** with four divergent
  values: `#0B0B0C` (`:33`, matching neither `#000` nor `#0B0F14`), `#F5F5F5` (`:34`), `#FF1A1A`
  (`:46,62`) and **white-on-red button text** (`:63`) in direct contradiction of the brand's
  black-on-red pairing (`Button.tsx:20`, `globals.css:73-76`).
- **The four surviving shared tokens are dead.** `--color-success/warning/danger/badge`
  (`web/src/app/globals.css:31-34`) have zero utility call sites in any `.tsx` file.
- **Skeletons are announced to no one** — `aria-hidden="true"` with no `role="status"` or
  `aria-busy` (`web/src/components/ui/Skeleton.tsx:4`), and "Confirming your payment…"
  (`complete/page.tsx:75`) and "Preparing secure payment…" (`CheckoutClient.tsx:74`) sit in no live
  region.
- **`Field` computes `errorId`/`hintId` and never applies `aria-describedby`**
  (`web/src/components/ui/Field.tsx:28-29`); only `SignUpForm` and `ResetPasswordForm` wire it
  manually.
- **Heading hierarchy breaks.** `not-found.tsx` has no `<h1>` at all (its only heading is
  `EmptyState`'s hardcoded `<h3>`, `EmptyState.tsx:18`), and both the homepage and `/browse` jump
  `h1` → `h3` because `ListingCard` uses `<h3>` (`ListingCard.tsx:75`).
- **Dead API surface:** `SearchForm`, `Badge variant="neutral"`, `Chip tone="green"` (aliased to
  red), `PriceDisplay size="sm"`, `AuthCard`'s `footer` prop, `StatCard`'s `note` prop, two unused
  atmosphere JPEGs in `public/atmosphere/`, and an unused `type WebListing` import at `page.tsx:3`.

### 7.3 Web screen inventory

| ROUTE | PURPOSE | CLASS | KEY PROBLEMS |
|---|---|---|---|
| `web/src/app/page.tsx` | Marketing + live grid homepage | **REDESIGN** | No hero, no value proposition, no search above the fold; two of four sections end in an off-site CTA |
| `web/src/app/browse/page.tsx` | Filterable listing index | **REFINE** | 24-item cap printed as the total (`:54,66`); no pagination; no active-filter chips; no date or "tonight" filter on a page titled "Tonight's tickets." |
| `web/src/app/listing/[id]/page.tsx` | Conversion page | **REFINE** | Best page in the product; no `loading.tsx`; sticky bar overlays the footer; "Buy now" only scrolls; no price for an active pure auction; single image, no gallery |
| `web/src/app/checkout/[id]/page.tsx` | Payment | **REDESIGN** | No image, no countdown, no trust marks, unlabelled "Pay" button, un-themed Stripe element |
| `web/src/app/checkout/[id]/complete/page.tsx` | Post-payment landing | **REDESIGN** | Success is body text, not a heading; no order number or amount; can show success and an error together |
| `web/src/app/sell/page.tsx` | Gate + create listing | **REBUILD** | ~20 fields, 5 sections, no steps, no draft; errors aggregate to the top of the form with no scroll-to-error; the blocked branch is a dead end with no support link |
| `web/src/app/transfer/send/[id]/page.tsx` | Seller delivery | **REFINE** | No listing image; a hard money-losing deadline styled as a neutral `success` alert; disabled CTA gives no reason |
| `web/src/app/transfer/receive/[id]/page.tsx` | Buyer confirmation | **REFINE** | Irreversible confirm has no dialog; reversible dispute has a `window.confirm` |
| `web/src/app/account/*` (9 routes) | Account area | **REFINE** | 8 tabs in one `overflow-x-auto` row with no scroll affordance (`AccountNav.tsx:21`); overview is four counters with no action surface; purchases and sales show no price and no event date |
| `web/src/app/login|signup|forgot-password|reset-password` | Auth | **REFINE** | No OAuth, no magic link, no password-visibility toggle, no strength meter; `noValidate` on all six forms; signup success replaces the form with a bare alert |
| `web/src/app/auth/confirm/page.tsx` | Email confirmation | **KEEP** | No spinner and no `aria-live` on the processing state |
| `web/src/app/error.tsx`, `not-found.tsx`, `browse/error.tsx` | Error boundaries | **KEEP** | `not-found.tsx` has no `<h1>` |
| `web/src/app/global-error.tsx` | Root crash screen | **REFINE** | Reimplements the brand inline with four divergent values |

---

## 8. Top 20 concrete UX defects, ordered by user impact

Ordered by severity to the user, not by how easy they are to fix. Silent failures rank above
cosmetic ones because the user cannot even tell something went wrong.

1. **A failed trust query makes an established seller look brand new.**
   `app/profile/[id].tsx:293` swallows the stats error to `console.warn`, and `:518-534` then render
   `?? 0` — so "0 completed sales, 0 disputes" is displayed as fact on the screen whose stated
   purpose (`:3`) is establishing trust.
   *Fix:* render an explicit "couldn't load seller history" state instead of coercing to zero.

2. **The only way to stop an account deletion can silently disappear.**
   `app/settings/index.tsx:113,123-125` wraps the deletion probe in a bare `catch` that sets
   `deletionPending` to false, so any schema or network hiccup hides the withdraw banner entirely
   and leaves the user no in-app path to cancel.
   *Fix:* distinguish "not pending" from "could not check" and surface the latter with a retry.

3. **Scene preferences can fail to save with no indication.**
   `app/settings/preferences.tsx:60-71` awaits the Supabase update, never destructures `error`, then
   unconditionally stops the spinner and navigates back.
   *Fix:* check the error and keep the user on the screen with an inline message.

4. **A failed block-list fetch renders as "No one blocked."**
   `app/settings/blocked-users.tsx:71-74` and `:101-106` both `setRows([])`, so a safety feature
   reports the opposite of the truth after any error.
   *Fix:* add an error branch distinct from the empty state.

5. **The buyer pays without ever seeing what they are buying.**
   `src/screens/checkout/CheckoutNative.tsx:483-530` renders Event / Venue / price / fee / Total as
   text rows with no image and no trust copy; the web checkout has no image either.
   *Fix:* put the event image, date and venue at the top of the order summary with the guarantee
   line beneath.

6. **There is no search anywhere in the mobile app.**
   `app/(tabs)/_layout.tsx:75-76` hides the only browse screen, no `TextInput` in `app/` filters
   listings, and `router.push('/(tabs)/explore')` appears nowhere. The web app already ships search
   (`web/src/components/ui/SearchInput.tsx:22`, "Search events, venues, artists").
   *Fix:* add a search field to the home header and restore a browse destination to the tab bar.

7. **Editing a listing can strand the user on a headerless spinner.**
   `app/listing/edit/[id].tsx:109-113` and `:114-123` return without `setLoading(false)`, and the
   loading branch at `:173-179` renders no topBar and no back button.
   *Fix:* always clear the loading flag in the guards and render the topBar in every branch.

8. **Buy Now is styled as the weaker of the two CTAs.**
   `src/screens/ListingDetailScreen.tsx:1596` gives it `colors.bgInput` with a grey border while
   Bid gets `colors.primary` (`:1610`).
   *Fix:* make instant purchase the primary button whenever `buy_now_enabled` is true.

9. **Buy-now and auction listings are indistinguishable in the feed.**
   `app/(tabs)/home.tsx:198,204` hardcode `'Current bid'` and `'Bid now'` for every card, even
   though `:540-541` already filters on `buy_now_enabled`. The web card does distinguish them
   (`web/src/components/ListingCard.tsx:81-89`).
   *Fix:* branch the price label and CTA on `listing.buy_now_enabled`.

10. **Bidding is a tap-counting exercise.**
    `src/screens/PlaceBidScreen.tsx:45,207-226` offers only a `±$5` stepper and `+5/+10/+25` chips
    with no amount field; bidding $200 over the current price takes roughly 40 taps.
    *Fix:* add a numeric input alongside the stepper, defaulting to the minimum bid.

11. **The only recovery path for denied notifications is a 16pt tap target.**
    `app/settings/notifications.tsx:211-213` with style `:276`, which is `{ marginTop: 6 }` and
    nothing else.
    *Fix:* give it real button padding and a 44pt minimum height.

12. **The App Store mandated 18+ gate is a 22pt tap target.**
    `app/(auth)/signup.tsx:109-118`, style `:252-268` — a 22×22 checkbox in a row with no vertical
    padding and no `hitSlop`.
    *Fix:* wrap the whole row in a 44pt `Pressable` and add `accessibilityLabel`.

13. **The deletion banner is a light-mode card with a 38pt destructive control.**
    `app/settings/index.tsx:281` uses `#FFF4F4` / `#FF1A1A` / `borderRadius: 0` with untinted text,
    and the withdraw button (`:286-294`) is `paddingVertical: 10` with no `minHeight`.
    *Fix:* rebuild from `colors.error`, `colors.bgCard`, `radius.md`, the spacing scale, and a 44pt
    button.

14. **Five banner rows can bury the listing image.**
    `src/screens/ListingDetailScreen.tsx:1188-1315` stacks SOLD, refresh hint, transfer action,
    Owner Actions and reservation/auction banners above the `ScrollView` holding the hero.
    *Fix:* collapse them into one contextual status strip and move Owner Actions into the overflow
    menu.

15. **The app is effectively unusable with a screen reader.**
    17 of the 22 secondary screens have zero accessibility props, `app/(tabs)/home.tsx` has 22
    touchables and none, and not one of the 16 hand-rolled back buttons has a role or label.
    *Fix:* label every touchable, starting with the tab screens and the bid/checkout path.

16. **All five tab screens ignore the safe area.**
    `paddingTop: 56` at `app/(tabs)/home.tsx:736`, `explore.tsx:172`, `bids.tsx:592`,
    `profile.tsx:514` and `paddingTop: 60` at `src/screens/CreateListingScreen.tsx:942`, while
    `SafeAreaProvider` is mounted at `app/_layout.tsx:80`.
    *Fix:* replace all five with `useSafeAreaInsets().top`.

17. **Raw Postgres and Stripe error strings are shown to end users.**
    Roughly twenty sites, including `src/screens/PlaceBidScreen.tsx:143`,
    `app/transfer/send/[id].tsx:181`, `app/transfer/receive/[id].tsx:165`, `app/my-listings.tsx:151`,
    `app/profile/[id].tsx:346`, `app/listing/edit/[id].tsx:162`, `app/(auth)/reset-password.tsx:44`.
    *Fix:* map known error codes to human copy and log the raw string instead of displaying it.

18. **A listing with no cover renders a broken image, and publishes one.**
    `web/src/lib/format.ts:141-147` returns the bucket *directory* URL when `cover_image_path` is
    empty. That value is fed to `next/image` at `web/src/components/ListingCard.tsx:40`,
    `web/src/app/listing/[id]/page.tsx:168` (with `priority`) and
    `web/src/components/account/SellerListings.tsx:142`, and is emitted into the OpenGraph image tag
    (`web/src/app/listing/[id]/page.tsx:76`) and the Event JSON-LD `image` array (`:118`) — so it
    reaches crawlers and social unfurls.
    *Fix:* ship a branded placeholder asset and return it whenever the path is empty.

19. **Listing creation is a 15-field wall with no progress and no draft.**
    `src/screens/CreateListingScreen.tsx:530-780`, errors gated on `submitted` with a generic
    bottom message at `:760-761` and no scroll-to-first-error.
    *Fix:* split into steps, persist a draft, and scroll to the first invalid field on submit.

20. **The seller's approved crop is not the crop anyone sees.**
    `src/screens/CreateListingScreen.tsx:721` advises 16:9, the preview tile is 2.03:1
    (`src/components/ImageUploadTile.tsx:66`), the mobile hero is 1.77:1
    (`src/screens/ListingDetailScreen.tsx:1545`), the bids card is 2.6:1 (`app/(tabs)/bids.tsx:622`)
    and the web card is 4:3 (`web/src/components/ListingCard.tsx:38`).
    *Fix:* pick one ratio, crop to it in the picker, and render that ratio on every surface.

**Runners-up, not scored above:** `ACTIVE` rendering red in the feed (`app/(tabs)/home.tsx:137`)
and green in My Listings (`src/components/SellerListingCard.tsx:54`); `/browse` capping at 24 and
printing the cap as the total (`web/src/app/browse/page.tsx:54,66`) with no pagination; the web
mobile CTA labelled "Buy now" that only scrolls to an anchor
(`web/src/app/listing/[id]/page.tsx:421-424`); the fixed purchase bar permanently overlaying the
footer (`:407`); `window.confirm()` guarding the reversible dispute while the irreversible
money-releasing confirm has no dialog at all
(`web/src/components/transfer/BuyerTransferPanel.tsx:176,185`);
107 blocking `Alert.alert` dialogs as the entire mobile feedback layer;
seven success alerts fired over UI that already states the same outcome
(`app/settings/verify-phone.tsx:125`, `app/transfer/send/[id].tsx:191`,
`app/transfer/receive/[id].tsx:209,243`, `app/settings/edit-profile.tsx:217`); the missing
`textContentType="oneTimeCode"` on the OTP field (`app/settings/verify-phone.tsx:177-186`), which
disables iOS SMS autofill on the app's selling gate; `app/payout-return.tsx:48-50` asserting
"Payout setup complete" without verifying it (acknowledged in its own doc-block at `:5-6`); four
different missing-image fallbacks; and two competing page-title sizes.

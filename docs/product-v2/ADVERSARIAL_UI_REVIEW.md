# ADVERSARIAL UI AND CODE REVIEW — Product V2 Tier-0 Foundation

Repo `/Users/josetascon/snatchit-consol` · branch `feature/venue-native-and-product-v2` · commit `5dd1883`
Method: verdicts are drawn from the **installed** packages in `node_modules`, from the repo's own
migrations and shipped screens, and from arithmetic — not from recollection of any API.

Verified environment:

| Package | Declared | Installed |
|---|---|---|
| `expo-image` | `~3.0.11` | **3.0.11** |
| `expo-router` | `~6.0.23` | **6.0.23** |
| `react-native` | `0.81.5` | **0.81.5** |
| `expo-linear-gradient` | — | **not installed** |
| `react-native-linear-gradient` | — | **not installed** |

`npx tsc --noEmit` produces only two pre-existing, unrelated errors
(`src/lib/secureStorage.ts`: `expo-secure-store` and `aes-js` absent from the borrowed
`node_modules`). `npx vitest run tests/product-v2-foundation.test.ts` → **28 passed**.
Both facts are true and both are consistent with every finding below.

---

## FINDINGS

| ID | SEV | FILE:LINE | CLAIM OR CODE ATTACKED | VERDICT | EVIDENCE | USER-VISIBLE CONSEQUENCE |
|---|---|---|---|---|---|---|
| F-01 | **P0** | `src/lib/pricing/allIn.ts:68,113` | `baseMinor` — "Listing price in minor units" | **CONFIRMED BROKEN** | Every marketplace price in this repo is stored and passed in **whole dollars**: `000_baseline_schema.sql:87` `buy_now_price int`; `src/lib/money.ts:53` "Listing prices are stored in whole dollars"; live call sites `app/(tabs)/home.tsx:199`, `app/(tabs)/explore.tsx:155`, `app/profile/[id].tsx:203`, `src/screens/ListingDetailScreen.tsx:1131` all use `allInFromDollars(listing.current_bid)`. `isUsableMinor(50)` returns true. | A Tier-1 screen migrating `allInFromDollars(x)` → `allInPrice({rail:'marketplace', baseMinor:x})` renders a $50 ticket as **"$0.55"**. Silent, on the primary conversion surface. |
| F-02 | **P1** | `EventMedia.tsx:191-202` | "a gradient needs expo-linear-gradient and this pass does not add dependencies" | **CONFIRMED BROKEN** (comment wrong + wrong artefact) | RN 0.81.5 ships gradients natively: `node_modules/react-native/Libraries/StyleSheet/StyleSheetTypes.d.ts:439` `experimental_backgroundImage?: ReadonlyArray<GradientValue> \| string`, wired in `ReactNativeStyleAttributes.js` and `BaseViewConfig.android.js`. Separately, `scrimBottom`/`scrimStrong` are flat colours applied to `StyleSheet.absoluteFill` — there is no bottom band anywhere. | Every `FEATURED_EVENT` and `TICKET_ART` image is uniformly darkened **45%**; every `EVENT_HERO` and `VENUE_HERO` by **28%**. The artwork the media system exists to protect is muddied across its whole surface, and a real gradient was available at zero dependency cost. |
| F-03 | **P1** | `EventMedia.tsx:80-83` | "a slot-sized derivative is requested" | **CONFIRMED BROKEN** | `boxWidth` honours the `width` prop, but `resolveImage(asset, slot, { breakpoint })` is never given it, so `slotPixelWidth` uses the **slot's** width. `devicePixelRatio` is never passed either (always defaults to 2). | The only shipped consumer overrides `width` on every call (`app/_dev/foundation.tsx:163,191,205`). A 150 pt card requests a 336 px derivative; a 140 pt `EVENT_HERO` cell requests **780 px**. The headline byte-waste defect is not fixed wherever `width` is used. |
| F-04 | **P1** | `slots.ts:54,72,89,110` | "Layout width in points … per breakpoint" | **CONFIRMED BROKEN** | `DISCOVERY_CARD` two-up needs `16 + 168 + 16 + 168 + 16 = 384` pt; iPhone SE 2/3 and 13 mini are **375** pt (SE 1st gen 320). `EVENT_HERO`/`VENUE_HERO`/`TICKET_ART` are a fixed **390**: overflows 375 by 15 pt, under-fills a 430 pt Pro Max by 40 pt. The existing feed uses fluid `width:'100%'` (`app/(tabs)/home.tsx:804`). | On a 375 pt phone the discovery grid clips or collapses to one column, and every "full-bleed" hero either overflows the screen or leaves a 40 pt dead margin down one edge. |
| F-05 | **P1** | `provenance.ts:66-75` | "Deliberately conservative … the default leans the safe way" | **CONFIRMED BROKEN** | `inventoryKindOf({ isDirect: true, listingMode: 'auction' })` → `'direct'`. `listingMode` is discarded whenever `isDirect` is true, and the field's own doc ("came from the venue's own ticket types") is satisfied by a **resold** venue-issued ticket. | A fan auction of a venue-issued ticket renders the brand-red badge **"Direct from event — Sold by the venue. Your ticket is issued straight to your account."** This is precisely the one error the module says it exists to prevent, and no test constructs the input. |
| F-06 | **P1** | `packages/design-tokens/src/index.ts:105`, `v2.ts:6-9` | "both clients consume it" / "the web app can consume the same values" | **CONFIRMED BROKEN** | `web/package.json` pins `@snatchit/design-tokens` to `file:vendor/snatchit-design-tokens-0.1.0.tgz`. `tar -tzf` on that tarball lists **only** `tokens.css`, `package.json`, `src/css.ts`, `src/index.ts`, `scripts/generate-css.ts`, `tests/tokens-parity.test.ts` — **no `brand.ts`**, and its `exports` map has **no `./brand`** entry. | The web app still renders the legacy blue-black palette (`#0B0F14` / `#E10600`). There are three copies of the brand, the parity test guards two of them, and the one the web actually ships is not compared to anything. |
| F-07 | **P1** | `v2.ts:135-136` | "Prices. Tabular figures so digits do not jitter as a bid updates." | **CONFIRMED BROKEN** | `type.price` sets only `family/size/lineHeight/letterSpacing/uppercase`. Tabular figures require `fontVariant: ['tabular-nums']` — the idiom this repo already uses correctly at `src/components/PriceDisplay.tsx:104`, `app/(tabs)/home.tsx:818`, `ListingDetailScreen.tsx:1565`. | Live bid prices jitter horizontally on every update — the exact defect the comment claims is solved, on the screen where it is most visible. |
| F-08 | P2 | `url.ts:112-116,184` | "`resize=cover` crops to the requested box; `resize=contain` fits inside it" | **CONFIRMED BROKEN** (comment wrong; code inert) | `@supabase/storage-js` `TransformOptions` (dist/index.d.mts:289-318) defines every resize mode in terms of **width *and* height**. Only `width` is ever sent, so no box exists; `cover` and `contain` produce byte-identical responses. | No server-side crop ever happens. Cropping is done on-device by `contentFit`, so a `cover` slot downloads and discards the off-frame pixels. Two tests assert this parameter and can never fail. |
| F-09 | P2 | `EventMedia.tsx:137-142` | Focal point under `contentFit="contain"` | **CONFIRMED BROKEN** | `expo-image` `Image.types.d.ts:341-348`: percentages follow **background-position** semantics — `'100%'` is the container/image size *difference*. Under `contain` that difference is the letterbox slack, so `top:'40%'` (from `DEFAULT_FOCAL.y = 0.4`) positions at 40% of the slack instead of centred. | Every legacy 16:9 asset in a portrait slot — i.e. the majority of live inventory, forced to `fit` by `url.ts:171` — sits visibly above centre against its blurred backdrop. At `EVENT_HERO` that is ~27 pt of asymmetry. |
| F-10 | P2 | `slots.ts:163-179` + `EventMedia.tsx:83` | "Density is capped at 2 … visually indistinguishable at arm's length" | **CONFIRMED BROKEN** (unmeasured claim, compounded) | `EventMedia` never reads `PixelRatio.get()`, so `dpr` is always the default 2. On a 3× device that is **0.67× native density**, delivered at `quality=45` (Supabase default is 80; valid range 20-100). | Dark, gradient-heavy nightlife artwork — the stated design constraint — banded and soft on every Pro-class iPhone. Two independent degradations stacked, neither measured in-repo. |
| F-11 | P2 | `url.ts:103,175-191` + test:162-167 | "render it as-is rather than fabricating a transformation endpoint" | **CONFIRMED BROKEN** | Any DB-controlled value matching `^https?://` is rendered verbatim, bypassing bucket scoping, width, quality, and format. A test enshrines this as intended. | A seller-controlled row can point the app at an arbitrary remote host (viewer IP leak, arbitrary imagery), and the 6.3 MB-original defect the module claims to fix is untouched for these rows. |
| F-12 | P2 | `url.ts:132,137` | `encodeURI(path)` | **CONFIRMED BROKEN** | `encodeURI` does not escape `#`, `?`, `&`, `+`, `=`. A `#` truncates the path into a fragment; a `?` swallows the query string. | A stored filename containing `#` or `?` yields a wrong object or a request with no width/quality — a broken or multi-megabyte image. |
| F-13 | P2 | `v2.ts:145` | "The brand's easing" in "the mobile runtime's brand tokens" | **CONFIRMED BROKEN** | `'cubic-bezier(0.22, 1, 0.36, 1)'` is a CSS string. No RN animation API accepts it; RN needs `Easing.bezier(0.22, 1, 0.36, 1)`. Repo-wide grep for `Easing.` in `src`/`app` returns nothing but this line. | Any Tier-1 screen that reaches for the brand easing gets a runtime-useless string; motion silently falls back to defaults and the app's feel diverges from the site. |
| F-14 | P2 | `v2.ts:123-125` | Display line heights | **CONFIRMED BROKEN** | `displayXl` 44/40, `displayLg` 34/32 — `lineHeight` below `fontSize`. Oswald is a tall condensed face; Android clips glyph tops when `lineHeight < fontSize`. | Screen titles clipped on Android. Reproduced in the preview itself: `app/_dev/foundation.tsx:289` `h1: {fontSize: 34, lineHeight: 34}`. |
| F-15 | P2 | `EventMedia.tsx:181-190` | "Now it renders a branded plate" | **CONFIRMED BROKEN** | `rgba(255,255,255,0.20)` on `#0A0A0A` = **1.57:1**. No `fontWeight`, and `fontFamily('display')` returns `undefined` (F-19), so it is the regular system face. | The fallback is a black rectangle with a hairline border and a letter nobody can see. In the preview's QA grid it is indistinguishable from a failed load. |
| F-16 | P2 | `app/_dev/foundation.tsx:9-11,71` | "NOT REACHABLE IN PRODUCTION" | **QUALIFIED** | `expo-router`'s `_ctx.js` require-context regex excludes only `+api`/`+html`/`+middleware`; `getRoutesCore.js:96-104` ignores only `+html`, `+native-intent`, `+api`, `+middleware`. There is **no `_`-prefix exclusion** — `_layout` is special-cased by name only (`getRoutesCore.js:498`). | `/_dev/foundation` is a registered route in release builds and the whole module is bundled. The `__DEV__` guard does stop it *displaying*, so the claim holds for display but not for reachability or bundle contents. |
| F-17 | P2 | `packages/design-tokens/src/index.ts:105` | `export * as v2 from './brand.ts'` | **CONFIRMED BROKEN** | Root `tsconfig.json` excludes `packages`; `web/tsconfig.json` includes only paths under `web/`. Nothing typechecks this line. Under web's `moduleResolution:"bundler"` with no `allowImportingTsExtensions`, a `.ts` specifier is **TS5097**. | The moment the tarball is regenerated and the web app imports the brand layer, `tsc --noEmit` fails in CI on a line no one has ever compiled. |
| F-18 | P2 | `EventMedia.tsx:40-51` | The scrim's stated purpose | **CONFIRMED BROKEN** | `EventMediaProps` has no `children`, and the component returns a closed `<View>`. Text cannot be placed inside the frame. | The scrim darkens artwork for text that structurally cannot be there; whatever a parent overlays as a sibling cannot be positioned against it. The one thing the scrim is for is not expressible. |
| F-19 | P2 | `fonts.ts:51,83` | "harmless until then" | **QUALIFIED** | `FONTS_INSTALLED = false`, so `fontFamily()` returns `undefined` on native. That *is* the safe RN fallback. But the honesty of the type scale depends on it: `v2.type.*` names five families that resolve to nothing. | Everything shipped from this foundation renders in the system face. The preview says so (`brandFontsActive()`), so this is disclosed, not hidden — but no Tier-1 screen can be visually signed off until the install lands. |
| F-20 | P2 | `v2.ts:45`, `foundation.tsx:314,319` | `text.muted` for labels | **CONFIRMED BROKEN** | `rgba(255,255,255,0.45)` on `#000` = **4.41:1**; on `#0A0A0A` = **4.16:1**. WCAG AA needs 4.5:1 for text under 18 pt. Preview labels are 10 pt (`swatchLabel`, `tiny`, `typeKey`, `micro`). `text.faint` (0.30) = **2.47:1**. | Every swatch and QA-cell label in the preview fails AA, and each is the only identifier for its cell. `text.secondary` (9.96:1) and `text.primary` pass. |
| F-21 | P3 | `EventMedia.tsx:170` | `memo(EventMediaImpl)` | **CONFIRMED BROKEN** | `asset` is an object literal at every call site (`foundation.tsx:160,187,204`); shallow compare never matches. | The memo is decorative. `resolveImage` re-runs and rebuilds `URLSearchParams` on every render of every cell. |
| F-22 | P3 | `EventMedia.tsx:88,128,149` | `importantForAccessibility="no"` | **QUALIFIED** | `ImageProps extends Omit<ViewProps,'style'\|'children'>` (`Image.types.d.ts:82`), so the props do forward, and the iOS/Android split is correct. But on Android `"no"` does not hide descendants — `"no-hide-descendants"` does. It works today only because every leaf independently opts out. | Correct now, silently wrong the first time a child is added. |
| F-23 | P3 | `allIn.ts:146-155` | `formatMinor` | **QUALIFIED** | `formatMinor(-6000)` → `"$-60"` (sign before symbol); `formatMinor(1e23)` → `"$1e+23"` via `String(Math.round(...))`; non-integers silently round. It is a second formatter beside `src/lib/money.ts:62 formatCents`, which uses `toLocaleString` and behaves differently. | Two formatters that disagree will drift; a refund or credit surface would print `$-60`. Not reachable through `priceLadder`, which guards with `isUsableMinor`. |
| F-24 | P3 | `provenance.ts:70,73` | `listingMode: 'offer'` | **CONFIRMED BROKEN** | Falls through to `marketplace_fixed`, whose copy is "Sold by another fan at **a set price**." | An offer-mode listing is described as having a set price. Untested. |
| F-25 | P3 | `url.ts:84-91` | `storageBase()` | **WORKS** (fragile) | `process.env.EXPO_PUBLIC_SUPABASE_URL` **is** the repo convention — `src/lib/supabase.ts:67` reads exactly this, and `babel-preset-expo` inlines `EXPO_PUBLIC_*` at build time. The `NEXT_PUBLIC_`/`SUPABASE_URL` fallbacks are inert on native but harmless. | No defect. The duplication (rather than importing `supabaseUrl`) means a future change in `supabase.ts` turns every image into a fallback with no test to catch it. |
| F-26 | — | `EventMedia.tsx:121-150` | Every `expo-image` prop | **WORKS** | Verified in `expo-image@3.0.11` `build/Image.types.d.ts`: `contentFit` :118, `contentPosition` :129 (percentages supported, `ImageContentPositionValue` :348), `transition` :134 (number = ms cross-dissolve), `blurRadius` :140 (points), `priority` :154, `cachePolicy` :169, `recyclingKey` :194. | No silent no-ops. Only caveat: `recyclingKey` is tagged `@platform android`/`@platform ios`, so the stale-flash fix does not apply on `react-native-web`. |
| F-27 | — | `EventMedia.tsx:123,136` | `absoluteFill` + `contentFit="contain"` in a fixed frame | **WORKS** | The frame has fixed `width`/`height` and `overflow:'hidden'`; absolutely-positioned children resolve against it, and `contain` letterboxes inside those bounds. (Yoga insets absolute children by the hairline border — 0.33 pt, imperceptible.) | Letterboxing behaves as intended. The defect is *where* it letterboxes — see F-09. |
| F-28 | — | `url.ts:132` | Supabase endpoint and parameter names | **WORKS** | `@supabase/storage-js` builds `${url}/render/image/public/${path}?width=…&quality=…&resize=…` (dist/index.mjs `getPublicUrl`), and `TransformOptions` (d.mts:289-318) names exactly `width`, `height`, `resize`, `quality`, `format`. | Path and names correct. `resize`'s *behaviour* is the problem — F-08. |
| F-29 | — | `allIn.ts:113` | Marketplace fee math | **WORKS** | `src/lib/money.ts:16-34` is byte-identical to `supabase/functions/_shared/money.ts:28-46`; buyer fee 10% `Math.round`, added on top, and the server rejects a mismatched client total (`totalMismatch`, `_shared/money.ts:94`). `isUsableMinor` runs before `buyerTotalCents`, so `assertCents` can never throw. | The math is right. The **units** are not — F-01. |
| F-30 | — | `foundation.tsx:71` | `if (!__DEV__) return <Redirect …>` before hooks | **WORKS** | `FoundationPreview`, `Section` and `Row` call zero hooks. `app/(tabs)/home.tsx` exists, and `typedRoutes: true` (`app.json:89`) accepts a group-qualified `Href`. | No Rules-of-Hooks violation today. It becomes one the first time a hook is added above the guard — move the guard below the hooks now. |
| F-31 | — | `tests/…:35-39` | The parity test's ability to fail | **WORKS** | `packages/design-tokens/src/brand.ts` and `src/theme/v2.ts` are two independent files (different headers; `diff` from `export const surface` onward is empty). `toStrictEqual` does deep comparison, so real drift fails. | It can fail — but only for the two copies that do not ship to web. See F-06. |

---

## CONFIRMED BREAKS AND THEIR FIXES

### F-01 (P0) — `baseMinor` collides with the repo's whole-dollar prices

`buy_now_price`, `current_bid` and `winning_bid_amount` are **dollars**. `allInPrice` wants **cents**,
and `isUsableMinor(50)` cannot tell them apart.

Do not fix this with a comment. Fix it at the type boundary:

```ts
// src/lib/pricing/allIn.ts
export type Cents = number & { readonly __brand: 'cents' };
export const centsFromDollars = (d: number): Cents => dollarsToCents(d) as Cents;

export interface MarketplacePriceInput {
  rail: 'marketplace';
  /** Cents. Marketplace columns are WHOLE DOLLARS — wrap with centsFromDollars(). */
  baseMinor: Cents | null | undefined;
  currency?: string;
}
```

A branded type makes `allInPrice({ rail: 'marketplace', baseMinor: listing.current_bid })` a
compile error, which is the only defence that survives the ninth screen migration. Add a test that
feeds a realistic column value (`baseMinor: centsFromDollars(50)` → `5500`) and one that asserts a
raw dollar value does not typecheck.

### F-02 (P1) — the scrim

Two independent defects. First, RN 0.81.5 already has gradients, so delete the comment and use them.
Second, a scrim must be a band, not a veil:

```ts
scrimBottom: {
  top: '55%',
  experimental_backgroundImage:
    'linear-gradient(to bottom, rgba(0,0,0,0) 0%, rgba(0,0,0,0.75) 100%)',
},
scrimStrong: {
  experimental_backgroundImage:
    'linear-gradient(to bottom, rgba(0,0,0,0.55) 0%, rgba(0,0,0,0) 38%, ' +
    'rgba(0,0,0,0) 55%, rgba(0,0,0,0.80) 100%)',
},
```

`scrimBottom` must stop being `StyleSheet.absoluteFill` and become an absolutely-positioned band
(`left:0, right:0, bottom:0`). Verify on Android — `experimental_backgroundImage` is new; if a
device regresses, the honest fallback is a three-View stack of decreasing opacity, still banded,
still zero-dependency.

### F-03 (P1) — `width` is not plumbed into the request

```ts
const resolved = resolveImage(asset, slot, {
  breakpoint,
  devicePixelRatio: PixelRatio.get(),
  overrideLayoutWidth: width,   // new: slotPixelWidth uses this when present
});
```

Add `overrideLayoutWidth?: number` to `resolveImage`'s options and to `slotPixelWidth`, and import
`PixelRatio` from `react-native`. Test: `<EventMedia width={150}>` must produce `width=300`, not
`width=336`.

### F-04 (P1) — the layout widths

`layoutWidth` must express *intent*, not points. Introduce a discriminated width policy:

```ts
type SlotWidth =
  | { mode: 'fullBleed' }                              // EVENT_HERO, VENUE_HERO, TICKET_ART
  | { mode: 'grid'; columns: number; gutter: number }  // DISCOVERY_CARD
  | { mode: 'fixed'; mobile: number; tablet: number; web: number }; // thumbnails
```

Resolve `fullBleed` and `grid` against `useWindowDimensions()` at render time. Until then, at
minimum: drop `DISCOVERY_CARD.mobile` to **160** (`16+160+16+160+16 = 368 ≤ 375`) and add a test
asserting two cards plus gutters fit within 375. The 390 heroes must not stay fixed — they are
wrong on *both* of the two commonest device widths.

### F-05 (P1) — `inventoryKindOf` can label a resale as venue-issued

`listingMode` is evidence that the row is a marketplace listing and must beat `isDirect`:

```ts
export function inventoryKindOf(row: {
  isDirect?: boolean;
  listingMode?: 'buy_now' | 'auction' | 'offer' | null;
}): InventoryKind {
  // A row with a listing mode IS a marketplace listing, whatever its ticket originally was.
  if (row.listingMode === 'auction') return 'marketplace_auction';
  if (row.listingMode) return 'marketplace_fixed';
  return row.isDirect === true ? 'direct' : 'marketplace_fixed';
}
```

Rename `isDirect` to `isVenuePrimarySale` so its meaning cannot be misread as "the ticket came from
the venue". Add tests for `{isDirect:true, listingMode:'auction'}`, `{isDirect:true,
listingMode:'buy_now'}` and `{listingMode:'offer'}` — none of which exist today.

### F-06 (P1) — the token duplication does not reach the web app

Repack and re-vendor, or the brand layer is mobile-only:

1. `npm pack` in `packages/design-tokens` and replace `web/vendor/snatchit-design-tokens-0.1.0.tgz`
   (bump the version so the lockfile actually changes).
2. Confirm `brand.ts` is in the new tarball and `./brand` is in its `exports`.
3. Extend `packages/design-tokens/tests/tokens-parity.test.ts` to compare `@snatchit/design-tokens/brand`
   (the *installed* path) against `@mobile/src/theme/v2` — the alias infrastructure already exists in
   `packages/vitest.config.ts`. The current root-suite test compares two files that both ship to mobile.

Then answer the real question the duplication raises: `packages/vitest.config.ts` already aliases
`@mobile/` to the repo root, so the package *could* re-export the mobile file. The duplication is
justified only if the package must be publishable standalone. If it must, the parity test has to
cover the artefact — see step 3. If it need not, delete `brand.ts` and re-export.

### F-07 (P1) — tabular figures

```ts
price: { family: font.bodyBold, size: 20, lineHeight: 24, letterSpacing: 0,
         uppercase: false, fontVariant: ['tabular-nums'] as const },
```

Add `fontVariant?: readonly string[]` to the type-token shape and make the preview apply it, so the
claim is visible rather than asserted. `src/components/PriceDisplay.tsx:104` is the working reference.

### F-08 / F-09 (P2) — the CDN contract and the focal point

`resize` is inert with a width-only request. Either send `height` (`slotPixelWidth / aspectRatio`)
so the CDN genuinely crops and the on-device crop becomes a no-op, or delete the `resize` parameter
and correct the comment to say the crop is done on-device. Sending height is the better trade: it
removes the wasted bytes in F-08 and lets the focal point be honoured server-side.

Independently, do not pass `contentPosition` when `contentFit` is `contain` — under `contain` the
percentage addresses letterbox slack, not subject position:

```tsx
contentPosition={isFit ? 'center' : {
  left: `${Math.round(resolved.focal.x * 100)}%`,
  top:  `${Math.round(resolved.focal.y * 100)}%`,
}}
```

### F-11 / F-12 (P2) — path handling

Allowlist absolute hosts (or drop them to `kind:'fallback'` with a new `reason:'untrusted-host'`),
and encode per segment:

```ts
const enc = (p: string) => p.split('/').map(encodeURIComponent).join('/');
```

---

## TESTS THAT PROVE NOTHING

The suite is 28 green assertions. These are the ones that cannot fail, or that fail only for
reasons nobody would ship.

1. **`expect(legacy.uri).toContain('resize=contain')`** (`:128`) and
   **`expect(v2asset.uri).toContain('resize=cover')`** (`:139`) — assert a query parameter the CDN
   ignores when only `width` is sent (F-08). They test string concatenation and call it crop behaviour.
2. **`beforeAll` sets `EXPO_PUBLIC_SUPABASE_URL`** (`:30-32`) for the whole file. The
   `no-storage-base` branch is never exercised, and a renamed or missing env var — the failure mode
   that turns every image in production into a fallback plate — cannot fail a test.
3. **`'is square everywhere, because radius 0 is the brand'`** (`:76-78`) — every slot literally reads
   `v2.radius.none`. The assertion compares a constant to itself.
4. **`'defines every slot the redesign references'`** (`:59-74`) — a hard-coded list checked against the
   keys of the object the list was copied from. It fails only on deletion, never on a wrong value.
5. **`'adds the buyer fee on the marketplace rail'`** (`:204-207`) uses `baseMinor: 5000`, a number
   equally plausible as $50-in-cents or $5,000-in-dollars. That ambiguity is exactly what hides F-01.
   Every fixture in the file is a round hundred; none resembles a real column value.
6. **`formatMinor`** (`:229-233`) covers 6000, 3922, 123456. No zero, no negative, no non-integer,
   nothing near the exponential-notation threshold — the three inputs the brief asked about.
7. **`inventoryKindOf`** (`:264-270`) never constructs `{isDirect:true, listingMode:'auction'}` or
   `listingMode:'offer'`. It tests the four cases the author already believed were safe and skips
   the two that are not (F-05, F-24).
8. **`provenanceSortWeight`** (`:272-279`) compares constants the function returns as literals.
9. **`focalToObjectPosition`** (`:176-181`) is fully specified, clamping included — and has **zero call
   sites** anywhere in `app/`, `src/`, `web/` or `packages/`. A well-tested dead function.
10. **Brand parity** (`:35-39`) guards only the two copies inside `brandTokens`. A new export added to
    one file and not the other still passes, and the copy the web app renders is not in the comparison
    at all (F-06).
11. **No test imports `EventMedia.tsx`, `fonts.ts`, or `app/_dev/foundation.tsx`.** The render
    component, the font resolver and the preview have **zero** coverage.

**Directly answering the brief:** there is no test that could catch a broken `expo-image` prop
(nothing renders the component), no test that could catch a wrong CDN parameter *name* (the
assertions check the strings the code itself wrote, never a response), and no test that could catch
a missing or renamed env var (`beforeAll` supplies it unconditionally). Those three are the failure
modes that reach users first, and the suite is blind to all three by construction.

What is missing and would have caught real defects:

- A render test (`react-test-renderer` or `@testing-library/react-native`) asserting the props
  `EventMedia` hands to `Image`, pinned against the installed `expo-image` types.
- A test that `resolveImage` honours an overridden layout width (F-03).
- A geometry test: two `DISCOVERY_CARD`s plus gutters fit inside 375 pt (F-04).
- A units test on `allInPrice` using a value taken from a real column (F-01).
- A test with `process.env.EXPO_PUBLIC_SUPABASE_URL` deleted, asserting `no-storage-base`.

---

## VERDICT: IS THIS SAFE TO BUILD TIER-1 SCREENS ON?

**No — not as it stands. Conditionally yes after F-01 through F-07 are closed.**

The foundation's architecture is sound and several of its judgements are genuinely good: the
discriminated `ResolvedImage`, the refusal to quote a price it cannot compute, the decision not to
re-crop legacy assets, and the choice to keep the fonts un-enabled rather than half-install them.
The verified facts of the environment are also in its favour — every `expo-image` prop it uses
exists with the semantics it assumes, the env var matches the app's own convention exactly, the
Supabase endpoint and parameter names are right, and the fee math matches the server byte for byte.

But this is a **foundation**, and its defects are the kind that multiply. Nothing outside the dev
preview imports any of it yet, which is the one thing that makes this cheap to fix now and expensive
to fix later:

- **F-01 must be fixed before a single screen calls `allInPrice`.** Every marketplace column in this
  repo is whole dollars and the primitive takes cents. The first screen to migrate will show prices
  100× too low, and the tests are written so that it will still be green.
- **F-04 must be fixed before a grid is built on `layoutWidth`.** Fixed point widths cannot express
  "full bleed" or "two columns", and both of the numbers chosen are wrong on the two commonest
  iPhone widths.
- **F-03 must be fixed before `width` is used**, or the component's headline claim is false wherever
  it is overridden — which is everywhere it is currently used.
- **F-05 must be fixed before any badge ships.** Labelling a fan's resale as venue-issued is the one
  error this codebase says it exists to prevent, and it is reachable with a two-field object.
- **F-02, F-06, F-07** are each a confident comment that is wrong about the world: a gradient
  dependency that was never needed, a web client that never receives the tokens, and tabular figures
  that were never enabled. Each was asserted rather than verified, and each is visible to a user.

Rebuilt onto branded units, a width policy that resolves against the real viewport, and a
listing-mode-first provenance rule, this is a good base. Shipped as-is, the first Tier-1 screen
inherits a wrong price, a wrong grid and a wrong badge, and the test suite reports success.

**Ship order:** F-01 → F-05 → F-04 → F-03 → F-07 → F-02 → F-06, then the five missing tests above,
then Tier-1.

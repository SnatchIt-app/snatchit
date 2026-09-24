# V3 appearance coverage — the one current matrix

**B · 2026-09-24.** Measured on **C `v3/midnight-app` @ `016087ea`**, across `src/screens`,
`src/components`, `app`. **Supersedes the 55/15/2 figures I gave on 2026-09-24 — those counted *imports*.**

> **Evidence class: source.** Read from code and computed. **Not rendered review, not device verification.**

---

## 1 · The correction

I classified a file as unmigrated if it imported `v2`. **`v2` exports six non-colour groups** — `space`,
`radius`, `font`, `type`, `motion`, `ratio` — and importing those says nothing about appearance. Re-measured
by **actual colour-token access** (`v2.surface|text|brand|border|status`, including named imports):

| | Files | |
|---|---|---|
| `.tsx` total | **82** | |
| No colour access at all | **14** | 2 of them import `v2` for **spacing/type only** — not conversion work |
| **Colour-bearing** | **68** | |
| → static `v2` colour only — **unmigrated** | **45** | was reported as 55 |
| → static + palette — **partial** | **1** (`app/_layout.tsx`) | was reported as 15 |
| → palette only | **16** | was reported as 2 |
| → literals only, no token | **6** | |

**C has migrated four times more than my figure implied.** The remaining work is **45 + 6**, not 55 + 15.

### Palette-only is not the same as finished

Of the 16 palette-only files, **11 carry no colour literal at all**. Five still do:

| File | Literals | Verdict |
|---|---|---|
| `nav/AdaptiveDock.tsx` | 5 | **All wrong** — `:236 :238 :255 :261 :278`. A-1 / A-2 |
| `media/EventMedia.tsx` | 5 | 4 are the scrim gradients — **correct, artwork**. `:309` the fallback initial is **wrong** (A-5) |
| `ui/Sheet.tsx` | 1 | **Wrong** — `:135` grabber (A-3) |
| `ui/IconButton.tsx` | 1 | `onArt` — **correct, artwork** |
| `ui/MediaUpload.tsx` | 1 | overlay on a photo — **correct, artwork** |

**Scheme-independent artwork colours are not conversion work.** Text and scrims over a seller's photo sit on
the image, never on the canvas, and stay identical in both appearances.

### The 6 literal-only files

`TransferStatusBadge` (14 — **zero importers, not a visible defect**) · `VerifiedSellerBadge` (2) ·
`StatCardStrip` · `ProofImageViewer` (viewer backdrop — likely correct) · `PlatformInstructions` ·
`ErrorBoundary`.

---

## 2 · The 45 unmigrated, in work order

Weighted by colour accesses — the biggest conversions first:

| Accesses | File |
|---|---|
| 58 | `src/screens/CreateListingScreen.tsx` |
| 32 | `app/_dev/foundation.tsx` *(dev route)* |
| 30 · 29 | `app/transfer/receive/[id].tsx` · `app/transfer/send/[id].tsx` |
| 27 · 27 | `app/profile/[id].tsx` · `app/settings/notifications.tsx` |
| 25 | `src/screens/checkout/CheckoutNative.tsx` |
| 18 · 16 · 16 | `app/settings/edit-profile.tsx` · `app/report/[type]/[id].tsx` · `app/settings/legal.tsx` |
| 12 · 11 · 10 × 4 | `SellerListingCard` · `listing/edit/[id]` · `settings/index`, `settings/privacy`, `bids/BidCard`, … |
| ≤ 9 | `blocked-users`, `DiscoveryCard`, `TransactionPanel`, `TicketEventGroup`, `ListingDetailScreen`, `payout-setup`, `support`, and the remainder |

**`ListingDetailScreen` at 9 and `TransactionPanel` at 9 are small conversions** — the screens B has drawn
most are among the cheapest to migrate.

---

## 3 · Approved values now applied in the design

| | |
|---|---|
| **Midnight canvas** | **`#000000`** — the approved value (`V3_PACKAGE_1` §2). My boards drew `#08090A`; that was a rendering artefact and is withdrawn |
| **Neutral hairlines (A-1)** | **`#28292D`** — approved 2026-09-22. **`palette.ts` records this as an open owner decision; it is not.** The stale row was mine and is closed |
| **Pressed primary** | **`#FF5353`** — agreed with C |

**Re-measured on `#000000`: 23 graded pairs per scheme, 0 fail, in both appearances.**

---

## 4 · Design coverage — and what it is not

**Ten surfaces drawn in both appearances:** bid entry · Appearance · home · search · listing detail ·
checkout · your order · create listing · my listings · send transfer.

**This is design coverage. It is not implementation completion.** Of those ten screens, the implementations
of listing detail, checkout, create, my listings, send transfer and your order are **still in the 45**.

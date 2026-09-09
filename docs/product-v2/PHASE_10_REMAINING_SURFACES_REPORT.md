# Phase 10 — Remaining surfaces audit + next 3-screen batch

**Session:** Front End · **Date:** 2026-09-03
**Branch:** `frontend/v2-phase10-remaining-surfaces` (from the Phase 9 checkpoint).
Phase 10 is **uncommitted** — awaiting owner device review. No push, no PR, no Core-owned file touched.

## 1. Phase 9 checkpoint

- **Branch at checkpoint:** `frontend/v2-phase9-adaptive-navigation`
- **Commit SHA:** `44e8429d348dc2bd07cd2c51c94ce274dd62c5df`
- **Message:** `feat(frontend-v2): add adaptive floating navigation`
- **Secret verification:** staged an explicit file list; no `.env`, node_modules, `.expo`, ios build
  artifacts, keys, provisioning files, caches or unrelated files. Verified clean.
- **Working tree after checkpoint:** clean of tracked changes (only the two pre-existing untracked
  prior-phase stray docs remained, deliberately excluded). Post-checkpoint verify: 558 tests / 22 files,
  tsc clean, 28 lint warnings / 0 errors.
- Phase 10 branch created from that commit; no rebase, no force-push.

## 2. Complete route audit

Traced `app/**` and the screens/components they mount. Layouts (`_layout` ×3) and dev-only surfaces are
excluded from the user-facing count.

| Route / surface | Reachable? | Current status | V2 status | Backend dep | Action |
| --- | --- | --- | --- | --- | --- |
| `(auth)/login`,`signup`,`reset-password` | Yes | Phase 7 | A approved | Supabase auth | keep |
| `(tabs)/home` | Yes | Phase 2 | A approved | listings | keep |
| `(tabs)/explore` (search) | Yes (in Home) | Phase 2 | A approved (V2) | listings search | keep |
| `(tabs)/create` → CreateListingScreen | Yes | Phase 5 | A approved | listings insert | keep |
| `(tabs)/bids` | Yes | Phase 4 | A approved | bids/transfers | keep |
| `(tabs)/profile` | Yes | Phase 6 | A approved | get_my_profile | keep |
| `(tabs)/index` | No (href:null) | legacy hidden | G dead | — | leave (unreachable) |
| `bid/[id]` → PlaceBidScreen | Yes | Phase 6 | A approved | bids | keep |
| `checkout/[id]` → CheckoutNative | Yes | Phase 3 | A approved | Stripe | keep |
| `listing/[id]` → ListingDetailScreen | Yes | Phase 1 | A approved | listings | keep |
| `listing/edit/[id]` | Yes | Phase 7 | A approved | listings update | keep |
| `my-listings` | Yes | Phase 7 | A approved | listings/transfers | keep |
| `settings/index` + 9 subroutes | Yes | Phase 6/8 | A approved | various | keep |
| `transfer/receive/[id]`,`send/[id]` | Yes | Phase 7 | A approved | transfers | keep |
| **`profile/[id]` (public)** | Yes (from listing) | **legacy** | **D → V2 (Phase 10)** | get_profile_trust_stats | **redesigned** |
| **`report/[type]/[id]`** | Yes (listing/profile overflow) | **legacy** | **D → V2 (Phase 10)** | reports insert | **redesigned** |
| **`payout-return`** | Yes (Stripe redirect) | **legacy** | **D → V2 (Phase 10)** | — (routing) | **redesigned** |
| **`payout-refresh`** | Yes (Stripe redirect) | **legacy** | **D → V2 (Phase 10)** | — (routing) | **redesigned** |
| Tickets | — | not built | F blocked by Core | kernel.tickets (absent) | slot kept, not built |
| `_dev/foundation` | Dev only | dev | E internal | — | leave |
| `_layout` ×3 | — | infra | E internal | — | leave (root loading spinner is minor) |

**Counts (reachable user-facing):** 29 total — **25 owner-approved V2** at audit + **4 legacy routes**
(the four redesigned this batch). After Phase 10: **0 remaining legacy user-facing routes**. Core-blocked:
1 (Tickets). Dead/unreachable: 1 (`(tabs)/index`).

## 3. Three selected Phase 10 surfaces

1. **Public profile (`app/profile/[id].tsx`)** — reached from every listing (tap the seller), the app's
   primary trust surface, and privacy-sensitive. Highest value; the last big legacy screen.
2. **Report flow (`app/report/[type]/[id].tsx`)** — reached from the listing overflow and the public
   profile; an App Store 1.2 safety requirement; legacy.
3. **Payout landing (`app/payout-return.tsx` + `app/payout-refresh.tsx`)** — the pages a seller lands on
   after Stripe onboarding; a coherent legacy pair that jarred against the V2 app.

(No notifications/activity feed exists — only the settings notification-preferences screen, already V2 —
so none was invented.)

## 4. Each screen

### Public profile
- **Before:** legacy `@/src/theme` (blue-black card, glow avatar ring, emoji ticket placeholder,
  rainbow reputation-tier pills, `shadow.card`).
- **After:** V2 — `SettingsHeader`, circular avatar with a red hairline ring, `Badge` for verified +
  reputation tier (restrained tones, not a rainbow), an `AccountSection` trust panel (big success-rate
  hero + hairline `TrustRow`s), `EventMedia` listing thumbnails, `Button` actions.
- **Behavior preserved:** block check, safe-columns-only fetch, `get_profile_trust_stats`, the
  **stats-unavailable ≠ zero** distinction, active-listings query, report/block/unblock (incl. the
  23505 already-blocked case), self-view hiding the safety actions, blocked/not-found/loading states.
  Reputation derivation extracted to the tested `src/lib/profile/reputation.ts`.
- **Data contracts:** `profiles` (public columns only), `user_blocks`, `get_profile_trust_stats`,
  `listings`. **Privacy:** never selects phone / stripe_connect_id / wallet / email / preferences (a
  test asserts it).
- **Loading:** `Spinner`. **Empty:** `EmptyState` (not found) + inline "No active listings" + the
  distinct "history unavailable" retry card. **Error:** friendly copy, raw logged. **Accessibility:**
  header role, labelled listing rows + actions, Badge carries the word. **Money:** `allInLabel`.
- **Files:** `app/profile/[id].tsx`, `src/lib/profile/reputation.ts` (new).

### Report flow
- **Before:** legacy `@/src/theme` (card radio list, `colors.accent` submit).
- **After:** V2 — `SettingsHeader`, hairline radio rows, a V2 multiline notes field with a char count,
  `Button` submit, fineprint.
- **Behavior preserved:** the `REASONS` list filtered by target type, the `reports` insert, the sign-in
  guard, the 1000-char cap, the confirmation → back, the friendly (not raw) error.
- **Data contracts:** `reports` insert. **Loading:** button spinner. **Empty:** n/a. **Error:** "Could
  not submit report" (raw logged). **Accessibility:** radios with `selected` state, labelled field.
- **Files:** `app/report/[type]/[id].tsx`.

### Payout landing (return + refresh)
- **Before:** legacy `@/src/theme` bordered-circle glyphs, `colors.accent` buttons.
- **After:** V2 — `SettingsHeader`, a `Badge` (Connected / Setup incomplete), Oswald title, Inter
  subtitle, `Button`.
- **Behavior preserved:** the 1500ms auto-redirect and `router.replace` targets
  (`/(tabs)/profile` for return, `/settings/payout-setup` for refresh) — so back never returns to the
  landing page. No error/red treatment on refresh (an expired link is normal).
- **Data contracts:** none (routing only). **Loading/empty/error:** n/a (transient). **Accessibility:**
  header + labelled CTA. **Motion:** none decorative.
- **Files:** `app/payout-return.tsx`, `app/payout-refresh.tsx`.

## 5. Remaining legacy surfaces

**None user-facing.** All 29 reachable user-facing surfaces are now V2. The only legacy-styled code left
is the root `app/_layout.tsx` loading spinner (infrastructure — a red spinner on black, effectively
on-brand) and `app/_dev/foundation.tsx` (dev only). Neither is a product surface.

## 6. Core-blocked surfaces

**Tickets** — the `HOME · CREATE · BIDS · TICKETS · PROFILE` fifth destination. Blocked: `kernel.tickets`
has no app-accessible authenticated owner-scoped SELECT; 093 undeployed; native venue flags off. The
navigation dock keeps the architectural slot (`navItems({ tickets: true })` returns the five-item order
with no layout change) but renders no Tickets tab, no placeholder, no "coming soon", no QR/wallet, and
queries nothing. Unblock needs Core to ship (1) an owner-scoped authenticated ticket read reachable from
the client, (2) a documented event-first ticket row shape (event ref, type, quantity, ownership/
fulfillment state, upcoming-vs-past), (3) a stable status/error vocabulary.

## 7. Test results

Suite **568 / 23 files** (was 558 / 22). New `tests/reputation.test.ts` (10): the reputation ladder
(null → new seller; a lost dispute as the floor even at high volume; under-5 new seller; Trusted/Top/
Elite promotion; volume-but-low-rate → review; restrained tones) and Phase 10 source guards (public
profile selects only safe columns — never private data — and keeps stats-unavailable/block/report/
self-view/`allInLabel`/`EventMedia`; report keeps the filtered insert + friendly error; payout keeps the
auto-redirect + replace routing; none query `kernel.tickets`). `tsc` clean; `expo lint` **27 warnings /
0 errors** (one below the 28 baseline, no new). iOS bundle HTTP 200.

## 8. Recommended next batch

1. **Owner device review** of these three Phase 10 surfaces (public profile, report, payout landing),
   plus a standalone look at **explore/search** (V2 since Phase 2 but never reviewed on its own).
2. **Tickets product batch** — the moment Core ships the ticket contract (§6); the nav slot is ready.
3. **Cleanup**: retire the unreachable `(tabs)/index` legacy screen and give the root `_layout` loading
   state the V2 `Spinner`; migrate/remove the dead `ImageUploadField`/`ImageUploadTile` now that
   production uses `MediaUpload`.

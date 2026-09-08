# Frontend V2 — Final readiness report

**Session:** Front End · **Date:** 2026-09-03
**Scope:** frontend (React Native / Expo) presentation only. No backend, schema, RLS, RPC,
Edge Function, money, auth, transfer, ticket, venue, or release configuration was touched in any
phase of this redesign.
**Status:** the V2 design system now covers every reachable user-facing mobile surface. The only
planned surface still outstanding — Tickets — is blocked by Core, not by frontend work.

> This report certifies **frontend V2 readiness only**. It does **not** claim the whole Snatch It
> application is production-ready; backend, payments, and release readiness are Core's to establish
> separately.

---

## 1. Final checkpoint chain

Each phase was checkpointed as one coherent local commit only after owner device approval. SHAs are
recovered from git history, not reconstructed.

| Phase | Commit subject | SHA |
| --- | --- | --- |
| Phase 0 — design foundation | `feat(frontend-v2): establish design foundation` | `9bf62356c122854be1b33c3f7fbccd122d269fdd` |
| Phase 1 — listing detail | `feat(frontend-v2): redesign listing detail` | `cc77150d31516c644004134b43b7d9d96f7bcfa1` |
| Phase 2 — home discovery | `feat(frontend-v2): redesign home discovery` | `b04953e6dbb5a2ad8a953a3290e78b84264cf28f` |
| Home logo revision | `fix(frontend-v2): home header uses the white SN logo mark` | `bec296c07d6085fdbd9bb37af0afe58088d63555` |
| Phase 3 — checkout | `feat(frontend-v2): redesign checkout experience` | `f0c7044782b2ecd6206a339d701fcacfbc8b7bdf` |
| Phase 4 — bids and ownership | `feat(frontend-v2): redesign bids and ownership` | `40dd9f25b4617daf20560cccae3c28a81c0bc158` |
| Phase 5 — create listing | `feat(frontend-v2): redesign create listing` | `66c4415be980f06b3423f3b6745f609b8b309317` |
| Phase 6 — bid, profile, settings | `feat(frontend-v2): redesign bid profile and settings` | `8f9621a440498960dd9575fde07c99287cc00145` |
| Phase 7 — auth, transfer, listings | `feat(frontend-v2): redesign auth transfer and listings` | `90e6b8331515bf59dcac031acd9d81382b77423f` |
| Phase 8 — account settings | `feat(frontend-v2): redesign account settings` | `c50eaf943e95f789aae9b398141012bb7d06121a` |
| Phase 9 — adaptive floating navigation | `feat(frontend-v2): add adaptive floating navigation` | `44e8429d348dc2bd07cd2c51c94ce274dd62c5df` |
| Phase 10 — remaining user surfaces | `feat(frontend-v2): complete remaining user surfaces` | `904721131b999af442ba14f009d5486d5923a6f2` |
| Closeout — cleanup (this report) | `chore(frontend-v2): close out mobile redesign` | recorded at commit time below |

The Phase 9 "adaptive floating navigation" dock and the Phase 4 Oswald line-height fix are included
in the chain above; the dock was approved on a physical iPhone and is now **frozen**.

## 2. Current branch / HEAD

- **Phase 10 checkpoint (approved):** `904721131b999af442ba14f009d5486d5923a6f2` on
  `frontend/v2-phase10-remaining-surfaces`.
- **Cleanup branch:** `frontend/v2-closeout`, cut from the Phase 10 checkpoint.
- **HEAD at report authoring:** the closeout commit created from this branch (see the completion
  block for the exact SHA). No push, no PR, no force-push.

## 3. Route coverage

Every reachable user-facing route and its V2 status. Layouts and dev-only surfaces are excluded from
the user-facing count.

| Route / surface | Reachable | V2 status |
| --- | --- | --- |
| `(auth)/login`, `signup`, `reset-password` | Yes | V2 (Phase 7) |
| `(tabs)/home` | Yes | V2 (Phase 2) |
| `(tabs)/explore` — Search | Yes (pushed from Home header) | V2 (Phase 2) |
| `(tabs)/create` → CreateListingScreen | Yes | V2 (Phase 5) |
| `(tabs)/bids` | Yes | V2 (Phase 4) |
| `(tabs)/profile` | Yes | V2 (Phase 6) |
| `bid/[id]` → PlaceBidScreen | Yes | V2 (Phase 6) |
| `checkout/[id]` → CheckoutNative | Yes | V2 (Phase 3) |
| `listing/[id]` → ListingDetailScreen | Yes | V2 (Phase 1) |
| `listing/edit/[id]` | Yes | V2 (Phase 7) |
| `my-listings` | Yes | V2 (Phase 7) |
| `settings/index` + 9 subroutes | Yes | V2 (Phase 6 / 8) |
| `transfer/receive/[id]`, `transfer/send/[id]` | Yes | V2 (Phase 7) |
| `profile/[id]` — public profile | Yes (from a listing) | V2 (Phase 10) |
| `report/[type]/[id]` | Yes (listing / profile overflow) | V2 (Phase 10) |
| `payout-return` | Yes (Stripe redirect) | V2 (Phase 10) |
| `payout-refresh` | Yes (Stripe redirect) | V2 (Phase 10) |
| `(tabs)/index` | No — group-default **redirect** to `/(tabs)/home`, `href:null` | Redirect only (retained; see §5) |
| Tickets | Not built | **Blocked by Core** (§8) |
| `_dev/foundation` | Dev only | internal |
| `_layout` ×3 | infra | V2 loading state (§5) |

**Reachable user-facing routes: 29. V2: 29. Legacy user-facing: 0. Core-blocked: 1 (Tickets).**

## 4. Owner-approved design system

- **Typography** — Oswald 700 display + Inter body, resolved through `textStyle(token)`; display
  line-heights floored by `safeLineHeight` (`MIN_LINE_HEIGHT_RATIO` 1.25) after the Phase 4 Oswald
  cap-height clipping fix. No AI language, no em-dashes / `--`, no emoji in product copy.
- **Color** — #000 canvas, #0A0A0A surface, #FF1A1A brand red with **black** text on red; red-tinted
  hairlines (gray is not used for borders). `error` is a deliberately different red from `brand.red`.
- **Geometry** — radius 0 everywhere as the brand rule; the one sanctioned exception is the approved
  navigation dock (rounded glass pill), which is frozen.
- **Media** — one `EventMedia` system with typed slots and a `legacy`/`auction-media` contract;
  no ad-hoc `Image` sizing.
- **Pricing** — the all-in money contract preserved end to end: whole dollars in `public.listings`,
  cents internally, rendered through `allInLabel` / `allInFromDollars`. No fee math in the UI.
- **Buttons** — one `Button` primitive (block / loading / disabled states); brand-red primary with
  black label.
- **Inputs** — one `Input` / field treatment: hairline underline, red focus, red selection, tabular
  char counts where capped.
- **Empty / loading states** — `EmptyState`, `Skeleton`, and the a11y-aware `Spinner` (reduced-motion
  renders a static mark; screen readers announce "busy"). "Unknown" is kept distinct from "zero"
  wherever data can be unavailable (e.g. trust stats).
- **Navigation** — the adaptive floating dock (`AdaptiveDock` + `NavDockProvider` +
  `dockMachine`): dark glass pill, selected inner capsule, left-anchored width-contraction collapse
  with scroll-direction hysteresis, keyboard drop, safe-area geometry, and a separate Create CTA
  offset. Built for the five-item `HOME · CREATE · BIDS · TICKETS · PROFILE` order; Tickets slot
  reserved, not rendered.
- **Motion** — RN `Animated` for nav; no decorative motion on transient/legal surfaces; reduced-motion
  respected in the Spinner.
- **Accessibility** — header roles, labelled controls and media rows, radio `selected` state, badges
  that carry their word, progressbar labels.

## 5. Cleanup results

Only the three items the Phase 10 audit identified were considered. Each was proven safe before acting.

- **Dead tab route `(tabs)/index` — RETAINED (not removed).** On inspection this is **not** dead code:
  it is a `<Redirect href="/(tabs)/home" />` that serves as the `(tabs)` group's default index. Expo
  Router resolves `/(tabs)` (no explicit segment) to this file; `unstable_settings.anchor = '(tabs)'`
  and the auth gate route through the group. Removing it introduces real ambiguity in group
  resolution, so per the "leave it if any ambiguity" rule it stays. The audit's "dead" label was
  imprecise — it is reachable by router resolution, just hidden from the tab bar (`href:null`).
- **Root loading state → V2.** `app/_layout.tsx` now renders the a11y-aware `Spinner`
  (`<Spinner size="large" color={v2.brand.red} label="Loading Snatch It" />`) on a `v2.surface.canvas`
  black ground, replacing the raw `ActivityIndicator` on `colors.bg`. Spinner is imported from its
  **leaf module** (`@/src/components/ui/Spinner`), not the `ui` barrel, so the web-safe root layout
  pulls in no native-only siblings; Spinner's own dependencies (`useReducedMotion`, `textStyle`, `v2`)
  are all platform-safe. Now-dead `colors` and `ActivityIndicator` imports were removed from the file.
  Root architecture, the auth gate, font-gating, and routing are unchanged.
- **Dead upload components — REMOVED.** `src/components/ImageUploadField.tsx` and
  `src/components/ImageUploadTile.tsx` were deleted. Proof: nothing imports `ImageUploadField`;
  `ImageUploadTile` is imported only by the (dead) `ImageUploadField`. Production Create and Transfer
  use `MediaUpload`. `tests/media-upload.test.ts` only asserts the *absence* of `ImageUploadTile` in
  the create/transfer sources, so deletion leaves it green; no test imports either component.
- **Intentionally retained:** the `useImageUpload` hook (`src/hooks/useImageUpload.ts`) — still
  consumed by `CreateListingScreen`, `transfer/send/[id]`, and `MediaUpload`. The `MediaUpload` header
  comment that references the legacy tile is accurate history and was left as-is. `_dev/foundation`
  (dev only) and the `(tabs)/index` redirect are retained as above.
- **Dead imports / styles:** only the two dead imports inside the one touched file (`_layout.tsx`)
  were removed. No repository-wide refactor was performed.

## 6. Test health

Baseline (post-Phase-10 checkpoint) → after cleanup:

| Check | Baseline | After cleanup |
| --- | --- | --- |
| Tests | 568 passed / 23 files | **568 passed / 23 files** |
| Typecheck (`tsc --noEmit`) | clean | **clean (exit 0)** |
| Lint (`expo lint`) | 27 warnings / 0 errors | **27 warnings / 0 errors** |
| New warnings | — | **none** |
| Native iOS bundle | HTTP 200 | **HTTP 200, ~14.56 MB, reflects this worktree** |

No test was weakened, skipped, or removed. The deleted components had no dedicated tests, so none were
removed. The lint count is identical (the deleted files carried no warnings; the root-layout edit added
none). The iOS bundle was confirmed to be serving this worktree (it contains the new "Loading Snatch
It" label) and built with no unresolved-import error after the deletions.

## 7. Core boundaries (unchanged, all phases)

No file under `supabase/**`, no migration, RLS policy, RPC, or Edge Function was created or modified.
`src/lib/money.ts`, `src/lib/payments.ts`, and `src/lib/supabase.ts` are untouched. The auth,
payment, transfer, auction, ticket, and venue architectures are unchanged. Every screen reads only
already-authorized data through existing contracts (`get_my_profile`, `get_profile_trust_stats`,
`listings`, `bids`, `transfers`, `reports`, `user_blocks`, Stripe). `kernel.tickets` is never queried.

## 8. Tickets blocker — frontend contract for Core

Tickets is the only major planned frontend surface still blocked, and the block is entirely on the
Core side. Nothing was built, exposed, faked, or stubbed: no Tickets tab, no placeholder, no "coming
soon", no invented ticket records, no fake QR/barcode, no Apple Wallet UI. The dock already reserves
the `ticket.fill` slot (`navItems({ tickets: true })` returns the five-item order with no layout
change); activation is a one-line flip when the contract lands.

### 8.1 Final Tickets product direction (preserved)

- **Primary nav becomes** `HOME · CREATE · BIDS · TICKETS · PROFILE`; Search stays inside Home.
- Tickets is **event-first** and must read as **ownership / attendance**, visually distinct from
  Bids (which is marketplace transaction activity). The two concepts stay separate.
- **YOUR TICKETS** surface: **Upcoming** (event artwork, event name, date/time, venue, ticket type,
  quantity, ownership / fulfillment state) and **Past** (historical, visually quieter). Past is a
  lightweight event history only — no invented attendance verification, friends-who-attended,
  memories, photos, or music integrations unless those become real product contracts.
- **Ticket Detail (future)** hierarchy: event artwork → event identity → date / venue → ticket type →
  quantity → ownership state → delivery / fulfillment state. QR / barcode, Apple Wallet, transfer
  actions, entry instructions, and the ticket identifier appear **only** if Core provides the
  corresponding contract — never inferred from `kernel.tickets` merely existing internally.

### 8.2 The read Core must expose

Frontend needs an **authenticated, owner-scoped read reachable from the client** (RPC, owner-scoped
view, or an RLS-protected read — Core owns which is safest). Frontend must **not** need direct
unrestricted `SELECT` against internal ticket infrastructure. The contract must provide stable,
frontend-safe fields sufficient to render:

- ticket id
- event reference
- event title
- event date / time
- venue name
- event artwork reference / path (if available)
- ticket type / tier
- quantity
- ownership state
- fulfillment / delivery state
- upcoming-vs-past classification, or enough stable event-time data to derive it safely

Also required from Core, documented and stable:

- ticket **status** vocabulary
- **fulfillment** vocabulary
- **error** vocabulary
- **empty-state** semantics (a member with no tickets)
- **authorization** behavior (what an unauthorized or non-owner read returns)

### 8.3 Entry credentials — a separate capability

QR / barcode / Apple Wallet are a **separate** contract and must not be coupled to the first Tickets
read. Before frontend builds them, Core must document: whether Snatch It issues the credential or an
external issuer owns it; credential type; lifecycle; rotation rules (if any); redemption semantics;
screenshot policy (if applicable); offline behavior; and security requirements. Apple Wallet
additionally needs its own issuance / pass contract. A useful Tickets **ownership** screen can ship
before Wallet / QR as long as Core's ownership read is safe.

### 8.4 Nav activation (when unblocked)

Flip the already-built Tickets-ready nav configuration; **do not redesign the dock**. Verify the
five-item geometry on a physical device at that time.

## 9. Remaining frontend work

- **BLOCKED (by Core):** the Tickets product surface (§8) — read contract, then optionally the
  QR / barcode / Wallet credential contract.
- **OPTIONAL:** a standalone owner device review of **Explore/Search** (`app/(tabs)/explore.tsx`) — it
  has been V2 since Phase 2 and compiles and passes, but was never reviewed on its own screen. It
  searches `public.listings` on `event_name` / `venue` (ilike), blocked-seller filtered, reached from
  the Home header; it is not a regression, only un-reviewed in isolation.
- **NONE otherwise:** every reachable user-facing surface is on the approved V2 system. No further
  redesign work is outstanding, and none was manufactured to fill this section.

## 10. Production readiness note

This is a **frontend V2 readiness** statement. The mobile presentation layer is complete and internally
verified (tests / typecheck / lint / native bundle). It does **not** assert that the Snatch It
application as a whole is production-ready: backend deployment, payments, release configuration, and
the Tickets contract remain Core's responsibility and must be established separately.

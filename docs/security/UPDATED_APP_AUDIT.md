# Updated App Audit — Marketplace Expansion (pre-build)

**Date:** 2026-06-12 · **Scope:** ticket transfer platforms, event categories, Miami locations/venues, splash bug, admin system, report/dispute notifications, proof-of-ownership MVP, App Review safety. Research basis: `docs/product/TRANSFER_METHOD_RESEARCH.md` (official sources only, created before any change).

## 1. Ticket Transfer Platforms

**Before:** 6 platforms (`dice, eventbrite, posh, axs, ticketmaster, other`) with two factually wrong instruction sets — DICE described an email transfer (officially it's app-only via phone contacts) and Eventbrite described a "Transfer" button (officially there is no account transfer; the purchaser edits the order's attendee name/email).

**After:** 16 research-confirmed platforms. `src/lib/platformInstructions.ts` fully rewritten from official documentation: corrected DICE + Eventbrite; added SeatGeek, Tixr, Fever, Shotgun, Universe, See Tickets, MLB Ballpark, StubHub, Vivid Seats, Gametime. Every screenshot warning in app copy is backed by an official statement (Ticketmaster SafeTix, DICE, SeatGeek, StubHub-rotating, Tixr NFC/rotating-QR); platforms with no official statement carry neutral copy — **no unsupported claims**. The MLB recall-before-scan risk is surfaced to buyers as a warning. Front Gate (III Points/Rolling Loud) and Ultra were researched but **deliberately not added** (transfer mechanics unconfirmed → "Other"). The existing `PlatformInstructions` component on the Send and Receive transfer screens reads from the map, so both screens are platform-specific automatically — no screen changes needed. DB CHECK constraint expanded in migration 033.

## 2. Event Categories

New required `listings.category` column (default `'nightlife'`, backfilled) with 8 values: Nightlife, Clubs, Concerts, Festivals, Sports, Music, Special Events, Other. UI: category pills in listing creation (`CreateListingScreen`), a CATEGORY section in the home Filters modal with multi-select chips + filter logic + active-count badges, and a Category row on listing detail. Explore feed remains a simple chronological feed (no filters there today — unchanged by design). Existing GA/VIP chips untouched.

## 3. Miami Locations / Venues

`src/constants/neighborhoods.ts` restructured into three groups — **Areas** (19: original 9 + Little River, Little Haiti, Hialeah, Doral, Kendall, Coral Gables, Aventura, Sunny Isles, Fort Lauderdale, Hollywood), **Clubs & Nightlife** (10: Club Space, The Ground, E11EVEN, LIV, Story, M2 Miami, Daer, Oasis Wynwood, Factory Town, Mana Wynwood), **Arenas, Stadiums & Live Music** (10: Kaseya Center, Hard Rock Stadium, loanDepot park, FPL Solar Amphitheater, Bayfront Park, Hard Rock Live, Amerant Bank Arena, Chase Stadium, The Fillmore Miami Beach, Miami Beach Bandshell — the latter two discovered during research). The creation picker is now **searchable with group headers**; the flat `NEIGHBORHOODS` export is preserved so home filters, Your Scene preferences, and existing listings keep working. Existing keys untouched — no data migration needed. Miami Marine Stadium: not added (no active ticketed venue platform confirmed).

## 4. Splash Screen Bug — root cause + fix

**Root cause:** the committed iOS native project was generated from an older Expo config. `Images.xcassets/SplashScreenLogo.imageset` contained stale artwork (hashes matched neither current asset) at 200pt, and `SplashScreenBackground.colorset` was `#0B0F14` (dark navy) instead of app.json's `#E9031E`. Because `ios/` is checked in, EAS uses it as-is — app.json's `expo-splash-screen` config (correctly pointing at `splash-icon.png`) was never re-applied. **Fix (surgical, no prebuild, icon untouched):** regenerated the imageset (200/400/600 px) from `assets/images/splash-icon.png` and set the background colorset to `#E9031E` (light + dark). Verified: new @3x corner pixel `(233,3,30)` = exact brand red = seamless edge-to-edge splash. Note for later: `splash-icon.png` is RGB (no alpha) — fine since its baked background exactly matches; if the logo ever changes, use a transparent PNG.

## 5. Admin Account / Admin System

Migration 033 creates `public.admin_users` — RLS enabled with **zero client policies** and explicit `REVOKE` from PUBLIC/anon/authenticated, so the only write path is the service role (dashboard/ops). Seeded with the verified production profile **SNATCH IT APP ADMIN** (`2b117757-f4e3-41c1-b7df-68a4502d0fba`). `public.is_admin()` (SECURITY DEFINER, pinned search_path, evaluates `auth.uid()` only, anon revoked) lets the app gate future admin UI. **No self-promotion is possible from the client by construction**; admin-only actions (`admin_resolve_dispute`, `delete_account_cleanup`, `proof_status` changes) are already service-role-only from migrations 032/033. No admin dashboard screen exists yet — admin work remains via the ops SQL packs; `is_admin()` is the safe hook for a future in-app dashboard.

## 6. Reports / Disputes / Admin Notifications

**Verified current state:** no Resend integration existed anywhere (no key, no imports); push exists via `send-push`; **no SMS provider exists — SMS deliberately NOT implemented** per instructions. **Implemented pipeline:** migration 033 adds fire-and-forget AFTER-triggers on `reports` (insert) and `transfers` (→ `disputed`) that call the new `notify-report` edge function via pg_net + Vault (the proven cron auth pattern); a notification failure can never block the report/dispute itself. The function sends: admin push (to all `admin_users`) + admin email to `support@snatchitapp.com`; reporter acknowledgment; "under review — do not complete off-platform arrangements" push/email to the reported party (neutral copy, no accusation) and to both dispute parties. **Email safety:** Resend sends are gated behind `EMAIL_ENABLED === 'true'` (default OFF) — tests can never send mail; sender `no-reply@snatchitapp.com`, admin inbox `support@snatchitapp.com`, both overridable via env. Requires post-deploy secrets (commands below).

## 7. Proof of Ownership — MVP shipped

**What's collected:** one required proof screenshot at listing creation (unchanged UX). **Where stored — fixed a privacy gap:** previously proofs went to the **public** `auction-media` bucket (anyone with the path could fetch a screenshot that may contain the seller's email/order numbers). Now they upload to the new **private `proof-docs` bucket** (migration 033): owner-only RLS read/write, admin review via service role, no public access path at all. **Review flow (manual for TestFlight — intentionally no OCR/AI; nothing of the sort exists in the stack and it would be overbuild):** every listing starts `proof_status='pending_review'`; an admin sets `approved`/`rejected` via service role (a guard trigger blocks any client from touching `proof_status` — no self-verification possible); the listing-detail badge "✓ Reviewed by Snatch It" renders **only when approved**, so the app never shows a fake verification claim. Listings stay live while pending — gating visibility on review was considered and deferred because it would touch every tested feed/buy path right before TestFlight; `rejected` is the ops signal to cancel the listing. What stops random screenshots: manual admin review cross-checking platform/event/date against the listing, the existing seller-risk scoring, and disputes/trust metrics downstream.

## 8. App Review / Safety check (post-change)

No private payment data, emails, or phones exposed (proof images now strictly private; notification emails resolved server-side only). No fake verification claims (badge is admin-gated). No unsupported platform transfer claims (research-gated copy; unverified platforms excluded). No screenshots-as-ticket claims except Eventbrite/StubHub-static where officially supported — and rotating-barcode bans are quoted where official. Report/Block flows untouched and now *more* compliant (active moderation notifications support Guideline 1.2's "act on reports" expectation). Account deletion untouched (admin_users rows cascade on user deletion). Stripe/payment/webhook logic untouched; `stripe-webhook` untouched.

## Deliverables / Files changed

**New:** `docs/product/TRANSFER_METHOD_RESEARCH.md` · `docs/security/UPDATED_APP_AUDIT.md` · `supabase/migrations/033_marketplace_expansion.sql` · `supabase/functions/notify-report/index.ts` · `src/constants/categories.ts`
**Modified:** `src/types/index.ts` (TicketPlatform 16, EventCategory, ProofStatus, Neighborhood 39, Listing fields) · `src/constants/neighborhoods.ts` (grouped + 30 new entries) · `src/lib/platformInstructions.ts` (rewritten, 16 platforms) · `src/screens/CreateListingScreen.tsx` (platforms, category pills, searchable grouped venue picker, private proof bucket, insert) · `app/(tabs)/home.tsx` (category filters) · `src/screens/ListingDetailScreen.tsx` (category row + proof badge) · `src/hooks/useImageUpload.ts` (bucket option) · `ios/snatchit/Images.xcassets/SplashScreenLogo.imageset/*` + `SplashScreenBackground.colorset/Contents.json` (splash fix)
**Untouched:** payments, Stripe webhooks, transfer state machine, auth, report/block screens.
`npx tsc --noEmit`: zero errors in changed files (only pre-existing landing-v2/NativeAppShell issues remain).

## Exact commands

```bash
cd /Users/josetascon/snatchit
git add docs/product/TRANSFER_METHOD_RESEARCH.md docs/security/UPDATED_APP_AUDIT.md \
  supabase/migrations/033_marketplace_expansion.sql \
  supabase/functions/notify-report \
  src/types/index.ts src/constants/neighborhoods.ts src/constants/categories.ts \
  src/lib/platformInstructions.ts src/screens/CreateListingScreen.tsx \
  src/screens/ListingDetailScreen.tsx "app/(tabs)/home.tsx" src/hooks/useImageUpload.ts \
  ios/snatchit/Images.xcassets/SplashScreenLogo.imageset \
  ios/snatchit/Images.xcassets/SplashScreenBackground.colorset/Contents.json
git commit -m "feat: marketplace expansion — 16 verified transfer platforms, categories, Miami venues, admin system, moderation notifications, private proof review, splash fix"

# Apply DB changes:
supabase db push                       # applies migration 033

# Deploy + configure the notification function (emails stay OFF until enabled):
supabase functions deploy notify-report
supabase secrets set RESEND_API_KEY=<your-resend-key> \
  EMAIL_FROM="Snatch It <no-reply@snatchitapp.com>" \
  ADMIN_EMAIL="support@snatchitapp.com"
# When ready for live email (production only):
supabase secrets set EMAIL_ENABLED=true
```

## Is an EAS build required?

**Yes** — the splash fix lives in native iOS assets (`Images.xcassets`), which only ship in a new binary, and the JS changes must be compiled into the bundle for TestFlight. Per instructions, **no build was run**; run `eas build --platform ios --profile production` when ready. The DB migration + edge function deploy are independent of the build and safe to apply first (the app handles `category`/`proof_status` both present and absent).

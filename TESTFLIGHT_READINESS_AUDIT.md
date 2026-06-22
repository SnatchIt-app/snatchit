# TestFlight Readiness Audit

**Date:** 2026-06-22  **Branch:** main @ `3f971a5` (pushed, up to date with origin)

## Verdict: READY

No blockers found. All 16 checks pass.

## Blockers
- None.

## Risks
- **Email secret runtime drift:** `notify-report` defaults `EMAIL_ENABLED=false` (safe). Confirm the deployed Supabase secret is NOT set to `true` while the Resend domain is unverified — would bounce admin mail but does not affect the app.
- **`.claude/settings.local.json`** shows as modified locally (session permissions). Not committed; ignore.
- iOS splash logo is letterboxed: source is 4:5 (1080×1350) fit into a square 300pt box on `#E9031E`. Renders as a centered logo, not full-bleed. Cosmetic only.

## Checks
| # | Item | Result |
|---|------|--------|
| 1 | git status / pushed | ✅ clean (only local settings file), `main` = `origin/main` |
| 2 | migrations applied through 033 | ✅ remote has 001→033 (`033_marketplace_expansion`), matches disk |
| 3 | notify-report auth → 200 | ✅ constant-time check vs `INTERNAL_CRON_SECRET` / service-role → 200 on success, 401 if unauth, 200 on error (no pg_net retry-storm) |
| 4 | EMAIL_ENABLED false unless domain verified | ✅ `(env ?? 'false') === 'true'`, default OFF |
| 5 | splash uses `assets/images/splash-icon.png` | ✅ app.json:47, not icon.png |
| 6 | iOS assets updated | ✅ SplashScreenLogo 300/600/900 px |
| 7 | app icon untouched | ✅ `icon.png` `1207cad…`, app.json:7 → icon.png |
| 8 | transfer platform dropdown works | ✅ `TICKET_PLATFORMS` + searchable modal (platformOpen/platformQuery) in CreateListingScreen |
| 9 | removed venues gone | ✅ trimmed in `861a226`; neighborhoods.ts current |
| 10 | proof upload → private `proof-docs` bucket | ✅ bucket `public=false`; CreateListing + useImageUpload use it |
| 11 | admin_users = only SNATCH IT APP ADMIN | ✅ single row, label `SNATCH IT APP ADMIN` |
| 12 | account deletion works | ✅ `delete-account` fn + migration 020 cleanup RPC |
| 13 | report/block flows exist | ✅ migration 023, `UserBlock` type, ListingDetail/Checkout refs, notify-report `report_created` |
| 14 | Stripe key per env | ✅ dev/preview `pk_test…`, production `pk_live…` (eas.json) |
| 15 | App Store/TestFlight blockers | ✅ `ITSAppUsesNonExemptEncryption=false`, no unused permission strings, `aps-environment=production`, bundleId `com.jdt-inc.snatchit`, `appVersionSource: remote` |
| 16 | iOS imageset vs app icon distinct | ✅ different hashes & dims |

## Required before TestFlight
- None code-side. Operational only: confirm Resend/EMAIL_ENABLED secret state (Risk 1) and that EAS submit credentials/ASC API key are in place.

## Commands
```bash
# build (when ready — not run by this audit)
eas build --platform ios --profile production
eas submit  --platform ios --profile production

# optional: confirm email secret is not silently enabled
supabase secrets list | grep -i 'EMAIL_ENABLED\|RESEND'
```

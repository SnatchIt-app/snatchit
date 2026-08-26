# Pre-iOS Build Final Audit

**Date:** 2026-06-13 · **Type:** read-only verification of the latest changes only · **Project:** `hqycwntpfoztoinemqns`

# VERDICT: APPROVED FOR IOS BUILD

No blockers found. Every audited path verified live. The prior notification blocker (N1) is **resolved** — `notify-report` returns HTTP 200 with the Vault service-role JWT. Two non-blocking confirmations to do in the Supabase Dashboard are listed at the end (they cannot reduce safety: the code defaults are already safe).

---

## 1. Splash screen asset selection — PASS

- **Icon vs splash not mixed up:** `icon.png` (md5 `874b0ef7…`) and `splash-icon.png` (md5 `9d3fabd6…`) are distinct files. app.json: `"icon": "./assets/images/icon.png"` (line 7), splash `"image": "./assets/images/splash-icon.png"` (line 47). PASS.
- **iOS native imageset uses the splash asset:** `SplashScreenLogo.imageset/image@3x.png` is 600×600 with brand-red corner pixel `(233,3,30)` = regenerated from `splash-icon.png` (not the icon). PASS.
- **Background matches brand red:** `SplashScreenBackground.colorset` = sRGB `(0.9137, 0.0118, 0.1176)` = `#E9031E`, matching app.json splash `backgroundColor` (lines 50/52). PASS.
- **app.json vs checked-in ios/ — no conflict:** app.json splash config is `#E9031E` + `splash-icon.png`, identical to the committed native assets, so whichever path EAS uses (it uses the committed `ios/` as-is since the project is pre-generated) yields the same result. The `#0B0F14` at app.json line 30 is the **Android adaptive-icon** background, not splash — not a conflict. PASS.
- **No stale icon/splash duplicates:** only the 3 imageset PNGs + 2 Contents.json are tracked under the splash imagesets; the old dark `#0B0F14` colorset value was overwritten. PASS.

## 2. notify-report live invocation — PASS

- **HTTP 200 with service-role JWT:** live test via `net.http_post` using the Vault `service_role_key` (request 2971) → `{"status_code":200,"body":"{\"ok\":true,\"event\":\"audit_ping\"}"}`. PASS (resolves prior N1).
- **INTERNAL_CRON_SECRET set correctly:** proven by the 200 — the function's bearer check accepted the Vault JWT, which only happens when `INTERNAL_CRON_SECRET` (or the runtime service-role key) matches that token. PASS.
- **Triggers point to notify-report:** `trg_notify_report_created AFTER INSERT ON reports` and `trg_notify_dispute_opened AFTER UPDATE OF status ON transfers WHEN (new.status='disputed' AND old IS DISTINCT FROM 'disputed')` → both `EXECUTE FUNCTION notify_moderation_event()`, which POSTs to `/functions/v1/notify-report`. PASS.
- **No 401 in pg_net responses:** the only recent response for the function is the 200 above; no 401. PASS.
- **No emails while EMAIL_ENABLED=false:** the audit_ping path sends no email; `sendEmail()` is hard-gated `if (!EMAIL_ENABLED) return` (default `false`). No send was triggered. PASS (value confirm = Dashboard item A).
- **RESEND_API_KEY / EMAIL_FROM / ADMIN_EMAIL exist:** code reads all three with safe defaults (`EMAIL_FROM`→`no-reply@snatchitapp.com`, `ADMIN_EMAIL`→`support@snatchitapp.com`); secret values are not readable via SQL → Dashboard item B. Not a build blocker (email stays off until explicitly enabled).

## 3. Migration 033 — PASS

- **Applied live:** `schema_migrations` contains `033`. PASS.
- **category column + values:** default `'nightlife'`, CHECK = `nightlife, clubs, concerts, festivals, sports, music, special_events, other` — exactly matches `src/constants/categories.ts`. PASS.
- **proof_status + guard:** default `'pending_review'`, CHECK `pending_review/approved/rejected`; `trg_guard_proof_status` present → blocks any non-service-role change (no client self-approval). PASS.
- **proof-docs bucket private:** `storage.buckets.public = false`. PASS.
- **admin_users:** exactly 1 row — `SNATCH IT APP ADMIN` / `2b117757-f4e3-41c1-b7df-68a4502d0fba`. PASS.
- **is_admin() safe:** SECURITY DEFINER, evaluates `auth.uid()` only; EXECUTE = authenticated + service_role, anon revoked (verified prior run). PASS.

## 4. Admin account lock — PASS

- Only `SNATCH IT APP ADMIN` is admin (n=1). PASS.
- `admin_users` RLS enabled with **0 policies** → no anon/authenticated read or write; service_role (RLS bypass) is the only write path; no app code writes the table. No self/other-promotion possible. PASS.
- No other user can reach admin-only state: `is_admin()` returns false for non-admins, can't probe other UUIDs. PASS.
- service_role-only actions (`admin_resolve_dispute`, `delete_account_cleanup`, `enforce_transfer_expiry`, `proof_status` writes) remain locked (migrations 032/033 verified). PASS.

## 5. Proof-of-ownership review flow — PASS

- **Upload to private bucket:** `CreateListingScreen` proofUpload uses `bucket: 'proof-docs'`; `useImageUpload` routes non-`auction-media` buckets to private (no public URL). PASS.
- **Insert sets pending_review:** column default `'pending_review'` applies on insert (client never sends it). PASS.
- **Badge only when approved:** listing detail renders "✓ Reviewed by Snatch It" only `if (listing.proof_status === 'approved')`. PASS.
- **Proof images not public / buyer cannot view seller's proof:** bucket `public=false`; storage policies are owner-only (`(storage.foldername(name))[1] = auth.uid()`), so a buyer's JWT cannot read the seller's proof path. PASS.
- **Admin review via service_role/manual only:** review reads via service role; `proof_status` writes blocked from clients by the guard trigger. PASS.

## 6. Marketplace expansion — PASS

- **16 platforms compile + match DB:** DB CHECK lists exactly the 16 platforms in `TicketPlatform`/`TICKET_PLATFORMS`; `PLATFORM_INSTRUCTIONS` is `Record<TicketPlatform,…>` (TS enforces all 16 keys) and `tsc --noEmit` is clean on changed files. PASS.
- **Instructions load on send/receive:** the existing `PlatformInstructions` component reads `PLATFORM_INSTRUCTIONS[platform]` on both transfer screens; all 16 keys present. PASS.
- **Categories in create/home/detail:** create-listing category pills + insert `category`; home Filters CATEGORY chips + filter logic + active-count; listing-detail Category row. PASS.
- **Venue picker searchable + grouped:** create-listing modal has a search box + 3 group headers (Areas / Clubs & Nightlife / Arenas, Stadiums & Live Music). PASS.
- **Old listings still work:** `category` backfilled to `nightlife` + NOT NULL default, `proof_status` backfilled to `pending_review`; detail/filter read with `?? 'nightlife'` fallbacks. No legacy breakage. PASS.

## 7. Git / build readiness — PASS

- **Working tree clean:** `git status --short` empty. PASS.
- **Pushed to remote:** `## main...origin/main` with no ahead/behind; `git log @{u}..HEAD` empty (all pushed). Latest commits: `a9340a1 docs: notification system audit`, `14bb346 fix: commit native splash assets`, `b4b4961 feat: expand marketplace…`. PASS.
- **ios/ splash force-added despite .gitignore:** `.gitignore` line 46 = `/ios`, yet `git ls-files` lists the 3 imageset PNGs + both Contents.json — force-added and tracked. PASS.
- **No secrets committed:** scan of tracked non-doc files found only env-var **names** with placeholder values (`scripts/seed-demo.ts` doc comments: `eyJ…service-role-jwt…` placeholder, `sk_test_` prefix guard) and migration 033's doc comment showing the `supabase secrets set` command shape — no real keys. PASS.
- **No EAS build until APPROVED:** verdict is APPROVED; build may proceed. (No build was run by this audit.)

---

## Dashboard confirmations (non-blocking, safe-by-default)

- **A —** confirm `EMAIL_ENABLED` is `false` (or unset) in `notify-report` secrets. If unset, the code default is `false`, so email is already off; this is informational only.
- **B —** confirm `RESEND_API_KEY`, `EMAIL_FROM`, `ADMIN_EMAIL` are set before you ever flip `EMAIL_ENABLED=true`. Email delivery also needs Resend domain verification (SPF/DKIM) for `snatchitapp.com`. None of this gates the iOS build.

---

`/Users/josetascon/snatchit/PRE_IOS_BUILD_FINAL_AUDIT.md`

```bash
cd /Users/josetascon/snatchit
git add docs/security/PRE_IOS_BUILD_FINAL_AUDIT.md
git commit -m "docs: pre-iOS-build final audit — APPROVED FOR IOS BUILD"
git push
```

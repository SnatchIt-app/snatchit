# Venue dashboard → https://venue.snatchitapp.com — deployment package

**Status: runbook only. Nothing in this file has been executed.** No migration, exposure, tenant row, Vercel project, deploy, DNS edit or credential entry is authorised by this document. Every OWNER step needs its own explicit go. Prepared 2026-10-21 from read-only evidence (§16). Decision IDs refer to `OWNER_DECISIONS.md`. The shared hosting reasoning (proxy mode, wildcard, SSL mode, same-site cookies) is set out in full in `ADMIN_HOSTING_admin.snatchitapp.com.md` §3, §6 and §8, and is only summarised here.

## 0. Summary
- **Today:**
  - Only a fixtures demo exists: `snatchit-venue-demo` (`prj_X9OGradc82yDlEf4AfDDmHTJfnI1`). It is CLI-deployed, not Git-linked, protected by Vercel SSO "all", and it serves commit 512e01e3, which is 25 commits behind v2.
  - `venue.snatchitapp.com` answers 404 DEPLOYMENT_NOT_FOUND through the Cloudflare wildcard.
- **Database mode is blocked by data and schema, not by hosting:**
  - the `venue_api` migration is applied nowhere and needs a new version number from A;
  - `venue_api` is not an exposed schema;
  - production has 0 organisations, venues and staff roles;
  - B's PFA-18C standing restriction forbids creating them.
- **Recommendation:**
  - Create a **new Git-linked project `snatchit-venue`** (root `venue`, a SHA-pinned Ignored Build Step like admin's, production branch `venue/production`).
  - Keep the demo project as the owner-only fixtures demo.
  - Bring `venue.snatchitapp.com` up **dark** first, behind Vercel SSO "All Deployments", so only the owner can open it. That proves DNS, TLS and database wiring without exposing a public login.
  - Switch to public only after the tenant bootstrap decision (V-06, V-08).

## 1. Current state (verified read-only 2026-10-21 unless marked "record")
| Item | Value |
|---|---|
| Demo project | `snatchit-venue-demo` `prj_X9OGradc82yDlEf4AfDDmHTJfnI1`. framework/rootDirectory null, `link` null, `ssoProtection: all`, Node 24.x. Domain: only `snatchit-venue-demo.vercel.app` |
| Demo production deployment | `dpl_4Rht1KT12uiuLqTEaSvdYE79eVhe` = `snatchit-venue-demo-6d3o29igc-gnvprod-5449s-projects.vercel.app`, cli, sha 512e01e3, 2026-10-06. Every URL answers 302 to vercel.com/sso-api |
| Demo env (names only) | `NEXT_PUBLIC_VENUE_DATA_SOURCE` [production, development]. No Supabase variables, so DB mode is impossible on that project |
| Team | Hobby, 1 member. Commercial use needs Pro (Vercel fair-use page: "Hobby teams are restricted to non-commercial personal use only") — H-08 |
| `venue.snatchitapp.com` | Cloudflare proxied wildcard → Vercel → 404 DEPLOYMENT_NOT_FOUND. The cert Vercel presents for it is the expired `*.snatchitapp.com` (2026-10-07), so a dedicated cert must be issued before DNS only (as for admin) |
| Candidate names | `snatchit-venue.vercel.app` answers 404 DEPLOYMENT_NOT_FOUND today (looks unclaimed, not guaranteed) |
| Code | `origin/venue/dashboard-v2` ee1d90b7 (code bb94b1f2); CI green there (venue 11 files/157 tests, build OK; pgTAP 188 ok). The production-readiness work is on **local, unpushed** `venue/production-readiness` (tip f1cb4e16 at the time of writing, still moving — a sibling task; not gated or verified by me) |
| `venue/` presence | absent on `main`, `admin/operating-console`, the production gate and the candidate. Present only on venue/* branches |
| DB mode reads | 8 `venue_api` views only, server-side, anon key plus the staff member's JWT. No RPC, no writes, no browser Supabase client |
| Migration (record + git) | `supabase/migrations/20260910120000_venue_api_read_views.sql` (sha256 4106b9d0…46d4a3), rollback `supabase/rollbacks/20260910120000_venue_api_read_views_rollback.sql`, pgTAP 188 (47 assertions). **Applied nowhere.** It cannot enter the gate under its current version (migrations-guard rule 4: the gate tip is 20261013000000, or 20261015000200 after #110), so A must assign a version above 20261015000200 and update the 17 files that hard-code the string |
| Production schema (record) | 076–120 applied (2026-09-02..09). Exposed schemas `public, graphql_public, kernel, ops` (2026-09-08). Native rows 0 (2026-09-12; no later count). Restriction: "no production venue, staff role, manifest, device or PIN creation" (PHASE2_PRODUCTION_STATE:24) |
| Sandbox (record) | `ofaidukbieeekqaboscm`: venue_api absent; only the read-only preflight (8/8, 2026-09-14) has run. The apply/expose/fixtures/api/browser phases never ran |

## 2. Project shape — recommendation
| | **New project `snatchit-venue` (recommended)** | Reuse `snatchit-venue-demo` |
|---|---|---|
| Data source | Production = database; Preview/Dev = fixtures | must flip Production to database, so the demo is lost or moves to Preview |
| Provenance | Git builds of an exact SHA (the demo CLI upload shipped untracked `tsconfig.tsbuildinfo`) | CLI uploads from a local tree |
| Protection | SSO "all" while dark, then Standard at go-live | the demo must stay "all"; production needs Standard |
| Rollback history | clean, production-only | mixed with demo deployments; on Hobby only the previous deployment can be rolled back to |
| Mis-deploy risk | a fixtures build cannot reach venue.snatchitapp.com unless Production env is changed | one `vercel deploy --prod` from a fixtures checkout puts "Demo — sample data" on the production host |
| Cost | one more project (Hobby allows it) | none |

**Settings for `snatchit-venue`**:
- name `snatchit-venue`; framework Next.js; **Root Directory `venue`**
- Node.js 22.x; the effective build Node is 24.x because `venue/package.json` engines is `>=22.0.0 <25.0.0`, same as admin
- install `npm ci` and build `next build` (defaults); function region `iad1`, matching admin
- **Ignored Build Step:** `test "$VERCEL_GIT_COMMIT_SHA" != "<APPROVED_VENUE_SHA_40>"`
- Preview Branch Tracking **off**, `previewDeploymentsDisabled` true
- Production Branch **`venue/production`**: a new branch at the approved SHA, protected by a ruleset (deletion, non-fast-forward, pull request, required check "Venue dashboard preview (Next.js)"); V-02
- Deployment Protection **Vercel Authentication: All Deployments** until V-08, then **Standard** (`all_except_custom_domains`)

**Order matters** (the admin 2026-09-08 lesson):
1. Set the root, the ignore step and Preview tracking **before** connecting Git.
2. Vercel validates the Root Directory before the Ignored Build Step. Without step 1, pushes to branches with no `venue/` create errored Preview deployments and failure emails.
3. Create the project without Git first (CLI or API). The dashboard "Import" flow deploys the default branch (`main`, which has no `venue/`) immediately.

## 3. Database-mode go-live order (each gate must pass before the next)
| # | Step | Who | Gate / evidence | Rollback |
|---|---|---|---|---|
| G1 | **A numbers the migration.** Re-timestamp `20260910120000_venue_api_read_views` (and its rollback) to an A-assigned version above `20261015000200`, update all 17 references (kit preflight/verify-apply/accept.mjs, `adapters.ts`, `read-result.ts`, tests, docs) and add the registry row. The SQL body stays byte-identical except the header. | A (code) | a grep for the old version returns 0; the migrations job applies it in order; pgTAP 188 passes | revert the commit (never applied, so immutability does not bind) |
| G2 | **Release candidate.** `venue/production-readiness` (kit merged, sb_secret guard, mode-aware titles, fail-closed entry, loading states, resale fallback, `.vercelignore`) plus G1 plus the §11 code items. CI green: venue typecheck/lint/test/build, migrations job, migrations-guard. Migration PRs need a fresh `AUTODEPLOY-VERIFIED-OFF: YYYY-MM-DD` marker (V-12). Draft PR against the integration base A names, **not** `admin/operating-console` (merging there redeploys admin's production branch). | D/F, A | CI run id and green checks | close the PR |
| G3 | **Local rehearsal.** Replay the production-order chain locally (076–156 as applied, plus G1's file), then: pgTAP 188; rollback and idempotent re-apply; kit `--phase all` against the G2 commit (local only, the kit refuses production: target.mjs:14,47). | D | kit PASS count; replay ledger matches | drop the local DB |
| G4 | **Sandbox window** (`ofaidukbieeekqaboscm`), owner names the window id. Kit phases in order: preflight → apply → verify-apply → **owner exposes `venue_api` on the sandbox** → verify-exposure → fixtures → api → browser → precedence → revocation → cleanup → postflight (HOSTED_ACCEPTANCE_RUNBOOK). A witnesses the ledger count and Gate-2 census before and after. | D runs; A witnesses; OWNER exposes and reviews 3 PNGs | every phase PASS; stop conditions per the runbook | remove `venue_api` from exposed schemas → cleanup → rollback file → ledger row delete |
| G5 | **Production apply** (owner go, A witness). Pre-read: ledger count and tip, Gate-2 census, `select to_regnamespace('venue_api')` is null, exposed list without venue_api. Apply the single file through `supabase db query --linked --project-ref hqycwntpfoztoinemqns -f supabase/migrations/<A_VERSION>_venue_api_read_views.sql` plus the explicit ledger row (the 2026-09-08 method). **Never `db push`.** Post-read: 8 views, `reloptions` contain `security_invoker=true` and `security_barrier=true`, SELECT granted to `authenticated` only, `anon` has no USAGE, ledger +1, census otherwise unchanged. | OWNER go; A applies or witnesses | post-read output | rollback file plus ledger row delete (A) |
| G6 | **Exposure** (owner, Supabase dashboard with MFA): Integrations → Data API → Settings → Exposed schemas. Re-read, then add **`venue_api` only**. Result: `public, graphql_public, kernel, ops, venue_api`. | OWNER | owner-run checks (anon key is public-class; do not paste it into shared logs): `curl -s -o /dev/null -w '%{http_code}' -H "apikey: $ANON" -H "Accept-Profile: venue_api" https://hqycwntpfoztoinemqns.supabase.co/rest/v1/nonexistent` → **404** (406 before); `curl -s -H "apikey: $ANON" -H "Accept-Profile: venue_api" "https://hqycwntpfoztoinemqns.supabase.co/rest/v1/venues?select=venue_id&limit=1"` → permission denied (42501); `Accept-Profile: catalog` → still **406** | remove `venue_api` from the list (fast lever: closes the API surface, leaves the views) |
| G7 | **Read-only verification** (A/D, owner go for a production read). Signed-in non-staff sees 0 rows in `my_staff_roles`/`my_org_roles`; base-table counts are unchanged. Note the new surface: any signed-in consumer can now read what base RLS already allows (approved venues, non-draft events, public ticket types, `remaining`), which is 0 rows today. | A/D | query output | as G6 |
| G8 | **Vercel project and env** (§4 V1–V4). Independent of G1–G7 and can be done early, but **no domain** until G10. | OWNER | project GET shows the settings | delete the project only if never deployed; otherwise keep it and remove its domains |
| G9 | **Tenant bootstrap decision** (V-06, owner with B). (a) Stay at zero data: dark launch only, and nobody can enter. (b) Lift the restriction **for org, venue and staff-role rows only** (not manifests, devices or PINs) and bootstrap one real tenant with an operator SQL pack using exact ids: organization + owner `org_member`, `catalog.venue` + approve, `venue.staff_role` grants, through existing functions (`catalog.create_venue`/`approve_venue`, `venue.grant_staff_role`, `kernel.set_org_status`). Pack tested on the local replay and the sandbox first. (c) Revive onboarding migration 138 with a new timestamp. | OWNER + B; A/B author the pack | B's written lift; a pack PASS on the sandbox | delete by exact ids (pack's reverse section) |
| G10 | **Deploy** (§4 V5–V9): pin the approved SHA, build, attach the domain, issue the cert, add DNS, verify dark, then go public per V-08. | OWNER | §12 checklist | §13 |

Independent work while A or B is pending: G2 code items, G3, the V1–V4 project setup, and drafting the G9 pack. None of these is a production write.

## 4. Vercel steps (OWNER)
`T=team_rld7LG9DKzgaph97l4H4jl9d`. The session's API token cannot create projects in this team (403, DEPLOYMENT.md), so the owner runs V1, or re-authenticates the CLI to the team scope.

- **V1. Create the project without Git.**
  - CLI: `vercel project add snatchit-venue --scope gnvprod-5449s-projects`.
  - Or API: `vercel api "/v11/projects?teamId=${T}" -X POST --input project.json` with
    ```json
    {"name":"snatchit-venue","framework":"nextjs","rootDirectory":"venue","commandForIgnoringBuildStep":"test \"$VERCEL_GIT_COMMIT_SHA\" != \"<APPROVED_VENUE_SHA_40>\""}
    ```
  - Verify: `vercel api "/v9/projects/snatchit-venue?teamId=${T}"` shows rootDirectory `venue`, the pin, and no `link`.
  - Rollback: delete the project (only while it has no deployments).
- **V2. Settings before Git.**
  - General: Node.js 22.x.
  - Build & Deployment: Ignored Build Step "Custom" with the pin above.
  - Deployment Protection → Vercel Authentication **All Deployments** (`ssoProtection.deploymentType = all`).
  - Environments → Preview → Branch Tracking **off**.
  - Verify: project GET shows `ssoProtection.all`, the pin, and `previewDeploymentsDisabled: true` (if the field is not settable on create, set it after V4 and re-read).
- **V3. Environment variables.** `NEXT_PUBLIC_*` values are inlined at build, so set them before the first build.

  | Name | Production | Preview | Development |
  |---|---|---|---|
  | `NEXT_PUBLIC_VENUE_DATA_SOURCE` | `database` | `fixtures` | `fixtures` |
  | `NEXT_PUBLIC_SUPABASE_URL` | `https://hqycwntpfoztoinemqns.supabase.co` | — (unset) | — |
  | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | owner pastes the production **anon** JWT (`role: anon`) or **`sb_publishable_…`** key, the same class as snatchit-admin Production. **Never** `service_role` or `sb_secret_…` | — | — |
  | `NEXT_PUBLIC_ENV_LABEL` | `production` | `preview` | `local` |

  - Preview carries no Supabase variables, so no preview can reach production (V-10).
  - Do not decrypt env to verify. Verify with names and targets via `GET /v9/projects/<id>/env`, and by the banner in V8.
- **V4. Connect Git.**
  - Settings → Git → Connect `SnatchIt-app/snatchit`, then Environments → Production → Branch Tracking → branch **`venue/production`**.
  - First create `venue/production` at the approved SHA with its ruleset (V-02; GitHub repo admin).
  - The admin record showed that connecting does not itself deploy.
  - Verify: project GET `link.productionBranch = venue/production`.
  - Rollback: Disconnect Git.
- **V5. First production build** (after G6, so the dark check exercises the real wiring).
  - Push or fast-forward `venue/production` to `<APPROVED_VENUE_SHA_40>` (through the PR merge). Vercel builds only because the pin matches. Expect READY, target production, `meta.githubCommitSha` = the approved SHA.
  - At this point only `snatchit-venue.vercel.app` exists, and it is behind SSO.
  - CLI alternative: `vercel deploy --prod` from a **clean** checkout of the SHA with `VERCEL_ORG_ID=${T} VERCEL_PROJECT_ID=<new id>`, and `venue/.vercelignore` present (f1cb4e16). Git is preferred for provenance.
  - Rollback: Instant Rollback (previous deployment only on Hobby). For the very first deployment, keep SSO "all" and do not attach the domain.
- **V6. Attach `venue.snatchitapp.com`** (Production, no redirect).
  - `vercel api "/v10/projects/<new id>/domains?teamId=${T}" -X POST -f name=venue.snatchitapp.com`
  - The wildcard routes it through Cloudflare at once. With SSO "all" the response is 302 to vercel.com/sso-api, so the host stays owner-only.
  - Wait for the dedicated cert:
    ```bash
    echo | openssl s_client -connect 76.76.21.21:443 -servername venue.snatchitapp.com 2>/dev/null | openssl x509 -noout -subject -issuer -enddate
    ```
    PASS = `CN=venue.snatchitapp.com`, Let's Encrypt, about 90 days. Today's baseline: `CN=*.snatchitapp.com` expired 2026-10-07.
  - **Not verified:** that HTTP-01 issuance is unaffected by SSO "All Deployments". If no cert issues within 60 minutes, check `curl -sS -D - -o /dev/null http://venue.snatchitapp.com/.well-known/acme-challenge/test-token`: a 404 carrying `x-vercel-id` means the path reaches Vercel. If issuance still fails, the fallback is to attach the domain at the V9 go-live under Standard, with the same A2-style gate.
  - Rollback: remove the domain from the project (project-scoped DELETE only; never account-level `vercel domains rm`).
- **V7. Cloudflare DNS.**
  - Read the rank-1 target for the **new** project: `vercel api "/v6/domains/venue.snatchitapp.com/config?teamId=${T}&projectIdOrName=snatchit-venue"` and use `recommendedCNAME[0].value`. The demo project's value `676c401e682632fb.vercel-dns-017.com` does **not** apply to a new project.
  - Record: **CNAME `venue` → `<rank-1 value>`**, fallback `cname.vercel-dns.com`, **DNS only**, TTL Auto. Only after V6's cert PASS.
  - Rollback: delete the record (falls back to the proxied wildcard; still served if the domain stays attached).
- **V8. Dark verification** (owner, signed in to Vercel in the browser; §12 part 1).
  - Sign in at `/login` with your own account.
  - Open `/o/00000000-0000-4000-8000-000000000000/v/00000000-0000-4000-8000-000000000001`. Expect the **denied** entry state ("holds no staff or organization role at this venue"). A platform admin holds no venue or org grant, and the venue row does not exist.
  - That proves sign-in, session refresh, `venue_api` exposure and RLS with zero data written.
  - Banner: `Database (production) — hqycwntpfoztoinemqns.supabase.co · reads as your own sign-in…`. It must not say "Demo — sample data".
  - If G9(b) ran, a granted staff account sees its venue.
- **V9. Go-live (public)** — only when V-08 says so.
  - Deployment Protection → **Standard**. Then `venue.snatchitapp.com` and `snatchit-venue.vercel.app` are public, and deployment URLs stay behind SSO.
  - Immediately set Domains → `snatchit-venue.vercel.app` → Redirect to `venue.snatchitapp.com`, **307**, then **308** after 7 days. Whether Vercel accepts a redirect on a vercel.app domain is not verified; see the admin package §11 for fallbacks.
  - Rollback: Protection back to "All Deployments" (instant, re-gates everything); remove the redirect.

## 5. Cloudflare record — exact
| Field | Value |
|---|---|
| Type | CNAME |
| Name | `venue` |
| Target | rank-1 `recommendedCNAME` for project `snatchit-venue` (read after V6); fallback `cname.vercel-dns.com` |
| Proxy status | **DNS only**, for the same reasons as admin §3: Vercel's guidance, the zone is not strict, HTML stays as rendered, and the venue CSP is `connect-src 'self'` |
| TTL | Auto |
| Zone SSL mode / wildcard / CAA | unchanged (H-03, H-04); explicit `venue` overrides `*` |

## 6. TLS
- The process is the same as admin: Vercel Let's Encrypt over HTTP-01, issued while the name is still proxied through the wildcard, checked against `76.76.21.21` **before** DNS only, then renewed by Vercel.
- Vercel's platform HSTS on custom domains is `max-age=63072000` (observed on `admin.`/apex direct-to-Vercel responses). The venue app sends no HSTS header of its own (§11 item 3).

## 7. Supabase Auth
- **Site URL stays `https://app.snatchitapp.com`.** Add **no** redirect URL for venue: sign-in is `signInWithPassword` in a server action, and sign-out is `signOut()`. `git grep` of `venue/src` on `origin/venue/dashboard-v2` and `venue/production-readiness` finds 0 uses of `redirectTo`, `emailRedirectTo`, `resetPasswordForEmail`, OTP, OAuth or `exchangeCodeForSession`.
- Staff accounts are ordinary Supabase users. A forgotten password can use the existing consumer reset (`https://app.snatchitapp.com` → email → `/auth/confirm?next=%2Freset-password`, which is already allowlisted). If a venue-host reset is ever built, add exactly `https://venue.snatchitapp.com/auth/confirm` (and `?next=**`), never a wildcard.
- MFA is not required by the venue app today (aal is read but unused). This is a product decision (V-07). Default: acceptable for the read-only slice; require aal2 before any write slice ships.
- **Exposed schemas: add `venue_api` (G6).** Do not expose `catalog` or `venue`.

## 8. Cookies
- **Attributes** are the same as admin (`@supabase/ssr` 0.12.6 defaults, no `cookieOptions`): `sb-hqycwntpfoztoinemqns-auth-token`, host-only to `venue.snatchitapp.com`, Path=/, SameSite=Lax, 400 days, not HttpOnly, not Secure.
- **Never set `Domain=.snatchitapp.com`. Never set `serverActions.allowedOrigins`.**
- **Venue-specific points:**
  1. Venue has **no browser Supabase client** (the four `"use client"` files import none). The cookie can therefore be **`HttpOnly` and `Secure`** with `cookieOptions: { httpOnly: true, secure: true }` in `lib/supabase/server.ts` and `lib/supabase/proxy.ts`. This is a recommended code item for D (H-10); the first DB-mode release is the right moment, since nobody holds a venue session yet. Optional `__Host-` name, as for admin.
  2. `POST /logout` is a route handler, so Next's Server Action origin check does not cover it. A same-site sibling page (apex, www, app, wildcard names) could force a logout. Severity is low; the fix is an `Origin` check in the route (D).
  3. `signOut()` defaults to scope **global** in supabase-js 2.115. Signing out of the venue dashboard ends that person's consumer web and native app sessions too. Recommended `signOut({ scope: 'local' })` for venue (D; H-11).

## 9. CORS and origins
- **No browser→Supabase call.** All reads are server-side (`createServerClient`, `cache: 'no-store'`), so there is nothing to configure in Supabase or in any edge-function `ALLOWED_ORIGINS`.
- **`connect-onboarding`** (venue Stripe Connect, **not deployed**) hard-codes `ALLOWED_REDIRECT_HOSTS = {snatchitapp.com, www.snatchitapp.com}`, and its fallback return URLs point at a marketing path that does not exist. Before it is ever deployed for venues:
  - A adds `venue.snatchitapp.com` to that set (code);
  - D builds the return and refresh routes in `venue/`;
  - set `VENUE_CONNECT_RETURN_URL`/`VENUE_CONNECT_REFRESH_URL` to `https://venue.snatchitapp.com/<route>` with no query or fragment (the function refuses state in the URL).

  Not part of this go-live (V-11).

## 10. CSP and headers carry-over
Headers come from `venue/next.config.ts`, the same in both modes:
- `content-security-policy: default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-src 'none'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'`
- `x-content-type-options: nosniff`
- `x-frame-options: DENY`
- `referrer-policy: strict-origin-when-cross-origin`
- `x-robots-tag: noindex, nofollow`

Fonts are self-hosted by `next/font` at build, so `font-src 'self'` holds. Nothing needs to change for the new host. Parity gaps against admin are listed in §11 item 3.

## 11. Code prerequisites (not owner actions; owned by D, F or A; status from a read of local branches, not verified by me)
1. Re-timestamped migration and references (A) — **pending** (G1).
2. Already on local `venue/production-readiness`:
   - kit merged: 789ddd14
   - kit denial marker aligned: 4392cce9
   - `sb_secret_` refusal: 44f6bc54
   - loading states: e841dc26
   - mode-aware titles (no "DEMO" in DB mode): 5fea862a
   - no Create-event link on an empty venue: ade4b303
   - fail-closed entry for non-UUID ids: 200c91f4
   - venue-wide resale policy: 78573d0b
   - `.vercelignore`: f1cb4e16

   The branch is unpushed and has no PR yet; its gates are the sibling task's responsibility.
3. **Not seen on any branch — recommended before public go-live (V9), not needed for dark launch:**
   - a production build guard in `venue/src/lib/env.ts`: when `NEXT_PUBLIC_VERCEL_ENV === "production"`, refuse to build unless `DATA_SOURCE === "database"`, the URL and key are set, and `ENV_LABEL === "production"`. This stops a fixtures or misconfigured build from reaching venue.snatchitapp.com, the way admin's env.ts does;
   - explicit `Strict-Transport-Security: max-age=63072000; includeSubDomains` and `Permissions-Policy` headers (parity with admin);
   - HttpOnly+Secure cookies, a `/logout` Origin check and local sign-out scope (§8).

## 12. Verification checklist
Part 1, dark (SSO "all"):
```bash
H=https://venue.snatchitapp.com
curl -sI "$H/" | grep -iE '^(HTTP|location|server|cf-ray)'          # HTTP/2 302 · location: https://vercel.com/sso-api?url=… · server: Vercel · no cf-ray
echo | openssl s_client -connect venue.snatchitapp.com:443 -servername venue.snatchitapp.com 2>/dev/null | openssl x509 -noout -subject -issuer -enddate   # CN=venue.snatchitapp.com, Let's Encrypt
dig +short CNAME venue.snatchitapp.com @1.1.1.1                     # <rank-1 value>.
```
Then the V8 browser checks (owner): denied entry for a random UUID pair, the Database (production) banner, and the cookie host-only on `venue.snatchitapp.com`.

Part 2, public (after V9):
```bash
curl -sI "$H/" | grep -iE '^(HTTP|location)'         # DB mode: HTTP/2 200 (static "Open your venue's link")
                                                     # TRIPWIRE: 307 → /o/smp_org_wynwood/v/smp_ven_room means a FIXTURES build is live → roll back
curl -sI "$H/login" | grep -iE '^(HTTP|content-security-policy|x-robots-tag|x-frame-options|strict-transport|set-cookie)'
#  200 · CSP with connect-src 'self' · x-robots-tag: noindex, nofollow · x-frame-options: DENY · strict-transport-security: max-age=63072000 · no set-cookie
curl -s "$H/login" | grep -c -e 'Fixture mode needs no sign-in' -e 'Demo — sample data'   # 0
curl -s "$H/" | grep -o '<title>[^<]*</title>'       # <title>Venue dashboard · Snatch It</title> (needs 5fea862a; v2 ee1d90b7 still says "· DEMO")
curl -s "$H/o/smp_org_wynwood/v/smp_ven_room" | grep -c '(sample)'                        # 0 (sample ids are refused in DB mode)
curl -sI 'https://snatchit-venue.vercel.app/login' | grep -iE '^(HTTP|location)'           # 307/308 → https://venue.snatchitapp.com/login
curl -sI https://snatchit-venue-demo.vercel.app/ | head -1                                 # 302 (demo still SSO-only; untouched)
```

## 13. Rollback matrix
| Step | Rollback | Result |
|---|---|---|
| G1/G2 code | revert / close PR | nothing deployed |
| G4 sandbox | remove exposure → kit cleanup → rollback file → ledger row delete → postflight | sandbox back to baseline |
| G5 production apply | `supabase/rollbacks/<A_VERSION>_venue_api_read_views_rollback.sql` (drops 8 views, then the schema, non-CASCADE) plus delete the ledger row (A) | schema as before |
| G6 exposure | remove `venue_api` from exposed schemas | API surface closed; views remain |
| G9 tenant rows | the pack's reverse section, deleting by exact ids | zero-data state restored |
| V1–V4 project | disconnect Git / remove domains; delete the project only if it never deployed (deleting frees the vercel.app name) | no host |
| V5 deploy | Instant Rollback (previous only on Hobby); restore the previous pin `test "$VERCEL_GIT_COMMIT_SHA" != "<previous approved SHA>"`; `vercel promote` to re-enable auto-assign | previous build |
| V6 domain | remove `venue.snatchitapp.com` from the project | 404 DEPLOYMENT_NOT_FOUND (today's state) |
| V7 DNS | delete the `venue` record | proxied wildcard path |
| V9 go-live | Deployment Protection back to "All Deployments"; remove the vercel.app redirect | owner-only again, instantly |
| Emergency | V9 rollback (protection "all") first, the fastest lever; then G6 (remove exposure) | no public surface, no data API |

## 14. Legacy host options: `snatchit-venue-demo.vercel.app`
| Option | Effect | Verdict |
|---|---|---|
| **Keep as the owner-only fixtures demo** (SSO "all", untouched) | sales or design reviews stay possible; can never be mistaken for production | **recommended** |
| Refresh it to v2 fixtures (preview deploy, no `--prod`) | owner sees the current UI | optional (separate decision in the venue hosting map) |
| Make it public (Standard or a shareable link) | public demo with Snatch It branding; no credentials in its build | owner decision (V-09) |
| Redirect it to venue.snatchitapp.com | needs a redirect-only build (a cross-project domain redirect is not offered); loses the demo; sends demo viewers to a login | not recommended |
| Delete the project | frees the `snatchit-venue-demo.vercel.app` name for anyone to claim | not recommended |

## 15. Owner actions (this package)
1. Decisions: V-01 project shape, V-02 production branch and ruleset, V-03 production apply go, V-04 exposure, V-05 sandbox window, V-06 tenant bootstrap with B, V-07 auth policy, V-08 dark or public, V-09 demo fate, V-10 Preview env, V-12 the AUTODEPLOY-VERIFIED-OFF marker, H-08 Pro.
2. Supabase dashboard (MFA): G4 sandbox exposure, G6 production exposure.
3. Vercel: V1–V9 (or re-authenticate the CLI to the team scope so V1 can be scripted).
4. Cloudflare: V7.
5. GitHub (repo admin): create `venue/production` and its ruleset; merge the approved PR.

## 16. Evidence and limits
- **Verified today:**
  - Vercel GETs: projects list, project domains, domain config for `venue.snatchitapp.com` (demo project scope), deployments, team plan, certs
  - `dig`, `curl -sI`, and the `openssl` origin-cert check showing the expired wildcard for `venue.`
  - git reads of `origin/venue/dashboard-v2` and local `venue/production-readiness`
  - `@supabase/ssr` and `auth-js` defaults
- **From records only:**
  - production ledger, schemas, row counts and the PFA-18C restriction
  - sandbox state
  - kit results
  - the API token's 403 on project creation
- **Not verified:**
  - Vercel cert issuance under SSO "All Deployments"
  - a redirect on a vercel.app domain
  - whether `snatchit-venue.vercel.app` is really unclaimed
  - the exact production exposed-schema list today (last record 2026-09-08)
- No write of any kind was made.

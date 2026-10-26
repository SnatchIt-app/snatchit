# Admin console → https://admin.snatchitapp.com — deployment package

**Status: runbook only. Nothing in this file has been executed.** No production change, deploy, DNS edit, Supabase setting or credential entry is authorised by this document; every step marked OWNER needs the owner's explicit go for that step. Prepared 2026-10-21 from read-only evidence (§15). Decision IDs (H-xx, V-xx) refer to `OWNER_DECISIONS.md` in this folder.

## 0. What changes and what does not

| Changes | Does not change |
|---|---|
| One domain added to Vercel project `snatchit-admin` | Code. The live commit stays `07100a356c86240d06c5e50c0833e557dd12b056` |
| One Cloudflare DNS record (`admin`, CNAME, DNS only) | The Ignored Build Step pin (`07100a35…`) |
| One env value (`NEXT_PUBLIC_SITE_URL`, Production) | Supabase Site URL, exposed schemas, DB, edge functions, Stripe |
| `snatchit-admin.vercel.app` becomes a redirect (307 soak, then 308) | Vercel SSO setting (`all_except_custom_domains`) |
| Optional, separate window: one Supabase redirect-allowlist entry removed | The two founders' accounts, roles and TOTP factors |

Expected impact: no downtime on the current host until step A6. Each founder signs in once more on the new host (cookies are per host), with the TOTP factor they already have.

## 1. Current state (verified read-only on 2026-10-21 unless marked "record")

| Item | Value |
|---|---|
| Vercel team | `team_rld7LG9DKzgaph97l4H4jl9d` (`gnvprod-5449s-projects`), plan **hobby**, 1 member (OWNER) |
| Project | `snatchit-admin` `prj_o17cASVVqqyGKPUtiklJRvAMVgNB`; rootDirectory `admin`; Node setting 22.x (the effective build runtime is 24.x because `engines` is `>=22 <25`, per the 2026-09-08 record); region iad1 |
| Git | `SnatchIt-app/snatchit`, production branch `admin/operating-console`; previewDeploymentsDisabled `true`; autoAssignCustomDomains `true` |
| Ignored Build Step | `test "$VERCEL_GIT_COMMIT_SHA" != "07100a356c86240d06c5e50c0833e557dd12b056"` |
| Deployment protection | `ssoProtection.deploymentType = all_except_custom_domains`. `snatchit-admin.vercel.app` is public (200 on /login). Deployment URLs and team aliases answer 302 to vercel.com/sso-api (checked: `snatchit-admin-3by0wuomc-…`, `snatchit-admin-gnvprod-5449s-projects`, `snatchit-admin-git-admin-operatin-389230-…`) |
| Production deployment | `dpl_8q8eeFuyixnfC4xZohU8vCtXHiZt` = `snatchit-admin-3by0wuomc-gnvprod-5449s-projects.vercel.app`, READY, sha 07100a35, created 2026-10-13T21:49Z |
| Previous production | `dpl_8xPaaBYGM7xgfGsS5fgNKib4gNXp` = `snatchit-admin-pfw3bb8or-gnvprod-5449s-projects.vercel.app`, sha f7e7e85f |
| Project domains | only `snatchit-admin.vercel.app` (no redirect) |
| Env names | `NEXT_PUBLIC_ENV_LABEL` [production], `NEXT_PUBLIC_SITE_URL` [production], `NEXT_PUBLIC_SUPABASE_ANON_KEY` [development, production], `NEXT_PUBLIC_SUPABASE_URL` [development, production]. No Preview target. No service-role or secret key in any scope (names only, values not read) |
| DNS for `admin.snatchitapp.com` | Cloudflare (`annabel`/`milan.ns.cloudflare.com`; no DNSSEC). A 104.21.35.180, 172.67.178.48 (Cloudflare proxy). No explicit record is visible from outside: a random label (`zz-wildcard-probe-7f3a`) and a two-level label (`a.b`) resolve the same way, so a **proxied wildcard `*` record** exists |
| HTTPS today | `https://admin.snatchitapp.com/` gives 404 with `x-vercel-error: DEPLOYMENT_NOT_FOUND`, `server: cloudflare`. Edge cert: Cloudflare Universal SSL, CN snatchitapp.com, SAN `*.snatchitapp.com`, Google Trust Services WE1, valid to 2026-12-07 |
| Origin cert Vercel presents for `admin.` today | `CN=*.snatchitapp.com`, Let's Encrypt YR2, **expired 2026-10-07 13:48Z** (verify code 10). It is not in the team's `/v8/certs` list. Vercel serves the same expired cert for `venue.` and `www.` |
| Cloudflare SSL mode | **Inferred "Full" (not strict)**: Cloudflare completes TLS to Vercel for `admin.`/`venue.`/`www.` although Vercel presents the expired cert. A Full (strict) zone would answer 526. "Always Use HTTPS" is off: the `http://` 308 carries Vercel's `Refresh:` header and matches Vercel's direct :80 answer |
| CAA (apex) | issue/issuewild include `letsencrypt.org`, which Vercel uses, plus pki.goog, digicert, sectigo, comodoca, ssl.com |
| Vercel's recommended target for `admin.snatchitapp.com` in this project | `GET /v6/domains/admin.snatchitapp.com/config?projectIdOrName=prj_o17c…`: CNAME rank 1 `31faf7f2ffaf73dc.vercel-dns-017.com.` (A 216.198.79.65, 64.29.17.65), rank 2 `cname.vercel-dns.com.`; A rank 1 `216.198.79.1`, `64.29.17.1`, rank 2 `76.76.21.21`; acceptedChallenges `http-01` |
| Precedent in the same zone | `app.snatchitapp.com` (snatchit-web) is proxied, and Vercel holds a dedicated HTTP-01 cert for it: `cert_X37DfMqubNxAEY8Og5HvjZTE`, CN app.snatchitapp.com, created 2026-10-14T02:19Z, valid to 2027-01-12, autoRenew true. The cert was issued after the wildcard expired. That it was issued through the proxy is inferred from the cert date and the current proxied DNS |
| Registrar | `snatchitapp.com` was bought on Vercel (2026-05-08, renew true, expires 2027-05-08), with custom nameservers pointing at Cloudflare. **DNS edits are made in Cloudflare.** Records added in Vercel DNS have no effect |
| Supabase Auth (record, A, 2026-10-16) | Site URL `https://app.snatchitapp.com`. Allowlist (4 exact entries): `snatchit://`, `https://app.snatchitapp.com/auth/confirm`, `https://app.snatchitapp.com/auth/confirm?next=**`, `https://snatchit-admin.vercel.app/**`. No live read was made here |
| Supabase Data API (record, 2026-09-08) | exposed `public, graphql_public, kernel, ops`. Not touched by this package |

## 2. Target state

| Item | Target |
|---|---|
| Canonical origin | `https://admin.snatchitapp.com` |
| Served deployment | whatever the project's production deployment is, through auto-assign. At cutover that is `dpl_8q8eeFuyixnfC4xZohU8vCtXHiZt` (07100a35). Later releases follow the normal pin process (H-09) |
| DNS | `admin` CNAME `31faf7f2ffaf73dc.vercel-dns-017.com` (re-read rank 1 after step A1), **DNS only**, TTL Auto |
| TLS | Vercel-managed Let's Encrypt cert for `admin.snatchitapp.com`, auto-renewed over HTTP-01 |
| Env (Production) | `NEXT_PUBLIC_SITE_URL=https://admin.snatchitapp.com`, `NEXT_PUBLIC_ENV_LABEL=production`, `NEXT_PUBLIC_SUPABASE_URL=https://hqycwntpfoztoinemqns.supabase.co` (unchanged), `NEXT_PUBLIC_SUPABASE_ANON_KEY` (unchanged; anon or publishable key only, never `service_role` or `sb_secret_…`) |
| Legacy host | `snatchit-admin.vercel.app` redirects to `admin.snatchitapp.com` with path and query kept: 307 for 7 days, then 308 |
| Supabase | Site URL unchanged. Nothing added to the allowlist. `https://snatchit-admin.vercel.app/**` optionally removed later (H-06) |

## 3. Proxy status: DNS only (recommended), with the reasoning

**Recommendation: DNS only (grey cloud).** The owner may choose proxied for Cloudflare Access (H-02).

Reasons for DNS only:
1. **Vercel's own guidance.** Its Cloudflare guide (vercel.com/guides/cloudflare-with-vercel, read 2026-10-21) recommends records "set to DNS only" and connecting directly. It lists the costs of a reverse proxy: reduced security signals, DDoS mitigation on shared proxy IPs, Bot Protection not working, client IP and geo lost, an extra hop, and no support for third-party proxies.
2. **The zone's SSL mode is not strict.** Behind a proxy, Cloudflare would not authenticate Vercel's certificate for this host (§1). Making it strict zone-wide today would break `www.snatchitapp.com`, where Vercel serves the expired wildcard (H-03). DNS only takes Cloudflare's SSL mode out of the admin path.
3. **The HTML stays as the app rendered it.** In a proxied zone, Cloudflare features such as Email Obfuscation, Rocket Loader and Zaraz can rewrite HTML and inject scripts. The console renders user emails and hydrates with React. With DNS only, none of this applies and no per-host rule has to be maintained.
4. **Parity.** The console is public on `snatchit-admin.vercel.app` today, and its own gate is password + TOTP, with aal2 re-checked in Postgres by `ops.assert_reader`. DNS only keeps exactly that posture.

What proxied would buy: a Cloudflare Access gate (for example an email-OTP allowlist of the two founders) in front of the login page, plus edge WAF and rate limits. If the owner picks it, use the proxied variant in §3a.

### 3a. Proxied variant (only if H-02 = proxied)
- DNS: `admin` CNAME `31faf7f2ffaf73dc.vercel-dns-017.com`, **Proxied**.
- Cloudflare → Rules → Configuration Rules, a rule for `http.host eq "admin.snatchitapp.com"`:
  - SSL **Full (strict)**
  - Email Obfuscation **Off**
  - Rocket Loader **Off**
  - Automatic HTTPS Rewrites Off
  - Disable Zaraz
- Cloudflare → Caching → Cache Rules: **Bypass cache** for that host.
- Do **not** change the zone-wide SSL mode (it would 526 `www.`).
- Cloudflare Access: create a self-hosted application for `admin.snatchitapp.com`, plus a **Bypass** application or policy for `admin.snatchitapp.com/.well-known/acme-challenge/*`. Without the bypass, Vercel's HTTP-01 renewal fails, and with strict mode the host answers 526 when the cert expires (about 90 days).
- Verification adds `cf-ray` and `server: cloudflare` to the expected headers. TLS is checked both at the edge and at the origin (`--resolve … 76.76.21.21`).

### 3b. The wildcard record
- An explicit `admin` record overrides the `*` wildcard for that exact name (RFC 4592), so the cutover does not depend on the wildcard and **must not edit it**.
- Deleting the wildcard is a separate decision (H-04), taken after go-live. Before deleting it, confirm in Cloudflare → DNS → Records that `@`, `www`, `app` and every other used name has its **own explicit record**. A name served only by `*` would go dark.
- Rollback: recreate `*` from the zone export taken in A0.

## 4. Steps (OWNER executes; each has verify and rollback)

Run A1 → A2 → A3 in one sitting. A3 must not run until A2 passes: DNS only before the cert exists would send browsers to the expired wildcard, and HSTS forbids a click-through.

### A0. Preflight (read-only; no approval needed)
```bash
T=team_rld7LG9DKzgaph97l4H4jl9d; P=prj_o17cASVVqqyGKPUtiklJRvAMVgNB
vercel api "/v9/projects/${P}/domains?teamId=${T}"                  # expect only snatchit-admin.vercel.app
vercel api "/v9/projects/${P}?teamId=${T}" --raw | python3 -c 'import json,sys;p=json.load(sys.stdin);print(p["commandForIgnoringBuildStep"],p["targets"]["production"]["id"],p["ssoProtection"])'
# expect the 07100a35 pin, dpl_8q8eeFuyixnfC4xZohU8vCtXHiZt, all_except_custom_domains
dig +short A admin.snatchitapp.com @1.1.1.1                          # expect 104.21.35.180 / 172.67.178.48
```
- Cloudflare → DNS → Records → **Import and Export → Export**. Save the BIND file. It is the DNS rollback artefact.
- Supabase → Authentication → URL Configuration: screenshot the Site URL and the Redirect URLs. Expect the §1 values. If they differ, stop and reconcile with A.
- Tell both founders the window. No approval or action has to be drained first: approvals live in `ops.approval` and do not depend on the host.

### A1. Add the domain to the project (OWNER, Vercel)
- Dashboard: snatchit-admin → Settings → **Domains** → Add `admin.snatchitapp.com`. Connect it to **Production**: no redirect, no Git branch, no custom environment.
- API equivalent (owner auth):
  ```bash
  vercel api "/v10/projects/${P}/domains?teamId=${T}" -X POST -f name=admin.snatchitapp.com
  ```
- Do **not** use `vercel domains rm`/`add` at account scope for anything under `snatchitapp.com`, which is a Vercel-registered domain. Use only the project-scoped add and remove.
- Effect: the wildcard already routes `admin.` through Cloudflare to Vercel, so the console starts answering on `https://admin.snatchitapp.com` through Cloudflare at once. It is public, the same posture as the vercel.app host. Founders should not use it until A3.
- Verify:
  ```bash
  vercel api "/v9/projects/${P}/domains/admin.snatchitapp.com?teamId=${T}"   # "verified": true, "redirect": null
  curl -sI https://admin.snatchitapp.com/login | grep -iE '^(HTTP|x-matched-path|x-vercel-error)'   # HTTP/2 200, x-matched-path: /login, no DEPLOYMENT_NOT_FOUND
  ```
- Rollback: Settings → Domains → `admin.snatchitapp.com` → **Remove**, or
  ```bash
  vercel api "/v9/projects/${P}/domains/admin.snatchitapp.com?teamId=${T}" -X DELETE
  ```
  The host returns to 404 DEPLOYMENT_NOT_FOUND.

### A2. Wait for the dedicated certificate (read-only gate)
```bash
echo | openssl s_client -connect 76.76.21.21:443 -servername admin.snatchitapp.com 2>/dev/null \
  | openssl x509 -noout -subject -issuer -enddate -ext subjectAltName
# PASS: subject=CN=admin.snatchitapp.com, issuer O=Let's Encrypt, notAfter about 90 days out, SAN DNS:admin.snatchitapp.com
# FAIL (today's baseline): subject=CN=*.snatchitapp.com, notAfter=Oct  7 13:48:00 2026 GMT
curl -sI --resolve admin.snatchitapp.com:443:76.76.21.21 https://admin.snatchitapp.com/login | head -1   # HTTP/2 200 (no -k: curl validates the cert)
vercel api "/v8/certs?teamId=${T}" --raw | python3 -c 'import json,sys;[print(c["id"],c["cns"],c["autoRenew"]) for c in json.load(sys.stdin)["certs"] if "admin.snatchitapp.com" in c["cns"]]'
```
- Expect issuance within minutes. No timing was measured for app.
- If it has not issued after 60 minutes, check the challenge path:
  ```bash
  curl -sS -D - -o /dev/null http://admin.snatchitapp.com/.well-known/acme-challenge/test-token
  ```
  Expect a 404 that carries an `x-vercel-id` header, which shows the path reaches Vercel. Then retry from the domain card in Vercel. **Do not continue to A3 without PASS.**
- Rollback: none needed (read-only).

### A3. Cloudflare DNS record (OWNER, Cloudflare)
- First re-read the rank-1 target:
  ```bash
  vercel api "/v6/domains/admin.snatchitapp.com/config?teamId=${T}&projectIdOrName=${P}"
  ```
  Use `recommendedCNAME[0].value`, expected `31faf7f2ffaf73dc.vercel-dns-017.com.`.
- Cloudflare → DNS → Records → Add record:
  - Type **CNAME**
  - Name **admin**
  - Target **31faf7f2ffaf73dc.vercel-dns-017.com** (fallback: `cname.vercel-dns.com`)
  - Proxy status **DNS only**
  - TTL **Auto**
- Transition: resolvers that cached the proxied answer (TTL 300) still reach Cloudflare for up to 5 minutes. Founders wait 5 minutes before A5.
- Verify:
  ```bash
  dig +short CNAME admin.snatchitapp.com @1.1.1.1        # 31faf7f2ffaf73dc.vercel-dns-017.com.
  dig +short A admin.snatchitapp.com @1.1.1.1            # 216.198.79.65 / 64.29.17.65 — no 104.21.x / 172.67.x
  curl -sI https://admin.snatchitapp.com/login | grep -iE '^(HTTP|server|cf-ray)'   # HTTP/2 200, server: Vercel, no cf-ray
  vercel api "/v6/domains/admin.snatchitapp.com/config?teamId=${T}&projectIdOrName=${P}"   # expect "misconfigured":false; configuredBy no longer "http"
  ```
- Rollback: delete the `admin` record, or switch it to Proxied. The name falls back to the proxied wildcard, and the console keeps answering through Cloudflare (the domain is still attached). For a full revert, also undo A1.

### A4. Production env (OWNER, Vercel)
- Settings → Environment Variables → `NEXT_PUBLIC_SITE_URL` (Production) → Edit → `https://admin.snatchitapp.com`. Leave the other three unchanged. Do not add a Preview target.
- Why no rebuild is required: at 07100a35, at `admin/dashboard-v2` f1e783e1 and at `admin/console-v2-integration` b82ef0b4, `SITE_URL` is read only by the `env.ts` guard (`git grep SITE_URL` → env.ts:12,33,43,54). No link, redirect, cookie or auth call uses it. The value takes effect at the **next production build**, by default the next approved release (H-07). That build fails, leaving production untouched, if the value is not `https://` on a real host or if `ENV_LABEL` is not `production`.
- Optional (H-07 = rebuild now): Deployments → `dpl_8q8eeFuyixnfC4xZohU8vCtXHiZt` → **Redeploy**, with build cache unticked. This is the same commit, and the pin admits 07100a35. It is a production deploy and needs its own go.
- Verify: `vercel api "/v9/projects/${P}/env?teamId=${T}"` shows the names and targets unchanged (do not decrypt).
- Rollback: set the value back to `https://snatchit-admin.vercel.app`. If the optional redeploy ran, **Instant Rollback** to `dpl_8q8eeFuyixnfC4xZohU8vCtXHiZt`. Hobby allows rollback only to the immediately previous deployment, which is that one. After a rollback, auto-assign is paused until `vercel promote` or **Undo Rollback**.

### A5. Founder acceptance on the new host (OWNER plus the second founder)
For each founder:
1. On `https://snatchit-admin.vercel.app`, **sign out first**. supabase-js 2.115 `signOut()` defaults to scope `global`, so signing out later on the old host would also end the new-host session, the consumer web session and the native app session.
2. Open `https://admin.snatchitapp.com/login`. The title must read "Sign in · Console · production" with the red production badge.
3. Sign in with your password, then TOTP. Your existing factor is reused: MfaFlow lists the verified factor and goes straight to verify. No re-enrolment.
4. Today renders. Open Orders and System (read-only). No mutation is required.
5. In DevTools → Application → Cookies → `https://admin.snatchitapp.com`, check `sb-hqycwntpfoztoinemqns-auth-token` (possibly `.0`/`.1`):
   - Domain `admin.snatchitapp.com` (no leading dot)
   - Path `/`
   - SameSite `Lax`
   It must **not** appear under `app.snatchitapp.com`.
- Pass = both founders. Fail = do not run A6; investigate, or roll back A3/A1.

### A6. Legacy host redirect (OWNER, Vercel)
- Settings → Domains → `snatchit-admin.vercel.app` → **Edit** → Redirect to `admin.snatchitapp.com`, status **307**. After 7 clean days, change it to **308**. Section 11 explains the choice.
- API equivalent:
  ```bash
  vercel api "/v9/projects/${P}/domains/snatchit-admin.vercel.app?teamId=${T}" -X PATCH -f redirect=admin.snatchitapp.com -F redirectStatusCode=307
  ```
- **Not verified:** that Vercel accepts a redirect on the project's own `*.vercel.app` domain. The Domains docs describe the Edit → "Redirect to" control for any project domain, and this exact case was not tested. If Vercel refuses, use fallback (c) in §11 (a host redirect in `admin/src/proxy.ts`, shipped in a release) or keep the parallel host (option a).
- Verify:
  ```bash
  curl -sI 'https://snatchit-admin.vercel.app/login?next=%2Forders' | grep -iE '^(HTTP|location)'
  # HTTP/2 307, location: https://admin.snatchitapp.com/login?next=%2Forders
  ```
  Path and query are kept. Same-team evidence: `snatchti.com/login?next=%2Fx` answers 308 to `https://app.snatchitapp.com/login?next=%2Fx` today.
- Rollback: Edit → Redirect to → **No redirect**. With the API, PATCH `{"redirect":null,"redirectStatusCode":null}` via `--input`; the dashboard is the safe path. After a **308**, browsers cache the redirect, which is why the first week uses 307.

### A7. Supabase allowlist cleanup (OWNER, optional, a separate window; H-06)
- Only after A6 has served 7 days, and outside any phone or email-link test. Follow A's A-3 window rules: EMAIL_LINK_LOCK free, and no auth link younger than 1 hour.
- Read the live list first. If it is not exactly the *before* string, stop and reconcile with A.
  - Before: `snatchit://,https://app.snatchitapp.com/auth/confirm,https://app.snatchitapp.com/auth/confirm?next=**,https://snatchit-admin.vercel.app/**`
  - After: `snatchit://,https://app.snatchitapp.com/auth/confirm,https://app.snatchitapp.com/auth/confirm?next=**`
- How: Dashboard → Authentication → URL Configuration → remove the entry, or Management API `PATCH /v1/projects/hqycwntpfoztoinemqns/config/auth` `{"uri_allow_list":"<after>"}`. **Do not change the Site URL.**
- Verify by a Management API GET only. Never probe `/verify` (rate_limit_verify is 30 per IP).
- Rollback: PATCH the exact *before* string.

### A8. Records (D or A, docs only)
- Add a dated addendum on the admin docs branch with the domain, DNS, cert id and the A5 results. A push to `admin/operating-console` creates a Git deployment that the pin cancels, which is harmless (2026-09-08 record).
- Update REDIRECT_INVENTORY row HOST-02, outside A's markers.

## 5. Cloudflare record — exact

| Field | Value |
|---|---|
| Type | CNAME |
| Name | `admin` (FQDN admin.snatchitapp.com) |
| Target | `31faf7f2ffaf73dc.vercel-dns-017.com` (Vercel rank 1 for this project as of 2026-10-21; re-read after A1). Fallback `cname.vercel-dns.com` |
| Proxy status | DNS only (default, H-02) |
| TTL | Auto |
| Zone SSL/TLS mode | Leave unchanged (inferred Full). Not in the path when DNS only. If proxied, use a hostname Configuration Rule with Full (strict) (§3a) |
| Wildcard `*` | Leave untouched during cutover (§3b; H-04) |
| CAA | No change; `letsencrypt.org` is already allowed |

## 6. TLS issuance and verification
- **Issuer:** Vercel, Let's Encrypt, HTTP-01 (`acceptedChallenges: ["http-01"]`). While the wildcard proxies the name, the challenge reaches Vercel through Cloudflare on port 80. Cloudflare uses the visitor's scheme in Full mode, and Always Use HTTPS is off. The app.snatchitapp.com cert (2026-10-14, proxied host) is the precedent; that it was issued through the proxy is inferred.
- **Order:** issue (A1/A2) **before** going DNS only (A3). Vercel's pre-generation docs give the same check: `curl https://<host> --resolve <host>:443:76.76.21.21 -I`.
- **Renewal:** automatic, about 30 days before expiry, over HTTP-01 straight to Vercel once DNS only. Re-check monthly with the A2 command, or watch `/v8/certs` for `autoRenew: true`.
- **Edge cert:** none when DNS only (Vercel's is the only cert). If proxied, Cloudflare Universal SSL (GTS WE1, `*.snatchitapp.com`, renewed by Cloudflare).
- **HSTS:** the app sends `max-age=63072000; includeSubDomains`, which covers admin.snatchitapp.com and its subdomains only, not siblings. No preload.

## 7. Supabase Auth
- **Site URL stays `https://app.snatchitapp.com`** (AUTH-01). Never change it for admin. It is the fallback for consumer email links.
- **The admin needs no redirect URL.** Sign-in is `signInWithPassword` in a server action plus browser `mfa.enroll`/`challenge`/`verify`, and none of these takes a redirect. `git grep -E "redirectTo|emailRedirectTo|resetPasswordForEmail|signInWithOtp|signInWithOAuth|exchangeCodeForSession|verifyOtp|signUp\("` over `admin/src` gives **0 matches** at 07100a35, `origin/admin/dashboard-v2`, and `admin/console-v2-integration` b82ef0b4.
- **Do not add `https://admin.snatchitapp.com/**`.** An unused wildcard entry only widens where Supabase may send auth links. GoTrue's implicit rule accepts the Site URL host only, so admin.snatchitapp.com is not implicitly allowed, which is the intended state.
- **Remove `https://snatchit-admin.vercel.app/**`** after A6 (A7, optional). Nothing uses it.
- **If a password-reset or email flow is ever added to admin:** add exactly `https://admin.snatchitapp.com/auth/confirm` (plus `?next=**` if needed), never a host wildcard, in the same release.
- Data API exposed schemas, MFA settings and JWT expiry: no change.

## 8. Cookies
- **Name:** `sb-hqycwntpfoztoinemqns-auth-token` (chunked `.0`/`.1` when large). The same name is used by web, admin and venue, because all three use one Supabase project.
- **Attributes** (from `@supabase/ssr` 0.12.6 `DEFAULT_COOKIE_OPTIONS`; admin sets no `cookieOptions`):
  - `Path=/`, `SameSite=Lax`, `Max-Age=34560000` (400 days)
  - **no Domain**, so the cookie is host-only to admin.snatchitapp.com
  - **not HttpOnly**: the /mfa browser client reads it
  - **not Secure**: neither the library nor the app sets it; HSTS covers transport after the first visit
- **Rules:**
  1. **Never set `Domain=.snatchitapp.com`** (`cookieOptions.domain`) in admin, venue or web. With one shared cookie name, it would send an aal2 founder session to app.snatchitapp.com and the marketing site, and present consumer sessions to admin.
  2. **Never set `serverActions.allowedOrigins`.** Next.js 16.3.3 compares the `Origin` host with the `Host`/`x-forwarded-host` and aborts mismatches, including `Origin: null` (`action-handler.js:427-460`). This is the CSRF wall between sibling subdomains.
  3. `git grep` finds no `cookieOptions`, `domain:` or `.snatchitapp.com` cookie setting in `web/src` (05ef5105), `admin/src` or `venue/src`.
- **New same-site exposure (why this matters now):**
  - `vercel.app` is on the Public Suffix List, so `snatchit-admin.vercel.app` is its own site. `admin.snatchitapp.com` is the **same site** as the apex, `www`, `app` and every wildcard-routed name, so SameSite=Lax no longer separates them.
  - What still holds:
    - the Server Action origin check (rule 2)
    - admin has no route handlers (no `app/api`)
    - every ops RPC re-checks role and aal2 in Postgres
  - Residual (low): a compromised sibling subdomain could "toss" a `Domain=.snatchitapp.com` cookie with the same name. At worst that is session fixation into a non-operator account, which the DB refuses.
- **Optional hardening (code, D; H-10):** `cookieOptions: { secure: true }` and a `__Host-`-prefixed cookie name in **both** the server and browser clients. The prefix forces Secure, Path=/ and no Domain, which defeats tossing. The cutover is the cheapest moment, because everyone signs in again anyway. Not required for go-live.
- **Session continuity:** none across hosts, by design. TOTP factors are per user and unaffected.

## 9. CORS, origins and server-side calls
| Call | Runs in | Target | CORS / allowlist needed |
|---|---|---|---|
| Pages, RSC, Server Actions (all ops reads and writes via `schema('ops').rpc`) | browser → admin origin → server | `https://hqycwntpfoztoinemqns.supabase.co/rest/v1` from the server | none (same origin; Supabase is called server-side) |
| `/mfa` TOTP: `mfa.listFactors`, `unenroll`, `enroll`, `challenge`, `verify` | **browser** | `https://hqycwntpfoztoinemqns.supabase.co/auth/v1` | none to configure; Supabase's gateway answers CORS. CSP `connect-src` already lists the host |
| Evidence: `storage.createSignedUrl` | server action | supabase storage | none. The signed URL is opened by navigation or `<img>`, which the CSP `img-src` allows |
| Resume refund: `POST /functions/v1/ops-refund-execute` | **server action** (lib/edge-functions.ts) | edge function | **none.** The function emits CORS headers only when `OPS_CONSOLE_ORIGIN` equals the request Origin. Keep it **unset**: it is not deployed in production, and refunds are disabled. If a browser caller is ever added, set it to exactly `https://admin.snatchitapp.com` |
| Consumer edge functions (`ALLOWED_ORIGINS` = snatchitapp.com, www) | — | — | no change; admin does not call them from a browser |

## 10. CSP and headers carry-over
Headers come from `admin/next.config.ts`, so they apply on every host with no change. Expected on `https://admin.snatchitapp.com/login`, the same as `snatchit-admin.vercel.app/login` today:
- `content-security-policy`:
  ```
  default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https://hqycwntpfoztoinemqns.supabase.co; font-src 'self'; connect-src 'self' https://hqycwntpfoztoinemqns.supabase.co wss://hqycwntpfoztoinemqns.supabase.co; frame-src 'none'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'; upgrade-insecure-requests
  ```
- `strict-transport-security: max-age=63072000; includeSubDomains`
- `x-frame-options: DENY`
- `x-content-type-options: nosniff`
- `referrer-policy: strict-origin-when-cross-origin`
- `x-robots-tag: noindex, nofollow`
- `permissions-policy: camera=(), microphone=(), geolocation=(), payment=(), usb=()`
- `cache-control: private, no-cache, no-store, max-age=0, must-revalidate` (dynamic)
- no `x-powered-by`

`'self'` now means admin.snatchitapp.com, and `form-action 'self'` keeps forms on the console. The new host needs no CSP edit.

## 11. Legacy redirect: `snatchit-admin.vercel.app`
| Option | Effect | Verdict |
|---|---|---|
| (a) Keep serving in parallel | two public login pages; Supabase allowlist entry kept | soak only |
| **(b) Vercel domain redirect, 307 for 7 days then 308** | one public host; path and query kept; no code change | **recommended** |
| (c) Host redirect in `admin/src/proxy.ts` (code release) | same as (b) but needs a pinned release | fallback if (b) is refused for vercel.app |
| (d) Remove the vercel.app domain | 404 for old bookmarks | not recommended |

Route-by-route analysis (the new host has its own cookies; the old host only redirects):
| Request on the old host | After the redirect | Outcome |
|---|---|---|
| `GET /login?next=%2Forders%2F<id>` | `GET https://admin.snatchitapp.com/login?next=%2Forders%2F<id>` | sign-in on the new host; `safeInternalPath` keeps `next` same-origin |
| `GET /`, `/orders/<id>`, `/system`… | same path on the new host | no new-host session → 307 to `/login?next=<path+query>` (proxy-logic.ts:42-45) |
| `GET /mfa`, `/denied` | same path | no session → `/login`; with an aal1 session → shown as usual |
| **POST** sign-in from a stale tab | 307/308 keep method and body; the browser sends `Origin: null` after a cross-origin redirect | Next aborts it ("Invalid Server Actions request"): nothing is processed, and the founder re-enters the password on the new host |
| **POST** console mutation (ConfirmForm) from a stale tab | same | aborted by the origin check (and, without a new-host session, by the proxy first). **No `ops.action` row is created.** The idempotency key is unused, so no duplicate is possible. Reload on the new host and resubmit |
| `POST` sign-out from a stale tab | aborted | sign out on the old host **before** A6 (A5 step 1) |
| RSC prefetch from a stale tab | the cross-origin fetch fails | the Next router falls back to a full navigation, which redirects |

Status code choice:
- 307 and 308 both preserve method and body. 301 and 302 would turn stale POSTs into GETs.
- 307 during the soak keeps a rollback possible, because browsers do not cache it. 308 after the soak gives the permanent signal.
- Deployment URLs (`snatchit-admin-*-gnvprod-5449s-projects.vercel.app`) stay behind Vercel SSO and need nothing.

## 12. Verification checklist (copy-paste; expected values)
```bash
H=https://admin.snatchitapp.com
curl -sI "$H/login"            | grep -iE '^(HTTP|server|cf-ray|x-robots-tag|x-frame-options|strict-transport|set-cookie)'
#  HTTP/2 200 · server: Vercel · (no cf-ray) · x-robots-tag: noindex, nofollow · x-frame-options: DENY
#  · strict-transport-security: max-age=63072000; includeSubDomains · (no set-cookie)
curl -sI "$H/orders?x=1"       | grep -iE '^(HTTP|location)'      # 307 · location: /login?next=%2Forders%3Fx%3D1
for p in / /system /money /users /cases /mfa /denied; do printf '%s ' "$p"; curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' "$H$p"; done
#  each 307 → $H/login?next=… (for /mfa and /denied: → /login?next=%2Fmfa / %2Fdenied)
curl -sI http://admin.snatchitapp.com/login | grep -iE '^(HTTP|location)'   # 308 · location: https://admin.snatchitapp.com/login
curl -s "$H/login" | grep -o '<title>[^<]*</title>'                         # <title>Sign in · Console · production</title>
curl -sI "$H/api/health" | head -1                                           # 307 to /login (there are no API routes)
echo | openssl s_client -connect admin.snatchitapp.com:443 -servername admin.snatchitapp.com 2>/dev/null | openssl x509 -noout -subject -issuer -enddate
#  subject=CN=admin.snatchitapp.com · issuer Let's Encrypt · notAfter ≈ +90 days
dig +short CNAME admin.snatchitapp.com @1.1.1.1                              # 31faf7f2ffaf73dc.vercel-dns-017.com.
curl -sI 'https://snatchit-admin.vercel.app/login?next=%2Forders' | grep -iE '^(HTTP|location)'   # 307 (later 308) · https://admin.snatchitapp.com/login?next=%2Forders
curl -sI https://snatchit-admin-3by0wuomc-gnvprod-5449s-projects.vercel.app/login | head -1   # 302 (Vercel SSO), unchanged
curl -sI https://zz-wildcard-probe-7f3a.snatchitapp.com/ | grep -i x-vercel-error             # DEPLOYMENT_NOT_FOUND (wildcard untouched)
```
Plus A5, signed in (founders): Today renders, the production badge shows, and the cookie is host-only. A2's origin-cert check and A3's `misconfigured:false` also apply.

## 13. Rollback matrix
| Step | Rollback | Result | Time |
|---|---|---|---|
| A1 domain | Remove `admin.snatchitapp.com` from the project (dashboard, or project-scoped DELETE) | host back to 404 DEPLOYMENT_NOT_FOUND; vercel.app unaffected | < 1 min |
| A3 DNS | Delete the `admin` record (or switch it to Proxied); restore from the A0 export if anything else changed | name falls back to the proxied wildcard; the console still serves through Cloudflare | ≤ 5 min (TTL) |
| A4 env | Set `NEXT_PUBLIC_SITE_URL` back to `https://snatchit-admin.vercel.app`; if redeployed, Instant Rollback to `dpl_8q8eeFuyixnfC4xZohU8vCtXHiZt`, then `vercel promote` it to re-enable auto-assign | previous build live | < 1 min |
| A6 redirect | Domains → `snatchit-admin.vercel.app` → No redirect | the old host serves the console again (users who received a cached 308 keep landing on the new host, which still works) | < 1 min |
| A7 allowlist | PATCH the exact *before* string; GET read-back | previous allowlist | < 1 min |
| Any release after cutover | Instant Rollback (previous deployment on Hobby); restore the pin `test "$VERCEL_GIT_COMMIT_SHA" != "07100a356c86240d06c5e50c0833e557dd12b056"` if a release moved it | previous deployment | < 1 min |
| Emergency, all of it | A6, then A3, then A1 rollbacks in that order; containment levers unchanged (`actions_enabled=false`, RUNBOOK §5) | back to 2026-10-21 state | ~10 min |

Abort criteria:
- A2 cert not issued.
- Any 5xx or 526 on the new host.
- A founder cannot reach Today at aal2.
- The cookie shows a `.snatchitapp.com` domain.
- The CSP differs from §10.

## 14. Owner actions (this package)
1. Decide H-01 (go for A1–A6 and a window), H-02 (DNS only vs proxied), H-05 (redirect policy), H-07 (rebuild now or at the next release), H-08 (Hobby vs Pro).
2. Cloudflare: A0 export, A3 record. Later, separately: H-03 and H-04.
3. Vercel: A1, A4 (and the optional redeploy), A6, and the 308 switch after 7 days.
4. Founders: A5.
5. Supabase: A0 screenshot; A7 later (optional, H-06).
6. Later releases: the pin moves per release. That is H-09, not part of this cutover.

## 15. Evidence and limits
- **Verified today (read-only):**
  - `dig @1.1.1.1`
  - `curl -sI` and `openssl s_client`, including `--resolve` / `-connect 76.76.21.21` direct-to-Vercel handshakes
  - `vercel api` GETs: `/v9/projects`, `/v9/projects/<id>/domains`, `/v6/domains/<d>/config`, `/v5/domains/snatchitapp.com`, `/v8/certs`, `/v13/deployments/<id>`, `/v2/teams/<id>`
  - `git show`/`grep` of admin code at 07100a35 and v2
  - Next 16.3.3 `action-handler.js`
  - `@supabase/ssr` 0.12.6 constants
  - `@supabase/auth-js` 2.115.0 `signOut` default
  - raw outputs in `evidence/`
- **From records, not re-read:** the Supabase Site URL and allowlist (REDIRECT_INVENTORY final state, 2026-10-16), exposed schemas (2026-09-08), founders' G1 results.
- **Inferred:**
  - Cloudflare zone SSL mode "Full"
  - the wildcard's origin (Vercel's default DNS for purchased domains, carried into Cloudflare at the NS move; the expired wildcard cert was issued on 2026-07-09 while Vercel DNS was authoritative)
  - Vercel accepting a redirect on a vercel.app domain (not tested)
  - cert issuance timing
- No Supabase, Cloudflare or Vercel write was made, and no env value was decrypted.

# Admin console and venue dashboard: readiness map (2026-10-21)

This map comes from read-only evidence: git refs, Vercel API GETs, public `curl` and `dig`, and the written records. It made no hosted database read and no production change. Hosting steps are in `ADMIN_HOSTING_admin.snatchitapp.com.md` and `VENUE_HOSTING_venue.snatchitapp.com.md`; owner decisions are in `OWNER_DECISIONS.md`. The final production domains are **https://admin.snatchitapp.com** and **https://venue.snatchitapp.com**.

## 1. Side by side

| Item | Admin console (`admin/`) | Venue dashboard (`venue/`) |
|---|---|---|
| Live URL today | https://snatchit-admin.vercel.app (public login page; every other route redirects to `/login`) | https://snatchit-venue-demo.vercel.app (Vercel SSO "all": owner only) |
| Target URL | https://admin.snatchitapp.com (today: Cloudflare wildcard → Vercel 404 `DEPLOYMENT_NOT_FOUND`) | https://venue.snatchitapp.com (same today) |
| Vercel project | `snatchit-admin`, git-linked, root `admin`, production branch `admin/operating-console`, Ignored Build Step pinned to `07100a35`, previews disabled | `snatchit-venue-demo`, not git-linked, CLI-deployed, framework from `venue/vercel.json`. No production venue project exists |
| Deployed commit | `07100a35` (PR #103 merge), `dpl_8q8eeFuyixnfC4xZohU8vCtXHiZt`, 2026-10-13. Rollback target `dpl_8xPaaBYGM7xgfGsS5fgNKib4gNXp` (`f7e7e85f`) | `512e01e3` (`venue/demo-integration`), `dpl_4Rht1KT12uiuLqTEaSvdYE79eVhe`, 2026-10-06. 25 commits behind v2 |
| Data mode | Database only: every read is an `ops.*` RPC under the operator's own JWT. No fixture mode | Fixtures (sample data, labelled) on the demo. Database mode needs the `venue_api` views and exposure, and is read-only |
| Data sources | `schema('ops').rpc(...)`: 26 read RPCs, plus `execute_action` and `approve_action`. Storage signed URLs come only via `ops.evidence_access`. The edge function `ops-refund-execute` is not deployed | 8 `security_invoker` views in `venue_api` (venues, events, event_sessions, resale_policies, ticket_types, inventory_batches, my_staff_roles, my_org_roles). No RPCs, no writes |
| Roles | `platform_admin` only in practice (2 founders, `public.admin_users`). Risk and support roles cannot be granted (dual control unavailable). Every RPC re-checks role and aal2 in Postgres | Staff and org roles from `venue.staff_role` and `kernel.org_member` through `my_staff_roles` / `my_org_roles`. Production has 0 orgs, venues and staff |
| Auth | Password, then TOTP (aal2) enforced by the proxy and in Postgres. No email-link flows | Password only. No MFA and no reset on the venue host |
| Env (names) | `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `NEXT_PUBLIC_SITE_URL`, `NEXT_PUBLIC_ENV_LABEL`. No Preview env | `NEXT_PUBLIC_VENUE_DATA_SOURCE` (fixtures/database), plus the same Supabase URL, anon key and label for database mode |
| Schemas and migrations | Production has 115–120 (ops), 143–146, 150–152, 154–156. 121, 125 and 126 are unapplied (records) | 076–120 are in production. Missing: the `venue_api` views (registry **159**, `20261021120000`, pgTAP **226**; applied nowhere) and `venue_api` exposure |
| Missing server logic | A's 157 (duplicate unsettled refund/payout guard) and 158 (relist expected check) are in progress. Alert delivery is unscheduled with no channel. No payout-hold action. `setting_set` is single-founder | Not wired in database mode: Today, Guest list, Check-in, Create event, writes, box office lookup, tenant onboarding. All are owner-deferred (`OWNER_DECISIONS.md` §E) |
| Money safety | Refunds are disabled end to end: `refund_execute_enabled=false` and the executor is undeployed. A duplicate unsettled action is possible server-side until 157 (the UI guard on the v2 branch fails closed). Refund-after-payout is not blocked server-side. The manual refund SOP was stale; a replacement draft is pending A | No money path |
| Tests (CI) | Live: 17 files / 119 tests. #121: 38 files / 353 tests. CI job "Admin console (Next.js)" is required | v2: 11 files / 157 tests. #122: 18 files / 294 tests. #123: pgTAP 226 72/72 |
| Acceptance proof | G1, G3, G4, G5 (operator), G6, G7 and G8 PASS (2026-09-08 record). G2, G5-unrelated and the signed-in suspension render are open | Kit 138/138 on a LOCAL replay only. The sandbox window (V1–V10) never ran past the read-only preflight |

## 2. Branches and draft PRs (this pass)

| PR | Branch → base | What |
|---|---|---|
| #116 | `admin/console-next-16.3.8` → `admin/operating-console` | Next.js 16.3.3 → 16.3.8 on the live console (7 advisories, 1 critical) |
| #121 | `admin/console-v2-integration` → `admin/operating-console` | Dashboard v2 (admin/ only) on the live console with RC5 suspension, the #89 refund-classification and alert-acknowledge port, the money-form guard via `ops.list_actions` (fails closed), env/cookie/MFA hardening, and Next 16.3.8 |
| #122 | `venue/production-readiness` → `venue/dashboard-v2` | Acceptance kit merged and re-pinned to 159, secret-key refusal, loading state, mode-aware copy, fail-closed entry, resale scope, Secure/HttpOnly own-name cookies, HSTS, `.vercelignore`, Next 16.3.8; **DC-3**: a production deployment refuses an unset or unknown data source |
| #123 | `venue/api-read-views-provisional` → `fix/154-listing-visibility-20261015` | `venue_api` views as registry 159 / pgTAP 226 (A allocated them in PR #115), four-file rule, local replay evidence. Comes to A before it leaves draft |
| #124 | `admin/manual-refund-sop` → `admin/operating-console` | A current manual refund procedure (DRAFT until A reviews the money wording) |
| #134 | `admin/console-relist-expected` → `admin/operating-console` | The live console sends the listing version for relist (A's 158 contract). Must deploy **before** 158 |
| #158 | `admin/console-v2-visual` → `admin/console-v2-integration` (stacked on #121) | V-1 visual hierarchy: labels and states on every figure, real-read comparisons and breakdowns, sortable tables, two workflow diagrams, reduced motion. The DC-2 test-row notice hook is in place and empty until A's 180 |
| #120 | `docs/dashboards-hosting-package` → `admin/operating-console` | This map, both hosting runbooks and the owner decision list |

Never merge a venue branch, or the old admin v2 branch, wholesale: they inherit non-dashboard `supabase/`, `app/` and `src/` content. Each ships its own app folder only, and never through `main`.

## 3. Practical order to hosted production readiness

**Admin**
1. Owner merges #116, moves the pin, redeploys. Operators reload their tabs.
2. Cut over the domain on the current commit, `ADMIN_HOSTING` A0–A6: domain add, wait for the cert, DNS-only CNAME, env, founder check, legacy redirect.
3. Deploy #134 (or #121, if v2 ships first), then the owner authorises 157 (#118) and then 158 (#125).
4. Owner decides O-1 (v2 replaces the live UI). Merge the v2 integration PR, pin, deploy, founder signed-in check (also closes the suspension-render gap).
5. Alert delivery (O-2), then the detector (O-3), then money-switch governance (O-4).

**Venue**
1. A reviews and merges the 159 migration branch in registry order: after 157/158, before 160–172.
2. Owner names a sandbox window. The kit runs V0–V10 with A witnessing, and the owner exposes `venue_api` on the sandbox.
3. Owner authorises the production apply of 159 (single file plus ledger row), then exposes `venue_api` in production.
4. Create the production venue project: git-linked, root `venue`, protected `venue/production` branch with a pin, Production env in database mode. Attach venue.snatchitapp.com, dark at first (SSO).
5. Tenant bootstrap stays blocked by B's PFA-18C zero-data restriction until the owner and B lift it narrowly. Until then the hosted dashboard has no data to show.

## 4. The one production venue (created 2026-10-22)
A executed the owner-authorised minimum onboarding on 2026-10-22 03:51:44Z; A's read-back verified it. Draft, not approved, not exposed.

| Item | Value |
|---|---|
| Organization | `24232848-0bcf-4fa9-8040-c8bd2dc38ed2` — legal name JDT LLC, display name Snatch It, status approved, no Connect ref |
| Membership | the owner's account as `org_owner` (the only member) |
| Venue | `5e8db24b-a0ac-440a-9f00-fa15ee3bbb75` — "Snatch It Venue", neighborhood wynwood (owner-confirmed), address and capacity NULL, **approval_status draft** |
| Everything else | 0 staff roles, 0 events, 0 inventory, 0 door-plane rows. No issuance, scanning or payments. |

**Dashboard URL, once hosted:** `https://venue.snatchitapp.com/o/24232848-0bcf-4fa9-8040-c8bd2dc38ed2/v/5e8db24b-a0ac-440a-9f00-fa15ee3bbb75`. Until then the same path on an SSO-protected preview in database mode.

**What the owner will see there, and when:** nothing readable until **159 (#123) and 176 (#143) are applied and `venue_api` is exposed** (the order in `VENUE_HOSTING_venue.snatchitapp.com.md`). After that: the venue name, "No events yet" with no create link, and resale shown as "not readable yet" while the venue is draft. The venue stays **draft, not approved**: `approve_venue` is a separate owner step tied to exposure and sales, and the public arm (`catalog_venue_sel_anon`) exposes only approved venues, so draft is the smaller exposure.

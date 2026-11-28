# Dashboard v2 — handoff for release review (Claude F)

Venue dashboard and admin operating console in the owner-approved concept
(visual direction locked 2026-10-09), plus the functional-readiness pass of
2026-10-12. **Not deployed, not merged to `main`, not in the current app
release** (A's `CANDIDATE_MANIFEST.md`). Both are local previews with exact
commits. Venue v2 still carries the unapplied `20260910120000_venue_api_read_views`
migration, so it cannot go live before an owner-approved apply; admin v2 would
replace the current console UI, which is a separate owner decision.

## Branch tips (verified against `origin`, 2026-10-12)

| App | Branch | Code tip | Commits in this pass |
|---|---|---|---|
| Admin | `admin/dashboard-v2` | `fae12913d31bf9ef555c8d627359a45bf2547d35` | `e1c04754` harness TOTP/QR · `c06fad75` readiness fixes · `fae12913` reason kept in server log |
| Venue | `venue/dashboard-v2` | `bb94b1f28ea07dbd4b17b64a5b3031753fb90f21` | `100374ac` readiness fixes · `bb94b1f2` two regressions found by the final sweep |

This document is committed on top of each code tip (docs only). Checkouts:
`/Volumes/DEV-SSD/01_SNATCH_IT/repos/snatchit-admin-v2` and `…/snatchit-venue-v2`.

## Integration branch (`admin/console-v2-integration`, 2026-10-21)

Admin v2 rebuilt on the live console, admin/ only. **Pushed as draft PR #121;
CI runs on the PR. Not merged, not deployed.** `origin/admin/console-v2-integration`
@ `5d1a059c` carries 32 commits over the base; this tree adds `d6ff9989`
(.vercelignore) and the reviewer-E commits below, local until the owner's
process pushes them.

- **Base:** `origin/admin/operating-console` @ `07100a35` (production, with #103).
  `git diff --name-only 07100a35 HEAD -- . ':!admin'` is empty, so none of v2's
  330 non-admin paths (stale edge functions, migrations, app/) come along.
- **Merged:** `d916a69e` is v2's admin/ tree from `f1e783e1` (code `fae12913`),
  byte for byte. `b82ef0b4` puts RC5 account suspension (#103) back on top, and
  the "investigate" warning counts `listing_blocked` rows only.
- **Fixes.** One commit each, with a test that failed on the unfixed code and
  planted mutants that the tests had to catch:

| | Commit | Fix | RED → GREEN | Mutants caught |
|---|---|---|---|---|
| F1 | `2e103504` | The money-form guard also reads `ops.list_actions` for the one subject in the unsettled states. `order_detail` stops at 50 rows; the guard no longer does. A failed or unrecognised read hides the form ("Couldn't check for an earlier request"). | page test 7 failed / 3 passed → 10/10, plus 10 unit tests | 10/10 |
| F2 | `24180dc6` | "Sample data" notice only for an explicitly set label of exactly `local`, `harness` or `rehearsal`, and never on Vercel production or preview. The harness now sets `NEXT_PUBLIC_ENV_LABEL=harness`. Tightened by F2b below. | 4 failed / 1 passed → 5/5 | 6/6 |
| F3 | `87509792` | `env.ts` refuses, at startup in every environment, an `sb_secret_` key or a JWT with any role other than anon (service_role included) in `NEXT_PUBLIC_SUPABASE_ANON_KEY`. The key is never printed. | 5 failed / 1 passed → 6/6 | 8/8 |
| F4 | `e8517067` | `/mfa` calls `ops.whoami()` before the enrol flow. whoami has no aal check (115:1134-1152), so it answers at aal1. A non-operator goes to `/denied`; operators are unchanged. | 5 failed / 2 passed → 7/7 | 7/7 |
| F5 | `36155fe0` | Session cookies are host-only by construction: `hostOnlyCookie()` drops any Domain. On a Vercel production deploy, `NEXT_PUBLIC_SITE_URL` must be `https://admin.snatchitapp.com`, or `https://snatchit-admin.vercel.app` during the transition. The CSP and headers are pinned as host-agnostic. | 6 failed / 4 passed → 10/10 | 13/13 |
| F6 | `cd54a3dc` | next 16.3.3 → 16.3.8, exact. The lockfile change set is identical to `bdd1dfb5`. npm audit: 1 critical + 2 high → 2 high (sharp, source-map-js; transitive). | 1 failed / 2 passed → 3/3 | 5/5 |
| S1 | `d4b10749` | Order page Payment panel: a "Stripe mode" row from `payment.stripe_livemode` (045). `order_detail` already returns it (`ops.payment_json` = `to_jsonb(p)` minus the client secret, 116:172-176; neither is redefined later on `release/production-gate-20260918`), so no SQL change. Literal `true` → Live, `false` → Test; a recorded null → Unclassified plus a warning that automated refunds and payouts fail closed on it (`row_mode_unclassified`, `PAYMENT_NOT_LIVE`), so a manual refund stops and goes to the owner. A missing key or non-boolean reads "Unclassified (not provided by the server)" / "(unrecognised value)" and claims nothing about automation. Header test-mode badge kept. Added after the wave-4 gates: only the touched tests (8 files / 84) and eslint on the changed files ran. | 12 failed / 0 passed → 12/12 | 11/11 |
| R1 | `9c79312d` | Relist states the listing version (migration 158, PR #125 head `f5abd471`; rollout: this console first, then 157, then 158 — before 158 the server stores relist `expected` and never reads it). `p_expected` = status, auction_status, ends_at, ended_at, updated_at copied raw from `ops.listing_detail` (`src/lib/relist.ts`, never through Date); the form only for active + cancelled with a string updated_at; `new_ends_at` posts with `Z` (new `param.<key>:utc`). Answers: succeeded shows `result.result` + `result.before`; stale_state 158's copy, Reload now and `result.current`; precondition ('Listing not found.' included) and replay unchanged; the P0001 "requires expected.updated_at" raise reads "console out of date" after denied / step-up / paused. The Relist panel is one Panel with one `OutcomeHost` (key `listing_relist`) in every state, so the answer survives the action's own refresh, which leaves the listing no longer relistable (the gap found in the live port). PG 17 local check (dropped): the console's args built from `to_jsonb` rows pass 158's gate and compare equal; a Date round trip compares stale. Full gates at `9c79312d`: typecheck 0, lint 0, vitest 42 files / 427, `next build` 0. | 28 failed / 25 passed, and relist-contract fails to load → 62/62 | 23/23 |
| RR1 | `c631ef4b` | The report_resolve answer survives the action's own refresh (found by two adversarial checkers). /marketplace/[id] lists only open reports under Resolve reports (the panel goes with the last one) and `/reports?status=pending` (the Today tile) only pending ones, so Actioned / Dismiss, and Mark reviewing on that filter, dropped the row and the OutcomeHost holding the answer in the same commit. Now one `ListOutcomeHost` (key `report_resolve`) sits above each list in every state; `OutcomeSlot` shows the answer in the report's own block or row while it is listed, otherwise the host shows it (below the panel; above the table on /reports) naming the report (reason · status as read in the refresh, or its short id) as no longer listed here. `submitActionForm` answers carry `subject {kind, id}` exactly as posted. Fresh loads list the same open reports; none open still means no panel. One host per list holds only the last answer, and while one triage post is pending a submit from another row is blocked, as a double submit is, until the answer arrives. Added after the wave-4 gates: only touched/related tests (11 files / 188) and eslint on the changed files ran. | 13 failed / 33 passed (new file 12 / 10; A10 guard 1) → 46/46 | 18/18 |
| AC1 | `cf02bbb8` | Read-only "Delivery channel" block at the top of /system's Alerts panel, for the owner's alert-channel preparation (the owner's email, no unverified recipient, nothing activated). **Delivery switch:** `alert_delivery_enabled` from the `ops.settings` result the page already reads (platform_admin only, 116:1593-1601). Only a literal true or false is shown; a non-admin reader, a failed read, no row, or any other value reads "unknown" with its reason, never the seeded default. **Schedule:** always "not shown by the server (owner/A to verify)". `ops.job_health` returns each cron job's jobid, name, schedule and active flag but not its command (143:186-197), and 146 adds no read, so no record establishes whether `ops.dispatch_alerts` is scheduled. **Channel:** "email to the owner's verified account email — prepared, not active (owner action)", marked as from the runbook and not a server read. It is fixed text, so the line needs a code change when the owner activates the channel. **Runbook:** the path `docs/dashboards/ALERT_CHANNEL_RUNBOOK.md`, shown as text, not a link. The file was added in `0b70026d` on `docs/dashboards-hosting-package` and is not in this tree. No new server call (the block reuses the settings and job_health results), no control, no email address. Added after the wave-4 gates: only touched/related tests (10 files / 145) and eslint on the changed files ran; typecheck not run. | 11 failed / 1 passed → 12/12 | 18/18 |

- **Review follow-ups** (independent review of F1–F6, 2026-10-21). Same rule: one commit each, a test that failed on the parent, planted mutants:

| | Commit | Fix | RED → GREEN | Mutants caught |
|---|---|---|---|---|
| F2b | `00fa892a` | `.env.example` ships `NEXT_PUBLIC_ENV_LABEL=local`, which was on the allowlist, so a developer on a hosted project got "fixture data". The notice now needs an explicit `harness` or `rehearsal` label (`local` removed; it stays a badge) **and** a `NEXT_PUBLIC_SUPABASE_URL` whose hostname is exactly `localhost`, `127.0.0.1` or `::1`. Still never on Vercel production or preview. | 7 failed / 3 passed → 10/10 | 7/7 |
| F1b | `b2b4d31f` | A `list_actions` row the client's exact match missed (subject_id in another case, a reshaped row) fell through to "clear". The server already filters by type, subject and the unsettled states, so any returned row now means pending (exact match preferred); items or `count_hint` > 0 with no usable row hide the form; only an empty page clears. | 7 failed / 21 passed → 28/28 | 7/7 |
| F7 | `128caa74` | Pre-existing (also on `07100a35`): after `getClaims()` refreshed the session, a proxy redirect (aal1 → `/mfa`, aal2 on `/login` or `/mfa`, no session → `/login`) dropped the rotated cookies, so the operator was signed out later. Redirects now carry every cookie through `hostOnlyCookie` plus the no-store cache headers, and nothing else. | 5 failed / 3 passed → 8/8 | 7/7 |
| F8 | `0495d524` | A's request, ahead of its refusal code. A raised error with an unseen code and a `rejected` outcome with an unseen `reject_reason` already rendered generically with the database's message; tests with the invented code `duplicate_unsettled` now pin both, for `execute_action` and `approve_action`. Changed: an answer with an unknown `status` no longer drops the database's message and code. | 2 failed / 10 passed → 12/12 | 9/9 |

- **Port of PR #89** (A said yes, 2026-10-21; `origin/admin/refund-classification-console` @ `3dab1614`). It is
  stacked as local commits, and #89 stays unmerged as the review surface. The panels are integrated into v2's
  components rather than #89's page layout. Record: `docs/OPS_CONSOLE_OPERATOR_GAPS.md`. Nothing is enabled, and
  the refund detector and alert delivery stay owner decisions.

| | Commit | What | RED → GREEN | Mutants caught |
|---|---|---|---|---|
| P1 | `cc713640` | Refund resolution on a case (migration 144): Classify, Obligation and the Status warning in `CaseWork` (the split pane and the full page), plus the `CaseRefundResolution` panel. Includes #89's `refund-resolution.ts` and its tests. | 14 failed / 40 passed, and #89's suite fails to load → 65/65 | 17/17, including #89's 4 negative controls at #89's counts (3, 3, 2, 1) |
| P2 | `dd91280f` | Alerts on /system (migration 146): the delivery and acknowledgement fields parsed, `AlertList` and `AlertAckForm`, `ops.alert_ack(p_alert_key, p_note)`, and owner-decision help for both switches. | 2 failed / 7 passed, and alert-ack fails to load → 27/27 | 18/18 |

- **Review follow-ups to the port** (2026-10-21). Same rule: one commit each, a test that failed on the parent, planted mutants:

| | Commit | Fix | RED → GREEN | Mutants caught |
|---|---|---|---|---|
| P1b | `e5beb6a4` | The Obligation control's State defaulted to *Settled*, the value that unlocks closing under 144's guard, so a progress note recorded untouched made a case closable over money still owed. It now has no preselected value (disabled "Choose…" option, `required`); an unchosen post goes as null, which 144 records as not settled. | 2 failed / 13 passed → 15/15 | 4/4 |
| P1c | `09f9d72b` | Classify's owner select defaulted to the operator, and 144 assigns on every classify, so an unassigned case was silently assigned. It now defaults to *Leave as is*, which posts no `assignee` (new `param.<key>:optional` type: empty is left out, not sent as null), and is labelled "Assign the case to" with help saying classifying assigns. | 6 failed / 19 passed → 25/25 | 5/5 |
| P2b | `17f6da80` | Acknowledge posted only `alert_key`, so a re-fire after the page loaded was acknowledged unseen. The form now posts the rendered `incident_seq`; a different incident in `alert_ack`'s answer returns a warning naming both; `AlertList` keeps the control mounted for acknowledged rows so the result survives the refresh. | 7 failed / 18 passed → 25/25 | 7/7 |
| F8b | `32781df3` | `unrecognisedResponse` used `pick`, which stops at a present null, so `reject_reason: null` hid a real `code` (and `message: null` a `detail`). Now the first non-empty string. | 2 failed / 12 passed → 14/14 | 3/3 |

- **Reviewer E's pre-deploy condition and LOW items** (independent review of #121, 2026-10-21). Same rule: one commit each, RED on the parent (src reverted with `git checkout`, final test files), planted mutants the tests had to catch. Only targeted vitest and eslint on the changed files ran (the shared heavy slot was held); raw logs with exit codes are in the private evidence folder, `round3-e-conditions`.

| | Commit | Fix | RED → GREEN | Mutants caught |
|---|---|---|---|---|
| P3 | `7dae15d2` | `ops.list_actions` filters by one `action_type`, so a pending `refund_execute` on the payment left "Request release" offered and a pending `payout_release` on the transfer left "Request refund" offered (check-then-act across two tabs or founders). Whenever either money form is offered the page now reads BOTH types for the same order — `payout_release` on the transfer subject, `refund_execute` on the payment subject, `refund_actions` kept as a source — and each form's guard folds the other in (`combineMoneyGuards`): either pending → both forms hidden, the "Already requested — <state>" notice naming and linking the blocking action ("Execute refund is pending on this order and blocks this form too: one money action at a time per order"); otherwise either unverified (failed read, unparseable page, any returned row, a transfer row without an id) → both hidden; only both clear → both forms. No transfer row never blocks the refund form; no money form offered → no read. Four earlier assertions that pinned the opposite ("the refund form is unaffected by a release on the transfer") flipped, plus two in A11. | 22 failed / 50 passed (72, 3 files) → 84/84 (4 files, with stripe-mode's page render) | 6/6 (same-type-only restored 22, cross-type read dropped 3, other-type error ignored 8, other-type pending ignored 15, id-less transfer reads clear 1, notice stops naming the action 5) |
| L1 | `8a23a2f6` | The Refund note said "Until migration 150 is live there is no column…"; 150 is applied. Now: 150 keeps each Stripe refund's own status in `payment_refund_state` and a counted refund stays counted even if it later fails (the manual refund SOP's §5.2, 150 cited by line); this page shows only the payment status, "refund recorded at", the Stripe refund id and the console's attempts, none of which says a refund settled — still "confirm the outcome in Stripe". No claim about `ops.order_detail` returning 150's rows. Source pin in readiness-fixes. | 1 failed / 24 passed → 25/25 | copy only: none |
| L2 | `98faee20` | `toActionOutcome` (lib/types.ts, not actions.ts: `unrecognisedResponse` there already had F8b's fix) read the rejected branch with `pick`, which stops at a present null, so `reject_reason: null` + `code` rendered as "precondition" and `message: null` hid a `detail`; same on `action_id` and the failed branch's `error`. `firstText` now lives in lib/types.ts and is used for all four; actions.ts imports it. | types 1 failed / 5 passed → 6/6; unknown-ops-codes (both `execute_action` and `approve_action`, rendered) 2 failed / 14 passed → 16/16 | 5/5 (reason via pick 3, message via pick 3, empty string accepted 5, failed error via pick 1, action_id via pick 1) |
| L3 | `bc852196` | `tests/review-e-gates.test.ts`: `requireOperator` sends aal1 / no aal / unknown aal to `/mfa` before `ops.whoami` is called (controls: aal2 → operator; denied or non-operator role → `/denied`); `canRequest` table for both money verbs over every role, `allowedRoles` = `["platform_admin"]`, support's own verbs as control, and rendered: support and risk get no money form and both notices even with clear guards; `OrderActions` with `canRelease` / `canRefund` false → no panel, no form, even with clear guards; the proxy matcher compiled by Next's own `getMiddlewareMatchers`: one constant string, runs on `/`, the auth screens, every console route, `.rsc`, `/api/*`; skips only `_next/static`, `_next/image`, `favicon.ico` and image extensions. | pins existing behaviour: 16/16 (no RED on the parent; the RED is each mutant) | 8/8 (aal2 redirect removed 2, refund_execute opened to support 2, payout_release opened to risk 2, canRelease ignored 2, canRefund ignored 2, matcher keeps `_next/static` 1, excludes `/login` 1, excludes `/api` 1) |
| L4 | `d4ce4d22` | `safeInternalPath` refuses — never rewrites — a path whose path part holds a `.` or `..` segment, an empty segment other than a trailing slash (`//` after position 0), or their `%2e` forms (WHATWG treats `%2e` as `.` in a segment): `/.//evil.com`, `/a/../b`, `/a//b`, `/orders/..`, `/%2e%2e/x`, `/%2e//evil.com`… Query string and fragment are not path segments and pass; `/a.b`, `/x/..y`, `/x/.hidden`, `/orders/` pass. Tests in `tests/redirect.test.ts`, the existing corpus (the review's `auth-redirect-adversarial.test.ts` does not exist in this tree); proxy-logic and proxy-session-redirect stay green. | 1 failed / 4 passed → 5/5 | 5/5 (`.` check 1, `..` check 1, `//` check 1, `%2e` decoding 1, whole check skipped 1) |
| L5 | `3d1ace19` | `sessionCookie()` for every session cookie the console writes (server client, proxy refresh, proxy redirect; the browser client gets `cookieOptions {secure: true}` too): host-only as before, `secure: true` when `NEXT_PUBLIC_VERCEL_ENV` is exactly `production` or `preview`, never on local `next dev`; `httpOnly` forced false by construction. Verified first: `MfaFlow` uses `getSupabaseBrowserClient()`, a `createBrowserClient` with no cookie accessors, so @supabase/ssr 0.12.6 reads the session from `document.cookie`; an HttpOnly session would leave the TOTP flow signed out. The F5 exact-equality assertion on the server write gained `httpOnly: false`. | domain-readiness 9 failed / 10 passed → 19/19 (proxy-session-redirect 8/8 unchanged) | 5/5 (preview dropped 4, Secure in local dev 3, host-only dropped 14, httpOnly not forced 5, browser client not told 2) |
| L6 | this commit | This table; the "not pushed / no PR / no CI" lines above and in *Not done* replaced; the PR count. | — | — |

- **Gates at `cd54a3dc`** (npm ci, local Node v24.13.1):
  - typecheck 0, lint 0;
  - vitest **33 files / 262 tests**, against 26 / 211 after the import;
  - `next build` 0 with the CI placeholder env: Next.js 16.3.8, 18 dynamic routes, /_not-found and the Proxy.
  - A build with `NEXT_PUBLIC_VERCEL_ENV=production` and `NEXT_PUBLIC_SITE_URL=https://admin.snatchitapp.com` passes.
  - Builds with an `sb_secret_` key, or with a production SITE_URL outside the allowlist, exit 1 with the refusal message.
- **Domain notes (admin.snatchitapp.com):**
  - No link, redirect or auth flow is built from the host. The only host names are the `PRODUCTION_SITE_HOSTS` allowlist in `src/lib/env-policy.ts` (`admin.snatchitapp.com`, `snatchit-admin.vercel.app`), a build-time check: a Vercel production build whose `NEXT_PUBLIC_SITE_URL` is on any other host exits 1. Comments in `env.ts` and `cookie-options.ts` mention hosts too, but drive nothing. So adding a host, or retiring `snatchit-admin.vercel.app`, is a code change plus a release, not only a Vercel setting. `env.ts`'s dev default `http://localhost:3200` is refused the same way.
  - `form-action`, `frame-ancestors` and `connect-src` are origin-relative (`'self'`) plus the Supabase origin, so they need no change on the new host.
  - Server Actions stay same-origin (no `allowedOrigins`).
  - Cookies are host-only, so operators sign in again on the new host. Sessions on `snatchit-admin.vercel.app` do not carry over, and none are shared with venue./app.
  - Admin uses password + TOTP only, with no redirect-based auth flow. Remove the `snatchit-admin.vercel.app` entry from `PRODUCTION_SITE_HOSTS` once the custom domain is live and the alias is retired. That removal ships in a release of its own.
- **Deploy note (server actions):** every console form posts to a Next.js server action, and server-action ids are build artifacts. They change on any Next version change (F6 is one), on a build without the build cache, and on a rollback to another build; Next also rotates them at most every 14 days, even when the source is unchanged. A console tab loaded before a promote or rollback then posts an id the serving deployment does not have ("Failed to find Server Action"), and the submit fails without reaching the database. Operators reload every open console tab after any promote or rollback (a reload also mints a fresh idempotency key), or the owner enables Vercel Skew Protection on the project so an old tab keeps reaching the deployment it was loaded from.
- **Not done here:**
  - pushing `d6ff9989` and the reviewer-E commits (P3, L1–L6) to #121, and reading that CI run (owner's process);
  - the full gates (npm ci, full vitest, project-wide typecheck, `next build`) after R1's `9c79312d` (typecheck 0, lint 0, vitest 42 files / 427, `next build` 0): RR1, AC1, `d6ff9989` and the reviewer-E commits ran only targeted vitest (final at `3d1ace19`: 24 files / 341, every touched test file and the suites importing the changed modules) and eslint on the changed files (0). Full tsc, full vitest and `next build` are owed at the branch tip; the gate figures in *Gates at `cd54a3dc`* below are for that commit;
  - P1–P2 (with P1b–P2b) against a local replay with 144 and 146 applied. The flows are listed in `OPS_CONSOLE_OPERATOR_GAPS.md` §3.2: classify, record obligation, resolve refused then allowed, `alert_ack`, and an acknowledgement from a stale page across a re-fire;
  - any browser, signed-in or aal2 render;
  - Vercel domain, DNS, TLS and env changes (owner);
  - the server-side duplicate refund/payout rule and relist expected-version (A's migrations; F1 stays a UI guard);
  - `expected` on the suspend/restore forms (OC-17);
  - the sharp and source-map-js lockfile advisories.

## V-1 visual hierarchy (`admin/console-v2-visual`, 2026-10-22)

Branch off #121's head `2fc0c8f4`, admin/ only, **local — not pushed, no PR, no CI run.** The owner's
requirement (2026-10-22, verbatim): "Improve the admin dashboard's visual hierarchy while keeping Snatch It
branding: useful real-data charts, trend comparisons, status breakdowns, sortable/filterable tables and small
explanatory workflow diagrams where they help operations. No invented metrics/sample success data. Label date
ranges, currency, timezone, data freshness and unavailable/empty/error states; exclude test rows consistently.
Use restrained motion, respect reduced motion and keep layout/performance/accessibility sound." Authorization,
MFA and money-action code and copy are untouched: no edit under `src/lib/auth`, `src/lib/actions.ts`,
`src/components/orders/OrderActions.tsx` or `src/proxy.ts` (a test asserts OrderActions neither imports nor
renders the new diagrams). Every figure still renders only what the `ops.*` read returned, per request, never
cached; no dependency was added. One commit per item, each with a test that was RED first and planted mutants
the tests had to catch; raw outputs with exit codes are in the private evidence folder `logs/v1-visual/`.

| | Commit | What | RED → GREEN | Mutants caught |
|---|---|---|---|---|
| V1-1 | `9e629bf2` (+ `9b345c74`) | **Labels and states on every figure surface.** `lib/figure-meta.ts` (pure): `CURRENCY` "USD" and `TIMEZONE` "UTC" taken from the formatters the console prints (`formatMoney`, `formatUtc`; buckets are UTC calendar days); `rangeLabel`; `asOfLabel` from the server's `computed_at` — a missing one reads "not stated by the server (read <time>)", never the read time dressed up as freshness; `isPartialPeriod` from the request's own clock ("includes today so far (partial)"); `tileState`: null → unavailable, zero rows → empty, else a figure. `FigureMeta` is the one line each surface carries; `readAt` is the server render time. `KpiTile` / `ChartCard` carry `data-state` ok · empty · unavailable · error: empty keeps the genuine zero and says so; unavailable shows "Not available" (no dash, no delta); error shows "Not read" — never a zero or an empty plot; a chart measure returned in no period is unavailable, checked before "empty". Money KPIs: one label above the group, the pending tile labelled point in time, a failed read keeps the surface with every tile in the error state under a subject-led alert ("Business figures couldn't be loaded."). Money charts: a label per card; the failed bucket is now visible under "For support" (the generic alert never printed `fn`). Today's attention counts and /system's metric row are labelled point in time with `ops.today` / `job_health` freshness. | file fails to load on the parent; with only the three new modules present 24 failed / 13 passed (37) → 37/37; related suites 8 files / 137 | 15/15 (one survived first — a failed read's group label losing `failed` while the pending tile kept it — killed by `9b345c74`) |
| V1-2 | `0a2b7648` | **Trend comparison and status breakdowns from real reads.** `compareWindows` (pure): the change from the previous `money_overview` window to the current one with its sign always stated ("+", "−", "±"), a whole percentage of the previous value, no percentage when the previous period was zero, "n/a" naming the missing side. `PeriodComparison` on Money under the tiles: both periods named in the header, "+$500.00 (+61%)" / "±$0.00 (no change)" / "+$225.00 (none in previous period)" / "n/a — previous period couldn't be read" / "n/a — not returned by the server"; a decorative pair of bars per row compares the same measure across the two periods (one measure per axis). Pending (point in time) and bank payouts (not tracked) are not compared; Today keeps the "Compared with …" line. `lib/breakdown.ts` (pure) + `StatusBreakdown`: counts per status over the rows the page's own list read returned, most common first, "Not stated" last and never dropped, the share of the row total, the scope ("N orders on this page") in the label; no rows is an explicit empty state. Orders: payment / ticket transfer (row-aware `transferStateLabel`, so `buyer_confirmed` with no confirmation record is never a buyer confirmation) / seller funds. Cases: status and priority. No new read. | file fails to load on the parent → 20/20; related suites 7 files / 134 | 16/16 |
| V1-3 | `a41ab6b8` | **Sortable + filterable DataTable.** `lib/table-view.ts` (pure): `nextSort`, `sortedIndices` (by the underlying value — the recorded code, integer cents, the ISO timestamp; stable; blanks last in both directions), `matchesFilter` (every word, case-insensitive), `viewIndices`. `ClientTable` ("use client"): the server still renders every cell and passes the elements down with each row's sort values and filter text (serialisable; no function crosses the boundary; no server DOM mutation — `next/dist/docs` server-and-client-boundary); it only re-orders or hides the rows it was given on this page, never re-fetches, never changes the server's row set; headers are native buttons ("Sort by <column>"), the sorted column carries `aria-sort`, a polite status line says "this page only" and "N of M rows shown"; without JS the server order renders. `DataTable`: `sortValue`, `headerText`, `firstSortDir`, `filterable` + `filterText`, `defaultSort`, the `notice` slot; a table that opts into nothing is byte-for-byte the old server table; pagination, caption, selection and the phone cards are kept. `OrderTable`, `CaseTable`, `UserTable`, `ListingTable` carry underlying values and an exported filter text; Orders, Users, Marketplace opt into the filter beside their server-side chips/forms; the Cases queue (a list) gets `SortFilterList` (native select Detected / Due / Priority / Title / Status, a direction button, the filter) with the keyboard model untouched. `data-sort-value` / `data-filter` make the wiring observable. | file fails to load on the parent → 31/31; every table / list page suite 17 files / 327 | 20/21 + 1 equivalent (dropping the explicit tie-break: V8's sort is stable since ES2019, so no behaviour changes) |
| V1-4 | `e1c4ea9d` | **Two static workflow diagrams** on the order page's actions column, after the action panels, collapsed behind "How this works". Refund path as it is today: Request refund (founder; parked as awaiting approval; full refund of the total only) → Two-founder approval (System → Approvals; nothing changes until then) → Execution disabled in production (`refund_execute_enabled` false; rejected as disabled; the console never calls Stripe) → Manual Stripe Dashboard refund per the manual refund SOP, **named as a draft not approved for use** (a full refund of the PaymentIntent; the `re_…` id noted on the case) → Webhook records the result ("Refund recorded (not confirmed settled)" is set by the Stripe webhook, never by the console; confirm the outcome in Stripe). Payout release: Seller marked sent (`seller_sent`, no release recorded, no open dispute) → Request release ("Release held payout", awaiting approval) → Second founder approval → Payout worker (Stripe Transfer to the connected account on its next run — not a bank payout; "Released to connected account"). Each step has `pins` and `sources`: the test checks every pin is in the step's own text and in a cited source — OrderActions and order-page copy, `lib/format.ts` labels verbatim, and the SOP file where it is checked out (`repos/snatchit-admin-sop`, branch `admin/manual-refund-sop`, cited by section). Inline SVG, `role="img"`, `aria-labelledby` its own `<title>` + `<desc>`, `focusable="false"`, viewBox + `w-full max-w-full h-auto`; a visually hidden `<ol>` is the text alternative and lists each step's source. | file fails to load on the parent → 15/15; order page suites 7 files / 105 | 17/17 |
| V1-5 | `67afd6a9` | **Motion and accessibility guard.** `.reveal`: a 160 ms fade-in on the disclosure body (the existing `fade-in` keyframes) — the only animation V-1 adds; the stylesheet's global `prefers-reduced-motion` rule removes it. `tests/motion-a11y.test.ts` pins on the sources and the markup: every V-1 duration ≤ 200 ms, no `animate-*`, the global reduced-motion and `:focus-visible` rules intact; no new control hides its outline, leaves the tab order or needs a key handler; focus order filter → sort buttons → rows and select → direction → filter → list; labelled fields, polite live status; at phone width the tables and the comparison scroll inside their container, toolbars wrap with fields capped at the viewport, the breakdown bar fills its column with a wrapping legend over one-column grids, the diagrams scale by viewBox with no fixed size, no new label forces one line. | 2 failed / 12 passed on the parent → 14/14; stylesheet, diagram and table suites 5 files / 80 | 14/14 |

- **Test rows (DC-1 / DC-2).** DC-1 (migration 180, the server-side exclusion) has not landed. No client-side
  test filter was added and no count is invented: every chart, table and KPI renders exactly what the server
  returns. **The single hook for DC-2's "N test records hidden" notice is
  `src/components/ui/HiddenTestRowsNotice.tsx`** (renders nothing unless given a server-reported integer), wired
  through `DataTable`'s `notice` slot for lists and `FigureMeta`'s `notice` slot for figures; nothing passes it
  yet, and `tests/figure-labels.test.ts` asserts no page renders the hook. The pages' own text filter is a view
  over the rows the server returned ("N of M rows shown"), not an exclusion.
- **Gates (heavy slot held 15:42:38Z → released 15:42:57Z, and 15:45:24Z → 15:45:59Z; local, Node v24.13.1,
  the sibling checkout's node_modules cloned, no install).** First run at `67afd6a9`: full vitest **50 files /
  629 passed**; tsc **3 errors**; `next build` with the CI placeholder env **exit 1** on the same type check
  (`06-gate-*.run1-at-67afd6a9.log`). The three errors — `aria-sort` typed as a string in `ClientTable`, a test
  fixture missing `raw`, a test reading a union field without narrowing — are fixed in **`20c7b6d2`** (no
  behaviour change; eslint 0). Second run at `20c7b6d2`: tsc **0**; full vitest **50 files / 629 passed**;
  `next build` with the CI placeholder env **exit 0** — Next.js 16.3.8, 18 dynamic routes + `/_not-found` + the
  Proxy (`06-gate-tsc.log`, `06-gate-vitest.log`, `06-gate-build.log`). `.next` removed after each run.
  **Branch tip: `20c7b6d2`** (this document is committed on top of it).
- **eslint on the changed files:** 0 for every item (`0N-itemN-eslint.log`). Only targeted vitest ran during the
  work (per item: the new file plus every suite that renders a changed module).
- **Evidence:** `private-evidence/F-web-redesign/logs/v1-visual/` — per item `red-parent`, `green`, `eslint`,
  `mutants` logs with exit codes; `mutate.sh` (plants one perl mutant, runs the tests, reverts with
  `git checkout`); `gates.sh`; `06-gate-*.log`.
- **Not done here:**
  - a DOM event test of the sort / filter interaction (no jsdom in the tree): the behaviour is proven through
    the pure view functions and the SSR of a default sort; any browser render, screenshot, signed-in or aal2
    check of the new surfaces;
  - drawing the previous period as a second series on the charts: only the KPI / table comparison from the two
    windows v2 already reads (a per-bucket previous series would double the `money_overview` calls — AN-1 first);
  - sort / filter on the Money page's "Payouts by transfer" and "Reconciliation queue", /system, /reports,
    /search, the action and audit tables, or the detail-page sub-tables (only the four lists the owner named; the
    shared `OrderTable` / `CaseTable` / `ListingTable` are sortable wherever they are rendered);
  - per-tile labels on /system's `MetricTile` cells: the row has one point-in-time label line;
  - the pre-existing animations above 200 ms (`.enter` 360–460 ms, `.drawer` 260 ms, `.meter` 500 ms) and the
    pre-existing `?? 0` rendering of a null count in `UserTable` / `ListingTable` (the sort mirrors what is shown);
  - `OpsFailureAlert` without a `subject` still never prints `fn` (fixed only for the charts by leading with a
    subject); the header `FreshnessSlot` still reads "Live data" when a page reports no `computed_at`;
  - the SOP is cited as a draft; it is not approved for use and its wording may change — the diagram test reads it
    from the sibling checkout when present and from `docs/admin-console/` if it lands in this tree;
  - pushing, a PR, CI (owner's process).

## What changed in the readiness pass

A two-scope audit (route/action contracts; responsive/keyboard/error states)
returned 72 findings. Each was verified in code (and against the SQL function
definitions where a filter or count was involved) before fixing.

**Admin — data and navigation.** "Needs an owner" / Assignee → Unassigned sent a
key `list_cases` ignores (assigned cases were included); later Orders pages
showed their own length as the total; open-case badges linked to a payment-id
filter that misses transfer and listing cases; a failed approvals read showed
`0`; Today's count used the 200-row list and its case links included closed
cases; retry links dropped filters on seven pages; a missing case id looked like
an outage; CaseTable offered sort links the server ignores; the due date said
"your local time" but is stored as UTC wall clock; dispute search hits linked to
themselves; nav said "Money & refunds" for a page with no refunds surface.

**Admin — A's nine approved items** (A's decisions 2026-10-12; D reviewed 2, 3,
4, 9 — no blocking finding):
1. `/system` setting and job forms revalidate (new idempotency key, current value).
2. `OutcomeHost` keeps the server's answer visible across the version-keyed
   remount (same fields to the same server action, text unchanged). One host per
   report on purpose: the report's forms re-key on the new status.
3. Submit stays focusable while pending (`aria-disabled` + click guard + form
   ref guard) in ConfirmForm, LoginForm, MfaFlow.
4. The order page shows "Already requested — <state>" instead of a re-armed
   refund/release form while one is unsettled. **Advisory (UI only).**
5. payout_review tile → `/money#payouts`.
6. Orders queue hints use the reviewed labels verbatim.
7. Unknown counts show "—"; unknown chart points are skipped; unreadable Today
   checks are listed, never counted clear.
8. A denial reads "Denied — nothing changed."
9. Sign-in outage copy is fixed text; `/denied?reason=` carries a code mapped to
   fixed text (raw reason only in the server log).

**Admin — keyboard/layout.** Order drawer keeps Tab inside; a popover's Escape no
longer also closes the case pane or drawer; phone filter and New manual case
popovers stay on screen; Cases pane scrolls within the viewport; single-key
shortcuts can be turned off (WCAG 2.1.4); console error boundary (Next 16
`retry()`); scroll padding clears the sticky bars below lg; placeholder contrast.

**Venue.** Preview links with a query or `#fragment` dropped the demo persona
(any non-default role silently became venue_manager); Today showed door figures
and "Open check-in" to roles the door screen denies; phone guest cards showed
ticket types to finance and no email to contact roles; finance could filter by
check-in through the URL; box office was sent to a door screen it can't open;
database mode stated holds, warnings and check-in-list state it never read; an
upcoming freeze was in the past tense; prices with cents failed validation;
the forced error state was mislabelled; denial pages lacked a heading/landmark;
phone header popovers opened off-screen; headline figures were invalid `dl`
markup. The final sweep then caught two regressions of this pass (an sr-only
span widening the phone purchasers view by 426px; the wizard error state's
missing h1), fixed in `bb94b1f2`.

## What did not change

- Money/refund/payout/transfer wording in `admin/src/lib/format.ts` — no label
  edited; Orders hints now use those labels verbatim.
- Every operator change still posts the same envelope to `execute_action`:
  expected version, a fresh idempotency key, the audit reason where required.
- `proxy-logic`, `requireOperator`'s aal2 and operator checks, server actions'
  authority, security headers, `supabase/` — unchanged. No migration, no auth
  configuration, no production credential, no live operational action.
- Venue demo actions stay labelled simulated; database mode stays read-only.

## Routes (unchanged)

Venue: `/`, `/login`, `/o/[org]/v/[venue]` (Today), `…/events`, `…/events/new`,
`…/events/[event]` (Event setup), `…/door` (Check-in), `…/attendees` (Guest list),
`…/inventory` (Tickets). Admin: `/login`, `/mfa`, `/denied`, `/`, `/cases`,
`/cases/[id]`, `/orders`, `/orders/[paymentId]`, `/transfers/[id]`, `/money`,
`/users`, `/users/[id]`, `/marketplace`, `/marketplace/[id]`, `/reports`,
`/search`, `/system`, `/actions/[id]`.

## Route / contract coverage

| Read or action | UI params / fields | Verified |
|---|---|---|
| `list_cases` | status[], priority[], case_type[], assignee me/unassigned/uuid, subject_kind, subject_id, cursor | against the function body; unit + browser (counts move) |
| `list_orders` | payment_status[], transfer_status[], payout_state, has_open_case, from/to, q, cursor; count_hint first page only | against the function body; unit + browser |
| `case_detail` | `not_found:` → "No case with this id." | browser |
| `order_detail` | actions + refund.refund_actions → pending request state | unit + browser (staged unsettled action) |
| `execute_action` envelope | unchanged; OutcomeHost/pending guard do not alter fields | D review; unit (field assertions); browser (1 action from 3 clicks) |
| `list_approvals` failure | "—" + "Couldn't be loaded" | browser via test-only fault proxy |
| Venue role matrix (`roles.ts`) | Today, guest list (table and cards), header search, door lookup | unit + browser per role |

## Verification (local production builds of the code tips, synthetic data)

- Unit: admin 197/197, venue 157/157; typecheck and lint clean. New tests
  `admin/tests/readiness-fixes.test.ts`, `admin/tests/auth-stub-totp.test.ts`,
  `venue/tests/readiness-fixes.test.tsx`; mutation-checked — 21 admin and 16 venue
  mutants (plus 2 on the stub's self-test), all killed, restores digest-verified.
- Browser (headless Chrome, real keys and clicks): admin checks R1–R14 and venue
  checks all pass (item 4's text assertion was tightened and rerun after an
  encoding slip in the check itself); Cases keyboard model unchanged.
- Heading/overflow sweep: admin 17 routes and venue 24 routes/states, desktop
  1440×900 and phone 390×844 — every page headed, 0 horizontal overflow.
- Reduced motion + reduced transparency: 0 animations, 0 transitions, 0 backdrop
  blur; glass solid on phone.
- Rendered contrast: 0 failures — admin 2,798 elements (7 pages), venue 1,088
  (12 pages).

### QR enrolment evidence

The local auth stub (`admin/scripts/auth-stub.mjs`, test harness only) now
returns GoTrue's enrolment shape — checked against the public supabase/auth
`mfa.go`, goqrsvg and svgo sources: raw SVG of `fill:black`/`fill:white` rects
(no `#`), block 3, level H, 20-byte base32 secret, SHA1/6 digits/30 s, skew 1 —
and verifies real RFC 6238 codes (`HARNESS_MFA_MODE=totp`).

On the real console flow, with no response patching:
- the rendered `<img>` is the data URL supabase-js builds;
- Chrome's built-in decoder (macOS Vision, independent of the encoder) reads it
  as `otpauth://totp/…`, and its secret equals the displayed secret;
- the fixed code 123456 and an expired code are refused, and a code computed
  from the decoded secret completes enrolment and lands on Today;
- the next sign-in's verify step accepts a computed code;
- on load the auto-focused code field has `:focus-visible` and a 4px ring
  (none when blurred).

**No real authenticator app has scanned the code.** The test operator's factor
was removed afterwards.

## New or changed visible strings

Admin: "Couldn't be loaded" · "Approvals (—)" · "This page couldn't be shown" ·
"Something unexpected went wrong while loading it. Try again; if it keeps
happening, send the reference below to whoever looks after the console." · "Go
to Today" · "Reference {digest}" · "Single-key shortcuts" "On"/"Off" · "Already
requested — {state}" · "Nothing more can be requested here until it finishes." ·
"Denied — nothing changed." · "Sign-in is unavailable right now. Try again in a
moment." · "The console's database could not be reached." · "The access check
returned an error." · "Nothing needs attention among the checks that were read."
· "{n} check(s) couldn't be read: …" · " · {n} listed" · "Due (UTC)" (was "Due
(your local time; stored as UTC)") · nav "Money" (was "Money & refunds") ·
Orders hints "Has an open case", "Seller funds: Manual review", label "Manual
payout review" (reviewed labels) · "closed {date}" · aria "More — all sections".

Venue: "Holds aren't readable in this mode." · "Check-in list state isn't
readable in this mode." · "Transfers will freeze at {time} — at doors time, or
earlier if the check-in list is opened first." · "Open your venue's link" + "The
dashboard opens at your venue's own address. Use the link your venue manager or
organization owner gave you." · not-found (database mode) "Not found", "This link
doesn't match a page of the venue dashboard. Use the link your venue gave you." ·
"This screen couldn't be shown" + "…send the reference below to Snatch It
support." · "Back to Today" · "Issuing and revoking PINs is done on a larger
screen." · "Downloads are requested on a larger screen." · "Capacity changes are
made on a larger screen. Everything else here works on this screen." · "Slice 1
covers the events list, event setup and ticket availability (read side)." · aria
"{Sample data|Database} — about this data".

## Captures (SSD, private, not committed)

`/Volumes/DEV-SSD/01_SNATCH_IT/repos/snatchit-venue-v2/.f-handoff/` —
`final8/` (final-build sweep, both apps, desktop and phone), `final7/`
(`admin-mfa-enrol-realqr-*`, `admin-mfa-verify-focus-desktop`), earlier sets as
listed in the previous handoff. That folder also holds harness configuration and
logs; never commit or share it.

## Local previews and restart

Running from the SSD: venue http://localhost:3311/o/smp_org_wynwood/v/smp_ven_room,
admin http://localhost:3213/cases (synthetic operator through the auth stub).
Restart steps: `.f-handoff/RESTART.md` (private). For the real-TOTP/QR stub start
it with `HARNESS_MFA_MODE=totp HARNESS_QR_ENCODER=<repo>/snatchit/node_modules/qrcode-terminal/vendor/QRCode`.

## Remaining limitations

1. **Real authenticator scan not performed** — QR evidence is the synthetic
   GoTrue-shaped enrolment decoded from the rendered page.
2. **Duplicate refund/release is guarded in the UI only (item 4).**
   `execute_action` has no server rule against a second unsettled action of
   the same type and subject. A stale tab or a second operator can still park
   one, and this applies to the current console too. `order_detail` `actions`
   is limit 50, so an old payout_release can fall out and re-arm the form.
   Recorded by A as a production finding for the owner, parked from this
   release. On `admin/console-v2-integration` (F1, `2e103504`) the 50-row gap is
   closed: the guard also reads `ops.list_actions` and fails closed. The server
   rule is still A's migration.
3. A15: relist's expected state is not compared server-side (A/D, needs a migration; parked).
4. A 429 at sign-in reads as a credentials error (A: stays as written).
5. Box office has no lookup surface: the role matrix allows manual lookup but the door screen denies the role (D's roles spec).
6. Venue database mode has no route loading state (a route `loading.tsx` would blank each screen's own frame on every navigation, including the demo); database-mode error screens keep pre-v4 styling.
7. Small phone targets meet WCAG AA 2.5.8 (24px), not the 44px AAA guideline; MetricTile definitions on /system are hover-only.
8. Screen reader (VoiceOver) not exercised; real event photography needs storage work — both optional.
9. The private rehearsal copy keeps the harness's append-only audit rows (labelled "harness:"); state was restored.

### Full gates run 2026-10-21 (wave 4, local, Node 24.13.1; CI on Node 22 runs on the PR)
Supersedes the "still owed" notes above for these items.
- `npm ci`, typecheck, lint: exit 0. `npm test`: **38 files / 353 tests**. `next build` with the CI placeholder env: exit 0 (18 dynamic routes + /_not-found + Proxy).
- Production guards, re-run first-hand by the lead at 07591c28:
  - a `sb_secret_` key gives exit 1, "Refusing to start: … is a Supabase secret key", and the key appears 0 times in the log;
  - `SITE_URL=https://evil.example` gives exit 1;
  - `SITE_URL=https://admin.snatchitapp.com` with an anon JWT gives exit 0.
- #89 flows on a LOCAL replay of the production chain (fix/154 @ bfc5cf97, 171 migrations), driven through the console's real server actions in headless Chrome as an aal2 founder:
  - classify A with "Leave as is" raises no obligation and leaves the case unassigned;
  - classify B raises `payout_owed`;
  - an unchosen State is blocked by the browser; when posted anyway, `settled=false` is recorded;
  - resolve is refused while an obligation is unsettled, and allowed after `settled=true`;
  - `alert_ack` works, and a stale page shows the "new incident #M … showed #N" warning;
  - a recovered alert is refused.
- Not run: the aal1 → TOTP enrolment path in this pass, a real authenticator, and any hosted environment.

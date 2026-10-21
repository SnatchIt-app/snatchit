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

Admin v2 rebuilt on the live console, admin/ only. **Local commits; not pushed,
no PR, no CI run, not deployed.**

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
  - push, draft PR and CI on Node 22;
  - the full gates after F2b–F8, P1–P2 and P1b–F8b (npm ci, full vitest, typecheck, `next build`): the shared machine slot was held, so only the touched test files and eslint on the touched files ran. The gate figures above are for `cd54a3dc`;
  - P1–P2 (with P1b–P2b) against a local replay with 144 and 146 applied. The flows are listed in `OPS_CONSOLE_OPERATOR_GAPS.md` §3.2: classify, record obligation, resolve refused then allowed, `alert_ack`, and an acknowledgement from a stale page across a re-fire;
  - any browser, signed-in or aal2 render;
  - Vercel domain, DNS, TLS and env changes (owner);
  - the server-side duplicate refund/payout rule and relist expected-version (A's migrations; F1 stays a UI guard);
  - `expected` on the suspend/restore forms (OC-17);
  - the sharp and source-map-js lockfile advisories.

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

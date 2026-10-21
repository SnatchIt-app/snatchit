# Dashboard v2 — handoff for release review (Claude F)

Venue dashboard and admin operating console in the owner-approved concept
(visual direction locked 2026-10-09), plus the functional-readiness pass of
2026-10-12. **Not deployed, not merged to `main`, not in the current app
release** (A's `CANDIDATE_MANIFEST.md`). Both are local previews with exact
commits. Venue v2's database mode needs the `venue_api` read views, now registry 159
`20261021120000_venue_api_read_views` (pgTAP 226). It replaces the unapplied
`20260910120000` file these branches still carry (retired, never to be applied).
Venue v2 cannot go live before an owner-approved apply; admin v2 would
replace the current console UI, which is a separate owner decision.

## Branch tips (verified against `origin`, 2026-10-12)

| App | Branch | Code tip | Commits in this pass |
|---|---|---|---|
| Admin | `admin/dashboard-v2` | `fae12913d31bf9ef555c8d627359a45bf2547d35` | `e1c04754` harness TOTP/QR · `c06fad75` readiness fixes · `fae12913` reason kept in server log |
| Venue | `venue/dashboard-v2` | `bb94b1f28ea07dbd4b17b64a5b3031753fb90f21` | `100374ac` readiness fixes · `bb94b1f2` two regressions found by the final sweep |

This document is committed on top of each code tip (docs only). Checkouts:
`/Volumes/DEV-SSD/01_SNATCH_IT/repos/snatchit-admin-v2` and `…/snatchit-venue-v2`.

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
   release.
3. A15: relist's expected state is not compared server-side (A/D, needs a migration; parked).
4. A 429 at sign-in reads as a credentials error (A: stays as written).
5. Box office has no lookup surface: the role matrix allows manual lookup but the door screen denies the role (D's roles spec).
6. ~~Venue database mode has no route loading state~~ — added on `venue/production-readiness` as a frame-shaped skeleton (see below), so a navigation no longer blanks the frame. Database-mode error screens still keep pre-v4 styling.
7. Small phone targets meet WCAG AA 2.5.8 (24px), not the 44px AAA guideline; MetricTile definitions on /system are hover-only.
8. Screen reader (VoiceOver) not exercised; real event photography needs storage work — both optional.
9. The private rehearsal copy keeps the harness's append-only audit rows (labelled "harness:"); state was restored.

## Production-readiness branch (`venue/production-readiness`, 2026-10-21)

Branch off `venue/dashboard-v2` @ `ee1d90b7` (code `bb94b1f2`) for a hosted preview now and a
database-mode host at `https://venue.snatchitapp.com` later. No new features (box office lookup,
database-mode guest list/door and writes stay with D). Not pushed, not deployed; one commit per fix.

| Fix | What changed |
|---|---|
| Acceptance kit | `venue/slice1-acceptance-kit` @ `62ec887d` merged (clean). Kit markers aligned to v2 copy: `DENIED` = "… isn't open to you.", role-label check in any case, after removing v2's own denial sentence ("A venue manager or an organization owner can give you access"; the kit reads innerText, so uppercase-styled text arrives uppercase), "174 still available", Sign out found in the DOM (it sits in a closed popover), and every page read waits for the route loading state to go. App/kit pins in the window manifest and runbook now name this branch (sha pinned when the window is named). |
| Secret key guard | `keyLooksPrivileged` also refuses `sb_secret_…` keys (trimmed, any case), not only legacy `service_role` JWTs. |
| Loading state | `src/app/o/[org]/v/[venue]/loading.tsx`: Shell-shaped skeleton (sidebar, top line, content), mode-neutral, `data-route-loading` for the kit. |
| Mode-aware copy | Root metadata says DEMO / sample data only in the fixture build ("Venue dashboard · Snatch It" in database mode). Events eyebrow shows the venue's own name (`venue_api.venues.name`). Stale comments fixed (CSP note, package description, "eight views"). The empty events list no longer offers Create event in database mode. |
| Entry default | Database mode starts from `{kind: "denied"}`; a non-UUID route can never come back as the fixture entry. |
| Resale policy | Venue-scope policies are read for the route venue; in-force policy = event scope first, then highest version (the rule in 088 `create_native_listing` / `buy_now`). RLS hides a draft event's own policy from every client, so a draft without a visible own row shows "Resale not readable until published" instead of its venue's policy, which could be more permissive than the one the server applies. Unapproved venues' venue-wide policies are still hidden by RLS and read as absent. |
| `.vercelignore` | A CLI deploy from `venue/` never uploads `.env*`, key files, `.vercel`, `.next`, `node_modules`, `*.tsbuildinfo`, `next-env.d.ts`, kit `.runs/`, harness state, logs or `.f-handoff`. |
| Domain readiness | `POST /logout` answers 303 with a relative `Location: /login`. Confirmed host-agnostic: no absolute URL in `src/`, CSP and headers carry no host (`connect-src 'self'`, every Supabase call is server-side), sign-in `next=` is relative-only, and the `@supabase/ssr` cookies are host-only (no Domain), `Path=/`, `SameSite=Lax`. |
| Next.js | `next` 16.3.3 → 16.3.8 exact (clears the critical advisory for 16.0.0–16.3.7). |

Verification (Node 24.13.1): typecheck and lint clean; vitest 16 files / 235 tests; `next build`
in fixture mode and in database mode with the CI placeholder env. Each fix has a test that failed
on the unfixed code and a planted regression the test catches. Acceptance kit `--phase all` on a
local replay of this branch (136/136 migrations, PostgREST exposing `venue_api`, auth stub):
**138/138**; with `venueInRouteOrg` planted to always pass, the three C6 checks fail (135/138).

Hosting notes for `venue.snatchitapp.com` (code side; nothing configured):

- Env (all inlined at build, so a change needs a rebuild): `NEXT_PUBLIC_VENUE_DATA_SOURCE=database`,
  `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` (anon or `sb_publishable_…`, never a
  secret key: the app refuses one), `NEXT_PUBLIC_ENV_LABEL`. The production project still needs
  registry 159 `20261021120000_venue_api_read_views` applied and `venue_api` exposed (owner-gated).
- Sign-in is password-only through a server action, so no Supabase Auth redirect URL is used
  today. Adding reset or magic-link sign-in later would need `https://venue.snatchitapp.com/**` in
  the Auth redirect allow-list.
- Session cookies are host-only, so the venue session is never shared with `admin.snatchitapp.com`
  or `snatchitapp.com`. They are not `HttpOnly` and not `Secure` (`@supabase/ssr` defaults); setting
  `cookieOptions: { secure: true, httpOnly: true }` for the production host is a reasonable
  hardening step, to be checked against the kit's H2/H3 cookie handling first.
- No CORS is involved: the browser only talks to its own origin.

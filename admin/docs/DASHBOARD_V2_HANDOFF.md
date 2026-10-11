# Dashboard v2 — handoff for release review (Claude F)

Venue dashboard and admin operating console, redesigned to the owner-approved
concept (2026-10-09). **Not deployed, not merged to `main`.** Ready for release
review; release, deployment and cleanup are owned elsewhere (A / Codex).

## Branch tips (verified against `origin`, 2026-10-11)

| App | Branch | Tip |
|---|---|---|
| Venue | `venue/dashboard-v2` | `e0fc2e4ff604ce0ffd3895fb669f2566e9e1e8a1` |
| Admin | `admin/dashboard-v2` | `b8cdc639abbeafd6faaf66fd15e09728dfcd7c98` (+ this document) |

Both checkouts live on the SSD only:
`/Volumes/DEV-SSD/01_SNATCH_IT/repos/snatchit-venue-v2` and `…/snatchit-admin-v2`.

## What did not change

- A's payment, refund, transfer and seller-funds wording (`admin/src/lib/format.ts`
  labels), the action form (`ConfirmForm`), server actions, the ops client, the
  auth proxy, security headers and everything under `supabase/` are byte-identical
  to the redesign baseline `ce397761`. Since then `lib/` only gained `isPast`, nav
  labels/icons and repeated-key parsing in `list()`.
- Every operator change still goes through `execute_action` with the rendered
  version as expected state, a fresh idempotency key and the required audit reason.
- No migrations, no auth configuration, no production credentials, no live
  operational actions. Venue demo actions stay labelled as simulated.

## Routes

**Venue** — `/login`, `/` (redirect), `/o/[org]/v/[venue]` (Today),
`…/events`, `…/events/new` (create wizard), `…/events/[event]` (Event setup),
`…/events/[event]/door` (Check-in), `…/events/[event]/attendees` (Guest list),
`…/events/[event]/inventory` (Tickets).

**Admin** — `/login`, `/mfa`, `/denied`, `/` (Today), `/cases`, `/cases/[id]`,
`/orders`, `/orders/[paymentId]`, `/transfers/[id]` (redirects to its order),
`/money`, `/users`, `/users/[id]`, `/marketplace`, `/marketplace/[id]`,
`/reports`, `/search`, `/system`, `/actions/[id]`.

## Behaviours

- **Shared system** — one stylesheet, byte-identical in both apps: ivory canvas,
  translucent glass navigation with solid fallbacks (`@supports`,
  `prefers-reduced-transparency`), serif headings and figures, sans controls,
  grouped hairline statistics, restrained status colours, no motion under
  `prefers-reduced-motion`.
- **Venue Today** — event artwork (generated from the title), status, primary
  action, grouped figures with definitions, attention queue with area filter,
  ticket saved views, arrivals chart, coming up. Event screens share one header.
- **Admin Orders** — saved-view queues with live counts, one filter chip per
  dimension, removable "Showing" chips, order preview drawer (`?open=`): Enter
  opens with focus on its heading, Escape closes and returns focus to the row.
  Failed reads say what was lost, keep the reason for support, offer Try again.
- **Admin Cases** — queue beside a detail pane (`?open=`); saved views (Open,
  Needs an owner, Urgent, Assigned to me) with counts; filters for status,
  priority, assignee, type. Arrow keys / j k / Home / End move through the queue,
  Enter opens (focus to the case heading), Escape closes (focus back to the row;
  Escape inside a field does not close). Below `xl` the open case replaces the
  queue with "All cases". Pane and full case page render the same forms.
- **Sign-in, two-factor, denied** — one glass sheet on the canvas; wording
  unchanged. Denied distinguishes "not an operator" from "couldn't confirm".

## Verification (local production builds, synthetic data)

- Tests: venue 140/140, admin 172/172; typecheck, lint, build pass.
- Route and state sweep at 1440×900 and 390×844: every route plus loading,
  empty, error, denied and not-found states has a page heading and no
  horizontal scroll (venue 21 states, admin 21 + Cases 5 + auth 8).
- Rendered contrast (painted pixels, with positive/negative controls): 0 failures
  — venue 836, admin 4,811, Cases 834, sign-in/MFA 73 elements.
- Keyboard with real key events: skip link, logical tab order, visible focus,
  filters, popovers, Orders drawer, Cases split view.
- Accessibility tree: all interactive controls named; heading outline per page.
- Orders outage: a test-only fault proxy produced the error card and keyboard
  "Try again" recovered all rows and counts. No production debug switch.
- Sign-in/MFA via the local auth stub: sign-in, wrong password, first-time
  enrolment, wrong code, enrolment completed, next sign-in's verify step,
  malformed code, successful verify, denied. The test operator's factor was
  removed afterwards.

## Captures (SSD, not committed)

`/Volumes/DEV-SSD/01_SNATCH_IT/repos/snatchit-venue-v2/.f-handoff/`

- `compare/today-vs-concept.png` — approved concept beside built venue Today.
- `final4/` — venue Today, Check-in, Events, Guest list; admin Today, Orders, drawer.
- `final/` — Orders states: filtered, empty, error, outage, recovered, drawer.
- `sweep/` (venue) and `asweep/` (admin) — full route/state sweep.
  `asweep/admin-cases*` and `final4/admin-case*` predate the split view.
- `final6/` — Cases queue, open case (desktop and phone), empty, not found, full case.
- `final5/` — sign-in, sign-in error, MFA enrol / wrong code / verify /
  invalid code, denied.

That folder also holds the private harness configuration; do not commit or share it.

## Local previews (served from the SSD)

- Venue: http://localhost:3311/o/smp_org_wynwood/v/smp_ven_room
- Admin: http://localhost:3213/cases (local test sign-in through the auth stub)

## Remaining limitations

1. **QR code not seen with a real authenticator.** The local stub returns a
   placeholder SVG containing `#fff`; inside the data URL supabase-js builds,
   `#` starts a fragment and the image breaks. For the captures only, the test
   browser rewrote that colour in the stub's response. Console code and the stub
   are unchanged. No real authenticator scan has been performed.
2. Screen reader (VoiceOver) not exercised — no spoken-output claim. Optional
   follow-up.
3. Event artwork is generated from the title; real event photography needs new
   storage/schema work. Optional follow-up.
4. Cases with no view selected lists every case, including resolved ones (as
   before); "Open" is one click away. The old column-sort links were removed —
   `list_cases` always ordered newest first and ignored them.
5. The auto-focused MFA code field's focus ring could not be measured headless
   before a key press; keyboard-focused fields show it.
6. Long real attention titles make venue Today rows taller than in the concept.

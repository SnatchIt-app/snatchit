# Venue dashboard — slice 1 handoff: events list + event setup, read side

Branch `venue/read-adapters-slice-1` (from `venue/dashboard-preview` @ 3f0e8d3). **Implemented and
locally verified. Not deployed anywhere. Nothing applied to the shared sandbox or production.**

## What exists in the backend today (verified read-only on production, 2026-09-09)

The Phase-2 dark substrate (076–092) is live: `catalog.venue/event/event_session/resale_policy`,
`venue.ticket_type/inventory_batch/inventory_hold` exist with RLS on and column grants, all rows 0,
every feature flag `false`. Neither `catalog` nor `venue` is exposed by the Data API (PostgREST
answers 406 `PGRST106`). The predicates `kernel.has_venue_role / has_org_role / has_event_role /
has_org_role_over_event` exist. **The spec's §0.1 "nothing exists" is stale.**

| Need for this slice | Table / function | Exists | API-reachable | Authorization already there |
|---|---|---|---|---|
| Events, sessions, resale policy | `catalog.event`, `catalog.event_session`, `catalog.resale_policy` | yes (078) | no (schema not exposed) | non-draft rows public to any authenticated user; drafts to the org plane (`catalog_event_sel_org`) **and** the venue's `venue_manager` (`catalog_event_sel_venue`, 080) |
| Ticket types | `venue.ticket_type` | yes (081) | no | public-visibility rows to any authenticated user; hidden rows to org_owner/org_admin/venue_manager only |
| Inventory | `venue.inventory_batch` | yes (081) | no | `remaining` only (column grant); capacity/held/sold are **not readable by any client role** (081 E-29) |
| Counters read for staff | — | **missing** | — | needs a contracted read (spec Δ3 `venue.get_dashboard_summary` or a batch-counters RPC) |
| Capacity change | — | out of scope (write; U-8 has no RPC) | — | — |

## What this slice adds

1. **Migration `supabase/migrations/20260910120000_venue_api_read_views.sql`** (+ rollback in
   `supabase/rollbacks/`): schema `venue_api` with eight `security_invoker`, `security_barrier` views
   over the granted columns only — `venues`, `events`, `event_sessions`, `resale_policies`,
   `ticket_types`, `inventory_batches` (remaining only), plus `my_staff_roles` / `my_org_roles`
   (the caller's own grant rows, filtered to `auth.uid()`, no identity column projected). USAGE + SELECT to `authenticated`; nothing
   to `anon`; no functions, no definer, no writes. It cannot widen anything: the caller's RLS and
   column grants apply unchanged (pgTAP §D proves view rows == base-table rows per caller).
   Version is timestamp-based so it cannot collide with Claude A's numeric series; **not applied to
   sandbox or production.** Gate-2 public census unchanged.
2. **pgTAP `supabase/tests/188_venue_api_read_views.sql`** (47 assertions; 187 is the release
   candidate's `187_my_tickets_read.sql`, untouched): shape, projection, tenant isolation as four
   synthetic callers, anon refusal, no-widening, and the caller's own grant views. Fixtures are
   created inside the test transaction and rolled back.
3. **App (`venue/`)**: `NEXT_PUBLIC_VENUE_DATA_SOURCE=fixtures|database` (default fixtures).
   Database mode: cookie session via `@supabase/ssr` (`/login`, `POST /logout`), verified claims
   (`getClaims`), read adapters `dbListEvents / dbGetEvent / dbListTicketTypes / dbListBatches`
   through `.schema("venue_api")`, typed failures `auth · permission · config · not_exposed ·
   transport · error` rendered explicitly (`DataSourceError`). Fixture-only surfaces (attendees,
   door, create wizard) render `NotWiredState` in database mode — sample data is never shown there.
   The banner turns blue and reads "Database (<env>) — <host> · your own sign-in; the role switch
   changes display only, never authorization". A service-role-shaped key in the public slot is
   refused at client construction.
4. **Harness**: `venue/scripts/rehearsal-fixtures.sql` (synthetic org A/B, venues, four staff
   accounts, events incl. a draft and a hidden ticket type) for a `*rehears*` database only;
   `venue/.env.local.example-harness`.

## Local verification (2026-09-10, rehearsal DB `snatchit_venue_rehears` = clone of the admin
rehearsal DB at the 000→120 production shape + this migration; PostgREST 16 exposing
`public, kernel, ops, venue_api`; auth stub)

| Proof | Result |
|---|---|
| Authorized staff see only their permitted data | pgTAP C1–C15 + PostgREST: manager A reads A's on-sale **and draft** events, both A ticket types (public + hidden), A batches; finance B reads B's batch, **not** A's draft (`[]`), **not** A's hidden type (`[]`), **not** A's hidden-type batch. |
| Another tenant's ids cannot disclose records | PostgREST `events?event_id=eq.<A draft>` as finance B → `[] 200`; `ticket_types?ticket_type_id=eq.<A hidden>` → `[] 200`; pgTAP C11/C13/C15/C17/C19. An unreadable id is indistinguishable from a missing one; the app renders the standard denial. |
| Anonymous / unauthenticated fail closed | `anon` token and no token → `42501 permission denied for schema venue_api` (401); pgTAP A6/A8/C21. |
| Counters cannot leak | `inventory_batches?select=capacity` → `42703 column does not exist`; pgTAP B1. |
| Non-exposed schema stays closed | `Accept-Profile: catalog` → `PGRST106` (406); the adapter maps this to `not_exposed` and the UI says so. |
| Empty · loading · error · denied · not-exposed · transport · config states | Vitest SSR (`data-source-ui.test.tsx`), `?state=` switches, and the live "Sign in to continue" / denial pages (screenshots 20–21). |
| Fixture behaviour intact | Vitest 66/66 incl. the original 50; fixture mode unchanged by default. |
| No service-role credential in the browser | The package has no such variable; `keyLooksPrivileged()` refuses one; CSP `connect-src 'self'` unchanged. |
| Writes remain preview-only | Every form still posts `did=<rpc>` to the same page; database mode adds no write path (`NotWiredState` on the wizard). pgTAP A9: no INSERT/UPDATE/DELETE privilege on the views. |

Checks: `npm run typecheck && npm run lint && npm test && npm run build` green (Vitest 73); pgTAP 188 → 47/47.

## Status by stage

| Stage | Status |
|---|---|
| Implemented | yes — code, migration + rollback, pgTAP, harness fixtures, docs |
| Locally verified | yes — see table above |
| Deployed | **no** (no environment has the migration or the app in database mode) |
| Operationally verified | **no** |

## Exact sandbox prerequisites (for when Claude C's payment tests are finished)

1. Confirm the sandbox ledger contains 076–092 (do **not** reapply); apply
   `20260910120000_venue_api_read_views.sql` via the SQL editor and record its ledger row.
   Rollback file is beside it. Coordinate the ledger entry with Claude A.
2. Data API → Exposed schemas: add **`venue_api`** only (not `catalog`, not `venue`).
3. Seed one organization, one **approved** venue, one event with a public ticket type and a
   batch, and at least two staff grants (a `venue_manager` and a non-manager) through the real
   grant path; create the matching auth users. Keep an outsider account for the denial proof.
4. Run the venue app with `NEXT_PUBLIC_VENUE_DATA_SOURCE=database`, the sandbox URL/anon key,
   `NEXT_PUBLIC_ENV_LABEL=sandbox`; repeat the PostgREST proofs above with sandbox tokens.
5. Not needed for this slice: no edge function, no flag change, no service-role key, no AWS.

## Browser evidence (database mode, local harness, 2026-09-10)

- No session → events page renders **"Sign in to continue"** (screenshot 20); `/login` (21).
- Signed in as `venue.manager.a` → events list: "Rehearsal Night A (on sale) · 174 available" and
  "Rehearsal Draft A (draft) · no releases yet"; event setup shows status **On sale → next step
  Live**, resale **Face-value queue**, both ticket types incl. the hidden one, **no sold/capacity
  or gross tiles**; inventory shows the remaining-only note and "174 available / 0 available";
  attendees shows **"Attendees is not wired to the database yet"**; a random event uuid → **"You
  don't have access to this."**
- `POST /logout` → next load is "Sign in to continue" again.
- Signed in as `outsider` → events list shows **only** the on-sale event (no draft); the draft's
  url → "You don't have access to this."; inventory shows only the public type (hidden absent).

## Authorization presentation (corrected, 2026-09-10)

- **Entry policy** (spec §5: "anon and fan have no dashboard at all"): in database mode a page renders
  only for a signed-in caller holding ≥1 grant at the route's venue or org, read from
  `venue_api.my_staff_roles` / `my_org_roles`. No grant → the standard denial plus a sign-out; public
  catalog rows remain readable elsewhere (consumer surfaces) and are **not** treated as staff access.
  RLS was not changed or broadened.
- **Display principal** = widest verified grant at that scope (`derivePrincipal`, precedence
  owner › admin › manager › org_finance › venue_finance › box_office › marketing › promoter_manager
  › scanner › org_member). The `?role=` / `?state=` preview controls are ignored in database mode and
  hidden from the strip; fixture mode keeps them.
- **No write control in database mode** (`writesEnabled=false`): no status advance, no danger zone,
  no release-hold form, no Create event, no `did=` preview forms, and the "Preview: would call…"
  banner never renders. The event page states plainly that status changes are not wired.
- **Caching**: every page is `force-dynamic`; the Supabase server client passes `cache: "no-store"`
  to every fetch; the session probe is per-request (`react.cache`). Browser sequence
  manager → logout → outsider → finance B on one server showed each caller only its own result.

### Capability matrix (database mode, this slice)

| Data / control | Public (any signed-in account, no grant) | venue_finance / box office / marketing / promoter mgr / scanner | venue_manager · org_owner · org_admin |
|---|---|---|---|
| Dashboard entry at a venue | **denied** | at their own venue only | at their own venue / org |
| Non-draft events, sessions, resale policy | readable by RLS, but **no dashboard** | yes | yes |
| Draft events | no | no (RLS `catalog_event_sel_venue`: manager only) | yes |
| Public ticket types | (RLS yes) — no dashboard | yes | yes |
| Hidden ticket types | no | no | yes |
| `remaining` per batch | (RLS yes for public types) — no dashboard | own venue | own venue |
| capacity / held / sold | no client role | no client role | no client role (counters read not contracted) |
| Any write control | none | none | none (not wired in this slice) |

### Browser validation, corrected build (local harness)

- outsider → events and inventory: "You don't have access to this… holds no staff or organization
  role at this venue" + Sign out.
- finance B → venue B events: "Rehearsal Night B (announced) · 185 available", **no Create event**;
  venue A route → denied; A's draft URL → denied (cross-venue).
- manager A → events (no Create button), event setup: status note, no `did` forms, no danger zone,
  strip "Capabilities come from your grants: Venue manager"; inventory: no release form, no edit
  banner, remaining-only note.
- `POST /logout` → next load "Sign in to continue"; clearing the `sb-*` cookies (simulated expiry)
  → "Sign in to continue"; non-UUID org/venue route → denial.

**What local evidence does not prove:** the auth stub mints HS256 tokens and emulates only the
password and refresh grants, and the harness runs PostgREST directly. Hosted Supabase login, cookie
refresh on expiry, `getClaims` against the project's JWKS, and the Data API's schema exposure are
**unverified until the sandbox steps below run**.

## Still missing before the next slices

- A **staff counters read** (capacity/held/sold) — nothing contracted grants it to any client; until
  then database mode shows `remaining` only and no gross/sold tiles.
- `venue.list_activity`, `venue.get_dashboard_summary`, `kernel.get_ticket_custody_chain` do not
  exist in production. Promoter counts need `venue.promoter` reads (promoter package, dark).
- Draft edit (U-9) and capacity change (U-8) have no RPC; the wizard stays preview-only.
- Attendees/door reads (`venue.list_attendees`, `venue.lookup_attendee`, `venue.validate_ticket_online`)
  exist in production but are outside this slice.

## Shared files touched (for Claude A)

New files only:
- `supabase/migrations/20260910120000_venue_api_read_views.sql`
- `supabase/rollbacks/20260910120000_venue_api_read_views_rollback.sql`
- `supabase/tests/188_venue_api_read_views.sql` (renumbered from 187 to avoid the RC's `187_my_tickets_read.sql`; no branch carries a 188 or a `2026091*` migration as of 2026-09-10). No existing migration,
test, or CI file was modified. The `venue` CI job already runs the app checks; the migrations job
picks up the new pgTAP file automatically.

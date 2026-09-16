# Venue onboarding and My Tickets — coordinated readiness report (owner request 2026-09-16)

Assembled by A. Sections: **A** (this file, §1–§4: contracts, schema exposure, RLS/role boundaries, edge functions,
migration dependencies, owner-MFA steps, unauthorized items), **D** (§5, client onboarding flow by role — embedded verbatim
from `docs/venue-dashboard/CLIENT_ONBOARDING_READINESS_20260916.md` @ `70e19af`), **C** (§6, My Tickets end to end — merged
from `docs/product-v2/MY_TICKETS_READINESS_20260916.md` when C pushes it), then the dependency graph (§7) and milestones (§8).
One correction D's section makes to a reading of the headers alone, carried into §3: the door-session "park" (PFA-26) is
stale documentation — migration 107 un-parked it and 107 is in the production ledger (tip 120); doors are switched off by
the scanning flag and the dark edges, not impossible.
Constraint honoured throughout: **nothing here enables issuance, scanning or native ticket data**; this is a report.

Tags, two axes kept apart (D's rule): **implemented / unapplied** (code exists, not on the environment) is a different risk
from **applied / unverified** (on the environment, no acceptance evidence). Plus **sandbox-only**, **untested** (state only a
live read could establish; the read is named), **missing** (no owner, no code).

Sources: repository sweep of `release/production-gate-20260918 @ 9bef640` (file:line cited), the venue branches for the
`venue/` app and `venue_api`, `docs/release/MIGRATION_NUMBER_REGISTRY.md`, `docs/release/PHASE2_PRODUCTION_STATE_20260912.md`
(canonical production state: ledger 135 = 114 numeric rows to tip 120 + 21 legacy timestamped rows), the sandbox manifest.
No live read was made for this report except the sandbox pre-flight already recorded for the B2 window.

---

## A §1. The app ↔ venue-dashboard contracts (what each surface actually calls)

| Surface | Contract | State |
|---|---|---|
| Mobile **My Tickets** tab (`app/(tabs)/tickets.tsx`, `src/lib/tickets/api.ts:28`) | one owner-scoped RPC, `public.get_my_tickets()` (no arguments; `security definer`; `authenticated` EXECUTE only; projects `kernel.tickets` joined to `catalog.event_session/event/venue` and `venue.ticket_type`; state vocabulary `valid/used/void/expired`, resale `held/listed/in_transfer/payment_hold/disputed`, mirrored in `src/lib/tickets/ticketState.ts`) | **implemented / unapplied in production**: the migration is `20260909000000_kernel_my_tickets_read.sql`, registry row "on the candidate"; not recorded in the canonical production ledger (135 rows, numeric tip 120 + 21 legacy timestamped). Where applied it returns the defined empty set because native issuance is seeded OFF (`20260909000000:73-75`). The screen shows no detail, QR, wallet or price: "none of those contracts exist yet" (`tickets.tsx:12`) |
| Mobile marketplace tickets (transfers rail) | `public.transfers` reads and RPCs `mark_transfer_viewed`, `set_transfer_delivery_info`, `mark_transfer_sent`, `buyer_dispute_transfer`; edge `confirm-and-release` (`app/transfer/receive/[id].tsx:116-239`, `send/[id].tsx:78-130`) | **applied / live in production** (the marketplace rail). Not "My Tickets"; a separate surface |
| Mobile venue-native client module (`src/lib/venue/client.ts`) | wraps `venue.*`, `catalog.*`, `kernel.*` RPCs via `.schema('venue'|'catalog'|'kernel')` (`:87-99`): `kernel.has_venue_role`, `venue.create_ticket_type`, `create_inventory_batch`, `set_ticket_type_price`, `set_batch_capacity`, `reserve_primary_inventory`, `release_inventory_hold`, `create_primary_checkout` | **implemented / fails closed**: PostgREST exposes only `public, graphql_public, kernel`; `venue` and `catalog` are not exposed and `feature.native_issuance_enabled` is false, so every call fails closed by design (`client.ts:14-19`) |
| **Venue dashboard** (`venue/` Next.js app, venue branches only, not on the release branch) | every read is a SELECT on a `venue_api` view via `.schema("venue_api")` (`venue/src/lib/db/adapters.ts:18-24`): `venues`, `events`, `event_sessions`, `resale_policies`, `ticket_types`, `inventory_batches`, `my_staff_roles`, `my_org_roles`; **no RPC anywhere in the dashboard** | **implemented / unapplied anywhere**: `20260910120000_venue_api_read_views.sql` (D, registry: "branch `venue/read-adapters-slice-1`, not applied"); eight `security_invoker, security_barrier` views, `SELECT` to `authenticated`, nothing to `anon`, no functions, no writes. The door page renders "not wired" in database mode; PIN and device lists come from fixtures only (`venue/src/lib/data.ts:82-88`, `door/page.tsx:19-25`) |
| **Admin console** (`admin/`) | `ops.*` RPCs only via `.schema("ops").rpc` (`admin/src/lib/ops.ts:23`); no table reads; no `venue_api`, `kernel`, `venue`, `catalog` | **applied / live** (ops console live 2026-09-08 from `ab3e17f`); MFA aal2 mandatory on every route |
| **Web marketplace** (`web/`) | browse/listing/checkout/transfer/account; no tickets surface, no `venue_api`, no `ops` | live; out of scope for both features |

**Contract gaps that block a usable onboarding + My Tickets without new work (missing):** no ticket detail / QR / wallet
contract for the consumer (`tickets.tsx:12`); no dashboard write surface at all (events, ticket types, batches, PINs, devices,
manifests are RPCs in `venue.*` with no dashboard caller); no scanner client; `docs/architecture/PHASE_2_APPLE_WALLET_SPEC.md`
exists as a spec only.

## A §2. Schema exposure and the RLS / role boundary

- **PostgREST exposure (the outer wall):** `pgrst.db_schemas = public, graphql_public, kernel` in production and on the sandbox
  (`PHASE2_DEPLOYMENT_RECORD_20260902.md:23,55`; sandbox pre-flight 2026-09-16). `venue`, `catalog`, `market`, `notify`, `ops`,
  `venue_api` are **not exposed**. Exposing `venue_api` is an owner-approved dashboard setting change to
  `public, graphql_public, kernel, venue_api` (`SANDBOX_ACCEPTANCE_WINDOW_MANIFEST.md:90-104`) — **owner MFA step B4**, the last
  act of the venue window, A announces it, D executes the venue kit. Exposing `venue`/`catalog` for the mobile native module is
  a further, separate, unauthorized change.
- **Grant wall (076):** `kernel`, `venue`, `market` USAGE to `authenticated` for function EXECUTE only (`076:65-79`); `catalog`
  USAGE to `anon, authenticated` (public read plane); `notify` USAGE to `service_role` (076) and `authenticated` (092); `ops`
  USAGE to `authenticated` and `service_role`, "EXECUTE is per-function", no policies — ops tables are reachable only through
  SECURITY DEFINER functions that assert aal2 (`115:19-20, 75-105`).
- **Membership predicates (080):** `kernel.has_venue_role`, `has_event_role`, `has_org_role_over_venue`, `has_org_role_over_event`
  (`080:60-105`); every venue-plane policy resolves through them.
- **Ticket rail RLS (079/080):** `kernel.tickets`, `ticket_ownership_log`, `door_freeze_override` RLS on; `grant select on
  kernel.tickets to authenticated` (`079:735`) with policies `sel_owner`, `sel_platform` (079) and `sel_venue` (org owner/admin/
  finance, `080:411`). Function ACLs stripped then granted per function (`079:780-789`).
- **Door tables (086):** `venue.door_session` deny-all, zero policies (audit-only, `086:83`); `venue.door_pin` column-scoped
  SELECT that never includes `pin_hash` (`086:48-50`); `venue.scan` append-only (`086:152`); `holder_mix_*` RPC-read only.
- **`venue_api` (D, unapplied):** `security_invoker` views, so the base tables' RLS and column grants apply to the caller; the
  `my_*` views filter on `auth.uid()`; `inventory_batches` projects `remaining` only (081 E-29).
- **Dashboard auth model:** the venue app signs in with Supabase password auth and reads at **any assurance level — no MFA
  gate on reads** (`venue/src/lib/auth/actions.ts:15`); entry policy is route-scope + grant existence (`venue/src/lib/page.ts`),
  authorization is RLS. The admin console requires **aal2 everywhere** (`admin/src/lib/auth/session.ts:42`; server side
  `ops.assert_reader` `115:83`). Whether venue staff should be MFA-gated for writes is an open product/security decision
  (**missing** ruling); reads-only slice 1 does not need it.
- **Feature flags:** seeded OFF in `078:1522-1524` (`feature.native_issuance_enabled`, `native_scanning_enabled`,
  `native_resale_enabled`), append-only `catalog.platform_config`, NULL ⇒ false; checked server-side in
  `venue.reserve_primary_inventory`, `create_inventory_hold`, `kernel.issue_ticket_atoms`, `venue.record_scan` /
  `_record_scan_core`, `market.*` (agent sweep §3). **No client reads any flag**; gating is entirely server-side. Flips go
  through `catalog.set_platform_config` with dual control on `signing.%` (`102:460-502`) — a runtime config act, never a
  migration; **unauthorized** today on every environment.

## A §3. Edge functions on these paths and their auth models (from the headers at the pin)

| Function | Role on the path | Auth | State |
|---|---|---|---|
| `door-session` | mint/validate the loginless door session; relays `record_scan`, `reconcile_offline_scans`, manifest reads; the device id is `kernel.assert_door_session`'s return value, never the body (EA-6) | `verify_jwt: false`, Class B: a `venue.door_pin` presented once at `/mint`,`/refresh`, then `Authorization: DoorSession <id>.<secret>`; no `auth.uid()` on the path | deployed **dark** (production record: three signer/door functions deployed dark); depends on 107's bcrypt PIN KDF (in the ledger, tip 120) and 125 for manifest sync drift (**unapplied**) |
| `door-manifest` | KMS-sign the M2 manifest, parity with M1 | `verify_jwt: true`, Class A: staff JWT forwarded; one `service_role` read of `venue.get_manifest_signing_context()`; ES256 pinned; sign-after-verify | dark: `KMS_PROVIDER` unset ⇒ `kms_unconfigured` 500 |
| `credential-sign` | cacheable signed ticket credential (C33) | `verify_jwt: true`; KMS from env, default `UnconfiguredKmsSigner` | **not deployed**; "DARK code only" |
| `primary-checkout` | venue-direct primary ticket order intent | `verify_jwt: true` | implemented; **not deployed** (activation runbook `docs/phase2/PRIMARY_TICKETING_PRODUCTION_ACTIVATION_RUNBOOK.md`) |
| `connect-onboarding` | organization Stripe Connect bind (ruling F/G) | JWT + org role | implemented; deployment state **untested in records** (read: production `supabase functions list`, owner-authorized) |
| `payout-execute`, `refund-execute`, `ops-refund-execute` | money legs | Vault `service_role_key` bearer from cron / console | live for the marketplace/ops; native settlement paths gated by flags |
| `send-push`, `notify-report`, `notify-transfer` | notifications | `service_role` bearer only (`send-push:7-12`); pg_net + Vault | live in production; on the sandbox **no key** (option (b)) so nothing outbound |
| `enforce-transfer-expiry` | settlement reconciliation + expiry (134 Phase 0 arm at the pin) | `INTERNAL_CRON_SECRET` or `SUPABASE_SERVICE_ROLE_KEY` bearer (`index.ts:148-170`) | live in production (pre-134); 134 arm on the stack |

There is no `scan-*` or `venue-*` function: scanning is `door-session`'s relay. There is no `supabase/config.toml`, so
per-function `verify_jwt` lives only in the headers and the deploy command (**untested**: the deployed posture per function is
a dashboard read).

## A §4. Migration dependencies, owner-MFA steps, and what remains unauthorized

**Applied in production (canonical record 2026-09-12):** 076–120 numeric (the Phase-2 schemas, grant wall, ticket atom rail,
signing key infrastructure 083/103/106/110/111, door and scan 086/104/105/107/108/109/112/113/114, primary ticketing 093,
settlement 087/094–101, ops console 115–120) plus 21 legacy timestamped rows. Trust root live; signer/door edges dark; every
native flag false; `kernel.tickets` empty (native issuance never ran).

**Not in production, by dependency (the chain for these two features):**
1. **B2 production-gate stack** `131 → 132 → 133 → 135 → 20260916000000` — required before any production change (owner
   ruling O-5/O-3); sandbox application **in progress 2026-09-16** under the approved package; production apply needs its own
   package (L-1 read, Vault `project_url` production ceremony, AUTODEPLOY attestation).
2. **121** (`get_manifest_signing_context` strict) — deferred by the owner; door plane hardening.
3. **125** (`sync_scan_device_manifest` open/unexpired drift fix, PR #62) — sandbox-only; needed before any real scanning.
4. **`20260909000000` My Tickets read** — on the candidate; needed for the Tickets tab to read anything.
5. **`20260910120000` `venue_api` read views (D)** — applied nowhere; needed for the dashboard's database mode; plus the
   PostgREST exposure change (owner MFA B4).
6. **Timestamped 2026-09-06 payment-reliability migrations** — on the candidate; recorded as not applied in the 09-06 program
   memory; **untested in the canonical record** (the production preflight ledger read settles it).
7. **Flags** (runtime config, owner + dual control): `feature.native_issuance_enabled` before any ticket exists;
   `native_scanning_enabled` before any scan; `native_resale_enabled` before native resale — each a separate ruling.
8. **KMS signing ceremony** (two-person, `docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md`; PFA-18C owner ceremony runbook) before
   `door-manifest` / `credential-sign` can sign — production credential M5/T3 explicitly not done (production state §27).

**Steps that require the owner, with MFA where the records say so:**
| Step | Who / how | MFA | Status |
|---|---|---|---|
| Admin console access | both founders | **aal2 mandatory**, enrolled (console live 2026-09-08) | done |
| `venue_api` PostgREST exposure (sandbox, then production) | owner in the Supabase dashboard, D's venue window step B4 | **owner MFA** (dashboard) | sandbox: authorized window, not yet run; production: unauthorized |
| Any production read, even a count | owner authorizes the exact query by name; A runs | — | L-1 read pending in the preflight package |
| Production Vault `project_url` ceremony (133) | owner (dashboard) or A from env under a ruling | dashboard: owner MFA | unauthorized |
| Native flag flips | `catalog.set_platform_config`, dual control on `signing.%`; owner ruling per flag | — | unauthorized on every environment |
| KMS signing key ceremony | two-person, owner + second approver | AWS + dashboard MFA | not executed |
| Build submission (TestFlight) | C from the tag, one build authorized after B2 application | ASC | not yet |

**Unauthorized as of this report (no ruling grants them):** every production write; production reads other than the exact
L-1 query when the owner names it; `venue_api` apply or exposure outside D's authorized venue window; exposure of `venue` /
`catalog` to PostgREST; any native flag flip on any environment; KMS provisioning or signing; deployment of `door-*`,
`credential-sign`, `primary-checkout` beyond their dark state; the sandbox `service_role_key` (deferred, option (b));
any build beyond the one combined build; venue exposure; native issuance; scanning; AWS changes; new secrets.

---

## D §5. Client onboarding flow by role
_Verbatim from D's `docs/venue-dashboard/CLIENT_ONBOARDING_READINESS_20260916.md` @ `70e19af` (`review/d-release-sprint`),
headings demoted to nest here; report-only, no database read; D's tags per step._

### Client onboarding — readiness by role (D, 2026-09-16)

**Status: REPORT ONLY. Nothing is enabled, applied, deployed or authorized by this document.** Written from files
and records; **no database read of any kind was performed for it**, in production or in the sandbox. Anything whose
state can only be settled by a live read is tagged `untested` with the exact read named, never guessed.

Requested by the owner 2026-09-16 (relayed through A) as D's part of one coordinated readiness report: A covers
app ↔ dashboard contracts, schema exposure, RLS/role boundaries, edges and migration dependencies; C covers My
Tickets; this covers onboarding.

#### How to read the tags

The owner asked for four. Two of them hide a distinction that matters more than the tag itself, so this report
keeps the axes apart and every row says which it is:

| Tag | Means |
|---|---|
| **applied** | the object exists in production today (migrations 076–120) |
| **written / unapplied** | the code exists and is reviewed, but no database has it — *implementation risk is low, deployment risk is entirely open* |
| **applied / unverified** | it is in production but has never run with real data — *the code is there; nobody has seen it work* |
| **sandbox-only** | exists on `ofaidukbieeekqaboscm` and nowhere else |
| **untested** | state cannot be established from records; the required read is named |
| **missing** | no implementation and, where noted, **no owner** |

Source of truth for what is applied: `docs/release/PHASE2_PRODUCTION_STATE_20260912.md` and
`docs/release/MIGRATION_NUMBER_REGISTRY.md`. Production ledger is 135 rows, numeric tip **120**.

---

#### 0. The one-paragraph answer

**The database for venue onboarding is essentially built and live in production. Almost nothing above it is.**
Migrations 076–120 — organisations, venues, events, staff roles, inventory, orders, credential issuance, door and
scanning, settlement, promoters — are applied. On top of that sit: no internal UI to create an organisation or
approve a venue, a venue dashboard that cannot read production data because its read views are applied nowhere, an
undeployed primary checkout, an undeployed Connect onboarding, three feature flags all `false`, and zero rows of
every native kind. A venue cannot today be onboarded, sold through, paid, or scanned at the door — not because the
logic is missing, but because nothing that a human or a phone touches is connected to it.

That is a better position than it sounds: the hard, irreversible part (schema, RLS, money semantics, signing) is
done and audited. The remaining work is mostly surface and sequencing, and most of it is not blocked on us.

---

#### 1. Platform owner — the only role that can authorise

| Step | Tag | Notes |
|---|---|---|
| Authorise a production migration | **applied** (process) | Owner-gated; `AUTODEPLOY-1` means merging to `main` applies pending migrations outside CI, so no migration-bearing PR merges until the dashboard setting is visually confirmed off |
| Authorise a production read | **applied** (process) | Every production read, even a count, needs the owner's authorisation by name. This is an authorisation fact, not an MFA fact |
| Flip a feature flag | **applied / unverified** | `catalog.set_platform_config` exists and is applied; the three `feature.native_*` flags have never been flipped. Flags are runtime config, never a migration |
| Admin console MFA | **applied** | Both founders on real MFA since the 2026-09-08 go-live (`docs/admin-console/DEPLOYMENT_RECORD_2026-09-08.md` is the citation) |
| Venue `venue_api` exposure (Dashboard → Data API → Exposed schemas) | **untested** | The one owner MFA act in the venue window (`SPRINT_PLAN_20260918.md` lines 79–81, 110). Never performed |
| MFA on any surface other than the admin console | **untested** | Not established in any record. Read required: the Supabase dashboard's own MFA state per founder, which only the owner can see |
| KMS / trust-root ceremonies | **applied** | One `kernel.signing_key` row, global/active/ES256; 3 `Sign` calls ever (1 ceremony proof, 2 denied); 0 runtime `AssumeRole` |

---

#### 2. Internal operator (platform admin) — **the biggest gap**

Everything in this section exists as a database function with **no interface in front of it**. I checked: on
`release/production-gate-20260918`, `git grep -E 'venue_api|door|scan_device|manifest|signing_key|staff_role'`
across `admin/src` returns **zero hits**. The admin console is an `ops.*` money/support console and has no venue,
door, issuance or onboarding surface at all.

| Step | Tag | Notes |
|---|---|---|
| Create an organisation (`kernel.create_organization`) | **applied / unverified** · UI **missing** | 0 organisations exist |
| Approve a venue (`catalog.approve_venue`) | **applied / unverified** · UI **missing** | 0 catalog venues exist |
| Set org status, Connect ref, payout destination | **applied / unverified** · UI **missing** | 093 provides the RPCs |
| Invite an org member, change/remove a role | **applied / unverified** · UI **missing** | `invite_org_member`, `accept_org_invite`, `change_org_role`, `remove_org_member`, `revoke_org_invite`, plus a sweep cron already running |
| Grant a platform role (`grant_platform_role`) | **applied / unverified** · UI **missing** | |
| Approval requests (`kernel.approval_request`) | **applied / unverified** · UI **missing** | Table exists; nothing renders or actions it |

**Consequence, stated plainly:** onboarding a first venue today means an operator executing SQL by hand against
production, under the owner's per-action authorisation, with `kernel.admin_audit` as the only trail. That is
workable exactly once, for a design-partner venue, with the owner watching. It is not a process, and it should not
be described to a client as one. **The first genuinely missing deliverable is an internal onboarding surface**, and
it has no owner assigned today.

---

#### 3. Venue organisation admin (the client)

| Step | Tag | Notes |
|---|---|---|
| Sign in to the venue dashboard | **written / unapplied** | `venue/` app exists on `venue/*` branches only; **absent from both release branches** |
| See their org, venues, events | **written / unapplied** | Reads go exclusively through `venue_api` views — migration `20260910120000`, **applied nowhere**, and not on either release branch. This is the single biggest gap between the venue UI and the release line |
| Create an event (wizard) | **written / unapplied** | `events/new`, `EventSetup`, `EventsTable` exist; `catalog.create_event` / `create_event_session` / `publish_event` are applied |
| Ticket types, inventory batches | **written / unapplied** (UI) · **applied / unverified** (RPCs) | Dashboard reads `remaining` only; capacity/held/sold deliberately not client-readable (081 E-29) |
| Attendees list / lookup | **written / unapplied** | `venue.list_attendees`, `venue.lookup_attendee` applied; UI renders fixtures |
| Sell a ticket (primary checkout) | **missing (deployment)** | `venue.create_primary_checkout` is applied, but the `primary-checkout` edge is **written and not deployed**. **A venue cannot sell.** |
| Grant staff a role (`venue.grant_staff_role`) | **applied / unverified** · UI **missing** | 0 staff roles exist |
| Invite a colleague | **applied / unverified** · UI **missing** | |

The role model itself is real and was exercised in the acceptance kit: org-level grants and venue-level grants are
distinct, with manager and scanner roles, an outsider case, a cross-tenant case, a pending-venue case, and the
adjacent case of an org grant without a venue grant at another org's venue. That is a well-specified permission
model with no administrative UI in front of it.

---

#### 4. Door and scanning

| Step | Tag | Notes |
|---|---|---|
| Door PIN creation (`venue.create_door_pin`) | **applied / unverified** | 0 PINs exist |
| Door session minting (`venue.mint_door_session`) | **applied / unverified** | **See the correction below** — this is *not* parked |
| Scan device enrolment (`venue.scan_device`) | **applied / unverified** | 0 devices |
| Open / close a door manifest | **applied / unverified** | 0 manifests |
| Record a scan; offline reconcile | **applied / unverified** | 108 provides `_record_scan_core`, door-machine variants |
| `door-session` edge (the door's only gate) | **applied / unverified** | Deployed **dark**, v1, no JWT, **0 requests ever** |
| `door-manifest` edge (parity signing) | **applied / unverified** | Deployed dark, JWT on, 0 requests |
| `credential-sign` edge | **applied / unverified** | Deployed dark, 0 requests, 0 signatures |
| Manifest signing context STRICT (121) | **written / unapplied** | Deferred by the owner behind an explicit authorisation phrase |
| Scan-device manifest sync (125) | **written / unapplied** | Local rehearsal only; A-reviewed review-only |
| Door surface in the venue dashboard | **missing (wiring)** | `door/page.tsx` renders `NotWiredState` in database mode; pins, devices, episodes, counters and lookup all come from fixtures |
| `feature.native_scanning_enabled` | **applied**, value `false` | |

##### Correction: the door-session "park" is stale documentation, not a blocker
The `door-session` edge's header states that `venue.mint_door_session` is parked by PFA-26 and raises
`precondition_failed: door_pin_kdf_unavailable` with zero mutation on every call — i.e. that no door session can
exist. **That is no longer true.** Migration `107_door_pin_kdf_unpark.sql` un-parks both `create_door_pin` and
`mint_door_session` using an in-DB pgcrypto bcrypt KDF, keeping the frozen signatures; its body raises only
legitimate `door_session_invalid` auth failures, and **107 is applied in production** (in the 093–109 batch,
2026-09-04). 107's *own* header also still reads "DARK / unapplied / undeployed", written before it was applied.

So scanning is gated by the flag, the dark edges and the absence of data — **not** by a parked function. Two
consequences: a readiness assessment based on those headers would conclude doors are impossible when they are
merely off, and the reverse error is available too. **Finding D-ONB-1 (LOW, documentation, two files):** the
`door-session` edge header and 107's header both describe a state that has changed; a migration header that
asserts its own applied state goes stale the moment it is applied and should not be a reader's source for it. The
registry and the production-state document are.

---

#### 5. Finance

| Step | Tag | Notes |
|---|---|---|
| Org Stripe Connect onboarding | **missing (deployment)** | `connect-onboarding` edge written, **not deployed**; deliberately separate from the individual-seller path. **A venue cannot get paid.** |
| Connect state / payout destination RPCs | **applied / unverified** | 093: `set_org_connect_ref`, `set_org_payout_destination`, `get_org_connect_state`, `sync_org_connect_state`, `stage_org_connect_ref`, `authorize_org_payout_dashboard` |
| Settlement, settlement lines, obligations | **applied / unverified** | 087, 095–098, 100, 101 |
| Payout / refund execution ticks | **applied / unverified** | crons running; 0 native volume |
| Export jobs (attendee/finance exports) | **applied / unverified** | Full lifecycle incl. authorised download, revoke, purge reconciliation |
| Promoter attribution and pro-rata | **applied / unverified** | 090, 098 |
| **Tax / 1099 handling** | **missing — and no owner** | Recorded as absent since the platform audit; nothing in any migration, edge or doc. For a platform paying organisations, this is a compliance obligation, not a feature |
| Fee/【money】definitions surfaced to the client | **missing** | No venue-facing statement of fees, and `admin/docs/ANALYTICS_DATA_CONTRACT.md` is the only place money terms are defined at all |

---

#### 6. Support and recovery

| Step | Tag | Notes |
|---|---|---|
| Push-token unbind (consumer) | **written / unapplied** | Runbook exists and is reviewed (`SUPPORT_RUNBOOK_PUSH_TOKEN_UNBIND.md`), on the b2 stack |
| Support-facing challenge history | **missing** | Specced, unbuilt; D's surface, owner-gated |
| Venue staff lockout / role recovery | **missing** | No runbook. The RPCs exist; nobody has written what support does |
| Door device lost mid-event | **missing** | `revoke_door_session`, `revoke_door_pin` and override grants exist; no procedure |
| Signing-key recovery | **applied** | 111 two-person approval + execution; the only recovery path with a real ceremony behind it |
| Org member removed in error | **applied / unverified** · procedure **missing** | |

**Pattern worth naming:** every recovery path that touches money or keys has a procedure; every recovery path that
touches a *venue's operations* has none. That asymmetry will be felt on the first live event night, not before.

---

#### 7. Production readiness — the ordered blockers

Nothing below is authorised by this report; each needs its own owner decision.

1. **`venue_api` read views applied nowhere, and not on either release branch.** Until this lands the dashboard
   cannot read real data anywhere, and it is not even carried by the code line everything else ships from.
2. **No internal onboarding UI.** First-venue onboarding is hand-run SQL. Needs an owner.
3. **`primary-checkout` not deployed** — no primary sales.
4. **`connect-onboarding` not deployed** — no venue payouts.
5. **Three flags `false`, zero native rows.** Correct today; flipping them is a separate owner act per flag, and
   `feature.native_issuance_enabled` gates the credential path that the dark edges serve.
6. **121 deferred, 125 unapplied** — both sit in the scanning/manifest path.
7. **Tax/1099 absent, unowned.**
8. **No venue-side support procedures.**

##### What is genuinely strong
The schema, RLS and role model are applied, reviewed and coherent; the money rail has been through adversarial
review; the trust root is live with a monitor armed and a two-person recovery path; every native surface is off by
default with zero data, which is the correct posture for something not yet operable. The gap is breadth of
surface, not depth of foundation.

---

#### 8. What I could not establish, and the read each needs

| Question | Read required |
|---|---|
| Live PostgREST exposed-schema list | Supabase dashboard (owner) or a production read — the state doc records `public, graphql_public, kernel, ops` as of 2026-09-08 and says it did not re-read |
| Whether any surface beyond the admin console has owner MFA enrolled | Owner's own dashboard view |
| Whether any venue dashboard surface other than events/setup is live-wired in database mode | Running the app against an applied `venue_api`; cannot be settled by reading files |
| Current production values of the three flags | A production read, owner-authorised (records say `false`; that is a record, not a reading) |

---

#### 9. Evidence limits

No database was read for this report. Applied/unapplied statements come from
`PHASE2_PRODUCTION_STATE_20260912.md` and `MIGRATION_NUMBER_REGISTRY.md`; deployment statements from the
production-state reconciliation; UI statements from reading the branches named. Where a document contradicted a
migration's contents I went to the migration and said so (§4). Counts of native rows ("0 tickets", "0 staff
roles") are as recorded on 2026-09-12 and have not been re-read.


## C §6. My Tickets end to end
_Merged from C's file when pushed: creation/issuance, delivery, transfer, receiving, event-day display, offline behaviour,
notifications, scanning hand-off; the exact build and feature gates before populated Tickets can be enabled._

---

## §7. Dependency graph

```mermaid
flowchart TD
  subgraph SBX[Sandbox verification]
    B2[B2 stack on sandbox\n131,132,133,135,20260916000000\nIN PROGRESS 2026-09-16] --> BUILD[One combined preview build\nfrom candidate/2026-09-18-pin-b2]
    BUILD --> DEV[Device matrix\npush rows DEFERRED (option b)]
    VAPI[venue_api views 20260910120000\napplied nowhere] --> VEXP[PostgREST exposure + venue_api\nowner MFA step B4]
    VEXP --> VACC[Venue hosted acceptance\nD's kit, 135 checks]
    MT[20260909000000 get_my_tickets\non the candidate] --> MTS[Tickets tab reads a defined set]
    FLAGSBX[native_issuance ON on sandbox\nowner ruling, set_platform_config] --> SEED[Primary checkout or seeded atoms\nkernel.tickets > 0]
    SEED --> MTS
    M125[125 scan-device manifest sync] --> DOORSBX[Door/scan rehearsal on sandbox\nscanning flag ON sandbox only]
    VACC --> DOORSBX
  end
  subgraph PROD[Production availability]
    B2 --> PPK[Production preflight package\nL-1 read, project_url ceremony,\nAUTODEPLOY attestation]
    PPK --> PAPPLY[Production apply of the stack\nowner-gated]
    PAPPLY --> PVAPI[venue_api in production\napply + exposure, owner MFA]
    PVAPI --> ONB[First usable client onboarding\nreads-only dashboard]
    PAPPLY --> PMT[20260909000000 in production]
    PMT --> PFLAG[native_issuance flag flip\ndual control]
    PFLAG --> PMTR[My Tickets release\npopulated for native buyers]
    KMS[KMS two-person ceremony] --> DOORP[door-manifest / credential-sign live]
    DOORP --> SCANP[scanning flag flip]
    PMTR --> SCANP
  end
  classDef open fill:#fff3cd,stroke:#856404;
  classDef ip fill:#d1ecf1,stroke:#0c5460;
  class B2 ip;
  class VAPI,MT,FLAGSBX,M125,KMS,PFLAG,SCANP open;
```

## §8. Realistic milestones (estimates; each production step needs its own owner ruling)

| Milestone | What "done" means | Depends on | Estimate |
|---|---|---|---|
| **M0 — B2 sandbox application + one build** | stack applied and verified on the sandbox; build cut from the tag; device matrix run with push rows deferred | in progress today | this week |
| **M1 — Venue onboarding, sandbox verification** | `venue_api` applied on the sandbox, `venue_api` exposed (owner MFA B4), D's hosted acceptance kit green in database mode, at least one org/venue/event readable by a staff account | D's venue window authorization; owner's ~10 min in three blocks | 1 week after M0 |
| **M2 — My Tickets, sandbox verification** | `20260909000000` on the sandbox; native issuance ON **on the sandbox only** by ruling; one primary checkout (or seeded atoms) producing `kernel.tickets` rows; the Tickets tab shows a real ticket on a handset; QR/detail contract still absent | M0 build; a ruling for the sandbox flag; Connect onboarding of a test org; C's gates | 2–3 weeks after M0 |
| **M3 — First usable client onboarding, production** | stack in production; `venue_api` applied and exposed in production (owner MFA); staff sign-in; reads-only dashboard for an onboarded venue; writes (events, ticket types, PINs) still via operator SQL packs or later slices | production preflight package; production `venue_api` ruling; D's slice 2 writes for self-service | 4–6 weeks |
| **M4 — My Tickets release, production** | native issuance flag ON in production (dual control); primary checkout deployed; My Tickets populated for native buyers; delivery via the app only (no wallet, no QR until their contracts exist) | M3; primary ticketing activation runbook; C's ticket detail/QR contract | 8–10 weeks |
| **M5 — Event-day scanning** | KMS ceremony done; `door-manifest` / `credential-sign` live; 121 + 125 applied; scanning flag ON; a scanner client exists (none today) | M4; two-person ceremony; a scanner client (**missing**) | after M4, not estimated |

These are working estimates given the four-session cadence and the owner-gated steps; the sandbox path is independent of
production and can run ahead of it. Nothing in this report enables issuance, scanning or native ticket data.

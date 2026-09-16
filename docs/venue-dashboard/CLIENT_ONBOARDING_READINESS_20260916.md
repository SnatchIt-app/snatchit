# Client onboarding — readiness by role (D, 2026-09-16)

**Status: REPORT ONLY. Nothing is enabled, applied, deployed or authorized by this document.** Written from files
and records; **no database read of any kind was performed for it**, in production or in the sandbox. Anything whose
state can only be settled by a live read is tagged `untested` with the exact read named, never guessed.

Requested by the owner 2026-09-16 (relayed through A) as D's part of one coordinated readiness report: A covers
app ↔ dashboard contracts, schema exposure, RLS/role boundaries, edges and migration dependencies; C covers My
Tickets; this covers onboarding.

## How to read the tags

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

## 0. The one-paragraph answer

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

## 1. Platform owner — the only role that can authorise

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

## 2. Internal operator (platform admin) — **the biggest gap**

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

## 3. Venue organisation admin (the client)

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

## 4. Door and scanning

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

### Correction: the door-session "park" is stale documentation, not a blocker
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

## 5. Finance

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

## 6. Support and recovery

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

## 7. Production readiness — the ordered blockers

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

### What is genuinely strong
The schema, RLS and role model are applied, reviewed and coherent; the money rail has been through adversarial
review; the trust root is live with a monitor armed and a two-person recovery path; every native surface is off by
default with zero data, which is the correct posture for something not yet operable. The gap is breadth of
surface, not depth of foundation.

---

## 8. What I could not establish, and the read each needs

| Question | Read required |
|---|---|
| Live PostgREST exposed-schema list | Supabase dashboard (owner) or a production read — the state doc records `public, graphql_public, kernel, ops` as of 2026-09-08 and says it did not re-read |
| Whether any surface beyond the admin console has owner MFA enrolled | Owner's own dashboard view |
| Whether any venue dashboard surface other than events/setup is live-wired in database mode | Running the app against an applied `venue_api`; cannot be settled by reading files |
| Current production values of the three flags | A production read, owner-authorised (records say `false`; that is a record, not a reading) |

---

## 9. Evidence limits

No database was read for this report. Applied/unapplied statements come from
`PHASE2_PRODUCTION_STATE_20260912.md` and `MIGRATION_NUMBER_REGISTRY.md`; deployment statements from the
production-state reconciliation; UI statements from reading the branches named. Where a document contradicted a
migration's contents I went to the migration and said so (§4). Counts of native rows ("0 tickets", "0 staff
roles") are as recorded on 2026-09-12 and have not been re-read.

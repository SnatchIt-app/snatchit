# D's critical-path inputs — venue acceptance, client onboarding, event-day scanning (2026-09-17)

**Report only. Nothing here is authorized, scheduled or started.** Companion to
`CLIENT_ONBOARDING_READINESS_20260916.md`. Written from records and from readings I took myself; each claim says
which. No production read was performed.

---

## 1. The environment question, resolved

The report's "trust root live / door edges dark" statements are **production-only facts**. They are true there and
false in both other environments. Stated per environment with the source:

| | Trust root | Door / credential edges | Native door data |
|---|---|---|---|
| **Production** | **LIVE** — `kernel.signing_key` one row `…b0`, global/active/**ES256**; KMS D4 `ECC_NIST_P256` enabled, `Sign` total 3 (1 ceremony proof, 2 denied), **0 runtime `AssumeRole`**; monitor armed, cron `23 5 * * *`, 0 alert rows | **DEPLOYED DARK** — `credential-sign` (JWT), `door-manifest` (JWT), `door-session` (no JWT), v1 from `562fda9`; **0 requests, 0 signatures ever** | zero rows of every kind (a live inactivity control, not an accident) |
| **Sandbox** `ofaidukbieeekqaboscm` | **ABSENT** — `kernel.signing_key` **0**, `kernel.tickets` **0** (my own reads, V0 04:35:37Z and close 04:57:13Z, 2026-09-16) | **NOT DEPLOYED** — the project has **nine** functions and none is a door/credential one (A's `functions list`, read during the B2 window: the four in scope plus `confirm-payment`, `confirm-and-release`, `delete-account`, `notify-report`, `create-connect-account`) | not established; needs a catalog read, and the window is closed |
| **Local harness** | **ABSENT** — `signing_key` 0 (my read, `d_cand_tap_rehears` at the pin) | **none exist** — the harness is psql-only, there is no edge runtime at all | `door_pin` 0, `scan_device` 0, `door_session` 0 |

Sources: production — `docs/release/PHASE2_PRODUCTION_STATE_20260912.md` (C2/C3/C5/C6 records). Sandbox — my B2
witness record and A's window reads. Local — read just now.

**Caveat on "applied" for the sandbox.** The sandbox ledger lists `123,124,125,127,128,129,130` above 109 and not
`110–120`, so it was not built row-by-row from the same chain as production. Do **not** infer per-migration
sandbox state from ledger rows; where it matters, read the catalog.

**And the separate stale-text finding stands (D-ONB-1).** The `door-session` edge header says
`venue.mint_door_session` is parked and raises `door_pin_kdf_unavailable` with zero mutation. Migration
`107_door_pin_kdf_unpark.sql` **un-parks** both `create_door_pin` and `mint_door_session`, and 107 is applied in
production (093–109 batch, 2026-09-04). 107's own header also still reads "DARK / unapplied / undeployed", written
before it was applied. So in production **the function works and the edge is dark** — scanning is gated by the
flag, the dark edges and the absence of data, *not* by a parked function. A readiness judgement taken from those
two headers reaches the opposite conclusion. A migration header must never be a reader's source for its own
applied state; the registry and the production-state document are.

---

## 2. Venue read-only acceptance — the owner's MFA moment and duration

Everything needed exists and is rehearsed; this track needs a **window**, not work.

**The owner is needed at two moments, not one.** Announcing only the MFA step leaves the second as a surprise:

| When | What the owner does | Owner time |
|---|---|---|
| At the start | Name the window; confirm the app build | 2 min |
| **B4 — after kit step 2 (`verify-apply`), before step 4 (`verify-exposure`)** | Supabase dashboard → project `ofaidukbieeekqaboscm` → Integrations → Data API → Exposed schemas → **add `venue_api` only**, Save. Screenshot before (E1) and after (E2), then tell D "exposed" | **3 min** |
| After V6 | Review three evidence screenshots (manager events, finance denied, outsider denied) | 5 min |
| If anything fails | Remove `venue_api` from the same list, Save, screenshot E6 | 1 min |

**Owner total ≈ 10 min. Automated wall time ≈ 8 min. End-to-end ≈ 25–30 min** including setup and the read-backs
A and I take either side of the apply. The MFA step is the only one nobody else can perform, and it is the
window's hinge: nothing after it runs until the owner says "exposed".

**Authorization, as A holds it and I am not assuming past:** authorized in principle as an unrun phase of O-1, but
not self-starting — it opens on the owner's explicit word after A announces the moment.

**One thing the owner should know before spending the window:** `20260910120000_venue_api_read_views.sql` is on
ten branches and **neither release branch**. Acceptance would prove the slice works; it would not put it on the
line everything else ships from. That merge is a separate, small task with a real owner (A) and it should be
sequenced, or the acceptance evidence ages against a branch nothing ships from.

---

## 3. Client onboarding — the operator gap first

**The gap, stated plainly:** every onboarding RPC is applied in production and **none has a user interface**.
`git grep -E 'venue_api|door|scan_device|manifest|signing_key|staff_role'` over `admin/src` on
`release/production-gate-20260918` returns **zero hits**.

| Task | What exists | What is missing | Owner | Depends on | Parallel? |
|---|---|---|---|---|---|
| Create organisation | `kernel.create_organization` (077) applied | the screen | **unassigned** | — | yes |
| Approve venue | `catalog.approve_venue` (078) applied | the screen | **unassigned** | — | yes |
| Invite / change / remove org member | full RPC set + an invite-expiry cron already running | the screens | **unassigned** | — | yes |
| Grant / revoke venue staff role | `venue.grant_staff_role` (080) applied | the screen | **unassigned** | — | yes |
| Approval requests | `kernel.approval_request` table | nothing renders or actions it | **unassigned** | — | yes |
| Org Connect onboarding | `connect-onboarding` edge **written** | **deployment** | A | owner authorization | yes |
| Primary sales | `venue.create_primary_checkout` applied | `primary-checkout` edge **not deployed** | A | owner authorization | yes |

**Effort — and I will not quote a number I have not scoped.** The smallest useful operator surface is four screens
(organisations list + create, venue approve, staff grants, one audit read) on a console that already has auth,
MFA, layout and `ops.*` reads — so the shell is free and the work is forms plus the four-file grant discipline per
new read. I would put a day into scoping it against the real RPC signatures before giving the owner a figure;
quoting one now would be a guess dressed as an estimate. **What the owner can decide today is the question
underneath it:** whether the first venue is onboarded by hand under per-action authorization (workable exactly
once, with the owner watching, `kernel.admin_audit` as the only trail) or whether the surface is built first.
That decision, not the build, is on the critical path.

**Suggested owner: me.** The admin console is my surface, the analytics contract discipline already applies to it,
and I have the four-file rule in hand.

---

## 4. Event-day scanning — and the dependency that reorders the whole plan

| Task | What exists | What is missing | Owner | Depends on |
|---|---|---|---|---|
| Door/scan schema | 086 + 104–109, 112–114 applied in production | — | — | — |
| PIN + door session | unparked by 107, applied | — | — | — |
| Manifest signing STRICT (121) | written, PR #58 | **not applied**, deferred behind an authorization phrase | B | owner |
| Scan-device manifest sync (125) | written, rehearsed, A-reviewed review-only | **not applied** | B | owner; 121 first |
| Dashboard door surface | screens exist | **renders `NotWiredState` in database mode**; pins, devices, episodes, counters, lookup all come from fixtures | **D** | `venue_api` (or a door read slice) |
| Scanning flag | `feature.native_scanning_enabled` applied, **false** | the flip | owner | everything above |
| Device enrolment, PINs, manifests | RPCs applied | zero data anywhere; creating it in production is currently out of bounds | owner | flag + data decision |

**The dependency that matters most, and the reason this is not an independent track:** scanning scans *tickets*.
Tickets come from `kernel.issue_ticket_atoms`, which runs on `payment_intent.succeeded` for a **primary** sale —
and `primary-checkout` is **not deployed**, with `feature.native_issuance_enabled` **false**. So event-day
scanning cannot be demonstrated end to end until the primary-sales path exists. **Sequence it behind primary
sales, not beside it.** The parts that *can* run in parallel are the dashboard door wiring (mine, needs a read
slice) and B's 121/125 decisions.

A's note stands and I have not estimated against it: the My Tickets sandbox fixture is not "one row" —
`kernel.tickets.signing_key_id` is NOT NULL with an FK to `kernel.signing_key` (084) and a custody trigger wants an
ownership-log tail, while `kernel.signing_key` writes are excluded by the manifest and by the owner. A is putting
the real shape to the owner.

---

## 5. What I would tell the owner in one line each

1. **Venue acceptance** is a 30-minute window, not a project — but land `venue_api` on the release line or the
   evidence ages against a branch nothing ships from.
2. **The operator surface is the real gap in onboarding**, it has no owner, and the decision to make today is
   hand-run-once versus build-first.
3. **Scanning is downstream of primary sales**, so its position on the critical path is set by
   `primary-checkout` and the issuance flag, not by 121 or 125.

# Task-level critical path (A, 2026-09-17; owner request) — five tracks, sandbox verification separated from production

Legend: **exists** = code/records present at the build tag `candidate/2026-09-18-build-b2` (`aad5f75`) or applied where
stated · **missing** = no code and/or no owner · **owner** = the session that does it (A/B/C/D) or **Owner** (a ruling, an
MFA act, a ceremony) · effort in working days for one session, review included, as each session estimated it (C's lane is
C's own estimate of 2026-09-17; B's and D's lanes are marked *(pending B/D)* until their inputs land and are merged verbatim)
· **∥** = can run in parallel with the row above. Nothing here authorizes a production change, a build, a flag, a secret
or a notification.

## Track 1 — Marketplace release readiness (production)

State: the candidate is on the sandbox at ledger 141 with the four edges (manifest §11, D PASS); the combined build is being
cut from `aad5f75`; production is untouched at ledger 135.

| # | Task | Exists | Missing | Owner | Depends on | Effort | ∥ |
|---|---|---|---|---|---|---|---|
| 1.1 | Combined build cut from the tag; installation link to the owner | **SUBMITTED 2026-09-17** by C from the tag in a clean worktree (`aad5f75`, 0 dirty): EAS iOS preview/internal build `dcbf20e0-76dd-4b18-a48a-20c203ba0175`, expected build 18; page https://expo.dev/accounts/jdt_inc/projects/snatchit/builds/dcbf20e0-76dd-4b18-a48a-20c203ba0175 (the installation link when it finishes) | the finished artifact | C | — | done | — |
| 1.2 | Handset session 2 on the combined build: DV-AUTH-1 (sign-in hang), DV-611C-2 (registration visibility), DV-S1/S2 (seller keyboard), row-11 residue (large-text banner), DV-ST1..ST4 (offline/error/empty/no-match, F-OFF-1) | scripts, read-backs | the run | C (guide), Owner (handset ≈ 2.5–3 h), A (4 read-backs + 1 staged read), D (witness) | 1.1 | 0.5 d C | — |
| 1.3 | Carried forward at their real status (not upgraded): two-session K-2 case **untested** outside D's harness (needs a second iPhone); row 18 **deferred** (needs push delivery); A11Y-1 VoiceOver **untested**; every push-delivery row **deferred** (option (b)) | records | evidence | C/A | Owner: key deferral, second device, VoiceOver opt-in | — | — |
| 1.4 | Two-second registration rejection window — **assessed by C + D 2026-09-17 (source, at the tag): understandable and recoverable, no silent failure found in source.** Reframing: `push_session_predates_epoch` bars every session older than the epoch, so this experience is met on every password change / sign-out-everywhere, not only in the 2 s race. Register path: the 42501 is classified `session_stale`, persisted and published to Settings **before** the local sign-out; the user lands on the login screen with "You were signed out on this device. Sign in again to keep notifications on."; a post-epoch session registers normally (tests + row 17). **F-2S-1 (LOW, copy):** the 135 challenge path does not route into the stale handler, so the failed-challenge banner shows the same "signed out" sentence while the user is still signed in and the app works; D recommends neutral copy on the challenge banner (not forcing re-auth from a push flow; that would be a behaviour change needing its own review); owner's call, not in the tag. One constructible quiet case recorded, not dismissed: a network drop in the sub-second between refusal and local sign-out leaves the user signed in until the next refusal, Settings still showing the remedy. **Device-untested:** C proposes DV-131-1 (register path, combined build) and DV-131-2 (challenge path, deferred with the key) — the difference between "found none" and "proven none" | C + D | done (source); DV-131-1 in 1.2 | — |
| 1.5 | Production preflight package: exact L-1 read (owner authorizes by name), ledger 135/tip 120 read, `AUTODEPLOY-VERIFIED-OFF` attestation, per-function `verify_jwt` read (D's ask), Vault `project_url` production ceremony (owner), 133 drift counts 4/5 | packet §2 | the owner's read authorizations; the ceremony | A (package), Owner (reads, ceremony) | 1.2 acceptance closed | 1 d A | ∥ 1.2 |
| 1.6 | Production apply of the stack `121? (deferred) → 123 → 124 → 125 → 126 → 127 → 128 → 129 → 130 → 131 → 132 → 133 → 135 → 20260916000000` + edges, serialized, D witnessing; 126 validated by CI/harness only on the sandbox | packages, rollbacks, D's rehearsals | the ruling | A, D witness, Owner | 1.5, Stripe `payment_intent.canceled` subscription (Owner) | 0.5 d window + 24 h observation | — |
| 1.7 | B's residuals: N-132-2 (availability, disclosed), fresh-mint concurrency dispositions, PFA-32 | records | *(pending B)* | B | — | *(pending B)* | ∥ |
| 1.8 | Notification P0/P1 fixes that ship with the release (backlog `NOTIFICATION_GAPS_BACKLOG_20260917.md` rows 1–3, 6–8): preferences decision, rebound notice on next sign-in, payout-destination drain arm, tap routing, idempotency, dedupe | inventory | the work | A/B/C per row | P3 decisions (Owner) | 6–8 d spread across A/B/C | ∥ 1.5 |

**Critical path to production:** 1.1 → 1.2 → 1.5 → 1.6. **Estimate:** build + session 2 this week; preflight package ready
in parallel; production window on the owner's ruling the week after, if session 2 raises no blocking finding.

## Track 2 — Venue read-only acceptance (sandbox)

State: authorized in principle by O-1 (2026-09-15) as a phase of the sandbox window, never run; the B2 ruling excluded
venue exposure from the B2 window only; the owner's 2026-09-17 instruction keeps it "at the agreed point". **It opens only
on the owner's explicit word after A announces the MFA moment; the MFA act (B4) is the owner's own.**

| # | Task | Exists | Missing | Owner | Depends on | Effort | ∥ |
|---|---|---|---|---|---|---|---|
| 2.1 | Kit pin re-verified against `9bef640` + ledger 141 (the venue migration `20260910120000` sorts after every numbered version and after `20260909…`, before `20260916000000`? — **no**: `20260910120000` < `20260916000000`, so on a ledger that already holds `20260916000000` the venue migration is out of `LC_ALL=C` order; D confirms the kit's ledger-row handling for this case) | kit, manifest | the order check | D | — | 0.5 d | — |
| 2.0 | **`20260910120000_venue_api_read_views.sql` is on ten branches and neither release branch** (D): acceptance proves the slice, not that it ships. A integrates it onto the production-gate stack as its own integration after session 2 (a `supabase/` change → new pin, CI, D's gate), so the evidence does not age against a branch nothing ships from | migration on D's branches | the integration | A | 1.2 | 0.5 d | ∥ 2.1 |
| 2.2 | Owner authorizes the venue window; A announces **two owner moments** (D): B4 after kit step 2 `verify-apply` and before step 4 `verify-exposure` — dashboard → Integrations → Data API → Exposed schemas → add `venue_api` only → Save, screenshots before/after, say "exposed" (**3 min**); after V6, review three evidence screenshots: manager events, finance denied, outsider denied (**5 min**); plus 2 min at the start to name the window and confirm the build. **Owner ≈ 10 min; automated ≈ 8 min; end-to-end 25–30 min** with A's read-backs either side. Nothing after B4 runs until the owner says so | D's plan | the ruling | Owner | 2.1 | — | — |
| 2.3 | B1–B3: D applies `venue_api` read views via the kit, A records census before/after (ledger 141 → 142) | migration, kit | — | D (apply), A (witness) | 2.2 | 0.25 d | — |
| 2.4 | **B4 owner MFA**: expose `venue_api` in the dashboard (`public, graphql_public, kernel, venue_api`), `db_pre_request` unchanged, three screenshots | runbook | the act | Owner (≈ 10 min in three blocks, D's plan) | 2.3 | — | — |
| 2.5 | B5–B6: kit api + browser phases (135 checks, C6/C7), cleanup by exact id, A re-verifies counts | kit | the run | D, A | 2.4 | 0.5 d | — |
| 2.6 | D's inputs on what the acceptance proves and does not (reads only; no writes, no door) | *(pending D)* | | D | | | |

**Estimate:** one working day of D once the owner opens it; owner time ≈ 10 min. **Separate from production:** production
`venue_api` apply + exposure is its own ruling (Track 3).

## Track 3 — Usable client onboarding

State: reads-only dashboard exists on the venue branches; `venue_api` applied nowhere; no dashboard write path; the operator
role is the biggest gap (D §5); several finance steps have no owner (tax/1099: **missing**).

| # | Task | Exists | Missing | Owner | Depends on | Effort | ∥ |
|---|---|---|---|---|---|---|---|
| 3.1 | Track 2 complete on the sandbox | — | — | D | 2.x | — | — |
| 3.2 | Production `venue_api` apply + exposure (owner MFA in production) | migration | the ruling; production window | Owner, D, A | 1.6 (stack in production) | 0.5 d | — |
| 3.3 | **Operator (platform admin) onboarding surface — the real onboarding blocker, and it has no owner** (D): every onboarding RPC is applied in production and none has a UI (`admin/src` has zero hits for venue/door/staff/manifest). **The decision on the critical path is not the build: hand-run the first venue under per-action authorization, or build the surface first.** Smallest useful surface: four screens on the console that already has auth, MFA, layout and `ops.*` reads. D will not quote effort unscoped: **one day against the real RPC signatures first, then a number**; suggested owner D | `ops.*` foundation; SQL packs; RPCs | the ruling on hand-run vs build; the scoping day | Owner (decision), D (scoping, then build) | 3.2 | 1 d scoping → estimate | ∥ 3.2 |
| 3.4 | Venue admin self-service writes (events, sessions, ticket types, batches): dashboard callers for the existing `venue.*` RPCs | RPCs (081/082) | dashboard write slice + `venue_api` exposure of the RPC path or public wrappers (A's contract) | D (UI), A (contract) | 3.2 | *(pending D)* | ∥ 3.3 |
| 3.5 | Staff MFA policy for writes (reads need none): decision | admin console pattern | ruling | Owner | — | — | ∥ |
| 3.6 | Finance responsibilities with no owner: tax/1099, payout-destination change notice (backlog row 3) | Connect onboarding exists | owner assignment | Owner | — | — | ∥ |
| 3.7 | Support recovery runbooks (push unbind exists; org/venue recovery missing) | runbook | *(pending D)* | D/B | | | ∥ |

**Estimate (substantiated by the rows above):** reads-only production onboarding = 1.6 + 3.2 ≈ **4–6 weeks** from today;
self-service writes (3.3–3.4) add D's pending estimate, likely several weeks more; 3.5–3.6 are rulings, not work.

## Track 4 — Populated My Tickets

State: the tab and the read contract exist; `20260909000000` is on the sandbox (ledger 141) and not in production; the only
legitimate producer of a ticket row is the dark native issuance chain. C's lane estimates (2026-09-17):

| # | Task | Exists | Missing | Owner | Depends on | Effort | ∥ |
|---|---|---|---|---|---|---|---|
| 4.1 | **Sandbox fixture** for the DV buyer — **not one row**: org, venue, event, session, ticket type, **a signing-key row** (`kernel.tickets.signing_key_id` is NOT NULL with an FK; the insert guard demands a global active ES256 key with a well-formed KMS ARN and a real P-256 SPKI PEM), the ticket, and an ownership-log tail (custody trigger at commit) — see `MY_TICKETS_SANDBOX_FIXTURE_PROPOSAL.md` | tables | the owner's ruling lifting two sandbox exclusions (`kernel.tickets`, `kernel.signing_key` writes); B's review of the key row | Owner, A (SQL, rehearsal, cleanup), B (review), D (witness) | ruling | 0.5 d A + 0.25 d B | — |
| 4.2 | CFT-801 populated Tickets device rows (list, Upcoming/Past, quantity, ownership × fulfillment, large text, VoiceOver) on any build carrying the tab | tab | the run | C (0.5 d guiding), Owner (~1 h) | 4.1 | 0.5 d | — |
| 4.3 | CFT-811 ticket detail | — | detail read contract (A 1–2 d incl. pgTAP + grant manifest) then C 2–3 d | A → C | 4.2 | 3–5 d | ∥ 4.2 |
| 4.4 | CFT-813 offline cache of the list | — | cache/TTL contract (A 1 d) then C 2–3 d; token half waits on 4.6 | A → C | 4.2 | 3–4 d | ∥ 4.3 |
| 4.5 | CFT-816 `ticket_ready` / `ownership_changed` push handling + routing | templates (Plane C) | a producer and the dispatcher un-parked (server, unscheduled) | A/B → C | backlog P3-2 | 1 d C + server | ∥ |
| 4.6 | CFT-812 Entry Pass / QR | — | `credential-sign` live + credential contract — **ceremony NO-GO**; QR renderer decision (Owner) | B → A → C | Track 5 | 3–4 d C | — |
| 4.7 | CFT-814 Apple Wallet; CFT-815 transfer/sell from a ticket | specs | wallet minting parked; `create_p2p_transfer` raises until the resale TTL and `native_resale_enabled` are decided | Owner rulings | — | not schedulable | — |
| 4.8 | **Production**: `20260909000000` owner-gated apply; native issuance flag flip (dual control); `primary-checkout` deployed; a primary-checkout client that does not exist; `venue`/`catalog` exposure or public wrappers (A's contract) | RPCs, edge code | the whole chain and its rulings | Owner, A, B, C | 1.6 | *(pending B for the chain)* + C's 4.3–4.4 | — |

**Estimate (substantiated):** populated Tickets **on the sandbox** = 4.1 (0.75 d after the ruling) + 4.2 (0.5 d) → days, not
weeks, if the owner lifts the two exclusions for a recorded fixture; **in production** = Track 1 done + 4.8's chain, of which
the flag flip, the checkout edge and a checkout client are unscheduled → **8–10 weeks** remains the honest figure and is
gated by rulings, not effort.

## Track 5 — Event-day scanning

State by environment (resolved by D from records, 2026-09-17; A concurs from the sandbox reads): **production** trust root live (KMS D4), signer/door functions deployed dark,
`kernel.signing_key` 1 active global key, flags false; **sandbox** no signing key (0), door/sign functions **not deployed** (the
sandbox `functions list` of 2026-09-16 shows nine functions, none of `door-session`, `door-manifest`, `credential-sign`,
`primary-checkout`), flags false; **local** dark code, `KMS_PROVIDER` unset. The door-session "park" text (PFA-26) is stale:
107 un-parked it and 107 is in production (tip 120); doors are switched off, not impossible (D §5).

| # | Task | Exists | Missing | Owner | Depends on | Effort | ∥ |
|---|---|---|---|---|---|---|---|
| 5.1 | 121 (manifest signing context strict) applied | migration, PR #58 | ruling | Owner, A | 1.6 | in the stack window | — |
| 5.2 | 125 (scan-device manifest sync drift) applied | on the sandbox | production ruling | Owner, A | 1.6 | in the stack window | — |
| 5.3 | KMS two-person signing ceremony (production credential M5/T3) | runbooks, trust root | the ceremony | Owner + second approver, B | — | *(pending B)* | ∥ |
| 5.4 | `door-manifest` / `credential-sign` from dark to live; `door-session` live | dark deploys | KMS provider configured; rulings | B | 5.3 | *(pending B)* | — |
| 5.5 | Scanner client | **none** | a client (web or native) using `door-session` (PIN → DoorSession token) | Owner decision; C or D | 5.4 contract | **missing, not estimated** | ∥ 5.3 |
| 5.6 | Scanning flag flip (dual control) + first real scan on the sandbox, then production | flag seeded false | rulings | Owner | 5.4, 5.5, Track 4 | — | — |

**Sequencing (D):** scanning is downstream of primary sales, not beside it — tickets come from `issue_ticket_atoms` on a primary `payment_intent.succeeded`, `primary-checkout` is not deployed and the issuance flag is false, so event-day scanning cannot be shown end to end until the primary path exists. Parallel now: D's dashboard door wiring (needs a read slice) and B's 121/125 decisions. **Caveat on sandbox state (D):** the sandbox ledger lists 123,124,125,127–130 above 109 and not 110–120, so it was not built row by row from production's chain; per-migration sandbox state is read from the catalog, never inferred from ledger rows. **Estimate:** after Track 4; not estimable until 5.5 has an owner and a shape. D's full inputs: `docs/venue-dashboard/CRITICAL_PATH_INPUTS_D_20260917.md` @ `a8cd818`.

## Standing item — required signup gender answer + analytics (must not disappear)

| Item | Owner | Status |
|---|---|---|
| CFT-901 data contract, privacy, schema, analytics review (A's answers owed): separate owner-only table; RLS owner-only; no admin row-level read; one aggregate function with small-group suppression; SECURITY DEFINER RPC write path setting consent + timestamps; "cleared" vs "undisclosed" distinguishable in the row, identical in every aggregate; retention = life of account; hard delete with the account; in the export; consent withdrawal stops inclusion forward | A | interim positions given 2026-09-16; full document owed with this critical path (next) |
| CFT-902–908 client: required answer with an equal-weight "Prefer not to say", inclusive options + optional self-description, the "why", explicit analytics consent, editable/clearable, private by default, never inferred | C | proposal `GENDER_PROFILE_DATA_PROPOSAL_C.md` written; waits on CFT-901 |
| Analytics dimensions and suppression thresholds | D | asked 2026-09-16 |
| Outstanding owner decisions | Owner | required vs skippable screen (App Store 5.1.1 data minimisation); which aggregates; retention text; whether any use outside analytics is ever approved (default: none) |
| Constraint | all | no migration or production change authorized; nothing in discovery, bidding, checkout, transfers or seller decisions |

## Parallelism summary
Track 1's session 2 and preflight package run together; Track 2 runs in D's lane on the owner's word independent of Track 1;
Track 4's sandbox fixture depends only on a ruling and A/B time; Tracks 3 and 5 are ruling-gated and start after Track 1's
production window. B's and D's lane estimates are merged verbatim when received; nothing above is a commitment to a date.

# Venue Authorization Model — Adversarial Security Audit

**Scope:** the venue-plane authorization model as it would behave **if primary ticketing were activated**
(`feature.native_issuance_enabled = true`, `feature.native_scanning_enabled = true`, and the venue dashboard
reaching Postgres directly).
**Corpus read:** migrations `076`–`092` (18,561 lines, all read in the relevant parts), plus
`PHASE_2_RLS_PERMISSION_SPEC.md`, `PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md`, `PHASE_2_CRM_EXPORT_SPEC.md`,
`_governance/DELETION_STATE_MACHINE_SPEC.md`.
**Branch:** `feature/venue-native-and-product-v2`. **Migrations 076–092 are IMMUTABLE** — every fix below is
expressed as a `093+` follow-up, a grant/RLS change, an operational config decision, or an owner ruling.
**Method:** read-only. No SQL was executed; every claim carries `file:line` evidence.

---

## 1. Executive summary

The venue authorization model is, on the whole, **unusually well built**. The four predicates in `080` are
`SECURITY DEFINER` with `set search_path = ''`, resolve their scope from *server-read* rows rather than
caller-supplied claims, and fail closed on every degenerate input. Every one of the ~50 `venue.*` / `catalog.*`
routines carrying `GRANT EXECUTE TO authenticated` re-derives the venue/org from the object id it was handed
and then tests authority **against the resolved scope** — there is no verb that trusts a caller-supplied
`venue_id`/`org_id` as its authorization subject. The one place a scope pair *could* have been forged
(`venue.open_settlement(p_org_id, p_venue_id, …)`) explicitly re-binds venue→org before writing
(`087:253-260`). Money verbs exclude every venue label by construction (`085:907-919`). The entire
buyer-PII surface (`list_attendees`, `lookup_attendee`, `build_export_rows`) is **parked fail-closed** under
PFA-28 and emits zero customer data (`087:1400-1402`, `087:1439-1441`, `087:910-919`). The canonical six
venue labels are correct everywhere; **`venue_door` and `venue_promoter` appear nowhere in the schema** — the
only occurrences are `080:143-149`, which *reject* them by name as superseded labels. That is a clean result.

The defects that do exist cluster in three places:

1. **A tenancy boundary the corpus itself already identified and then applied inconsistently.** `087` binds
   every venue role to the venue's *current operator* (the E-76 conjunct, `087:650-659`, `087:1369-1374`,
   `087:1299`). `081`, `082` and `086` do not. Because `catalog.update_venue` can repoint
   `catalog.venue.org_id` (`078:688-704`) while `catalog.event.org_id` stays stamped at creation
   (`078:877-881`), and because *nothing* clears `venue.staff_role` on that transfer, an operatorship change
   leaves one tenant's staff holding live read **and write** authority over another tenant's events. This is
   the single P0.
2. **The comp path is the fraud surface with the weakest controls.** `venue.allocate_comp` and
   `venue.issue_comp` are single-actor, `venue_manager`-only, carry **no AAL2 step-up and no per-staff cap**
   despite `078` seeding `comp.per_staff_step_up_max_units` with a documented "absent ⇒ every comp needs
   step-up" fail-to-safe (`078:1561-1563`) and despite RLS §11.1a requiring C39 gating on both verbs. One
   compromised manager session mints unlimited free live tickets.
3. **One verb with literally zero in-body authorization**, `venue.cancel_pending_order` (`082:478-523`),
   currently walled only by a `service_role`-only grant whose *delivery mechanism is an open owner decision*
   (PFA-15, `082:469-476`) — and one of the four candidate resolutions the migration itself lists is "an
   authenticated edge-caller".

**Nothing here is remotely exploitable today.** Native issuance and scanning are dark, and `venue`/`catalog`
are not PostgREST-exposed. Those two facts are the only reason the P1s are not P0s. Activation removes both.

**PostgREST verdict:** exposing `venue` and `catalog` is **conditionally safe** — see §6.

---

## 2. Findings

| ID | SEV | Title | Evidence (file:line) | Attack scenario | Recommended fix | Class | Blocks activation |
|---|---|---|---|---|---|---|---|
| **V-1** | **P0** | Operatorship transfer does not re-scope venue authority: stale staff keep write access to the new tenant, and the new tenant gains write access to the old tenant's events | `078:688-704` (platform_admin repoints `catalog.venue.org_id`) · `078:877-881` (`catalog.event.org_id` stamped at create, never re-derived) · `080:60-73` (`has_venue_role` is venue-keyed, no operator test) · `080:93-103` (`has_org_role_over_venue` resolves the *current* `catalog.venue.org_id`) · `080:314-324` (the only writer that ever deletes `staff_role` is the **erasure** hook) · consumers with no binding: `081:220-221, 288-289, 379-380, 455-456, 721-722, 817` · `082:151-159, 223-229` · `086:745-748, 1083, 1162, 1183` · `080:367-419` (all four AUTHZ-PKG1 read policies) · **contrast** `087:650-659`, `087:1299`, `087:1369-1374`, `087:299-300` which *do* bind | Club A moves from Org Alpha to Org Beta via the contracted `update_venue` org_id arm. Alpha's `venue_manager` rows survive the move untouched. That ex-manager now: reads Beta's **draft** events (`080:381-390`), reads Beta's orders including `buyer_id`, `total_minor` and `command_idempotency_key` (`082:151-159`), reads Beta's door manifests and scan ledger (`086:317-352`, `086:155-158`), and **writes** — re-prices Beta's ticket types (`081:288-292`), cuts capacity on Beta's live batches (`081:455-459`), releases Beta's buyers' inventory holds (`081:815-820`), opens/closes Beta's door manifest (`086:745-748`), and mints comps against Beta's inventory (`086:1162`). Symmetrically, Beta's `org_owner` immediately acquires pricing and capacity authority over Alpha's still-open events, because `has_org_role_over_venue` reads the *new* operator | (a) `093` helper `kernel.has_venue_role_bound(venue,event,roles)` carrying the E-76 conjunct, and `CREATE OR REPLACE` the affected `081/082/086` bodies + `DROP/CREATE` the four `080` policies to use it; (b) `093` adds a `staff_role` purge + audit row inside `catalog.update_venue`'s `org_id` arm; (c) until (a) lands, **operationally freeze operatorship transfers** | POST-FREEZE AMENDMENT + IMPLEMENTATION FOLLOW-UP + OPERATIONAL CONFIG | **YES** (or gate operatorship transfer to "never" at launch) |
| **V-2** | **P1** | Comp allocation and issuance carry no AUTHZ-M8/C39 step-up and no separation of duties — a single `venue_manager` session mints unlimited free live tickets | `086:1154-1170` (`allocate_comp`: one `has_venue_role([venue_manager])` test, nothing else) · `086:1172-1212` (`issue_comp`: same single test, then calls the real mint) · `083:440-582` (`kernel.issue_ticket_atoms` — real `kernel.tickets` rows, `sold += q`) · `078:1561-1563` (`comp.per_staff_step_up_max_units` / `_window_hours` seeded `null` with the documented X-12 "absent ⇒ EVERY comp needs step-up") · spec requires C39 on both verbs: `PHASE_2_RLS_PERMISSION_SPEC.md:1859-1860` · no `aal` read exists anywhere in `086` (grep: `v_aal` appears only in `085` and `087`) | An attacker with a stolen `venue_manager` session (aal1, no re-auth, no step-up demanded) calls `allocate_comp(session, batch, 500)` and then `issue_comp(alloc, attacker_uid, 500)`. 500 genuine, scannable, resaleable tickets exist, indistinguishable at the door from sold inventory. The only artifact is a `comp_allocation` row the attacker created themselves; there is no second human, no cap, no step-up, and no rate limit anywhere on the path | `093` `CREATE OR REPLACE` both verbs to read `comp.per_staff_step_up_max_units` / `_window_hours` live, count the actor's comps in the window, and demand `aal2` (using the exact `085:1163-1168` idiom) once the cap is exceeded — with the X-12 fail-to-safe (NULL config ⇒ step-up always). Owner must also seed the two keys | IMPLEMENTATION FOLLOW-UP + OWNER POLICY DECISION (the cap values) | **YES** |
| **V-3** | **P1** | `venue.issue_comp` mints custody to an arbitrary identity with no recipient-state gate — a third party can re-arm a BP-1 deletion blocker on a `DELETION_PENDING` user, or hand custody to a tombstone | `086:1172-1207` (`p_grantee` is inserted straight into the mint context as `owner_id`; no `is_deletion_pending`, no `ERASED` check, no consent, no accept step) · contrast the E-23 defensive twin present in `082:345-351` and `085:1912-1916` · `DELETION_STATE_MACHINE_SPEC.md:167-176` BP-1 custody blocker · `DELETION_STATE_MACHINE_SPEC.md:274` F-4 relies on an **accept** step that `issue_comp` does not have | User U requests account deletion. A `venue_manager` (any venue, no relationship to U required beyond knowing U's uuid) issues a comp to `p_grantee = U`. A fresh `kernel.tickets` row lands with `current_owner_id = U`; BP-1 re-arms and the deletion sweep can never reach the tombstone. Repeat on a cron and U's erasure right is denied indefinitely by a third party. The `ERASED` variant is worse in kind: custody lands on a tombstone, contradicting INV #23 ("a tombstone holds no authority") which `080:191-193` enforces for staff grants but nothing enforces here | `093` adds the `082:345-351` twin (refuse `DELETION_PENDING` **and** `ERASED` grantee) to `issue_comp`; longer term an accept step, mirroring F-4's design | IMPLEMENTATION FOLLOW-UP + OWNER POLICY DECISION (whether a pending-deletion grantee is refused or merely warned) | **YES** |
| **V-4** | **P1** | `venue.cancel_pending_order` has **zero** in-body authorization, and the decision that keeps it unreachable is an open owner question | `082:478-523` (the entire body: null checks, a `reason_code` literal equality, then `update … set status='cancelled'` — no `auth.uid()`, no role test, no ownership test, no org test) · `082:691-693` (granted to `service_role` only) · `082:469-476` (PFA-15: the delivery mechanism is *undetermined*, and the four candidates the migration lists include "**an authenticated edge-caller**") · `076:71-79` (`service_role` holds no `venue` USAGE, which is the only thing making it inert today) | PFA-15 is resolved the convenient way — someone grants `EXECUTE … TO authenticated` so the edge function can call it with the user's JWT. Every signed-in user can now cancel **any** pending order by uuid: a trivial cross-tenant denial-of-sale, and each cancellation releases the victim's held inventory back to the pool (via the `081` TTL sweep) for the attacker to reserve. Order ids leak through any client that renders them | (a) Record the PFA-15 resolution **in writing** as `service_role`/postgres-owner only, never `authenticated`; (b) `093` adds a defensive in-body assertion (`auth.uid() is null or kernel.is_platform(array['platform_admin'])`) so the function is safe even if a future grant is wrong; (c) deliver reachability by granting `service_role` USAGE on `venue`, not by widening EXECUTE | OWNER POLICY DECISION + IMPLEMENTATION FOLLOW-UP + OPERATIONAL CONFIG | **YES** (the PFA-15 decision must be recorded before activation) |
| **V-5** | **P2** | `venue.release_inventory_hold` admits `venue_scanner`, a label AUTHZ-H5 explicitly **removed** from this verb | `081:815-820` (`… and not kernel.has_venue_role(v_venue, array['venue_manager','venue_scanner'])`) · spec: `PHASE_2_RLS_PERMISSION_SPEC.md:1851` — "`venue_scanner` **REMOVED** — `AUTHZ-H5`", and the sanctioned set is `venue_box_office`/`venue_manager` **or** `has_org_role_over_venue([org_owner,org_admin])` | A door scanner — the lowest-trust venue label, the one running on a tablet in a crowd — can release **any** buyer's active hold at that venue, for any session, at any time. During an on-sale, a scanner (or anyone who obtains a scanner's session) drops competing buyers' holds and re-reserves the freed capacity. The implementation is simultaneously *narrower* than spec (box office and the org arm are missing), so this is a mis-transcription, not a deliberate widening | `093` `CREATE OR REPLACE` with the spec set: holder · `has_venue_role([venue_box_office, venue_manager])` · `has_org_role_over_venue([org_owner, org_admin])` · the NULL-uid sweep branch | POST-FREEZE AMENDMENT (081 frozen) | No — but fix before the first on-sale |
| **V-6** | **P2** | `venue.record_scan` takes `p_actor_device_id` from the request, unvalidated, into an append-only ledger — AUTHZ-H3b requires it come from `assert_door_session`'s return | `086:1070-1099` (`p_actor_device_id` flows straight into the `venue.scan` insert at `086:1096-1098`; no check that the device exists at this venue, is `active`, or belongs to the caller) · `086:119-138` (`venue.scan.device_id` FKs `scan_device` but carries **no venue conjunct**) · `086:147-149` (append-only trigger — the forged row is permanent) · spec: `PHASE_2_RLS_PERMISSION_SPEC.md:1857` ("`p_actor_device_id` taken from its return value, **never from the request**") · the `service_role` + `assert_door_session` arm the spec mandates is **absent** from the body entirely | A `venue_scanner` committing admission fraud (waving in unticketed friends, or double-admitting a re-sold code) attributes every scan to another staff member's device uuid — or to a *different venue's* device, since the FK does not constrain venue. `venue.scan` is append-only, so the false attribution can never be corrected; the per-device forensic trail that is the entire point of the ledger is destroyed at will by the role most likely to need auditing | `093` `CREATE OR REPLACE` `record_scan`/`reconcile_offline_scans` to (a) validate `p_actor_device_id` resolves to an `active` `scan_device` at `v_venue`, and (b) implement the `service_role` + `assert_door_session` arm, sourcing the device id from the assertion's return. Add a venue conjunct via a CHECK/trigger on `venue.scan` | POST-FREEZE AMENDMENT + IMPLEMENTATION FOLLOW-UP | No |
| **V-7** | **P2** | `kernel.change_org_role` can promote a `DELETION_PENDING` identity to (sole) `org_owner`, creating a BP-11 completion blocker on a third party's pending erasure | `077:1167-1290` (no `deletion_state` gate anywhere in the body; the only gates in `077` are `077:785` `create_organization` and `077:1111` `accept_org_invite`) · `DELETION_STATE_MACHINE_SPEC.md:175` (BP-11: sole `org_owner` blocks the tombstone) · `DELETION_STATE_MACHINE_SPEC.md:276` (F-6 names only the two verbs `077` gates) | User U requests deletion. An `org_owner` promotes U to `org_owner` (`change_org_role`) and then removes themselves (permitted — the ≥1-owner floor is satisfied while U holds the label). U is now the sole `org_owner`; BP-11 blocks U's erasure indefinitely, and U cannot self-demote (the last-owner floor at `077:1236-1240` refuses). U's only exit is a platform intervention. F-6's letter does not name this verb, so this is a gap in the machine, not a coding error against it | `093` adds the F-6 refusal to `change_org_role` when `p_new_role = 'org_owner'` and the target is `DELETION_PENDING`/`ERASED`; amend DSM §3.2 to name the verb | POST-FREEZE AMENDMENT + OWNER POLICY DECISION (amend F-6) | No |
| **V-8** | **P2** | `kernel.tickets` venue read arm is venue-wide and full-projection for `venue_scanner`; spec grants "scan cols, session" | `080:410-419` (`kernel_tickets_sel_venue` — `has_event_role(session→event, ['venue_manager','venue_finance','venue_scanner'])`, no session narrowing, no column narrowing beyond the shared `080:430-434` grant) · spec `PHASE_2_RLS_PERMISSION_SPEC.md` §7.5 row `venue_scanner`: `A⁸(scan cols, session)` + note 9 "only for its session" | A scanner working one Tuesday show enumerates every ticket atom the venue ever issued for every event — serials, ticket types, credential versions, signing key ids, seat refs, resale states. Serial + `credential_version` + `signing_key_id` is the offline-verify triple; a scanner harvesting it across the venue's whole history is the precondition for offline credential forgery once `feature.native_scanning_enabled` flips. The `current_owner_id` col-scope (`080:421-434`) correctly keeps PII out, so this is credential-metadata exposure, not PII | `093` narrows the scanner arm to sessions with an **open** `venue.door_manifest` (the natural "tonight" operand, which `086` supplies and OPEN-1 said did not exist at `080`); or a column-scoped RPC. Note: `080`'s policies are dropped/recreated by name, so this is a policy replacement, not a body edit | POST-FREEZE AMENDMENT (resolves OPEN-1) | No |
| **V-9** | **P2** | `venue.inventory_hold` venue read arm exposes buyer `identity_id` venue-wide to `venue_scanner` | `081:1050-1065` (`venue_inventory_hold_sel_venue` admits `venue_scanner` at venue grain) · `081:1043` (`grant select` on **all** columns including `identity_id`) · spec `PHASE_2_RLS_PERMISSION_SPEC.md` §9.5: `venue_scanner` → `A(own session)`, and `venue_finance` → `A(own-venue)` (the impl grants the scanner more and the finance label nothing) | A scanner enumerates which identities are holding inventory for every future show at the venue — a purchase-intent list joinable to `public.profiles` public-safe columns (`068`: `display_name`, `avatar_url`, `bio`) to produce a named list of who is about to buy tickets to what. Not contact data, but a behavioural profile the demographics spec's whole architecture exists to prevent leaking | `093` narrows the scanner arm to the open-manifest session set (same operand as V-8) and adds `venue_finance` per §9.5 | POST-FREEZE AMENDMENT | No |
| **V-10** | **P3** | `venue.check_promoter_slug_available` authorizes on an **unscoped** `venue.staff_role` / `org_member` probe | `090:655-656` (`exists (select 1 from venue.staff_role s where s.identity_id = v_uid and s.role in (…))` — no `venue_id`, no org) · §2.2c: "my venues" is a navigation projection, **never** an authorization input · the same function's own comment at `090:646` calls a global namespace "a cross-tenant oracle" | A `venue_promoter_manager` at any one venue probes the **global** promoter-link slug namespace at 30/min (`090:660`), enumerating competitors' campaign slugs. The slug namespace is global by design so the oracle is inherent; the defect is the *shape* of the authorization test, which is the one anti-pattern §2.2c names | `093` replaces the two `exists` probes with the scoped helpers, or accepts the global namespace explicitly and documents the ruling | POST-FREEZE AMENDMENT | No |
| **V-11** | **P3** | `venue.ticket_type` venue arm admits three labels with no row in spec §9.1, and gives `venue_scanner` venue-wide instead of own-session reads | `081:999-1009` (the non-hidden arm lists `venue_box_office`, `venue_marketing`, `venue_promoter_manager`, `venue_scanner`) · spec §9.1 table (`PHASE_2_RLS_PERMISSION_SPEC.md:1216-1227`) enumerates only `org_member`, `org_owner/admin`, `org_finance`, `venue_manager`, `venue_scanner`(door_only+public, own session), `venue_finance`, promoter, platform | A `venue_marketing` staffer reads `door_only` ticket types and prices for every event at the venue. Low impact — the two-tier hidden/non-hidden split (the R3-3a shape) is correctly implemented and hidden types stay manager-only | Reconcile in `093` or amend §9.1 to add the three labels explicitly | POST-FREEZE AMENDMENT **or** OWNER POLICY DECISION (amend the matrix — the impl is arguably the better product) | No |
| **V-12** | **P3** | `venue.inventory_batch` venue arm gives `venue_scanner` venue-wide `remaining` (spec: own session) | `081:1026-1037` · spec §9.2 `venue_scanner` → `A(remaining, own session)` | Scanner enumerates remaining inventory for all future shows. Very low impact — `remaining` for `public`-visibility types is already world-readable to any authenticated principal (`081:1020-1024`), correctly per spec | Narrow with the same open-manifest operand as V-8/V-9, or accept | POST-FREEZE AMENDMENT | No |
| **V-13** | **P3** | `venue.allocate_comp` does not bind `p_batch_id` to `p_session_id` | `086:1154-1167` (venue is resolved from `p_session_id`; `p_batch_id` is inserted unvalidated) · `086:163-174` (no CHECK tying `comp_allocation.batch_id` to `event_session_id`) · **mitigated** at mint by `083:544-551` (`batch_mismatch`) | A venue A manager writes a `comp_allocation` row pointing at venue B's batch id. `issue_comp` then always fails at `083:549-551`, so no inventory moves — but the row is a permanent, readable cross-tenant identifier reference and a silent dead-end for the operator | `093` adds the session/batch coherence check to `allocate_comp` (the `081:374-377` idiom) | POST-FREEZE AMENDMENT | No |
| **V-14** | **P3** | `credential.*` TTL/skew keys are seeded `visibility='public'` — anon-readable offline-credential validity windows | `078:1528-1530` (`credential.wallet_exp_skew`, `credential.wallet_default_span`, `credential.app_ttl_interval` seeded `'public'`) · `078:354-356` (anon reads every `public` row) · AUTHZ-CFG1 (`PHASE_2_RLS_PERMISSION_SPEC.md:1130-1165`) restricts `door.*` on exactly this reasoning ("how long a stolen door tablet keeps working") | A signed-out attacker learns the exact clock skew tolerance and validity span of an offline credential before attempting a replay — the same calibration leak AUTHZ-CFG1 was written to close, one namespace over. Not a spec violation (`credential.*` is not in the six restricted namespaces) but the same argument applies verbatim. **Confirmed clean:** every `refund.*`, `payout.*`, `authn.*`, `comp.*`, `crm.*`, `door.*` key is seeded `restricted` | Owner ruling to move `credential.*` to `restricted` and expose the *decision* not the *threshold*; delivered as a `set_platform_config` version bump, not a migration | OWNER POLICY DECISION | No |

**Counts:** 1 × P0, 3 × P1, **5 × P2**, **5 × P3**.

### Explicitly checked and CLEAN

- **Predicate hygiene.** All four `080` predicates are `stable security definer set search_path = ''` with
  fully-qualified references (`080:60-73`, `78-88`, `93-103`, `105-115`); so is `kernel.has_org_role`
  (`077:453-466`) and `kernel.is_platform` (`077:468-488`). No JWT-claim role test exists anywhere.
- **No escalation via a foreign id.** Passing another tenant's `venue_id`/`event_id` to any predicate simply
  probes *that* venue's roster for `auth.uid()` and returns false. A NULL/unknown id yields a NULL scalar
  sub-select → `exists` over an impossible predicate → false. Fail-closed on every degenerate input.
- **No transitive org leak.** `has_org_role_over_venue`/`_over_event` resolve exactly one hop
  (`catalog.venue.org_id` / `catalog.event.org_id`) and delegate. RM-4 holds: there is no venue→org path.
  (The *staleness* of that one hop after an operatorship move is V-1, not a leak in the resolution itself.)
- **Revocation is immediate.** `has_venue_role` is a live point probe on `venue.staff_role`
  (`080:55-59`, `080:302-304`); no JWT survives a revoke, and there is no cache, TTL or materialization.
  `revoke_staff_role` correctly permits self-revoke and manager-revokes-manager (`080:270-283`).
- **No self-grant, and the AUTHZ-M7 tier guard is real.** `080:151-154` blocks self-grant;
  `080:203-214` forces `venue_manager` minting through the org tier.
- **`venue_door` / `venue_promoter` do not exist.** The only occurrences in the entire corpus are
  `080:33-38` and `080:143-149`, where they are named as *superseded* and rejected.
- **Buyer PII is unreachable.** `venue.list_attendees` (`087:1400-1402`), `venue.lookup_attendee`
  (`087:1439-1441`) and `venue.build_export_rows` (`087:910-919`) all raise
  `customer_ref_crypto_unavailable` after authz and before touching data. `kernel.org_contact_consent` and
  `_event` are deny-all with zero policies (`082:260-262`, `082:295-298`). `venue.export_job` is deny-all
  with an empty grant set (`087:172-173`). `kernel.tickets.current_owner_id` is stripped from the
  `authenticated` column grant (`080:421-434`). **The strongest part of the model.**
- **The only buyer-identifying data a venue staffer reaches** is `venue."order".buyer_id` /
  `venue.inventory_hold.identity_id` (opaque uuids), joinable only to `public.profiles`' public-safe columns
  (`068`: `display_name`, `avatar_url`, `avatar_path`, `bio`, `created_at`, `is_verified_seller`,
  `stripe_onboarding_complete`). No email, phone, legal name or wallet balance is reachable on any path.
- **Money separation of duties holds.** `kernel.request_order_refund` excludes `org_admin` and **every**
  venue label (`085:907-919`); `set_org_payout_destination` is `org_owner`-only with maturity + AAL2
  (`085:1611-1631`); `request_org_payout` carries SoD-1, maturity, AAL2 and probation (`087:427-441`);
  `venue.finalize_primary_order` is `service_role`-only and treats the payment as the authority
  (`085:2147-2148`, `085:1918-1939`).
- **`venue.open_settlement` binds its scope.** `087:253-260` — venue ∈ org, event ∈ venue ∧ org, raising
  `not_found` (no existence oracle). The one verb that takes a `(org, venue)` pair does the right thing.
- **No view laundering.** The only view in `076`–`092` is `market.listing_unified`, created
  `with (security_invoker = true)` (`089:48-49`) and granted to `authenticated` only (`089:93-94`).
- **No function retains implicit PUBLIC EXECUTE.** PFA-1 (`076:100-111`) makes this the highest-risk class in
  the schema. I enumerated every `create or replace function` across `076`–`092` and cross-matched against
  every `revoke … on function` / ACL array: **zero misses.** Each revoke includes `public`.
- **`granted_by` erasure handling.** `080:314-324` deletes the erased identity's grants (INV #23) and
  SET NULLs grants they made (INV #24) — correct, and the F-11 `FOR SHARE` race construction at
  `080:184-194` is sound.
- **Config seeds.** Every `refund.*` / `payout.*` / `authn.*` / `comp.*` / `crm.*` / `door.*` key is seeded
  `restricted` (`078:1545-1566`); only feature kill-switches and `credential.*` are `public` (V-14).

---

## 3. Per-verb authorization table (client-callable `venue.*` / `catalog.*`)

Every routine below carries `GRANT EXECUTE TO authenticated`. **Subject** = how the authorization scope is
obtained: *server-resolved* means the body reads it from the object id; *param* means it is trusted from the
caller (there are none in this class except where noted).

| # | Verb | Pkg:line | Subject | In-body authorization predicate | Notes |
|---|---|---|---|---|---|
| 1 | `kernel.has_venue_role` | `080:60` | param venue | *(is the predicate)* — `staff_role` point probe on `auth.uid()` | Oracle limited to the caller's own grants |
| 2 | `kernel.has_event_role` | `080:78` | event→venue | delegates to (1) | |
| 3 | `kernel.has_org_role_over_venue` | `080:93` | venue→org | delegates to `has_org_role` | reads **current** operator (V-1) |
| 4 | `kernel.has_org_role_over_event` | `080:105` | event→org | delegates to `has_org_role` | reads **stamped** org (V-1) |
| 5 | `venue.grant_staff_role` | `080:121` | server-resolved | `venue_manager` (5 labels) · org `owner/admin` · `platform_admin`; `venue_manager` label requires org/platform (AUTHZ-M7); no self-grant; `ERASED` target refused | `DELETION_PENDING` target **allowed** — deliberate, per §3.2 (no staff-grant refusal exists) |
| 6 | `venue.revoke_staff_role` | `080:249` | server-resolved | self · `venue_manager` · org `owner/admin` · `platform_admin` | asymmetric by design; no last-manager floor |
| 7 | `venue.create_ticket_type` | `081:175` | event→venue | `has_org_role_over_venue([owner,admin])` ∨ `has_venue_role([manager])` | V-1 |
| 8 | `venue.set_ticket_type_price` | `081:246` | tt→event→venue | same, C9 live re-check under `FOR UPDATE` | money-consequential; **no AAL2** (spec does not require) · V-1 |
| 9 | `venue.create_inventory_batch` | `081:320` | tt→event→venue | same; also enforces tt/session same-event | V-1 |
| 10 | `venue.set_batch_capacity` | `081:408` | batch→tt→event→venue | same; **no platform arm** (correct per §20.3.2); C27 floor `new ≥ held+sold` absolute | V-1 |
| 11 | `venue.reserve_primary_inventory` | `081:527` | batch | any `authenticated`, own hold; F-1 `DELETION_PENDING` refusal; feature-flag gated | matches spec |
| 12 | `venue.create_inventory_hold` | `081:672` | batch→venue | `has_org_role_over_venue([owner,admin])` ∨ `has_venue_role([manager])` | matches spec |
| 13 | `venue.release_inventory_hold` | `081:764` | batch→venue | holder ∨ `has_venue_role([manager, **scanner**])` ∨ NULL-uid sweep | **V-5** — scanner removed by AUTHZ-H5; box office + org arm missing |
| 14 | `catalog.publish_event` | `081:899` | event | `has_org_role([owner,admin])` ∨ `has_venue_role([manager])` | |
| 15 | `venue.create_primary_checkout` | `082:305` | session→event→org | any `authenticated`, buyer = `auth.uid()`; F-1 + E-23 gates first; org server-derived; price snapshot server-read | **exemplary** — no client-trusted field |
| 16 | `kernel.grant_org_contact_consent` | `082:530` | own row | own-row only, no `p_identity_id` param | |
| 17 | `kernel.withdraw_org_contact_consent` | `082:591` | own row | own-row only | |
| 18 | `kernel.list_my_org_contact_consents` | `082:636` | own row | own-row only | |
| 19 | `catalog.set_session_door_schedule` | `086:474` | session→event | `has_org_role` ∨ `has_venue_role([manager])` | |
| 20 | `venue.open_door_manifest` | `086:728` | session→venue | `has_venue_role([manager])` ∨ org `owner/admin` ∨ `platform_admin` | O-4 allow-list correct · V-1 |
| 21 | `venue.close_door_manifest` | `086:811` | session→venue | same | V-1 |
| 22 | `venue.get_door_manifest` | `086:843` | session→venue | `has_venue_role([scanner, manager])` | `service_role`+`assert_door_session` arm absent (fail-closed) |
| 23 | `venue.preview_door_open_impact` | `086:875` | session→venue | `has_venue_role([manager])` ∨ `platform_admin` | org arm missing vs spec (narrower) |
| 24 | `venue.get_live_device_count` | `086:895` | session→venue | `has_venue_role([manager])` ∨ `platform_admin` | scanner-own-session arm missing (narrower) |
| 25 | `venue.create_door_pin` | `086:918` | param venue | `has_venue_role([manager])` | V-1 |
| 26 | `venue.revoke_door_pin` | `086:932` | pin→venue | `has_venue_role([manager])` | |
| 27 | `venue.revoke_door_session` | `086:971` | session→venue | `has_venue_role([manager])` ∨ `platform_admin/support` | |
| 28 | `venue.register_scan_device` | `086:1004` | param venue | `has_venue_role([manager])` | V-1 |
| 29 | `venue.set_scan_device_status` | `086:1017` | device→venue | `has_venue_role([manager])` | |
| 30 | `venue.sync_scan_device_manifest` | `086:1040` | device→venue | `has_venue_role([scanner, manager])` | |
| 31 | `venue.record_scan` | `086:1070` | session→venue | `has_venue_role([scanner, manager])` | **V-6** — `p_actor_device_id` unvalidated |
| 32 | `venue.validate_ticket_online` | `086:1111` | session→venue | `has_venue_role([scanner, manager])` | |
| 33 | `venue.reconcile_offline_scans` | `086:1130` | session→venue | `has_venue_role([scanner, manager])` | same device-id issue as V-6 |
| 34 | `venue.allocate_comp` | `086:1154` | session→venue | `has_venue_role([manager])` **only** | **V-2** (no C39/AAL2), **V-13** (batch unbound), org arm missing |
| 35 | `venue.issue_comp` | `086:1172` | alloc→session→venue | `has_venue_role([manager])` **only** | **V-2**, **V-3** — mints real custody |
| 36 | `venue.create_guest_list` | `086:1214` | session→venue | `has_venue_role([manager, box_office])` | |
| 37 | `venue.upsert_guest_entry` | `086:1229` | list→session→venue | `has_venue_role([manager, box_office])` | |
| 38 | `venue.remove_guest_entry` | `086:1256` | entry→…→venue | `has_venue_role([manager, box_office])` | |
| 39 | `venue.check_in_guest_entry` | `086:1274` | entry→…→venue | `has_venue_role([manager, box_office, scanner])` | |
| 40 | `venue.get_holder_mix` | `086:1311` | session→venue | `has_venue_role([manager, marketing, promoter_manager])` ∨ org ∨ `platform_admin` | aggregate only; X-3 no-export holds |
| 41 | `venue.unpublish_holder_mix` / `_all` | `086:1355/1370` | — | `platform_admin` only | |
| 42 | `kernel.grant_door_freeze_override` | `086:568` | — | `platform_admin` only | |
| 43 | `kernel.revoke_door_freeze_override` | `086:606` | — | `platform_admin`/`platform_risk` | |
| 44 | `kernel.revoke_signing_key` | `086:714` | — | platform | |
| 45 | `venue.open_settlement` | `087:227` | **params re-bound** | `has_venue_role(venue,[finance])` ∨ `has_org_role(org,[finance,owner])` **then** venue ∈ org, event ∈ venue∧org | correct scope binding |
| 46 | `kernel.close_settlement` | `087:289` | settlement | `venue_finance` **∧ E-76 operator bind** ∨ `org_finance` ∨ `platform_admin` | **binds** |
| 47 | `kernel.request_org_payout` | `087:408` | param org | `has_org_role([owner,finance])` + SoD-1 + maturity + **AAL2** + probation | |
| 48 | `venue.request_export` | `087:681` | scope→org/venue | `assert_may_request` (raising) — template allow-list + **E-76 bind** | |
| 49 | `venue.authorize_export_download` | `087:1013` | job→scope | `assert_may_request` | |
| 50 | `venue.revoke_export` | `087:1053` | job→scope | requester ∨ `platform_admin`, then `assert_may_request` | |
| 51 | `venue.list_export_jobs` | `087:1275` | scope→org/venue | org `owner/admin/marketing` ∨ (**E-76 bind** ∧ venue `manager/marketing`) ∨ platform | |
| 52 | `venue.list_attendees` | `087:1359` | session→org/venue | 4 arms, all **E-76 bound**; platform arm needs a closed-enum reason | **parked fail-closed** |
| 53 | `venue.lookup_attendee` | `087:1417` | session→org/venue | venue `manager/box_office` (**E-76 bound**) ∨ org `owner/admin` ∨ `platform_support` | **parked fail-closed** |
| 54 | `venue.create_promoter` … `set_promoter_code_window` (9 verbs) | `090:414-902` | promoter/code→org, event→venue | `has_org_role(org,[owner,admin,promoter_manager])` ∨ (event ∈ org ∧ `has_venue_role(venue,[manager,promoter_manager])`) | scope-bound |
| 55 | `venue.check_promoter_slug_available` | `090:649` | **none** | unscoped `org_member` / `staff_role` existence probe | **V-10** |
| 56 | `venue.preview_promoter_code` | `090:948` | code+session | code validity + session scope | also `service_role` for the unauthenticated edge |
| 57 | `venue.bind_order_attribution` | `090:984` | order→venue | buyer-own ∨ (`source='door'` ∧ `has_venue_role([box_office, manager])`) | |
| 58 | `venue.review_attribution_flag` | `090:1160` | attribution→venue/org | `has_venue_role([manager])` ∨ org `owner/admin` ∨ `platform_risk` | |
| 59 | `venue.get_my_promoter_summary` / `list_my_attributions` | `090:1242/1296` | own promoter | own-promoter scoped | |
| 60 | `venue.list_promoter_attributions` | `090:1334` | scope | venue `manager/finance/promoter_manager` ∨ org ∨ platform | no E-76 bind (V-1 class) |
| 61 | `kernel.is_promoter_for_event` | `090:1222` | event | own-relationship predicate | |
| 62 | `catalog.create_venue` | `078:510` | param org | `has_org_role([owner,admin])` | |
| 63 | `catalog.approve_venue` | `078:564` | venue | `is_platform([platform_admin])` | |
| 64 | `catalog.update_venue` | `078:623` | venue→org | `has_org_role([owner,admin])` ∨ `has_venue_role([manager])`; **`org_id` arm = `platform_admin` only + reason** | the V-1 trigger verb |
| 65 | `catalog.create_event` | `078:829` | param venue→org | `has_org_role([owner,admin])` ∨ `has_venue_role([manager])`; org **server-derived** | |
| 66 | `catalog.create_event_session` | `078:749` | event→venue | same | |
| 67 | `catalog.update_event` | `078:901` | event→venue | same + marketing-column arm (`org_marketing`/`venue_marketing`) | |
| 68 | `catalog.update_event_session` | `079:518` | session→event→venue | same + marketing arm | |
| 69 | `catalog.set_platform_config` | `078:1048` | — | `platform_admin` + dual control on 7 namespaces | |
| 70 | `catalog.set_resale_policy` | `078:1318` | scope→venue/org | `has_org_role([owner,admin])` ∨ `platform_admin` ∨ `has_venue_role([manager])` | |
| 71 | `catalog.effective_freeze_at` · `kernel.money_role_grant_matured` | `078:405/454` | scope | read predicates, no mutation | |

**Not client-callable (verified `service_role`/definer-only):** `venue.cancel_pending_order` (`082:691-693`
— but see **V-4**), `venue.finalize_primary_order` (`085:2147-2148`), `kernel.refund_primary_order`,
`kernel.issue_ticket_atoms` (`083`), `venue.assert_may_request`, `venue.build_export_rows`,
`venue.finalize_export`, `kernel.pay_promoter_commission` (`090:1604-1605` — no grant at all),
`venue.normalize_promoter_code` (`090:62`), every sweep, every `on_identity_erased_*` hook, `notify.emit_*`.

---

## 4. RLS matrix — venue / catalog tables

**RLS on** is `true` for every table below (verified). **Zero policies + RLS on = deny-all** (GP-3).

| Table | RLS | Policies | What `authenticated` can actually SELECT | Matches spec? |
|---|---|---|---|---|
| `catalog.venue` | on | `sel_anon` (`078:307`), `sel_org` (`078:312`), `sel_venue` (`080:367`) | approved venues (all) · own-org incl. draft (`org_member`+) · own-venue (all six labels). Cols: all but none withheld | ✅ §8.1 |
| `catalog.event` | on | `sel_anon` (`078:323`), `sel_org` (`078:328`), `sel_venue` (`080:381`) | non-draft (all) · own-org incl. draft (`org_member`+) · own-venue: **draft only for `venue_manager`**, non-draft for the other five | ✅ §8.2 (the R3-3a `status <> 'draft'` form is correct) |
| `catalog.event_session` | on | `sel_anon` (`078:336`), `sel_org` (`078:343`), `sel_venue` (`080:397`) | sessions of visible events · own-org · own-venue (5 labels; **scanner deliberately absent**, OPEN-1) | ✅ (scanner narrower than §8.3) |
| `catalog.platform_config` | on | `sel_public` (`078:354`), `sel_restricted` (`078:359`) | `visibility='public'` rows only; restricted → `platform_admin`/`platform_risk` | ✅ §8.4 · see **V-14** on which keys are public |
| `catalog.resale_policy` | on | `sel_public` (`078:382`) | policies of approved venues / non-draft events | ✅ §8.5 |
| `venue.staff_role` | on (**NOT forced** — `080:331-335`, load-bearing) | `sel_venue`, `sel_org`, `sel_platform` (`080:343/351/356`) | own-venue roster (all six labels) · org `owner/admin` over the venue · `platform_admin/support/risk` | ✅ §9.9 |
| `venue.ticket_type` | on | `sel_public` (`081:990`), `sel_venue` (`081:999`) | `visibility='public'` (any authenticated) · hidden → org `owner/admin` + `venue_manager` only · non-hidden → +`org_finance`, `org_member`, and 5 venue labels | ⚠️ **V-11** — 3 labels not in §9.1; scanner venue-wide not own-session |
| `venue.inventory_batch` | on | `sel_public` (`081:1020`), `sel_venue` (`081:1026`) | **`remaining` only** — `capacity/held/sold` withheld from *all* clients by column grant (`081:1016-1018`, E-24/E-29). Rows: public-visibility types (any) · org `owner/admin/finance` + venue `manager/finance/scanner` | ⚠️ **V-12** — narrower on columns than §9.2 (documented impossibility), wider on scanner scope |
| `venue.inventory_batch_shard` | on | **zero** | nothing | ✅ §9.3 deny-all |
| `venue.inventory_movement` | on | **zero** (+ `revoke update,delete`, `081:1068`) | nothing | ✅ §9.4 deny-all (spec's `V(own-venue)` cells are undeliverable without a policy — narrower, safe) |
| `venue.inventory_hold` | on | `sel_owner` (`081:1045`), `sel_venue` (`081:1050`) | own holds · org `owner/admin/finance` + venue `manager/scanner` — **incl. `identity_id`** | ⚠️ **V-9** — scanner venue-wide; `venue_finance` missing |
| `venue."order"` | on | `sel_owner`, `sel_org`, `sel_venue` (`082:139/143/150`) | own orders · org `owner/admin/finance` + `platform_risk/admin` · venue `manager/finance`. **All columns** incl. `buyer_id`, `total_minor` | ✅ §9.7 (scanner deliberately excluded, E-37 — narrower) |
| `venue.order_item` | on | `sel_owner`, `sel_org`, `sel_venue` (`082:210/216/223`) | inherits order scope | ✅ §9.8 |
| `kernel.org_contact_consent` | on | **zero**, empty grant (`082:260-262`) | nothing | ✅ OR-1 |
| `kernel.org_contact_consent_event` | on | **zero**, AO (`082:295-298`) | nothing | ✅ OR-1 |
| `venue.door_pin` | on | `sel_venue` (`086:53`) | `venue_manager` only; **`pin_hash` withheld** by column grant (`086:50-51`) | ✅ §9.10 |
| `venue.door_session` | on | **zero**, empty grant (`086:83`) | nothing — `token_hash` unreachable on every path | ✅ AUTHZ-H3 |
| `venue.scan_device` | on | `sel_venue` (`086:108`) | venue `scanner/manager` | ✅ §9.11 |
| `venue.scan` | on | `sel_venue` (`086:155`), AO | venue `scanner/manager`, venue-wide | ✅ §9.12 (see **V-6** for the write-side attribution defect) |
| `venue.comp_allocation` | on | `sel_venue` (`086:183`) | `venue_manager` only | ✅ §9.15 |
| `venue.guest_list` / `venue.guest_entry` | on | `sel_venue` (`086:206/229`) | venue `manager/box_office`. `guest_entry.guest_name` is staff-entered, not buyer data | ✅ §9.16 |
| `venue.door_manifest` / `_entry` / `_delta` | on | `sel_venue` (`086:317/350/392`), AO | venue `scanner/manager`. **No identity column anywhere** (PFA-24) | ✅ |
| `venue.holder_mix_snapshot` / `_bucket` | on | **zero** (`086:420/429`) | nothing — RPC-only, X-3 no-export | ✅ |
| `venue.settlement` / `venue.settlement_line` | on | `sel_org`, `sel_venue` (`087:79/83/118/123`) | org `owner/admin/finance` + platform · venue `manager/finance` | ✅ §9.13/§9.14 |
| `venue.export_job` | on | **zero**, empty grant (`087:172-173`) | nothing | ✅ OR-1 |
| `venue.promoter` / `_link` / `_code` / `_code_scope` | on | 10 policies (`090:358-402`) | org `owner/admin/finance` + platform · venue `manager/finance` (event/venue-scoped) · own promoter row | ✅ §9.17 |
| `venue.attribution` / `venue.attribution_review` | on | **zero** (grant list at `090:351` omits them) | nothing | ✅ |
| `kernel.tickets` | on | `sel_owner` (`079:738`), `sel_platform` (`079:743`), `sel_venue` (`080:411`) | own atoms · platform · org `owner/admin/finance` + venue `manager/finance/scanner`. **`current_owner_id` stripped** from the column grant (`080:430-434`) | ⚠️ **V-8** — scanner venue-wide + full projection vs §7.5 "scan cols, session" |

---

## 5. Cross-tenant attack paths — direct answers

**Can a staff member of venue A read or mutate venue B's data?**
*Normally, no.* Every predicate is venue-keyed and every verb resolves the venue from the object. **After an
operatorship transfer, yes** — and in both directions, for reads *and* writes (**V-1**). Two narrower cases:
a venue A manager can plant a `comp_allocation` row referencing venue B's batch id (**V-13**, blocked at mint),
and a venue A scanner can attribute scans to venue B's device ids (**V-6**).

**Can an `org_member` with no venue role reach venue data?**
Yes, and it is **spec-conformant**: `catalog.venue` and `catalog.event` incl. drafts (`078:312-331`, spec
§8.1/§8.2 both grant `org_member` `A(own-org incl. draft)`), `catalog.event_session` (`078:343`), and
non-hidden `venue.ticket_type` (`081:1005`). `org_member` reaches **no** order, settlement, staff roster,
door, scan, comp, guest, promoter or ticket row. Correct.

**Is revocation immediate?**
Yes. `has_venue_role` is a live table probe (`080:55-59`); a `DELETE` from `venue.staff_role` takes effect on
the very next call, on the same unexpired JWT. No cache, no TTL, no materialized roster, no JWT claim.
`080:302-304` states the property and the implementation honours it.

**Can a `DELETION_PENDING` identity be granted a venue role or made an org owner?**
- Venue role: **yes, deliberately.** `080:167-194` refuses only `ERASED` and documents why
  (`DELETION_PENDING` is not a blocker; DSM §3.2's freeze surface names no staff-grant refusal). The
  `FOR SHARE` construction closes the tombstone race. **Correct as ruled.**
- Org owner: **yes, and this is a gap** — `kernel.change_org_role` has no deletion gate (**V-7**), so a third
  party can make a pending-deletion identity the *sole* `org_owner` and permanently block their erasure.
- Custody: **yes, and this is a gap** — `venue.issue_comp` pushes ticket custody onto any identity with no
  state check (**V-3**), re-arming BP-1.

---

## 6. SAFE TO EXPOSE `venue` / `catalog` VIA POSTGREST?

### Verdict: **YES for `catalog`. QUALIFIED YES for `venue` — conditional on five items, three of which are P0/P1 fixes.**

**What changes.** Today `db-schemas = public, graphql_public, kernel`, so **no `venue.*` or `catalog.*`
routine and no `venue.*` table is reachable from a browser at all** — the entire surface audited above is
currently reachable only through edge functions holding a direct connection. Exposing both schemas makes
~26 tables and ~71 RPCs directly client-reachable with a user JWT.

**What becomes reachable, and by whom:**

- **`catalog` is already USAGE-granted to `anon`** (`076:76`). Exposing it therefore opens a **signed-out**
  surface: `catalog.venue` (approved only), `catalog.event` (non-draft), `catalog.event_session` (sessions of
  visible events), `catalog.platform_config` (`visibility='public'` rows only), `catalog.resale_policy` — all
  column-scoped (`078:124-126`, `162-164`, `204-207`, `236-237`) and policy-scoped. **This is the intended
  public discovery plane and it is correctly built.** No `catalog` function carries an `anon` EXECUTE grant
  (the revoke loops at `078:1490-1500` strip `public, anon, authenticated` before granting to
  `authenticated` only). The only anon-visible item I would change is **V-14** (`credential.*` TTLs).
- **`venue` is USAGE-granted to `authenticated` only** (`076:72`, `078`). Exposing it opens **nothing to
  `anon`** — a signed-out PostgREST request hits the schema wall with 42501. Confirm this holds in the
  deployed database before flipping the setting.
- **No table becomes readable that should not be.** I checked every `venue.*` table: the nine that must be
  invisible are RLS-on with **zero policies and an empty client grant** — `inventory_batch_shard`,
  `inventory_movement`, `door_session`, `holder_mix_snapshot`, `holder_mix_bucket`, `export_job`,
  `attribution`, `attribution_review`, plus `kernel.org_contact_consent(_event)`. The three secret-bearing
  columns (`door_pin.pin_hash`, `door_session.token_hash`, `kernel.tickets.current_owner_id`) are withheld by
  column grant or by having no grant at all. **No hash, token, key material or buyer contact value is
  reachable through any exposed table.** The one view is `security_invoker` (`089:48-49`).
- **PostgREST resource embedding** (`/order?select=*,order_item(*)`) traverses FKs but each table's own RLS
  still applies, so embedding creates no new authority.

### Conditions — all five must be met before exposure

| # | Condition | Class | Why |
|---|---|---|---|
| **C1** | Land **V-1** (operator binding + `staff_role` purge on transfer) **or** administratively freeze operatorship transfers | POST-FREEZE AMENDMENT / OPERATIONAL CONFIG | Exposure turns V-1 from "an edge function could be tricked" into "the ex-tenant's browser can do it directly" |
| **C2** | Land **V-2** and **V-3** (comp step-up + recipient gate) | IMPLEMENTATION FOLLOW-UP | `issue_comp` becomes a one-request free-ticket mint from any browser holding a manager session |
| **C3** | Record the **PFA-15** resolution in writing as `service_role`/postgres-only, and add the **V-4** defensive assertion | OWNER POLICY DECISION + IMPLEMENTATION FOLLOW-UP | The zero-authz body is one grant away from a universal order-cancel endpoint |
| **C4** | Verify in the deployed DB, immediately before flipping the setting: `venue` schema USAGE is **not** held by `anon`; `relforcerowsecurity = false` on `venue.staff_role` (`080:331-335` — FORCE makes the read policy recurse); and every `venue.*`/`catalog.*` function's ACL matches its package's revoke list | OPERATIONAL CONFIG | PFA-1 (`076:100-111`): a schema-scoped default-privileges belt for **functions** is impossible in Postgres, so any `093+` function that forgets its explicit `REVOKE … FROM public` ships **publicly executable**. This must become a CI assertion, not a review habit |
| **C5** | Land **V-5** (scanner hold-release) before the first public on-sale | POST-FREEZE AMENDMENT | Direct exposure turns an internal mis-transcription into a client-reachable inventory-griefing endpoint |

**With C1–C5 met, exposing `venue` and `catalog` is safe.** The model's design — server-resolved scope,
definer bodies, live-table predicates, deny-by-default schemas, column-scoped secrets, fail-closed PII —
holds up under direct client reachability. Without them, exposure converts one P0 and three P1s from
"requires an edge-function foothold" to "requires a browser".

**Not a condition, but recommended alongside:** V-8/V-9/V-12 share one fix — narrow the three
`venue_scanner` read arms to sessions with an **open** `venue.door_manifest`. That operand did not exist when
`080`/`081` were written (recorded as OPEN-1, `080:392-395`); `086` supplies it. One `093` policy replacement
closes all three and discharges OPEN-1.

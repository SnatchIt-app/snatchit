# DECISION F — Attendee privacy and the venue role matrix

**Status:** RECOMMENDATION (read-only analysis; no migration authored, nothing applied)
**Branch:** `feature/venue-native-and-product-v2`
**Date:** 2026-09-02
**Scope:** what a venue partner may see about an attendee at venue-direct launch, per role.

**Classification of the recommendation as a whole:**

| Component | Classification |
|---|---|
| The launch matrix (§6) | **WITHIN FROZEN ARCHITECTURE** — it is CRM §3's frozen matrix restricted to the subset the deployed bytes already enforce |
| Export stays dark at launch (§8) | **WITHIN FROZEN ARCHITECTURE** — PFA-28 already ordains it; no new decision is taken here |
| Attendee verbs stay parked (§8) | **WITHIN FROZEN ARCHITECTURE** — PFA-28, owner-signed 2026-09-01 |
| Column-scoping `venue."order"` to withhold `buyer_id` (§10, R-1) | **IMPLEMENTATION FOLLOW-UP** (093) — the I-4/E-24 pattern already ratified in 080; escalate to POST-FREEZE AMENDMENT only if RLS §9.7 is read as *contemplating* a raw identity uuid in the venue read |
| Turning `demographics.holder_mix_enabled` on | **OPERATIONAL CONFIG** — and blocked behind PFA-27's read-audit obligation |
| Un-parking the CRM rail | **POST-FREEZE AMENDMENT** — requires the 14-item `CRM_CUSTOMER_REF_CRYPTO` ratification. Not a launch item. |

---

## 1. What a venue can see TODAY (deployed 076–092)

Phase-2 migrations 076–092 are deployed but dark. Feature flags
`feature.native_issuance_enabled` and `feature.native_scanning_enabled` are both seeded
`false` (`supabase/migrations/078_catalog_reference_data_and_flags.sql:1522-1523`), so no
order and no scan can exist yet. Everything below is therefore the *structural* answer:
what the grants and policies would admit the moment the flags flip.

### 1.1 The headline finding

**No deployed Phase-2 verb returns an attendee's name or email to any venue role.** A repo-wide
grep of 080–092 for `public.profiles`, `display_name` and `auth.users` finds exactly three classes
of hit, and none of them is an attendee: promoter display names
(`090_venue_promoter_engine.sql:975`, `:1378`), promoter identity resolution at creation
(`090:465-467`), and notification labels (`092_notify_reduced.sql:720`). The two verbs that
*were* contracted to return attendee identity are parked fail-closed (§2).

**The one hole is not a verb — it is a table grant.** See §1.3.

### 1.2 Table-by-table, exactly

**`venue."order"`** — `082_venue_orders.sql:129` issues a **table-grain** grant:
`grant select on venue."order" to authenticated`. Because no column list is given, **every
column is reachable**, including `buyer_id` (a global identity uuid,
`082:75`). Three SELECT policies:

| Policy | Line | Principals |
|---|---|---|
| `venue_order_sel_owner` | `082:140-142` | the buyer's own row (`buyer_id = auth.uid()`) |
| `venue_order_sel_org` | `082:144-149` | `org_owner`, `org_admin`, `org_finance`, `platform_risk`, `platform_admin` |
| `venue_order_sel_venue` | `082:151-159` | **`venue_manager`, `venue_finance` only** |

Columns thereby reachable by `venue_manager` / `venue_finance`: `order_id`, **`buyer_id`**,
`event_session_id`, `org_id`, `status`, `source`, `total_minor`, `currency`,
`command_idempotency_key`, `attribution_candidate_code_id`, `attribution_candidate_link_id`,
`created_at`, `updated_at`.

`venue_scanner` is **deliberately absent** from the venue arm — the migration records the
reason at `082:130-138`: RLS §9.7 n28 grades the scanner `A(own-SESSION orders)`, a scope the
frozen role model cannot express, so 082 fails closed (erratum E-37). `venue_box_office` and
`venue_marketing` are absent too. **That is correct and must not be "fixed" at launch.**

**`venue.order_item`** — `082:206` table grant; policies `082:210/216/223` mirror the order's
three arms. Columns: `order_id`, `ticket_type_id`, `quantity`, `unit_price_minor`, `currency`,
`created_at`. **No identity column exists on this table**, so the table-grain grant is harmless here.

**`kernel.tickets`** — this one was done right. `080_venue_staff_roles_and_predicates.sql:429-433`
revokes the blanket grant and re-issues it as an explicit 16-column list that **excludes
`current_owner_id`**:

```
revoke select on kernel.tickets from authenticated;
grant select (ticket_atom_id, event_session_id, org_id, ticket_type_id, serial_no,
              state, resale_state, credential_version, signing_key_id, home_region,
              seat_ref, unit_row_id, external_seat_ref, issued_at, created_at, updated_at)
  on kernel.tickets to authenticated;
```

The migration states the reasoning at `080:420-428` (I-4 / E-24): a row-level policy cannot
express a per-policy column set, so the discipline is carried by the GRANT. The owner's own
row visibility is unaffected because `sel_owner`'s predicate is a policy expression, outside
column ACLs. Policy `kernel_tickets_sel_venue` (`080:410-418`) admits
`org_owner`/`org_admin`/`org_finance` at org grain, and `venue_manager`/`venue_finance`/`venue_scanner`
at session grain. **So a venue sees the tickets in its room and cannot see who holds them.**
This is the pattern §10 R-1 asks to replicate on `venue."order"`.

**`venue.scan`** (`086_venue_door_and_scan.sql:119-160`) — table grant at `086:153`; policy
`venue_scan_sel_venue` (`086:155-159`) admits **`venue_scanner`, `venue_manager`** only.
Columns include `ticket_atom_id`, `device_id`, `actor_identity_id` (the *staff* member who
scanned — RM §7.4), `direction`, `scan_type`, `result`, `offline_pending`, `device_boot_id`,
`scan_sequence`, `fraud_flag`, `manifest_id`, `manifest_version`, `occurred_at`. **No attendee
identity.** Append-only (`086:151-152` revokes UPDATE/DELETE including from `service_role`).
Note that finance roles are absent — which matches CRM §2.2 footnote ᶠ ("finance roles are `D`
on `venue.scan`, so check-in columns are **absent** from a finance read, not blank").

**`venue.door_manifest` / `_entry` / `_delta`** (`086:242`, `086:329`, `086:355`) — table grants
at `086:315`, `086:347`, `086:389`; policies at `086:317`, `086:349-351`, `086:391-393` admit
**`venue_scanner`, `venue_manager`**. The entry projection is
`(manifest_id, ticket_atom_id, serial_no, ticket_type_id, credential_version, signing_key_id,
ticket_state, resale_state)`. **There is no name column, no email column, no buyer column, no
price column.** See §3.

**`venue.door_pin`** (`086:32`) — column-scoped grant at `086:50-51` that **withholds
`pin_hash`**; policy `086:53-55` = `venue_manager` only.
**`venue.door_session`** (`086:59`) — `086:83` deny-all, **zero policies** (audit-only).
**`venue.scan_device`** (`086:88`) — table grant `086:106`; policy `086:108-110` =
`venue_scanner`, `venue_manager`.

**`venue.comp_allocation`** (`086:163`) — table grant `086:181`; policy `086:183-186` =
**`venue_manager` only**. Carries `granted_to_identity` (a global identity uuid) and
`granted_to_name` (free text). Same class of exposure as `venue."order".buyer_id`, much
smaller blast radius.

**`venue.guest_list` / `venue.guest_entry`** (`086:191`, `086:211`) — table grants `086:204`,
`086:226`; policies `086:206-209`, `086:229-235` = **`venue_manager`, `venue_box_office`**.
`guest_entry` carries `guest_name` (free text), `party_size`, `status`, `checked_in_at`.
**This is the one place a venue legitimately holds a person's name today** — and correctly so:
a guest list is a name the venue itself wrote down, not a fan's platform identity.

**`venue.staff_role`** (`080:34`) — `080:341` grants SELECT; policies `080:344-368` let all six
venue labels read their own venue's roster, plus `org_owner`/`org_admin` and platform.

**`venue.promoter` / `_link` / `_code` / `_code_scope`** — `090:351` grants SELECT; policies
`090:358-403` admit `org_owner`/`org_admin`/`org_finance`, `venue_manager`/`venue_finance`,
the promoter's own row, and platform. **`venue_promoter_manager` holds NO direct SELECT on any
promoter table** — recorded at `090:404-405` (E-124: EXEC on the code RPCs, no SELECT cell in
any frozen matrix → deny-by-default).

**`venue.attribution` / `venue.attribution_review`** — `090:349-350` revoke from
`public, anon, authenticated, service_role` and the grant line at `090:351` deliberately
**omits them**: "NO grant to any client role (AUTHZ-M9)" (`090:352`). Reachable only through
definer RPCs. See §5.

**Zero-policy, zero-grant (unreachable by any client role):** `kernel.admin_audit`
(`077:256-259`), `kernel.identity_demographic` (`077:357-359` — "The grant set is EMPTY, not
reduced"), `kernel.identity_demographic_erasure` (`077:382-384`),
`kernel.identity_contact_pref` (`077:400-401`), `kernel.identity_contact_pref_event`
(`077:423-426`), `kernel.org_contact_consent` (`082:260-262`),
`kernel.org_contact_consent_event` (`082:295-298`), `kernel.org_customer_key`,
`venue.holder_mix_snapshot` (`086:410-411`), `venue.holder_mix_bucket`, `venue.export_job`.

### 1.3 The one real exposure at launch

`venue."order"` is granted at **table** grain (`082:129`), so `buyer_id` — a raw global identity
uuid — is directly readable by `venue_manager` and `venue_finance`. Separately, migration
`068_profiles_authenticated_select_public_safe_only.sql:31-33` grants `authenticated` SELECT on
`public.profiles (id, display_name, avatar_url, avatar_path, bio, created_at,
is_verified_seller, stripe_onboarding_complete)` on **any** row — a fact CRM §5.6 states
explicitly.

Consequently:

```sql
-- available to venue_manager the moment native issuance is enabled
select o.order_id, o.total_minor, o.status, p.display_name
  from venue."order" o join public.profiles p on p.id = o.buyer_id
 where o.event_session_id = :session;
```

That is an **attendee-name roster with money attached**, produced by a two-table client-side
join, with:

- no `crm_lookup.attendee` audit row,
- no rate budget (CRM §7.1's 240/h is never consulted),
- no consent gate (§5.1's four-way conjunction is never evaluated),
- no `customer_ref` pseudonymisation,
- and the raw `identity_id` in hand — which CRM §2.3 names first on the never-exported list
  precisely because "two orgs' CSVs union on it and reconstruct a person's cross-venue
  attendance graph".

It bypasses `venue.list_attendees` entirely, which means PFA-28's park does not actually stop
a venue from getting a roster — it only stops them getting it through the audited door.
**This is the single item that requires 093 work.** See §10 R-1.

---

## 2. The parked attendee verbs

### 2.1 What they were contracted to return

`venue.list_attendees(p_session_id, p_filters, p_cursor, p_reason_code)`
(`087_venue_settlement_and_export.sql:1359`) — the holder-grain roster read, column-scoped by
role into four authority branches (`087:1370-1375`):

| Branch | Principals | Class set |
|---|---|---|
| OPERATIONS | `venue_manager`, `org_owner`, `org_admin` | the union: IDENT + OPS + CONTACT + MONEY |
| MARKETING | `venue_marketing`, `org_marketing` | IDENT + OPS + CONTACT, **no money** |
| FINANCE | `venue_finance`, `org_finance` | IDENT + MONEY, **no contact, no check-in** |
| PLATFORM | `platform_support`, `platform_risk`, `platform_admin` | reason-coded, separately rate-limited |

Denied classes are **absent from the shape**, not blank. The projection draws from the 21-field
catalogue in `docs/architecture/PHASE_2_CRM_EXPORT_SPEC.md:242-273`: fields 1–12 (IDENT/OPS/CONTACT),
13–15 (org-grain CRM), 16–21 (MONEY). Filters use a closed conjunctive grammar of eight members
(`087:1385-1387`). Frozen limits documented for the un-park at `087:1352-1357`: 240/h venue-org,
40/h + 200/24h + 20 distinct sessions for platform; 50-row page; per-page audit
`crm_lookup.attendee` / `crm_lookup.platform_roster`.

`venue.lookup_attendee(p_session_id, p_query_kind, p_query_value)` (`087:1417`) — ONE record,
service context. `p_query_kind ∈ {email_exact, order_ref, name_prefix}`. Authority
(`087:1424-1429`): `venue_manager`, `venue_box_office`, `org_owner`/`org_admin`, `platform_support`
— **both marketing labels denied**. `name_prefix < 3` chars raises `prefix_too_short` before any
data and without consuming budget (`087:1434-1436`).

### 2.2 The `customer_ref` HMAC and why the park matters for privacy

The frozen mechanism (PFA-28, `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md:2148-2152`):

```
customer_ref = base32(HMAC-SHA256(org_customer_key(:job_org_id), identity_id)[0..9])
             -- 80 bits, 16 characters
```

It is CRM field 1 (IDENT), and §2.2 says it is carried by **every** roster projection — "every
role that may read the roster". It is the **per-org pseudonym**: because the HMAC key is
`kernel.org_customer_key(org_id)`, the same person yields a *different* `customer_ref` at every
organization. That single property is what makes a roster tenant-safe: within one org it is a
stable "this is the same person as last month" handle; across two orgs it is nothing, so two
venues' files cannot be unioned into a cross-venue attendance graph. It is the direct
replacement for `identity_id`, which §2.3 forbids for exactly that reason.

PFA-28 (`POST_FREEZE_AMENDMENTS.md:2153-2178`) found that no ratified in-DB mechanism exists to
compute it: pgcrypto is deliberately absent (PFA-20 class — "unmanaged custody, a security
decision made by an implementer"), md5 is not an HMAC, and `gen_random_bytes` (the only in-DB
CSPRNG) is pgcrypto's, so the 32-byte key cannot even be minted. Options (a)–(d) were all
rejected; option (e) — **park the readers fail-closed** — was chosen and **owner-signed
2026-09-01** (`:2178`).

The ruling's substance (`:2179-2188`) is unambiguous: the requirement stays mandatory, and every
emitter **fails closed rather than emit a weaker identifier** — "never identity_id, never an
unkeyed hash, never a truncated uuid, never NULL, never a random substitute". The affected set is
exactly three of thirteen CRM entry points (`:2191-2199`): `venue.build_export_rows`,
`venue.list_attendees`, `venue.lookup_attendee`. The OR-19 lazy key mint is deferred with it, so
**no `kernel.org_customer_key` row is ever written at 087 — no key material exists to leak.**

In the deployed bytes both readers enforce authz, org scoping, the reason-code enum and the
filter grammar **first**, then raise:

- `087:1401-1403` — `precondition_failed: customer_ref_crypto_unavailable … reader parked
  fail-closed, no customer data emitted`
- `087:1462-1464` — same, for the lookup

Zero mutation, no rate budget consumed. The frozen signatures and return shapes are fixed so the
un-park is body-only (`:2210-2211`).

**Privacy reading:** the park is not a degradation, it is currently the *strongest* control in the
system. There is no attendee-identity read path at all. The forward obligation
`CRM_CUSTOMER_REF_CRYPTO` (`POST_FREEZE_AMENDMENTS.md:2275`) enumerates 14 items that must be
ratified before any customer_ref-emitting read becomes operational — primitive, computation
location, key custody, rotation, redaction, service_role exposure, test vectors. **None of that
is launch work.**

---

## 3. The door path — and the minimum data for a door decision

### 3.1 What the deployed door surface actually returns

`venue.get_door_manifest(p_session_id, p_since_delta_seq)` (`086:843-873`) — authority
`has_venue_role(venue, [venue_scanner, venue_manager])` (`086:849`). Returns a header
(`manifest_id`, `manifest_version`, `manifest_digest`, `max_delta_seq`) plus, per atom:

```
ticket_atom_id · serial_no · ticket_type_id · credential_version · signing_key_id
              · ticket_state · resale_state
```

`venue.validate_ticket_online(p_atom_id, p_session_id)` (`086:1111-1128`) returns
`ticket_state`, `resale_state`, `signing_key_id`, `credential_version`, and the single boolean
`admissible = (state='active' and resale_state='none' and not is_transfer_frozen(atom))`.

`venue.record_scan(...)` (`086:1070-1109`) returns `{scan_id, result}` where
`result ∈ {admitted, duplicate, invalid}`. Duplicate detection is a database invariant, not a
client check: the partial unique index `scan_admitted_in_uq` (`086:139-141`) allows at most one
`admitted`+`in` scan per atom per session (C41 first-in-wins).

The door lifecycle spec states the rule directly
(`docs/architecture/PHASE_2_DOOR_LIFECYCLE_SPEC.md:703-704`): *"No owner identity, no PII, no
ticket-type price — this is the door's only bulk read"*, and binds it to the hard rule that door
staff never receive a bulk attendee list.

### 3.2 The MINIMUM door dataset — determination

To admit a human at a door, a scanner needs to answer exactly one question: *is this credential
valid, for this session, right now, and has it already been used?* That decomposes into six
facts and no more:

| # | Fact | Source in the deployed manifest | Why it is required |
|---|---|---|---|
| 1 | the credential's signature verifies | `signing_key_id` + `credential_version` | otherwise a photocopied QR admits |
| 2 | the ticket is admissible | `ticket_state='active'` ∧ `resale_state='none'` ∧ not transfer-frozen | a voided / listed / locked / disputed ticket must not admit |
| 3 | it belongs to **this** session | `session_id` on the manifest header | an M2 for another session must be refused (DOOR §7.5) |
| 4 | it has not already been admitted | `venue.scan` C41 unique index (`086:139`) | duplicate detection is the whole anti-passback control |
| 5 | which tier / entrance | `ticket_type_id` | GA vs VIP vs balcony is a routing decision at the rope |
| 6 | a human-speakable handle | `serial_no` | so a door supervisor can say "ticket 114" out loud during a dispute |

**Nothing else. No name, no email, no order, no price, no buyer identity, no check-in history for
anyone but this atom.** A door is a *credential* check, not an *identity* check; where an identity
check is genuinely required (age, will-call, a disputed ticket) it is a box-office act at a
counter, not a scanner act at a rope.

### 3.3 A deliberate divergence, recommended for adoption

CRM §5.1 and role-model F11 (`docs/architecture/PHASE_2_ROLE_MODEL_SPEC.md:644`) both describe a
door projection of "**name + validity**". **The deployed door surface is tighter: it carries no
name at all.** Recommendation: **keep the deployed behaviour and do not add a name to the
manifest.** Read the specs' "name + validity" as belonging to the *box-office single-record
lookup* (F11's `A◐` for `venue_box_office`, `087:1417`), not to the scanner device. A shared
tablet handed to a contractor in a loud room is the least controllable principal in the system;
a name column on it is a name column in a stranger's hands, and it buys nothing that facts 1–6
do not already provide.

---

## 4. Consent — what the buyer agrees to, and what it unlocks

Two independent controls, and they are not the same kind of object.

**Layer 1 — per-`(identity, org)` consent.** `kernel.org_contact_consent` (`082:236-254`):
PK `(identity_id, org_id)`, `state ∈ {granted, withdrawn}`, `notice_version`, `granted_at`,
`withdrawn_at`, `source_order_id`. **Default is NO ROW — i.e. no consent.** Deny-all, zero
policies (`082:260-262`). Written only by `kernel.grant_org_contact_consent(p_org_id,
p_notice_version, p_source_order_id)` (`082:527`) and
`kernel.withdraw_org_contact_consent(p_org_id)` (`082:601`). Both are **own-row only — there is
no `p_identity_id` parameter**, so no staff member can consent on a fan's behalf. Both are
rate-limited 30/hour (`082:544`, `082:610`), both append an immutable event row to
`kernel.org_contact_consent_event` (`082:265-291`, append-only trigger `082:290`), and both write
`kernel.admin_audit` with the **data subject as the actor** (`082:583-586`, `082:637-640`).
A grant with no `notice_version` is refused by a table CHECK (`082:283`).

**Layer 2 — the master kill switch.** `kernel.identity_contact_pref.venue_email_contact ∈
{allow, block}` (`077:393-398`), default `allow`, deny-all zero policies (`077:400-401`).
`kernel.get_my_contact_prefs()` (`077:678`) resolves a missing row to `allow` — GATE-DEFAULT-1,
documented at `077:692-693`: *"the master switch is a kill switch, not a consent"*. That is why
its default is permissive while Layer 1's is not: it is a **revocation channel** over consents the
person actively gave. `kernel.set_my_contact_prefs` (`077:698`) mirrors the same discipline —
own-row, rate-limited, AO event append (`077:747-749`), audited `crm_contact.pref_changed`
(`077:751-756`).

**What the buyer is actually agreeing to** (CRM §5.3, the binding copy): an *unchecked* control
naming the org — "Let {Org} email me about their events. They only get your email if you tick
this." The demographics spec's dark-pattern ban list is adopted by reference: no pre-selected
default, no asymmetric affordances, no reward for ticking, no penalty for not, no re-asking after
withdrawal.

**What it unlocks — and the answer is narrow.** Consent is one of four conjuncts in the §5.1 gate:

```
emit_email(identity, :job_org_id) :=
      identity_contact_pref(identity).venue_email_contact = 'allow'
  AND org_contact_consent(identity, :job_org_id).state = 'granted'   -- the JOB'S org
  AND identity is live (not deactivated, not erased, not the sentinel)
  AND the reading role holds the CONTACT class for this scope
```

and `emit_name(identity, org) := emit_email(identity, org)` in an export — one predicate driving
both cells, so a future engineer cannot gate one and forget the other. Evaluated at a single
`gate_as_of` instant stamped at build claim.

**Consent unlocks the email cell and the exported name cell. Nothing else.** It does not unlock
phone (never, for anyone), legal name (never), demographics, a wider roster, or a longer
retention. And CRM §5.2 pins the rule that implementers get backwards: **consent is a fact about
a person and an organization, never a property of a ticket, so it never moves when a ticket
moves.** A p2p transferee is on the roster as a holder and off the mailing list. That is the
correct place for them.

**At launch, consent unlocks nothing at all**, because all three emitters are parked (§2).
Capture it anyway from day one — the record is the fan's own evidence in the dispute they are
most likely to have ("this venue emailed me and I never agreed"), and it is already built,
audited and append-only.

---

## 5. Promoter attribution — and it exposes no buyer

`venue.attribution` (`090:158-190`) carries `link_id`, `order_id`, `promoter_id`, `org_id`,
`event_id`, `code_id`, `method`, `touch_corroborated`, `self_deal_flag`, `terms_version`,
commission terms, `basis_minor`, `credited_amount_minor`, `resolution_reason`, `order_paid_at`.
**There is no buyer column, no identity column, no name, no email.** The link to a person exists
only transitively through `order_id`, and the table holds **no grant to any client role**
(`090:349-352`, AUTHZ-M9).

`venue.list_promoter_attributions(p_scope_kind, p_scope_id, p_filters, p_cursor)` (`090:1334`)
is the only back-office read. Authority (`090:1389-1392`): `venue_manager`, `venue_finance`,
**`venue_promoter_manager`**, `org_owner`, `org_admin`, `org_finance`, `org_promoter_manager`,
plus platform. Its projection (`090:1368-1381`) emits `when`, **`order_ref` =
`left(replace(order_id::text,'-',''), 8)`** — an eight-hex-character order reference, never an
attendee — plus `event_id`, `promoter_id`, aggregated `ticket_type`, `qty`,
`gross_attributed_minor`, `commission_minor`, `method`, `touch_corroborated`, `self_deal_flag`,
`terms_version`, `resolution_reason`, `displaced_promoter` (a *promoter's* name), `review_decision`,
`settled`. The migration comment names the rule at `090:1332`: *"the order REFERENCE, never an
attendee"*.

**What `venue_promoter_manager` needs**, and gets: which promoter drove which orders, how many
tickets, what commission basis, whether the attribution was self-dealt or displaced, and whether
it has settled. That is the complete commercial question.

**What it must not get**, and does not: any attendee name. CRM §3.1 records the reasoning — a
promoter manager asking "who did my promoters bring, by name" is asking to cross the two-tier
wall. Role-model H2/H3 and F12 mark both promoter-manager labels `·` on bulk roster and export.
Demographics §6 grants them the **event-level** holder-mix and explicitly denies the *promoter
axis*: a promoter-attributed sub-population at a club night is routinely 10–40 people, far below
k = 25, and a promoter-scoped aggregate is exactly the second axis that makes the event aggregate
differenceable. `venue.get_holder_mix` (`086:1317`) implements this — `venue_promoter_manager` is
in the allow-list, and the function has no promoter parameter.

**Verdict: promoter attribution as deployed is correct and needs no change.**

---

## 6. THE RECOMMENDED LAUNCH MATRIX

**Legend.**
**VISIBLE** — rendered by default in a surface the role already reaches, no extra grant, no extra act.
**MASKED** — the row is present but the cell is pseudonymous or truncated (`customer_ref`, 8-char `order_ref`, a bucketed count) — never the underlying value.
**ON REQUEST WITH AUDIT** — reachable only through a single-record or paged definer verb that writes `kernel.admin_audit` and consumes a rate budget; not on any default screen.
**NEVER** — no surface, no grant, no role, no exception.
**[P]** — currently unreachable because PFA-28 parks the emitter; the cell states the *post-un-park* posture, and is NEVER in practice at launch.
**[D]** — dark at launch behind a feature flag or an unratified obligation.

### 6.1 Operational attendee data — this can launch

| Role | Attendee name | Ticket status | Order number | Ticket type | Purchase time | Check-in status | Refund status | Payment amount | Promoter attribution |
|---|---|---|---|---|---|---|---|---|---|
| **`venue_manager`** | ON REQUEST WITH AUDIT [P] | VISIBLE | MASKED (8-char ref) | VISIBLE | VISIBLE | VISIBLE | VISIBLE | VISIBLE | VISIBLE |
| **`venue_finance`** | NEVER | VISIBLE | MASKED (8-char ref) | VISIBLE | VISIBLE | **NEVER** | VISIBLE | VISIBLE | VISIBLE |
| **`venue_box_office`** | ON REQUEST WITH AUDIT [P] | ON REQUEST WITH AUDIT [P] | ON REQUEST WITH AUDIT [P] | ON REQUEST WITH AUDIT [P] | ON REQUEST WITH AUDIT [P] | VISIBLE (guest list only) | NEVER | NEVER | NEVER |
| **`venue_marketing`** | MASKED (`customer_ref`) [P] | VISIBLE [P] | **NEVER** | VISIBLE [P] | VISIBLE [P] | VISIBLE [P] | NEVER | **NEVER** | NEVER |
| **`venue_promoter_manager`** | **NEVER** | NEVER | MASKED (8-char ref) | VISIBLE | VISIBLE | NEVER | NEVER | VISIBLE (commission basis only) | VISIBLE |
| **`venue_scanner`** | **NEVER** | VISIBLE (atom only) | **NEVER** | VISIBLE | **NEVER** | VISIBLE (this atom only) | **NEVER** | **NEVER** | **NEVER** |
| **`org_owner`** | ON REQUEST WITH AUDIT [P] | VISIBLE | MASKED (8-char ref) | VISIBLE | VISIBLE | VISIBLE | VISIBLE | VISIBLE | VISIBLE |
| **`org_admin`** | ON REQUEST WITH AUDIT [P] | VISIBLE | MASKED (8-char ref) | VISIBLE | VISIBLE | VISIBLE | VISIBLE | VISIBLE | VISIBLE |
| **`org_finance`** | NEVER | VISIBLE | MASKED (8-char ref) | VISIBLE | VISIBLE | **NEVER** | VISIBLE | VISIBLE | VISIBLE |
| **`org_marketing`** | MASKED (`customer_ref`) [P] | VISIBLE [P] | **NEVER** | VISIBLE [P] | VISIBLE [P] | VISIBLE [P] | NEVER | **NEVER** | NEVER |
| **`org_promoter_manager`** | **NEVER** | NEVER | MASKED (8-char ref) | VISIBLE | VISIBLE | NEVER | NEVER | VISIBLE (commission basis only) | VISIBLE |
| **`org_member`** | NEVER | NEVER | NEVER | NEVER | NEVER | NEVER | NEVER | NEVER | NEVER |

### 6.2 Marketing and CRM data — this stays behind PFA-28 and consent

| Role | Email | Phone | Demographic fields (individual) | Demographic aggregate | Export |
|---|---|---|---|---|---|
| **`venue_manager`** | ON REQUEST WITH AUDIT + CONSENT [P] | **NEVER** | **NEVER** | VISIBLE [D] | `operations_v1`, ON REQUEST WITH AUDIT [P][D] |
| **`venue_finance`** | **NEVER** | **NEVER** | **NEVER** | **NEVER** | **NEVER** |
| **`venue_box_office`** | ON REQUEST WITH AUDIT + CONSENT [P] | **NEVER** | **NEVER** | **NEVER** | **NEVER** |
| **`venue_marketing`** | ON REQUEST WITH AUDIT + CONSENT [P] | **NEVER** | **NEVER** | VISIBLE [D] | `audience_v1` only, ON REQUEST WITH AUDIT [P][D] |
| **`venue_promoter_manager`** | **NEVER** | **NEVER** | **NEVER** | VISIBLE, event grain only [D] | **NEVER** |
| **`venue_scanner`** | **NEVER** | **NEVER** | **NEVER** | **NEVER** | **NEVER** |
| **`org_owner`** | ON REQUEST WITH AUDIT + CONSENT [P] | **NEVER** | **NEVER** | VISIBLE [D] | `operations_v1`, ON REQUEST WITH AUDIT [P][D] |
| **`org_admin`** | ON REQUEST WITH AUDIT + CONSENT [P] | **NEVER** | **NEVER** | VISIBLE [D] | `operations_v1`, ON REQUEST WITH AUDIT [P][D] |
| **`org_finance`** | **NEVER** | **NEVER** | **NEVER** | **NEVER** | **NEVER** |
| **`org_marketing`** | ON REQUEST WITH AUDIT + CONSENT [P] | **NEVER** | **NEVER** | VISIBLE [D] | `audience_v1` only, ON REQUEST WITH AUDIT [P][D] |
| **`org_promoter_manager`** | **NEVER** | **NEVER** | **NEVER** | VISIBLE, event grain only [D] | **NEVER** |
| **`org_member`** | **NEVER** | **NEVER** | **NEVER** | **NEVER** | **NEVER** |

Org-grain CRM fields (13–15: `first_seen_at`, `events_attended_count`, `sessions_held_count`,
CRM §2.2) are ON REQUEST WITH AUDIT [P] for `org_owner`, `org_admin`, `org_marketing`, and
**NEVER** for every venue-grain label — including `venue_manager`. A venue-grain role must not
receive a number aggregated across events (CRM §3, X7 `·` for VMG/VMK).

### 6.3 Justification for every VISIBLE

| Cell | Operational need |
|---|---|
| ticket status — VMG/VFI/VSC/orgs | you cannot run a door or reconcile a night without knowing which tickets are live, voided or already scanned; the deployed grant already withholds `current_owner_id` (`080:429-433`), so this is a count of tickets, not a list of people |
| ticket type — all operational roles | routing at the rope (GA vs VIP), inventory reconciliation, and the tier line on a settlement |
| order number (masked) — VMG/VFI/orgs/promoter mgrs | the handle a customer reads off a confirmation email during a dispute; the 8-char truncation already implemented at `090:1372` is sufficient to disambiguate within a session and is not an enumeration handle |
| purchase time — VMG/VFI/orgs | fraud triage ("forty orders in ninety seconds"), refund-window arithmetic, and settlement cut-off |
| check-in status — VMG/VSC/VMK/orgs | the scanner needs it to refuse a duplicate; the manager needs the live count to decide whether to open a second door; marketing needs attended-vs-held to know what a campaign actually produced. **Denied to finance** — RLS §9.12 grades finance `D` on `venue.scan`, and the deployed policy `086:155-159` already omits them |
| refund status — VMG/VFI/orgs | a refunded ticket must not admit, and a refunded order must not settle |
| payment amount — VMG/VFI/orgs | settlement, reconciliation, and chargeback defence are the venue's own money |
| payment amount — promoter mgrs | **restricted to `gross_attributed_minor` / `commission_minor`** (`090:1375`) — the commission basis, never the attendee's card or the order total |
| promoter attribution — VMG/VFI/VPM/orgs | the entire commercial purpose of the promoter programme; `090:1334`'s projection carries an order *reference*, no attendee |
| demographic aggregate — VMG/VMK/VPM/OOW/OAD | the on-screen holder-mix card only, ≥ 25 responders, ≥ 2 buckets, every bucket ≥ 5, re-derived fail-closed at read (`086:1341-1348`). It informs creative; it never travels (X-3, X-7) |
| guest-list check-in — VBO | the venue wrote those names down itself; they are the venue's own record, not a fan's platform identity |
| attendee name / email — ON REQUEST WITH AUDIT | one person at a time, at a counter, in front of that person: will-call, a lost confirmation, a disputed ticket. Never a screen you can leave open, never a list you can print |

### 6.4 Justification for every NEVER

| Cell | Reason |
|---|---|
| **phone — every role, every surface** | CRM §2.3, restated at full strength: not a column, not a filter, not a hash, not a search key, not a match key, not a suppression key. There is no door or box-office question a phone number answers. `phone_number` is on the X-6 forbidden-identifier list (`supabase/ci/x6_forbidden.json`) and a CI gate fails the build if it appears in an export source |
| **legal name — every role** | 068 already removed it from the `authenticated` grant. CRM §2.3: *"a door verifies a government ID against a human, not against a CSV"* |
| **individual demographic value — every role including `platform_admin`** | X-1. `kernel.identity_demographic`'s client grant set is **empty, not reduced** (`077:357-359`), and demographics §7.1 admits no consent version that unlocks individual disclosure |
| **demographics — `org_finance`, `venue_finance`, `venue_box_office`, `venue_scanner`, `platform_support`, `platform_risk`** | demographics §6.1: audience composition is not money data, not a service datum, and not a risk signal. Granting it widens the blast radius of a compromised account for zero product gain |
| **check-in — finance roles** | RLS §9.12 grades finance `D` on `venue.scan`; the columns are **absent** from a finance read, not blank. Already true in the deployed policy |
| **money — both marketing labels** | CRM §3.1's load-bearing asymmetry: *finance sees money and no contact; marketing sees contact and no money; neither sees both.* Only `venue_manager`, `org_owner` and `org_admin` hold the union, and that union is the narrowest allow-list in the corpus |
| **contact — both finance labels** | the same asymmetry, run in the other direction. CRM export is a contact surface, not a money surface |
| **attendee name — promoter managers** | CRM §3.1: "who did my promoters bring, by name" crosses the two-tier wall. Their commercial need is fully served by the attribution surface |
| **roster and export — `venue_box_office`** | role-model F12 marks VBO `·` on bulk list/export. Stated honestly so nobody is surprised at 9 p.m.: **a box office cannot print a paper list.** A printed list is an unaudited export with none of §6's controls and a longer life than any of them |
| **export — `venue_finance`, `org_finance`, promoter managers, `venue_scanner`, `org_member`, all platform roles** | role-model H2/H3 mark both finance labels and both promoter-manager labels `·`. Platform bulk extraction is denied on the venue surface by CRM §3.2 / K-3 / D-8: it would file a platform action in a venue's history and give a compromised platform account the venue's rate limits |
| **everything except facts 1–6 — `venue_scanner`** | see §7 |
| **everything — `org_member`** | a directory membership, not a capability. No read policy in 080/082/086/090 names it |
| **`identity_id` / `buyer_id` in any venue-facing projection** | CRM §2.3, first entry: it is a cross-org join key; two orgs' files union on it and reconstruct a person's cross-venue attendance graph. This is the §10 R-1 gap |

---

## 7. What `venue_scanner` must NEVER see

The scanner is not a person. It is **a device at a door, frequently shared, frequently handed to
a contractor, frequently left unattended on a stool in a loud room.** It is the least controllable
principal in the system and must therefore have the smallest possible blast radius.

`venue_scanner` must **NEVER** see:

1. **Any attendee name** — from the manifest, from a lookup, from a search box, from a join.
2. **Any email address or phone number.**
3. **Any order number, order status, refund state, unit price, or order total.** Deployed
   correctly today: the scanner is absent from `venue_order_sel_venue` (`082:151-159`) and from
   `venue_order_item_sel_venue` (`082:223`), and the migration records the deliberate fail-closed
   choice at `082:130-138`.
4. **Any buyer or holder identity uuid.** `kernel.tickets.current_owner_id` is already withheld
   by the column grant (`080:429-433`) — that withholding is load-bearing and must not be relaxed.
5. **Any demographic value or aggregate.** Demographics §6: *"absolutely nothing"*.
   `venue.get_holder_mix`'s allow-list (`086:1317-1321`) correctly omits the scanner.
6. **Any door PIN or `pin_hash`.** Already withheld by the column grant at `086:50-51`.
7. **Any promoter, attribution, commission or settlement fact.**
8. **Any other venue's data, and any session other than the one with an open manifest.**
9. **A holder-grain view of any kind.** The manifest must stay **atom-grain**. The moment it
   groups by person it becomes a roster, and a roster on a shared tablet is the exact artefact
   the whole design refuses.
10. **A guest list.** `venue.guest_list` / `guest_entry` carry free-text names and are correctly
    scoped to `venue_manager` + `venue_box_office` (`086:206-209`, `086:229-235`).

What the scanner **does** get is §3.2's six facts, and the deployed `get_door_manifest`
(`086:843`) already returns exactly those and nothing more. **Change nothing here.**

Two lower-priority tightenings noted for 093 (§10 R-2, R-3): `venue.scan` is table-granted
(`086:153`), so a scanner reads `actor_identity_id` (a *staff* uuid) and `device_boot_id` — more
than the six facts, though not attendee data.

---

## 8. Default vs additional grant · what may be exported · what stays dark

### 8.1 By default (the role grant alone)

Ticket status · ticket type · check-in status (scanner and manager) · the door manifest's six
facts · order/money for `venue_manager`, `venue_finance` and the org back office · promoter
attribution for the six attribution-reading labels · own-venue staff roster (all six labels,
`080:344`) · own-row consent state for any fan (`kernel.list_my_org_contact_consents`, `082:660`).

### 8.2 Requires an additional grant, act or ratification

| Datum | What it additionally requires |
|---|---|
| any attendee **name** | the PFA-28 un-park (14-item `CRM_CUSTOMER_REF_CRYPTO` ratification) **and** a role holding IDENT for the scope. In an export, additionally the §5.1 gate |
| any attendee **email** | all of the above **plus the buyer's own affirmative per-org consent** (`kernel.org_contact_consent.state='granted'`) **plus** the master switch at `allow` **plus** a live identity **plus** the CONTACT class for the scope. Four conjuncts, fail-closed on any unknown |
| any **export artifact** | the template allow-list, the export lifecycle, `venue.assert_may_request` at request *and again* at download (EX-4 — the one predicate that keeps "neither sees both" true), and the un-park |
| any **demographic aggregate** | `catalog.platform_config['demographics.holder_mix_enabled'] = true` (**no such row is seeded in 078** — `get_holder_mix` reads `coalesce(v_flag,false)` at `086:1330-1332` and returns `{suppressed:true}`), **plus** ≥ 25 responders, ≥ 2 buckets, min bucket ≥ 5, re-derived fail-closed at read |
| any **order or money** datum | native issuance enabled (`078:1522`, currently `false`) — no order can exist until then |
| any **check-in** datum | native scanning enabled (`078:1523`, currently `false`) |

### 8.3 Export — who, and does it stay dark?

**Export must stay DARK at launch, for every role.** This costs nothing to enforce because it is
already enforced and cannot be turned on by configuration: `venue.build_export_rows` is one of
PFA-28's three parked emitters, so a claimed job records `state='failed'`,
`failure_code='build_error'` and `crm_export.fail` with reason
`customer_ref_crypto_unavailable`, returning zero rows; `finalize_export` refuses any non-running
job, so **no artifact can ever exist for a parked build**
(`POST_FREEZE_AMENDMENTS.md:2200-2206`). Enabling the surface would produce nothing but failed
jobs and a support queue.

Post-ratification, the frozen allow-lists (CRM §6.4, §3) are:

| Template | Columns | Who may request, download and revoke |
|---|---|---|
| `audience_v1` | fields 1–12; org grain adds 13–15 | `org_owner`, `org_admin`, `org_marketing` (org grain), `venue_manager`, `venue_marketing` (venue grain) |
| `operations_v1` | `audience_v1` + fields 16–21 (MONEY) | **`org_owner`, `org_admin`, `venue_manager` only** |

Download and revoke are scoped **by `template_id`, not only by grain** — a marketing label may
redeem exactly the jobs whose template it may request (`audience_v1` only), enforced by
re-evaluating the request-time predicate at download. `org_marketing` legitimately *sees* an
`operations_v1` job in the history panel and cannot download it. Without that one predicate the
finance/marketing asymmetry is a claim about a matrix rather than a property of the system.

**Never exportable by anyone, at any time:** `identity_id`, phone, legal name, payment
identifiers, credential internals (`ticket_atom_id`, `credential_version`, `signing_key_id`,
`serial_no`), door internals (`pin_hash`, `scan_device_id`, `device_boot_id`), the transfer
counterparty, platform-side fan state, `residency_region`/`kyc_ref`, any other org's data, and
**every demographic object, value, derivation or proxy**. The last is not a policy — it is a CI
gate: `scripts/ci/x6_gate.sh` greps the export sources case-insensitively against
`supabase/ci/x6_forbidden.json`'s 36 terms, verifies the §2.2 column manifest against the spec
table (exactly 21 columns), and runs a poison-directory positive control so a broken scanner
cannot pass silently. It additionally asserts (`x6_gate.sh:126-129`) that **087 creates no
extension**, enforcing PFA-28's no-pgcrypto ruling. Nothing in this recommendation adds a term to,
removes a term from, or otherwise touches that gate.

---

## 9. Audit — what must be logged, and where

**Where:** `kernel.admin_audit` (`077:236-247`). It is append-only — `revoke update, delete …
from service_role` (`077:259`) plus a BEFORE UPDATE OR DELETE guard trigger (`077:261-264`) — and
carries **zero grants and zero policies for any client role** (`077:257`). CRM §8.1 states why it
must not live in a venue-owned table: *the actor most likely to want an export record gone is the
venue*, and `kernel.admin_audit` is the only object a venue can neither read directly nor modify
at all. The venue's own history panel reads a projection through the dashboard's activity RPC,
never `before`/`after`.

**Must be logged:**

| Action | Status |
|---|---|
| `crm_contact.consent_granted` / `crm_contact.consent_withdrawn` | **already implemented** — `082:583-586`, `082:637-640`; actor is the data subject |
| `crm_contact.pref_changed` | **already implemented** — `077:751-756` |
| staff-role grant / revoke | **already implemented** — 080 Part 3 |
| `order.cancel` | **already implemented** — `082:518-522` (SN-SYSTEM sentinel actor) |
| `crm_lookup.attendee` — every single-record lookup, recording `(kind, outcome)` and **never the query value** | contracted, documented at `087:1412-1414`, delivered at un-park |
| `crm_lookup.platform_roster` — every platform-arm roster page | contracted, `087:1355` |
| `crm_export.request` / `.generate` / `.download` / `.revoke` / `.expire` / `.purge` / `.fail` | lifecycle live; `.fail` fires today under the park |
| `crm_export.denied` | **GAP** — no writer exists. Recorded as forward obligation "CRM denial witness" (E-68, `POST_FREEZE_AMENDMENTS.md:2276`). A refused attempt is more interesting than a successful one; an audit that records only successes cannot show an attacker probing scopes |
| a demographic-aggregate read | **GAP** — `venue.get_holder_mix` is `STABLE` and cannot write; recorded as PFA-27, noted in-line at `086:1341-1343`. Blocks flipping the demographics flag, not launch |

**Never in an audit row** (CRM §8.3, enforced by E-80's `^[A-Za-z0-9._:-]{1,64}$` bound on every
value that reaches the audit): a customer row, a name, an email, a `customer_ref`, a probed email
value, an `org_customer_key`, or any signed URL.

**One honest over-report to keep:** the download audit row is written in the same transaction that
authorises the URL, before the URL is returned. If the network then fails, the audit says a
download happened when no bytes arrived. That is the correct direction for an audit to be wrong,
and the alternative — a client-confirmed callback — is an attacker-controlled audit.

---

## 10. Does this need 093 work?

**Almost none. One item, and it is the important one.**

### Achievable with existing grants and policies, plus keeping the parked verbs parked

- The entire `venue_scanner` row of the matrix — the deployed door surface (`086:843`) already
  returns exactly the six minimum facts and no identity.
- The entire `venue_box_office`, `venue_promoter_manager`, `venue_marketing`,
  `org_promoter_manager` and `org_member` rows.
- Export dark for everyone — enforced by PFA-28's fail-closed builder; not configurable on.
- Attendee names and emails unreachable — enforced by the same park.
- Demographics dark — no `demographics.holder_mix_enabled` row is seeded, and
  `get_holder_mix` fails closed to `{suppressed:true}` on a missing flag (`086:1330-1332`).
- Consent capture, withdrawal, the master kill switch and their audit trail — fully built.
- Promoter attribution with no buyer identity — `090:1334`'s projection is already correct.
- Finance denied check-in — already true in `086:155-159`.
- `kernel.tickets` withholding `current_owner_id` — already true in `080:429-433`.

### Requires 093

**R-1 (REQUIRED before native issuance is enabled) — column-scope `venue."order"`.**
`082:129` grants SELECT at table grain, exposing `buyer_id` to `venue_manager` and
`venue_finance`; joined to `public.profiles` (readable on any row by any `authenticated` user
after `068:31-33`) this yields an unaudited, un-rate-limited, consent-free attendee-name roster
that bypasses `venue.list_attendees` entirely and hands over the exact cross-org join key
CRM §2.3 forbids (§1.3). **PFA-28's park does not close this — it only closes the audited door.**

Fix: a 093 package re-issues the `authenticated` grant as an explicit column list omitting
`buyer_id`, using verbatim the pattern 080 already applied to `kernel.tickets`:

```
revoke select on venue."order" from authenticated;
grant select (order_id, event_session_id, org_id, status, source, total_minor, currency,
              command_idempotency_key, attribution_candidate_code_id,
              attribution_candidate_link_id, created_at, updated_at)
  on venue."order" to authenticated;
```

`venue_order_sel_owner` (`082:140-142`) is a **policy predicate**, evaluated outside column ACLs,
so the buyer's own read is unaffected — this is the identical argument recorded at `080:420-428`
(I-4 / E-24). Migration 082 is immutable, so this is a new package, never an edit. No object
added, no policy changed, no behaviour widened. **Classification: IMPLEMENTATION FOLLOW-UP.**
Escalate to POST-FREEZE AMENDMENT only if RLS §9.7 is read as affirmatively *contemplating* a raw
identity uuid in the venue read; the CRM spec's §2.3 and §5.6 both argue the opposite.

**R-2 (RECOMMENDED, same package) — column-scope `venue.comp_allocation`.** `086:181` is a table
grant exposing `granted_to_identity` and `granted_to_name` to `venue_manager`. Same class as R-1,
much smaller blast radius. Note `granted_to_name` is a name the *venue* supplied, like a guest
list, so it may stay; `granted_to_identity` should be withheld.

**R-3 (OPTIONAL, lower priority) — column-scope `venue.scan`.** `086:153` is a table grant, so a
shared door device reads `actor_identity_id` and `device_boot_id`. Neither is attendee data, but
both exceed the six facts a door needs, and `device_boot_id` and `scan_device_id` are on the X-6
forbidden list for exports. Suggested grant:
`(scan_id, ticket_atom_id, event_session_id, direction, scan_type, result, offline_pending,
fraud_flag, manifest_id, manifest_version, occurred_at, server_receipt_at)`.

**Nothing else.** No new table, no new RPC, no new policy, no change to the X-6 gate, no change to
the parked verbs, and no change to any 076–092 byte.

---

## 11. Summary of the recommended posture

> **Operational attendee data can launch. Marketing and CRM data cannot, and does not need to.**

A venue partner at launch gets everything required to run a door and a box office: which tickets
are valid, which type, which have been used, which orders were placed and for how much, and which
promoter drove them. It gets **no attendee name and no attendee email**, because the mechanism that
would make those tenant-safe — the per-org `customer_ref` HMAC — has no ratified implementation,
and PFA-28's owner-signed ruling is that the readers fail closed rather than emit a weaker
identifier. That park is the strongest privacy control currently in the system and should be left
exactly where it is.

The door already meets the minimum: six facts, atom grain, no identity. Consent is already built,
already own-row-only, already append-only and already audited — capture it from day one even
though it currently unlocks nothing, because it is the fan's own evidence.

The single thing that must change before native issuance is enabled is a **column grant**, not a
policy and not a verb: `venue."order"` currently hands `buyer_id` to venue staff, and one join to
`public.profiles` turns that into the roster this entire document is designed to withhold.

# DECISION C — VENUE OPERATORSHIP TRANSFER

**Subject:** stale venue authority across a `catalog.venue.org_id` repoint
**Branch:** `feature/venue-native-and-product-v2` · **Corpus:** migrations `076`–`092` (IMMUTABLE)
**Method:** read-only static analysis. No SQL executed. Every claim carries `file:line`.
**Prior art:** `docs/product-v2/_research/venue_security_audit.md` finding **V-1** (P0, activation-blocking) ·
`docs/product-v2/ADVERSARIAL_REVIEW.md` finding **J-8** (confirmed defect, P1, not activation-blocking).

---

## 0. THE HEADLINE FINDING (neither prior document states it)

The corpus's own mitigation — the **E-76 current-operator conjunct** — **does not defend against the Alice
scenario at all.** It defends the opposite direction.

The conjunct is always of the form:

```sql
(select v.org_id from catalog.venue v where v.venue_id = <venue>) = <the scope object's org_id>
```

After Venue X moves from Org A to Org B:

| Scope object | `venue.org_id` | object `org_id` | E-76 conjunct | Alice (stale A staff, `staff_role` on X) |
|---|---|---|---|---|
| Org **B**'s new events/sessions/settlements at X | B | B | **TRUE** | **passes — E-76 gives ZERO protection** |
| Org **A**'s legacy events at X | B | A | FALSE | blocked |

So E-76 protects the **departing** operator's legacy rows from the **arriving** operator's org roles
(`has_org_role_over_venue` resolves the *new* `venue.org_id` — `080:93-103`). It does **nothing** about stale
staff over the new tenant, which is the scenario in the brief.

**Consequence:** the audit's remedy (a) — "make the E-76 conjunct universal" — is a fix for the *symmetric*
half only. The Alice half is closed by exactly one thing: **clearing or re-scoping `venue.staff_role` on
transfer** (the audit's remedy (b)). Option 3 as commonly framed is therefore **not a substitute** for
Option 2. This materially reorders the options below.

---

## 1. IS THE TRANSFER CALLABLE TODAY, AND BY WHOM?

**`catalog.update_venue(p_venue_id, p_patch, p_command_key)` — `078:623-742`.**

| Question | Answer | Evidence |
|---|---|---|
| Who may call the function at all? | `org_owner`/`org_admin` over the *current* operator, **or** `venue_manager` on the venue | `078:661-671` |
| Who may include `"org_id"` in the patch? | **`kernel.is_platform(array['platform_admin'])` only** | `078:688-691` |
| Reason code required? | **Yes** — a non-empty `reason_code` carried *inside the patch*; absent ⇒ `reason_required` | `078:692-695` |
| Target org validated? | Yes — must exist in `kernel.organization` | `078:697-699` |
| Audited? | Yes — `kernel.admin_audit` row `venue.update` with before/after including `org_id` | `078:726-737` |
| Where does `platform_admin` come from? | `kernel.platform_role` **or** the legacy `public.admin_users` allowlist | `077:468-487` |
| Is `public.admin_users` client-reachable? | **No.** RLS enabled; `REVOKE ALL … FROM PUBLIC, anon, authenticated`; no client write path anywhere in the repo | `033:102-135` |
| Can a venue operator do this themselves? | **No.** An `org_owner` calling the `org_id` arm gets `42501 insufficient_privilege: operatorship change is platform_admin only` — asserted by pgTAP **G20** | `078:688-691` · `supabase/tests/142:665-669` |
| Is there a client caller? | **None.** Repo-wide grep finds `update_venue` only in `078`, its rollback, and the pgTAP suites. No mobile/web/edge caller exists | repo grep |

**Verdict: the transfer is Snatch It staff only.** It is a deliberate, audited, reason-coded, platform-admin
tenancy move. It is not attacker-initiated. J-8 is correct on this point and I independently confirm each link.

**One caveat J-8 does not state:** `platform_admin` is satisfied by the *legacy* `public.admin_users` row set —
humans given "admin" in `033_marketplace_expansion` for **listing moderation** now hold operatorship-transfer
authority (`077:483-486`). That is the J-15 finding, and it widens the human blast radius of this verb beyond
whoever the team thinks holds Phase-2 platform authority.

## 2. IS A DIRECT TABLE `UPDATE` POSSIBLE, BYPASSING THE RPC?

**For client roles: no.**

- `catalog.venue`: `revoke all … from public, anon, authenticated`, then a **column-scoped SELECT-only** grant
  to `anon, authenticated` (`078:122-126`). No `INSERT`/`UPDATE`/`DELETE` grant exists for any client role.
- RLS is enabled and every policy on the table is `FOR SELECT` (`078:306-314`, `080:369-377`); the corpus's
  GP-1/GP-2 rule is that no client principal holds a write grant anywhere in `catalog` (`078:296-298`).
- Schema-level: `grant usage on schema catalog to anon, authenticated` only — USAGE confers nothing on its own
  (`076:75`).
- `venue.staff_role` is likewise `grant select` only, with the three read policies in `080:352-366`.

**For `service_role`/`postgres`: yes.** Neither is revoked, and Supabase's `service_role` carries BYPASSRLS.
Any holder of the service key, or anyone with SQL-editor/psql access as `postgres`, can
`update catalog.venue set org_id = …` with **no reason code, no audit row, and no RPC**. No edge function does
so today (`supabase/functions/*` contains zero `catalog.` references), so the only realistic actor is a human
on the SQL editor. **This is the path a freeze must also cover** — an operational policy that only says "don't
call the RPC" leaves it open.

## 3. THE ERASURE HOOK — IS IT THE ONLY WRITER THAT DELETES `staff_role`?

`kernel.on_identity_erased_staff(p_identity)` — `080:314-324`:

```sql
delete from venue.staff_role s where s.identity_id = p_identity;          -- INV #23
update venue.staff_role s set granted_by = null where s.granted_by = p_identity;  -- INV #24
```

Exhaustive writer census of `venue.staff_role` across all 18,561 lines of `076`–`092`:

| Site | Operation | Evidence |
|---|---|---|
| `venue.grant_staff_role` | `INSERT` | `080:224` |
| `venue.revoke_staff_role` | `DELETE` (one `(venue, identity, role)` row) | `080:288` |
| `kernel.on_identity_erased_staff` | `DELETE` by identity · `UPDATE granted_by := null` | `080:319`, `080:323` |

**That is the complete set.** Nothing keyed on `venue_id` ever deletes. `catalog.update_venue` does not touch
the table (`078:623-742` — verified line by line). **Confirmed: account erasure is the only venue-independent
eraser of staff authority, and it is keyed on the person, never on the venue.** A transfer leaves every row
intact.

Corollary: `venue.staff_role` has an `on delete restrict` FK to `catalog.venue` (`080:31`), so the venue row
cannot be deleted out from under the grants either.

## 4. WHAT 087 DOES DIFFERENTLY, AND WHY THE OTHERS DON'T

`087` (and, less visibly, `088` and `090`) carry the E-76 conjunct in their **RPC bodies**:

| Site | Form | Evidence |
|---|---|---|
| `venue.assert_may_request` (exports) | `venue.org_id = scope.org` ∧ `staff_role` probe | `087:650-659` |
| `kernel.close_settlement` | `venue.org_id = settlement.org_id` | `087:299-300` |
| `venue.list_export_jobs` | `venue.org_id = v_org` | `087:1299` |
| `venue.list_attendees` | `v_venue_bound` flag ANDed into all three venue arms | `087:1369-1374` |
| `venue.lookup_attendee` | inline conjunct | `087:1425-1428` |
| `catalog.cancel_event` | inline conjunct | `088:1628-1631` |
| `venue.review_attribution_flag` | conjunct against the **attribution's** org | `090:1172-1177` |

The amendment record explains the origin: **E-76** (`POST_FREEZE_AMENDMENTS.md:2249`) was raised while writing
the CRM export authority, because the export/roster surface would have handed the prior operator's rosters to
the new operator's staff. **E-88** (`:2262`) then extended it to the money arms. Both were written *as
amendments to `087`* — i.e. the conjunct was discovered late, in the package that happened to expose it, and
was applied **as a local correction to that package's verbs**, never promoted to the shared predicate
`kernel.has_venue_role` (`080:60-73`), which is where it would have become universal. `081`, `082` and `086`
were already frozen bytes by then, and `080`'s four AUTHZ-PKG1 read policies (`080:367-432`) predate it
entirely. The corpus never re-derived the conjunct as a global invariant — which is also why `087`'s **own RLS
policies** (`087:79-84`, `087:118-125`) do *not* carry it even though its RPCs do.

---

## 5. THE ALICE CAPABILITY TABLE

> **Scenario.** Organization A operates Venue X. Alice holds `venue.staff_role (X, alice, 'venue_manager')`.
> A `platform_admin` calls `catalog.update_venue(X, '{"org_id":"<B>","reason_code":"sale"}', key)`.
> After the call: `catalog.venue.org_id = B` · Org A's legacy events at X keep `event.org_id = A`
> (`078:878-880`, and `update_event` refuses the `org_id`/`venue_id`/`status` keys — `078:944-948`) ·
> `venue.staff_role` is untouched.

Legend — **REACHABLE**: works today against Org B's data with the flags as seeded. **BLOCKED**: some other
predicate, flag, park, or empty table stops it first.

### 5.1 Events

| Capability | Verb / policy | Authority test | Bound to operator? | Status |
|---|---|---|---|---|
| Read Org B's events at X **including `draft`** | `catalog_event_sel_venue` `080:381-390` | `has_venue_role(venue_id,['venue_manager'])` — the manager arm has no `status <> 'draft'` guard | **no** | **REACHABLE** |
| Read Org B's sessions | `catalog_event_session_sel_venue` `080:394-401` | `has_event_role(...)` → `has_venue_role` | **no** | **REACHABLE** |
| **Create** an event stamped `org_id = B` | `catalog.create_event` `078:829-897`, arm `078:869-871` | `has_venue_role(X,['venue_manager'])`; `org_id` is server-derived from the **current** `catalog.venue.org_id` `078:878-880` | **no** | **REACHABLE** — she writes *into* Org B's tenancy |
| Create/patch sessions | `catalog.create_event_session` `078:749`, arm `078:794` · `update_event_session` (079) | `has_venue_role(...,['venue_manager'])` | **no** | **REACHABLE** |
| Edit Org B's event marketing + title | `catalog.update_event` `078:901`, arm `078:967-972` | `has_venue_role`; title change post-draft needs a reason code `078:977-982` | **no** | **REACHABLE** |
| **Publish** — `draft→announced→on_sale→live→completed` | `catalog.publish_event` `081:899`, arm `081:930-933` | `has_venue_role(X,['venue_manager'])`; `on_sale` needs ≥1 ticket_type **with a batch** — which she can also create | **no** | **REACHABLE** — public-facing state change on another tenant's event |
| **Cancel** Org B's events at X | `catalog.cancel_event` `088:1612`, arm `088:1628-1631` | E-76 conjunct — but `venue.org_id = B = event.org_id`, so it **passes** | yes, **and it does not help** | **REACHABLE** (the void/refund cascade itself is inert — no atoms exist) |
| Cancel Org **A**'s legacy events at X | same | conjunct **fails** (`B ≠ A`) | yes | **BLOCKED** |

### 5.2 Pricing

| Capability | Verb | Authority | Bound? | Status |
|---|---|---|---|---|
| Create ticket types on Org B's events | `venue.create_ticket_type` `081:175`, arm `081:220-221` | `has_org_role_over_venue` ∨ `has_venue_role(X,['venue_manager'])` | **no** | **REACHABLE** |
| **Re-price** Org B's ticket types | `venue.set_ticket_type_price` `081:246`, arm `081:288-292` | same | **no** | **REACHABLE.** No feature flag. Binds only orders created *after* it (`081:299-302`) — so no retroactive money movement, but full control of the live price |

### 5.3 Inventory

| Capability | Verb | Authority | Bound? | Status |
|---|---|---|---|---|
| Create inventory batches | `venue.create_inventory_batch` `081:320`, arm `081:379-380` | `has_venue_role(X,['venue_manager'])` | **no** | **REACHABLE** |
| Change batch capacity | `venue.set_batch_capacity` `081:408`, arm `081:455-456` | same. Absolute floor `new >= held + sold` `081:461-465` | **no** | **REACHABLE** (floor is 0 today, so she can set any capacity) |
| Create a buyer hold | `venue.create_inventory_hold` `081:672`, arm `081:721-722` | same | **no** | **BLOCKED** — `feature.native_issuance_enabled` is checked first and seeds `false` (`081:702-707`, seed `078:1522`) |
| Release someone's hold | `venue.release_inventory_hold` `081:764`, arm `081:817` | `has_venue_role(X,['venue_manager','venue_scanner'])` | **no** | **BLOCKED in practice** — no holds can exist (the only creator is flag-gated) |
| Draw real inventory | `venue.reserve_primary_inventory` `081:527` | — | — | **BLOCKED** — flag checked before any counter mutation `081:579-588` |

### 5.4 Orders

| Capability | Policy | What it exposes | Bound? | Status |
|---|---|---|---|---|
| Read Org B's orders at X | `venue_order_sel_venue` `082:150-159` | `grant select on venue."order" to authenticated` is **not** column-scoped (`082:129`), so the policy exposes **`buyer_id`, `total_minor`, `currency`, `status`, `source`, `command_idempotency_key`, both attribution-candidate columns** | **no** | **BLOCKED today** — the table is empty: the sole writer `venue.create_primary_checkout` needs a hold, and holds are flag-gated. **Fully reachable on activation.** |
| Read order line items | `venue_order_item_sel_venue` `082:222-229` | `ticket_type_id`, `quantity`, `unit_price_minor` | **no** | same |
| Read `kernel.tickets` for Org B's sessions | `kernel_tickets_sel_venue` `080:407-417` | column-scoped: **`current_owner_id` is revoked** from `authenticated` (`080:427-432`), so no buyer identity | **no** | **BLOCKED today** — no atom can be minted: `kernel.provision_signing_key` hard-raises (`083:375-383`) |
| Cancel a pending order | `venue.cancel_pending_order` `082:478` | **zero in-body authorization** — walled only by a `service_role`-only grant whose delivery is an open owner decision (PFA-15, `082:469-476`) | n/a | **BLOCKED** by grant, but note this is a separate open risk |
| Refund | `kernel.refund` `085:~907-919` | **every venue label is forbidden by construction** (MONEY §6.1): buyer ∨ `org_owner`/`org_finance` ∨ platform only | n/a | **BLOCKED — structurally, not incidentally** |

### 5.5 Attendees

| Capability | Verb | Authority | Bound? | Status |
|---|---|---|---|---|
| Roster listing | `venue.list_attendees` `087:1359` | E-76 bound (`087:1369-1374`) — **conjunct passes for Org B** | yes, ineffective | **BLOCKED** — hard PFA-28 park: raises `customer_ref_crypto_unavailable` after authz, emitting zero data (`087:1400-1402`) |
| Single-attendee lookup | `venue.lookup_attendee` `087:1417` | E-76 bound `087:1425-1428` — passes for Org B; marketing labels denied | yes, ineffective | **BLOCKED** — same park `087:1439-1441` |
| CRM export request | `venue.request_export` `087:681` via `assert_may_request` `087:613-668` | `venue_manager` is on **both** template allow-lists (`audience_v1`, `operations_v1`); E-76 bound — passes for Org B | yes, ineffective | Job row can be **created**; `venue.build_export_rows` is parked and emits nothing (`087:910-919`) ⇒ **no data** |
| Holder mix (aggregate demographics) | `venue.get_holder_mix` `086:1311`, arm `086:1319` | `has_venue_role(X,['venue_manager','venue_marketing','venue_promoter_manager'])` | **no** | **BLOCKED in practice** — nothing to aggregate without tickets |

### 5.6 Door

| Capability | Verb | Authority | Bound? | Status |
|---|---|---|---|---|
| **Open** a door manifest on Org B's session | `venue.open_door_manifest` `086:728`, arm `086:745-750` | `has_venue_role(X,['venue_manager'])` | **no** | **REACHABLE NOW.** Entry count is `count(*)` over `kernel.tickets` = 0, so it opens fine with no inventory. **First open calls `catalog.engage_door_freeze` and `market.on_door_freeze_engaged` (`086:788-792`)** — it stamps `door_open_at`, which is a **one-way, unfreezable** state (`close_door_manifest` "does NOT unfreeze, does NOT touch door_open_at", `086:809-810`) and permanently freezes the schedule (`086:481-483`) |
| Close it | `venue.close_door_manifest` `086:811`, arm `086:819-822` | same | **no** | **REACHABLE** |
| Set the door schedule | `catalog.set_session_door_schedule` `086:474`, arm `086:487-490` | same | **no** | **REACHABLE** |
| Read manifests / entries / deltas / scan ledger | `086:317-318`, `350-352`, `392-394`, `155-158` | `has_venue_role(X, [...])` | **no** | **BLOCKED in practice** — empty without tickets |
| Mint door PINs, register/disable scan devices, mint & revoke door sessions | `086:918`, `932-939`, `1004-1009`, `1017-1025`, `955`, `971-978` | `has_venue_role(X,['venue_manager'])` | **no** | **REACHABLE NOW** — credentials for another tenant's door, no tickets required |
| Record a scan | `venue.record_scan` `086:1070`, arm `086:1083` | — | **no** | **BLOCKED** — `feature.native_scanning_enabled` is `false` (`086:1077`, seed `078:1523`) |
| **Allocate** comps | `venue.allocate_comp` `086:1154`, arm `086:1161-1163` | `venue_manager` only, single actor, **no AAL2 step-up, no per-staff cap** | **no** | **REACHABLE NOW** — writes a `comp_allocation` row against Org B's batch |
| **Issue** comps (mint free tickets) | `venue.issue_comp` `086:1172`, arm `086:1182-1184` | `venue_manager` only | **no** | **BLOCKED** — requires an active `kernel.signing_key` (`086:1199-1201`), and provisioning hard-raises (`083:375-383`) |
| Guest lists: create, upsert, remove, check in | `086:1214-1220`, `1229-1238`, `1256-1266`, `1274-1285` | `venue_manager`/`venue_box_office` | **no** | **REACHABLE NOW** — no ticket dependency |

### 5.7 Staff

| Capability | Verb | Authority | Bound? | Status |
|---|---|---|---|---|
| Grant the five **non-manager** labels at X (`venue_finance`, `venue_box_office`, `venue_marketing`, `venue_promoter_manager`, `venue_scanner`) | `venue.grant_staff_role` `080:120`, arm `080:200-206` | `has_venue_role(X,['venue_manager'])` | **no** | **REACHABLE NOW.** Self-grant is refused (`080:152-155`), so she seats **confederates**, not herself. This is the persistence amplifier — and it is how the `venue_finance` money arms below become reachable |
| Grant `venue_manager` | same, tier guard `080:190-198` | org tier or platform only; a venue_manager attempt raises `tier_guard` | n/a | **BLOCKED** |
| **Revoke any label at X, including `venue_manager`** | `venue.revoke_staff_role` `080:255`, arm `080:277-282` | `self` ∨ `has_venue_role(X,['venue_manager'])` ∨ org tier ∨ platform. Deliberately asymmetric; **no last-manager floor** (`080:262-268`) | **no** | **REACHABLE NOW** — she can strip every manager Org B seats. Org B's `org_owner` can re-grant, so this is disruption, not permanent lockout |

### 5.8 Settings

| Capability | Verb | Authority | Bound? | Status |
|---|---|---|---|---|
| Rename / re-address / re-capacity Venue X | `catalog.update_venue` `078:623`, venue arm `078:667-669` | `has_venue_role(X,['venue_manager'])` | **no** | **REACHABLE NOW** — she still holds the venue arm of the very verb that moved the venue |
| Re-point `org_id` herself | `078:688-691` | `platform_admin` only | n/a | **BLOCKED** |
| Change `approval_status` | `078:676-682` rejects the key; `catalog.approve_venue` `078:564` is `platform_admin` only (`078:585-588`) | n/a | **BLOCKED** |
| **Set the resale policy** (mode, `price_cap_bps`, **`royalty_bps`**) at venue *or* event scope | `catalog.set_resale_policy` `078:1318`, arm `078:1377-1379` | `has_venue_role(v_venue,['venue_manager'])`, venue resolved from `p_scope_id` | **no** | **REACHABLE NOW.** This is a **money-shaping** setting on another tenant's venue — the royalty rate that will govern their resale revenue |
| Platform config | `catalog.set_platform_config` `078:1048` | `platform_admin` only (`078:1082-1086`); **creates no new key** (`078:1094-1096`) | n/a | **BLOCKED** |

### 5.9 Promoters (not in the brief's list, but the widest escalation found)

| Capability | Verb | Authority | Status |
|---|---|---|---|
| Create/update promoters **for Org B org-wide** | `venue.create_promoter` `090:414`, arm `090:427-430` · `update_promoter` `090:504-506` | `has_org_role(B,[...])` ∨ `exists(catalog.venue v where v.org_id = B and has_venue_role(v.venue_id,['venue_manager','venue_promoter_manager']))` | **REACHABLE NOW.** Note the shape: a venue role on **one** venue of Org B confers authority at **org grain**, not venue grain — Alice's authority is not even confined to Venue X |
| Promoter links, codes, bulk codes, code status/scope/window | `090:576-577`, `690-692`, `772-774`, `849-851`, `876-878`, `915-917` | same shape | **REACHABLE NOW** — includes **commission terms (`bps`)**: money-shaping |
| Read Org B's whole promoter program | `090:362-367`, `380-382`, `393-395` | same shape | **REACHABLE NOW** |
| Read the attribution ledger | `venue.list_promoter_attributions` `090:1334`, arm `090:1353-1356` | venue arm, **no E-76 bind** | **REACHABLE** (ledger empty today) |
| Adjudicate attribution flags | `venue.review_attribution_flag` `090:1160`, arm `090:1172-1177` | E-76 bound — **passes for Org B** | **REACHABLE** (ledger empty today) |

### 5.10 Future money

| Capability | Verb | Authority | Status |
|---|---|---|---|
| Open a settlement for Org B at X | `venue.open_settlement` `087:227`, arm `087:237-240` | **`venue_finance`** ∨ org money roles; then re-binds `venue ∈ org` (`087:253-256`) — passes, since `venue.org_id = B` | **BLOCKED for Alice directly** (she is `venue_manager`) — but **reachable via a `venue_finance` confederate she can seat** (§5.7). Settlements close at net = 0 today (both line seams return zero rows at 087) |
| Close a settlement | `kernel.close_settlement` `087:289`, arm `087:299-302` | `venue_finance` **∧ E-76** (passes for B) ∨ `org_finance` ∨ `platform_admin` | same — reachable via confederate, inert today |
| Read settlement headers & lines for Org B at X | `venue_settlement_sel_venue` `087:83-84` · `venue_settlement_line_sel_venue` `087:123-125` | `has_venue_role(venue_id,['venue_manager','venue_finance'])` — **these two RLS policies carry NO E-76 conjunct even though 087's RPCs do** | **REACHABLE** directly by Alice once settlements exist |
| Request an org payout | `kernel.request_org_payout` `087:408`, arm `087:416-418` | `has_org_role(B,['org_owner','org_finance'])` — **no venue arm at all** | **BLOCKED — structurally** |
| Refund | `kernel.refund` `085:907-919` | every venue label forbidden | **BLOCKED — structurally** |
| Pay promoter commission | `kernel.pay_promoter_commission` `090:1401` | settlement-scoped | **BLOCKED** (commission payouts are HELD by policy) |

### 5.11 Summary of what Alice actually holds

**Reachable today, with the flags exactly as seeded and no tickets in existence:**

1. Full read of Org B's event catalogue at Venue X, **including drafts**.
2. **Create** events inside Org B's tenancy; edit, session, and **publish** them through `on_sale`/`live`.
3. **Cancel** Org B's events at Venue X (E-76 does not block this direction).
4. Full pricing and capacity authority over Org B's inventory at Venue X.
5. **Set the resale policy, including `royalty_bps`**, at venue and event scope.
6. Open/close door manifests — **irreversibly engaging the door freeze** on Org B's sessions.
7. Mint door PINs, register scan devices, mint door sessions for Org B's venue.
8. Allocate comps; create and check in guest lists.
9. Seat five staff labels for Org B's venue and **revoke every manager Org B seats**.
10. Org-wide authority over **Org B's entire promoter program**, including commission terms.
11. Rename/re-address Venue X.

**Blocked today, but only by darkness (all become live on activation):** order and ticket reads (incl.
`buyer_id`, `total_minor`, `command_idempotency_key`), hold create/release, scan recording, comp **issuance**,
manifest/scan-ledger reads, settlement reads and the venue_finance settlement verbs.

**Blocked structurally (would survive activation):** operatorship re-point, venue approval, platform config,
minting `venue_manager`, refunds, payout requests — and all of Org **A**'s legacy rows behind the E-76 arms.

**Symmetric leak, same root cause:** Org B's `org_owner` immediately acquires pricing, capacity, publish,
door and staff authority over **Org A's still-open legacy events** at Venue X, because
`has_org_role_over_venue` resolves the *new* `catalog.venue.org_id` (`080:93-103`) and the `081`/`082`/`086`
consumers apply no conjunct. This is the half E-76 was written for, and it is unfixed everywhere E-76 is
absent.

---

## 6. SEVERITY VERDICT

**P1 — a correctness defect in a contracted, platform-only operation. Not activation-blocking. But the
adversarial review under-states the reachable blast radius, and the audit's proposed fix is half wrong.**

Where J-8 is right:
- The `org_id` arm is genuinely `platform_admin`-only, reason-coded and audited. Verified independently.
- `public.admin_users` is genuinely unreachable by `anon`/`authenticated`. Verified.
- There is no client caller of `update_venue` anywhere in the repo. Verified.
- No attacker can *initiate* the state. Correct.

Where J-8 is wrong or incomplete:
1. **"Most consequences sit behind the signing-key block; the subset reachable today is pricing and capacity
   writes."** Understated. Eleven distinct capability classes are reachable today with zero tickets, including
   **event creation inside the new tenant**, **publishing to `on_sale`**, **event cancellation**, **resale
   royalty configuration**, **irreversible door-freeze engagement**, **door credential minting**, **staff
   revocation**, and **org-wide promoter/commission authority**.
2. **It treats the E-76 arms as mitigating.** They do not mitigate the stale-staff direction at all (§0). The
   review cites `087` binds as reducing exposure; for Alice-over-Org-B every one of them evaluates true.
3. **It does not identify `grant_staff_role` as an amplifier.** A stale manager seats a `venue_finance`
   confederate, which is exactly the label that unlocks the settlement verbs on activation.
4. **It does not identify the `service_role`/`postgres` direct-UPDATE path** (§2), which an
   RPC-level or policy-level control does not cover.

Where the audit is wrong: its remedy (a) — the universal conjunct — closes the *symmetric* half only. Calling
it "the fix" for V-1 would leave the headline scenario fully open.

**Practical severity today is low** because the state cannot arise without a deliberate Snatch It action, and
Snatch It controls whether that action is taken. **Latent severity is high** because the moment the first
transfer happens the state is silent, permanent, and produces no error anywhere.

---

## 7. THE THREE OPTIONS

### OPTION 1 — Freeze venue operatorship transfers for launch

**Does the freeze mechanically close it? YES — completely, and this is provable from the writer census.**

The vulnerability requires exactly one precondition: `catalog.venue.org_id` differs from what it was when the
`staff_role` rows and `catalog.event.org_id` values were written. I enumerated every writer:

| Alternative path | Can it produce the divergence? | Evidence |
|---|---|---|
| **A second `venue.org_id` writer** | **No.** `update catalog.venue … set org_id` appears exactly once in the whole corpus | `078:701` (sole site; grep over all 18,561 lines) |
| **A venue created under the wrong org** | **No divergence.** `catalog.create_venue` requires `has_org_role(p_org_id,['org_owner','org_admin'])` and stamps `org_id = p_org_id` (`078:531-533`, `078:550-552`). Events at that venue then get the *same* org (`078:878-880`). Wrong-org creation is a **billing/identity** error, not an authority-divergence: `event.org_id ≡ venue.org_id` still holds. The corrective path without transfers is archive-and-recreate | `078:510-559` |
| **An org merge** | **No such verb exists.** `077` has `create_organization`, `update_organization`, `set_org_status`, `set_org_connect_ref`, invite/accept/change-role/remove-member — **no merge, no re-parent, no org-id rewrite** | `077:767-1440` census |
| **An org status change** | **No.** `kernel.set_org_status` writes only `kernel.organization.status`; it touches neither `catalog.venue` nor `venue.staff_role`, and no venue predicate reads org status | `077:880-946` |
| **A venue re-approval** | **No.** `catalog.approve_venue` writes only `approval_status` | `078:564-618` |
| **`update_event` re-pointing an event** | **No.** `org_id`, `venue_id`, `status` are all outside the writable key set and raise `unwritable_key` **before** any authority test | `078:944-948` |
| **A second `catalog.event` insert site** | **No.** One insert, org server-derived | `078:879` (sole site) |
| **Erasure / deletion sweep** | **No.** Removes authority, never repoints it | `080:314-324` |
| **Direct SQL by a venue operator** | **No.** No client role holds any write grant on `catalog.venue` (§2) | `078:122-126` |
| **Direct SQL as `service_role`/`postgres`** | **YES — the one hole.** BYPASSRLS + owner rights; no reason code, no audit row | §2 |

**Therefore: `event.org_id ≡ venue.org_id` is an invariant of the system as long as no transfer occurs, and
stale `staff_role` is harmless while the venue never changes hands.** The freeze fully closes the
vulnerability — **provided it also covers the direct-SQL path.** An operational policy that names only the RPC
does not.

- **Advantages:** zero code, zero migration, zero frozen bytes touched, immediately effective, does not
  interact with any dark rail, trivially auditable (the `venue.update` audit rows with a changed `org_id` are
  the complete evidence set).
- **Disadvantages:** it removes a real capability from the product. Venue-changes-hands is a normal event in
  nightlife (leases, sales, management-company changes). The workaround — archive the old venue, create a new
  one under the new org, re-grant staff, recreate events — orphans history, breaks continuity of the venue's
  identity to buyers, and is manual.
- **Failure modes:** (i) **policy drift** — the freeze is a promise, and promises degrade; a platform_admin who
  wasn't told will make the call and hit no error; (ii) the **`admin_users` allowlist** means the set of people
  who *can* make the call is wider than the set who know the policy (J-15); (iii) **direct SQL** bypasses any
  RPC-level control; (iv) it does **not** address the equally-unbound symmetric direction if a divergence ever
  arises another way (e.g. a data-repair script).
- **Launch implications:** none. Nothing in the launch scope needs a transfer.

### OPTION 2 — Atomic transfer that re-scopes or revokes prior authority

What a correct `093` `catalog.update_venue` `org_id` arm would have to do, in the same transaction, under the
row's existing `for update` (`078:653-656`):

1. `delete from venue.staff_role where venue_id = p_venue_id` — **capture the deleted rows first** and write
   them into a `kernel.admin_audit` `venue.operatorship.transfer` row (`before` = the full roster) so the move
   is reconstructible. This is the step that closes the Alice half.
2. Revoke live door credentials scoped to the venue: `venue.door_pin`, `venue.scan_device`, any open
   `door_session` — otherwise a physical scanner keeps working across the tenancy boundary (`086:53`, `086:108`).
3. Refuse the move when the venue has **live obligations** under the departing org — an `open` settlement
   (`venue.settlement.status = 'open'`), an open door manifest, an unexpired inventory hold, a `pending` order.
   A transfer mid-episode is a money-boundary hazard, and the corpus has no compensating machinery for it.
4. Decide and record the **legacy-event ruling**: Org A's events keep `org_id = A` (E-76 already fences them
   from Org B's staff, but the `081`/`082`/`086` consumers do **not**), so either (a) also add the conjunct
   there — remedy 3b below — or (b) refuse the transfer while any non-terminal Org A event remains at the venue.
   Option (b) is far smaller and is the one I would take.
5. Emit a notification to both orgs' owners.

**Authorable as a `093` follow-up without touching frozen bytes? YES.** `catalog.update_venue` is
`create or replace` (`078:623`), its ACL survives replacement, and `093` is the sanctioned forward channel.
Every table it must write already exists. The **only** thing that needs owner sign-off is that this is a
**normative behavior change** to a frozen contract — freeze §2.6/§4 require a **POST-FREEZE AMENDMENT** with an
owner signature, not merely an implementation follow-up.

- **Advantages:** restores the capability with correct semantics; makes the audit trail complete; the
  re-grant-from-scratch discipline is the right security posture for a tenancy move anyway.
- **Disadvantages:** it is real work with real edge cases (steps 2–4), needs its own pgTAP fixture, and it is a
  post-freeze amendment.
- **Failure modes:** a partial implementation (purging `staff_role` but not door credentials, or not fencing
  live settlements) reads as "fixed" while leaving a narrower version of the same hole. Purging without
  capturing the roster in the audit row destroys the operator's ability to re-seat their team.
- **Launch implications:** unnecessary for launch. Required before the **first** transfer.

### OPTION 3 — A different ownership model

**3a — event-scoped rather than venue-scoped authority.** `venue.staff_role` becomes `(venue_id, event_id?)`
or a new event-grain grant table. This is a **schema and role-model change** touching `080` (the table, the
four predicates, both grant/revoke verbs, three RLS policies) and every consumer in `081`/`082`/`086`/`087`/
`090`. It contradicts `080:76-88`'s explicit design statement — *"no table stores an 'event role', so there is
no second source of venue authority"* — and ROLE_MODEL §3.4. **Reject:** a full post-freeze re-architecture of
the venue plane to fix a platform-only operation, with an enormous regression surface, and it does not even
address the case cleanly (a stale grant on a *pre-transfer* event is still stale).

**3b — make the current-operator conjunct universal.** Promote E-76 into a `093` helper
`kernel.has_venue_role_bound(p_venue, p_org, p_roles)` and `create or replace` the `081`/`082`/`086` bodies
plus `drop/create` the four `080` policies to use it. **Per §0, this does NOT fix the Alice scenario** — the
conjunct is satisfied for the new operator's own rows. It fixes the **symmetric** half (Org B reaching Org A's
legacy events) and makes the model internally consistent. It is a genuinely good hygiene change, and it is a
**complement to Option 2, never a substitute.**

- **Advantages (3b):** consistency; removes the "why does 087 bind and 081 not" trap for future implementers;
  closes the symmetric direction permanently.
- **Disadvantages (3b):** touches ~15 call sites and 4 policies across four packages — a wide `093` with a wide
  regression surface, for a direction that Option 2 step 4(b) closes with a single refusal clause.
- **Failure modes (3b):** shipping it and *believing the case is closed* — the most dangerous outcome in this
  whole analysis, because the conjunct looks like a fix and tests green while Alice retains everything.
- **Launch implications:** none; do not attempt before launch.

---

## 8. RECOMMENDATION

**Adopt OPTION 1 for launch — the freeze — with the enforcement mechanism specified below. Schedule OPTION 2
as the gate on the first real transfer. Fold 3b into that same `093` only if the transfer verb chooses step
4(a) over 4(b).**

The freeze is correct because it is *mechanically complete* (§7, the writer census), not merely convenient. It
is the rare case where an operational control is provably equivalent to a code fix, because the vulnerable
state has exactly one entry point.

### 8.1 THE EXACT ENFORCEMENT MECHANISM

A pure operational policy is **not sufficient** — a platform_admin who has not read the policy gets no error.
Three layers, in this order:

**Layer 1 (primary) — a `093` `CREATE OR REPLACE` that hard-refuses the `org_id` arm.**

`supabase/migrations/093_freeze_operatorship_transfer.sql`, replacing `catalog.update_venue` with a body
identical to `078:623-742` except that the `if p_patch ? 'org_id' then` block (`078:688-704`) becomes:

```sql
if p_patch ? 'org_id' then
  raise exception 'precondition_failed: operatorship_transfer_frozen — venue operatorship transfer is
    suspended pending the 093+ atomic re-scoping verb (Decision C). Contact the platform owner.'
    using errcode = 'P0001';
end if;
```

Placed **after** the unwritable-key loop so the error is stable and carries no authority oracle. Everything
else in the function — the venue arm, the profile-edit arms, the audit row — is byte-identical to `078`.

Why this layer and not a revoked grant: revoking `EXECUTE` on `update_venue` would also kill the benign
profile edits (`name`, `address`, `capacity_hint`) that the venue arm legitimately serves (`078:706-724`) and
that pgTAP **G22** asserts (`supabase/tests/142:674-676`). The block must be surgical to the `org_id` key.

Why not a `platform_config` flag: **`catalog.set_platform_config` cannot create a new key** — *"THIS FUNCTION
CREATES NO NEW KEY — a key that no code reads is a config row that lies"* (`078:1094-1096`), and every key must
be seeded by a migration. A flag-based freeze would itself require a `093` migration to seed the key, so it
buys nothing over the direct refusal while adding a runtime-mutable surface. **Do not build a flag.**

**Classification of Layer 1: IMPLEMENTATION FOLLOW-UP.** It **narrows** a contracted verb without changing any
normative decision — the corpus never rules that transfers must be *available*, and RLS §11.1a's only ruling is
that the arm is `platform_admin`-only and audited. Freeze §2.5 covers "engineering choices the corpus already
uniquely determines"; a temporary, reversible refusal that strictly reduces authority is squarely inside it.
**Reversing it later — the real Option 2 verb — IS a POST-FREEZE AMENDMENT**, because that adds behavior
(`staff_role` purge, credential revocation, obligation fencing) the frozen corpus does not describe.

**Layer 2 — cover the `service_role`/`postgres` direct-SQL path. OPERATIONAL CONFIG + OWNER POLICY.**

Layer 1 cannot bind a superuser. Add:
- A written owner policy: *no direct `UPDATE` of `catalog.venue.org_id` outside the sanctioned RPC*, listed in
  the runbook alongside the existing "migrate-then-functions" deploy rule.
- A **detective control**, since a preventive one is impossible against `postgres`: a periodic assertion that
  `catalog.event.org_id` equals its venue's `org_id` for every event (see Layer 3's second query) — this
  catches a direct-SQL transfer after the fact, which is the best available.
- Confirm the `public.admin_users` roster is the intended platform_admin set, given J-15: those rows were
  granted for **listing moderation** in `033` and now carry operatorship authority (`077:483-486`).

**Layer 3 — CI assertions. IMPLEMENTATION FOLLOW-UP.**

In `supabase/tests/142_phase2_catalog_config_and_seeds.sql`, beside the existing G20 (`142:665-669`), add:

```sql
-- G20a: the operatorship arm is FROZEN (Decision C, migration 093).
SELECT throws_ok(
  format($$SELECT catalog.update_venue(%L::uuid,'{"org_id":"%s","reason_code":"sale"}'::jsonb,'ck-frz-1')$$,
         tap._fetch142('venue'), tap._fetch142('org')),
  'P0001', NULL, 'G20a: operatorship transfer is frozen (093)');
```

matched on the message, not on "any error" — the RED-B lesson recorded at `142:662-664`, where a bare matcher
let a *different* failure pass as success.

Plus a standing structural invariant, runnable in CI and as the Layer-2 detective control:

```sql
-- INV-C1: no event may be stamped to an org other than its venue's current operator.
SELECT is_empty(
  $$SELECT e.event_id FROM catalog.event e
     JOIN catalog.venue v ON v.venue_id = e.venue_id
    WHERE e.org_id <> v.org_id$$,
  'INV-C1: event.org_id = venue.org_id for every event (no operatorship divergence)');
```

This single query is the **complete detector** for the vulnerable state, by §7's census. G22 must keep passing
unchanged — that is the proof the freeze is surgical.

### 8.2 HOW THE FREEZE IS VERIFIED

1. `093` applies; pgTAP **G20a** green, **G20/G21/G22** unchanged and green.
2. **INV-C1** green on production.
3. `select count(*) from kernel.admin_audit where action='venue.update' and before->>'org_id' is distinct
   from after->>'org_id'` returns **0** — no transfer has ever occurred (this is also the historical check:
   run it *before* applying 093 to confirm no legacy divergence already exists).
4. Migration ledger parity per the standing rule (`db push --include-all`, `git_branch` empty,
   `AUTODEPLOY-VERIFIED-OFF` on the PR).

### 8.3 HOW THE FREEZE IS LIFTED

The freeze is lifted **only** by shipping Option 2 — it is not a config toggle and there is deliberately no
runtime switch:

1. File a **POST-FREEZE AMENDMENT** (`PFA-<n>`) describing the atomic transfer semantics: `staff_role` purge
   with roster capture, door-credential revocation, live-obligation refusal, and the legacy-event ruling
   (4(a) universal conjunct vs 4(b) refuse-while-legacy-events-exist — recommend **4(b)**). Owner signature
   required.
2. Ship `094_atomic_operatorship_transfer.sql` — `create or replace catalog.update_venue` implementing it,
   plus a pgTAP fixture that transfers a venue with a seeded roster and asserts the roster is gone, the audit
   row carries it, and INV-C1 still holds.
3. Replace G20a with a positive test that a platform_admin transfer **succeeds** and leaves zero `staff_role`
   rows on the venue.
4. Layers 2 and 3's INV-C1 stay forever.

### 8.4 CLASSIFICATION SUMMARY

| Element | Class |
|---|---|
| `093` refusal of the `org_id` arm | **IMPLEMENTATION FOLLOW-UP** (narrows a contracted verb; no normative change) |
| Written no-direct-SQL policy + `admin_users` roster review | **OWNER POLICY** |
| Detective INV-C1 sweep on production | **OPERATIONAL CONFIG** |
| pgTAP G20a + INV-C1 | **IMPLEMENTATION FOLLOW-UP** |
| The eventual atomic transfer verb (Option 2) | **POST-FREEZE AMENDMENT** |
| Universal E-76 conjunct (Option 3b), if adopted | **POST-FREEZE AMENDMENT** |
| Event-scoped authority (Option 3a) | **POST-FREEZE AMENDMENT — rejected** |
| Alice's own severity | **P1**, not activation-blocking, **must be closed before the first transfer** |

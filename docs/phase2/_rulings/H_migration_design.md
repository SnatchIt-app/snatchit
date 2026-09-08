# H — MINIMUM CORRECT MIGRATION SCOPE FOR VENUE-DIRECT PRIMARY TICKETING

**Agent H · design ruling · 2026-09-02 · read-only pass**
**Repo** `/Users/josetascon/snatchit-consol` · branch `feature/venue-native-and-product-v2`
**Nothing was authored, applied, migrated or committed.** No `.sql` file was created. This document is
the only file written by this pass. Migration 093 does not exist and is not authored here.

**Design inputs taken as GIVEN, not re-litigated:**

> **RULING 1.** Snatch It remains merchant and business of record for venue-direct primary sales.
> Charge model stays separate charges and transfers: no `transfer_data`, no `on_behalf_of`, no
> `application_fee_amount`, no `Stripe-Account` header. Orgs are paid by Transfer at settlement.
>
> **RULING 2.** An org becomes connected to Stripe through a NEW edge function that mints the account
> server-side (Express · US · `business_type=company` · `capabilities[transfers]` only ·
> `metadata[org_id]`) and writes the id back. The caller-supplied `acct_` parameter on the SQL binder
> is eliminated as an input path.

**Owner constraints binding this document, verbatim:** *"Keep 093 as small as safely possible."* ·
*"Do NOT copy Stripe's entire account object into Postgres."*

---

## 0. THE VERDICT, UP FRONT

**ONE migration. Not three.**

Fourteen items are in. Sixteen are moved out and named. The split was tested seriously and fails on
one fact: **no intermediate state is sellable.** A 093/094 boundary would produce a system that can
take real buyer money and has no row saying what the venue is owed — which is precisely the failure
`C_money_ledger_accounting.md §0` and `PRIMARY_TICKETING_OWNER_DECISION_PACKET.md:29-31` exist to
prevent. A migration boundary that cannot be launched from is not a milestone; it is an invitation to
launch from it. Full reasoning at §5.

**The one-sentence description of 093:** it makes a venue-direct ticket *mintable* (payments shape,
signing key, inventory config), makes an org's payee *safe to bind and impossible to sell without*
(two mirror columns, one sync writer, one checkout gate, two hardened binders, two notifications), and
makes the venue's claim *a row* (one pure seam, one `close_settlement` body, two partial unique
indexes, one config key).

**What 093 explicitly does NOT touch:** `venue.finalize_primary_order` — the hottest money function in
the schema, holding the mint, the inventory decrement, the payment link and the attribution resolve
under four locks — is left byte-identical. That is a deliberate and load-bearing minimality result.

---

## 1. METHOD

Every item below is judged on four questions, in this order:

1. **WHY 093** — why it must be a migration at all (i.e. it is DDL, or a row only DDL can write).
2. **WHY NOT EDGE** — why an edge function cannot do it. The decisive form of this argument, over and
   over, is **PostgREST direct reachability**: `venue.create_primary_checkout`, `catalog.publish_event`,
   `kernel.set_org_connect_ref` and `kernel.set_org_payout_destination` are all `grant execute … to
   authenticated` (082:668-700 and the parallel ACL blocks in 077/081/085). A caller reaches them with
   one HTTP request. **An edge function cannot defend a door it does not stand in front of.**
3. **WHY NOT CONFIG** — `catalog.set_platform_config` raises `precondition_failed: unknown_key %` at
   **078:1103** for any key with no seeded row, and its own comment states the rule: *"THIS FUNCTION
   CREATES NO NEW KEY — a key that no code reads is a config row that lies (078 seeds every key)."*
   078 Part 8 seeds exactly 41 keys. `catalog.platform_config` is `revoke all … from public, anon,
   authenticated` (078:235) and PFA-21 left `catalog` untouched for `service_role`. **Every new key is
   therefore a migration, with no exception and no workaround.**
4. **WHY NOT LATER** — why deferral is unsafe; or, where deferral IS safe, that is said plainly and the
   item is moved to §3.

**The standard applied for "safe".** A *safety* failure misstates or loses money, exposes identity, or
writes an irreversible wrong row. A *liveness* failure refuses work that should have succeeded. The
owner's instruction is a safety instruction. **Liveness failures were moved out.** This is why the
`announced → on_sale` gate, the operatorship freeze and the commission-seam raise are all in §3 rather
than §2, and each of those is a judgment I state openly rather than bury.

**A structural fact that drives half the rulings.** `venue.settlement_line` is append-only twice over
(trigger `087:110-112` firing `kernel.raise_append_only()`; `revoke update, delete … from
service_role` at `087:115`) and `venue.settlement`'s four money columns are write-once at close
(`087:334-337`, with a re-close short-circuiting at `087:305-309`). **A settlement closed with a wrong
or missing line can never be corrected in place.** Wherever an item's absence would write a permanently
wrong ledger row, deferral is not an option, and I say so under WHY NOT LATER without hedging.

---

## 2. THE IN SET — 14 ITEMS

### GROUP A — the rail can produce a ticket at all

---

#### I-1 · `public.payments` constrained relaxation + rail-pairing check + seller-policy null-guard

**Shape.** In ONE statement group, in ONE transaction:
`alter table public.payments alter column listing_id drop not null, alter column seller_id drop not
null;` · drop and re-add the `mode` CHECK widened with a native member · `add constraint
payments_rail_pairing_ck check ((listing_id is not null and seller_id is not null and mode in
('buy_now','auction')) or (listing_id is null and seller_id is null and mode = <native member>))` ·
`drop policy "payments: seller select"` and re-create it as `seller_id is not null and seller_id =
auth.uid()`.

**WHY 093.** `listing_id` and `seller_id` are `not null references …` on a frozen `public.*` table
(`000_baseline_schema.sql:973,975`) and `mode` carries a CHECK (`:993`). Dropping a NOT NULL, widening
a CHECK, adding a constraint and replacing an RLS policy are all DDL. There is no runtime path to any
of them.

**WHY NOT EDGE.** A NOT NULL is enforced at the storage wall. An edge function attempting to record a
venue-direct payment is rejected by Postgres before any application logic runs. No amount of edge code
relaxes a column constraint. The only edge-side alternative is to synthesize a sentinel listing and a
sentinel seller — forbidden twice in the governance record, and additionally self-defeating, because
`idx_payments_one_success_per_listing` (`003_payment_integrity.sql:52`) would cap the platform at one
direct sale ever through a shared sentinel.

**WHY NOT CONFIG.** A config key cannot relax a column constraint or replace a policy. No key of any
spelling exists that gates the shape of `public.payments`, and 078:1103 forbids creating one.

**WHY NOT LATER. NOT DEFERRABLE — this is the gate on the entire feature.**
`kernel.payment_native.payment_id` is `uuid not null references public.payments(id)` (`085:42`) and
`venue.finalize_primary_order` refuses to mint unless a `succeeded` `public.payments` row exists,
belongs to the buyer, and covers the order (`085:1919-1934`). The requirement is bolted in twice,
both inside frozen package 085. Without this item **no venue-direct order can ever be finalized** and
nothing else in 093 has any effect. The proof it is load-bearing is already in the repo: the money
pgTAP suite fabricates a fake Miami listing and a fake seller purely to give finalize a payment row.

**Confirmed non-issues, stated so nobody re-opens them.**
`idx_payments_one_success_per_listing` needs no rescoping: it carries no `nulls not distinct` clause,
so every direct row with a NULL `listing_id` is distinct to it. The index stays byte-identical for
resale and becomes an automatic no-op for direct sales. The seller policy's null-guard is a **zero-
semantic-delta documentation act**: `seller_id = auth.uid()` with a NULL `seller_id` already evaluates
NULL, which RLS treats as false, so native payments are already invisible to the seller-side policy —
correctly, because there is no seller. Adding the explicit `is not null` changes no behaviour and does
not change the policy count, which an existing test pins. **No new policy is added and none is needed:**
nothing venue-facing reads `public.payments`, and `kernel.payment_native` is revoked from client roles.

**Atomicity requirement.** The DROP NOT NULLs and the pairing CHECK must land in the same transaction.
Between them, a *resale* row carrying a NULL listing or seller is storable, and twelve live resale-path
sites break — three of them silently (a constraint violation swallowed behind a success response, a
duplicate guard that stops matching, a seller screen that renders blank money with no error). **Do not
use `NOT VALID` + a later `VALIDATE`**: the two-step opens exactly that window, and the table is 56
rows, so there is nothing to buy with it.

---

#### I-2 · The signing-key bootstrap row

**Shape.** One `insert into kernel.signing_key (scope, public_key, kms_handle_ref, status,
not_before) values ('global', <owner-supplied verify key>, <owner-supplied KMS handle>, 'active',
now());` — **no private key material** (C33; the table holds only `public_key` and an opaque
`kms_handle_ref`, `083:56-57`).

**WHY 093.** `kernel.provision_signing_key` is an **unconditional raise** (`083:375-383`:
`dual_control_unavailable — … provisioning is parked, no key is activated`), and so is
`rotate_signing_key` (`083:385-393`). The table is `revoke all … from anon, authenticated`
(`083:111`). There is no other writer anywhere in the schema. A migration INSERT is the only path
short of a superuser session.

**WHY NOT EDGE.** Two independent blocks. (a) The provisioning RPC raises before doing anything, so an
edge caller gets an exception, not a key. (b) `service_role` holds **USAGE ONLY** on the `kernel`
schema (`085:2092-2095`, PFA-21: *"No table/DML grants"*), so an edge function cannot INSERT into
`kernel.signing_key` directly either. Both doors are shut.

**WHY NOT CONFIG.** A signing key is a row in a table with an immutability trigger
(`083:103-105`, `guard_signing_key_immutable`) and three partial unique indexes on `status='active'`
per scope (`083:73-78`). It is not a value; `catalog.platform_config` cannot hold it and
`set_platform_config` cannot create it.

**WHY NOT LATER. NOT DEFERRABLE — nothing exists without it.**
`kernel.tickets.signing_key_id` is `not null` (`079:48`) with an `on delete restrict` FK adopted at
`084:53`, and `kernel.issue_ticket_atoms` raises `precondition_failed: no_active_signing_key` unless an
`active`, in-window, scope-coherent key resolves (`083:514-530`). **You cannot skip the key by skipping
the QR code.** Ticket *existence* requires it.

**Two traps carried forward from the evidence, both real.**
(a) **Do NOT un-park the provisioning RPCs.** They are granted to `authenticated` and are safe only
because they raise first; a naive un-park exposes key provisioning to every signed-in user.
(b) **Key selection is caller-supplied, not preferred.** `kernel.issue_ticket_atoms` reads
`v_key := (p_ctx->>'signing_key_id')::uuid` (`083:479`) and then *validates scope coherence*
(`083:522-527`) — it does not resolve a key by precedence. So a per-event key does not "outrank" the
global one by any mechanism inside the mint; whichever key the caller pins is the one used, provided it
governs the session's scope. **This makes key resolution an obligation of the caller path**
(`venue.finalize_primary_order` passes `'signing_key_id', v_key` at `085:2046`) and it must be verified
before the flag flips, because a wrong key at launch is silent, deferred and permanent: the key is
pinned at mint, rotation never re-pins, revoke is parked, and the FK blocks deletion.

**Owner dependency.** The two values in this INSERT are outputs of the two-person KMS ceremony. **The
migration cannot be authored until the owner signs and supplies them.** This is the only item in 093
with an external human input.

---

#### I-3 · Three config key rows: `inventory.hold_ttl_interval`, `inventory.per_user_active_hold_max`, `ticket.expiry_grace`

**Shape.** Three rows into `catalog.platform_config` at `version 1`, `visibility 'restricted'`,
`value 'null'::jsonb`, `on conflict (key, version) do nothing` — the exact 078 PFA-9 pattern
(*"the ROW exists so set_platform_config's registry precondition holds, the VALUE is absent so every
X-12 consumer takes the RESTRICTIVE reading"*).

**WHY 093.** None of the three appears in 078's 41-key seed block (`078:1524-1580`). All three are
*consumed* — `081:617`, `081:633`, `081:729`, `079:477` — and none is *seeded*. That is the PFA-9
CLASS A shape. 078:1103 refuses to create them.

**WHY NOT EDGE.** An edge function calling `set_platform_config` receives
`precondition_failed: unknown_key`. A direct INSERT is unavailable: `catalog.platform_config` is
`revoke all … from public, anon, authenticated` (`078:235`) and PFA-21 explicitly left `catalog`
untouched for `service_role`.

**WHY NOT CONFIG.** This is the definitional case. Config sets values on keys that already exist; it
cannot bring a key into existence.

**WHY NOT LATER.** Two of the three are hard sale blockers, one is a slower but permanent harm.
- `inventory.hold_ttl_interval` — `venue.reserve_inventory` raises `precondition_failed:
  hold_ttl_unset` when the key is absent (`081:633-637`, and again at `081:729-733`). **Every
  reservation fails closed. There is no checkout at all.**
- `inventory.per_user_active_hold_max` — absent ⇒ `coalesce(v_cap_max, 0)` ⇒ `v_active + 1 > 0` is
  always true ⇒ `precondition_failed: hold_cap_exceeded` on the *first* hold of every user
  (`081:613-626`). **Also a total block, and one that reads like a cap bug rather than a missing key.**
- `ticket.expiry_grace` — the sweep returns `{"swept_count": 0}` while unset (`079:477-485`). Not a
  sale blocker. But a no-show buyer's atom stays `active` forever, the live-custody deletion blocker
  never clears, and that buyer becomes **permanently undeletable** — an erasure-law and App-Store
  failure that needs no money at all to trigger. Deferring the *value* is free; deferring the *row*
  costs a whole second migration to write one line later.

**Separation of concerns, stated so it is not confused.** 093 creates the ROWS. The VALUES are
`set_platform_config` calls after 093 and before the flag flips. Two of the three values (`hold_ttl`,
`hold_max`) are launch-blocking config; the third (`expiry_grace`) is blocking only for deletion.

---

#### I-4 · Column-scope `venue."order"` to omit buyer identity

**Shape.** `revoke select on venue."order" from authenticated;` then
`grant select (order_id, org_id, event_session_id, status, total_minor, currency, created_at,
updated_at, …) on venue."order" to authenticated;` — the full column list minus `buyer_id`. The
precedent is the same column-list grant idiom already used on `kernel.organization` (`077:133`).

**WHY 093.** `grant select on venue."order" to authenticated` (`082:129`) is a table-grain grant.
Narrowing a grant is DDL. There is no runtime narrowing of a column privilege.

**WHY NOT EDGE.** PostgREST exposes `venue."order"` directly to `authenticated` the moment the `venue`
schema is added to the exposed-schema list — which is on the config-after-093 list. No edge function
sits in front of a PostgREST table read. The policies `venue_order_sel_org` (`082:144`) and
`venue_order_sel_venue` (`082:151`) then hand `buyer_id` to org and venue roles, and one join to
`profiles` yields an attendee roster with money attached: no audit row, no rate limit, no consent gate.

**WHY NOT CONFIG.** A config key cannot change a grant, and none exists.

**WHY NOT LATER.** Deferral is *technically* safe today (no orders exist, `venue` is not exposed) but
creates an ordering hazard against a **config** action rather than a migration, which is the worst kind
of dependency to leave dangling: a PostgREST exposure is one dashboard toggle and it silently opens the
hole. The item costs two lines. **Keeping it removes a whole class of "did we remember to do X before
Y" from the launch runbook, which is worth far more than two lines.** I keep it on that basis and state
the reasoning openly rather than claiming an urgency it does not have.

**Confirmed non-issue.** RLS `USING` clauses are not subject to the caller's column privileges, so
`venue_order_sel_owner` (`buyer_id = auth.uid()`, `082:140`) keeps working. The buyer's own read is
unaffected because it is a policy predicate, not a column grant.

---

### GROUP B — an org can hold a payee safely, and cannot sell without one

---

#### I-5 · TWO mirror columns on `kernel.organization` — and only two

**Shape.** `alter table kernel.organization add column connect_transfers_active boolean not null
default false, add column connect_state_synced_at timestamptz;`

`F_org_onboarding.md §3.3` proposes **six**. The owner's instruction is *"Do NOT copy Stripe's entire
account object into Postgres."* Each is judged alone:

| Column | Ruling | Reason |
|---|---|---|
| `connect_transfers_active` | **IN** | The only field with a Postgres-side consumer that cannot make a network call. It is the operand of I-7's gate, which lives inside a `SECURITY DEFINER` SQL function. Load-bearing. |
| `connect_state_synced_at` | **IN** | Not decoration. Without it, `false` cannot be distinguished from *never synced*, and `true` cannot be distinguished from *true six months ago, with a dropped webhook since*. **A gate that cannot tell fresh-true from stale-true is not a safe gate.** One timestamptz is what makes the one boolean trustworthy, and it is the only thing a dead-webhook alert can key on. |
| `connect_payouts_enabled` | **OUT** | F itself rules it *"Not a sale gate"*. Its only consumer is a dashboard warning. No dashboard exists (F P9). |
| `connect_requirements_due` | **OUT** | Consumer is a dashboard banner. No dashboard. |
| `connect_disabled_reason` | **OUT** | Consumer is support triage; support can read Stripe. Not a Postgres gate. |
| `connect_requirements_deadline` | **OUT** | Consumer is a pre-emptive warning banner. No dashboard. |

**The rule that produced this cut is F's own, applied to F:** *"a field with no consumer is a field
that will sit at its default forever, which is exactly what happened to
`profiles.stripe_charges_enabled`."* Four of the six have no Postgres consumer and no shipped UI
consumer. They are the `stripe_charges_enabled` failure being repeated, four times, in advance. They
are re-added in the migration that ships the venue dashboard, when they acquire a reader.

**WHY 093.** `ALTER TABLE … ADD COLUMN` is DDL.

**WHY NOT EDGE.** The consumer is I-7's predicate, evaluated inside `venue.create_primary_checkout` — a
`SECURITY DEFINER` PL/pgSQL function that cannot make a network call. Holding the state only in the
edge means the DB-reachable door is ungated, and that door is `grant execute … to authenticated`
(`082:674,685`).

**WHY NOT CONFIG.** `catalog.platform_config` is platform-global and `platform_admin`-written
(`078:1084-1086`). This is **per-org state authored by Stripe**. Putting a per-org fact in a global key
is a category error, and the webhook carries no `platform_admin` identity with which to write one.

**WHY NOT LATER.** Without the mirror there is no gate; without the gate an org with no working Connect
account can put an event on sale and take buyer money that can never be transferred out. Recovery does
not exist: there is no reserve (`091:13-15`, contractually always empty), no clawback (money spec §9.4),
and no org-scoped receivable (`kernel.identity_obligation.debtor_identity_id` is `not null references
auth.users(id)`, `085:167` — an org id is unstorable).

**Client exposure: none, by construction.** `kernel.organization`'s client grant is the column list
`(org_id, display_name, status)` (`077:133`). New columns are not in that list and are therefore not
readable by `authenticated`. No RLS work is required and none should be added.

**Monotonicity, stated in the migration comment so nobody "fixes" it later.**
`profiles.stripe_onboarding_complete` is deliberately monotonic. **`connect_transfers_active` must be
the opposite: it must be able to return to `false`.** A venue that loses `transfers` must stop selling.

---

#### I-6 · `kernel.sync_org_connect_state(...)` — the service_role-only writer

**Shape.** A new `SECURITY DEFINER … set search_path = ''` function shaped exactly like
`kernel.mark_payout_transfer_state` (`085:1668`): `revoke all … from public, anon, authenticated`,
`grant execute … to service_role` only. Writes `connect_transfers_active` and stamps
`connect_state_synced_at = now()`. **No human path, and none may ever be added.**

**WHY 093.** It is a function. Function creation and its ACL are DDL.

**WHY NOT EDGE.** This is the sharpest case in the document, and it is a *physical* impossibility, not a
design preference: `service_role` holds **USAGE ONLY** on the `kernel` schema (`085:2092-2095`, PFA-21,
verbatim *"No table/DML grants"*). The webhook literally cannot `UPDATE kernel.organization`. It
requires a DEFINER RPC to exist, and only a migration can create one.

**WHY NOT CONFIG.** Not a value.

**WHY NOT LATER.** I-5's columns without I-6's writer are the `stripe_charges_enabled` tombstone in its
pure form — columns that sit at their defaults forever. Worse: `connect_transfers_active` defaults
`false`, so I-7's gate would refuse **every** checkout for **every** org, permanently. **Columns and
writer are one item split across two lines; they ship together or the feature is dead on arrival.**

**Why it cannot be `set_org_connect_ref`.** That function raises when `auth.uid()` is NULL
(`077:962-967`) precisely so it can stamp `payout_destination_set_by` with a real human. A webhook has
no human. The two are correctly separate verbs.

**Refresh discipline for the edge author (not 093's job, but named):** the sync must read a *retrieved*
`Account` by id, never the webhook event's embedded snapshot, per Stripe's own guidance.

---

#### I-7 · The connect-readiness gate in `venue.create_primary_checkout` — G2 only, and UNCONDITIONAL

**Shape.** `CREATE OR REPLACE` of `venue.create_primary_checkout`, adding one precondition beside the
existing `not_on_sale` check (`082:377-379`), where `v_org_id` is already server-derived from the
session's event (`082:369-372`):

```
if not exists (select 1 from kernel.organization o
                where o.org_id = v_org_id
                  and o.stripe_connect_account_ref is not null
                  and o.connect_transfers_active) then
  raise exception 'precondition_failed: payout_not_ready';
end if;
```

**WHY 093.** A precondition inside a `SECURITY DEFINER` PL/pgSQL body. `CREATE OR REPLACE FUNCTION` is
DDL and is the only way to change it.

**WHY NOT EDGE.** `venue.create_primary_checkout(uuid, jsonb, uuid[], text)` is explicitly
`grant execute … to authenticated` (`082:674, 685-686`). It is reachable by one PostgREST call with no
edge in the path. An edge-only gate is bypassed by an HTTP request. `F §3.5` reaches the same
conclusion from the other direction: *"the DB gate is authoritative and the edge must not carry its own
copy of the rule."*

**WHY NOT CONFIG.** A config value cannot install a predicate. And see the next paragraph — I am
deliberately not creating the key F proposes.

**WHY NOT LATER. NOT DEFERRABLE. This is the single gate that protects money.** Without it the sequence
is: org sells → platform holds the cash → settlement closes → `kernel.request_org_payout` raises
`no_payout_destination` (`087:444-446`) → the money sits in the platform balance indefinitely with the
venue owed and unpayable. Every recovery lever the corpus declined to build (reserve, clawback) is
declined precisely because payouts are settlement-cadenced and gated. This is the gate.

**A deliberate departure from `F_org_onboarding.md`, stated openly.** F recommends putting G1/G2 behind
a new `venue.require_connect_for_on_sale` config key so a supervised pilot can relax the gate. **I do
not create that key.** A key whose only function is to switch off the one gate that protects money is
not a minimality win — it is an extra migration item, an extra attack surface, and an ops footgun.
A pilot that wants to sell without a payout destination would need a migration to do it, which is
correct: selling with no payee is the exact condition 093 exists to make impossible. If the owner wants
the escape hatch, it is one row in a later migration and costs nothing to add then.

**The `announced → on_sale` gate (F's G1) is moved out — see §3, O-1.**

---

#### I-8 · `kernel.set_org_connect_ref` — cross-plane refusal, raised attach authority, and the attach notification

**Shape.** Body-only `CREATE OR REPLACE`. Signature unchanged. Four changes:

1. **Cross-plane refusal** (the SQL half of RULING 2): raise `conflict_locked` if
   `p_connect_account_id` appears in `public.profiles.stripe_connect_id` or
   `public.stripe_connect_archive`.
2. **`org_owner` only** — drop `org_finance` from the predicate at `077:967`.
3. **Status narrowed** from `('applied','approved','active')` (`077:980-982`) to
   `('approved','active')`.
4. **`aal2` step-up**, copying `085:1626-1632` verbatim including the `step_up_unavailable` arm for an
   absent claim.
5. Best-effort `security_payout_method_added` emit (see I-9's shared note).

**On "eliminating the caller-supplied `acct_` parameter" — the honest reading.** `CREATE OR REPLACE`
cannot change a parameter list. Removing the parameter means `DROP FUNCTION` + a new signature: a
destructive act on a frozen-package object whose grants are pinned by 077's ACL block and whose
behaviour is pinned by pgTAP at `tests/141:638-649`. **And it would not achieve the goal**, because a
signature change does not stop a hostile caller from supplying an id — it only moves where the id comes
from. The control that actually eliminates the attack is the **cross-plane refusal**, plus the edge's
`metadata[org_id]` verification (which is a Stripe read and cannot be done in SQL at all). So: the SQL
half of RULING 2 is the refusal; the mint-server-side half is the edge function's, and the parameter
stays as the transport for a *server-minted* id. **Stated plainly so the ruling is not recorded as
implemented when only half of it is.**

**WHY 093.** Function body replacement is DDL.

**WHY NOT EDGE.** Decisive. `kernel.set_org_connect_ref` is executable by `authenticated`
(`G_onboarding_security.md §6.4.6`). An `org_finance` — a role any `org_admin` can grant
(`077:1040-1042`) — calls it directly via PostgREST with their own personal seller `acct_`, obtained
free from `create-connect-account:212`. **The new onboarding edge function is walked around, not
through.** This is G-1, ranked *"the single most likely real attack"* with *"Total"* impact: every
settlement payout for that org lands in a personal account, indefinitely, silently.

**WHY NOT CONFIG.** No key gates this verb; 078:1103 forbids creating one; and an authority predicate
is code, not a value.

**WHY NOT LATER. NOT DEFERRABLE the moment an org can be onboarded.** The window opens with the first
org bind and every payout thereafter rides through it. `organization_connect_ref_key` (`077:124-126`)
is a *per-plane* index — it cannot see `public.profiles`, which is exactly G-1's mechanism.

**Two judgment calls inside this item, both stated rather than hidden.**
- **Maturity (72h) is NOT added to attach**, though `G §5.1` recommends it. `org_owner` is granted at
  `kernel.create_organization` time (`077:807-812`), so a maturity floor means every new venue waits
  three days before it can *begin* Stripe onboarding. F's own reasoning applies: *"a first bind risks
  no money, a re-point risks all of it."* The controls that matter at first bind are ownership,
  status and cross-plane — not tenure.
- **`aal2` on attach carries an ops prerequisite.** `set_org_payout_destination` already demands `aal2`
  unconditionally (`085:1626-1632`), so MFA enrolment for org owners must be solved before any
  destination can ever be changed. Adding it to attach brings that dependency forward to onboarding.
  **If org-owner MFA enrolment is not available at launch, drop change (4) and ship (1)(2)(3)(5)** —
  those three alone close G-1 and G-6, and the fallback is stated here so the decision does not have
  to be re-derived under time pressure.

**A useful consequence.** Narrowing the status to `approved`/`active` closes G-6 at source: a payee can
no longer be bound before platform review, which means the probation-clock ageing amplifier
(`087:472-476`, whose operand includes `org.connect_ref.bind`) is largely neutralised. That is why
G-6b is safe to defer (§3, O-6).

---

#### I-9 · `kernel.set_org_payout_destination` — the re-point notification and the org-status gate

**Shape.** Body-only `CREATE OR REPLACE`. Two changes:
1. Refuse when `v_org.status not in ('approved','active')` — a **suspended** org's owner can re-point
   the payee today (`085:1641-1642` has no status check at all).
2. Best-effort `security_payout_destination_changed` emit.

**The notification pattern for both I-8 and I-9.** The type keys are already seeded and mandatory,
push+email, non-muteable: `security_payout_destination_changed` (`092:269`) and
`security_payout_method_added` (`092:270`), with templates at `092:336-339`. The emitter
`notify.emit_event` is `service_role`-executable (`076:343`) and both binders are `SECURITY DEFINER`.
Wrap each in `begin … exception when others then raise warning`, keyed on the `admin_audit` row id —
the exact `change_org_role` precedent at `077:1263-1279` — so a notify failure can never roll back a
bind. Recipients: **every** `org_owner` and `org_finance` of the org, including those who did not act.
Payload carries `{{destination_last4}}` only, **never** the full `acct_` id (Connect ids are barred
from leaving the trust boundary, and the shipped templates already ask only for the last 4).

**WHY 093.** Function body replacement is DDL.

**WHY NOT EDGE.** Same PostgREST reachability. And here it is not merely a bypass, it is *the* bypass:
a tripwire that fires only on the edge path is a tripwire the attacker walks around, since the hostile
re-point (G-3) is precisely a direct RPC call by a compromised `org_owner`. **A detection control the
attacker can route around is not a detection control.**

**WHY NOT CONFIG.** The types and templates are already seeded — what is missing is a *producer*, which
is code. Config cannot produce an event.

**WHY NOT LATER. NOT DEFERRABLE.** G-2 is ranked #2 in `G_onboarding_security.md`, launch-blocking, and
described as *"the single highest value-per-line control in this ruling."* It is the **only** human
tripwire on G-3, and in-DB dual control on the destination is unbuildable without widening a frozen
CHECK (§3, O-15). Since dual control is downgraded, the notification is carrying its load. It cannot
also be deferred.

The status gate rides free in a body already being replaced, and it closes a hole on the single
highest-blast-radius verb in the system: a suspended org is suspended because something is wrong, and
letting it re-point its payee is exactly the wrong direction. Un-suspension is available to
`platform_admin` (`077:897-899`), so nothing is permanently stranded.

---

### GROUP C — the venue's claim becomes a row

---

#### I-10 · The primary revenue-share config KEY (value absent)

**Shape.** One row: `('venue.primary_platform_share_bps', 1, 'null'::jsonb, 'restricted')` — the 078
PFA-9 pattern. Basis points, integer, matching 090's promoter-rate convention and avoiding float
rounding. **The spelling is a proposal; the corpus states no frozen spelling for this key** (no primary
ticketing fee key of any spelling exists — `078:1524-1580`), so the owner names it.

**WHY 093.** 078:1103 — `precondition_failed: unknown_key`. Non-negotiable and mechanical.

**WHY NOT EDGE.** `set_platform_config` refuses; `catalog.platform_config` is revoked from client roles
(`078:235`) and PFA-21 left `catalog` untouched for `service_role`. There is no INSERT path outside a
migration.

**WHY NOT CONFIG.** The definitional case, again.

**WHY NOT LATER. NOT DEFERRABLE, and this is the one place where "later" is genuinely unrecoverable.**
I-11's seam needs a fee operand. If the key does not exist, the seam either invents a rate — which
PFA-30 forbids verbatim (*"Do NOT invent a platform fee rate/key/value, a royalty basis or percentage,
a rounding bearer, fallback percentages, an implicit zero fee or zero royalty"*) — or refuses to line.
If it refuses, a settlement closed in the interim carries **no primary_sale line at all**, and
`venue.settlement_line` is append-only with write-once header money columns: **that settlement can
never be corrected.** The under-recognition is silent and permanent.

**Key row now, value later.** Creating the row with `'null'` invents nothing: the row is the auditable
carrier of the absence, and every X-12 consumer takes the restrictive reading. The owner sets the value
by `set_platform_config` before the first settlement close.

---

#### I-11 · `kernel.settlement_primary_lines(p_settlement_id uuid)` — the third seam, with the refund arm

**Shape.** A new `returns setof kernel.settlement_line_candidate` function, `stable`,
`security definer`, `set search_path = ''`, matching the frozen SEAM-2a contract at `087:204-207`
(*"STABLE, pure, MUST NOT raise (a raise would roll back close_settlement)"*).

Two arms, one function:

- **Revenue arm.** For each eligible order in the settlement's scope, emit
  `('primary_sale', order_id, +venue_proceeds_minor, order.currency, 'organization', settlement.org_id)`.
  `venue_proceeds_minor := total_minor - (total_minor * share_bps) / 10000` using **integer division
  (floor) on the platform's fee**, so the sub-cent residue always falls to the venue and the platform
  can never over-collect by rounding. `is_rounding_bearer` is left at its `false` default, exactly as
  `market_sale` and `promoter_commission` lines do; **C31 rounding-bearer assignment stays deferred**
  and no bearer is invented.
- **Refund arm.** For each `kernel.refund` reaching that scope through
  `kernel.payment_native → venue."order"`, emit `('refund_void', refund_id, -amount_minor, …)`. Using
  `refund_id` (not `order_id`) as `cause_ref` correctly admits multiple partial refunds over time, each
  once.

**Three properties it must have, each with a shipped precedent:**
- **Fail-inert on an absent rate.** If `venue.primary_platform_share_bps` reads NULL, emit **zero
  rows** — never raise, because a raise rolls back the entire close (`087:204-207`). This is the
  X-12 restrictive reading applied to a seam.
- **`NOT EXISTS` pre-filter** over prior lines of the same `(cause, cause_ref)`, under a per-org
  transaction advisory lock — the `090:1519, 090:1536` pattern. The pre-filter is the braces; I-13's
  indexes are the belt.
- **Reuse 090's scope predicate verbatim** (`090:1530-1535`), which already accepts both the
  event-scoped and the venue+period-scoped settlement shapes (`087:47-50`). **Do not invent a second
  scope semantics.**

**A design property worth stating.** Unlike `kernel.settlement_commission_lines` — which is a payout
minter wearing a seam's clothes (`090:1511 → 090:1540 → 090:1483`) and which can raise at `090:1447` —
**this seam is a pure line generator.** It mints nothing, writes nothing, and cannot raise. It restores
the contract 090 broke.

**WHY 093.** A new function is DDL. There is exactly **one** `INSERT INTO venue.settlement_line` in the
whole repository (`087:318`) and it consumes only what the seams return; the seam is the only sanctioned
way to add a line.

**WHY NOT EDGE.** Three reasons, any one sufficient. (a) The line must be inserted inside
`close_settlement`'s transaction, under the header's `FOR UPDATE` (`087:298`), because the four money
columns are derived from the lines present at that instant and are then write-once (`087:329-337`) — a
line inserted afterwards is orphaned by construction, since a re-close short-circuits at
`087:305-309`. (b) It would be a second writer of a ledger the corpus assigns to one path
(`DOMAIN:1102`, R7 money single-path: *"`venue.settlements` … request; they never write money rows"*).
(c) Whether `service_role` even retains INSERT on `venue.settlement_line` is contested —
`C_money_ledger_accounting.md §1.3` reads `087:114-116` as leaving it, while `085:2092-2095` grants
only `USAGE` on the schema — and the answer does not matter, because (a) and (b) both stand regardless.

**WHY NOT CONFIG.** A config value cannot create a candidate producer. The gap is not a disabled branch
or a missing constant: **the producer does not exist.**

**WHY NOT LATER. NOT DEFERRABLE — this is the item the whole exercise is about.**
Today a venue-direct sale produces **zero** ledger facts: `venue."order".status='paid'`
(`085:2056`), a `kernel.payment_native` link (`085:2060-2061`), atoms, and nothing else. The database
cannot answer *"how much do we owe venue X"* — not approximately, not expensively, not at all, because
the obligation has no row. Selling in that state means taking real money reconstructable only from
Stripe history, which is the specific failure the architecture was built to avoid. And the append-only
substrate means every settlement closed in the gap is permanently wrong.

**On the refund arm's inclusion (it is not optional).** One could argue it defers safely, since no
payout executor exists and money cannot actually leave. That argument fails on permanence: a settlement
that closes with the full gross and no refund deduction states a net the platform will later pay, in a
table that cannot be amended. The arm is a handful of lines inside a function being written anyway.
**It ships with the revenue arm or the ledger is born lying.**

---

#### I-12 · `kernel.close_settlement` body replacement — three-seam union and a bare `ON CONFLICT`

**Shape.** Body-only `CREATE OR REPLACE`. Signature and every authority predicate byte-identical. Two
changes:
1. The candidate loop unions **three** seams instead of two (`087:311-312` gains
   `union all select * from kernel.settlement_primary_lines(p_settlement_id)`).
2. `on conflict (settlement_id, cause, cause_ref) do nothing` at `087:320` becomes a **bare
   `on conflict do nothing`**.

**WHY 093.** `CREATE OR REPLACE FUNCTION` is the only way to change a body. Note this is a first:
`close_settlement` has exactly one definition site in the entire repo (`087:289`) and has never been
replaced — 088 and 090 replaced only the two *seam stubs* (`088:319`, `090:1511`). Widening an existing
seam instead would be a semantic lie (a primary sale is not a resale royalty and not a commission), so
a third seam, and therefore a body change, is unavoidable.

**WHY NOT EDGE.** Same as I-11 (a)(b): the union runs inside the close transaction under the header's
`FOR UPDATE`, and the derivation at `087:329-333` is what makes the header equal the sum of its lines.

**WHY NOT CONFIG.** No key selects which seams `close_settlement` unions, and 078:1103 forbids creating
one.

**WHY NOT LATER — AND THE `ON CONFLICT` FIX IS NOT SEPARABLE FROM I-13.** The existing clause is an
**inference specification**: it arbitrates only `settlement_line_cause_uq` (`087:105`). A violation of
a *different* index — I-13's partial uniques — is not caught by it and raises `23505`, aborting the
entire close. So:
- index without body change ⇒ **any second settlement touching an already-lined order aborts the whole
  close**, and the append-only table means the operator cannot delete the offending line to recover;
- body change without index ⇒ **cross-settlement double-lining is storable**, permanently, and the
  venue can be paid twice.

**They must land in the same transaction. This is the tightest ordering dependency in 093.**

---

#### I-13 · Two partial unique indexes on `venue.settlement_line`

**Shape.**
```
create unique index if not exists primary_one_sale_line_ever
  on venue.settlement_line (cause_ref) where cause = 'primary_sale';
create unique index if not exists refund_one_void_line_ever
  on venue.settlement_line (cause_ref) where cause = 'refund_void';
```
Exactly the shape of `attribution_one_commission_line_ever` (`090:214-215`), which is the only
cross-settlement uniqueness guarantee that exists today.

**WHY 093.** `CREATE UNIQUE INDEX` is DDL.

**WHY NOT EDGE.** A uniqueness guarantee cannot be enforced by application code across concurrent
transactions. That is what an index is for, and the pre-filter in I-11 is a race-narrowing optimisation,
not a guarantee.

**WHY NOT CONFIG.** Not a value.

**WHY NOT LATER. NOT DEFERRABLE.** `settlement_line_cause_uq` is scoped `(settlement_id, cause,
cause_ref)` — one line per cause **per settlement**. `venue.settlement` carries **no uniqueness
constraint of any kind** (`087:44-69`), and the schema deliberately supports both an event-scoped and an
overlapping venue+period header (`087:47-50`). **The same order is therefore lineable in two
settlements and payable twice.** The promoter engine had to ship `090:214-215` for exactly this reason;
primary sales have no equivalent. And because the line table is append-only, **the bad line can never be
deleted** — this is a defect with no remediation path, which is the strongest possible case against
deferral.

**Do NOT use `CREATE INDEX CONCURRENTLY`** — it cannot run inside a transaction block, which would break
I-12's atomicity requirement. On an empty table a plain `CREATE UNIQUE INDEX` is instantaneous (§6).

---

#### I-14 · `kernel.settlement_commission_lines` — exclude `partially_refunded`

**Shape.** Body-only `CREATE OR REPLACE` of the 090 seam, adding `'partially_refunded'` to the
terminal-class exclusion set at `090:1537`. One token.

**This item was not on the candidate list. The evidence puts it there.**
`E_refunds_disputes.md §9` defect 1: `partially_refunded` is not in the exclusion set, and by design a
direct-partial `kernel.refund_primary_order` **voids no atoms at all** (`085:571-573`, comment:
*"Direct-partial: money only (voids nothing)"*). So every atom survives, the basis at `090:1466-1473` is
unchanged, and **the promoter is paid full commission on revenue that was partly returned to the
buyer.**

**WHY 093.** Function body replacement is DDL.

**WHY NOT EDGE.** The seam is reachable only from `close_settlement` and asserts its own call stack
(`090:1411-1414`). No edge function can reach inside it, and none should.

**WHY NOT CONFIG.** The exclusion set is a literal in a body, not a key.

**WHY NOT LATER. NOT DEFERRABLE *because 093 activates it.*** Today the defect is inert-ish: commission
payouts are minted `held`/`unfunded_settlement` (`090:1483-1488`) and nothing releases them
(`kernel.release_payout` has zero callers outside pgTAP, and even released there is no contracted
transition to `submitted` for `cause='promoter_commission'`). **But 093 is the migration that makes
`net > 0` reachable for the first time** — it is what turns E-138's Option B from policy into economics.
The first settlements to carry real commissions would carry a knowingly wrong basis, permanently, in an
append-only table, and `kernel.release_payout` would pay it with no re-check of the order's refund state.

**The asymmetry that decides it.** Excluding `partially_refunded` over-corrects: a partially refunded
order pays **no** commission rather than a reduced one. That is a *reversible* error — the attribution
row survives, `attribution_one_commission_line_ever` is not consumed, and a later, correct seam that
recomputes the basis net of the refund can still line it. Under-correcting writes a wrong line that can
**never** be undone. **Restrictive-and-reversible beats permissive-and-permanent.** The over-correction
is accepted and named here so the later fix is a known obligation, not a rediscovery.

---

## 3. THE OUT SET — 16 ITEMS MOVED OUT, AND WHY DEFERRAL IS SAFE

For each: WHY 093 / WHY NOT EDGE / WHY NOT CONFIG are stated where they still apply, and
**WHY NOT LATER is answered "deferral IS safe" with the reason.**

| # | Item | WHY 093 | WHY NOT EDGE | WHY NOT CONFIG | **Deferral is safe because** |
|---|---|---|---|---|---|
| **O-1** | **G1 gate: `announced → on_sale` in `catalog.publish_event`** | Body replacement | Directly PostgREST-reachable | Key would have to be created | **It carries no safety property.** G1 refuses a *state transition*; I-7's G2 refuses the *money*. With G2 alone, an unbacked org can reach `on_sale` and every checkout refuses with `payout_not_ready` — bad operator experience, **zero money risk**. With G1 alone, an org ready at on-sale time that later loses `transfers` keeps selling (F §3.6 relies on G2 for exactly that). G1 costs one extra `CREATE OR REPLACE` of a function 093 otherwise never touches, and costs the same later as now. **Named cost of deferring: a venue can announce a public on-sale that does not work, generating a support call.** |
| **O-2** | **`venue.require_connect_for_on_sale` config key** | 078:1103 | — | — | **Not deferred — declined.** A key whose only function is to switch off the money gate is an attack surface, not a feature. See I-7. Add it in a later migration if the owner wants the pilot escape hatch. |
| **O-3** | **Four of F's six mirror columns** (`connect_payouts_enabled`, `connect_requirements_due`, `connect_disabled_reason`, `connect_requirements_deadline`) | ALTER TABLE | — | Per-org, not global | **No consumer exists.** All four feed a venue dashboard that is not built (F P9). Shipping them now repeats the `stripe_charges_enabled` failure F itself diagnoses — columns that sit at their defaults forever. Add them in the migration that ships their reader. Directly honours *"do not copy the account object."* |
| **O-4** | **Operatorship-transfer freeze** (body-only `catalog.update_venue`) **+ pending-payout assertion** | Body replacement (`078:685-701`) | Directly PostgREST-reachable | *"not a config flag, because the config setter cannot create keys"* | **Money does not follow the venue.** `kernel.payout.payee_org_id` is written from `venue.settlement.org_id`, the org stamped at sale time (`087:341-343`); `venue."order".org_id` and `kernel.tickets.org_id` are likewise stamped. So a transfer cannot redirect a cent. The residual risk is a retained venue-role holder's capabilities over the new operator's venue — real, ranked **P1, not activation-blocking**, requiring a deliberate `platform_admin` act with a mandatory reason code and an audit row, with **zero client callers anywhere**. **Operational condition on this deferral, stated as such: no operatorship transfer may be executed before the freeze lands.** |
| **O-5** | `set_org_payout_destination` `unique_violation` → `conflict_locked` (`085:1647-1653`) | Body replacement | — | — | **The prevention already holds** — `organization_connect_ref_key` (`077:124-126`) blocks the collision. Only the *error contract* is wrong (a raw `23505` instead of a mapped code). No outcome changes. |
| **O-6** | Probation clock from activation, not bind (`087:472-476`) | Body replacement | — | — | **I-8 subsumes most of it.** Narrowing attach status to `approved`/`active` means a payee can no longer be bound while `applied`, which removes the bind-early-and-age-out path. The residual (bind at `approved`, activate later) is narrow and the probation hold still applies to the first payout after any *change*. |
| **O-7** | `payout.destination_cooldown_hours` fail-closed fallback (`085:1650`) | Body replacement | — | — | **The fix is config, not code.** The key already exists at `078:1553` with a `null` value. Setting it to 72 via `set_platform_config` engages the cool-down with no migration at all. The fail-open *fallback* is defence in depth behind org_owner + aal2 + maturity + probation + I-9's notification. **Config action, not a 093 item.** |
| **O-8** | Out-of-band write trigger on `kernel.organization.stripe_connect_account_ref` (G-11) | New trigger | — | — | **Superuser-only threat**, ranked "Recommended", not launch-blocking. A superuser can also drop the trigger. The real control is the CI invariant (audit-coverage over every ref ever held), which is a test, not a migration. |
| **O-9** | Commission seam `raise` → `continue` at `090:1447` | Body replacement | — | — | **This is a liveness failure, not a safety failure.** A malformed attribution aborts a settlement close; the money stays in the platform balance and nothing is lost or misstated. By the standard set in §1, it moves out. **It does escalate after 093** (a blocked close now means a venue cannot be paid), so it is the highest-priority item in this table. |
| **O-10** | Emitting `purchase_confirmed` / `ticket_ready` on the direct rail | Would require replacing `venue.finalize_primary_order` | **The edge CAN do it** — from the webhook's native branch, after finalize returns (the `088:1340` precedent is in-function, but nothing requires that) | — | **This is the one item where WHY NOT EDGE fails, so it does not belong in a migration.** And the cost of doing it in SQL is the worst risk/benefit trade in the set: replacing the function that holds the mint, the inventory decrement, the payment link and the attribution resolve under four locks, in order to add a notification. **Edge work.** |
| **O-11** | Uniqueness on the `venue.settlement` header | New index | — | — | **Redundant given I-13.** With a cross-settlement unique on `primary_sale`/`refund_void` by `cause_ref`, the same order cannot be lined twice however many settlements exist. Adding header uniqueness would also risk breaking the legitimate event-scoped + period-scoped pattern the schema deliberately supports (`087:47-50`). **Accepted residual: overlapping settlement headers remain storable.** |
| **O-12** | Populating `venue.settlement_line.occurred_at` | Would require changing the frozen `kernel.settlement_line_candidate` composite type (`087:26-33`), which two frozen signatures depend on | — | — | **Not minimal, and no new defect.** The column is already NULL for `market_sale` and `promoter_commission`. Leaving it NULL for `primary_sale` is consistent, not a regression. |
| **O-13** | Individual-plane destination write behind a JWT-bound RPC (G-12) | New RPC + rewiring `create-connect-account:216-218,258` | — | — | **Touches the shipped, live resale rail.** G itself says *"schedule it, do not couple it to launch."* Coupling a live-rail change to the venue launch multiplies blast radius for no venue-side benefit. |
| **O-14** | A fee-shaped `cause` member / gross-line representation | Would widen the frozen D3 closed-set CHECK on `venue.settlement_line.cause` (`087:95-98`) | — | — | **A policy question, not a technical one.** I-11 enters the line **net** (venue proceeds), which needs **no** enum change. **Accepted representational loss, stated for the owner:** `fees_minor` will be 0 on a primary-only settlement and platform revenue is representable only by subtraction (`order.total_minor − Σ primary_sale lines`), never as a row. If the owner wants platform revenue as a ledger row, that is a vocabulary widening and a separate ratification. |
| **O-15** | In-DB dual control on a destination change | Would widen `kernel.approval_request`'s frozen `action`/`subject_kind` CHECKs (`077:269-276`, `:299-302`) | — | — | **Unbuildable without a ratification** (the PFA-4 SCOPE OPENED clause). The substitutes ship instead and are genuinely strong: SoD-1 excludes the destination setter from requesting the payout (`087:428-431`) — dual control **at the moment money moves**, which is the moment that matters; destination probation holds the first payout after any change for a `platform_risk` release (`087:465-495`); and I-9's notification. Record as an owner-owed follow-up. |
| **O-16** | The four non-SQL blockers: `refund-execute`, the payout executor + the `source_transaction` question, the webhook's native branch, `kernel.resolve_dispute_native`'s unconditional raise | — | — | — | **No SQL is available or appropriate.** See §7 — these are why 093 is necessary but not sufficient, and they are named there rather than smuggled into a migration. |

---

## 4. THE SPLIT RULING — ONE MIGRATION

### 4.1 The split I tested

The most defensible three-way split, constructed to give each stage a real meaning:

| | Contents | What it independently makes safe | What the system can do after it | What it still cannot do |
|---|---|---|---|---|
| **093** | I-1 payments · I-2 signing key · I-3 config rows · I-4 order column-scope | A ticket can be minted at all; buyer identity is not readable from the order table | Create an order, record a payment, mint atoms, hold inventory | No org can be onboarded safely (G-1 wide open); nothing stops an unbacked org selling; **no row says what the venue is owed** |
| **094** | I-5 columns · I-6 sync writer · I-7 G2 gate · I-8 attach hardening · I-9 re-point controls | An org's payee cannot be a personal account, every bind/re-point announces itself, and no checkout succeeds without a live `transfers` capability | Onboard an org; sell only when the payee is real and fresh | **Still no row says what the venue is owed.** Selling here is C §0's failure with real money in it |
| **095** | I-10 key · I-11 seam · I-12 body · I-13 indexes · I-14 commission basis | The obligation is a row; conservation holds; Option B's funding leg exists | Close a settlement that recognises primary revenue; mint an org payout at a true net | — |

### 4.2 Why I reject it

**1. No intermediate state is sellable, so no boundary is a milestone.** Both 093-alone and 093+094 are
states in which the system can take real buyer money and has no ledger fact for the venue's claim.
That is not a partial launch; it is the exact failure mode the whole architecture exists to prevent.
A boundary you cannot launch from buys nothing operationally.

**2. It invites a partial launch — the single largest risk in this set.** 094 *looks* finished: money
gated, payee safe, notifications firing. A migration boundary there becomes an implicit "this is
enough" signal, and the thing standing between that state and disaster is one config flip of
`feature.native_issuance_enabled`. **One migration removes the affordance entirely.**

**3. It converts an in-file ordering requirement into a cross-migration hazard, and changes the failure
mode from a refusal into an outage.** I-7's predicate reads a column created by I-5. Split across
files, a partial or reordered apply leaves `venue.create_primary_checkout` referencing a column that
does not exist — `42703 undefined_column` on the buyer-facing door. Inside one file that state is
unrepresentable.

**4. Three replay-parity events instead of one.** CI runs a Gate-2 fresh-replay parity check, and the
production ledger must stay 1:1 with the repo. Three migrations is three chances for drift and three
reconciliations for no benefit.

### 4.3 The two honest arguments FOR splitting, and why both dissolve

**Lock profile.** `public.payments` is the only live table touched (I-1). But `ALTER … DROP NOT NULL` is
catalog-only, and the CHECK additions scan 56 rows. Bundling function replacements alongside does not
lengthen the exclusive window meaningfully — `CREATE OR REPLACE FUNCTION` locks a `pg_proc` row, not a
table. **The lock argument does not support a split.**

**Rollback granularity.** One migration means one rollback. The set is asymmetric: the payments
relaxation is reversible (re-add the NOT NULLs, valid only while no direct rows exist), the function
replacements are reversible (restore prior bodies), the config rows are reversible (delete), and the
indexes are reversible (drop). **The single irreversible item is the signing-key row** —
`kernel.tickets.signing_key_id` is `ON DELETE RESTRICT`, so once one atom is minted the key row can
never be deleted. That looks like a case for isolating it. **But its irreversibility is created by the
flag flip, not by the migration:** no atom can be minted until
`feature.native_issuance_enabled` goes true, which is a config act performed last. At the moment 093
lands, the key row is still freely deletable. **The rollback argument dissolves too.**

### 4.4 Ruling

**ONE migration, 093, containing I-1 … I-14.** The items in §3 become a later 094 (or several), and
none of them changes what the system can safely do. The recommended ordering for that follow-up work,
by escalation-after-093: **O-9** (a blocked close now means an unpayable venue) → **O-1** (a public
on-sale that does not work) → **O-4** (P1 authorization residue) → **O-3** (unblocks the dashboard) →
the rest.

---

## 5. ORDERING, ATOMICITY AND WHAT BREAKS OUT OF ORDER

### 5.1 Hard ordering dependencies

| # | Dependency | Direction | Consequence of violating it |
|---|---|---|---|
| **D1** | I-12 body replacement ↔ I-13 indexes | **Atomic — same transaction, neither first** | **Index first:** any second settlement touching an already-lined order raises `23505` inside `close_settlement` (the existing `ON CONFLICT` is an inference spec arbitrating only `settlement_line_cause_uq`) and **aborts the entire close**; the append-only table means the operator cannot delete the line to recover. **Body first:** cross-settlement double-lining is storable and the venue can be paid twice, permanently. |
| **D2** | I-1 `DROP NOT NULL` ↔ I-1 rail-pairing CHECK | **Atomic — same transaction** | A *resale* row with a NULL listing or seller becomes storable. Twelve live resale-path sites break; three fail silently (a swallowed constraint violation behind a success response, a duplicate guard that stops matching, a seller screen rendering blank money). |
| **D3** | I-5 columns → I-6 writer → I-7 predicate | **Strict order, one file** | I-7 before I-5 ⇒ `42703 undefined_column` on **every checkout attempt** — a crash on the buyer-facing door, not a refusal. I-6 before I-5 ⇒ the PL/pgSQL body creates fine (bodies are not catalog-validated at creation) and fails at first webhook call — a dead sync arm that looks healthy. |
| **D4** | I-5 + I-6 ↔ each other | **Same migration** | Columns without the writer = `connect_transfers_active` stuck at `false` forever = I-7 refuses **every** checkout for **every** org. The feature is dead on arrival and looks like a gate bug. |
| **D5** | I-10 key row → first settlement close | **Before any close, guaranteed by same-file** | The seam reads NULL, emits zero rows (correctly, X-12), and the settlement closes at net 0 with no payout. Silent under-recognition, **permanently uncorrectable** in that settlement. |
| **D6** | I-11 seam created → I-12 body references it | Free at creation, ordered for hygiene | PL/pgSQL resolves at execution, so a body pointing at a missing function creates successfully. Create the seam first anyway so a mid-file failure never leaves a live body pointing at nothing. |
| **D7** | I-4 order column-scope → PostgREST exposure of `venue` | **093 before a CONFIG act** | The only dependency in the set that points at a *dashboard toggle* rather than a migration. Exposing `venue` before I-4 hands `buyer_id` to org and venue roles with no audit and no rate limit. |
| **D8** | I-2 signing key row → owner KMS ceremony | **External input before authoring** | 093 cannot be authored until the owner supplies the verify key and the KMS handle. **This is the critical path on 093's calendar.** |

### 5.2 Safe to apply while the rails are dark — essentially all of it

`feature.native_issuance_enabled` is seeded `false` (`078:1522`); `feature.native_resale_enabled` and
`feature.native_scanning_enabled` likewise. Every money-writing function in 085/087/088/090 is
reachable **only from pgTAP** — zero edge callers, zero cron callers of any settlement or payout RPC.
Specifically:

- **I-11 / I-12 (seam + close body):** no settlement header exists in production, so the new arm
  produces zero candidates. **Inert on arrival.**
- **I-13 (indexes):** `venue.settlement_line` is empty in production. A non-concurrent
  `CREATE UNIQUE INDEX` takes `SHARE` (blocking writes, not reads) on a table with no writers —
  instantaneous. Not `CONCURRENTLY`, which cannot run in a transaction block and would break D1.
- **I-3 / I-10 (config rows):** new rows with `on conflict (key, version) do nothing`. Every consumer
  reads `order by version desc limit 1` and treats absent/NULL restrictively. **Zero risk.**
- **I-5 (columns):** `boolean not null default false` and a nullable `timestamptz` are catalog-only on
  PG 11+ — no table rewrite. `kernel.organization` has effectively no production rows (no org has ever
  onboarded). The client grant is a column list that excludes them, so **no client exposure by
  construction.**
- **I-6 / I-7 / I-8 / I-9 / I-12 / I-14 (function replacements):** `CREATE OR REPLACE FUNCTION` takes
  `ACCESS EXCLUSIVE` on the `pg_proc` row only, briefly blocking concurrent calls to that one function.
  Every one of them has zero production callers.
- **I-4 (grant narrowing):** `venue."order"` is empty and unexposed.
- **I-2 (key row):** a single INSERT into an empty table.

### 5.3 The one lock that matters

**`public.payments` — the only LIVE table in the whole set.** The resale rail writes to it constantly
(`create-payment-intent`, `stripe-webhook`, `enforce-transfer-expiry`).

- `ALTER TABLE public.payments ALTER COLUMN listing_id DROP NOT NULL` (and `seller_id`) —
  `ACCESS EXCLUSIVE`, catalog-only, instant.
- `DROP CONSTRAINT` on the `mode` CHECK, then `ADD CONSTRAINT` — the ADD full-scans under
  `ACCESS EXCLUSIVE`. 56 rows.
- `ADD CONSTRAINT payments_rail_pairing_ck` — same.

**Total exclusive window: milliseconds.** But the lock is exclusive and will **queue every in-flight
resale payment write behind it** if it has to wait for a long-running transaction to clear.

**Recommendation: `set local lock_timeout = '3s'` for the transaction** so the migration fails fast and
is retried, rather than queueing behind a slow reader and stalling live payment writes for the duration.
This is the only operational precaution 093 requires.

**Explicitly rejected:** `ADD CONSTRAINT … NOT VALID` followed by a later `VALIDATE CONSTRAINT`. It is
the standard large-table technique and it is **wrong here**, because it opens exactly the window D2
forbids, and buys nothing on 56 rows.

---

## 6. WHAT 093 MAKES TRUE — AND WHAT IT DOES NOT

### 6.1 True after 093 + the config actions + the edge work

- A venue-direct order can be created, paid, finalized, and can mint real ticket atoms against a real
  signing key.
- An org can be onboarded to Stripe through the new edge function, and **cannot** bind a personal seller
  account, **cannot** bind before platform review, and **cannot** bind or re-point without every
  `org_owner` and `org_finance` being told.
- **No checkout succeeds for an org whose `transfers` capability is not live**, enforced at the database
  door that PostgREST exposes, not at an edge that can be walked around.
- The venue's claim is a **row**: signed, append-only, conserved by
  `settlement_waterfall_ck`, and provably equal to the sum of its lines within a settlement.
- The same order can never be lined in two settlements. A refund reduces the next settlement. A
  partially refunded order no longer over-pays a promoter.
- **Two dead code paths in 088 come alive as a side effect and should be tested as such:** the
  chargeback→settlement producer (`088:351-359`) finally posts against a real gross instead of a
  structural zero, and the dispute payout-freeze leg (`088:842-844`), which joins
  `settlement_line.cause_ref` to a primary `order_id`, stops being dead code.
- **E-138 / Option B's funding leg exists.** Commission becomes an economic deduction from real primary
  revenue before the org payout is minted at `v_net` — a literal, one-for-one implementation of
  `primary ticket revenue → promoter commission liability → venue distributable settlement`.

### 6.2 NOT true after 093 — and these are not SQL problems

State these plainly; they are the difference between "the obligation is recordable" and "the obligation
is payable", and between "we can sell" and "we should sell".

1. **No venue can actually be PAID.** `kernel.payout` rows are minted `pending` and nothing advances
   them: `mark_payout_transfer_state` has zero callers, and **the `source_transaction` question is
   unresolved on paper** — one settlement payout has many funding charges, Stripe accepts one
   `source_transaction`, and `kernel.payout.source_transaction_ref` (`085:134`) has never been written
   by any shipped function. **This must be settled on paper before the payout executor is written.**
   093 makes the obligation *recordable*, not *payable*.
2. **No buyer can actually be REFUNDED.** `refund-execute` does not exist; every `kernel.refund` row is
   born `pending` with no reachable transition out — while `venue."order"` is moved to
   `refunded`/`partially_refunded` and the atoms are **voided** in the same transaction. **The buyer
   loses the ticket and does not get the money.** This is the most dangerous property in the current
   build, it is model-independent, and no migration fixes it. **Refund executability is a hard
   precondition of selling direct tickets.**
3. **Nothing opens a settlement automatically.** It is a manual finance action. An org can sell for
   months with no settlement ever opened and no line ever written. **The orphan sweep is a required
   monitoring artefact, not a migration:** `select o.order_id … from venue."order" o where o.status in
   ('paid','partially_refunded') and not exists (select 1 from venue.settlement_line l where l.cause =
   'primary_sale' and l.cause_ref = o.order_id)`. The index it needs already exists
   (`settlement_line_cause_ref_idx`, `087:108`).
4. **A lost dispute never resolves.** `kernel.resolve_dispute_native` always raises
   (`088:944-946`) — the payout stays held forever and the atoms stay in `dispute_hold` forever. Safe
   for the platform's money, bad for a venue's operations, and unbuildable without widening a frozen
   CHECK.
5. **Scenario 5 (chargeback after the venue is paid) is unrecoverable** under this charge model as
   specified — money spec §9.4 forbids a clawback, `reverse_transfer` has zero hits repo-wide, and the
   only named alternative (netting via the `chargeback` line) now at least has a positive side to net
   against, which 093 creates. That is an improvement, not a solution.
6. **The webhook's native branch does not exist.** The current webhook returns a non-success status for
   an unknown mode, so a native charge would **retry for days** until that branch is written.

### 6.3 The config actions 093 enables but does not perform

`inventory.hold_ttl_interval` · `inventory.per_user_active_hold_max` · `ticket.expiry_grace` ·
`venue.primary_platform_share_bps` · `payout.destination_cooldown_hours` (= 72; the key already exists
at `078:1553`) · the refund window (= zero) · PostgREST exposure of `venue` and `catalog` (**after**
I-4) · and **last, after everything else is verified**, `feature.native_issuance_enabled`.

---

## 7. THE 093 MANIFEST

| # | Item | Object | DDL kind |
|---|---|---|---|
| I-1 | payments relaxation + rail-pairing check + seller-policy null-guard | `public.payments` | ALTER TABLE ×3, DROP/CREATE POLICY |
| I-2 | signing-key bootstrap row | `kernel.signing_key` | INSERT |
| I-3 | three config key rows | `catalog.platform_config` | INSERT |
| I-4 | column-scoped order grant | `venue."order"` | REVOKE + GRANT |
| I-5 | two mirror columns | `kernel.organization` | ALTER TABLE |
| I-6 | `kernel.sync_org_connect_state` | new function | CREATE FUNCTION + ACL |
| I-7 | G2 connect-readiness gate | `venue.create_primary_checkout` | CREATE OR REPLACE |
| I-8 | cross-plane refusal + attach authority + attach notify | `kernel.set_org_connect_ref` | CREATE OR REPLACE |
| I-9 | re-point notify + org-status gate | `kernel.set_org_payout_destination` | CREATE OR REPLACE |
| I-10 | revenue-share key row (value null) | `catalog.platform_config` | INSERT |
| I-11 | `kernel.settlement_primary_lines` (revenue + refund arms) | new function | CREATE FUNCTION + ACL |
| I-12 | three-seam union + bare `ON CONFLICT` | `kernel.close_settlement` | CREATE OR REPLACE |
| I-13 | two partial unique indexes | `venue.settlement_line` | CREATE UNIQUE INDEX ×2 |
| I-14 | exclude `partially_refunded` | `kernel.settlement_commission_lines` | CREATE OR REPLACE |

**New tables: 0. New columns: 2. New enum members: 0. New RLS policies: 0. Money-ledger DDL: 0.
`venue.finalize_primary_order`: untouched. Files 076–092: unmodified.**

---

*Prepared by Agent H. Read-only pass. No migration authored, no `.sql` file written, nothing applied,
nothing committed, no production or remote access. This document is the only file created.*
